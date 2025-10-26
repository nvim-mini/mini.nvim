local helpers = dofile('tests/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('diff', config) end
local unload_module = function(config) child.mini_unload('diff', config) end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
local sleep = function(ms) helpers.sleep(ms, child) end
local new_buf = function() return child.api.nvim_create_buf(true, false) end
local new_scratch_buf = function() return child.api.nvim_create_buf(false, true) end
local get_buf = function() return child.api.nvim_get_current_buf() end
local set_buf = function(buf_id) child.api.nvim_set_current_buf(buf_id) end
--stylua: ignore end

-- TODO: Remove after compatibility with Neovim=0.9 is dropped
local islist = vim.fn.has('nvim-0.10') == 1 and vim.islist or vim.tbl_islist

local test_dir = 'tests/dir-diff'
local test_dir_absolute = vim.fs.normalize(vim.fn.fnamemodify(test_dir, ':p')):gsub('(.)/$', '%1')
local test_file_path = test_dir_absolute .. '/file'

local git_repo_dir = test_dir_absolute .. '/git-repo'
local git_git_dir = git_repo_dir .. '/.git-dir'
local git_dir_path = git_repo_dir .. '/dir-in-git'
local git_file_basename = 'file-in-git'
local git_file_path = git_repo_dir .. '/dir-in-git/' .. git_file_basename

local forward_lua = function(fun_str)
  local lua_cmd = fun_str .. '(...)'
  return function(...) return child.lua_get(lua_cmd, { ... }) end
end

-- Time constants
local default_watch_debounce_delay = 50
local dummy_text_change_delay = helpers.get_time_const(30)
local small_time = helpers.get_time_const(10)
local micro_time = 1

-- Common wrappers
local edit = function(path)
  child.cmd('edit ' .. child.fn.fnameescape(path))
  -- Slow context needs a small delay to get things up to date
  if helpers.is_slow() then sleep(small_time) end
end

local set_ref_text = function(...)
  child.lua([[require('mini.diff').set_ref_text(...)]], { ... })
  -- Slow context needs a small delay to get things up to date
  if helpers.is_slow() then sleep(small_time) end
end

local get_buf_hunks = function(buf_id)
  buf_id = buf_id or 0
  return child.lua_get('require("mini.diff").get_buf_data(' .. buf_id .. ').hunks')
end

local get_buf_data = function(buf_id)
  return child.lua(
    [[
      local res = require('mini.diff').get_buf_data(...)
      if res == nil then return nil end
      -- Can not return callables from child process
      res.config.source = nil
      return res
    ]],
    { buf_id }
  )
end

local is_buf_enabled = function(buf_id) return get_buf_data(buf_id) ~= vim.NIL end

-- - Dummy source, which is set by default in most tests
local setup_with_dummy_source = function(text_change_delay)
  text_change_delay = text_change_delay or dummy_text_change_delay
  child.lua('_G.text_change_delay = ' .. text_change_delay)
  child.lua([[
    _G.dummy_log = {}
    _G.dummy_source = {
      name = 'dummy',
      attach = function(...) table.insert(_G.dummy_log, { 'attach', { ... } }) end,
      detach = function(...) table.insert(_G.dummy_log, { 'detach', { ... } }) end,
      apply_hunks = function(...) table.insert(_G.dummy_log, { 'apply_hunks', { ... } }) end,
    }
    require('mini.diff').setup({ source = _G.dummy_source, delay = { text_change = _G.text_change_delay } })
  ]])
end

local validate_dummy_log = function(ref_log) eq(child.lua_get('_G.dummy_log'), ref_log) end

local clean_dummy_log = function() child.lua('_G.dummy_log = {}') end

-- - Git mocks
local mock_count_set_ref_text = function()
  child.lua([[
    local set_ref_text_orig = MiniDiff.set_ref_text
    _G.n_set_ref_text_calls = 0
    MiniDiff.set_ref_text = function(...)
      _G.n_set_ref_text_calls = _G.n_set_ref_text_calls + 1
      set_ref_text_orig(...)
    end
  ]])
end

local mock_change_git_index = function()
  local index_path = git_git_dir .. '/index'
  child.fn.writefile({}, index_path .. '.lock')
  sleep(micro_time)
  child.fn.delete(index_path)
  child.loop.fs_rename(index_path .. '.lock', index_path)
end

local mock_spawn = function()
  local mock_file = test_dir_absolute .. '/mocks/spawn.lua'
  local lua_cmd = string.format('dofile(%s)', vim.inspect(mock_file))
  child.lua(lua_cmd)
end

local get_spawn_log = function() return child.lua_get('_G.spawn_log') end

local validate_git_spawn_log = function(ref_log)
  local spawn_log = get_spawn_log()

  local n = math.max(#spawn_log, #ref_log)
  for i = 1, n do
    local real, ref = spawn_log[i], ref_log[i]
    if real == nil then
      eq('Real spawn log does not have entry for present reference log entry', ref)
    elseif ref == nil then
      eq(real, 'Reference does not have entry for present spawn log entry')
    elseif islist(ref) then
      eq(real, { executable = 'git', options = { args = ref, cwd = real.options.cwd } })
    else
      if real.options.cwd ~= nil then real.options.cwd = child.fs.normalize(real.options.cwd) end
      eq(real, { executable = 'git', options = ref })
    end
  end
end

local get_process_log = function() return child.lua_get('_G.process_log') end

-- - Notifications
local mock_notify = function()
  child.lua([[
    _G.notify_log = {}
    vim.notify = function(...) table.insert(_G.notify_log, { ... }) end
  ]])
end

local get_notify_log = function() return child.lua_get('_G.notify_log') end

local validate_notifications = function(ref_log, msg_pattern)
  local notify_log = get_notify_log()
  local n = math.max(#notify_log, #ref_log)
  for i = 1, n do
    local real, ref = notify_log[i], ref_log[i]
    if real == nil then
      eq('Real notify log does not have entry for present reference log entry', ref)
    elseif ref == nil then
      eq(real, 'Reference does not have entry for present notify log entry')
    else
      local expect_msg = msg_pattern and expect.match or eq
      expect_msg(real[1], ref[1])
      eq(real[2], child.lua_get('vim.log.levels.' .. ref[2]))
    end
  end
end

local clear_notify_log = function() return child.lua('_G.notify_log = {}') end

-- Module helpers
local setup_enabled_buffer = function()
  -- Usually used to make tests on not initial (kind of special) buffer
  local init_buf_id = get_buf()
  set_buf(new_buf())
  child.lua('MiniDiff.enable(0)')
  child.api.nvim_buf_delete(init_buf_id, { force = true })
  clean_dummy_log()
end

local get_viz_extmarks = function(buf_id)
  local ns_id = child.api.nvim_get_namespaces().MiniDiffViz
  local full_extmarks = child.api.nvim_buf_get_extmarks(buf_id, ns_id, 0, -1, { details = true })
  local res = {}
  for _, e in ipairs(full_extmarks) do
    -- Do not test with dummy extmark (placed to ensure visible signcolumn)
    local is_dummy_extmark = e[2] == 0
      and e[3] == 0
      and e[4].sign_text == '  '
      and e[4].sign_hl_group == 'SignColumn'
      and e[4].cursorline_hl_group == 'CursorLineSign'
      and e[4].right_gravity == false
    if not is_dummy_extmark then
      table.insert(res, {
        line = e[2] + 1,
        sign_hl_group = e[4].sign_hl_group,
        sign_text = e[4].sign_text,
        number_hl_group = e[4].number_hl_group,
      })
    end
  end
  return res
end

local validate_viz_extmarks = function(buf_id, ref) eq(get_viz_extmarks(buf_id), ref) end

local get_overlay_extmarks = function(buf_id, from_line, to_line)
  local ns_id = child.api.nvim_get_namespaces().MiniDiffOverlay
  return child.api.nvim_buf_get_extmarks(buf_id, ns_id, { from_line - 1, 0 }, { to_line - 1, -1 }, { details = true })
end

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      child.set_size(10, 15)
      mock_notify()
      setup_with_dummy_source()
      clean_dummy_log()
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
  eq(child.lua_get('type(_G.MiniDiff)'), 'table')

  -- Autocommand group
  eq(child.fn.exists('#MiniDiff'), 1)

  -- Highlight groups
  child.cmd('hi clear')
  load_module()
  local is_010 = child.fn.has('nvim-0.10') == 1
  local validate_hl_group = function(name, pattern) expect.match(child.cmd_capture('hi ' .. name), pattern) end

  validate_hl_group('MiniDiffSignAdd', 'links to ' .. (is_010 and 'Added' or 'diffAdded'))
  validate_hl_group('MiniDiffSignChange', 'links to ' .. (is_010 and 'Changed' or 'diffChanged'))
  validate_hl_group('MiniDiffSignDelete', 'links to ' .. (is_010 and 'Removed' or 'diffRemoved'))
  validate_hl_group('MiniDiffOverAdd', 'links to DiffAdd')
  validate_hl_group('MiniDiffOverChange', 'links to DiffText')
  validate_hl_group('MiniDiffOverChangeBuf', 'links to MiniDiffOverChange')
  validate_hl_group('MiniDiffOverContext', 'links to DiffChange')
  eq(child.fn.hlexists('MiniFilesFile'), 1)
  validate_hl_group('MiniDiffOverDelete', 'links to DiffDelete')
end

T['setup()']['creates `config` field'] = function()
  load_module()

  eq(child.lua_get('type(_G.MiniDiff.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniDiff.config.' .. field), value) end

  expect_config('view.style', 'sign')
  expect_config('view.signs', { add = '▒', change = '▒', delete = '▒' })
  expect_config('view.priority', child.highlight.priorities.user - 1)
  expect_config('source', vim.NIL)
  expect_config('delay.text_change', 200)
  expect_config('mappings.apply', 'gh')
  expect_config('mappings.reset', 'gH')
  expect_config('mappings.textobject', 'gh')
  expect_config('mappings.goto_first', '[H')
  expect_config('mappings.goto_prev', '[h')
  expect_config('mappings.goto_next', ']h')
  expect_config('mappings.goto_last', ']H')
  expect_config('options.algorithm', 'histogram')
  expect_config('options.indent_heuristic', true)
  expect_config('options.linematch', 60)
  expect_config('options.wrap_goto', false)
end

T['setup()']["respects global 'number' option when setting default `view.style`"] = function()
  unload_module()
  child.go.number, child.wo.number = true, false
  load_module()
  eq(child.lua_get('MiniDiff.config.view.style'), 'number')
end

T['setup()']['respects `config` argument'] = function()
  load_module({ delay = { text_change = 20 } })
  eq(child.lua_get('MiniDiff.config.delay.text_change'), 20)
end

T['setup()']['validates `config` argument'] = function()
  local expect_config_error = function(config, name, target_type)
    expect.error(load_module, vim.pesc(name) .. '.*' .. vim.pesc(target_type), config)
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ view = 'a' }, 'view', 'table')
  expect_config_error({ view = { style = 1 } }, 'view.style', 'string')
  expect_config_error({ view = { signs = 'a' } }, 'view.signs', 'table')
  expect_config_error({ view = { signs = { add = 1 } } }, 'view.signs.add', 'string')
  expect_config_error({ view = { signs = { change = 1 } } }, 'view.signs.change', 'string')
  expect_config_error({ view = { signs = { delete = 1 } } }, 'view.signs.delete', 'string')
  expect_config_error({ view = { priority = 'a' } }, 'view.priority', 'number')

  expect_config_error({ source = 'a' }, 'source', 'table')

  expect_config_error({ delay = 'a' }, 'delay', 'table')
  expect_config_error({ delay = { text_change = 'a' } }, 'delay.text_change', 'number')

  expect_config_error({ mappings = 'a' }, 'mappings', 'table')
  expect_config_error({ mappings = { apply = 1 } }, 'mappings.apply', 'string')
  expect_config_error({ mappings = { reset = 1 } }, 'mappings.reset', 'string')
  expect_config_error({ mappings = { textobject = 1 } }, 'mappings.textobject', 'string')
  expect_config_error({ mappings = { goto_first = 1 } }, 'mappings.goto_first', 'string')
  expect_config_error({ mappings = { goto_prev = 1 } }, 'mappings.goto_prev', 'string')
  expect_config_error({ mappings = { goto_next = 1 } }, 'mappings.goto_next', 'string')
  expect_config_error({ mappings = { goto_last = 1 } }, 'mappings.goto_last', 'string')

  expect_config_error({ options = 'a' }, 'options', 'table')
  expect_config_error({ options = { algorithm = 1 } }, 'options.algorithm', 'string')
  expect_config_error({ options = { indent_heuristic = 'a' } }, 'options.indent_heuristic', 'boolean')
  expect_config_error({ options = { linematch = 'a' } }, 'options.linematch', 'number')
  expect_config_error({ options = { wrap_goto = 'a' } }, 'options.wrap_goto', 'boolean')
end

T['setup()']['ensures colors'] = function()
  child.cmd('colorscheme default')
  expect.match(child.cmd_capture('hi MiniDiffOverAdd'), 'links to DiffAdd')
end

T['setup()']['auto enables in all existing loaded buffers'] = function()
  unload_module()

  local buf_id_cur_normal = new_buf()
  set_buf(buf_id_cur_normal)
  local buf_id_other_normal = new_buf()

  local buf_id_bad_1 = new_scratch_buf()
  local buf_id_bad_2 = new_buf()
  child.api.nvim_buf_set_lines(buf_id_bad_2, 0, -1, false, { '\0' })

  local buf_id_bad_3 = new_buf()
  child.api.nvim_buf_delete(buf_id_bad_3, { unload = true })
  eq(child.api.nvim_buf_is_loaded(buf_id_bad_3), false)
  child.api.nvim_set_option_value('buflisted', true, { buf = buf_id_bad_3 })

  setup_with_dummy_source()

  -- Only normal valid loaded text buffers should be auto enabled
  eq(is_buf_enabled(buf_id_cur_normal), true)
  eq(is_buf_enabled(buf_id_other_normal), true)
  eq(is_buf_enabled(buf_id_bad_1), false)
  eq(is_buf_enabled(buf_id_bad_2), false)
  eq(is_buf_enabled(buf_id_bad_3), false)

  -- Should not force load unloaded buffers
  eq(child.api.nvim_buf_is_loaded(buf_id_bad_3), false)
end

T['setup()']['can not create mappings'] = function()
  child.api.nvim_del_keymap('n', 'gh')
  load_module({ mappings = { apply = '' } })
  eq(child.fn.maparg('gh', 'n'), '')
end

T['enable()'] = new_set({ hooks = { pre_case = setup_enabled_buffer } })

local enable = forward_lua('MiniDiff.enable')

T['enable()']['works in not normal buffer'] = function()
  local buf_id = new_scratch_buf()
  set_buf(buf_id)
  clean_dummy_log()
  enable(buf_id)
  validate_dummy_log({ { 'attach', { buf_id } } })
end

T['enable()']['works in not current buffer'] = function()
  local buf_id = new_buf()
  enable(buf_id)
  validate_dummy_log({ { 'attach', { buf_id } } })
  eq(is_buf_enabled(buf_id), true)
end

T['enable()']['normalizes input buffer'] = function()
  local buf_id = new_scratch_buf()
  set_buf(buf_id)
  clean_dummy_log()
  enable(0)
  eq(is_buf_enabled(buf_id), true)
end

T['enable()']['does not re-enable already enabled buffer'] = function()
  enable()
  validate_dummy_log({})
end

T['enable()']['makes sure buffer is loaded'] = function()
  -- Set up not loaded but existing buffer with lines
  local new_buf_id = child.api.nvim_create_buf(true, false)
  child.api.nvim_buf_set_lines(new_buf_id, 0, -1, false, { 'aaa', 'bbb' })
  child.api.nvim_buf_set_option(new_buf_id, 'modified', false)
  child.api.nvim_buf_delete(new_buf_id, { unload = true })
  eq(child.api.nvim_buf_get_lines(new_buf_id, 0, -1, false), {})

  -- Should also not trigger `*Enter` events
  child.cmd('au BufEnter,BufWinEnter * lua _G.n = (_G.n or 0) + 1')
  enable(new_buf_id)
  eq(child.fn.bufloaded(new_buf_id), 1)
  eq(child.lua_get('_G.n'), vim.NIL)
end

T['enable()']['makes buffer update cache on `BufWinEnter`'] = function()
  eq(get_buf_data().config.delay.text_change, dummy_text_change_delay)
  child.b.minidiff_config = { delay = { text_change = 200 } }
  child.api.nvim_exec_autocmds('BufWinEnter', { buffer = get_buf() })
  eq(get_buf_data().config.delay.text_change, 200)
end

T['enable()']['makes buffer disabled when deleted'] = function()
  local alt_buf_id = new_buf()
  enable(alt_buf_id)
  clean_dummy_log()

  local buf_id = get_buf()
  child.api.nvim_buf_delete(buf_id, { force = true })
  validate_dummy_log({ { 'detach', { buf_id } } })
end

T['enable()']['makes buffer reset on rename'] = function()
  local buf_id = get_buf()
  child.api.nvim_buf_set_name(0, 'hello')
  validate_dummy_log({ { 'detach', { buf_id } }, { 'attach', { buf_id } } })
end

T['enable()']['validates arguments'] = function()
  expect.error(function() enable({}) end, '`buf_id`.*valid buffer id')
end

T['enable()']['respects `vim.{g,b}.minidiff_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    local buf_id = new_buf()
    if var_type == 'b' then child.api.nvim_buf_set_var(buf_id, 'minidiff_disable', true) end
    if var_type == 'g' then child.api.nvim_set_var('minidiff_disable', true) end
    enable(buf_id)
    validate_dummy_log({})
    eq(is_buf_enabled(buf_id), false)
  end,
})

T['enable()']['respects `vim.b.minidiff_config`'] = function()
  local buf_id = new_buf()
  child.api.nvim_buf_set_var(buf_id, 'minidiff_config', { delay = { text_change = 200 } })
  enable(buf_id)
  eq(get_buf_data(buf_id).config.delay.text_change, 200)
end

T['disable()'] = new_set({ hooks = { pre_case = setup_enabled_buffer } })

local disable = forward_lua('MiniDiff.disable')

T['disable()']['works'] = function()
  local buf_id = get_buf()
  eq(is_buf_enabled(buf_id), true)
  set_lines({ 'aaa', 'bbb' })
  set_ref_text(0, { 'aaa' })
  eq(child.b.minidiff_summary == vim.NIL, false)
  eq(child.b.minidiff_summary_string == vim.NIL, false)

  disable(buf_id)
  eq(is_buf_enabled(buf_id), false)

  -- Should delete buffer autocommands
  eq(child.api.nvim_get_autocmds({ buffer = buf_id }), {})

  -- Should delete buffer-local variables
  eq(child.b.minidiff_summary == vim.NIL, true)
  eq(child.b.minidiff_summary_string == vim.NIL, true)

  -- Should detach source
  validate_dummy_log({ { 'detach', { buf_id } } })

  -- Should clear visualization
  child.expect_screenshot()
end

T['disable()']['works in not current buffer'] = function()
  local buf_id = new_buf()
  enable(buf_id)
  clean_dummy_log()
  set_lines({ 'aaa', 'bbb' })
  set_ref_text(0, { 'aaa' })

  disable(buf_id)
  eq(is_buf_enabled(buf_id), false)
  validate_dummy_log({ { 'detach', { buf_id } } })
end

T['disable()']['works in not enabled buffer'] = function()
  local buf_id = new_buf()
  eq(is_buf_enabled(buf_id), false)
  expect.no_error(function() disable(buf_id) end)
end

T['disable()']['normalizes input buffer'] = function()
  local buf_id = new_scratch_buf()
  set_buf(buf_id)

  enable(buf_id)
  eq(is_buf_enabled(buf_id), true)
  disable(0)
  eq(is_buf_enabled(buf_id), false)
end

T['disable()']['validates arguments'] = function()
  expect.error(function() disable('a') end, '`buf_id`.*valid buffer id')
end

T['toggle()'] = new_set({ hooks = { pre_case = setup_enabled_buffer } })

local toggle = forward_lua('MiniDiff.toggle')

T['toggle()']['works'] = function()
  child.lua([[
    _G.log = {}
    local cur_enable = MiniDiff.enable
    MiniDiff.enable = function(...)
      table.insert(_G.log, { 'enabled', { ... } })
      cur_enable(...)
    end
    local cur_disable = MiniDiff.disable
    MiniDiff.disable = function(...)
      cur_disable(...)
      table.insert(_G.log, { 'disabled', { ... } })
    end
  ]])

  local buf_id = get_buf()
  eq(is_buf_enabled(buf_id), true)
  toggle(buf_id)
  eq(is_buf_enabled(buf_id), false)
  toggle(buf_id)
  eq(is_buf_enabled(buf_id), true)

  eq(child.lua_get('_G.log'), { { 'disabled', { buf_id } }, { 'enabled', { buf_id } } })
end

T['toggle_overlay()'] = new_set({ hooks = { pre_case = setup_enabled_buffer } })

local toggle_overlay = forward_lua('MiniDiff.toggle_overlay')

T['toggle_overlay()']['works'] = function()
  local init_buf_id = get_buf()
  set_lines({ 'AAA', 'uuu', 'BBB', 'CcC', 'DDD', 'FFF' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC', 'DDD', 'EEE', 'FFF' })

  -- Should be disabled by default
  child.expect_screenshot()
  toggle_overlay(init_buf_id)
  child.expect_screenshot()

  -- Should work per buffer
  local buf_id = new_buf()
  set_buf(buf_id)
  set_lines({ 'AAA', 'uuu', 'BBB' })
  set_ref_text(0, { 'AAA', 'BBB' })

  child.expect_screenshot()
  toggle_overlay(buf_id)
  child.expect_screenshot()

  -- Should work in not current buffer
  toggle_overlay(init_buf_id)
  set_buf(init_buf_id)
  child.expect_screenshot()
end

T['toggle_overlay()']['validates arguments'] = function()
  expect.error(function() toggle_overlay('a') end, '`buf_id`.*valid buffer id')

  disable()
  expect.error(function() toggle_overlay(0) end, 'Buffer.*not enabled')
end

T['export()'] = new_set()

local export = forward_lua('MiniDiff.export')

T['export()']['works with "qf" format'] = function()
  edit(test_file_path)
  local buf_id_1 = get_buf()
  set_ref_text(buf_id_1, { 'aaa' })

  local buf_id_2 = new_buf()
  child.api.nvim_buf_set_lines(buf_id_2, 0, -1, false, { 'AAA', 'uuu', 'BBB', 'CcC', 'DDD', 'FFF' })
  set_ref_text(buf_id_2, { 'AAA', 'BBB', 'CCC', 'DDD', 'EEE', 'FFF' })

  --stylua: ignore
  local ref = {
    { bufnr = buf_id_1, lnum = 2, col = 1, end_lnum = 2, end_col = 4, type = 'A', text = 'Add',    filename = test_file_path },
    { bufnr = buf_id_2, lnum = 2, col = 1, end_lnum = 2, end_col = 4, type = 'A', text = 'Add',    filename = '' },
    { bufnr = buf_id_2, lnum = 4, col = 1, end_lnum = 4, end_col = 4, type = 'C', text = 'Change', filename = '' },
    { bufnr = buf_id_2, lnum = 5, col = 1, end_lnum = 5, end_col = 1, type = 'D', text = 'Delete', filename = '' },
  }
  eq(export('qf'), ref)
end

T['export()']['works with multiline hunks'] = function()
  local buf_id_1 = new_buf()
  child.api.nvim_buf_set_lines(buf_id_1, 0, -1, false, { 'AAA', 'uuu', 'vv', 'BBB', 'CcC', 'DdD', 'EEE', 'HHH' })
  set_ref_text(buf_id_1, { 'AAA', 'BBB', 'CCC', 'DDD', 'EEE', 'FFF', 'GGG', 'HHH' })
  --stylua: ignore
  local ref = {
    { bufnr = buf_id_1, lnum = 2, col = 1, end_lnum = 3, end_col = 3, type = 'A', text = 'Add',    filename = '' },
    { bufnr = buf_id_1, lnum = 5, col = 1, end_lnum = 6, end_col = 4, type = 'C', text = 'Change', filename = '' },
    { bufnr = buf_id_1, lnum = 7, col = 1, end_lnum = 7, end_col = 1, type = 'D', text = 'Delete', filename = '' },
  }
  eq(export('qf'), ref)
end

T['export()']['respects `opts.scope`'] = function()
  local buf_id_1 = new_buf()
  child.api.nvim_buf_set_lines(buf_id_1, 0, -1, false, { 'aaa', 'uuu' })
  set_ref_text(buf_id_1, { 'aaa' })
  local buf_id_2 = new_buf()
  child.api.nvim_buf_set_lines(buf_id_2, 0, -1, false, { 'aaa', 'uuu' })
  set_ref_text(buf_id_2, { 'aaa' })

  eq(export('qf', { scope = 'current' }), {})

  set_buf(buf_id_1)
  local ref_entry = { bufnr = 2, lnum = 2, col = 1, end_lnum = 2, end_col = 4, type = 'A', text = 'Add', filename = '' }
  eq(export('qf', { scope = 'current' }), { ref_entry })
end

T['export()']['validates arguments'] = function()
  expect.error(function() export('aaa') end, 'one of')
end

T['get_buf_data()'] = new_set({ hooks = { pre_case = setup_enabled_buffer } })

T['get_buf_data()']['works'] = function()
  set_lines({ 'aaa', 'bbb' })
  set_ref_text(0, { 'aaa' })

  child.lua('_G.buf_data = MiniDiff.get_buf_data()')

  -- Should have proper structure
  local fields = child.lua_get('vim.tbl_keys(_G.buf_data)')
  table.sort(fields)
  eq(fields, { 'config', 'hunks', 'overlay', 'ref_text', 'summary' })

  eq(child.lua_get('vim.deep_equal(MiniDiff.config, _G.buf_data.config)'), true)
  eq(child.lua_get('_G.buf_data.summary'), { source_name = 'dummy', add = 1, change = 0, delete = 0, n_ranges = 1 })
  eq(
    child.lua_get('_G.buf_data.hunks'),
    { { buf_start = 2, buf_count = 1, ref_start = 1, ref_count = 0, type = 'add' } }
  )
  eq(child.lua_get('_G.buf_data.ref_text'), 'aaa\n')

  eq(child.lua_get('_G.buf_data.overlay'), false)
  toggle_overlay()
  eq(child.lua_get('MiniDiff.get_buf_data().overlay'), true)
end

T['get_buf_data()']['works with not set reference text'] = function()
  local buf_data = get_buf_data()
  eq(buf_data.hunks, {})
  eq(buf_data.summary, {})
  eq(buf_data.ref_text, nil)
end

T['get_buf_data()']['works on not enabled buffer'] = function()
  local out = child.lua([[
    local buf_id = vim.api.nvim_create_buf(true, false)
    return MiniDiff.get_buf_data(buf_id) == nil
  ]])
  eq(out, true)
end

T['get_buf_data()']['validates arguments'] = function()
  expect.error(function() get_buf_data('a') end, '`buf_id`.*valid buffer id')
end

T['get_buf_data()']['returns copy of underlying data'] = function()
  local out = child.lua([[
    local buf_data = MiniDiff.get_buf_data()
    buf_data.hunks = 'aaa'
    return MiniDiff.get_buf_data().hunks ~= 'aaa'
  ]])
  eq(out, true)
end

T['get_buf_data()']['correctly computes summary numbers'] = function()
  child.lua('MiniDiff.config.options.linematch = 0')
  local buf_id = new_buf()
  set_buf(buf_id)
  enable(buf_id)
  eq(get_buf_data(buf_id).config.options.linematch, 0)

  local validate = function(ref_summary) eq(get_buf_data(buf_id).summary, ref_summary) end

  -- Delete lines
  set_lines({ 'BBB', 'DDD' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC', 'DDD' })
  -- NOTE: Number of ranges is 1 because in buffer two delete hunks start on
  -- consecutive lines
  validate({ source_name = 'dummy', add = 0, change = 0, delete = 2, n_ranges = 1 })

  -- Add lines
  set_lines({ 'AAA', 'uuu', 'BBB', 'vvv' })
  set_ref_text(0, { 'AAA', 'BBB' })
  validate({ source_name = 'dummy', add = 2, change = 0, delete = 0, n_ranges = 2 })

  -- Changed lines are computed per hunk as minimum number of added and deleted
  -- lines. Excess is counted as corresponding lines (added/deleted)
  set_lines({ 'aaa', 'CCC', 'ddd', 'eee', 'uuu' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC', 'DDD', 'EEE' })
  local ref_hunks = {
    { buf_start = 1, buf_count = 1, ref_start = 1, ref_count = 2, type = 'change' },
    { buf_start = 3, buf_count = 3, ref_start = 4, ref_count = 2, type = 'change' },
  }
  eq(get_buf_hunks(buf_id), ref_hunks)
  validate({ source_name = 'dummy', add = 1, change = 3, delete = 1, n_ranges = 2 })
end

T['get_buf_data()']['uses number of contiguous ranges in summary'] = function()
  set_lines({ 'AAA', 'uuu', 'BbB', 'DDD', 'www', 'EEE' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC', 'DDD', 'EEE' })
  local buf_data = get_buf_data()
  eq(buf_data.hunks, {
    { buf_start = 2, buf_count = 1, ref_start = 1, ref_count = 0, type = 'add' },
    { buf_start = 3, buf_count = 1, ref_start = 2, ref_count = 1, type = 'change' },
    { buf_start = 3, buf_count = 0, ref_start = 3, ref_count = 1, type = 'delete' },
    { buf_start = 5, buf_count = 1, ref_start = 4, ref_count = 0, type = 'add' },
  })

  eq(buf_data.summary.n_ranges, 2)
end

T['set_ref_text()'] = new_set({ hooks = { pre_case = setup_enabled_buffer } })

T['set_ref_text()']['works'] = function()
  set_lines({ 'aaa' })

  local validate = function(input_ref_text, ref_ref_text, ref_hunks)
    set_ref_text(0, input_ref_text)
    eq(get_buf_data().ref_text, ref_ref_text)
    eq(get_buf_data().hunks, ref_hunks)
  end
  local ref_hunks = { { buf_start = 1, buf_count = 0, ref_start = 2, ref_count = 1, type = 'delete' } }

  -- Should work with table input (as an array of lines)
  validate({ 'aaa', 'bbb' }, 'aaa\nbbb\n', ref_hunks)

  -- Should work with empty table to remove reference text
  validate({}, nil, {})

  -- Should work with string input
  validate('aaa\n\n', 'aaa\n\n', ref_hunks)

  -- Should append newline if not present
  validate('aaa\nccc', 'aaa\nccc\n', ref_hunks)
  validate('aaa\nccc\n', 'aaa\nccc\n', ref_hunks)
end

T['set_ref_text()']['removing reference text removes visualization'] = function()
  set_lines({ 'aaa', 'bbb' })
  set_ref_text(0, { 'aaa' })
  child.expect_screenshot()
  set_ref_text(0, {})
  child.expect_screenshot()
end

T['set_ref_text()']['enables not enabled buffer'] = function()
  local buf_id = new_buf()
  set_ref_text(buf_id, { 'aaa' })
  eq(is_buf_enabled(buf_id), true)

  -- Give informative error if could not enable
  child.lua('MiniDiff.config.source = { attach = function() return false end }')
  local new_buf_id = new_buf()
  expect.error(function() set_ref_text(new_buf_id, { 'bbb' }) end, 'not enabled')
end

T['set_ref_text()']['immediately updates diff data and visualization'] = function()
  set_lines({ 'aaa', 'bbb' })
  set_ref_text(0, { 'aaa' })
  local ref_hunks = { { buf_start = 2, buf_count = 1, ref_start = 1, ref_count = 0, type = 'add' } }
  eq(get_buf_hunks(0), ref_hunks)
  child.expect_screenshot()
end

T['set_ref_text()']['validates arguments'] = function()
  expect.error(function() set_ref_text('a') end, '`buf_id`.*valid buffer id')
end

T['gen_source'] = new_set()

T['gen_source']['git()'] = new_set({
  hooks = {
    pre_case = function()
      -- Although it is the default source, "dummy" source is set in earlier hook
      child.lua('MiniDiff.config.source = MiniDiff.gen_source.git()')
      local init_buf_id = get_buf()
      set_buf(new_buf())
      child.api.nvim_buf_delete(init_buf_id, { force = true })

      -- Mock
      mock_spawn()

      -- Set some data in child process
      child.lua('_G.git_dir = ' .. vim.inspect(git_git_dir))
    end,
    post_case = function()
      -- Ensure no changes in reference git repo
      local index_path = git_git_dir .. '/index'
      vim.fn.delete(index_path .. '.lock')
      if vim.fn.filereadable(index_path) == 0 then vim.fn.writefile({}, index_path) end
    end,
  },
})

T['gen_source']['git()']['works'] = function()
  child.lua([[
    _G.stdio_queue = {
      { { 'out', _G.git_dir } },         -- Get path to repo's Git dir
      { { 'out', 'Line 1\nLine 2\n' } }, -- Get reference text
    }
  ]])

  edit(git_file_path)
  eq(is_buf_enabled(0), true)

  -- Should set reference text immediately
  eq(get_buf_data(0).ref_text, 'Line 1\nLine 2\n')

  local ref_git_spawn_log = {
    { args = { 'rev-parse', '--path-format=absolute', '--git-dir' }, cwd = git_dir_path },
    { args = { 'show', ':0:./' .. git_file_basename }, cwd = git_dir_path },
  }
  validate_git_spawn_log(ref_git_spawn_log)

  eq(is_buf_enabled(0), true)
  eq(get_buf_data(0).ref_text, 'Line 1\nLine 2\n')

  -- All processes and streams should be properly closed
  --stylua: ignore
  local ref_process_log = {
    'Stream out for process 1 was closed.', 'Process 1 was closed.',
    'Stream out for process 2 was closed.', 'Process 2 was closed.',
  }
  eq(get_process_log(), ref_process_log)
end

T['gen_source']['git()']['can apply hunks'] = function()
  child.lua([[
    local ref_text = table.concat({ 'Line -1', 'Line 0', 'Line 1', 'Line 22', 'Line 33', 'Line 4' }, '\n')
    _G.stdio_queue = {
      { { 'out', _G.git_dir } },              -- Get path to repo's Git dir
      { { 'out', ref_text } },                -- Get reference text
      { { 'out', '100644 lf file-in-git' } }, -- Get path data for the patch
      { { 'in' } },                           -- Apply patch
    }
  ]])

  edit(git_file_path)
  eq(is_buf_enabled(0), true)
  eq(get_buf_data(0).ref_text, 'Line -1\nLine 0\nLine 1\nLine 22\nLine 33\nLine 4\n')

  -- Make change
  type_keys('G', 'cc', 'world')
  sleep(small_time)

  local ref_hunks = {
    { buf_start = 0, buf_count = 0, ref_start = 1, ref_count = 2, type = 'delete' },
    { buf_start = 2, buf_count = 2, ref_start = 4, ref_count = 2, type = 'change' },
    { buf_start = 5, buf_count = 1, ref_start = 6, ref_count = 0, type = 'add' },
  }
  eq(get_buf_hunks(0), ref_hunks)

  child.lua([[MiniDiff.do_hunks(0, 'apply')]])

  --stylua: ignore
  local ref_git_spawn_log = {
    { args = { 'rev-parse', '--path-format=absolute', '--git-dir' }, cwd = git_dir_path },
    { args = { 'show', ':0:./' .. git_file_basename }, cwd = git_dir_path },
    {
      args = { 'ls-files', '-z', '--full-name', '--format=%(objectmode) %(eolinfo:index) %(path)', '--', git_file_basename },
      cwd = git_dir_path,
    },
    { args = { 'apply', '--whitespace=nowarn', '--cached', '--unidiff-zero', '-' }, cwd = git_dir_path },
  }
  validate_git_spawn_log(ref_git_spawn_log)

  -- All processes and streams should be properly closed
  --stylua: ignore
  local ref_process_log = {
    'Stream out for process 1 was closed.', 'Process 1 was closed.',
    'Stream out for process 2 was closed.', 'Process 2 was closed.',
    'Stream out for process 3 was closed.', 'Process 3 was closed.',
    -- Proper patch should be written in 'stdin'
    'Stream in for process 4 wrote: diff --git a/file-in-git b/file-in-git',
    'Stream in for process 4 wrote: \n',
    'Stream in for process 4 wrote: index 000000..000000 100644',
    'Stream in for process 4 wrote: \n',
    'Stream in for process 4 wrote: --- a/file-in-git',
    'Stream in for process 4 wrote: \n',
    'Stream in for process 4 wrote: +++ b/file-in-git',
    'Stream in for process 4 wrote: \n',
    'Stream in for process 4 wrote: @@ -1,2 +1,0 @@',
    'Stream in for process 4 wrote: \n',
    'Stream in for process 4 wrote: -Line -1',
    'Stream in for process 4 wrote: \n',
    'Stream in for process 4 wrote: -Line 0',
    'Stream in for process 4 wrote: \n',
    'Stream in for process 4 wrote: @@ -4,2 +2,2 @@',
    'Stream in for process 4 wrote: \n',
    'Stream in for process 4 wrote: -Line 22',
    'Stream in for process 4 wrote: \n',
    'Stream in for process 4 wrote: -Line 33',
    'Stream in for process 4 wrote: \n',
    'Stream in for process 4 wrote: +Line 2',
    'Stream in for process 4 wrote: \n',
    'Stream in for process 4 wrote: +Line 3',
    'Stream in for process 4 wrote: \n',
    'Stream in for process 4 wrote: @@ -7,0 +5,1 @@',
    'Stream in for process 4 wrote: \n',
    'Stream in for process 4 wrote: +world',
    'Stream in for process 4 wrote: \n',
    'Stream in for process 4 was shut down.', 'Process 4 was closed.',
  }
  eq(get_process_log(), ref_process_log)
end

T['gen_source']['git()']['handles "crlf" line endings in index'] = function()
  -- Computing reference text
  child.lua([[
    _G.stdio_queue = {
      { { 'out', _G.git_dir } },                   -- Get path to repo's Git dir
      { { 'out', 'Line 1\r\nLINE 2\r\nLine 3' } }, -- Get reference text
      { { 'out', '100644 crlf file-in-git' } },    -- Get path data for the patch
      { { 'in' } },                                -- Apply patch
    }
  ]])

  edit(git_file_path)
  eq(is_buf_enabled(0), true)

  -- - Should set reference text with only '\n' representing end of line
  eq(get_buf_data(0).ref_text, 'Line 1\nLINE 2\nLine 3\n')

  -- Applying hunks
  child.lua([[MiniDiff.do_hunks(0, 'apply')]])
  --stylua: ignore
  local ref_process_log = {
    'Stream out for process 1 was closed.', 'Process 1 was closed.',
    'Stream out for process 2 was closed.', 'Process 2 was closed.',
    'Stream out for process 3 was closed.', 'Process 3 was closed.',
    'Stream in for process 4 wrote: diff --git a/file-in-git b/file-in-git',
    'Stream in for process 4 wrote: \n',
    'Stream in for process 4 wrote: index 000000..000000 100644',
    'Stream in for process 4 wrote: \n',
    'Stream in for process 4 wrote: --- a/file-in-git',
    'Stream in for process 4 wrote: \n',
    'Stream in for process 4 wrote: +++ b/file-in-git',
    'Stream in for process 4 wrote: \n',
    'Stream in for process 4 wrote: @@ -2,1 +2,1 @@',
    'Stream in for process 4 wrote: \n',
    -- Should append "\r" at end of line if CRLF is used in index
    'Stream in for process 4 wrote: -LINE 2\r',
    'Stream in for process 4 wrote: \n',
    'Stream in for process 4 wrote: +Line 2\r',
    'Stream in for process 4 wrote: \n',
    'Stream in for process 4 wrote: @@ -4,0 +4,2 @@',
    'Stream in for process 4 wrote: \n',
    'Stream in for process 4 wrote: +Line 4\r',
    'Stream in for process 4 wrote: \n',
    'Stream in for process 4 wrote: +Line 5\r',
    'Stream in for process 4 wrote: \n',
    'Stream in for process 4 was shut down.', 'Process 4 was closed.',
  }
  eq(get_process_log(), ref_process_log)
end

T['gen_source']['git()']['returns correct structure'] = function()
  eq(
    child.lua_get('vim.tbl_map(type, MiniDiff.gen_source.git())'),
    { apply_hunks = 'function', attach = 'function', detach = 'function', name = 'string' }
  )
  eq(child.lua_get('MiniDiff.gen_source.git().name'), 'git')
end

T['gen_source']['git()']["reacts to change in 'index' Git file"] = function()
  helpers.skip_if_slow()

  child.lua([[
    _G.stdio_queue = {
      { { 'out', _G.git_dir } },          -- Get path to repo's Git dir
      { { 'out', 'Line 1\nLine 2\n' } },  -- Get reference text
      { { 'out', 'Line 1\nLine 22\n' } }, -- Get reference text after 'index' update
    }
  ]])

  edit(git_file_path)
  eq(is_buf_enabled(0), true)
  eq(get_buf_data(0).ref_text, 'Line 1\nLine 2\n')

  -- Emulate change in 'index' as it is done by Git
  mock_count_set_ref_text()

  -- Use slightly bigger yet constrained delay for more robust tests
  local small_time_bigger = math.min(2 * small_time, 0.9 * default_watch_debounce_delay)

  -- Should react to change in 'index' file by reasking reference text
  -- These reactions should be debounced
  mock_change_git_index()
  sleep(default_watch_debounce_delay - small_time_bigger)
  -- - No changes as less than 50 ms has passed
  eq(get_buf_data(0).ref_text, 'Line 1\nLine 2\n')
  eq(child.lua_get('_G.n_set_ref_text_calls'), 0)

  mock_change_git_index()
  sleep(default_watch_debounce_delay - small_time_bigger)
  eq(child.lua_get('_G.n_set_ref_text_calls'), 0)
  sleep(small_time_bigger + small_time)
  eq(get_buf_data(0).ref_text, 'Line 1\nLine 22\n')
  eq(child.lua_get('_G.n_set_ref_text_calls'), 1)

  -- Should react __only__ to changes in 'index' file
  child.fn.writefile({}, git_git_dir .. '/index.lock')
  sleep(default_watch_debounce_delay + small_time)
  eq(child.lua_get('_G.n_set_ref_text_calls'), 1)

  -- Should stop reacting after detaching
  disable()
  mock_change_git_index()
  sleep(2 * small_time)
  eq(child.lua_get('_G.n_set_ref_text_calls'), 1)

  -- Should make proper process spawns
  local ref_git_spawn_log = {
    { args = { 'rev-parse', '--path-format=absolute', '--git-dir' }, cwd = git_dir_path },
    { args = { 'show', ':0:./' .. git_file_basename }, cwd = git_dir_path },
    { args = { 'show', ':0:./' .. git_file_basename }, cwd = git_dir_path },
  }
  validate_git_spawn_log(ref_git_spawn_log)
end

T['gen_source']['git()']['attaches only in readable file buffers'] = function()
  edit('not-real-file')
  eq(is_buf_enabled(0), false)

  set_buf(new_scratch_buf())
  eq(is_buf_enabled(0), false)

  child.lua('vim.uv.fs_realpath = function() return nil end')
  edit(test_file_path)
  eq(is_buf_enabled(0), false)

  -- No spawns should be needed for these early checks
  validate_git_spawn_log({})
end

T['gen_source']['git()']['works with errors during attach'] = function()
  -- Like if file is not in Git repo or there is no `git` executable
  child.lua([[
    _G.stdio_queue = {
      { {} }, -- Get path to repo's Git dir
    }
    _G.process_mock_data = { { exit_code = 1 } }
  ]])

  edit(git_file_path)
  eq(is_buf_enabled(0), false)
end

T['gen_source']['git()']['works with wiped out target buffer'] = function()
  child.lua([[_G.stdio_queue = { { { 'out', _G.git_dir } } }]])

  child.lua('_G.path = ' .. vim.inspect(git_file_path))
  local buf_id = child.lua([[
    vim.cmd('edit ' .. vim.fn.fnameescape(_G.path))
    local buf_id = vim.api.nvim_get_current_buf()
    -- Should not result in an error
    vim.schedule(function() vim.api.nvim_buf_delete(buf_id, { force = true }) end)
    return buf_id
  ]])

  eq(is_buf_enabled(0), false)
  eq(child.api.nvim_buf_is_valid(buf_id), false)
  eq(child.cmd_capture('messages'), '')

  local ref_git_spawn_log = {
    { args = { 'rev-parse', '--path-format=absolute', '--git-dir' }, cwd = git_dir_path },
  }
  validate_git_spawn_log(ref_git_spawn_log)
end

T['gen_source']['git()']['works with errors during getting reference text'] = function()
  -- Should attach but reset ref text (to react if it *gets* in index)
  child.lua([[
    _G.stdio_queue = {
      { { 'out', _G.git_dir } }, -- Get path to repo's Git dir
      { {} },                    -- Get reference text
    }
    _G.process_mock_data = { [2] = { exit_code = 1 } }
  ]])

  edit(git_file_path)
  eq(is_buf_enabled(0), true)
  eq(get_buf_data(0).ref_text, nil)

  local ref_git_spawn_log = {
    { args = { 'rev-parse', '--path-format=absolute', '--git-dir' }, cwd = git_dir_path },
    { args = { 'show', ':0:./' .. git_file_basename }, cwd = git_dir_path },
  }
  validate_git_spawn_log(ref_git_spawn_log)
end

T['gen_source']['git()']['reacts to file rename'] = function()
  -- Should disable/enable file because it might have changed Git repo
  child.lua([[
    _G.stdio_queue = {
      { { 'out', _G.git_dir } },         -- Get path to repo's Git dir
      { { 'out', 'Line 1\nLine 2\n' } }, -- Get reference text
      { { 'out', vim.fn.getcwd() } },    -- Get path to repo's Git dir after rename
      { { 'out', 'Hello\nWorld\n' } },   -- Get reference text after rename
    }
  ]])

  edit(git_file_path)
  eq(is_buf_enabled(0), true)
  eq(get_buf_data(0).ref_text, 'Line 1\nLine 2\n')

  child.api.nvim_buf_set_name(0, test_file_path)

  local ref_git_spawn_log = {
    { args = { 'rev-parse', '--path-format=absolute', '--git-dir' }, cwd = git_dir_path },
    { args = { 'show', ':0:./' .. 'file-in-git' }, cwd = git_dir_path },
    { args = { 'rev-parse', '--path-format=absolute', '--git-dir' }, cwd = test_dir_absolute },
    { args = { 'show', ':0:./' .. 'file' }, cwd = test_dir_absolute },
  }
  validate_git_spawn_log(ref_git_spawn_log)

  eq(is_buf_enabled(0), true)
  eq(get_buf_data(0).ref_text, 'Hello\nWorld\n')
end

T['gen_source']['git()']['should try attaching same buffer exactly once'] = function()
  -- If buffer was not attached on `BufEnter` after it tried, then it should
  -- stop trying. This is an example of when buffer's file is not in Git repo.
  -- Should disable/enable file because it might have changed Git repo
  child.lua([[
    _G.stdio_queue = {
      { {} }, -- Get path to repo's Git dir
    }
    _G.process_mock_data = { { exit_code = 1 } }
  ]])

  edit(test_file_path)
  local init_buf = get_buf()
  eq(is_buf_enabled(0), false)

  -- Simulate `BufEnter`
  set_buf(new_scratch_buf())
  set_buf(init_buf)
  eq(is_buf_enabled(0), false)

  -- Spawn should be done only once (on the first try)
  local ref_git_spawn_log = {
    { args = { 'rev-parse', '--path-format=absolute', '--git-dir' }, cwd = test_dir_absolute },
  }
  validate_git_spawn_log(ref_git_spawn_log)
end

T['gen_source']['none()'] = new_set()

T['gen_source']['none()']['works'] = function()
  child.lua('MiniDiff.config.source = MiniDiff.gen_source.none()')

  -- Should return proper structure
  eq(child.lua_get('vim.tbl_map(type, MiniDiff.config.source)'), { attach = 'function', name = 'string' })
  eq(child.lua_get('MiniDiff.config.source.name'), 'none')

  -- Should allow enabling buffer but not set any reference text
  local buf_id = new_buf()
  enable(buf_id)
  eq(is_buf_enabled(buf_id), true)
  eq(get_buf_data(buf_id).ref_text, nil)

  -- Should allow setting reference text manually
  set_ref_text(buf_id, { 'aaa' })
  eq(get_buf_data(buf_id).ref_text, 'aaa\n')
end

T['gen_source']['save()'] = new_set()

T['gen_source']['save()']['works'] = function()
  child.lua('MiniDiff.config.source = MiniDiff.gen_source.save()')
  edit(test_file_path)
  local init_lines = get_lines()
  MiniTest.finally(function() child.fn.writefile(init_lines, test_file_path) end)

  local validate_ref_text = function(ref) eq(get_buf_data(0).ref_text, ref) end

  -- Should return proper structure
  eq(
    child.lua_get('vim.tbl_map(type, MiniDiff.config.source)'),
    { attach = 'function', detach = 'function', name = 'string' }
  )
  eq(child.lua_get('MiniDiff.config.source.name'), 'save')

  -- Should update reference text on save
  validate_ref_text('aaa\nuuu\n')
  type_keys('G', 'o', 'vvv', '<Esc>')
  sleep(small_time + small_time)
  validate_ref_text('aaa\nuuu\n')
  child.cmd('write')
  validate_ref_text('aaa\nuuu\nvvv\n')

  -- Should work with trailing empty/blank lines
  type_keys('G', 'o', '<Esc>')
  child.cmd('write')
  validate_ref_text('aaa\nuuu\nvvv\n\n')

  type_keys('G', 'o', ' ', '<Esc>')
  child.cmd('write')
  validate_ref_text('aaa\nuuu\nvvv\n\n \n')

  -- Should still work after `:edit`
  child.cmd('edit')
  validate_ref_text('aaa\nuuu\nvvv\n\n \n')

  -- Should update reference text when file change outside buffer
  child.fn.writefile({ 'bbb', 'xxx' }, test_file_path)
  local cur_changedtick = child.api.nvim_buf_get_changedtick(0)
  child.cmd('silent! checktime')
  -- - Wait for `:checktime` itself to process
  for _ = 1, 100 do
    if child.api.nvim_buf_get_changedtick(0) ~= cur_changedtick then break end
    vim.uv.sleep(small_time)
  end
  if child.api.nvim_buf_get_changedtick(0) == cur_changedtick then
    MiniTest.skip('Could not wait for `silent! checktime` to take effect')
  end
  validate_ref_text('bbb\nxxx\n')

  -- Should clean up buffer autocommands on detach
  local has_save_autocommands = function()
    return #child.api.nvim_get_autocmds({ event = 'BufWritePost', buffer = get_buf() }) > 0
  end
  eq(has_save_autocommands(), true)
  disable()
  eq(has_save_autocommands(), false)
end

T['gen_source']['save()']['works with BOM bytes'] = function()
  child.lua('MiniDiff.config.source = MiniDiff.gen_source.save()')
  local path = test_dir_absolute .. '/file-bom'
  edit(path)

  local init_content = child.fn.readblob(path, 'b')
  MiniTest.finally(function()
    local file = io.open(path, 'w')
    assert(file)
    file:write(init_content)
    file:close()
  end)

  local validate_ref_text = function(ref) eq(get_buf_data(0).ref_text, ref) end

  eq(child.bo.fileencoding, 'utf-8')
  local utf8_bom_bytes = string.char(0xef, 0xbb, 0xbf)
  validate_ref_text(utf8_bom_bytes .. 'bbb\nvvv\n')

  type_keys('G', 'o', 'hello', '<Esc>')
  child.cmd('write')
  validate_ref_text(utf8_bom_bytes .. 'bbb\nvvv\nhello\n')
end

T['do_hunks()'] = new_set()

local do_hunks = forward_lua('MiniDiff.do_hunks')

T['do_hunks()']['works'] = function()
  set_lines({ 'aaa', 'BBB' })
  child.bo.modified = false
  set_ref_text(0, { 'AAA', 'BBB', 'CCC' })

  -- Apply
  do_hunks(0, 'apply')
  -- - By default should do action on all lines
  local ref_hunks = {
    { buf_start = 1, buf_count = 1, ref_start = 1, ref_count = 1, type = 'change' },
    { buf_start = 2, buf_count = 0, ref_start = 3, ref_count = 1, type = 'delete' },
  }
  validate_dummy_log({ { 'apply_hunks', { get_buf(), ref_hunks } } })

  -- Yank
  do_hunks(0, 'yank')
  eq(child.fn.getreg('"'), 'AAA\nCCC\n')

  -- Reset
  do_hunks(0, 'reset')
  eq(get_lines(), { 'AAA', 'BBB', 'CCC' })
  eq(child.bo.modified, true)
end

T['do_hunks()']['works with no hunks'] = function()
  set_lines({ 'aaa' })
  set_ref_text(0, { 'aaa' })

  -- Apply
  do_hunks(0, 'apply')
  validate_dummy_log({})
  validate_notifications({ { '(mini.diff) No hunks to apply', 'INFO' } })
  clear_notify_log()

  -- Yank
  do_hunks(0, 'yank')
  eq(child.fn.getreg('"'), '')
  validate_notifications({ { '(mini.diff) No hunks to yank', 'INFO' } })
  clear_notify_log()

  -- Reset
  do_hunks(0, 'reset')
  eq(get_lines(), { 'aaa' })
  validate_notifications({ { '(mini.diff) No hunks to reset', 'INFO' } })
  clear_notify_log()
end

T['do_hunks()']['works with "add" hunks'] = function()
  local ref_hunks

  set_lines({ 'uuu', 'aaa', 'vvv', 'ccc', 'www', 'xxx' })
  set_ref_text(0, { 'aaa', 'ccc' })

  -- Apply
  do_hunks(0, 'apply')
  ref_hunks = {
    { buf_start = 1, buf_count = 1, ref_start = 0, ref_count = 0, type = 'add' },
    { buf_start = 3, buf_count = 1, ref_start = 1, ref_count = 0, type = 'add' },
    { buf_start = 5, buf_count = 2, ref_start = 2, ref_count = 0, type = 'add' },
  }
  validate_dummy_log({ { 'apply_hunks', { get_buf(), ref_hunks } } })

  -- Yank
  do_hunks(0, 'yank')
  -- - No reference lines to yank
  eq(child.fn.getreg('"'), '')

  -- Reset
  do_hunks(0, 'reset')
  eq(get_lines(), { 'aaa', 'ccc' })
end

T['do_hunks()']['works with "change" hunks'] = function()
  set_lines({ 'aaa', 'BBB', 'ccc', 'DDD', 'eee', 'fff' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC', 'DDD', 'EEE', 'FFF' })

  -- Apply
  do_hunks(0, 'apply')
  local ref_hunks = {
    { buf_start = 1, buf_count = 1, ref_start = 1, ref_count = 1, type = 'change' },
    { buf_start = 3, buf_count = 1, ref_start = 3, ref_count = 1, type = 'change' },
    { buf_start = 5, buf_count = 2, ref_start = 5, ref_count = 2, type = 'change' },
  }
  validate_dummy_log({ { 'apply_hunks', { get_buf(), ref_hunks } } })

  -- Yank
  do_hunks(0, 'yank')
  eq(child.fn.getreg('"'), 'AAA\nCCC\nEEE\nFFF\n')

  -- Reset
  do_hunks(0, 'reset')
  eq(get_lines(), { 'AAA', 'BBB', 'CCC', 'DDD', 'EEE', 'FFF' })
end

T['do_hunks()']['works with "delete" hunks'] = function()
  set_lines({ 'bbb', 'ddd' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc', 'ddd', 'eee', 'fff' })

  -- Apply
  do_hunks(0, 'apply')
  local ref_hunks = {
    { buf_start = 0, buf_count = 0, ref_start = 1, ref_count = 1, type = 'delete' },
    { buf_start = 1, buf_count = 0, ref_start = 3, ref_count = 1, type = 'delete' },
    { buf_start = 2, buf_count = 0, ref_start = 5, ref_count = 2, type = 'delete' },
  }
  validate_dummy_log({ { 'apply_hunks', { get_buf(), ref_hunks } } })

  -- Yank
  do_hunks(0, 'yank')
  eq(child.fn.getreg('"'), 'aaa\nccc\neee\nfff\n')

  -- Reset
  do_hunks(0, 'reset')
  eq(get_lines(), { 'aaa', 'bbb', 'ccc', 'ddd', 'eee', 'fff' })
end

T['do_hunks()']['works with "delete" hunks on edges as target'] = function()
  local ref_hunks

  -- First line
  set_lines({ 'bbb' })
  set_ref_text(0, { 'aaa', 'bbb' })

  do_hunks(0, 'apply', { line_start = 1, line_end = 1 })
  ref_hunks = { { buf_start = 0, buf_count = 0, ref_start = 1, ref_count = 1, type = 'delete' } }
  validate_dummy_log({ { 'apply_hunks', { get_buf(), ref_hunks } } })
  clean_dummy_log()

  do_hunks(0, 'yank')
  eq(child.fn.getreg('"'), 'aaa\n')

  do_hunks(0, 'reset', { line_start = 1, line_end = 1 })
  eq(get_lines(), { 'aaa', 'bbb' })

  -- Last line
  set_lines({ 'aaa' })
  set_ref_text(0, { 'aaa', 'bbb' })

  do_hunks(0, 'apply', { line_start = 2, line_end = 2 })
  ref_hunks = { { buf_start = 1, buf_count = 0, ref_start = 2, ref_count = 1, type = 'delete' } }
  validate_dummy_log({ { 'apply_hunks', { get_buf(), ref_hunks } } })
  clean_dummy_log()

  do_hunks(0, 'yank')
  eq(child.fn.getreg('"'), 'bbb\n')

  do_hunks(0, 'reset', { line_start = 2, line_end = 2 })
  eq(get_lines(), { 'aaa', 'bbb' })
end

T['do_hunks()']['works when "change" and "delete" hunks overlap'] = function()
  set_lines({ 'AAA', 'CcC', 'EeE', 'FFF' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC', 'DDD', 'EEE', 'FFF' })

  -- Apply
  do_hunks(0, 'apply')
  local ref_hunks = {
    { buf_start = 1, buf_count = 0, ref_start = 2, ref_count = 1, type = 'delete' },
    { buf_start = 2, buf_count = 1, ref_start = 3, ref_count = 1, type = 'change' },
    { buf_start = 2, buf_count = 0, ref_start = 4, ref_count = 1, type = 'delete' },
    { buf_start = 3, buf_count = 1, ref_start = 5, ref_count = 1, type = 'change' },
  }
  validate_dummy_log({ { 'apply_hunks', { get_buf(), ref_hunks } } })
  clean_dummy_log()

  -- Yank
  do_hunks(0, 'yank')
  eq(child.fn.getreg('"'), 'BBB\nCCC\nDDD\nEEE\n')

  -- Reset
  do_hunks(0, 'reset')
  eq(get_lines(), { 'AAA', 'BBB', 'CCC', 'DDD', 'EEE', 'FFF' })
end

T['do_hunks()']['respects `opts.line_start`'] = function()
  set_lines({ 'aaa', 'BBB' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC' })

  -- Apply
  do_hunks(0, 'apply', { line_start = 2 })
  local ref_hunks = { { buf_start = 2, buf_count = 0, ref_start = 3, ref_count = 1, type = 'delete' } }
  validate_dummy_log({ { 'apply_hunks', { get_buf(), ref_hunks } } })

  -- Yank
  do_hunks(0, 'yank', { line_start = 2 })
  eq(child.fn.getreg('"'), 'CCC\n')

  -- Reset
  do_hunks(0, 'reset', { line_start = 2 })
  eq(get_lines(), { 'aaa', 'BBB', 'CCC' })
end

T['do_hunks()']['respects `opts.line_end`'] = function()
  set_lines({ 'aaa', 'BBB' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC' })

  -- Apply
  do_hunks(0, 'apply', { line_end = 1 })
  local ref_hunks = { { buf_start = 1, buf_count = 1, ref_start = 1, ref_count = 1, type = 'change' } }
  validate_dummy_log({ { 'apply_hunks', { get_buf(), ref_hunks } } })

  -- Yank
  do_hunks(0, 'yank', { line_end = 1 })
  eq(child.fn.getreg('"'), 'AAA\n')

  -- Reset
  do_hunks(0, 'reset', { line_end = 1 })
  eq(get_lines(), { 'AAA', 'BBB' })
end

T['do_hunks()']['respects `opts.register`'] = function()
  set_lines({ 'aaa', 'BBB' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC' })
  do_hunks(0, 'yank', { register = 'a' })
  eq(child.fn.getreg('a'), 'AAA\nCCC\n')
  eq(child.fn.getreg('"'), '')
end

T['do_hunks()']['allows negative target lines'] = function()
  set_lines({ 'aaa', 'BBB' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC' })

  -- Apply
  do_hunks(0, 'apply', { line_start = -2, line_end = -1 })
  local ref_hunks = {
    { buf_start = 1, buf_count = 1, ref_start = 1, ref_count = 1, type = 'change' },
    { buf_start = 2, buf_count = 0, ref_start = 3, ref_count = 1, type = 'delete' },
  }
  validate_dummy_log({ { 'apply_hunks', { get_buf(), ref_hunks } } })

  -- Yank
  do_hunks(0, 'yank', { line_start = -2, line_end = -1 })
  eq(child.fn.getreg('"'), 'AAA\nCCC\n')

  -- Reset
  do_hunks(0, 'reset', { line_start = -2, line_end = -1 })
  eq(get_lines(), { 'AAA', 'BBB', 'CCC' })
end

T['do_hunks()']['allows target range to contain lines between hunks'] = function()
  set_lines({ 'bbb', 'uuu', 'vvv', 'ccc', 'www', 'ddd' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc', 'ddd', 'eee' })

  -- Apply
  do_hunks(0, 'apply')
  -- - By default should do action on all lines
  local ref_hunks = {
    { buf_start = 0, buf_count = 0, ref_start = 1, ref_count = 1, type = 'delete' },
    { buf_start = 2, buf_count = 2, ref_start = 2, ref_count = 0, type = 'add' },
    { buf_start = 5, buf_count = 1, ref_start = 3, ref_count = 0, type = 'add' },
    { buf_start = 6, buf_count = 0, ref_start = 5, ref_count = 1, type = 'delete' },
  }
  validate_dummy_log({ { 'apply_hunks', { get_buf(), ref_hunks } } })

  -- Yank
  do_hunks(0, 'yank')
  eq(child.fn.getreg('"'), 'aaa\neee\n')

  -- Reset
  do_hunks(0, 'reset')
  eq(get_lines(), { 'aaa', 'bbb', 'ccc', 'ddd', 'eee' })
end

T['do_hunks()']['can act on hunk part'] = function()
  set_lines({ 'uuu', 'vvv', 'aaa', 'bbb', 'ccc' })
  set_ref_text(0, { 'aaa', 'BBB', 'CCC' })

  -- Apply
  do_hunks(0, 'apply', { line_start = 2, line_end = 4 })
  local ref_hunks = {
    { buf_start = 2, buf_count = 1, ref_start = 0, ref_count = 0, type = 'add' },
    -- If hunk intersects target range, its reference part is used in full
    { buf_start = 4, buf_count = 1, ref_start = 2, ref_count = 2, type = 'change' },
  }
  validate_dummy_log({ { 'apply_hunks', { get_buf(), ref_hunks } } })

  -- Yank
  do_hunks(0, 'yank', { line_start = 2, line_end = 4 })
  eq(child.fn.getreg('"'), 'BBB\nCCC\n')

  -- Reset
  do_hunks(0, 'reset', { line_start = 2, line_end = 4 })
  eq(get_lines(), { 'uuu', 'aaa', 'BBB', 'CCC', 'ccc' })
end

T['do_hunks()']['validates arguments'] = function()
  set_lines({ 'aaa', 'bbb', 'ccc' })
  set_ref_text(0, { 'aaa', 'bbb' })

  expect.error(function() do_hunks(-1) end, 'valid buffer')

  expect.error(function() do_hunks(0, 'aaa') end, '`action`.*one of')

  expect.error(function() do_hunks(0, 'apply', { line_start = 'a' }) end, '`line_start`.*number')
  expect.error(function() do_hunks(0, 'apply', { line_end = 'a' }) end, '`line_end`.*number')
  expect.error(function() do_hunks(0, 'apply', { line_start = 2, line_end = 1 }) end, '`line_start`.*less.*`line_end`')

  disable()
  expect.error(function() do_hunks(0) end, 'Buffer.*not enabled')
end

T['goto_hunk()'] = new_set()

local goto_hunk = forward_lua('MiniDiff.goto_hunk')

T['goto_hunk()']['works'] = function()
  set_lines({ 'uuu', 'aaa', 'vvv', 'bbb', 'www', 'ccc', 'xxx' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc' })

  local validate = function(direction, ref_cursor)
    set_cursor(4, 0)
    goto_hunk(direction)
    eq(get_cursor(), ref_cursor)
  end

  validate('first', { 1, 0 })
  validate('prev', { 3, 0 })
  validate('next', { 5, 0 })
  validate('last', { 7, 0 })
end

T['goto_hunk()']['works when inside hunk range'] = function()
  set_lines({ 'uuu', 'aaa', 'vvv', 'www', 'xxx', 'ccc', 'yyy' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc' })

  local validate = function(direction, ref_cursor)
    set_cursor(4, 0)
    goto_hunk(direction)
    eq(get_cursor(), ref_cursor)
  end

  -- Should not count current hunk when computing target
  validate('first', { 1, 0 })
  validate('prev', { 1, 0 })
  validate('next', { 7, 0 })
  validate('last', { 7, 0 })
end

T['goto_hunk()']['respects `opts.n_times`'] = function()
  set_lines({ 'uuu', 'aaa', 'vvv', 'bbb', 'www', 'ccc', 'xxx' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc' })

  local validate = function(direction, ref_cursor)
    set_cursor(4, 0)
    goto_hunk(direction, { n_times = 2 })
    eq(get_cursor(), ref_cursor)
  end

  validate('first', { 3, 0 })
  validate('prev', { 1, 0 })
  validate('next', { 7, 0 })
  validate('last', { 5, 0 })
end

T['goto_hunk()']['allows too big `opts.n_times`'] = function()
  set_lines({ 'uuu', 'aaa', 'vvv', 'bbb', 'www', 'ccc', 'xxx' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc' })

  local validate = function(direction, ref_cursor)
    set_cursor(4, 0)
    goto_hunk(direction, { n_times = 1000 })
    eq(get_cursor(), ref_cursor)
    validate_notifications({})
  end

  -- Should partially go until reaches the end
  validate('first', { 7, 0 })
  validate('prev', { 1, 0 })
  validate('next', { 7, 0 })
  validate('last', { 1, 0 })
end

T['goto_hunk()']['respects `opts.line_start`'] = function()
  set_lines({ 'uuu', 'aaa', 'vvv', 'bbb', 'www', 'ccc', 'xxx' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc' })

  local validate = function(direction, ref_cursor)
    set_cursor(1, 0)
    goto_hunk(direction, { line_start = 4 })
    eq(get_cursor(), ref_cursor)
  end

  validate('first', { 1, 0 })
  validate('prev', { 3, 0 })
  validate('next', { 5, 0 })
  validate('last', { 7, 0 })
end

T['goto_hunk()']['respects `opts.wrap`'] = function()
  -- Should use `config.options.wrap_goto` as default value
  child.lua('MiniDiff.config.options.wrap_goto = true')

  set_lines({ 'uuu', 'aaa', 'vvv', 'bbb', 'www', 'ccc', 'xxx' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc' })

  local validate = function(direction, init_cursor, ref_cursor, n_times)
    set_cursor(unpack(init_cursor))
    goto_hunk(direction, { n_times = n_times })
    eq(get_cursor(), ref_cursor)
    validate_notifications({ { '(mini.diff) Wrapped around edge in direction "' .. direction .. '"', 'INFO' } })
    clear_notify_log()
  end

  validate('prev', { 1, 0 }, { 7, 0 })
  validate('next', { 7, 0 }, { 1, 0 })

  validate('prev', { 2, 0 }, { 7, 0 }, 2)
  validate('next', { 6, 0 }, { 1, 0 }, 2)

  validate('prev', { 2, 0 }, { 7, 0 }, 6)
  validate('next', { 6, 0 }, { 1, 0 }, 6)

  validate('first', { 4, 0 }, { 1, 0 }, 5)
  validate('last', { 4, 0 }, { 7, 0 }, 5)

  validate('first', { 4, 0 }, { 3, 0 }, 10)
  validate('last', { 4, 0 }, { 5, 0 }, 10)

  -- Explicit `opts` should take preference
  set_cursor(1, 1)
  goto_hunk('prev', { wrap = false })
  eq(get_cursor(), { 1, 1 })
end

T['goto_hunk()']['does not wrap around edges by default'] = function()
  set_lines({ 'aaa', 'vvv', 'bbb', 'www', 'ccc' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc' })

  local validate = function(direction, init_cursor)
    set_cursor(unpack(init_cursor))
    goto_hunk(direction)
    eq(get_cursor(), init_cursor)
    validate_notifications({ { '(mini.diff) No hunk ranges in direction "' .. direction .. '"', 'INFO' } })
    clear_notify_log()
  end

  validate('prev', { 2, 1 })
  validate('next', { 4, 1 })
end

T['goto_hunk()']['works with no hunks'] = function()
  set_lines({ 'aaa' })
  set_ref_text(0, { 'aaa' })

  local cursor = get_cursor()
  goto_hunk('next')
  eq(get_cursor(), cursor)
  validate_notifications({ { '(mini.diff) No hunks to go to', 'INFO' } })
end

T['goto_hunk()']['correctly computes contiguous ranges'] = function()
  local validate = function(init_cursor, direction, opts, ref_cursor)
    set_cursor(unpack(init_cursor))
    goto_hunk(direction, opts)
    eq(get_cursor(), ref_cursor)
  end

  -- "Change" hunk adjacent to "add" and "delete" hunks
  set_lines({ 'AAA', 'uuu', 'BbB', 'DDD', 'www', 'EEE' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC', 'DDD', 'EEE' })
  eq(get_buf_hunks(), {
    { buf_start = 2, buf_count = 1, ref_start = 1, ref_count = 0, type = 'add' },
    { buf_start = 3, buf_count = 1, ref_start = 2, ref_count = 1, type = 'change' },
    { buf_start = 3, buf_count = 0, ref_start = 3, ref_count = 1, type = 'delete' },
    { buf_start = 5, buf_count = 1, ref_start = 4, ref_count = 0, type = 'add' },
  })

  validate({ 1, 0 }, 'first', {}, { 2, 0 })
  validate({ 1, 0 }, 'first', { n_times = 2 }, { 5, 0 })

  validate({ 6, 0 }, 'prev', {}, { 5, 0 })
  validate({ 5, 0 }, 'prev', {}, { 2, 0 })

  validate({ 1, 0 }, 'next', {}, { 2, 0 })
  validate({ 2, 0 }, 'next', {}, { 5, 0 })

  validate({ 6, 0 }, 'last', {}, { 5, 0 })
  validate({ 6, 0 }, 'last', { n_times = 2 }, { 2, 0 })
end

T['goto_hunk()']['adds current position to jump list'] = function()
  set_lines({ 'aaa', 'uuu', 'bbb', 'vvv', 'ccc' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc' })

  local validate = function(init_cursor, direction, ref_cursor)
    set_cursor(unpack(init_cursor))
    goto_hunk(direction)
    eq(get_cursor(), ref_cursor)
    type_keys('<C-o>')
    eq(get_cursor(), init_cursor)
  end

  validate({ 3, 1 }, 'first', { 2, 0 })
  validate({ 3, 1 }, 'prev', { 2, 0 })
  validate({ 3, 1 }, 'next', { 4, 0 })
  validate({ 3, 1 }, 'last', { 4, 0 })
end

T['goto_hunk()']['puts cursor on first line of range'] = function()
  set_lines({ 'aaa', 'uuu', 'vvv', 'bbb', 'www', 'xxx', 'ccc' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc' })

  local validate = function(init_cursor, direction, ref_cursor)
    set_cursor(unpack(init_cursor))
    goto_hunk(direction)
    eq(get_cursor(), ref_cursor)
  end

  validate({ 1, 0 }, 'first', { 2, 0 })
  validate({ 7, 0 }, 'first', { 2, 0 })

  validate({ 6, 0 }, 'prev', { 2, 0 })
  validate({ 4, 0 }, 'prev', { 2, 0 })

  validate({ 1, 0 }, 'next', { 2, 0 })
  validate({ 4, 0 }, 'next', { 5, 0 })

  validate({ 7, 0 }, 'last', { 5, 0 })
  validate({ 4, 0 }, 'last', { 5, 0 })
end

T['goto_hunk()']['puts cursor on first non-blank column'] = function()
  set_lines({ 'AAA', '  uuu', 'BBB', '\tvvv', 'CCC', '\t www', 'DDD' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC', 'DDD' })

  local validate = function(init_cursor, direction, opts, ref_cursor)
    set_cursor(unpack(init_cursor))
    goto_hunk(direction, opts)
    eq(get_cursor(), ref_cursor)
  end

  validate({ 1, 0 }, 'first', {}, { 2, 2 })
  validate({ 1, 0 }, 'first', { n_times = 2 }, { 4, 1 })
  validate({ 1, 0 }, 'first', { n_times = 3 }, { 6, 2 })

  validate({ 7, 0 }, 'prev', {}, { 6, 2 })
  validate({ 5, 0 }, 'prev', {}, { 4, 1 })
  validate({ 3, 0 }, 'prev', {}, { 2, 2 })

  validate({ 1, 0 }, 'next', {}, { 2, 2 })
  validate({ 3, 0 }, 'next', {}, { 4, 1 })
  validate({ 5, 0 }, 'next', {}, { 6, 2 })

  validate({ 7, 0 }, 'last', {}, { 6, 2 })
  validate({ 7, 0 }, 'last', { n_times = 2 }, { 4, 1 })
  validate({ 7, 0 }, 'last', { n_times = 3 }, { 2, 2 })
end

T['goto_hunk()']['opens just enough folds'] = function()
  set_lines({ 'aaa', 'uuu', 'bbb', 'ccc', 'ddd', 'eee' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc', 'ddd', 'eee' })

  local validate = function(init_cursor, direction)
    child.cmd('2,3fold')
    child.cmd('5,6fold')
    for i, s in ipairs({ -1, 2, 2, -1, 5, 5 }) do
      eq(child.fn.foldclosed(i), s)
    end

    set_cursor(unpack(init_cursor))
    goto_hunk(direction)
    eq(get_cursor(), { 2, 0 })
    for i, s in ipairs({ -1, -1, -1, -1, 5, 5 }) do
      eq(child.fn.foldclosed(i), s)
    end
  end

  validate({ 1, 0 }, 'first')
  validate({ 3, 0 }, 'prev')
  validate({ 1, 0 }, 'next')
  validate({ 6, 0 }, 'last')
end

T['goto_hunk()']['validates arguments'] = function()
  expect.error(function() goto_hunk('aaa') end, '`direction`.*one of')
  expect.error(function() goto_hunk('next', { n_times = 'a' }) end, '`opts.n_times`.*number')
  expect.error(function() goto_hunk('next', { n_times = 0 }) end, '`opts.n_times`.*positive')
  expect.error(function() goto_hunk('next', { line_start = 'a' }) end, '`opts.line_start`.*number')

  disable()
  expect.error(function() goto_hunk() end, 'Buffer.*not enabled')
end

-- More thorough tests are done in "Integration tests"
T['operator()'] = new_set()

T['operator()']['is present'] = function() eq(child.lua_get('type(MiniDiff.operator)'), 'function') end

T['operator()']['can be used in a mapping'] = function()
  child.lua([[
    local rhs = function() return MiniDiff.operator('yank') .. 'gh' end
    vim.keymap.set('n', 'ghy', rhs, { expr = true, remap = true })
  ]])

  set_lines({ 'ccc', 'DDD', 'EEE', 'fff' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc', 'ddd', 'eee', 'fff' })
  type_keys('ghy')
  eq(child.fn.getreg('"'), 'aaa\nbbb\nddd\neee\n')

  -- Can be used with register
  set_lines({ 'aaa' })
  set_ref_text(0, { 'aaa', 'bbb' })
  type_keys('"aghy')
  eq(child.fn.getreg('a'), 'bbb\n')
  eq(child.fn.getreg('"'), 'aaa\nbbb\nddd\neee\n')
end

-- More thorough tests are done in "Integration tests"
T['textobject()'] = new_set()

T['textobject()']['is present'] = function() eq(child.lua_get('type(MiniDiff.textobject)'), 'function') end

-- More thorough tests are done in "Multiple source" set of "Integration tests"
T['fail_attach()'] = new_set()

T['fail_attach()']['validates arguments'] = function()
  expect.error(function() child.lua('MiniDiff.fail_attach("a")') end, '`buf_id`.*valid buffer id')
end

-- Integration tests ==========================================================
T['Auto enable'] = new_set()

T['Auto enable']['works'] = function()
  local buf_id = new_buf()
  set_buf(buf_id)
  eq(is_buf_enabled(buf_id), true)

  -- Should auto enable only in listed buffers
  local buf_id_unlisted = child.api.nvim_create_buf(false, false)
  set_buf(buf_id_unlisted)
  eq(is_buf_enabled(buf_id_unlisted), false)

  -- Should try auto enable in `BufEnter`
  disable(buf_id)
  eq(is_buf_enabled(buf_id), false)
  set_buf(buf_id)
  eq(is_buf_enabled(buf_id), true)

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

T['Auto enable']['does not enable in not proper buffers'] = function()
  -- Has set `vim.b.minidiff_disable`
  local buf_id_disabled = new_buf()
  child.api.nvim_buf_set_var(buf_id_disabled, 'minidiff_disable', true)
  set_buf(buf_id_disabled)
  eq(is_buf_enabled(buf_id_disabled), false)

  -- Is not normal
  set_buf(new_scratch_buf())
  eq(is_buf_enabled(0), false)

  -- Is not text buffer
  local buf_id_not_text = new_buf()
  child.api.nvim_buf_set_lines(buf_id_not_text, 0, -1, false, { 'aa', '\0', 'bb' })
  set_buf(buf_id_not_text)
  eq(is_buf_enabled(buf_id_not_text), false)
end

T['Auto enable']['works after `:edit`'] = function()
  child.lua([[
    MiniDiff.config.source = { attach = function(buf_id) MiniDiff.set_ref_text(buf_id, { 'aaa' }) end }
  ]])

  edit(test_file_path)
  eq(is_buf_enabled(0), true)
  local ref_hunks = { { buf_start = 2, buf_count = 1, ref_start = 1, ref_count = 0, type = 'add' } }
  eq(get_buf_hunks(0), ref_hunks)

  -- - It should be able to use `:edit` to update buffer config
  child.b.minidiff_config = { options = { algorithm = 'minimal' } }
  eq(get_buf_data(0).config.options.algorithm, 'histogram')

  child.cmd('edit')
  eq(get_lines(), { 'aaa', 'uuu' })

  eq(is_buf_enabled(0), true)
  eq(get_buf_hunks(0), ref_hunks)
  eq(get_buf_data(0).config.options.algorithm, 'minimal')
  validate_viz_extmarks(0, { { line = 2, sign_hl_group = 'MiniDiffSignAdd', sign_text = '▒ ' } })
end

T['Visualization'] = new_set({ hooks = { pre_case = setup_enabled_buffer } })

T['Visualization']['works'] = function()
  set_lines({ 'AAA', 'uuu', 'BBB', 'CcC', 'DDD', 'FFF' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC', 'DDD', 'EEE', 'FFF' })

  local init_viz_extmarks = {
    { line = 2, sign_hl_group = 'MiniDiffSignAdd', sign_text = '▒ ' },
    { line = 4, sign_hl_group = 'MiniDiffSignChange', sign_text = '▒ ' },
    { line = 5, sign_hl_group = 'MiniDiffSignDelete', sign_text = '▒ ' },
  }
  validate_viz_extmarks(0, init_viz_extmarks)
  child.expect_screenshot()

  -- Should update in debounce fashion
  set_cursor(6, 0)
  type_keys('o', 'hello')
  validate_viz_extmarks(0, init_viz_extmarks)

  sleep(dummy_text_change_delay - 2 * small_time)
  validate_viz_extmarks(0, init_viz_extmarks)

  type_keys('<CR>', 'world')
  sleep(dummy_text_change_delay - 2 * small_time)
  validate_viz_extmarks(0, init_viz_extmarks)

  sleep(2 * small_time + small_time)
  validate_viz_extmarks(0, {
    { line = 2, sign_hl_group = 'MiniDiffSignAdd', sign_text = '▒ ' },
    { line = 4, sign_hl_group = 'MiniDiffSignChange', sign_text = '▒ ' },
    { line = 5, sign_hl_group = 'MiniDiffSignDelete', sign_text = '▒ ' },
    { line = 7, sign_hl_group = 'MiniDiffSignAdd', sign_text = '▒ ' },
    { line = 8, sign_hl_group = 'MiniDiffSignAdd', sign_text = '▒ ' },
  })
end

T['Visualization']['does not appear if there is no gutter'] = function()
  child.o.signcolumn, child.o.number = 'no', false
  disable()
  enable()

  set_lines({ 'AAA', 'uuu', 'BBB', 'CcC', 'DDD', 'FFF' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC', 'DDD', 'EEE', 'FFF' })
  -- Shouldn't force neither sign nor number column
  child.expect_screenshot()
end

T['Visualization']['can be visually disabled'] = function()
  child.lua('MiniDiff.config.view.style = "sign"')
  child.lua('MiniDiff.config.view.signs = { add = "", change = "", delete = "" }')
  disable()
  enable()

  set_lines({ 'AAA', 'uuu', 'BBB', 'CcC', 'DDD', 'FFF' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC', 'DDD', 'EEE', 'FFF' })
  -- Shouldn't show sign column, although extmarks are still placed
  child.expect_screenshot()
  eq(#get_viz_extmarks(0) > 0, true)
end

T['Visualization']['works with "add" hunks'] = function()
  -- Every added line should be visualized as part of hunk
  set_lines({ 'aaa', 'uuu', 'vvv', 'bbb', 'www', 'ccc' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc' })
  validate_viz_extmarks(0, {
    { line = 2, sign_hl_group = 'MiniDiffSignAdd', sign_text = '▒ ' },
    { line = 3, sign_hl_group = 'MiniDiffSignAdd', sign_text = '▒ ' },
    { line = 5, sign_hl_group = 'MiniDiffSignAdd', sign_text = '▒ ' },
  })
  child.expect_screenshot()

  -- Should work if added is on edge
  set_lines({ 'uuu', 'aaa', 'bbb' })
  set_ref_text(0, { 'aaa' })
  validate_viz_extmarks(0, {
    { line = 1, sign_hl_group = 'MiniDiffSignAdd', sign_text = '▒ ' },
    { line = 3, sign_hl_group = 'MiniDiffSignAdd', sign_text = '▒ ' },
  })
  child.expect_screenshot()
end

T['Visualization']['works with "change" hunks'] = function()
  -- Every changed line should be visualized as part of hunk
  set_lines({ 'AAA', 'BbB', '', 'DDD', 'EeE', 'FFF' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC', 'DDD', 'EEE', 'FFF' })
  validate_viz_extmarks(0, {
    { line = 2, sign_hl_group = 'MiniDiffSignChange', sign_text = '▒ ' },
    { line = 3, sign_hl_group = 'MiniDiffSignChange', sign_text = '▒ ' },
    { line = 5, sign_hl_group = 'MiniDiffSignChange', sign_text = '▒ ' },
  })
  child.expect_screenshot()

  -- Should work if added is on edge
  set_lines({ 'AaA', 'BBB', 'CcC' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC' })
  validate_viz_extmarks(0, {
    { line = 1, sign_hl_group = 'MiniDiffSignChange', sign_text = '▒ ' },
    { line = 3, sign_hl_group = 'MiniDiffSignChange', sign_text = '▒ ' },
  })
  child.expect_screenshot()
end

T['Visualization']['works with "delete" hunks'] = function()
  -- Whole deleted hunk should be visualized at single line nearby
  set_lines({ 'aaa', 'ddd', 'eee', 'ggg' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc', 'ddd', 'eee', 'fff', 'ggg' })
  validate_viz_extmarks(0, {
    { line = 1, sign_hl_group = 'MiniDiffSignDelete', sign_text = '▒ ' },
    { line = 3, sign_hl_group = 'MiniDiffSignDelete', sign_text = '▒ ' },
  })
  child.expect_screenshot()

  -- Should work if hunk is on edge
  set_lines({ 'bbb', 'ccc' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc', 'ddd' })
  validate_viz_extmarks(0, {
    { line = 1, sign_hl_group = 'MiniDiffSignDelete', sign_text = '▒ ' },
    { line = 2, sign_hl_group = 'MiniDiffSignDelete', sign_text = '▒ ' },
  })
  child.expect_screenshot()

  -- Should work if overlap
  set_lines({ 'bbb' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc' })
  validate_viz_extmarks(0, {
    { line = 1, sign_hl_group = 'MiniDiffSignDelete', sign_text = '▒ ' },
  })
  child.expect_screenshot()
end

T['Visualization']['works when "change" overlaps with "delete"'] = function()
  -- Should prefer "change"
  set_lines({ 'AAA', 'BbB', 'DDD' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC', 'DDD' })
  validate_viz_extmarks(0, { { line = 2, sign_hl_group = 'MiniDiffSignChange', sign_text = '▒ ' } })
end

T['Visualization']['reacts to hunk lines delete/move'] = function()
  if child.fn.has('nvim-0.10') == 0 then MiniTest.skip('Reaction to line delete/move is available on Neovim>=0.10.') end
  child.o.signcolumn = 'yes'

  set_lines({ 'aaa', 'bbb', 'uuu', 'vvv', 'ccc', 'ddd' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc', 'ddd' })

  validate_viz_extmarks(0, {
    { line = 3, sign_hl_group = 'MiniDiffSignAdd', sign_text = '▒ ' },
    { line = 4, sign_hl_group = 'MiniDiffSignAdd', sign_text = '▒ ' },
  })

  set_cursor(3, 0)
  type_keys('dj', 'k', 'P')
  -- Should be immediately not drawn (invalidated)
  child.expect_screenshot()

  sleep(dummy_text_change_delay + small_time)
  validate_viz_extmarks(0, {
    { line = 2, sign_hl_group = 'MiniDiffSignAdd', sign_text = '▒ ' },
    { line = 3, sign_hl_group = 'MiniDiffSignAdd', sign_text = '▒ ' },
  })
  child.expect_screenshot()
end

T['Visualization']['forces redraw when it is needed'] = function()
  child.set_size(10, 15)

  child.api.nvim_set_keymap('n', '<C-y>', '<Cmd>normal! yyp<CR>', {})
  local ctrls_rhs = '<Cmd>lua MiniDiff.set_ref_text(0, vim.api.nvim_buf_get_lines(0, 0, -1, false))<CR>'
  child.api.nvim_set_keymap('n', '<C-s>', ctrls_rhs, {})

  set_lines({ 'aaa' })
  set_ref_text(0, { 'aaa' })

  type_keys('gg', '<C-y>')
  sleep(dummy_text_change_delay + small_time)
  validate_viz_extmarks(0, { { line = 2, sign_hl_group = 'MiniDiffSignAdd', sign_text = '▒ ' } })
  child.expect_screenshot()

  type_keys('<C-s>')
  child.expect_screenshot()
end

T['Visualization']['respects `view.style`'] = function()
  child.lua([[MiniDiff.config.view.style = 'number']])
  child.o.number = true
  disable()
  enable()

  set_lines({ 'AAA', 'uuu', 'BBB', 'CcC', 'DDD', 'FFF' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC', 'DDD', 'EEE', 'FFF' })

  local viz_extmarks = {
    { line = 2, number_hl_group = 'MiniDiffSignAdd' },
    { line = 4, number_hl_group = 'MiniDiffSignChange' },
    { line = 5, number_hl_group = 'MiniDiffSignDelete' },
  }
  validate_viz_extmarks(0, viz_extmarks)

  child.expect_screenshot()

  -- Should work even without 'number' set
  child.o.number = false
  disable()
  enable()
  set_lines({ 'AAA', 'uuu', 'BBB', 'CcC', 'DDD', 'FFF' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC', 'DDD', 'EEE', 'FFF' })
  validate_viz_extmarks(0, viz_extmarks)
  child.expect_screenshot()
end

T['Visualization']['shows signcolumn even if hunks are outside of view'] = function()
  -- Make sure that extmark has no visible side effects
  child.o.signcolumn = 'auto:2'
  child.o.cursorline = true
  child.cmd('hi CursrLineSign guibg=Red ctermbg=Red')
  child.cmd('hi SignColumn guibg=Blue ctermbg=Blue')

  child.lua('MiniDiff.config.delay.text_change = ' .. small_time)
  disable()
  enable()

  local lines = { 'AAA', 'BBB', 'CCC', 'DDD', 'EEE', 'FFF', 'GGG', 'HHH', 'III', 'JJJ' }
  set_lines(lines)
  table.insert(lines, 'uuu')
  set_ref_text(0, lines)
  sleep(small_time + small_time)
  child.expect_screenshot()

  -- Should be deleted when not needed, making sign column still only single
  -- "sign width" wide (2 cells)
  type_keys('gg', 'O', '<CR>', '<Esc>')
  sleep(small_time + small_time)
  local ns_id = child.api.nvim_get_namespaces().MiniDiffViz
  local extmarks = child.api.nvim_buf_get_extmarks(0, ns_id, 0, -1, { details = true })
  eq(#extmarks, 2)
  -- Neovim>=0.11 has signs combine attributes, so check screenshot only there
  if child.fn.has('nvim-0.11') == 1 then child.expect_screenshot() end
end

T['Visualization']['respects `view.signs`'] = function()
  child.lua([[MiniDiff.config.view.signs = { add = '+', change = '~', delete = '-' }]])
  disable()
  enable()

  set_lines({ 'AAA', 'uuu', 'BBB', 'CcC', 'DDD', 'FFF' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC', 'DDD', 'EEE', 'FFF' })

  local viz_extmarks = {
    { line = 2, sign_hl_group = 'MiniDiffSignAdd', sign_text = '+ ' },
    { line = 4, sign_hl_group = 'MiniDiffSignChange', sign_text = '~ ' },
    { line = 5, sign_hl_group = 'MiniDiffSignDelete', sign_text = '- ' },
  }
  validate_viz_extmarks(0, viz_extmarks)
  child.expect_screenshot()
end

T['Visualization']['respects `view.priority`'] = function()
  child.lua('MiniDiff.config.view.priority = 100')
  disable()
  enable()

  set_lines({ 'AAA', 'uuu', 'BBB', 'CcC', 'DDD', 'FFF' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC', 'DDD', 'EEE', 'FFF' })

  local ns_id = child.api.nvim_get_namespaces().MiniDiffViz
  local extmarks = child.api.nvim_buf_get_extmarks(0, ns_id, 0, -1, { details = true })
  eq(vim.tbl_map(function(e) return e[4].priority end, extmarks), { 100, 100, 100 })
end

T['Visualization']['respects `vim.b.minidiff_config`'] = function()
  local buf_id = new_buf()
  child.api.nvim_buf_set_var(buf_id, 'minidiff_config', { view = { style = 'number' } })
  set_buf(buf_id)

  set_lines({ 'AAA', 'uuu', 'BBB' })
  set_ref_text(buf_id, { 'AAA', 'BBB' })

  validate_viz_extmarks(0, { { line = 2, number_hl_group = 'MiniDiffSignAdd' } })
end

T['Overlay'] = new_set({
  hooks = {
    pre_case = function()
      child.set_size(15, 15)
      setup_enabled_buffer()
      toggle_overlay(0)
    end,
  },
})

T['Overlay']['works'] = function()
  set_lines({ 'AAA', 'uuu', 'BBB', 'CcC', 'DDD', 'FFF' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC', 'DDD', 'EEE', 'FFF' })

  child.expect_screenshot()

  -- Should be updated interactively when diff itself is updated
  set_cursor(5, 0)
  type_keys('A', '<CR>', 'EeE')

  child.expect_screenshot()
  sleep(dummy_text_change_delay + small_time)
  child.expect_screenshot()
end

T['Overlay']['works with "add" hunks'] = function()
  set_lines({ 'aaa', 'uuu', 'vvv', 'bbb', 'www', 'ccc' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc' })
  child.expect_screenshot()
end

T['Overlay']['works with "change" hunks'] = function()
  child.lua('MiniDiff.config.options.linematch = 0')

  -- When number of added and deleted lines are the same, reference lines
  -- should be shown next to the corresponding buffer lines
  set_lines({ 'AAA', 'BbB', 'CcC', 'DdD', 'EEE' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC', 'DDD', 'EEE' })
  child.expect_screenshot()

  -- When number of added and deleted lines are not the same, all reference
  -- lines should be shown together above hunk's first buffer line
  set_lines({ 'AAA', 'uuu', 'BbB', 'CcC', 'DdD', 'EEE' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC', 'DDD', 'EEE' })
  child.expect_screenshot()
end

T['Overlay']['works with "delete" hunks'] = function()
  set_lines({ 'aaa', 'ddd', 'fff' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc', 'ddd', 'eee', 'fff' })
  child.expect_screenshot()
end

T['Overlay']['always highlights whole lines'] = function()
  child.set_size(10, 15)
  set_lines({ 'AAA', 'uuu', 'BBB', 'CcC', 'DDD', 'FFF' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC', 'DDD', 'EEE', 'FFF' })

  child.set_size(10, 25)
  child.expect_screenshot()
end

T['Overlay']['scrolls along with buffer lines'] = function()
  if child.fn.has('nvim-0.11') == 0 then MiniTest.skip('Virtual line scroll is available only on Neovim>=0.11') end

  child.set_size(10, 15)
  child.o.wrap = false
  local l = 'abcdefghijklmnopqrstuvwxyz'
  local L = l:upper()
  local ref_lines = { 1 .. l, 2 .. l, 3 .. l, 4 .. l, 5 .. l, 6 .. l }
  set_lines({ 1 .. l, 3 .. l, 4 .. L, 6 .. l })
  set_cursor(1, 0)
  set_ref_text(0, ref_lines)

  -- Should scroll virtual lines for deleted and changed with linematch hunks
  type_keys('zL')
  child.expect_screenshot()

  -- Should also scroll virtual lines for change hunks without linematch
  child.lua('MiniDiff.config.options.linematch = 0')
  set_cursor(1, 0)
  set_ref_text(0, ref_lines)
  type_keys('zL')
  child.expect_screenshot()
end

T['Overlay']['works at edge lines'] = function()
  child.set_size(10, 15)
  -- Virtual lines above first line need scroll to become visible
  -- See https://github.com/neovim/neovim/issues/16166
  -- Better with `<C-y>`. See https://github.com/neovim/neovim/issues/27967.

  -- 'Add' hunks
  set_lines({ 'uuu', 'aaa', 'vvv' })
  set_ref_text(0, { 'aaa' })
  child.expect_screenshot()

  -- 'Change' hunks
  set_lines({ 'AaA', 'BBB', 'CcC' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC' })
  type_keys('<C-y>')
  child.expect_screenshot()

  -- 'Delete' hunks
  set_lines({ 'BBB' })
  set_ref_text(0, { 'AAA', 'BBB', 'DDD' })
  type_keys('<C-y>')
  child.expect_screenshot()
end

T['Overlay']['works when "change" overlaps with "delete"'] = function()
  set_lines({ 'AAA', 'BbB', 'DDD' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC', 'DDD' })
  child.expect_screenshot()
end

T['Overlay']['uses correct highlight groups'] = function()
  set_lines({ 'AAA', 'uuu', 'BBB', 'CcC', 'DDD', 'FFF' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC', 'DDD', 'EEE', 'FFF' })

  -- 'Add'
  local add_extmarks = get_overlay_extmarks(0, 2, 2)
  eq(#add_extmarks, 1)
  eq(add_extmarks[1][4].hl_group, 'MiniDiffOverAdd')

  -- 'Change'
  local change_extmarks = get_overlay_extmarks(0, 4, 4)
  eq(#change_extmarks, 3)

  -- - Context of buffer changes as whole line highlighting
  local change_details_1 = change_extmarks[1][4]
  eq(change_extmarks[1][2], 3)
  eq(change_extmarks[1][3], 0)
  eq(change_details_1.end_row, 4)
  eq(change_details_1.end_col, 0)
  eq(change_details_1.hl_eol, true)
  eq(change_details_1.hl_group, 'MiniDiffOverContextBuf')
  eq(change_details_1.priority, 198)

  -- - Context and change of reference text (as virtual line)
  local change_virt_lines = change_extmarks[2][4].virt_lines
  eq(#change_virt_lines, 1)
  eq(change_virt_lines[1][1], { 'C', 'MiniDiffOverContext' })
  eq(change_virt_lines[1][2], { 'C', 'MiniDiffOverChange' })
  eq(change_virt_lines[1][3], { 'C', 'MiniDiffOverContext' })
  eq(change_extmarks[2][4].virt_lines_above, true)

  -- - Buffer changes as separate extmarks
  eq(change_extmarks[3][4].hl_group, 'MiniDiffOverChangeBuf')

  -- 'Delete'
  local delete_extmarks = get_overlay_extmarks(0, 5, 5)
  eq(#delete_extmarks, 1)

  eq(delete_extmarks[1][4].virt_lines_above, false)
  eq(delete_extmarks[1][4].virt_lines_above, false)
  local delete_virt_lines = delete_extmarks[1][4].virt_lines
  eq(#delete_virt_lines, 1)
  eq(delete_virt_lines[1][1], { 'EEE', 'MiniDiffOverDelete' })
end

T['Overlay']['uses correct highlight groups in uneven change hunks'] = function()
  child.lua('MiniDiff.config.options.linematch = 0')
  set_lines({ 'aaa', 'eee', 'fff', 'ggg', 'ddd' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc', 'ddd' })
  local extmarks = get_overlay_extmarks(0, 1, 5)

  eq(#extmarks, 1)
  -- Both changed reference lines should be shown as virtual lines
  local virt_lines = extmarks[1][4].virt_lines
  eq(virt_lines[1][1][2], 'MiniDiffOverChange')
  eq(virt_lines[2][1][2], 'MiniDiffOverChange')

  -- All three changed lines should be highlighted as whole lines
  eq(extmarks[1][2], 1)
  eq(extmarks[1][3], 0)
  eq(extmarks[1][4].end_row, 4)
  eq(extmarks[1][4].end_col, 0)
  eq(extmarks[1][4].hl_eol, true)
  eq(extmarks[1][4].hl_group, 'MiniDiffOverContextBuf')
end

T['Overlay']['respects `view.priority`'] = function()
  child.lua('MiniDiff.config.view.priority = MiniDiff.config.view.priority - 10')
  local ref_priority = child.lua_get('MiniDiff.config.view.priority')

  set_lines({ 'AAA', 'uuu', 'BBB', 'CcC', 'DDD', 'FFF' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC', 'DDD', 'EEE', 'FFF' })
  local overlay_extmarks = get_overlay_extmarks(0, 1, 6)
  local priorities = vim.tbl_map(function(t) return t[4].priority end, overlay_extmarks)
  -- Some extmarks (for context of changed buffer text) have one less of
  -- reference priority to be below highlighting for changed buffer text
  local is_proper = vim.tbl_map(function(p) return p == ref_priority or p == (ref_priority - 1) end, priorities)
  eq(is_proper, vim.tbl_map(function() return true end, priorities))
end

T['Overlay']['word diff'] = new_set()

T['Overlay']['word diff']['works'] = function()
  set_lines({ 'AAA', 'b_BBB_b', 'CCcccC', 'DDD', 'xxx' })
  set_ref_text(0, { 'AAA', 'B_BBB_B', 'CCC', 'DDdddD', 'EEE' })
  child.expect_screenshot()
end

T['Overlay']['word diff']['works with one of lines being empty'] = function()
  child.set_size(7, 15)
  set_lines({ 'uuu', '', 'vvv' })
  set_ref_text(0, { 'uuu', 'AAA', 'vvv' })
  child.expect_screenshot()
  set_lines({ 'uuu', 'AAA', 'vvv' })
  set_ref_text(0, { 'uuu', '', 'vvv' })
  child.expect_screenshot()
end

T['Overlay']['word diff']['has non-zero interhunk context'] = function()
  -- Changed characters which are near enough should be visualized as the whole
  -- range between them is also changed. This reduces visual noise.
  set_lines({ '__34567890', '_2_4567890', '_23_567890', '_234_67890', '_2345_7890', '_23456_890' })
  set_ref_text(0, { '1234567890', '1234567890', '1234567890', '1234567890', '1234567890', '1234567890' })
  type_keys('<C-y>')
  child.expect_screenshot()
end

T['Overlay']['word diff']['works with multibyte characters'] = function()
  child.set_size(10, 15)

  local validate = function(buf_lines, ref_lines)
    set_lines(buf_lines)
    set_ref_text(0, ref_lines)
    type_keys('<C-y>')
    child.expect_screenshot()
  end

  -- Byte representation of characters (for reference):
  -- - ы - { '<d1>', '<8b>' }
  -- - ф - { '<d1>', '<84>' }
  -- - ▒ - { '<e2>', '<96>', '<92>' }
  -- - ┃ - { '<e2>', '<94>', '<83>' }
  validate({ 'фыы', 'ыфы', 'ыыф' }, { 'ыыы', 'ыыы', 'ыыы' })
  validate({ 'ыыы', 'ыыы', 'ыыы' }, { 'фыы', 'ыфы', 'ыыф' })
  validate({ 'фыы', 'ыфы', 'ыыф' }, { 'ыы', 'ыы', 'ыы' })
  validate({ 'ыы', 'ыы', 'ыы' }, { 'фыы', 'ыфы', 'ыыф' })

  validate({ '┃▒▒', '▒┃▒', '▒▒┃' }, { '▒▒▒', '▒▒▒', '▒▒▒' })
  validate({ '▒▒▒', '▒▒▒', '▒▒▒' }, { '┃▒▒', '▒┃▒', '▒▒┃' })
  validate({ '┃▒▒', '▒┃▒', '▒▒┃' }, { '▒▒', '▒▒', '▒▒' })
  validate({ '▒▒', '▒▒', '▒▒' }, { '┃▒▒', '▒┃▒', '▒▒┃' })

  validate({ 'ыxx', 'xыx', 'xxы' }, { 'xxx', 'xxx', 'xxx' })
  validate({ 'xxx', 'xxx', 'xxx' }, { 'ыxx', 'xыx', 'xxы' })
end

T['Overlay']['word diff']['works with BOM bytes'] = function()
  local path = test_dir_absolute .. '/file-bom'
  edit(path)
  local content = child.fn.readblob(path, 'b'):gsub('\r', '')

  toggle_overlay(0)
  set_lines({ 'bBb', 'vvv' })
  set_ref_text(0, content)

  type_keys('<C-y>')
  child.expect_screenshot()
end

T['Diff'] = new_set({ hooks = { pre_case = setup_enabled_buffer } })

T['Diff']['works'] = function()
  set_lines({ 'aaa', 'uuu', 'bbb' })
  set_ref_text(0, { 'aaa', 'bbb' })
  local other_buf_id = new_buf()
  child.api.nvim_buf_set_lines(other_buf_id, 0, -1, false, { 'ccc', 'vvv', 'ddd' })
  set_ref_text(other_buf_id, { 'ccc', 'ddd' })

  local ref_hunks_before = { { buf_start = 2, buf_count = 1, ref_start = 1, ref_count = 0, type = 'add' } }
  eq(get_buf_hunks(0), ref_hunks_before)
  eq(get_buf_hunks(other_buf_id), ref_hunks_before)

  -- Should be updated in debounce fashion across all buffers
  set_cursor(2, 0)
  type_keys('o', 'hello', '<Esc>')
  eq(get_buf_hunks(0), ref_hunks_before)
  eq(get_buf_hunks(other_buf_id), ref_hunks_before)

  local small_time_bigger = 2 * small_time

  sleep(dummy_text_change_delay - small_time_bigger)
  eq(get_buf_hunks(0), ref_hunks_before)
  eq(get_buf_hunks(other_buf_id), ref_hunks_before)

  set_buf(other_buf_id)
  set_cursor(2, 0)
  type_keys('o', 'world', '<Esc>')

  sleep(dummy_text_change_delay - small_time_bigger)
  eq(get_buf_hunks(0), ref_hunks_before)
  eq(get_buf_hunks(other_buf_id), ref_hunks_before)

  sleep(small_time_bigger + small_time)

  local ref_hunks_after = { { buf_start = 2, buf_count = 2, ref_start = 1, ref_count = 0, type = 'add' } }
  eq(get_buf_hunks(0), ref_hunks_after)
  eq(get_buf_hunks(other_buf_id), ref_hunks_after)
end

T['Diff']['sets proper summary buffer-local variables'] = function()
  set_lines({ 'AAA', 'uuu', 'BBB', 'ccc', 'DDD', 'EEE', 'GGG' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC', 'DDD', 'EEE', 'FFF', 'GGG' })

  eq(child.b.minidiff_summary, { source_name = 'dummy', add = 1, change = 1, delete = 1, n_ranges = 3 })
  eq(child.b.minidiff_summary_string, '#3 +1 ~1 -1')

  -- Summary string should maintain order of "n-add-change-delete"
  local validate_summary_string = function(buf_lines, ref_lines, ref_summary_string)
    set_lines(buf_lines)
    set_ref_text(0, ref_lines)
    eq(child.b.minidiff_summary_string, ref_summary_string)
  end

  validate_summary_string({ 'AAA', 'uuu' }, { 'AAA' }, '#1 +1')
  validate_summary_string({ 'aaa' }, { 'AAA' }, '#1 ~1')
  validate_summary_string({ 'AAA' }, { 'AAA', 'BBB' }, '#1 -1')

  validate_summary_string({ 'AAA', 'CCC', 'ddd' }, { 'AAA', 'BBB', 'CCC', 'DDD' }, '#2 ~1 -1')
  validate_summary_string({ 'AAA', 'CCC', 'uuu' }, { 'AAA', 'BBB', 'CCC' }, '#2 +1 -1')
  validate_summary_string({ 'AAA', 'uuu', 'BBB', 'ccc', 'DDD' }, { 'AAA', 'BBB', 'CCC', 'DDD' }, '#2 +1 ~1')

  -- Should still set if enabled but no ref text
  validate_summary_string({ 'AAA', 'uuu' }, {}, '')
  set_ref_text(0, {})
  eq(child.b.minidiff_summary, { source_name = 'dummy' })
end

T['Diff']['respects `options.algorithm`'] = function()
  child.lua('MiniDiff.config.options.linematch = 0')
  local ref_lines = { '[', ']', 'AAA', 'CCC', 'BBB', '[', ']' }

  set_lines({ '[', 'AAA', ']', 'CCC', '[', 'BBB', ']' })
  set_ref_text(0, ref_lines)
  local histogram_hunks = {
    { buf_start = 1, buf_count = 0, ref_start = 2, ref_count = 1, type = 'delete' },
    { buf_start = 3, buf_count = 4, ref_start = 4, ref_count = 3, type = 'change' },
  }
  eq(get_buf_hunks(0), histogram_hunks)

  child.lua([[MiniDiff.config.options.algorithm = 'myers']])
  set_ref_text(0, ref_lines)
  local myers_hunks = {
    { buf_start = 1, buf_count = 0, ref_start = 2, ref_count = 1, type = 'delete' },
    { buf_start = 3, buf_count = 1, ref_start = 3, ref_count = 0, type = 'add' },
    { buf_start = 4, buf_count = 0, ref_start = 5, ref_count = 1, type = 'delete' },
    { buf_start = 6, buf_count = 1, ref_start = 6, ref_count = 0, type = 'add' },
  }
  eq(get_buf_hunks(0), myers_hunks)
end

T['Diff']['respects `options.indent_heuristic`'] = function()
  set_lines({ 'xxx', ' aaa', ' bbb', '', '', ' aaa', 'xxx' })
  local ref_lines = { 'xxx', ' aaa', 'xxx' }

  set_ref_text(0, ref_lines)
  eq(get_buf_hunks(0), { { buf_start = 2, buf_count = 4, ref_start = 1, ref_count = 0, type = 'add' } })

  child.lua('MiniDiff.config.options.indent_heuristic = false')
  set_ref_text(0, ref_lines)
  eq(get_buf_hunks(0), { { buf_start = 3, buf_count = 4, ref_start = 2, ref_count = 0, type = 'add' } })
end

T['Diff']['respects `options.linematch`'] = function()
  set_lines({ 'xxx', 'uuu', 'AaA', 'xxx' })
  local ref_lines = { 'xxx', 'AAA', 'xxx' }

  set_ref_text(0, ref_lines)
  local linematch_hunks = {
    { buf_start = 2, buf_count = 1, ref_start = 1, ref_count = 0, type = 'add' },
    { buf_start = 3, buf_count = 1, ref_start = 2, ref_count = 1, type = 'change' },
  }
  eq(get_buf_hunks(0), linematch_hunks)

  child.lua('MiniDiff.config.options.linematch = 0')
  set_ref_text(0, ref_lines)
  local nolinematch_hunks = {
    { buf_start = 2, buf_count = 2, ref_start = 2, ref_count = 1, type = 'change' },
  }
  eq(get_buf_hunks(0), nolinematch_hunks)
end

T['Diff']['works with BOM bytes'] = function()
  local small_text_change_delay = 3 * small_time
  child.lua('MiniDiff.config.delay.text_change = ' .. small_text_change_delay)
  local lines = { 'aaa', 'bbb' }

  local validate_bom_buffer = function(fileencoding, bytes)
    -- Mock buffer with BOM bytes
    local buf_id = new_scratch_buf()
    set_buf(buf_id)

    child.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
    child.api.nvim_set_option_value('fileencoding', fileencoding, { buf = buf_id })
    child.api.nvim_set_option_value('bomb', true, { buf = buf_id })

    local text_lines = vim.deepcopy(lines)
    text_lines[1] = bytes .. text_lines[1]
    set_ref_text(buf_id, text_lines)

    -- Should respect BOM bytes and not report first line as "change" hunk
    eq(get_buf_data().hunks, {})

    type_keys('G', 'o', 'hello', '<Esc>')
    sleep(small_text_change_delay + small_time)
    eq(get_buf_data().hunks, { { type = 'add', buf_start = 3, buf_count = 1, ref_start = 2, ref_count = 0 } })
  end

  validate_bom_buffer('utf-8', string.char(0xef, 0xbb, 0xbf))
  validate_bom_buffer('utf-16be', string.char(0xfe, 0xff))
  validate_bom_buffer('utf-16', string.char(0xfe, 0xff))
  validate_bom_buffer('utf-16le', string.char(0xff, 0xfe))
  validate_bom_buffer('ucs-4be', string.char(0x00, 0x00, 0xfe, 0xff))
  validate_bom_buffer('ucs-4', string.char(0x00, 0x00, 0xfe, 0xff))
  validate_bom_buffer('ucs-4le', string.char(0xff, 0xfe, 0x00, 0x00))

  validate_bom_buffer('unknown', '')
end

T['Diff']['redraws statusline when diff is updated'] = function()
  set_lines({ 'aaa', 'uuu' })
  set_ref_text(0, { 'aaa' })

  child.o.statusline = '%!b:minidiff_summary_string'
  child.expect_screenshot()

  set_cursor(2, 0)
  type_keys('o', 'hello')
  sleep(dummy_text_change_delay + small_time)
  child.expect_screenshot()
end

T['Diff']['triggers dedicated event'] = function()
  child.lua([[
    _G.event_log = {}
    local track = function(ev) table.insert(_G.event_log, ev.buf) end
    vim.api.nvim_create_autocmd('User', { pattern = 'MiniDiffUpdated', callback = track})
  ]])

  set_lines({ 'aaa', 'uuu' })
  local buf_id = get_buf()

  set_buf(new_buf())
  set_ref_text(buf_id, { 'aaa' })
  -- Should trigger with correct buffer in event data
  eq(child.lua_get('_G.event_log'), { buf_id })
  set_buf(buf_id)

  set_cursor(2, 0)
  type_keys('o', 'hello')

  eq(child.lua_get('_G.event_log'), { buf_id })
  sleep(dummy_text_change_delay + small_time)
  eq(child.lua_get('_G.event_log'), { buf_id, buf_id })
end

T['Diff']['`MiniDiffUpdated` event can be used to override `minidiff_summary_string` variable'] = function()
  child.set_size(10, 15)
  child.o.laststatus = 2
  child.o.statusline = '%{getbufvar("%", "minidiff_summary_string", "")}'

  child.cmd('au User MiniDiffUpdated lua vim.b.minidiff_summary_string = "Hello"')
  set_lines({ 'aaa', 'uuu' })
  set_ref_text(0, { 'aaa' })
  eq(child.b.minidiff_summary_string, 'Hello')

  -- Should redraw statusline after `MiniDiffUpdated` event is triggered
  child.expect_screenshot()
end

-- More thorough tests are done in "do_hunks"
T['Operator'] = new_set({ hooks = { pre_case = clean_dummy_log } })

T['Operator']['apply'] = new_set()

T['Operator']['apply']['works in Normal mode'] = function()
  local ref_hunks
  set_lines({ 'aaa', 'bbb', 'CCC', 'uuu', 'vvv' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC' })

  set_cursor(1, 0)
  type_keys('gh', 'j')
  ref_hunks = { { buf_start = 1, buf_count = 2, ref_start = 1, ref_count = 2, type = 'change' } }
  validate_dummy_log({ { 'apply_hunks', { get_buf(), ref_hunks } } })
  clean_dummy_log()

  -- With dot-repeat
  set_cursor(4, 0)
  type_keys('.')
  ref_hunks = { { buf_start = 4, buf_count = 2, ref_start = 3, ref_count = 0, type = 'add' } }
  validate_dummy_log({ { 'apply_hunks', { get_buf(), ref_hunks } } })
end

T['Operator']['apply']['allows dot-repeat across buffers'] = function()
  local ref_hunks
  set_lines({ 'aaa', 'uuu', 'vvv' })
  set_ref_text(0, { 'aaa' })
  set_cursor(2, 0)
  type_keys('gh', '_')
  ref_hunks = { { buf_start = 2, buf_count = 1, ref_start = 1, ref_count = 0, type = 'add' } }
  validate_dummy_log({ { 'apply_hunks', { get_buf(), ref_hunks } } })
  clean_dummy_log()

  local new_buf_id = new_buf()
  set_buf(new_buf_id)
  set_lines({ 'ccc', 'ddd', 'www', 'xxx', 'eee' })
  set_ref_text(0, { 'ccc', 'ddd', 'eee' })
  set_cursor(3, 0)
  type_keys('.')
  ref_hunks = { { buf_start = 3, buf_count = 1, ref_start = 2, ref_count = 0, type = 'add' } }
  validate_dummy_log({ { 'attach', { new_buf_id } }, { 'apply_hunks', { new_buf_id, ref_hunks } } })
  clean_dummy_log()
end

T['Operator']['apply']['works in Visual mode'] = function()
  set_lines({ 'aaa', 'bbb', 'CCC', 'uuu', 'vvv' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC' })

  set_cursor(1, 0)
  type_keys('vj', 'gh')
  local ref_hunks = { { buf_start = 1, buf_count = 2, ref_start = 1, ref_count = 2, type = 'change' } }
  validate_dummy_log({ { 'apply_hunks', { get_buf(), ref_hunks } } })
  eq(child.fn.mode(), 'n')
end

T['Operator']['apply']['works on not proper textobject'] = function()
  set_lines({ 'aaa', 'bbb', 'ccc' })
  set_ref_text(0, { 'aaa', 'ccc' })

  type_keys('G', 'ghgh')
  validate_notifications({
    { '(mini.diff) No hunk range under cursor', 'INFO' },
    { '(mini.diff) Not a proper textobject', 'INFO' },
  })
end

T['Operator']['apply']['restores window view'] = function()
  child.set_size(7, 15)
  local ref_hunks

  -- Should restore on first application
  set_lines({ 'ooo', 'ppp', 'qqq', 'rrr', 'aaa', 'sss', 'ttt', 'uuu', 'bbb' })

  set_ref_text(0, { 'aaa', 'bbb' })
  set_cursor(4, 2)
  type_keys('zz')
  eq(child.fn.line('w0'), 2)

  type_keys('gh', 'gg')
  ref_hunks = { { buf_start = 1, buf_count = 4, ref_start = 0, ref_count = 0, type = 'add' } }
  validate_dummy_log({ { 'apply_hunks', { get_buf(), ref_hunks } } })
  clean_dummy_log()

  eq(get_cursor(), { 4, 2 })
  eq(child.fn.line('w0'), 2)

  -- Should not interfere with dot-repeat
  set_ref_text(0, { 'ooo', 'ppp', 'qqq', 'rrr', 'aaa', 'bbb' })
  set_cursor(8, 2)
  type_keys('zz')
  eq(child.fn.line('w0'), 6)
  type_keys('.')
  ref_hunks = { { buf_start = 6, buf_count = 3, ref_start = 5, ref_count = 0, type = 'add' } }
  validate_dummy_log({ { 'apply_hunks', { get_buf(), ref_hunks } } })
  -- - Places cursor at the start of textobject as all operators do
  eq(get_cursor(), { 1, 2 })
  eq(child.fn.line('w0'), 1)
end

T['Operator']['apply']['works with different mapping'] = function()
  child.lua([[MiniDiff.setup({ source = _G.dummy_source, mappings = { apply = 'Gh' } })]])

  set_lines({ 'aaa', 'bbb' })
  set_ref_text(0, { 'aaa' })

  set_cursor(2, 0)
  type_keys('Gh', '_')
  local ref_hunks = { { buf_start = 2, buf_count = 1, ref_start = 1, ref_count = 0, type = 'add' } }
  validate_dummy_log({ { 'apply_hunks', { get_buf(), ref_hunks } } })
end

T['Operator']['reset'] = new_set()

T['Operator']['reset']['works in Normal mode'] = function()
  set_lines({ 'aaa', 'bbb', 'CCC', 'uuu', 'vvv' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC' })

  set_cursor(1, 2)
  type_keys('gH', 'j')
  eq(get_lines(), { 'AAA', 'BBB', 'CCC', 'uuu', 'vvv' })
  eq(get_cursor(), { 1, 2 })

  -- With dot-repeat
  set_cursor(4, 1)
  type_keys('.')
  eq(get_lines(), { 'AAA', 'BBB', 'CCC' })
  eq(get_cursor(), { 3, 1 })
end

T['Operator']['reset']['allows dot-repeat across buffers'] = function()
  set_lines({ 'aaa', 'uuu', 'vvv' })
  set_ref_text(0, { 'aaa' })
  set_cursor(2, 0)
  type_keys('gH', '_')
  eq(get_lines(), { 'aaa', 'vvv' })

  local new_buf_id = new_buf()
  set_buf(new_buf_id)
  set_lines({ 'ccc', 'ddd', 'www', 'xxx', 'eee' })
  set_ref_text(0, { 'ccc', 'ddd', 'eee' })
  set_cursor(3, 0)
  type_keys('.')
  eq(get_lines(), { 'ccc', 'ddd', 'xxx', 'eee' })
end

T['Operator']['reset']['works in Visual mode'] = function()
  set_lines({ 'aaa', 'bbb', 'CCC', 'uuu', 'vvv' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC' })

  set_cursor(1, 2)
  type_keys('vj', 'gH')
  eq(get_lines(), { 'AAA', 'BBB', 'CCC', 'uuu', 'vvv' })
  eq(get_cursor(), { 1, 2 })
end

T['Operator']['reset']['works on not proper textobject'] = function()
  set_lines({ 'aaa', 'bbb', 'ccc' })
  set_ref_text(0, { 'aaa', 'ccc' })

  type_keys('G', 'gHgh')
  validate_notifications({
    { '(mini.diff) No hunk range under cursor', 'INFO' },
    { '(mini.diff) Not a proper textobject', 'INFO' },
  })
end

T['Operator']['reset']['works with different mapping'] = function()
  child.lua([[MiniDiff.setup({ source = _G.dummy_source, mappings = { reset = 'GH' } })]])

  set_lines({ 'aaa', 'bbb' })
  set_ref_text(0, { 'aaa' })

  set_cursor(2, 0)
  type_keys('GH', '_')
  eq(get_lines(), { 'aaa' })
end

T['Textobject'] = new_set()

T['Textobject']['works'] = function()
  set_lines({ 'aaa', 'uuu', 'vvv', 'bbb', 'ccc', 'www' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc' })

  set_cursor(2, 0)
  type_keys('d', 'gh')
  eq(get_lines(), { 'aaa', 'bbb', 'ccc', 'www' })
  eq(get_cursor(), { 2, 0 })

  -- With dot-repeat
  set_ref_text(0, { 'aaa', 'bbb', 'ccc' })

  set_cursor(4, 0)
  type_keys('.')
  eq(get_lines(), { 'aaa', 'bbb', 'ccc' })
  eq(get_cursor(), { 3, 0 })
end

T['Textobject']['can work in Visual mode'] = function()
  load_module({ mappings = { textobject = 'GH' } })
  set_lines({ 'aaa', 'uuu', 'vvv', 'bbb', 'ccc', 'www' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc' })

  set_cursor(2, 0)
  type_keys('v', 'GH', 'd')
  eq(get_lines(), { 'aaa', 'bbb', 'ccc', 'www' })
  eq(get_cursor(), { 2, 0 })

  -- Dot-repeat after first application in Visual mode should apply to the same
  -- relative region
  set_ref_text(0, { 'aaa', 'bbb', 'ccc' })

  set_cursor(1, 0)
  type_keys('.')
  eq(get_lines(), { 'ccc', 'www' })
  eq(get_cursor(), { 1, 0 })
end

T['Textobject']['prefers operator mappings in Visual mode'] = function()
  load_module({ mappings = { apply = 'Gh', textobject = 'Gh' } })
  expect.match(child.cmd_capture('xmap Gh'), 'Apply hunks')

  load_module({ mappings = { reset = 'GH', textobject = 'GH' } })
  expect.match(child.cmd_capture('xmap GH'), 'Reset hunks')
end

T['Textobject']['does not depend on relative position inside hunk'] = function()
  set_lines({ 'aaa', 'uuu', 'vvv', 'www', 'bbb' })
  set_ref_text(0, { 'aaa', 'bbb' })

  set_cursor(3, 0)
  type_keys('d', 'gh')
  eq(get_lines(), { 'aaa', 'bbb' })
end

T['Textobject']['works when not inside hunk range'] = function()
  set_lines({ 'aaa', 'bbb' })
  set_ref_text(0, { 'aaa' })

  set_cursor(1, 0)
  type_keys('d', 'gh')
  eq(get_lines(), { 'aaa', 'bbb' })
  validate_notifications({ { '(mini.diff) No hunk range under cursor', 'INFO' } })
end

T['Textobject']['allows dot-repeat across buffers'] = function()
  set_lines({ 'aaa', 'uuu' })
  set_ref_text(0, { 'aaa' })
  set_cursor(2, 0)
  type_keys('d', 'gh')
  eq(get_lines(), { 'aaa' })

  local new_buf_id = new_buf()
  set_buf(new_buf_id)
  set_lines({ 'bbb', 'ccc', 'vvv', 'www', 'ddd' })
  set_ref_text(0, { 'bbb', 'ccc', 'ddd' })
  set_cursor(3, 0)
  type_keys('.')
  eq(get_lines(), { 'bbb', 'ccc', 'ddd' })
end

T['Textobject']['correctly computes contiguous ranges'] = function()
  -- "Change" hunk adjacent to "add" and "delete" hunks
  set_lines({ 'AAA', 'uuu', 'BbB', 'DDD', 'www', 'EEE' })
  set_ref_text(0, { 'AAA', 'BBB', 'CCC', 'DDD', 'EEE' })
  eq(get_buf_hunks(), {
    { buf_start = 2, buf_count = 1, ref_start = 1, ref_count = 0, type = 'add' },
    { buf_start = 3, buf_count = 1, ref_start = 2, ref_count = 1, type = 'change' },
    { buf_start = 3, buf_count = 0, ref_start = 3, ref_count = 1, type = 'delete' },
    { buf_start = 5, buf_count = 1, ref_start = 4, ref_count = 0, type = 'add' },
  })

  set_cursor(3, 0)
  type_keys('d', 'gh')
  eq(get_lines(), { 'AAA', 'DDD', 'www', 'EEE' })
end

T['Textobject']['works with "delete" hunks on edges as target'] = function()
  -- First line
  set_lines({ 'bbb', 'ccc' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc' })

  set_cursor(1, 1)
  type_keys('d', 'gh')
  eq(get_lines(), { 'ccc' })
  eq(get_cursor(), { 1, 1 })

  -- Last line
  set_lines({ 'aaa', 'bbb' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc' })

  set_cursor(2, 1)
  type_keys('d', 'gh')
  eq(get_lines(), { 'aaa' })
  eq(get_cursor(), { 1, 1 })
end

T['Textobject']['works with different mapping'] = function()
  child.lua([[
    MiniDiff.setup({ source = _G.dummy_source, mappings = { textobject = 'Gh' } })
  ]])

  set_lines({ 'aaa', 'uuu', 'bbb' })
  set_ref_text(0, { 'aaa', 'bbb' })

  set_cursor(2, 0)
  type_keys('d', 'Gh')
  eq(get_lines(), { 'aaa', 'bbb' })
end

T['Textobject']['throws error in not enabled buffer'] = function()
  child.set_size(30, 80)
  child.o.cmdheight = 10
  disable()
  expect.error(function() type_keys('d', 'gh') end, 'not enabled')
end

T['Textobject']['respects `vim.{g,b}.minidiff_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child.set_size(30, 80)
    child.o.cmdheight = 10
    set_lines({ 'aaa', 'uuu' })
    set_ref_text(0, { 'aaa' })

    child[var_type].minidiff_disable = true
    disable()
    enable()
    set_cursor(2, 0)
    expect.error(function() type_keys('d', 'gh') end, 'not enabled')
  end,
})

-- More thorough tests are done in "goto_hunk"
T['Goto'] = new_set()

T['Goto']['works in Normal mode'] = function()
  set_lines({ 'uuu', 'aaa', 'vvv', 'bbb', 'www', 'ccc', 'xxx' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc' })

  local validate = function(keys, ref_cursor)
    set_cursor(4, 0)
    type_keys(keys)
    eq(get_cursor(), ref_cursor)
  end

  validate('[H', { 1, 0 })
  validate('[h', { 3, 0 })
  validate(']h', { 5, 0 })
  validate(']H', { 7, 0 })
end

T['Goto']['works in Visual mode'] = function()
  set_lines({ 'uuu', 'aaa', 'vvv', 'bbb', 'www', 'ccc', 'xxx' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc' })

  local validate = function(keys, ref_cursor)
    child.ensure_normal_mode()
    set_cursor(4, 0)
    type_keys('v', keys)
    eq(get_cursor(), ref_cursor)
    eq(child.fn.mode(), 'v')
  end

  validate('[H', { 1, 0 })
  validate('[h', { 3, 0 })
  validate(']h', { 5, 0 })
  validate(']H', { 7, 0 })
end

T['Goto']['works in Operator-pending mode'] = function()
  local validate = function(keys, ref_lines, ref_cursor)
    set_lines({ 'uuu', 'aaa', 'vvv', 'bbb', 'www', 'ccc', 'xxx' })
    set_ref_text(0, { 'aaa', 'bbb', 'ccc' })
    set_cursor(4, 1)

    -- Should operate linewise
    type_keys('d', keys)
    eq(get_lines(), ref_lines)
    eq(get_cursor(), ref_cursor)

    -- With dot-repeat
    set_lines({ 'uuu', 'aaa', 'vvv', 'bbb', 'www', 'ccc', 'xxx' })
    set_cursor(4, 1)
    type_keys('.')
    eq(get_lines(), ref_lines)
    eq(get_cursor(), ref_cursor)
  end

  validate('[H', { 'www', 'ccc', 'xxx' }, { 1, 1 })
  validate('[h', { 'uuu', 'aaa', 'www', 'ccc', 'xxx' }, { 3, 1 })
  validate(']h', { 'uuu', 'aaa', 'vvv', 'ccc', 'xxx' }, { 4, 1 })
  validate(']H', { 'uuu', 'aaa', 'vvv' }, { 3, 1 })
end

T['Goto']['allows dot-repeat across buffers'] = function()
  set_lines({ 'aaa', 'uuu', 'bbb' })
  set_ref_text(0, { 'aaa' })
  set_cursor(1, 0)
  type_keys('d', ']h')
  eq(get_lines(), { 'bbb' })

  local new_buf_id = new_buf()
  set_buf(new_buf_id)
  set_lines({ 'ccc', 'ddd', 'vvv', 'www', 'eee' })
  set_ref_text(0, { 'ccc', 'ddd', 'eee' })
  set_cursor(2, 0)
  type_keys('.')
  eq(get_lines(), { 'ccc', 'www', 'eee' })
end

T['Goto']['respects [count]'] = function()
  set_lines({ 'uuu', 'aaa', 'vvv', 'bbb', 'www', 'ccc', 'xxx' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc' })

  local validate = function(keys, ref_cursor)
    set_cursor(4, 0)
    type_keys('2', keys)
    eq(get_cursor(), ref_cursor)
  end

  validate('[H', { 3, 0 })
  validate('[h', { 1, 0 })
  validate(']h', { 7, 0 })
  validate(']H', { 5, 0 })
end

T['Goto']['respects `options.wrap_goto`'] = function()
  child.lua('MiniDiff.config.options.wrap_goto = true')

  set_lines({ 'uuu', 'aaa', 'vvv', 'bbb', 'www', 'ccc', 'xxx' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc' })

  local validate = function(keys, init_cursor, ref_cursor)
    set_cursor(unpack(init_cursor))
    type_keys(keys)
    eq(get_cursor(), ref_cursor)
  end

  validate('[h', { 1, 0 }, { 7, 0 })
  validate(']h', { 7, 0 }, { 1, 0 })

  validate('2[h', { 1, 0 }, { 5, 0 })
  validate('2]h', { 7, 0 }, { 3, 0 })

  validate('6[H', { 4, 0 }, { 3, 0 })
  validate('6]H', { 4, 0 }, { 5, 0 })
end

T['Goto']['works with different mappings'] = function()
  child.lua([[
    MiniDiff.setup({
      source = _G.dummy_source,
      mappings = {
        goto_first = '[G',
        goto_prev = '[g',
        goto_next = ']g',
        goto_last = ']G',
      }
    })
  ]])

  set_lines({ 'uuu', 'aaa', 'vvv', 'bbb', 'www', 'ccc', 'xxx' })
  set_ref_text(0, { 'aaa', 'bbb', 'ccc' })

  local validate = function(keys, ref_cursor)
    set_cursor(4, 0)
    type_keys(keys)
    eq(get_cursor(), ref_cursor)
  end

  validate('[G', { 1, 0 })
  validate('[g', { 3, 0 })
  validate(']g', { 5, 0 })
  validate(']G', { 7, 0 })
end

T['Array of sources'] = new_set()

local setup_array_sources = function(n_attach_fails, fail_delay, text_change_delay)
  child.lua('_G.n_attach_fails = ' .. (n_attach_fails or 2))
  child.lua('_G.fail_delay = ' .. (fail_delay or (2 * small_time)))
  child.lua('_G.text_change_delay = ' .. (text_change_delay or (3 * small_time)))

  child.lua([[
    _G.log = {}
    local make_source = function(id, do_attach, fail)
      return {
        name = 'Source ' .. id,
        attach = function(buf_id)
          table.insert(_G.log, 'Source ' .. id .. ' attach')
          if not do_attach() then return fail(buf_id, 'Source ' .. id) end
          MiniDiff.set_ref_text(buf_id, 'This is source ' .. id .. '\n')
          table.insert(_G.log, 'Source ' .. id .. ' attach success')
        end,
        detach = function(buf_id) table.insert(_G.log, 'Source ' .. id .. ' detach') end,
        apply_hunks = function(buf_id, hunks)
          table.insert(_G.log, 'Source ' .. id .. ' apply hunks')
          MiniDiff.set_ref_text(buf_id, 'This is source ' .. id .. '\nAfter applying hunks\n')
        end,
      }
    end

    _G.n_attach_tries = 0
    local do_attach = function()
      _G.n_attach_tries = _G.n_attach_tries + 1
      return _G.n_attach_tries > _G.n_attach_fails
    end

    local fail_now = function(_, source_name)
      table.insert(_G.log, source_name .. ' attach fail')
      return false
    end
    local fail_later = function(buf_id, source_name)
      vim.defer_fn(function()
        table.insert(_G.log, source_name .. ' attach fail')
        MiniDiff.fail_attach(buf_id)
      end, _G.fail_delay)
    end

    local source_1 = make_source(1, do_attach, fail_now)
    local source_2 = make_source(2, do_attach, fail_later)
    local source_3 = make_source(3, do_attach, fail_now)

    require('mini.diff').setup({
      -- Supplying array of sources should try to attach them in order
      source = { source_1, source_2, source_3 },
      delay = { text_change = text_change_delay },
    })
  ]])
end

T['Array of sources']['works'] = function()
  local n_attach_fails, fail_delay, text_change_delay = 2, 2 * small_time, 3 * small_time
  setup_array_sources(n_attach_fails, fail_delay, text_change_delay)

  set_buf(new_scratch_buf())
  set_lines({ 'This is' })
  enable(0)

  local ref_log = {
    -- First source fails immediately
    'Source 1 attach',
    'Source 1 attach fail',
    -- Second source delays its fail
    'Source 2 attach',
  }
  eq(child.lua_get('_G.log'), ref_log)

  -- - No source should be yet attached
  eq(get_buf_data(0).ref_text, nil)
  eq(child.b.minidiff_summary, vim.NIL)

  -- After waiting for source 2 to fail, it should attach source 3
  sleep(fail_delay + small_time)
  vim.list_extend(ref_log, { 'Source 2 attach fail', 'Source 3 attach', 'Source 3 attach success' })

  eq(child.lua_get('_G.log'), ref_log)
  eq(get_buf_data(0).ref_text, 'This is source 3\n')

  local ref_summary = { add = 0, change = 1, delete = 0, n_ranges = 1, source_name = 'Source 3' }
  eq(child.b.minidiff_summary, ref_summary)

  -- Should react to text change
  set_lines({ 'This is', 'new', 'lines' })
  sleep(text_change_delay + small_time)
  ref_summary.add = 2
  eq(child.b.minidiff_summary, ref_summary)

  -- Should use methods from proper source
  child.lua('_G.log = {}')
  do_hunks(0, 'apply')
  eq(child.lua_get('_G.log'), { 'Source 3 apply hunks' })

  child.lua('_G.log = {}')
  disable(0)
  eq(child.lua_get('_G.log'), { 'Source 3 detach' })
end

T['Array of sources']['can not attach'] = function()
  local n_attach_fails, fail_delay, text_change_delay = 4, 2 * small_time, 3 * small_time
  setup_array_sources(n_attach_fails, fail_delay, text_change_delay)

  set_buf(new_scratch_buf())
  enable(0)

  -- Should fail at all three attaches and not call any `detach`
  sleep(fail_delay + small_time)
  --stylua: ignore
  local ref_log = {
    'Source 1 attach', 'Source 1 attach fail',
    'Source 2 attach', 'Source 2 attach fail',
    'Source 3 attach', 'Source 3 attach fail',
  }
  eq(child.lua_get('_G.log'), ref_log)

  -- Should properly clean up buffer
  eq(is_buf_enabled(), false)
  eq(child.b.minidiff_summary, vim.NIL)
  eq(child.api.nvim_get_autocmds({ buffer = get_buf() }), {})

  -- Next enable should try attaching from first source
  child.lua('_G.log = {}')
  enable(0)
  sleep(fail_delay + small_time)
  ref_log = { 'Source 1 attach', 'Source 1 attach fail', 'Source 2 attach', 'Source 2 attach success' }
  eq(child.lua_get('_G.log'), ref_log)

  local ref_summary = { add = 0, change = 1, delete = 0, n_ranges = 1, source_name = 'Source 2' }
  eq(child.b.minidiff_summary, ref_summary)

  -- Should still properly track changes
  set_lines({ 'This is', 'new', 'lines' })
  sleep(text_change_delay + small_time)
  ref_summary.add = 2
  eq(child.b.minidiff_summary, ref_summary)
end

T['Array of sources']['works after `:edit`'] = function()
  local n_attach_fails, fail_delay, text_change_delay = 1, 2 * small_time, 3 * small_time
  setup_array_sources(n_attach_fails, fail_delay, text_change_delay)

  edit(test_file_path)
  sleep(text_change_delay + small_time)

  local ref_log = {
    -- First source fails immediately
    'Source 1 attach',
    'Source 1 attach fail',
    -- Second source attaches successfully (also immediately)
    'Source 2 attach',
    'Source 2 attach success',
  }
  eq(child.lua_get('_G.log'), ref_log)
  eq(get_buf_data(0).ref_text, 'This is source 2\n')

  local ref_summary = { add = 1, change = 1, delete = 0, n_ranges = 1, source_name = 'Source 2' }
  eq(child.b.minidiff_summary, ref_summary)

  -- Should try attaching from first source
  child.lua('_G.log = {}')
  child.cmd('edit')
  ref_log = { 'Source 2 detach', 'Source 1 attach', 'Source 1 attach success' }
  eq(child.lua_get('_G.log'), ref_log)

  -- Should properly track changes
  set_lines({ 'This is' })
  sleep(text_change_delay + small_time)
  ref_summary.add, ref_summary.source_name = 0, 'Source 1'
  eq(child.b.minidiff_summary, ref_summary)
end

T['Array of sources']['respects buffer-local config'] = function()
  local n_attach_fails, fail_delay, text_change_delay = 1, 2 * small_time, 3 * small_time
  setup_array_sources(n_attach_fails, fail_delay, text_change_delay)

  set_buf(new_scratch_buf())
  child.lua('vim.b.minidiff_config = { source = { MiniDiff.config.source[3], MiniDiff.config.source[2] } }')
  set_lines({ 'This is' })
  enable(0)

  local ref_log = { 'Source 3 attach', 'Source 3 attach fail', 'Source 2 attach', 'Source 2 attach success' }
  eq(child.lua_get('_G.log'), ref_log)
end

T['Array of sources']['works with built-in sources'] = function()
  mock_spawn()
  child.lua([[
    -- Fails to attach
    _G.stdio_queue = {
      { {} }, -- Get path to repo's Git dir
    }
    _G.process_mock_data = { { exit_code = 1 } }
  ]])

  local text_change_delay = 3 * small_time
  child.lua('_G.text_change_delay = ' .. text_change_delay)

  child.lua([[
    MiniDiff.config.source = { MiniDiff.gen_source.git(), MiniDiff.gen_source.save() }
    MiniDiff.config.delay.text_change = _G.text_change_delay
  ]])
  edit(git_file_path)
  local init_lines = get_lines()
  MiniTest.finally(function() child.fn.writefile(init_lines, git_file_path) end)

  eq(is_buf_enabled(0), true)
  local ref_summary_saved = { add = 0, change = 0, delete = 0, n_ranges = 0, source_name = 'save' }
  eq(child.b.minidiff_summary, ref_summary_saved)

  -- Should properly track changes
  set_lines({ 'This is' })
  sleep(text_change_delay + small_time)
  local ref_summary_modified = { add = 0, change = 1, delete = 4, n_ranges = 1, source_name = 'save' }
  eq(child.b.minidiff_summary, ref_summary_modified)

  child.cmd('write')
  eq(child.b.minidiff_summary, ref_summary_saved)
end

return T
