local helpers = dofile('tests/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('extra', config) end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
local sleep = function(ms) helpers.sleep(ms, child) end
--stylua: ignore end

-- TODO: Remove after compatibility with Neovim=0.9 is dropped
local islist = vim.fn.has('nvim-0.10') == 1 and vim.islist or vim.tbl_islist

-- Tweak `expect_screenshot()` to test only on Neovim>=0.10 (as it has floating
-- window footer). Use `child.expect_screenshot_orig()` for original testing.
child.expect_screenshot_orig = child.expect_screenshot
child.expect_screenshot = function(opts)
  if child.fn.has('nvim-0.10') == 0 then return end
  child.expect_screenshot_orig(opts)
end

-- Test paths helpers
local path_sep = package.config:sub(1, 1)
local join_path = function(...) return (table.concat({ ... }, path_sep):gsub('([\\/])[\\/]*', '%1')) end
local full_path = function(x) return (child.fn.fnamemodify(x, ':p'):gsub('(.)[\\/]$', '%1')) end

local test_dir = 'tests/dir-extra'
local test_dir_absolute = vim.fn.fnamemodify(test_dir, ':p'):gsub('(.)[\\/]$', '%1')
local real_files_dir = 'tests/dir-extra/real-files'

local make_testpath = function(...) return join_path(test_dir, ...) end

local real_file = function(basename) return join_path(real_files_dir, basename) end

-- Common test wrappers
local forward_lua = function(fun_str)
  local lua_cmd = fun_str .. '(...)'
  return function(...) return child.lua_get(lua_cmd, { ... }) end
end

local forward_lua_notify = function(fun_str)
  local lua_cmd = fun_str .. '(...)'
  return function(...) return child.lua_notify(lua_cmd, { ... }) end
end

local stop_picker = forward_lua('MiniPick.stop')
local get_picker_items = forward_lua('MiniPick.get_picker_items')
local get_picker_matches = forward_lua('MiniPick.get_picker_matches')
local is_picker_active = forward_lua('MiniPick.is_picker_active')

-- Common test helpers
local validate_buf_name = function(buf_id, name)
  buf_id = buf_id or child.api.nvim_get_current_buf()
  name = name ~= '' and full_path(name) or ''
  eq(child.api.nvim_buf_get_name(buf_id), name)
end

local validate_edit = function(lines_before, cursor_before, keys, lines_after, cursor_after)
  child.ensure_normal_mode()
  set_lines(lines_before)
  set_cursor(cursor_before[1], cursor_before[2])

  type_keys(keys)

  eq(get_lines(), lines_after)
  eq(get_cursor(), cursor_after)

  child.ensure_normal_mode()
end

local validate_edit1d = function(line_before, col_before, keys, line_after, col_after)
  validate_edit({ line_before }, { 1, col_before }, keys, { line_after }, { 1, col_after })
end

local validate_selection = function(selection_from, selection_to, visual_mode)
  eq(child.fn.mode(), visual_mode or 'v')

  -- Compute two correctly ordered edges
  local from = { child.fn.line('v'), child.fn.col('v') - 1 }
  local to = { child.fn.line('.'), child.fn.col('.') - 1 }
  if to[1] < from[1] or (to[1] == from[1] and to[2] < from[2]) then
    from, to = to, from
  end
  eq(from, selection_from)
  eq(to, selection_to)
end

local validate_picker_name = function(ref_name) eq(child.lua_get('MiniPick.get_picker_opts().source.name'), ref_name) end

local validate_picker_cwd = function(ref_cwd) eq(child.lua_get('MiniPick.get_picker_opts().source.cwd'), ref_cwd) end

local validate_partial_equal_arr = function(test_arr, ref_arr)
  -- Same length
  eq(#test_arr, #ref_arr)

  -- Partial values
  local test_arr_mod = {}
  for i = 1, #ref_arr do
    local test_with_ref_keys = {}
    for key, _ in pairs(ref_arr[i]) do
      test_with_ref_keys[key] = test_arr[i][key]
    end
    test_arr_mod[i] = test_with_ref_keys
  end
  eq(test_arr_mod, ref_arr)
end

local get_extra_picker_extmarks = function(from, to)
  local ns_id = child.api.nvim_get_namespaces().MiniExtraPickers
  local extmarks = child.api.nvim_buf_get_extmarks(0, ns_id, from, to, { details = true })
  return vim.tbl_map(function(x) return { row = x[2], col = x[3], hl_group = x[4].hl_group } end, extmarks)
end

-- Common mocks
local mock_win_functions = function() child.cmd('source tests/dir-extra/mocks/mock-win-functions.lua') end

local mock_fn_executable = function(available_executables)
  local lua_cmd = string.format(
    'vim.fn.executable = function(x) return vim.tbl_contains(%s, x) and 1 or 0 end',
    vim.inspect(available_executables)
  )
  child.lua(lua_cmd)
end

local mock_git_repo = function(repo_dir)
  mock_fn_executable({ 'git' })

  local lua_cmd = string.format(
    [[
      _G.systemlist_orig = _G.systemlist_orig or vim.fn.systemlist
      vim.fn.systemlist = function(...)
        _G.systemlist_args = {...}
        return %s
      end]],
    vim.inspect({ repo_dir })
  )
  child.lua(lua_cmd)
end

local mock_no_git_repo = function()
  mock_fn_executable({ 'git' })
  child.lua([[
    _G.systemlist_orig = _G.systemlist_orig or vim.fn.systemlist
    -- Mock shell error after running check for Git repo
    vim.fn.systemlist = function() return _G.systemlist_orig('non-existing-cli-command') end
  ]])
end

local validate_git_repo_check = function(target_dir)
  eq(child.lua_get('_G.systemlist_args'), { { 'git', '-C', target_dir, 'rev-parse', '--show-toplevel' } })
end

local clear_git_repo_check = function() child.lua('_G.systemlist_args = nil') end

local mock_spawn = function()
  local mock_file = join_path(test_dir, 'mocks', 'spawn.lua')
  local lua_cmd = string.format('dofile(%s)', vim.inspect(mock_file))
  child.lua(lua_cmd)
end

local mock_stdout_feed = function(feed) child.lua('_G.stdout_data_feed = ' .. vim.inspect(feed)) end

local mock_stderr_feed = function(feed) child.lua('_G.stderr_data_feed = ' .. vim.inspect(feed)) end

local mock_cli_return = function(lines)
  mock_stdout_feed({ table.concat(lines, '\n') })
  mock_stderr_feed({})
end

local get_spawn_log = function() return child.lua_get('_G.spawn_log') end

local clear_spawn_log = function() child.lua('_G.spawn_log = {}') end

local validate_spawn_log = function(ref, index)
  local present = get_spawn_log()
  if type(index) == 'number' then present = present[index] end
  eq(present, ref)
end

local get_process_log = function() return child.lua_get('_G.process_log') end

local clear_process_log = function() child.lua('_G.process_log = {}') end

-- Mock consistent paths for more robust screenshot testing
local mock_slash_path_sep = function()
  if path_sep == '/' then return end
  child.lua([[
    _G.fnamemodify_orig = vim.fn.fnamemodify
    vim.fn.fnamemodify = function(...)
      return (_G.fnamemodify_orig(...):gsub('\\', '/'))
    end

    _G.getcwd_orig = vim.fn.getcwd
    vim.fn.getcwd = function() return (getcwd_orig():gsub('\\', '/')) end
  ]])
end

local unmock_slash_path_sep = function()
  if path_sep == '/' then return end
  child.lua([[
    package.config = _G.package_config_orig
    vim.fn.fnamemodify, vim.fn.getcwd = _G.fnamemodify_orig, _G.getcwd_orig
  ]])
end

-- Time constants
local small_time = helpers.get_time_const(10)

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()

      -- Make more comfortable screenshots
      child.o.laststatus = 0
      child.o.ruler = false
      child.set_size(15, 40)
    end,
    post_once = child.stop,
  },
  n_retry = helpers.get_n_retry(2),
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  child.lua([[require('mini.extra').setup()]])

  -- Global variable
  eq(child.lua_get('type(_G.MiniExtra)'), 'table')
end

T['setup()']['pickers are added to `MiniPick.registry`'] = new_set(
  { parametrize = { { 'pick_first' }, { 'extra_first' } } },
  {
    test = function(init_order)
      if init_order == 'extra_first' then
        load_module()
        child.lua([[require('mini.pick').setup()]])
      end
      if init_order == 'pick_first' then
        child.lua([[require('mini.pick').setup()]])
        load_module()
      end

      local extra_pickers = child.lua_get('vim.tbl_keys(MiniExtra.pickers)')
      for _, picker_name in ipairs(extra_pickers) do
        local lua_cmd = string.format([[type(MiniPick.registry['%s'])]], picker_name)
        eq(child.lua_get(lua_cmd), 'function')
      end
    end,
  }
)

T['setup()']['does not override user picker in `MiniPick.registry`'] = function()
  child.lua([[
    require('mini.pick').setup()
    MiniPick.registry.buf_lines = function() _G.hello = 'world' end
  ]])
  load_module()
  child.lua_notify('MiniPick.registry.buf_lines()')
  eq(child.lua_get('_G.hello'), 'world')
end

T['gen_ai_spec'] = new_set({ hooks = { pre_case = load_module } })

T['gen_ai_spec']['buffer()'] = new_set()

T['gen_ai_spec']['buffer()']['works as `a` textobject'] = function()
  child.lua([[require('mini.ai').setup({ custom_textobjects = { B = MiniExtra.gen_ai_spec.buffer() } })]])

  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'caB', 'xx', '<Esc>' }, { 'xx' }, { 1, 1 })
  validate_edit({ 'aa', 'bb' }, { 2, 0 }, { 'caB', 'xx', '<Esc>' }, { 'xx' }, { 1, 1 })

  local validate_delete = function(lines_before, cursor_before)
    validate_edit(lines_before, cursor_before, { 'daB' }, { '' }, { 1, 0 })
  end

  validate_delete({ '', ' ', '\t', 'aa', '\t', ' ', '' }, { 1, 0 })
  validate_delete({ '', ' ', '\t', 'aa', '\t', ' ', '' }, { 4, 0 })
  validate_delete({ '', 'aa', '', 'cc', '' }, { 1, 0 })

  validate_delete({ 'aa' }, { 1, 0 })
  validate_delete({ 'aa', '' }, { 1, 0 })
  validate_delete({ '' }, { 1, 0 })
  validate_delete({ ' ', ' ', ' ' }, { 1, 0 })

  -- Should work with dot-repeat
  local buf_id_2 = child.api.nvim_create_buf(true, false)
  child.api.nvim_buf_set_lines(buf_id_2, 0, -1, false, { ' ', 'bb', ' ' })

  set_lines({ ' ', 'aa', ' ' })
  type_keys('caB', 'xx', '<Esc>')
  eq(get_lines(), { 'xx' })
  child.api.nvim_set_current_buf(buf_id_2)
  type_keys('.')
  eq(get_lines(), { 'xx' })
end

T['gen_ai_spec']['buffer()']['works as `i` textobject'] = function()
  child.lua([[require('mini.ai').setup({ custom_textobjects = { B = MiniExtra.gen_ai_spec.buffer() } })]])

  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'ciB', 'xx', '<Esc>' }, { 'xx' }, { 1, 1 })
  validate_edit({ 'aa', 'bb' }, { 2, 0 }, { 'ciB', 'xx', '<Esc>' }, { 'xx' }, { 1, 1 })

  local lines_with_blanks = { '', ' ', '\t', 'aa', '\t', ' ', '' }
  validate_edit(lines_with_blanks, { 1, 0 }, { 'diB' }, { '', ' ', '\t', '', '\t', ' ', '' }, { 4, 0 })
  validate_edit(lines_with_blanks, { 4, 0 }, { 'diB' }, { '', ' ', '\t', '', '\t', ' ', '' }, { 4, 0 })

  validate_edit({ '', 'aa', '', 'cc', '' }, { 1, 0 }, { 'ciB', 'xx', '<Esc>' }, { '', 'xx', '' }, { 2, 1 })
  validate_edit({ '  aa', '  ', 'bb  ' }, { 1, 0 }, { 'ciB', 'xx', '<Esc>' }, { 'xx' }, { 1, 1 })

  validate_edit({ 'aa' }, { 1, 0 }, { 'diB' }, { '' }, { 1, 0 })
  validate_edit({ 'aa', '' }, { 1, 0 }, { 'diB' }, { '', '' }, { 1, 0 })
  validate_edit({ '', 'aa' }, { 1, 0 }, { 'diB' }, { '', '' }, { 2, 0 })
  validate_edit({ '' }, { 1, 0 }, { 'diB' }, { '' }, { 1, 0 })
  validate_edit({ ' ', ' ', ' ' }, { 1, 0 }, { 'diB' }, { ' ', ' ', ' ' }, { 1, 0 })

  -- Should work with dot-repeat
  local buf_id_2 = child.api.nvim_create_buf(true, false)
  child.api.nvim_buf_set_lines(buf_id_2, 0, -1, false, { ' ', '  bb', ' ' })

  set_lines({ ' ', '  aa', ' ' })
  type_keys('ciB', 'xx', '<Esc>')
  eq(get_lines(), { ' ', 'xx', ' ' })
  child.api.nvim_set_current_buf(buf_id_2)
  type_keys('.')
  eq(get_lines(), { ' ', 'xx', ' ' })
end

T['gen_ai_spec']['diagnostic()'] = new_set({
  hooks = {
    pre_case = function()
      local mock_path = make_testpath('mocks', 'diagnostic.lua')
      child.lua(string.format('dofile(%s)', vim.inspect(mock_path)))
    end,
  },
})

T['gen_ai_spec']['diagnostic()']['works'] = function()
  child.lua([[require('mini.ai').setup({ custom_textobjects = { D = MiniExtra.gen_ai_spec.diagnostic() } })]])
  local buf_cur, buf_other = child.api.nvim_get_current_buf(), child.lua_get('_G.buf_id_1')

  local validate = function(ai_type)
    child.ensure_normal_mode()
    child.api.nvim_set_current_buf(buf_cur)
    set_cursor(1, 0)

    type_keys('v', ai_type, 'D')
    validate_selection({ 1, 0 }, { 1, 4 })

    -- Consecutive application should work
    type_keys(ai_type, 'D')
    validate_selection({ 2, 0 }, { 2, 6 })

    -- Should support `[count]`
    type_keys('2', ai_type, 'D')
    validate_selection({ 4, 0 }, { 4, 3 })

    -- Should support `next`/`prev`
    type_keys(ai_type, 'l', 'D')
    validate_selection({ 3, 0 }, { 3, 3 })

    type_keys(ai_type, 'n', 'D')
    validate_selection({ 4, 0 }, { 4, 3 })

    -- Different buffer
    child.ensure_normal_mode()
    child.api.nvim_set_current_buf(buf_other)
    set_cursor(2, 0)
    type_keys('v', ai_type, 'D')
    validate_selection({ 2, 2 }, { 2, 6 })
  end

  -- Both `a` and `i` should behave the same
  validate('a')
  validate('i')
end

T['gen_ai_spec']['diagnostic()']['respects `severity` argument'] = function()
  child.lua([[require('mini.ai').setup({
    custom_textobjects = { D = MiniExtra.gen_ai_spec.diagnostic(vim.diagnostic.severity.WARN) },
  })]])
  local buf_other = child.lua_get('_G.buf_id_1')
  child.api.nvim_set_current_buf(buf_other)

  local validate = function(ai_type)
    child.ensure_normal_mode()
    set_cursor(1, 0)

    type_keys('v', ai_type, 'D')
    validate_selection({ 1, 6 }, { 1, 12 })
    type_keys(ai_type, 'D')
    validate_selection({ 3, 2 }, { 3, 8 })
  end

  validate('a')
  validate('i')
end

T['gen_ai_spec']['indent()'] = new_set()

local ai_indent = function(...) return child.lua_get('MiniExtra.gen_ai_spec.indent()(...)', { ... }) end

T['gen_ai_spec']['indent()']['works as `a` textobject'] = function()
  child.lua([[require('mini.ai').setup({ custom_textobjects = { I = MiniExtra.gen_ai_spec.indent() } })]])

  set_lines({ 'aa', ' bb', '  cc', ' bb', 'aa', ' bb', 'aa', ' bb', 'aa' })

  set_cursor(3, 0)
  type_keys('v', 'aI')
  validate_selection({ 2, 0 }, { 4, 3 })

  -- Consecutive application should work
  type_keys('aI')
  validate_selection({ 1, 0 }, { 5, 2 })

  -- Should support `[count]`
  type_keys('2aI')
  validate_selection({ 7, 0 }, { 9, 2 })

  -- Should support `next`/`prev`
  type_keys('alI')
  validate_selection({ 5, 0 }, { 7, 2 })

  type_keys('anI')
  validate_selection({ 7, 0 }, { 9, 2 })
end

T['gen_ai_spec']['indent()']['works as `i` textobject'] = function()
  child.lua([[require('mini.ai').setup({ custom_textobjects = { I = MiniExtra.gen_ai_spec.indent() } })]])

  set_lines({ 'aa', ' bb', '  cc', ' bb', 'aa', ' bb', 'aa', ' bb', 'aa' })

  set_cursor(3, 0)
  type_keys('v', 'iI')
  validate_selection({ 3, 2 }, { 3, 3 })

  -- Consecutive application should work
  type_keys('iI')
  validate_selection({ 2, 1 }, { 4, 2 })

  -- Should support `[count]`
  type_keys('2iI')
  validate_selection({ 8, 1 }, { 8, 2 })

  -- Should support `next`/`prev`
  type_keys('ilI')
  validate_selection({ 6, 1 }, { 6, 2 })

  type_keys('inI')
  validate_selection({ 8, 1 }, { 8, 2 })
end

T['gen_ai_spec']['indent()']['works when started on blank line'] = function()
  child.lua([[require('mini.ai').setup({ custom_textobjects = { I = MiniExtra.gen_ai_spec.indent() } })]])
  set_lines({ 'aa', '', '   ', ' bb', 'aa' })
  local validate = function(line, col)
    child.ensure_normal_mode()
    set_cursor(line, col)
    type_keys('v', 'aI')
    validate_selection({ 1, 0 }, { 5, 2 })
  end

  validate(2, 0)
  validate(3, 2)
end

T['gen_ai_spec']['indent()']['returns correct structure'] = function()
  set_lines({ 'aa', ' bb', '  cc', ' bb', 'aa' })
  eq(ai_indent('a'), {
    { from = { line = 1, col = 1 }, to = { line = 5, col = 3 } },
    { from = { line = 2, col = 1 }, to = { line = 4, col = 4 } },
  })
  eq(ai_indent('i'), {
    { from = { line = 2, col = 2 }, to = { line = 4, col = 3 } },
    { from = { line = 3, col = 3 }, to = { line = 3, col = 4 } },
  })
end

local validate_ai_indent = function(ref_region_lines)
  local output = ai_indent('a')
  local output_region_lines = {}
  for _, region in ipairs(output) do
    table.insert(output_region_lines, { region.from.line, region.to.line })
  end
  eq(output_region_lines, ref_region_lines)
end

T['gen_ai_spec']['indent()']['works with tabs'] = function()
  -- When only tabs are present
  set_lines({ 'aa', '\tbb', '\t\tcc', '\tbb', 'aa' })
  validate_ai_indent({ { 1, 5 }, { 2, 4 } })

  -- Should respect 'tabstop' if tabs and spaces are mixed
  child.o.tabstop = 3
  set_lines({ '   aa', '    cc', '\t\txx', ' \tyy', '   aa' })
  validate_ai_indent({ { 1, 5 }, { 2, 4 } })
end

T['gen_ai_spec']['indent()']['ignores blank lines indent when computing scopes'] = function()
  set_lines({ 'aa', ' bb', '    ', '', 'aa' })
  validate_ai_indent({ { 1, 5 } })
end

T['gen_ai_spec']['indent()']['includes edge blank lines in `i` textobject'] = function()
  set_lines({ 'aa', '', '  ', ' bb', '  ', '', 'aa' })
  validate_ai_indent({ { 1, 7 } })
end

T['gen_ai_spec']['indent()']['ignores not enclosed regions'] = function()
  set_lines({ '', '  ', 'aa', ' bb', 'aa', '  ', '' })
  validate_ai_indent({ { 3, 5 } })

  set_lines({ '', '  ', 'aa', '  ', '' })
  validate_ai_indent({})
end

T['gen_ai_spec']['indent()']['does not include scopes with only blank inside'] = function()
  set_lines({ 'aa', ' bb', '  ', '', '  ', ' bb', 'aa' })
  validate_ai_indent({ { 1, 7 } })
end

T['gen_ai_spec']['indent()']['casts rays from top to bottom'] = function()
  -- NOTE: Not necessarily a good feature, but a documented behavior
  set_lines({ ' bb', '   dd', '  cc', 'aa' })
  validate_ai_indent({ { 1, 4 } })
end

T['gen_ai_spec']['line()'] = new_set()

T['gen_ai_spec']['line()']['works as `a` textobject'] = function()
  child.lua([[require('mini.ai').setup({ custom_textobjects = { L = MiniExtra.gen_ai_spec.line() } })]])

  validate_edit1d('aa', 0, { 'caL', 'xx', '<Esc>' }, 'xx', 1)
  validate_edit1d('  aa', 0, { 'caL', 'xx', '<Esc>' }, 'xx', 1)
  validate_edit1d('\taa', 0, { 'caL', 'xx', '<Esc>' }, 'xx', 1)
  validate_edit1d('  aa', 2, { 'caL', 'xx', '<Esc>' }, 'xx', 1)

  -- Should operate charwise inside a line
  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 1 }, { 'daL' }, { '', 'bb', 'cc' }, { 1, 0 })
  validate_edit({ 'aa', 'bb', 'cc' }, { 2, 1 }, { 'daL' }, { 'aa', '', 'cc' }, { 2, 0 })
  validate_edit({ 'aa', 'bb', 'cc' }, { 3, 1 }, { 'daL' }, { 'aa', 'bb', '' }, { 3, 0 })

  -- Should work with dot-repeat
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'caL', 'xx', '<Esc>', 'j', '.' }, { 'xx', 'xx' }, { 2, 1 })
end

T['gen_ai_spec']['line()']['works as `i` textobject'] = function()
  child.lua([[require('mini.ai').setup({ custom_textobjects = { L = MiniExtra.gen_ai_spec.line() } })]])

  validate_edit1d('aa', 0, { 'ciL', 'xx', '<Esc>' }, 'xx', 1)
  validate_edit1d('  aa', 0, { 'ciL', 'xx', '<Esc>' }, '  xx', 3)
  validate_edit1d('\taa', 0, { 'ciL', 'xx', '<Esc>' }, '\txx', 2)
  validate_edit1d(' \taa', 0, { 'ciL', 'xx', '<Esc>' }, ' \txx', 3)
  validate_edit1d('  aa', 2, { 'ciL', 'xx', '<Esc>' }, '  xx', 3)

  -- Should operate charwise inside a line
  validate_edit({ '  aa', '  bb', '  cc' }, { 1, 1 }, { 'diL' }, { '  ', '  bb', '  cc' }, { 1, 1 })
  validate_edit({ '  aa', '  bb', '  cc' }, { 2, 1 }, { 'diL' }, { '  aa', '  ', '  cc' }, { 2, 1 })
  validate_edit({ '  aa', '  bb', '  cc' }, { 3, 1 }, { 'diL' }, { '  aa', '  bb', '  ' }, { 3, 1 })

  -- Should work with dot-repeat
  validate_edit({ '  aa', '  bb' }, { 1, 0 }, { 'ciL', 'xx', '<Esc>', 'j', '.' }, { '  xx', '  xx' }, { 2, 3 })
end

T['gen_ai_spec']['number()'] = new_set()

T['gen_ai_spec']['number()']['works as `a` textobject'] = function()
  child.lua([[require('mini.ai').setup({ custom_textobjects = { N = MiniExtra.gen_ai_spec.number() } })]])

  set_lines({ '111', '-222', '3.33', '-4.44' })

  set_cursor(1, 0)
  type_keys('v', 'aN')
  validate_selection({ 1, 0 }, { 1, 2 })

  -- Consecutive application should work
  type_keys('aN')
  validate_selection({ 2, 0 }, { 2, 3 })

  -- Should support `[count]`
  type_keys('2aN')
  validate_selection({ 4, 0 }, { 4, 4 })

  -- Should support `next`/`prev`
  type_keys('alN')
  validate_selection({ 3, 0 }, { 3, 3 })

  type_keys('anN')
  validate_selection({ 4, 0 }, { 4, 4 })
end

--stylua: ignore
T['gen_ai_spec']['number()']['works as `a` in all necessary cases'] = function()
  child.lua([[require('mini.ai').setup({ custom_textobjects = { N = MiniExtra.gen_ai_spec.number() } })]])

  local validate = function(number_string)
    local ref_output = number_string:gsub('.', 'x')
    validate_edit1d(number_string, 0, {'vaN', 'rx'}, ref_output, 0)
  end

  validate('1')
  validate('11')
  validate('-2')
  validate('-22')
  validate('3.3')
  validate('3.33')
  validate('33.3')
  validate('-4.4')
  validate('-4.44')
  validate('-44.4')

  validate('00')
  validate('-00')
  validate('00.00')
  validate('-00.00')

  validate_edit1d('-.11', 0, { 'vaN', 'rx' }, '-.xx', 2)
  validate_edit1d('.11',  0, { 'vaN', 'rx' }, '.xx',  1)
end

T['gen_ai_spec']['number()']['works as `i` textobject'] = function()
  child.lua([[require('mini.ai').setup({ custom_textobjects = { N = MiniExtra.gen_ai_spec.number() } })]])

  set_lines({ '11.2-33 44' })

  set_cursor(1, 0)
  type_keys('v', 'iN')
  validate_selection({ 1, 0 }, { 1, 1 })

  -- Consecutive application should work
  type_keys('iN')
  validate_selection({ 1, 3 }, { 1, 3 })

  -- Should support `[count]`
  type_keys('2iN')
  validate_selection({ 1, 8 }, { 1, 9 })

  -- Should support `next`/`prev`
  type_keys('ilN')
  validate_selection({ 1, 5 }, { 1, 6 })

  type_keys('inN')
  validate_selection({ 1, 8 }, { 1, 9 })
end

T['gen_ai_spec']['number()']['works as `i` in all necessary cases'] = function()
  child.lua([[require('mini.ai').setup({ custom_textobjects = { N = MiniExtra.gen_ai_spec.number() } })]])

  local validate = function(line_before, line_after, col_after)
    validate_edit1d(line_before, 0, { 'viN', 'rx' }, line_after, col_after)
  end

  validate('1', 'x', 0)
  validate('11', 'xx', 0)
  validate('-2', '-x', 1)
  validate('-22', '-xx', 1)
  validate(' 3.3', ' x.3', 1)
  validate(' 3.33', ' x.33', 1)
  validate('33.3', 'xx.3', 0)
  validate('-4.4', '-x.4', 1)
  validate('-4.44', '-x.44', 1)
  validate('-44.4', '-xx.4', 1)

  validate('00', 'xx', 0)
  validate('-00', '-xx', 1)
  validate('00.00', 'xx.00', 0)
  validate('-00.00', '-xx.00', 1)

  validate('.11', '.xx', 1)
  validate('-.11', '-.xx', 2)
  validate_edit1d('11.22', 3, { 'viN', 'rx' }, '11.xx', 3)
end

T['gen_ai_spec']['number()']['works with cursor on any part of match'] = function()
  child.lua([[require('mini.ai').setup({ custom_textobjects = { N = MiniExtra.gen_ai_spec.number() } })]])

  -- `a` textobject
  set_lines({ '-123.456 789' })
  for i = 0, 7 do
    child.ensure_normal_mode()
    set_cursor(1, i)
    type_keys('v', 'aN')
    validate_selection({ 1, 0 }, { 1, 7 })
  end

  -- `i` textobject
  for i = 8, 11 do
    child.ensure_normal_mode()
    set_cursor(1, i)
    type_keys('v', 'iN')
    validate_selection({ 1, 9 }, { 1, 11 })
  end
end

T['gen_highlighter'] = new_set({ hooks = { pre_case = load_module } })

T['gen_highlighter']['words()'] = new_set()

local hi_words = forward_lua('MiniExtra.gen_highlighter.words')

T['gen_highlighter']['words()']['works'] = function()
  eq(hi_words({ 'aaa' }, 'Error'), { pattern = { '%f[%w]()aaa()%f[%W]' }, group = 'Error' })
  eq(
    hi_words({ 'aaa', 'bbb' }, 'Error'),
    { pattern = { '%f[%w]()aaa()%f[%W]', '%f[%w]()bbb()%f[%W]' }, group = 'Error' }
  )

  -- Should escape special characters
  eq(hi_words({ 'a.+?-b' }, 'Error'), { pattern = { '%f[%w]()a%.%+%?%-b()%f[%W]' }, group = 'Error' })

  -- Should use `extmark_opts` as is
  eq(
    hi_words({ 'aaa' }, 'Error', { priority = 100 }),
    { pattern = { '%f[%w]()aaa()%f[%W]' }, group = 'Error', extmark_opts = { priority = 100 } }
  )
end

T['gen_highlighter']['words()']['validates arguments'] = function()
  expect.error(function() hi_words('todo', 'Error') end, '`words`.*array')
  expect.error(function() hi_words({ 1 }, 'Error') end, '`words`.*strings')
  expect.error(function() hi_words({ 'todo' }, 1) end, '`group`.*string or callable')
end

T['pickers'] = new_set({
  hooks = {
    pre_case = function()
      load_module()
      child.lua([[require('mini.pick').setup()]])

      -- Make some UI elements differentiable in screenshots
      child.cmd('hi MiniPickBorder guifg=Red ctermfg=1')
      child.cmd('hi MiniPickPrompt guifg=Green ctermfg=2')
      child.cmd('hi MiniPickPromptCaret guifg=Yellow ctermfg=3')
      child.cmd('hi MiniPickPromptPrefix guifg=Azure ctermfg=4')
    end,
  },
})

local validate_active_picker = function() eq(child.lua_get('require("mini.pick").get_picker_state() ~= nil'), true) end

local validate_global_source_options = function(picker_start, check_preview, check_choose)
  child.lua([[
    MiniPick.config.source.preview = function(buf_id, item)
      vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, { "My preview" })
      _G.custom_preview = true
    end
    MiniPick.config.source.choose = function(item)
      _G.custom_choose = true
    end
  ]])
  picker_start()
  local ref_custom_preview = check_preview == false and vim.NIL or true
  type_keys('<Tab>')
  eq(child.lua_get('_G.custom_preview'), ref_custom_preview)
  local ref_custom_choose = check_choose == false and vim.NIL or true
  type_keys('<CR>')
  eq(child.lua_get('_G.custom_choose'), ref_custom_choose)
  type_keys('<C-c>')
end

T['pickers']["validate no 'mini.pick'"] = function()
  child.lua([[require = function(module) error() end]])

  local extra_pickers = child.lua_get('vim.tbl_keys(MiniExtra.pickers)')
  for _, picker_name in ipairs(extra_pickers) do
    local err_pattern = '%(mini%.extra%) `pickers%.' .. picker_name .. "%(%)` requires 'mini%.pick'"

    expect.error(function()
      local lua_cmd = string.format([[MiniExtra.pickers['%s']()]], picker_name)
      child.lua(lua_cmd)
    end, err_pattern)
  end
end

T['pickers']['buf_lines()'] = new_set()

local pick_buf_lines = forward_lua_notify('MiniExtra.pickers.buf_lines')

local setup_buffers = function()
  -- Normal buffer with name
  local buf_id_1 = child.api.nvim_create_buf(true, false)
  child.api.nvim_buf_set_lines(buf_id_1, 0, -1, false, { 'This is', '  buffer 1' })
  child.api.nvim_buf_set_name(buf_id_1, 'buffer-1')

  -- Normal buffer without name
  local buf_id_2 = child.api.nvim_create_buf(true, false)
  child.api.nvim_buf_set_lines(buf_id_2, 0, -1, false, { 'This is', '  buffer 2' })

  -- Normal buffer without lines
  local buf_id_3 = child.api.nvim_create_buf(true, false)

  -- Not listed normal buffer
  local buf_id_4 = child.api.nvim_create_buf(false, false)

  -- Not normal buffer
  local buf_id_5 = child.api.nvim_create_buf(false, true)

  -- Set current buffer
  local buf_init = child.api.nvim_get_current_buf()
  child.api.nvim_set_current_buf(buf_id_1)
  child.api.nvim_buf_delete(buf_init, { force = true })

  return { buf_id_1, buf_id_2, buf_id_3, buf_id_4, buf_id_5 }
end

T['pickers']['buf_lines()']['works'] = function()
  local buffers = setup_buffers()

  child.lua_notify('_G.return_item = MiniExtra.pickers.buf_lines()')
  validate_picker_name('Buffer lines (all)')
  child.expect_screenshot()

  -- Should properly choose (and also support choosing in same buffer)
  type_keys('<C-n>')
  type_keys('<CR>')
  validate_buf_name(0, 'buffer-1')
  eq(get_cursor(), { 2, 0 })

  -- Should return chosen value with proper structure
  eq(child.lua_get('_G.return_item'), { bufnr = buffers[1], lnum = 2, text = 'buffer-1\0002\000  buffer 1' })

  -- Should work without set up 'mini.pick'
  child.mini_unload('pick')
  pick_buf_lines()
  validate_active_picker()
end

T['pickers']['buf_lines()']['respects `local_opts.scope`'] = function()
  setup_buffers()
  pick_buf_lines({ scope = 'current' })
  validate_picker_name('Buffer lines (current)')
  child.expect_screenshot()
end

T['pickers']['buf_lines()']['respects `local_opts.preserve_order`'] = function()
  set_lines({ 'axay', 'b', 'aaxy', 'ccc', 'xaa' })
  pick_buf_lines({ scope = 'current', preserve_order = true })

  type_keys('x')
  eq(get_picker_matches().all_inds, { 1, 3, 5 })
  type_keys('y')
  eq(get_picker_matches().all_inds, { 1, 3 })
end

T['pickers']['buf_lines()']['pads line numbers'] = function()
  local set_n_lines = function(buf_id, prefix, n)
    local lines = {}
    for i = 1, n do
      lines[i] = prefix .. '-' .. i
    end
    child.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
  end

  local buf_id_1 = child.api.nvim_create_buf(true, false)
  set_n_lines(buf_id_1, 'buf-1', 9)

  local buf_id_2 = child.api.nvim_create_buf(true, false)
  set_n_lines(buf_id_2, 'buf-2', 10)

  local buf_id_3 = child.api.nvim_create_buf(true, false)
  set_n_lines(buf_id_3, 'buf-3', 99)

  local buf_id_4 = child.api.nvim_create_buf(true, false)
  set_n_lines(buf_id_4, 'buf-4', 100)

  -- Should pad line numbers to achieve more aligned look
  child.lua_notify('MiniExtra.pickers.buf_lines()')
  sleep(small_time)
  local items = get_picker_items()

  local validate_has_item_with_text = function(text)
    local res = false
    for _, item in ipairs(items) do
      if item.text == text then res = true end
    end
    eq(res, true)
  end

  validate_has_item_with_text('\0001\000buf-1-1')
  validate_has_item_with_text('\0009\000buf-1-9')

  validate_has_item_with_text('\000 1\000buf-2-1')
  validate_has_item_with_text('\000 9\000buf-2-9')
  validate_has_item_with_text('\00010\000buf-2-10')

  validate_has_item_with_text('\000 1\000buf-3-1')
  validate_has_item_with_text('\00099\000buf-3-99')

  validate_has_item_with_text('\000  1\000buf-4-1')
  validate_has_item_with_text('\000 99\000buf-4-99')
  validate_has_item_with_text('\000100\000buf-4-100')

  type_keys('<C-c>')

  -- Should work with `scope='current'`
  child.api.nvim_set_current_buf(buf_id_4)
  child.lua_notify('MiniExtra.pickers.buf_lines({ scope = "current" })')
  sleep(small_time)
  items = get_picker_items()

  validate_has_item_with_text('  1\000buf-4-1')
  validate_has_item_with_text(' 99\000buf-4-99')
  validate_has_item_with_text('100\000buf-4-100')
  type_keys('<C-c>')
end

T['pickers']['buf_lines()']['can not show icons'] = function()
  setup_buffers()
  child.lua('MiniPick.config.source.show = MiniPick.default_show')
  pick_buf_lines()
  child.expect_screenshot()
end

T['pickers']['buf_lines()']['respects `opts`'] = function()
  pick_buf_lines({}, { source = { name = 'My name' } })
  validate_picker_name('My name')
end

T['pickers']['buf_lines()']['respects global source options'] = function()
  validate_global_source_options(pick_buf_lines, true, true)
end

T['pickers']['buf_lines()']['validates arguments'] = function()
  local validate = function(local_opts, error_pattern)
    expect.error(function() child.lua('MiniExtra.pickers.buf_lines(...)', { local_opts }) end, error_pattern)
  end
  validate({ scope = '1' }, '`pickers%.buf_lines`.*"scope".*"1".*one of')
end

T['pickers']['colorschemes()'] = new_set()

local pick_colorschemes = forward_lua_notify('MiniExtra.pickers.colorschemes')

T['pickers']['colorschemes()']['works'] = function()
  child.lua_notify('_G.return_item = MiniExtra.pickers.colorschemes()')
  validate_picker_name('Colorschemes')
  type_keys('^mini')

  -- Should find bundled 'mini*' color schemes
  child.expect_screenshot({ ignore_text = { 14 } })

  -- Should have proper preview
  type_keys('<Tab>')
  eq(child.g.colors_name, 'miniautumn')
  child.expect_screenshot({ ignore_text = { 14 } })

  -- Should properly choose
  type_keys('<CR>')
  eq(child.g.colors_name, 'miniautumn')
  expect.match(child.cmd_capture('hi Normal'), 'guibg=#262029')

  -- Should return chosen value
  eq(child.lua_get('_G.return_item'), 'miniautumn')
end

T['pickers']['colorschemes()']['works with preview'] = function()
  pick_colorschemes()
  type_keys('^mini')

  -- Preview should actually apply the color scheme
  local validate = function(ref_name, ref_normal_bg)
    eq(child.g.colors_name, ref_name)
    expect.match(child.cmd_capture('hi Normal'), 'guibg=' .. ref_normal_bg)
    child.expect_screenshot({ ignore_text = { 14 } })
  end

  type_keys('<Tab>')
  validate('miniautumn', '#262029')

  type_keys('<C-n>')
  validate('minicyan', '#0a2a2a')

  type_keys('<C-p>')
  validate('miniautumn', '#262029')
end

T['pickers']['colorschemes()']['previews with original background'] = function()
  child.cmd('set rtp+=tests/dir-extra/colorschemes')

  child.o.background = 'dark'
  pick_colorschemes()
  type_keys('^mini', '<C-n>', '<C-n>', '<Tab>')
  eq(child.o.background, 'light')
  eq(child.g.colors_name, 'miniforcebg')

  type_keys('<C-n>')
  eq(child.o.background, 'dark')
  eq(child.g.colors_name, 'minischeme')
end

T['pickers']['colorschemes()']['can choose marked'] = function()
  pick_colorschemes()
  type_keys('^mini')
  type_keys('<C-x>', '<C-n>', '<C-x>', '<M-CR>')
  eq(child.g.colors_name, 'miniautumn')
end

T['pickers']['colorschemes()']["can cancel with 'mini.colors'"] = function()
  child.cmd('colorscheme minischeme')
  -- These customizations should persist even if there was preview
  child.api.nvim_set_hl(0, 'Normal', { fg = '#000000' })
  child.g.terminal_color_0 = '#010101'

  child.lua_notify('_G.return_item = MiniExtra.pickers.colorschemes()')
  type_keys('^mini', '<Tab>')
  eq(child.g.colors_name, 'miniautumn')

  -- Should trigger 'ColorScheme' event
  child.cmd('au ColorScheme * lua _G.n = (_G.n or 0) + 1')
  type_keys('<C-c>')
  eq(child.lua_get('_G.n'), child.fn.has('nvim-0.10') == 1 and 1 or 2)

  eq(child.lua_get('_G.return_item'), vim.NIL)
  eq(child.g.colors_name, 'minischeme')
  expect.match(child.cmd_capture('hi Normal'), 'guifg=#000000')
  eq(child.g.terminal_color_0, '#010101')
end

T['pickers']['colorschemes()']["can cancel without 'mini.colors'"] = function()
  -- Mock absent 'mini.colors'
  child.lua([[
    local require_orig = require
    require = function(modname)
      if modname == 'mini.colors' then error("module 'mini.colors' not found") end
      return require_orig(modname)
    end
  ]])

  child.cmd('colorscheme miniwinter')
  -- These customizations can not persist even if there was preview
  child.api.nvim_set_hl(0, 'Normal', { fg = '#000000' })
  child.g.terminal_color_0 = '#010101'

  child.lua_notify('_G.return_item = MiniExtra.pickers.colorschemes()')
  type_keys('^mini', '<Tab>')
  eq(child.g.colors_name, 'miniautumn')

  type_keys('<C-c>')

  eq(child.lua_get('_G.return_item'), vim.NIL)
  eq(child.g.colors_name, 'miniwinter')
  expect.match(child.cmd_capture('hi Normal'), 'guifg=#d8d4cd')
  eq(child.g.terminal_color_0, '#000f15')

  -- Should work if there is no `g:colors_name` defined before starting picker
  child.g.colors_name = nil
  pick_colorschemes()
  type_keys('^mini', '<Tab>', '<C-c>')
  eq(child.cmd_capture('messages'), '')
end

T['pickers']['colorschemes()']['restores original color scheme only if needed'] = function()
  pick_colorschemes()
  child.cmd('au ColorScheme * lua _G.n = (_G.n or 0) + 1')
  type_keys('<C-c>')
  eq(child.lua_get('_G.n'), vim.NIL)
end

T['pickers']['colorschemes()']['respects `local_opts.names`'] = function()
  pick_colorschemes({ names = { 'minisummer', 'minispring' } })
  eq(get_picker_items(), { 'minisummer', 'minispring' })
  type_keys('<Tab>')
  eq(child.g.colors_name, 'minisummer')
  type_keys('<C-c>')

  -- Should validate
  expect.error(function() child.lua('MiniExtra.pickers.colorschemes({ names = 1 })') end, '`names`.*array')
  expect.error(function() child.lua('MiniExtra.pickers.colorschemes({ names = { "xxx" } })') end, '"xxx".*not')
end

T['pickers']['colorschemes()']['respects `local_opts.preview_hl_groups`'] = function()
  pick_colorschemes({ preview_hl_groups = { 'Normal', 'MiniPickBorder' } })
  type_keys('^mini', '<Tab>')
  child.expect_screenshot({ ignore_text = { 14 } })

  -- Should validate
  expect.error(
    function() child.lua('MiniExtra.pickers.colorschemes({ preview_hl_groups = 1 })') end,
    '`preview_hl_groups`.*array'
  )
end

T['pickers']['colorschemes()']['respects `opts`'] = function()
  pick_colorschemes({}, { source = { name = 'My name' } })
  validate_picker_name('My name')
end

T['pickers']['commands()'] = new_set()

local pick_commands = forward_lua_notify('MiniExtra.pickers.commands')

T['pickers']['commands()']['works'] = function()
  child.set_size(10, 80)

  child.lua_notify('_G.return_item = MiniExtra.pickers.commands()')
  validate_picker_name('Commands')
  type_keys("'chdir")
  child.expect_screenshot({ ignore_text = { 9 } })

  -- Should have proper preview
  type_keys('<Tab>')
  -- - No data for built-in commands is yet available
  child.expect_screenshot({ ignore_text = { 9 } })

  -- Should properly choose
  type_keys('<CR>')
  eq(child.fn.getcmdline(), 'chdir ')
  eq(child.fn.getcmdpos(), 7)

  -- Should return chosen value
  eq(child.lua_get('_G.return_item'), 'chdir')

  -- Should work without set up 'mini.pick'
  child.mini_unload('pick')
  pick_commands()
  validate_active_picker()
end

T['pickers']['commands()']['respects user commands'] = function()
  local expect_screenshot = function(...)
    -- Screenshots are generated for Neovim>=0.12, since the output structure
    -- of `nvim_get_commands()` has changed
    if child.fn.has('nvim-0.12') == 0 then return end
    child.expect_screenshot(...)
  end

  child.set_size(25, 75)
  child.cmd('command -nargs=0 MyCommand lua _G.my_command = true')
  child.cmd('command -nargs=* -buffer MyCommandBuf lua _G.my_command_buf = true')

  -- Both global and buffer-local
  pick_commands()
  type_keys('^MyCommand')
  eq(get_picker_matches().all, { 'MyCommand', 'MyCommandBuf' })

  -- Should have proper preview with data
  type_keys('<Tab>')
  expect_screenshot({ ignore_text = { 24 } })
  type_keys('<C-n>')
  expect_screenshot({ ignore_text = { 24 } })

  -- Should on choose execute command if it is without arguments
  type_keys('<C-p>', '<CR>')
  eq(is_picker_active(), false)
  eq(child.lua_get('_G.my_command'), true)
  eq(child.lua_get('_G.my_command_buf'), vim.NIL)
end

T['pickers']['commands()']['respects `opts`'] = function()
  pick_commands({}, { source = { name = 'My name' } })
  validate_picker_name('My name')
end

T['pickers']['commands()']['respects global source options'] = function()
  validate_global_source_options(pick_commands, false, false)
end

T['pickers']['diagnostic()'] = new_set({
  hooks = {
    pre_case = function()
      local mock_path = make_testpath('mocks', 'diagnostic.lua')
      child.lua(string.format('dofile(%s)', vim.inspect(mock_path)))
    end,
  },
})

local pick_diagnostic = forward_lua_notify('MiniExtra.pickers.diagnostic')

T['pickers']['diagnostic()']['works'] = function()
  child.set_size(25, 100)
  child.cmd('enew')

  mock_slash_path_sep()
  child.lua_notify('_G.return_item = MiniExtra.pickers.diagnostic()')
  validate_picker_name('Diagnostic (all)')
  child.expect_screenshot()

  -- Should use proper highlight groups
  validate_partial_equal_arr(get_extra_picker_extmarks(0, -1), {
    { hl_group = 'DiagnosticFloatingError' },
    { hl_group = 'DiagnosticFloatingError' },
    { hl_group = 'DiagnosticFloatingError' },
    { hl_group = 'DiagnosticFloatingWarn' },
    { hl_group = 'DiagnosticFloatingWarn' },
    { hl_group = 'DiagnosticFloatingWarn' },
    { hl_group = 'DiagnosticFloatingInfo' },
    { hl_group = 'DiagnosticFloatingInfo' },
    { hl_group = 'DiagnosticFloatingInfo' },
    { hl_group = 'DiagnosticFloatingHint' },
    { hl_group = 'DiagnosticFloatingHint' },
    { hl_group = 'DiagnosticFloatingHint' },
  })

  -- Should have proper preview
  type_keys('<C-n>')
  type_keys('<Tab>')
  child.expect_screenshot()
  unmock_slash_path_sep()

  -- Should properly choose
  type_keys('<CR>')
  validate_buf_name(0, make_testpath('mocks', 'diagnostic-file-1'))
  eq(get_cursor(), { 2, 2 })

  local return_item = child.lua_get('_G.return_item')
  -- - Remove any private fields (like `_extmark_id` on Neovim>=0.12)
  for _, k in ipairs(vim.tbl_keys(return_item)) do
    if k:sub(1, 1) == '_' then return_item[k] = nil end
  end

  --stylua: ignore
  -- Should return chosen value with proper structure
  eq(return_item, {
    bufnr    = 1, namespace = child.lua_get('_G.diag_ns'),
    severity = 1,
    col      = 3, end_col   = 8,
    end_lnum = 2, lnum      = 2,
    path     = 'tests/dir-extra/mocks/diagnostic-file-1',
    message  = 'Error 2',
    text     = 'E │ tests/dir-extra/mocks/diagnostic-file-1 │ Error 2',
  })

  -- Should work without set up 'mini.pick'
  child.mini_unload('pick')
  pick_diagnostic()
  validate_active_picker()
end

T['pickers']['diagnostic()']['respects `local_opts.get_opts`'] = function()
  local hint_severity = child.lua_get('vim.diagnostic.severity.HINT')
  pick_diagnostic({ get_opts = { severity = hint_severity } })
  validate_partial_equal_arr(
    get_picker_items(),
    { { severity = hint_severity }, { severity = hint_severity }, { severity = hint_severity } }
  )
end

T['pickers']['diagnostic()']['respects `local_opts.scope`'] = function()
  local buf_id = child.api.nvim_get_current_buf()
  pick_diagnostic({ scope = 'current' })
  validate_picker_name('Diagnostic (current)')
  validate_partial_equal_arr(
    get_picker_items(),
    { { bufnr = buf_id }, { bufnr = buf_id }, { bufnr = buf_id }, { bufnr = buf_id } }
  )
end

T['pickers']['diagnostic()']['respects `local_opts.sort_by`'] = function()
  local sev_error = child.lua_get('_G.vim.diagnostic.severity.ERROR')
  local sev_warn = child.lua_get('_G.vim.diagnostic.severity.WARN')
  local sev_info = child.lua_get('_G.vim.diagnostic.severity.INFO')
  local sev_hint = child.lua_get('_G.vim.diagnostic.severity.HINT')

  local path_1 = make_testpath('mocks', 'diagnostic-file-1')
  local path_2 = make_testpath('mocks', 'diagnostic-file-2')
  if path_sep == '\\' then
    path_1, path_2 = (path_1:gsub('/', '\\')), (path_2:gsub('/', '\\'))
  end

  pick_diagnostic({ sort_by = 'severity' })
  --stylua: ignore
  validate_partial_equal_arr(
    get_picker_items(),
    {
      { severity = sev_error, path = path_1, message = 'Error 1' },
      { severity = sev_error, path = path_1, message = 'Error 2' },
      { severity = sev_error, path = path_2, message = 'Error 3' },
      { severity = sev_warn,  path = path_1, message = 'Warning 1' },
      { severity = sev_warn,  path = path_1, message = 'Warning 2' },
      { severity = sev_warn,  path = path_2, message = 'Warning 3' },
      { severity = sev_info,  path = path_1, message = 'Info 1' },
      { severity = sev_info,  path = path_1, message = 'Info 2' },
      { severity = sev_info,  path = path_2, message = 'Info 3' },
      { severity = sev_hint,  path = path_1, message = 'Hint 1' },
      { severity = sev_hint,  path = path_1, message = 'Hint 2' },
      { severity = sev_hint,  path = path_2, message = 'Hint 3' },
    }
  )
  stop_picker()

  pick_diagnostic({ sort_by = 'path' })
  --stylua: ignore
  validate_partial_equal_arr(
    get_picker_items(),
    {
      { severity = sev_error, path = path_1, message = 'Error 1' },
      { severity = sev_error, path = path_1, message = 'Error 2' },
      { severity = sev_warn,  path = path_1, message = 'Warning 1' },
      { severity = sev_warn,  path = path_1, message = 'Warning 2' },
      { severity = sev_info,  path = path_1, message = 'Info 1' },
      { severity = sev_info,  path = path_1, message = 'Info 2' },
      { severity = sev_hint,  path = path_1, message = 'Hint 1' },
      { severity = sev_hint,  path = path_1, message = 'Hint 2' },
      { severity = sev_error, path = path_2, message = 'Error 3' },
      { severity = sev_warn,  path = path_2, message = 'Warning 3' },
      { severity = sev_info,  path = path_2, message = 'Info 3' },
      { severity = sev_hint,  path = path_2, message = 'Hint 3' },
    }
  )
  stop_picker()
end

T['pickers']['diagnostic()']['respects `opts`'] = function()
  pick_diagnostic({}, { source = { name = 'My name' } })
  validate_picker_name('My name')
end

T['pickers']['diagnostic()']['respects global source options'] = function()
  validate_global_source_options(pick_diagnostic, true, false)
end

T['pickers']['diagnostic()']['does not modify diagnostic table'] = function()
  local diagnostic_current = child.lua_get('vim.diagnostic.get()')
  pick_diagnostic()
  stop_picker()
  eq(child.lua_get('vim.diagnostic.get()'), diagnostic_current)
end

T['pickers']['diagnostic()']["forces 'buflisted' on opened buffer"] = function()
  -- This matters for project wide diagnostic done inside unlisted buffers
  child.lua('vim.bo[_G.buf_id_2].buflisted = false')

  pick_diagnostic()
  type_keys('<C-p>', '<CR>')
  eq(child.bo.buflisted, true)
end

T['pickers']['diagnostic()']['validates arguments'] = function()
  local validate = function(local_opts, error_pattern)
    expect.error(function() child.lua('MiniExtra.pickers.diagnostic(...)', { local_opts }) end, error_pattern)
  end
  validate({ scope = '1' }, '`pickers%.diagnostic`.*"scope".*"1".*one of')
  validate({ sort_by = '1' }, '`pickers%.diagnostic`.*"sort_by".*"1".*one of')
end

T['pickers']['explorer()'] = new_set()

local pick_explorer = forward_lua_notify('MiniExtra.pickers.explorer')

T['pickers']['explorer()']['works'] = function()
  local init_dir = full_path(make_testpath('explorer'))
  child.fn.chdir(init_dir)

  child.lua_notify('_G.return_item = MiniExtra.pickers.explorer()')
  validate_picker_name('File explorer')
  validate_picker_cwd(init_dir)
  local init_items = get_picker_items()
  child.expect_screenshot()

  -- Can navigate inside directory
  type_keys('<C-n>', '<CR>')
  child.expect_screenshot()
  validate_picker_name('File explorer')
  validate_picker_cwd(init_dir .. '/dir1')

  -- - Should actually change items
  eq(vim.deep_equal(init_items, get_picker_items()), false)

  -- Can preview directory (both regular and `..`) and file
  type_keys('<Tab>')
  child.expect_screenshot()
  type_keys('<C-n>')
  child.expect_screenshot()
  type_keys('<C-n>')
  child.expect_screenshot()

  -- Can navigate up
  type_keys('<C-g>', '<CR>')
  child.expect_screenshot()
  validate_picker_cwd(init_dir)

  -- Can choose file
  type_keys('<C-p>', '<CR>')
  validate_buf_name(0, 'file3')
  eq(get_lines(), { 'File 3' })

  -- Should return chosen value
  eq(child.lua_get('_G.return_item'), { fs_type = 'file', path = init_dir .. '/file3', text = 'file3' })

  -- Should work without set up 'mini.pick'
  child.mini_unload('pick')
  pick_explorer()
  validate_active_picker()
end

T['pickers']['explorer()']['works with query'] = function()
  local init_dir = full_path(make_testpath('explorer'))
  child.fn.chdir(init_dir)

  pick_explorer()
  type_keys('^D')
  eq(get_picker_matches().all, { { fs_type = 'directory', path = init_dir .. '/Dir2', text = 'Dir2/' } })

  type_keys('<CR>')
  eq(get_picker_matches().all, {
    { fs_type = 'directory', path = init_dir, text = '..' },
    { fs_type = 'file', path = init_dir .. '/Dir2/file2-1', text = 'file2-1' },
  })
  -- - Should reset the query
  eq(child.lua_get('MiniPick.get_picker_query()'), {})
end

T['pickers']['explorer()']['can be resumed'] = function()
  local init_dir = full_path(make_testpath('explorer'))
  child.fn.chdir(init_dir)
  pick_explorer()
  type_keys('<C-n>', '<CR>', '<C-n>')
  child.expect_screenshot()
  stop_picker()

  child.lua_notify('MiniPick.builtin.resume()')
  validate_picker_cwd(init_dir .. '/dir1')
  child.expect_screenshot()
end

T['pickers']['explorer()']['respects `local_opts.cwd`'] = function()
  local validate = function(cwd, ref_picker_cwd)
    local init_win_id, init_cwd = child.api.nvim_get_current_win(), child.fn.getcwd()
    local cwd_absolute = cwd == '..' and vim.fn.fnamemodify(init_cwd, ':h') or full_path(cwd)
    pick_explorer({ cwd = cwd })
    validate_picker_cwd(ref_picker_cwd)

    -- Picker window's directory should change, but other should stay the same
    eq(child.fn.getcwd(0), cwd_absolute)
    eq(child.fn.getcwd(init_win_id), init_cwd)

    -- Cleanup
    stop_picker()
  end

  local path = make_testpath('explorer')

  -- Relative path
  validate(path, full_path(path))

  -- Absolute path
  validate(full_path(path), full_path(path))

  -- Parent path
  child.fn.chdir(path)
  validate('..', test_dir_absolute)
end

T['pickers']['explorer()']['respects `local_opts.filter`'] = function()
  local init_dir = full_path(make_testpath('explorer'))
  child.fn.chdir(init_dir)
  child.lua([[
    _G.filter_log = {}
    _G.dir_filter = function(item)
      table.insert(_G.filter_log, vim.deepcopy(item))
      return item.fs_type == 'directory'
    end
  ]])
  child.lua_notify('MiniExtra.pickers.explorer({ filter = _G.dir_filter })')
  child.expect_screenshot()

  -- Should work when navigate into subdirectory
  type_keys('<C-n>', '<CR>')
  child.expect_screenshot()

  -- Should be called with proper arguments
  local filter_log = child.lua_get('_G.filter_log')
  eq(#filter_log, 7 + 3)
  eq(filter_log[1], { fs_type = 'directory', path = test_dir_absolute, text = '..' })
end

T['pickers']['explorer()']['respects `local_opts.sort`'] = function()
  local init_dir = full_path(make_testpath('explorer'))
  child.fn.chdir(init_dir)
  child.lua([[
    _G.sort_log = {}
    _G.sort_plain = function(items)
      table.insert(_G.sort_log, vim.deepcopy(items))
      local res = vim.deepcopy(items)
      table.sort(res, function(a, b) return a.text < b.text end)
      return res
    end
  ]])
  child.lua_notify('MiniExtra.pickers.explorer({ sort = _G.sort_plain })')
  child.expect_screenshot()

  -- Should work when navigate into subdirectory
  type_keys('<C-n>', '<C-n>', '<C-n>', '<CR>')
  child.expect_screenshot()

  -- Should be called with proper arguments
  local sort_log = child.lua_get('_G.sort_log')
  eq(#sort_log, 2)
  eq(islist(sort_log[1]), true)
  eq(sort_log[1][1], { fs_type = 'directory', path = test_dir_absolute, text = '..' })
end

T['pickers']['explorer()']['can not show icons'] = function()
  local init_dir = full_path(make_testpath('explorer'))
  child.fn.chdir(init_dir)

  child.lua('MiniPick.config.source.show = MiniPick.default_show')
  pick_explorer()
  child.expect_screenshot()
  type_keys('<C-n>', '<CR>')
  child.expect_screenshot()
end

T['pickers']['explorer()']['respects `opts`'] = function()
  local init_dir = full_path(make_testpath('explorer'))
  child.fn.chdir(init_dir)
  pick_explorer({}, { source = { name = 'My name' } })
  validate_picker_name('My name')
end

T['pickers']['explorer()']['respects global source options'] = function()
  validate_global_source_options(pick_explorer, true, false)
end

T['pickers']['explorer()']['validates arguments'] = function()
  local validate = function(local_opts, error_pattern)
    expect.error(function() child.lua('MiniExtra.pickers.explorer(...)', { local_opts }) end, error_pattern)
  end

  validate({ cwd = '1' }, '`local_opts%.cwd`.*valid directory path')
  validate({ filter = '1' }, '`local_opts%.filter`.*callable')
  validate({ sort = '1' }, '`local_opts%.sort`.*callable')
end

T['pickers']['git_branches()'] = new_set({ hooks = { pre_case = mock_spawn } })

local pick_git_branches = forward_lua_notify('MiniExtra.pickers.git_branches')

T['pickers']['git_branches()']['works'] = function()
  child.set_size(10, 90)

  local repo_dir = test_dir_absolute
  child.fn.chdir(repo_dir)
  mock_git_repo(repo_dir)
  local branch_lines = {
    '* main              0123456 Commit message.',
    'remotes/origin/HEAD -> origin/main',
    'remotes/origin/main aaaaaaa Another commit message.',
  }
  mock_cli_return(branch_lines)

  local buf_init = child.api.nvim_get_current_buf()
  child.lua_notify('_G.return_item = MiniExtra.pickers.git_branches()')
  validate_picker_name('Git branches (all)')
  child.expect_screenshot()

  eq(get_spawn_log(), {
    { executable = 'git', options = { args = { 'branch', '--all', '-v', '--no-color', '--list' }, cwd = repo_dir } },
  })
  clear_spawn_log()
  clear_process_log()

  -- Should have proper preview
  child.lua([[_G.stream_type_queue = { 'stdout', 'stderr' }]])
  local log_lines = { '0123456 Commit message.', 'aaaaaaa Another commit message.' }
  mock_cli_return(log_lines)
  type_keys('<Tab>')
  child.expect_screenshot()

  eq(get_spawn_log(), {
    { executable = 'git', options = { args = { '-C', repo_dir, 'log', 'main', '--format=format:%h %s' } } },
  })
  -- - It should properly close both stdout and stderr
  eq(get_process_log(), { 'stdout_2 was closed.', 'stderr_1 was closed.', 'Process Pid_2 was closed.' })

  -- Should properly choose by showing history in the new scratch buffer
  child.lua([[_G.stream_type_queue = { 'stdout', 'stderr' }]])
  mock_cli_return(log_lines)
  type_keys('<CR>')

  eq(get_lines(), log_lines)
  local buf_cur = child.api.nvim_get_current_buf()
  eq(buf_init ~= buf_cur, true)
  eq(child.bo.buftype, 'nofile')
  eq(child.api.nvim_buf_get_name(buf_cur), 'miniextra://' .. buf_cur .. '/main')

  -- Should return chosen value
  eq(child.lua_get('_G.return_item'), branch_lines[1])

  -- Should work without set up 'mini.pick'
  child.mini_unload('pick')
  pick_git_branches()
  validate_active_picker()
end

T['pickers']['git_branches()']['respects `local_opts.path`'] = function()
  local repo_dir = test_dir_absolute
  mock_git_repo(repo_dir)
  local dir_path = make_testpath('git-files')
  local dir_path_full = full_path(dir_path)

  local validate = function(path, ref_repo_dir)
    pick_git_branches({ path = path })
    eq(get_spawn_log()[1].options, { args = { 'branch', '--all', '-v', '--no-color', '--list' }, cwd = ref_repo_dir })
    validate_picker_cwd(ref_repo_dir)
    validate_git_repo_check(dir_path_full)

    -- Cleanup
    stop_picker()
    clear_spawn_log()
    clear_git_repo_check()
  end

  -- Should always use parent repository path
  -- - Directory path
  validate(dir_path_full, repo_dir)

  -- - File path
  validate(join_path(dir_path, 'git-file-1'), repo_dir)

  -- - Default with different current directory
  child.fn.chdir(dir_path_full)
  validate(nil, repo_dir)
end

T['pickers']['git_branches()']['respects `local_opts.scope`'] = function()
  mock_git_repo(test_dir_absolute)
  child.fn.chdir(test_dir_absolute)

  local validate = function(scope, ref_args, ref_picker_name)
    pick_git_branches({ scope = scope })
    eq(get_spawn_log()[1].options.args, ref_args)
    validate_picker_name(ref_picker_name)

    -- Cleanup
    stop_picker()
    clear_spawn_log()
  end

  validate('all', { 'branch', '--all', '-v', '--no-color', '--list' }, 'Git branches (all)')
  validate('local', { 'branch', '-v', '--no-color', '--list' }, 'Git branches (local)')
  validate('remotes', { 'branch', '--remotes', '-v', '--no-color', '--list' }, 'Git branches (remotes)')
end

T['pickers']['git_branches()']['respects `opts`'] = function()
  local repo_dir = test_dir_absolute
  child.fn.chdir(repo_dir)
  mock_git_repo(repo_dir)
  pick_git_branches({}, { source = { name = 'My name' } })
  validate_picker_name('My name')
end

T['pickers']['git_branches()']['respects global source options'] = function()
  validate_global_source_options(pick_git_branches, false, false)
end

T['pickers']['git_branches()']['validates git'] = function()
  -- CLI
  mock_fn_executable({})
  expect.error(
    function() child.lua('MiniExtra.pickers.git_branches()') end,
    '`pickers%.git_branches` requires executable `git`'
  )

  -- Repo
  mock_no_git_repo()
  expect.error(
    function() child.lua('MiniExtra.pickers.git_branches()') end,
    '`pickers%.git_branches` could not find Git repo for ' .. vim.pesc(child.fn.getcwd())
  )
end

T['pickers']['git_branches()']['validates arguments'] = function()
  mock_git_repo(test_dir_absolute)
  child.fn.chdir(test_dir_absolute)
  local validate = function(local_opts, error_pattern)
    expect.error(function() child.lua('MiniExtra.pickers.git_branches(...)', { local_opts }) end, error_pattern)
  end

  validate({ path = '1' }, 'Path.*1 is not a valid path')
  validate({ path = '' }, 'Path.*is empty')
  validate({ scope = '1' }, '`pickers%.git_branches`.*"scope".*"1".*one of')
end

T['pickers']['git_commits()'] = new_set({ hooks = { pre_case = mock_spawn } })

local pick_git_commits = forward_lua_notify('MiniExtra.pickers.git_commits')

T['pickers']['git_commits()']['works'] = function()
  child.set_size(33, 100)

  local repo_dir = test_dir_absolute
  child.fn.chdir(repo_dir)
  mock_git_repo(repo_dir)
  local log_lines = { '0123456 Commit message.', 'aaaaaaa Another commit message.', '1111111 Initial commit.' }
  mock_cli_return(log_lines)
  child.lua([[
    vim.treesitter.get_parser = function(...)
      _G.ts_get_parser_args = { ... }
      errror('No parser')
    end
  ]])

  local buf_init = child.api.nvim_get_current_buf()
  child.lua_notify('_G.return_item = MiniExtra.pickers.git_commits()')
  validate_picker_name('Git commits (all)')
  child.expect_screenshot()

  eq(get_spawn_log(), {
    { executable = 'git', options = { args = { 'log', '--format=format:%h %s', '--', repo_dir }, cwd = repo_dir } },
  })
  clear_spawn_log()
  clear_process_log()

  -- Should have proper preview (should try to load tree-sitter first)
  child.lua([[_G.stream_type_queue = { 'stdout', 'stderr' }]])
  local show_commit_lines = child.fn.readfile(join_path('mocks', 'git-commit'))
  mock_cli_return(show_commit_lines)
  type_keys('<C-p>', '<Tab>')
  child.expect_screenshot()
  eq(child.lua_get('_G.ts_get_parser_args[2]'), 'git')

  eq(get_spawn_log(), {
    { executable = 'git', options = { args = { '-C', repo_dir, '--no-pager', 'show', '1111111' } } },
  })
  -- - It should properly close both stdout and stderr
  eq(get_process_log(), { 'stdout_2 was closed.', 'stderr_1 was closed.', 'Process Pid_2 was closed.' })

  -- Should properly choose by showing commit in the new scratch buffer
  child.lua([[_G.stream_type_queue = { 'stdout', 'stderr' }]])
  mock_cli_return(show_commit_lines)
  type_keys('<CR>')

  eq(get_lines(), show_commit_lines)
  local buf_cur = child.api.nvim_get_current_buf()
  eq(buf_init ~= buf_cur, true)
  eq(child.bo.buftype, 'nofile')
  eq(child.api.nvim_buf_get_name(buf_cur), 'miniextra://' .. buf_cur .. '/1111111')
  eq(child.bo.syntax, 'git')
  eq(child.bo.filetype, 'git')

  -- Should return chosen value
  eq(child.lua_get('_G.return_item'), log_lines[#log_lines])

  -- Should work without set up 'mini.pick'
  child.mini_unload('pick')
  pick_git_commits()
  validate_active_picker()
end

T['pickers']['git_commits()']['respects `local_opts.path`'] = function()
  local repo_dir = test_dir_absolute
  mock_git_repo(repo_dir)
  child.fn.chdir(repo_dir)
  local dir_path_full = full_path('git-files')

  local validate = function(path, ref_repo_dir)
    pick_git_commits({ path = path })
    eq(
      get_spawn_log()[1].options,
      { args = { 'log', [[--format=format:%h %s]], '--', path or ref_repo_dir }, cwd = ref_repo_dir }
    )
    validate_picker_cwd(ref_repo_dir)
    validate_picker_name(path == nil and 'Git commits (all)' or 'Git commits (for path)')
    validate_git_repo_check(dir_path_full)

    -- Cleanup
    stop_picker()
    clear_spawn_log()
    clear_git_repo_check()
  end

  -- Should always use repo dir as cwd and use path verbatim
  -- - Directory path
  validate(dir_path_full, repo_dir)

  -- - File path
  validate(join_path(dir_path_full, 'git-file-1'), repo_dir)

  -- - Default with different current directory should use repo dir as path
  child.fn.chdir(dir_path_full)
  validate(nil, repo_dir)
end

T['pickers']['git_commits()']['respects `opts`'] = function()
  local repo_dir = test_dir_absolute
  child.fn.chdir(repo_dir)
  mock_git_repo(repo_dir)
  pick_git_commits({}, { source = { name = 'My name' } })
  validate_picker_name('My name')
end

T['pickers']['git_commits()']['respects global source options'] = function()
  validate_global_source_options(pick_git_branches, false, false)
end

T['pickers']['git_commits()']['validates git'] = function()
  -- CLI
  mock_fn_executable({})
  expect.error(
    function() child.lua('MiniExtra.pickers.git_commits()') end,
    '`pickers%.git_commits` requires executable `git`'
  )

  -- Repo
  mock_no_git_repo()
  expect.error(
    function() child.lua('MiniExtra.pickers.git_commits()') end,
    '`pickers%.git_commits` could not find Git repo for ' .. vim.pesc(child.fn.getcwd())
  )
end

T['pickers']['git_commits()']['validates arguments'] = function()
  mock_git_repo(test_dir_absolute)
  child.fn.chdir(test_dir_absolute)

  local validate = function(local_opts, error_pattern)
    expect.error(function() child.lua('MiniExtra.pickers.git_commits(...)', { local_opts }) end, error_pattern)
  end

  validate({ path = '1' }, 'Path.*1 is not a valid path')
  validate({ path = '' }, 'Path.*is empty')
end

T['pickers']['git_files()'] = new_set({ hooks = { pre_case = mock_spawn } })

local pick_git_files = forward_lua_notify('MiniExtra.pickers.git_files')

T['pickers']['git_files()']['works'] = function()
  child.set_size(10, 50)

  local repo_dir = test_dir_absolute
  child.fn.chdir(repo_dir)
  mock_git_repo(repo_dir)
  mock_cli_return({ 'git-files/git-file-1', 'git-files/git-file-2' })

  child.lua_notify('_G.return_item = MiniExtra.pickers.git_files()')
  validate_picker_name('Git files (tracked)')
  child.expect_screenshot()
  eq(get_spawn_log(), {
    { executable = 'git', options = { args = { '-C', repo_dir, 'ls-files', '--cached' }, cwd = repo_dir } },
  })

  -- Should have proper preview
  type_keys('<Tab>')
  child.expect_screenshot()

  -- Should properly choose
  type_keys('<CR>')
  validate_buf_name(0, join_path('git-files', 'git-file-1'))

  -- Should return chosen value
  eq(child.lua_get('_G.return_item'), 'git-files/git-file-1')

  -- Should work without set up 'mini.pick'
  child.mini_unload('pick')
  pick_git_files()
  validate_active_picker()
end

T['pickers']['git_files()']['respects `local_opts.path`'] = function()
  local repo_dir = test_dir_absolute
  mock_git_repo(repo_dir)
  local dir_path = make_testpath('git-files')
  local dir_path_full = full_path(dir_path)

  local validate = function(path, ref_cwd)
    pick_git_files({ path = path })
    eq(get_spawn_log()[1].options, { args = { '-C', ref_cwd, 'ls-files', '--cached' }, cwd = ref_cwd })
    validate_picker_cwd(ref_cwd)
    validate_git_repo_check(dir_path_full)

    -- Cleanup
    stop_picker()
    clear_spawn_log()
    clear_git_repo_check()
  end

  -- Directory path
  validate(dir_path_full, dir_path_full)

  -- File path (should use its parent directory path)
  validate(join_path(dir_path, 'git-file-1'), dir_path_full)

  -- By default should not use parent repo and use current directory instead
  child.fn.chdir(dir_path_full)
  validate(nil, dir_path_full)
end

T['pickers']['git_files()']['respects `local_opts.scope`'] = function()
  mock_git_repo(test_dir_absolute)
  child.fn.chdir(test_dir_absolute)

  local validate = function(scope, flags, ref_picker_name)
    pick_git_files({ scope = scope })
    local ref_args = { '-C', test_dir_absolute, 'ls-files' }
    vim.list_extend(ref_args, flags)
    eq(get_spawn_log()[1].options.args, ref_args)
    validate_picker_name(ref_picker_name)

    -- Cleanup
    stop_picker()
    clear_spawn_log()
  end

  validate('tracked', { '--cached' }, 'Git files (tracked)')
  validate('modified', { '--modified' }, 'Git files (modified)')
  validate('untracked', { '--others' }, 'Git files (untracked)')
  validate('ignored', { '--others', '--ignored', '--exclude-standard' }, 'Git files (ignored)')
  validate('deleted', { '--deleted' }, 'Git files (deleted)')
end

T['pickers']['git_files()']['can not show icons'] = function()
  child.set_size(10, 50)
  local repo_dir = test_dir_absolute
  child.fn.chdir(repo_dir)
  mock_git_repo(repo_dir)
  mock_cli_return({ 'git-files/git-file-1', 'git-files/git-file-2' })

  child.lua('MiniPick.config.source.show = MiniPick.default_show')
  pick_git_files()
  child.expect_screenshot()
end

T['pickers']['git_files()']['respects `opts`'] = function()
  local repo_dir = test_dir_absolute
  child.fn.chdir(repo_dir)
  mock_git_repo(repo_dir)
  pick_git_files({}, { source = { name = 'My name' } })
  validate_picker_name('My name')
end

T['pickers']['git_files()']['respects global source options'] = function()
  local repo_dir = test_dir_absolute
  child.fn.chdir(repo_dir)
  mock_git_repo(repo_dir)
  mock_cli_return({ 'git-files/git-file-1', 'git-files/git-file-2' })
  validate_global_source_options(pick_git_files, true, true)
end

T['pickers']['git_files()']['validates git'] = function()
  -- CLI
  mock_fn_executable({})
  expect.error(
    function() child.lua('MiniExtra.pickers.git_files()') end,
    '`pickers%.git_files` requires executable `git`'
  )

  -- Repo
  mock_no_git_repo()
  expect.error(
    function() child.lua('MiniExtra.pickers.git_files()') end,
    '`pickers%.git_files` could not find Git repo for ' .. vim.pesc(child.fn.getcwd())
  )
end

T['pickers']['git_files()']['validates arguments'] = function()
  mock_git_repo(test_dir_absolute)
  child.fn.chdir(test_dir_absolute)

  local validate = function(local_opts, error_pattern)
    expect.error(function() child.lua('MiniExtra.pickers.git_files(...)', { local_opts }) end, error_pattern)
  end

  validate({ path = '1' }, 'Path.*1 is not a valid path')
  validate({ path = '' }, 'Path.*is empty')
  validate({ scope = '1' }, '`pickers%.git_files`.*"scope".*"1".*one of')
end

T['pickers']['git_hunks()'] = new_set({ hooks = { pre_case = mock_spawn } })

local pick_git_hunks = forward_lua_notify('MiniExtra.pickers.git_hunks')

T['pickers']['git_hunks()']['works'] = function()
  child.set_size(33, 100)

  local repo_dir = test_dir_absolute
  child.fn.chdir(repo_dir)
  mock_git_repo(repo_dir)
  local diff_lines = child.fn.readfile(join_path('mocks', 'git-diff'))
  mock_cli_return(diff_lines)
  child.lua([[
    vim.treesitter.get_parser = function(...)
      _G.ts_get_parser_args = { ... }
      errror('No parser')
    end
  ]])

  child.lua_notify('_G.return_item = MiniExtra.pickers.git_hunks()')
  validate_picker_name('Git hunks (unstaged all)')
  child.expect_screenshot()

  local ref_args = { 'diff', '--patch', '--unified=3', '--color=never', '--', repo_dir }
  eq(get_spawn_log(), { { executable = 'git', options = { args = ref_args, cwd = repo_dir } } })

  -- Should have proper preview (without extra CLI calls, but with trying to
  -- load tree-sitter first)
  type_keys('<Tab>')
  child.expect_screenshot()
  for _ = 1, (#get_picker_items() - 1) do
    type_keys('<C-n>')
    child.expect_screenshot()
  end
  eq(child.lua_get('_G.ts_get_parser_args[2]'), 'diff')

  -- Should properly choose by navigating to the first hunk change
  type_keys('<CR>')
  local target_path = join_path('git-files', 'git-file-2')
  validate_buf_name(0, target_path)
  eq(get_cursor(), { 12, 0 })

  -- Should return chosen value
  local return_item = child.lua_get('_G.return_item')
  local return_item_keys = vim.tbl_keys(return_item)
  table.sort(return_item_keys)
  eq(return_item_keys, { 'header', 'hunk', 'lnum', 'path', 'text' })
  eq(return_item.path, 'git-files/git-file-2')
  eq(return_item.lnum, 12)

  -- Should work without set up 'mini.pick'
  child.mini_unload('pick')
  pick_git_hunks()
  validate_active_picker()
end

T['pickers']['git_hunks()']['works in edge cases'] = function()
  local repo_dir = test_dir_absolute
  child.fn.chdir(repo_dir)
  mock_git_repo(repo_dir)
  local diff_lines = child.fn.readfile(join_path('mocks', 'git-diff-edge-cases'))
  mock_cli_return(diff_lines)

  pick_git_hunks()

  local items = get_picker_items()
  eq(#items, 2)
  -- Should recognize diffs that come with `diff.mnemonicPrefix=true`
  eq(items[1].text, 'git-files/git-file-1 │ -1,4 +1,3  │ ')
  -- Should recognize diffs that come from deleted file
  eq(items[2].text, 'git-files/git-file-2 │ -1,21 +0,0 │ ')
  -- - NOTE: Although it still points to a deleted file, so no navigation to it
  eq(items[2].path, 'git-files/git-file-2')
end

T['pickers']['git_hunks()']['respects `local_opts.n_context`'] = new_set({ parametrize = { { 0 }, { 20 } } }, {
  test = function(n_context)
    child.set_size(15, 100)
    local repo_dir = test_dir_absolute
    mock_git_repo(repo_dir)
    child.fn.chdir(repo_dir)

    -- Zero context
    local mock_path = join_path('mocks', 'git-diff-unified-' .. n_context)
    local diff_lines = child.fn.readfile(mock_path)
    mock_cli_return(diff_lines)

    pick_git_hunks({ n_context = n_context })
    eq(get_spawn_log(), {
      {
        executable = 'git',
        options = {
          args = { 'diff', '--patch', '--unified=' .. n_context, '--color=never', '--', repo_dir },
          cwd = repo_dir,
        },
      },
    })
    child.expect_screenshot()

    -- - Preview
    type_keys('<Tab>')
    child.expect_screenshot()
    type_keys('<C-n>')
    child.expect_screenshot()

    -- - Choose
    type_keys('<CR>')
    if n_context == 0 then
      validate_buf_name(0, join_path('git-files', 'git-file-1'))
      eq(get_cursor(), { 11, 0 })
    end
    if n_context == 20 then
      validate_buf_name(0, join_path('git-files', 'git-file-2'))
      eq(get_cursor(), { 2, 0 })
    end
  end,
})

T['pickers']['git_hunks()']['respects `local_opts.path`'] = function()
  local repo_dir = test_dir_absolute
  mock_git_repo(repo_dir)
  child.fn.chdir(repo_dir)
  local dir_path_full = full_path('git-files')

  local validate = function(path, ref_repo_dir)
    pick_git_hunks({ path = path })
    eq(
      get_spawn_log()[1].options,
      { args = { 'diff', '--patch', '--unified=3', '--color=never', '--', path or ref_repo_dir }, cwd = ref_repo_dir }
    )
    validate_picker_cwd(ref_repo_dir)
    validate_picker_name(path == nil and 'Git hunks (unstaged all)' or 'Git hunks (unstaged for path)')
    validate_git_repo_check(dir_path_full)

    -- Cleanup
    stop_picker()
    clear_spawn_log()
    clear_git_repo_check()
  end

  -- Should always use repo dir as cwd and use path verbatim
  -- - Directory path
  validate(dir_path_full, repo_dir)

  -- - File path
  validate(join_path(dir_path_full, 'git-file-1'), repo_dir)

  -- - Default with different current directory should use repo dir as path
  child.fn.chdir(dir_path_full)
  validate(nil, repo_dir)
end

T['pickers']['git_hunks()']['respects `local_opts.scope`'] = function()
  local repo_dir = test_dir_absolute
  mock_git_repo(repo_dir)
  child.fn.chdir(repo_dir)

  local validate = function(scope, ref_args, ref_picker_name)
    pick_git_hunks({ scope = scope })
    eq(get_spawn_log()[1].options.args, ref_args)
    validate_picker_name(ref_picker_name)

    -- Cleanup
    stop_picker()
    clear_spawn_log()
  end

  validate(
    'unstaged',
    { 'diff', '--patch', '--unified=3', '--color=never', '--', repo_dir },
    'Git hunks (unstaged all)'
  )

  validate(
    'staged',
    { 'diff', '--patch', '--cached', '--unified=3', '--color=never', '--', repo_dir },
    'Git hunks (staged all)'
  )
end

T['pickers']['git_hunks()']['respects `opts`'] = function()
  local repo_dir = test_dir_absolute
  child.fn.chdir(repo_dir)
  mock_git_repo(repo_dir)
  pick_git_hunks({}, { source = { name = 'My name' } })
  validate_picker_name('My name')
end

T['pickers']['git_hunks()']['respects global source options'] = function()
  local repo_dir = test_dir_absolute
  child.fn.chdir(repo_dir)
  mock_git_repo(repo_dir)
  local diff_lines = child.fn.readfile(join_path('mocks', 'git-diff'))
  mock_cli_return(diff_lines)
  validate_global_source_options(pick_git_hunks, false, true)
end

T['pickers']['git_hunks()']['validates git'] = function()
  -- CLI
  mock_fn_executable({})
  expect.error(
    function() child.lua('MiniExtra.pickers.git_hunks()') end,
    '`pickers%.git_hunks` requires executable `git`'
  )

  -- Repo
  mock_no_git_repo()
  expect.error(
    function() child.lua('MiniExtra.pickers.git_hunks()') end,
    '`pickers%.git_hunks` could not find Git repo for ' .. vim.pesc(child.fn.getcwd())
  )
end

T['pickers']['git_hunks()']['validates arguments'] = function()
  mock_git_repo(test_dir_absolute)
  child.fn.chdir(test_dir_absolute)

  local validate = function(local_opts, error_pattern)
    expect.error(function() child.lua('MiniExtra.pickers.git_hunks(...)', { local_opts }) end, error_pattern)
  end

  validate({ n_context = 'a' }, '`n_context`.*`pickers%.git_hunks`.*number')
  validate({ path = '1' }, 'Path.*1 is not a valid path')
  validate({ path = '' }, 'Path.*is empty')
  validate({ scope = '1' }, '`pickers%.git_hunks`.*"scope".*"1".*one of')
end

T['pickers']['hipatterns()'] = new_set()

local pick_hipatterns = forward_lua_notify('MiniExtra.pickers.hipatterns')

local setup_hipatterns = function()
  child.lua('_G.delay = ' .. (2 * small_time))
  child.lua([[require('mini.hipatterns').setup({
    highlighters = {
      minmax = { pattern = { 'min', 'max' }, group = 'Error' },
      ['local'] = { pattern = 'local', group = 'Comment' },
    },
    delay = { text_change = _G.delay },
  })]])
  child.cmd('edit ' .. real_file('a.lua'))
  local buf_id_1 = child.api.nvim_create_buf(true, false)

  local buf_id_2 = child.api.nvim_create_buf(true, false)
  child.api.nvim_set_current_buf(buf_id_2)
  child.api.nvim_buf_set_lines(buf_id_2, 0, -1, false, { '', 'min', 'max', 'local' })
  sleep(2 * small_time + small_time)

  -- Should not be present in results
  local buf_id_not_enabled = child.api.nvim_create_buf(true, false)
  child.api.nvim_buf_set_lines(buf_id_not_enabled, 0, -1, false, { 'min max local' })

  return buf_id_1, buf_id_2
end

T['pickers']['hipatterns()']['works'] = function()
  child.set_size(15, 120)
  local _, buf_id_2 = setup_hipatterns()

  mock_slash_path_sep()
  child.lua_notify('_G.return_item = MiniExtra.pickers.hipatterns()')
  validate_picker_name('Mini.hipatterns matches (all)')
  child.expect_screenshot()

  -- Should highlight highlighter's name with its group
  local ns_id = child.api.nvim_get_namespaces().MiniExtraPickers
  local extmarks = child.api.nvim_buf_get_extmarks(0, ns_id, 0, -1, { details = true })
  local extmark_data = vim.tbl_map(
    function(x)
      return { row = x[2], row_end = x[4].end_row, col = x[3], col_end = x[4].end_col, hl_group = x[4].hl_group }
    end,
    extmarks
  )
  --stylua: ignore
  eq(extmark_data, {
    { hl_group = 'Comment', row = 0, row_end = 0, col = 0, col_end = 5 },
    { hl_group = 'Comment', row = 1, row_end = 1, col = 0, col_end = 5 },
    { hl_group = 'Error',   row = 2, row_end = 2, col = 0, col_end = 6 },
    { hl_group = 'Error',   row = 3, row_end = 3, col = 0, col_end = 6 },
    { hl_group = 'Comment', row = 4, row_end = 4, col = 0, col_end = 5 },
    { hl_group = 'Error',   row = 5, row_end = 5, col = 0, col_end = 6 },
    { hl_group = 'Error',   row = 6, row_end = 6, col = 0, col_end = 6 },
  })

  -- Can preview match region
  type_keys('<C-p>', '<Tab>')
  child.expect_screenshot()

  -- Should properly choose by positioning on region start
  type_keys('<CR>')
  eq(child.api.nvim_get_current_buf(), buf_id_2)
  eq(get_cursor(), { 3, 0 })

  -- Should return chosen value
  eq(child.lua_get('_G.return_item'), {
    bufnr = buf_id_2,
    highlighter = 'minmax',
    hl_group = 'Error',
    lnum = 3,
    end_lnum = 3,
    col = 1,
    end_col = 4,
    text = 'minmax │ Buffer_3│3│1│max',
  })

  -- Should work without set up 'mini.pick'
  child.mini_unload('pick')
  pick_hipatterns()
  validate_active_picker()
end

T['pickers']['hipatterns()']['respects `local_opts.scope`'] = function()
  child.set_size(15, 50)
  setup_hipatterns()
  pick_hipatterns({ scope = 'current' })
  validate_picker_name('Mini.hipatterns matches (current)')
  child.expect_screenshot()
end

T['pickers']['hipatterns()']['respects `local_opts.highlighters`'] = function()
  child.set_size(15, 120)
  setup_hipatterns()

  mock_slash_path_sep()
  pick_hipatterns({ highlighters = { 'minmax' } })
  child.expect_screenshot()
  stop_picker()

  -- Empty table
  pick_hipatterns({ highlighters = {} })
  eq(get_picker_items(), {})
end

T['pickers']['hipatterns()']['respects `opts`'] = function()
  setup_hipatterns()
  pick_hipatterns({}, { source = { name = 'My name' } })
  validate_picker_name('My name')
end

T['pickers']['hipatterns()']['respects global source options'] = function()
  setup_hipatterns()
  validate_global_source_options(pick_hipatterns, true, true)
end

T['pickers']['hipatterns()']["checks for present 'mini.hipatterns'"] = function()
  child.lua([[
    local require_orig = require
    require = function(x)
      if x == 'mini.hipatterns' then error() end
      require_orig(x)
    end
  ]])
  expect.error(function() child.lua('MiniExtra.pickers.hipatterns()') end, '`pickers%.hipatterns`.*mini%.hipatterns')
end

T['pickers']['hipatterns()']['validates arguments'] = function()
  local validate = function(local_opts, error_pattern)
    expect.error(function() child.lua('MiniExtra.pickers.hipatterns(...)', { local_opts }) end, error_pattern)
  end

  validate({ scope = '1' }, '`pickers%.hipatterns`.*"scope".*"1".*one of')
  validate({ highlighters = '1' }, '`local_opts%.highlighters.*array')
end

T['pickers']['history()'] = new_set({
  hooks = {
    pre_case = function()
      child.cmd('set history=100')

      -- Command-line history
      child.lua('_G.n = 0')
      type_keys(':lua _G.n = _G.n + 1<CR>')
      type_keys(':lua _G.n = _G.n + 2<CR>')

      -- Search history
      child.api.nvim_buf_set_lines(0, 0, -1, false, { 'aaa', 'bbb' })
      type_keys('/aaa<CR>')
      type_keys('/bbb<CR>')

      -- Expressions history
      type_keys('O', '<C-r>=1+1<CR>', '<Esc>')
      type_keys('o', '<C-r>=2+2<CR>', '<Esc>')

      -- Input history
      child.lua_notify([[vim.fn.input('Prompt')]])
      type_keys('input 1', '<CR>')
      child.lua_notify([[vim.fn.input('Prompt')]])
      type_keys('input 2', '<CR>')

      -- Debug mode
      -- Can't really emulate debug mode

      child.api.nvim_buf_set_lines(0, 0, -1, false, {})
    end,
  },
})

local pick_history = forward_lua_notify('MiniExtra.pickers.history')

T['pickers']['history()']['works'] = function()
  child.set_size(20, 70)

  child.lua_notify('_G.return_item = MiniExtra.pickers.history()')
  -- - Should by default list all history
  validate_picker_name('History (all)')
  child.expect_screenshot()

  -- Should have no preview
  type_keys('<Tab>')
  child.expect_screenshot()

  -- Should return chosen value with proper structure
  type_keys('<CR>')
  eq(child.lua_get('_G.return_item'), ': lua _G.n = _G.n + 2')

  -- Should work without set up 'mini.pick'
  child.mini_unload('pick')
  pick_history()
  validate_active_picker()
end

T['pickers']['history()']['works for command-line history'] = function()
  -- Works
  pick_history({ scope = 'cmd' })
  eq(get_picker_items(), { ': lua _G.n = _G.n + 2', ': lua _G.n = _G.n + 1' })
  validate_picker_name('History (cmd)')

  -- Should execute command on choose
  local n = child.lua_get('_G.n')
  type_keys('<C-n>', '<CR>')
  eq(child.lua_get('_G.n'), n + 1)

  -- Should work with aliases
  pick_history({ scope = ':' })
  validate_picker_name('History (:)')
  -- Should update command line history
  eq(get_picker_items(), { ': lua _G.n = _G.n + 1', ': lua _G.n = _G.n + 2' })
end

T['pickers']['history()']['works for search history'] = function()
  set_lines({ 'bbb', '  aaa' })

  -- Works
  pick_history({ scope = 'search' })
  validate_picker_name('History (search)')
  eq(get_picker_items(), { '/ bbb', '/ aaa' })

  -- Should restart search on choose (and update history)
  type_keys('<C-n>', '<CR>')
  eq(get_cursor(), { 2, 2 })
  eq(child.o.hlsearch, true)
  -- - `:history` lists from oldest to newest
  expect.match(child.cmd_capture('history search'), 'bbb.*aaa')

  -- Should work with aliases
  pick_history({ scope = '/' })
  validate_picker_name('History (/)')
  -- - Should have updated the history
  eq(get_picker_items(), { '/ aaa', '/ bbb' })
  stop_picker()

  -- - For `?` alias should search backward
  set_lines({ 'aaa', 'bbb', 'aaa' })
  set_cursor(2, 0)
  pick_history({ scope = '?' })
  validate_picker_name('History (?)')
  eq(get_picker_items(), { '? aaa', '? bbb' })

  type_keys('<CR>')
  eq(get_cursor(), { 1, 0 })
  eq(child.o.hlsearch, true)
end

T['pickers']['history()']['works for expression register history'] = function()
  pick_history({ scope = 'expr' })
  validate_picker_name('History (expr)')
  eq(get_picker_items(), { '= 2+2', '= 1+1' })

  -- Nothing is expected to be done on choose
  type_keys('<CR>')

  -- Should work with aliases
  pick_history({ scope = '=' })
  validate_picker_name('History (=)')
  eq(get_picker_items(), { '= 2+2', '= 1+1' })
end

T['pickers']['history()']['works for input history'] = function()
  pick_history({ scope = 'input' })
  validate_picker_name('History (input)')
  eq(get_picker_items(), { '@ input 2', '@ input 1' })

  -- Nothing is expected to be done on choose
  type_keys('<CR>')

  -- Should work with aliases
  pick_history({ scope = '@' })
  validate_picker_name('History (@)')
  eq(get_picker_items(), { '@ input 2', '@ input 1' })
end

T['pickers']['history()']['works with too wide entries'] = function()
  child.set_size(10, 15)
  pick_history({ scope = 'cmd' })
  eq(get_picker_items(), { ': lua _G.n = _G.n + 2', ': lua _G.n = _G.n + 1' })
end

T['pickers']['history()']['respects `opts`'] = function()
  pick_history({}, { source = { name = 'My name' } })
  validate_picker_name('My name')
end

T['pickers']['history()']['respects global source options'] = function()
  validate_global_source_options(pick_history, false, false)
end

T['pickers']['history()']['validates arguments'] = function()
  local validate = function(local_opts, error_pattern)
    expect.error(function() child.lua('MiniExtra.pickers.history(...)', { local_opts }) end, error_pattern)
  end
  validate({ scope = '1' }, '`pickers%.history`.*"scope".*"1".*one of')
end

T['pickers']['history()']['has custom "edit_command" mapping'] = function()
  local validate = function(type, content, active)
    eq(child.fn.getcmdtype(), type)
    eq(child.fn.getcmdline(), content)
    eq(is_picker_active(), active)
    type_keys('<C-c>')
  end

  pick_history()
  eq(child.lua_get('MiniPick.get_picker_opts().mappings.edit_command.char'), '<C-e>')
  type_keys(':', '<C-e>')
  validate(':', 'lua _G.n = _G.n + 2', false)

  pick_history()
  type_keys('/', '<C-e>')
  validate('/', 'bbb', false)

  pick_history()
  type_keys('@', '<C-e>')
  validate('', '', true)

  pick_history({ scope = ':' })
  type_keys('<C-e>')
  validate(':', 'lua _G.n = _G.n + 2', false)

  pick_history({ scope = '/' })
  type_keys('<C-e>')
  validate('/', 'bbb', false)
end

T['pickers']['hl_groups()'] = new_set()

local pick_hl_groups = forward_lua_notify('MiniExtra.pickers.hl_groups')

T['pickers']['hl_groups()']['works'] = function()
  child.set_size(10, 80)

  child.lua_notify('_G.return_item = MiniExtra.pickers.hl_groups()')
  validate_picker_name('Highlight groups')
  type_keys('^Spell')
  child.expect_screenshot({ ignore_text = { 9 } })

  -- Should use same group for line highlighting
  local matches = get_picker_matches().all
  validate_partial_equal_arr(get_extra_picker_extmarks(0, -1), {
    { row = 0, col = 0, hl_group = matches[1] },
    { row = 1, col = 0, hl_group = matches[2] },
    { row = 2, col = 0, hl_group = matches[3] },
    { row = 3, col = 0, hl_group = matches[4] },
  })

  -- Should have proper preview
  type_keys('<Tab>')
  child.expect_screenshot({ ignore_text = { 9 } })

  -- Should properly choose
  type_keys('<CR>')
  eq(child.fn.getcmdline(), 'hi SpellBad cterm=undercurl gui=undercurl guisp=#eab3d9')
  eq(child.fn.getcmdpos(), 56)

  -- Should return chosen value
  eq(child.lua_get('_G.return_item'), 'SpellBad')

  -- Should work without set up 'mini.pick'
  child.mini_unload('pick')
  pick_hl_groups()
  validate_active_picker()
end

T['pickers']['hl_groups()']['respects non-default/linked highlight groups'] = function()
  child.set_size(10, 40)
  child.cmd('hi AAAA guifg=#aaaaaa')
  child.cmd('hi link AAAB AAAA')

  pick_hl_groups()
  type_keys('^AAA')
  child.expect_screenshot()
  validate_partial_equal_arr(get_extra_picker_extmarks(0, -1), {
    { row = 0, col = 0, hl_group = 'AAAA' },
    { row = 1, col = 0, hl_group = 'AAAB' },
  })
end

T['pickers']['hl_groups()']['respects `opts`'] = function()
  pick_hl_groups({}, { source = { name = 'My name' } })
  validate_picker_name('My name')
end

T['pickers']['hl_groups()']['respects global source options'] = function()
  validate_global_source_options(pick_hl_groups, false, false)
end

T['pickers']['keymaps()'] = new_set()

local pick_keymaps = forward_lua_notify('MiniExtra.pickers.keymaps')

local setup_keymaps = function()
  local all_modes = { 'n', 'x', 's', 'o', 'i', 'l', 'c', 't' }

  for _, mode in ipairs(all_modes) do
    -- Remove all built-in mappings
    child.cmd(mode .. 'mapclear')

    -- Make custom mappings for more control in tests
    local rhs = string.format('<Cmd>lua _G.res = "%s"<CR>', mode)
    child.api.nvim_set_keymap(mode, '<Space>' .. mode, rhs, {})
  end

  -- - With description
  child.api.nvim_set_keymap('n', '<Space>d', '<Cmd>lua _G.res = "desc"<CR>', { desc = 'Description' })

  -- - With longer LHS (to test width aligning)
  child.api.nvim_set_keymap('n', '<Space>nnn', '<Cmd>lua _G.res = "long"<CR>', {})

  -- - Buffer local
  child.api.nvim_buf_set_keymap(0, 'n', '<Space>b', '<Cmd>lua _G.res = "buf"<CR>', {})
end

T['pickers']['keymaps()']['works'] = function()
  child.set_size(30, 80)
  setup_keymaps()

  child.lua_notify('_G.return_item = MiniExtra.pickers.keymaps()')
  validate_picker_name('Keymaps (all)')
  child.expect_screenshot()

  -- Should have proper preview
  type_keys('<Tab>')
  child.expect_screenshot()

  -- Should properly choose by executing LHS keys
  type_keys('<CR>')
  eq(child.lua_get('_G.res'), 'buf')

  -- Should return chosen value
  local ref_maparg = child.fn.maparg(' b', 'n', false, true)
  ref_maparg.lhs = child.api.nvim_replace_termcodes(ref_maparg.lhs, true, true, true)
  eq(child.lua_get('_G.return_item'), {
    desc = '<Cmd>lua _G.res = "buf"<CR>',
    lhs = '<Space>b',
    maparg = ref_maparg,
    text = 'n @ │ <Space>b   │ <Cmd>lua _G.res = "buf"<CR>',
  })

  -- Should work without set up 'mini.pick'
  child.mini_unload('pick')
  pick_keymaps()
  validate_active_picker()
end

T['pickers']['keymaps()']['can be chosen in non-Normal modes'] = function()
  setup_keymaps()
  local validate = function(mode, init_keys)
    type_keys(init_keys)
    pick_keymaps()
    type_keys('^' .. mode, '<CR>')
    eq(child.lua_get('_G.res'), mode)
    child.ensure_normal_mode()
  end

  validate('i', 'i')
  validate('x', 'v')
  validate('o', 'd')
  validate('c', ':')
end

T['pickers']['keymaps()']['shows source of Lua callback in preview'] = function()
  child.set_size(20, 100)
  setup_keymaps()
  child.cmd('source ' .. make_testpath('mocks', 'keymaps.lua'))
  pick_keymaps()
  type_keys("'ga ")
  child.expect_screenshot()

  type_keys('<Tab>')
  child.expect_screenshot()
  type_keys('<C-b>')
  child.expect_screenshot()
end

T['pickers']['keymaps()']['respects `local_opts.mode`'] = function()
  child.lua([[
    _G.all_items_same_mode = function(mode)
      for _, item in ipairs(MiniPick.get_picker_items()) do
        local char = item.text:sub(1, 1)
        -- Allow 'v' mode mappings when 'x' or 's' is requested
        local is_v_mode = mode == 'x' or mode == 's'
        if not (char == mode or (is_v_mode and char == 'v')) then return false end
      end
      return true
    end
  ]])
  local validate = function(mode)
    pick_keymaps({ mode = mode })
    local lua_cmd = string.format('_G.all_items_same_mode(%s)', vim.inspect(mode))
    eq(child.lua_get(lua_cmd), true)
    stop_picker()
  end

  validate('n')
  validate('x')
  validate('s')
  validate('o')
  validate('i')
  validate('l')
  validate('c')
  validate('t')
end

T['pickers']['keymaps()']['respects `local_opts.scope`'] = function()
  setup_keymaps()

  local has_scopes = function()
    local has_global, has_buf = false, false
    for _, item in ipairs(get_picker_items()) do
      local is_buffer = item.text:sub(3, 3) == '@'
      if is_buffer then has_buf = true end
      if not is_buffer then has_global = true end
    end
    return { global = has_global, buf = has_buf }
  end

  pick_keymaps({ scope = 'global' })
  eq(has_scopes(), { global = true, buf = false })
  stop_picker()

  pick_keymaps({ scope = 'buf' })
  eq(has_scopes(), { global = false, buf = true })
  stop_picker()
end

T['pickers']['keymaps()']['respects `opts`'] = function()
  pick_keymaps({}, { source = { name = 'My name' } })
  validate_picker_name('My name')
end

T['pickers']['keymaps()']['respects global source options'] = function()
  validate_global_source_options(pick_keymaps, false, false)
end

T['pickers']['keymaps()']['validates arguments'] = function()
  local validate = function(local_opts, error_pattern)
    expect.error(function() child.lua('MiniExtra.pickers.keymaps(...)', { local_opts }) end, error_pattern)
  end

  validate({ mode = '1' }, '`pickers%.keymaps`.*"mode".*"1".*one of')
  validate({ scope = '1' }, '`pickers%.keymaps`.*"scope".*"1".*one of')
end

T['pickers']['list()'] = new_set()

local pick_list = forward_lua_notify('MiniExtra.pickers.list')

local validate_qf_loc = function(scope)
  child.set_size(20, 70)

  -- Setup quickfix/location list
  mock_slash_path_sep()
  local path = real_file('a.lua')
  child.cmd('edit ' .. path)
  child.cmd('enew')
  local buf_cur = child.api.nvim_get_current_buf()
  set_lines({ 'aaaaa', 'bbbbb', 'ccccc', 'ddddd', 'eeeee' })
  local list = {
    { filename = full_path(path), lnum = 1, col = 7, text = 'File' },
    { bufnr = buf_cur, lnum = 2, col = 2, text = 'Buffer' },
    { bufnr = buf_cur, lnum = 3, col = 3, end_lnum = 4, end_col = 4 },
  }
  if scope == 'quickfix' then child.fn.setqflist(list) end
  if scope == 'location' then child.fn.setloclist(0, list) end

  -- Start picker
  child.lua_notify('_G.return_item = MiniExtra.pickers.list({ scope = ' .. vim.inspect(scope) .. ' })')
  validate_picker_name('List (' .. scope .. ')')
  child.expect_screenshot()

  -- Should preview position/region
  type_keys('<Tab>')
  child.expect_screenshot()
  type_keys('<C-n>')
  child.expect_screenshot()
  type_keys('<C-n>')
  child.expect_screenshot()

  -- Should properly choose by positioning on region start
  type_keys('<CR>')
  eq(child.api.nvim_get_current_buf(), buf_cur)
  eq(get_cursor(), { 3, 2 })

  -- Should return chosen value
  validate_partial_equal_arr(
    { child.lua_get('_G.return_item') },
    { { bufnr = 2, lnum = 3, end_lnum = 4, col = 3, end_col = 4, text = 'Buffer_2│3│3' } }
  )
end

T['pickers']['list()']['works for `quickfix`'] = function() validate_qf_loc('quickfix') end

T['pickers']['list()']['works for `location`'] = function() validate_qf_loc('location') end

T['pickers']['list()']['works for `jump`'] = function()
  child.set_size(20, 70)

  -- Setup jump list
  local path = real_file('a.lua')
  child.cmd('edit ' .. path)
  type_keys('G')

  child.cmd('enew')
  local buf_cur = child.api.nvim_get_current_buf()
  set_lines({ 'aaaaa', 'bbbbb' })
  type_keys('G', 'gg')

  -- Start picker
  mock_slash_path_sep()
  child.lua_notify([[_G.return_item = MiniExtra.pickers.list({ scope = 'jump' })]])
  validate_picker_name('List (jump)')
  child.expect_screenshot()

  -- Should preview position
  type_keys('<Tab>')
  child.expect_screenshot()

  -- Should properly choose by moving to position
  type_keys('<CR>')
  eq(child.api.nvim_get_current_buf(), buf_cur)
  eq(get_cursor(), { 2, 0 })

  -- Should return chosen value
  validate_partial_equal_arr(
    { child.lua_get('_G.return_item') },
    { { bufnr = buf_cur, lnum = 2, col = 1, text = 'Buffer_2│2│1' } }
  )
end

T['pickers']['list()']['works for `change`'] = function()
  child.set_size(20, 70)

  -- Setup jump list
  local path = real_file('a.lua'):gsub('\\', '/')
  child.cmd('edit ' .. path)
  set_cursor(1, 1)
  type_keys('i', ' Change 1 ', '<Esc>')

  set_cursor(3, 3)
  type_keys('i', ' Change 2 ', '<Esc>')

  -- Start picker
  mock_slash_path_sep()
  child.lua_notify([[_G.return_item = MiniExtra.pickers.list({ scope = 'change' })]])
  validate_picker_name('List (change)')
  child.expect_screenshot()

  -- Should preview position
  type_keys('<Tab>')
  child.expect_screenshot()

  -- Should properly choose by moving to position
  type_keys('<CR>')
  eq(get_cursor(), { 1, 10 })

  -- Should return chosen value
  validate_partial_equal_arr(
    { child.lua_get('_G.return_item') },
    { { bufnr = 1, col = 11, coladd = 0, lnum = 1, text = path .. '│1│11' } }
  )
end

T['pickers']['list()']['works with empty list'] = function()
  local validate = function(scope)
    pick_list({ scope = scope })
    eq(get_picker_items(), {})
    stop_picker()
  end

  validate('quickfix')
  validate('location')
  validate('jump')
  validate('change')
end

T['pickers']['list()']['respects `opts`'] = function()
  pick_list({ scope = 'jump' }, { source = { name = 'My name' } })
  validate_picker_name('My name')
end

T['pickers']['list()']['respects global source options'] = function()
  local path = real_file('a.lua')
  child.cmd('edit ' .. path)
  type_keys('G')
  type_keys('gg')
  validate_global_source_options(function() pick_list({ scope = 'jump' }) end, true, false)
end

T['pickers']['list()']['validates arguments'] = function()
  local validate = function(local_opts, error_pattern)
    expect.error(function() child.lua('MiniExtra.pickers.list(...)', { local_opts }) end, error_pattern)
  end

  validate({}, '`pickers%.list` needs an explicit scope')
  validate({ scope = '1' }, '`pickers%.list`.*"scope".*"1".*one of')
end

T['pickers']['lsp()'] = new_set()

local pick_lsp = forward_lua_notify('MiniExtra.pickers.lsp')

local setup_lsp = function()
  child.set_size(15, 90)

  -- Set up file
  local file_path = real_file('a.lua')
  child.cmd('edit ' .. file_path)

  -- Mock server
  child.cmd('luafile tests/mock-lsp/extra.lua')

  return file_path, full_path(file_path)
end

local scope_to_request = {
  declaration = 'textDocument/declaration',
  definition = 'textDocument/definition',
  document_symbol = 'textDocument/documentSymbol',
  implementation = 'textDocument/implementation',
  references = 'textDocument/references',
  type_definition = 'textDocument/typeDefinition',
  workspace_symbol = 'workspace/symbol',
  workspace_symbol_live = 'workspace/symbol',
}

local validate_location_scope = function(scope)
  local file_path, file_path_full = setup_lsp()

  mock_slash_path_sep()
  pick_lsp({ scope = scope })
  eq(child.lua_get('_G.lsp_requests'), { scope_to_request[scope] })
  validate_picker_name('LSP (' .. scope .. ')')
  child.expect_screenshot()

  -- Should preview position
  type_keys('<Tab>')
  child.expect_screenshot()
  unmock_slash_path_sep()

  -- Should have proper items
  local ref_item = {
    filename = file_path_full,
    path = file_path_full,
    lnum = 3,
    col = 16,
    end_lnum = 3,
    end_col = 17,
    text = file_path:gsub('\\', '/') .. '│3│16│   x = math.max(a, 2),',
    user_data = {
      range = { start = { line = 2, character = 15 }, ['end'] = { line = 2, character = 16 } },
      uri = 'file://' .. (helpers.is_windows() and '/' or '') .. file_path_full:gsub('\\', '/'),
    },
  }
  if child.fn.has('nvim-0.11') == 0 then
    ref_item.end_lnum, ref_item.end_col = nil, nil
  end
  if child.fn.has('nvim-0.10') == 0 then ref_item.user_data = nil end
  eq(get_picker_items()[1], ref_item)

  -- Should properly choose by moving to the position
  type_keys('<CR>')
  validate_buf_name(0, file_path)
  eq(get_cursor(), { 3, 15 })

  -- Should open path in relative form for nicer `:buffers`.
  -- It isn't testing much as `vim.lsp.buf` is mocked, but just in case.
  expect.match(child.cmd_capture('buffers'):gsub('\\', '/'), '[^/]' .. vim.pesc(file_path:gsub('\\', '/')))
end

local validate_symbol_scope = function(scope, skip_preview)
  local file_path, file_path_full = setup_lsp()

  mock_slash_path_sep()
  pick_lsp({ scope = scope })
  validate_picker_name('LSP (' .. scope .. ')')
  eq(child.lua_get('_G.lsp_requests'), { scope_to_request[scope] })
  if scope == 'workspace_symbol' then eq(child.lua_get('_G.params.query'), '') end
  child.expect_screenshot()

  -- Should highlight some symbols
  local has_mini_icons = child.lua_get('_G.MiniIcons ~= nil')
  local ref_extmark_data = {
    { hl_group = '@number', row = 0, col = 0 },
    { hl_group = '@object', row = 1, col = 0 },
    { hl_group = '@variable', row = 2, col = 0 },
    { hl_group = '@variable', row = 3, col = 0 },
  }
  if has_mini_icons then
    ref_extmark_data[1].hl_group = 'MiniIconsOrange'
    ref_extmark_data[2].hl_group = 'MiniIconsGrey'
    ref_extmark_data[3].hl_group = 'MiniIconsCyan'
    ref_extmark_data[4].hl_group = 'MiniIconsCyan'
  end
  eq(get_extra_picker_extmarks(0, -1), ref_extmark_data)

  -- Should preview position
  if not skip_preview then
    type_keys('<Tab>')
    child.expect_screenshot()
  end
  unmock_slash_path_sep()

  -- Should have proper items
  local text_prefix = scope == 'workspace_symbol' and (file_path:gsub('\\', '/') .. '│1│7│ ') or ''
  local kind_name = child.lua_get('vim.lsp.protocol.SymbolKind[16]')
  -- - Icon should be added only if it is not already assumed to be inside
  --   `SymbolKind` map (as after `MiniIcons.tweak_lsp_kind()`).
  if has_mini_icons and kind_name == 'Number' then text_prefix = ' ' .. text_prefix end
  local ref_item = {
    filename = file_path_full,
    path = file_path_full,
    lnum = 1,
    col = 7,
    end_lnum = 1,
    end_col = 8,
    kind = 'Number',
    text = text_prefix .. '[' .. kind_name .. '] a',
    hl = ref_extmark_data[1].hl_group,
  }
  if child.fn.has('nvim-0.11') == 0 then
    ref_item.end_lnum, ref_item.end_col = nil, nil
  end
  eq(get_picker_items()[1], ref_item)

  -- Should properly choose by moving to the position
  type_keys('<CR>')
  validate_buf_name(0, file_path)
  eq(get_cursor(), { 1, 6 })

  -- Should open path in relative form for nicer `:buffers`.
  -- It isn't testing much as `vim.lsp.buf` is mocked, but just in case.
  expect.match(child.cmd_capture('buffers'):gsub('\\', '/'), '[^/]' .. vim.pesc(file_path:gsub('\\', '/')))
end

local validate_symbol_scope_with_tweaked_kind = function(scope, tweak_lsp_kind_mode)
  child.lua('_G.symbol_kind_orig = vim.deepcopy(vim.lsp.protocol.SymbolKind)')
  child.lua("require('mini.icons').setup()")
  child.lua('MiniIcons.tweak_lsp_kind(...)', { tweak_lsp_kind_mode })

  validate_symbol_scope(scope, true)

  child.lua('vim.lsp.protocol.SymbolKind = _G.symbol_kind_orig')
end

T['pickers']['lsp()']['works for `declaration`'] = function() validate_location_scope('declaration') end

T['pickers']['lsp()']['works for `definition`'] = function() validate_location_scope('definition') end

T['pickers']['lsp()']['works for `document_symbol`'] = function() validate_symbol_scope('document_symbol') end

T['pickers']['lsp()']["works for `document_symbol` with 'mini.icons' set up"] = function()
  child.lua("require('mini.icons').setup()")
  validate_symbol_scope('document_symbol')
end

T['pickers']['lsp()']['works for `document_symbol` after `MiniIcons.tweak_lsp_kind()`'] = function()
  validate_symbol_scope_with_tweaked_kind('document_symbol', 'prepend')
  validate_symbol_scope_with_tweaked_kind('document_symbol', 'append')
  validate_symbol_scope_with_tweaked_kind('document_symbol', 'replace')
end

T['pickers']['lsp()']['works for `implementation`'] = function() validate_location_scope('implementation') end

T['pickers']['lsp()']['works for `references`'] = function()
  local file_path, file_path_full = setup_lsp()

  mock_slash_path_sep()
  pick_lsp({ scope = 'references' })
  validate_picker_name('LSP (references)')
  eq(child.lua_get('_G.lsp_requests'), { 'textDocument/references' })
  child.expect_screenshot()

  -- Should preview position
  type_keys('<C-n>', '<Tab>')
  child.expect_screenshot()
  unmock_slash_path_sep()

  -- Should have proper items
  local ref_item = {
    filename = file_path_full,
    path = file_path_full,
    lnum = 3,
    col = 16,
    end_lnum = 3,
    end_col = 17,
    text = file_path:gsub('\\', '/') .. '│3│16│   x = math.max(a, 2),',
    user_data = {
      uri = 'file://' .. (helpers.is_windows() and '/' or '') .. file_path_full:gsub('\\', '/'),
      range = { start = { line = 2, character = 15 }, ['end'] = { line = 2, character = 16 } },
    },
  }
  if child.fn.has('nvim-0.11') == 0 then
    ref_item.end_lnum, ref_item.end_col = nil, nil
  end
  if child.fn.has('nvim-0.10') == 0 then ref_item.user_data = nil end
  eq(get_picker_items()[2], ref_item)

  -- Should properly choose by moving to the position
  type_keys('<CR>')
  validate_buf_name(0, file_path)
  eq(get_cursor(), { 3, 15 })
end

T['pickers']['lsp()']['works for `type_definition`'] = function() validate_location_scope('type_definition') end

T['pickers']['lsp()']['works for `workspace_symbol`'] = function() validate_symbol_scope('workspace_symbol') end

T['pickers']['lsp()']["works for `workspace_symbol` with 'mini.icons' set up"] = function()
  child.lua("require('mini.icons').setup()")
  validate_symbol_scope('workspace_symbol')
end

T['pickers']['lsp()']['works for `workspace_symbol` after `MiniIcons.tweak_lsp_kind()`'] = function()
  validate_symbol_scope_with_tweaked_kind('workspace_symbol', 'prepend')
  validate_symbol_scope_with_tweaked_kind('workspace_symbol', 'append')
  validate_symbol_scope_with_tweaked_kind('workspace_symbol', 'replace')
end

T['pickers']['lsp()']['works for `workspace_symbol_live`'] = function()
  setup_lsp()
  mock_slash_path_sep()

  -- Test only "live" part in the hope that "workspace_symbol" part is the same
  local validate = function(n_requests, query)
    local ref_requests, lsp_method = {}, scope_to_request.workspace_symbol_live
    for i = 1, n_requests do
      ref_requests[i] = lsp_method
    end
    eq(child.lua_get('_G.lsp_requests'), ref_requests)
    eq(child.lua_get('_G.params'), query ~= nil and { query = query } or vim.NIL)

    child.lua('_G.lsp_requests, _G.params = {}, nil')
  end

  -- Should not do any request on start
  pick_lsp({ scope = 'workspace_symbol_live' })
  validate_picker_name('LSP (workspace_symbol_live)')
  validate(0, nil)
  eq(get_picker_items(), {})

  -- Should make new request on every picker query change
  type_keys('a')
  validate(1, 'a')

  type_keys('x')
  validate(1, 'ax')

  -- Should not make request for empty query and show no items instead
  type_keys('<C-u>')
  validate(0, nil)
  eq(get_picker_items(), {})
end

T['pickers']['lsp()']['respects `local_opts.symbol_query`'] = function()
  setup_lsp()

  pick_lsp({ scope = 'workspace_symbol', symbol_query = 'aaa' })
  eq(child.lua_get('_G.params.query'), 'aaa')
end

T['pickers']['lsp()']['respects `opts`'] = function()
  setup_lsp()
  pick_lsp({ scope = 'references' }, { source = { name = 'My name' } })
  validate_picker_name('My name')
end

T['pickers']['lsp()']['respects global source options'] = function()
  setup_lsp()
  validate_global_source_options(function() pick_lsp({ scope = 'document_symbol' }) end, true, false)
end

T['pickers']['lsp()']['validates arguments'] = function()
  local validate = function(local_opts, error_pattern)
    expect.error(function() child.lua('MiniExtra.pickers.lsp(...)', { local_opts }) end, error_pattern)
  end

  validate({}, '`pickers%.lsp` needs an explicit scope')
  validate({ scope = '1' }, '`pickers%.lsp`.*"scope".*"1".*one of')
end

T['pickers']['marks()'] = new_set()

local pick_marks = forward_lua_notify('MiniExtra.pickers.marks')

local setup_marks = function()
  child.cmd('edit ' .. real_file('a.lua'))
  local buf_file = child.api.nvim_get_current_buf()
  set_cursor(1, 5)
  type_keys('mA')
  set_cursor(1, 0)

  local buf_main = child.api.nvim_create_buf(true, false)
  child.api.nvim_set_current_buf(buf_main)
  set_lines({ 'Line 1-1', 'Line 1-2', 'Line 1-3' })
  set_cursor(1, 3)
  type_keys('ma')
  set_cursor(3, 5)
  type_keys('mb')
  set_cursor(1, 0)

  local buf_alt = child.api.nvim_create_buf(true, false)
  child.api.nvim_set_current_buf(buf_alt)
  set_lines({ 'Line 2-1', 'Line 2-2', 'line 2-3' })
  set_cursor(2, 2)
  type_keys('ma')
  set_cursor(1, 0)

  child.api.nvim_set_current_buf(buf_main)

  return { main = buf_main, alt = buf_alt, file = buf_file }
end

T['pickers']['marks()']['works'] = function()
  child.set_size(20, 70)
  setup_marks()

  mock_slash_path_sep()
  child.lua_notify('_G.return_item = MiniExtra.pickers.marks()')
  validate_picker_name('Marks (all)')
  child.expect_screenshot()

  -- Should preview mark's position
  type_keys('<Tab>')
  child.expect_screenshot()
  type_keys('<C-n>')
  child.expect_screenshot()
  type_keys('<C-n>', '<C-n>', '<C-n>', '<C-n>')
  child.expect_screenshot()
  unmock_slash_path_sep()

  -- Should properly choose by positioning on mark
  local path = real_file('a.lua')
  type_keys('<CR>')
  validate_buf_name(0, path)
  eq(get_cursor(), { 1, 5 })

  -- Should return chosen value
  local path_slash = path:gsub('\\', '/')
  local ref_item = { col = 6, lnum = 1, path = path_slash, text = 'A │ ' .. path_slash .. '│1│6' }
  eq(child.lua_get('_G.return_item'), ref_item)

  -- Should work without set up 'mini.pick'
  child.mini_unload('pick')
  pick_marks()
  validate_active_picker()
end

T['pickers']['marks()']['respects `local_opts.scope`'] = function()
  local buffers = setup_marks()
  child.set_size(15, 40)

  mock_slash_path_sep()
  pick_marks({ scope = 'global' })
  child.expect_screenshot()
  stop_picker()

  pick_marks({ scope = 'buf' })
  validate_picker_name('Marks (buf)')
  child.expect_screenshot()
  stop_picker()

  child.api.nvim_set_current_buf(buffers.alt)
  pick_marks({ scope = 'buf' })
  child.expect_screenshot()
  stop_picker()
end

T['pickers']['marks()']['respects `opts`'] = function()
  pick_marks({}, { source = { name = 'My name' } })
  validate_picker_name('My name')
end

T['pickers']['marks()']['respects global source options'] = function()
  setup_marks()
  validate_global_source_options(pick_marks, true, true)
end

T['pickers']['marks()']['validates arguments'] = function()
  local validate = function(local_opts, error_pattern)
    expect.error(function() child.lua('MiniExtra.pickers.marks(...)', { local_opts }) end, error_pattern)
  end

  validate({ scope = '1' }, '`pickers%.marks`.*"scope".*"1".*one of')
end

T['pickers']['oldfiles()'] = new_set({
  hooks = {
    pre_case = function()
      child.set_size(10, 70)
      mock_slash_path_sep()
    end,
  },
})

local pick_oldfiles = forward_lua_notify('MiniExtra.pickers.oldfiles')

T['pickers']['oldfiles()']['works'] = function()
  local path_1, path_2 = real_file('LICENSE'), make_testpath('mocks', 'diagnostic.lua')
  local ref_oldfiles = { full_path(path_1), full_path(path_2), 'not-existing' }
  child.v.oldfiles = ref_oldfiles

  child.lua_notify('_G.return_item = MiniExtra.pickers.oldfiles()')
  validate_picker_name('Old files')
  child.expect_screenshot()
  unmock_slash_path_sep()

  -- Should have proper items (only readable files with short paths)
  local path_1_slash, path_2_slash = (path_1:gsub('\\', '/')), (path_2:gsub('\\', '/'))
  eq(get_picker_items(), { path_1_slash, path_2_slash })

  -- Should properly choose
  type_keys('<CR>')
  validate_buf_name(0, path_1)
  eq(get_cursor(), { 1, 0 })

  --stylua: ignore
  -- Should return chosen value with proper structure
  eq(child.lua_get('_G.return_item'), path_1_slash)

  -- Should work without set up 'mini.pick'
  child.mini_unload('pick')
  pick_oldfiles()
  validate_active_picker()
end

T['pickers']['oldfiles()']['works with empty `v:oldfiles`'] = function()
  child.v.oldfiles = {}
  pick_oldfiles()
  eq(get_picker_items(), {})
end

T['pickers']['oldfiles()']['can not show icons'] = function()
  child.set_size(10, 70)
  local ref_oldfiles = { full_path(real_file('LICENSE')), full_path(make_testpath('mocks', 'diagnostic.lua')) }
  child.v.oldfiles = ref_oldfiles

  child.lua('MiniPick.config.source.show = MiniPick.default_show')
  pick_oldfiles()
  child.expect_screenshot()
end

T['pickers']['oldfiles()']['respects `local_opts.current_dir'] = function()
  child.set_size(10, 70)
  local ref_oldfiles = { full_path(real_file('LICENSE')), full_path(make_testpath('mocks', 'diagnostic.lua')) }
  child.v.oldfiles = ref_oldfiles

  child.fn.chdir(real_files_dir)
  pick_oldfiles({ current_dir = true })
  local items = get_picker_items()
  -- - Only paths inside current directory are shown
  eq(#items, 1)
  eq(items[1], 'LICENSE')
end

T['pickers']['oldfiles()']['respects `local_opts.preserve_order`'] = function()
  child.lua('vim.fn.filereadable = function() return 1 end')
  child.v.oldfiles = { 'axay', 'b', 'aaxy', 'ccc', 'xaa' }
  pick_oldfiles({ preserve_order = true })

  type_keys('x')
  eq(get_picker_matches().all_inds, { 1, 3, 5 })
  type_keys('y')
  eq(get_picker_matches().all_inds, { 1, 3 })
end

T['pickers']['oldfiles()']['respects `opts`'] = function()
  pick_oldfiles({}, { source = { name = 'My name' } })
  validate_picker_name('My name')
end

T['pickers']['oldfiles()']['respects global source options'] = function()
  local path_1, path_2 = real_file('LICENSE'), make_testpath('mocks', 'diagnostic.lua')
  local ref_oldfiles = { full_path(path_1), full_path(path_2), 'not-existing' }
  child.v.oldfiles = ref_oldfiles
  validate_global_source_options(pick_oldfiles, true, true)
end

T['pickers']['oldfiles()']['respects `opts.source.cwd`'] = function()
  child.set_size(10, 70)
  local ref_oldfiles = { full_path(real_file('LICENSE')), full_path(make_testpath('mocks', 'diagnostic.lua')) }
  child.v.oldfiles = ref_oldfiles

  pick_oldfiles({}, { source = { cwd = real_files_dir } })
  local items = get_picker_items()
  eq(items[1], 'LICENSE')
  -- - For paths not from `cwd` it should shorten home directory to `~`
  expect.match(items[2], vim.pesc(child.fn.fnamemodify(ref_oldfiles[2], ':~')))
end

T['pickers']['options()'] = new_set()

local pick_options = forward_lua_notify('MiniExtra.pickers.options')

T['pickers']['options()']['works'] = function()
  child.set_size(35, 60)

  child.lua_notify('_G.return_item = MiniExtra.pickers.options()')
  validate_picker_name('Options (all)')
  type_keys('^cursor')
  child.expect_screenshot({ ignore_text = { 34 } })

  -- Should have proper preview
  type_keys('<Tab>')
  child.expect_screenshot({ ignore_text = { 34 } })

  -- - Should use proper highlight group for headers
  validate_partial_equal_arr(get_extra_picker_extmarks(0, -1), {
    { row = 0, col = 0, hl_group = 'MiniPickHeader' },
    { row = 3, col = 0, hl_group = 'MiniPickHeader' },
  })

  -- Should properly choose
  type_keys('<CR>')
  eq(child.fn.getcmdline(), 'set cursorbind')
  eq(child.fn.getcmdpos(), 15)

  -- Should return chosen value
  eq(child.lua_get('_G.return_item'), { text = 'cursorbind', info = child.api.nvim_get_option_info2('cursorbind', {}) })

  -- Should work without set up 'mini.pick'
  child.mini_unload('pick')
  pick_options()
  validate_active_picker()
end

T['pickers']['options()']['respects set options'] = function()
  child.set_size(10, 40)
  child.o.cursorline = true
  child.wo.cursorcolumn = true
  child.bo.commentstring = '### %s'

  pick_options()
  type_keys('^cursor')
  child.expect_screenshot()

  -- Should highlight not set options as dimmed
  validate_partial_equal_arr(get_extra_picker_extmarks(0, -1), {
    { row = 0, col = 0, hl_group = 'Comment' },
    { row = 3, col = 0, hl_group = 'Comment' },
  })

  -- Should show valid present value (in the scope of target) window in preview
  -- - Window local option
  type_keys('<C-n>', '<Tab>')
  child.expect_screenshot()

  -- Buffer-local option
  type_keys('<C-u>', '^commentstring', '<Tab>')
  child.expect_screenshot()
end

T['pickers']['options()']['correctly chooses non-binary options'] = function()
  pick_options()
  type_keys('^laststatus', '<CR>')
  eq(child.fn.getcmdline(), 'set laststatus=')
  eq(child.fn.getcmdpos(), 16)
end

T['pickers']['options()']['correctly previews deprecated options'] = function()
  -- There shouldn't be "deprecated" options listed after Neovim 0.11 refactors
  if child.fn.has('nvim-0.11') == 1 then return end
  child.set_size(10, 115)
  pick_options()
  type_keys('^aleph', '<Tab>')
  child.expect_screenshot({ ignore_text = { 9 } })
end

T['pickers']['options()']['respects `local_opts.scope`'] = function()
  local validate = function(scope)
    pick_options({ scope = scope })
    validate_picker_name('Options (' .. scope .. ')')

    if scope == 'all' then return stop_picker() end

    -- Validate proper set of options
    local is_010 = child.fn.has('nvim-0.10') == 1 and child.fn.has('nvim-0.11') == 0
    for _, item in ipairs(get_picker_items()) do
      -- Neovim=0.10 has `nvim_get_option_info2()` throwing error for options
      -- that are obsolete (like 'aleph').
      -- It doesn't happen on Neovim=0.9 or Neovim>=0.11.
      local ok, item_info = pcall(child.api.nvim_get_option_info2, item.text, {})
      local item_scope = (not ok and is_010) and scope or item_info.scope
      eq(item_scope, scope)
    end

    stop_picker()
  end

  validate('all')
  validate('global')
  validate('win')
  validate('buf')
end

T['pickers']['options()']['respects `opts`'] = function()
  pick_options({}, { source = { name = 'My name' } })
  validate_picker_name('My name')
end

T['pickers']['options()']['respects global source options'] = function()
  validate_global_source_options(pick_options, false, false)
end

T['pickers']['options()']['validates arguments'] = function()
  local validate = function(local_opts, error_pattern)
    expect.error(function() child.lua('MiniExtra.pickers.options(...)', { local_opts }) end, error_pattern)
  end

  validate({ scope = '1' }, '`pickers%.options`.*"scope".*"1".*one of')
end

T['pickers']['registers()'] = new_set()

local pick_registers = forward_lua_notify('MiniExtra.pickers.registers')

local setup_registers = function()
  child.fn.setreg('a', 'Register a')
  child.fn.setreg('=', '1 + 1')
  set_lines({ 'Yank register', 'Contains multiline text' })
  type_keys('yj')
  set_lines({})
end

T['pickers']['registers()']['works'] = function()
  child.set_size(80, 40)
  setup_registers()

  -- Mock constant clipboard for better reproducibility of system registers
  -- (mostly on CI). As `setreg('+', '')` is not guaranteed to be working for
  -- system clipboard, use `g:clipboard` which copies/pastes nothing.
  child.lua([[
    local empty = function() return '' end
    vim.g.clipboard = {
      name  = 'myClipboard',
      copy  = { ['+'] = empty, ['*'] = empty },
      paste = { ['+'] = empty, ['*'] = empty },
    }
  ]])

  child.lua_notify('_G.return_item = MiniExtra.pickers.registers()')
  validate_picker_name('Registers')
  child.expect_screenshot()

  -- Should preview register content (even multiline)
  type_keys('<Tab>')
  child.expect_screenshot()

  -- Should properly choose pasting register contents
  type_keys('^a', '<CR>')
  eq(get_lines(), { 'Register a' })

  -- Should return chosen value
  eq(child.lua_get('_G.return_item'), { regname = 'a', regcontents = 'Register a', text = 'a │ Register a' })

  -- Should work without set up 'mini.pick'
  child.mini_unload('pick')
  pick_registers()
  validate_active_picker()
end

T['pickers']['registers()']['can be chosen in non-Normal modes'] = function()
  setup_registers()
  local pick_reg_a = function()
    pick_registers()
    type_keys('^a', '<CR>')
  end

  -- -- Doesn't really work in Visual mode because 'mini.pick' doesn't
  -- type_keys('i', 'toremove', '<Esc>', 'viw')
  -- pick_reg_a()
  -- eq(is_picker_active(), false)
  -- eq(get_lines(), { 'Register a' })
  -- eq(child.fn.mode(), 'v')
  -- child.ensure_normal_mode()
  -- set_lines({})

  -- Insert mode
  type_keys('i')
  pick_reg_a()
  eq(is_picker_active(), false)
  eq(get_lines(), { 'Register a' })
  eq(child.fn.mode(), 'i')
  child.ensure_normal_mode()
  set_lines({})

  -- Command-line mode
  type_keys(':')
  pick_reg_a()
  eq(is_picker_active(), false)
  eq(child.fn.mode(), 'c')
  eq(child.fn.getcmdline(), 'Register a')
  eq(child.fn.getcmdpos(), 11)
  child.ensure_normal_mode()
  set_lines({})
end

T['pickers']['registers()']['works with expression register'] = function()
  setup_registers()
  local pick_expr_reg = function()
    pick_registers()
    type_keys('^=', '<CR>')
  end

  -- Should reevaluate and paste
  -- - Normal mode
  pick_expr_reg()
  eq(get_lines(), { '2' })
  eq(child.fn.mode(), 'n')
  set_lines({})

  -- - Insert mode
  type_keys('i')
  pick_expr_reg()
  eq(get_lines(), { '2' })
  eq(child.fn.mode(), 'i')
  child.ensure_normal_mode()
  set_lines({})

  -- - Command-line mode
  type_keys(':')
  pick_expr_reg()
  eq(child.fn.mode(), 'c')
  eq(child.fn.getcmdline(), '2')
  eq(child.fn.getcmdpos(), 2)
  child.ensure_normal_mode()
  set_lines({})
end

T['pickers']['registers()']['respects `opts`'] = function()
  pick_registers({}, { source = { name = 'My name' } })
  validate_picker_name('My name')
end

T['pickers']['registers()']['respects global source options'] = function()
  setup_registers()
  validate_global_source_options(pick_registers, false, false)
end

T['pickers']['spellsuggest()'] = new_set()

local pick_spellsuggest = forward_lua_notify('MiniExtra.pickers.spellsuggest')

local setup_spell = function()
  set_lines({ 'hello wold' })
  set_cursor(1, 8)
end

T['pickers']['spellsuggest()']['works'] = function()
  child.set_size(15, 70)

  setup_spell()
  child.lua_notify('_G.return_item = MiniExtra.pickers.spellsuggest()')
  validate_picker_name('Spell suggestions for "wold"')
  eq(#get_picker_items(), 25)
  child.expect_screenshot()

  -- Should have no preview
  type_keys('<Tab>')
  child.expect_screenshot()

  -- Should properly choose by replacing suggestion
  type_keys('<CR>')
  eq(get_lines(), { 'hello world' })
  eq(get_cursor(), { 1, 6 })

  -- Should return chosen value
  eq(child.lua_get('_G.return_item'), { index = 1, text = 'world' })

  -- Should work without set up 'mini.pick'
  child.mini_unload('pick')
  pick_spellsuggest()
  validate_active_picker()
end

T['pickers']['spellsuggest()']['respects `local_opts.n_suggestions`'] = function()
  setup_spell()
  pick_spellsuggest({ n_suggestions = 10 })
  eq(#get_picker_items(), 10)
end

T['pickers']['spellsuggest()']['respects `opts`'] = function()
  setup_spell()
  pick_spellsuggest({}, { source = { name = 'My name' } })
  validate_picker_name('My name')
end

T['pickers']['spellsuggest()']['respects global source options'] = function()
  setup_spell()
  validate_global_source_options(pick_spellsuggest, false, false)
end

T['pickers']['spellsuggest()']['validates arguments'] = function()
  local validate = function(local_opts, error_pattern)
    expect.error(function() child.lua('MiniExtra.pickers.spellsuggest(...)', { local_opts }) end, error_pattern)
  end

  validate({ n_suggestions = '1' }, '`local_opts%.n_suggestions.*number')
  validate({ n_suggestions = 0 }, '`local_opts%.n_suggestions.*positive')
end

T['pickers']['treesitter()'] = new_set()

local pick_treesitter = forward_lua_notify('MiniExtra.pickers.treesitter')

local setup_treesitter = function()
  local path = real_file('a.lua')
  child.cmd('edit ' .. path)
  child.lua('vim.treesitter.start()')
  sleep(small_time)

  return path
end

T['pickers']['treesitter()']['works'] = function()
  child.set_size(52, 70)
  local path = setup_treesitter()

  child.lua_notify('_G.return_item = MiniExtra.pickers.treesitter()')
  validate_picker_name('Tree-sitter nodes')
  child.expect_screenshot()

  -- Should preview node's region
  type_keys('<Tab>')
  child.expect_screenshot()
  type_keys('<C-n>')
  child.expect_screenshot()

  -- Should properly choose by positioning on region start
  type_keys('<CR>')
  validate_buf_name(0, path)
  eq(get_cursor(), { 1, 6 })

  -- Should return chosen value
  eq(child.lua_get('_G.return_item'), {
    bufnr = child.api.nvim_get_current_buf(),
    col = 7,
    end_col = 12,
    end_lnum = 1,
    lnum = 1,
    text = ' assignment_statement (1│7 - 1│12)',
  })

  -- Should work without set up 'mini.pick'
  child.mini_unload('pick')
  pick_treesitter()
  validate_active_picker()
end

T['pickers']['treesitter()']['checks for active tree-sitter'] = function()
  expect.error(function() child.lua('MiniExtra.pickers.treesitter()') end, '`pickers%.treesitter`.*parser')
end

T['pickers']['treesitter()']['respects `opts`'] = function()
  setup_treesitter()
  pick_treesitter({}, { source = { name = 'My name' } })
  validate_picker_name('My name')
end

T['pickers']['treesitter()']['respects global source options'] = function()
  setup_treesitter()
  validate_global_source_options(pick_treesitter, true, true)
end

local setup_visits = function()
  -- NOTE: 'mini.visits' uses forward slashes in index
  local dir = test_dir_absolute:gsub('\\', '/')
  local path_1 = full_path(make_testpath('git-files', 'git-file-1')):gsub('\\', '/')
  local path_2 = full_path(make_testpath('git-files', 'git-file-2')):gsub('\\', '/')
  local visit_index = {
    [dir] = {
      [dir .. '/file-xyyx'] = { count = 5, latest = 5 },
      [dir .. '/file-xx'] = { count = 1, labels = { xxx = true, uuu = true }, latest = 10 },
      [dir .. '/file-xyx'] = { count = 10, labels = { xxx = true }, latest = 2 },
      [dir .. '/real-files/a.lua'] = { count = 3, labels = { yyy = true }, latest = 3 },
    },
    [dir .. '/git-files'] = {
      [path_1] = { count = 0, labels = { xxx = true, www = true }, latest = 0 },
      [path_2] = { count = 100, latest = 100 },
    },
  }

  child.lua([[require('mini.visits').set_index(...)]], { visit_index })
  child.fn.chdir(dir)
end

T['pickers']['visit_paths()'] =
  new_set({ hooks = {
    pre_case = function()
      mock_win_functions()
      setup_visits()
    end,
  } })

local pick_visit_paths = forward_lua_notify('MiniExtra.pickers.visit_paths')

T['pickers']['visit_paths()']['works'] = function()
  child.set_size(15, 60)

  child.lua_notify('_G.return_item = MiniExtra.pickers.visit_paths()')
  validate_picker_name('Visit paths (cwd)')
  child.expect_screenshot()

  -- Can preview path
  type_keys('<C-p>', '<Tab>')
  child.expect_screenshot()

  -- Should properly choose
  type_keys('<CR>')
  validate_buf_name(0, join_path('real-files', 'a.lua'))

  -- Should return chosen value
  eq(child.lua_get('_G.return_item'), 'real-files/a.lua')

  -- Should work without set up 'mini.pick'
  child.mini_unload('pick')
  pick_visit_paths()
  validate_active_picker()
end

T['pickers']['visit_paths()']['respects `local_opts.cwd`'] = function()
  pick_visit_paths({ cwd = '' })
  validate_picker_name('Visit paths (all)')
  eq(get_picker_items(), {
    -- Should use short paths relative to the current working directory
    'git-files/git-file-2',
    'file-xyyx',
    'file-xx',
    'file-xyx',
    'real-files/a.lua',
    'git-files/git-file-1',
  })
end

T['pickers']['visit_paths()']['respects `local_opts.filter`'] = function()
  pick_visit_paths({ filter = 'xxx' })
  eq(get_picker_items(), { 'file-xx', 'file-xyx' })
end

T['pickers']['visit_paths()']['respects `local_opts.preserve_order`'] = function()
  -- Should not preserve original sort by default
  pick_visit_paths()
  type_keys('x', 'x')
  eq(get_picker_matches().all, { 'file-xx', 'file-xyx', 'file-xyyx' })
  type_keys('<Esc>')

  -- Should preserve original order with `preserve_order`
  pick_visit_paths({ preserve_order = true })
  type_keys('x', 'x')
  eq(get_picker_matches().all, { 'file-xyyx', 'file-xx', 'file-xyx' })
  type_keys('<Esc>')
end

T['pickers']['visit_paths()']['respects `local_opts.recency_weight`'] = function()
  pick_visit_paths({ recency_weight = 1 })
  eq(get_picker_items(), { 'file-xx', 'file-xyyx', 'real-files/a.lua', 'file-xyx' })
end

T['pickers']['visit_paths()']['respects `local_opts.sort`'] = function()
  child.lua([[_G.sort = function() return { { path = vim.fn.getcwd():gsub('\\', '/') .. '/aaa' } } end]])
  child.lua_notify([[MiniExtra.pickers.visit_paths({ sort = _G.sort })]])
  eq(get_picker_items(), { 'aaa' })
end

T['pickers']['visit_paths()']['can not show icons'] = function()
  child.set_size(15, 60)
  child.lua('MiniPick.config.source.show = MiniPick.default_show')
  pick_visit_paths()
  child.expect_screenshot()
end

T['pickers']['visit_paths()']['respects `opts`'] = function()
  pick_visit_paths({}, { source = { name = 'My name' } })
  validate_picker_name('My name')
end

T['pickers']['visit_paths()']['respects global source options'] = function()
  setup_visits()
  validate_global_source_options(pick_visit_paths, true, true)
end

T['pickers']['visit_paths()']["checks for present 'mini.visits'"] = function()
  child.lua([[
    local require_orig = require
    require = function(x)
      if x == 'mini.visits' then error() end
      require_orig(x)
    end
  ]])
  expect.error(function() child.lua('MiniExtra.pickers.visit_paths()') end, '`pickers%.visit_paths`.*mini%.visits')
end

T['pickers']['visit_paths()']["can open visited directory in 'mini.files'"] = function()
  child.lua([[require('mini.files').setup()]])

  -- NOTE: 'mini.visits' uses forward slashes in index
  local dir = test_dir_absolute:gsub('\\', '/')
  local visit_index = {
    [dir] = {
      [dir .. '/real-files'] = { count = 10, latest = 10 },
    },
  }
  child.lua([[require('mini.visits').set_index(...)]], { visit_index })
  child.fn.chdir(dir)

  child.cmd('edit real-files/a.lua')
  pick_visit_paths()
  child.expect_screenshot()
  type_keys('<CR>')
  child.expect_screenshot()
end

T['pickers']['visit_labels()'] = new_set({ hooks = { pre_case = setup_visits } })

local pick_visit_labels = forward_lua_notify('MiniExtra.pickers.visit_labels')

T['pickers']['visit_labels()']['works'] = function()
  child.set_size(15, 60)

  child.lua_notify('_G.return_item = MiniExtra.pickers.visit_labels()')
  validate_picker_name('Visit labels (cwd)')
  child.expect_screenshot()

  -- Can preview label by showing paths with it
  type_keys('<Tab>')
  child.expect_screenshot()

  -- Should properly choose by starting picking from label paths
  type_keys('<C-p>', '<CR>')
  child.expect_screenshot()

  -- Should properly choose path
  type_keys('<CR>')
  validate_buf_name(0, join_path('real-files', 'a.lua'))

  -- Should return chosen path
  eq(child.lua_get('_G.return_item'), 'real-files/a.lua')

  -- Should work without set up 'mini.pick'
  child.mini_unload('pick')
  pick_visit_labels()
  validate_active_picker()
end

T['pickers']['visit_labels()']['respects `local_opts.cwd`'] = function()
  pick_visit_labels({ cwd = '' })
  validate_picker_name('Visit labels (all)')
  eq(get_picker_items(), { 'xxx', 'uuu', 'www', 'yyy' })
end

T['pickers']['visit_labels()']['respects `local_opts.filter`'] = function()
  child.lua([[_G.filter = function(path_data) return string.find(path_data.path, 'xx') ~= nil end]])
  child.lua_notify('MiniExtra.pickers.visit_labels({ filter = _G.filter })')
  eq(get_picker_items(), { 'uuu', 'xxx' })
end

T['pickers']['visit_labels()']['respects `local_opts.path`'] = function()
  pick_visit_labels({ path = full_path(join_path('real-files', 'a.lua')) })
  eq(get_picker_items(), { 'yyy' })
end

T['pickers']['visit_labels()']['respects `local_opts.sort`'] = function()
  child.set_size(15, 60)
  child.lua([[_G.sort = function() return { { path = vim.fn.getcwd():gsub('\\', '/') .. '/aaa' } } end]])
  child.lua_notify([[MiniExtra.pickers.visit_labels({ sort = _G.sort })]])
  eq(get_picker_items(), { 'xxx', 'uuu', 'yyy' })

  -- Sorting should affect both preview and after choosing
  type_keys('<Tab>')
  child.expect_screenshot()

  type_keys('<CR>')
  eq(get_picker_items(), { 'aaa' })
end

T['pickers']['visit_labels()']['can not show icons after choosing'] = function()
  child.set_size(15, 60)
  child.lua('MiniPick.config.source.show = MiniPick.default_show')
  pick_visit_labels()
  type_keys('<CR>')
  child.expect_screenshot()
end

T['pickers']['visit_labels()']['respects `opts`'] = function()
  pick_visit_labels({}, { source = { name = 'My name' } })
  validate_picker_name('My name')
end

T['pickers']['visit_labels()']['respects global source options'] = function()
  setup_visits()
  validate_global_source_options(pick_visit_labels, false, false)
end

T['pickers']['visit_labels()']["checks for present 'mini.visits'"] = function()
  child.lua([[
    local require_orig = require
    require = function(x)
      if x == 'mini.visits' then error() end
      require_orig(x)
    end
  ]])
  expect.error(function() child.lua('MiniExtra.pickers.visit_labels()') end, '`pickers%.visit_labels`.*mini%.visits')
end

return T
