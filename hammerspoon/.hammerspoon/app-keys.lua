-- アプリ切り替えなどのショートカット (⌃⌘ + キー)
--
-- APPS: 押すとそのアプリを前面に出す (起動していなければ起動する)。
--       すでに前面にあるときに押すと隠して、直前に使っていたアプリに戻る。
-- URLS: 固定の URL を Vivaldi で開く / ⌃⌘g: 入力欄を出して Google 検索 / ⌃⌘r: cmux の最新通知へ
-- 同じキーを Raycast などにも登録すると、どちらが反応するか定まらないため、ここだけで割り当てる。
--
-- どの PC でも同じにしたいショートカットはここに置く。
-- その PC でしか使わないもの (Slack チャンネルのクイックリンクなど) は Raycast に置き、dotfiles には入れない。

local MODS = { "ctrl", "cmd" }

-- キー -> bundle ID
-- (bundle ID は `osascript -e 'id of app "<アプリ名>"'` で確認できる)
local APPS = {
  t = "com.cmuxterm.app",
  b = "com.vivaldi.Vivaldi",
  o = "com.google.Chrome",
  n = "md.obsidian",
  s = "com.tinyspeck.slackmacgap",
  e = "com.microsoft.VSCode",
}

local CMUX = "com.cmuxterm.app"
local VIVALDI = "com.vivaldi.Vivaldi"

-- 固定の URL を Vivaldi で開くもの。キー -> URL
local URLS = {
  c = "https://calendar.google.com/",
}

-- 入力した語で検索するもの (⌃⌘g)。{query} を URL エンコードした入力に置き換える
local SEARCH_URL = "https://www.google.com/search?q={query}"

local function toggle(bundleID)
  local app = hs.application.get(bundleID)
  if app and app:isFrontmost() then
    -- 隠すと macOS が直前のアプリを前面に戻す。最小化と違い、次に前面に出すとそのまま元の位置に戻る
    app:hide()
  else
    hs.application.launchOrFocusByBundleID(bundleID)
  end
end

-- cmux を前面に出し、最新の通知 (Claude Code の入力待ちなど) へ移動する (cmux の ⌘⇧U)
local function jumpToLatestNotification()
  local app = hs.application.get(CMUX)
  if not app then
    -- 起動直後は通知がないので、起動するだけにする
    hs.application.launchOrFocusByBundleID(CMUX)
    return
  end
  app:activate()
  -- 送り先のアプリを指定するので、前面に出るのを待たなくても cmux に届く
  hs.eventtap.keyStroke({ "cmd", "shift" }, "u", 0, app)
end

local function openURL(url)
  hs.urlevent.openURLWithBundle(url, VIVALDI)
end

-- 入力欄に打った語を、Enter で Vivaldi の Google 検索として開く
local searchChooser = hs.chooser.new(function(choice)
  if choice then
    openURL((SEARCH_URL:gsub("{query}", function() return hs.http.encodeForQuery(choice.query) end)))
  end
end)
searchChooser:placeholderText("Google で検索")
searchChooser:queryChangedCallback(function(query)
  -- 候補が 1 件ないと Enter で何も選ばれないので、入力をそのまま 1 件の候補にする
  if query == "" then
    searchChooser:choices({})
  else
    searchChooser:choices({ { text = query, subText = "Google で検索", query = query } })
  end
end)

-- require の戻り値は package.loaded に残るため、ここに入れたものは GC で止まらない
local M = { hotkeys = {} }
for key, bundleID in pairs(APPS) do
  table.insert(M.hotkeys, hs.hotkey.bind(MODS, key, function() toggle(bundleID) end))
end
for key, url in pairs(URLS) do
  table.insert(M.hotkeys, hs.hotkey.bind(MODS, key, function() openURL(url) end))
end
table.insert(M.hotkeys, hs.hotkey.bind(MODS, "g", function()
  searchChooser:query("")
  searchChooser:show()
end))
table.insert(M.hotkeys, hs.hotkey.bind(MODS, "r", jumpToLatestNotification))
M.searchChooser = searchChooser

return M
