--- *mini.comment* Comment lines
---
--- MIT License Copyright (c) 2021 Evgeni Chasnovski

--- Features:
--- - Commenting in Normal mode respects |count| and is dot-repeatable.
---
--- - Comment structure by default is inferred from 'commentstring': either
---   from current buffer or from locally active tree-sitter language.
---   It can be customized via `options.custom_commentstring`
---   (see |MiniComment.config| for details).
---
--- - Allows custom hooks before and after successful commenting.
---
--- - Configurable options for some nuanced behavior.
---
--- What it doesn't do:
--- - Block and sub-line comments. This will only support per-line commenting.
---
--- - Handle indentation with mixed tab and space.
---
--- - Preserve trailing whitespace in empty lines.
---
--- Notes:
--- - To use tree-sitter aware commenting, global value of 'commentstring'
---   should be `''` (empty string). This is the default value, so make sure to
---   not set it manually to a different value.
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.comment').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table
--- `MiniComment` which you can use for scripting or manually (with
--- `:lua MiniComment.*`).
---
--- See |MiniComment.config| for `config` structure and default values.
---
--- You can override runtime config settings locally to buffer inside
--- `vim.b.minicomment_config` which should have same structure as
--- `MiniComment.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- # Disabling ~
---
--- To disable core functionality, set `vim.g.minicomment_disable` (globally) or
--- `vim.b.minicomment_disable` (for a buffer) to `true`. Considering high number
--- of different scenarios and customization intentions, writing exact rules
--- for disabling module's functionality is left to user. See
--- |mini.nvim-disabling-recipes| for common recipes.
---@tag MiniComment

-- Module definition ==========================================================
local MiniComment = {}
local H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniComment.config|.
---
---@usage >lua
---   require('mini.comment').setup() -- use default config
---   -- OR
---   require('mini.comment').setup({}) -- replace {} with your config table
--- <
MiniComment.setup = function(config)
  -- Export module
  _G.MiniComment = MiniComment

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)
end

--- Defaults ~
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text # Options ~
---
--- ## Custom commentstring ~
---
--- `options.custom_commentstring` can be a function customizing 'commentstring'
--- option used to infer comment structure. It is called once before every
--- commenting action with the following arguments:
--- - `ref_position` - position at which to compute 'commentstring' (might be
---   relevant for a text with locally different commenting rules). Its structure
---   is the same as `opts.ref_position` in |MiniComment.toggle_lines()|.
---
--- Its output should be a valid 'commentstring' (string containing `%s`).
---
--- If not set or the output is `nil`, |MiniComment.get_commentstring()| is used.
---
--- For example, this option can be used to always use buffer 'commentstring'
--- even in case of present active tree-sitter parser: >lua
---
---   require('mini.comment').setup({
---     options = {
---       custom_commentstring = function() return vim.bo.commentstring end,
---     }
---   })
--- <
--- # Hooks ~
---
--- `hooks.pre` and `hooks.post` functions are executed before and after successful
--- commenting action (toggle or computing textobject). They will be called
--- with a single table argument which has the following fields:
--- - <action> `(string)` - action name. One of "toggle" (when actual toggle
---   direction is yet unknown), "comment", "uncomment", "textobject".
--- - <line_start> `(number|nil)` - action start line. Can be absent if yet unknown.
--- - <line_end> `(number|nil)` - action end line. Can be absent if yet unknown.
--- - <ref_position> `(table|nil)` - reference position.
---
--- Notes:
--- - Changing 'commentstring' in `hooks.pre` is allowed and will take effect.
--- - If hook returns `false`, any further action is terminated.
MiniComment.config = {
  -- Options which control module behavior
  options = {
    -- Function to compute custom 'commentstring' (optional)
    custom_commentstring = nil,

    -- Whether to ignore blank lines in actions and textobject
    ignore_blank_line = false,

    -- Whether to ignore blank lines at beginning or end of range selection
    ignore_surrounding_blank_line = false,

    -- Whether to recognize as comment only lines without indent
    start_of_line = false,

    -- Whether to force single space inner padding for comment parts
    pad_comment_parts = true,
  },

  -- Module mappings. Use `''` (empty string) to disable one.
  mappings = {
    -- Toggle comment (like `gcip` - comment inner paragraph) for both
    -- Normal and Visual modes
    comment = 'gc',

    -- Toggle comment on current line
    comment_line = 'gcc',

    -- Toggle comment on visual selection
    comment_visual = 'gc',

    -- Define 'comment' textobject (like `dgc` - delete whole comment block)
    -- Works also in Visual mode if mapping differs from `comment_visual`
    textobject = 'gc',
  },

  -- Hook functions to be executed at certain stage of commenting
  hooks = {
    -- Before successful commenting. Does nothing by default.
    pre = function() end,
    -- After successful commenting. Does nothing by default.
    post = function() end,
  },
}
--minidoc_afterlines_end

-- Module functionality =======================================================
--- Main function to be mapped
---
--- It is meant to be used in expression mappings (see |:map-<expr>|) to enable
--- dot-repeatability and commenting on range. There is no need to do this
--- manually, everything is done inside |MiniComment.setup()|.
---
--- It has a somewhat unintuitive logic (because of how expression mapping with
--- dot-repeatability works): it should be called without arguments inside
--- expression mapping and with argument when action should be performed.
---
---@param mode string|nil Optional string with 'operatorfunc' mode (see |g@|).
---
---@return string|nil 'g@' if called without argument, '' otherwise (but after
---   performing action).
MiniComment.operator = function(mode)
  if H.is_disabled() then return '' end

  -- If used without arguments inside expression mapping:
  -- - Set itself as `operatorfunc` to be called later to perform action.
  -- - Return 'g@' which will then be executed resulting into waiting for a
  --   motion or text object. This textobject will then be recorded using `'[`
  --   and `']` marks. After that, `operatorfunc` is called with `mode` equal
  --   to one of "line", "char", or "block".
  -- NOTE: setting `operatorfunc` inside this function enables usage of 'count'
  -- like `10gc_` toggles comments of 10 lines below (starting with current).
  if mode == nil then
    vim.o.operatorfunc = 'v:lua.MiniComment.operator'
    return 'g@'
  end

  -- If called with non-nil `mode`, get target region and act on it
  -- This also works in expression mapping in Visual mode, as `g@` seems to
  -- place these marks on start and end of visual selection
  local mark_left, mark_right = '[', ']'
  local lnum_from, col_from = unpack(vim.api.nvim_buf_get_mark(0, mark_left))
  local lnum_to, col_to = unpack(vim.api.nvim_buf_get_mark(0, mark_right))

  -- Do nothing if "from" mark is after "to" (like in empty textobject)
  if (lnum_from > lnum_to) or (lnum_from == lnum_to and col_from > col_to) then return end

  -- NOTE: use cursor position as reference for possibly computing local
  -- tree-sitter-based 'commentstring'. Recompute every time for a proper
  -- dot-repeat. In Visual and sometimes Normal mode it uses left position.
  local cursor = vim.api.nvim_win_get_cursor(0)

  local config = H.get_config()
  if (lnum_from ~= lnum_to) and config.options.ignore_surrounding_blank_line then
    lnum_from = vim.fn.nextnonblank(lnum_from)
    lnum_to = vim.fn.prevnonblank(lnum_to)
    cursor = { lnum_from, 1 }
  end
  MiniComment.toggle_lines(lnum_from, lnum_to, { ref_position = { cursor[1], cursor[2] + 1 } })
  return ''
end

--- Toggle comments between two line numbers
---
--- It uncomments if lines are comment (every line is a comment or blank) and
--- comments otherwise. It respects indentation and doesn't insert trailing
--- whitespace. Toggle commenting not in visual mode is also dot-repeatable
--- and respects |count|.
---
--- # Notes ~
---
--- - Comment structure is inferred from buffer's 'commentstring' option or
---   local language of tree-sitter parser (if active).
---
--- - Call to this function will remove all |extmarks| from target range.
---
---@param line_start number Start line number (inclusive from 1 to number of lines).
---@param line_end number End line number (inclusive from 1 to number of lines).
---@param opts table|nil Options. Possible fields:
---   - <ref_position> `(table)` - A two-value array with `{ row, col }` (both
---     starting at 1) of reference position at which 'commentstring' value
---     will be computed. Default: `{ line_start, 1 }`.
MiniComment.toggle_lines = function(line_start, line_end, opts)
  if H.is_disabled() then return end

  opts = opts or {}
  local ref_position = vim.deepcopy(opts.ref_position) or { line_start, 1 }

  local n_lines = vim.api.nvim_buf_line_count(0)
  if not (1 <= line_start and line_start <= n_lines and 1 <= line_end and line_end <= n_lines) then
    error('(mini.comment) `line_start` and `line_end` should be within range [1; ' .. n_lines .. '].')
  end
  if not (line_start <= line_end) then
    error('(mini.comment) `line_start` should be less than or equal to `line_end`.')
  end

  local config = H.get_config()
  local hook_arg = { action = 'toggle', line_start = line_start, line_end = line_end, ref_position = ref_position }
  if config.hooks.pre(hook_arg) == false then return end

  local parts = H.get_comment_parts(ref_position, config.options)
  local lines = vim.api.nvim_buf_get_lines(0, line_start - 1, line_end, false)
  local indent, is_comment = H.get_lines_info(lines, parts, config.options)

  local f = is_comment and H.make_uncomment_function(parts) or H.make_comment_function(parts, indent, config.options)

  -- NOTE: Direct of `nvim_buf_set_lines()` essentially removes (squashes to
  -- empty range at either side of the region) both regular and extended marks
  -- inside region. It can be resolved at least in the following ways:
  -- 1. Use `lockmarks`. Preserves regular but does nothing for extmarks.
  -- 2. Use `vim.fn.setline(line_start, new_lines)`. Preserves regular marks,
  --    but squashes extmarks within a single line.
  -- 3. Refactor to use precise editing of lines with `nvim_buf_set_text()`.
  --    Preserves both regular and extended marks.
  --
  -- But:
  -- - Options 2 and 3 are **significantly** slower for a large-ish regions.
  --   Toggle of ~4000 lines takes 20 ms for 1, 200 ms for 2, 400 ms for 3.
  --
  -- - Preserving extmarks is not a universally good thing to do. It looks like
  --   a good idea for extmarks which are not used for directly highlighting
  --   text (like for 'mini.diff' signs or smartly tracking buffer position).
  --   However, preserving extmarks is not 100% desirable when they highlight
  --   text area, as every comment toggle at least results in a flickering
  --   due to those extmarks still highlighting a (un)commented region.
  --   Main example is LSP semantic token highlighting. Although it can have
  --   special treatment (precisely clear those extmarks in the target region),
  --   it is not 100% effective (they are restored after undo, again resulting
  --   into flicker) and there might be more unnoticed issues.
  --
  -- So all in all, computing and replacing whole lines with `lockmarks` is the
  -- best compromise so far. It also aligns with treating "toggle comment" in
  -- a semantic way (those lines lines now have completely different meaning)
  -- rather than in a text edit way (add comment parts to those lines).
  _G._from, _G._to, _G._lines = line_start - 1, line_end, vim.tbl_map(f, lines)
  vim.cmd('lockmarks lua pcall(vim.api.nvim_buf_set_lines, 0, _G._from, _G._to, false, _G._lines)')
  _G._from, _G._to, _G._lines = nil, nil, nil

  hook_arg.action = is_comment and 'uncomment' or 'comment'
  if config.hooks.post(hook_arg) == false then return end
end

--- Select comment textobject
---
--- This selects all commented lines adjacent to cursor line. If `ignore_blank_line`
--- option is enabled (see |MiniComment.config|), blank lines between commented
--- lines are treated as part of textobject.
--- Designed to be used with operator mode mappings (see |mapmode-o|).
MiniComment.textobject = function()
  if H.is_disabled() then return end

  local config = H.get_config()
  local hook_args = { action = 'textobject' }
  if config.hooks.pre(hook_args) == false then return end

  local lnum_cur = vim.fn.line('.')
  local parts = H.get_comment_parts({ lnum_cur, vim.fn.col('.') }, config.options)
  local comment_check = H.make_comment_check(parts, config.options)
  local lnum_from, lnum_to

  local ignore_blank_line = config.options.ignore_blank_line
  local check = function(lnum)
    if lnum == 0 then return false end
    local l = vim.fn.getline(lnum)
    return comment_check(l) or (ignore_blank_line and H.is_blank(l))
  end

  -- Recognize textobject only if on comment or blank between comments
  local lnum_prev, lnum_next = vim.fn.prevnonblank(lnum_cur), vim.fn.nextnonblank(lnum_cur)
  local is_in_comments = check(lnum_prev) and (lnum_prev == lnum_cur or check(lnum_next))

  if is_in_comments then
    lnum_from = lnum_cur
    while (lnum_from >= 2) and check(lnum_from - 1) do
      lnum_from = lnum_from - 1
    end
    if ignore_blank_line then lnum_from = vim.fn.nextnonblank(lnum_from) end

    lnum_to = lnum_cur
    local n_lines = vim.api.nvim_buf_line_count(0)
    while (lnum_to <= n_lines - 1) and check(lnum_to + 1) do
      lnum_to = lnum_to + 1
    end
    if ignore_blank_line then lnum_to = vim.fn.prevnonblank(lnum_to) end

    local is_visual = vim.tbl_contains({ 'v', 'V', '\22' }, vim.fn.mode())
    if is_visual then vim.cmd('normal! \27') end

    -- This visual selection doesn't seem to change `'<` and `'>` marks when
    -- executed as `onoremap` mapping
    vim.cmd('normal! ' .. lnum_from .. 'GV' .. lnum_to .. 'G')
  end

  hook_args.line_start, hook_args.line_end = lnum_from, lnum_to
  if config.hooks.post(hook_args) == false then return end
end

--- Get 'commentstring'
---
--- This function represents default approach of computing relevant
--- 'commentstring' option in current buffer. Used to infer comment structure.
---
--- It has the following logic:
--- - If there is an active tree-sitter parser, try to get 'commentstring' from
---   the local language at `ref_position`.
---
--- - If first step is not successful, use buffer's 'commentstring' directly.
---
---@param ref_position table Reference position inside current buffer at which
---   to compute 'commentstring'. Same structure as `opts.ref_position`
---   in |MiniComment.toggle_lines()|.
---
---@return string Relevant value of 'commentstring'.
MiniComment.get_commentstring = function(ref_position)
  local buf_cs = vim.bo.commentstring

  -- TODO: Remove `opts.error` after compatibility with Neovim=0.11 is dropped
  local has_parser, parser = pcall(vim.treesitter.get_parser, 0, nil, { error = false })
  if not has_parser or parser == nil then return buf_cs end

  -- Try to get 'commentstring' associated with local tree-sitter language.
  -- This is useful for injected languages (like markdown with code blocks).
  -- Sources:
  -- - https://github.com/neovim/neovim/pull/22634#issue-1620078948
  -- - https://github.com/neovim/neovim/pull/22643
  local row, col = ref_position[1] - 1, ref_position[2] - 1
  local ref_range = { row, col, row, col + 1 }

  -- - Get 'commentstring' from the deepest LanguageTree which both contains
  --   reference range and has valid 'commentstring' (meaning it has at least
  --   one associated 'filetype' with valid 'commentstring').
  --   In simple cases using `parser:language_for_range()` would be enough, but
  --   it fails for languages without valid 'commentstring' (like 'comment').
  local ts_cs, res_level = nil, 0
  local traverse

  traverse = function(lang_tree, level)
    if not lang_tree:contains(ref_range) then return end

    local lang = lang_tree:lang()
    local filetypes = vim.treesitter.language.get_filetypes(lang)
    for _, ft in ipairs(filetypes) do
      -- Using `vim.filetype.get_option()` for performance as it has caching
      local cur_cs = vim.filetype.get_option(ft, 'commentstring')
      if type(cur_cs) == 'string' and cur_cs ~= '' and level > res_level then
        ts_cs, res_level = cur_cs, level
      end
    end

    for _, child_lang_tree in pairs(lang_tree:children()) do
      traverse(child_lang_tree, level + 1)
    end
  end
  traverse(parser, 1)

  return ts_cs or buf_cs
end

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniComment.config)

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  H.check_type('options', config.options, 'table')
  H.check_type('options.custom_commentstring', config.options.custom_commentstring, 'function', true)
  H.check_type('options.ignore_blank_line', config.options.ignore_blank_line, 'boolean')
  H.check_type('options.ignore_surrounding_blank_line', config.options.ignore_surrounding_blank_line, 'boolean')
  H.check_type('options.start_of_line', config.options.start_of_line, 'boolean')
  H.check_type('options.pad_comment_parts', config.options.pad_comment_parts, 'boolean')

  H.check_type('mappings', config.mappings, 'table')
  H.check_type('mappings.comment', config.mappings.comment, 'string')
  H.check_type('mappings.comment_line', config.mappings.comment_line, 'string')
  H.check_type('mappings.comment_visual', config.mappings.comment_visual, 'string')
  H.check_type('mappings.textobject', config.mappings.textobject, 'string')

  H.check_type('hooks', config.hooks, 'table')
  H.check_type('hooks.pre', config.hooks.pre, 'function')
  H.check_type('hooks.post', config.hooks.post, 'function')

  return config
end

H.apply_config = function(config)
  MiniComment.config = config

  -- Make mappings
  local operator_rhs = function() return MiniComment.operator() end
  H.map('n', config.mappings.comment, operator_rhs, { expr = true, desc = 'Comment' })
  H.map('x', config.mappings.comment_visual, operator_rhs, { expr = true, desc = 'Comment selection' })
  H.map(
    'n',
    config.mappings.comment_line,
    function() return MiniComment.operator() .. '_' end,
    { expr = true, desc = 'Comment line' }
  )
  -- Use `<Cmd>...<CR>` to have proper dot-repeat
  -- See https://github.com/neovim/neovim/issues/23406
  local modes = config.mappings.textobject == config.mappings.comment_visual and { 'o' } or { 'x', 'o' }
  H.map(modes, config.mappings.textobject, '<Cmd>lua MiniComment.textobject()<CR>', { desc = 'Comment textobject' })
end

H.is_disabled = function() return vim.g.minicomment_disable == true or vim.b.minicomment_disable == true end

H.get_config = function(config)
  return vim.tbl_deep_extend('force', MiniComment.config, vim.b.minicomment_config or {}, config or {})
end

-- Core implementations -------------------------------------------------------
H.get_comment_parts = function(ref_position, options)
  local cs
  if vim.is_callable(options.custom_commentstring) then cs = options.custom_commentstring(ref_position) end
  cs = cs or MiniComment.get_commentstring(ref_position)

  if cs == nil or cs == '' then
    vim.api.nvim_echo({ { '(mini.comment) ', 'WarningMsg' }, { [[Option 'commentstring' is empty.]] } }, true, {})
    return { left = '', right = '' }
  end

  if not (type(cs) == 'string' and string.find(cs, '%%s') ~= nil) then
    H.error(vim.inspect(cs) .. " is not a valid 'commentstring'.")
  end

  -- Structure of 'commentstring': <left part> <%s> <right part>
  local left, right = string.match(cs, '^(.-)%%s(.-)$')

  -- Force single space padding if requested
  if options.pad_comment_parts then
    left, right = vim.trim(left), vim.trim(right)
    left, right = left == '' and '' or (left .. ' '), right == '' and '' or (' ' .. right)
  end
  return { left = left, right = right }
end

H.make_comment_check = function(parts, options)
  local l_esc, r_esc = vim.pesc(parts.left), vim.pesc(parts.right)
  local prefix = options.start_of_line and '' or '%s-'

  -- Commented line has the following structure:
  -- <whitespace> <trimmed left> <anything> <trimmed right> <whitespace>
  local regex = '^' .. prefix .. vim.trim(l_esc) .. '.*' .. vim.trim(r_esc) .. '%s-$'

  return function(line) return string.find(line, regex) ~= nil end
end

H.get_lines_info = function(lines, parts, options)
  local comment_check = H.make_comment_check(parts, options)

  local is_commented = true
  local indent, indent_width = nil, math.huge

  for _, l in ipairs(lines) do
    -- Update lines indent: minimum of all indents except blank lines
    local _, indent_width_cur, indent_cur = string.find(l, '^(%s*)')

    -- Ignore blank lines completely when making a decision
    if indent_width_cur < l:len() then
      -- NOTE: Copying actual indent instead of recreating it with `indent_width`
      -- allows to handle both tabs and spaces
      if indent_width_cur < indent_width then
        indent_width, indent = indent_width_cur, indent_cur
      end

      -- Update comment info: commented if every non-blank line is commented
      if is_commented then is_commented = comment_check(l) end
    end
  end

  -- `indent` can still be `nil` in case all `lines` are empty
  return indent or '', is_commented
end

H.make_comment_function = function(parts, indent, options)
  local prefix = options.start_of_line and (parts.left .. indent) or (indent .. parts.left)
  local nonindent_start = string.len(indent) + 1
  local suffix = parts.right

  local blank_comment = indent .. vim.trim(parts.left) .. vim.trim(parts.right)
  local ignore_blank_line = options.ignore_blank_line

  return function(line)
    if H.is_blank(line) then return ignore_blank_line and line or blank_comment end

    return prefix .. string.sub(line, nonindent_start) .. suffix
  end
end

H.make_uncomment_function = function(parts)
  local l_esc, r_esc = vim.pesc(parts.left), vim.pesc(parts.right)
  local regex = '^(%s*)' .. l_esc .. '(.*)' .. r_esc .. '(%s-)$'
  local regex_trimmed = '^(%s*)' .. vim.trim(l_esc) .. '(.*)' .. vim.trim(r_esc) .. '(%s-)$'

  return function(line)
    -- Try regex with exact comment parts first, fall back to trimmed parts
    local indent, new_line, trail = line:match(regex)
    if new_line == nil then
      indent, new_line, trail = line:match(regex_trimmed)
    end

    -- Return original if line is not commented
    if new_line == nil then return line end

    -- Prevent trailing whitespace
    if H.is_blank(new_line) then
      indent, trail = '', ''
    end

    return indent .. new_line .. trail
  end
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.comment) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.map = function(mode, lhs, rhs, opts)
  if lhs == '' then return end
  opts = vim.tbl_deep_extend('force', { silent = true }, opts or {})
  vim.keymap.set(mode, lhs, rhs, opts)
end

H.is_blank = function(x) return string.find(x, '^%s*$') ~= nil end

return MiniComment
