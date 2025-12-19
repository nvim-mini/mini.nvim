--- *mini.statusline* Statusline
---
--- MIT License Copyright (c) 2021 Evgeni Chasnovski

--- Features:
--- - Define own custom statusline structure for active and inactive windows.
---   This is done with a function which should return string appropriate for
---   |'statusline'|. Its code should be similar to default one with structure:
---     - Compute string data for every section you want to be displayed.
---     - Combine them in groups with |MiniStatusline.combine_groups()|.
---
--- - Built-in active mode indicator with colors.
---
--- - Sections can hide information when window is too narrow (specific window
---   width is configurable per section).
---
--- # Dependencies ~
---
--- Suggested dependencies (provide extra functionality, will work without them):
---
--- - Nerd font (to support extra icons).
---
--- - Enabled |mini.icons| module for |MiniStatusline.section_fileinfo()|.
---   Falls back to using 'nvim-tree/nvim-web-devicons' plugin or shows nothing.
---
--- - Enabled |mini.git| module for |MiniStatusline.section_git()|.
---   Falls back to using 'lewis6991/gitsigns.nvim' plugin or shows nothing.
---
--- - Enabled |mini.diff| module for |MiniStatusline.section_diff()|.
---   Falls back to using 'lewis6991/gitsigns.nvim' plugin or shows nothing.
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.statusline').setup({})`
--- (replace `{}` with your `config` table). It will create global Lua table
--- `MiniStatusline` which you can use for scripting or manually (with
--- `:lua MiniStatusline.*`).
---
--- See |MiniStatusline.config| for `config` structure and default values. For
--- some content examples, see |MiniStatusline-example-content|.
---
--- You can override runtime config settings locally to buffer inside
--- `vim.b.ministatusline_config` which should have same structure as
--- `MiniStatusline.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- # Highlight groups ~
---
--- Highlight depending on mode (second |MiniStatusline.section_mode()| output):
--- - `MiniStatuslineModeNormal` - Normal mode.
--- - `MiniStatuslineModeInsert` - Insert mode.
--- - `MiniStatuslineModeVisual` - Visual mode.
--- - `MiniStatuslineModeReplace` - Replace mode.
--- - `MiniStatuslineModeCommand` - Command mode.
--- - `MiniStatuslineModeOther` - other modes (like Terminal, etc.).
---
--- Highlight used in default statusline:
--- - `MiniStatuslineDevinfo` - for "dev info" group
---   (|MiniStatusline.section_git()| and |MiniStatusline.section_diagnostics()|).
--- - `MiniStatuslineFilename` - for |MiniStatusline.section_filename()| section.
--- - `MiniStatuslineFileinfo` - for |MiniStatusline.section_fileinfo()| section.
---
--- Other groups:
--- - `MiniStatuslineInactive` - highlighting in not focused window.
---
--- To change any highlight group, set it directly with |nvim_set_hl()|.
---
--- # Disabling ~
---
--- To disable (show empty statusline), set `vim.g.ministatusline_disable`
--- (globally) or `vim.b.ministatusline_disable` (for a buffer) to `true`.
--- Considering high number of different scenarios and customization
--- intentions, writing exact rules for disabling module's functionality is
--- left to user. See |mini.nvim-disabling-recipes| for common recipes.
---@tag MiniStatusline

--- Example content
---
--- # Default content ~
---
--- This function is used as default value for active content: >lua
---
---   function()
---     local mode, mode_hl = MiniStatusline.section_mode({ trunc_width = 120 })
---     local git           = MiniStatusline.section_git({ trunc_width = 40 })
---     local diff          = MiniStatusline.section_diff({ trunc_width = 75 })
---     local diagnostics   = MiniStatusline.section_diagnostics({ trunc_width = 75 })
---     local lsp           = MiniStatusline.section_lsp({ trunc_width = 75 })
---     local filename      = MiniStatusline.section_filename({ trunc_width = 140 })
---     local fileinfo      = MiniStatusline.section_fileinfo({ trunc_width = 120 })
---     local location      = MiniStatusline.section_location({ trunc_width = 75 })
---     local search        = MiniStatusline.section_searchcount({ trunc_width = 75 })
---
---     return MiniStatusline.combine_groups({
---       { hl = mode_hl,                  strings = { mode } },
---       { hl = 'MiniStatuslineDevinfo',  strings = { git, diff, diagnostics, lsp } },
---       '%<', -- Mark general truncate point
---       { hl = 'MiniStatuslineFilename', strings = { filename } },
---       '%=', -- End left alignment
---       { hl = 'MiniStatuslineFileinfo', strings = { fileinfo } },
---       { hl = mode_hl,                  strings = { search, location } },
---     })
---   end
--- <
--- # Show boolean options ~
---
--- To compute section string for boolean option use variation of this code
--- snippet inside content function (you can modify option itself, truncation
--- width, short and long displayed names): >lua
---
---   local spell = vim.wo.spell and (MiniStatusline.is_truncated(120) and 'S' or 'SPELL') or ''
--- <
--- Here `x and y or z` is a common Lua way of doing ternary operator: if `x`
--- is `true`-ish then return `y`, if not - return `z`.
---@tag MiniStatusline-example-content

---@alias __statusline_args table Section arguments.
---@alias __statusline_section string Section string.

-- Module definition ==========================================================
local MiniStatusline = {}
local H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniStatusline.config|.
---
---@usage >lua
---   require('mini.statusline').setup() -- use default config
---   -- OR
---   require('mini.statusline').setup({}) -- replace {} with your config table
--- <
MiniStatusline.setup = function(config)
  -- Export module
  _G.MiniStatusline = MiniStatusline

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Define behavior
  H.create_autocommands()

  -- - Disable built-in statusline in Quickfix window
  vim.g.qf_disable_statusline = 1

  -- Create default highlighting
  H.create_default_hl()
end

--- Defaults ~
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
MiniStatusline.config = {
  -- Content of statusline as functions which return statusline string. See
  -- `:h statusline` and code of default contents (used instead of `nil`).
  content = {
    -- Content for active window
    active = nil,
    -- Content for inactive window(s)
    inactive = nil,
  },

  -- Whether to use icons by default
  use_icons = true,
}
--minidoc_afterlines_end

-- Module functionality =======================================================
--- Compute content for active window
MiniStatusline.active = function()
  if H.is_disabled() then return '' end
  return (H.get_config().content.active or H.default_content_active)()
end

--- Compute content for inactive window
MiniStatusline.inactive = function()
  if H.is_disabled() then return '' end
  return (H.get_config().content.inactive or H.default_content_inactive)()
end

--- Combine groups of sections
---
--- Each group can be either a string or a table with fields `hl` (group's
--- highlight group) and `strings` (strings representing sections).
---
--- General idea of this function is as follows;
--- - String group is used as is (useful for special strings like `%<` or `%=`).
--- - Each table group has own highlighting in `hl` field (if missing, the
---   previous one is used) and string parts in `strings` field. Non-empty
---   strings from `strings` are separated by one space. Non-empty groups are
---   separated by two spaces (one for each highlighting).
---
---@param groups table Array of groups.
---
---@return string String suitable for 'statusline'.
MiniStatusline.combine_groups = function(groups)
  local parts = vim.tbl_map(function(s)
    if type(s) == 'string' then return s end
    if type(s) ~= 'table' then return '' end

    local string_arr = vim.tbl_filter(function(x) return type(x) == 'string' and x ~= '' end, s.strings or {})
    local str = table.concat(string_arr, ' ')

    -- Use previous highlight group
    if s.hl == nil then return ' ' .. str .. ' ' end

    -- Allow using this highlight group later
    if str:len() == 0 then return '%#' .. s.hl .. '#' end

    return string.format('%%#%s# %s ', s.hl, str)
  end, groups)

  return table.concat(parts, '')
end

--- Decide whether to truncate
---
--- This basically computes window width and compares it to `trunc_width`: if
--- window is smaller then truncate; otherwise don't. Don't truncate by
--- default.
---
--- Use this to manually decide if section needs truncation or not.
---
---@param trunc_width number|nil Truncation width. If `nil`, output is `false`.
---
---@return boolean Whether to truncate.
MiniStatusline.is_truncated = function(trunc_width)
  -- Use -1 to default to 'not truncated'
  local cur_width = vim.o.laststatus == 3 and vim.o.columns or vim.api.nvim_win_get_width(0)
  return cur_width < (trunc_width or -1)
end

-- Sections ===================================================================
-- Functions should return output text without whitespace on sides.
-- Return empty string to omit section.

--- Section for Vim |mode()|
---
--- Short output is returned if window width is lower than `args.trunc_width`.
---
---@param args __statusline_args
---
---@return ... Section string and mode's highlight group.
MiniStatusline.section_mode = function(args)
  local mode_info = H.modes[vim.fn.mode()]

  local mode = MiniStatusline.is_truncated(args.trunc_width) and mode_info.short or mode_info.long

  return mode, mode_info.hl
end

--- Section for Git information
---
--- Shows Git summary from |mini.git| (should be set up; recommended). To tweak
--- formatting of what data is shown, modify buffer-local summary string directly
--- as described in |MiniGit-examples|.
---
--- If 'mini.git' is not set up, section falls back on 'lewis6991/gitsigns' data
--- or showing empty string.
---
--- Empty string is returned if window width is lower than `args.trunc_width`.
---
---@param args __statusline_args Use `args.icon` to supply your own icon.
---
---@return __statusline_section
MiniStatusline.section_git = function(args)
  if MiniStatusline.is_truncated(args.trunc_width) then return '' end

  local summary = vim.b.minigit_summary_string or vim.b.gitsigns_head
  if summary == nil then return '' end

  local use_icons = H.use_icons or H.get_config().use_icons
  local icon = args.icon or (use_icons and '' or 'Git')
  return icon .. ' ' .. (summary == '' and '-' or summary)
end

--- Section for diff information
---
--- Shows diff summary from |mini.diff| (should be set up; recommended). To tweak
--- formatting of what data is shown, modify buffer-local summary string directly
--- as described in |MiniDiff-diff-summary|.
---
--- If 'mini.diff' is not set up, section falls back on 'lewis6991/gitsigns' data
--- or showing empty string.
---
--- Empty string is returned if window width is lower than `args.trunc_width`.
---
---@param args __statusline_args Use `args.icon` to supply your own icon.
---
---@return __statusline_section
MiniStatusline.section_diff = function(args)
  if MiniStatusline.is_truncated(args.trunc_width) then return '' end

  local summary = vim.b.minidiff_summary_string or vim.b.gitsigns_status
  if summary == nil then return '' end

  local use_icons = H.use_icons or H.get_config().use_icons
  local icon = args.icon or (use_icons and '' or 'Diff')
  return icon .. ' ' .. (summary == '' and '-' or summary)
end

--- Section for Neovim's builtin diagnostics
---
--- Shows nothing if diagnostics is disabled, no diagnostic is set, or for short
--- output. Otherwise uses |vim.diagnostic.get()| to compute and show number of
--- errors ('E'), warnings ('W'), information ('I'), and hints ('H').
---
--- Short output is returned if window width is lower than `args.trunc_width`.
---
---@param args __statusline_args Use `args.icon` to supply your own icon.
---   Use `args.signs` to use custom signs per severity level name. For example: >lua
---
---   { ERROR = '!', WARN = '?', INFO = '@', HINT = '*' }
--- <
---@return __statusline_section
MiniStatusline.section_diagnostics = function(args)
  if MiniStatusline.is_truncated(args.trunc_width) then return '' end

  -- Construct string parts. NOTE: call `diagnostic_is_disabled()` *after*
  -- check for present `count` to not source `vim.diagnostic` on startup.
  local count = H.diagnostic_counts[vim.api.nvim_get_current_buf()]
  if count == nil or H.diagnostic_is_disabled() then return '' end

  local severity, signs, t = vim.diagnostic.severity, args.signs or {}, {}
  for _, level in ipairs(H.diagnostic_levels) do
    local n = count[severity[level.name]] or 0
    -- Add level info only if diagnostic is present
    if n > 0 then table.insert(t, ' ' .. (signs[level.name] or level.sign) .. n) end
  end
  if #t == 0 then return '' end

  local use_icons = H.use_icons or H.get_config().use_icons
  local icon = args.icon or (use_icons and '' or 'Diag')
  return icon .. table.concat(t, '')
end

--- Section for attached LSP servers
---
--- Shows number of LSP servers (each as separate "+" character) attached to
--- current buffer or nothing if none is attached.
--- Nothing is shown if window width is lower than `args.trunc_width`.
---
---@param args __statusline_args Use `args.icon` to supply your own icon.
---
---@return __statusline_section
MiniStatusline.section_lsp = function(args)
  if MiniStatusline.is_truncated(args.trunc_width) then return '' end

  local attached = H.attached_lsp[vim.api.nvim_get_current_buf()] or ''
  if attached == '' then return '' end

  local use_icons = H.use_icons or H.get_config().use_icons
  local icon = args.icon or (use_icons and '󰰎' or 'LSP')
  return icon .. ' ' .. attached
end

--- Section for file name
---
--- Show full file name or relative in short output.
---
--- Short output is returned if window width is lower than `args.trunc_width`.
---
---@param args __statusline_args
---
---@return __statusline_section
MiniStatusline.section_filename = function(args)
  -- In terminal always use plain name
  if vim.bo.buftype == 'terminal' then
    return '%t'
  elseif MiniStatusline.is_truncated(args.trunc_width) then
    -- File name with 'truncate', 'modified', 'readonly' flags
    -- Use relative path if truncated
    return '%f%m%r'
  else
    -- Use fullpath if not truncated
    return '%F%m%r'
  end
end

--- Section for file information
---
--- Shows 'filetype', 'fileencoding' / 'encoding', 'fileformat', and buffer size.
--- Short output has only non-empty 'filetype' and is returned if window width is
--- lower than `args.trunc_width` or buffer is not normal (as per 'buftype').
---
--- Buffer size is computed based on current text, not file's saved version.
---
--- If `config.use_icons` is true and icon provider is present (see
--- "Dependencies" section in |mini.statusline|), shows icon near the filetype.
---
---@param args __statusline_args
---
---@return __statusline_section
MiniStatusline.section_fileinfo = function(args)
  local filetype = vim.bo.filetype

  -- Add filetype icon
  H.ensure_get_icon()
  if H.get_icon ~= nil and filetype ~= '' then filetype = H.get_icon(filetype) .. ' ' .. filetype end

  -- Construct output string if truncated or buffer is not normal
  if MiniStatusline.is_truncated(args.trunc_width) or vim.bo.buftype ~= '' then return filetype end

  -- Construct output string with extra file info
  local encoding = vim.bo.fileencoding or vim.bo.encoding
  local format = vim.bo.fileformat
  local size = H.get_filesize()

  return string.format('%s%s%s[%s] %s', filetype, filetype == '' and '' or ' ', encoding, format, size)
end

--- Section for location inside buffer
---
--- Show location inside buffer in the form:
--- - Normal: `'<cursor line>|<total lines>│<cursor column>|<total columns>'`
--- - Short: `'<cursor line>│<cursor column>'`
---
--- Short output is returned if window width is lower than `args.trunc_width`.
---
---@param args __statusline_args
---
---@return __statusline_section
MiniStatusline.section_location = function(args)
  -- Use virtual column number to allow update when past last column
  if MiniStatusline.is_truncated(args.trunc_width) then return '%l│%2v' end

  -- Use `virtcol()` to correctly handle multi-byte characters
  return '%l|%L│%2v|%-2{virtcol("$") - 1}'
end

--- Section for current search count
---
--- Show the current status of |searchcount()|. Empty output is returned if
--- window width is lower than `args.trunc_width`, search highlighting is not
--- on (see |v:hlsearch|), or if number of search result is 0.
---
--- `args.options` is forwarded to |searchcount()|. By default it recomputes
--- data on every call which can be computationally expensive (although still
--- usually on 0.1 ms order of magnitude). To prevent this, supply
--- `args.options = { recompute = false }`.
---
---@param args __statusline_args
---
---@return __statusline_section
MiniStatusline.section_searchcount = function(args)
  if vim.v.hlsearch == 0 or MiniStatusline.is_truncated(args.trunc_width) then return '' end
  -- `searchcount()` can return errors because it is evaluated very often in
  -- statusline. For example, when typing `/` followed by `\(`, it gives E54.
  local ok, s_count = pcall(vim.fn.searchcount, (args or {}).options or { recompute = true })
  if not ok or s_count.current == nil or s_count.total == 0 then return '' end

  if s_count.incomplete == 1 then return '?/?' end

  local too_many = '>' .. s_count.maxcount
  local current = s_count.current > s_count.maxcount and too_many or s_count.current
  local total = s_count.total > s_count.maxcount and too_many or s_count.total
  return current .. '/' .. total
end

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniStatusline.config)

-- Showed diagnostic levels
H.diagnostic_levels = {
  { name = 'ERROR', sign = 'E' },
  { name = 'WARN', sign = 'W' },
  { name = 'INFO', sign = 'I' },
  { name = 'HINT', sign = 'H' },
}

-- Diagnostic counts per buffer id
H.diagnostic_counts = {}

-- String representation of attached LSP clients per buffer id
H.attached_lsp = {}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  H.check_type('content', config.content, 'table')
  H.check_type('content.active', config.content.active, 'function', true)
  H.check_type('content.inactive', config.content.inactive, 'function', true)

  H.check_type('use_icons', config.use_icons, 'boolean')

  return config
end

H.apply_config = function(config)
  MiniStatusline.config = config

  -- Set statusline globally and dynamically decide which content to use
  vim.go.statusline =
    '%{%(nvim_get_current_win()==#g:actual_curwin || &laststatus==3) ? v:lua.MiniStatusline.active() : v:lua.MiniStatusline.inactive()%}'
end

H.create_autocommands = function()
  local gr = vim.api.nvim_create_augroup('MiniStatusline', {})

  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = gr, pattern = pattern, callback = callback, desc = desc })
  end

  -- Use `schedule_wrap()` because at `LspDetach` server is still present
  local track_lsp = vim.schedule_wrap(function(data)
    H.attached_lsp[data.buf] = vim.api.nvim_buf_is_valid(data.buf) and H.compute_attached_lsp(data.buf) or nil
    vim.cmd('redrawstatus')
  end)
  au({ 'LspAttach', 'LspDetach' }, '*', track_lsp, 'Track LSP clients')

  -- Use `schedule_wrap()` because `redrawstatus` might error on `:bwipeout`
  -- See: https://github.com/neovim/neovim/issues/32349
  local track_diagnostics = vim.schedule_wrap(function(data)
    H.diagnostic_counts[data.buf] = vim.api.nvim_buf_is_valid(data.buf) and H.get_diagnostic_count(data.buf) or nil
    vim.cmd('redrawstatus')
  end)
  au('DiagnosticChanged', '*', track_diagnostics, 'Track diagnostics')

  au('ColorScheme', '*', H.create_default_hl, 'Ensure colors')
end

--stylua: ignore
H.create_default_hl = function()
  local set_default_hl = function(name, data)
    data.default = true
    vim.api.nvim_set_hl(0, name, data)
  end

  set_default_hl('MiniStatuslineModeNormal',  { link = 'Cursor' })
  set_default_hl('MiniStatuslineModeInsert',  { link = 'DiffChange' })
  set_default_hl('MiniStatuslineModeVisual',  { link = 'DiffAdd' })
  set_default_hl('MiniStatuslineModeReplace', { link = 'DiffDelete' })
  set_default_hl('MiniStatuslineModeCommand', { link = 'DiffText' })
  set_default_hl('MiniStatuslineModeOther',   { link = 'IncSearch' })

  set_default_hl('MiniStatuslineDevinfo',  { link = 'StatusLine' })
  set_default_hl('MiniStatuslineFilename', { link = 'StatusLineNC' })
  set_default_hl('MiniStatuslineFileinfo', { link = 'StatusLine' })
  set_default_hl('MiniStatuslineInactive', { link = 'StatusLineNC' })
end

H.is_disabled = function() return vim.g.ministatusline_disable == true or vim.b.ministatusline_disable == true end

H.get_config = function(config)
  return vim.tbl_deep_extend('force', MiniStatusline.config, vim.b.ministatusline_config or {}, config or {})
end

-- Mode -----------------------------------------------------------------------
-- Custom `^V` and `^S` symbols to make this file appropriate for copy-paste
-- (otherwise those symbols are not displayed).
local CTRL_S = vim.api.nvim_replace_termcodes('<C-S>', true, true, true)
local CTRL_V = vim.api.nvim_replace_termcodes('<C-V>', true, true, true)

-- stylua: ignore start
H.modes = setmetatable({
  ['n']    = { long = 'Normal',   short = 'N',   hl = 'MiniStatuslineModeNormal' },
  ['v']    = { long = 'Visual',   short = 'V',   hl = 'MiniStatuslineModeVisual' },
  ['V']    = { long = 'V-Line',   short = 'V-L', hl = 'MiniStatuslineModeVisual' },
  [CTRL_V] = { long = 'V-Block',  short = 'V-B', hl = 'MiniStatuslineModeVisual' },
  ['s']    = { long = 'Select',   short = 'S',   hl = 'MiniStatuslineModeVisual' },
  ['S']    = { long = 'S-Line',   short = 'S-L', hl = 'MiniStatuslineModeVisual' },
  [CTRL_S] = { long = 'S-Block',  short = 'S-B', hl = 'MiniStatuslineModeVisual' },
  ['i']    = { long = 'Insert',   short = 'I',   hl = 'MiniStatuslineModeInsert' },
  ['R']    = { long = 'Replace',  short = 'R',   hl = 'MiniStatuslineModeReplace' },
  ['c']    = { long = 'Command',  short = 'C',   hl = 'MiniStatuslineModeCommand' },
  ['r']    = { long = 'Prompt',   short = 'P',   hl = 'MiniStatuslineModeOther' },
  ['!']    = { long = 'Shell',    short = 'Sh',  hl = 'MiniStatuslineModeOther' },
  ['t']    = { long = 'Terminal', short = 'T',   hl = 'MiniStatuslineModeOther' },
}, {
  -- By default return 'Unknown' but this shouldn't be needed
  __index = function()
    return   { long = 'Unknown',  short = 'U',   hl = '%#MiniStatuslineModeOther#' }
  end,
})
-- stylua: ignore end

-- Default content ------------------------------------------------------------
--stylua: ignore
H.default_content_active = function()
  H.use_icons = H.get_config().use_icons
  local mode, mode_hl = MiniStatusline.section_mode({ trunc_width = 120 })
  local git           = MiniStatusline.section_git({ trunc_width = 40 })
  local diff          = MiniStatusline.section_diff({ trunc_width = 75 })
  local diagnostics   = MiniStatusline.section_diagnostics({ trunc_width = 75 })
  local lsp           = MiniStatusline.section_lsp({ trunc_width = 75 })
  local filename      = MiniStatusline.section_filename({ trunc_width = 140 })
  local fileinfo      = MiniStatusline.section_fileinfo({ trunc_width = 120 })
  local location      = MiniStatusline.section_location({ trunc_width = 75 })
  local search        = MiniStatusline.section_searchcount({ trunc_width = 75 })
  H.use_icons = nil

  -- Usage of `MiniStatusline.combine_groups()` ensures highlighting and
  -- correct padding with spaces between groups (accounts for 'missing'
  -- sections, etc.)
  return MiniStatusline.combine_groups({
    { hl = mode_hl,                  strings = { mode } },
    { hl = 'MiniStatuslineDevinfo',  strings = { git, diff, diagnostics, lsp } },
    '%<', -- Mark general truncate point
    { hl = 'MiniStatuslineFilename', strings = { filename } },
    '%=', -- End left alignment
    { hl = 'MiniStatuslineFileinfo', strings = { fileinfo } },
    { hl = mode_hl,                  strings = { search, location } },
  })
end

H.default_content_inactive = function() return '%#MiniStatuslineInactive#%F%=' end

-- LSP ------------------------------------------------------------------------
H.compute_attached_lsp = function(buf_id) return string.rep('+', vim.tbl_count(H.get_buf_lsp_clients(buf_id))) end

H.get_buf_lsp_clients = function(buf_id) return vim.lsp.get_clients({ bufnr = buf_id }) end
-- NOTE: Use `has('nvim-0.xx')` instead of directly checking presence of target
-- function to avoid loading `vim.xxx` modules at `require('mini.statusline')`.
-- This visibly improves startup time.
if vim.fn.has('nvim-0.10') == 0 then
  H.get_buf_lsp_clients = function(buf_id) return vim.lsp.buf_get_clients(buf_id) end
end

-- Diagnostics ----------------------------------------------------------------
H.get_diagnostic_count = function(buf_id) return vim.diagnostic.count(buf_id) end
if vim.fn.has('nvim-0.10') == 0 then
  H.get_diagnostic_count = function(buf_id)
    local res = {}
    for _, d in ipairs(vim.diagnostic.get(buf_id)) do
      res[d.severity] = (res[d.severity] or 0) + 1
    end
    return res
  end
end

H.diagnostic_is_disabled = function() return not vim.diagnostic.is_enabled({ bufnr = 0 }) end
if vim.fn.has('nvim-0.10') == 0 then H.diagnostic_is_disabled = function() return vim.diagnostic.is_disabled(0) end end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.statusline) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.get_filesize = function()
  local size = math.max(vim.fn.line2byte(vim.fn.line('$') + 1) - 1, 0)
  if size < 1024 then
    return string.format('%dB', size)
  elseif size < 1048576 then
    return string.format('%.2fKiB', size / 1024)
  else
    return string.format('%.2fMiB', size / 1048576)
  end
end

H.ensure_get_icon = function()
  if not (H.use_icons or H.get_config().use_icons) then
    -- Show no icon
    H.get_icon = nil
  elseif H.get_icon ~= nil then
    -- Cache only once
    return
  elseif _G.MiniIcons ~= nil then
    -- Prefer 'mini.icons'
    H.get_icon = function(filetype) return (_G.MiniIcons.get('filetype', filetype)) end
  else
    -- Try falling back to 'nvim-web-devicons'
    local has_devicons, devicons = pcall(require, 'nvim-web-devicons')
    if not has_devicons then return end
    H.get_icon = function() return (devicons.get_icon(vim.fn.expand('%:t'), nil, { default = true })) end
  end
end

return MiniStatusline
