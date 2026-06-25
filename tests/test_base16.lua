local helpers = dofile('tests/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
local load_module = function(config) child.mini_load('base16', config) end
local unload_module = function() child.mini_unload('base16') end
local reload_module = function(config) child.mini_reload('base16', config) end

local validate_hl_group = function(group_name, target)
  expect.match(
    child.cmd_capture('highlight ' .. group_name):gsub(' +', ' '),
    group_name .. ' xxx .*' .. vim.pesc(target)
  )
end

-- Data =======================================================================
local minischeme_palette = {
  base00 = '#112641',
  base01 = '#3a475e',
  base02 = '#606b81',
  base03 = '#8691a7',
  base04 = '#d5dc81',
  base05 = '#e2e98f',
  base06 = '#eff69c',
  base07 = '#fcffaa',
  base08 = '#ffcfa0',
  base09 = '#cc7e46',
  base0A = '#46a436',
  base0B = '#9ff895',
  base0C = '#ca6ecf',
  base0D = '#42f7ff',
  base0E = '#ffc4ff',
  base0F = '#00a5c5',
}

local minischeme_use_cterm = {
  base00 = 235,
  base01 = 238,
  base02 = 60,
  base03 = 103,
  base04 = 186,
  base05 = 186,
  base06 = 229,
  base07 = 229,
  base08 = 223,
  base09 = 173,
  base0A = 71,
  base0B = 156,
  base0C = 170,
  base0D = 87,
  base0E = 225,
  base0F = 38,
}

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()

      -- Undo the color scheme applied for all tests
      child.cmd('hi clear')

      load_module({ palette = minischeme_palette })
    end,
    post_once = child.stop,
  },
  n_retry = helpers.get_n_retry(1),
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  -- Global variable
  eq(child.lua_get('type(_G.MiniBase16)'), 'table')
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniBase16.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniBase16.config.' .. field), value) end

  expect_config('palette', minischeme_palette)
  expect_config('use_cterm', vim.NIL)
end

T['setup()']['respects `config` argument'] = function()
  unload_module()
  load_module({ palette = minischeme_palette, use_cterm = true })
  eq(child.lua_get('MiniBase16.config.use_cterm'), true)
end

T['setup()']['validates `config` argument'] = function()
  unload_module()

  local expect_config_error = function(config, name, target_type)
    expect.error(function() load_module(config) end, vim.pesc(name) .. '.*' .. vim.pesc(target_type))
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ palette = 'a' }, 'config.palette', 'table')
  expect_config_error({ palette = { 'a' } }, 'config.palette', 'base00')
  expect_config_error({ palette = { base00 = 1 } }, 'config.palette', 'HEX')
  expect_config_error({ palette = { base00 = '000' } }, 'config.palette.base00', 'HEX')
  expect_config_error({ palette = { base00 = '000000' } }, 'config.palette.base00', 'HEX')
  expect_config_error({ palette = { base00 = '#GGGGGG' } }, 'config.palette.base00', 'HEX')
  expect_config_error({ palette = minischeme_palette, use_cterm = 'a' }, 'use_cterm', 'boolean or table')
  expect_config_error({ palette = minischeme_palette, use_cterm = { 'a' } }, 'use_cterm', 'base00')
  expect_config_error({ palette = minischeme_palette, use_cterm = { base00 = 'a' } }, 'use_cterm.base00', 'cterm color')
  expect_config_error({ palette = minischeme_palette, use_cterm = { base00 = -1 } }, 'use_cterm.base00', 'cterm color')
end

T['setup()']['defines builtin highlight groups'] = function()
  local p = child.lua_get('MiniBase16.config.palette')
  validate_hl_group('Normal', ('guifg=%s guibg=%s'):format(p.base05, p.base00))
  validate_hl_group('Cursor', ('guifg=%s guibg=%s'):format(p.base00, p.base05))

  validate_hl_group('Comment', ('guifg=%s'):format(p.base03))
  validate_hl_group('Error', ('guifg=%s guibg=%s'):format(p.base00, p.base08))
  validate_hl_group('Special', ('guifg=%s'):format(p.base0C))
  validate_hl_group('Bold', 'gui=bold')

  local diagnostic_hl_group = 'DiagnosticError'
  validate_hl_group(diagnostic_hl_group, ('guifg=%s'):format(p.base08))
end

T['setup()']['defines highlight groups for terminal colors'] = function()
  local p = child.lua_get('MiniBase16.config.palette')
  vim.g.terminal_color_0 = p.base00
  vim.g.terminal_color_background = vim.o.background == 'dark' and vim.g.terminal_color_0 or vim.g.terminal_color_7
  vim.g.terminal_color_foreground = vim.o.background == 'dark' and vim.g.terminal_color_5 or vim.g.terminal_color_2
end

T['setup()']['clears previous colorscheme'] = function()
  local p = child.lua_get('MiniBase16.config.palette')
  child.cmd('colorscheme blue')
  load_module({ palette = minischeme_palette })
  validate_hl_group('Normal', ('guifg=%s guibg=%s'):format(p.base05, p.base00))
end

T['setup()']['respects `config.use_cterm`'] = function()
  local p = child.lua_get('MiniBase16.config.palette')
  local p_cterm = minischeme_use_cterm

  reload_module({ palette = minischeme_palette, use_cterm = true })
  validate_hl_group(
    'Normal',
    ('ctermfg=%s ctermbg=%s guifg=%s guibg=%s'):format(p_cterm.base05, p_cterm.base00, p.base05, p.base00)
  )

  reload_module({ palette = minischeme_palette, use_cterm = p_cterm })
  validate_hl_group(
    'Normal',
    ('ctermfg=%s ctermbg=%s guifg=%s guibg=%s'):format(p_cterm.base05, p_cterm.base00, p.base05, p.base00)
  )
end

T['setup()']['respects `config.plugins`'] = function()
  local clear_highlight = function()
    child.cmd('highlight clear')
    expect.match(child.cmd_capture('hi MiniCursorword'), 'cleared')
  end

  -- By default it should load plugin integrations
  clear_highlight()
  reload_module({ palette = minischeme_palette })
  validate_hl_group('MiniCursorword', 'gui=underline')

  -- If supplied `false`, should not load plugin integration
  clear_highlight()
  reload_module({
    palette = minischeme_palette,
    plugins = { ['nvim-mini/mini.nvim'] = false, ['echasnovski/mini.nvim'] = false },
  })
  expect.match(child.cmd_capture('hi MiniCursorword'), 'cleared')

  -- Should allow loading only chosen integrations
  clear_highlight()
  reload_module({ palette = minischeme_palette, plugins = { default = false, ['nvim-mini/mini.nvim'] = true } })
  validate_hl_group('MiniCursorword', 'gui=underline')
  expect.match(child.cmd_capture('hi GitSignsAdd'), 'cleared')
end

T['mini_palette()'] = new_set()

T['mini_palette()']['validates arguments'] = function()
  local validate = function(args, error_pattern)
    expect.error(function() child.lua_get('MiniBase16.mini_palette(...)', args) end, error_pattern)
  end

  validate({ 1, '#000000' }, 'background.*HEX')
  validate({ 'a', '#000000' }, 'background.*HEX')
  validate({ '000000', '#000000' }, 'background.*HEX')
  validate({ '#GGGGGG', '#000000' }, 'background.*HEX')

  validate({ '#000000', 1 }, 'foreground.*HEX')
  validate({ '#000000', 'a' }, 'foreground.*HEX')
  validate({ '#000000', '000000' }, 'foreground.*HEX')
  validate({ '#000000', '#GGGGGG' }, 'foreground.*HEX')

  validate({ '#000000', '#FFFFFF', 'a' }, 'accent_chroma.*number')
  validate({ '#000000', '#FFFFFF', -1 }, 'accent_chroma.*positive')
end

T['mini_palette()']['works'] = function()
  eq(child.lua_get([[MiniBase16.mini_palette('#112641', '#e2e98f', 75)]]), minischeme_palette)
end

T['rgb_palette_to_cterm_palette()'] = new_set()

T['rgb_palette_to_cterm_palette()']['validates arguments'] = function()
  local validate = function(palette, error_pattern)
    expect.error(
      function() child.lua_get('MiniBase16.rgb_palette_to_cterm_palette(...)', { palette }) end,
      error_pattern
    )
  end

  validate('a', 'palette.*table')
  validate({ 'a' }, 'palette.*base00')
  validate({ base00 = 1 }, 'palette.*HEX')
  validate({ base00 = '000' }, 'palette.base00.*HEX')
  validate({ base00 = '000000' }, 'palette.base00.*HEX')
  validate({ base00 = '#GGGGGG' }, 'palette.base00.*HEX')
end

T['rgb_palette_to_cterm_palette()']['works'] = function()
  eq(child.lua_get('MiniBase16.rgb_palette_to_cterm_palette(...)', { minischeme_palette }), minischeme_use_cterm)
end

T['minischeme colorscheme'] = new_set()

T['minischeme colorscheme']['works with dark background'] = function()
  child.cmd('colorscheme minischeme')
  child.o.background = 'dark'
  validate_hl_group('Normal', 'ctermfg=186 ctermbg=235 guifg=#e2e98f guibg=#112641')
end

T['minischeme colorscheme']['works with light background'] = function()
  child.cmd('colorscheme minischeme')
  child.o.background = 'light'
  validate_hl_group('Normal', 'ctermfg=18 ctermbg=254 guifg=#002a83 guibg=#e2e5ca')
end

return T
