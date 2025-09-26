--- *mini.trailspace* Trailspace (highlight and remove)
---
--- MIT License Copyright (c) 2021 Evgeni Chasnovski

--- Features:
--- - Highlighting is done only in modifiable buffer by default, only in Normal
---   mode, and stops in Insert mode and when leaving window.
---
--- - Trim all trailing whitespace with |MiniTrailspace.trim()|.
---
--- - Trim all trailing empty lines with |MiniTrailspace.trim_last_lines()|.
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.trailspace').setup({})`
--- (replace `{}` with your `config` table). It will create global Lua table
--- `MiniTrailspace` which you can use for scripting or manually (with
--- `:lua MiniTrailspace.*`).
---
--- See |MiniTrailspace.config| for `config` structure and default values.
---
--- You can override runtime config settings locally to buffer inside
--- `vim.b.minitrailspace_config` which should have same structure as
--- `MiniTrailspace.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- # Highlight groups ~
---
--- * `MiniTrailspace` - highlight group for trailing space.
---
--- To change any highlight group, modify it directly with |:highlight|.
---
--- # Disabling ~
---
--- To disable, set `vim.g.minitrailspace_disable` (globally) or
--- `vim.b.minitrailspace_disable` (for a buffer) to `true`. Considering high
--- number of different scenarios and customization intentions, writing exact
--- rules for disabling module's functionality is left to user. See
--- |mini.nvim-disabling-recipes| for common recipes. Note: after disabling
--- there might be highlighting left; it will be removed after next
--- highlighting update (see |events| and `MiniTrailspace` |augroup|).
---@tag MiniTrailspace

-- Module definition ==========================================================
local MiniTrailspace = {}
local H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniTrailspace.config|.
---
---@usage >lua
---   require('mini.trailspace').setup() -- use default config
---   -- OR
---   require('mini.trailspace').setup({}) -- replace {} with your config table
--- <
MiniTrailspace.setup = function(config)
  -- Export module
  _G.MiniTrailspace = MiniTrailspace

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Define behavior
  H.create_autocommands(config)

  -- Create default highlighting
  H.create_default_hl()

  -- Initialize highlight (usually takes effect during startup)
  vim.defer_fn(MiniTrailspace.highlight, 0)
end

--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
MiniTrailspace.config = {
  -- Highlight only in normal buffers (ones with empty 'buftype'). This is
  -- useful to not show trailing whitespace where it usually doesn't matter.
  only_in_normal_buffers = true,
}
--minidoc_afterlines_end

-- Module functionality =======================================================
--- Highlight trailing whitespace in current window
MiniTrailspace.highlight = function()
  -- Highlight only in normal mode
  if H.is_disabled() or vim.fn.mode() ~= 'n' then
    MiniTrailspace.unhighlight()
    return
  end

  -- Possibly work only in normal buffers
  if H.get_config().only_in_normal_buffers and not H.is_buffer_normal() then return end

  -- Don't add match id on top of existing one
  if H.get_match_id() ~= nil then return end

  vim.fn.matchadd('MiniTrailspace', [[\s\+$]])
end

--- Unhighlight trailing whitespace in current window
MiniTrailspace.unhighlight = function()
  -- Use `pcall` because there is an error if match id is not present. It can
  -- happen if something else called `clearmatches`.
  pcall(vim.fn.matchdelete, H.get_match_id())
end

--- Trim trailing whitespace
MiniTrailspace.trim = function()
  -- Save cursor position to later restore
  local curpos = vim.api.nvim_win_get_cursor(0)
  -- Search and replace trailing whitespace
  vim.cmd([[keeppatterns %s/\s\+$//e]])
  vim.api.nvim_win_set_cursor(0, curpos)
end

--- Trim last blank lines
MiniTrailspace.trim_last_lines = function()
  local n_lines = vim.api.nvim_buf_line_count(0)
  local last_nonblank = vim.fn.prevnonblank(n_lines)
  if last_nonblank < n_lines then vim.api.nvim_buf_set_lines(0, last_nonblank, n_lines, true, {}) end
end

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniTrailspace.config)

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  H.check_type('only_in_normal_buffers', config.only_in_normal_buffers, 'boolean')

  return config
end

H.apply_config = function(config) MiniTrailspace.config = config end

H.create_autocommands = function(config)
  local gr = vim.api.nvim_create_augroup('MiniTrailspace', {})

  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = gr, pattern = pattern, callback = callback, desc = desc })
  end

  -- NOTE: Respecting both `WinEnter` and `BufEnter` seems to be useful to
  -- account of different order of handling buffer opening in new window.
  -- Notable example: 'nvim-tree' at commit a1600e5.
  au({ 'WinEnter', 'BufEnter', 'InsertLeave' }, '*', MiniTrailspace.highlight, 'Highlight')
  au({ 'WinLeave', 'BufLeave', 'InsertEnter' }, '*', MiniTrailspace.unhighlight, 'Unhighlight')

  if config.only_in_normal_buffers then
    -- Add tracking of 'buftype' changing because it can be set after events on
    -- which highlighting is done. If not done, highlighting appears but
    -- disappears if buffer is reentered.
    au('OptionSet', 'buftype', H.track_normal_buffer, 'Track normal buffer')
  end

  au('ColorScheme', '*', H.create_default_hl, 'Ensure colors')
end

H.create_default_hl = function() vim.api.nvim_set_hl(0, 'MiniTrailspace', { default = true, link = 'Error' }) end

H.is_disabled = function() return vim.g.minitrailspace_disable == true or vim.b.minitrailspace_disable == true end

H.get_config = function(config)
  return vim.tbl_deep_extend('force', MiniTrailspace.config, vim.b.minitrailspace_config or {}, config or {})
end

H.track_normal_buffer = function()
  if not H.get_config().only_in_normal_buffers then return end

  -- This should be used with 'OptionSet' event for 'buftype' option
  -- Empty 'buftype' means "normal buffer"
  if vim.v.option_new == '' then
    MiniTrailspace.highlight()
  else
    MiniTrailspace.unhighlight()
  end
end

H.is_buffer_normal = function(buf_id) return vim.bo[buf_id or 0].buftype == '' end

H.get_match_id = function()
  -- NOTE: this can be replaced with more efficient custom tracking of id per
  -- window but it will have more edge cases (like won't update on manual
  -- `clearmatches()`)
  for _, match in ipairs(vim.fn.getmatches()) do
    if match.group == 'MiniTrailspace' then return match.id end
  end
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.trailspace) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

return MiniTrailspace
