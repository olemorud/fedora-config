# Dotfiles

Vendored from github.com/olemorud/dotfiles into `files/home/`, cleaned
up. Nothing is cloned at run time.

## Dropped

- `air.css`: stylesheet for an `m` command that no longer exists.
- `.gitignore`, `.vim/colors/.melange.vim.swp`, `.gitkeep` files: repo
  housekeeping and an editor swap file.
- `alias pacman`: Arch only.
- `.vim/colors/melange_modified.vim`: merged into `melange.vim`.
- All vim plugins (vim-plug, vim-lsp, asyncomplete, bufferline, codeium)
  and the mappings that depended on them.

## Fixed

### .gitconfig

- `lola` alias contained a literal `\n` in the middle of the command.
- `signingkey` was an absolute `/home/ole/...` path; now `~/.ssh/...`.
- `credential.helper = manager-core` is not packaged on Fedora; replaced
  with `libsecret` (package `git-credential-libsecret`).
- `core.editor = vim --clean` was a workaround for netrw opening on every
  start. The vimrc now only opens netrw when started without a file, so
  the editor is plain `vim`.
- Removed `color.*` and `push.default` (defaults since git 2.0).
- Mixed tabs and spaces.

### zsh

- `.zshrc` sourced `$HOME/zsh/*` unquoted with an awk shebang trick.
  Now sources `~/.config/zsh/{options,aliases,prompt}.zsh` in that order.
- `ls --color` forced colour even when piped; now `--color=auto`.
- `ll`, `la`, `l` duplicated the `LC_COLLATE=C` prefix; they now chain off
  the `ls` alias.
- `take` was an alias to a function with unquoted `$1`, no trailing
  newline in the usage message and output to `/dev/stderr`.
- `_gdcheck` duplicated `gd-check`; removed.
- `gd-pull` comment said "outputs to stdout" but it extracted with tar;
  `tar x -` also lacked `-f`. Comment and command fixed.
- `HISTSIZE` (10000) was smaller than `SAVEHIST` (20000), which makes
  the saved history truncate. Both are 20000.
- `color_prompt=yes` was unused. A commented-out lesspipe line and a
  duplicate `list-colors ''` zstyle were removed.
- `prompt.zsh` defined `precmd()` directly (printing an undefined
  `$TERM_TITLE`) while also using `add-zsh-hook`. Now both hooks go
  through `add-zsh-hook`. A general `':vcs_info:*:*' actionformats`
  overrode the git-specific one; removed. `setopt prompt_subst` was set
  twice.

### vim

- `set nocompatible` came after plugin setup; it is now the first line.
- `set number`, `set autoread`, `directory`, `backupdir` were each set
  twice.
- `t_8f`/`t_8b` contained raw escape bytes and `set t_Co=256` is
  redundant with `termguicolors`; all removed.
- `autocmd` lines were not in an `augroup`, so re-sourcing the file
  stacked duplicates.
- netrw opened on every start, including `git commit`; now only when vim
  is started without arguments.
- `packadd termdebug` was missing, so `:Termdebug` did not exist.
- `filetype on/plugin on/indent on` collapsed to one line.

### Colorscheme

`melange.vim` (light only, with custom `Normal`/`Search`/`Substitute`
colours) and `melange_modified.vim` (upstream, light and dark) both set
`g:colors_name = 'melange'` but only the first was ever loaded. They are
merged: the light/dark file with the custom light colours applied.
