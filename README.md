## What is Blackboard?

Blackboard is a quick way to view and jump to **project-local marks**.

A project mark is identified by a single letter `a-z` and is stored per-git-repo under `stdpath('data')`.

If the cursor is inside a Treesitter-detected function when you set a mark, Blackboard also stores a **percent within the function** so the mark can survive edits within that function.

## Demo

https://github.com/user-attachments/assets/cdce5440-0cde-4947-9c99-57709621db84

## Commands

- `:BlackboardToggle` show/hide the Blackboard window
- `:BlackboardMark {a-z}` set/overwrite a project mark
- `:BlackboardUnmark {a-z}` delete a project mark
- `:BlackboardJump {a-z}` jump to a project mark

## Example config

```lua
return {
  'SearidangPa/blackboard.nvim',
  dependencies = { 'nvim-lua/plenary.nvim' },
  config = function()
    local bb = require 'blackboard'

    bb.setup {}

    vim.keymap.set('n', '<leader>bb', bb.toggle_mark_window, { desc = '[B]lackboard toggle' })

    -- quick mark/jump for a single letter
    vim.keymap.set('n', '<leader>ma', function()
      bb.mark 'a'
    end, { desc = '[M]ark a' })

    vim.keymap.set('n', '<leader>ja', function()
      bb.jump 'a'
    end, { desc = '[J]ump a' })
  end,
}
```
