-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 Ding Zheng Yuan

local config = require("config")
local xopt = require("xopt")

return {
  { "build matches golden output", function(T)
    local s = config.defaultStyle("lined")
    s.spacing = 30; s.marginSide = "right"
    local text = xopt.build({ style = s })
    T.eq(text, T.readFile(T.root .. "/tests/fixtures/golden.xopt"))
  end },
  { "build options", function(T)
    local text = xopt.build({
      style = config.defaultStyle("graph"), width = 612, height = 792,
      backgroundColor = "#202020", copyLastPageSettings = false, copyLastPageSize = true,
    })
    T.ok(text:find("^xoj/template\n"))
    T.ok(text:find("\ncopyLastPageSize=true\n", 1, true))
    T.ok(text:find("\ncopyLastPageSettings=false\n", 1, true))
    T.ok(text:find("\nsize=612.000000x792.000000\n", 1, true))
    T.ok(text:find("\nbackgroundType=graph\n", 1, true))
    T.ok(text:find("\nbackgroundTypeConfig=r1=14.17\n", 1, true))
    T.ok(text:find("\nbackgroundColor=#202020\n", 1, true))
  end },
  { "fileName is filesystem-safe", function(T)
    T.eq(xopt.fileName("College ruled (7.1 mm)"), "College-ruled-7.1-mm.xopt")
    T.eq(xopt.fileName("../../etc/x"), "..-..-etc-x.xopt")
    T.eq(xopt.fileName("***"), "template.xopt")
  end },
}
