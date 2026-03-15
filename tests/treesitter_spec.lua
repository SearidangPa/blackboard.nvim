-- luacheck: globals describe it assert before_each after_each
local beaver = require 'beaver'
local eq = assert.are.same

describe('treesitter', function()
  local bufnr

  after_each(function()
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  local function create_buffer(lines, filetype)
    bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].filetype = filetype
    return bufnr
  end

  it('finds a lua function context', function()
    local lines = {
      'local function greet(name)',
      '  return "hi " .. name',
      'end',
    }
    local buffer = create_buffer(lines, 'lua')
    local ctx = beaver.enclosing_function(buffer, 1)

    assert.is_not_nil(ctx)
    eq('greet', ctx.name)
  end)

  it('finds a go function context', function()
    local lines = {
      'package main',
      '',
      'func greet(name string) string {',
      '  return name',
      '}',
    }
    local buffer = create_buffer(lines, 'go')
    local ctx = beaver.enclosing_function(buffer, 3)

    assert.is_not_nil(ctx)
    eq('greet', ctx.name)
  end)
end)
