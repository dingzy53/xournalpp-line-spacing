# Changelog

## 0.1.0 — 2026-11-03

First release. Tested on Xournal++ 1.3.7 (Fedora) with lua-lgi 0.9.2.

- Settings window (GTK 3 via lgi/LuaGObject): paper type, line spacing (pt/mm/in), margin
  position and side, line width, line/margin colours; apply to current page, all pages or
  a range; live preview with revert on close.
- Named presets with built-ins (24/20/32 pt, college and wide ruled, 5 mm graph and dots),
  default preset, per-preset menu entries.
- "New document with these settings" / "New document (default preset)": File → New, then
  restyle the blank first page; waits for the save prompt and never touches the old document.
- Configure shortcut is Ctrl+Alt+S (Ctrl+Alt+L locks the screen on KDE).
- `.xopt` page-template export is built but not offered: Configure Page Template segfaults
  on custom configs in Xournal++ <= 1.3.8 (fixed upstream in #7888).
- Fallback dialog when GTK bindings are missing; Looser/Tighter/Reset shortcuts.
