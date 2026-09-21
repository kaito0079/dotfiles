" 文字コードをUTF-8に設定
set fenc=utf-8
" 入力中のコマンドをステータスに表示する
set showcmd

" 見た目系
" 行数を表示
set number
" カーソルの位置を表示
set ruler
" 現在の行を強調表示
set cursorline
" 行末の1文字先までカーソルを移動できるように
set virtualedit=onemore
" 括弧入力時に対応する括弧を表示
set showmatch
" ステータスラインを常に表示
set laststatus=2
" コマンドラインの補完
set wildmode=list:longest
" シンタックスハイライトの有効化
syntax enable

" Tab系
" インデントをスペース4つ分に設定
set tabstop=4
" インデントの増減を4つ分に
set shiftwidth=4
" 不可視文字(タブ、空白、改行)を可視化(タブが「▶-」と表示される)
set list listchars=tab:\▶\-
" Tab文字を半角スペースにする
set expandtab
" スマートインデント
set smartindent
" 自動インデント
set autoindent

" 検索系
" 検索文字列が小文字の場合は大文字小文字を区別なく検索する
set ignorecase
" 検索文字列に大文字が含まれている場合は区別して検索する
set smartcase
" 検索文字列入力時に順次対象文字列にヒットさせる
set incsearch
" 検索時に最後まで行ったら最初に戻る
set wrapscan
" 検索語をハイライト表示
set hlsearch
