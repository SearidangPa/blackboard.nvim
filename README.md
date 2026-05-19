# blackboard.nvim

Project-local letter bookmarks for Neovim.

Blackboard lets you set marks `a-z`, jump back to them, render marks in a floating board, and optionally show signs in the sign column.

## Requirements

- Neovim
- A git project (`.git` root required)
- `nvim-lua/plenary.nvim`
- `SearidangPa/beaver.nvim`
- Optional: `folke/snacks.nvim` (only for `require('blackboard').pick()`)

## Installation (lazy.nvim)

```lua
{
  'SearidangPa/blackboard.nvim',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'SearidangPa/beaver.nvim',
    -- optional:
    -- 'folke/snacks.nvim',
  },
  opts = {
    show_signs = true,
  },
}
```

## Usage

```lua
local bb = require 'blackboard'

bb.mark 'a'
bb.jump 'a'
bb.prompt_mark()
bb.toggle_mark_window()
bb.pick() -- requires snacks.nvim
bb.clear_marks()
```

```vim
:BlackBoard
```

`:BlackBoard` opens a focusable floating window listing the project's marks. Inside the window:

- `d` — delete the mark(s) shown on the current line (a function group is removed in one keypress)
- `D` — delete all marks
- `q` / `<Esc>` — close the window

## Notes

- Marks are scoped per git project.
- Marks are persisted under `stdpath('data')/blackboard/project_marks`.
