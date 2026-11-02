# frozen_string_literal: true

# Clean shell startup and completion observation widgets.
module ShellCompletion
  BASH = <<~'SHELL'
    if [[ $PROBE_ACCEPT_ARGUMENTS == 1 ]]; then
    jmespath() {
      printf '%s\0' "$@" > "$PROBE_RESULT"
      printf '__CAPTURED__'
    }
    jmespath.rb() { jmespath "$@"; }
    fi
    source "$PROBE_ROOT/completions/jmespath.bash"
    definition=$(declare -f _jmespath_completion)
    eval "${definition/_jmespath_completion/_probe_original}"
    _jmespath_completion() {
      _probe_original "$@"
      printf '%s\0' "${COMPREPLY[@]}" > "$PROBE_CANDIDATES"
      [[ $PROBE_CANDIDATES_ONLY == 1 ]] && printf '__CAPTURED__'
    }
    _probe_capture() {
      local entry
      entry=$(builtin history 1)
      [[ $entry == *'#'* ]] || return
      printf '%s' "${entry#*#}" > "$PROBE_RESULT"
      printf '__CAPTURED__'
    }
    HISTFILE=/dev/null
    HISTCONTROL=
    HISTIGNORE=
    set -o history
    PROMPT_COMMAND=_probe_capture
    bind '"\C-x\C-g": "\C-a#\C-e\n"'
    bind '"\C-b": backward-char'
    PS1='__READY__'
  SHELL
  ZSH = <<~'SHELL'
    if [[ $PROBE_ACCEPT_ARGUMENTS == 1 ]]; then
    jmespath() {
      printf '%s\0' "$@" > "$PROBE_RESULT"
      printf '__CAPTURED__'
    }
    jmespath.rb() { jmespath "$@"; }
    fi
    fpath=("$PROBE_ROOT/completions" $fpath)
    autoload -Uz compinit
    compinit -D -i
    compadd() {
      local -a probe_matches
      builtin compadd -A probe_matches "$@"
      printf '%s\0' "${probe_matches[@]}" >> "$PROBE_CANDIDATES"
      builtin compadd "$@"
    }
    _probe_capture() {
      print -rn -- "$BUFFER" > "$PROBE_RESULT"
      print -rn -- '__CAPTURED__'
    }
    zle -N _probe_capture
    bindkey -e
    bindkey '^X^G' _probe_capture
    _probe_complete() {
      zle complete-word
      [[ $PROBE_CANDIDATES_ONLY == 1 ]] && print -rn -- '__CAPTURED__'
    }
    zle -N _probe_complete
    bindkey '^I' _probe_complete
    PS1='__READY__'
  SHELL
end
