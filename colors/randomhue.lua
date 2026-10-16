local hues = require('mini.hues')

-- Generate random config with initialized random seed (otherwise it won't be
-- random during startup)
math.randomseed(vim.uv.hrtime())
local base_colors = hues.gen_random_base_colors()

hues.setup({
  background = base_colors.background,
  foreground = base_colors.foreground,
  n_hues = 8,
  saturation = vim.o.background == 'dark' and 'medium' or 'high',
  accent = 'bg',
})

vim.g.colors_name = 'randomhue'
