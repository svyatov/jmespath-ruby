# Bash 3.2 completion for both executable names. Source this file to register it.
# Rejoin Readline word-break fragments only when they are adjacent in the input.
_jmespath_completion_words() {
  local remaining=${COMP_LINE:0:COMP_POINT} piece joined= index
  for ((index = COMP_CWORD; index >= 0; index--)); do
    piece=${COMP_WORDS[index]}
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

# Decode shell quoting without evaluating filename text.
_jmespath_completion_unquote() {
  local text=$1 character next quote=
  REPLY=
  while [[ -n $text ]]; do
    character=${text:0:1}
    text=${text:1}
    if [[ $quote == "'" ]]; then
      if [[ $character == "'" ]]; then quote=; else REPLY+=$character; fi
    elif [[ $character == \\ ]]; then
      next=${text:0:1}
      if [[ $quote == '"' && $next != [\$\`\"\\] && $next != $'\n' ]]; then
        REPLY+=$character
      else
        text=${text:1}
        [[ $next != $'\n' ]] && REPLY+=$next
      fi
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
}

_jmespath_completion() {
  local -a words=()
  local current word candidate prefix REPLY
  local index expecting_path=0
  _jmespath_completion_words
  current=${words[${#words[@]}-1]}
  COMPREPLY=()

  for ((index = 1; index < ${#words[@]} - 1; index++)); do
    word=${words[index]}
    if ((expecting_path)); then
      expecting_path=0
      continue
    fi
    case $word in
      --file|--query-file) expecting_path=1 ;;
      --) return ;;
    esac
  done

  if ((!expecting_path)); then
    case $current in
      --file=*|--query-file=*) expecting_path=1; current=${current#*=} ;;
    esac
  fi

  if ((expecting_path)); then
    # Readline replaces only the suffix after its last unquoted word break.
    _jmespath_completion_unquote "${current%"${2-}"}"
    prefix=$REPLY
    _jmespath_completion_unquote "$current"
    current=$REPLY
    while IFS= read -r -d '' candidate; do
      COMPREPLY[${#COMPREPLY[@]}]=${candidate#"$prefix"}
    done < <(
      shopt -s nullglob
      shopt -u failglob
      for candidate in "$current"*; do printf '%s\0' "$candidate"; done
    )
    # Enable Readline filename quoting only for paths, including on Bash 3.2.
    compgen -f -- "$current" >/dev/null || :
  elif [[ $current == -* ]]; then
    while IFS= read -r candidate; do
      COMPREPLY[${#COMPREPLY[@]}]=$candidate
    done < <(compgen -W '-h --help --version --functions --file --query-file --validate --pretty --raw-output --json-lines' -- "$current")
  fi
}

complete -F _jmespath_completion jmespath jmespath.rb
