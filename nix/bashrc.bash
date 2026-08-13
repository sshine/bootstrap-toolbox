# .bashrc for bootstrap-toolbox
#
# Installed as /etc/bashrc, which is where nixpkgs' bash looks for a system-wide
# rc file in interactive shells, and where /etc/profile sends login shells.

# Non-interactive shells (`bash -lc ...`) want none of this.
case $- in
*i*) ;;
*) return ;;
esac

# There is no /usr in this image; buildEnv merges every package's share/ into
# /share. Sourcing bash_completion from there is also what aims its lazy loader
# at the merged completions directory, so git, helm, ssh and friends complete
# without being listed here one by one.
# shellcheck source=/dev/null
if ! shopt -oq posix && [ -r /share/bash-completion/bash_completion ]; then
  . /share/bash-completion/bash_completion
fi

alias k=kubectl
# shellcheck source=/dev/null
source <(kubectl completion bash)
# The lazy loader is never asked about `k`, so hand it kubectl's completion.
eval "$(complete -p kubectl | sed 's/kubectl$/k/')"

# just ships no static completion file, only a generator.
# shellcheck source=/dev/null
source <(just --completions bash)

alias gs='git status'
alias gl='git log'
alias gap='git add -p'
alias gd='git diff'
alias gdc='git diff --cached'
alias gpr='git pull --rebase --prune'

# In-cluster kubectl authenticates from the service account and has no context,
# so the segment carries its own separator and collapses away when empty.
__kube_prompt() {
  local out ctx ns
  out=$(kubectl config view --minify -o jsonpath='{.current-context}{"\n"}{..namespace}' 2>/dev/null) || return
  ctx=${out%%$'\n'*}
  ns=${out#*$'\n'}
  [ -n "$ctx" ] || return
  local G=$'\001\033[01;32m\002' R=$'\001\033[00m\002'
  echo " : ${G}${ctx}${R}:${G}${ns:-default}${R}"
}
PS1='[\[\033[01;32m\]\u\[\033[00m\]$(__kube_prompt) : \[\033[01;32m\]\w\[\033[00m\]] \$ '

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=100000
HISTFILESIZE=100000
HISTCONTROL=ignoreboth
HISTTIMEFORMAT='%F %T '
PROMPT_COMMAND="history -a; history -n${PROMPT_COMMAND:+; $PROMPT_COMMAND}"

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
shopt -s globstar
