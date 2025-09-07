--- *mini.move* Move any selection in any direction
--- *MiniMove*
---
--- MIT License Copyright (c) 2023 Evgeni Chasnovski
---
--- ==============================================================================
---
--- Features:
--- - Works in two modes:
---     - Visual mode. Select text (charwise with |v|, linewise with |V|, and
---       blockwise with |CTRL-V|) and press customizable mapping to move in
---       all four directions (left, right, down, up). It keeps Visual mode.
---     - Normal mode. Press customizable mapping to move current line in all
---       four directions (left, right, down, up).
---     - Special handling of linewise movement:
---         - Vertical movement gets reindented with |=|.
---         - Horizontal movement is either improved indent/dedent with |>| / |<|
---           or single character shifting with left and right.
---         - Cursor moves along with selection.
---
--- - Provides both mappings and Lua functions for motions. See
---   |MiniMove.move_selection()| and |MiniMove.move_line()|.
---
--- - Respects |v:count|. Movement mappings can be preceded by a number which
---   multiplies command effect.
---
--- - All consecutive moves (regardless of direction) can be undone by a single |u|.
---
--- - Respects preferred column for vertical movement. It will vertically move
---   selection as how cursor is moving (not strictly vertically if target
---   column is not present in target line).
---
--- Notes:
--- - Doesn't allow moving selection outside of current lines (by design).
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.move').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `MiniMove`
--- which you can use for scripting or manually (with `:lua MiniMove.*`).
---
--- See |MiniMove.config| for available config settings.
---
--- You can override runtime config settings (but not `config.mappings`) locally
--- to buffer inside `vim.b.minimove_config` which should have same structure
--- as `MiniMove.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- # Comparisons ~
---
--- - 'matze/vim-move':
---     - Doesn't support vertical movement of charwise and blockwise selections.
---       While 'mini.move' does.
---     - Doesn't support horizontal movement of current line in favor of
---       horizontal movement of current character.
---     - Has extra functionality for certain moves (like move by half page).
---       While 'mini.move' does not (by design).
--- - 'booperlv/nvim-gomove':
---     - Doesn't support movement in charwise visual selection.
---       While 'mini.move' does.
---     - Has extra functionality beyond moving text, like duplication.
---       While 'mini.move' concentrates only on moving functionality.
---
--- # Disabling ~
---
--- To disable, set `vim.g.minimove_disable` (globally) or `vim.b.minimove_disable`
--- (for a buffer) to `true`. Considering high number of different scenarios
--- and customization intentions, writing exact rules for disabling module's
--- functionality is left to user. See |mini.nvim-disabling-recipes| for common
--- recipes.

---@alias __move_direction string One of "left", "down", "up", "right".
---@alias __move_opts table|nil Options. Same structure as `options` in |MiniMove.config|
---   (with its values as defaults) plus these allowed extra fields:
---   - <n_times> (number) - number of times to try to make a move.
---     Default: |v:count1|.

---@diagnostic disable:undefined-field

-- Module definition ==========================================================
local MiniMove = {}
local H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniMove.config|.
---
---@usage >lua
---   require('mini.move').setup() -- use default config
---   -- OR
---   require('mini.move').setup({}) -- replace {} with your config table
--- <
MiniMove.setup = function(config)
  -- Export module
  _G.MiniMove = MiniMove

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)
end

--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text # Mappings ~
---
--- Other possible choices of mappings: >lua
---
---   -- `HJKL` for moving visual selection (overrides H, L, J in Visual mode)
---   require('mini.move').setup({
---     mappings = {
---       left  = 'H',
---       right = 'L',
---       down  = 'J',
---       up    = 'K',
---     }
---   })
---
---   -- Shift + arrows
---   require('mini.move').setup({
---     mappings = {
---       left  = '<S-left>',
---       right = '<S-right>',
---       down  = '<S-down>',
---       up    = '<S-up>',
---
---       line_left  = '<S-left>',
---       line_right = '<S-right>',
---       line_down  = '<S-down>',
---       line_up    = '<S-up>',
---     }
---   })
--- <
MiniMove.config = {
  -- Module mappings. Use `''` (empty string) to disable one.
  mappings = {
    -- Move visual selection in Visual mode. Defaults are Alt (Meta) + hjkl.
    left = '<M-h>',
    right = '<M-l>',
    down = '<M-j>',
    up = '<M-k>',

    -- Move current line in Normal mode
    line_left = '<M-h>',
    line_right = '<M-l>',
    line_down = '<M-j>',
    line_up = '<M-k>',
  },

  -- Options which control moving behavior
  options = {
    -- Shift the character under the cursor horizontally instead of indenting
    -- in linewise mode
    shift_horizontal_chars = false,
    -- Automatically reindent selection during linewise vertical move
    reindent_linewise = true,
  },
}
--minidoc_afterlines_end

-- Module functionality =======================================================
--- Move visually selected region in any direction within present lines
---
--- Main function powering visual selection move in Visual mode.
---
--- Notes:
--- - Vertical movement in linewise mode is followed up by reindent with |v_=|.
--- - Horizontal movement in linewise mode is same as |v_<| and |v_>|.
---
---@param direction __move_direction
---@param opts __move_opts
MiniMove.move_selection = function(direction, opts)
  if H.is_disabled() or not vim.o.modifiable then return end

  opts = vim.tbl_deep_extend('force', H.get_config().options, opts or {})

  -- This could have been a one-line expression mappings, but there are issues:
  -- - Initial yanking modifies some register. Not critical, but also not good.
  -- - Doesn't work at movement edges (first line for `K`, etc.). See
  --   https://github.com/vim/vim/issues/11786
  -- - Results into each movement being a separate undo block, which is
  --   inconvenient with several back-to-back movements.
  local cur_mode = vim.fn.mode()

  -- Act only inside visual mode
  if not (cur_mode == 'v' or cur_mode == 'V' or cur_mode == '\22') then return end

  -- Define common predicates
  local dir_type = (direction == 'up' or direction == 'down') and 'vert' or 'hori'
  local is_linewise = cur_mode == 'V'

  -- Make early return in small buffer
  if vim.api.nvim_buf_line_count(0) == 1 then
    if is_linewise and dir_type == 'vert' then return end
    if not is_linewise and vim.fn.getline(1):len() == 0 then return end
  end

  -- Cache useful data because it will be reset when executing commands
  local n_times = opts.n_times or vim.v.count1
  local ref_curpos, ref_last_col = vim.fn.getcurpos(), vim.fn.col('$')
  local is_cursor_on_selection_start = vim.fn.line('.') < vim.fn.line('v')

  -- Determine if previous action was this type of move
  local is_moving = vim.deep_equal(H.state, H.get_move_state())
  if not is_moving then H.curswant = nil end

  -- Allow undo of consecutive moves at once (direction doesn't matter)
  local cmd = H.make_cmd_normal(is_moving)

  -- Treat horizontal linewise movement specially
  if is_linewise and dir_type == 'hori' then
    -- Use indentation as horizontal movement for linewise selection
    cmd(n_times .. H.indent_keys[direction] .. 'gv')

    -- Make cursor move along selection
    H.correct_cursor_col(ref_curpos, ref_last_col)

    -- Track new state to allow joining in single undo block
    H.state = H.get_move_state()

    return
  end

  -- Temporarily ensure possibility to put cursor just after line end.
  -- This allows a more intuitive cursor positioning from and to end of line.
  -- NOTE: somehow, this should be done before initial cut to take effect.
  local cache_virtualedit = vim.o.virtualedit
  if not cache_virtualedit:find('all') then vim.o.virtualedit = 'onemore' end

  -- Cut selection while saving caching register
  local cache_z_reg = vim.fn.getreginfo('z')
  -- - Don't use `"zx` directly to not affect registers 1-9
  cmd('"zygv"_x')

  -- Detect edge selection: last line(s) for vertical and last character(s)
  -- for horizontal. At this point (after cutting selection) cursor is on the
  -- edge which can happen in two cases:
  --   - Move second to last selection towards edge (like in 'abc' move 'b'
  --     to right or second to last line down).
  --   - Move edge selection away from edge (like in 'abc' move 'c' to left
  --     or last line up).
  -- Use condition that removed selection was further than current cursor
  -- to distinguish between two cases.
  local is_edge_selection_hori = dir_type == 'hori' and vim.fn.col('.') < vim.fn.col("'<")
  local is_edge_selection_vert = dir_type == 'vert' and vim.fn.line('.') < vim.fn.line("'<")
  local is_edge_selection = is_edge_selection_hori or is_edge_selection_vert

  -- Use `p` as paste key instead of `P` in cases which might require moving
  -- selection to place which is unreachable with `P`: right to be line end
  -- and down to be last line. NOTE: temporary `virtualedit=onemore` solves
  -- this only for horizontal movement, but not for vertical.
  local can_go_overline = not is_linewise and direction == 'right'
  local can_go_overbuf = is_linewise and direction == 'down'
  local paste_key = (can_go_overline or can_go_overbuf) and 'p' or 'P'

  -- Restore `curswant` to try move cursor to initial column (just like
  -- default `hjkl` moves)
  if dir_type == 'vert' then H.set_curswant(H.curswant) end

  -- Possibly reduce number of moves by one to not overshoot move
  local n = n_times - ((paste_key == 'p' or is_edge_selection) and 1 or 0)

  -- Don't allow movement past last line of block selection (any part)
  if cur_mode == '\22' and direction == 'down' and vim.fn.line('$') == vim.fn.line("'>") then n = 0 end

  -- Move cursor
  if n > 0 then cmd(n .. H.move_keys[direction]) end

  -- Save curswant. Correct for one less move when using `p` as paste.
  H.curswant = H.get_curswant() + ((direction == 'right' and paste_key == 'p') and 1 or 0)

  -- Open just enough folds (but not in linewise mode, as it allows moving
  -- past folds)
  if not is_linewise then cmd('zv') end

  -- Paste
  cmd('"z' .. paste_key)

  -- Select newly moved region. Another way is to use something like `gvhoho`
  -- but it doesn't work well with selections spanning several lines.
  cmd('`[1v')

  -- Do extra in case of linewise selection
  if is_linewise then
    -- Reindent linewise selection if `=` can do that.
    -- NOTE: this sometimes doesn't work well with folds (and probably
    -- `foldmethod=indent`) and linewise mode because it recomputes folds after
    -- that and the whole "move past fold" doesn't work.
    if opts.reindent_linewise and dir_type == 'vert' and vim.o.equalprg == '' then cmd('=gv') end

    -- Move cursor along the selection. NOTE: do this *after* reindent to
    -- account for its effect.
    -- - Ensure that cursor is on the right side of selection
    if is_cursor_on_selection_start then cmd('o') end
    H.correct_cursor_col(ref_curpos, ref_last_col)
  end

  -- Restore intermediate values
  vim.fn.setreg('z', cache_z_reg)
  vim.o.virtualedit = cache_virtualedit

  -- Track new state to allow joining in single undo block
  H.state = H.get_move_state()
end

--- Move current line in any direction
---
--- Main function powering current line move in Normal mode.
---
--- Notes:
--- - Vertical movement is followed up by reindent with |v_=|.
--- - Horizontal movement is almost the same as |<<| and |>>| with a different
---   handling of |v:count| (multiplies shift effect instead of modifying that
---   number of lines).
---
---@param direction __move_direction
---@param opts __move_opts
MiniMove.move_line = function(direction, opts)
  if H.is_disabled() or not vim.o.modifiable then return end
  if vim.api.nvim_buf_line_count(0) == 1 and (direction == 'down' or direction == 'up') then return end

  opts = vim.tbl_deep_extend('force', H.get_config().options, opts or {})

  -- Determine if previous action was this type of move
  local is_moving = vim.deep_equal(H.state, H.get_move_state())

  -- Allow undo of consecutive moves at once (direction doesn't matter)
  local cmd = H.make_cmd_normal(is_moving)

  -- Cache useful data because it will be reset when executing commands
  local n_times = opts.n_times or vim.v.count1
  local is_last_line_up = direction == 'up' and vim.fn.line('.') == vim.fn.line('$')
  local ref_curpos, ref_last_col = vim.fn.getcurpos(), vim.fn.col('$')

  if direction == 'left' or direction == 'right' then
    -- NOTE: This documentation OK?
    -- Use either indentation or single character shifting as horizontal
    -- movement. Explicitly call `count1` because `<`/`>` use `v:count` to
    -- define number of lines. Go to first non-blank at the end.

    -- NOTE: Added as first option to avoid `if not` per personal style policy
    if opts.shift_horizontal_chars then
      local key = H.move_keys[direction]
      cmd("x" .. string.rep(key, n_times) .. "P")

      -- NOTE: This is a bit hacky, I admit, but I don't control vim cursor
      -- positions much. If there's better code for this, please let me know :-)
      if key == "l" then
        ref_last_col = ref_last_col - n_times
      else
        ref_last_col = ref_last_col + n_times
      end
    else
      -- NOTE: This is the original behaviour (`<<` and `>>`)
      local key = H.indent_keys[direction]
      cmd(string.rep(key .. key, n_times))
    end

    -- Make cursor move along selection
    H.correct_cursor_col(ref_curpos, ref_last_col)

    -- Track new state to allow joining in single undo block
    H.state = H.get_move_state()

    return
  end

  -- Cut current line while saving caching register
  local cache_z_reg = vim.fn.getreginfo('z')
  -- - Don't use `"zdd` directly to not affect registers 1-9
  cmd('"zyy"_dd')

  -- Move cursor
  local paste_key = direction == 'up' and 'P' or 'p'
  local n = n_times - ((paste_key == 'p' or is_last_line_up) and 1 or 0)
  if n > 0 then cmd(n .. H.move_keys[direction]) end

  -- Paste
  cmd('"z' .. paste_key)

  -- Reindent and put cursor on first non-blank
  if opts.reindent_linewise and vim.o.equalprg == '' then cmd('==') end

  -- Move cursor along the selection. NOTE: do this *after* reindent to
  -- account for its effect.
  H.correct_cursor_col(ref_curpos, ref_last_col)

  -- Restore intermediate values
  vim.fn.setreg('z', cache_z_reg)

  -- Track new state to allow joining in single undo block
  H.state = H.get_move_state()
end

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniMove.config)

H.move_keys = { left = 'h', down = 'j', up = 'k', right = 'l' }
H.indent_keys = { left = '<', right = '>' }

-- Moving state used to decide when to start new undo block ...
H.state = {
  -- ... on buffer change
  buf_id = nil,
  -- ... on text change
  changedtick = nil,
  -- ... on cursor move
  cursor = nil,
  -- ... on mode change
  mode = nil,
}

H.curswant = nil

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  H.check_type('mappings', config.mappings, 'table')
  H.check_type('mappings.left', config.mappings.left, 'string')
  H.check_type('mappings.down', config.mappings.down, 'string')
  H.check_type('mappings.up', config.mappings.up, 'string')
  H.check_type('mappings.right', config.mappings.right, 'string')
  H.check_type('mappings.line_left', config.mappings.line_left, 'string')
  H.check_type('mappings.line_right', config.mappings.line_right, 'string')
  H.check_type('mappings.line_down', config.mappings.line_down, 'string')
  H.check_type('mappings.line_up', config.mappings.line_up, 'string')

  H.check_type('options', config.options, 'table')
  H.check_type('options.shift_horizontal_chars', config.options.shift_horizontal_chars, 'boolean')
  H.check_type('options.reindent_linewise', config.options.reindent_linewise, 'boolean')

  return config
end

--stylua: ignore
H.apply_config = function(config)
  MiniMove.config = config

  -- Make mappings
  local maps = config.mappings

  H.map('x', maps.left,  [[<Cmd>lua MiniMove.move_selection('left')<CR>]],  { desc = 'Move left' })
  H.map('x', maps.right, [[<Cmd>lua MiniMove.move_selection('right')<CR>]], { desc = 'Move right' })
  H.map('x', maps.down,  [[<Cmd>lua MiniMove.move_selection('down')<CR>]],  { desc = 'Move down' })
  H.map('x', maps.up,    [[<Cmd>lua MiniMove.move_selection('up')<CR>]],    { desc = 'Move up' })

  H.map('n', maps.line_left,  [[<Cmd>lua MiniMove.move_line('left')<CR>]],  { desc = 'Move line left' })
  H.map('n', maps.line_right, [[<Cmd>lua MiniMove.move_line('right')<CR>]], { desc = 'Move line right' })
  H.map('n', maps.line_down,  [[<Cmd>lua MiniMove.move_line('down')<CR>]],  { desc = 'Move line down' })
  H.map('n', maps.line_up,    [[<Cmd>lua MiniMove.move_line('up')<CR>]],    { desc = 'Move line up' })
end

H.is_disabled = function() return vim.g.minimove_disable == true or vim.b.minimove_disable == true end

H.get_config = function(config)
  return vim.tbl_deep_extend('force', MiniMove.config, vim.b.minimove_config or {}, config or {})
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.move) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.map = function(mode, lhs, rhs, opts)
  if lhs == '' then return end
  opts = vim.tbl_deep_extend('force', { silent = true }, opts or {})
  vim.keymap.set(mode, lhs, rhs, opts)
end

H.make_cmd_normal = function(include_undojoin)
  local normal_command = (include_undojoin and 'undojoin | ' or '') .. 'silent keepjumps normal! '

  return function(x)
    -- Caching and restoring data on every command is not necessary but leads
    -- to a nicer implementation

    -- Disable 'mini.bracketed' to avoid unwanted entries to its yank history
    local cache_minibracketed_disable = vim.b.minibracketed_disable
    local cache_unnamed_register = { points_to = vim.fn.getreginfo('"').points_to }

    -- Don't track possible put commands into yank history
    vim.b.minibracketed_disable = true

    vim.cmd(normal_command .. x)

    vim.b.minibracketed_disable = cache_minibracketed_disable
    vim.fn.setreg('"', cache_unnamed_register)
  end
end

H.get_move_state = function()
  return {
    buf_id = vim.api.nvim_get_current_buf(),
    changedtick = vim.b.changedtick,
    cursor = vim.api.nvim_win_get_cursor(0),
    mode = vim.fn.mode(),
  }
end

H.correct_cursor_col = function(ref_curpos, ref_last_col)
  -- Use `ref_curpos = getcurpos()` instead of `vim.api.nvim_win_get_cursor(0)`
  -- allows to also account for `virtualedit=all`

  local col_diff = vim.fn.col('$') - ref_last_col
  local new_col = math.max(ref_curpos[3] + col_diff, 1)
  vim.fn.cursor({ vim.fn.line('.'), new_col, ref_curpos[4], ref_curpos[5] + col_diff })
end

H.get_curswant = function() return vim.fn.winsaveview().curswant end
H.set_curswant = function(x)
  if x == nil then return end
  vim.fn.winrestview({ curswant = x })
end

return MiniMove
