local helpers = dofile('tests/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq, eq_approx = helpers.expect, helpers.expect.equality, helpers.expect.equality_approx
local new_set = MiniTest.new_set

local dir_path = vim.fn.fnamemodify('tests/dir-colors/', ':p')
local colors_path = dir_path .. '/colors/'

-- Helpers with child processes
local load_module = function(config) child.mini_load('colors', config) end
local unload_module = function(config) child.mini_unload('colors', config) end
local type_keys = function(...) return child.type_keys(...) end
local sleep = function(ms) helpers.sleep(ms, child) end

-- Mock test color scheme
local mock_cs = function() child.cmd('set rtp+=' .. dir_path .. 'mock_cs/') end

-- Time constants
local default_transition_duration, default_show_duration = 1000, 1000
local default_transition_steps = 25
local small_transition_time = 0.5 * (default_transition_duration / default_transition_steps)
local small_time = helpers.get_time_const(10)

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      load_module()
    end,
    post_once = child.stop,
  },
  n_retry = helpers.get_n_retry(2),
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  -- Global variable
  eq(child.lua_get('type(_G.MiniColors)'), 'table')

  -- `Colorscheme` command
  eq(child.fn.exists(':Colorscheme'), 2)
end

T['setup()']['creates `config` field'] = function() eq(child.lua_get('type(_G.MiniColors.config)'), 'table') end

T['as_colorscheme()'] = new_set()

T['as_colorscheme()']['works'] = function()
  child.lua([[_G.cs_data = {
    name = 'my_test_cs',
    groups = { Normal = { fg = '#ffffff', bg = '#000000' } },
    terminal = { [0] = '#111111' }
  }]])
  child.lua('_G.cs = MiniColors.as_colorscheme(_G.cs_data)')

  -- Fields
  local validate_field = function(field, value) eq(child.lua_get('_G.cs.' .. field), value) end

  validate_field('name', 'my_test_cs')

  validate_field('groups.Normal', { fg = '#ffffff', bg = '#000000' })

  validate_field('terminal[0]', '#111111')

  -- Methods
  local validate_method = function(method)
    local lua_cmd = string.format('type(_G.cs.%s)', method)
    eq(child.lua_get(lua_cmd), 'function')
  end

  validate_method('apply')
  validate_method('add_cterm_attributes')
  validate_method('add_terminal_colors')
  validate_method('add_transparency')
  validate_method('chan_add')
  validate_method('chan_invert')
  validate_method('chan_modify')
  validate_method('chan_multiply')
  validate_method('chan_repel')
  validate_method('chan_set')
  validate_method('color_modify')
  validate_method('compress')
  validate_method('get_palette')
  validate_method('resolve_links')
  validate_method('simulate_cvd')
  validate_method('write')

  -- Should not modify input table
  eq(child.lua_get('type(_G.cs_data.apply)'), 'nil')

  -- Should not require any input data
  expect.no_error(function() child.lua('MiniColors.as_colorscheme({})') end)
end

T['as_colorscheme()']['validates arguments'] = function()
  expect.error(function() child.lua('MiniColors.as_colorscheme(1)') end, '%(mini%.colors%).*table')

  expect.error(
    function() child.lua('MiniColors.as_colorscheme({groups = 1})') end,
    '%(mini%.colors%).*groups.*table or nil'
  )
  expect.error(
    function() child.lua('MiniColors.as_colorscheme({groups = { 1 }})') end,
    '%(mini%.colors%).*All elements.*groups.*tables'
  )

  expect.error(
    function() child.lua('MiniColors.as_colorscheme({terminal = 1})') end,
    '%(mini%.colors%).*terminal.*table or nil'
  )
  expect.error(
    function() child.lua('MiniColors.as_colorscheme({terminal = { 1 }})') end,
    '%(mini%.colors%).*All elements.*terminal.*strings'
  )
end

T['as_colorscheme()']['ensures independence of groups'] = function()
  child.lua([[_G.hl_group = { fg = '#012345' }]])
  child.lua([[_G.cs = MiniColors.as_colorscheme({ groups = { Normal = hl_group, NormalNC = hl_group }})]])

  eq(child.lua_get('_G.cs.groups.Normal == _G.cs.groups.NormalNC'), false)
end

T['as_colorscheme() methods'] = new_set()

T['as_colorscheme() methods']['add_cterm_attributes()'] = function()
  child.lua([[_G.cs = MiniColors.as_colorscheme({
    groups = {
      Normal          = { fg = '#5f87af', bg = '#080808' },
      TestForce       = { fg = '#5f87af', ctermfg = 0 },
      TestApprox      = { fg = '#5f87aa' },
      TestNormalCterm = { ctermfg = 67,   ctermbg = 232 },
      TestSpecial     = { sp = '#00ff00', underline = true },
    }
  })]])

  -- Default
  eq(child.lua_get('_G.cs:add_cterm_attributes().groups'), {
    -- Updates both `guifg` and `guibg`. Works with chromatics and grays.
    Normal = { fg = '#5f87af', ctermfg = 67, bg = '#080808', ctermbg = 232 },
    -- Updates already present `cterm` (`force = true` by default)
    TestForce = { fg = '#5f87af', ctermfg = 67 },
    -- Should be able to approximate
    TestApprox = { fg = '#5f87aa', ctermfg = 67 },
    -- Doesn't change `cterm` if no corresponding `gui`
    TestNormalCterm = { ctermbg = 232, ctermfg = 67 },
    -- Doesn't touch `sp`
    TestSpecial = { sp = '#00ff00', underline = true },
  })

  -- - Should return copy without modifying original
  eq(child.lua_get('_G.cs.groups.Normal.ctermfg'), vim.NIL)

  -- With `force = false`
  eq(child.lua_get('_G.cs:add_cterm_attributes({ force = false }).groups.TestForce'), { fg = '#5f87af', ctermfg = 0 })
end

T['as_colorscheme() methods']['add_terminal_colors()'] = new_set()

T['as_colorscheme() methods']['add_terminal_colors()']['works'] = function()
  child.lua([[_G.cs = MiniColors.as_colorscheme({
    groups = {
      Normal = { fg = '#c7c7c7', bg = '#2e2e2e' },
      Test1  = { fg = '#ffaea0', bg = '#e0c479' },
      Test2  = { fg = '#97d9a4', bg = '#70d9eb' },
      Test3  = { fg = '#aec4ff', sp = '#ecafe6' },
    }
  })]])

  eq(
    child.lua_get([[vim.deep_equal(_G.cs:add_terminal_colors().terminal, {
    [0] = '#2e2e2e', [8] = '#2e2e2e',
    [1] = '#ffaea0', [9] = '#ffaea0',
    [2] = '#97d9a4', [10] = '#97d9a4',
    [3] = '#e0c479', [11] = '#e0c479',
    [4] = '#aec4ff', [12] = '#aec4ff',
    [5] = '#ecafe6', [13] = '#ecafe6',
    [6] = '#70d9eb', [14] = '#70d9eb',
    [7] = '#c7c7c7', [15] = '#c7c7c7',
  })]]),
    true
  )
end

T['as_colorscheme() methods']['add_terminal_colors()']['uses present terminal colors'] = function()
  child.lua([[_G.cs = MiniColors.as_colorscheme({
    groups = {
      Normal = { fg = '#c7c7c7', bg = '#2e2e2e' },
    },
    terminal = {
    [0] = '#ffaea0', [8] = '#97d9a4',
    [1] = '#2e2e2e', [9] = '#e0c479',
    [2] = '#e0c479', [10] = '#2e2e2e',
    [3] = '#97d9a4', [11] = '#ffaea0',
    [4] = '#ecafe6', [12] = '#70d9eb',
    [5] = '#aec4ff', [13] = '#c7c7c7',
    [6] = '#c7c7c7', [14] = '#aec4ff',
    [7] = '#70d9eb', [15] = '#ecafe6',
  }
  })]])

  eq(
    child.lua_get([[vim.deep_equal(_G.cs:add_terminal_colors().terminal, {
    [0] = '#2e2e2e', [8] = '#2e2e2e',
    [1] = '#ffaea0', [9] = '#ffaea0',
    [2] = '#97d9a4', [10] = '#97d9a4',
    [3] = '#e0c479', [11] = '#e0c479',
    [4] = '#aec4ff', [12] = '#aec4ff',
    [5] = '#ecafe6', [13] = '#ecafe6',
    [6] = '#70d9eb', [14] = '#70d9eb',
    [7] = '#c7c7c7', [15] = '#c7c7c7',
  })]]),
    true
  )
end

T['as_colorscheme() methods']['add_terminal_colors()']['properly approximates'] = function()
  local validate_red = function(hex) eq(child.lua_get('_G.cs:add_terminal_colors().terminal[1]'), hex) end

  -- Picks proper red if it exists in palette
  child.lua([[_G.cs = MiniColors.as_colorscheme({
    groups = {
      -- Reference lightness should be taken from `Normal.fg` (80 in this case)
      Normal = { fg = '#c7c7c7', bg = '#2e2e2e' },
      -- Proper red with `l = 80, h = 30`
      Test   = { fg = '#ffaea0' },
      -- Different lightness
      TestDiffL = { fg = '#f2a193', bg = '#ffbfb2' },
      -- Different hue
      TestDiffH = { fg = '#ffada6', bg = '#ffaf9b' },
    }
  })]])
  validate_red('#ffaea0')

  -- Properly picks closest lightness in absence of perfect hue
  child.lua([[_G.cs = MiniColors.as_colorscheme({
    groups = {
      Normal = { fg = '#c7c7c7', bg = '#2e2e2e' },
      -- All have hue 40, but lightness 70, 79, 90
      TestDiffL = { fg = '#e2967b', bg = '#f1a388', sp = '#ffd7c6' },
    }
  })]])
  validate_red('#f1a388')

  -- Properly picks closest hue in absence of perfect lightness
  child.lua([[_G.cs = MiniColors.as_colorscheme({
    groups = {
      Normal = { fg = '#c7c7c7', bg = '#2e2e2e' },
      -- All have lightness 80, but hue 20, 29, 40
      TestDiffH = { fg = '#ffadac', bg = '#ffaea1', sp = '#ffb195' },
    }
  })]])
  validate_red('#ffaea1')

  -- Doesn't take chroma into account
  child.lua([[_G.cs = MiniColors.as_colorscheme({
    groups = {
      Normal = { fg = '#c7c7c7', bg = '#2e2e2e' },
      -- The `fg` has correct lightness and hue but chroma is only 1
      -- The `bg` has more vivid colors, but lightness is 74
      -- So, `fg` should be picked as correct one
      Test = { fg = '#cdc4c3', bg = '#fe9584' },
    }
  })]])
  validate_red('#cdc4c3')
end

T['as_colorscheme() methods']['add_terminal_colors()']['respects `opts.force`'] = function()
  child.lua([[_G.cs = MiniColors.as_colorscheme({
    groups = {
      Normal = { fg = '#c7c7c7', bg = '#2e2e2e' },
      Test   = { fg = '#ffaea0' },
    },
    terminal = { [1] = '#012345' }
  })]])

  eq(child.lua_get('_G.cs:add_terminal_colors({ force = false }).terminal[1]'), '#012345')
end

T['as_colorscheme() methods']['add_terminal_colors()']['respects `opts.palette_args`'] = function()
  child.lua([[_G.cs = MiniColors.as_colorscheme({
    groups = {
      Normal = { fg = '#c7c7c7', bg = '#2e2e2e' },
      Test   = { fg = '#012345', bg = '#012345', sp = '#012345' },
      -- Although this `fg` is a perfect match, it won't be used due to not
      -- being frequent enough
      Test2  = { fg = '#ffaea0', bg = '#012345' }
    }
  })]])

  eq(child.lua_get('_G.cs:add_terminal_colors({ palette_args = { threshold = 0.5 } }).terminal[1]'), '#012345')
end

T['as_colorscheme() methods']['add_terminal_colors()']['handles not proper `Normal` highlight group'] = function()
  -- Absent (should fall back on lightness depending on background)
  child.cmd('hi clear Normal')
  child.lua([[_G.cs = MiniColors.as_colorscheme({
    groups = {
      -- The `fg` has fallback lightness for light background, `bg` - for dark
      Test   = { fg = '#470301', bg = '#ffbfb2' },
    }
  })]])

  child.o.background = 'dark'
  eq(child.lua_get('_G.cs:add_terminal_colors().terminal[1]'), '#ffbfb2')

  child.o.background = 'light'
  eq(child.lua_get('_G.cs:add_terminal_colors().terminal[1]'), '#470301')

  -- Linked
  child.lua([[_G.cs = MiniColors.as_colorscheme({
    groups = {
      NormalLink = { fg = '#c7c7c7', bg = '#2e2e2e' },
      Normal = { link = 'NormalLink' },
      -- The `fg` has perfect fit while `bg` uses fallback lightness
      Test   = { fg = '#ffaea0', bg = '#ffbfb2' },
    }
  })]])
  eq(child.lua_get('_G.cs:add_terminal_colors().terminal[1]'), '#ffaea0')
end

T['as_colorscheme() methods']['add_transparency()'] = new_set()

T['as_colorscheme() methods']['add_transparency()']['works'] = function()
  child.lua([[_G.hl_group = { fg = '#aaaaaa', ctermfg = 255, bg = '#111111', ctermbg = 232, }]])
  local hl_group = child.lua_get('_G.hl_group')
  local hl_transparent = { fg = '#aaaaaa', ctermfg = 255, blend = 0 }

  child.lua([[_G.cs = MiniColors.as_colorscheme({
    groups = {
      -- General (should be made transparent)
      Normal = hl_group,
      NormalNC = { bg = '#111111' },
      EndOfBuffer = { ctermbg = 232 },
      MsgArea = { blend = 50 },
      ErrorMsg = { bg = '#000000' },
      MsgSeparator = hl_group,
      VertSplit = hl_group,
      WinSeparator = hl_group,

      -- Other (should be left as is)
      NormalFloat = hl_group,
      SignColumn = hl_group,
      StatusLine = hl_group,
      TabLine = hl_group,
      WinBar = hl_group,
    }
  })]])

  child.lua('_G.cs_trans = _G.cs:add_transparency()')

  eq(child.lua_get('_G.cs_trans.groups'), {
    Normal = hl_transparent,
    NormalNC = { blend = 0 },
    EndOfBuffer = { blend = 0 },
    MsgArea = { blend = 0 },
    ErrorMsg = { blend = 0 },
    MsgSeparator = hl_transparent,
    VertSplit = hl_transparent,
    WinSeparator = hl_transparent,

    NormalFloat = hl_group,
    SignColumn = hl_group,
    StatusLine = hl_group,
    TabLine = hl_group,
    WinBar = hl_group,
  })

  -- Should return copy without modifying original
  eq(child.lua_get('_G.cs.groups.Normal.bg'), '#111111')
end

T['as_colorscheme() methods']['add_transparency()']['works with not all groups present'] = function()
  child.lua([[_G.cs = MiniColors.as_colorscheme({ groups = { Normal = { bg = '#012345' } } })]])
  eq(child.lua_get('_G.cs:add_transparency().groups'), { Normal = { blend = 0 } })
end

T['as_colorscheme() methods']['add_transparency()']['respects `opts`'] = function()
  child.lua([[_G.hl_group = { fg = '#aaaaaa', ctermfg = 255, bg = '#111111', ctermbg = 232, }]])
  local hl_group = child.lua_get('_G.hl_group')
  local hl_transparent = { fg = '#aaaaaa', ctermfg = 255, blend = 0 }

  local validate_groups_become_transparent = function(opts, groups)
    -- Create colorscheme object
    local group_fields = vim.tbl_map(function(x) return x .. ' = hl_group' end, groups)
    local lua_cmd =
      string.format('_G.cs = MiniColors.as_colorscheme({ groups = { %s } })', table.concat(group_fields, ', '))
    child.lua(lua_cmd)

    -- Validate
    local ref_groups = {}
    for _, gr in ipairs(groups) do
      ref_groups[gr] = hl_transparent
    end

    local lua_get_cmd = string.format('_G.cs:add_transparency(%s).groups', vim.inspect(opts))
    eq(child.lua_get(lua_get_cmd), ref_groups)
  end

  -- opts.general
  child.lua([[_G.cs = MiniColors.as_colorscheme({ groups = { Normal = hl_group } })]])
  eq(child.lua_get('_G.cs:add_transparency({ general = false }).groups.Normal'), hl_group)

  -- Other
  validate_groups_become_transparent({ float = true }, { 'FloatBorder', 'FloatTitle', 'NormalFloat' })
  --stylua: ignore
  validate_groups_become_transparent(
    { statuscolumn = true },
    {
      'FoldColumn', 'LineNr', 'LineNrAbove', 'LineNrBelow', 'SignColumn',
      'DiagnosticSignError', 'DiagnosticSignWarn', 'DiagnosticSignInfo', 'DiagnosticSignHint', 'DiagnosticSignOk',
    }
  )
  validate_groups_become_transparent(
    { statusline = true },
    { 'StatusLine', 'StatusLineNC', 'StatusLineTerm', 'StatusLineTermNC' }
  )
  validate_groups_become_transparent({ tabline = true }, { 'TabLine', 'TabLineFill', 'TabLineSel' })
  validate_groups_become_transparent({ winbar = true }, { 'WinBar', 'WinBarNC' })
end

T['as_colorscheme() methods']['add_transparency()']['respects sign highlight groups'] = function()
  child.fn.sign_define('Sign1', { texthl = 'Texthl', numhl = 'Numhl' })

  child.lua([[_G.cs = MiniColors.as_colorscheme({
    groups = {
      Texthl = { bg = '#111111' },
      Numhl = { bg = '#111111' },
    }
  })]])

  eq(child.lua_get('_G.cs:add_transparency({ statuscolumn = true }).groups'), {
    Texthl = { blend = 0 },
    Numhl = { blend = 0 },
  })

  eq(child.lua_get('_G.cs:add_transparency().groups'), {
    Texthl = { bg = '#111111' },
    Numhl = { bg = '#111111' },
  })
end

T['as_colorscheme() methods']['apply()'] = new_set()

T['as_colorscheme() methods']['apply()']['works'] = function()
  -- Define current color scheme data
  child.g.colors_name = 'prior_cs'
  child.api.nvim_set_hl(0, 'Normal', { fg = '#aaaaaa', bg = '#111111' })
  child.api.nvim_set_hl(0, 'TestPartial', { fg = '#aaaaaa', bg = '#111111' })
  child.api.nvim_set_hl(0, 'TestSingle', { fg = '#aaaaaa' })
  child.g.terminal_color_1 = '#aa0000'

  -- Create and apply some color scheme
  child.lua([[_G.cs = MiniColors.as_colorscheme({
    name = 'new_cs',
    groups = {
      Normal = { fg = '#ffffff', bg = '#000000' },
      TestPartial = { fg = '#ffffff' },
      TestNew = { bg = '#000000' }
    },
    terminal = { [0] = '#000000' }
  })]])
  child.lua('_G.cs:apply()')

  -- Validate
  eq(child.g.colors_name, 'new_cs')

  expect.match(child.cmd_capture('hi Normal'), 'guifg=#ffffff%s+guibg=#000000')
  -- - Should override completely without inheriting `bg`
  expect.match(child.cmd_capture('hi TestPartial'), 'guifg=#ffffff$')
  -- - Should clear all highlight groups by default
  expect.match(child.cmd_capture('hi TestSingle'), 'cleared')
  -- - Should be able to create new highlight groups
  expect.match(child.cmd_capture('hi TestNew'), 'guibg=#000000$')

  -- - Should remove all previous terminal colors
  eq(child.g.terminal_color_0, '#000000')
  eq(child.g.terminal_color_1, vim.NIL)
end

T['as_colorscheme() methods']['apply()']['respects `opts.clear`'] = function()
  child.api.nvim_set_hl(0, 'TestSingle', { fg = '#aaaaaa' })

  child.lua([[_G.cs = MiniColors.as_colorscheme({
    groups = { Normal = { fg = '#ffffff' } }
  })]])
  child.lua('_G.cs:apply({ clear = false })')
  expect.match(child.cmd_capture('hi TestSingle'), 'guifg=#aaaaaa$')
end

local create_basic_cs = function()
  child.lua([[_G.cs = MiniColors.as_colorscheme({
    -- Oklch ~ { l = 50, c = 15, h = 0 }
    -- Oklab ~ { l = 50, a = 14.96, b = 0.056 }
    -- Saturation ~ 65
    -- Temperature = 90
    -- Pressure = 180
    -- RGB = { r = 186, g = 74, b = 115 }
    groups = { Normal = { fg = '#ba4a73' } }
  })]])
end

local validate_chan_method = function(method, channel, args, ref_normal_fg)
  local lua_cmd = string.format([[_G.cs_modified = _G.cs:%s('%s', %s)]], method, channel, args)
  child.lua(lua_cmd)

  eq(child.lua_get('_G.cs_modified.groups.Normal.fg'), ref_normal_fg)
end

local validate_self_copy = function(method, value_string)
  local lua_cmd = string.format([[_G.cs_modified = _G.cs:%s('hue', %s)]], method, value_string)
  child.lua(lua_cmd)

  eq(child.lua_get('vim.deep_equal(_G.cs, _G.cs_modified)'), true)
  eq(child.lua_get('_G.cs ~= _G.cs_modified'), true)
end

-- Only basic testing here. More thorough tests are in `chan_modify()`.
T['as_colorscheme() methods']['chan_add()'] = new_set({ hooks = { pre_case = create_basic_cs } })

--stylua: ignore
T['as_colorscheme() methods']['chan_add()']['works'] = function()
  local validate = function(channel, value, ref_normal_fg, opts_string)
    local args = string.format('%s, %s', value, opts_string or '{}')
    validate_chan_method('chan_add', channel, args, ref_normal_fg)
  end

  validate('lightness',   10,  '#d8658d')
  validate('chroma',      -10, '#906b76')
  validate('saturation',  10,  '#c33f72')
  validate('hue',         10,  '#bd4a62')
  validate('temperature', 10,  '#bd4a62')
  validate('pressure',    -10, '#bd4a62')
  validate('a',           -10, '#906b75')
  validate('b',           10,  '#cb4021')
  validate('red',         16,  '#ca4a73')
  validate('green',       16,  '#ba5a73')
  validate('blue',        16,  '#ba4a83')

  -- Should respect `opts`
  validate('chroma', 20, '#e30078', [[{ gamut_clip = 'cusp' }]])

  -- With value 0 should return copy of input
  validate_self_copy('chan_add', '0')
end

T['as_colorscheme() methods']['chan_add()']['validates arguments'] = function()
  expect.error(function() child.lua('_G.cs:chan_add(1, 10)') end, 'Channel.*one of')
  expect.error(function() child.lua([[_G.cs:chan_add('aaa', 10)]]) end, 'Channel.*one of')

  expect.error(function() child.lua([[_G.cs:chan_add('hue', 'a')]]) end, '`value`.*number')
end

-- Only basic testing here. More thorough tests are in `chan_modify()`.
T['as_colorscheme() methods']['chan_invert()'] = new_set({ hooks = { pre_case = create_basic_cs } })

--stylua: ignore
T['as_colorscheme() methods']['chan_invert()']['works'] = function()
  -- Use different color with off-center channel values
  child.lua([[_G.cs = MiniColors.as_colorscheme({
    groups = { Normal = { fg = '#432618' } }
  })]])

  local validate = function(channel, ref_normal_fg, opts_string)
    validate_chan_method('chan_invert', channel, opts_string or '{}', ref_normal_fg)
  end

  validate('lightness',   '#e3bdac')
  -- - Chroma is same as saturation due to lack of good reference point
  validate('chroma',      '#3d291f')
  validate('saturation',  '#3d291f')
  validate('hue',         '#382740')
  validate('temperature', '#382740')
  validate('pressure',    '#243419')
  validate('a',           '#243419')
  validate('b',           '#382740')
  validate('red',         '#bc2618')
  validate('green',       '#43d918')
  validate('blue',        '#4326e7')

  -- Should respect `opts`
  child.lua([[_G.cs.groups.Normal.fg = '#fef0cb']])
  validate('lightness', '#221900', [[{ gamut_clip = 'cusp' }]])
end

T['as_colorscheme() methods']['chan_invert()']['validates arguments'] = function()
  expect.error(function() child.lua('_G.cs:chan_invert(1)') end, 'Channel.*one of')
  expect.error(function() child.lua([[_G.cs:chan_invert('aaa')]]) end, 'Channel.*one of')
end

T['as_colorscheme() methods']['chan_modify()'] = new_set({ hooks = { pre_case = create_basic_cs } })

local validate_chan_modify = function(channel, function_body, ref_normal_fg, opts_string)
  opts_string = opts_string or '{}'
  local lua_cmd = string.format('_G.f = function(x) %s end', function_body)
  child.lua(lua_cmd)

  local lua_get_cmd = string.format([[_G.cs:chan_modify('%s', _G.f, %s).groups.Normal.fg]], channel, opts_string)
  eq(child.lua_get(lua_get_cmd), ref_normal_fg)
end

T['as_colorscheme() methods']['chan_modify()']['works with "lightness"'] = function()
  local validate = function(...) validate_chan_modify('lightness', ...) end

  validate('return x - 10', '#9c2e5a')

  -- Should normalize to [0; 100]
  validate('return 110', '#ffffff')
  validate('return -10', '#000000')

  -- Should respect `opts.gamut_clip`
  validate('return 80', '#ff9bbe', [[{ gamut_clip = 'cusp' }]])
end

T['as_colorscheme() methods']['chan_modify()']['works with "chroma"'] = function()
  local validate = function(...) validate_chan_modify('chroma', ...) end

  validate('return x - 10', '#906b76')

  -- Should normalize to positive number
  validate('return -10', '#777777')

  -- Should respect `opts.gamut_clip`
  validate('return 25', '#da0072', [[{ gamut_clip = 'cusp' }]])
end

T['as_colorscheme() methods']['chan_modify()']['works with "saturation"'] = function()
  local validate = function(...) validate_chan_modify('saturation', ...) end

  validate('return x - 10', '#b15374')

  -- Should normalize to [0; 100]
  validate('return 110', '#d70071')
  validate('return -10', '#777777')

  -- In theory, 'gamut_clip' is unnecessary as it always stays inside gamut
end

T['as_colorscheme() methods']['chan_modify()']['works with "hue"'] = function()
  local validate = function(...) validate_chan_modify('hue', ...) end

  validate('return x + 10', '#bd4a62')

  -- Should periodically normalize to be inside [0; 360)
  validate('return x + 370', '#bd4a62')
  validate('return x - 350', '#bd4a62')

  -- Should respect `opts.gamut_clip`
  validate('return 90', '#a28000', [[{ gamut_clip = 'cusp' }]])

  -- Doesn't have effect on grays (as they have no defined hue)
  child.lua([[_G.cs.groups.Normal.fg = '#aaaaaa']])
  validate('return 90', '#aaaaaa')
end

T['as_colorscheme() methods']['chan_modify()']['works with "temperature"'] = function()
  child.lua([[_G.cs = MiniColors.as_colorscheme({
    -- Test on both hue half-planes ([-90; 90] and [90; 270])
    -- Both colors have temperature 90
    groups = { Normal = { fg = '#ba4a73', bg = '#68cebb' } }
  })]])

  local validate = function(function_body, ref_fg_hex, ref_bg_hex, opts_string)
    opts_string = opts_string or '{}'

    local lua_cmd = string.format('_G.f = function(x) %s end', function_body)
    child.lua(lua_cmd)

    local lua_get_cmd = string.format([[_G.cs:chan_modify('temperature', _G.f, %s).groups.Normal]], opts_string)
    eq(child.lua_get(lua_get_cmd), { fg = ref_fg_hex, bg = ref_bg_hex })
  end

  -- "Temperature" is a circular distance to hue 270
  validate('return x + 10', '#bd4a62', '#71ceaf')

  -- Should normalize to [0; 180]
  validate('return 270', '#927300', '#d2b66b')
  validate('return -90', '#556fce', '#a0b6fa')

  -- Should respect `opts.gamut_clip`
  validate('return 180', '#a28000', '#d2b66b', [[{ gamut_clip = 'cusp' }]])

  -- Doesn't have effect on grays (as they have no defined hue)
  child.lua([[_G.cs.groups.Normal.fg = '#aaaaaa']])
  child.lua([[_G.cs.groups.Normal.bg = '#777777']])
  validate('return 180', '#aaaaaa', '#777777')
end

T['as_colorscheme() methods']['chan_modify()']['works with "pressure"'] = function()
  child.lua([[_G.cs = MiniColors.as_colorscheme({
    -- Test on both hue half-planes ([0; 180] and [180, 360))
    -- Both colors have pressure 90
    groups = { Normal = { fg = '#556fce', bg = '#d2b66b' } }
  })]])

  local validate = function(function_body, ref_fg_hex, ref_bg_hex, opts_string)
    opts_string = opts_string or '{}'

    local lua_cmd = string.format('_G.f = function(x) %s end', function_body)
    child.lua(lua_cmd)

    local lua_get_cmd = string.format([[_G.cs:chan_modify('pressure', _G.f, %s).groups.Normal]], opts_string)
    eq(child.lua_get(lua_get_cmd), { fg = ref_fg_hex, bg = ref_bg_hex })
  end

  -- "Pressure" is a circular distance to hue 180
  validate('return x + 10', '#6769cc', '#dbb26c')

  -- Should normalize to [0; 180]
  validate('return 270', '#ba4a73', '#ee9eb6')
  validate('return -90', '#018a79', '#68cebb')

  -- Should respect `opts.gamut_clip`
  validate('return 0', '#01a38f', '#68cebb', [[{ gamut_clip = 'cusp' }]])

  -- Doesn't have effect on grays (as they have no defined hue)
  child.lua([[_G.cs.groups.Normal.fg = '#aaaaaa']])
  child.lua([[_G.cs.groups.Normal.bg = '#777777']])
  validate('return 180', '#aaaaaa', '#777777')
end

T['as_colorscheme() methods']['chan_modify()']['works with "a"'] = function()
  local validate = function(...) validate_chan_modify('a', ...) end

  validate('return x - 20', '#568178')

  -- Should respect `opts.gamut_clip`
  validate('return -20', '#00b49e', [[{ gamut_clip = 'cusp' }]])
end

T['as_colorscheme() methods']['chan_modify()']['works with "b"'] = function()
  local validate = function(...) validate_chan_modify('b', ...) end

  validate('return x - 10', '#ab48ae')

  -- Should respect `opts.gamut_clip`
  validate('return 40', '#dd8c00', [[{ gamut_clip = 'cusp' }]])
end

T['as_colorscheme() methods']['chan_modify()']['works with "red"'] = function()
  local validate = function(...) validate_chan_modify('red', ...) end

  validate('return x - 16', '#aa4a73')

  -- Should normalize to [0; 255]
  validate('return 300', '#ff4a73')
  validate('return -50', '#004a73')

  -- In theory, 'gamut_clip' is unnecessary as it always stays inside gamut
end

T['as_colorscheme() methods']['chan_modify()']['works with "green"'] = function()
  local validate = function(...) validate_chan_modify('green', ...) end

  validate('return x - 16', '#ba3a73')

  -- Should normalize to [0; 255]
  validate('return 300', '#baff73')
  validate('return -50', '#ba0073')

  -- In theory, 'gamut_clip' is unnecessary as it always stays inside gamut
end

T['as_colorscheme() methods']['chan_modify()']['works with "blue"'] = function()
  local validate = function(...) validate_chan_modify('blue', ...) end

  validate('return x - 16', '#ba4a63')

  -- Should normalize to [0; 255]
  validate('return 300', '#ba4aff')
  validate('return -50', '#ba4a00')

  -- In theory, 'gamut_clip' is unnecessary as it always stays inside gamut
end

T['as_colorscheme() methods']['chan_modify()']['validates arguments'] = function()
  child.lua([[_G.cs = MiniColors.as_colorscheme({ groups = { Normal = { fg = '#ffffff' } } })]])
  child.lua('_G.f = function(x) return x + 1 end')

  expect.error(function() child.lua('_G.cs:chan_modify(1, _G.f)') end, 'Channel.*one of')
  expect.error(function() child.lua([[_G.cs:chan_modify('aaa', _G.f)]]) end, 'Channel.*one of')

  expect.error(function() child.lua([[_G.cs:chan_modify('hue', 1)]]) end, '`f`.*callable')

  expect.error(function() child.lua([[_G.cs:chan_modify('hue', _G.f, { filter = 1 })]]) end, '`opts%.filter`.*callable')
  expect.error(
    function() child.lua([[_G.cs:chan_modify('hue', _G.f, { filter = 'a' })]]) end,
    '`opts%.filter`.*proper attribute'
  )

  expect.error(
    function() child.lua([[_G.cs:chan_modify('hue', _G.f, { gamut_clip = 'a' })]]) end,
    '`opts%.gamut_clip`.*one of'
  )
end

T['as_colorscheme() methods']['chan_modify()']['respects `opts.filter`'] = function()
  child.lua([[_G.cs = MiniColors.as_colorscheme({
    groups = { Normal = { fg = '#000000', bg = '#000000', sp = '#000000' } },
    terminal = { [0] = '#000000' },
  })]])
  child.lua([[_G.f = function(x) return x + 2 end]])

  -- Allowed attribute strings
  local validate_attr = function(attr)
    local lua_cmd = string.format([[_G.cs_modified = _G.cs:chan_modify('lightness', _G.f, { filter = '%s' })]], attr)
    child.lua(lua_cmd)

    local ref_normal = { fg = '#000000', bg = '#000000', sp = '#000000' }
    if attr ~= 'term' then ref_normal[attr] = '#020202' end
    eq(child.lua_get('_G.cs_modified.groups.Normal'), ref_normal)

    local ref_terminal = attr == 'term' and '#020202' or '#000000'
    eq(child.lua_get('_G.cs_modified.terminal[0]'), ref_terminal)
  end

  validate_attr('fg')
  validate_attr('bg')
  validate_attr('sp')
  validate_attr('term')

  -- Callable filter
  child.lua('_G.args_history = {}')
  child.lua([[_G.filter = function(...)
    table.insert(_G.args_history, { ... })
    return false
  end]])

  eq(child.lua_get([[vim.deep_equal(_G.cs, _G.cs:chan_modify('lightness', _G.f, { filter = _G.filter }))]]), true)
  -- Ensure consistent order in history as there is no order guarantee in how
  -- filter is applied
  child.lua('table.sort(_G.args_history, function(a, b) return a[2].attr < b[2].attr end)')
  eq(child.lua_get('_G.args_history'), {
    { '#000000', { attr = 'bg', name = 'Normal' } },
    { '#000000', { attr = 'fg', name = 'Normal' } },
    { '#000000', { attr = 'sp', name = 'Normal' } },
    { '#000000', { attr = 'term', name = 'terminal_color_0' } },
  })
end

T['as_colorscheme() methods']['chan_modify()']['respects `opts.gamut_clip`'] = function()
  child.lua([[_G.cs = MiniColors.as_colorscheme({
    -- This is approximately { l = 75, c = 5, h = 0 } in Oklch
    groups = { Normal = { fg = '#d5acb8' } }
  })]])
  child.lua([[_G.f = function(_) return 20 end]])

  eq(child.lua_get([[_G.cs:chan_modify('chroma', _G.f).groups.Normal.fg]]), '#ff88b7')
  eq(child.lua_get([[_G.cs:chan_modify('chroma', _G.f, { gamut_clip = 'chroma' }).groups.Normal.fg]]), '#ff88b7')
  eq(child.lua_get([[_G.cs:chan_modify('chroma', _G.f, { gamut_clip = 'cusp' }).groups.Normal.fg]]), '#ff7eb1')
  eq(child.lua_get([[_G.cs:chan_modify('chroma', _G.f, { gamut_clip = 'lightness' }).groups.Normal.fg]]), '#ff68a7')
end

-- Only basic testing here. More thorough tests are in `chan_modify()`.
T['as_colorscheme() methods']['chan_multiply()'] = new_set({ hooks = { pre_case = create_basic_cs } })

--stylua: ignore
T['as_colorscheme() methods']['chan_multiply()']['works'] = function()
  local validate = function(channel, coef, ref_normal_fg, opts_string)
    local args = string.format('%s, %s', coef, opts_string or '{}')
    validate_chan_method('chan_multiply', channel, args, ref_normal_fg)
  end

  validate('lightness',   0.5, '#6e0037')
  validate('chroma',      0.5, '#9c6475')
  validate('saturation',  1.5, '#d51071')
  validate('hue',         100, '#bf4b4e')
  validate('temperature', 2,   '#927300')
  validate('pressure',    0.5, '#927300')
  validate('a',           -1,  '#008b79')
  validate('b',           -1,  '#ba4a74')
  validate('red',         0.5, '#5d4a73')
  validate('green',       0.5, '#ba2573')
  validate('blue',        0.5, '#ba4a3a')

  -- Should respect `opts`
  validate('chroma', 20, '#f50081', [[{ gamut_clip = 'cusp' }]])

  -- With coefficient 1 should return copy of input
  validate_self_copy('chan_multiply', '1')
end

T['as_colorscheme() methods']['chan_multiply()']['validates arguments'] = function()
  expect.error(function() child.lua('_G.cs:chan_multiply(1, 10)') end, 'Channel.*one of')
  expect.error(function() child.lua([[_G.cs:chan_multiply('aaa', 10)]]) end, 'Channel.*one of')

  expect.error(function() child.lua([[_G.cs:chan_multiply('hue', 'a')]]) end, '`coef`.*number')
end

-- Only basic testing here. More thorough tests are in `chan_modify()`.
T['as_colorscheme() methods']['chan_repel()'] = new_set({ hooks = { pre_case = create_basic_cs } })

T['as_colorscheme() methods']['chan_repel()']['works with linear channels'] = function()
  -- Tested only with `lightness` as linear scale in hope that all others
  -- (except hue) are implemented the same
  local ref_lch = child.lua_get([[MiniColors.convert(_G.cs.groups.Normal.fg, 'oklch')]])
  local ref_l = ref_lch.l

  local validate = function(sources, coef, ref_normal_fg, opts_string)
    local args = string.format('%s, %s, %s', vim.inspect(sources), coef, opts_string or '{}')
    validate_chan_method('chan_repel', 'lightness', args, ref_normal_fg)
  end

  local ref_color = function(nudge, opts_string)
    --stylua: ignore
    local lua_get_cmd = string.format(
      [[MiniColors.convert({ l = %s, c = %s, h = %s }, 'hex', %s)]],
      ref_lch.l + nudge, ref_lch.c, ref_lch.h, opts_string or '{}'
    )
    return child.lua_get(lua_get_cmd)
  end

  -- Should be repelled away from source
  validate({ ref_l + 15 }, 10, ref_color(-2.23))
  validate({ ref_l - 15 }, 10, ref_color(2.23))

  -- If repelled number is inside [src - coef; src + coef], it should be
  -- repelled outside of it but close to nearest edge
  validate({ ref_l + 1 }, 10, ref_color(-9.05))
  validate({ ref_l - 1 }, 10, ref_color(9.05))

  -- If repelled from distant source, effect should be very small
  validate({ ref_l + 40 }, 10, ref_color(-0.183))
  validate({ ref_l - 40 }, 10, ref_color(0.183))

  -- Should attract with negative coefficient
  validate({ ref_l + 15 }, -10, ref_color(6.0653))
  validate({ ref_l - 15 }, -10, ref_color(-6.0653))

  -- If attracted number is inside [src - coef; src + coef], it should be
  -- attracted directly towards source
  validate({ ref_l - 9 }, -10, ref_color(-9))
  validate({ ref_l - 1 }, -10, ref_color(-1))
  validate({ ref_l + 1 }, -10, ref_color(1))
  validate({ ref_l + 9 }, -10, ref_color(9))

  -- Should allow multiple sources with additive nudges
  validate({ ref_l - 1, ref_l + 1 }, 10, ref_color(0))
  validate({ ref_l - 1, ref_l + 2 }, 10, ref_color(0.861))
  validate({ ref_l - 2, ref_l + 1 }, 10, ref_color(-0.861))

  validate({ ref_l - 1, ref_l + 1 }, -10, ref_color(0))
  validate({ ref_l - 1, ref_l + 2 }, -10, ref_color(1))
  validate({ ref_l - 2, ref_l + 1 }, -10, ref_color(-1))

  -- Should allow single number source
  validate(ref_l + 15, 10, ref_color(-2.23))

  -- Should respect `opts`
  local ref_cusp = ref_color(-39.0123, [[{ gamut_clip = 'cusp' }]])
  validate({ ref_l + 1 }, 40, ref_cusp, [[{ gamut_clip = 'cusp' }]])

  -- With no sources or coefficient 0 should return copy of input
  validate_self_copy('chan_repel', '{}, 1')
  validate_self_copy('chan_repel', '{ 0 }, 0')
end

T['as_colorscheme() methods']['chan_repel()']['works with "hue"'] = function()
  -- Use color more appropriate for this test
  local ref_hex = '#a95d69'
  child.lua('_G.cs.groups.Normal.fg = ' .. vim.inspect(ref_hex))
  local ref_lch = child.lua_get([[MiniColors.convert(_G.cs.groups.Normal.fg, 'oklch')]])
  -- Approximately 10.5
  local ref_h = ref_lch.h

  local validate = function(sources, coef, ref_normal_fg)
    local args = string.format('%s, %s', vim.inspect(sources), coef)
    validate_chan_method('chan_repel', 'hue', args, ref_normal_fg)
  end

  local ref_color = function(nudge)
    --stylua: ignore
    local lua_get_cmd = string.format(
      [[MiniColors.convert({ l = %s, c = %s, h = %s }, 'hex')]],
      -- Having `% 360` is crucial to test periodic nature
      ref_lch.l, ref_lch.c, (ref_lch.h + nudge) % 360
    )
    return child.lua_get(lua_get_cmd)
  end

  -- This mostly tests periodic nature of "hue" channel

  -- Should be repelled away from source
  validate({ ref_h + 5 }, 4, ref_color(-1.146))
  validate({ ref_h - 5 }, 4, ref_color(1.146))

  -- Should be attracted with negative coefficient
  validate({ ref_h + 5 }, -4, ref_color(3.115))
  validate({ ref_h - 5 }, -4, ref_color(-3.115))

  -- Should be repelled on circle
  validate({ ref_h + 5 }, 20, ref_color(-15.576))
  validate({ ref_h - 5 }, 20, ref_color(15.576))

  -- Should account for periodic nature. Here 355 is actually close (~15.5
  -- instead of ~344.5), so it should be repelled in positive direction
  validate({ 355 }, 20, ref_color(9.214))

  -- Points away from 180 degrees should be almost unaffected
  validate({ ref_h + 180 }, 20, ref_color(0))
end

T['as_colorscheme() methods']['chan_repel()']['properly repels when close to source'] = function()
  local create_cs = function(fg, bg)
    local lua_cmd =
      string.format([[_G.cs = MiniColors.as_colorscheme({ groups = { Normal = { fg = '%s', bg = '%s' } } })]], fg, bg)
    child.lua(lua_cmd)
  end

  local validate = function(channel, sources, coef, ref_normal_group)
    local lua_get_cmd =
      string.format([[_G.cs:chan_repel('%s', %s, %s).groups.Normal]], channel, vim.inspect(sources), coef)
    eq(child.lua_get(lua_get_cmd), ref_normal_group)
  end

  -- Lightness
  create_cs('#ffffff', '#000000')
  validate('lightness', { 0 }, 10, { fg = '#ffffff', bg = '#161616' })
  validate('lightness', { 100 }, 10, { fg = '#e2e2e2', bg = '#000000' })

  -- Chroma (grays will remain grays as they don't have hue to go along)
  create_cs('#ba4a73', '#eeeeee')
  validate('chroma', { 14.96798 }, 5, { fg = '#cc2d72', bg = '#eeeeee' })

  -- Saturation (grays sill remain the same)
  create_cs('#d70071', '#eeeeee')
  validate('saturation', { 0 }, 10, { fg = '#d70071', bg = '#eeeeee' })
  validate('saturation', { 100 }, 10, { fg = '#cf2772', bg = '#eeeeee' })

  -- Hue
  create_cs('#837655', '#6b7695')
  validate('hue', { 89.0081 }, 10, { fg = '#7e7856', bg = '#6b7695' })
  validate('hue', { 269.5389 }, 10, { fg = '#837655', bg = '#667895' })

  -- Temperature
  create_cs('#567e8d', '#bc5419')
  validate('temperature', { 43.3911 }, 10, { fg = '#547f8a', bg = '#bc5419' })
  validate('temperature', { 135.3044 }, 10, { fg = '#567e8d', bg = '#bf4f33' })

  -- Pressure
  create_cs('#567e8d', '#bc5419')
  validate('pressure', { 43.3911 }, 10, { fg = '#597d90', bg = '#bc5419' })
  validate('pressure', { 135.3044 }, 10, { fg = '#567e8d', bg = '#b55b00' })

  -- a
  create_cs('#018a79', '#a65d75')
  validate('a', { -10.2764 }, 2, { fg = '#348779', bg = '#a65d75' })
  validate('a', { 9.9023 }, 2, { fg = '#018a79', bg = '#9e6375' })

  -- b
  create_cs('#6073b2', '#8e7426')
  validate('b', { -10.0310 }, 2, { fg = '#6474a7', bg = '#8e7426' })
  validate('b', { 9.9888 }, 2, { fg = '#6073b2', bg = '#89753c' })

  -- Red
  create_cs('#ff0000', '#000000')
  validate('red', { 0 }, 16, { fg = '#ff0000', bg = '#100000' })
  validate('red', { 255 }, 16, { fg = '#ef0000', bg = '#000000' })

  -- Green
  create_cs('#00ff00', '#000000')
  validate('green', { 0 }, 16, { fg = '#00ff00', bg = '#001000' })
  validate('green', { 255 }, 16, { fg = '#00ef00', bg = '#000000' })

  -- Blue
  create_cs('#0000ff', '#000000')
  validate('blue', { 0 }, 16, { fg = '#0000ff', bg = '#000010' })
  validate('blue', { 255 }, 16, { fg = '#0000ef', bg = '#000000' })
end

T['as_colorscheme() methods']['chan_repel()']['validates arguments'] = function()
  expect.error(function() child.lua('_G.cs:chan_repel(1, 10, 1)') end, 'Channel.*one of')
  expect.error(function() child.lua([[_G.cs:chan_repel('aaa', 10, 1)]]) end, 'Channel.*one of')

  expect.error(function() child.lua([[_G.cs:chan_repel('hue', 'a', 1)]]) end, '`sources`.*array of numbers')
  expect.error(function() child.lua([[_G.cs:chan_repel('hue', { 'a' }, 1)]]) end, '`sources`.*array of numbers')

  expect.error(function() child.lua([[_G.cs:chan_repel('hue', 10, 'a')]]) end, '`coef`.*number')
end

-- Only basic testing here. More thorough tests are in `chan_modify()`.
T['as_colorscheme() methods']['chan_set()'] = new_set({ hooks = { pre_case = create_basic_cs } })

--stylua: ignore
T['as_colorscheme() methods']['chan_set()']['works with linear channels'] = function()
  -- Add second color to test multiple `values`
  -- Oklch ~ { l = 70, c = 5, h = 100 }
  -- Oklab ~ { l = 70, a = -1, b = 5 }
  -- Saturation ~ 32
  -- Temperature = 170
  -- Pressure = 80
  -- RGB = { r = 178 g = 173, b = 137 }
  child.lua([[_G.cs.groups.Normal.bg = '#b2ad89']])

  local validate = function(channel, values, ref_normal, opts_string)
    local lua_get_cmd =
      string.format([[_G.cs:chan_set('%s', %s, %s).groups.Normal]], channel, vim.inspect(values), opts_string or '{}')
    eq(child.lua_get(lua_get_cmd), ref_normal)
  end

  validate('lightness',   { 60 },  { fg = '#d8658d', bg = '#97926f' })
  validate('chroma',      { 10 },  { fg = '#a65d74', bg = '#b9ae60' })
  validate('saturation',  { 50 },  { fg = '#ad5774', bg = '#b6ad74' })
  validate('hue',         { 45 },  { fg = '#bc541a', bg = '#c7a292' })
  validate('temperature', { 45 },  { fg = '#9757b3', bg = '#8ab3c3' })
  validate('pressure',    { 45 },  { fg = '#4d891f', bg = '#9eb394' })
  validate('a',           { 0 },   { fg = '#777777', bg = '#b7ab89' })
  validate('b',           { 0 },   { fg = '#ba4a73', bg = '#a6aeac' })
  validate('red',         { 128 }, { fg = '#804a73', bg = '#80ad89' })
  validate('green',       { 128 }, { fg = '#ba8073', bg = '#b28089' })
  validate('blue',        { 128 }, { fg = '#ba4a80', bg = '#b2ad80' })

  -- Should allow multiple values while setting to closest one
  validate('lightness',   { 60,  65 },  { fg = '#d8658d', bg = '#a49f7c' })
  validate('chroma',      { 7,   10 },  { fg = '#a65d74', bg = '#b5ad7a' })
  validate('saturation',  { 50,  40 },  { fg = '#ad5774', bg = '#b4ad80' })
  -- - "Hue" should use circlar distance
  validate('hue',         { 45,  355 }, { fg = '#b84b7b', bg = '#c7a292' })
  validate('temperature', { 45,  150 }, { fg = '#9757b3', bg = '#a7b18e' })
  validate('pressure',    { 45,  150 }, { fg = '#bf4d3e', bg = '#9eb394' })
  validate('a',           { 0,   10 },  { fg = '#a65d74', bg = '#b7ab89' })
  validate('b',           { 0,   4 },   { fg = '#ba4a73', bg = '#b0ad90' })
  validate('red',         { 128, 237 }, { fg = '#ed4a73', bg = '#80ad89' })
  validate('green',       { 128, 192 }, { fg = '#ba8073', bg = '#b2c089' })
  validate('blue',        { 128, 140 }, { fg = '#ba4a80', bg = '#b2ad8c' })

  -- Should allow single number as `values`
  validate('lightness', 60, { fg = '#d8658d', bg = '#97926f' })

  -- Should respect `opts`
  validate('lightness', { 10 }, { fg = '#560029', bg = '#221d00' }, [[{ gamut_clip = 'cusp' }]])
end

T['as_colorscheme() methods']['chan_set()']['validates arguments'] = function()
  expect.error(function() child.lua('_G.cs:chan_set(1, 10)') end, 'Channel.*one of')
  expect.error(function() child.lua([[_G.cs:chan_set('aaa', 10)]]) end, 'Channel.*one of')

  expect.error(function() child.lua([[_G.cs:chan_set('hue', 'a')]]) end, '`values`.*array of numbers')
  expect.error(function() child.lua([[_G.cs:chan_set('hue', { 'a' })]]) end, '`values`.*array of numbers')
  expect.error(function() child.lua([[_G.cs:chan_set('hue', {})]]) end, '`values`.*should not be empty')
end

T['as_colorscheme() methods']['color_modify()'] = function()
  child.lua([[_G.cs = MiniColors.as_colorscheme({
    groups = {
      Normal = { fg = '#ffffff', bg = '#ffffff' },
      TestNotAllAttrs = { sp = '#ffffff' },
    },
    terminal = { [0] = '#ffffff' }
  })]])
  child.lua('_G.args_history = {}')
  child.lua([[_G.f = function(...)
    table.insert(_G.args_history, { ... })
    return '#000000'
  end]])

  child.lua('_G.cs_modified = _G.cs:color_modify(_G.f)')
  eq(child.lua_get('_G.cs_modified.groups.Normal'), { fg = '#000000', bg = '#000000' })
  eq(child.lua_get('_G.cs_modified.groups.TestNotAllAttrs'), { sp = '#000000' })
  eq(child.lua_get('_G.cs_modified.terminal[0]'), '#000000')

  child.lua('table.sort(_G.args_history, function(a, b) return a[2].attr < b[2].attr end)')
  eq(child.lua_get('_G.args_history'), {
    { '#ffffff', { attr = 'bg', name = 'Normal' } },
    { '#ffffff', { attr = 'fg', name = 'Normal' } },
    { '#ffffff', { attr = 'sp', name = 'TestNotAllAttrs' } },
    { '#ffffff', { attr = 'term', name = 'terminal_color_0' } },
  })
end

T['as_colorscheme() methods']['compress()'] = new_set()

T['as_colorscheme() methods']['compress()']['works'] = function()
  -- Compressing should be like removing all highlight groups similar to ones
  -- that come after `:hi clear`
  child.cmd('hi clear')
  child.lua('_G.cs = MiniColors.get_colorscheme()')
  eq(child.lua_get('vim.tbl_count(_G.cs.groups) == 0'), false)
  eq(child.lua_get('vim.tbl_count(_G.cs:compress().groups) == 0'), true)

  child.lua([[_G.cs = MiniColors.as_colorscheme({
    groups = {
      -- This link is the same as after `:hi clear` so should be removed
      SpecialChar = { link = 'Special' },

      -- Should preserve manually created highlight groups
      Test = { fg = '#ffffff' },

      -- By default should exclude groups from some pre-defined plugins
      DevIconMine = { fg = '#ffffff' },
      colorizer_mine = { fg = '#ffffff' },
    },
    -- Terminal colors should be untouched
    terminal = { [1] = '#ff0000' }
  })]])
  child.lua('_G.cs_compressed = _G.cs:compress()')

  eq(child.lua_get('_G.cs_compressed.groups'), { Test = { fg = '#ffffff' } })
  eq(child.lua_get('_G.cs_compressed.terminal'), { [1] = '#ff0000' })

  -- Should return full copy of group data
  child.lua([[_G.cs.groups.Test.bg = '#000000']])
  child.lua([[_G.cs.terminal[1] = '#000000']])

  eq(child.lua_get('_G.cs_compressed.groups.Test.bg'), vim.NIL)
  eq(child.lua_get('_G.cs_compressed.terminal[1]'), '#ff0000')
end

T['as_colorscheme() methods']['compress()']['respects `opts.plugins`'] = function()
  child.lua([[_G.cs = MiniColors.as_colorscheme({
    groups = {
      DevIconMine = { fg = '#ffffff' },
      colorizer_mine = { fg = '#ffffff' },
    }
  })]])

  eq(child.lua_get('_G.cs:compress({ plugins = false }).groups'), {
    DevIconMine = { fg = '#ffffff' },
    colorizer_mine = { fg = '#ffffff' },
  })
end

T['as_colorscheme() methods']['compress()']['does not have side effects'] = function()
  -- As checking equivalence to result of `:hi clear` needs to execute it,
  -- there should be proper cache and restore of current color scheme
  child.cmd('hi TestRestore guifg=#ffffff')
  child.lua([[_G.cs = MiniColors.as_colorscheme({
    groups = { Test = { bg = '#000000' } }
  })]])

  child.lua('_G.cs:compress()')
  expect.match(child.cmd_capture('hi TestRestore'), 'guifg=#ffffff$')
end

T['as_colorscheme() methods']['get_palette()'] = new_set()

T['as_colorscheme() methods']['get_palette()']['works'] = function()
  child.lua([[_G.cs = MiniColors.as_colorscheme({
    groups = {
      Normal = { fg = '#ffffff', bg = '#000000' },
      Test = { fg = '#fcb48c', bg = '#ffadac', sp = '#e9c07a' },
    },
    terminal = { [0] = '#222222', [1] = '#777777', [15] = '#d4d4d4' },
  })]])

  -- Should return colors in increasing order of lightness
  eq(
    child.lua_get('_G.cs:get_palette()'),
    { '#000000', '#222222', '#777777', '#ffadac', '#fcb48c', '#e9c07a', '#d4d4d4', '#ffffff' }
  )

  -- By default returns only colors above small threshold
  child.lua([[
    local cs_groups = {}
    for i = 0, 100 do
      cs_groups['Test' .. i] = { fg = '#012345' }
    end
    cs_groups.TestRare = { fg = '#543210' }
    _G.cs = MiniColors.as_colorscheme({ groups = cs_groups })
  ]])
  eq(child.lua_get('_G.cs:get_palette()'), { '#012345' })
end

T['as_colorscheme() methods']['get_palette()']['respects `opts.threshold`'] = function()
  child.lua([[_G.cs = MiniColors.as_colorscheme({
    groups = { Test = { fg = '#012345', bg = '#012345', sp = '#543210' } }
  })]])
  eq(child.lua_get('_G.cs:get_palette({ threshold = 0.5 })'), { '#012345' })
end

T['as_colorscheme() methods']['resolve_links()'] = function()
  child.lua([[_G.cs = MiniColors.as_colorscheme({
    groups = {
      Normal = { link = 'Test1' },
      Test1 = { link = 'Test2' },
      Test2 = { fg = '#ffffff' },
      TestImpossible = { link = 'TestMissing' },
    }
  })]])
  child.lua('_G.cs_resolved = _G.cs:resolve_links()')

  eq(child.lua_get('_G.cs_resolved.groups'), {
    -- Should resolve all nested links
    Normal = { fg = '#ffffff' },
    Test1 = { fg = '#ffffff' },
    Test2 = { fg = '#ffffff' },
    -- Can't resolve link to a group not defined within color scheme
    TestImpossible = { link = 'TestMissing' },
  })

  -- Should return copy without modifying original
  eq(child.lua_get('_G.cs.groups.Test1.fg'), vim.NIL)

  -- Resolved data should be independent of original link
  child.lua([[_G.cs_resolved.groups.Test2.fg = '#000000']])
  eq(child.lua_get('_G.cs_resolved.groups.Test1.fg'), '#ffffff')
end

T['as_colorscheme() methods']['simulate_cvd()'] = function()
  -- Test only basics. More thorough ones are in `MiniColors.simulate_cvd()`.
  child.lua([[_G.cs = MiniColors.as_colorscheme({
    groups = { Normal = { fg = '#00ff00', bg = '#00ff00', sp = '#00ff00' } },
    terminal = { [1] = '#ff0000' },
  })]])

  child.lua([[_G.cs_cvd = _G.cs:simulate_cvd('protan', 1)]])
  eq(child.lua_get('_G.cs_cvd.groups'), { Normal = { fg = '#ffc900', bg = '#ffc900', sp = '#ffc900' } })
  eq(child.lua_get('_G.cs_cvd.terminal[1]'), '#271d00')
end

T['as_colorscheme() methods']['write()'] = new_set({
  hooks = {
    pre_case = function()
      local lua_cmd = string.format([[vim.fn.stdpath = function() return %s end]], vim.inspect(dir_path))
      child.lua(lua_cmd)

      -- Add to `rtp` to be able to discrove color schemes
      child.cmd('set rtp+=' .. dir_path)
    end,
    post_case = function() vim.fn.delete(colors_path, 'rf') end,
  },
})

local make_validate_file_lines = function(path)
  local lines = vim.fn.readfile(path)
  local lines_string = table.concat(lines, '\n')
  return function(pat) expect.match(lines_string, pat) end, function(pat) expect.no_match(lines_string, pat) end
end

T['as_colorscheme() methods']['write()']['works'] = function()
  child.lua([[_G.cs = MiniColors.as_colorscheme({
    name = 'my_cs',
    groups = {
      Normal = { fg = '#ffffff', bg = '#000000' },
      -- This should be dropped during compression
      SpecialChar = { link = 'Special' },
    },
    terminal = { [1] = '#ff0000' },
  })]])

  -- Calling `write()` should result into discroverable color scheme
  child.lua('_G.cs:write()')

  -- Validate
  child.cmd('colorscheme my_cs')

  eq(child.g.colors_name, 'my_cs')
  expect.match(child.cmd_capture('hi Normal'), 'guifg=#ffffff')
  eq(child.g.terminal_color_1, '#ff0000')

  -- Make basic checks for file content
  local validate_match, validate_no_match = make_validate_file_lines(colors_path .. '/my_cs.lua')

  -- - Description comments
  validate_match([[^%-%- Made with 'mini%.colors']])
  validate_match([[%-%- Highlight groups]])
  validate_match([[%-%- Terminal colors]])

  -- - Basic code
  validate_match([[vim.cmd%('highlight clear'%)]])
  validate_match([[vim%.g%.colors_name = "my_cs"]])
  validate_match([["Normal", { bg = "#000000", fg = "#ffffff" }]])
  validate_match([[g.terminal_color_1 = "#ff0000"]])

  -- - Should compress by default and not include redundant groups
  validate_no_match('SpecialChar')
end

T['as_colorscheme() methods']['write()']['makes unique color scheme name'] = function()
  mock_cs()

  child.lua([[_G.cs = MiniColors.as_colorscheme({
    -- This color scheme should already be present
    name = 'mock_cs',
    groups = { Normal = { fg = '#ffffff', bg = '#000000' } },
    terminal = { [1] = '#ff0000' },
  })]])
  child.lua('_G.cs:write()')

  local files = child.fn.readdir(colors_path)
  eq(#files, 1)
  -- File name should add timestamp suffix in case of duplicated name, but
  -- doesn't work on Windows
  helpers.skip_on_windows('`vim.fn.strftime()` does not work on Windows')
  expect.match(files[1], 'mock_cs_%d%d%d%d%d%d%d%d_%d%d%d%d%d%d%.lua')
end

T['as_colorscheme() methods']['write()']['handles empty fields'] = function()
  child.lua('_G.cs = MiniColors.as_colorscheme({})')
  child.lua('_G.cs:write()')

  -- File name should be inferred as 'mini_colors'
  local validate_match = make_validate_file_lines(colors_path .. 'mini_colors.lua')

  validate_match('g%.colors_name = nil')
  validate_match('%-%- No highlight groups defined')
  validate_match('%-%- No terminal colors defined')
end

T['as_colorscheme() methods']['write()']['handles metatables'] = function()
  child.lua([[
    local mt = { __tostring = function(x) return vim.inspect(x) end }
    _G.cs = MiniColors.as_colorscheme({
      name = 'my_cs',
      groups = {
        Normal = setmetatable({ fg = '#ffffff', bg = '#000000' }, mt),
        -- This should be dropped during compression
        SpecialChar = vim.empty_dict(),
      },
      terminal = setmetatable({ [1] = '#ff0000' }, mt),
    })]])

  child.lua('_G.cs:write()')
  local _, validate_no_match = make_validate_file_lines(colors_path .. '/my_cs.lua')
  validate_no_match('metatable')
  validate_no_match('vim%.empty_dict%(%)')
end

T['as_colorscheme() methods']['write()']['respects `opts.compress`'] = function()
  child.lua([[_G.cs = MiniColors.as_colorscheme({
    name = 'my_cs',
    groups = {
      -- This should be dropped during compression
      SpecialChar = { link = 'Special' },
      Normal = { fg = '#ffffff' },
    }
  })]])
  child.lua('_G.cs:write({ compress = false })')

  local validate_match = make_validate_file_lines(colors_path .. 'my_cs.lua')
  -- It should be present as no compression should have been done
  validate_match('SpecialChar')
end

T['as_colorscheme() methods']['write()']['respects `opts.name`'] = function()
  child.lua([[_G.cs = MiniColors.as_colorscheme({
    name = 'blue',
    groups = { Normal = { fg = '#ffffff' } }
  })]])
  child.lua([[_G.cs:write({ name = 'my_cs_from_name' })]])

  eq(child.fn.filereadable(colors_path .. 'my_cs_from_name.lua'), 1)
end

T['as_colorscheme() methods']['write()']['respects `opts.directory`'] = function()
  local inner_dir = dir_path .. 'inner_dir/'
  MiniTest.finally(function() vim.fn.delete(inner_dir, 'rf') end)

  child.lua([[_G.cs = MiniColors.as_colorscheme({
    name = 'my_cs',
    groups = { Normal = { fg = '#ffffff' } }
  })]])

  local write_cmd = '_G.cs:write({ directory = ' .. vim.inspect(inner_dir) .. ' })'
  child.lua(write_cmd)

  eq(child.fn.filereadable(inner_dir .. 'my_cs.lua'), 1)
end

T['get_colorscheme()'] = new_set()

local validate_mock_cs = function(cs_var)
  -- Fields
  local validate_field = function(field, value) eq(child.lua_get(cs_var .. '.' .. field), value) end

  validate_field('groups.Normal', { fg = '#5f87af', bg = '#080808' })
  validate_field('groups.TestNormalCterm', { ctermfg = 67, ctermbg = 232 })
  validate_field('groups.TestComment', { fg = '#5f87af', bg = '#080808' })
  validate_field('groups.TestSpecial', { sp = '#00ff00', underline = true })
  validate_field('groups.TestBlend', { bg = '#121212', blend = 0 })

  validate_field('name', 'mock_cs')

  validate_field('terminal[0]', '#010101')
  validate_field('terminal[7]', '#fefefe')

  -- Methods
  local validate_method = function(method)
    local lua_cmd = string.format('type(%s.%s)', cs_var, method)
    eq(child.lua_get(lua_cmd), 'function')
  end

  validate_method('apply')
  validate_method('add_cterm_attributes')
  validate_method('add_terminal_colors')
  validate_method('add_transparency')
  validate_method('chan_add')
  validate_method('chan_invert')
  validate_method('chan_modify')
  validate_method('chan_multiply')
  validate_method('chan_repel')
  validate_method('chan_set')
  validate_method('color_modify')
  validate_method('compress')
  validate_method('get_palette')
  validate_method('resolve_links')
  validate_method('simulate_cvd')
  validate_method('write')
end

T['get_colorscheme()']['works for current color scheme'] = function()
  mock_cs()
  child.cmd('colorscheme mock_cs')

  child.lua('_G.cs = MiniColors.get_colorscheme()')
  validate_mock_cs('_G.cs')
end

T['get_colorscheme()']['works for some color scheme'] = function()
  mock_cs()
  child.lua([[_G.cs = MiniColors.get_colorscheme('mock_cs')]])
  validate_mock_cs('_G.cs')
end

T['get_colorscheme()']['works when color is defined by name'] = function()
  child.cmd('hi Normal guifg=Red guibg=Black')
  child.g.terminal_color_1 = 'Red'

  child.lua('_G.cs = MiniColors.get_colorscheme()')
  eq(child.lua_get('_G.cs.groups.Normal'), { fg = '#ff0000', bg = '#000000' })
  eq(child.lua_get('_G.cs.terminal[1]'), '#ff0000')
end

T['get_colorscheme()']['works with cleared groups'] = function()
  child.cmd('hi clear MsgArea')
  child.cmd('hi clear AAA')

  local validate_hl = function(name, ref)
    eq(child.lua_get('_G.cs.groups.' .. name), ref)
    -- Should not include metatable (from being equal to `vim.empty_dict()`),
    -- as this results in incorrect lines after `write()`
    eq(child.lua_get('getmetatable(_G.cs.groups.' .. name .. ')'), vim.NIL)
  end

  -- Cleared groups should still be present
  child.lua('_G.cs = MiniColors.get_colorscheme()')
  validate_hl('MsgArea', {})
  validate_hl('AAA', {})

  -- Should work after `add_transparency()` (still no metatable)
  child.lua('_G.cs = _G.cs:add_transparency()')
  validate_hl('MsgArea', { blend = 0 })
  validate_hl('AAA', {})
end

T['get_colorscheme()']['validates arguments'] = function()
  expect.error(function() child.lua_get('MiniColors.get_colorscheme(111)') end, '`name`.*string')
  expect.error(function() child.lua_get([[MiniColors.get_colorscheme('aaa')]]) end, 'No color scheme')
end

T['get_colorscheme()']['has no side effects'] = function()
  -- Update current color scheme
  child.g.color_name = 'aaa'
  child.cmd('hi AAA guifg=#aaaaaa')

  mock_cs()
  child.lua([[_G.cs = MiniColors.get_colorscheme('mock_cs')]])

  eq(child.g.color_name, 'aaa')
  expect.match(child.cmd_capture('hi AAA'), 'AAA.*guifg=#aaaaaa')
end

T['get_colorscheme()']['respects `opts.new_name`'] = function()
  -- Current color scheme
  child.g.colors_name = 'aaa'
  eq(child.lua_get([[MiniColors.get_colorscheme(nil, { new_name = 'bbb' }).name]]), 'bbb')

  -- Some other color scheme
  mock_cs()
  eq(child.lua_get([[MiniColors.get_colorscheme('mock_cs', { new_name = 'ccc' }).name]]), 'ccc')
end

T['animate()'] = new_set({
  hooks = {
    pre_case = function()
      -- Create two color scheme objects
      child.lua([[_G.cs_1 = MiniColors.as_colorscheme({
        name = 'cs_1',
        groups = {
          Normal      = { fg = '#190000', bg = '#001900' },
          TestSpecial = { sp = '#000019', blend = 0 },
          TestLink    = { link = 'Title' },
          TestSingle  = { fg = '#ffffff', bg = '#000000', sp = '#aaaaaa', underline = true },

          TestBold          = { fg = '#000000', bold          = true },
          TestItalic        = { fg = '#000000', italic        = true },
          TestNocombine     = { fg = '#000000', nocombine     = true },
          TestReverse       = { fg = '#000000', reverse       = true },
          TestStandout      = { fg = '#000000', standout      = true },
          TestStrikethrough = { fg = '#000000', strikethrough = true },
          TestUndercurl     = { fg = '#000000', undercurl     = true },
          TestUnderdashed   = { fg = '#000000', underdashed   = true },
          TestUnderdotted   = { fg = '#000000', underdotted   = true },
          TestUnderdouble   = { fg = '#000000', underdouble   = true },
          TestUnderline     = { fg = '#000000', underline     = true },
        },
        terminal = { [0] = '#190000', [7] = '#001900' }
      })]])

      child.lua([[_G.cs_2 = MiniColors.as_colorscheme({
        name = 'cs_2',
        groups = {
          Normal      = { fg = '#000000', bg = '#000000' },
          TestSpecial = { sp = '#000000', blend = 25 },
          TestLink    = { link = 'Comment' },
          TestSingle  = {},

          TestBold          = { fg = '#000000', bold          = nil },
          TestItalic        = { fg = '#000000', italic        = nil },
          TestNocombine     = { fg = '#000000', nocombine     = nil },
          TestReverse       = { fg = '#000000', reverse       = nil },
          TestStandout      = { fg = '#000000', standout      = nil },
          TestStrikethrough = { fg = '#000000', strikethrough = nil },
          TestUndercurl     = { fg = '#000000', undercurl     = nil },
          TestUnderdashed   = { fg = '#000000', underdashed   = nil },
          TestUnderdotted   = { fg = '#000000', underdotted   = nil },
          TestUnderdouble   = { fg = '#000000', underdouble   = nil },
          TestUnderline     = { fg = '#000000', underline     = nil },
        },
        terminal = { [7] = '#000000', [15] = '#000000' }
      })]])

      -- Create function to get relevant data
      child.lua([[_G.get_relevant_cs_data = function(cs)
        cs = cs or MiniColors.get_colorscheme()

        return {
          name = cs.name,
          groups = {
            Normal            = cs.groups.Normal,
            TestSpecial       = cs.groups.TestSpecial,
            TestLink          = cs.groups.TestLink,
            TestSingle        = cs.groups.TestSingle,
            TestBold          = cs.groups.TestBold,
            TestItalic        = cs.groups.TestItalic,
            TestNocombine     = cs.groups.TestNocombine,
            TestReverse       = cs.groups.TestReverse,
            TestStandout      = cs.groups.TestStandout,
            TestStrikethrough = cs.groups.TestStrikethrough,
            TestUndercurl     = cs.groups.TestUndercurl,
            TestUnderdashed   = cs.groups.TestUnderdashed,
            TestUnderdotted   = cs.groups.TestUnderdotted,
            TestUnderdouble   = cs.groups.TestUnderdouble,
            TestUnderline     = cs.groups.TestUnderline,
          },
          terminal = {
            { 0, vim.g.terminal_color_0},
            { 7, vim.g.terminal_color_7},
            { 15, vim.g.terminal_color_15},
          }
        }
      end]])
    end,
  },
  n_retry = helpers.get_n_retry(4),
})

local validate_cs_1 = function()
  local cur_cs_data = child.lua_get('_G.get_relevant_cs_data()')
  local cs_1_data = child.lua_get('_G.get_relevant_cs_data(_G.cs_1)')
  eq(cur_cs_data, cs_1_data)
end

local validate_cs_2 = function()
  local cur_cs_data = child.lua_get('_G.get_relevant_cs_data()')
  local cs_2_data = child.lua_get('_G.get_relevant_cs_data(_G.cs_2)')
  eq(cur_cs_data, cs_2_data)
end

--stylua: ignore
T['animate()']['works'] = function()
  local validate_intermediate = function()
    eq(
      child.lua_get('_G.get_relevant_cs_data()'),
      {
        name = 'transition_step',
        groups = {
          Normal      = { fg = '#0c0100', bg = '#040f00' },
          TestSpecial = { sp = '#00010b', blend = 8 },
          TestLink    = { link = 'Title' },
          TestSingle  = { bg = '#000000', fg = '#ffffff', sp = '#aaaaaa', underline = true },

          TestBold          = { fg = '#000000', bold          = true },
          TestItalic        = { fg = '#000000', italic        = true },
          TestNocombine     = { fg = '#000000', nocombine     = true },
          TestReverse       = { fg = '#000000', reverse       = true },
          TestStandout      = { fg = '#000000', standout      = true },
          TestStrikethrough = { fg = '#000000', strikethrough = true },
          TestUndercurl     = { fg = '#000000', undercurl     = true },
          TestUnderdashed   = { fg = '#000000', underdashed   = true },
          TestUnderdotted   = { fg = '#000000', underdotted   = true },
          TestUnderdouble   = { fg = '#000000', underdouble   = true },
          TestUnderline     = { fg = '#000000', underline     = true },
        },
        terminal = { { 0, '#190000' }, { 7, '#040f00' }, { 15 } }
      }
    )
  end

  -- Start with first color scheme
  child.lua('_G.cs_1:apply()')
  validate_cs_1()

  -- It should animate transition from current color scheme to first in array,
  -- then to second, and so on
  local test_transition_duration, test_show_duration = 15 * small_time, 10 * small_time
  child.lua('_G.test_transition_duration = ' .. test_transition_duration)
  child.lua('_G.test_show_duration = ' .. test_show_duration)
  child.lua([[
    MiniColors.animate(
      { _G.cs_2, _G.cs_1 },
      {
        -- Test with manual options for more robust testing. Sadly, no default
        -- option values are tested as times can be too fast for running in CI.
        -- There are indirect tests in `:Colorscheme`, though.
        transition_steps = 3,
        transition_duration = _G.test_transition_duration,
        show_duration = _G.test_show_duration,
      }
    )
  ]])

  -- Should actually perform transform
  sleep(0.5 * test_transition_duration)
  validate_intermediate()

  sleep(0.5 * test_transition_duration + small_time)
  validate_cs_2()

  -- After first transition end it should show color scheme 2 for specified
  -- "show" duration
  sleep(test_show_duration - 2 * small_time)
  validate_cs_2()

  -- After showing period it should start transition back to first one (as it
  -- was specially designed command)
  sleep(0.5 * test_transition_duration + 3 * small_time)
  validate_intermediate()

  sleep(0.5 * test_transition_duration)
  validate_cs_1()
end

T['animate()']['validates arguments'] = function()
  expect.error(function() child.lua('MiniColors.animate(_G.cs_2)') end, 'array of color schemes')
end

T['convert()'] = new_set()

local convert = function(...) return child.lua_get('MiniColors.convert(...)', { ... }) end

T['convert()']['converts to 8-bit'] = function()
  local validate = function(x, ref) eq(convert(x, '8-bit'), ref) end

  local bit_ref = 67
  validate(bit_ref, bit_ref)
  validate('#5f87af', bit_ref)
  validate({ r = 95, g = 135, b = 175 }, bit_ref)
  validate({ l = 54.729, a = -2.692, b = -7.072 }, bit_ref)
  validate({ l = 54.729, c = 7.567, h = 249.16 }, bit_ref)
  validate({ l = 54.729, s = 44.01, h = 249.16 }, bit_ref)

  -- Handles grays
  local gray_ref = 240
  validate({ r = 88, g = 88, b = 88 }, gray_ref)
  validate({ l = 37.6, a = 0, b = 0 }, gray_ref)
  validate({ l = 37.6, c = 0 }, gray_ref)
  validate({ l = 37.6, c = 0, h = 180 }, gray_ref)
  validate({ l = 37.6, s = 0 }, gray_ref)
  validate({ l = 37.6, s = 0, h = 180 }, gray_ref)
end

T['convert()']['converts to HEX'] = function()
  local validate = function(x, ref) eq(convert(x, 'hex'), ref) end

  local hex_ref = '#5f87af'
  validate(67, hex_ref)
  validate(hex_ref, hex_ref)
  validate({ r = 95, g = 135, b = 175 }, hex_ref)
  validate({ l = 54.729, a = -2.692, b = -7.072 }, hex_ref)
  validate({ l = 54.729, c = 7.567, h = 249.16 }, hex_ref)
  validate({ l = 54.729, s = 44.01, h = 249.16 }, hex_ref)

  -- Handles grays
  local gray_ref = '#111111'
  validate({ r = 17, g = 17, b = 17 }, gray_ref)
  validate({ l = 8, a = 0, b = 0 }, gray_ref)
  validate({ l = 8, c = 0 }, gray_ref)
  validate({ l = 8, c = 0, h = 180 }, gray_ref)
  validate({ l = 8, s = 0 }, gray_ref)
  validate({ l = 8, s = 0, h = 180 }, gray_ref)

  -- Performs correct gamut clipping
  -- NOTE: this uses approximate linear model and not entirely correct
  -- Clipping should be correct below and above cusp lightness.
  -- Cusp for hue=0 is at c=26.23 and l=59.05
  eq(convert({ l = 15, c = 13, h = 0 }, 'hex'), convert({ l = 15, c = 10.266, h = 0 }, 'hex'))
  eq(convert({ l = 85, c = 13, h = 0 }, 'hex'), convert({ l = 85, c = 9.5856, h = 0 }, 'hex'))

  -- Clipping with 'chroma' method should clip chroma channel
  eq(
    convert({ l = 15, c = 13, h = 0 }, 'hex', { gamut_clip = 'chroma' }),
    convert({ l = 15, c = 10.266, h = 0 }, 'hex')
  )
  eq(
    convert({ l = 85, c = 13, h = 0 }, 'hex', { gamut_clip = 'chroma' }),
    convert({ l = 85, c = 9.5856, h = 0 }, 'hex')
  )

  -- Clipping with 'lightness' method should clip lightness channel
  eq(
    convert({ l = 15, c = 13, h = 0 }, 'hex', { gamut_clip = 'lightness' }),
    convert({ l = 22.07, c = 13, h = 0 }, 'hex')
  )
  eq(
    convert({ l = 85, c = 13, h = 0 }, 'hex', { gamut_clip = 'lightness' }),
    convert({ l = 79.66, c = 13, h = 0 }, 'hex')
  )

  -- Clipping with 'cusp' method should draw line towards c=c_cusp, l=0 in
  -- (c, l) coordinates (with **not corrected** `l`)
  eq(
    convert({ l = 15, c = 13, h = 0 }, 'hex', { gamut_clip = 'cusp' }),
    convert({ l = 18.84, c = 11.77, h = 0 }, 'hex')
  )
  eq(convert({ l = 85, c = 13, h = 0 }, 'hex', { gamut_clip = 'cusp' }), convert({ l = 82, c = 11.5, h = 0 }, 'hex'))
end

T['convert()']['converts to RGB'] = function()
  local validate = function(x, ref, tol) eq_approx(convert(x, 'rgb'), ref, tol or 0) end

  local rgb_ref = { r = 95, g = 135, b = 175 }
  validate(67, rgb_ref)
  validate('#5f87af', rgb_ref)
  validate(rgb_ref, rgb_ref)
  validate({ l = 54.729, a = -2.692, b = -7.072 }, rgb_ref, 0.01)
  validate({ l = 54.729, c = 7.567, h = 249.16 }, rgb_ref, 0.01)
  validate({ l = 54.729, s = 44.01, h = 249.16 }, rgb_ref, 0.01)

  -- Handles grays
  local gray_ref = { r = 17, g = 17, b = 17 }
  validate({ l = 8, a = 0, b = 0 }, gray_ref, 0.02)
  validate({ l = 8, c = 0 }, gray_ref, 0.02)
  validate({ l = 8, c = 0, h = 180 }, gray_ref, 0.02)
  validate({ l = 8, s = 0 }, gray_ref, 0.02)
  validate({ l = 8, s = 0, h = 180 }, gray_ref, 0.02)

  -- Normalization
  validate({ r = 300, g = -10, b = 127 }, { r = 255, g = 0, b = 127 })

  -- Performs correct gamut clipping
  -- NOTE: this uses approximate linear model and not entirely correct
  -- Clipping should be correct below and above cusp lightness.
  -- Cusp for hue=0 is at c=26.23 and l=59.05
  eq_approx(convert({ l = 15, c = 13, h = 0 }, 'rgb'), convert({ l = 15, c = 10.266, h = 0 }, 'rgb'), 1e-4)
  eq_approx(convert({ l = 85, c = 13, h = 0 }, 'rgb'), convert({ l = 85, c = 9.5856, h = 0 }, 'rgb'), 1e-4)

  -- Clipping with 'chroma' method should clip chroma channel
  eq_approx(
    convert({ l = 15, c = 13, h = 0 }, 'rgb', { gamut_clip = 'chroma' }),
    convert({ l = 15, c = 10.266, h = 0 }, 'rgb'),
    0.02
  )
  eq_approx(
    convert({ l = 85, c = 13, h = 0 }, 'rgb', { gamut_clip = 'chroma' }),
    convert({ l = 85, c = 9.5856, h = 0 }, 'rgb'),
    0.02
  )

  -- Clipping with 'lightness' method should clip lightness channel
  eq_approx(
    convert({ l = 15, c = 13, h = 0 }, 'rgb', { gamut_clip = 'lightness' }),
    convert({ l = 22.07, c = 13, h = 0 }, 'rgb'),
    0.02
  )
  eq_approx(
    convert({ l = 85, c = 13, h = 0 }, 'rgb', { gamut_clip = 'lightness' }),
    convert({ l = 79.66, c = 13, h = 0 }, 'rgb'),
    0.02
  )

  -- Clipping with 'cusp' method should draw line towards c=c_cusp, l=0 in
  -- (c, l) coordinates (with **not corrected** `l`)
  eq_approx(
    convert({ l = 15, c = 13, h = 0 }, 'rgb', { gamut_clip = 'cusp' }),
    convert({ l = 18.8397, c = 11.7727, h = 0 }, 'rgb'),
    0.02
  )
  eq_approx(
    convert({ l = 85, c = 13, h = 0 }, 'rgb', { gamut_clip = 'cusp' }),
    convert({ l = 82.003, c = 11.5003, h = 0 }, 'rgb'),
    0.02
  )
end

T['convert()']['converts to Oklab'] = function()
  local validate = function(x, ref, tol) eq_approx(convert(x, 'oklab'), ref, tol or 0) end

  local oklab_ref = { l = 54.7293, a = -2.6923, b = -7.0722 }
  validate(67, oklab_ref, 1e-3)
  validate('#5f87af', oklab_ref, 1e-3)
  validate({ r = 95, g = 135, b = 175 }, oklab_ref, 1e-3)
  validate(oklab_ref, oklab_ref, 1e-6)
  validate({ l = 54.7293, c = 7.5673, h = 249.1588 }, oklab_ref, 1e-3)
  validate({ l = 54.7293, s = 44.0189, h = 249.1588 }, oklab_ref, 1e-3)

  -- Handles grays
  local gray_ref = { l = 8, a = 0, b = 0 }
  validate(gray_ref, gray_ref)
  validate({ l = 8, c = 0 }, gray_ref)
  validate({ l = 8, c = 0, h = 180 }, gray_ref)
  validate({ l = 8, s = 0 }, gray_ref)
  validate({ l = 8, s = 0, h = 180 }, gray_ref)

  -- Normalization
  validate({ l = 110, a = 1, b = 1 }, { l = 100, a = 1, b = 1 }, 1e-6)
  validate({ l = -10, a = 1, b = 1 }, { l = 0, a = 1, b = 1 }, 1e-6)
end

T['convert()']['converts to Oklch'] = function()
  local validate = function(x, ref, tol) eq_approx(convert(x, 'oklch'), ref, tol or 0) end

  local oklch_ref = { l = 54.7293, c = 7.5673, h = 249.1588 }
  validate(67, oklch_ref, 1e-3)
  validate('#5f87af', oklch_ref, 1e-3)
  validate({ r = 95, g = 135, b = 175 }, oklch_ref, 1e-3)
  validate({ l = 54.7293, a = -2.6923, b = -7.0722 }, oklch_ref, 1e-3)
  validate(oklch_ref, oklch_ref, 1e-6)
  validate({ l = 54.7293, s = 44.0189, h = 249.1588 }, oklch_ref, 1e-3)

  -- Handles grays
  local gray_ref = { l = 8, c = 0 }
  validate({ l = 8, a = 0, b = 0 }, gray_ref)
  validate(gray_ref, gray_ref)
  validate({ l = 8, c = 0, h = 180 }, gray_ref)
  validate({ l = 8, s = 0 }, gray_ref)
  validate({ l = 8, s = 0, h = 180 }, gray_ref)

  -- Normalization
  validate({ l = 110, c = 10, h = 0 }, { l = 100, c = 10, h = 0 }, 1e-6)
  validate({ l = -10, c = 10, h = 0 }, { l = 0, c = 10, h = 0 }, 1e-6)

  validate({ l = 50, c = -10, h = 0 }, { l = 50, c = 0 }, 1e-6)

  validate({ l = 50, c = 10, h = -90 }, { l = 50, c = 10, h = 270 }, 1e-6)
  validate({ l = 50, c = 10, h = 450 }, { l = 50, c = 10, h = 90 }, 1e-6)
  validate({ l = 50, c = 10, h = 360 }, { l = 50, c = 10, h = 0 }, 1e-6)
end

T['convert()']['converts to okhsl'] = function()
  local validate = function(x, ref, tol) eq_approx(convert(x, 'okhsl'), ref, tol or 0) end

  local okhsl_ref = { l = 54.7293, s = 44.0189, h = 249.1588 }
  validate(67, okhsl_ref, 1e-3)
  validate('#5f87af', okhsl_ref, 1e-3)
  validate({ r = 95, g = 135, b = 175 }, okhsl_ref, 1e-3)
  validate({ l = 54.7293, a = -2.6923, b = -7.0722 }, okhsl_ref, 1e-3)
  validate({ l = 54.7293, c = 7.5673, h = 249.1588 }, okhsl_ref, 1e-3)
  validate(okhsl_ref, okhsl_ref, 1e-6)

  -- Handles grays
  local gray_ref = { l = 8, s = 0 }
  validate({ l = 8, a = 0, b = 0 }, gray_ref)
  validate({ l = 8, c = 0 }, gray_ref)
  validate({ l = 8, c = 0, h = 180 }, gray_ref)
  validate(gray_ref, gray_ref)
  validate({ l = 8, s = 0, h = 180 }, gray_ref)

  -- Normalization
  validate({ l = 110, s = 10, h = 0 }, { l = 100, s = 0 }, 1e-6)
  validate({ l = -10, s = 10, h = 0 }, { l = 0, s = 0 }, 1e-6)

  validate({ l = 50, s = -10, h = 0 }, { l = 50, s = 0 }, 1e-6)

  validate({ l = 50, s = 10, h = -90 }, { l = 50, s = 10, h = 270 }, 1e-6)
  validate({ l = 50, s = 10, h = 450 }, { l = 50, s = 10, h = 90 }, 1e-6)
  validate({ l = 50, s = 10, h = 360 }, { l = 50, s = 10, h = 0 }, 1e-6)
end

T['convert()']['respects `opts.adjust_lightness`'] = function()
  -- Should return correct lightness estimate
  local validate = function(input, space, ref_output)
    eq(convert(input, space, { adjust_lightness = false }), ref_output)
  end
  validate({ l = 20, a = 2, b = 0 }, 'hex', '#1e1216')
  validate({ l = 20, c = 2, h = 0 }, 'hex', '#1e1216')
  validate({ l = 20, s = 26, h = 357 }, 'hex', '#1e1216')

  local validate_approx = function(input, space, ref_output, tol)
    eq_approx(convert(input, space, { adjust_lightness = false }), ref_output, tol)
  end
  validate_approx({ l = 20, a = 2, b = 0 }, 'rgb', { r = 30, g = 18, b = 22 }, 0.5)
  validate_approx({ l = 20, c = 2, h = 0 }, 'rgb', { r = 30, g = 18, b = 22 }, 0.5)
  validate_approx({ l = 20, s = 26, h = 357 }, 'rgb', { r = 30, g = 18, b = 22 }, 0.5)

  local validate_l = function(input, space, ref_l)
    eq_approx(convert(input, space, { adjust_lightness = false }).l, ref_l, 0.05)
  end
  validate_l('#1e1216', 'oklab', 20)
  validate_l('#1e1216', 'oklch', 20)
  validate_l('#1e1216', 'okhsl', 20)

  local validate_same_l = function(input, space) eq(convert(input, space, { adjust_lightness = false }).l, input.l) end
  validate_same_l({ l = 20, a = 2, b = 0 }, 'oklch')
  validate_same_l({ l = 20, a = 2, b = 0 }, 'okhsl')
  validate_same_l({ l = 20, c = 2, h = 0 }, 'oklab')
  validate_same_l({ l = 20, c = 2, h = 0 }, 'okhsl')
  validate_same_l({ l = 20, s = 26, h = 357 }, 'oklab')
  validate_same_l({ l = 20, s = 26, h = 357 }, 'oklch')

  -- Should compute correct gamut clipping
  eq(convert({ l = 20, c = 20, h = 0 }, 'hex', { adjust_lightness = false, gamut_clip = 'lightness' }), '#b2005d')
  eq(convert({ l = 20, c = 20, h = 0 }, 'hex', { adjust_lightness = false, gamut_clip = 'cusp' }), '#6a0035')
end

T['convert()']['validates arguments'] = function()
  -- Input
  expect.error(function() convert('aaaaaa', 'rgb') end, 'Can not infer color space of "aaaaaa"')
  expect.error(function() convert('##aaaaaa', 'rgb') end, 'Can not infer')
  expect.error(function() convert({}, 'rgb') end, 'Can not infer color space of {}')
  expect.error(function() convert({ l = 50, a = 1 }, 'rgb') end, 'Can not infer color space of')

  -- - `nil` is allowed as input
  eq(child.lua_get([[MiniColors.convert(nil, 'hex')]]), vim.NIL)

  -- `to_space`
  expect.error(function() convert('#aaaaaa', 'AAA') end, 'one of')
end

-- Only basic testing here. More thorough tests are in `chan_modify()`
-- Assumes they both are implemented similarly
T['modify_channel()'] = new_set()

T['modify_channel()']['works'] = function()
  child.lua('_G.f = function(x) return x + 10 end')
  local validate = function(channel, ref)
    local lua_get_cmd = string.format([[MiniColors.modify_channel('#ba4a73', '%s', _G.f)]], channel)
    eq(child.lua_get(lua_get_cmd), ref)
  end

  validate('lightness', '#d8658d')
  validate('chroma', '#d70071')
  validate('saturation', '#c33f72')
  validate('hue', '#bd4a62')
  validate('temperature', '#bd4a62')
  validate('pressure', '#ba4a73')
  validate('a', '#d70071')
  validate('b', '#cb4021')
  validate('red', '#c44a73')
  validate('green', '#ba5473')
  validate('blue', '#ba4a7d')
end

T['modify_channel()']['accepts input in any color space'] = function()
  local validate = function(input)
    child.lua('_G.f = function(x) return x end')
    local lua_get_cmd = string.format([[MiniColors.modify_channel(%s, 'lightness', _G.f)]], vim.inspect(input))
    eq(child.lua_get(lua_get_cmd), '#5f87af')
  end

  validate(67)
  validate('#5f87af')
  validate({ r = 95, g = 135, b = 175 })
  validate({ l = 54.729, a = -2.692, b = -7.072 })
  validate({ l = 54.729, c = 7.567, h = 249.16 })
  validate({ l = 54.729, s = 44.01, h = 249.16 })
end

T['modify_channel()']['validates arguments'] = function()
  child.lua('_G.f = function(x) return x + 1 end')

  expect.error(function() child.lua([[MiniColors.modify_channel(1, 'hue', _G.f)]]) end, 'color space')
  expect.error(function() child.lua([[MiniColors.modify_channel('111111', 'hue', _G.f)]]) end, 'color space')

  expect.error(function() child.lua([[MiniColors.modify_channel('#000000', 1, _G.f)]]) end, 'Channel.*one of')
  expect.error(function() child.lua([[MiniColors.modify_channel('#000000', 'aaa', _G.f)]]) end, 'Channel.*one of')

  expect.error(function() child.lua([[MiniColors.modify_channel('#000000', 'hue', 1)]]) end, '`f`.*callable')
end

T['modify_channel()']['respects `opts.gamut_clip`'] = function()
  eq(
    child.lua_get(
      [[MiniColors.modify_channel('#ba4a73', 'chroma', function() return 100 end, { gamut_clip = 'cusp' })]]
    ),
    '#f50081'
  )
end

T['simulate_cvd()'] = new_set()

local simulate_cvd = function(...) return child.lua_get('MiniColors.simulate_cvd(...)', { ... }) end

T['simulate_cvd()']['works for "protan"'] = function()
  local validate = function(x, severity, ref) eq(simulate_cvd(x, 'protan', severity), ref) end

  local hex = '#00ff00'
  validate(hex, 0.0, '#00ff00')
  validate(hex, 0.1, '#2ef400')
  validate(hex, 0.2, '#55ea00')
  validate(hex, 0.3, '#77e300')
  validate(hex, 0.4, '#94dd00')
  validate(hex, 0.5, '#add800')
  validate(hex, 0.6, '#c4d400')
  validate(hex, 0.7, '#d9d000')
  validate(hex, 0.8, '#ebcd00')
  validate(hex, 0.9, '#fdcb00')
  validate(hex, 1.0, '#ffc900')

  -- Works for non-hex input
  validate({ r = 0, g = 255, b = 0 }, 1, '#ffc900')
end

T['simulate_cvd()']['works for "deutan"'] = function()
  local validate = function(x, severity, ref) eq(simulate_cvd(x, 'deutan', severity), ref) end

  local hex = '#00ff00'
  validate(hex, 0.0, '#00ff00')
  validate(hex, 0.1, '#2def02')
  validate(hex, 0.2, '#51e303')
  validate(hex, 0.3, '#6fd805')
  validate(hex, 0.4, '#87cf06')
  validate(hex, 0.5, '#9bc707')
  validate(hex, 0.6, '#acc008')
  validate(hex, 0.7, '#bbba09')
  validate(hex, 0.8, '#c7b50a')
  validate(hex, 0.9, '#d2b00a')
  validate(hex, 1.0, '#dbab0b')

  -- Works for non-hex input
  validate({ r = 0, g = 255, b = 0 }, 1, '#dbab0b')
end

T['simulate_cvd()']['works for "tritan"'] = function()
  local validate = function(x, severity, ref) eq(simulate_cvd(x, 'tritan', severity), ref) end

  local hex = '#00ff00'
  validate(hex, 0.0, '#00ff00')
  validate(hex, 0.1, '#18f60e')
  validate(hex, 0.2, '#22f11b')
  validate(hex, 0.3, '#21f026')
  validate(hex, 0.4, '#17f131')
  validate(hex, 0.5, '#07f43f')
  validate(hex, 0.6, '#00f851')
  validate(hex, 0.7, '#00fa67')
  validate(hex, 0.8, '#00f980')
  validate(hex, 0.9, '#00f499')
  validate(hex, 1.0, '#00edb0')

  -- Works for non-hex input
  validate({ r = 0, g = 255, b = 0 }, 1, '#00edb0')
end

T['simulate_cvd()']['works for "mono"'] = function()
  local validate = function(lightness)
    local hex = convert({ l = lightness, c = 4, h = 0 }, 'hex')
    local ref_gray = convert({ l = convert(hex, 'oklch').l, c = 0 }, 'hex')
    eq(simulate_cvd(hex, 'mono'), ref_gray)
  end

  for i = 0, 10 do
    validate(10 * i)
  end

  -- Works for non-hex input
  eq(simulate_cvd({ r = 0, g = 255, b = 0 }, 'mono'), '#d3d3d3')
end

T['simulate_cvd()']['allows all values of `severity`'] = function()
  local validate = function(severity_1, severity_2)
    eq(simulate_cvd('#00ff00', 'protan', severity_1), simulate_cvd('#00ff00', 'protan', severity_2))
  end

  -- Not one of 0, 0.1, ..., 0.9, 1 is rounded towards closest one
  validate(0.54, 0.5)
  validate(0.56, 0.6)

  -- `nil` is allowed
  validate(nil, 1)

  -- Out of bounds values
  validate(100, 1)
  validate(-100, 0)
end

T['simulate_cvd()']['validates arguments'] = function()
  -- Input
  expect.error(function() simulate_cvd('aaaaaa', 'protan', 1) end, 'Can not infer color space of "aaaaaa"')
  expect.error(function() simulate_cvd({}, 'protan', 1) end, 'Can not infer color space of {}')

  -- - `nil` is allowed as input
  eq(child.lua_get([[MiniColors.simulate_cvd(nil, 'protan', 1)]]), vim.NIL)

  -- `cvd_type`
  expect.error(function() simulate_cvd('#aaaaaa', 'AAA', 1) end, 'one of')

  -- `severity`
  expect.error(function() simulate_cvd('#aaaaaa', 'protan', 'a') end, '`severity`.*number')
end

-- Integration tests ==========================================================
T[':Colorscheme'] = new_set({ n_retry = helpers.get_n_retry(8) })

T[':Colorscheme']['works'] = function()
  mock_cs()

  child.cmd('hi Normal guifg=#ffffff')
  type_keys(':Colorscheme mock_cs<CR>')
  sleep(default_transition_duration + 3 * small_time)
  expect.match(child.cmd_capture('hi Normal'), 'guifg=#5f87af')
end

T[':Colorscheme']['accepts several arguments'] = function()
  helpers.skip_if_slow()

  child.cmd('colorscheme blue')
  mock_cs()
  type_keys(':Colorscheme mock_cs blue<CR>')

  sleep(default_transition_duration + small_time)
  expect.match(child.cmd_capture('hi Normal'), 'guifg=#5f87af')

  sleep(default_show_duration - 2 * small_transition_time)
  expect.match(child.cmd_capture('hi Normal'), 'guifg=#5f87af')

  sleep(default_transition_duration + 2 * small_transition_time + small_time)
  expect.match(child.cmd_capture('hi Normal'), 'guifg=#ffd700')
end

T[':Colorscheme']['provides proper completion'] = function()
  mock_cs()
  type_keys(':Colorscheme mock_<Tab> blu<Tab>')
  eq(child.fn.getcmdline(), 'Colorscheme mock_cs blue')
  type_keys('<Esc>')
end

T['interactive()'] = new_set()

T['interactive()']['works'] = function()
  -- - Mock '~/.config/nvim'
  local lua_cmd = 'vim.fn.stdpath = function() return ' .. vim.inspect(dir_path) .. ' end'
  child.lua(lua_cmd)
  child.cmd('set rtp+=' .. dir_path)
  MiniTest.finally(function() vim.fn.delete(colors_path, 'rf') end)

  -- Check screenshots only on Neovim>=0.11 as there are slight differences in
  -- highlighting
  local expect_screenshot = function()
    if child.fn.has('nvim-0.11') == 1 then child.expect_screenshot() end
  end

  child.set_size(30, 60)
  child.o.cmdheight = 3

  child.g.colors_name = 'test_interactive'
  child.cmd('hi Normal guifg=#ffffff guibg=#000000')

  child.lua('MiniColors.interactive()')

  -- General data
  expect_screenshot()

  eq(child.api.nvim_buf_get_name(0), 'minicolors://' .. child.api.nvim_get_current_buf() .. '/interactive')
  eq(child.bo.filetype, 'lua')
  eq(child.get_cursor(), { 22, 0 })
  eq(child.api.nvim_get_mode().mode, 'n')

  -- Applying transformations using direct calls to methods
  type_keys('i', [[chan_invert('lightness')]], '<Esc>')
  type_keys('<M-a>')
  expect.match(child.cmd_capture('hi Normal'), 'guifg=#000000 guibg=#ffffff')

  -- Writing
  -- - Write
  type_keys('<A-w>')
  expect_screenshot()
  type_keys('<C-w>new_cs<CR>')

  -- - Verify
  child.cmd('hi Normal guifg=#ffffff guibg=#000000')
  child.cmd('colorscheme new_cs')
  eq(child.g.colors_name, 'new_cs')
  expect.match(child.cmd_capture('hi Normal'), 'guifg=#000000 guibg=#ffffff')

  -- Resetting
  type_keys('<M-r>')
  eq(child.g.colors_name, 'test_interactive')
  expect.match(child.cmd_capture('hi Normal'), 'guifg=#ffffff guibg=#000000')

  -- Quitting
  local cur_buf_id = child.api.nvim_get_current_buf()
  type_keys('<M-q>')
  eq(child.api.nvim_get_current_buf() ~= cur_buf_id, true)
end

T['interactive()']['works without prior `setup()`'] = function()
  unload_module()
  expect.no_error(function() child.lua([[require('mini.colors').interactive()]]) end)

  expect.match(child.cmd_capture('nmap <M-a>'), 'Apply')
end

T['interactive()']['can have side effects'] = function()
  child.lua('MiniColors.interactive()')
  type_keys('i', '_G.a = 1', '<Esc>')
  type_keys('<M-a>')
  eq(child.lua_get('_G.a'), 1)
end

T['interactive()']['has no internal side effects'] = function()
  child.lua('MiniColors.interactive()')
  type_keys('<M-a>')

  -- Temporary values are not kept global
  local validate_nil = function(var_name) eq(child.lua_get('type(' .. var_name .. ')'), 'nil') end

  validate_nil('_G._interactive_cs')
  validate_nil('self')

  -- Direct methods should not be global
  validate_nil('apply')
  validate_nil('add_cterm_attributes')
  validate_nil('add_terminal_colors')
  validate_nil('add_transparency')
  validate_nil('chan_add')
  validate_nil('chan_invert')
  validate_nil('chan_modify')
  validate_nil('chan_multiply')
  validate_nil('chan_repel')
  validate_nil('chan_set')
  validate_nil('color_modify')
  validate_nil('compress')
  validate_nil('get_palette')
  validate_nil('resolve_links')
  validate_nil('simulate_cvd')
  validate_nil('write')
end

T['interactive()']['exposes relevant variables'] = function()
  child.lua([[_G.cs = MiniColors.as_colorscheme({
    name = 'input_cs',
    groups = { Normal = { fg = '#ffffff' } }
  })]])
  child.lua('MiniColors.interactive({ colorscheme = _G.cs })')

  local validate_code = function(value_code, ref_output)
    type_keys('cc', '_G.output = ', value_code, '<Esc>')
    type_keys('<M-a>')
    eq(child.lua_get('_G.output'), ref_output)
  end

  -- Methods should be exposed (hope they are correct ones)
  --stylua: ignore
  local methods = {
    'apply', 'add_cterm_attributes', 'add_terminal_colors', 'add_transparency',
    'chan_add', 'chan_invert', 'chan_modify', 'chan_multiply', 'chan_repel', 'chan_set',
    'color_modify', 'compress', 'get_palette', 'resolve_links', 'simulate_cvd', 'write',
  }
  for _, meth in ipairs(methods) do
    validate_code('type(' .. meth .. ')', 'function')
  end

  -- `self` should be exposed with initial updatable colorscheme
  type_keys('cc', [[chan_invert('lightness'); _G.self = self]], '<Esc>')
  type_keys('<M-a>')
  eq(child.lua_get('_G.self.name'), 'input_cs')
  eq(child.lua_get('_G.self.groups.Normal.fg'), '#000000')
end

T['interactive()']['handles errors'] = function()
  child.o.cmdheight = 10

  child.lua('MiniColors.interactive()')
  type_keys('i', 'a = 1 + true', '<Esc>')

  expect.error(function() type_keys('<M-a>') end, 'attempt.*arithmetic.*boolean')
end

T['interactive()']['respects `opts.colorscheme`'] = function()
  child.lua([[_G.cs = MiniColors.as_colorscheme({
    name = 'input_cs',
    groups = { Normal = { fg = '#ffffff' } },
  })]])
  child.g.colors_name = 'current_cs'
  child.cmd('hi Normal guifg=#000000')

  child.lua('MiniColors.interactive({ colorscheme = _G.cs })')

  -- Apply
  type_keys('<M-a>')
  eq(child.g.colors_name, 'input_cs')
  expect.match(child.cmd_capture('hi Normal'), 'guifg=#ffffff')

  -- Reset
  child.cmd('hi Normal guifg=#000000')
  type_keys('<M-a>')
  expect.match(child.cmd_capture('hi Normal'), 'guifg=#ffffff')
end

T['interactive()']['respects `opts.mappings`'] = function()
  child.lua([[MiniColors.interactive({
    mappings = { Apply = '<C-a>', Reset = '<C-r>', Quit = '<C-q>', Write = '<C-w>' },
  })]])

  local n = 0
  local validate_desc = function(desc, ref_desc)
    eq(desc, ref_desc)
    n = n + 1
  end

  local buf_maps = child.api.nvim_buf_get_keymap(0, 'n')
  for _, m in ipairs(buf_maps) do
    if m.lhs == '<C-A>' then validate_desc(m.desc, 'Apply') end
    if m.lhs == '<C-R>' then validate_desc(m.desc, 'Reset') end
    if m.lhs == '<C-Q>' then validate_desc(m.desc, 'Quit') end
    if m.lhs == '<C-W>' then validate_desc(m.desc, 'Write') end
  end
  -- Validate that all maps are created
  eq(n, 4)
end

return T
