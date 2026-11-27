-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 Ding Zheng Yuan
--
-- Button-only UI built on app.openDialog, used when GTK bindings are unavailable.
-- app.openDialog(message, buttons, callbackName) is asynchronous and displays plain
-- text (gtk_message_dialog_format_secondary_text, not Pango markup); the callback
-- is a *global* function name receiving the button number.
local apply = require("apply")
local config = require("config")
local units = require("units")

local M = {}

local BUTTONS = {
  [1] = "−2 pt",
  [2] = "+2 pt",
  [3] = "Apply to all pages",
  [4] = "Apply default preset",
  [5] = "Done",
}
local DELTA = { [1] = -2, [2] = 2 }

--- Current page's style (unsupported formats default to lined).
local function currentStyle(app)
  local p = apply.currentPage(app)
  if not p then return nil end
  return config.toStyle(p.format, p.config), p
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
    "Line spacing: %s (%s)\nPage %d of %d — %s\n\n" ..
    "Steps change the current page immediately (%s undoes).\n" ..
    "Install lua-lgi (or LuaGObject) for the full settings dialog.",
    units.format(style.spacing, "pt"),
    units.format(style.spacing, "mm"),
    p.index, p.count, config.LABELS[style.format] or p.format,
    apply.UNDO_KEY)

  -- Global trampoline required by app.openDialog.
  _G.__lineSpacingFallbackResponse = function(button)
    if DELTA[button] then
      local _, err = M.step(app, DELTA[button])
      if err then ctx.notify(err, true) return end
      M.open(ctx) -- reopen with the new value
    elseif button == 3 then
      local r, err = apply.applyStyle(app, style, "all")
      ctx.notify(r and apply.describeResult(r) or err, not r)
    elseif button == 4 then
      local r, err = apply.applyStyle(app, ctx.store:getDefault().style, "current")
      ctx.notify(r and apply.describeResult(r) or err, not r)
    end
  end
  app.openDialog(msg, BUTTONS, "__lineSpacingFallbackResponse")
end

return M
