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
    list[1] = snap.current
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
