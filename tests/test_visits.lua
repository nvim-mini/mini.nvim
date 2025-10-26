local helpers = dofile('tests/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('visits', config) end
local unload_module = function() child.mini_unload('visits') end
local type_keys = function(...) return child.type_keys(...) end
local sleep = function(ms) helpers.sleep(ms, child, true) end
local edit = function(path) child.cmd('edit ' .. child.fn.fnameescape(path)) end
local child_time = function() return child.lua_get('os.time()') end
--stylua: ignore end

-- Test paths helpers
local join_path = function(...) return table.concat({ ... }, '/') end

local full_path = function(x) return (child.fn.fnamemodify(x, ':p'):gsub('\\', '/'):gsub('/+', '/'):gsub('(.)/$', '%1')) end

local test_dir = 'tests/dir-visits'
local test_dir_absolute = vim.fn.fnamemodify(test_dir, ':p'):gsub('\\', '/'):gsub('(.)/$', '%1')
local xdg_data_home = test_dir_absolute
local data_std_path = xdg_data_home .. (helpers.is_windows() and '/nvim-data' or '/nvim')

local make_testpath = function(...) return join_path(test_dir_absolute, ...) end

local cleanup_index_file = function()
  -- Clean up possibly written index file as it affects multiple test cases
  local default_index_path = data_std_path .. '/mini-visits-index'
  if vim.fn.filereadable(default_index_path) == 0 then return end
  vim.fn.delete(default_index_path)
end

-- Common test wrappers
local forward_lua = function(fun_str)
  local lua_cmd = fun_str .. '(...)'
  return function(...) return child.lua_get(lua_cmd, { ... }) end
end

local get_index = forward_lua('MiniVisits.get_index')
local set_index = forward_lua('MiniVisits.set_index')

local getcwd = function() return (child.fn.getcwd():gsub('\\', '/')) end

local new_uri_scratch_buf = function()
  local buf_id = child.api.nvim_create_buf(false, true)
  child.api.nvim_buf_set_name(buf_id, 'xxx://hello/world')
  return buf_id
end

-- Common test helpers
local validate_buf_name = function(buf_id, name)
  buf_id = buf_id or child.api.nvim_get_current_buf()
  name = name ~= '' and full_path(name) or ''
  name = name:gsub('/+$', '')
  eq(child.api.nvim_buf_get_name(buf_id):gsub('\\', '/'), name)
end

local validate_partial_equal = function(test_tbl, ref_tbl)
  eq(type(test_tbl), 'table')

  local test_with_ref_keys = {}
  for key, _ in pairs(ref_tbl) do
    test_with_ref_keys[key] = test_tbl[key]
  end
  eq(test_with_ref_keys, ref_tbl)
end

local validate_index_entry = function(cwd, path, ref)
  local index = child.lua_get('MiniVisits.get_index()')
  local out = (index[full_path(cwd)] or {})[full_path(path)]
  if ref == nil then
    eq(out, nil)
  else
    validate_partial_equal(out, ref)
  end
end

local make_ref_index_full = function(ref_index)
  local ref_full = {}
  for cwd, cwd_tbl in pairs(ref_index) do
    local cwd_tbl_full = {}
    for path, path_tbl in pairs(cwd_tbl) do
      cwd_tbl_full[make_testpath(path)] = path_tbl
    end
    ref_full[make_testpath(cwd)] = cwd_tbl_full
  end
  return ref_full
end

local set_index_from_ref = function(ref) set_index(make_ref_index_full(ref)) end

-- Common mocks
local mock_ui_select = function(choice_index)
  local lua_cmd = string.format(
    [[
    _G.ui_select_log = {}
    vim.ui.select = function(items, opts, on_choice)
      table.insert(_G.ui_select_log, { items = items, prompt = opts.prompt })
      on_choice(items[%s], %s)
    end]],
    choice_index,
    choice_index
  )
  child.lua(lua_cmd)
end

local get_ui_select_log = function() return child.lua_get('_G.ui_select_log') end

-- Time constants
local default_track_delay = 1000
local small_time = helpers.get_time_const(10)
local test_track_delay = 2 * small_time

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      cleanup_index_file()

      -- Make `stdpath('data')` point to test directory
      local lua_cmd = string.format([[vim.uv.os_setenv('XDG_DATA_HOME', %s)]], vim.inspect(xdg_data_home))
      child.lua(lua_cmd)

      -- Load module
      load_module()

      -- Make more comfortable screenshots
      child.set_size(5, 60)
      child.o.laststatus = 0
      child.o.ruler = false
    end,
    post_once = function()
      child.stop()
      cleanup_index_file()
      vim.fn.delete(data_std_path, 'rf')
    end,
  },
  n_retry = helpers.get_n_retry(2),
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  -- Global variable
  eq(child.lua_get('type(_G.MiniVisits)'), 'table')

  -- Autocommand group
  eq(child.fn.exists('#MiniVisits'), 1)
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniVisits.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniVisits.config.' .. field), value) end

  expect_config('list.filter', vim.NIL)
  expect_config('list.filter', vim.NIL)

  expect_config('silent', false)

  expect_config('store.autowrite', true)
  expect_config('store.normalize', vim.NIL)
  expect_config('store.path', child.fn.stdpath('data') .. '/mini-visits-index')

  expect_config('track.event', 'BufEnter')
  expect_config('track.delay', 1000)
end

T['setup()']['respects `config` argument'] = function()
  unload_module()
  load_module({ silent = true })
  eq(child.lua_get('MiniVisits.config.silent'), true)
end

T['setup()']['validates `config` argument'] = function()
  unload_module()

  local expect_config_error = function(config, name, target_type)
    expect.error(load_module, vim.pesc(name) .. '.*' .. vim.pesc(target_type), config)
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ list = 'a' }, 'list', 'table')
  expect_config_error({ list = { filter = 'a' } }, 'list.filter', 'function')
  expect_config_error({ list = { sort = 'a' } }, 'list.sort', 'function')

  expect_config_error({ silent = 'a' }, 'silent', 'boolean')

  expect_config_error({ store = 'a' }, 'store', 'table')
  expect_config_error({ store = { autowrite = 'a' } }, 'store.autowrite', 'boolean')
  expect_config_error({ store = { normalize = 'a' } }, 'store.normalize', 'function')
  expect_config_error({ store = { path = 1 } }, 'store.path', 'string')

  expect_config_error({ track = 'a' }, 'track', 'table')
  expect_config_error({ track = { event = 1 } }, 'track.event', 'string')
  expect_config_error({ track = { delay = 'a' } }, 'track.delay', 'number')
end

T['register_visit()'] = new_set()

local register_visit = forward_lua('MiniVisits.register_visit')

T['register_visit()']['works'] = function()
  -- Should not check if arguments represent present paths on disk
  local file_full, file_2_full = full_path('file'), full_path('dir/file-2')
  local dir_full, dir_2_full = full_path('dir'), full_path('dir-2')

  -- Should create entry if it is not present treating input as file system
  -- entries (relative to current directory in this case)
  eq(get_index(), {})
  register_visit('file', 'dir')
  eq(get_index(), { [dir_full] = { [file_full] = { count = 1, latest = child_time() } } })

  register_visit('file', 'dir')
  local latest_1 = child_time()
  eq(get_index(), { [dir_full] = { [file_full] = { count = 2, latest = latest_1 } } })

  register_visit('dir/file-2', 'dir')
  local latest_2 = child_time()
  eq(get_index(), {
    [dir_full] = {
      [file_full] = { count = 2, latest = latest_1 },
      [file_2_full] = { count = 1, latest = latest_2 },
    },
  })

  register_visit('file', 'dir-2')
  eq(get_index(), {
    [dir_full] = {
      [file_full] = { count = 2, latest = latest_1 },
      [file_2_full] = { count = 1, latest = latest_2 },
    },
    [dir_2_full] = {
      [file_full] = { count = 1, latest = child_time() },
    },
  })
end

T['register_visit()']['uses current data as defaults'] = function()
  local path = make_testpath('file')
  edit(path)
  register_visit()
  eq(get_index(), { [getcwd()] = { [path] = { count = 1, latest = child_time() } } })

  -- Errors on non-normal buffer
  child.api.nvim_set_current_buf(new_uri_scratch_buf())
  expect.error(register_visit, 'not for a regular file')
end

T['register_visit()']['handles paths with "~" for home directory'] = function()
  register_visit('~/file', '~/dir')
  local home_dir = child.loop.os_homedir():gsub('\\', '/')
  eq(
    get_index(),
    { [join_path(home_dir, 'dir')] = { [join_path(home_dir, 'file')] = { count = 1, latest = child_time() } } }
  )
end

T['register_visit()']['does not affect other stored data'] = function()
  local path, cwd = make_testpath('file'), test_dir_absolute
  set_index({ [cwd] = { [path] = { count = 0, latest = 0, aaa = { bbb = true } } } })
  register_visit(path, cwd)
  eq(get_index(), { [cwd] = { [path] = { count = 1, latest = child_time(), aaa = { bbb = true } } } })
end

T['register_visit()']['validates arguments'] = function()
  local validate = function(error_pattern, ...)
    local args = { ... }
    expect.error(function() register_visit(unpack(args)) end, error_pattern)
  end

  validate('`path`.*string', 1, 'dir')
  validate('`cwd`.*string', 'file', 1)
  validate('`path` and `cwd`.*not.*empty', '', 'dir')
  validate('`path` and `cwd`.*not.*empty', 'file', '')
end

T['add_path()'] = new_set()

local add_path = forward_lua('MiniVisits.add_path')

T['add_path()']['works'] = function()
  -- Should not check if arguments represent present paths on disk
  local dir_full = full_path('dir')
  local file_full, file_2_full = full_path('file'), full_path('file-2')

  add_path('file', 'dir')
  eq(get_index(), { [dir_full] = { [file_full] = { count = 0, latest = 0 } } })

  -- Should do nothing if path-cwd already exists
  add_path('file', 'dir')
  eq(get_index(), { [dir_full] = { [file_full] = { count = 0, latest = 0 } } })

  add_path('file-2', 'dir')
  eq(
    get_index(),
    { [dir_full] = { [file_full] = { count = 0, latest = 0 }, [file_2_full] = { count = 0, latest = 0 } } }
  )
end

T['add_path()']['works with empty string arguments'] = function()
  local file_full, file_2_full = full_path('file'), full_path('file-2')
  local dir_full, dir_2_full = full_path('dir'), full_path('dir-2')
  local init_tbl = { count = 0, latest = 0 }

  -- If no visits, should result into no added paths
  add_path('', 'dir')
  eq(get_index(), {})
  add_path('file', '')
  eq(get_index(), {})
  add_path('', '')
  eq(get_index(), {})

  -- Empty string for `path` should mean "add all present paths in cwd".
  -- Not useful, but should be allowed for consistency with other functions.
  add_path('file', 'dir')
  add_path('', 'dir')
  eq(get_index(), { [dir_full] = { [file_full] = init_tbl } })

  -- Empty string for `cwd` should mean "add path to all visited cwds".
  add_path('file', 'dir-2')
  add_path('file-2', '')
  eq(get_index(), {
    [dir_full] = { [file_full] = init_tbl, [file_2_full] = init_tbl },
    [dir_2_full] = { [file_full] = init_tbl, [file_2_full] = init_tbl },
  })
end

T['add_path()']['uses current data as defaults'] = function()
  local path = make_testpath('file')
  edit(path)
  add_path()
  eq(get_index(), { [getcwd()] = { [path] = { count = 0, latest = 0 } } })

  -- Errors on non-normal buffer
  child.api.nvim_set_current_buf(new_uri_scratch_buf())
  expect.error(add_path, 'not for a regular file')
end

T['add_path()']['does not affect other stored data'] = function()
  local path, cwd = make_testpath('file'), test_dir_absolute
  set_index({ [cwd] = { [path] = { count = 0, latest = 0, aaa = { bbb = true } } } })
  add_path(path, cwd)
  eq(get_index(), { [cwd] = { [path] = { count = 0, latest = 0, aaa = { bbb = true } } } })
end

T['add_path()']['validates arguments'] = function()
  expect.error(function() add_path(1, 'dir') end, '`path`.*string')
  expect.error(function() add_path('file', 1) end, '`cwd`.*string')
end

T['add_label()'] = new_set()

local add_label = forward_lua('MiniVisits.add_label')

T['add_label()']['works'] = function()
  -- Should not check if arguments represent present paths on disk
  local file_full, dir_full = full_path('file'), full_path('dir')

  -- Should add path if it is not present
  add_label('aaa', 'file', 'dir')
  eq(get_index(), { [dir_full] = { [file_full] = { count = 0, labels = { aaa = true }, latest = 0 } } })

  -- Should show feedback message
  child.expect_screenshot()

  -- Should add to already existing path-cwd pair
  add_label('bbb', 'file', 'dir')
  eq(get_index(), { [dir_full] = { [file_full] = { count = 0, labels = { aaa = true, bbb = true }, latest = 0 } } })

  -- Should not affect already present data
  register_visit('file', 'dir')
  add_label('ccc', 'file', 'dir')
  eq(get_index(), {
    [dir_full] = { [file_full] = { count = 1, labels = { aaa = true, bbb = true, ccc = true }, latest = child_time() } },
  })
end

T['add_label()']['works with empty string arguments'] = function()
  local file_full, file_2_full = full_path('file'), full_path('file-2')
  local dir_full, dir_2_full = full_path('dir'), full_path('dir-2')

  -- If no visits, should result into no added paths and labels
  add_path('', 'dir')
  eq(get_index(), {})
  add_path('file', '')
  eq(get_index(), {})
  add_path('', '')
  eq(get_index(), {})

  -- Empty string for `path` should mean "add to all present paths in cwd"
  add_path('file', 'dir')
  add_path('file-2', 'dir')
  add_label('aaa', '', 'dir')
  eq(get_index(), {
    [dir_full] = {
      [file_full] = { count = 0, labels = { aaa = true }, latest = 0 },
      [file_2_full] = { count = 0, labels = { aaa = true }, latest = 0 },
    },
  })

  -- Empty string for `cwd` should mean "add to path in all present cwds"
  add_path('file', 'dir-2')
  add_label('bbb', 'file', '')
  eq(get_index(), {
    [dir_full] = {
      [file_full] = { count = 0, labels = { aaa = true, bbb = true }, latest = 0 },
      [file_2_full] = { count = 0, labels = { aaa = true }, latest = 0 },
    },
    [dir_2_full] = {
      [file_full] = { count = 0, labels = { bbb = true }, latest = 0 },
    },
  })

  -- Both empty strings should mean "add to all present paths in present cwds"
  add_label('ccc', '', '')
  eq(get_index(), {
    [dir_full] = {
      [file_full] = { count = 0, labels = { aaa = true, bbb = true, ccc = true }, latest = 0 },
      [file_2_full] = { count = 0, labels = { aaa = true, ccc = true }, latest = 0 },
    },
    [dir_2_full] = {
      [file_full] = { count = 0, labels = { bbb = true, ccc = true }, latest = 0 },
    },
  })
end

T['add_label()']['uses current data as defaults for path and cwd'] = function()
  local path = make_testpath('file')
  edit(path)
  add_label('aaa')
  eq(get_index(), { [getcwd()] = { [path] = { count = 0, labels = { aaa = true }, latest = 0 } } })

  -- Errors on non-normal buffer
  child.api.nvim_set_current_buf(new_uri_scratch_buf())
  expect.error(function() add_label('aaa') end, 'not for a regular file')
end

T['add_label()']['asks user for label if it is not supplied'] = function()
  local file_full, file_2_full = full_path('file'), full_path('file-2')
  local dir_full, dir_2_full = full_path('dir'), full_path('dir-2')

  child.lua_notify([[MiniVisits.add_label(nil, 'file', 'dir')]])
  child.expect_screenshot()
  type_keys('aaa', '<CR>')
  eq(get_index(), { [dir_full] = { [file_full] = { count = 0, labels = { aaa = true }, latest = 0 } } })

  -- Has completion with all labels from target cwd
  add_label('abb', 'file-2', 'dir')
  add_label('bbb', 'file', 'dir')
  add_label('ccc', 'file', 'dir-2')
  add_label('ddd', 'file-2', 'dir-2')

  child.lua_notify([[MiniVisits.add_label(nil, 'file', 'dir')]])
  type_keys('<Tab>')
  child.expect_screenshot()

  -- - Should properly filter it
  type_keys('<C-e>', 'a', '<Tab>')
  child.expect_screenshot()

  -- - Can be canceled without adding any label
  type_keys('<C-c>')
  eq(get_index(), {
    [dir_full] = {
      [file_full] = { count = 0, labels = { aaa = true, bbb = true }, latest = 0 },
      [file_2_full] = { count = 0, labels = { abb = true }, latest = 0 },
    },
    [dir_2_full] = {
      [file_full] = { count = 0, labels = { ccc = true }, latest = 0 },
      [file_2_full] = { count = 0, labels = { ddd = true }, latest = 0 },
    },
  })
end

T['add_label()']['does not affect other stored data'] = function()
  local path, cwd = make_testpath('file'), test_dir_absolute
  set_index({ [cwd] = { [path] = { count = 0, latest = 0, aaa = { bbb = true } } } })
  add_label('xxx', path, cwd)
  eq(get_index(), { [cwd] = { [path] = { count = 0, labels = { xxx = true }, latest = 0, aaa = { bbb = true } } } })
end

T['add_label()']['validates arguments'] = function()
  expect.error(function() add_label(1, 'file', 'dir') end, '`label`.*string')
  expect.error(function() add_label('aaa', 1, 'dir') end, '`path`.*string')
  expect.error(function() add_label('aaa', 'file', 1) end, '`cwd`.*string')
end

T['remove_path()'] = new_set()

local remove_path = forward_lua('MiniVisits.remove_path')

T['remove_path()']['works'] = function()
  -- Should not check if arguments represent present paths on disk
  local dir_full = full_path('dir')
  local file_full, file_2_full = full_path('file'), full_path('file-2')

  add_path('file', 'dir')
  eq(get_index(), { [dir_full] = { [file_full] = { count = 0, latest = 0 } } })
  remove_path('file', 'dir')
  eq(get_index(), {})

  -- Should do nothing if path-cwd already absent
  remove_path('file', 'dir')
  eq(get_index(), {})
end

T['remove_path()']['works with empty string arguments'] = function()
  local file_full, file_2_full = full_path('file'), full_path('file-2')
  local dir_full, dir_2_full = full_path('dir'), full_path('dir-2')
  local init_tbl = { count = 0, latest = 0 }

  -- If no visits, should result into no errors
  remove_path('', 'dir')
  eq(get_index(), {})
  remove_path('file', '')
  eq(get_index(), {})
  remove_path('', '')
  eq(get_index(), {})

  -- Empty string for `path` should mean "remove all present paths in cwd".
  add_path('file', 'dir')
  add_path('file-2', 'dir')
  add_path('file', 'dir-2')
  remove_path('', 'dir')
  eq(get_index(), { [dir_2_full] = { [file_full] = init_tbl } })

  -- Empty string for `cwd` should mean "remove path from all visited cwds".
  add_path('file', 'dir')
  add_path('file-2', 'dir')
  remove_path('file', '')
  eq(get_index(), { [dir_full] = { [file_2_full] = init_tbl } })

  -- Both empty strings should essentially mean "remove all present"
  add_path('file', 'dir')
  add_path('file-2', 'dir')
  remove_path('', '')
  eq(get_index(), {})
end

T['remove_path()']['uses current data as defaults'] = function()
  local path = make_testpath('file')
  edit(path)
  add_path()
  eq(get_index(), { [getcwd()] = { [path] = { count = 0, latest = 0 } } })

  remove_path()
  eq(get_index(), {})

  -- Errors on non-normal buffer
  child.api.nvim_set_current_buf(new_uri_scratch_buf())
  expect.error(remove_path, 'not for a regular file')
end

T['remove_path()']['validates arguments'] = function()
  expect.error(function() remove_path(1, 'dir') end, '`path`.*string')
  expect.error(function() remove_path('file', 1) end, '`cwd`.*string')
end

T['remove_label()'] = new_set()

local remove_label = forward_lua('MiniVisits.remove_label')

T['remove_label()']['works'] = function()
  -- Should not check if arguments represent present paths on disk
  local file_full, dir_full = full_path('file'), full_path('dir')

  add_label('aaa', 'file', 'dir')
  eq(get_index(), { [dir_full] = { [file_full] = { count = 0, labels = { aaa = true }, latest = 0 } } })

  remove_label('aaa', 'file', 'dir')
  eq(get_index(), { [dir_full] = { [file_full] = { count = 0, latest = 0 } } })

  -- Should show feedback message
  child.expect_screenshot()

  -- Should not affect already present data
  register_visit('file', 'dir')
  add_label('bbb', 'file', 'dir')
  add_label('ccc', 'file', 'dir')
  remove_label('bbb', 'file', 'dir')
  eq(get_index(), {
    [dir_full] = { [file_full] = { count = 1, labels = { ccc = true }, latest = child_time() } },
  })
end

T['remove_label()']['works with empty string arguments'] = function()
  local file_full, file_2_full = full_path('file'), full_path('file-2')
  local dir_full, dir_2_full = full_path('dir'), full_path('dir-2')

  -- If no visits, should result into no error
  remove_path('', 'dir')
  eq(get_index(), {})
  remove_path('file', '')
  eq(get_index(), {})
  remove_path('', '')
  eq(get_index(), {})

  -- Empty string for `path` should mean "remove from all present paths in cwd"
  add_label('aaa', 'file', 'dir')
  add_label('aaa', 'file-2', 'dir')
  add_label('aaa', 'file', 'dir-2')
  remove_label('aaa', '', 'dir')
  eq(get_index(), {
    [dir_full] = {
      [file_full] = { count = 0, latest = 0 },
      [file_2_full] = { count = 0, latest = 0 },
    },
    [dir_2_full] = {
      [file_full] = { count = 0, labels = { aaa = true }, latest = 0 },
    },
  })

  -- Empty string for `cwd` should mean "remove from path in all present cwds"
  add_label('aaa', 'file', 'dir')
  add_label('aaa', 'file-2', 'dir')
  remove_label('aaa', 'file', '')
  eq(get_index(), {
    [dir_full] = {
      [file_full] = { count = 0, latest = 0 },
      [file_2_full] = { count = 0, labels = { aaa = true }, latest = 0 },
    },
    [dir_2_full] = {
      [file_full] = { count = 0, latest = 0 },
    },
  })

  -- Both empty should mean "remove from all present paths in present cwds"
  add_label('aaa', 'file', 'dir')
  add_label('aaa', 'file', 'dir-2')
  remove_label('aaa', '', '')
  eq(get_index(), {
    [dir_full] = {
      [file_full] = { count = 0, latest = 0 },
      [file_2_full] = { count = 0, latest = 0 },
    },
    [dir_2_full] = {
      [file_full] = { count = 0, latest = 0 },
    },
  })
end

T['remove_label()']['uses current data as defaults for path and cwd'] = function()
  local path = make_testpath('file')
  edit(path)
  add_label('aaa')
  eq(get_index(), { [getcwd()] = { [path] = { count = 0, labels = { aaa = true }, latest = 0 } } })

  remove_label('aaa')
  eq(get_index(), { [getcwd()] = { [path] = { count = 0, latest = 0 } } })

  -- Errors on non-normal buffer
  child.api.nvim_set_current_buf(new_uri_scratch_buf())
  expect.error(function() remove_label('aaa') end, 'not for a regular file')
end

T['remove_label()']['asks user for label if it is not supplied'] = function()
  local file_full, file_2_full = full_path('file'), full_path('file-2')
  local dir_full, dir_2_full = full_path('dir'), full_path('dir-2')

  add_label('aaa', 'file', 'dir')
  add_label('bbb', 'file', 'dir')

  child.lua_notify([[MiniVisits.remove_label(nil, 'file', 'dir')]])
  child.expect_screenshot()
  type_keys('aaa', '<CR>')
  eq(get_index(), { [dir_full] = { [file_full] = { count = 0, labels = { bbb = true }, latest = 0 } } })

  -- Has completion with all labels from target path-cwd pair
  add_label('aaa', 'file', 'dir')
  add_label('abb', 'file', 'dir')
  add_label('bbb', 'file', 'dir')

  add_label('ccc', 'file-2', 'dir')
  add_label('ddd', 'file', 'dir-2')

  child.lua_notify([[MiniVisits.remove_label(nil, 'file', 'dir')]])
  type_keys('<Tab>')
  child.expect_screenshot()

  -- - Should properly filter it
  type_keys('<C-e>', 'a', '<Tab>')
  child.expect_screenshot()

  -- - Can be canceled without adding any label
  type_keys('<C-c>')
  eq(get_index(), {
    [dir_full] = {
      [file_full] = { count = 0, labels = { aaa = true, abb = true, bbb = true }, latest = 0 },
      [file_2_full] = { count = 0, labels = { ccc = true }, latest = 0 },
    },
    [dir_2_full] = {
      [file_full] = { count = 0, labels = { ddd = true }, latest = 0 },
    },
  })
end

T['remove_label()']['does not affect other stored data'] = function()
  local path, cwd = make_testpath('file'), test_dir_absolute
  set_index({ [cwd] = { [path] = { count = 0, labels = { xxx = true }, latest = 0, aaa = { bbb = true } } } })
  remove_label('xxx', path, cwd)
  eq(get_index(), { [cwd] = { [path] = { count = 0, latest = 0, aaa = { bbb = true } } } })
end

T['remove_label()']['validates arguments'] = function()
  expect.error(function() remove_label(1, 'file', 'dir') end, '`label`.*string')
  expect.error(function() remove_label('aaa', 1, 'dir') end, '`path`.*string')
  expect.error(function() remove_label('aaa', 'file', 1) end, '`cwd`.*string')
end

T['list_paths()'] = new_set()

local list_paths = forward_lua('MiniVisits.list_paths')

T['list_paths()']['works'] = function()
  local cur_time = child_time()
  local ref_index = {
    dir_1 = {
      ['dir_1/file_1-1'] = { count = 2, latest = cur_time - 3 },
      ['dir_1/file_1-2'] = { count = 1, latest = cur_time - 4 },
    },
    dir_2 = {
      ['dir_2/file_2-1'] = { count = 3, latest = cur_time - 2 },
      ['dir_1/file_1-2'] = { count = 4, latest = cur_time - 1 },
    },
  }
  set_index_from_ref(ref_index)

  local validate_dir_1 = function(cwd)
    eq(list_paths(cwd), { make_testpath('dir_1', 'file_1-1'), make_testpath('dir_1', 'file_1-2') })
  end

  -- Should work with relative path `cwd`
  local rel_cwd = join_path(test_dir, 'dir_1')
  validate_dir_1(rel_cwd)

  -- Should work with absolute path `cwd`
  local abs_cwd = full_path(rel_cwd)
  validate_dir_1(abs_cwd)

  -- Should use current working directory by default
  child.fn.chdir(make_testpath('dir_1'))
  validate_dir_1(nil)

  -- Should work with empty string `cwd` meaning "all visited cwds"
  eq(
    list_paths(''),
    { make_testpath('dir_1', 'file_1-2'), make_testpath('dir_2', 'file_2-1'), make_testpath('dir_1', 'file_1-1') }
  )

  -- Should not affect the index
  eq(get_index(), make_ref_index_full(ref_index))
end

T['list_paths()']['respects `opts.filter`'] = function()
  local ref_index = {
    dir_1 = {
      ['dir_1/file_1-1'] = { count = 2, latest = 10 },
      ['dir_1/file_1-2'] = { count = 1, latest = 9 },
    },
  }
  set_index_from_ref(ref_index)

  child.lua([[
    _G.filter_args_log = {}
    _G.filter = function(...)
      table.insert(_G.filter_args_log, { ... })
      local path_data = ({ ... })[1]
      return path_data.count > 1
    end]])

  child.lua('_G.cwd = ' .. vim.inspect(make_testpath('dir_1')))
  eq(child.lua_get([[MiniVisits.list_paths(cwd, { filter = _G.filter })]]), { make_testpath('dir_1', 'file_1-1') })

  local args_log = child.lua_get('_G.filter_args_log')
  -- - Ensure same order in test, as there is no guarantee of order
  table.sort(args_log, function(a, b) return a[1].path < b[1].path end)
  eq(args_log, {
    { { count = 2, latest = 10, path = make_testpath('dir_1', 'file_1-1') } },
    { { count = 1, latest = 9, path = make_testpath('dir_1', 'file_1-2') } },
  })
end

T['list_paths()']['respects `opts.sort`'] = function()
  local ref_index = {
    dir_1 = {
      ['dir_1/file_1-1'] = { count = 2, latest = 10 },
      ['dir_1/file_1-2'] = { count = 1, latest = 9 },
    },
  }
  set_index_from_ref(ref_index)

  child.lua([[
    _G.sort_args_log = {}
    _G.sort = function(...)
      table.insert(_G.sort_args_log, { ... })
      local path_data_arr = vim.deepcopy(({ ... })[1])
      table.sort(path_data_arr, function(a, b) return a.count < b.count end)
      return path_data_arr
    end]])

  child.lua('_G.cwd = ' .. vim.inspect(make_testpath('dir_1')))
  eq(
    child.lua_get([[MiniVisits.list_paths(_G.cwd, { sort = _G.sort })]]),
    { make_testpath('dir_1', 'file_1-2'), make_testpath('dir_1', 'file_1-1') }
  )

  local args_log = child.lua_get('_G.sort_args_log')
  eq(vim.tbl_count(args_log), 1)
  local path_data_arr = args_log[1][1]
  -- - Ensure same order in test, as there is no guarantee of order
  table.sort(path_data_arr, function(a, b) return a.path < b.path end)
  eq(path_data_arr, {
    { count = 2, latest = 10, path = make_testpath('dir_1', 'file_1-1') },
    { count = 1, latest = 9, path = make_testpath('dir_1', 'file_1-2') },
  })
end

T['list_paths()']['allows `opts.sort` to return non-related array'] = function()
  child.lua([[_G.sort = function() return { { path = 'bb' }, { path = 'aa' } } end]])
  eq(child.lua_get([[MiniVisits.list_paths('', { sort = _G.sort })]]), { 'bb', 'aa' })
end

T['list_paths()']['properly merges visit data for filter and sort'] = function()
  --stylua: ignore
  local ref_index = {
    dir_1 = {
      ['dir_1/file_1-1'] = { count = 2, latest = 10, aaa = 1 },
      ['dir_1/file_1-2'] = { count = 1, latest = 9, bbb  = 'a' },
      ['file']           = { count = 1, latest = 8, data = { bool = true, num = 2, str = 'b' } },
    },
    dir_2 = {
      ['dir_1/file_1-1'] = { count = 11, latest = 100, ccc = 3 },
      ['file']           = { count = 10, latest = 1, data = { bool2 = true, num2 = 2, str2 = 'b' } },
    }
  }
  set_index_from_ref(ref_index)

  child.lua([[
    _G.filter_args_log, _G.sort_args_log = {}, {}
    _G.filter = function(...)
      table.insert(_G.filter_args_log, { ... })
      return true
    end
    _G.sort = function(...)
      table.insert(_G.sort_args_log, { ... })
      return ({...})[1]
    end]])

  child.lua_get([[MiniVisits.list_paths('', { filter = _G.filter, sort = _G.sort })]])

  -- Filter
  local filter_args_log = child.lua_get('_G.filter_args_log')
  -- - Ensure same order in test, as there is no guarantee of order
  table.sort(filter_args_log, function(a, b) return a[1].path < b[1].path end)

  eq(filter_args_log, {
    -- `count` should be summed, `latest` should be reduced with `math.max`,
    -- non-related fields should be merged
    { { count = 13, latest = 100, path = make_testpath('dir_1', 'file_1-1'), aaa = 1, ccc = 3 } },
    { { count = 1, latest = 9, path = make_testpath('dir_1', 'file_1-2'), bbb = 'a' } },
    {
      {
        count = 11,
        latest = 8,
        path = make_testpath('file'),
        data = { bool = true, bool2 = true, num = 2, num2 = 2, str = 'b', str2 = 'b' },
      },
    },
  })

  -- Sort
  local sort_args_log = child.lua_get('_G.sort_args_log')
  eq(vim.tbl_count(sort_args_log), 1)
  local path_data_arr = sort_args_log[1][1]
  -- - Ensure same order in test, as there is no guarantee of order
  table.sort(path_data_arr, function(a, b) return a.path < b.path end)

  eq(path_data_arr, {
    { count = 13, latest = 100, path = make_testpath('dir_1', 'file_1-1'), aaa = 1, ccc = 3 },
    { count = 1, latest = 9, path = make_testpath('dir_1', 'file_1-2'), bbb = 'a' },
    {
      count = 11,
      latest = 8,
      path = make_testpath('file'),
      data = { bool = true, bool2 = true, num = 2, num2 = 2, str = 'b', str2 = 'b' },
    },
  })
end

T['list_paths()']['respects `config.list`'] = function()
  set_index_from_ref({ dir_1 = { file = { count = 1, latest = 10 } } })

  child.lua([[
    _G.filter = function()
      _G.filter_been_here = true
      return true
    end
    _G.sort = function(...)
      _G.sort_been_here = true
      return ({...})[1]
    end]])
  child.lua('MiniVisits.config.list = { filter = _G.filter, sort = _G.sort }')

  list_paths('')

  eq(child.lua_get('_G.filter_been_here'), true)
  eq(child.lua_get('_G.sort_been_here'), true)
end

T['list_paths()']['validates arguments'] = function()
  expect.error(function() list_paths(1) end, '`cwd`.*string')
end

T['list_labels()'] = new_set()

local list_labels = forward_lua('MiniVisits.list_labels')

T['list_labels()']['works'] = function()
  local ref_index = {
    dir_1 = {
      ['dir_1/file_1-1'] = { count = 0, labels = { xxx = true, bbb = true }, latest = 0 },
      ['dir_1/file_1-2'] = { count = 0, labels = { xxx = true, aaa = true }, latest = 0 },
    },
    dir_2 = {
      ['dir_2/file_2-1'] = { count = 0, latest = 0 },
      ['dir_1/file_1-2'] = { count = 0, labels = { xxx = true, yyy = true }, latest = 0 },
    },
  }
  set_index_from_ref(ref_index)

  -- Should first sort by decreasing frequency of appearance for different
  -- paths. Ties should be resolved alphabetically.

  -- Should work with relative paths
  local rel_path = join_path(test_dir, 'dir_1', 'file_1-1')
  local rel_cwd = join_path(test_dir, 'dir_1')
  eq(list_labels(rel_path, rel_cwd), { 'bbb', 'xxx' })

  -- Should work with absolute paths
  local abs_path = full_path(rel_path)
  local abs_cwd = full_path(rel_cwd)
  eq(list_labels(abs_path, abs_cwd), { 'bbb', 'xxx' })

  -- Should use current file and directory as defaults
  child.fn.chdir(make_testpath('dir_1'))
  edit('file_1-1')
  eq(list_labels(), { 'bbb', 'xxx' })

  -- Should work with empty string `path` meaning "all paths in target cwd"
  eq(list_labels('', abs_cwd), { 'xxx', 'aaa', 'bbb' })

  -- Should work with empty string `cwd` meaning "path in all cwds"
  -- - NOTE: Although `xxx` label happens twice, it is still counted as one
  --   because it is for the same path.
  eq(list_labels(make_testpath('dir_1', 'file_1-2'), ''), { 'aaa', 'xxx', 'yyy' })

  -- Should work with both empty strings meaning "all visits"
  eq(list_labels('', ''), { 'xxx', 'aaa', 'bbb', 'yyy' })

  -- Should work with empty string `cwd` meaning "all visited cwds"
  eq(get_index(), make_ref_index_full(ref_index))
end

T['list_labels()']['respects `opts.filter`'] = function()
  local ref_index = {
    dir_1 = {
      ['dir_1/file_1-1'] = { count = 2, labels = { xxx = true, aaa = true }, latest = 10 },
      ['dir_1/file_1-2'] = { count = 1, labels = { xxx = true, bbb = true }, latest = 9 },
    },
  }
  set_index_from_ref(ref_index)

  child.lua([[
    _G.filter_args_log = {}
    _G.filter = function(...)
      table.insert(_G.filter_args_log, { ... })
      local path_data = ({ ... })[1]
      return path_data.count > 1
    end]])

  child.lua('_G.cwd = ' .. vim.inspect(make_testpath('dir_1')))
  eq(child.lua_get([[MiniVisits.list_labels('', cwd, { filter = _G.filter })]]), { 'aaa', 'xxx' })

  local args_log = child.lua_get('_G.filter_args_log')
  -- - Ensure same order in test, as there is no guarantee of order
  table.sort(args_log, function(a, b) return a[1].path < b[1].path end)
  eq(args_log, {
    { { count = 2, labels = { xxx = true, aaa = true }, latest = 10, path = make_testpath('dir_1', 'file_1-1') } },
    { { count = 1, labels = { xxx = true, bbb = true }, latest = 9, path = make_testpath('dir_1', 'file_1-2') } },
  })
end

T['list_labels()']['properly merges visit data for filter'] = function()
  --stylua: ignore
  local ref_index = {
    dir_1 = {
      ['dir_1/file_1-1'] = { count = 2, labels = { xxx = true, aaa = true }, latest = 10, aaa = 1 },
      ['dir_1/file_1-2'] = { count = 1, labels = { xxx = true, bbb = true }, latest = 9, bbb  = 'a' },
      ['file']           = { count = 1, latest = 8, data = { bool = true, num = 2, str = 'b' } },
    },
    dir_2 = {
      ['dir_1/file_1-1'] = { count = 11, labels = { xxx = true, ccc = true }, latest = 100, ccc = 3 },
      ['file']           = { count = 10, latest = 1, data = { bool2 = true, num2 = 2, str2 = 'b' } },
    }
  }
  set_index_from_ref(ref_index)

  child.lua([[
    _G.filter_args_log = {}
    _G.filter = function(...)
      table.insert(_G.filter_args_log, { ... })
      return true
    end]])

  child.lua_get([[MiniVisits.list_labels('', '', { filter = _G.filter })]])

  local filter_args_log = child.lua_get('_G.filter_args_log')
  -- - Ensure same order in test, as there is no guarantee of order
  table.sort(filter_args_log, function(a, b) return a[1].path < b[1].path end)

  eq(filter_args_log, {
    -- `count` should be summed, `latest` should be reduced with `math.max`,
    -- non-related fields should be merged
    {
      {
        count = 13,
        labels = { xxx = true, aaa = true, ccc = true },
        latest = 100,
        path = make_testpath('dir_1', 'file_1-1'),
        aaa = 1,
        ccc = 3,
      },
    },
    {
      {
        count = 1,
        labels = { xxx = true, bbb = true },
        latest = 9,
        path = make_testpath('dir_1', 'file_1-2'),
        bbb = 'a',
      },
    },
    {
      {
        count = 11,
        latest = 8,
        path = make_testpath('file'),
        data = { bool = true, bool2 = true, num = 2, num2 = 2, str = 'b', str2 = 'b' },
      },
    },
  })
end

T['list_labels()']['respects `config.list`'] = function()
  set_index_from_ref({ dir_1 = { file = { count = 1, labels = { xxx = true }, latest = 10 } } })

  child.lua([[
    _G.filter = function()
      _G.filter_been_here = true
      return true
    end]])
  child.lua('MiniVisits.config.list = { filter = _G.filter }')

  list_labels('', '')
  eq(child.lua_get('_G.filter_been_here'), true)
end

T['list_labels()']['validates arguments'] = function()
  expect.error(function() list_labels(1, 'cwd') end, '`path`.*string')
  expect.error(function() list_labels('file', 1) end, '`cwd`.*string')

  child.api.nvim_set_current_buf(new_uri_scratch_buf())
  expect.error(function() list_labels() end, 'not for a regular file')
end

T['select_path()'] = new_set({
  hooks = {
    pre_case = function()
      -- Ensure consistent path separator
      child.lua([[
        local getcwd_orig = vim.fn.getcwd
        vim.fn.getcwd = function() return (getcwd_orig():gsub('\\', '/')) end
      ]])
    end,
  },
})

local select_path = forward_lua('MiniVisits.select_path')

T['select_path()']['works'] = function()
  local ref_index = {
    dir_1 = {
      ['dir_1/file_1-1'] = { count = 2, latest = 10 },
      ['dir_1/file_1-2'] = { count = 1, latest = 9 },
    },
  }
  set_index_from_ref(ref_index)

  child.fn.chdir(make_testpath('dir_1'))

  mock_ui_select(1)
  select_path()
  eq(get_ui_select_log(), {
    {
      items = {
        { path = make_testpath('dir_1', 'file_1-1'), text = 'file_1-1' },
        { path = make_testpath('dir_1', 'file_1-2'), text = 'file_1-2' },
      },
      prompt = 'Visited paths',
    },
  })
  validate_buf_name(0, 'file_1-1')

  -- Should open path in relative form for nicer `:buffers`
  expect.match(child.cmd_capture('buffers'), '[^/]file_1%-1')
end

T['select_path()']['mimics empty buffer reuse'] = function()
  local ref_index = { dir_1 = { ['dir_1/file_1-1'] = { count = 2, latest = 10 } } }
  set_index_from_ref(ref_index)
  child.fn.chdir(make_testpath('dir_1'))
  mock_ui_select(1)

  local validate = function(ref_n_bufs)
    select_path()
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

T['select_path()']['properly shortens paths'] = function()
  local home_dir = child.loop.os_homedir()

  local dir_path = make_testpath('dir_1')
  child.fn.chdir(dir_path)
  set_index({
    [dir_path] = {
      [join_path(dir_path, 'subdir', 'file_1-1-1')] = { count = 2, latest = 10 },
      [join_path(home_dir, 'file')] = { count = 1, latest = 9 },
    },
  })

  mock_ui_select(1)
  select_path()
  local items = get_ui_select_log()[1].items
  eq(items[1].text, 'subdir/file_1-1-1')
  eq(items[2].text, '~/file')
end

T['select_path()']['can be properly canceled'] = function()
  local ref_index = { dir_1 = { file = { count = 1, latest = 10 } } }
  set_index_from_ref(ref_index)

  local init_buf_id = child.api.nvim_get_current_buf()
  local init_buf_name = child.api.nvim_buf_get_name(init_buf_id)
  mock_ui_select(nil)
  select_path()

  eq(child.api.nvim_get_current_buf(), init_buf_id)
  eq(child.api.nvim_buf_get_name(0), init_buf_name)
end

T['select_path()']['reuses current buffer when opening path'] = function()
  local ref_index = { dir_1 = { file = { count = 1, latest = 10 } } }
  set_index_from_ref(ref_index)

  child.fn.chdir(make_testpath('dir_1'))
  edit(make_testpath('file'))
  local file_buf_id = child.api.nvim_get_current_buf()

  edit(make_testpath('dir_1/file_1-1'))
  child.api.nvim_buf_set_option(file_buf_id, 'buflisted', false)

  mock_ui_select(1)
  select_path()

  eq(child.api.nvim_get_current_buf(), file_buf_id)
  -- Should make unlisted buffer listed
  eq(child.bo.buflisted, true)
end

T['select_path()']['forwards arguments to `list_paths()`'] = function()
  local ref_index = { dir_1 = { file = { count = 1, latest = 10 } } }
  set_index_from_ref(ref_index)

  child.fn.chdir(make_testpath('dir_1'))
  child.lua([[
    MiniVisits.list_paths = function(...)
      _G.list_paths_args = { ... }
      return { 'file' }
    end]])

  mock_ui_select(1)
  select_path('aaa', { opts = true })
  validate_buf_name(0, 'file')

  eq(child.lua_get('_G.list_paths_args'), { 'aaa', { opts = true } })
end

T['select_path()']['validates arguments'] = function()
  expect.error(function() select_path(1) end, '`cwd`.*string')
end

T['select_label()'] = new_set()

local select_label = forward_lua('MiniVisits.select_label')

T['select_label()']['works'] = function()
  local ref_index = {
    dir_1 = {
      ['dir_1/file_1-1'] = { count = 3, labels = { xxx = true, aaa = true }, latest = 10 },
      ['dir_1/file_1-2'] = { count = 2, labels = { xxx = true, bbb = true }, latest = 9 },
      ['dir_1/subdir/file_1-1-1'] = { count = 1, labels = { bbb = true }, latest = 8 },
    },
  }
  set_index_from_ref(ref_index)

  child.fn.chdir(make_testpath('dir_1'))
  edit('file')

  mock_ui_select(1)
  select_label('', getcwd())
  eq(get_ui_select_log(), {
    { items = { 'bbb', 'xxx', 'aaa' }, prompt = 'Visited labels' },
    {
      items = {
        { path = make_testpath('dir_1', 'file_1-2'), text = 'file_1-2' },
        { path = make_testpath('dir_1', 'subdir', 'file_1-1-1'), text = 'subdir/file_1-1-1' },
      },
      prompt = 'Visited paths',
    },
  })
  validate_buf_name(0, 'file_1-2')

  -- Should open path in relative form for nicer `:buffers`
  expect.match(child.cmd_capture('buffers'):gsub('\\', '/'), '[^/]file_1%-2')
end

T['select_label()']['mimics empty buffer reuse'] = function()
  local ref_index = { dir_1 = { ['dir_1/file_1-2'] = { count = 2, labels = { aaa = true }, latest = 9 } } }
  set_index_from_ref(ref_index)
  child.fn.chdir(make_testpath('dir_1'))
  mock_ui_select(1)

  local validate = function(ref_n_bufs)
    select_label('', getcwd())
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
T['select_label()']['can be properly canceled'] = function()
  local ref_index = { dir_1 = { file = { count = 1, labels = { aaa = true }, latest = 10 } } }
  set_index_from_ref(ref_index)

  local init_buf_id = child.api.nvim_get_current_buf()
  local init_buf_name = child.api.nvim_buf_get_name(init_buf_id)
  mock_ui_select(nil)
  select_label(make_testpath('file'))

  eq(child.api.nvim_get_current_buf(), init_buf_id)
  eq(child.api.nvim_buf_get_name(0), init_buf_name)
end

T['select_label()']['forwards arguments to `list_labels()` and `select_path()`'] = function()
  local ref_index = { dir_1 = { file = { count = 1, labels = { aaa = true }, latest = 10 } } }
  set_index_from_ref(ref_index)

  child.fn.chdir(make_testpath('dir_1'))
  child.lua([[
    MiniVisits.list_labels = function(...)
      _G.list_labels_args = { ... }
      return { 'aaa' }
    end
    MiniVisits.select_path = function(...) _G.select_path_args = { ... } end]])

  mock_ui_select(1)
  select_label('path', 'cwd', { opts = true })

  eq(child.lua_get('_G.list_labels_args'), { 'path', 'cwd', { opts = true } })
  eq(child.lua_get('_G.select_path_args[1]'), 'cwd')

  child.lua('_G.passed_filter = _G.select_path_args[2].filter')
  eq(child.lua_get([[_G.passed_filter({ labels = { aaa = true } })]]), true)
  eq(child.lua_get([[_G.passed_filter({ labels = { bbb = true } }) == true]]), false)
end

T['select_label()']['validates arguments'] = function()
  expect.error(function() select_label(1, 'cwd') end, '`path`.*string')
  expect.error(function() select_label('file', 1) end, '`cwd`.*string')
end

T['iterate_paths()'] = new_set()

local iterate_paths = forward_lua('MiniVisits.iterate_paths')

local setup_index_for_iterate = function()
  set_index_from_ref({
    dir_1 = {
      ['dir_1/file_1-1'] = { count = 3, latest = 3 },
      ['dir_1/file_1-2'] = { count = 2, latest = 2 },
      ['dir_1/file_1-3'] = { count = 1, latest = 1 },
    },
  })
  local dir_path = make_testpath('dir_1')
  child.fn.chdir(dir_path)
end

local validate_iterate = function(init_path, direction, opts, ref_path)
  if init_path ~= nil then edit(init_path) end
  iterate_paths(direction, getcwd(), opts)
  validate_buf_name(0, ref_path)
end

--stylua: ignore
T['iterate_paths()']['works'] = function()
  setup_index_for_iterate()

  validate_iterate('file_1-2', 'first',    {}, 'file_1-1')
  validate_iterate('file_1-3', 'backward', {}, 'file_1-2')
  validate_iterate('file_1-1', 'forward',  {}, 'file_1-2')
  validate_iterate('file_1-2', 'last',     {}, 'file_1-3')
end

--stylua: ignore
T['iterate_paths()']['works when current path is not in array'] = function()
  setup_index_for_iterate()
  local validate = function(...)
    edit('file')
    validate_iterate(...)
  end

  validate(nil, 'first',    {}, 'file_1-1')
  validate(nil, 'backward', {}, 'file_1-3')
  validate(nil, 'forward',  {}, 'file_1-1')
  validate(nil, 'last',     {}, 'file_1-3')

  validate(nil, 'first',    { n_times = 2 }, 'file_1-2')
  validate(nil, 'backward', { n_times = 2 }, 'file_1-2')
  validate(nil, 'forward',  { n_times = 2 }, 'file_1-2')
  validate(nil, 'last',     { n_times = 2 }, 'file_1-2')
end

--stylua: ignore
T['iterate_paths()']['works when current buffer does not have path'] = function()
  setup_index_for_iterate()
  local validate = function(...)
    child.api.nvim_set_current_buf(child.api.nvim_create_buf(false, true))
    validate_iterate(...)
  end

  validate(nil, 'first',    {}, 'file_1-1')
  validate(nil, 'backward', {}, 'file_1-3')
  validate(nil, 'forward',  {}, 'file_1-1')
  validate(nil, 'last',     {}, 'file_1-3')
end

T['iterate_paths()']['works if there are not paths to iterate'] = function()
  local validate = function(direction)
    local init_buf = child.api.nvim_get_current_buf()
    iterate_paths(direction)
    eq(child.api.nvim_get_current_buf(), init_buf)
    eq(child.api.nvim_buf_get_name(0), '')
  end

  validate('first')
  validate('backward')
  validate('forward')
  validate('last')
end

T['iterate_paths()']['reuses current buffer when opening path'] = function()
  setup_index_for_iterate()
  edit(join_path(getcwd(), 'file_1-1'))
  local file_buf_id = child.api.nvim_get_current_buf()

  edit(join_path(getcwd(), 'file_1-2'))
  child.api.nvim_buf_set_option(file_buf_id, 'buflisted', false)

  iterate_paths('first')

  eq(child.api.nvim_get_current_buf(), file_buf_id)
  -- Should make unlisted buffer listed
  eq(child.bo.buflisted, true)
end

T['iterate_paths()']['does not track visit'] = function()
  child.lua('MiniVisits.config.track.delay = ' .. test_track_delay)
  setup_index_for_iterate()
  local init_index = get_index()

  iterate_paths('first')
  sleep(test_track_delay + small_time)
  iterate_paths('forward')
  sleep(test_track_delay + small_time)
  iterate_paths('backward')
  sleep(test_track_delay + small_time)
  iterate_paths('last')
  sleep(test_track_delay + small_time)

  eq(get_index(), init_index)

  -- Should properly cleanup
  eq(child.g.minivisits_disable, vim.NIL)
  for _, buf_id in ipairs(child.api.nvim_list_bufs()) do
    local lua_cmd = string.format('vim.b[%d].minivisits_disable', buf_id)
    eq(child.lua_get(lua_cmd), vim.NIL)
  end
end

T['iterate_paths()']['respects `cwd` argument'] = function()
  setup_index_for_iterate()
  child.fn.chdir('subdir')

  iterate_paths('first', make_testpath('dir_1'))
  validate_buf_name(0, make_testpath('dir_1', 'file_1-1'))
end

T['iterate_paths()']['respects `opts.filter`'] = function()
  set_index_from_ref({
    dir_1 = {
      ['dir_1/file_1-1'] = { count = 1, labels = { aaa = true }, latest = 1 },
      ['dir_1/file_1-2'] = { count = 10, latest = 10 },
    },
  })

  iterate_paths('first', make_testpath('dir_1'), { filter = 'aaa' })
  validate_buf_name(0, make_testpath('dir_1', 'file_1-1'))
end

T['iterate_paths()']['respects `opts.sort`'] = function()
  child.lua([[_G.sort = function() return { { path = 'new-file' } } end]])
  child.lua([[MiniVisits.iterate_paths('first', nil, { sort = _G.sort })]])
  validate_buf_name(0, 'new-file')
end

--stylua: ignore
T['iterate_paths()']['respects `opts.n_times`'] = function()
  setup_index_for_iterate()

  validate_iterate('file_1-3', 'first',    { n_times = 2 }, 'file_1-2')
  validate_iterate('file_1-3', 'backward', { n_times = 2 }, 'file_1-1')
  validate_iterate('file_1-1', 'forward',  { n_times = 2 }, 'file_1-3')
  validate_iterate('file_1-1', 'last',     { n_times = 2 }, 'file_1-2')
end

--stylua: ignore
T['iterate_paths()']['respects `opts.wrap`'] = function()
  setup_index_for_iterate()

  -- No wrap by default
  validate_iterate('file_1-1', 'first',    { n_times = 5 }, 'file_1-3')
  validate_iterate('file_1-2', 'backward', { n_times = 5 }, 'file_1-1')
  validate_iterate('file_1-2', 'forward',  { n_times = 5 }, 'file_1-3')
  validate_iterate('file_1-1', 'last',     { n_times = 5 }, 'file_1-1')

  validate_iterate('file_1-1', 'first',    { n_times = 5, wrap = true }, 'file_1-2')
  validate_iterate('file_1-2', 'backward', { n_times = 5, wrap = true }, 'file_1-3')
  validate_iterate('file_1-2', 'forward',  { n_times = 5, wrap = true }, 'file_1-1')
  validate_iterate('file_1-1', 'last',     { n_times = 5, wrap = true }, 'file_1-2')
end

T['iterate_paths()']['validates arguments'] = function()
  expect.error(function() iterate_paths(1, 'cwd') end, '`direction`.*one of')
  expect.error(function() iterate_paths('forward', 1) end, '`cwd`.*string')
end

T['get_index()'] = new_set()

T['get_index()']['works'] = function()
  child.lua('MiniVisits.config.track.delay = ' .. test_track_delay)
  eq(get_index(), {})

  local path = make_testpath('file')
  edit(path)
  sleep(test_track_delay)
  eq(get_index(), { [getcwd()] = { [path] = { count = 1, latest = child_time() } } })

  -- Should return table copy
  local is_ok = child.lua([[
    _G.cur_index = MiniVisits.get_index()
    _G.ref_index = vim.deepcopy(_G.cur_index)
    _G.cur_index['aa'] = {}
    return vim.deep_equal(MiniVisits.get_index(), _G.ref_index)
  ]])
  eq(is_ok, true)
end

T['set_index()'] = new_set()

T['set_index()']['works'] = function()
  child.lua('MiniVisits.config.track.delay = ' .. test_track_delay)

  local path, cwd = make_testpath('file'), getcwd()
  child.lua(string.format('_G.path, _G.cwd = %s, %s', vim.inspect(path), vim.inspect(cwd)))
  child.lua([[
    _G.index_ref = { [vim.fn.getcwd():gsub('\\', '/')] = { [_G.path] = { count = 1, latest = 10 } } }
    MiniVisits.set_index(_G.index_ref)
  ]])

  eq(get_index(), { [cwd] = { [path] = { count = 1, latest = 10 } } })

  -- Should set table copy
  edit(path)
  sleep(test_track_delay)
  eq(get_index(), { [cwd] = { [path] = { count = 2, latest = child_time() } } })
  eq(child.lua_get('_G.index_ref'), { [cwd] = { [path] = { count = 1, latest = 10 } } })
end

T['set_index()']['treats set index as whole history and not only current session'] = function()
  local store_path = make_testpath('tmp-index')
  MiniTest.finally(vim.schedule_wrap(function() vim.fn.delete(store_path, 'rf') end))
  child.fn.writefile({ 'return { aaa = { bbb = { count = 10, latest = 10 } } }' }, store_path)

  child.lua('MiniVisits.config.track.delay = 10')
  child.lua('MiniVisits.config.store.path = ' .. vim.inspect(store_path))

  local path, cwd = make_testpath('file'), getcwd()
  set_index({ [cwd] = { [path] = { count = 1, latest = child_time() } } })
  eq(list_paths(''), { path })
end

T['set_index()']['validates arguments'] = function()
  local validate = function(x, error_pattern)
    expect.error(function() set_index(x) end, error_pattern)
  end

  validate(1, '`index`.*table')
  validate({ { path = { count = 1, latest = 1 } } }, 'First level keys in `index`.*strings')
  validate({ cwd = 1 }, 'First level values in `index`.*tables')
  validate({ cwd = { { count = 1, latest = 1 } } }, 'Second level keys in `index`.*strings')
  validate({ cwd = { path = 1 } }, 'Second level values in `index`.*tables')
  validate({ cwd = { path = { count = '1', latest = 1 } } }, '`count`.*in `index`.*numbers')
  validate({ cwd = { path = { count = 1, latest = '1' } } }, '`latest`.*in `index`.*numbers')
  validate({ cwd = { path = { count = 1, latest = 1, labels = 1 } } }, '`labels`.*table')
  validate({ cwd = { path = { count = 1, latest = 1, labels = { true } } } }, 'Keys in `labels`.*strings')
  validate({ cwd = { path = { count = 1, latest = 1, labels = { aaa = 1 } } } }, 'Values in `labels`.*`true`')
end

T['reset_index()'] = new_set()

local reset_index = forward_lua('MiniVisits.reset_index')

T['reset_index()']['works'] = function()
  local store_path = child.lua_get('MiniVisits.config.store.path')
  child.fn.mkdir(vim.fn.fnamemodify(store_path, ':h'), 'p')
  child.fn.writefile({ 'return { aaa = { bbb = { count = 10, latest = 10 } } }' }, store_path)

  local path, cwd = make_testpath('file'), getcwd()
  set_index({ [cwd] = { [path] = { count = 1, latest = child_time() } } })

  child.lua('MiniVisits.reset_index()')
  eq(get_index(), { aaa = { bbb = { count = 10, latest = 10 } } })
end

T['reset_index()']['does nothing if reading index failed'] = function()
  -- No index file
  local index = { [getcwd()] = { [make_testpath('file')] = { count = 1, latest = 10 } } }
  set_index(index)

  reset_index()
  eq(get_index(), index)

  -- Error during `MiniVisits.read_index()`
  local store_path = child.lua_get('MiniVisits.config.store.path')
  child.fn.mkdir(vim.fn.fnamemodify(store_path, ':h'), 'p')
  child.fn.writefile({ 'Not a Lua code' }, store_path)

  reset_index()
  eq(get_index(), index)
end

T['normalize_index()'] = new_set()

local normalize_index = forward_lua('MiniVisits.normalize_index')

T['normalize_index()']['works'] = function()
  local path, cwd = make_testpath('file'), getcwd()
  local index = { [cwd] = { [path] = { count = 1, labels = { aaa = true }, latest = child_time() } } }
  set_index(index)

  -- Should return the output of `MiniVisits.gen_normalize.default` by default
  child.lua([[MiniVisits.gen_normalize.default = function()
    return function(...)
      _G.normalize_args = { ... }
      return ...
    end
  end]])

  eq(normalize_index(), index)
  eq(child.lua_get('_G.normalize_args'), { index })

  -- Should respect input even if there is session index present
  local index_2 = { cwd = { path = { count = 1, latest = 10 } } }
  eq(normalize_index(index_2), index_2)
end

T['normalize_index()']['respects `config.store.normalize`'] = function()
  local path, cwd = make_testpath('file'), getcwd()
  local index = { [cwd] = { [path] = { count = 1, labels = { aaa = true }, latest = child_time() } } }
  set_index(index)

  -- Should return the output of `MiniVisits.gen_normalize.default` by default
  child.lua([[MiniVisits.config.store.normalize = function(...)
    _G.normalize_args = { ... }
    return ...
  end]])

  eq(normalize_index(), index)
  eq(child.lua_get('_G.normalize_args'), { index })
end

T['normalize_index()']['validates output'] = function()
  child.lua('MiniVisits.config.store.normalize = function() return 1 end')
  expect.error(normalize_index, '`index` after normalization')
end

T['normalize_index()']['validates arguments'] = function()
  expect.error(function() normalize_index(1) end, '`index`.*table')
end

T['read_index()'] = new_set()

local read_index = forward_lua('MiniVisits.read_index')

T['read_index()']['works'] = function()
  local store_path = child.lua_get('MiniVisits.config.store.path')
  child.fn.mkdir(vim.fn.fnamemodify(store_path, ':h'), 'p')
  child.fn.writefile({ 'return { aaa = { bbb = { count = 10, latest = 10 } } }' }, store_path)

  eq(read_index(), { aaa = { bbb = { count = 10, latest = 10 } } })
end

T['read_index()']['respects `store_path` argument'] = function()
  local store_path = make_testpath('test-index')
  MiniTest.finally(function() vim.fn.delete(store_path) end)
  child.fn.writefile({ 'return { aaa = { bbb = { count = 10, latest = 10 } } }' }, store_path)

  eq(read_index(store_path), { aaa = { bbb = { count = 10, latest = 10 } } })
end

T['read_index()']['returns `nil` if can not locate file'] = function()
  eq(read_index('non-existing-file'), vim.NIL)
  eq(read_index(''), vim.NIL)
end

T['read_index()']['throws error if Lua sourcing failed'] = function()
  local store_path = make_testpath('test-index')
  MiniTest.finally(function() vim.fn.delete(store_path) end)
  child.fn.writefile({ 'return {' }, store_path)
  expect.error(function() read_index(store_path) end)
end

T['read_index()']['validates arguments'] = function()
  expect.error(function() read_index(1) end, '`store_path`.*string')
end

T['write_index()'] = new_set()

local write_index = forward_lua('MiniVisits.write_index')

T['write_index()']['works'] = function()
  local path, cwd = make_testpath('file'), getcwd()
  local index = { [cwd] = { [path] = { count = 1, latest = child_time() } } }
  set_index(index)

  -- Should call `normalize_index` and write its output
  child.lua([[MiniVisits.normalize_index = function(index)
    _G.input_index = vim.deepcopy(index)
    return { aaa = { bbb = { count = 10, latest = 10 } } }
  end]])

  write_index()
  local store_path = child.lua_get('MiniVisits.config.store.path')
  eq(
    table.concat(vim.fn.readfile(store_path), '\n'),
    'return {\n  aaa = {\n    bbb = {\n      count = 10,\n      latest = 10\n    }\n  }\n}'
  )

  eq(child.lua_get('_G.input_index'), index)
end

T['write_index()']['respects arguments'] = function()
  -- Should create non-existing parent directories
  local store_path = make_testpath('nondir/subdir/test-index')
  MiniTest.finally(function() vim.fn.delete(store_path) end)
  local path, cwd = make_testpath('file'), getcwd()
  local index = { [cwd] = { [path] = { count = 1, latest = child_time() } } }
  write_index(store_path, index)

  eq(table.concat(vim.fn.readfile(store_path), '\n'), 'return ' .. vim.inspect(index))
end

T['write_index()']['validates arguments'] = function()
  expect.error(function() write_index(1, { aaa = { bbb = { count = 10, latest = 10 } } }) end, '`store_path`.*string')
  expect.error(function() write_index(make_testpath('test-index'), 1) end, '`index`.*table')
end

T['rename_in_index()'] = new_set()

local rename_in_index = forward_lua('MiniVisits.rename_in_index')

T['rename_in_index()']['works for files'] = function()
  local path, cwd = make_testpath('file'), test_dir_absolute
  local index = {
    [cwd] = {
      [path] = { count = 1, latest = 10 },
      [path .. '_suffix'] = { count = 2, latest = 11 },
    },
    [cwd .. '_2'] = {
      [path] = { count = 10, latest = 100 },
      [path .. '_suffix'] = { count = 20, latest = 110 },
    },
  }
  set_index(index)

  -- Should rename only full matches in whole index object
  eq(rename_in_index(path, path .. '_new'), {
    [cwd] = {
      [path .. '_new'] = { count = 1, latest = 10 },
      [path .. '_suffix'] = { count = 2, latest = 11 },
    },
    [cwd .. '_2'] = {
      [path .. '_new'] = { count = 10, latest = 100 },
      [path .. '_suffix'] = { count = 20, latest = 110 },
    },
  })

  -- Should allow specifying index as argument
  eq(
    rename_in_index(path, path .. '_very_new', { [cwd] = { [path] = { count = 2, latest = 20 } } }),
    { [cwd] = { [path .. '_very_new'] = { count = 2, latest = 20 } } }
  )

  -- Should nor affect current index
  eq(get_index(), index)
end

T['rename_in_index()']['works for directories'] = function()
  local path = make_testpath('dir_1', 'file_1-1')
  local cwd, cwd_2 = make_testpath('dir_1'), make_testpath('dir_1_1')
  local index = {
    [cwd] = { [path] = { count = 1, latest = 10 } },
    [cwd_2] = { [path] = { count = 10, latest = 100 } },
  }
  set_index(index)

  -- Should rename both full matches and as a parent
  local path_to = cwd .. '_new'
  eq(rename_in_index(cwd, path_to), {
    [path_to] = { [join_path(path_to, 'file_1-1')] = { count = 1, latest = 10 } },
    [cwd_2] = { [join_path(path_to, 'file_1-1')] = { count = 10, latest = 100 } },
  })

  -- Should allow specifying index as argument
  eq(
    rename_in_index(cwd, cwd .. '_very_new', { [cwd] = { [path] = { count = 2, latest = 20 } } }),
    { [cwd .. '_very_new'] = { [join_path(cwd .. '_very_new', 'file_1-1')] = { count = 2, latest = 20 } } }
  )

  -- Can rename directory to its child
  eq(
    rename_in_index(cwd, cwd .. '/child', { [cwd] = { [path] = { count = 2, latest = 20 } } }),
    { [cwd .. '/child'] = { [join_path(cwd .. '/child', 'file_1-1')] = { count = 2, latest = 20 } } }
  )

  -- Should nor affect current index
  eq(get_index(), index)
end

T['rename_in_index()']['validates_arguments'] = function()
  expect.error(function() rename_in_index(1, 'bbb') end, '`path_from`.*string')
  expect.error(function() rename_in_index('aaa', 2) end, '`path_to`.*string')
  expect.error(function() rename_in_index('aaa', 'bbb', 1) end, '`index`.*table')
end

T['gen_filter'] = new_set()

T['gen_filter']['default()'] = new_set()

T['gen_filter']['default()']['works'] = function()
  child.lua('_G.f = MiniVisits.gen_filter.default()')
  eq(child.lua_get('_G.f()'), true)
  eq(child.lua_get('_G.f({ aaa = { bbb = { count = 10, latest = 10 } } })'), true)
end

T['gen_filter']['this_session()'] = new_set()

T['gen_filter']['this_session()']['works'] = function()
  child.lua('_G.session_start = os.time()')
  child.lua('_G.f = MiniVisits.gen_filter.this_session()')

  eq(child.lua_get('_G.f({ latest = _G.session_start - 10 })'), false)
  eq(child.lua_get('_G.f({ latest = _G.session_start + 10 })'), true)
end

T['gen_sort'] = new_set()

T['gen_sort']['default()'] = new_set()

local validate_gen_sort = function(method, path_data_arr, recency_weight, ref_paths)
  child.lua([[_G.path_data_arr = ]] .. vim.inspect(path_data_arr))
  child.lua([[_G.path_data_arr_ref = vim.deepcopy(_G.path_data_arr)]])

  local out = child.lua_get(
    'MiniVisits.gen_sort.' .. method .. '(...)(_G.path_data_arr)',
    { { recency_weight = recency_weight } }
  )
  local out_paths = vim.tbl_map(function(x) return x.path end, out)
  eq(out_paths, ref_paths)

  -- Should not modify input array
  eq(child.lua_get('vim.deep_equal(_G.path_data_arr, _G.path_data_arr_ref)'), true)
end

--stylua: ignore
T['gen_sort']['default()']['works'] = function()
  local path_data_arr = {
    { path = 'aaa', count = 100, latest = 3 },   -- ranked 1 and 2
    { path = 'bbb', count = 3,   latest = 2 },   -- ranked 2 and 3
    { path = 'ccc', count = 2,   latest = 100 }, -- ranked 3 and 1
    { path = 'ddd', count = 1,   latest = 1 },   -- ranked 4 and 4
  }

  validate_gen_sort('default', path_data_arr, nil, { 'aaa', 'ccc', 'bbb', 'ddd' })
  validate_gen_sort('default', path_data_arr, 0.5, { 'aaa', 'ccc', 'bbb', 'ddd' })
  validate_gen_sort('default', path_data_arr, 0,   { 'aaa', 'bbb', 'ccc', 'ddd' })
  validate_gen_sort('default', path_data_arr, 1,   { 'ccc', 'aaa', 'bbb', 'ddd' })
end

T['gen_sort']['default()']['handles ties'] = function()
  local path_data_arr = {
    { path = 'aaa', count = 9, latest = 4 }, -- ranked 1 and 4 = 2.5
    { path = 'bbb', count = 2, latest = 6 }, -- ranked 4 and 2 = 3
    { path = 'ccc', count = 2, latest = 5 }, -- ranked 4 and 3 = 3.5
    { path = 'ddd', count = 2, latest = 1 }, -- ranked 4 and 7 = 5.5
    { path = 'eee', count = 2, latest = 3 }, -- ranked 4 and 5 = 4.5
    { path = 'fff', count = 2, latest = 2 }, -- ranked 4 and 6 = 5
    { path = 'ggg', count = 1, latest = 7 }, -- ranked 7 and 1 = 4
  }

  -- In ranks (should assign average rank)
  validate_gen_sort('default', path_data_arr, 0.5, { 'aaa', 'bbb', 'ccc', 'ggg', 'eee', 'fff', 'ddd' })

  -- In output score (should sort by path)
  validate_gen_sort('default', path_data_arr, 0, { 'aaa', 'bbb', 'ccc', 'ddd', 'eee', 'fff', 'ggg' })
end

T['gen_sort']['z()'] = new_set()

T['gen_sort']['z()']['works'] = function()
  local cur_time = child_time()
  local path_data_arr = {
    { path = 'aaa', count = 2, latest = cur_time - 1 },
    { path = 'bbb', count = 3, latest = cur_time - 10000 },
    { path = 'ccc', count = 4, latest = cur_time - 20000 },
    { path = 'ddd', count = 1, latest = cur_time - 30000 },
  }

  validate_gen_sort('z', path_data_arr, 0, { 'aaa', 'bbb', 'ccc', 'ddd' })
end

T['gen_normalize'] = new_set()

T['gen_normalize']['default()'] = new_set()

local validate_default_normalize = function(opts, index_input, index_ref)
  child.lua('_G.normalize = MiniVisits.gen_normalize.default(...)', { opts })
  eq(child.lua_get('_G.normalize(...)', { index_input }), index_ref)
end

T['gen_normalize']['default()']['works'] = function()
  local path, path_2, path_3 =
    make_testpath('file'), make_testpath('dir_1', 'file_1-1'), make_testpath('dir_1', 'file_1-2')
  local cwd, cwd_2 = getcwd(), test_dir_absolute

  validate_default_normalize({}, {
    [cwd] = {
      [path] = { count = 600, labels = { aaa = true }, latest = 10 },
      [path_2] = { count = 400, latest = 20 },
      [path_3] = { count = 1, latest = 30 },
      ['non-path'] = { count = 1, latest = 40 },
    },
    [cwd_2] = {
      [path] = { count = 10, labels = { bbb = true }, latest = 100 },
      ['non-path-2'] = { count = 20, latest = 200 },
    },
  }, {
    [cwd] = {
      -- Should multiply each `count` by `800 / 1001` and keep 2 decimal places
      [path] = { count = 479.52, labels = { aaa = true }, latest = 10 },
      [path_2] = { count = 319.68, latest = 20 },
      [path_3] = { count = 0.8, latest = 30 },
      -- Should prune non-paths by default
    },
    [cwd_2] = {
      -- Should decay per cwd
      [path] = { count = 10, labels = { bbb = true }, latest = 100 },
    },
  })

  -- Does decay even for a single entry
  validate_default_normalize(
    {},
    { [cwd] = { [path] = { count = 1001, latest = 10 } } },
    { [cwd] = { [path] = { count = 800, latest = 10 } } }
  )

  -- Works even for a very large total `count` sum
  validate_default_normalize(
    {},
    { [cwd] = { [path] = { count = 10000, latest = 10 }, [path_2] = { count = 10000, latest = 20 } } },
    { [cwd] = { [path] = { count = 400, latest = 10 }, [path_2] = { count = 400, latest = 20 } } }
  )
end

T['gen_normalize']['default()']['prunes before and after decay'] = function()
  local path, path_2 = make_testpath('file'), make_testpath('dir_1', 'file_1-1')
  local cwd = getcwd()

  -- Before decay
  validate_default_normalize({}, {
    [cwd] = {
      [path] = { count = 999.9, latest = 10 },
      [path_2] = { count = 0.4, latest = 20 },
    },
  }, {
    [cwd] = {
      -- There is no decay as `path_2` entry was removed before and total sum
      -- is now below threshold
      [path] = { count = 999.9, latest = 10 },
    },
  })

  -- After decay
  validate_default_normalize({}, {
    [cwd] = {
      [path] = { count = 1000, latest = 10 },
      [path_2] = { count = 0.51, latest = 20 },
    },
  }, {
    [cwd] = {
      -- There is decay in `path` and no `path_2` entry as no pruning was done
      -- before decay. After it, `path_2` has `count = 0.41` and is pruned.
      [path] = { count = 799.59, latest = 10 },
    },
  })
end

T['gen_normalize']['default()']['does not prune if visit has label'] = function()
  local path, cwd = make_testpath('file'), getcwd()
  local index = { [cwd] = { [path] = { count = 0, labels = { aaa = true }, latest = 0 } } }
  validate_default_normalize({}, index, index)
end

T['gen_normalize']['default()']['respects `opts.decay_threshold`'] = function()
  local path, path_2 = make_testpath('file'), make_testpath('dir_1', 'file_1-1')
  local cwd = getcwd()

  local index = {
    [cwd] = {
      [path] = { count = 800, latest = 10 },
      [path_2] = { count = 150, latest = 20 },
    },
  }

  validate_default_normalize({}, index, index)

  validate_default_normalize({ decay_threshold = 949.9 }, index, {
    [cwd] = {
      [path] = { count = 673.68, latest = 10 },
      [path_2] = { count = 126.32, latest = 20 },
    },
  })
end

T['gen_normalize']['default()']['respects `opts.decay_target`'] = function()
  local path, path_2 = make_testpath('file'), make_testpath('dir_1', 'file_1-1')
  local cwd = getcwd()

  local index = {
    [cwd] = {
      [path] = { count = 800, latest = 10 },
      [path_2] = { count = 201, latest = 20 },
    },
  }

  validate_default_normalize({}, index, {
    [cwd] = {
      [path] = { count = 639.36, latest = 10 },
      [path_2] = { count = 160.64, latest = 20 },
    },
  })

  validate_default_normalize({ decay_target = 100 }, index, {
    [cwd] = {
      [path] = { count = 79.92, latest = 10 },
      [path_2] = { count = 20.08, latest = 20 },
    },
  })
end

T['gen_normalize']['default()']['respects `opts.prune_threshold`'] = function()
  local path, path_2 = make_testpath('file'), make_testpath('dir_1', 'file_1-1')
  local cwd = getcwd()

  local index = {
    [cwd] = {
      [path] = { count = 0.4, latest = 10 },
      [path_2] = { count = 1, latest = 20 },
    },
  }

  validate_default_normalize({}, index, { [cwd] = { [path_2] = { count = 1, latest = 20 } } })

  validate_default_normalize({ prune_threshold = 1.01 }, index, {})
  validate_default_normalize({ prune_threshold = 0.1 }, index, index)
end

T['gen_normalize']['default()']['respects `opts.prune_paths`'] = function()
  local path, path_2 = make_testpath('file'), make_testpath('dir_1', 'file_1-1')
  local cwd, cwd_2 = getcwd(), test_dir_absolute

  local index = {
    [cwd] = {
      [path] = { count = 10, latest = 10 },
      ['non-path'] = { count = 10, latest = 10 },
    },
    ['non-cwd'] = {
      [path] = { count = 20, latest = 20 },
    },
    [cwd_2] = {
      ['non-path'] = { count = 30, latest = 30 },
    },
  }

  -- Should not remove paths by default
  validate_default_normalize({}, index, { [cwd] = { [path] = { count = 10, latest = 10 } } })

  validate_default_normalize({ prune_paths = false }, index, index)
end

T['gen_normalize']['default()']['has output validating arguments'] = function()
  expect.error(function() child.lua('MiniVisits.gen_normalize.default()(1)') end, '`index`.*table')
end

-- Integration tests ----------------------------------------------------------
T['Tracking'] = new_set()

T['Tracking']['works'] = function()
  local path, path_2 = make_testpath('file'), make_testpath('dir1', 'file1-1')

  edit(path)
  eq(get_index(), {})

  sleep(default_track_delay - 2 * small_time)
  eq(get_index(), {})

  -- Should implement debounce style delay
  edit(path_2)
  sleep(default_track_delay - 2 * small_time)
  eq(get_index(), {})
  -- - "Latest" time should use time of actual registration
  sleep(2 * small_time)
  eq(get_index(), { [getcwd()] = { [path_2] = { count = 1, latest = child_time() } } })
end

T['Tracking']['registers only normal buffers'] = function()
  child.lua('MiniVisits.config.track.delay = ' .. test_track_delay)

  -- Scratch buffer
  local buf_id = child.api.nvim_create_buf(false, true)
  child.api.nvim_set_current_buf(buf_id)
  sleep(test_track_delay + small_time)
  eq(get_index(), {})

  -- Help buffer
  child.cmd('help')
  sleep(test_track_delay + small_time)
  eq(get_index(), {})
end

T['Tracking']['can register directories'] = function()
  child.lua('MiniVisits.config.track.delay = ' .. test_track_delay)

  local path = make_testpath('dir1')
  edit(path)
  sleep(test_track_delay + small_time)
  validate_index_entry('', path, { count = 1 })
end

T['Tracking']['does not register same path twice in a row'] = function()
  child.lua('MiniVisits.config.track.delay = ' .. test_track_delay)

  local path = make_testpath('file')
  edit(path)
  sleep(test_track_delay + small_time)
  validate_index_entry('', path, { count = 1 })

  child.cmd('help')
  sleep(test_track_delay + small_time)
  validate_index_entry('', path, { count = 1 })

  edit(path)
  sleep(test_track_delay + small_time)
  validate_index_entry('', path, { count = 1 })
end

T['Tracking']['is done on `BufEnter` by default'] = function()
  child.lua('MiniVisits.config.track.delay = ' .. test_track_delay)

  local path, path_2 = make_testpath('file'), make_testpath('dir1', 'file1-1')
  edit(path)
  sleep(test_track_delay + small_time)

  child.cmd('vertical split | edit ' .. child.fn.fnameescape(path_2))
  sleep(test_track_delay + small_time)

  -- Going back and forth should count as visits
  child.cmd('wincmd w')
  sleep(test_track_delay + small_time)
  child.cmd('wincmd w')
  sleep(test_track_delay + small_time)

  validate_index_entry('', path, { count = 2 })
  validate_index_entry('', path_2, { count = 2 })
end

T['Tracking']['respects `config.track.event`'] = function()
  child.cmd('autocmd! MiniVisits')
  load_module({ track = { event = 'BufHidden', delay = test_track_delay } })

  local path = make_testpath('file')
  edit(path)
  sleep(test_track_delay + small_time)
  eq(get_index(), {})

  child.api.nvim_set_current_buf(child.api.nvim_create_buf(false, true))
  sleep(test_track_delay + small_time)
  validate_index_entry('', path, { count = 1 })
end

T['Tracking']['can have `config.track.event = ""` to disable tracking'] = function()
  child.cmd('autocmd! MiniVisits')
  load_module({ track = { event = '', delay = test_track_delay } })
  eq(child.cmd_capture('au MiniVisits'):find('BufEnter'), nil)

  local path = make_testpath('file')
  edit(path)
  sleep(test_track_delay + small_time)
  eq(get_index(), {})
end

T['Tracking']['can have `config.track.delay = 0`'] = function()
  child.lua('MiniVisits.config.track.delay = 0')
  local path = make_testpath('file')
  edit(path)
  validate_index_entry('', path, { count = 1 })
end

T['Tracking']['respects `vim.{g,b}.minivisits_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child.lua('MiniVisits.config.track.delay = ' .. test_track_delay)
    local path, path_2 = make_testpath('file'), make_testpath('dir1', 'file1-1')

    -- Setting variable after event but before delay expired should work
    edit(path)
    sleep(0.1 * test_track_delay)
    child[var_type].minivisits_disable = true
    sleep(0.9 * test_track_delay + small_time)
    eq(get_index(), {})

    -- Global variable should disable globally, buffer - per buffer
    edit(path_2)
    sleep(test_track_delay + small_time)
    if var_type == 'g' then
      eq(get_index(), {})
    else
      validate_index_entry('', path_2, { count = 1 })
    end

    -- Buffer-local variable should still work
    edit(path)
    sleep(test_track_delay + small_time)
    validate_index_entry('', path, nil)
  end,
})

T['Storing'] = new_set()

T['Storing']['works'] = function()
  child.cmd('doautocmd VimLeavePre')
  local store_path = child.lua_get('MiniVisits.config.store.path')
  eq(child.fn.readfile(store_path), { 'return {}' })
end

T['Storing']['respects `config.store.autowrite`'] = function()
  local store_path = child.lua_get('MiniVisits.config.store.path')
  eq(child.fn.filereadable(store_path), 0)

  -- Should be respected even if set after `setup()`
  child.lua('MiniVisits.config.store.autowrite = false')
  child.cmd('doautocmd VimLeavePre')
  eq(child.fn.filereadable(store_path), 0)
end

T['Storing']['respects `config.store.normalize`'] = function()
  child.lua([[MiniVisits.config.store.normalize = function(...)
    _G.normalize_args = { ... }
    return { dir = { file = { count = 10, latest = 100 } } }
  end]])
  child.cmd('doautocmd VimLeavePre')
  local store_path = child.lua_get('MiniVisits.config.store.path')
  eq(
    table.concat(child.fn.readfile(store_path), '\n'),
    'return {\n  dir = {\n    file = {\n      count = 10,\n      latest = 100\n    }\n  }\n}'
  )

  eq(child.lua_get('_G.normalize_args'), { {} })
end

T['Storing']['respects `config.store.path`'] = function()
  local store_path = make_testpath('test-index')
  MiniTest.finally(function() vim.fn.delete(store_path) end)
  child.lua('MiniVisits.config.store.path = ' .. vim.inspect(store_path))

  child.stop()
  eq(vim.fn.readfile(store_path), { 'return {}' })
end

return T
