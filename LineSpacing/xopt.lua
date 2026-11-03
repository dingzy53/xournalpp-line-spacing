-- Build Xournal++ page-template (.xopt) files.
--
-- Format verified against xournalpp v1.3.7 src/core/control/settings/PageTemplateSettings.cpp
-- (parse/toString). Load the file via Journal -> Configure Page Template -> Load from file.
-- New documents then start with this background; with copyLastPageSettings=true,
-- inserted pages copy the previous page's background (including its config string).
local config = require("config")

local M = {}

M.A4 = { width = 595.275591, height = 841.889764 }

--- opts = {
---   style = Style,                   -- required
---   width, height = number (pt),     -- default A4
---   backgroundColor = "#rrggbb",     -- default white
---   copyLastPageSettings = bool,     -- default true
---   copyLastPageSize = bool,         -- default false
--- }
function M.build(opts)
  assert(type(opts) == "table" and type(opts.style) == "table", "xopt.build: opts.style required")
  local format, cfg = config.fromStyle(opts.style)
  local w = opts.width or M.A4.width
  local h = opts.height or M.A4.height
  local bg = config.normalizeColor(opts.backgroundColor) or "#ffffff"
  local copySettings = opts.copyLastPageSettings ~= false
  local copySize = opts.copyLastPageSize == true

  local lines = {
    "xoj/template",
    "copyLastPageSize=" .. tostring(copySize),
    "copyLastPageSettings=" .. tostring(copySettings),
    string.format("size=%.6fx%.6f", w, h),
    "backgroundType=" .. format,
    "backgroundTypeConfig=" .. cfg,
    "backgroundColor=" .. bg,
  }
  return table.concat(lines, "\n") .. "\n"
end

--- Safe file name from a preset name: "College ruled (7.1 mm)" -> "College-ruled-7.1-mm.xopt"
function M.fileName(name)
  local s = tostring(name or "template"):gsub("[^%w%.%-_]+", "-"):gsub("%-+", "-"):gsub("^%-", ""):gsub("%-$", "")
  if s == "" then s = "template" end
  return s .. ".xopt"
end

function M.write(path, text)
  local f, err = io.open(path, "w")
  if not f then return false, err end
  local ok, werr = f:write(text)
  f:close()
  if not ok then return false, werr end
  return true
end

return M
