-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 Ding Zheng Yuan

local config = require("config")
local presets = require("presets")

local function style(spacing)
  local s = config.defaultStyle("lined")
  s.spacing = spacing
  return s
end

return {
  { "builtins present and valid", function(T)
    T.ok(#presets.BUILTINS >= 5)
    for _, p in ipairs(presets.BUILTINS) do
      T.ok(config.validate(p.style), p.name)
    end
  end },
  { "put/get/save/reload", function(T)
    local dir = T.tmpdir()
    local store = presets.open(dir)
    T.ok(store:put("Mine 30pt", style(30), "pt"))
    T.ok(store:put("Mine mm", style(20), "mm"))
    local again = presets.open(dir)
    local p = again:get("Mine 30pt")
    T.ok(p, "preset reloaded")
    T.eq(p.style.spacing, 30); T.eq(p.unit, "pt")
    T.eq(#again:userPresets(), 2)
    T.eq(#again:list(), #presets.BUILTINS + 2)
  end },
  { "overwrite keeps order", function(T)
    local store = presets.open(T.tmpdir())
    store:put("A", style(20)); store:put("B", style(22)); store:put("A", style(26))
    local u = store:userPresets()
    T.eq(u[1].name, "A"); T.eq(u[1].style.spacing, 26); T.eq(#u, 2)
  end },
  { "builtin names are reserved", function(T)
    local store = presets.open(T.tmpdir())
    local ok, err = store:put(presets.BUILTINS[1].name, style(30))
    T.ok(not ok); T.ok(err:find("built%-in"), err)
  end },
  { "invalid style rejected", function(T)
    local store = presets.open(T.tmpdir())
    T.ok(not store:put("bad", style(1)))
    T.ok(not store:put("   ", style(30)))
  end },
  { "rename and remove and default", function(T)
    local dir = T.tmpdir()
    local store = presets.open(dir)
    store:put("A", style(20)); store:put("B", style(22))
    T.ok(store:setDefault("A"))
    T.ok(store:rename("A", "C"))
    T.eq(store:getDefault().name, "C")
    T.ok(not store:rename("C", "B"), "rename onto existing name")
    T.ok(store:remove("C"))
    T.eq(store:getDefault().name, presets.BUILTINS[1].name)
    T.ok(not store:remove("nope"))
    T.eq(#presets.open(dir):userPresets(), 1)
  end },
  { "corrupted file is backed up", function(T)
    local dir = T.tmpdir()
    local f = io.open(dir .. "/presets.lua", "w"); f:write("return {{{ nope"); f:close()
    local store, warning = presets.open(dir)
    T.ok(warning and warning:find("unreadable"), tostring(warning))
    T.eq(#store:userPresets(), 0)
    T.ok(io.open(dir .. "/presets.lua", "r") == nil, "original moved away")
  end },
  { "presets file runs sandboxed", function(T)
    local dir = T.tmpdir()
    local marker = dir .. "/pwned"
    local f = io.open(dir .. "/presets.lua", "w")
    f:write("os.execute('touch " .. marker .. "') return { presets = {} }")
    f:close()
    local _, warning = presets.open(dir)
    T.ok(warning, "load must fail without os")
    T.ok(io.open(marker, "r") == nil, "code in presets file must not run")
  end },
  { "infinite loop in presets file is aborted", function(T)
    local _, err = presets.decode("while true do end")
    T.ok(err, "expected an error")
  end },
  { "invalid entries dropped with warning", function(T)
    local dir = T.tmpdir()
    local f = io.open(dir .. "/presets.lua", "w")
    f:write([[return { presets = {
      { name = "ok", unit = "mm", style = { format = "ruled", spacing = 20, lineWidth = 0.5 } },
      { name = "bad", style = { format = "ruled", spacing = -1, lineWidth = 0.5 } },
      { name = "ok", style = { format = "ruled", spacing = 30, lineWidth = 0.5 } },
      "junk",
    } }]])
    f:close()
    local store, warning = presets.open(dir)
    T.eq(#store:userPresets(), 1)
    T.ok(warning and warning:find("3 invalid"), tostring(warning))
  end },
  { "serialize is loadable and stable", function(T)
    local data = { presets = { { name = "q\"uote\n", unit = "pt", style = style(24.25) } } }
    local text = presets.encode(data)
    T.eq(text, presets.encode(presets.decode(text)))
    T.eq(presets.decode(text).presets[1].name, "q\"uote\n")
  end },
  { "suggestName avoids clashes", function(T)
    local store = presets.open(T.tmpdir())
    local n1 = store:suggestName(style(28), "pt")
    T.eq(n1, "Ruled 28 pt")
    store:put(n1, style(28))
    T.eq(store:suggestName(style(28), "pt"), "Ruled 28 pt (2)")
  end },
}
