-- General design of testing sessions is to have each session file define
-- `_G.session_file` variable with value being path to sourced session. So
-- these assumptions are assumed:
-- - If `_G.session_file` is `nil`, no session file was sourced.
-- - If `_G.session_file` is not `nil`, its value is a relative (to project
--   root) path to a session file that was sourced.
local helpers = dofile('tests/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

local project_root = vim.fs.normalize(vim.fn.getcwd())
local empty_dir_relpath = 'tests/dir-sessions/empty'
local empty_dir_path = project_root .. '/' .. empty_dir_relpath

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('sessions', config) end
local unload_module = function() child.mini_unload('sessions') end
local reload_module = function(config) unload_module(); load_module(config) end
local reload_from_strconfig = function(strconfig) unload_module(); child.mini_load_strconfig('sessions', strconfig) end
local set_lines = function(...) return child.set_lines(...) end
local make_path = function(...) return vim.fs.normalize(table.concat({...}, '/')) end
local cd = function(...) child.cmd('cd ' .. make_path(...)) end
local sleep = function(ms) helpers.sleep(ms, child) end
--stylua: ignore end

-- Make helpers
local cleanup_directories = function()
  -- Cleanup files for directories to have invariant properties
  -- Ensure 'empty' directory doesn't exist
  child.fn.delete(empty_dir_path, 'rf')

  -- Ensure 'missing-directory' doesn't exist
  child.fn.delete('tests/dir-sessions/missing-directory', 'rf')

  -- Ensure 'global' does not contain file 'Session.vim'
  local files = { 'tests/dir-sessions/global/Session.vim' }

  for _, f in ipairs(files) do
    child.fn.delete(f)
  end
end

local get_latest_message = function() return child.cmd_capture('1messages') end

local get_buf_names = function()
  return child.lua_get('vim.tbl_map(function(x) return vim.fn.bufname(x) end, vim.api.nvim_list_bufs())')
end

local compare_buffer_names = function(x, y)
  -- Don't test exact equality because different Neovim versions create
  -- different buffer order when sourcing session (see
  -- https://github.com/vim/vim/pull/9520)
  table.sort(x)
  table.sort(y)
  eq(x, y)
end

-- Helpers for validating sessions
local populate_sessions = function(delay)
  delay = delay or 0

  child.fn.delete(empty_dir_path, 'rf')
  child.fn.mkdir(empty_dir_path)

  local make_file = function(name)
    local path = make_path(empty_dir_path, name)
    local value = make_path(empty_dir_relpath, name)
    child.fn.writefile({ ([[lua _G.session_file = '%s']]):format(value) }, path)
  end

  make_file('session_a')
  -- Modification time is up to seconds, so wait to ensure correct order
  sleep(delay)
  make_file('session_b')

  return empty_dir_path
end

local validate_session_loaded = function(relative_path)
  local path = make_path('tests/dir-sessions', relative_path)

  -- It should actually source file
  eq(child.lua_get('_G.session_file'), path)

  -- It should set `this_session`
  eq(child.v.this_session, make_path(project_root, path))
end

local validate_no_session_loaded = function() eq(child.lua_get('type(_G.session_file)'), 'nil') end

local reset_session_indicator = function() child.lua('_G.session_file = nil') end

-- Helpers for testing hooks
--stylua: ignore start
local make_hook_string = function(pre_post, action, hook_type)
  if hook_type == 'config' then
    return string.format(
      [[{ %s = { %s = function(...) _G.hooks_args = { ... }; _G.hooks_%s_%s = 'config' end }}]],
      pre_post, action, pre_post, action
    )
  end
  if hook_type == 'opts' then
    return string.format(
      [[{ %s = function(...) _G.hooks_args = { ... }; _G.hooks_%s_%s = 'opts' end }]],
      pre_post, pre_post, action
    )
  end
end
--stylua: ignore end

local validate_executed_hook = function(pre_post, action, value)
  local var_name = ('_G.hooks_%s_%s'):format(pre_post, action)
  eq(child.lua_get(var_name), value)

  -- Only one argument should be passed
  local hooks_args = child.lua_get('_G.hooks_args')
  eq(vim.tbl_keys(hooks_args), { 1 })

  -- It is a session data
  local data = hooks_args[1]
  local keys = vim.tbl_keys(data)
  table.sort(keys)
  eq(keys, { 'modify_time', 'name', 'path', 'type' })
  eq(vim.tbl_map(function(x) return type(data[x]) end, keys), { 'number', 'string', 'string', 'string' })
end

-- Time constants
local one_second_delay = 1000
local small_time = helpers.get_time_const(10)

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()

      -- Ensure `require('mini.sessions')` is always possible (which might not be
      -- the case with all present `cd` calls)
      child.cmd('set rtp+=' .. project_root)

      -- Ensure always identical starting current directory
      cd(project_root)

      -- Ensure directory structure invariants
      cleanup_directories()

      -- Make all showed messages full width
      child.o.cmdheight = 10

      -- Load module
      load_module()

      -- Ensure clear message history
      child.cmd('messages clear')
    end,
    post_once = function()
      cleanup_directories()
      child.stop()
    end,
  },
  n_retry = helpers.get_n_retry(1),
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  -- Global variable
  eq(child.lua_get('type(_G.MiniSessions)'), 'table')

  -- Autocommand group
  eq(child.fn.exists('#MiniSessions'), 1)
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniSessions.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniSessions.config.' .. field), value) end

  expect_config('autoread', false)
  expect_config('autowrite', true)
  expect_config('directory', child.fn.stdpath('data') .. '/session')
  expect_config('file', 'Session.vim')
  expect_config('force', { read = false, write = true, delete = false })
  expect_config('hooks.pre', { read = nil, write = nil, delete = nil })
  expect_config('hooks.post', { read = nil, write = nil, delete = nil })
  expect_config('verbose', { read = false, write = true, delete = true })
end

T['setup()']['respects `config` argument'] = function()
  reload_module({ autoread = true })
  eq(child.lua_get('MiniSessions.config.autoread'), true)
end

T['setup()']['validates `config` argument'] = function()
  unload_module()

  local expect_config_error = function(config, name, target_type)
    expect.error(function() load_module(config) end, vim.pesc(name) .. '.*' .. vim.pesc(target_type))
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ autoread = 'a' }, 'autoread', 'boolean')
  expect_config_error({ autowrite = 'a' }, 'autowrite', 'boolean')
  expect_config_error({ directory = 1 }, 'directory', 'string')
  expect_config_error({ file = 1 }, 'file', 'string')
  expect_config_error({ force = 'a' }, 'force', 'table')
  expect_config_error({ force = { read = 'a' } }, 'force.read', 'boolean')
  expect_config_error({ force = { write = 'a' } }, 'force.write', 'boolean')
  expect_config_error({ force = { delete = 'a' } }, 'force.delete', 'boolean')
  expect_config_error({ hooks = 'a' }, 'hooks', 'table')
  expect_config_error({ hooks = { pre = 'a' } }, 'hooks.pre', 'table')
  expect_config_error({ hooks = { pre = { read = 'a' } } }, 'hooks.pre.read', 'function')
  expect_config_error({ hooks = { pre = { write = 'a' } } }, 'hooks.pre.write', 'function')
  expect_config_error({ hooks = { pre = { delete = 'a' } } }, 'hooks.pre.delete', 'function')
  expect_config_error({ hooks = { post = 'a' } }, 'hooks.post', 'table')
  expect_config_error({ hooks = { post = { read = 'a' } } }, 'hooks.post.read', 'function')
  expect_config_error({ hooks = { post = { write = 'a' } } }, 'hooks.post.write', 'function')
  expect_config_error({ hooks = { post = { delete = 'a' } } }, 'hooks.post.delete', 'function')
  expect_config_error({ verbose = 'a' }, 'verbose', 'table')
  expect_config_error({ verbose = { read = 'a' } }, 'verbose.read', 'boolean')
  expect_config_error({ verbose = { write = 'a' } }, 'verbose.write', 'boolean')
  expect_config_error({ verbose = { delete = 'a' } }, 'verbose.delete', 'boolean')
end

T['setup()']['detects sessions and respects `config.directory`'] = function()
  cd('tests', 'dir-sessions')

  reload_module({ directory = 'global' })
  local detected = child.lua_get('MiniSessions.detected')

  -- Should be a table with correct keys
  eq(type(detected), 'table')
  local keys = vim.tbl_keys(detected)
  table.sort(keys)
  --stylua: ignore
  eq(keys, {
    '.session', 'Session.vim', 'session1', 'session2.vim', 'session3.lua',
    'session_cd_global', 'session_cd_local', 'session_cd_local_2'
  })

  -- Elements should have correct structure
  local cur_dir = child.fn.getcwd()
  local session_dir = make_path(cur_dir, 'global')
  for key, val in pairs(detected) do
    eq(type(val.modify_time), 'number')
    eq(val.name, key)

    if val.name == 'Session.vim' then
      eq(val.type, 'local')
      eq(val.path, make_path(cur_dir, 'Session.vim'))
    else
      eq(val.type, 'global')
      eq(val.path, make_path(session_dir, val.name))
    end
  end
end

T['setup()']['prefers local session file over global'] = function()
  -- Make file 'Session.vim' be in both `config.directory` and current one
  local path_local = 'tests/dir-sessions/global/Session.vim'
  child.fn.writefile({ ([[lua _G.session_file = '%s']]):format(path_local) }, path_local)

  cd('tests', 'dir-sessions')

  reload_module({ directory = 'global' })
  local detected = child.lua_get('MiniSessions.detected')
  local expected_path = project_root .. '/tests/dir-sessions/Session.vim'

  eq(detected['Session.vim'].path, expected_path)
end

T['setup()']['allows empty string for `config.directory`'] = function()
  reload_module({ directory = '' })
  eq(child.lua_get('MiniSessions.detected'), {})
end

T['setup()']['creates missing `config.directory`'] = function()
  local directory = 'tests/dir-sessions/missing-directory'

  eq(child.fn.isdirectory(directory), 0)
  reload_module({ directory = directory })
  eq(child.fn.isdirectory(directory), 1)
end

T['setup()']['does not create `config.directory` if it is an existing file'] = function()
  reload_module({ directory = 'lua/mini/sessions.lua' })
  expect.match(get_latest_message(), '%(mini%.sessions%).*lua/mini/sessions%.lua.*is not a directory path')
end

T['setup()']['respects `config.file`'] = function()
  cd('tests', 'dir-sessions', 'local')

  reload_module({ autowrite = false, file = 'alternative-local-session' })
  local detected = child.lua_get('MiniSessions.detected')

  eq(detected['Session.vim'], nil)
  eq(detected['alternative-local-session'].type, 'local')
end

T['setup()']['allows empty string for `config.file`'] = function()
  cd('tests/dir-sessions')
  reload_module({ file = '' })
  local detected = child.lua_get('MiniSessions.detected')
  eq(vim.tbl_filter(function(x) return x.type == 'local' end, detected), {})
end

T['detected'] = new_set()

T['detected']['is present'] = function()
  cd('tests', 'dir-sessions')
  reload_module({ directory = 'global' })
  eq(child.lua_get('type(MiniSessions.detected)'), 'table')
end

T['detected']['is an empty table if no sessions are detected'] = function()
  reload_module({ directory = vim.fn.fnamemodify(child.fn.tempname(), ':h') })
  eq(child.lua_get('MiniSessions.detected'), {})
end

T['read()'] = new_set()

T['read()']['works'] = function()
  reload_module({ autowrite = false, directory = 'tests/dir-sessions/global' })
  child.lua([[MiniSessions.read('session1')]])
  validate_session_loaded('global/session1')
end

T['read()']['works with no detected sessions'] = function()
  reload_module({ directory = '', file = '' })
  eq(child.lua_get('MiniSessions.detected'), {})
  expect.no_error(function() child.lua('MiniSessions.read()') end)
  expect.match(get_latest_message(), '%(mini%.sessions%) There are no detected sessions')
end

T['read()']['accepts only name of detected session'] = function()
  reload_module({ autowrite = false, directory = 'tests/dir-sessions/global' })
  expect.error(
    function() child.lua([[MiniSessions.read('session-absent')]]) end,
    '%(mini%.sessions%) "session%-absent" is not a name for detected session'
  )
  validate_no_session_loaded()
end

T['read()']['removes stale local session from detected'] = function()
  -- Start in 'local' directory
  cd('tests', 'dir-sessions', 'local')
  reload_module({ autowrite = false, directory = project_root .. '/tests/dir-sessions/global' })
  eq(child.lua_get([[MiniSessions.detected['Session.vim'] ~= nil]]), true)

  -- Test yes local -> no local
  child.lua([[MiniSessions.read('session_cd_global')]])
  validate_session_loaded('global/session_cd_global')
  eq(child.lua_get([[MiniSessions.detected['Session.vim'] ~= nil]]), false)

  -- Test no local -> yes local
  child.lua([[MiniSessions.read('session_cd_local')]])
  validate_session_loaded('global/session_cd_local')
  eq(child.lua_get([[MiniSessions.detected['Session.vim'] ~= nil]]), true)

  -- Test yes local -> yes other local
  child.lua([[MiniSessions.read('session_cd_local_2')]])
  validate_session_loaded('global/session_cd_local_2')
  eq(child.lua_get([[MiniSessions.detected['Session.vim'] ~= nil]]), true)
  local other_local_path = project_root .. '/tests/dir-sessions/local-2/Session.vim'
  eq(child.lua_get([[MiniSessions.detected['Session.vim'].path ]]), other_local_path)
end

T['read()']['makes detected sessions up to date'] = function()
  local new_session = 'tests/dir-sessions/global/new_session'
  MiniTest.finally(function() vim.fn.delete(new_session) end)

  -- Detect sessions without new session
  reload_module({ autowrite = false, directory = 'tests/dir-sessions/global' })
  eq(child.lua_get('MiniSessions.detected.new_session == nil'), true)

  -- Create new session file manually and try to read it directly without
  -- reloading whole module.
  child.fn.writefile({ 'lua _G.session_file = ' .. vim.inspect(new_session) }, new_session)

  child.lua([[MiniSessions.read('new_session')]])
  validate_session_loaded('global/new_session')
end

local setup_unsaved_buffers = function()
  child.o.hidden = true
  local res = {}
  set_lines({ 'aaa' })
  table.insert(res, child.api.nvim_get_current_buf())

  child.cmd('e foo')
  set_lines({ 'bbb' })
  table.insert(res, child.api.nvim_get_current_buf())

  return res
end

T['read()']['does not source if there are unsaved listed buffers'] = function()
  reload_module({ autowrite = false, directory = 'tests/dir-sessions/global' })

  -- Setup unsaved buffers
  local unsaved_buffers = setup_unsaved_buffers()

  -- Session should not be sourced
  local error_pattern =
    vim.pesc('(mini.sessions) There are unsaved listed buffers: ' .. table.concat(unsaved_buffers, ', ') .. '.')
  expect.error(function() child.lua([[MiniSessions.read('session1')]]) end, error_pattern)
  validate_no_session_loaded()
end

T['read()']['ignores unsaved not listed buffers'] = function()
  reload_module({ autowrite = false, directory = 'tests/dir-sessions/global' })
  local buf_id = child.api.nvim_create_buf(false, false)
  child.api.nvim_buf_set_lines(buf_id, 0, -1, true, { 'aaa' })
  eq(child.api.nvim_buf_get_option(buf_id, 'modified'), true)
  eq(child.api.nvim_buf_get_option(buf_id, 'buflisted'), false)

  child.lua([[MiniSessions.read('session1')]])
  validate_session_loaded('global/session1')
end

T['read()']['uses by default local session'] = function()
  cd('tests', 'dir-sessions', 'local')
  reload_module({ autowrite = false, directory = 'tests/dir-sessions/global' })

  eq(child.lua_get([[MiniSessions.detected['Session.vim'].type]]), 'local')
  child.lua('MiniSessions.read()')
  validate_session_loaded('local/Session.vim')
end

T['read()']['uses by default latest global session'] = function()
  local session_dir = populate_sessions(one_second_delay + small_time)

  reload_module({ autowrite = false, directory = session_dir })
  child.lua('MiniSessions.read()')
  validate_session_loaded('empty/session_b')
end

T['read()']['respects `force` from `config` and `opts` argument'] = function()
  reload_module({ autowrite = false, directory = 'tests/dir-sessions/global', force = { read = true } })

  -- Should overwrite unsaved buffers and load session if `force` is `true`
  setup_unsaved_buffers()
  child.lua([[MiniSessions.read('session1')]])
  validate_session_loaded('global/session1')

  -- Should prefer `opts` over `config`
  setup_unsaved_buffers()
  reset_session_indicator()
  expect.error(
    function() child.lua([[MiniSessions.read('session2.vim', { force = false })]]) end,
    '%(mini%.sessions%) There are unsaved listed buffers'
  )
  validate_no_session_loaded()
end

T['read()']['does not stop on source error'] = function()
  reload_module({ autowrite = false, directory = 'tests/dir-sessions/global' })

  local session_file = 'tests/dir-sessions/global/session_with_error'
  local folded_file = 'tests/dir-sessions/folded_file'
  local extra_file = 'tests/dir-sessions/extra_file'
  MiniTest.finally(function()
    vim.fn.delete(session_file)
    vim.fn.delete(folded_file)
    vim.fn.delete(extra_file)
  end)

  -- Create buffer with non-trivial folds to imitate "No folds found" error
  child.o.foldmethod = 'indent'
  child.cmd('edit ' .. folded_file)
  set_lines({ 'a', '\ta', '\ta', 'a', '\ta', '\ta' })
  child.cmd('write')

  child.cmd('normal! zM')
  child.cmd('2 | normal! zo')

  -- Create another buffer to check correct session read
  child.cmd('edit ' .. extra_file)
  set_lines({ 'This should be preserved in session' })
  child.cmd('write')

  -- Write session and make sure it contains call to open folds
  child.cmd('edit ' .. folded_file)
  child.cmd('mksession ' .. session_file)

  local session_lines = table.concat(child.fn.readfile(session_file), '\n')
  expect.match(session_lines, 'normal! zo')

  -- Modify file so that no folds will be found by session file
  child.fn.writefile({ 'No folds in this file' }, folded_file)

  -- Cleanly read session which should open foldless file without errors
  child.restart()
  load_module({ autowrite = false, directory = 'tests/dir-sessions/global' })

  expect.no_error(function() child.lua([[MiniSessions.read('session_with_error')]]) end)

  local buffers = child.api.nvim_list_bufs()
  eq(#buffers, 2)

  child.api.nvim_set_current_buf(buffers[1])
  local buf_name_1 = child.fs.normalize(child.api.nvim_buf_get_name(0))
  eq(vim.endswith(buf_name_1, '/' .. folded_file), true)
  eq(child.api.nvim_buf_get_lines(0, 0, -1, true), { 'No folds in this file' })

  child.api.nvim_set_current_buf(buffers[2])
  local buf_name_2 = child.fs.normalize(child.api.nvim_buf_get_name(0))
  eq(vim.endswith(buf_name_2, '/' .. extra_file), true)
  eq(child.api.nvim_buf_get_lines(0, 0, -1, true), { 'This should be preserved in session' })
end

T['read()']['writes current session prior to reading a new one'] = function()
  local cur_session = project_root .. '/tests/dir-sessions/global/current-session'
  MiniTest.finally(function() child.fn.delete(cur_session) end)

  local validate = function(ref_autowrite)
    reload_module({ autowrite = false, directory = 'tests/dir-sessions/global' })
    child.v.this_session = cur_session
    child.lua('MiniSessions.config.autowrite = ' .. tostring(ref_autowrite))

    eq(child.fn.filereadable(cur_session), 0)
    child.lua('MiniSessions.read("session1")')
    -- Should only write current if `autowrite` is enabled
    eq(child.fn.filereadable(cur_session), ref_autowrite and 1 or 0)
    child.fn.delete(cur_session)
  end

  validate(true)
  validate(false)
end

T['read()']['respects hooks from `config` and `opts` argument'] = new_set({
  parametrize = { { 'pre' }, { 'post' } },
}, {
  test = function(pre_post)
    -- Should use `config`
    local hook_string_config = make_hook_string(pre_post, 'read', 'config')
    reload_from_strconfig({
      autowrite = 'false',
      directory = [['tests/dir-sessions/global']],
      hooks = hook_string_config,
    })
    child.lua([[MiniSessions.read('session1')]])

    validate_session_loaded('global/session1')
    validate_executed_hook(pre_post, 'read', 'config')
    -- - Make sure that current session is not written
    child.v.this_session = ''

    -- Should prefer `opts` over `config`
    local hook_string_opts = make_hook_string(pre_post, 'read', 'opts')
    child.lua(([[MiniSessions.read('session2.vim', { hooks = %s })]]):format(hook_string_opts))

    validate_session_loaded('global/session2.vim')
    validate_executed_hook(pre_post, 'read', 'opts')
  end,
})

T['read()']['respects `verbose` from `config` and `opts` argument'] = function()
  reload_module({ autowrite = false, directory = 'tests/dir-sessions/global', verbose = { read = true } })

  -- Should give message about read session
  child.lua([[MiniSessions.read('session1')]])
  validate_session_loaded('global/session1')
  expect.match(get_latest_message(), '%(mini%.sessions%) Read session.*session1')
  -- - Make sure that current session is not written
  child.v.this_session = ''

  -- Should prefer `opts` over `config`
  reset_session_indicator()
  child.lua([[MiniSessions.read('session2.vim', { verbose = false })]])
  validate_session_loaded('global/session2.vim')
end

T['read()']['respects `vim.{g,b}.minisessions_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    reload_module({ autowrite = false, directory = 'tests/dir-sessions/global' })
    child[var_type].minisessions_disable = true

    reset_session_indicator()
    child.lua([[MiniSessions.read('session1')]])
    validate_no_session_loaded()
  end,
})

T['write()'] = new_set()

T['write()']['works'] = function()
  child.fn.mkdir(empty_dir_path)
  reload_module({ autowrite = false, directory = empty_dir_path })

  -- Setup buffers
  child.cmd('e foo | e bar')
  local buf_names_expected = get_buf_names()
  child.lua([[MiniSessions.write('new_session')]])

  -- Should update `v:this_session`
  local path_expected = make_path(empty_dir_path, 'new_session')
  eq(child.v.this_session, path_expected)

  -- Verify that written session is correct
  child.cmd('%bwipeout')
  child.cmd('source ' .. path_expected)
  compare_buffer_names(get_buf_names(), buf_names_expected)
end

T['write()']['updates `v:this_session`'] = function()
  child.fn.mkdir(empty_dir_path)
  reload_module({ autowrite = false, directory = empty_dir_path })

  eq(child.v.this_session, '')
  child.lua([[MiniSessions.write('new_session')]])
  eq(child.v.this_session, make_path(empty_dir_path, 'new_session'))
end

T['write()']['updates `MiniSessions.detected` with new session'] = function()
  child.fn.mkdir(empty_dir_path)
  reload_module({ autowrite = false, directory = empty_dir_path })

  eq(child.lua_get('MiniSessions.detected'), {})
  child.lua([[MiniSessions.write('new_session')]])
  eq(child.lua_get('MiniSessions.detected.new_session').path, make_path(empty_dir_path, 'new_session'))
end

T['write()']['updates `MiniSessions.detected` for present session'] = function()
  local session_dir = populate_sessions(one_second_delay + small_time)
  reload_module({ directory = session_dir })

  child.lua([[MiniSessions.read('session_a')]])
  sleep(one_second_delay + small_time)
  child.lua([[MiniSessions.write('session_a')]])

  local detected = child.lua_get('MiniSessions.detected')
  eq(detected.session_a.modify_time > detected.session_b.modify_time, true)
end

T['write()']['validates `session_name`'] = function()
  reload_module({ autowrite = false, directory = 'tests/dir-sessions/global' })
  expect.error(
    function() child.lua([[MiniSessions.write('')]]) end,
    '%(mini%.sessions%) Supply non%-empty session name'
  )
end

T['write()']['writes by default to `v:this_session`'] = function()
  local session_dir = populate_sessions()
  reload_module({ directory = session_dir })
  child.lua([[MiniSessions.read('session_a')]])

  -- Verify that `v:this_session` points to correct place
  local session_path = make_path(session_dir, 'session_a')
  eq(child.v.this_session, session_path)

  -- Write session with `session_name = nil`
  child.cmd('e foo | e bar')
  local buf_names_expected = get_buf_names()
  child.lua('MiniSessions.write()')

  -- Verify that it was actually written to `v:this_session`
  child.cmd('%bwipeout!')
  child.cmd('source ' .. session_path)
  compare_buffer_names(get_buf_names(), buf_names_expected)
end

T['write()']['writes to current directory if passed name of local session file'] = function()
  reload_module({ file = 'new-local-session', directory = '' })

  child.fn.mkdir(empty_dir_path)
  cd(empty_dir_path)
  child.lua([[MiniSessions.write('new-local-session')]])

  local path = make_path(empty_dir_path, 'new-local-session')
  eq(child.fn.filereadable(path), 1)
end

T['write()']['writes to global directory'] = function()
  child.fn.mkdir(empty_dir_path)
  reload_module({ file = '', directory = empty_dir_path })

  child.lua([[MiniSessions.write('new-global-session')]])

  local target_path = make_path(empty_dir_path, 'new-global-session')
  eq(child.fn.filereadable(target_path), 1)
end

T['write()']['respects `force` from `config` and `opts` argument'] = function()
  child.fn.mkdir(empty_dir_path)
  reload_module({ directory = empty_dir_path, force = { write = false } })

  -- Should not allow writing to existing file if `force` is `false`
  local path = make_path(empty_dir_path, 'existing-file')
  child.fn.writefile({}, path)

  expect.error(
    function() child.lua([[MiniSessions.write('existing-file')]]) end,
    [[%(mini%.sessions%) Can't write to existing]]
  )
  eq(child.fn.readfile(path), {})

  -- Should prefer `opts` over `config`
  child.lua([[MiniSessions.write('existing-file', { force = true })]])
  eq(#child.fn.readfile(path) > 0, true)
end

T['write()']['respects hooks from `config` and `opts` argument'] = new_set({
  parametrize = { { 'pre' }, { 'post' } },
}, {
  test = function(pre_post)
    child.fn.mkdir(empty_dir_path)
    local path

    -- Should use `config`
    local hook_string_config = make_hook_string(pre_post, 'write', 'config')
    reload_from_strconfig({ directory = vim.inspect(empty_dir_path), hooks = hook_string_config })
    child.lua([[MiniSessions.write('file_01')]])

    path = make_path(empty_dir_path, 'file_01')
    eq(#child.fn.readfile(path) > 0, true)
    validate_executed_hook(pre_post, 'write', 'config')

    -- Should prefer `opts` over `config`
    local hook_string_opts = make_hook_string(pre_post, 'write', 'opts')
    child.lua(([[MiniSessions.write('file_02', { hooks = %s })]]):format(hook_string_opts))

    path = make_path(empty_dir_path, 'file_02')
    eq(#child.fn.readfile(path) > 0, true)
    validate_executed_hook(pre_post, 'write', 'opts')
  end,
})

T['write()']['respects `verbose` from `config` and `opts` argument'] = function()
  child.fn.mkdir(empty_dir_path)
  reload_module({ directory = empty_dir_path, verbose = { write = false } })
  local msg_pattern = '%(mini%.sessions%) Written session.*session%-written'

  -- Should not give message about written session
  child.lua([[MiniSessions.write('session-written')]])
  local path = make_path(empty_dir_path, 'session-written')
  eq(#child.fn.readfile(path) > 0, true)
  expect.no_match(get_latest_message(), msg_pattern)

  -- Should prefer `opts` over `config`
  child.fn.delete(path)
  child.lua([[MiniSessions.write('session-written', { verbose = true })]])
  eq(#child.fn.readfile(path) > 0, true)
  expect.match(get_latest_message(), msg_pattern)
end

T['write()']['respects `vim.{g,b}.minisessions_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child.fn.mkdir(empty_dir_path)
    reload_module({ directory = empty_dir_path })
    local path = make_path(empty_dir_path, 'session-file')

    child[var_type].minisessions_disable = true

    child.fn.delete(path)
    child.lua([[MiniSessions.write('session-file')]])
    eq(child.fn.filereadable('session-file'), 0)
  end,
})

T['delete()'] = new_set()

T['delete()']['works'] = function()
  local session_dir = populate_sessions()
  reload_module({ directory = session_dir })
  local path = make_path(session_dir, 'session_a')

  eq(child.lua_get('MiniSessions.detected')['session_a'].path, path)
  child.lua([[MiniSessions.delete('session_a')]])
  eq(child.fn.filereadable(path), 0)
end

T['delete()']['validates presence of detected sessions'] = function()
  reload_module({ file = '', directory = '' })

  expect.error(
    function() child.lua([[MiniSessions.delete('aaa')]]) end,
    '%(mini%.sessions%) There are no detected sessions'
  )
end

T['delete()']['validates `session_name`'] = function()
  reload_module({ directory = 'tests/dir-sessions/global' })
  expect.error(
    function() child.lua([[MiniSessions.delete('')]]) end,
    '%(mini%.sessions%) Supply non%-empty session name'
  )
end

T['delete()']['deletes by default `v:this_session`'] = function()
  local session_dir = populate_sessions()
  reload_module({ directory = session_dir, force = { delete = true } })

  child.lua([[MiniSessions.read('session_a')]])
  local path = make_path(session_dir, 'session_a')
  eq(child.v.this_session, path)

  child.lua('MiniSessions.delete()')
  eq(child.fn.filereadable(path), 0)

  -- Should also update `v:this_session`
  eq(child.v.this_session, '')
end

T['delete()']['deletes from current directory if passed name of local session file'] = function()
  local session_dir = populate_sessions()
  cd(session_dir)
  reload_module({ file = 'session_a', directory = '' })
  eq(child.lua_get('MiniSessions.detected.session_a.type'), 'local')

  child.lua([[MiniSessions.delete('session_a')]])

  local path = make_path(session_dir, 'session_a')
  eq(child.fn.filereadable(path), 0)
end

T['delete()']['deletes from global directory'] = function()
  local session_dir = populate_sessions()
  reload_module({ file = '', directory = session_dir })
  eq(child.lua_get('MiniSessions.detected.session_a.type'), 'global')

  child.lua([[MiniSessions.delete('session_a')]])

  local path = make_path(session_dir, 'session_a')
  eq(child.fn.filereadable(path), 0)
end

T['delete()']['makes detected sessions up to date'] = function()
  local new_session = 'tests/dir-sessions/global/new_session'
  MiniTest.finally(function() vim.fn.delete(new_session) end)

  -- Detect sessions without new session
  reload_module({ autowrite = false, directory = 'tests/dir-sessions/global' })
  eq(child.lua_get('MiniSessions.detected.new_session == nil'), true)

  -- Create new session file manually and try to delete it directly without
  -- reloading whole module.
  child.fn.writefile({ 'lua _G.session_file = ' .. vim.inspect(new_session) }, new_session)

  child.lua([[MiniSessions.delete('new_session')]])
  eq(child.fn.filereadable(new_session), 0)
end

T['delete()']['respects `force` from `config` and `opts` argument'] = function()
  local session_dir = populate_sessions()
  reload_module({ directory = session_dir, force = { delete = true } })
  local path

  -- Should allow deleting current session if `force` is `false`
  child.lua([[MiniSessions.read('session_a')]])
  path = make_path(session_dir, 'session_a')
  eq(child.v.this_session, path)

  child.lua([[MiniSessions.delete('session_a')]])
  eq(child.fn.filereadable(path), 0)

  -- Should prefer `opts` over `config`
  child.lua([[MiniSessions.read('session_b')]])
  path = make_path(session_dir, 'session_b')
  eq(child.v.this_session, path)

  expect.error(
    function() child.lua([[MiniSessions.delete('session_b', { force = false })]]) end,
    [[%(mini%.sessions%) Can't delete current session]]
  )
  eq(child.fn.filereadable(path), 1)
end

T['delete()']['respects hooks from `config` and `opts` argument'] = new_set({
  parametrize = { { 'pre' }, { 'post' } },
}, {
  test = function(pre_post)
    local session_dir = populate_sessions()
    local path

    -- Should use `config`
    local hook_string_config = make_hook_string(pre_post, 'delete', 'config')
    reload_from_strconfig({ directory = vim.inspect(session_dir), hooks = hook_string_config })
    child.lua([[MiniSessions.delete('session_a')]])

    path = make_path(session_dir, 'session_a')
    eq(child.fn.filereadable(path), 0)
    validate_executed_hook(pre_post, 'delete', 'config')

    -- Should prefer `opts` over `config`
    local hook_string_opts = make_hook_string(pre_post, 'delete', 'opts')
    child.lua(([[MiniSessions.delete('session_b', { hooks = %s })]]):format(hook_string_opts))

    path = make_path(session_dir, 'session_b')
    eq(child.fn.filereadable(path), 0)
    validate_executed_hook(pre_post, 'delete', 'opts')
  end,
})

T['delete()']['respects `verbose` from `config` and `opts` argument'] = function()
  local session_dir = populate_sessions()
  reload_module({ directory = session_dir, verbose = { delete = false } })
  local msg_pattern = '%(mini%.sessions%) Deleted session.*'
  local path

  -- Should not give message about deleted session
  child.lua([[MiniSessions.delete('session_a')]])
  path = make_path(session_dir, 'session_a')
  eq(child.fn.filereadable(path), 0)
  expect.no_match(get_latest_message(), msg_pattern .. 'session_a')

  -- Should prefer `opts` over `config`
  child.lua([[MiniSessions.delete('session_b', { verbose = true })]])
  path = make_path(session_dir, 'session_b')
  eq(child.fn.filereadable(path), 0)
  expect.match(get_latest_message(), msg_pattern .. 'session_b')
end

T['delete()']['respects `vim.{g,b}.minisessions_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    local session_dir = populate_sessions()
    reload_module({ directory = session_dir })
    local path = make_path(session_dir, 'session_a')

    child[var_type].minisessions_disable = true

    if child.fn.filereadable(path) == 0 then populate_sessions() end
    child.lua([[MiniSessions.delete('session_a')]])
    eq(child.fn.filereadable(path), 1)
  end,
})

T['select()'] = new_set({
  hooks = {
    pre_case = function()
      -- Mock `vim.ui.select`
      child.lua('vim.ui = { select = function(...) _G.ui_select_args = { ... } end }')

      -- Load module with detected sessions
      local session_dir = populate_sessions()

      -- Add local session
      cd(session_dir)
      child.fn.writefile({}, make_path(session_dir, 'Session.vim'), '')

      reload_module({ directory = session_dir })
    end,
  },
})

T['select()']['works'] = function()
  child.lua('MiniSessions.select()')

  -- Should place local session first and then others alphabetically
  eq(child.lua_get('_G.ui_select_args[1]'), { 'Session.vim', 'session_a', 'session_b' })

  -- Should give informative prompt
  eq(child.lua_get('_G.ui_select_args[2].prompt'), 'Select session to read')

  -- Should format items by appending session type
  eq(child.lua_get([[_G.ui_select_args[2].format_item('Session.vim')]]), 'Session.vim (local)')
  eq(child.lua_get([[_G.ui_select_args[2].format_item('session_a')]]), 'session_a (global)')

  -- By default should read selected session
  validate_no_session_loaded()
  child.lua([[_G.ui_select_args[3]('session_a', 2)]])
  validate_session_loaded('empty/session_a')
end

T['select()']['makes detected sessions up to date'] = function()
  child.lua('MiniSessions.select()')
  eq(child.lua_get('_G.ui_select_args[1]'), { 'Session.vim', 'session_a', 'session_b' })

  -- Remove 'session_a' manually which should be shown in `select()` output
  local directory = child.lua_get('MiniSessions.config.directory')
  child.fn.delete(make_path(directory, 'session_a'), 'rf')

  child.lua('MiniSessions.select()')
  eq(child.lua_get('_G.ui_select_args[1]'), { 'Session.vim', 'session_b' })
end

T['select()']['verifies presence of `vim.ui` and `vim.ui.select`'] = function()
  child.lua('vim.ui = 1')
  expect.error(function() child.lua('MiniSessions.select()') end, '%(mini%.sessions%).*vim%.ui')

  child.lua('vim.ui = {}')
  expect.error(function() child.lua('MiniSessions.select()') end, '%(mini%.sessions%).*vim%.ui%.select')
end

T['select()']['validates `action` argument'] = function()
  expect.error(
    function() child.lua([[MiniSessions.select('aaa')]]) end,
    [[%(mini%.sessions%) `action` should be one of 'read', 'write', or 'delete'.]]
  )
end

T['select()']['respects `action` argument'] = function()
  local session_dir = child.lua_get('MiniSessions.config.directory')
  local path = make_path(session_dir, 'session_a')
  eq(child.fn.filereadable(path), 1)

  child.lua([[MiniSessions.select('delete')]])
  child.lua([[_G.ui_select_args[3]('session_a', 2)]])
  eq(child.fn.filereadable(path), 0)
end

T['select()']['respects `opts` argument'] = function()
  child.lua([[MiniSessions.select('read', { verbose = true })]])

  local msg_pattern = '%(mini%.sessions%) Read session.*session_a'
  expect.no_match(get_latest_message(), msg_pattern)
  child.lua([[_G.ui_select_args[3]('session_a', 2)]])
  validate_session_loaded('empty/session_a')
  expect.match(get_latest_message(), msg_pattern)
end

T['get_latest()'] = new_set()

T['get_latest()']['works'] = function()
  local dir = populate_sessions(one_second_delay + small_time)
  reload_module({ directory = dir })
  eq(child.lua_get('MiniSessions.get_latest()'), 'session_b')
end

T['get_latest()']['works if there are no detected sessions'] = function()
  reload_module({ directory = '', file = '' })
  eq(child.lua_get('MiniSessions.get_latest()'), vim.NIL)
end

-- Integration tests ==========================================================
T['Autoreading sessions'] = new_set()

T['Autoreading sessions']['works'] = function()
  child.restart({ '-u', 'tests/dir-sessions/init-files/autoread.lua' })
  validate_session_loaded('local/Session.vim')
end

T['Autoreading sessions']['does not autoread if Neovim started to show something'] = function()
  local init_autoread = 'tests/dir-sessions/init-files/autoread.lua'
  local validate = function(...)
    child.restart({ '-u', init_autoread, ... })
    validate_no_session_loaded()
  end

  -- There are files in arguments (like `nvim foo.txt` with new file).
  validate('new-file.txt')

  -- Several buffers are listed (like session with placeholder buffers)
  validate('-c', 'e foo | set buflisted | e bar | set buflisted')

  -- Unlisted buffers (like from `nvim-tree`) don't affect decision
  child.restart({ '-u', init_autoread, '-c', 'e foo | set nobuflisted | e bar | set buflisted' })
  validate_session_loaded('local/Session.vim')

  -- Current buffer is meant to show something else
  validate('-c', 'set filetype=text')

  -- Current buffer has any lines (something opened explicitly)
  validate('-c', [[call setline(1, 'a')]])
end

T['Autowriting sessions'] = new_set()

T['Autowriting sessions']['works'] = function()
  local init_autowrite = 'tests/dir-sessions/init-files/autowrite.lua'
  child.restart({ '-u', init_autowrite })

  -- Create session with one buffer, expect to autowrite it with second
  child.fn.mkdir(empty_dir_path)
  cd(empty_dir_path)
  child.cmd('e aaa | w | mksession')
  local path_local = make_path(empty_dir_path, 'Session.vim')
  eq(child.fn.filereadable(path_local), 1)

  child.cmd('e bbb | w')
  child.restart({ '-u', 'NONE' })
  child.cmd('source ' .. path_local)
  compare_buffer_names(get_buf_names(), { 'aaa', 'bbb' })
end

return T
