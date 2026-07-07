--- *mini.bufremove* Remove buffers
---
--- MIT License Copyright (c) 2021 Evgeni Chasnovski

--- Features:
--- - Unshow, delete, and wipeout buffer while saving window layout
---   (opposite to builtin Neovim's commands).
---
--- # Setup ~
---
--- This module doesn't need setup, but it can be done to improve usability.
--- Setup with `require('mini.bufremove').setup({})` (replace `{}` with your
--- `config` table). It will create global Lua table `MiniBufremove` which you
--- can use for scripting or manually (with `:lua MiniBufremove.*`).
---
--- See |MiniBufremove.config| for `config` structure and default values.
---
--- This module doesn't have runtime options, so using `vim.b.minibufremove_config`
--- will have no effect here.
---
--- To stop module from showing non-error feedback, set `config.silent = true`.
---
--- # Notes ~
---
--- 1. Which buffer to show in window(s) after its current buffer is removed is
---    decided by the algorithm:
---    - If alternate buffer (see |CTRL-^|) is listed (see |buflisted()|), use it.
---    - If previous listed buffer (see |:bprevious|) is different, use it.
---    - Otherwise create a new one with `nvim_create_buf(true, false)` and use it.
---
--- # Disabling ~
---
--- To disable core functionality, set `vim.g.minibufremove_disable` (globally) or
--- `vim.b.minibufremove_disable` (for a buffer) to `true`. Considering high
--- number of different scenarios and customization intentions, writing exact
--- rules for disabling module's functionality is left to user. See
--- |mini.nvim-disabling-recipes| for common recipes.
---@tag MiniBufremove

---@alias __bufremove_return boolean|nil Whether operation was successful. If `nil`, no operation was done.
---@alias __bufremove_buf_id number|nil Buffer identifier (see |bufnr()|) to use.
---   Default: 0 for current.
---@alias __bufremove_force boolean|nil Whether to ignore unsaved changes (using `!` version of
---   command). If `false`, calling with unsaved changes will prompt confirm dialog.
---   Default: `false`.

-- Module definition ==========================================================
local MiniBufremove = {}
local H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniBufremove.config|.
---
---@usage >lua
---   require('mini.bufremove').setup() -- use default config
---   -- OR
---   require('mini.bufremove').setup({}) -- replace {} with your config table
--- <
MiniBufremove.setup = function(config)
  -- Export module
  _G.MiniBufremove = MiniBufremove

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)
end

--- Defaults ~
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
MiniBufremove.config = {
  -- Whether to disable showing non-error feedback
  silent = false,
}
--minidoc_afterlines_end

-- Module functionality =======================================================
--- Delete buffer `buf_id` with |:bdelete| after unshowing it
---
---@param buf_id __bufremove_buf_id
---@param force __bufremove_force
---
---@return __bufremove_return
MiniBufremove.delete = function(buf_id, force)
  if H.is_disabled() then return end

  return H.unshow_and_cmd(buf_id, force, 'bdelete')
end

--- Wipeout buffer `buf_id` with |:bwipeout| after unshowing it
---
---@param buf_id __bufremove_buf_id
---@param force __bufremove_force
---
---@return __bufremove_return
MiniBufremove.wipeout = function(buf_id, force)
  if H.is_disabled() then return end

  return H.unshow_and_cmd(buf_id, force, 'bwipeout')
end

--- Stop showing buffer `buf_id` in all windows
---
---@param buf_id __bufremove_buf_id
---
---@return __bufremove_return
MiniBufremove.unshow = function(buf_id)
  if H.is_disabled() then return end

  buf_id = H.normalize_buf_id(buf_id)

  if not H.is_valid_id(buf_id, 'buffer') then return false end

  vim.tbl_map(MiniBufremove.unshow_in_window, vim.fn.win_findbuf(buf_id))

  return true
end

--- Stop showing current buffer of window `win_id`
---
--- Notes:
--- - If `win_id` represents |cmdline-window|, this function will close it.
---
---@param win_id number|nil Window identifier (see |win_getid()|) to use.
---   Default: 0 for current.
---
---@return __bufremove_return
MiniBufremove.unshow_in_window = function(win_id)
  if H.is_disabled() then return nil end

  win_id = (win_id == nil) and 0 or win_id

  if not H.is_valid_id(win_id, 'window') then return false end

  local cur_buf = vim.api.nvim_win_get_buf(win_id)

  -- Temporary use window `win_id` as current to have Vim's functions working
  vim.api.nvim_win_call(win_id, function()
    if vim.fn.getcmdwintype() ~= '' then
      vim.cmd('close!')
      return
    end

    -- Try using alternate buffer
    local alt_buf = vim.fn.bufnr('#')
    if alt_buf ~= cur_buf and vim.fn.buflisted(alt_buf) == 1 then
      vim.api.nvim_win_set_buf(win_id, alt_buf)
      return
    end

    -- Try using previous buffer
    local has_previous = pcall(vim.cmd, 'bprevious')
    if has_previous and cur_buf ~= vim.api.nvim_win_get_buf(win_id) then return end

    -- Create new listed scratch buffer
    -- NOTE: leave it unnamed to allow `:h buffer-reuse`
    local new_buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_win_set_buf(win_id, new_buf)
  end)

  return true
end

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniBufremove.config)

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  H.check_type('silent', config.silent, 'boolean')

  return config
end

H.apply_config = function(config) MiniBufremove.config = config end

H.is_disabled = function() return vim.g.minibufremove_disable == true or vim.b.minibufremove_disable == true end

-- Removing implementation ----------------------------------------------------
H.unshow_and_cmd = function(buf_id, force, cmd)
  buf_id = H.normalize_buf_id(buf_id)
  if not H.is_valid_id(buf_id, 'buffer') then
    H.message(buf_id .. ' is not a valid buffer id.')
    return false
  end

  if force == nil then force = false end
  if type(force) ~= 'boolean' then
    H.message('`force` should be boolean.')
    return false
  end

  local fun_name = ({ ['bdelete'] = 'delete', ['bwipeout'] = 'wipeout' })[cmd]
  if not H.can_remove(buf_id, force, fun_name) then return false end

  -- Unshow buffer from all windows
  MiniBufremove.unshow(buf_id)

  -- Execute command
  local command = string.format('%s! %d', cmd, buf_id)
  -- Use `pcall` here to take care of case where `unshow()` was enough. This
  -- can happen with 'bufhidden' option values:
  -- - If `delete` then `unshow()` already `bdelete`d buffer. Without `pcall`
  --   it gives E516 for `MiniBufremove.delete()` (`wipeout` works).
  -- - If `wipe` then `unshow()` already `bwipeout`ed buffer. Without `pcall`
  --   it gives E517 for module's `wipeout()` (still E516 for `delete()`).
  --
  -- Also account for executing command in command-line window.
  -- It gives E11 if trying to execute command. The `unshow()` call should
  -- close such window but somehow it doesn't seem to happen immediately.
  local ok, result = pcall(vim.cmd, command)
  if not (ok or result:find('E516%D') or result:find('E517%D') or result:find('E11%D')) then
    H.message(result)
    return false
  end

  return true
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.bufremove) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.echo = function(msg, is_important)
  if MiniBufremove.config.silent then return end

  -- Construct message chunks
  msg = type(msg) == 'string' and { { msg } } or msg
  table.insert(msg, 1, { '(mini.bufremove) ', 'WarningMsg' })

  -- Echo. Force redraw to ensure that it is effective (`:h echo-redraw`)
  vim.cmd([[echo '' | redraw]])
  vim.api.nvim_echo(msg, is_important, {})
end

H.message = function(msg) H.echo(msg, true) end

H.is_valid_id = function(x, type)
  local is_valid = false
  if type == 'buffer' then
    is_valid = vim.api.nvim_buf_is_valid(x)
  elseif type == 'window' then
    is_valid = vim.api.nvim_win_is_valid(x)
  end

  if not is_valid then H.message(string.format('%s is not a valid %s id.', tostring(x), type)) end
  return is_valid
end

-- Check if buffer can be removed with `MiniBufremove.fun_name` function
H.can_remove = function(buf_id, force, fun_name)
  if force or not vim.bo[buf_id].modified then return true end
  local msg = string.format('Buffer %d has unsaved changes. Do you want to force %s?', buf_id, fun_name)
  return vim.fn.confirm(msg, '&No\n&Yes', 1, 'Question') == 2
end

-- Compute 'true' buffer id (strictly positive integer). Treat `nil` and 0 as
-- current buffer.
H.normalize_buf_id = function(buf_id)
  if buf_id == nil or buf_id == 0 then return vim.api.nvim_get_current_buf() end
  return buf_id
end

return MiniBufremove
