# LC_COLLATE=C: case-sensitive sort, i.e. README before aaa.py
alias ls='LC_COLLATE=C ls --color=auto --group-directories-first'
alias ll='ls -la'
alias la='ls -A'
alias l='ls -CF'

alias xo='xdg-open'

alias history='history 0'  # show the complete history

# vimx is vim built with +clipboard (from vim-X11)
command -v vimx >/dev/null && alias vim='vimx'

# Create a directory and cd into it
take() {
    if [ -z "$1" ]; then
        printf 'usage: take <directory>\n' >&2
        return 1
    fi
    mkdir -p "$1" && cd "$1" || return
}

# gd: encrypted, compressed file storage on Google Drive via rclone.
# Requires an rclone remote named "gdrive".

gd-auth() {
    rclone lsd gdrive: >/dev/null 2>&1 || {
        print -u2 'Google Drive auth failed;' \
            'try: rclone config reconnect gdrive:'
        return 1
    }
}

gd-check() {
    local missing=()
    for cmd in rclone zstd gpg; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    (( ${#missing[@]} == 0 )) || {
        print -u2 "Missing dependencies: ${missing[*]}"
        return 1
    }
    gd-auth
}

# Compress, encrypt and upload a file or directory
gd-push() {
    gd-check || return
    tar cf - "$1" \
        | zstd -6 \
        | gpg -c -z 0 -o - \
        | rclone rcat "gdrive:rclone/${1:t}.tar.zst.gpg"
}

# Download, decrypt and extract into the current directory
gd-pull() {
    gd-check || return
    rclone cat "gdrive:rclone/${1:t}.tar.zst.gpg" \
        | gpg -d \
        | zstd -d -c \
        | tar xf -
}

# List stored files
gd-ls() {
    gd-check || return
    rclone lsf --files-only gdrive:rclone/ \
        | sed -n 's/\.tar\.zst\.gpg$//p'
}

# Remove a stored file
gd-rm() {
    gd-check || return
    rclone deletefile "gdrive:rclone/${1:t}.tar.zst.gpg"
}

gd() {
    local command="$1"
    shift 2>/dev/null || true

    case "$command" in
        push)  gd-push "$@" ;;
        pull)  gd-pull "$@" ;;
        ls)    gd-ls "$@" ;;
        rm)    gd-rm "$@" ;;
        check) gd-check "$@" ;;
        auth)  gd-auth "$@" ;;
        "")
            print -u2 'usage: gd <command> [args]'
            print -u2 ''
            print -u2 'commands:'
            print -u2 '  push <path>   Compress, encrypt and upload'
            print -u2 '  pull <path>   Download, decrypt and extract'
            print -u2 '  ls            List stored files'
            print -u2 '  rm <path>     Remove a stored file'
            print -u2 '  check         Check dependencies and authentication'
            print -u2 '  auth          Check Google Drive authentication'
            return 2
            ;;
        *)
            print -u2 "gd: unknown command: $command"
            print -u2 'usage: gd {push|pull|ls|rm|check|auth} ...'
            return 2
            ;;
    esac
}
