This repository is a small Neovim plugin written in Lua.
Primary goals for agents: keep startup fast, follow Stylua formatting, and use LuaLS annotations consistently.

## Repo layout

- `lua/blackboard.lua`: main plugin entry/module (exports `setup`, commands, key behaviors)
- `lua/util_blackboard_mark_info.lua`: mark collection + parsing helpers
- `lua/util_blackboard_preview.lua`: fullscreen preview window logic
- `lua/util_annotations.lua`: LuaLS type/alias annotations
- `.stylua.toml`: formatting rules (indent=2, quotes=single, no call parens)

## Build / lint / test

There is no “build” step (Lua plugin). Validation is primarily formatting + headless Neovim checks.

### Formatting (required)

- Format all Lua:
  - `stylua .`
  - or `stylua lua/`

- Check formatting (no writes):
  - `stylua --check .`

Notes:
- Ensure `stylua` is installed and on your `PATH`.
- `.stylua.toml` enforces: 2 spaces, Unix EOL, prefer single quotes, `call_parentheses = None`, `column_width = 160`.

### Linting (optional / best-effort)

This repo does not currently include a linter config (no `.luacheckrc`). If you have tools installed locally:

- Quick static checks:
  - `luacheck lua/` (if `luacheck` is installed)
- Lua language server diagnostics:
  - Run via your editor (LuaLS). Prefer `---@diagnostic disable-next-line` only when needed.

### Tests

There is no `tests/` or `spec/` directory in this repo today.

If tests are added later, prefer Plenary+Busted (common for Neovim Lua plugins).

- Run all tests (typical pattern):
  - `nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }" -c q`

- Run a single test file (most requested):
  - `nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile tests/foo_spec.lua" -c q`

- Run a single test case (Busted):
  - `nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile tests/foo_spec.lua { filter = 'my test name' }" -c q`

(These commands require `plenary.nvim` and a minimal init; they are included here for future-proofing.)

### Headless runtime smoke checks (recommended)

Use Neovim headless mode to catch syntax/runtime errors quickly.

- Require the module:
  - `nvim --headless -u NONE "+set runtimepath^=/Users/searidangpa/.local/share/nvim/lazy/blackboard.nvim" "+lua require('blackboard')" +q- Require + call setup`

- Require + call setup:
  - `nvim --headless -u NONE "+lua require('blackboard').setup({})" +q`

- Execute user commands exist:
  - `nvim --headless -u NONE "+lua require('blackboard')" "+silent! BlackboardToggle" +q`

If a change depends on `plenary.nvim` or treesitter, run checks in a real Neovim environment with those installed.

### Dependencies (runtime)

- Required: `nvim-lua/plenary.nvim` (paths + filetype detection)
- Optional: Treesitter highlighting in the preview window (falls back to `syntax` when unavailable)

## Code style guidelines

### Formatting and whitespace

- Always run `stylua` before finalizing changes.
- Keep lines reasonably short; `.stylua.toml` uses `column_width = 160`.
- Use Unix line endings.

### Imports / `require`

- Prefer local `require` near usage to avoid increasing startup cost.
  - Example pattern: `local util = require 'util_blackboard_mark_info'` inside the function that uses it.
- Use Stylua’s preferred require style (single quotes, no parentheses): `require 'module'`.
- If you need many helpers from one module, assign once: `local util = require 'x'`.

### Modules and exports

- Modules should follow the existing pattern:
  - `local M = {}`
  - define locals/helpers above
  - exported functions near the bottom
  - `return M`
- Keep exported API small and stable (`setup`, toggles, preview/jump actions).

### Naming conventions

- Use `snake_case` for locals, functions, and fields (`blackboard_state`, `toggle_mark_window`).
- Use leading underscore for “private” helpers inside util modules (`_add_mark_info`).
- Use descriptive names over abbreviations; keep “buf/win” abbreviations consistent with Neovim conventions.

### Types and annotations (LuaLS)

- Use LuaLS annotations consistently (`---@class`, `---@param`, `---@return`, `---@type`).
- When you add/change fields in `blackboard_state` or options, update:
  - `lua/util_annotations.lua`
- Prefer precise container types:
  - `table<string, string[]>`, `blackboard.MarkInfo[]`, etc.

### Neovim API usage

- Prefer `vim.api.nvim_*` functions for buffer/window operations.
- Prefer `vim.bo[bufnr]` / `vim.wo[winid]` for buffer/window-local options.
- Avoid mutating global editor state unless necessary; restore state when closing windows.
- Keep autocmds grouped and cleaned up (see `blackboard_group`).

### Error handling philosophy

- Use `assert(...)` for programmer errors / invariants that should never happen.
- Use early returns for user/state conditions (invalid buffers, missing marks).
- For user-facing failures, prefer `vim.notify(msg, vim.log.levels.ERROR)`.
- For optional integrations (treesitter), guard with `pcall` and provide a fallback.

### Performance and side effects

- Avoid heavy work at `require` time; defer until commands/keymaps invoke behavior.
- Be mindful when reading entire files (`plenary.path:read()`): keep it scoped and cached (`filepath_to_content_lines`).
- Avoid creating many autocmds or namespaces repeatedly; reuse or clear appropriately.

### UI / text conventions

- Keep symbols configurable via options (existing: `not_under_func_symbol`, `under_func_symbol`).
- Avoid introducing new non-ASCII/emoji UI glyphs unless it materially improves UX.

## Contribution checklist (for agents)

- Run `stylua .`.
- Run at least one headless smoke check (`require('blackboard')`).
- If you touched types/state/options, update `lua/util_annotations.lua`.
- Keep changes minimal and consistent with existing patterns.
