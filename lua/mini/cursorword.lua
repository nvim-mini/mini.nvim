--- *mini.cursorword* Autohighlight word under cursor
---
--- MIT License Copyright (c) 2021 Evgeni Chasnovski

--- Features:
--- - Autohighlight word under cursor with customizable delay.
---
--- - Current word under cursor can be highlighted differently.
---
--- - Highlighting is triggered only if current cursor character is a |[:keyword:]|.
---
--- - Highlighting stops in insert and terminal modes.
---
--- - "Word under cursor" is meant as in Vim's |<cword>|: something user would
---   get as 'iw' text object.
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.cursorword').setup({})`
--- (replace `{}` with your `config` table). It will create global Lua table
--- `MiniCursorword` which you can use for scripting or manually (with
--- `:lua MiniCursorword.*`).
---
--- See |MiniCursorword.config| for `config` structure and default values.
---
--- You can override runtime config settings locally to buffer inside
--- `vim.b.minicursorword_config` which should have same structure as
--- `MiniCursorword.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- # Highlight groups ~
---
--- - `MiniCursorword` - highlight group of a non-current cursor word.
---   Default: plain underline.
---
--- - `MiniCursorwordCurrent` - highlight group of a current word under cursor.
---   Default: links to `MiniCursorword` (so `:hi clear MiniCursorwordCurrent`
---   will lead to showing `MiniCursorword` highlight group).
---   Note: To not highlight it, use the following Lua code: >lua
---
---   vim.api.nvim_set_hl(0, 'MiniCursorwordCurrent', {})
--- <
--- To change any highlight group, set it directly with |nvim_set_hl()|.
---
--- # Disabling ~
---
--- To disable core functionality, set `vim.g.minicursorword_disable` (globally) or
--- `vim.b.minicursorword_disable` (for a buffer) to `true`. Considering high
--- number of different scenarios and customization intentions, writing exact
--- rules for disabling module's functionality is left to user. See
--- |mini.nvim-disabling-recipes| for common recipes. Note: after disabling
--- there might be highlighting left; it will be removed after next
--- highlighting update.
---
--- Module-specific disabling:
--- - Don't show highlighting if cursor is on the word that is in a blocklist
---   of current filetype. In this example, blocklist for "lua" is "local" and
---   "require" words, for "javascript" - "import": >lua
---
---   _G.cursorword_blocklist = function()
---     local curword = vim.fn.expand('<cword>')
---     local filetype = vim.bo.filetype
---
---     -- Add any disabling global or filetype-specific logic here
---     local blocklist = {}
---     if filetype == 'lua' then
---       blocklist = { 'local', 'require' }
---     elseif filetype == 'javascript' then
---       blocklist = { 'import' }
---     end
---
---     vim.b.minicursorword_disable = vim.tbl_contains(blocklist, curword)
---   end
---
---   -- Make sure to add this autocommand *before* calling module's `setup()`.
---   vim.cmd('au CursorMoved * lua _G.cursorword_blocklist()')
--- <
---@tag MiniCursorword

-- Module definition ==========================================================
local MiniCursorword = {}
local H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniCursorword.config|.
---
---@usage >lua
---   require('mini.cursorword').setup() -- use default config
---   -- OR
---   require('mini.cursorword').setup({}) -- replace {} with your config table
--- <
MiniCursorword.setup = function(config)
  -- Export module
  _G.MiniCursorword = MiniCursorword

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Define behavior
  H.create_autocommands()

  -- Create default highlighting
  H.create_default_hl()
end

--- Defaults ~
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
MiniCursorword.config = {
  -- Delay (in ms) between when cursor moved and when highlighting appeared
  delay = 100,
}
--minidoc_afterlines_end

-- Module functionality =======================================================

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniCursorword.config)

-- Delay timer
H.timer = vim.uv.new_timer()

-- Information about last match highlighting (stored *per window*):
-- - Key: windows' unique buffer identifiers.
-- - Value: table with:
--     - `id` field for match id (from `vim.fn.matchadd()`).
--     - `word` field for matched word.
H.window_matches = {}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  H.check_type('delay', config.delay, 'number')

  return config
end

H.apply_config = function(config)
  MiniCursorword.config = config

  -- Make `setup()` to proper reset module
  for _, m in ipairs(vim.fn.getmatches()) do
    if vim.startswith(m.group, 'MiniCursorword') then vim.fn.matchdelete(m.id) end
  end
end

H.create_autocommands = function()
  local gr = vim.api.nvim_create_augroup('MiniCursorword', {})

  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = gr, pattern = pattern, callback = callback, desc = desc })
  end

  au('CursorMoved', '*', H.auto_highlight, 'Auto highlight cursorword')
  au({ 'InsertEnter', 'TermEnter', 'QuitPre' }, '*', H.auto_unhighlight, 'Auto unhighlight cursorword')
  au('ModeChanged', '*:[^i]', H.auto_highlight, 'Auto highlight cursorword')

  au('ColorScheme', '*', H.create_default_hl, 'Ensure colors')
  au('FileType', 'TelescopePrompt', function() vim.b.minicursorword_disable = true end, 'Disable locally')
end

--stylua: ignore
H.create_default_hl = function()
  vim.api.nvim_set_hl(0, 'MiniCursorword',        { default = true, underline = true })
  vim.api.nvim_set_hl(0, 'MiniCursorwordCurrent', { default = true, link = 'MiniCursorword' })
end

H.is_disabled = function() return vim.g.minicursorword_disable == true or vim.b.minicursorword_disable == true end

H.get_config = function(config)
  return vim.tbl_deep_extend('force', MiniCursorword.config, vim.b.minicursorword_config or {}, config or {})
end

-- Autocommands ---------------------------------------------------------------
H.auto_highlight = function()
  -- Stop any possible previous delayed highlighting
  H.timer:stop()

  -- Stop highlighting immediately if module is disabled when cursor is not on
  -- 'keyword'
  if not H.should_highlight() then return H.unhighlight() end

  -- Get current information
  local win_id = vim.api.nvim_get_current_win()
  local win_match = H.window_matches[win_id] or {}
  local curword = H.get_cursor_word()

  -- Only immediately update highlighting of current word under cursor if
  -- currently highlighted word equals one under cursor
  if win_match.word == curword then
    H.unhighlight(true)
    H.highlight(true)
    return
  end

  -- Stop highlighting previous match (if it exists)
  H.unhighlight()

  -- Delay highlighting
  H.timer:start(
    H.get_config().delay,
    0,
    vim.schedule_wrap(function()
      -- Ensure that always only one word is highlighted
      H.unhighlight()
      H.highlight()
    end)
  )
end

H.auto_unhighlight = function()
  -- Stop any possible previous delayed highlighting
  H.timer:stop()
  H.unhighlight()
end

-- Highlighting ---------------------------------------------------------------
---@param only_current boolean|nil Whether to forcefully highlight only current word
---   under cursor.
---@private
H.highlight = function(only_current)
  -- A modified version of https://stackoverflow.com/a/25233145
  -- Using `matchadd()` instead of a simpler `:match` to tweak priority of
  -- 'current word' highlighting: with `:match` it is higher than for
  -- `incsearch` which is not convenient.
  local win_id = vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(win_id) then return end

  if not H.should_highlight() then return end

  H.window_matches[win_id] = H.window_matches[win_id] or {}

  -- Add match highlight for current word under cursor
  local current_word_pattern = [[\k*\%#\k*]]
  local match_id_current = vim.fn.matchadd('MiniCursorwordCurrent', current_word_pattern, -1)
  H.window_matches[win_id].id_current = match_id_current

  -- Don't add main match id if not needed or if one is already present
  if only_current or H.window_matches[win_id].id ~= nil then return end

  -- Add match highlight for non-current word under cursor. NOTEs:
  -- - Using `\(...\)\@!` allows to not match current word.
  -- - Using 'very nomagic' ('\V') allows not escaping.
  -- - Using `\<` and `\>` matches whole word (and not as part).
  local curword = H.get_cursor_word()
  local pattern = string.format([[\(%s\)\@!\&\V\<%s\>]], current_word_pattern, curword)
  local match_id = vim.fn.matchadd('MiniCursorword', pattern, -1)

  -- Store information about highlight
  H.window_matches[win_id].id = match_id
  H.window_matches[win_id].word = curword
end

---@param only_current boolean|nil Whether to remove highlighting only of current
---   word under cursor.
---@private
H.unhighlight = function(only_current)
  -- Don't do anything if there is no valid information to act upon
  local win_id = vim.api.nvim_get_current_win()
  local win_match = H.window_matches[win_id]
  if not vim.api.nvim_win_is_valid(win_id) or win_match == nil then return end

  -- Use `pcall` because there is an error if match id is not present. It can
  -- happen if something else called `clearmatches`.
  pcall(vim.fn.matchdelete, win_match.id_current)
  H.window_matches[win_id].id_current = nil

  if not only_current then
    pcall(vim.fn.matchdelete, win_match.id)
    H.window_matches[win_id] = nil
  end
end

H.should_highlight = function() return not H.is_disabled() and H.is_cursor_on_keyword() end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.cursorword) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.is_cursor_on_keyword = function()
  local col = vim.fn.col('.')
  local curchar = vim.api.nvim_get_current_line():sub(col, col)

  -- Use `pcall()` to catch `E5108` (can happen in binary files, see #112)
  local ok, match_res = pcall(vim.fn.match, curchar, '[[:keyword:]]')
  return ok and match_res >= 0
end

H.get_cursor_word = function() return vim.fn.escape(vim.fn.expand('<cword>'), [[\/]]) end

return MiniCursorword
