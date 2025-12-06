--- *mini.cmdline* Command line tweaks
---
--- MIT License Copyright (c) 2025 Evgeni Chasnovski

--- Features:
---
--- - Autocomplete with customizable delay. Enhances |cmdline-completion| and
---   manual |'wildchar'| pressing experience.
---   Requires Neovim>=0.11, though Neovim>=0.12 is recommended.
---
--- - Autocorrect words as-you-type. Only words that must come from a fixed set of
---   candidates (like commands and options) are autocorrected by default.
---
--- - Autopeek command range as-you-type. Shows a floating window with range lines
---   along with customizable context lines.
---
--- What it doesn't do:
---
--- - Customization of command line UI. Use |vim._extui| (on Neovim>=0.12).
---
--- - Customization of autocompletion candidates. They are computed
---   via |cmdline-completion|.
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.cmdline').setup({})` (replace `{}`
--- with your `config` table). It will create global Lua table `MiniCmdline` which
--- you can use for scripting or manually (with `:lua MiniCmdline.*`).
---
--- See |MiniCmdline.config| for `config` structure and default values.
---
--- You can override runtime config settings locally to buffer inside
--- `vim.b.minicmdline_config` which should have same structure as
--- `MiniCmdline.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- # Suggested option values ~
---
--- Some options are set automatically (if not set before |MiniCmdline.setup()|):
--- - |'wildmode'| is set to "noselect,full" for less intrusive autocompletion.
---   Requires Neovim>=0.11 and enabled `config.autocomplete`.
--- - |'wildoptions'| is set to "pum,fuzzy" to enable fuzzy matching.
---
--- # Comparisons ~
---
--- - [folke/noice.nvim](https://github.com/folke/noice.nvim):
---     - Mostly focuses on visual aspects of the Command line.
---       This modules is aimed to improve its workflow without changing UI.
---
--- - [nacro90/numb.nvim](https://github.com/nacro90/numb.nvim):
---     - Designed to preview only a single line range defined by numbers.
---       This module handles any form of |:range| and |:range-offset| for both
---       one and two line ranges.
---     - Shows target line directly in the normal window.
---       This module uses a dedicated floating window.
---
--- - Built-in |cmdline-autocompletion| (on Neovim>=0.12):
---     - This module on Neovim>=0.12 uses that as its base for autocompletion.
---       Ont top of that it also provides customizable delay and predicate.
---
--- - Built-in |vim._extui| (on Neovim>=0.12):
---     - Mostly focuses on visual aspects of the Command line.
---       This modules is aimed to improve its workflow without changing UI.
---
--- # Highlight groups ~
---
--- - `MiniCmdlinePeekBorder` - border of autopeek window.
--- - `MiniCmdlinePeekLineNr` - line numbers in autopeek window.
--- - `MiniCmdlinePeekNormal` - basic foreground/background of autopeek window.
--- - `MiniCmdlinePeekSep` - statuscolumn separator in autopeek window.
--- - `MiniCmdlinePeekSign` - signs in autopeek window.
--- - `MiniCmdlinePeekTitle` - title of autopeek window.
---
--- # Disabling ~
---
--- To disable acting in mappings, set `vim.g.minicmdline_disable` (globally) or
--- `vim.b.minicmdline_disable` (for a buffer) to `true`. Considering high number
--- of different scenarios and customization intentions, writing exact rules
--- for disabling module's functionality is left to user.
--- See |mini.nvim-disabling-recipes| for common recipes.
---@tag MiniCmdline

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local

-- Module definition ==========================================================
local MiniCmdline = {}
local H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniCmdline.config|.
---
---@usage >lua
---   require('mini.cmdline').setup() -- use default config
---   -- OR
---   require('mini.cmdline').setup({}) -- replace {} with your config table
--- <
MiniCmdline.setup = function(config)
  -- Export module
  _G.MiniCmdline = MiniCmdline

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
---@text # General ~
---
--- - Each feature is configured via separate table.
--- - Use `enable = false` to disable a feature.
---
---# Autocomplete ~
---
--- `config.autocomplete` is used to configure autocompletion: automatic show
--- of |'wildmenu'|.
---
--- `autocomplete.delay` defines a (debounce style) delay after which |'wildchar'|
--- is triggered to show wildmenu.
--- Default: 0. Note: Neovim>=0.12 is recommended for positive values if you
--- want to reduce flicker (thanks to |wildtrigger()|).
---
--- `autocomplete.predicate` defines a condition of whether to trigger completion
--- at the current command line state. Takes a table with input data and should
--- return `true` to show completion and `false` otherwise. Will be called before
--- the possible delay at current command line state.
--- Default: |MiniCmdline.default_autocomplete_predicate()|.
---
--- Input data fields:
--- - <line> `(string)` - current command line text. See |getcmdline()|.
--- - <pos> `(number)` - current command line column. See |getcmdpos()|.
--- - <line_prev> `(string)` - command line text before the latest change.
--- - <pos_prev> `(number)` - command line column before the latest cursor move.
---
--- Example of blocking completion based on completion type (as some may be slow): >lua
---
---   local block_compltype = { shellcmd = true }
---   require('mini.cmdline').setup({
---     autocomplete = {
---       predicate = function()
---         return not block_compltype[vim.fn.getcmdcompltype()]
---       end,
---     },
---   })
--- <
--- Similar approach can be used to enable completion only for normal Ex commands.
--- Use `return vim.fn.getcmdtype() == ':'` as a predicate output.
---
---# Autocorrect ~
---
--- `config.autocorrect` is used to configure autocorrection: automatic adjustment
--- of bad words as you type them. This works only when appending text at the end
--- of the command line. Editing already typed words does not trigger autocorrect
--- (allows correcting the autocorrection).
---
--- When to autocorrect is computed automatically based on |getcmdcomplpat()| after
--- every key press: if it doesn't add the character to completion pattern, then
--- the pattern before the key press is attempted to be corrected.
--- There is also an autocorrection attempt for the last word just before
--- executing the command.
---
--- Notes:
--- - This is intended mostly for fixing typos and not as a shortcut for fuzzy
---   matching. Performing the latter automatically is too intrusive. Explicitly
---   use fuzzy completion for that (set up by default).
---
--- - Default autocorrection is done only for words that must come from a fixed
---   set of candidates (like commands and options) by choosing the one with
---   the lowest string distance.
---   See |MiniCmdline.default_autocorrect_func()| for details.
---
--- - If current command expects only a single argument (like |:colorscheme|), then
---   autocorrection will happen only just before executing the command.
---
--- `autocorrect.func` is a function that can be used to customize autocorrection.
--- Takes a table with input data and should return a string with the correct word
--- or `nil` for no autocorrection. Default: |MiniCmdline.default_autocorrect_func()|.
---
--- Input data fields:
--- - <word> `(string)` - word to be autocorrected. Never empty string.
--- - <type> `(string)` - word type. Output of |getcmdcompltype()|.
---
---# Autopeek ~
---
--- `config.autopeek` is used to configure automatic peeking: show command's target
--- range in a floating window. The window will appear above command line and show
--- current buffer with the focus on left and right (if present and differs from
--- left) range lines.
---
--- `autopeek.n_context` defines how many lines to show above and below the target.
--- The range itself is visualized by default with the statuscolumn signs.
--- Default: 1.
---
--- `autopeek.window` defines behavior of a peek window.
--- `autopeek.window.config` is a table defining floating window characteristics
--- or a callable returning such table.
--- It should have the same structure as in |nvim_open_win()|.
---
--- `autopeek.window.statuscolumn` is a special function that can be used to
--- customize |'statuscolumn'| value for the peek window. Takes a table with input
--- data and should return a string to display for line |v:lnum|.
--- Default: |MiniCmdline.default_autopeek_statuscolumn()|.
--- Input data fields:
--- - <left> `(number)` - left range edge. Not necessarily smallest.
--- - <right> `(number)` - right range edge. Same as `left` for a single line range.
---
--- Example of showing `<` and `>` signs on range lines: >lua
---
---   function(data)
---     local n, l, r = vim.v.lnum, data.left, data.right
---     local s = n == l and (n == r and '* ' or '< ') or n == r and '> ' or ''
---     -- Needs explicit highlighting via `:h 'statusline'` syntax
---     return '%#MiniCmdlinePeekSign#' .. s
---   end
--- <
--- Notes:
--- - Peek window directly shows current buffer, which means that all its
---   extmarks, virtual text, virtual lines, etc. are also shown.
--- - Non-zero context might work unreliably if there are virtual lines.
--- - Peeking intentionally hides Visual selection if Command-line mode is entered
---   directly from it. Peeking `'<,'>` range already visualizes the selection.
---   To disable autopeek for this case, add the following code BEFORE
---   executing `require('mini.cmdline').setup()`: >lua
---
---     local disable = vim.schedule_wrap(function()
---       local is_from_visual = vim.startswith(vim.fn.getcmdline(), "'<,'>")
---       MiniCmdline.config.autopeek.enable = not is_from_visual
---     end)
---     local reenable = function() MiniCmdline.config.autopeek.enable = true end
---
---     vim.api.nvim_create_autocmd('CmdlineEnter', { callback = disable })
---     vim.api.nvim_create_autocmd('CmdlineLeave', { callback = reenable })
--- <
MiniCmdline.config = {
  -- Autocompletion: show `:h 'wildmenu'` as you type
  autocomplete = {
    enable = true,

    -- Delay (in ms) after which to trigger completion
    -- Neovim>=0.12 is recommended for positive values
    delay = 0,

    -- Custom rule of when to trigger completion
    predicate = nil,

    -- Whether to map arrow keys for more consistent wildmenu behavior
    map_arrows = true,
  },

  -- Autocorrection: adjust non-existing words (commands, options, etc.)
  autocorrect = {
    enable = true,

    -- Custom autocorrection rule
    func = nil,
  },

  -- Autopeek: show command's target range in a floating window
  autopeek = {
    enable = true,

    -- Number of lines to show above and below range lines
    n_context = 1,

    -- Window options
    window = {
      -- Floating window config
      config = {},

      -- Function to render statuscolumn
      statuscolumn = nil,
    },
  },
}
--minidoc_afterlines_end

--- Default autocompletion predicate
---
---@param data table Input autocompletion data. As described in |MiniCmdline.config|.
---@param opts table|nil Options. Reserved for future use.
---
---@return boolean If command line does not (yet) contain a letter - `false`,
---   otherwise - `true`. This makes autopeek easier to use for a numerical range.
MiniCmdline.default_autocomplete_predicate = function(data, opts) return data.line:find('%a') ~= nil end

--- Default autocorrection function
---
--- - Return input word if `opts.strict_type=true` and input `type` is not proper.
--- - Get candidates via `opts.get_candidates()`.
---   Default: mostly via |getcompletion()| with empty pattern and input `type`.
---   Exceptions are `help` and `option` types: both list all available candidates
---   in their own ways.
--- - Choose the candidate with the lowest Damerau–Levenshtein distance
---   (smallest number of deletion/insertion/substitution/transposition needed
---   to transform one word into another; slightly prefers transposition).
---   Notes:
---     - Type `'command'` also chooses from all valid candidate abbreviations.
---     - Comparison is done both respecting and ignoring case.
---
---@param data table Input autocorrection data. As described in |MiniCmdline.config|.
---@param opts table|nil Options. Possible fields:
---   - <strict_type> `(boolean)` - whether to restrict output only for types which
---     must have words from a fixed set of candidates (like command or option
---     names). Note: does not include `help` type since |:help| already has
---     "sophisticated algorithm" to handle typos. Default: `true`.
---   - <get_candidates> `(function)` - source of candidates. Will be called
---     with `data` as argument and should return array of string candidates to
---     choose from.
---     Default: for most types -  |getcompletion()| with empty pattern and
---     input `type`; for `help` and `option` type - all available help tags and
---     option names (long and short) respectively.
---
---@return string Autocorrected word.
MiniCmdline.default_autocorrect_func = function(data, opts)
  H.check_type('data', data, 'table')
  H.check_type('data.word', data.word, 'string')
  H.check_type('data.type', data.type, 'string')

  opts = opts or {}
  local strict_type = opts.strict_type == nil or opts.strict_type
  if strict_type and not H.autocorrect_strict_types[data.type] then return data.word end

  -- Get all valid words
  local all = vim.is_callable(opts.get_candidates) and opts.get_candidates(data) or H.get_autocorrect_candidates(data)
  if vim.tbl_contains(all, data.word) or data.word == '' then return data.word end

  -- Make results stable in case several candidates have the same distance
  table.sort(all)

  -- Handle commands separately: need dedicated abbreviation length
  -- computation and to allow `!`
  if data.type == 'command' then return H.get_nearest_command(data.word, all) end

  -- Fall back to computing nearest string without allowing abbreviations
  local abbr_lens = vim.tbl_map(string.len, all)
  return H.get_nearest_abbr(data.word, all, abbr_lens)
end

--- Default autopeek statuscolumn
---
--- - Show signs next to lines depending on their relation to peeked range.
---   Highlighted with `MiniCmdlinePeekSign` group.
--- - Show line numbers for left and right parts of the range.
---   Highlighted with `MiniCmdlinePeekLineNr` group.
--- - Separate statuscolumn and buffer text with dedicated separator character.
---   Highlighted with `MiniCmdlinePeekSep` group.
---
--- Notes:
--- - Intended to only be used as a part of |'statuscolumn'| function, as it
---   uses |v:lnum| and |v:virtnum| to compute the output.
---
--- Example of adjusting a `mid` sign: >lua
---
---   local peek_stc_opts = { signs = { mid = '+' } }
---   local peek_stc = function(data)
---     return MiniCmdline.default_autopeek_statuscolumn(data, peek_stc_opts)
---   end
---   require('mini.cmdline').setup({
---     autopeek = { window = { statuscolumn = peek_stc } },
---   })
--- <
---@param data table Input peek data. As described in |MiniCmdline.config|.
---@param opts table|nil Options. Possible fields:
---   - <signs> `(table)` - signs to show. Possible fields:
---       - <same> `(string)` - on range if `left=right`. Default: `'🭬'`.
---       - <left> `(string)`  - on `left` line.  Default: `'┌'`.
---       - <mid> `(string)`   - inside range.  Default: `'┊'`.
---       - <right> `(string)` - on `right` line. Default: `'└'`.
---       - <out> `(string)` - outside of range. Default: `''` (no sign).
---       - <virt> `(string)` - virtual line. Default: `'•'`.
---       - <wrap> `(string)` - wrapped line. Default: `'↳'`.
---   - <sep> `(string)` - string to put at the end to separate statuscolumn and
---     buffer text. Default: `'│'`
---
---   Note: Any sign and separator should have every `%` escaped as `%%` (due to its
---   special meaning in |'statuscolumn'|).
MiniCmdline.default_autopeek_statuscolumn = function(data, opts)
  opts = opts or {}
  local signs = opts.signs or {}
  local sep_format = opts.sep == nil and '│' or opts.sep:gsub('%%', '%%%%')

  if vim.v.virtnum ~= 0 then
    local sign = (vim.v.virtnum < 0 and (signs.virt or '•') or (signs.wrap or '↳'))
    -- Format as `sign %= sep-hl sep`
    return sign .. '%=%#MiniCmdlinePeekSep#' .. sep_format:gsub('%%%%', '%%')
  end

  local n, l, r = vim.v.lnum, data.left, data.right
  -- Format as `sign-hl sign linenr-hl %= linenr sep-hl sep`
  local fmt = '%%#MiniCmdlinePeekSign#%s%%#MiniCmdlinePeekLineNr#%%=%s%%#MiniCmdlinePeekSep#' .. sep_format
  if n == l and n == r then return string.format(fmt, signs.same or '🭬', n) end
  if n == l then return string.format(fmt, signs.left or '┌', n) end
  if n == r then return string.format(fmt, signs.right or '└', n) end
  if (l < n and n < r) or (r < n and n < l) then return string.format(fmt, signs.mid or '┊', '') end
  return string.format(fmt, signs.out or '', '')
end

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniCmdline.config)

-- Timers
H.timers = {
  autocomplete = vim.loop.new_timer(),
}

-- Autocomplete requires `noselect` flag of 'wildmode'. Present in Neovim>=0.11
H.can_autocomplete = vim.fn.has('nvim-0.11') == 1

-- Autocorrect types for which words *must* be from some fixed set
-- Basically a subset of `:h :command-complete` which might lead to an error if
-- word is not from a fixed set. Can be adjusted for more nuances.
-- Reasons for not including a type:
-- - The main reason is because type's usage can be done in context when
--   creating a new object. Like `:edit new-file` for `file` type.
-- - No `help` because there already is an autocorrection with a "sophisticated
--   algorithm to decide which match is better than another one".
--stylua: ignore
H.autocorrect_strict_types = {
  arglist       = true, -- file names in argument list
  -- augroup       = true, -- autocmd groups
  -- breakpoint    = true, -- |:breakadd| suboptions
  buffer        = true, -- buffer names
  color         = true, -- color schemes
  command       = true, -- Ex command (and arguments)
  compiler      = true, -- compilers
  diff_buffer   = true, -- diff buffer names
  -- dir           = true, -- directory names
  -- dir_in_path   = true, -- directory names in |'cdpath'|
  -- environment   = true, -- environment variable names
  event         = true, -- autocommand events
  -- expression    = true, -- Vim expression
  -- file          = true, -- file and directory names
  -- file_in_path  = true, -- file and directory names in |'path'|
  filetype      = true, -- filetype names |'filetype'|
  -- ['function']  = true, -- function name
  -- help          = true, -- help subjects
  -- highlight     = true, -- highlight groups
  history       = true, -- |:history| suboptions
  keymap        = true, -- keyboard mappings
  locale        = true, -- locale names (as output of locale -a)
  -- lua           = true, -- Lua expression |:lua|
  mapclear      = true, -- buffer argument
  -- mapping       = true, -- mapping name
  -- menu          = true, -- menus
  messages      = true, -- |:messages| suboptions
  option        = true, -- options
  packadd       = true, -- optional package |pack-add| names
  -- runtime       = true, -- file and directory names in |'runtimepath'|
  -- scriptnames   = true, -- sourced script names
  -- shellcmd      = true, -- Shell command
  -- shellcmdline  = true, -- First is a shell command and subsequent ones are filenames
  sign          = true, -- |:sign| suboptions
  syntax        = true, -- syntax file names |'syntax'|
  syntime       = true, -- |:syntime| suboptions
  -- tag           = true, -- tags
  -- tag_listfiles = true, -- tags, file names are shown when CTRL-D is hit
  -- user          = true, -- user names
  -- var           = true, -- user variables
}

-- Various cache to use during command line edit
H.cache = {}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  H.check_type('autocomplete', config.autocomplete, 'table')
  H.check_type('autocomplete.enable', config.autocomplete.enable, 'boolean')
  H.check_type('autocomplete.delay', config.autocomplete.delay, 'number')
  H.check_type('autocomplete.predicate', config.autocomplete.predicate, 'function', true)
  H.check_type('autocomplete.map_arrows', config.autocomplete.map_arrows, 'boolean')

  H.check_type('autocorrect', config.autocorrect, 'table')
  H.check_type('autocorrect.enable', config.autocorrect.enable, 'boolean')
  H.check_type('autocorrect.func', config.autocorrect.func, 'function', true)

  H.check_type('autopeek', config.autopeek, 'table')
  H.check_type('autopeek.enable', config.autopeek.enable, 'boolean')
  H.check_type('autopeek.n_context', config.autopeek.n_context, 'number')
  H.check_type('autopeek.window', config.autopeek.window, 'table')
  local autopeek_win_config = config.autopeek.window.config
  if not (type(autopeek_win_config) == 'table' or vim.is_callable(autopeek_win_config)) then
    H.error('`autopeek.window.config` should be table or callable, not ' .. type(autopeek_win_config))
  end
  H.check_type('autopeek.window.statuscolumn', config.autopeek.window.statuscolumn, 'callable', true)

  return config
end

H.apply_config = function(config)
  MiniCmdline.config = config

  -- Try setting suggested option values
  -- NOTE: This makes it more like 'mini.completion' (with 'noselect')
  local was_set = vim.api.nvim_get_option_info2('wildmode', { scope = 'global' }).was_set
  if not was_set and config.autocomplete.enable and H.can_autocomplete then vim.o.wildmode = 'noselect,full' end

  was_set = vim.api.nvim_get_option_info2('wildoptions', { scope = 'global' }).was_set
  if not was_set then vim.o.wildoptions = 'pum,fuzzy' end

  -- Set useful mappings
  if config.autocomplete.map_arrows then
    local map_arrow = function(dir, wildmenu_prefix, desc)
      local rhs = function() return (vim.fn.wildmenumode() == 1 and wildmenu_prefix or '') .. dir end
      vim.keymap.set('c', dir, rhs, { expr = true, desc = desc })
    end
    map_arrow('<Left>', '<Space><BS>', 'Move cursor left')
    map_arrow('<Right>', '<Space><BS>', 'Move cursor right')
    -- NOTE: All tests seem to pass without these mappings. But it is mentioned
    -- in `:h cmdline-autocompletion`, so probably worth adding
    map_arrow('<Up>', '<C-e>', 'Go to earlier history')
    map_arrow('<Down>', '<C-e>', 'Go to newer history')
  end
end

H.create_autocommands = function()
  local gr = vim.api.nvim_create_augroup('MiniCmdline', {})

  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = gr, pattern = pattern, callback = callback, desc = desc })
  end

  -- Act on command line events. Notes:
  -- - Schedule for 'CmdlineEnter' to not act on mappings like `:...`
  --   (like `:<C-u>...` popular for Visual mode).
  -- - Schedule for 'CmdlineChanged' to work around autcompletion issues with
  --   mocking wildchar.
  -- - Do not schedule 'CmdlineLeave' to be able to set command text before
  --   executing it.
  au('CmdlineEnter', '*', vim.schedule_wrap(H.on_cmdline_enter), 'Act on command line enter')
  au('CmdlineChanged', '*', vim.schedule_wrap(H.on_cmdline_changed), 'Act on command line change')
  au('CmdlineLeave', '*', H.on_cmdline_leave, 'Act on command line leave')

  au('VimResized', '*', function() H.autopeek(true) end, 'Adjust peek window')
  au('CmdwinEnter', '*', function() H.peek_hide() end, 'Hide peek window')

  au('ColorScheme', '*', H.create_default_hl, 'Ensure colors')
end

H.create_default_hl = function()
  local hi = function(name, opts)
    opts.default = true
    vim.api.nvim_set_hl(0, name, opts)
  end

  hi('MiniCmdlinePeekBorder', { link = 'FloatBorder' })
  hi('MiniCmdlinePeekLineNr', { link = 'DiagnosticSignWarn' })
  hi('MiniCmdlinePeekNormal', { link = 'NormalFloat' })
  hi('MiniCmdlinePeekSep', { link = 'SignColumn' })
  hi('MiniCmdlinePeekSign', { link = 'DiagnosticSignHint' })
  hi('MiniCmdlinePeekTitle', { link = 'FloatTitle' })
end

H.is_disabled = function() return vim.g.minicmdline_disable == true or vim.b.minicmdline_disable == true end

H.get_config = function() return vim.tbl_deep_extend('force', MiniCmdline.config, vim.b.minicmdline_config or {}) end

-- Autocommands ---------------------------------------------------------------
H.on_cmdline_enter = function()
  -- Check for Command-line mode to not act on `:...` mappings
  if H.is_disabled() or vim.fn.mode() ~= 'c' then return end

  -- Act only on "not nested" command line (for simplicity). It can nest after
  -- `c_CTRL-R_=`, since there are CmdlineEnter-CmdlineChanged-CmdlineLeave for
  -- it without explicit leave-enter for the initial normal Ex command mode.
  -- There doesn't seem to be a way to have `n_nested > 1`, but use counter of
  -- nested levels instead of a boolean `is_nested` just in case.
  if H.cache.state ~= nil then
    H.cache.n_nested = (H.cache.n_nested or 0) + 1
    return
  end

  H.cache = {
    buf_id = vim.api.nvim_get_current_buf(),
    cmd_type = vim.fn.getcmdtype(),
    config = H.get_config(),
    peek = {},
    state = H.get_cmd_state(),
    state_prev = H.get_cmd_state(true),
  }
  H.cache.autocomplete_predicate = H.cache.config.autocomplete.predicate or MiniCmdline.default_autocomplete_predicate
  H.cache.buf_is_cmdwin = vim.fn.getbufinfo(H.cache.buf_id)[1].command == 1

  MiniCmdline._peek_statuscolumn = H.make_peek_statuscolumn()
  if H.cache.config.autopeek.enable then H.autopeek() end
end

H.on_cmdline_changed = function()
  if H.cache.state == nil or H.cache.n_nested ~= nil then return end

  -- Act only on actual line change
  local state = H.get_cmd_state()
  if state.line == H.cache.state.line then return end

  -- Update state accounting for some edge cases
  if H.cache.state_prev.compltype == 'option' then H.adjust_option_cmd_state(state) end
  H.cache.state_prev, H.cache.state = H.cache.state, state

  local config = H.cache.config
  if config.autocomplete.enable and H.can_autocomplete then H.autocomplete() end
  if config.autocorrect.enable then H.autocorrect(false) end
  if config.autopeek.enable then H.autopeek() end
end

H.on_cmdline_leave = function()
  if H.cache.state == nil then return end
  if H.cache.n_nested ~= nil then
    H.cache.n_nested = H.cache.n_nested > 1 and (H.cache.n_nested - 1) or nil
    return
  end

  if H.cache.config.autocorrect.enable and not vim.v.event.abort then H.autocorrect(true) end
  H.peek_hide()
  H.cache = {}
  MiniCmdline._peek_statuscolumn = nil
end

H.get_cmd_state = function(is_init)
  local compltype = vim.fn.getcmdcompltype()
  if is_init then return { complpat = '', compltype = compltype, line = '', pos = 1, cmd = {} } end
  return { complpat = H.getcmdcomplpat(), compltype = compltype, line = vim.fn.getcmdline(), pos = vim.fn.getcmdpos() }
end

H.adjust_option_cmd_state = function(state)
  -- Cases like `set nowrap invmagic` are completed specially. After `no`/`inv`
  -- there is a specialized completion only for boolean options. In practice it
  -- results into `compltype=''` and `complpat=<text after no/inv>`.
  -- This interferes with how autocorrection is detected, as it relies on whole
  -- `nowrap` / `invmagic` to be a single complpat *with compltype=option*.
  --
  -- The solution is to detect cases "it was compltype=option but now it isn't"
  -- and try to expand complpat to match the whole word on cursor's left.
  if state.compltype == 'option' then return end
  state.complpat = state.line:sub(1, state.pos - 1):match(' (%w+)$') or ''
  state.compltype = state.complpat ~= nil and 'option' or state.compltype
end

-- Autocomplete ---------------------------------------------------------------
H.autocomplete = function()
  H.timers.autocomplete:stop()

  -- Do not complete if predicate says so
  local state, state_prev = H.cache.state, H.cache.state_prev
  local data = { line = state.line, pos = state.pos, line_prev = state_prev.line, pos_prev = state_prev.pos }
  if not H.cache.autocomplete_predicate(data) then return H.hide_wild() end

  -- Do nothing in some problematic cases (when wildmenu does not work)
  -- TODO: Remove after compatibility with Neovim=0.11 is dropped
  if H.block_autocomplete() then return end

  local delay = H.cache.config.autocomplete.delay
  if delay == 0 then return H.trigger_complete() end
  H.timers.autocomplete:start(delay, 0, H.trigger_complete_scheduled)
end

H.block_autocomplete = function() return false end
if vim.fn.has('nvim-0.12') == 0 then
  H.block_autocomplete = function()
    -- Block for non-interactive command type
    if H.cache.cmd_type ~= ':' then return true end

    -- Block for cases when there is no completion candidates. This affects
    -- performance (completion candidates are computed twice), but it is
    -- the most robust way of dealing with problematic situations:
    -- - Some commands don't have completion defined: `:s`, `:g`, etc.
    -- - Some cases result in verbatim `^I` inserted. Like after bang (`:q!`).
    --
    -- The `vim.fn.getcmdcompltype() == ''` condition is too wide as it denies
    -- legitimate cases of when there are available completion candidates.
    -- Like in user commands created with `vim.api.nvim_create_user_command()`.
    local line_before_pos = H.cache.state.line:sub(1, H.cache.state.pos - 1)
    -- `getcompletion` may result in error, like after `:ltag `
    local ok, candidates = pcall(vim.fn.getcompletion, line_before_pos, 'cmdline')
    return not (ok and #candidates > 0)
  end
end

H.trigger_complete = function()
  if vim.fn.mode() ~= 'c' then return end
  H.trigger_wild()
end

H.trigger_complete_scheduled = vim.schedule_wrap(H.trigger_complete)

H.trigger_wild = function() vim.fn.wildtrigger() end
if vim.fn.has('nvim-0.12') == 0 then
  H.trigger_wild = function()
    -- Not triggerring when wildmenu is shown helps avoiding trigger after
    -- manually pressing wildchar (as text is also changes).
    if vim.fn.wildmenumode() == 1 then return end
    -- Type `<C-z>` which is "Trigger 'wildmode', but always available."
    vim.api.nvim_feedkeys('\26', 'nt', false)
  end
end

H.hide_wild = function()
  -- Ensure that there is no outdated pmenu after `wildtrigger()`
  vim.cmd('redraw')

  -- This works, but it triggers wildmenu, which is not usable when the point
  -- is to hide pmenu if `autocomplete.predicate()` returned `false` ()
  -- local keys = (vim.fn.wildmenumode() == 0 and '\26' or '') .. '\5'
  -- vim.api.nvim_feedkeys(keys, 'nt', false)
end
if vim.fn.has('nvim-0.12') == 0 then H.hide_wild = function() end end

-- Autocorrect ----------------------------------------------------------------
H.autocorrect = function(is_final)
  -- Act only for normal Ex commands after a word is just finished typing
  if not (H.cache.cmd_type == ':' and H.cache.state.line:find('%S') ~= nil) then return end

  local state, state_prev = H.cache.state, H.cache.state_prev
  local line, line_prev = state.line, state_prev.line
  local pos, pos_prev = state.pos, state_prev.pos

  -- Act only when text is appended. It makes it natural to tweak autocorrected
  -- text by going back and editing it. This is also easier to implement.
  local is_at_end, was_at_end = (pos - 1) == line:len(), (pos_prev - 1) == line_prev:len()
  local is_text_append = vim.startswith(line, line_prev) and is_at_end and was_at_end
  local is_word_finished = not vim.startswith(state.complpat, state_prev.complpat)

  if not (is_text_append and (is_word_finished or is_final)) then return end

  -- Compute autocorrection
  local state_to_use = is_final and state or state_prev
  local word = state_to_use.complpat
  if word == '' then return end

  local func = H.cache.config.autocorrect.func or MiniCmdline.default_autocorrect_func
  local new_word = func({ word = word, type = state_to_use.compltype }) or word

  if word == new_word then return end
  if type(new_word) ~= 'string' then return H.notify('Can not autocorrect for ' .. vim.inspect(word), 'WARN') end

  -- Set corrected word
  local init_pos = state_to_use.pos
  local new_line = line:sub(1, init_pos - word:len() - 1) .. new_word .. line:sub(init_pos)
  -- - Use `noautocmd` to not conflict with `autocomplete` on `CmdlineChanged`
  local cmd = string.format('call setcmdline(%s, %s)', vim.inspect(new_line), new_line:len() + 1)
  vim.cmd('noautocmd ' .. cmd)
end

H.get_autocorrect_candidates = function(data)
  if data.type == 'help' then
    local help_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[help_buf].buftype = 'help'
    -- - NOTE: no dedicated buffer name because it is immediately wiped out
    local tags = vim.api.nvim_buf_call(help_buf, function() return vim.fn.taglist('.*') end)
    vim.api.nvim_buf_delete(help_buf, { force = true })
    return vim.tbl_map(function(x) return x.name end, tags)
  end

  if data.type == 'option' then
    local all = {}
    for name, info in pairs(vim.api.nvim_get_all_options_info()) do
      table.insert(all, name)

      local is_bool = info.type == 'boolean'
      table.insert(all, is_bool and ('no' .. name) or nil)
      table.insert(all, is_bool and ('inv' .. name) or nil)

      local has_shortname = info.shortname ~= ''
      table.insert(all, has_shortname and info.shortname or nil)
      table.insert(all, (has_shortname and is_bool) and ('no' .. info.shortname) or nil)
      table.insert(all, (has_shortname and is_bool) and ('inv' .. info.shortname) or nil)
    end
    return all
  end

  local ok, all = pcall(vim.fn.getcompletion, '', data.type)
  return ok and all or { data.word }
end

H.get_nearest_command = function(ref, all)
  -- Do not alter `:=` command, as it is a special Lua shorthand command
  if ref:sub(1, 1) == '=' then return ref end

  -- Allow trailing special punctuation (specific to commands)
  local word, suffix = ref:match('^(.+)([!|]?)$')

  -- Account for the fact that commands can be abbreviated (`:h |20.2|`):
  local cmd_abbr_lens, usr_cmds, usr_max_len = {}, {}, 0
  for _, cmd in ipairs(all) do
    -- User command abbreviation needs to uniquely identify command name
    if cmd:find('^[A-Z]') ~= nil then
      usr_cmds[cmd] = true
      usr_max_len = math.max(usr_max_len, cmd:len())
    else
      -- ANY abbreviation of ANY built-in command is a valid command (may be
      -- different; `wincmd`->`w`==`write`). Its an internal optimization.
      -- EXCEPT: `:def` abbreviation of `:defer` is not allowed.
      cmd_abbr_lens[cmd] = cmd == 'defer' and 4 or 1
    end
  end

  -- Slice user commands with increasing abbreviation length to find which
  -- ones can be uniquely identified by it
  for cur_abbr_len = 1, usr_max_len do
    local cur_abbrs = {}
    for cmd, _ in pairs(usr_cmds) do
      local abbr = cmd:sub(1, cur_abbr_len)
      cur_abbrs[abbr] = cur_abbrs[abbr] or {}
      table.insert(cur_abbrs[abbr], cmd)
    end

    for _, cmd_arr in pairs(cur_abbrs) do
      if #cmd_arr == 1 then
        local cmd = cmd_arr[1]
        cmd_abbr_lens[cmd] = math.min(cur_abbr_len, cmd:len())
        usr_cmds[cmd] = nil
      end
    end
  end

  local abbr_lens = vim.tbl_map(function(x) return cmd_abbr_lens[x] end, all)
  return H.get_nearest_abbr(word, all, abbr_lens) .. suffix
end

H.get_nearest_abbr = function(word, candidates, abbr_lens)
  local tolower = vim.fn.tolower
  local word_split = vim.split(word, '')
  local word_split_l = vim.split(tolower(word), '')

  -- Prefer closest string respecting case first, then try ignorecase
  local res, res_dist = nil, math.huge
  for i, cand in ipairs(candidates) do
    local min_abbr_len = abbr_lens[i]
    local d, abbr_len = H.string_abbr_dist(word_split, vim.split(cand, ''), min_abbr_len)
    if d < res_dist then
      res, res_dist = cand:sub(1, abbr_len), d
    end
  end
  for i, cand in ipairs(candidates) do
    local min_abbr_len = abbr_lens[i]
    local cand_word_l = tolower(cand)
    local d_l, abbr_len_l = H.string_abbr_dist(word_split_l, vim.split(cand_word_l, ''), min_abbr_len)
    if d_l < res_dist then
      res, res_dist = cand:sub(1, abbr_len_l), d_l
    end
  end

  return res
end

H.string_abbr_dist = function(ref, cand, min_abbr_len)
  -- Source: https://en.wikipedia.org/wiki/Damerau-Levenshtein_distance
  -- d[i][j] - distance between `ref[1:i]` and `cand[1:j]` abbreviations
  local d = {}
  for i = 0, #ref do
    d[i] = { [0] = i }
  end
  for j = 0, #cand do
    d[0][j] = j
  end
  for i = 1, #ref do
    for j = 1, #cand do
      local cost = ref[i] == cand[j] and 0 or 1
      -- Account for deletion, insertion, substitution
      d[i][j] = math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
      -- Account for transposition. Slightly favor them over others, as it is
      -- a common source for autocorrection
      if i > 1 and j > 1 and ref[i] == cand[j - 1] and ref[i - 1] == cand[j] then
        d[i][j] = math.min(d[i][j], d[i - 2][j - 2] + 0.99 * cost)
      end
    end
  end

  -- Find the candidate abbreviation with the smallest distance
  local abbr_d = d[#ref]
  local dist, abbr_len = math.huge, nil
  for j = min_abbr_len, #cand do
    if abbr_d[j] < dist then
      dist, abbr_len = abbr_d[j], j
    end
  end

  return dist, abbr_len
end

-- Autopeek -------------------------------------------------------------------
H.autopeek = function(force)
  -- Decide if peek needs to be shown or hidden
  if not (H.cache.cmd_type == ':' and not H.cache.buf_is_cmdwin) then return end

  local line = H.cache.state.line
  if line:find('%S') == nil then H.peek_hide() end

  local range = H.parse_cmd_range(line)
  if range[1] == nil and range[2] == nil then return H.peek_hide() end

  -- NOTE: Force peek update if command line height has changed when typing
  local cmdheight = math.ceil((vim.fn.strdisplaywidth(line) + 1) / vim.o.columns)
  cmdheight = math.max(cmdheight, vim.o.cmdheight)
  force = force or cmdheight ~= H.cache.peek.cmdheight
  local cur_range = H.cache.peek.range or {}
  if not force and range[1] == cur_range[1] and range[2] == cur_range[2] then return end

  -- Normalize and show range
  local n_lines = vim.api.nvim_buf_line_count(0)
  local left = H.clamp(range[1] or range[2], 1, n_lines)
  local right = H.clamp(range[2] or range[1], 1, n_lines)
  local from = right < left and right or left
  local to = right < left and left or right

  H.cache.peek.range = range
  H.cache.peek.cmdheight = cmdheight
  H.cache.peek.statuscolumn_data = { left = left, right = right }
  H.cache.peek.win_id = H.peek_show(from, to)
end

H.peek_show = function(from, to)
  -- Compute height to show union of left and right contexts plus possible fold
  local n_context = math.max(H.cache.config.autopeek.n_context, 0)
  local n_lines = vim.api.nvim_buf_line_count(0)
  local cont_from = H.peek_new_context(from, n_context, n_lines)
  local cont_to = H.peek_new_context(to, n_context, n_lines)
  local height = H.peek_get_height(cont_from, cont_to)

  -- Ensure opened window of enough height.
  -- NOTE: This uses current buffer directly, which means that all its extmarks
  -- are shown. This is both good (for extra text highlighting) and bad
  -- (virtual lines and text) thing. Ideally, extmark "owners" should take care
  -- of where they should be shown. Usually setting something like "only show
  -- inside this particular window" makes sense. Like in 'mini.diff' and
  -- 'mini.indentscope'. This is currently not (robustly) possible. Sources:
  -- - https://github.com/neovim/neovim/issues/19654
  -- - https://github.com/neovim/neovim/pull/27361
  -- - https://github.com/neovim/neovim/pull/28432
  -- - https://github.com/neovim/neovim/pull/28728
  local config = H.peek_get_config(height)
  local win_id = H.cache.peek.win_id
  win_id = H.is_valid_win(win_id) and win_id or vim.api.nvim_open_win(0, false, config)
  vim.api.nvim_win_set_config(win_id, config)

  -- Ensure context fits the window (it may be not enough height to fit whole)
  if config.height < height then H.peek_adjust_context(cont_from, cont_to, height, config.height) end

  -- Finalize window view
  vim.api.nvim_win_call(win_id, function()
    -- Define window-local options
    vim.cmd("setlocal foldenable foldlevel=0 foldmethod=manual foldminlines=1 foldtext=''")
    vim.cmd('setlocal foldcolumn=0 nocursorline nonumber scrolloff=0 signcolumn=no nowrap')
    vim.wo.list = vim.go.list
    vim.wo.listchars = vim.go.listchars
    vim.wo.statuscolumn = '%{%v:lua.MiniCmdline._peek_statuscolumn()%}'
    vim.wo.winhighlight = 'NormalFloat:MiniCmdlinePeekNormal'
      .. ',FloatBorder:MiniCmdlinePeekBorder'
      .. ',FloatTitle:MiniCmdlinePeekTitle'

    -- Display range lines with context, fold the excess, ensure at least one
    -- range end is shown (might be not the case if there are virtual lines).
    vim.api.nvim_win_set_cursor(0, { cont_from.before, 0 })
    vim.cmd('normal! zEzt')
    vim.api.nvim_win_set_cursor(0, { cont_from.at, 0 })
    local from_after, to_before = cont_from.after, cont_to.before
    if to_before - from_after > 1 then vim.cmd(string.format('%s,%sfold', from_after + 1, to_before - 1)) end
  end)

  -- NOTE: Need explicit redraw because otherwise window is not shown
  vim.cmd('redraw')
  return win_id
end

H.peek_new_context = function(at, n_context, n_lines)
  return { before = H.clamp(at - n_context, 1, n_lines), at = at, after = H.clamp(at + n_context, 1, n_lines) }
end

H.peek_get_height = function(cont_from, cont_to)
  -- L(a or b) = L(a) + L(b) - L(a and b). Also adjust for fold.
  local n_from = cont_from.after - cont_from.before + 1
  local n_to = cont_to.after - cont_to.before + 1
  local n_both = math.max(cont_from.after - cont_to.before + 1, 0)
  local n_fold = (cont_to.before - cont_from.after > 1) and 1 or 0
  return (n_from + n_to - n_both) + n_fold
end

H.peek_get_config = function(height)
  local cmdheight = H.cache.peek.cmdheight

  local default_config = { relative = 'editor', style = 'minimal', zindex = 249 }
  default_config.anchor = 'SE'
  default_config.row = math.max(vim.o.lines - cmdheight, 1)
  default_config.col = 1
  default_config.width = vim.o.columns
  default_config.height = height

  default_config.border = (vim.fn.exists('+winborder') == 0 or vim.o.winborder == '') and 'single' or nil
  default_config.title = ' Peek '
  default_config.focusable = false

  local win_config = H.cache.config.autopeek.window.config
  if vim.is_callable(win_config) then win_config = win_config() end
  local config = vim.tbl_deep_extend('force', default_config, win_config or {})

  if type(config.title) == 'string' then config.title = H.fit_to_width(config.title, config.width) end

  -- Tweak config values to ensure they are proper, accounting for border
  local offset = config.border == 'none' and 0 or 2
  config.height = math.max(math.min(config.height, vim.o.lines - cmdheight - offset), 1)
  config.width = math.min(config.width, vim.o.columns - offset)

  return config
end

H.peek_adjust_context = function(cont_from, cont_to, height, target_height)
  local extra = height - target_height

  -- First truncate outer context (keeping top and bottom equal)
  -- NOTE: Reduce in a cycle and not via a formula since outer context can be
  -- shorter if its range line is close to file border
  while extra > 0 do
    local n_from_out, n_to_out = cont_from.at - cont_from.before, cont_to.after - cont_to.at
    if n_from_out <= 0 and n_to_out <= 0 then break end

    local is_reduce_from = n_from_out > n_to_out
    cont_from.before = cont_from.before + (is_reduce_from and 1 or 0)
    cont_to.after = cont_to.after - (is_reduce_from and 0 or 1)
    extra = extra - 1
  end
  if extra <= 0 then return end

  -- Hide excess inner context under the fold
  -- NOTE: Reduce height by 3 to make space for `from`, `to`, and fold
  local inner_context_lines = math.max(target_height - 3, 0)
  local half_height = math.floor(0.5 * inner_context_lines)
  cont_from.after = cont_from.at + half_height
  cont_to.before = cont_to.at - (inner_context_lines - half_height)
end

H.peek_hide = function()
  local info = H.cache.peek or {}
  H.win_close_safely(info.win_id)
  H.cache.peek = {}
end

H.make_peek_statuscolumn = function()
  local statuscolumn = H.cache.config.autopeek.window.statuscolumn or MiniCmdline.default_autopeek_statuscolumn
  return function() return statuscolumn(H.cache.peek.statuscolumn_data) or '' end
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.cmdline) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.notify = function(msg, level_name, silent)
  if not silent then vim.notify('(mini.cmdline) ' .. msg, vim.log.levels[level_name]) end
end

H.clamp = function(x, from, to) return math.min(math.max(x, from), to) end

H.is_valid_win = function(win_id) return type(win_id) == 'number' and vim.api.nvim_win_is_valid(win_id) end

H.win_close_safely = function(win_id)
  if H.is_valid_win(win_id) then vim.api.nvim_win_close(win_id, true) end
end

H.fit_to_width = function(text, width)
  local t_width = vim.fn.strchars(text)
  return t_width <= width and text or ('…' .. vim.fn.strcharpart(text, t_width - width + 1, width - 1))
end

H.parse_cmd_range = function(line)
  local ok, parsed = pcall(vim.api.nvim_parse_cmd, line, {})

  -- Try extra parsing to have a result for some edge cases
  -- - Line with only range
  if not ok then
    ok, parsed = pcall(vim.api.nvim_parse_cmd, line .. 'sort', {})
  end
  -- - Unfinished `/xxx` range
  if not ok and line:find('/') ~= nil then
    ok, parsed = pcall(vim.api.nvim_parse_cmd, line .. '/sort', {})
  end
  -- - Unrecognized command
  if not ok and line:find('%a') ~= nil and line:find('^%A') ~= nil then
    ok, parsed = pcall(vim.api.nvim_parse_cmd, line:match('^%A+') .. 'sort', {})
  end

  -- Treat `range` only as a "line range"
  return (ok and parsed.addr == 'line') and parsed.range or {}
end

H.getcmdcomplpat = function() return vim.fn.getcmdcomplpat() end
if vim.fn.has('nvim-0.11') == 0 then
  -- Match alphanumeric characters to cursor's left, if present
  -- This is not 100% how it works, but good enough
  H.getcmdcomplpat = function() return vim.fn.getcmdline():sub(1, vim.fn.getcmdpos() - 1):match('%w+$') or '' end
end

return MiniCmdline
