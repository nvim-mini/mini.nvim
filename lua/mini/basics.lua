--- *mini.basics* Common configuration presets
---
--- MIT License Copyright (c) 2023 Evgeni Chasnovski

--- Install, create 'init.lua', add `require('mini.basics').setup()`, and you
--- are good to go.
---
--- Features:
--- - Presets for common options. It will only change option if it wasn't
---   manually set before. See more in |MiniBasics.config.options|.
---
--- - Presets for common mappings. It will only add a mapping if it wasn't
---   manually created before. See more in |MiniBasics.config.mappings|.
---
--- - Presets for common autocommands. See more in |MiniBasics.config.autocommands|.
---
--- - Reverse compatibility is a high priority. Any decision to change already
---   present behavior will be made with great care.
---
--- Notes:
--- - Main goal of this module is to provide a relatively easier way for
---   new-ish Neovim users to have better "works out of the box" experience
---   while having documented relevant options/mappings/autocommands to study.
---   It is based partially on survey among Neovim users and partially is
---   coming from personal preferences.
---
---   However, more seasoned users almost surely will find something useful.
---
---   Still, it is recommended to read about used options/mappings/autocommands
---   and decide if they are needed. The main way to do that is by reading
---   Neovim's help pages (linked in help file) and this module's source code
---   (thoroughly documented for easier comprehension).
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.basics').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `MiniBasics`
--- which you can use for scripting or manually (with `:lua MiniBasics.*`).
---
--- See |MiniBasics.config| for available config settings.
---
--- To stop module from showing non-error feedback, set `config.silent = true`.
---
--- # Comparisons ~
---
--- - [tpope/vim-sensible](https://github.com/tpope/vim-sensible):
---     - Most of 'tpope/vim-sensible' is already incorporated as default
---       options in Neovim (see |nvim-defaults|). This module has a much
---       broader effect.
--- - [tpope/vim-unimpaired](https://github.com/tpope/vim-unimpaired):
---     - The 'tpope/vim-unimpaired' has mapping for toggling options with `yo`
---       prefix. This module implements similar functionality with `\` prefix
---       (see |MiniBasics.config.mappings|).
---@tag MiniBasics

---@diagnostic disable:undefined-field

-- To study source behind presets, search for:
-- - `-- Options ---` for `config.options`.
-- - `-- Mappings ---` for `config.mappings`.
-- - `-- Autocommands ---` for `config.autocommands`.

-- Module definition ==========================================================
local MiniBasics = {}
local H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniBasics.config|.
---
---@usage >lua
---   require('mini.basics').setup() -- use default config
---   -- OR
---   require('mini.basics').setup({}) -- replace {} with your config table
--- <
MiniBasics.setup = function(config)
  -- Export module
  _G.MiniBasics = MiniBasics

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)
end

--- Defaults ~
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text # Options ~
--- *MiniBasics.config.options*
---
--- Usage example: >lua
---
---   require('mini.basics').setup({
---     options = {
---       basic = true,
---       extra_ui = true,
---       win_borders = 'double',
---     }
---   })
--- <
--- ## options.basic ~
---
--- The `config.options.basic` sets certain options to values which are quite
--- commonly used (judging by study of available Neovim pre-configurations,
--- public dotfiles, and surveys).
--- Any option is changed only if it was not set manually beforehand.
--- For exact changes, please see source code ('lua/mini/basics.lua').
---
--- Here is the list of affected options (put cursor on it and press |CTRL-]|):
--- - General:
---     - Sets |<Leader>| key to |<Space>|. Be sure to make all Leader mappings
---       after this (otherwise they are made with default <Leader>).
---     - Runs `:filetype plugin indent on` (see |:filetype-overview|)
---     - |'backup'|
---     - |'mouse'|
---     - |'undofile'|
---     - |'writebackup'|
--- - Appearance
---     - |'breakindent'|
---     - |'cursorline'|
---     - |'fillchars'|
---     - |'linebreak'|
---     - |'number'|
---     - |'ruler'|
---     - |'showmode'|
---     - |'signcolumn'|
---     - |'shortmess'|
---     - |'splitbelow'|
---     - |'splitkeep'|
---     - |'splitright'|
---     - |'termguicolors'| (on Neovim<0.10; later versions have it smartly enabled)
---     - |'wrap'|
--- - Editing
---     - |'completeopt'|
---     - |'formatoptions'|
---     - |'ignorecase'|
---     - |'incsearch'|
---     - |'infercase'|
---     - |'smartcase'|
---     - |'smartindent'|
---     - |'virtualedit'|
---
--- ## options.extra_ui ~
---
--- The `config.options.extra_ui` sets certain options for visual appearance
--- which might not be aligned with common preferences, but still worth trying.
--- Any option is changed only if it was not set manually beforehand.
--- For exact changes, please see source code ('lua/mini/basics.lua').
---
--- List of affected options:
--- - |'list'|
--- - |'listchars'|
--- - |'pumblend'|
--- - |'pumheight'|
--- - |'winblend'|
--- - Runs `:syntax on` (see |:syntax-on|)
---
--- ## options.win_borders ~
---
--- The `config.options.win_borders` updates |'fillchars'| to have a consistent set
--- of characters for window border (`vert`, `horiz`, `msgsep`, etc.).
---
--- Available values:
--- - `'auto'` - infer from |'winborder'|. On Neovim<0.11 do nothing.
--- - `'bold'` - bold lines.
--- - `'dot'` - dot in every cell.
--- - `'double'` - double line.
--- - `'single'` - single line.
--- - `'solid'` - no symbol, only background.
---
--- # Mappings ~
--- *MiniBasics.config.mappings*
---
--- Usage example: >lua
---
---   require('mini.basics').setup({
---     mappings = {
---       basic = true,
---       option_toggle_prefix = [[\]],
---       windows = true,
---       move_with_alt = true,
---     }
---   })
--- <
--- If you want some mappings to be different or not made at all, set or delete
--- them after calling |MiniBasics.setup()|.
---
--- ## mappings.basic ~
---
--- The `config.mappings.basic` creates mappings for certain commonly mapped actions
--- (judging by study of available Neovim pre-configurations and public dotfiles).
---
--- Some of the mappings override built-in ones to either improve their
--- behavior or override its default not very useful action.
--- It will only add a mapping if it wasn't manually created before.
---
--- Here is a table with created mappings : >
---
---  |Keys   |     Modes       |                  Description                  |
---  |-------|-----------------|-----------------------------------------------|
---  | j     | Normal, Visual  | Move down by visible lines with no [count]    |
---  | k     | Normal, Visual  | Move up by visible lines with no [count]      |
---  | go    | Normal          | Add [count] empty lines after cursor          |
---  | gO    | Normal          | Add [count] empty lines before cursor         |
---  | gy    | Normal, Visual  | Copy to system clipboard                      |
---  | gp    | Normal, Visual  | Paste from system clipboard                   |
---  | gV    | Normal          | Visually select latest changed or yanked text |
---  | g/    | Visual          | Search inside current visual selection        |
---  | *     | Visual          | Search forward for current visual selection   |
---  | #     | Visual          | Search backward for current visual selection  |
---  | <C-s> | Normal, Visual, | Save and go to Normal mode                    |
---  |       |     Insert      |                                               |
--- <
--- Notes:
--- - See |[count]| for its meaning.
--- - On Neovim>=0.10 mappings for `#` and `*` are not created as their
---   enhanced variants are made built-in. See |v_star-default| and |v_#-default|.
--- - On Neovim>=0.11 there are |[<Space>| / |]<Space>| for adding empty lines.
---   The `gO` and `go` mappings are still created as they are more aligned with
---   similarly purposed |O| and |o| keys (although sometimes conflict with |gO|).
---
--- ## mappings.option_toggle_prefix ~
---
--- The `config.mappings.option_toggle_prefix` defines a prefix used for
--- creating mappings that toggle common options. The result mappings will be
--- `<prefix> + <suffix>`. For example, with default value, `\w` will toggle |'wrap'|.
---
--- Other viable choices for prefix are
--- - `,` (as a mnemonic for several values to toggle).
--- - `|` (as a same mnemonic).
--- - `yo` (used in 'tpope/vim-unimpaired')
--- - Something with |<Leader>| key, like `<Leader>t` (`t` for "toggle"). Note:
---   if your prefix contains `<Leader>` key, make sure to set it before
---   calling |MiniBasics.setup()| (as is done with default `basic` field of
---   |MiniBasics.config.options|).
---
--- After toggling, there will be a feedback about the current option value if
--- prior to `require('mini.basics').setup()` module wasn't silenced (see
--- "Silencing" section in |mini.basics|).
---
--- It will only add a mapping if it wasn't manually created before.
---
--- Here is a list of suffixes for created toggling mappings (all in Normal mode):
---
--- - `b` - |'background'|.
--- - `c` - |'cursorline'|.
--- - `C` - |'cursorcolumn'|.
--- - `d` - diagnostic (via |vim.diagnostic| functions).
--- - `h` - |'hlsearch'| (or |v:hlsearch| to be precise).
--- - `i` - |'ignorecase'|.
--- - `l` - |'list'|.
--- - `n` - |'number'|.
--- - `r` - |'relativenumber'|.
--- - `s` - |'spell'|.
--- - `w` - |'wrap'|.
---
--- ## mappings.windows ~
---
--- The `config.mappings.windows` creates mappings for easiere window manipulation.
---
--- It will only add a mapping if it wasn't manually created before.
---
--- Here is a list with created Normal mode mappings (all respect |[count]|):
--- - Window navigation:
---     - `<C-h>` - focus on left window (see |CTRL-W_H|).
---     - `<C-j>` - focus on below window (see |CTRL-W_J|).
---     - `<C-k>` - focus on above window (see |CTRL-W_K|).
---     - `<C-l>` - focus on right window (see |CTRL-W_L|).
--- - Window resize (all use arrow keys; variants of |:resize|; respect |[count]|):
---     - `<C-left>`  - decrease window width.
---     - `<C-down>`  - decrease window height.
---     - `<C-up>`    - increase window height.
---     - `<C-right>` - increase window width.
---
--- ## mappings.move_with_alt ~
---
--- The `config.mappings.move_with_alt` creates mappings for a more consistent
--- cursor move in Insert, Command, and Terminal modes. For example, it proves
--- useful in combination of autopair plugin (like |mini.pairs|) to move right
--- outside of inserted pairs (no matter what the pair is).
---
--- It will only add a mapping if it wasn't manually created before.
---
--- Here is a list of created mappings (`<M-x>` means `Alt`/`Meta` plus `x`):
--- - `<M-h>` - move cursor left.  Modes: Insert, Terminal, Command.
--- - `<M-j>` - move cursor down.  Modes: Insert, Terminal.
--- - `<M-k>` - move cursor up.    Modes: Insert, Terminal.
--- - `<M-l>` - move cursor right. Modes: Insert, Terminal, Command.
---
--- # Autocommands ~
--- *MiniBasics.config.autocommands*
---
--- Usage example: >lua
---
---   require('mini.basics').setup({
---     autocommands = {
---       basic = true,
---       relnum_in_visual_mode = true,
---     }
---   })
--- <
--- ## autocommands.basic ~
---
--- The `config.autocommands.basic` creates some common autocommands:
---
--- - Starts insert mode when opening terminal (see |:startinsert| and |TermOpen|).
--- - Highlights yanked text for a brief period of time (see |vim.hl.on_yank()|;
---   on Neovim<0.11 - |vim.hl.on_yank()|) and |TextYankPost|).
---
--- ## autocommands.relnum_in_visual_mode ~
---
--- The `config.autocommands.relnum_in_visual_mode` creates autocommands that
--- enable |'relativenumber'| in linewise and blockwise Visual modes and disable
--- otherwise. See |ModeChanged|.
MiniBasics.config = {
  -- Options. Set field to `false` to disable.
  options = {
    -- Basic options ('number', 'ignorecase', and many more)
    basic = true,

    -- Extra UI features ('winblend', 'listchars', 'pumheight', ...)
    extra_ui = false,

    -- Presets for window borders ('single', 'double', ...)
    -- Default 'auto' infers from 'winborder' option
    win_borders = 'auto',
  },

  -- Mappings. Set field to `false` to disable.
  mappings = {
    -- Basic mappings (better 'jk', save with Ctrl+S, ...)
    basic = true,

    -- Prefix for mappings that toggle common options ('wrap', 'spell', ...).
    -- Supply empty string to not create these mappings.
    option_toggle_prefix = [[\]],

    -- Window navigation with <C-hjkl>, resize with <C-arrow>
    windows = false,

    -- Move cursor in Insert, Command, and Terminal mode with <M-hjkl>
    move_with_alt = false,
  },

  -- Autocommands. Set field to `false` to disable
  autocommands = {
    -- Basic autocommands (highlight on yank, start Insert in terminal, ...)
    basic = true,

    -- Set 'relativenumber' only in linewise and blockwise Visual mode
    relnum_in_visual_mode = false,
  },

  -- Whether to disable showing non-error feedback
  silent = false,
}
--minidoc_afterlines_end

--- Toggle diagnostic for current buffer
---
--- This uses |vim.diagnostic| functions per buffer.
---
---@return string String indicator for new state. Similar to what |:set| `{option}?` shows.
MiniBasics.toggle_diagnostic = function()
  local buf_id = vim.api.nvim_get_current_buf()
  local is_enabled = H.diagnostic_is_enabled(buf_id)

  local f
  if vim.fn.has('nvim-0.10') == 1 then
    f = function(bufnr) vim.diagnostic.enable(not is_enabled, { bufnr = bufnr }) end
  else
    f = is_enabled and vim.diagnostic.disable or vim.diagnostic.enable
  end
  f(buf_id)

  local new_buf_state = not is_enabled

  return new_buf_state and '  diagnostic' or 'nodiagnostic'
end

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniBasics.config)

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  H.check_type('options', config.options, 'table')

  H.check_type('options.basic', config.options.basic, 'boolean')
  H.check_type('options.extra_ui', config.options.extra_ui, 'boolean')
  H.check_type('options.win_borders', config.options.win_borders, 'string')

  H.check_type('mappings', config.mappings, 'table')
  H.check_type('mappings.basic', config.mappings.basic, 'boolean')
  H.check_type('mappings.option_toggle_prefix', config.mappings.option_toggle_prefix, 'string')
  H.check_type('mappings.windows', config.mappings.windows, 'boolean')
  H.check_type('mappings.move_with_alt', config.mappings.move_with_alt, 'boolean')

  H.check_type('autocommands', config.autocommands, 'table')
  H.check_type('autocommands.basic', config.autocommands.basic, 'boolean')
  H.check_type('autocommands.relnum_in_visual_mode', config.autocommands.relnum_in_visual_mode, 'boolean')

  H.check_type('silent', config.silent, 'boolean')

  return config
end

H.apply_config = function(config)
  MiniBasics.config = config

  H.apply_options(config)
  H.apply_mappings(config)
  H.apply_autocommands(config)
end

-- Options --------------------------------------------------------------------
--stylua: ignore
H.apply_options = function(config)
  -- Use `local o, opt = vim.o, vim.opt` to copy lines as is.
  -- Or use `vim.o` and `vim.opt` directly.
  local o, opt = H.vim_o, H.vim_opt

  -- Basic options
  if config.options.basic then
    -- Leader key
    if vim.g.mapleader == nil then
      vim.g.mapleader = ' ' -- Use space as the one and only true Leader key
    end

    -- General
    o.undofile    = true  -- Enable persistent undo (see also `:h undodir`)

    o.backup      = false -- Don't store backup while overwriting the file
    o.writebackup = false -- Don't store backup while overwriting the file

    o.mouse       = 'a'   -- Enable mouse for all available modes

    vim.cmd('filetype plugin indent on') -- Enable all filetype plugins

    -- Appearance
    o.breakindent   = true    -- Indent wrapped lines to match line start
    o.cursorline    = true    -- Highlight current line
    o.linebreak     = true    -- Wrap long lines at 'breakat' (if 'wrap' is set)
    o.number        = true    -- Show line numbers
    o.splitbelow    = true    -- Horizontal splits will be below
    o.splitright    = true    -- Vertical splits will be to the right

    o.ruler         = false   -- Don't show cursor position in command line
    o.showmode      = false   -- Don't show mode in command line
    o.wrap          = false   -- Display long lines as just one line

    o.signcolumn    = 'yes'   -- Always show sign column (otherwise it will shift text)
    o.fillchars     = 'eob: ' -- Don't show `~` outside of buffer

    -- Editing
    o.ignorecase  = true -- Ignore case when searching (use `\C` to force not doing that)
    o.incsearch   = true -- Show search results while typing
    o.infercase   = true -- Infer letter cases for a richer built-in keyword completion
    o.smartcase   = true -- Don't ignore case when searching if pattern has upper case
    o.smartindent = true -- Make indenting smart

    o.completeopt   = 'menuone,noselect' -- Customize completions
    o.virtualedit   = 'block'            -- Allow going past the end of line in visual block mode
    o.formatoptions = 'qjl1'             -- Don't autoformat comments

    -- Neovim version dependent
    opt.shortmess:append('WcC') -- Reduce command line messages
    o.splitkeep = 'screen'      -- Reduce scroll during window split

    if vim.fn.has('nvim-0.10') == 0 then
      o.termguicolors = true -- Enable gui colors
    end
  end

  -- Some opinioneted extra UI options
  if config.options.extra_ui then
    o.pumblend  = 10 -- Make builtin completion menus slightly transparent
    o.pumheight = 10 -- Make popup menu smaller
    o.winblend  = 10 -- Make floating windows slightly transparent

    -- NOTE: Having `tab` present is needed because `^I` will be shown if
    -- omitted (documented in `:h listchars`).
    -- Having it equal to a default value should be less intrusive.
    o.listchars = 'tab:> ,extends:…,precedes:…,nbsp:␣' -- Define which helper symbols to show
    o.list      = true                                 -- Show some helper symbols

    -- Enable syntax highlighting if it wasn't already (as it is time consuming)
    if vim.fn.exists("syntax_on") ~= 1 then vim.cmd([[syntax enable]]) end
  end

  -- Use some common window borders presets
  local win_borders = config.options.win_borders
  if win_borders == 'auto' and vim.fn.has('nvim-0.11') == 1 then
    local option_value = vim.o.winborder
    win_borders = H.winborder_map[option_value] or option_value
  end
  local border_chars = H.win_borders_fillchars[win_borders]
  if border_chars ~= nil then vim.opt.fillchars:append(border_chars) end
end

H.vim_o = setmetatable({}, {
  __newindex = function(_, name, value)
    local was_set = vim.api.nvim_get_option_info2(name, { scope = 'global' }).was_set
    if was_set then return end

    vim.o[name] = value
  end,
})

H.vim_opt = setmetatable({}, {
  __index = function(_, name)
    local was_set = vim.api.nvim_get_option_info2(name, { scope = 'global' }).was_set
    if was_set then return { append = function() end, remove = function() end } end

    return vim.opt[name]
  end,
})

--stylua: ignore
H.win_borders_fillchars = {
  bold   = 'vert:┃,horiz:━,horizdown:┳,horizup:┻,verthoriz:╋,vertleft:┫,vertright:┣,msgsep:━',
  dot    = 'vert:·,horiz:·,horizdown:·,horizup:·,verthoriz:·,vertleft:·,vertright:·,msgsep:·',
  double = 'vert:║,horiz:═,horizdown:╦,horizup:╩,verthoriz:╬,vertleft:╣,vertright:╠,msgsep:═',
  single = 'vert:│,horiz:─,horizdown:┬,horizup:┴,verthoriz:┼,vertleft:┤,vertright:├,msgsep:─',
  solid  = 'vert: ,horiz: ,horizdown: ,horizup: ,verthoriz: ,vertleft: ,vertright: ,msgsep: ',
}
H.winborder_map = { none = 'solid', rounded = 'single', shadow = 'solid' }

-- Mappings -------------------------------------------------------------------
--stylua: ignore
H.apply_mappings = function(config)
  -- Use `local map = vim.keymap.set` to copy lines as is. Or use it directly.
  local map = H.keymap_set

  if config.mappings.basic then
    -- Move by visible lines. Notes:
    -- - Don't map in Operator-pending mode because it severely changes behavior:
    --   like `dj` on non-wrapped line will not delete it.
    -- - Condition on `v:count == 0` to allow easier use of relative line numbers.
    map({ 'n', 'x' }, 'j', [[v:count == 0 ? 'gj' : 'j']], { expr = true })
    map({ 'n', 'x' }, 'k', [[v:count == 0 ? 'gk' : 'k']], { expr = true })

    -- Add empty lines before and after cursor line supporting dot-repeat
    MiniBasics.put_empty_line = function(put_above)
      -- This has a typical workflow for enabling dot-repeat:
      -- - On first call it sets `operatorfunc`, caches data, and calls
      --   `operatorfunc` on current cursor position.
      -- - On second call it performs task: puts `v:count1` empty lines
      --   above/below current line.
      if type(put_above) == 'boolean' then
        vim.o.operatorfunc = 'v:lua.MiniBasics.put_empty_line'
        MiniBasics.cache_empty_line = { put_above = put_above }
        return 'g@l'
      end

      local target_line = vim.fn.line('.') - (MiniBasics.cache_empty_line.put_above and 1 or 0)
      vim.fn.append(target_line, vim.fn['repeat']({ '' }, vim.v.count1))
    end

    -- NOTE: if you don't want to support dot-repeat, use this snippet:
    -- ```
    -- map('n', 'gO', "<Cmd>call append(line('.') - 1, repeat([''], v:count1))<CR>")
    -- map('n', 'go', "<Cmd>call append(line('.'),     repeat([''], v:count1))<CR>")
    -- ```
    map('n', 'gO', 'v:lua.MiniBasics.put_empty_line(v:true)',  { expr = true, desc = 'Put empty line above' })
    map('n', 'go', 'v:lua.MiniBasics.put_empty_line(v:false)', { expr = true, desc = 'Put empty line below' })

    -- Copy/paste with system clipboard
    map({ 'n', 'x' }, 'gy', '"+y', { desc = 'Copy to system clipboard' })
    map(  'n',        'gp', '"+p', { desc = 'Paste from system clipboard' })
    -- - Paste in Visual with `P` to not copy selected text (`:h v_P`)
    map(  'x',        'gp', '"+P', { desc = 'Paste from system clipboard' })

    -- Reselect latest changed, put, or yanked text
    map('n', 'gV', '"g`[" . strpart(getregtype(), 0, 1) . "g`]"', { expr = true, replace_keycodes = false, desc = 'Visually select changed text' })

    -- Search inside visually highlighted text. Use `silent = false` for it to
    -- make effect immediately.
    map('x', 'g/', '<esc>/\\%V', { silent = false, desc = 'Search inside visual selection' })

    -- Search visually selected text (slightly better than builtins in
    -- Neovim<0.10 but slightly worse than builtins in Neovim>=0.10)
    -- TODO: Remove this after compatibility with Neovim=0.9 is dropped
    if vim.fn.has('nvim-0.10') == 0 then
      map('x', '*', [[y/\V<C-R>=escape(@", '/\')<CR><CR>]], { desc = 'Search forward' })
      map('x', '#', [[y?\V<C-R>=escape(@", '?\')<CR><CR>]], { desc = 'Search backward' })
    end

    -- Alternative way to save and exit in Normal mode.
    -- NOTE: Adding `redraw` helps with `cmdheight=0` if buffer is not modified
    map(  'n',        '<C-S>', '<Cmd>silent! update | redraw<CR>',      { desc = 'Save' })
    map({ 'i', 'x' }, '<C-S>', '<Esc><Cmd>silent! update | redraw<CR>', { desc = 'Save and go to Normal mode' })
  end

  local toggle_prefix = config.mappings.option_toggle_prefix
  if type(toggle_prefix) == 'string' and toggle_prefix ~= '' then
    local map_toggle = function(lhs, rhs, desc) map('n', toggle_prefix .. lhs, rhs, { desc = desc }) end

    if config.silent then
      -- Toggle without feedback
      map_toggle('b', '<Cmd>lua vim.o.bg = vim.o.bg == "dark" and "light" or "dark"<CR>', "Toggle 'background'")
      map_toggle('c', '<Cmd>setlocal cursorline!<CR>',                                    "Toggle 'cursorline'")
      map_toggle('C', '<Cmd>setlocal cursorcolumn!<CR>',                                  "Toggle 'cursorcolumn'")
      map_toggle('d', '<Cmd>lua MiniBasics.toggle_diagnostic()<CR>',                      'Toggle diagnostic')
      map_toggle('h', '<Cmd>let v:hlsearch = 1 - v:hlsearch<CR>',                         'Toggle search highlight')
      map_toggle('i', '<Cmd>setlocal ignorecase!<CR>',                                    "Toggle 'ignorecase'")
      map_toggle('l', '<Cmd>setlocal list!<CR>',                                          "Toggle 'list'")
      map_toggle('n', '<Cmd>setlocal number!<CR>',                                        "Toggle 'number'")
      map_toggle('r', '<Cmd>setlocal relativenumber!<CR>',                                "Toggle 'relativenumber'")
      map_toggle('s', '<Cmd>setlocal spell!<CR>',                                         "Toggle 'spell'")
      map_toggle('w', '<Cmd>setlocal wrap!<CR>',                                          "Toggle 'wrap'")
    else
      map_toggle('b', '<Cmd>lua vim.o.bg = vim.o.bg == "dark" and "light" or "dark"; print(vim.o.bg)<CR>',       "Toggle 'background'")
      map_toggle('c', '<Cmd>setlocal cursorline! cursorline?<CR>',                                               "Toggle 'cursorline'")
      map_toggle('C', '<Cmd>setlocal cursorcolumn! cursorcolumn?<CR>',                                           "Toggle 'cursorcolumn'")
      map_toggle('d', '<Cmd>lua print(MiniBasics.toggle_diagnostic())<CR>',                                      'Toggle diagnostic')
      map_toggle('h', '<Cmd>let v:hlsearch = 1 - v:hlsearch | echo (v:hlsearch ? "  " : "no") . "hlsearch"<CR>', 'Toggle search highlight')
      map_toggle('i', '<Cmd>setlocal ignorecase! ignorecase?<CR>',                                               "Toggle 'ignorecase'")
      map_toggle('l', '<Cmd>setlocal list! list?<CR>',                                                           "Toggle 'list'")
      map_toggle('n', '<Cmd>setlocal number! number?<CR>',                                                       "Toggle 'number'")
      map_toggle('r', '<Cmd>setlocal relativenumber! relativenumber?<CR>',                                       "Toggle 'relativenumber'")
      map_toggle('s', '<Cmd>setlocal spell! spell?<CR>',                                                         "Toggle 'spell'")
      map_toggle('w', '<Cmd>setlocal wrap! wrap?<CR>',                                                           "Toggle 'wrap'")
    end
  end

  if config.mappings.windows then
    -- Window navigation
    map('n', '<C-H>', '<C-w>h', { desc = 'Focus on left window' })
    map('n', '<C-J>', '<C-w>j', { desc = 'Focus on below window' })
    map('n', '<C-K>', '<C-w>k', { desc = 'Focus on above window' })
    map('n', '<C-L>', '<C-w>l', { desc = 'Focus on right window' })

    -- Window resize (respecting `v:count`)
    map('n', '<C-Left>',  '"<Cmd>vertical resize -" . v:count1 . "<CR>"', { expr = true, replace_keycodes = false, desc = 'Decrease window width' })
    map('n', '<C-Down>',  '"<Cmd>resize -"          . v:count1 . "<CR>"', { expr = true, replace_keycodes = false, desc = 'Decrease window height' })
    map('n', '<C-Up>',    '"<Cmd>resize +"          . v:count1 . "<CR>"', { expr = true, replace_keycodes = false, desc = 'Increase window height' })
    map('n', '<C-Right>', '"<Cmd>vertical resize +" . v:count1 . "<CR>"', { expr = true, replace_keycodes = false, desc = 'Increase window width' })
  end

  if config.mappings.move_with_alt then
    -- Move only sideways in command mode. Using `silent = false` makes movements
    -- to be immediately shown.
    map('c', '<M-h>', '<Left>',  { silent = false, desc = 'Left' })
    map('c', '<M-l>', '<Right>', { silent = false, desc = 'Right' })

    -- Don't `noremap` in insert mode to have these keybindings behave exactly
    -- like arrows (crucial inside TelescopePrompt)
    map('i', '<M-h>', '<Left>',  { noremap = false, desc = 'Left' })
    map('i', '<M-j>', '<Down>',  { noremap = false, desc = 'Down' })
    map('i', '<M-k>', '<Up>',    { noremap = false, desc = 'Up' })
    map('i', '<M-l>', '<Right>', { noremap = false, desc = 'Right' })

    map('t', '<M-h>', '<Left>',  { desc = 'Left' })
    map('t', '<M-j>', '<Down>',  { desc = 'Down' })
    map('t', '<M-k>', '<Up>',    { desc = 'Up' })
    map('t', '<M-l>', '<Right>', { desc = 'Right' })
  end
end

H.keymap_set = function(modes, lhs, rhs, opts)
  -- NOTE: Use `<C-H>`, `<C-Up>`, `<M-h>` casing (instead of `<C-h>`, `<C-up>`,
  -- `<M-H>`) to match the `lhs` of keymap info. Otherwise it will say that
  -- mapping doesn't exist when in fact it does.
  if type(modes) == 'string' then modes = { modes } end

  for _, mode in ipairs(modes) do
    -- Don't map if mapping is already set **globally**
    local map_info = H.get_map_info(mode, lhs)
    if not H.is_default_keymap(mode, lhs, map_info) then return end

    -- Map
    H.map(mode, lhs, rhs, opts)
  end
end

H.is_default_keymap = function(mode, lhs, map_info)
  if map_info == nil then return true end
  local rhs, desc = map_info.rhs or '', map_info.desc or ''

  -- Some mappings are set by default in Neovim
  if mode == 'n' and lhs == '<C-L>' then return rhs:find('nohl') ~= nil end
  if mode == 'n' and lhs == 'gO' and vim.fn.has('nvim-0.11') == 1 then return desc:find('vim%.lsp') ~= nil end
  if mode == 'i' and lhs == '<C-S>' then return desc:find('signature') ~= nil end
  if mode == 'x' and lhs == '*' then return rhs == [[y/\V<C-R>"<CR>]] end
  if mode == 'x' and lhs == '#' then return rhs == [[y?\V<C-R>"<CR>]] end
end

H.get_map_info = function(mode, lhs)
  local keymaps = vim.api.nvim_get_keymap(mode)
  for _, info in ipairs(keymaps) do
    if info.lhs == lhs then return info end
  end
end

-- Autocommands ---------------------------------------------------------------
H.apply_autocommands = function(config)
  local gr = vim.api.nvim_create_augroup('MiniBasicsAutocommands', {})

  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = gr, pattern = pattern, callback = callback, desc = desc })
  end

  if config.autocommands.basic then
    local f = function() vim.hl.on_yank() end
    if vim.fn.has('nvim-0.11') == 0 then f = function() vim.highlight.on_yank() end end
    au('TextYankPost', '*', f, 'Highlight yanked text')

    local start_terminal_insert = vim.schedule_wrap(function(data)
      -- Try to start terminal mode only if target terminal is current
      if not (vim.api.nvim_get_current_buf() == data.buf and vim.bo.buftype == 'terminal') then return end
      vim.cmd('startinsert')
    end)
    au('TermOpen', 'term://*', start_terminal_insert, 'Start builtin terminal in Insert mode')
  end

  if config.autocommands.relnum_in_visual_mode then
    au(
      'ModeChanged',
      -- Show relative numbers only when they matter (linewise and blockwise
      -- selection) and 'number' is set (avoids horizontal flickering)
      '*:[V\x16]*',
      function() vim.wo.relativenumber = vim.wo.number end,
      'Show relative line numbers'
    )
    au(
      'ModeChanged',
      '[V\x16]*:*',
      -- Hide relative numbers when neither linewise/blockwise mode is on
      function() vim.wo.relativenumber = string.find(vim.fn.mode(), '^[V\22]') ~= nil end,
      'Hide relative line numbers'
    )
  end
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.basics) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.map = function(mode, lhs, rhs, opts)
  if lhs == '' then return end
  opts = vim.tbl_deep_extend('force', { silent = true }, opts or {})
  vim.keymap.set(mode, lhs, rhs, opts)
end

if vim.fn.has('nvim-0.10') == 1 then
  H.diagnostic_is_enabled = function(buf_id) return vim.diagnostic.is_enabled({ bufnr = buf_id }) end
else
  H.diagnostic_is_enabled = function(buf_id) return not vim.diagnostic.is_disabled(buf_id) end
end

return MiniBasics
