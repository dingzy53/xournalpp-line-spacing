-- GTK 3 settings dialog (via lgi / LuaGObject).
--
-- Non-modal and non-blocking: no Gtk.main(), no dialog:run(). Xournal++ already
-- runs the GTK main loop; our signal handlers execute inside it.
local apply = require("apply")
local config = require("config")
local units = require("units")
local xopt = require("xopt")

local M = {}

local instance -- the single open dialog, if any

local TARGETS = { "current", "all", "range" }
local TARGET_LABELS = { current = "Current page", all = "All pages", range = "Page range" }

--- ctx = {
---   app, store, gtk = ui.gtk.load() result,
---   notify(msg, isError),       -- fallback notification (app.openDialog)
---   onPresetsChanged(),         -- optional
---   saveDialog(suggestedName, cb(path)) -- optional, defaults to app.fileDialogSave
--- }
function M.open(ctx)
  if instance then
    instance.window:present()
    instance.reloadFromPage()
    return instance
  end

  local app, store = ctx.app, ctx.store
  local Gtk, Gdk, GLib = ctx.gtk.Gtk, ctx.gtk.Gdk, ctx.gtk.GLib

  local self = {}
  local updating = false   -- suppress change handlers while filling widgets
  local unit = "pt"
  local style = config.defaultStyle("lined")
  local preview = { active = false, original = nil, timer = nil }

  ---------------------------------------------------------------------------
  -- Widgets
  ---------------------------------------------------------------------------
  local function label(text, opts)
    local l = Gtk.Label { label = text, xalign = 0 }
    for k, v in pairs(opts or {}) do l[k] = v end
    return l
  end

  local function spin(lower, upper, step, digits)
    return Gtk.SpinButton {
      adjustment = Gtk.Adjustment { lower = lower, upper = upper, step_increment = step,
        page_increment = step * 10 },
      digits = digits, numeric = true, width_chars = 7,
    }
  end

  local presetCombo = Gtk.ComboBoxText { hexpand = true }
  local deleteBtn = Gtk.Button { label = "Delete" }
  local defaultBtn = Gtk.Button { label = "Set default" }
  local nameEntry = Gtk.Entry { placeholder_text = "Preset name", hexpand = true }
  local saveBtn = Gtk.Button { label = "Save preset" }

  local formatCombo = Gtk.ComboBoxText()
  for _, f in ipairs(config.FORMATS) do formatCombo:append(f, config.LABELS[f]) end

  local spacingSpin = spin(1, 1000, 0.5, 2)
  local unitCombo = Gtk.ComboBoxText()
  for _, u in ipairs(units.UNITS) do unitCombo:append(u, u) end
  local spacingPtLabel = label("", { hexpand = true })

  local marginLabel = label("Margin:")
  local marginSpin = spin(0, 10000, 1, 2)
  local marginUnitLabel = label("pt")
  local sideCombo = Gtk.ComboBoxText()
  sideCombo:append("left", "Left")
  sideCombo:append("right", "Right")

  local lineWidthSpin = spin(config.LIMITS.lineWidth[1], config.LIMITS.lineWidth[2], 0.1, 2)

  local colorCheck = Gtk.CheckButton { label = "Line colour" }
  local colorBtn = Gtk.ColorButton()
  local marginColorCheck = Gtk.CheckButton { label = "Margin colour" }
  local marginColorBtn = Gtk.ColorButton()

  local targetCombo = Gtk.ComboBoxText()
  for _, t in ipairs(TARGETS) do targetCombo:append(t, TARGET_LABELS[t]) end
  local fromSpin = spin(1, 1, 1, 0)
  local toSpin = spin(1, 1, 1, 0)
  local rangeBox = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 6,
    label("from"), fromSpin, label("to"), toSpin }
  local includeBgCheck = Gtk.CheckButton { label = "Also replace PDF/image backgrounds" }
  local previewCheck = Gtk.CheckButton { label = "Live preview on current page" }

  local status = label("", { wrap = true, max_width_chars = 50, selectable = true })

  local readBtn = Gtk.Button { label = "Read from page" }
  local exportBtn = Gtk.Button { label = "Export as page template (.xopt)…" }
  local closeBtn = Gtk.Button { label = "Close" }
  local applyBtn = Gtk.Button { label = "Apply" }
  applyBtn:get_style_context():add_class("suggested-action")

  local grid = Gtk.Grid { row_spacing = 8, column_spacing = 8 }
  local row = 0
  local function addRow(l, ...)
    if l then grid:attach(type(l) == "string" and label(l) or l, 0, row, 1, 1) end
    local col = 1
    for _, w in ipairs({ ... }) do
      grid:attach(w, col, row, 1, 1)
      col = col + 1
    end
    row = row + 1
  end
  local function addWide(w, col, width)
    grid:attach(w, col or 0, row, width or 4, 1)
    row = row + 1
  end

  addRow("Preset:", presetCombo, deleteBtn, defaultBtn)
  addRow(nil, nameEntry, saveBtn)
  addWide(Gtk.Separator { orientation = Gtk.Orientation.HORIZONTAL })
  addRow("Paper:", formatCombo)
  addRow("Line spacing:", spacingSpin, unitCombo, spacingPtLabel)
  addRow(marginLabel, marginSpin, marginUnitLabel, sideCombo)
  addRow("Line width:", lineWidthSpin, label("pt"))
  addRow(colorCheck, colorBtn)
  addRow(marginColorCheck, marginColorBtn)
  addWide(Gtk.Separator { orientation = Gtk.Orientation.HORIZONTAL })
  addRow("Apply to:", targetCombo, rangeBox)
  addWide(includeBgCheck, 1, 3)
  addWide(previewCheck, 1, 3)
  addWide(status)

  local buttons = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 6 }
  buttons:pack_start(readBtn, false, false, 0)
  buttons:pack_start(exportBtn, false, false, 0)
  buttons:pack_end(applyBtn, false, false, 0)
  buttons:pack_end(closeBtn, false, false, 0)

  local vbox = Gtk.Box { orientation = Gtk.Orientation.VERTICAL, spacing = 12 }
  vbox:pack_start(grid, true, true, 0)
  vbox:pack_start(buttons, false, false, 0)

  local window = Gtk.Window {
    title = "Line Spacing",
    type_hint = Gdk.WindowTypeHint.DIALOG,
    resizable = false,
    border_width = 12,
    window_position = Gtk.WindowPosition.MOUSE,
  }
  window:add(vbox)
  self.window = window

  ---------------------------------------------------------------------------
  -- Helpers
  ---------------------------------------------------------------------------
  local function setStatus(msg, isError)
    msg = msg or ""
    status:set_markup(isError and ('<span foreground="#c01c28">' .. GLib.markup_escape_text(msg, -1) .. "</span>")
      or GLib.markup_escape_text(msg, -1))
  end

  local function rgbaToHex(rgba)
    local function b(x) return math.floor(x * 255 + 0.5) end
    return string.format("#%02x%02x%02x", b(rgba.red), b(rgba.green), b(rgba.blue))
  end

  local function hexToRgba(hex)
    local rgba = Gdk.RGBA()
    rgba:parse(hex)
    return rgba
  end

  local function pageWidth()
    local p = apply.currentPage(app)
    return p and p.width or xopt.A4.width
  end

  local function setSpinPt(sp, pt)
    local adj = sp.adjustment
    local lo, hi
    if sp == spacingSpin then
      lo, hi = config.LIMITS.spacing[1], config.LIMITS.spacing[2]
    else
      lo, hi = 0, pageWidth()
    end
    adj.lower = units.fromPt(lo, unit)
    adj.upper = units.fromPt(hi, unit)
    adj.step_increment = units.STEP[unit]
    adj.page_increment = units.STEP[unit] * 10
    sp.digits = units.DIGITS[unit]
    sp.value = units.fromPt(pt, unit)
  end

  local function updateSensitivity()
    local fmt = formatCombo.active_id
    local hasMargin = config.hasMargin(fmt)
    marginLabel.sensitive = hasMargin
    marginSpin.sensitive = hasMargin
    marginUnitLabel.sensitive = hasMargin
    sideCombo.sensitive = config.hasMarginSide(fmt)
    marginLabel.label = fmt == "graph" and "Border:" or "Margin:"
    marginColorCheck.sensitive = config.hasMarginColor(fmt)
    marginColorBtn.sensitive = config.hasMarginColor(fmt) and marginColorCheck.active
    colorBtn.sensitive = colorCheck.active
    rangeBox.sensitive = targetCombo.active_id == "range"
    local sel = presetCombo.active_id and store:get(presetCombo.active_id)
    deleteBtn.sensitive = sel ~= nil and not sel.builtin
    defaultBtn.sensitive = sel ~= nil
  end

  -- Fill widgets from `style` (internal pt values).
  local function fillForm()
    updating = true
    formatCombo.active_id = style.format
    unitCombo.active_id = unit
    marginUnitLabel.label = unit
    setSpinPt(spacingSpin, style.spacing)
    spacingPtLabel.label = unit == "pt" and "" or ("= " .. units.format(style.spacing, "pt"))
    local d = config.DEFAULTS[style.format]
    setSpinPt(marginSpin, style.margin or d.margin or 0)
    sideCombo.active_id = style.marginSide or "left"
    lineWidthSpin.value = style.lineWidth
    colorCheck.active = style.color ~= nil
    if style.color then colorBtn.rgba = hexToRgba(style.color) end
    marginColorCheck.active = style.marginColor ~= nil
    if style.marginColor then marginColorBtn.rgba = hexToRgba(style.marginColor) end
    updateSensitivity()
    updating = false
  end

  -- Read widgets into a fresh Style.
  local function readForm()
    local fmt = formatCombo.active_id or "lined"
    local s = config.defaultStyle(fmt)
    s.extra = style.extra or {}
    s.spacing = units.toPt(spacingSpin.value, unit)
    if config.hasMargin(fmt) then
      s.margin = units.toPt(marginSpin.value, unit)
      s.marginSide = config.hasMarginSide(fmt) and (sideCombo.active_id or "left") or "left"
    end
    s.lineWidth = lineWidthSpin.value
    s.color = colorCheck.active and rgbaToHex(colorBtn.rgba) or nil
    s.marginColor = (config.hasMarginColor(fmt) and marginColorCheck.active) and rgbaToHex(marginColorBtn.rgba) or nil
    return s
  end

  local function refreshPresets(selectName)
    updating = true
    presetCombo:remove_all()
    local def = store:getDefault()
    for _, p in ipairs(store:list()) do
      presetCombo:append(p.name, p.name .. (p.name == def.name and "  ★" or ""))
    end
    if selectName and store:get(selectName) then presetCombo.active_id = selectName end
    updateSensitivity()
    updating = false
  end

  local function refreshPageRange()
    local p = apply.currentPage(app)
    local count = p and p.count or 1
    for _, sp in ipairs({ fromSpin, toSpin }) do
      sp.adjustment.lower = 1
      sp.adjustment.upper = count
    end
    if p then
      updating = true
      fromSpin.value = p.index
      toSpin.value = count
      updating = false
    end
  end

  ---------------------------------------------------------------------------
  -- Preview
  ---------------------------------------------------------------------------
  local function cancelTimer()
    if preview.timer then
      GLib.source_remove(preview.timer)
      preview.timer = nil
    end
  end

  local function startPreview()
    local p = apply.currentPage(app)
    if not p then return end
    preview.active = true
    preview.original = { index = p.index, format = p.format, config = p.config }
  end

  -- Undo the live preview by restoring the remembered page type.
  local function revertPreview()
    cancelTimer()
    if preview.active and preview.original then
      local o = preview.original
      local p = apply.snapshot(app).pages[o.index]
      if p and (p.format ~= o.format or p.config ~= o.config) then
        apply.applyPageType(app, o.format, o.config, { from = o.index, to = o.index },
          { includeBackgrounds = true })
      end
    end
    preview.active, preview.original = false, nil
  end

  local function schedulePreview()
    if not preview.active then return end
    cancelTimer()
    preview.timer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 200, function()
      preview.timer = nil
      local s = readForm()
      local ok, err = config.validate(s, pageWidth())
      if not ok then setStatus(err, true) return false end
      local p = apply.currentPage(app)
      if p and preview.original and p.index ~= preview.original.index then
        -- user moved to another page: finish the old preview, start a new one here
        revertPreview()
        startPreview()
      end
      if p and apply.isBackgroundPage(p.format) and not includeBgCheck.active then
        setStatus("Preview skipped: the current page has a PDF/image background.", false)
        return false
      end
      apply.applyStyle(app, s, "current", { includeBackgrounds = true })
      setStatus("Previewing on page " .. (p and p.index or "?") .. " (not applied yet).")
      return false
    end)
  end

  ---------------------------------------------------------------------------
  -- Actions
  ---------------------------------------------------------------------------
  function self.reloadFromPage()
    local p = apply.currentPage(app)
    if not p then return end
    style = config.toStyle(p.format, p.config)
    if not config.isSupported(p.format) then
      style = config.defaultStyle("lined")
      setStatus(string.format("Page %d has a %s background; showing defaults.", p.index,
        p.format:gsub("^:", "")))
    else
      setStatus(string.format("Loaded from page %d of %d.", p.index, p.count))
    end
    refreshPageRange()
    fillForm()
  end

  local function doApply()
    cancelTimer()
    local s = readForm()
    local ok, err = config.validate(s, pageWidth())
    if not ok then setStatus(err, true) return end
    local target = targetCombo.active_id or "current"
    if target == "range" then target = { from = fromSpin.value, to = toSpin.value } end
    -- Restore the previewed page first so it is counted/handled like any other page.
    local wasPreviewing = preview.active
    revertPreview()
    local r, aerr = apply.applyStyle(app, s, target, { includeBackgrounds = includeBgCheck.active })
    if not r then setStatus(aerr, true) return end
    style = s
    -- Detect a Xournal++ build that ignores the config argument.
    local fmt, cfg = config.fromStyle(s)
    if r.changed > 0 and target == "current" and not apply.verifyCurrent(app, fmt, cfg) then
      setStatus("Xournal++ did not keep the line settings (config argument unsupported?).", true)
    else
      setStatus(apply.describeResult(r) .. ". Ctrl+Z undoes.")
    end
    if wasPreviewing then startPreview() end
  end

  local function doSavePreset()
    local s = readForm()
    local name = nameEntry.text
    if name == nil or name:match("^%s*$") then name = store:suggestName(s, unit) end
    local ok, err = store:put(name, s, unit)
    if not ok then setStatus(err, true) return end
    nameEntry.text = ""
    refreshPresets(name)
    setStatus("Saved preset \"" .. name .. "\". Menu entries update after restarting Xournal++.")
    if ctx.onPresetsChanged then ctx.onPresetsChanged() end
  end

  local function doDeletePreset()
    local name = presetCombo.active_id
    if not name then return end
    local ok, err = store:remove(name)
    if not ok then setStatus(err, true) return end
    refreshPresets()
    setStatus("Deleted preset \"" .. name .. "\".")
    if ctx.onPresetsChanged then ctx.onPresetsChanged() end
  end

  local function doSetDefault()
    local name = presetCombo.active_id
    if not name then return end
    local ok, err = store:setDefault(name)
    if not ok then setStatus(err, true) return end
    refreshPresets(name)
    setStatus("\"" .. name .. "\" is now the default preset (Plugins menu → Apply default preset).")
  end

  local function doExport()
    local s = readForm()
    local ok, err = config.validate(s, pageWidth())
    if not ok then setStatus(err, true) return end
    local p = apply.currentPage(app)
    local name = presetCombo.active_id or store:suggestName(s, unit)
    local text = xopt.build({
      style = s,
      width = p and p.width, height = p and p.height,
      copyLastPageSettings = true,
    })
    local saveDialog = ctx.saveDialog or function(suggested, cb)
      _G.__lineSpacingXoptPath = cb
      app.fileDialogSave("__lineSpacingXoptPath", suggested)
    end
    saveDialog(xopt.fileName(name), function(path)
      if not path or path == "" then return end
      if not path:match("%.xopt$") then path = path .. ".xopt" end
      local wok, werr = xopt.write(path, text)
      if wok then
        setStatus("Saved " .. path .. ".\nTo use it for new documents: Journal → Configure Page Template → " ..
          "Load from file → OK.")
      else
        setStatus("Could not write " .. path .. ": " .. tostring(werr), true)
      end
    end)
  end

  local function close()
    revertPreview()
    window:destroy()
  end

  ---------------------------------------------------------------------------
  -- Signals
  ---------------------------------------------------------------------------
  local function onFormChanged()
    if updating then return end
    updateSensitivity()
    local s = readForm()
    spacingPtLabel.label = unit == "pt" and "" or ("= " .. units.format(s.spacing, "pt"))
    schedulePreview()
  end

  function formatCombo:on_changed()
    if updating then return end
    -- switching paper type: keep spacing, reset margin to the new format's default
    local s = readForm()
    local d = config.DEFAULTS[s.format]
    if d.margin ~= nil and not config.hasMargin(style.format) then s.margin = d.margin end
    style = s
    fillForm()
    schedulePreview()
  end

  function unitCombo:on_changed()
    if updating then return end
    local s = readForm() -- read with the old unit
    unit = unitCombo.active_id or "pt"
    style = s
    fillForm()
  end

  spacingSpin.on_value_changed = onFormChanged
  marginSpin.on_value_changed = onFormChanged
  lineWidthSpin.on_value_changed = onFormChanged
  sideCombo.on_changed = onFormChanged
  colorCheck.on_toggled = onFormChanged
  marginColorCheck.on_toggled = onFormChanged
  colorBtn.on_color_set = onFormChanged
  marginColorBtn.on_color_set = onFormChanged
  targetCombo.on_changed = function() if not updating then updateSensitivity() end end

  function presetCombo:on_changed()
    if updating then return end
    local p = presetCombo.active_id and store:get(presetCombo.active_id)
    if not p then return end
    style = config.copy(p.style)
    unit = p.unit or "pt"
    fillForm()
    setStatus("Preset \"" .. p.name .. "\" loaded into the form. Click Apply to use it.")
    schedulePreview()
  end

  function previewCheck:on_toggled()
    if previewCheck.active then
      startPreview()
      schedulePreview()
    else
      revertPreview()
      setStatus("Preview off; page restored.")
    end
  end

  readBtn.on_clicked = function() self.reloadFromPage() end
  applyBtn.on_clicked = doApply
  saveBtn.on_clicked = doSavePreset
  nameEntry.on_activate = doSavePreset
  deleteBtn.on_clicked = doDeletePreset
  defaultBtn.on_clicked = doSetDefault
  exportBtn.on_clicked = doExport
  closeBtn.on_clicked = close

  function window:on_delete_event()
    revertPreview()
    return false -- let GTK destroy the window
  end

  function window:on_destroy()
    cancelTimer()
    instance = nil
  end

  ---------------------------------------------------------------------------
  -- Init
  ---------------------------------------------------------------------------
  updating = true
  targetCombo.active_id = "current"
  updating = false
  refreshPresets()
  self.reloadFromPage()
  window:show_all()

  -- exposed for tests
  self.widgets = {
    presetCombo = presetCombo, nameEntry = nameEntry, saveBtn = saveBtn, deleteBtn = deleteBtn,
    defaultBtn = defaultBtn, formatCombo = formatCombo, spacingSpin = spacingSpin, unitCombo = unitCombo,
    marginSpin = marginSpin, sideCombo = sideCombo, lineWidthSpin = lineWidthSpin,
    colorCheck = colorCheck, colorBtn = colorBtn, targetCombo = targetCombo, fromSpin = fromSpin,
    toSpin = toSpin, includeBgCheck = includeBgCheck, previewCheck = previewCheck, status = status,
    applyBtn = applyBtn, closeBtn = closeBtn, exportBtn = exportBtn, readBtn = readBtn,
  }
  self.readForm = readForm
  self.close = close

  instance = self
  return self
end

function M.isOpen()
  return instance ~= nil
end

return M
