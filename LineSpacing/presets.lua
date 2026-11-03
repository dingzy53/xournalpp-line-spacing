-- Named presets ("templates") of background styles, persisted as a Lua table literal.
--
-- The file is loaded with an empty environment and text mode only, so a tampered
-- presets file cannot call os/io functions. Writes go to a temp file + rename.
local config = require("config")
local units = require("units")

local M = {}

M.VERSION = 1
M.FILE_NAME = "presets.lua"

local function builtin(name, format, spacingPt, unit, extra)
  local style = config.defaultStyle(format)
  style.spacing = spacingPt
  for k, v in pairs(extra or {}) do style[k] = v end
  return { name = name, style = style, unit = unit, builtin = true }
end

-- Always available, never written to disk.
M.BUILTINS = {
  builtin("Default (24 pt)", "lined", 24.0, "pt"),
  builtin("Narrow (20 pt)", "lined", 20.0, "pt"),
  builtin("Large (32 pt)", "lined", 32.0, "pt"),
  builtin("College ruled (7.1 mm)", "lined", units.toPt(7.1, "mm"), "mm",
    { margin = units.toPt(32, "mm") }),
  builtin("Wide ruled (8.7 mm)", "lined", units.toPt(8.7, "mm"), "mm",
    { margin = units.toPt(32, "mm") }),
  builtin("Graph 5 mm", "graph", units.toPt(5, "mm"), "mm"),
  builtin("Dotted 5 mm", "dotted", units.toPt(5, "mm"), "mm"),
}

local function isBuiltinName(name)
  for _, p in ipairs(M.BUILTINS) do
    if p.name == name then return true end
  end
  return false
end

---------------------------------------------------------------------------
-- Serialisation
---------------------------------------------------------------------------

local function serialize(v, indent)
  indent = indent or ""
  local t = type(v)
  if t == "string" then
    return string.format("%q", v)
  elseif t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return "0" end
    if math.type(v) == "integer" then return tostring(v) end
    return string.format("%.17g", v)
  elseif t == "boolean" then
    return tostring(v)
  elseif t == "table" then
    local inner = indent .. "  "
    local parts = {}
    -- array part
    for i = 1, #v do
      parts[#parts + 1] = inner .. serialize(v[i], inner)
    end
    -- hash part, sorted for stable diffs
    local keys = {}
    for k in pairs(v) do
      if not (math.type(k) == "integer" and k >= 1 and k <= #v) then
        keys[#keys + 1] = k
      end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
      local key
      if type(k) == "string" and k:match("^[%a_][%w_]*$") then
        key = k
      else
        key = "[" .. serialize(k) .. "]"
      end
      parts[#parts + 1] = inner .. key .. " = " .. serialize(v[k], inner)
    end
    if #parts == 0 then return "{}" end
    return "{\n" .. table.concat(parts, ",\n") .. ",\n" .. indent .. "}"
  end
  return "nil"
end
M.serialize = serialize

local function sanitizePreset(p)
  if type(p) ~= "table" or type(p.name) ~= "string" or p.name == "" then return nil end
  if type(p.style) ~= "table" then return nil end
  local style = config.copy(p.style)
  style.extra = type(style.extra) == "table" and style.extra or {}
  style.sourceFormat = nil
  if not config.validate(style) then return nil end
  local unit = units.PT_PER[p.unit] and p.unit or "pt"
  return { name = p.name, style = style, unit = unit }
end

--- Parse file text. Returns data table or nil, err.
function M.decode(text)
  local chunk, err = load(text, "=presets", "t", {})
  if not chunk then return nil, err end
  -- Abort pathological files (e.g. infinite loops) after ~1M VM instructions.
  local hasHook = debug and debug.sethook
  if hasHook then
    debug.sethook(function() error("presets file takes too long to load", 2) end, "", 1000000)
  end
  local ok, data = pcall(chunk)
  if hasHook then debug.sethook() end
  if not ok then return nil, data end
  if type(data) ~= "table" or type(data.presets) ~= "table" then
    return nil, "presets file has no 'presets' table"
  end
  local out = { version = M.VERSION, presets = {}, default = nil, dropped = 0 }
  local seen = {}
  for _, p in ipairs(data.presets) do
    local clean = sanitizePreset(p)
    if clean and not seen[clean.name] and not isBuiltinName(clean.name) then
      out.presets[#out.presets + 1] = clean
      seen[clean.name] = true
    else
      out.dropped = out.dropped + 1
    end
  end
  if type(data.default) == "string" then out.default = data.default end
  return out
end

function M.encode(data)
  local plain = { version = M.VERSION, default = data.default, presets = {} }
  for _, p in ipairs(data.presets) do
    plain.presets[#plain.presets + 1] = { name = p.name, style = p.style, unit = p.unit }
  end
  return "-- Line Spacing plugin presets. Generated file; edit with care.\nreturn "
    .. serialize(plain) .. "\n"
end

---------------------------------------------------------------------------
-- Store
---------------------------------------------------------------------------

local Store = {}
Store.__index = Store

--- Open (or create) the preset store in directory `dir`.
-- Returns store, warning (warning set if an existing file was unreadable and backed up).
function M.open(dir)
  local self = setmetatable({
    path = dir and (dir .. "/" .. M.FILE_NAME) or nil,
    data = { version = M.VERSION, presets = {} },
  }, Store)
  local warning = self:load()
  return self, warning
end

function Store:load()
  if not self.path then return nil end
  local f = io.open(self.path, "r")
  if not f then return nil end -- first run
  local text = f:read("a")
  f:close()
  local data, err = M.decode(text)
  if not data then
    local backup = self.path .. ".bak-" .. os.date("%Y%m%d-%H%M%S")
    os.rename(self.path, backup)
    self.data = { version = M.VERSION, presets = {} }
    return "Presets file was unreadable (" .. tostring(err) .. "). Moved to " .. backup
  end
  self.data = data
  if data.dropped > 0 then
    return string.format("%d invalid preset(s) were ignored.", data.dropped)
  end
  return nil
end

function Store:save()
  if not self.path then return true end
  local tmp = self.path .. ".tmp"
  local f, err = io.open(tmp, "w")
  if not f then return false, err end
  local ok, werr = f:write(M.encode(self.data))
  f:close()
  if not ok then
    os.remove(tmp)
    return false, werr
  end
  local rok, rerr = os.rename(tmp, self.path)
  if not rok then return false, rerr end
  return true
end

--- Built-ins first, then user presets in insertion order.
function Store:list()
  local all = {}
  for _, p in ipairs(M.BUILTINS) do all[#all + 1] = p end
  for _, p in ipairs(self.data.presets) do all[#all + 1] = p end
  return all
end

function Store:userPresets()
  return self.data.presets
end

function Store:get(name)
  for _, p in ipairs(self:list()) do
    if p.name == name then return p end
  end
  return nil
end

local function indexOf(list, name)
  for i, p in ipairs(list) do
    if p.name == name then return i end
  end
  return nil
end

--- Insert or overwrite a user preset. Returns true or false, err.
function Store:put(name, style, unit)
  if type(name) ~= "string" then return false, "Preset name is required" end
  name = name:gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then return false, "Preset name is required" end
  if isBuiltinName(name) then return false, "\"" .. name .. "\" is a built-in preset; choose another name" end
  local ok, err = config.validate(style)
  if not ok then return false, err end
  local clean = config.copy(style)
  clean.sourceFormat = nil
  local p = { name = name, style = clean, unit = units.PT_PER[unit] and unit or "pt" }
  local i = indexOf(self.data.presets, name)
  if i then self.data.presets[i] = p else self.data.presets[#self.data.presets + 1] = p end
  return self:save()
end

function Store:remove(name)
  local i = indexOf(self.data.presets, name)
  if not i then return false, "No user preset named \"" .. tostring(name) .. "\"" end
  table.remove(self.data.presets, i)
  if self.data.default == name then self.data.default = nil end
  return self:save()
end

function Store:rename(old, new)
  local i = indexOf(self.data.presets, old)
  if not i then return false, "No user preset named \"" .. tostring(old) .. "\"" end
  if type(new) ~= "string" then return false, "New name is required" end
  new = new:gsub("^%s+", ""):gsub("%s+$", "")
  if new == "" then return false, "New name is required" end
  if new == old then return true end
  if isBuiltinName(new) or indexOf(self.data.presets, new) then
    return false, "A preset named \"" .. new .. "\" already exists"
  end
  self.data.presets[i].name = new
  if self.data.default == old then self.data.default = new end
  return self:save()
end

function Store:setDefault(name)
  if name ~= nil and not self:get(name) then return false, "Unknown preset" end
  self.data.default = name
  return self:save()
end

function Store:getDefault()
  return (self.data.default and self:get(self.data.default)) or M.BUILTINS[1]
end

--- Suggest an unused name like "Lined 28 pt", "Lined 28 pt (2)".
function Store:suggestName(style, unit)
  local base = config.LABELS[style.format]:gsub(" %+ margin line", "") .. " " .. units.format(style.spacing, unit or "pt")
  local name, n = base, 1
  while self:get(name) do
    n = n + 1
    name = string.format("%s (%d)", base, n)
  end
  return name
end

M.isBuiltinName = isBuiltinName

return M
