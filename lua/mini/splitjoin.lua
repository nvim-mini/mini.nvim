--- *mini.splitjoin* Split and join arguments
---
--- MIT License Copyright (c) 2023 Evgeni Chasnovski

--- Features:
--- - Mappings and Lua functions that modify arguments (regions inside brackets
---   between allowed separators) under cursor.
---
---   Supported actions:
---     - Toggle - split if arguments are on single line, join otherwise.
---       Main supported function of the module. See |MiniSplitjoin.toggle()|.
---     - Split - make every argument separator be on end of separate line.
---       See |MiniSplitjoin.split()|.
---     - Join - make all arguments be on single line.
---       See |MiniSplitjoin.join()|.
---
--- - Mappings are dot-repeatable in Normal mode and work in Visual mode.
---
--- - Customizable argument detection (see |MiniSplitjoin.config.detect|):
---     - Which brackets can contain arguments.
---     - Which strings can separate arguments.
---     - Which regions are excluded when looking for separators (like inside
---       nested brackets or quotes).
---
--- - Customizable pre and post hooks for both split and join. See `split` and
---   `join` in |MiniSplitjoin.config|. There are several built-in ones
---   in |MiniSplitjoin.gen_hook|.
---
--- - Works inside comments by using modified notion of indent.
---   See |MiniSplitjoin.get_indent_part()|.
---
--- - Provides low-level Lua functions for split and join at positions.
---   See |MiniSplitjoin.split_at()| and |MiniSplitjoin.join_at()|.
---
--- Notes:
--- - Search for arguments is done using Lua patterns (regex-like approach).
---   Certain amount of false positives is to be expected.
---
--- - This module is mostly designed around |MiniSplitjoin.toggle()|. If target
---   split positions are on different lines, join first and then split.
---
--- - Actions can be done on Visual mode selection, which mostly present as
---   a safety route in case of incorrect detection of initial region.
---   It uses |MiniSplitjoin.get_visual_region()| which treats selection as full
---   brackets (include brackets in selection).
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.splitjoin').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `MiniSplitjoin`
--- which you can use for scripting or manually (with `:lua MiniSplitjoin.*`).
---
--- See |MiniSplitjoin.config| for available config settings.
---
--- You can override runtime config settings (like action hooks) locally to
--- buffer inside `vim.b.minisplitjoin_config` which should have same structure
--- as `MiniSplitjoin.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- # Comparisons ~
---
--- - 'FooSoft/vim-argwrap':
---     - Mostly has the same design as this module.
---     - Doesn't work inside comments, while this module does.
---     - Has more built-in ways to control split and join, while this module
---       intentionally provides only handful.
--- - 'AndrewRadev/splitjoin.vim':
---     - More oriented towards language-depended transformations, while this
---       module intntionally deals with more generic text-related functionality.
--- - 'Wansmer/treesj':
---     - Operates based on tree-sitter nodes. This is more accurate in
---       some edge cases, but **requires** tree-sitter parser.
---     - Doesn't work inside comments or strings.
---
--- # Disabling ~
---
--- To disable, set `g:minisplitjoin_disable` (globally) or `b:minisplitjoin_disable`
--- (for a buffer) to `v:true`. Considering high number of different scenarios
--- and customization intentions, writing exact rules for disabling module's
--- functionality is left to user. See |mini.nvim-disabling-recipes| for common
--- recipes.
---@tag MiniSplitjoin

--- - POSITION - table with fields <line> and <col> containing line and column
---   numbers respectively. Both are 1-indexed. Example: `{ line = 2, col = 1 }`.
---
--- - REGION - table representing region in a buffer. Fields: <from> and <to> for
---   inclusive start and end positions. Example: >lua
---
---   { from = { line = 1, col = 1 }, to = { line = 2, col = 1 } }
--- <
---@tag MiniSplitjoin-glossary

---@alias __splitjoin_options table|nil Options. Has structure from |MiniSplitjoin.config|
---   inheriting its default values.
---
---   Following extra optional fields are allowed:
---   - <position> `(table)` - position at which to find smallest bracket region.
---     See |MiniSplitjoin-glossary| for the structure.
---     Default: cursor position.
---   - <region> `(table)` - region at which to perform action. Assumes inclusive
---     both start at left bracket and end at right bracket.
---     See |MiniSplitjoin-glossary| for the structure.
---     Default: `nil` to automatically detect region.
---@alias __splitjoin_hook_brackets - <brackets> `(table)` - array of bracket patterns indicating on which
---      brackets action should be made. Has same structure as `brackets`
---      in |MiniSplitjoin.config.detect|.
---      Default: `MiniSplitjoin.config.detect.brackets`.

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local

-- Module definition ==========================================================
local MiniSplitjoin = {}
local H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniSplitjoin.config|.
---
---@usage >lua
---   require('mini.splitjoin').setup() -- use default config
---   -- OR
---   require('mini.splitjoin').setup({}) -- replace {} with your config table
--- <
MiniSplitjoin.setup = function(config)
  -- Export module
  _G.MiniSplitjoin = MiniSplitjoin

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)
end

--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text                                                    *MiniSplitjoin.config.detect*
--- # Detection ~
---
--- The table at `config.detect` controls how arguments are detected using Lua
--- patterns. General idea is to convert whole buffer into a single line,
--- perform string search, and convert results back into 2d positions.
---
--- Example configuration: >lua
---
---   require('mini.splitjoin').setup({
---     detect = {
---       -- Detect only inside balanced parenthesis
---       brackets = { '%b()' },
---
---       -- Allow both `,` and `;` to separate arguments
---       separator = '[,;]',
---
---       -- Make any separator define an argument
---       exclude_regions = {},
---     },
---   })
--- <
--- ## Outer brackets ~
---
--- `detect.brackets` is an array of Lua patterns used to find enclosing region.
--- It is done by traversing whole buffer to find the smallest region matching
--- any supplied pattern.
---
--- Default: `nil`, inferred as `{ '%b()', '%b[]', '%b{}' }`.
--- So an argument can be inside a balanced `()`, `[]`, or `{}`.
---
--- Example: `brackets = { '%b()' }` will search for arguments only inside
--- balanced `()`.
---
--- ## Separator ~
---
--- `detect.separator` is a single Lua pattern defining which strings should be
--- treated as argument separators.
---
--- Empty string in `detect.separator` will result in only surrounding brackets
--- used as separators.
---
--- Only end of pattern match will be used as split/join positions.
---
--- Default: `','`. So an argument can be separated only with comma.
---
--- Example: `separator = { '[,;]' }` will treat both `,` and `;` as separators.
---
--- ## Excluded regions ~
---
--- `detect.exclude_regions` is an array of Lua patterns for sub-regions from which
--- to exclude separators. Enables correct detection in case of nested brackets
--- and quotes.
---
--- Default: `nil`; inferred as `{ '%b()', '%b[]', '%b{}', '%b""', "%b''" }`.
--- So a separator **can not** be inside a balanced `()`, `[]`, `{}` (representing
--- nested argument regions) or `""`, `''` (representing strings).
---
--- Example: `exclude_regions = {}` will not exclude any regions. So in case of
--- `f(a, { b, c })` it will detect both commas as argument separators.
---
--- # Hooks ~
---
--- `split.hooks_pre`, `split.hooks_post`, `join.hooks_pre`, and `join.hooks_post`
--- are arrays of hook functions. If empty (default) no hook is applied.
---
--- Hooks should take and return array of positions. See |MiniSplitjoin-glossary|.
---
--- They can be used to tweak actions:
---
--- - Pre-hooks are called before action. Each is applied on the output of
---   previous one. Input of first hook are detected split/join positions.
---   Output of last one is actually used to perform split/join.
---
--- - Post-hooks are called after action. Each is applied on the output of
---   previous one. Input of first hook are split/join positions from actual
---   action plus its region's right end as last position (for easier hook code).
---   Output of last one is used as action return value.
---
--- For more specific details see |MiniSplitjoin.split()| and |MiniSplitjoin.join()|.
---
--- See |MiniSplitjoin.gen_hook| for generating common hooks with examples.
MiniSplitjoin.config = {
  -- Module mappings. Use `''` (empty string) to disable one.
  -- Created for both Normal and Visual modes.
  mappings = {
    toggle = 'gS',
    split = '',
    join = '',
  },

  -- Detection options: where split/join should be done
  detect = {
    -- Array of Lua patterns to detect region with arguments.
    -- Default: { '%b()', '%b[]', '%b{}' }
    brackets = nil,

    -- String Lua pattern defining argument separator
    separator = ',',

    -- Array of Lua patterns for sub-regions to exclude separators from.
    -- Enables correct detection in presence of nested brackets and quotes.
    -- Default: { '%b()', '%b[]', '%b{}', '%b""', "%b''" }
    exclude_regions = nil,
  },

  -- Split options
  split = {
    hooks_pre = {},
    hooks_post = {},
  },

  -- Join options
  join = {
    hooks_pre = {},
    hooks_post = {},
  },
}
--minidoc_afterlines_end

--- Toggle arguments
---
--- Overview:
--- - Detect region at input position: either by using supplied `opts.region` or
---   by finding smallest bracketed region surrounding position.
---   See |MiniSplitjoin.config.detect| for more details.
--- - If region spans single line, use |MiniSplitjoin.split()| with found region.
---   Otherwise use |MiniSplitjoin.join()|.
---
---@param opts __splitjoin_options
---
---@return any Output of chosen `split()` or `join()` action.
MiniSplitjoin.toggle = function(opts)
  if H.is_disabled() then return end

  opts = H.get_opts(opts)

  local region = opts.region or H.find_smallest_bracket_region(opts.position, opts.detect.brackets)
  if region == nil then return end

  opts.region = region
  if region.from.line == region.to.line then
    return MiniSplitjoin.split(opts)
  else
    return MiniSplitjoin.join(opts)
  end
end

--- Split arguments
---
--- Overview:
--- - Detect region: either by using supplied `opts.region` or by finding smallest
---   bracketed region surrounding input position (cursor position by default).
---   See |MiniSplitjoin.config.detect| for more details.
---
--- - Find separator positions using `separator` and `exclude_regions` from `opts`.
---   Both brackets are treated as separators.
---   See |MiniSplitjoin.config.detect| for more details.
---   Note: stop if no separator positions are found.
---
--- - Modify separator positions to represent split positions. Last split position
---   (which is inferred from right bracket) is moved one column to left so that
---   right bracket would move on new line.
---
--- - Apply all hooks from `opts.split.hooks_pre`. Each is applied on the output of
---   previous one. Input of first hook is split positions from previous step.
---   Output of last one is used as split positions in next step.
---
--- - Split and update split positions with |MiniSplitjoin.split_at()|.
---
--- - Apply all hooks from `opts.split.hooks_post`. Each is applied on the output of
---   previous one. Input of first hook is split positions from previous step plus
---   region's right end (for easier hook code).
---   Output of last one is used as function return value.
---
--- Note:
--- - By design, it doesn't detect if argument **should** be split, so application
---   on arguments spanning multiple lines can lead to undesirable result.
---
---@param opts __splitjoin_options
---
---@return any Output of last `opts.split.hooks_post` or `nil` if no split positions
---   found. Default: return value of |MiniSplitjoin.split_at()| application.
MiniSplitjoin.split = function(opts)
  if H.is_disabled() then return end

  opts = H.get_opts(opts)

  local region = opts.region or H.find_smallest_bracket_region(opts.position, opts.detect.brackets)
  if region == nil then return nil end

  local positions = H.find_split_positions(region, opts.detect.separator, opts.detect.exclude_regions)
  if #positions == 0 then return nil end

  -- Call pre-hooks
  for _, hook in ipairs(opts.split.hooks_pre) do
    positions = hook(positions)
  end

  -- Split at positions
  local split_positions = MiniSplitjoin.split_at(positions)

  -- Call post-hooks to tweak splits. Add right bracket for easier hook code.
  local last = split_positions[#split_positions]
  local last_next_line = vim.fn.getline(last.line + 1)
  local new_col = MiniSplitjoin.get_indent_part(last_next_line):len() + 1
  table.insert(split_positions, { line = last.line + 1, col = new_col })

  for _, hook in ipairs(opts.split.hooks_post) do
    split_positions = hook(split_positions)
  end

  return split_positions
end

--- Join arguments
---
--- Overview:
--- - Detect region: either by using supplied `opts.region` or by finding smallest
---   bracketed region surrounding input position (cursor position by default).
---   See |MiniSplitjoin.config.detect| for more details.
---
--- - Compute join positions to be line ends of all but last region lines.
---   Note: stop if no join positions are found.
---
--- - Apply all hooks from `opts.join.hooks_pre`. Each is applied on the output
---   of previous one. Input of first hook is join positions from previous step.
---   Output of last one is used as join positions in next step.
---
--- - Join and update join positions with |MiniSplitjoin.join_at()|.
---
--- - Apply all hooks from `opts.join.hooks_post`. Each is applied on the output
---   of previous one. Input of first hook is join positions from previous step
---   plus region's right end for easier hook code.
---   Output of last one is used as function return value.
---
---@param opts __splitjoin_options
---
---@return any Output of last `opts.split.hooks_post` or `nil` of no join positions
---   found. Default: return value of |MiniSplitjoin.join_at()| application.
MiniSplitjoin.join = function(opts)
  if H.is_disabled() then return end

  opts = H.get_opts(opts)

  local region = opts.region or H.find_smallest_bracket_region(opts.position, opts.detect.brackets)
  if region == nil then return nil end

  local positions = H.find_join_positions(region)
  if #positions == 0 then return nil end

  -- Call pre-hooks
  for _, hook in ipairs(opts.join.hooks_pre) do
    positions = hook(positions)
  end

  -- Join at positions
  local join_positions = MiniSplitjoin.join_at(positions)

  -- Call post-hooks to tweak joins. Add right bracket for easier hook code.
  local last = join_positions[#join_positions]
  table.insert(join_positions, { line = last.line, col = last.col + 1 })

  for _, hook in ipairs(opts.join.hooks_post) do
    join_positions = hook(join_positions)
  end

  return join_positions
end

--- Generate common hooks
---
--- This is a table with function elements. Call to actually get hook.
---
--- All generated post-hooks return updated versions of their input reflecting
--- changes done inside hook.
---
--- Example for `lua` filetype (place it in 'lua.lua' filetype plugin, |ftplugin|): >lua
---
---   local gen_hook = MiniSplitjoin.gen_hook
---   local curly = { brackets = { '%b{}' } }
---
---   -- Add trailing comma when splitting inside curly brackets
---   local add_comma_curly = gen_hook.add_trailing_separator(curly)
---
---   -- Delete trailing comma when joining inside curly brackets
---   local del_comma_curly = gen_hook.del_trailing_separator(curly)
---
---   -- Pad curly brackets with single space after join
---   local pad_curly = gen_hook.pad_brackets(curly)
---
---   -- Create buffer-local config
---   vim.b.minisplitjoin_config = {
---     split = { hooks_post = { add_comma_curly } },
---     join  = { hooks_post = { del_comma_curly, pad_curly } },
---   }
--- <
MiniSplitjoin.gen_hook = {}

--- Generate hook to pad brackets
---
--- This is a join post-hook. Use in `join.hooks_post` of |MiniSplitjoin.config|.
---
---@param opts table|nil Options. Possible fields:
---    - <pad> `(string)` - pad to add after first and before last join positions.
---      Default: `' '` (single space).
---    __splitjoin_hook_brackets
---
---@return function A hook which adds inner pad to first and last join positions and
---   returns updated input join positions.
MiniSplitjoin.gen_hook.pad_brackets = function(opts)
  opts = opts or {}
  local pad = opts.pad or ' '
  local brackets = opts.brackets or H.get_opts(opts).detect.brackets
  local n_pad = pad:len()

  return function(join_positions)
    -- Act only on actual join
    local n_pos = #join_positions
    if n_pos == 0 or pad == '' then return join_positions end

    -- Act only if brackets are matched. First join position should be exactly
    -- on left bracket, last - just before right bracket.
    local first, last = join_positions[1], join_positions[n_pos]
    local brackets_matched = H.is_positions_inside_brackets(first, last, brackets)
    if not brackets_matched then return join_positions end

    -- Pad only in case of non-trivial join
    if first.line == last.line and (last.col - first.col) <= 1 then return join_positions end

    -- Add pad after left and before right edges
    H.set_text(first.line - 1, last.col - 1, first.line - 1, last.col - 1, { pad })
    H.set_text(first.line - 1, first.col, first.line - 1, first.col, { pad })

    -- Update `join_positions` to reflect text change
    -- - Account for left pad
    for i = 2, n_pos do
      join_positions[i].col = join_positions[i].col + n_pad
    end
    -- - Account for right pad
    join_positions[n_pos].col = join_positions[n_pos].col + n_pad

    return join_positions
  end
end

--- Generate hook to add trailing separator
---
--- This is a split post-hook. Use in `split.hooks_post` of |MiniSplitjoin.config|.
---
---@param opts table|nil Options. Possible fields:
---    - <sep> `(string)` - separator to add before last split position.
---      Default: `','`.
---    __splitjoin_hook_brackets
---
---@return function A hook which adds separator before last split position and
---   returns updated input split positions.
MiniSplitjoin.gen_hook.add_trailing_separator = function(opts)
  opts = opts or {}
  local sep = opts.sep or ','
  local brackets = opts.brackets or H.get_opts(opts).detect.brackets

  return function(split_positions)
    -- Add only in case there is at least one argument
    local n_pos = #split_positions
    if n_pos < 3 then return split_positions end

    -- Act only if brackets are matched
    local first, last = split_positions[1], split_positions[n_pos]
    local brackets_matched = H.is_positions_inside_brackets(first, last, brackets)
    if not brackets_matched then return split_positions end

    -- Act only if there is no trailing separator already
    local target_line = vim.fn.getline(last.line - 1)
    local target_col = target_line:find(vim.pesc(sep) .. '$')
    if target_col ~= nil then return split_positions end

    -- Add trailing separator
    local col = target_line:len()
    H.set_text(last.line - 2, col, last.line - 2, col, { sep })

    -- Don't update `split_positions`, as appending to line has no effect
    return split_positions
  end
end

--- Generate hook to delete trailing separator
---
--- This is a join post-hook. Use in `join.hooks_post` of |MiniSplitjoin.config|.
---
---@param opts table|nil Options. Possible fields:
---    - <sep> `(string)` - separator to remove before last join position.
---      Default: `','`.
---    __splitjoin_hook_brackets
---
---@return function A hook which adds separator before last split position and
---   returns updated input split positions.
MiniSplitjoin.gen_hook.del_trailing_separator = function(opts)
  opts = opts or {}
  local sep = opts.sep or ','
  local brackets = opts.brackets or H.get_opts(opts).detect.brackets
  local n_sep = sep:len()

  return function(join_positions)
    -- Act only on actual join
    local n_pos = #join_positions
    if n_pos == 0 then return join_positions end

    -- Act only if brackets are matched
    local first, last = join_positions[1], join_positions[n_pos]
    local brackets_matched = H.is_positions_inside_brackets(first, last, brackets)
    if not brackets_matched then return join_positions end

    -- Act only if there is matched trailing separator
    local target_line = vim.fn.getline(last.line):sub(1, last.col - 1)
    local target_col = target_line:find(vim.pesc(sep) .. '%s*$')
    if target_col == nil then return join_positions end

    -- Remove trailing separator
    H.set_text(last.line - 1, target_col - 1, last.line - 1, target_col - 1 + n_sep, {})

    -- Update `join_positions` to reflect text change. Update last as it moved.
    -- Do not update second to last because it didn't affect what was tracked.
    join_positions[n_pos] = { line = last.line, col = last.col - n_sep }

    return join_positions
  end
end

--- Split at positions
---
--- Overview:
--- - For each position move all characters after it to next line and make it have
---   same indent as current one (see |MiniSplitjoin.get_indent_part()|).
---   Also remove trailing whitespace at position line.
---
--- - Increase indent of inner lines by a single pad: tab in case of |noexpandtab|
---   or |shiftwidth()| number of spaces otherwise.
---
--- Notes:
--- - Cursor is adjusted to follow text updates.
--- - Use output of this function to keep track of input positions.
---
---@param positions table Array of positions at which to perform split.
---   See |MiniSplitjoin-glossary| for their structure. Note: they don't have
---   to be ordered, but first and last ones will be used to infer lines for
---   which indent will be increased.
---
---@return table Array of new positions to where input `positions` were moved.
MiniSplitjoin.split_at = function(positions)
  local n_pos = #positions
  if n_pos == 0 then return {} end

  -- Cache values that might change
  local cursor_extmark = H.put_extmark_at_positions({ H.get_cursor_pos() })[1]
  local input_extmarks = H.put_extmark_at_positions(positions)

  -- Split at extmark positions
  for i = 1, n_pos do
    H.split_at_extmark(input_extmarks[i])
  end

  -- Increase indent of inner lines
  local first_new_pos = H.get_extmark_pos(input_extmarks[1])
  local last_new_pos = H.get_extmark_pos(input_extmarks[n_pos])
  H.increase_indent(first_new_pos.line + 1, last_new_pos.line)

  -- Put cursor back on tracked position
  H.put_cursor_at_extmark(cursor_extmark)

  -- Reconstruct input positions
  local res = vim.tbl_map(H.get_extmark_pos, input_extmarks)
  vim.api.nvim_buf_clear_namespace(0, H.ns_id, 0, -1)
  return res
end

--- Join at positions
---
--- Overview:
--- - For each position join its line with the next line. Joining is done by
---   replacing trailing whitespace of the line and indent of its next line
---   (see |MiniSplitjoin.get_indent_part()|) with a pad string (single space except
---   empty string for first and last positions). To adjust this, use hooks
---   (for example, see |MiniSplitjoin.gen_hook.pad_brackets()|).
---
--- Notes:
--- - Cursor is adjusted to follow text updates.
--- - Use output of this function to keep track of input positions.
---
---@param positions table Array of positions at which to perform join.
---   See |MiniSplitjoin-glossary| for their structure. Note: they don't have
---   to be ordered, but first and last ones will have different pad string.
---
---@return table Array of new positions to where input `positions` were moved.
MiniSplitjoin.join_at = function(positions)
  local n_pos = #positions
  if n_pos == 0 then return {} end

  -- Cache values that might change
  local cursor_extmark = H.put_extmark_at_positions({ H.get_cursor_pos() })[1]
  local input_extmarks = H.put_extmark_at_positions(positions)

  -- Join at positions which are changing following extmarks
  for i = 1, n_pos do
    local cur_pad_string = (i == 1 or i == n_pos) and '' or ' '
    H.join_at_extmark(input_extmarks[i], cur_pad_string)
  end

  -- Put cursor back on tracked position
  H.put_cursor_at_extmark(cursor_extmark)

  -- Reconstruct input positions
  local res = vim.tbl_map(H.get_extmark_pos, input_extmarks)
  vim.api.nvim_buf_clear_namespace(0, H.ns_id, 0, -1)
  return res
end

--- Get previous visual region
---
--- Get previous visual selection using |`<| and |`>| marks in the format of
--- region (see |MiniSplitjoin-glossary|). Used in Visual mode mappings.
---
--- Note:
--- - Both marks are included in region, so for better
--- - In linewise Visual mode
---
---@return table A region. See |MiniSplitjoin-glossary| for exact structure.
MiniSplitjoin.get_visual_region = function()
  local from_pos, to_pos = vim.fn.getpos("'<"), vim.fn.getpos("'>")
  local from, to = { line = from_pos[2], col = from_pos[3] }, { line = to_pos[2], col = to_pos[3] }
  -- Tweak for linewise Visual selection
  if vim.fn.visualmode() == 'V' then
    from.col, to.col = 1, vim.fn.col({ to.line, '$' }) - 1
  end

  return { from = from, to = to }
end

--- Get string's indent part
---
---@param line string String for which to compute indent.
---@param respect_comments boolean|nil Whether to respect comments as indent part.
---   Default: `true`.
---
---@return string Part of input representing line's indent. Can be empty string.
---   Use `string.len()` to compute indent in bytes.
MiniSplitjoin.get_indent_part = function(line, respect_comments)
  if respect_comments == nil then respect_comments = true end
  if not respect_comments then return line:match('^%s*') end

  -- Make it respect various comment leaders
  local comment_indent = H.get_comment_indent(line, H.get_comment_leaders())
  if comment_indent ~= '' then return comment_indent end

  return line:match('^%s*')
end

--- Operator for Normal mode mappings
---
--- Main function to be used in expression mappings. No need to use it
--- directly, everything is setup in |MiniSplitjoin.setup()|.
---
---@param task string Name of task.
MiniSplitjoin.operator = function(task)
  local is_init_call = task == 'toggle' or task == 'split' or task == 'join'
  if not is_init_call then
    MiniSplitjoin[H.cache.operator_task]()
    return ''
  end

  if H.is_disabled() then
    -- Using `<Esc>` prevents moving cursor caused by current implementation
    -- detail of adding `' '` inside expression mapping
    return [[\<Esc>]]
  end

  H.cache.operator_task = task
  vim.o.operatorfunc = 'v:lua.MiniSplitjoin.operator'
  return 'g@'
end

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniSplitjoin.config)

H.ns_id = vim.api.nvim_create_namespace('MiniSplitjoin')

H.cache = { operator_task = nil }

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  H.check_type('mappings', config.mappings, 'table')
  H.check_type('mappings.toggle', config.mappings.toggle, 'string', true)
  H.check_type('mappings.split', config.mappings.split, 'string')
  H.check_type('mappings.join', config.mappings.join, 'string', true)

  H.check_type('detect', config.detect, 'table')
  H.check_type('detect.brackets', config.detect.brackets, 'table', true)
  H.check_type('detect.separator', config.detect.separator, 'string')
  H.check_type('detect.exclude_regions', config.detect.exclude_regions, 'table', true)

  H.check_type('split', config.split, 'table')
  H.check_type('split.hooks_pre', config.split.hooks_pre, 'table')
  H.check_type('split.hooks_post', config.split.hooks_post, 'table')

  H.check_type('join', config.join, 'table')
  H.check_type('join.hooks_pre', config.join.hooks_pre, 'table')
  H.check_type('join.hooks_post', config.join.hooks_post, 'table')

  return config
end

--stylua: ignore
H.apply_config = function(config)
  MiniSplitjoin.config = config

  -- Make mappings
  local maps = config.mappings

  H.map('n', maps.toggle, 'v:lua.MiniSplitjoin.operator("toggle") . " "', { expr = true, desc = 'Toggle arguments' })
  H.map('n', maps.split,  'v:lua.MiniSplitjoin.operator("split") . " "',  { expr = true, desc = 'Split arguments' })
  H.map('n', maps.join,   'v:lua.MiniSplitjoin.operator("join") . " "',   { expr = true, desc = 'Join arguments' })

  H.map('x', maps.toggle, ':<C-u>lua MiniSplitjoin.toggle({ region = MiniSplitjoin.get_visual_region() })<CR>', { desc = 'Toggle arguments' })
  H.map('x', maps.split,  ':<C-u>lua MiniSplitjoin.split({ region = MiniSplitjoin.get_visual_region() })<CR>',  { desc = 'Split arguments' })
  H.map('x', maps.join,   ':<C-u>lua MiniSplitjoin.join({ region = MiniSplitjoin.get_visual_region() })<CR>',   { desc = 'Join arguments' })
end

H.is_disabled = function() return vim.g.minisplitjoin_disable == true or vim.b.minisplitjoin_disable == true end

H.get_config = function(config)
  return vim.tbl_deep_extend('force', MiniSplitjoin.config, vim.b.minisplitjoin_config or {}, config or {})
end

H.get_opts = function(opts)
  opts = opts or {}

  -- Infer detect options. Can't use usual `vim.tbl_deep_extend()` because it
  -- doesn't work properly on arrays
  local default_detect = {
    brackets = { '%b()', '%b[]', '%b{}' },
    separator = ',',
    exclude_regions = { '%b()', '%b[]', '%b{}', '%b""', "%b''" },
  }
  local config = H.get_config()

  return {
    position = opts.position or H.get_cursor_pos(),
    region = opts.region,
    -- Extend `detect` not deeply to avoid unwanted values from longer defaults
    detect = vim.tbl_extend('force', default_detect, config.detect, opts.detect or {}),
    split = vim.tbl_deep_extend('force', config.split, opts.split or {}),
    join = vim.tbl_deep_extend('force', config.join, opts.join or {}),
  }
end

-- Split ----------------------------------------------------------------------
H.split_at_extmark = function(extmark_id)
  local pos = H.get_extmark_pos(extmark_id)

  -- Split
  H.set_text(pos.line - 1, pos.col, pos.line - 1, pos.col, { '', '' })

  -- Remove trailing whitespace on split line
  local split_line = vim.fn.getline(pos.line)
  local start_of_trailspace = split_line:find('%s*$')
  H.set_text(pos.line - 1, start_of_trailspace - 1, pos.line - 1, split_line:len(), {})

  -- Adjust indent on new line
  local cur_indent = MiniSplitjoin.get_indent_part(vim.fn.getline(pos.line + 1))
  local new_indent = MiniSplitjoin.get_indent_part(split_line)
  H.set_text(pos.line, 0, pos.line, cur_indent:len(), { new_indent })
end

H.find_split_positions = function(region, separator, exclude_regions)
  local sep_positions = H.find_separator_positions(region, separator, exclude_regions)
  local n_pos = #sep_positions

  sep_positions[n_pos].col = sep_positions[n_pos].col - 1
  return sep_positions
end

-- Join -----------------------------------------------------------------------
H.join_at_extmark = function(extmark_id, pad)
  local line_num = H.get_extmark_pos(extmark_id).line
  if vim.api.nvim_buf_line_count(0) <= line_num then return end

  -- Join by replacing trailing whitespace of current line and indent of next
  -- one with `pad`
  local lines = vim.api.nvim_buf_get_lines(0, line_num - 1, line_num + 1, true)
  local above_start_col = lines[1]:len() - lines[1]:match('%s*$'):len()
  local below_end_col = MiniSplitjoin.get_indent_part(lines[2]):len()

  H.set_text(line_num - 1, above_start_col, line_num, below_end_col, { pad })
end

H.find_join_positions = function(region, separator, exclude_regions)
  local lines = vim.api.nvim_buf_get_lines(0, region.from.line - 1, region.to.line, true)

  -- Join whole region into single line
  local res = {}
  local init_line = region.from.line - 1
  for i = 1, #lines - 1 do
    table.insert(res, { line = init_line + i, col = lines[i]:len() })
  end
  return res
end

-- Detect ---------------------------------------------------------------------
H.find_smallest_bracket_region = function(position, brackets)
  local neigh = H.get_neighborhood()
  local cur_offset = neigh.pos_to_offset(position)

  local best_span = H.find_smallest_covering(neigh['1d'], cur_offset, brackets)
  if best_span == nil then return nil end

  return neigh.span_to_region(best_span)
end

H.find_smallest_covering = function(line, ref_offset, patterns)
  local res, min_width = nil, math.huge
  for _, pattern in ipairs(patterns) do
    local cur_init = 0
    local left, right = string.find(line, pattern, cur_init)
    while left do
      if left <= ref_offset and ref_offset <= right and (right - left) < min_width then
        res, min_width = { from = left, to = right }, right - left
      end

      cur_init = left + 1
      left, right = string.find(line, pattern, cur_init)
    end
  end

  return res
end

H.find_separator_positions = function(region, separator, exclude_regions)
  if separator == '' then return { region.from, region.to } end

  local neigh = H.get_neighborhood()
  local region_span = neigh.region_to_span(region)
  local region_s = neigh['1d']:sub(region_span.from, region_span.to)

  -- Match separator endings
  local seps = {}
  region_s:gsub(separator .. '()', function(r) table.insert(seps, r - 1) end)

  -- Remove separators that are in excluded regions.
  local inner_string, forbidden = region_s:sub(2, -2), {}
  local add_to_forbidden = function(l, r) table.insert(forbidden, { from = l + 1, to = r }) end

  for _, pat in ipairs(exclude_regions) do
    inner_string:gsub('()' .. pat .. '()', add_to_forbidden)
  end

  -- - Also exclude trailing separator
  inner_string:gsub('()' .. separator .. '%s*()$', add_to_forbidden)

  local sub_offsets = vim.tbl_filter(function(x) return not H.is_offset_inside_spans(x, forbidden) end, seps)

  -- Treat enclosing brackets as separators
  if region_s:len() > 2 then
    -- Use only last bracket in case of empty brackets
    table.insert(sub_offsets, 1, 1)
  end
  table.insert(sub_offsets, region_s:len())

  -- Convert offsets to positions
  local start_offset = region_span.from
  return vim.tbl_map(function(sub_off) return neigh.offset_to_pos(start_offset + sub_off - 1) end, sub_offsets)
end

H.is_offset_inside_spans = function(ref_point, spans)
  for _, span in ipairs(spans) do
    if span.from <= ref_point and ref_point <= span.to then return true end
  end
  return false
end

H.is_positions_inside_brackets = function(from_pos, to_pos, brackets)
  local text_lines = vim.api.nvim_buf_get_text(0, from_pos.line - 1, from_pos.col - 1, to_pos.line - 1, to_pos.col, {})
  local text = table.concat(text_lines, '\n')

  for _, b in ipairs(brackets) do
    if text:find('^' .. b .. '$') ~= nil then return true end
  end
  return false
end

H.is_char_at_position = function(position, char)
  local present_char = vim.fn.getline(position.line):sub(position.col, position.col)
  return present_char == char
end

-- Simplified version of "neighborhood" from 'mini.ai':
-- - Use whol buffer.
-- - No empty regions or spans.
--
-- NOTEs:
-- - `region = { from = { line = a, col = b }, to = { line = c, col = d } }`.
--   End-inclusive charwise selection. All `a`, `b`, `c`, `d` are 1-indexed.
-- - `offset` is the number between 1 to `neigh1d:len()`.
H.get_neighborhood = function()
  local neigh2d = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  -- Append 'newline' character to distinguish between lines in 1d case
  -- (crucial for handling empty lines)
  for k, v in pairs(neigh2d) do
    neigh2d[k] = v .. '\n'
  end
  local neigh1d = table.concat(neigh2d, '')
  local n_lines = #neigh2d

  -- Compute offsets for just before line starts
  local line_offsets = {}
  local cur_offset = 0
  for i = 1, n_lines do
    line_offsets[i] = cur_offset
    cur_offset = cur_offset + neigh2d[i]:len()
  end

  -- Convert 2d buffer position to 1d offset
  local pos_to_offset = function(pos) return line_offsets[pos.line] + pos.col end

  -- Convert 1d offset to 2d buffer position
  local offset_to_pos = function(offset)
    for i = 1, n_lines - 1 do
      if line_offsets[i] < offset and offset <= line_offsets[i + 1] then
        return { line = i, col = offset - line_offsets[i] }
      end
    end

    return { line = n_lines, col = offset - line_offsets[n_lines] }
  end

  -- Convert 2d region to 1d span
  local region_to_span = function(region) return { from = pos_to_offset(region.from), to = pos_to_offset(region.to) } end

  -- Convert 1d span to 2d region
  local span_to_region = function(span) return { from = offset_to_pos(span.from), to = offset_to_pos(span.to) } end

  return {
    ['1d'] = neigh1d,
    ['2d'] = neigh2d,
    pos_to_offset = pos_to_offset,
    offset_to_pos = offset_to_pos,
    region_to_span = region_to_span,
    span_to_region = span_to_region,
  }
end

-- Extmarks -------------------------------------------------------------------
H.put_extmark_at_positions = function(positions)
  return vim.tbl_map(
    function(pos) return vim.api.nvim_buf_set_extmark(0, H.ns_id, pos.line - 1, pos.col - 1, {}) end,
    positions
  )
end

H.get_extmark_pos = function(extmark_id)
  local res = vim.api.nvim_buf_get_extmark_by_id(0, H.ns_id, extmark_id, {})
  return { line = res[1] + 1, col = res[2] + 1 }
end

H.get_cursor_pos = function()
  local cur_pos = vim.api.nvim_win_get_cursor(0)
  return { line = cur_pos[1], col = cur_pos[2] + 1 }
end

H.put_cursor_at_extmark = function(id)
  local new_pos = vim.api.nvim_buf_get_extmark_by_id(0, H.ns_id, id, {})
  vim.api.nvim_win_set_cursor(0, { new_pos[1] + 1, new_pos[2] })
  vim.api.nvim_buf_del_extmark(0, H.ns_id, id)
end

-- Indent ---------------------------------------------------------------------
H.increase_indent = function(from_line, to_line)
  local lines = vim.api.nvim_buf_get_lines(0, from_line - 1, to_line, true)

  -- Respect comment leaders only if all lines are commented
  local comment_leaders = H.get_comment_leaders()
  local respect_comments = H.is_comment_block(lines, comment_leaders)

  -- Increase indent of all lines (end-inclusive)
  local pad = vim.bo.expandtab and string.rep(' ', vim.fn.shiftwidth()) or '\t'
  for i, l in ipairs(lines) do
    local n_indent = MiniSplitjoin.get_indent_part(l, respect_comments):len()

    -- Don't increase indent of blank lines (possibly respecting comments)
    local cur_by_string = l:len() == n_indent and '' or pad

    local line_num = from_line + i - 1
    H.set_text(line_num - 1, n_indent, line_num - 1, n_indent, { cur_by_string })
  end
end

H.get_comment_indent = function(line, comment_leaders)
  local res = ''

  for _, leader in ipairs(comment_leaders) do
    local cur_match = line:match('^%s*' .. vim.pesc(leader) .. '%s*')
    -- Use biggest match in case of several matches. Allows respecting "nested"
    -- comment leaders like "---" and "--".
    if type(cur_match) == 'string' and res:len() < cur_match:len() then res = cur_match end
  end

  return res
end

-- Comments -------------------------------------------------------------------
H.get_comment_leaders = function()
  local res = {}

  -- From 'commentstring'
  local main_leader = vim.split(vim.bo.commentstring, '%%s')[1]
  -- - Ensure there is no whitespace before or after
  table.insert(res, vim.trim(main_leader))

  -- From 'comments'
  for _, comment_part in ipairs(vim.opt_local.comments:get()) do
    local prefix, suffix = comment_part:match('^(.*):(.*)$')

    -- Control whitespace around suffix
    suffix = vim.trim(suffix)

    if prefix:find('b') then
      -- Respect `b` flag (for blank) requiring space, tab or EOL after it
      table.insert(res, suffix .. ' ')
      table.insert(res, suffix .. '\t')
    elseif prefix:find('f') == nil then
      -- Add otherwise ignoring `f` flag (only first line should have it)
      table.insert(res, suffix)
    end
  end

  return res
end

H.is_comment_block = function(lines, comment_leaders)
  for _, l in ipairs(lines) do
    if not H.is_commented(l, comment_leaders) then return false end
  end
  return true
end

H.is_commented = function(line, comment_leaders)
  for _, leader in ipairs(comment_leaders) do
    if line:find('^%s*' .. vim.pesc(leader) .. '%s*') ~= nil then return true end
  end
  return false
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.splitjoin) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.map = function(mode, lhs, rhs, opts)
  if lhs == '' then return end
  opts = vim.tbl_deep_extend('force', { silent = true }, opts or {})
  vim.keymap.set(mode, lhs, rhs, opts)
end

H.set_text = function(start_row, start_col, end_row, end_col, replacement)
  local ok = pcall(vim.api.nvim_buf_set_text, 0, start_row, start_col, end_row, end_col, replacement)
  if not ok or #replacement == 0 then return end

  -- Fix cursor position if it was exactly on start position.
  -- See https://github.com/neovim/neovim/issues/22526.
  local cursor = vim.api.nvim_win_get_cursor(0)
  if (start_row + 1) == cursor[1] and start_col == cursor[2] then
    vim.api.nvim_win_set_cursor(0, { cursor[1], cursor[2] + replacement[1]:len() })
  end
end

return MiniSplitjoin
