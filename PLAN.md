# PLAN: Review & Simplification (`xournalpp-line-spacing` v0.1.0)

> Reviewed against Xournal++ 1.3.8 (`luapi_application.h`, `Plugin.cpp`, `BackgroundConfig.h`), upcoming 1.4 (`parentPath`), and `dingzy53` repo standards.
>
> Baseline on this machine (Lua 5.4.8, `lua-lgi` + display): `luac -p LineSpacing/*.lua LineSpacing/ui/*.lua tests/*.lua` clean; `lua tests/run.lua` passes `46 passed, 0 failed`; `lua tests/gtk_smoke.lua` passes `ALL OK` (16 checks).
>
> **Status:** Code, tests, CI, selftest, hero screenshot, and README updated on `refactor/simplify-1.3` with macOS UAT fixes (`xopp-mac-uat-2026-11-27`). Version bump/tag waits on macOS retest.

---

## Decisions Resolved

1. [x] **Remove `Live preview` (`LineSpacing/ui/dialog.lua`):** Removed preview state/timers/`revertPreview()` so Apply creates 1 clean Undo step per changed page.
2. [x] **Trim Plugin menu entries (`LineSpacing/main.lua`):** Replaced 13+ dynamic items with 5 static items (`parentPath = {"Line Spacing"}` + `toolbarId`s).
3. [x] **`New document` action:** Kept as a Plugin menu item (`Line Spacing: New Document (Default Preset)`); simplified dialog footer to `[Read Page]` + `[Close] [Apply]`.
4. [x] **Remove unused `xopt.lua`:** Deleted `LineSpacing/xopt.lua`, `tests/test_xopt.lua`, and `tests/fixtures/golden.xopt`.
5. [x] **GitHub repo description & hero image:** Moved `docs/dialog.png` -> `docs/images/hero.png` and updated the GitHub repo description via `gh repo edit`.

---

## 1. Bug Fix & Core UX Simplification

- **Eliminate Undo-stack pollution (`LineSpacing/ui/dialog.lua`):**
  Remove `preview` state, `previewCheck`, `GLib.timeout_add` debouncing, and `revertPreview()`. Applying settings creates 1 clean Undo step per changed page.
- **Static Plugin menu (`LineSpacing/main.lua:109-126`):**
  Remove the dynamic `menuPresets` loop (removes the restart requirement and `"Preset no longer exists."` error). Add `toolbarId` values for toolbar customization and `parentPath = {"Line Spacing"}` for Xournal++ 1.4+ submenus.

## 2. Dialog & Fallback UI Simplification

- **Declutter GTK window (`LineSpacing/ui/dialog.lua`):**
  - Condense the 2-row, 5-widget preset header into a single compact preset row.
  - Move secondary controls (`Line width`, `Line colour`, `Margin colour`, `Also replace PDF/image backgrounds`) into a `Gtk.Expander` (`"Appearance & options"`), auto-expanded when the loaded page or preset uses non-default width or colours.
  - Close on `Escape` (`on_key_press_event`), and set `transient_for` to Xournal++'s active `Gtk.ApplicationWindow` when available so the window stays on top.
- **Simplify fallback dialog (`LineSpacing/ui/fallback.lua:13-22, 53-83`):**
  Reduce the 7-button strip to 5 buttons (`−2 pt`, `+2 pt`, `Apply to All`, `Default Preset`, `Done`) aligned with `STEP_PT = 2`.

## 3. Settings & Code Simplification

- **Persist preferred unit (`LineSpacing/presets.lua`, `LineSpacing/ui/dialog.lua:38`):**
  Store the user's preferred unit (`"pt"`, `"mm"`, `"in"`) in `presets.lua` instead of resetting to `"pt"` on every `reloadFromPage()`.
- **Remove dead and redundant code:**
  - Remove `LineSpacing/xopt.lua` (inline `DEFAULT_PAGE_WIDTH = 595.275591` in `config.lua`).
  - Remove unused `Store:rename` (`LineSpacing/presets.lua:243-256`), `config.toMap` (`LineSpacing/config.lua:67-73`), and `ctx.onPresetsChanged` / `ctx.saveDialog` hooks (`LineSpacing/ui/dialog.lua:23-24, 383, 393`).
  - Remove global `debug.sethook` in `presets.decode` (`LineSpacing/presets.lua:105-110`); `load(text, "=presets", "t", {})` already sandboxes the chunk without clearing external debug hooks.
  - Default `config.toStyle` fallback for unsupported formats to `"lined"` (`LineSpacing/config.lua:121`), removing duplicate overrides in `main.lua:73`, `fallback.lua:34`, and `dialog.lua:341`.
- **Docs & repo hygiene:**
  - Move `docs/dialog.png` -> `docs/images/hero.png` and update `README.md` and `scripts/screenshot.lua`.
  - Set GitHub repo description and prune merged remote branch `chore/lua55-ci` if approved.

## 4. Test Suite Review & Additions

**Assessment:** The 3-tier layout (`tests/run.lua`, `tests/gtk_smoke.lua`, `scripts/selftest.sh`) is strong, **but not yet enough to make the plugin robust**:
- CI only runs `tests/run.lua`, leaving `main.lua`, `ui/fallback.lua`, `ui/gtk.lua`, and `ui/dialog.lua` at **0% CI coverage**.
- `tests/fakeapp.lua` does not implement `registerUi`, `openDialog`, `getFolder`, or Undo tracking.
- Fallback dialog flows (used on Windows and minimal Linux without `lua-lgi`) have no automated tests.

**Planned test additions:**
1. **Extend `tests/fakeapp.lua`:** add `registerUi` (`initUi`-only + global callback check), `openDialog` (validate Pango markup), `getFolder`, and an `undoCount` counter on `changeCurrentPageBackground`.
2. **Add `tests/test_main.lua` to `tests/run.lua`:** test `initUi()`, fallback UI when `lgi` is missing, `lineSpacingStep` bounds and `:pdf` protection, `lineSpacingApplyDefault`, `lineSpacingNewDocument`, `storeWarning` display, and Pango escaping of `&`/`<`/`>`.
3. **Verify Undo counts & UX in `test_apply.lua` and `tests/gtk_smoke.lua`:** assert 1 Apply on current page = 1 Undo step, closing without Apply = 0 Undo steps, `Escape` closes the window, and preferred `unit` persists across opens.
4. **Update `.github/workflows/ci.yml`:** run `luac5.4 -p LineSpacing/*.lua LineSpacing/ui/*.lua tests/*.lua` and `xvfb-run -a lua5.4 tests/gtk_smoke.lua` (`lua-lgi` + `xvfb`) on every push and PR.

---

## 5. Mac UAT Fixes (`xopp-mac-uat-2026-11-27`)

1. **Treat `app.openDialog` as plain text (`LineSpacing/ui/fallback.lua`, `LineSpacing/main.lua`):** remove `<b>`/`<small>` tags and `fallback.escape` (Xournal++ `XojMsgBox` renders secondary text via `gtk_message_dialog_format_secondary_text`, while `Gtk.Label:set_markup` in `ui/dialog.lua` keeps `GLib.markup_escape_text`).
2. **Pre-select matching preset (`LineSpacing/presets.lua`, `LineSpacing/ui/dialog.lua`):** add `Store:findMatching(style)` and sync `presetCombo` when loading or applying a matching style.
3. **OS-aware Undo hint & macOS bundle note (`LineSpacing/apply.lua`, `README.md`):** show `⌘Z` on macOS and document Xournal++ 1.3.8's macOS LuaGObject fallback in `README.md`.
