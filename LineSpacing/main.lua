-- Line Spacing — Xournal++ plugin entry point.
-- Requires Xournal++ >= 1.3.7 (uses the config argument of app.changeCurrentPageBackground).
--
-- Xournal++ prepends this plugin's folder to package.path ("<plugin>/?.lua"), so
-- require("ui.dialog") resolves to <plugin>/ui/dialog.lua.
local apply = require("apply")
local config = require("config")
local presets = require("presets")
local fallback = require("ui.fallback")

local STEP_PT = 2

local store, storeWarning
local menuPresets = {} -- mode index -> preset name, fixed at initUi time

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

lineSpacingReset = guarded(function()
  local p = apply.currentPage(app)
  if not p then return end
  local style = config.toStyle(p.format, p.config)
  if not config.isSupported(p.format) then style = config.defaultStyle("lined") end
  style.spacing = config.DEFAULTS[style.format].spacing
  local _, err = apply.applyStyle(app, style, "current")
  if err then notify(err, true) end
end)

local function applyPreset(p)
  if not p then
    notify("Preset no longer exists.", true)
    return
  end
  local r, err = apply.applyStyle(app, p.style, "current")
  if not r then notify(err, true) end
end

lineSpacingApplyDefault = guarded(function()
  applyPreset(getStore():getDefault())
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

lineSpacingApplyPreset = guarded(function(index)
  applyPreset(getStore():get(menuPresets[index]))
end)

---------------------------------------------------------------------------

function initUi()
  app.registerUi({ menu = "Line spacing: Configure…", callback = "lineSpacingConfigure",
    accelerator = "<Control><Alt>s" }) -- Ctrl+Alt+L locks the screen on KDE
  app.registerUi({ menu = "Line spacing: Looser (+" .. STEP_PT .. " pt)", callback = "lineSpacingStep", mode = 1,
    accelerator = "<Control><Alt>equal" })
  app.registerUi({ menu = "Line spacing: Tighter (−" .. STEP_PT .. " pt)", callback = "lineSpacingStep", mode = -1,
    accelerator = "<Control><Alt>minus" })
  app.registerUi({ menu = "Line spacing: Reset to default", callback = "lineSpacingReset" })
  app.registerUi({ menu = "Line spacing: Apply default preset", callback = "lineSpacingApplyDefault" })
  app.registerUi({ menu = "Line spacing: New document (default preset)", callback = "lineSpacingNewDocument" })

  -- One entry per preset. Xournal++ 1.3.7 has no submenus for plugins (parentPath is
  -- master-only), and entries can only be registered here, so new presets need a restart.
  for i, p in ipairs(getStore():list()) do
    menuPresets[i] = p.name
    app.registerUi({ menu = "Line spacing preset: " .. p.name, callback = "lineSpacingApplyPreset", mode = i })
  end
end
