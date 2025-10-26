-- This is intended to mostly cover general API. In a sense, all tests in this
-- plugin also test 'mini.test'.
local helpers = dofile('tests/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set, finally = MiniTest.new_set, MiniTest.finally

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('test', config) end
local unload_module = function() child.mini_unload('test') end
local set_cursor = function(...) return child.set_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
--stylua: ignore end

-- TODO: Remove after compatibility with Neovim=0.9 is dropped
local islist = vim.fn.has('nvim-0.10') == 1 and vim.islist or vim.tbl_islist

local get_latest_message = function() return child.cmd_capture('1messages') end

local get_ref_path = function(name) return string.format('tests/dir-test/%s', name) end

local get_current_all_cases = function()
  -- Encode functions inside child. Works only for "simple" functions.
  local command = [[vim.tbl_map(function(case)
    case.hooks.pre = vim.tbl_map(string.dump, case.hooks.pre)
    case.hooks.post = vim.tbl_map(string.dump, case.hooks.post)
    case.test = string.dump(case.test)
    return case
  end, MiniTest.current.all_cases)]]
  local res = child.lua_get(command)

  -- Decode functions in current process
  res = vim.tbl_map(function(case)
    case.hooks.pre = vim.tbl_map(loadstring, case.hooks.pre)
    case.hooks.post = vim.tbl_map(loadstring, case.hooks.post)
    case.test = loadstring(case.test)
    return case
  end, res)

  -- Update array to enable getting element by last entry of `desc` field
  return setmetatable(res, {
    __index = function(t, key)
      return vim.tbl_filter(function(case_output)
        local last_desc = case_output.desc[#case_output.desc]
        return last_desc == key
      end, t)[1]
    end,
  })
end

local testrun_ref_file = function(name)
  local find_files_command = string.format([[_G.find_files = function() return { '%s' } end]], get_ref_path(name))
  child.lua(find_files_command)
  child.lua([[
    _G.reporter_log = {}
    _G.report_in_log = {
      start = function(...) table.insert(_G.reporter_log, { 'start', ... }) end,
      update = function(...)
        table.insert(_G.reporter_log, { 'update', vim.deepcopy(MiniTest.current.case.exec.state), ... })
      end,
      finish = function(...) table.insert(_G.reporter_log, { 'finish', ... }) end,
    }
  ]])
  child.lua([[MiniTest.run({ collect = { find_files = _G.find_files }, execute = { reporter = _G.report_in_log } })]])
  return get_current_all_cases()
end

local filter_by_desc = function(cases, id, value)
  return vim.tbl_filter(function(c) return c.desc[id] == value end, cases)
end

local expect_all_state = function(cases, state)
  local res = true
  for _, c in ipairs(cases) do
    if type(c.exec) ~= 'table' or c.exec.state ~= state then res = false end
  end

  eq(res, true)
end

-- Time constants
local terminal_wait = helpers.get_time_const(500)

-- Output test set
local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      -- Mock UI so that default reporter is as if used interactively
      child.lua('vim.api.nvim_list_uis = function() return { 1 } end')
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
  eq(child.lua_get('type(_G.MiniTest)'), 'table')

  -- Autocommand group
  eq(child.fn.exists('#MiniTest'), 1)

  -- Highlight groups
  child.cmd('hi clear')
  load_module()
  expect.match(child.cmd_capture('hi MiniTestFail'), 'gui=bold')
  expect.match(child.cmd_capture('hi MiniTestPass'), 'gui=bold')
  expect.match(child.cmd_capture('hi MiniTestEmphasis'), 'gui=bold')
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniTest.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniTest.config.' .. field), value) end

  expect_config('collect.emulate_busted', true)
  eq(child.lua_get('type(_G.MiniTest.config.collect.find_files)'), 'function')
  eq(child.lua_get('type(_G.MiniTest.config.collect.filter_cases)'), 'function')
  expect_config('execute.reporter', vim.NIL)
  expect_config('execute.stop_on_error', false)
  expect_config('script_path', 'scripts/minitest.lua')
  expect_config('silent', false)
end

T['setup()']['respects `config` argument'] = function()
  unload_module()
  load_module({ script_path = 'a' })
  eq(child.lua_get('MiniTest.config.script_path'), 'a')
end

T['setup()']['validates `config` argument'] = function()
  unload_module()

  local expect_config_error = function(config, name, target_type)
    local pattern = vim.pesc(name) .. '.*' .. vim.pesc(target_type)
    expect.error(load_module, pattern, config)
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ collect = 'a' }, 'collect', 'table')
  expect_config_error({ collect = { emulate_busted = 'a' } }, 'collect.emulate_busted', 'boolean')
  expect_config_error({ collect = { find_files = 'a' } }, 'collect.find_files', 'function')
  expect_config_error({ collect = { filter_cases = 'a' } }, 'collect.filter_cases', 'function')
  expect_config_error({ execute = 'a' }, 'execute', 'table')
  expect_config_error({ execute = { reporter = 'a' } }, 'execute.reporter', 'function')
  expect_config_error({ execute = { stop_on_error = 'a' } }, 'execute.stop_on_error', 'boolean')
  expect_config_error({ script_path = 1 }, 'script_path', 'string')
  expect_config_error({ silent = 1 }, 'silent', 'boolean')
end

T['setup()']['ensures colors'] = function()
  child.cmd('colorscheme default')
  expect.match(child.cmd_capture('hi MiniTestFail'), 'gui=bold')
  expect.match(child.cmd_capture('hi MiniTestPass'), 'gui=bold')
  expect.match(child.cmd_capture('hi MiniTestEmphasis'), 'gui=bold')
end

T['new_set()'] = new_set()

T['new_set()']['tracks field order'] = function()
  local res = testrun_ref_file('testref_new-set.lua')

  -- Check order
  local order_cases = vim.tbl_map(
    function(c) return c.desc[#c.desc] end,
    vim.tbl_filter(function(c) return c.desc[2] == 'order' end, res)
  )
  eq(order_cases, { 'From initial call', 'zzz First added', 'aaa Second added', 1 })
end

T['new_set()']['stores `opts`'] = function()
  local opts = { parametrize = { { 'a' } }, n_retry = 10 }
  child.lua([[_G.set = MiniTest.new_set(...)]], { opts })
  eq(child.lua_get([[getmetatable(_G.set).opts]]), opts)
end

T['case helpers'] = new_set()

T['case helpers']['work'] = function()
  local res = testrun_ref_file('testref_case-helpers.lua')

  -- `finally()`
  eq(res['finally() with error; check'].exec.state, 'Pass')
  eq(res['finally() no error; check'].exec.state, 'Pass')
  eq(child.lua_get('_G.finally_log'), { 'one', 'two' })

  -- `skip()`
  eq(res['skip(); no message'].exec.state, 'Pass with notes')
  eq(res['skip(); no message'].exec.notes, { 'Skip test' })

  eq(res['skip(); with message'].exec.state, 'Pass with notes')
  eq(res['skip(); with message'].exec.notes, { 'This is a custom skip message' })

  eq(res['skip() can be called from helper'].exec.notes, { 'Skip from helper' })

  eq(res['skip one'].exec.state, 'Pass with notes')
  eq(res['skip one'].exec.notes, { 'Should skip case' })
  eq(res['skip two'].exec.state, 'Pass with notes')
  eq(res['skip two'].exec.notes, { 'Should skip case' })

  eq(res['skip() in other hooks'].exec.state, 'Fail')
  eq(res['skip() in other hooks'].exec.notes, {})

  -- `add_note()`
  eq(res['add_note() case'].exec.state, 'Pass with notes')
  eq(res['add_note() case'].exec.notes, { 'pre_once', 'pre_case', 'test case', 'post_case', 'post_once' })
end

T['run()'] = new_set()

T['run()']['respects `opts` argument'] = function()
  child.lua('MiniTest.run({ collect = { find_files = function() return {} end } })')
  eq(#get_current_all_cases(), 0)

  -- Should also use buffer local config
  local general_file = get_ref_path('testref_general.lua')
  local command = string.format(
    [[vim.b.minitest_config = { collect = { find_files = function() return { '%s' } end } }]],
    general_file
  )
  child.lua(command)
  child.lua('MiniTest.run()')
  eq(#get_current_all_cases() > 0, true)
end

T['run()']['tries to execute script if no arguments are supplied'] = function()
  local validate = function()
    local cache_local_config = child.b.minitest_config

    eq(child.lua_get('_G.custom_script_result'), vim.NIL)
    child.lua('MiniTest.run()')
    eq(child.lua_get('_G.custom_script_result'), 'This actually ran')

    -- Global and buffer local config should be restored
    eq(child.lua_get('type(MiniTest.config.aaa)'), 'nil')
    eq(child.b.minitest_config, cache_local_config)
  end

  local script_path = get_ref_path('testref_custom-script.lua')
  child.lua('MiniTest.config.script_path = ' .. vim.inspect(script_path))
  validate()

  -- Should also use buffer local config
  child.lua([[MiniTest.config.script_path = '']])
  child.lua('_G.custom_script_result = nil')
  child.b.minitest_config = { script_path = script_path }
  validate()
end

T['run()']['handles `parametrize`'] = function()
  local res = testrun_ref_file('testref_run-parametrize.lua')
  eq(#res, 10)

  local short_res = vim.tbl_map(function(c)
    local desc = vim.list_slice(c.desc, 2)
    return { args = c.args, desc = desc, passed_args = c.exec.fails[1]:match('Passed arguments: (.-)\n  Traceback.*$') }
  end, res)

  eq(short_res[1], { args = { 'a' }, desc = { 'parametrize', 'first level' }, passed_args = '"a"' })
  eq(short_res[2], { args = { 'b' }, desc = { 'parametrize', 'first level' }, passed_args = '"b"' })

  eq(short_res[3], { args = { 'a', 1 }, desc = { 'parametrize', 'nested', 'test' }, passed_args = '"a", 1' })
  eq(short_res[4], { args = { 'a', 2 }, desc = { 'parametrize', 'nested', 'test' }, passed_args = '"a", 2' })
  eq(short_res[5], { args = { 'b', 1 }, desc = { 'parametrize', 'nested', 'test' }, passed_args = '"b", 1' })
  eq(short_res[6], { args = { 'b', 2 }, desc = { 'parametrize', 'nested', 'test' }, passed_args = '"b", 2' })

  --stylua: ignore start
  eq(short_res[7],  { args = { 'a', 'a', 1, 1 }, desc = { 'multiple args', 'nested', 'test' }, passed_args = '"a", "a", 1, 1' })
  eq(short_res[8],  { args = { 'a', 'a', 2, 2 }, desc = { 'multiple args', 'nested', 'test' }, passed_args = '"a", "a", 2, 2' })
  eq(short_res[9],  { args = { 'b', 'b', 1, 1 }, desc = { 'multiple args', 'nested', 'test' }, passed_args = '"b", "b", 1, 1' })
  eq(short_res[10], { args = { 'b', 'b', 2, 2 }, desc = { 'multiple args', 'nested', 'test' }, passed_args = '"b", "b", 2, 2' })
  --stylua: ignore end
end

T['run()']['validates `parametrize`'] = function()
  expect.error(
    function() testrun_ref_file('testref_run-parametrize-error.lua') end,
    [[`parametrize` should have only tables. Got "a"]]
  )
end

T['run()']['handles `data`'] = function()
  local res = testrun_ref_file('testref_run-data.lua')
  local short_res = vim.tbl_map(function(c) return { data = c.data, desc = vim.list_slice(c.desc, 2) } end, res)

  eq(#short_res, 2)
  eq(short_res[1], {
    data = { a = 1, b = 2 },
    desc = { 'data', 'first level' },
  })
  eq(short_res[2], {
    data = { a = 10, b = 2, c = 30 },
    desc = { 'data', 'nested', 'should override' },
  })
end

T['run()']['handles `hooks`'] = function()
  local res = testrun_ref_file('testref_run-hooks.lua')
  --stylua: ignore
  eq(child.lua_get('_G.log'), {
    -- Test order
    "pre_once_1",
    "pre_case_1", "First level test", "post_case_1",
    "pre_once_2",
    "pre_case_1", "pre_case_2", "Nested #1", "post_case_2", "post_case_1",
    "pre_case_1", "pre_case_2", "Nested #2", "post_case_2", "post_case_1",
    "post_once_2",
    "post_once_1",

    -- Test skip case on hook error. All hooks should still be called.
    "pre_case_3", "post_case_3", "post_once_3",
    "pre_once_4", "post_case_4", "post_once_4",

    -- Using same function in `*_once` hooks should still lead to its multiple
    -- execution.
    "Same function",
    "Same function",
    "Same hook test",
    "Same function",
    "Same function",
  })

  -- Skipping test case due to hook errors should add a note
  expect.match(filter_by_desc(res, 2, 'skip_case_on_hook_error #1')[1].exec.notes[1], '^Skip.*error.*hooks')
end

T['run()']['handles `n_retry`'] = function()
  local res = testrun_ref_file('testref_run-n_retry.lua')
  --stylua: ignore
  local ref_log = {
    'default',
    'should override', 'should override',
    'more override', 'more override', 'more override',
    'first success #1', 'first success #2', 'first success #3',
    'latest error #1', 'latest error #2', 'latest error #3',

    -- Retries should NOT be applied separately to hooks
    'no retry pre_once', 'no retry pre_case', 'no retry post_case', 'no retry post_once',

    -- Should retry failed case with all its `pre_case` and `post_case`.
    -- The `pre_once` and `post_once` should still be executed only once.
    'outer pre_once', 'inner pre_once',
    'outer pre_case', 'inner pre_case', 'hook exec case', 'inner post_case', 'outer post_case',
    'outer pre_case', 'inner pre_case', 'hook exec case', 'inner post_case', 'outer post_case',
    'inner post_once', 'outer post_once',

    'screenshot', 'screenshot',
    'skip',
    'parameter 1', 'parameter 1', 'parameter 2', 'parameter 2'
  }
  eq(child.lua_get('_G.log'), ref_log)

  -- Should track relevant `n_retry` value
  eq(vim.tbl_map(function(x) return x.n_retry end, res), { 1, 2, 3, 10, 3, 2, 2, 2, 2, 2, 2, 2 })

  -- Should report latest (and only latest) error among all retries
  local latest_error_case_fails = filter_by_desc(res, 2, 'reports latest error')[1].exec.fails
  eq(#latest_error_case_fails, 1)
  expect.match(latest_error_case_fails[1], 'Error #3')

  -- Should report hook fails even if `n_retry > 1`
  eq(#filter_by_desc(res, 2, 'does not retry hooks')[1].exec.fails, 4)

  -- Should not generate new screenshots after first try
  eq(filter_by_desc(res, 2, 'screenshot number')[1].exec.notes, {})

  -- Should update state on every retry
  local update_case_num
  for i, case in ipairs(res) do
    if case.desc[2] == 'updates state on every retry' then update_case_num = i end
  end
  child.lua('_G.target_case_num = ' .. (update_case_num or #res))
  local updates_of_target_case = child.lua([[
    local res = {}
    for _, t in ipairs(_G.reporter_log) do
      if t[1] == 'update' and t[3] == target_case_num then table.insert(res, t) end
    end
    return res
  ]])
  local ref_updates = {
    { 'update', "Executing 'pre' hook #1", 12 },
    { 'update', "Executing 'pre' hook #2", 12 },
    { 'update', 'Executing test', 12 },
    { 'update', "Executing 'post' hook #1", 12 },
    -- Method `update()` of reporter should be called on every retry
    { 'update', "Executing 'pre' hook #2", 12 },
    { 'update', 'Executing test', 12 },
    { 'update', "Executing 'post' hook #1", 12 },
    { 'update', "Executing 'post' hook #2", 12 },
    { 'update', 'Fail', 12 },
  }
  eq(updates_of_target_case, ref_updates)
end

T['run()']['respects `stop_on_error` after all retries'] = function()
  local path = get_ref_path('testref_run-n_retry-stop_on_error.lua')
  local command = string.format([[_G.cases = MiniTest.collect({ find_files = function() return { '%s' } end })]], path)
  child.lua(command)

  -- Should indeed stop on first "final" error (i.e. ignore errors from tries)
  child.lua('MiniTest.execute(_G.cases, { stop_on_error = true })')
  eq(child.lua_get('_G.log'), { 'try #1', 'try #2', 'try #3', 'continue' })
  eq(child.lua_get('_G.cases[3].exec'), vim.NIL)
end

T['run()']['appends traceback to fails'] = function()
  local res = testrun_ref_file('testref_general.lua')
  local ref_path = get_ref_path('testref_general.lua')
  local n = 0
  for _, case in ipairs(res) do
    if #case.exec.fails > 0 then
      expect.match(case.exec.fails[1], 'Traceback:%s+' .. vim.pesc(ref_path))
      n = n + 1
    end
  end

  if n == 0 then error('No actual fails was tested', 0) end
end

T['run_file()'] = new_set()

T['run_file()']['works'] = function()
  child.lua([[MiniTest.run_file(...)]], { get_ref_path('testref_run.lua') })
  local last_desc =
    child.lua_get([[vim.tbl_map(function(case) return case.desc[#case.desc] end, MiniTest.current.all_cases)]])
  eq(last_desc, { 'run_at_location()', 'extra case' })
end

T['run_file()']['normalizes input path'] = function()
  child.lua('MiniTest.run_file(...)', { './' .. get_ref_path('testref_run.lua') })
  eq(child.lua_get('MiniTest.current.all_cases[1].desc[1]'):gsub('\\', '/'), 'tests/dir-test/testref_run.lua')
end

T['run_at_location()'] = new_set()

T['run_at_location()']['works with non-default input'] = new_set({ parametrize = { { 3 }, { 4 }, { 5 } } }, {
  function(line)
    local path = get_ref_path('testref_run.lua')
    local command = string.format([[MiniTest.run_at_location({ file = '%s', line = %s })]], path, line)
    child.lua(command)

    local all_cases = get_current_all_cases()
    eq(#all_cases, 1)
    eq(all_cases[1].desc, { path, 'run_at_location()' })
  end,
})

T['run_at_location()']['uses cursor position by default'] = function()
  local path = get_ref_path('testref_run.lua')
  child.cmd('edit ' .. path)
  set_cursor(4, 0)
  child.lua('MiniTest.run_at_location()')

  local all_cases = get_current_all_cases()
  eq(#all_cases, 1)
  local desc = all_cases[1].desc
  eq(desc[1]:gsub('\\', '/'), path)
  eq(desc[2], 'run_at_location()')
end

local collect_general = function()
  local path = get_ref_path('testref_general.lua')
  local command = string.format([[_G.cases = MiniTest.collect({ find_files = function() return { '%s' } end })]], path)
  child.lua(command)
end

T['collect()'] = new_set()

T['collect()']['works'] = function()
  child.lua('_G.cases = MiniTest.collect()')

  -- TODO: Remove after compatibility with Neovim=0.9 is dropped
  child.lua([[_G.islist = vim.fn.has('nvim-0.10') == 1 and vim.islist or vim.tbl_islist]])

  -- Should return array of cases
  eq(child.lua_get('_G.islist(_G.cases)'), true)

  local keys = child.lua_get('vim.tbl_keys(_G.cases[1])')
  table.sort(keys)
  eq(keys, { 'args', 'data', 'desc', 'hooks', 'n_retry', 'test' })

  local hook_keys = child.lua_get('vim.tbl_keys(_G.cases[1].hooks)')
  table.sort(hook_keys)
  eq(hook_keys, { 'post', 'post_source', 'pre', 'pre_source' })
end

T['collect()']['respects `emulate_busted` option'] = function()
  local res = testrun_ref_file('testref_collect-busted.lua')

  -- All descriptions should be prepended with file name
  eq(#filter_by_desc(res, 1, get_ref_path('testref_collect-busted.lua')), #res)

  -- `describe()/it()`
  eq(#filter_by_desc(res, 2, 'describe()/it()'), 3)

  -- `setup()/teardown()`
  expect_all_state(filter_by_desc(res, 2, 'setup()/teardown()'), 'Pass')

  -- `before_each()/after_each()`
  expect_all_state(filter_by_desc(res, 2, 'before_each()/after_each()'), 'Pass')

  -- `MiniTest.skip()`
  expect_all_state(filter_by_desc(res, 2, 'MiniTest.skip()'), 'Pass with notes')

  -- `MiniTest.finally()`
  local cases_finally = filter_by_desc(res, 2, 'MiniTest.finally()')
  -- all_have_state(filter_by_desc(cases_finally, 3, 'works with no error'))
  expect_all_state(filter_by_desc(cases_finally, 3, 'works with no error'), 'Pass')
  expect_all_state(filter_by_desc(cases_finally, 3, 'works with error'), 'Pass')

  -- Should also use buffer local config
  child.lua([[vim.b.minitest_config = { collect = { emulate_busted = false } }]])
  local busted_file = get_ref_path('testref_collect-busted.lua')
  local command = string.format([[MiniTest.collect({ find_files = function() return { '%s' } end })]], busted_file)
  expect.error(function() child.lua(command) end, 'attempt to call global')
end

T['collect()']['respects `find_files` option'] = function()
  local command = string.format(
    [[_G.cases = MiniTest.collect({ find_files = function() return { '%s' } end })]],
    get_ref_path('testref_general.lua')
  )
  child.lua(command)
  eq(child.lua_get('#_G.cases'), 2)
  eq(child.lua_get('_G.cases[1].desc[1]'), 'tests/dir-test/testref_general.lua')

  child.lua([[vim.b.minitest_config = { collect = { find_files = function() return {} end } }]])
  child.lua('_G.cases = MiniTest.collect()')
  eq(child.lua_get('#_G.cases'), 0)
end

T['collect()']['respects `filter_cases` option'] = function()
  local command = string.format(
    [[_G.cases = MiniTest.collect({
      find_files = function() return { '%s' } end,
      filter_cases = function(case) return case.desc[2] == 'case 2' end,
    })]],
    get_ref_path('testref_general.lua')
  )
  child.lua(command)

  eq(child.lua_get('#_G.cases'), 1)
  eq(child.lua_get('_G.cases[1].desc[2]'), 'case 2')

  child.lua([[vim.b.minitest_config = { collect = { filter_cases = function() return false end } }]])
  child.lua('_G.cases = MiniTest.collect()')
  eq(child.lua_get('#_G.cases'), 0)
end

T['execute()'] = new_set()

T['execute()']['respects `reporter` option'] = new_set()

T['execute()']['respects `reporter` option']['empty'] = function()
  collect_general()
  child.lua('MiniTest.execute(_G.cases, { reporter = {} })')
end

T['execute()']['respects `reporter` option']['partial'] = function()
  collect_general()
  child.lua([[MiniTest.execute(
    _G.cases,
    { reporter = {
      start = function() _G.was_in_start = true end,
      finish = function() _G.was_in_finish = true end,
    } }
  )]])

  eq(child.lua_get('_G.was_in_start'), true)
  eq(child.lua_get('_G.was_in_finish'), true)

  child.lua('vim.b.minitest_config = { execute = { reporter = { update = function() _G.was_in_update = true end } } }')
  child.lua('MiniTest.execute(_G.cases)')
  eq(child.lua_get('_G.was_in_update'), true)
end

T['execute()']['respects `stop_on_error` option'] = function()
  collect_general()

  child.lua('MiniTest.execute(_G.cases, { stop_on_error = true })')

  eq(child.lua_get('type(_G.cases[1].exec)'), 'table')
  eq(child.lua_get('_G.cases[1].exec.state'), 'Fail')

  eq(child.lua_get('type(_G.cases[2].exec)'), 'nil')

  -- Should also use buffer local config
  child.lua('vim.b.minitest_config = { execute = { stop_on_error = false } }')
  child.lua('MiniTest.execute(_G.cases)')
  eq(child.lua_get('type(_G.cases[2].exec)'), 'table')
end

T['execute()']['properly calls `reporter` methods'] = function()
  collect_general()

  child.lua([[
  _G.update_history = {}
  _G.reporter = {
    start = function(all_cases) _G.all_cases = all_cases end,
    update = function(case_num)
      table.insert(_G.update_history, { case_num = case_num, state = _G.all_cases[case_num].exec.state })
    end,
    finish = function() _G.was_in_finish = true end,
  }]])

  child.lua([[MiniTest.execute(_G.cases, { reporter = _G.reporter })]])
  eq(child.lua_get('#_G.all_cases'), 2)
  eq(child.lua_get('_G.update_history'), {
    { case_num = 1, state = "Executing 'pre' hook #1" },
    { case_num = 1, state = "Executing 'pre' hook #2" },
    { case_num = 1, state = 'Executing test' },
    { case_num = 1, state = "Executing 'post' hook #1" },
    { case_num = 1, state = 'Fail' },
    { case_num = 2, state = "Executing 'pre' hook #1" },
    { case_num = 2, state = 'Executing test' },
    { case_num = 2, state = "Executing 'post' hook #1" },
    { case_num = 2, state = "Executing 'post' hook #2" },
    { case_num = 2, state = 'Pass' },
  })
  eq(child.lua_get('_G.was_in_finish'), true)
end

T['execute()']['handles no cases'] = function()
  child.lua('MiniTest.execute({})')
  eq(child.lua_get('MiniTest.current.all_cases'), {})

  -- Should throw message
  eq(get_latest_message(), '(mini.test) No cases to execute.')
end

T['execute()']['respects `config.silent`'] = function()
  child.lua('MiniTest.config.silent = true')
  child.lua('MiniTest.execute({})')
  eq(child.lua_get('MiniTest.current.all_cases'), {})

  -- Should not throw message
  eq(get_latest_message(), '')
end

T['stop()'] = new_set()

T['stop()']['works'] = function()
  collect_general()

  child.lua('_G.grandchild = MiniTest.new_child_neovim(); _G.grandchild.start()')
  child.lua('MiniTest.execute(_G.cases, { reporter = { start = function() MiniTest.stop() end } })')

  eq(child.lua_get('type(_G.cases[1].exec)'), 'nil')
  eq(child.lua_get('type(_G.cases[2].exec)'), 'nil')

  -- Should close all opened child processed by default
  eq(child.lua_get('_G.grandchild.is_running()'), false)
end

T['stop()']['respects `close_all_child_neovim` option'] = function()
  collect_general()

  child.lua('_G.grandchild = MiniTest.new_child_neovim(); _G.grandchild.start()')
  -- Register cleanup
  finally(function() child.lua('_G.grandchild.stop()') end)
  child.lua([[MiniTest.execute(
    _G.cases,
    { reporter = { start = function() MiniTest.stop({ close_all_child_neovim = false }) end } }
  )]])

  -- Shouldn't close as per option
  eq(child.lua_get('_G.grandchild.is_running()'), true)
end

T['is_executing()'] = new_set()

T['is_executing()']['works'] = function()
  collect_general()

  -- Tests are executing all the time while reporter is active, but not before
  -- or after
  eq(child.lua_get('MiniTest.is_executing()'), false)

  child.lua([[
  _G.executing_states = {}
  local track_is_executing = function() table.insert(_G.executing_states, MiniTest.is_executing()) end
  MiniTest.execute(
    _G.cases,
    { reporter = { start = track_is_executing, update = track_is_executing, finish = track_is_executing } }
  )]])

  local all_true = true
  for _, s in ipairs(child.lua_get('_G.executing_states')) do
    if s ~= true then all_true = false end
  end
  eq(all_true, true)

  eq(child.lua_get('MiniTest.is_executing()'), false)
end

T['expect'] = new_set()

T['expect']['equality()/no_equality()'] = new_set()

T['expect']['equality()/no_equality()']['work when equal'] = function()
  local f, empty_tbl = function() end, {}

  local validate = function(x, y)
    expect.no_error(MiniTest.expect.equality, x, y)
    expect.error(MiniTest.expect.no_equality, '%*no%* equality.*Object:', x, y)
  end

  validate(1, 1)
  validate('a', 'a')
  validate(f, f)
  validate(empty_tbl, empty_tbl)

  -- Tables should be compared "deeply per elements"
  validate(empty_tbl, {})
  validate({ 1 }, { 1 })
  validate({ a = 1 }, { a = 1 })
  validate({ { b = 2 } }, { { b = 2 } })
end

T['expect']['equality()/no_equality()']['work when not equal'] = function()
  local f = function() end
  local validate = function(x, y)
    expect.error(MiniTest.expect.equality, 'equality.*Left:  .*Right: ', x, y)
    expect.no_error(MiniTest.expect.no_equality, x, y)
  end

  validate(1, 2)
  validate(1, '1')
  validate('a', 'b')
  validate(f, function() end)

  -- Tables should be compared "deeply per elements"
  validate({ 1 }, { 2 })
  validate({ a = 1 }, { a = 2 })
  validate({ a = 1 }, { b = 1 })
  validate({ a = 1 }, { { a = 1 } })
  validate({ { b = 2 } }, { { b = 3 } })
  validate({ { b = 2 } }, { { c = 2 } })
end

T['expect']['equality()/no_equality()']['return `true` on success'] = function()
  eq(MiniTest.expect.equality(1, 1), true)
  eq(MiniTest.expect.no_equality(1, 2), true)
end

T['expect']['error()'] = new_set()

T['expect']['error()']['works'] = function()
  expect.error(function()
    MiniTest.expect.error(function() end)
  end, 'error%..*Observed no error')

  expect.error(function()
    MiniTest.expect.error(function() end, 'aa')
  end, 'error matching pattern "aa"%..*Observed no error')

  expect.error(function() MiniTest.expect.error(error, 'bb') end, 'error matching pattern "bb"%..*Observed error:')
end

T['expect']['error()']['respects `pattern` argument'] = function()
  ---@diagnostic disable-next-line:param-type-mismatch
  expect.error(function() MiniTest.expect.error(error, 1) end, 'pattern.*string')

  -- `nil` and `''` are placeholders for 'any error'
  expect.no_error(function() MiniTest.expect.error(error, '') end)
  expect.no_error(function() MiniTest.expect.error(error, nil) end)
end

T['expect']['error()']['accepts function arguments'] = function()
  --stylua: ignore
  local f = function(x, y)
    if x ~= y then error('`x` and `y` are not equal') end
  end

  expect.no_error(function() MiniTest.expect.error(f, 'not equal', 1, 2) end)
  expect.error(function() MiniTest.expect.error(f, 'not equal', 1, 1) end)
end

T['expect']['error()']['returns `true` on success'] = function() eq(MiniTest.expect.error(error), true) end

T['expect']['no_error()'] = new_set()

T['expect']['no_error()']['works'] = function()
  expect.error(function() MiniTest.expect.no_error(error) end, '%*no%* error%..*Observed error:')

  expect.no_error(function()
    MiniTest.expect.no_error(function() end)
  end)
end

T['expect']['no_error()']['accepts function arguments'] = function()
  --stylua: ignore
  local f = function(x, y)
    if x ~= y then error('`x` and `y` are not equal') end
  end

  expect.error(function() MiniTest.expect.no_error(f, 1, 2) end)
  expect.no_error(function() MiniTest.expect.no_error(f, 1, 1) end)
end

T['expect']['no_error()']['returns `true` on success'] = function()
  eq(MiniTest.expect.no_error(function() end), true)
end

T['expect']['reference_screenshot()'] = new_set()

T['expect']['reference_screenshot()']['works'] = function()
  local path = get_ref_path('reference-screenshot')
  child.set_size(5, 12)

  set_lines({ 'aaa' })
  eq(MiniTest.expect.reference_screenshot(child.get_screenshot(), path), true)

  set_lines({ 'bbb' })
  expect.error(
    function() MiniTest.expect.reference_screenshot(child.get_screenshot(), path) end,
    'screenshot equality to reference at ' .. vim.pesc(vim.inspect(path)) .. '.*Reference:.*Observed:'
  )

  -- Should pass if supplied `nil` (like in case of no reasonable screenshot)
  eq(MiniTest.expect.reference_screenshot(nil), true)
end

T['expect']['reference_screenshot()']['locates problem'] = function()
  local path = get_ref_path('reference-screenshot')
  local validate = function(screen, pattern)
    expect.error(function() MiniTest.expect.reference_screenshot(screen, path) end, pattern)
  end

  child.set_size(5, 12)
  set_lines({ 'aaa' })
  local screen = child.get_screenshot()

  -- Number of lines
  local screen_text_lines = vim.deepcopy(screen)
  table.remove(screen_text_lines.text, 1)
  validate(screen_text_lines, 'Different number of `text` lines%. Reference: 5%. Observed: 4%.')

  local screen_attr_lines = vim.deepcopy(screen)
  table.remove(screen_attr_lines.attr, 1)
  validate(screen_attr_lines, 'Different number of `attr` lines%. Reference: 5%. Observed: 4%.')

  -- Number of columns
  local screen_text_columns = vim.deepcopy(screen)
  table.remove(screen_text_columns.text[1], 1)
  validate(screen_text_columns, 'Different number of columns in `text` line 1%. Reference: 12%. Observed: 11%.')

  local screen_attr_columns = vim.deepcopy(screen)
  table.remove(screen_attr_columns.attr[1], 1)
  validate(screen_attr_columns, 'Different number of columns in `attr` line 1%. Reference: 12%. Observed: 11%.')

  -- Cells
  local screen_text_cell = vim.deepcopy(screen)
  screen_text_cell.text[1][2] = 'X'
  validate(screen_text_cell, 'Different `text` cell at line 1 column 2%. Reference: "a"%. Observed: "X"%.')

  local screen_attr_cell = vim.deepcopy(screen)
  screen_attr_cell.attr[1][2] = 'X'
  validate(screen_attr_cell, 'Different `attr` cell at line 1 column 2%. Reference: "0"%. Observed: "X"%.')
end

T['expect']['reference_screenshot()']['correctly infers reference path'] = function()
  child.set_size(5, 20)

  set_lines({ 'This path should be correctly inferred without suffix' })
  eq(MiniTest.expect.reference_screenshot(child.get_screenshot()), true)

  set_lines({ 'This path should have suffix 002' })
  eq(MiniTest.expect.reference_screenshot(child.get_screenshot()), true)

  set_lines({ 'This is a call to `reference_screenshot()` with manual path' })
  eq(MiniTest.expect.reference_screenshot(child.get_screenshot(), 'tests/dir-test/intermediate-screenshot'), true)

  set_lines({ 'This path should have suffix 004' })
  eq(MiniTest.expect.reference_screenshot(child.get_screenshot()), true)
end

local validate_path_sanitize = function()
  child.set_size(5, 12)
  set_lines({ 'Path should be correctly sanitized' })

  eq(MiniTest.expect.reference_screenshot(child.get_screenshot()), true)
end

local useful_punctuation = [=[_-+{}()[]'"]=]
local linux_forbidden = [[/]]
local windows_forbidden = [[<>:"/\|?*]]
local whitespace = '\t '
local special_characters = string.char(0) .. string.char(1) .. string.char(31)
local suffix = useful_punctuation .. linux_forbidden .. windows_forbidden .. whitespace .. special_characters

-- Don't permanently create reference file because its name is very long. This
-- might hurt Windows users which are not interested in testing this plugin.
T['expect']['reference_screenshot()']['correctly sanitizes path ' .. suffix] = new_set(
  { parametrize = { { suffix } } },
  {
    test = function()
      local expected_filename = table.concat({
        'tests/screenshots/',
        'tests-test_test.lua---',
        'expect---',
        'reference_screenshot()---',
        'correctly-sanitizes-path-',
        [[_-+{}()[]''----'-------------]],
        'test-+-args-',
        [[{-'_-+{}()[]'-'-----'-------t--0-1-31'-}]],
      }, '')
      finally(function()
        MiniTest.current.case.exec.notes = {}
        vim.fn.delete(expected_filename)
      end)
      eq(vim.fn.filereadable(expected_filename), 0)
      validate_path_sanitize()
      eq(vim.fn.filereadable(expected_filename), 1)
    end,
  }
)

-- Paths should not end with whitespace or dot
T['expect']['reference_screenshot()']['correctly sanitizes path for Windows '] = validate_path_sanitize
T['expect']['reference_screenshot()']['correctly sanitizes path for Windows #2.'] = validate_path_sanitize

T['expect']['reference_screenshot()']['creates reference if it does not exist'] = function()
  local path = get_ref_path('nonexistent-reference-screenshot')
  child.fn.delete(path)
  finally(function()
    child.fn.delete(path)
    MiniTest.current.case.exec.notes = {}
  end)

  set_lines({ 'nonexistent' })
  local screenshot = child.get_screenshot()

  eq(MiniTest.expect.reference_screenshot(screenshot, path), true)
  eq(MiniTest.current.case.exec.notes, { 'Created reference screenshot at path ' .. vim.inspect(path) })

  MiniTest.current.case.exec.notes = {}
  eq(MiniTest.expect.reference_screenshot(screenshot, path), true)
  eq(MiniTest.current.case.exec.notes, {})
end

T['expect']['reference_screenshot()']['respects `opts.force` argument'] = function()
  local path = get_ref_path('force-reference-screenshot')
  local notes = { 'Created reference screenshot at path ' .. vim.inspect(path) }

  child.fn.delete(path)
  finally(function()
    child.fn.delete(path)
    MiniTest.current.case.exec.notes = {}
  end)

  set_lines({ 'First run' })
  eq(MiniTest.expect.reference_screenshot(child.get_screenshot(), path), true)
  eq(MiniTest.current.case.exec.notes, notes)

  MiniTest.current.case.exec.notes = {}
  set_lines({ 'This should be forced' })
  eq(MiniTest.expect.reference_screenshot(child.get_screenshot(), path, { force = true }), true)
  eq(MiniTest.current.case.exec.notes, notes)
end

T['expect']['reference_screenshot()']['respects `opts.ignore_lines`'] = function()
  -- Do not show soft deprecation message
  local notify_orig = vim.notify
  vim.notify = function() end
  MiniTest.finally(function() vim.notify = notify_orig end)

  local path = get_ref_path('reference-screenshot')
  child.set_size(5, 12)
  local validate = function(ignore_lines, ref)
    eq(MiniTest.expect.reference_screenshot(child.get_screenshot(), path, { ignore_lines = ignore_lines }), ref)
  end

  set_lines({ 'aaa' })
  validate(nil, true)

  set_lines({ 'aaa', 'bbb' })
  validate({ 2 }, true)
  validate({ 1, 2, 3 }, true)

  set_lines({ 'ccc', 'bbb' })
  expect.error(
    function() MiniTest.expect.reference_screenshot(child.get_screenshot(), path, { ignore_lines = { 2 } }) end,
    'screenshot equality to reference at ' .. vim.pesc(vim.inspect(path)) .. '.*Reference:.*Observed:'
  )
end

T['expect']['reference_screenshot()']['respects `opts.ignore_text`'] = function()
  local path = get_ref_path('reference-screenshot')
  child.set_size(5, 12)
  local validate = function(ignore_text, ref)
    eq(MiniTest.expect.reference_screenshot(child.get_screenshot(), path, { ignore_text = ignore_text }), ref)
  end

  set_lines({ 'aaa' })
  validate(nil, true)
  validate(false, true)

  -- Make different text but same highlighting
  set_lines({ 'aaa', 'bbb' })
  local ns_id = child.api.nvim_create_namespace('test-hl')
  child.api.nvim_buf_set_extmark(0, ns_id, 1, 0, { end_row = 2, end_col = 0, hl_group = 'EndOfBuffer', hl_eol = true })

  validate({ 2 }, true)
  validate({ 1, 2, 3 }, true)

  set_lines({ 'ccc', 'bbb' })
  expect.error(
    function() MiniTest.expect.reference_screenshot(child.get_screenshot(), path, { ignore_text = { 2 } }) end,
    'screenshot equality to reference at '
      .. vim.pesc(vim.inspect(path))
      .. '.*Different `text` cell at line 1 column 1%. Reference: "a"%. Observed: "c"%.'
  )
end

T['expect']['reference_screenshot()']['respects `opts.ignore_attr`'] = function()
  local path = get_ref_path('reference-screenshot')
  child.set_size(5, 12)
  local validate = function(ignore_attr, ref)
    eq(MiniTest.expect.reference_screenshot(child.get_screenshot(), path, { ignore_attr = ignore_attr }), ref)
  end

  set_lines({ 'aaa' })
  validate(nil, true)
  validate(false, true)

  -- Make different attr but same text
  local ns_id = child.api.nvim_create_namespace('test-hl')
  child.api.nvim_buf_set_extmark(0, ns_id, 0, 1, { end_row = 0, end_col = 3, hl_group = 'EndOfBuffer' })

  validate({ 1 }, true)
  validate({ 1, 2 }, true)

  expect.error(
    function() MiniTest.expect.reference_screenshot(child.get_screenshot(), path, { ignore_text = { 2 } }) end,
    'screenshot equality to reference at '
      .. vim.pesc(vim.inspect(path))
      .. '.*Different `attr` cell at line 1 column 2%. Reference: "0"%. Observed: "1"%.'
  )
end

T['expect']['reference_screenshot()']['respects `opts.directory`'] = function()
  child.set_size(5, 12)
  set_lines({ 'opts.directory' })
  eq(MiniTest.expect.reference_screenshot(child.get_screenshot(), nil, { directory = 'tests/dir-test' }), true)
  eq(MiniTest.expect.reference_screenshot(child.get_screenshot(), nil, { directory = 'tests/dir-test/' }), true)
end

T['expect']['reference_screenshot()']['works with multibyte characters'] = function()
  child.set_size(5, 12)
  set_lines({ '  1  2' })
  expect.no_error(function() MiniTest.expect.reference_screenshot(child.get_screenshot()) end)
end

T['new_expectation()'] = new_set()

T['new_expectation()']['works'] = function()
  local expect_truthy = MiniTest.new_expectation(
    'truthy',
    function(x) return x end,
    function(x) return 'Object: ' .. vim.inspect(x) end
  )

  expect.error(expect_truthy, 'truthy%..*Object:', false)
  expect.no_error(expect_truthy, 1)
end

T['new_expectation()']['allows string or function arguments'] = function()
  local expect_truthy = MiniTest.new_expectation(
    function() return 'func_truthy' end,
    function(x) return x end,
    'Not truthy'
  )

  expect.error(expect_truthy, 'func_truthy%..*Not truthy', false)
  expect.no_error(expect_truthy, 1)
end

T['new_child_neovim()'] = new_set()

T['new_child_neovim()']['works'] = function()
  finally(function() child.lua('_G.grandchild.stop()') end)
  child.lua('_G.grandchild = MiniTest.new_child_neovim(); _G.grandchild.start()')
  eq(child.lua_get('_G.grandchild.is_running()'), true)
end

T['child'] = new_set()

T['child']['job'] = function()
  eq(type(child.job), 'table')

  child.stop()
  eq(child.job, nil)
end

T['child']['start()'] = new_set()

T['child']['start()']['respects `args` argument'] = function()
  child.stop()

  child.start({ '-c', 'lua _G.inside_args = true' })
  eq(child.lua_get('_G.inside_args'), true)
end

T['child']['start()']['does nothing if already running'] = function()
  finally(function() child.lua('_G.grandchild.stop()') end)
  child.lua('_G.grandchild = MiniTest.new_child_neovim(); _G.grandchild.start()')

  child.lua('_G.should_be_present = true')
  child.lua('_G.grandchild.start()')
  eq(child.lua_get('_G.should_be_present'), true)

  eq(get_latest_message(), '(mini.test) Child process is already running. Use `child.restart()`.')
end

T['child']['stop()'] = function()
  eq(child.is_running(), true)
  child.stop()
  eq(child.is_running(), false)
end

T['child']['restart()'] = new_set()

T['child']['restart()']['respects `args` argument'] = function()
  eq(child.lua_get('_G.inside_args'), vim.NIL)
  child.restart({ '-c', 'lua _G.inside_args = true' })
  eq(child.lua_get('_G.inside_args'), true)
end

T['child']['restart()']['uses `args` from `start()` by default'] = function()
  child.stop()

  child.start({ '-c', 'lua _G.inside_args = true' })
  eq(child.lua_get('_G.inside_args'), true)

  child.restart()
  eq(child.lua_get('_G.inside_args'), true)
end

local validate_child_method = function(method, opts)
  opts = vim.tbl_deep_extend('force', { prevent_hanging = true }, opts or {})

  -- Validate presence of method
  expect.no_error(method)

  -- Validate hanging prevention
  if opts.prevent_hanging then
    child.type_keys('di')
    expect.error(method, opts.name .. '.*child process is blocked')
    -- Unblock for faster test execution
    child.type_keys('<Esc>')
  end

  -- Validate ensuring running
  child.stop()
  expect.error(method, 'Child process is not running')
end

local validate_child_field = function(tbl_name, field_name, value)
  local var = string.format('vim[%s][%s]', vim.inspect(tbl_name), vim.inspect(field_name))

  -- Setting
  child[tbl_name][field_name] = value
  eq(child.lua_get(var), value)

  -- Getting
  eq(child[tbl_name][field_name], child.lua_get(var))
end

T['child']['api'] = function()
  local method = function() return child.api.nvim_buf_set_lines(0, 0, -1, true, { 'aaa' }) end
  validate_child_method(method, { prevent_hanging = false })
end

T['child']['api_notify'] = function()
  local method = function() return child.api_notify.nvim_buf_set_lines(0, 0, -1, true, { 'aaa' }) end
  validate_child_method(method, { prevent_hanging = false })
end

T['child']['redirected method tables'] = new_set({
  parametrize = {
    { 'diagnostic', 'get', { 0 } },
    { 'fn', 'fnamemodify', { '.', ':p' } },
    { 'highlight', 'range', { 0, 1, 'Comment', { 0, 1 }, { 0, 2 } } },
    { 'hl', 'range', { 0, 1, 'Comment', { 0, 1 }, { 0, 2 } } },
    { 'json', 'encode', { { a = 1 } } },
    { 'loop', 'hrtime', {} },
    { 'lsp', 'get_active_clients', {} },
    { 'mpack', 'encode', { { a = 1 } } },
    { 'spell', 'check', { 'thouht' } },
    { 'treesitter', 'get_parser', {} },
    { 'ui', 'select', {} },
    { 'fs', 'normalize', { '/tmp/' } },
  },
  hooks = {
    pre_case = function()
      -- Mock problematic methods
      child.lua('vim.treesitter.get_parser = function() end')
      child.lua('vim.ui.select = function() end')
    end,
  },
})

T['child']['redirected method tables']['method'] = function(tbl_name, field_name, args)
  if tbl_name == 'hl' and child.fn.has('nvim-0.11') == 0 then return end
  local method = function() return child[tbl_name][field_name](unpack(args)) end
  validate_child_method(method, { name = tbl_name .. '.' .. field_name })
end

T['child']['redirected method tables']['field'] = function(tbl_name, field_name, _)
  if tbl_name == 'hl' and child.fn.has('nvim-0.11') == 0 then return end
  -- Although being tables, they should be overridable to allow test doubles
  validate_child_field(tbl_name, field_name, true)
end

T['child']['ui'] = function()
  -- Nothing to actually test due to mandatory function argument
  eq(type(child.ui), 'table')
end

T['child']['scoped variables'] = new_set({ parametrize = { { 'g' }, { 'b' }, { 'w' }, { 't' }, { 'v' }, { 'env' } } })

T['child']['scoped variables']['method'] = function(scope)
  local method = function() return child[scope].char end
  validate_child_method(method, { name = scope })
end

T['child']['scoped variables']['field'] = function(scope) validate_child_field(scope, 'char', 'a') end

T['child']['scoped options'] = new_set({
  parametrize = { { 'o', 'lines', 10 }, { 'go', 'lines', 10 }, { 'bo', 'filetype', 'lua' }, { 'wo', 'number', true } },
})

T['child']['scoped options']['method'] = function(tbl_name, field_name, _)
  local method = function() return child[tbl_name][field_name] end
  validate_child_method(method, { name = tbl_name })
end

T['child']['scoped options']['field'] = function(tbl_name, field_name, value)
  validate_child_field(tbl_name, field_name, value)
end

T['child']['type_keys()'] = new_set()

T['child']['type_keys()']['works'] = function()
  local method = function() child.type_keys('i', 'abc') end
  validate_child_method(method, { prevent_hanging = false })
end

T['child']['type_keys()']['allows strings and arrays of strings'] = function()
  child.type_keys('i', { 'H', 'e', 'l', 'l', 'o' }, ' ', { 'World' }, '<Esc>')
  eq(get_lines(), { 'Hello World' })
end

T['child']['type_keys()']['validates input'] = function()
  local pattern = 'type_keys.*string'

  expect.error(child.type_keys, pattern, 'a', 1)
  expect.error(child.type_keys, pattern, 'a', { 'a', 1 })
end

T['child']['type_keys()']['throws error explicitly'] = function()
  expect.error(child.type_keys, 'E492: Not an editor command: aaa', ':aaa<CR>')
end

T['child']['type_keys()']['respects `wait` argument'] = function()
  local delay = helpers.get_time_const(100)
  local start_time = vim.uv.hrtime()
  child.type_keys(delay, 'i', 'Hello', { 'w', 'o' }, 'rld')
  local end_time = vim.uv.hrtime()
  local duration = (end_time - start_time) * 0.000001
  eq(0.9 * 5 * delay <= duration and duration <= 1.1 * 5 * delay, true)
end

T['child']['cmd()'] = function()
  local method = function() child.cmd([[echomsg 'Hello world']]) end

  method()
  eq(child.cmd_capture('1messages'), 'Hello world')

  validate_child_method(method, { name = 'cmd' })
end

T['child']['cmd_capture()'] = function()
  local method = function() return child.cmd_capture([[echomsg 'Hello world']]) end

  eq(method(), 'Hello world')

  validate_child_method(method, { name = 'cmd_capture' })
end

T['child']['lua()'] = function()
  local method = function() return child.lua('_G.n = 0') end

  eq(child.lua_get('_G.n'), vim.NIL)
  method()
  eq(child.lua_get('_G.n'), 0)

  validate_child_method(method, { name = 'lua' })
end

T['child']['lua_notify()'] = function()
  local method = function() return child.lua_notify('_G.n = 0') end

  eq(child.lua_get('_G.n'), vim.NIL)
  method()
  eq(child.lua_get('_G.n'), 0)

  validate_child_method(method, { prevent_hanging = false })
end

T['child']['lua_get()'] = function()
  local method = function() return child.lua_get('1 + 1') end

  eq(method(), 2)

  validate_child_method(method, { name = 'lua_get' })
end

T['child']['lua_func()'] = function()
  -- Works
  local method = function()
    return child.lua_func(function() return 1 + 1 end)
  end
  eq(method(), 2)

  -- Actually executes function in child neovim
  child.lua('_G.var = 1')
  child.lua_func(function() _G.var = 10 end)
  eq(child.lua_get('_G.var'), 10)

  -- Can take arguments
  eq(child.lua_func(function(a, b) return a + b end, 1, 2), 3)

  -- Has no side effects
  child.lua_func(function() end)
  eq(child.lua_get('f'), vim.NIL)

  -- Can error
  expect.error(function()
    return child.lua_func(function() error('test error') end)
  end, 'test error')

  validate_child_method(method, { name = 'lua_func' })
end

T['child']['is_blocked()'] = function()
  eq(child.is_blocked(), false)

  child.type_keys('di')
  eq(child.is_blocked(), true)

  child.ensure_normal_mode()
  validate_child_method(child.is_blocked, { prevent_hanging = false })
end

T['child']['is_running()'] = function()
  eq(child.is_running(), true)
  child.stop()
  eq(child.is_running(), false)
end

T['child']['ensure_normal_mode()'] = new_set()

T['child']['ensure_normal_mode()']['works'] = new_set({ parametrize = { { 'i' }, { 'v' }, { ':' }, { 'R' } } }, {
  function(keys)
    child.type_keys(keys)
    expect.no_equality(child.api.nvim_get_mode().mode, 'n')
    child.ensure_normal_mode()
    eq(child.api.nvim_get_mode().mode, 'n')
  end,
})

T['child']['ensure_normal_mode()']['ensures running'] = function()
  validate_child_method(child.ensure_normal_mode, { prevent_hanging = false })
end

T['child']['get_screenshot()'] = new_set()

T['child']['get_screenshot()']['ensures running'] = function()
  validate_child_method(child.get_screenshot, { name = 'get_screenshot' })
end

T['child']['get_screenshot()']['works'] = function()
  set_lines({ 'aaa' })
  local screenshot = child.get_screenshot()

  -- Structure
  eq(type(screenshot), 'table')
  eq(islist(screenshot.text), true)
  eq(islist(screenshot.attr), true)

  local n_lines, n_cols = child.o.lines, child.o.columns

  eq(#screenshot.text, n_lines)
  eq(#screenshot.attr, n_lines)

  for i = 1, n_lines do
    eq(islist(screenshot.text[i]), true)
    eq(islist(screenshot.attr[i]), true)

    eq(#screenshot.text[i], n_cols)
    eq(#screenshot.attr[i], n_cols)

    for j = 1, n_cols do
      eq(type(screenshot.text[i][j]), 'string')
      eq(type(screenshot.attr[i][j]), 'string')
    end
  end

  -- Content
  expect.match(table.concat(screenshot.text[1], ''), '^aaa')
  expect.no_equality(screenshot.attr[1][1], screenshot.attr[2][1])
end

T['child']['get_screenshot()']['respects `opts.redraw`'] = function()
  -- This blocks redraw until explicitly called
  child.lua_notify('vim.fn.getchar()')
  set_lines({ 'Should be visible only after redraw' })

  local screenshot = child.get_screenshot({ redraw = false })
  expect.match(table.concat(screenshot.text[1]), '^   ')
  -- - Should be `redraw = true` by default
  screenshot = child.get_screenshot()
  expect.match(table.concat(screenshot.text[1]), '^Should be visible')
end

T['child']['get_screenshot()']['`tostring()`'] = new_set()

T['child']['get_screenshot()']['`tostring()`']['works'] = function()
  set_lines({ 'aaa' })
  local screenshot = child.get_screenshot()
  local lines = vim.split(tostring(screenshot), '\n')
  local n_lines, n_cols = child.o.lines, child.o.columns

  -- "Ruler" + "Lines" + "Empty line" + "Ruler" + "Lines"
  eq(#lines, 2 * n_lines + 3)
  eq(lines[n_lines + 2], '')

  -- Content
  eq(vim.fn.strchars(lines[2]), 3 + n_cols)
  expect.match(lines[2], '^01|aaa')

  eq(vim.fn.strchars(lines[n_lines + 4]), 3 + n_cols)
  expect.no_equality(lines[n_lines + 4]:sub(4, 4), lines[n_lines + 5]:sub(4, 4))
end

T['child']['get_screenshot()']['`tostring()`']['makes proper rulers'] = function()
  local validate = function(ref_ruler)
    local lines = vim.split(tostring(child.get_screenshot()), '\n')
    eq(lines[1], ref_ruler)
    local n = 0.5 * (#lines - 3)
    eq(lines[n + 3], ref_ruler)
  end

  child.set_size(5, 12)
  validate('-|---------|--')

  child.set_size(10, 12)
  validate('--|---------|--')

  child.set_size(100, 20)
  validate('---|---------|---------|')
end

T['child']['get_screenshot()']['`tostring()`']['makes proper line numbers'] = function()
  local validate = function(...)
    local lines = vim.split(tostring(child.get_screenshot()), '\n')
    local n = 0.5 * (#lines - 3)

    for _, ref in ipairs({ ... }) do
      local pattern = '^' .. ref[2] .. '|'
      expect.match(lines[1 + ref[1]], pattern)
      expect.match(lines[n + 3 + ref[1]], pattern)
    end
  end

  child.set_size(5, 12)
  validate({ 1, '1' }, { 5, '5' })

  child.set_size(10, 12)
  validate({ 1, '01' }, { 10, '10' })

  child.set_size(100, 12)
  validate({ 1, '001' }, { 10, '010' }, { 100, '100' })
end

T['child']['get_screenshot()']['works with floating windows'] = function()
  -- This setup should result into displayed text 'bb a': 'bb ' from floating
  -- window, 'aa' - from underneath text
  set_lines({ 'aaaa' })

  local buf_id = child.api.nvim_create_buf(true, true)
  child.api.nvim_buf_set_lines(buf_id, 0, -1, true, { 'bb ' })
  child.api.nvim_open_win(buf_id, false, { relative = 'editor', width = 3, height = 1, row = 0, col = 0 })

  local screenshot = child.get_screenshot()
  eq(screenshot.text[1][1], 'b')
  eq(screenshot.text[1][2], 'b')
  eq(screenshot.text[1][3], ' ')
  eq(screenshot.text[1][4], 'a')
end

-- Integration tests ==========================================================
T['gen_reporter'] = new_set()

T['gen_reporter']['buffer'] = new_set({
  hooks = {
    pre_case = function()
      child.o.termguicolors = true
      child.set_size(70, 120)
    end,
  },
  parametrize = {
    { '' },
    { 'group_depth=2' },
    { 'window={width=0.9*vim.o.columns,col=0.05*vim.o.columns}' },
    { 'window={border="double",title=("a"):rep(200)}' },
  },
}, {
  test = function(opts_element)
    -- Should respect non-empty 'winborder' while preferring explicitly
    -- configured value over it
    if vim.startswith(opts_element, 'window') then
      if child.fn.has('nvim-0.11') == 0 then MiniTest.skip("'winborder' option is present on Neovim>=0.11") end
      child.o.winborder = 'rounded'
    end

    -- Testing "in dynamic" is left for manual approach
    local path = get_ref_path('testref_reporters.lua')
    local reporter_command = string.format('_G.reporter = MiniTest.gen_reporter.buffer({ %s })', opts_element)
    child.lua(reporter_command)

    local execute_command = string.format([[MiniTest.run_file('%s', { execute = { reporter = _G.reporter } })]], path)
    child.lua(execute_command)

    -- Unify path separator for more robust testing. Rely on search and replace
    -- to preserve extmark highlighting.
    if package.config:sub(1, 1) == '\\' then
      local cur_pos = child.api.nvim_win_get_cursor(0)
      child.cmd([[silent! %s^\S\zs\\^/^g]])
      child.cmd('silent! nohlsearch')
      set_cursor(unpack(cur_pos))
    end

    child.expect_screenshot()

    -- Should be able to run several times
    expect.no_error(child.lua, execute_command)
    expect.no_error(child.lua, execute_command)

    -- Should use properly named buffer
    eq(child.api.nvim_buf_get_name(0), 'minitest://' .. child.api.nvim_get_current_buf() .. '/buffer-reporter')
  end,
})

T['gen_reporter']['stdout'] = new_set({
  hooks = {
    pre_case = function()
      child.o.termguicolors = true
      child.set_size(35, 120)
      child.o.laststatus = 0
    end,
  },
  parametrize = { { '' }, { 'TEST_GROUP_DEPTH=2' }, { 'TEST_QUIT_ON_FINISH=false' } },
}, {
  test = function(env_var)
    helpers.skip_on_windows('Terminal tests are designed for Unix')

    -- Testing "in dynamic" is left for manual approach
    local path = 'tests/dir-test/init_stdout-reporter_works.lua'
    local command = string.format([[%s %s --headless --clean -n -u %s]], env_var, vim.v.progpath, vim.inspect(path))
    child.fn.termopen(command)
    -- Wait until check is done and possible process is ended
    vim.uv.sleep(terminal_wait)
    local ignore_attr = child.fn.has('nvim-0.11') == 1 and {} or { 31, 32, 34, 35 }
    child.expect_screenshot({ ignore_attr = ignore_attr })
  end,
})

return T
