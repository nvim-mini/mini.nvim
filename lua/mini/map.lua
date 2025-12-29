--- *mini.map* Window with buffer text overview
---
--- MIT License Copyright (c) 2022 Evgeni Chasnovski

--- Features:
--- - Show and manage special floating window displaying automatically updated
---   overview of current buffer text. Window takes up whole height of Neovim
---   instance and is fixed to a left/right side. Map content is computed by
---   taking all current lines, converting it to binary whitespace/non-whitespace
---   mask, rescaling to appropriate dimensions, and converting back to strings
---   consisting from special encoding symbols. All this is done **very fast** and
---   **asynchronously**. See |MiniMap.open()|, |MiniMap.refresh()|, |MiniMap.close()|,
---   |MiniMap.toggle()|, |MiniMap.toggle_side()|.
---   For a general overview and tips, see |mini.map-usage|.
---
--- - Show scrollbar next to map content. It represents current line and view
---   (top and bottom visible lines). Can be the only thing shown, making map
---   window a "pure scrollbar". See "Pure scrollbar config" section in
---   |MiniMap.config|.
---
--- - Highlight map lines representing certain data in current buffer. This is
---   done via extensible set of callables, called integrations (see
---   "Integrations" section in |MiniMap.config|). There are pre-built generators
---   for common integrations:
---     - Builtin search (as result of |/| and similar).
---     - Builtin diagnostic (taken from |vim.diagnostic.get()|).
---     - General diff hunks provided by |mini.diff|.
---     - Hunks computed provided by 'lewis6991/gitsigns.nvim'.
---   For more details see |MiniMap.gen_integration|.
---
--- - Focus on map window to quickly browse current (source) buffer. Moving inside
---   map window updates cursor position in source window enabling fast and
---   targeted buffer exploration. To focus back, hit `<CR>` to accept current
---   explored position or `<Esc>` to go back to original position. See
---   |MiniMap.toggle_focus()|.
---
--- - Customizable via |MiniMap.config| and/or `opts` argument of |MiniMap.open()|
---   or |MiniMap.refresh()|:
---     - Encoding symbols used to display binary information of different
---       resolution (default is 3x2). There are pre-built generators for
---       different basic character families and resolutions. See
---       |MiniMap.gen_encode_symbols|.
---     - Scrollbar symbols, separate for line and view. Can have any width
---       (even zero, which virtually disables scrollbar).
---     - Integrations producing map line highlights.
---     - Window options: side (left/right), width, 'winblend', and more.
---
--- What it doesn't do:
--- - Automatically refresh when typing in Insert mode. Although it can be done in
---   non-blocking way, it still might introduce considerable computation overhead
---   (especially in very large files).
--- - Has more flexible window configuration. In case a full height floating
---   window obstructs vision of underlying buffers, use |MiniMap.toggle()| or
---   |MiniMap.toggle_side()|. Works best with global statusline.
--- - Provide autoopen functionality. Due to vast differences in user preference
---   of when map window should be shown, set up of automatic opening is left to
---   user. A common approach would be to call `MiniMap.open()` on |VimEnter| event.
---   If you use |mini.starter|, you can modify `<CR>` buffer mapping: >lua
---
---     local set_map_keymap = function()
---       local rhs = function()
---         MiniStarter.eval_current_item()
---         MiniMap.open()
---       end
---       vim.keymap.set('n', '<CR>', rhs, { buffer = true })
---     end
---     local opts = { pattern = 'MiniStarterOpened', callback = set_map_keymap }
---     vim.api.nvim_create_autocmd('User', opts)
--- <
--- # Setup ~
---
--- This module needs a setup with `require('mini.map').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `MiniMap`
--- which you can use for scripting or manually (with `:lua MiniMap.*`).
---
--- See |MiniMap.config| for available config settings.
---
--- You can override runtime config settings (like `config.modifiers`) locally
--- to buffer inside `vim.b.minimap_config` which should have same structure
--- as `MiniMap.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- # Dependencies ~
---
--- Suggested dependencies (provide extra functionality for integrations):
--- - Enabled |mini.diff| module for general diff highlighting via
---   |MiniMap.gen_integration.diff()|. If missing, no highlighting is added.
--- - Plugin [lewis6991/gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim)
---   for Git status highlighting via |MiniMap.gen_integration.gitsigns()|.
---   If missing, no highlighting is added.
---
--- # Comparisons ~
---
--- - [wfxr/minimap.vim](https://github.com/wfxr/minimap.vim):
---     - 'mini.map' doesn't have dependencies while being as fast as written
---       in Rust dependency of 'minimap.vim'.
---     - 'mini.map' uses floating window, while 'minimap.vim' uses regular one.
---     - 'mini.map' provides slightly different visual interface with
---       scrollbar and integration counts.
---     - 'mini.map' allows encode symbols customization, 'minimap.vim' does not.
---     - 'mini.map' allows extending highlight integrations, while only
---       builtin search and git status are supported in 'minimap.vim'.
---     - 'mini.map' updates in asynchronous (non-blocking) fashion, 'minimap.vim'
---       does not.
---     - 'mini.map' can be used as a pure scrollbar, 'minimap.vim' can not.
--- - [dstein64/nvim-scrollview](https://github.com/dstein64/nvim-scrollview):
---     - 'mini.map' has two-part scrollbar showing current line and view (with
---       variable height), while 'nvim-scrollview' shows only current view
---       (with fixed height).
---     - 'nvim-scrollview' respects folds, i.e. shows view of visible lines,
---       while 'mini.map' by design always shows view based on actual lines.
---     - 'nvim-scrollview' creates scrollbar which can be dragged with mouse,
---       while 'mini.nvim' does not, by design (use |MiniMap.toggle_focus()|).
---     - 'mini.map' can show buffer outline, while 'nvim-scrollview' can not.
---     - 'mini.map' can show highlight integrations, while 'nvim-scrollview'
---       can not.
--- - [petertriho/nvim-scrollbar](https://github.com/petertriho/nvim-scrollbar):
---     - 'mini.map' has two-part scrollbar showing current line and view (with
---       variable height), while 'nvim-scrollbar' shows only current view.
---     - 'mini.map' can show buffer outline, while 'nvim-scrollbar' can not.
---     - 'mini.map' has fully extendable highlight integrations, while
---       'nvim-scrollbar' only supports diagnostic and search (with dependency).
--- - [lewis6991/satellite.nvim](https://github.com/lewis6991/satellite.nvim):
---     - Almost the same differences as with 'dstein64/nvim-scrollview', except
---       'satellite.nvim' can display some set of integration highlights.
---
--- # Highlight groups ~
---
--- - `MiniMapNormal` - basic highlight of whole window.
--- - `MiniMapSymbolCount` - counts of per-line integration items.
--- - `MiniMapSymbolLine` - scrollbar part representing current line.
--- - `MiniMapSymbolView` - scrollbar part representing current view.
---
--- To change any highlight group, set it directly with |nvim_set_hl()|.
---
--- # Disabling ~
---
--- To disable, set `vim.g.minimap_disable` (globally) or `vim.b.minimap_disable`
--- (for a buffer) to `true`. Considering high number of different scenarios
--- and customization intentions, writing exact rules for disabling module's
--- functionality is left to user. See |mini.nvim-disabling-recipes| for common
--- recipes.
---@tag MiniMap

--- # Mappings ~
---
--- This module doesn't make mappings, only provides functions for users to map
--- manually. Here is how one |<Leader>| set of mappings can be constructed: >lua
---
---   vim.keymap.set('n', '<Leader>mc', MiniMap.close)
---   vim.keymap.set('n', '<Leader>mf', MiniMap.toggle_focus)
---   vim.keymap.set('n', '<Leader>mo', MiniMap.open)
---   vim.keymap.set('n', '<Leader>mr', MiniMap.refresh)
---   vim.keymap.set('n', '<Leader>ms', MiniMap.toggle_side)
---   vim.keymap.set('n', '<Leader>mt', MiniMap.toggle)
--- <
--- # How automatic refresh works ~
---
--- Automatic refresh is done by calling |MiniMap.refresh()| when appropriate
--- |events| occur. It is done with specially chosen `parts` argument value (to
--- avoid unnecessary computations). For example, when only cursor has moved
--- (|CursorMoved|), only scrollbar is updated; so no recomputation of integrations
--- or line encoding is done.
---
--- To avoid visual clutter, automatic refresh is done only in normal buffers
--- and help pages (i.e. with |'buftype'| being empty or "help")
---
--- When you think content is not up to date, try one of these:
--- - Call |MiniMap.refresh()| manually. Make mapping to make it easier.
--- - Save current buffer, for example with |:write|.
--- - Exit and enter Normal mode (if your Neovim version supports |ModeChanged|).
---@tag mini.map-usage

---@alias __map_opts table|nil Options used to define map configuration. Same structure
---   as |MiniMap.config|. Will have effect until at least one tabpage has opened
---   map window. Default values are taken in the following order:
---   - From `opts` field of |MiniMap.current|.
---   - From `vim.b.minimap_config`.
---   - From |MiniMap.config|.

---@diagnostic disable:undefined-field

-- Module definition ==========================================================
local MiniMap = {}
local H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniMap.config|.
---
---@usage >lua
---   require('mini.map').setup() -- use default config
---   -- OR
---   require('mini.map').setup({}) -- replace {} with your config table
--- <
MiniMap.setup = function(config)
  -- Export module
  _G.MiniMap = MiniMap

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Define behavior
  H.create_autocommands()

  -- Create default highlighting
  H.create_default_hl()
end

--stylua: ignore
--- Defaults ~
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text # Symbols ~
---
--- Options in `config.symbols` define characters used to display various
--- information in map window.
---
--- ## Encode symbols ~
---
--- The `config.symbols.encode` option defines which characters are used to
--- encode source buffer lines. For details of encode algorithm, see
--- |MiniMap.encode_strings()|.
---
--- This option should be a table with the following structure:
--- - <resolution> field - table containing <row> and <col> elements with row
---   and column resolution of each symbol. This defines encoding structure and
---   number of needed encode symbols.
--- - Numerical fields 1, 2, ..., 2^(row_resolution * col_resolution). Each symbol
---   represents a `(row_resolution, col_resolution)` boolean mask (`true` for
---   non-whitespace, `false` for whitespace), created as (reversed) binary digit:
---   `true` as 1; `false` as 0. Traversing left-right, top-bottom (top-left is
---   lowest bit, bottom-right - highest). So first symbol encodes a complete
---   whitespace, last - complete non-whitespace.
---
--- If `nil` (default), output of |MiniMap.gen_encode_symbols.block()| with `'3x2'`
--- identifier is used.
---
--- Example: { '1', '2', '3', '4', resolution = { row = 1, col = 2 } }. This
--- will encode two characters in each input row. So a string `'  a  aaa'` will
--- be encoded as `'1234'`.
---
--- There are pre-built generators of encode symbols:
--- - |MiniMap.gen_encode_symbols.block()|
--- - |MiniMap.gen_encode_symbols.dot()|
--- - |MiniMap.gen_encode_symbols.shade()|
---
--- ## Scrollbar symbols ~
---
--- Options `config.symbols.scroll_line` and `config.symbols.scroll_view` define
--- strings used to represent current line and current view inside map window.
--- Can have any length, map window content will adjust.
---
--- If supplied window width is small enough so that only (part of) of
--- scrollbar can be shown, it is called a "pure scrollbar". The behavior differs
--- slightly from normal map window. See "Pure scrollbar config" later section.
---
--- Some suggestions for scrollbar symbols:
--- - View-line pairs: '▒' and '█'.
--- - Line - '🮚', '▶'.
--- - View - '╎', '┋', '┋'.
---
--- # Integrations ~
---
--- Option `config.integrations` is an array of integrations. Each one is used
--- to define map line highlights representing some important lines in source
--- buffer. If `nil` (default), no integrations are used.
---
--- Each integration should be a callable returning an array with data about
--- **source buffer** lines it wants to highlight. Each array element should be
--- a table with <line> (source buffer line number) and <hl_group> (string with
--- highlight group name) keys. Note: line number outside of source buffer
--- count will be converted to a nearest appropriate one.
---
--- Example output of single integration: >lua
---
---   {
---     { line = 1, hl_group = 'Search' },
---     { line = 2, hl_group = 'Operator' },
---     { line = 9, hl_group = 'Search'}
---   }
--- <
--- Conversion to map highlights is done on a "first seen" basis: actual
--- highlight group applied to a map line is taken from the first integration
--- output convertible to that map line. Other outputs with same map line
--- (after conversion) contribute to integration count shown between scrollbar
--- and encoded lines (if `config.window.show_integration_count` is `true`).
---
--- Previous example output with default `'3x2'` resolution will add |hl-Search|
--- highlight on map lines 1 and 3, and show integration count 2 on first line.
---
--- Every element of integrations array is called one by one from start to end
--- with their outputs appended to end of single array. This means that more
--- important integrations should be placed in the beginning of an array, as
--- this will make them have higher priority in case other integrations will
--- highlight same map line.
---
--- Example of using `config.integrations`: >lua
---
---   local map = require('mini.map')
---   map.setup({
---     integrations = {
---       map.gen_integration.builtin_search(),
---       map.gen_integration.diff(),
---       map.gen_integration.diagnostic(),
---     },
---   })
--- <
--- # Window config ~
---
--- Option `config.window` defines some properties of map window.
---
--- `window.focusable` - whether to allow focusing on map window with other
--- methods beside |MiniMap.toggle_focus()| (like |:wincmd|, |CTRL-W|, or mouse).
--- Default: `false`.
---
--- `window.side` - which side to stick map window: `'left'` or `'right'` (default).
---
--- `window.show_integration_count` - whether to show integration count between
--- scrollbar and encoded lines. Integration count is a number of integration
--- outputs which were converted to same map line. When `true`, adds single
--- cell column with numbers from 2 to 9 and character '+' indicating count
--- greater than 9. Count 1 is not shown, because it is redundant to highlighted
--- map line. Default: `true`.
---
--- `window.width` - width of floating window, including scrollbar and
--- integration count column. Default: 10.
---
--- `window.winblend` - value of 'winblend' of floating window. Value 0 makes it
--- completely non-transparent, 100 - completely transparent (content is still
--- visible, but with slightly different highlights).
---
--- `window.zindex` - z-index of floating window. Default: 10.
---
--- # Pure scrollbar config ~
---
--- "Pure scrollbar" is a configuration when window width is not enough to show
--- encoded content. It has following differences from default "map" approach:
--- - It doesn't perform line encoding with |MiniMap.encode_strings()|
---   but instead uses encoding with fixed number of lines (equal to window
---   height).
--- - Integration highlights are not computed.
---
--- Config: >lua
---
---   require('mini.map').setup({
---     -- Customize `symbols` to your liking
---
---     window = {
---       -- Set this to the maximum width of your scroll symbols
---       width = 1,
---
---       -- Set this to your liking. Try values 0, 25, 50, 75, 100
---       winblend = 100,
---
---       -- Don't need extra column
---       show_integration_count = false,
---     }
---   })
--- <
MiniMap.config = {
  -- Highlight integrations (none by default)
  integrations = nil,

  -- Symbols used to display data
  symbols = {
    -- Encode symbols. See `:h MiniMap.config` for specification and
    -- `:h MiniMap.gen_encode_symbols` for pre-built ones.
    -- Default: solid blocks with 3x2 resolution.
    encode = nil,

    -- Scrollbar parts for view and line. Use empty string to disable any.
    scroll_line = '█',
    scroll_view = '┃',
  },

  -- Window options
  window = {
    -- Whether window is focusable in normal way (with `wincmd` or mouse)
    focusable = false,

    -- Side to stick ('left' or 'right')
    side = 'right',

    -- Whether to show count of multiple integration highlights
    show_integration_count = true,

    -- Total width
    width = 10,

    -- Value of 'winblend' option
    winblend = 25,

    -- Z-index
    zindex = 10,
  },
}
--minidoc_afterlines_end

--- Table with information about current state of map
---
--- At least these keys are supported:
--- - <buf_data> - table with buffer identifiers. Field <map> contains
---   identifier of a buffer used to display map. Field <source> - buffer
---   identifier which content map is displaying (i.e. source buffer).
--- - <win_data> - table of window identifiers used to display map in certain
---   tabpage. Keys: tabpage identifier. Values: window identifier.
--- - <opts> - current options used to control map display. Same structure
---   as |MiniMap.config|. Takes precedence over global and buffer-local configs.
---   Is reset when last map window is closed with |MiniMap.close()|.
MiniMap.current = {
  buf_data = {},
  win_data = {},
  opts = {},
}

-- Module functionality =======================================================
--- Encode strings
---
--- This takes arbitrary array of strings and computes its non-whitespace
--- outline. Output is an array of strings with configurable array length, string
--- width, and symbols representing encoding.
---
--- Each encode symbol is assumed to have resolution within which it can convey
--- binary information. For example, resolution `3x2` (row resolution 3,
--- column - 2) means that each symbol can encode 3 rows and 2 columns of
--- binary data. Here it is used to encode non-whitespace mask. See more in
--- "Encode symbols" section of |MiniMap.config|.
---
--- Encoding has the following steps:
--- - Convert strings to boolean mask: 2d boolean array with each row
---   representing a string. Element in every row subarray is `true` if
---   respective (possibly multibyte) character in a string is not a whitespace,
---   `false` otherwise. Note: tabs are expanded into 'tabstop' spaces.
--- - Rescale to appropriate dimensions:
---     - Each output dimension is just enough to encode all input strings, but
---       not more than supplied dimensions (`opts.n_rows * resolution.row` and
---       `opts.n_cols * resolution.col` respectively).
---     - If input dimensions are too big to fit inside output, perform grid
---       downscaling with loss of information. Input boolean mask is divided
---       into 2d-bins with as equal as possible dimensions. Each bin then
---       converted into single boolean value: `true` if bin contains at least
---       one `true` element, `false` otherwise. This leads to a whitespace
---       output meaning that **all** entries in a bin are whitespace, while
---       non-whitespace output means that **some** entry is non-whitespace.
--- - Convert boolean mask to symbol strings:
---     - Input rescaled boolean mask is divided into bins with dimensions of
---       symbol resolution (assuming `false` outer padding).
---     - Each bin with resolution dimensions is transformed into encode symbol.
---       Single convertible `(resolution.row, resolution.col)` boolean
---       mask is treated as (reversed) binary digit: `true` as 1; `false` as 0.
---       Traversing left-right, top-bottom (top-left is lowest bit,
---       bottom-right - highest).
---
--- Example:
---
--- Assume the output should have 3 rows of symbols each with width 2. Encode
--- symbols are ' ', '▌', '▐', '█' with `1x2` resolution.
---
--- Assume input strings: >
---   aaaaa
---    b b
---
---    d d
---   e e
--- <
--- Steps:
--- - Convert to boolean mask (each row is a boolean array, "t"/"f" ~ `true`/`false`,
---   empty spots are equivalent to being `false`): >
---   ttttt
---   ftft
---
---   ftft
---   tft
--- <
--- - Rescale. Output dimensions are `n_rows * resolution.row = 3 * 1 = 3` rows and
---   `n_cols * resolution.col = 2 * 2 = 4`. It creates as equal as possible grid
---   with 3 rows and 4 columns and converts bins to single booleans. Result: >
---   tttt
---   tftf
---   ttff
--- <
--- - Convert to symbols. It makes `1x2` bins, treats their input as (reversed)
---   binary digits (`ff=00=0`, `tf=10=1`, `ft=01=2`, `tt=11=3`) and takes
---   corresponding symbols from supplied options (value plus 1). Result: >
---   ██
---   ▌▌
---   █
--- <
---@param strings table Array of arbitrary strings.
---@param opts table|nil Options. Possible fields:
---   - <n_rows> - number of rows in output encoding. If too big, will be
---     truncated to be maximum needed to encode all input strings (taking into
---     account symbols row resolution). Default: `math.huge`.
---   - <n_cols> - width of every encoding string. If too big, will be truncated
---     to be maximum needed to encode all input strings (taking into account
---     symbols column resolution). Default: `math.huge`.
---   - <symbols> - array of symbols with extra `resolution` field. See "Encode
---     symbols" section of |MiniMap.config| for more details. Default: output
---     of |MiniMap.gen_encode_symbols.block()| with `'3x2'` identifier.
---
---@return table Array of encoded strings.
MiniMap.encode_strings = function(strings, opts)
  -- Validate input
  if not H.is_array_of(strings, H.is_string) then
    H.error('`strings` argument of `encode_strings()` should be array of strings.')
  end

  opts = vim.tbl_deep_extend(
    'force',
    { n_rows = math.huge, n_cols = math.huge, symbols = H.get_config().symbols.encode or H.default_symbols },
    opts or {}
  )

  -- Compute encoding
  local mask = H.mask_from_strings(strings, opts)
  mask = H.mask_rescale(mask, opts)
  return H.mask_to_symbols(mask, opts)
end

--- Open map window
---
--- This creates and shows map window in current tabpage. It basically has
--- two steps:
--- - If not already done, create map buffer (used to set lines and other
---   visual indicators) and map window.
--- - Call |MiniMap.refresh()|.
---
---@param opts __map_opts
MiniMap.open = function(opts)
  -- Early returns
  if H.is_disabled() then return end

  -- Normalize input
  opts = H.normalize_opts(opts)

  -- Allow execution in case of already opened window
  if H.is_window_open() then
    MiniMap.refresh(opts)
    return
  end

  -- Open buffer and window
  local buf_id = MiniMap.current.buf_data.map
  if buf_id == nil or not vim.api.nvim_buf_is_valid(buf_id) then
    buf_id = H.create_map_buffer()
    MiniMap.current.buf_data.map = buf_id
  end

  local win_id = vim.api.nvim_open_win(buf_id, false, H.normalize_window_options(opts.window))
  H.set_current_map_win(win_id)

  -- Set buffer and window options. Other important options are handled by
  -- `style = 'minimal'` in `nvim_open_win()`.
  vim.api.nvim_win_call(win_id, function()
    --stylua: ignore
    local options = {
      'buftype=nofile', 'foldcolumn=0', 'foldlevel=999', 'matchpairs=', 'nobuflisted',
      'nomodeline',     'noreadonly',   'noswapfile',    'synmaxcol&',  'nowrap',
    }
    -- Vim's `setlocal` is currently more robust compared to `opt_local`
    -- Use `noautocmd` to make it more invisible for others
    vim.cmd(('silent! noautocmd setlocal %s'):format(table.concat(options, ' ')))

    -- Override Normal highlighting locally for map window
    vim.cmd('silent! setlocal winhighlight=NormalFloat:MiniMapNormal')
  end)

  -- Refresh content
  MiniMap.refresh(opts)
end

--- Refresh map window
---
--- This function serves two purposes:
--- - Update current map configuration via `opts`.
--- - Update parts of displayed content via `parts`.
---
---@param opts __map_opts
---@param parts table|nil Which parts to update. Recognised keys with boolean
---   values (all `true` by default):
---   - <integrations> - whether to update integration highlights.
---   - <lines> - whether to update map lines.
---   - <scrollbar> - whether to update scrollbar.
MiniMap.refresh = function(opts, parts)
  -- Early return
  if H.is_disabled() or not H.is_window_open() then return end

  -- Normalize input
  opts = H.normalize_opts(opts)
  parts = vim.tbl_deep_extend('force', { integrations = true, lines = true, scrollbar = true }, parts or {})

  -- Update current data
  H.cache.scrollbar_data.offset = math.max(H.str_width(opts.symbols.scroll_line), H.str_width(opts.symbols.scroll_view))
    + (opts.window.show_integration_count and 1 or 0)
  MiniMap.current.opts = opts

  -- Update window options
  H.update_window_opts()

  -- Possibly update parts in asynchronous fashion
  if parts.lines then vim.schedule(H.update_map_lines) end
  if parts.scrollbar then vim.schedule(H.update_map_scrollbar) end
  if parts.integrations then vim.schedule(H.update_map_integrations) end
end

--- Close map window
---
--- Also resets `opts` field of |MiniMap.current| after closing last map window
--- (among possibly several tabpages).
MiniMap.close = function()
  pcall(vim.api.nvim_win_close, H.get_current_map_win(), true)
  H.set_current_map_win(nil)

  -- Reset current options if closed last window so as to use config during
  -- next opening
  if vim.tbl_count(MiniMap.current.win_data) == 0 then MiniMap.current.opts = {} end
end

--- Toggle map window
---
--- Open if not shown in current tabpage, close otherwise.
---
---@param opts table|nil Input for |MiniMap.open()|.
MiniMap.toggle = function(opts)
  if H.is_window_open() then
    MiniMap.close()
  else
    MiniMap.open(opts)
  end
end

--- Toggle focus to/from map window
---
--- When not inside map window, put cursor inside map window; otherwise put
--- cursor in previous window with source buffer.
---
--- When cursor is moving inside map window (but not just after focusing), view of
--- source window is updated to show first line convertible to current map line.
--- This allows quick targeted source buffer exploration.
---
--- There are at least these extra methods to focus back from map window:
--- - Press `<CR>` to accept current explored position in source buffer.
---   Equivalent to calling this function with `false` argument.
--- - Press `<Esc>` to go back to original position prior focusing on map window.
---   Equivalent to calling this function with `true` argument.
---
---@param use_previous_cursor boolean|nil Whether to focus on source window at
---   original cursor position (the one prior focusing on map window).
MiniMap.toggle_focus = function(use_previous_cursor)
  if not H.is_window_open() then return end
  local cur_win, map_win = vim.api.nvim_get_current_win(), H.get_current_map_win()

  if cur_win == map_win then
    -- Focus on previous window
    vim.api.nvim_set_current_win(H.cache.previous_win.id)

    -- Use either previous cursor or first non-whitespace character (if this
    -- was the result of cursor movement inside map window)
    if use_previous_cursor and H.cache.previous_win.cursor ~= nil then
      vim.api.nvim_win_set_cursor(0, H.cache.previous_win.cursor)
    elseif H.cache.n_map_cursor_moves > 1 then
      vim.cmd('normal! ^')
    end
  else
    -- Focus on map window. Cursor is set on `BufEnter` to account for other
    -- ways of focusing on buffer (for example, with `<C-w><C-w>`)
    vim.api.nvim_set_current_win(map_win)
  end
end

--- Toggle side of map window
---
--- A small convenience wrapper for calling |MiniMap.refresh()| to change the
--- side of map window.
MiniMap.toggle_side = function()
  if not H.is_window_open() then return end
  local cur_side = MiniMap.current.opts.window.side
  MiniMap.refresh(
    { window = { side = cur_side == 'left' and 'right' or 'left' } },
    { integrations = false, lines = false, scrollbar = false }
  )
end

--- Generate encode symbols
---
--- This is a table with function elements. Call to actually get encode symbols.
---
--- Each element takes a string resolution identifier of a form `'rxc'` (like `'3x2'`)
--- where `r` is a row resolution of each symbol (how many rows of binary data it
--- can encode) and `c` is a column resolution (how many columns it can encode).
MiniMap.gen_encode_symbols = {}

--- Generate block encode symbols
---
--- Outputs use solid block to encode binary data. Example: '🬗', '▟', '█'.
---
---@param id string Resolution identifier.
---   Available values: `'1x2'`, `'2x1'`, `'2x2'`, `'3x2'` (default in 'mini.map').
MiniMap.gen_encode_symbols.block = function(id) return H.block_symbols[id] end

--- Generate dot encode symbols
---
--- Outputs use dots to encode binary data. Example: '⡪', '⣼', '⣿'.
---
---@param id string Resolution identifier. Available values: `'4x2'`, `'3x2'`.
MiniMap.gen_encode_symbols.dot = function(id) return H.dot_symbols[id] end

--- Generate shade encode symbols
---
--- Outputs use whole cell shades to encode binary data. They use same set of
--- characters ('░', '▒', '▒', '▓), but with different resolution.
---
---@param id string Resolution identifier. Available values: `'1x2'`, `'2x1'`.
MiniMap.gen_encode_symbols.shade = function(id) return H.shade_symbols[id] end

--- Generate integrations
---
--- This is a table with function elements. Call to actually get encode symbols.
---
--- Each element takes a table defining highlight groups used for to highlight
--- map lines.
MiniMap.gen_integration = {}

--- Builtin search
---
--- Highlight lines with matches of current builtin search (like with |/|, |?|, etc.).
--- Integration count reflects number of actual matches.
---
--- It prompts integration highlighting update on every change of |'hlsearch'|
--- (see |OptionSet|) or |v:hlsearch|. Note that it is not happening for some keys:
--- - After starting search with |n|, |N|, |star|, or |#|.
---   To enable highlight update on this keys, make custom mappings. Like this: >lua
---
---   for _, key in ipairs({ 'n', 'N', '*', '#' }) do
---     local rhs = key ..
---       '<Cmd>lua MiniMap.refresh({}, {lines = false, scrollbar = false})<CR>'
---     vim.keymap.set('n', key, rhs)
---   end
--- <
---@param hl_groups table|nil Table defining highlight groups. Can have the
---   following fields:
---   - <search> - highlight group for search matches. Default: |hl-Search|.
MiniMap.gen_integration.builtin_search = function(hl_groups)
  if hl_groups == nil then hl_groups = { search = 'Search' } end

  -- Update when necessary. Not ideal, because it won't react on `n/N/*`, etc.
  -- See https://github.com/neovim/neovim/issues/18879
  local gr = vim.api.nvim_create_augroup('MiniMapBuiltinSearch', {})
  local opts = { group = gr, pattern = 'hlsearch', callback = H.on_integration_update, desc = "On 'hlsearch' update" }
  vim.api.nvim_create_autocmd('OptionSet', opts)

  -- - NOTE: beware of possible https://github.com/neovim/neovim/issues/21469
  vim.cmd([[
    silent! call dictwatcherdel(v:, 'hlsearch', 'MiniMapOnHLSearchChanged')
    function! MiniMapOnHLSearchChanged(d,k,z)
      lua MiniMap.refresh(nil, { lines = false, scrollbar = false })
    endfunction
    call dictwatcheradd(v:, 'hlsearch', 'MiniMapOnHLSearchChanged')
  ]])

  local search_hl = hl_groups.search

  return function()
    -- Do nothing of search is not active
    if vim.v.hlsearch == 0 or not vim.o.hlsearch then return {} end

    -- Do nothing if not inside source buffer (can happen in map buffer, for example)
    if not H.is_source_buffer() then return {} end

    -- Save window view to later restore, as the only way to get positions of
    -- search matches seems to be consecutive application of `search()` and
    -- retrieving cursor position.
    local win_view = vim.fn.winsaveview()

    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    local search_count = vim.fn.searchcount({ recompute = true, maxcount = 0 })
    local search_pattern = vim.fn.getreg('/')
    local line_hl = {}
    for _ = 1, (search_count.total or 0) do
      vim.fn.search(search_pattern)
      table.insert(line_hl, { line = vim.fn.line('.'), hl_group = search_hl })
    end

    vim.fn.winrestview(win_view)

    return line_hl
  end
end

--- Builtin diagnostic
---
--- Highlight lines with matches of current diagnostic items. Items are computed
--- with |vim.diagnostic.get()| for current (source) buffer.
---
--- It prompts integration highlighting update on every |DiagnosticChanged| event.
--- Diagnostic items with higher severity (see |vim.diagnostic.severity|) have
--- higher highlight priority (errors will be shown over all others, etc.).
---
---@param hl_groups table|nil Table defining highlight groups. Supplied fields
---   also define which diagnostic severity to highlight.
---   Can have the following fields:
---   - <error> - highlight group for error items.
---     Default: |hl-DiagnosticFloatingError|.
---   - <warn> - highlight group for warning items. Default: `nil` (not shown).
---   - <info> - highlight group for info items. Default: `nil` (not shown).
---   - <hint> - highlight group for hint items. Default: `nil` (not shown).
---
---@usage >lua
---   -- Show all diagnostic levels
---   local map = require('mini.map')
---   local diagnostic_integration = map.gen_integration.diagnostic({
---     error = 'DiagnosticFloatingError',
---     warn  = 'DiagnosticFloatingWarn',
---     info  = 'DiagnosticFloatingInfo',
---     hint  = 'DiagnosticFloatingHint',
---   })
---   map.setup({ integrations = { diagnostic_integration } })
--- <
MiniMap.gen_integration.diagnostic = function(hl_groups)
  if hl_groups == nil then hl_groups = { error = 'DiagnosticFloatingError' } end

  -- Precompute ordered array of supported levels. Using keys of
  -- `severity_highlights` is not enough because higher severity should be
  -- processed later in order to appear on top.
  local severity_level_names = vim.tbl_filter(
    function(x) return vim.tbl_contains(vim.tbl_keys(hl_groups), x) end,
    { 'error', 'warn', 'info', 'hint' }
  )
  local severity_data = vim.tbl_map(
    function(x) return { severity = vim.diagnostic.severity[x:upper()], hl_group = hl_groups[x] } end,
    severity_level_names
  )

  -- Refresh map when needed
  local augroup = vim.api.nvim_create_augroup('MiniMapDiagnostics', {})
  vim.api.nvim_create_autocmd(
    'DiagnosticChanged',
    { group = augroup, callback = H.on_integration_update, desc = 'On DiagnosticChanged' }
  )

  return function()
    local line_hl = {}
    local diagnostic_arr = vim.diagnostic.get(MiniMap.current.buf_data.source)
    for _, data in ipairs(severity_data) do
      local severity_diagnostic_arr = vim.tbl_filter(function(x) return x.severity == data.severity end, diagnostic_arr)
      for _, diag in ipairs(severity_diagnostic_arr) do
        -- Add all diagnostic lines to highlight
        for i = diag.lnum, diag.end_lnum do
          table.insert(line_hl, { line = i + 1, hl_group = data.hl_group })
        end
      end
    end

    return line_hl
  end
end

--- General diff hunks from |mini.diff|
---
--- Highlight lines which are part of current diff.
--- Requires 'mini.diff' as dependency.
---
---@param hl_groups table|nil Table defining highlight groups. If `nil` (not
---   supplied), this status is not highlighted. Can have the following fields:
---   - <add> - group name for "add" hunks. Default: "MiniDiffSignAdd".
---   - <change> - group name for "change" hunks. Default: "MiniDiffSignChange".
---   - <delete> - group name for "delete" hunks. Default: "MiniDiffSignDelete".
MiniMap.gen_integration.diff = function(hl_groups)
  if hl_groups == nil then
    hl_groups = { add = 'MiniDiffSignAdd', change = 'MiniDiffSignChange', delete = 'MiniDiffSignDelete' }
  end

  local augroup = vim.api.nvim_create_augroup('MiniMapDiff', {})
  vim.api.nvim_create_autocmd(
    'User',
    { group = augroup, pattern = 'MiniDiffUpdated', callback = H.on_integration_update, desc = 'On MiniDiffUpdated' }
  )

  return function()
    local has_diff, diff = pcall(require, 'mini.diff')
    if not has_diff or diff == nil then return {} end

    local has_buf_data, buf_data = pcall(diff.get_buf_data, MiniMap.current.buf_data.source)
    if not has_buf_data or buf_data == nil then return {} end

    return H.hunks_to_line_hl(buf_data.hunks, hl_groups)
  end
end

--- Hunks from 'lewis6991/gitsigns.nvim'
---
--- Highlight lines which have non-trivial Git status.
--- Requires [lewis6991/gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim).
---
---@param hl_groups table|nil Table defining highlight groups. If `nil` (not
---   supplied), this status is not highlighted. Can have the following fields:
---   - <add> - group name for added lines. Default: "GitSignsAdd".
---   - <change> - group name for changed lines. Default: "GitSignsChange".
---   - <delete> - group name for deleted lines. Default: "GitSignsDelete".
MiniMap.gen_integration.gitsigns = function(hl_groups)
  if hl_groups == nil then hl_groups = { add = 'GitSignsAdd', change = 'GitSignsChange', delete = 'GitSignsDelete' } end

  local augroup = vim.api.nvim_create_augroup('MiniMapGitsigns', {})
  vim.api.nvim_create_autocmd(
    'User',
    { group = augroup, pattern = 'GitSignsUpdate', callback = H.on_integration_update, desc = 'On GitSignsUpdate' }
  )

  return function()
    local has_gitsigns, gitsigns = pcall(require, 'gitsigns')
    if not has_gitsigns or gitsigns == nil then return {} end

    local has_hunks, hunks = pcall(gitsigns.get_hunks, MiniMap.current.buf_data.source)
    if not has_hunks or hunks == nil then return {} end

    local diff_hunks = {}
    for _, h in ipairs(hunks) do
      --stylua: ignore
      table.insert( diff_hunks, {
        type = h.type,
        buf_start = h.added.start,   buf_count = h.added.count,
        ref_start = h.removed.start, ref_count = h.removed.count,
      })
    end

    return H.hunks_to_line_hl(diff_hunks, hl_groups)
  end
end

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniMap.config)

-- Cache for various operations
H.cache = {
  -- Data about previous window. Used for focus related computations.
  previous_win = {},

  -- Table with information used for latest buffer lines encoding. Used for
  -- quick conversion between source and map coordinates.
  encode_data = {},

  -- Table with information about scrollbar. Used for quick scrollbar related
  -- computations.
  scrollbar_data = { view = {}, line = nil },

  -- Number of cursor movements inside map buffer since focusing. Needed to not
  -- update source buffer view just after focusing.
  n_map_cursor_moves = 0,
}

H.ns_id = {
  integrations = vim.api.nvim_create_namespace('MiniMapIntegrations'),
  scroll_view = vim.api.nvim_create_namespace('MiniMapScrollView'),
  scroll_line = vim.api.nvim_create_namespace('MiniMapScrollLine'),
}

--stylua: ignore start
H.block_symbols = {}

H.block_symbols['1x2'] = { ' ', '▌', '▐', '█', resolution = { row = 1, col = 2 } }

H.block_symbols['2x1'] = { ' ', '▀', '▄', '█', resolution = { row = 2, col = 1 } }

H.block_symbols['2x2'] = {
  ' ', '▘', '▝', '▀', '▖', '▌', '▞', '▛', '▗', '▚', '▐', '▜', '▄', '▙', '▟', '█',
  resolution = { row = 2, col = 2 },
}

H.block_symbols['3x2'] = {
  ' ', '🬀', '🬁', '🬂', '🬃', '🬄', '🬅', '🬆', '🬇', '🬈', '🬉', '🬊', '🬋', '🬌', '🬍', '🬎',
  '🬏', '🬐', '🬑', '🬒', '🬓', '▌', '🬔', '🬕', '🬖', '🬗', '🬘', '🬙', '🬚', '🬛', '🬜', '🬝',
  '🬞', '🬟', '🬠', '🬡', '🬢', '🬣', '🬤', '🬥', '🬦', '🬧', '▐', '🬨', '🬩', '🬪', '🬫', '🬬',
  '🬭', '🬮', '🬯', '🬰', '🬱', '🬲', '🬳', '🬴', '🬵', '🬶', '🬷', '🬸', '🬹', '🬺', '🬻', '█',
  resolution = { row = 3, col = 2 },
}

H.dot_symbols = {}

H.dot_symbols['4x2'] = {
  '⠀', '⠁', '⠈', '⠉', '⠂', '⠃', '⠊', '⠋', '⠐', '⠑', '⠘', '⠙', '⠒', '⠓', '⠚', '⠛',
  '⠄', '⠅', '⠌', '⠍', '⠆', '⠇', '⠎', '⠏', '⠔', '⠕', '⠜', '⠝', '⠖', '⠗', '⠞', '⠟',
  '⠠', '⠡', '⠨', '⠩', '⠢', '⠣', '⠪', '⠫', '⠰', '⠱', '⠸', '⠹', '⠲', '⠳', '⠺', '⠻',
  '⠤', '⠥', '⠬', '⠭', '⠦', '⠧', '⠮', '⠯', '⠴', '⠵', '⠼', '⠽', '⠶', '⠷', '⠾', '⠿',
  '⡀', '⡁', '⡈', '⡉', '⡂', '⡃', '⡊', '⡋', '⡐', '⡑', '⡘', '⡙', '⡒', '⡓', '⡚', '⡛',
  '⡄', '⡅', '⡌', '⡍', '⡆', '⡇', '⡎', '⡏', '⡔', '⡕', '⡜', '⡝', '⡖', '⡗', '⡞', '⡟',
  '⡠', '⡡', '⡨', '⡩', '⡢', '⡣', '⡪', '⡫', '⡰', '⡱', '⡸', '⡹', '⡲', '⡳', '⡺', '⡻',
  '⡤', '⡥', '⡬', '⡭', '⡦', '⡧', '⡮', '⡯', '⡴', '⡵', '⡼', '⡽', '⡶', '⡷', '⡾', '⡿',
  '⢀', '⢁', '⢈', '⢉', '⢂', '⢃', '⢊', '⢋', '⢐', '⢑', '⢘', '⢙', '⢒', '⢓', '⢚', '⢛',
  '⢄', '⢅', '⢌', '⢍', '⢆', '⢇', '⢎', '⢏', '⢔', '⢕', '⢜', '⢝', '⢖', '⢗', '⢞', '⢟',
  '⢠', '⢡', '⢨', '⢩', '⢢', '⢣', '⢪', '⢫', '⢰', '⢱', '⢸', '⢹', '⢲', '⢳', '⢺', '⢻',
  '⢤', '⢥', '⢬', '⢭', '⢦', '⢧', '⢮', '⢯', '⢴', '⢵', '⢼', '⢽', '⢶', '⢷', '⢾', '⢿',
  '⣀', '⣁', '⣈', '⣉', '⣂', '⣃', '⣊', '⣋', '⣐', '⣑', '⣘', '⣙', '⣒', '⣓', '⣚', '⣛',
  '⣄', '⣅', '⣌', '⣍', '⣆', '⣇', '⣎', '⣏', '⣔', '⣕', '⣜', '⣝', '⣖', '⣗', '⣞', '⣟',
  '⣠', '⣡', '⣨', '⣩', '⣢', '⣣', '⣪', '⣫', '⣰', '⣱', '⣸', '⣹', '⣲', '⣳', '⣺', '⣻',
  '⣤', '⣥', '⣬', '⣭', '⣦', '⣧', '⣮', '⣯', '⣴', '⣵', '⣼', '⣽', '⣶', '⣷', '⣾', '⣿',
  resolution = { row = 4, col = 2 },
}

H.dot_symbols['3x2'] = { resolution = { row = 3, col = 2 } }
for i = 1,64 do H.dot_symbols['3x2'][i] = H.dot_symbols['4x2'][i] end

H.shade_symbols = {}

H.shade_symbols['2x1'] = { '░', '▒', '▒', '▓', resolution = { row = 2, col = 1 } }

H.shade_symbols['1x2'] = { '░', '▒', '▒', '▓', resolution = { row = 1, col = 2 } }

H.default_symbols = H.block_symbols['3x2']
--stylua: ignore end

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  local ok_integrations, msg_integrations = H.is_valid_config_integrations(config.integrations, 'integrations')
  if not ok_integrations then H.error(msg_integrations) end

  local ok_symbols, msg_symbols = H.is_valid_config_symbols(config.symbols, 'symbols')
  if not ok_symbols then H.error(msg_symbols) end

  local ok_window, msg_window = H.is_valid_config_window(config.window, 'window')
  if not ok_window then H.error(msg_window) end

  return config
end

H.apply_config = function(config) MiniMap.config = config end

H.create_autocommands = function()
  local gr = vim.api.nvim_create_augroup('MiniMap', {})

  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = gr, pattern = pattern, callback = callback, desc = desc })
  end

  au({ 'BufEnter', 'BufWritePost', 'TextChanged', 'VimResized' }, '*', H.on_content_change, 'On content change')
  au({ 'CursorMoved', 'WinScrolled' }, '*', H.on_view_change, 'On view change')
  au('WinLeave', '*', H.on_winleave, 'On WinLeave')
  au('WinClosed', '*', H.on_winclosed, 'On WinClosed')
  au('ModeChanged', '*:n', H.on_content_change, 'On return to Normal mode')
  au('ColorScheme', '*', H.create_default_hl, 'Ensure colors')
end

--stylua: ignore
H.create_default_hl = function()
  local set_default_hl = function(name, data)
    data.default = true
    vim.api.nvim_set_hl(0, name, data)
  end

  set_default_hl('MiniMapNormal',      { link = 'NormalFloat' })
  set_default_hl('MiniMapSymbolCount', { link = 'Special' })
  set_default_hl('MiniMapSymbolLine',  { link = 'Title' })
  set_default_hl('MiniMapSymbolView',  { link = 'Delimiter' })
end

H.is_disabled = function() return vim.g.minimap_disable == true or vim.b.minimap_disable == true end

H.get_config = function(config)
  return vim.tbl_deep_extend('force', MiniMap.config, vim.b.minimap_config or {}, config or {})
end

-- Autocommands ---------------------------------------------------------------
H.on_content_change = vim.schedule_wrap(function()
  -- Using `vim.schedule_wrap()` helps computing more precise buffer data.
  -- Example: if omitted, terminal buffer is recognized as normal and thus map
  -- is updated.
  if not H.is_proper_buftype() then return end
  MiniMap.refresh()
end)

H.on_view_change = vim.schedule_wrap(function()
  if not (H.is_proper_buftype() and H.is_source_buffer()) then return end
  MiniMap.refresh({}, { integrations = false, lines = false })
end)

H.on_integration_update = vim.schedule_wrap(function()
  if not (H.is_proper_buftype() and H.is_source_buffer()) then return end
  MiniMap.refresh({}, { lines = false, scrollbar = false })
end)

H.on_winleave = function()
  if not (H.is_proper_buftype() and H.is_source_buffer()) then return end

  H.cache.previous_win.id = vim.api.nvim_get_current_win()
  H.cache.previous_win.cursor = vim.api.nvim_win_get_cursor(0)
end

H.on_winclosed = function(data)
  -- Ensure that `H.cache.previous_win` always points to a valid normal window
  local ok, closed_win_id = pcall(tonumber, data.match)
  if not ok or closed_win_id ~= H.cache.previous_win.id then return end

  for _, win_id in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if win_id ~= closed_win_id and vim.api.nvim_win_get_config(win_id).relative == '' then
      H.cache.previous_win = { id = win_id }
      return
    end
  end
end

H.track_map_cursor = function()
  -- Operate only inside map window but not just after focusing
  H.cache.n_map_cursor_moves = H.cache.n_map_cursor_moves + 1
  local cur_win, map_win = vim.api.nvim_get_current_win(), H.get_current_map_win()
  if cur_win ~= map_win or H.cache.n_map_cursor_moves <= 1 then return end

  -- Don't allow putting cursor inside offset (where scrollbar is)
  local cur_pos = vim.api.nvim_win_get_cursor(map_win)
  if cur_pos[2] < H.cache.scrollbar_data.offset then
    vim.api.nvim_win_set_cursor(map_win, { cur_pos[1], H.cache.scrollbar_data.offset })
  end

  -- Synchronize cursors in map and previous window
  local prev_win_id = H.cache.previous_win.id
  if prev_win_id == nil then return end

  vim.api.nvim_win_set_cursor(prev_win_id, { H.mapline_to_sourceline(cur_pos[1]), 0 })

  -- Open just enough folds and center cursor
  vim.api.nvim_win_call(prev_win_id, function() vim.cmd('normal! zvzz') end)
end

H.on_map_enter = function()
  -- Check if anything is present (window can be not opened because there is
  -- one buffer, but many possible windows; so this can be executed on second
  -- `MiniMap.open()` without opened window)
  if not H.is_window_open() or H.cache.previous_win.cursor == nil then return end

  -- Put cursor in map window at line indicator to the right of scrollbar
  local map_line = H.sourceline_to_mapline(H.cache.previous_win.cursor[1])
  local win_id = H.get_current_map_win()

  vim.api.nvim_win_set_cursor(win_id, { map_line, H.cache.scrollbar_data.offset })

  -- Reset number of cursor moves to later check if should track cursor move
  H.cache.n_map_cursor_moves = 0
end

-- Work with mask -------------------------------------------------------------
---@param strings table Array of strings
---@return table Non-whitespace mask, boolean 2d array. Each row corresponds to
---   string, each column - to whether character with that number is a
---   non-whitespace. Respects multibyte characters.
---@private
H.mask_from_strings = function(strings, _)
  local tab_space = string.rep(' ', vim.o.tabstop)

  local res = {}
  for i, s in ipairs(strings) do
    -- Expand tabs into spaces
    local s_ext = s:gsub('\t', tab_space)
    local n_cols = H.str_width(s_ext)
    local mask_row = H.tbl_repeat(true, n_cols)

    -- Detect whitespace
    s_ext:gsub('()%s', function(j) mask_row[H.str_utfindex(s_ext, j)] = false end)
    res[i] = mask_row
  end

  return res
end

---@param mask table Boolean 2d array.
---@return table Boolean 2d array rescaled to be shown by symbols:
---   `opts.n_rows` lines and `opts.n_cols` within a row.
---@private
H.mask_rescale = function(mask, opts)
  -- Infer output number of rows and columns. Should be multiples of
  -- `symbols.resolution.row` and `symbols.resolution.col` respectively.
  local source_rows = #mask
  local source_cols = 0
  for _, m_row in ipairs(mask) do
    source_cols = math.max(source_cols, #m_row)
  end

  -- Compute effective number of rows and columns in output such that it can
  -- contain all encoded symbols (taking into account their resolution).
  -- Don't make it a multiple of resolution at this stage because it can later
  -- lead to inaccurate representation in some cases. Like with small source
  -- number of rows it will lead to conversion coefficients greater than 1
  -- (because `math.ceil()` should be used to round for resolution) and some
  -- rows in the middle of output will be skipped.
  local resolution = opts.symbols.resolution
  local n_rows = math.min(source_rows, opts.n_rows * resolution.row)
  local n_cols = math.min(source_cols, opts.n_cols * resolution.col)

  -- Rescale. It uses unequal but optimal bins to map source lines/columns to
  -- boolean encoding (has target dimensions but multiplied by resolution).
  -- Value within 2d-bin is `true` if at least one value within it is `true`.
  local res = {}
  for i = 1, n_rows do
    res[i] = H.tbl_repeat(false, n_cols)
  end

  local rows_coeff, cols_coeff = n_rows / source_rows, n_cols / source_cols

  for i, m_row in ipairs(mask) do
    for j, m in ipairs(m_row) do
      local res_i = math.floor((i - 1) * rows_coeff) + 1
      local res_j = math.floor((j - 1) * cols_coeff) + 1
      res[res_i][res_j] = m or res[res_i][res_j]
    end
  end

  return res
end

--- Convert extended map mask to strings. Each bin with resolution dimensions
--- is transformed into encode symbol. Single convertible `(resolution.row,
--- resolution.col)` boolean mask is treated as binary digit: `true` as 1;
--- `false` as 0; traversing left-right, top-bottom (top-left is lowest bit,
--- bottom-right - highest).
---
---@param mask table Boolean 2d array to be shown as symbols.
---@return table Array of strings representing input `mask`.
---@private
H.mask_to_symbols = function(mask, opts)
  local symbols = opts.symbols
  local row_resol, col_resol = symbols.resolution.row, symbols.resolution.col

  local powers_of_two = {}
  for i = 0, (row_resol * col_resol - 1) do
    powers_of_two[i] = 2 ^ i
  end

  -- Assumes rectangular table
  local symbols_n_rows, symbols_n_cols = math.ceil(#mask / row_resol), math.ceil(#mask[1] / col_resol)

  -- Compute symbols array indexes (start from zero)
  local symbol_ind = {}
  for i = 1, symbols_n_rows do
    symbol_ind[i] = H.tbl_repeat(0, symbols_n_cols)
  end

  for i = 0, #mask - 1 do
    local row = mask[i + 1]
    local row_div, row_mod = math.floor(i / row_resol), i % row_resol
    for j = 0, #row - 1 do
      local col_div, col_mod = math.floor(j / col_resol), j % col_resol

      local two_power = row_mod * col_resol + col_mod
      local to_add = row[j + 1] and powers_of_two[two_power] or 0

      local sym_i, sym_j = row_div + 1, col_div + 1
      symbol_ind[sym_i][sym_j] = symbol_ind[sym_i][sym_j] + to_add
    end
  end

  -- Construct symbols strings
  local res = {}
  for i, row in ipairs(symbol_ind) do
    local syms = vim.tbl_map(function(id) return symbols[id + 1] end, row)
    res[i] = table.concat(syms)
  end

  return res
end

-- Work with config -----------------------------------------------------------
H.normalize_opts = function(x)
  x = vim.tbl_deep_extend('force', H.get_config(), MiniMap.current.opts or {}, x or {})
  H.validate_if(H.is_valid_opts, x, 'opts')
  return x
end

H.is_valid_opts = function(x, x_name)
  x_name = x_name or 'opts'

  local ok_integrations, msg_integrations = H.is_valid_config_integrations(x.integrations, x_name .. '.integrations')
  if not ok_integrations then return ok_integrations, msg_integrations end

  local ok_symbols, msg_symbols = H.is_valid_config_symbols(x.symbols, x_name .. '.symbols')
  if not ok_symbols then return ok_symbols, msg_symbols end

  local ok_window, msg_window = H.is_valid_config_window(x.window, x_name .. '.window')
  if not ok_window then return ok_window, msg_window end

  return true
end

H.is_valid_config_integrations = function(x, x_name)
  x_name = x_name or 'config.integrations'

  if x ~= nil then
    if not H.is_array_of(x, vim.is_callable) then return false, H.msg_config(x_name, 'array of callables') end
  end

  return true
end

H.is_valid_config_symbols = function(x, x_name)
  x_name = x_name or 'config.symbols'

  if type(x) ~= 'table' then return false, H.msg_config(x_name, 'table') end

  -- Encode symbols is `nil` by default
  if x.encode ~= nil then
    local ok_encode, msg_encode = H.is_encode_symbols(x.encode, x_name .. '.encode')
    if not ok_encode then return ok_encode, msg_encode end
  end

  -- Current line
  if not H.is_string(x.scroll_line) then return false, H.msg_config(x_name .. '.scroll_line', 'string') end

  -- Current view
  if not H.is_string(x.scroll_view) then return false, H.msg_config(x_name .. '.scroll_view', 'string') end

  return true
end

H.is_valid_config_window = function(x, x_name)
  x_name = x_name or 'config.window'

  if type(x) ~= 'table' then return false, H.msg_config(x_name, 'table') end

  -- Focusable
  if type(x.focusable) ~= 'boolean' then return false, H.msg_config(x_name .. '.focusable', 'boolean') end

  -- Side
  if not (x.side == 'left' or x.side == 'right') then
    return false, H.msg_config(x_name .. '.side', [[one of 'left', 'right']])
  end

  -- Width
  if not (type(x.width) == 'number' and x.width > 0) then
    return false, H.msg_config(x_name .. '.width', 'positive number')
  end

  -- Show "more" integration symbols
  if type(x.show_integration_count) ~= 'boolean' then
    return false, H.msg_config(x_name .. '.show_integration_count', 'boolean')
  end

  -- Window local 'winblend'
  if not (type(x.winblend) == 'number' and 0 <= x.winblend and x.winblend <= 100) then
    return false, H.msg_config(x_name .. '.winblend', 'number between 0 and 100')
  end

  -- Z-index
  if not (type(x.zindex) == 'number' and x.zindex > 0) then
    return false, H.msg_config(x_name .. '.zindex', 'positive number')
  end

  return true
end

H.msg_config = function(x_name, msg) return string.format('`%s` should be %s.', x_name, msg) end

-- Work with map window -------------------------------------------------------
H.normalize_window_options = function(win_opts, full)
  if full == nil then full = true end

  local has_tabline = vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1)
  local has_statusline = vim.o.laststatus > 0
  local anchor, col = 'NE', vim.o.columns
  if win_opts.side == 'left' then
    anchor, col = 'NW', 0
  end

  local res = {
    relative = 'editor',
    anchor = anchor,
    row = has_tabline and 1 or 0,
    col = col,
    width = win_opts.width,
    -- Can be updated at `VimResized` event
    height = vim.o.lines - vim.o.cmdheight - (has_tabline and 1 or 0) - (has_statusline and 1 or 0),
    focusable = win_opts.focusable,
    border = 'none',
    zindex = win_opts.zindex,
  }
  if not full then return res end

  res.style = 'minimal'
  return res
end

H.get_current_map_win = function() return MiniMap.current.win_data[vim.api.nvim_get_current_tabpage()] end

H.set_current_map_win = function(win_id) MiniMap.current.win_data[vim.api.nvim_get_current_tabpage()] = win_id end

H.is_window_open = function()
  local cur_win_id = H.get_current_map_win()
  return cur_win_id ~= nil and vim.api.nvim_win_is_valid(cur_win_id)
end

-- Work with map updates ------------------------------------------------------
H.create_map_buffer = function()
  local buf_id = vim.api.nvim_create_buf(false, true)
  H.set_buf_name(buf_id, 'content')

  -- Set buffer local options (which don't involve `noautocmd`)
  vim.bo[buf_id].filetype = 'minimap'

  -- Make buffer local mappings
  vim.keymap.set('n', '<CR>', '<Cmd>lua MiniMap.toggle_focus(false)<CR>', { buffer = buf_id })
  vim.keymap.set('n', '<Esc>', '<Cmd>lua MiniMap.toggle_focus(true)<CR>', { buffer = buf_id })

  -- Make buffer local autocommands
  vim.api.nvim_create_autocmd('BufEnter', { buffer = buf_id, callback = H.on_map_enter, desc = 'On map enter' })
  vim.api.nvim_create_autocmd(
    'CursorMoved',
    { buffer = buf_id, callback = H.track_map_cursor, desc = 'Track map cursor' }
  )

  -- Make buffer play nicely with other 'mini.nvim' modules
  vim.api.nvim_buf_set_var(buf_id, 'minicursorword_disable', true)

  return buf_id
end

H.update_window_opts = function()
  local opts = MiniMap.current.opts
  local win_id = H.get_current_map_win()

  -- Window config
  vim.api.nvim_win_set_config(win_id, H.normalize_window_options(opts.window, false))

  -- 'winblend'
  vim.wo[win_id].winblend = opts.window.winblend
end

H.update_map_lines = function()
  if not H.is_window_open() then return end

  local buf_id, opts = MiniMap.current.buf_data.map, MiniMap.current.opts
  local win_id = H.get_current_map_win()

  -- Compute output number of rows and columns to fit currently shown window
  local offset = H.cache.scrollbar_data.offset
  local n_cols = vim.api.nvim_win_get_width(win_id) - offset
  local n_rows = vim.api.nvim_win_get_height(win_id)

  -- Encode lines from current buffer
  local source_buf_id = vim.api.nvim_get_current_buf()
  MiniMap.current.buf_data.source = source_buf_id
  local buf_lines = vim.api.nvim_buf_get_lines(source_buf_id, 0, -1, true)
  -- Ensure that current buffer has lines (can be not the case when this is
  -- executed asynchronously during Neovim closing)
  if #buf_lines == 0 then return end

  local encode_symbols = opts.symbols.encode or H.default_symbols
  local source_rows, scrollbar_prefix = #buf_lines, string.rep(' ', offset)
  local encoded_lines, rescaled_rows, resolution_row
  if n_cols <= 0 then
    -- Case of "only scroll indicator". Needed to make scrollbar correctly
    -- travel from buffer top to bottom.
    encoded_lines = H.tbl_repeat(scrollbar_prefix, n_rows)

    -- Note that full encoding was done with single whitespace per line
    rescaled_rows, resolution_row = n_rows, 1
  else
    -- Case of "full map"
    local encode_opts = { n_cols = n_cols, n_rows = n_rows, symbols = encode_symbols }
    encoded_lines = MiniMap.encode_strings(buf_lines, encode_opts)

    -- Add whitespace for scrollbar
    encoded_lines = vim.tbl_map(function(x) return string.format('%s%s', scrollbar_prefix, x) end, encoded_lines)

    -- Note that actual encoding was done
    resolution_row = encode_symbols.resolution.row
    rescaled_rows = math.min(source_rows, n_rows * resolution_row)
  end

  -- Set map lines. Compute encode data in a way used in mask rescaling
  vim.api.nvim_buf_set_lines(buf_id, 0, -1, true, encoded_lines)

  -- Cache encode data to speed up most frequent scrollbar computation
  H.cache.encode_data = {
    source_rows = source_rows,
    rescaled_rows = rescaled_rows,
    resolution_row = resolution_row,
    map_rows = #encoded_lines,
  }

  -- Force scrollbar update
  H.cache.scrollbar_data.view, H.cache.scrollbar_data.line = {}, nil
end

H.update_map_scrollbar = function()
  if not H.is_window_open() then return end

  local buf_id = MiniMap.current.buf_data.map
  local cur_view, cur_line = H.cache.scrollbar_data.view or {}, H.cache.scrollbar_data.line
  local symbols = MiniMap.current.opts.symbols

  -- View
  local view = { from_line = vim.fn.line('w0'), to_line = vim.fn.line('w$') }
  if not (view.from_line == cur_view.from_line and view.to_line == cur_view.to_line) then
    local ns_id = H.ns_id.scroll_view
    local extmark_opts =
      { virt_text = { { symbols.scroll_view, 'MiniMapSymbolView' } }, virt_text_pos = 'overlay', priority = 10 }

    -- Remove previous view
    vim.api.nvim_buf_clear_namespace(buf_id, ns_id, 0, -1)

    -- Add current view
    local map_from_line = H.sourceline_to_mapline(view.from_line)
    local map_to_line = H.sourceline_to_mapline(view.to_line)

    for i = map_from_line, map_to_line do
      H.set_extmark_safely(buf_id, ns_id, i - 1, 0, extmark_opts)
    end

    H.cache.scrollbar_data.view = view
  end

  -- Current line
  local scroll_line = vim.fn.line('.')
  if scroll_line ~= cur_line then
    local ns_id = H.ns_id.scroll_line
    -- Set higher priority than view signs to be visible over them
    local extmark_opts =
      { virt_text = { { symbols.scroll_line, 'MiniMapSymbolLine' } }, virt_text_pos = 'overlay', priority = 11 }

    -- Remove previous line
    vim.api.nvim_buf_clear_namespace(buf_id, ns_id, 0, -1)

    -- Add new line
    local map_line = H.sourceline_to_mapline(scroll_line)

    H.set_extmark_safely(buf_id, ns_id, map_line - 1, 0, extmark_opts)
    H.cache.scrollbar_data.line = scroll_line
  end
end

H.update_map_integrations = function()
  if not H.is_window_open() then return end

  local buf_id = MiniMap.current.buf_data.map
  local integrations = MiniMap.current.opts.integrations or {}

  -- Remove previous highlights and signs
  local ns_id = H.ns_id.integrations
  vim.api.nvim_buf_clear_namespace(buf_id, ns_id, 0, -1)

  -- Do nothing more in case of pure scrollbar
  -- This is after removing "more" signs to allow switching to pure scrollbar
  -- after such were already visible
  if H.is_pure_scrollbar() then return end

  -- Add line highlights. Use latest one for every map line.
  local line_counts = {}
  for _, integration in ipairs(integrations) do
    local line_hl = integration()
    for _, lh in ipairs(line_hl) do
      local map_line = H.sourceline_to_mapline(lh.line)
      local cur_count = line_counts[map_line] or 0
      line_counts[map_line] = cur_count + 1

      -- Actually highlight only first map line occurrence
      if cur_count == 0 then H.add_line_hl(buf_id, ns_id, lh.hl_group, map_line - 1) end
    end
  end

  -- Possibly add integration counts
  if not MiniMap.current.opts.window.show_integration_count then return end

  local col = H.cache.scrollbar_data.offset - 1
  for l, count in pairs(line_counts) do
    if count > 1 then
      local text = count > 9 and '+' or tostring(count)
      local extmark_opts = {
        virt_text = { { text, 'MiniMapSymbolCount' } },
        virt_text_pos = 'overlay',
        hl_mode = 'blend',
      }
      H.set_extmark_safely(buf_id, ns_id, l - 1, col, extmark_opts)
    end
  end
end

H.sourceline_to_mapline = function(source_line)
  local data = H.cache.encode_data
  local coef = data.rescaled_rows / data.source_rows
  local rescaled_row = math.floor(coef * (source_line - 1)) + 1
  local res = math.floor((rescaled_row - 1) / data.resolution_row) + 1
  return math.min(math.max(res, 1), data.map_rows)
end

H.mapline_to_sourceline = function(map_line)
  local data = H.cache.encode_data
  local coef = data.rescaled_rows / data.source_rows
  local rescaled_row = (map_line - 1) * data.resolution_row + 1
  local res = math.ceil((rescaled_row - 1) / coef) + 1
  return math.min(math.max(res, 1), data.source_rows)
end

-- Hunks ----------------------------------------------------------------------
H.hunks_to_line_hl = function(hunks, hl_groups)
  local res = {}
  for _, h in ipairs(hunks) do
    local from_line = h.buf_start
    local n_added, n_removed = h.buf_count, h.ref_count
    local n_lines = math.max(n_added, 1)
    -- Highlight similar to hunk summary logic:
    -- - Delete - single first line if nothing was added.
    -- - Change - added lines that are within first removed lines.
    -- - Added - added lines after first removed lines.
    for i = 1, n_lines do
      local hl_type = (n_added < i and 'delete') or (i <= n_removed and 'change' or 'add')
      local hl_group = hl_groups[hl_type]
      if hl_group ~= nil then table.insert(res, { line = from_line + i - 1, hl_group = hl_group }) end
    end
  end

  return res
end

-- Predicates -----------------------------------------------------------------
H.is_array_of = function(x, predicate)
  if not H.islist(x) then return false end
  for _, v in ipairs(x) do
    if not predicate(v) then return false end
  end
  return true
end

H.is_string = function(x) return type(x) == 'string' end

H.is_encode_symbols = function(x, x_name)
  x_name = x_name or 'symbols'

  if type(x) ~= 'table' then return false, H.msg_config(x_name, 'table') end
  if type(x.resolution) ~= 'table' then return false, H.msg_config(x_name .. '.resolution', 'table') end
  if type(x.resolution.col) ~= 'number' then return false, H.msg_config(x_name .. '.resolution.col', 'number') end
  if type(x.resolution.row) ~= 'number' then return false, H.msg_config(x_name .. '.resolution.row', 'number') end

  local two_power = x.resolution.col * x.resolution.row
  for i = 1, 2 ^ two_power do
    if not H.is_string(x[i]) then return false, H.msg_config(string.format('%s[%d]', x_name, i), 'string') end
  end

  return true
end

H.is_proper_buftype = function()
  local buf_type = vim.bo.buftype
  return buf_type == '' or buf_type == 'help'
end

H.is_source_buffer = function() return vim.api.nvim_get_current_buf() == MiniMap.current.buf_data.source end

H.is_pure_scrollbar = function()
  local win_id = H.get_current_map_win()
  local offset = H.cache.scrollbar_data.offset
  return vim.api.nvim_win_get_width(win_id) <= offset
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.map) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.set_buf_name = function(buf_id, name) vim.api.nvim_buf_set_name(buf_id, 'minimap://' .. buf_id .. '/' .. name) end

H.validate_if = function(predicate, x, x_name)
  local is_valid, msg = predicate(x, x_name)
  if not is_valid then H.error(msg) end
end

H.add_line_hl = function(buf_id, ns_id, hl_group, line)
  H.set_extmark_safely(buf_id, ns_id, line, H.cache.scrollbar_data.offset, {
    hl_group = hl_group,
    end_row = line + 1,
    end_col = 0,
    strict = false,
  })
end

H.set_extmark_safely = function(...) pcall(vim.api.nvim_buf_set_extmark, ...) end

H.str_utfindex = function(s, i) return vim.str_utfindex(s, 'utf-32', i) end
if vim.fn.has('nvim-0.11') == 0 then H.str_utfindex = function(s, i) return (vim.str_utfindex(s, i)) end end

H.str_width = function(x) return H.str_utfindex(x) end

H.tbl_repeat = function(x, n)
  local res = {}
  for _ = 1, n do
    table.insert(res, x)
  end
  return res
end

-- TODO: Remove after compatibility with Neovim=0.9 is dropped
H.islist = vim.fn.has('nvim-0.10') == 1 and vim.islist or vim.tbl_islist

return MiniMap
