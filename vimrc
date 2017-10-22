function! BuildYCM(info)
    " info is a dictionary with 3 fields
    " - name:   name of the plugin
    " - status: 'installed', 'updated', or 'unchanged'
    " - force:  set on PlugInstall! or PlugUpdate!
    if a:info.status == 'installed' || a:info.force
        !./install.py
    endif
endfunction

call plug#begin()
" Common VIM agreements
Plug 'tpope/vim-sensible'
" File browser
Plug 'scrooloose/nerdtree'
" Distraction-free writing in Vim
Plug 'junegunn/goyo.vim'
" Go Support
Plug 'fatih/vim-go', { 'do': ':GoInstallBinaries' }
" Autocompletion
Plug 'Valloric/YouCompleteMe', { 'do': function('BuildYCM') }
" Peaksea theme
Plug 'vim-scripts/peaksea'
" Git diff in modified files
Plug 'airblade/vim-gitgutter'

call plug#end()

filetype plugin on
filetype indent on
syn on se title

" Always show current position
set ruler

" Height of the command bar
set cmdheight=2

" Use space instead of tabs
set expandtab

" Buffer becomes hidden when it is abandoned
set hid

" Be smart when using tabs
set smarttab

" 1 tab == 4 spaces
set tabstop=4
set softtabstop=4
set shiftwidth=4

set listchars=tab:>-,trail:~,extends:>,precedes:<
set list
set laststatus=2
set statusline=%<%f\ %h%m%r\ %y%=%{v:register}\ %-14.(%l,%c%V%)\ %P
set nu

" Highlight search results
set hlsearch

" Make search act like search in modern browsers
set incsearch

" Show matching brackets when text indicator is over them
set showmatch

" Turn backup off, since most stuff is in git anyway
set nobackup
set nowb
set noswapfile

" Keybindings
map <C-n> :NERDTreeToggle<CR>

" Enable 256 colors pallete in Gnome Terminal
if $COLORTERM == 'gnome-terminal'
    set t_Co=256
endif

try
    colorscheme peaksea
catch
endtry


try
    set switchbuf=useopen,usetab,newtab
    set stal=2
catch
endtry


set encoding=utf8
