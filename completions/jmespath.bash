# Bash 3.2 completion for both executable names. Source this file to register it.
# Rejoin Readline word-break fragments only when they are adjacent in the input.
_jmespath_completion_words() {
  local remaining=${COMP_LINE:0:COMP_POINT} piece joined= index
  for ((index = COMP_CWORD; index >= 0; index--)); do
    piece=${COMP_WORDS[index]}
    if ((index == COMP_CWORD)); then
      while [[ $remaining != *"$piece" ]]; do piece=${piece%?}; done
    fi
    joined=$piece$joined
    remaining=${remaining%"$piece"}
    if ((index == 0)) || [[ $remaining == *[[:space:]] ]]; then
      words=("$joined" "${words[@]}")
      joined=
      while [[ $remaining == *[[:space:]] ]]; do
        remaining=${remaining%?}
      done
    fi
  done
}

# Decode quoting and HOME references without evaluating filename text.
_jmespath_completion_unquote() {
  local text=$1 character next quote= escape decoded digits skip_ansi=0
  REPLY=
  while [[ -n $text ]]; do
    character=${text:0:1}
    text=${text:1}
    if [[ $quote == ansi ]]; then
      if [[ $character == "'" ]]; then
        quote=
      elif [[ $character == \\ ]]; then
        next=${text:0:1}
        text=${text:1}
        ((skip_ansi)) && continue
        escape=\\$next
        case $next in
          [0-7])
            digits=$next
            while ((${#digits} < 3)) && [[ $text == [0-7]* ]]; do
              digits+=${text:0:1}; text=${text:1}
            done
            escape=\\0$digits ;;
          x)
            digits=
            while ((${#digits} < 2)) && [[ $text == [[:xdigit:]]* ]]; do
              digits+=${text:0:1}; text=${text:1}
            done
            if [[ -z $digits ]]; then REPLY+='\x'; continue; fi
            escape=\\x$digits ;;
          c)
            next=${text:0:1}; text=${text:1}
            printf -v digits '%d' "'$next"
            printf -v escape '\\%03o' "$((digits & 31))" ;;
          "'"|'"'|'?') escape=$next ;;
        esac
        printf -v decoded '%b' "$escape"
        REPLY+=$decoded
        [[ -z $decoded ]] && skip_ansi=1
      elif ((!skip_ansi)); then
        REPLY+=$character
      fi
    elif [[ $quote == "'" ]]; then
      if [[ $character == "'" ]]; then quote=; else REPLY+=$character; fi
    elif [[ $character == \\ ]]; then
      next=${text:0:1}
      if [[ $quote == '"' && $next != [\$\`\"\\] && $next != $'\n' ]]; then
        REPLY+=$character
      else
        text=${text:1}
        [[ $next != $'\n' ]] && REPLY+=$next
      fi
    elif [[ $character == '$' && -z $quote && $text == "'"* ]]; then
      quote=ansi
      skip_ansi=0
      text=${text:1}
    elif [[ $character == '$' && ( $text == HOME || $text == HOME[/\"]* ) ]]; then
      REPLY+=$HOME
      text=${text#HOME}
    elif [[ $character == '$' && $text == '{HOME}'* ]]; then
      REPLY+=$HOME
      text=${text#'{HOME}'}
    elif [[ $character == "'" || $character == '"' ]]; then
      if [[ $quote == "$character" ]]; then
        quote=
      elif [[ -z $quote ]]; then
        quote=$character
      else
        REPLY+=$character
      fi
    else
      REPLY+=$character
    fi
  done
  unclosed_quote=$quote
}

_jmespath_completion() {
  local -a words=()
  local current word candidate prefix REPLY unclosed_quote raw_path option=
  local index expecting_path=0 expand_home=0
  _jmespath_completion_words
  current=${words[${#words[@]}-1]}
  COMPREPLY=()

  if ((${#words[@]} > 2)); then
    _jmespath_completion_unquote "${words[1]}"
    case $REPLY in
      --help|-h)
        ((${#words[@]} == 3)) || return
        _jmespath_completion_unquote "$current"
        while IFS= read -r candidate; do
          COMPREPLY[${#COMPREPLY[@]}]=$candidate
        done < <(compgen -W 'input output validate functions interactive' -- "$REPLY")
        return ;;
    esac
  fi

  for ((index = 1; index < ${#words[@]} - 1; index++)); do
    _jmespath_completion_unquote "${words[index]}"
    word=$REPLY
    if ((expecting_path)); then
      expecting_path=0
      continue
    fi
    case $word in
      --file|--query-file) expecting_path=1 ;;
      --) return ;;
    esac
  done

  raw_path=$current
  if ((!expecting_path)); then
    if [[ $current == *=* ]]; then
      _jmespath_completion_unquote "${current%%=*}"
      case $REPLY in
        --file|--query-file)
          expecting_path=1
          option=$REPLY=
          raw_path=${current#*=}
          [[ -n $unclosed_quote ]] && raw_path= ;;
      esac
    fi
  fi

  if ((expecting_path)); then
    case $raw_path in
      '~'|'~/'*) expand_home=1 ;;
      '~'*) return ;;
    esac
    # Readline replaces only the suffix after its last unquoted word break.
    _jmespath_completion_unquote "${current%"${2-}"}"
    prefix=$REPLY
    _jmespath_completion_unquote "$current"
    current=$REPLY
    if [[ -n $option ]]; then
      current=${current#"$option"}
      if [[ $prefix == "$option"* ]]; then
        prefix=${prefix#"$option"}
        option=
      fi
    fi
    if ((expand_home)); then
      current=$HOME${current#\~}
      [[ $prefix == '~'* ]] && prefix=$HOME${prefix#\~}
    elif [[ $current == '~'* ]]; then
      # A quoted or escaped tilde must stay literal when Readline rewrites it.
      current=./$current
      [[ -n $prefix ]] && prefix=./$prefix
    fi
    while IFS= read -r -d '' candidate; do
      COMPREPLY[${#COMPREPLY[@]}]=$option${candidate#"$prefix"}
    done < <(
      shopt -s nullglob
      shopt -u failglob
      for candidate in "$current"*; do printf '%s\0' "$candidate"; done
    )
    # Enable Readline filename quoting only for paths, including on Bash 3.2.
    if type compopt >/dev/null 2>&1; then
      compopt -o filenames
    else
      compgen -f -- "$current" >/dev/null || :
    fi
  elif [[ $current == -* ]]; then
    while IFS= read -r candidate; do
      COMPREPLY[${#COMPREPLY[@]}]=$candidate
    done < <(compgen -W '-h --help --version --functions --file --query-file --validate --pretty --raw-output --json-lines --interactive' -- "$current")
  fi
}

complete -F _jmespath_completion jmespath jmespath.rb
