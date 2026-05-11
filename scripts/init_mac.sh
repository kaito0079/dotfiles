#!/bin/bash

# .DS_Storeを作らないようにする
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true

# Dockの設定
# Dockを自動的に隠す
defaults write com.apple.dock autohide -bool true
# Dockに標準で入っている全てのアプリを消す(Finderとゴミ箱は消えない)
#defaults write com.apple.dock persistent-apps -array

# ==============================================================================
# ホットコーナーの設定
#
# 数値と機能の対応表
# ------------------------------------------------------------------------------
#  0: - (なし)
#  2: Mission Control
#  3: アプリケーションウィンドウ
#  4: デスクトップ
#  5: スクリーンセーバーを開始する
#  6: スクリーンセーバーを無効にする
#  7: Dashboard
# 10: ディスプレイをスリープさせる
# 11: Launchpad
# 12: 通知センター
# 13: 画面をロック
# 14: クイックメモ
#
# 各コーナーの指定
# ------------------------------------------------------------------------------
# wvous-tl-corner: 左上
# wvous-tr-corner: 右上
# wvous-bl-corner: 左下
# wvous-br-corner: 右下
#
# 修飾キーの指定
# ------------------------------------------------------------------------------
# wvous-XX-modifier: 0 は修飾キーなし
#
# ==============================================================================

# 左上 -> Mission Controller
#defaults write com.apple.dock wvous-tl-corner -int 2
#defaults write com.apple.dock wvous-tl-modifier -int 0
# 右上 -> 通知センター
defaults write com.apple.dock wvous-tr-corner -int 12
defaults write com.apple.dock wvous-tr-modifier -int 0
# 左下 -> デスクトップ
defaults write com.apple.dock wvous-bl-corner -int 4
defaults write com.apple.dock wvous-bl-modifier -int 0
# 右下 -> Launchpad
defaults write com.apple.dock wvous-br-corner -int 11
defaults write com.apple.dock wvous-br-modifier -int 0

# Finder
# ステータスバーを表示
defaults write com.apple.finder ShowStatusBar -bool true
## パスバーを表示
defaults write com.apple.finder ShowPathBar -bool true
# タブバーを表示
defaults write com.apple.finder ShowTabView -bool true

# 不可視ファイルを表示
defaults write com.appple.finder AppleShowAllFiles true

# キー長押し時の特殊文字ポップアップを無効にし、キーリピートを有効にする
defaults write -g ApplePressAndHoldEnabled -bool false


# Install brew
#(echo; echo 'eval "$(/opt/homebrew/bin/brew shellenv)"') >> "$HOME/.zprofile"
#eval "$(/opt/homebrew/bin/brew shellenv)"

# サービスの自動起動を制御
launchctl disable gui/"$(id -u)"/com.apple.rcd  # Apple Music
