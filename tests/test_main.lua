-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 Ding Zheng Yuan

local fakeapp = require("fakeapp")

local function loadMain(T, pages, current, opts)
  opts = opts or {}
  for _, m in ipairs({ "apply", "config", "presets", "units", "ui.fallback", "ui.gtk", "ui.dialog", "main" }) do
    package.loaded[m] = nil
  end
  if opts.noGtk then
    package.loaded["ui.gtk"] = { load = function() return nil, "no lgi" end }
  end
  local app, fake = fakeapp.new(pages or {
    { format = "lined", config = "" },
    { format = ":pdf", config = "" },
    { format = "ruled", config = "r1=18" },
  }, current or 1)
  fake.configDir = opts.configDir or T.tmpdir()
  _G.app = app
  dofile(T.root .. "/LineSpacing/main.lua")
  return app, fake
end

return {
  { "initUi registers 5 static menu entries with valid globals", function(T)
    local app, fake = loadMain(T)
    fake.runInitUi()
    T.eq(#fake.registered, 5)
    local seen = {}
    for _, item in ipairs(fake.registered) do
      T.ok(type(item.menu) == "string" and item.menu ~= "")
      T.ok(type(_G[item.callback]) == "function", "missing global " .. tostring(item.callback))
      T.ok(item.toolbarId and not seen[item.toolbarId], "unique toolbarId " .. tostring(item.toolbarId))
      seen[item.toolbarId] = true
      T.eq(item.parentPath[1], "Line Spacing")
    end
    local ok = pcall(app.registerUi, { menu = "Late", callback = "lineSpacingConfigure" })
    T.eq(ok, false, "registerUi outside initUi must error")
  end },

  { "lineSpacingStep respects bounds and skips PDF pages", function(T)
    local _, fake = loadMain(T, {
      { format = "lined", config = "r1=4" },
      { format = ":pdf", config = "" },
    }, 1)
    lineSpacingStep(-1)
    T.eq(fake.pages[1].config, "r1=4", "clamped at lower bound")
    lineSpacingStep(1)
    T.eq(fake.pages[1].config, "r1=6")

    fake.current = 2
    lineSpacingStep(1)
    T.eq(fake.pages[2].format, ":pdf")
    T.eq(#fake.dialogs, 1)
    T.eq(fake.dialogs[1].error, true)
  end },

  { "lineSpacingApplyDefault and lineSpacingNewDocument", function(T)
    local _, fake = loadMain(T, { { format = "ruled", config = "r1=14" } }, 1)
    lineSpacingApplyDefault()
    T.eq(fake.pages[1].format, "lined")
    T.eq(fake.pages[1].config, "r1=24")

    fake.filename = "/tmp/doc.xopp"
    lineSpacingNewDocument()
    T.eq(#fake.pages, 1)
    T.eq(fake.pages[1].format, "lined")
    T.eq(fake.pages[1].config, "r1=24")
  end },

  { "fallback UI handles step, apply all, default preset, and Done", function(T)
    local _, fake = loadMain(T, nil, 1, { noGtk = true })
    lineSpacingConfigure()
    T.eq(#fake.dialogs, 1)
    T.ok(fake.dialogs[1].msg:find("24 pt", 1, true))
    T.ok(not fake.dialogs[1].msg:find("<b>", 1, true))
    T.ok(not fake.dialogs[1].msg:find("<small>", 1, true))

    -- Button 2: +2 pt -> applies immediately and reopens dialog with 26 pt
    _G.__lineSpacingFallbackResponse(2)
    T.eq(fake.pages[1].config, "r1=26")
    T.eq(#fake.dialogs, 2)
    T.ok(fake.dialogs[2].msg:find("26 pt", 1, true))

    -- Button 3: Apply to all pages (page 2 :pdf untouched)
    _G.__lineSpacingFallbackResponse(3)
    T.eq(fake.pages[3].format, "lined")
    T.eq(fake.pages[3].config, "r1=26")
    T.eq(fake.pages[2].format, ":pdf")
    T.eq(fake.dialogs[#fake.dialogs].error, false)

    -- Button 4: Apply default preset
    _G.__lineSpacingFallbackResponse(4)
    T.eq(fake.pages[1].config, "r1=24")

    -- Button 5: Done (no-op)
    local before = #fake.dialogs
    _G.__lineSpacingFallbackResponse(5)
    T.eq(#fake.dialogs, before)
  end },

  { "storeWarning passes plain path text without HTML escaping and only shows once", function(T)
    local dir = T.tmpdir() .. "/bad&<dir>"
    assert(os.execute("mkdir -p '" .. dir .. "'"))
    local f = assert(io.open(dir .. "/presets.lua", "w"))
    f:write("return {{{ broken")
    f:close()

    local _, fake = loadMain(T, nil, 1, { noGtk = true, configDir = dir })
    lineSpacingConfigure()
    T.eq(#fake.dialogs, 2) -- warning + fallback UI
    T.eq(fake.dialogs[1].error, true)
    T.ok(fake.dialogs[1].msg:find("bad&<dir>", 1, true), fake.dialogs[1].msg)
    T.ok(not fake.dialogs[1].msg:find("&amp;", 1, true), fake.dialogs[1].msg)

    lineSpacingConfigure()
    T.eq(#fake.dialogs, 3, "warning not repeated")
  end },
}
