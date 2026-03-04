local helpers = dofile('tests/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('map', config) end
local unload_module = function() child.mini_unload('map') end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
--stylua: ignore end

-- Main function wrappers
local map_open = function(opts) child.lua('MiniMap.open(...)', { opts }) end

local map_refresh = function(opts, parts) child.lua('MiniMap.refresh(...)', { opts, parts }) end

local map_close = function() child.lua('MiniMap.close()') end

-- Helpers related to 'mini.map'
local get_resolution_test_file = function(id) return 'tests/dir-map/resolution_' .. id end

local get_map_win_id = function() return child.lua_get('MiniMap.current.win_data[vim.api.nvim_get_current_tabpage()]') end

local get_map_win_side = function()
  local win_config = child.api.nvim_win_get_config(get_map_win_id())
  if win_config.anchor == 'NE' and win_config.col == child.o.columns then return 'right' end
  if win_config.anchor == 'NW' and win_config.col == 0 then return 'left' end
  return 'something is wrong'
end

local get_current = function() return child.lua_get('MiniMap.current') end

local get_map_width = function() return child.api.nvim_win_get_width(get_map_win_id()) end

local disable_map_updates = function()
  child.cmd([[
    augroup MiniMap
      au!
    augroup END
  ]])
end

local mock_diagnostic = function() child.cmd('source tests/dir-map/mock-diagnostic.lua') end

local mock_gitsigns = function() child.cmd('set rtp+=tests/dir-map') end

local mock_diff = function()
  child.lua([[
    local diff = require('mini.diff')
    diff.setup({ source = diff.gen_source.none(), options = { linematch = 0 } })
    local buf_text = { 'uuu', 'vvv', 'aaa', 'bbb', 'ddd', 'EEE', 'FFF', 'GGG', 'HHH', 'III', 'JJJ', 'KKK', 'LLL' }
    local ref_text = { 'aaa', 'bbb', 'ccc', 'ddd', 'eee', 'fff' }

    vim.api.nvim_buf_set_lines(0, 0, -1, false, buf_text)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    diff.set_ref_text(0, ref_text)
  ]])
end

local source_test_integration = function() child.cmd('source tests/dir-map/src-test-integration.lua') end

local mock_test_integration = function()
  source_test_integration()

  child.lua([[
    local integrations = MiniMap.config.integrations or {}
    table.insert(integrations, _G.test_integration)
    MiniMap.config.integrations = integrations
  ]])
end

local source_test_encode_symbols = function()
  child.lua([[_G.test_encode_symbols = { '1', '2', '3', '4', resolution = { row = 1, col = 2 } }]])
end

-- Various utilities
local tbl_repeat = function(x, n)
  local res = {}
  for _ = 1, n do
    table.insert(res, x)
  end
  return res
end

local eq_keys = function(tbl, ref_keys)
  local test_keys = vim.tbl_keys(tbl)
  local ref_keys_copy = vim.deepcopy(ref_keys)

  table.sort(test_keys)
  table.sort(ref_keys_copy)
  eq(test_keys, ref_keys_copy)
end

local get_n_shown_windows = function() return #child.api.nvim_tabpage_list_wins(0) end

-- Output test set
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

-- Data =======================================================================
-- All possible encodings of '3x2' resolution
local example_lines = {
  '  a  aaa  a  aaa',
  '        a a a a ',
  '                ',
  '  a  aaa  a  aaa',
  ' a a a aaaaaaaaa',
  '                ',
  '  a  aaa  a  aaa',
  '        a a a a ',
  'a a a a a a a a ',
  '  a  aaa  a  aaa',
  ' a a a aaaaaaaaa',
  'a a a a a a a a ',
  '  a  aaa  a  aaa',
  '        a a a a ',
  ' a a a a a a a a',
  '  a  aaa  a  aaa',
  ' a a a aaaaaaaaa',
  ' a a a a a a a a',
  '  a  aaa  a  aaa',
  '        a a a a ',
  'aaaaaaaaaaaaaaaa',
  '  a  aaa  a  aaa',
  ' a a a aaaaaaaaa',
  'aaaaaaaaaaaaaaaa',
}

local extended_example_lines = vim.deepcopy(example_lines)
vim.list_extend(extended_example_lines, example_lines)

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  -- Global variable
  eq(child.lua_get('type(_G.MiniMap)'), 'table')

  -- Autocommand group
  eq(child.fn.exists('#MiniMap'), 1)

  -- Highlight groups
  child.cmd('hi clear')
  load_module()
  local has_highlight = function(group, value) expect.match(child.cmd_capture('hi ' .. group), value) end

  has_highlight('MiniMapNormal', 'links to NormalFloat')
  has_highlight('MiniMapSymbolCount', 'links to Special')
  has_highlight('MiniMapSymbolLine', 'links to Title')
  has_highlight('MiniMapSymbolView', 'links to Delimiter')
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniMap.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniMap.config.' .. field), value) end

  -- Check default values
  expect_config('integrations', vim.NIL)

  expect_config('symbols.encode', vim.NIL)
  expect_config('symbols.scroll_line', '█')
  expect_config('symbols.scroll_view', '┃')

  expect_config('window.focusable', false)
  expect_config('window.side', 'right')
  expect_config('window.show_integration_count', true)
  expect_config('window.width', 10)
  expect_config('window.winblend', 25)
  expect_config('window.zindex', 10)
end

T['setup()']['respects `config` argument'] = function()
  unload_module()
  load_module({ window = { width = 1 } })
  eq(child.lua_get('MiniMap.config.window.width'), 1)
end

T['setup()']['validates `config` argument'] = function()
  unload_module()

  local expect_config_error = function(config, name, target_type)
    expect.error(function() load_module(config) end, vim.pesc(name) .. '.*' .. vim.pesc(target_type))
  end

  local expect_all_encode_symbols_check = function()
    local expect_bad_config = function(err_pattern)
      expect.error(function() child.lua([[MiniMap.setup(_G.bad_config)]]) end, err_pattern)
    end

    child.lua('_G.bad_config = { symbols = { encode = { resolution = { col = 2, row = 2 } } } }')
    for i = 1, 4 do
      expect_bad_config('symbols%.encode%[' .. i .. '%].*string')
      child.lua(string.format('_G.bad_config.symbols.encode[%d] = "%d"', i, i))
    end
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ integrations = 'a' }, 'integrations', 'array')
  expect_config_error({ integrations = { 'a' } }, 'integrations', 'callable')

  expect_config_error({ symbols = 'a' }, 'symbols', 'table')
  expect_config_error({ symbols = { encode = 'a' } }, 'symbols.encode', 'table')

  expect_config_error({ symbols = { encode = { resolution = 'a' } } }, 'symbols.encode.resolution', 'table')
  expect_config_error(
    { symbols = { encode = { resolution = { col = 'a' } } } },
    'symbols.encode.resolution.col',
    'number'
  )
  expect_config_error(
    { symbols = { encode = { resolution = { col = 2, row = 'a' } } } },
    'symbols.encode.resolution.row',
    'number'
  )
  expect_all_encode_symbols_check()

  expect_config_error({ symbols = { scroll_line = 1 } }, 'symbols.scroll_line', 'string')
  expect_config_error({ symbols = { scroll_view = 1 } }, 'symbols.scroll_view', 'string')

  expect_config_error({ window = 'a' }, 'window', 'table')
  expect_config_error({ window = { focusable = 1 } }, 'window.focusable', 'boolean')
  expect_config_error({ window = { side = 1 } }, 'window.side', 'one of')
  expect_config_error({ window = { side = 'a' } }, 'window.side', 'one of')
  expect_config_error({ window = { show_integration_count = 1 } }, 'window.show_integration_count', 'boolean')
  expect_config_error({ window = { width = 'a' } }, 'window.width', 'number')
  expect_config_error({ window = { winblend = 'a' } }, 'window.winblend', 'number')
  expect_config_error({ window = { zindex = 'a' } }, 'window.zindex', 'number')
end

T['setup()']['ensures colors'] = function()
  child.cmd('colorscheme default')
  expect.match(child.cmd_capture('hi MiniMapNormal'), 'links to NormalFloat')
end

local encode_strings = function(strings, opts)
  local cmd = string.format('MiniMap.encode_strings(%s, %s)', vim.inspect(strings), vim.inspect(opts))
  return child.lua_get(cmd)
end

T['encode_strings()'] = new_set()

T['encode_strings()']['works'] = function() eq(encode_strings({ 'aa', 'aa', 'aa' }), { '█' }) end

T['encode_strings()']['validates `strings` argument'] = function()
  expect.error(function() encode_strings('a') end, 'array')
  expect.error(function() encode_strings({ 1, 'a' }) end, 'strings')
end

T['encode_strings()']['respects `strings` argument'] = function() eq(encode_strings({ 'aa' }), { '🬂' }) end

T['encode_strings()']['respects `opts.n_rows`'] = function()
  local strings = tbl_repeat('aa', 3 * 3)
  eq(encode_strings(strings), { '█', '█', '█' })
  eq(encode_strings(strings, { n_rows = 1 }), { '█' })
  -- Very big values are trimmed to minimum necessary needed
  eq(encode_strings(strings, { n_rows = 1000 }), { '█', '█', '█' })

  -- Rescaling should be done via "output is non-empty if at least one cell is
  -- non-empty; empty if all empty"
  eq(encode_strings({ 'a', ' ', ' ', ' ', ' ', 'a', 'a', 'a', ' ', ' ', ' ' }, { n_rows = 2 }), { '🬐', '🬀' })
end

T['encode_strings()']['respects `opts.n_cols`'] = function()
  local strings = tbl_repeat('aaaaaa', 3)
  eq(encode_strings(strings), { '███' })
  eq(encode_strings(strings, { n_cols = 1 }), { '█' })
  -- Very big values are trimmed to minimum necessary needed
  eq(encode_strings(strings, { n_cols = 1000 }), { '███' })

  -- Rescaling should be done via "output is non-empty if at least one cell is
  -- non-empty; empty if all empty"
  eq(encode_strings({ 'a  a  aa' }, { n_cols = 2 }), { '🬂🬁' })
end

T['encode_strings()']['respects `opts.symbols`'] = function()
  source_test_encode_symbols()
  eq(
    child.lua_get([[MiniMap.encode_strings({ '  aa', 'a  a' }, { symbols = _G.test_encode_symbols })]]),
    { '14', '23' }
  )
end

T['encode_strings()']['works with empty strings'] = function()
  eq(encode_strings({ 'aaaa', '', 'aaaa', '' }), { '🬰🬰', '  ' })
end

T['encode_strings()']['correctly computes default dimensions'] = function()
  eq(encode_strings({ 'a', 'aa', 'aaa', 'aaaa', 'aaaaa', '' }), { '🬺🬏 ', '🬎🬎🬃' })
end

T['encode_strings()']['does not trim whitespace'] = function()
  eq(encode_strings({ ' ' }), { ' ' })
  eq(encode_strings({ 'aa  ', 'aa  ', 'aa  ' }), { '█ ' })
end

T['encode_strings()']['works with multibyte strings'] = function()
  eq(encode_strings({ 'ыыыыыы', 'ыыыы', 'ыы', 'aaaaaa', 'aaaa', 'aa' }), { '█🬎🬂', '█🬎🬂' })
end

T['encode_strings()']['correctly rescales in edge cases'] = function()
  -- There were cases with more straightforward rescaling when certain middle
  -- output row was not affected by any input row, leaving it empty. This was
  -- because rescaling coefficient was more than 1.
  local strings = tbl_repeat('aa', 37)
  local ref_output = tbl_repeat('█', 12)
  table.insert(ref_output, '🬂')
  eq(encode_strings(strings), ref_output)
end

T['encode_strings()']['can work with input dimensions being not multiple of resolution'] = function()
  eq(encode_strings({ 'a' }), { '🬀' })
  eq(encode_strings({ 'aaa' }), { '🬂🬀' })
  eq(encode_strings({ 'a', 'a' }), { '🬄' })
  eq(encode_strings({ 'a', 'a', 'a', 'a' }), { '▌', '🬀' })
end

T['encode_strings()']['expands tabs'] = function()
  eq(encode_strings({ '\taa' }), { '    🬂' })

  child.o.tabstop = 4
  eq(encode_strings({ '\taa' }), { '  🬂' })
end

T['open()'] = new_set({ hooks = { pre_case = function() child.set_size(30, 30) end } })

T['open()']['works'] = function()
  set_lines(example_lines)
  set_cursor(15, 0)
  mock_test_integration()

  map_open()

  child.expect_screenshot()
end

T['open()']['sets important map buffer options'] = function()
  local init_buf = child.api.nvim_get_current_buf()
  map_open()
  local all_bufs = child.api.nvim_list_bufs()
  eq(#all_bufs, 2)
  local map_buf_id = all_bufs[1] == init_buf and all_bufs[2] or all_bufs[1]

  eq(child.api.nvim_buf_get_name(map_buf_id), 'minimap://' .. map_buf_id .. '/content')

  local validate_option = function(name, value) eq(child.api.nvim_buf_get_option(map_buf_id, name), value) end

  validate_option('filetype', 'minimap')

  validate_option('buftype', 'nofile')
  validate_option('buflisted', false)
  validate_option('swapfile', false)
end

T['open()']['sets important window options'] = function()
  local init_win = child.api.nvim_get_current_win()
  map_open()
  local all_wins = child.api.nvim_tabpage_list_wins(0)
  eq(#all_wins, 2)
  local map_win_id = all_wins[1] == init_win and all_wins[2] or all_wins[1]

  local validate_option = function(name, value) eq(child.api.nvim_win_get_option(map_win_id, name), value) end

  validate_option('foldcolumn', '0')
  validate_option('signcolumn', 'auto')
  validate_option('wrap', false)
end

T['open()']['correctly computes window config'] = function()
  child.set_size(30, 20)
  map_open()
  local win_id = get_map_win_id()

  local hide, mouse, border, style
  if child.fn.has('nvim-0.10') == 1 then hide = false end
  if child.fn.has('nvim-0.11') == 1 then mouse = false end
  if child.fn.has('nvim-0.12') == 1 then
    border = 'none'
    style = 'minimal'
  end
  eq(child.api.nvim_win_get_config(win_id), {
    anchor = 'NE',
    border = border,
    col = 20,
    external = false,
    focusable = false,
    height = 28,
    hide = hide,
    mouse = mouse,
    relative = 'editor',
    row = 0,
    style = style,
    width = 10,
    zindex = 10,
  })
  eq(child.api.nvim_win_get_option(win_id, 'winblend'), child.lua_get('MiniMap.config.window.winblend'))
end

T['open()']['respects `opts.integrations` argument'] = function()
  set_lines(example_lines)
  source_test_integration()
  child.lua('MiniMap.open({ integrations = { _G.test_integration } })')
  child.expect_screenshot()

  -- Updates current data accordingly
  eq(child.lua_get('MiniMap.current.opts.integrations[1] == _G.test_integration'), true)
end

T['open()']['respects `opts.symbols` argument'] = function()
  set_lines(example_lines)
  source_test_encode_symbols()
  child.lua([[MiniMap.open({
    symbols = { encode = _G.test_encode_symbols, scroll_line = '>', scroll_view = '+' },
  })]])

  child.expect_screenshot()

  -- Can have empty strings as scrollbar characters, virtually disabling it
  map_close()
  map_open({ symbols = { scroll_line = '', scroll_view = '' } })
  child.expect_screenshot()
end

T['open()']['allows more than single character in scroll symbols'] = function()
  set_lines(example_lines)
  source_test_encode_symbols()
  map_open({ symbols = { scroll_line = '>|<', scroll_view = '||' } })
  child.expect_screenshot()
end

T['open()']['respects `opts.window` argument'] = function()
  set_lines(example_lines)
  --stylua: ignore
  local opts = {
    window = { focusable = true, side = 'left', show_integration_count = false, width = 15, winblend = 50, zindex = 20 },
  }
  map_open(opts)

  child.expect_screenshot()
  eq(child.api.nvim_win_get_option(get_map_win_id(), 'winblend'), 50)
  eq(child.api.nvim_win_get_config(get_map_win_id()).zindex, 20)

  -- Map window should be focusable
  child.cmd('wincmd w')
  eq(child.api.nvim_get_current_win(), get_map_win_id())

  -- Updates current data accordingly
  eq(child.lua_get('MiniMap.current.opts.window'), opts.window)
end

T['open()']['respects `MiniMap.config`'] = function()
  child.lua('MiniMap.config.window.width = 20')
  map_open()
  eq(child.api.nvim_win_get_width(get_map_win_id()), 20)
  eq(child.lua_get('MiniMap.current.opts.window.width'), 20)
end

T['open()']['respects `MiniMap.current`'] = function()
  child.lua([[MiniMap.current.opts = { window = { side = 'left' } }]])
  map_open()
  eq(get_map_win_side(), 'left')
end

T['open()']['correctly updates `MiniMap.current`'] = function()
  map_open()
  local current = get_current()

  eq_keys(current, { 'buf_data', 'opts', 'win_data' })

  eq_keys(current.buf_data, { 'map', 'source' })
  eq(current.buf_data.source, child.api.nvim_get_current_buf())

  eq(current.opts, child.lua_get('MiniMap.config'))

  eq_keys(current.win_data, { child.api.nvim_get_current_tabpage() })
end

T['open()']['respects important options when computing window height'] = function()
  local validate = function(options, row, height)
    local default_opts = { showtabline = 1, laststatus = 2, cmdheight = 1 }
    options = vim.tbl_deep_extend('force', default_opts, options)
    for name, value in pairs(options) do
      child.o[name] = value
    end

    map_open()
    local config = child.api.nvim_win_get_config(get_map_win_id())
    eq(config.row, row)
    eq(config.height, height)
    map_close()

    for name, value in pairs(default_opts) do
      child.o[name] = value
    end
  end

  validate({ showtabline = 0, laststatus = 0, cmdheight = 1 }, 0, 29)

  -- Tabline. Should make space for it if it is actually shown
  validate({ showtabline = 2, laststatus = 0 }, 1, 28)

  validate({ showtabline = 1, laststatus = 0 }, 0, 29)
  child.cmd('tabedit')
  validate({ showtabline = 2, laststatus = 0 }, 1, 28)
  child.cmd('tabclose')

  -- Statusline
  validate({ showtabline = 0, laststatus = 1 }, 0, 28)
  validate({ showtabline = 0, laststatus = 2 }, 0, 28)
  validate({ showtabline = 0, laststatus = 3 }, 0, 28)

  -- Command line
  validate({ showtabline = 0, laststatus = 0, cmdheight = 4 }, 0, 26)
  validate({ showtabline = 0, laststatus = 0, cmdheight = 0 }, 0, 30)
end

T['open()']['can be used with already opened window'] = function()
  map_open()
  local current = get_current()
  expect.no_error(map_open)
  eq(current, get_current())
end

T['open()']['can be used in multiple tabpages'] = function()
  local init_tabpage = child.api.nvim_get_current_tabpage()
  map_open()
  child.cmd('tabedit')
  local second_tabpage = child.api.nvim_get_current_tabpage()

  -- Shouldn't be open in new tabpage
  eq(get_map_win_id(), vim.NIL)

  -- Should open window and register it as second opened
  map_open()
  eq(#get_current().win_data, 2)
  eq(get_map_win_id() ~= nil, true)

  -- Should be independently closed
  child.api.nvim_set_current_tabpage(init_tabpage)
  map_close()
  eq(child.lua_get('vim.tbl_count(MiniMap.current.win_data)'), 1)
  eq(get_map_win_id(), vim.NIL)

  child.api.nvim_set_current_tabpage(second_tabpage)
  eq(get_map_win_id() ~= nil, true)
end

T['open()']['can open pure scrollbar'] = function()
  set_lines(example_lines)
  set_cursor(15, 0)
  child.cmd('normal! zz')
  map_open({ window = { width = 1 } })
  child.expect_screenshot()
end

T['open()']['works after previous window was closed manually'] = function()
  map_open()
  eq(#child.api.nvim_tabpage_list_wins(0), 2)
  child.api.nvim_win_close(get_map_win_id(), true)
  eq(#child.api.nvim_tabpage_list_wins(0), 1)

  expect.no_error(map_open)
  eq(#child.api.nvim_tabpage_list_wins(0), 2)
end

T['open()']['shows appropriate integration counts'] = function()
  child.lua([[_G.integration_many_matches = function()
    local res = {}
    for i = 1, 11 do
      for j = 1, i do
        table.insert(res, { line = i, hl_group = 'Operator' })
      end
    end
    return res
  end]])

  set_lines(example_lines)
  child.lua([[MiniMap.open({
    integrations = { _G.integration_many_matches },
    symbols = { encode = { ' ', '█', resolution = { row = 1, col = 1 } } }
  })]])
  child.expect_screenshot()
end

T['open()']['respects `MiniMapNormal` highlight group'] = function()
  set_lines(example_lines)
  child.cmd('hi MiniMapNormal ctermfg=black')
  map_open({ window = { winblend = 0 } })

  -- Open separate floating window for comparison
  local buf_id = child.api.nvim_create_buf(true, false)
  child.api.nvim_buf_set_lines(buf_id, 0, -1, true, tbl_repeat('bbbbb', 10))
  child.api.nvim_open_win(buf_id, false, {
    relative = 'editor',
    anchor = 'NW',
    row = 0,
    col = 0,
    width = 5,
    height = 10,
  })

  -- Highlighting of map and other floating window should differ
  child.expect_screenshot()
end

T['open()']['respects `vim.{g,b}.minimap_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minimap_disable = true

    map_open()
    eq(#child.api.nvim_tabpage_list_wins(0), 1)
  end,
})

T['refresh()'] =
  new_set({ hooks = {
    pre_case = function()
      child.set_size(30, 30)
      disable_map_updates()
    end,
  } })

T['refresh()']['works'] = function()
  map_open()

  set_lines(example_lines)
  set_cursor(15, 0)
  mock_test_integration()
  child.expect_screenshot()

  map_refresh()
  child.expect_screenshot()
end

T['refresh()']['works without opened map'] = function() expect.no_error(map_refresh) end

T['refresh()']['respects `opts.integrations` argument'] = function()
  set_lines(example_lines)
  map_open()

  source_test_integration()
  child.lua('MiniMap.refresh({ integrations = { _G.test_integration } })')
  child.expect_screenshot()

  -- Updates current data accordingly
  eq(child.lua_get('MiniMap.current.opts.integrations[1] == _G.test_integration'), true)
end

T['refresh()']['respects `opts.symbols` argument'] = function()
  set_lines(example_lines)
  source_test_encode_symbols()

  map_open()

  child.lua([[MiniMap.refresh({
    symbols = { encode = _G.test_encode_symbols, scroll_line = '>', scroll_view = '+' },
  })]])
  child.expect_screenshot()

  -- Updates current data accordingly
  eq(child.lua_get('MiniMap.current.opts.symbols.scroll_line'), '>')
end

T['refresh()']['respects `opts.window` argument'] = function()
  set_lines(example_lines)
  map_open()

  --stylua: ignore
  local opts = {
    window = { focusable = true, side = 'left', show_integration_count = false, width = 15, winblend = 50, zindex = 20 },
  }
  map_refresh(opts)

  child.expect_screenshot()
  eq(child.api.nvim_win_get_option(get_map_win_id(), 'winblend'), 50)
  eq(child.api.nvim_win_get_config(get_map_win_id()).zindex, 20)

  -- Updates current data accordingly
  eq(child.lua_get('MiniMap.current.opts.window'), opts.window)
end

T['refresh()']['respects `parts` argument'] = function()
  map_open()
  child.expect_screenshot()

  set_lines(tbl_repeat('aa aa aa', #example_lines))
  set_cursor(15, 0)
  mock_test_integration()

  -- Nothing should have changed in map window
  map_refresh({}, { integrations = false, lines = false, scrollbar = false })
  child.expect_screenshot()

  -- Only lines should have changed in map window
  map_refresh({}, { integrations = false, lines = true, scrollbar = false })
  child.expect_screenshot()

  -- Only scrollbar should have changed in map window
  set_lines(example_lines)
  map_refresh({}, { integrations = false, lines = false, scrollbar = true })
  child.expect_screenshot()

  -- Only integration highlights should have changed in map window
  set_cursor(1, 0)
  map_refresh({}, { integrations = true, lines = false, scrollbar = false })
  child.expect_screenshot()
end

T['refresh()']['is not affected by `MiniMap.config.window`'] = function()
  child.lua('MiniMap.config.window.width = 10')

  map_open()
  eq(get_map_width(), 10)

  child.lua('MiniMap.config.window.width = 20')
  map_refresh()
  eq(get_map_width(), 10)
end

T['refresh()']['updates `MiniMap.current`'] = function()
  child.lua('MiniMap.config.window.width = 20')
  map_open()
  eq(child.api.nvim_win_get_width(get_map_win_id()), 20)
  eq(child.lua_get('MiniMap.current.opts.window.width'), 20)
end

T['refresh()']['respects `MiniMap.current`'] = function()
  -- Check that any interactive refresh keeps all windows with synced options
  map_open()
  child.lua([[MiniMap.current.opts.window.side = 'left']])

  eq(get_map_win_side(), 'right')
  map_refresh()
  eq(get_map_win_side(), 'left')
end

T['refresh()']['respects `vim.{g,b}.minimap_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    disable_map_updates()
    map_open()

    child[var_type].minimap_disable = true
    set_lines(example_lines)
    map_refresh()
    -- Shouldn't show any map lines
    child.expect_screenshot()
  end,
})

T['close()'] = new_set()

T['close()']['works'] = function()
  map_open()
  eq(#child.api.nvim_tabpage_list_wins(0), 2)
  map_close()
  eq(#child.api.nvim_tabpage_list_wins(0), 1)
end

T['close()']['resets `MiniMap.current.opts` after closing last map window'] = function()
  local is_current_opts_reset = function() return child.lua_get('vim.tbl_count(MiniMap.current.opts)') == 0 end

  map_open()
  local init_tabpage = child.api.nvim_get_current_tabpage()
  child.cmd('tabedit')
  local second_tabpage = child.api.nvim_get_current_tabpage()
  map_open()

  eq(#child.api.nvim_list_wins(), 4)
  eq(is_current_opts_reset(), false)

  child.api.nvim_set_current_tabpage(init_tabpage)
  map_close()
  eq(#child.api.nvim_list_wins(), 3)
  eq(is_current_opts_reset(), false)

  child.api.nvim_set_current_tabpage(second_tabpage)
  map_close()
  eq(#child.api.nvim_list_wins(), 2)
  eq(is_current_opts_reset(), true)
end

T['close()']['does not error if window was closed manually'] = function()
  map_open()
  eq(#child.api.nvim_tabpage_list_wins(0), 2)
  child.api.nvim_win_close(get_map_win_id(), true)
  eq(#child.api.nvim_tabpage_list_wins(0), 1)

  -- Should not error and make proper clean up
  eq(#get_current().win_data, 1)
  expect.no_error(map_close)
  eq(#get_current().win_data, 0)
end

T['close()']['disrespects `vim.{g,b}.minimap_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    map_open()
    eq(get_n_shown_windows(), 2)
    child[var_type].minimap_disable = true

    map_close()
    eq(get_n_shown_windows(), 1)
  end,
})

T['toggle()'] = new_set()

T['toggle()']['works'] = function()
  eq(get_n_shown_windows(), 1)

  child.lua('MiniMap.toggle()')
  eq(get_n_shown_windows(), 2)
  eq(vim.tbl_count(get_current().win_data), 1)

  child.lua('MiniMap.toggle()')
  eq(get_n_shown_windows(), 1)
  eq(vim.tbl_count(get_current().win_data), 0)
end

T['toggle_focus()'] = new_set()

T['toggle_focus()']['works'] = function()
  set_lines(example_lines)
  set_cursor(15, 10)

  local init_win = child.api.nvim_get_current_win()
  map_open()
  eq(child.api.nvim_get_current_win(), init_win)

  -- Should move focus to map window
  child.lua('MiniMap.toggle_focus()')
  eq(child.api.nvim_get_current_win(), get_map_win_id())

  -- Moving cursor in map window should move cursor in previous window (line -
  -- first one encoded by the current map line; column - first non-blank)
  -- More tests in integration tests
  set_cursor(1, 0)
  child.lua('MiniMap.toggle_focus()')
  eq(child.api.nvim_get_current_win(), init_win)
  eq(get_cursor(), { 1, 2 })
end

T['toggle_focus()']['respects `use_previous_cursor`'] = function()
  set_lines(example_lines)
  set_cursor(15, 10)
  map_open()

  child.lua('MiniMap.toggle_focus()')
  set_cursor(1, 0)
  child.lua('MiniMap.toggle_focus(true)')
  eq(get_cursor(), { 15, 10 })
end

T['toggle_focus()']['does not move to first non-blank in source if no movement in map'] = function()
  set_lines(example_lines)
  set_cursor(15, 10)
  local init_win = child.api.nvim_get_current_win()

  map_open()
  child.lua('MiniMap.toggle_focus()')
  eq(child.api.nvim_get_current_win(), get_map_win_id())

  child.lua('MiniMap.toggle_focus()')
  eq(child.api.nvim_get_current_win(), init_win)
  eq(get_cursor(), { 15, 10 })
end

T['toggle_side()'] = new_set()

T['toggle_side()']['works'] = function()
  -- Can be used without opened window
  expect.no_error(function() child.lua('MiniMap.toggle_side()') end)

  map_open()
  eq(get_map_win_side(), 'right')
  child.lua('MiniMap.toggle_side()')
  eq(get_map_win_side(), 'left')
  child.lua('MiniMap.toggle_side()')
  eq(get_map_win_side(), 'right')
end

T['current'] = new_set()

T['current']['has initial value'] = function()
  eq(get_current(), {
    buf_data = {},
    opts = {},
    win_data = {},
  })
end

T['current']['has correct `buf_data` structure'] = function()
  local init_buf = child.api.nvim_get_current_buf()
  map_open()
  local all_bufs = child.api.nvim_list_bufs()
  eq(#all_bufs, 2)
  local map_buf_id = all_bufs[1] == init_buf and all_bufs[2] or all_bufs[1]

  eq(child.lua_get('MiniMap.current.buf_data'), { source = init_buf, map = map_buf_id })
end

T['current']['has correct `opts` structure'] = function()
  map_open()
  eq(child.lua_get('vim.deep_equal(MiniMap.current.opts, MiniMap.config)'), true)
end

T['current']['has correct `win_data` structure'] = function()
  map_open()
  local init_tabpage = child.api.nvim_get_current_tabpage()
  child.cmd('tabedit')
  local second_tabpage = child.api.nvim_get_current_tabpage()
  map_open()

  local opts_win_data = child.lua_get('MiniMap.current.win_data')
  eq_keys(opts_win_data, { init_tabpage, second_tabpage })

  local buf_1 = child.api.nvim_win_get_buf(opts_win_data[init_tabpage])
  eq(child.api.nvim_buf_get_option(buf_1, 'filetype'), 'minimap')

  local buf_2 = child.api.nvim_win_get_buf(opts_win_data[init_tabpage])
  eq(child.api.nvim_buf_get_option(buf_2, 'filetype'), 'minimap')
end

local validate_gen_encode_symbols = function(field, id)
  child.lua(string.format([[_G.symbols = MiniMap.gen_encode_symbols['%s']('%s')]], field, id))

  local cmd = string.format(
    [[MiniMap.encode_strings(vim.fn.readfile('%s'), { symbols = _G.symbols })]],
    get_resolution_test_file(id)
  )

  eq(child.lua_get(cmd), child.lua_get('{ table.concat(_G.symbols) }'))
end

T['gen_encode_symbols'] = new_set()

T['gen_encode_symbols']['can be used as `MiniMap.config.symbols.encode`'] = function()
  child.set_size(30, 30)
  unload_module()
  child.lua([[_G.map = require('mini.map')]])
  child.lua([[_G.map.setup({ symbols = { encode = _G.map.gen_encode_symbols.block('1x2') } })]])

  set_lines(example_lines)
  map_open()
  child.expect_screenshot()
end

T['gen_encode_symbols']['can be used as part of `opts.symbols.encode`'] = function()
  child.set_size(30, 30)

  set_lines(example_lines)
  child.lua([[MiniMap.open({ symbols = { encode = MiniMap.gen_encode_symbols.block('1x2') } })]])
  child.expect_screenshot()
end

T['gen_encode_symbols']['block()'] = function()
  validate_gen_encode_symbols('block', '1x2')
  validate_gen_encode_symbols('block', '2x1')
  validate_gen_encode_symbols('block', '2x2')
  validate_gen_encode_symbols('block', '3x2')
end

T['gen_encode_symbols']['dot()'] = function()
  validate_gen_encode_symbols('dot', '3x2')
  validate_gen_encode_symbols('dot', '4x2')
end

T['gen_encode_symbols']['shade()'] = function()
  validate_gen_encode_symbols('shade', '1x2')
  validate_gen_encode_symbols('shade', '2x1')
end

local map_open_with_integration = function(integration)
  local cmd = string.format('MiniMap.open({ integrations = { MiniMap.gen_integration.%s() } })', integration)
  child.lua(cmd)
end

T['gen_integration'] = new_set({
  hooks = {
    pre_case = function()
      child.set_size(30, 30)
      set_lines(example_lines)
      set_cursor(15, 0)
    end,
  },
})

T['gen_integration']['builtin_search()'] = new_set()

T['gen_integration']['builtin_search()']['works'] = function()
  local screen_opts = child.fn.has('nvim-0.12') == 1 and {} or { ignore_text = { 30 }, ignore_attr = { 30 } }
  map_open_with_integration('builtin_search')

  -- It should show counts for actual matches, not matched lines
  type_keys('/', ' a', '<CR>')
  child.expect_screenshot(screen_opts)

  -- Should not affect cursor
  local cur_pos = get_cursor()
  map_refresh()
  eq(get_cursor(), cur_pos)

  -- Should respect 'hlsearch' option
  child.o.hlsearch = false
  map_refresh()
  child.expect_screenshot(screen_opts)
end

T['gen_integration']['builtin_search()']['respects `hl_groups` argument'] = function()
  map_open_with_integration('builtin_search')

  child.lua([[MiniMap.config.integrations = {
    MiniMap.gen_integration.builtin_search({ search = 'MiniMapSymbolLine' })
  }]])
  type_keys('/', ' a', '<CR>')

  local output = child.lua_get('MiniMap.config.integrations[1]()')
  for _, v in ipairs(output) do
    eq(v.hl_group, 'MiniMapSymbolLine')
  end
end

T['gen_integration']['builtin_search()']['updates when appropriate'] = function()
  local screen_opts = child.fn.has('nvim-0.12') == 1 and {} or { ignore_text = { 30 }, ignore_attr = { 30 } }
  map_open_with_integration('builtin_search')

  type_keys('/', ' a', '<CR>')
  child.expect_screenshot(screen_opts)

  -- Should update when 'hlsearch' option is changed
  child.o.hlsearch = false
  child.expect_screenshot(screen_opts)

  child.o.hlsearch = true
  child.expect_screenshot(screen_opts)

  -- Should update when `v:hlsearch` is changed (like `\h` in 'mini.basics')
  if child.fn.has('nvim-0.10') == 0 then return end

  child.v.hlsearch = false
  child.expect_screenshot(screen_opts)

  child.v.hlsearch = true
  child.expect_screenshot(screen_opts)

  -- Ideally, it should also update when starting highlight search after
  -- `n/N/*`, etc.), but it currently doesn't seem possible
  -- See https://github.com/neovim/neovim/issues/18879
end

T['gen_integration']['builtin_search()']['respects documented keymaps'] = function()
  local screen_opts = child.fn.has('nvim-0.12') == 1 and {} or { ignore_text = { 30 }, ignore_attr = { 30 } }
  map_open_with_integration('builtin_search')

  child.lua([[
    for _, key in ipairs({ 'n', 'N', '*', '#' }) do
      vim.keymap.set(
        'n',
        key,
        key ..
          '<Cmd>lua MiniMap.refresh({}, {lines = false, scrollbar = false})<CR>'
      )
    end]])

  local validate = function(key)
    type_keys('/', ' a', '<CR>')
    child.cmd('nohlsearch')

    -- Should update map highlighting
    type_keys(key)
    child.expect_screenshot(screen_opts)
  end

  validate('n')
  validate('N')
  validate('*')
  validate('#')
end

T['gen_integration']['diagnostic()'] = new_set()

T['gen_integration']['diagnostic()']['works'] = function()
  mock_diagnostic()
  map_open_with_integration('diagnostic')
  child.expect_screenshot()
end

T['gen_integration']['diagnostic()']['respects `hl_groups` argument'] = function()
  mock_diagnostic()

  local validate = function(hl_groups)
    map_close()
    local cmd = string.format(
      [[MiniMap.open({ integrations = { MiniMap.gen_integration.diagnostic(%s) } })]],
      vim.inspect(hl_groups)
    )
    child.lua(cmd)

    child.expect_screenshot()

    map_close()
  end

  -- Each valid non-nil entry results into showing that diagnostic severity
  validate({ warn = 'DiagnosticFloatingWarn' })
  validate({ info = 'DiagnosticFloatingInfo' })
  validate({ hint = 'DiagnosticFloatingHint' })

  -- Higher severity should have higher priority
  validate({
    error = 'DiagnosticFloatingError',
    warn = 'DiagnosticFloatingWarn',
    info = 'DiagnosticFloatingInfo',
    hint = 'DiagnosticFloatingHint',
  })
end

T['gen_integration']['diagnostic()']['updates when appropriate'] = function()
  map_open()

  mock_diagnostic()
  child.lua('MiniMap.current.opts.integrations = { MiniMap.gen_integration.diagnostic() }')
  child.expect_screenshot()
  child.cmd('doautocmd DiagnosticChanged')
  child.expect_screenshot()
end

T['gen_integration']['gitsigns()'] = new_set()

T['gen_integration']['gitsigns()']['works'] = function()
  mock_gitsigns()
  map_open_with_integration('gitsigns')
  child.expect_screenshot()

  --stylua: ignore
  eq(
    child.lua_get('MiniMap.current.opts.integrations[1]()'),
    {
      { line = 1,    hl_group = 'GitSignsAdd' },
      { line = 2,    hl_group = 'GitSignsAdd' },
      { line = 4,    hl_group = 'GitSignsDelete' },
      { line = 7,    hl_group = 'GitSignsChange' },
      { line = 8,    hl_group = 'GitSignsChange' },
      { line = 9,    hl_group = 'GitSignsAdd' },
      { line = 10,   hl_group = 'GitSignsAdd' },
      { line = 11,   hl_group = 'GitSignsAdd' },
      { line = 12,   hl_group = 'GitSignsAdd' },
      { line = 0,    hl_group = 'GitSignsDelete' },
      { line = 1000, hl_group = 'GitSignsAdd' },
    }
  )
end

T['gen_integration']['gitsigns()']['respects `hl_groups` argument'] = function()
  mock_gitsigns()
  child.lua([[MiniMap.open({
    integrations = { MiniMap.gen_integration.gitsigns({ delete = 'Special' }) }
  })]])
  child.expect_screenshot()

  eq(
    child.lua_get('MiniMap.current.opts.integrations[1]()'),
    { { line = 4, hl_group = 'Special' }, { line = 0, hl_group = 'Special' } }
  )
end

T['gen_integration']['gitsigns()']['updates when appropriate'] = function()
  map_open()

  mock_gitsigns()
  child.lua('MiniMap.current.opts.integrations = { MiniMap.gen_integration.gitsigns() }')
  child.expect_screenshot()
  child.cmd('doautocmd User GitSignsUpdate')
  child.expect_screenshot()
end

T['gen_integration']['gitsigns()']['works if no "gitsigns" is detected'] = function()
  eq(child.lua_get('MiniMap.gen_integration.gitsigns()()'), {})
end

T['gen_integration']['diff()'] = new_set()

T['gen_integration']['diff()']['works'] = function()
  child.set_size(20, 30)
  mock_diff()
  map_open_with_integration('diff')
  child.expect_screenshot()

  --stylua: ignore
  eq(
    child.lua_get('MiniMap.current.opts.integrations[1]()'),
    {
      { line = 1 , hl_group = 'MiniDiffSignAdd'    },
      { line = 2 , hl_group = 'MiniDiffSignAdd'    },
      { line = 4 , hl_group = 'MiniDiffSignDelete' },
      { line = 6 , hl_group = 'MiniDiffSignChange' },
      { line = 7 , hl_group = 'MiniDiffSignChange' },
      { line = 8 , hl_group = 'MiniDiffSignAdd'    },
      { line = 9 , hl_group = 'MiniDiffSignAdd'    },
      { line = 10, hl_group = 'MiniDiffSignAdd'     },
      { line = 11, hl_group = 'MiniDiffSignAdd'     },
      { line = 12, hl_group = 'MiniDiffSignAdd'     },
      { line = 13, hl_group = 'MiniDiffSignAdd'    },
    }
  )
end

T['gen_integration']['diff()']['respects `hl_groups` argument'] = function()
  mock_diff()
  child.lua([[MiniMap.open({
    integrations = { MiniMap.gen_integration.diff({ delete = 'Special' }) }
  })]])
  eq(child.lua_get('MiniMap.current.opts.integrations[1]()'), { { line = 4, hl_group = 'Special' } })
end

T['gen_integration']['diff()']['updates when appropriate'] = function()
  map_open()

  mock_diff()
  child.lua([[
    local refresh_orig = MiniMap.refresh
    MiniMap.refresh = function(...)
      _G.n = (_G.n or 0) + 1
      refresh_orig(...)
    end
  ]])
  child.lua('MiniMap.current.opts.integrations = { MiniMap.gen_integration.diff() }')
  child.lua('_G.n = 0')
  child.cmd('doautocmd User MiniDiffUpdated')
  eq(child.lua_get('_G.n'), 1)
end

T['gen_integration']['diff()']['works if no diff data is found'] = function()
  -- Not enabled buffer
  mock_diff()
  child.lua('MiniDiff.disable(0)')
  eq(child.lua_get('MiniDiff.get_buf_data(0)'), vim.NIL)
  eq(child.lua_get('MiniMap.gen_integration.diff()()'), {})

  -- No 'mini.diff'
  child.lua([[
    MiniDiff = nil
    package.loaded['mini.diff'] = nil
    require = function() error() end
  ]])
  eq(child.lua_get('MiniMap.gen_integration.diff()()'), {})
end

-- Integration tests ==========================================================
T['Window'] = new_set()

T['Window']['fully updates on buffer enter'] = function()
  child.set_size(30, 30)
  mock_test_integration()

  local buf_1 = child.api.nvim_create_buf(true, false)
  child.api.nvim_buf_set_lines(buf_1, 0, -1, true, { 'aa', 'aa', 'aa', '   aa', '   aa' })

  local buf_2 = child.api.nvim_create_buf(true, false)
  child.api.nvim_buf_set_lines(buf_2, 0, -1, true, example_lines)

  child.api.nvim_set_current_buf(buf_1)
  map_open()
  child.expect_screenshot()

  child.api.nvim_set_current_buf(buf_2)
  child.expect_screenshot()
end

T['Window']['fully updates on buffer write'] = function()
  child.set_size(15, 20)
  mock_test_integration()
  child.o.autoindent = false

  map_open()
  type_keys('i', 'aaa<CR>', '   aa<CR>', '   aa')

  child.expect_screenshot()
  child.cmd('doautocmd BufWritePost')
  child.expect_screenshot()
end

T['Window']['fully updates on text change in Normal mode'] = function()
  child.set_size(15, 20)
  mock_test_integration()

  set_lines({ 'aaa', '   aa', '   aa' })
  set_cursor(3, 0)
  map_open()

  child.expect_screenshot()
  type_keys('d', 'k')
  child.expect_screenshot()
end

T['Window']['fully updates on vim resize'] = function()
  child.set_size(30, 30)
  mock_test_integration()

  set_lines(extended_example_lines)
  map_open()
  child.expect_screenshot()
  child.o.lines = 15
  child.expect_screenshot()
end

T['Window']['fully updates on mode change to Normal'] = function()
  child.set_size(15, 20)
  mock_test_integration()
  child.o.autoindent = false
  set_lines({ 'aa', '   aa', '   aa' })
  set_cursor(1, 0)

  map_open()
  type_keys('i', '   bb<CR>', '   bb<CR>', 'bb<CR>')
  child.expect_screenshot()
  type_keys('<Esc>')
  child.expect_screenshot()
end

T['Window']['implements buffer local mappings'] = function()
  set_lines(example_lines)
  map_open()

  local validate = function(key, ref_cursor)
    set_cursor(15, 10)
    child.lua('MiniMap.toggle_focus()')
    set_cursor(1, 0)
    type_keys(key)
    eq(get_cursor(), ref_cursor)
  end

  -- `<CR>` should accept currently showed line in source buffer and put on
  -- first non-blank character in line
  validate('<CR>', { 1, 2 })

  -- `<Esc>` should return to exact previous cursor position
  validate('<Esc>', { 15, 10 })
end

T['Window']['has options in sync across all opened windows'] = function()
  map_open()
  child.cmd('tabedit')
  map_open()

  type_keys('1gt')
  map_refresh({ window = { side = 'left' } })
  eq(get_map_win_side(), 'left')

  type_keys('2gt')
  eq(get_map_win_side(), 'left')
end

T['Window']['does not account for folds'] = function()
  child.set_size(30, 30)
  set_lines(extended_example_lines)

  map_open()
  child.expect_screenshot()

  -- Make fold
  set_cursor(7, 0)
  type_keys('zf', '24j')

  -- Should treat top and bottom visible lines as is
  set_cursor(1, 0)
  type_keys('7G')
  child.expect_screenshot()
  type_keys('j')
  child.expect_screenshot()
end

T['Window']['is not focusable by default'] = function()
  local init_win_id = child.api.nvim_get_current_win()
  set_lines(example_lines)
  map_open()

  child.cmd('wincmd w')
  eq(child.api.nvim_get_current_win(), init_win_id)
end

T['Window']['can be made focusable by mouse with `window.focusable = true`'] = function()
  set_lines(example_lines)
  map_open({ window = { focusable = true, side = 'left' } })

  -- Ensure drawn floating window (github.com/neovim/neovim/issues/25643)
  child.cmd('redraw')
  child.api.nvim_input_mouse('left', 'press', '', 0, 5, 5)
  eq(child.api.nvim_get_current_win(), get_map_win_id())
end

T['Window']['ensures target window is valid'] = function()
  local init_win_id = child.api.nvim_get_current_win()
  child.cmd('wincmd s')
  local target_win_id = child.api.nvim_get_current_win()
  map_open()
  child.lua('MiniMap.toggle_focus()')

  -- Closing target window should result into recomputing new target window
  child.api.nvim_win_close(target_win_id, true)
  child.lua('MiniMap.toggle_focus()')
  eq(child.api.nvim_get_current_win(), init_win_id)
end

T['Window']["does not respect 'winborder' option"] = function()
  if child.fn.has('nvim-0.11') == 0 then MiniTest.skip("'winborder' option is present on Neovim>=0.11") end
  child.set_size(15, 20)
  child.o.winborder = 'rounded'
  map_open()
  child.expect_screenshot()
end

T['Scrollbar'] = new_set()

T['Scrollbar']['updates on cursor movement'] = function()
  child.set_size(30, 30)
  set_lines(example_lines)
  map_open()
  local init_integration_update_count = child.lua_get('_G.n_test_integration_calls')

  set_cursor(1, 0)
  child.expect_screenshot()
  type_keys('3j')
  child.expect_screenshot()
  type_keys('5l')
  child.expect_screenshot()
  type_keys('G')
  child.expect_screenshot()

  -- Integrations shouldn't be called on cursor movement
  eq(child.lua_get('_G.n_test_integration_calls'), init_integration_update_count)
end

T['Scrollbar']['updates on source window scrolling'] = function()
  child.set_size(30, 30)
  set_lines(example_lines)
  map_open()
  local init_integration_update_count = child.lua_get('_G.n_test_integration_calls')

  set_cursor(21, 0)
  child.expect_screenshot()
  type_keys('zz')
  child.expect_screenshot()

  -- Integrations shouldn't be called on window scroll
  eq(child.lua_get('_G.n_test_integration_calls'), init_integration_update_count)
end

T['Pure scrollbar'] = new_set()

T['Pure scrollbar']['works'] = function()
  child.set_size(30, 30)
  set_lines(example_lines)
  map_open({ window = { width = 1, show_integration_count = false } })

  -- Should try to span all height in case of few lines
  child.expect_screenshot()
  type_keys('G')
  child.expect_screenshot()
end

T['Pure scrollbar']['is active when width is lower than offset'] = function()
  child.set_size(30, 30)
  set_lines(example_lines)

  -- Still should be pure scrollbar because integration count is shown
  map_open({ window = { width = 2, show_integration_count = true } })
  child.expect_screenshot()

  -- Still should be pure scrollbar because scroll symbols are wider
  map_refresh({ symbols = { scroll_line = '><' }, window = { width = 3 } })
  child.expect_screenshot()

  -- Should stop being pure scrollbar ones actual encoding can be shown
  map_refresh({ window = { width = 4 } })
  child.expect_screenshot()
end

T['Cursor in map window'] = new_set()

T['Cursor in map window']['moves cursor in source window'] = function()
  local init_win_id = child.api.nvim_get_current_win()
  local validate_source_cursor = function(ref_cursor) eq(child.api.nvim_win_get_cursor(init_win_id), ref_cursor) end
  set_lines(example_lines)
  set_cursor(2, 10)
  map_open()
  child.lua('MiniMap.toggle_focus()')

  -- It shouldn't move just after focusing
  eq(get_cursor(), { 1, 2 })
  validate_source_cursor({ 2, 10 })

  type_keys('l')
  validate_source_cursor({ 1, 0 })

  type_keys('j')
  validate_source_cursor({ 4, 0 })

  -- It puts source cursor on the first source line which is encoded as current
  -- map line
  type_keys('G')
  validate_source_cursor({ 22, 0 })
end

T['Cursor in map window']['opens enough folds in source window'] = function()
  child.set_size(30, 30)
  set_lines(example_lines)

  -- Make fold
  set_cursor(4, 0)
  type_keys('zf', '2j')
  set_cursor(1, 0)

  map_open()
  child.expect_screenshot()
  child.lua('MiniMap.toggle_focus()')
  type_keys('2G')
  child.expect_screenshot()
end

T['Cursor in map window']['can not move on scrollbar or integration counts'] = function()
  set_lines(example_lines)
  set_cursor(1, 0)

  map_open()
  child.lua('MiniMap.toggle_focus()')
  eq(get_cursor(), { 1, 2 })

  type_keys('h')
  eq(get_cursor(), { 1, 2 })

  type_keys('0')
  eq(get_cursor(), { 1, 2 })
end

T['Cursor in map window']['is properly set outside of `MiniMap.toggle_focus()`'] = function()
  set_lines(example_lines)
  set_cursor(15, 0)

  map_open({ window = { focusable = true } })
  type_keys('<C-w><C-w>')
  eq(child.api.nvim_get_current_win(), get_map_win_id())
  eq(get_cursor(), { 5, 2 })
end

return T
