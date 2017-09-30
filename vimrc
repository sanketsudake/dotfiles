call plug#begin()
" Common VIM agreements
Plug 'tpope/vim-sensible'
" File browser
Plug 'scrooloose/nerdtree'
" Distraction-free writing in Vim
Plug 'junegunn/goyo.vim'
" Go Support
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

" Keybindings
map <C-n> :NERDTreeToggle<CR>
