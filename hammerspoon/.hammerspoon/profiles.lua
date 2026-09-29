-- ウィンドウ配置のプロファイル (layout.lua から読み込む)
--
-- つながっているモニターの集合が screens と完全に一致したときに、そのプロファイルで配置する。
-- モニター名は Console で次を実行すると確認できる。
--   hs.inspect(hs.fnutils.map(hs.screen.allScreens(), function(s) return s:name() end))
--
-- screens: モニター名 -> 役割名 (rules の screen で参照する)
-- rules:   bundle ID -> { 配置先の役割, 配置方法 }
--          配置方法: "maximize" = ウィンドウのまま最大化 / "left-half" "right-half" = 左 / 右半分
--                    "fullscreen" = macOS のフルスクリーン / 省略 = 画面を移すだけ
-- default: rules にないアプリの配置 (rules と同じ形式。mode を省略すると画面を移すだけで、サイズは画面に収まるよう調整される)
-- focus:   配置後に前面に出すアプリの bundle ID (省略可)

return {
  home = {
    screens = {
      ["BenQ GW2480"] = "left",
      ["H27T22C-3"] = "center",
      ["BenQ EX2510"] = "right",
    },
    rules = {
      ["com.vivaldi.Vivaldi"] = { screen = "left", mode = "maximize" },
      ["com.cmuxterm.app"] = { screen = "center", mode = "maximize" },
      ["com.tinyspeck.slackmacgap"] = { screen = "right", mode = "fullscreen" },
    },
    default = { screen = "center" },
    focus = "com.cmuxterm.app",
  },

  office = {
    screens = {
      ["DELL S2725QC"] = "main",
      ["Built-in Retina Display"] = "laptop",
    },
    rules = {
      ["com.cmuxterm.app"] = { screen = "main", mode = "left-half" },
      ["com.vivaldi.Vivaldi"] = { screen = "main", mode = "right-half" },
      ["com.tinyspeck.slackmacgap"] = { screen = "laptop", mode = "fullscreen" },
      ["com.google.Chrome"] = { screen = "laptop", mode = "maximize" },
      ["md.obsidian"] = { screen = "laptop", mode = "maximize" },
    },
    default = { screen = "main" },
    focus = "com.cmuxterm.app",
  },

  laptop = {
    -- 内蔵ディスプレイは外部モニター接続時と単体時で名前が変わる (単体時は "Built-in Display")
    screens = {
      ["Built-in Display"] = "laptop",
    },
    rules = {
      ["com.tinyspeck.slackmacgap"] = { screen = "laptop", mode = "fullscreen" },
    },
    default = { screen = "laptop", mode = "maximize" },
    focus = "com.cmuxterm.app",
  },
}
