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

-- モニター接続時のウィンドウ配置 (環境ごとの設定は profiles.lua)
require("layout")
