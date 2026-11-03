-- A fake `app` object mimicking the parts of the Xournal++ Lua API we use.
local M = {}

function M.new(pages, current)
  local fake = { pages = pages, current = current or 1, calls = {} }
  local app = {}

  function app.getDocumentStructure()
    local out = { pages = {}, currentPage = fake.current }
    for i, p in ipairs(fake.pages) do
      out.pages[i] = {
        pageTypeFormat = p.format,
        pageTypeConfig = p.config or "",
        pageWidth = p.width or 595.275591,
        pageHeight = p.height or 841.889764,
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
    fake.calls[#fake.calls + 1] = "change(" .. fake.current .. "," .. format .. "," .. tostring(cfg) .. ")"
    local p = fake.pages[fake.current]
    p.format = format
    p.config = cfg or ""
  end

  return app, fake
end

return M
