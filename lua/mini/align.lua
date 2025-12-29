--- *mini.align* Align text interactively
---
--- MIT License Copyright (c) 2022 Evgeni Chasnovski

--- Rich and flexible customization of both alignment rules and user interaction.
--- Works with charwise, linewise, and blockwise selections in both Normal mode
--- (on textobject/motion; with dot-repeat) and Visual mode.
---
--- Features:
--- - Alignment is done in three main steps:
---     - <Split> lines into parts based on Lua pattern(s) or user-supplied rule.
---     - <Justify> parts for certain side(s) to be same width inside columns.
---     - <Merge> parts to be lines, with customizable delimiter(s).
---
---     Each main step can be preceded by other steps (pre-steps) to achieve
---     highly customizable outcome. See `steps` value in |MiniAlign.config|.
---     For more details, see |MiniAlign-glossary| and |MiniAlign-algorithm|.
---
--- - User can control alignment interactively by pressing customizable modifiers
---   (single keys representing how alignment steps and/or options should change).
---   Some of default modifiers:
---     - Press `s` to enter split Lua pattern.
---     - Press `j` to choose justification side from available ones ("left",
---       "center", "right", "none").
---     - Press `m` to enter merge delimiter.
---     - Press `f` to enter filter Lua expression to configure which parts
---       will be affected (like "align only first column").
---     - Press `i` to ignore some commonly unwanted split matches.
---     - Press `p` to pair neighboring parts so they be aligned together.
---     - Press `t` to trim whitespace from parts.
---     - Press `<BS>` (backspace) to delete some last pre-step.
---
---     For more details, see |MiniAlign-modifiers-builtin| and |MiniAlign-examples|.
---
--- - Alignment can be done with instant preview (result is updated after each
---   modifier) or without it (result is shown and accepted after non-default
---   split pattern is set).
---
--- - Every user interaction is accompanied with helper status message showing
---   relevant information about current alignment process.
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.align').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `MiniAlign`
--- which you can use for scripting or manually (with `:lua MiniAlign.*`).
---
--- See |MiniAlign.config| for available config settings.
---
--- You can override runtime config settings (like `config.modifiers`) locally
--- to buffer inside `vim.b.minialign_config` which should have same structure
--- as `MiniAlign.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- To stop module from showing non-error feedback, set `config.silent = true`.
---
--- # Comparisons ~
---
--- - [junegunn/vim-easy-align](https://github.com/junegunn/vim-easy-align):
---     - 'mini.align' is mostly designed after 'junegunn/vim-easy-align', so
---       there are a lot of similarities.
---     - Both plugins allow users to change alignment options interactively by
---       pressing modifier keys (albeit completely different default ones).
---       'junegunn/vim-easy-align' has those modifiers fixed, while 'mini.align'
---       allows their full customization. See |MiniAlign.config| for examples.
---     - 'junegunn/vim-easy-align' is designed to treat delimiters differently
---       than other parts of strings. 'mini.align' doesn't distinguish split
---       parts from one another by design: splitting is allowed to be done
---       based on some other logic than by splitting on delimiters.
---     - 'junegunn/vim-easy-align' initially aligns by only first delimiter.
---       'mini.align' initially aligns by all delimiter.
---     - 'junegunn/vim-easy-align' implements special filtering by delimiter
---       row number. 'mini.align' has builtin filtering based on Lua code
---       supplied by user in modifier phase. See |MiniAlign.gen_step.filter()|
---       and 'f' builtin modifier.
---     - 'mini.align' treats any non-registered modifier as a plain delimiter
---       pattern, while 'junegunn/vim-easy-align' does not.
---     - 'mini.align' exports core Lua function used for aligning strings
---       (|MiniAlign.align_strings()|).
--- - [godlygeek/tabular](https://github.com/godlygeek/tabular):
---     - 'godlygeek/tabular' is mostly designed around single command which is
---       customized by printing its parameters. 'mini.align' implements
---       different concept of interactive alignment through pressing
---       customizable single character modifiers.
---     - 'godlygeek/tabular' can detect region upon which alignment can be
---       desirable. 'mini.align' does not by design: use Visual selection or
---       textobject/motion to explicitly define region to align.
---
--- # Disabling ~
---
--- To disable, set `vim.g.minialign_disable` (globally) or `vim.b.minialign_disable`
--- (for a buffer) to `true`. Considering high number of different scenarios
--- and customization intentions, writing exact rules for disabling module's
--- functionality is left to user. See |mini.nvim-disabling-recipes| for common
--- recipes.
---@tag MiniAlign

--- PARTS ~
--- 2d array of strings (array of arrays of strings).
--- See more in |MiniAlign.as_parts()|.
---
--- ROW ~
--- First-level array of parts (like `parts[1]`).
---
--- COLUMN ~
--- Array of strings, constructed from parts elements with the same
--- second-level index (like `{ parts[1][1],` `parts[2][1], ... }`).
---
--- STEP ~
--- A named callable. See |MiniAlign.new_step()|. When used in terms of alignment
--- steps, callable takes two arguments: some object (parts or string array)
--- and option table.
---
--- SPLIT ~
--- Process of taking array of strings and converting it into parts.
---
--- JUSTIFY ~
--- Process of taking parts and converting them to aligned parts (all elements
--- have same widths inside columns).
---
--- MERGE ~
--- Process of taking parts and converting it back to array of strings. Usually
--- by concatenating rows into strings.
---
--- REGION ~
--- Table representing region in a buffer. Fields <from> / <to> have inclusive
--- start / end positions (<to> might be `nil` to describe empty region).
--- Positions are also tables with <line> and <col> fields (both start at 1).
---
--- MODE ~
--- Either charwise ("char", `v`, |charwise|), linewise ("line", `V`, |linewise|)
--- or blockwise ("block", `<C-v>`, |blockwise-visual|)
---@tag MiniAlign-glossary

--- There are two main processes implemented in 'mini.align': strings alignment
--- and interactive region alignment. See |MiniAlign-glossary| for more information
--- about used terms.
---
--- # Strings alignment ~
---
--- Main implementation is in |MiniAlign.align_strings()|. Its input is array of
--- strings and output - array of aligned strings. The process consists from three
--- main steps (split, justify, merge) which can be preceded by any number of
--- preliminary steps (pre-split, pre-justify, pre-merge).
---
--- Algorithm:
--- - <Pre-split>. Take input array of strings and consecutively apply all
---   pre-split steps (`steps.pre_split`). Each one has `(strings, opts)` signature
---   and should modify array in place.
--- - <Split>. Take array of strings and convert it to parts with `steps.split()`.
---   It has `(strings, opts)` signature and should return parts.
--- - <Pre-justify>. Take parts and consecutively apply all pre-justify
---   steps (`steps.pre_justify`). Each one has `(parts, opts)` signature and
---   should modify parts in place.
--- - <Justify>. Take parts and apply `steps.justify()`. It has `(parts, opts)`
---   signature and should modify parts in place.
--- - <Pre-merge>. Take parts and consecutively apply all pre-merge
---   steps (`steps.pre_merge`). Each one has `(parts, opts)` signature and
---   should modify parts in place.
--- - <Merge>. Take parts and convert it to array of strings with `steps.merge()`.
---   It has `(parts, opts)` signature and should return array of strings.
---
--- Notes:
--- - All table objects are initially copied so that modification in place doesn't
---   affect workflow.
--- - Default main steps are designed to be controlled via options. See
---   |MiniAlign.align_strings()| and default step entries in |MiniAlign.gen_step|.
--- - All steps are guaranteed to take same option table as second argument.
---   This allows steps to "talk" to each other, i.e. earlier steps can pass data
---   to later ones.
---
--- # Interactive region alignment ~
---
--- Interactive alignment is a main entry point for most users. It can be done
--- in two flavors:
--- - <Without-preview>. Initiated via mapping defined in `start` of
---   `MiniAlign.config.mappings`. Alignment is accepted once split pattern becomes
---   non-default.
--- - <With-preview>. Initiated via mapping defined in `start_with_preview` of
---   `MiniAlign.config.mappings`. Alignment result is shown after every modifier
---   and is accepted after `<CR>` (`Enter`) is hit. Note: each preview is done by
---   applying current alignment steps and options to the initial region lines,
---   not the ones currently displaying in preview.
---
--- Lifecycle (assuming default mappings):
--- - <Initiate-alignment>:
---     - In Normal mode type `ga` (or `gA` to show preview) followed by textobject
---       or motion defining region to be aligned.
---     - In Visual mode select region and type `ga` (or `gA` to show preview).
---   Strings contained in selected region will be used as input to
---   |MiniAlign.align_strings()|.
---   Beware of mode when selecting region: charwise (`v`), linewise (`V`), or
---   blockwise (`<C-v>`). They all behave differently.
--- - <Press-modifiers>. Press single keys one at a time:
---     - If pressed key is among table keys of `modifiers` table of
---       |MiniAlign.config|, its function value is executed. It usually modifies
---       some options(s) and/or affects some pre-step(s).
---     - If pressed key is not among defined modifiers, it is treated as plain
---       split pattern.
---   This process can either end by itself (usually in case of no preview and
---   non-default split pattern being set) or you can choose to end it manually.
--- - <Accept-or-discard>. In case of active preview, accept current result by
---   pressing `<CR>`. Discard any result and return to initial regions with
---   either `<Esc>` or `<C-c>`.
---
--- See more in |MiniAlign-modifiers-builtin| and |MiniAlign-examples|.
---
--- Notes:
--- - Visual blockwise selection works best with 'virtualedit' equal to "block"
---   or "all".
--- - Alignment with preview works best with 'showmode' disabled.
---@tag MiniAlign-algorithm

--- Overview of builtin modifiers
---
--- All examples assume interactive alignment with preview in linewise mode. With
--- default mappings, use `V` to select lines and `gA` to initiate alignment. It
--- might be helpful to copy lines into modifiable buffer and experiment yourself.
---
--- Notes:
--- - Any pressed key which doesn't have defined modifier will be treated as
---   plain split pattern.
--- - All modifiers can be customized inside |MiniAlign.setup()|. See "Modifiers"
---   section of |MiniAlign.config|.
---
--- # Main option modifiers ~
---
--- <s> Enter split pattern (confirm prompt by pressing `<CR>`). Input is treated
---   as plain delimiter.
---
---   Before: >
---   a-b-c
---   aa-bb-cc
--- <
---   After typing `s-<CR>`: >
---   a -b -c
---   aa-bb-cc
--- <
--- <j> Choose justify side. Prompts user (with helper message) to type single
---   character identifier of side: `l`eft, `c`enter, `r`ight, `n`one.
---
---   Before: >
---   a_b_c
---   aa_bb_cc
--- <
---   After typing `_jr` (first make split by `_`): >
---    a_ b_ c
---   aa_bb_cc
--- <
--- <m> Enter merge delimiter (confirm prompt by pressing `<CR>`).
---
---   Before: >
---   a_b_c
---   aa_bb_cc
--- <
---   After typing `_m--<CR>` (first make split by `_`): >
---   a --_--b --_--c
---   aa--_--bb--_--cc
--- <
--- # Modifiers adding pre-steps ~
---
--- <f> Enter filter expression. See more details in |MiniAlign.gen_step.filter()|.
---
---   Before: >
---   a_b_c
---   aa_bb_cc
--- <
---   After typing `_fn==1<CR>` (first make split by `_`): >
---   a _b_c
---   aa_bb_cc
--- <
--- <i> Ignore some split matches. It modifies `split_exclude_patterns` option by
---   adding commonly wanted patterns. See more details in
---   |MiniAlign.gen_step.ignore_split()|.
---
---   Before: >
---   /* This_is_assumed_to_be_comment */
---   a"_"_b
---   aa_bb
--- <
---   After typing `_i` (first make split by `_`): >
---   /* This_is_assumed_to_be_comment */
---   a"_"_b
---   aa  _bb
--- <
--- <p> Pair neighboring parts.
---
---   Before: >
---   a_b_c
---   aaa_bbb_ccc
--- <
---   After typing `_p` (first make split by `_`): >
---   a_  b_  c
---   aaa_bbb_ccc
--- <
--- <t> Trim parts from whitespace on both sides (keeping indentation).
---
---   Before: >
---   a   _   b   _   c
---     aa _bb _cc
--- <
---   After typing `_t` (first make split by `_`): >
---   a   _b _c
---     aa_bb_cc
--- <
--- # Delete some last pre-step ~
---
--- <BS> Delete one of the pre-steps. If there is only one kind of pre-steps,
---   remove its latest added one. If not, prompt user to choose pre-step kind
---   by entering single character: `s`plit, `j`ustify, `m`erge.
---
---   Examples:
---   - `tp<BS>` results in only "trim" step to be left.
---   - `it<BS>` prompts to choose which step to delete (pre-split or
---     pre-justify in this case).
---
--- # Special configurations for common splits ~
---
--- <=> Use special pattern to align by a group of consecutive "=". It can be
---   preceded by any number of punctuation marks and followed by some sommon
---   punctuation characters. Trim whitespace and merge with single space.
---
---   Before: >
---   a=b
---   aa<=bb
---   aaa===bbb
---   aaaa   =   cccc
--- <
---   After typing `=`: >
---   a    =   b
---   aa   <=  bb
---   aaa  === bbb
---   aaaa =   cccc
--- <
--- <,> Besides splitting by "," character, trim whitespace, pair neighboring
---   parts and merge with single space.
---
---   Before: >
---   a,b
---   aa,bb
---   aaa    ,    bbb
--- <
---   After typing `,`: >
---   a,   b
---   aa,  bb
---   aaa, bbb
--- <
--- <|> Split by "|" character, trim whitespace, merge with single space.
---
---   Before: >
---   |a|b|
---   |aa|bb|
---   |aaa    |    bbb   |
--- <
---   After typing `|`: >
---   | a   | b   |
---   | aa  | bb  |
---   | aaa | bbb |
--- <
--- <Space> (Space bar) Squash consecutive whitespace into single space (except
---   possible indentation) and split by `%s+` pattern (keeps indentation).
---
---   Before: >
---   a b c
---     aa    bb   cc
--- <
---   After typing `<Space>`: >
---     a  b  c
---     aa bb cc
--- <
---@tag MiniAlign-modifiers-builtin

--- Copy lines in modifiable buffer, initiate alignment with preview (`gAip`)
--- and try typing suggested key sequences.
--- These are modified examples taken from 'junegunn/vim-easy-align'.
---
--- # Equal sign ~
---
--- Lines: >
---
---   # This=is=assumed=to be a comment
---   "a ="
---   a =
---   a = 1
---   bbbb = 2
---   ccccccc = 3
---   ccccccccccccccc
---   ddd = 4
---   eeee === eee = eee = eee=f
---   fff = ggg += gg &&= gg
---   g != hhhhhhhh == 888
---   i   := 5
---   i     %= 5
---   i       *= 5
---   j     =~ 5
---   j   >= 5
---   aa      =>         123
---   aa <<= 123
---   aa        >>= 123
---   bbb               => 123
---   c     => 1233123
---   d   =>      123
---   dddddd &&= 123
---   dddddd ||= 123
---   dddddd /= 123
---   gg <=> ee
--- <
--- Key sequences:
--- - `=`
--- - `=jc`
--- - `=jr`
--- - `=m!<CR>`
--- - `=p`
--- - `=i` (execute `:lua vim.o.commentstring = '# %s'` for full experience)
--- - `=<BS>`
--- - `=<BS>p`
--- - `=fn==1<CR>`
--- - `=<BS>fn==1<CR>t`
--- - `=frow>7<CR>`
---@tag MiniAlign-examples

---@alias __align_with_preview boolean|nil Whether to align with live preview.

-- Module definition ==========================================================
local MiniAlign = {}
local H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniAlign.config|.
---
---@usage >lua
---   require('mini.align').setup() -- use default config
---   -- OR
---   require('mini.align').setup({}) -- replace {} with your config table
--- <
MiniAlign.setup = function(config)
  -- Export module
  _G.MiniAlign = MiniAlign

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)
end

--- Defaults ~
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text # Modifiers ~
---
--- `MiniAlign.config.modifiers` is used to define interactive user experience
--- of managing alignment process. It is a table with single character keys and
--- modifier function values.
---
--- Each modifier function:
--- - Is called when corresponding modifier key is pressed.
--- - Has signature `(steps, opts)` and should modify any of its input in place.
---
--- Examples:
--- - Modifier function used for default 'i' modifier: >lua
---
---   function(steps, _)
---     table.insert(steps.pre_split, MiniAlign.gen_step.ignore_split())
---   end
--- <
--- - Tweak 't' modifier to use highest indentation instead of keeping it: >lua
---
---   require('mini.align').setup({
---     modifiers = {
---       t = function(steps, _)
---         local trim_high = MiniAlign.gen_step.trim('both', 'high')
---         table.insert(steps.pre_justify, trim_high)
---       end
---     }
---   })
--- <
--- - Tweak `j` modifier to cycle through available "justify_side" option
---   values (like in 'junegunn/vim-easy-align'): >lua
---
---   require('mini.align').setup({
---     modifiers = {
---       j = function(_, opts)
---         local next_option = ({
---           left = 'center', center = 'right', right = 'none', none = 'left',
---         })[opts.justify_side]
---         opts.justify_side = next_option or 'left'
---       end,
---     },
---   })
--- <
--- # Options ~
---
--- `MiniAlign.config.options` defines default values of options used to control
--- behavior of steps.
---
--- Examples:
--- - Set `justify_side = 'center'` to center align at initialization.
---
--- For more details about options see |MiniAlign.align_strings()| and entries of
--- |MiniAlign.gen_step| for default main steps.
---
--- # Steps ~
---
--- `MiniAlign.config.steps` defines default steps to be applied during
--- alignment process.
---
--- Examples:
--- - Align by default only first pair of columns: >lua
---
---   local align = require('mini.align')
---   align.setup({
---     steps = {
---       pre_justify = { align.gen_step.filter('n == 1') }
---     },
---   })
--- <
MiniAlign.config = {
  -- Module mappings. Use `''` (empty string) to disable one.
  mappings = {
    start = 'ga',
    start_with_preview = 'gA',
  },

  -- Modifiers changing alignment steps and/or options
  modifiers = {
    -- Main option modifiers
    --minidoc_replace_start ['s'] = --<function: enter split pattern>,
    ['s'] = function(_, opts)
      local input = H.user_input('Enter split Lua pattern')
      if input == nil then return end
      opts.split_pattern = input
    end,
    --minidoc_replace_end
    --minidoc_replace_start ['j'] = --<function: choose justify side>,
    ['j'] = function(_, opts)
      -- stylua: ignore
      H.echo({
        { 'Select justify: ', 'ModeMsg' }, { 'l', 'Question' }, { 'eft, ' },
        { 'c', 'Question' }, { 'enter, ' }, { 'r', 'Question' }, { 'ight, ' },
        { 'n', 'Question' }, { 'one' }
      })
      local ok, char = pcall(vim.fn.getcharstr)
      if not ok or char == '\27' then return end

      local direction = ({ l = 'left', c = 'center', r = 'right', n = 'none' })[char]
      if direction == nil then return end
      opts.justify_side = direction
    end,
    --minidoc_replace_end
    --minidoc_replace_start ['m'] = --<function: enter merge delimiter>,
    ['m'] = function(_, opts)
      local input = H.user_input('Enter merge delimiter')
      if input == nil then return end
      opts.merge_delimiter = input
    end,
    --minidoc_replace_end

    -- Modifiers adding pre-steps
    --minidoc_replace_start ['f'] = --<function: filter parts by entering Lua expression>,
    ['f'] = function(steps, _)
      local input = H.user_input('Enter filter expression')
      local step = MiniAlign.gen_step.filter(input)
      if step == nil then return end
      table.insert(steps.pre_justify, step)
    end,
    --minidoc_replace_end
    --minidoc_replace_start ['i'] = --<function: ignore some split matches>,
    ['i'] = function(steps, _) table.insert(steps.pre_split, MiniAlign.gen_step.ignore_split()) end,
    --minidoc_replace_end
    --minidoc_replace_start ['p'] = --<function: pair parts>,
    ['p'] = function(steps, _) table.insert(steps.pre_justify, MiniAlign.gen_step.pair()) end,
    --minidoc_replace_end
    --minidoc_replace_start ['t'] = --<function: trim parts>,
    ['t'] = function(steps, _) table.insert(steps.pre_justify, MiniAlign.gen_step.trim()) end,
    --minidoc_replace_end

    -- Delete some last pre-step
    --minidoc_replace_start ['<BS>'] = --<function: delete some last pre-step>,
    [vim.api.nvim_replace_termcodes('<BS>', true, true, true)] = function(steps, _)
      local has_pre = {}
      for _, pre in ipairs({ 'pre_split', 'pre_justify', 'pre_merge' }) do
        if #steps[pre] > 0 then table.insert(has_pre, pre) end
      end

      if #has_pre == 0 then return end

      if #has_pre == 1 then
        local pre = steps[has_pre[1]]
        table.remove(pre, #pre)
        return
      end

      --stylua: ignore
      H.echo({
        { 'Select pre-step to remove: ', 'ModeMsg' }, { 's', 'Question' }, { 'plit, ' },
        { 'j', 'Question' }, { 'ustify, ' }, { 'm', 'Question' }, { 'erge' },
      })
      local ok, char = pcall(vim.fn.getcharstr)
      if not ok or char == '\27' then return end

      if char == 's' then table.remove(steps.pre_split, #steps.pre_split) end
      if char == 'j' then table.remove(steps.pre_justify, #steps.pre_justify) end
      if char == 'm' then table.remove(steps.pre_merge, #steps.pre_merge) end
    end,
    --minidoc_replace_end

    -- Special configurations for common splits
    --minidoc_replace_start ['='] = --<function: enhanced setup for '='>,
    ['='] = function(steps, opts)
      opts.split_pattern = '%p*=+[<>~]*'
      table.insert(steps.pre_justify, MiniAlign.gen_step.trim())
      opts.merge_delimiter = ' '
    end,
    --minidoc_replace_end
    --minidoc_replace_start [','] = --<function: enhanced setup for ','>,
    [','] = function(steps, opts)
      opts.split_pattern = ','
      table.insert(steps.pre_justify, MiniAlign.gen_step.trim())
      table.insert(steps.pre_justify, MiniAlign.gen_step.pair())
      opts.merge_delimiter = ' '
    end,
    --minidoc_replace_end
    --minidoc_replace_start ['|'] = --<function: enhanced setup for '|'>,
    ['|'] = function(steps, opts)
      opts.split_pattern = '|'
      table.insert(steps.pre_justify, MiniAlign.gen_step.trim())
      opts.merge_delimiter = ' '
    end,
    --minidoc_replace_end
    --minidoc_replace_start [' '] = --<function: enhanced setup for ' '>,
    [' '] = function(steps, opts)
      table.insert(
        steps.pre_split,
        MiniAlign.new_step('squash', function(strings)
          -- Replace all space sequences with single space (except indent)
          for i, s in ipairs(strings) do
            strings[i] = s:gsub('()(%s+)', function(n, space) return n == 1 and space or ' ' end)
          end
        end)
      )
      -- Don't use `' '` to respect indent
      opts.split_pattern = '%s+'
    end,
    --minidoc_replace_end
  },

  -- Default options controlling alignment process
  options = {
    split_pattern = '',
    justify_side = 'left',
    merge_delimiter = '',
  },

  -- Default steps performing alignment (if `nil`, default is used)
  steps = {
    pre_split = {},
    split = nil,
    pre_justify = {},
    justify = nil,
    pre_merge = {},
    merge = nil,
  },

  -- Whether to disable showing non-error feedback
  -- This also affects (purely informational) helper messages shown after
  -- idle time if user input is required.
  silent = false,
}
--minidoc_afterlines_end

-- Module functionality =======================================================
--- Align strings
---
--- For details about alignment process see |MiniAlign-algorithm|.
---
---@param strings table Array of strings.
---@param opts table|nil Options. Its copy will be passed to steps as second
---   argument. Extended with `MiniAlign.config.options`.
---   This is a place to control default main steps:
---   - `opts.split_pattern` - Lua pattern(s) used to make split parts.
---   - `opts.split_exclude_patterns` - which split matches should be ignored.
---   - `opts.justify_side` - which direction(s) alignment should be done.
---   - `opts.justify_offsets` - offsets tweaking width of first column
---   - `opts.merge_delimiter` - which delimiter(s) to use when merging.
---   For more information see |MiniAlign.gen_step| entry for corresponding
---   default step.
---@param steps table|nil Steps. Extended with `MiniAlign.config.steps`.
---   Possible `nil` values are replaced with corresponding default steps:
---   - `split` - |MiniAlign.gen_step.default_split()|.
---   - `justify` - |MiniAlign.gen_step.default_justify()|.
---   - `merge` - |MiniAlign.gen_step.default_merge()|.
MiniAlign.align_strings = function(strings, opts, steps)
  -- Validate arguments
  if not H.is_array_of(strings, H.is_string) then
    H.error('First argument of `MiniAlign.align_strings()` should be array of strings.')
  end
  opts = H.normalize_opts(opts)
  steps = H.normalize_steps(steps, 'steps')

  -- Make a copy so that modification in place doesn't affect input
  strings = vim.deepcopy(strings)

  -- Pre split
  for _, step in ipairs(steps.pre_split) do
    H.apply_step(step, strings, opts, 'pre_split')
  end

  -- Split
  local parts = H.apply_step(steps.split, strings, opts, 'split')
  if not H.is_parts(parts) then
    if H.can_be_parts(parts) then
      parts = MiniAlign.as_parts(parts)
    else
      H.error('Output of `split` step should be convertible to parts. See `:h MiniAlign.as_parts()`.')
    end
  end

  -- Pre justify
  for _, step in ipairs(steps.pre_justify) do
    H.apply_step(step, parts, opts, 'pre_justify')
  end

  -- Justify
  H.apply_step(steps.justify, parts, opts, 'justify')

  -- Pre merge
  for _, step in ipairs(steps.pre_merge) do
    H.apply_step(step, parts, opts, 'pre_merge')
  end

  -- Merge
  local new_strings = H.apply_step(steps.merge, parts, opts, 'merge')
  if not H.is_array_of(new_strings, H.is_string) then H.error('Output of `merge` step should be array of strings.') end
  return new_strings
end

--- Align current region with user-supplied steps
---
--- Mostly designed to be used inside mappings.
---
--- Will use |MiniAlign.align_strings()| and set the following options in `opts`:
--- - `justify_offsets` - array of offsets used to achieve actual alignment of
---   a region. It is non-trivial (not array of zeros) only for charwise
---   selection: offset of first string is computed as width of prefix to the
---   left of region start.
--- - `region` - current affected region (see |MiniAlign-glossary|). Can be
---   used to create more advanced steps.
--- - `mode` - mode of selection (see |MiniAlign-glossary|).
---
---@param mode string Selection mode. One of "char", "line", "block".
MiniAlign.align_user = function(mode)
  local modifiers = H.get_config().modifiers
  local with_preview = H.cache.with_preview
  local opts = H.cache.opts or H.normalize_opts()
  local steps = H.cache.steps or H.normalize_steps()

  local steps_are_from_cache = H.cache.steps ~= nil
  H.cache.region = nil

  -- Track if lines were actually changed to properly undo during preview
  local lines_were_changed = false

  -- Make initial process
  lines_were_changed = H.process_current_region(lines_were_changed, mode, opts, steps)

  -- Make early return:
  -- - If cache is present (enables dot-repeat).
  -- - If `split` is not default with no preview (no more information needed).
  if steps_are_from_cache or (not with_preview and opts.split_pattern ~= '') then return end

  -- Ask user to input modifier id until no more is needed
  local n_iter = 0
  while true do
    -- Get modifier from user
    local id = H.user_modifier(with_preview, H.make_status_msg_chunks(opts, steps))
    n_iter = n_iter + 1

    -- Stop in case user supplied inappropriate modifier id (abort)
    -- Also stop in case of too many iterations (guard from infinite cycle)
    if id == nil or n_iter > 1000 then
      if lines_were_changed then H.undo() end
      if n_iter > 1000 then H.echo({ { 'Too many modifiers typed.', 'WarningMsg' } }, true) end
      break
    end

    -- Stop preview after `<CR>` (confirmation)
    if with_preview and id == '\r' then break end

    -- Apply modifier
    local mod = modifiers[id]
    if mod == nil then
      -- Use supplied identifier as split pattern
      opts.split_pattern = vim.pesc(id)
    else
      -- Modifier should change input `steps` table in place
      local ok, out = pcall(mod, steps, opts)
      if not ok then
        -- Force message to appear for 500ms because it might be overridden by
        -- helper status message
        local msg = string.format('Modifier %s should be properly callable. Reason: %s', vim.inspect(id), out)
        H.echo({ { msg, 'WarningMsg' } }, true)
        vim.cmd('redraw')
        vim.loop.sleep(500)
      end
    end

    -- Normalize steps and options while validating their correctness
    opts = H.normalize_opts(opts)
    steps = H.normalize_steps(steps, opts)

    -- Process region while tracking if lines were set at least once
    local lines_now_changed = H.process_current_region(lines_were_changed, mode, opts, steps)
    lines_were_changed = lines_were_changed or lines_now_changed

    -- Stop in "no preview" mode right after `split` is defined
    if not with_preview and opts.split_pattern ~= '' then break end
  end

  -- Remove helper status message (if shown)
  H.unecho()
end

--- Convert 2d array of strings to parts
---
--- This function verifies if input is a proper 2d array of strings and adds
--- methods to its copy.
---
---@class parts
---
---@field apply function Takes callable `f` and applies it to every part.
---   Callable should have signature `(s, data)`: `s` is a string part,
---   `data` - table with its data (<row> has row number, <col> has column number).
---   Returns new 2d array.
---
---@field apply_inplace function Takes callable `f` and applies it to every part.
---   Should have same signature as in `apply` method. Outputs (should all be
---   strings) are assigned in place to a corresponding parts element. Returns
---   parts itself to enable method chaining.
---
---@field get_dims function Return dimensions of parts array: a table with
---   <row> and <col> keys having number of rows and number of columns (maximum
---   number of elements across all rows).
---
---@field group function Concatenate neighboring strings based on supplied
---   boolean mask and direction (one of "left", default, or "right"). Has
---   signature `(mask, direction)` and modifies parts in place. Returns parts
---   itself to enable method chaining.
---   Example:
---   - Parts: `{ { "a", "b", "c" }, { "d", "e" }, { "f" } }`
---   - Mask: `{ { false, false, true }, { true, false }, { false } }`
---   - Result for direction "left":  `{ { "abc" },    { "d", "e" }, { "f" } }`
---   - Result for direction "right": `{ { "ab","c" }, { "de" },     { "f" } }`
---
---@field pair function Concatenate neighboring element pairs. Takes
---   `direction` as input (one of "left", default, or "right") and applies
---   `group()` for an alternating mask.
---   Example:
---   - Parts: `{ { "a", "b", "c" }, { "d", "e" }, { "f" } }`
---   - Result for direction "left":  `{ { "ab", "c" }, { "de" }, { "f" } }`
---   - Result for direction "right": `{ { "a", "bc" }, { "de" }, { "f" } }`
---
---@field slice_col function Return column with input index `j`. Note: it might
---   not be an array if rows have unequal number of columns.
---
---@field slice_row function Return row with input index `i`.
---
---@field trim function Trim elements whitespace. Has signature `(direction, indent)`
---   and modifies parts in place. Returns parts itself to enable method chaining.
---   - Possible values of `direction`: "both" (default), "left", "right",
---   "none". Defines from which side whitespaces should be removed.
---   - Possible values of `indent`: "keep" (default), "low", "high", "remove".
---   Defines what to do with possible indent (left whitespace of first string
---   in a row). Value "keep" keeps it; "low" makes all indent equal to the
---   lowest across rows; "high" - highest across rows; "remove" - removes indent.
---
---@usage >lua
---   parts = MiniAlign.as_parts({ { 'a', 'b' }, { 'c' } })
---   print(vim.inspect(parts.get_dims())) -- Should be { row = 2, col = 2 }
---
---   parts.apply_inplace(function(s, data)
---     return ' ' .. data.row .. s .. data.col .. ' '
---   end)
---   print(vim.inspect(parts)) -- Should be { { ' 1a1 ', ' 1b2 ' }, { ' 2c1 ' } }
---
---   parts.trim('both', 'remove').pair()
---   print(vim.inspect(parts)) -- Should be { { '1a11b2' }, { '2c1' } }
--- <
MiniAlign.as_parts = function(arr2d)
  local ok, msg = H.can_be_parts(arr2d)
  if not ok then H.error('Input of `as_parts()` ' .. msg) end

  local parts = vim.deepcopy(arr2d)
  local methods = {}

  methods.apply = function(f)
    local res = {}
    for i, row in ipairs(parts) do
      res[i] = {}
      for j, s in ipairs(row) do
        res[i][j] = f(s, { row = i, col = j })
      end
    end
    return res
  end

  methods.apply_inplace = function(f)
    for i, row in ipairs(parts) do
      for j, s in ipairs(row) do
        local new_val = f(s, { row = i, col = j })
        if type(new_val) ~= 'string' then H.error('Input of `apply_inplace()` method should always return string.') end
        parts[i][j] = new_val
      end
    end

    return parts
  end

  methods.get_dims = function()
    local n_cols = 0
    for _, row in ipairs(parts) do
      n_cols = math.max(n_cols, #row)
    end
    return { row = #parts, col = n_cols }
  end

  -- Group cells into single string based on boolean mask.
  -- Can be used for filtering separators and sticking separator to its part.
  methods.group = function(mask, direction)
    direction = direction or 'left'
    for i, row in ipairs(parts) do
      local group_tables = H.group_by_mask(row, mask[i], direction)
      parts[i] = vim.tbl_map(table.concat, group_tables)
    end
    return parts
  end

  methods.pair = function(direction)
    direction = direction or 'left'

    local mask = {}
    for i, row in ipairs(parts) do
      mask[i] = {}
      for j, _ in ipairs(row) do
        -- Count from corresponding end
        local num = direction == 'left' and j or (#row - j + 1)
        mask[i][j] = num % 2 == 0
      end
    end

    parts.group(mask, direction)
    return parts
  end

  -- NOTE: output might not be an array (some rows can not have input column)
  -- Use `vim.tbl_keys()` and `vim.tbl_values()`
  methods.slice_col = function(j)
    return vim.tbl_map(function(row) return row[j] end, parts)
  end

  methods.slice_row = function(i) return parts[i] or {} end

  methods.trim = function(direction, indent)
    direction = direction or 'both'
    indent = indent or 'keep'

    -- Verify arguments
    local trim_fun = H.trim_functions[direction]
    if not vim.is_callable(trim_fun) then
      local allowed = vim.tbl_map(vim.inspect, vim.tbl_keys(H.trim_functions))
      table.sort(allowed)
      H.error('`direction` should be one of ' .. table.concat(allowed, ', ') .. '.')
    end

    local indent_fun = H.indent_functions[indent]
    if not vim.is_callable(indent_fun) then
      local allowed = vim.tbl_map(vim.inspect, vim.tbl_keys(H.indent_functions))
      table.sort(allowed)
      H.error('`indent` should be one of ' .. table.concat(allowed, ', ') .. '.')
    end

    -- Compute indentation to restore later
    local row_indent = vim.tbl_map(function(row) return row[1]:match('^(%s*)') end, parts)
    row_indent = indent_fun(row_indent)

    -- Trim
    parts.apply_inplace(trim_fun)

    -- Restore indentation if it was removed
    if vim.tbl_contains({ 'both', 'left' }, direction) then
      for i, row in ipairs(parts) do
        row[1] = string.format('%s%s', row_indent[i], row[1])
      end
    end

    return parts
  end

  return setmetatable(parts, { class = 'parts', __index = methods })
end

--- Create step
---
--- A step is basically a named callable object. Having a name bundled with
--- some action powers helper status message during interactive alignment process.
---
---@param name string Step name.
---@param action function|table Step action. Should be a callable object
---   (see |vim.is_callable()|).
---
---@return table A table with keys: <name> with `name` argument, <action> with `action`.
MiniAlign.new_step = function(name, action)
  if type(name) ~= 'string' then H.error('Step name should be string.') end
  if not vim.is_callable(action) then H.error('Step action should be callable.') end
  return { name = name, action = action }
end

--- Generate common action steps
---
--- This is a table with function elements. Call to actually get step.
---
--- Each step action is a function that has signature `(object, opts)`, where
--- `object` is either parts or array of strings (depends on which stage of
--- alignment process it is assumed to be applied) and `opts` is table of options.
---
--- Outputs of elements named `default_*` are used as default corresponding main
--- step (split, justify, merge). Behavior of all of them depend on values from
--- supplied options (second argument).
---
--- Outputs of other elements depend on both step generator input values and
--- options supplied at execution. This design is mostly because their output
--- can be used several times in pre-steps.
---
---@usage >lua
---   local align = require('mini.align')
---   align.setup({
---     modifiers = {
---       -- Use 'T' modifier to remove both whitespace and indent
---       T = function(steps, _)
---         table.insert(steps.pre_justify, align.gen_step.trim('both', 'remove'))
---       end,
---     },
---     options = {
---       -- By default align "right", "left", "right", "left", ...
---       justify_side = { 'right', 'left' },
---     },
---     steps = {
---       -- Align by default only first pair of columns
---       pre_justify = { align.gen_step.filter('n == 1') },
---     },
---   })
--- <
MiniAlign.gen_step = {}

--- Generate default split step
---
--- Output splits strings using matches of Lua pattern(s) from `split_pattern`
--- option which are not dismissed by `split_exclude_patterns` option.
---
--- Outline of how single string is split:
--- - Convert `split_pattern` option to array of strings (string is converted
---   as one-element array). This array will be recycled in case there are more
---   split matches than in converted `split_pattern` array (which almost always).
--- - Find all forbidden spans (intervals inside string) - all matches of all
---   patterns in `split_exclude_patterns`.
--- - Find match for the next pattern. If it is not inside any forbidden span,
---   add preceding unmatched substring and matched split as two parts. Repeat
---   with the next pattern.
--- - If no pattern match is found, add the rest of string as final part.
---
--- Output uses following options (as part second argument, `opts` table):
--- - <split_pattern> - string or array of strings used to detect split matches
---   and create parts. Default: `''` meaning no matches (whole string is used
---   as part). Examples: `'%s+'`, `{ '<', '>' }`.
--- - <split_exclude_patterns> - array of strings defining which regions to
---   exclude from being matched. Default: `{}`. Examples: `{ '".-"', '^%s*#.*' }`.
---
---@return table A step named "split" and with appropriate callable action.
---
---@seealso |MiniAlign.gen_step.ignore_split()| heavily uses `split_exclude_patterns`.
MiniAlign.gen_step.default_split = function() return MiniAlign.new_step('split', H.default_action_split) end

--- Generate default justify step
---
--- Output makes column elements of string parts have equal width by adding
--- left and/or right whitespace padding. Which side(s) to pad is defined by
--- `justify_side` option. Width of first column can be tweaked with `justify_offsets`
--- option.
---
--- Outline of how parts are justified:
--- - Convert `justify_side` option to array of strings (single string is
---   converted as one-element array). Recycle this array to have length equal
---   to number of columns in parts.
--- - For all columns compute maximum width of strings from it (add offsets from
---   `justify_offsets` to first column widths). Note: for left alignment, width
---   of last row element does not affect column width. This is mainly because
---   it won't be padded and helps dealing with "no single match" lines.
--- - Make all elements have same width inside column by adding appropriate
---   amount of whitespace. Which side(s) to add is controlled by the corresponding
---   `justify_side` array element. Note: padding is done with spaces which
---   might conflict with tab indentation.
---
--- Output uses following options (as part second argument, `opts` table):
--- - <justify_side> - string or array of strings. Each element can be one of
---   "left" (pad right side), "center" (pad both sides equally), "right" (pad
---   left side), "none" (no padding). Default: "left".
--- - <justify_offsets> - array of numeric left offsets of rows. Used to adjust
---   for possible not equal indents, like in case of charwise selection when
---   left edge is not on the first column. Default: array of zeros. Set
---   automatically during interactive alignment in charwise mode.
---
---@return table A step named "justify" and with appropriate callable action.
MiniAlign.gen_step.default_justify = function() return MiniAlign.new_step('justify', H.default_action_justify) end

--- Generate default merge step
---
--- Output merges rows of parts into strings by placing merge delimiter(s)
--- between them.
---
--- Outline of how parts are converted to array of strings:
--- - Convert `merge_delimiter` option to array of strings (single string is
---   converted as one-element array). Recycle this array to have length equal
---   to number of columns in parts minus 1. Also possibly trim leading whitespace
---   in first merge character to not affect indentation.
--- - Exclude empty strings from parts. They add nothing to output except extra
---   usage of merge delimiter.
--- - Concatenate each row interleaving with array of merge delimiters.
---
--- Output uses following options (as part second argument, `opts` table):
--- - <merge_delimiter> - string or array of strings. Default: `''`.
---   Examples: `' '`, `{ '', ' ' }`.
---
---@return table A step named "merge" and with appropriate callable action.
MiniAlign.gen_step.default_merge = function() return MiniAlign.new_step('merge', H.default_action_merge) end

--- Generate filter step
---
--- Construct function predicate from supplied Lua string expression and make
--- step evaluating it on every part element.
---
--- Outline of how filtering is done:
--- - Convert Lua filtering expression into function predicate which can be
---   evaluated in manually created context (some specific variables being set).
--- - Compute boolean mask for parts by applying predicate to each element of
---   2d array with special variables set to specific values (see next section).
--- - Group parts with computed mask. See `group()` method of parts in
---   |MiniAlign.as_parts()|.
---
--- Special variables which can be used in expression:
--- - <row> - row number of current element.
--- - <ROW> - total number of rows in parts.
--- - <col> - column number of current element.
--- - <COL> - total number of columns in current row.
--- - <s>   - string value of current element.
--- - <n>   - column pair number of current element. Useful when filtering by
---           result of pattern splitting.
--- - <N>   - total number of column pairs in current row.
--- - All variables from global table `_G`.
---
--- Tips:
--- - This general filtering approach can be used to both include and exclude
---   certain parts from alignment. Examples:
---     - Use `row ~= 2` to align all parts except from second row.
---     - Use `n == 1` to align only by first pair of columns.
--- - Filtering by last equal sign usually can be done with `n >= (N - 1)`
---   (because there is usually something to the right of it).
---
---@param expr string Lua expression as a string which will be used as predicate.
---
---@return table|nil A step named "filter" and with appropriate callable action.
MiniAlign.gen_step.filter = function(expr)
  local action = H.make_filter_action(expr)
  if action == nil then return end
  return MiniAlign.new_step('filter', action)
end

--- Generate ignore step
---
--- Output adds certain values to `split_exclude_patterns` option. Should be
--- used as pre-split step.
---
---@param patterns table Array of patterns to be added to
---   `split_exclude_patterns` as is. Default: `{ [[".-"]] }` (excludes strings
---   for most cases).
---@param exclude_comment boolean|nil Whether to add comment pattern to
---   `split_exclude_patterns`. Comment pattern is derived from 'commentstring'
---   option. Default: `true`.
---
---@return table A step named "ignore" and with appropriate callable action.
---
---@seealso |MiniAlign.gen_step.default_split()| for details about
---   `split_exclude_patterns` option.
MiniAlign.gen_step.ignore_split = function(patterns, exclude_comment)
  patterns = patterns or { '".-"' }
  if exclude_comment == nil then exclude_comment = true end

  -- Validate ingput
  if not H.is_array_of(patterns, H.is_string) then
    H.error('Argument `patterns` of `ignore_split()` should be array of strings.')
  end
  if type(exclude_comment) ~= 'boolean' then
    H.error('Argument `exclude_comment` of `ignore_split()` should be boolean.')
  end

  -- Make action which modifies `opts.split_exclude_patterns`
  local action = function(_, opts)
    local excl = opts.split_exclude_patterns or {}

    -- Add supplied patterns while avoiding duplication
    for _, patt in ipairs(patterns) do
      if not vim.tbl_contains(excl, patt) then table.insert(excl, patt) end
    end

    -- Possibly add current comment pattern while avoiding duplication
    if exclude_comment then
      -- In 'commentstring', `%s` denotes the comment content
      local comment_pattern = vim.pesc(vim.o.commentstring):gsub('%%%%s', '.-')
      -- Ignore to the end of the string if 'commentstring' is like "xxx%s"
      comment_pattern = comment_pattern:gsub('%.%-%s*$', '.*')
      if not vim.tbl_contains(excl, comment_pattern) then table.insert(excl, comment_pattern) end
    end

    opts.split_exclude_patterns = excl
  end

  return MiniAlign.new_step('ignore', action)
end

--- Generate pair step
---
--- Output calls `pair()` method of parts (see |MiniAlign.as_parts()|) with
--- supplied `direction` argument.
---
---@param direction string Which direction to pair. One of "left" (default) or
---"right".
---
---@return table A step named "pair" and with appropriate callable action.
MiniAlign.gen_step.pair = function(direction)
  return MiniAlign.new_step('pair', function(parts, _) parts.pair(direction) end)
end

--- Generate trim step
---
--- Output calls `trim()` method of parts (see |MiniAlign.as_parts()|) with
--- supplied `direction` and `indent` arguments.
---
---@param direction string|nil Which sides to trim whitespace. One of "both"
---   (default), "left", "right", "none".
---@param indent string|nil What to do with possible indent (left whitespace
---   of first string in a row). One of "keep" (default), "low", "high", "remove".
---
---@return table A step named "trim" and with appropriate callable action.
MiniAlign.gen_step.trim = function(direction, indent)
  return MiniAlign.new_step('trim', function(parts, _) parts.trim(direction, indent) end)
end

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniAlign.config)

-- Cache for various operations
H.cache = {}

-- Module's namespaces
H.ns_id = {
  -- Track user input
  input = vim.api.nvim_create_namespace('MiniAlignInput'),
}

-- Pad functions for supported justify directions
-- Allow to not add trailing whitespace
H.pad_functions = {
  left = function(x, n_spaces, no_trailing)
    if no_trailing or H.is_infinite(n_spaces) then return x end
    return string.format('%s%s', x, string.rep(' ', n_spaces))
  end,
  center = function(x, n_spaces, no_trailing)
    local n_left = math.floor(0.5 * n_spaces)
    return H.pad_functions.right(H.pad_functions.left(x, n_left, no_trailing), n_spaces - n_left, no_trailing)
  end,
  right = function(x, n_spaces, no_trailing)
    if (no_trailing and H.is_whitespace(x)) or H.is_infinite(n_spaces) then return x end
    return string.format('%s%s', string.rep(' ', n_spaces), x)
  end,
  none = function(x, _, _) return x end,
}

-- Trim functions
H.trim_functions = {
  both = function(x) return H.trim_functions.left(H.trim_functions.right(x)) end,
  left = function(x) return string.gsub(x, '^%s*', '') end,
  right = function(x) return string.gsub(x, '%s*$', '') end,
  none = function(x) return x end,
}

-- Indentation functions
H.indent_functions = {
  keep = function(indent_arr) return indent_arr end,
  high = function(indent_arr)
    local max_indent = indent_arr[1]
    for i = 2, #indent_arr do
      max_indent = (max_indent:len() < indent_arr[i]:len()) and indent_arr[i] or max_indent
    end
    return vim.tbl_map(function() return max_indent end, indent_arr)
  end,
  low = function(indent_arr)
    local min_indent = indent_arr[1]
    for i = 2, #indent_arr do
      min_indent = (indent_arr[i]:len() < min_indent:len()) and indent_arr[i] or min_indent
    end
    return vim.tbl_map(function() return min_indent end, indent_arr)
  end,
  remove = function(indent_arr)
    return vim.tbl_map(function() return '' end, indent_arr)
  end,
}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  H.check_type('mappings', config.mappings, 'table')
  H.check_type('mappings.start', config.mappings.start, 'string')
  H.check_type('mappings.start_with_preview', config.mappings.start_with_preview, 'string')

  H.check_type('modifiers', config.modifiers, 'table')
  for k, v in pairs(config.modifiers) do
    if not vim.is_callable(v) then H.error(string.format('`modifiers[%s]` should be callable.', vim.inspect(k))) end
  end

  H.validate_steps(config.steps, 'steps')
  H.check_type('options', config.options, 'table')
  H.check_type('silent', config.silent, 'boolean')

  return config
end

H.apply_config = function(config)
  MiniAlign.config = config

  --stylua: ignore start
  H.map('n', config.mappings.start, H.make_action_normal(false), { expr = true, desc = 'Align' })
  H.map('x', config.mappings.start, H.make_action_visual(false), { desc = 'Align' })

  H.map('n', config.mappings.start_with_preview, H.make_action_normal(true), { expr = true, desc = 'Align with preview' })
  H.map('x', config.mappings.start_with_preview, H.make_action_visual(true), { desc = 'Align with preview' })
  --stylua: ignore end
end

H.is_disabled = function() return vim.g.minialign_disable == true or vim.b.minialign_disable == true end

H.get_config = function()
  -- Using `tbl_deep_extend()` works even in presense of `steps.pre_*` arrays
  -- because default ones are empty.
  return vim.tbl_deep_extend('force', MiniAlign.config, vim.b.minialign_config or {})
end

-- Mappings -------------------------------------------------------------------
H.make_action_normal = function(with_preview)
  return function()
    if H.is_disabled() then return end

    H.cache = { with_preview = with_preview }

    -- Set 'operatorfunc' which will be later called with appropriate marks set
    vim.o.operatorfunc = 'v:lua.MiniAlign.align_user'
    return 'g@'
  end
end

H.make_action_visual = function(with_preview)
  return function()
    if H.is_disabled() then return end

    H.cache = { with_preview = with_preview }

    -- Perform action and exit Visual mode
    local mode = ({ ['v'] = 'char', ['V'] = 'line', ['\22'] = 'block' })[vim.fn.mode(1)]
    MiniAlign.align_user(mode)
    vim.cmd('normal! \27')
  end
end

-- Work with steps and options ------------------------------------------------
H.is_valid_steps = function(x, x_name)
  x_name = x_name or 'config.steps'

  if type(x) ~= 'table' then return false, string.format('`%s` should be table.', x_name) end

  -- Validators
  local is_steps_array = function(y) return H.is_array_of(y, H.is_step) end
  local steps_array_msg = 'should be array of steps (see `:h MiniAlign.new_step()`).'

  local is_maybe_step = function(y) return y == nil or H.is_step(y) end
  local step_msg = 'should be step (see `:h MiniAlign.new_step()`).'

  -- Actual checks
  if not is_steps_array(x.pre_split) then return false, H.msg_bad_steps(x_name, 'pre_split', steps_array_msg) end

  if not is_maybe_step(x.split) then return false, H.msg_bad_steps(x_name, 'split', step_msg) end

  if not is_steps_array(x.pre_justify) then return false, H.msg_bad_steps(x_name, 'pre_justify', steps_array_msg) end

  if not is_maybe_step(x.justify) then return false, H.msg_bad_steps(x_name, 'justify', step_msg) end

  if not is_steps_array(x.pre_merge) then return false, H.msg_bad_steps(x_name, 'pre_merge', steps_array_msg) end

  if not is_maybe_step(x.merge) then return false, H.msg_bad_steps(x_name, 'merge', step_msg) end

  return true
end

H.validate_steps = function(x, x_name)
  local is_valid, msg = H.is_valid_steps(x, x_name)
  if not is_valid then H.error(msg) end
end

H.normalize_steps = function(steps, steps_name)
  -- Infer all defaults from module config
  -- NOTE: Don't use `tbl_deep_extend` to prefer full input arrays (if present)
  local res = vim.tbl_extend('force', H.get_config().steps, steps or {})

  H.validate_steps(res, steps_name)

  -- Possibly fill in default main steps
  res.split = res.split or MiniAlign.gen_step.default_split()
  res.justify = res.justify or MiniAlign.gen_step.default_justify()
  res.merge = res.merge or MiniAlign.gen_step.default_merge()

  -- Deep copy to ensure that table values will not be affected (because if a
  -- table value is present only in one input, it is taken as is).
  return vim.deepcopy(res)
end

H.normalize_opts = function(opts)
  local res = vim.tbl_deep_extend('force', H.get_config().options, opts or {})
  return vim.deepcopy(res)
end

H.msg_bad_steps = function(steps_name, key, msg) return string.format('`%s.%s` %s', steps_name, key, msg) end

H.apply_step = function(step, arr, opts, step_container_name)
  local arr_name, predicate, suggest = 'parts', H.is_parts, ' See `:h MiniAlign.as_parts()`.'
  if not H.is_parts(arr) then
    arr_name = 'strings'
    predicate = function(x) return H.is_array_of(x, H.is_string) end
    suggest = ''
  end

  local res = step.action(arr, opts)

  if not predicate(arr) then
    --stylua: ignore
    local msg = string.format(
      'Step `%s` of `%s` should preserve structure of `%s`.%s',
      step.name, step_container_name, arr_name, suggest
    )
    H.error(msg)
  end

  return res
end

-- Work with default actions --------------------------------------------------
H.default_action_split = function(string_array, opts)
  -- Prepare options
  local pattern = opts.split_pattern
  if not (H.is_string(pattern) or H.is_array_of(pattern, H.is_string)) then
    H.error('Option `split_pattern` should be string or array of strings.')
  end
  if type(pattern) == 'string' then pattern = { pattern } end

  local exclude_patterns = opts.split_exclude_patterns or {}
  if not H.is_array_of(exclude_patterns, H.is_string) then
    H.error('Option `split_exclude_patterns` should be array of strings.')
  end

  local capture_exclude_regions = vim.tbl_map(function(x)
    local patt = x
    patt = x:sub(1, 1) == '^' and ('^()' .. patt:sub(2)) or ('()' .. patt)
    patt = x:sub(-1, -1) == '$' and (patt:sub(1, -2) .. '()$') or (patt .. '()')
    return patt
  end, exclude_patterns)

  local forbidden_spans = {}
  local add_to_forbidden = function(l, r) table.insert(forbidden_spans, { l, r - 1 }) end
  local make_forbidden_spans = function(s)
    forbidden_spans = {}
    for _, capture_pat in ipairs(capture_exclude_regions) do
      s:gsub(capture_pat, add_to_forbidden)
    end
    return forbidden_spans
  end

  -- Make splits excluding matches inside forbidden regions
  local res = vim.tbl_map(
    function(s) return H.default_action_split_string(s, pattern, make_forbidden_spans) end,
    string_array
  )
  return MiniAlign.as_parts(res)
end

H.default_action_split_string = function(s, pattern_arr, make_forbidden_spans)
  -- Construct forbidden spans for string
  local forbidden_spans = make_forbidden_spans(s)

  -- Split by recycled `pattern_arr`
  local res = {}
  local n_total, n_latest_add, n_find = s:len(), 0, 0
  local n_pair = 1

  while true do
    local cur_split = H.slice_mod(pattern_arr, n_pair)
    local sep_left, sep_right = H.string_find(s, cur_split, n_find)

    if sep_left == nil then
      -- Avoid adding empty string to non-empty input because it does nothing
      -- but confuses "don't add trailspace" logic
      local rest = s:sub(n_latest_add, n_total)
      if not (rest == '' and #res > 0) then table.insert(res, rest) end
      break
    end

    local is_good = #forbidden_spans == 0
      or not H.is_any_point_inside_any_span({ sep_left, sep_right }, forbidden_spans)
    if is_good then
      table.insert(res, s:sub(n_latest_add, sep_left - 1))
      table.insert(res, s:sub(sep_left, sep_right))
      n_latest_add = sep_right + 1
      n_pair = n_pair + 1
    end

    if (sep_right + 1) <= n_find then
      H.error(string.format('Pattern %s can not advance search.', vim.inspect(cur_split)))
    end
    n_find = sep_right + 1
  end

  return res
end

H.default_action_justify = function(parts, opts)
  -- Prepare options
  local side = opts.justify_side
  if not (H.is_justify_side(side) or H.is_array_of(side, H.is_justify_side)) then
    H.error([[Option `justify_side` should be one of 'left', 'center', 'right', 'none', or array of those.]])
  end
  if type(side) == 'string' then side = { side } end

  local offsets = opts.justify_offsets or H.tbl_repeat(0, #parts)

  -- Recycle `justify` array and precompute padding functions
  local dims = parts.get_dims()
  local pad_funs, side_arr = {}, {}
  for j = 1, dims.col do
    local s = H.slice_mod(side, j)
    side_arr[j] = s
    pad_funs[j] = H.pad_functions[s]
  end

  -- Compute cell width and maximum column widths (adjusting for offsets)
  local width_col = {}
  for j = 1, dims.col do
    width_col[j] = 0
  end

  local width = {}
  for i, row in ipairs(parts) do
    width[i] = {}
    for j, s in ipairs(row) do
      local w = vim.fn.strdisplaywidth(s)
      width[i][j] = w

      -- Compute offset
      local off = j == 1 and offsets[i] or 0

      -- Don't use last column in row to compute column width in case of left
      -- justification (it won't be padded so shouldn't contribute to column)
      if not (j == #row and side_arr[j] == 'left') then width_col[j] = math.max(off + w, width_col[j]) end
    end
  end

  -- Pad cells to have same width across columns (adjusting for offsets)
  for i, row in ipairs(parts) do
    for j, s in ipairs(row) do
      local off = j == 1 and offsets[i] or 0
      local n_space = width_col[j] - width[i][j] - off
      -- Don't add trailing whitespace for last column
      parts[i][j] = pad_funs[j](s, n_space, j == #row)
    end
  end
end

H.default_action_merge = function(parts, opts)
  -- Prepare options
  local delimiter = opts.merge_delimiter
  if not (H.is_string(delimiter) or H.is_array_of(delimiter, H.is_string)) then
    H.error('Option `merge_delimiter` should be string or array of strings.')
  end
  if type(delimiter) == 'string' then delimiter = { delimiter } end

  -- Precompute combination strings (recycle `merge` array)
  local dims = parts.get_dims()
  local delim_arr = {}
  for j = 1, dims.col - 1 do
    delim_arr[j] = H.slice_mod(delimiter, j)
  end

  -- Do not change indentation
  local first_parts_are_indent = true
  for i = 1, dims.row do
    first_parts_are_indent = first_parts_are_indent and H.is_whitespace(parts[i][1])
  end
  delim_arr[1] = (first_parts_are_indent and delim_arr[1] ~= nil) and delim_arr[1]:gsub('^%s*', '') or delim_arr[1]

  return vim.tbl_map(function(row) return H.concat_array(row, delim_arr) end, parts)
end

-- Work with modifiers --------------------------------------------------------
H.make_filter_action = function(expr)
  if expr == nil then return nil end
  if expr == '' then expr = 'true' end

  local is_loaded, f = pcall(function() return assert(loadstring('return ' .. expr)) end)
  if not (is_loaded and vim.is_callable(f)) then H.error(vim.inspect(expr) .. ' is not a valid filter expression.') end

  local predicate = function(data)
    local context = setmetatable(data, { __index = _G })
    debug.setfenv(f, context)
    return f()
  end

  return function(parts, _)
    local mask = {}
    local data = { ROW = #parts }
    for i, row in ipairs(parts) do
      data.row = i
      mask[i] = {}
      for j, s in ipairs(row) do
        data.col, data.COL = j, #row
        data.s = s

        -- Current and total number of pairs
        data.n = math.ceil(0.5 * j)
        data.N = math.ceil(0.5 * #row)

        mask[i][j] = predicate(data)
      end
    end

    parts.group(mask)
  end
end

-- Work with regions ----------------------------------------------------------
---@return boolean Whether some lines were actually set.
---@private
H.process_current_region = function(lines_were_changed, mode, opts, steps)
  -- Cache current options and steps for dot-repeat
  H.cache.opts, H.cache.steps = opts, steps

  -- Undo previously set lines
  if lines_were_changed then H.undo() end

  -- Get current region. NOTE: use cached value to ensure that the same region
  -- is processed during preview. Otherwise there might be problems with
  -- getting "current" regions in Normal mode as necessary marks (`[` and `]`)
  -- can be not valid.
  local region = H.cache.region or H.get_current_region()
  H.cache.region = region

  -- Enrich options
  opts.region = region
  opts.mode = mode
  opts.justify_offsets = H.tbl_repeat(0, region.to.line - region.from.line + 1)
  if mode == 'char' then
    -- Compute offset of first line for charwise selection
    local prefix = vim.fn.getline(region.from.line):sub(1, region.from.col - 1)
    opts.justify_offsets[1] = vim.fn.strdisplaywidth(prefix)
  end

  -- Actually process region
  local strings = H.region_get_text(region, mode)
  local strings_aligned = MiniAlign.align_strings(strings, opts, steps)
  H.region_set_text(region, mode, strings_aligned)

  -- Make sure that latest changes are shown
  vim.cmd('redraw')

  -- Confirm that lines were actually set
  return table.concat(strings) ~= table.concat(strings_aligned)
end

H.get_current_region = function()
  local from_expr, to_expr = "'[", "']"
  if H.is_visual_mode() then
    from_expr, to_expr = '.', 'v'
  end

  -- Add offset (*_pos[4]) to allow position go past end of line
  local from_pos = vim.fn.getpos(from_expr)
  local from = { line = from_pos[2], col = from_pos[3] + from_pos[4] }
  local to_pos = vim.fn.getpos(to_expr)
  local to = { line = to_pos[2], col = to_pos[3] + to_pos[4] }

  -- Ensure correct order
  if to.line < from.line or (to.line == from.line and to.col < from.col) then
    from, to = to, from
  end

  return { from = from, to = to }
end

H.region_get_text = function(region, mode)
  local from, to = region.from, region.to

  if mode == 'char' then
    local to_col_offset = vim.o.selection == 'exclusive' and 1 or 0
    return H.get_text(from.line - 1, from.col - 1, to.line - 1, to.col - to_col_offset)
  end

  if mode == 'line' then return H.get_lines(from.line - 1, to.line) end

  if mode == 'block' then
    -- Use virtual columns to respect multibyte/wide/composing characters
    local left_virtcol, right_virtcol = H.region_virtcols(region)

    local res, lines = {}, H.get_lines(from.line - 1, to.line)
    for i, l in ipairs(lines) do
      local lnum = from.line + i - 1
      local left_col = H.virtcol2col(lnum, left_virtcol)
      local right_col = H.virtcol2col(lnum, right_virtcol)
      right_col = right_col + H.str_utf_end(l, right_col)

      table.insert(res, l:sub(left_col, right_col))
    end
    return res
  end
end

H.region_set_text = function(region, mode, text)
  local from, to = region.from, region.to

  if mode == 'char' then
    -- Ensure not going past last column (can happen with `$` in Visual mode)
    local to_line_n_cols = vim.fn.col({ to.line, '$' }) - 1
    local to_col = math.min(to.col, to_line_n_cols)
    local to_col_offset = vim.o.selection == 'exclusive' and 1 or 0
    H.set_text(from.line - 1, from.col - 1, to.line - 1, to_col - to_col_offset, text)
  end

  if mode == 'line' then H.set_lines(from.line - 1, to.line, text) end

  if mode == 'block' then
    if #text ~= (to.line - from.line + 1) then
      H.error('Number of replacement lines should fit the region in blockwise mode')
    end

    -- Use virtual columns to respect multibyte characters
    local left_virtcol, right_virtcol = H.region_virtcols(region)

    local lines = H.get_lines(from.line - 1, to.line)
    for i, l in ipairs(lines) do
      local lnum = from.line + i - 1
      local left_col = H.virtcol2col(lnum, left_virtcol)
      local right_col = H.virtcol2col(lnum, right_virtcol)
      right_col = right_col + H.str_utf_end(l, right_col)

      -- Adjust columns to not go outside of line
      -- TODO: Remove after compatibility with Neovim=0.9 is dropped
      left_col, right_col = math.max(left_col - 1, 0), math.min(right_col, l:len())
      H.set_text(lnum - 1, left_col, lnum - 1, right_col, { text[i] })
    end
  end
end

H.region_virtcols = function(region)
  -- Account for multibyte characters and position past the line end
  local from_virtcol = H.pos_to_virtcol(region.from)
  local to_virtcol = H.pos_to_virtcol(region.to)

  local left_virtcol, right_virtcol = math.min(from_virtcol, to_virtcol), math.max(from_virtcol, to_virtcol)
  right_virtcol = right_virtcol - (vim.o.selection == 'exclusive' and 1 or 0)

  return left_virtcol, right_virtcol
end

H.pos_to_virtcol = function(pos)
  -- Account for position past line end
  local eol_col = vim.fn.col({ pos.line, '$' })
  if eol_col < pos.col then return vim.fn.virtcol({ pos.line, '$' }) + pos.col - eol_col end

  return vim.fn.virtcol({ pos.line, pos.col })
end

-- Work with user interaction -------------------------------------------------
H.user_modifier = function(with_preview, msg_chunks)
  -- Get from user single character modifier
  local needs_help_msg = true
  local delay = (H.cache.msg_shown or with_preview) and 0 or 1000
  vim.defer_fn(function()
    if not needs_help_msg then return end

    table.insert(msg_chunks, { ' Enter modifier' })
    H.echo(msg_chunks)
    H.cache.msg_shown = true
  end, delay)
  local ok, char = pcall(vim.fn.getcharstr)
  needs_help_msg = false

  -- Terminate if couldn't get input (like with <C-c>) or it is `<Esc>`
  if not ok or char == '\27' then return nil end
  return char
end

H.user_input = function(prompt, text)
  -- Register temporary keystroke listener to distinguish between cancel with
  -- `<Esc>` and immediate `<CR>`.
  local on_key = vim.on_key or vim.register_keystroke_callback
  local was_cancelled = false
  on_key(function(key)
    if key == '\27' then was_cancelled = true end
  end, H.ns_id.input)

  -- Ask for input
  local opts = { prompt = '(mini.align) ' .. prompt .. ': ', default = text or '' }
  vim.cmd('echohl Question')
  -- Use `pcall` to allow `<C-c>` to cancel user input
  local ok, res = pcall(vim.fn.input, opts)
  vim.cmd('echohl None | redraw')

  -- Stop key listening
  on_key(nil, H.ns_id.input)

  if not ok or was_cancelled then return end
  return res
end

H.make_status_msg_chunks = function(opts, steps)
  local single_to_string = function(pre_steps, opts_value)
    local steps_str = ''
    if #pre_steps > 0 then
      local pre_names = vim.tbl_map(function(x) return x.name end, pre_steps)
      steps_str = string.format('(%s) ', table.concat(pre_names, ', '))
    end
    return steps_str .. vim.inspect(opts_value)
  end

  return {
    { 'Split: ', 'ModeMsg' },
    { single_to_string(steps.pre_split, opts.split_pattern) },
    { ' | ', 'Question' },
    { 'Justify: ', 'ModeMsg' },
    { single_to_string(steps.pre_justify, opts.justify_side) },
    { ' | ', 'Question' },
    { 'Merge: ', 'ModeMsg' },
    { single_to_string(steps.pre_merge, opts.merge_delimiter) },
    { ' |', 'Question' },
  }
end

-- Predicates -----------------------------------------------------------------
H.is_array_of = function(x, predicate)
  if not H.islist(x) then return false end
  for _, v in ipairs(x) do
    if not predicate(v) then return false end
  end
  return true
end

H.is_step = function(x) return type(x) == 'table' and type(x.name) == 'string' and vim.is_callable(x.action) end

H.is_string = function(v) return type(v) == 'string' end

H.is_justify_side = function(x) return x == 'left' or x == 'center' or x == 'right' or x == 'none' end

H.is_parts = function(x) return H.can_be_parts(x) and (getmetatable(x) or {}).class == 'parts' end

H.can_be_parts = function(x)
  if type(x) ~= 'table' then return false, 'should be table' end
  for i = 1, #x do
    if not H.is_array_of(x[i], H.is_string) then return false, 'values should be an array of strings' end
  end
  return true
end

H.is_infinite = function(x) return x == math.huge or x == -math.huge end

H.is_visual_mode = function() return vim.tbl_contains({ 'v', 'V', '\22' }, vim.fn.mode(1)) end

H.is_whitespace = function(x) return type(x) == 'string' and x:find('^%s*$') ~= nil end

-- Work with get/set text -----------------------------------------------------
H.get_text = function(start_row, start_col, end_row, end_col)
  return vim.api.nvim_buf_get_text(0, start_row, start_col, end_row, end_col, {})
end

H.get_lines = function(start_row, end_row) return vim.api.nvim_buf_get_lines(0, start_row, end_row, true) end

--- Set text in current buffer without affecting marks
---@private
H.set_text = function(start_row, start_col, end_row, end_col, replacement)
  --stylua: ignore
  local cmd = string.format(
    'lockmarks lua vim.api.nvim_buf_set_text(0, %d, %d, %d, %d, %s)',
    start_row, start_col, end_row, end_col, vim.inspect(replacement)
  )
  vim.cmd(cmd)
end

--- Set lines in current buffer without affecting marks
---@private
H.set_lines = function(start_row, end_row, replacement)
  --stylua: ignore
  local cmd = string.format(
    'lockmarks lua vim.api.nvim_buf_set_lines(0, %d, %d, true, %s)',
    start_row, end_row, vim.inspect(replacement)
  )
  vim.cmd(cmd)
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.align) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.echo = function(msg, add_to_history)
  if H.get_config().silent then return end

  -- Construct message chunks
  msg = type(msg) == 'string' and { { msg } } or msg
  table.insert(msg, 1, { '(mini.align) ', 'WarningMsg' })

  -- Avoid hit-enter-prompt
  local max_width = vim.o.columns * math.max(vim.o.cmdheight - 1, 0) + vim.v.echospace
  local chunks, tot_width = {}, 0
  for _, ch in ipairs(msg) do
    local new_ch = { vim.fn.strcharpart(ch[1], 0, max_width - tot_width), ch[2] }
    table.insert(chunks, new_ch)
    tot_width = tot_width + vim.fn.strdisplaywidth(new_ch[1])
    if tot_width >= max_width then break end
  end

  -- Echo. Force redraw to ensure that it is effective (`:h echo-redraw`)
  vim.cmd([[echo '' | redraw]])
  vim.api.nvim_echo(chunks, add_to_history, {})
end

H.unecho = function()
  if H.cache.msg_shown then vim.cmd([[echo '' | redraw]]) end
end

H.map = function(mode, lhs, rhs, opts)
  if lhs == '' then return end
  opts = vim.tbl_deep_extend('force', { silent = true }, opts or {})
  vim.keymap.set(mode, lhs, rhs, opts)
end

H.slice_mod = function(x, i) return x[((i - 1) % #x) + 1] end

H.tbl_repeat = function(val, n)
  local res = {}
  for i = 1, n do
    res[i] = val
  end
  return res
end

H.group_by_mask = function(arr, mask, direction)
  local res, cur_group = {}, {}

  -- Construct actors based on direction
  local from, to, by = 1, #arr, 1
  local insert = function(t, v) table.insert(t, v) end
  if direction == 'right' then
    from, to, by = to, from, -1
    insert = function(t, v) table.insert(t, 1, v) end
  end

  -- Group
  for i = from, to, by do
    insert(cur_group, arr[i])
    if mask[i] or i == to then
      insert(res, cur_group)
      cur_group = {}
    end
  end

  return res
end

H.concat_array = function(target_arr, concat_arr)
  local ext_arr = {}
  for i = 1, #target_arr - 1 do
    -- Concat non-empty cells (empty cells at this point add only extra merge)
    if target_arr[i] ~= '' then
      table.insert(ext_arr, target_arr[i])
      table.insert(ext_arr, concat_arr[i])
    end
  end
  table.insert(ext_arr, target_arr[#target_arr])
  return table.concat(ext_arr, '')
end

H.string_find = function(s, pattern, init)
  init = init or 1

  -- Match only start of full string if pattern says so.
  -- This is needed because `string.find()` doesn't do this.
  -- Example: `string.find('(aaa)', '^.*$', 4)` returns `4, 5`
  if pattern:sub(1, 1) == '^' and init > 1 then return nil end

  -- Treat `''` as if nothing is found (treats it as "reset split"). If not
  -- altered, results in infinite loop.
  if pattern == '' then return nil end

  return string.find(s, pattern, init)
end

H.virtcol2col = function(lnum, col) return vim.fn.virtcol2col(0, lnum, col) end
if vim.fn.has('nvim-0.10') == 0 then
  -- Neovim<0.10 has `virtcol2col` returning cell's last column instead of
  -- cell's first column in Neovim>=0.10
  H.virtcol2col = function(lnum, col)
    if vim.fn.virtcol2col(0, lnum, col) == 0 then return 0 end
    return vim.fn.virtcol2col(0, lnum, col - 1) + 1
  end
end

H.str_utfindex = function(s, i) return vim.str_utfindex(s, 'utf-32', i) end
if vim.fn.has('nvim-0.11') == 0 then H.str_utfindex = function(s, i) return (vim.str_utfindex(s, i)) end end

H.str_utf_end = function(s, n) return n >= s:len() and 0 or vim.str_utf_end(s, n) end
if vim.fn.has('nvim-0.10') == 0 then
  H.str_utf_end = function(s, n) return n >= s:len() and 0 or (vim.str_byteindex(s, H.str_utfindex(s, n)) - n) end
end

H.is_any_point_inside_any_span = function(points, spans)
  for _, point in ipairs(points) do
    for _, span in ipairs(spans) do
      if span[1] <= point and point <= span[2] then return true end
    end
  end
  return false
end

H.undo = function()
  if H.is_visual_mode() then
    -- Can't use `u` in Visual mode because it makes all selection lowercase
    local cur_mode = vim.fn.mode(1)
    vim.cmd('silent! normal! \27')

    -- Undo
    vim.cmd('silent! lockmarks undo')

    -- Manually restore selection. There are issues with using restoring marks
    -- via `gv` (couldn't figure out how to reliably preserve visual mode).
    -- As this is called only if lines were set, region is cached.
    local region = H.cache.region
    vim.api.nvim_win_set_cursor(0, { region.from.line, region.from.col - 1 })
    vim.cmd('silent! normal!' .. cur_mode)
    vim.api.nvim_win_set_cursor(0, { region.to.line, region.to.col - 1 })
  else
    vim.cmd('silent! lockmarks normal! u')
  end
end

-- TODO: Remove after compatibility with Neovim=0.9 is dropped
H.islist = vim.fn.has('nvim-0.10') == 1 and vim.islist or vim.tbl_islist

return MiniAlign
