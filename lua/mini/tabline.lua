--- *mini.tabline* Tabline
---
--- MIT License Copyright (c) 2021 Evgeni Chasnovski

--- Key idea: show all listed buffers in readable way with minimal total width.
---
--- Features:
--- - Buffers are listed in the order of their identifier (see |bufnr()|).
---
--- - Different highlight groups for "states" of buffer affecting 'buffer tabs'.
---
--- - Buffer names are made unique by extending paths to files or appending
---   unique identifier to buffers without name.
---
--- - Current buffer is displayed "optimally centered" (in center of screen
---   while maximizing the total number of buffers shown) when there are many
---   buffers open.
---
--- - 'Buffer tabs' are clickable if Neovim allows it.
---
--- - Extra information section in case of multiple Neovim tabpages.
---
--- - Truncation symbols which show if there are tabs to the left and/or right.
---   Exact characters are taken from 'listchars' global value (`precedes` and
---   `extends` fields) and are shown only if 'list' option is enabled.
---
--- What it doesn't do:
--- - Custom buffer order is not supported.
---
--- # Dependencies ~
---
--- Suggested dependencies (provide extra functionality, will work without them):
---
--- - Enabled |MiniIcons| module to show icons near file names.
---   Falls back to using 'nvim-tree/nvim-web-devicons' plugin or shows nothing.
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.tabline').setup({})`
--- (replace `{}` with your `config` table). It will create global Lua table
--- `MiniTabline` which you can use for scripting or manually (with
--- `:lua MiniTabline.*`).
---
--- See |MiniTabline.config| for `config` structure and default values.
---
--- You can override runtime config settings locally to buffer inside
--- `vim.b.minitabline_config` which should have same structure as
--- `MiniTabline.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- # Suggested option values ~
---
--- Some options are set automatically by |MiniTabline.setup()|:
--- - 'showtabline' is set to 2 to always show tabline.
---
--- # Highlight groups ~
---
--- * `MiniTablineCurrent` - buffer is current (has cursor in it).
--- * `MiniTablineVisible` - buffer is visible (displayed in some window).
--- * `MiniTablineHidden` - buffer is hidden (not displayed).
--- * `MiniTablineModifiedCurrent` - buffer is modified and current.
--- * `MiniTablineModifiedVisible` - buffer is modified and visible.
--- * `MiniTablineModifiedHidden` - buffer is modified and hidden.
--- * `MiniTablineFill` - unused right space of tabline.
--- * `MiniTablineTabpagesection` - section with tabpage information.
--- * `MiniTablineTrunc` - truncation symbols indicating more left/right tabs.
---
--- To change any highlight group, modify it directly with |:highlight|.
---
--- # Disabling ~
---
--- To disable (show empty tabline), set `vim.g.minitabline_disable` (globally) or
--- `vim.b.minitabline_disable` (for a buffer) to `true`. Considering high number
--- of different scenarios and customization intentions, writing exact rules
--- for disabling module's functionality is left to user. See
--- |mini.nvim-disabling-recipes| for common recipes.
---@tag MiniTabline

-- Module definition ==========================================================
local MiniTabline = {}
local H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniTabline.config|.
---
---@usage >lua
---   require('mini.tabline').setup() -- use default config
---   -- OR
---   require('mini.tabline').setup({}) -- replace {} with your config table
--- <
MiniTabline.setup = function(config)
  -- Export module
  _G.MiniTabline = MiniTabline

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Define behavior
  H.create_autocommands()

  -- Create default highlighting
  H.create_default_hl()

  -- Function to make tabs clickable
  vim.api.nvim_exec(
    [[function! MiniTablineSwitchBuffer(buf_id, clicks, button, mod)
        execute 'buffer' a:buf_id
      endfunction]],
    false
  )
end

--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text # Format ~
---
--- `config.format` is a callable that takes buffer identifier and pre-computed
--- label as arguments and returns a string with formatted label. Output will be
--- treated strictly as text (i.e. no 'statusline' like constructs is allowed).
--- This function will be called for all displayable in tabline buffers.
--- Default: |MiniTabline.default_format()|.
---
--- Example of adding "+" suffix for modified buffers: >lua
---
---   function(buf_id, label)
---     local suffix = vim.bo[buf_id].modified and '+ ' or ''
---     return MiniTabline.default_format(buf_id, label) .. suffix
---   end
--- <
MiniTabline.config = {
  -- Whether to show file icons (requires 'mini.icons')
  show_icons = true,

  -- Function which formats the tab label
  -- By default surrounds with space and possibly prepends with icon
  format = nil,

  -- Where to show tabpage section in case of multiple vim tabpages.
  -- One of 'left', 'right', 'none'.
  tabpage_section = 'left',
}
--minidoc_afterlines_end

-- Module functionality =======================================================
--- Make string for |tabline|
MiniTabline.make_tabline_string = function()
  if H.is_disabled() then return '' end

  H.make_tabpage_section()
  H.list_tabs()
  H.finalize_labels()
  H.fit_width()

  return H.concat_tabs()
end

--- Default tab format
---
--- Used by default as `config.format`.
--- Prepends label with padded icon based on buffer's name (if `show_icon`
--- in |MiniTabline.config| is `true`) and surrounds label with single space.
--- Note: it is meant to be used only as part of `format` in |MiniTabline.config|.
---
---@param buf_id number Buffer identifier.
---@param label string Pre-computed label.
---
---@return string Formatted label.
MiniTabline.default_format = function(buf_id, label)
  if H.get_icon == nil then return string.format(' %s ', label) end
  return string.format(' %s %s ', H.get_icon(vim.api.nvim_buf_get_name(buf_id)), label)
end

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniTabline.config)

-- Table to keep track of tabs
H.tabs = {}

-- Keep track of initially unnamed buffers
H.unnamed_buffers_seq_ids = {}

-- Separator of file path
H.path_sep = package.config:sub(1, 1)

-- String with tabpage prefix
H.tabpage_section = ''

-- Data about truncation characters used when there are too much tabs
H.trunc = { left = '', right = '', needs_left = false, needs_right = false }

-- Buffer number of center buffer
H.center_buf_id = nil

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  H.check_type('show_icons', config.show_icons, 'boolean')
  H.check_type('format', config.format, 'function', true)
  H.check_type('tabpage_section', config.tabpage_section, 'string')

  return config
end

H.apply_config = function(config)
  MiniTabline.config = config

  -- Make tabline always visible (essential for custom tabline)
  vim.o.showtabline = 2

  -- Cache truncation characters
  H.cache_trunc_chars()

  -- Set tabline string
  vim.o.tabline = '%!v:lua.MiniTabline.make_tabline_string()'
end

H.create_autocommands = function()
  local gr = vim.api.nvim_create_augroup('MiniTabline', {})
  vim.api.nvim_create_autocmd('ColorScheme', { group = gr, callback = H.create_default_hl, desc = 'Ensure colors' })

  local trunc_opts = { group = gr, pattern = { 'list', 'listchars' }, callback = H.cache_trunc_chars }
  trunc_opts.desc = 'Ensure truncation characters'
  vim.api.nvim_create_autocmd('OptionSet', trunc_opts)
end

--stylua: ignore
H.create_default_hl = function()
  local set_default_hl = function(name, data)
    data.default = true
    vim.api.nvim_set_hl(0, name, data)
  end

  set_default_hl('MiniTablineCurrent', { link = 'TabLineSel' })
  set_default_hl('MiniTablineVisible', { link = 'TabLineSel' })
  set_default_hl('MiniTablineHidden',  { link = 'TabLine' })

  set_default_hl('MiniTablineModifiedCurrent', { link = 'StatusLine' })
  set_default_hl('MiniTablineModifiedVisible', { link = 'StatusLine' })
  set_default_hl('MiniTablineModifiedHidden',  { link = 'StatusLineNC' })

  set_default_hl('MiniTablineTabpagesection', { link = 'Search' })
  set_default_hl('MiniTablineFill', { link = 'Normal' })
  set_default_hl('MiniTablineTrunc', { link = 'MiniTablineHidden' })
end

H.is_disabled = function() return vim.g.minitabline_disable == true or vim.b.minitabline_disable == true end

H.get_config = function(config)
  return vim.tbl_deep_extend('force', MiniTabline.config, vim.b.minitabline_config or {}, config or {})
end

-- Work with tabpages ---------------------------------------------------------
H.make_tabpage_section = function()
  local n_tabpages = vim.fn.tabpagenr('$')
  if n_tabpages == 1 or H.get_config().tabpage_section == 'none' then
    H.tabpage_section = ''
    return
  end

  local cur_tabpagenr = vim.fn.tabpagenr()
  H.tabpage_section = string.format(' Tab %s/%s ', cur_tabpagenr, n_tabpages)
end

-- Work with tabs -------------------------------------------------------------
-- List tabs
H.list_tabs = function()
  local tabs = {}
  for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf_id].buflisted then
      local tab = { buf_id = buf_id }
      tab['hl'] = H.construct_highlight(buf_id)
      tab['tabfunc'] = '%' .. buf_id .. '@MiniTablineSwitchBuffer@'
      tab['label'], tab['label_extender'] = H.construct_label_data(buf_id)

      table.insert(tabs, tab)
    end
  end

  H.tabs = tabs
end

-- Tab's highlight group
H.construct_highlight = function(buf_id)
  local hl_type = buf_id == vim.api.nvim_get_current_buf() and 'Current'
    or (vim.fn.bufwinnr(buf_id) > 0 and 'Visible' or 'Hidden')
  if vim.bo[buf_id].modified then hl_type = 'Modified' .. hl_type end

  return '%#MiniTabline' .. hl_type .. '#'
end

-- Tab's label and label extender
H.construct_label_data = function(buf_id)
  local label, label_extender

  local bufpath = vim.api.nvim_buf_get_name(buf_id)
  if bufpath ~= '' then
    -- Process path buffer
    label = vim.fn.fnamemodify(bufpath, ':t')
    label_extender = H.make_path_extender(buf_id)
  else
    -- Process unnamed buffer
    label = H.make_unnamed_label(buf_id)
    label_extender = function(x) return x end
  end

  return label, label_extender
end

H.make_path_extender = function(buf_id)
  -- Add parent to current label (if possible)
  return function(label)
    local full_path = vim.api.nvim_buf_get_name(buf_id)
    -- Using `vim.pesc` prevents effect of problematic characters (like '.')
    local pattern = string.format('[^%s]+%s%s$', H.path_sep, H.path_sep, vim.pesc(label))
    return string.match(full_path, pattern) or label
  end
end

-- Work with unnamed buffers --------------------------------------------------
-- Unnamed buffers are tracked in `H.unnamed_buffers_seq_ids` for
-- disambiguation. This table is designed to store 'sequential' buffer
-- identifier. This approach allows to have the following behavior:
-- - Create three unnamed buffers.
-- - Delete second one.
-- - Tab label for third one remains the same.
H.make_unnamed_label = function(buf_id)
  local buftype = vim.bo[buf_id].buftype
  -- Differentiate quickfix/location lists and scratch/other unnamed buffers
  local label = buftype == 'quickfix'
      -- There can be only one quickfix buffer and many location buffers
      and (vim.fn.getqflist({ qfbufnr = true }).qfbufnr == buf_id and '*quickfix*' or '*location*')
    or ((buftype == 'nofile' or buftype == 'acwrite') and '!' or '*')

  -- Possibly add tracking id
  local unnamed_id = H.get_unnamed_id(buf_id)
  if unnamed_id > 1 then label = string.format('%s(%d)', label, unnamed_id) end

  return label
end

H.get_unnamed_id = function(buf_id)
  -- Use existing sequential id if possible
  local seq_id = H.unnamed_buffers_seq_ids[buf_id]
  if seq_id ~= nil then return seq_id end

  -- Cache sequential id for currently unnamed buffer `buf_id`
  H.unnamed_buffers_seq_ids[buf_id] = vim.tbl_count(H.unnamed_buffers_seq_ids) + 1
  return H.unnamed_buffers_seq_ids[buf_id]
end

-- Work with labels -----------------------------------------------------------
H.finalize_labels = function()
  if #H.tabs == 0 then return end

  -- Deduplicate
  local nonunique_buf_ids = H.get_nonunique_buf_ids()
  while #nonunique_buf_ids > 0 do
    local nothing_changed = true

    -- Extend labels
    for _, buf_id in ipairs(nonunique_buf_ids) do
      local tab = H.tabs[buf_id]
      local old_label = tab.label
      tab.label = tab.label_extender(tab.label)
      if old_label ~= tab.label then nothing_changed = false end
    end

    if nothing_changed then break end

    nonunique_buf_ids = H.get_nonunique_buf_ids()
  end

  -- Format labels
  local config = H.get_config()

  -- - Ensure cached `get_icon` for `default_format` (for better performance)
  H.ensure_get_icon(config)

  -- - Apply formatting
  local format = config.format or MiniTabline.default_format
  for _, tab in pairs(H.tabs) do
    tab.label = format(tab.buf_id, tab.label)
  end
end

H.get_nonunique_buf_ids = function()
  local label_counts = {}
  for _, tab in ipairs(H.tabs) do
    label_counts[tab.label] = (label_counts[tab.label] or 0) + 1
  end

  local res = {}
  for i, tab in ipairs(H.tabs) do
    if label_counts[tab.label] > 1 then table.insert(res, i) end
  end
  return res
end

-- Fit tabline to maximum displayed width -------------------------------------
H.fit_width = function()
  if #H.tabs == 0 then return end

  local cur_buf = vim.api.nvim_get_current_buf()
  if vim.bo[cur_buf].buflisted then H.center_buf_id = cur_buf end

  -- Compute label width data
  local center_offset = 1
  local tot_width = 0
  for _, tab in pairs(H.tabs) do
    tab.label_width = H.strwidth(tab.label)
    tab.chars_on_left = tot_width

    tot_width = tot_width + tab.label_width

    if tab.buf_id == H.center_buf_id then
      -- Make right end of 'center tab' to be always displayed in center in
      -- case of truncation
      center_offset = tot_width
    end
  end

  local display_interval = H.compute_display_interval(center_offset, tot_width)

  H.truncate_tabs_display(display_interval)
end

H.compute_display_interval = function(center_offset, tabline_width)
  -- left - first character to be displayed (starts with 1)
  -- right - last character to be displayed
  -- Conditions to be satisfied:
  -- 1) right - left + 1 = math.min(tot_width, tabline_width)
  -- 2) 1 <= left <= tabline_width; 1 <= right <= tabline_width

  local tot_width = vim.o.columns - H.strwidth(H.tabpage_section)

  -- Usage of `math.floor` is crucial to avoid non-integer values which might
  -- affect total width of output tabline string.
  -- Using `floor` instead of `ceil` has effect when `tot_width` is odd:
  -- - `floor` makes "true center" to be between second to last and last label
  --   character (usually non-space and space).
  -- - `ceil` - between last character of center label and first character of
  --   next label (both whitespaces).
  local right = math.min(tabline_width, math.floor(center_offset + 0.5 * tot_width))
  local left = math.max(1, right - tot_width + 1)
  right = left + math.min(tot_width, tabline_width) - 1

  return { left, right }
end

H.truncate_tabs_display = function(display_interval)
  local display_left, display_right = display_interval[1], display_interval[2]

  local tabs, first, last = {}, nil, nil
  for i, tab in ipairs(H.tabs) do
    local tab_left = tab.chars_on_left + 1
    local tab_right = tab.chars_on_left + tab.label_width
    if (display_left <= tab_right) and (tab_left <= display_right) then
      -- Process tab that should be displayed (even partially)
      local n_trunc_left = math.max(0, display_left - tab_left)
      local n_trunc_right = math.max(0, tab_right - display_right)

      -- Take desired amount of characters starting from `n_trunc_left`
      tab.label = vim.fn.strcharpart(tab.label, n_trunc_left, tab.label_width - n_trunc_right)

      table.insert(tabs, tab)

      -- Keep track of the shown tab range for truncation characters
      first, last = first or i, i
    end
  end

  -- Truncate first and/or last tabs if there is anything to the left/right
  H.trunc.needs_left = H.trunc.left ~= '' and (first > 1 or H.strwidth(tabs[1].label) < tabs[1].label_width)
  if H.trunc.needs_left then tabs[1].label = vim.fn.strcharpart(tabs[1].label, 1) end

  local n = #tabs
  H.trunc.needs_right = H.trunc.right ~= '' and (last < #H.tabs or H.strwidth(tabs[n].label) < tabs[n].label_width)
  if H.trunc.needs_right then tabs[n].label = vim.fn.strcharpart(tabs[n].label, 0, H.strwidth(tabs[n].label) - 1) end

  H.tabs = tabs
end

H.cache_trunc_chars = function()
  local trunc_chars = { left = '', right = '' }
  if vim.go.list then
    local listchars = vim.go.listchars
    trunc_chars.left = listchars:match('precedes:(.[^,]*)') or ''
    trunc_chars.right = listchars:match('extends:(.[^,]*)') or ''
  end
  H.trunc = trunc_chars
end

-- Concatenate tabs into single tablien string --------------------------------
H.concat_tabs = function()
  -- NOTE: it is assumed that all padding is incorporated into labels
  local t = {}
  if H.trunc.needs_left then table.insert(t, '%#MiniTablineTrunc#' .. H.trunc.left:gsub('%%', '%%%%')) end
  for _, tab in ipairs(H.tabs) do
    -- Escape '%' in labels
    table.insert(t, tab.hl .. tab.tabfunc .. tab.label:gsub('%%', '%%%%'))
  end
  if H.trunc.needs_right then table.insert(t, '%#MiniTablineTrunc#' .. H.trunc.right:gsub('%%', '%%%%')) end

  -- Usage of `%X` makes filled space to the right "non-clickable"
  local res = table.concat(t, '') .. '%X%#MiniTablineFill#'

  -- Add tabpage section
  if H.tabpage_section ~= '' then
    local position = H.get_config().tabpage_section
    if position == 'left' then res = '%#MiniTablineTabpagesection#' .. H.tabpage_section .. res end
    if position == 'right' then res = res .. '%=%#MiniTablineTabpagesection#' .. H.tabpage_section end
  end

  return res
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.tabline) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.strwidth = function(x) return vim.api.nvim_strwidth(x) end

H.ensure_get_icon = function(config)
  if not config.show_icons then
    -- Show no icon
    H.get_icon = nil
  elseif H.get_icon ~= nil then
    -- Cache only once
    return
  elseif _G.MiniIcons ~= nil then
    -- Prefer 'mini.icons'
    H.get_icon = function(name) return (_G.MiniIcons.get('file', name)) end
  else
    -- Try falling back to 'nvim-web-devicons'
    local has_devicons, devicons = pcall(require, 'nvim-web-devicons')
    if not has_devicons then return end
    -- Use basename because it makes exact file name matching work
    H.get_icon = function(name) return (devicons.get_icon(vim.fn.fnamemodify(name, ':t'), nil, { default = true })) end
  end
end

return MiniTabline
