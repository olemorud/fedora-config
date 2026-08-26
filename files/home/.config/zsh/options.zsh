setopt interactivecomments  # allow comments in interactive mode
setopt magicequalsubst      # filename expansion for foo=~/bar arguments
setopt nonomatch            # pass unmatched globs through instead of erroring
setopt notify               # report background job status immediately
setopt numericglobsort      # sort filenames numerically when it makes sense
setopt promptsubst          # command substitution in prompt
setopt print_exit_value     # print non-zero exit codes

WORDCHARS=${WORDCHARS//\/}  # treat / as a word boundary
PROMPT_EOL_MARK=""          # hide the % shown after output without newline

# Completion
autoload -Uz compinit
compinit -d ~/.cache/zcompdump
zstyle ':completion:*:*:*:*:*' menu select
zstyle ':completion:*' auto-description 'specify: %d'
zstyle ':completion:*' completer _expand _complete
zstyle ':completion:*' format 'Completing %d'
zstyle ':completion:*' group-name ''
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' list-prompt \
    '%SAt %p: Hit TAB for more, or the character to insert%s'
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
zstyle ':completion:*' rehash true
zstyle ':completion:*' select-prompt \
    '%SScrolling active: current selection at %p%s'
zstyle ':completion:*' use-compctl false
zstyle ':completion:*' verbose true
zstyle ':completion:*:kill:*' command 'ps -u $USER -o pid,%cpu,tty,cputime,cmd'
zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#)*=0=01;31'

# History
HISTFILE=~/.zsh_history
HISTSIZE=20000
SAVEHIST=20000
setopt hist_expire_dups_first  # drop duplicates first when trimming
setopt hist_ignore_dups        # skip consecutive duplicates
setopt hist_ignore_space       # skip commands starting with a space
setopt hist_verify             # expand history before running it
setopt share_history           # share history between sessions

# time(1) output format
TIMEFMT=$'\nreal\t%E\nuser\t%U\nsys\t%S\ncpu\t%P'

# Keys
bindkey "^[[H" beginning-of-line
bindkey "^[[F" end-of-line
bindkey "^[[3~" delete-char
