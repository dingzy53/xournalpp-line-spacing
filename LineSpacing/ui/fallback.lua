-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 Ding Zheng Yuan
--
-- Button-only UI built on app.openDialog, used when GTK bindings are unavailable.
-- app.openDialog(message, buttons, callbackName) is asynchronous and renders Pango
-- markup; the callback is a *global* function name receiving the button number.
local apply = require("apply")
local config = require("config")
local units = require("units")

local M = {}

local BUTTONS = {
  [1] = "−4 pt",
  [2] = "−1 pt",
  [3] = "+1 pt",
  [4] = "+4 pt",
  [5] = "Apply to all pages",
  [6] = "Save as preset",
  [7] = "Done",
}
local DELTA = { [1] = -4, [2] = -1, [3] = 1, [4] = 4 }

local function escape(s)
  return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end
M.escape = escape

--- Current page's style (unsupported formats are converted to a default lined style).
local function currentStyle(app)
  local p = apply.currentPage(app)
  if not p then return nil end
  local style = config.toStyle(p.format, p.config)
  if not config.isSupported(p.format) then style = config.defaultStyle("lined") end
  return style, p
end

--- Change spacing of the current page by `delta` pt. Returns new style or nil, err.
function M.step(app, delta)
  local style, p = currentStyle(app)
  if not style then return nil, "No page" end
  if apply.isBackgroundPage(p.format) then
    return nil, "The current page has a PDF/image background; use the Configure dialog to replace it."
  end
  local lo, hi = config.LIMITS.spacing[1], config.LIMITS.spacing[2]
  style.spacing = math.max(lo, math.min(hi, style.spacing + delta))
  local r, err = apply.applyStyle(app, style, "current")
  if not r then return nil, err end
  return style
end

--- Open the step dialog. `ctx` = { app, store, notify(msg, isError) }
function M.open(ctx)
  local app = ctx.app
  local style, p = currentStyle(app)
  if not style then return end

  local msg = string.format(
    "<b>Line spacing: %s</b> (%s)\nPage %d of %d — %s\n\n" ..
    "Steps change the current page immediately (Ctrl+Z undoes).\n" ..
    "<small>Install lua-lgi for the full settings dialog.</small>",
    escape(units.format(style.spacing, "pt")),
    escape(units.format(style.spacing, "mm")),
    p.index, p.count, escape(config.LABELS[style.format] or p.format))

  -- Global trampoline required by app.openDialog.
  _G.__lineSpacingFallbackResponse = function(button)
    if DELTA[button] then
      local _, err = M.step(app, DELTA[button])
      if err then ctx.notify(err, true) return end
      M.open(ctx) -- reopen with the new value
    elseif button == 5 then
      local r, err = apply.applyStyle(app, style, "all")
      ctx.notify(r and apply.describeResult(r) or err, not r)
    elseif button == 6 then
      local name = ctx.store:suggestName(style, "pt")
      local ok, err = ctx.store:put(name, style, "pt")
      ctx.notify(ok and ("Saved preset \"" .. name .. "\". It appears in the menu after restarting Xournal++.") or err,
        not ok)
    end
  end
  app.openDialog(msg, BUTTONS, "__lineSpacingFallbackResponse")
end

return M
