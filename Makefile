CWD=$(shell pwd)

all: vim-plugins git-config vim-rc


vim-plugins: vim-plug

vim-rc:
	ln -sf ${CWD}/vimrc ${HOME}/.vimrc

vim-plug:
	python -mplatform | grep -qi Ubuntu && sudo apt-get install -y build-essential cmake || sudo yum install cmake
	mkdir -p ~/.vim/autoload ~/.vim/bundle
	curl -fLo ~/.vim/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
	vim +PlugInstall +qall

git-config:
	git config --global core.editor vim
	git config --global user.name "Sanket Sudake"
	git config --global user.email "sanket@infracloud.io"
	git config --global color.ui true
	git config --global gitreview.username "ssudake21"
