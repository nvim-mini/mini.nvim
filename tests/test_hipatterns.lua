local helpers = dofile('tests/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
local load_module = function(config) child.mini_load('hipatterns', config) end
local set_lines = function(...) return child.set_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
local sleep = function(ms) helpers.sleep(ms, child, true) end

local forward_lua = function(fun_str)
  local lua_cmd = fun_str .. '(...)'
  return function(...) return child.lua_get(lua_cmd, { ... }) end
end

-- Module helpers
local get_hi_namespaces = function()
  local res = {}
  for name, ns_id in pairs(child.api.nvim_get_namespaces()) do
    local hi_name = name:match('^MiniHipatterns%-(.*)$')
    if hi_name ~= nil then res[hi_name] = ns_id end
  end
  return res
end

local get_hipatterns_extmarks = function(buf_id, hi_names)
  local hi_namespaces = get_hi_namespaces()
  hi_names = hi_names or vim.tbl_keys(hi_namespaces)

  local full_extmarks = {}
  for _, hi_name in ipairs(hi_names) do
    vim.list_extend(
      full_extmarks,
      child.api.nvim_buf_get_extmarks(buf_id, hi_namespaces[hi_name], 0, -1, { details = true })
    )
  end

  return vim.tbl_map(
    function(ext)
      return { line = ext[2] + 1, from_col = ext[3] + 1, to_col = ext[4].end_col, hl_group = ext[4].hl_group }
    end,
    full_extmarks
  )
end

local validate_hl_group = function(name, pattern) expect.match(child.cmd_capture('hi ' .. name), pattern) end

-- Data =======================================================================
local test_lines = { 'abcd abcd', 'Abcd ABCD', 'abcdaabcd' }

-- Time constants
local small_time = helpers.get_time_const(10)

-- Test config
local test_config = {
  highlighters = { abcd = { pattern = 'abcd', group = 'Error' } },
  delay = { text_change = 5 * small_time, scroll = 2 * small_time },
}

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      child.set_size(10, 15)

      child.lua('_G.test_config = ' .. vim.inspect(test_config))
    end,
    post_once = child.stop,
  },
  n_retry = helpers.get_n_retry(2),
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  load_module()

  -- Global variable
  eq(child.lua_get('type(_G.MiniHipatterns)'), 'table')

  -- Autocommand group
  eq(child.fn.exists('#MiniHipatterns'), 1)

  -- Highlight groups
  child.cmd('hi clear')
  child.cmd('hi DiagnosticError guifg=#ff0000 ctermfg=9')
  child.cmd('hi DiagnosticWarn  guifg=#ffff00 ctermfg=11')
  child.cmd('hi DiagnosticInfo  guifg=#0000ff ctermfg=14')
  child.cmd('hi DiagnosticHint  guifg=#00ffff ctermfg=12')
  load_module()
  local has_highlight = function(group, value) expect.match(child.cmd_capture('hi ' .. group), value) end

  has_highlight('MiniHipatternsFixme', 'cterm=bold,reverse ctermfg=9 gui=bold,reverse guifg=#ff0000')
  has_highlight('MiniHipatternsHack', 'cterm=bold,reverse ctermfg=11 gui=bold,reverse guifg=#ffff00')
  has_highlight('MiniHipatternsTodo', 'cterm=bold,reverse ctermfg=14 gui=bold,reverse guifg=#0000ff')
  has_highlight('MiniHipatternsNote', 'cterm=bold,reverse ctermfg=12 gui=bold,reverse guifg=#00ffff')
end

T['setup()']['creates `config` field'] = function()
  load_module()

  eq(child.lua_get('type(_G.MiniHipatterns.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniHipatterns.config.' .. field), value) end

  expect_config('highlighters', {})
  expect_config('delay.text_change', 200)
  expect_config('delay.scroll', 50)
end

T['setup()']['respects `config` argument'] = function()
  load_module({ delay = { text_change = 20 } })
  eq(child.lua_get('MiniHipatterns.config.delay.text_change'), 20)
end

T['setup()']['validates `config` argument'] = function()
  local expect_config_error = function(config, name, target_type)
    expect.error(function() load_module(config) end, vim.pesc(name) .. '.*' .. vim.pesc(target_type))
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ highlighters = 'a' }, 'highlighters', 'table')
  expect_config_error({ delay = 'a' }, 'delay', 'table')
  expect_config_error({ delay = { text_change = 'a' } }, 'delay.text_change', 'number')
  expect_config_error({ delay = { scroll = 'a' } }, 'delay.scroll', 'number')
end

T['setup()']['ensures colors'] = function()
  load_module()
  child.cmd('colorscheme default')
  expect.match(child.cmd_capture('hi MiniHipatternsFixme'), 'gui=bold,reverse')
end

T['setup()']['auto enables in all visible buffers'] = function()
  child.set_size(10, 30)
  child.o.winwidth = 1

  local buf_id_1 = child.api.nvim_get_current_buf()
  set_lines(test_lines)
  child.cmd('wincmd v')

  local buf_id_2 = child.api.nvim_create_buf(true, false)
  child.api.nvim_buf_set_lines(buf_id_2, 0, -1, false, { '22abcd22' })

  local buf_id_3 = child.api.nvim_create_buf(true, false)
  child.api.nvim_set_current_buf(buf_id_3)
  set_lines({ '33abcd33' })

  -- Should enable in all proper buffers currently shown in some window
  load_module(test_config)
  sleep(small_time)
  child.expect_screenshot()
  eq(child.lua_get('MiniHipatterns.get_enabled_buffers()'), { buf_id_1, buf_id_3 })

  child.api.nvim_set_current_buf(buf_id_2)
  sleep(small_time)
  child.expect_screenshot()
  eq(child.lua_get('MiniHipatterns.get_enabled_buffers()'), { buf_id_1, buf_id_2, buf_id_3 })
end

T['Auto enable'] = new_set()

T['Auto enable']['works'] = function()
  load_module(test_config)

  local init_buf_id = child.api.nvim_get_current_buf()
  local buf_id = child.api.nvim_create_buf(true, false)
  child.api.nvim_buf_set_lines(buf_id, 0, -1, false, { '22abcd22' })
  child.api.nvim_set_current_buf(buf_id)
  sleep(small_time)
  child.expect_screenshot()
  eq(child.lua_get('MiniHipatterns.get_enabled_buffers()'), { init_buf_id, buf_id })
end

T['Auto enable']['does not enable in not proper buffers'] = function()
  load_module(test_config)

  -- Should not load for not normal buffers
  local scratch_buf_id = child.api.nvim_create_buf(false, true)
  child.api.nvim_set_current_buf(scratch_buf_id)
  set_lines(test_lines)
  sleep(test_config.delay.text_change + small_time)
  child.expect_screenshot()

  -- Should not load for not loaded buffers
  local unloaded_buf_id = child.lua([[
    local unloaded_buf_id = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(unloaded_buf_id)
    vim.api.nvim_buf_delete(unloaded_buf_id, { unload = true })
    return unloaded_buf_id
  ]])
  local enabled_buffers = child.lua_get('MiniHipatterns.get_enabled_buffers()')
  eq(vim.tbl_contains(enabled_buffers, unloaded_buf_id), false)

  -- Should not error if buffer is not valid
  expect.no_error(function()
    child.lua([[
      local buf_id = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_set_current_buf(buf_id)
      vim.api.nvim_buf_delete(buf_id, { force = true })
    ]])
    eq(child.cmd_capture('1messages'), '')
  end)
end

T['Auto enable']['makes `:edit` work'] = function()
  load_module(test_config)

  local test_file = 'tests/hipatterns_file'
  MiniTest.finally(function() vim.fn.delete(test_file) end)

  child.cmd('edit ' .. test_file)
  set_lines(test_lines)
  child.cmd('write')

  sleep(test_config.delay.text_change + small_time)
  child.expect_screenshot()

  child.cmd('edit')
  child.expect_screenshot()
end

T['Autocommands'] = new_set()

T['Autocommands']['resets on color scheme change'] = function()
  child.set_size(10, 30)
  child.o.winwidth = 1

  child.lua([[_G.new_hl_group_highlighter = {
    pattern = 'aaa',
    group = function()
      vim.cmd('hi AAA cterm=underline')
      return 'AAA'
    end,
  }]])
  child.lua([[require('mini.hipatterns').setup({
    highlighters = { aaa = _G.new_hl_group_highlighter },
    delay = _G.test_config.delay,
  })]])

  set_lines({ 'aaa' })
  child.cmd('wincmd v | enew')
  set_lines({ 'xxaaaxx' })

  sleep(test_config.delay.text_change + small_time)
  child.expect_screenshot()

  -- After `:hi clear` highlighting disappears as highlight group is cleared
  child.cmd('hi clear')
  child.expect_screenshot({ ignore_attr = { child.o.lines } })

  -- `ColorScheme` event which should lead to highlight reevaluation of all
  -- enabled buffers
  child.cmd('doautocmd ColorScheme')
  child.expect_screenshot({ ignore_attr = { child.o.lines } })
end

T['enable()'] = new_set()

local enable = forward_lua([[require('mini.hipatterns').enable]])
local get_enabled_buffers = forward_lua([[require('mini.hipatterns').get_enabled_buffers]])

T['enable()']['works'] = function()
  set_lines(test_lines)
  enable(0, test_config)

  -- Should register buffer as enabled
  eq(get_enabled_buffers(), { child.api.nvim_get_current_buf() })

  -- Should add highlights immediately
  child.expect_screenshot()

  -- Should disable on buffer detach
  child.ensure_normal_mode()
  child.cmd('bdelete!')
  eq(get_enabled_buffers(), {})
end

T['enable()']['works with defaults'] = function()
  child.b.minihipatterns_config = test_config
  set_lines(test_lines)
  enable()
  child.expect_screenshot()
end

T['enable()']['works in not normal buffer'] = function()
  local scratch_buf_id = child.api.nvim_create_buf(false, true)
  child.api.nvim_set_current_buf(scratch_buf_id)

  set_lines({ 'xxabcdxx' })
  enable(scratch_buf_id, test_config)
  child.expect_screenshot()
end

T['enable()']['works in not current buffer'] = function()
  local new_buf_id = child.api.nvim_create_buf(true, false)
  child.api.nvim_buf_set_lines(new_buf_id, 0, -1, false, { 'xxabcdxx' })

  enable(new_buf_id, test_config)

  child.api.nvim_set_current_buf(new_buf_id)
  child.expect_screenshot()
end

T['enable()']['reacts to text change'] = function()
  -- Should enable debounced auto highlight on text change
  enable(0, test_config)

  -- Interactive text change
  type_keys('i', 'abc')
  sleep(test_config.delay.text_change - small_time)
  type_keys('d')

  -- - No highlights should be shown as delay was smaller than in config
  child.expect_screenshot()

  -- - Still no highlights should be shown
  sleep(test_config.delay.text_change - small_time)
  child.expect_screenshot()

  -- - Now there should be highlights
  sleep(2 * small_time)
  child.expect_screenshot()

  -- Not interactive text change
  set_lines({ 'ABCD', 'abcd' })

  child.expect_screenshot()
  sleep(test_config.delay.text_change + small_time)
  child.expect_screenshot()
end

T['enable()']['does not flicker during text insert'] = function()
  enable(0, test_config)

  -- Interactive text change
  type_keys('i', 'abcd')
  sleep(test_config.delay.text_change + small_time)
  child.expect_screenshot()

  type_keys(' abcd')
  child.expect_screenshot()
  sleep(test_config.delay.text_change + small_time)
  child.expect_screenshot()
end

T['enable()']['reacts to buffer enter'] = function()
  local init_buf_id = child.api.nvim_get_current_buf()
  enable(init_buf_id, { highlighters = test_config.highlighters })

  local other_buf_id = child.api.nvim_create_buf(true, false)
  child.api.nvim_set_current_buf(other_buf_id)

  -- On buffer enter it should update config and highlighting (after delay)
  local lua_cmd =
    string.format('vim.b[%d].minihipatterns_config = { delay = { text_change = %d } }', init_buf_id, 2 * small_time)
  child.lua(lua_cmd)
  child.api.nvim_buf_set_lines(init_buf_id, 0, -1, false, { 'abcd' })

  child.api.nvim_set_current_buf(init_buf_id)

  child.expect_screenshot()
  sleep(2 * small_time + small_time)
  child.expect_screenshot()
end

T['enable()']['reacts to filetype change'] = function()
  child.lua([[_G.hipatterns_config = {
    highlighters = {
      abcd_ft = {
        pattern = function(buf_id)
          if vim.bo[buf_id].filetype == 'aaa' then return nil end
          return 'abcd'
        end,
        group = 'Error'
      },
    },
    delay = _G.test_config.delay,
  }]])

  set_lines({ 'xxabcdxx' })
  child.lua([[require('mini.hipatterns').enable(0, _G.hipatterns_config)]])
  child.expect_screenshot()

  -- Should update highlighting after delay
  child.cmd('set filetype=aaa')
  child.expect_screenshot()
  sleep(test_config.delay.text_change + small_time)
  child.expect_screenshot()
end

T['enable()']['reacts to window scroll'] = function()
  enable(0, test_config)

  -- Change same line each before `delay.text_change`. This creates a situation
  -- when only one line will be highlighted while others - don't (but should).
  set_lines({ 'xxabcdxx' })
  type_keys('yy')
  for _ = 1, 15 do
    type_keys('P')
  end

  sleep(test_config.delay.text_change + small_time)
  child.expect_screenshot()

  -- Scroll should update highlighting inside view with `delay.scroll` debounce
  type_keys('<C-e>')
  sleep(0.5 * test_config.delay.scroll)
  type_keys('<C-e>')
  sleep(test_config.delay.scroll + small_time)
  child.expect_screenshot()

  -- Update should be done only on the final view
  type_keys('<C-y>')
  child.expect_screenshot()
  type_keys('2<C-e>')
  child.expect_screenshot()
end

T['enable()']['reacts to delete of line with match'] = function()
  set_lines({ 'abcd', 'xxx', 'xxx', 'abcd', 'xxx', 'xxx', 'abcd' })

  local hi_abcd = {
    pattern = 'abcd',
    group = '',
    extmark_opts = { virt_text = { { 'Hello', 'Error' } }, virt_text_pos = 'right_align' },
  }
  local config = { highlighters = { abcd = hi_abcd }, delay = test_config.delay }
  enable(0, config)

  sleep(test_config.delay.text_change + small_time)
  child.expect_screenshot()

  local validate = function(line_to_delete)
    child.api.nvim_win_set_cursor(0, { line_to_delete, 0 })
    type_keys('dd')
    sleep(test_config.delay.text_change + small_time)
    child.expect_screenshot()
  end

  validate(1)
  validate(3)
  validate(5)
end

T['Highlighters'] = new_set()

T['Highlighters']['silently skips wrong entries'] = function()
  local highlighters = {
    correct = { pattern = 'abcd', group = 'Error' },
    pattern_absent = { group = 'Error' },
    pattern_wrong_type = { pattern = 1, group = 'Error' },
    group_absent = { pattern = 'aaa' },
    group_wrong_type = { pattern = 'aaa', group = 1 },
    priority_wrong_type = { pattern = 'aaa', group = 'Error', extmark_opts = 'a' },
  }
  enable(0, { highlighters = highlighters, delay = test_config.delay })

  set_lines({ 'xxabcd', 'aaa' })
  sleep(test_config.delay.text_change + small_time)
  child.expect_screenshot()
end

T['Highlighters']['allows submatch in `pattern`'] = function()
  set_lines({ 'abcd', 'xabcd', 'xxabcd', 'xxabcdxx' })

  local validate = function(pattern)
    child.lua('require("mini.hipatterns").disable()')
    local config = {
      highlighters = { abcd = { pattern = pattern, group = 'Error' } },
      delay = test_config.delay,
    }
    enable(0, config)

    sleep(test_config.delay.text_change + small_time)
    child.expect_screenshot()
  end

  validate('xx()ab()cd')
  validate('()ab()cd')
  validate('ab()cd()')

  -- One capture `()` should also work treating it as start and inferring end
  -- as full match's end
  validate('()abcd')

  -- Third an more captures should be ignored
  validate('xx()ab()c()d()')
end

T['Highlighters']['works with overlapping matches'] = function()
  local validate = function(pattern, ref_ranges)
    child.lua('require("mini.hipatterns").disable()')
    local config = {
      highlighters = { x = { pattern = pattern, group = 'Error' } },
      delay = test_config.delay,
    }
    enable(0, config)

    sleep(test_config.delay.text_change + small_time)
    local ranges = vim.tbl_map(function(e) return { e.from_col, e.to_col } end, get_hipatterns_extmarks(0, { 'x' }))
    eq(ranges, ref_ranges)
  end

  set_lines({ string.rep('x', 7) })

  -- Should behave similarly to how `/` with `\zs` and `\ze` works
  validate('xxx', { { 1, 3 }, { 4, 6 } })
  validate('()xx()x', { { 1, 2 }, { 3, 4 }, { 5, 6 } })
  validate('x()xx()', { { 2, 3 }, { 5, 6 } })
  validate('x()x()x', { { 2, 2 }, { 4, 4 }, { 6, 6 } })
end

T['Highlighters']['allows frontier pattern in `pattern`'] = function()
  local config = {
    highlighters = { abcd = { pattern = '%f[%w]abcd%f[%W]', group = 'Error' } },
    delay = test_config.delay,
  }
  enable(0, config)

  set_lines({ 'abcd', 'xabcd', 'abcdx', 'xabcdx', ' abcd ' })
  sleep(test_config.delay.text_change + small_time)
  child.expect_screenshot()
end

T['Highlighters']['allows callable `pattern`'] = function()
  child.lua([[_G.hi_callable_pattern = {
    pattern = function(...)
      _G.args = { ... }
      return 'abcd'
    end,
    group = 'Error'
  }]])
  child.lua([[require('mini.hipatterns').enable(
    0,
    { highlighters = { test = _G.hi_callable_pattern }, delay = _G.test_config.delay }
  )]])

  set_lines({ 'xxabcd' })
  sleep(test_config.delay.text_change + small_time)
  child.expect_screenshot()
  -- Should be called with correct signature
  eq(child.lua_get('_G.args'), { child.api.nvim_get_current_buf() })
end

T['Highlighters']['allows return `nil` `pattern` to not highlight'] = function()
  child.lua([[_G.hi_conditional_pattern = {
    pattern = function(buf_id)
      if vim.b[buf_id].not_highlight then return nil end
      return 'abcd'
    end,
    group = 'Error'
  }]])
  child.lua([[require('mini.hipatterns').enable(
    0,
    { highlighters = { test = _G.hi_conditional_pattern }, delay = _G.test_config.delay }
  )]])

  set_lines({ 'xxabcd' })
  sleep(test_config.delay.text_change + small_time)
  child.expect_screenshot()

  child.b.not_highlight = true
  set_lines({ 'xxabcd' })
  sleep(test_config.delay.text_change + small_time)
  child.expect_screenshot()
end

T['Highlighters']['allows array `pattern`'] = function()
  -- Should allow both string and callable elements
  child.lua([[_G.hi_array = {
    pattern = {
      'abcd',
      function(buf_id)
        if vim.b[buf_id].not_highlight then return nil end
        return 'efgh'
      end
    } ,
    group = 'Error'
  }]])
  child.lua([[require('mini.hipatterns').enable(
    0,
    { highlighters = { array = _G.hi_array }, delay = _G.test_config.delay }
  )]])

  set_lines({ 'xxabcd', 'xxefgh' })
  sleep(test_config.delay.text_change + small_time)
  child.expect_screenshot()

  child.b.not_highlight = true
  set_lines({ 'xxabcd', 'xxefgh' })
  sleep(test_config.delay.text_change + small_time)
  child.expect_screenshot()
end

T['Highlighters']['allows callable `group`'] = function()
  child.lua([[_G.hi_callable_group = {
    pattern = 'abcd',
    group = function(...)
      _G.args = vim.deepcopy({ ... })
      return 'Error'
    end,
  }]])
  child.lua([[require('mini.hipatterns').enable(
    0,
    { highlighters = { test = _G.hi_callable_group }, delay = _G.test_config.delay }
  )]])

  set_lines({ 'xxabcd' })
  sleep(test_config.delay.text_change + small_time)
  child.expect_screenshot()
  -- Should be called with correct signature
  eq(child.lua_get('_G.args'), { 1, 'abcd', { full_match = 'abcd', line = 1, from_col = 3, to_col = 6 } })

  -- Check arguments with submatch
  local validate_submatch = function(pattern, ref_args)
    child.lua('_G.args = nil')
    child.lua('_G.hi_callable_group.pattern = ' .. vim.inspect(pattern))
    set_lines({ 'abcd' })
    sleep(test_config.delay.text_change + small_time)
    eq(child.lua_get('_G.args'), ref_args)
  end

  validate_submatch('()ab()cd', { 1, 'ab', { full_match = 'abcd', line = 1, from_col = 1, to_col = 2 } })
  validate_submatch('a()bc()d', { 1, 'bc', { full_match = 'abcd', line = 1, from_col = 2, to_col = 3 } })
  validate_submatch('ab()cd()', { 1, 'cd', { full_match = 'abcd', line = 1, from_col = 3, to_col = 4 } })

  validate_submatch('a()bcd', { 1, 'bcd', { full_match = 'abcd', line = 1, from_col = 2, to_col = 4 } })
end

T['Highlighters']['allows return `nil` `group` to not highlight'] = function()
  child.lua([[_G.hi_conditional_group = {
    pattern = 'abcd',
    group = function(buf_id, match, data)
      -- Don't highlight on even lines
      if data.line % 2 == 0 then return nil end
      return 'Error'
    end,
  }]])
  child.lua([[require('mini.hipatterns').enable(
    0,
    { highlighters = { test = _G.hi_conditional_group }, delay = _G.test_config.delay }
  )]])

  set_lines({ 'xxabcd', 'xxabcd', 'xxabcd', 'xxabcd', 'xxabcd' })
  sleep(test_config.delay.text_change + small_time)
  child.expect_screenshot()
end

T['Highlighters']['respects `extmark_opts.priority`'] = function()
  local config = { highlighters = { abcd = { pattern = 'abcd', group = 'Error' } } }
  set_lines({ 'abcd', 'abcd', 'abcd' })
  enable(0, config)
  child.expect_screenshot()

  local ns_id = child.api.nvim_create_namespace('test')
  local set_extmark = function(line, priority)
    child.api.nvim_buf_set_extmark(0, ns_id, line - 1, 0, { end_col = 4, hl_group = 'Visual', priority = priority })
  end

  -- Default priority should be 200
  set_extmark(1, 199)
  set_extmark(3, 201)
  child.expect_screenshot()

  -- Should respect extmark_opts.priority in `highlighters` entry
  child.lua([[require('mini.hipatterns').disable(0)]])
  config.highlighters.abcd.extmark_opts = { priority = 202 }
  enable(0, config)
  child.expect_screenshot()
end

T['Highlighters']['respects `extmark_opts`'] = function()
  child.lua([[_G.hi_abcd = { pattern = 'abcd', group = 'Error', extmark_opts = { priority = 100 } }]])
  child.lua([[_G.hi_efgh = {
    pattern = 'efgh',
    group = function() return 'Comment' end,
    extmark_opts = function(buf_id, match, data)
      _G.extmark_args = { buf_id = buf_id, match = match, data = vim.deepcopy(data) }
      return { hl_group = data.hl_group, end_row = data.line - 1, end_col = data.to_col - 2 }
    end,
  }]])

  set_lines({ 'abcd', 'efgh' })
  child.lua([[require('mini.hipatterns').enable(
    0,
    { highlighters = { abcd = _G.hi_abcd, efgh = _G.hi_efgh } }
  )]])

  child.expect_screenshot()

  -- Check actual extmark details
  local validate_full_extmark = function(extmark, row, col, details)
    eq({ row = extmark[2], col = extmark[3] }, { row = row, col = col })
    local real_details = {}
    for key, _ in pairs(details) do
      real_details[key] = extmark[4][key]
    end
    eq(real_details, details)
  end

  local hi_namespaces = get_hi_namespaces()

  -- As table (should set options needed for highlighting region)
  local abcd_extmarks = child.api.nvim_buf_get_extmarks(0, hi_namespaces['abcd'], 0, -1, { details = true })
  eq(#abcd_extmarks, 1)
  validate_full_extmark(abcd_extmarks[1], 0, 0, { priority = 100, hl_group = 'Error', end_row = 0, end_col = 4 })

  -- As callable
  local efgh_extmarks = child.api.nvim_buf_get_extmarks(0, hi_namespaces['efgh'], 0, -1, { details = true })
  eq(#efgh_extmarks, 1)
  validate_full_extmark(efgh_extmarks[1], 1, 0, { hl_group = 'Comment', end_row = 1, end_col = 2 })

  -- - Should be called with correct arguments
  eq(child.lua_get('_G.extmark_args'), {
    buf_id = child.api.nvim_get_current_buf(),
    match = 'efgh',
    data = { from_col = 1, full_match = 'efgh', hl_group = 'Comment', line = 2, to_col = 4 },
  })
end

T['enable()']['validates arguments'] = function()
  expect.error(function() enable('a', {}) end, '`buf_id`.*valid buffer id')
  expect.error(function() enable(child.api.nvim_get_current_buf(), 'a') end, '`config`.*table')
end

T['enable()']['respects `vim.{g,b}.minihipatterns_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minihipatterns_disable = true

    set_lines(test_lines)
    enable(0, test_config)
    sleep(test_config.delay.text_change + small_time)
    child.expect_screenshot()
  end,
})

T['enable()']['respects global config after `setup()`'] = function()
  set_lines(test_lines)
  load_module(test_config)
  enable(0)

  child.expect_screenshot()
end

T['enable()']['respects `vim.b.minihipatterns_config`'] = function()
  set_lines(test_lines)
  child.b.minihipatterns_config = test_config
  enable(0)

  child.expect_screenshot()

  -- Delay should also be respected
  set_lines({ 'abcd' })
  sleep(test_config.delay.text_change - small_time)
  child.expect_screenshot()
  sleep(2 * small_time)
  child.expect_screenshot()
end

T['disable()'] = new_set()

local disable = forward_lua([[require('mini.hipatterns').disable]])

T['disable()']['works'] = function()
  local cur_buf_id = child.api.nvim_get_current_buf()
  set_lines(test_lines)
  enable(0, test_config)
  child.expect_screenshot()

  -- By default should disable current buffer
  disable()
  child.expect_screenshot()
  eq(get_enabled_buffers(), {})

  -- Allows 0 as alias for current buffer
  enable(0, test_config)
  eq(get_enabled_buffers(), { cur_buf_id })
  disable(0)
  eq(get_enabled_buffers(), {})
end

T['disable()']['works in not current buffer'] = function()
  local init_buf_id = child.api.nvim_get_current_buf()
  set_lines(test_lines)
  enable(0, test_config)
  child.expect_screenshot()

  child.api.nvim_set_current_buf(child.api.nvim_create_buf(true, false))
  disable(init_buf_id)
  child.api.nvim_set_current_buf(init_buf_id)
  sleep(test_config.delay.text_change + small_time)
  child.expect_screenshot()
end

T['disable()']['works on not enabled buffer'] = function()
  expect.no_error(function() disable(0) end)
end

T['disable()']['validates arguments'] = function()
  expect.error(function() disable('a') end, '`buf_id`.*valid buffer id')
end

T['toggle()'] = new_set()

local toggle = forward_lua([[require('mini.hipatterns').toggle]])

T['toggle()']['works'] = function()
  local cur_buf_id = child.api.nvim_get_current_buf()
  set_lines(test_lines)

  -- By default should disable current buffer
  child.lua('_G.test_config = ' .. vim.inspect(test_config))
  child.lua([[require('mini.hipatterns').toggle(nil, test_config)]])
  child.expect_screenshot()
  eq(get_enabled_buffers(), { cur_buf_id })

  toggle()
  child.expect_screenshot()
  eq(get_enabled_buffers(), {})

  -- Allows 0 as alias for current buffer
  toggle(0, test_config)
  eq(get_enabled_buffers(), { cur_buf_id })

  toggle(0)
  eq(get_enabled_buffers(), {})
end

T['toggle()']['validates arguments'] = function()
  expect.error(function() toggle('a', {}) end, '`buf_id`.*valid buffer id')
  expect.error(function() toggle(child.api.nvim_get_current_buf(), 'a') end, '`config`.*table')
end

T['update()'] = new_set()

local update = forward_lua([[require('mini.hipatterns').update]])

T['update()']['works'] = function()
  child.lua([[_G.hi_conditional_pattern = {
    pattern = function(buf_id)
      if vim.b[buf_id].not_highlight then return nil end
      return 'abcd'
    end,
    group = 'Error'
  }]])
  child.lua([[require('mini.hipatterns').enable(
    0,
    { highlighters = { test = _G.hi_conditional_pattern }, delay = { text_change = 20 } }
  )]])

  local lines = { 'xxabcd', 'xxabcd', 'xxabcd', 'xxabcd' }
  set_lines(lines)
  sleep(test_config.delay.text_change + small_time)

  child.expect_screenshot()

  -- Should update immediately to not highlight only lines 2 and 3
  child.b.not_highlight = true
  update(0, 2, 3)
  child.expect_screenshot()

  -- Should work for single lines
  child.b.not_highlight = true
  update(0, 1, 1)
  child.expect_screenshot()

  -- `from_line` should be inferred as 1
  child.b.not_highlight = false
  child.lua([[require('mini.hipatterns').update(0, nil, 3)]])
  child.expect_screenshot()

  -- `to_line` should be inferred as last line
  child.b.not_highlight = true
  child.lua([[require('mini.hipatterns').update(0, 2, nil)]])
  child.expect_screenshot()

  -- Works on not current buffer
  local init_buf_id = child.api.nvim_get_current_buf()
  child.api.nvim_set_current_buf(child.api.nvim_create_buf(true, false))

  child.api.nvim_buf_set_var(init_buf_id, 'not_highlight', false)
  update(init_buf_id, 2, 3)
  child.api.nvim_set_current_buf(init_buf_id)
  child.expect_screenshot()
end

T['update()']['does not work in not enabled buffer'] = function()
  local cur_buf_id = child.api.nvim_get_current_buf()
  set_lines(test_lines)

  expect.error(function() update(cur_buf_id, 1, 2) end, 'Buffer ' .. cur_buf_id .. ' is not enabled')
end

T['update()']['validates arguments'] = function()
  enable(0)

  expect.error(function() update('a', 1, 2) end, '`buf_id`.*valid buffer id')
  expect.error(function() update(0, 'a', 2) end, '`from_line`.*number')
  expect.error(function() update(0, 1, 'a') end, '`to_line`.*number')
end

T['get_enabled_buffers()'] = new_set()

T['get_enabled_buffers()']['works'] = function()
  local create_buf = function() return child.api.nvim_create_buf(true, false) end
  local buf_id_1 = create_buf()
  create_buf()
  local buf_id_3 = create_buf()
  local buf_id_4 = create_buf()

  enable(buf_id_3)
  enable(buf_id_1)
  enable(buf_id_4)
  eq(get_enabled_buffers(), { buf_id_1, buf_id_3, buf_id_4 })

  disable(buf_id_3)
  eq(get_enabled_buffers(), { buf_id_1, buf_id_4 })

  -- Does not return invalid buffers
  child.api.nvim_buf_delete(buf_id_4, {})
  eq(get_enabled_buffers(), { buf_id_1 })
end

T['get_matches()'] = new_set()

local get_matches = forward_lua([[require('mini.hipatterns').get_matches]])

T['get_matches()']['works'] = function()
  local buf_id_1 = child.api.nvim_create_buf(true, false)
  child.api.nvim_buf_set_lines(buf_id_1, 0, -1, false, { 'aaa bbb', '  aaa', '  bbb' })
  local buf_id_2 = child.api.nvim_create_buf(true, false)

  child.lua([[require('mini.hipatterns').setup({
    highlighters = {
      -- Common highlighter
      aaa = { pattern = 'aaa', group = 'Comment' },
      -- Highlighter with non-string name and callable `extmark_opts` without
      -- `end_row`/`end_col`
      [10] = {
        pattern = 'bbb',
        group = '',
        extmark_opts = function(_, _, data)
          return { virt_text = { { 'xxx', 'Error' } }, virt_text_pos = 'overlay' }
        end,
      },
    },
    delay = _G.test_config.delay,
  })]])

  enable(buf_id_1)
  sleep(test_config.delay.text_change + small_time)
  local matches = get_matches(buf_id_1)

  -- Order should be guaranteed (as tostring(10) is less than 'aaa')
  eq(matches, {
    { bufnr = 2, highlighter = 10, lnum = 1, col = 5 },
    { bufnr = 2, highlighter = 10, lnum = 3, col = 3 },
    { bufnr = 2, highlighter = 'aaa', lnum = 1, col = 1, end_lnum = 1, end_col = 4, hl_group = 'Comment' },
    { bufnr = 2, highlighter = 'aaa', lnum = 2, col = 3, end_lnum = 2, end_col = 6, hl_group = 'Comment' },
  })

  -- Should return empty table if disabled
  disable(buf_id_1)
  eq(get_matches(buf_id_1), {})

  -- Should return empty table if no matches
  enable(buf_id_2)
  sleep(test_config.delay.text_change + small_time)
  eq(get_matches(buf_id_2), {})
end

T['get_matches()']['respects `buf_id` argument'] = function()
  local buf_id = child.api.nvim_get_current_buf()
  child.api.nvim_buf_set_lines(buf_id, 0, -1, false, { 'bbb aaa' })
  child.lua([[require('mini.hipatterns').setup({
    highlighters = {  aaa = { pattern = 'aaa', group = 'Error' }  },
    delay = _G.test_config.delay,
  })]])
  enable(buf_id)
  sleep(test_config.delay.text_change + small_time)

  -- Should allow both `nil` and `0` to mean current buffer
  local ref_output =
    { { bufnr = buf_id, highlighter = 'aaa', hl_group = 'Error', lnum = 1, col = 5, end_lnum = 1, end_col = 8 } }
  eq(get_matches(), ref_output)
  eq(get_matches(0), ref_output)
end

T['get_matches()']['respects `highlighters` argument'] = function()
  local buf_id = child.api.nvim_get_current_buf()
  child.api.nvim_buf_set_lines(buf_id, 0, -1, false, { 'bbb AAA aaa' })
  child.lua([[require('mini.hipatterns').setup({
    highlighters = {
      -- Should respect `pattern` array
      aaa = { pattern = { 'aaa', 'AAA' }, group = 'Error' },
      bbb = { pattern = 'bbb', group = 'Comment' },
    },
    delay = _G.test_config.delay,
  })]])
  enable(buf_id)
  sleep(test_config.delay.text_change + small_time)

  -- Should respect order of `highlighters` in output and discard any not
  -- present highlighter identifiers
  eq(get_matches(buf_id, { 'bbb', 'xxx', 'aaa' }), {
    { bufnr = buf_id, highlighter = 'bbb', hl_group = 'Comment', lnum = 1, col = 1, end_lnum = 1, end_col = 4 },
    { bufnr = buf_id, highlighter = 'aaa', hl_group = 'Error', lnum = 1, col = 5, end_lnum = 1, end_col = 8 },
    { bufnr = buf_id, highlighter = 'aaa', hl_group = 'Error', lnum = 1, col = 9, end_lnum = 1, end_col = 12 },
  })
end

T['get_matches()']['validates arguments'] = function()
  expect.error(function() get_matches('a') end, '`buf_id`.*not valid')
  expect.error(function() get_matches(child.api.nvim_get_current_buf(), 1) end, '`highlighters`.*array')
end

T['gen_highlighter'] = new_set()

T['gen_highlighter']['hex_color()'] = new_set()

local enable_hex_color = function(...)
  child.lua(
    [[_G.hipatterns = require('mini.hipatterns')
      _G.hipatterns.setup({
        highlighters = { hex_color = _G.hipatterns.gen_highlighter.hex_color(...) },
      })]],
    { ... }
  )
  sleep(small_time)
end

T['gen_highlighter']['hex_color()']['works'] = function()
  set_lines({
    -- Should be highlighted
    '#000000 #ffffff',
    '#FffFFf',

    -- Should not be highlighted
    '#00000 #0000000',
    '#00000g',
  })

  enable_hex_color()

  child.expect_screenshot()

  -- Should use correct highlight groups
  --stylua: ignore
  eq(get_hipatterns_extmarks(0), {
    { line = 1, from_col = 1, to_col = 7,  hl_group = 'MiniHipatterns_000000_bg' },
    { line = 1, from_col = 9, to_col = 15, hl_group = 'MiniHipatterns_ffffff_bg' },
    { line = 2, from_col = 1, to_col = 7,  hl_group = 'MiniHipatterns_ffffff_bg' },
  })
  expect.match(child.cmd_capture('hi MiniHipatterns_000000_bg'), 'guifg=#ffffff guibg=#000000')
  expect.match(child.cmd_capture('hi MiniHipatterns_ffffff_bg'), 'guifg=#000000 guibg=#ffffff')
end

T['gen_highlighter']['hex_color()']["works with style '#'"] = function()
  set_lines({ '#000000 #ffffff' })

  enable_hex_color({ style = '#' })

  child.expect_screenshot()

  -- Should use correct highlight groups
  eq(get_hipatterns_extmarks(0), {
    { line = 1, from_col = 1, to_col = 1, hl_group = 'MiniHipatterns_000000_bg' },
    { line = 1, from_col = 9, to_col = 9, hl_group = 'MiniHipatterns_ffffff_bg' },
  })
  expect.match(child.cmd_capture('hi MiniHipatterns_000000_bg'), 'guifg=#ffffff guibg=#000000')
  expect.match(child.cmd_capture('hi MiniHipatterns_ffffff_bg'), 'guifg=#000000 guibg=#ffffff')
end

T['gen_highlighter']['hex_color()']["works with style 'line'"] = function()
  set_lines({ '#000000 #ffffff' })

  enable_hex_color({ style = 'line' })

  child.expect_screenshot()

  -- Should use correct highlight groups
  --stylua: ignore
  eq(get_hipatterns_extmarks(0), {
    { line = 1, from_col = 1, to_col = 7,  hl_group = 'MiniHipatterns_000000_line' },
    { line = 1, from_col = 9, to_col = 15, hl_group = 'MiniHipatterns_ffffff_line' },
  })
  expect.match(child.cmd_capture('hi MiniHipatterns_000000_line'), 'gui=underline guisp=#000000')
  expect.match(child.cmd_capture('hi MiniHipatterns_ffffff_line'), 'gui=underline guisp=#ffffff')
end

T['gen_highlighter']['hex_color()']["works with style 'inline'"] = function()
  if child.fn.has('nvim-0.10') == 0 then
    expect.error(function() enable_hex_color({ style = 'inline' }) end, '"inline".*hex_color.*0%.10')
    return
  end

  child.set_size(5, 25)
  set_lines({ '#000000 #ffffff' })

  enable_hex_color({ style = 'inline' })
  child.expect_screenshot()

  -- Should use correct highlight groups
  expect.match(child.cmd_capture('hi MiniHipatterns_000000_fg'), 'guifg=#000000')
  expect.match(child.cmd_capture('hi MiniHipatterns_ffffff_fg'), 'guifg=#ffffff')
end

T['gen_highlighter']['hex_color()']['correctly computes highlight group'] = function()
  set_lines({ '#767676 #777777', '#098777 #178d7c' })

  enable_hex_color()
  sleep(2 * small_time)

  --stylua: ignore
  eq(get_hipatterns_extmarks(0), {
    { line = 1, from_col = 1, to_col = 7,  hl_group = 'MiniHipatterns_767676_bg' },
    { line = 1, from_col = 9, to_col = 15, hl_group = 'MiniHipatterns_777777_bg' },
    { line = 2, from_col = 1, to_col = 7,  hl_group = 'MiniHipatterns_098777_bg' },
    { line = 2, from_col = 9, to_col = 15, hl_group = 'MiniHipatterns_178d7c_bg' },
  })

  validate_hl_group('MiniHipatterns_767676_bg', 'guifg=#ffffff guibg=#767676')
  validate_hl_group('MiniHipatterns_777777_bg', 'guifg=#000000 guibg=#777777')
  validate_hl_group('MiniHipatterns_098777_bg', 'guifg=#ffffff guibg=#098777')
  validate_hl_group('MiniHipatterns_178d7c_bg', 'guifg=#000000 guibg=#178d7c')
end

T['gen_highlighter']['hex_color()']['is present after color scheme change'] = function()
  set_lines({ '#000000 #ffffff' })
  enable_hex_color()
  sleep(2 * small_time)

  child.cmd('hi clear')
  child.cmd('colorscheme blue')

  sleep(2 * small_time)
  --stylua: ignore
  eq(get_hipatterns_extmarks(0), {
    { line = 1, from_col = 1, to_col = 7,  hl_group = 'MiniHipatterns_000000_bg' },
    { line = 1, from_col = 9, to_col = 15, hl_group = 'MiniHipatterns_ffffff_bg' },
  })
  expect.match(child.cmd_capture('hi MiniHipatterns_000000_bg'), 'guifg=#ffffff guibg=#000000')
  expect.match(child.cmd_capture('hi MiniHipatterns_ffffff_bg'), 'guifg=#000000 guibg=#ffffff')
end

T['gen_highlighter']['hex_color()']['respects `opts.priority`'] = function()
  set_lines({ '#000000', '#000000', '#000000' })
  enable_hex_color()
  sleep(2 * small_time)

  child.expect_screenshot()

  local ns_id = child.api.nvim_create_namespace('test')
  child.cmd('hi Temp guifg=#aaaaaa')
  local set_extmark = function(line, priority)
    child.api.nvim_buf_set_extmark(0, ns_id, line - 1, 0, { end_col = 7, hl_group = 'Temp', priority = priority })
  end

  -- Default priority should be 200
  set_extmark(1, 199)
  set_extmark(3, 201)
  child.expect_screenshot()

  -- Should respect priority in `highlighters` entry
  disable(0)
  enable_hex_color({ priority = 202 })
  child.expect_screenshot()
end

T['gen_highlighter']['hex_color()']['respects `opts.filter`'] = function()
  set_lines({ '#000000 #ffffff' })

  child.lua([[
    _G.hipatterns = require('mini.hipatterns')
    _G.filter = function(buf_id) return vim.b[buf_id].do_highlight end
    _G.hipatterns.enable(0, {
      highlighters = {
        hex_color = _G.hipatterns.gen_highlighter.hex_color({ filter = _G.filter }),
      },
    })
  ]])

  -- Should not highlight
  child.b.do_highlight = false
  update(0)
  child.expect_screenshot()

  -- Should highlight
  child.b.do_highlight = true
  update(0)
  child.expect_screenshot()
end

T['gen_highlighter']['hex_color()']['respects `opts.max_number`'] = function()
  set_lines({ '#000000', '#000001', '#ffffff' })

  child.lua([[
    local hipatterns = require('mini.hipatterns')
    hipatterns.enable(0, {
      highlighters = {
        hex_color = hipatterns.gen_highlighter.hex_color({ max_number = 2 }),
      },
    })
  ]])

  update(0)
  child.expect_screenshot()
end

T['compute_hex_color_group()'] = new_set()

local compute_hex_color_group = forward_lua([[require('mini.hipatterns').compute_hex_color_group]])

T['compute_hex_color_group()']['works'] = function()
  eq(compute_hex_color_group('#000000', 'bg'), 'MiniHipatterns_000000_bg')
  eq(compute_hex_color_group('#ffffff', 'bg'), 'MiniHipatterns_ffffff_bg')
  eq(compute_hex_color_group('#767676', 'bg'), 'MiniHipatterns_767676_bg')
  eq(compute_hex_color_group('#777777', 'bg'), 'MiniHipatterns_777777_bg')
  eq(compute_hex_color_group('#098777', 'bg'), 'MiniHipatterns_098777_bg')
  eq(compute_hex_color_group('#178d7c', 'bg'), 'MiniHipatterns_178d7c_bg')

  validate_hl_group('MiniHipatterns_000000_bg', 'guifg=#ffffff guibg=#000000')
  validate_hl_group('MiniHipatterns_ffffff_bg', 'guifg=#000000 guibg=#ffffff')
  validate_hl_group('MiniHipatterns_767676_bg', 'guifg=#ffffff guibg=#767676')
  validate_hl_group('MiniHipatterns_777777_bg', 'guifg=#000000 guibg=#777777')
  validate_hl_group('MiniHipatterns_098777_bg', 'guifg=#ffffff guibg=#098777')
  validate_hl_group('MiniHipatterns_178d7c_bg', 'guifg=#000000 guibg=#178d7c')

  -- Should use cache per `hex_color` and `style` combination
  eq(compute_hex_color_group('#767676', 'line'), 'MiniHipatterns_767676_line')
  validate_hl_group('MiniHipatterns_767676_line', 'gui=underline guisp=#767676')
end

T['compute_hex_color_group()']['respects `style` argument'] = function()
  eq(compute_hex_color_group('#000000', 'line'), 'MiniHipatterns_000000_line')
  validate_hl_group('MiniHipatterns_000000_line', 'gui=underline guisp=#000000')
  eq(compute_hex_color_group('#aaaaaa', 'fg'), 'MiniHipatterns_aaaaaa_fg')
  validate_hl_group('MiniHipatterns_aaaaaa_fg', 'guifg=#aaaaaa')
end

T['compute_hex_color_group()']['persists after `:colorscheme`'] = function()
  -- Needs `setup()` call to create `ColorScheme` autocommand
  load_module()

  eq(compute_hex_color_group('#000000', 'bg'), 'MiniHipatterns_000000_bg')
  validate_hl_group('MiniHipatterns_000000_bg', 'guifg=#ffffff guibg=#000000')

  child.cmd('colorscheme blue')
  eq(compute_hex_color_group('#000000', 'line'), 'MiniHipatterns_000000_line')
  validate_hl_group('MiniHipatterns_000000_line', 'gui=underline guisp=#000000')
end

T['compute_hex_color_group()']['works if there was an error creating highlight group'] = function()
  child.lua('vim.api.nvim_set_hl = function() error("An unknown error") end')
  eq(compute_hex_color_group('#000000', 'bg'), vim.NIL)
  -- Should not cache as successful creation
  eq(compute_hex_color_group('#000000', 'bg'), vim.NIL)
end

T['compute_hex_color_group()']['respects `opts.max_number`'] = function()
  -- Needs `setup()` call to create `ColorScheme` autocommand
  load_module()

  local validate = function(max_number, hex, ref)
    eq(compute_hex_color_group(hex, 'bg', { max_number = max_number }), ref)
  end

  validate(2, '#000000', 'MiniHipatterns_000000_bg')
  validate(2, '#000001', 'MiniHipatterns_000001_bg')
  validate(2, '#000002', vim.NIL)

  -- Should persist the check
  validate(2, '#000002', vim.NIL)

  -- Should be able to increase `max_number`
  validate(3, '#000002', 'MiniHipatterns_000002_bg')

  -- Should reset on `:colorscheme`
  child.cmd('colorscheme blue')
  validate(2, '#000000', 'MiniHipatterns_000000_bg')
  validate(2, '#000001', 'MiniHipatterns_000001_bg')
  validate(2, '#000002', vim.NIL)

  -- Should count only actually created highlight groups
  child.lua([[
    _G.nvim_set_hl_orig = vim.api.nvim_set_hl
    vim.api.nvim_set_hl = function() error("An unknown error") end
  ]])
  validate(3, '#000002', vim.NIL)
  child.lua('vim.api.nvim_set_hl = _G.nvim_set_hl_orig')
  validate(3, '#000002', 'MiniHipatterns_000002_bg')
end

return T
