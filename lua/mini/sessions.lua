--- *mini.sessions* Session management
---
--- MIT License Copyright (c) 2021 Evgeni Chasnovski

--- Read, write, and delete sessions. Uses |:mksession| (meaning 'sessionoptions'
--- is fully respected). This is intended as a drop-in Lua replacement for
--- [mhinz/vim-startify](https://github.com/mhinz/vim-startify) session management
--- (works out of the box with sessions created by it). Implements both global
--- (from configured directory) and local (from current directory) sessions.
---
--- Key design ideas:
--- - Sessions are represented by readable files (results of applying |:mksession|).
---   There are two kinds of sessions:
---     - Global: any file inside a configurable directory.
---     - Local: configurable file inside current working directory (|getcwd()|).
---
--- - All session files are detected during `MiniSessions.setup()` and during
---   relevant actions (`read`, `delete`, `select`) with file names as session
---   names (including possible extension).
---
--- - No automated new session creation. Use |MiniSessions.write()| manually.
---
--- - Store information about detected sessions in separate table
---   (|MiniSessions.detected|) and operate only on it. Meaning if this information
---   changes, there will be no effect until next detection. To avoid confusion,
---   don't directly use |:mksession| / |:source| for writing / reading session files.
---
--- Features:
--- - Autoread default session (local if detected, else latest written global) if
---   Neovim was called without intention to show something else.
---
--- - Autowrite currently read session before leaving it (quit Neovim or read
---   another session).
---
--- - Configurable severity level of all actions.
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.sessions').setup({})`
--- (replace `{}` with your `config` table). It will create global Lua table
--- `MiniSessions` which you can use for scripting or manually (with
--- `:lua MiniSessions.*`).
---
--- See |MiniSessions.config| for `config` structure and default values.
---
--- This module doesn't benefit from buffer local configuration, so using
--- `vim.b.minisessions_config` will have no effect here.
---
--- # Disabling ~
---
--- To disable core functionality, set `vim.g.minisessions_disable` (globally) or
--- `vim.b.minisessions_disable` (for a buffer) to `true`. Considering high
--- number of different scenarios and customization intentions, writing exact
--- rules for disabling module's functionality is left to user. See
--- |mini.nvim-disabling-recipes| for common recipes.
---@tag MiniSessions

-- Module definition ==========================================================
local MiniSessions = {}
local H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniSessions.config|.
---
---@usage >lua
---   require('mini.sessions').setup() -- use default config
---   -- OR
---   require('mini.sessions').setup({}) -- replace {} with your config table
--- <
MiniSessions.setup = function(config)
  -- Export module
  _G.MiniSessions = MiniSessions

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Define behavior
  H.create_autocommands(config)
end

--- Defaults ~
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
MiniSessions.config = {
  -- Whether to read default session if Neovim opened without file arguments
  autoread = false,

  -- Whether to write currently read session before leaving it
  autowrite = true,

  -- Directory where global sessions are stored (use `''` to disable)
  --minidoc_replace_start directory = --<"session" subdir of user data directory from |stdpath()|>,
  directory = vim.fn.stdpath('data') .. '/session',
  --minidoc_replace_end

  -- File for local session (use `''` to disable)
  file = 'Session.vim',

  -- Whether to force possibly harmful actions (meaning depends on function)
  force = { read = false, write = true, delete = false },

  -- Hook functions for actions. Default `nil` means 'do nothing'.
  -- Takes table with active session data as argument.
  hooks = {
    -- Before successful action
    pre = { read = nil, write = nil, delete = nil },
    -- After successful action
    post = { read = nil, write = nil, delete = nil },
  },

  -- Whether to print session path after action
  verbose = { read = false, write = true, delete = true },
}
--minidoc_afterlines_end

-- Module data ================================================================
--- Table of detected sessions. Keys represent session name. Values are tables
--- with session information that currently has these fields (but subject to
--- change):
--- - <modify_time> `(number)` modification time (see |getftime()|) of session file.
--- - <name> `(string)` name of session (should be equal to table key).
--- - <path> `(string)` full path to session file.
--- - <type> `(string)` type of session ('global' or 'local').
MiniSessions.detected = {}

-- Module functionality =======================================================
--- Read detected session
---
--- What it does:
--- - If there is an active session and `autowrite` is `true` in |MiniSessions.config|,
---   write it with |MiniSessions.write()|.
--- - Delete all current buffers with |:bwipeout|. This is needed to correctly
---   restore buffers from target session. If `force` is not `true`, checks
---   beforehand for unsaved listed buffers and stops if there are any.
--- - Source session with supplied name.
---
---@param session_name string|nil Name of detected session file to read. Default:
---   `nil` for default session: local (if detected) or latest session (see
---   |MiniSessions.get_latest()|).
---@param opts table|nil Table with options. Current allowed keys:
---   - <force> (whether to delete unsaved buffers; default:
---     `MiniSessions.config.force.read`).
---   - <verbose> (whether to print session path after action; default
---     `MiniSessions.config.verbose.read`).
---   - <hooks> (a table with <pre> and <post> function hooks to be executed
---     with session data argument before and after successful read; overrides
---     `MiniSessions.config.hooks.pre.read` and
---     `MiniSessions.config.hooks.post.read`).
MiniSessions.read = function(session_name, opts)
  if H.is_disabled() then return end

  -- Make sessions up to date
  H.detect_sessions()
  if vim.tbl_count(MiniSessions.detected) == 0 then
    return H.message('There are no detected sessions. Change configuration and rerun `MiniSessions.setup()`.')
  end

  -- Get session data
  if session_name == nil then
    if MiniSessions.detected[MiniSessions.config.file] ~= nil then
      session_name = MiniSessions.config.file
    else
      session_name = MiniSessions.get_latest()
    end
  end

  opts = vim.tbl_deep_extend('force', H.default_opts('read'), opts or {})

  if not H.validate_detected(session_name) then return end

  local data = MiniSessions.detected[session_name]

  -- Possibly check for unsaved listed buffers and do nothing if present
  if not opts.force then
    local unsaved_listed_buffers = H.get_unsaved_listed_buffers()

    if #unsaved_listed_buffers > 0 then
      local buf_list = table.concat(unsaved_listed_buffers, ', ')
      H.error(('There are unsaved listed buffers: %s.'):format(buf_list))
    end
  end

  -- Write current session to allow proper switching between sessions
  if H.get_this_session() ~= '' and MiniSessions.config.autowrite then
    MiniSessions.write(nil, { force = true, verbose = false })
  end

  -- Execute 'pre' hook
  H.possibly_execute(opts.hooks.pre, data)

  -- Wipeout all buffers
  vim.cmd('silent! %bwipeout!')

  -- Read session file
  local session_path = data.path
  vim.cmd(('silent! source %s'):format(vim.fn.fnameescape(session_path)))
  vim.v.this_session = session_path

  -- Possibly notify
  if opts.verbose then H.message(('Read session %s'):format(session_path)) end

  -- Ensure correct detected local session
  H.detect_sessions()

  -- Execute 'post' hook
  H.possibly_execute(opts.hooks.post, data)
end

--- Write session
---
--- What it does:
--- - Check if file for supplied session name already exists. If it does and
---   `force` is not `true`, then stop.
--- - Write session with |:mksession| to a file named `session_name`. Its
---   directory is determined based on type of session:
---     - It is at location |v:this_session| if `session_name` is `nil` and
---       there is currently read session.
---     - It is current working directory (|getcwd()|) if `session_name` is equal
---       to `MiniSessions.config.file` (represents local session).
---     - It is `MiniSessions.config.directory` otherwise (represents global
---       session).
--- - Update |MiniSessions.detected|.
---
---@param session_name string|nil Name of session file to write. Default: `nil` for
---   currently read session (|v:this_session|).
---@param opts table|nil Table with options. Current allowed keys:
---   - <force> (whether to ignore existence of session file; default:
---     `MiniSessions.config.force.write`).
---   - <verbose> (whether to print session path after action; default
---     `MiniSessions.config.verbose.write`).
---   - <hooks> (a table with <pre> and <post> function hooks to be executed
---     with session data argument before and after successful write; overrides
---     `MiniSessions.config.hooks.pre.write` and
---     `MiniSessions.config.hooks.post.write`).
MiniSessions.write = function(session_name, opts)
  if H.is_disabled() then return end

  opts = vim.tbl_deep_extend('force', H.default_opts('write'), opts or {})

  local session_path = H.name_to_path(session_name)

  if not opts.force and H.is_readable_file(session_path) then
    H.error([[Can't write to existing session when `opts.force` is not `true`.]])
  end

  local data = H.new_session(session_path)

  -- Execute 'pre' hook
  H.possibly_execute(opts.hooks.pre, data)

  -- Make session file
  local command = string.format('mksession%s %s', opts.force and '!' or '', vim.fn.fnameescape(session_path))
  vim.cmd(command)
  data.modify_time = vim.fn.getftime(session_path)

  -- Update detected sessions
  MiniSessions.detected[data.name] = data

  -- Update current session
  vim.v.this_session = session_path

  -- Possibly notify
  if opts.verbose then H.message(('Written session %s'):format(session_path)) end

  -- Execute 'post' hook
  H.possibly_execute(opts.hooks.post, data)
end

--- Delete detected session
---
--- What it does:
--- - Check if session name is a current one. If yes and `force` is not `true`,
---   then stop.
--- - Delete session.
--- - Update |MiniSessions.detected|.
---
---@param session_name string|nil Name of detected session file to delete. Default:
---   `nil` for name of currently read session (taken from |v:this_session|).
---@param opts table|nil Table with options. Current allowed keys:
---   - <force> (whether to allow deletion of current session; default:
---     `MiniSessions.config.force.delete`).
---   - <verbose> (whether to print session path after action; default
---     `MiniSessions.config.verbose.delete`).
---   - <hooks> (a table with <pre> and <post> function hooks to be executed
---     with session data argument before and after successful delete; overrides
---     `MiniSessions.config.hooks.pre.delete` and
---     `MiniSessions.config.hooks.post.delete`).
MiniSessions.delete = function(session_name, opts)
  if H.is_disabled() then return end
  if vim.tbl_count(MiniSessions.detected) == 0 then
    H.error('There are no detected sessions. Change configuration and rerun `MiniSessions.setup()`.')
  end

  opts = vim.tbl_deep_extend('force', H.default_opts('delete'), opts or {})

  local session_path = H.name_to_path(session_name)

  -- Make sessions up to date
  H.detect_sessions()

  -- Make sure to delete only detected session (matters for local session)
  session_name = vim.fn.fnamemodify(session_path, ':t')
  if not H.validate_detected(session_name) then return end
  session_path = MiniSessions.detected[session_name].path

  local is_current_session = session_path == H.get_this_session()
  if not opts.force and is_current_session then
    H.error([[Can't delete current session when `opts.force` is not `true`.]])
  end

  local data = MiniSessions.detected[session_name]

  -- Execute 'pre' hook
  H.possibly_execute(opts.hooks.pre, data)

  -- Delete and update detected sessions
  vim.fn.delete(session_path)
  MiniSessions.detected[session_name] = nil
  if is_current_session then vim.v.this_session = '' end

  -- Possibly notify
  if opts.verbose then H.message(('Deleted session %s'):format(session_path)) end

  -- Execute 'pre' hook
  H.possibly_execute(opts.hooks.post, data)
end

--- Select session interactively and perform action
---
--- Note: this uses |vim.ui.select()| function. For more user-friendly
--- experience, override it (for example, see |MiniPick.ui_select()|).
---
---@param action string|nil Action to perform. Should be one of "read" (default),
---   "write", or "delete".
---@param opts table|nil Options for specified action.
MiniSessions.select = function(action, opts)
  if not (type(vim.ui) == 'table' and type(vim.ui.select) == 'function') then
    H.error('`MiniSessions.select()` requires `vim.ui.select()` function.')
  end

  action = action or 'read'
  if not vim.tbl_contains({ 'read', 'write', 'delete' }, action) then
    H.error("`action` should be one of 'read', 'write', or 'delete'.")
  end

  -- Make sessions up to date
  H.detect_sessions()

  -- Ensure consistent order of items
  local detected = {}
  for _, session in pairs(MiniSessions.detected) do
    table.insert(detected, session)
  end
  local sort_fun = function(a, b)
    -- Put local session first, others - increasing alphabetically
    local a_name = a.type == 'local' and '' or a.name
    local b_name = b.type == 'local' and '' or b.name
    return a_name < b_name
  end
  table.sort(detected, sort_fun)
  local detected_names = vim.tbl_map(function(x) return x.name end, detected)

  vim.ui.select(detected_names, {
    prompt = 'Select session to ' .. action,
    format_item = function(x) return ('%s (%s)'):format(x, MiniSessions.detected[x].type) end,
  }, function(item, idx)
    if item == nil then return end
    MiniSessions[action](item, opts)
  end)
end

--- Get name of latest detected session
---
--- Latest session is the session with the latest modification time determined
--- by |getftime()|.
---
---@return string|nil Name of latest session or `nil` if there is no sessions.
MiniSessions.get_latest = function()
  if vim.tbl_count(MiniSessions.detected) == 0 then return end

  local latest_time, latest_name = -1, nil
  for name, data in pairs(MiniSessions.detected) do
    if data.modify_time > latest_time then
      latest_time, latest_name = data.modify_time, name
    end
  end

  return latest_name
end

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniSessions.config)

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  H.check_type('autoread', config.autoread, 'boolean')
  H.check_type('autowrite', config.autowrite, 'boolean')
  H.check_type('directory', config.directory, 'string')
  H.check_type('file', config.file, 'string')

  H.check_type('force', config.force, 'table')
  H.check_type('force.read', config.force.read, 'boolean')
  H.check_type('force.write', config.force.write, 'boolean')
  H.check_type('force.delete', config.force.delete, 'boolean')

  H.check_type('hooks', config.hooks, 'table')
  H.check_type('hooks.pre', config.hooks.pre, 'table')
  H.check_type('hooks.pre.read', config.hooks.pre.read, 'function', true)
  H.check_type('hooks.pre.write', config.hooks.pre.write, 'function', true)
  H.check_type('hooks.pre.delete', config.hooks.pre.delete, 'function', true)
  H.check_type('hooks.post', config.hooks.post, 'table')
  H.check_type('hooks.post.read', config.hooks.post.read, 'function', true)
  H.check_type('hooks.post.write', config.hooks.post.write, 'function', true)
  H.check_type('hooks.post.delete', config.hooks.post.delete, 'function', true)

  H.check_type('verbose', config.verbose, 'table')
  H.check_type('verbose.read', config.verbose.read, 'boolean')
  H.check_type('verbose.write', config.verbose.write, 'boolean')
  H.check_type('verbose.delete', config.verbose.delete, 'boolean')

  return config
end

H.apply_config = function(config)
  MiniSessions.config = config

  H.detect_sessions(config)
end

H.create_autocommands = function(config)
  local gr = vim.api.nvim_create_augroup('MiniSessions', {})

  if config.autoread then
    local autoread = function()
      if not H.is_something_shown() then MiniSessions.read() end
    end
    local opts = { group = gr, nested = true, once = true, callback = autoread, desc = 'Autoread latest session' }
    vim.api.nvim_create_autocmd('VimEnter', opts)
  end

  if config.autowrite then
    local autowrite = function()
      if H.get_this_session() ~= '' then MiniSessions.write(nil, { force = true }) end
    end
    local opts = { group = gr, callback = autowrite, desc = 'Autowrite current session' }
    vim.api.nvim_create_autocmd('VimLeavePre', opts)
  end
end

H.is_disabled = function() return vim.g.minisessions_disable == true or vim.b.minisessions_disable == true end

H.get_config = function(config)
  return vim.tbl_deep_extend('force', MiniSessions.config, vim.b.minisessions_config or {}, config or {})
end

-- Work with sessions ---------------------------------------------------------
H.detect_sessions = function(config)
  config = H.get_config(config)

  local res_global = config.directory == '' and {} or H.detect_sessions_global(config.directory)
  local res_local = config.file == '' and {} or H.detect_sessions_local(config.file)

  -- If there are both local and global session with same name, prefer local
  MiniSessions.detected = vim.tbl_deep_extend('force', res_global, res_local)
end

H.detect_sessions_global = function(global_dir)
  -- Ensure correct directory path: create if doesn't exist
  global_dir = H.full_path(global_dir)
  if vim.fn.isdirectory(global_dir) ~= 1 then
    local ok, _ = pcall(vim.fn.mkdir, global_dir, 'p')

    if not ok then
      H.message(('%s is not a directory path.'):format(vim.inspect(global_dir)))
      return {}
    end
  end

  -- Find global sessions
  local res = {}
  for name in vim.fs.dir(global_dir) do
    local f = global_dir .. '/' .. name
    if H.is_readable_file(f) then
      local s = H.new_session(f, 'global')
      res[s.name] = s
    end
  end
  return res
end

H.detect_sessions_local = function(local_file)
  local f = vim.fn.getcwd() .. '/' .. local_file
  if not H.is_readable_file(f) then return {} end

  local s = H.new_session(f, 'local')
  return { [s.name] = s }
end

H.new_session = function(session_path, session_type)
  return {
    modify_time = vim.fn.getftime(session_path),
    name = vim.fn.fnamemodify(session_path, ':t'),
    path = H.full_path(session_path),
    type = session_type or H.get_session_type(session_path),
  }
end

H.get_session_type = function(session_path)
  if MiniSessions.config.directory == '' then return 'local' end

  local session_dir = H.full_path(session_path)
  local global_dir = H.full_path(MiniSessions.config.directory)
  return session_dir == global_dir and 'global' or 'local'
end

H.validate_detected = function(session_name)
  local is_detected = vim.tbl_contains(vim.tbl_keys(MiniSessions.detected), session_name)
  if is_detected then return true end

  H.error(('%s is not a name for detected session.'):format(vim.inspect(session_name)))
end

H.get_unsaved_listed_buffers = function()
  return vim.tbl_filter(
    function(buf_id) return vim.bo[buf_id].modified and vim.bo[buf_id].buflisted end,
    vim.api.nvim_list_bufs()
  )
end

H.get_this_session = function() return vim.fs.normalize(vim.v.this_session) end

H.name_to_path = function(session_name)
  if session_name == nil then
    local this_session = H.get_this_session()
    if this_session == '' then H.error('There is no active session. Supply non-nil session name.') end
    return this_session
  end

  session_name = tostring(session_name)
  if session_name == '' then H.error('Supply non-empty session name.') end

  local session_dir = (session_name == MiniSessions.config.file) and vim.fn.getcwd() or MiniSessions.config.directory
  return H.full_path(session_dir .. '/' .. session_name)
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.sessions) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.echo = function(msg, is_important)
  -- Construct message chunks
  msg = type(msg) == 'string' and { { msg } } or msg
  table.insert(msg, 1, { '(mini.sessions) ', 'WarningMsg' })

  -- Avoid hit-enter-prompt
  local max_width = vim.o.columns * math.max(vim.o.cmdheight - 1, 0) + vim.v.echospace
  local chunks, tot_width = {}, 0
  for _, ch in ipairs(msg) do
    local new_ch = { vim.fn.strcharpart(ch[1], 0, max_width - tot_width), ch[2] }
    table.insert(chunks, new_ch)
    tot_width = tot_width + vim.fn.strdisplaywidth(new_ch[1])
    if tot_width >= max_width then break end
  end

  -- Echo. Force redraw to ensure that it is effective (`:h echo-redraw`)
  vim.cmd([[echo '' | redraw]])
  vim.api.nvim_echo(chunks, is_important, {})
end

H.message = function(msg) H.echo(msg, true) end

H.default_opts = function(action)
  local config = MiniSessions.config
  return {
    force = config.force[action],
    verbose = config.verbose[action],
    hooks = { pre = config.hooks.pre[action], post = config.hooks.post[action] },
  }
end

H.is_readable_file = function(path) return vim.fn.isdirectory(path) ~= 1 and vim.fn.getfperm(path):sub(1, 1) == 'r' end

H.full_path = function(path) return vim.fs.normalize(vim.fn.resolve(vim.fn.fnamemodify(path, ':p'))) end

H.is_something_shown = function()
  -- Don't autoread session if Neovim is opened to show something. That is
  -- when at least one of the following is true:
  -- - There are files in arguments (like `nvim foo.txt` with new file).
  if vim.fn.argc() > 0 then return true end

  -- - Several buffers are listed (like session with placeholder buffers). That
  --   means unlisted buffers (like from `nvim-tree`) don't affect decision.
  local listed_buffers = vim.tbl_filter(
    function(buf_id) return vim.fn.buflisted(buf_id) == 1 end,
    vim.api.nvim_list_bufs()
  )
  if #listed_buffers > 1 then return true end

  -- - Current buffer is meant to show something else
  if vim.bo.filetype ~= '' then return true end

  -- - Current buffer has any lines (something opened explicitly).
  -- NOTE: Usage of `line2byte(line('$') + 1) < 0` seemed to be fine, but it
  -- doesn't work if some automated changed was made to buffer while leaving it
  -- empty (returns 2 instead of -1). This was also the reason of not being
  -- able to test with child Neovim process from 'tests/helpers'.
  local n_lines = vim.api.nvim_buf_line_count(0)
  if n_lines > 1 then return true end
  local first_line = vim.api.nvim_buf_get_lines(0, 0, 1, true)[1]
  if string.len(first_line) > 0 then return true end

  return false
end

H.possibly_execute = function(f, ...)
  if f == nil then return end
  return f(...)
end

return MiniSessions
