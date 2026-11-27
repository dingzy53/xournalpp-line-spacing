-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 Ding Zheng Yuan
--
-- Line Spacing — Xournal++ plugin entry point.
-- Requires Xournal++ >= 1.3.7 (uses the config argument of app.changeCurrentPageBackground).
local apply = require("apply")
local presets = require("presets")
local fallback = require("ui.fallback")

local STEP_PT = 2

local store, storeWarning

local function getStore()
  if not store then
    local ok, dir = pcall(app.getFolder, "config")
    store, storeWarning = presets.open(ok and dir or nil)
  end
  return store
end

local function notify(msg, isError)
  app.openDialog(fallback.escape(msg), { [1] = "OK" }, "", isError == true)
end

local function guarded(fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then
      notify("Line Spacing plugin error:\n" .. tostring(err), true)
    end
  end
end

local function context()
  return { app = app, store = getStore(), notify = notify }
end

---------------------------------------------------------------------------
-- Menu callbacks (must be globals: Xournal++ looks them up by name)
---------------------------------------------------------------------------

lineSpacingConfigure = guarded(function()
  local ctx = context()
  if storeWarning then
    notify(storeWarning, true)
    storeWarning = nil
  end
  local gtk, err = require("ui.gtk").load()
  if gtk then
    ctx.gtk = gtk
    require("ui.dialog").open(ctx)
  else
    print("[LineSpacing] GTK bindings unavailable, using fallback UI: " .. tostring(err))
    fallback.open(ctx)
  end
end)

lineSpacingStep = guarded(function(direction)
  local _, err = fallback.step(app, direction * STEP_PT)
  if err then notify(err, true) end
end)

lineSpacingApplyDefault = guarded(function()
  local r, err = apply.applyStyle(app, getStore():getDefault().style, "current")
  if not r then notify(err, true) end
end)

lineSpacingNewDocument = guarded(function()
  local schedule
  local gtk = require("ui.gtk").load()
  if gtk then
    schedule = function(fn, ms) gtk.GLib.timeout_add(gtk.GLib.PRIORITY_DEFAULT, ms, fn) end
  end
  apply.newDocument(app, getStore():getDefault().style, schedule, function(ok, msg)
    if not ok and msg then notify(msg, true) end
  end)
end)

---------------------------------------------------------------------------

function initUi()
  local parent = { "Line Spacing" }
  app.registerUi({ menu = "Line Spacing…", parentPath = parent, toolbarId = "LINE_SPACING_CONFIGURE",
    callback = "lineSpacingConfigure", accelerator = "<Control><Alt>s", iconName = "preferences-other" })
  app.registerUi({ menu = "Line Spacing: Looser (+" .. STEP_PT .. " pt)", parentPath = parent,
    toolbarId = "LINE_SPACING_LOOSER", callback = "lineSpacingStep", mode = 1,
    accelerator = "<Control><Alt>equal", iconName = "zoom-in" })
  app.registerUi({ menu = "Line Spacing: Tighter (−" .. STEP_PT .. " pt)", parentPath = parent,
    toolbarId = "LINE_SPACING_TIGHTER", callback = "lineSpacingStep", mode = -1,
    accelerator = "<Control><Alt>minus", iconName = "zoom-out" })
  app.registerUi({ menu = "Line Spacing: Apply Default Preset", parentPath = parent,
    toolbarId = "LINE_SPACING_APPLY_DEFAULT", callback = "lineSpacingApplyDefault", iconName = "emblem-default" })
  app.registerUi({ menu = "Line Spacing: New Document (Default Preset)", parentPath = parent,
    toolbarId = "LINE_SPACING_NEW_DOCUMENT", callback = "lineSpacingNewDocument", iconName = "document-new" })
end
