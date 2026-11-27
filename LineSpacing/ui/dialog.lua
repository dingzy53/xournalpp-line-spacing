-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 Ding Zheng Yuan
--
-- GTK 3 settings dialog (via lgi / LuaGObject).
--
-- Non-modal and non-blocking: no Gtk.main(), no dialog:run(). Xournal++ already
-- runs the GTK main loop; our signal handlers execute inside it.
local apply = require("apply")
local config = require("config")
local units = require("units")

local M = {}

local instance -- the single open dialog, if any

local TARGETS = { "current", "all", "range" }
local TARGET_LABELS = { current = "Current page", all = "All pages", range = "Page range" }

local function hasCustomAppearance(s)
  local d = config.DEFAULTS[s.format]
  return s.color ~= nil or s.marginColor ~= nil
    or math.abs((s.lineWidth or d.lineWidth) - d.lineWidth) >= 1e-6
end

--- ctx = { app, store, gtk = ui.gtk.load() result, notify(msg, isError) }
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
  local unit = store:getUnit()
  local style = config.defaultStyle("lined")

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
  local defaultBtn = Gtk.Button { label = "★", tooltip_text = "Set as default preset" }
  local saveMenuBtn = Gtk.Button { label = "Save…" }
  local deleteBtn = Gtk.Button { label = "Delete" }

  local nameEntry = Gtk.Entry { placeholder_text = "Preset name", width_chars = 18 }
  local saveBtn = Gtk.Button { label = "Save" }
  saveBtn:get_style_context():add_class("suggested-action")
  local savePopover = Gtk.Popover { relative_to = saveMenuBtn }
  local popBox = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 6, border_width = 8 }
  popBox:pack_start(nameEntry, true, true, 0)
  popBox:pack_start(saveBtn, false, false, 0)
  savePopover:add(popBox)

  local formatCombo = Gtk.ComboBoxText()
  for _, f in ipairs(config.FORMATS) do formatCombo:append(f, config.LABELS[f]) end

  local spacingSpin = spin(1, 1000, 0.5, 2)
  local unitCombo = Gtk.ComboBoxText()
  for _, u in ipairs(units.UNITS) do unitCombo:append(u, u) end
  local spacingPtLabel = label("")

  local marginLabel = label("Margin:")
  local marginSpin = spin(0, 10000, 1, 2)
  local marginUnitLabel = label(unit)
  local sideCombo = Gtk.ComboBoxText()
  sideCombo:append("left", "Left")
  sideCombo:append("right", "Right")

  local lineWidthSpin = spin(config.LIMITS.lineWidth[1], config.LIMITS.lineWidth[2], 0.1, 2)

  local colorCheck = Gtk.CheckButton { label = "Line colour" }
  -- initial colours = Xournal++ defaults (xopp_dodgerblue / xopp_deeppink)
  local colorBtn = Gtk.ColorButton { rgba = Gdk.RGBA { red = 0x1e / 255, green = 0x90 / 255, blue = 1, alpha = 1 } }
  local marginColorCheck = Gtk.CheckButton { label = "Margin colour" }
  local marginColorBtn = Gtk.ColorButton { rgba = Gdk.RGBA { red = 1, green = 0x14 / 255, blue = 0x93 / 255, alpha = 1 } }

  local targetCombo = Gtk.ComboBoxText()
  for _, t in ipairs(TARGETS) do targetCombo:append(t, TARGET_LABELS[t]) end
  local fromSpin = spin(1, 1, 1, 0)
  local toSpin = spin(1, 1, 1, 0)
  local rangeBox = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 6,
    label("from"), fromSpin, label("to"), toSpin }
  local includeBgCheck = Gtk.CheckButton { label = "Also replace PDF/image backgrounds" }

  local status = label("", { wrap = true, max_width_chars = 50, selectable = true })

  local readBtn = Gtk.Button { label = "Read Page" }
  local closeBtn = Gtk.Button { label = "Close" }
  local applyBtn = Gtk.Button { label = "Apply" }
  applyBtn:get_style_context():add_class("suggested-action")

  local function makeGrid()
    local g = Gtk.Grid { row_spacing = 8, column_spacing = 8 }
    local row = 0
    local function addRow(l, ...)
      if l then g:attach(type(l) == "string" and label(l) or l, 0, row, 1, 1) end
      local box = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 6 }
      for _, w in ipairs({ ... }) do
        local expand = w.hexpand == true
        box:pack_start(w, expand, expand, 0)
      end
      g:attach(box, 1, row, 1, 1)
      row = row + 1
    end
    local function addWide(w, col, width)
      g:attach(w, col or 0, row, width or 2, 1)
      row = row + 1
    end
    return g, addRow, addWide
  end

  local grid, addRow, addWide = makeGrid()
  addRow("Preset:", presetCombo, defaultBtn, saveMenuBtn, deleteBtn)
  addWide(Gtk.Separator { orientation = Gtk.Orientation.HORIZONTAL })
  addRow("Paper:", formatCombo)
  addRow("Line spacing:", spacingSpin, unitCombo, spacingPtLabel)
  addRow(marginLabel, marginSpin, marginUnitLabel, sideCombo)
  addRow("Apply to:", targetCombo, rangeBox)

  local advGrid, addAdvRow, addAdvWide = makeGrid()
  advGrid.margin_top = 6
  addAdvRow("Line width:", lineWidthSpin, label("pt"))
  addAdvRow(colorCheck, colorBtn)
  addAdvRow(marginColorCheck, marginColorBtn)
  addAdvWide(includeBgCheck, 0, 2)

  local appearanceExpander = Gtk.Expander { label = "Appearance & options", expanded = false }
  appearanceExpander:add(advGrid)
  addWide(appearanceExpander)
  addWide(status)

  local buttons = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 6 }
  buttons:pack_start(readBtn, false, false, 0)
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
  pcall(function()
    for _, top in ipairs(Gtk.Window.list_toplevels()) do
      if top ~= window and top.visible and Gtk.ApplicationWindow:is_type_of(top) then
        window:set_transient_for(top)
        break
      end
    end
  end)
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
    return p and p.width or config.DEFAULT_PAGE_WIDTH
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
  -- Actions
  ---------------------------------------------------------------------------
  function self.reloadFromPage()
    local p = apply.currentPage(app)
    if not p then return end
    style = config.toStyle(p.format, p.config)
    if not config.isSupported(p.format) then
      setStatus(string.format("Page %d has a %s background; showing defaults.", p.index,
        p.format:gsub("^:", "")))
    else
      setStatus(string.format("Loaded from page %d of %d.", p.index, p.count))
    end
    appearanceExpander.expanded = hasCustomAppearance(style)
    refreshPageRange()
    fillForm()
  end

  local function doApply()
    local s = readForm()
    local ok, err = config.validate(s, pageWidth())
    if not ok then setStatus(err, true) return end
    local target = targetCombo.active_id or "current"
    if target == "range" then target = { from = fromSpin.value, to = toSpin.value } end
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
  end

  local function openSavePopover()
    nameEntry.text = store:suggestName(readForm(), unit)
    savePopover:show_all()
    savePopover:popup()
    nameEntry:grab_focus()
  end

  local function doSavePreset()
    local s = readForm()
    local name = nameEntry.text
    if name == nil or name:match("^%s*$") then name = store:suggestName(s, unit) end
    local ok, err = store:put(name, s, unit)
    if not ok then setStatus(err, true) return end
    nameEntry.text = ""
    if savePopover.visible then
      savePopover:popdown()
      savePopover:hide()
    end
    refreshPresets(name)
    setStatus("Saved preset \"" .. name .. "\".")
  end

  local function doDeletePreset()
    local name = presetCombo.active_id
    if not name then return end
    local ok, err = store:remove(name)
    if not ok then setStatus(err, true) return end
    refreshPresets()
    setStatus("Deleted preset \"" .. name .. "\".")
  end

  local function doSetDefault()
    local name = presetCombo.active_id
    if not name then return end
    local ok, err = store:setDefault(name)
    if not ok then setStatus(err, true) return end
    refreshPresets(name)
    setStatus("\"" .. name .. "\" is now the default preset.")
  end

  local function close()
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
  end

  function formatCombo:on_changed()
    if updating then return end
    local s = readForm()
    local d = config.DEFAULTS[s.format]
    if d.margin ~= nil and not config.hasMargin(style.format) then s.margin = d.margin end
    style = s
    fillForm()
  end

  function unitCombo:on_changed()
    if updating then return end
    local s = readForm() -- read with the old unit
    unit = unitCombo.active_id or "pt"
    store:setUnit(unit)
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
    if p.unit and p.unit ~= unit then
      unit = p.unit
      store:setUnit(unit)
    end
    appearanceExpander.expanded = hasCustomAppearance(style)
    fillForm()
    setStatus("Preset \"" .. p.name .. "\" loaded into the form. Click Apply to use it.")
  end

  readBtn.on_clicked = function() self.reloadFromPage() end
  applyBtn.on_clicked = doApply
  saveMenuBtn.on_clicked = openSavePopover
  saveBtn.on_clicked = doSavePreset
  nameEntry.on_activate = doSavePreset
  deleteBtn.on_clicked = doDeletePreset
  defaultBtn.on_clicked = doSetDefault
  closeBtn.on_clicked = close

  function window:on_key_press_event(ev)
    local ok, kv = pcall(function() return ev.key.keyval end)
    if (ok and kv or ev.keyval) == Gdk.KEY_Escape then
      close()
      return true
    end
    return false
  end

  function window:on_destroy()
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
    presetCombo = presetCombo, defaultBtn = defaultBtn, saveMenuBtn = saveMenuBtn, deleteBtn = deleteBtn,
    savePopover = savePopover, nameEntry = nameEntry, saveBtn = saveBtn,
    formatCombo = formatCombo, spacingSpin = spacingSpin, unitCombo = unitCombo,
    marginSpin = marginSpin, sideCombo = sideCombo, lineWidthSpin = lineWidthSpin,
    colorCheck = colorCheck, colorBtn = colorBtn, marginColorCheck = marginColorCheck,
    marginColorBtn = marginColorBtn, targetCombo = targetCombo, fromSpin = fromSpin,
    toSpin = toSpin, includeBgCheck = includeBgCheck, appearanceExpander = appearanceExpander,
    status = status, applyBtn = applyBtn, closeBtn = closeBtn, readBtn = readBtn,
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
