--- *mini.pairs* Autopairs
--- *MiniPairs*
---
--- MIT License Copyright (c) 2021 Evgeni Chasnovski
---
--- ==============================================================================
---
--- Features:
--- - Functionality to work with two "paired" characters conditional on cursor's
---   neighborhood (character to its left and character to its right).
---
--- - Usage should be through making appropriate mappings using |MiniPairs.map|
---   or in |MiniPairs.setup| (for global mapping), |MiniPairs.map_buf| (for
---   buffer mapping).
---
--- - Pairs get automatically registered for special <BS> (all configured modes)
---   and <CR> (only Insert mode) mappings. Pressing the key inside pair will
---   delete whole pair and insert extra blank line inside pair respectively.
---   Note: these mappings are autocreated if they do not override existing ones.
---
--- What it doesn't do:
--- - It doesn't support multiple characters as "open" and "close" symbols. Use
---   snippets for that.
---
--- - It doesn't support dependency on filetype. Use |i_CTRL-V| to insert
---   single symbol or `autocmd` command or 'after/ftplugin' approach to:
---     - `:lua MiniPairs.map_buf(0, 'i', <*>, <pair_info>)` - make new mapping
---       for '<*>' in current buffer.
---     - `:lua MiniPairs.unmap_buf(0, 'i', <*>, <pair>)` - unmap key `<*>` while
---       unregistering `<pair>` pair in current buffer. Note: this reverts
---       mapping done by |MiniPairs.map_buf|. If mapping was done with
---       |MiniPairs.map|, unmap for buffer in usual Neovim manner:
---       `inoremap <buffer> <*> <*>` (this maps `<*>` key to do the same it
---       does by default).
---     - Disable module for buffer (see 'Disabling' section).
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.pairs').setup({})`
--- (replace `{}` with your `config` table). It will create global Lua table
--- `MiniPairs` which you can use for scripting or manually (with
--- `:lua MiniPairs.*`).
---
--- See |MiniPairs.config| for `config` structure and default values.
---
--- This module doesn't have runtime options, so using `vim.b.minipairs_config`
--- will have no effect here.
---
--- # Example mappings ~
--- >lua
---   -- Register quotes inside `config` of `MiniPairs.setup()`
---   mappings = {
---     ['"'] = { register = { cr = true } },
---     ["'"] = { register = { cr = true } },
---   }
---
---   -- Insert `<>` pair if `<` is typed at line start, don't register for <CR>
---   local lt_opts = {
---     action = 'open',
---     pair = '<>',
---     neigh_pattern = '\r.',
---     register = { cr = false },
---   }
---   MiniPairs.map('i', '<', lt_opts)
---
---   local gt_opts = { action = 'close', pair = '<>', register = { cr = false } }
---   MiniPairs.map('i', '>', gt_opts)
---
---   -- Create symmetrical `$$` pair only in Tex files
---   local map_tex = function()
---     MiniPairs.map_buf(0, 'i', '$', { action = 'closeopen', pair = '$$' })
---   end
---   vim.api.nvim_create_autocmd(
---     'FileType',
---     { pattern = 'tex', callback = map_tex }
---   )
--- <
--- # Notes ~
---
--- - Make sure to make proper mapping of <CR> in order to support completion
---   plugin of your choice:
---     - For |MiniCompletion| see 'Helpful key mappings' section.
---     - For current implementation of "hrsh7th/nvim-cmp" there is no need to
---       make custom mapping. You can use default setup, which will confirm
---       completion selection if popup is visible and expand pair otherwise.
--- - Having mapping in terminal mode can conflict with:
---     - Autopairing capabilities of interpretators (`ipython`, `radian`).
---     - Vim mode of terminal itself.
---
--- # Disabling ~
---
--- To disable, set `vim.g.minipairs_disable` (globally) or `vim.b.minipairs_disable`
--- (for a buffer) to `true`. Considering high number of different scenarios
--- and customization intentions, writing exact rules for disabling module's
--- functionality is left to user. See |mini.nvim-disabling-recipes| for common
--- recipes.

---@alias __pairs_neigh_pattern string|nil Pattern for two neighborhood characters.
---   Character "\r" indicates line start, "\n" - line end.
---@alias __pairs_pair string String with two characters representing pair.
---@alias __pairs_unregistered_pair string Pair which should be unregistered from both <BS> and <CR>.
---   Should be explicitly supplied to avoid confusion.
---   Supply `''` to not unregister pair.

-- Module definition ==========================================================
local MiniPairs = {}
local H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniPairs.config|.
---
---@usage >lua
---   require('mini.pairs').setup() -- use default config
---   -- OR
---   require('mini.pairs').setup({}) -- replace {} with your config table
--- <
MiniPairs.setup = function(config)
  -- Export module
  _G.MiniPairs = MiniPairs

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Define behavior
  H.create_autocommands()
end

--stylua: ignore
--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
MiniPairs.config = {
  -- In which modes mappings from this `config` should be created
  modes = { insert = true, command = false, terminal = false },

  -- Global mappings. Each right hand side should be a pair information, a
  -- table with at least these fields (see more in |MiniPairs.map|):
  -- - <action> - one of "open", "close", "closeopen".
  -- - <pair> - two character string for pair to be used.
  -- By default pair is not inserted after `\`, quotes are not recognized by
  -- <CR>, `'` does not insert pair after a letter.
  -- Only parts of tables can be tweaked (others will use these defaults).
  -- Supply `false` instead of table to not map particular key.
  mappings = {
    ['('] = { action = 'open', pair = '()', neigh_pattern = '[^\\].' },
    ['['] = { action = 'open', pair = '[]', neigh_pattern = '[^\\].' },
    ['{'] = { action = 'open', pair = '{}', neigh_pattern = '[^\\].' },

    [')'] = { action = 'close', pair = '()', neigh_pattern = '[^\\].' },
    [']'] = { action = 'close', pair = '[]', neigh_pattern = '[^\\].' },
    ['}'] = { action = 'close', pair = '{}', neigh_pattern = '[^\\].' },

    ['"'] = { action = 'closeopen', pair = '""', neigh_pattern = '[^\\].',   register = { cr = false } },
    ["'"] = { action = 'closeopen', pair = "''", neigh_pattern = '[^%a\\].', register = { cr = false } },
    ['`'] = { action = 'closeopen', pair = '``', neigh_pattern = '[^\\].',   register = { cr = false } },
  },
}
--minidoc_afterlines_end

-- Module functionality =======================================================
--- Make global mapping
---
--- This is a wrapper for |nvim_set_keymap()| but instead of right hand side of
--- mapping (as string) it expects table with pair information.
---
--- Using this function instead of |nvim_set_keymap()| allows automatic
--- registration of pairs which will be recognized by <BS> and <CR>.
--- It also infers mapping description from `pair_info`.
---
---@param mode string `mode` for |nvim_set_keymap()|.
---@param lhs string `lhs` for |nvim_set_keymap()|.
---@param pair_info table Table with pair information. Fields:
---   - <action> - one of "open" (for |MiniPairs.open|),
---     "close" (for |MiniPairs.close|), or "closeopen" (for |MiniPairs.closeopen|).
---   - <pair> - two character string to be used as argument for action function.
---     Can contain multibyte characters.
---   - <neigh_pattern> - optional 'two character' neighborhood pattern to be
---     used as argument for action function. Note: neighborhood might contain
---     multiple characters.
---     Default: `'..'` (no restriction from neighborhood).
---   - <register> - optional table with information about whether this pair will
---     be recognized by <BS> (in |MiniPairs.bs|) and/or <CR> (in |MiniPairs.cr|).
---     Should have boolean fields <bs> and <cr> (both `true` by default).
---@param opts table|nil Optional table `opts` for |nvim_set_keymap()|. Elements
---   `expr` and `noremap` won't be recognized (`true` by default).
MiniPairs.map = function(mode, lhs, pair_info, opts)
  pair_info = H.validate_pair_info(pair_info)
  opts = vim.tbl_deep_extend('force', opts or {}, { expr = true, noremap = true })
  opts.desc = H.infer_mapping_description(pair_info)

  vim.api.nvim_set_keymap(mode, lhs, H.pair_info_to_map_rhs(pair_info), opts)
  H.register_pair(pair_info, mode, 'all')

  -- Ensure that <BS> and <CR> are mapped for input mode
  H.ensure_cr_bs(mode)
end

--- Make buffer mapping
---
--- This is a wrapper for |nvim_buf_set_keymap()| but instead of string right
--- hand side of mapping it expects table with pair information similar to one
--- in |MiniPairs.map|.
---
--- Using this function instead of |nvim_buf_set_keymap()| allows automatic
--- registration of pairs which will be recognized by <BS> and <CR>.
--- It also infers mapping description from `pair_info`.
---
---@param buffer number `buffer` for |nvim_buf_set_keymap()|.
---@param mode string `mode` for |nvim_buf_set_keymap()|.
---@param lhs string `lhs` for |nvim_buf_set_keymap()|.
---@param pair_info table Table with pair information.
---@param opts table|nil Optional table `opts` for |nvim_buf_set_keymap()|.
---   Elements `expr` and `noremap` won't be recognized (`true` by default).
MiniPairs.map_buf = function(buffer, mode, lhs, pair_info, opts)
  pair_info = H.validate_pair_info(pair_info)
  opts = vim.tbl_deep_extend('force', opts or {}, { expr = true, noremap = true })
  opts.desc = H.infer_mapping_description(pair_info)

  vim.api.nvim_buf_set_keymap(buffer, mode, lhs, H.pair_info_to_map_rhs(pair_info), opts)
  H.register_pair(pair_info, mode, buffer == 0 and vim.api.nvim_get_current_buf() or buffer)

  -- Ensure that <BS> and <CR> are mapped for input mode
  H.ensure_cr_bs(mode)
end

--- Remove global mapping
---
--- A wrapper for |nvim_del_keymap()| which registers supplied `pair`.
---
---@param mode string `mode` for |nvim_del_keymap()|.
---@param lhs string `lhs` for |nvim_del_keymap()|.
---@param pair __pairs_unregistered_pair
MiniPairs.unmap = function(mode, lhs, pair)
  -- `pair` should be supplied explicitly
  H.check_type('pair', pair, 'string')

  -- Use `pcall` to allow 'deleting' already deleted mapping
  pcall(vim.api.nvim_del_keymap, mode, lhs)
  if pair == '' then return end
  H.unregister_pair(pair, mode, 'all')
end

--- Remove buffer mapping
---
--- Wrapper for |nvim_buf_del_keymap()| which also unregisters supplied `pair`.
---
--- Note: this only reverts mapping done by |MiniPairs.map_buf|. If mapping was
--- done with |MiniPairs.map|, revert to default behavior for buffer: >lua
---
---   -- Map `X` key to do the same it does by default
---   vim.keymap.set('i', 'X', 'X', { buffer = true })
--- <
---@param buffer number `buffer` for |nvim_buf_del_keymap()|.
---@param mode string `mode` for |nvim_buf_del_keymap()|.
---@param lhs string `lhs` for |nvim_buf_del_keymap()|.
---@param pair __pairs_unregistered_pair
MiniPairs.unmap_buf = function(buffer, mode, lhs, pair)
  -- `pair` should be supplied explicitly
  H.check_type('pair', pair, 'string')

  -- Use `pcall` to allow 'deleting' already deleted mapping
  pcall(vim.api.nvim_buf_del_keymap, buffer, mode, lhs)
  if pair == '' then return end
  H.unregister_pair(pair, mode, buffer == 0 and vim.api.nvim_get_current_buf() or buffer)
end

--- Process "open" symbols
---
--- Used as |map-expr| mapping for "open" symbols in asymmetric pair ('(', '[',
--- etc.). If neighborhood doesn't match supplied pattern, function results
--- into "open" symbol. Otherwise, it pastes whole pair and moves inside pair
--- with |<Left>|.
---
--- Used inside |MiniPairs.map| and |MiniPairs.map_buf| for an actual mapping.
---
---@param pair __pairs_pair
---@param neigh_pattern __pairs_neigh_pattern
---
---@return string Keys performing "open" action.
MiniPairs.open = function(pair, neigh_pattern)
  if H.is_disabled() or not H.neigh_match(neigh_pattern) then return H.get_open_char(pair) end

  -- Temporarily redraw lazily for no cursor flicker due to `<Left>`.
  -- This can happen in a big file with tree-sitter highlighting enabled.
  H.with_temp_option('lazyredraw', true)

  return pair .. H.get_arrow_key('left')
end

--- Process "close" symbols
---
--- Used as |map-expr| mapping for "close" symbols in asymmetric pair (')',
--- ']', etc.). If neighborhood doesn't match supplied pattern, function
--- results into "close" symbol. Otherwise it jumps over symbol to the right of
--- cursor (with |<Right>|) if it is equal to "close" one and inserts it
--- otherwise.
---
--- Used inside |MiniPairs.map| and |MiniPairs.map_buf| for an actual mapping.
---
---@param pair __pairs_pair
---@param neigh_pattern __pairs_neigh_pattern
---
---@return string Keys performing "close" action.
MiniPairs.close = function(pair, neigh_pattern)
  local close = H.get_close_char(pair)
  local move_right = not H.is_disabled() and H.neigh_match(neigh_pattern) and H.get_neigh('right') == close
  return move_right and H.get_arrow_key('right') or close
end

--- Process "closeopen" symbols
---
--- Used as |map-expr| mapping for 'symmetrical' symbols (from pairs '""',
--- '\'\'', '``').  It tries to perform 'closeopen action': move over right
--- character (with |<Right>|) if it is equal to second character from pair or
--- conditionally paste pair otherwise (with |MiniPairs.open()|).
---
--- Used inside |MiniPairs.map| and |MiniPairs.map_buf| for an actual mapping.
---
---@param pair __pairs_pair
---@param neigh_pattern __pairs_neigh_pattern
---
---@return string Keys performing "closeopen" action.
MiniPairs.closeopen = function(pair, neigh_pattern)
  local move_right = not H.is_disabled() and H.get_neigh('right') == H.get_close_char(pair)
  return move_right and H.get_arrow_key('right') or MiniPairs.open(pair, neigh_pattern)
end

--- Process |<BS>|
---
--- Used as |map-expr| mapping for <BS> in Insert mode. It removes whole pair
--- (via executing <Del> after input key) if neighborhood is equal to a whole
--- pair recognized for current buffer. Pair is recognized for current buffer
--- if it is registered for global or current buffer mapping. Pair is
--- registered as a result of calling |MiniPairs.map| or |MiniPairs.map_buf|.
---
--- Mapped by default inside |MiniPairs.setup|.
---
--- This can be used to modify other Insert mode keys to respect neighborhood
--- pair. Examples: >lua
---
---   local map_bs = function(lhs, rhs)
---     vim.keymap.set('i', lhs, rhs, { expr = true, replace_keycodes = false })
---   end
---
---   map_bs('<C-h>', 'v:lua.MiniPairs.bs()')
---   map_bs('<C-w>', 'v:lua.MiniPairs.bs("\23")')
---   map_bs('<C-u>', 'v:lua.MiniPairs.bs("\21")')
--- <
---@param key string|nil Key to use. Default: `'<BS>'`.
---
---@return string Keys performing "backspace" action.
MiniPairs.bs = function(key)
  local res, neigh = key or H.keys.bs, H.get_neigh('whole')
  local do_extra = not H.is_disabled() and H.is_pair_registered(neigh, vim.fn.mode(), 'bs')
  return do_extra and (res .. H.keys.del) or res
end

--- Process |i_<CR>|
---
--- Used as |map-expr| mapping for <CR> in insert mode. It puts "close"
--- symbol on next line (via `<CR><C-o>O`) if neighborhood is equal to a whole
--- pair recognized for current buffer. Pair is recognized for current buffer
--- if it is registered for global or current buffer mapping. Pair is
--- registered as a result of calling |MiniPairs.map| or |MiniPairs.map_buf|.
---
--- Note: some relevant mode changing events are temporarily ignored
--- (with |eventignore|) to counter effect of using |i_CTRL-O|.
---
--- Mapped by default inside |MiniPairs.setup|.
---
---@param key string|nil Key to use. Default: `'<CR>'`.
---
---@return string Keys performing "new line" action.
MiniPairs.cr = function(key)
  local res = key or H.keys.cr

  local neigh = H.get_neigh('whole')
  if H.is_disabled() or not H.is_pair_registered(neigh, vim.fn.mode(), 'cr') then return res end

  -- Temporarily ignore mode change to not trigger some common expensive
  -- autocommands (like diagnostic check, etc.)
  H.with_temp_option('eventignore', 'InsertLeave,InsertLeavePre,InsertEnter,TextChanged,ModeChanged')

  -- Temporarily redraw lazily for no cursor flicker due to `<C-o>O`.
  -- This can happen in a big file with tree-sitter highlighting enabled.
  H.with_temp_option('lazyredraw', true)

  return res .. H.keys.above
end

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniPairs.config)

-- Default value of `pair_info` for mapping functions
H.default_pair_info = { neigh_pattern = '..', register = { bs = true, cr = true } }

-- Pair sets registered *per mode-buffer-key*. Buffer `'all'` contains pairs
-- registered for all buffers.
H.registered_pairs = {
  i = { all = { bs = {}, cr = {} } },
  c = { all = { bs = {}, cr = {} } },
  t = { all = { bs = {}, cr = {} } },
}

-- Precomputed keys to increase speed
-- stylua: ignore start
local function escape(s) return vim.api.nvim_replace_termcodes(s, true, true, true) end
H.keys = {
  above      = escape('<C-o>O'),
  bs         = escape('<BS>'),
  cr         = escape('<CR>'),
  del        = escape('<Del>'),
  keep_undo  = escape('<C-g>U'),
  -- Using left/right keys in insert mode breaks undo sequence and, more
  -- importantly, dot-repeat. To avoid this, use 'i_CTRL-G_U' mapping.
  -- Use `H.get_arrow_key()` for keys instead of direct from this table.
  left       = escape('<Left>'),
  right      = escape('<Right>'),
  left_undo  = escape('<C-g>U<Left>'),
  right_undo = escape('<C-g>U<Right>'),
}
-- stylua: ignore end

-- Cache for temporary set options
H.options_cache = {}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  H.check_type('modes', config.modes, 'table')
  H.check_type('modes.insert', config.modes.insert, 'boolean')
  H.check_type('modes.command', config.modes.command, 'boolean')
  H.check_type('modes.terminal', config.modes.terminal, 'boolean')

  H.check_type('mappings', config.mappings, 'table')

  local validate_mapping = function(pair_info, prefix)
    -- Allow `false` to not create mapping
    if pair_info == false then return end
    H.validate_pair_info(pair_info, prefix)
  end

  validate_mapping(config.mappings['('], "mappings['(']")
  validate_mapping(config.mappings['['], "mappings['[']")
  validate_mapping(config.mappings['{'], "mappings['{']")
  validate_mapping(config.mappings[')'], "mappings[')']")
  validate_mapping(config.mappings[']'], "mappings[']']")
  validate_mapping(config.mappings['}'], "mappings['}']")
  validate_mapping(config.mappings['"'], "mappings['\"']")
  validate_mapping(config.mappings["'"], 'mappings["\'"]')
  validate_mapping(config.mappings['`'], "mappings['`']")

  return config
end

H.apply_config = function(config)
  MiniPairs.config = config

  -- Setup mappings in supplied modes
  local mode_ids = { insert = 'i', command = 'c', terminal = 't' }
  -- Compute in which modes mapping should be set up
  local mode_array = {}
  for name, to_set in pairs(config.modes) do
    if to_set then table.insert(mode_array, mode_ids[name]) end
  end

  local map_conditionally = function(mode, key, pair_info)
    -- Allow `false` to not create mapping
    if pair_info == false then return end

    -- This also should take care of mapping <BS> and <CR>
    MiniPairs.map(mode, key, pair_info)
  end

  for _, mode in pairs(mode_array) do
    for key, pair_info in pairs(config.mappings) do
      map_conditionally(mode, key, pair_info)
    end
  end
end

H.create_autocommands = function()
  local gr = vim.api.nvim_create_augroup('MiniPairs', {})

  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = gr, pattern = pattern, callback = callback, desc = desc })
  end

  au('FileType', { 'TelescopePrompt', 'fzf' }, function() vim.b.minipairs_disable = true end, 'Disable locally')
end

H.is_disabled = function() return vim.g.minipairs_disable == true or vim.b.minipairs_disable == true end

-- Pair registration ----------------------------------------------------------
H.register_pair = function(pair_info, mode, buffer)
  -- Process new mode
  H.registered_pairs[mode] = H.registered_pairs[mode] or { all = { bs = {}, cr = {} } }
  local mode_pairs = H.registered_pairs[mode]

  -- Process new buffer
  local buf_pairs = mode_pairs[buffer] or { bs = {}, cr = {} }
  mode_pairs[buffer] = buf_pairs

  -- Register pair in a buffer or 'all'. NOTE: ensure to add entry only if
  -- `register[key]` is `true` for a faster check in `is_pair_registered`.
  local register, pair = pair_info.register, pair_info.pair
  buf_pairs.bs[pair] = register.bs == true and true or nil
  buf_pairs.cr[pair] = register.cr == true and true or nil
end

H.unregister_pair = function(pair, mode, buffer)
  local mode_pairs = H.registered_pairs[mode]
  if not (mode_pairs and mode_pairs[buffer]) then return end

  local buf_pairs = mode_pairs[buffer]
  buf_pairs.bs[pair], buf_pairs.cr[pair] = nil, nil
end

H.is_pair_registered = function(pair, mode, key)
  local mode_pairs = H.registered_pairs[mode]
  if not mode_pairs then return false end

  if mode_pairs['all'][key][pair] then return true end

  local buf_pairs = mode_pairs[vim.api.nvim_get_current_buf()]
  if not buf_pairs then return false end

  return buf_pairs[key][pair] == true
end

H.ensure_cr_bs = function(mode)
  local has_any_cr_pair, has_any_bs_pair = false, false
  for _, pair_tbl in pairs(H.registered_pairs[mode]) do
    has_any_cr_pair = has_any_cr_pair or not vim.tbl_isempty(pair_tbl.cr)
    has_any_bs_pair = has_any_bs_pair or not vim.tbl_isempty(pair_tbl.bs)
  end

  -- NOTE: this doesn't distinguish between global and buffer mappings. Both
  -- <BS> and <CR> should work as normal even if no pairs are registered
  -- NOTE: do not autocreate mappings if there is already one present. This
  -- allows creating more complicated `<CR>`/`<BS>` mappings and not worry
  -- about the initialization/setup order.
  if has_any_bs_pair and vim.fn.maparg('<BS>', mode) == '' then
    -- Use not `silent` in Command mode to make it redraw
    local opts = { silent = mode ~= 'c', expr = true, replace_keycodes = false, desc = 'MiniPairs <BS>' }
    H.map(mode, '<BS>', 'v:lua.MiniPairs.bs()', opts)
  end
  if mode == 'i' and has_any_cr_pair and vim.fn.maparg('<CR>', mode) == '' then
    local opts = { expr = true, replace_keycodes = false, desc = 'MiniPairs <CR>' }
    H.map(mode, '<CR>', 'v:lua.MiniPairs.cr()', opts)
  end
end

-- Work with pair_info --------------------------------------------------------
H.validate_pair_info = function(x, prefix)
  prefix = prefix or 'pair_info'
  H.check_type(prefix, x, 'table')
  x = vim.tbl_deep_extend('force', H.default_pair_info, x)

  H.check_type(prefix .. '.action', x.action, 'string')
  H.check_type(prefix .. '.pair', x.pair, 'string')
  H.check_type(prefix .. '.neigh_pattern', x.neigh_pattern, 'string')
  H.check_type(prefix .. '.register', x.register, 'table')

  H.check_type(prefix .. '.register.bs', x.register.bs, 'boolean')
  H.check_type(prefix .. '.register.cr', x.register.cr, 'boolean')

  return x
end

H.pair_info_to_map_rhs = function(x)
  return string.format('v:lua.MiniPairs.%s(%s, %s)', x.action, vim.inspect(x.pair), vim.inspect(x.neigh_pattern))
end

H.infer_mapping_description = function(x)
  local action_name = x.action:sub(1, 1):upper() .. x.action:sub(2)
  return string.format('%s action for %s pair', action_name, vim.inspect(x.pair))
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.pairs) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.get_neigh = function(neigh_type)
  local is_command_mode = vim.fn.mode() == 'c'
  -- Get line and add '\r' and '\n' to always return 2 characters
  local line = is_command_mode and vim.fn.getcmdline() or vim.api.nvim_get_current_line()
  line = '\r' .. line .. '\n'
  -- Get start character index accounting for added '\r' at the start
  local start = is_command_mode and vim.fn.charidx(line, vim.fn.getcmdpos()) or vim.fn.charcol('.')
  start = start - 1

  return vim.fn.strcharpart(line, start + (neigh_type == 'right' and 1 or 0), neigh_type == 'whole' and 2 or 1)
end

H.neigh_match = function(pattern) return H.get_neigh('whole'):find(pattern or '') ~= nil end

H.get_open_char = function(x) return vim.fn.strcharpart(x, 0, 1) end
H.get_close_char = function(x) return vim.fn.strcharpart(x, 1, 1) end

H.get_arrow_key = function(key)
  return vim.fn.mode() == 'i' and (key == 'right' and H.keys.right_undo or H.keys.left_undo)
    or (key == 'right' and H.keys.right or H.keys.left)
end

H.map = function(mode, lhs, rhs, opts)
  if lhs == '' then return end
  opts = vim.tbl_deep_extend('force', { silent = true }, opts or {})
  vim.keymap.set(mode, lhs, rhs, opts)
end

H.with_temp_option = function(name, value)
  -- Cache option only once to not override it later with temporary set value
  -- Like in case of `nvim_feedkeys('(\r(\r')`
  if H.options_cache[name] == nil then H.options_cache[name] = vim.o[name] end
  vim.o[name] = value
  H.restore_option_later(name)
end

H.restore_option_later = vim.schedule_wrap(function(name)
  if H.options_cache[name] == nil then return end
  vim.o[name] = H.options_cache[name]
  H.options_cache[name] = nil
end)

return MiniPairs
