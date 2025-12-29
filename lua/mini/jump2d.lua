--- *mini.jump2d* Jump within visible lines
---
--- MIT License Copyright (c) 2022 Evgeni Chasnovski

--- Jump within visible lines via iterative label filtering.
---
--- Features:
--- - Make jump by iterative filtering of possible, equally considered jump
---   spots until there is only one. Filtering is done by typing a label
---   character that is visualized at jump spot.
---
--- - Customizable (see |MiniJump2d.config|):
---     - Way of computing possible jump spots with opinionated default.
---     - Characters used to label jump spots during iterative filtering.
---     - Visual effects: how many steps ahead to show; dim lines with spots.
---     - Action hooks to be executed at certain events during jump.
---     - Allowed windows: current and/or not current.
---     - Allowed lines: whether to process blank or folded lines, lines
---       before/at/after cursor line, etc. Example: user can configure to look
---       for spots only inside current window at or after cursor line.
---     Example: user can configure to look for word starts only inside current
---     window at or after cursor line with 'j' and 'k' labels performing some
---     action after jump.
---
--- - Works in Visual and Operator-pending (with dot-repeat) modes.
---
--- - Preconfigured ways of computing jump spots (see |MiniJump2d.builtin_opts|):
---     - Starts of lines.
---     - Starts of words.
---     - Single character from user input.
---     - Variable length query from user input.
---
--- - Works with multibyte characters.
---
--- General overview of how jump is intended to be performed:
--- - Lock eyes on desired location ("spot") recognizable by future jump.
---   Should be within visible lines at place where cursor can be placed.
---
--- - Initiate jump. Either by custom keybinding or with a call to
---   |MiniJump2d.start()| (allows customization options). This will highlight
---   all possible jump spots with their labels (letters from "a" to "z" by
---   default). For more details, read |MiniJump2d.start()| and |MiniJump2d.config|.
---
--- - Type character that appeared over desired location. If its label was
---   unique, jump is performed. If it wasn't unique, possible jump spots are
---   filtered to those having the same label character.
---
--- - Repeat previous step until there is only one possible jump spot or type <CR>
---   to jump to first available jump spot. Typing anything else stops jumping
---    without moving cursor.
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.jump2d').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table
--- `MiniJump2d` which you can use for scripting or manually (with
--- `:lua MiniJump2d.*`).
---
--- See |MiniJump2d.config| for available config settings.
---
--- You can override runtime config settings locally to buffer inside
--- `vim.b.minijump2d_config` which should have same structure as
--- `MiniJump2d.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- To stop module from showing non-error feedback, set `config.silent = true`.
---
--- # Example usage ~
---
--- - Modify default jumping to use only current window at or after cursor line: >lua
---
---   require('mini.jump2d').setup({
---     allowed_lines = { cursor_before = false },
---     allowed_windows = { not_current = false },
---   })
--- <
--- - Jump to line start using combination of options supplied in
---   |MiniJump2d.config| and |MiniJump2d.builtin_opts.line_start|: >vim
---
---   :lua MiniJump2d.start(MiniJump2d.builtin_opts.line_start)
--- <
--- - Jump to a single character typed after executing this command: >vim
---
---   :lua MiniJump2d.start(MiniJump2d.builtin_opts.single_character)
--- <
--- - See more examples in |MiniJump2d.start()| and |MiniJump2d.builtin_opts|.
---
--- # Comparisons ~
---
--- - [phaazon/hop.nvim](https://github.com/phaazon/hop.nvim):
---     - Both are fast, customizable, and extensible (user can write their own
---       ways to define jump spots).
---     - 'hop.nvim' visualizes all steps at once. While this module can show
---       configurable number of steps ahead.
---     - Both have several builtin ways to specify type of jump (word start,
---       line start, one character or query based on user input). 'hop.nvim'
---       does that by exporting many targeted Neovim commands, while this
---       module has preconfigured basic options leaving others to
---       customization with Lua code (see |MiniJump2d.builtin_opts|).
---     - 'hop.nvim' computes labels (called "hints") differently. Contrary to
---       this module deliberately not having preference of one jump spot over
---       another, 'hop.nvim' uses specialized algorithm that produces sequence
---       of keys in a slightly biased manner: some sequences are intentionally
---       shorter than the others (leading to fewer average keystrokes). They
---       are put near cursor (by default) and highlighted differently. Final
---       order of sequences is based on distance to the cursor.
---     - 'mini.jump2d' has opinionated default algorithm of computing jump
---       spots. See |MiniJump2d.default_spotter()|.
---
--- # Highlight groups ~
---
--- - `MiniJump2dSpot` - highlighting of jump spot's next step. By default it
---   uses label with highest contrast while not being too visually demanding:
---   white on black for dark 'background', black on white for light. If it
---   doesn't suit your liking, try couple of these alternatives (or choose
---   your own, of course): >lua
---
---     -- Reverse underlying colors (mostly *very* visible in any colorscheme)
---     vim.api.nvim_set_hl(0, 'MiniJump2dSpot', { reverse = true })
---
---     -- Bold italic
---     vim.api.nvim_set_hl(0, 'MiniJump2dSpot', { bold = true, italic = true })
---
---     -- Red undercurl
---     vim.api.nvim_set_hl(0, 'MiniJump2dSpot', { sp = 'Red', undercurl = true })
--- <
--- - `MiniJump2dSpotUnique` - highlighting of jump spot's next step if it has
---   unique label. By default links to `MiniJump2dSpot`.
---
--- - `MiniJump2dSpotAhead` - highlighting of jump spot's future steps. By default
---   similar to `MiniJump2dSpot` but with less contrast and visibility.
---
--- - `MiniJump2dDim` - highlighting of lines with at least one jump spot.
---   Make it non-bright in order for jump spot labels to be more visible.
---   By default linked to `Comment` highlight group.
---
--- To change any highlight group, set it directly with |nvim_set_hl()|.
---
--- # Disabling ~
---
--- To disable, set `vim.g.minijump2d_disable` (globally) or
--- `vim.b.minijump2d_disable` (for a buffer) to `true`. Considering high
--- number of different scenarios and customization intentions, writing exact
--- rules for disabling module's functionality is left to user. See
--- |mini.nvim-disabling-recipes| for common recipes.
---@tag MiniJump2d

-- Module definition ==========================================================
local MiniJump2d = {}
local H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniJump2d.config|.
---
---@usage >lua
---   require('mini.jump2d').setup() -- use default config
---   -- OR
---   require('mini.jump2d').setup({}) -- replace {} with your config table
--- <
MiniJump2d.setup = function(config)
  -- Export module
  _G.MiniJump2d = MiniJump2d

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
---@text # Spotter function ~
---
--- Actual computation of possible jump spots is done through spotter function.
--- It should have the following arguments:
--- - `line_num` is a line number inside buffer.
--- - `args` - table with additional arguments:
---     - {win_id} - identifier of a window where input line number is from.
---     - {win_id_init} - identifier of a window which was current when
---       `MiniJump2d.start()` was called.
---
--- Its output is a list of byte-indexed positions that should be considered as
--- possible jump spots for this particular line in this particular window.
--- Note: for a more aligned visualization this list should be (but not
--- strictly necessary) sorted increasingly.
---
--- Note: spotter function is always called with `win_id` window being
--- "temporary current" (see |nvim_win_call()|). This allows using builtin
--- Vimscript functions that operate only inside current window.
---
--- # View ~
---
--- Option `view.n_steps_ahead` controls how many steps ahead to show along
--- with the currently required label. Those future steps are shown with
--- different (less visible) highlight group ("MiniJump2dSpotAhead"). Usually
--- it is a good idea to use this with a spotter which doesn't result into many
--- jump spots (like, for example, |MiniJump2d.builtin_opts.word_start|).
--- Default is 0 to not show anything ahead as it reduces visual noise.
---
--- Option `view.dim` controls whether to dim lines with at least one jump spot.
--- Dimming is done by applying "MiniJump2dDim" highlight group to the whole line.
---
--- # Allowed lines ~
---
--- Option `allowed_lines` controls which lines will be used for computing
--- possible jump spots:
--- - If `blank` or `fold` is `true`, it is possible to jump to first column of blank
---   line (determined by |prevnonblank()|) or first folded one (determined by
---   |foldclosed()|) respectively. Otherwise they are skipped. These lines are
---   not processed by spotter function even if the option is `true`.
--- - If `cursor_before`, (`cursor_at`, `cursor_after`) is `true`, lines before
---   (at, after) cursor line of all processed windows are forwarded to spotter
---   function. Otherwise, they don't. This allows control of jump "direction".
---
--- # Hooks ~
---
--- Following hook functions can be used to further tweak jumping experience:
--- - `before_start` - called without arguments first thing when jump starts.
---   One of the possible use cases is to ask for user input and update spotter
---   function with it.
--- - `after_jump` - called after jump was actually done. Useful to make
---   post-adjustments (like move cursor to first non-whitespace character).
MiniJump2d.config = {
  -- Function producing jump spots (byte indexed) for a particular line.
  -- For more information see |MiniJump2d.start()|.
  -- If `nil` (default) - use |MiniJump2d.default_spotter()|
  spotter = nil,

  -- Characters used for labels of jump spots (in supplied order)
  labels = 'abcdefghijklmnopqrstuvwxyz',

  -- Options for visual effects
  view = {
    -- Whether to dim lines with at least one jump spot
    dim = false,

    -- How many steps ahead to show. Set to big number to show all steps.
    n_steps_ahead = 0,
  },

  -- Which lines are used for computing spots
  allowed_lines = {
    blank = true, -- Blank line (not sent to spotter even if `true`)
    cursor_before = true, -- Lines before cursor line
    cursor_at = true, -- Cursor line
    cursor_after = true, -- Lines after cursor line
    fold = true, -- Start of fold (not sent to spotter even if `true`)
  },

  -- Which windows from current tabpage are used for visible lines
  allowed_windows = {
    current = true,
    not_current = true,
  },

  -- Functions to be executed at certain events
  hooks = {
    before_start = nil, -- Before jump start
    after_jump = nil, -- After jump was actually done
  },

  -- Module mappings. Use `''` (empty string) to disable one.
  mappings = {
    start_jumping = '<CR>',
  },

  -- Whether to disable showing non-error feedback
  -- This also affects (purely informational) helper messages shown after
  -- idle time if user input is required.
  silent = false,
}
--minidoc_afterlines_end

-- Module functionality =======================================================
--- Start jumping
---
--- Compute possible jump spots, visualize them and wait for iterative filtering.
---
--- # First computation of possible jump spots ~
---
--- - Process allowed windows (current and/or not current; controlled by
---   `allowed_windows` option) by visible lines from top to bottom. For each
---   one see if it is allowed (controlled by `allowed_lines` option). If not
---   allowed, then do nothing. If allowed and should be processed by
---   `spotter`, process it.
--- - Apply spotter function from `spotter` option for each appropriate line
---   and concatenate outputs. This means that eventual order of jump spots
---   aligns with lexicographical order within "window id" - "line number" -
---   "position in `spotter` output" tuples.
--- - For each possible jump compute its label: a single character from
---   `labels` option used to filter jump spots. Each possible label character
---   might be used more than once to label several "consecutive" jump spots.
---   It is done in an optimal way under assumption of no preference of one
---   spot over another. Basically, it means "use all labels at each step of
---   iterative filtering as equally as possible".
---
--- # Visualization ~
---
--- Current label for each possible jump spot is shown at that position
--- overriding everything underneath it.
---
--- # Iterative filtering ~
---
--- Labels of possible jump spots are computed in order to use them as equally
--- as possible.
---
--- Example:
--- - With `abc` as `labels` option, initial labels for 10 possible jumps
---   are "aaaabbbccc". As there are 10 spots which should be "coded" with 3
---   symbols, at least 2 symbols need 3 steps to filter them out. With current
---   implementation those are always the "first ones".
--- - After typing `a`, it filters first four jump spots and recomputes its
---   labels to be "aabc".
--- - After typing `a` again, it filters first two spots and recomputes its
---   labels to be "ab".
--- - After typing either `a` or `b` it filters single spot and makes jump.
---
--- With default 26 labels for most real-world cases 2 steps is enough for
--- default spotter function. Rarely 3 steps are needed with several windows.
---
---@param opts table|nil Configuration of jumping, overriding global and buffer
---   local values. Has the same structure as |MiniJump2d.config|
---   without <mappings> field. Extra allowed fields:
---   - <hl_group> - highlight group for first step.
---     Default: `"MiniJump2dSpot"`.
---   - <hl_group_ahead> - highlight group for second and later steps.
---     Default: `"MiniJump2dSpotAhead"`.
---   - <hl_group_dim> - highlight group for dimming used lines.
---     Default: `"MiniJump2dDim"`.
---   - <hl_group_unique> - highlight group for unique next step.
---     Default: `"MiniJump2dSpotUnique"`.
---
---@usage >lua
---   -- Start default jumping
---   MiniJump2d.start()
---
---   -- Jump to word start
---   MiniJump2d.start(MiniJump2d.builtin_opts.word_start)
---
---   -- Jump to single character from user input (follow by typing one character)
---   MiniJump2d.start(MiniJump2d.builtin_opts.single_character)
---
---   -- Jump to first character of punctuation group only inside current window
---   -- which is placed at cursor line; visualize with `Search`
---   MiniJump2d.start({
---     spotter = MiniJump2d.gen_spotter.pattern('%p+'),
---     allowed_lines = { cursor_before = false, cursor_after = false },
---     allowed_windows = { not_current = false },
---     hl_group = 'Search'
---   })
--- <
---@seealso |MiniJump2d.config|
MiniJump2d.start = function(opts)
  if H.is_disabled() then return end

  opts = opts or {}

  -- Apply `before_start` before `tbl_deep_extend` to allow it modify options
  -- inside it (notably `spotter`). Example: `builtins.single_character`.
  local before_start = (opts.hooks or {}).before_start
    or ((vim.b.minijump2d_config or {}).hooks or {}).before_start
    or MiniJump2d.config.hooks.before_start
  if before_start ~= nil then before_start() end

  opts = H.get_config(opts)
  opts.spotter = opts.spotter or MiniJump2d.default_spotter
  opts.hl_group = opts.hl_group or 'MiniJump2dSpot'
  opts.hl_group_ahead = opts.hl_group_ahead or 'MiniJump2dSpotAhead'
  opts.hl_group_unique = opts.hl_group_unique or 'MiniJump2dSpotUnique'
  opts.hl_group_dim = opts.hl_group_dim or 'MiniJump2dDim'

  local spots = H.spots_compute(opts)
  if #spots == 0 then
    H.message('No spots to show.')
    return
  end
  if #spots == 1 then
    H.perform_jump(spots[1], opts.hooks.after_jump)
    return
  end

  local label_tbl = vim.split(opts.labels, '')
  spots = H.spots_add_steps(spots, label_tbl, opts.view.n_steps_ahead)

  H.spots_show(spots, opts)

  H.cache.spots = spots

  H.advance_jump(opts)
end

--- Stop jumping
MiniJump2d.stop = function()
  H.spots_unshow()
  H.cache.spots = nil
  H.cache.msg_shown = false
  vim.cmd('redraw')

  if H.cache.is_in_getcharstr then vim.api.nvim_input('<C-c>') end
end

--- Generate spotter
---
--- This is a table with function elements. Call to actually get a spotter.
MiniJump2d.gen_spotter = {}

--- Generate spotter for Lua pattern
---
---@param pattern string|nil Lua pattern. Default: `'[^%s%p]+'` which matches group
---   of "non-whitespace non-punctuation characters" (basically a way of saying
---   "group of alphanumeric characters" that works with multibyte characters).
---@param side string|nil Which side of pattern match should be considered as
---   jumping spot. Should be one of 'start' (start of match, default), 'end'
---   (inclusive end of match), or 'none' (match for spot is done manually
---   inside pattern with plain `()` matching group).
---
---@return function Spotter function.
---
---@usage >lua
---   -- Match any punctuation
---   MiniJump2d.gen_spotter.pattern('%p')
---
---   -- Match first from line start non-whitespace character
---   MiniJump2d.gen_spotter.pattern('^%s*%S', 'end')
---
---   -- Match start of last word
---   MiniJump2d.gen_spotter.pattern('[^%s%p]+[%s%p]-$', 'start')
---
---   -- Match letter followed by another letter (example of manual matching
---   -- inside pattern)
---   MiniJump2d.gen_spotter.pattern('%a()%a', 'none')
--- <
MiniJump2d.gen_spotter.pattern = function(pattern, side)
  -- Don't use `%w` to account for multibyte characters
  pattern = pattern or '[^%s%p]+'
  side = side or 'start'

  -- Process anchored patterns separately because:
  -- - `gmatch()` doesn't work if pattern start with `^`.
  -- - Manual adding of `()` will conflict with anchors.
  local is_anchored = pattern:sub(1, 1) == '^' or pattern:sub(-1, -1) == '$'
  if is_anchored then
    return function(line_num, args)
      local line = vim.fn.getline(line_num)
      local s, e, m = line:find(pattern)
      return { ({ ['start'] = s, ['end'] = e, ['none'] = m })[side] }
    end
  end

  -- Handle `side = 'end'` later by appending length of match to match start.
  -- This, unlike appending `()` to end of pattern, makes output spot to be
  -- inside matched pattern and on its exact right.
  -- Having `(%s)` for `side = 'none'` is for compatibility with later `gmatch`
  local pattern_template = side == 'none' and '(%s)' or '(()%s)'
  pattern = pattern_template:format(pattern)

  return function(line_num, args)
    local line = vim.fn.getline(line_num)
    local res = {}
    -- NOTE: maybe a more straightforward approach would be a series of
    -- `line:find(original_pattern, init)` with moving `init`, but it has some
    -- weird behavior with quantifiers.
    -- For example: `string.find('  --', '%s*', 4)` returns `4 3`.
    for whole, spot in string.gmatch(line, pattern) do
      -- Possibly correct spot to be index of last matched position
      if side == 'end' then spot = spot + math.max(whole:len() - 1, 0) end

      -- Ensure that index is strictly within line length (which can be not
      -- true in case of weird pattern, like when using frontier `%f[%W]`)
      spot = math.min(math.max(spot, 0), line:len())

      -- Unify how spot is chosen in case of multibyte characters
      -- Use `+-1` to make sure that result is at start of multibyte character
      local utf_index = H.str_utfindex(line, spot) - 1
      spot = H.str_byteindex(line, utf_index) + 1

      -- Add spot only if it referces new actually visible column
      if spot ~= res[#res] then table.insert(res, spot) end
    end
    return res
  end
end

-- TODO: Remove after releasing 'mini.nvim' 0.17.0
MiniJump2d.gen_pattern_spotter = function(pattern, side)
  local msg = '`gen_pattern_spotter` is moved to `gen_spotter.pattern` for consistency with other modules.'
    .. ' It still works for now, but will stop working after the next release.'
    .. ' Sorry for the inconvenience.'
  H.notify(msg, 'WARN')
  return MiniJump2d.gen_spotter.pattern(pattern, side)
end

--- Generate spotter for Vimscript pattern
---
---@param pattern string|nil Vimscript |pattern|. Default: `\k\+` to match group
---   of "keyword characters" (see 'iskeyword').
---
---@return function Spotter function.
---
---@usage >lua
---   -- Match start of a keyword
---   MiniJump2d.gen_spotter.vimpattern('\\k\\+')
---
---   -- Match end of a keyword
---   MiniJump2d.gen_spotter.vimpattern('\\k*\\zs\\k')
--- <
MiniJump2d.gen_spotter.vimpattern = function(pattern)
  pattern = pattern or '\\k\\+'
  if type(pattern) ~= 'string' then H.error('`pattern` should be string') end
  local r = vim.regex(pattern)
  local is_anchored = pattern:sub(1, 1) == '^' or pattern:sub(-1, -1) == '$'

  return function(line_num, _)
    local res, l, start = {}, vim.fn.getline(line_num), 1
    local n = is_anchored and 1 or (l:len() + 1)
    for _ = 1, n do
      local from, to = r:match_str(l)
      if from == nil then break end
      table.insert(res, from + start)
      l, start = l:sub(to + 1), start + to
    end
    return res
  end
end

--- Generate union of spotters
---
---@param ... any Each argument should be a valid spotter.
---   See |MiniJump2d.config| for more details.
---
---@return function Spotter producing union of spots.
---
---@usage >lua
---   -- Match start and end of non-blank character groups:
---   local nonblank_start = MiniJump2d.gen_spotter.pattern('%S+', 'start')
---   local nonblank_end = MiniJump2d.gen_spotter.pattern('%S+', 'end')
---   local spotter = MiniJump2d.gen_spotter.union(nonblank_start, nonblank_end)
--- <
MiniJump2d.gen_spotter.union = function(...)
  local spotters = { ... }
  if #spotters == 0 then
    return function() return {} end
  end

  local is_all_callable = true
  for _, x in ipairs(spotters) do
    if not vim.is_callable(x) then is_all_callable = false end
  end

  if not is_all_callable then H.error('All `gen_spotter.union()` arguments should be callable elements.') end

  return function(line_num, args)
    local res = spotters[1](line_num, args)
    for i = 2, #spotters do
      res = H.merge_unique(res, spotters[i](line_num, args))
    end
    return res
  end
end

-- TODO: Remove after releasing 'mini.nvim' 0.17.0
MiniJump2d.gen_union_spotter = function(...)
  local msg = '`gen_union_spotter` is moved to `gen_spotter.union` for consistency with other modules.'
    .. ' It still works for now, but will stop working after the next release.'
    .. ' Sorry for the inconvenience.'
  H.notify(msg, 'WARN')
  return MiniJump2d.gen_spotter.union(...)
end

--- Default spotter function
---
--- Spot is possible for jump if it is one of the following:
--- - Start or end of non-whitespace character group.
--- - Alphanumeric character followed or preceded by punctuation (useful for
---   snake case names).
--- - Start of uppercase character group (useful for camel case names). Usually
---   only Latin alphabet is recognized due to Lua patterns shortcomings.
---
--- These rules are derived in an attempt to balance between two intentions:
--- - Allow as much useful jumping spots as possible.
--- - Make labeled jump spots easily distinguishable.
---
--- Usually takes from 2 to 3 keystrokes to get to destination.
---@tag MiniJump2d.default_spotter()
MiniJump2d.default_spotter = (function()
  -- NOTE: not using `MiniJump2d.gen_spotter.union()` due to slightly better
  -- algorithmic complexity merging small arrays first.
  local nonblank_start = MiniJump2d.gen_spotter.pattern('%S+', 'start')
  local nonblank_end = MiniJump2d.gen_spotter.pattern('%S+', 'end')
  -- Use `[^%s%p]` as "alphanumeric" to allow working with multibyte characters
  local alphanum_before_punct = MiniJump2d.gen_spotter.pattern('[^%s%p]%p', 'start')
  local alphanum_after_punct = MiniJump2d.gen_spotter.pattern('%p[^%s%p]', 'end')
  -- NOTE: works only with Latin alphabet
  local upper_start = MiniJump2d.gen_spotter.pattern('%u+', 'start')

  return function(line_num, args)
    local res_1 = H.merge_unique(nonblank_start(line_num, args), nonblank_end(line_num, args))
    local res_2 = H.merge_unique(alphanum_before_punct(line_num, args), alphanum_after_punct(line_num, args))
    local res = H.merge_unique(res_1, res_2)
    return H.merge_unique(res, upper_start(line_num, args))
  end
end)()

--- Table with builtin `opts` values for |MiniJump2d.start()|
---
--- Each element of table is itself a table defining one or several options for
--- `MiniJump2d.start()`. Read help description to see which options it defines
--- (like in |MiniJump2d.builtin_opts.line_start|).
---
---@usage >lua
---   -- Using `MiniJump2d.builtin_opts.line_start` as example:
---   -- Command
---   :lua MiniJump2d.start(MiniJump2d.builtin_opts.line_start)
---
---   -- Custom mapping
---   vim.keymap.set(
---     'n', '<CR>',
---     '<Cmd>lua MiniJump2d.start(MiniJump2d.builtin_opts.line_start)<CR>'
---   )
---
---   -- Inside `MiniJump2d.setup()` (make sure to use all defined options)
---   local jump2d = require('mini.jump2d')
---   local jump_line_start = jump2d.builtin_opts.line_start
---   jump2d.setup({
---     spotter = jump_line_start.spotter,
---     hooks = { after_jump = jump_line_start.hooks.after_jump }
---   })
--- <
MiniJump2d.builtin_opts = {}

--- Jump with |MiniJump2d.default_spotter()|
---
--- Defines `spotter`.
MiniJump2d.builtin_opts.default = { spotter = MiniJump2d.default_spotter }

--- Jump to line start
---
--- Defines `spotter` and `hooks.after_jump`.
MiniJump2d.builtin_opts.line_start = {
  spotter = function(line_num, args) return { 1 } end,
  hooks = {
    after_jump = function()
      -- Move to first non-blank character
      vim.cmd('normal! ^')
    end,
  },
}

--- Jump to word start
---
--- Respects 'iskeyword' when computing word start.
---
--- Defines `spotter`.
MiniJump2d.builtin_opts.word_start = { spotter = MiniJump2d.gen_spotter.vimpattern('\\k\\+') }

-- Produce `opts` which modifies spotter based on user input
local function user_input_opts(input_fun)
  local res = {
    spotter = function() return {} end,
    allowed_lines = { blank = false, fold = false },
  }

  local before_start = function()
    local input = input_fun()
    -- Allow user to cancel input and not show any jumping spots
    if input == nil then return end
    res.spotter = MiniJump2d.gen_spotter.pattern(vim.pesc(input))
  end
  res.hooks = { before_start = before_start }

  return res
end

--- Jump to single character taken from user input
---
--- Defines `spotter`, `allowed_lines.blank`, `allowed_lines.fold`, and
--- `hooks.before_start`.
MiniJump2d.builtin_opts.single_character = user_input_opts(
  function() return H.getcharstr('Enter single character to search') end
)

--- Jump to query taken from user input
---
--- Defines `spotter`, `allowed_lines.blank`, `allowed_lines.fold`, and
--- `hooks.before_start`.
MiniJump2d.builtin_opts.query = user_input_opts(function() return H.input('Enter query to search') end)

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniJump2d.config)

-- Namespaces to be used within module
H.ns_id = {
  dim = vim.api.nvim_create_namespace('MiniJump2dDim'),
  spots = vim.api.nvim_create_namespace('MiniJump2dSpots'),
  input = vim.api.nvim_create_namespace('MiniJump2dInput'),
}

-- Table with current relevant data:
H.cache = {
  -- Array of shown spots
  spots = nil,

  -- Indicator of whether Neovim is currently in "getcharstr" mode
  is_in_getcharstr = false,

  -- Whether helper message was shown
  msg_shown = false,
}

-- Table with special keys
H.keys = {
  esc = vim.api.nvim_replace_termcodes('<Esc>', true, true, true),
  cr = vim.api.nvim_replace_termcodes('<CR>', true, true, true),
  block_operator_pending = vim.api.nvim_replace_termcodes('no<C-V>', true, true, true),
}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  H.check_type('spotter', config.spotter, 'function', true)
  H.check_type('labels', config.labels, 'string')

  H.check_type('view', config.view, 'table')
  H.check_type('view.dim', config.view.dim, 'boolean')
  H.check_type('view.n_steps_ahead', config.view.n_steps_ahead, 'number')

  H.check_type('allowed_lines', config.allowed_lines, 'table')
  H.check_type('allowed_lines.blank', config.allowed_lines.blank, 'boolean')
  H.check_type('allowed_lines.cursor_before', config.allowed_lines.cursor_before, 'boolean')
  H.check_type('allowed_lines.cursor_at', config.allowed_lines.cursor_at, 'boolean')
  H.check_type('allowed_lines.cursor_after', config.allowed_lines.cursor_after, 'boolean')
  H.check_type('allowed_lines.fold', config.allowed_lines.fold, 'boolean')

  H.check_type('allowed_windows', config.allowed_windows, 'table')
  H.check_type('allowed_windows.current', config.allowed_windows.current, 'boolean')
  H.check_type('allowed_windows.not_current', config.allowed_windows.not_current, 'boolean')

  H.check_type('hooks', config.hooks, 'table')
  H.check_type('hooks.before_start', config.hooks.before_start, 'function', true)
  H.check_type('hooks.after_jump', config.hooks.after_jump, 'function', true)

  H.check_type('mappings', config.mappings, 'table')
  H.check_type('mappings.start_jumping', config.mappings.start_jumping, 'string')

  H.check_type('silent', config.silent, 'boolean')

  return config
end

H.apply_config = function(config)
  MiniJump2d.config = config

  -- Apply mappings
  local keymap = config.mappings.start_jumping
  H.map('n', keymap, MiniJump2d.start, { desc = 'Start 2d jumping' })
  H.map('x', keymap, MiniJump2d.start, { desc = 'Start 2d jumping' })
  -- Use `<Cmd>...<CR>` to have proper dot-repeat
  -- See https://github.com/neovim/neovim/issues/23406
  -- TODO: use local functions if/when that issue is resolved
  H.map('o', keymap, '<Cmd>lua MiniJump2d.start()<CR>', { desc = 'Start 2d jumping' })
end

H.create_autocommands = function(config)
  local gr = vim.api.nvim_create_augroup('MiniJump2d', {})

  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { pattern = pattern, group = gr, callback = callback, desc = desc })
  end

  -- Corrections for default `<CR>` mapping to not interfere with popular usages
  if config.mappings.start_jumping == '<CR>' then
    local revert_cr = function() vim.keymap.set('n', '<CR>', '<CR>', { buffer = true }) end
    au('FileType', 'qf', revert_cr, 'Revert <CR>')
    au('CmdwinEnter', '*', revert_cr, 'Revert <CR>')
  end

  au('ColorScheme', '*', H.create_default_hl, 'Ensure colors')
end

--stylua: ignore
H.create_default_hl = function()
  local set_default_hl = function(name, data)
    data.default = true
    vim.api.nvim_set_hl(0, name, data)
  end

  local is_light_bg = vim.o.background == 'light'
  local bg_color = is_light_bg and 'white' or 'black'
  local fg_color = is_light_bg and 'black' or 'white'

  set_default_hl('MiniJump2dSpot',       { fg = fg_color, bg = bg_color, bold = true, nocombine = true })
  set_default_hl('MiniJump2dSpotAhead',  { fg = 'grey',   bg = bg_color, nocombine = true })
  set_default_hl('MiniJump2dSpotUnique', { link = 'MiniJump2dSpot' })
  set_default_hl('MiniJump2dDim',        { link = 'Comment' })
end

H.is_disabled = function() return vim.g.minijump2d_disable == true or vim.b.minijump2d_disable == true end

H.get_config = function(config)
  return vim.tbl_deep_extend('force', MiniJump2d.config, vim.b.minijump2d_config or {}, config or {})
end

-- Jump spots -----------------------------------------------------------------
H.spots_compute = function(opts)
  local win_id_init, allowed = vim.api.nvim_get_current_win(), opts.allowed_windows
  local win_id_arr = vim.tbl_filter(function(win_id)
    if not vim.api.nvim_win_get_config(win_id).focusable then return false end
    if win_id == win_id_init then return allowed.current end
    return allowed.not_current
  end, H.tabpage_list_wins(0))

  local res = {}
  for _, win_id in ipairs(win_id_arr) do
    vim.api.nvim_win_call(win_id, function()
      local cursor_pos = vim.api.nvim_win_get_cursor(win_id)
      local spotter_args = { win_id = win_id, win_id_init = win_id_init }
      local buf_id = vim.api.nvim_win_get_buf(win_id)

      -- Use all currently visible lines
      for i = vim.fn.line('w0'), vim.fn.line('w$') do
        local columns = H.spot_find_in_line(i, spotter_args, opts, cursor_pos)
        -- Use all returned columns for particular line
        for _, col in ipairs(columns) do
          table.insert(res, { line = i, column = col, buf_id = buf_id, win_id = win_id })
        end
      end
    end)
  end
  return res
end

H.spots_add_steps = function(spots, label_tbl, n_steps_ahead)
  -- Compute all required steps
  local steps = {}
  for _ = 1, #spots do
    table.insert(steps, {})
  end

  H.populate_spot_steps(steps, label_tbl, 1, n_steps_ahead + 1)

  for i, spot in ipairs(spots) do
    spot.steps = steps[i]
  end

  return spots
end

---@param spot_steps_arr table Array of step arrays. Single step array consists
---   from labels user needs to press in order to filter out the spot. Example:
---   { { 'a', 'a' }, { 'a', 'b' },  { 'b' } }
---
---@return nil Modifies `spot_steps_arr` in place.
---@private
H.populate_spot_steps = function(spot_steps_arr, label_tbl, cur_step, max_step)
  local n_spots, n_label_chars = #spot_steps_arr, #label_tbl
  if n_spots <= 1 or max_step < cur_step then return end

  -- Adding labels for specific step is done by distributing all available
  -- labels as equally as possible by repeating labels in their order.
  -- Example: with 3 label characters labels should evolve with progressing
  -- number of spots like this: 'a', 'ab', 'abc', 'aabc', 'aabbc', 'aabbcc',
  -- 'aaabbcc', 'aaabbbcc', 'aaabbbccc', etc.
  local base, extra = math.floor(n_spots / n_label_chars), n_spots % n_label_chars

  -- `cur_label_spot_steps` is an array of spot steps which are expanded with
  -- the same label. It is used to initiate computing all steps needed.
  local label_id, cur_label_spot_steps = 1, {}
  local label_max_count = base + (label_id <= extra and 1 or 0)
  for _, spot_steps in ipairs(spot_steps_arr) do
    table.insert(spot_steps, label_tbl[label_id])
    table.insert(cur_label_spot_steps, spot_steps)

    if #cur_label_spot_steps >= label_max_count then
      H.populate_spot_steps(cur_label_spot_steps, label_tbl, cur_step + 1, max_step)
      label_id, cur_label_spot_steps = label_id + 1, {}
      label_max_count = base + (label_id <= extra and 1 or 0)
    end
  end
end

H.spots_show = function(spots, opts)
  spots = spots or H.cache.spots or {}

  local set_extmark = vim.api.nvim_buf_set_extmark

  -- Add extmark with proper virtual text to jump spots
  local dim_buf_lines = {}
  for _, extmark in ipairs(H.spots_to_extmarks(spots, opts)) do
    local extmark_opts = {
      hl_mode = 'combine',
      -- Use very high priority
      priority = 1000,
      virt_text = extmark.virt_text,
      virt_text_pos = 'overlay',
    }
    local buf_id, line = extmark.buf_id, extmark.line
    pcall(set_extmark, buf_id, H.ns_id.spots, line, extmark.col, extmark_opts)

    -- Register lines to dim
    local lines = dim_buf_lines[buf_id] or {}
    lines[line] = true
    dim_buf_lines[buf_id] = lines
  end

  -- Possibly dim used lines
  if opts.view.dim then
    local extmark_opts = { end_col = 0, hl_eol = true, hl_group = opts.hl_group_dim, priority = 999 }
    for buf_id, lines in pairs(dim_buf_lines) do
      for _, l_num in ipairs(vim.tbl_keys(lines)) do
        extmark_opts.end_line = l_num + 1
        pcall(set_extmark, buf_id, H.ns_id.dim, l_num, 0, extmark_opts)
      end
    end
  end

  -- Redraw to force showing marks
  vim.cmd('redraw')
end

H.spots_unshow = function(spots)
  spots = spots or H.cache.spots or {}

  -- Remove spot extmarks from all buffers they are present
  local buf_ids = {}
  for _, s in ipairs(spots) do
    buf_ids[s.buf_id] = true
  end

  for _, buf_id in ipairs(vim.tbl_keys(buf_ids)) do
    pcall(vim.api.nvim_buf_clear_namespace, buf_id, H.ns_id.spots, 0, -1)
    pcall(vim.api.nvim_buf_clear_namespace, buf_id, H.ns_id.dim, 0, -1)
  end
end

--- Convert consecutive spot labels into single extmark
---
--- This considerably increases performance in case of many spots.
---@private
H.spots_to_extmarks = function(spots, opts)
  if #spots == 0 then return {} end

  local hl_group, hl_group_ahead, hl_group_unique = opts.hl_group, opts.hl_group_ahead, opts.hl_group_unique

  -- Compute counts for first step in order to distinguish which highlight
  -- group to use: `hl_group` or `hl_group_unique`
  local first_step_counts = {}
  for _, s in ipairs(spots) do
    local cur_first_step = s.steps[1]
    local cur_count = first_step_counts[cur_first_step] or 0
    first_step_counts[cur_first_step] = cur_count + 1
  end

  -- Define how steps for single spot are added to virtual text
  local append_to_virt_text = function(virt_text_arr, steps, n_steps_to_show)
    -- Use special group if current first step is unique
    local first_hl_group = first_step_counts[steps[1]] == 1 and hl_group_unique or hl_group
    table.insert(virt_text_arr, { steps[1], first_hl_group })

    -- Add ahead steps only if they are present
    local ahead_label = table.concat(steps):sub(2, n_steps_to_show)
    if ahead_label ~= '' then table.insert(virt_text_arr, { ahead_label, hl_group_ahead }) end
  end

  -- Convert all spots to array of extmarks
  local res = {}
  local buf_id, line, col, virt_text = spots[1].buf_id, spots[1].line - 1, spots[1].column - 1, {}

  for i = 1, #spots - 1 do
    local cur_spot, next_spot = spots[i], spots[i + 1]
    local n_steps = #cur_spot.steps

    -- Find which spot steps can be shown
    local is_in_same_line = cur_spot.buf_id == next_spot.buf_id and cur_spot.line == next_spot.line
    local max_allowed_steps = is_in_same_line and (next_spot.column - cur_spot.column) or math.huge
    local n_steps_to_show = math.min(n_steps, max_allowed_steps)

    -- Add text for shown steps
    append_to_virt_text(virt_text, cur_spot.steps, n_steps_to_show)

    -- Finish creating extmark if next spot is far enough
    local next_is_close = is_in_same_line and n_steps == max_allowed_steps
    if not next_is_close then
      table.insert(res, { buf_id = buf_id, line = line, col = col, virt_text = virt_text })
      buf_id, line, col, virt_text = next_spot.buf_id, next_spot.line - 1, next_spot.column - 1, {}
    end
  end

  local last_steps = spots[#spots].steps
  append_to_virt_text(virt_text, last_steps, #last_steps)
  table.insert(res, { buf_id = buf_id, line = line, col = col, virt_text = virt_text })

  return res
end

H.spot_find_in_line = function(line_num, spotter_args, opts, cursor_pos)
  local allowed = opts.allowed_lines

  -- Adjust for cursor line
  local cur_line = cursor_pos[1]
  if
    (not allowed.cursor_before and line_num < cur_line)
    or (not allowed.cursor_at and line_num == cur_line)
    or (not allowed.cursor_after and line_num > cur_line)
  then
    return {}
  end

  -- Process folds
  local fold_indicator = vim.fn.foldclosed(line_num)
  if fold_indicator ~= -1 then return (allowed.fold and fold_indicator == line_num) and { 1 } or {} end

  -- Process blank lines
  if vim.fn.prevnonblank(line_num) ~= line_num then return allowed.blank and { 1 } or {} end

  -- Finally apply spotter
  return opts.spotter(line_num, spotter_args)
end

-- Jump state -----------------------------------------------------------------
H.advance_jump = function(opts)
  local label_tbl = vim.split(opts.labels, '')

  local spots = H.cache.spots
  local n_steps_ahead = opts.view.n_steps_ahead

  if type(spots) ~= 'table' or #spots < 1 then
    H.spots_unshow(spots)
    H.cache.spots = nil
    return
  end

  local key = H.getcharstr('Enter encoding symbol to advance jump')

  if vim.tbl_contains(label_tbl, key) then
    H.spots_unshow(spots)
    spots = vim.tbl_filter(function(x) return x.steps[1] == key end, spots)

    if #spots > 1 then
      spots = H.spots_add_steps(spots, label_tbl, n_steps_ahead)
      H.spots_show(spots, opts)
      H.cache.spots = spots

      H.advance_jump(opts)
    end
  end

  if #spots == 1 or key == H.keys.cr then H.perform_jump(spots[1], opts.hooks.after_jump) end

  MiniJump2d.stop()
end

H.perform_jump = function(spot, after_hook)
  -- Add to jumplist
  vim.cmd('normal! m`')

  vim.api.nvim_set_current_win(spot.win_id)
  vim.api.nvim_win_set_cursor(spot.win_id, { spot.line, spot.column - 1 })

  -- Possibly unfold to see cursor
  vim.cmd('normal! zv')

  if after_hook ~= nil then after_hook() end
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.jump2d) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.notify = function(msg, level_name, silent)
  if not silent then vim.notify('(mini.jump2d) ' .. msg, vim.log.levels[level_name]) end
end

H.echo = function(msg, is_important)
  if H.get_config().silent then return end

  -- Construct message chunks
  msg = type(msg) == 'string' and { { msg } } or msg
  table.insert(msg, 1, { '(mini.jump2d) ', 'WarningMsg' })

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
  vim.api.nvim_echo(chunks, is_important, {})
end

H.unecho = function()
  if H.cache.msg_shown then vim.cmd([[echo '' | redraw]]) end
end

H.message = function(msg) H.echo(msg, true) end

H.is_operator_pending = function()
  return vim.tbl_contains({ 'no', 'noV', H.keys.block_operator_pending }, vim.fn.mode(1))
end

H.getcharstr = function(msg)
  local needs_help_msg = true
  if msg ~= nil then
    vim.defer_fn(function()
      if not needs_help_msg then return end
      H.echo(msg)
      H.cache.msg_shown = true
    end, 1000)
  end

  H.cache.is_in_getcharstr = true
  local _, char = pcall(vim.fn.getcharstr)
  H.cache.is_in_getcharstr = false
  needs_help_msg = false
  H.unecho()

  return char
end

H.input = function(prompt, text)
  -- Distinguish between `<C-c>`, `<Esc>`, and first `<CR>`
  local on_key = vim.on_key or vim.register_keystroke_callback
  local was_cancelled = false
  on_key(function(key)
    if key == H.keys.esc then was_cancelled = true end
  end, H.ns_id.input)

  -- Ask for input
  local opts = { prompt = '(mini.jump2d) ' .. prompt .. ': ', default = text or '' }
  -- Use `pcall` to allow `<C-c>` to cancel user input
  local ok, res = pcall(vim.fn.input, opts)

  -- Stop key listening
  on_key(nil, H.ns_id.input)

  if not ok or was_cancelled then return end
  return res
end

--- This ensures order of windows based on their layout
---
--- This is already done by default in `nvim_tabpage_list_wins()`, but is not
--- documented, so can break any time.
---
---@private
H.tabpage_list_wins = function(tabpage_id)
  local wins = vim.api.nvim_tabpage_list_wins(tabpage_id)
  local wins_pos = {}
  for _, win_id in ipairs(wins) do
    local pos = vim.api.nvim_win_get_position(win_id)
    local config = vim.api.nvim_win_get_config(win_id)
    wins_pos[win_id] = { row = pos[1], col = pos[2], zindex = config.zindex or 0 }
  end

  -- Sort windows by their position: top to bottom, left to right, low to high
  table.sort(wins, function(a, b)
    -- Put higher window further to have them processed later. This means that
    -- in case of same buffer in floating and underlying regular windows,
    -- floating will have "the latest" extmarks (think like `MiniMisc.zoom()`).
    if wins_pos[a].zindex < wins_pos[b].zindex then return true end
    if wins_pos[a].zindex > wins_pos[b].zindex then return false end

    if wins_pos[a].col < wins_pos[b].col then return true end
    if wins_pos[a].col > wins_pos[b].col then return false end

    return wins_pos[a].row < wins_pos[b].row
  end)

  return wins
end

H.map = function(mode, lhs, rhs, opts)
  if lhs == '' then return end
  opts = vim.tbl_deep_extend('force', { silent = true }, opts or {})
  vim.keymap.set(mode, lhs, rhs, opts)
end

H.merge_unique = function(tbl_1, tbl_2)
  if type(tbl_1) == 'table' and type(tbl_2) ~= 'table' then return tbl_1 end
  if type(tbl_1) ~= 'table' and type(tbl_2) == 'table' then return tbl_2 end

  local n_1, n_2 = #tbl_1, #tbl_2
  local res, i, j = {}, 1, 1
  local to_add
  while i <= n_1 and j <= n_2 do
    if tbl_1[i] < tbl_2[j] then
      to_add = tbl_1[i]
      i = i + 1
    else
      to_add = tbl_2[j]
      j = j + 1
    end
    if res[#res] ~= to_add then table.insert(res, to_add) end
  end

  while i <= n_1 do
    to_add = tbl_1[i]
    if res[#res] ~= to_add then table.insert(res, to_add) end
    i = i + 1
  end
  while j <= n_2 do
    to_add = tbl_2[j]
    if res[#res] ~= to_add then table.insert(res, to_add) end
    j = j + 1
  end

  return res
end

H.str_utfindex = function(s, i) return vim.str_utfindex(s, 'utf-32', i) end
if vim.fn.has('nvim-0.11') == 0 then H.str_utfindex = function(s, i) return (vim.str_utfindex(s, i)) end end

H.str_byteindex = function(s, i) return vim.str_byteindex(s, 'utf-32', i) end
if vim.fn.has('nvim-0.11') == 0 then H.str_byteindex = function(s, i) return vim.str_byteindex(s, i) end end

return MiniJump2d
