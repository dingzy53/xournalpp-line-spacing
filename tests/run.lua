-- Minimal test runner. Usage (from repo root):  lua tests/run.lua
local root = arg[0]:match("^(.*)/tests/run%.lua$") or "."
package.path = root .. "/LineSpacing/?.lua;" .. root .. "/tests/?.lua;" .. package.path

local T = { passed = 0, failed = 0, root = root }

function T.eq(actual, expected, msg)
  if actual ~= expected then
    error(string.format("%s\n    expected: %s\n    actual:   %s", msg or "values differ",
      tostring(expected), tostring(actual)), 2)
  end
end

function T.near(actual, expected, tol, msg)
  tol = tol or 1e-6
  if type(actual) ~= "number" or math.abs(actual - expected) > tol then
    error(string.format("%s\n    expected: %s (±%g)\n    actual:   %s", msg or "numbers differ",
      tostring(expected), tol, tostring(actual)), 2)
  end
end

function T.ok(v, msg)
  if not v then error(msg or "expected truthy value", 2) end
end

function T.tmpdir()
  local p = os.tmpname()
  os.remove(p)
  assert(os.execute("mkdir -p '" .. p .. "'"))
  return p
end

function T.readFile(path)
  local f = assert(io.open(path, "r"))
  local s = f:read("a")
  f:close()
  return s
end

local files = { "test_units", "test_config", "test_xopt", "test_presets", "test_apply" }
for _, name in ipairs(files) do
  local cases = require(name)
  for _, case in ipairs(cases) do
    local ok, err = pcall(case[2], T)
    if ok then
      T.passed = T.passed + 1
    else
      T.failed = T.failed + 1
      io.stderr:write(string.format("FAIL %s: %s\n  %s\n", name, case[1], err))
    end
  end
end

print(string.format("%d passed, %d failed", T.passed, T.failed))
os.exit(T.failed == 0 and 0 or 1)
