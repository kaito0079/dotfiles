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

-- 接続直後は macOS 自身もウィンドウを動かし、watcher も複数回呼ばれるので、落ち着くまで待ってから判定する。
-- 途中の構成はどのプロファイルとも完全一致しないため、待つのは macOS の動きを避けるためだけ
local SETTLE_SEC = 1.0

-- フルスクリーンの解除・移行はアニメーションが終わるまで次の操作を受け付けないため待つ
local FULLSCREEN_ANIMATION_SEC = 1.0
-- 解除を受け付けないアプリ (モーダル表示中など) で再試行し続けないための上限
local FULLSCREEN_EXIT_MAX_TRIES = 3

-- 移動の反映や Space の切り替えは完了の通知がないため、短い間隔で確認して終わりしだい次へ進む
local POLL_INTERVAL_SEC = 0.1
local POLL_MAX_TRIES = 20

-- 最後に配置したプロファイル名。起動・Reload Config のときにこれと比べ、同じなら配置し直さない
local SETTINGS_KEY = "layout.lastProfile"

-- 戻り値を保持しないタイマーは GC で回収されて止まることがあるため、実行されるまでここで参照を持つ
local pendingTimers = {}

local function after(sec, fn)
  local timer
  timer = hs.timer.doAfter(sec, function()
    pendingTimers[timer] = nil
    fn()
  end)
  pendingTimers[timer] = true
end

local function waitUntil(predicate, fn, interval)
  local timer
  timer = hs.timer.waitUntil(predicate, function()
    pendingTimers[timer] = nil
    fn()
  end, interval)
  pendingTimers[timer] = true
end

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

-- 処理が終わったら (中止した場合も) done を呼ぶ
local function placeFullScreen(win, screen, done, exitTries)
  exitTries = exitTries or 0
  if win:isFullScreen() then
    if win:screen() == screen then return done() end
    if exitTries >= FULLSCREEN_EXIT_MAX_TRIES then
      log.w(string.format("fullscreen: %s の解除を受け付けないため中止", win:application():name()))
      return done()
    end
    -- フルスクリーンのままでは別の画面へ動かせないので、一度解除する
    win:setFullScreen(false)
    after(FULLSCREEN_ANIMATION_SEC, function() placeFullScreen(win, screen, done, exitTries + 1) end)
    return
  end
  win:moveToScreen(screen)
  -- 移動が反映される前にフルスクリーンにすると元の画面で全画面になるため、着いたことを確認してから切り替える
  local tries = 0
  waitUntil(function()
    tries = tries + 1
    return win:screen() == screen or tries > POLL_MAX_TRIES
  end, function()
    -- 着かないまま上限に達したら、別の画面で全画面になるよりは何もしない
    if win:screen() == screen then
      win:setFullScreen(true)
      after(FULLSCREEN_ANIMATION_SEC, done)
    else
      log.w(string.format("fullscreen: %s が %s に着かないため中止 (現在 %s)",
        win:application():name(), screen:name(), win:screen():name()))
      done()
    end
  end, POLL_INTERVAL_SEC)
end

-- フルスクリーンのルールがあるのに今の Space でウィンドウが見つからないアプリを、前面に出してから配置する。
-- (Mac 単体で全画面にした Slack は、外部モニター接続後も専用の Space に残っていて見えない)
-- 前面に出すと macOS がその Space に切り替えるので、ウィンドウが見えるようになるのを待ってから配置する。
-- track() は非同期の処理を 1 つ始めるたびに呼び、終わったら返り値の関数を呼ぶ
local function placeHiddenFullScreenApps(profile, screens, placed, track)
  for bundleID, rule in pairs(profile.rules) do
    local app = hs.application.get(bundleID)
    if rule.mode == "fullscreen" and not placed[bundleID] and app then
      local done = track()
      app:activate()
      local tries = 0
      waitUntil(function()
        tries = tries + 1
        return app:mainWindow() ~= nil or tries > POLL_MAX_TRIES
      end, function()
        local win = app:mainWindow()
        if win then
          placeFullScreen(win, screens[rule.screen], done)
        else
          log.w(string.format("fullscreen: %s のウィンドウが見つからないため中止", app:name()))
          done()
        end
      end, POLL_INTERVAL_SEC)
    end
  end
end

local function applyLayout(profile, screens)
  -- フルスクリーン化はフォーカスを奪うので、focus のアプリは全部終わってから前面に出す。
  -- ループ中に同期的に終わる処理があっても早まらないよう、ループ自体を 1 件として数えておく
  local pending = 0
  local function track()
    pending = pending + 1
    return function()
      pending = pending - 1
      if pending == 0 and profile.focus then
        local app = hs.application.get(profile.focus)
        if app then app:activate() end
      end
    end
  end
  local loopDone = track()

  local placed = {}
  for _, win in ipairs(hs.window.visibleWindows()) do
    local app = win:application()
    if win:isStandard() and app then
      placed[app:bundleID()] = true
      local rule = profile.rules[app:bundleID()] or profile.default
      local screen = screens[rule.screen]
      if rule.mode == "fullscreen" then
        placeFullScreen(win, screen, track())
      elseif not win:isFullScreen() then
        win:moveToScreen(screen, false, true)
        if UNITS[rule.mode] then win:moveToUnit(UNITS[rule.mode]) end
      end
    end
  end

  placeHiddenFullScreenApps(profile, screens, placed, track)
  loopDone()
end

-- 起動をまたいで覚えておくことで、モニターをつないでから Hammerspoon が起動した (再起動・ログイン) ときも配置できる。
-- 一致なし (nil) は保存しない。外している途中の状態で起動しても、前回の場所との比較が残るようにするため
local lastProfileName = hs.settings.get(SETTINGS_KEY)

local layoutTimer = hs.timer.delayed.new(SETTLE_SEC, function()
  local name, profile, screens = matchProfile()
  -- watcher はモニター接続以外 (Dock の表示変更など) でも呼ばれるので、プロファイルが切り替わったときだけ配置する
  if name ~= lastProfileName then
    log.i(string.format("profile: %s -> %s", tostring(lastProfileName), tostring(name)))
    if name then
      applyLayout(profile, screens)
      hs.settings.set(SETTINGS_KEY, name)
    end
  end
  lastProfileName = name
end)

-- local にすると GC で回収されて watcher が止まるため、グローバルに保持する。
screenWatcher = hs.screen.watcher.new(function() layoutTimer:start() end):start()

-- 起動・Reload Config の時点でも 1 回判定する (前回と同じプロファイルなら何もしない)
layoutTimer:start()
