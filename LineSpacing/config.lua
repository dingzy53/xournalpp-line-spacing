-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 Ding Zheng Yuan
--
-- Background config strings ("r1=24,m1=72,...") <-> Style tables.
--
-- Keys and defaults verified against xournalpp v1.3.7:
--   src/core/model/BackgroundConfig.h          (key names)
--   src/core/view/background/*BackgroundView.* (defaults, semantics)
-- The C++ parser splits on ',' and then on the LAST '=' of each item; values are
-- read with operator>> (numbers) or std::hex (colours, 0xAARRGGBB, alpha ignored).
local M = {}

M.DEFAULT_PAGE_WIDTH = 595.275591

M.FORMATS = { "ruled", "lined", "graph", "dotted" }

M.LABELS = {
  ruled = "Ruled",
  lined = "Ruled + margin line",
  graph = "Graph",
  dotted = "Dotted",
}

-- margin == nil means the format has no margin setting.
M.DEFAULTS = {
  ruled  = { spacing = 24.0,  lineWidth = 0.5 },
  lined  = { spacing = 24.0,  lineWidth = 0.5, margin = 72.0 },
  graph  = { spacing = 14.17, lineWidth = 0.5, margin = 0.0 },
  dotted = { spacing = 14.17, lineWidth = 1.5 },
}

M.LIMITS = {
  spacing   = { 4.0, 200.0 },
  lineWidth = { 0.1, 5.0 },
}

-- Keys this module owns; anything else is passed through untouched.
local OWNED = { r1 = true, m1 = true, lw = true, f1 = true, af1 = true, f2 = true, af2 = true }

function M.isSupported(format)
  return M.DEFAULTS[format] ~= nil
end

function M.hasMargin(format)
  return M.DEFAULTS[format] ~= nil and M.DEFAULTS[format].margin ~= nil
end

-- Only "lined" draws a margin line with its own colour; "graph" margin is a border.
function M.hasMarginSide(format)
  return format == "lined"
end

function M.hasMarginColor(format)
  return format == "lined"
end

--- Parse "k=v,k=v" into an ordered list of {key, value} string pairs.
function M.parse(str)
  local list = {}
  for item in tostring(str or ""):gmatch("[^,]+") do
    local k, v = item:match("^(.*)=(.*)$") -- greedy key: split at the last '='
    if k and k ~= "" then
      list[#list + 1] = { k, v }
    end
  end
  return list
end

--- Compact, locale-independent number formatting: 24 -> "24", 20.1259842 -> "20.126".
function M.formatNumber(n)
  local s = string.format("%.4f", n)
  s = s:gsub("(%.%d-)0+$", "%1"):gsub("%.$", "")
  if s == "-0" then s = "0" end
  return s
end

--- "#RRGGBB" / "rrggbb" / "0xAARRGGBB" / "aarrggbb" -> "#rrggbb", or nil.
function M.normalizeColor(v)
  if type(v) ~= "string" then return nil end
  local hex = v:gsub("^#", ""):gsub("^0[xX]", ""):lower()
  if not hex:match("^%x+$") then return nil end
  if #hex == 8 then
    hex = hex:sub(3) -- drop alpha byte
  elseif #hex ~= 6 then
    return nil
  end
  return "#" .. hex
end

local function colorToConfig(c)
  return c:sub(2) -- "#rrggbb" -> "rrggbb" (verified to render in 1.3.7)
end

local function copyDefaults(format)
  local d = M.DEFAULTS[format]
  local style = {
    format = format,
    spacing = d.spacing,
    lineWidth = d.lineWidth,
    extra = {},
  }
  if d.margin ~= nil then
    style.margin = d.margin
    style.marginSide = "left"
  end
  return style
end

M.defaultStyle = copyDefaults

--- Build a Style from a page's format + config string.
-- Unsupported formats (plain, pdf, image, staves, iso*) yield a default "lined" style,
-- with `sourceFormat` recording what the page really had.
function M.toStyle(format, configStr)
  local fmt = M.isSupported(format) and format or "lined"
  local style = copyDefaults(fmt)
  style.sourceFormat = format

  for _, kv in ipairs(M.parse(configStr)) do
    local k, v = kv[1], kv[2]
    local n = tonumber(v)
    if k == "r1" and n then
      style.spacing = n
    elseif k == "lw" and n then
      style.lineWidth = n
    elseif k == "m1" and n and M.hasMargin(fmt) then
      if n < 0 and M.hasMarginSide(fmt) then
        style.margin, style.marginSide = -n, "right"
      else
        style.margin, style.marginSide = math.abs(n), "left"
      end
    elseif k == "f1" then
      style.color = M.normalizeColor(v)
    elseif k == "f2" then
      style.marginColor = M.normalizeColor(v)
    elseif not OWNED[k] then
      style.extra[#style.extra + 1] = { k, v }
    end
    -- af1/af2 (dark-page colours) are regenerated from f1/f2 on output.
  end
  return style
end

local function near(a, b)
  return math.abs(a - b) < 1e-6
end

--- Style -> format, config string.
-- r1 is always written (explicit is better for users reading the .xopp);
-- other keys only when they differ from the renderer default.
function M.fromStyle(style)
  local fmt = style.format
  assert(M.isSupported(fmt), "unsupported format: " .. tostring(fmt))
  local d = M.DEFAULTS[fmt]
  local out = {}
  local function put(k, v) out[#out + 1] = k .. "=" .. v end

  put("r1", M.formatNumber(style.spacing or d.spacing))

  if d.margin ~= nil and style.margin ~= nil then
    local m = style.margin
    if M.hasMarginSide(fmt) and style.marginSide == "right" then
      put("m1", M.formatNumber(-m))
    elseif not near(m, d.margin) then
      put("m1", M.formatNumber(m))
    end
  end

  if style.lineWidth and not near(style.lineWidth, d.lineWidth) then
    put("lw", M.formatNumber(style.lineWidth))
  end

  local c = M.normalizeColor(style.color)
  if c then
    put("f1", colorToConfig(c))
    put("af1", colorToConfig(c)) -- same colour on dark pages: the user chose it explicitly
  end

  local mc = M.normalizeColor(style.marginColor)
  if mc and M.hasMarginColor(fmt) then
    put("f2", colorToConfig(mc))
    put("af2", colorToConfig(mc))
  end

  for _, kv in ipairs(style.extra or {}) do
    if not OWNED[kv[1]] then
      put(kv[1], kv[2])
    end
  end

  return fmt, table.concat(out, ",")
end

--- Validate a Style. Returns true, or false + message.
function M.validate(style, pageWidth)
  if type(style) ~= "table" then return false, "style must be a table" end
  if not M.isSupported(style.format) then
    return false, "unsupported paper type: " .. tostring(style.format)
  end
  local function inRange(name, v, lo, hi, label)
    if type(v) ~= "number" or v ~= v then
      return false, label .. " must be a number"
    end
    if v < lo or v > hi then
      return false, string.format("%s must be between %s and %s pt", label,
        M.formatNumber(lo), M.formatNumber(hi))
    end
    return true
  end
  local ok, err = inRange("spacing", style.spacing, M.LIMITS.spacing[1], M.LIMITS.spacing[2], "Line spacing")
  if not ok then return false, err end
  ok, err = inRange("lineWidth", style.lineWidth, M.LIMITS.lineWidth[1], M.LIMITS.lineWidth[2], "Line width")
  if not ok then return false, err end
  if M.hasMargin(style.format) and style.margin ~= nil then
    ok, err = inRange("margin", style.margin, 0, pageWidth or 2000, "Margin")
    if not ok then return false, err end
  end
  if style.color ~= nil and not M.normalizeColor(style.color) then
    return false, "invalid line colour: " .. tostring(style.color)
  end
  if style.marginColor ~= nil and not M.normalizeColor(style.marginColor) then
    return false, "invalid margin colour: " .. tostring(style.marginColor)
  end
  return true
end

--- Deep copy (styles are plain data).
function M.copy(t)
  if type(t) ~= "table" then return t end
  local r = {}
  for k, v in pairs(t) do r[k] = M.copy(v) end
  return r
end

--- One-line summary for menus and labels.
function M.describe(style, unit)
  local units = require("units")
  local s = M.LABELS[style.format] .. ", " .. units.format(style.spacing, unit or "pt")
  return s
end

return M
