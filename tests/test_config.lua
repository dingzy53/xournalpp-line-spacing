-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 Ding Zheng Yuan

local config = require("config")

return {
  { "parse splits on last '='", function(T)
    local l = config.parse("r1=24,a=b=c,,noeq,m1=-72")
    T.eq(#l, 3)
    T.eq(l[1][1], "r1"); T.eq(l[1][2], "24")
    T.eq(l[2][1], "a=b"); T.eq(l[2][2], "c")
    T.eq(l[3][1], "m1"); T.eq(l[3][2], "-72")
  end },
  { "parse empty/nil", function(T)
    T.eq(#config.parse(""), 0)
    T.eq(#config.parse(nil), 0)
  end },
  { "formatNumber", function(T)
    T.eq(config.formatNumber(24), "24")
    T.eq(config.formatNumber(24.0), "24")
    T.eq(config.formatNumber(20.1259843), "20.126")
    T.eq(config.formatNumber(-72), "-72")
    T.eq(config.formatNumber(-0.00001), "0")
    T.eq(config.formatNumber(0.5), "0.5")
  end },
  { "normalizeColor", function(T)
    T.eq(config.normalizeColor("#FF0000"), "#ff0000")
    T.eq(config.normalizeColor("00aa00"), "#00aa00")
    T.eq(config.normalizeColor("0xff3333cc"), "#3333cc")
    T.eq(config.normalizeColor("ff3333cc"), "#3333cc")
    T.eq(config.normalizeColor("red"), nil)
    T.eq(config.normalizeColor("#fff"), nil)
    T.eq(config.normalizeColor(nil), nil)
  end },
  { "toStyle defaults for lined", function(T)
    local s = config.toStyle("lined", "")
    T.eq(s.format, "lined"); T.eq(s.spacing, 24.0); T.eq(s.margin, 72.0)
    T.eq(s.marginSide, "left"); T.eq(s.lineWidth, 0.5)
  end },
  { "toStyle reads keys", function(T)
    local s = config.toStyle("lined", "r1=40,m1=-50,lw=1.5,f1=ff0000,af1=ff0000,f2=00aa00")
    T.eq(s.spacing, 40); T.eq(s.margin, 50); T.eq(s.marginSide, "right")
    T.eq(s.lineWidth, 1.5); T.eq(s.color, "#ff0000"); T.eq(s.marginColor, "#00aa00")
    T.eq(#s.extra, 0)
  end },
  { "toStyle unsupported format falls back to ruled", function(T)
    local s = config.toStyle("pdf", "")
    T.eq(s.format, "ruled"); T.eq(s.sourceFormat, "pdf")
    local s2 = config.toStyle("plain", "")
    T.eq(s2.format, "ruled")
  end },
  { "graph margin is a non-negative border", function(T)
    local s = config.toStyle("graph", "m1=40,rm=1,bli=5,blw=1")
    T.eq(s.margin, 40); T.eq(s.marginSide, "left")
    T.eq(#s.extra, 3)
    local _, cfg = config.fromStyle(s)
    T.eq(cfg, "r1=14.17,m1=40,rm=1,bli=5,blw=1")
  end },
  { "fromStyle default lined emits only r1", function(T)
    local fmt, cfg = config.fromStyle(config.defaultStyle("lined"))
    T.eq(fmt, "lined"); T.eq(cfg, "r1=24")
  end },
  { "fromStyle right margin and colours", function(T)
    local s = config.defaultStyle("lined")
    s.spacing = 30; s.marginSide = "right"; s.margin = 72; s.lineWidth = 1
    s.color = "#FF0000"; s.marginColor = "#00aa00"
    local _, cfg = config.fromStyle(s)
    T.eq(cfg, "r1=30,m1=-72,lw=1,f1=ff0000,af1=ff0000,f2=00aa00,af2=00aa00")
  end },
  { "fromStyle drops margin keys for ruled", function(T)
    local s = config.toStyle("lined", "r1=30,m1=-72,f2=00aa00")
    s.format = "ruled"
    local _, cfg = config.fromStyle(s)
    T.eq(cfg, "r1=30")
  end },
  { "round trip preserves unknown keys", function(T)
    local src = "r1=18,lw=0.8,zz=1,foo=bar"
    local _, cfg = config.fromStyle(config.toStyle("ruled", src))
    T.eq(cfg, "r1=18,lw=0.8,zz=1,foo=bar")
  end },
  { "round trip toStyle(fromStyle(x))", function(T)
    local s = config.defaultStyle("lined")
    s.spacing = 21.5; s.margin = 40; s.marginSide = "right"; s.color = "#123456"
    local fmt, cfg = config.fromStyle(s)
    local r = config.toStyle(fmt, cfg)
    T.eq(r.spacing, 21.5); T.eq(r.margin, 40); T.eq(r.marginSide, "right"); T.eq(r.color, "#123456")
  end },
  { "validate", function(T)
    local s = config.defaultStyle("lined")
    T.ok(config.validate(s))
    s.spacing = 2
    local ok, err = config.validate(s)
    T.ok(not ok); T.ok(err:find("Line spacing"), err)
    s.spacing = 0 / 0
    T.ok(not config.validate(s))
    s.spacing = 24; s.margin = 700
    T.ok(not config.validate(s, 595))
    s.margin = 72; s.color = "nope"
    T.ok(not config.validate(s))
    T.ok(not config.validate({ format = "staves", spacing = 24, lineWidth = 0.5 }))
  end },
}
