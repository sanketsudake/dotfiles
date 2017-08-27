call plug#begin()
Plug 'fatih/vim-go'
call plug#end()
filetype plugin indent on
syn on se title
set tabstop=4
set softtabstop=4
set shiftwidth=4
set expandtab
set listchars=eol:$,tab:>-,trail:~,extends:>,precedes:<
set list
set laststatus=2
set statusline=%<%f\ %h%m%r\ %y%=%{v:register}\ %-14.(%l,%c%V%)\ %P
