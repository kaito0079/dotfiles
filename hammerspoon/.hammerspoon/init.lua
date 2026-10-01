-- Hammerspoon 設定
--
-- 運用ルール:
--   - 第三者製の Spoon やネット上の設定サンプルをそのまま使わない。
--     Spoon を使うなら公式リポジトリ (github.com/Hammerspoon/Spoons) のもので、
--     コードを読んだものに限る。
--   - このファイル (および dotfiles 配下) に認証情報を書かない。
--   - スクリーンロックを妨げる用途 (hs.caffeinate でのスリープ抑止など) に使わない。
--   - クラッシュレポートの送信は無効にする (下記)。

-- クラッシュレポート (Sentry) の送信を無効化する。
-- 設定画面のチェックボックスと同じ HSUploadCrashData を書き換える。
-- 起動直後のクラッシュにも効くよう setup/init_mac.sh でも defaults で設定している。
hs.uploadCrashData(false)

-- ターミナル (Claude Code を含む) から `hs -c '<Lua>'` で設定の再読み込みや
-- Console の確認をできるようにする。hs コマンドは Hammerspoon.app 同梱のもの
-- (Contents/Frameworks/hs/hs) を使う。同じユーザーのプロセスなら任意の Lua を
-- 実行できるため、Claude Code では `hs -c` を許可リストに入れず毎回承認する。
require("hs.ipc")

-- モニター接続時のウィンドウ配置 (環境ごとの設定は profiles.lua)
require("layout")

-- アプリの切り替え手段とショートカットの回数を記録する (繰り返し作業の分析用)
require("input-log")
