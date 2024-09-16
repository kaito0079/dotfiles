#!/bin/bash

# .DS_Storeを作らないようにする
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true

# Dockの設定
# Dockを自動的に隠す
defaults write com.apple.dock autohide -bool true
# Dockに標準で入っている全てのアプリを消す(Finderとゴミ箱は消えない)
#defaults write com.apple.dock persistent-apps -array

# Mission Control
# ホットコーナー
# 左上 -> Mission Controller
#defaults write com.apple.dock wvous-tl-corner -int 2
#defaults write com.apple.dock wvous-tl-modifier -int 0
# 右上 -> Mission Controller
#defaults write com.apple.dock wvous-tr-corner -int 2
#defaults write com.apple.dock wvous-tr-modifier -int 0
# 左下 -> Launchpad
# defaults write com.apple.dock wvous-bl-corner -int 11
# defaults write com.apple.dock wvous-bl-modifier -int 0
# 右下 -> Show application windows
# defaults write com.apple.dock wvous-br-corner -int 3
# defaults write com.apple.dock wvous-br-modifier -int 0

# Finder
# ステータスバーを表示
defaults write com.apple.finder ShowStatusBar -bool true
## パスバーを表示
defaults write com.apple.finder ShowPathBar -bool true
# タブバーを表示
defaults write com.apple.finder ShowTabView -bool true

# 不可視ファイルを表示
defaults write com.appple.finder AppleShowAllFiles true


# Install brew
#(echo; echo 'eval "$(/opt/homebrew/bin/brew shellenv)"') >> /Users/kaito.tada/.zprofile
#eval "$(/opt/homebrew/bin/brew shellenv)"

# サービスの自動起動を制御
launchctl disable gui/"$(id -u)"/com.apple.rcd  # Apple Music
