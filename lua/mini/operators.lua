--- *mini.operators* Text edit operators
---
--- MIT License Copyright (c) 2023 Evgeni Chasnovski

--- Features:
--- - Operators:
---     - Evaluate text and replace with output.
---     - Exchange text regions.
---     - Multiply (duplicate) text.
---     - Replace text with register.
---     - Sort text.
---
--- - Automated configurable mappings to operate on textobject, line, selection.
---   Can be disabled in favor of more control with |MiniOperators.make_mappings()|.
---
--- - All operators support |[count]| and dot-repeat.
---
--- See |MiniOperators-overview| and |MiniOperators.config| for more details.
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.operators').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `MiniOperators`
--- which you can use for scripting or manually (with `:lua MiniOperators.*`).
---
--- See |MiniOperators.config| for available config settings.
---
--- You can override runtime config settings (but not `config.mappings`) locally
--- to buffer inside `vim.b.minioperators_config` which should have same structure
--- as `MiniOperators.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- # Comparisons ~
---
--- - [gbprod/substitute.nvim](https://github.com/gbprod/substitute.nvim):
---     - Has "replace" and "exchange" variants, but not others from this module.
---     - Has "replace/substitute" over range functionality, while this module
---       does not by design (it is similar to |:s| functionality while not
---       offering significantly lower mental complexity).
---     - "Replace" highlights pasted text, while in this module it doesn't.
---     - "Exchange" doesn't work across buffers, while in this module it does.
---
--- - [svermeulen/vim-subversive](https://github.com/svermeulen/vim-subversive):
---     - Main inspiration for "replace" functionality, so they are mostly similar
---       for this operator.
---     - Has "replace/substitute" over range functionality, while this module
---       does not by design.
---
--- - [tommcdo/vim-exchange](https://github.com/tommcdo/vim-exchange):
---     - Main inspiration for "exchange" functionality, so they are mostly
---       similar for this operator.
---     - Doesn't work across buffers, while this module does.
---
--- - [christoomey/vim-sort-motion](https://github.com/christoomey/vim-sort-motion):
---     - Uses |:sort| for linewise sorting, while this module uses consistent
---       sorting algorithm (by default, see |MiniOperators.default_sort_func()|).
---     - Sorting algorithm can't be customized, while this module allows this
---       (see `sort.func` in |MiniOperators.config|).
---     - For charwise region uses only commas as separators, while this module
---       can also separate by semicolon or whitespace (by default,
---       see |MiniOperators.default_sort_func()|).
---
--- # Highlight groups ~
---
--- - `MiniOperatorsExchangeFrom` - first region to exchange.
---
--- To change any highlight group, set it directly with |nvim_set_hl()|.
---
--- # Disabling ~
---
--- To disable main functionality, set `vim.g.minioperators_disable` (globally) or
--- `vim.b.minioperators_disable` (for a buffer) to `true`. Considering high number
--- of different scenarios and customization intentions, writing exact rules
--- for disabling module's functionality is left to user. See
--- |mini.nvim-disabling-recipes| for common recipes.
---@tag MiniOperators

--- Operator defines an action that will be performed on a textobject, motion,
--- or visual selection (similar to |d|, |c|, etc.). When makes sense, it can also
--- respect supplied register (like "replace" operator).
---
--- This module implements each operator in a separate dedicated function
--- (like |MiniOperators.replace()| for "replace" operator). Each such function
--- takes `mode` as argument and acts depending on it:
---
--- - If `mode` is `nil` (or not explicitly supplied), it sets |'operatorfunc'|
---   to this dedicated function and returns `g@` assuming being called from
---   expression mapping. See |:map-operator| and |:map-expression| for more details.
---
--- - If `mode` is "char", "line", or "block", it acts as `operatorfunc` and performs
---   action for region between |`[| and |`]| marks.
---
--- - If `mode` is "visual", it performs action for region between |`<| and |`>| marks.
---
--- For more details about specific operator, see help for its function:
---
--- - Evaluate: |MiniOperators.evaluate()|
--- - Exchange: |MiniOperators.exchange()|
--- - Multiply: |MiniOperators.multiply()|
--- - Replace:  |MiniOperators.replace()|
--- - Sort:     |MiniOperators.sort()|
---
--- # Mappings ~
--- *MiniOperators-mappings*
---
--- All operators are automatically mapped during |MiniOperators.setup()| execution.
--- Mappings keys are deduced from `prefix` field of corresponding `config` entry.
--- All built-in conflicting mappings are removed (like |gra|, |grn| in Neovim>=0.11).
--- Both |gx| and |v_gx| are remapped to `gX` (if that is not already taken).
---
--- For each operator the following mappings are created:
---
--- - In Normal mode to operate on textobject. Uses `prefix` directly.
--- - In Normal mode to operate on line. Appends to `prefix` the last character.
---   This aligns with |operator-doubled| and established patterns for operators
---   with more than two characters, like |guu|, |gUU|, etc.
--- - In Visual mode to operate on visual selection. Uses `prefix` directly.
---
--- Example of default mappings for "replace":
--- - `gr` in Normal mode for operating on textobject.
---   Example of usage: `griw` replaces "inner word" with default register.
--- - `grr` in Normal mode for operating on line.
---   Example of usage: `grr` replaces current line.
--- - `gr` in Visual mode for operating on visual selection.
---   Example of usage: `viw` selects "inner word" and `gr` replaces it.
---
--- There are two suggested ways to customize mappings:
---
--- - Change `prefix` in |MiniOperators.setup()| call. For example, doing >lua
---
---     require('mini.operators').setup({ replace = { prefix = 'cr' } })
--- <
---   will make mappings for `cr` / `crr` / `cr` instead of `gr` / `grr` / `gr`.
---
--- - Disable automated mapping creation by supplying empty string as prefix and
---   use |MiniOperators.make_mappings()| directly. For example: >lua
---
---     -- Disable automated creation of "replace"
---     local operators = require('mini.operators')
---     operators.setup({ replace = { prefix = '' } })
---
---     -- Make custom mappings
---     operators.make_mappings(
---       'replace',
---       { textobject = 'cr', line = 'crr', selection = 'cr' }
---     )
--- <
---@tag MiniOperators-overview

---@alias __operators_mode string|nil One of `nil`, `'char'`, `'line'`, `'block'`, `'visual'`.
---@alias __operators_content table Table with the following fields:
---   - <lines> `(table)` - array with content lines.
---   - <submode> `(string)` - region submode. One of `'v'`, `'V'`, `'<C-v>'` (escaped).

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local
---@diagnostic disable:cast-local-type

-- Module definition ==========================================================
local MiniOperators = {}
local H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniOperators.config|.
---
---@usage >lua
---   require('mini.operators').setup() -- use default config
---   -- OR
---   require('mini.operators').setup({}) -- replace {} with your config table
--- <
MiniOperators.setup = function(config)
  -- Export module
  _G.MiniOperators = MiniOperators

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
---@text # Evaluate ~
---
--- `evaluate.prefix` is a string used to automatically infer operator mappings keys
--- during |MiniOperators.setup()|. See |MiniOperators-mappings|.
---
--- `evaluate.func` is a function used to actually evaluate text region.
--- If `nil` (default), |MiniOperators.default_evaluate_func()| is used.
---
--- This function will take content table representing selected text as input
--- and should return array of lines as output (each item per line).
--- Content table has fields `lines`, array of region lines, and `submode`,
--- one of `v`, `V`, `\22` (escaped `<C-v>`) for charwise, linewise, and blockwise.
---
--- To customize evaluation per language, set `evaluate.func` in buffer-local
--- config (`vim.b.minioperators_config`; see |mini.nvim-buffer-local-config|).
---
--- # Exchange ~
---
--- `exchange.prefix` is a string used to automatically infer operator mappings keys
--- during |MiniOperators.setup()|. See |MiniOperators-mappings|.
---
--- Note: default value "gx" overrides |gx| / |v_gx|. Instead they are remapped
--- to `gX` (if that is not already taken). To keep using `gx` with built-in
--- feature (open URL at cursor) choose different `config.prefix`.
---
--- `exchange.reindent_linewise` is a boolean indicating whether newly put linewise
--- text should preserve indent of replaced text. In other words, if `false`,
--- regions are exchanged preserving their indents; if `true` - without them.
---
--- # Multiply ~
---
--- `multiply.prefix` is a string used to automatically infer operator mappings keys
--- during |MiniOperators.setup()|. See |MiniOperators-mappings|.
---
--- `multiply.func` is a function used to optionally update multiplied text.
--- If `nil` (default), text used as is.
---
--- Takes content table as input (see "Evaluate" section) and should return
--- array of lines as output.
---
--- # Replace ~
---
--- `replace.prefix` is a string used to automatically infer operator mappings keys
--- during |MiniOperators.setup()|. See |MiniOperators-mappings|.
---
--- `replace.reindent_linewise` is a boolean indicating whether newly put linewise
--- text should preserve indent of replaced text.
---
--- # Sort ~
---
--- `sort.prefix` is a string used to automatically infer operator mappings keys
--- during |MiniOperators.setup()|. See |MiniOperators-mappings|.
---
--- `sort.func` is a function used to actually sort text region.
--- If `nil` (default), |MiniOperators.default_sort_func()| is used.
---
--- Takes content table as input (see "Evaluate" section) and should return
--- array of lines as output.
---
--- Example of `sort.func` which asks user for custom delimiter for charwise region: >lua
---
---   local sort_func = function(content)
---     local opts = {}
---     if content.submode == 'v' then
---       -- Ask for delimiter to be treated as is (not as Lua pattern)
---       local delimiter = vim.fn.input('Sort delimiter: ')
---       -- Treat surrounding whitespace as part of split
---       opts.split_patterns = { '%s*' .. vim.pesc(delimiter) .. '%s*' }
---     end
---     return MiniOperators.default_sort_func(content, opts)
---   end
---
---   require('mini.operators').setup({ sort = { func = sort_func } })
--- <
MiniOperators.config = {
  -- Each entry configures one operator.
  -- `prefix` defines keys mapped during `setup()`: in Normal mode
  -- to operate on textobject and line, in Visual - on selection.

  -- Evaluate text and replace with output
  evaluate = {
    prefix = 'g=',

    -- Function which does the evaluation
    func = nil,
  },

  -- Exchange text regions
  exchange = {
    -- NOTE: Default `gx` is remapped to `gX`
    prefix = 'gx',

    -- Whether to reindent new text to match previous indent
    reindent_linewise = true,
  },

  -- Multiply (duplicate) text
  multiply = {
    prefix = 'gm',

    -- Function which can modify text before multiplying
    func = nil,
  },

  -- Replace text with register
  replace = {
    -- NOTE: Default `gr*` LSP mappings are removed
    prefix = 'gr',

    -- Whether to reindent new text to match previous indent
    reindent_linewise = true,
  },

  -- Sort text
  sort = {
    prefix = 'gs',

    -- Function which does the sort
    func = nil,
  }
}
--minidoc_afterlines_end

--- Evaluate text and replace with output
---
--- It replaces the region with the output of `config.evaluate.func`.
--- By default it is |MiniOperators.default_evaluate_func()| which evaluates
--- text as Lua code depending on the region submode.
---
---@param mode __operators_mode
MiniOperators.evaluate = function(mode)
  if H.is_disabled() or not vim.bo.modifiable then return '' end

  -- If used without arguments inside expression mapping, set it as
  -- 'operatorfunc' and call it again as a result of expression mapping.
  if mode == nil then
    vim.o.operatorfunc = 'v:lua.MiniOperators.evaluate'
    return 'g@'
  end

  local evaluate_func = H.get_config().evaluate.func or MiniOperators.default_evaluate_func
  local data = H.get_region_data(mode)
  if data == nil then return end
  data.reindent_linewise = true
  H.apply_content_func(evaluate_func, data)
end

--- Exchange text regions
---
--- Has two-step logic:
--- - First call remembers the region as the one to be exchanged and highlights it
---   with `MiniOperatorsExchangeFrom` highlight group.
--- - Second call performs the exchange. Basically, a two substeps action:
---   "yank both regions" and replace each one with another.
---
--- Notes:
--- - Use `<C-c>` to stop exchanging after the first step.
---
--- - Exchanged regions can have different (char,line,block)-wise submodes.
---
--- - Works with most cases of intersecting regions, but not officially supported.
---
---@param mode __operators_mode
MiniOperators.exchange = function(mode)
  if H.is_disabled() or not vim.bo.modifiable then return '' end

  -- If used without arguments inside expression mapping, set it as
  -- 'operatorfunc' and call it again as a result of expression mapping.
  if mode == nil then
    vim.o.operatorfunc = 'v:lua.MiniOperators.exchange'
    return 'g@'
  end

  -- Depending on present cache data, perform exchange step
  if not H.exchange_has_step_one() then
    -- Store data about first region
    H.cache.exchange.step_one = H.exchange_set_region_extmark(mode, true)
    if H.cache.exchange.step_one == nil then return end

    -- Temporarily remap `<C-c>` to stop the exchange
    H.exchange_set_stop_mapping()
  else
    -- Store data about second region
    H.cache.exchange.step_two = H.exchange_set_region_extmark(mode, false)
    if H.cache.exchange.step_two == nil then return end

    -- Do exchange
    H.exchange_do()

    -- Stop exchange
    H.exchange_stop()
  end
end

--- Multiply (duplicate) text
---
--- Copies a region (without affecting registers) and puts it directly after.
---
--- Notes:
--- - Supports two types of |[count]|: `[count1]gm[count2][textobject]` with default
---   `config.multiply.prefix` makes `[count1]` copies of region defined by
---   `[count2][textobject]`. Example: `2gm3aw` - 2 copies of `3aw`.
---
--- - |[count]| for "line" mapping (`gmm` by default) is treated as `[count1]` from
---   previous note.
---
--- - Advantages of using this instead of "yank" + "paste":
---    - Doesn't modify any register, while separate steps need some register to
---      hold multiplied text.
---    - In most cases separate steps would be "yank" + "move cursor" + "paste",
---      while "multiply" makes it at once.
---
---@param mode __operators_mode
MiniOperators.multiply = function(mode)
  if H.is_disabled() or not vim.bo.modifiable then return '' end

  -- If used without arguments inside expression mapping, set it as
  -- 'operatorfunc' and call it again as a result of expression mapping.
  if mode == nil then
    vim.o.operatorfunc = 'v:lua.MiniOperators.multiply'
    H.cache.multiply = { count = vim.v.count1 }

    -- Reset count to allow two counts: first for paste, second for textobject
    return vim.api.nvim_replace_termcodes('<Cmd>redraw<CR>g@', true, true, true)
  end

  local count = mode == 'visual' and vim.v.count1 or H.cache.multiply.count
  local data = H.get_region_data(mode)
  if data == nil then return end
  local mark_from, mark_to, submode = data.mark_from, data.mark_to, data.submode

  H.with_temp_context({ registers = { 'x', '"' } }, function()
    -- Yank to temporary "x" register
    local yank_data = { mark_from = mark_from, mark_to = mark_to, submode = submode, mode = mode, register = 'x' }
    H.do_between_marks('y', yank_data)

    -- Modify lines in "x" register
    local func = H.get_config().multiply.func or function(content) return content.lines end
    local x_reginfo = vim.fn.getreginfo('x')
    x_reginfo.regcontents = func({ lines = x_reginfo.regcontents, submode = submode })
    vim.fn.setreg('x', x_reginfo)

    -- Adjust cursor for a proper paste
    local ref_coords = H.multiply_get_ref_coords(mark_from, mark_to, submode)
    vim.api.nvim_win_set_cursor(0, ref_coords)

    -- Paste after textobject from temporary register
    H.cmd_normal(count .. '"xp')

    -- Adjust cursor to be at start of pasted text. Not in linewise mode as it
    -- already is at first non-blank, while this moves to first column.
    if submode ~= 'V' then vim.cmd('normal! `[') end
  end)
end

--- Replace text with register
---
--- Notes:
--- - Supports two types of |[count]|: `[count1]gr[count2][textobject]` with default
---   `config.replace.prefix` puts `[count1]` contents of register over region defined
---   by `[count2][textobject]`. Example: `2gr3aw` - 2 register contents over `3aw`.
---
--- - |[count]| for "line" mapping (`grr` by default) is treated as `[count1]` from
---   previous note.
---
--- - Advantages of using this instead of "visually select" + "paste with |v_P|":
---    - As operator it is dot-repeatable which has cumulative gain in case of
---      multiple replacing is needed.
---    - Can automatically reindent.
---
---@param mode __operators_mode
MiniOperators.replace = function(mode)
  if H.is_disabled() or not vim.bo.modifiable then return '' end

  -- If used without arguments inside expression mapping, set it as
  -- 'operatorfunc' and call it again as a result of expression mapping.
  if mode == nil then
    vim.o.operatorfunc = 'v:lua.MiniOperators.replace'
    H.cache.replace = { count = vim.v.count1, register = vim.v.register }

    -- Reset count to allow two counts: first for paste, second for textobject
    return vim.api.nvim_replace_termcodes('<Cmd>redraw<CR>g@', true, true, true)
  end

  -- Do replace
  -- - Compute `count` and `register` prior getting region data because it
  --   invalidates them for active Visual mode
  local count = mode == 'visual' and vim.v.count1 or H.cache.replace.count
  local register = mode == 'visual' and vim.v.register or H.cache.replace.register
  local data = H.get_region_data(mode)
  if data == nil then return '' end
  data.count = count
  data.register = register
  data.reindent_linewise = H.get_config().replace.reindent_linewise

  H.replace_do(data)

  return ''
end

--- Sort text
---
--- It replaces the region with the output of `config.sort.func`.
--- By default it is |MiniOperators.default_sort_func()| which sorts the text
--- depending on submode.
---
--- Notes:
--- - "line" mapping is charwise (as there is not much sense in sorting
---   linewise a single line). This also results into no |[count]| support.
---
---@param mode __operators_mode
MiniOperators.sort = function(mode)
  if H.is_disabled() or not vim.bo.modifiable then return '' end

  -- If used without arguments inside expression mapping, set it as
  -- 'operatorfunc' and call it again as a result of expression mapping.
  if mode == nil then
    vim.o.operatorfunc = 'v:lua.MiniOperators.sort'
    return 'g@'
  end

  local sort_func = H.get_config().sort.func or MiniOperators.default_sort_func
  H.apply_content_func(sort_func, H.get_region_data(mode))
end

--- Make operator mappings
---
---@param operator_name string Name of existing operator from this module.
---@param lhs_tbl table Table with mappings keys. Should have these fields:
---   - <textobject> `(string)` - Normal mode mapping to operate on textobject.
---   - <line> `(string)` - Normal mode mapping to operate on line.
---     Usually an alias for textobject mapping followed by |_|.
---     For "sort" it operates charwise on whole line without left and right
---     whitespace (as there is not much sense in sorting linewise a single line).
---   - <selection> `(string)` - Visual mode mapping to operate on selection.
---
---   Supply empty string to not create particular mapping. Note: creating `line`
---   mapping needs `textobject` mapping to be set.
---
---@usage >lua
---   require('mini.operators').make_mappings(
---     'replace',
---     { textobject = 'cr', line = 'crr', selection = 'cr' }
---   )
--- <
MiniOperators.make_mappings = function(operator_name, lhs_tbl)
  -- Validate arguments
  if not (type(operator_name) == 'string' and MiniOperators[operator_name] ~= nil) then
    H.error('`operator_name` should be a valid operator name.')
  end
  local is_keys_tbl = type(lhs_tbl) == 'table'
    and type(lhs_tbl.textobject) == 'string'
    and type(lhs_tbl.line) == 'string'
    and type(lhs_tbl.selection) == 'string'
  if not is_keys_tbl then H.error('`lhs_tbl` should be a valid table of keys.') end

  if lhs_tbl.line ~= '' and lhs_tbl.textobject == '' then
    H.error('Creating mapping for `line` needs mapping for `textobject`.')
  end

  -- Make mappings
  local operator_desc = operator_name:sub(1, 1):upper() .. operator_name:sub(2)

  local expr_opts = { expr = true, replace_keycodes = false, desc = operator_desc }
  H.map('n', lhs_tbl.textobject, string.format('v:lua.MiniOperators.%s()', operator_name), expr_opts)

  local rhs = lhs_tbl.textobject .. '_'
  -- - Make `sort()` line mapping to be charwise
  if operator_name == 'sort' then rhs = '^' .. lhs_tbl.textobject .. 'g_' end
  H.map('n', lhs_tbl.line, rhs, { remap = true, desc = operator_desc .. ' line' })

  local visual_rhs = string.format([[<Cmd>lua MiniOperators.%s('visual')<CR>]], operator_name)
  H.map('x', lhs_tbl.selection, visual_rhs, { desc = operator_desc .. ' selection' })
end

--- Default evaluate function
---
--- Evaluate text as Lua code and return object from last line (like if last
--- line is prepended with `return` if it is not already).
---
--- Behavior depends on region submode:
---
--- - For charwise and linewise regions, text evaluated as is.
---
--- - For blockwise region, lines are evaluated per line using only first lines
---   of outputs. This allows separate execution of lines in order to provide
---   something different compared to linewise region.
---
---@param content __operators_content
MiniOperators.default_evaluate_func = function(content)
  if not H.is_content(content) then H.error('`content` should be a content table.') end

  local lines, submode = content.lines, content.submode

  -- In non-blockwise mode return the result of the last line
  if submode ~= H.submode_keys.block then return H.eval_lua_lines(lines) end

  -- In blockwise selection evaluate and return each line separately
  return vim.tbl_map(function(l) return H.eval_lua_lines({ l })[1] end, lines)
end

--- Default sort function
---
--- Sort text based on region submode:
---
--- - For charwise region, split by separator pattern, sort parts, merge back
---   with separators. Actual pattern is inferred based on the array of patterns
---   from `opts.split_patterns`: whichever element is present in the text is
---   used, preferring the earlier one if several are present.
---   Example: sorting "c, b; a" line with default `opts.split_patterns` results
---   into "b; a, c" as it is split only by comma.
---
--- - For linewise and blockwise regions sort lines as is.
---
--- Notes:
--- - Sort is done with |table.sort()| on an array of lines, which doesn't treat
---   whitespace or digits specially. Use |:sort| for more complicated tasks.
---
--- - Pattern is allowed to be an empty string in which case split results into
---   all characters as parts.
---
--- - Pad pattern in `split_patterns` with `%s*` to include whitespace into separator.
---   Example: line "b _ a" with "_" pattern will be sorted as " a_b " (because
---   it is split as "b ", "_", " a" ) while with "%s*_%s*" pattern it results
---   into "a _ b" (split as "b", " _ ", "a").
---
---@param content __operators_content
---@param opts table|nil Options. Possible fields:
---   - <compare_fun> `(function)` - compare function compatible with |table.sort()|.
---     Default: direct compare with `<`.
---   - <split_patterns> `(table)` - array of split Lua patterns to be used for
---     charwise submode. Order is important.
---     Default: `{ '%s*,%s*', '%s*;%s*', '%s+', '' }`.
MiniOperators.default_sort_func = function(content, opts)
  if not H.is_content(content) then H.error('`content` should be a content table.') end

  opts = vim.tbl_deep_extend('force', { compare_fun = nil, split_patterns = nil }, opts or {})

  local compare_fun = opts.compare_fun or function(a, b) return a < b end
  if not vim.is_callable(compare_fun) then H.error('`opts.compare_fun` should be callable.') end

  local split_patterns = opts.split_patterns or { '%s*,%s*', '%s*;%s*', '%s+', '' }
  if not H.islist(split_patterns) then H.error('`opts.split_patterns` should be array.') end

  -- Prepare lines to sort
  local lines, submode = content.lines, content.submode

  if submode ~= 'v' then
    table.sort(lines, compare_fun)
    return lines
  end

  local parts, seps = H.sort_charwise_split(lines, split_patterns)
  table.sort(parts, compare_fun)
  return H.sort_charwise_unsplit(parts, seps)
end

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniOperators.config)

-- Namespaces
H.ns_id = {
  exchange = vim.api.nvim_create_namespace('MiniOperatorsExchange'),
}

-- Cache for all operators
H.cache = {
  exchange = {},
  multiply = {},
  replace = {},
}

-- Submode keys for
H.submode_keys = {
  char = 'v',
  line = 'V',
  block = vim.api.nvim_replace_termcodes('<C-v>', true, true, true),
}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  H.check_type('evaluate', config.evaluate, 'table')
  H.check_type('evaluate.prefix', config.evaluate.prefix, 'string')
  H.check_type('evaluate.func', config.evaluate.func, 'function', true)

  H.check_type('exchange', config.exchange, 'table')
  H.check_type('exchange.prefix', config.exchange.prefix, 'string')
  H.check_type('exchange.reindent_linewise', config.exchange.reindent_linewise, 'boolean')

  H.check_type('multiply', config.multiply, 'table')
  H.check_type('multiply.prefix', config.multiply.prefix, 'string')
  H.check_type('multiply.func', config.multiply.func, 'function', true)

  H.check_type('replace', config.replace, 'table')
  H.check_type('replace.prefix', config.replace.prefix, 'string')
  H.check_type('replace.reindent_linewise', config.replace.reindent_linewise, 'boolean')

  H.check_type('sort', config.sort, 'table')
  H.check_type('sort.prefix', config.sort.prefix, 'string')
  H.check_type('sort.func', config.sort.func, 'function', true)

  return config
end

H.apply_config = function(config)
  MiniOperators.config = config

  local remove_lsp_mapping = function(mode, lhs)
    local map_desc = vim.fn.maparg(lhs, mode, false, true).desc
    if map_desc == nil or string.find(map_desc, 'vim%.lsp') == nil then return end
    vim.keymap.del(mode, lhs)
  end

  local remap_builtin_gx = function(mode)
    if vim.fn.maparg('gX', mode) ~= '' then return end
    local keymap = vim.fn.maparg('gx', mode, false, true)
    local rhs = keymap.callback or keymap.rhs
    if rhs == nil or (keymap.desc or ''):find('URI under cursor') == nil then return end
    vim.keymap.set(mode, 'gX', rhs, { desc = keymap.desc })
  end

  -- Make mappings
  local map_all = function(operator_name)
    -- Map only valid LHS
    local prefix = config[operator_name].prefix
    if type(prefix) ~= 'string' or prefix == '' then return end

    -- Remove conflicting built-in mappings
    if prefix == 'gr' and vim.fn.has('nvim-0.11') == 1 then
      remove_lsp_mapping('n', 'gra')
      remove_lsp_mapping('x', 'gra')
      remove_lsp_mapping('n', 'gri')
      remove_lsp_mapping('n', 'grn')
      remove_lsp_mapping('n', 'grr')
      remove_lsp_mapping('n', 'grt')
    end

    if prefix == 'gx' and vim.fn.has('nvim-0.10') == 1 then
      remap_builtin_gx('n')
      remap_builtin_gx('x')
    end

    local lhs_tbl = {
      textobject = prefix,
      line = prefix .. vim.fn.strcharpart(prefix, vim.fn.strchars(prefix) - 1, 1),
      selection = prefix,
    }
    MiniOperators.make_mappings(operator_name, lhs_tbl)
  end

  map_all('evaluate')
  map_all('exchange')
  map_all('multiply')
  map_all('replace')
  map_all('sort')
end

H.is_disabled = function() return vim.g.minioperators_disable == true or vim.b.minioperators_disable == true end

H.get_config = function(config)
  return vim.tbl_deep_extend('force', MiniOperators.config, vim.b.minioperators_config or {}, config or {})
end

H.create_autocommands = function()
  local gr = vim.api.nvim_create_augroup('MiniOperators', {})
  vim.api.nvim_create_autocmd('ColorScheme', { group = gr, callback = H.create_default_hl, desc = 'Ensure colors' })
end

H.create_default_hl = function()
  vim.api.nvim_set_hl(0, 'MiniOperatorsExchangeFrom', { default = true, link = 'IncSearch' })
end

-- Evaluate -------------------------------------------------------------------
H.eval_lua_lines = function(lines)
  -- Copy to not modify input
  local lines_copy, n = vim.deepcopy(lines), #lines
  lines_copy[n] = (lines_copy[n]:find('^%s*return%s+') == nil and 'return ' or '') .. lines_copy[n]

  local str_to_eval = table.concat(lines_copy, '\n')

  -- Allow returning tuple with any value(s) being `nil`
  return H.inspect_objects(assert(loadstring(str_to_eval))())
end

H.inspect_objects = function(...)
  local objects = {}
  -- Not using `{...}` because it removes `nil` input
  for i = 1, select('#', ...) do
    local v = select(i, ...)
    table.insert(objects, vim.inspect(v))
  end

  return vim.split(table.concat(objects, '\n'), '\n')
end

-- Exchange -------------------------------------------------------------------
H.exchange_do = function()
  local step_one, step_two = H.cache.exchange.step_one, H.cache.exchange.step_two

  -- Do nothing if regions are the same
  if H.exchange_is_same_steps(step_one, step_two) then return end

  -- Save temporary registers
  local reg_one, reg_two = vim.fn.getreginfo('a'), vim.fn.getreginfo('b')

  -- Create step temporary contexts (data that should not change)
  local context_one = { buf_id = step_one.buf_id, marks = { 'x', 'y' }, registers = { '"' } }
  local context_two = { buf_id = step_two.buf_id, marks = { 'x', 'y' }, registers = { '"' } }

  -- Put regions into registers. NOTE: do it before actual exchange to allow
  -- intersecting regions.
  local populating_register = function(step, register)
    return function()
      H.exchange_set_step_marks(step, { 'x', 'y' })
      local yank_data =
        { mark_from = 'x', mark_to = 'y', submode = step.submode, mode = step.mode, register = register }
      H.do_between_marks('y', yank_data)
    end
  end

  H.with_temp_context(context_one, populating_register(step_one, 'a'))
  H.with_temp_context(context_two, populating_register(step_two, 'b'))

  -- Sequentially replace
  local replacing = function(step, register)
    return function()
      H.exchange_set_step_marks(step, { 'x', 'y' })

      local replace_data = {
        count = 1,
        mark_from = 'x',
        mark_to = 'y',
        mode = step.mode,
        register = register,
        reindent_linewise = H.get_config().exchange.reindent_linewise,
        submode = step.submode,
      }
      H.replace_do(replace_data)
    end
  end

  H.with_temp_context(context_one, replacing(step_one, 'b'))
  H.with_temp_context(context_two, replacing(step_two, 'a'))

  -- Restore temporary registers
  vim.fn.setreg('a', reg_one)
  vim.fn.setreg('b', reg_two)
end

H.exchange_has_step_one = function()
  local step_one = H.cache.exchange.step_one
  if type(step_one) ~= 'table' then return false end

  if not vim.api.nvim_buf_is_valid(step_one.buf_id) then
    H.exchange_stop()
    return false
  end
  return true
end

H.exchange_set_region_extmark = function(mode, add_highlight)
  local ns_id = H.ns_id.exchange

  -- Compute regular marks for target region
  local region_data = H.get_region_data(mode)
  if region_data == nil then return end
  local submode = region_data.submode
  local markcoords_from, markcoords_to = H.get_mark(region_data.mark_from), H.get_mark(region_data.mark_to)

  -- Compute extmark's range for target region
  local extmark_from = { markcoords_from[1] - 1, markcoords_from[2] }
  local extmark_to = { markcoords_to[1] - 1, H.get_next_char_bytecol(markcoords_to) }

  -- Adjust for visual selection in case of 'selection=exclusive'
  if region_data.mark_to == '>' and vim.o.selection == 'exclusive' then extmark_to[2] = extmark_to[2] - 1 end

  -- - Tweak columns for linewise marks
  if submode == 'V' then
    extmark_from[2] = 0
    extmark_to[2] = vim.fn.col({ extmark_to[1] + 1, '$' }) - 1
  end

  -- Set extmark to represent region. Add highlighting inside of it only if
  -- needed and not in blockwise submode (can't highlight that way).
  local buf_id = vim.api.nvim_get_current_buf()

  local extmark_hl_group
  if add_highlight and submode ~= H.submode_keys.block then extmark_hl_group = 'MiniOperatorsExchangeFrom' end

  local extmark_opts = {
    end_row = extmark_to[1],
    end_col = extmark_to[2],
    hl_group = extmark_hl_group,
    -- Using this gravity is better for handling empty lines in linewise mode
    end_right_gravity = mode == 'line',
  }
  local region_extmark_id = vim.api.nvim_buf_set_extmark(buf_id, ns_id, extmark_from[1], extmark_from[2], extmark_opts)

  -- - Possibly add highlighting for blockwise mode
  if add_highlight and extmark_hl_group == nil then
    -- Highlighting blockwise region needs full register type with width
    local opts = { regtype = H.exchange_get_blockwise_regtype(markcoords_from, markcoords_to) }
    H.highlight_range(buf_id, ns_id, 'MiniOperatorsExchangeFrom', extmark_from, extmark_to, opts)
  end

  -- Return data to cache
  return { buf_id = buf_id, mode = mode, submode = submode, extmark_id = region_extmark_id }
end

H.exchange_get_region_extmark = function(step)
  return vim.api.nvim_buf_get_extmark_by_id(step.buf_id, H.ns_id.exchange, step.extmark_id, { details = true })
end

H.exchange_set_step_marks = function(step, mark_names)
  local extmark_details = H.exchange_get_region_extmark(step)

  H.set_mark(mark_names[1], { extmark_details[1] + 1, extmark_details[2] })

  -- Unadjust for visual selection in case of 'selection=exclusive'
  local should_unadjust = step.mode == 'visual' and vim.o.selection == 'exclusive'
  local col_offset = should_unadjust and 1 or 0

  H.set_mark(mark_names[2], { extmark_details[3].end_row + 1, extmark_details[3].end_col - 1 + col_offset })
end

H.exchange_get_blockwise_regtype = function(markcoords_from, markcoords_to)
  local f = function()
    -- Yank into "z" register and return its blockwise type
    H.set_mark('x', markcoords_from)
    H.set_mark('y', markcoords_to)
    local yank_data = { mark_from = 'x', mark_to = 'y', submode = H.submode_keys.block, mode = 'block', register = 't' }
    H.do_between_marks('y', yank_data)

    return vim.fn.getregtype('t')
  end

  return H.with_temp_context({ buf_id = 0, marks = { 'x', 'y' }, registers = { 't' } }, f)
end

H.exchange_stop = function()
  H.exchange_del_stop_mapping()

  local cur, ns_id = H.cache.exchange, H.ns_id.exchange
  if cur.step_one ~= nil then pcall(vim.api.nvim_buf_clear_namespace, cur.step_one.buf_id, ns_id, 0, -1) end
  if cur.step_two ~= nil then pcall(vim.api.nvim_buf_clear_namespace, cur.step_two.buf_id, ns_id, 0, -1) end
  H.cache.exchange = {}
end

H.exchange_set_stop_mapping = function()
  local lhs = '<C-c>'
  H.cache.exchange.stop_restore_map_data = vim.fn.maparg(lhs, 'n', false, true)
  vim.keymap.set('n', lhs, H.exchange_stop, { desc = 'Stop exchange' })
end

H.exchange_del_stop_mapping = function()
  local map_data = H.cache.exchange.stop_restore_map_data
  if map_data == nil then return end

  -- Try restore previous mapping if it was set
  if vim.tbl_count(map_data) > 0 then
    vim.fn.mapset('n', false, map_data)
  else
    vim.keymap.del('n', map_data.lhs or '<C-c>')
  end
end

H.exchange_is_same_steps = function(step_one, step_two)
  if step_one.buf_id ~= step_two.buf_id or step_one.submode ~= step_two.submode then return false end
  -- Region's start and end should be the same
  local one, two = H.exchange_get_region_extmark(step_one), H.exchange_get_region_extmark(step_two)
  return one[1] == two[1] and one[2] == two[2] and one[3].end_row == two[3].end_row and one[3].end_col == two[3].end_col
end

-- Multiply -------------------------------------------------------------------
H.multiply_get_ref_coords = function(mark_from, mark_to, submode)
  local markcoords_from, markcoords_to = H.get_mark(mark_from), H.get_mark(mark_to)
  if mark_to == '>' and vim.o.selection == 'exclusive' then markcoords_to[2] = markcoords_to[2] - 1 end

  if submode ~= H.submode_keys.block then return markcoords_to end

  -- In blockwise selection go to top right corner (allowing for presence of
  -- multibyte characters)
  local row = math.min(markcoords_from[1], markcoords_to[1])

  -- - "from"/"to" may not only be "top-left"/"bottom-right" but also
  --   "top-right" and "bottom-left"
  local virtcol_from = vim.fn.virtcol({ markcoords_from[1], markcoords_from[2] + 1 })
  local virtcol_to = vim.fn.virtcol({ markcoords_to[1], markcoords_to[2] + 1 })
  local virtcol = math.max(virtcol_from, virtcol_to)

  local col = vim.fn.virtcol2col(0, row, virtcol)

  return { row, col - 1 }
end

-- Replace --------------------------------------------------------------------
--- Delete region between two marks and paste from register
---
---@param data table Fields:
---   - <count> (optional) - Number of times to paste.
---   - <mark_from> - Name of "from" mark.
---   - <mark_to> - Name of "to" mark.
---   - <mode> - Operator mode. One of 'visual', 'char', 'line', 'block'.
---   - <register> - Name of register from which to paste.
---   - <submode> - Region submode. One of 'v', 'V', '\22'.
---@private
H.replace_do = function(data)
  -- NOTE: Ideally, implementation would leverage "Visually select - press `P`"
  -- approach, but it has issues with dot-repeat. The `cancel_redo()` approach
  -- doesn't work probably because `P` implementation uses more than one
  -- dot-repeat overwrite.
  local register, submode = data.register, data.submode
  local mark_from, mark_to = data.mark_from, data.mark_to

  -- Do nothing with invalid register (don't allow A-Z because they are used to
  -- append to lowercase register and have no use here)
  local reg_is_invalid = string.find(register, '^[0-9a-z"%-:.%%#=*+_/]$') == nil
  if reg_is_invalid then H.error('Register ' .. vim.inspect(register) .. ' is invalid.') end

  -- Get reginfo and infer missing data (can be empty for special registers)
  local reg_info = vim.fn.getreginfo(register)
  if reg_info.regcontents == nil then H.error('Register ' .. vim.inspect(register) .. ' is empty.') end
  reg_info.regtype = reg_info.regtype or 'v'

  -- Determine if region is at edge which is needed for the correct paste key
  local from_line, from_col = unpack(H.get_mark(mark_from))
  local to_line, to_col = unpack(H.get_mark(mark_to))
  local edge_to_col = vim.fn.col({ to_line, '$' }) - 1 - (vim.o.selection == 'exclusive' and 0 or 1)

  local is_edge_line = submode == 'V' and to_line == vim.fn.line('$')
  local is_edge_col = submode ~= 'V' and to_col == edge_to_col and vim.o.virtualedit ~= 'all'
  local is_edge = is_edge_line or is_edge_col

  local covers_linewise_all_buffer = is_edge_line and from_line == 1

  -- Compute current indent if needed
  local init_indent
  local should_reindent = data.reindent_linewise and data.submode == 'V' and vim.o.equalprg == ''
  if should_reindent then init_indent = H.get_region_indent(mark_from, mark_to) end

  -- Delete region to black whole register
  -- - Delete single character in blockwise submode with inclusive motion.
  --   See https://github.com/neovim/neovim/issues/24613
  local is_blockwise_single_cell = submode == H.submode_keys.block and from_line == to_line and from_col == to_col
  local forced_motion = is_blockwise_single_cell and 'v' or submode

  local delete_data =
    { mark_from = mark_from, mark_to = mark_to, submode = forced_motion, mode = data.mode, register = '_' }
  H.do_between_marks('d', delete_data)

  -- Set temporary register data to have proper submode and indent
  -- NOTE: use dedicated temporary register to workaround not being able to
  -- write register data into readonly registers ('%', '#', '.').
  local tmp_register, tmp_reg_info = register == '=' and '=' or 'x', vim.deepcopy(reg_info)
  if tmp_reg_info.regtype:sub(1, 1) ~= submode then tmp_reg_info.regtype = submode end
  if should_reindent then tmp_reg_info.regcontents = H.update_indent(tmp_reg_info.regcontents, init_indent) end

  local cache_reg_info = vim.fn.getreginfo(tmp_register)
  vim.fn.setreg(tmp_register, tmp_reg_info)

  -- Paste
  local expr_reg_keys = tmp_register == '=' and (reg_info.regcontents[1] .. '\r') or ''
  local paste_keys = (data.count or 1) .. '"' .. tmp_register .. expr_reg_keys .. (is_edge and 'p' or 'P')
  H.cmd_normal(paste_keys)

  -- Restore temporary register data
  vim.fn.setreg(tmp_register, cache_reg_info)

  -- Adjust cursor to be at start mark
  vim.api.nvim_win_set_cursor(0, { from_line, from_col })

  -- Adjust for extra empty line after pasting inside empty buffer
  if covers_linewise_all_buffer then vim.api.nvim_buf_set_lines(0, 0, 1, true, {}) end
end

-- Sort -----------------------------------------------------------------------
H.sort_charwise_split = function(lines, split_patterns)
  local lines_str = table.concat(lines, '\n')

  local pat
  for _, pattern in ipairs(split_patterns) do
    if lines_str:find(pattern) ~= nil then
      pat = pattern
      break
    end
  end

  if pat == nil then return lines, {} end

  -- Allow pattern to be an empty string to get every character
  if pat == '' then
    local parts = vim.split(lines_str, '')
    local seps = vim.fn['repeat']({ '' }, #parts - 1)
    return parts, seps
  end

  -- Split into parts and separators
  local parts, seps = {}, {}
  local init, n = 1, lines_str:len()
  while init < n do
    local sep_from, sep_to = string.find(lines_str, pat, init)
    if sep_from == nil then break end
    table.insert(parts, lines_str:sub(init, sep_from - 1))
    table.insert(seps, lines_str:sub(sep_from, sep_to))
    init = sep_to + 1
  end
  table.insert(parts, lines_str:sub(init, n))

  return parts, seps
end

H.sort_charwise_unsplit = function(parts, seps)
  local all = {}
  for i = 1, #parts do
    table.insert(all, parts[i])
    table.insert(all, seps[i] or '')
  end

  return vim.split(table.concat(all, ''), '\n')
end

-- General --------------------------------------------------------------------
H.apply_content_func = function(content_func, data)
  if data == nil then return end
  local mark_from, mark_to, submode = data.mark_from, data.mark_to, data.submode
  local reindent_linewise = data.reindent_linewise

  H.with_temp_context({ marks = { '>' }, registers = { 'x', '"' } }, function()
    -- Yank effective region content into "x" register.
    data.register = 'x'
    H.do_between_marks('y', data)

    -- Apply content function to register content
    local reg_info = vim.fn.getreginfo('x')
    local content_init = { lines = reg_info.regcontents, submode = submode }
    reg_info.regcontents = content_func(content_init)
    vim.fn.setreg('x', reg_info)

    -- Replace region with new register content
    local replace_data = {
      count = 1,
      mark_from = mark_from,
      mark_to = mark_to,
      mode = data.mode,
      register = 'x',
      reindent_linewise = reindent_linewise,
      submode = submode,
    }
    H.replace_do(replace_data)
  end)
end

H.do_between_marks = function(operator, data)
  -- Force 'inclusive' selection as `<C-v>` submode does not force it (while
  -- `v` does). This means that in case of 'selection=exclusive' marks should
  -- be adjusted prior to this.
  local cache_selection = vim.o.selection
  if data.mode == 'block' and vim.o.selection == 'exclusive' then vim.o.selection = 'inclusive' end

  -- Don't trigger `TextYankPost` event as these yanks are not user-facing
  local is_yank = operator == 'y'
  local cache_eventignore = vim.o.eventignore
  if is_yank then vim.o.eventignore = 'TextYankPost' end

  -- Make sure that marks `[` and `]` don't change after `y`
  local context_marks = { '<', '>' }
  if is_yank then context_marks = vim.list_extend(context_marks, { '[', ']' }) end
  H.with_temp_context({ marks = context_marks }, function()
    local mark_from, mark_to, submode, register = data.mark_from, data.mark_to, data.submode, data.register
    local keys
    if data.mode == 'visual' and vim.o.selection == 'exclusive' then
      keys = ('`' .. mark_from) .. submode .. ('`' .. mark_to) .. ('"' .. register .. operator)
    else
      keys = ('`' .. mark_from) .. ('"' .. register .. operator .. submode) .. ('`' .. mark_to)
    end

    -- Make sure that outer action is dot-repeatable by cancelling effect of
    -- `d` or dot-repeatable `y`
    local cancel_redo = operator == 'd' or (operator == 'y' and vim.o.cpoptions:find('y') ~= nil)
    H.cmd_normal(keys, { cancel_redo = cancel_redo })
  end)

  vim.o.selection = cache_selection
  if is_yank then vim.o.eventignore = cache_eventignore end
end

H.is_content = function(x) return type(x) == 'table' and H.islist(x.lines) and type(x.submode) == 'string' end

-- Marks ----------------------------------------------------------------------
H.get_region_data = function(mode)
  local submode = H.get_submode(mode)
  local selection_is_visual = mode == 'visual'

  -- Make sure that visual selection marks are relevant
  if selection_is_visual and H.is_visual_mode() then vim.cmd('normal! \27') end

  local mark_from = selection_is_visual and '<' or '['
  local mark_to = selection_is_visual and '>' or ']'

  -- Detect empty region. NOTE: This doesn't work when cursor is on first line
  -- and first column, but there doesn't seem to be a better way to do that.
  local pos_from, pos_to = H.get_mark(mark_from), H.get_mark(mark_to)
  if pos_to[1] < pos_from[1] or (pos_to[1] == pos_from[1] and pos_to[2] < pos_from[2]) then return end

  return { mode = mode, submode = submode, mark_from = mark_from, mark_to = mark_to }
end

H.get_region_indent = function(mark_from, mark_to)
  local l_from, l_to = H.get_mark(mark_from)[1], H.get_mark(mark_to)[1]
  local lines = vim.api.nvim_buf_get_lines(0, l_from - 1, l_to, true)
  return H.compute_indent(lines)
end

H.get_mark = function(mark_name) return vim.api.nvim_buf_get_mark(0, mark_name) end

H.set_mark = function(mark_name, mark_data) vim.api.nvim_buf_set_mark(0, mark_name, mark_data[1], mark_data[2], {}) end

H.str_utfindex = function(s, i) return vim.str_utfindex(s, 'utf-32', i) end
if vim.fn.has('nvim-0.11') == 0 then H.str_utfindex = function(s, i) return (vim.str_utfindex(s, i)) end end

H.str_byteindex = function(s, i) return vim.str_byteindex(s, 'utf-32', i) end
if vim.fn.has('nvim-0.11') == 0 then H.str_byteindex = function(s, i) return vim.str_byteindex(s, i) end end

H.get_next_char_bytecol = function(markcoords)
  local line = vim.fn.getline(markcoords[1])
  local utf_index = H.str_utfindex(line, math.min(line:len(), markcoords[2] + 1))
  return H.str_byteindex(line, utf_index)
end

-- Indent ---------------------------------------------------------------------
H.compute_indent = function(lines)
  local res_indent, res_indent_width = nil, math.huge
  local blank_indent, blank_indent_width = nil, math.huge
  for _, l in ipairs(lines) do
    local cur_indent = l:match('^%s*')
    local cur_indent_width = cur_indent:len()
    local is_blank = cur_indent_width == l:len()
    if not is_blank and cur_indent_width < res_indent_width then
      res_indent, res_indent_width = cur_indent, cur_indent_width
    elseif is_blank and cur_indent_width < blank_indent_width then
      blank_indent, blank_indent_width = cur_indent, cur_indent_width
    end
  end

  return res_indent or blank_indent or ''
end

H.update_indent = function(lines, new_indent)
  -- Replace current indent with new indent without affecting blank lines
  local n_cur_indent = H.compute_indent(lines):len()
  return vim.tbl_map(function(l)
    if l:find('^%s*$') ~= nil then return l end
    return new_indent .. l:sub(n_cur_indent + 1)
  end, lines)
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.operators) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.map = function(mode, lhs, rhs, opts)
  if lhs == '' then return end
  opts = vim.tbl_deep_extend('force', { silent = true }, opts or {})
  vim.keymap.set(mode, lhs, rhs, opts)
end

H.get_submode = function(mode)
  if mode == 'visual' then return H.is_visual_mode() and vim.fn.mode() or vim.fn.visualmode() end
  return H.submode_keys[mode]
end

H.is_visual_mode = function()
  local cur_mode = vim.fn.mode()
  return cur_mode == 'v' or cur_mode == 'V' or cur_mode == H.submode_keys.block
end

H.with_temp_context = function(context, f)
  local res
  vim.api.nvim_buf_call(context.buf_id or 0, function()
    -- Cache temporary data
    local marks_data = {}
    for _, mark_name in ipairs(context.marks or {}) do
      marks_data[mark_name] = H.get_mark(mark_name)
    end

    local reg_data = {}
    for _, reg_name in ipairs(context.registers or {}) do
      reg_data[reg_name] = vim.fn.getreginfo(reg_name)
    end

    -- Perform action
    res = f()

    -- Restore data
    for mark_name, data in pairs(marks_data) do
      pcall(H.set_mark, mark_name, data)
    end
    for reg_name, data in pairs(reg_data) do
      pcall(vim.fn.setreg, reg_name, data)
    end
  end)

  return res
end

-- A hack to restore previous dot-repeat action
H.cancel_redo = function() end
(function()
  local has_ffi, ffi = pcall(require, 'ffi')
  if not has_ffi then return end
  local has_cancel_redo = pcall(ffi.cdef, 'void CancelRedo(void)')
  if not has_cancel_redo then return end
  H.cancel_redo = function() pcall(ffi.C.CancelRedo) end
end)()

H.cmd_normal = function(command, opts)
  opts = opts or {}
  local cancel_redo = opts.cancel_redo
  if cancel_redo == nil then cancel_redo = true end

  vim.cmd('silent keepjumps normal! ' .. command)

  if cancel_redo then H.cancel_redo() end
end

-- TODO: Remove after compatibility with Neovim=0.9 is dropped
H.islist = vim.fn.has('nvim-0.10') == 1 and vim.islist or vim.tbl_islist

-- TODO: Remove after compatibility with Neovim=0.10 is dropped
H.highlight_range = function(...) vim.hl.range(...) end
if vim.fn.has('nvim-0.11') == 0 then H.highlight_range = function(...) vim.highlight.range(...) end end

return MiniOperators
