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
local Gtk, Gdk, GLib = gtk.Gtk, gtk.Gdk, gtk.GLib

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
  { format = "ruled", config = "r1=18,lw=1.5,f1=ff0000" },
}, 1)

local dir = os.tmpname(); os.remove(dir); os.execute("mkdir -p " .. dir)
local store = presets.open(dir)
local ctx = {
  app = app, store = store, gtk = gtk,
  notify = function(m) print("notify: " .. m) end,
}

-- 1. Open and close without Apply -> 0 Undo steps
local d = dialog.open(ctx)
local w = d.widgets
pump()
check(w.formatCombo.active_id == "lined", "form loaded from page 1 (lined)")
check(math.abs(w.spacingSpin.value - 24) < 1e-9, "spacing 24 pt from page")
check(w.appearanceExpander.expanded == false, "appearance expander starts collapsed for default page")
d.close(); pump()
check(fake.undoCount == 0, "close without Apply creates 0 undo steps")
check(not dialog.isOpen(), "dialog closed")

-- 2. Reopen, switch unit (persisted), Apply = 1 Undo step
d = dialog.open(ctx); w = d.widgets; pump()
w.unitCombo.active_id = "mm"; pump()
check(math.abs(w.spacingSpin.value - 24 / (72 / 25.4)) < 0.01, "unit switch converts value to mm")
w.spacingSpin.value = 10; pump()
w.sideCombo.active_id = "right"; pump()
w.applyBtn:clicked(); pump()
check(fake.pages[1].config == "r1=28.3465,m1=-72", "apply current: " .. fake.pages[1].config)
check(fake.undoCount == 1, "single Apply creates 1 undo step")
check(presets.open(dir):getUnit() == "mm", "preferred unit persisted to disk")

-- 3. Save preset via popover
w.saveMenuBtn:clicked(); pump()
check(w.savePopover.visible, "save popover opens")
w.nameEntry.text = "Ten mm"
w.saveBtn:clicked(); pump()
check(not w.savePopover.visible, "save popover closes after save")
check(presets.open(dir):get("Ten mm") ~= nil, "preset saved to disk")
check(presets.open(dir):get("Ten mm").unit == "mm", "preset remembers unit")

-- 4. Apply to all pages: pdf page skipped
w.targetCombo.active_id = "all"; pump()
w.applyBtn:clicked(); pump()
check(fake.pages[2].format == ":pdf", "pdf page untouched")
check(fake.pages[3].format == "lined" and fake.pages[3].config == "r1=28.3465,m1=-72", "page 3 changed")
check(fake.current == 1, "current page restored")

-- 5. Escape closes dialog; reopen remembers unit "mm" and expands for custom page
local esc = Gdk.Event.new(Gdk.EventType.KEY_PRESS)
esc.key.window = d.window:get_window()
esc.key.keyval = Gdk.KEY_Escape
d.window:event(esc); pump()
check(not dialog.isOpen(), "Escape closes dialog")

fake.current = 3
fake.pages[3] = { format = "ruled", config = "r1=18,lw=1.5,f1=ff0000" }
d = dialog.open(ctx); w = d.widgets; pump()
check(w.unitCombo.active_id == "mm", "reopened dialog remembers preferred unit")
check(w.appearanceExpander.expanded == true, "appearance expander auto-expands for custom line width/colour")
d.close(); pump()

os.execute("rm -rf " .. dir)
print(failures == 0 and "ALL OK" or (failures .. " failure(s)"))
os.exit(failures == 0 and 0 or 1)
