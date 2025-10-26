--- *mini.bracketed* Go forward/backward with square brackets
---
--- MIT License Copyright (c) 2023 Evgeni Chasnovski

--- Features:
--- - Configurable Lua functions to go forward/backward to a certain target.
---   Each function can be customized with:
---     - Direction. One of "forward", "backward", "first" (forward starting
---       from first one), "last" (backward starting from last one).
---     - Number of times to go.
---     - Whether to wrap on edges (going forward on last one goes to first).
---     - Some other target specific options.
---
--- - Mappings using square brackets. They are created using configurable
---   target suffix and can be selectively disabled.
---
---   Each mapping supports |[count]|. Mappings are created in Normal mode; for
---   targets which move cursor in current buffer also Visual and
---   Operator-pending (with dot-repeat) modes are supported.
---
---   Using `lower-suffix` and `upper-suffix` (lower and upper case suffix) for
---   a single target the following mappings are created:
---     - `[` + `upper-suffix` : go first.
---     - `[` + `lower-suffix` : go backward.
---     - `]` + `lower-suffix` : go forward.
---     - `]` + `upper-suffix` : go last.
---
--- - Supported targets (for more information see help for corresponding Lua
---   function):
---
---   `Target`                           `Mappings`         `Lua function`
---   Buffer ......................... `[B` `[b` `]b` `]B` .... |MiniBracketed.buffer()|
---   Comment block .................. `[C` `[c` `]c` `]C` .... |MiniBracketed.comment()|
---   Conflict marker ................ `[X` `[x` `]x` `]X` .... |MiniBracketed.conflict()|
---   Diagnostic ..................... `[D` `[d` `]d` `]D` .... |MiniBracketed.diagnostic()|
---   File on disk ................... `[F` `[f` `]f` `]F` .... |MiniBracketed.file()|
---   Indent change .................. `[I` `[i` `]i` `]I` .... |MiniBracketed.indent()|
---   Jump inside current buffer ..... `[J` `[j` `]j` `]J` .... |MiniBracketed.jump()|
---   Location from |location-list| .... `[L` `[l` `]l` `]L` .... |MiniBracketed.location()|
---   Old files ...................... `[O` `[o` `]o` `]O` .... |MiniBracketed.oldfile()|
---   Quickfix entry from |Quickfix| ... `[Q` `[q` `]q` `]Q` .... |MiniBracketed.quickfix()|
---   Tree-sitter node and parents ... `[T` `[t` `]t` `]T` .... |MiniBracketed.treesitter()|
---   Undo from linear history ....... `[U` `[u` `]u` `]U` .... |MiniBracketed.undo()|
---   Window in current tab .......... `[W` `[w` `]w` `]W` .... |MiniBracketed.window()|
---   Yank entry over put region ..... `[Y` `[y` `]y` `]Y` .... |MiniBracketed.yank()|
---
--- Notes:
--- - The `undo` target remaps |u| and |CTRL-R| keys to register undo state
---   after undo and redo respectively. If this conflicts with your setup,
---   either disable `undo` target or make your remaps after calling
---   |MiniBracketed.setup()|. To use `undo` target, remap your undo/redo keys
---   to call |MiniBracketed.register_undo_state()| after the action.
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.bracketed').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `MiniBracketed`
--- which you can use for scripting or manually (with `:lua MiniBracketed.*`).
---
--- See |MiniBracketed.config| for available config settings.
---
--- You can override runtime config settings (like target options) locally
--- to buffer inside `vim.b.minibracketed_config` which should have same structure
--- as `MiniBracketed.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- # Comparisons ~
---
--- - [tpope/vim-unimpaired](https://github.com/tpope/vim-unimpaired):
---     - Supports buffer, conflict, file, location, and quickfix targets mostly
---       via built-in commands (like |:bprevious|, etc.) without configuration.
---     - Supports files from argument list and tags. This module does not.
---     - Doesn't support most other this module's targets (comment, indent, ...).
--- - |mini.indentscope|:
---     - Target |MiniBracketed.indent()| target can go to "first" and "last"
---       indent change. It also can go not only to line with smaller indent,
---       but also bigger or different one.
---     - Mappings from 'mini.indentscope' have more flexibility in computation of
---       indent scope, like how to treat empty lines near border or whether to
---       compute indent at cursor.
---
--- # Disabling ~
---
--- To disable, set `vim.g.minibracketed_disable` (globally) or
--- `vim.b.minibracketed_disable` (for a buffer) to `true`. Considering high
--- number of different scenarios and customization intentions, writing exact
--- rules for disabling module's functionality is left to user. See
--- |mini.nvim-disabling-recipes| for common recipes.
---@tag MiniBracketed

---@diagnostic disable:luadoc-miss-type-name
---@alias __bracketed_direction string One of "first", "backward", "forward", "last".
---@alias __bracketed_add_to_jumplist - <add_to_jumplist> (`boolean`) - Whether to add current position to jumplist.
---     Default: `false`.
---@alias __bracketed_opts table|nil Options. A table with fields:
---   - <n_times> `(number)` - Number of times to advance. Default: |v:count1|.
---   - <wrap> `(boolean)` - Whether to wrap around edges. Default: `true`.

---@diagnostic disable:undefined-field

-- Module definition ==========================================================
local MiniBracketed = {}
local H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniBracketed.config|.
---
---@usage >lua
---   require('mini.bracketed').setup() -- use default config
---   -- OR
---   require('mini.bracketed').setup({}) -- replace {} with your config table
--- <
MiniBracketed.setup = function(config)
  -- Export module
  _G.MiniBracketed = MiniBracketed

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Define behavior
  H.create_autocommands()
end

--stylua: ignore
--- Defaults ~
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text Options ~
---
--- Each entry configures target with the same name and can have data configuring
--- mapping suffix and target options.
---
--- Example of configuration: >lua
---
---   require('mini.bracketed').setup({
---     -- Map [N, [n, ]n, ]N for conflict marker like in 'tpope/vim-unimpaired'
---     conflict = { suffix = 'n' },
---
---     -- Make diagnostic advance only by errors
---     diagnostic = { options = { severity = vim.diagnostic.severity.ERROR } },
---
---     -- Disable creation of mappings for `indent` target (for example,
---     -- in favor of ones from |mini.indentscope|)
---     indent = { suffix = '' },
---
---     -- Disable mappings for `window` target in favor of custom ones
---     window = { suffix = '' },
---   })
---
---   -- Create custom `window` mappings
---   local map = vim.keymap.set
---   map('n', '<Leader>wH', "<Cmd>lua MiniBracketed.window('first')<CR>")
---   map('n', '<Leader>wh', "<Cmd>lua MiniBracketed.window('backward')<CR>")
---   map('n', '<Leader>wl', "<Cmd>lua MiniBracketed.window('forward')<CR>")
---   map('n', '<Leader>wL', "<Cmd>lua MiniBracketed.window('last')<CR>")
--- <
--- ## Suffix ~
---
--- The `suffix` key is used to create target mappings.
---
--- Supply empty string to disable mapping creation for that particular target.
--- To create a completely different mapping (like with |<Leader>|) use target
--- function manually.
---
--- Using `lower-suffix` and `upper-suffix` (lower and upper case suffix) for
--- a single target the following mappings are created:
--- - `[` + `upper-suffix` : go first.
--- - `[` + `lower-suffix` : go backward.
--- - `]` + `lower-suffix` : go forward.
--- - `]` + `upper-suffix` : go last.
---
--- When supplied with a non-letter, only forward/backward mappings are created.
---
--- ## Options ~
---
--- The `options` key is directly forwarded as `opts` to corresponding Lua function.
MiniBracketed.config = {
  -- First-level elements are tables describing behavior of a target:
  --
  -- - <suffix> - single character suffix. Used after `[` / `]` in mappings.
  --   For example, with `b` creates `[B`, `[b`, `]b`, `]B` mappings.
  --   Supply empty string `''` to not create mappings.
  --
  -- - <options> - table overriding target options.
  --
  -- See `:h MiniBracketed.config` for more info.

  buffer     = { suffix = 'b', options = {} },
  comment    = { suffix = 'c', options = {} },
  conflict   = { suffix = 'x', options = {} },
  diagnostic = { suffix = 'd', options = {} },
  file       = { suffix = 'f', options = {} },
  indent     = { suffix = 'i', options = {} },
  jump       = { suffix = 'j', options = {} },
  location   = { suffix = 'l', options = {} },
  oldfile    = { suffix = 'o', options = {} },
  quickfix   = { suffix = 'q', options = {} },
  treesitter = { suffix = 't', options = {} },
  undo       = { suffix = 'u', options = {} },
  window     = { suffix = 'w', options = {} },
  yank       = { suffix = 'y', options = {} },
}
--minidoc_afterlines_end

--- Listed buffer
---
--- Go to next/previous listed buffer. Order by their number (see |bufnr()|).
---
--- Direction "forward" increases number, "backward" - decreases.
---
---@param direction __bracketed_direction
---@param opts __bracketed_opts
MiniBracketed.buffer = function(direction, opts)
  if H.is_disabled() then return end

  H.validate_direction(direction, { 'first', 'backward', 'forward', 'last' }, 'buffer')
  opts =
    vim.tbl_deep_extend('force', { n_times = vim.v.count1, wrap = true }, H.get_config().buffer.options, opts or {})

  -- Define iterator that traverses all valid listed buffers
  -- (should be same as `:bnext` / `:bprev`)
  local buf_list = vim.api.nvim_list_bufs()
  local is_listed = function(buf_id) return vim.api.nvim_buf_is_valid(buf_id) and vim.bo[buf_id].buflisted end

  local iterator = {}

  iterator.next = function(buf_id)
    for id = buf_id + 1, buf_list[#buf_list] do
      if is_listed(id) then return id end
    end
  end

  iterator.prev = function(buf_id)
    for id = buf_id - 1, buf_list[1], -1 do
      if is_listed(id) then return id end
    end
  end

  iterator.state = vim.api.nvim_get_current_buf()
  iterator.start_edge = buf_list[1] - 1
  iterator.end_edge = buf_list[#buf_list] + 1

  -- Iterate
  local res_buf_id = MiniBracketed.advance(iterator, direction, opts)
  if res_buf_id == iterator.state then return end

  -- Apply
  vim.api.nvim_set_current_buf(res_buf_id)
end

--- Comment block
---
--- Go to next/previous comment block. Only linewise comments using
--- 'commentsring' are recognized.
---
--- Direction "forward" increases line number, "backward" - decreases.
---
---@param direction __bracketed_direction
---@param opts __bracketed_opts
---   __bracketed_add_to_jumplist
---   - <block_side> `(string)` - which side of comment block to use. One of
---     "near" (default; use nearest side), "start" (use first line), "end"
---     (use last line), "both" (use both first and last lines).
MiniBracketed.comment = function(direction, opts)
  if H.is_disabled() then return end

  H.validate_direction(direction, { 'first', 'backward', 'forward', 'last' }, 'comment')
  opts = vim.tbl_deep_extend(
    'force',
    { add_to_jumplist = false, block_side = 'near', n_times = vim.v.count1, wrap = true },
    H.get_config().comment.options,
    opts or {}
  )

  -- Compute loop data to traverse target commented lines in current buffer
  local is_commented = H.make_comment_checker()
  if is_commented == nil then return end

  local predicate = ({
    near = function(_, cur, _, recent) return cur and not recent end,
    start = function(above, cur, _, _) return cur and not above end,
    ['end'] = function(_, cur, below, _) return cur and not below end,
    both = function(above, cur, below, _) return cur and not (above and below) end,
  })[opts.block_side]
  if predicate == nil then return end

  -- Define iterator
  local iterator = {}

  local n_lines = vim.api.nvim_buf_line_count(0)
  iterator.next = function(line_num)
    local above, cur = is_commented(line_num), is_commented(line_num + 1)
    for lnum = line_num + 1, n_lines do
      local below = is_commented(lnum + 1)
      if predicate(above, cur, below, above) then return lnum end
      above, cur = cur, below
    end
  end

  iterator.prev = function(line_num)
    local cur, below = is_commented(line_num - 1), is_commented(line_num)
    for lnum = line_num - 1, 1, -1 do
      local above = is_commented(lnum - 1)
      if predicate(above, cur, below, below) then return lnum end
      below, cur = cur, above
    end
  end

  iterator.state = vim.fn.line('.')
  iterator.start_edge = 0
  iterator.end_edge = n_lines + 1

  -- Iterate
  local res_line_num = MiniBracketed.advance(iterator, direction, opts)
  local is_outside = res_line_num <= 0 or n_lines < res_line_num
  if res_line_num == nil or res_line_num == iterator.state or is_outside then return end

  -- Possibly add current position to jumplist
  if opts.add_to_jumplist then H.add_to_jumplist() end

  -- Apply. Open just enough folds and put cursor on first non-blank.
  H.set_cursor(res_line_num, 0)
  vim.cmd('normal! zv^')
end

--- Git conflict marker
---
--- Go to next/previous lines containing Git conflict marker. That is, if it
--- starts with "<<<<<<< ", ">>>>>>> ", or is "=======".
---
--- Direction "forward" increases line number, "backward" - decreases.
---
--- Notes:
--- - Using this target in Operator-pending mode allows the following approach
---   at resolving merge conflicts:
---     - Place cursor on `=======` line.
---     - Execute one of these: `d]x[xdd` (choose upper part) or
---       `d[x]xdd` (choose lower part).
---
---@param direction __bracketed_direction
---@param opts __bracketed_opts
---   __bracketed_add_to_jumplist
MiniBracketed.conflict = function(direction, opts)
  if H.is_disabled() then return end

  H.validate_direction(direction, { 'first', 'backward', 'forward', 'last' }, 'conflict')
  opts = vim.tbl_deep_extend(
    'force',
    { add_to_jumplist = false, n_times = vim.v.count1, wrap = true },
    H.get_config().conflict.options,
    opts or {}
  )

  -- Define iterator that traverses all conflict markers in current buffer
  local n_lines = vim.api.nvim_buf_line_count(0)

  local iterator = {}

  iterator.next = function(line_num)
    for lnum = line_num + 1, n_lines do
      if H.is_conflict_mark(lnum) then return lnum end
    end
  end

  iterator.prev = function(line_num)
    for lnum = line_num - 1, 1, -1 do
      if H.is_conflict_mark(lnum) then return lnum end
    end
  end

  iterator.state = vim.fn.line('.')
  iterator.start_edge = 0
  iterator.end_edge = n_lines + 1

  -- Iterate
  local res_line_num = MiniBracketed.advance(iterator, direction, opts)
  local is_outside = res_line_num <= 0 or n_lines < res_line_num
  if res_line_num == nil or res_line_num == iterator.state or is_outside then return end

  -- Possibly add current position to jumplist
  if opts.add_to_jumplist then H.add_to_jumplist() end

  -- Apply. Open just enough folds and put cursor on first non-blank.
  H.set_cursor(res_line_num, 0)
  vim.cmd('normal! zv^')
end

--- Diagnostic
---
--- Go to next/previous diagnostic. This is mostly similar to built-in
--- |vim.diagnostic.jump()| (on Neovim<0.11 it is |vim.diagnostic.goto_next()| and
--- |vim.diagnostic.goto_prev()|) which has an interface and behavior
--- consistent with other methods of the module.
---
--- Direction "forward" increases line number, "backward" - decreases.
---
--- Notes:
--- - Using `severity` option, this target can be used in mappings like "go to
---   next/previous error" (), etc. Using code similar to this: >lua
---
---   local severity_error = vim.diagnostic.severity.ERROR
---   -- Use these inside custom mappings
---   MiniBracketed.diagnostic('forward', { severity = severity_error })
---   MiniBracketed.diagnostic('backward', { severity = severity_error })
--- <
---@param direction __bracketed_direction
---@param opts __bracketed_opts
---   - <float> `(boolean|table)` - control floating window after movement.
---     For available values see |vim.diagnostic.goto_next()|.
---   - <severity> `(string|table)` - which severity to use.
---     For available values see |diagnostic-severity|.
MiniBracketed.diagnostic = function(direction, opts)
  if H.is_disabled() then return end

  H.validate_direction(direction, { 'first', 'backward', 'forward', 'last' }, 'diagnostic')
  local default_opts = { float = vim.diagnostic.config().float, n_times = vim.v.count1, severity = nil, wrap = true }
  local buf_id = vim.api.nvim_get_current_buf()
  if vim.is_callable(default_opts.float) then default_opts.float = default_opts.float(nil, buf_id) end
  opts = vim.tbl_extend('force', default_opts, H.get_config().diagnostic.options, opts or {})

  -- Define iterator that traverses all diagnostic entries in current buffer
  local to_cursor_pos = function(pos) return { pos[1] + 1, pos[2] } end
  local pos_field = vim.fn.has('nvim-0.11') == 1 and 'pos' or 'cursor_position'
  local iterator = {}

  iterator.next = function(position)
    local next_opts = { [pos_field] = to_cursor_pos(position), severity = opts.severity, wrap = false }
    local next = vim.diagnostic.get_next(next_opts)
    if next == nil then return end
    return { next.lnum, next.col }
  end

  iterator.prev = function(position)
    local prev_opts = { [pos_field] = to_cursor_pos(position), severity = opts.severity, wrap = false }
    local prev = vim.diagnostic.get_prev(prev_opts)
    if prev == nil then return end
    return { prev.lnum, prev.col }
  end

  -- - Define states with zero-based indexing as used in `vim.diagnostic`.
  -- - Go outside of proper buffer position for `start_edge` and `end_edge` to
  --   correctly spot diagnostic entry right and start and end of buffer.
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  iterator.state = { cursor_pos[1] - 1, cursor_pos[2] }

  iterator.start_edge = { 0, -1 }

  local last_line = vim.api.nvim_buf_line_count(0)
  iterator.end_edge = { last_line - 1, vim.fn.col({ last_line, '$' }) - 1 }

  -- Iterate
  local res_pos = MiniBracketed.advance(iterator, direction, opts)
  if res_pos == nil or res_pos == iterator.state then return end

  -- Apply. Use built-in jump with offsetted cursor position to make it respect
  -- `vim.diagnostic.config()`.
  H.diagnostic_jump({ res_pos[1] + 1, res_pos[2] - 1 }, opts.float, opts.severity)
end

--- File on disk
---
--- Go to next/previous file on disk alphabetically. Files are taken from
--- directory of file in current buffer (or current working directory if buffer
--- doesn't contain a readable file). Only first-level files are used, i.e. it
--- doesn't go inside subdirectories.
---
--- Direction "forward" goes forward alphabetically, "backward" - backward.
---
---@param direction __bracketed_direction
---@param opts __bracketed_opts
MiniBracketed.file = function(direction, opts)
  if H.is_disabled() then return end

  H.validate_direction(direction, { 'first', 'backward', 'forward', 'last' }, 'file')
  opts = vim.tbl_deep_extend('force', { n_times = vim.v.count1, wrap = true }, H.get_config().file.options, opts or {})

  -- Get file data
  local file_data = H.get_file_data()
  if file_data == nil then return end
  local file_basenames, directory = file_data.file_basenames, file_data.directory

  -- Define iterator that traverses all found files
  local iterator = {}
  local n_files = #file_basenames

  iterator.next = function(ind)
    -- Allow advance in untrackable current buffer
    if ind == nil then return 1 end
    if n_files <= ind then return end
    return ind + 1
  end

  iterator.prev = function(ind)
    -- Allow advance in untrackable current buffer
    if ind == nil then return n_files end
    if ind <= 1 then return end
    return ind - 1
  end

  -- - Find filename array index of current buffer
  local cur_basename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':t')
  local cur_basename_ind
  if cur_basename ~= '' then
    for i, f in ipairs(file_basenames) do
      if cur_basename == f then
        cur_basename_ind = i
        break
      end
    end
  end

  iterator.state = cur_basename_ind
  iterator.start_edge = 0
  iterator.end_edge = n_files + 1

  -- Iterate
  local res_ind = MiniBracketed.advance(iterator, direction, opts)
  if res_ind == iterator.state then return end

  -- Apply. Open target_path.
  local path_sep = package.config:sub(1, 1)
  local target_path = directory .. path_sep .. file_basenames[res_ind]
  H.edit(target_path)
end

--- Indent change
---
--- Go to next/previous line with different indent (see |indent()|).
--- Can be used to go to lines with smaller, bigger, or different indent.
---
--- Notes:
--- - Directions "first" and "last" work differently from most other targets
---   for performance reasons. They are essentially "backward" and "forward"
---   with very big `n_times` option.
--- - For similar reasons, `wrap` is not supported.
--- - Blank line inherit indent from near non-blank line in direction of movement.
---
--- Direction "forward" increases line number, "backward" - decreases.
---
---@param direction __bracketed_direction
---@param opts table|nil Options. A table with fields:
---   - <n_times> `(number)` - Number of times to advance. Default: |v:count1|.
---   __bracketed_add_to_jumplist
---   - <change_type> `(string)` - which type of indent change to use.
---     One of "less" (default; smaller indent), "more" (bigger indent),
---     "diff" (different indent).
MiniBracketed.indent = function(direction, opts)
  if H.is_disabled() then return end

  H.validate_direction(direction, { 'first', 'backward', 'forward', 'last' }, 'indent')
  opts = vim.tbl_deep_extend(
    'force',
    { add_to_jumplist = false, change_type = 'less', n_times = vim.v.count1 },
    H.get_config().indent.options,
    opts or {}
  )

  opts.wrap = false

  if direction == 'first' then
    -- For some reason using `n_times = math.huge` leads to infinite loop
    direction, opts.n_times = 'backward', vim.api.nvim_buf_line_count(0) + 1
  end
  if direction == 'last' then
    direction, opts.n_times = 'forward', vim.api.nvim_buf_line_count(0) + 1
  end

  -- Compute loop data to traverse target commented lines in current buffer
  local predicate = ({
    less = function(new, cur) return new < cur or cur == 0 end,
    more = function(new, cur) return new > cur end,
    diff = function(new, cur) return new ~= cur end,
  })[opts.change_type]
  if predicate == nil then return end

  -- Define iterator
  local iterator = {}

  iterator.next = function(cur_lnum)
    -- Correctly process empty current line
    cur_lnum = vim.fn.nextnonblank(cur_lnum)
    local cur_indent = vim.fn.indent(cur_lnum)

    local new_lnum, new_indent = cur_lnum, cur_indent
    -- Check with `new_lnum > 0` because `nextnonblank()` returns -1 if line is
    -- outside of line range
    while new_lnum > 0 do
      new_indent = vim.fn.indent(new_lnum)
      if predicate(new_indent, cur_indent) then return new_lnum end
      new_lnum = vim.fn.nextnonblank(new_lnum + 1)
    end
  end

  iterator.prev = function(cur_lnum)
    cur_lnum = vim.fn.prevnonblank(cur_lnum)
    local cur_indent = vim.fn.indent(cur_lnum)

    local new_lnum, new_indent = cur_lnum, cur_indent
    while new_lnum > 0 do
      new_indent = vim.fn.indent(new_lnum)
      if predicate(new_indent, cur_indent) then return new_lnum end
      new_lnum = vim.fn.prevnonblank(new_lnum - 1)
    end
  end

  -- - Don't add first and last states as there is no wrapping around edges
  iterator.state = vim.fn.line('.')

  -- Iterate
  local res_line_num = MiniBracketed.advance(iterator, direction, opts)
  if res_line_num == nil or res_line_num == iterator.state then return end

  -- Possibly add current position to jumplist
  if opts.add_to_jumplist then H.add_to_jumplist() end

  -- Apply. Open just enough folds and put cursor on first non-blank.
  H.set_cursor(res_line_num, 0)
  vim.cmd('normal! zv^')
end

--- Jump inside current buffer
---
--- Go to next/previous jump from |jumplist| which is inside current buffer.
---
--- Notes:
--- - There are no Visual mode mappings due to implementation problems.
---
--- Direction "forward" increases jump number, "backward" - decreases.
---
---@param direction __bracketed_direction
---@param opts __bracketed_opts
MiniBracketed.jump = function(direction, opts)
  if H.is_disabled() then return end

  H.validate_direction(direction, { 'first', 'backward', 'forward', 'last' }, 'jump')
  opts = vim.tbl_deep_extend('force', { n_times = vim.v.count1, wrap = true }, H.get_config().jump.options, opts or {})

  -- Define iterator that traverses all jumplist entries inside current buffer
  local cur_buf_id = vim.api.nvim_get_current_buf()
  local jump_list, cur_jump_num = unpack(vim.fn.getjumplist())
  local n_list = #jump_list
  if n_list == 0 then return end
  -- - Correct for zero-based indexing
  cur_jump_num = cur_jump_num + 1

  local iterator = {}

  local is_jump_num_from_current_buffer = function(jump_num)
    local jump_entry = jump_list[jump_num]
    if jump_entry == nil then return end
    return jump_entry.bufnr == cur_buf_id
  end

  iterator.next = function(jump_num)
    for num = jump_num + 1, n_list do
      if is_jump_num_from_current_buffer(num) then return num end
    end
  end

  iterator.prev = function(jump_num)
    for num = jump_num - 1, 1, -1 do
      if is_jump_num_from_current_buffer(num) then return num end
    end
  end

  iterator.state = cur_jump_num
  iterator.start_edge = 0
  iterator.end_edge = n_list + 1

  -- Iterate
  local res_jump_num = MiniBracketed.advance(iterator, direction, opts)
  if res_jump_num == nil or jump_list[res_jump_num] == nil then return end

  -- Apply. Make jump. Allow jumping to current jump entry as it might be
  -- different from current cursor position.
  H.make_jump(jump_list, cur_jump_num, res_jump_num)
end

--- Location from location list
---
--- Go to next/previous location from |location-list|. This is similar to
--- |:lfirst|, |:lprevious|, |:lnext|, and |:llast| but with support of
--- wrapping around edges and |[count]| for "first"/"last" direction.
---
--- Direction "forward" increases location number, "backward" - decreases.
---
---@param direction __bracketed_direction
---@param opts __bracketed_opts
MiniBracketed.location = function(direction, opts)
  if H.is_disabled() then return end

  H.validate_direction(direction, { 'first', 'backward', 'forward', 'last' }, 'location')
  opts =
    vim.tbl_deep_extend('force', { n_times = vim.v.count1, wrap = true }, H.get_config().location.options, opts or {})

  H.qf_loc_implementation('location', direction, opts)
end

--- Old files from previous and current sessions
---
--- Go to older/newer readable file either from previous session (see |v:oldfiles|)
--- or the current one (updated automatically after |MiniBracketed.setup()| call).
---
--- Direction "forward" goes to more recent files, "backward" - to older.
---
--- Notes:
--- - In current session it tracks only normal buffers (see |'buftype'|) for
---   some readable file.
--- - No new file is tracked when advancing this target. Only after buffer
---   change is done not through this target (like with |MiniBracketed.buffer()|),
---   it updates recency of last advanced and new buffers.
---
---@param direction __bracketed_direction
---@param opts __bracketed_opts
MiniBracketed.oldfile = function(direction, opts)
  if H.is_disabled() then return end

  H.validate_direction(direction, { 'first', 'backward', 'forward', 'last' }, 'oldfile')
  opts =
    vim.tbl_deep_extend('force', { n_times = vim.v.count1, wrap = true }, H.get_config().oldfile.options, opts or {})

  -- Define iterator that traverses all old files
  local cur_path = vim.api.nvim_buf_get_name(0)

  H.oldfile_normalize()
  local oldfile_arr = H.oldfile_get_array()
  local n_oldfiles = #oldfile_arr

  local iterator = {}

  iterator.next = function(ind)
    -- Allow advance in untrackable current buffer
    if ind == nil then return 1 end
    if n_oldfiles <= ind then return end
    return ind + 1
  end

  iterator.prev = function(ind)
    -- Allow advance in untrackable current buffer
    if ind == nil then return n_oldfiles end
    if ind <= 1 then return end
    return ind - 1
  end

  iterator.state = H.cache.oldfile.recency[cur_path]
  iterator.start_edge = 0
  iterator.end_edge = n_oldfiles + 1

  -- Iterate
  local res_arr_ind = MiniBracketed.advance(iterator, direction, opts)
  if res_arr_ind == nil or res_arr_ind == iterator.state then return end

  -- Apply. Edit file at path while marking it not for tracking.
  H.cache.oldfile.is_advancing = true
  H.edit(oldfile_arr[res_arr_ind])
end

--- Quickfix from quickfix list
---
--- Go to next/previous entry from |quickfix| list. This is similar to
--- |:cfirst|, |:cprevious|, |:cnext|, and |:clast| but with support of
--- wrapping around edges and |[count]| for "first"/"last" direction.
---
--- Direction "forward" increases location number, "backward" - decreases.
---
---@param direction __bracketed_direction
---@param opts __bracketed_opts
MiniBracketed.quickfix = function(direction, opts)
  if H.is_disabled() then return end

  H.validate_direction(direction, { 'first', 'backward', 'forward', 'last' }, 'quickfix')
  opts =
    vim.tbl_deep_extend('force', { n_times = vim.v.count1, wrap = true }, H.get_config().quickfix.options, opts or {})

  H.qf_loc_implementation('quickfix', direction, opts)
end

--- Tree-sitter node
---
--- Go to end/start of current tree-sitter node and its parents (except root).
---
--- Notes:
--- - Requires loaded tree-sitter parser in the current buffer.
--- - Directions "first" and "last" work differently from most other targets
---   for performance reasons. They are essentially "backward" and "forward"
---   with very big `n_times` option.
--- - For similar reasons, `wrap` is not supported.
---
--- Direction "forward" moves cursor forward to node's end, "backward" - backward
--- to node's start.
---
---@param direction __bracketed_direction
---@param opts table|nil Options. A table with fields:
---   - <n_times> `(number)` - Number of times to advance. Default: |v:count1|.
---   __bracketed_add_to_jumplist
MiniBracketed.treesitter = function(direction, opts)
  if H.is_disabled() then return end

  H.validate_direction(direction, { 'first', 'backward', 'forward', 'last' }, 'treesitter')
  opts = vim.tbl_deep_extend(
    'force',
    { add_to_jumplist = false, n_times = vim.v.count1 },
    H.get_config().treesitter.options,
    opts or {}
  )

  opts.wrap = false

  if direction == 'first' then
    direction, opts.n_times = 'backward', math.huge
  end
  if direction == 'last' then
    direction, opts.n_times = 'forward', math.huge
  end

  -- Define iterator that traverses current node and its parents (except root)
  local is_bad_node = function(node) return node == nil or node:parent() == nil end
  local is_after = function(row_new, col_new, row_ref, col_ref)
    return row_ref < row_new or (row_ref == row_new and col_ref < col_new)
  end
  local is_before = function(row_new, col_new, row_ref, col_ref) return is_after(row_ref, col_ref, row_new, col_new) end

  local iterator = {}

  -- Traverse node and parents until node's end is after current position
  iterator.next = function(node_pos)
    local node = node_pos.node
    if is_bad_node(node) then return nil end

    local init_row, init_col = node_pos.pos[1], node_pos.pos[2]
    local cur_row, cur_col, cur_node = init_row, init_col, node

    repeat
      if is_bad_node(cur_node) then break end

      cur_row, cur_col = cur_node:end_()
      -- Correct for end-exclusiveness
      cur_col = cur_col - 1
      cur_node = cur_node:parent()
    until is_after(cur_row, cur_col, init_row, init_col)

    if not is_after(cur_row, cur_col, init_row, init_col) then return end

    return { node = cur_node, pos = { cur_row, cur_col } }
  end

  -- Traverse node and parents until node's start is before current position
  iterator.prev = function(node_pos)
    local node = node_pos.node
    if is_bad_node(node) then return nil end

    local init_row, init_col = node_pos.pos[1], node_pos.pos[2]
    local cur_row, cur_col, cur_node = init_row, init_col, node

    repeat
      if is_bad_node(cur_node) then break end

      cur_row, cur_col = cur_node:start()
      cur_node = cur_node:parent()
    until is_before(cur_row, cur_col, init_row, init_col)

    if not is_before(cur_row, cur_col, init_row, init_col) then return end

    return { node = cur_node, pos = { cur_row, cur_col } }
  end

  local cur_pos = vim.api.nvim_win_get_cursor(0)
  local ok, node = pcall(H.get_treesitter_node, cur_pos[1] - 1, cur_pos[2])
  if not ok then
    H.error(
      'In `treesitter()` target can not find tree-sitter node under cursor.'
        .. ' Do you have tree-sitter enabled in current buffer?'
    )
  end
  iterator.state = { pos = { cur_pos[1] - 1, cur_pos[2] }, node = node }

  -- Iterate
  local res_node_pos = MiniBracketed.advance(iterator, direction, opts)
  if res_node_pos == nil then return end

  -- Possibly add current position to jumplist
  if opts.add_to_jumplist then H.add_to_jumplist() end

  -- Apply
  H.set_cursor(res_node_pos.pos[1] + 1, res_node_pos.pos[2])
end

--- Undo along a tracked linear history
---
--- In a nutshell:
--- - Keys |u| and |CTRL-R| (although remapped) can be used as usual, but every
---   their execution new state is recorded in this module's linear undo history.
--- - Advancing this target goes along linear undo history revealing undo states
---   **in order they actually appeared**.
--- - One big difference with built-in methods is that tracked linear history
---   can repeat undo states (not consecutively, though).
---
--- Neovim's default way of managing undo history is through branches (see
--- |undo-branches|). Basically it means that if you undo several changes and then
--- make new ones, it creates new undo branch while usually (see |'undolevels'|)
--- saving previous buffer states in another branch. While there are commands
--- to navigate by time of undo state creation (like |:earlier| and |:later|),
--- there is no intuitive way to cycle through them. Existing |g-| and |g+|
--- cycle through undo states **based on their creation time**, which often
--- gets confusing really guickly in extensively edited buffer.
---
--- This `undo()` target provides a way to cycle through linear undo history
--- **in order states actually appeared**. It does so by registering any new undo
--- states plus every time |MiniBracketed.register_undo_state()| is called. To have
--- more "out of the box" experience, |u| and |CTRL-R| are remapped to call it after
--- they perform their undo/redo.
---
--- Example:
---
--- To show more clearly the difference between advancing this target and using
--- built-in functionality, here is an example:
---
--- - Create undo history in a new buffer (|:new|):
---     - Enter `one two three` text.
---     - Delete first word with `daw` and undo the change with `u`.
---     - Delete second word with `daw` and undo the change with `u`.
---     - Delete third word with `daw` and undo the change with `u`.
---
--- - Now try one of the following (each one after performing previous steps in
---   separate new buffer):
---     - Press `u`. It goes back to empty buffer. Press `<C-R>` twice and it
---       goes to the latest change (`one two`). No way to get to other states
---       (like `two three` or `one three`) with these two keys.
---
---     - Press `g-`. It goes to an empty buffer. Press `g+` 4 times. It cycles
---       through all available undo states **in order they were created**.
---
---     - Finally, press `[u`. It goes back to `one two` - state which was
---       **previously visited** by the user. Another `[u` restores `one two three`.
---       Use `]U` to go to latest visited undo state.
---
---@param direction __bracketed_direction
---@param opts __bracketed_opts
MiniBracketed.undo = function(direction, opts)
  if H.is_disabled() then return end

  H.validate_direction(direction, { 'first', 'backward', 'forward', 'last' }, 'undo')
  opts = vim.tbl_deep_extend('force', { n_times = vim.v.count1, wrap = true }, H.get_config().undo.options, opts or {})

  -- Define iterator that traverses undo states in order they appeared
  local buf_id = vim.api.nvim_get_current_buf()
  H.undo_sync(buf_id, vim.fn.undotree())

  local iterator = {}
  local buf_history = H.cache.undo[buf_id]
  local n = #buf_history

  iterator.next = function(id)
    if id == nil or n <= id then return end
    return id + 1
  end

  iterator.prev = function(id)
    if id == nil or id <= 1 then return end
    return id - 1
  end

  iterator.state = buf_history.current_id
  iterator.start_edge = 0
  iterator.end_edge = n + 1

  -- Iterate
  local res_id = MiniBracketed.advance(iterator, direction, opts)
  if res_id == nil or res_id == iterator.state then return end

  -- Apply. Move to undo state by number while recording current history id
  buf_history.is_advancing = true
  vim.cmd('undo ' .. buf_history[res_id])

  buf_history.current_id = res_id
end

--- Register state for undo target
---
--- Use this function to add current undo state to this module's linear undo
--- history. It is used in |MiniBracketed.setup()| to remap |u| and |CTRL-R| keys
--- to add their new state to linear undo history.
MiniBracketed.register_undo_state = function()
  local buf_id = vim.api.nvim_get_current_buf()
  local tree = vim.fn.undotree()

  -- Synchronize undo history and stop advancing
  H.undo_sync(buf_id, tree, false)

  -- Append new undo state to linear history
  local buf_history = H.cache.undo[buf_id]
  H.undo_append_state(buf_history, tree.seq_cur)
  buf_history.current_id = #buf_history
end

--- Normal window
---
--- Go to next/previous normal window. Order by their number (see |winnr()|).
---
--- Direction "forward" increases window number, "backward" - decreases.
---
--- Only normal (non-floating) windows are used.
---
---@param direction __bracketed_direction
---@param opts __bracketed_opts
MiniBracketed.window = function(direction, opts)
  if H.is_disabled() then return end

  H.validate_direction(direction, { 'first', 'backward', 'forward', 'last' }, 'window')
  opts =
    vim.tbl_deep_extend('force', { n_times = vim.v.count1, wrap = true }, H.get_config().window.options, opts or {})

  -- Define iterator that traverses all normal windows in "natural" order
  local is_normal = function(win_nr)
    local win_id = vim.fn.win_getid(win_nr)
    return vim.api.nvim_win_get_config(win_id).relative == ''
  end

  local iterator = {}

  iterator.next = function(win_nr)
    for nr = win_nr + 1, vim.fn.winnr('$') do
      if is_normal(nr) then return nr end
    end
  end

  iterator.prev = function(win_nr)
    for nr = win_nr - 1, 1, -1 do
      if is_normal(nr) then return nr end
    end
  end

  iterator.state = vim.fn.winnr()
  iterator.start_edge = 0
  iterator.end_edge = vim.fn.winnr('$') + 1

  -- Iterate
  local res_win_nr = MiniBracketed.advance(iterator, direction, opts)
  if res_win_nr == iterator.state then return end

  -- Apply
  vim.api.nvim_set_current_win(vim.fn.win_getid(res_win_nr))
end

--- Replace "latest put region" with yank history entry
---
--- After |MiniBracketed.setup()| is called, on every yank/delete/change operation
--- (technically, every trigger of |TextYankPost| event) the object of operation
--- is added to yank history. Advancing this target will replace the region of
--- latest put operation with entry from yank history.
---
--- By default works best if called **right after** text paste (like with |p| or |P|).
---
--- To better detect "latest put region", use |MiniBracketed.register_put_region()|
--- as described later.
---
--- Direction "forward" goes to newer yank history entry, "backward" - to older.
---
--- Example:
---
--- - Type `one two three`.
--- - Yank each word with `yiw`.
--- - Create new line and press `p`. This should paste `three`.
--- - Type `[y`. This should replace latest `three` with `two`.
---
--- # Latest put region ~
---
--- "Latest put region" is (in order of decreasing priority):
--- - The one from latest advance of this target.
--- - The one registered by user with |MiniBracketed.register_put_region()|.
--- - The one taken from |'[| and |']| marks.
---
--- For users there are these approaches to manage which region will be used:
--- - Do nothing. In this case region between `[` / `]` marks will always be used
---   for first `yank` advance.
---   Although doable, this has several drawbacks: it will use latest yanked or
---   changed region or the entire buffer if marks are not set.
---   If remember to advance this target only after recent put operation, this
---   should work as expected.
---
--- - Remap common put operations to use |MiniBracketed.register_put_region()|.
---   After that, only regions from mapped put operations will be used for first
---   advance. Example of custom mappings (note use of |:map-expression|): >lua
---
---     local put_keys = { 'p', 'P' }
---     for _, lhs in ipairs(put_keys) do
---       local rhs = 'v:lua.MiniBracketed.register_put_region("' .. lhs .. '")'
---       vim.keymap.set({ 'n', 'x' }, lhs, rhs, { expr = true })
---     end
--- <
---@param direction __bracketed_direction
---@param opts __bracketed_opts
---   - <operators> `(table)` - array of operator names ("c", "d", or "y") for
---     which yank entry should be used to advance. For example, use `{ "y" }`
---     to advance only by entries actually resulted from yank operation with |y|.
---     Default: `{ 'c', 'd', 'y' }`.
MiniBracketed.yank = function(direction, opts)
  if H.is_disabled() then return end

  H.validate_direction(direction, { 'first', 'backward', 'forward', 'last' }, 'yank')
  -- NOTE: Don't use `tbl_deep_extend` to prefer full input `operators` array
  local default_opts = { n_times = vim.v.count1, operators = { 'c', 'd', 'y' }, wrap = true }
  opts = vim.tbl_extend('force', default_opts, H.get_config().yank.options, opts or {})

  -- Update yank history data
  local cache_yank, history = H.cache.yank, H.cache.yank.history
  local n_history = #history
  local cur_state = H.get_yank_state()
  if not vim.deep_equal(cur_state, cache_yank.state) then H.yank_stop_advancing() end

  -- Define iterator that traverses yank history for entry with proper operator
  local iterator = {}

  iterator.next = function(id)
    for i = id + 1, n_history do
      if vim.tbl_contains(opts.operators, history[i].operator) then return i end
    end
  end

  iterator.prev = function(id)
    for i = id - 1, 1, -1 do
      if vim.tbl_contains(opts.operators, history[i].operator) then return i end
    end
  end

  iterator.state = cache_yank.current_id
  iterator.start_edge = 0
  iterator.end_edge = n_history + 1

  -- Iterate
  local res_id = MiniBracketed.advance(iterator, direction, opts)
  if res_id == nil then return end

  -- Apply. Replace latest put region with yank history entry
  -- - Account for possible errors when latest region became out of bounds
  local ok, _ = pcall(H.replace_latest_put_region, cache_yank.history[res_id])
  if not ok then return end

  cache_yank.current_id = res_id
  cache_yank.is_advancing = true
  cache_yank.state = H.get_yank_state()
end

--- Register "latest put region"
---
--- This function should be called after put register becomes relevant
--- (|v:register| is appropriately set) but before put operation takes place
--- (|'[| and |']| marks become relevant).
---
--- Designed to be used in a user-facing expression mapping (see |:map-expression|).
--- For mapping examples see |MiniBracketed.yank()|.
---
---@param put_key string Put keys to be remapped.
---
---@return string Returns `put_key` for a better usage inside expression mappings.
MiniBracketed.register_put_region = function(put_key)
  local buf_id = vim.api.nvim_get_current_buf()

  -- Compute mode of register **before** putting (while it is still relevant)
  local mode = H.get_register_mode(vim.v.register)

  -- Register latest put region **after** it is done (when it becomes relevant)
  vim.schedule(function() H.cache.yank.user_put_regions[buf_id] = H.get_latest_region(mode) end)

  return put_key
end

--- Advance iterator
---
--- This is the main function which performs any forward/backward/first/last
--- advance in this module. Its basic idea is to take iterator (object containing
--- information about current state and how to go to next/previous one) and go
--- in certain direction until needed/allowed.
---
--- Notes:
--- - Directions "first" and "last" are convenience wrappers for "forward" and
---   "backward" with pre-setting initial state to `start_edge` and `end_edge`.
--- - Iterators `next()` and `prev()` methods should be able to handle `nil` as input.
--- - This function only returns new state and doesn't modify `iterator.state`.
---
---@param iterator table Table:
---   - Methods:
---       - <next> - given state, return state in forward direction (no wrap).
---       - <prev> - given state, return state in backward direction (no wrap).
---   - Fields:
---       - <state> - object describing current state.
---       - <start_edge> (optional) - object with `forward(start_edge)` describing
---         first state. If `nil`, can't wrap forward or use direction "first".
---       - <end_edge> (optional) - object with `backward(end_edge)` describing
---         last state. If `nil`, can't wrap backward or use direction "last".
---@param direction string Direction. One of "first", "backward", "forward", "last".
---@param opts table|nil Options with the following keys:
---   - <n_times> `(number)` - number of times to go in input direction.
---     Default: `v:count1`.
---   - <wrap> `(boolean)` - whether to wrap around edges when `next()` or
---     `prev()` return `nil`. Default: `true`.
---
---@return any Result state. If `nil`, could not reach any valid result state.
MiniBracketed.advance = function(iterator, direction, opts)
  opts = vim.tbl_deep_extend('force', { n_times = vim.v.count1, wrap = true }, opts or {})

  -- Use two states: "result" will be used as result, "current" will be used
  -- for iteration. Separation is needed at least for two reasons:
  -- - Allow partial reach of `n_times`.
  -- - Don't allow `start_edge` and `end_edge` be the output.
  local res_state = iterator.state

  -- Compute loop data
  local iter_method = 'next'
  local cur_state = res_state

  if direction == 'backward' then iter_method = 'prev' end

  if direction == 'first' then
    cur_state, iter_method = iterator.start_edge, 'next'
  end

  if direction == 'last' then
    cur_state, iter_method = iterator.end_edge, 'prev'
  end

  -- Loop
  local iter = iterator[iter_method]
  for _ = 1, opts.n_times do
    -- Advance
    cur_state = iter(cur_state)

    if cur_state == nil then
      -- Stop if can't wrap around edges
      if not opts.wrap then break end

      -- Wrap around edge
      local edge = iterator.start_edge
      if iter_method == 'prev' then edge = iterator.end_edge end
      if edge == nil then break end

      cur_state = iter(edge)

      -- Ensure non-nil new state (can happen when there are no targets)
      if cur_state == nil then break end
    end

    -- Allow only partial reach of `n_times`
    res_state = cur_state
  end

  return res_state
end

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniBracketed.config)

H.cache = {
  -- Tracking of old files for `oldfile()` (this data structure is designed to be
  -- fast to add new file; initially `nil` to postpone initialization from
  -- `v:oldfiles` up until it is actually needed):
  -- - `recency` is a table with file paths as fields and numerical values
  --   indicating how recent file was accessed (higher - more recent).
  -- - `max_recency` is a maximum currently used `recency`. Used to add new file.
  -- - `is_advancing` is an indicator that buffer change was done inside
  --   `oldfile()` function. It is a key to enabling moving along old files
  --   (and not just going back and forth between two files because they swap
  --   places as two most recent files).
  -- - `last_advanced_bufname` - name of last advanced buffer. Used to update
  --   recency of only the last buffer entered during advancing.
  oldfile = nil,

  -- Per buffer history of visited undo states. A table for each buffer id:
  -- - Numerical fields indicate actual history of visited undo states (from
  --   oldest to latest).
  -- - <current_id> - identifier of current history entry (used for iteration).
  -- - <seq_last> - latest recorded state (`seq_last` from `undotree()`).
  -- - <is_advancing> - whether currently advancing. Used to allow consecutive
  --   advances along tracked undo history.
  undo = {},

  -- Cache for `yank` targets
  yank = {
    -- Per-buffer region of latest advance. Used to correctly determine range
    -- and mode of latest advanced region.
    advance_put_regions = {},
    -- Current id of yank entry in yank history
    current_id = 0,
    -- Yank history. Each element contains data necessary to replace latest put
    -- region with yanked one. See `track_yank()`.
    history = {},
    -- Whether currently advancing
    is_advancing = false,
    -- State of latest yank advancement to determine of currently advancing
    state = {},
    -- Per-buffer region registered by user as "latest put region". Used to
    -- overcome limitations of automatic detection of latest put region (like
    -- not reliable mode detection when pasting from register; respecting not
    -- only regions of put operations, but also yank and change).
    user_put_regions = {},
  },
}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  H.check_type('buffer', config.buffer, 'table')
  H.check_type('buffer.suffix', config.buffer.suffix, 'string')
  H.check_type('buffer.options', config.buffer.options, 'table')

  H.check_type('comment', config.comment, 'table')
  H.check_type('comment.suffix', config.comment.suffix, 'string')
  H.check_type('comment.options', config.comment.options, 'table')

  H.check_type('conflict', config.conflict, 'table')
  H.check_type('conflict.suffix', config.conflict.suffix, 'string')
  H.check_type('conflict.options', config.conflict.options, 'table')

  H.check_type('diagnostic', config.diagnostic, 'table')
  H.check_type('diagnostic.suffix', config.diagnostic.suffix, 'string')
  H.check_type('diagnostic.options', config.diagnostic.options, 'table')

  H.check_type('file', config.file, 'table')
  H.check_type('file.suffix', config.file.suffix, 'string')
  H.check_type('file.options', config.file.options, 'table')

  H.check_type('indent', config.indent, 'table')
  H.check_type('indent.suffix', config.indent.suffix, 'string')
  H.check_type('indent.options', config.indent.options, 'table')

  H.check_type('jump', config.jump, 'table')
  H.check_type('jump.suffix', config.jump.suffix, 'string')
  H.check_type('jump.options', config.jump.options, 'table')

  H.check_type('location', config.location, 'table')
  H.check_type('location.suffix', config.location.suffix, 'string')
  H.check_type('location.options', config.location.options, 'table')

  H.check_type('oldfile', config.oldfile, 'table')
  H.check_type('oldfile.suffix', config.oldfile.suffix, 'string')
  H.check_type('oldfile.options', config.oldfile.options, 'table')

  H.check_type('quickfix', config.quickfix, 'table')
  H.check_type('quickfix.suffix', config.quickfix.suffix, 'string')
  H.check_type('quickfix.options', config.quickfix.options, 'table')

  H.check_type('treesitter', config.treesitter, 'table')
  H.check_type('treesitter.suffix', config.treesitter.suffix, 'string')
  H.check_type('treesitter.options', config.treesitter.options, 'table')

  H.check_type('undo', config.undo, 'table')
  H.check_type('undo.suffix', config.undo.suffix, 'string')
  H.check_type('undo.options', config.undo.options, 'table')

  H.check_type('window', config.window, 'table')
  H.check_type('window.suffix', config.window.suffix, 'string')
  H.check_type('window.options', config.window.options, 'table')

  H.check_type('yank', config.yank, 'table')
  H.check_type('yank.suffix', config.yank.suffix, 'string')
  H.check_type('yank.options', config.yank.options, 'table')

  return config
end

--stylua: ignore
H.apply_config = function(config)
  MiniBracketed.config = config

  -- Make mappings. NOTE: make 'forward'/'backward' *after* 'first'/'last' to
  -- allow non-letter suffixes define 'forward'/'backward'.
  if config.buffer.suffix ~= '' then
    local low, up = H.get_suffix_variants(config.buffer.suffix)
    H.map('n', '[' .. up,  "<Cmd>lua MiniBracketed.buffer('first')<CR>",    { desc = 'Buffer first' })
    H.map('n', ']' .. up,  "<Cmd>lua MiniBracketed.buffer('last')<CR>",     { desc = 'Buffer last' })
    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.buffer('backward')<CR>", { desc = 'Buffer backward' })
    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.buffer('forward')<CR>",  { desc = 'Buffer forward' })
  end

  if config.comment.suffix ~= '' then
    local low, up = H.get_suffix_variants(config.comment.suffix)
    H.map('n', '[' .. up, "<Cmd>lua MiniBracketed.comment('first')<CR>",  { desc = 'Comment first' })
    H.map('x', '[' .. up, "<Cmd>lua MiniBracketed.comment('first')<CR>",  { desc = 'Comment first' })
    H.map('o', '[' .. up, "V<Cmd>lua MiniBracketed.comment('first')<CR>", { desc = 'Comment first' })

    H.map('n', ']' .. up, "<Cmd>lua MiniBracketed.comment('last')<CR>",  { desc = 'Comment last' })
    H.map('x', ']' .. up, "<Cmd>lua MiniBracketed.comment('last')<CR>",  { desc = 'Comment last' })
    H.map('o', ']' .. up, "V<Cmd>lua MiniBracketed.comment('last')<CR>", { desc = 'Comment last' })

    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.comment('backward')<CR>",  { desc = 'Comment backward' })
    H.map('x', '[' .. low, "<Cmd>lua MiniBracketed.comment('backward')<CR>",  { desc = 'Comment backward' })
    H.map('o', '[' .. low, "V<Cmd>lua MiniBracketed.comment('backward')<CR>", { desc = 'Comment backward' })

    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.comment('forward')<CR>",  { desc = 'Comment forward' })
    H.map('x', ']' .. low, "<Cmd>lua MiniBracketed.comment('forward')<CR>",  { desc = 'Comment forward' })
    H.map('o', ']' .. low, "V<Cmd>lua MiniBracketed.comment('forward')<CR>", { desc = 'Comment forward' })
  end

  if config.conflict.suffix ~= '' then
    local low, up = H.get_suffix_variants(config.conflict.suffix)
    H.map('n', '[' .. up, "<Cmd>lua MiniBracketed.conflict('first')<CR>",  { desc = 'Conflict first' })
    H.map('x', '[' .. up, "<Cmd>lua MiniBracketed.conflict('first')<CR>",  { desc = 'Conflict first' })
    H.map('o', '[' .. up, "V<Cmd>lua MiniBracketed.conflict('first')<CR>", { desc = 'Conflict first' })

    H.map('n', ']' .. up, "<Cmd>lua MiniBracketed.conflict('last')<CR>",  { desc = 'Conflict last' })
    H.map('x', ']' .. up, "<Cmd>lua MiniBracketed.conflict('last')<CR>",  { desc = 'Conflict last' })
    H.map('o', ']' .. up, "V<Cmd>lua MiniBracketed.conflict('last')<CR>", { desc = 'Conflict last' })

    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.conflict('backward')<CR>",  { desc = 'Conflict backward' })
    H.map('x', '[' .. low, "<Cmd>lua MiniBracketed.conflict('backward')<CR>",  { desc = 'Conflict backward' })
    H.map('o', '[' .. low, "V<Cmd>lua MiniBracketed.conflict('backward')<CR>", { desc = 'Conflict backward' })

    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.conflict('forward')<CR>",  { desc = 'Conflict forward' })
    H.map('x', ']' .. low, "<Cmd>lua MiniBracketed.conflict('forward')<CR>",  { desc = 'Conflict forward' })
    H.map('o', ']' .. low, "V<Cmd>lua MiniBracketed.conflict('forward')<CR>", { desc = 'Conflict forward' })
  end

  if config.diagnostic.suffix ~= '' then
    local low, up = H.get_suffix_variants(config.diagnostic.suffix)
    H.map('n', '[' .. up, "<Cmd>lua MiniBracketed.diagnostic('first')<CR>",  { desc = 'Diagnostic first' })
    H.map('x', '[' .. up, "<Cmd>lua MiniBracketed.diagnostic('first')<CR>",  { desc = 'Diagnostic first' })
    H.map('o', '[' .. up, "v<Cmd>lua MiniBracketed.diagnostic('first')<CR>", { desc = 'Diagnostic first' })

    H.map('n', ']' .. up, "<Cmd>lua MiniBracketed.diagnostic('last')<CR>",  { desc = 'Diagnostic last' })
    H.map('x', ']' .. up, "<Cmd>lua MiniBracketed.diagnostic('last')<CR>",  { desc = 'Diagnostic last' })
    H.map('o', ']' .. up, "v<Cmd>lua MiniBracketed.diagnostic('last')<CR>", { desc = 'Diagnostic last' })

    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.diagnostic('backward')<CR>",  { desc = 'Diagnostic backward' })
    H.map('x', '[' .. low, "<Cmd>lua MiniBracketed.diagnostic('backward')<CR>",  { desc = 'Diagnostic backward' })
    H.map('o', '[' .. low, "v<Cmd>lua MiniBracketed.diagnostic('backward')<CR>", { desc = 'Diagnostic backward' })

    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.diagnostic('forward')<CR>",  { desc = 'Diagnostic forward' })
    H.map('x', ']' .. low, "<Cmd>lua MiniBracketed.diagnostic('forward')<CR>",  { desc = 'Diagnostic forward' })
    H.map('o', ']' .. low, "v<Cmd>lua MiniBracketed.diagnostic('forward')<CR>", { desc = 'Diagnostic forward' })
  end

  if config.file.suffix ~= '' then
    local low, up = H.get_suffix_variants(config.file.suffix)
    H.map('n', '[' .. up,  "<Cmd>lua MiniBracketed.file('first')<CR>",    { desc = 'File first' })
    H.map('n', ']' .. up,  "<Cmd>lua MiniBracketed.file('last')<CR>",     { desc = 'File last' })
    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.file('backward')<CR>", { desc = 'File backward' })
    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.file('forward')<CR>",  { desc = 'File forward' })
  end

  if config.indent.suffix ~= '' then
    local low, up = H.get_suffix_variants(config.indent.suffix)
    H.map('n', '[' .. up, "<Cmd>lua MiniBracketed.indent('first')<CR>",  { desc = 'Indent first' })
    H.map('x', '[' .. up, "<Cmd>lua MiniBracketed.indent('first')<CR>",  { desc = 'Indent first' })
    H.map('o', '[' .. up, "V<Cmd>lua MiniBracketed.indent('first')<CR>", { desc = 'Indent first' })

    H.map('n', ']' .. up, "<Cmd>lua MiniBracketed.indent('last')<CR>",  { desc = 'Indent last' })
    H.map('x', ']' .. up, "<Cmd>lua MiniBracketed.indent('last')<CR>",  { desc = 'Indent last' })
    H.map('o', ']' .. up, "V<Cmd>lua MiniBracketed.indent('last')<CR>", { desc = 'Indent last' })

    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.indent('backward')<CR>",  { desc = 'Indent backward' })
    H.map('x', '[' .. low, "<Cmd>lua MiniBracketed.indent('backward')<CR>",  { desc = 'Indent backward' })
    H.map('o', '[' .. low, "V<Cmd>lua MiniBracketed.indent('backward')<CR>", { desc = 'Indent backward' })

    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.indent('forward')<CR>",  { desc = 'Indent forward' })
    H.map('x', ']' .. low, "<Cmd>lua MiniBracketed.indent('forward')<CR>",  { desc = 'Indent forward' })
    H.map('o', ']' .. low, "V<Cmd>lua MiniBracketed.indent('forward')<CR>", { desc = 'Indent forward' })
  end

  if config.jump.suffix ~= '' then
    -- No Visual mode mappings due to implementation problems ()
    local low, up = H.get_suffix_variants(config.jump.suffix)
    H.map('n', '[' .. up, "<Cmd>lua MiniBracketed.jump('first')<CR>",  { desc = 'Jump first' })
    H.map('o', '[' .. up, "v<Cmd>lua MiniBracketed.jump('first')<CR>", { desc = 'Jump first' })

    H.map('n', ']' .. up, "<Cmd>lua MiniBracketed.jump('last')<CR>",  { desc = 'Jump last' })
    H.map('o', ']' .. up, "v<Cmd>lua MiniBracketed.jump('last')<CR>", { desc = 'Jump last' })

    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.jump('backward')<CR>",  { desc = 'Jump backward' })
    H.map('o', '[' .. low, "v<Cmd>lua MiniBracketed.jump('backward')<CR>", { desc = 'Jump backward' })

    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.jump('forward')<CR>",  { desc = 'Jump forward' })
    H.map('o', ']' .. low, "v<Cmd>lua MiniBracketed.jump('forward')<CR>", { desc = 'Jump forward' })
  end

  if config.oldfile.suffix ~= '' then
    local low, up = H.get_suffix_variants(config.oldfile.suffix)
    H.map('n', '[' .. up,  "<Cmd>lua MiniBracketed.oldfile('first')<CR>",    { desc = 'Oldfile first' })
    H.map('n', ']' .. up,  "<Cmd>lua MiniBracketed.oldfile('last')<CR>",     { desc = 'Oldfile last' })
    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.oldfile('backward')<CR>", { desc = 'Oldfile backward' })
    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.oldfile('forward')<CR>",  { desc = 'Oldfile forward' })
  end

  if config.location.suffix ~= '' then
    local low, up = H.get_suffix_variants(config.location.suffix)
    H.map('n', '[' .. up,  "<Cmd>lua MiniBracketed.location('first')<CR>",    { desc = 'Location first' })
    H.map('n', ']' .. up,  "<Cmd>lua MiniBracketed.location('last')<CR>",     { desc = 'Location last' })
    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.location('backward')<CR>", { desc = 'Location backward' })
    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.location('forward')<CR>",  { desc = 'Location forward' })
  end

  if config.quickfix.suffix ~= '' then
    local low, up = H.get_suffix_variants(config.quickfix.suffix)
    H.map('n', '[' .. up,  "<Cmd>lua MiniBracketed.quickfix('first')<CR>",    { desc = 'Quickfix first' })
    H.map('n', ']' .. up,  "<Cmd>lua MiniBracketed.quickfix('last')<CR>",     { desc = 'Quickfix last' })
    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.quickfix('backward')<CR>", { desc = 'Quickfix backward' })
    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.quickfix('forward')<CR>",  { desc = 'Quickfix forward' })
  end

  if config.treesitter.suffix ~= '' then
    local low, up = H.get_suffix_variants(config.treesitter.suffix)
    H.map('n', '[' .. up, "<Cmd>lua MiniBracketed.treesitter('first')<CR>",  { desc = 'Treesitter first' })
    H.map('x', '[' .. up, "<Cmd>lua MiniBracketed.treesitter('first')<CR>",  { desc = 'Treesitter first' })
    H.map('o', '[' .. up, "v<Cmd>lua MiniBracketed.treesitter('first')<CR>", { desc = 'Treesitter first' })

    H.map('n', ']' .. up, "<Cmd>lua MiniBracketed.treesitter('last')<CR>",  { desc = 'Treesitter last' })
    H.map('x', ']' .. up, "<Cmd>lua MiniBracketed.treesitter('last')<CR>",  { desc = 'Treesitter last' })
    H.map('o', ']' .. up, "v<Cmd>lua MiniBracketed.treesitter('last')<CR>", { desc = 'Treesitter last' })

    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.treesitter('backward')<CR>",  { desc = 'Treesitter backward' })
    H.map('x', '[' .. low, "<Cmd>lua MiniBracketed.treesitter('backward')<CR>",  { desc = 'Treesitter backward' })
    H.map('o', '[' .. low, "v<Cmd>lua MiniBracketed.treesitter('backward')<CR>", { desc = 'Treesitter backward' })

    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.treesitter('forward')<CR>",  { desc = 'Treesitter forward' })
    H.map('x', ']' .. low, "<Cmd>lua MiniBracketed.treesitter('forward')<CR>",  { desc = 'Treesitter forward' })
    H.map('o', ']' .. low, "v<Cmd>lua MiniBracketed.treesitter('forward')<CR>", { desc = 'Treesitter forward' })
  end

  if config.undo.suffix ~= '' then
    local low, up = H.get_suffix_variants(config.undo.suffix)
    H.map('n', '[' .. up,  "<Cmd>lua MiniBracketed.undo('first')<CR>",    { desc = 'Undo first' })
    H.map('n', ']' .. up,  "<Cmd>lua MiniBracketed.undo('last')<CR>",     { desc = 'Undo last' })
    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.undo('backward')<CR>", { desc = 'Undo backward' })
    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.undo('forward')<CR>",  { desc = 'Undo forward' })

    H.map('n', 'u',     'u<Cmd>lua MiniBracketed.register_undo_state()<CR>')
    H.map('n', '<C-R>', '<C-R><Cmd>lua MiniBracketed.register_undo_state()<CR>')
  end

  if config.window.suffix ~= '' then
    local low, up = H.get_suffix_variants(config.window.suffix)
    H.map('n', '[' .. up,  "<Cmd>lua MiniBracketed.window('first')<CR>",    { desc = 'Window first' })
    H.map('n', ']' .. up,  "<Cmd>lua MiniBracketed.window('last')<CR>",     { desc = 'Window last' })
    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.window('backward')<CR>", { desc = 'Window backward' })
    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.window('forward')<CR>",  { desc = 'Window forward' })
  end

  if config.yank.suffix ~= '' then
    local low, up = H.get_suffix_variants(config.yank.suffix)
    H.map('n', '[' .. up,  "<Cmd>lua MiniBracketed.yank('first')<CR>",    { desc = 'Yank first' })
    H.map('n', ']' .. up,  "<Cmd>lua MiniBracketed.yank('last')<CR>",     { desc = 'Yank last' })
    H.map('n', '[' .. low, "<Cmd>lua MiniBracketed.yank('backward')<CR>", { desc = 'Yank backward' })
    H.map('n', ']' .. low, "<Cmd>lua MiniBracketed.yank('forward')<CR>",  { desc = 'Yank forward' })
  end
end

H.get_suffix_variants = function(char) return char:lower(), char:upper() end

H.create_autocommands = function()
  local gr = vim.api.nvim_create_augroup('MiniBracketed', {})

  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = gr, pattern = pattern, callback = callback, desc = desc })
  end

  au('BufEnter', '*', H.track_oldfile, 'Track oldfile')
  au('TextYankPost', '*', H.track_yank, 'Track yank')
end

H.is_disabled = function() return vim.g.minibracketed_disable == true or vim.b.minibracketed_disable == true end

H.get_config = function(config)
  return vim.tbl_deep_extend('force', MiniBracketed.config, vim.b.minibracketed_config or {}, config or {})
end

-- Autocommands ---------------------------------------------------------------
H.track_oldfile = function()
  if H.is_disabled() then return end

  -- Ensure tracking data is initialized
  H.oldfile_ensure_initialized()

  -- Reset tracking indicator to allow proper tracking of next buffer
  local is_advancing = H.cache.oldfile.is_advancing
  H.cache.oldfile.is_advancing = false

  -- Track only appropriate buffers (normal buffers with path)
  local path = vim.api.nvim_buf_get_name(0)
  local is_proper_buffer = path ~= '' and vim.bo.buftype == ''
  if not is_proper_buffer then return end

  -- If advancing, don't touch tracking data to be able to consecutively move
  -- along recent files. Cache advanced buffer name to later update recency of
  -- the last one (just before buffer switching outside of `oldfile()`)
  local cache_oldfile = H.cache.oldfile

  if is_advancing then
    cache_oldfile.last_advanced_bufname = path
    return
  end

  -- If not advancing, update recency of a single latest advanced buffer (if
  -- present) and then update recency of current buffer
  if cache_oldfile.last_advanced_bufname ~= nil then
    H.oldfile_update_recency(cache_oldfile.last_advanced_bufname)
    cache_oldfile.last_advanced_bufname = nil
  end

  H.oldfile_update_recency(path)
end

H.track_yank = function()
  -- Don't track if asked not to. Allows other functionality to disable
  -- tracking (like in 'mini.move').
  if H.is_disabled() then return end

  -- Track all `TextYankPost` events without exceptions. This leads to a better
  -- handling of charwise/linewise/blockwise selection detection.
  local event = vim.v.event
  table.insert(
    H.cache.yank.history,
    { operator = event.operator, regcontents = event.regcontents, regtype = event.regtype }
  )

  H.yank_stop_advancing()
end

-- Comments -------------------------------------------------------------------
H.make_comment_checker = function()
  local left, right = unpack(vim.fn.split(vim.bo.commentstring, '%s'))
  left, right = left or '', right or ''
  if left == '' and right == '' then return nil end

  -- String is commented if it has structure:
  -- <space> <left> <anything> <right> <space>
  local regex = string.format('^%%s-%s.*%s%%s-$', vim.pesc(vim.trim(left)), vim.pesc(vim.trim(right)))

  -- Check if line with number `line_num` is a comment. NOTE: `getline()`
  -- return empty string for invalid line number, which makes them *not
  -- commented*.
  return function(line_num) return vim.fn.getline(line_num):find(regex) ~= nil end
end

-- Conflicts ------------------------------------------------------------------
H.is_conflict_mark = function(line_num)
  local l_start = vim.fn.getline(line_num):sub(1, 8)
  return l_start == '<<<<<<< ' or l_start == '=======' or l_start == '>>>>>>> '
end

-- Diagnostic -----------------------------------------------------------------
H.diagnostic_jump = function(pos, float, severity)
  vim.diagnostic.jump({ count = 1, pos = pos, float = float, severity = severity })
end
if vim.fn.has('nvim-0.11') == 0 then
  H.diagnostic_jump = function(pos, float, severity)
    vim.diagnostic.goto_next({ cursor_position = pos, float = float, severity = severity })
  end
end

-- Files ----------------------------------------------------------------------
H.get_file_data = function()
  -- Compute target directory
  local cur_buf_path = vim.api.nvim_buf_get_name(0)
  local dir_path = cur_buf_path ~= '' and vim.fn.fnamemodify(cur_buf_path, ':p:h') or vim.fn.getcwd()

  -- Compute sorted array of all files in target directory
  local dir_handle = vim.uv.fs_scandir(dir_path)
  local files_stream = function() return vim.uv.fs_scandir_next(dir_handle) end

  local files = {}
  for basename, fs_type in files_stream do
    if fs_type == 'file' then table.insert(files, basename) end
  end

  -- - Sort files ignoring case
  table.sort(files, function(x, y) return x:lower() < y:lower() end)

  if #files == 0 then return end
  return { directory = dir_path, file_basenames = files }
end

-- Jumps ----------------------------------------------------------------------
H.make_jump = function(jump_list, cur_jump_num, new_jump_num)
  local num_diff = new_jump_num - cur_jump_num

  if num_diff == 0 then
    -- Perform jump manually to always jump. Example: move to last jump and
    -- move manually; then jump with "last" direction should move to last jump.
    local jump_entry = jump_list[new_jump_num]
    pcall(vim.fn.cursor, { jump_entry.lnum, jump_entry.col + 1, jump_entry.coladd })
  else
    -- Use builtin mappings to also update current jump entry
    local key = num_diff > 0 and '\t' or '\15'
    vim.cmd('normal! ' .. math.abs(num_diff) .. key)
  end

  -- Open just enough folds
  vim.cmd('normal! zv')
end

-- Oldfile --------------------------------------------------------------------
H.oldfile_normalize = function()
  -- Ensure that tracking data is initialized
  H.oldfile_ensure_initialized()

  -- Order currently readable paths in increasing order of recency
  local recency_pairs = {}
  for path, rec in pairs(H.cache.oldfile.recency) do
    if vim.fn.filereadable(path) == 1 then table.insert(recency_pairs, { path, rec }) end
  end
  table.sort(recency_pairs, function(x, y) return x[2] < y[2] end)

  -- Construct new tracking data with recency from 1 to number of entries
  local new_recency = {}
  for i, pair in ipairs(recency_pairs) do
    new_recency[pair[1]] = i
  end

  H.cache.oldfile = { recency = new_recency, max_recency = #recency_pairs, is_advancing = H.cache.oldfile.is_advancing }
end

H.oldfile_ensure_initialized = function()
  if H.cache.oldfile ~= nil or vim.v.oldfiles == nil then return end

  local n = #vim.v.oldfiles
  local recency = {}
  for i, path in ipairs(vim.v.oldfiles) do
    recency[path] = n - i + 1
  end

  H.cache.oldfile = { recency = recency, max_recency = n, is_advancing = false }
end

H.oldfile_get_array = function()
  local res = {}
  for path, i in pairs(H.cache.oldfile.recency) do
    res[i] = path
  end
  return res
end

H.oldfile_update_recency = function(path)
  local n = H.cache.oldfile.max_recency + 1
  H.cache.oldfile.recency[path] = n
  H.cache.oldfile.max_recency = n
end

-- Quickfix/Location lists ----------------------------------------------------
H.qf_loc_implementation = function(list_type, direction, opts)
  local get_list, goto_command = vim.fn.getqflist, 'cc'
  if list_type == 'location' then
    get_list, goto_command = function(...) return vim.fn.getloclist(0, ...) end, 'll'
  end

  -- Define iterator that traverses quickfix/location list entries
  local list = get_list()
  local n_list = #list
  if n_list == 0 then return end

  local iterator = {}

  iterator.next = function(ind)
    if ind == nil or n_list <= ind then return end
    return ind + 1
  end

  iterator.prev = function(ind)
    if ind == nil or ind <= 1 then return end
    return ind - 1
  end

  iterator.state = get_list({ idx = 0 }).idx
  iterator.start_edge = 0
  iterator.end_edge = n_list + 1

  -- Iterate
  local res_ind = MiniBracketed.advance(iterator, direction, opts)

  -- Apply. Focus target entry, open enough folds and center. Allow jumping to
  -- current quickfix/loclist entry as it might be different from current
  -- cursor position.
  vim.cmd(goto_command .. ' ' .. res_ind)
  vim.cmd('normal! zvzz')
end

-- Treesitter -----------------------------------------------------------------
H.get_treesitter_node = function(row, col) return vim.treesitter.get_node({ pos = { row, col } }) end

-- Undo -----------------------------------------------------------------------
H.undo_sync = function(buf_id, tree, is_advancing)
  -- Get or initialize buffer history of visited undo states
  local prev_buf_history = H.cache.undo[buf_id] or H.undo_init(tree)
  if is_advancing == nil then is_advancing = prev_buf_history.is_advancing end

  -- Prune current buffer history to contain only allowed state numbers. This
  -- assumes that once undo state is not allowed, it will always be not
  -- allowed. This step is needed because allowed undo state numbers can:
  -- - Not start from 1 due to 'undolevels'.
  -- - Contain range of missing state numbers due to `:undo!`.
  --
  -- Do this even if advancing because `:undo!` can be executed at any time.
  local allowed_states = H.undo_get_allowed_state_numbers(tree)

  local buf_history = {}
  for i, state_num in ipairs(prev_buf_history) do
    -- Use only allowed states
    if allowed_states[state_num] then H.undo_append_state(buf_history, state_num) end

    -- Correctly track current id when advancing
    if i == prev_buf_history.current_id then buf_history.current_id = #buf_history end
  end
  buf_history.current_id = buf_history.current_id or #buf_history
  buf_history.is_advancing = prev_buf_history.is_advancing
  buf_history.seq_last = prev_buf_history.seq_last

  H.cache.undo[buf_id] = buf_history

  -- Continue only if not actually advancing: either if set so manually *or* if
  -- there were additions to undo history *or* some states became not allowed
  -- (due to `:undo!`).
  if is_advancing and tree.seq_last <= buf_history.seq_last and #buf_history == #prev_buf_history then return end

  -- Register current undo state (if not equal to last).
  -- Usually it is a result of advance but also can be due to `:undo`/`:undo!`.
  H.undo_append_state(buf_history, tree.seq_cur)

  -- Add all new *allowed* undo states created since last sync
  for new_state = buf_history.seq_last + 1, tree.seq_last do
    if allowed_states[new_state] then H.undo_append_state(buf_history, new_state) end
  end

  -- Update data to be most recent
  buf_history.current_id = #buf_history
  buf_history.is_advancing = false
  buf_history.seq_last = tree.seq_last
end

H.undo_append_state = function(buf_history, state_num)
  -- Ensure that there are no two consecutive equal states
  if state_num == nil or buf_history[#buf_history] == state_num then return end

  table.insert(buf_history, state_num)
end

H.undo_init = function(tree)
  -- Assume all previous states are allowed
  local res = {}
  for i = 0, tree.seq_last do
    res[i + 1] = i
  end
  res.current_id = #res
  res.is_advancing = false
  res.seq_last = tree.seq_last

  return res
end

H.undo_get_allowed_state_numbers = function(tree)
  -- `:undo 0` is always possible (goes to *before* the first allowed state).
  local res = { [0] = true }
  local traverse
  traverse = function(entries)
    for _, e in ipairs(entries) do
      if e.alt ~= nil then traverse(e.alt) end
      res[e.seq] = true
    end
  end

  traverse(tree.entries)
  return res
end

-- Yank -----------------------------------------------------------------------
H.yank_stop_advancing = function()
  H.cache.yank.current_id = #H.cache.yank.history
  H.cache.yank.is_advancing = false
  H.cache.yank.advance_put_regions[vim.api.nvim_get_current_buf()] = nil
end

H.get_yank_state = function() return { buf_id = vim.api.nvim_get_current_buf(), changedtick = vim.b.changedtick } end

H.replace_latest_put_region = function(yank_data)
  -- Squash all yank advancing in a single undo block
  local normal_command = (H.cache.yank.is_advancing and 'undojoin | ' or '') .. 'silent normal! '
  local normal_fun = function(x) vim.cmd(normal_command .. x) end

  -- Compute latest put region: from latest `yank` advance; or from user's
  -- latest put; or from `[`/`]` marks
  local cache_yank = H.cache.yank
  local buf_id = vim.api.nvim_get_current_buf()
  local latest_region = cache_yank.advance_put_regions[buf_id]
    or cache_yank.user_put_regions[buf_id]
    or H.get_latest_region()

  -- Compute modes for replaced and new regions.
  local latest_mode = latest_region.mode
  local new_mode = yank_data.regtype:sub(1, 1)

  -- Compute later put key based on replaced and new regions.
  -- Prefer `P` but use `p` in cases replaced region was on the edge: last line
  -- for linewise-linewise replace or last column for nonlinewise-nonlinewise.
  local is_linewise = (latest_mode == 'V' and new_mode == 'V')
  local is_edge_line = is_linewise and latest_region.to.line == vim.fn.line('$')

  local is_charblockwise = (latest_mode ~= 'V' and new_mode ~= 'V')
  local is_edge_col = is_charblockwise and latest_region.to.col == vim.fn.getline(latest_region.to.line):len()

  local is_edge = is_edge_line or is_edge_col
  local put_key = is_edge and 'p' or 'P'

  -- Delete latest region
  H.region_delete(latest_region, normal_fun)

  -- Paste yank data using temporary register
  local cache_z_reg = vim.fn.getreg('z')
  vim.fn.setreg('z', yank_data.regcontents, yank_data.regtype)

  normal_fun('"z' .. put_key)

  vim.fn.setreg('z', cache_z_reg)

  -- Register newly put region for correct further advancing
  cache_yank.advance_put_regions[buf_id] = H.get_latest_region(new_mode)
end

H.get_latest_region = function(mode)
  local left, right = vim.fn.getpos("'["), vim.fn.getpos("']")
  return {
    from = { line = left[2], col = left[3] },
    to = { line = right[2], col = right[3] },
    -- Mode should be one of 'v', 'V', or '\22' ('<C-v>')
    -- By default use mode of current or unnamed register
    -- NOTE: this breaks if latest paste was not from unnamed register.
    -- To account for that, use `register_put_region()`.
    mode = mode or H.get_register_mode(vim.v.register),
  }
end

H.region_delete = function(region, normal_fun)
  -- Start with `to` to have cursor positioned on region start after deletion
  H.set_cursor(region.to.line, region.to.col - 1)

  -- Do nothing more if region is empty (or leads to unnecessary line deletion)
  local is_empty = region.from.line == region.to.line
    and region.from.col == region.to.col
    and vim.fn.getline(region.from.line) == ''

  if is_empty then return end

  -- Select region in correct Visual mode
  normal_fun(region.mode)
  H.set_cursor(region.from.line, region.from.col - 1)

  -- Delete region in "black hole" register
  -- - NOTE: it doesn't affect history as `"_` doesn't trigger `TextYankPost`
  normal_fun('"_d')
end

H.get_register_mode = function(register)
  -- Use only first character to correctly get '\22' in blockwise mode
  return vim.fn.getregtype(register):sub(1, 1)
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.bracketed) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.validate_direction = function(direction, choices, fun_name)
  if not vim.tbl_contains(choices, direction) then
    local choices_string = "'" .. table.concat(choices, "', '") .. "'"
    local error_text = string.format('In `%s()` argument `direction` should be one of %s.', fun_name, choices_string)
    H.error(error_text)
  end
end

H.map = function(mode, lhs, rhs, opts)
  if lhs == '' then return end
  opts = vim.tbl_deep_extend('force', { silent = true }, opts or {})
  vim.keymap.set(mode, lhs, rhs, opts)
end

H.edit = function(path, win_id)
  if type(path) ~= 'string' then return end
  local b = vim.api.nvim_win_get_buf(win_id or 0)
  local try_mimic_buf_reuse = (vim.fn.bufname(b) == '' and vim.bo[b].buftype ~= 'quickfix' and not vim.bo[b].modified)
    and (#vim.fn.win_findbuf(b) == 1 and vim.deep_equal(vim.fn.getbufline(b, 1, '$'), { '' }))
  local buf_id = vim.fn.bufadd(vim.fn.fnamemodify(path, ':.'))
  -- Showing in window also loads. Use `pcall` to not error with swap messages.
  pcall(vim.api.nvim_win_set_buf, win_id or 0, buf_id)
  vim.bo[buf_id].buflisted = true
  if try_mimic_buf_reuse then pcall(vim.api.nvim_buf_delete, b, { unload = false }) end
  return buf_id
end

H.add_to_jumplist = function() vim.cmd([[normal! m']]) end

H.set_cursor = function(row, col)
  if row <= 0 then return vim.api.nvim_win_set_cursor(0, { 1, 0 }) end
  local n_lines = vim.api.nvim_buf_line_count(0)
  if n_lines < row then return vim.api.nvim_win_set_cursor(0, { n_lines, vim.fn.getline(n_lines):len() - 1 }) end
  col = math.min(math.max(col, 0), vim.fn.getline(row):len())
  return vim.api.nvim_win_set_cursor(0, { row, col })
end

return MiniBracketed
