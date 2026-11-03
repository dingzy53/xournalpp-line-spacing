local units = require("units")

return {
  { "mm to pt", function(T)
    T.near(units.toPt(7.1, "mm"), 20.1259843, 1e-6)
    T.near(units.toPt(25.4, "mm"), 72, 1e-9)
  end },
  { "in to pt and back", function(T)
    T.near(units.toPt(1, "in"), 72)
    T.near(units.fromPt(36, "in"), 0.5)
  end },
  { "round trip all units", function(T)
    for _, u in ipairs(units.UNITS) do
      T.near(units.fromPt(units.toPt(3.3, u), u), 3.3, 1e-12, u)
    end
  end },
  { "format trims zeros", function(T)
    T.eq(units.format(24, "pt"), "24 pt")
    T.eq(units.format(units.toPt(7.1, "mm"), "mm"), "7.1 mm")
    T.eq(units.format(36, "in"), "0.5 in")
    T.eq(units.format(20.5, "pt"), "20.5 pt")
  end },
  { "unknown unit errors", function(T)
    T.ok(not pcall(units.toPt, 1, "cm"))
  end },
}
