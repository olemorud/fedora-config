set nocompatible
filetype plugin indent on
syntax on

set number
set autoread                        " reload files changed on disk
set hidden                          " switch buffers without saving
set backspace=indent,eol,start
set ignorecase smartcase
set history=1000
set wildmenu
set tabstop=4 shiftwidth=4
set mouse=a
set completeopt=menuone,noinsert,noselect,preview

" Swap and backup files out of the working tree
set directory=$HOME/.vim/swapfiles//
set backupdir=$HOME/.vim/backups//

" Disable Ex mode
noremap Q <nop>

" Buffers behave more like tabs
noremap gl :bnext!<CR>
noremap gh :bprevious!<CR>
noremap gd :bdelete!<CR>

" Tab through the completion popup
inoremap <expr> <Tab>   pumvisible() ? "\<C-n>" : "\<Tab>"
inoremap <expr> <S-Tab> pumvisible() ? "\<C-p>" : "\<S-Tab>"

" netrw as a file explorer side pane
let g:netrw_winsize = 12
let g:netrw_banner = 0
let g:netrw_liststyle = 3

" Termdebug (:Termdebug ./prog)
packadd termdebug
let g:termdebug_popup = 0
let g:termdebug_wide = 163

augroup vimrc
    autocmd!
    " Open the explorer only when started without a file argument
    autocmd VimEnter * if argc() == 0 | Lexplore | endif
    " Close the preview window when completion is done
    autocmd CompleteDone * if pumvisible() == 0 | pclose | endif
    " F5: compile and run a single-file C program
    autocmd FileType c nnoremap <buffer> <F5> :w <bar>
        \ exec '!gcc ' . shellescape('%') . ' -lm -o ' . shellescape('%:r')
        \ . ' && ./' . shellescape('%:r')<CR>
augroup END

" Colors
set termguicolors
set background=light
colorscheme melange
