-- Add project root as full path to runtime path (in order to be able to
-- `require()`) modules from this module
vim.cmd([[let &rtp.=','.getcwd()]])

-- Ensure persistent color scheme (matters after new default in Neovim 0.10)
vim.o.background = 'dark'
require('mini.hues').setup({ background = '#11262d', foreground = '#c0c8cc', autoadjust = false })
vim.g.colors_name = 'minitest-scheme'

-- - Make screenshot tests more robust across Neovim versions
vim.o.statusline = '%<%f %l,%c%V'

if vim.fn.has('nvim-0.11') == 1 then
  vim.api.nvim_set_hl(0, 'PmenuMatch', { link = 'Pmenu' })
  vim.api.nvim_set_hl(0, 'PmenuMatchSel', { link = 'PmenuSel' })
end

-- Ensure no custom fold method in Lua files (it interferes with many tests)
vim.cmd('au FileType lua set foldmethod=manual')

-- - Ensure that child process is tested with termguicolors, since 'mini.hues'
--   only works with it. This might matter with screenshot testing.
--   One example is how https://github.com/neovim/neovim/pull/35026 adjusts
--   the behavior based on the presence of `rgb`.
--   NOTE: similar effect can be achieved by adding the following to
--   `child.setup` in 'helpers.lua':
--   `child.api.nvim_ui_attach(child.o.columns, child.o.lines, { rgb=true })`
vim.o.termguicolors = true
