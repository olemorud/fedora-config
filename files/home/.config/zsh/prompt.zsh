autoload -Uz add-zsh-hook vcs_info

zstyle ':vcs_info:*' enable git
zstyle ':vcs_info:git:*' check-for-changes true
zstyle ':vcs_info:git:*' stagedstr '+'
zstyle ':vcs_info:git:*' unstagedstr '!'
zstyle ':vcs_info:git:*' formats '(%s %b%u%c)'
zstyle ':vcs_info:git:*' actionformats '(%s %b%u%c %a)'

add-zsh-hook precmd vcs_info

# Blank line between commands
_prompt_newline() { print "" }
add-zsh-hook precmd _prompt_newline

# ternary example: "%(?.A.B)" where ? is the previous exit status
PROMPT='%F{240} [%T] %~ ${vcs_info_msg_0_}
$%f '
