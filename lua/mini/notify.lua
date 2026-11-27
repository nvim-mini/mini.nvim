--- *mini.notify* Show notifications
---
--- MIT License Copyright (c) 2024 Evgeni Chasnovski

--- Features:
---
--- - Show one or more highlighted notifications in a single floating window.
---   Messages can be multicolor.
---
--- - Manage notifications (add, update, remove, clear).
---
--- - Custom |vim.notify()| implementation. To adjust, use |MiniNotify.make_notify()|
---   or save-restore `vim.notify` manually after calling |MiniNotify.setup()|.
---
--- - Automated show of LSP progress report.
---
--- - Track history which can be accessed with |MiniNotify.get_all()|
---   and shown with |MiniNotify.show_history()|.
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.notify').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `MiniNotify`
--- which you can use for scripting or manually (with `:lua MiniNotify.*`).
---
--- See |MiniNotify.config| for `config` structure and default values.
---
--- You can override runtime config settings locally to buffer inside
--- `vim.b.mininotify_config` which should have same structure as
--- `MiniNotify.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- # Comparisons ~
---
--- - [j-hui/fidget.nvim](https://github.com/j-hui/fidget.nvim):
---     - Basic goals of providing interface for notifications are similar.
---     - Has more configuration options and visual effects, while this module
---       does not (by design).
---
--- - [rcarriga/nvim-notify](https://github.com/rcarriga/nvim-notify):
---     - Similar to `j-hui/fidget.nvim`.
---
--- # Highlight groups ~
--- *MiniNotify-hl-groups*
---
--- - `MiniNotifyBorder` - window border.
--- - `MiniNotifyLspProgress` - notifications from built-in LSP progress report.
--- - `MiniNotifyNormal` - basic foreground/background highlighting.
--- - `MiniNotifyNvimProgress` - notifications from built-in Neovim progress report.
--- - `MiniNotifyTitle` - window title.
---
--- To change any highlight group, set it directly with |nvim_set_hl()|.
---
--- NOTE: |vim.notify()| override after |MiniNotify.make_notify()| uses own
--- highlight groups per notification level.
---
--- # Disabling ~
---
--- To disable showing notifications, set `vim.g.mininotify_disable` (globally) or
--- `vim.b.mininotify_disable` (for a buffer) to `true`. Considering high number
--- of different scenarios and customization intentions, writing exact rules
--- for disabling module's functionality is left to user. See
--- |mini.nvim-disabling-recipes| for common recipes.
---@tag MiniNotify

--- # Notification specification ~
---
--- Notification is a table with the following keys:
---
--- - <msg> `(string)` - notification message in one of the forms:
---   - Single string with `\n` delimiting several lines. Use for simple messages.
---   - Array of "text-hl chunk" lines, as `virt_lines` in |nvim_buf_set_extmark()|.
---     Text in chunk is required, highlight group is optional. Chunk with
---     empty string as text at the end of line will add highlighting till the
---     end of visible line. Chunk highlighting will be applied on top of the
---     whole message `hl_group` group supplied in |MiniNotify.add()|.
---     Use for multicolor messages. Example:
---     `{ { { 'Line ' }, { '#1', 'Bold' } }, {}, { { 'Line #3', 'Italic' } } }`
--- - <level> `(string)` - notification level as key of |vim.log.levels|.
---   Like "ERROR", "WARN", "INFO", etc.
--- - <hl_group> `(string)` - highlight group with which notification is shown.
--- - <data> `(table)` - extra data to store in notification (like `source`, etc.).
--- - <ts_add> `(number)` - timestamp of when notification is added.
--- - <ts_update> `(number)` - timestamp of the latest notification update.
--- - <ts_remove> `(number|nil)` - timestamp of when notification is removed.
---   It is `nil` if notification was never removed and thus considered "active".
---
--- Notes:
--- - Timestamps are compatible with |strftime()| and have fractional part.
---@tag MiniNotify-specification

--- To allow user customization, there are the following |User| autocommand events:
---
--- - `MiniNotifyWindowOpen` - after opening a notification window.
--- - `MiniNotifyWindowUpdate` - after updating an existing notification window.
---
--- Each event's |event-data| table contains `win_id` (window identifier) field.
--- The window is also made current for the duration of events.
---
--- Example usage: >lua
---
---   -- Tweak appearance via options of the notification window
---   vim.cmd('au User MiniNotifyWindowOpen setlocal winblend=50 wrap')
--- <
---@tag MiniNotify-events

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local
---@diagnostic disable:cast-local-type
---@diagnostic disable:undefined-doc-name
---@diagnostic disable:luadoc-miss-type-name

-- Module definition ==========================================================
local MiniNotify = {}
local H = {}

--- Module setup
---
--- This will also:
--- - Set |vim.notify()| custom implementation (see |MiniNotify.make_notify()|).
--- - Clean the history. Use `MiniNotify.setup(MiniNotify.config)` to force
---   clean history while preserving the config.
---
---@param config table|nil Module config table. See |MiniNotify.config|.
---
---@usage >lua
---   require('mini.notify').setup() -- use default config
---   -- OR
---   require('mini.notify').setup({}) -- replace {} with your config table
--- <
MiniNotify.setup = function(config)
  -- Export module
  _G.MiniNotify = MiniNotify

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Define behavior
  H.create_autocommands()

  -- Create default highlighting
  H.create_default_hl()

  -- Set custom implementation
  vim.notify = MiniNotify.make_notify()
end

--- Defaults ~
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text # Content ~
---
--- `config.content` defines how notifications are shown.
---
--- `content.format` is a function which takes single notification object
--- (see |MiniNotify-specification|) and returns a string to be used directly
--- when showing notification.
--- Default: `nil` for |MiniNotify.default_format()|.
---
--- `content.sort` is a function which takes array of notification objects
--- (see |MiniNotify-specification|) and returns an array of such objects.
--- It can be used to define custom order and/or filter for notifications which
--- are shown simultaneously.
--- Note: Input contains notifications before applying `content.format`.
--- Default: `nil` for |MiniNotify.default_sort()|.
---
--- Example: >lua
---
---   local compare_update = function(a, b) return a.ts_update > b.ts_update end
---   require('mini.notify').setup({
---     content = {
---       -- Use notification message as is for LSP progress
---       format = function(notif)
---         if notif.data.source == 'lsp_progress' then return notif.msg end
---         return MiniNotify.default_format(notif)
---       end,
---
---       -- Show more recently updates notifications first
---       sort = function(notif_arr)
---         table.sort(notif_arr, compare_update)
---         return notif_arr
---       end,
---     },
---   })
--- <
--- # LSP progress ~
---
--- `config.lsp_progress` defines automated notifications for LSP progress.
--- It is implemented as a single updating notification per progress with all
--- information about it.
--- Setting up is done inside |MiniNotify.setup()| via scheduled (|vim.schedule()|)
--- setting of |lsp-handler| for "$/progress" method.
---
--- `lsp_progress.enable` is a boolean indicating whether LSP progress should
--- be shown in notifications. Can be disabled in current session.
--- Default: `true`. Note: Should be `true` during |MiniNotify.setup()| call to be able
--- to enable it in current session.
---
--- `lsp_progress.level` is a level to be used in |MiniNotify.add()|.
--- Default: `'INFO'`.
---
--- `lsp_progress.duration_last` is a number of milliseconds for the last progress
--- report to be shown on screen before removing it.
--- Default: 1000.
---
--- Notes:
--- - This respects previously set handler by saving and calling it.
--- - Overriding "$/progress" method of `vim.lsp.handlers` disables notifications.
--- - All LSP progress notifications set the following fields in `data`:
---     - <source> is `"lsp_progress"`.
---     - <client_name> is set to client's name (provided by client or inferred).
---     - <context> is the latest LSP request context (`ctx` arg of |lsp-handler|).
---     - <response> is the latest LSP response (`result` arg of |lsp-handler|).
---
--- # Window ~
---
--- `config.window` defines behavior of notification window.
---
--- `window.config` is a table defining floating window characteristics
--- or a callable returning such table (will be called with identifier of
--- window's buffer already showing notifications). It should have the same
--- structure as in |nvim_open_win()|. It has the following default values
--- which show notifications in the upper right corner with upper limit on width:
--- - `width` is chosen to fit buffer content but at most `window.max_width_share`
---   share of |'columns'|. To reduce flicker with intensive progress updates, it
---   also doesn't decrease for a visible window after notification changes.
---   To have higher maximum width, use function in `config.window` which computes
---   dimensions inside of it (based on buffer content).
--- - `height` is chosen to fit buffer content.
--- - `anchor`, `col`, and `row` are "NE", |'columns'|, and 0 or 1 (depending on tabline).
--- - `border` is "single".
--- - `zindex` is 999 to be as much on top as reasonably possible.
---
--- `window.max_width_share` defines maximum window width as a share of |'columns'|.
--- Should be a number between 0 (not included) and 1.
--- Default: 0.382.
---
--- Example for showing notifications in bottom right corner: >lua
---
---   local win_config = function()
---     local has_statusline = vim.o.laststatus > 0
---     local pad = vim.o.cmdheight + (has_statusline and 1 or 0)
---     return { anchor = 'SE', col = vim.o.columns, row = vim.o.lines - pad }
---   end
---   require('mini.notify').setup({ window = { config = win_config } })
--- <
--- Notes:
--- - To improve usability, some window options (like |'winblend'| and |'wrap'|) are
---   have specific values that may differ from global. To customize them, use
---   a dedicated autocommand as described in `:h MiniNotify-events`. To look at
---   missing or missed parts of the message, use |MiniNotify.show_history()|.
MiniNotify.config = {
  -- Content management
  content = {
    -- Function which formats the notification message
    -- By default prepends message with notification time
    format = nil,

    -- Function which orders notification array from most to least important
    -- By default orders first by level and then by update timestamp
    sort = nil,
  },

  -- Notifications about LSP progress
  lsp_progress = {
    -- Whether to enable showing
    enable = true,

    -- Notification level
    level = 'INFO',

    -- Duration (in ms) of how long last message should be shown
    duration_last = 1000,
  },

  -- Notifications about Neovim controlled progress
  nvim_progress = {
    -- Whether to enable showing
    enable = true,

    -- Notification level
    level = 'INFO',

    -- Duration (in ms) of how long last message should be shown
    duration_last = 1000,
  },

  -- Window options
  window = {
    -- Floating window config
    config = {},

    -- Maximum window width as share (between 0 and 1) of available columns
    max_width_share = 0.382,
  },
}
--minidoc_afterlines_end

--- Make vim.notify wrapper
---
--- Calling this function creates an implementation of |vim.notify()| powered by
--- this module. General idea is to show notification as soon as safely possible
--- (see |vim.schedule_wrap()|) and remove it after a configurable amount of time.
---
--- All notifications set `source = "vim.notify"` in their `data` field.
---
--- This is used with default options inside |MiniNotify.setup()|. To adjust,
--- call manually after `setup()`. For example, to show errors longer: >lua
---
---   require('mini.notify').setup()
---   vim.notify = MiniNotify.make_notify({ ERROR = { duration = 10000 } })
--- <
--- To preserve original `vim.notify`: >lua
---
---   local notify_orig = vim.notify
---   require('mini.notify').setup()
---   vim.notify = notify_orig
--- <
---@param opts table|nil Options to configure behavior of notification `level`
---   (as in |MiniNotify.add()|). Fields are the same as names of `vim.log.levels`
---   with values being tables with possible fields:
---   - <duration> `(number)` - duration (in ms) of how much a notification
---     should be shown. If 0 or negative, notification is not shown at all.
---   - <hl_group> `(string)` - highlight group of notification.
---   Only data different to default can be supplied.
---
---   Default: >lua
---
---   {
---     ERROR = { duration = 5000, hl_group = 'DiagnosticError'  },
---     WARN  = { duration = 5000, hl_group = 'DiagnosticWarn'   },
---     INFO  = { duration = 5000, hl_group = 'DiagnosticInfo'   },
---     DEBUG = { duration = 0,    hl_group = 'DiagnosticHint'   },
---     TRACE = { duration = 0,    hl_group = 'DiagnosticOk'     },
---     OFF   = { duration = 0,    hl_group = 'MiniNotifyNormal' },
---   }
--- <
MiniNotify.make_notify = function(opts)
  local level_names = {}
  for k, v in pairs(vim.log.levels) do
    level_names[v] = k
  end

  --stylua: ignore
  local default_opts = {
    ERROR = { duration = 5000, hl_group = 'DiagnosticError'  },
    WARN  = { duration = 5000, hl_group = 'DiagnosticWarn'   },
    INFO  = { duration = 5000, hl_group = 'DiagnosticInfo'   },
    DEBUG = { duration = 0,    hl_group = 'DiagnosticHint'   },
    TRACE = { duration = 0,    hl_group = 'DiagnosticOk'     },
    OFF   = { duration = 0,    hl_group = 'MiniNotifyNormal' },
  }
  opts = vim.tbl_deep_extend('force', default_opts, opts or {})

  for key, val in pairs(opts) do
    if default_opts[key] == nil then H.error('Keys should be log level names.') end
    if type(val) ~= 'table' then H.error('Level data should be table.') end
    if type(val.duration) ~= 'number' then H.error('`duration` in level data should be number.') end
    if type(val.hl_group) ~= 'string' then H.error('`hl_group` in level data should be string.') end
  end

  return vim.schedule_wrap(function(msg, level)
    level = level or vim.log.levels.INFO
    local level_name = level_names[level]
    if level_name == nil then H.error('Only valid values of `vim.log.levels` are supported.') end

    local level_data = opts[level_name]
    if level_data.duration <= 0 then return end

    local id = MiniNotify.add(msg, level_name, level_data.hl_group, { source = 'vim.notify' })
    vim.defer_fn(function() MiniNotify.remove(id) end, level_data.duration)
  end)
end

--- Add notification
---
--- Add notification to history. It is considered "active" and is shown.
--- To hide, call |MiniNotify.remove()| with identifier this function returns.
---
--- Example: >lua
---
---   local id = MiniNotify.add('Hello', 'WARN', 'Comment')
---   vim.defer_fn(function() MiniNotify.remove(id) end, 1000)
--- <
---@param msg string|table Notification message. See |MiniNotify-specification|.
---@param level string|nil Notification level as key of |vim.log.levels|.
---   Default: `'INFO'`.
---@param hl_group string|nil Base notification highlight group. Will be applied to
---   the whole notification message. Default: `'MiniNotifyNormal'`.
---@param data table|nil Extra data to store in the notification.
---   Default: `{}`.
---
---@return number Notification identifier.
MiniNotify.add = function(msg, level, hl_group, data)
  H.validate_msg(msg)
  level = level or 'INFO'
  H.validate_level(level)
  hl_group = hl_group or 'MiniNotifyNormal'
  H.validate_hl_group(hl_group)
  data = data or {}
  H.check_type('data', data, 'table')

  local cur_ts = H.get_timestamp()
  local new_notif = { msg = msg, level = level, hl_group = hl_group, ts_add = cur_ts, ts_update = cur_ts, data = data }

  local new_id = #H.history + 1
  -- NOTE: Crucial to use the same table here and later only update values
  -- inside of it in place. This makes sure that history entries are in sync.
  H.history[new_id], H.active[new_id] = new_notif, new_notif

  -- Refresh active notifications
  MiniNotify.refresh()

  return new_id
end

--- Update active notification
---
--- Modify contents of active notification.
---
---@param id number Identifier of currently active notification as returned
---   by |MiniNotify.add()|.
---@param new table Table with contents to update. Keys should be as non-timestamp
---   fields of |MiniNotify-specification| and values - new content values.
---   If present, field `data` is updated as is. Use |MiniNotify.get()| together
---   with |vim.tbl_deep_extend()| to change only part of it.
MiniNotify.update = function(id, new)
  local notif = H.active[id]
  if notif == nil then H.error('`id` is not an identifier of active notification.') end
  H.check_type('new', new, 'table')

  if new.msg ~= nil then H.validate_msg(new.msg) end
  if new.level ~= nil then H.validate_level(new.level) end
  if new.hl_group ~= nil then H.validate_hl_group(new.hl_group) end
  H.check_type('data', new.data, 'table', true)

  notif.msg = new.msg or notif.msg
  notif.level = new.level or notif.level
  notif.hl_group = new.hl_group or notif.hl_group
  notif.data = new.data or notif.data
  notif.ts_update = H.get_timestamp()

  MiniNotify.refresh()
end

--- Remove notification
---
--- If notification is active, make it not active (by setting `ts_remove` field).
--- If not active, do nothing.
---
---@param id number|nil Identifier of previously added notification.
---   If it is not, nothing is done (silently).
MiniNotify.remove = function(id)
  local notif = H.active[id]
  if notif == nil then return end
  notif.ts_remove = H.get_timestamp()
  H.active[id] = nil

  MiniNotify.refresh()
end

--- Remove all active notifications
---
--- Hide all active notifications and stop showing window (if shown).
MiniNotify.clear = function()
  local cur_ts = H.get_timestamp()
  for id, _ in pairs(H.active) do
    H.active[id].ts_remove = cur_ts
  end
  H.active = {}

  MiniNotify.refresh()
end

--- Refresh notification window
---
--- Make notification window show relevant information:
--- - Create an array of active notifications (see |MiniNotify-specification|).
--- - Apply `config.content.sort` to an array. If output has zero notifications,
---   make notification window to not show.
--- - Apply `config.content.format` to each element of notification array and
---   update its message.
--- - Construct content from notifications and show them in a window.
---
--- Note: effects are delayed if inside fast event (|vim.in_fast_event()|).
MiniNotify.refresh = function()
  if vim.in_fast_event() then return vim.schedule(MiniNotify.refresh) end
  if H.is_textlock() then
    pcall(vim.api.nvim_del_autocmd, H.cache.safestate_au_id)
    local au_opts = { once = true, nested = true, callback = vim.schedule_wrap(MiniNotify.refresh) }
    H.cache.safestate_au_id = vim.api.nvim_create_autocmd('SafeState', au_opts)
    return
  end
  if H.is_disabled() or type(vim.v.exiting) == 'number' then return H.window_close() end

  -- Prepare array of active notifications
  local notif_arr = vim.deepcopy(vim.tbl_values(H.active))
  local config_content = H.get_config().content

  local sort = vim.is_callable(config_content.sort) and config_content.sort or MiniNotify.default_sort
  notif_arr = sort(notif_arr)
  if not H.is_notification_array(notif_arr) then H.error('Output of `content.sort` should be notification array.') end
  if #notif_arr == 0 then return H.window_close() end

  local format = vim.is_callable(config_content.format) and config_content.format or MiniNotify.default_format
  notif_arr = H.notif_apply_format(notif_arr, format)

  -- Refresh buffer
  local buf_id = H.cache.buf_id
  if not H.is_loaded_buf(buf_id) then buf_id = H.buffer_create(buf_id) end
  H.buffer_refresh(buf_id, notif_arr)

  -- Refresh window
  local win_id = H.cache.win_id
  if not (H.is_valid_win(win_id) and H.is_win_in_tabpage(win_id)) then
    H.window_close()
    win_id = H.window_open(buf_id)
    H.window_trigger_event(win_id, 'MiniNotifyWindowOpen')
  end

  vim.api.nvim_win_set_config(win_id, H.window_compute_config(win_id, buf_id))
  H.window_trigger_event(win_id, 'MiniNotifyWindowUpdate')

  -- Redraw
  vim.cmd('redraw')

  -- Update cache
  H.cache.buf_id, H.cache.win_id = buf_id, win_id
end

--- Get previously added notification by id
---
---@param id number Identifier of notification.
---
---@return table Notification object (see |MiniNotify-specification|).
MiniNotify.get = function(id) return vim.deepcopy(H.history[id]) end

--- Get all previously added notifications
---
--- Get map of used notifications with keys being notification identifiers.
---
--- Can be used to get only active notification objects. Example: >lua
---
---   -- Get active notifications
---   vim.tbl_filter(
---     function(notif) return notif.ts_remove == nil end,
---     MiniNotify.get_all()
---   )
--- <
---@return table Map with notification object values (see |MiniNotify-specification|).
---   Note: messages are taken from last valid update.
MiniNotify.get_all = function() return vim.deepcopy(H.history) end

--- Show history
---
--- Open or reuse a scratch buffer with all previously shown notifications.
---
--- Notes:
--- - Content is ordered from oldest to newest based on latest update time.
--- - Message is formatted with `config.content.format`.
MiniNotify.show_history = function()
  -- Prepare content
  local config_content = H.get_config().content
  local notif_arr = MiniNotify.get_all()
  table.sort(notif_arr, function(a, b) return a.ts_update < b.ts_update end)
  local format = vim.is_callable(config_content.format) and config_content.format or MiniNotify.default_format
  notif_arr = H.notif_apply_format(notif_arr, format)

  -- Show content in a reusable buffer
  local buf_id
  for _, id in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[id].filetype == 'mininotify-history' then buf_id = id end
  end
  if buf_id == nil then
    buf_id = vim.api.nvim_create_buf(true, true)
    H.set_buf_name(buf_id, 'history')
    vim.bo[buf_id].modifiable = true
    vim.bo[buf_id].filetype = 'mininotify-history'
  end
  H.buffer_refresh(buf_id, notif_arr)
  vim.api.nvim_win_set_buf(0, buf_id)
end

--- Default content format
---
--- Used by default as `config.content.format`. Prepends every notification message
--- line with a prefix (human readable time and equal size whitespace) and
--- a continuous vertical separator.
---
---@param notif table Notification object (see |MiniNotify-specification|).
---
---@return string|table Formatted notification message of the same type as in input.
MiniNotify.default_format = function(notif)
  local time = vim.fn.strftime('%H:%M:%S', math.floor(notif.ts_update)) .. '│ '
  local indent = string.rep(' ', vim.fn.strdisplaywidth(time) - 2) .. '│ '
  if type(notif.msg) == 'string' then return time .. notif.msg:gsub('\n', '\n' .. indent) end

  -- Prepend with relevant chunks and reconstruct the copy (for performance)
  local new_msg = { { { time } } }
  for i = 2, #notif.msg do
    new_msg[i] = { { indent } }
  end
  for i = 1, #notif.msg do
    for j = 1, #notif.msg[i] do
      new_msg[i][j + 1] = { notif.msg[i][j][1], notif.msg[i][j][2] }
    end
  end
  return new_msg
end

--- Default content sort
---
--- Used by default as `config.content.sort`. First sorts by notification's `level`
--- ("ERROR" > "WARN" > "INFO" > "DEBUG" > "TRACE" > "OFF"; the bigger the more
--- important); if draw - by latest add time (the later the more important).
---
---@param notif_arr table Array of notifications (see |MiniNotify-specification|).
---
---@return table Sorted array of notifications.
MiniNotify.default_sort = function(notif_arr)
  local res = vim.deepcopy(notif_arr)
  table.sort(res, H.notif_compare)
  return res
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniNotify.config

-- Map of currently active notifications with their id as key
H.active = {}

-- History of all notifications in order they are created
H.history = {}

-- Maps of progress process id to notification content
H.lsp_progress = {}
H.nvim_progress = {}

-- Priorities of levels
H.level_priority = { ERROR = 6, WARN = 5, INFO = 4, DEBUG = 3, TRACE = 2, OFF = 1 }

-- Namespaces
H.ns_id = {
  highlight = vim.api.nvim_create_namespace('MiniNotifyHighlight'),
}

-- Various cache
H.cache = {
  -- Notification buffer and window
  buf_id = nil,
  win_id = nil,
  -- Scratch buffer to test if the editor is in textlock state
  textlock_buf_id = nil,
  -- Autocommand identifier when delaying until `SafeState`
  safestate_au_id = nil,
}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  H.check_type('content', config.content, 'table')
  H.check_type('content.format', config.content.format, 'function', true)
  H.check_type('content.sort', config.content.sort, 'function', true)

  H.check_type('lsp_progress', config.lsp_progress, 'table')
  H.check_type('lsp_progress.enable', config.lsp_progress.enable, 'boolean')
  H.validate_level(config.lsp_progress.level, 'config.lsp_progress.level')
  H.check_type('lsp_progress.duration_last', config.lsp_progress.duration_last, 'number')

  H.check_type('nvim_progress', config.nvim_progress, 'table')
  H.check_type('nvim_progress.enable', config.nvim_progress.enable, 'boolean')
  H.validate_level(config.nvim_progress.level, 'config.nvim_progress.level')
  H.check_type('nvim_progress.duration_last', config.nvim_progress.duration_last, 'number')

  H.check_type('window', config.window, 'table')
  if not (type(config.window.config) == 'table' or vim.is_callable(config.window.config)) then
    H.error('`window.config` should table or callable, not ' .. type(config.window.config))
  end
  H.check_type('window.max_width_share', config.window.max_width_share, 'number')

  return config
end

H.apply_config = function(config)
  MiniNotify.config = config

  if config.lsp_progress.enable then
    -- Use `vim.schedule` to reduce startup time (sourcing `vim.lsp` is costly)
    vim.schedule(function()
      -- Cache original handler only once (to avoid infinite loop)
      if vim.lsp.handlers['$/progress before mini.notify'] == nil then
        vim.lsp.handlers['$/progress before mini.notify'] = vim.lsp.handlers['$/progress']
      end

      vim.lsp.handlers['$/progress'] = H.lsp_progress_handler
    end)
  end

  if config.nvim_progress.enable and vim.fn.has('nvim-0.12') == 1 then
    vim.cmd('set messagesopt+=progress:')

    local gr = vim.api.nvim_create_augroup('MiniNotifyNvimProgress', {})
    local desc = 'Handle Neovim progress'
    vim.api.nvim_create_autocmd('Progress', { group = gr, callback = H.nvim_progress_handler, desc = desc })
  end

  -- Clean history
  if #H.history > 0 then MiniNotify.clear() end
  H.history = {}
end

H.create_autocommands = function()
  local gr = vim.api.nvim_create_augroup('MiniNotify', {})

  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = gr, pattern = pattern, callback = callback, desc = desc })
  end

  au({ 'TabEnter', 'VimResized' }, '*', function()
    H.window_close()
    MiniNotify.refresh()
  end, 'Refresh notifications')
  au('ColorScheme', '*', H.create_default_hl, 'Ensure colors')

  -- TODO: Remove after releasing 'mini.nvim' 0.20.0
  if type(MiniNotify.config.window.winblend) == 'number' then
    local set_winblend = function() vim.wo.winblend = MiniNotify.config.window.winblend end
    au('User', 'MiniNotifyWindowOpen', set_winblend, "Ensure window 'winblend'")
    local msg = '(mini.notify) `config.window.winblend` is soft deprecated in favor of'
      .. ' using dedicated `:h MiniNotify-events`.'
      .. ' This config setting works for now, but will be fully removed after the next release.'
      .. ' Sorry for the inconvenience.'
    vim.schedule(function() vim.notify(msg, vim.log.levels.WARN) end)
  end
end

--stylua: ignore
H.create_default_hl = function()
  local hi = function(name, opts)
    opts.default = true
    vim.api.nvim_set_hl(0, name, opts)
  end

  hi('MiniNotifyBorder', { link = 'FloatBorder' })
  hi('MiniNotifyLspProgress', { link = 'MiniNotifyNormal' })
  hi('MiniNotifyNormal', { link = 'NormalFloat' })
  hi('MiniNotifyNvimProgress', { link = 'MiniNotifyNormal' })
  hi('MiniNotifyTitle',  { link = 'FloatTitle'  })
end

H.is_disabled = function() return vim.g.mininotify_disable == true or vim.b.mininotify_disable == true end

H.get_config = function(config)
  return vim.tbl_deep_extend('force', MiniNotify.config, vim.b.mininotify_config or {}, config or {})
end

-- Progress handlers ----------------------------------------------------------
H.lsp_progress_handler = function(err, result, ctx, config)
  -- Make basic response processing. First call original LSP handler.
  -- It is crucial to not override `LspProgress` event.
  if vim.is_callable(vim.lsp.handlers['$/progress before mini.notify']) then
    vim.lsp.handlers['$/progress before mini.notify'](err, result, ctx, config)
  end

  local lsp_progress_config = H.get_config().lsp_progress
  if not lsp_progress_config.enable then return end

  if err ~= nil then return vim.notify(vim.inspect(err), vim.log.levels.ERROR) end
  if not (type(result) == 'table' and type(result.value) == 'table') then return end
  local value = result.value

  local client = vim.lsp.get_client_by_id(ctx.client_id)
  if client == nil then return end

  -- Construct LSP progress id
  local buf_id = ctx.bufnr or 'nil'
  local lsp_progress_id = buf_id .. client.id .. (result.token or '')
  local progress_info = H.lsp_progress[lsp_progress_id] or {}
  local data = { source = 'lsp_progress', client_name = client.name, response = result, context = ctx }

  -- Store percentage to be used if no new one was sent
  progress_info.percentage = (value.kind == 'end' and 100 or value.percentage) or progress_info.percentage or 0

  -- Cache title because it is only supplied on 'begin'
  if value.kind == 'begin' then progress_info.title = value.title end

  -- Make message
  local title, message = progress_info.title or '', value.message or ''
  local mid = (title == '' or message == '') and '' or ' '
  local msg = string.format('%3d%% %s: %s%s%s', progress_info.percentage, client.name, title, mid, message)

  -- Check for valid history entry as `setup()` might have removed the id
  if H.history[progress_info.notif_id] == nil then
    progress_info.notif_id = MiniNotify.add(msg, lsp_progress_config.level, 'MiniNotifyLspProgress', data)
  else
    MiniNotify.update(progress_info.notif_id, { msg = msg, data = data })
  end

  -- Cache progress info
  H.lsp_progress[lsp_progress_id] = progress_info

  -- Hide notification after last update to reduce flicker
  if value.kind == 'end' then
    H.lsp_progress[lsp_progress_id] = nil
    local delay = math.max(lsp_progress_config.duration_last, 0)
    vim.defer_fn(function() MiniNotify.remove(progress_info.notif_id) end, delay)
  end
end

H.nvim_progress_handler = function(ev)
  local nvim_progress_config = H.get_config().nvim_progress
  if not nvim_progress_config.enable then return end

  -- Store important data that can be supplied once
  local progress_info = H.nvim_progress[ev.data.id] or {}
  progress_info.percent = ev.data.percent or progress_info.percent or 0
  progress_info.source = ev.data.source or progress_info.source or ''
  progress_info.title = ev.data.title or progress_info.title or ''
  progress_info.is_finished = false

  -- Make message
  local status = H.nvim_status_to_notify_status[ev.data.status]
  local prefix = status == 'busy' and string.format('%3d%%', progress_info.percent) or status
  local source = progress_info.source
  local title = progress_info.title == source and '' or progress_info.title
  local text = table.concat(ev.data.text or {})
  local mid = (title == '' or text == '') and '' or ' '
  local msg = string.format('%s %s %s%s%s', prefix, source, title, mid, text)

  -- Check for valid history entry as `setup()` might have removed the id
  local data = { source = 'nvim_progress', event_data = ev.data }
  if H.history[progress_info.notif_id] == nil then
    progress_info.notif_id = MiniNotify.add(msg, nvim_progress_config.level, 'MiniNotifyNvimProgress', data)
  else
    MiniNotify.update(progress_info.notif_id, { msg = msg, data = data })
  end

  -- Cache progress info
  H.nvim_progress[ev.data.id] = progress_info

  -- Hide after last update or reaching 100% (avoids "dangling" progress)
  if not progress_info.is_finished and (ev.data.status ~= 'running' or progress_info.percent == 100) then
    progress_info.is_finished = true
    vim.defer_fn(function()
      if not progress_info.is_finished then return end
      H.nvim_progress[ev.data.id] = nil
      pcall(MiniNotify.remove, progress_info.notif_id)
    end, math.max(nvim_progress_config.duration_last, 0))
  end
end

H.nvim_status_to_notify_status = { cancel = 'stop', failed = 'fail', running = 'busy', success = 'done' }

-- Buffer ---------------------------------------------------------------------
H.buffer_create = function(prev_buf_id)
  pcall(vim.api.nvim_buf_delete, prev_buf_id, { force = true })
  local buf_id = vim.api.nvim_create_buf(false, true)
  H.set_buf_name(buf_id, 'content')
  vim.bo[buf_id].modifiable = true
  vim.bo[buf_id].filetype = 'mininotify'
  return buf_id
end

H.buffer_refresh = function(buf_id, notif_arr)
  local ns_id = H.ns_id.highlight

  -- Ensure clear buffer
  vim.api.nvim_buf_clear_namespace(buf_id, ns_id, 0, -1)
  vim.api.nvim_buf_set_lines(buf_id, 0, -1, true, {})

  -- Compute+set lines+highlight
  local lines, highlights = {}, {}
  for _, notif in ipairs(notif_arr) do
    H.append_msg_line_and_hl(notif, lines, highlights)
  end

  vim.api.nvim_buf_set_lines(buf_id, 0, -1, true, lines)
  for _, hi_data in ipairs(highlights) do
    hi_data[3].hl_eol, hi_data[3].hl_mode = true, 'combine'
    vim.api.nvim_buf_set_extmark(buf_id, ns_id, hi_data[1], hi_data[2], hi_data[3])
  end
end

H.buffer_default_width = function(buf_id, max_width_share)
  -- Compute width so as to fit all lines
  local width = 1
  for _, l in ipairs(vim.api.nvim_buf_get_lines(buf_id, 0, -1, true)) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  -- - Limit from above for better visuals
  max_width_share = math.min(math.max(max_width_share, 0), 1)
  local max_width = math.max(math.floor(max_width_share * vim.o.columns), 1)
  return math.min(width, max_width)
end

H.append_msg_line_and_hl = function(notif, lines, highlights)
  local n_lines = #lines
  if type(notif.msg) == 'string' then
    vim.list_extend(lines, vim.split(notif.msg, '\n'))
  else
    for i, ch_line in ipairs(notif.msg) do
      local l, old_w, cur_w = {}, 0, 0
      local row, n_ch_line = #lines, #ch_line
      for j, ch in ipairs(ch_line) do
        table.insert(l, ch[1])
        old_w, cur_w = cur_w, cur_w + ch[1]:len()

        local is_last_empty = ch[1] == '' and j == n_ch_line
        local end_row = is_last_empty and (row + 1) or row
        local end_col = is_last_empty and 0 or cur_w
        local ext_opts = { end_row = end_row, end_col = end_col, hl_group = ch[2], priority = 102 }
        table.insert(highlights, { row, old_w, ext_opts })
      end
      table.insert(lines, table.concat(l))
    end
  end

  local ext_opts = { end_row = #lines, end_col = 0, hl_group = notif.hl_group, priority = 101 }
  table.insert(highlights, { n_lines, 0, ext_opts })
end

-- Window ---------------------------------------------------------------------
H.window_open = function(buf_id)
  local config = H.window_compute_config(nil, buf_id)
  local win_id = vim.api.nvim_open_win(buf_id, false, config)

  vim.wo[win_id].foldenable = false
  vim.wo[win_id].foldmethod = 'manual'
  vim.wo[win_id].list = vim.go.list
  vim.wo[win_id].listchars = vim.go.listchars
  -- TODO: Modify after releasing 'mini.nvim' 0.20.0
  vim.wo[win_id].winblend = H.get_config().window.winblend or 25
  vim.wo[win_id].winhighlight = 'NormalFloat:MiniNotifyNormal,FloatBorder:MiniNotifyBorder,FloatTitle:MiniNotifyTitle'
  vim.wo[win_id].wrap = false

  return win_id
end

H.window_compute_config = function(win_id, buf_id)
  local has_tabline = vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1)
  local has_statusline = vim.o.laststatus > 0
  local max_height = vim.o.lines - vim.o.cmdheight - (has_tabline and 1 or 0) - (has_statusline and 1 or 0)
  local max_width = vim.o.columns

  -- Default config
  local config_win = H.get_config().window
  local default_config = { relative = 'editor', style = 'minimal', zindex = 999 }
  default_config.anchor, default_config.col, default_config.row = 'NE', vim.o.columns, has_tabline and 1 or 0
  default_config.width = H.buffer_default_width(buf_id, config_win.max_width_share)
  default_config.height = vim.api.nvim_buf_line_count(buf_id)
  default_config.border = (vim.fn.exists('+winborder') == 0 or vim.o.winborder == '') and 'single' or nil
  default_config.title = ' Notifications '
  -- Don't allow focus to not disrupt window navigation
  default_config.focusable = false

  if win_id ~= nil then
    default_config.width = math.max(default_config.width, vim.api.nvim_win_get_width(win_id))
    if vim.wo[win_id].wrap then
      vim.api.nvim_win_set_config(win_id, { width = default_config.width })
      default_config.height = vim.api.nvim_win_text_height(win_id, {}).all
    end
  end

  -- User config
  local win_config = config_win.config
  if vim.is_callable(win_config) then win_config = win_config(buf_id) end
  local config = vim.tbl_deep_extend('force', default_config, win_config or {})

  -- Tweak config values to ensure they are proper, accounting for border
  local offset = config.border == 'none' and 0 or 2
  config.height = math.min(config.height, max_height - offset)
  config.width = math.min(config.width, max_width - offset)
  if type(config.title) == 'string' then config.title = H.fit_to_width(config.title, config.width) end

  return config
end

H.window_close = function()
  if H.is_valid_win(H.cache.win_id) then vim.api.nvim_win_close(H.cache.win_id, true) end
  H.cache.win_id = nil
end

H.window_trigger_event = function(win_id, event_name)
  local au_opts = { pattern = event_name, data = { win_id = win_id } }
  vim.api.nvim_win_call(win_id, function() vim.api.nvim_exec_autocmds('User', au_opts) end)
end

-- Notifications --------------------------------------------------------------
H.validate_msg = function(x, x_name)
  if not H.is_msg(x) then H.error((x_name or '`msg`') .. ' should be string or array of "text-hl chunk" lines.') end
end

H.validate_level = function(x, x_name)
  if vim.log.levels[x] == nil then H.error((x_name or '`level`') .. ' should be key of `vim.log.levels`.') end
end

H.validate_hl_group = function(x)
  if type(x) ~= 'string' then H.error('`hl_group` should be string.') end
end

H.is_msg = function(x)
  if type(x) == 'string' then return true end
  if not vim.islist(x) or #x == 0 then return false end
  for _, ch_line in ipairs(x) do
    if not vim.islist(ch_line) then return false end
    for _, ch in ipairs(ch_line) do
      local is_ch = type(ch) == 'table' and type(ch[1]) == 'string' and (ch[2] == nil or type(ch[2]) == 'string')
      if not is_ch then return false end
    end
  end
  return true
end

H.is_notification = function(x)
  return type(x) == 'table'
    and H.is_msg(x.msg)
    and vim.log.levels[x.level] ~= nil
    and type(x.hl_group) == 'string'
    and type(x.ts_add) == 'number'
    and type(x.ts_update) == 'number'
    and (x.ts_remove == nil or type(x.ts_remove) == 'number')
end

H.is_notification_array = function(x)
  if not vim.islist(x) then return false end
  for _, y in ipairs(x) do
    if not H.is_notification(y) then return false end
  end
  return true
end

H.notif_apply_format = function(notif_arr, format)
  for _, notif in ipairs(notif_arr) do
    local res = format(notif)
    H.validate_msg(res, 'Output of `content.format`')
    notif.msg = res
  end
  return notif_arr
end

H.notif_compare = function(a, b)
  local a_priority, b_priority = H.level_priority[a.level], H.level_priority[b.level]
  return a_priority > b_priority or (a_priority == b_priority and a.ts_add > b.ts_add)
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.notify) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.set_buf_name = function(buf_id, name) vim.api.nvim_buf_set_name(buf_id, 'mininotify://' .. buf_id .. '/' .. name) end

H.is_loaded_buf = function(buf_id) return type(buf_id) == 'number' and vim.api.nvim_buf_is_loaded(buf_id) end

H.is_valid_win = function(win_id) return type(win_id) == 'number' and vim.api.nvim_win_is_valid(win_id) end

H.is_win_in_tabpage = function(win_id) return vim.api.nvim_win_get_tabpage(win_id) == vim.api.nvim_get_current_tabpage() end

H.is_textlock = function()
  if not H.is_loaded_buf(H.cache.textlock_buf_id) then
    pcall(vim.api.nvim_buf_delete, H.cache.textlock_buf_id, { force = true })
    local buf_id = vim.api.nvim_create_buf(false, true)
    H.set_buf_name(buf_id, 'textlock-check-scratch')
    vim.bo[buf_id].modifiable = true
    H.cache.textlock_buf_id = buf_id
  end
  local ok = pcall(vim.api.nvim_buf_set_lines, H.cache.textlock_buf_id, 0, -1, false, {})
  return not ok
end

H.fit_to_width = function(text, width, dir)
  if vim.api.nvim_strwidth(text) <= width then return text end
  for w = vim.fn.strchars(text) - 1, 1, -1 do
    text = vim.fn.strcharpart(text, dir == 'right' and 0 or 1, w)
    if vim.api.nvim_strwidth(text) < width then return dir == 'right' and (text .. '…') or ('…' .. text) end
  end
  return width < 1 and '' or '…'
end

H.get_timestamp = function()
  -- This is more acceptable for `vim.fn.strftime()` than `vim.uv.hrtime()`
  local seconds, microseconds = vim.uv.gettimeofday()
  return seconds + 0.000001 * microseconds
end

return MiniNotify
