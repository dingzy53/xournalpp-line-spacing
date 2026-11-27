-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 Ding Zheng Yuan
--
-- Applying styles to pages through the Xournal++ Lua API.
--
-- Every function takes `app` explicitly so it can be unit-tested with a fake.
-- API facts (xournalpp v1.3.7, src/core/plugin/luapi_application.h):
--   * app.getDocumentStructure(): pages[i].pageTypeFormat / pageTypeConfig /
--     pageWidth / pageHeight, currentPage (all 1-based)
--   * pageTypeFormat for PDF/image pages is ":pdf" / ":image"
--   * app.setCurrentPage(n) is 1-based and clamped
--   * app.changeCurrentPageBackground(format, config) - 2nd arg undocumented in
--     luapi_application.def.lua, but read with luaL_optstring since <= 1.3.7.
--     Each call is one undo step.
local config = require("config")

local M = {}

local BACKGROUND_FORMATS = { [":pdf"] = true, [":image"] = true }

function M.isBackgroundPage(format)
  return BACKGROUND_FORMATS[format] == true
end

--- Snapshot of the document: { count, current, pages = { {format, config, width, height}... } }
function M.snapshot(app)
  local doc = app.getDocumentStructure()
  local pages = {}
  for i, p in ipairs(doc.pages or {}) do
    pages[i] = {
      format = p.pageTypeFormat,
      config = p.pageTypeConfig or "",
      width = p.pageWidth,
      height = p.pageHeight,
    }
  end
  return { count = #pages, current = doc.currentPage or 1, pages = pages }
end

--- Info about the current page, or nil if there is no document.
function M.currentPage(app)
  local snap = M.snapshot(app)
  local p = snap.pages[snap.current]
  if not p then return nil end
  return {
    index = snap.current,
    count = snap.count,
    format = p.format,
    config = p.config,
    width = p.width,
    height = p.height,
  }
end

--- Resolve a target spec into a sorted list of page numbers.
-- target = "current" | "all" | { from = n, to = m }
function M.resolveTarget(target, snap)
  local list = {}
  if target == "current" then
    if snap.pages[snap.current] then list[1] = snap.current end
  elseif target == "all" then
    for i = 1, snap.count do list[i] = i end
  elseif type(target) == "table" then
    local a = math.floor(tonumber(target.from) or 1)
    local b = math.floor(tonumber(target.to) or snap.count)
    if a > b then a, b = b, a end
    a, b = math.max(1, a), math.min(snap.count, b)
    for i = a, b do list[#list + 1] = i end
  else
    error("unknown target: " .. tostring(target))
  end
  return list
end

--- Apply a page type to pages.
-- opts.includeBackgrounds: also replace PDF/image backgrounds (default false)
-- Returns { changed = n, skippedBackground = n, unchanged = n }
function M.applyPageType(app, format, cfg, target, opts)
  opts = opts or {}
  local snap = M.snapshot(app)
  local pagesToVisit = M.resolveTarget(target, snap)
  local result = { changed = 0, skippedBackground = 0, unchanged = 0 }
  local original = snap.current
  local moved = false

  for _, n in ipairs(pagesToVisit) do
    local p = snap.pages[n]
    if M.isBackgroundPage(p.format) and not opts.includeBackgrounds then
      result.skippedBackground = result.skippedBackground + 1
    elseif p.format == format and p.config == cfg then
      result.unchanged = result.unchanged + 1
    else
      if n ~= snap.current or moved then
        app.setCurrentPage(n)
        moved = true
      end
      app.changeCurrentPageBackground(format, cfg)
      result.changed = result.changed + 1
    end
  end

  if moved then
    app.setCurrentPage(original)
    if app.scrollToPage then app.scrollToPage(original) end
  end
  return result
end

--- Apply a Style. Returns result table, or nil + error message.
function M.applyStyle(app, style, target, opts)
  local ok, err = config.validate(style)
  if not ok then return nil, err end
  local format, cfg = config.fromStyle(style)
  return M.applyPageType(app, format, cfg, target, opts)
end

--- Check that the running Xournal++ honoured the config argument on the current page.
-- Returns true, or false + actual config.
function M.verifyCurrent(app, format, cfg)
  local p = M.currentPage(app)
  if p and p.format == format and p.config == cfg then return true end
  return false, p and (p.format .. " / " .. p.config) or "no page"
end

--- True if the open document is a fresh one: never saved, one page, nothing drawn,
-- not a PDF/image background. Safe to restyle without touching user content.
function M.isBlankUntitled(app)
  local doc = app.getDocumentStructure()
  local pages = doc.pages or {}
  if (doc.xoppFilename or "") ~= "" or (doc.pdfBackgroundFilename or "") ~= "" then return false end
  if #pages ~= 1 then return false end
  local p = pages[1]
  return not p.isAnnotated and not M.isBackgroundPage(p.pageTypeFormat)
end

--- Create a new document (File → New) and give its first page `style`.
--
-- Xournal++ may first ask whether to save the current document; that prompt is
-- asynchronous, so the new document can appear after activateAction returns.
-- `schedule(fn, ms)` (optional, e.g. a GLib timer) is used to wait for it; `fn`
-- returns true to keep waiting. `done(ok, msg)` is called with the outcome.
-- The style is only ever applied to a blank, untitled, single-page document.
-- (Pages inserted later copy it when "Copy last page settings" is on.)
function M.newDocument(app, style, schedule, done)
  local ok, err = config.validate(style)
  if not ok then done(false, err) return end

  app.activateAction("new-file")

  local function tryApply()
    if not M.isBlankUntitled(app) then return false end
    M.applyStyle(app, style, "current", { includeBackgrounds = false })
    done(true, "New document created.")
    return true
  end

  if tryApply() then return end
  if not schedule then
    done(false, "Finish the save prompt, then use \"Apply default preset\" or the Configure window " ..
      "on the new document.")
    return
  end
  local waited, step, limit = 0, 250, 120000
  schedule(function()
    if tryApply() then return false end
    waited = waited + step
    if waited >= limit then
      done(false, nil) -- user most likely cancelled the save prompt; stay quiet
      return false
    end
    return true
  end, step)
end

--- Human summary of an apply result.
function M.describeResult(r)
  local parts = { string.format("%d page(s) changed", r.changed) }
  if r.unchanged > 0 then parts[#parts + 1] = string.format("%d already matching", r.unchanged) end
  if r.skippedBackground > 0 then
    parts[#parts + 1] = string.format("%d PDF/image page(s) skipped", r.skippedBackground)
  end
  return table.concat(parts, ", ")
end

return M
