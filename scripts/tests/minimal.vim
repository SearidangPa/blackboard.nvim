" covers all package managers i am willing to cover
set rtp+=.
set rtp+=../plenary.nvim
set rtp+=../nvim-treesitter
set rtp+=~/.vim/plugged/plenary.nvim
set rtp+=~/.vim/plugged/nvim-treesitter
set rtp+=~/.local/share/nvim/site/pack/packer/start/plenary.nvim
set rtp+=~/.local/share/nvim/site/pack/packer/start/nvim-treesitter
set rtp+=~/.local/share/lunarvim/site/pack/packer/start/plenary.nvim
set rtp+=~/.local/share/lunarvim/site/pack/packer/start/nvim-treesitter
set rtp+=~/.local/share/nvim/lazy/plenary.nvim
set rtp+=~/.local/share/nvim/lazy/nvim-treesitter

set autoindent
set tabstop=4
set expandtab
set shiftwidth=4
set noswapfile

runtime! plugin/plenary.vim
runtime! plugin/nvim-treesitter.lua

lua <<EOF
vim.opt.rtp:append(vim.fn.stdpath('data') .. '/site')

local required_parsers = {
  'lua',
  'go',
}

local function missing_parsers(parsers)
  local missing = {}
  local buf = vim.api.nvim_create_buf(false, true)
  for _, lang in ipairs(parsers) do
    local ok = pcall(vim.treesitter.get_parser, buf, lang)
    if not ok then
      table.insert(missing, lang)
    end
  end
  vim.api.nvim_buf_delete(buf, { force = true })
  return missing
end

local function install_with_main_branch_api(parsers)
  local install_dir = vim.fn.stdpath('data') .. '/site'
  require('nvim-treesitter').setup({ install_dir = install_dir })
  require('nvim-treesitter').install(parsers):wait(300000)
end

-- master branch is deprecated but still widely used
local function install_with_master_branch_api(parsers)
  -- fixes 'pos_delta >= 0' error - https://github.com/nvim-lua/plenary.nvim/issues/52
  vim.cmd('set display=lastline')
  -- make "TSInstall*" available
  vim.cmd('runtime! plugin/nvim-treesitter.vim')
  vim.cmd('TSInstallSync ' .. table.concat(parsers, ' '))
end

local to_install = missing_parsers(required_parsers)
if #to_install > 0 then
  -- Detect which nvim-treesitter API is available (main vs master branch)
  local has_main_api, ts = pcall(require, 'nvim-treesitter')
  has_main_api = has_main_api and type(ts.install) == 'function'

  if has_main_api then
    local ok, err = pcall(install_with_main_branch_api, to_install)
    if not ok then
      print('Tree-sitter install error (main API): ' .. tostring(err))
    end
  else
    local ok, err = pcall(install_with_master_branch_api, to_install)
    if not ok then
      print('Tree-sitter install error (master API): ' .. tostring(err))
    end
  end
end
EOF
