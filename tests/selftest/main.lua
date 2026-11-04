-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 Ding Zheng Yuan
--
-- In-app self test. Runs inside a real Xournal++ against the real `app` API.
-- Environment (set by scripts/selftest.sh):
--   LS_PLUGIN_DIR  path to the LineSpacing plugin folder
--   LS_DOC         a writable copy of tests/fixtures/spacing.xopp
--   LS_OUT         results file
local pluginDir = assert(os.getenv("LS_PLUGIN_DIR"), "LS_PLUGIN_DIR not set")
package.path = pluginDir .. "/?.lua;" .. package.path

local out = assert(io.open(assert(os.getenv("LS_OUT")), "w"))
local failures = 0
local function log(s) out:write(s, "\n"); out:flush() end
local function check(cond, msg)
  log((cond and "ok   " or "FAIL ") .. msg)
  if not cond then failures = failures + 1 end
end

local function steps()
  local apply = require("apply")
  local config = require("config")

  check(app.openFile(os.getenv("LS_DOC"), 1, true), "openFile fixture")
  local snap = apply.snapshot(app)
  check(snap.count == 4, "fixture has 4 pages (got " .. snap.count .. ")")
  check(snap.pages[1].config == "r1=16", "page 1 config read back: " .. snap.pages[1].config)
  coroutine.yield()

  -- 1. config argument honoured on current page
  local s = config.defaultStyle("lined"); s.spacing = 30
  local r = apply.applyStyle(app, s, "current")
  check(r and r.changed == 1, "applyStyle current")
  check(apply.verifyCurrent(app, "lined", "r1=30"), "config argument honoured by this Xournal++ build")
  coroutine.yield()

  -- 2. all pages, restoring the current page
  app.setCurrentPage(2)
  coroutine.yield()
  check(apply.currentPage(app).index == 2, "setCurrentPage(2) takes effect synchronously")
  s.spacing = 22
  r = apply.applyStyle(app, s, "all")
  snap = apply.snapshot(app)
  local allOk = true
  for i, p in ipairs(snap.pages) do
    if p.format ~= "lined" or p.config ~= "r1=22" then
      allOk = false
      log("     page " .. i .. ": " .. p.format .. " " .. p.config)
    end
  end
  check(allOk, "applyStyle all pages -> r1=22 everywhere")
  check(snap.current == 2, "current page restored to 2 (got " .. snap.current .. ")")
  coroutine.yield()

  -- 3. plugin entry points loaded into this state (same code as the real plugin)
  dofile(pluginDir .. "/main.lua")
  lineSpacingStep(1)
  check(apply.currentPage(app).config == "r1=24", "Looser (+2 pt): " .. apply.currentPage(app).config)
  lineSpacingStep(-1); lineSpacingStep(-1)
  check(apply.currentPage(app).config == "r1=20", "Tighter twice: " .. apply.currentPage(app).config)
  lineSpacingReset()
  check(apply.currentPage(app).config == "r1=24", "Reset: " .. apply.currentPage(app).config)
  coroutine.yield()

  -- 4. GTK dialog inside the host
  local gtk, err = require("ui.gtk").load()
  check(gtk ~= nil, "GTK bindings load inside Xournal++ (" .. tostring(gtk and gtk.binding or err) .. ")")
  if gtk then
    local presets = require("presets")
    local dir = os.getenv("LS_OUT") .. ".presets"
    os.execute("mkdir -p '" .. dir .. "'")
    local d = require("ui.dialog").open({
      app = app, gtk = gtk, store = presets.open(dir),
      notify = function(m) log("     notify: " .. m) end,
    })
    coroutine.yield()
    d.widgets.spacingSpin.value = 36
    d.widgets.applyBtn:clicked()
    coroutine.yield()
    check(apply.currentPage(app).config == "r1=36", "dialog Apply: " .. apply.currentPage(app).config)
    d.widgets.previewCheck.active = true
    d.widgets.spacingSpin.value = 50
    coroutine.yield("wait") -- let the 200 ms preview timer fire
    check(apply.currentPage(app).config == "r1=50", "dialog preview: " .. apply.currentPage(app).config)
    d.close()
    coroutine.yield()
    check(apply.currentPage(app).config == "r1=36", "dialog close reverts preview: " .. apply.currentPage(app).config)
    -- open/close repeatedly
    for _ = 1, 5 do
      local dd = require("ui.dialog").open({ app = app, gtk = gtk, store = presets.open(dir), notify = log })
      coroutine.yield()
      dd.close()
    end
    check(true, "dialog opened/closed 5x without crash")
  end

  -- 5. persist
  app.activateAction("save")
  coroutine.yield("wait")

  -- 6. new document with a style (saved doc -> no prompt -> synchronous)
  local g = require("ui.gtk").load()
  local newResult
  local ns = config.defaultStyle("lined"); ns.spacing = 28; ns.marginSide = "right"
  apply.newDocument(app, ns, g and function(fn, ms) g.GLib.timeout_add(g.GLib.PRIORITY_DEFAULT, ms, fn) end,
    function(ok, msg) newResult = { ok, msg } end)
  for _ = 1, 20 do
    if newResult then break end
    coroutine.yield("wait")
  end
  local np = apply.snapshot(app)
  check(newResult and newResult[1], "newDocument reported success: " .. tostring(newResult and newResult[2]))
  check(np.count == 1 and np.pages[1].config == "r1=28,m1=-72", "new document page 1: " .. tostring(np.pages[1] and np.pages[1].config))
  app.activateAction("new-page-after")
  coroutine.yield()
  np = apply.snapshot(app)
  check(np.count == 2 and np.pages[2].config == "r1=28,m1=-72", "inserted page copies spacing: " .. tostring(np.pages[2] and np.pages[2].config))

  -- discard the unsaved new document without a prompt so quitting stays non-interactive
  app.openFile(os.getenv("LS_DOC"), 1, true)
  coroutine.yield()

  -- 7. quit with the dialog still open (must not crash; checked via exit code by the script)
  if gtk then
    require("ui.dialog").open({ app = app, gtk = gtk, store = require("presets").open(nil), notify = log })
    coroutine.yield()
  end
  log("DONE failures=" .. failures)
end

local co = coroutine.create(steps)

local function tick()
  local ok, res = coroutine.resume(co)
  if not ok then
    log("FAIL error: " .. tostring(res))
    log("DONE failures=" .. (failures + 1))
    out:close()
    app.activateAction("quit")
    return
  end
  if coroutine.status(co) == "dead" then
    out:close()
    app.activateAction("quit")
    return
  end
  return res
end

function initUi()
  local okLgi, lgi = pcall(require, "lgi")
  if not okLgi then okLgi, lgi = pcall(require, "LuaGObject") end
  if not okLgi then
    log("FAIL selftest needs lgi to schedule steps: " .. tostring(lgi))
    log("DONE failures=1")
    out:close()
    return
  end
  local GLib = lgi.GLib
  -- Run one step per main-loop tick so Xournal++ can process page changes and redraws.
  GLib.timeout_add(GLib.PRIORITY_DEFAULT, 1500, function()
    local function loop()
      local res = tick()
      if coroutine.status(co) ~= "dead" then
        GLib.timeout_add(GLib.PRIORITY_DEFAULT, res == "wait" and 500 or 100, function() loop() return false end)
      end
    end
    loop()
    return false
  end)
end
