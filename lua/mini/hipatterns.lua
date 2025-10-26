--- *mini.hipatterns* Highlight patterns in text
---
--- MIT License Copyright (c) 2023 Evgeni Chasnovski

--- Features:
--- - Highlight text with configurable patterns and highlight groups (can be
---   string or callable).
---
--- - Highlighting is updated asynchronously with configurable debounce delay.
---
--- - Function to get matches in a buffer (see |MiniHipatterns.get_matches()|).
---
--- See |MiniHipatterns-examples| for common configuration examples.
---
--- Notes:
--- - It does not define any highlighters by default. Add to `config.highlighters`
---   to have a visible effect.
---
--- - Sometimes (especially during frequent buffer updates on same line numbers)
---   highlighting can be outdated or not applied when it should be. This is due
---   to asynchronous nature of updates reacting to text changes (via
---   `on_lines` of |nvim_buf_attach()|).
---   To make them up to date, use one of the following:
---     - Scroll window (for example, with |CTRL-E| / |CTRL-Y|). This will ensure
---       up to date highlighting inside window view.
---     - Hide and show buffer.
---     - Execute `:edit` (if you enabled highlighting with |MiniHipatterns.setup()|).
---     - Manually call |MiniHipatterns.update()|.
---
--- - If you experience flicker when typing near highlighted pattern in Insert
---   mode, it might be due to `delay` configuration of |mini.completion| or
---   using built-in completion.
---   For better experience with 'mini.completion', make sure that its
---   `delay.completion` is less than this module's `delay.text_change` (which
---   it is by default).
---   The reason for this is (currently unresolvable) limitations of Neovim's
---   built-in completion implementation.
---
--- # Setup ~
---
--- Setting up highlights can be done in two ways:
--- - Manually for every buffer with `require('mini.hipatterns').enable()`.
---   This will enable highlighting only in one particular buffer until it is
---   unloaded (which also includes calling `:edit` on current file).
---
--- - Globally with `require('mini.hipatterns').setup({})` (replace `{}` with
---   your `config` table). This will auto-enable highlighting in "normal"
---   buffers (see 'buftype'). Use |MiniHipatterns.enable()| to manually enable
---   in other buffers.
---   It will also create global Lua table `MiniHipatterns` which you can use
---   for scripting or manually (with `:lua MiniHipatterns.*`).
---
--- See |MiniHipatterns.config| for `config` structure and default values.
---
--- You can override runtime config settings (like highlighters and delays)
--- locally to buffer inside `vim.b.minihipatterns_config` which should have
--- same structure as `MiniHipatterns.config`.
--- See |mini.nvim-buffer-local-config| for more details.
---
--- # Comparisons ~
---
--- - [folke/todo-comments](https://github.com/folke/todo-comments):
---     - Oriented for "TODO", "NOTE", "FIXME" like patterns, while this module
---       can work with any Lua patterns and computable highlight groups.
---     - Has functionality beyond text highlighting (sign placing,
---       "telescope.nvim" extension, etc.), while this module only focuses on
---       highlighting text.
--- - [folke/paint.nvim](https://github.com/folke/paint.nvim):
---     - Mostly similar to this module, but with slightly less functionality,
---       such as computed pattern and highlight group, asynchronous delay, etc.
--- - [NvChad/nvim-colorizer.lua](https://github.com/NvChad/nvim-colorizer.lua):
---     - Oriented for color highlighting, while this module can work with any
---       Lua patterns and computable highlight groups.
---     - Has more built-in color spaces to highlight, while this module out of
---       the box provides only hex color highlighting
---       (see |MiniHipatterns.gen_highlighter.hex_color()|). Other types are
---       also possible to implement.
--- - [uga-rosa/ccc.nvim](https://github.com/uga-rosa/ccc.nvim):
---     - Has more than color highlighting functionality, which is compared to
---       this module in the same way as 'NvChad/nvim-colorizer.lua'.
---
--- # Highlight groups ~
---
--- - `MiniHipatternsFixme` - suggested group to use for `FIXME`-like patterns.
--- - `MiniHipatternsHack` - suggested group to use for `HACK`-like patterns.
--- - `MiniHipatternsTodo` - suggested group to use for `TODO`-like patterns.
--- - `MiniHipatternsNote` - suggested group to use for `NOTE`-like patterns.
---
--- To change any highlight group, set it directly with |nvim_set_hl()|.
---
--- # Disabling ~
---
--- This module can be disabled in three ways:
--- - Globally: set `vim.g.minihipatterns_disable` to `true`.
--- - Locally for buffer permanently: set `vim.b.minihipatterns_disable` to `true`.
--- - Locally for buffer temporarily (until next auto-enabling event if set up
---   with |MiniHipatterns.setup()|): call |MiniHipatterns.disable()|.
---
--- Considering high number of different scenarios and customization
--- intentions, writing exact rules for disabling module's functionality is
--- left to user. See |mini.nvim-disabling-recipes| for common recipes.
---@tag MiniHipatterns

--- # Common configuration examples ~
---
--- - Special words used to convey different level of attention: >lua
---
---   require('mini.hipatterns').setup({
---     highlighters = {
---       fixme = { pattern = 'FIXME', group = 'MiniHipatternsFixme' },
---       hack  = { pattern = 'HACK',  group = 'MiniHipatternsHack'  },
---       todo  = { pattern = 'TODO',  group = 'MiniHipatternsTodo'  },
---       note  = { pattern = 'NOTE',  group = 'MiniHipatternsNote'  },
---     }
---   })
--- <
--- - To match only when pattern appears as a standalone word, use frontier
---   patterns `%f`. For example, instead of `'TODO'` pattern use
---   `'%f[%w]()TODO()%f[%W]'`. In this case, for example, 'TODOING' or 'MYTODO'
---   won't match, but 'TODO' and 'TODO:' will.
---
--- - Color hex (like `#rrggbb`) highlighting: >lua
---
---   local hipatterns = require('mini.hipatterns')
---   hipatterns.setup({
---     highlighters = {
---       hex_color = hipatterns.gen_highlighter.hex_color(),
---     }
---   })
--- <
---   You can customize which part of hex color is highlighted by using `style`
---   field of input options. See |MiniHipatterns.gen_highlighter.hex_color()|.
---
--- - Colored words: >lua
---
---   local words = { red = '#ff0000', green = '#00ff00', blue = '#0000ff' }
---   local word_color_group = function(_, match)
---     local hex = words[match]
---     if hex == nil then return nil end
---     return MiniHipatterns.compute_hex_color_group(hex, 'bg')
---   end
---
---   local hipatterns = require('mini.hipatterns')
---   hipatterns.setup({
---     highlighters = {
---       word_color = { pattern = '%S+', group = word_color_group },
---     },
---   })
--- <
--- - Trailing whitespace (if don't want to use more specific |mini.trailspace|): >lua
---
---   { pattern = '%f[%s]%s*$', group = 'Error' }
--- <
--- - Censor certain sensitive information: >lua
---
---   local censor_extmark_opts = function(_, match, _)
---     local mask = string.rep('x', vim.fn.strchars(match))
---     return {
---       virt_text = { { mask, 'Comment' } }, virt_text_pos = 'overlay',
---       priority = 200, right_gravity = false,
---     }
---   end
---
---   require('mini.hipatterns').setup({
---     highlighters = {
---       censor = {
---         pattern = 'password: ()%S+()',
---         group = '',
---         extmark_opts = censor_extmark_opts,
---       },
---     },
---   })
--- <
--- - Enable only in certain filetypes. There are at least these ways to do it:
---     - (Suggested) With `vim.b.minihipatterns_config` in |filetype-plugin|.
---       Basically, create "after/ftplugin/<filetype>.lua" file in your config
---       directory (see |$XDG_CONFIG_HOME|) and define `vim.b.minihipatterns_config`
---       there with filetype specific highlighters.
---
---       This assumes `require('mini.hipatterns').setup()` call.
---
---       For example, to highlight keywords in EmmyLua comments in Lua files,
---       create "after/ftplugin/lua.lua" with the following content: >lua
---
---         vim.b.minihipatterns_config = {
---           highlighters = {
---             emmylua = { pattern = '^%s*%-%-%-()@%w+()', group = 'Special' }
---           }
---         }
--- <
---     - Use callable `pattern` with condition. For example: >lua
---
---       require('mini.hipatterns').setup({
---         highlighters = {
---           emmylua = {
---             pattern = function(buf_id)
---               if vim.bo[buf_id].filetype ~= 'lua' then return nil end
---               return '^%s*%-%-%-()@%w+()'
---             end,
---             group = 'Special',
---           },
---         },
---       })
--- <
--- - Disable only in certain filetypes. Enable with |MiniHipatterns.setup()|
---   and set `vim.b.minihipatterns_disable` buffer-local variable to `true` for
---   buffer you want disabled. See |mini.nvim-disabling-recipes| for more examples.
---@tag MiniHipatterns-examples

---@alias __hipatterns_buf_id number|nil Buffer identifier in which to enable highlighting.
---   Default: 0 for current buffer.

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local

-- Module definition ==========================================================
local MiniHipatterns = {}
local H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniHipatterns.config|.
---
---@usage >lua
---   require('mini.hipatterns').setup({}) -- replace {} with your config table
---                                        -- needs `highlighters` field present
--- <
MiniHipatterns.setup = function(config)
  -- Export module
  _G.MiniHipatterns = MiniHipatterns

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Define behavior
  H.create_autocommands()
  for _, win_id in ipairs(vim.api.nvim_list_wins()) do
    H.auto_enable({ buf = vim.api.nvim_win_get_buf(win_id) })
  end

  -- Create default highlighting
  H.create_default_hl()
end

--- Defaults ~
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text # Highlighters ~
---
--- `highlighters` table defines which patterns will be highlighted by placing
--- |extmark| at the match start. It might or might not have explicitly named
--- fields, but having them is recommended and is required for proper use of
--- `vim.b.minihipatterns_config` as buffer-local config. By default it is
--- empty expecting user definition.
---
--- Each entry defines single highlighter as a table with the following fields:
--- - <pattern> `(string|function|table)` - Lua pattern to highlight. Can be
---   either string, callable returning the string, or an array of those.
---   If string:
---     - It can have submatch delimited by placing `()` on start and end, NOT
---       by surrounding with it. Otherwise it will result in error
---       containing `number expected, got string`. Example: `xx()abcd()xx`
---       will match `abcd` only if `xx` is placed before and after it.
---
---   If callable:
---     - It will be called for every enabled buffer with its identifier as input.
---
---     - It can return `nil` meaning this particular highlighter will not work
---       in this particular buffer.
---
---   If array:
---     - Each element is matched and highlighted with the same highlight group.
---
--- - <group> `(string|function)` - name of highlight group to use. Can be either
---   string or callable returning the string.
---   If callable:
---     - It will be called for every pattern match with the following arguments:
---         - `buf_id` - buffer identifier.
---         - `match` - string pattern match to be highlighted.
---         - `data` - extra table with information about the match.
---           It has at least these fields:
---             - <full_match> - string with full pattern match.
---             - <line> - match line number (1-indexed).
---             - <from_col> - match starting byte column (1-indexed).
---             - <to_col> - match ending byte column (1-indexed, inclusive).
---
---     - It can return `nil` meaning this particular match will not be highlighted.
---
--- - <extmark_opts> `(table|function|nil)` - optional extra options
---   for |nvim_buf_set_extmark()|. If callable, will be called in the same way
---   as callable <group> (`data` will also contain `hl_group` key with <group>
---   value) and should return a table with all options for extmark (including
---   `end_row`, `end_col`, `hl_group`, and `priority`).
---
--- See "Common use cases" section for the examples.
---
--- # Delay ~
---
--- `delay` is a table defining delays in milliseconds used for asynchronous
--- highlighting process.
---
--- `delay.text_change` is used to delay highlighting updates by accumulating
--- them (in debounce fashion). Smaller values will lead to faster response but
--- more frequent updates. Bigger - slower response but less frequent updates.
---
--- `delay.scroll` is used to delay updating highlights in current window view
--- during scrolling (see |WinScrolled| event). These updates are present to
--- ensure up to date highlighting after scroll.
MiniHipatterns.config = {
  -- Table with highlighters (see |MiniHipatterns.config| for more details).
  -- Nothing is defined by default. Add manually for visible effect.
  highlighters = {},

  -- Delays (in ms) defining asynchronous highlighting process
  delay = {
    -- How much to wait for update after every text change
    text_change = 200,

    -- How much to wait for update after window scroll
    scroll = 50,
  },
}
--minidoc_afterlines_end

--- Enable highlighting in buffer
---
--- Notes:
--- - With default config it will highlight nothing, as there are no default
---   highlighters.
---
--- - Buffer highlighting is enabled until buffer is unloaded from memory
---   or |MiniHipatterns.disable()| on this buffer is called.
---
--- - `:edit` disables this, as it is mostly equivalent to closing and opening
---   buffer. In order for highlighting to persist after `:edit`, call
---   |MiniHipatterns.setup()|.
---
---@param buf_id __hipatterns_buf_id
---@param config table|nil Optional buffer-local config. Should have the same
---   structure as |MiniHipatterns.config|. Values will be taken in this order:
---   - From this `config` argument (if supplied).
---   - From buffer-local config in `vim.b.minihipatterns_config` (if present).
---   - From global config (if |MiniHipatterns.setup()| was called).
---   - From default values.
MiniHipatterns.enable = function(buf_id, config)
  buf_id = H.validate_buf_id(buf_id)
  config = H.validate_config_arg(config)

  -- Don't enable more than once
  if H.is_buf_enabled(buf_id) then return end

  -- Register enabled buffer with cached data for performance
  H.update_cache(buf_id, config)

  -- Add buffer watchers
  vim.api.nvim_buf_attach(buf_id, false, {
    -- Called on every text change (`:h nvim_buf_lines_event`)
    on_lines = function(_, _, _, from_line, _, to_line)
      local buf_cache = H.cache[buf_id]
      -- Properly detach if highlighting is disabled
      if buf_cache == nil then return true end
      H.process_lines(buf_id, from_line + 1, to_line, buf_cache.delay.text_change)
    end,

    -- Called when buffer content is changed outside of current session
    on_reload = function() pcall(MiniHipatterns.update, buf_id) end,

    -- Called when buffer is unloaded from memory (`:h nvim_buf_detach_event`),
    -- **including** `:edit` command
    on_detach = function() MiniHipatterns.disable(buf_id) end,
  })

  -- Add buffer autocommands
  local augroup = vim.api.nvim_create_augroup('MiniHipatternsBuffer' .. buf_id, { clear = true })
  H.cache[buf_id].augroup = augroup

  local update_buf = vim.schedule_wrap(function()
    if not H.is_buf_enabled(buf_id) then return end

    H.update_cache(buf_id, config)

    local delay_ms = H.cache[buf_id].delay.text_change
    H.process_lines(buf_id, 1, vim.api.nvim_buf_line_count(buf_id), delay_ms)
  end)

  vim.api.nvim_create_autocmd(
    { 'BufWinEnter', 'FileType' },
    { group = augroup, buffer = buf_id, callback = update_buf, desc = 'Update highlighting for whole buffer' }
  )

  vim.api.nvim_create_autocmd(
    'WinScrolled',
    { group = augroup, buffer = buf_id, callback = H.update_view, desc = 'Update highlighting in view' }
  )

  -- Add highlighting to whole buffer
  H.process_lines(buf_id, 1, vim.api.nvim_buf_line_count(buf_id), 0)
end

--- Disable highlighting in buffer
---
--- Note that if |MiniHipatterns.setup()| was called, the effect is present
--- until the next auto-enabling event. To permanently disable highlighting in
--- buffer, set `vim.b.minihipatterns_disable` to `true`
---
---@param buf_id __hipatterns_buf_id
MiniHipatterns.disable = function(buf_id)
  buf_id = H.validate_buf_id(buf_id)

  local buf_cache = H.cache[buf_id]
  if buf_cache == nil then return end
  H.cache[buf_id] = nil

  vim.api.nvim_del_augroup_by_id(buf_cache.augroup)
  for _, ns in pairs(H.ns_id) do
    H.clear_namespace(buf_id, ns, 0, -1)
  end
end

--- Toggle highlighting in buffer
---
--- Call |MiniHipatterns.disable()| if enabled; |MiniHipatterns.enable()| otherwise.
---
---@param buf_id __hipatterns_buf_id
---@param config table|nil Forwarded to |MiniHipatterns.enable()|.
MiniHipatterns.toggle = function(buf_id, config)
  buf_id = H.validate_buf_id(buf_id)
  config = H.validate_config_arg(config)

  if H.is_buf_enabled(buf_id) then
    MiniHipatterns.disable(buf_id)
  else
    MiniHipatterns.enable(buf_id, config)
  end
end

--- Update highlighting in range
---
--- Works only in buffer with enabled highlighting. Effect takes immediately
--- without delay.
---
---@param buf_id __hipatterns_buf_id
---@param from_line number|nil Start line from which to update (1-indexed).
---@param to_line number|nil End line from which to update (1-indexed, inclusive).
MiniHipatterns.update = function(buf_id, from_line, to_line)
  buf_id = H.validate_buf_id(buf_id)

  if not H.is_buf_enabled(buf_id) then H.error(string.format('Buffer %d is not enabled.', buf_id)) end

  from_line = from_line or 1
  if type(from_line) ~= 'number' then H.error('`from_line` should be a number.') end
  to_line = to_line or vim.api.nvim_buf_line_count(buf_id)
  if type(to_line) ~= 'number' then H.error('`to_line` should be a number.') end

  -- Process lines immediately without delay
  H.process_lines(buf_id, from_line, to_line, 0)
end

--- Get an array of enabled buffers
---
---@return table Array of buffer identifiers with enabled highlighting.
MiniHipatterns.get_enabled_buffers = function()
  local res = {}
  for buf_id, _ in pairs(H.cache) do
    if vim.api.nvim_buf_is_valid(buf_id) then
      table.insert(res, buf_id)
    else
      -- Clean up if buffer is invalid and for some reason is still enabled
      H.cache[buf_id] = nil
    end
  end

  -- Ensure consistent order
  table.sort(res)

  return res
end

--- Get buffer matches
---
---@param buf_id number|nil Buffer identifier for which to return matches.
---   Default: `nil` for current buffer.
---@param highlighters table|nil Array of highlighter identifiers (as in
---   `highlighters` field of |MiniHipatterns.config|) for which to return matches.
---   Default: all available highlighters (ordered by string representation).
---
---@return table Array of buffer matches which are tables with following fields:
---   - <bufnr> `(number)` - buffer identifier of a match.
---   - <highlighter> `(any)` - highlighter identifier which produced the match.
---   - <lnum> `(number)` - line number of the match start (starts with 1).
---   - <col> `(number)` - column number of the match start (starts with 1).
---   - <end_lnum> `(number|nil)` - line number of the match end (starts with 1).
---   - <end_col> `(number|nil)` - column number next to the match end
---     (implements end-exclusive region; starts with 1).
---   - <hl_group> `(string|nil)` - name of match's highlight group.
---
---   Matches are ordered first by supplied `highlighters`, then by line and
---   column of match start.
MiniHipatterns.get_matches = function(buf_id, highlighters)
  buf_id = (buf_id == nil or buf_id == 0) and vim.api.nvim_get_current_buf() or buf_id
  if not (type(buf_id) == 'number' and vim.api.nvim_buf_is_valid(buf_id)) then
    H.error('`buf_id` is not valid buffer identifier.')
  end

  local all_highlighters = H.get_all_highlighters()
  highlighters = highlighters or all_highlighters
  if not H.islist(highlighters) then H.error('`highlighters` should be an array.') end
  highlighters = vim.tbl_filter(function(x) return vim.tbl_contains(all_highlighters, x) end, highlighters)

  local position_compare = function(a, b) return a[2] < b[2] or (a[2] == b[2] and a[3] < b[3]) end
  local res = {}
  for _, hi_id in ipairs(highlighters) do
    local extmarks = H.get_extmarks(buf_id, H.ns_id[hi_id], 0, -1, { details = true })
    table.sort(extmarks, position_compare)

    for _, extmark in ipairs(extmarks) do
      local end_lnum, end_col = extmark[4].end_row, extmark[4].end_col
      end_lnum = type(end_lnum) == 'number' and (end_lnum + 1) or end_lnum
      end_col = type(end_col) == 'number' and (end_col + 1) or end_col
      --stylua: ignore
      local entry = {
        bufnr = buf_id,        highlighter = hi_id,
        lnum = extmark[2] + 1, col = extmark[3] + 1,
        end_lnum = end_lnum,   end_col = end_col,
        hl_group = extmark[4].hl_group,
      }
      table.insert(res, entry)
    end
  end
  return res
end

--- Generate builtin highlighters
---
--- This is a table with function elements. Call to actually get highlighter.
MiniHipatterns.gen_highlighter = {}

--- Highlight hex color string
---
--- This will match color hex string in format `#rrggbb` and highlight it
--- according to `opts.style` displaying matched color.
---
--- Highlight group is computed using |MiniHipatterns.compute_hex_color_group()|,
--- so all its usage notes apply here.
---
---@param opts table|nil Options. Possible fields:
---   - <style> `(string)` - one of:
---       - `'full'` -  highlight background of whole hex string with it. Default.
---       - `'#'` - highlight background of only `#`.
---       - `'line'` - highlight underline with that color.
---       - `'inline'` - highlight text of <inline_text>.
---         Note: requires Neovim>=0.10.
---   - <priority> `(number)` - priority of highlighting. Default: 200.
---   - <filter> `(function)` - callable object used to filter buffers in which
---     highlighting will take place. It should take buffer identifier as input
---     and return `false` or `nil` to not highlight inside this buffer.
---   - <inline_text> `(string)` - string to be placed and highlighted with color
---     to the right of match in case <style> is "inline". Default: "█".
---
---@return table Highlighter table ready to be used as part of `config.highlighters`.
---   Both `pattern` and `group` are callable.
---
---@usage >lua
---   local hipatterns = require('mini.hipatterns')
---   hipatterns.setup({
---     highlighters = {
---       hex_color = hipatterns.gen_highlighter.hex_color(),
---     }
---   })
--- <
MiniHipatterns.gen_highlighter.hex_color = function(opts)
  local default_opts = { style = 'full', priority = 200, filter = H.always_true, inline_text = '█' }
  opts = vim.tbl_deep_extend('force', default_opts, opts or {})

  local style = opts.style
  if style == 'inline' and vim.fn.has('nvim-0.10') == 0 then
    H.error('Style "inline" in `gen_highlighter.hex_color()` requires Neovim>=0.10.')
  end

  local pattern = style == '#' and '()#()%x%x%x%x%x%x%f[%X]' or '#%x%x%x%x%x%x%f[%X]'
  local hl_style = ({ full = 'bg', ['#'] = 'bg', line = 'line', inline = 'fg' })[style] or 'bg'

  local extmark_opts = { priority = opts.priority }
  if opts.style == 'inline' then
    local priority, inline_text = opts.priority, opts.inline_text
    ---@diagnostic disable:cast-local-type
    extmark_opts = function(_, _, data)
      local virt_text = { { inline_text, data.hl_group } }
      return { virt_text = virt_text, virt_text_pos = 'inline', priority = priority, right_gravity = false }
    end
  end

  return {
    pattern = H.wrap_pattern_with_filter(pattern, opts.filter),
    group = function(_, _, data) return MiniHipatterns.compute_hex_color_group(data.full_match, hl_style) end,
    extmark_opts = extmark_opts,
  }
end

--- Compute and create group to highlight hex color string
---
--- Notes:
--- - This works properly only with enabled |'termguicolors'|.
---
--- - To increase performance, it caches highlight groups per `hex_color` and
---   `style` combination. Needs a call to |MiniHipatterns.setup()| to have
---   these groups be persistent across color scheme changes.
---
---@param hex_color string Hex color string in format `#rrggbb`.
---@param style|nil string One of:
---   - `'bg'` - highlight background with `hex_color` and foreground with black or
---     white (whichever is more visible). Default.
---   - `'fg'` - highlight foreground with `hex_color`.
---   - `'line'` - highlight underline with `hex_color`.
---
---@return string Name of created highlight group appropriate to show `hex_color`.
MiniHipatterns.compute_hex_color_group = function(hex_color, style)
  style = style or 'bg'
  local hex = hex_color:lower():sub(2)
  local group_name = string.format('MiniHipatterns_%s_%s', hex, style)

  -- Use manually tracked table instead of `vim.fn.hlexists()` because the
  -- latter still returns true for cleared highlights
  if H.hex_color_groups[group_name] then return group_name end

  -- Define highlight group if it is not already defined
  if style == 'bg' then
    -- Compute opposite color based on Oklab lightness (for better contrast)
    local opposite = H.compute_opposite_color(hex)
    vim.api.nvim_set_hl(0, group_name, { fg = opposite, bg = hex_color })
  end

  if style == 'fg' then vim.api.nvim_set_hl(0, group_name, { fg = hex_color }) end

  if style == 'line' then vim.api.nvim_set_hl(0, group_name, { sp = hex_color, underline = true }) end

  -- Keep track of created groups to properly react on `:hi clear`
  H.hex_color_groups[group_name] = true

  return group_name
end

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniHipatterns.config)

-- Timers
H.timer_debounce = vim.uv.new_timer()
H.timer_view = vim.uv.new_timer()

-- Namespaces per highlighter name
H.ns_id = {}

-- Cache of queued changes used for debounced highlighting
H.change_queue = {}

-- Cache per enabled buffer
H.cache = {}

-- Data about created highlight groups for hex colors
H.hex_color_groups = {}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  H.check_type('highlighters', config.highlighters, 'table')

  H.check_type('delay', config.delay, 'table')
  H.check_type('delay.text_change', config.delay.text_change, 'number')
  H.check_type('delay.scroll', config.delay.scroll, 'number')

  return config
end

H.apply_config = function(config) MiniHipatterns.config = config end

H.create_autocommands = function()
  local gr = vim.api.nvim_create_augroup('MiniHipatterns', {})

  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = gr, pattern = pattern, callback = callback, desc = desc })
  end

  au('BufEnter', '*', H.auto_enable, 'Enable highlighting')
  au('ColorScheme', '*', H.create_default_hl, 'Ensure colors')
  au('ColorScheme', '*', H.on_colorscheme, 'Reload all enabled pattern highlighters')
end

H.create_default_hl = function()
  local hi_link_bold_reverse = function(to, from)
    local data = vim.api.nvim_get_hl(0, { name = from, link = false })
    data.default, data.bold, data.reverse = true, true, true
    data.cterm = { bold = true, reverse = true }
    vim.api.nvim_set_hl(0, to, data)
  end
  hi_link_bold_reverse('MiniHipatternsFixme', 'DiagnosticError')
  hi_link_bold_reverse('MiniHipatternsHack', 'DiagnosticWarn')
  hi_link_bold_reverse('MiniHipatternsTodo', 'DiagnosticInfo')
  hi_link_bold_reverse('MiniHipatternsNote', 'DiagnosticHint')
end

H.is_disabled = function(buf_id)
  local buf_disable = H.get_buf_var(buf_id, 'minihipatterns_disable')
  return vim.g.minihipatterns_disable == true or buf_disable == true
end

H.get_config = function(config, buf_id)
  local buf_config = H.get_buf_var(buf_id, 'minihipatterns_config') or {}
  return vim.tbl_deep_extend('force', MiniHipatterns.config, buf_config, config or {})
end

H.get_buf_var = function(buf_id, name)
  if not vim.api.nvim_buf_is_valid(buf_id) then return nil end
  return vim.b[buf_id or 0][name]
end

-- Autocommands ---------------------------------------------------------------
H.auto_enable = vim.schedule_wrap(function(data)
  local buf = data.buf
  if not (vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == '') then return end
  MiniHipatterns.enable(buf)
end)

H.update_view = vim.schedule_wrap(function(data)
  -- Update view only in enabled buffers
  local buf_cache = H.cache[data.buf]
  if buf_cache == nil then return end

  -- NOTE: due to scheduling (which is necessary for better performance),
  -- current buffer can be not the target one. But as there is no proper (easy
  -- and/or fast) way to get the view of certain buffer (except the current)
  -- accept this approach. The main problem of current buffer having not
  -- enabled highlighting is solved during processing buffer highlighters.

  -- Debounce without aggregating redraws (only last view should be updated)
  H.timer_view:stop()
  H.timer_view:start(buf_cache.delay.scroll, 0, H.process_view)
end)

H.on_colorscheme = function()
  -- Reset created highlight groups for hex colors, as they are probably
  -- cleared after `:hi clear`
  H.hex_color_groups = {}

  -- Reload all currently enabled buffers
  for buf_id, _ in pairs(H.cache) do
    MiniHipatterns.disable(buf_id)
    MiniHipatterns.enable(buf_id)
  end
end

-- Validators -----------------------------------------------------------------
H.validate_buf_id = function(x)
  if x == nil or x == 0 then return vim.api.nvim_get_current_buf() end

  if not (type(x) == 'number' and vim.api.nvim_buf_is_valid(x)) then
    H.error('`buf_id` should be `nil` or valid buffer id.')
  end

  return x
end

H.validate_config_arg = function(x)
  if x == nil or type(x) == 'table' then return x or {} end
  H.error('`config` should be `nil` or table.')
end

H.validate_string = function(x, name)
  if type(x) == 'string' then return x end
  H.error(string.format('`%s` should be string.'))
end

-- Enabling -------------------------------------------------------------------
H.is_buf_enabled = function(buf_id) return H.cache[buf_id] ~= nil end

H.update_cache = function(buf_id, config)
  local buf_cache = H.cache[buf_id] or {}
  local buf_config = H.get_config(config, buf_id)
  buf_cache.highlighters = H.normalize_highlighters(buf_config.highlighters)
  buf_cache.delay = buf_config.delay

  H.cache[buf_id] = buf_cache
end

H.normalize_highlighters = function(highlighters)
  local res = {}
  for hi_name, hi in pairs(highlighters) do
    -- Allow pattern to be string, callable, or array of those. Convert all
    -- valid cases into array of callables.
    local pattern = type(hi.pattern) == 'string' and function() return hi.pattern end or hi.pattern
    if vim.is_callable(pattern) then pattern = { pattern } end
    local is_pattern_ok = H.islist(pattern)
    if is_pattern_ok then
      for i, pat in ipairs(pattern) do
        pattern[i] = type(pat) == 'string' and function() return pat end or pat
        is_pattern_ok = is_pattern_ok and vim.is_callable(pattern[i])
      end
    end

    local group = type(hi.group) == 'string' and function() return hi.group end or hi.group

    local extmark_opts = hi.extmark_opts or { priority = 200 }
    if type(extmark_opts) == 'table' then
      local t = extmark_opts
      ---@diagnostic disable:cast-local-type
      extmark_opts = function(_, _, data)
        local opts = vim.deepcopy(t)
        opts.hl_group = opts.hl_group or data.hl_group
        opts.end_row = opts.end_row or (data.line - 1)
        opts.end_col = opts.end_col or data.to_col
        return opts
      end
    end

    if is_pattern_ok and vim.is_callable(group) and vim.is_callable(extmark_opts) then
      res[hi_name] = { pattern = pattern, group = group, extmark_opts = extmark_opts }
      H.ns_id[hi_name] = vim.api.nvim_create_namespace('MiniHipatterns-' .. hi_name)
    end
  end

  return res
end

H.get_all_highlighters = function()
  local hi_arr = vim.tbl_map(function(x) return { x, tostring(x) } end, vim.tbl_keys(H.ns_id))
  table.sort(hi_arr, function(a, b) return a[2] < b[2] end)
  return vim.tbl_map(function(x) return x[1] end, hi_arr)
end

-- Processing -----------------------------------------------------------------
H.process_lines = vim.schedule_wrap(function(buf_id, from_line, to_line, delay_ms)
  -- Make sure that that at least one line is processed (important to react
  -- after deleting line with extmark non-trivial `extmark_opts`)
  table.insert(H.change_queue, { buf_id, math.min(from_line, to_line), math.max(from_line, to_line) })

  -- Debounce
  H.timer_debounce:stop()
  H.timer_debounce:start(delay_ms, 0, H.process_change_queue)
end)

H.process_view = vim.schedule_wrap(function()
  table.insert(H.change_queue, { vim.api.nvim_get_current_buf(), vim.fn.line('w0'), vim.fn.line('w$') })

  -- Process immediately assuming debouncing should be already done
  H.process_change_queue()
end)

H.process_change_queue = vim.schedule_wrap(function()
  local queue = H.normalize_change_queue()

  for buf_id, lines_to_process in pairs(queue) do
    H.process_buffer_changes(buf_id, lines_to_process)
  end

  H.change_queue = {}
end)

H.normalize_change_queue = function()
  local res = {}
  for _, change in ipairs(H.change_queue) do
    -- `change` is { buf_id, from_line, to_line }; lines are already 1-indexed
    local buf_id = change[1]

    local buf_lines_to_process = res[buf_id] or {}
    for i = change[2], change[3] do
      buf_lines_to_process[i] = true
    end

    res[buf_id] = buf_lines_to_process
  end

  return res
end

H.process_buffer_changes = vim.schedule_wrap(function(buf_id, lines_to_process)
  -- Return early if buffer is not proper.
  -- Also check if buffer is enabled here mostly for better resilience. It
  -- might be actually needed due to various `schedule_wrap`s leading to change
  -- queue entry with not target (and improper) buffer.
  local buf_cache = H.cache[buf_id]
  if not vim.api.nvim_buf_is_valid(buf_id) or H.is_disabled(buf_id) or buf_cache == nil then return end

  -- Optimizations are done assuming small-ish number of highlighters and
  -- large-ish number of lines to process

  -- Process highlighters
  for hi_name, hi in pairs(buf_cache.highlighters) do
    -- Remove current highlights
    local ns = H.ns_id[hi_name]
    for l_num, _ in pairs(lines_to_process) do
      H.clear_namespace(buf_id, ns, l_num - 1, l_num)
    end

    -- Add new highlights
    for _, pattern in ipairs(hi.pattern) do
      H.apply_highlighter_pattern(pattern(buf_id), hi, buf_id, ns, lines_to_process)
    end
  end
end)

H.apply_highlighter_pattern = vim.schedule_wrap(function(pattern, hi, buf_id, ns, lines_to_process)
  -- Check again because buffer might have become invalid since latest check
  if not vim.api.nvim_buf_is_valid(buf_id) then return end

  if type(pattern) ~= 'string' then return end
  local group, extmark_opts = hi.group, hi.extmark_opts
  local pattern_has_line_start = pattern:sub(1, 1) == '^'

  -- Apply per proper line
  for l_num, _ in pairs(lines_to_process) do
    local line = H.get_line(buf_id, l_num)
    local from, to, sub_from, sub_to = line:find(pattern)

    while from and (from <= to) do
      -- Compute full pattern match
      local full_match = line:sub(from, to)

      -- Compute (possibly inferred) submatch
      sub_from, sub_to = sub_from or from, sub_to or (to + 1)
      -- - Make last column end-inclusive
      sub_to = sub_to - 1
      local match = line:sub(sub_from, sub_to)

      -- Set extmark based on submatch
      local data = { full_match = full_match, line = l_num, from_col = sub_from, to_col = sub_to }
      local hl_group = group(buf_id, match, data)
      if hl_group ~= nil then
        data.hl_group = hl_group
        H.set_extmark(buf_id, ns, l_num - 1, sub_from - 1, extmark_opts(buf_id, match, data))
      end

      -- Overcome an issue that `string.find()` doesn't recognize `^` when
      -- `init` is more than 1
      if pattern_has_line_start then break end

      from, to, sub_from, sub_to = line:find(pattern, to + 1)
    end
  end
end)

-- Built-in highlighters ------------------------------------------------------
H.wrap_pattern_with_filter = function(pattern, filter)
  return function(...)
    if not filter(...) then return nil end
    return pattern
  end
end

H.compute_opposite_color = function(hex)
  local dec = tonumber(hex, 16)
  local b = H.correct_channel(math.fmod(dec, 256) / 255)
  local g = H.correct_channel(math.fmod((dec - b) / 256, 256) / 255)
  local r = H.correct_channel(math.floor(dec / 65536) / 255)

  local l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
  local m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
  local s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b

  local l_, m_, s_ = H.cuberoot(l), H.cuberoot(m), H.cuberoot(s)

  local L = H.correct_lightness(0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_)

  return L < 0.5 and '#ffffff' or '#000000'
end

-- Function for RGB channel correction. Assumes input in [0; 1] range
-- https://bottosson.github.io/posts/colorwrong/#what-can-we-do%3F
H.correct_channel = function(x) return 0.04045 < x and math.pow((x + 0.055) / 1.055, 2.4) or (x / 12.92) end

-- Function for lightness correction
-- https://bottosson.github.io/posts/colorpicker/#intermission---a-new-lightness-estimate-for-oklab
H.correct_lightness = function(x)
  local k1, k2 = 0.206, 0.03
  local k3 = (1 + k1) / (1 + k2)

  return 0.5 * (k3 * x - k1 + math.sqrt((k3 * x - k1) ^ 2 + 4 * k2 * k3 * x))
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.hipatterns) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.get_line = function(buf_id, line_num)
  return vim.api.nvim_buf_get_lines(buf_id, line_num - 1, line_num, false)[1] or ''
end

H.set_extmark = function(...) pcall(vim.api.nvim_buf_set_extmark, ...) end

H.get_extmarks = function(...)
  local ok, res = pcall(vim.api.nvim_buf_get_extmarks, ...)
  if not ok then return {} end
  return res
end

H.clear_namespace = function(...) pcall(vim.api.nvim_buf_clear_namespace, ...) end

H.always_true = function() return true end

H.cuberoot = function(x) return math.pow(x, 0.333333) end

-- TODO: Remove after compatibility with Neovim=0.9 is dropped
H.islist = vim.fn.has('nvim-0.10') == 1 and vim.islist or vim.tbl_islist

return MiniHipatterns
