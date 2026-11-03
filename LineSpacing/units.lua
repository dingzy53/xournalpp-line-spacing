-- Length unit conversions. Xournal++ page coordinates are in PostScript points (1/72 in).
local M = {}

M.UNITS = { "pt", "mm", "in" }

M.PT_PER = {
  pt = 1.0,
  mm = 72.0 / 25.4,
  ["in"] = 72.0,
}

-- Decimal places shown in the UI per unit.
M.DIGITS = { pt = 2, mm = 2, ["in"] = 3 }

-- Spin-button step per unit.
M.STEP = { pt = 0.5, mm = 0.1, ["in"] = 0.01 }

local function check(unit)
  if not M.PT_PER[unit] then
    error("unknown unit: " .. tostring(unit), 3)
  end
end

function M.toPt(value, unit)
  check(unit)
  return value * M.PT_PER[unit]
end

function M.fromPt(pt, unit)
  check(unit)
  return pt / M.PT_PER[unit]
end

-- Human-readable value, trailing zeros trimmed: format(20.1259, "mm") -> "7.1 mm"
function M.format(pt, unit)
  check(unit)
  local s = string.format("%." .. M.DIGITS[unit] .. "f", M.fromPt(pt, unit))
  s = s:gsub("(%.%d-)0+$", "%1"):gsub("%.$", "")
  return s .. " " .. unit
end

return M
