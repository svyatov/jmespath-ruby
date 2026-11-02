# Bash 3.2 completion for both executable names. Source this file to register it.
_jmespath_completion() {
  local current=${COMP_WORDS[COMP_CWORD]} word candidate
  local index expecting_path=0
  COMPREPLY=()

  for ((index = 1; index < COMP_CWORD; index++)); do
    word=${COMP_WORDS[index]}
    if ((expecting_path)); then
      # Readline splits equals values into separate words by default.
      [[ $word == = ]] && continue
      expecting_path=0
      continue
    fi
    case $word in
      --file|--query-file) expecting_path=1 ;;
      --) return ;;
    esac
  done

  case $current in
    --file=*|--query-file=*)
      expecting_path=1
      current=${current#*=}
      ;;
  esac

  if ((expecting_path)); then
    [[ $current == = ]] && current=
    while IFS= read -r candidate; do
      COMPREPLY[${#COMPREPLY[@]}]=$candidate
    done < <(compgen -f -- "$current")
  elif [[ $current == -* ]]; then
    while IFS= read -r candidate; do
      COMPREPLY[${#COMPREPLY[@]}]=$candidate
    done < <(compgen -W '-h --help --version --functions --file --query-file --validate --pretty --raw-output --json-lines' -- "$current")
  fi
}

complete -o filenames -F _jmespath_completion jmespath jmespath.rb
