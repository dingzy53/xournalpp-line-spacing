-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 Ding Zheng Yuan

local apply = require("apply")
local config = require("config")
local fakeapp = require("fakeapp")

local function doc()
  return {
    { format = "lined", config = "" },
    { format = ":pdf", config = "" },
    { format = "plain", config = "" },
    { format = "lined", config = "r1=30" },
  }
end

local function style30()
  local s = config.defaultStyle("lined")
  s.spacing = 30
  return s
end

return {
  { "current page only", function(T)
    local app, fake = fakeapp.new(doc(), 3)
    local r = apply.applyStyle(app, style30(), "current")
    T.eq(r.changed, 1)
    T.eq(fake.pages[3].format, "lined"); T.eq(fake.pages[3].config, "r1=30")
    T.eq(fake.pages[1].config, "")
    T.eq(#fake.calls, 1, "no page switching needed for the current page")
  end },
  { "all pages skips pdf and matching, restores current page", function(T)
    local app, fake = fakeapp.new(doc(), 3)
    local r = apply.applyStyle(app, style30(), "all")
    T.eq(r.changed, 2); T.eq(r.skippedBackground, 1); T.eq(r.unchanged, 1)
    T.eq(fake.pages[2].format, ":pdf")
    T.eq(fake.pages[1].config, "r1=30")
    T.eq(fake.current, 3, "current page restored")
    T.eq(fake.calls[#fake.calls], "scrollToPage(3)")
  end },
  { "includeBackgrounds replaces pdf page", function(T)
    local app, fake = fakeapp.new(doc(), 1)
    local r = apply.applyStyle(app, style30(), "all", { includeBackgrounds = true })
    T.eq(r.skippedBackground, 0); T.eq(fake.pages[2].format, "lined")
  end },
  { "range is clamped and ordered", function(T)
    local app, fake = fakeapp.new(doc(), 1)
    local r = apply.applyStyle(app, style30(), { from = 9, to = 3 })
    T.eq(r.changed + r.unchanged, 2)
    T.eq(fake.pages[3].config, "r1=30")
    T.eq(fake.pages[1].config, "")
  end },
  { "invalid style is rejected without touching pages", function(T)
    local app, fake = fakeapp.new(doc(), 1)
    local s = style30(); s.spacing = 1
    local r, err = apply.applyStyle(app, s, "all")
    T.eq(r, nil); T.ok(err)
    T.eq(#fake.calls, 0)
  end },
  { "currentPage and verify", function(T)
    local app = fakeapp.new(doc(), 4)
    local p = apply.currentPage(app)
    T.eq(p.index, 4); T.eq(p.count, 4); T.eq(p.config, "r1=30")
    T.ok(apply.verifyCurrent(app, "lined", "r1=30"))
    T.ok(not apply.verifyCurrent(app, "lined", "r1=31"))
  end },
  { "isBlankUntitled", function(T)
    local app, fake = fakeapp.new({ { format = "lined", config = "" } }, 1)
    T.ok(apply.isBlankUntitled(app))
    fake.pages[1].annotated = true
    T.ok(not apply.isBlankUntitled(app), "annotated")
    fake.pages[1].annotated = false; fake.filename = "/x.xopp"
    T.ok(not apply.isBlankUntitled(app), "saved file")
    fake.filename = ""; fake.pages[2] = { format = "lined" }
    T.ok(not apply.isBlankUntitled(app), "two pages")
  end },
  { "newDocument synchronous", function(T)
    local app, fake = fakeapp.new(doc(), 2)
    fake.filename = "/some/file.xopp"
    local result
    apply.newDocument(app, style30(), nil, function(ok, msg) result = { ok, msg } end)
    T.ok(result[1], tostring(result[2]))
    T.eq(#fake.pages, 1); T.eq(fake.pages[1].config, "r1=30")
  end },
  { "newDocument waits for save prompt, never touches old document", function(T)
    local app, fake = fakeapp.new(doc(), 1)
    fake.filename = "/some/file.xopp"
    fake.asyncNew = true
    local pendingFn, result
    local schedule = function(fn) pendingFn = fn end
    apply.newDocument(app, style30(), schedule, function(ok, msg) result = { ok, msg } end)
    T.eq(result, nil, "not done yet")
    T.eq(fake.pages[1].config, "", "old document untouched")
    T.ok(pendingFn() == true, "keeps waiting while prompt is open")
    fake.finishNew()
    T.ok(pendingFn() == false, "stops after applying")
    T.ok(result[1]); T.eq(fake.pages[1].config, "r1=30")
  end },
  { "newDocument gives up quietly if prompt cancelled", function(T)
    local app, fake = fakeapp.new(doc(), 1)
    fake.filename = "/f.xopp"; fake.asyncNew = true
    local pendingFn, result
    apply.newDocument(app, style30(), function(fn) pendingFn = fn end, function(ok, msg) result = { ok, msg } end)
    local n = 0
    while pendingFn() do n = n + 1 end
    T.eq(result[1], false); T.eq(result[2], nil)
    T.ok(n > 100, "polled for a while")
    T.eq(fake.pages[1].config, "")
  end },
  { "newDocument without timer explains next step", function(T)
    local app, fake = fakeapp.new(doc(), 1)
    fake.filename = "/f.xopp"; fake.asyncNew = true
    local result
    apply.newDocument(app, style30(), nil, function(ok, msg) result = { ok, msg } end)
    T.eq(result[1], false); T.ok(result[2]:find("Apply default preset"))
  end },
  { "describeResult", function(T)
    T.eq(apply.describeResult({ changed = 2, unchanged = 1, skippedBackground = 1 }),
      "2 page(s) changed, 1 already matching, 1 PDF/image page(s) skipped")
  end },
}
