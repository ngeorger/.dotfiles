" Consult the Vim Options Documentation as a reference
" http://vimdoc.sourceforge.net/htmldoc/options.html

" Explicitly use sh
set shell=sh

" Be more useful (ie. drop Vi compatibility)
set nocompatible

" Setting this first seems to fix non-zero exit status on OS X
filetype on

" Disable all file type detection (for Vundle)
filetype off

" Enable mouse usage everywhere (all modes)
if has('mouse')
    set mouse=a
endif

" Load up Vundle
set rtp+=~/.vim/bundle/vundle/
call vundle#rc()

" Let Vundle manage Vundle
Bundle 'gmarik/vundle'

" ******************** Bundles ********************
Bundle 'altercation/vim-colors-solarized'
Bundle 'bling/vim-airline'
Bundle 'ervandew/supertab'
Bundle 'kien/ctrlp.vim'
Bundle 'Lokaltog/vim-easymotion'
Bundle 'scrooloose/nerdtree'
Bundle 'scrooloose/syntastic'
Bundle 'tpope/vim-fugitive'
Bundle 'L9'
Bundle 'surround.vim'

" Enable full file type detection (for Vundle)
filetype plugin indent on

" Use the Solarized colour scheme
try
    colorscheme solarized
catch
    colorscheme default
endtry

" Optimise for dark backgrounds
set background=dark

" Allow backspacing over everything in insert mode
set backspace=indent,eol,start

" Don't litter the filesystem with backup files
set nobackup

" Highlight the current line
set cursorline

" Don't expand tabs into spaces
set noexpandtab

" Increase the command line history
set history=50

" Ignore case in search patterns
set ignorecase

" Search incrementally (ie. start matching immediately)
set incsearch

" Always draw a status line
set laststatus=2

" Enable modeline support
set modeline

" Print the line number in front of each line
set number

" Always show the cursor position (line and column number)
set ruler

" Show partial command in the last line of the screen
set showcmd

" Case sensitive search if the pattern has upper case characters
set smartcase

" Do smart autoindenting when starting a new line
set smartindent

" Insert appropriate number of blanks for tab in front of a line
set smarttab

" If the terminal has colour support then add some extras
if &t_Co > 2 || has('gui_running')
    " Enable syntax highlighting
    syntax on

    " Highlight matches when searching
    set hlsearch
endif

