-- モニター接続時のウィンドウ配置
--
-- つないだモニターの組み合わせが profiles.lua のどれかと一致した時点で、1 回だけアプリを各画面へ振り分ける。
-- どのプロファイルとも一致しない構成では何もしない。

local profiles = require("profiles")

-- プロファイルの切り替えと失敗を Hammerspoon の Console に出す
local log = hs.logger.new("layout", "info")

-- 配置方法 -> 画面内の位置
local UNITS = {
  maximize = hs.layout.maximized,
  ["left-half"] = hs.layout.left50,
  ["right-half"] = hs.layout.right50,
}

-- 接続直後は macOS 自身もウィンドウを動かし、watcher も複数回呼ばれるので、落ち着くまで待ってから判定する。
-- 途中の構成はどのプロファイルとも完全一致しないため、待つのは macOS の動きを避けるためだけ
local SETTLE_SEC = 1.0

-- 最後に配置したプロファイル名。起動・Reload Config のときにこれと比べ、同じなら配置し直さない
local SETTINGS_KEY = "layout.lastProfile"

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

local function applyLayout(profile, screens)
  for _, win in ipairs(hs.window.visibleWindows()) do
    local app = win:application()
    -- macOS のフルスクリーンは専用の Space にあり、解除と移動を待つ処理が不安定なため触らない
    if win:isStandard() and app and not win:isFullScreen() then
      local rule = profile.rules[app:bundleID()] or profile.default
      win:moveToScreen(screens[rule.screen], false, true)
      if UNITS[rule.mode] then win:moveToUnit(UNITS[rule.mode]) end
    end
  end

  if profile.focus then
    local app = hs.application.get(profile.focus)
    if app then app:activate() end
  end
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
