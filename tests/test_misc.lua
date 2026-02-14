local helpers = dofile('tests/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

local project_root = vim.fs.normalize(vim.fn.fnamemodify(vim.fn.getcwd(), ':p'))
local dir_misc_path = project_root .. '/tests/dir-misc'

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('misc', config) end
local unload_module = function() child.mini_unload('misc') end
local reload_module = function(config) unload_module(); load_module(config) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local make_path = function(...) return vim.fs.normalize(table.concat({...}, '/')) end
local make_abspath = function(...) return make_path(project_root, ...) end
local getcwd = function() return child.fs.normalize(child.fn.getcwd()) end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local edit = function(x) child.cmd('edit ' .. x) end
local type_keys = function(...) return child.type_keys(...) end
local sleep = function(ms) helpers.sleep(ms, child) end
--stylua: ignore end

local get_filetype = function(buf_id)
  if buf_id == nil or buf_id == 0 then buf_id = child.api.nvim_get_current_buf() end
  return child.api.nvim_get_option_value('filetype', { buf = buf_id })
end

local set_filetype = function(buf_id, value)
  if buf_id == nil or buf_id == 0 then buf_id = child.api.nvim_get_current_buf() end
  return child.api.nvim_set_option_value('filetype', value, { buf = buf_id })
end

-- Time constants
local small_time = helpers.get_time_const(10)
local micro_time = 1
local no_term_response_delay = 1000

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      load_module()
    end,
    post_once = child.stop,
  },
  n_retry = helpers.get_n_retry(1),
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  -- Global variable
  eq(child.lua_get('type(_G.MiniMisc)'), 'table')
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniMisc.config)'), 'table')

  eq(child.lua_get('MiniMisc.config.make_global'), { 'put', 'put_text' })
end

T['setup()']['respects `config` argument'] = function()
  reload_module({ make_global = { 'put' } })
  eq(child.lua_get('MiniMisc.config.make_global'), { 'put' })
end

T['setup()']['validates `config` argument'] = function()
  unload_module()

  local expect_config_error = function(config, name, target_type)
    expect.error(function() load_module(config) end, vim.pesc(name) .. '.*' .. vim.pesc(target_type))
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ make_global = 'a' }, 'make_global', 'table')
  expect_config_error({ make_global = { 'a' } }, 'make_global', "exported 'mini.misc' methods")
end

T['setup()']['creates global functions'] = function()
  eq(child.lua_get('type(_G.put)'), 'function')
  eq(child.lua_get('type(_G.put_text)'), 'function')
end

T['bench_time()'] = new_set({
  hooks = {
    pre_case = function()
      child.lua('_G.small_time = ' .. small_time)
      child.lua('_G.f = function(ms) ms = ms or _G.small_time; vim.loop.sleep(ms); return ms end')
    end,
  },
})

local bench_time = function(...) return unpack(child.lua_get('{ MiniMisc.bench_time(_G.f, ...) }', { ... })) end

-- Validate that benchmark is within tolerable error from target. This is
-- needed due to random nature of benchmarks.
local validate_benchmark = function(time_tbl, target)
  helpers.skip_if_slow()

  local s, n = 0, 0
  for _, x in ipairs(time_tbl) do
    s, n = s + x, n + 1
  end

  local error = 0.2
  eq(n * target * (1 - error) < s, true)
  eq(s < target * (1 + error) * n, true)
end

T['bench_time()']['works'] = function()
  local b, res = bench_time()
  -- By default should run function once
  eq(#b, 1)
  validate_benchmark(b, 0.001 * small_time)
  -- Second value is function output
  eq(res, small_time)
end

T['bench_time()']['respects `n` argument'] = function()
  local b, _ = bench_time(5)
  -- By default should run function once
  eq(#b, 5)
  validate_benchmark(b, 0.001 * small_time)
end

T['bench_time()']['respects `...` as benched time arguments'] = function()
  local b, res = bench_time(1, 5 * small_time)
  validate_benchmark(b, 0.001 * 5 * small_time)
  -- Second value is function output
  eq(res, 5 * small_time)
end

T['get_gutter_width()'] = new_set()

T['get_gutter_width()']['works'] = function()
  -- By default there is no gutter ('sign column')
  eq(child.lua_get('MiniMisc.get_gutter_width()'), 0)

  -- This setting indeed makes gutter with width of two columns
  child.wo.signcolumn = 'yes:1'
  eq(child.lua_get('MiniMisc.get_gutter_width()'), 2)
end

T['get_gutter_width()']['respects `win_id` argument'] = function()
  child.cmd('split')
  local windows = child.api.nvim_list_wins()

  child.api.nvim_win_set_option(windows[1], 'signcolumn', 'yes:1')
  eq(child.lua_get('MiniMisc.get_gutter_width(...)', { windows[2] }), 0)
end

T['log_add()'] = new_set()

local validate_log = function(ref_log)
  local log = child.lua_get('MiniMisc.log_get()')
  eq(#log, #ref_log)

  -- Validate timestamp and non-timestamp data separately
  local log_small, prev_timestamp = {}, 0
  for i, l in ipairs(log) do
    log_small[i] = vim.deepcopy(l)
    log_small[i].timestamp = nil

    eq(type(l.timestamp), 'number')
    eq(prev_timestamp < l.timestamp, true)
    prev_timestamp = l.timestamp
  end
  eq(log_small, ref_log)
end

T['log_add()']['works'] = function()
  child.lua([[
    local t = { a = 1 }
    MiniMisc.log_add('before', t)
    MiniMisc.log_add('before nodeepcopy', t, { deepcopy = false })
    t.a = t.a + 1
    MiniMisc.log_add('after', t)

    MiniMisc.log_add('types 1', { 1, 'text', { x = true } })
    MiniMisc.log_add('types 2', true)
    MiniMisc.log_add('types 3', nil)

    MiniMisc.log_add(1, 'number desc')
    MiniMisc.log_add(nil, 'no desc')
  ]])

  validate_log({
    { desc = 'before', state = { a = 1 } },
    { desc = 'before nodeepcopy', state = { a = 2 } },
    { desc = 'after', state = { a = 2 } },
    { desc = 'types 1', state = { 1, 'text', { x = true } } },
    { desc = 'types 2', state = true },
    { desc = 'types 3' },
    { desc = 1, state = 'number desc' },
    { state = 'no desc' },
  })

  -- Should allow function in log entry
  local fun_in_log = child.lua([[
    MiniMisc.log_add('func 1', function() return 1 end)
    MiniMisc.log_add('func 2', { f = function() return 2 end })

    local log = MiniMisc.log_get()
    return { log[#log - 1].state(), log[#log].state.f() }
  ]])
  eq(fun_in_log, { 1, 2 })

  -- Should properly set timestamps
  child.lua('_G.small_time = ' .. vim.inspect(small_time))
  local diff = child.lua([[
    MiniMisc.log_add('ts 1', 1)
    vim.loop.sleep(10 * _G.small_time)
    MiniMisc.log_add('ts 2', 2)

    local log = MiniMisc.log_get()
    return log[#log].timestamp - log[#log - 1].timestamp
  ]])
  eq((9 * small_time) < diff and diff < (11 * small_time), true)
end

T['log_get()'] = new_set()

T['log_get()']['works'] = function()
  -- Most of the testing is done in tests for other functions
  local log = child.lua([[
    MiniMisc.log_add('desc', { a = 1 })
    return MiniMisc.log_get()
  ]])
  eq(type(log), 'table')
  eq(vim.tbl_count(log), 1)
  local entry_names = vim.tbl_keys(log[1])

  table.sort(entry_names)
  eq(entry_names, { 'desc', 'state', 'timestamp' })

  eq(log[1].desc, 'desc')
  eq(log[1].state, { a = 1 })
  eq(type(log[1].timestamp), 'number')
  eq(log[1].timestamp > 0, true)
end

T['log_show()'] = new_set()

T['log_show()']['works'] = function()
  -- Set up windows
  local buf_id_other = child.api.nvim_get_current_buf()
  local win_id_other = child.api.nvim_get_current_win()
  child.cmd('vert split')
  local win_id = child.api.nvim_get_current_win()

  -- Should start showing log in a new scratch buffer in the current window
  child.lua('MiniMisc.log_add("desc", { a = 1 })')
  child.lua('MiniMisc.log_show()')
  local buf_id_log = child.api.nvim_get_current_buf()
  eq(child.api.nvim_buf_get_name(buf_id_log), 'minimisc://' .. buf_id_log .. '/log')

  local validate_wins = function()
    eq(child.api.nvim_win_get_buf(win_id), buf_id_log)
    eq(child.api.nvim_win_get_buf(win_id_other), buf_id_other)
    eq(child.api.nvim_get_current_win(), win_id)
    eq(buf_id_log == buf_id_other, false)
  end

  local validate_lines = function(ref_lines)
    local log_lines = child.api.nvim_buf_get_lines(buf_id_log, 0, -1, false)
    local mock_ts = 12.33
    for i = 1, #log_lines do
      log_lines[i] = log_lines[i]:gsub('timestamp = %d+%.%d+', function()
        mock_ts = mock_ts + 0.01
        return 'timestamp = ' .. mock_ts
      end)
    end
    eq(log_lines, ref_lines)
  end

  validate_wins()

  local ref_lines = {
    '{ {',
    '    desc = "desc",',
    '    state = {',
    '      a = 1',
    '    },',
    '    timestamp = 12.34',
    '  } }',
  }
  validate_lines(ref_lines)

  -- Should reuse buffer and window
  child.api.nvim_set_current_win(win_id_other)
  child.lua('MiniMisc.log_add("desc", { b = 2 })')
  child.lua('MiniMisc.log_show()')
  validate_wins()

  ref_lines = {
    '{ {',
    '    desc = "desc",',
    '    state = {',
    '      a = 1',
    '    },',
    '    timestamp = 12.34',
    '  }, {',
    '    desc = "desc",',
    '    state = {',
    '      b = 2',
    '    },',
    '    timestamp = 12.35',
    '  } }',
  }
  validate_lines(ref_lines)
end

T['log_clear()'] = new_set()

T['log_clear()']['works'] = function()
  child.lua('_G.notify_log = {}; vim.notify = function(...) table.insert(_G.notify_log, { ... }) end')
  child.lua('_G.small_time = ' .. vim.inspect(small_time))
  local log = child.lua([[
    MiniMisc.log_add('desc 1', 1)
    vim.loop.sleep(10 * _G.small_time)
    MiniMisc.log_add('desc 2', 2)

    MiniMisc.log_clear()
    MiniMisc.log_add('after clear', 3)

    return MiniMisc.log_get()
  ]])

  validate_log({ { desc = 'after clear', state = 3 } })
  -- Should restart start value for timestamps
  eq(log[1].timestamp < small_time, true)

  eq(child.lua_get('_G.notify_log'), { { '(mini.misc) Cleared log' } })
end

local validate_put = {
  put = function(args, reference_output)
    local capture = child.cmd_capture(('lua MiniMisc.put(%s)'):format(args))
    eq(capture, table.concat(reference_output, '\n'))
  end,

  put_text = function(args, reference_output)
    set_lines({})
    child.lua(('MiniMisc.put_text(%s)'):format(args))

    -- Insert text under current line
    table.insert(reference_output, 1, '')
    eq(get_lines(), reference_output)
  end,
}

T['put()/put_text()'] = new_set({
  parametrize = { { 'put' }, { 'put_text' } },
})

T['put()/put_text()']['works'] = function(put_name)
  local validate = validate_put[put_name]

  validate('{ a = 1, b = true }', { '{', '  a = 1,', '  b = true', '}' })
end

T['put()/put_text()']['allows several arguments'] = function(put_name)
  local validate = validate_put[put_name]

  child.lua('_G.a = 1; _G.b = true')
  validate('_G.a, _G.b', { '1', 'true' })
end

T['put()/put_text()']['handles tuple function output'] = function(put_name)
  local validate = validate_put[put_name]

  child.lua('_G.f = function() return 1, true end')
  validate('_G.f()', { '1', 'true' })
end

T['put()/put_text()']['prints `nil` values'] = function(put_name)
  local validate = validate_put[put_name]

  validate('nil', { 'nil' })
  validate('1, nil', { '1', 'nil' })
  validate('nil, 2', { 'nil', '2' })
  validate('1, nil, 2', { '1', 'nil', '2' })
end

local resize_initial_width, resize_win_id
T['resize_window()'] = new_set({
  hooks = {
    pre_case = function()
      -- Prepare two windows
      resize_initial_width = child.api.nvim_win_get_width(0)
      child.cmd('vsplit')
      resize_win_id = child.api.nvim_list_wins()[1]
    end,
  },
})

T['resize_window()']['works'] = function()
  local target_width = math.floor(0.25 * resize_initial_width)
  -- This sets gutter width to 4
  child.api.nvim_win_set_option(resize_win_id, 'signcolumn', 'yes:2')

  child.lua('MiniMisc.resize_window(...)', { resize_win_id, target_width })
  eq(child.api.nvim_win_get_width(resize_win_id), target_width + 4)
end

T['resize_window()']['correctly computes default `text_width` argument'] = function()
  child.wo.signcolumn = 'yes:2'

  -- min(vim.o.columns, 79) < textwidth < colorcolumn
  child.o.columns = 160
  child.lua('MiniMisc.resize_window(0)')
  eq(child.api.nvim_win_get_width(0), 79 + 4)

  child.o.columns = 60
  child.lua('MiniMisc.resize_window(0)')
  -- Should set to maximum available width, which is less than `columns` by 1
  -- (window separator) and 'winminwidth'
  eq(child.api.nvim_win_get_width(0), 60 - 1 - child.o.winminwidth)

  child.bo.textwidth = 50
  child.lua('MiniMisc.resize_window(0)')
  eq(child.api.nvim_win_get_width(0), 50 + 4)

  child.wo.colorcolumn = '+2,-2'
  child.lua('MiniMisc.resize_window(0)')
  eq(child.api.nvim_win_get_width(0), 52 + 4)

  child.wo.colorcolumn = '-2,+2'
  child.lua('MiniMisc.resize_window(0)')
  eq(child.api.nvim_win_get_width(0), 48 + 4)

  child.wo.colorcolumn = '40,-2'
  child.lua('MiniMisc.resize_window(0)')
  eq(child.api.nvim_win_get_width(0), 40 + 4)
end

T['safely()'] = new_set({
  hooks = {
    pre_case = function()
      -- Create a log to track execution
      child.lua('_G.log = {}')

      -- Mock `vim.notify()`
      child.lua([[
        _G.notify_log = {}
        local inverse_levels = {}
        for k, v in pairs(vim.log.levels) do
          inverse_levels[v] = k
        end
        vim.notify = function(msg, lvl, opts)
          table.insert(_G.notify_log, { msg, inverse_levels[lvl], opts })
        end
      ]])
    end,
  },
})

local safely = function(when, f_string)
  local lua_cmd = string.format('MiniMisc.safely(%s, %s)', vim.inspect(when), f_string)
  child.lua(lua_cmd)
end

local validate_notify_log = function(ref_log)
  local log = child.lua_get('_G.notify_log')
  eq(#log, #ref_log)
  for i = 1, #log do
    -- Validate notification message by pattern matching
    expect.match(log[i][1], ref_log[i][1])
    eq(log[i][2], ref_log[i][2])
    eq(log[i][3], ref_log[i][3])
  end

  child.lua('_G.notify_log = {}')
end

local validate_log = function(ref_log)
  eq(child.lua_get('_G.log'), ref_log)
  child.lua('_G.log = {}')
end

-- Helper for populating functions that use `safely` to test proper traceback
local populate_nested_funs = function(safely_when)
  child.lua('_G.safely_when = ' .. vim.inspect(safely_when))
  child.lua([[
    _G.inner_fun = function(arg) error('My custom error') end
    _G.outer_fun = function()
      MiniMisc.safely(_G.safely_when, function(...)
        table.insert(_G.log, { _G.safely_when, ... }); _G.inner_fun()
      end)
    end
  ]])
end

T['safely()']['works with "now"'] = function()
  populate_nested_funs('now')
  child.lua([[
    _G.outer_fun()
    table.insert(_G.log, 'Should be still executed')
  ]])

  -- Should execute, report error as a warning with useful traceback
  validate_notify_log({ { 'My custom error.*inner_fun.*safely.*outer_fun', 'WARN' } })

  -- Should not block next code
  validate_log({ { 'now' }, 'Should be still executed' })
end

T['safely()']['works with "later"'] = function()
  populate_nested_funs('later')
  child.lua([[
    _G.outer_fun()
    table.insert(_G.log, 'Should be executed first')
  ]])

  sleep(micro_time)

  validate_notify_log({ { 'My custom error.*inner_fun.*safely.*outer_fun', 'WARN' } })
  validate_log({ 'Should be executed first', { 'later' } })
end

T['safely()']['clears "later" queue between different event loops'] = function()
  child.lua([[
    _G.f = function() table.insert(_G.log, 'later') end
    MiniMisc.safely('later', _G.f)
    _G.immediate_log = vim.deepcopy(_G.log)
  ]])
  eq(child.lua_get('_G.immediate_log'), {})
  sleep(micro_time)
  validate_log({ 'later' })

  child.lua('MiniMisc.safely("later", _G.f)')
  sleep(2 * micro_time)
  -- If it did not clear the queue, it would have been 2 new elements
  validate_log({ 'later' })
end

T['safely()']['works with "delay"'] = function()
  local delay = 5 * small_time
  populate_nested_funs('delay:' .. delay)
  child.lua('_G.outer_fun()')

  sleep(delay - small_time)
  validate_notify_log({})
  sleep(2 * small_time)
  validate_notify_log({ { 'My custom error.*inner_fun.*safely.*outer_fun', 'WARN' } })
  validate_log({ { 'delay:' .. delay } })
end

T['safely()']['works with "event" without patterns'] = function()
  populate_nested_funs('event:InsertEnter,CmdlineEnter')
  child.lua('_G.outer_fun()')
  validate_notify_log({})

  -- Should execute exactly once on whichever event triggers first
  type_keys('i')
  validate_notify_log({ { 'My custom error.*inner_fun.*safely.*outer_fun', 'WARN' } })
  validate_log({ { 'event:InsertEnter,CmdlineEnter' } })

  type_keys('<Esc>', ':')
  validate_notify_log({})

  -- Should not block triggering other events (even nested) inside callback
  child.lua([[
    _G.log = {}
    vim.cmd('au BufEnter * lua table.insert(_G.log, "BufEnter")')
    vim.cmd('au FileType * lua table.insert(_G.log, vim.bo.filetype)')
    vim.cmd('au User Test lua table.insert(_G.log, "Test")')
    MiniMisc.safely('event:BufEnter', function()
      vim.bo.filetype = 'my-filetype'
      vim.api.nvim_exec_autocmds('User', { pattern = 'Test' })

      -- Although triggers `BufEnter`, should *not* execute this function
      vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(false, true))
    end)
  ]])
  local buf_id = child.api.nvim_create_buf(false, true)
  validate_log({})
  child.api.nvim_set_current_buf(buf_id)
  validate_log({ 'BufEnter', 'my-filetype', 'Test', 'BufEnter' })
end

T['safely()']['works with "event" with patterns'] = function()
  local setup = function(when)
    populate_nested_funs(when)
    child.lua('_G.outer_fun()')
    validate_notify_log({})
  end

  -- Should execute exactly once on whichever combo triggers first
  local when_cmdline = 'event:CmdlineEnter,CmdlineLeave~:,/'
  setup(when_cmdline)
  type_keys(':')
  validate_notify_log({ { 'My custom error.*inner_fun.*safely.*outer_fun', 'WARN' } })
  validate_log({ { when_cmdline } })
  type_keys('<Esc>')
  validate_notify_log({})
  validate_log({})

  setup(when_cmdline)
  type_keys('/')
  validate_notify_log({ { 'My custom error.*inner_fun.*safely.*outer_fun', 'WARN' } })
  validate_log({ { when_cmdline } })
  type_keys('<Esc>')
  validate_notify_log({})
  validate_log({})

  -- Order of events in `when` should not matter
  local when_cmdline_2 = 'event:CmdlineLeave,CmdlineEnter~/,:'
  setup(when_cmdline_2)
  type_keys(':')
  validate_notify_log({ { 'My custom error.*inner_fun.*safely.*outer_fun', 'WARN' } })
  validate_log({ { when_cmdline_2 } })
  type_keys('<Esc>')
  validate_notify_log({})
  validate_log({})
end

T['safely()']['works with "filetype"'] = function()
  populate_nested_funs('filetype:aaa,bbb')
  child.lua('_G.outer_fun()')
  validate_notify_log({})

  local buf_id = child.api.nvim_create_buf(false, true)
  child.api.nvim_set_current_buf(buf_id)
  validate_notify_log({})

  -- Should execute exactly once and only on relevant filetypes
  child.bo.filetype = 'xxx'
  validate_notify_log({})

  child.bo.filetype = 'aaa'
  validate_notify_log({ { 'My custom error.*inner_fun.*safely.*outer_fun', 'WARN' } })
  validate_log({ { 'filetype:aaa,bbb' } })

  child.bo.filetype = 'bbb'
  validate_notify_log({})
  validate_log({})
end

T['safely()']['with "filetype" redetects filetype'] = function()
  edit(make_path(dir_misc_path, 'lang.aaa'))
  child.bo.filetype = 'aaa'
  local buf_aaa_1 = child.api.nvim_get_current_buf()

  edit(make_path(dir_misc_path, 'dir', 'lang.aaa'))
  child.bo.filetype = 'aaa'
  local buf_aaa_2 = child.api.nvim_get_current_buf()

  edit(make_path(dir_misc_path, 'dir', 'subdir', 'lang.aaa'))
  local buf_lang_aaa = child.api.nvim_get_current_buf()
  -- As file name matches 'ftdetect', it should be redetected even if filetype
  -- does not match one from `when`
  child.bo.filetype = 'xxx'

  edit('not-aaa')
  local buf_not_aaa = child.api.nvim_get_current_buf()
  child.bo.filetype = 'yyy'

  -- Should redetect in current and non-current loaded buffers
  child.api.nvim_buf_delete(buf_aaa_1, { unload = true })
  eq(child.api.nvim_buf_is_loaded(buf_aaa_1), false)

  child.o.packpath = child.o.packpath .. ',' .. dir_misc_path
  child.lua('MiniMisc.safely("filetype:aaa", function() vim.cmd("packadd mocked-lang-plugin") end)')

  edit(make_path(dir_misc_path, 'dir', 'subdir-2', 'lang.aaa'))
  local buf_aaa_3 = child.api.nvim_get_current_buf()
  eq(child.lua_get('_G.lang_plugin_ftdetect'), vim.NIL)

  child.bo.filetype = 'aaa'
  eq(child.lua_get('_G.lang_plugin_ftdetect'), { 'ftdetect/aaa.lua' })

  eq(child.api.nvim_buf_is_loaded(buf_aaa_1), false)
  eq(get_filetype(buf_aaa_2), 'lang-aaa')
  eq(child.bo.filetype, 'lang-aaa')

  eq(get_filetype(buf_lang_aaa), 'lang-aaa')

  eq(get_filetype(buf_not_aaa), 'yyy')

  -- Should also source proper ftplugins after redetection
  local ref_ftplugin_history = {
    [tostring(buf_aaa_2)] = true,
    [tostring(buf_lang_aaa)] = true,
    [tostring(buf_aaa_3)] = true,
    ['ftplugin/lang-aaa.lua'] = 3,
  }
  eq(child.lua_get('_G.lang_plugin_ftplugin'), ref_ftplugin_history)
end

T['safely()']['with "filetype" resources filetype scripts'] = function()
  local buf_aaa_1 = child.api.nvim_create_buf(true, false)
  set_filetype(buf_aaa_1, 'aaa')
  child.api.nvim_buf_delete(buf_aaa_1, { unload = true })
  eq(child.api.nvim_buf_is_loaded(buf_aaa_1), false)

  local buf_aaa_2 = child.api.nvim_create_buf(true, false)
  set_filetype(buf_aaa_2, 'aaa')

  local buf_not_aaa = child.api.nvim_create_buf(true, false)
  set_filetype(buf_not_aaa, 'xxx')

  child.o.packpath = child.o.packpath .. ',' .. dir_misc_path
  child.lua('MiniMisc.safely("filetype:aaa", function() vim.cmd("packadd mocked-lang-plugin") end)')

  local buf_aaa_3 = child.api.nvim_create_buf(true, false)
  eq(child.lua_get('_G.lang_plugin_ftplugin'), vim.NIL)

  set_filetype(buf_aaa_3, 'aaa')
  local ref_ftplugin_history = {
    [tostring(buf_aaa_2)] = true,
    [tostring(buf_aaa_3)] = true,
    ['ftplugin/aaa.lua'] = 2,
  }
  eq(child.lua_get('_G.lang_plugin_ftplugin'), ref_ftplugin_history)

  eq(child.api.nvim_buf_is_loaded(buf_aaa_1), false)
  eq(get_filetype(buf_aaa_2), 'aaa')
  eq(get_filetype(buf_aaa_3), 'aaa')
  eq(get_filetype(buf_not_aaa), 'xxx')
end

T['safely()']['with "filetype" skips redetect if no filetype detection'] = function()
  child.cmd('filetype off')

  child.o.packpath = child.o.packpath .. ',' .. dir_misc_path
  child.lua('MiniMisc.safely("filetype:aaa", function() vim.cmd("packadd mocked-lang-plugin") end)')

  local buf_aaa_1 = child.api.nvim_create_buf(true, false)
  set_filetype(buf_aaa_1, 'aaa')
  eq(child.lua_get('_G.lang_plugin_ftdetect'), vim.NIL)
  eq(child.lua_get('_G.lang_plugin_ftplugin'), vim.NIL)
end

T['safely()']['with "filetype" skips redetect if function errored'] = function()
  child.o.packpath = child.o.packpath .. ',' .. dir_misc_path
  child.lua([[MiniMisc.safely("filetype:aaa", function()
    vim.cmd("packadd mocked-lang-plugin")
    error('Unexpected error after adding a plugin')
  end)]])

  edit(make_path(dir_misc_path, 'lang.aaa'))
  set_filetype(0, 'aaa')

  -- 'ftdetect/' scripts are run by `:packadd`, but their rules should not be
  -- re-applied on existing buffers (even if filetype matches)
  eq(child.lua_get('_G.lang_plugin_ftdetect'), { 'ftdetect/aaa.lua' })
  eq(get_filetype(0), 'aaa')

  eq(child.lua_get('_G.lang_plugin_ftplugin'), vim.NIL)
end

T['safely()']['can be nested'] = function()
  local delay = 5 * small_time
  child.lua('_G.delay = ' .. delay)
  child.lua([[
    MiniMisc.safely('now', function()
      table.insert(_G.log, 'now 1')

      MiniMisc.safely('delay:' .. _G.delay, function() table.insert(_G.log, 'delay 1') end)
      MiniMisc.safely('event:User~Test', function() table.insert(_G.log, 'event 1') end)
      MiniMisc.safely('filetype:aaa', function() table.insert(_G.log, 'filetype 1') end)

      MiniMisc.safely('now', function()
        vim.api.nvim_exec_autocmds('User', { pattern = 'Test' })
        table.insert(_G.log, 'now 2')
      end)

      MiniMisc.safely('later', function()
        table.insert(_G.log, 'later 1')

        MiniMisc.safely('later', function()
          table.insert(_G.log, 'later 2')
          vim.bo.filetype = 'aaa'
        end)
        MiniMisc.safely('now', function() table.insert(_G.log, 'now 3') end)
      end)
    end)
  ]])

  sleep(delay + small_time)
  validate_log({ 'now 1', 'event 1', 'now 2', 'later 1', 'now 3', 'later 2', 'filetype 1', 'delay 1' })
end

T['safely()']['validates input'] = function()
  expect.error(function() safely(1, 'function() end') end, '`when`.*string')
  expect.error(function() safely('xxx', 'function() end') end, 'Could not parse `when`')
  expect.error(function() safely('now', '1') end, '`f`.*callable')
end

local git_repo_path = make_abspath('tests/dir-misc/mocked-git-repo')
local git_path = make_abspath('tests/dir-misc/mocked-git-repo/.git')
local test_file_makefile = make_abspath('tests/dir-misc/aaa.lua')
local test_file_git = make_abspath('tests/dir-misc/mocked-git-repo/bbb.lua')

local init_mock_git = function(git_type)
  if git_type == 'file' then
    -- File '.git' is used inside submodules
    child.fn.writefile({ '' }, git_path)
  else
    child.fn.mkdir(git_path)
  end
end

local cleanup_mock_git = function() child.fn.delete(git_path, 'rf') end

T['setup_auto_root()'] = new_set({ hooks = { post_case = cleanup_mock_git } })

local setup_auto_root = function(...) child.lua('MiniMisc.setup_auto_root(...)', { ... }) end

T['setup_auto_root()']['works'] = function()
  eq(getcwd(), project_root)
  child.o.autochdir = true

  setup_auto_root()

  -- Resets 'autochdir'
  eq(child.o.autochdir, false)

  -- Creates autocommand
  eq(child.lua_get([[#vim.api.nvim_get_autocmds({ group = 'MiniMiscAutoRoot' })]]) > 0, true)

  -- Respects 'Makefile'
  child.cmd('edit ' .. test_file_makefile)
  eq(getcwd(), dir_misc_path)

  -- Respects '.git' directory and file
  for _, git_type in ipairs({ 'directory', 'file' }) do
    init_mock_git(git_type)
    child.cmd('edit ' .. test_file_git)
    eq(getcwd(), git_repo_path)
    cleanup_mock_git()
  end
end

T['setup_auto_root()']['validates input'] = function()
  expect.error(function() setup_auto_root('a') end, '`names`.*array')
  expect.error(function() setup_auto_root({ 1 }) end, '`names`.*string')
  expect.error(function() setup_auto_root({ '.git' }, 1) end, '`fallback`.*callable')
end

T['setup_auto_root()']['respects `names` argument'] = function()
  init_mock_git('directory')
  setup_auto_root({ 'Makefile' })

  -- Should not stop on git repo directory, but continue going up
  child.cmd('edit ' .. test_file_git)
  eq(getcwd(), dir_misc_path)
end

T['setup_auto_root()']['allows callable `names`'] = function()
  init_mock_git('directory')
  child.lua([[_G.find_aaa = function(x) return x == 'aaa.lua' end]])
  child.lua('MiniMisc.setup_auto_root(_G.find_aaa)')

  -- Should not stop on git repo directory, but continue going up
  child.cmd('edit ' .. test_file_git)
  eq(child.lua_get('MiniMisc.find_root(0, _G.find_aaa)'), dir_misc_path)
  eq(getcwd(), dir_misc_path)
end

T['setup_auto_root()']['respects `fallback` argument'] = function()
  -- Should return and cache fallback result if not found root by going up
  -- NOTE: More tests are done in `find_root()`
  local lua_cmd = string.format(
    [[MiniMisc.setup_auto_root({ 'non-existing' }, function(path) _G.path_arg = path; return %s end)]],
    vim.inspect(dir_misc_path)
  )
  child.lua(lua_cmd)

  child.cmd('edit ' .. test_file_git)
  eq(child.lua_get('_G.path_arg'), child.fs.normalize(child.api.nvim_buf_get_name(0)))
  eq(getcwd(), dir_misc_path)
end

T['setup_auto_root()']['works in buffers without path'] = function()
  setup_auto_root()

  local scratch_buf_id = child.api.nvim_create_buf(false, true)

  local cur_dir = getcwd()
  child.api.nvim_set_current_buf(scratch_buf_id)
  eq(getcwd(), cur_dir)
end

T['setup_auto_root()']['works only for current buffer'] = function()
  setup_auto_root()
  init_mock_git('file')

  child.lua('_G.log = {}')
  child.lua('_G.path_1 = ' .. vim.inspect(test_file_makefile))
  child.lua('_G.path_2 = ' .. vim.inspect(test_file_git))
  child.cmd('autocmd DirChanged * lua table.insert(_G.log, vim.fn.getcwd())')

  child.lua([[
    vim.cmd('edit ' .. vim.fn.fnameescape(_G.path_1))
    local buf_id_1 = vim.api.nvim_get_current_buf()
    vim.cmd('edit ' .. vim.fn.fnameescape(_G.path_2))
    vim.api.nvim_buf_delete(buf_id_1, { force = true })
  ]])
  local log = vim.tbl_map(child.fs.normalize, child.lua_get('_G.log'))
  eq(log, { git_repo_path })
  eq(child.cmd_capture('messages'), '')
end

T['setup_auto_root()']['triggers nested autocommands'] = function()
  setup_auto_root()
  child.cmd('au DirChanged * lua _G.hello = "world"')
  child.cmd('edit ' .. test_file_makefile)
  eq(child.lua_get('_G.hello'), 'world')
end

T['find_root()'] = new_set({ hooks = { post_case = cleanup_mock_git } })

local find_root = function(...) return child.lua_get('MiniMisc.find_root(...)', { ... }) end

T['find_root()']['works'] = function()
  -- Respects 'Makefile'
  child.cmd('edit ' .. test_file_makefile)
  eq(find_root(), dir_misc_path)
  child.cmd('%bwipeout')

  -- Respects '.git' directory and file
  for _, git_type in ipairs({ 'directory', 'file' }) do
    init_mock_git(git_type)
    child.cmd('edit ' .. test_file_git)
    eq(find_root(), git_repo_path)
    child.cmd('%bwipeout')
    cleanup_mock_git()
  end
end

T['find_root()']['validates arguments'] = function()
  expect.error(function() find_root('a') end, '`buf_id`.*buffer id')
  expect.error(function() find_root(-1) end, '`buf_id`.*buffer id')
  expect.error(function() find_root(0, 1) end, '`names`.*string')
  expect.error(function() find_root(0, '.git') end, '`names`.*array')
  expect.error(function() find_root(0, { '.git' }, 1) end, '`fallback`.*callable')
end

T['find_root()']['respects `buf_id` argument'] = function()
  init_mock_git('directory')

  child.cmd('edit ' .. test_file_makefile)
  local init_buf_id = child.api.nvim_get_current_buf()
  child.cmd('edit ' .. test_file_git)
  eq(child.api.nvim_get_current_buf() ~= init_buf_id, true)

  eq(find_root(init_buf_id), dir_misc_path)
end

T['find_root()']['respects `names` argument'] = function()
  init_mock_git('directory')

  -- Should not stop on git repo directory, but continue going up
  child.cmd('edit ' .. test_file_git)
  eq(find_root(0, { 'aaa.lua' }), dir_misc_path)
end

T['find_root()']['allows callable `names`'] = function()
  init_mock_git('directory')
  child.cmd('edit ' .. test_file_git)

  child.lua([[_G.find_aaa = function(x) return x == 'aaa.lua' end]])
  eq(child.lua_get('MiniMisc.find_root(0, _G.find_aaa)'), dir_misc_path)
end

T['find_root()']['respects `fallback` argument'] = function()
  local validate = function(fallback_output, ref)
    local lua_cmd = string.format(
      [[MiniMisc.find_root(
        0,
        { 'non-existing' },
        function(path) _G.path_arg = path; return %s end
      )]],
      vim.inspect(fallback_output)
    )
    eq(child.lua_get(lua_cmd), ref)

    -- Fallback should be called with buffer path
    eq(child.lua_get('_G.path_arg'), child.fs.normalize(child.api.nvim_buf_get_name(0)))

    -- Cleanup
    child.lua('_G.path_arg = nil')
  end

  child.cmd('edit ' .. test_file_git)

  -- Should handle incorrect fallback return without setting it to cache
  validate(nil, vim.NIL)
  validate(1, vim.NIL)
  validate('non-existing', vim.NIL)

  -- Should return and cache fallback result if not found root by going up
  validate(dir_misc_path, dir_misc_path)

  local after_cache = child.lua_get([[MiniMisc.find_root(0, { 'non-existing' }, function() _G.been_here = true end)]])
  eq(after_cache, dir_misc_path)
  eq(child.lua_get('_G.been_here'), vim.NIL)
end

T['find_root()']['works in buffers without path'] = function()
  local scratch_buf_id = child.api.nvim_create_buf(false, true)
  child.api.nvim_set_current_buf(scratch_buf_id)
  eq(find_root(), vim.NIL)
end

T['find_root()']['uses cache'] = function()
  child.cmd('edit ' .. test_file_git)
  -- Returns root based on 'Makefile' as there is no git root
  eq(find_root(), dir_misc_path)

  -- Later creation of git root should not affect output as it should be cached
  -- from first call
  init_mock_git('directory')
  eq(find_root(), dir_misc_path)
end

T['setup_termbg_sync()'] = new_set({
  hooks = {
    pre_case = function()
      if child.fn.has('nvim-0.10') == 0 then MiniTest.skip('`setup_termbg_sync()` works only on Neovim>=0.10') end

      child.lua([[
        -- Mock `io.stdout:write` used to send control sequences to terminal emulator
        _G.log = {}
        io.stdout = { write = function(self, ...) table.insert(_G.log, { ... }) end }

        -- Mock attached UI
        vim.api.nvim_list_uis = function() return { { stdout_tty = true } } end
      ]])
    end,
  },
})

local validate_termbg_augroup = function(ref)
  local has_augroup = pcall(child.api.nvim_get_autocmds, { group = 'MiniMiscTermbgSync', event = 'TermResponse' })
  eq(has_augroup, ref)
end

T['setup_termbg_sync()']['works'] = new_set(
  -- Neovim=0.10 uses string sequence as response, while Neovim>=0.11 sets it
  -- in `sequence` table field
  { parametrize = { { '\027]11;rgb:1111/2626/2d2d' }, { { sequence = '\027]11;rgb:1111/2626/2d2d' } } } },
  {
    test = function(response_data)
      local eq_log = function(ref_log)
        eq(child.lua_get('_G.log'), ref_log)
        child.lua('_G.log = {}')
      end

      child.cmd('hi Normal guifg=#222222 guibg=#dddddd')
      child.lua('MiniMisc.setup_termbg_sync()')

      -- Should first ask if terminal emulator supports the feature
      eq_log({ { '\027]11;?\007' } })

      -- Mock typical response assuming '#11262d' as background color
      child.api.nvim_exec_autocmds('TermResponse', { data = response_data })

      -- Should sync immediately
      eq_log({ { '\027]11;#dddddd\007' } })

      -- Should sync on appropriate events
      local validate_event = function(event, log_entry)
        child.api.nvim_exec_autocmds(event, {})
        eq_log({ { log_entry } })
      end
      validate_event('VimResume', '\027]11;#dddddd\007')
      validate_event('ColorScheme', '\027]11;#dddddd\007')
      validate_event('VimLeavePre', '\027]111\027\\')
      validate_event('VimSuspend', '\027]111\027\\')
    end,
  }
)

T['setup_termbg_sync()']['can be called multiple times'] = function()
  child.cmd('hi Normal guifg=#222222 guibg=#dddddd')
  child.lua('MiniMisc.setup_termbg_sync()')
  child.api.nvim_exec_autocmds('TermResponse', { data = '\027]11;rgb:1111/2626/2d2d' })
  eq(child.lua_get('_G.log'), { { '\027]11;?\a' }, { '\027]11;#dddddd\a' } })
  child.lua('_G.log = {}')

  -- If called second time, the terminal background color is already synced
  child.lua('MiniMisc.setup_termbg_sync()')
  child.api.nvim_exec_autocmds('TermResponse', { data = '\027]11;rgb:dddd/dddd/dddd' })
  eq(child.lua_get('_G.log'), { { '\027]11;?\a' }, { '\027]11;#dddddd\a' } })
  child.lua('_G.log = {}')

  -- Should reset to the color from the very first call
  child.api.nvim_exec_autocmds('VimLeavePre', {})
  eq(child.lua_get('_G.log'), { { '\027]111\027\\' } })
end

T['setup_termbg_sync()']['does nothing if there is no proper stdout'] = function()
  local validate = function()
    child.lua('MiniMisc.setup_termbg_sync()')
    child.api.nvim_create_augroup('MiniMiscTermbgSync', { clear = false })
    eq(child.lua_get('#vim.api.nvim_get_autocmds({ group = "MiniMiscTermbgSync" })'), 0)
  end

  -- No UI
  child.lua('vim.api.nvim_list_uis = function() return {} end')
  validate()

  -- UI without stdout (like GUI)
  child.lua('vim.api.nvim_list_uis = function() return { { stdout_tty = false } } end')
  validate()
end

T['setup_termbg_sync()']['handles no response from terminal emulator'] = function()
  child.lua('_G.notify_log = {}; vim.notify = function(...) table.insert(_G.notify_log, { ... }) end')
  child.lua('MiniMisc.setup_termbg_sync()')
  validate_termbg_augroup(true)

  -- If there is no response from terminal emulator for 1s, delete autocmd
  child.loop.sleep(no_term_response_delay + small_time)
  validate_termbg_augroup(false)

  -- Should show informative notification
  local ref_notify = {
    '(mini.misc) `setup_termbg_sync()` did not get proper response from terminal emulator',
    child.lua_get('vim.log.levels.WARN'),
  }
  eq(child.lua_get('_G.notify_log'), { ref_notify })
end

T['setup_termbg_sync()']['handles bad response from terminal emulator'] = function()
  child.lua('_G.notify_log = {}; vim.notify = function(...) table.insert(_G.notify_log, { ... }) end')
  child.lua('MiniMisc.setup_termbg_sync()')

  -- Should not delete augroup/autocommand or show notification yet, because
  -- proper response might comer later
  child.api.nvim_exec_autocmds('TermResponse', { data = 'something-bad' })
  validate_termbg_augroup(true)
  eq(child.lua_get('_G.notify_log'), {})

  child.api.nvim_exec_autocmds('TermResponse', { data = 'other-bad' })
  validate_termbg_augroup(true)
  eq(child.lua_get('_G.notify_log'), {})

  -- After timeout delay it should cleanup and show all bad responses
  child.loop.sleep(no_term_response_delay + small_time)
  validate_termbg_augroup(false)
  local ref_notify = {
    '(mini.misc) `setup_termbg_sync()` did not get proper response from terminal emulator,'
      .. ' only these: { "something-bad", "other-bad" }',
    child.lua_get('vim.log.levels.WARN'),
  }
  eq(child.lua_get('_G.notify_log'), { ref_notify })
end

T['setup_termbg_sync()']['handles parallel unrelated `TermResponse` events'] = function()
  child.lua('_G.notify_log = {}; vim.notify = function(...) table.insert(_G.notify_log, { ... }) end')
  child.lua('MiniMisc.setup_termbg_sync()')

  local validate_n_termresponse = function(ref_n)
    eq(#child.api.nvim_get_autocmds({ group = 'MiniMiscTermbgSync', event = 'TermResponse' }), ref_n)
  end

  -- After receiving bad response should still wait for possible proper one
  child.api.nvim_exec_autocmds('TermResponse', { data = 'something-bad' })
  validate_termbg_augroup(true)
  validate_n_termresponse(1)
  eq(child.lua_get('_G.notify_log'), {})

  -- After receiving proper response should immediately stop waiting for it and
  -- set up proper `termbg` autocommands
  local seq = '\027]11;rgb:1111/2626/2d2d'
  local data = child.fn.has('nvim-0.11') == 1 and { sequence = seq } or seq
  child.api.nvim_exec_autocmds('TermResponse', { data = data })
  validate_termbg_augroup(true)
  validate_n_termresponse(0)
  eq(#child.api.nvim_get_autocmds({ group = 'MiniMiscTermbgSync' }) > 0, true)
  eq(child.lua_get('_G.notify_log'), {})
end

T['setup_termbg_sync()']['handles different color formats'] = function()
  local validate = function(term_response_color)
    -- Mock clean start to overcome that color is parsed only once per session
    child.lua('package.loaded["mini.misc"] = nil')
    child.lua('require("mini.misc").setup_termbg_sync()')
    child.api.nvim_exec_autocmds('TermResponse', { data = '\027]11;' .. term_response_color })

    -- Should properly parse initial background and use it to reset on exit
    child.lua('_G.log = {}')
    child.api.nvim_exec_autocmds('VimLeavePre', {})
    eq(child.lua_get('_G.log'), { { '\027]111\027\\' } })

    -- Clean up
    child.lua('_G.log = {}')
    child.api.nvim_create_augroup('MiniMiscTermbgSync', { clear = true })
  end

  validate('rgb:1234/5678/9abc', '#12569a')
  validate('rgb:213/546/879', '#215487')
  validate('rgb:31/75/b9', '#3175b9')
  validate('rgb:4/8/c', '#4488cc')
  validate('rgb:1/23/456', '#112345')

  validate('rgba:1234/5678/9abc/1234', '#12569a')
  validate('rgba:213/546/879/1234', '#215487')
  validate('rgba:31/75/b9/1234', '#3175b9')
  validate('rgba:4/8/c/1234', '#4488cc')
  validate('rgba:1/23/456/1234', '#112345')
end

T['setup_termbg_sync()']['handles transparent `Normal` background'] = function()
  child.cmd('hi Normal guifg=#222222 guibg=#dddddd')
  child.lua('MiniMisc.setup_termbg_sync()')
  child.api.nvim_exec_autocmds('TermResponse', { data = '\027]11;rgb:1111/2626/2d2d' })
  child.lua('_G.log = {}')

  -- When syncing with "transparent" `Normal`, should restore the original
  -- terminal background
  child.cmd('hi Normal guifg=#222222 guibg=NONE')
  child.api.nvim_exec_autocmds('ColorScheme', {})
  eq(child.lua_get('_G.log'), { { '\027]111\027\\' } })
end

T['setup_termbg_sync()']['respects `opts.explicit_reset`'] = function()
  child.cmd('hi Normal guifg=#222222 guibg=#dddddd')
  child.lua('MiniMisc.setup_termbg_sync({ explicit_reset = true })')
  child.api.nvim_exec_autocmds('TermResponse', { data = '\027]11;rgb:1111/2626/2d2d' })
  child.lua('_G.log = {}')

  -- Should still sync on appropriate events
  local validate_event = function(event, log_entry)
    child.api.nvim_exec_autocmds(event, {})
    eq(child.lua_get('_G.log'), { { log_entry } })
    child.lua('_G.log = {}')
  end
  validate_event('VimResume', '\027]11;#dddddd\007')
  validate_event('ColorScheme', '\027]11;#dddddd\007')
  -- - Should reset by setting initial color explicitly
  validate_event('VimLeavePre', '\027]11;#11262d\007')
  validate_event('VimSuspend', '\027]11;#11262d\007')

  -- Should reset with explicit bg color on transparent `Normal` background
  child.cmd('hi Normal guifg=#222222 guibg=NONE')
  child.api.nvim_exec_autocmds('ColorScheme', {})
  eq(child.lua_get('_G.log'), { { '\027]11;#11262d\a' } })
end

local restore_cursor_test_file = make_path(dir_misc_path, 'restore-cursor.lua')
local restore_cursor_init_file = make_path(dir_misc_path, 'init-restore-cursor.lua')
local restore_cursor_shada_path = make_path(dir_misc_path, 'restore-cursor.shada')

local cursor_set_test_type = function(x)
  vim.env.RESTORE_CURSOR_TEST_TYPE = x
  MiniTest.finally(function() vim.env.RESTORE_CURSOR_TEST_TYPE = '' end)
end

T['setup_restore_cursor()'] = new_set({
  hooks = {
    pre_case = function()
      -- Ensure that shada file is correctly set
      child.o.shadafile = restore_cursor_shada_path
    end,
    post_case = function()
      -- Don't save new shada file on child stop
      child.o.shadafile = 'NONE'

      -- Clean up
      child.fn.delete(restore_cursor_shada_path)
    end,
  },
})

T['setup_restore_cursor()']['works'] = function()
  edit(restore_cursor_test_file)
  set_cursor(10, 3)
  child.cmd('wshada!')

  child.restart({ '-u', restore_cursor_init_file, '--', restore_cursor_test_file })

  eq(get_cursor(), { 10, 3 })
  -- Should center by default
  eq(child.fn.line('w0'), 7)
end

T['setup_restore_cursor()']['validates input'] = function()
  local setup_restore_cursor = function(...) child.lua('MiniMisc.setup_restore_cursor(...)', { ... }) end

  expect.error(function() setup_restore_cursor({ center = 1 }) end, '`opts.center`.*boolean')
  expect.error(function() setup_restore_cursor({ ignore_filetype = 1 }) end, '`opts.ignore_filetype`.*array')
end

T['setup_restore_cursor()']['respects `opts.center`'] = function()
  edit(restore_cursor_test_file)
  set_cursor(10, 3)
  child.cmd('wshada!')

  cursor_set_test_type('not-center')
  child.restart({ '-u', restore_cursor_init_file, '--', restore_cursor_test_file })

  eq(get_cursor(), { 10, 3 })
  -- Should not center line
  eq(child.fn.line('w$'), 10)
end

T['setup_restore_cursor()']['respects `opts.ignore_filetype`'] = function()
  edit(restore_cursor_test_file)
  set_cursor(10, 3)
  child.cmd('wshada!')

  cursor_set_test_type('ignore-lua')
  child.restart({ '-u', restore_cursor_init_file, '--', restore_cursor_test_file })

  eq(get_cursor(), { 1, 0 })
end

T['setup_restore_cursor()']['restores only in normal buffer'] = function()
  edit(restore_cursor_test_file)
  set_cursor(10, 3)
  child.cmd('wshada!')

  cursor_set_test_type('set-not-normal-buftype')
  child.restart({ '-u', restore_cursor_init_file, '--', restore_cursor_test_file })

  eq(get_cursor(), { 1, 0 })
end

T['setup_restore_cursor()']['does not restore if position is already set'] = function()
  edit(restore_cursor_test_file)
  set_cursor(10, 3)
  child.cmd('wshada!')

  cursor_set_test_type('set-position')
  child.restart({ '-u', restore_cursor_init_file, '--', restore_cursor_test_file })

  eq(get_cursor(), { 4, 0 })

  -- Double check that `setup_restore_cursor()` was run
  expect.match(child.cmd_capture('au MiniMiscRestoreCursor'), 'BufRead')
end

T['setup_restore_cursor()']['does not restore if position is outdated'] = function()
  edit(restore_cursor_test_file)

  -- Ensure that file content won't change even on test case error
  local true_lines = get_lines()
  MiniTest.finally(function() vim.fn.writefile(true_lines, restore_cursor_test_file) end)

  set_cursor(10, 3)
  child.cmd('wshada!')
  child.cmd('bwipeout')

  -- Modify file so that position will appear outdated
  child.fn.writefile({ '-- bbb', '-- bbb' }, restore_cursor_test_file)

  child.restart({ '-u', restore_cursor_init_file, '--', restore_cursor_test_file })

  eq(get_cursor(), { 1, 0 })

  -- Double check that `setup_restore_cursor()` was run
  expect.match(child.cmd_capture('au MiniMiscRestoreCursor'), 'BufRead')
end

T['setup_restore_cursor()']['opens just enough folds'] = function()
  edit(restore_cursor_test_file)
  set_cursor(10, 3)
  child.cmd('wshada!')

  cursor_set_test_type('make-folds')
  child.restart({ '-u', restore_cursor_init_file, '--', restore_cursor_test_file })

  -- Should open only needed folds
  eq(get_cursor(), { 10, 3 })

  eq({ child.fn.foldclosed(2), child.fn.foldclosed(3) }, { 2, 2 })
  eq({ child.fn.foldclosed(9), child.fn.foldclosed(10) }, { -1, -1 })

  -- Double check that `setup_restore_cursor()` was run
  expect.match(child.cmd_capture('au MiniMiscRestoreCursor'), 'BufRead')
end

local stat_summary = function(...) return child.lua_get('MiniMisc.stat_summary({ ... })', { ... }) end

T['stat_summary()'] = new_set()

T['stat_summary()']['works'] = function()
  eq(stat_summary(10, 4, 3, 2, 1), { minimum = 1, mean = 4, median = 3, maximum = 10, n = 5, sd = math.sqrt(50 / 4) })
end

T['stat_summary()']['validates input'] = function()
  expect.error(function() stat_summary('a') end, 'array')
  expect.error(function() stat_summary({ a = 1 }) end, 'array')
  expect.error(function() stat_summary({ 'a' }) end, 'numbers')
end

T['stat_summary()']['works with one number'] = function()
  eq(stat_summary(10), { minimum = 10, mean = 10, median = 10, maximum = 10, n = 1, sd = 0 })
end

T['stat_summary()']['handles even/odd number of elements for `median`'] = function()
  eq(stat_summary(1, 2).median, 1.5)
  eq(stat_summary(3, 1, 2).median, 2)
end

T['tbl_head()/tbl_tail()'] = new_set({
  parametrize = { { 'tbl_head' }, { 'tbl_tail' } },
})

T['tbl_head()/tbl_tail()']['works'] = function(fun_name)
  local example_table = { a = 1, b = 2, c = 3, d = 4, e = 5, f = 6, g = 7 }

  local validate = function(n)
    local output = child.lua_get(('MiniMisc.%s(...)'):format(fun_name), { example_table, n })
    local reference = math.min(vim.tbl_count(example_table), n or 5)
    eq(vim.tbl_count(output), reference)
  end

  -- The exact values vary greatly and so seem to be untestable
  validate(nil)
  validate(3)
  validate(0)
end

local comments_option
T['use_nested_comments()'] = new_set({
  hooks = {
    pre_case = function()
      child.api.nvim_set_current_buf(child.api.nvim_create_buf(true, false))
      comments_option = child.bo.comments
    end,
  },
})

T['use_nested_comments()']['works'] = function()
  child.bo.commentstring = '# %s'
  child.lua('MiniMisc.use_nested_comments()')
  eq(child.bo.comments, 'n:#,' .. comments_option)
end

T['use_nested_comments()']["ignores 'commentstring' with two parts"] = function()
  child.bo.commentstring = '/*%s*/'
  child.lua('MiniMisc.use_nested_comments()')
  eq(child.bo.comments, comments_option)
end

T['use_nested_comments()']['respects `buf_id` argument'] = function()
  local new_buf_id = child.api.nvim_create_buf(true, false)
  child.api.nvim_buf_set_option(new_buf_id, 'commentstring', '# %s')

  child.lua('MiniMisc.use_nested_comments(...)', { new_buf_id })

  eq(child.bo.comments, comments_option)
  eq(child.api.nvim_buf_get_option(new_buf_id, 'comments'), 'n:#,' .. comments_option)
end

T['zoom()'] = new_set()

local get_floating_windows = function()
  return vim.tbl_filter(
    function(x) return child.api.nvim_win_get_config(x).relative ~= '' end,
    child.api.nvim_list_wins()
  )
end

local validate_dims = function(win_id, height, width)
  local config = child.api.nvim_win_get_config(win_id)
  eq({ config.height, config.width }, { height, width })
end

T['zoom()']['works'] = function()
  child.set_size(5, 20)
  set_lines({ 'aaa', 'bbb' })
  child.o.statusline = 'Statusline should not be visible in floating window'
  child.o.winblend = 50

  local buf_id = child.api.nvim_get_current_buf()
  eq(child.lua_get('MiniMisc.zoom()'), true)
  local floating_wins = get_floating_windows()

  eq(#floating_wins, 1)
  local win_id = floating_wins[1]
  eq(child.api.nvim_win_get_buf(win_id), buf_id)
  validate_dims(win_id, 4, 20)
  eq(child.api.nvim_win_get_option(win_id, 'winblend'), 0)

  -- No statusline should be present
  child.expect_screenshot()

  -- Should toggle between zoom in and out
  eq(child.lua_get('MiniMisc.zoom()'), false)
  eq(#get_floating_windows(), 0)
end

T['zoom()']['respects `buf_id` argument'] = function()
  local buf_id = child.api.nvim_create_buf(true, false)
  child.lua('MiniMisc.zoom(...)', { buf_id })
  local floating_wins = get_floating_windows()

  eq(#floating_wins, 1)
  eq(child.api.nvim_win_get_buf(floating_wins[1]), buf_id)
end

T['zoom()']['respects `config` argument'] = function()
  child.set_size(5, 30)

  local validate = function(config, ref_height, ref_width)
    child.lua('MiniMisc.zoom(...)', { 0, config })
    local floating_wins = get_floating_windows()

    eq(#floating_wins, 1)
    validate_dims(floating_wins[1], ref_height, ref_width)
    child.expect_screenshot()

    child.cmd('quit')
  end

  validate({ width = 20 }, 4, 20)

  -- Should adjust in reaction to border
  validate({ border = 'double' }, 2, 28)

  -- Should truncate possible title
  validate({ width = 20, border = 'single', title = 'Custom title to check truncation' }, 2, 20)

  -- Should work with different border types
  validate({ border = { '', 'x', '', '', '', 'x', '', '' } }, 2, 30)
  validate({ border = { '', '', '', 'x', '', '', '', 'x' } }, 4, 28)
  validate({ border = { '!', 'x', '', '', '', '', '', 'x' } }, 3, 29)
  validate({ border = { '', '', '', 'x' } }, 4, 28)
  validate({ border = { '!', 'x' } }, 2, 28)
  validate({ border = { 'x' } }, 2, 28)
end

T['zoom()']["respects 'winborder' option"] = function()
  if child.fn.has('nvim-0.11') == 0 then MiniTest.skip("'winborder' option is present on Neovim>=0.11") end
  child.set_size(5, 30)

  local validate = function(winborder, border_arg)
    child.o.winborder = winborder
    local lua_cmd = string.format('MiniMisc.zoom(0, { border = %s })', vim.inspect(border_arg))
    child.lua(lua_cmd)
    child.expect_screenshot()
    child.lua('MiniMisc.zoom()')
  end

  validate('rounded', nil)

  -- Should prefer explicitly configured value over 'winborder'
  validate('rounded', 'double')

  -- Should work with "string array" 'winborder'
  if child.fn.has('nvim-0.12') == 0 then MiniTest.skip("String array 'winborder' is present on Neovim>=0.12") end
  validate('+,-,+,|,+,-,+,|', nil)
end

T['zoom()']['reacts to relevant UI changes'] = function()
  child.set_size(5, 30)
  child.lua('MiniMisc.zoom()')
  local win_id = get_floating_windows()[1]

  validate_dims(win_id, 4, 30)
  child.o.lines = 10
  validate_dims(win_id, 9, 30)
  child.o.columns = 20
  validate_dims(win_id, 9, 20)
  child.o.cmdheight = 0
  validate_dims(win_id, 10, 20)
  child.o.cmdheight = 3
  validate_dims(win_id, 7, 20)
end

T['zoom()']['can be safely closed manually'] = function()
  child.set_size(5, 30)
  child.lua('MiniMisc.zoom()')
  child.cmd('quit')

  expect.no_error(function() child.cmd_capture('au MiniMiscZoom') end)
  child.o.lines = 10
  expect.error(function() child.cmd_capture('au MiniMiscZoom') end, 'No such group')
end

return T
