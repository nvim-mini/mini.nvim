--- *mini.visits* Track and reuse file system visits
---
--- MIT License Copyright (c) 2023 Evgeni Chasnovski

--- Features:
---
--- - Persistently track file system visits (both files and directories)
---   per project directory. Store visit index is human readable and editable.
---
--- - Visit index is normalized on every write to contain relevant information.
---   Exact details can be customized. See |MiniVisits.normalize_index()|.
---
--- - Built-in ability to persistently add labels to path for later use.
---   See |MiniVisits.add_label()| and |MiniVisits.remove_label()|.
---
--- - Exported functions to reuse visit data:
---     - List visited paths/labels with custom filter and sort (uses "robust
---       frecency" by default). Can be used as source for pickers.
---       See |MiniVisits.list_paths()| and |MiniVisits.list_labels()|.
---       See |MiniVisits.gen_filter| and |MiniVisits.gen_sort|.
---
---     - Select visited paths/labels using |vim.ui.select()|.
---       See |MiniVisits.select_path()| and |MiniVisits.select_label()|.
---
---     - Iterate through visit paths in target direction ("forward", "backward",
---       "first", "last"). See |MiniVisits.iterate_paths()|.
---
--- - Exported functions to manually update visit index allowing persistent
---   track of any user information. See `*_index()` functions.
---
--- Notes:
--- - All data is stored _only_ in in-session Lua variable (for quick operation)
---   and at `config.store.path` on disk (for persistent usage).
--- - Most of functions affect an in-session data which gets written to disk only
---   before Neovim is closing or when users asks to.
--- - It doesn't account for paths being renamed or moved (because there is no
---   general way to detect that). Usually a manual intervention to the visit
---   index is required after the change but _before_ the next writing to disk
---   (usually before closing current session) because it will treat previous
---   path as deleted and remove it from index.
---   There is a |MiniVisits.rename_in_index()| helper for that.
---   If rename/move is done with |mini.files|, index is autoupdated.
---
--- Sources with more details:
--- - |MiniVisits-overview|
--- - |MiniVisits-index-specification|
--- - |MiniVisits-examples|
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.visits').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `MiniVisits`
--- which you can use for scripting or manually (with `:lua MiniVisits.*`).
---
--- See |MiniVisits.config| for `config` structure and default values.
---
--- You can override runtime config settings locally to buffer inside
--- `vim.b.minivisits_config` which should have same structure as
--- `MiniVisits.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- # Comparisons ~
---
--- - [nvim-telescope/telescope-frecency.nvim](https://github.com/nvim-telescope/telescope-frecency.nvim):
---     - It stores array of actual visit timestamps, while this module tracks
---       only total number and latest timestamp of visits. This is by design
---       as a different trade-off between how much data is being used/stored
---       and complexity of underlying "frecency" sorting.
---     - By default tracks a buffer only once per session, while this module
---       tracks on every meaningful buffer enter. This leads to a more relevant
---       in-session sorting.
---     - Implements an original frecency algorithm of Firefox's address bar,
---       while this module uses own "robust frecency" approach.
---     - Mostly designed to work with 'nvim-telescope/telescope.nvim', while
---       this module provides general function to list paths and select
---       with |vim.ui.select()|.
---     - Does not allow use of custom data (like labels), while this module does.
---
--- - [ThePrimeagen/harpoon](https://github.com/ThePrimeagen/harpoon):
---     - Has slightly different concept than general labeling, which more
---       resembles adding paths to an ordered stack. This module implements
---       a more common labeling which does not imply order with ability to
---       make it automated depending on the task and/or preference.
---     - Implements marks as positions in a path, while this module labels paths.
---     - Writes data on disk after every meaning change, while this module is
---       more conservative and read only when Neovim closes or when asked to.
---     - Has support for labeling terminals, while this modules is oriented
---       only towards paths.
---     - Has dedicated UI to manage marks, while this module does not by design.
---       There are functions for adding and removing label from the path.
---     - Does not provide functionality to track and reuse any visited path,
---       while this module does.
---
--- # Disabling ~
---
--- To disable automated tracking, set `vim.g.minivisits_disable` (globally) or
--- `vim.b.minivisits_disable` (for a buffer) to `true`. Considering high
--- number of different scenarios and customization intentions, writing exact
--- rules for disabling module's functionality is left to user. See
--- |mini.nvim-disabling-recipes| for common recipes.
---@tag MiniVisits

--- # Tracking visits ~
---
--- File system visits (both directory and files) tracking is done in two steps:
--- - On every dedicated event (`config.track.event`, |BufEnter| by default) timer
---   is (re)started to actually register visit after certain amount of time
---   (`config.track.delay` milliseconds, 1000 by default). It is not registered
---   immediately to allow navigation to target buffer in several steps
---   (for example, with series of |:bnext| / |:bprevious|).
---
--- - When delay time passes without any dedicated events being triggered
---   (meaning user is "settled" on certain buffer), |MiniVisits.register_visit()|
---   is called if all of the following conditions are met:
---     - Module is not disabled (see "Disabling" section in |mini.visits|).
---     - Buffer is normal with non-empty name (used as visit path).
---     - Visit path does not equal to the latest tracked one. This is to allow
---       temporary enter of non-normal buffers (like help, terminal, etc.)
---       without artificial increase of visit count.
---
--- Visit is autoregistered for |current-directory| and leads to increase of count
--- and latest time of visit. See |MiniVisits-index-specification| for more details.
---
--- Notes:
--- - All data is stored _only_ in in-session Lua variable (for quick operation)
---   and at `config.store.path` on disk (for persistent usage). It is automatically
---   written to disk before every Neovim exit (if `config.store.autowrite` is set).
---
--- - Tracking can be disabled by supplying empty string as `track.event`.
---   Then it is up to the user to properly call |MiniVisits.register_visit()|.
---
--- # Reusing visits ~
---
--- Visit data can be reused in at least these ways:
---
--- - Get a list of visited paths (see |MiniVisits.list_paths()|) and use it
---   to visualize/pick/navigate visit history.
---
--- - Select one of the visited paths to open it (see |MiniVisits.select_path()|).
---
--- - Move along visit history (see |MiniVisits.iterate_paths()|).
---
--- - Utilize labels. Any visit can be added one or more labels (like "core",
---   "tmp", etc.). They are bound to the visit (path registered for certain
---   directory) and are stored persistently.
---   Labels can be used to manually create groups of files and/or directories
---   that have particular interest to the user.
---   There is no one right way to use them, though. See |MiniVisits-examples|
---   for some inspiration.
---
--- - Utilizing custom data. Visit index can be manipulated manually using
---   `_index()` set of functions. All "storable" (i.e. not functions or
---   metatables) user data inside index is then stored on disk, so it can be
---   used to create any kind of workflow user wants.
---
--- See |MiniVisits-examples| for some actual configuration and workflow examples.
---@tag MiniVisits-overview

--- # Structure ~
---
--- Visit index is a table containing actual data in two level deep nested tables.
---
--- First level keys are paths of project directory (a.k.a "cwd") for which
--- visits are registered.
---
--- Second level keys are actual visit paths. Their values are tables with visit
--- data which should follow these requirements:
--- - Field <count> should be present and be a number. It represents the number
---   of times this path was visited under particular cwd.
--- - Field <latest> should be present and be a number. It represents the time
---   of latest path visit under particular cwd.
---   By default computed with |os.time()| (up to a second).
--- - Field <labels> might not be present. If present, it should be a table
---   with string labels as keys and `true` as values. It represents labels of
---   the path under particular cwd.
---
--- Notes:
--- - All paths are absolute.
--- - Visit path should not necessarily be a part of corresponding cwd.
--- - Both `count` and `latest` can be any number: whole, fractional, negative, etc.
---
--- Example of an index data: >lua
---
---   {
---     ['/home/user/project_1'] = {
---       ['home/user/project_1/file'] = { count = 3, latest = 1699796000 },
---       ['home/user/project_1/subdir'] = {
---         count = 10, latest = 1699797000, labels = { core = true },
---       },
---     },
---     ['/home/user/project_2'] = {
---       ['home/user/project_1/file'] = {
---         count = 0, latest = 0, labels = { other = true },
---       },
---       ['home/user/project_2/README'] = { count = 1, latest = 1699798000 },
---     },
---   }
--- <
--- # Storage ~
---
--- When stored on disk, visit index is a file containing Lua code returning
--- visit index table. It can be edited by hand as long as it contains a valid
--- Lua code (to be executed with |dofile()|).
---
--- Notes:
--- - Storage is implemented in such a way that it doesn't really support more
---   than one parallel Neovim processes. Meaning that if there are two or more
---   simultaneous Neovim processes with same visit index storage path, the last
---   one writing to it will preserve its visit history while others - won't.
---
--- # Normalization ~
---
--- To ensure that visit index contains mostly relevant data, it gets normalized:
--- automatically inside |MiniVisits.write_index()| or
--- via |MiniVisits.normalize_index()|.
---
--- What normalization actually does can be configured in `config.store.normalize`.
---
--- See |MiniVisits.gen_normalize.default()| for default normalization approach.
---@tag MiniVisits-index-specification

--- This module provides a flexible framework for working with file system visits.
--- Exact choice of how to organize workflow is left to the user.
--- Here are some examples for inspiration which can be combined together.
---
--- # Use different sorting ~
---
--- Default sorting in |MiniVisits.gen_sort.default()| allows flexible adjustment
--- of which feature to prefer more: recency or frequency. Here is an example of
--- how to make set of keymaps for three types of sorting combined with two types
--- of scopes (all visits and only for current cwd): >lua
---
---   local make_select_path = function(select_global, recency_weight)
---     local visits = require('mini.visits')
---     local sort = visits.gen_sort.default({ recency_weight = recency_weight })
---     local select_opts = { sort = sort }
---     return function()
---       local cwd = select_global and '' or vim.fn.getcwd()
---       visits.select_path(cwd, select_opts)
---     end
---   end
---
---   local map = function(lhs, desc, ...)
---     vim.keymap.set('n', lhs, make_select_path(...), { desc = desc })
---   end
---
---   -- Adjust LHS and description to your liking
---   map('<Leader>vr', 'Select recent (all)',   true,  1)
---   map('<Leader>vR', 'Select recent (cwd)',   false, 1)
---   map('<Leader>vy', 'Select frecent (all)',  true,  0.5)
---   map('<Leader>vY', 'Select frecent (cwd)',  false, 0.5)
---   map('<Leader>vf', 'Select frequent (all)', true,  0)
---   map('<Leader>vF', 'Select frequent (cwd)', false, 0)
--- <
--- Note: If using |mini.pick|, consider |MiniExtra.pickers.visit_paths()|.
---
--- # Use manual labels ~
---
--- Labels is a powerful tool to create groups of associated paths.
--- Usual workflow consists of:
--- - Add label with |MiniVisits.add_label()| (prompts for actual label).
--- - Remove label with |MiniVisits.remove_label()| (prompts for actual label).
--- - When need to use labeled groups, call |MiniVisits.select_label()| which
---   will then call |MiniVisits.select_path()| to select path among those
---   having selected label.
---   Note: If using |mini.pick|, consider |MiniExtra.pickers.visit_labels()|.
---
--- To make this workflow smoother, here is an example of keymaps: >lua
---
---   local map_vis = function(keys, call, desc)
---     local rhs = '<Cmd>lua MiniVisits.' .. call .. '<CR>'
---     vim.keymap.set('n', '<Leader>' .. keys, rhs, { desc = desc })
---   end
---
---   map_vis('vv', 'add_label()',          'Add label')
---   map_vis('vV', 'remove_label()',       'Remove label')
---   map_vis('vl', 'select_label("", "")', 'Select label (all)')
---   map_vis('vL', 'select_label()',       'Select label (cwd)')
--- <
--- # Use fixed labels ~
---
--- During work on every project there is usually a handful of files where core
--- activity is concentrated. This can be made easier by creating mappings
--- which add/remove special fixed label (for example, "core") and select paths
--- with that label for both all and current cwd. Example: >lua
---
---   -- Create and select
---   local map_vis = function(keys, call, desc)
---     local rhs = '<Cmd>lua MiniVisits.' .. call .. '<CR>'
---     vim.keymap.set('n', '<Leader>' .. keys, rhs, { desc = desc })
---   end
---
---   map_vis('vv', 'add_label("core")',                     'Add to core')
---   map_vis('vV', 'remove_label("core")',                  'Remove from core')
---   map_vis('vc', 'select_path("", { filter = "core" })',  'Select core (all)')
---   map_vis('vC', 'select_path(nil, { filter = "core" })', 'Select core (cwd)')
---
---   -- Iterate based on recency
---   local sort_latest = MiniVisits.gen_sort.default({ recency_weight = 1 })
---   local map_iterate_core = function(lhs, direction, desc)
---     local opts = { filter = 'core', sort = sort_latest, wrap = true }
---     local rhs = function()
---       MiniVisits.iterate_paths(direction, vim.fn.getcwd(), opts)
---     end
---     vim.keymap.set('n', lhs, rhs, { desc = desc })
---   end
---
---   map_iterate_core('[{', 'last',     'Core label (earliest)')
---   map_iterate_core('[[', 'forward',  'Core label (earlier)')
---   map_iterate_core(']]', 'backward', 'Core label (later)')
---   map_iterate_core(']}', 'first',    'Core label (latest)')
--- <
--- # Use automated labels ~
---
--- When using version control system (such as Git), usually there is already
--- an identifier that groups files you are working with - branch name.
--- Here is an example of keymaps to add/remove label equal to branch name: >lua
---
---   local map_branch = function(keys, action, desc)
---     local rhs = function()
---       local branch = vim.fn.system('git rev-parse --abbrev-ref HEAD')
---       if vim.v.shell_error ~= 0 then return nil end
---       branch = vim.trim(branch)
---       require('mini.visits')[action](branch)
---     end
---     vim.keymap.set('n', '<Leader>' .. keys, rhs, { desc = desc })
---   end
---
---   map_branch('vb', 'add_label',    'Add branch label')
---   map_branch('vB', 'remove_label', 'Remove branch label')
--- <
---@tag MiniVisits-examples

---@alias __visits_path string|nil Visit path. Can be empty string to mean "all visited
---   paths for `cwd`". Default: path of current buffer if normal, error otherwise.
---@alias __visits_cwd string|nil Visit cwd (project directory). Can be empty string to mean
---   "all visited cwd". Default: |current-directory|.
---@alias __visits_filter - <filter> `(function)` - predicate to filter paths. For more information
---     about how it is used, see |MiniVisits.config.list|.
---     Default: value of `config.list.filter` with |MiniVisits.gen_filter.default()|
---     as its default.
---@alias __visits_sort - <sort> `(function)` - path data sorter. For more information about how
---     it is used, see |MiniVisits.config.list|.
---     Default: value of `config.list.sort` or |MiniVisits.gen_sort.default()|
---     as its default.

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local
---@diagnostic disable:cast-local-type
---@diagnostic disable:undefined-doc-name
---@diagnostic disable:luadoc-miss-type-name

-- Module definition ==========================================================
local MiniVisits = {}
local H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniVisits.config|.
---
---@usage >lua
---   require('mini.visits').setup() -- use default config
---   -- OR
---   require('mini.visits').setup({}) -- replace {} with your config table
--- <
MiniVisits.setup = function(config)
  -- Export module
  _G.MiniVisits = MiniVisits

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Define behavior
  H.create_autocommands(config)
end

--- Defaults ~
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text # List ~
--- *MiniVisits.config.list*
---
--- `config.list` defines how visit index is converted to a path list by default.
---
--- `list.filter` is a callable which should take a path data and return `true` if
--- this path should be present in the list.
--- Default: output of |MiniVisits.gen_filter.default()|.
---
--- Path data is a table with at least these fields:
--- - <path> `(string)` - absolute path of visit.
--- - <count> `(number)` - number of visits.
--- - <latest> `(number)` - timestamp of latest visit.
--- - <labels> `(table|nil)` - table of labels (has string keys with `true` values).
---
--- Notes:
--- - Both `count` and `latest` (in theory) can be any number. But built-in tracking
---   results into positive integer `count` and `latest` coming from |os.time()|.
--- - There can be other entries if they are set by user as index entry.
---
--- `list.sort` is a callable which should take an array of path data and return
--- a sorted array of path data (or at least tables each containing <path> field).
--- Default: output of |MiniVisits.gen_sort.default()|.
--- Single path data entry is a table with a same structure as for `list.filter`.
---
--- Note, that `list.sort` can be used both to filter, sort, or even return paths
--- unrelated to the input.
---
--- # Silent ~
---
--- `config.silent` is a boolean controlling whether to show non-error feedback
--- (like adding/removing labels, etc.). Default: `false`.
---
--- # Store ~
---
--- `config.store` defines how visit index is stored on disk to enable persistent
--- data across several sessions.
---
--- `store.autowrite` is a boolean controlling whether to write visit data to
--- disk on |VimLeavePre| event. Default: `true`.
---
--- `store.normalize` is a callable which should take visit index
--- (see |MiniVisits-index-specification|) as input and return "normalized" visit
--- index as output. This is used to ensure that visit index is up to date and
--- contains only relevant data. For example, it controls how old and
--- irrelevant visits are "forgotten", and more.
--- Default: output of |MiniVisits.gen_normalize.default()|.
---
--- `store.path` is a path to which visit index is written. See "Storage" section
--- of |MiniVisits-index-specification| for more details.
--- Note: set to empty string to disable any writing with not explicitly set
--- path (including the one on |VimLeavePre|).
--- Default: "mini-visits-index" file inside |$XDG_DATA_HOME|.
---
--- # Track ~
---
--- `config.track` defines how visits are tracked (index entry is autoupdated).
--- See "Tracking visits" section in |MiniVisits-overview| for more details.
---
--- `track.event` is a proper Neovim |{event}| on which track get triggered.
--- Note: set to empty string to disable automated tracking.
--- Default: |BufEnter|.
---
--- `track.delay` is a delay in milliseconds after event is triggered and visit
--- is autoregistered.
--- Default: 1000 (to allow navigation between buffers without tracking
--- intermediate ones).
MiniVisits.config = {
  -- How visit index is converted to list of paths
  list = {
    -- Predicate for which paths to include (all by default)
    filter = nil,

    -- Sort paths based on the visit data (robust frecency by default)
    sort = nil,
  },

  -- Whether to disable showing non-error feedback
  silent = false,

  -- How visit index is stored
  store = {
    -- Whether to write all visits before Neovim is closed
    autowrite = true,

    -- Function to ensure that written index is relevant
    normalize = nil,

    -- Path to store visit index
    path = vim.fn.stdpath('data') .. '/mini-visits-index',
  },

  -- How visit tracking is done
  track = {
    -- Start visit register timer at this event
    -- Supply empty string (`''`) to not do this automatically
    event = 'BufEnter',

    -- Debounce delay after event to register a visit
    delay = 1000,
  },
}
--minidoc_afterlines_end

--- Register visit
---
--- Steps:
--- - Ensure that there is an entry for path-cwd pair.
--- - Add 1 to visit `count`.
--- - Set `latest` visit time to equal current time.
---
---@param path string|nil Visit path. Default: path of current buffer if normal,
---   error otherwise.
---@param cwd string|nil Visit cwd (project directory). Default: |current-directory|.
MiniVisits.register_visit = function(path, cwd)
  path = H.validate_path(path)
  cwd = H.validate_cwd(cwd)
  if path == '' or cwd == '' then H.error('Both `path` and `cwd` should not be empty.') end

  H.ensure_index_entry(path, cwd)
  local path_tbl = H.index[cwd][path]
  path_tbl.count = path_tbl.count + 1
  path_tbl.latest = os.time()
end

--- Add path to index
---
--- Ensures that there is a (one or more) entry for path-cwd pair. If entry is
--- already present, does nothing. If not - creates it with both `count` and
--- `latest` set to 0.
---
---@param path __visits_path
---@param cwd __visits_cwd
MiniVisits.add_path = function(path, cwd)
  path = H.validate_path(path)
  cwd = H.validate_cwd(cwd)

  local path_cwd_pairs = H.resolve_path_cwd(path, cwd)
  for _, pair in ipairs(path_cwd_pairs) do
    H.ensure_index_entry(pair.path, pair.cwd)
  end
end

--- Add label to path
---
--- Steps:
--- - Ensure that there is an entry for path-cwd pair.
--- - Add label to the entry.
---
---@param label string|nil Label string. Default: `nil` to ask from user.
---@param path __visits_path
---@param cwd __visits_cwd
MiniVisits.add_label = function(label, path, cwd)
  path = H.validate_path(path)
  cwd = H.validate_cwd(cwd)

  if label == nil then
    -- Suggest all labels from cwd in completion
    label = H.get_label_from_user('Enter label to add', MiniVisits.list_labels('', cwd))
    if label == nil then return end
  end
  label = H.validate_string(label, 'label')

  -- Add label to all target path-cwd pairs
  local path_cwd_pairs = H.resolve_path_cwd(path, cwd)
  for _, pair in ipairs(path_cwd_pairs) do
    H.ensure_index_entry(pair.path, pair.cwd)
    local path_tbl = H.index[pair.cwd][pair.path]
    local labels = path_tbl.labels or {}
    labels[label] = true
    path_tbl.labels = labels
  end

  H.echo(string.format('Added %s label.', vim.inspect(label)))
end

--- Remove path
---
--- Deletes a (one or more) entry for path-cwd pair from an index. If entry is
--- already absent, does nothing.
---
--- Notes:
--- - Affects only in-session Lua variable. Call |MiniVisits.write_index()| to
---   make it persistent.
---
---@param path __visits_path
---@param cwd __visits_cwd
MiniVisits.remove_path = function(path, cwd)
  path = H.validate_path(path)
  cwd = H.validate_cwd(cwd)

  -- Remove all target visits
  H.ensure_read_index()
  local path_cwd_pairs = H.resolve_path_cwd(path, cwd)
  for _, pair in ipairs(path_cwd_pairs) do
    local cwd_tbl = H.index[pair.cwd]
    if type(cwd_tbl) == 'table' then cwd_tbl[pair.path] = nil end
  end

  for dir, _ in pairs(H.index) do
    if vim.tbl_count(H.index[dir]) == 0 then H.index[dir] = nil end
  end
end

--- Remove label from path
---
--- Steps:
--- - Remove label from (one or more) index entry.
--- - If it was last label in an entry, remove `labels` key.
---
---@param label string|nil Label string. Default: `nil` to ask from user.
---@param path __visits_path
---@param cwd __visits_cwd
MiniVisits.remove_label = function(label, path, cwd)
  path = H.validate_path(path)
  cwd = H.validate_cwd(cwd)

  if label == nil then
    -- Suggest only labels from target path-cwd pairs
    label = H.get_label_from_user('Enter label to remove', MiniVisits.list_labels(path, cwd))
    if label == nil then return end
  end
  label = H.validate_string(label, 'label')

  -- Remove label from all target path-cwd pairs (ignoring not present ones and
  -- collapsing `labels` if removed last label)
  H.ensure_read_index()
  local path_cwd_pairs = H.resolve_path_cwd(path, cwd)
  for _, pair in ipairs(path_cwd_pairs) do
    local path_tbl = (H.index[pair.cwd] or {})[pair.path]
    if type(path_tbl) == 'table' and type(path_tbl.labels) == 'table' then
      path_tbl.labels[label] = nil
      if vim.tbl_count(path_tbl.labels) == 0 then path_tbl.labels = nil end
    end
  end

  H.echo(string.format('Removed %s label.', vim.inspect(label)))
end

--- List visit paths
---
--- Convert visit index for certain cwd into an ordered list of visited paths.
--- Supports custom filtering and sorting.
---
--- Examples: >lua
---
---   -- Get paths sorted from most to least recent
---   local sort_recent = MiniVisits.gen_sort.default({ recency_weight = 1 })
---   MiniVisits.list_paths(nil, { sort = sort_recent })
---
---   -- Get paths from all cwd sorted from most to least frequent
---   local sort_frequent = MiniVisits.gen_sort.default({ recency_weight = 0 })
---   MiniVisits.list_paths('', { sort = sort_frequent })
---
---   -- Get paths not including hidden
---   local is_not_hidden = function(path_data)
---     return not vim.startswith(vim.fn.fnamemodify(path_data.path, ':t'), '.')
---   end
---   MiniVisits.list_paths(nil, { filter = is_not_hidden })
--- <
---@param cwd __visits_cwd
---@param opts table|nil Options. Possible fields:
---   __visits_filter
---   __visits_sort
---
---@return table Array of visited paths.
MiniVisits.list_paths = function(cwd, opts)
  cwd = H.validate_cwd(cwd)

  opts = vim.tbl_deep_extend('force', H.get_config().list, opts or {})
  local filter = H.validate_filter(opts.filter)
  local sort = H.validate_sort(opts.sort)

  local path_data_arr = H.make_path_array('', cwd)
  local res_arr = sort(vim.tbl_filter(filter, path_data_arr))
  return vim.tbl_map(function(x) return x.path end, res_arr)
end

--- List visit labels
---
--- Convert visit index for certain path-cwd pair into an ordered list of labels.
--- Supports custom filtering for paths. Result is ordered from most to least
--- frequent label.
---
--- Examples: >lua
---
---   -- Get labels for current path-cwd pair
---   MiniVisits.list_labels()
---
---   -- Get labels for current path across all cwd
---   MiniVisits.list_labels(nil, '')
---
---   -- Get all available labels excluding ones from hidden files
---   local is_not_hidden = function(path_data)
---     return not vim.startswith(vim.fn.fnamemodify(path_data.path, ':t'), '.')
---   end
---   MiniVisits.list_labels('', '', { filter = is_not_hidden })
--- <
---@param path __visits_path
---@param cwd __visits_cwd
---@param opts table|nil Options. Possible fields:
---   __visits_filter
---   __visits_sort
---
---@return table Array of available labels.
MiniVisits.list_labels = function(path, cwd, opts)
  path = H.validate_path(path)
  cwd = H.validate_cwd(cwd)

  opts = vim.tbl_deep_extend('force', { filter = H.get_config().list.filter }, opts or {})
  local filter = H.validate_filter(opts.filter)

  local path_data_arr = H.make_path_array(path, cwd)
  local res_arr = vim.tbl_filter(filter, path_data_arr)

  -- Count labels
  local label_counts = {}
  for _, path_data in ipairs(res_arr) do
    for label, _ in pairs(path_data.labels or {}) do
      label_counts[label] = (label_counts[label] or 0) + 1
    end
  end

  -- Sort from most to least common
  local label_arr = {}
  for label, count in pairs(label_counts) do
    table.insert(label_arr, { count, label })
  end
  table.sort(label_arr, function(a, b) return a[1] > b[1] or (a[1] == b[1] and a[2] < b[2]) end)
  return vim.tbl_map(function(x) return x[2] end, label_arr)
end

--- Select visit path
---
--- Uses |vim.ui.select()| with an output of |MiniVisits.list_paths()| and
--- calls |:edit| on the chosen item.
---
--- Note: if you have |mini.pick|, consider using |MiniExtra.pickers.visit_labels()|
--- and |MiniExtra.pickers.visit_paths()|.
---
--- Examples:
---
--- - Select from all visited paths: `MiniVisits.select_path('')`
---
--- - Select from paths under current directory sorted from most to least recent: >lua
---
---     local sort_recent = MiniVisits.gen_sort.default({ recency_weight = 1 })
---     MiniVisits.select_path(nil, { sort = sort_recent })
--- <
---@param cwd string|nil Forwarded to |MiniVisits.list_paths()|.
---@param opts table|nil Forwarded to |MiniVisits.list_paths()|.
MiniVisits.select_path = function(cwd, opts)
  local paths = MiniVisits.list_paths(cwd, opts)
  local cwd_to_short = cwd == '' and vim.fn.getcwd() or cwd
  local items = vim.tbl_map(function(path) return { path = path, text = H.short_path(path, cwd_to_short) } end, paths)
  local select_opts = { prompt = 'Visited paths', format_item = function(item) return item.text end }
  local on_choice = function(item) H.edit((item or {}).path) end

  vim.ui.select(items, select_opts, on_choice)
end

--- Select visit label
---
--- Uses |vim.ui.select()| with an output of |MiniVisits.list_labels()| and
--- calls |MiniVisits.select_path()| to get target paths with selected label.
---
--- Note: if you have |mini.pick|, consider using |MiniExtra.pickers.visit_labels()|.
---
--- Examples:
---
--- - Select from labels of current path: `MiniVisits.select_label()`
---
--- - Select from all visited labels: `MiniVisits.select_label('', '')`
---
--- - Select from current project labels and sort paths (after choosing) from most
---   to least recent: >lua
---
---     local sort_recent = MiniVisits.gen_sort.default({ recency_weight = 1 })
---     MiniVisits.select_label('', nil, { sort = sort_recent })
--- <
---@param path string|nil Forwarded to |MiniVisits.list_labels()|.
---@param cwd string|nil Forwarded to |MiniVisits.list_labels()|.
---@param opts table|nil Forwarded to both |MiniVisits.list_labels()|
---  and |MiniVisits.select_path()| (after choosing a label).
MiniVisits.select_label = function(path, cwd, opts)
  local items = MiniVisits.list_labels(path, cwd, opts)
  opts = opts or {}
  local on_choice = function(label)
    if label == nil then return end

    -- Select among subset of paths with chosen label
    local filter_cur = (opts or {}).filter or MiniVisits.gen_filter.default()
    local new_opts = vim.deepcopy(opts)
    new_opts.filter = function(path_data)
      return filter_cur(path_data) and type(path_data.labels) == 'table' and path_data.labels[label]
    end
    MiniVisits.select_path(cwd, new_opts)
  end

  vim.ui.select(items, { prompt = 'Visited labels' }, on_choice)
end

--- Iterate visit paths
---
--- Steps:
--- - Compute a sorted array of target paths using |MiniVisits.list_paths()|.
--- - Identify the current index inside the array based on path of current buffer.
--- - Iterate through the array certain amount of times in a dedicated direction:
---     - For "first" direction - forward starting from index 0 (so that single
---       first iteration leads to first path).
---     - For "backward" direction - backward starting from current index.
---     - For "forward" direction - forward starting from current index.
---     - For "last" direction - backward starting from index after the last one
---       (so that single first iteration leads to the last path).
---
--- Notes:
--- - Mostly designed to be used as a mapping. See `MiniVisits-examples`.
--- - If path from current buffer is not in the output of `MiniVisits.list_paths()`,
---   starting index is inferred such that first iteration lands on first item
---   (if iterating forward) or last item (if iterating backward).
--- - Navigation with this function is not tracked (see |MiniVisits-overview|).
---   This is done to allow consecutive application without affecting
---   underlying list of paths.
---
--- Examples assuming underlying array of files `{ "file1", "file2", "file3" }`:
---
--- - `MiniVisits("first")` results into focusing on "file1".
--- - `MiniVisits("backward", { n_times = 2 })` from "file3" results into "file1".
--- - `MiniVisits("forward", { n_times = 10 })` from "file1" results into "file3".
--- - `MiniVisits("last", { n_times = 4, wrap = true })` results into "file3".
---
---@param direction string One of "first", "backward", "forward", "last".
---@param cwd string|nil Forwarded to |MiniVisits.list_paths()|.
---@param opts table|nil Options. Possible fields:
---   - <filter> `(function)` - forwarded to |MiniVisits.list_paths()|.
---   - <sort> `(function)` - forwarded to |MiniVisits.list_paths()|.
---   - <n_times> `(number)` - number of steps to go in certain direction.
---     Default: |v:count1|.
---   - <wrap> `(boolean)` - whether to wrap around list edges. Default: `false`.
MiniVisits.iterate_paths = function(direction, cwd, opts)
  if not (direction == 'first' or direction == 'backward' or direction == 'forward' or direction == 'last') then
    H.error('`direction` should be one of "first", "backward", "forward", "last".')
  end
  local is_move_forward = (direction == 'first' or direction == 'forward')

  local default_opts = { filter = nil, sort = nil, n_times = vim.v.count1, wrap = false }
  opts = vim.tbl_deep_extend('force', default_opts, opts or {})
  local all_paths = MiniVisits.list_paths(cwd, { filter = opts.filter, sort = opts.sort })

  local n_tot = #all_paths
  if n_tot == 0 then return end

  -- Compute current index
  local cur_ind
  if direction == 'first' then cur_ind = 0 end
  if direction == 'last' then cur_ind = n_tot + 1 end
  if direction == 'backward' or direction == 'forward' then
    local cur_path = H.buf_get_path(vim.api.nvim_get_current_buf())
    for i, path in ipairs(all_paths) do
      if path == cur_path then
        cur_ind = i
        break
      end
    end
  end

  -- - If not on path from the list, make going forward start from the
  --   beginning and backward - from end
  if cur_ind == nil then cur_ind = is_move_forward and 0 or (n_tot + 1) end

  -- Compute target index ensuring that it is inside `[1, #all_paths]`
  local res_ind = cur_ind + opts.n_times * (is_move_forward and 1 or -1)
  res_ind = opts.wrap and ((res_ind - 1) % n_tot + 1) or math.min(math.max(res_ind, 1), n_tot)

  -- Open path with no visit track (for default `track.event`)
  -- Use `vim.g` instead of `vim.b` to not register in **next** buffer
  local cache_disabled = vim.g.minivisits_disable
  vim.g.minivisits_disable = true
  H.edit(all_paths[res_ind])
  vim.g.minivisits_disable = cache_disabled
end

--- Get active visit index
---
---@return table Copy of currently active visit index table.
MiniVisits.get_index = function()
  H.ensure_read_index()
  return vim.deepcopy(H.index)
end

--- Set active visit index
---
---@param index table Visit index table.
MiniVisits.set_index = function(index)
  H.validate_index(index, '`index`')
  H.index = vim.deepcopy(index)
  H.cache.needs_index_read = false
end

--- Reset active visit index
---
--- Set currently active visit index to the output of |MiniVisits.read_index()|.
--- Does nothing if reading the index failed.
MiniVisits.reset_index = function()
  local ok, stored_index = pcall(MiniVisits.read_index)
  if not ok or stored_index == nil then return end
  MiniVisits.set_index(stored_index)
end

--- Normalize visit index
---
--- Applies `config.store.normalize` (|MiniVisits.gen_normalize.default()| by default)
--- to the input index object and returns the output (if it fits in the definition
--- of index object; see |MiniVisits-index-specification|).
---
---@param index table|nil Index object. Default: copy of the current index.
---
---@return table Normalized index object.
MiniVisits.normalize_index = function(index)
  index = index or MiniVisits.get_index()
  H.validate_index(index, '`index`')

  local config = H.get_config()
  local normalize = config.store.normalize
  if not vim.is_callable(normalize) then normalize = MiniVisits.gen_normalize.default() end
  local new_index = normalize(vim.deepcopy(index))
  H.validate_index(new_index, '`index` after normalization')

  return new_index
end

--- Read visit index from disk
---
---@param store_path string|nil Path on the disk containing visit index data.
---   Default: `config.store.path`.
---   Notes:
---   - Can return `nil` if path is empty string or file is not readable.
---   - File is sourced with |dofile()| as a regular Lua file.
---
---@return table|nil Output of the file source.
MiniVisits.read_index = function(store_path)
  store_path = store_path or H.get_config().store.path
  if store_path == '' then return nil end
  H.validate_string(store_path, 'store_path')
  if vim.fn.filereadable(store_path) == 0 then return nil end

  return dofile(store_path)
end

--- Write visit index to disk
---
--- Steps:
--- - Normalize index with |MiniVisits.normalize_index()|.
--- - Ensure path is valid (all parent directories are created, etc.).
--- - Write index object to the path so that it is readable
---   with |MiniVisits.read_index()|.
---
---@param store_path string|nil Path on the disk where to write visit index data.
---   Default: `config.store.path`. Note: if empty string, nothing is written.
---@param index table|nil Index object to write to disk.
---   Default: current session index.
MiniVisits.write_index = function(store_path, index)
  store_path = store_path or H.get_config().store.path
  H.validate_string(store_path, 'store_path')
  if store_path == '' then return end
  index = index or MiniVisits.get_index()
  H.validate_index(index, '`index`')

  -- Normalize index
  index = MiniVisits.normalize_index(index)

  -- Ensure writable path
  store_path = vim.fn.fnamemodify(store_path, ':p')
  local path_dir = vim.fn.fnamemodify(store_path, ':h')
  vim.fn.mkdir(path_dir, 'p')

  -- Write
  local lines = vim.split(vim.inspect(index), '\n')
  lines[1] = 'return ' .. lines[1]
  vim.fn.writefile(lines, store_path)
end

--- Rename path in index
---
--- A helper to react for a path rename/move in order to preserve its visit data.
--- It works both for file and directory paths.
---
--- Notes:
--- - It does not update current index, but returns a modified index object.
---   Use |MiniVisits.set_index()| to make it current.
--- - Use only full paths.
--- - Do not append `/` to directory paths. Use same format as for files.
---
--- Assuming `path_from` and `path_to` are variables containing full paths
--- before and after rename/move, here is an example to update current index: >lua
---
---   local new_index = MiniVisits.rename_in_index(path_from, path_to)
---   MiniVisits.set_index(new_index)
--- <
---@param path_from string Full path to be renamed.
---@param path_to string Full path to be replaced with.
---@param index table|nil Index object inside which to perform renaming.
---   Default: current session index.
---
---@return table Index object with renamed path.
MiniVisits.rename_in_index = function(path_from, path_to, index)
  path_from = H.validate_string(path_from, 'path_from')
  path_to = H.validate_string(path_to, 'path_to')
  index = index or MiniVisits.get_index()
  H.validate_index(index, '`index`')

  local path_from_pattern = vim.pesc(path_from)
  local pattern_from_full = string.format('^%s$', path_from_pattern)
  local pattern_from_parent_dir = string.format('^(%s)/', path_from_pattern)
  local path_to_parent_dir = path_to .. '/'

  local replace = function(x)
    if string.find(x, pattern_from_full) ~= nil then return path_to end
    return string.gsub(x, pattern_from_parent_dir, path_to_parent_dir)
  end

  local res = {}
  for cwd, cwd_tbl in pairs(index) do
    local new_cwd_tbl = {}
    for path, path_tbl in pairs(cwd_tbl) do
      new_cwd_tbl[replace(path)] = vim.deepcopy(path_tbl)
    end
    res[replace(cwd)] = new_cwd_tbl
  end

  return res
end

--- Generate filter function
---
--- This is a table with function elements. Call to actually get specification.
MiniVisits.gen_filter = {}

--- Default filter
---
--- Always returns `true` resulting in no actual filter.
---
---@return function Visit filter function. See |MiniVisits.config.list| for more details.
MiniVisits.gen_filter.default = function()
  return function(path_data) return true end
end

--- Filter visits from current session
---
---@return function Visit filter function. See |MiniVisits.config.list| for more details.
MiniVisits.gen_filter.this_session = function()
  return function(path_data) return H.cache.session_start_time <= path_data.latest end
end

--- Generate sort function
---
--- This is a table with function elements. Call to actually get specification.
MiniVisits.gen_sort = {}

--- Default sort
---
--- Sort paths using "robust frecency" approach. It relies on the rank operation:
--- based on certain reference number for every item, assign it a number
--- between 1 (best) and number of items (worst). Ties are dealt with "average
--- rank" approach: each element with a same reference number is assigned
--- an average rank among such elements. This way total rank sum depends only
--- on number of paths.
---
--- Here is an algorithm outline:
--- - Rank paths based on frequency (`count` value): from most to least frequent.
--- - Rank paths based on recency (`latest` value): from most to least recent.
--- - Combine ranks from previous steps with weights:
---   `score = (1 - w) * rank_frequency + w * rank_recency`, where `w` is
---   "recency weight". The smaller this weight the less recency affects outcome.
---
--- Examples:
--- - Default recency weight 0.5 results into "robust frecency" sorting: it
---   combines both frequency and recency.
---   This is called a "robust frecency" because actual values don't have direct
---   effect on the outcome, only ordering matters. For example, if there is
---   a very frequent file with `count = 100` while all others have `count = 5`,
---   it will not massively dominate the outcome as long as it is not very recent.
---
--- - Having recency weight 1 results into "from most to least recent" sorting.
---
--- - Having recency weight 0 results into "from most to least frequent" sorting.
---
---@param opts table|nil Option. Possible fields:
---   - <recency_weight> `(number)` - a number between 0 and 1 for recency weight.
---     Default: 0.5.
---
---@return function Visit sort function. See |MiniVisits.config.list| for more details.
MiniVisits.gen_sort.default = function(opts)
  opts = vim.tbl_deep_extend('force', { recency_weight = 0.5 }, opts or {})
  local recency_weight = opts.recency_weight
  local is_weight = type(recency_weight) == 'number' and 0 <= recency_weight and recency_weight <= 1
  if not is_weight then H.error('`opts.recency_weight` should be number between 0 and 1.') end

  return function(path_data_arr)
    path_data_arr = vim.deepcopy(path_data_arr)

    -- Add ranks for `count` and `latest`
    table.sort(path_data_arr, function(a, b) return a.count > b.count end)
    H.tbl_add_rank(path_data_arr, 'count')
    table.sort(path_data_arr, function(a, b) return a.latest > b.latest end)
    H.tbl_add_rank(path_data_arr, 'latest')

    -- Compute final rank and sort by it
    for _, path_data in ipairs(path_data_arr) do
      path_data.rank = (1 - recency_weight) * path_data.count_rank + recency_weight * path_data.latest_rank
    end
    table.sort(path_data_arr, function(a, b) return a.rank < b.rank or (a.rank == b.rank and a.path < b.path) end)
    return path_data_arr
  end
end

--- Z sort
---
--- Sort as in https://github.com/rupa/z.
---
---@return function Visit sort function. See |MiniVisits.config.list| for more details.
MiniVisits.gen_sort.z = function()
  return function(path_data_arr)
    path_data_arr = vim.deepcopy(path_data_arr)
    local now = os.time()
    for _, path_data in ipairs(path_data_arr) do
      -- Source: https://github.com/rupa/z/blob/master/z.sh#L151
      local dtime = math.max(now - path_data.latest, 0.0001)
      path_data.z = 10000 * path_data.count * (3.75 / ((0.0001 * dtime + 1) + 0.25))
    end
    table.sort(path_data_arr, function(a, b) return a.z > b.z or (a.z == b.z and a.path < b.path) end)
    return path_data_arr
  end
end

--- Generate normalize function
---
--- This is a table with function elements. Call to actually get specification.
MiniVisits.gen_normalize = {}

--- Generate default normalize function
---
--- Steps:
--- - Prune visits, i.e. remove outdated visits:
---     - If `count` number of visits is below prune threshold, remove that visit
---       entry from particular cwd (it can still be present in others).
---     - If either first (cwd) or second (path) level key doesn't represent an
---       actual path on disk, remove the whole associated value.
---     - NOTE: if visit has any label, it is not automatically pruned.
---
--- - Decay visits, i.e. possibly make visits more outdated. This is an important
---   part to the whole usability: together with pruning it results into automated
---   removing of paths which were visited long ago and are not relevant.
---
---   Decay is done per cwd if its total `count` values sum exceeds decay threshold.
---   It is performed through multiplying each `count` by same coefficient so that
---   the new total sum of `count` is equal to some smaller target value.
---   Note: only two decimal places are preserved, so the sum might not be exact.
---
--- - Prune once more to ensure that there are no outdated paths after decay.
---
---@param opts table|nil Options. Possible fields:
---   - <decay_threshold> `(number)` - decay threshold. Default: 1000.
---   - <decay_target> `(number)` - decay target. Default: 800.
---   - <prune_threshold> `(number)` - prune threshold. Default: 0.5.
---   - <prune_paths> `(boolean)` - whether to prune outdated paths. Default: `true`.
---
---@return function Visit index normalize function. See "Store" in |MiniVisits.config|.
MiniVisits.gen_normalize.default = function(opts)
  local default_opts = { decay_threshold = 1000, decay_target = 800, prune_threshold = 0.5, prune_paths = true }
  opts = vim.tbl_deep_extend('force', default_opts, opts or {})

  return function(index)
    H.validate_index(index)
    local res = vim.deepcopy(index)
    H.index_prune(res, opts.prune_paths, opts.prune_threshold)
    for cwd, cwd_tbl in pairs(res) do
      H.index_decay_cwd(cwd_tbl, opts.decay_threshold, opts.decay_target)
    end
    -- Ensure that no path has count smaller than threshold
    H.index_prune(res, false, opts.prune_threshold)
    return res
  end
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniVisits.config

-- Various timers
H.timers = {
  track = vim.uv.new_timer(),
}

-- Current visit index
H.index = {}

-- Various cache
H.cache = {
  -- Latest tracked path used to not autoregister same path in a row
  latest_tracked_path = nil,

  -- Whether index is yet to be read from the stored path, as it is not read
  -- right away delaying until it is absolutely necessary
  needs_index_read = true,

  -- Start time of this session to be used in `gen_filter.this_session`
  session_start_time = os.time(),
}

-- File system information
H.is_windows = vim.uv.os_uname().sysname == 'Windows_NT'

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  H.check_type('list', config.list, 'table')
  H.check_type('list.filter', config.list.filter, 'function', true)
  H.check_type('list.sort', config.list.sort, 'function', true)

  H.check_type('silent', config.silent, 'boolean')

  H.check_type('store', config.store, 'table')
  H.check_type('store.autowrite', config.store.autowrite, 'boolean')
  H.check_type('store.normalize', config.store.normalize, 'function', true)
  H.check_type('store.path', config.store.path, 'string')

  H.check_type('track', config.track, 'table')
  H.check_type('track.delay', config.track.delay, 'number')
  H.check_type('track.event', config.track.event, 'string')

  return config
end

H.apply_config = function(config) MiniVisits.config = config end

H.create_autocommands = function(config)
  local gr = vim.api.nvim_create_augroup('MiniVisits', {})

  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = gr, pattern = pattern, callback = callback, desc = desc })
  end

  if config.track.event ~= '' then au(config.track.event, '*', H.autoregister_visit, 'Auto register visit') end
  au('VimLeavePre', '*', function()
    if not H.get_config().store.autowrite then return end
    pcall(MiniVisits.write_index)
  end, 'Autowrite visit index')

  -- React to file manipulation with 'mini.files'
  au('User', { 'MiniFilesActionRename', 'MiniFilesActionMove' }, function(args)
    local cur_index = MiniVisits.get_index()
    local ok, new_index = pcall(MiniVisits.rename_in_index, args.data.from, args.data.to, cur_index)
    if not ok then return end
    MiniVisits.set_index(new_index)
  end, 'Rename in index')
end

H.is_disabled = function(buf_id)
  local buf_disable = H.get_buf_var(buf_id, 'minivisits_disable')
  return vim.g.minivisits_disable == true or buf_disable == true
end

H.get_config = function(config, buf_id)
  local buf_config = H.get_buf_var(buf_id, 'minivisits_config') or {}
  return vim.tbl_deep_extend('force', MiniVisits.config, buf_config, config or {})
end

H.get_buf_var = function(buf_id, name)
  if not H.is_valid_buf(buf_id) then return nil end
  return vim.b[buf_id or 0][name]
end

-- Autocommands ---------------------------------------------------------------
H.autoregister_visit = function(data)
  -- Recognize the register opportunity by stopping timer before check for
  -- disabling. This is important for `iterate_paths` functionality.
  H.timers.track:stop()
  local buf_id = data.buf
  if H.is_disabled(buf_id) then return end

  local f = vim.schedule_wrap(function()
    if H.is_disabled(buf_id) then return end

    -- Register only normal buffer if it is not the latest registered (avoids
    -- tracking visits from switching between normal and non-normal buffers)
    local path = H.buf_get_path(buf_id)
    if path == nil or path == H.cache.latest_tracked_path then return end

    local ok = pcall(MiniVisits.register_visit, path, vim.fn.getcwd())
    if not ok then return end

    H.cache.latest_tracked_path = path
  end)

  H.timers.track:start(H.get_config(nil, buf_id).track.delay, 0, f)
end

-- Visit index ----------------------------------------------------------------
H.ensure_read_index = function()
  if not H.cache.needs_index_read then return end

  -- Try reading previous index
  local ok, res_index = pcall(MiniVisits.read_index)
  if not ok then return end
  local is_index = pcall(H.validate_index, res_index)
  if not is_index then return end

  -- Merge current index with stored
  for cwd, cwd_tbl in pairs(H.index) do
    local cwd_tbl_res = res_index[cwd] or {}
    for path, path_tbl_new in pairs(cwd_tbl) do
      local path_tbl_res = cwd_tbl_res[path] or { count = 0, latest = 0 }
      cwd_tbl_res[path] = H.merge_path_tbls(path_tbl_res, path_tbl_new)
    end
    res_index[cwd] = cwd_tbl_res
  end

  H.index = res_index
  H.cache.needs_index_read = false
end

H.ensure_index_entry = function(path, cwd)
  local cwd_tbl = H.index[cwd] or {}
  cwd_tbl[path] = cwd_tbl[path] or { count = 0, latest = 0 }
  H.index[cwd] = cwd_tbl
end

H.resolve_path_cwd = function(path, cwd)
  H.ensure_read_index()

  -- Empty cwd means all available cwds
  local cwd_arr = cwd == '' and vim.tbl_keys(H.index) or { cwd }

  -- Empty path means all available paths in all target cwds
  if path ~= '' then
    return vim.tbl_map(function(x) return { path = path, cwd = x } end, cwd_arr)
  end

  local res = {}
  for _, d in ipairs(cwd_arr) do
    local cwd_tbl = H.index[d] or {}
    for p, _ in pairs(cwd_tbl) do
      table.insert(res, { path = p, cwd = d })
    end
  end
  return res
end

H.make_path_array = function(path, cwd)
  local index = MiniVisits.get_index()
  local path_tbl = {}
  for _, pair in ipairs(H.resolve_path_cwd(path, cwd)) do
    local path_tbl_to_merge = (index[pair.cwd] or {})[pair.path]
    if type(path_tbl_to_merge) == 'table' then
      local p = pair.path
      path_tbl[p] = path_tbl[p] or { path = p, count = 0, latest = 0 }
      path_tbl[p] = H.merge_path_tbls(path_tbl[p], path_tbl_to_merge)
    end
  end

  return vim.tbl_values(path_tbl)
end

H.merge_path_tbls = function(path_tbl_ref, path_tbl_new)
  local path_tbl = vim.tbl_deep_extend('force', path_tbl_ref, path_tbl_new)

  -- Add all counts together
  path_tbl.count = path_tbl_ref.count + path_tbl_new.count

  -- Compute the latest visit
  path_tbl.latest = math.max(path_tbl_ref.latest, path_tbl_new.latest)

  -- Labels should be already a proper union of both labels

  return path_tbl
end

H.index_prune = function(index, prune_paths, threshold)
  if type(threshold) ~= 'number' then H.error('Prune threshold should be number.') end

  -- Possibly prune non-path cwds
  for cwd, cwd_tbl in pairs(index) do
    if prune_paths and vim.fn.isdirectory(cwd) == 0 then index[cwd] = nil end
  end

  -- Prune on path level
  for cwd, cwd_tbl in pairs(index) do
    for path, path_tbl in pairs(cwd_tbl) do
      local should_prune_path = prune_paths and not (vim.fn.filereadable(path) == 1 or vim.fn.isdirectory(path) == 1)
      local should_prune = should_prune_path or path_tbl.count < threshold
      -- Don't prune if visit has labels (can happen if label was added
      -- manually without actual visit, thus `count = 0`)
      if path_tbl.labels == nil and should_prune then cwd_tbl[path] = nil end
    end
  end

  -- Remove possible cwd tables which were only with non-paths entries
  for cwd, cwd_tbl in pairs(index) do
    if vim.tbl_count(cwd_tbl) == 0 then index[cwd] = nil end
  end
end

H.index_decay_cwd = function(cwd_tbl, threshold, target)
  if type(threshold) ~= 'number' then H.error('Decay threshold should be number.') end
  if type(target) ~= 'number' then H.error('Decay target should be number.') end

  -- Decide whether to decay (if total count exceeds threshold)
  local total_count = 0
  for _, path_tbl in pairs(cwd_tbl) do
    total_count = total_count + path_tbl.count
  end
  if total_count == 0 or total_count <= threshold then return end

  -- Decay (multiply counts by coefficient to have total count equal target)
  local coef = target / total_count
  for _, path_tbl in pairs(cwd_tbl) do
    -- Round to preserve only two decimal places
    path_tbl.count = math.floor(100 * coef * path_tbl.count + 0.5) / 100
  end
end

H.get_label_from_user = function(prompt, labels_complete)
  MiniVisits._complete = function(arg_lead)
    return vim.tbl_filter(function(x) return x:find(arg_lead, 1, true) ~= nil end, labels_complete)
  end
  local completion = 'customlist,v:lua.MiniVisits._complete'
  local input_opts = { prompt = prompt .. ': ', completion = completion, cancelreturn = false }
  local ok, res = pcall(vim.fn.input, input_opts)
  MiniVisits._complete = nil
  if not ok or res == false then return nil end
  return res
end

-- Validators -----------------------------------------------------------------
H.validate_path = function(x)
  x = x or H.buf_get_path(vim.api.nvim_get_current_buf())
  if x == nil then H.error('Current buffer is not for a regular file') end
  H.validate_string(x, 'path')
  return x == '' and '' or H.full_path(x)
end

H.validate_cwd = function(x)
  x = x or vim.fn.getcwd()
  H.validate_string(x, 'cwd')
  return x == '' and '' or H.full_path(x)
end

H.validate_filter = function(x)
  x = x or MiniVisits.gen_filter.default()
  if type(x) == 'string' then
    local label = x
    x = function(path_data) return (path_data.labels or {})[label] end
  end
  if not vim.is_callable(x) then H.error('`filter` should be callable or string label name.') end
  return x
end

H.validate_sort = function(x)
  x = x or MiniVisits.gen_sort.default()
  if not vim.is_callable(x) then H.error('`sort` should be callable.') end
  return x
end

H.validate_index = function(x, name)
  name = name or '`index`'
  if type(x) ~= 'table' then H.error(name .. ' should be a table.') end
  for cwd, cwd_tbl in pairs(x) do
    if type(cwd) ~= 'string' then H.error('First level keys in ' .. name .. ' should be strings.') end
    if type(cwd_tbl) ~= 'table' then H.error('First level values in ' .. name .. ' should be tables.') end

    for path, path_tbl in pairs(cwd_tbl) do
      if type(path) ~= 'string' then H.error('Second level keys in ' .. name .. ' should be strings.') end
      if type(path_tbl) ~= 'table' then H.error('Second level values in ' .. name .. ' should be tables.') end

      if type(path_tbl.count) ~= 'number' then H.error('`count` entries in ' .. name .. ' should be numbers.') end
      if type(path_tbl.latest) ~= 'number' then H.error('`latest` entries in ' .. name .. ' should be numbers.') end

      H.validate_labels_field(path_tbl.labels)
    end
  end
end

H.validate_labels_field = function(x)
  if x == nil then return end
  if type(x) ~= 'table' then H.error('`labels` should be a table.') end

  for key, value in pairs(x) do
    if type(key) ~= 'string' then H.error('Keys in `labels` table should be strings.') end
    if value ~= true then H.error('Values in `labels` table should only be `true`.') end
  end
end

H.validate_string = function(x, name)
  if type(x) == 'string' then return x end
  H.error(string.format('`%s` should be string.', name))
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.visits) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.echo = function(msg)
  if H.get_config().silent then return end

  -- Construct message chunks
  msg = type(msg) == 'string' and { { msg } } or msg
  table.insert(msg, 1, { '(mini.visits) ', 'WarningMsg' })

  -- Echo. Force redraw to ensure that it is effective (`:h echo-redraw`)
  vim.cmd([[echo '' | redraw]])
  vim.api.nvim_echo(msg, false, {})
end

H.is_valid_buf = function(buf_id) return type(buf_id) == 'number' and vim.api.nvim_buf_is_valid(buf_id) end

H.buf_get_path = function(buf_id)
  -- Get path only for valid normal buffers
  if not (H.is_valid_buf(buf_id) and vim.bo[buf_id].buftype == '') then return nil end
  local res = H.full_path(vim.api.nvim_buf_get_name(buf_id))
  if res == '' then return end
  return res
end

H.tbl_add_rank = function(arr, key)
  local rank_key, ties = key .. '_rank', {}
  for i, tbl in ipairs(arr) do
    -- Assumes `arr` is an array of tables sorted from best to worst
    tbl[rank_key] = i

    -- Track ties
    if i > 1 and tbl[key] == arr[i - 1][key] then
      local val = tbl[key]
      local data = ties[val] or { n = 1, sum = i - 1 }
      data.n, data.sum = data.n + 1, data.sum + i
      ties[val] = data
    end
  end

  -- Correct for ties using mid-rank
  for i, tbl in ipairs(arr) do
    local tie_data = ties[tbl[key]]
    if tie_data ~= nil then tbl[rank_key] = tie_data.sum / tie_data.n end
  end
end

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

H.full_path = function(path) return (vim.fn.fnamemodify(path, ':p'):gsub('/+', '/'):gsub('(.)/$', '%1')) end
if H.is_windows then
  H.full_path = function(path)
    return (vim.fn.fnamemodify(path, ':p'):gsub('\\', '/'):gsub('/+', '/'):gsub('(.)/$', '%1'))
  end
end

H.short_path = function(path, cwd)
  cwd = cwd or vim.fn.getcwd()
  -- Ensure `cwd` is treated as directory path (to not match similar prefix)
  cwd = cwd:sub(-1) == '/' and cwd or (cwd .. '/')
  if vim.startswith(path, cwd) then return path:sub(cwd:len() + 1) end
  local res = vim.fn.fnamemodify(path, ':~')
  if H.is_windows then res = res:gsub('\\', '/') end
  return res
end

return MiniVisits
