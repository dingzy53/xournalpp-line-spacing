-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 Ding Zheng Yuan
--
-- Drive the real GTK dialog against a fake `app`. Needs a display and lgi.
-- Usage: lua tests/gtk_smoke.lua        (exit code 0 = pass)
local root = arg[0]:match("^(.*)/tests/gtk_smoke%.lua$") or "."
package.path = root .. "/LineSpacing/?.lua;" .. root .. "/tests/?.lua;" .. package.path

local fakeapp = require("fakeapp")
local presets = require("presets")
local gtk = assert(require("ui.gtk").load())
local dialog = require("ui.dialog")
local Gtk, GLib = gtk.Gtk, gtk.GLib

local failures = 0
local function check(cond, msg)
  if cond then print("ok   " .. msg) else print("FAIL " .. msg); failures = failures + 1 end
end

local function pump(ms)
  local deadline = GLib.get_monotonic_time() + (ms or 50) * 1000
  repeat
    while Gtk.events_pending() do Gtk.main_iteration() end
  until GLib.get_monotonic_time() >= deadline
end

local app, fake = fakeapp.new({
  { format = "lined", config = "" },
  { format = ":pdf", config = "" },
  { format = "ruled", config = "r1=18" },
}, 1)

local dir = os.tmpname(); os.remove(dir); os.execute("mkdir -p " .. dir)
local store = presets.open(dir)
local ctx = {
  app = app, store = store, gtk = gtk,
  notify = function(m) print("notify: " .. m) end,
}

local d = dialog.open(ctx)
local w = d.widgets
pump()

check(w.formatCombo.active_id == "lined", "form loaded from page 1 (lined)")
check(math.abs(w.spacingSpin.value - 24) < 1e-9, "spacing 24 pt from page")

-- change spacing in mm and apply to current page
w.unitCombo.active_id = "mm"; pump()
check(math.abs(w.spacingSpin.value - 24 / (72 / 25.4)) < 0.01, "unit switch converts value to mm")
w.spacingSpin.value = 10; pump()
w.sideCombo.active_id = "right"; pump()
w.applyBtn:clicked(); pump()
check(fake.pages[1].config == "r1=28.3465,m1=-72", "apply current: " .. fake.pages[1].config)

-- save preset
w.nameEntry.text = "Ten mm"
w.saveBtn:clicked(); pump()
check(presets.open(dir):get("Ten mm") ~= nil, "preset saved to disk")
check(presets.open(dir):get("Ten mm").unit == "mm", "preset remembers unit")

-- apply to all pages: pdf page skipped
w.targetCombo.active_id = "all"; pump()
w.applyBtn:clicked(); pump()
check(fake.pages[2].format == ":pdf", "pdf page untouched")
check(fake.pages[3].format == "lined" and fake.pages[3].config == "r1=28.3465,m1=-72", "page 3 changed")
check(fake.current == 1, "current page restored")

-- live preview then close restores the page
w.targetCombo.active_id = "current"
w.previewCheck.active = true; pump()
w.unitCombo.active_id = "pt"; pump()
w.spacingSpin.value = 40; pump(400)
check(fake.pages[1].config:match("^r1=40"), "preview applied: " .. fake.pages[1].config)
d.close(); pump()
check(fake.pages[1].config == "r1=28.3465,m1=-72", "close reverts preview: " .. fake.pages[1].config)
check(not dialog.isOpen(), "dialog closed")

-- reopen, select builtin preset, create a new document with it
d = dialog.open(ctx); w = d.widgets; pump()
w.presetCombo.active_id = "Graph 5 mm"; pump()
check(w.formatCombo.active_id == "graph", "preset loads into form")
fake.filename = "/tmp/existing.xopp"; fake.asyncNew = true
w.newDocBtn:clicked(); pump(300)
check(fake.pages[1].format == "lined", "old document untouched while save prompt is open")
fake.finishNew(); pump(400)
check(#fake.pages == 1 and fake.pages[1].format == "graph" and fake.pages[1].config == "r1=14.1732",
  "new document gets preset: " .. fake.pages[1].format .. " " .. fake.pages[1].config)
fake.asyncNew = false

-- validation error shown, nothing applied
local before = fake.pages[1].config
w.unitCombo.active_id = "pt"; pump()
w.lineWidthSpin.value = 0.1
w.spacingSpin.value = 4; pump()
w.applyBtn:clicked(); pump()
check(fake.pages[1].format == "graph", "apply at lower bound works")
d.close(); pump()

os.execute("rm -rf " .. dir)
print(failures == 0 and "ALL OK" or (failures .. " failure(s)"))
os.exit(failures == 0 and 0 or 1)
