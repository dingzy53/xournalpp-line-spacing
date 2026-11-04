-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 Ding Zheng Yuan
--
-- Render the dialog (with a fake app) to docs/dialog.png. Usage: lua scripts/screenshot.lua
local root = arg[0]:match("^(.*)/scripts/screenshot%.lua$") or "."
package.path = root .. "/LineSpacing/?.lua;" .. root .. "/tests/?.lua;" .. package.path
local gtk = assert(require("ui.gtk").load())
local Gtk = gtk.Gtk
local app = require("fakeapp").new({ { format = "lined", config = "r1=28.3465,m1=-72" }, { format = "lined", config = "" } }, 1)
local d = require("ui.dialog").open({ app = app, gtk = gtk, store = require("presets").open(nil), notify = print })
d.widgets.unitCombo.active_id = "mm"
d.widgets.presetCombo.active_id = nil
-- Move the dialog content into an offscreen window and snapshot it.
local content = d.window:get_child()
d.window:remove(content)
local off = Gtk.OffscreenWindow()
local frame = Gtk.EventBox { border_width = 12 }
frame:add(content)
off:add(frame)
off:show_all()
for _ = 1, 50 do while Gtk.events_pending() do Gtk.main_iteration() end end
off:get_pixbuf():savev(root .. "/docs/dialog.png", "png", {}, {})
d.close()
