# Interactive zsh config. The actual content lives in ~/.config/zsh.
ZSH_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"

source "$ZSH_CONFIG/options.zsh"
source "$ZSH_CONFIG/aliases.zsh"
source "$ZSH_CONFIG/prompt.zsh"
