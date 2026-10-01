-- アプリの切り替え手段と、修飾キー付きショートカットの回数の記録
--
-- 繰り返し作業の分析 (activitywatch/aw-collect.py) 用に、アプリが切り替わるたびに
-- 「どうやって切り替えたか」を ~/.local/share/aw-insights/switches.tsv に 1 行ずつ追記する。
-- ショートカットを設定していないのか、設定しているのに使えていないのかを見分けるため。
-- 修飾キー付きの組み合わせは、アプリごとに 1 時間単位の回数だけを combos.tsv に残す。
--
-- 記録しないもの:
--   - 修飾キーなしの入力 (文字・本文・Raycast の検索語)
--   - セキュア入力中 (パスワード欄など) のすべての入力
--   - クリックの座標 (Dock / メニューバー / ウィンドウの分類だけを残す)
-- 90 日より古い行は activitywatch/aw-prune.py が削除する。

local log = hs.logger.new("input-log", "info")

local DIR = os.getenv("HOME") .. "/.local/share/aw-insights"
local SWITCHES = DIR .. "/switches.tsv"
local COMBOS = DIR .. "/combos.tsv"

-- 切り替えの直前にこの秒数以内のショートカット・クリックがあれば、それが切り替えの手段とみなす
local CAUSE_WINDOW_SEC = 1.0
-- Raycast や Mission Control を開いてから選ぶまでの猶予。検索語を打つ時間を見込む
local LAUNCHER_WINDOW_SEC = 20
-- ⌘ を押したまま Tab を押し、離した時点で切り替わる。途中でやめた ⌘Tab を後の切り替えに数えない
local CMDTAB_WINDOW_SEC = 3
-- 一覧を開いてから選んで切り替えるもの。キー -> 手段の名前
-- (Raycast の設定 raycastGlobalHotkey = Control-49、⌃↑ / ⌃↓ は macOS 標準のキー)
local LAUNCHERS = {
  ["⌃space"] = "raycast",
  ["⌃up"] = "missioncontrol",
  ["⌃down"] = "appexpose",
}
-- 開いた後のクリックを「一覧から選んだ」とみなす場所。
-- Raycast は外をクリックすると閉じるので Raycast の中だけ。Mission Control・App Exposé は
-- 縮小表示の位置の要素が切り替え先のウィンドウとして返るため、どこをクリックしても選択とみなす
local LAUNCHER_CLICK_PLACES = { raycast = "raycast", missioncontrol = "any", appexpose = "any" }
-- 回数の集計を書き出す間隔。書き出し前に Reload Config すると、その分は失われる
local FLUSH_SEC = 600

hs.fs.mkdir(DIR)

local et = hs.eventtap
local types = et.event.types

-- 直前の操作。切り替えが起きた時点でこれを見て手段を決める
local last = {
  combo = nil,       -- { name, at }
  click = nil,       -- { place, at }
  launcher = nil,    -- { kind, at }。Raycast・Mission Control を開いた。選択・Esc で消す
  cmdTabs = 0,       -- ⌘ を押したままの Tab の回数
  cmdTabAt = nil,
}
-- [時間の先頭 epoch .. "\t" .. アプリ .. "\t" .. 組み合わせ] -> 回数
local comboCounts = {}

local function append(path, line)
  local f = io.open(path, "a")
  if not f then
    log.e("書き込めません: " .. path)
    return
  end
  f:write(line, "\n")
  f:close()
end

local function clean(s)
  return (tostring(s or ""):gsub("[\t\n]", " "))
end

local function comboName(e)
  local f = e:getFlags()
  if not (f.cmd or f.ctrl or f.alt) then return nil end
  local key = hs.keycodes.map[e:getKeyCode()] or "?"
  return (f.ctrl and "⌃" or "") .. (f.alt and "⌥" or "") .. (f.shift and "⇧" or "") .. (f.cmd and "⌘" or "") .. key
end

-- クリックした場所を Dock / メニューバー / ウィンドウに分ける。要素の中身は読まない
local function clickPlace()
  local pos = hs.mouse.absolutePosition()
  local ok, el = pcall(hs.axuielement.systemElementAtPosition, pos)
  if not ok or not el then return "unknown" end
  local app = hs.application.applicationForPID(el:pid())
  local bundle = app and app:bundleID()
  if bundle == "com.apple.dock" then return "dock" end
  -- Raycast の一覧をマウスで選んだ場合は、Raycast での切り替えとして扱う
  if bundle == "com.raycast.macos" then return "raycast" end
  local role = el:attributeValue("AXRole") or ""
  if role:find("MenuBar") then return "menubar" end
  return "window"
end

local function frontName()
  local app = hs.application.frontmostApplication()
  return app and app:name() or ""
end

local function onKey(e)
  if et.isSecureInputEnabled() then return false end
  local code = e:getKeyCode()
  if code == hs.keycodes.map["escape"] then last.launcher = nil end
  local name = comboName(e)
  if not name then return false end

  local now = hs.timer.secondsSinceEpoch()
  local l = last.launcher
  if LAUNCHERS[name] then
    last.launcher = { kind = LAUNCHERS[name], at = now }
  elseif name == "⌘tab" or name == "⇧⌘tab" then
    last.cmdTabs = last.cmdTabs + 1
    last.cmdTabAt = now
  elseif not (l and now - l.at <= LAUNCHER_WINDOW_SEC) then
    -- 一覧を開いている間の組み合わせ (Raycast の ⌘Enter など) は一覧の中の操作なので、切り替えの手段にしない
    last.combo = { name = name, at = now }
  end
  local hour = math.floor(now / 3600) * 3600
  local k = hour .. "\t" .. clean(frontName()) .. "\t" .. name
  comboCounts[k] = (comboCounts[k] or 0) + 1
  return false
end

local function onClick()
  last.click = { place = clickPlace(), at = hs.timer.secondsSinceEpoch() }
  return false
end

-- 直前の操作から切り替えの手段を決める
local function cause(now)
  local c, k, l = last.combo, last.click, last.launcher
  local function recent(at, window) return at and now - at <= window end
  local launcherOpen = l and recent(l.at, LAUNCHER_WINDOW_SEC)
  -- 一覧を開いた後のその一覧の中のクリックは、一覧から選んだ操作
  local places = LAUNCHER_CLICK_PLACES[l and l.kind]
  if launcherOpen and k and k.at > l.at and (places == "any" or k.place == places) then
    return l.kind, string.format("%.0f", now - l.at)
  end
  -- 一覧を閉じた後のショートカット・クリックは、新しい方を切り替えの直接の原因とみなす
  local comboOk = c and recent(c.at, CAUSE_WINDOW_SEC) and not (launcherOpen and c.at < l.at)
  local clickOk = k and recent(k.at, CAUSE_WINDOW_SEC) and not (launcherOpen and k.at < l.at)
  if comboOk and (not clickOk or c.at >= k.at) then return "shortcut", c.name end
  if clickOk then return "mouse", k.place end
  if launcherOpen then return l.kind, string.format("%.0f", now - l.at) end
  if last.cmdTabs > 0 and recent(last.cmdTabAt, CMDTAB_WINDOW_SEC) then return "cmdtab", tostring(last.cmdTabs) end
  return "unknown", ""
end

local previous = frontName()

local function onActivated(name, event)
  if event ~= hs.application.watcher.activated or name == previous then return end
  local now = hs.timer.secondsSinceEpoch()
  local how, detail = cause(now)
  append(SWITCHES, table.concat({ math.floor(now), clean(previous), clean(name), how, clean(detail) }, "\t"))
  previous = name
  last.launcher, last.cmdTabs, last.cmdTabAt, last.combo, last.click = nil, 0, nil, nil, nil
end

local function flush()
  local lines = {}
  for k, n in pairs(comboCounts) do table.insert(lines, k .. "\t" .. n) end
  comboCounts = {}
  if #lines > 0 then append(COMBOS, table.concat(lines, "\n")) end
end

-- require の戻り値は package.loaded に残るため、ここに入れたものは GC で止まらない
local M = {}
M.keyTap = et.new({ types.keyDown }, onKey):start()
M.clickTap = et.new({ types.leftMouseDown }, onClick):start()
M.appWatcher = hs.application.watcher.new(onActivated):start()
M.flushTimer = hs.timer.doEvery(FLUSH_SEC, flush)
M.flush = flush

-- Reload Config や終了の前に、集計途中の回数を書き出す
hs.shutdownCallback = flush

return M
