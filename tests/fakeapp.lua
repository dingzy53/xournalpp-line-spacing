-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 Ding Zheng Yuan
--
-- A fake `app` object mimicking the parts of the Xournal++ Lua API we use.
local M = {}

local function checkPlainText(msg)
  local s = tostring(msg or "")
  if s:find("</?[bsi][^>]*>") then
    error("raw markup tags in app.openDialog (plain text only): " .. s)
  end
end

function M.new(pages, current)
  local fake = {
    pages = pages,
    current = current or 1,
    calls = {},
    undoCount = 0,
    filename = "",
    registered = {},
    inInitUi = false,
    dialogs = {},
    configDir = nil,
  }
  local app = {}

  function fake.runInitUi()
    fake.inInitUi = true
    local ok, err = pcall(_G.initUi)
    fake.inInitUi = false
    if not ok then error(err, 2) end
  end

  function app.getDocumentStructure()
    local out = { pages = {}, currentPage = fake.current, xoppFilename = fake.filename, pdfBackgroundFilename = "" }
    for i, p in ipairs(fake.pages) do
      out.pages[i] = {
        pageTypeFormat = p.format,
        pageTypeConfig = p.config or "",
        pageWidth = p.width or 595.275591,
        pageHeight = p.height or 841.889764,
        isAnnotated = p.annotated == true,
      }
    end
    return out
  end

  function app.setCurrentPage(n)
    fake.calls[#fake.calls + 1] = "setCurrentPage(" .. n .. ")"
    fake.current = math.max(1, math.min(#fake.pages, n))
  end

  function app.scrollToPage(n)
    fake.calls[#fake.calls + 1] = "scrollToPage(" .. n .. ")"
  end

  function app.changeCurrentPageBackground(format, cfg)
    fake.undoCount = fake.undoCount + 1
    fake.calls[#fake.calls + 1] = "change(" .. fake.current .. "," .. format .. "," .. tostring(cfg) .. ")"
    local p = fake.pages[fake.current]
    p.format = format
    p.config = cfg or ""
  end

  -- "new-file": synchronous unless fake.asyncNew is set, in which case
  -- fake.finishNew() completes it (simulating the save prompt).
  function app.activateAction(name)
    fake.calls[#fake.calls + 1] = "action(" .. name .. ")"
    if name == "new-file" then
      local function finish()
        fake.pages = { { format = "lined", config = "" } }
        fake.current, fake.filename = 1, ""
      end
      if fake.asyncNew then fake.finishNew = finish else finish() end
    end
  end

  function app.registerUi(opts)
    if not fake.inInitUi then
      error("registerUi needs to be called within initUi()")
    end
    if type(opts) ~= "table" or type(opts.callback) ~= "string" or opts.callback == "" then
      error("Missing callback function!")
    end
    fake.registered[#fake.registered + 1] = opts
    return { menuId = #fake.registered }
  end

  function app.openDialog(msg, buttons, cb, isError)
    checkPlainText(msg)
    fake.dialogs[#fake.dialogs + 1] = { msg = msg, buttons = buttons, cb = cb, error = isError == true }
  end

  function app.getFolder(kind)
    return fake.configDir or os.getenv("TMPDIR") or "/tmp"
  end

  return app, fake
end

return M
