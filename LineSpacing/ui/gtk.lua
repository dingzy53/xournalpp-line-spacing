-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 Ding Zheng Yuan
--
-- Locate GTK 3 bindings for Lua.
--   Fedora/Debian packages: lua-lgi        -> require("lgi")
--   Flathub Xournal++:      LuaGObject     -> require("LuaGObject")  (lgi fork)
-- Returns { lgi, Gtk, Gdk, GLib } or nil + reason. The result is cached.
local M = {}

local cached, cachedErr

local function try(modname)
  local ok, lgi = pcall(require, modname)
  if not ok then return nil, modname .. ": " .. tostring(lgi):match("^[^\n]*") end
  local okGtk, Gtk = pcall(lgi.require, "Gtk", "3.0")
  if not okGtk then return nil, modname .. " (Gtk 3.0): " .. tostring(Gtk):match("^[^\n]*") end
  return { lgi = lgi, Gtk = Gtk, Gdk = lgi.require("Gdk", "3.0"), GLib = lgi.GLib, binding = modname }
end

function M.load()
  if cached ~= nil or cachedErr ~= nil then return cached, cachedErr end
  local errs = {}
  for _, name in ipairs({ "lgi", "LuaGObject" }) do
    local b, err = try(name)
    if b then
      cached = b
      return cached
    end
    errs[#errs + 1] = err
  end
  cachedErr = table.concat(errs, "; ")
  return nil, cachedErr
end

return M
