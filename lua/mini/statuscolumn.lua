--- *mini.statuscolumn* Statuscolumn
---
--- MIT License Copyright (c) 2026 Evgeni Chasnovski

--- Features:
---
--- - Fast |'statuscolumn'| with improved defaults.
--- - Fully customizable content via functions that take precomputed useful data.
--- - |MiniStatuscolumn.gen_content.main()| for simplified customization.
--- - Automatic dimming inside inactive windows content.
---
--- Notes:
--- - Works best on Neovim>=0.11.
--- - Default content follows the behavior defined by options for the built-in
---   statuscolumn sections. Like |'number'|, |'signcolumn'|, |'foldcolumn'|, etc.
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.statuscolumn').setup({})`
--- (replace `{}` with your `config` table). It will create global Lua table
--- `MiniStatuscolumn` which you can use for scripting or manually (with
--- `:lua MiniStatuscolumn.*`).
---
--- See |MiniStatuscolumn.config| for `config` structure and default values.
---
--- # Suggested option values ~
---
--- - Default content works best with enabled |'number'| and |'signcolumn'|.
---
--- - Depending on how distinctive |hl-FoldColumn| is from |hl-LineNr|, it might
---   be a good idea to use minimal fold column characters in |'fillchars'|.
---   Like `foldopen:🯘` and `foldclose:🮥`, while `foldsep` and `foldinner` (on
---   Neovim>=0.12) set to a single space.
---
--- # Comparisons ~
---
--- - [luukvball/statuscol.nvim](https://github.com/luukvbaal/statuscol.nvim):
---     - A framework with building blocks and configuration: custom sections,
---       sign filters, fold functions.
---       While this module aims to provide a performant |'statuscolumn'| with
---       a sensible default with a limited (yet enough) customization and an
---       entry point to building own |'statuscolumn'|.
---
--- - [folke/snacks.nvim#statuscolumn](https://github.com/folke/snacks.nvim):
---     - An opinionated |'statuscolumn'| implementation with a limited
---       customization.
---       While this module provides more opportunities for building custom
---       implementation and more customization.
---
--- # Highlight groups ~
--- *MiniStatuscolumn-hl-groups*
---
--- - `MiniStatuscolumnDim` - dimmed column. By default is a dimmed |hl-LineNr|.
--- - `MiniStatuscolumnDimCursor` - dimmed column at cursor line.
--- - `MiniStatuscolumnSep` - separator of column and text.
--- - `MiniStatuscolumnSepCursor` - separator of column and text at cursor line.
---@tag MiniStatuscolumn

---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local

local MiniStatuscolumn = {}
local H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniStatuscolumn.config|.
---
---@usage >lua
---   require('mini.statuscolumn').setup() -- use default config
---   -- OR
---   require('mini.statuscolumn').setup({}) -- replace {} with your config table
--- <
MiniStatuscolumn.setup = function(config)
  -- Export module
  _G.MiniStatuscolumn = MiniStatuscolumn

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Define behavior
  H.create_autocommands(config)

  -- Create default highlighting
  H.create_default_hl()
end

--- Defaults ~
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text # Content ~
---
--- `config.content` is a table that defines |'statuscolumn'| content for active
--- (`content.active`) and inactive (`content.inactive`) windows. Each content is
--- a function that takes a single `data` argument with useful info about the
--- current Neovim state (precomputed only when needed to improve performance) and
--- should return a |'statusline'| like string.
---
--- An input `data` argument is a table with the following fields:
--- - <buf_id> `(number)` - identifier of a drawn buffer.
--- - <is_cursorlinenr> `(boolean)` - whether |hl-CursorLineNr| conditions are met.
--- - <is_foldcolumn_fixed> `(boolean)` - whether |'foldcolumn'| has fixed width.
--- - <is_signcolumn_fixed> `(boolean)` - whether |'signcolumn'| has fixed width.
--- - <is_statuscolumn_empty> `(boolean)` - whether |'statuscolumn'| default content
---   is empty. Useful to determine if anything should be drawn.
--- - <opt_cursorline> `(boolean)` - current value of |'cursorline'|.
--- - <opt_cursorlineopt> `(string)` - current value of |'cursorlineopt'|.
--- - <opt_foldcolumn> `(string)` - current value of |'foldcolumn'|.
--- - <opt_number> `(boolean)` - current value of |'number'|.
--- - <opt_relativenumber> `(boolean)` - current value of |'relativenumber'|.
--- - <opt_signcolumn> `(string)` - current value of |'signcolumn'|.
--- - <win_id> `(number)` - identifier of a drawn window.
---
--- The data about target line (for which content is evaluated) can be accessed
--- as described in |'statuscolumn'| via the dedicated |v:| variables.
--- Like |v:lnum|, |v:relnum|, and |v:virtnum|.
---
--- Example custom content: >lua
---
---   -- Show sign and separator if statuscolumn is not empty
---   local active = function(data)
---     return data.is_statuscolumn_empty and '' or '%s│'
---   end
---   -- Show nothing in inactive windows
---   local inactive = function(_) return '' end
---   local content = { active = active, inactive = inactive }
---   require('mini.statuscolumn').setup({ content = content })
--- <
--- If one content function is missing, the other is used in its place.
--- If both content functions are missing, the default content is used: the output
--- of |MiniStatuscolumn.gen_content.main()| with the following specification: >lua
---
---   { fold = '%C', lnum = '%l', sign = '%s' }, -- Default sections
---   { format = '=lfs', sep = '▏' },  -- Line-fold-sign-separator format
---   { ltype = 'virt', lnum = '•' },  -- Dot in virtual lines
---   { ltype = 'wrap', lnum = '↳' },  -- Arrow in wrapped lines
---   { win = 'inactive', sep = ' ' }, -- No separator in inactive windows
--- <
--- Default content works best with enabled |'number'|, otherwise statuscolumn width
--- might fluctuate if there are wrapped or virtual lines due to special symbols.
---
--- Notes:
--- - Make sure that custom content functions are as fast as possible since they
---   will be called VERY frequently: at least every non-pure-cursor-move redraw
---   (during typing, window scroll, etc.) for every visible line in every visible
---   window. A rough estimate: about 100 times per redraw and about 1 million
---   times per hour of text editing.
--- - For performance reasons there are several |'statuscolumn'| optimizations
---   that affect any implementation. Like pre-computed width and when it changes.
---   Make sure to read |'statuscolumn'| to be aware of them.
---
--- # Dim inactive windows ~
---
--- `config.dim` is a boolean that defines whether to dim statuscolumn content
--- in inactive windows. It means that all |'statuscolumn'| relevant highlight
--- groups are overridden to be `MiniStatuscolumnDimCursor` at cursor line and
--- `MiniStatuscolumnDim` everywhere else. Default: `true`.
---
--- Default values of dimming highlight groups are computed as a dimmed variant
--- of |hl-LineNr| group, meaning its foreground is computed to be closer to its
--- background. The used approach is good enough, if not - define groups manually.
MiniStatuscolumn.config = {
  -- Statuscolumn content as functions that return statusline-like string
  content = {
    -- Content of an active window
    active = nil,
    -- Content of an inactive window
    inactive = nil,
  },

  -- Whether to dim column content in inactive windows
  dim_inactive = true,
}
--minidoc_afterlines_end

--- Content generators
---
--- This is a table with function elements. Call to actually get a content table.
MiniStatuscolumn.gen_content = {}

--- Main content generator
---
--- Generates a content that can be customized via selected "info" fields applied
--- at selected drawn line "coordinates".
---
--- "Info" string fields (as |'statusline'| like text):
--- - <fold> - fold section. Default: `'%C'`.
--- - <sign> - sign section. Default: `'%s'`.
--- - <lnum> - line number section. Default: `'%l'`.
--- - <sep> - separator between column and in-buffer text. Default: `' '`.
---   Highlighted with groups `MiniStatuscolumnSep` and `MiniStatuscolumnSepCursor`
---   The latter is used under the conditions described in |hl-CursorLineNr|.
--- - <format> - order of sections (excluding <sep>) as a string containing only
---   `f` (fold), `s` (sign), `l` (lnum), and `=` (as `%=` in |'statusline'| syntax).
---   Default: `'fs=l'`.
---
--- NOTE: using dedicated |'statusline'| syntax, as in default values, makes
--- section content follow their respective options. Like using `%l` will show
--- nothing if |'number'| is disabled.
---
--- "Coordinate" fields:
--- - <win> - type of drawn window. One of `'active'`, `'inactive'`.
--- - <pos> - position of drawn line relative to the cursor. One of `'cursor'`,
---   `'above'`, `'below'`. Note: value does not depend on the |'relativenumber'|,
---   unlike |hl-LineNrAbove| and |hl-LineNrBelow|.
--- - <ltype> - type of drawn line. One of `'text'` (next to the regular buffer
---   text), `'virt'` (next to the virtual line), `'wrap'` (next to the wrapped part
---   of buffer text).
---
--- Customization is done via an array specification that acts as a sequence of
--- rules applied on top of the previous ones. Each rule/item should define at
--- least one "info" field and may filter by one or more "coordinate" field.
--- It is recommended to start with wider rules and go towards narrower ones.
--- If an "info" field is not defined after all rules are processed, its
--- default value is used.
---
--- Each section is clickable with mouse. Clicks will be processed with an
--- `opts.click` function and can be customized per section-coordinate.
---
--- Examples of content specification:
---
--- - Specification for default `content` in |MiniStatuscolumn.config|.
---   Use as a template to adjust/remove added behavior: >lua
---
---   local statuscolumn = require('mini.statuscolumn')
---   local spec = {
---     -- Prefer visible separator with a more efficient order to use
---     -- usually present whitespace to the right of signs
---     { format = '=lfs', sep = '▏' },
---     -- Use custom symbol for virtual lines
---     { ltype = 'virt', lnum = '•' },
---     -- Use custom symbol for wrapped lines
---     { ltype = 'wrap', lnum = '↳' },
---     -- Hide separator to better indicate inactive windows
---     { win = 'inactive', sep = ' ' },
---   }
---   statuscolumn.setup({ content = statuscolumn.gen_content.main(spec) })
--- <
--- - Ways to configure separator:
---
---   - Thicker separator at cursor: `{ pos = 'cursor', sep = '▍' }`.
---
---   - More cell-centered separator: `{ format='=fsl', sep='│' }`
---
--- - Ways to indicate inactive windows:
---
---   - Hide regular non-cursor line: define `MiniStatuscolumnDim` highlight group
---     to have the same foreground and background. It will still show cursor line
---     and lines which have signs or line number with special highlighting (like
---     diagnostics, diff status, etc.).
---
---   - Show nothing: `{ win='inactive', fold='', lnum='', sign='' }`
---
---   - Hide separator: `{ win='inactive', sep='' }`
---
--- - Force highlighting: `{ pos='cursor', ltype='virt', lnum='%#CursorLineNr#•' }`.
---   Has problems that it overrides highlighting from extmarks.
---
--- Notes:
--- - Implementation of |'statuscolumn'| has some performance trade-offs when it
---   comes to computing which areas are clickable. Suggested usage:
---     - Use one <format> per window type, as section order is better to persist
---       across lines of the same window.
---     - Clicking the cell that contains text should work. Clicking an empty cell
---       of known section might not always work.
---     - On Neovim<0.13 the `ltype` is always the one that is used in the top
---       window line.
---
---@param spec table[]|nil Specification array. Default: `{}`, which imitates
---   default |'statuscolumn'|.
---@param opts table|nil Options. Possible fields:
---   - <click> `(function)` - action to perform on mouse click in statuscolumn.
---     Default: |MiniStatuscolumn.default_click()|.
---
---     Called with a single table `data` argument with the following fields:
---     - <button> `(string)` - mouse button, as described in `@` |'statusline'| flag.
---     - <modifiers> `(string)` - modifiers, as described in `@` |'statusline'| flag.
---     - <n_clicks> `(number)` - number of clicks.
---     - <ltype> `(string)` - line type "coordinate" field.
---     - <section> `(string)` - section name. One of `'fold'`, `'sign'`, `'lnum'`, `'sep'`.
---     - <mousepos> `(table)` - output of |getmousepos()|. Can be used to determine
---       line number, window identifier/type, etc.
---
---     Notes:
---    - On Neovim<0.13 it is only possible to split statuscolumn line into
---      "clicking ranges" once per window. This is why `data.ltype` might have
---      not correct values. Should work as expected on Neovim>=0.13.
---    - A best available (but somewhat limiting) pattern to identify what was
---      clicked is to use |screenstring()| with <screenrow> and <screencol>
---      fields of <mousepos>. For example, fixed distinctive symbols for wrapped
---      and virtual lines can help identifying that click was done on them.
MiniStatuscolumn.gen_content.main = function(spec, opts)
  spec = spec or {}
  H.validate_main_content_spec(spec)
  opts = vim.tbl_extend('force', { click = MiniStatuscolumn.default_click }, opts or {})
  H.check_type('opts.click', opts.click, 'function')

  -- Force redraw on cursor move (since 'statuscolumn' is not fully redrawn on
  -- pure cursor moves). Do only when necessary as doing on every move results
  -- into flickering (like with 'mini.cursorword' highlighting word twice)
  local _redraw, redraw_opts = vim.api.nvim__redraw, { win = 0, statuscolumn = true }
  local win_get_cursor = vim.api.nvim_win_get_cursor
  local buf_get_extmarks, extmarks_opts = vim.api.nvim_buf_get_extmarks, { limit = 1, type = 'virt_lines' }
  local redraw_lnum = 0
  -- - Force redraw with cursor next to the virtual line, otherwise manually
  --   added cursor sep highlighting will not be shown when cursor moves from
  --   above and will "stay" there when cursor moves above.
  local redraw_stc_on_cursor_move = function()
    local lnum = win_get_cursor(0)[1]
    -- Don't redraw when highlight is up to date: on horizontal movement and if
    -- not special cursor line specific highlight is needed
    if redraw_lnum == lnum or not vim.o.cursorline then return end
    -- Redraw after moving from the line with virtual lines to make sure that
    -- outdated cursorline-specific highlights are removed
    if redraw_lnum > 0 then _redraw(redraw_opts) end

    redraw_lnum = #buf_get_extmarks(0, -1, { lnum - 1, 0 }, { lnum - 1, -1 }, extmarks_opts) > 0 and lnum or 0
    -- Redraw immediately to make sure that cursorline-specific highlight
    -- is applied to virtual lines
    if redraw_lnum > 0 then _redraw(redraw_opts) end
  end
  local gr = vim.api.nvim_create_augroup('MiniStatuscolumnMain', {})
  local au_opts = { group = gr, callback = redraw_stc_on_cursor_move, desc = 'Ensure redraw' }
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, au_opts)

  -- Pre-compute content map to later choose one of its string value in the
  -- content function
  local content_map = H.make_main_content_map(spec, opts.click)
  local make = function(win)
    return function(win_data)
      if win_data.is_statuscolumn_empty then return '' end
      local pos = vim.v.relnum == 0 and 'cursor' or (vim.v.lnum < win_get_cursor(0)[1] and 'above' or 'below')
      local ltype = vim.v.virtnum == 0 and 'text' or (vim.v.virtnum < 0 and 'virt' or 'wrap')
      return content_map[win][pos][ltype].content[win_data.is_cursorlinenr]
    end
  end

  return { active = make('active'), inactive = make('inactive') }
end

--- Default mouse click handler
---
--- Makes clicked window and line current. Centers the line on double click.
---
---@param data table As described in |MiniStatuscolumn.gen_content.main()|.
MiniStatuscolumn.default_click = function(data)
  H.check_type('data', data, 'table')
  H.check_type('data.mousepos', data.mousepos, 'table')
  H.check_type('data.mousepos.winid', data.mousepos.winid, 'number')
  H.check_type('data.mousepos.line', data.mousepos.line, 'number')
  H.check_type('data.mousepos.column', data.mousepos.column, 'number')
  H.check_type('data.n_clicks', data.n_clicks, 'number')

  local mousepos = data.mousepos
  local ok = pcall(vim.api.nvim_set_current_win, mousepos.winid)
  if not ok then return end
  ok = pcall(vim.api.nvim_win_set_cursor, mousepos.winid, { mousepos.line, mousepos.column - 1 })
  if not ok then return end

  if data.n_clicks == 2 then vim.cmd('normal! zz') end
end

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniStatuscolumn.config)

-- Namespaces
H.ns_id = {
  track = vim.api.nvim_create_namespace('MiniStatuscolumnTrack'),
}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  H.check_type('config.content', config.content, 'table')
  H.check_type('config.content.active', config.content.active, 'function', true)
  H.check_type('config.content.inactive', config.content.inactive, 'function', true)

  H.check_type('config.dim_inactive', config.dim_inactive, 'boolean')

  return config
end

H.apply_config = function(config)
  MiniStatuscolumn.config = config

  -- Ensure proper content
  local content = config.content
  if content.active == nil and content.inactive == nil then
    local default_spec = {
      { fold = '%C', lnum = '%l', sign = '%s' },
      { format = '=lfs', sep = '▏' },
      { ltype = 'virt', lnum = '•' },
      { ltype = 'wrap', lnum = '↳' },
      { win = 'inactive', sep = ' ' },
    }
    content = MiniStatuscolumn.gen_content.main(default_spec)
  end

  -- Make and set statuscolumn
  H.make_statuscolumn_functions(content.active or content.inactive, content.inactive or content.active)
  vim.o.statuscolumn =
    '%{%nvim_get_current_win()==#g:actual_curwin ? v:lua.MiniStatuscolumn.active() : v:lua.MiniStatuscolumn.inactive()%}'
end

H.create_autocommands = function(config)
  local gr = vim.api.nvim_create_augroup('MiniStatuscolumn', {})
  vim.api.nvim_create_autocmd('ColorScheme', { group = gr, callback = H.create_default_hl, desc = 'Ensure colors' })

  if config.dim_inactive then H.make_dim_inactive() end
end

H.create_default_hl = function()
  local hi = function(name, opts)
    opts.default = true
    vim.api.nvim_set_hl(0, name, opts)
  end

  H.ensure_dim_hl()
  hi('MiniStatuscolumnDimCursor', { link = 'MiniStatuscolumnDim' })
  hi('MiniStatuscolumnSep', { link = 'LineNr' })
  hi('MiniStatuscolumnSepCursor', { link = 'CursorLineNr' })
end

-- Dim ------------------------------------------------------------------------
H.make_dim_inactive = function()
  -- Set automatic inactive highlight
  local inactive_winhl = {
    'CursorLineFold:MiniStatuscolumnDimCursor',
    'CursorLineNr:MiniStatuscolumnDimCursor',
    'CursorLineSign:MiniStatuscolumnDimCursor',
    'FoldColumn:MiniStatuscolumnDim',
    'LineNr:MiniStatuscolumnDim',
    'LineNrAbove:MiniStatuscolumnDim',
    'LineNrBelow:MiniStatuscolumnDim',
    'SignColumn:MiniStatuscolumnDim',

    'MiniStatuscolumnSep:MiniStatuscolumnDim',
    'MiniStatuscolumnSepCursor:MiniStatuscolumnDimCursor',
  }
  local inactive_winhl_str = table.concat(inactive_winhl, ',')
  local inactive_winhl_map = {}
  for _, hl_pair in ipairs(inactive_winhl) do
    inactive_winhl_map[hl_pair] = true
  end

  local not_inactive_winhl = function(hl_pair) return not inactive_winhl_map[hl_pair] end

  local ensure_dimmed = function()
    local cur_win_id = vim.api.nvim_get_current_win()
    -- NOTE: Working with all visible windows instead of precisely per window
    -- (inferred from the event data) is more robust due to window-local
    -- options and window events nature
    for _, win_id in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local winhl_split = vim.split(vim.wo[win_id].winhighlight, ',')
      local new_winhl = table.concat(vim.tbl_filter(not_inactive_winhl, winhl_split), ',')
      if win_id ~= cur_win_id then new_winhl = new_winhl .. ((new_winhl == '' and '' or ',') .. inactive_winhl_str) end
      vim.wo[win_id][0].winhighlight = new_winhl
    end
  end

  local gr = vim.api.nvim_create_augroup('MiniStatuscolumn', { clear = false })

  -- NOTE: The `BufWinEnter` callback is called with entered buffer temporarily
  -- made current. It means that showing that buffer without visibly changing
  -- windows can result in it highlighted as "active", when it is not. Schedule
  -- dimming for this event in hope that this will not result in flickering.
  vim.api.nvim_create_autocmd('WinEnter', { group = gr, callback = ensure_dimmed, desc = 'Ensure dimmed' })
  local ensure_dimmed_scheduled = vim.schedule_wrap(ensure_dimmed)
  vim.api.nvim_create_autocmd('BufWinEnter', { group = gr, callback = ensure_dimmed_scheduled, desc = 'Ensure dimmed' })
end

H.ensure_dim_hl = function()
  local linenr = vim.api.nvim_get_hl(0, { name = 'LineNr', link = false })
  local normal = vim.api.nvim_get_hl(0, { name = 'Normal', link = false })
  local fg_num, bg_num = linenr.fg or normal.fg, linenr.bg or normal.bg
  if type(fg_num) ~= 'number' or type(bg_num) ~= 'number' then
    return vim.api.nvim_set_hl(0, 'MiniStatuscolumnDim', { link = 'LineNr' })
  end

  -- Make regular foreground a bit closer to the effective background
  local fg, bg = string.format('%06x', fg_num), string.format('%06x', bg_num)
  local mix = function(i, j) return 0.618 * tonumber(bg:sub(i, j), 16) + 0.382 * tonumber(fg:sub(i, j), 16) end
  local fg_dim = string.format('#%02x%02x%02x', mix(1, 2), mix(3, 4), mix(5, 6))
  -- NOTE: do not use `default=true` since it needs recomputation to be valid
  vim.api.nvim_set_hl(0, 'MiniStatuscolumnDim', { fg = fg_dim, bg = '#' .. bg })
end

-- Content --------------------------------------------------------------------
H.make_statuscolumn_functions = function(active, inactive)
  -- Local helpers to not do extra `vim.api` table lookups
  local get_cur_win = vim.api.nvim_get_current_win
  local eval_stl = vim.api.nvim_eval_statusline
  local win_is_valid = vim.api.nvim_win_is_valid
  local get_statuscolumn_string = function(win_id, lnum)
    return eval_stl('%l%C%s', { winid = win_id, use_statuscol_lnum = 1 }).str
  end

  -- Set up window data caching
  local gr = vim.api.nvim_create_augroup('MiniStatuscolumnWinCache', {})
  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = gr, pattern = pattern, callback = callback, desc = desc })
  end

  local win_cache = {}
  local update_win_cache = function()
    win_cache = {}
    for _, win_id in ipairs(vim.api.nvim_list_wins()) do
      local cache = { buf_id = vim.api.nvim_win_get_buf(win_id), win_id = win_id }

      -- Relevant options
      cache.opt_cursorline = vim.wo[win_id].cursorline
      cache.opt_cursorlineopt = vim.wo[win_id].cursorlineopt
      cache.opt_foldcolumn = vim.wo[win_id].foldcolumn
      cache.opt_number = vim.wo[win_id].number
      cache.opt_relativenumber = vim.wo[win_id].relativenumber
      cache.opt_signcolumn = vim.wo[win_id].signcolumn

      -- Helpful indicators
      cache.is_signcolumn_fixed = cache.opt_signcolumn:sub(2, 2) ~= 'u'
      cache.is_foldcolumn_fixed = cache.opt_foldcolumn:sub(2, 2) ~= 'u'
      cache.is_statuscolumn_empty = get_statuscolumn_string(win_id, 1) == ''
      cache.is_cursorlinenr = cache.opt_cursorline
        and (cache.opt_cursorlineopt:find('number') ~= nil or cache.opt_cursorlineopt:find('both') ~= nil)

      win_cache[win_id] = cache
    end
  end

  local get_win_cache = function(win_id)
    if win_cache[win_id] then return win_cache[win_id] end
    update_win_cache()
    return win_cache[win_id] or {}
  end

  -- - Not-very-frequent cache update
  au({ 'BufWinEnter', 'TermOpen' }, '*', update_win_cache, 'Update window cache')
  local options = { 'cursorline', 'cursorlineopt', 'foldcolumn', 'number', 'relativenumber', 'signcolumn' }
  au('OptionSet', options, update_win_cache, 'Update window cache')

  -- - Frequent cache update needed to react on non-fixed signcolumn/foldcolumn
  --   changing their width. Like after adding a sign or fold.
  --   Schedule as otherwise `nvim_eval_statusline()` returns outdated value.
  local track_empty_statuscolumn = vim.schedule_wrap(function(win_id, toprow)
    local cache = get_win_cache(win_id)
    if cache.is_signcolumn_fixed and cache.is_foldcolumn_fixed then return end
    if not win_is_valid(win_id) or vim.wo[win_id].statuscolumn == '' then return end
    local old, new = cache.is_statuscolumn_empty, get_statuscolumn_string(win_id, toprow) == ''
    cache.is_statuscolumn_empty = new

    -- Ensure that drawn statuscolumn uses up to date cache. Resetting the
    -- 'statuscolumn' option also allows width to shrink (`:h 'statuscolumn'`).
    if new ~= old then vim.wo[win_id].statuscolumn = vim.wo[win_id].statuscolumn end
  end)
  local on_win = function(_, win_id, _, toprow, _)
    track_empty_statuscolumn(win_id, toprow)
    return false
  end
  vim.api.nvim_set_decoration_provider(H.ns_id.track, { on_win = on_win })

  -- Define exported functions for active and inactive windows
  MiniStatuscolumn.active = function() return active(get_win_cache(get_cur_win())) end
  MiniStatuscolumn.inactive = function() return inactive(get_win_cache(get_cur_win())) end
end

H.validate_main_content_spec = function(x)
  H.check_array_of('spec', x, 'table')
  for i, s in ipairs(x) do
    local item = string.format('spec[%d]', i)
    if s.win ~= nil then H.check_one_of(item .. '.win', s.win, { 'active', 'inactive' }) end
    if s.pos ~= nil then H.check_one_of(item .. '.pos', s.pos, { 'above', 'cursor', 'below' }) end
    if s.ltype ~= nil then H.check_one_of(item .. '.ltype', s.ltype, { 'text', 'virt', 'wrap' }) end

    H.check_type(item .. '.format', s.format, 'string', true)
    if s.format ~= nil and s.format:find('[^=lfs]') ~= nil then
      H.error('`' .. item .. '.format` should contain only `=fls` characters')
    end
    H.check_type(item .. '.fold', s.fold, 'string', true)
    H.check_type(item .. '.lnum', s.lnum, 'string', true)
    H.check_type(item .. '.sign', s.sign, 'string', true)
    H.check_type(item .. '.sep', s.sep, 'string', true)

    local at_least_one_info = s.format or s.fold or s.lnum or s.sign or s.sep
    if not at_least_one_info then H.error('`' .. item .. '` should contain at least one info field') end
  end
end

H.make_main_content_map = function(spec, click)
  -- Gather array spec into a map ensuring default values
  spec = vim.deepcopy(spec)
  table.insert(spec, 1, { format = 'fs=l', fold = '%C', lnum = '%l', sign = '%s', sep = ' ' })

  local map = {}
  for _, s in ipairs(spec) do
    local win_values = s.win == nil and { 'active', 'inactive' } or { s.win }
    local pos_values = s.pos == nil and { 'above', 'cursor', 'below' } or { s.pos }
    local ltype_values = s.ltype == nil and { 'text', 'virt', 'wrap' } or { s.ltype }

    for _, win in ipairs(win_values) do
      s.win = win
      local win_map = map[win] or {}
      for _, pos in ipairs(pos_values) do
        s.pos = pos
        local pos_map = win_map[pos] or {}
        for _, ltype in ipairs(ltype_values) do
          s.ltype = ltype
          pos_map[ltype] = vim.tbl_extend('force', pos_map[ltype] or {}, s)
        end
        win_map[pos] = pos_map
      end
      map[win] = win_map
    end
  end

  -- Prepare clicking data
  local make_click = function(ltype, section)
    return function(_, n_clicks, button, modifiers)
      local data = { n_clicks = n_clicks, button = button, modifiers = modifiers }
      data.mousepos = vim.fn.getmousepos()
      -- NOTE: `ltype` has proper values only on Neovim>=0.13
      -- See: https://github.com/neovim/neovim/issues/40210
      data.ltype, data.section = ltype, section
      click(data)
    end
  end

  local with_click = function(ltype, section, section_content)
    if section_content == '' then return '' end
    local click_name = '_click_' .. ltype .. '_' .. section
    MiniStatuscolumn[click_name] = make_click(ltype, section)

    return string.format('%%@v:lua.MiniStatuscolumn.%s@%s%%T', click_name, section_content)
  end

  -- Compute content for each scope
  local format_repl = { ['='] = '%=' }
  for _, win_map in pairs(map) do
    for pos, pos_map in pairs(win_map) do
      for ltype, ltype_map in pairs(pos_map) do
        format_repl.f = with_click(ltype, 'fold', ltype_map.fold)
        format_repl.l = with_click(ltype, 'lnum', ltype_map.lnum)
        format_repl.s = with_click(ltype, 'sign', ltype_map.sign)
        local content_str = ltype_map.format:gsub('[=fls]', format_repl)

        -- NOTE: show separator hl based on whether it is configured to show
        -- "CursorLine" highlighting in the column (`:h hl-CursorLineNr`, but
        -- it works for fold and sign: https://github.com/vim/vim/issues/20480)
        -- It also helps with drawing issues, since statuscolumn is not redrawn
        -- on cursor movement with 'nocursorline', which makes cursor separator
        -- not update also.
        local sep, sep_hl = ltype_map.sep, '%#MiniStatuscolumnSep#'
        local sep_hl_cur = pos == 'cursor' and '%#MiniStatuscolumnSepCursor#' or sep_hl
        local content = {}
        content[false] = content_str .. with_click(ltype, 'sep', sep == '' and '' or (sep_hl .. sep))
        content[true] = content_str .. with_click(ltype, 'sep', sep == '' and '' or (sep_hl_cur .. sep))
        ltype_map.content = content
      end
    end
  end

  return map
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.statuscolumn) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.check_one_of = function(name, x, choices)
  if vim.tbl_contains(choices, x) then return end
  local choices_string = table.concat(vim.tbl_map(vim.inspect, choices), ', ')
  local msg = string.format('`%s` should be one of %s', name, choices_string)
  H.error(msg)
end

H.check_array_of = function(name, x, ref_type)
  if not vim.islist(x) then H.error('`' .. name .. '` should be array') end
  for i, k in ipairs(x) do
    if type(k) ~= ref_type then H.error('Every `' .. name .. '` item should be ' .. ref_type) end
  end
end

return MiniStatuscolumn
