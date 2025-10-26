--- *mini.deps* Plugin manager
---
--- MIT License Copyright (c) 2024 Evgeni Chasnovski

--- Features:
---
--- - Manage plugins utilizing Git and built-in |packages| with these actions:
---     - Add plugin to current session, download if absent. See |MiniDeps.add()|.
---     - Update with/without confirm, with/without parallel download of new data.
---       See |MiniDeps.update()|.
---     - Delete unused plugins with/without confirm. See |MiniDeps.clean()|.
---     - Get / set / save / load snapshot. See `MiniDeps.snap_*()` functions.
---
---     All main actions are available both as Lua functions and user commands
---     (see |MiniDeps-commands|).
---
--- - Minimal yet flexible plugin |MiniDeps-plugin-specification|:
---     - Plugin source.
---     - Name of target plugin directory.
---     - Checkout target: branch, commit, tag, etc.
---     - Monitor branch to track updates without checking out.
---     - Dependencies to be set up prior to the target plugin.
---     - Hooks to call before/after plugin is created/changed.
---
--- - Helpers implementing two-stage startup: |MiniDeps.now()| and |MiniDeps.later()|.
---   See |MiniDeps-overview| for how to implement basic lazy loading with them.
---
--- What it doesn't do:
---
--- - Manage plugins which are developed without Git. The suggested approach is
---   to create a separate package (see |packages|).
---
--- - Provide ways to completely remove or update plugin's functionality in
---   current session. Although this is partially doable, it can not be done
---   in full (yet) because plugins can have untraceable side effects
---   (autocmmands, mappings, etc.).
---   The suggested approach is to restart Nvim.
---
--- Sources with more details:
--- - |MiniDeps-overview|
--- - |MiniDeps-plugin-specification|
--- - |MiniDeps-commands|
---
--- # Dependencies ~
---
--- For most of its functionality this plugin relies on `git` CLI tool.
--- See https://git-scm.com/ for more information about how to install it.
--- Actual knowledge of Git is not required but helpful.
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.deps').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `MiniDeps`
--- which you can use for scripting or manually (with `:lua MiniDeps.*`).
---
--- See |MiniDeps.config| for `config` structure and default values.
---
--- You can override runtime config settings locally to buffer inside
--- `vim.b.minideps_config` which should have same structure as
--- `MiniDeps.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- # Comparisons ~
---
--- - [folke/lazy.nvim](https://github.com/folke/lazy.nvim):
---     - More feature-rich and complex.
---     - Uses table specification with dedicated functions to add plugins,
---       while this module uses direct function call approach
---       (calling |MiniDeps.add()| ensures that plugin is usable).
---     - Uses version tags by default, while this module is more designed towards
---       tracking branches. Using tags is possible too (see |MiniDeps-overview|).
---
--- - [savq/paq-nvim](https://github.com/savq/paq-nvim):
---     - Overall less feature-rich than this module (by design).
---     - Uses array of plugin specifications inside `setup()` call to define which
---       plugins should be installed. Requires separate `:PaqInstall` call to
---       actually install them. This module ensures installation on first load.
---
--- - [junegunn/vim-plug](https://github.com/junegunn/vim-plug):
---     - Written in Vimscript, while this module is in Lua.
---     - Similar approach to defining and installing plugins as 'savq/paq-nvim'.
---     - Has basic lazy-loading built-in, while this module does not (by design).
---
--- # Highlight groups ~
---
--- Highlight groups are used inside confirmation buffers after
--- default |MiniDeps.update()| and |MiniDeps.clean()|.
---
--- - `MiniDepsChangeAdded`   - added change (commit) during update.
--- - `MiniDepsChangeRemoved` - removed change (commit) during update.
--- - `MiniDepsHint`          - various hints.
--- - `MiniDepsInfo`          - various information.
--- - `MiniDepsMsgBreaking`   - message for (conventional commit) breaking change.
--- - `MiniDepsPlaceholder`   - placeholder when there is no valuable information.
--- - `MiniDepsTitle`         - various titles.
--- - `MiniDepsTitleError`    - title when plugin had errors during update.
--- - `MiniDepsTitleSame`     - title when plugin has no changes to update.
--- - `MiniDepsTitleUpdate`   - title when plugin has changes to update.
---
--- To change any highlight group, set it directly with |nvim_set_hl()|.
---@tag MiniDeps

--- # Directory structure ~
---
--- This module uses built-in |packages| to make plugins usable in current session.
--- It works with "pack/deps" package inside `config.path.package` directory.
---
--- By default "opt" subdirectory is used to install optional plugins which are
--- loaded on demand with |MiniDeps.add()|.
--- Non-optional plugins in "start" subdirectory are supported but only if moved
--- there manually after initial install. Use it if you know what you are doing.
---
--- # Add plugin ~
---
--- Use |MiniDeps.add()| to add plugin to current session. Supply plugin's URL
--- source as a string or |MiniDeps-plugin-specification| in general. If plugin is
--- not present in "pack/deps" package, it will be created (a.k.a. installed)
--- before processing anything else.
---
--- The recommended way of adding a plugin is by calling |MiniDeps.add()| in the
--- |init.lua| file (make sure |MiniDeps.setup()| is called prior): >lua
---
---   local add = MiniDeps.add
---
---   -- Add to current session (install if absent)
---   add({
---     source = 'neovim/nvim-lspconfig',
---     -- Supply dependencies near target plugin
---     depends = { 'williamboman/mason.nvim' },
---   })
---
---   add({
---     source = 'nvim-treesitter/nvim-treesitter',
---     -- Use 'master' while monitoring updates in 'main'
---     checkout = 'master',
---     monitor = 'main',
---     -- Perform action after every checkout
---     hooks = { post_checkout = function() vim.cmd('TSUpdate') end },
---   })
---   -- Possible to immediately execute code which depends on the added plugin
---   require('nvim-treesitter.configs').setup({
---     ensure_installed = { 'lua', 'vimdoc' },
---     highlight = { enable = true },
---   })
--- <
--- NOTE:
--- - To increase performance, `add()` only ensures presence on disk and
---   nothing else. In particular, it doesn't ensure `opts.checkout` state.
---   Update or modify plugin state explicitly (see later sections).
---
--- # Lazy loading ~
---
--- Any lazy-loading is assumed to be done manually by calling |MiniDeps.add()|
--- at appropriate time. This module provides helpers implementing special safe
--- two-stage loading:
--- - |MiniDeps.now()| safely executes code immediately. Use it to load plugins
---   with UI necessary to make initial screen draw.
--- - |MiniDeps.later()| schedules code to be safely executed later, preserving
---   order. Use it (with caution) for everything else which doesn't need
---   precisely timed effect, as it will be executed some time soon on one of
---   the next event loops. >lua
---
---   local now, later = MiniDeps.now, MiniDeps.later
---
---   -- Safely execute immediately
---   now(function() vim.cmd('colorscheme miniwinter') end)
---   now(function() require('mini.statusline').setup() end)
---
---   -- Safely execute later
---   later(function() require('mini.pick').setup() end)
--- <
--- # Update ~
---
--- To update plugins from current session with new data from their sources,
--- use |:DepsUpdate|. This will download updates (utilizing multiple cores) and
--- show confirmation buffer. Follow instructions at its top to finish an update.
---
--- NOTE: This updates plugins on disk which most likely won't affect current
--- session. Restart Nvim to have them properly loaded.
---
--- # Modify ~
---
--- To change plugin's specification (like set different `checkout`, etc.):
--- - Update corresponding |MiniDeps.add()| call.
--- - Run `:DepsUpdateOffline <plugin_name>`.
--- - Review changes and confirm.
--- - Restart Nvim.
---
--- NOTE: if `add()` prior used a single source string, make sure to convert
--- its argument to `{ source = '<previous_argument>', checkout = '<state>'}`
---
--- # Snapshots ~
---
--- Use |:DepsSnapSave| to save state of all plugins from current session into
--- a snapshot file (see `config.path.snapshot`).
---
--- Use |:DepsSnapLoad| to load snapshot. This will change (without confirmation)
--- state on disk. Plugins present in both snapshot file and current session
--- will be affected. Restart Nvim to see the effect.
---
--- NOTE: loading snapshot does not change plugin's specification defined inside
--- |MiniDeps.add()| call. This means that next update might change plugin's state.
--- To make it permanent, freeze plugin in target state manually.
---
--- # Freeze ~
---
--- Modify plugin's specification to have `checkout` pointing to a static
--- target: tag, state (commit hash), or 'HEAD' (to freeze in current state).
---
--- Frozen plugins will not receive updates. You can monitor any new changes from
--- its source by "subscribing" to `monitor` branch which will be shown inside
--- confirmation buffer after |:DepsUpdate|.
---
--- Example: use `checkout = 'v0.10.0'` to freeze plugin at tag "v0.10.0" while
--- monitoring new versions in the log from `monitor` (usually default) branch.
---
--- # Rollback ~
---
--- To roll back after an unfortunate update:
--- - Get identifier of latest working state:
---     - Use |:DepsShowLog| to see update log, look for plugin's name, and copy
---       identifier listed as "State before:".
---     - See previously saved snapshot file for plugin's name and copy
---       identifier next to it.
--- - Freeze plugin at that state while monitoring appropriate branch.
---   Revert to previous shape of |MiniDeps.add()| call to resume updating.
---
--- # Remove ~
---
--- - Make sure that target plugin is not registered in current session.
---   Usually it means removing corresponding |MiniDeps.add()| call.
--- - Run |:DepsClean|. This will show confirmation buffer with a list of plugins to
---   be deleted from disk. Follow instructions at its top to finish cleaning.
---
--- Alternatively, manually delete plugin's directory from "pack/deps" package.
---@tag MiniDeps-overview

--- Each plugin dependency is managed based on its specification (a.k.a. "spec").
--- See |MiniDeps-overview| for some examples.
---
--- Specification can be a single string which is inferred as:
--- - Plugin <name> if it doesn't contain "/".
--- - Plugin <source> otherwise.
---
--- Primarily, specification is a table with the following fields:
---
--- - <source> `(string|nil)` - field with URI of plugin source used during creation
---   or update. Can be anything allowed by `git clone`.
---   Default: `nil` to rely on source set up during install.
---   Notes:
---     - It is required for creating plugin, but can be omitted afterwards.
---     - As the most common case, URI of the format "user/repo" (if it contains
---       valid characters) is transformed into "https://github.com/user/repo".
---
--- - <name> `(string|nil)` - directory basename of where to put plugin source.
---   It is put in "pack/deps/opt" subdirectory of `config.path.package`.
---   Default: basename of <source> if it is present, otherwise should be
---   provided explicitly.
---
--- - <checkout> `(string|nil)` - checkout target used to set state during update.
---   Can be anything supported by `git checkout` - branch, commit, tag, etc.
---   Default: `nil` for default branch (usually "main" or "master").
---
--- - <monitor> `(string|nil)` - monitor branch used to track new changes from
---   different target than `checkout`. Should be a name of present Git branch.
---   Default: `nil` for default branch (usually "main" or "master").
---
--- - <depends> `(table|nil)` - array of plugin specifications (strings or tables)
---   to be added prior to the target.
---   Default: `nil` for no dependencies.
---
--- - <hooks> `(table|nil)` - table with callable hooks to call on certain events.
---   Possible hook names:
---     - <pre_install>   - before creating plugin directory.
---     - <post_install>  - after  creating plugin directory (before |:packadd|).
---     - <pre_checkout>  - before making change in existing plugin.
---     - <post_checkout> - after  making change in existing plugin.
---   Each hook is executed with the following table as an argument:
---     - <path> (`string`)   - absolute path to plugin's directory
---       (might not yet exist on disk).
---     - <source> (`string`) - resolved <source> from spec.
---     - <name> (`string`)   - resolved <name> from spec.
---   Default: `nil` for no hooks.
---@tag MiniDeps-plugin-specification

--- Note: Most commands have a Lua function alternative which they rely on.
--- Like |:DepsAdd| uses |MiniDeps.add()|, etc.
---
--- # :DepsAdd ~
---
--- *:DepsAdd* with `user/repo` argument makes plugin https://github.com/user/repo
--- available in the current session (also creates it, if it is not present).
--- `:DepsAdd name` adds already installed plugin `name` to current session.
--- Accepts only single string compatible with |MiniDeps-plugin-specification|.
--- To add plugin in every session, put |MiniDeps.add()| in |init.lua|.
---
--- # :DepsUpdate ~
---
--- *:DepsUpdate* synchronizes plugins with their session specifications and
--- updates them with new changes from sources. It shows confirmation buffer in
--- a separate |tabpage| with information about an upcoming update to review
--- and (selectively) apply. See |MiniDeps.update()| for more info.
---
--- `:DepsUpdate name` updates plugin `name`. Any number of names is allowed.
---
--- `:DepsUpdate!` and `:DepsUpdate! name` update without confirmation.
--- You can see what was done in the log file afterwards (|:DepsShowLog|).
---
--- # :DepsUpdateOffline ~
---
--- *:DepsUpdateOffline* is same as |:DepsUpdate| but doesn't download new updates
--- from sources. Useful to only synchronize plugin specification in code and
--- on disk without unnecessary downloads.
---
--- # :DepsShowLog ~
---
--- *:DepsShowLog* opens log file to review.
---
--- # :DepsClean ~
---
--- *:DepsClean* deletes plugins from disk not added to current session. It shows
--- confirmation buffer in a separate |tabpage| with information about an upcoming
--- deletes to review and (selectively) apply. See |MiniDeps.clean()| for more info.
---
--- `:DepsClean!` deletes plugins without confirmation.
---
--- # :DepsSnapSave ~
---
--- *:DepsSnapSave* creates snapshot file in default location (see |MiniDeps.config|).
--- `:DepsSnapSave path` creates snapshot file at `path`.
---
--- # :DepsSnapLoad ~
---
--- *:DepsSnapLoad* loads snapshot file from default location (see |MiniDeps.config|).
--- `:DepsSnapLoad path` loads snapshot file at `path`.
---@tag MiniDeps-commands

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local
---@diagnostic disable:cast-local-type
---@diagnostic disable:undefined-doc-name
---@diagnostic disable:luadoc-miss-type-name

-- Module definition ==========================================================
local MiniDeps = {}
local H = {}

--- Module setup
---
--- Calling this function creates user commands described in |MiniDeps-commands|.
---
---@param config table|nil Module config table. See |MiniDeps.config|.
---
---@usage >lua
---   require('mini.deps').setup() -- use default config
---   -- OR
---   require('mini.deps').setup({}) -- replace {} with your config table
--- <
MiniDeps.setup = function(config)
  -- Export module
  _G.MiniDeps = MiniDeps

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Define behavior
  H.create_autocommands()

  -- Create default highlighting
  H.create_default_hl()

  -- Create user commands
  H.create_user_commands()
end

--stylua: ignore
--- Defaults ~
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text # Job ~
---
--- `config.job` defines how CLI jobs are run.
---
--- `job.n_threads` is a maximum number of parallel jobs used when needed.
--- Default: 80% of all available.
---
--- `job.timeout` is a duration (in ms) from job start until it is forced to stop.
--- Default: 30000.
---
--- # Paths ~
---
--- `config.path` defines main paths used in this module.
---
--- `path.package` is a string with path inside which "pack/deps" package is stored
--- (see |MiniDeps-overview|).
--- Default: "site" subdirectory of "data" standard path (see |stdpath()|).
---
--- `path.snapshot` is a string with default path for snapshot.
--- See |:DepsSnapSave| and |:DepsSnapLoad|.
--- Default: "mini-deps-snap" file in "config" standard path (see |stdpath()|).
---
--- `path.log` is a string with path containing log of operations done by module.
--- In particular, it contains all changes done after making an update.
--- Default: "mini-deps.log" file in "log" standard path (see |stdpath()|).
---
--- # Silent ~
---
--- `config.silent` is a boolean controlling whether to suppress non-error feedback.
--- Default: `false`.
MiniDeps.config = {
  -- Parameters of CLI jobs
  job = {
    -- Number of parallel threads to use. Default: 80% of all available.
    n_threads = nil,

    -- Timeout (in ms) for each job before force quit
    timeout = 30000,
  },

  -- Paths describing where to store data
  path = {
    -- Directory for built-in package.
    -- All plugins are actually stored in 'pack/deps' subdirectory.
    package = vim.fn.stdpath('data') .. '/site',

    -- Default file path for a snapshot
    snapshot = vim.fn.stdpath('config') .. '/mini-deps-snap',

    -- Log file
    --minidoc_replace_start log = vim.fn.stdpath('log') .. '/mini-deps.log'
    log = vim.fn.stdpath('log') .. '/mini-deps.log',
    --minidoc_replace_end
  },

  -- Whether to disable showing non-error feedback
  silent = false,
}
--minidoc_afterlines_end

--- Add plugin to current session
---
--- - Process specification by expanding dependencies into single spec array.
--- - Ensure plugin is present on disk along with its dependencies by installing
---   (in parallel) absent ones:
---     - Execute `opts.hooks.pre_install`.
---     - Use `git clone` to clone plugin from its source URI into "pack/deps/opt".
---     - Set state according to `opts.checkout`.
---     - Execute `opts.hooks.post_install`.
--- - Register spec(s) in current session.
--- - Make sure plugin(s) can be used in current session (see |:packadd|).
--- - If not during startup and is needed, source all "after/plugin/" scripts.
---
--- Notes:
--- - Presence of plugin is checked by its name which is the same as the name
---   of its directory inside "pack/deps" package (see |MiniDeps-overview|).
--- - To increase performance, this function only ensures presence on disk and
---   nothing else. In particular, it doesn't ensure `opts.checkout` state.
---   Use |MiniDeps.update()| or |:DepsUpdateOffline| explicitly.
--- - Adding plugin several times updates its session specs.
---
---@param spec table|string Plugin specification. See |MiniDeps-plugin-specification|.
---@param opts table|nil Options. Possible fields:
---   - <bang> `(boolean)` - whether to use `:packadd!` instead of plain |:packadd|.
MiniDeps.add = function(spec, opts)
  opts = opts or {}
  if type(opts) ~= 'table' then H.error('`opts` should be table.') end
  if opts.source or opts.name or opts.checkout then H.error('`add()` accepts only single spec.') end

  -- Normalize
  local plugs = {}
  H.expand_spec(plugs, spec)

  -- Process
  local plugs_to_install = {}
  for i, p in ipairs(plugs) do
    local path, is_present = H.get_plugin_path(p.name)
    p.path = path
    if not is_present then table.insert(plugs_to_install, vim.deepcopy(p)) end
  end

  -- Install
  if #plugs_to_install > 0 then
    H.ensure_git_exec()
    for _, p in ipairs(plugs_to_install) do
      p.job = H.cli_new_job({}, vim.fn.getcwd())
    end

    H.notify(string.format('Installing `%s`', plugs[#plugs].name))
    H.plugs_exec_hooks(plugs_to_install, 'pre_install')
    H.plugs_install(plugs_to_install)
    H.plugs_exec_hooks(plugs_to_install, 'post_install')
  end

  -- Add plugins to current session
  local cmd = 'packadd' .. (opts.bang and '!' or '') .. ' '
  for _, p in ipairs(plugs) do
    -- Register in 'mini.deps' session
    table.insert(H.session, p)

    -- Add to 'runtimepath'
    vim.cmd(cmd .. p.name)
  end

  -- Execute 'after/' scripts if not during startup (when they will be sourced
  -- automatically), as `:packadd` only sources plain 'plugin/' files.
  -- See https://github.com/vim/vim/issues/1994.
  -- Deliberately do so after executing all currently known 'plugin/' files.
  local should_load_after_dir = vim.v.vim_did_enter == 1 and not opts.bang and vim.o.loadplugins
  if not should_load_after_dir then return end
  for _, p in ipairs(plugs) do
    -- NOTE: This sources first lua and then vim, not how it is done during
    -- startup (`:h loadplugins`) for speed (one `glob()` instead of two).
    local after_paths = vim.fn.glob(p.path .. '/after/plugin/**/*.{vim,lua}', false, true)
    vim.tbl_map(H.source, after_paths)
  end
end

--- Update plugins
---
--- - Synchronize specs with state of plugins on disk (set `source`, etc.).
--- - Infer data before downloading updates.
--- - If not offline, download updates (in parallel).
--- - Infer data after downloading updates.
--- - If update is forced, apply all changes immediately while updating log
---   file (at `config.path.log`; use |:DepsShowLog| to review).
---   Otherwise show confirmation buffer with instructions on how to proceed.
---
---@param names table|nil Array of plugin names to update.
---  Default: all plugins from current session (see |MiniDeps.get_session()|).
---@param opts table|nil Options. Possible fields:
---   - <force> `(boolean)` - whether to force update without confirmation.
---     Default: `false`.
---   - <offline> `(boolean)` - whether to skip downloading updates from sources.
---     Default: `false`.
MiniDeps.update = function(names, opts)
  opts = vim.tbl_deep_extend('force', { force = false, offline = false }, opts or {})

  -- Compute array of plugin data to be reused in update. Each contains a CLI
  -- job "assigned" to plugin's path which stops execution after first error.
  local plugs = H.plugs_from_names(names)
  if #plugs == 0 then return H.notify('Nothing to update') end

  -- Prepare repositories and specifications
  H.ensure_git_exec()
  H.plugs_ensure_origin_source(plugs)

  -- Preprocess before downloading
  H.plugs_infer_head(plugs)
  H.plugs_ensure_target_refs(plugs)
  H.plugs_infer_commit(plugs, 'monitor', 'monitor_from')

  -- Download data if asked
  if not opts.offline then H.plugs_download_updates(plugs) end

  -- Process data for update
  H.plugs_infer_commit(plugs, 'checkout', 'checkout_to')
  H.plugs_infer_commit(plugs, 'monitor', 'monitor_to')
  H.plugs_infer_log(plugs, 'head', 'checkout_to', 'checkout_log')
  H.plugs_infer_log(plugs, 'monitor_from', 'monitor_to', 'monitor_log')

  -- Checkout if asked (before feedback to include possible checkout errors)
  if opts.force then H.plugs_checkout(plugs) end

  -- Make feedback
  local lines = H.update_compute_feedback_lines(plugs)
  local feedback = opts.force and H.update_feedback_log or H.update_feedback_confirm
  feedback(lines)

  -- Show job warnings and errors
  H.plugs_show_job_notifications(plugs, 'update')
end

--- Clean plugins
---
--- - Compute absent plugins: not registered in current session
---   (see |MiniDeps.get_session()|) but present on disk in dedicated "pack/deps"
---   package (inside `config.path.package`).
--- - If cleaning is forced, delete all absent plugins from disk.
---   Otherwise show confirmation buffer with instructions on how to proceed.
---
---@param opts table|nil Options. Possible fields:
---   - <force> `(boolean)` - whether to force delete without confirmation.
---     Default: `false`.
MiniDeps.clean = function(opts)
  opts = vim.tbl_deep_extend('force', { force = false }, opts or {})

  -- Compute path candidates to delete
  local is_in_session = {}
  for _, s in ipairs(MiniDeps.get_session()) do
    is_in_session[s.path] = true
  end

  local is_absent_plugin = function(x) return vim.fn.isdirectory(x) == 1 and not is_in_session[x] end
  local absent_paths = vim.tbl_filter(is_absent_plugin, H.get_all_plugin_paths())

  -- Clean
  if #absent_paths == 0 then return H.notify('Nothing to clean') end
  local clean_fun = opts.force and H.clean_delete or H.clean_confirm
  clean_fun(absent_paths)
end

--- Compute snapshot
---
---@return table A snapshot table: plugin names as keys and state as values.
---   All plugins in current session are processed.
MiniDeps.snap_get = function()
  local plugs = H.plugs_from_names()
  H.ensure_git_exec()
  H.plugs_infer_head(plugs)
  H.plugs_show_job_notifications(plugs, 'computing snapshot')

  local snap = {}
  for _, p in ipairs(plugs) do
    if p.head ~= '' then snap[p.name] = p.head end
  end
  return snap
end

--- Apply snapshot
---
--- Notes:
--- - Checking out states from snapshot does not update session plugin spec
---   (`checkout` field in particular). Among others, it means that next call
---   to |MiniDeps.update()| might override the result of this function.
---   To make changes permanent, set `checkout` spec field to state from snapshot.
---
---@param snap table A snapshot table: plugin names as keys and state as values.
---   Only plugins in current session are processed.
MiniDeps.snap_set = function(snap)
  if type(snap) ~= 'table' then H.error('Snapshot should be a table.') end

  -- Construct current session plugin data with `checkout` from snapshot
  for k, v in pairs(snap) do
    if not (type(k) == 'string' and type(v) == 'string') then snap[k] = nil end
  end
  local plugs = H.plugs_from_names(vim.tbl_keys(snap))
  for _, p in ipairs(plugs) do
    p.checkout = snap[p.name]
  end

  -- Checkout
  H.ensure_git_exec()
  H.plugs_checkout(plugs)
  H.plugs_show_job_notifications(plugs, 'applying snapshot')
end

--- Save snapshot
---
---@param path string|nil A valid path on disk where to write snapshot computed
---   with |MiniDeps.snap_get()|.
---   Default: `config.path.snapshot`.
MiniDeps.snap_save = function(path)
  path = path or H.full_path(H.get_config().path.snapshot)
  if type(path) ~= 'string' then H.error('`path` should be string.') end

  -- Compute snapshot
  local snap = MiniDeps.snap_get()

  -- Write snapshot
  local lines = vim.split(vim.inspect(snap), '\n')
  lines[1] = 'return ' .. lines[1]
  vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
  vim.fn.writefile(lines, path)

  H.notify('Created snapshot at ' .. vim.inspect(path))
end

--- Load snapshot file
---
--- Notes from |MiniDeps.snap_set()| also apply here.
---
---@param path string|nil A valid path on disk from where to read snapshot.
---   Default: `config.path.snapshot`.
MiniDeps.snap_load = function(path)
  path = path or H.full_path(H.get_config().path.snapshot)
  if vim.fn.filereadable(path) ~= 1 then H.error('`path` should be path to a readable file.') end

  local ok, snap = pcall(dofile, H.full_path(path))
  if not (ok and type(snap) == 'table') then H.error('`path` is not a path to proper snapshot.') end

  MiniDeps.snap_set(snap)
end

--- Get session
---
--- Plugin is registered in current session if it either:
--- - Was added with |MiniDeps.add()| (preserving order of calls).
--- - Is a "start" plugin and present in 'runtimpath'.
---
---@return table Array with specifications of all plugins registered in
---   current session.
MiniDeps.get_session = function()
  -- Normalize `H.session` allowing specs for same plugin
  local res, plugin_ids = {}, {}
  local add_spec = function(spec)
    local id = plugin_ids[spec.path] or (#res + 1)
    -- Treat `depends` differently as it is an array and direct merge is bad
    -- Also: https://github.com/neovim/neovim/pull/15094#discussion_r671663938
    local depends = vim.deepcopy((res[id] or {}).depends or {})
    vim.list_extend(depends, spec.depends or {})
    res[id] = vim.tbl_deep_extend('force', res[id] or {}, spec)
    res[id].depends = depends

    plugin_ids[spec.path] = id
  end
  vim.tbl_map(add_spec, H.session)
  H.session = res

  -- Add 'start/' plugins that are in 'rtp'. NOTE: not whole session concept is
  -- built around presence in 'rtp' to 100% ensure to preserve the order in
  -- which user called `add()`.
  local start_path = H.full_path(H.get_package_path() .. '/pack/deps/start')
  local pattern = string.format('^%s/([^/]+)$', vim.pesc(start_path))
  for _, runtime_path in ipairs(vim.api.nvim_list_runtime_paths()) do
    -- Make sure plugin path is normalized (matters on Windows)
    local path = H.full_path(runtime_path)
    local name = string.match(path, pattern)
    if name ~= nil then add_spec({ path = path, name = name, hooks = {}, depends = {} }) end
  end

  -- Return copy to not allow modification in place
  return vim.deepcopy(res)
end

--- Execute function now
---
--- Safely execute function immediately. Errors are shown with |vim.notify()|
--- later, after all queued functions (including with |MiniDeps.later()|)
--- are executed, thus not blocking execution of next code in file.
---
--- Assumed to be used as a first step during two-stage config execution to
--- load plugins immediately during startup. See |MiniDeps-overview|.
---
---@param f function Callable to execute.
MiniDeps.now = function(f)
  local ok, err = pcall(f)
  if not ok then table.insert(H.cache.exec_errors, err) end
  H.schedule_finish()
end

--- Execute function later
---
--- Queue function to be safely executed later without blocking execution of
--- next code in file. All queued functions are guaranteed to be executed in
--- order they were added.
--- Errors are shown with |vim.notify()| after all queued functions are executed.
---
--- Assumed to be used as a second step during two-stage config execution to
--- load plugins "lazily" after startup. See |MiniDeps-overview|.
---
---@param f function Callable to execute.
MiniDeps.later = function(f)
  table.insert(H.cache.later_callback_queue, f)
  H.schedule_finish()
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniDeps.config

-- Array of plugin specs
H.session = {}

-- Various cache
H.cache = {
  -- Whether finish of `now()` or `later()` is already scheduled
  finish_is_scheduled = false,

  -- Callback queue for `later()`
  later_callback_queue = {},

  -- Errors during execution of `now()` or `later()`
  exec_errors = {},

  -- Git version
  git_version = nil,
}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  H.check_type('job', config.job, 'table')
  H.check_type('job.n_threads', config.job.n_threads, 'number', true)
  H.check_type('job.timeout', config.job.timeout, 'number')

  H.check_type('path', config.path, 'table')
  H.check_type('path.package', config.path.package, 'string')
  H.check_type('path.snapshot', config.path.snapshot, 'string')
  H.check_type('path.log', config.path.log, 'string')

  H.check_type('silent', config.silent, 'boolean')

  return config
end

H.apply_config = function(config)
  MiniDeps.config = config

  -- Reset current session to allow resourcing script with `setup()` call
  H.session = {}

  -- Add target package path to 'packpath'
  local pack_path = H.full_path(config.path.package)
  vim.cmd('set packpath^=' .. vim.fn.fnameescape(pack_path))
end

H.get_config = function(config)
  return vim.tbl_deep_extend('force', MiniDeps.config, vim.b.minideps_config or {}, config or {})
end

H.create_autocommands = function()
  local gr = vim.api.nvim_create_augroup('MiniDeps', {})
  vim.api.nvim_create_autocmd('ColorScheme', { group = gr, callback = H.create_default_hl, desc = 'Ensure colors' })
end

--stylua: ignore
H.create_default_hl = function()
  local hi = function(name, opts)
    opts.default = true
    vim.api.nvim_set_hl(0, name, opts)
  end

  local has_core_diff_hl = vim.fn.has('nvim-0.10') == 1
  hi('MiniDepsChangeAdded',   { link = has_core_diff_hl and 'Added' or 'diffAdded' })
  hi('MiniDepsChangeRemoved', { link = has_core_diff_hl and 'Removed' or 'diffRemoved' })
  hi('MiniDepsHint',          { link = 'DiagnosticHint' })
  hi('MiniDepsInfo',          { link = 'DiagnosticInfo' })
  hi('MiniDepsMsgBreaking',   { link = 'DiagnosticWarn' })
  hi('MiniDepsPlaceholder',   { link = 'Comment' })
  hi('MiniDepsTitle',         { link = 'Title' })
  hi('MiniDepsTitleError',    { link = 'DiffDelete' })
  hi('MiniDepsTitleSame',     { link = 'DiffText' })
  hi('MiniDepsTitleUpdate',   { link = 'DiffAdd' })
end

H.create_user_commands = function()
  -- Do not create commands immediately to increase startup time
  local new_cmd = vim.schedule_wrap(vim.api.nvim_create_user_command)

  local complete_session_names = function(arg, _, _)
    local session_names = vim.tbl_map(function(s) return s.name end, MiniDeps.get_session())
    return vim.tbl_filter(function(n) return vim.startswith(n, arg) end, session_names)
  end
  local complete_disk_names = function(arg, _, _)
    local disk_names = vim.tbl_map(function(p) return vim.fn.fnamemodify(p, ':t') end, H.get_all_plugin_paths())
    return vim.tbl_filter(function(n) return vim.startswith(n, arg) end, disk_names)
  end

  local add = function(input) MiniDeps.add(input.fargs[1]) end
  new_cmd('DepsAdd', add, { nargs = '+', complete = complete_disk_names, desc = 'Add plugin to session' })

  local make_update_cmd = function(name, offline, desc)
    local callback = function(input)
      local names
      if #input.fargs > 0 then names = input.fargs end
      MiniDeps.update(names, { force = input.bang, offline = offline })
    end
    local opts = { bang = true, complete = complete_session_names, nargs = '*', desc = desc }
    new_cmd(name, callback, opts)
  end
  make_update_cmd('DepsUpdate', false, 'Update plugins')
  make_update_cmd('DepsUpdateOffline', true, 'Update plugins without downloading from source')

  local show_log = function()
    H.edit(H.get_config().path.log)
    H.update_add_syntax()
    vim.cmd([[syntax match MiniDepsTitle "^\(==========\).*\1$"]])
  end
  new_cmd('DepsShowLog', show_log, { desc = 'Show log' })

  local clean = function(input) MiniDeps.clean({ force = input.bang }) end
  new_cmd('DepsClean', clean, { bang = true, desc = 'Delete unused plugins' })

  local snap_save = function(input) MiniDeps.snap_save(input.fargs[1]) end
  new_cmd('DepsSnapSave', snap_save, { nargs = '*', complete = 'file', desc = 'Save plugin snapshot' })

  local snap_load = function(input) MiniDeps.snap_load(input.fargs[1]) end
  new_cmd('DepsSnapLoad', snap_load, { nargs = '*', complete = 'file', desc = 'Load plugin snapshot' })
end

-- Git commands ---------------------------------------------------------------
H.git_cmd = function(cmd_name, ...)
  local args = H.git_args[cmd_name](...)
  if args == nil then return {} end

  -- Use '-c gc.auto=0' to disable `stderr` "Auto packing..." messages
  return { 'git', '-c', 'gc.auto=0', unpack(args) }
end

--stylua: ignore
H.git_args = {
  version = function()
    return { 'version' }
  end,
  clone = function(source, path)
    local res = {
      'clone', '--quiet', '--filter=blob:none',
      '--recurse-submodules', '--also-filter-submodules', '--origin', 'origin',
      source, path,
    }
    -- Use `--also-filter-submodules` only with appropriate version
    if not (H.cache.git_version.major >= 2 and H.cache.git_version.minor >= 36) then
      table.remove(res, 5)
    end
    return res
  end,
  stash = function(timestamp)
    return { 'stash', '--quiet', '--message', '(mini.deps) ' .. timestamp .. ' Stash before checkout' }
  end,
  checkout = function(target)
    return { 'checkout', '--quiet', target }
  end,
  -- Using '--tags --force' means conflicting tags will be synced with remote
  fetch = function()
    return { 'fetch', '--quiet', '--tags', '--force', '--recurse-submodules=yes', 'origin' }
  end,
  set_origin = function(source)
    return { 'remote', 'set-url', 'origin', source }
  end,
  get_origin = function()
    return { 'remote', 'get-url', 'origin' }
  end,
  get_default_origin_branch = function()
    return { 'rev-parse', '--abbrev-ref', 'origin/HEAD' }
  end,
  is_origin_branch = function(name)
    -- Returns branch's name if it is present
    return { 'branch', '--list', '--all', '--format=%(refname:short)', 'origin/' .. name }
  end,
  -- Using `rev-list -1` shows a commit of revision, while `rev-parse` shows
  -- hash of revision. Those are different for annotated tags.
  get_hash = function(rev)
    return { 'rev-list', '-1', rev }
  end,
  log = function(from, to)
    if from == nil or to == nil or from == to then return nil end
    -- `--topo-order` makes showing divergent branches nicer
    -- `--decorate-refs` shows only tags near commits (not `origin/main`, etc.)
    --stylua: ignore
    return {
      'log', '--pretty=format:%m %h | %ai | %an%d%n  %s%n', '--topo-order', '--decorate-refs=refs/tags',
      from .. '...' .. to,
    }
  end,
}

H.ensure_git_exec = function()
  if H.cache.git_version ~= nil then return end
  local jobs = { H.cli_new_job(H.git_cmd('version'), vim.fn.getcwd()) }
  H.cli_run(jobs)
  if #jobs[1].err > 0 then H.error('Could not find executable `git` CLI tool') end
  local major, minor = string.match(H.cli_stream_tostring(jobs[1].out), '(%d+)%.(%d+)')
  H.cache.git_version = { major = tonumber(major), minor = tonumber(minor) }
end

-- Plugin specification -------------------------------------------------------
H.expand_spec = function(target, spec)
  -- Prepare
  if type(spec) == 'string' then
    local field = string.find(spec, '/') ~= nil and 'source' or 'name'
    spec = { [field] = spec }
  end
  if type(spec) ~= 'table' then H.error('Plugin spec should be table.') end

  local has_min_fields = type(spec.source) == 'string' or type(spec.name) == 'string'
  if not has_min_fields then H.error('Plugin spec should have proper `source` or `name`.') end

  -- Normalize
  spec = vim.deepcopy(spec)

  if spec.source and type(spec.source) ~= 'string' then H.error('`source` in plugin spec should be string.') end
  local is_user_repo = type(spec.source) == 'string' and spec.source:find('^[%w-]+/[%w-_.]+$') ~= nil
  if is_user_repo then spec.source = 'https://github.com/' .. spec.source end

  spec.name = spec.name or vim.fn.fnamemodify(spec.source, ':t')
  if type(spec.name) ~= 'string' then H.error('`name` in plugin spec should be string.') end
  if string.find(spec.name, '/') ~= nil then H.error('`name` in plugin spec should not contain "/".') end
  if spec.name == '' then H.error('`name` in plugin spec should not be empty.') end

  if spec.checkout and type(spec.checkout) ~= 'string' then H.error('`checkout` in plugin spec should be string.') end
  if spec.monitor and type(spec.monitor) ~= 'string' then H.error('`monitor` in plugin spec should be string.') end

  spec.hooks = vim.deepcopy(spec.hooks) or {}
  if type(spec.hooks) ~= 'table' then H.error('`hooks` in plugin spec should be table.') end
  local hook_names = { 'pre_install', 'post_install', 'pre_checkout', 'post_checkout' }
  for _, hook_name in ipairs(hook_names) do
    local is_not_hook = spec.hooks[hook_name] and not vim.is_callable(spec.hooks[hook_name])
    if is_not_hook then H.error('`hooks.' .. hook_name .. '` in plugin spec should be callable.') end
  end

  -- Expand dependencies recursively before adding current spec to target
  spec.depends = vim.deepcopy(spec.depends) or {}
  if not H.islist(spec.depends) then H.error('`depends` in plugin spec should be array.') end
  for _, dep_spec in ipairs(spec.depends) do
    H.expand_spec(target, dep_spec)
  end

  table.insert(target, spec)
end

-- Plugin operations ----------------------------------------------------------
H.plugs_exec_hooks = function(plugs, name)
  for _, p in ipairs(plugs) do
    local has_error = p.job and #p.job.err > 0
    local should_execute = vim.is_callable(p.hooks[name]) and not has_error
    if should_execute then
      local ok, err = pcall(p.hooks[name], { path = p.path, source = p.source, name = p.name })
      if not ok then
        local msg = string.format('Error executing %s hook in `%s`:\n%s', name, p.name, err)
        H.notify(msg, 'ERROR')
      end
    end
  end
end

H.plugs_install = function(plugs)
  -- Clone
  local prepare = function(p)
    if p.source == nil and #p.job.err == 0 then p.job.err = { 'SPECIFICATION HAS NO `source` TO INSTALL PLUGIN.' } end
    p.job.command = H.git_cmd('clone', p.source or '', p.path)
    p.job.exit_msg = string.format('Installed `%s`', p.name)
  end
  H.plugs_run_jobs(plugs, prepare)

  -- Checkout
  vim.tbl_map(function(p) p.job.cwd = p.path end, plugs)
  H.plugs_checkout(plugs, { exec_hooks = false, all_helptags = true })

  -- Show warnings and errors
  H.plugs_show_job_notifications(plugs, 'installing plugin')
end

H.plugs_download_updates = function(plugs)
  -- Show actual target number of plugins attempted to fetch
  local n_noerror = 0
  for _, p in ipairs(plugs) do
    if #p.job.err == 0 then n_noerror = n_noerror + 1 end
  end
  if n_noerror == 0 then return end
  H.notify('Downloading ' .. n_noerror .. ' update' .. (n_noerror > 1 and 's' or ''))

  local prepare = function(p)
    p.job.command = H.git_cmd('fetch')
    p.job.exit_msg = string.format('Downloaded update for `%s`', p.name)
  end
  H.plugs_run_jobs(plugs, prepare)
end

H.plugs_checkout = function(plugs, opts)
  opts = vim.tbl_deep_extend('force', { exec_hooks = true, all_helptags = false }, opts or {})

  H.plugs_infer_head(plugs)
  H.plugs_ensure_target_refs(plugs)
  H.plugs_infer_commit(plugs, 'checkout', 'checkout_to')

  -- Operate only on plugins that actually need checkout
  local checkout_plugs = vim.tbl_filter(function(p) return p.head ~= p.checkout_to end, plugs)

  -- Stash changes
  local stash_command = H.git_cmd('stash', H.get_timestamp())
  local prepare = function(p) p.job.command = stash_command end
  H.plugs_run_jobs(checkout_plugs, prepare)

  -- Execute pre hooks
  if opts.exec_hooks then H.plugs_exec_hooks(checkout_plugs, 'pre_checkout') end

  -- Checkout
  prepare = function(p)
    p.job.command = H.git_cmd('checkout', p.checkout_to)
    p.job.exit_msg = string.format('Checked out `%s` in `%s`', p.checkout, p.name)
  end
  H.plugs_run_jobs(checkout_plugs, prepare)

  -- Execute post hooks
  if opts.exec_hooks then H.plugs_exec_hooks(checkout_plugs, 'post_checkout') end

  -- (Re)Generate help tags according to the current help files
  local help_plugs = opts.all_helptags and plugs or checkout_plugs
  for _, p in ipairs(help_plugs) do
    local doc_dir = p.path .. '/doc'
    -- Completely redo tags
    vim.fn.delete(doc_dir .. '/tags')
    local has_help_files = vim.fn.glob(doc_dir .. '/**') ~= ''
    if has_help_files then pcall(vim.cmd, 'helptags ' .. vim.fn.fnameescape(doc_dir)) end
  end
end

-- Plugin operation helpers ---------------------------------------------------
H.plugs_from_names = function(names)
  if names and not H.islist(names) then H.error('`names` should be array.') end
  for _, name in ipairs(names or {}) do
    if type(name) ~= 'string' then H.error('`names` should contain only strings.') end
  end

  local res = {}
  for _, spec in ipairs(MiniDeps.get_session()) do
    if names == nil or vim.tbl_contains(names, spec.name) then
      spec.job = H.cli_new_job({}, spec.path)
      table.insert(res, spec)
    end
  end

  return res
end

H.plugs_run_jobs = function(plugs, prepare, process)
  if vim.is_callable(prepare) then vim.tbl_map(prepare, plugs) end

  H.cli_run(vim.tbl_map(function(p) return p.job end, plugs))

  if vim.is_callable(process) then vim.tbl_map(process, plugs) end

  -- Clean jobs. Preserve errors for jobs to be properly reusable.
  for _, p in ipairs(plugs) do
    p.job.command, p.job.exit_msg, p.job.out = {}, nil, {}
  end
end

H.plugs_show_job_notifications = function(plugs, action_name)
  for _, p in ipairs(plugs) do
    local warn = H.cli_stream_tostring(p.job.warn)
    if warn ~= '' then
      local msg = string.format('Warnings in `%s` during %s\n%s', p.name, action_name, warn)
      H.notify(msg, 'WARN')
    end
    local err = H.cli_stream_tostring(p.job.err)
    if err ~= '' then
      local msg = string.format('Error in `%s` during %s\n%s', p.name, action_name, err)
      H.notify(msg, 'ERROR')
    end
  end
end

H.plugs_ensure_origin_source = function(plugs)
  local prepare = function(p) p.job.command = p.source and H.git_cmd('set_origin', p.source) or H.git_cmd('get_origin') end
  local process = function(p) p.source = p.source or H.cli_stream_tostring(p.job.out) end
  H.plugs_run_jobs(plugs, prepare, process)
end

H.plugs_ensure_target_refs = function(plugs)
  local prepare = function(p)
    local needs_infer = p.checkout == nil or p.monitor == nil
    p.job.command = needs_infer and H.git_cmd('get_default_origin_branch') or {}
  end
  local process = function(p)
    local def_branch = H.cli_stream_tostring(p.job.out):gsub('^origin/', '')
    p.checkout = p.checkout or def_branch
    p.monitor = p.monitor or def_branch
    p.has_monitor = p.checkout ~= p.monitor
  end
  H.plugs_run_jobs(plugs, prepare, process)
end

H.plugs_infer_head = function(plugs)
  local prepare = function(p) p.job.command = p.head == nil and H.git_cmd('get_hash', 'HEAD') or {} end
  local process = function(p) p.head = p.head or H.cli_stream_tostring(p.job.out) end
  H.plugs_run_jobs(plugs, prepare, process)
end

H.plugs_infer_commit = function(plugs, field_ref, field_out)
  -- Determine if reference points to an origin branch (to avoid error later)
  local prepare = function(p)
    -- Don't recompute commit if it is already computed
    -- Don't compute commit for 'monitor' if it won't be used
    p.should_infer = p[field_out] == nil and (field_ref ~= 'monitor' or p.has_monitor)
    p.job.command = p.should_infer and H.git_cmd('is_origin_branch', p[field_ref]) or {}
  end
  local process = function(p) p.is_ref_origin_branch = H.cli_stream_tostring(p.job.out):find('%S') ~= nil end
  H.plugs_run_jobs(plugs, prepare, process)

  -- Infer commit depending on whether it points to origin branch
  prepare = function(p)
    -- Force `checkout = 'HEAD'` to always point to current commit to freeze
    -- updates. This is needed because `origin/HEAD` is also present.
    local is_from_origin = p.is_ref_origin_branch and p[field_ref] ~= 'HEAD'
    local ref = (is_from_origin and 'origin/' or '') .. p[field_ref]
    p.job.command = p.should_infer and H.git_cmd('get_hash', ref) or {}
  end
  process = function(p)
    if p.should_infer then p[field_out] = H.cli_stream_tostring(p.job.out) end
    p.is_ref_origin_branch, p.should_infer = nil, nil
  end
  H.plugs_run_jobs(plugs, prepare, process)
end

H.plugs_infer_log = function(plugs, field_from, field_to, field_out)
  local prepare = function(p) p.job.command = H.git_cmd('log', p[field_from], p[field_to]) end
  local process = function(p) p[field_out] = H.cli_stream_tostring(p.job.out) end
  H.plugs_run_jobs(plugs, prepare, process)
end

-- File system ----------------------------------------------------------------
H.get_plugin_path = function(name)
  local package_path = H.get_package_path()

  -- First check for the most common case of name present in 'pack/deps/opt'
  local opt_path = string.format('%s/pack/deps/opt/%s', package_path, name)
  if vim.uv.fs_stat(opt_path) ~= nil then return opt_path, true end

  -- Allow processing 'pack/deps/start'
  local start_path = string.format('%s/pack/deps/start/%s', package_path, name)
  if vim.uv.fs_stat(start_path) ~= nil then return start_path, true end

  -- Use 'opt' directory by default
  return opt_path, false
end

H.get_all_plugin_paths = function()
  local deps_path, res = H.get_package_path() .. '/pack/deps', {}
  vim.list_extend(res, H.readdir(deps_path .. '/opt'))
  vim.list_extend(res, H.readdir(deps_path .. '/start'))
  return res
end

H.get_package_path = function() return H.full_path(H.get_config().path.package) end

-- Clean ----------------------------------------------------------------------
H.clean_confirm = function(paths)
  -- Compute lines
  local lines = {
    'This is a confirmation report before a clean.',
    '',
    'Lines `- <plugin>` show plugins to be deleted from disk.',
    'Remove line to not delete that plugin.',
    '',
    'To finish clean, write this buffer (for example, with `:write` command).',
    'To cancel clean, close this window (for example, with `:close` command).',
    '',
  }
  local n_header = #lines - 1
  for _, p in ipairs(paths) do
    table.insert(lines, string.format('- %s (%s)', vim.fn.fnamemodify(p, ':t'), p))
  end

  -- Show report in new buffer in separate tabpage
  local finish_clean = function(buf_id)
    -- Compute plugin paths to update
    local paths_to_delete = {}
    for _, l in ipairs(vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)) do
      local cur_path = string.match(l, '^%- .* %((.*)%)$')
      if cur_path ~= nil then table.insert(paths_to_delete, cur_path) end
    end

    if #paths_to_delete == 0 then return H.notify('Nothing to delete') end
    H.clean_delete(paths_to_delete)
  end
  H.show_confirm_buf(lines, { name = 'confirm-clean', exec_on_write = finish_clean })

  -- Define basic highlighting
  vim.cmd('syntax region MiniDepsHint start="^\\%1l" end="\\%' .. n_header .. 'l$"')

  -- Define conceal to show only name with whole path when cursor is on it
  vim.cmd('syntax conceal on')
  vim.cmd([[syntax match MiniDepsInfo "\s\+(.\{-})$"]])
  vim.cmd('syntax conceal off')
  vim.cmd('setlocal conceallevel=3')
end

H.clean_delete = function(paths)
  local n_to_delete = #paths
  for i, p in ipairs(paths) do
    vim.fn.delete(p, 'rf')
    local msg = string.format('(%d/%d) Deleted `%s` from disk', i, n_to_delete, vim.fn.fnamemodify(p, ':t'))
    H.notify(msg)
  end
end

-- Update ---------------------------------------------------------------------
H.update_compute_feedback_lines = function(plugs)
  -- Construct lines with metadata for later sort
  local plug_data = {}
  for i, p in ipairs(plugs) do
    local lines = H.update_compute_report_single(p)
    --stylua: ignore
    plug_data[i] = {
      lines = lines, has_error = p.has_error, has_updates = p.has_updates, has_monitor = p.has_monitor, name = p.name, index = i
    }
  end

  -- Sort to put first ones with errors, then with updates, then rest
  local compare = function(a, b)
    if a.has_error and not b.has_error then return true end
    if not a.has_error and b.has_error then return false end
    if a.has_updates and not b.has_updates then return true end
    if not a.has_updates and b.has_updates then return false end
    if a.has_monitor and not b.has_monitor then return true end
    if not a.has_monitor and b.has_monitor then return false end
    if a.name == 'mini.nvim' then return true end
    if b.name == 'mini.nvim' then return false end
    return a.index < b.index
  end
  table.sort(plug_data, compare)

  local plug_lines = vim.tbl_map(function(x) return x.lines end, plug_data)
  return vim.split(table.concat(plug_lines, '\n\n'), '\n')
end

H.update_compute_report_single = function(p)
  p.has_error, p.has_updates = #p.job.err > 0, p.head ~= p.checkout_to

  local err = H.cli_stream_tostring(p.job.err)
  if err ~= '' then return string.format('!!! %s !!!\n\n%s', p.name, err) end

  -- Compute title surrounding based on whether plugin needs an update
  local surrounding = p.has_updates and '+++' or '---'
  local parts = { string.format('%s %s %s\n', surrounding, p.name, surrounding) }

  if p.head == p.checkout_to then
    table.insert(parts, 'Path:   ' .. p.path .. '\n')
    table.insert(parts, 'Source: ' .. (p.source or '<None>') .. '\n')
    table.insert(parts, string.format('State:  %s (%s)', p.checkout_to, p.checkout))
  else
    table.insert(parts, 'Path:         ' .. p.path .. '\n')
    table.insert(parts, 'Source:       ' .. (p.source or '<None>') .. '\n')
    table.insert(parts, 'State before: ' .. p.head .. '\n')
    table.insert(parts, string.format('State after:  %s (%s)', p.checkout_to, p.checkout))
  end

  -- Show pending updates only if they are present
  if p.has_updates then
    table.insert(parts, string.format('\n\nPending updates from `%s`:\n', p.checkout))
    table.insert(parts, p.checkout_log)
  end

  -- Show monitor updates only if user asked for them
  if p.has_monitor then
    table.insert(parts, string.format('\n\nMonitor updates from `%s`:\n', p.monitor))
    table.insert(parts, p.monitor_log ~= '' and p.monitor_log or '<Nothing>')
  end

  return table.concat(parts, '')
end

H.update_feedback_confirm = function(lines)
  -- Add helper header
  local report = {
    'This is a confirmation report before an update.',
    '',
    'Line `+++ <plugin_name> +++` means plugin will be updated.',
    'See update details below it.',
    'Changes starting with ">"/"<" will be added/removed.',
    'Remove the line to not update that plugin.',
    '',
    'Line `--- <plugin_name> ---` means plugin has nothing to update.',
    '',
    "Line `!!! <plugin_name> !!!` means plugin had an error and won't be updated.",
    'See error details below it.',
    '',
    'Use regular fold keys (`zM`, `zR`, etc.) to manage shorter view.',
    'To finish update, write this buffer (for example, with `:write` command).',
    'To cancel update, close this window (for example, with `:close` command).',
    '',
  }
  local n_header = #report - 1
  vim.list_extend(report, lines)

  -- Show report in new buffer in separate tabpage
  local finish_update = function(buf_id)
    -- Compute plugin names to update
    local names = {}
    for _, l in ipairs(vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)) do
      local cur_name = string.match(l, '^%+%+%+ (.*) %+%+%+$')
      if cur_name ~= nil then table.insert(names, cur_name) end
    end

    -- Update and delete buffer (in that order, to show that update is done)
    MiniDeps.update(names, { force = true, offline = true })
  end

  H.show_confirm_buf(report, { name = 'confirm-update', exec_on_write = finish_update, setup_folds = true })

  -- Define basic highlighting
  vim.cmd('syntax region MiniDepsHint start="^\\%1l" end="\\%' .. n_header .. 'l$"')
  H.update_add_syntax()
end

H.update_add_syntax = function()
  vim.cmd([[
    syntax match MiniDepsTitleError    "^!!! .\+ !!!$"
    syntax match MiniDepsTitleUpdate   "^+++ .\+ +++$"
    syntax match MiniDepsTitleSame     "^--- .\+ ---$"
    syntax match MiniDepsInfo          "^Path: \+\zs[^ ]\+"
    syntax match MiniDepsInfo          "^Source: \+\zs[^ ]\+"
    syntax match MiniDepsInfo          "^State[^:]*: \+\zs[^ ]\+\ze"
    syntax match MiniDepsHint          "\(^State.\+\)\@<=(.\+)$"
    syntax match MiniDepsChangeAdded   "^> .*$"
    syntax match MiniDepsChangeRemoved "^< .*$"
    syntax match MiniDepsMsgBreaking   "^  \S\+!: .*$"
    syntax match MiniDepsPlaceholder   "^<.*>$"
  ]])
end

H.update_feedback_log = function(lines)
  local title = string.format('========== Update %s ==========', H.get_timestamp())
  table.insert(lines, 1, title)
  table.insert(lines, '')

  local log_path = H.get_config().path.log
  vim.fn.mkdir(vim.fn.fnamemodify(log_path, ':h'), 'p')
  vim.fn.writefile(lines, log_path, 'a')
end

-- Confirm --------------------------------------------------------------------
H.show_confirm_buf = function(lines, opts)
  -- Show buffer
  local buf_id = vim.api.nvim_create_buf(true, true)
  H.set_buf_name(buf_id, opts.name)
  vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
  vim.cmd('tab sbuffer ' .. buf_id)
  local tab_num, win_id = vim.api.nvim_tabpage_get_number(0), vim.api.nvim_get_current_win()

  local delete_buffer = vim.schedule_wrap(function()
    pcall(vim.api.nvim_buf_delete, buf_id, { force = true })
    pcall(function() vim.cmd('tabclose ' .. tab_num) end)
    vim.cmd('redraw')
  end)

  -- Define folding
  local is_title = function(l) return l:find('^%-%-%-') or l:find('^%+%+%+') or l:find('^%!%!%!') end
  --stylua: ignore
  MiniDeps._confirm_foldexpr = function(lnum)
    if lnum == 1 then return 0 end
    if is_title(vim.fn.getline(lnum - 1)) then return 1 end
    if is_title(vim.fn.getline(lnum + 1)) then return 0 end
    return '='
  end

  -- Possibly set up folding. Use `:setlocal` for these options to not be
  -- inherited if some other buffer is opened in the same window.
  if opts.setup_folds then
    vim.cmd('setlocal foldenable foldmethod=expr foldlevel=999')
    vim.cmd('setlocal foldexpr=v:lua.MiniDeps._confirm_foldexpr(v:lnum)')
  end

  -- Define action on accepting confirm
  local finish = function()
    MiniDeps._confirm_foldexpr = nil
    opts.exec_on_write(buf_id)
    delete_buffer()
  end
  -- - Use `nested` to allow other events (`WinEnter` for 'mini.statusline')
  vim.api.nvim_create_autocmd('BufWriteCmd', { buffer = buf_id, nested = true, callback = finish })

  -- Define action to cancel confirm
  local cancel_au_id
  local on_cancel = function(data)
    MiniDeps._confirm_foldexpr = nil
    if tonumber(data.match) ~= win_id then return end
    pcall(vim.api.nvim_del_autocmd, cancel_au_id)
    delete_buffer()
  end
  cancel_au_id = vim.api.nvim_create_autocmd('WinClosed', { nested = true, callback = on_cancel })

  -- Set buffer-local options last (so that user autocmmands could override)
  vim.bo.buftype, vim.bo.filetype, vim.bo.modified = 'acwrite', 'minideps-confirm', false
end

-- CLI ------------------------------------------------------------------------
H.cli_run = function(jobs)
  local config_job = H.get_config().job
  local n_threads = math.max(config_job.n_threads or H.get_n_threads(), 1)

  -- Use only actually runnable jobs
  local should_run = function(job)
    -- Run only if there is command to run and previous runs of same reusable
    -- job did not result into error
    return type(job.command) == 'table' and #job.command > 0 and #job.err == 0
  end
  jobs = vim.tbl_filter(should_run, jobs)

  local n_total, id_started, n_finished = #jobs, 0, 0
  if n_total == 0 then return end

  local run_next
  run_next = function()
    if n_total <= id_started then return end
    id_started = id_started + 1

    local job = jobs[id_started]
    local command, cwd, exit_msg = job.command or {}, job.cwd, job.exit_msg

    -- Prepare data for `vim.uv.spawn`
    local executable, args = command[1], vim.list_slice(command, 2, #command)
    local process, stdout, stderr = nil, vim.uv.new_pipe(), vim.uv.new_pipe()

    -- - Unset special `GIT_xxx` variables that can affect `git` commands
    local env_map = vim.fn.environ()
    env_map.GIT_DIR, env_map.GIT_WORK_TREE = nil, nil
    local env = {}
    for k, v in pairs(env_map) do
      table.insert(env, k .. '=' .. tostring(v))
    end

    local spawn_opts = { args = args, cwd = cwd, env = env, stdio = { nil, stdout, stderr } }

    local on_exit = function(code)
      -- Process only not already closing job
      if process:is_closing() then return end
      process:close()

      -- Process exit code: if 0 treat `stderr` as warning; error otherwise
      if code == 0 then
        vim.list_extend(job.warn, job.err)
        -- NOTE: This is valid as only jobs with `err = {}` are filtered to run
        job.err = {}
      else
        table.insert(job.err, 1, 'ERROR CODE ' .. code .. '\n')
      end

      -- Finalize job
      n_finished = n_finished + 1
      if type(exit_msg) == 'string' and #job.err == 0 then
        H.notify(string.format('(%d/%d) %s', n_finished, n_total, exit_msg))
      end

      -- Start next parallel job
      run_next()
    end

    process = vim.uv.spawn(executable, spawn_opts, on_exit)
    H.cli_read_stream(stdout, job.out)
    H.cli_read_stream(stderr, job.err)
    vim.defer_fn(function()
      if not process:is_active() then return end
      table.insert(job.err, 'PROCESS REACHED TIMEOUT.')
      on_exit(1)
    end, config_job.timeout)
  end

  for _ = 1, n_threads do
    run_next()
  end

  vim.wait(config_job.timeout * n_total, function() return n_total <= n_finished end, 1)
end

H.cli_read_stream = function(stream, feed)
  local callback = function(err, data)
    if err then return table.insert(feed, 1, 'ERROR: ' .. err) end
    if data ~= nil then return table.insert(feed, data) end
    stream:close()
  end
  stream:read_start(callback)
end

H.cli_stream_tostring = function(stream) return (table.concat(stream):gsub('\n+$', '')) end

H.cli_new_job = function(command, cwd, exit_msg)
  return { command = command, cwd = cwd, exit_msg = exit_msg, out = {}, warn = {}, err = {} }
end

-- Two-stage execution --------------------------------------------------------
H.schedule_finish = function()
  if H.cache.finish_is_scheduled then return end
  vim.schedule(H.finish)
  H.cache.finish_is_scheduled = true
end

H.finish = function()
  local timer, step_delay = vim.uv.new_timer(), 1
  local f = nil
  f = vim.schedule_wrap(function()
    local callback = H.cache.later_callback_queue[1]
    if callback == nil then
      H.cache.finish_is_scheduled, H.cache.later_callback_queue = false, {}
      H.report_errors()
      return
    end

    table.remove(H.cache.later_callback_queue, 1)
    MiniDeps.now(callback)
    timer:start(step_delay, 0, f)
  end)
  timer:start(step_delay, 0, f)
end

H.report_errors = function()
  if #H.cache.exec_errors == 0 then return end
  local error_lines = table.concat(H.cache.exec_errors, '\n\n')
  H.cache.exec_errors = {}
  H.notify('There were errors during two-stage execution:\n\n' .. error_lines, 'ERROR')
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.deps) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.set_buf_name = function(buf_id, name) vim.api.nvim_buf_set_name(buf_id, 'minideps://' .. buf_id .. '/' .. name) end

H.notify = vim.schedule_wrap(function(msg, level)
  level = level or 'INFO'
  if H.get_config().silent and level ~= 'ERROR' and level ~= 'WARN' then return end
  if type(msg) == 'table' then msg = table.concat(msg, '\n') end
  vim.notify(string.format('(mini.deps) %s', msg), vim.log.levels[level])
  vim.cmd('redraw')
end)

H.edit = function(path, win_id)
  if type(path) ~= 'string' then return end
  local b = vim.api.nvim_win_get_buf(win_id or 0)
  local try_mimic_buf_reuse = (vim.fn.bufname(b) == '' and vim.bo[b].buftype ~= 'quickfix' and not vim.bo[b].modified)
    and (#vim.fn.win_findbuf(b) == 1 and vim.deep_equal(vim.fn.getbufline(b, 1, '$'), { '' }))
  local buf_id = vim.fn.bufadd(vim.fn.fnamemodify(path, ':.'))
  -- Showing in window also loads. Use `pcall` to not error with swap messages.
  pcall(vim.api.nvim_win_set_buf, win_id or 0, buf_id)
  vim.bo[buf_id].buflisted = true
  if try_mimic_buf_reuse then pcall(vim.api.nvim_buf_delete, b, { unload = false }) end
  return buf_id
end

H.get_timestamp = function() return vim.fn.strftime('%Y-%m-%d %H:%M:%S') end

H.get_n_threads = function() return math.floor(0.8 * #(vim.uv.cpu_info() or {})) end

H.full_path = function(path) return (vim.fn.fnamemodify(path, ':p'):gsub('\\', '/'):gsub('/+', '/'):gsub('(.)/$', '%1')) end

H.readdir = function(path)
  if vim.fn.isdirectory(path) ~= 1 then return {} end
  return vim.tbl_map(function(x) return path .. '/' .. x end, vim.fn.readdir(path))
end

H.source = function(path)
  pcall(function() vim.cmd('source ' .. vim.fn.fnameescape(path)) end)
end

-- TODO: Remove after compatibility with Neovim=0.9 is dropped
H.islist = vim.fn.has('nvim-0.10') == 1 and vim.islist or vim.tbl_islist

return MiniDeps
