local helpers = dofile('tests/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('files', config) end
local unload_module = function() child.mini_unload('files') end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
local sleep = function(ms) helpers.sleep(ms, child) end
--stylua: ignore end

-- Test paths helpers
local test_dir = 'tests/dir-files'

local join_path = function(...) return table.concat({ ... }, '/') end
local full_path = function(...) return (vim.fn.fnamemodify(join_path(...), ':p'):gsub('\\', '/'):gsub('(.)/$', '%1')) end
local short_path = function(...) return (vim.fn.fnamemodify(join_path(...), ':~'):gsub('\\', '/'):gsub('(.)/$', '%1')) end

local make_test_path = function(...) return full_path(join_path(test_dir, ...)) end

local make_temp_dir = function(name, children)
  -- Make temporary directory and make sure it is removed after test is done
  local temp_dir = make_test_path(name or 'temp')
  vim.fn.mkdir(temp_dir, 'p')

  MiniTest.finally(function() vim.fn.delete(temp_dir, 'rf') end)

  -- Create children
  for _, path in ipairs(children) do
    local path_ext = temp_dir .. '/' .. path
    if vim.endswith(path, '/') then
      vim.fn.mkdir(path_ext)
    else
      vim.fn.writefile({}, path_ext)
    end
  end

  return temp_dir
end

-- Common validators and helpers
local validate_file_content = function(path, lines) eq(child.fn.readfile(path), lines) end

local validate_tree = function(dir, ref_tree)
  child.lua('_G.dir = ' .. vim.inspect(dir))
  local tree = child.lua([[
    local read_dir
    read_dir = function(path, res)
      res = res or {}
      local fs = vim.loop.fs_scandir(path)
      local name, fs_type = vim.loop.fs_scandir_next(fs)
      while name do
        local cur_path = path .. '/' .. name
        table.insert(res, cur_path .. (fs_type == 'directory' and '/' or ''))
        if fs_type == 'directory' then read_dir(cur_path, res) end
        name, fs_type = vim.loop.fs_scandir_next(fs)
      end
      return res
    end
    local dir_len = _G.dir:len()
    return vim.tbl_map(function(p) return p:sub(dir_len + 2) end, read_dir(_G.dir))
  ]])
  table.sort(tree)
  local ref = vim.deepcopy(ref_tree)
  table.sort(ref)
  eq(tree, ref)
end

local validate_cur_line = function(x) eq(get_cursor()[1], x) end

local is_explorer_active = function() return child.lua_get('MiniFiles.get_explorer_state() ~= nil') end

local validate_n_wins = function(n) eq(#child.api.nvim_tabpage_list_wins(0), n) end

local validate_fs_entry = function(x)
  eq(type(x), 'table')
  eq(x.fs_type == 'file' or x.fs_type == 'directory', true)
  eq(type(x.name), 'string')
  eq(type(x.path), 'string')
end

local validate_confirm_args = function(ref_msg_pattern, can_cancel)
  if can_cancel == nil then can_cancel = true end
  local args = child.lua_get('_G.confirm_args')
  expect.match(args[1], ref_msg_pattern)
  if args[2] ~= nil then eq(args[2], '&Yes\n&No' .. (can_cancel and '\n&Cancel' or '')) end
  if args[3] ~= nil then eq(args[3], 1) end
  if args[4] ~= nil then eq(args[4], 'Question') end
end

local make_plain_pattern = function(...) return table.concat(vim.tbl_map(vim.pesc, { ... }), '.*') end

local is_file_in_buffer = function(buf_id, path)
  return string.find(child.api.nvim_buf_get_name(buf_id):gsub('\\', '/'), vim.pesc(path:gsub('\\', '/')) .. '$') ~= nil
end

local is_file_in_window = function(win_id, path) return is_file_in_buffer(child.api.nvim_win_get_buf(win_id), path) end

-- Common test wrappers
local forward_lua = function(fun_str)
  local lua_cmd = fun_str .. '(...)'
  return function(...) return child.lua_get(lua_cmd, { ... }) end
end

local open = forward_lua('MiniFiles.open')
local close = forward_lua('MiniFiles.close')
local go_in = forward_lua('MiniFiles.go_in')
local go_out = forward_lua('MiniFiles.go_out')
local trim_left = forward_lua('MiniFiles.trim_left')
local trim_right = forward_lua('MiniFiles.trim_right')
local get_explorer_state = forward_lua('MiniFiles.get_explorer_state')
local set_bookmark = forward_lua('MiniFiles.set_bookmark')

local get_visible_paths = function()
  return vim.tbl_map(function(x) return x.path end, get_explorer_state().windows)
end

-- Extmark helper
local get_extmarks_hl = function()
  local ns_id = child.api.nvim_get_namespaces()['MiniFilesHighlight']
  local extmarks = child.api.nvim_buf_get_extmarks(0, ns_id, 0, -1, { details = true })
  return vim.tbl_map(function(x) return x[4].hl_group end, extmarks)
end

-- Common mocks
local mock_win_functions = function() child.cmd('source tests/dir-files/mock-win-functions.lua') end

local mock_confirm = function(user_choice)
  local lua_cmd = string.format(
    [[vim.fn.confirm = function(...)
        _G.confirm_args = { ... }
        return %d
      end]],
    user_choice
  )
  child.lua(lua_cmd)
end

local mock_stdpath_data = function()
  local data_dir = make_test_path('data')
  local lua_cmd = string.format(
    [[
    _G.stdpath_orig = vim.fn.stpath
    vim.fn.stdpath = function(what)
      if what == 'data' then return %s end
      return _G.stdpath_orig(what)
    end]],
    vim.inspect(data_dir)
  )
  child.lua(lua_cmd)
  return data_dir
end

-- Data =======================================================================
local test_dir_path = 'tests/dir-files/common'
local test_file_path = 'tests/dir-files/common/a-file'

local test_fs_entries = {
  -- Intentionally in proper order
  { fs_type = 'directory', name = '.a-dir', path = full_path('.a-dir') },
  { fs_type = 'directory', name = 'a-dir', path = full_path('a-dir') },
  { fs_type = 'directory', name = 'b-dir', path = full_path('b-dir') },
  { fs_type = 'file', name = '.a-file', path = full_path('.a-file') },
  { fs_type = 'file', name = 'a-file', path = full_path('a-file') },
  { fs_type = 'file', name = 'A-file-2', path = full_path('A-file-2') },
  { fs_type = 'file', name = 'b-file', path = full_path('b-file') },
}

-- Time constants
local track_lost_focus_delay = 1000
local small_time = helpers.get_time_const(10)

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      mock_win_functions()
      child.set_size(15, 80)
      load_module()

      -- Mock `vim.notify()`
      child.lua([[
        _G.notify_log = {}
        vim.notify = function(...) table.insert(_G.notify_log, { ... }) end
      ]])

      -- Make more robust screenshots
      child.o.laststatus = 0
      child.o.showtabline = 0

      -- - Hide intro
      child.cmd('vsplit')
      child.cmd('quit')
    end,
    post_case = function() vim.fn.delete(make_test_path('data'), 'rf') end,
    post_once = child.stop,
  },
  n_retry = helpers.get_n_retry(2),
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  -- Global variable
  eq(child.lua_get('type(_G.MiniFiles)'), 'table')

  -- Autocommand group
  eq(child.fn.exists('#MiniFiles'), 1)

  -- Highlight groups
  child.cmd('hi clear')
  load_module()
  local validate_hl_group = function(name, ref) expect.match(child.cmd_capture('hi ' .. name), ref) end

  validate_hl_group('MiniFilesBorder', 'links to FloatBorder')
  validate_hl_group('MiniFilesBorderModified', 'links to DiagnosticFloatingWarn')
  validate_hl_group('MiniFilesCursorLine', 'links to CursorLine')
  validate_hl_group('MiniFilesDirectory', 'links to Directory')
  eq(child.fn.hlexists('MiniFilesFile'), 1)
  validate_hl_group('MiniFilesNormal', 'links to NormalFloat')
  validate_hl_group('MiniFilesTitle', 'links to FloatTitle')
  validate_hl_group('MiniFilesTitleFocused', 'links to FloatTitle')
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniFiles.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniFiles.config.' .. field), value) end

  expect_config('content.filter', vim.NIL)
  expect_config('content.highlight', vim.NIL)
  expect_config('content.prefix', vim.NIL)
  expect_config('content.sort', vim.NIL)

  expect_config('mappings.close', 'q')
  expect_config('mappings.go_in', 'l')
  expect_config('mappings.go_in_plus', 'L')
  expect_config('mappings.go_out', 'h')
  expect_config('mappings.go_out_plus', 'H')
  expect_config('mappings.reset', '<BS>')
  expect_config('mappings.reveal_cwd', '@')
  expect_config('mappings.show_help', 'g?')
  expect_config('mappings.synchronize', '=')
  expect_config('mappings.trim_left', '<')
  expect_config('mappings.trim_right', '>')

  expect_config('options.use_as_default_explorer', true)
  expect_config('options.permanent_delete', true)

  expect_config('windows.max_number', math.huge)
  expect_config('windows.preview', false)
  expect_config('windows.width_focus', 50)
  expect_config('windows.width_nofocus', 15)
  expect_config('windows.width_preview', 25)
end

T['setup()']['respects `config` argument'] = function()
  unload_module()
  load_module({ mappings = { close = 'gc' } })
  eq(child.lua_get('MiniFiles.config.mappings.close'), 'gc')
end

T['setup()']['validates `config` argument'] = function()
  unload_module()

  local expect_config_error = function(config, name, target_type)
    expect.error(load_module, vim.pesc(name) .. '.*' .. vim.pesc(target_type), config)
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ content = 'a' }, 'content', 'table')
  expect_config_error({ content = { filter = 1 } }, 'content.filter', 'function')
  expect_config_error({ content = { highlight = 1 } }, 'content.highlight', 'function')
  expect_config_error({ content = { prefix = 1 } }, 'content.prefix', 'function')
  expect_config_error({ content = { sort = 1 } }, 'content.sort', 'function')

  expect_config_error({ mappings = 'a' }, 'mappings', 'table')
  expect_config_error({ mappings = { close = 1 } }, 'mappings.close', 'string')
  expect_config_error({ mappings = { go_in = 1 } }, 'mappings.go_in', 'string')
  expect_config_error({ mappings = { go_in_plus = 1 } }, 'mappings.go_in_plus', 'string')
  expect_config_error({ mappings = { go_out = 1 } }, 'mappings.go_out', 'string')
  expect_config_error({ mappings = { go_out_plus = 1 } }, 'mappings.go_out_plus', 'string')
  expect_config_error({ mappings = { reset = 1 } }, 'mappings.reset', 'string')
  expect_config_error({ mappings = { reveal_cwd = 1 } }, 'mappings.reveal_cwd', 'string')
  expect_config_error({ mappings = { show_help = 1 } }, 'mappings.show_help', 'string')
  expect_config_error({ mappings = { synchronize = 1 } }, 'mappings.synchronize', 'string')
  expect_config_error({ mappings = { trim_left = 1 } }, 'mappings.trim_left', 'string')
  expect_config_error({ mappings = { trim_right = 1 } }, 'mappings.trim_right', 'string')

  expect_config_error({ options = 'a' }, 'options', 'table')
  expect_config_error({ options = { use_as_default_explorer = 1 } }, 'options.use_as_default_explorer', 'boolean')
  expect_config_error({ options = { permanent_delete = 1 } }, 'options.permanent_delete', 'boolean')

  expect_config_error({ windows = 'a' }, 'windows', 'table')
  expect_config_error({ windows = { max_number = 'a' } }, 'windows.max_number', 'number')
  expect_config_error({ windows = { preview = 1 } }, 'windows.preview', 'boolean')
  expect_config_error({ windows = { width_focus = 'a' } }, 'windows.width_focus', 'number')
  expect_config_error({ windows = { width_nofocus = 'a' } }, 'windows.width_nofocus', 'number')
  expect_config_error({ windows = { width_preview = 'a' } }, 'windows.width_preview', 'number')
end

T['setup()']['ensures colors'] = function()
  child.cmd('colorscheme default')
  expect.match(child.cmd_capture('hi MiniFilesBorder'), 'links to FloatBorder')
end

T['open()'] = new_set()

T['open()']['works with directory path'] = function()
  -- Works with relative path
  open(test_dir_path)
  child.expect_screenshot()
  close()
  eq(is_explorer_active(), false)

  -- Works with absolute path
  open(vim.fn.fnamemodify(test_dir_path, ':p'))
  child.expect_screenshot()
  close()
  eq(is_explorer_active(), false)

  -- Works with trailing slash
  open(test_dir_path .. '/')
  child.expect_screenshot()
end

T['open()']['works with file path'] = function()
  -- Works with relative path
  open(test_file_path)
  -- Should focus on file entry
  child.expect_screenshot()
  close()

  -- Works with absolute path
  open(vim.fn.fnamemodify(test_file_path, ':p'))
  child.expect_screenshot()
end

T['open()']['works per tabpage'] = function()
  open(test_dir_path)
  child.expect_screenshot()

  child.cmd('tabedit')
  open(test_dir_path .. '/a-dir')
  child.expect_screenshot()

  child.cmd('tabnext')
  child.expect_screenshot()
end

T['open()']['handles problematic entry names'] = function()
  local temp_dir = make_temp_dir('temp', { '%a bad-file-name', 'a bad-dir.name/' })

  open(temp_dir)
  child.expect_screenshot()
end

T['open()']['handles backslash on Unix'] = function()
  if child.lua_get('vim.loop.os_uname().sysname') == 'Windows_NT' then MiniTest.skip('Test is not for Windows.') end

  local temp_dir = make_temp_dir('temp', { '\\', 'hello\\', 'wo\\rld' })
  open(temp_dir)
  child.expect_screenshot()
end

T['open()']['handles undo just after open'] = function()
  open(test_dir_path)
  type_keys('u')
  eq(#get_lines() > 1, true)
  eq(child.cmd_capture('1messages'), 'Already at oldest change')
end

T['open()']['uses icon provider'] = function()
  -- 'mini.icons'
  child.lua('require("mini.icons").setup()')
  open(make_test_path('real'))
  --stylua: ignore
  eq(get_extmarks_hl(), {
    'MiniIconsAzure',  'MiniFilesFile',
    'MiniIconsYellow', 'MiniFilesFile',
    'MiniIconsAzure',  'MiniFilesFile',
    'MiniIconsCyan',   'MiniFilesFile',
    'MiniIconsGrey',   'MiniFilesFile',
    'MiniIconsGrey',   'MiniFilesFile',
  })

  go_out()
  --stylua: ignore
  eq(get_extmarks_hl(), {
    'MiniIconsAzure', 'MiniFilesDirectory',
    -- 'lua' directory has special highlighting
    'MiniIconsBlue', 'MiniFilesDirectory',
    'MiniIconsAzure', 'MiniFilesDirectory',
    'MiniIconsAzure', 'MiniFilesDirectory',
    'MiniIconsAzure', 'MiniFilesFile',
    'MiniIconsAzure', 'MiniFilesFile',
  })

  child.expect_screenshot()
  close()

  -- Should still prefer 'mini.icons' if 'nvim-web-devicons' is available
  -- - Mock 'nvim-web-devicons'
  child.cmd('set rtp+=tests/dir-files')

  open(make_test_path('real'))
  child.expect_screenshot()
  close()

  -- Should fall back to 'nvim-web-devicons'
  child.lua('_G.MiniIcons = nil')

  open(make_test_path('real'))
  child.expect_screenshot()
end

T['open()']['uses `MiniIcons.get()` with full path'] = function()
  child.set_size(15, 60)
  child.lua([[vim.filetype.add({ pattern = { ['.*/common/.*%-file'] = 'make' } })]])
  child.lua('require("mini.icons").setup()')
  open(test_dir_path)
  child.expect_screenshot()
end

T['open()']['history'] = new_set()

T['open()']['history']['opens from history by default'] = function()
  open(test_dir_path)
  type_keys('j')
  go_in()
  type_keys('2j')
  child.expect_screenshot()

  close()
  eq(is_explorer_active(), false)
  open(test_dir_path)
  -- Should be exactly the same, including cursors
  child.expect_screenshot()
end

T['open()']['history']['handles external changes between calls'] = function()
  local temp_dir = make_temp_dir('temp', { 'subdir/' })

  open(temp_dir)
  go_in()
  child.expect_screenshot()

  close()
  child.fn.delete(join_path(temp_dir, 'subdir'), 'rf')
  open(temp_dir)
  child.expect_screenshot()
end

T['open()']['history']['respects `use_latest`'] = function()
  open(test_dir_path)
  type_keys('j')
  go_in()
  type_keys('2j')
  child.expect_screenshot()

  close()
  eq(is_explorer_active(), false)
  open(test_dir_path, false)
  -- Should be as if opened first time
  child.expect_screenshot()
end

T['open()']['history']['prefers global config before taking from history'] = function()
  child.lua([[
    _G.filter_starts_from_a = function(fs_entry) return vim.startswith(fs_entry.name, 'a') end
    _G.filter_starts_from_b = function(fs_entry) return vim.startswith(fs_entry.name, 'b') end
  ]])

  local lua_cmd = string.format(
    'MiniFiles.open(%s, false, { content = { filter = _G.filter_starts_from_a } })',
    vim.inspect(test_dir_path)
  )
  child.lua(lua_cmd)
  child.expect_screenshot()

  close()
  child.lua('MiniFiles.config.content.filter = _G.filter_starts_from_b')
  open(test_dir_path, true)
  child.expect_screenshot()
end

T['open()']['history']['stores whole branch and not only visible windows'] = function()
  child.set_size(15, 60)
  open(test_dir_path)
  go_in()
  child.expect_screenshot()
  close()

  child.set_size(15, 80)
  -- Should show two windows
  open(test_dir_path, true)
  child.expect_screenshot()
end

T['open()']['history']['is shared across tabpages'] = function()
  -- Prepare history
  open(test_dir_path)
  go_in()
  child.expect_screenshot()
  close()

  -- Open in new tabpage
  child.cmd('tabedit')
  open(test_dir_path, true)
  child.expect_screenshot()
  go_out()
  close()

  child.cmd('tabnext')
  open(test_dir_path, true)
  child.expect_screenshot()
end

T['open()']['history']['updates target window on every call'] = function()
  -- Prepare windows
  local win_id_1 = child.api.nvim_get_current_win()
  child.cmd('wincmd v')
  local win_id_2 = child.api.nvim_get_current_win()
  eq(win_id_1 ~= win_id_2, true)

  -- Put explorer in history which opened in current window
  open(test_file_path)
  go_in()
  close()
  eq(is_file_in_window(win_id_1, test_file_path), false)
  eq(is_file_in_window(win_id_2, test_file_path), true)

  child.api.nvim_win_set_buf(win_id_2, child.api.nvim_win_get_buf(win_id_1))

  -- New `open()` call should register new target window
  child.api.nvim_set_current_win(win_id_1)
  open(test_file_path)
  go_in()
  close()
  eq(is_file_in_window(win_id_1, test_file_path), true)
  eq(is_file_in_window(win_id_2, test_file_path), false)
end

T['open()']['focuses on file entry when opened from history'] = function()
  local path = make_test_path('common/a-dir/ab-file')

  -- If in branch, just focus on entry
  open(path)
  type_keys('j')
  go_out()
  child.expect_screenshot()

  close()
  open(path)
  child.expect_screenshot()

  -- If not in branch, reset
  go_out()
  trim_right()
  child.expect_screenshot()
  close()

  open(path)
  child.expect_screenshot()
end

T['open()']['normalizes before first refresh when focused on file'] = function()
  -- Prepare explorer state to be opened from history
  open(make_test_path('common'))
  go_in()
  eq(is_explorer_active(), true)
  close()

  -- Mock `nvim_open_win()`
  child.lua([[
    _G.init_nvim_open_win = vim.api.nvim_open_win
    _G.open_win_count = 0
    vim.api.nvim_open_win = function(...)
      _G.open_win_count = _G.open_win_count + 1
      return init_nvim_open_win(...)
    end
  ]])

  -- Test. Opening file in 'common' directory makes previous two-window view
  -- not synchronized with cursor (pointing at file while right window is for
  -- previously opened directory). Make sure that it is made one window prior
  -- to rendering, otherwise it might result in flickering.
  open(make_test_path('common/a-file'))
  child.expect_screenshot()
  eq(child.lua_get('_G.open_win_count'), 1)
end

T['open()']['normalizes before first refresh when focused on directory with `windows.preview`'] = function()
  -- Prepare explorer state to be opened from history
  open(test_dir_path)
  eq(is_explorer_active(), true)
  close()

  -- Mock `nvim_open_win()`
  child.lua([[
    _G.init_nvim_open_win = vim.api.nvim_open_win
    _G.open_win_count = 0
    vim.api.nvim_open_win = function(...)
      _G.open_win_count = _G.open_win_count + 1
      return init_nvim_open_win(...)
    end
  ]])

  -- Test. It should preview right away without extra window manipulations.
  open(test_dir_path, true, { windows = { preview = true } })
  child.expect_screenshot()
  eq(child.lua_get('_G.open_win_count'), 2)
end

T['open()']['respects `content.filter`'] = function()
  child.lua([[
    _G.filter_arg = {}
    MiniFiles.config.content.filter = function(fs_entry)
      _G.filter_arg = fs_entry

      -- Show only directories
      return fs_entry.fs_type == 'directory'
    end
  ]])

  open(test_dir_path)
  child.expect_screenshot()
  validate_fs_entry(child.lua_get('_G.filter_arg'))

  -- Local value from argument should take precedence
  child.lua([[_G.filter_starts_from_a = function(fs_entry) return vim.startswith(fs_entry.name, 'a') end ]])

  local lua_cmd = string.format(
    [[MiniFiles.open(%s, false, { content = { filter = _G.filter_starts_from_a } })]],
    vim.inspect(test_dir_path)
  )
  child.lua(lua_cmd)
  child.expect_screenshot()
end

T['open()']['respects `content.highlight`'] = function()
  child.lua([[
    _G.highlight_arg = {}
    MiniFiles.config.content.highlight = function(fs_entry)
      _G.highlight_arg = fs_entry
      -- Should use 'MiniFilesNormal' as a fallback
      return nil
    end
  ]])

  open(test_dir_path)
  child.expect_screenshot()
  validate_fs_entry(child.lua_get('_G.highlight_arg'))

  -- Local value from argument should take precedence
  child.lua([[_G.highlight_starts_from_a = function(fs_entry)
    return vim.startswith(fs_entry.name, 'a') and 'String' or 'Comment'
  end]])

  local lua_cmd = string.format(
    'MiniFiles.open(%s, false, { content = { highlight = _G.highlight_starts_from_a } })',
    vim.inspect(test_dir_path)
  )
  child.lua(lua_cmd)
  child.expect_screenshot()
end

T['open()']['respects `content.prefix`'] = function()
  child.set_size(15, 60)

  child.lua([[
    _G.prefix_arg = {}
    MiniFiles.config.content.prefix = function(fs_entry)
      _G.prefix_arg = fs_entry

      if fs_entry.fs_type == 'directory' then
        return '-', 'Comment'
      else
        return '|', 'Special'
      end
    end
  ]])

  open(test_dir_path)
  child.expect_screenshot()
  validate_fs_entry(child.lua_get('_G.prefix_arg'))

  -- Local value from argument should take precedence
  child.lua([[_G.prefix_2 = function(fs_entry) return '|', 'Special' end ]])

  local lua_cmd =
    string.format([[MiniFiles.open(%s, false, { content = { prefix = _G.prefix_2 } })]], vim.inspect(test_dir_path))
  child.lua(lua_cmd)
  child.expect_screenshot()
end

T['open()']['`content.prefix` can be used to not show prefix'] = function()
  child.lua([[MiniFiles.config.content.prefix = function() return '', '' end]])
  open(test_dir_path)
  go_in()
  child.expect_screenshot()
end

T['open()']['`content.prefix` can return `nil`'] = function()
  child.set_size(15, 60)

  local validate = function(return_expr)
    local lua_cmd = string.format([[MiniFiles.config.content.prefix = function() return %s end]], return_expr)
    child.lua(lua_cmd)
    open(test_dir_path)
    child.expect_screenshot()
    close()
  end

  validate()
  validate([['', nil]])
  validate([[nil, '']])
end

T['open()']['`content.prefix` is called only on visible part of preview'] = function()
  child.set_size(5, 100)
  child.lua([[
    MiniFiles.config.windows.preview = true

    _G.log = {}
    MiniFiles.config.content.prefix = function(fs_entry)
      table.insert(_G.log, fs_entry.name)
      return '-', 'Comment'
    end

    _G.scandir_log = {}
    fs_scandir_orig = vim.loop.fs_scandir
    vim.loop.fs_scandir = function(path)
      table.insert(_G.scandir_log, path)
      return fs_scandir_orig(path)
    end
  ]])

  local validate_log = function(ref)
    local computed_prefix = child.lua_get('_G.log')
    table.sort(computed_prefix)
    eq(computed_prefix, ref)
    child.lua('_G.log = {}')
  end

  local children = { 'dir/', 'dir/subdir/' }
  for i = 1, 6 do
    table.insert(children, 'dir/subdir/file-' .. i)
  end
  local temp_dir = make_temp_dir('temp', children)

  open(temp_dir .. '/dir')
  -- Prefix should be computed only for entries that might be visible (first
  -- vim.o.cmdheight)
  validate_log({ 'file-1', 'file-2', 'file-3', 'file-4', 'file-5', 'subdir' })

  -- Prefix should be recomputed for all entries *only* if the path is focused
  go_out()
  validate_log({ 'dir' })

  go_in()
  validate_log({})

  -- - Synchronization should also not force recomputation on **all** entries
  type_keys('o', 'new-file', '<Esc>', 'k')
  mock_confirm(1)
  child.lua('MiniFiles.synchronize()')
  validate_log({ 'dir', 'file-1', 'file-2', 'file-3', 'file-4', 'file-5', 'new-file', 'subdir' })

  child.lua('_G.scandir_log = {}')
  go_in()
  -- - Only focus should result into prefix recomputation on all entries
  validate_log({ 'file-1', 'file-2', 'file-3', 'file-4', 'file-5', 'file-6' })
  -- - Should also not result in additional disk read
  eq(child.lua_get('_G.scandir_log'), {})
end

T['open()']['respects `content.sort`'] = function()
  child.lua([[
    _G.sort_arg = {}
    MiniFiles.config.content.sort = function(fs_entries)
      _G.sort_arg = fs_entries

      -- Sort alphabetically without paying attention to file system type
      local res = vim.deepcopy(fs_entries)
      table.sort(res, function(a, b) return a.name < b.name end)
      return res
    end
  ]])

  open(test_dir_path)
  child.expect_screenshot()

  local sort_arg = child.lua_get('_G.sort_arg')
  eq(type(sort_arg), 'table')
  for _, val in pairs(sort_arg) do
    validate_fs_entry(val)
  end

  -- Local value from argument should take precedence
  child.lua([[
    _G.sort_rev_alpha = function(fs_entries)
      local res = vim.deepcopy(fs_entries)
      table.sort(res, function(a, b) return a.name > b.name end)
      return res
    end
  ]])

  local lua_cmd =
    string.format([[MiniFiles.open(%s, false, { content = { sort = _G.sort_rev_alpha } })]], vim.inspect(test_dir_path))
  child.lua(lua_cmd)
  child.expect_screenshot()
end

T['open()']['`content.sort` can be used to also filter items'] = function()
  child.lua([[
    MiniFiles.config.content.sort = function(fs_entries)
      -- Sort alphabetically without paying attention to file system type
      local res = vim.tbl_filter(function(x) return x.fs_type == 'directory' end, fs_entries)
      table.sort(res, function(a, b) return a.name > b.name end)
      return res
    end
  ]])

  open(test_dir_path)
  child.expect_screenshot()
end

T['open()']['respects `mappings`'] = function()
  child.lua([[MiniFiles.config.mappings.go_in = '<CR>']])
  open(test_dir_path)
  type_keys('<CR>')
  child.expect_screenshot()
  close()

  -- Local value from argument should take precedence
  open(test_dir_path, false, { mappings = { go_in = 'K' } })
  type_keys('K')
  child.expect_screenshot()
end

T['open()']['does not create mapping for empty string'] = function()
  local has_map = function(lhs, pattern) return child.cmd_capture('nmap ' .. lhs):find(pattern) ~= nil end

  -- Supplying empty string should mean "don't create keymap"
  child.lua('MiniFiles.config.mappings.go_in = ""')
  open()

  eq(has_map('q', 'Close'), true)
  eq(has_map('l', 'Go in'), false)
end

T['open()']['respects `windows.max_number`'] = function()
  child.lua('MiniFiles.config.windows.max_number = 1')
  open(test_dir_path)
  go_in()
  child.expect_screenshot()
  close()

  -- Local value from argument should take precedence
  open(test_dir_path, false, { windows = { max_number = 2 } })
  go_in()
  child.expect_screenshot()
end

T['open()']['respects `windows.preview`'] = function()
  child.lua('MiniFiles.config.windows.preview = true')
  open(test_dir_path)
  child.expect_screenshot()
  close()

  -- Local value from argument should take precedence
  open(test_dir_path, false, { windows = { preview = false } })
  child.expect_screenshot()
end

T['open()']['respects `windows.width_focus` and `windows.width_nofocus`'] = function()
  child.lua('MiniFiles.config.windows.width_focus = 40')
  child.lua('MiniFiles.config.windows.width_nofocus = 10')
  open(test_dir_path)
  go_in()
  child.expect_screenshot()
  close()

  -- Local value from argument should take precedence
  open(test_dir_path, false, { windows = { width_focus = 30, width_nofocus = 20 } })
  go_in()
  child.expect_screenshot()
end

T['open()']['respects `windows.width_preview`'] = function()
  child.lua('MiniFiles.config.windows.preview = true')
  child.lua('MiniFiles.config.windows.width_focus = 20')
  child.lua('MiniFiles.config.windows.width_nofocus = 10')
  child.lua('MiniFiles.config.windows.width_preview = 15')

  local test_path = make_test_path('nested')

  -- Preview window is to the right of focused one (if preview is active)
  open(test_path)
  child.expect_screenshot()
  go_in()
  child.expect_screenshot()
  go_in()
  child.expect_screenshot()
  go_out()
  child.expect_screenshot()
  go_out()
  child.expect_screenshot()

  close()

  -- Local value from argument should take precedence
  open(test_path, false, { windows = { width_focus = 20, width_preview = 30 } })
  child.expect_screenshot()
end

T['open()']['properly closes currently opened explorer'] = function()
  local path_1, path_2 = make_test_path('common'), make_test_path('common/a-dir')
  open(path_1)
  go_in()
  eq(is_explorer_active(), true)

  -- Should properly close current opened explorer (at least save to history)
  open(path_2)
  close()

  open(path_1, true)
  child.expect_screenshot()
end

T['open()']['properly closes currently opened explorer with pending file system actions'] = function()
  child.cmd('au User MiniFilesExplorerClose lua _G.had_close_event = true')
  child.set_size(100, 100)

  local path_1, path_2 = make_test_path('common'), make_test_path('common/a-dir')
  open(path_1)
  type_keys('o', 'hello')

  -- Should mention modified buffers and ask for confirmation
  mock_confirm(1)
  open(path_2)
  validate_confirm_args('pending file system actions.*Close without sync', false)

  -- Should trigger proper event for closing explorer
  eq(child.lua_get('_G.had_close_event'), true)
  close()
  child.ensure_normal_mode()

  -- Should not confirm if there are no actionable pending file system actions
  child.lua('_G.confirm_args = nil')
  open(path_1)
  type_keys('o')
  open(path_2)
  eq(child.lua_get('_G.confirm_args'), vim.NIL)
end

T['open()']['tracks lost focus'] = function()
  child.lua('MiniFiles.config.windows.preview = true')

  local validate = function(loose_focus)
    open(test_dir_path)
    child.cmd('redraw')
    loose_focus()
    -- Tracking is done by checking every second
    sleep(track_lost_focus_delay + small_time)
    eq(is_explorer_active(), false)
    eq(#child.api.nvim_list_bufs(), 1)
  end

  local init_win_id = child.api.nvim_get_current_win()
  validate(function() child.api.nvim_set_current_win(init_win_id) end)

  validate(function() child.cmd('quit') end)

  validate(function()
    go_in()
    type_keys('ZZ')
  end)

  -- Should still be possible to open same explorer afterwards
  open(test_dir_path)
  eq(is_explorer_active(), true)
end

T['open()']['can display entries with newline character'] = function()
  if helpers.is_windows() then MiniTest.skip('Newline characters in names are not supported on Windows') end
  local temp_dir = make_temp_dir('temp', { 'di\nr/', 'fi\nl\ne' })
  open(temp_dir, true, { windows = { preview = true } })
  child.expect_screenshot()
  type_keys('j')
  child.expect_screenshot()
end

T['open()']['validates input'] = function()
  -- `path` should be a real path
  expect.error(function() open('aaa') end, 'path.*not a valid path.*aaa')
end

T['open()']['respects `vim.b.minifiles_config`'] = function()
  child.lua([[_G.filter_starts_from_a = function(fs_entry) return vim.startswith(fs_entry.name, 'a') end ]])
  child.lua('vim.b.minifiles_config = { content = { filter = _G.filter_starts_from_a } }')

  open(test_dir_path)
  child.expect_screenshot()
end

T['refresh()'] = new_set()

local refresh = forward_lua('MiniFiles.refresh')

T['refresh()']['works'] = function()
  open(test_dir_path)
  refresh({ windows = { width_focus = 30 } })
  child.expect_screenshot()
end

T['refresh()']['preserves explorer options'] = function()
  open(test_dir_path, false, { windows = { width_focus = 45, width_nofocus = 10 } })
  go_in()
  child.expect_screenshot()
  -- Current explorer options should be preserved
  refresh({ windows = { width_focus = 30 } })
  child.expect_screenshot()
end

T['refresh()']['does not update buffers with `nil` `filter` and `sort`'] = function()
  local temp_dir = make_temp_dir('temp', { 'subdir/' })

  open(temp_dir)
  local buf_id_1 = child.api.nvim_get_current_buf()
  go_in()
  local buf_id_2 = child.api.nvim_get_current_buf()
  child.expect_screenshot()

  local changedtick_1 = child.api.nvim_buf_get_var(buf_id_1, 'changedtick')
  local changedtick_2 = child.api.nvim_buf_get_var(buf_id_2, 'changedtick')

  -- Should not update buffers
  refresh()
  eq(child.api.nvim_buf_get_var(buf_id_1, 'changedtick'), changedtick_1)
  eq(child.api.nvim_buf_get_var(buf_id_2, 'changedtick'), changedtick_2)

  -- Should not update even if there are external changes (there is
  -- `synchronize()` for that)
  vim.fn.mkdir(join_path(temp_dir, 'subdir', 'subsubdir'))
  refresh()
  child.expect_screenshot()
  eq(child.api.nvim_buf_get_var(buf_id_1, 'changedtick'), changedtick_1)
  eq(child.api.nvim_buf_get_var(buf_id_2, 'changedtick'), changedtick_2)
end

T['refresh()']['updates buffers with non-empty `content`'] = function()
  child.lua([[
    _G.hide_dotfiles = function(fs_entry) return not vim.startswith(fs_entry.name, '.') end
    _G.hide_prefix = function() return '', '' end
    _G.sort_rev_alpha = function(fs_entries)
      local res = vim.deepcopy(fs_entries)
      table.sort(res, function(a, b) return a.name > b.name end)
      return res
    end
  ]])

  open(test_dir_path)
  child.expect_screenshot()

  child.lua('MiniFiles.refresh({ content = { filter = _G.hide_dotfiles } })')
  child.expect_screenshot()

  child.lua('MiniFiles.refresh({ content = { prefix = _G.hide_prefix } })')
  child.expect_screenshot()

  child.lua('MiniFiles.refresh({ content = { sort = _G.sort_rev_alpha } })')
  child.expect_screenshot()
end

T['refresh()']['handles presence of pending file system actions'] = function()
  child.set_size(10, 60)
  child.lua([[_G.hide_dotfiles = function(fs_entry) return not vim.startswith(fs_entry.name, '.') end ]])

  local temp_dir = make_temp_dir('temp', { 'file', '.file' })
  open(temp_dir)

  -- On confirm should update buffers without synchronization
  type_keys('o', 'new-file', '<Esc>')
  child.expect_screenshot()

  mock_confirm(1)
  child.lua('MiniFiles.refresh({ content = { filter = _G.hide_dotfiles }, windows = { width_focus = 30 } })')
  child.expect_screenshot()

  validate_confirm_args('pending file system actions.*Update buffers without sync', false)

  -- On no confirm should not update buffers, but still apply other changes
  type_keys('o', 'new-file-2', '<Esc>')
  if child.fn.has('nvim-0.10') == 1 then child.expect_screenshot() end

  mock_confirm(2)
  child.lua('MiniFiles.refresh({ content = { filter = function() return true end }, windows = { width_focus = 15 } })')
  if child.fn.has('nvim-0.10') == 1 then child.expect_screenshot() end

  mock_confirm(1)
  close()
  child.ensure_normal_mode()

  -- Should not confirm if there are no actionable pending file system actions
  child.lua('_G.confirm_args = nil')
  open(temp_dir)
  type_keys('o')
  refresh()
  eq(child.lua_get('_G.confirm_args'), vim.NIL)
end

T['refresh()']['works when no explorer is opened'] = function() expect.no_error(refresh) end

-- More extensive testing is done in 'File manipulation'
T['synchronize()'] = new_set()

local synchronize = forward_lua('MiniFiles.synchronize')

T['synchronize()']['can update external file system changes'] = function()
  local temp_dir = make_temp_dir('temp', { 'subdir/' })

  open(temp_dir)
  validate_cur_line(1)

  vim.fn.mkdir(join_path(temp_dir, 'aaa'))
  eq(synchronize(), true)
  child.expect_screenshot()

  -- Cursor should be "sticked" to current entry
  validate_cur_line(2)
end

T['synchronize()']['can apply file system actions'] = function()
  local temp_dir = make_temp_dir('temp', {})

  open(temp_dir)
  type_keys('i', 'new-file', '<Esc>')

  mock_confirm(1)

  validate_tree(temp_dir, {})
  eq(synchronize(), true)
  validate_tree(temp_dir, { 'new-file' })
end

T['synchronize()']['can cancel synchronization'] = function()
  local temp_dir = make_temp_dir('temp', {})

  open(temp_dir)
  type_keys('i', 'new-file', '<Esc>')

  child.fn.writefile({ '' }, join_path(temp_dir, 'aaa'))

  mock_confirm(3)

  validate_tree(temp_dir, { 'aaa' })
  eq(synchronize(), false)
  -- Should not apply file system changes, not sync external changes, and keep
  -- buffers as is
  validate_tree(temp_dir, { 'aaa' })
  eq(get_lines(), { 'new-file' })
end

T['synchronize()']['should follow cursor on current entry path'] = function()
  local temp_dir = make_temp_dir('temp', { 'dir/', 'file' })

  open(temp_dir)
  type_keys('G', 'o', 'new-dir/', '<Esc>')
  type_keys('k')

  validate_cur_line(2)

  mock_confirm(1)
  synchronize()
  validate_cur_line(3)
end

T['synchronize()']['should follow cursor on new path'] = function()
  mock_confirm(1)
  local temp_dir = make_temp_dir('temp', { 'dir/' })
  open(temp_dir)

  -- File
  type_keys('O', 'new-file', '<Esc>')
  validate_cur_line(1)
  synchronize()
  validate_cur_line(2)

  -- Directory
  type_keys('o', 'new-dir/', '<Esc>')
  validate_cur_line(3)
  synchronize()
  validate_cur_line(2)

  -- Nested directories
  type_keys('o', 'a/b', '<Esc>')
  validate_cur_line(3)
  synchronize()
  validate_cur_line(1)
end

T['synchronize()']['works when no explorer is opened'] = function() expect.no_error(synchronize) end

T['reset()'] = new_set()

local reset = forward_lua('MiniFiles.reset')

T['reset()']['works'] = function()
  open(test_dir_path)
  type_keys('j')
  go_in()
  child.expect_screenshot()

  reset()
  child.expect_screenshot()
end

T['reset()']['works when anchor is not in branch'] = function()
  open(join_path(test_dir_path, 'a-dir'))
  go_out()
  type_keys('k')
  go_in()
  child.expect_screenshot()

  reset()
  if child.fn.has('nvim-0.10') == 1 then child.expect_screenshot() end
end

T['reset()']['resets all cursors'] = function()
  open(test_dir_path)
  type_keys('j')
  go_in()
  type_keys('G')
  validate_cur_line(3)

  -- Should reset cursors in both visible and invisible buffers
  go_out()
  type_keys('G')
  child.expect_screenshot()

  reset()
  child.expect_screenshot()
  type_keys('j')
  go_in()
  validate_cur_line(1)
end

T['reset()']['works when no explorer is opened'] = function() expect.no_error(reset) end

T['close()'] = new_set()

T['close()']['works'] = function()
  open(test_dir_path)
  child.expect_screenshot()

  -- Should return `true` if closing was successful
  eq(close(), true)
  child.expect_screenshot()

  -- Should close all windows and delete all buffers
  eq(is_explorer_active(), false)
  eq(#child.api.nvim_list_bufs(), 1)
end

T['close()']['works per tabpage'] = function()
  open(test_dir_path)
  child.cmd('tabedit')
  open(test_file_path)

  child.cmd('tabprev')
  close()

  -- On different tabpage explorer should still be present
  child.cmd('tabnext')
  child.expect_screenshot()
end

T['close()']['checks for pending file system actions'] = function()
  child.cmd('au User MiniFilesExplorerClose lua _G.had_close_event = true')
  open(test_dir_path)
  type_keys('o', 'new', '<Esc>')
  child.expect_screenshot()

  -- Should confirm close and do nothing if there is none (and return `false`)
  mock_confirm(2)
  eq(close(), false)
  child.expect_screenshot()
  validate_confirm_args('pending file system actions.*Close without sync', false)

  -- - Should not trigger close event (as there was no closing)
  eq(child.lua_get('_G.had_close_event'), vim.NIL)

  -- Should close if there is confirm
  mock_confirm(1)
  eq(close(), true)
  child.expect_screenshot()

  -- Should not confirm if there are no actionable pending file system actions
  child.lua('_G.confirm_args = nil')
  open(test_dir_path)
  type_keys('o')
  close()
  eq(child.lua_get('_G.confirm_args'), vim.NIL)
end

T['close()']['results into focus on target window'] = function()
  local init_win_id = child.api.nvim_get_current_win()
  child.cmd('belowright vertical split')
  local ref_win_id = child.api.nvim_get_current_win()

  open(test_dir_path)
  close()
  eq(child.api.nvim_get_current_win(), ref_win_id)

  -- Should handle non-valid target window
  open(test_dir_path)
  child.api.nvim_win_close(ref_win_id, true)
  close()
  eq(child.api.nvim_get_current_win(), init_win_id)
end

T['close()']['closes help window'] = function()
  open(test_dir_path)
  child.lua('MiniFiles.show_help()')
  validate_n_wins(3)
  close()
  validate_n_wins(1)
end

T['close()']['handles invalid target window'] = function()
  child.set_size(15, 60)

  child.cmd('wincmd v')
  local target_win_id = child.api.nvim_get_current_win()
  open(test_dir_path)
  child.expect_screenshot()
  eq(#child.api.nvim_list_wins(), 3)

  child.api.nvim_win_close(target_win_id, true)
  close()
  child.expect_screenshot()
  eq(#child.api.nvim_list_bufs(), 1)
  eq(#child.api.nvim_list_wins(), 1)
  eq(child.cmd('messages'), '')
end

T['close()']['works when no explorer is opened'] = function() eq(close(), vim.NIL) end

T['go_in()'] = new_set()

T['go_in()']['works on file'] = function()
  open(test_dir_path)
  type_keys('/', [[\.a-file]], '<CR>')
  go_in()
  close()

  expect.match(child.api.nvim_buf_get_name(0), '%.a%-file$')
  eq(get_lines(), { '.a-file' })

  -- Should open path in relative form for nicer `:buffers`
  expect.match(child.cmd_capture('buffers'):gsub('\\', '/'), '[^/]' .. vim.pesc(test_dir_path))
end

T['go_in()']['mimics empty buffer reuse'] = function()
  local validate = function(ref_n_bufs)
    open(test_dir_path)
    type_keys('/', [[\.a-file]], '<CR>')
    go_in()
    close()

    eq(#child.api.nvim_list_bufs(), ref_n_bufs)
    child.cmd('%bwipeout!')
  end

  -- Should mimic `:h buffer-reuse` similar to how `:edit` does it
  eq(child.api.nvim_get_current_buf() == 1, true)
  validate(1)

  eq(child.api.nvim_get_current_buf() ~= 1, true)
  validate(1)

  child.cmd('tabnew')
  validate(2)

  -- Should reuse only for strict set of conditions
  child.api.nvim_buf_set_name(0, 'named-buf')
  validate(2)

  child.bo.buftype = 'quickfix'
  validate(2)

  child.cmd('split')
  eq(#child.fn.win_findbuf(child.api.nvim_get_current_buf()), 2)
  validate(2)

  child.api.nvim_buf_set_lines(0, 0, -1, false, { ' ' })
  validate(2)

  child.bo.modified = true
  validate(2)
end

T['go_in()']['respects `opts.close_on_file`'] = function()
  open(test_dir_path)
  type_keys('/', [[\.a-file]], '<CR>')
  go_in({ close_on_file = true })
  expect.match(child.api.nvim_buf_get_name(0), '%.a%-file$')
  eq(get_lines(), { '.a-file' })

  eq(is_explorer_active(), false)
end

T['go_in()']['works on files with problematic names'] = function()
  local bad_name = '%a bad-file-name'
  local temp_dir = make_temp_dir('temp', { bad_name })
  child.fn.writefile({ 'aaa' }, join_path(temp_dir, bad_name))

  open(temp_dir)
  go_in()
  close()

  eq(is_file_in_buffer(0, bad_name), true)
  eq(get_lines(), { 'aaa' })
end

T['go_in()']['uses already opened listed buffer without `:edit`'] = function()
  local temp_dir = make_temp_dir('temp', { 'file' })
  local file_path = join_path(temp_dir, 'file')

  child.cmd('edit ' .. vim.fn.fnameescape(file_path))
  local buf_id = child.api.nvim_get_current_buf()
  child.fn.writefile({ 'New changes' }, file_path)

  open(temp_dir)
  go_in()
  -- If `:edit` was used, then content would have changed
  eq(child.api.nvim_buf_get_lines(buf_id, 0, -1, false), { '' })
  close(temp_dir)

  -- Should make unlisted buffer become listed
  child.cmd('bdelete ' .. buf_id)
  eq(child.api.nvim_buf_get_option(buf_id, 'buflisted'), false)

  open(temp_dir)
  go_in()
  eq(child.api.nvim_buf_get_option(buf_id, 'buflisted'), true)
end

T['go_in()']['uses proper target window'] = function()
  local win_id_1 = child.api.nvim_get_current_win()
  child.cmd('wincmd v')
  local win_id_2 = child.api.nvim_get_current_win()
  eq(win_id_1 ~= win_id_2, true)

  open(test_file_path)
  go_in()
  eq(is_file_in_window(win_id_1, test_file_path), false)
  eq(is_file_in_window(win_id_2, test_file_path), true)
end

T['go_in()']['works if target window is not valid'] = function()
  local win_id_1 = child.api.nvim_get_current_win()
  child.cmd('wincmd v')
  local win_id_2 = child.api.nvim_get_current_win()
  eq(win_id_1 ~= win_id_2, true)

  open(test_file_path)
  child.api.nvim_win_close(win_id_2, true)
  go_in()
  eq(is_file_in_window(win_id_1, test_file_path), true)
end

T['go_in()']['works on directory'] = function()
  open(test_dir_path)

  -- Should open if not already visible
  go_in()
  child.expect_screenshot()

  -- Should focus if already visible
  go_out()
  go_in()
  child.expect_screenshot()
end

T['go_in()']['works on file with newline character'] = function()
  if helpers.is_windows() then MiniTest.skip('Newline characters in names are not supported on Windows') end
  local temp_dir = make_temp_dir('temp', { 'fi\nl\ne' })
  open(temp_dir)
  go_in()
  close()
  expect.match(child.api.nvim_buf_get_name(0), 'fi\nl\ne$')
end

T['go_in()']['works when no explorer is opened'] = function() expect.no_error(go_in) end

T['go_in()']['warns about paths not present on disk'] = function()
  local validate_log = function(msg_pattern)
    local notify_log = child.lua_get('_G.notify_log')
    eq(#notify_log, 1)
    expect.match(notify_log[1][1], msg_pattern)
    eq(notify_log[1][2], child.lua_get('vim.log.levels.WARN'))
    child.lua('_G.notify_log = {}')
  end

  open(test_dir_path)

  -- Modified line without synchronization
  type_keys('O', 'new-file', '<Esc>')
  go_in()
  validate_log('Line "new%-file".*Did you modify without synchronization%?')

  -- Entry which doesn't exist on disk
  child.lua([[
    local get_fs_entry_orig = MiniFiles.get_fs_entry
    MiniFiles.get_fs_entry = function(...)
      local res = get_fs_entry_orig(...)
      res.fs_type = nil
      return res
    end
  ]])
  type_keys('j')
  go_in()
  validate_log('Path .* is not present on disk%.$')

  -- Entry with possibly miscreated symlink
  child.lua('vim.fn.resolve = function() return "miscreated-symlink" end')
  go_in()
  validate_log('Path.*is not present on disk.*miscreated symlink %(resolved to miscreated%-symlink%)')
end

T['go_out()'] = new_set()

T['go_out()']['works on not branch root'] = function()
  open(test_dir_path)
  type_keys('j')
  go_in()

  -- Should focus parent directory with cursor pointing on entry to the right
  go_out()
  child.expect_screenshot()
end

T['go_out()']['works on branch root'] = function()
  local path = make_test_path('common', 'a-dir')
  open(path)

  -- Should focus parent directory with cursor pointing on entry to the right
  -- Should also preserve visibility of current directory
  go_out()
  child.expect_screenshot()
end

T['go_out()']['root update reuses buffers without their update'] = function()
  local temp_dir = make_temp_dir('temp', { 'dir/' })
  local path = join_path(temp_dir, 'dir')

  open(path)
  child.fn.writefile({}, join_path(path, 'file'))
  go_out()
  -- Present buffer should not be updated with new file system information
  child.expect_screenshot()
end

T['go_out()']['works when no explorer is opened'] = function() expect.no_error(go_out) end

T['trim_left()'] = new_set()

T['trim_left()']['works'] = function()
  open(make_test_path('nested'))
  go_in()
  go_in()
  child.expect_screenshot()

  trim_left()
  child.expect_screenshot()
end

T['trim_left()']['works when in the middle of the branch'] = function()
  child.lua('MiniFiles.config.windows.width_focus = 20')

  open(make_test_path('nested'))
  go_in()
  go_in()
  go_out()
  child.expect_screenshot()

  trim_left()
  child.expect_screenshot()
end

T['trim_left()']['works when no explorer is opened'] = function() expect.no_error(trim_left) end

T['trim_right()'] = new_set()

T['trim_right()']['works'] = function()
  open(make_test_path('nested'))
  go_in()
  go_in()
  go_out()
  go_out()
  child.expect_screenshot()

  trim_right()
  child.expect_screenshot()
end

T['trim_right()']['works when in the middle of the branch'] = function()
  child.lua('MiniFiles.config.windows.width_focus = 20')

  open(make_test_path('nested'))
  go_in()
  go_in()
  go_out()
  child.expect_screenshot()

  trim_right()
  child.expect_screenshot()
end

T['trim_right()']['works when no explorer is opened'] = function() expect.no_error(trim_right) end

T['reveal_cwd()'] = new_set()

local reveal_cwd = forward_lua('MiniFiles.reveal_cwd')

T['reveal_cwd()']['works'] = function()
  child.set_size(10, 80)

  child.lua('MiniFiles.config.windows.width_focus = 20')
  local nested_path = make_test_path('nested')
  child.fn.chdir(nested_path)

  open(nested_path)
  go_in()
  go_in()
  trim_left()
  child.expect_screenshot()

  reveal_cwd()
  child.expect_screenshot()
end

T['reveal_cwd()']['works with preview'] = function()
  child.set_size(10, 80)

  child.lua('MiniFiles.config.windows.preview = true')
  child.lua('MiniFiles.config.windows.width_focus = 20')
  child.lua('MiniFiles.config.windows.width_preview = 10')
  local nested_path = make_test_path('nested')
  child.fn.chdir(nested_path)

  open(nested_path)
  go_in()
  go_in()
  trim_left()
  child.expect_screenshot()

  reveal_cwd()
  child.expect_screenshot()
end

T['reveal_cwd()']['works when not inside cwd'] = function()
  child.lua('MiniFiles.config.windows.width_focus = 20')
  local open_path = full_path(test_dir_path)
  local temp_dir = make_temp_dir('temp', {})
  child.fn.chdir(temp_dir)

  open(open_path)
  child.expect_screenshot()

  reveal_cwd()
  child.expect_screenshot()
end

T['reveal_cwd()']['works when root is already cwd'] = function()
  child.lua('MiniFiles.config.windows.width_focus = 20')
  local open_path = full_path(test_dir_path)
  child.fn.chdir(test_dir_path)

  open(open_path)
  child.expect_screenshot()

  reveal_cwd()
  child.expect_screenshot()
end

T['reveal_cwd()']['properly places cursors'] = function()
  child.lua('MiniFiles.config.windows.width_focus = 20')
  local temp_dir =
    make_temp_dir('temp', { 'dir-1/', 'dir-2/', 'dir-3/', 'dir-2/dir-21/', 'dir-2/dir-22/', 'dir-2/dir-23/' })
  temp_dir = full_path(temp_dir)
  child.fn.chdir(temp_dir)

  open(join_path(temp_dir, 'dir-2', 'dir-23'))
  child.expect_screenshot()

  reveal_cwd()
  child.expect_screenshot()
end

T['reveal_cwd()']['works when no explorer is opened'] = function() expect.no_error(reveal_cwd) end

T['show_help()'] = new_set()

local show_help = forward_lua('MiniFiles.show_help')

T['show_help()']['works'] = function()
  child.set_size(22, 60)
  open(test_dir_path)
  local win_id_explorer = child.api.nvim_get_current_win()

  type_keys('2j')

  show_help()
  local buf_help = child.api.nvim_get_current_buf()
  eq(child.api.nvim_buf_get_name(0), 'minifiles://' .. buf_help .. '/help')
  child.expect_screenshot()

  -- Should focus on help window
  eq(child.api.nvim_get_current_win() ~= win_id_explorer, true)

  -- Pressing `q` should close help window, delete buffer, and focus on
  -- explorer at same line
  type_keys('q')
  eq(child.api.nvim_buf_is_valid(buf_help), false)
  child.expect_screenshot()
end

T['show_help()']['opens relatively current window'] = function()
  child.set_size(22, 60)
  child.lua('MiniFiles.config.windows.width_focus = 30')

  open(test_dir_path)
  go_in()

  show_help()
  child.expect_screenshot()
end

T['show_help()']['handles non-default mappings'] = function()
  child.set_size(22, 60)
  child.lua('MiniFiles.config.mappings.go_in = ""')
  child.lua('MiniFiles.config.mappings.go_in_plus = "l"')

  open(test_dir_path)
  show_help()
  child.expect_screenshot()
end

T['show_help()']['handles mappings without description'] = function()
  child.set_size(22, 60)

  open(test_dir_path)
  child.lua([[vim.keymap.set('n', 'g.', '<Cmd>echo 1<CR>', { buffer = vim.api.nvim_get_current_buf() })]])
  show_help()
  child.expect_screenshot()
end

T['show_help()']['handles bookmarks'] = function()
  child.set_size(30, 60)
  open(test_dir_path)
  local root = full_path(test_dir)
  -- Relative (should use path as is)
  set_bookmark('a', test_dir)
  -- With description
  set_bookmark('b', root .. '/common', { desc = 'Desc' })
  -- Not normalized
  set_bookmark('~', '~')
  child.lua([[
    -- Function without description (should be called and use output)
    MiniFiles.set_bookmark('c', function() return '~/' end)
    -- Function with description
    MiniFiles.set_bookmark('d', vim.fn.getcwd, { desc = 'Cwd' })
  ]])
  -- Long description
  set_bookmark('e', root .. '/nested', { desc = 'Should use these to adjust width' })

  show_help()
  child.expect_screenshot()
end

T['show_help()']['adjusts window width'] = function()
  child.set_size(22, 60)
  child.lua('MiniFiles.config.mappings.go_in = "<C-l>"')

  open(test_dir_path)
  show_help()
  child.expect_screenshot()
end

T['show_help()']['works when no explorer is opened'] = function() expect.no_error(show_help) end

T['get_fs_entry()'] = new_set()

local get_fs_entry = forward_lua('MiniFiles.get_fs_entry')

T['get_fs_entry()']['works'] = function()
  open(test_dir_path)
  local buf_id = child.api.nvim_get_current_buf()

  -- Directory
  local dir_res = { fs_type = 'directory', name = '.a-dir', path = full_path(test_dir_path, '.a-dir') }
  eq(get_fs_entry(buf_id, 1), dir_res)

  -- - Should use current cursor line by default
  eq(get_fs_entry(), dir_res)

  -- - Should allow 0 as buffer id
  eq(get_fs_entry(0, 1), dir_res)

  -- File
  local file_res = { fs_type = 'file', name = '.a-file', path = full_path(test_dir_path, '.a-file') }
  eq(get_fs_entry(buf_id, 4), file_res)

  -- User modified line. Should return "original" entry data (as long as
  -- entry's path id is not modified)
  set_cursor(4, 0)
  type_keys('A', '111', '<Esc>')
  eq(get_fs_entry(buf_id, 4), file_res)

  -- User created line
  type_keys('o', 'new_entry', '<Esc>')
  eq(get_fs_entry(buf_id, 5), vim.NIL)
end

T['get_fs_entry()']['validates input'] = function()
  expect.error(function() get_fs_entry() end, 'buf_id.*opened directory buffer')

  open(test_dir_path)
  expect.error(function() get_fs_entry(0, 1000) end, 'line.*valid line number in buffer %d')
end

T['get_explorer_state()'] = new_set()

T['get_explorer_state()']['works'] = function()
  child.cmd('belowright vertical split')
  local ref_target_win = child.api.nvim_get_current_win()
  local anchor = full_path(test_dir_path)

  open(anchor)
  local win_1 = child.api.nvim_get_current_win()
  local path_2 = get_fs_entry().path
  go_in()
  local win_2 = child.api.nvim_get_current_win()

  set_bookmark('a', anchor, { desc = 'Anchor' })

  local ref_branch = { anchor, path_2 }
  local ref_windows = { { win_id = win_1, path = anchor }, { win_id = win_2, path = path_2 } }
  local ref_state = {
    anchor = anchor,
    bookmarks = { a = { path = anchor, desc = 'Anchor' } },
    branch = ref_branch,
    depth_focus = 2,
    target_window = ref_target_win,
    windows = ref_windows,
  }
  eq(get_explorer_state(), ref_state)
end

T['get_explorer_state()']['works with preview'] = function()
  child.lua('MiniFiles.config.windows.preview = true')
  local ref_target_win = child.api.nvim_get_current_win()
  local anchor = full_path(test_dir_path)

  open(anchor)
  local win_cur = child.api.nvim_get_current_win()
  local path_preview = get_fs_entry().path
  local win_preview
  for _, win_id in ipairs(child.api.nvim_list_wins()) do
    if win_id ~= ref_target_win and win_id ~= win_cur then win_preview = win_id end
  end

  -- Should show preview as window entry
  local ref_branch = { anchor, path_preview }
  local ref_windows = { { win_id = win_cur, path = anchor }, { win_id = win_preview, path = path_preview } }
  local ref_state = {
    anchor = anchor,
    bookmarks = {},
    branch = ref_branch,
    depth_focus = 1,
    target_window = ref_target_win,
    windows = ref_windows,
  }
  eq(get_explorer_state(), ref_state)
end

T['get_explorer_state()']['works when explorer is opened with file path'] = function()
  child.lua('MiniFiles.config.windows.preview = true')
  local file_full = full_path(test_file_path)
  local file_parent_dir = file_full:gsub('[\\/][^\\/]-$', '')

  open(file_full)
  local state = get_explorer_state()

  -- Anchor is always a directory path, parent directory of a file in this case
  eq(state.anchor, file_parent_dir)

  -- Should include file path in branch
  eq(state.branch, { file_parent_dir, file_full })
  eq(state.depth_focus, 1)

  -- Should show file preview as window entry
  eq(vim.tbl_map(function(x) return x.path end, state.windows), { file_parent_dir, file_full })
end

T['get_explorer_state()']['works when branch is not fully visible'] = function()
  child.set_size(10, 40)
  child.lua('MiniFiles.config.windows.width_focus = 35')

  local test_path = make_test_path('nested')
  open(test_path)
  go_in()
  go_in()

  local ref_branch = { test_path, test_path .. '/dir-1', test_path .. '/dir-1/dir-11' }
  local validate = function(depth_focus)
    local state = get_explorer_state()
    eq(state.branch, ref_branch)
    eq(state.depth_focus, depth_focus)
    eq(state.windows, { { win_id = child.api.nvim_get_current_win(), path = ref_branch[depth_focus] } })
  end

  validate(3)
  go_out()
  validate(2)
  go_out()
  validate(1)
end

T['get_explorer_state()']['returns copy of data'] = function()
  open(test_dir_path)
  local res = child.lua([[
    local state = MiniFiles.get_explorer_state()
    local ref = vim.deepcopy(state)
    state.bookmarks.a, state.branch[1], state.windows[1].win_id = -1, -1, -1
    local new_state = MiniFiles.get_explorer_state()
    return vim.deep_equal(new_state, ref)
  ]])
  eq(res, true)
end

T['get_explorer_state()']['works when no explorer is opened'] = function() eq(get_explorer_state(), vim.NIL) end

T['get_explorer_state()']['ensures valid target window'] = function()
  local init_win_id = child.api.nvim_get_current_win()
  child.cmd('belowright vertical split')
  local ref_win_id = child.api.nvim_get_current_win()

  open(test_dir_path)

  eq(get_explorer_state().target_window, ref_win_id)

  child.api.nvim_win_close(ref_win_id, true)
  eq(get_explorer_state().target_window, init_win_id)
end

T['set_target_window()'] = new_set()

local set_target_window = forward_lua('MiniFiles.set_target_window')

T['set_target_window()']['works'] = function()
  local init_win_id = child.api.nvim_get_current_win()
  child.cmd('belowright vertical split')
  local ref_win_id = child.api.nvim_get_current_win()

  open(test_file_path)

  eq(get_explorer_state().target_window, ref_win_id)
  set_target_window(init_win_id)
  eq(get_explorer_state().target_window, init_win_id)

  go_in()
  eq(is_file_in_buffer(child.api.nvim_win_get_buf(init_win_id), test_file_path), true)
end

T['set_target_window()']['validates input'] = function()
  open(test_dir_path)
  expect.error(function() set_target_window(1) end, 'valid window')
end

T['set_target_window()']['works when no explorer is opened'] = function()
  expect.no_error(function() set_target_window(child.api.nvim_get_current_win()) end)
end

T['set_branch()'] = new_set()

local set_branch = forward_lua('MiniFiles.set_branch')
local get_branch = function() return child.lua_get('(MiniFiles.get_explorer_state() or {}).branch') end
local get_depth_focus = function() return (get_explorer_state() or {}).depth_focus end

T['set_branch()']['works'] = function()
  child.set_size(12, 30)
  child.lua('MiniFiles.config.windows.width_focus = 20')
  child.lua('MiniFiles.config.windows.width_nofocus = 10')
  child.lua('MiniFiles.config.windows.width_preview = 15')
  open()

  local path = full_path(test_dir_path)
  set_branch({ path })
  eq(get_branch(), { path })
  eq(get_depth_focus(), 1)
  child.expect_screenshot()

  -- More than one path
  set_branch({ path, path .. '/a-dir' })
  eq(get_branch(), { path, path .. '/a-dir' })
  -- - Should set default focus on deepest directory
  eq(get_depth_focus(), 2)
  -- - Should set full branch although it might not be visible fully
  child.expect_screenshot()

  -- - Changing instance width should show more of branch
  child.set_size(12, 40)
  child.expect_screenshot()
end

T['set_branch()']['works with file path in branch'] = function()
  child.lua('MiniFiles.config.windows.width_focus = 20')
  child.lua('MiniFiles.config.windows.width_nofocus = 10')
  child.lua('MiniFiles.config.windows.width_preview = 15')
  child.set_size(12, 40)
  local anchor = child.fn.getcwd()
  open(anchor)

  local real_dir = make_test_path('real')
  set_branch({ real_dir, real_dir .. '/LICENSE' })
  -- Width of 'LICENSE' window is `width_nofocus` because preview is disabled
  child.expect_screenshot()
  -- - Should show file preview even though preview is not enabled
  eq(get_branch(), { real_dir, real_dir .. '/LICENSE' })
  -- - Should set default focus on deepest directory
  eq(get_depth_focus(), 1)
  -- - Should position cursor on child entry
  eq(get_fs_entry().name, 'LICENSE')

  close()

  -- Should use `width_preview` when preview is enabled
  child.lua('MiniFiles.config.windows.preview = true')
  open(anchor, false)
  set_branch({ real_dir, real_dir .. '/LICENSE' })
  child.expect_screenshot()
end

T['set_branch()']['works with preview'] = function()
  child.lua('MiniFiles.config.windows.width_focus = 20')
  child.lua('MiniFiles.config.windows.width_nofocus = 10')
  child.lua('MiniFiles.config.windows.width_preview = 15')
  child.set_size(12, 40)
  child.lua('MiniFiles.config.windows.preview = true')
  open()

  -- Preview should be applied after setting branch
  local path = full_path(test_dir_path)
  set_branch({ path })
  eq(get_branch(), { path, get_fs_entry().path })
  eq(get_depth_focus(), 1)
  child.expect_screenshot()
end

T['set_branch()']['works with not absolute paths'] = function()
  open()

  -- Using `~` for home directory should be allowed
  set_branch({ '~' })
  eq(get_explorer_state().branch, { full_path(child.loop.os_homedir()) })

  -- Relative paths should be resolved against current working directory
  local nested = make_test_path('nested')
  child.fn.chdir(nested)
  set_branch({ '.', './dir-1' })
  eq(get_explorer_state().branch, { nested, nested .. '/dir-1' })

  -- The ".." should also be resolved (but supported only on Neovim>=0.10)
  if child.fn.has('nvim-0.10') == 1 then
    set_branch({ '..' })
    eq(get_explorer_state().branch, { full_path(test_dir) })
  end
end

T['set_branch()']['sets cursors on child entries'] = function()
  child.set_size(12, 180)
  local root = full_path(test_dir)
  local root_parent = child.fn.fnamemodify(root, ':h')

  open(root_parent)
  local branch = { root, root .. '/nested', root .. '/nested/dir-1', root .. '/nested/dir-1/dir-12' }
  set_branch(branch)
  eq(get_branch(), branch)
  eq(get_visible_paths(), branch)

  local cursor_lines = vim.tbl_map(function(x)
    local lnum = child.api.nvim_win_get_cursor(x.win_id)[1]
    return child.fn.getbufline(child.api.nvim_win_get_buf(x.win_id), lnum)[1]:match('[\\/]([^\\/]+)$')
  end, get_explorer_state().windows)
  eq(cursor_lines, { 'nested', 'dir-1', 'dir-12', 'file-121' })
end

T['set_branch()']['respects previously set cursors'] = function()
  local nested = make_test_path('nested')
  local path = join_path(nested, 'dir-1')
  open(path)
  type_keys('G')
  eq(child.fn.line('.'), 2)

  -- Inside visible window
  go_out()
  eq(get_visible_paths(), { nested, path })
  set_branch({ path })
  eq(get_branch(), { path })
  eq(child.fn.line('.'), 2)

  -- Not inside visible window
  go_out()
  go_out()
  type_keys('j')
  eq(get_visible_paths(), { full_path(test_dir) })
  set_branch({ path })
  eq(get_branch(), { path })
  eq(child.fn.line('.'), 2)
end

T['set_branch()']['respects `opts.depth_focus`'] = function()
  open()
  local path = full_path(test_dir_path)
  local branch = { path, path .. '/a-dir', path .. '/a-dir/aa-file' }

  local validate = function(depth_focus, ref_depth_focus)
    set_branch(branch, { depth_focus = depth_focus })
    eq(get_branch(), branch)
    eq(get_depth_focus(), ref_depth_focus)
  end

  validate(1, 1)
  eq(get_fs_entry().path, path .. '/a-dir')

  -- Should normalize to fit in branch
  validate(0, 1)
  validate(-math.huge, 1)

  -- - Maximum allowed depth is the depth of deepest directory
  validate(10, 2)
  validate(math.huge, 2)

  -- - Fractional depth are allowed
  validate(1.99, 1)
end

T['set_branch()']['works when no explorer is opened'] = function() eq(set_branch(full_path(test_dir_path)), vim.NIL) end

T['set_branch()']['validates input'] = function()
  open()
  local validate = function(branch, opts, err_pattern)
    expect.error(function() set_branch(branch, opts or {}) end, err_pattern)
  end

  validate(test_dir, nil, 'array')
  validate({}, nil, 'at least one element')
  validate({ -1 }, nil, 'not string.*%-1')
  validate({ test_dir, -1 }, nil, 'not string.*%-1')

  validate({ test_dir .. '/absent' }, nil, 'not present path.*/absent')
  validate({ test_dir, test_dir .. '/absent' }, nil, 'not present path.*/absent')

  validate({ test_dir .. '/common', test_dir }, nil, 'parent%-child')
  validate({ test_dir, test_dir .. '/common/a-dir', test_dir .. '/common' }, nil, 'parent%-child')

  validate({ full_path(test_file_path) }, nil, 'one directory')
end

T['set_bookmark()'] = new_set()

T['set_bookmark()']['works'] = function()
  open()
  local root = full_path(test_dir)
  local path_a, path_A, path_b = root, root .. '/common', root .. '/lua'
  local path_c, path_d = root .. '/nested', root .. '/real'

  set_bookmark('a', path_a)
  -- Allows different cases
  set_bookmark('A', path_A)
  -- Same path under different id
  set_bookmark('x', path_a)
  -- Allows any single character
  set_bookmark('~', '~')
  -- Allows description
  set_bookmark('b', path_b, { desc = 'Path b' })

  -- Allows callable path
  child.lua([[
    local root = vim.fn.getcwd() .. '/tests/dir-files'
    MiniFiles.set_bookmark('c', function() return root .. '/nested' end)
    MiniFiles.set_bookmark('d', function() return root .. '/real' end, { desc = 'Path d' })
  ]])

  local res = child.lua([[
    local bookmarks = MiniFiles.get_explorer_state().bookmarks
    for k, v in pairs(bookmarks) do
      if vim.is_callable(v.path) then v.path = { 'Callable', (v.path():gsub('\\', '/')) } end
    end
    return bookmarks
  ]])

  local ref = {
    a = { path = path_a },
    A = { path = path_A },
    ['~'] = { path = '~' },
    b = { path = path_b, desc = 'Path b' },
    c = { path = { 'Callable', path_c } },
    d = { path = { 'Callable', path_d }, desc = 'Path d' },
    x = { path = path_a },
  }
  eq(res, ref)

  -- Can override bookmarks
  set_bookmark('a', path_b, { desc = 'Another path b' })
  eq(child.lua_get('MiniFiles.get_explorer_state().bookmarks.a'), { path = path_b, desc = 'Another path b' })
end

T['set_bookmark()']['preserves path as is'] = function()
  open()

  -- Relative path
  set_bookmark('a', test_dir)
  eq(get_explorer_state().bookmarks.a, { path = test_dir })

  -- Not normalized path
  set_bookmark('b', test_dir .. '/common/')
  eq(get_explorer_state().bookmarks.b, { path = test_dir .. '/common/' })

  -- Path with `~` for home directory
  set_bookmark('~', '~')
  eq(get_explorer_state().bookmarks['~'], { path = '~' })

  -- Callable
  child.lua('MiniFiles.set_bookmark("c", vim.fn.getcwd)')
  eq(child.lua_get('MiniFiles.get_explorer_state().bookmarks.c.path()'), child.fn.getcwd())
end

T['set_bookmark()']['persists across restart/reset'] = function()
  local path = full_path(test_dir_path)
  open(path)
  go_in()
  set_bookmark('a', path .. '/a-dir')
  local ref_bookmarks = get_explorer_state().bookmarks
  eq(ref_bookmarks.a, { path = path .. '/a-dir' })

  reset()
  eq(get_explorer_state().bookmarks, ref_bookmarks)

  -- Should preserve if opening explorer from history
  close()
  open(path, true)
  eq(get_explorer_state().bookmarks, ref_bookmarks)
  close()

  -- Should NOT preserve if opening fresh explorer
  open(path, false)
  eq(get_explorer_state().bookmarks, {})
end

T['set_bookmark()']['works when no explorer is opened'] = function() eq(set_bookmark('a', test_dir), vim.NIL) end

T['set_bookmark()']['validates input'] = function()
  open()
  local validate = function(id, path, opts, err_pattern)
    expect.error(function() set_bookmark(id, path, opts) end, err_pattern)
  end
  local path = full_path(test_dir_path)
  local path_file = full_path(test_file_path)

  validate(1, path, nil, 'id.*character')
  validate('aa', path, nil, 'id.*single')
  validate('a', 1, nil, 'path.*valid')
  validate('a', path_file, nil, 'path.*directory')
  validate('a', path, { desc = 1 }, 'description.*string')
end

T['get_latest_path()'] = new_set()

local get_latest_path = forward_lua('MiniFiles.get_latest_path')

T['get_latest_path()']['works'] = function()
  -- Initially should return `nil`
  eq(get_latest_path(), vim.NIL)

  -- Should be updated after `open`
  open(test_dir_path)
  eq(get_latest_path(), full_path(test_dir_path))

  -- Should work after `close`
  close()
  eq(get_latest_path(), full_path(test_dir_path))

  -- Should work per tabpage
  child.cmd('tabedit')
  eq(get_latest_path(), vim.NIL)

  -- Should return parent path for file path (as it is anchor path)
  local file_path = join_path(test_dir_path, 'a-file')
  open(file_path)
  eq(get_latest_path(), full_path(test_dir_path))
end

T['default_filter()'] = new_set()

local default_filter = forward_lua('MiniFiles.default_filter')

T['default_filter()']['works'] = function()
  -- Should not filter anything out
  eq(default_filter(test_fs_entries[1]), true)
end

T['default_sort()'] = new_set()

local default_sort = forward_lua('MiniFiles.default_sort')

T['default_sort()']['works'] = function()
  local t = test_fs_entries
  local fs_entries_shuffled = { t[1], t[7], t[6], t[3], t[5], t[2], t[4] }
  eq(default_sort(fs_entries_shuffled), test_fs_entries)
end

-- Integration tests ==========================================================
T['Windows'] = new_set()

T['Windows']['reuses buffers for hidden directories'] = function()
  open(test_dir_path)
  go_in()
  local buf_id_ref = child.api.nvim_get_current_buf()

  -- Open another directory at this depth
  go_out()
  type_keys('j')
  go_in()

  -- Open again initial directory at this depth. Should reuse buffer.
  go_out()
  type_keys('k')
  go_in()

  eq(child.api.nvim_get_current_buf(), buf_id_ref)
end

T['Windows']['does not wrap content'] = function()
  child.set_size(10, 20)
  child.lua('MiniFiles.config.windows.width_focus = 10')
  local temp_dir = make_temp_dir('temp', { 'a a a a a a a a a a', 'file' })

  open(temp_dir)
  child.expect_screenshot()
end

T['Windows']['correctly computes part of branch to show'] = function()
  child.set_size(10, 80)

  child.lua('MiniFiles.config.windows.width_focus = 20')
  child.lua('MiniFiles.config.windows.width_nofocus = 10')

  open(make_test_path('nested'))
  for _ = 1, 5 do
    go_in()
  end
  child.expect_screenshot()

  go_out()
  child.expect_screenshot()
  go_out()
  child.expect_screenshot()
  go_out()
  child.expect_screenshot()
  go_out()
  child.expect_screenshot()
  go_out()
  child.expect_screenshot()
end

T['Windows']['correctly computes part of branch to show with preview'] = function()
  child.set_size(10, 80)

  child.lua('MiniFiles.config.windows.preview = true')
  child.lua('MiniFiles.config.windows.width_preview = 20')
  child.lua('MiniFiles.config.windows.width_nofocus = 10')
  open(test_dir_path)
  go_in()
  child.expect_screenshot()
end

T['Windows']['is in sync with cursor'] = function()
  child.lua('MiniFiles.config.windows.width_focus = 20')
  child.lua('MiniFiles.config.windows.width_nofocus = 10')

  open(make_test_path('nested'))
  go_in()
  go_in()
  go_in()

  -- No trimming when moving left-right
  go_out()
  child.expect_screenshot()
  go_out()
  go_out()
  go_in()
  child.expect_screenshot()

  -- Trims everything to the right when going up-down
  type_keys('j')
  child.expect_screenshot()

  -- Also trims if cursor is moved in Insert mode
  go_out()
  child.expect_screenshot()
  type_keys('o')
  child.expect_screenshot()
end

T['Windows']['reacts on `VimResized`'] = function()
  open(test_dir_path)
  go_in()

  -- Decreasing width
  child.o.columns = 60
  child.expect_screenshot()

  -- Increasing width
  child.o.columns = 80
  child.expect_screenshot()

  -- Decreasing height
  child.o.lines = 8
  child.expect_screenshot()

  -- Increasing height
  child.o.lines = 15
  child.expect_screenshot()
end

T['Windows']['works with too small dimensions'] = function()
  child.set_size(8, 15)
  open(test_dir_path)
  child.expect_screenshot()
end

T['Windows']['respects tabline when computing position'] = function()
  child.o.showtabline, child.o.tabline = 2, '%#TabLineSel#My tabline%#TabLineFill#'
  open(test_dir_path)
  child.expect_screenshot()
end

T['Windows']['respects tabline and statusline when computing height'] = function()
  child.set_size(8, 60)
  child.o.tabline = '%#TabLineSel#My tabline%#TabLineFill#'
  child.o.statusline = 'My statusline'

  local validate = function()
    open(test_dir_path)
    child.expect_screenshot()
    close()
  end

  child.o.showtabline, child.o.laststatus = 2, 2
  validate()

  child.o.showtabline, child.o.laststatus = 0, 2
  validate()

  child.o.showtabline, child.o.laststatus = 2, 0
  validate()

  child.o.showtabline, child.o.laststatus = 0, 0
  validate()
end

T['Windows']['uses correct UI highlight groups'] = function()
  local validate_winhl_match = function(win_id, from_hl, to_hl)
    local winhl = child.api.nvim_win_get_option(win_id, 'winhighlight')

    -- Make sure entry is match in full
    local base_pattern = from_hl .. ':' .. to_hl
    local is_matched = winhl:find(base_pattern .. ',') ~= nil or winhl:find(base_pattern .. '$') ~= nil
    eq(is_matched, true)
  end

  open(test_dir_path)
  local win_id_1 = child.api.nvim_get_current_win()
  go_in()
  local win_id_2 = child.api.nvim_get_current_win()

  validate_winhl_match(win_id_1, 'NormalFloat', 'MiniFilesNormal')
  validate_winhl_match(win_id_1, 'FloatBorder', 'MiniFilesBorder')
  validate_winhl_match(win_id_1, 'FloatTitle', 'MiniFilesTitle')
  validate_winhl_match(win_id_1, 'CursorLine', 'MiniFilesCursorLine')
  validate_winhl_match(win_id_2, 'NormalFloat', 'MiniFilesNormal')
  validate_winhl_match(win_id_2, 'FloatBorder', 'MiniFilesBorder')
  validate_winhl_match(win_id_2, 'FloatTitle', 'MiniFilesTitleFocused')
  validate_winhl_match(win_id_2, 'CursorLine', 'MiniFilesCursorLine')

  -- Simply going in Insert mode should not add "modified"
  type_keys('i')
  validate_winhl_match(win_id_1, 'FloatBorder', 'MiniFilesBorder')
  validate_winhl_match(win_id_2, 'FloatBorder', 'MiniFilesBorder')

  type_keys('x')
  validate_winhl_match(win_id_1, 'FloatBorder', 'MiniFilesBorder')
  validate_winhl_match(win_id_2, 'FloatBorder', 'MiniFilesBorderModified')
end

T['Windows']['uses correct content highlight groups'] = function()
  open(test_dir_path)
  --stylua: ignore
  eq(
    get_extmarks_hl(),
    {
      "MiniFilesDirectory", "MiniFilesDirectory",
      "MiniFilesDirectory", "MiniFilesDirectory",
      "MiniFilesDirectory", "MiniFilesDirectory",
      "MiniFilesFile",      "MiniFilesFile",
      "MiniFilesFile",      "MiniFilesFile",
      "MiniFilesFile",      "MiniFilesFile",
      "MiniFilesFile",      "MiniFilesFile",
    }
  )
end

T['Windows']['correctly highlight content during editing'] = function()
  open(test_dir_path)
  type_keys('C', 'new-dir', '<Esc>')
  -- Highlighting of typed text should be the same as directories
  -- - Move cursor away for cursorcolumn to not obstruct the view
  type_keys('G')
  child.expect_screenshot()
end

T['Windows']['always show cursor line in directories'] = function()
  child.o.cursorline = false
  child.o.cursorlineopt = 'number'
  open(test_dir_path, false, { windows = { preview = true } })
  child.expect_screenshot()
  eq(child.wo.cursorlineopt, 'number,line')

  -- File preview should not show cursor line
  type_keys('G')
  child.expect_screenshot()
  close()

  -- Should preserve flags of 'cursorlineopt' as much as possible
  child.o.cursorlineopt = 'screenline'
  open(test_dir_path)
  eq(child.wo.cursorlineopt, 'screenline')
end

T['Windows']['can be closed manually'] = function()
  open(test_dir_path)
  type_keys('G', '<CR>')
  child.cmd('wincmd l | only')
  validate_n_wins(1)

  open(test_dir_path)
  validate_n_wins(2)

  close(test_dir_path)
  validate_n_wins(1)

  open(test_dir_path)
  child.cmd('quit!')
  validate_n_wins(1)

  open(test_dir_path)
  validate_n_wins(2)
end

T['Windows']['never shows past end of buffer'] = function()
  mock_confirm(1)

  -- Modifying buffer in Insert mode
  open(test_dir_path)
  type_keys('G', 'o')
  -- - Should increase height while first line still be visible
  child.expect_screenshot()

  child.ensure_normal_mode()
  close()

  -- Modifying buffer in Normal mode
  open(test_dir_path)
  type_keys('yj', 'G', 'p')
  child.expect_screenshot()

  close()

  -- Works when top line is not first buffer line
  child.set_size(10, 60)
  open(test_dir_path)
  type_keys('yj', 'G', 'p')
  child.expect_screenshot()
end

T['Windows']['restricts manual buffer navigation'] = function()
  if child.fn.has('nvim-0.10') == 0 then MiniTest.skip('Window and buffer pairing is available on Neovim>=0.10') end
  child.api.nvim_create_buf(true, false)
  open(test_dir_path)
  validate_n_wins(2)
  expect.error(function() child.cmd('bnext') end)
  -- Attempting to switch buffer should keep explorer usable
  expect.no_error(get_fs_entry)
end

T['Windows']["do not evaluate 'foldexpr' too much"] = function()
  if child.fn.has('nvim-0.10') == 0 then MiniTest.skip('Correct behavior is only on Neovim>=0.10') end

  child.lua('MiniFiles.config.windows.preview = true')
  child.lua([[
    _G.n = 0
    _G.foldexpr_count = function() _G.n = _G.n + 1; return 0 end
    vim.o.foldmethod = 'expr'
    vim.o.foldexpr = 'v:lua.foldexpr_count()'
  ]])
  open(test_dir_path)

  -- There still might be evaluations after `open()` because 'foldexpr' seems
  -- to be executed even if buffer is not shown in any window
  child.lua('_G.n = 0')
  type_keys('j')
  type_keys('k')
  go_in()
  go_out()
  eq(child.lua_get('_G.n'), 0)
end

T['Windows']["respect 'winborder' option"] = function()
  if child.fn.has('nvim-0.11') == 0 then MiniTest.skip("'winborder' option is present on Neovim>=0.11") end
  child.set_size(15, 40)

  child.o.winborder = 'rounded'
  open(test_dir_path)
  child.expect_screenshot()
  close()

  -- Should prefer explicitly configured value over 'winborder'
  child.lua([[
    vim.api.nvim_create_autocmd('User', {
      pattern = 'MiniFilesWindowOpen',
      callback = function(args)
        local win_id = args.data.win_id
        local config = vim.api.nvim_win_get_config(win_id)
        config.border = 'double'
        vim.api.nvim_win_set_config(win_id, config)
      end,
    })
  ]])
  open(test_dir_path)
  child.expect_screenshot()
end

T['Preview'] = new_set({
  hooks = {
    pre_case = function()
      child.lua('MiniFiles.config.windows.preview = true')
      child.lua('MiniFiles.config.windows.width_focus = 25')
    end,
  },
})

T['Preview']['works for directories'] = function()
  -- Should open preview right after `open()`
  open(test_dir_path)
  child.expect_screenshot()

  -- Should update preview after cursor move
  type_keys('j')
  child.expect_screenshot()

  -- Should open preview right after `go_in()`
  go_in()
  child.expect_screenshot()
end

T['Preview']['works for files'] = function()
  local expect_screenshot = function()
    -- Test only on Neovim>=0.10 because there was major tree-sitter update
    if child.fn.has('nvim-0.10') == 1 then child.expect_screenshot() end
  end

  open(make_test_path('real'))

  -- Should preview Lua file with highlighting
  expect_screenshot()

  -- Should preview text file (also with enabled highlighting but as there is
  -- none defined, non should be visible)
  type_keys('j')
  expect_screenshot()

  -- Should read only maximum necessary amount of lines
  local buffers = child.api.nvim_list_bufs()
  local buf_id = buffers[#buffers]
  eq(#child.api.nvim_buf_get_lines(buf_id, 0, -1, false), child.o.lines)

  -- Should not set filetype
  eq(child.api.nvim_buf_get_option(buf_id, 'filetype'), 'minifiles')

  -- Should recognize binary files and show placeholder preview
  type_keys('j')
  expect_screenshot()

  -- Should work for empty files
  type_keys('j')
  expect_screenshot()

  -- Should fall back to built-in syntax highlighting in case of no tree-sitter
  type_keys('j')
  expect_screenshot()

  -- Should not error on files which failed to read (looks like on Windows it
  -- can be different from "non-readable" files)
  child.lua('vim.loop.fs_open = function() return nil end')
  type_keys('j')
  expect_screenshot()
end

T['Preview']['works with imaginary paths'] = function()
  child.set_size(15, 60)
  local temp_dir = make_temp_dir('temp', {})
  open(temp_dir)

  -- Should show preview for empty line
  child.expect_screenshot()

  -- Should still show preview window for files not (yet) on disk
  type_keys('o')
  child.expect_screenshot()
  type_keys('n')
  child.expect_screenshot()
  -- Should update title as user types
  type_keys('e')
  child.expect_screenshot()
  type_keys('w/')

  -- Should update the title even if popup menu is shown
  child.o.completeopt = 'menuone,noselect'
  type_keys('<CR>', 'n', '<C-n>')
  eq(child.fn.pumvisible() == 1, true)
  type_keys('e')
  child.expect_screenshot()

  -- Should treat non-empty blank line as new file name
  type_keys('<Esc>', 'o', ' ')
  child.expect_screenshot()
  type_keys('<C-u>', '<Esc>')

  -- Should properly update to existing file preview after synchronization
  mock_confirm(1)
  synchronize()
  validate_tree(temp_dir, { 'new/', 'ne' })
  child.expect_screenshot()
  type_keys('j')
  child.expect_screenshot()
end

T['Preview']['does not highlight big files'] = function()
  local big_file = make_test_path('big.lua')
  MiniTest.finally(function() child.fn.delete(big_file, 'rf') end)

  -- Has limit per line
  child.fn.writefile({ string.format('local a = "%s"', string.rep('a', 1000)) }, big_file)
  open(big_file)
  -- NOTE: there is no visible right pad because it got truncated by Neovim,
  -- as 'MOCK_ROOT' doesn't account for initial truncation from left
  child.expect_screenshot()
  close()

  -- It also should have total limit, but it is not tested to not overuse file
  -- system accesses during test
end

T['Preview']['is not removed when going out'] = function()
  child.lua('MiniFiles.config.windows.width_focus = 15')
  child.lua('MiniFiles.config.windows.width_preview = 15')

  open(test_dir_path)

  -- Directory preview
  type_keys('j')
  go_in()
  go_out()
  child.expect_screenshot()

  -- File preview
  go_in()
  go_in()
  go_out()
  go_out()
  child.expect_screenshot()
end

T['Preview']['reuses buffers'] = function()
  -- Show two previews (for directory and file) and hide them
  open(test_dir_path)
  type_keys('G')
  go_out()
  local all_buffers = child.api.nvim_list_bufs()
  trim_left()

  -- Show them again which should use same buffers
  go_in()
  type_keys('gg')
  eq(all_buffers, child.api.nvim_list_bufs())
end

T['Preview']['is not shown if not enough space'] = function()
  child.lua('MiniFiles.config.windows.width_focus = 50')
  child.set_size(15, 60)
  open(test_dir_path)
  child.expect_screenshot()
end

T['Preview']['previews only one level deep'] = function()
  child.set_size(10, 80)

  open(make_test_path('nested'))
  child.expect_screenshot()
end

T['Preview']['works after `trim_left()`'] = function()
  child.set_size(10, 80)

  open(make_test_path('nested'))
  go_in()
  trim_left()
  type_keys('j')
  child.expect_screenshot()
end

T['Preview']['does not result in flicker'] = function()
  child.lua('MiniFiles.config.windows.width_focus = 50')
  -- Exact width is important: it is just enough to fit focused (52) and two
  -- non-focused (17+17) windows which was the computed visible range range
  child.set_size(10, 86)
  child.lua([[
    _G.get_visible_bufs = function()
      local res = {}
      for _, win_id in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        table.insert(res, vim.api.nvim_win_get_buf(win_id))
      end
      table.sort(res)
      return res
    end
  ]])

  open(test_dir)
  child.lua([[
    MiniFiles.go_in()
    MiniFiles.go_in()
    _G.visible_bufs = _G.get_visible_bufs()
  ]])

  -- State shown initially should be the same as after some time has passed
  sleep(small_time)
  eq(child.lua_get('_G.visible_bufs'), child.lua_get('_G.get_visible_bufs()'))
end

T['Preview']['always updates with cursor'] = function()
  child.lua('MiniFiles.config.windows.width_focus = 50')
  -- Exact width is important: it is just enough to fit focused (52) and two
  -- non-focused (17+17) windows which was the computed visible range range
  child.set_size(10, 86)
  open(test_dir)
  go_in()
  go_in()
  type_keys('j')
  child.expect_screenshot()
end

T['Preview']['can work after renaming with small overall width'] = function()
  child.lua('MiniFiles.config.windows.width_focus = 20')
  child.lua('MiniFiles.config.windows.width_preview = 15')
  child.lua('MiniFiles.config.windows.width_nofocus = 10')
  child.set_size(10, 54)

  local temp_dir = make_temp_dir('temp', { 'dir/', 'dir/nested/', 'dir/nested/nested-2/', 'dir/nested/nested-2/file' })
  open(temp_dir)
  go_in()
  go_in()
  go_in()
  type_keys('C', 'new-file', '<Esc>')
  -- - At this point there is a preview active but for a path with soon to be
  --   outdated basename
  child.expect_screenshot()

  mock_confirm(1)
  synchronize()
  child.expect_screenshot()
end

T['Mappings'] = new_set()

T['Mappings']['`close` works'] = function()
  -- Default
  open(test_dir_path)
  eq(is_explorer_active(), true)
  type_keys('q')
  eq(is_explorer_active(), false)
  close()

  -- User-supplied
  open(test_dir_path, false, { mappings = { close = 'Q' } })
  eq(is_explorer_active(), true)
  type_keys('Q')
  eq(is_explorer_active(), false)
  close()

  -- Empty
  open(test_dir_path, false, { mappings = { close = '' } })
  eq(is_explorer_active(), true)
  -- - Needs second `q` to unblock child process after built-in `q`
  type_keys('q', 'q')
  eq(is_explorer_active(), true)
end

T['Mappings']['`go_in` works'] = function()
  -- Default
  open(test_dir_path)
  validate_n_wins(2)
  type_keys('l')
  child.expect_screenshot()
  close()

  -- User-supplied
  open(test_dir_path, false, { mappings = { go_in = 'Q' } })
  validate_n_wins(2)
  type_keys('Q')
  validate_n_wins(3)
  close()

  -- Empty
  open(test_dir_path, false, { mappings = { go_in = '' } })
  validate_n_wins(2)
  type_keys('l')
  validate_n_wins(2)
end

T['Mappings']['`go_in` works in linewise Visual mode'] = function()
  local has_opened_buffer = function(name)
    local path = join_path(test_dir_path, name)
    for _, buf_id in ipairs(child.api.nvim_list_bufs()) do
      if is_file_in_buffer(buf_id, path) then return true end
    end
    return false
  end

  -- Should open all files
  open(test_dir_path)
  set_cursor(4, 0)
  type_keys('V', '2j')

  type_keys('l')
  eq(has_opened_buffer('.a-file'), true)
  eq(has_opened_buffer('a-file'), true)
  eq(has_opened_buffer('A-file-2'), true)
  -- - Should go back in Normal mode
  eq(child.fn.mode(), 'n')

  -- Should go in only last directory with cursor moved to its entry
  set_cursor(3, 0)
  type_keys('V', 'k')
  child.expect_screenshot()

  type_keys('l')
  child.expect_screenshot()
  eq(child.fn.mode(), 'n')

  -- Should work when selection contains both files and directories
  -- Cursor in initial window still should be moved to target entry
  close()
  child.cmd('%bwipeout')

  open(test_dir_path, false)
  set_cursor(3, 0)
  type_keys('V', 'j')

  type_keys('l')
  child.expect_screenshot()
  eq(has_opened_buffer('.a-file'), true)
  eq(child.fn.mode(), 'n')
end

T['Mappings']['`go_in` ignores non-linewise Visual mode'] = function()
  local validate = function(mode_key)
    open(test_dir_path, false)
    validate_n_wins(2)

    type_keys(mode_key, 'l')
    validate_n_wins(2)
    eq(child.fn.mode(), mode_key)

    child.ensure_normal_mode()
    close()
  end

  validate('v')
  -- '\22' is an escaped version of `<C-v>`
  validate('\22')
end

T['Mappings']['`go_in` supports <count>'] = function()
  child.set_size(15, 60)
  child.lua('MiniFiles.config.windows.width_focus = 20')
  child.lua('MiniFiles.config.windows.width_nofocus = 10')

  open(make_test_path('nested'))
  type_keys('2l')
  child.expect_screenshot()

  close()

  -- Works with high values ending at file
  open(test_dir_path)
  type_keys('10l')
  child.expect_screenshot()
end

T['Mappings']['`go_in_plus` works'] = function()
  -- On directories should be the same as `go_in`
  -- Default
  open(test_dir_path)
  validate_n_wins(2)
  type_keys('L')
  child.expect_screenshot()
  close()

  -- User-supplied
  open(test_dir_path, false, { mappings = { go_in_plus = 'Q' } })
  validate_n_wins(2)
  type_keys('Q')
  validate_n_wins(3)
  close()

  -- Empty
  open(test_dir_path, false, { mappings = { go_in_plus = '' } })
  validate_n_wins(2)
  type_keys('L')
  validate_n_wins(2)
end

T['Mappings']['`go_in_plus` works on files'] = function()
  open(test_file_path)
  validate_n_wins(2)

  -- Should open file and close explorer
  type_keys('L')
  validate_n_wins(1)
  eq(is_file_in_buffer(0, test_file_path), true)
end

T['Mappings']['`go_in_plus` works on non-path entry'] = function()
  local temp_dir = make_temp_dir('temp', {})
  open(temp_dir)

  -- Empty line
  type_keys('L')
  eq(child.api.nvim_get_mode().blocking, false)

  -- Non-empty line
  type_keys('i', 'new-entry', '<Esc>')
  type_keys('L')
  eq(child.api.nvim_get_mode().blocking, false)
end

T['Mappings']['`go_in_plus` supports <count>'] = function()
  child.set_size(10, 50)
  child.lua('MiniFiles.config.windows.width_focus = 20')
  child.lua('MiniFiles.config.windows.width_nofocus = 10')

  open(make_test_path('nested'))
  type_keys('2L')
  child.expect_screenshot()

  close()

  -- Works with high values ending at file
  local temp_dir = make_temp_dir('temp', { 'file' })
  child.fn.writefile({ 'Temp file' }, join_path(temp_dir, 'file'))
  open(temp_dir)
  type_keys('10L')
  child.expect_screenshot()
end

T['Mappings']['`go_out` works'] = function()
  local path = make_test_path('common', 'a-dir')

  -- Default
  open(path)
  validate_n_wins(2)
  type_keys('h')
  child.expect_screenshot()
  close()

  -- User-supplied
  open(path, false, { mappings = { go_out = 'Q' } })
  validate_n_wins(2)
  type_keys('Q')
  validate_n_wins(3)
  close()

  -- Empty
  open(path, false, { mappings = { go_out = '' } })
  validate_n_wins(2)
  type_keys('h')
  validate_n_wins(2)
end

T['Mappings']['`go_out` supports <count>'] = function()
  child.set_size(10, 70)
  child.lua('MiniFiles.config.windows.width_focus = 20')
  child.lua('MiniFiles.config.windows.width_nofocus = 10')

  open(make_test_path('nested', 'dir-1', 'dir-11'))
  go_in()
  go_in()
  child.expect_screenshot()

  type_keys('2h')
  child.expect_screenshot()
  type_keys('2h')
  child.expect_screenshot()
end

T['Mappings']['`go_out_plus` works'] = function()
  local path = make_test_path('common', 'a-dir')

  -- Default
  open(path)
  validate_n_wins(2)
  type_keys('H')
  child.expect_screenshot()
  close()

  -- User-supplied
  open(path, false, { mappings = { go_out_plus = 'Q' } })
  validate_n_wins(2)
  type_keys('Q')
  child.expect_screenshot()
  close()

  -- Empty
  open(path, false, { mappings = { go_out_plus = '' } })
  validate_n_wins(2)
  type_keys('H')
  child.expect_screenshot()
end

T['Mappings']['`go_out_plus` supports <count>'] = function()
  child.set_size(10, 70)
  child.lua('MiniFiles.config.windows.width_focus = 20')
  child.lua('MiniFiles.config.windows.width_nofocus = 10')

  open(make_test_path('nested', 'dir-1', 'dir-11'))
  go_in()
  go_in()
  child.expect_screenshot()

  type_keys('2H')
  child.expect_screenshot()
  type_keys('2H')
  child.expect_screenshot()
end

T['Mappings']['`mark_goto` works'] = function()
  local validate_log = function(ref_log)
    eq(child.lua_get('_G.notify_log'), ref_log)
    child.lua('_G.notify_log = {}')
  end
  local warn_level = child.lua_get('vim.log.levels.WARN')

  local path = full_path(test_dir_path)
  local mark_path = path .. '/a-dir'
  open(path)
  set_bookmark('a', mark_path)
  go_out()
  expect.no_equality(get_branch(), { mark_path })
  type_keys("'", 'a')
  eq(get_branch(), { mark_path })
  -- - Should show no notifications
  validate_log({})

  -- Warns about not existing bookmark id
  go_out()
  local ref_branch = get_branch()
  type_keys("'", 'x')
  eq(get_branch(), ref_branch)
  validate_log({ { '(mini.files) No bookmark with id "x"', warn_level } })

  -- Does nothing (silently) after `<Esc>` or `<C-c>`
  type_keys("'", '<Esc>')
  eq(get_branch(), ref_branch)
  validate_log({})
  type_keys("'", '<C-c>')
  eq(get_branch(), ref_branch)
  validate_log({})

  close()

  -- User-supplied
  open(path, false, { mappings = { mark_goto = '`' } })
  set_bookmark('a', mark_path)
  go_out()
  type_keys('`', 'a')
  eq(get_branch(), { mark_path })
  close()

  -- Empty
  open(path, false, { mappings = { mark_goto = '' } })
  set_bookmark('a', mark_path)
  go_out()
  expect.error(function() type_keys("'", 'a') end, 'E20')
end

T['Mappings']["`mark_goto` automatically sets `'` bookmark"] = function()
  local get_cur_path = function()
    local state = get_explorer_state()
    return state.branch[state.depth_focus]
  end

  local path = full_path(test_dir_path)
  local mark_path = path .. '/a-dir'
  open(path)
  set_bookmark('a', mark_path)

  go_out()
  local path_before_jump = get_cur_path()
  eq(get_explorer_state().bookmarks["'"], nil)
  type_keys("'", 'a')
  eq(get_branch(), { mark_path })
  eq(get_explorer_state().bookmarks["'"], { desc = 'Before latest jump', path = path_before_jump })

  type_keys("'", "'")
  eq(get_branch(), { path_before_jump })
  eq(get_explorer_state().bookmarks["'"], { desc = 'Before latest jump', path = mark_path })
end

T['Mappings']['`mark_goto` works with special paths'] = function()
  local validate_log = function(ref_log)
    eq(child.lua_get('_G.notify_log'), ref_log)
    child.lua('_G.notify_log = {}')
  end
  local warn_level = child.lua_get('vim.log.levels.WARN')
  local cwd = child.fn.getcwd():gsub('\\', '/')

  local path = full_path(test_dir_path)
  open(path)

  -- Relative paths (should be resolved against cwd, not currently focused)
  local path_rel = test_dir_path .. '/a-dir'
  set_bookmark('a', path_rel)
  type_keys("'", 'a')
  eq(get_branch(), { full_path(path_rel) })

  -- Involving '~'
  set_bookmark('~', '~')
  type_keys("'", '~')
  expect.no_equality(get_branch(), { full_path(path_rel) })
  validate_log({})

  -- Function paths
  child.lua([[MiniFiles.set_bookmark('b', vim.fn.getcwd)]])
  type_keys("'", 'b')
  eq(get_branch(), { cwd })

  -- Not existing on disk
  child.lua([[MiniFiles.set_bookmark('c', function() return vim.fn.getcwd() .. '/not-present' end)]])
  type_keys("'", 'c')
  eq(get_branch(), { cwd })
  validate_log({ { '(mini.files) Bookmark path should be a valid path to directory', warn_level } })

  -- Not directory path
  child.lua('_G.file_path = ' .. vim.inspect(full_path(test_file_path)))
  child.lua([[MiniFiles.set_bookmark('d', function() return _G.file_path end)]])
  type_keys("'", 'd')
  eq(get_branch(), { cwd })
  validate_log({ { '(mini.files) Bookmark path should be a valid path to directory', warn_level } })
end

T['Mappings']['`mark_set` works'] = function()
  local path = full_path(test_dir_path)
  open(path)
  local mark_path = get_fs_entry().path
  go_in()
  type_keys('m', 'a')
  local ref_bookmarks = { a = { path = mark_path } }
  eq(get_explorer_state().bookmarks, ref_bookmarks)

  -- - Should show notification
  local info_level = child.lua_get('vim.log.levels.INFO')
  eq(child.lua_get('_G.notify_log'), { { '(mini.files) Bookmark "a" is set', info_level } })

  -- Does nothing after `<Esc>` or `<C-c>`
  type_keys('m', '<Esc>')
  eq(get_explorer_state().bookmarks, ref_bookmarks)
  type_keys('m', '<C-c>')
  eq(get_explorer_state().bookmarks, ref_bookmarks)

  close()

  -- User-supplied
  open(path, false, { mappings = { mark_set = 'M' } })
  go_in()
  type_keys('M', 'a')
  eq(get_explorer_state().bookmarks, ref_bookmarks)
  close()

  -- Empty
  open(path, false, { mappings = { mark_set = '' } })
  go_in()
  type_keys('m', 'a')
  eq(get_explorer_state().bookmarks, {})
end

T['Mappings']['`reset` works'] = function()
  local prepare = function(...)
    close()
    open(...)
    type_keys('j')
    go_in()
    validate_n_wins(3)
  end

  -- Default
  prepare(test_dir_path)
  type_keys('<BS>')
  child.expect_screenshot()

  -- User-supplied
  prepare(test_dir_path, false, { mappings = { reset = 'Q' } })
  type_keys('Q')
  child.expect_screenshot()

  -- Empty
  prepare(test_dir_path, false, { mappings = { reset = '' } })
  type_keys('<BS>')
  child.expect_screenshot()
end

T['Mappings']['`reveal_cwd` works'] = function()
  child.set_size(10, 80)

  child.lua('MiniFiles.config.windows.width_focus = 20')
  local nested_path = make_test_path('nested')
  child.fn.chdir(nested_path)

  local prepare = function(...)
    close()
    open(...)
    go_in()
    go_in()
    trim_left()
  end

  -- Default
  prepare(nested_path)
  type_keys('@')
  child.expect_screenshot()

  -- User-supplied
  prepare(nested_path, false, { mappings = { reveal_cwd = 'Q' } })
  type_keys('Q')
  child.expect_screenshot()

  -- Empty
  prepare(nested_path, false, { mappings = { reveal_cwd = '' } })
  -- - Follow up `@` with register name to avoid blocking child process
  type_keys('@', 'a')
  child.expect_screenshot()
end

T['Mappings']['`show_help` works'] = function()
  child.set_size(22, 60)

  -- Default
  open(test_dir_path)
  type_keys('g?')
  child.expect_screenshot()
  type_keys('q')
  close()

  -- User-supplied
  open(test_dir_path, false, { mappings = { show_help = 'Q' } })
  type_keys('Q')
  child.expect_screenshot()
  type_keys('q')
  close()

  -- Empty
  open(test_dir_path, false, { mappings = { show_help = '' } })
  type_keys('g?')
  child.expect_screenshot()
end

T['Mappings']['`synchronize` works'] = function()
  child.set_size(10, 60)

  local temp_dir = make_temp_dir('temp', {})
  local validate = function(file_name, key)
    child.expect_screenshot()
    child.fn.writefile({}, join_path(temp_dir, file_name))
    type_keys(key)
    child.expect_screenshot()
  end

  -- Default
  open(temp_dir)
  validate('file-1', '=')
  close()

  -- User-supplied
  open(temp_dir, false, { mappings = { synchronize = 'Q' } })
  validate('file-2', 'Q')
  close()

  -- Empty
  open(temp_dir, false, { mappings = { synchronize = '' } })
  validate('file-3', '=')
end

T['Mappings']['`trim_left` works'] = function()
  -- Default
  open(test_dir_path)
  go_in()
  validate_n_wins(3)
  type_keys('<')
  child.expect_screenshot()
  close()

  -- User-supplied
  open(test_dir_path, false, { mappings = { trim_left = 'Q' } })
  go_in()
  validate_n_wins(3)
  type_keys('Q')
  validate_n_wins(2)
  close()

  -- Empty
  open(test_dir_path, false, { mappings = { trim_left = '' } })
  go_in()
  validate_n_wins(3)
  type_keys('<')
  validate_n_wins(3)
end

T['Mappings']['`trim_right` works'] = function()
  local path = make_test_path('common', 'a-dir')

  -- Default
  open(path)
  go_out()
  validate_n_wins(3)
  type_keys('>')
  child.expect_screenshot()
  close()

  -- User-supplied
  open(path, false, { mappings = { trim_right = 'Q' } })
  go_out()
  validate_n_wins(3)
  type_keys('Q')
  validate_n_wins(2)
  close()

  -- Empty
  open(path, false, { mappings = { trim_right = '' } })
  go_out()
  validate_n_wins(3)
  type_keys('>')
  validate_n_wins(3)
end

T['File manipulation'] = new_set()

T['File manipulation']['can create'] = function()
  child.set_size(10, 60)
  local temp_dir = make_temp_dir('temp', {})
  open(temp_dir)

  set_lines({ 'new-file', 'new-dir/' })
  set_cursor(1, 0)
  child.expect_screenshot()

  mock_confirm(1)
  synchronize()
  child.expect_screenshot()

  validate_tree(temp_dir, { 'new-file', 'new-dir/' })

  local ref_pattern = make_plain_pattern('CONFIRM FILE SYSTEM ACTIONS', short_path(temp_dir) .. '\n')
  validate_confirm_args(ref_pattern)
  validate_confirm_args('  CREATE │ new%-file %(file%)')
  validate_confirm_args('  CREATE │ new%-dir %(directory%)')
end

T['File manipulation']['create does not override existing entry'] = function()
  child.set_size(10, 60)

  local temp_dir = make_temp_dir('temp', { 'file', 'dir/', 'dir/subfile' })
  local file_path = join_path(temp_dir, 'file')
  child.fn.writefile({ 'File' }, file_path)

  open(temp_dir)
  type_keys('o', 'file', '<CR>', 'dir/', '<Esc>')
  child.expect_screenshot()

  mock_confirm(1)
  synchronize()
  child.expect_screenshot()

  validate_tree(temp_dir, { 'dir/', 'dir/subfile', 'file' })
  validate_file_content(file_path, { 'File' })

  -- Should show warning
  local warn_level = child.lua_get('vim.log.levels.WARN')
  local ref_log = {
    { '(mini.files) Can not create ' .. file_path .. '. Target path already exists.', warn_level },
    { '(mini.files) Can not create ' .. temp_dir .. '/dir/. Target path already exists.', warn_level },
  }
  eq(child.lua_get('_G.notify_log'), ref_log)
end

T['File manipulation']['creates files in nested directories'] = function()
  child.set_size(10, 60)
  local temp_dir = make_temp_dir('temp', { 'dir/' })
  open(temp_dir)

  local lines = get_lines()
  -- Should work both in present directories and new ones (creating them)
  lines = vim.list_extend(lines, { 'dir/nested-file', 'dir-1/nested-file-1', 'dir-1/nested-file-2' })
  set_lines(lines)
  child.expect_screenshot()

  mock_confirm(1)
  synchronize()
  child.expect_screenshot()

  validate_tree(temp_dir, { 'dir/', 'dir/nested-file', 'dir-1/', 'dir-1/nested-file-1', 'dir-1/nested-file-2' })

  -- Validate separately because order is not guaranteed
  local ref_pattern = make_plain_pattern('CONFIRM FILE SYSTEM ACTIONS', short_path(temp_dir) .. '\n')
  validate_confirm_args(ref_pattern)

  -- - Should show paths relative to directory where manipulation was registered
  validate_confirm_args('  CREATE │ dir/nested%-file %(file%)')
  validate_confirm_args('  CREATE │ dir%-1/nested%-file%-1 %(file%)')
  validate_confirm_args('  CREATE │ dir%-1/nested%-file%-2 %(file%)')
end

T['File manipulation']['creates nested directories'] = function()
  child.set_size(10, 60)
  local temp_dir = make_temp_dir('temp', { 'dir/' })
  open(temp_dir)

  local lines = get_lines()
  -- Should work both in present directories and new ones (creating them)
  lines = vim.list_extend(lines, { 'dir/nested-dir/', 'dir-1/nested-dir-1/', 'dir-1/nested-dir-2/' })
  set_lines(lines)
  child.expect_screenshot()

  mock_confirm(1)
  synchronize()
  child.expect_screenshot()

  validate_tree(temp_dir, { 'dir/', 'dir/nested-dir/', 'dir-1/', 'dir-1/nested-dir-1/', 'dir-1/nested-dir-2/' })

  -- Validate separately because order is not guaranteed
  local ref_pattern = make_plain_pattern('CONFIRM FILE SYSTEM ACTIONS', short_path(temp_dir) .. '\n')
  validate_confirm_args(ref_pattern)

  -- - Should show paths relative to directory where manipulation was registered
  validate_confirm_args('  CREATE │ dir/nested%-dir %(directory%)')
  validate_confirm_args('  CREATE │ dir%-1/nested%-dir%-1 %(directory%)')
  validate_confirm_args('  CREATE │ dir%-1/nested%-dir%-2 %(directory%)')
end

T['File manipulation']['can delete'] = function()
  local entries = { 'file', 'empty-dir/', 'dir/', 'dir/file', 'dir/nested-dir/', 'dir/nested-dir/file' }
  local temp_dir = make_temp_dir('temp', entries)
  child.cmd('edit ' .. (temp_dir .. '/file'))
  local buf_id = child.api.nvim_get_current_buf()
  local buf_name = child.api.nvim_buf_get_name(buf_id)

  open(temp_dir)

  set_lines({})
  child.expect_screenshot()

  mock_confirm(1)
  synchronize()
  child.expect_screenshot()

  validate_tree(temp_dir, {})
  -- - Should not affect the buffer for deleted file (allows restoring it)
  eq(child.api.nvim_buf_get_name(buf_id), buf_name)

  -- Validate separately because order is not guaranteed
  local ref_pattern = make_plain_pattern('CONFIRM FILE SYSTEM ACTIONS', short_path(temp_dir) .. '\n')
  validate_confirm_args(ref_pattern)

  validate_confirm_args('  DELETE │ dir %(permanently%)')
  validate_confirm_args('  DELETE │ empty%-dir %(permanently%)')
  validate_confirm_args('  DELETE │ file %(permanently%)')
end

T['File manipulation']['delete respects `options.permanent_delete`'] = function()
  child.set_size(10, 60)

  -- Mock `stdpath()`
  local data_dir = mock_stdpath_data()
  local trash_dir = join_path(data_dir, 'mini.files', 'trash')

  -- Create temporary data, open file from it, and delete it
  child.lua('MiniFiles.config.options.permanent_delete = false')
  local temp_dir = make_temp_dir('temp', { 'file', 'dir/', 'dir/subfile' })
  child.cmd('edit ' .. (temp_dir .. '/file'))
  local buf_id = child.api.nvim_get_current_buf()
  local buf_name = child.api.nvim_buf_get_name(buf_id)

  open(temp_dir)

  type_keys('VGd')
  mock_confirm(1)
  synchronize()

  -- Should move into special trash directory
  validate_tree(temp_dir, {})
  validate_tree(trash_dir, { 'file', 'dir/', 'dir/subfile' })

  validate_confirm_args('  DELETE │ file %(to trash%)')
  validate_confirm_args('  DELETE │ dir %(to trash%)')

  -- - Should not affect the buffer for moved to trash file (similar to regular
  --   "delete" action and avoids triggering autocommands).
  eq(child.api.nvim_buf_get_name(buf_id), buf_name)

  -- Deleting entries again with same name should replace previous ones
  -- - Recreate previously deleted entries with different content
  child.fn.writefile({ 'New file' }, join_path(temp_dir, 'file'))
  child.fn.mkdir(join_path(temp_dir, 'dir'))
  child.fn.writefile({ 'New subfile' }, join_path(temp_dir, 'dir', 'subfile'))

  mock_confirm(1)
  synchronize()

  -- - Delete again
  type_keys('VGd')
  mock_confirm(1)
  synchronize()

  validate_tree(temp_dir, {})
  validate_tree(trash_dir, { 'dir/', 'dir/subfile', 'file' })

  -- - Check that files actually were replaced
  validate_file_content(join_path(trash_dir, 'file'), { 'New file' })
  validate_file_content(join_path(trash_dir, 'dir', 'subfile'), { 'New subfile' })
end

T['File manipulation']['can move to trash across devices'] = function()
  child.set_size(10, 60)

  local data_dir = mock_stdpath_data()
  local trash_dir = join_path(data_dir, 'mini.files', 'trash')
  child.lua('MiniFiles.config.options.permanent_delete = false')

  -- Mock `vim.loop.fs_rename()` not working across devices/volumes/partitions
  child.lua('vim.loop.fs_rename = function() return nil, "EXDEV: cross-device link not permitted:", "EXDEV" end')

  local temp_dir = make_temp_dir('temp', { 'file', 'dir/', 'dir/nested/', 'dir/nested/file' })
  open(temp_dir)

  -- Write lines in moved files to check "copy-delete" and not "create-delete"
  child.fn.writefile({ 'File' }, join_path(temp_dir, 'file'))
  child.fn.writefile({ 'File nested' }, join_path(temp_dir, 'dir', 'nested', 'file'))

  type_keys('dG')
  mock_confirm(1)
  synchronize()

  validate_tree(temp_dir, {})
  validate_tree(trash_dir, { 'dir/', 'dir/nested/', 'dir/nested/file', 'file' })

  validate_file_content(join_path(trash_dir, 'file'), { 'File' })
  validate_file_content(join_path(trash_dir, 'dir', 'nested', 'file'), { 'File nested' })
end

T['File manipulation']['can rename'] = function()
  local temp_dir = make_temp_dir('temp', { 'file', 'dir/' })
  open(temp_dir)

  type_keys('C', 'new-dir', '<Esc>')
  type_keys('j', 'A', '-new', '<Esc>')
  child.expect_screenshot()

  mock_confirm(1)
  synchronize()
  child.expect_screenshot()

  validate_tree(temp_dir, { 'file-new', 'new-dir/' })

  -- Validate separately because order is not guaranteed
  local ref_pattern = make_plain_pattern('CONFIRM FILE SYSTEM ACTIONS', short_path(temp_dir) .. '\n')
  validate_confirm_args(ref_pattern)

  validate_confirm_args('  RENAME │ dir => new%-dir')
  validate_confirm_args('  RENAME │ file => file%-new')
end

T['File manipulation']['rename does not override existing entry'] = function()
  child.set_size(10, 60)

  local temp_dir = make_temp_dir('temp', { 'dir/', 'dir-2/', 'file', 'file-2' })
  open(temp_dir)
  child.expect_screenshot()

  type_keys('A', '-2', '<Esc>')
  type_keys('2j', 'A', '-2', '<Esc>')
  child.expect_screenshot()

  mock_confirm(1)
  synchronize()
  child.expect_screenshot()

  -- Should show warning
  local warn_level = child.lua_get('vim.log.levels.WARN')
  local ref_log = {
    { '(mini.files) Can not move or rename ' .. temp_dir .. '/dir. Target path already exists.', warn_level },
    { '(mini.files) Can not move or rename ' .. temp_dir .. '/file. Target path already exists.', warn_level },
  }
  eq(child.lua_get('_G.notify_log'), ref_log)
end

T['File manipulation']['rename file renames opened buffers'] = function()
  local temp_dir = make_temp_dir('temp', { 'file' })

  local file_path_prev = join_path(temp_dir, 'file')
  child.cmd('edit ' .. file_path_prev)
  local buf_id = child.api.nvim_get_current_buf()

  open(temp_dir)
  type_keys('C', 'new-file', '<Esc>')

  eq(is_file_in_buffer(buf_id, file_path_prev), true)

  mock_confirm(1)
  synchronize()
  eq(is_file_in_buffer(buf_id, join_path(temp_dir, 'new-file')), true)

  -- Should open path in relative form for nicer `:buffers`
  expect.match(child.cmd_capture('buffers'):gsub('\\', '/'), '[^/]tests/dir%-files/temp/new%-file')
end

T['File manipulation']['rename directory renames opened buffers'] = function()
  local temp_dir = make_temp_dir('temp', { 'dir/', 'dir/file', 'dir/nested/', 'dir/nested/file-2' })

  local file_path_prev = join_path(temp_dir, 'dir', 'file')
  child.cmd('edit ' .. file_path_prev)
  local file_buf_id = child.api.nvim_get_current_buf()

  local descendant_path_prev = join_path(temp_dir, 'dir', 'nested', 'file-2')
  child.cmd('edit ' .. descendant_path_prev)
  local descendant_buf_id = child.api.nvim_get_current_buf()

  open(temp_dir)
  type_keys('C', 'new-dir', '<Esc>')

  eq(is_file_in_buffer(file_buf_id, file_path_prev), true)
  eq(is_file_in_buffer(descendant_buf_id, descendant_path_prev), true)

  mock_confirm(1)
  synchronize()
  eq(is_file_in_buffer(file_buf_id, join_path(temp_dir, 'new-dir', 'file')), true)
  eq(is_file_in_buffer(descendant_buf_id, join_path(temp_dir, 'new-dir', 'nested', 'file-2')), true)
end

T['File manipulation']['renames even if lines are rearranged'] = function()
  local temp_dir = make_temp_dir('temp', { 'file-1', 'file-2' })
  open(temp_dir)

  -- Rearrange lines
  type_keys('dd', 'p')

  type_keys('gg', 'C', 'new-file-2', '<Esc>')
  type_keys('j^', 'C', 'new-file-1', '<Esc>')

  mock_confirm(1)
  synchronize()

  validate_confirm_args('RENAME │ file%-2 => new%-file%-2')
  validate_confirm_args('RENAME │ file%-1 => new%-file%-1')
end

T['File manipulation']['rename works again after undo'] = function()
  local temp_dir = make_temp_dir('temp', { 'file' })
  open(temp_dir)

  type_keys('C', 'file-new', '<Esc>')
  child.expect_screenshot()

  mock_confirm(1)
  synchronize()

  validate_tree(temp_dir, { 'file-new' })

  -- Validate confirmation messages
  local ref_pattern = make_plain_pattern('CONFIRM FILE SYSTEM ACTIONS', short_path(temp_dir) .. '\n')
  validate_confirm_args(ref_pattern)
  validate_confirm_args('  RENAME │ file => file%-new')

  -- Undo and synchronize should cleanly rename back
  type_keys('u', 'u')
  child.expect_screenshot()

  mock_confirm(1)
  synchronize()

  validate_tree(temp_dir, { 'file' })
  validate_confirm_args('  RENAME │ file%-new => file')
end

T['File manipulation']['can move file'] = function()
  local temp_dir = make_temp_dir('temp', { 'file', 'dir/' })
  open(temp_dir)

  -- Write lines in moved file to check actual move and not "delete-create"
  child.fn.writefile({ 'File' }, join_path(temp_dir, 'file'))

  -- Perform manipulation
  type_keys('G', 'dd')
  go_in()
  type_keys('V', 'P')
  child.expect_screenshot()

  mock_confirm(1)
  synchronize()
  child.expect_screenshot()

  validate_tree(temp_dir, { 'dir/', 'dir/file' })
  validate_file_content(join_path(temp_dir, 'dir', 'file'), { 'File' })

  -- Validate separately because order is not guaranteed
  local ref_pattern = make_plain_pattern('CONFIRM FILE SYSTEM ACTIONS', short_path(temp_dir) .. '\n')
  validate_confirm_args(ref_pattern)
  -- - Target path should be relative to group directory
  validate_confirm_args('  MOVE   │ file => dir/file')
end

T['File manipulation']['can move directory'] = function()
  local temp_dir = make_temp_dir('temp', { 'dir/', 'dir/file', 'dir/nested/', 'dir/nested/file', 'dir-target/' })
  open(temp_dir)

  -- Write lines in moved file to check actual move and not "delete-create"
  child.fn.writefile({ 'File' }, join_path(temp_dir, 'dir', 'file'))

  type_keys('dd')
  go_in()
  type_keys('V', 'P')
  child.expect_screenshot()

  mock_confirm(1)
  synchronize()
  child.expect_screenshot()

  --stylua: ignore
  local ref_tree = {
    'dir-target/',
    'dir-target/dir/', 'dir-target/dir/file',
    'dir-target/dir/nested/', 'dir-target/dir/nested/file',
  }
  validate_tree(temp_dir, ref_tree)
  validate_file_content(join_path(temp_dir, 'dir-target', 'dir', 'file'), { 'File' })

  local ref_pattern = make_plain_pattern('CONFIRM FILE SYSTEM ACTIONS', short_path(temp_dir) .. '\n')
  validate_confirm_args(ref_pattern)
  validate_confirm_args('  MOVE   │ dir => dir%-target/dir')
end

T['File manipulation']['move can show not relative "to" path'] = function()
  local temp_dir = make_temp_dir('temp', { 'dir/', 'dir/file' })
  open(temp_dir .. '/dir')

  -- Perform manipulation
  type_keys('dd')
  go_out()
  type_keys('P')
  mock_confirm(1)
  synchronize()

  validate_confirm_args('  MOVE   │ file => ' .. vim.pesc(short_path(temp_dir, 'file')))
end

T['File manipulation']['move does not override existing entry'] = function()
  child.set_size(10, 80)

  local temp_dir = make_temp_dir('temp', { 'dir/', 'file', 'target-dir/', 'target-dir/dir/', 'target-dir/file' })
  open(temp_dir)
  child.expect_screenshot()

  type_keys('dd', 'l', 'p')
  type_keys('h', 'G', 'dd', 'l', 'p')
  child.expect_screenshot()

  mock_confirm(1)
  synchronize()
  child.expect_screenshot()

  -- Should show warning
  local warn_level = child.lua_get('vim.log.levels.WARN')
  local ref_log = {
    { '(mini.files) Can not move or rename ' .. temp_dir .. '/dir. Target path already exists.', warn_level },
    { '(mini.files) Can not move or rename ' .. temp_dir .. '/file. Target path already exists.', warn_level },
  }
  eq(child.lua_get('_G.notify_log'), ref_log)
end

T['File manipulation']['handles move directory inside itself'] = function()
  local temp_dir = make_temp_dir('temp', { 'dir/', 'dir/file', 'dir/nested/' })
  open(temp_dir)

  type_keys('yy')
  go_in()
  go_in()
  type_keys('V', 'p')
  go_out()
  go_out()
  type_keys('dd')
  child.expect_screenshot()

  -- Should ask for confirmation but silently not do this
  mock_confirm(1)
  synchronize()
  child.expect_screenshot()

  validate_tree(temp_dir, { 'dir/', 'dir/file', 'dir/nested/' })

  validate_confirm_args('  MOVE   │ dir => dir/nested/dir')
end

T['File manipulation']['can move while changing basename'] = function()
  local temp_dir = make_temp_dir('temp', { 'file', 'dir/' })
  open(temp_dir)

  -- Write lines in moved file to check actual move and not "delete-create"
  child.fn.writefile({ 'File' }, join_path(temp_dir, 'file'))

  -- Perform manipulation
  type_keys('G', 'dd')
  go_in()
  type_keys('V', 'P')
  -- - Rename
  type_keys('C', 'new-file', '<Esc>')
  child.expect_screenshot()

  mock_confirm(1)
  synchronize()
  child.expect_screenshot()

  validate_tree(temp_dir, { 'dir/', 'dir/new-file' })
  validate_file_content(join_path(temp_dir, 'dir', 'new-file'), { 'File' })

  validate_confirm_args('  MOVE   │ file => dir/new%-file')
end

T['File manipulation']['can move inside new directory'] = function()
  child.set_size(10, 60)

  local temp_dir = make_temp_dir('temp', { 'file' })
  open(temp_dir)

  -- Write lines in moved file to check actual move and not "delete-create"
  child.fn.writefile({ 'File' }, join_path(temp_dir, 'file'))

  -- Perform manipulation
  type_keys('i', 'new-dir/new-subdir/', '<Esc>')
  child.expect_screenshot()

  mock_confirm(1)
  synchronize()
  child.expect_screenshot()

  validate_tree(temp_dir, { 'new-dir/', 'new-dir/new-subdir/', 'new-dir/new-subdir/file' })
  validate_file_content(join_path(temp_dir, 'new-dir', 'new-subdir', 'file'), { 'File' })

  local ref_pattern = make_plain_pattern(short_path(temp_dir) .. '\n')
  validate_confirm_args(ref_pattern)
  validate_confirm_args('  MOVE   │ file => new%-dir/new%-subdir/file')
end

T['File manipulation']['can move across devices'] = function()
  child.set_size(10, 60)

  -- Mock `vim.loop.fs_rename()` not working across devices/volumes/partitions
  child.lua('vim.loop.fs_rename = function() return nil, "EXDEV: cross-device link not permitted:", "EXDEV" end')

  local tmp_children = { 'dir/', 'dir/file', 'dir/nested/', 'dir/nested/sub/', 'dir/nested/sub/file' }
  local temp_dir = make_temp_dir('temp', tmp_children)
  open(temp_dir)

  -- Write lines in moved files to check "copy-delete" and not "create-delete"
  child.fn.writefile({ 'File' }, join_path(temp_dir, 'dir', 'file'))
  child.fn.writefile({ 'File nested' }, join_path(temp_dir, 'dir', 'nested', 'sub', 'file'))

  go_in()
  type_keys('dG')
  go_out()
  type_keys('P')

  mock_confirm(1)
  synchronize()

  validate_tree(temp_dir, { 'dir/', 'file', 'nested/', 'nested/sub/', 'nested/sub/file' })
  validate_file_content(join_path(temp_dir, 'file'), { 'File' })
  validate_file_content(join_path(temp_dir, 'nested', 'sub', 'file'), { 'File nested' })
end

T['File manipulation']['move works again after undo'] = function()
  local temp_dir = make_temp_dir('temp', { 'file', 'dir/' })
  open(temp_dir)

  -- Perform manipulation
  type_keys('G', 'dd')
  go_in()
  type_keys('V', 'P')
  child.expect_screenshot()

  mock_confirm(1)
  synchronize()

  validate_tree(temp_dir, { 'dir/', 'dir/file' })

  -- Validate confirmation messages
  local ref_pattern = make_plain_pattern('CONFIRM FILE SYSTEM ACTIONS', short_path(temp_dir) .. '\n')
  validate_confirm_args(ref_pattern)
  validate_confirm_args('  MOVE   │ file => dir/file')

  -- Undos and synchronize should cleanly move back
  type_keys('u', 'u')
  go_out()
  type_keys('u', 'u')
  -- - Clear command line
  type_keys(':', '<Esc>')
  -- - Highlighting is different on Neovim>=0.10
  if child.fn.has('nvim-0.10') == 1 then child.expect_screenshot() end

  mock_confirm(1)
  synchronize()

  validate_tree(temp_dir, { 'dir/', 'file' })
  validate_confirm_args('  MOVE   │ file => ' .. vim.pesc(short_path(temp_dir, 'file')))
end

T['File manipulation']['can copy file'] = function()
  local temp_dir = make_temp_dir('temp', { 'file', 'dir/' })
  open(temp_dir)

  -- Write lines in copied file to check actual copy and not create
  child.fn.writefile({ 'File' }, join_path(temp_dir, 'file'))

  -- Perform manipulation
  type_keys('j', 'yy', 'k')
  go_in()
  type_keys('V', 'P')
  -- - Should be able to copy in same directory
  go_out()
  type_keys('p', 'C', 'file-copy', '<Esc>')
  child.expect_screenshot()

  mock_confirm(1)
  synchronize()
  child.expect_screenshot()

  validate_tree(temp_dir, { 'dir/', 'dir/file', 'file', 'file-copy' })
  validate_file_content(join_path(temp_dir, 'file'), { 'File' })
  validate_file_content(join_path(temp_dir, 'dir', 'file'), { 'File' })
  validate_file_content(join_path(temp_dir, 'file-copy'), { 'File' })

  -- Validate separately because order is not guaranteed
  local ref_pattern = make_plain_pattern('CONFIRM FILE SYSTEM ACTIONS', short_path(temp_dir) .. '\n')
  validate_confirm_args(ref_pattern)

  -- - Target path should be relative to group directory
  validate_confirm_args('  COPY   │ file => dir/file')
  validate_confirm_args('  COPY   │ file => file%-copy')
end

T['File manipulation']['can copy file inside new directory'] = function()
  child.set_size(10, 60)

  local temp_dir = make_temp_dir('temp', { 'file' })
  open(temp_dir)

  -- Write lines in moved file to check actual move and not "delete-create"
  child.fn.writefile({ 'File' }, join_path(temp_dir, 'file'))

  -- Perform manipulation
  type_keys('yy', 'p')
  type_keys('i', 'new-dir/new-subdir/', '<Esc>')
  child.expect_screenshot()

  mock_confirm(1)
  synchronize()
  child.expect_screenshot()

  validate_tree(temp_dir, { 'file', 'new-dir/', 'new-dir/new-subdir/', 'new-dir/new-subdir/file' })
  validate_file_content(join_path(temp_dir, 'new-dir', 'new-subdir', 'file'), { 'File' })
end

T['File manipulation']['can copy directory'] = function()
  local temp_dir = make_temp_dir('temp', { 'dir/', 'dir/file', 'dir/nested/', 'dir-target/' })
  open(temp_dir)

  -- Write lines in copied file to check actual copy and not create
  child.fn.writefile({ 'File' }, join_path(temp_dir, 'dir', 'file'))

  -- Perform manipulation
  type_keys('yy', 'j')
  go_in()
  type_keys('V', 'P')
  -- - Should be able to copy in same directory
  go_out()
  type_keys('p', 'C', 'dir-copy', '<Esc>')
  child.expect_screenshot()

  mock_confirm(1)
  synchronize()
  child.expect_screenshot()

  --stylua: ignore
  local ref_tree = {
    'dir/',                           'dir/file',            'dir/nested/',
    'dir-target/', 'dir-target/dir/', 'dir-target/dir/file', 'dir-target/dir/nested/',
    'dir-copy/',                      'dir-copy/file',       'dir-copy/nested/',
  }
  validate_tree(temp_dir, ref_tree)

  validate_file_content(join_path(temp_dir, 'dir', 'file'), { 'File' })
  validate_file_content(join_path(temp_dir, 'dir-target', 'dir', 'file'), { 'File' })
  validate_file_content(join_path(temp_dir, 'dir-copy', 'file'), { 'File' })

  -- Validate separately because order is not guaranteed
  local ref_pattern = make_plain_pattern('CONFIRM FILE SYSTEM ACTIONS', short_path(temp_dir) .. '\n')
  validate_confirm_args(ref_pattern)

  -- - Target path should be relative to group directory
  validate_confirm_args('  COPY   │ dir => dir%-target/dir')
  validate_confirm_args('  COPY   │ dir => dir%-copy')
end

T['File manipulation']['can copy directory inside new directory'] = function()
  child.set_size(10, 60)

  local temp_dir = make_temp_dir('temp', { 'dir/', 'dir/file', 'dir/nested/' })
  open(temp_dir)

  -- Write lines in copied file to check actual copy and not create
  child.fn.writefile({ 'File' }, join_path(temp_dir, 'dir', 'file'))

  -- Perform manipulation
  type_keys('yy', 'p')
  type_keys('i', 'new-dir/new-subdir/', '<Esc>')
  child.expect_screenshot()

  mock_confirm(1)
  synchronize()
  child.expect_screenshot()

  --stylua: ignore
  local ref_tree = {
    'dir/', 'dir/file', 'dir/nested/',
    'new-dir/', 'new-dir/new-subdir/',
    'new-dir/new-subdir/dir/', 'new-dir/new-subdir/dir/file', 'new-dir/new-subdir/dir/nested/',
  }
  validate_tree(temp_dir, ref_tree)

  validate_file_content(join_path(temp_dir, 'dir', 'file'), { 'File' })
  validate_file_content(join_path(temp_dir, 'new-dir', 'new-subdir', 'dir', 'file'), { 'File' })
end

T['File manipulation']['copy can show not relative "to" path'] = function()
  local temp_dir = make_temp_dir('temp', { 'dir/', 'dir/file' })
  open(temp_dir .. '/dir')

  -- Perform manipulation
  type_keys('yy')
  go_out()
  type_keys('p')
  mock_confirm(1)
  synchronize()

  validate_confirm_args('  COPY   │ file => ' .. vim.pesc(short_path(temp_dir, 'file')))
end

T['File manipulation']['copy does not override existing entry'] = function()
  child.set_size(10, 80)

  local temp_dir = make_temp_dir('temp', { 'dir/', 'file', 'target-dir/', 'target-dir/dir/', 'target-dir/file' })
  open(temp_dir)
  child.expect_screenshot()

  type_keys('yy', 'j', 'l', 'p')
  type_keys('h', 'G', 'yy', 'k', 'l', 'p')
  child.expect_screenshot()

  mock_confirm(1)
  synchronize()
  child.expect_screenshot()

  -- Should show warning
  local warn_level = child.lua_get('vim.log.levels.WARN')
  local ref_log = {
    { '(mini.files) Can not copy ' .. temp_dir .. '/dir. Target path already exists.', warn_level },
    { '(mini.files) Can not copy ' .. temp_dir .. '/file. Target path already exists.', warn_level },
  }
  eq(child.lua_get('_G.notify_log'), ref_log)
end

T['File manipulation']['can copy directory inside itself'] = function()
  local temp_dir = make_temp_dir('temp', { 'dir/', 'dir/file', 'dir/nested/' })
  open(temp_dir)

  -- Write lines in copied file to check actual copy and not create
  child.fn.writefile({ 'File' }, join_path(temp_dir, 'dir', 'file'))

  -- Perform manipulation
  type_keys('yy')
  go_in()
  type_keys('p')
  child.expect_screenshot()

  mock_confirm(1)
  synchronize()
  child.expect_screenshot()

  validate_tree(temp_dir, { 'dir/', 'dir/dir/', 'dir/dir/file', 'dir/dir/nested/', 'dir/file', 'dir/nested/' })
  validate_file_content(join_path(temp_dir, 'dir', 'file'), { 'File' })
  validate_file_content(join_path(temp_dir, 'dir', 'dir', 'file'), { 'File' })

  validate_confirm_args('  COPY   │ dir => dir/dir')
end

T['File manipulation']['can convert file into directory'] = function()
  local temp_dir = make_temp_dir('temp', { 'file', 'dir/', 'dir/subfile' })
  child.fn.writefile({ 'Subfile' }, join_path(temp_dir, 'dir', 'subfile'))
  open(temp_dir)

  type_keys('A', '/', '<Esc>')
  type_keys('j', 'A', '/', '<Esc>')
  child.expect_screenshot()

  mock_confirm(1)
  synchronize()
  child.expect_screenshot()

  -- Should convert file->directory but not touch directory->directory
  validate_tree(temp_dir, { 'file/', 'dir/', 'dir/subfile' })
  validate_file_content(join_path(temp_dir, 'dir', 'subfile'), { 'Subfile' })

  validate_confirm_args('  DELETE │ file')
  validate_confirm_args('  RENAME │ dir => dir')
  validate_confirm_args('  CREATE │ file %(directory%)')
end

T['File manipulation']['respects modified hidden buffers'] = function()
  local temp_dir = make_temp_dir('temp', { 'file', 'dir/' })
  open(temp_dir)

  go_in()
  type_keys('C', 'new-file', '<Esc>')
  go_out()
  trim_right()
  child.expect_screenshot()

  mock_confirm(1)
  synchronize()

  validate_tree(temp_dir, { 'dir/', 'dir/new-file', 'file' })
end

T['File manipulation']['can be not confirmed'] = function()
  open(test_dir_path)
  type_keys('o', 'new-file', '<Esc>')

  child.expect_screenshot()
  mock_confirm(2)
  synchronize()
  child.expect_screenshot()
  eq(child.fn.filereadable(join_path(test_dir_path, 'new-file')), 0)
end

T['File manipulation']['can be not confirmed with preview'] = function()
  child.lua('MiniFiles.config.windows.preview = true')
  open(test_dir_path)
  type_keys('o', 'new-file', '<Esc>')

  child.expect_screenshot()
  mock_confirm(2)
  synchronize()
  child.expect_screenshot()
  eq(child.fn.filereadable(join_path(test_dir_path, 'new-file')), 0)
end

T['File manipulation']['works with problematic names'] = function()
  local temp_dir = make_temp_dir('temp', { [[a %file-]], 'b file' })
  open(temp_dir)

  -- Perform manipulation
  -- - Delete
  type_keys('dd')
  -- - Rename
  type_keys('C', 'c file', '<Esc>')
  -- - Create
  type_keys('o', 'd file', '<Esc>')
  if child.fn.has('nvim-0.10') == 1 then child.expect_screenshot() end

  mock_confirm(1)
  synchronize()
  if child.fn.has('nvim-0.10') == 1 then child.expect_screenshot() end

  validate_tree(temp_dir, { 'c file', 'd file' })
end

T['File manipulation']['handles backslash on Unix'] = function()
  if child.loop.os_uname().sysname == 'Windows_NT' then MiniTest.skip('Test is not for Windows.') end

  local temp_dir = make_temp_dir('temp', { '\\', 'hello\\', 'wo\\rld' })
  open(temp_dir)

  -- Perform manipulation
  -- - Delete
  type_keys('dd')
  -- - Rename
  type_keys('C', 'new-hello', '<Esc>')
  -- - Create
  type_keys('o', 'bad\\file', '<Esc>')
  if child.fn.has('nvim-0.10') == 1 then child.expect_screenshot() end

  mock_confirm(1)
  synchronize()
  if child.fn.has('nvim-0.10') == 1 then child.expect_screenshot() end

  validate_tree(temp_dir, { 'bad\\file', 'new-hello', 'wo\\rld' })
end

T['File manipulation']['ignores blank lines'] = function()
  open(test_dir_path)
  type_keys('o', '<Esc>', 'yy', 'p')
  child.expect_screenshot()

  -- Should synchronize without confirmation
  synchronize()
  child.expect_screenshot()
end

T['File manipulation']['ignores identical user-copied entries'] = function()
  open(test_dir_path)
  type_keys('yj', 'p')
  child.expect_screenshot()

  -- Should synchronize without confirmation
  synchronize()
  child.expect_screenshot()
end

T['File manipulation']['special cases'] = new_set()

T['File manipulation']['special cases']['freed path'] = new_set()

T['File manipulation']['special cases']['freed path']['delete and move other'] = function()
  local temp_dir = make_temp_dir('temp', { 'dir/', 'dir/file-a', 'file-b' })
  child.fn.writefile({ 'File A' }, join_path(temp_dir, 'dir', 'file-a'))
  open(temp_dir)
  type_keys('j', 'dd')
  go_in()
  type_keys('dd')
  go_out()
  type_keys('p', 'C', 'file-b')
  mock_confirm(1)
  synchronize()

  validate_tree(temp_dir, { 'dir/', 'file-b' })
  validate_file_content(join_path(temp_dir, 'file-b'), { 'File A' })
end

T['File manipulation']['special cases']['freed path']['delete and rename other'] = function()
  local temp_dir = make_temp_dir('temp', { 'file-a', 'file-b' })
  child.fn.writefile({ 'File B' }, join_path(temp_dir, 'file-b'))
  open(temp_dir)
  type_keys('dd', 'C', 'file-a', '<Esc>')
  mock_confirm(1)
  synchronize()

  validate_tree(temp_dir, { 'file-a' })
  validate_file_content(join_path(temp_dir, 'file-a'), { 'File B' })
end

T['File manipulation']['special cases']['freed path']['delete and copy other'] = function()
  local temp_dir = make_temp_dir('temp', { 'file-a', 'file-b' })
  child.fn.writefile({ 'File A' }, join_path(temp_dir, 'file-a'))
  child.fn.writefile({ 'File B' }, join_path(temp_dir, 'file-b'))
  open(temp_dir)
  type_keys('dd', 'yy', 'p', 'C', 'file-a', '<Esc>')
  mock_confirm(1)
  synchronize()

  validate_tree(temp_dir, { 'file-a', 'file-b' })
  validate_file_content(join_path(temp_dir, 'file-a'), { 'File B' })
  validate_file_content(join_path(temp_dir, 'file-b'), { 'File B' })
end

T['File manipulation']['special cases']['freed path']['delete and create'] = function()
  local temp_dir = make_temp_dir('temp', { 'file' })
  child.fn.writefile({ 'File' }, join_path(temp_dir, 'file'))
  open(temp_dir)
  type_keys('dd', 'o', 'file', '<Esc>')
  mock_confirm(1)
  synchronize()

  validate_tree(temp_dir, { 'file' })
  validate_file_content(join_path(temp_dir, 'file'), {})
end

T['File manipulation']['special cases']['freed path']['move and rename other'] = function()
  local temp_dir = make_temp_dir('temp', { 'dir/', 'file-a', 'file-b' })
  child.fn.writefile({ 'File A' }, join_path(temp_dir, 'file-a'))
  child.fn.writefile({ 'File B' }, join_path(temp_dir, 'file-b'))
  open(temp_dir)
  type_keys('j', 'dd', 'k')
  go_in()
  type_keys('P')
  go_out()
  type_keys('j', 'C', 'file-a')
  mock_confirm(1)
  synchronize()

  validate_tree(temp_dir, { 'dir/', 'dir/file-a', 'file-a' })
  validate_file_content(join_path(temp_dir, 'file-a'), { 'File B' })
  validate_file_content(join_path(temp_dir, 'dir', 'file-a'), { 'File A' })
end

T['File manipulation']['special cases']['freed path']['move and copy other'] = function()
  local temp_dir = make_temp_dir('temp', { 'dir/', 'file-a', 'file-b' })
  child.fn.writefile({ 'File A' }, join_path(temp_dir, 'file-a'))
  child.fn.writefile({ 'File B' }, join_path(temp_dir, 'file-b'))
  open(temp_dir)
  type_keys('j', 'dd', 'gg')
  go_in()
  type_keys('P')
  go_out()
  type_keys('j', 'yy', 'p', 'C', 'file-a')
  mock_confirm(1)
  synchronize()

  validate_tree(temp_dir, { 'dir/', 'dir/file-a', 'file-a', 'file-b' })
  validate_file_content(join_path(temp_dir, 'file-a'), { 'File B' })
  validate_file_content(join_path(temp_dir, 'file-b'), { 'File B' })
  validate_file_content(join_path(temp_dir, 'dir', 'file-a'), { 'File A' })
end

T['File manipulation']['special cases']['freed path']['move and create'] = function()
  local temp_dir = make_temp_dir('temp', { 'dir/', 'file-a' })
  child.fn.writefile({ 'File A' }, join_path(temp_dir, 'file-a'))
  open(temp_dir)
  type_keys('j', 'dd', 'k')
  go_in()
  type_keys('P')
  go_out()
  type_keys('o', 'file-a')
  mock_confirm(1)
  synchronize()

  validate_tree(temp_dir, { 'dir/', 'dir/file-a', 'file-a' })
  validate_file_content(join_path(temp_dir, 'file-a'), {})
  validate_file_content(join_path(temp_dir, 'dir', 'file-a'), { 'File A' })
end

T['File manipulation']['special cases']['freed path']['rename and move other'] = function()
  -- NOTE: Unfortunately, this doesn't work as "move" is done before "rename".
  -- Accounting for this seems involve even more tweaks than is currently done,
  -- like fully computing the proper order of overlapping actions (which might
  -- not be fully possibly due to "cyclic renames/moves"). So this deliberately
  -- is left unresolved with the suggestion to split steps and sync more often.

  -- local temp_dir = make_temp_dir('temp', { 'dir/', 'dir/file-a', 'file-b' })
  -- child.fn.writefile({ 'File A' }, join_path(temp_dir, 'dir', 'file-a'))
  -- child.fn.writefile({ 'File B' }, join_path(temp_dir, 'file-b'))
  -- open(temp_dir)
  -- type_keys('G', 'C', 'file-c', '<Esc>')
  -- type_keys('gg')
  -- go_in()
  -- type_keys('dd')
  -- go_out()
  -- type_keys('p', 'C', 'file-b', '<Esc>')
  -- mock_confirm(1)
  -- synchronize()
  --
  -- validate_tree(temp_dir, { 'dir/', 'file-b', 'file-c' })
  -- validate_file_content(join_path(temp_dir, 'file-b'), { 'File A' })
  -- validate_file_content(join_path(temp_dir, 'file-c'), { 'File B' })
end

T['File manipulation']['special cases']['freed path']['rename and copy other'] = function()
  local temp_dir = make_temp_dir('temp', { 'file-a', 'file-b' })
  child.fn.writefile({ 'File A' }, join_path(temp_dir, 'file-a'))
  child.fn.writefile({ 'File B' }, join_path(temp_dir, 'file-b'))
  open(temp_dir)
  type_keys('C', 'file-c', '<Esc>')
  type_keys('j', 'yy', 'p', 'C', 'file-a')
  mock_confirm(1)
  synchronize()

  validate_tree(temp_dir, { 'file-a', 'file-b', 'file-c' })
  validate_file_content(join_path(temp_dir, 'file-a'), { 'File B' })
  validate_file_content(join_path(temp_dir, 'file-b'), { 'File B' })
  validate_file_content(join_path(temp_dir, 'file-c'), { 'File A' })
end

T['File manipulation']['special cases']['freed path']['rename and create'] = function()
  local temp_dir = make_temp_dir('temp', { 'file' })
  child.fn.writefile({ 'File' }, join_path(temp_dir, 'file'))
  open(temp_dir)
  type_keys('C', 'new-file', '<Esc>')
  type_keys('o', 'file')
  mock_confirm(1)
  synchronize()

  validate_tree(temp_dir, { 'file', 'new-file' })
  validate_file_content(join_path(temp_dir, 'file'), {})
  validate_file_content(join_path(temp_dir, 'new-file'), { 'File' })
end

T['File manipulation']['special cases']['act on same path'] = new_set()

T['File manipulation']['special cases']['act on same path']['copy and rename'] = function()
  local temp_dir = make_temp_dir('temp', { 'file' })
  child.fn.writefile({ 'File' }, join_path(temp_dir, 'file'))
  open(temp_dir)
  type_keys('yy', 'p', 'C', 'file-a', '<Esc>')
  type_keys('k^', 'C', 'file-b', '<Esc>')
  mock_confirm(1)
  synchronize()

  validate_tree(temp_dir, { 'file-a', 'file-b' })
  validate_file_content(join_path(temp_dir, 'file-a'), { 'File' })
  validate_file_content(join_path(temp_dir, 'file-b'), { 'File' })
end

T['File manipulation']['special cases']['act on same path']['copy and move'] = function()
  local temp_dir = make_temp_dir('temp', { 'dir/', 'file' })
  child.fn.writefile({ 'File' }, join_path(temp_dir, 'file'))
  open(temp_dir)
  type_keys('j', 'yy', 'p', 'C', 'file-a', '<Esc>')
  type_keys('k', 'dd', 'k')
  go_in()
  type_keys('P')
  mock_confirm(1)
  synchronize()

  validate_tree(temp_dir, { 'dir/', 'dir/file', 'file-a' })
  validate_file_content(join_path(temp_dir, 'file-a'), { 'File' })
  validate_file_content(join_path(temp_dir, 'dir', 'file'), { 'File' })
end

T['File manipulation']['special cases']['inside affected directory'] = new_set()

T['File manipulation']['special cases']['inside affected directory']['delete in copied'] = function()
  local temp_dir = make_temp_dir('temp', { 'dir/', 'dir/file' })
  open(temp_dir .. '/dir')
  type_keys('dd')
  go_out()
  type_keys('yy', 'p', 'C', 'new-dir', '<Esc>')
  mock_confirm(1)
  synchronize()

  -- "Delete" is done before "copy", so as to "free" space. So both directories
  -- don't have deleted file.
  validate_tree(temp_dir, { 'dir/', 'new-dir/' })
end

T['File manipulation']['special cases']['inside affected directory']['delete in renamed'] = function()
  local temp_dir = make_temp_dir('temp', { 'dir/', 'dir/file' })
  open(temp_dir .. '/dir')
  type_keys('dd')
  go_out()
  type_keys('C', 'new-dir', '<Esc>')
  mock_confirm(1)
  synchronize()

  validate_tree(temp_dir, { 'new-dir/' })
end

T['File manipulation']['special cases']['inside affected directory']['delete in moved'] = function()
  local temp_dir = make_temp_dir('temp', { 'dir/', 'dir/file', 'other-dir/' })
  open(temp_dir .. '/dir')
  type_keys('dd')
  go_out()
  type_keys('dd')
  go_in()
  type_keys('P')
  mock_confirm(1)
  synchronize()

  validate_tree(temp_dir, { 'other-dir/', 'other-dir/dir/' })
end

T['File manipulation']['special cases']['inside affected directory']['move in deleted'] = function()
  local temp_dir = make_temp_dir('temp', { 'dir/', 'dir/file', 'dir/subdir/' })
  open(temp_dir .. '/dir')
  type_keys('j', 'dd')
  go_in()
  type_keys('p')
  go_out()
  go_out()
  type_keys('dd')
  mock_confirm(1)
  synchronize()

  -- Should prefer "delete"
  validate_tree(temp_dir, {})
end

T['File manipulation']['special cases']['inside affected directory']['move in renamed'] = function()
  local temp_dir = make_temp_dir('temp', { 'dir/', 'dir/file', 'dir/subdir/' })
  open(temp_dir .. '/dir')
  type_keys('j', 'dd')
  go_in()
  type_keys('p')
  go_out()
  go_out()
  type_keys('C', 'new-dir', '<Esc>')
  mock_confirm(1)
  synchronize()

  validate_tree(temp_dir, { 'new-dir/', 'new-dir/subdir/', 'new-dir/subdir/file' })
end

T['File manipulation']['special cases']['inside affected directory']['move in copied'] = function()
  local temp_dir = make_temp_dir('temp', { 'dir/', 'dir/file', 'dir/subdir/' })
  open(temp_dir .. '/dir')
  type_keys('j', 'dd')
  go_in()
  type_keys('p')
  go_out()
  go_out()
  type_keys('yy', 'p', 'C', 'new-dir')
  mock_confirm(1)
  synchronize()

  local ref_tree = { 'dir/', 'dir/subdir/', 'dir/subdir/file', 'new-dir/', 'new-dir/subdir/', 'new-dir/subdir/file' }
  validate_tree(temp_dir, ref_tree)
end

T['File manipulation']['special cases']['inside affected directory']['rename in deleted'] = function()
  local temp_dir = make_temp_dir('temp', { 'dir/', 'dir/file' })
  open(temp_dir .. '/dir')
  type_keys('C', 'new-file', '<Esc>')
  go_out()
  type_keys('dd')
  mock_confirm(1)
  synchronize()

  -- Should prefer "delete"
  validate_tree(temp_dir, {})
end

T['File manipulation']['special cases']['inside affected directory']['rename in moved'] = function()
  local temp_dir = make_temp_dir('temp', { 'dir/', 'dir/file', 'other-dir/' })
  open(temp_dir .. '/dir')
  type_keys('C', 'new-file', '<Esc>')
  go_out()
  type_keys('dd', 'G')
  go_in()
  type_keys('P')
  mock_confirm(1)
  synchronize()

  validate_tree(temp_dir, { 'other-dir/', 'other-dir/dir/', 'other-dir/dir/new-file' })
end

T['File manipulation']['special cases']['inside affected directory']['rename in copied'] = function()
  local temp_dir = make_temp_dir('temp', { 'dir/', 'dir/file' })
  open(temp_dir .. '/dir')
  type_keys('C', 'new-file', '<Esc>')
  go_out()
  type_keys('yy', 'p', 'C', 'new-dir', '<Esc>')
  mock_confirm(1)
  synchronize()

  -- "Rename" is done before "copy", so as to "free" space. So both directories
  -- have renamed file.
  validate_tree(temp_dir, { 'dir/', 'dir/new-file', 'new-dir/', 'new-dir/new-file' })
end

T['File manipulation']['special cases']['inside affected directory']['copy in deleted'] = function()
  local temp_dir = make_temp_dir('temp', { 'dir/', 'dir/file' })
  open(temp_dir .. '/dir')
  type_keys('yy', 'p', 'C', 'file-a', '<Esc>')
  go_out()
  type_keys('dd')
  mock_confirm(1)
  synchronize()

  -- Should prefer "delete"
  validate_tree(temp_dir, {})
end

T['File manipulation']['special cases']['inside affected directory']['copy in moved'] = function()
  local temp_dir = make_temp_dir('temp', { 'dir/', 'dir/file', 'other-dir/' })
  open(temp_dir .. '/dir')
  type_keys('yy', 'p', 'C', 'file-a', '<Esc>')
  go_out()
  type_keys('dd')
  go_in()
  type_keys('P')
  mock_confirm(1)
  synchronize()

  validate_tree(temp_dir, { 'other-dir/', 'other-dir/dir/', 'other-dir/dir/file', 'other-dir/dir/file-a' })
end

T['File manipulation']['special cases']['inside affected directory']['copy in renamed'] = function()
  local temp_dir = make_temp_dir('temp', { 'dir/', 'dir/file' })
  open(temp_dir .. '/dir')
  type_keys('yy', 'p', 'C', 'file-a', '<Esc>')
  go_out()
  type_keys('C', 'new-dir', '<Esc>')
  mock_confirm(1)
  synchronize()

  validate_tree(temp_dir, { 'new-dir/', 'new-dir/file', 'new-dir/file-a' })
end

T['File manipulation']['special cases']['inside affected directory']['create in deleted'] = function()
  local temp_dir = make_temp_dir('temp', { 'dir/' })
  open(temp_dir .. '/dir')
  type_keys('i', 'file', '<Esc>')
  go_out()
  type_keys('dd')
  mock_confirm(1)
  synchronize()

  -- Should prefer "delete"
  validate_tree(temp_dir, {})
end

T['File manipulation']['special cases']['inside affected directory']['create in moved'] = function()
  local temp_dir = make_temp_dir('temp', { 'dir/', 'other-dir/' })
  open(temp_dir .. '/dir')
  type_keys('i', 'file', '<Esc>')
  go_out()
  type_keys('dd')
  go_in()
  type_keys('P')
  mock_confirm(1)
  synchronize()

  validate_tree(temp_dir, { 'other-dir/', 'other-dir/dir/', 'other-dir/dir/file' })
end

T['File manipulation']['special cases']['inside affected directory']['create in renamed'] = function()
  local temp_dir = make_temp_dir('temp', { 'dir/' })
  open(temp_dir .. '/dir')
  type_keys('i', 'file', '<Esc>')
  go_out()
  type_keys('C', 'new-dir', '<Esc>')
  mock_confirm(1)
  synchronize()

  validate_tree(temp_dir, { 'new-dir/', 'new-dir/file' })
end

T['File manipulation']['special cases']['inside affected directory']['create in copied'] = function()
  local temp_dir = make_temp_dir('temp', { 'dir/' })
  open(temp_dir .. '/dir')
  type_keys('i', 'file', '<Esc>')
  go_out()
  type_keys('yy', 'p', 'C', 'new-dir', '<Esc>')
  mock_confirm(1)
  synchronize()

  -- "Create" is done last so only in original directory. There is no special
  -- reason for this choice other than grouping "move"/"rename"/"copy" seems
  -- like a more organized choice.
  validate_tree(temp_dir, { 'dir/', 'dir/file', 'new-dir/' })
end

T['File manipulation']['special cases']['from affected directory'] = new_set()

T['File manipulation']['special cases']['from affected directory']['move from deleted'] = function()
  local temp_dir = make_temp_dir('temp', { 'dir/', 'dir/file' })
  open(temp_dir .. '/dir')
  type_keys('dd')
  go_out()
  type_keys('p')
  type_keys('gg', 'dd')
  mock_confirm(1)
  synchronize()

  validate_tree(temp_dir, { 'file' })
end

T['File manipulation']['special cases']['from affected directory']['move from renamed'] = function()
  local temp_dir = make_temp_dir('temp', { 'dir/', 'dir/file' })
  open(temp_dir .. '/dir')
  type_keys('dd')
  go_out()
  type_keys('p')
  type_keys('gg', 'C', 'new-dir')
  mock_confirm(1)
  synchronize()

  validate_tree(temp_dir, { 'file', 'new-dir/' })
end

T['File manipulation']['special cases']['from affected directory']['move from copied'] = function()
  local temp_dir = make_temp_dir('temp', { 'dir/', 'dir/file' })
  open(temp_dir .. '/dir')
  type_keys('dd')
  go_out()
  type_keys('p')
  type_keys('gg', 'yy', 'p', 'C', 'new-dir')
  mock_confirm(1)
  synchronize()

  -- "Move" is done before "copy", so as to "free" space. So no directories
  -- have moved file.
  validate_tree(temp_dir, { 'dir/', 'file', 'new-dir/' })
end

T['File manipulation']['special cases']['from affected directory']['copy from deleted'] = function()
  local temp_dir = make_temp_dir('temp', { 'dir/', 'dir/file' })
  child.fn.writefile({ 'File' }, join_path(temp_dir, 'dir', 'file'))
  open(temp_dir .. '/dir')
  type_keys('yy')
  go_out()
  type_keys('p')
  type_keys('gg', 'dd')
  mock_confirm(1)
  synchronize()

  validate_tree(temp_dir, { 'file' })
  validate_file_content(join_path(temp_dir, 'file'), { 'File' })
end

T['File manipulation']['special cases']['from affected directory']['copy from moved'] = function()
  local temp_dir = make_temp_dir('temp', { 'dir/', 'dir/file', 'other-dir/' })
  child.fn.writefile({ 'File' }, join_path(temp_dir, 'dir', 'file'))
  open(temp_dir .. '/dir')
  type_keys('yy')
  go_out()
  type_keys('p')
  type_keys('gg', 'dd', 'G')
  go_in()
  type_keys('P')
  mock_confirm(1)
  synchronize()

  validate_tree(temp_dir, { 'file', 'other-dir/', 'other-dir/dir/', 'other-dir/dir/file' })
  validate_file_content(join_path(temp_dir, 'file'), { 'File' })
  validate_file_content(join_path(temp_dir, 'other-dir', 'dir', 'file'), { 'File' })
end

T['File manipulation']['special cases']['from affected directory']['copy from renamed'] = function()
  local temp_dir = make_temp_dir('temp', { 'dir/', 'dir/file' })
  child.fn.writefile({ 'File' }, join_path(temp_dir, 'dir', 'file'))
  open(temp_dir .. '/dir')
  type_keys('yy')
  go_out()
  type_keys('p')
  type_keys('gg', 'C', 'new-dir', '<Esc>')
  mock_confirm(1)
  synchronize()

  validate_tree(temp_dir, { 'file', 'new-dir/', 'new-dir/file' })
  validate_file_content(join_path(temp_dir, 'file'), { 'File' })
  validate_file_content(join_path(temp_dir, 'new-dir', 'file'), { 'File' })
end

T['File manipulation']['special cases']['into affected directory'] = new_set()

T['File manipulation']['special cases']['into affected directory']['move into deleted'] = function()
  local temp_dir = make_temp_dir('temp', { 'dir/', 'file' })
  open(temp_dir)
  type_keys('G', 'dd')
  go_in()
  type_keys('P')
  go_out()
  type_keys('dd')
  mock_confirm(1)
  synchronize()

  -- Should prefer "delete"
  validate_tree(temp_dir, {})
end

T['File manipulation']['special cases']['into affected directory']['move into renamed'] = function()
  local temp_dir = make_temp_dir('temp', { 'dir/', 'file' })
  open(temp_dir)
  type_keys('G', 'dd')
  go_in()
  type_keys('P')
  go_out()
  type_keys('C', 'new-dir')
  mock_confirm(1)
  synchronize()

  validate_tree(temp_dir, { 'new-dir/', 'new-dir/file' })
end

T['File manipulation']['special cases']['into affected directory']['move into copied'] = function()
  local temp_dir = make_temp_dir('temp', { 'dir/', 'file' })
  open(temp_dir)
  type_keys('G', 'dd')
  go_in()
  type_keys('P')
  go_out()
  type_keys('yy', 'p', 'C', 'new-dir')
  mock_confirm(1)
  synchronize()

  validate_tree(temp_dir, { 'dir/', 'dir/file', 'new-dir/', 'new-dir/file' })
end

T['File manipulation']['special cases']['into affected directory']['copy into deleted'] = function()
  local temp_dir = make_temp_dir('temp', { 'dir/', 'file' })
  open(temp_dir)
  type_keys('G', 'yy', 'gg')
  go_in()
  type_keys('P')
  go_out()
  type_keys('dd')
  mock_confirm(1)
  synchronize()

  -- Should prefer "delete"
  validate_tree(temp_dir, { 'file' })
end

T['File manipulation']['special cases']['into affected directory']['copy into moved'] = function()
  local temp_dir = make_temp_dir('temp', { 'dir/', 'other-dir/', 'file' })
  open(temp_dir)
  type_keys('G', 'yy', 'gg')
  go_in()
  type_keys('P')
  go_out()
  type_keys('dd')
  go_in()
  type_keys('P')
  mock_confirm(1)
  synchronize()

  validate_tree(temp_dir, { 'file', 'other-dir/', 'other-dir/dir/', 'other-dir/dir/file' })
end

T['File manipulation']['special cases']['into affected directory']['copy into renamed'] = function()
  local temp_dir = make_temp_dir('temp', { 'dir/', 'file' })
  open(temp_dir)
  type_keys('G', 'yy', 'gg')
  go_in()
  type_keys('P')
  go_out()
  type_keys('C', 'new-dir', '<Esc>')
  mock_confirm(1)
  synchronize()

  validate_tree(temp_dir, { 'file', 'new-dir/', 'new-dir/file' })
end

T['File manipulation']['entry with newline'] = function()
  if helpers.is_windows() then MiniTest.skip('Newline characters in names are not supported on Windows') end
  local temp_dir = make_temp_dir('temp', { 'di\nr/', 'fi\nl\ne' })
  open(temp_dir)
  -- NOTE: copy/move/rename *will* replace '\n' with escaped version, though
  type_keys('cc', 'new-dir/', '<Esc>')
  mock_confirm(1)
  synchronize()
  validate_confirm_args('DELETE │ di<NL>r')

  validate_tree(temp_dir, { 'new-dir/', 'fi\nl\ne' })
end

T['File manipulation']['special cases']['nested move'] = new_set()

T['File manipulation']['special cases']['nested move']['works'] = function()
  local temp_dir = make_temp_dir('temp', { 'dir-a/', 'dir-a/dir-b/', 'dir-a/dir-b/dir-c/', 'dir-a/dir-b/dir-c/file' })
  open(temp_dir .. '/dir-a/dir-b')
  type_keys('dd')
  go_out()
  go_out()
  type_keys('p')
  type_keys('gg')
  go_in()
  type_keys('dd')
  go_out()
  type_keys('p')
  mock_confirm(1)
  synchronize()

  validate_tree(temp_dir, { 'dir-a/', 'dir-b/', 'dir-c/', 'dir-c/file' })
end

T['Cursors'] = new_set()

T['Cursors']['are preserved'] = function()
  open(test_dir_path)

  -- During navigation
  type_keys('j')
  go_in()
  go_in()
  go_out()
  validate_cur_line(1)
  type_keys('j')

  go_out()
  validate_cur_line(2)

  go_in()
  validate_cur_line(2)

  -- In hidden buffers
  go_out()
  trim_left()
  go_in()
  validate_cur_line(2)

  -- When opening from history
  close()
  open(test_dir_path, true)
  validate_cur_line(2)
  go_out()
  validate_cur_line(2)
end

T['Cursors']['not allowed to the left of the entry name'] = function()
  open(test_dir_path)
  local cursor = get_cursor()

  -- Normal mode
  type_keys('b')
  eq(get_cursor(), cursor)
  type_keys('10b')
  eq(get_cursor(), cursor)
  type_keys('0')
  eq(get_cursor(), cursor)

  set_cursor(cursor[1], 0)
  eq(get_cursor(), cursor)

  -- Insert mode
  type_keys('i')
  type_keys('<Left>')
  eq(get_cursor(), cursor)
end

T['Cursors']['handle `content.prefix` returning different lengths'] = function()
  child.lua([[
    _G.cur_prefix = ''
    MiniFiles.config.content.prefix = function()
      local res_prefix = _G.cur_prefix
      _G.cur_prefix = _G.cur_prefix .. '+'
      return res_prefix, 'Comment'
    end
  ]])

  open(test_dir_path)
  child.expect_screenshot()

  local cur_cursor = get_cursor()
  eq(cur_cursor, { 1, 4 })

  local offset = 0
  local validate_cursor = function()
    type_keys('j')
    offset = offset + 1
    eq(get_cursor(), { cur_cursor[1] + offset, cur_cursor[2] + offset })
  end

  validate_cursor()
  validate_cursor()
  validate_cursor()
end

T['Cursors']['shows whole line after horizontal scroll'] = function()
  child.set_size(10, 60)

  open(test_dir_path)

  type_keys('7zl')
  child.expect_screenshot()

  type_keys('2B')
  child.expect_screenshot()
end

T['Events'] = new_set()

local track_event = function(event_name)
  child.lua('_G.event_name = ' .. vim.inspect(event_name))
  local lua_cmd = [[
    _G.callback_args_data = {}
    local f = function(args) table.insert(_G.callback_args_data, args.data or {}) end
    vim.api.nvim_create_autocmd('User', { pattern = _G.event_name, callback = f })
  ]]
  child.lua(lua_cmd)
end

local get_event_track = function() return child.lua_get('_G.callback_args_data') end

local clear_event_track = function() child.lua('_G.callback_args_data = {}') end

local validate_event_track = function(ref, do_sort)
  local event_track = child.lua_get('_G.callback_args_data')

  if do_sort then table.sort(event_track, function(a, b) return a.buf_id < b.buf_id end) end
  eq(event_track, ref)
end

local validate_n_events = function(n_ref) eq(#child.lua_get('_G.callback_args_data'), n_ref) end

T['Events']['`MiniFilesExplorerOpen` triggers'] = function()
  track_event('MiniFilesExplorerOpen')
  child.cmd('au User MiniFilesExplorerOpen lua _G.windows = vim.api.nvim_list_wins()')

  open(test_dir_path)
  validate_event_track({ {} })
  -- Should trigger after all windows are opened
  eq(#child.lua_get('_G.windows'), 2)
  clear_event_track()

  close()
  validate_event_track({})

  open(test_dir_path)
  validate_event_track({ {} })
end

T['Events']['`MiniFilesExplorerClose` triggers'] = function()
  track_event('MiniFilesExplorerClose')
  child.cmd('au User MiniFilesExplorerClose lua _G.windows = vim.api.nvim_list_wins()')

  open(test_dir_path)
  validate_event_track({})
  clear_event_track()

  close()
  validate_event_track({ {} })
  -- Should trigger before all windows are closed
  eq(#child.lua_get('_G.windows'), 2)
  clear_event_track()

  open(test_dir_path)
  validate_event_track({})
  clear_event_track()

  close()
  validate_event_track({ {} })
end

T['Events']['`MiniFilesBufferCreate` triggers'] = function()
  track_event('MiniFilesBufferCreate')
  child.lua([[
    local f = function(args) _G.buf_name = vim.api.nvim_buf_get_name(args.data.buf_id) end
    vim.api.nvim_create_autocmd('User', { pattern = 'MiniFilesBufferCreate', callback = f })
  ]])

  local open_path = full_path(test_dir_path)

  open(open_path)
  local buf_cur = child.api.nvim_get_current_buf()
  validate_event_track({ { buf_id = buf_cur } })
  -- - Should be already properly named
  eq(child.lua_get('_G.buf_name'), 'minifiles://' .. buf_cur .. '/' .. open_path)
  clear_event_track()

  go_in()
  buf_cur = child.api.nvim_get_current_buf()
  validate_event_track({ { buf_id = buf_cur } })
  eq(child.lua_get('_G.buf_name'), 'minifiles://' .. buf_cur .. '/' .. join_path(open_path, '.a-dir'))
  clear_event_track()

  -- No event should be triggered if buffer is reused
  go_out()
  trim_right()
  go_in()

  validate_event_track({})
end

T['Events']['`MiniFilesBufferCreate` triggers inside preview'] = function()
  track_event('MiniFilesBufferCreate')

  child.lua('MiniFiles.config.windows.preview = true')
  open(test_dir_path)
  validate_n_events(2)

  type_keys('j')
  validate_n_events(3)

  -- No event should be triggered when going inside previewed directory (as
  -- buffer should be reused). But should also be triggered for file previews.
  clear_event_track()
  type_keys('k')
  go_in()
  validate_n_events(1)

  -- No event should trigger for imaginary path
  clear_event_track()
  type_keys('o')
  validate_n_wins(3)
  validate_n_events(0)

  type_keys('imaginary-file')
  validate_n_wins(3)
  validate_n_events(0)
end

T['Events']['`MiniFilesBufferCreate` can be used to create buffer-local mappings'] = function()
  child.lua([[
    _G.n = 0
    local rhs = function() _G.n = _G.n + 1 end
    vim.api.nvim_create_autocmd(
      'User',
      {
        pattern = 'MiniFilesBufferCreate',
        callback = function(args) vim.keymap.set('n', 'W', rhs, { buffer = args.data.buf_id }) end,
      }
    )
  ]])

  type_keys('W')
  eq(child.lua_get('_G.n'), 0)

  open(test_dir_path)
  type_keys('W')
  eq(child.lua_get('_G.n'), 1)

  go_in()
  type_keys('W')
  eq(child.lua_get('_G.n'), 2)
end

T['Events']['`MiniFilesBufferUpdate` triggers'] = function()
  track_event('MiniFilesBufferUpdate')

  open(test_dir_path)
  local buf_id_1, win_id_1 = child.api.nvim_get_current_buf(), child.api.nvim_get_current_win()
  -- No `win_id` on first buffer update
  validate_event_track({ { buf_id = buf_id_1 } })
  clear_event_track()

  -- Force buffer updates
  synchronize()
  validate_event_track({ { buf_id = buf_id_1, win_id = win_id_1 } })
  clear_event_track()

  go_in()
  local buf_id_2, win_id_2 = child.api.nvim_get_current_buf(), child.api.nvim_get_current_win()
  validate_event_track({ { buf_id = buf_id_2 } })
  clear_event_track()

  -- Force all buffers to update
  synchronize()

  -- - Force order, as there is no order guarantee of event trigger
  validate_event_track({ { buf_id = buf_id_1, win_id = win_id_1 }, { buf_id = buf_id_2, win_id = win_id_2 } }, true)
end

T['Events']['`MiniFilesBufferUpdate` triggers inside preview'] = function()
  track_event('MiniFilesBufferUpdate')

  child.lua('MiniFiles.config.windows.preview = true')
  open(test_dir_path)
  validate_n_events(2)

  type_keys('j')
  validate_n_events(3)

  -- Should be triggered when going inside previewed directory (as different
  -- buffer becomes current).
  clear_event_track()
  type_keys('k')
  go_in()
  validate_n_events(2)

  -- No event should trigger for imaginary path
  clear_event_track()
  type_keys('o')
  validate_n_wins(3)
  validate_n_events(0)

  type_keys('imaginary-file')
  validate_n_wins(3)
  validate_n_events(0)
end

T['Events']['`MiniFilesWindowOpen` triggers'] = function()
  track_event('MiniFilesWindowOpen')

  open(test_dir_path)
  local buf_id_1, win_id_1 = child.api.nvim_get_current_buf(), child.api.nvim_get_current_win()
  -- Should provide both `buf_id` and `win_id`
  validate_event_track({ { buf_id = buf_id_1, win_id = win_id_1 } })
  clear_event_track()

  go_in()
  local buf_id_2, win_id_2 = child.api.nvim_get_current_buf(), child.api.nvim_get_current_win()
  validate_event_track({ { buf_id = buf_id_2, win_id = win_id_2 } })
  clear_event_track()

  -- Should indicate reused buffer but not window
  go_out()
  trim_right()
  go_in()
  local win_id_3 = child.api.nvim_get_current_win()
  validate_event_track({ { buf_id = buf_id_2, win_id = win_id_3 } })
end

T['Events']['`MiniFilesWindowOpen` can be used to tweak window config'] = function()
  child.lua([[
    vim.api.nvim_create_autocmd('User', {
      pattern = 'MiniFilesWindowOpen',
      callback = function(args)
        local win_id = args.data.win_id
        local config = vim.api.nvim_win_get_config(win_id)
        config.border, config.title_pos = 'double', 'right'
        vim.api.nvim_win_set_config(win_id, config)
      end,
    })
  ]])

  open(test_dir_path)
  child.expect_screenshot()

  go_in()
  child.expect_screenshot()

  go_out()
  trim_right()
  go_in()
  child.expect_screenshot()
end

T['Events']['`MiniFilesWindowUpdate` triggers'] = function()
  track_event('MiniFilesWindowUpdate')

  open(test_dir_path)
  local buf_id_1, win_id_1 = child.api.nvim_get_current_buf(), child.api.nvim_get_current_win()
  -- Triggered several times because `CursorMoved` also triggeres it.
  -- Should provide both `buf_id` and `win_id`.
  validate_event_track({ { buf_id = buf_id_1, win_id = win_id_1 }, { buf_id = buf_id_1, win_id = win_id_1 } })
  clear_event_track()

  go_in()
  local buf_id_2, win_id_2 = child.api.nvim_get_current_buf(), child.api.nvim_get_current_win()

  -- - Both windows should be updated
  validate_event_track(
    {
      { buf_id = buf_id_1, win_id = win_id_1 },
      { buf_id = buf_id_1, win_id = win_id_1 },
      { buf_id = buf_id_2, win_id = win_id_2 },
      { buf_id = buf_id_2, win_id = win_id_2 },
    },
    -- - Force order, as there is no order guarantee of event trigger
    true
  )
end

T['Events']['`MiniFilesWindowUpdate` is triggered after every possible window config update'] = function()
  track_event('MiniFilesWindowUpdate')

  open(test_dir_path)
  clear_event_track()

  -- Windows have to adjust configs on every cursor move if preview is set
  child.lua('MiniFiles.config.windows.preview = true')

  local validate = function(keys)
    clear_event_track()
    type_keys(keys)
    eq(#get_event_track() > 0, true)
  end

  validate('j')
  validate('<Right>')
  validate({ 'i', '<Left>' })

  -- NOTE: Currently this event also is triggered on every cursor move even if
  -- preview is not enabled. This is to simplify code.
end

T['Events']['`MiniFilesWindowUpdate` is triggered after current buffer is set'] = function()
  track_event('MiniFilesWindowUpdate')
  open(test_dir_path)
  clear_event_track()
  go_out()
  validate_event_track({
    { buf_id = 2, win_id = 1004 },
    { buf_id = 2, win_id = 1004 },
    { buf_id = 3, win_id = 1003 },
    { buf_id = 3, win_id = 1003 },
  }, true)
end

T['Events']['`MiniFilesWindowUpdate` can customize internally set window config parts'] = function()
  local expect_screenshot = child.expect_screenshot
  if child.fn.has('nvim-0.10') == 0 then
    local expect_orig = expect_screenshot
    expect_screenshot = function() child.expect_screenshot({ ignore_attr = true }) end
  end
  child.set_size(15, 80)

  load_module({
    windows = {
      preview = true,
      width_focus = 40,
      width_nofocus = 10,
      width_preview = 20,
    },
  })

  child.lua([[
    vim.api.nvim_create_autocmd('User', {
      pattern = 'MiniFilesWindowUpdate',
      callback = function(args)
        local config = vim.api.nvim_win_get_config(args.data.win_id)
        -- Ensure fixed height
        config.height = 5
        -- Ensure title padding
        local n = #config.title
        config.title[1][1] = config.title[1][1]:gsub('^ ', '')
        config.title[n][1] = config.title[n][1]:gsub(' $', '')
        vim.api.nvim_win_set_config(args.data.win_id, config)
      end
    })
  ]])

  open(test_dir_path)
  go_in()
  expect_screenshot()

  -- Works in Insert mode when number of entries is less than height
  type_keys('o', 'a', 'b', 'c')
  expect_screenshot()
  child.ensure_normal_mode()

  -- Works in Insert mode when number of entries is more than height
  go_out()
  type_keys('o', 'd', 'e', 'f')
  expect_screenshot()
  child.ensure_normal_mode()

  -- Works when modifying below last visible line
  type_keys('3j', 'o', 'a')
  expect_screenshot()

  -- Works even if completion menu (like from 'mini.completion') is triggered
  child.cmd('set iskeyword+=-')
  type_keys('<C-n>')
  expect_screenshot()
end

T['Events']['`MiniFilesActionCreate` triggers'] = function()
  track_event('MiniFilesActionCreate')

  local validate = function(entry, inject_external_create)
    local temp_dir = make_temp_dir('temp', {})
    local entry_name = entry:gsub('(.)/$', '%1')
    local entry_path = join_path(temp_dir, entry_name)
    open(temp_dir, false)

    -- Perform create
    type_keys('i', entry, '<Esc>')

    mock_confirm(1)
    if inject_external_create then child.fn.writefile({}, entry_path) end
    synchronize()

    -- If there was external create, then action was not successful and thus
    -- event should not trigger
    local ref = inject_external_create and {} or { { action = 'create', to = entry_path } }
    validate_event_track(ref)

    -- Cleanup
    close()
    child.fn.delete(temp_dir, 'rf')
    clear_event_track()
  end

  validate('file', false)
  validate('file', true)
  validate('dir/', false)
  validate('dir/', true)
end

T['Events']['`MiniFilesActionDelete` triggers'] = function()
  track_event('MiniFilesActionDelete')

  local validate = function(entry, inject_external_delete)
    local temp_dir = make_temp_dir('temp', { entry })
    local entry_name = entry:gsub('(.)/$', '%1')
    local entry_path = join_path(temp_dir, entry_name)
    open(temp_dir, false)

    -- Perform delete
    type_keys('dd')

    mock_confirm(1)
    if inject_external_delete then child.fn.delete(entry_path, 'rf') end
    synchronize()

    -- If there was external delete, then action was not successful and thus
    -- event should not trigger
    local ref = inject_external_delete and {} or { { action = 'delete', from = entry_path } }
    validate_event_track(ref)

    -- Cleanup
    close()
    child.fn.delete(temp_dir, 'rf')
    clear_event_track()
  end

  validate('file', false)
  validate('file', true)
  validate('dir/', false)
  validate('dir/', true)
end

T['Events']['`MiniFilesActionDelete` triggers for `options.permanent_delete = false`'] = function()
  track_event('MiniFilesActionDelete')

  local data_dir = mock_stdpath_data()
  local trash_dir = join_path(data_dir, 'mini.files', 'trash')
  child.lua('MiniFiles.config.options.permanent_delete = false')
  local temp_dir = make_temp_dir('temp', { 'file', 'dir/', 'dir/subfile' })
  open(temp_dir)

  type_keys('VGd')
  mock_confirm(1)
  synchronize()

  local event_track = get_event_track()
  table.sort(event_track, function(a, b) return a.from < b.from end)
  -- Should also supply `to` field with path to trash
  eq(event_track, {
    { action = 'delete', from = join_path(temp_dir, 'dir'), to = join_path(trash_dir, 'dir') },
    { action = 'delete', from = join_path(temp_dir, 'file'), to = join_path(trash_dir, 'file') },
  })
end

T['Events']['`MiniFilesActionRename` triggers'] = function()
  track_event('MiniFilesActionRename')

  local validate = function(entry, inject_external_delete)
    local temp_dir = make_temp_dir('temp', { entry })
    local entry_name = entry:gsub('(.)/$', '%1')
    local entry_path = join_path(temp_dir, entry_name)
    open(temp_dir, false)

    -- Perform rename
    type_keys('A', '-new', '<Esc>')
    local new_entry_path = join_path(temp_dir, entry_name .. '-new')

    mock_confirm(1)
    if inject_external_delete then child.fn.delete(entry_path, 'rf') end
    synchronize()

    -- If there was external delete, then action was not successful and thus
    -- event should not trigger
    local ref = inject_external_delete and {} or { { action = 'rename', from = entry_path, to = new_entry_path } }
    validate_event_track(ref)

    -- Cleanup
    close()
    child.fn.delete(temp_dir, 'rf')
    clear_event_track()
  end

  validate('file', false)
  validate('file', true)
  validate('dir/', false)
  validate('dir/', true)
end

T['Events']['`MiniFilesActionCopy` triggers'] = function()
  track_event('MiniFilesActionCopy')

  local validate = function(entry, inject_external_delete)
    local temp_dir = make_temp_dir('temp', { entry })
    if entry == 'dir/' then
      -- Test on non-empty directory
      child.fn.mkdir(join_path(temp_dir, 'dir', 'subdir'))
      child.fn.writefile({}, join_path(temp_dir, 'dir', 'subdir', 'subfile'))
    end

    local entry_name = entry:gsub('(.)/$', '%1')
    local entry_path = join_path(temp_dir, entry_name)
    open(temp_dir, false)

    -- Perform copy in same parent directory
    type_keys('yy', 'p', 'A', '-new', '<Esc>')
    local new_entry_path = join_path(temp_dir, entry_name .. '-new')

    mock_confirm(1)
    if inject_external_delete then child.fn.delete(entry_path, 'rf') end
    synchronize()

    -- If there was external delete, then action was not successful and thus
    -- event should not trigger
    local ref = inject_external_delete and {} or { { action = 'copy', from = entry_path, to = new_entry_path } }
    validate_event_track(ref)

    -- Cleanup
    close()
    child.fn.delete(temp_dir, 'rf')
    clear_event_track()
  end

  validate('file', false)
  validate('file', true)
  validate('dir/', false)
  validate('dir/', true)
end

T['Events']['`MiniFilesActionMove` triggers'] = function()
  track_event('MiniFilesActionMove')

  local validate = function(entry, inject_external_delete)
    local temp_dir = make_temp_dir('temp', { entry, 'a-dir/' })
    local entry_name = entry:gsub('(.)/$', '%1')
    local entry_path = join_path(temp_dir, entry_name)
    open(temp_dir, false)

    -- Perform move
    type_keys('j', 'dd', 'l', 'p')
    local new_entry_path = join_path(temp_dir, 'a-dir', entry_name)

    mock_confirm(1)
    if inject_external_delete then child.fn.delete(entry_path, 'rf') end
    synchronize()

    -- If there was external delete, then action was not successful and thus
    -- event should not trigger
    local ref = inject_external_delete and {} or { { action = 'move', from = entry_path, to = new_entry_path } }
    validate_event_track(ref)

    -- Cleanup
    close()
    child.fn.delete(temp_dir, 'rf')
    clear_event_track()
  end

  validate('file', false)
  validate('file', true)
  validate('dir/', false)
  validate('dir/', true)
end

T['Default explorer'] = new_set()

T['Default explorer']['works on startup'] = function()
  vim.loop.os_setenv('USE_AS_DEFAULT_EXPLORER', 'true')
  child.restart({ '-u', make_test_path('init-default-explorer.lua'), '--', test_dir_path })
  child.expect_screenshot()

  -- Should hide scratch buffer on file open
  type_keys('G')
  go_in()
  close()
  eq(#child.api.nvim_list_bufs(), 1)
end

T['Default explorer']['respects `options.use_as_default_explorer`'] = function()
  vim.loop.os_setenv('USE_AS_DEFAULT_EXPLORER', 'false')
  child.restart({ '-u', make_test_path('init-default-explorer.lua'), '--', test_dir_path })
  eq(child.bo.filetype, 'netrw')
end

T['Default explorer']['works in `:edit .`'] = function()
  child.cmd('edit ' .. test_dir_path)
  child.expect_screenshot()
end

T['Default explorer']['works in `:vsplit .`'] = function()
  child.cmd('vsplit ' .. test_dir_path)
  child.expect_screenshot()

  type_keys('G')
  go_in()
  close()
  child.expect_screenshot()
  eq(#child.api.nvim_list_bufs(), 2)
end

T['Default explorer']['works in `:tabfind .`'] = function()
  child.set_size(15, 60)
  child.o.showtabline = 0
  child.o.laststatus = 0

  child.cmd('tabfind ' .. test_dir_path)
  child.expect_screenshot()

  type_keys('G')
  go_in()
  close()
  child.expect_screenshot()
  eq(#child.api.nvim_list_bufs(), 2)
  eq(#child.api.nvim_list_tabpages(), 2)
  eq(child.cmd('messages'), '')
end

T['Default explorer']['handles close without opening file'] = function()
  child.cmd('wincmd v')
  child.cmd('edit ' .. test_dir_path)
  child.expect_screenshot()

  -- Should close and smartly (preserving layout) delete "directory buffer"
  close()
  child.expect_screenshot()
  eq(child.api.nvim_buf_get_name(0), '')
  eq(#child.api.nvim_list_bufs(), 1)
end

return T
