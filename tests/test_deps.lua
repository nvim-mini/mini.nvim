local helpers = dofile('tests/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('deps', config) end
local unload_module = function() child.mini_unload('deps') end
local sleep = function(ms) helpers.sleep(ms, child) end
--stylua: ignore end

-- TODO: Remove after compatibility with Neovim=0.9 is dropped
local islist = vim.fn.has('nvim-0.10') == 1 and vim.islist or vim.tbl_islist

local test_dir = 'tests/dir-deps'
local test_dir_absolute = vim.fs.normalize(vim.fn.fnamemodify(test_dir, ':p')):gsub('(.)/$', '%1')
local test_opt_dir = test_dir_absolute .. '/pack/deps/opt'
local test_snap_path = test_dir_absolute .. '/snapshots/snap'
local test_log_path = test_dir_absolute .. '/mini-deps.log'

-- Common test helpers
local log_level = function(level)
  if level == nil then return nil end
  return child.lua_get('vim.log.levels.' .. level)
end

local clone_args = function(from, to)
  --stylua: ignore
  return {
    'clone', '--quiet', '--filter=blob:none',
    '--recurse-submodules', '--also-filter-submodules',
    '--origin', 'origin', from, to,
  }
end

local log_args = function(range)
  return { 'log', '--pretty=format:%m %h | %ai | %an%d%n  %s%n', '--topo-order', '--decorate-refs=refs/tags', range }
end

local validate_confirm_buf = function(name)
  eq(child.api.nvim_buf_get_name(0), 'minideps://' .. child.api.nvim_get_current_buf() .. '/' .. name)
  eq(child.bo.buftype, 'acwrite')
  eq(child.bo.filetype, 'minideps-confirm')
  eq(#child.api.nvim_list_tabpages() > 1, true)
  eq(#child.api.nvim_tabpage_list_wins(0), 1)
end

local validate_not_confirm_buf = function()
  eq(#child.api.nvim_list_tabpages(), 1)
  eq(child.bo.filetype ~= 'minideps-confirm', true)
end

-- Common test wrappers
local forward_lua = function(fun_str)
  local lua_cmd = fun_str .. '(...)'
  return function(...) return child.lua_get(lua_cmd, { ... }) end
end

local add = forward_lua('MiniDeps.add')
local get_session = forward_lua('MiniDeps.get_session')

-- Common mocks
local mock_test_package = function(path)
  path = path or test_dir_absolute
  local lua_cmd = string.format(
    [[local config = vim.deepcopy(MiniDeps.config)
      config.path.package = %s
      MiniDeps.setup(config)]],
    vim.inspect(path)
  )
  child.lua(lua_cmd)
end

local mock_plugin = function(path)
  local lua_dir = path .. '/lua'
  child.fn.mkdir(lua_dir, 'p')
  child.fn.writefile({ 'return {}' }, lua_dir .. '/module.lua')
end

local mock_timestamp = function(timestamp)
  timestamp = timestamp or '2024-01-02 03:04:05'
  local lua_cmd = string.format('vim.fn.strftime = function() return %s end', vim.inspect(timestamp))
  child.lua(lua_cmd)
end

local mock_bad_env_vars = function()
  child.fn.setenv('GIT_DIR', test_dir_absolute .. '/.git')
  child.fn.setenv('GIT_WORK_TREE', test_dir_absolute)
end

local mock_hide_path = function(path)
  path = path or test_dir_absolute
  -- NOTE: use "^" as pattern separator because "/" can cause troubles
  child.cmd(':%s^' .. child.fn.escape(path, ' /') .. '^MOCKDIR^')
  child.bo.modified = false
end

local mock_spawn = function()
  local mock_file = test_dir_absolute .. '/mocks/spawn.lua'
  local lua_cmd = string.format('dofile(%s)', vim.inspect(mock_file))
  child.lua(lua_cmd)
end

local get_spawn_log = function() return child.lua_get('_G.spawn_log') end

local validate_git_spawn_log = function(ref_log)
  local spawn_log = get_spawn_log()

  local ref_env = child.fn.environ()
  -- Should never include environment variables that can affect Git operations
  ref_env.GIT_DIR, ref_env.GIT_WORK_TREE = nil, nil

  local n = math.max(#spawn_log, #ref_log)
  for i = 1, n do
    local real, ref = spawn_log[i], ref_log[i]
    if real == nil then
      eq('Real spawn log does not have entry for present reference log entry', ref)
    elseif ref == nil then
      eq(real, 'Reference does not have entry for present spawn log entry')
    elseif islist(ref) then
      -- Assume default `git` options
      local args = { '-c', 'gc.auto=0' }
      vim.list_extend(args, ref)
      local opts = { args = args, cwd = real.options.cwd, env = ref_env, clear_env = true }
      local ref_val = { executable = 'git', options = opts }
      eq(real, ref_val)
    else
      local opts = vim.deepcopy(ref)
      -- Assume default `git` options
      local args = { '-c', 'gc.auto=0' }
      opts.args = vim.list_extend(args, opts.args)
      if opts.env == nil then
        opts.env = opts.env or ref_env
        opts.clear_env = true
      end
      eq(real, { executable = 'git', options = opts })
    end
  end
end

local get_process_log = function() return child.lua_get('_G.process_log') end

-- Work with notifications
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
      eq(real[2], log_level(ref[2]))
    end
  end
end

local clear_notify_log = function() return child.lua('_G.notify_log = {}') end

-- Common validators
local is_in_rtp = function(path)
  path = child.fs.normalize(path)
  for _, p in ipairs(child.api.nvim_list_runtime_paths()) do
    if path == child.fs.normalize(p) then return true end
  end
  return false
end

-- Time constants
local small_time = helpers.get_time_const(10)
local micro_time = 1

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()

      -- Load module
      load_module()

      -- Make more comfortable screenshots
      child.o.laststatus = 0
      child.o.ruler = false
      child.o.showtabline = 0

      -- Mock `vim.notify()`
      mock_notify()

      -- Mock `vim.loop.spawn()`
      mock_spawn()

      -- Mock getting reproducible timestamp
      mock_timestamp()
    end,
    post_once = child.stop,
  },
  n_retry = helpers.get_n_retry(2),
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  -- Global variable
  eq(child.lua_get('type(_G.MiniDeps)'), 'table')

  -- Autocommand group
  eq(child.fn.exists('#MiniDeps'), 1)

  -- User commands
  local has_user_command = function(cmd) eq(child.fn.exists(':' .. cmd), 2) end
  has_user_command('DepsAdd')
  has_user_command('DepsUpdate')
  has_user_command('DepsUpdateOffline')
  has_user_command('DepsShowLog')
  has_user_command('DepsClean')
  has_user_command('DepsSnapSave')
  has_user_command('DepsSnapLoad')

  -- Highlight groups
  child.cmd('hi clear')
  load_module()
  local has_highlight = function(group, value) expect.match(child.cmd_capture('hi ' .. group), value) end

  local is_010 = child.fn.has('nvim-0.10') == 1
  has_highlight('MiniDepsChangeAdded', 'links to ' .. (is_010 and 'Added' or 'diffAdded'))
  has_highlight('MiniDepsChangeRemoved', 'links to ' .. (is_010 and 'Removed' or 'diffRemoved'))
  has_highlight('MiniDepsHint', 'links to DiagnosticHint')
  has_highlight('MiniDepsInfo', 'links to DiagnosticInfo')
  has_highlight('MiniDepsPlaceholder', 'links to Comment')
  has_highlight('MiniDepsTitle', 'links to Title')
  has_highlight('MiniDepsTitleError', 'links to DiffDelete')
  has_highlight('MiniDepsTitleSame', 'links to DiffText')
  has_highlight('MiniDepsTitleUpdate', 'links to DiffAdd')
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniDeps.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniDeps.config.' .. field), value) end

  expect_config('job.n_threads', vim.NIL)
  expect_config('job.timeout', 30000)

  expect_config('path.package', child.fn.stdpath('data') .. '/site')
  expect_config('path.snapshot', child.fn.stdpath('config') .. '/mini-deps-snap')
  expect_config('path.log', child.fn.stdpath('state') .. '/mini-deps.log')

  expect_config('silent', false)
end

T['setup()']['respects `config` argument'] = function()
  unload_module()
  load_module({ silent = true })
  eq(child.lua_get('MiniDeps.config.silent'), true)
end

T['setup()']['validates `config` argument'] = function()
  unload_module()

  local expect_config_error = function(config, name, target_type)
    expect.error(load_module, vim.pesc(name) .. '.*' .. vim.pesc(target_type), config)
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ job = 'a' }, 'job', 'table')
  expect_config_error({ job = { n_threads = 'a' } }, 'job.n_threads', 'number')
  expect_config_error({ job = { timeout = 'a' } }, 'job.timeout', 'number')

  expect_config_error({ path = 'a' }, 'path', 'table')
  expect_config_error({ path = { package = 1 } }, 'path.package', 'string')
  expect_config_error({ path = { snapshot = 1 } }, 'path.snapshot', 'string')
  expect_config_error({ path = { log = 1 } }, 'path.log', 'string')

  expect_config_error({ silent = 'a' }, 'silent', 'boolean')
end

T['setup()']['ensures colors'] = function()
  child.cmd('colorscheme default')
  expect.match(child.cmd_capture('hi MiniDepsHint'), 'links to DiagnosticHint')
end

T['setup()']["prepends 'packpath' with package path"] = function()
  mock_test_package(test_dir_absolute)
  eq(vim.startswith(child.o.packpath, test_dir_absolute), true)
end

T['setup()']['clears session'] = function()
  load_module({ path = { package = test_dir_absolute } })
  add('plugin_1')
  eq(#get_session(), 1)

  load_module({ path = { package = test_dir_absolute } })
  eq(#get_session(), 0)
end

T['add()'] = new_set({ hooks = { pre_case = mock_test_package } })

T['add()']['works for present plugins'] = new_set({ parametrize = { { 'plugin_1' }, { { name = 'plugin_1' } } } }, {
  test = function(spec)
    local ref_path = test_opt_dir .. '/plugin_1'
    eq(is_in_rtp(ref_path), false)
    eq(get_session(), {})

    add(spec)

    eq(is_in_rtp(ref_path), true)
    eq(is_in_rtp(ref_path .. '/after'), true)
    eq(get_session(), { { name = 'plugin_1', path = ref_path, hooks = {}, depends = {} } })

    -- No CLI process should be run as plugin is already present
    eq(get_spawn_log(), {})

    -- Should load 'plugin/', 'after/plugin/', etc.
    eq(child.lua_get('type(_G.plugin_log)'), 'table')
  end,
})

T['add()']['infers name from source'] = new_set({
  parametrize = {
    { 'us-er1/plu-gin_0.nvim' },
    { 'https://github.com/us-er1/plu-gin_0.nvim' },
    { { source = 'us-er1/plu-gin_0.nvim' } },
    { { source = 'https://github.com/us-er1/plu-gin_0.nvim' } },
  },
}, {
  test = function(spec)
    local ref_path = test_opt_dir .. '/plu-gin_0.nvim'
    local ref_source = 'https://github.com/us-er1/plu-gin_0.nvim'
    add(spec)
    eq(is_in_rtp(ref_path), true)
    eq(get_session(), { { source = ref_source, name = 'plu-gin_0.nvim', path = ref_path, hooks = {}, depends = {} } })
  end,
})

T['add()']['uses only valid characters when infers source'] = function()
  add('git@github.com:user/plugin_1')
  local ref_path = test_opt_dir .. '/plugin_1'
  eq(
    get_session(),
    { { source = 'git@github.com:user/plugin_1', name = 'plugin_1', path = ref_path, hooks = {}, depends = {} } }
  )
end

T['add()']["properly sources 'plugin/' and 'after/plugin/'"] = function()
  add({ name = 'plugin_1', depends = { 'plugin_2' } })
  --stylua: ignore
  local ref_plugin_log = {
          'plugin/plug_2.lua',
          'plugin/plug_1.vim',       'plugin/plug_1.lua',       'plugin/subdir/plug_1_sub.lua',
    'after/plugin/plug_2.lua',
    'after/plugin/plug_1.lua', 'after/plugin/plug_1.vim', 'after/plugin/subdir/plug_1_sub.lua',
  }
  eq(child.lua_get('_G.plugin_log'), ref_plugin_log)
end

T['add()']["does not source 'after/plugin/' when not needed"] = function()
  -- During startup
  local setup_cmd =
    string.format("lua require('mini.deps').setup({ path = { package = %s } })", vim.inspect(test_dir_absolute))
  child.restart({ '-u', 'NONE', '--cmd', 'set rtp+=.', '--cmd', setup_cmd, '--cmd', "lua MiniDeps.add('plugin_1')" })

  --stylua: ignore
  eq(child.lua_get('_G.plugin_log'), {
    -- 'plugin/' directory gets sourced both as part of startup and `:packadd`
          'plugin/plug_1.vim',       'plugin/plug_1.lua',       'plugin/subdir/plug_1_sub.lua',
          'plugin/plug_1.vim',       'plugin/plug_1.lua',       'plugin/subdir/plug_1_sub.lua',
    -- But sourcing 'after/plugin/' in 'mini.deps' should not duplicate startup
    'after/plugin/plug_1.vim', 'after/plugin/plug_1.lua', 'after/plugin/subdir/plug_1_sub.lua',
  })

  -- When 'loadplugins = false'
  child.restart({ '-u', 'NONE', '--cmd', 'set rtp+=.', '--cmd', setup_cmd })
  child.o.loadplugins = false
  add('plugin_1')

  -- - `:packadd` does not recognize 'loadplugins' and thus sources them
  --   But 'after/plugin/' should not be sourced
  eq(child.lua_get('_G.plugin_log'), { 'plugin/plug_1.vim', 'plugin/plug_1.lua', 'plugin/subdir/plug_1_sub.lua' })
end

T['add()']['can update session data'] = function()
  add('plugin_1')
  add('plugin_2')
  eq(get_session(), {
    { path = test_opt_dir .. '/plugin_1', name = 'plugin_1', depends = {}, hooks = {} },
    { path = test_opt_dir .. '/plugin_2', name = 'plugin_2', depends = {}, hooks = {} },
  })

  add({ source = 'my_source', name = 'plugin_1' })
  add({ name = 'plugin_2', depends = { 'plugin_3' } })
  eq(get_session(), {
    { path = test_opt_dir .. '/plugin_1', name = 'plugin_1', source = 'my_source', depends = {}, hooks = {} },
    { path = test_opt_dir .. '/plugin_2', name = 'plugin_2', depends = { 'plugin_3' }, hooks = {} },
    { path = test_opt_dir .. '/plugin_3', name = 'plugin_3', depends = {}, hooks = {} },
  })

  child.lua([[
    MiniDeps.add({ name = 'plugin_3', hooks = { post_checkout = function() return 'Hello' end } })
    _G.hello = MiniDeps.get_session()[3].hooks.post_checkout()
  ]])
  eq(child.lua_get('_G.hello'), 'Hello')
end

T['add()']['respects plugins from "start" directory'] = function()
  local start_dir = test_dir_absolute .. '/pack/deps/start'
  mock_plugin(start_dir .. '/plug')
  MiniTest.finally(function() child.fn.delete(start_dir, 'rf') end)
  mock_test_package(test_dir_absolute)

  add('user/plug')
  eq(get_session(), {
    { path = start_dir .. '/plug', name = 'plug', source = 'https://github.com/user/plug', hooks = {}, depends = {} },
  })

  -- No CLI process should be run as plugin is already present
  eq(get_spawn_log(), {})
end

T['add()']['allows nested dependencies'] = function()
  add({
    name = 'plugin_1',
    depends = {
      { source = 'user/plugin_2', depends = {
        { name = 'plugin_3', checkout = 'hello' },
      } },
    },
  })
  eq(get_session(), {
    { path = test_opt_dir .. '/plugin_3', name = 'plugin_3', checkout = 'hello', depends = {}, hooks = {} },
    {
      path = test_opt_dir .. '/plugin_2',
      name = 'plugin_2',
      source = 'https://github.com/user/plugin_2',
      depends = { { checkout = 'hello', name = 'plugin_3' } },
      hooks = {},
    },
    {
      path = test_opt_dir .. '/plugin_1',
      name = 'plugin_1',
      depends = {
        { source = 'user/plugin_2', depends = {
          { checkout = 'hello', name = 'plugin_3' },
        } },
      },
      hooks = {},
    },
  })
end

T['add()']['does not error on cyclic dependencies'] = function()
  add({ name = 'plugin_1', depends = { 'plugin_1' } })
  add({ source = 'user/plugin_2', depends = { 'plugin_2' } })
  add({ source = 'user/plugin_3', depends = { 'new_user/plugin_3' } })
  eq(get_session(), {
    { path = test_opt_dir .. '/plugin_1', name = 'plugin_1', depends = { 'plugin_1' }, hooks = {} },
    {
      path = test_opt_dir .. '/plugin_2',
      name = 'plugin_2',
      source = 'https://github.com/user/plugin_2',
      depends = { 'plugin_2' },
      hooks = {},
    },
    {
      path = test_opt_dir .. '/plugin_3',
      name = 'plugin_3',
      source = 'https://github.com/user/plugin_3',
      depends = { 'new_user/plugin_3' },
      hooks = {},
    },
  })
end

T['add()']['validates specification'] = function()
  local validate = function(spec, err_pattern)
    expect.error(function() add(spec) end, err_pattern)
  end

  validate('', '`name`.*should not be empty')
  validate(1, 'table')
  validate({}, '`source` or `name`')
  validate({ source = 1 }, '`source` or `name`')
  validate({ source = 1, name = 'plugin_1' }, '`source`.*string')
  validate({ name = 1, source = 'user/plugin_1' }, '`name`.*string')
  validate({ name = 'user/plugin_1' }, '`name`.*not contain "/"')
  validate({ name = '' }, '`name`.*not be empty')
  validate({ checkout = 1, name = 'plugin_1' }, '`checkout`.*string')
  validate({ monitor = 1, name = 'plugin_1' }, '`monitor`.*string')
  validate({ hooks = 1, name = 'plugin_1' }, '`hooks`.*table')
  validate({ hooks = { pre_install = '' }, name = 'plugin_1' }, '`hooks%.pre_install`.*callable')
  validate({ hooks = { post_install = '' }, name = 'plugin_1' }, '`hooks%.post_install`.*callable')
  validate({ hooks = { pre_checkout = '' }, name = 'plugin_1' }, '`hooks%.pre_checkout`.*callable')
  validate({ hooks = { post_checkout = '' }, name = 'plugin_1' }, '`hooks%.post_checkout`.*callable')
  validate({ depends = 1, name = 'plugin_1' }, '`depends`.*array')
  validate({ depends = { name = 'plugin_2' }, name = 'plugin_1' }, '`depends`.*array')

  -- Should also validate inside dependencies
  validate({ depends = { {} }, name = 'plugin_1' }, '`source` or `name`')
  validate({ depends = { { name = 'plugin_2', depends = { {} } } }, name = 'plugin_1' }, '`source` or `name`')
end

T['add()']['validates `opts`'] = function()
  expect.error(function() add('plugin_1', 'a') end, '`opts`.*table')
  expect.error(function() add('plugin_1', { checkout = 'branch' }) end, '`add%(%)`.*only single spec')
end

T['add()']['respects `opts.bang`'] = function()
  add('plugin_1', { bang = true })
  eq(child.lua_get('_G.plugin_log'), vim.NIL)
end

T['add()']['does not modify input'] = function()
  child.lua([[
    _G.spec = {
      name = 'plugin_1',
      hooks = { post_update = function() end },
      depends = { 'plugin_2' },
    }
    _G.spec_ref = vim.deepcopy(_G.spec)
    MiniDeps.add(_G.spec)
  ]])
  eq(child.lua_get('#MiniDeps.get_session()'), 2)
  eq(child.lua_get('vim.deep_equal(_G.spec, _G.spec_ref)'), true)
end

T['add()']['Install'] = new_set({
  hooks = {
    pre_case = function()
      mock_test_package()

      -- Mock `vim.fn.isdirectory` to always say that there is a directory to
      -- simulate side-effect of `git clone`
      child.lua('vim.fn.isdirectory = function() return 1 end')
    end,
  },
})

T['add()']['Install']['works'] = function()
  mock_bad_env_vars()
  local ref_environ = child.fn.environ()

  child.lua([[
    _G.stdio_queue = {
      { out = 'git version 2.43.0'}, -- Check Git executable
      {},                            -- Clone
      { out = 'sha0head' },          -- Get `HEAD`
      { out = 'origin/main' },       -- Get default branch
      { out = 'origin/main' },       -- Check if `main` is origin branch
      { out = 'sha0head' },          -- Get commit of `origin/main`
      {},                            -- Stash changes
      {},                            -- Checkout changes
    }

    -- Mock non-trivial cloning duration
    _G.process_mock_data = { { duration = 5 } }
  ]])
  add('user/new_plugin')

  -- Should result into a proper sequence of CLI runs
  --stylua: ignore
  local ref_git_spawn_log = {
    { args = { 'version' }, cwd = child.fn.getcwd() },
    clone_args('https://github.com/user/new_plugin', test_opt_dir .. '/new_plugin'),
    {
      args = { 'rev-list', '-1', 'HEAD' },
      cwd = test_opt_dir .. '/new_plugin',
    },
    { 'rev-parse', '--abbrev-ref', 'origin/HEAD' },
    { 'branch', '--list', '--all', '--format=%(refname:short)', 'origin/main' },
    { 'rev-list', '-1', 'origin/main' },

    -- NOTE: Does not actually checkout because current commit is mocked the
    -- same as target
  }
  validate_git_spawn_log(ref_git_spawn_log)

  -- All processes and streams should be properly closed
  --stylua: ignore
  eq(
    get_process_log(),
    {
      'Stream out for process 1 was closed.', 'Stream err for process 1 was closed.', 'Process 1 was closed.',
      'Stream out for process 2 was closed.', 'Stream err for process 2 was closed.', 'Process 2 was closed.',
      'Stream out for process 3 was closed.', 'Stream err for process 3 was closed.', 'Process 3 was closed.',
      'Stream out for process 4 was closed.', 'Stream err for process 4 was closed.', 'Process 4 was closed.',
      'Stream out for process 5 was closed.', 'Stream err for process 5 was closed.', 'Process 5 was closed.',
      'Stream out for process 6 was closed.', 'Stream err for process 6 was closed.', 'Process 6 was closed.',
    }
  )

  -- Should produce notifications
  local ref_notify_log = {
    { '(mini.deps) Installing `new_plugin`', 'INFO' },
    { '(mini.deps) (1/1) Installed `new_plugin`', 'INFO' },
  }
  validate_notifications(ref_notify_log)

  -- Should not affect any environment variables
  eq(child.fn.environ(), ref_environ)
end

T['add()']['Install']['checks for executable Git'] = function()
  child.lua([[
    _G.stdio_queue = { { err = 'No Git'} }
    _G.process_mock_data = { { exit_code = 1 } }
  ]])
  expect.error(function() add('user/new_plugin') end, 'Could not find executable `git` CLI tool')
end

T['add()']['Install']['reacts to early Git version'] = function()
  child.lua([[
    _G.stdio_queue = {
      { out = 'git version 2.35.10'}, -- Check Git executable
      {},                             -- Clone
      { out = 'sha0head' },           -- Get `HEAD`
      { out = 'origin/main' },        -- Get default branch
      { out = 'origin/main' },        -- Check if `main` is origin branch
      { out = 'sha0head' },           -- Get commit of `origin/main`
      {},                             -- Stash changes
      {},                             -- Checkout changes
    }
  ]])
  add('user/new_plugin')

  -- Should result into a proper sequence of CLI runs
  --stylua: ignore
  local ref_git_spawn_log = {
    { args = { 'version' }, cwd = child.fn.getcwd() },
    {
      'clone', '--quiet', '--filter=blob:none', '--recurse-submodules', '--origin', 'origin',
      'https://github.com/user/new_plugin', test_opt_dir .. '/new_plugin',
    },
    {
      args = { 'rev-list', '-1', 'HEAD' },
      cwd = test_opt_dir .. '/new_plugin',
    },
    { 'rev-parse', '--abbrev-ref', 'origin/HEAD' },
    { 'branch', '--list', '--all', '--format=%(refname:short)', 'origin/main' },
    { 'rev-list', '-1', 'origin/main' },
  }
  validate_git_spawn_log(ref_git_spawn_log)
end

T['add()']['Install']['checks out non-default target'] = function()
  child.lua([[
    _G.stdio_queue = {
      { out = 'git version 2.43.0'}, -- Check Git executable
      {},                            -- Clone
      { out = 'sha0head' },          -- Get `HEAD`
      { out = 'origin/main' },       -- Get default branch
      { out = 'origin/hello' },      -- Check if `hello` is origin branch
      { out = 'new0hello' },         -- Get commit of `hello`
      {},                            -- Stash changes
      {},                            -- Checkout changes
    }

    -- Mock non-trivial cloning duration
    _G.process_mock_data = { { duration = 5 } }
  ]])
  add({ source = 'user/new_plugin', checkout = 'hello' })

  -- Should result into a proper sequence of CLI runs
  --stylua: ignore
  local ref_git_spawn_log = {
    { args = { 'version' }, cwd = child.fn.getcwd() },
    clone_args('https://github.com/user/new_plugin', test_opt_dir .. '/new_plugin'),
    {
      args = { 'rev-list', '-1', 'HEAD' },
      cwd = test_opt_dir .. '/new_plugin',
    },
    -- NOTE: Default branch is still checked because `monitor` is `nil`
    { 'rev-parse', '--abbrev-ref', 'origin/HEAD' },
    { 'branch', '--list', '--all', '--format=%(refname:short)', 'origin/hello' },
    { 'rev-list', '-1', 'origin/hello' },
    { 'stash', '--quiet', '--message', '(mini.deps) 2024-01-02 03:04:05 Stash before checkout' },
    { 'checkout', '--quiet', 'new0hello' },
  }
  validate_git_spawn_log(ref_git_spawn_log)

  -- Should produce notifications
  local ref_notify_log = {
    { '(mini.deps) Installing `new_plugin`', 'INFO' },
    { '(mini.deps) (1/1) Installed `new_plugin`', 'INFO' },
    { '(mini.deps) (1/1) Checked out `hello` in `new_plugin`', 'INFO' },
  }
  validate_notifications(ref_notify_log)
end

T['add()']['Install']['can checkout to a not branch'] = function()
  child.lua([[
    _G.stdio_queue = {
      { out = 'git version 2.43.0'}, -- Check Git executable
      {},                            -- Clone
      { out = 'sha0head' },          -- Get `HEAD`
      { out = 'origin/main' },       -- Get default branch
      { out = '' },                  -- Check if `stable_tag` is origin branch (it is not)
      { out = 'new0hello' },         -- Get commit of `stable_tag`
      {},                            -- Stash changes
      {},                            -- Checkout changes
    }
  ]])
  add({ source = 'user/new_plugin', checkout = 'stable_tag' })

  -- Should result into a proper sequence of CLI runs
  --stylua: ignore
  local ref_git_spawn_log = {
    { args = { 'version' }, cwd = child.fn.getcwd() },
    clone_args('https://github.com/user/new_plugin', test_opt_dir .. '/new_plugin'),
    {
      args = { 'rev-list', '-1', 'HEAD' },
      cwd = test_opt_dir .. '/new_plugin',
    },
    -- NOTE: Default branch is still checked because `monitor` is `nil`
    { 'rev-parse', '--abbrev-ref', 'origin/HEAD' },
    { 'branch', '--list', '--all', '--format=%(refname:short)', 'origin/stable_tag' },
    -- Get commit of specifically 'stable_tag' and not 'origin/stable_tag'
    { 'rev-list', '-1', 'stable_tag' },
    { 'stash', '--quiet', '--message', '(mini.deps) 2024-01-02 03:04:05 Stash before checkout' },
    { 'checkout', '--quiet', 'new0hello' },
  }
  validate_git_spawn_log(ref_git_spawn_log)

  -- Should produce notifications
  local ref_notify_log = {
    { '(mini.deps) Installing `new_plugin`', 'INFO' },
    { '(mini.deps) (1/1) Installed `new_plugin`', 'INFO' },
    { '(mini.deps) (1/1) Checked out `stable_tag` in `new_plugin`', 'INFO' },
  }
  validate_notifications(ref_notify_log)
end

T['add()']['Install']['installs dependencies in parallel'] = function()
  child.lua([[
    _G.stdio_queue = {
      { out = 'git version 2.43.0'}, -- Check Git executable
      {},                            -- Clone dep_plugin_2
      {},                            -- Clone dep_plugin_1
      {},                            -- Clone new_plugin
      { out = 'sha2head' },          -- Get `HEAD` in dep_plugin_2
      { out = 'sha1head' },          -- Get `HEAD` in dep_plugin_1
      { out = 'sha0head' },          -- Get `HEAD` in new_plugin
      { out = 'origin/trunk' },      -- Get default branch in dep_plugin_2
      { out = 'origin/master' },     -- Get default branch in dep_plugin_1
      { out = 'origin/main' },       -- Get default branch in new_plugin
      { out = 'origin/trunk' },      -- Check if `trunk`  is origin branch in dep_plugin_2
      { out = 'origin/master' },     -- Check if `master` is origin branch in dep_plugin_1
      { out = 'origin/main' },       -- Check if `main`   is origin branch in new_plugin
      { out = 'sha2head' },          -- Get commit of `trunk`  in dep_plugin_2
      { out = 'new1head' },          -- Get commit of `master` in dep_plugin_1
      { out = 'sha0head' },          -- Get commit of `main`   in new_plugin
      {},                            -- Stash changes in dep_plugin_1
      {},                            -- Checkout changes in dep_plugin_1
    }

    -- Mock non-trivial cloning duration
    _G.process_mock_data = { [2] = { duration = 50 }, [3] = { duration = 30 }, [4] = { duration = 40 } }
  ]])
  local start_time = child.loop.hrtime()
  add({
    source = 'user/new_plugin',
    depends = { { source = 'user/dep_plugin_1', checkout = 'master', depends = { 'user/dep_plugin_2' } } },
  })
  local duration = 0.000001 * (child.loop.hrtime() - start_time)
  eq(50 <= duration and duration < 120, true)

  -- Should result into a proper sequence of CLI runs
  local cwd_new_plugin, cwd_dep_plugin_1, cwd_dep_plugin_2 =
    test_opt_dir .. '/new_plugin', test_opt_dir .. '/dep_plugin_1', test_opt_dir .. '/dep_plugin_2'

  --stylua: ignore
  local ref_git_spawn_log = {
    { args = { 'version' }, cwd = child.fn.getcwd() },

    clone_args('https://github.com/user/dep_plugin_2', cwd_dep_plugin_2),
    clone_args('https://github.com/user/dep_plugin_1', cwd_dep_plugin_1),
    clone_args('https://github.com/user/new_plugin', cwd_new_plugin),

    { args = { 'rev-list', '-1', 'HEAD' }, cwd = cwd_dep_plugin_2 },
    { args = { 'rev-list', '-1', 'HEAD' }, cwd = cwd_dep_plugin_1 },
    { args = { 'rev-list', '-1', 'HEAD' }, cwd = cwd_new_plugin },

    -- NOTE: Default branch is still checked because `monitor` is `nil`
    { args = { 'rev-parse', '--abbrev-ref', 'origin/HEAD' }, cwd = cwd_dep_plugin_2 },
    { args = { 'rev-parse', '--abbrev-ref', 'origin/HEAD' }, cwd = cwd_dep_plugin_1 },
    { args = { 'rev-parse', '--abbrev-ref', 'origin/HEAD' }, cwd = cwd_new_plugin },

    { args = { 'branch', '--list', '--all', '--format=%(refname:short)', 'origin/trunk' }, cwd = cwd_dep_plugin_2 },
    { args = { 'branch', '--list', '--all', '--format=%(refname:short)', 'origin/master' }, cwd = cwd_dep_plugin_1 },
    { args = { 'branch', '--list', '--all', '--format=%(refname:short)', 'origin/main' }, cwd = cwd_new_plugin },

    { args = { 'rev-list', '-1', 'origin/trunk' }, cwd = cwd_dep_plugin_2 },
    { args = { 'rev-list', '-1', 'origin/master' }, cwd = cwd_dep_plugin_1 },
    { args = { 'rev-list', '-1', 'origin/main' }, cwd = cwd_new_plugin },

    { args = { 'stash', '--quiet', '--message', '(mini.deps) 2024-01-02 03:04:05 Stash before checkout' }, cwd = cwd_dep_plugin_1 },

    { args = { 'checkout', '--quiet', 'new1head' }, cwd = cwd_dep_plugin_1 },
  }
  validate_git_spawn_log(ref_git_spawn_log)

  -- Should produce notifications
  local ref_notify_log = {
    { '(mini.deps) Installing `new_plugin`', 'INFO' },
    -- NOTE: Cloning exit notifications are done immediately after job is done,
    -- not in a session order
    { '(mini.deps) (1/3) Installed `dep_plugin_1`', 'INFO' },
    { '(mini.deps) (2/3) Installed `new_plugin`', 'INFO' },
    { '(mini.deps) (3/3) Installed `dep_plugin_2`', 'INFO' },
    { '(mini.deps) (1/1) Checked out `master` in `dep_plugin_1`', 'INFO' },
  }
  validate_notifications(ref_notify_log)
end

T['add()']['Install']['can handle both present and not present plugins'] = new_set({
  parametrize = {
    -- Present target, not present dependency
    { { source = 'user/plugin_1', depends = { 'user/new_plugin' } } },
    -- Present dependency, not present target
    { { source = 'user/new_plugin', depends = { 'user/plugin_1' } } },
  },
}, {
  test = function()
    local validate = function(spec, clone_name)
      -- Make clean mock
      mock_spawn()

      child.lua([[
        _G.stdio_queue = {
          { out = 'git version 2.43.0'}, -- Check Git executable
          {},                            -- Clone
          { out = 'sha0head' },          -- Get `HEAD`
          { out = 'origin/main' },       -- Get default branch
          { out = 'origin/main' },       -- Check if `main` is origin branch
          { out = 'sha0head' },          -- Get commit of `origin/main`
          {},                            -- Stash changes
          {},                            -- Checkout changes
        }
      ]])
      add(spec)

      -- Should result into a proper sequence of CLI runs
      --stylua: ignore
      local ref_git_spawn_log = {
        { args = { 'version' }, cwd = child.fn.getcwd() },
        clone_args('https://github.com/user/new_plugin', test_opt_dir .. '/new_plugin'),
        {
          args = { 'rev-list', '-1', 'HEAD' },
          cwd = test_opt_dir .. '/new_plugin',
        },
        { 'rev-parse', '--abbrev-ref', 'origin/HEAD' },
        { 'branch', '--list', '--all', '--format=%(refname:short)', 'origin/main' },
        { 'rev-list', '-1', 'origin/main' },
      }
      validate_git_spawn_log(ref_git_spawn_log)
    end
  end,
})

T['add()']['Install']['properly executes `*_install` hooks'] = function()
  child.lua([[
    _G.stdio_queue = {
      { out = 'git version 2.43.0'}, -- Check Git executable
      {},                            -- Clone dep_plugin
      {},                            -- Clone new_plugin
      { out = 'sha1head' },          -- Get `HEAD` in dep_plugin
      { out = 'sha0head' },          -- Get `HEAD` in new_plugin
      { out = 'origin/master' },     -- Get default branch in dep_plugin
      { out = 'origin/main' },       -- Get default branch in new_plugin
      { out = 'origin/master' },     -- Check if `master` is origin branch in dep_plugin
      { out = 'origin/main' },       -- Check if `main`   is origin branch in new_plugin
      { out = 'new1head' },          -- Get commit of `master` in dep_plugin
      { out = 'sha0head' },          -- Get commit of `main`   in new_plugin
      {},                            -- Stash changes in dep_plugin
      {},                            -- Checkout changes in dep_plugin
    }

    -- Mock non-trivial cloning duration to simulate out of order finish
    _G.process_mock_data = { [2] = { duration = 10 }, [3] = { duration = 5 } }

    -- Add plugin with dependency and hooks
    _G.args = {}
    local make_hook = function(msg)
      return function(...)
        table.insert(_G.args, { msg, { ... } })
        vim.notify(msg)
      end
    end

    local dep_spec = {
      source = 'user/dep_plugin',
      hooks = {
        pre_install = make_hook('Dependency pre_install'),
        post_install = make_hook('Dependency post_install'),
      },
    }
    local spec = {
      source = 'user/new_plugin',
      depends = { dep_spec },
      hooks = {
        pre_install = make_hook('Target pre_install'),
        post_install = make_hook('Target post_install'),
      },
    }

    MiniDeps.add(spec)
  ]])

  -- Should be called with proper arguments
  local cwd_new_plugin, cwd_dep_plugin = test_opt_dir .. '/new_plugin', test_opt_dir .. '/dep_plugin'
  local ref_args = {
    {
      'Dependency pre_install',
      { { path = cwd_dep_plugin, source = 'https://github.com/user/dep_plugin', name = 'dep_plugin' } },
    },
    {
      'Target pre_install',
      { { path = cwd_new_plugin, source = 'https://github.com/user/new_plugin', name = 'new_plugin' } },
    },
    {
      'Dependency post_install',
      { { path = cwd_dep_plugin, source = 'https://github.com/user/dep_plugin', name = 'dep_plugin' } },
    },
    {
      'Target post_install',
      { { path = cwd_new_plugin, source = 'https://github.com/user/new_plugin', name = 'new_plugin' } },
    },
  }
  eq(child.lua_get('_G.args'), ref_args)

  -- Should produce notifications
  local ref_notify_log = {
    -- Hooks are executed in a session order
    { 'Dependency pre_install' },
    { 'Target pre_install' },
    { '(mini.deps) Installing `new_plugin`', 'INFO' },
    -- Cloning exit notifications are done after job is finished
    { '(mini.deps) (1/2) Installed `new_plugin`', 'INFO' },
    { '(mini.deps) (2/2) Installed `dep_plugin`', 'INFO' },
    { '(mini.deps) (1/1) Checked out `master` in `dep_plugin`', 'INFO' },
    -- Hooks are executed in a session order
    { 'Dependency post_install' },
    { 'Target post_install' },
  }
  validate_notifications(ref_notify_log)
end

T['add()']['Install']['handles errors in hooks'] = function()
  child.lua([[_G.stdio_queue = { { out = 'git version 2.43.0'} } -- Check Git executable]])
  child.lua([[
    MiniDeps.add({
      source = 'user/new_plugin',
      hooks = { pre_install = function() error('Error in `pre_install`') end },
    })
  ]])
  --stylua: ignore
  validate_notifications({
    { '(mini.deps) Installing `new_plugin`', 'INFO' },
    { '(mini.deps) Error executing pre_install hook in `new_plugin`:\n[string "<nvim>"]:3: Error in `pre_install`', 'ERROR' },
    { '(mini.deps) (1/1) Installed `new_plugin`', 'INFO' },
  })
end

T['add()']['Install']['generates help tags'] = function()
  -- Set up clear temporary directory
  local cur_package_path = test_dir_absolute .. '/temp'
  local cur_opt_dir = cur_package_path .. '/pack/deps/opt'

  child.lua('_G.temp_package_path = ' .. vim.inspect(cur_package_path))
  MiniTest.finally(function() child.lua('vim.fn.delete(_G.temp_package_path, "rf")') end)
  child.lua('MiniDeps.setup({ path = { package = _G.temp_package_path } })')

  child.lua([[
    _G.stdio_queue = {
      { out = 'git version 2.43.0'}, -- Check Git executable
      {},                            -- Clone dep_plugin_2
      {},                            -- Clone dep_plugin_1
      {},                            -- Clone new_plugin
      { out = 'sha2head' },          -- Get `HEAD` in dep_plugin_2
      { out = 'sha1head' },          -- Get `HEAD` in dep_plugin_1
      { out = 'sha0head' },          -- Get `HEAD` in new_plugin
      { out = 'origin/trunk' },      -- Get default branch in dep_plugin_2
      { out = 'origin/master' },     -- Get default branch in dep_plugin_1
      { out = 'origin/main' },       -- Get default branch in new_plugin
      { out = 'origin/trunk' },      -- Check if `trunk`  is origin branch in dep_plugin_2
      { out = 'origin/master' },     -- Check if `master` is origin branch in dep_plugin_1
      { out = 'origin/main' },       -- Check if `main`   is origin branch in new_plugin
      { out = 'new2head' },          -- Get commit of `trunk`  in dep_plugin_2
      { out = 'new1head' },          -- Get commit of `master` in dep_plugin_1
      { out = 'sha0head' },          -- Get commit of `main`   in new_plugin
      {},                            -- Stash changes in dep_plugin_1
      {},                            -- Checkout changes in dep_plugin_1
    }

    -- Mock action cloning side-effects which creates '/doc' directories
    local opt_dir = _G.temp_package_path .. '/pack/deps/opt'
    _G.process_mock_data = {
      -- 'dep_plugin_2' has '/doc' with already present conflicting '/tag'
      [2] = {
        action = function()
          vim.fn.mkdir(opt_dir .. '/dep_plugin_2/doc', 'p')
          vim.fn.writefile({ 'old_dep_2_tag	dep_2.txt	/*old_dep_2_tag*' }, opt_dir .. '/dep_plugin_2/doc/dep_2.txt')
          vim.fn.writefile({ '*depstest_dep_2_tag*', 'Help for dep_2.' }, opt_dir .. '/dep_plugin_2/doc/dep_2.txt')
        end
      },

      -- 'dep_plugin_1' has '/doc' with help files and has explicit checkout
      [3] = {
        action = function()
          vim.fn.mkdir(opt_dir .. '/dep_plugin_1/doc', 'p')
          vim.fn.writefile({ '*depstest_dep_1_tag*', 'Help for dep_1.' }, opt_dir .. '/dep_plugin_1/doc/dep_1.txt')
        end
      },

      -- 'new_plugin' has '/doc' with help files and has no explicit checkout
      [4] = {
        action = function()
          vim.fn.mkdir(opt_dir .. '/new_plugin/doc', 'p')
          vim.fn.writefile({ '*depstest_new_tag*', 'Help for new.' }, opt_dir .. '/new_plugin/doc/new.txt')
        end
      },
    }
  ]])
  add({
    source = 'user/new_plugin',
    depends = { { source = 'user/dep_plugin_1', checkout = 'master', depends = { 'user/dep_plugin_2' } } },
  })

  local validate_tags = function(plugin_name, content)
    local lines = child.fn.readfile(cur_opt_dir .. '/' .. plugin_name .. '/doc/tags')
    eq(lines, content)
  end

  -- Already present conflicting `tag` file should be overridden
  validate_tags('dep_plugin_2', { 'depstest_dep_2_tag\tdep_2.txt\t/*depstest_dep_2_tag*' })

  -- With actual checkout
  validate_tags('dep_plugin_1', { 'depstest_dep_1_tag\tdep_1.txt\t/*depstest_dep_1_tag*' })

  -- Without actual checkout
  validate_tags('new_plugin', { 'depstest_new_tag\tnew.txt\t/*depstest_new_tag*' })

  -- Help tags are actually reachable
  local help_tags = child.fn.getcompletion('depstest_', 'help')
  table.sort(help_tags)
  eq(help_tags, { 'depstest_dep_1_tag', 'depstest_dep_2_tag', 'depstest_new_tag' })
end

T['add()']['Install']['handles process errors and warnings'] = function()
  child.lua([[
    _G.stdio_queue = {
      { out = 'git version 2.43.0'},                            -- Check Git executable
      { err = 'filtering not recognized by server, ignoring' }, -- Clone dep_plugin
      { err = 'Could not clone' },                              -- Clone new_plugin
      { out = 'sha2head' },                                     -- Get `HEAD` in dep_plugin
    }

    -- Mock non-zero exit code in getting dep_plugin's head
    _G.process_mock_data = { [3] = { exit_code = 1 }, [4] = { exit_code = 128 } }
  ]])

  add({ source = 'user/new_plugin', depends = { 'user/dep_plugin' } })

  -- Errors should be treated as follows:
  -- - If exit code is non-zero, it should error notify it with `stderr` output
  -- - If exit code is zero, then process did not error and `stderr` is warning
  --stylua: ignore
  local ref_git_spawn_log = {
    { args = { 'version' }, cwd = child.fn.getcwd() },
    clone_args('https://github.com/user/dep_plugin', test_opt_dir .. '/dep_plugin'),
    clone_args('https://github.com/user/new_plugin', test_opt_dir .. '/new_plugin'),
    {
      args = { 'rev-list', '-1', 'HEAD' },
      cwd = test_opt_dir .. '/dep_plugin',
    },
  }
  validate_git_spawn_log(ref_git_spawn_log)

  -- Should produce notifications
  local ref_notify_log = {
    { '(mini.deps) Installing `new_plugin`', 'INFO' },
    { '(mini.deps) (1/2) Installed `dep_plugin`', 'INFO' },
    {
      '(mini.deps) Warnings in `dep_plugin` during installing plugin\nfiltering not recognized by server, ignoring',
      'WARN',
    },
    { '(mini.deps) Error in `dep_plugin` during installing plugin\nERROR CODE 128', 'ERROR' },
    { '(mini.deps) Error in `new_plugin` during installing plugin\nERROR CODE 1\nCould not clone', 'ERROR' },
  }
  validate_notifications(ref_notify_log)
end

T['add()']['Install']['handles no `source` for absent plugin'] = function()
  child.lua([[_G.stdio_queue = { { out = 'git version 2.43.0'} } -- Check Git executable]])
  add({ name = 'new_plugin' })
  local ref_notify_log = {
    { '(mini.deps) Installing `new_plugin`', 'INFO' },
    {
      '(mini.deps) Error in `new_plugin` during installing plugin\nSPECIFICATION HAS NO `source` TO INSTALL PLUGIN.',
      'ERROR',
    },
  }
  validate_notifications(ref_notify_log)
end

T['add()']['Install']['respects `config.job.n_threads`'] = function()
  child.lua([[
    _G.stdio_queue = {
      { out = 'git version 2.43.0'}, -- Check Git executable
      {},                            -- Clone dep_plugin
      {},                            -- Clone new_plugin
      { out = 'sha2head' },          -- Get `HEAD` in dep_plugin
      { out = 'sha0head' },          -- Get `HEAD` in new_plugin
      { out = 'origin/trunk' },      -- Get default branch in dep_plugin
      { out = 'origin/main' },       -- Get default branch in new_plugin
      { out = 'origin/trunk' },      -- Check if `trunk`  is origin branch in dep_plugin
      { out = 'origin/main' },       -- Check if `main`   is origin branch in new_plugin
      { out = 'sha2head' },          -- Get commit of `trunk`  in dep_plugin
      { out = 'sha0head' },          -- Get commit of `main`   in new_plugin
    }

    -- Mock non-trivial cloning duration
    _G.process_mock_data = { [2] = { duration = 30 }, [3] = { duration = 30 } }
  ]])

  child.lua('MiniDeps.config.job.n_threads = 1')

  local start_time = child.loop.hrtime()
  add({ source = 'user/new_plugin', depends = { 'user/dep_plugin' } })
  local duration = 0.000001 * (child.loop.hrtime() - start_time)
  eq(40 <= duration, true)
end

T['add()']['Install']['works when no information about number of cores is available'] = function()
  child.lua([[
    _G.stdio_queue = {
      { out = 'git version 2.43.0'}, -- Check Git executable
      {},                            -- Clone
      { out = 'sha0head' },          -- Get `HEAD`
      { out = 'origin/main' },       -- Get default branch
      { out = 'origin/main' },       -- Check if `main` is origin branch
      { out = 'sha0head' },          -- Get commit of `origin/main`
      {},                            -- Stash changes
      {},                            -- Checkout changes
    }
  ]])
  child.lua('vim.loop.cpu_info = function() return nil end')
  expect.no_error(function() add('user/new_plugin') end)
end

T['add()']['Install']['respects `config.job.timeout`'] = function()
  child.lua('_G.duration = ' .. (10 * small_time))
  child.lua([[
    _G.stdio_queue = {
      { out = 'git version 2.43.0'}, -- Check Git executable
      {},                            -- Clone dep_plugin
      {},                            -- Clone new_plugin
      { out = 'sha2head' },          -- Get `HEAD` in dep_plugin
    }

    -- Mock long execution of some jobs
    _G.process_mock_data = { [2] = { duration = _G.duration }, [3] = { duration = 0 }, [4] = { duration = _G.duration } }
  ]])

  child.lua('MiniDeps.config.job.timeout = ' .. (5 * small_time))
  add({ source = 'user/new_plugin', depends = { 'user/dep_plugin' } })

  local ref_notify_log = {
    { '(mini.deps) Installing `new_plugin`', 'INFO' },
    { '(mini.deps) (1/2) Installed `new_plugin`', 'INFO' },
    { '(mini.deps) Error in `dep_plugin` during installing plugin\nERROR CODE 1\nPROCESS REACHED TIMEOUT.', 'ERROR' },
    { '(mini.deps) Error in `new_plugin` during installing plugin\nERROR CODE 1\nPROCESS REACHED TIMEOUT.', 'ERROR' },
  }
  validate_notifications(ref_notify_log)
end

T['add()']['Install']['respects `config.silent`'] = function()
  child.lua([[
    _G.stdio_queue = {
      { out = 'git version 2.43.0'}, -- Check Git executable
      {},                            -- Clone
      { out = 'sha0head' },          -- Get `HEAD`
      { out = 'origin/main' },       -- Get default branch
      { out = 'origin/hello' },      -- Check if `hello` is origin branch
      { out = 'new0hello' },         -- Get commit of `hello`
      {},                            -- Stash changes
      {},                            -- Checkout changes
    }
  ]])
  child.lua('MiniDeps.config.silent = true')
  add({ source = 'user/new_plugin', checkout = 'hello' })

  -- Should produce no notifications
  validate_notifications({})
end

T['add()']['Install']['does not affect newly added session data'] = function()
  child.lua([[_G.stdio_queue = { { out = 'git version 2.43.0'} } -- Check Git executable]])
  add('user/new_plugin')
  eq(get_session(), {
    {
      path = test_opt_dir .. '/new_plugin',
      name = 'new_plugin',
      source = 'https://github.com/user/new_plugin',
      depends = {},
      hooks = {},
    },
  })
end

T['update()'] = new_set({
  hooks = {
    pre_case = function() load_module({ path = { package = test_dir_absolute, log = test_log_path } }) end,
    post_case = function()
      child.fn.delete(test_log_path)
      for i = 1, 3 do
        child.fn.delete(string.format('%s/plugin_%d/doc/tags', test_opt_dir, i))
      end
    end,
  },
})

local update = forward_lua('MiniDeps.update')

T['update()']['works'] = function()
  child.set_size(40, 80)
  mock_bad_env_vars()
  local ref_environ = child.fn.environ()

  -- By default should update all plugins in session
  add('plugin_1')
  add({ source = 'https://new_source/plugin_2' })
  add('plugin_3')

  local plugin_2_log = table.concat({
    '< sha2head | 2024-01-02 01:01:01 +0200 | Neo McVim',
    '  Removed commit in plugin_2.',
    '> new2head | 2024-01-02 02:02:02 +0200 | Neo McVim',
    '  Added commit in plugin_2.',
  }, '\n')
  child.lua('_G.plugin_2_log = ' .. vim.inspect(plugin_2_log))

  child.lua([[
    _G.stdio_queue = {
      { out = 'git version 2.43.0'}, -- Check Git executable
      { out = 'https://github.com/user/plugin_1' }, -- Get source from `origin` in plugin_1
      { err = 'Some warning' },                     -- Set `origin` to source in plugin_2
      { err = 'Error computing origin' },           -- Get source from `origin` in plugin_3
      { out = 'sha1head' },          -- Get `HEAD` in plugin_1
      { out = 'sha2head' },          -- Get `HEAD` in plugin_2
      { out = 'origin/main' },       -- Get default branch in plugin_1
      { out = 'origin/master' },     -- Get default branch in plugin_2
      {},                            -- Fetch in plugin_1
      {},                            -- Fetch in plugin_2
      { out = 'origin/main' },       -- Check if `checkout` is origin branch in plugin_1
      { out = 'origin/master' },     -- Check if `checkout` is origin branch in plugin_2
      { out = 'sha1head' },          -- Get commit of `checkout` in plugin_1
      { out = 'new2head' },          -- Get commit of `checkout` in plugin_2
      { out = _G.plugin_2_log },     -- Get log of `checkout` changes in plugin_2
    }

    -- Mock non-trivial fetch duration
    _G.process_mock_data = { [4] = { exit_code = 1 }, [9] = { duration = 50 }, [10] = { duration = 40 } }
  ]])

  -- Update should be done in parallel
  local start_time = child.loop.hrtime()
  update()
  local duration = 0.000001 * (child.loop.hrtime() - start_time)
  eq(50 <= duration and duration < 90, true)

  -- Should result into a proper sequence of CLI runs
  local cwd_plugin_1, cwd_plugin_2, cwd_plugin_3 =
    test_opt_dir .. '/plugin_1', test_opt_dir .. '/plugin_2', test_opt_dir .. '/plugin_3'
  --stylua: ignore
  local ref_git_spawn_log = {
    { args = { 'version' }, cwd = child.fn.getcwd() },

    { args = { 'remote', 'get-url', 'origin' },                                cwd = cwd_plugin_1 },
    { args = { 'remote', 'set-url', 'origin', 'https://new_source/plugin_2' }, cwd = cwd_plugin_2 },
    { args = { 'remote', 'get-url', 'origin' },                                cwd = cwd_plugin_3 },

    { args = { 'rev-list', '-1', 'HEAD' }, cwd = cwd_plugin_1 },
    { args = { 'rev-list', '-1', 'HEAD' }, cwd = cwd_plugin_2 },

    { args = { 'rev-parse', '--abbrev-ref', 'origin/HEAD' }, cwd = cwd_plugin_1 },
    { args = { 'rev-parse', '--abbrev-ref', 'origin/HEAD' }, cwd = cwd_plugin_2 },

    { args = { 'fetch', '--quiet', '--tags', '--force', '--recurse-submodules=yes', 'origin' }, cwd = cwd_plugin_1 },
    { args = { 'fetch', '--quiet', '--tags', '--force', '--recurse-submodules=yes', 'origin' }, cwd = cwd_plugin_2 },

    { args = { 'branch', '--list', '--all', '--format=%(refname:short)', 'origin/main' },   cwd = cwd_plugin_1 },
    { args = { 'branch', '--list', '--all', '--format=%(refname:short)', 'origin/master' }, cwd = cwd_plugin_2 },

    { args = { 'rev-list', '-1', 'origin/main' },   cwd = cwd_plugin_1 },
    { args = { 'rev-list', '-1', 'origin/master' }, cwd = cwd_plugin_2 },

    { args = log_args('sha2head...new2head'), cwd = cwd_plugin_2 },
  }
  validate_git_spawn_log(ref_git_spawn_log)

  -- Should produce notifications
  local ref_notify_log = {
    { '(mini.deps) Downloading 2 updates', 'INFO' },
    { '(mini.deps) (1/2) Downloaded update for `plugin_2`', 'INFO' },
    { '(mini.deps) (2/2) Downloaded update for `plugin_1`', 'INFO' },
    { '(mini.deps) Warnings in `plugin_2` during update\nSome warning', 'WARN' },
    { '(mini.deps) Error in `plugin_3` during update\nERROR CODE 1\nError computing origin', 'ERROR' },
  }
  validate_notifications(ref_notify_log)

  -- Should show confirmation buffer. Plugin entries should be in order of
  -- "error", "has changes", "no changes".
  mock_hide_path(test_dir_absolute)
  child.expect_screenshot()
  validate_confirm_buf('confirm-update')

  -- Should not affect any environment variables
  eq(child.fn.environ(), ref_environ)
end

T['update()']['checks for executable Git'] = function()
  add('plugin_1')
  child.lua([[
    _G.stdio_queue = { { err = 'No Git'} }
    _G.process_mock_data = { { exit_code = 1 } }
  ]])
  expect.error(function() update() end, 'Could not find executable `git` CLI tool')
end

T['update()']['Confirm buffer'] = new_set({
  hooks = {
    pre_case = function()
      add('plugin_1')
      add('plugin_2')

      child.lua([[
        _G.plugin_1_log = '> new1head | 2024-01-02 01:01:01 +0200 | Neo McVim\n  Added commit in plugin_1.'
        _G.plugin_2_log = '> new2head | 2024-01-02 02:02:02 +0200 | Neo McVim\n  Added commit in plugin_2.'
        _G.stdio_queue = {
          { out = 'git version 2.43.0'}, -- Check Git executable
          { out = 'https://github.com/user/plugin_1' }, -- Get source from `origin` in plugin_1
          { out = 'https://github.com/user/plugin_2' }, -- Get source from `origin` in plugin_2
          { out = 'sha1head' },          -- Get `HEAD` in plugin_1
          { out = 'sha2head' },          -- Get `HEAD` in plugin_2
          { out = 'origin/main' },       -- Get default branch in plugin_1
          { out = 'origin/master' },     -- Get default branch in plugin_2
          {},                            -- Fetch in plugin_1
          {},                            -- Fetch in plugin_2
          { out = 'origin/main' },       -- Check if `checkout` is origin branch in plugin_1
          { out = 'origin/master' },     -- Check if `checkout` is origin branch in plugin_2
          { out = 'new1head' },          -- Get commit of `checkout` in plugin_1
          { out = 'new2head' },          -- Get commit of `checkout` in plugin_2
          { out = _G.plugin_1_log },     -- Get log of `checkout` changes in plugin_1
          { out = _G.plugin_2_log },     -- Get log of `checkout` changes in plugin_2
        }
      ]])

      -- Confirmation buffer should be configurable in `FileType` event with
      -- window being current (so as to `vim.wo` can work)
      child.cmd('au FileType minideps-confirm lua _G.minideps_ft_win_id = vim.api.nvim_get_current_win()')

      update()
      eq(#get_spawn_log(), 15)
      eq(#get_notify_log(), 3)
      validate_confirm_buf('confirm-update')
      eq(child.lua_get('_G.minideps_ft_win_id') == child.api.nvim_get_current_win(), true)

      child.lua([[
        _G.prev_update = MiniDeps.update
        MiniDeps.update = function(...)
          _G.update_args = { ... }
          prev_update(...)
        end
      ]])
    end,
  },
})

T['update()']['Confirm buffer']['can apply changes'] = function()
  mock_bad_env_vars()
  local ref_environ = child.fn.environ()

  -- Should run `update()` on buffer write with only valid plugin names
  -- Remove 'plugin_1' from being updated
  child.cmd('g/^+++ plugin_1/normal! dd/')
  child.cmd('write')

  -- Should update and close confirmation buffer
  eq(child.lua_get('_G.update_args'), { { 'plugin_2' }, { force = true, offline = true } })
  validate_not_confirm_buf()

  -- Should not affect any environment variables
  eq(child.fn.environ(), ref_environ)
end

T['update()']['Confirm buffer']['can cancel'] = function()
  child.cmd('close')
  eq(child.lua_get('_G.update_args'), vim.NIL)
  validate_not_confirm_buf()
end

T['update()']['Confirm buffer']['can open several'] = function()
  child.lua('_G.prev_update()')
  validate_confirm_buf('confirm-update')
end

T['update()']['can fold in confirm buffer'] = function()
  child.set_size(30, 80)

  -- Confirmation buffer should enable local folds
  child.o.foldenable = false
  child.o.foldmethod = 'indent'
  child.o.foldlevel = 0
  child.o.foldtext = '"  >> ".getline(v:foldstart)'

  -- Should be possible to automatically show folds on start
  child.cmd('au FileType minideps-confirm setlocal foldlevel=0')

  add('user/plugin_1')
  add('user/plugin_2')
  add('user/plugin_3')

  local plugin_2_log = table.concat({
    '< sha2head | 2024-01-02 01:01:01 +0200 | Neo McVim',
    '  Removed commit in plugin_2.',
    '> new2head | 2024-01-02 02:02:02 +0200 | Neo McVim',
    '  Added commit in plugin_2.',
  }, '\n')
  child.lua('_G.plugin_2_log = ' .. vim.inspect(plugin_2_log))

  child.lua([[
    _G.stdio_queue = {
      { out = 'git version 2.43.0'},    -- Check Git executable
      {},                               -- Set `origin` to source in plugin_1
      {},                               -- Set `origin` to source in plugin_2
      { err = 'Error setting origin' }, -- Set `origin` to source in plugin_3
      { out = 'sha1head' },             -- Get `HEAD` in plugin_1
      { out = 'sha2head' },             -- Get `HEAD` in plugin_2
      { out = 'origin/main' },          -- Get default branch in plugin_1
      { out = 'origin/master' },        -- Get default branch in plugin_2
      {},                               -- Fetch in plugin_1
      {},                               -- Fetch in plugin_2
      { out = 'origin/main' },          -- Check if `checkout` is origin branch in plugin_1
      { out = 'origin/master' },        -- Check if `checkout` is origin branch in plugin_2
      { out = 'sha1head' },             -- Get commit of `checkout` in plugin_1
      { out = 'new2head' },             -- Get commit of `checkout` in plugin_2
      { out = _G.plugin_2_log },        -- Get log of `checkout` changes in plugin_2
    }

    _G.process_mock_data = { [4] = { exit_code = 1 } }
  ]])

  update()
  mock_hide_path(test_dir_absolute)

  child.expect_screenshot()

  -- Should not preserve fold options in new buffer in same window
  child.cmd('enew')
  eq(child.wo.foldenable, false)
  eq(child.wo.foldmethod, 'indent')
  eq(child.wo.foldlevel, 0)

  -- Should not preserve fold options when quit
  child.cmd('quit')
  eq(child.wo.foldenable, false)
  eq(child.wo.foldmethod, 'indent')
  eq(child.wo.foldlevel, 0)
end

T['update()']['can highlight breaking changes'] = function()
  child.set_size(33, 80)

  add('plugin_1')

  local plugin_1_log = table.concat({
    '< sha2head | 2024-01-02 01:01:01 +0200 | Neo McVim',
    '  feat!: a breaking feature',
    '> new2head | 2024-01-02 02:02:02 +0200 | Neo McVim',
    '  fix(deps)!: a breaking fix',
    '> wow2head | 2024-01-02 03:03:03 +0200 | Neo McVim',
    '  fix: not a fix!: breaking change',
  }, '\n')
  child.lua('_G.plugin_1_log = ' .. vim.inspect(plugin_1_log))

  child.lua([[
    _G.stdio_queue = {
      { out = 'git version 2.43.0'}, -- Check Git executable
      { out = 'https://github.com/user/plugin_1' }, -- Get source from `origin` in plugin_1
      { out = 'sha1head' },          -- Get `HEAD` in plugin_1
      { out = 'origin/main' },       -- Get default branch in plugin_1
      {},                            -- Fetch in plugin_1
      { out = 'origin/main' },       -- Check if `checkout` is origin branch in plugin_1
      { out = 'wow1head' },          -- Get commit of `checkout` in plugin_1
      { out = _G.plugin_1_log },     -- Get log of `checkout` changes in plugin_1
    }
  ]])

  update()

  -- Should show confirmation buffer with highlighted breaking messages
  mock_hide_path(test_dir_absolute)
  child.expect_screenshot()
end

T['update()']['can work with non-default branches'] = function()
  child.set_size(32, 80)

  add({ source = 'user/plugin_1', checkout = 'hello', monitor = 'world' })
  child.lua([[
    _G.checkout_log = '> new1head | 2024-01-02 01:01:01 +0200 | Neo McVim\n  Added commit in checkout.'
    _G.monitor_log = '> new2head | 2024-01-02 02:02:02 +0200 | Neo McVim\n  Added commit in monitor.'
    _G.stdio_queue = {
      { out = 'git version 2.43.0'}, -- Check Git executable
      {},                            -- Set `origin` to source
      { out = 'sha1head' },          -- Get `HEAD`
      -- NOTE: Don't get default branch as both every target is explicit
      { out = 'origin/world' },      -- Check if `monitor` is origin branch
      { out = 'sha2head' },          -- Get commit of `monitor`
      {},                            -- Fetch
      { out = 'origin/hello' },      -- Check if `checkout` is origin branch (it is)
      { out = 'new1head' },          -- Get commit of `checkout`
      { out = 'origin/world' },      -- Check if `monitor` is origin branch (it is)
      { out = 'new2head' },          -- Get commit of `monitor`
      { out = _G.checkout_log },     -- Get log of `checkout` changes
      { out = _G.monitor_log },      -- Get log of `monitor` changes
    }
  ]])
  update()

  -- Should result into a proper sequence of CLI runs
  --stylua: ignore
  local ref_git_spawn_log = {
    { args = { 'version' }, cwd = child.fn.getcwd() },
    { args = { 'remote', 'set-url', 'origin', 'https://github.com/user/plugin_1' }, cwd = test_opt_dir .. '/plugin_1' },
    { 'rev-list', '-1', 'HEAD' },
    { 'branch', '--list', '--all', '--format=%(refname:short)', 'origin/world' },
    { 'rev-list', '-1', 'origin/world' },
    { 'fetch', '--quiet', '--tags', '--force', '--recurse-submodules=yes', 'origin' },
    { 'branch', '--list', '--all', '--format=%(refname:short)', 'origin/hello' },
    { 'rev-list', '-1', 'origin/hello' },
    { 'branch', '--list', '--all', '--format=%(refname:short)', 'origin/world' },
    { 'rev-list', '-1', 'origin/world' },
    log_args('sha1head...new1head'),
    log_args('sha2head...new2head'),
  }
  validate_git_spawn_log(ref_git_spawn_log)

  -- - Modify absolute paths to be more reproducible
  mock_hide_path(test_dir_absolute)
  child.expect_screenshot()
end

T['update()']['shows empty monitor log'] = function()
  child.set_size(27, 80)

  add({ source = 'user/plugin_1', checkout = 'hello', monitor = 'world' })
  child.lua([[
    _G.stdio_queue = {
      { out = 'git version 2.43.0'}, -- Check Git executable
      {},                            -- Set `origin` to source
      { out = 'sha1head' },          -- Get `HEAD`
      -- NOTE: Don't get default branch as both every target is explicit
      { out = 'origin/world' },      -- Check if `monitor` is origin branch
      { out = 'sha2head' },          -- Get commit of `monitor`
      {},                            -- Fetch
      { out = 'origin/hello' },      -- Check if `checkout` is origin branch (it is)
      { out = 'sha1head' },          -- Get commit of `checkout`
      { out = 'origin/world' },      -- Check if `monitor` is origin branch (it is)
      { out = 'sha2head' },          -- Get commit of `monitor`
    }
  ]])
  update()

  mock_hide_path(test_dir_absolute)
  child.expect_screenshot()
end

T['update()']['properly executes `*_checkout` hooks'] = function()
  child.lua([[
    -- Add plugins with hooks
    _G.args = {}
    local make_hook = function(msg)
      return function(...)
        table.insert(_G.args, { msg, { ... } })
        vim.notify(msg)
      end
    end

    for i = 1, 3 do
      local name = 'plugin_' .. i
      MiniDeps.add({
        source = 'user/' .. name,
        hooks = {
          pre_checkout = make_hook(name .. ' pre_checkout'),
          post_checkout = make_hook(name .. ' post_checkout'),
        },
      })
    end

    _G.stdio_queue = {
      { out = 'git version 2.43.0'}, -- Check Git executable
      {},                            -- Set `origin` to source in plugin_1
      {},                            -- Set `origin` to source in plugin_2
      {},                            -- Set `origin` to source in plugin_3
      { out = 'sha1head' },          -- Get `HEAD` in plugin_1
      { out = 'sha2head' },          -- Get `HEAD` in plugin_2
      { out = 'sha3head' },          -- Get `HEAD` in plugin_3
      { out = 'origin/main' },       -- Get default branch in plugin_1
      { out = 'origin/master' },     -- Get default branch in plugin_2
      { out = 'origin/master' },     -- Get default branch in plugin_3
      {},                            -- Fetch in plugin_1
      {},                            -- Fetch in plugin_2
      {},                            -- Fetch in plugin_3
      { out = 'origin/main' },       -- Check if `checkout` is origin branch in plugin_1
      { out = 'origin/master' },     -- Check if `checkout` is origin branch in plugin_2
      { out = 'origin/master' },     -- Check if `checkout` is origin branch in plugin_3
      { out = 'new1head' },          -- Get commit of `checkout` in plugin_1
      { out = 'new2head' },          -- Get commit of `checkout` in plugin_2
      { out = 'sha3head' },          -- Get commit of `checkout` in plugin_3
      { out = 'Log 1' },             -- Get log of `checkout` changes in plugin_1
      { out = 'Log 2' },             -- Get log of `checkout` changes in plugin_2
      {},                            -- Stash in plugin_1
      {},                            -- Stash in plugin_2
      {},                            -- Checkout in plugin_1
      {},                            -- Checkout in plugin_2
    }
  ]])
  child.lua('MiniDeps.update(nil, { force = true })')

  -- Should be called with proper arguments
  local cwd_plugin_1, cwd_plugin_2 = test_opt_dir .. '/plugin_1', test_opt_dir .. '/plugin_2'
  local ref_args = {
    {
      'plugin_1 pre_checkout',
      { { path = cwd_plugin_1, source = 'https://github.com/user/plugin_1', name = 'plugin_1' } },
    },
    {
      'plugin_2 pre_checkout',
      { { path = cwd_plugin_2, source = 'https://github.com/user/plugin_2', name = 'plugin_2' } },
    },
    {
      'plugin_1 post_checkout',
      { { path = cwd_plugin_1, source = 'https://github.com/user/plugin_1', name = 'plugin_1' } },
    },
    {
      'plugin_2 post_checkout',
      { { path = cwd_plugin_2, source = 'https://github.com/user/plugin_2', name = 'plugin_2' } },
    },
  }
  eq(child.lua_get('_G.args'), ref_args)

  -- Should produce notifications
  local ref_notify_log = {
    { '(mini.deps) Downloading 3 updates', 'INFO' },
    { '(mini.deps) (1/3) Downloaded update for `plugin_1`', 'INFO' },
    { '(mini.deps) (2/3) Downloaded update for `plugin_2`', 'INFO' },
    { '(mini.deps) (3/3) Downloaded update for `plugin_3`', 'INFO' },
    { 'plugin_1 pre_checkout' },
    { 'plugin_2 pre_checkout' },
    -- No 'plugin_3' hooks should be executed as no checkout was done
    { '(mini.deps) (1/2) Checked out `main` in `plugin_1`', 'INFO' },
    { '(mini.deps) (2/2) Checked out `master` in `plugin_2`', 'INFO' },
    { 'plugin_1 post_checkout' },
    { 'plugin_2 post_checkout' },
  }
  validate_notifications(ref_notify_log)
end

T['update()']['handles errors in hooks'] = function()
  child.lua([[
    MiniDeps.add({
      source = 'user/plugin_1',
      hooks = { pre_checkout = function() error('Error in `pre_checkout`') end },
    })
    _G.stdio_queue = {
      { out = 'git version 2.43.0'}, -- Check Git executable
      {},                            -- Set `origin` to source
      { out = 'sha1head' },          -- Get `HEAD`
      { out = 'origin/main' },       -- Get default branch
      {},                            -- Fetch
      { out = 'origin/main' },       -- Check if `checkout` is origin branch
      { out = 'new1head' },          -- Get commit of `checkout`
      { out = 'Log 1' },             -- Get log of `checkout` changes
      {},                            -- Stash
      {},                            -- Checkout
    }
  ]])
  child.lua('MiniDeps.update(nil, { force = true, offline = true })')
  --stylua: ignore
  validate_notifications({
    { '(mini.deps) Error executing pre_checkout hook in `plugin_1`:\n[string "<nvim>"]:3: Error in `pre_checkout`', 'ERROR' },
    { '(mini.deps) (1/1) Checked out `main` in `plugin_1`', 'INFO' }
  })
end

T['update()']['generates help tags'] = function()
  child.lua([[
    _G.stdio_queue = {
      { out = 'git version 2.43.0'}, -- Check Git executable
      {},                            -- Set `origin` to source in plugin_1
      {},                            -- Set `origin` to source in plugin_2
      { out = 'sha1head' },          -- Get `HEAD` in plugin_1
      { out = 'sha2head' },          -- Get `HEAD` in plugin_2
      { out = 'origin/main' },       -- Get default branch in plugin_1
      { out = 'origin/master' },     -- Get default branch in plugin_2
      {},                            -- Fetch in plugin_1
      {},                            -- Fetch in plugin_2
      { out = 'origin/main' },       -- Check if `checkout` is origin branch in plugin_1
      { out = 'origin/master' },     -- Check if `checkout` is origin branch in plugin_2
      { out = 'new1head' },          -- Get commit of `checkout` in plugin_1
      { out = 'sha2head' },          -- Get commit of `checkout` in plugin_2
      { out = 'Log 1' },             -- Get log of `checkout` changes in plugin_1
      {},                            -- Stash in plugin_1
      {},                            -- Checkout in plugin_1
    }
  ]])
  add('user/plugin_1')
  add('user/plugin_2')

  child.lua('MiniDeps.update(nil, { force = true })')

  local tags_lines = child.fn.readfile(test_opt_dir .. '/plugin_1/doc/tags')
  eq(tags_lines, { 'depstest_plugin_1_tag\thelp_1.txt\t/*depstest_plugin_1_tag*' })
  eq(child.fn.filereadable(test_opt_dir .. '/plugin_2/doc/tags'), 0)

  -- Help tags are actually reachable
  local help_tags = child.fn.getcompletion('depstest_', 'help')
  table.sort(help_tags)
  eq(help_tags, { 'depstest_plugin_1_tag' })
end

T['update()']['respects `names` argument'] = function()
  add('plugin_1')
  add('plugin_2')

  local validate = function(names)
    clear_notify_log()
    update(names)
    validate_notifications({
      { '(mini.deps) Downloading 1 update', 'INFO' },
      { '(mini.deps) (1/1) Downloaded update for `plugin_1`', 'INFO' },
    })
  end

  validate({ 'plugin_1' })

  -- Should silently drop names not in session
  validate({ 'plugin_1', 'plugin_3', 'not_present_even_on_disk' })

  -- Should allow empty array
  clear_notify_log()
  update({})
  validate_notifications({ { '(mini.deps) Nothing to update', 'INFO' } })
end

T['update()']['valdiates arguments'] = function()
  expect.error(function() update('plugin_1') end, '`names`.*array')
  expect.error(function() update({ 'plugin_1', 1, { name = 'plugin_2' } }) end, '`names`.*strings')
end

T['update()']['respects `opts.force`'] = function()
  add('user/plugin_1')

  child.lua([[
    _G.checkout_log = '> new1head | 2024-01-02 01:01:01 +0200 | Neo McVim\n  Added commit in checkout.'
    _G.stdio_queue = {
      { out = 'git version 2.43.0'}, -- Check Git executable
      {},                            -- Set `origin` to source
      { out = 'sha1head' },          -- Get `HEAD`
      { out = 'origin/main' },       -- Get default branch
      {},                            -- Fetch
      { out = 'origin/main' },       -- Check if `checkout` is origin branch (it is)
      { out = 'new1head' },          -- Get commit of `checkout`
      { out = _G.checkout_log },     -- Get log of `checkout` changes
      {},                            -- Stash
      {},                            -- Checkout
    }
  ]])
  child.lua('MiniDeps.update(nil, { force = true })')

  -- Should result into a proper sequence of CLI runs
  local ref_git_spawn_log = {
    { args = { 'version' }, cwd = child.fn.getcwd() },
    {
      args = { 'remote', 'set-url', 'origin', 'https://github.com/user/plugin_1' },
      cwd = test_opt_dir .. '/plugin_1',
    },
    { 'rev-list', '-1', 'HEAD' },
    { 'rev-parse', '--abbrev-ref', 'origin/HEAD' },
    { 'fetch', '--quiet', '--tags', '--force', '--recurse-submodules=yes', 'origin' },
    { 'branch', '--list', '--all', '--format=%(refname:short)', 'origin/main' },
    { 'rev-list', '-1', 'origin/main' },
    log_args('sha1head...new1head'),
    { 'stash', '--quiet', '--message', '(mini.deps) 2024-01-02 03:04:05 Stash before checkout' },
    { 'checkout', '--quiet', 'new1head' },
  }
  validate_git_spawn_log(ref_git_spawn_log)

  -- Should produce notifications
  local ref_notify_log = {
    { '(mini.deps) Downloading 1 update', 'INFO' },
    { '(mini.deps) (1/1) Downloaded update for `plugin_1`', 'INFO' },
    { '(mini.deps) (1/1) Checked out `main` in `plugin_1`', 'INFO' },
  }
  validate_notifications(ref_notify_log)

  -- Should do actual checkout right away without confirmation
  validate_not_confirm_buf()

  -- Should write to log file
  local log_path = child.lua_get('MiniDeps.config.path.log')
  local log_lines = child.fn.readfile(log_path)
  -- - Make test more reproducible
  log_lines = vim.tbl_map(function(l) return l:gsub(vim.pesc(test_dir_absolute), 'MOCKDIR') end, log_lines)

  local ref_log_lines = {
    '========== Update 2024-01-02 03:04:05 ==========',
    '+++ plugin_1 +++',
    'Path:         MOCKDIR/pack/deps/opt/plugin_1',
    'Source:       https://github.com/user/plugin_1',
    'State before: sha1head',
    'State after:  new1head (main)',
    '',
    'Pending updates from `main`:',
    '> new1head | 2024-01-02 01:01:01 +0200 | Neo McVim',
    '  Added commit in checkout.',
    '',
  }
  eq(log_lines, ref_log_lines)
end

T['update()']['respects `opts.offline`'] = function()
  add('user/plugin_1')

  child.lua([[
    _G.stdio_queue = {
      { out = 'git version 2.43.0'}, -- Check Git executable
      {},                            -- Set `origin` to source
      { out = 'sha1head' },          -- Get `HEAD`
      { out = 'origin/main' },       -- Get default branch
      -- No fetch with `opts.offline`
      { out = 'origin/main' },       -- Check if `checkout` is origin branch (it is)
      { out = 'new1head' },          -- Get commit of `checkout`
      { out = 'Log 1' },             -- Get log of `checkout` changes
    }
  ]])
  child.lua('MiniDeps.update(nil, { offline = true })')

  -- Should result into a proper sequence of CLI runs
  local ref_git_spawn_log = {
    { args = { 'version' }, cwd = child.fn.getcwd() },
    {
      args = { 'remote', 'set-url', 'origin', 'https://github.com/user/plugin_1' },
      cwd = test_opt_dir .. '/plugin_1',
    },
    { 'rev-list', '-1', 'HEAD' },
    { 'rev-parse', '--abbrev-ref', 'origin/HEAD' },
    -- No fetch with `opts.offline`
    { 'branch', '--list', '--all', '--format=%(refname:short)', 'origin/main' },
    { 'rev-list', '-1', 'origin/main' },
    log_args('sha1head...new1head'),
  }
  validate_git_spawn_log(ref_git_spawn_log)

  -- Should produce notifications
  validate_notifications({})
end

T['update()']['respects `config.job.n_threads`'] = function()
  child.lua([[
    _G.stdio_queue = {
      { out = 'git version 2.43.0'}, -- Check Git executable
      {},                            -- Set `origin` to source in plugin_1
      {},                            -- Set `origin` to source in plugin_2
      { out = 'sha1head' },          -- Get `HEAD` in plugin_1
      { out = 'sha2head' },          -- Get `HEAD` in plugin_2
      { out = 'origin/main' },       -- Get default branch in plugin_1
      { out = 'origin/master' },     -- Get default branch in plugin_2
      {},                            -- Fetch in plugin_1
      {},                            -- Fetch in plugin_2
      { out = 'origin/main' },       -- Check if `checkout` is origin branch in plugin_1
      { out = 'origin/master' },     -- Check if `checkout` is origin branch in plugin_2
      { out = 'sha1head' },          -- Get commit of `checkout` in plugin_1
      { out = 'sha2head' },          -- Get commit of `checkout` in plugin_2
    }

    -- Mock non-trivial fetch duration
    _G.process_mock_data = { [8] = { duration = 30 }, [9] = { duration = 30 } }
  ]])
  add('user/plugin_1')
  add('user/plugin_2')

  child.lua('MiniDeps.config.job.n_threads = 1')
  local start_time = child.loop.hrtime()
  update()
  local duration = 0.000001 * (child.loop.hrtime() - start_time)
  eq(40 <= duration, true)
end

T['update()']['works when no information about number of cores is available'] = function()
  child.lua([[
    _G.stdio_queue = {
      { out = 'git version 2.43.0'}, -- Check Git executable
      {},                            -- Set `origin` to source in plugin_1
      { out = 'sha1head' },          -- Get `HEAD` in plugin_1
      { out = 'origin/main' },       -- Get default branch in plugin_1
      {},                            -- Fetch in plugin_1
      { out = 'origin/main' },       -- Check if `checkout` is origin branch in plugin_1
      { out = 'sha1head' },          -- Get commit of `checkout` in plugin_1
    }
  ]])
  add('user/plugin_1')
  child.lua('vim.loop.cpu_info = function() return nil end')
  expect.no_error(update)
end

T['update()']['respects `config.job.timeout`'] = function()
  helpers.skip_if_slow()

  child.lua('_G.duration = ' .. (10 * small_time))
  child.lua([[
    _G.stdio_queue = {
      { out = 'git version 2.43.0'}, -- Check Git executable
      {},                            -- Set `origin` to source in plugin_1
      {},                            -- Set `origin` to source in plugin_2
      { out = 'sha1head' },          -- Get `HEAD` in plugin_1
      { out = 'origin/main' },       -- Get default branch in plugin_1
      {},                            -- Fetch in plugin_1
    }

    -- Mock non-trivial durations
    _G.process_mock_data = { [3] = { duration = _G.duration }, [6] = { duration = _G.duration } }
  ]])
  add('user/plugin_1')
  add('user/plugin_2')

  child.lua('MiniDeps.config.job.timeout = ' .. (5 * small_time))
  update()

  local ref_notify_log = {
    { '(mini.deps) Downloading 1 update', 'INFO' },
    { '(mini.deps) Error in `plugin_1` during update\nERROR CODE 1\nPROCESS REACHED TIMEOUT.', 'ERROR' },
    { '(mini.deps) Error in `plugin_2` during update\nERROR CODE 1\nPROCESS REACHED TIMEOUT.', 'ERROR' },
  }
  validate_notifications(ref_notify_log)
end

T['update()']['respects `config.silent`'] = function()
  add('user/plugin_1')

  child.lua([[
    _G.stdio_queue = {
      { out = 'git version 2.43.0'}, -- Check Git executable
      {},                            -- Set `origin` to source
      { out = 'sha1head' },          -- Get `HEAD`
      { out = 'origin/main' },       -- Get default branch
      {},                            -- Fetch
      { out = 'origin/main' },       -- Check if `checkout` is origin branch (it is)
      { out = 'new1head' },          -- Get commit of `checkout`
      { out = 'Log 1' },             -- Get log of `checkout` changes
      {},                            -- Stash
      {},                            -- Checkout
    }
  ]])

  child.lua('MiniDeps.config.silent = true')
  child.lua('MiniDeps.update(nil, { force = true })')

  -- Should produce no notifications
  validate_notifications({})
end

T['update()']['handles process errors and warnings'] = function()
  add('user/plugin_1')
  add('user/plugin_2')

  child.lua([[
    _G.stdio_queue = {
      { out = 'git version 2.43.0'}, -- Check Git executable
      { err = 'Some warning' },      -- Set `origin` to source in plugin_1
      { err = 'Bad `origin`'},       -- Set `origin` to source in plugin_2
      { out = 'sha2head' },          -- Get `HEAD` in plugin_1
    }

    -- Mock non-zero exit code in getting plugin_1's head
    _G.process_mock_data = { [3] = { exit_code = 1 }, [4] = { exit_code = 128 } }
  ]])

  update()

  -- If any error (from `stderr` or exit code) is encountered, all CLI jobs for
  -- that particular plugin should not be done
  local ref_git_spawn_log = {
    { args = { 'version' }, cwd = child.fn.getcwd() },
    { args = { 'remote', 'set-url', 'origin', 'https://github.com/user/plugin_1' }, cwd = test_opt_dir .. '/plugin_1' },
    { args = { 'remote', 'set-url', 'origin', 'https://github.com/user/plugin_2' }, cwd = test_opt_dir .. '/plugin_2' },
    { args = { 'rev-list', '-1', 'HEAD' }, cwd = test_opt_dir .. '/plugin_1' },
  }
  validate_git_spawn_log(ref_git_spawn_log)

  -- Should produce notifications
  local ref_notify_log = {
    { '(mini.deps) Warnings in `plugin_1` during update\nSome warning', 'WARN' },
    { '(mini.deps) Error in `plugin_1` during update\nERROR CODE 128', 'ERROR' },
    { '(mini.deps) Error in `plugin_2` during update\nERROR CODE 1\nBad `origin`', 'ERROR' },
  }
  validate_notifications(ref_notify_log)
end

T['clean()'] = new_set({
  hooks = {
    pre_case = function()
      local start_dir = test_dir_absolute .. '/pack/deps/start'
      mock_plugin(start_dir .. '/start_plugin')
      local not_in_session_1 = test_opt_dir .. '/plugin_not_in_session_1'
      mock_plugin(not_in_session_1)
      local not_in_session_2 = test_opt_dir .. '/plugin_not_in_session_2'
      mock_plugin(not_in_session_2)
      mock_test_package(test_dir_absolute)

      local lua_cmd = string.format(
        '_G.info = { start_dir = %s, not_in_session_1 = %s, not_in_session_2 = %s }',
        vim.inspect(start_dir),
        vim.inspect(not_in_session_1),
        vim.inspect(not_in_session_2)
      )
      child.lua(lua_cmd)

      add('plugin_1')
      add('plugin_2')
      add('plugin_3')
      add('plu-gin_0.nvim')
      eq(#get_session(), 5)
    end,
    post_case = function()
      child.lua([[
        vim.fn.delete(_G.info.start_dir, 'rf')
        vim.fn.delete(_G.info.not_in_session_1, 'rf')
        vim.fn.delete(_G.info.not_in_session_2, 'rf')
      ]])
    end,
  },
})

local clean = forward_lua('MiniDeps.clean')

T['clean()']['works'] = function()
  child.set_size(15, 80)

  -- Confirmation buffer should be configurable in `FileType` event with
  -- window being current (so as to `vim.wo` can work)
  child.cmd('au FileType minideps-confirm lua _G.minideps_ft_win_id = vim.api.nvim_get_current_win()')

  clean()

  -- By default should show confirmation buffer
  child.set_cursor(1, 0)
  child.wo.wrap = false
  child.expect_screenshot()
  validate_confirm_buf('confirm-clean')
  eq(child.lua_get('_G.minideps_ft_win_id') == child.api.nvim_get_current_win(), true)

  -- Should reveal concealed full path
  child.set_cursor(9, 0)
  -- - Mock absolute path only on current line as path in parenthesis is used
  --   to determine which path to delete from disk.
  child.cmd(':s/' .. child.fn.escape(test_dir_absolute, ' /') .. '/MOCKDIR/')
  child.bo.modified = false
  child.expect_screenshot()

  -- Should delete from disk on buffer write but only listed plugin names
  child.cmd('%g/not_in_session_1/normal! dd')
  child.cmd('write')

  eq(child.lua_get('vim.fn.isdirectory(_G.info.not_in_session_1)'), 1)
  eq(child.lua_get('vim.fn.isdirectory(_G.info.not_in_session_2)'), 0)

  -- Should produce notifications
  validate_notifications({ { '(mini.deps) (1/1) Deleted `plugin_not_in_session_2` from disk', 'INFO' } })

  -- Should close confirm buffer
  validate_not_confirm_buf()
end

T['clean()']['can cancel confirm'] = function()
  clean()
  validate_confirm_buf('confirm-clean')
  child.cmd('quit')
  validate_not_confirm_buf()

  -- Should not delete from disk
  eq(child.lua_get('vim.fn.isdirectory(_G.info.not_in_session_1)'), 1)
  eq(child.lua_get('vim.fn.isdirectory(_G.info.not_in_session_2)'), 1)
  validate_notifications({})
end

T['clean()']['respects `opts.force`'] = function()
  clean({ force = true })

  -- Should delete from disk without confirmation
  validate_not_confirm_buf()
  eq(child.lua_get('vim.fn.isdirectory(_G.info.not_in_session_1)'), 0)
  eq(child.lua_get('vim.fn.isdirectory(_G.info.not_in_session_2)'), 0)

  validate_notifications({
    { '(mini.deps) (1/2) Deleted `plugin_not_in_session_1` from disk', 'INFO' },
    { '(mini.deps) (2/2) Deleted `plugin_not_in_session_2` from disk', 'INFO' },
  })
end

T['clean()']['respects `config.silent`'] = function()
  child.lua('MiniDeps.config.silent = true')
  clean({ force = true })
  validate_notifications({})
end

T['clean()']['shows notification when nothing to clean'] = function()
  add('plugin_not_in_session_1')
  add('plugin_not_in_session_2')
  clean({ force = true })
  validate_notifications({ { '(mini.deps) Nothing to clean', 'INFO' } })
end

T['snap_get()'] = new_set({
  hooks = {
    pre_case = function()
      mock_plugin(test_dir_absolute .. '/pack/deps/start/start_plugin')
      load_module({ path = { package = test_dir_absolute } })
      add('plugin_1')
    end,
    post_case = function() child.fn.delete(test_dir_absolute .. '/pack/deps/start', 'rf') end,
  },
})

local snap_get = forward_lua('MiniDeps.snap_get')

T['snap_get()']['works'] = function()
  child.lua([[
    _G.stdio_queue = {
      { out = 'git version 2.43.0'}, -- Check Git executable
      { out = 'sha1head' },          -- Get `HEAD` in plugin_1
      { out = 'sha2head' },          -- Get `HEAD` in start_plugin
    }
  ]])

  local snap = snap_get()

  -- Should return snapshot
  eq(snap, { plugin_1 = 'sha1head', start_plugin = 'sha2head' })

  -- Should not produce notifications
  validate_notifications({})
end

T['snap_get()']['checks for executable Git'] = function()
  add('plugin_1')
  child.lua([[
    _G.stdio_queue = { { err = 'No Git'} }
    _G.process_mock_data = { { exit_code = 1 } }
  ]])
  expect.error(snap_get, 'Could not find executable `git` CLI tool')
end

T['snap_get()']['handles process errors'] = function()
  child.lua([[
    _G.stdio_queue = {
      { out = 'git version 2.43.0'}, -- Check Git executable
      { err = 'Some error' },        -- Get `HEAD` in plugin_1
      { out = 'sha2head' },          -- Get `HEAD` in start_plugin
    }
    _G.process_mock_data = { [2] = { exit_code = 1 } }
  ]])

  -- Should still return snapshot but without data for errored plugins
  local snap = snap_get()
  eq(snap, { start_plugin = 'sha2head' })

  -- Should show error notifications
  validate_notifications({
    { '(mini.deps) Error in `plugin_1` during computing snapshot\nERROR CODE 1\nSome error', 'ERROR' },
  })
end

T['snap_set()'] = new_set({
  hooks = {
    pre_case = function()
      mock_plugin(test_dir_absolute .. '/pack/deps/start/start_plugin')
      load_module({ path = { package = test_dir_absolute } })
      add({ name = 'plugin_1', checkout = 'hello' })
      add({ name = 'plugin_2' })
    end,
    post_case = function()
      child.fn.delete(test_dir_absolute .. '/pack/deps/start', 'rf')
      child.fn.delete(test_opt_dir .. '/plugin_1/doc/tags', 'rf')
      child.fn.delete(test_opt_dir .. '/plugin_2/doc/tags', 'rf')
    end,
  },
})

local snap_set = forward_lua('MiniDeps.snap_set')

T['snap_set()']['works'] = function()
  local init_session = get_session()
  child.lua([[
    _G.stdio_queue = {
      { out = 'git version 2.43.0'},  -- Check Git executable
      { out = 'sha1head' },           -- Get `HEAD` in plugin_1
      -- Should stop other steps for plugin after first error
      { err = 'Error getting HEAD' }, -- Get `HEAD` in plugin_2
      { out = 'shaShead' },           -- Get `HEAD` in start_plugin
      { out = 'origin/main' },        -- Get default branch in plugin_1
      { out = 'origin/master' },      -- Get default branch in start_plugin
      { out = '' },                   -- Check if snap state is origin branch in plugin_1 (it is not)
      { out = '' },                   -- Check if snap state is origin branch in start_plugin (it is not)
      { out = 'new1head' },           -- Get commit of `checkout` in plugin_1
      { out = 'shaShead' },           -- Get commit of `checkout` in start_plugin
      {},                             -- Stash in start_plugin
      {},                             -- Checkout in start_plugin
    }
    _G.process_mock_data = { [3] = { exit_code = 1 } }
  ]])

  -- Should apply only to plugins inside current session
  snap_set({ plugin_1 = 'new1head', plugin_2 = 'sha2head', start_plugin = 'shaShead' })

  local cwd_plugin_1, cwd_plugin_2, cwd_start_plugin =
    test_opt_dir .. '/plugin_1', test_opt_dir .. '/plugin_2', test_dir_absolute .. '/pack/deps/start/start_plugin'
  local ref_git_spawn_log = {
    { args = { 'version' }, cwd = child.fn.getcwd() },

    { args = { 'rev-list', '-1', 'HEAD' }, cwd = cwd_plugin_1 },
    { args = { 'rev-list', '-1', 'HEAD' }, cwd = cwd_plugin_2 },
    { args = { 'rev-list', '-1', 'HEAD' }, cwd = cwd_start_plugin },

    { args = { 'rev-parse', '--abbrev-ref', 'origin/HEAD' }, cwd = cwd_plugin_1 },
    { args = { 'rev-parse', '--abbrev-ref', 'origin/HEAD' }, cwd = cwd_start_plugin },

    { args = { 'branch', '--list', '--all', '--format=%(refname:short)', 'origin/new1head' }, cwd = cwd_plugin_1 },
    { args = { 'branch', '--list', '--all', '--format=%(refname:short)', 'origin/shaShead' }, cwd = cwd_start_plugin },

    { args = { 'rev-list', '-1', 'new1head' }, cwd = cwd_plugin_1 },
    { args = { 'rev-list', '-1', 'shaShead' }, cwd = cwd_start_plugin },

    {
      args = { 'stash', '--quiet', '--message', '(mini.deps) 2024-01-02 03:04:05 Stash before checkout' },
      cwd = cwd_plugin_1,
    },
    { args = { 'checkout', '--quiet', 'new1head' }, cwd = cwd_plugin_1 },
  }
  validate_git_spawn_log(ref_git_spawn_log)

  -- Should produce notifications
  local ref_notify_log = {
    { '(mini.deps) (1/1) Checked out `new1head` in `plugin_1`', 'INFO' },
    { '(mini.deps) Error in `plugin_2` during applying snapshot\nERROR CODE 1\nError getting HEAD', 'ERROR' },
  }
  validate_notifications(ref_notify_log)

  -- Should generate help tags in actually checked out plugins
  local tags_lines = child.fn.readfile(test_opt_dir .. '/plugin_1/doc/tags')
  eq(tags_lines, { 'depstest_plugin_1_tag\thelp_1.txt\t/*depstest_plugin_1_tag*' })
  eq(child.fn.filereadable(test_opt_dir .. '/plugin_2/doc/tags'), 0)

  -- - Help tags should be actually reachable
  local help_tags = child.fn.getcompletion('depstest_', 'help')
  table.sort(help_tags)
  eq(help_tags, { 'depstest_plugin_1_tag' })

  -- Should not affect current session data
  eq(get_session(), init_session)
end

T['snap_set()']['checks for executable Git'] = function()
  add('plugin_1')
  child.lua([[
    _G.stdio_queue = { { err = 'No Git'} }
    _G.process_mock_data = { { exit_code = 1 } }
  ]])
  expect.error(function() snap_set({}) end, 'Could not find executable `git` CLI tool')
end

T['snap_set()']['validates arguments'] = function()
  expect.error(function() snap_set(1) end, 'Snapshot.*table')
end

T['snap_load()'] = new_set({
  hooks = {
    pre_case = function() child.lua('MiniDeps.snap_set = function(...) _G.snap_set_args = { ... } end') end,
  },
})

local snap_load = forward_lua('MiniDeps.snap_load')

T['snap_load()']['works'] = function()
  load_module({ path = { snapshot = test_snap_path } })
  snap_load()
  eq(child.lua_get('_G.snap_set_args'), { { plugin_1 = 'sha1head', plugin_2 = 'sha2head' } })
end

T['snap_load()']['respects `path`'] = function()
  local validate = function(path)
    snap_load(path)
    eq(child.lua_get('_G.snap_set_args'), { { plugin_1 = 'sha1head', plugin_2 = 'sha2head' } })
    child.lua('_G.snap_set_args = nil')
  end

  -- Should work both with absolute and relative paths
  validate(test_dir_absolute .. '/snapshots/snap')
  validate(test_dir .. '/snapshots/snap')
end

T['snap_load()']['validates arguments'] = function()
  expect.error(function() snap_load(1) end, '`path`.*readable file')

  -- Should validate if file contains proper-ish snapshot
  local validate = function(path)
    expect.error(function() snap_load(path) end, '`path`.*not a path to proper snapshot')
  end
  validate(test_dir_absolute .. '/snapshots/not-proper-1')
  validate(test_dir_absolute .. '/snapshots/not-proper-2')
end

T['snap_save()'] = new_set({
  hooks = {
    pre_case = function()
      -- Use path in non-existing directory to test parent directory creation
      local snap_path = test_dir_absolute .. '/test-snap-save/snap'
      load_module({ path = { snapshot = snap_path } })
      child.lua([[
        MiniDeps.snap_get = function() return { plugin_1 = 'sha1head', ['bad name'] = 'shaBhead' } end
      ]])
    end,
    post_case = function() child.fn.delete(test_dir_absolute .. '/test-snap-save', 'rf') end,
  },
})

local snap_save = forward_lua('MiniDeps.snap_save')

T['snap_save()']['works'] = function()
  local validate = function(path)
    eq(child.fn.readfile(path), { 'return {', '  ["bad name"] = "shaBhead",', '  plugin_1 = "sha1head"', '}' })
  end

  snap_save()
  local def_path = child.lua_get('MiniDeps.config.path.snapshot')
  validate(def_path)

  -- Should produce notifications
  validate_notifications({
    { '(mini.deps) Created snapshot at ' .. vim.inspect(def_path), 'INFO' },
  })

  -- Should respect `path`
  local path = test_dir_absolute .. '/test-snap-save/other-snap'
  snap_save(path)
  validate(path)
end

T['snap_save()']['validates arguments'] = function()
  expect.error(function() snap_save(1) end, '`path`.*string')
end

T['get_session()'] = new_set({ hooks = { pre_case = mock_test_package } })

T['get_session()']['works'] = function()
  add('plugin_1')
  add({ source = 'https://my_site.com/plugin_2', depends = { 'user/plugin_3' } })
  eq(get_session(), {
    { path = test_opt_dir .. '/plugin_1', name = 'plugin_1', depends = {}, hooks = {} },
    {
      path = test_opt_dir .. '/plugin_3',
      name = 'plugin_3',
      source = 'https://github.com/user/plugin_3',
      depends = {},
      hooks = {},
    },
    {
      path = test_opt_dir .. '/plugin_2',
      name = 'plugin_2',
      source = 'https://my_site.com/plugin_2',
      depends = { 'user/plugin_3' },
      hooks = {},
    },
  })
end

T['get_session()']['works even after several similar `add()`'] = function()
  add({ source = 'user/plugin_1', checkout = 'hello', depends = { 'plugin_2' } })
  -- Every extra adding should override previous but only new data fields
  add({ name = 'plugin_1', checkout = 'hello' })
  add({ name = 'plugin_2', checkout = 'world' })
  add({ source = 'https://my_site.com/plugin_1', depends = { 'plugin_3' } })

  eq(get_session(), {
    { path = test_opt_dir .. '/plugin_2', name = 'plugin_2', depends = {}, hooks = {}, checkout = 'world' },
    {
      path = test_opt_dir .. '/plugin_1',
      name = 'plugin_1',
      source = 'https://my_site.com/plugin_1',
      -- Although both 'plugin_2' and 'plugin_3' are in dependencies,
      -- 'plugin_1' was added only indicating 'plugin_2' as dependency, so it
      -- only has it in session before itself.
      depends = { 'plugin_2', 'plugin_3' },
      hooks = {},
      checkout = 'hello',
    },
    { path = test_opt_dir .. '/plugin_3', name = 'plugin_3', depends = {}, hooks = {} },
  })
end

T['get_session()']["respects plugins from 'start' directory which are in 'runtimepath'"] = function()
  local start_dir = test_dir_absolute .. '/pack/deps/start'
  mock_plugin(start_dir .. '/start')
  mock_plugin(start_dir .. '/start_manual')
  mock_plugin(start_dir .. '/start_manual_dependency')
  mock_plugin(start_dir .. '/start_not_in_rtp')
  MiniTest.finally(function() child.fn.delete(start_dir, 'rf') end)
  mock_test_package(test_dir_absolute)

  -- Make sure that only somem of 'start' plugins are in 'runtimepath'
  local lua_cmd = string.format(
    'vim.api.nvim_list_runtime_paths = function() return { %s, %s, %s } end',
    vim.inspect(start_dir .. '/start_manual'),
    vim.inspect(start_dir .. '/start_manual_dependency'),
    vim.inspect(start_dir .. '/start')
  )
  child.lua(lua_cmd)

  -- Add some plugins manually both from 'opt' and 'start' directories
  add('plugin_1')
  add({ source = 'user/start_manual', depends = { 'start_manual_dependency' } })

  eq(get_session(), {
    -- Should add plugins from "start" *after* manually added ones
    { path = test_opt_dir .. '/plugin_1', name = 'plugin_1', depends = {}, hooks = {} },

    -- Should not affect or duplicate already manually added ones
    { path = start_dir .. '/start_manual_dependency', name = 'start_manual_dependency', depends = {}, hooks = {} },

    {
      path = start_dir .. '/start_manual',
      name = 'start_manual',
      source = 'https://github.com/user/start_manual',
      depends = { 'start_manual_dependency' },
      hooks = {},
    },

    { path = start_dir .. '/start', name = 'start', depends = {}, hooks = {} },
  })
end

T['get_session()']['returns copy'] = function()
  add({ name = 'plugin_1', depends = { 'plugin_2' } })
  child.lua([[
    _G.session = MiniDeps.get_session()
    _G.session[1].name = 'new name'
    _G.session[2].depends = { 'new dep' }
  ]])
  local session = get_session()
  eq(session[1].name, 'plugin_2')
  eq(session[2].depends, { 'plugin_2' })
end

T['now()'] = new_set()

T['now()']['works'] = function()
  -- Should execute input right now
  child.lua([[
    _G.log = {}
    MiniDeps.now(function() log[#log + 1] = 'now' end)
    log[#log + 1] = 'after now'
  ]])
  eq(child.lua_get('_G.log'), { 'now', 'after now' })
end

T['now()']['can be called inside other `now()`/`later()` call'] = function()
  child.lua([[
    _G.log = {}
    MiniDeps.now(function()
      log[#log + 1] = 'now'
      MiniDeps.now(function() log[#log + 1] = 'now_now' end)
    end)
    MiniDeps.later(function()
      log[#log + 1] = 'later'
      MiniDeps.now(function() log[#log + 1] = 'later_now' end)
    end)
    _G.immediate_log = vim.deepcopy(_G.log)
  ]])
  eq(child.lua_get('_G.immediate_log'), { 'now', 'now_now' })

  sleep(small_time)
  eq(child.lua_get('_G.log'), { 'now', 'now_now', 'later', 'later_now' })
end

T['now()']['clears queue between different event loops'] = function()
  child.lua([[
    _G.log = {}
    _G.f = function() log[#log + 1] = 'now' end
    MiniDeps.now(_G.f)
    _G.immediate_log = vim.deepcopy(_G.log)
  ]])
  eq(child.lua_get('_G.immediate_log'), { 'now' })

  sleep(small_time)
  child.lua('MiniDeps.now(_G.f)')
  -- If it did not clear the queue, it would have been 3 elements
  eq(child.lua_get('_G.log'), { 'now', 'now' })
end

T['now()']['notifies about errors after everything is executed'] = function()
  child.lua([[
    MiniDeps.now(function() error('Inside now()') end)
    local f = function() vim.notify('Info', vim.log.levels.INFO) end
    MiniDeps.later(f)
    MiniDeps.later(f)
  ]])

  sleep(2 * small_time)
  validate_notifications({ { 'Info', 'INFO' }, { 'Info', 'INFO' }, { 'errors.*Inside now()', 'ERROR' } }, true)
end

T['now()']['shows all errors at once'] = function()
  child.lua([[
    MiniDeps.now(function() error('Inside now() #1') end)
    MiniDeps.now(function() error('Inside now() #2') end)
  ]])
  sleep(micro_time)
  validate_notifications({ { 'errors.*Inside now%(%) #1.*Inside now%(%) #2', 'ERROR' } }, true)
end

T['now()']['does not respect `config.silent`'] = function()
  -- Should still show errors even if `config.silent = true`
  child.lua('MiniDeps.config.silent = true')
  child.lua('MiniDeps.now(function() error("Inside now()") end)')
  sleep(micro_time)
  validate_notifications({ { 'Inside now%(%)', 'ERROR' } }, true)
end

T['later()'] = new_set()

T['later()']['works'] = function()
  -- Should execute input later without blocking
  child.lua([[
    _G.log = {}
    MiniDeps.later(function() log[#log + 1] = 'later' end)
    log[#log + 1] = 'after later'
    _G.log_in_this_loop = vim.deepcopy(_G.log)
  ]])
  eq(child.lua_get('_G.log_in_this_loop'), { 'after later' })

  sleep(small_time)
  eq(child.lua_get('_G.log'), { 'after later', 'later' })
end

T['later()']['can be called inside other `now()`/`later()` call'] = function()
  child.lua([[
    _G.log = {}
    MiniDeps.later(function()
      log[#log + 1] = 'later'
      MiniDeps.later(function() log[#log + 1] = 'later_later' end)
    end)
    MiniDeps.now(function()
      log[#log + 1] = 'now'
      MiniDeps.later(function() log[#log + 1] = 'now_later' end)
    end)
    _G.immediate_log = vim.deepcopy(_G.log)
  ]])
  eq(child.lua_get('_G.immediate_log'), { 'now' })

  sleep(2 * small_time)
  eq(child.lua_get('_G.log'), { 'now', 'later', 'now_later', 'later_later' })
end

T['later()']['clears queue between different event loops'] = function()
  child.lua([[
    _G.log = {}
    _G.f = function() log[#log + 1] = 'later' end
    MiniDeps.later(_G.f)
    _G.immediate_log = vim.deepcopy(_G.log)
  ]])
  eq(child.lua_get('_G.immediate_log'), {})
  sleep(micro_time)
  eq(child.lua_get('_G.log'), { 'later' })

  child.lua('MiniDeps.later(_G.f)')
  -- If it did not clear the queue, it would have been 3 elements
  sleep(2 * micro_time)
  eq(child.lua_get('_G.log'), { 'later', 'later' })
end

T['later()']['notifies about errors after everything is executed'] = function()
  child.lua([[
    MiniDeps.later(function() error('Inside later()') end)
    local f = function() vim.notify('Info', vim.log.levels.INFO) end
    MiniDeps.later(f)
    MiniDeps.later(f)
  ]])

  sleep(2 * small_time)
  validate_notifications({ { 'Info', 'INFO' }, { 'Info', 'INFO' }, { 'errors.*Inside later()', 'ERROR' } }, true)
end

T['later()']['shows all errors at once'] = function()
  child.lua([[
    MiniDeps.later(function() error('Inside later() #1') end)
    MiniDeps.later(function() error('Inside later() #2') end)
  ]])
  sleep(2 * small_time)
  validate_notifications({ { 'errors.*Inside later%(%) #1.*Inside later%(%) #2', 'ERROR' } }, true)
end

T['later()']['does not respect `config.silent`'] = function()
  -- Should still show errors even if `config.silent = true`
  child.lua('MiniDeps.config.silent = true')
  child.lua('MiniDeps.later(function() error("Inside later()") end)')
  sleep(small_time)
  validate_notifications({ { 'Inside later%(%)', 'ERROR' } }, true)
end

-- Integration tests ----------------------------------------------------------
T['Commands'] =
  new_set({ hooks = {
    pre_case = function()
      mock_test_package()
      child.set_size(10, 30)
    end,
  } })

local validate_cmd = function(cmd, ref_args)
  child.lua('_G.args = nil')
  child.cmd(cmd)
  -- Use `vim.inspect()` because some arguments have troubles going through RPC
  -- (like {nil, { ... }})
  eq(child.lua_get('vim.inspect(_G.args)'), vim.inspect(ref_args))
end

T['Commands'][':DepsAdd works'] = function()
  child.lua('MiniDeps.add = function(...) _G.args = { ... } end')

  validate_cmd('DepsAdd user/new_plugin nothing_more should_be_added', { 'user/new_plugin' })

  -- Should have proper completion
  child.type_keys(':DepsAdd ', '<Tab>')
  if child.fn.has('nvim-0.12') == 0 then
    child.expect_screenshot()
    return
  end
  local ref_cmdcomplete_info = {
    cmdline_orig = 'DepsAdd ',
    matches = { 'plu-gin_0.nvim', 'plugin_1', 'plugin_2', 'plugin_3' },
    pum_visible = 1,
    selected = 0,
  }
  eq(child.fn.cmdcomplete_info(), ref_cmdcomplete_info)
end

T['Commands'][':DepsUpdate works'] = function()
  child.lua('MiniDeps.update = function(...) _G.args = { ... } end')
  add('plugin_1')
  add('plugin_2')

  validate_cmd('DepsUpdate', { nil, { force = false, offline = false } })
  validate_cmd(
    'DepsUpdate plugin_1 plugin_2 plugin_3',
    { { 'plugin_1', 'plugin_2', 'plugin_3' }, { force = false, offline = false } }
  )

  -- Should accept bang
  validate_cmd('DepsUpdate!', { nil, { force = true, offline = false } })
  validate_cmd(
    'DepsUpdate! plugin_1 plugin_2 plugin_3',
    { { 'plugin_1', 'plugin_2', 'plugin_3' }, { force = true, offline = false } }
  )

  -- Should have proper completion
  child.type_keys(':DepsUpdate ', '<Tab>')
  if child.fn.has('nvim-0.12') == 0 then
    child.expect_screenshot()
    return
  end
  local ref_cmdcomplete_info = {
    cmdline_orig = 'DepsUpdate ',
    matches = { 'plugin_1', 'plugin_2' },
    pum_visible = 1,
    selected = 0,
  }
  eq(child.fn.cmdcomplete_info(), ref_cmdcomplete_info)
end

T['Commands'][':DepsUpdateOffline works'] = function()
  child.lua('MiniDeps.update = function(...) _G.args = { ... } end')
  add('plugin_1')
  add('plugin_2')

  validate_cmd('DepsUpdateOffline', { nil, { force = false, offline = true } })
  validate_cmd(
    'DepsUpdateOffline plugin_1 plugin_2 plugin_3',
    { { 'plugin_1', 'plugin_2', 'plugin_3' }, { force = false, offline = true } }
  )

  -- Should accept bang
  validate_cmd('DepsUpdateOffline!', { nil, { force = true, offline = true } })
  validate_cmd(
    'DepsUpdateOffline! plugin_1 plugin_2 plugin_3',
    { { 'plugin_1', 'plugin_2', 'plugin_3' }, { force = true, offline = true } }
  )

  -- Should have proper completion
  child.type_keys(':DepsUpdateOffline ', '<Tab>')
  if child.fn.has('nvim-0.12') == 0 then
    child.expect_screenshot()
    return
  end
  local ref_cmdcomplete_info = {
    cmdline_orig = 'DepsUpdateOffline ',
    matches = { 'plugin_1', 'plugin_2' },
    pum_visible = 1,
    selected = 0,
  }
  eq(child.fn.cmdcomplete_info(), ref_cmdcomplete_info)
end

T['Commands'][':DepsShowLog works'] = function()
  child.set_size(12, 60)
  load_module({ path = { package = test_opt_dir, log = test_dir_absolute .. '/test-log' } })
  local n_bufs = #child.api.nvim_list_bufs()
  child.cmd('DepsShowLog')
  child.expect_screenshot()

  -- Should open path in relative form for nicer `:buffers`
  expect.match(child.cmd_capture('buffers'):gsub('\\', '/'), 'tests/dir%-deps/test%-log')

  -- Should mimic `:h buffer-reuse` similar to how `:edit` does it
  eq(#child.api.nvim_list_bufs(), n_bufs)
end

T['Commands'][':DepsClean works'] = function()
  child.lua('MiniDeps.clean = function(...) _G.args = { ... } end')
  validate_cmd('DepsClean', { { force = false } })
  validate_cmd('DepsClean!', { { force = true } })
end

T['Commands'][':DepsSnapSave works'] = function()
  child.lua('MiniDeps.snap_save = function(...) _G.args = { ... } end')

  validate_cmd('DepsSnapSave', {})
  validate_cmd('DepsSnapSave path/to/file should_not be_used', { 'path/to/file' })

  -- Should have proper completion
  eq(child.api.nvim_get_commands({})['DepsSnapSave'].complete, 'file')
end

T['Commands'][':DepsSnapLoad works'] = function()
  child.lua('MiniDeps.snap_load = function(...) _G.args = { ... } end')

  validate_cmd('DepsSnapLoad', {})
  validate_cmd('DepsSnapLoad path/to/file should_not be_used', { 'path/to/file' })

  -- Should have proper completion
  eq(child.api.nvim_get_commands({})['DepsSnapLoad'].complete, 'file')
end

return T
