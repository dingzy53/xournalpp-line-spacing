# PLAN: Lua 5.5 CI check and repository metadata

> Branch: `chore/lua55-ci` (from `main` at `7900521`) · Date: 2026-11-20 · Status: Section 2 done (`3a1edbe`); section 3 awaits owner approval.
>
> The initial v0.1.0 implementation plan is finished and shipped in `0.1.0`; see git history at `7900521` for its text.

## Context

In the 2026-11-20 test report on macOS 14 with Xournal++ 1.3.8 (bundled **Lua 5.5.1**), `xournalpp-line-spacing` 0.1.0 **passed all checks** (menu entries, GTK dialog with bundled `lgi`, live preview, close-without-apply restore, apply + undo, preset saving).

However, sibling plugin `xournalpp-bookmarks` failed to load on Xournal++ 1.3.8 because Lua 5.5 makes `for`-loop variables read-only (`<const>`), and our CI only runs Lua 5.4.

## 1. Lua 5.5 compatibility audit

### Result (verified)
Every `.lua` file under `LineSpacing/`, `scripts/` and `tests/` was audited for:
1. Assignments to `for`-loop control variables (numeric and generic `for`): **none found**.
2. Uses of the identifier `global` (new declaration syntax in Lua 5.5): **none found** (re-checked 2026-11-21; the only `global` is in a comment in `ui/fallback.lua`).
3. `luac -p LineSpacing/*.lua LineSpacing/ui/*.lua tests/*.lua`: passes cleanly on Lua 5.4.8.

## 2. CI: add Lua 5.5 syntax and unit-test check — done (`3a1edbe`)

### Cause
`.github/workflows/release.yml:31-32` only installs `lua5.4` and runs `lua5.4 tests/run.lua` on tag push. There is no push/PR `ci.yml` workflow, and Lua 5.5 is not checked in CI.

### Fix
1. Add `.github/workflows/ci.yml` (on `push` to `main` and `pull_request`) and update `.github/workflows/release.yml` to:
   - run `lua5.4 tests/run.lua`;
   - build Lua 5.5.1 from source (`https://www.lua.org/ftp/lua-5.5.1.tar.gz`), run `luac -p` on all `.lua` files in `LineSpacing/` and `tests/`, and run `tests/run.lua` under Lua 5.5.

## 3. Open item from `SKILL.md`: empty GitHub repo description

- The GitHub repository description for `dingzy53/xournalpp-line-spacing` is currently empty.
- Proposed description (matches `README.md` tagline):
  `Xournal++ plugin to configure page background line, grid, and dot spacing with live preview and presets.`
- Command (to run once approved):
  `gh repo edit dingzy53/xournalpp-line-spacing --description "Xournal++ plugin to configure page background line, grid, and dot spacing with live preview and presets."`

## Order of work

1. [x] `Add Lua 5.5 syntax and test check to CI` (`.github/workflows/ci.yml`, `.github/workflows/release.yml`). Done in `3a1edbe`; YAML validated with `yaml.safe_load`. Not run against a real Lua 5.5 build locally; first CI run will confirm.
2. [ ] Set the GitHub repo description via `gh repo edit` (no new release needed since 0.1.0 code is unchanged).

## Open questions for the owner

1. Approve the proposed GitHub repository description above?
2. ~~Should we add `.github/workflows/ci.yml` for push/PR checks in addition to `release.yml`?~~ Resolved: added (push to `main` and `pull_request`).
