--- *mini.indentscope* Visualize and work with indent scope
---
--- MIT License Copyright (c) 2022 Evgeni Chasnovski

--- Indent scope (or just "scope") is a maximum set of consecutive lines which
--- contains certain reference line (cursor line by default) and every member
--- has indent not less than certain reference indent ("indent at cursor" by
--- default: minimum between cursor column and indent of cursor line).
---
--- Features:
--- - Visualize scope with animated vertical line. It is very fast and done
---   automatically in a non-blocking way (other operations can be performed,
---   like moving cursor). You can customize debounce delay and animation rule.
---
--- - Customization of scope computation options can be done on global level
---   (in |MiniIndentscope.config|), for a certain buffer (using
---   `vim.b.miniindentscope_config` buffer variable), or within a call (using
---   `opts` variable in |MiniIndentscope.get_scope()|).
---
--- - Customizable notion of a border: which adjacent lines with strictly lower
---   indent are recognized as such. This is useful for a certain filetypes
---   (for example, Python or plain text).
---
--- - Customizable way of line to be considered "border first". This is useful
---   if you want to place cursor on function header and get scope of its body.
---
--- - There are textobjects and motions to operate on scope. Support |count|
---   and dot-repeat (in operator pending mode).
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.indentscope').setup({})`
--- (replace `{}` with your `config` table). It will create global Lua table
--- `MiniIndentscope` which you can use for scripting or manually (with `:lua
--- MiniIndentscope.*`).
---
--- See |MiniIndentscope.config| for available config settings.
---
--- You can override runtime config settings locally to buffer inside
--- `vim.b.miniindentscope_config` which should have same structure as
--- `MiniIndentscope.config`. See |mini.nvim-buffer-local-config| for more
--- details.
---
--- # Comparisons ~
---
--- - [lukas-reineke/indent-blankline.nvim](https://github.com/lukas-reineke/indent-blankline.nvim):
---     - Its main functionality is about showing static guides of indent levels.
---     - Implementation of 'mini.indentscope' is similar to
---       'indent-blankline.nvim' (using |extmarks| on first column to be shown
---       even on blank lines). They can be used simultaneously, but it will
---       lead to one of the visualizations being on top (hiding) of another.
---
--- # Highlight groups ~
---
--- - `MiniIndentscopeSymbol` - symbol showing on every line of scope if its
---   indent is multiple of 'shiftwidth'.
--- - `MiniIndentscopeSymbolOff` - symbol showing on every line of scope if its
---   indent is not multiple of 'shiftwidth'.
---   Default: links to `MiniIndentscopeSymbol`.
---
--- To change any highlight group, set it directly with |nvim_set_hl()|.
---
--- # Disabling ~
---
--- To disable autodrawing, set `vim.g.miniindentscope_disable` (globally) or
--- `vim.b.miniindentscope_disable` (for a buffer) to `true`. Considering high
--- number of different scenarios and customization intentions, writing exact
--- rules for disabling module's functionality is left to user. See
--- |mini.nvim-disabling-recipes| for common recipes.
---@tag MiniIndentscope

--- Draw of scope indicator is done as iterative animation. It has the
--- following design:
--- - Draw indicator on origin line (where cursor is at) immediately. Indicator
---   is visualized as `MiniIndentscope.config.symbol` placed to the right of
---   scope's border indent. This creates a line from top to bottom scope edges.
--- - Draw upward and downward concurrently per one line. Progression by one
---   line in both direction is considered to be one step of animation.
--- - Before each step wait certain amount of time, which is decided by
---   "animation function". It takes next and total step numbers (both are one
---   or bigger) and returns number of milliseconds to wait before drawing next
---   step. Comparing to a more popular "easing functions" in animation (input:
---   duration since animation start; output: percent of animation done), it is
---   a discrete inverse version of its derivative. Such interface proved to be
---   more appropriate for kind of task at hand.
---
--- # Special cases ~
---
--- - When scope to be drawn intersects (same indent, ranges overlap) currently
---   visible one (at process or finished drawing), drawing is done immediately
---   without animation. With most common example being typing new text, this
---   feels more natural.
--- - Scope for the whole buffer is not drawn as it is isually redundant.
---   Technically, it can be thought as drawn at column 0 (because border
---   indent is -1) which is not visible.
---@tag MiniIndentscope-drawing

-- Module definition ==========================================================
local MiniIndentscope = {}
local H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniIndentscope.config|.
---
---@usage >lua
---   require('mini.indentscope').setup() -- use default config
---   -- OR
---   require('mini.indentscope').setup({}) -- replace {} with your config table
--- <
MiniIndentscope.setup = function(config)
  -- Export module
  _G.MiniIndentscope = MiniIndentscope

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
---@text # Options ~
---
--- ## Border ~
---
--- Field `border` controls which line(s) with smaller indent to categorize
--- as border. This matters for textobjects and motions.
--- It also controls how empty lines are treated: they are included in scope
--- only if followed by a border. Another way of looking at it is that indent
--- of blank line is computed based on value of `border` option.
--- Here is an illustration of how `border` works in presence of empty lines: >
---
---                              |both|bottom|top|none|
---   1|function foo()           | 0  |  0   | 0 | 0  |
---   2|                         | 4  |  0   | 4 | 0  |
---   3|    print('Hello world') | 4  |  4   | 4 | 4  |
---   4|                         | 4  |  4   | 2 | 2  |
---   5|  end                    | 2  |  2   | 2 | 2  |
--- <
--- Numbers inside a table are indent values of a line computed with certain
--- value of `border`. So, for example, a scope with reference line 3 and
--- right-most column has body range depending on value of `border` option:
--- - `border` is "both":   range is 2-4, border is 1 and 5 with indent 2.
--- - `border` is "top":    range is 2-3, border is 1 with indent 0.
--- - `border` is "bottom": range is 3-4, border is 5 with indent 0.
--- - `border` is "none":   range is 3-3, border is empty with indent `nil`.
---
--- ## Indent at cursor ~
---
--- Field `indent_at_cursor` controls if cursor position should affect computation
--- of scope. If `true`, reference indent is a minimum of reference line's indent
--- and cursor column. In main example, here how scope's body range differs
--- depending on cursor column and `indent_at_cursor` value (assuming cursor is
--- on line 3 and it is whole buffer): >
---
---   Column\Option true|false
---      1 and 2    2-5 | 2-4
---    3 and more   2-4 | 2-4
--- <
--- ## Number of lines ~
---
--- Field `n_lines` defines |MiniIndentscope.get_scope()| behavior for how many
--- lines above/below to check before iteration is stopped. Scope that reached
--- computation limit has <is_incomplete> field set to `true`. It will also not
--- be auto drawn with default `config.draw.predicate`.
---
--- Lower values will result in better overall performance in exchange for more
--- frequent incomplete scope computation. Set to `math.huge` for no restriction.
---
--- ## Try as border ~
---
--- Field `try_as_border` controls how to act when input line can be recognized
--- as a border of some neighbor indent scope. In main example, when input line
--- is 1 and can be recognized as border for inner scope, value `try_as_border=true`
--- means that inner scope will be returned. Similar, for input line 5 inner scope
--- will be returned if it is recognized as border.
MiniIndentscope.config = {
  -- Draw options
  draw = {
    -- Delay (in ms) between event and start of drawing scope indicator
    delay = 100,

    -- Animation rule for scope's first drawing. A function which, given
    -- next and total step numbers, returns wait time (in ms). See
    -- |MiniIndentscope.gen_animation| for builtin options. To disable
    -- animation, use `require('mini.indentscope').gen_animation.none()`.
    --minidoc_replace_start animation = --<function: implements constant 20ms between steps>,
    animation = function(s, n) return 20 end,
    --minidoc_replace_end

    -- Whether to auto draw scope: return `true` to draw, `false` otherwise.
    -- Default draws only fully computed scope (see `options.n_lines`).
    predicate = function(scope) return not scope.body.is_incomplete end,

    -- Symbol priority. Increase to display on top of more symbols.
    priority = 2,
  },

  -- Module mappings. Use `''` (empty string) to disable one.
  mappings = {
    -- Textobjects
    object_scope = 'ii',
    object_scope_with_border = 'ai',

    -- Motions (jump to respective border line; if not present - body line)
    goto_top = '[i',
    goto_bottom = ']i',
  },

  -- Options which control scope computation
  options = {
    -- Type of scope's border: which line(s) with smaller indent to
    -- categorize as border. Can be one of: 'both', 'top', 'bottom', 'none'.
    border = 'both',

    -- Whether to use cursor column when computing reference indent.
    -- Useful to see incremental scopes with horizontal cursor movements.
    indent_at_cursor = true,

    -- Maximum number of lines above or below within which scope is computed
    n_lines = 10000,

    -- Whether to first check input line to be a border of adjacent scope.
    -- Use it if you want to place cursor on function header to get scope of
    -- its body.
    try_as_border = false,
  },

  -- Which character to use for drawing scope indicator
  symbol = '╎',
}
--minidoc_afterlines_end

-- Module functionality =======================================================
--- Compute indent scope
---
--- Indent scope (or just "scope") is a maximum set of consecutive lines which
--- contains certain reference line (cursor line by default) and every member
--- has indent not less than certain reference indent ("indent at column" by
--- default). Here "indent at column" means minimum between input column value
--- and indent of reference line. When using cursor column, this allows for a
--- useful interactive view of nested indent scopes by making horizontal
--- movements within line.
---
--- Options controlling actual computation is taken from these places in order:
--- - Argument `opts`. Use it to ensure independence from other sources.
--- - Buffer local variable `vim.b.miniindentscope_config` (`options` field).
---   Useful to define local behavior (for example, for a certain filetype).
--- - Global options from |MiniIndentscope.config|.
---
--- # Algorithm overview ~
---
--- - Compute reference "indent at column". Reference line is an input `line`
---   which might be modified to one of its neighbors if `try_as_border` option
---   is `true`: if it can be viewed as border of some neighbor scope, it will.
--- - Process upwards and downwards from reference line searching for line with
---   indent strictly less than reference one. This is like casting rays up and
---   down from reference line and reference indent until meeting "a wall"
---   (character to the right of indent or buffer edge). Latest line before
---   meeting a wall is a respective end of scope body. It always exists because
---   reference line is a such one.
---   Casting ray is forced to stop if it goes over `opts.n_lines` lines.
--- - Based on top and bottom lines with strictly lower indent, construct
---   scopes's border. The way it is computed is decided based on `border`
---   option (see |MiniIndentscope.config| for more information).
--- - Compute border indent as maximum indent of border lines (or reference
---   indent minus one in case of no border). This is used during drawing
---   visual indicator.
---
--- # Indent computation ~
---
--- For every line indent is intended to be computed unambiguously:
--- - For "normal" lines indent is an output of |indent()|.
--- - Indent is `-1` for imaginary lines 0 and past last line.
--- - For blank and empty lines indent is computed based on previous
---   (|prevnonblank()|) and next (|nextnonblank()|) non-blank lines. The way
---   it is computed is decided based on `border` in order to not include blank
---   lines at edge of scope's body if there is no border there. See
---   |MiniIndentscope.config| for a details example.
---
---@param line number|nil Input line number (starts from 1). Can be modified to a
---   neighbor if `try_as_border` is `true`. Default: cursor line.
---@param col number|nil Column number (starts from 1). Default: if
---   `indent_at_cursor` option is `true` - cursor column from `curswant` of
---   |getcurpos()| (allows for more natural behavior on empty lines);
---   `math.huge` otherwise in order to not incorporate cursor in computation.
---@param opts table|nil Options to override global or buffer local ones (see
---   |MiniIndentscope.config|).
---
---@return table Table with scope information:
---   - <body> - table with <top> (top line of scope, inclusive), <bottom>
---     (bottom line of scope, inclusive), and <indent> (minimum indent within
---     scope) keys. Line numbers start at 1. Can also have <is_incomplete> key
---     set to `true` if computation was stopped due to `opts.n_lines` restriction.
---   - <border> - table with <top> (line of top border, might be `nil`),
---     <bottom> (line of bottom border, might be `nil`), and <indent> (indent
---     of border) keys. Line numbers start at 1.
---   - <buf_id> - identifier of current buffer.
---   - <reference> - table with <line> (reference line), <column> (reference
---     column), and <indent> ("indent at column") keys.
MiniIndentscope.get_scope = function(line, col, opts)
  opts = H.get_config({ options = opts }).options

  -- Compute default `line` and\or `col`
  if not (line and col) then
    local curpos = vim.fn.getcurpos()

    line = line or curpos[2]
    line = opts.try_as_border and H.border_correctors[opts.border](line, opts) or line

    -- Use `curpos[5]` (`curswant`, see `:h getcurpos()`) to account for blank
    -- and empty lines.
    col = col or (opts.indent_at_cursor and curpos[5] or math.huge)
  end

  -- Compute "indent at column"
  local line_indent = H.get_line_indent(line, opts)
  local indent = math.min(col, line_indent)

  -- Make early return
  local body = { indent = indent }
  if indent <= 0 then
    body.top, body.bottom, body.indent = 1, vim.fn.line('$'), line_indent
  else
    local up_line, up_min_indent, up_is_incomplete = H.cast_ray(line, indent, 'up', opts)
    local down_line, down_min_indent, down_is_incomplete = H.cast_ray(line, indent, 'down', opts)
    body.top, body.bottom = up_line, down_line
    body.indent = math.min(line_indent, up_min_indent, down_min_indent)
    body.is_incomplete = up_is_incomplete or down_is_incomplete
  end

  return {
    body = body,
    border = H.border_from_body[opts.border](body, opts),
    buf_id = vim.api.nvim_get_current_buf(),
    reference = { line = line, column = col, indent = indent },
  }
end

--- Draw scope manually
---
--- Scope is visualized as a vertical line within scope's body range at column
--- equal to border indent plus one (or body indent if border is absent).
--- Numbering starts from one.
---
---@param scope table|nil Scope. Default: output of |MiniIndentscope.get_scope()|
---   with default arguments.
---@param opts table|nil Options. Currently supported:
---    - <animation_fun> - animation function for drawing. See
---      |MiniIndentscope-drawing| and |MiniIndentscope.gen_animation|.
---    - <priority> - priority number for visualization. See `priority` option
---      for |nvim_buf_set_extmark()|.
MiniIndentscope.draw = function(scope, opts)
  scope = scope or MiniIndentscope.get_scope()
  local config = H.get_config()
  local draw_opts =
    vim.tbl_deep_extend('force', { animation_fun = config.draw.animation, priority = config.draw.priority }, opts or {})

  H.undraw_scope()

  H.current.scope = scope
  H.draw_scope(scope, draw_opts)
end

--- Undraw currently visible scope manually
MiniIndentscope.undraw = function() H.undraw_scope() end

--- Generate builtin animation function
---
--- This is a builtin source to generate animation function for usage in
--- `MiniIndentscope.config.draw.animation`. Most of them are variations of
--- common easing functions, which provide certain type of progression for
--- revealing scope visual indicator.
---
--- Each field corresponds to one family of progression which can be customized
--- further by supplying appropriate arguments.
---
--- Examples:
--- - Don't use animation: `MiniIndentscope.gen_animation.none()`
--- - Use quadratic "out" easing with total duration of 1000 ms: >lua
---
---   gen_animation.quadratic({ easing = 'out', duration = 1000, unit = 'total' })
--- <
---@seealso |MiniIndentscope-drawing| for more information about how drawing is done.
MiniIndentscope.gen_animation = {}

---@alias __indentscope_animation_opts table|nil Options that control progression. Possible keys:
---   - <easing> `(string)` - a subtype of progression. One of "in"
---     (accelerating from zero speed), "out" (decelerating to zero speed),
---     "in-out" (default; accelerating halfway, decelerating after).
---   - <duration> `(number)` - duration (in ms) of a unit. Default: 20.
---   - <unit> `(string)` - which unit's duration `opts.duration` controls. One
---     of "step" (default; ensures average duration of step to be `opts.duration`)
---     or "total" (ensures fixed total duration regardless of scope's range).
---@alias __indentscope_animation_return function Animation function (see |MiniIndentscope-drawing|).

--- Generate no animation
---
--- Show indicator immediately. Same as animation function always returning 0.
MiniIndentscope.gen_animation.none = function()
  return function() return 0 end
end

--- Generate linear progression
---
---@param opts __indentscope_animation_opts
---
---@return __indentscope_animation_return
MiniIndentscope.gen_animation.linear = function(opts)
  return H.animation_arithmetic_powers(0, H.normalize_animation_opts(opts))
end

--- Generate quadratic progression
---
---@param opts __indentscope_animation_opts
---
---@return __indentscope_animation_return
MiniIndentscope.gen_animation.quadratic = function(opts)
  return H.animation_arithmetic_powers(1, H.normalize_animation_opts(opts))
end

--- Generate cubic progression
---
---@param opts __indentscope_animation_opts
---
---@return __indentscope_animation_return
MiniIndentscope.gen_animation.cubic = function(opts)
  return H.animation_arithmetic_powers(2, H.normalize_animation_opts(opts))
end

--- Generate quartic progression
---
---@param opts __indentscope_animation_opts
---
---@return __indentscope_animation_return
MiniIndentscope.gen_animation.quartic = function(opts)
  return H.animation_arithmetic_powers(3, H.normalize_animation_opts(opts))
end

--- Generate exponential progression
---
---@param opts __indentscope_animation_opts
---
---@return __indentscope_animation_return
MiniIndentscope.gen_animation.exponential = function(opts)
  return H.animation_geometrical_powers(H.normalize_animation_opts(opts))
end

--- Move cursor within scope
---
--- Cursor is placed on a first non-blank character of target line.
---
---@param side string One of "top" or "bottom".
---@param use_border boolean|nil Whether to move to border or within scope's body.
---   If particular border is absent, body is used.
---@param scope table|nil Scope to use. Default: output of |MiniIndentscope.get_scope()|.
MiniIndentscope.move_cursor = function(side, use_border, scope)
  scope = scope or MiniIndentscope.get_scope()

  -- This defaults to body's side if it is not present in border
  local target_line = use_border and scope.border[side] or scope.body[side]
  target_line = math.min(math.max(target_line, 1), vim.fn.line('$'))

  vim.api.nvim_win_set_cursor(0, { target_line, 0 })
  -- Move to first non-blank character to allow chaining scopes
  vim.cmd('normal! ^')
end

--- Function for motion mappings
---
--- Move to a certain side of border. Respects |count| and dot-repeat (in
--- operator-pending mode). Doesn't move cursor for scope that is not shown
--- (drawing indent less that zero).
---
---@param side string One of "top" or "bottom".
---@param add_to_jumplist boolean|nil Whether to add movement to jump list. It is
---   `true` only for Normal mode mappings.
MiniIndentscope.operator = function(side, add_to_jumplist)
  local scope = MiniIndentscope.get_scope()

  -- Don't support scope that can't be shown
  if H.scope_get_draw_indent(scope) < 0 then return end

  -- Add movement to jump list. Needs remembering `count1` before that because
  -- it seems to reset it to 1.
  local count = vim.v.count1
  if add_to_jumplist then vim.cmd('normal! m`') end

  -- Make sequence of jumps
  for _ = 1, count do
    MiniIndentscope.move_cursor(side, true, scope)
    -- Use `try_as_border = false` to enable chaining
    scope = MiniIndentscope.get_scope(nil, nil, { try_as_border = false })

    -- Don't support scope that can't be shown
    if H.scope_get_draw_indent(scope) < 0 then return end
  end
end

--- Function for textobject mappings
---
--- Respects |count| and dot-repeat (in operator-pending mode). Doesn't work
--- for scope that is not shown (drawing indent less that zero).
---
---@param use_border boolean|nil Whether to include border in textobject. When
---   `true` and `try_as_border` option is `false`, allows "chaining" calls for
---   incremental selection.
MiniIndentscope.textobject = function(use_border)
  local scope = MiniIndentscope.get_scope()

  -- Don't support scope that can't be shown
  if H.scope_get_draw_indent(scope) < 0 then return end

  -- Allow chaining only if using border
  local count = use_border and vim.v.count1 or 1

  -- Make sequence of incremental selections
  for _ = 1, count do
    -- Try finish cursor on border
    local start, finish = 'top', 'bottom'
    if use_border and scope.border.bottom == nil then
      start, finish = 'bottom', 'top'
    end

    H.exit_visual_mode()
    MiniIndentscope.move_cursor(start, use_border, scope)
    vim.cmd('normal! V')
    MiniIndentscope.move_cursor(finish, use_border, scope)

    -- Use `try_as_border = false` to enable chaining
    scope = MiniIndentscope.get_scope(nil, nil, { try_as_border = false })

    -- Don't support scope that can't be shown
    if H.scope_get_draw_indent(scope) < 0 then return end
  end
end

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniIndentscope.config)

-- Namespace for drawing vertical line
H.ns_id = vim.api.nvim_create_namespace('MiniIndentscope')

-- Timer for doing animation
H.timer = vim.uv.new_timer()

-- Table with current relevalnt data:
-- - `event_id` - counter for events.
-- - `scope` - latest drawn scope.
-- - `draw_status` - status of current drawing.
H.current = { event_id = 0, scope = {}, draw_status = 'none' }

-- Functions to compute indent in ambiguous cases
H.indent_funs = {
  ['min'] = function(top_indent, bottom_indent) return math.min(top_indent, bottom_indent) end,
  ['max'] = function(top_indent, bottom_indent) return math.max(top_indent, bottom_indent) end,
  ['top'] = function(top_indent, bottom_indent) return top_indent end,
  ['bottom'] = function(top_indent, bottom_indent) return bottom_indent end,
}

-- Functions to compute indent of blank line to satisfy `config.options.border`
H.blank_indent_funs = {
  ['none'] = H.indent_funs.min,
  ['top'] = H.indent_funs.bottom,
  ['bottom'] = H.indent_funs.top,
  ['both'] = H.indent_funs.max,
}

-- Functions to compute border from body
H.border_from_body = {
  ['none'] = function(body, opts) return {} end,
  ['top'] = function(body, opts) return { top = body.top - 1, indent = H.get_line_indent(body.top - 1, opts) } end,
  ['bottom'] = function(body, opts)
    return { bottom = body.bottom + 1, indent = H.get_line_indent(body.bottom + 1, opts) }
  end,
  ['both'] = function(body, opts)
    return {
      top = body.top - 1,
      bottom = body.bottom + 1,
      indent = math.max(H.get_line_indent(body.top - 1, opts), H.get_line_indent(body.bottom + 1, opts)),
    }
  end,
}

-- Functions to correct line in case it is a border
H.border_correctors = {
  ['none'] = function(line, opts) return line end,
  ['top'] = function(line, opts)
    local cur_indent, next_indent = H.get_line_indent(line, opts), H.get_line_indent(line + 1, opts)
    return (cur_indent < next_indent) and (line + 1) or line
  end,
  ['bottom'] = function(line, opts)
    local prev_indent, cur_indent = H.get_line_indent(line - 1, opts), H.get_line_indent(line, opts)
    return (cur_indent < prev_indent) and (line - 1) or line
  end,
  ['both'] = function(line, opts)
    local prev_indent, cur_indent, next_indent =
      H.get_line_indent(line - 1, opts), H.get_line_indent(line, opts), H.get_line_indent(line + 1, opts)

    if prev_indent <= cur_indent and next_indent <= cur_indent then return line end

    -- If prev and next indents are equal and bigger than current, prefer next
    if prev_indent <= next_indent then return line + 1 end

    return line - 1
  end,
}

-- Whether or not Nvim supports the virt_text_repeat_linebreak extmark feature
H.has_wrapped_virt_text = vim.fn.has('nvim-0.10') == 1

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  H.check_type('draw', config.draw, 'table')
  H.check_type('draw.delay', config.draw.delay, 'number')
  H.check_type('draw.animation', config.draw.animation, 'function')
  H.check_type('draw.predicate', config.draw.predicate, 'function')
  H.check_type('draw.priority', config.draw.priority, 'number')

  H.check_type('mappings', config.mappings, 'table')
  H.check_type('mappings.object_scope', config.mappings.object_scope, 'string')
  H.check_type('mappings.object_scope_with_border', config.mappings.object_scope_with_border, 'string')
  H.check_type('mappings.goto_top', config.mappings.goto_top, 'string')
  H.check_type('mappings.goto_bottom', config.mappings.goto_bottom, 'string')

  H.check_type('options', config.options, 'table')
  H.check_type('options.border', config.options.border, 'string')
  H.check_type('options.indent_at_cursor', config.options.indent_at_cursor, 'boolean')
  H.check_type('options.n_lines', config.options.n_lines, 'number')
  H.check_type('options.try_as_border', config.options.try_as_border, 'boolean')

  H.check_type('symbol', config.symbol, 'string')

  return config
end

H.apply_config = function(config)
  MiniIndentscope.config = config
  local maps = config.mappings

  --stylua: ignore start
  H.map('n', maps.goto_top, [[<Cmd>lua MiniIndentscope.operator('top', true)<CR>]], { desc = 'Go to indent scope top' })
  H.map('n', maps.goto_bottom, [[<Cmd>lua MiniIndentscope.operator('bottom', true)<CR>]], { desc = 'Go to indent scope bottom' })

  H.map('x', maps.goto_top, [[<Cmd>lua MiniIndentscope.operator('top')<CR>]], { desc = 'Go to indent scope top' })
  H.map('x', maps.goto_bottom, [[<Cmd>lua MiniIndentscope.operator('bottom')<CR>]], { desc = 'Go to indent scope bottom' })
  H.map('x', maps.object_scope, '<Cmd>lua MiniIndentscope.textobject(false)<CR>', { desc = 'Object scope' })
  H.map('x', maps.object_scope_with_border, '<Cmd>lua MiniIndentscope.textobject(true)<CR>', { desc = 'Object scope with border' })

  -- Use `<Cmd>...<CR>` to have proper dot-repeat
  -- See https://github.com/neovim/neovim/issues/23406
  -- TODO: use local functions if/when that issue is resolved
  H.map('o', maps.goto_top, [[<Cmd>lua MiniIndentscope.operator('top')<CR>]], { desc = 'Go to indent scope top' })
  H.map('o', maps.goto_bottom, [[<Cmd>lua MiniIndentscope.operator('bottom')<CR>]], { desc = 'Go to indent scope bottom' })
  H.map('o', maps.object_scope, '<Cmd>lua MiniIndentscope.textobject(false)<CR>', { desc = 'Object scope' })
  H.map('o', maps.object_scope_with_border, '<Cmd>lua MiniIndentscope.textobject(true)<CR>', { desc = 'Object scope with border' })
  --stylua: ignore start
end

H.create_autocommands = function()
  local gr = vim.api.nvim_create_augroup('MiniIndentscope', {})

  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = gr, pattern = pattern, callback = callback, desc = desc })
  end

  local lazy_events = { 'CursorMoved', 'CursorMovedI', 'ModeChanged' }
  au(lazy_events, '*', function() H.auto_draw({ lazy = true }) end, 'Auto draw indentscope lazily')
  local now_events = { 'TextChanged', 'TextChangedI', 'TextChangedP', 'WinScrolled' }
  au(now_events, '*', function() H.auto_draw() end, 'Auto draw indentscope')

  au('ColorScheme', '*', H.create_default_hl, 'Ensure colors')
end

--stylua: ignore
H.create_default_hl = function()
  vim.api.nvim_set_hl(0, 'MiniIndentscopeSymbol',    { default = true, link = 'Delimiter' })
  vim.api.nvim_set_hl(0, 'MiniIndentscopeSymbolOff', { default = true, link = 'MiniIndentscopeSymbol' })
end

H.is_disabled = function() return vim.g.miniindentscope_disable == true or vim.b.miniindentscope_disable == true end

H.get_config = function(config)
  return vim.tbl_deep_extend('force', MiniIndentscope.config, vim.b.miniindentscope_config or {}, config or {})
end

-- Autocommands ---------------------------------------------------------------
H.auto_draw = function(opts)
  if H.is_disabled() then
    H.undraw_scope()
    return
  end

  opts = opts or {}
  local scope = MiniIndentscope.get_scope()

  -- Make early return if nothing has to be done. Doing this before updating
  -- event id allows to not interrupt ongoing animation.
  if opts.lazy and H.current.draw_status ~= 'none' and H.scope_is_equal(scope, H.current.scope) then return end

  -- Account for current event
  local local_event_id = H.current.event_id + 1
  H.current.event_id = local_event_id

  -- Compute drawing options for current event
  local draw_opts = H.make_autodraw_opts(scope)

  -- Allow delay
  if draw_opts.delay > 0 then H.undraw_scope(draw_opts) end

  -- Use `defer_fn()` even if `delay` is 0 to draw indicator only after all
  -- events are processed (stops flickering)
  vim.defer_fn(function()
    if H.current.event_id ~= local_event_id then return end

    H.undraw_scope(draw_opts)

    -- Don't autodraw if not asked to
    if not H.get_config().draw.predicate(scope) then return end

    H.current.scope = scope
    H.draw_scope(scope, draw_opts)
  end, draw_opts.delay)
end

-- Scope ----------------------------------------------------------------------
-- Line indent:
-- - Equals output of `vim.fn.indent()` in case of non-blank line.
-- - Depends on `MiniIndentscope.config.options.border` in such way so as to
--   ignore blank lines before line not recognized as border.
H.get_line_indent = function(line, opts)
  local prev_nonblank = vim.fn.prevnonblank(line)
  local res = vim.fn.indent(prev_nonblank)

  -- Compute indent of blank line depending on `border` option
  local border = opts.border
  if line ~= prev_nonblank then
    local next_indent = vim.fn.indent(vim.fn.nextnonblank(line))
    local blank_rule = H.blank_indent_funs[border]
    res = blank_rule(res, next_indent)
  end

  return res
end

H.cast_ray = function(line, indent, direction, opts)
  local final_line, increment = 1, -1
  if direction == 'down' then
    final_line, increment = vim.fn.line('$'), 1
  end

  local is_incomplete
  if math.abs(line - final_line) > opts.n_lines then
    final_line, is_incomplete = line + increment * opts.n_lines, true
  end

  local min_indent = math.huge
  for l = line, final_line, increment do
    local new_indent = H.get_line_indent(l + increment, opts)
    if new_indent < indent then return l, min_indent, nil end
    if new_indent < min_indent then min_indent = new_indent end
  end

  return final_line, min_indent, is_incomplete
end

H.scope_get_draw_indent = function(scope) return scope.border.indent or (scope.body.indent - 1) end

H.scope_is_equal = function(scope_1, scope_2)
  if type(scope_1) ~= 'table' or type(scope_2) ~= 'table' then return false end

  return scope_1.buf_id == scope_2.buf_id
    and H.scope_get_draw_indent(scope_1) == H.scope_get_draw_indent(scope_2)
    and scope_1.body.top == scope_2.body.top
    and scope_1.body.bottom == scope_2.body.bottom
    and scope_1.body.is_incomplete == scope_2.body.is_incomplete
end

H.scope_has_intersect = function(scope_1, scope_2)
  if type(scope_1) ~= 'table' or type(scope_2) ~= 'table' then return false end
  if (scope_1.buf_id ~= scope_2.buf_id) or (H.scope_get_draw_indent(scope_1) ~= H.scope_get_draw_indent(scope_2)) then
    return false
  end

  local body_1, body_2 = scope_1.body, scope_2.body
  return (body_2.top <= body_1.top and body_1.top <= body_2.bottom)
    or (body_1.top <= body_2.top and body_2.top <= body_1.bottom)
end

-- Indicator ------------------------------------------------------------------
--- Compute indicator of scope to be displayed
---
--- Indicator is visual representation of scope in current window view using
--- extmarks. Currently only needed because Neovim can't correctly process
--- horizontal window scroll (Neovim issue:
--- https://github.com/neovim/neovim/issues/14050)
---
---@return table|nil Table with indicator info or empty one in case indicator
---   shouldn't be drawn.
---@private
H.indicator_compute = function(scope)
  scope = scope or H.current.scope
  local indent = H.scope_get_draw_indent(scope)

  -- Don't draw indicator that should be outside of screen. This condition is
  -- (perpusfully) "responsible" for not drawing indicator spanning whole file.
  if indent < 0 then return {} end

  -- Text indentation should depend on current window view because it will use
  -- `virt_text_win_col` attribute of extmark options (the only way to reliably
  -- put it anywhere on screen; important to show properly on empty lines).
  local col = indent - vim.fn.winsaveview().leftcol
  if col < 0 then return {} end

  -- Pick highlight group based on if indent is a multiple of shiftwidth.
  -- This adds visual indicator of whether indent is "correct".
  local hl_group = (indent % vim.fn.shiftwidth() == 0) and 'MiniIndentscopeSymbol' or 'MiniIndentscopeSymbolOff'
  local virt_text = { { H.get_config().symbol, hl_group } }

  return {
    buf_id = vim.api.nvim_get_current_buf(),
    virt_text = virt_text,
    virt_text_win_col = col,
    top = scope.body.top,
    bottom = scope.body.bottom,
  }
end

-- Drawing --------------------------------------------------------------------
H.draw_scope = function(scope, opts)
  scope = scope or {}
  opts = opts or {}

  local indicator = H.indicator_compute(scope)

  -- Don't draw anything if nothing to be displayed
  if indicator.virt_text == nil or #indicator.virt_text == 0 then
    H.current.draw_status = 'finished'
    return
  end

  -- Make drawing function
  local draw_fun = H.make_draw_function(indicator, opts)

  -- Perform drawing
  H.current.draw_status = 'drawing'
  H.draw_indicator_animation(indicator, draw_fun, opts.animation_fun)
end

H.draw_indicator_animation = function(indicator, draw_fun, animation_fun)
  -- Draw from origin (cursor line but within indicator range)
  local top, bottom = indicator.top, indicator.bottom
  local origin = math.min(math.max(vim.fn.line('.'), top), bottom)

  local step = 0
  local n_steps = math.max(origin - top, bottom - origin)
  local wait_time = 0

  local draw_step
  draw_step = vim.schedule_wrap(function()
    -- Check for not drawing outside of interval is done inside `draw_fun`
    local success = draw_fun(origin - step)
    if step > 0 then success = success and draw_fun(origin + step) end

    if not success or step == n_steps then
      H.current.draw_status = step == n_steps and 'finished' or H.current.draw_status
      H.timer:stop()
      return
    end

    step = step + 1
    wait_time = wait_time + animation_fun(step, n_steps)

    -- Repeat value of `timer` seems to be rounded down to milliseconds. This
    -- means that values less than 1 will lead to timer stop repeating. Instead
    -- call next step function directly.
    if wait_time < 1 then
      H.timer:set_repeat(0)
      -- Use `return` to make this proper "tail call"
      return draw_step()
    else
      H.timer:set_repeat(wait_time)

      -- Restart `wait_time` only if it is actually used. Do this accounting
      -- actually set repeat time.
      wait_time = wait_time - H.timer:get_repeat()

      -- Usage of `again()` is needed to overcome the fact that it is called
      -- inside callback and to restart initial timer. Mainly this is needed
      -- only in case of transition from 'non-repeating' timer to 'repeating'
      -- one in case of complex animation functions. See
      -- https://docs.libuv.org/en/v1.x/timer.html#api
      H.timer:again()
    end
  end)

  -- Start non-repeating timer without callback execution. This shouldn't be
  -- `timer:start(0, 0, draw_step)` because it will execute `draw_step` on the
  -- next redraw (flickers on window scroll).
  H.timer:start(10000000, 0, draw_step)

  -- Draw step zero (at origin) immediately
  draw_step()
end

H.undraw_scope = function(opts)
  opts = opts or {}

  -- Don't operate outside of current event if able to verify
  if opts.event_id and opts.event_id ~= H.current.event_id then return end

  pcall(vim.api.nvim_buf_clear_namespace, H.current.scope.buf_id or 0, H.ns_id, 0, -1)

  H.current.draw_status = 'none'
  H.current.scope = {}
end

H.make_autodraw_opts = function(scope)
  local config = H.get_config()
  local res = {
    event_id = H.current.event_id,
    type = 'animation',
    delay = config.draw.delay,
    animation_fun = config.draw.animation,
    priority = config.draw.priority,
  }

  if H.current.draw_status == 'none' then return res end

  -- Draw immediately scope which intersects (same indent, overlapping ranges)
  -- currently drawn or finished. This is more natural when typing text.
  if H.scope_has_intersect(scope, H.current.scope) then
    res.type = 'immediate'
    res.delay = 0
    res.animation_fun = MiniIndentscope.gen_animation.none()
    return res
  end

  return res
end

H.make_draw_function = function(indicator, opts)
  local extmark_opts = {
    hl_mode = 'combine',
    priority = opts.priority,
    right_gravity = false,
    virt_text = indicator.virt_text,
    virt_text_win_col = indicator.virt_text_win_col,
    virt_text_pos = 'overlay',
  }

  if H.has_wrapped_virt_text and vim.wo.breakindent and vim.wo.showbreak == '' then
    extmark_opts.virt_text_repeat_linebreak = true
  end

  local current_event_id = opts.event_id

  return function(l)
    -- Don't draw if outdated
    if H.current.event_id ~= current_event_id and current_event_id ~= nil then return false end

    -- Don't draw if disabled
    if H.is_disabled() then return false end

    -- Don't put extmark outside of indicator range
    if not (indicator.top <= l and l <= indicator.bottom) then return true end

    return pcall(vim.api.nvim_buf_set_extmark, indicator.buf_id, H.ns_id, l - 1, 0, extmark_opts)
  end
end

-- Animations -----------------------------------------------------------------
--- Imitate common power easing function
---
--- Every step is preceded by waiting time decreasing/increasing in power
--- series fashion (`d` is "delta", ensures total duration time):
--- - "in":  d*n^p; d*(n-1)^p; ... ; d*2^p;     d*1^p
--- - "out": d*1^p; d*2^p;     ... ; d*(n-1)^p; d*n^p
--- - "in-out": "in" until 0.5*n, "out" afterwards
---
--- This way it imitates `power + 1` common easing function because animation
--- progression behaves as sum of `power` elements.
---
---@param power number Power of series.
---@param opts table Options from `MiniIndentscope.gen_animation` entry.
---@private
H.animation_arithmetic_powers = function(power, opts)
  -- Sum of first `n_steps` natural numbers raised to `power`
  local arith_power_sum = ({
    [0] = function(n_steps) return n_steps end,
    [1] = function(n_steps) return n_steps * (n_steps + 1) / 2 end,
    [2] = function(n_steps) return n_steps * (n_steps + 1) * (2 * n_steps + 1) / 6 end,
    [3] = function(n_steps) return n_steps ^ 2 * (n_steps + 1) ^ 2 / 4 end,
  })[power]

  -- Function which computes common delta so that overall duration will have
  -- desired value (based on supplied `opts`)
  local duration_unit, duration_value = opts.unit, opts.duration
  local make_delta = function(n_steps, is_in_out)
    local total_time = duration_unit == 'total' and duration_value or (duration_value * n_steps)
    local total_parts
    if is_in_out then
      -- Examples:
      -- - n_steps=5: 3^d, 2^d, 1^d, 2^d, 3^d
      -- - n_steps=6: 3^d, 2^d, 1^d, 1^d, 2^d, 3^d
      total_parts = 2 * arith_power_sum(math.ceil(0.5 * n_steps)) - (n_steps % 2 == 1 and 1 or 0)
    else
      total_parts = arith_power_sum(n_steps)
    end
    return total_time / total_parts
  end

  return ({
    ['in'] = function(s, n) return make_delta(n) * (n - s + 1) ^ power end,
    ['out'] = function(s, n) return make_delta(n) * s ^ power end,
    ['in-out'] = function(s, n)
      local n_half = math.ceil(0.5 * n)
      local s_halved
      if n % 2 == 0 then
        s_halved = s <= n_half and (n_half - s + 1) or (s - n_half)
      else
        s_halved = s < n_half and (n_half - s + 1) or (s - n_half + 1)
      end
      return make_delta(n, true) * s_halved ^ power
    end,
  })[opts.easing]
end

--- Imitate common exponential easing function
---
--- Every step is preceded by waiting time decreasing/increasing in geometric
--- progression fashion (`d` is 'delta', ensures total duration time):
--- - 'in':  (d-1)*d^(n-1); (d-1)*d^(n-2); ...; (d-1)*d^1;     (d-1)*d^0
--- - 'out': (d-1)*d^0;     (d-1)*d^1;     ...; (d-1)*d^(n-2); (d-1)*d^(n-1)
--- - 'in-out': 'in' until 0.5*n, 'out' afterwards
---
---@param opts table Options from `MiniIndentscope.gen_animation` entry.
---@private
H.animation_geometrical_powers = function(opts)
  -- Function which computes common delta so that overall duration will have
  -- desired value (based on supplied `opts`)
  local duration_unit, duration_value = opts.unit, opts.duration
  local make_delta = function(n_steps, is_in_out)
    local total_time = duration_unit == 'step' and (duration_value * n_steps) or duration_value
    -- Exact solution to avoid possible (bad) approximation
    if n_steps == 1 then return total_time + 1 end
    if is_in_out then
      local n_half = math.ceil(0.5 * n_steps)
      -- Example for n_steps=6:
      -- Steps: (d-1)*d^2, (d-1)*d^1, (d-1)*d^0, (d-1)*d^0, (d-1)*d^1, (d-1)*d^2
      -- Sum: 2 * (d - 1) * (d^0 + d^1 + d^2) = 2 * (d^3 - 1)
      -- Solution: 2 * (d^3 - 1) = total_time =>
      --   d = math.pow(0.5 * total_time + 1, 1 / 3)
      --
      -- Example for n_steps=5:
      -- Steps: (d-1)*d^2, (d-1)*d^1, (d-1)*d^0, (d-1)*d^1, (d-1)*d^2
      -- Sum: 2 * (d - 1) * (d^0 + d^1 + d^2) - (d - 1) = 2 * (d^3 - 1) - (d - 1)
      -- Solution: 2 * (d^3 - 1) - (d - 1) = total_time =>
      --   As there is no general explicit solution, use approximation =>
      --   (Exact solution without `- (d-1)`):
      --     d_0 = math.pow(0.5 * total_time + 1, 1 / 3);
      --   (Correction by solving exactly withtou `- (d-1)` for
      --   `total_time_corr = total_time + (d_0 - 1)`):
      --     d_1 = math.pow(0.5 * total_time_corr + 1, 1 / 3)
      if n_steps % 2 == 1 then total_time = total_time + math.pow(0.5 * total_time + 1, 1 / n_half) - 1 end
      return math.pow(0.5 * total_time + 1, 1 / n_half)
    end
    return math.pow(total_time + 1, 1 / n_steps)
  end

  return ({
    ['in'] = function(s, n)
      local delta = make_delta(n)
      return (delta - 1) * delta ^ (n - s)
    end,
    ['out'] = function(s, n)
      local delta = make_delta(n)
      return (delta - 1) * delta ^ (s - 1)
    end,
    ['in-out'] = function(s, n)
      local n_half, delta = math.ceil(0.5 * n), make_delta(n, true)
      local s_halved
      if n % 2 == 0 then
        s_halved = s <= n_half and (n_half - s) or (s - n_half - 1)
      else
        s_halved = s < n_half and (n_half - s) or (s - n_half)
      end
      return (delta - 1) * delta ^ s_halved
    end,
  })[opts.easing]
end

H.normalize_animation_opts = function(x)
  x = vim.tbl_deep_extend('force', { easing = 'in-out', duration = 20, unit = 'step' }, x or {})

  if not vim.tbl_contains({ 'in', 'out', 'in-out' }, x.easing) then
    H.error([[In `gen_animation` option `easing` should be one of 'in', 'out', or 'in-out'.]])
  end

  if type(x.duration) ~= 'number' or x.duration < 0 then
    H.error([[In `gen_animation` option `duration` should be a positive number.]])
  end

  if not vim.tbl_contains({ 'total', 'step' }, x.unit) then
    H.error([[In `gen_animation` option `unit` should be one of 'step' or 'total'.]])
  end

  return x
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.indentscope) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.map = function(mode, lhs, rhs, opts)
  if lhs == '' then return end
  opts = vim.tbl_deep_extend('force', { silent = true }, opts or {})
  vim.keymap.set(mode, lhs, rhs, opts)
end

H.exit_visual_mode = function()
  local ctrl_v = vim.api.nvim_replace_termcodes('<C-v>', true, true, true)
  local cur_mode = vim.fn.mode()
  if cur_mode == 'v' or cur_mode == 'V' or cur_mode == ctrl_v then vim.cmd('normal! ' .. cur_mode) end
end

return MiniIndentscope
