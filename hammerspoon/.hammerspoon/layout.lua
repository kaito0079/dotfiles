-- モニター接続時のウィンドウ配置
--
-- つないだモニターの組み合わせが profiles.lua のどれかと一致した時点で、1 回だけアプリを各画面へ振り分ける。
-- どのプロファイルとも一致しない構成では何もしない。

local profiles = require("profiles")

-- プロファイルの切り替えと失敗を Hammerspoon の Console に出す
local log = hs.logger.new("layout", "info")

-- 配置方法 -> 画面内の位置 (fullscreen 以外)
local UNITS = {
  maximize = hs.layout.maximized,
  ["left-half"] = hs.layout.left50,
  ["right-half"] = hs.layout.right50,
}

-- フルスクリーンの解除・移行はアニメーションが終わるまで次の操作を受け付けないため待つ
local FULLSCREEN_ANIMATION_SEC = 1.0
-- 解除を受け付けないアプリ (モーダル表示中など) で再試行し続けないための上限
local FULLSCREEN_EXIT_MAX_TRIES = 3

-- 移動が反映される前にフルスクリーンにすると元の画面で全画面になるため、
-- 目的の画面に着いたことを確認してからフルスクリーンにする (Slack などの Electron アプリは反映が遅い)
local MOVE_CHECK_INTERVAL_SEC = 0.2
local MOVE_CHECK_MAX_TRIES = 10

-- 配置後に focus のアプリを前面に出すまでの待ち時間。
-- 先に出すとフルスクリーン化で奪い返されるため、解除 → 移動確認 → 移行 (約 2.2 秒) が終わってから出す
local FOCUS_DELAY_SEC = 3

-- つながっているモニターがプロファイルの screens と完全に一致すれば { 役割名 -> hs.screen } を返す。
-- 一部一致を許すと、内蔵ディスプレイだけのプロファイルが外部モニター接続時にも一致してしまう。
local function resolveScreens(profile)
  local screens = {}
  for _, screen in ipairs(hs.screen.allScreens()) do
    local role = profile.screens[screen:name()]
    if not role then return nil end
    screens[role] = screen
  end
  for _, role in pairs(profile.screens) do
    if not screens[role] then return nil end
  end
  return screens
end

-- rules / default が screens にない役割名を指していると、配置の途中で nil の画面に移そうとして止まる。
-- 書き間違いのあるプロファイルは読み込み時に除外し、Console にエラーを出す。
local function invalidRoles(profile)
  local roles = {}
  for _, role in pairs(profile.screens) do roles[role] = true end
  local invalid = {}
  for bundleID, rule in pairs(profile.rules) do
    if not roles[rule.screen] then table.insert(invalid, bundleID .. " -> " .. tostring(rule.screen)) end
  end
  if not roles[profile.default.screen] then table.insert(invalid, "default -> " .. tostring(profile.default.screen)) end
  return invalid
end

for name, profile in pairs(profiles) do
  local invalid = invalidRoles(profile)
  if #invalid > 0 then
    log.e(string.format("profile %s を無効化: screens にない役割 (%s)", name, table.concat(invalid, ", ")))
    profiles[name] = nil
  end
end

local function matchProfile()
  for name, profile in pairs(profiles) do
    local screens = resolveScreens(profile)
    if screens then return name, profile, screens end
  end
end

local function placeFullScreen(win, screen, exitTries)
  exitTries = exitTries or 0
  if win:isFullScreen() then
    if win:screen() == screen then return end
    if exitTries >= FULLSCREEN_EXIT_MAX_TRIES then
      log.w(string.format("fullscreen: %s の解除を受け付けないため中止", win:application():name()))
      return
    end
    -- フルスクリーンのままでは別の画面へ動かせないので、一度解除する
    win:setFullScreen(false)
    hs.timer.doAfter(FULLSCREEN_ANIMATION_SEC, function() placeFullScreen(win, screen, exitTries + 1) end)
    return
  end
  win:moveToScreen(screen)
  local tries = 0
  hs.timer.waitUntil(function()
    tries = tries + 1
    return win:screen() == screen or tries > MOVE_CHECK_MAX_TRIES
  end, function()
    -- 着かないまま上限に達したら、別の画面で全画面になるよりは何もしない
    if win:screen() == screen then
      win:setFullScreen(true)
    else
      log.w(string.format("fullscreen: %s が %s に着かないため中止 (現在 %s)",
        win:application():name(), screen:name(), win:screen():name()))
    end
  end, MOVE_CHECK_INTERVAL_SEC)
end

local function applyLayout(profile, screens)
  for _, win in ipairs(hs.window.visibleWindows()) do
    local app = win:application()
    if win:isStandard() and app then
      local rule = profile.rules[app:bundleID()] or profile.default
      local screen = screens[rule.screen]
      if rule.mode == "fullscreen" then
        placeFullScreen(win, screen)
      elseif not win:isFullScreen() then
        win:moveToScreen(screen, false, true)
        if UNITS[rule.mode] then win:moveToUnit(UNITS[rule.mode]) end
      end
    end
  end

  if profile.focus then
    hs.timer.doAfter(FOCUS_DELAY_SEC, function()
      local app = hs.application.get(profile.focus)
      if app then app:activate() end
    end)
  end
end

-- 起動時点のプロファイルを覚えておき、Reload Config だけでは配置し直さない
local lastProfileName = matchProfile()

-- 接続直後は macOS 自身もウィンドウを動かし、watcher も複数回呼ばれるので、落ち着いてから 1 回だけ判定する
local layoutTimer = hs.timer.delayed.new(2, function()
  local name, profile, screens = matchProfile()
  -- watcher はモニター接続以外 (Dock の表示変更など) でも呼ばれるので、プロファイルが切り替わったときだけ配置する
  if name ~= lastProfileName then
    log.i(string.format("profile: %s -> %s", tostring(lastProfileName), tostring(name)))
    if name then applyLayout(profile, screens) end
  end
  lastProfileName = name
end)

-- local にすると GC で回収されて watcher が止まるため、グローバルに保持する。
screenWatcher = hs.screen.watcher.new(function() layoutTimer:start() end):start()
