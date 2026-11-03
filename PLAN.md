# PLAN — Xournal++ "Line Spacing" plugin

Goal: let the user **configure the line height (spacing) of page backgrounds through a GUI**, and **save the result as a template** that can be reused later — both inside the plugin (named presets) and by Xournal++ itself (new-page template).

Research baseline: xournalpp `master` @ `fa23208` (2026-11-03) and tag `v1.3.7` (the version installed on this machine: Fedora RPM `xournalpp-1.3.7-1.fc44`, Lua 5.4). Every API used below was verified to exist in **v1.3.7**.

---

## 1. Background: how Xournal++ draws ruled paper

A page background is a `PageType { format, config }`:

- `format` — `plain | ruled | lined | staves | graph | dotted | isodotted | isograph | pdf | image`
- `config` — comma-separated `key=value` string parsed by `BackgroundConfig` (`src/core/model/BackgroundConfig.h`)

Config keys honoured by the renderers (`src/core/view/background/*.cpp`):

| key | meaning | applies to | default |
|---|---|---|---|
| `r1` | raster = line spacing / grid size, **pt** | ruled, lined, graph, dotted, iso*, staves | ruled/lined `24.0` |
| `m1` | margin line x-position, pt (negative ⇒ from right edge) | lined, graph (border) | lined `72.0` |
| `lw` | line width, pt | all generated | ruled `0.5` |
| `f1` / `af1` | main line colour, hex (light / dark page) | all | light blue / dark slate |
| `f2` / `af2` | margin line colour | lined | red / … |
| `rm` | round margin to raster (graph border) | graph | `0` |
| `bli` / `blw` | bold every N-th line / bold line width | graph | – |

Facts that shape the design:

1. **Config is persisted per page** in the `.xopp` file: `<background type="solid" style="lined" config="r1=32,m1=72" color="#ffffffff"/>` (`SaveHandler.cpp:392`, `XmlParser.cpp:285`). So a changed spacing survives save/reload with no extra work.
2. **Lua can set it**: `app.changeCurrentPageBackground(format, config)` — the 2nd argument is undocumented in `luapi_application.def.lua` but present since ≤1.3.7 (`luaL_optstring(L, 2, "")`). Each call creates one undo action.
3. **Lua can read it**: `app.getDocumentStructure().pages[i].pageTypeFormat / pageTypeConfig`.
4. **New pages inherit it** when the page template has `copyLastPageSettings=true` (the current setting here): `copyBackgroundFromOtherPage` copies the whole `PageType` including `config`.
5. **The menu of page types** comes from `pagetemplates.ini` in the *install* dir (`/usr/share/xournalpp/ui/`) only — no user-dir override. Editing it is a system-file hack overwritten by package updates → **out of scope**.
6. **No Lua API sets the global page template** (`Settings::pageTemplateSettings`). But Xournal++'s *Journal → Configure Page Template* dialog can **Load / Save `.xopt` files**, whose format is plain text:
   ```
   xoj/template
   copyLastPageSize=false
   copyLastPageSettings=false
   size=595.275591x841.889764
   backgroundType=lined
   backgroundTypeConfig=r1=32,m1=72
   backgroundColor=#ffffff
   ```
   `backgroundTypeConfig` is parsed and kept (`PageTemplateSettings.cpp`). → The plugin can *write* `.xopt` files the user loads once in that dialog.
7. **Not configurable**: the vertical offset of the first line (`HEADER_SIZE`) and bottom gap (`FOOTER_SIZE`) are compile-time constants. No "top margin" option is possible from a plugin.
8. `settings.xml` is rewritten by Xournal++ on exit → **never edit it from the plugin**.

## 2. Scope

### In scope (v1)
- GUI dialog to edit: format (ruled / lined / graph / dotted), **line spacing**, unit (pt / mm / in), margin position + side, line width, line colours.
- Apply to: current page / all pages / page range.
- Read current page's values to pre-fill the dialog.
- **Named presets** ("templates") stored by the plugin: save, overwrite, rename, delete, apply.
- **Export a preset as `.xopt`** for Xournal++'s page-template dialog (makes it the default for *new documents*).
- Fallback UI when GTK bindings are unavailable.

### Out of scope (v1)
- Editing `pagetemplates.ini` / adding entries to the built-in page-type menu.
- Top/bottom margins, staves-specific settings, isometric settings (could come later; only `r1` would be trivial).
- Patching Xournal++ C++ (possible follow-up: upstream PR exposing spacing in the GUI / adding a Lua `setPageTemplate`).

## 3. Runtime requirements and GUI strategy

Xournal++'s Lua API only offers `app.openDialog(message, buttons, cb)` — buttons, no text/number input. A real form needs GTK bindings from Lua:

| install | binding | module name |
|---|---|---|
| Fedora RPM (this machine) | `lua-lgi` 0.9.2 (`dnf install lua-lgi`, *not installed yet*) | `lgi` |
| Flathub Flatpak | LuaGObject 0.10.5 (bundled) | `LuaGObject` (lgi fork, same API shape) |
| Debian/Ubuntu | `lua-lgi` (Recommended dep) | `lgi` |

Xournal++ 1.3.x is **GTK 3** → use `Gtk 3.0`.

Loader (in `ui/gtk.lua`):
```lua
local ok, lgi = pcall(require, "lgi")
if not ok then ok, lgi = pcall(require, "LuaGObject") end
if ok then
  local okGtk, Gtk = pcall(lgi.require, "Gtk", "3.0")
  if okGtk then return { lgi = lgi, Gtk = Gtk } end
end
return nil   -- caller falls back to ui/fallback.lua
```

**Risk:** lgi + Lua 5.4 has a history of breakage. Phase 0 smoke test:
```sh
sudo dnf install lua-lgi
lua -e 'local lgi=require("lgi"); local Gtk=lgi.require("Gtk","3.0"); print(Gtk._version)'
```
…and the same inside Xournal++ (a 3-line test plugin), because Xournal++ embeds its own `lua_State` and GTK main loop. The dialog must be **non-blocking**: create a `Gtk.Dialog`/`Gtk.Window`, connect `on_response`, `show_all()` — do **not** call `Gtk.main()` or `dialog:run()` (nested main loop inside the host app is fragile).

**Fallback UI (no lgi)** — still fully usable:
- `Plugins → Line Spacing → Presets → <name>` menu entries (one per preset, via `registerUi{mode=i}`; registered at `initUi` time, so new presets appear after restart).
- `Tighter (−2 pt)` / `Looser (+2 pt)` / `Reset (24 pt)` menu items with accelerators, acting on the current page.
- `app.openDialog` step dialog: "Spacing: 28 pt" with buttons `−4  −1  +1  +4  Apply to all  Save as preset  Close`; re-opens itself after each click (callback re-invokes).
- Preset name for "Save as preset" in fallback mode = auto-generated (`lined-28pt`); rename by editing `presets.lua`.

## 4. Architecture

```
xournalpp-line-spacing/
├── LineSpacing/                 # the installable plugin folder
│   ├── plugin.ini               # [about] [default] enabled=true [plugin] mainfile=main.lua
│   ├── main.lua                 # initUi(), menu callbacks; thin glue only
│   ├── config.lua               # parse/serialise "k=v,k=v" config strings (pure Lua)
│   ├── units.lua                # pt <-> mm <-> in (pure)
│   ├── presets.lua              # load/save/validate preset store (pure + io)
│   ├── xopt.lua                 # build .xopt template text (pure)
│   ├── apply.lua                # apply PageType to current/all/range pages via app.*
│   └── ui/
│       ├── gtk.lua              # binding loader (lgi / LuaGObject)
│       ├── dialog.lua           # GTK form
│       └── fallback.lua         # openDialog-based UI
├── tests/
│   ├── run.lua                  # tiny test runner, runs with plain `lua`
│   ├── test_config.lua
│   ├── test_units.lua
│   ├── test_presets.lua
│   ├── test_xopt.lua
│   └── fixtures/spacing.xopp    # hand-written document for render test
├── scripts/
│   ├── install.sh               # symlink LineSpacing/ into ~/.config/xournalpp/plugins/
│   └── render-check.sh          # xopp -> pdf -> png, for visual verification
├── PLAN.md  README.md  CHANGELOG.md  LICENSE (GPL-2.0-or-later, matching Xournal++)
```

Module boundaries: everything that does not touch `app.*` or GTK is pure Lua and unit-tested outside Xournal++. `app` is only referenced from `apply.lua`, `main.lua`, `ui/*`.

### 4.1 Data model

```lua
-- one "style" = what gets applied to a page
Style = {
  format    = "lined",     -- ruled | lined | graph | dotted
  spacing   = 24.0,        -- pt   -> r1
  margin    = 72.0,        -- pt, nil = format default; side handled by sign
  marginSide= "left",      -- "left" | "right"  -> m1 = margin or m1 = -margin
  lineWidth = 0.5,         -- pt   -> lw
  color     = nil,         -- "#rrggbb" or nil (default)  -> f1
  marginColor = nil,       -- -> f2
  extra     = {},          -- unknown keys read from a page are preserved verbatim
}
Preset = { name = "College ruled", style = Style, unit = "mm", createdAt = "...", version = 1 }
```

`config.lua`:
- `parse("r1=32,m1=-72") -> {r1="32", m1="-72"}` (strings; keep order for stable output)
- `toStyle(format, cfgTable) -> Style` and `fromStyle(Style) -> format, "r1=32,m1=72,lw=0.5"`
- Emit only non-default keys; numbers formatted with `%.4g` to avoid `32.000000`.
- Colour format: verify against `BackgroundConfig::loadValueHex` before emitting (likely `f1=0x...`/hex without `#` — **check in Phase 1**).
- Round-trip invariant: `parse(fromStyle(toStyle(x))) == x` for known keys; unknown keys passed through.

Validation: spacing ∈ [4, 200] pt; line width ∈ [0.1, 5] pt; margin ∈ [0, pageWidth]. Reject NaN / non-numeric input with an inline error label (GTK) or ignore (fallback).

### 4.2 Preset storage ("save as template")

Two layers, deliberately separate:

**(a) Plugin presets** — the user-facing "templates":
- File: `app.getFolder("config") .. "/line-spacing/presets.lua"` (verified in v1.3.7: `getFolder("config")` → `Util::getConfigSubfolder("plugin-settings")`, i.e. `~/.config/xournalpp/plugin-settings/`; log the resolved path at runtime).
- Format: a Lua table literal returned by `return { version = 1, presets = { ... } }`, loaded with `load(text, name, "t", {})` (empty env, text-only — no code execution from the file). Written via temp file + `os.rename` (atomic).
- Ships with built-ins (not stored, always present): `Default (24 pt)`, `Narrow (20 pt)`, `College ruled (7.1 mm)`, `Wide ruled (8.7 mm)`, `Large (32 pt)`.
- Operations: save current dialog values as new preset, overwrite, rename, delete, set "default preset" (used by "Apply default" accelerator).
- Corrupted file ⇒ back it up as `presets.lua.bak-<timestamp>`, start empty, show a message.

**(b) Xournal++ page template (`.xopt`)** — for *new documents*:
- Dialog button "Export as Xournal++ page template…" → `app.fileDialogSave(cb, "<preset>.xopt")` → write `xopt.build(preset, pageSize)`.
- `pageSize` from current page (`getDocumentStructure`), defaulting to A4 `595.275591x841.889764`.
- After writing, show instructions: *Journal → Configure Page Template → Load from file → OK*.
- Option "Keep `copyLastPageSettings=true`" (checkbox, default on) so the inserted page follows the previous page's spacing within a document.

**Why not set it directly?** No Lua API; editing `settings.xml` is overwritten on exit. Upstream follow-up: propose `app.setPageTemplate{...}` (see §8).

## 5. GUI design (GTK 3 via lgi)

Single non-modal dialog "Line Spacing", opened from `Plugins → Line Spacing → Configure…` (accelerator e.g. `<Ctrl><Alt>l`, configurable later).

```
┌ Line Spacing ───────────────────────────────────────┐
│ Preset: [ College ruled        ▾] [Save as…] [🗑]    │
│─────────────────────────────────────────────────────│
│ Paper:        (•) Ruled ( ) Lined ( ) Graph ( ) Dots │
│ Line spacing: [ 7.10 ⇅]  [mm ▾]   = 20.13 pt         │
│ Margin:       [ 25.4 ⇅] mm   side: (•) Left ( ) Right│
│ Line width:   [ 0.50 ⇅] pt                           │
│ Line colour:  [■ default]   Margin colour: [■ def.]  │
│─────────────────────────────────────────────────────│
│ Apply to: (•) Current page ( ) All pages ( ) Pages [3]–[7] │
│ [x] Live preview on current page                      │
│─────────────────────────────────────────────────────│
│ [Export .xopt template…]        [Close] [Apply]       │
└─────────────────────────────────────────────────────┘
```

Behaviour:
- On open: read current page via `getDocumentStructure()` (`currentPage`, its `pageTypeFormat`/`pageTypeConfig`) and pre-fill. Non-generated formats (pdf/image) ⇒ default to Ruled and warn "will replace the PDF/image background" only on Apply.
- Unit switch converts the displayed value, keeps internal pt.
- Margin widgets disabled unless format is `lined` or `graph`.
- **Live preview**: debounce 150 ms (`GLib.timeout_add`) then `changeCurrentPageBackground` on the current page. Because each call is an undo step, preview mode remembers the original `PageType` and on *Close without Apply* restores it. (Undo history still gets the intermediate steps — document this; investigate whether `app.uiAction{action="ACTION_UNDO"}` can collapse them. Default: preview **off**.)
- Apply to all/range: loop pages with `app.setCurrentPage(i)` + `changeCurrentPageBackground`, then return to the original page and `app.scrollToPage`. Skip pdf/image pages unless "Include PDF/image pages" is checked. One undo step per page — acceptable; mentioned in README.
- Colour pickers: `Gtk.ColorButton`, plus "default" toggle so we don't emit `f1` unless set.
- Errors from `app.*` are `pcall`-wrapped and shown in an inline `Gtk.InfoBar`.

## 6. Implementation phases

Each phase ends with a commit (small commits within phases are fine).

**Phase 0 — feasibility spikes (½ day)**
- 0.1 Render check: hand-write `tests/fixtures/spacing.xopp` with three pages (`r1=16`, `r1=24`, `r1=40,m1=-72`), run `xournalpp --create-pdf=out/spacing.pdf tests/fixtures/spacing.xopp`, `pdftoppm -png -r 50`, eyeball. Proves config keys load+render on 1.3.7 headless. → `scripts/render-check.sh`.
- 0.2 Minimal plugin `LineSpacing/` with one menu item calling `app.changeCurrentPageBackground("lined","r1=32")`; install via symlink; verify in GUI, save, reopen.
- 0.3 `dnf install lua-lgi`; smoke test outside and inside Xournal++ (open a `Gtk.Window` from a menu callback, close it, repeat 5×, no crash/hang). Also test closing Xournal++ while the window is open.
- 0.4 Confirm `getFolder("config")` path, colour hex format for `f1`, and that a `.xopt` with `backgroundTypeConfig` loads in *Configure Page Template* and new pages use it.
- **Decision gate:** if 0.3 fails → v1 ships fallback UI only; GTK dialog moves to v1.1.

**Phase 1 — pure core + tests (1 day)**
- `config.lua`, `units.lua`, `xopt.lua`, `presets.lua` (+ round-trip, validation, corrupted-file tests). `lua tests/run.lua` must pass.

**Phase 2 — apply layer + fallback UI (½ day)**
- `apply.lua` (current / all / range, skip pdf/image, restore current page).
- `ui/fallback.lua` + menu entries (Tighter/Looser/Reset, preset menu).

**Phase 3 — GTK dialog (1–1½ days)**
- `ui/gtk.lua`, `ui/dialog.lua` per §5; preset combo wired to `presets.lua`; export `.xopt`.

**Phase 4 — polish & release (½ day)**
- README (install, usage, screenshots via render-check, limitations), CHANGELOG, LICENSE, `scripts/install.sh`, tag `v0.1.0`.

## 7. Testing & acceptance

Automated (plain `lua`, no Xournal++):
- config parse/serialise round-trip, unknown key pass-through, number formatting.
- unit conversions (`7.1 mm ≈ 20.126 pt`, tolerance 1e-3).
- preset store: save/load/rename/delete, atomic write, corrupted file recovery, sandboxed load (file containing `os.execute` must not run).
- `.xopt` output matches golden file byte-for-byte.

Headless render (`scripts/render-check.sh`): fixture → PDF → PNG; compare line count per page against expected `floor((H − HEADER − FOOTER)/r1)+1` by sampling a pixel column (simple Lua/`pdftoppm -gray` check), or visual review.

Manual acceptance checklist (Xournal++ 1.3.7, RPM):
1. Configure… opens, pre-filled from current page.
2. Change spacing to 32 pt → Apply → current page redraws; Ctrl+Z restores.
3. Apply to all pages on a 5-page doc with one PDF page → PDF page untouched.
4. Save → close → reopen `.xopp` → spacing preserved.
5. Insert new page (copyLastPageSettings on) → inherits spacing.
6. Save preset "Mine 30pt" → restart Xournal++ → preset listed and applies.
7. Export `.xopt` → load in Configure Page Template → File → New → page uses 30 pt.
8. With `lua-lgi` uninstalled → fallback menus work, no error popup on startup.
9. Dark background colour → lines use `af1` default (still visible).

## 8. Risks & open questions

| risk | mitigation |
|---|---|
| lgi broken with Lua 5.4 / crashes host | Phase 0 gate; fallback UI is first-class |
| GTK dialog outlives plugin state / app quit | keep a single dialog instance; `on_destroy` clears ref; no `Gtk.main()` |
| Undocumented 2nd arg of `changeCurrentPageBackground` changes | it's in master too; pin min version 1.3.7; feature-detect by reading back `pageTypeConfig` after apply |
| Many undo steps for "all pages" / preview | preview off by default; document |
| Presets menu needs restart to show new entries | documented; GTK dialog sees them live |
| Flatpak path differences | `getFolder()` for storage; install script detects `~/.var/app/com.github.xournalpp.xournalpp/config/xournalpp/plugins` vs `~/.config/xournalpp/plugins` |

Upstream follow-ups (optional, after v1):
- Document the `config` arg of `app.changeCurrentPageBackground` in `luapi_application.def.lua`.
- Propose `app.getPageTemplate()` / `app.setPageTemplate(t)` Lua API.
- Propose loading `pagetemplates.ini` additionally from the user config dir.

## 9. Conventions

- Lua 5.4-compatible, also runs on 5.3 (no `<const>`/`<close>`).
- Commit after every meaningful change; messages in imperative mood.
- Always re-check latest upstream `luapi_application.def.lua` / source before using an API; note min version in code comments.
