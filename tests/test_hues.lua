local helpers = dofile('tests/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
local load_module = function(config) child.mini_load('hues', config) end
local unload_module = function() child.mini_unload('hues') end
local reload_module = function(config) child.mini_reload('hues', config) end

local validate_hl_group = function(group_name, target)
  eq(child.cmd_capture('highlight ' .. group_name):gsub(' +', ' '), group_name .. ' xxx ' .. target)
end

-- Data =======================================================================
local bg = '#11262d'
local fg = '#c0c8cc'

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()

      -- Undo the color scheme applied for all tests
      child.cmd('hi clear')
    end,
    post_once = child.stop,
  },
  n_retry = helpers.get_n_retry(1),
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  load_module({ background = bg, foreground = fg })

  -- Global variable
  eq(child.lua_get('type(_G.MiniHues)'), 'table')
end

T['setup()']['creates `config` field'] = function()
  load_module({ background = bg, foreground = fg })

  eq(child.lua_get('type(_G.MiniHues.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniHues.config.' .. field), value) end

  expect_config('n_hues', 8)
  expect_config('saturation', 'medium')
  expect_config('accent', 'bg')
  expect_config('autoadjust', true)
end

T['setup()']['respects `config` argument'] = function()
  load_module({ background = '#000000', foreground = '#ffffff' })
  eq(child.lua_get('MiniHues.config.background'), '#000000')
end

T['setup()']['validates `config` argument'] = function()
  local expect_config_error = function(config, name, target_type)
    expect.error(function() load_module(config) end, vim.pesc(name) .. '.*' .. vim.pesc(target_type))
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({}, 'setup', 'both `background` and `foreground`')

  expect_config_error({ background = 1, foreground = fg }, 'background', 'string')
  expect_config_error({ background = '000000', foreground = fg }, 'background', '#rrggbb')

  expect_config_error({ background = bg, foreground = 1 }, 'foreground', 'string')
  expect_config_error({ background = bg, foreground = 'ffffff' }, 'foreground', '#rrggbb')

  expect_config_error({ background = bg, foreground = fg, n_hues = '1' }, 'n_hues', 'number')
  expect_config_error({ background = bg, foreground = fg, n_hues = -1 }, 'n_hues', '0')
  expect_config_error({ background = bg, foreground = fg, n_hues = 9 }, 'n_hues', '8')

  expect_config_error({ background = bg, foreground = fg, saturation = 'aaa' }, 'saturation', 'one of')

  expect_config_error({ background = bg, foreground = fg, accent = 'aaa' }, 'accent', 'one of')

  expect_config_error({ background = bg, foreground = fg, autoadjust = 1 }, 'autoadjust', 'boolean')
end

T['setup()']['defines builtin highlight groups'] = function()
  load_module({ background = '#222222', foreground = '#dddddd' })

  validate_hl_group('Normal', 'guifg=#dddddd guibg=#222222')
  validate_hl_group('Cursor', 'guifg=#222222 guibg=#dddddd')

  validate_hl_group('Comment', 'guifg=#9a9a9a')
  validate_hl_group('Error', 'guibg=#3e0c20')
  validate_hl_group('Special', 'guifg=#a1efdf')
  validate_hl_group('Bold', 'cterm=bold gui=bold')

  validate_hl_group('DiagnosticError', 'guifg=#ffc7da')
  validate_hl_group('DiagnosticWarn', 'guifg=#f2dca0')
  validate_hl_group('DiagnosticInfo', 'guifg=#c0d2ff')
  validate_hl_group('DiagnosticOk', 'guifg=#c7eab5')
  validate_hl_group('DiagnosticHint', 'guifg=#a1efdf')
end

T['setup()']['defines tree-sitter groups'] = function()
  load_module({ background = '#222222', foreground = '#dddddd' })
  validate_hl_group('@variable', 'guifg=#dddddd')
end

T['setup()']['defines LSP semantic token highlights'] = function()
  load_module({ background = '#222222', foreground = '#dddddd' })
  validate_hl_group('@lsp.type.variable', 'links to @variable')
end

T['setup()']['defines terminal colors'] = function()
  load_module({ background = '#222222', foreground = '#dddddd' })

  eq(child.g.terminal_color_0, '#080808')
  eq(child.g.terminal_color_1, '#ffc7da')
  eq(child.g.terminal_color_2, '#c7eab5')
  eq(child.g.terminal_color_3, '#f2dca0')
  eq(child.g.terminal_color_4, '#a5e6ff')
  eq(child.g.terminal_color_5, '#f2ceff')
  eq(child.g.terminal_color_6, '#a1efdf')
  eq(child.g.terminal_color_7, '#9a9a9a')

  eq(child.g.terminal_color_8, '#5c5c5c')
  eq(child.g.terminal_color_9, '#ffc7da')
  eq(child.g.terminal_color_10, '#c7eab5')
  eq(child.g.terminal_color_11, '#f2dca0')
  eq(child.g.terminal_color_12, '#a5e6ff')
  eq(child.g.terminal_color_13, '#f2ceff')
  eq(child.g.terminal_color_14, '#a1efdf')
  eq(child.g.terminal_color_15, '#f4f4f4')

  -- Properly sets black and white for light color scheme
  load_module({ background = '#dddddd', foreground = '#222222' })
  eq(child.g.terminal_color_0, '#080808')
  eq(child.g.terminal_color_7, '#9a9a9a')
  eq(child.g.terminal_color_8, '#5c5c5c')
  eq(child.g.terminal_color_15, '#f4f4f4')
end

T['setup()']['clears previous colorscheme'] = function()
  child.cmd('colorscheme blue')
  load_module({ background = '#222222', foreground = '#dddddd' })
  validate_hl_group('Normal', 'guifg=#dddddd guibg=#222222')
end

T['setup()']['respects `config.n_hues`'] = function()
  load_module({ background = '#222222', foreground = '#dddddd', n_hues = 1 })

  validate_hl_group('DiagnosticError', 'guifg=#ffc7da')
  validate_hl_group('DiagnosticHint', 'guifg=#ffc7da')
end

T['setup()']['respects `config.saturation`'] = function()
  local validate = function(saturation, ref_error_fg)
    load_module({ background = '#222222', foreground = '#dddddd', saturation = saturation })
    validate_hl_group('DiagnosticError', 'guifg=' .. ref_error_fg)
  end

  validate('low', '#f5d3dc')
  validate('lowmedium', '#ffcddb')
  validate('medium', '#ffc7da')
  validate('mediumhigh', '#ffb5cf')
  validate('high', '#ffa8c6')

  expect.error(
    function() load_module({ background = '#222222', foreground = '#dddddd', saturation = 'aaa' }) end,
    'one of.*"high"'
  )
end

T['setup()']['respects `config.accent`'] = function()
  load_module({ background = '#222222', foreground = '#dddddd', accent = 'red' })

  validate_hl_group('WinSeparator', 'guifg=#ffc7da')

  expect.error(
    function() load_module({ background = '#222222', foreground = '#dddddd', accent = 'aaa' }) end,
    'one of.*"bg"'
  )
end

T['setup()']['respects `config.plugins`'] = function()
  load_module({ background = '#222222', foreground = '#dddddd' })

  local clear_highlight = function()
    child.cmd('highlight clear')
    expect.match(child.cmd_capture('hi MiniCursorword'), 'cleared')
  end

  -- By default it should load plugin integrations
  clear_highlight()
  load_module({ background = '#222222', foreground = '#dddddd' })
  validate_hl_group('MiniCursorword', 'cterm=underline gui=underline')

  -- If supplied `false`, should not load plugin integration
  clear_highlight()
  reload_module({
    background = '#222222',
    foreground = '#dddddd',
    plugins = { ['nvim-mini/mini.nvim'] = false, ['echasnovski/mini.nvim'] = false },
  })
  expect.match(child.cmd_capture('hi MiniCursorword'), 'cleared')

  -- Should allow loading only chosen integrations
  clear_highlight()
  reload_module({
    background = '#222222',
    foreground = '#dddddd',
    plugins = { default = false, ['echasnovski/mini.nvim'] = true },
  })
  validate_hl_group('MiniCursorword', 'cterm=underline gui=underline')
  expect.match(child.cmd_capture('hi GitSignsAdd'), 'cleared')
end

T['setup()']['respects `config.autoadjust`'] = function()
  -- By default it should autoadjust
  child.cmd('highlight clear')
  child.o.fillchars = 'msgsep:-'
  load_module({ background = '#222222', foreground = '#dddddd' })
  -- - Should also initially pick proper attributes
  validate_hl_group('MsgSeparator', 'guifg=#dddddd')

  child.o.fillchars = 'msgsep: '
  validate_hl_group('MsgSeparator', 'guibg=#3e3e3e')
  child.o.fillchars = 'msgsep:-'
  validate_hl_group('MsgSeparator', 'guifg=#dddddd')

  -- Should not autoadjust if `autoadjust = false`
  child.cmd('highlight clear')
  child.api.nvim_del_augroup_by_name('MiniHuesAdjust')
  child.o.fillchars = 'msgsep:-'
  load_module({ background = '#222222', foreground = '#dddddd', autoadjust = false })
  validate_hl_group('MsgSeparator', 'guifg=#dddddd guibg=#3e3e3e')
  child.o.fillchars = 'msgsep: '
  validate_hl_group('MsgSeparator', 'guifg=#dddddd guibg=#3e3e3e')

  -- Should autoadjust `Pmenu` based on 'pumborder'
  if child.fn.has('nvim-0.12') == 1 then
    child.cmd('highlight clear')
    child.o.pumborder = 'single'
    load_module({ background = '#222222', foreground = '#dddddd' })
    validate_hl_group('Pmenu', 'links to NormalFloat')

    child.o.pumborder = 'none'
    validate_hl_group('Pmenu', 'guifg=#dddddd guibg=#3e3e3e')
  end
end

T['make_palette()'] = new_set()

local make_palette = function(...) return child.lua_get([[require('mini.hues').make_palette(...)]], { ... }) end

--stylua: ignore
local validate_nonbase_colors = function(config, ref_colors)
  local palette = make_palette(config)
  eq(
    {
      red    = palette.red,
      orange = palette.orange,
      yellow = palette.yellow,
      green  = palette.green,
      cyan   = palette.cyan,
      azure  = palette.azure,
      blue   = palette.blue,
      purple = palette.purple,
    },
    ref_colors
  )
end

--stylua: ignore
T['make_palette()']['works'] = function()
  eq(
  make_palette({ background = '#222222', foreground = '#dddddd' }),
  {
    bg_edge2  = '#080808',
    bg_edge   = '#161616',
    bg        = '#222222',
    bg_mid    = '#3e3e3e',
    bg_mid2   = '#5c5c5c',
    fg_edge2  = '#f4f4f4',
    fg_edge   = '#e8e8e8',
    fg        = '#dddddd',
    fg_mid    = '#bbbbbb',
    fg_mid2   = '#9a9a9a',
    red       = '#ffc7da',
    red_bg    = '#3e0c20',
    orange    = '#ffcbb1',
    orange_bg = '#431700',
    yellow    = '#f2dca0',
    yellow_bg = '#453500',
    green     = '#c7eab5',
    green_bg  = '#122d00',
    cyan      = '#a1efdf',
    cyan_bg   = '#004940',
    azure     = '#a5e6ff',
    azure_bg  = '#004053',
    blue      = '#c0d2ff',
    blue_bg   = '#141d48',
    purple    = '#f2ceff',
    purple_bg = '#30133c',
    accent    = '#dddddd',
    accent_bg = '#222222',
  })

  eq(
  make_palette({ background = '#dddddd', foreground = '#222222' }),
  {
    bg_edge2  = '#f4f4f4',
    bg_edge   = '#e8e8e8',
    bg        = '#dddddd',
    bg_mid    = '#bbbbbb',
    bg_mid2   = '#9a9a9a',
    fg_edge2  = '#080808',
    fg_edge   = '#161616',
    fg        = '#222222',
    fg_mid    = '#3e3e3e',
    fg_mid2   = '#5c5c5c',
    red       = '#3e0c20',
    red_bg    = '#ffc7da',
    orange    = '#431700',
    orange_bg = '#ffcbb1',
    yellow    = '#453500',
    yellow_bg = '#f2dca0',
    green     = '#122d00',
    green_bg  = '#c7eab5',
    cyan      = '#004940',
    cyan_bg   = '#a1efdf',
    azure     = '#004053',
    azure_bg  = '#a5e6ff',
    blue      = '#141d48',
    blue_bg   = '#c0d2ff',
    purple    = '#30133c',
    purple_bg = '#f2ceff',
    accent    = '#222222',
    accent_bg = '#dddddd',
  })
end

T['make_palette()']['correctly shifts hue of non-base colors'] = function()
  -- Chromatic background, gray foreground
  local validate_bg = function(input_bg, ref_red)
    eq(make_palette({ background = input_bg, foreground = '#dddddd' }).red, ref_red)
  end

  validate_bg('#2e1c24', '#ffc6cb')
  validate_bg('#2f1c22', '#ffc7c4')
  validate_bg('#2f1c1f', '#ffc8e8')
  validate_bg('#2f1d1c', '#ffc7d9')
  validate_bg('#2f1d1a', '#ffc6d2')

  -- Gray background, chromatic foreground
  local validate_fg = function(input_fg, ref_red)
    eq(make_palette({ background = '#dddddd', foreground = input_fg }).red, ref_red)
  end

  validate_fg('#2e1c24', '#400c16')
  validate_fg('#2f1c22', '#410d10')
  validate_fg('#2f1c1f', '#3b0e2a')
  validate_fg('#2f1d1c', '#3f0d21')
  validate_fg('#2f1d1a', '#400c1b')

  -- Chromatic background, chromatic foreground
  local validate_both = function(input_fg, ref_red)
    eq(make_palette({ background = '#2f1c22', foreground = input_fg }).red, ref_red)
  end

  validate_both('#d8bfc6', '#f7b2b0')
  validate_both('#d9bfc2', '#ecb2d5')
  validate_both('#f7b2b1', '#eeb2d1')
  validate_both('#f6b3a7', '#f5b1b6')
  validate_both('#f5b59f', '#f6b2b1')
  validate_both('#f2b897', '#ebb3d7')
end

--stylua: ignore
T['make_palette()']['respects `config.n_hues`'] = function()
  -- Works in general
  validate_nonbase_colors(
    { background = '#2f1c22', foreground = '#d8bfc6', n_hues = 8 },
    {
      red  = '#f7b2b0', orange = '#ebbd8f', yellow = '#c8cc90', green  = '#9cd7b2',
      cyan = '#85d7dc', azure  = '#9cccf8', blue   = '#c7bef7', purple = '#e9b3da',
    }
  )
  validate_nonbase_colors(
    { background = '#2f1c22', foreground = '#d8bfc6', n_hues = 6 },
    {
      red  = '#f6b3a9', orange = '#f6b3a9', yellow = '#dbc58a', green  = '#a3d6ab',
      cyan = '#86d5e3', azure  = '#86d5e3', blue   = '#b1c5fc', purple = '#e4b4e0',
    }
  )
  validate_nonbase_colors(
    { background = '#2f1c22', foreground = '#d8bfc6', n_hues = 4 },
    {
      red  = '#f4b79d', orange = '#f4b79d', yellow = '#b1d39e', green  = '#b1d39e',
      cyan = '#8cd2ed', azure  = '#8cd2ed', blue   = '#dab8eb', purple = '#dab8eb',
    }
  )
  validate_nonbase_colors(
    { background = '#2f1c22', foreground = '#d8bfc6', n_hues = 2 },
    {
      red  = '#dbc58a', orange = '#dbc58a', yellow = '#dbc58a', green  = '#dbc58a',
      cyan = '#b1c5fc', azure  = '#b1c5fc', blue   = '#b1c5fc', purple = '#b1c5fc',
    }
  )
  validate_nonbase_colors(
    { background = '#2f1c22', foreground = '#d8bfc6', n_hues = 0 },
    {
      red  = '#c6c6c6', orange = '#c6c6c6', yellow = '#c6c6c6', green  = '#c6c6c6',
      cyan = '#c6c6c6', azure  = '#c6c6c6', blue   = '#c6c6c6', purple = '#c6c6c6',
    }
  )

  -- Properly shifts initial equidistant grid
  validate_nonbase_colors(
    { background = '#2f1e16', foreground = '#d8c1b7', n_hues = 2 },
    {
      red  = '#dbb7ea', orange = '#dbb7ea', yellow = '#b0d39f', green  = '#b0d39f',
      cyan = '#b0d39f', azure  = '#b0d39f', blue   = '#dbb7ea', purple = '#dbb7ea',
    }
  )
end

--stylua: ignore
T['make_palette()']['respects `config.saturation`'] = function()
  validate_nonbase_colors(
    { background = '#222222', foreground = '#dddddd', saturation = 'low' },
    {
      red  = '#f5d3dc', orange = '#f5d6c8', yellow = '#e7ddc0', green  = '#d2e4c9',
      cyan = '#c2e6de', azure  = '#c2e3f1', blue   = '#d3ddf9', purple = '#e7d6f0',
    }
  )
  validate_nonbase_colors(
    { background = '#222222', foreground = '#dddddd', saturation = 'high' },
    {
      red  = '#ffa8c6', orange = '#ffb28d', yellow = '#ffd863', green  = '#aef585',
      cyan = '#1dffe1', azure  = '#82ddff', blue   = '#9cb6ff', purple = '#ebb2ff',
    }
  )
end

--stylua: ignore
T['make_palette()']['respects `config.accent`'] = function()
  local validate = function(accent, ref_colors)
    local palette = make_palette({ background = '#222222', foreground = '#d8c1b7', accent = accent })
    eq({ accent_bg = palette.accent_bg, accent = palette.accent }, ref_colors)
  end

  validate('bg',     { accent_bg = '#222222', accent = '#c6c6c6' })
  validate('fg',     { accent_bg = '#431600', accent = '#d8c1b7' })
  validate('red',    { accent_bg = '#410c0f', accent = '#f6b2af' })
  validate('orange', { accent_bg = '#492a00', accent = '#eabd8f' })
  validate('yellow', { accent_bg = '#343700', accent = '#c7cc90' })
  validate('green',  { accent_bg = '#003a20', accent = '#9bd7b2' })
  validate('cyan',   { accent_bg = '#004b50', accent = '#85d6dd' })
  validate('azure',  { accent_bg = '#002a4b', accent = '#9dccf8' })
  validate('blue',   { accent_bg = '#241844', accent = '#c7bef7' })
  validate('purple', { accent_bg = '#390f2f', accent = '#e9b3d9' })
end

T['make_palette()']['validates arguments'] = function()
  expect.error(function() make_palette({ background = 1 }) end, '`background`.*#rrggbb')
  expect.error(function() make_palette({ background = bg, foreground = 1 }) end, '`foreground`.*#rrggbb')

  expect.error(function() make_palette({ background = bg, foreground = fg, n_hues = 'a' }) end, '`n_hues`.*number')
  expect.error(function() make_palette({ background = bg, foreground = fg, n_hues = -1 }) end, '0')
  expect.error(function() make_palette({ background = bg, foreground = fg, n_hues = 9 }) end, '8')

  expect.error(function() make_palette({ background = bg, foreground = fg, saturation = 'aaa' }) end, 'one of.*"high"')

  expect.error(function() make_palette({ background = bg, foreground = fg, accent = 'aaa' }) end, 'one of.*"bg"')
end

T['apply_palette()'] = new_set()

local apply_palette = function(...) return child.lua_get([[require('mini.hues').apply_palette(...)]], { ... }) end

T['apply_palette()']['works'] = function()
  child.cmd('hi Normal guifg=#eeeeee')
  child.cmd('hi String guifg=#00ff00')

  local palette = make_palette({ background = '#222222', foreground = '#dddddd' })
  palette.fg = '#aaaaaa'
  apply_palette(palette)

  validate_hl_group('Normal', 'guifg=#aaaaaa guibg=#222222')
  validate_hl_group('String', 'guifg=#c7eab5')
  validate_hl_group('@variable', 'guifg=#aaaaaa')
  validate_hl_group('MiniCursorword', 'cterm=underline gui=underline')
  validate_hl_group('WhichKey', 'guifg=#a1efdf')
  validate_hl_group('@lsp.type.variable', 'links to @variable')
  eq(child.g.terminal_color_0, '#080808')
end

T['apply_palette()']['respects `plugins`'] = function()
  local palette = make_palette({ background = '#222222', foreground = '#dddddd' })
  apply_palette(palette, { default = false, ['echasnovski/mini.nvim'] = true })
  validate_hl_group('MiniCursorword', 'cterm=underline gui=underline')
  validate_hl_group('WhichKey', 'cleared')

  -- Uses the one from `config` by default
  child.cmd('hi clear')
  child.lua([[require('mini.hues').setup({
    background = '#222222',
    foreground = '#dddddd',
    plugins = { default = true, ["nvim-mini/mini.nvim"] = false, ["echasnovski/mini.nvim"] = false },
  })]])
  apply_palette(palette)
  validate_hl_group('MiniCursorword', 'cleared')
  validate_hl_group('WhichKey', 'guifg=#a1efdf')
end

T['apply_palette()']['respects `opts.autoadjust`'] = function()
  local palette = make_palette({ background = '#222222', foreground = '#dddddd' })

  -- By default it should follow `config.autoadjust`
  child.lua('MiniHues.config.autoadjust = false')
  child.cmd('highlight clear')
  child.o.fillchars = 'msgsep:-'

  apply_palette(palette)
  validate_hl_group('MsgSeparator', 'guifg=#dddddd guibg=#3e3e3e')

  child.o.fillchars = 'msgsep: '
  validate_hl_group('MsgSeparator', 'guifg=#dddddd guibg=#3e3e3e')

  -- Should respect `opts.autoadjust` value
  child.o.fillchars = 'msgsep: '
  apply_palette(palette, {}, { autoadjust = true })
  validate_hl_group('MsgSeparator', 'guibg=#3e3e3e')

  child.o.fillchars = 'msgsep:-'
  validate_hl_group('MsgSeparator', 'guifg=#dddddd')
end

T['apply_palette()']['clears highlight groups'] = function()
  child.cmd('hi AAA guifg=#cccccc')
  local palette = make_palette({ background = '#222222', foreground = '#dddddd' })

  -- Should execute `:hi clear` only if there was previous color scheme applied
  apply_palette(palette)
  validate_hl_group('AAA', 'guifg=#cccccc')

  child.g.colors_name = 'some_colorscheme'
  apply_palette(palette)
  validate_hl_group('AAA', 'cleared')
end

T['apply_palette()']['clears `g:colors_name`'] = function()
  child.g.colors_name = 'hello'
  local palette = make_palette({ background = '#222222', foreground = '#dddddd' })
  apply_palette(palette)
  eq(child.g.colors_name, vim.NIL)
end

T['apply_palette()']['validates input'] = function()
  expect.error(function() apply_palette('a') end, '`palette`.*table')

  local palette = make_palette({ background = '#222222', foreground = '#dddddd' })
  expect.error(function() apply_palette(palette, 'a') end, '`plugins`.*table')
end

T['get_palette()'] = new_set()

T['get_palette()']['works'] = function()
  local res = child.lua([[
    local palette = MiniHues.make_palette({ background = '#222222', foreground = '#dddddd' })
    palette.fg = '#aaaaaa'
    MiniHues.apply_palette(palette)

    local res_palette = MiniHues.get_palette()
    local is_same = vim.deep_equal(palette, res_palette)

    -- Should not be affected by change in applied palette
    palette.bg = '#000000'
    local is_same_1 = vim.deep_equal(palette, res_palette)

    -- Should return copy
    res_palette.bg = '#000000'
    local is_same_2 = vim.deep_equal(MiniHues.get_palette(), res_palette)

    return { is_same, is_same_1, is_same_2 }
  ]])

  eq(res, { true, false, false })
end

T['gen_random_base_colors()'] = new_set()

T['gen_random_base_colors()']['works'] = function()
  -- With dark background
  child.o.background = 'dark'
  child.lua('math.randomseed(20230504)')
  eq(
    child.lua_get([[require('mini.hues').gen_random_base_colors()]]),
    { background = '#292111', foreground = '#c9c6c0' }
  )

  -- With lightness background
  child.o.background = 'light'
  child.lua('math.randomseed(20230504)')
  eq(
    child.lua_get([[require('mini.hues').gen_random_base_colors()]]),
    { background = '#e5e2db', foreground = '#302e29' }
  )
end

T['gen_random_base_colors()']['respects `opts.gen_hue`'] = function()
  child.o.background = 'dark'
  for _ = 1, 2 do
    eq(
      child.lua_get([[require('mini.hues').gen_random_base_colors({ gen_hue = function() return 0 end })]]),
      { background = '#2f1c22', foreground = '#cdc4c6' }
    )
  end

  eq(
    child.lua_get([[require('mini.hues').gen_random_base_colors({ gen_hue = function() return 720 end })]]),
    { background = '#2f1c22', foreground = '#cdc4c6' }
  )
end

T['gen_random_base_colors()']['validates arguments'] = function()
  expect.error(
    function() child.lua([[require('mini.hues').gen_random_base_colors({ gen_hue = 1 })]]) end,
    '`gen_hue`.*callable'
  )
end

T['Bundled color schemes'] = new_set()

T['Bundled color schemes']['works'] = function()
  -- randomhue
  expect.no_error(function() child.cmd('colorscheme randomhue') end)
  eq(child.fn.hlexists('MiniCursorword'), 1)

  local validate_lightness = function()
    local hl = child.api.nvim_get_hl(0, { name = 'Normal' })
    -- NOTE: This is not 100% proper solution, but at least it is something
    if child.o.background == 'dark' then eq(hl.fg > hl.bg, true) end
    if child.o.background == 'light' then eq(hl.fg < hl.bg, true) end
  end

  child.o.background = 'dark'
  validate_lightness()
  child.o.background = 'light'
  validate_lightness()

  -- Four seasons
  local validate = function(cs_name, ref_bg)
    expect.no_error(function() child.cmd('colorscheme ' .. cs_name) end)
    expect.match(child.cmd_capture('hi Normal'), 'guibg=' .. ref_bg)
  end

  child.o.background = 'dark'
  validate('miniwinter', '#11262d')
  validate('minispring', '#1c2617')
  validate('minisummer', '#27211e')
  validate('miniautumn', '#262029')

  child.o.background = 'light'
  validate('miniwinter', '#dce4e8')
  validate('minispring', '#e0e4de')
  validate('minisummer', '#e9e1dd')
  validate('miniautumn', '#e5e1e7')
end

return T
