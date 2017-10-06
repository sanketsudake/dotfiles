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
set nu
set hls

" Keybindings
map <C-n> :NERDTreeToggle<CR>
