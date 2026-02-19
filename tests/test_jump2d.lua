local helpers = dofile('tests/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('jump2d', config) end
local unload_module = function() child.mini_unload('jump2d') end
local reload_module = function(config) unload_module(); load_module(config) end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
local sleep = function(ms) helpers.sleep(ms, child) end
local get_latest_message = function() return child.cmd_capture('1messages') end
--stylua: ignore end

-- Make helpers
-- Window setups
local setup_windows = function()
  -- Current tabpage. Create four windows.
  local win_topleft = child.api.nvim_get_current_win()

  child.cmd('rightbelow split')
  local win_bottomleft = child.api.nvim_get_current_win()

  child.api.nvim_set_current_win(win_topleft)
  child.cmd('rightbelow vsplit')
  local win_topright = child.api.nvim_get_current_win()

  child.api.nvim_set_current_win(win_bottomleft)
  child.cmd('rightbelow vsplit')
  local win_bottomright = child.api.nvim_get_current_win()

  -- Other tabpage
  child.cmd('tabedit')
  local win_other_tabpage = child.api.nvim_get_current_win()

  -- Construct window table
  child.api.nvim_set_current_win(win_topleft)
  local wins = {
    topleft = win_topleft,
    bottomleft = win_bottomleft,
    topright = win_topright,
    bottomright = win_bottomright,
    other_tabpage = win_other_tabpage,
  }

  -- Ensure different buffers with text tailored to buffer id
  for _, name in ipairs({ 'topleft', 'bottomleft', 'topright', 'bottomright', 'other_tabpage' }) do
    local win_id = wins[name]
    local buf_id = child.api.nvim_create_buf(true, false)
    child.api.nvim_win_set_buf(win_id, buf_id)
    child.api.nvim_buf_set_lines(buf_id, 0, -1, true, { 'xx' .. buf_id .. 'xx' })
  end

  return wins
end

local setup_two_windows = function()
  local win_left = child.api.nvim_get_current_win()
  child.cmd('rightbelow vsplit aaa')
  local win_right = child.api.nvim_get_current_win()

  child.api.nvim_set_current_win(win_left)
  local wins = { left = win_left, right = win_right }

  for _, win_name in ipairs({ 'left', 'right' }) do
    local buf_id = child.api.nvim_create_buf(true, false)
    local l = 'xx' .. buf_id .. 'xx'
    child.api.nvim_buf_set_lines(buf_id, 0, -1, true, { l, l, l })

    local win_id = wins[win_name]
    child.api.nvim_win_set_buf(win_id, buf_id)
    child.api.nvim_win_set_cursor(win_id, { 2, 0 })
  end

  return wins
end

-- Time constants
local reminder_delay = 1000
local small_time = helpers.get_time_const(10)

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      load_module()

      -- Make `start()` non-blocking to be able to execute tests. Otherwise it
      -- will block child state waiting for `getcharstr()` to finish.
      child.lua('MiniJump2d.start = vim.schedule_wrap(MiniJump2d.start)')
    end,
    post_once = child.stop,
  },
  n_retry = helpers.get_n_retry(2),
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  -- Global variable
  eq(child.lua_get('type(_G.MiniJump2d)'), 'table')

  -- Autocommand group (with default config)
  eq(child.fn.exists('#MiniJump2d'), 1)

  -- Highlight groups, depending on background
  child.cmd('hi clear')
  child.o.background = 'dark'
  reload_module()
  expect.match(child.cmd_capture('hi MiniJump2dSpot'), 'gui=bold,nocombine guifg=[Ww]hite guibg=[Bb]lack')

  child.cmd('hi clear MiniJump2dSpot')

  child.o.background = 'light'
  reload_module()
  expect.match(child.cmd_capture('hi MiniJump2dSpot'), 'gui=bold,nocombine guifg=[Bb]lack guibg=[Ww]hite')
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniJump2d.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniJump2d.config.' .. field), value) end

  expect_config('spotter', vim.NIL)
  expect_config('labels', 'abcdefghijklmnopqrstuvwxyz')
  expect_config('view', { dim = false, n_steps_ahead = 0 })
  expect_config(
    'allowed_lines',
    { blank = true, cursor_before = true, cursor_at = true, cursor_after = true, fold = true }
  )
  expect_config('allowed_windows', { current = true, not_current = true })
  expect_config('hooks', { before_start = nil, after_jump = nil })
  expect_config('mappings', { start_jumping = '<CR>' })
  expect_config('silent', false)
end

T['setup()']['respects `config` argument'] = function()
  unload_module()
  load_module({ labels = 'a' })
  eq(child.lua_get('MiniJump2d.config.labels'), 'a')
end

T['setup()']['validates `config` argument'] = function()
  unload_module()

  local expect_config_error = function(config, name, target_type)
    expect.error(function() load_module(config) end, vim.pesc(name) .. '.*' .. vim.pesc(target_type))
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ spotter = 'a' }, 'spotter', 'function')
  expect_config_error({ labels = 1 }, 'labels', 'string')
  expect_config_error({ view = 1 }, 'view', 'table')
  expect_config_error({ view = { dim = 'a' } }, 'view.dim', 'boolean')
  expect_config_error({ view = { n_steps_ahead = 'a' } }, 'view.n_steps_ahead', 'number')
  expect_config_error({ allowed_lines = 'a' }, 'allowed_lines', 'table')
  expect_config_error({ allowed_lines = { blank = 1 } }, 'allowed_lines.blank', 'boolean')
  expect_config_error({ allowed_lines = { cursor_before = 1 } }, 'allowed_lines.cursor_before', 'boolean')
  expect_config_error({ allowed_lines = { cursor_at = 1 } }, 'allowed_lines.cursor_at', 'boolean')
  expect_config_error({ allowed_lines = { cursor_after = 1 } }, 'allowed_lines.cursor_after', 'boolean')
  expect_config_error({ allowed_lines = { fold = 1 } }, 'allowed_lines.fold', 'boolean')
  expect_config_error({ allowed_windows = 'a' }, 'allowed_windows', 'table')
  expect_config_error({ allowed_windows = { current = 'a' } }, 'allowed_windows.current', 'boolean')
  expect_config_error({ allowed_windows = { not_current = 'a' } }, 'allowed_windows.not_current', 'boolean')
  expect_config_error({ hooks = 'a' }, 'hooks', 'table')
  expect_config_error({ hooks = { before_start = 1 } }, 'hooks.before_start', 'function')
  expect_config_error({ hooks = { after_jump = 1 } }, 'hooks.after_jump', 'function')
  expect_config_error({ mappings = 'a' }, 'mappings', 'table')
  expect_config_error({ mappings = { start_jumping = 1 } }, 'mappings.start_jumping', 'string')
  expect_config_error({ silent = 'a' }, 'silent', 'boolean')
end

T['setup()']['ensures colors'] = function()
  child.cmd('colorscheme default')
  expect.match(child.cmd_capture('hi MiniJump2dSpot'), 'gui=bold,nocombine guifg=[Ww]hite guibg=[Bb]lack')
end

T['setup()']['applies `config.mappings`'] = function()
  child.set_size(5, 12)
  set_lines({ 'xxxx', 'xxxx' })
  type_keys('<CR>')
  child.expect_screenshot()
end

T['setup()']['properly handles `config.mappings`'] = function()
  local has_map = function(lhs, pattern) return child.cmd_capture('nmap ' .. lhs):find(pattern) ~= nil end
  eq(has_map('<CR>', '2d'), true)

  unload_module()
  child.api.nvim_del_keymap('n', '<CR>')

  -- Supplying empty string should mean "don't create keymap"
  load_module({ mappings = { start_jumping = '' } })
  eq(has_map('<CR>', '2d'), false)
end

T['setup()']['resets <CR> mapping in quickfix window'] = function()
  child.set_size(20, 50)
  set_lines({ 'Hello World' })
  child.cmd([[cexpr ['Hello', 'Quickfix'] | copen]])
  -- Should create not remappable buffer-local mapping
  expect.match(child.cmd_capture('nmap <CR>'), '%*@<CR>')
end

T['setup()']['resets <CR> mapping in command-line window'] = function()
  type_keys([[:call append(0, 'Hello')<CR>]])
  set_lines({})
  type_keys('q:')
  set_cursor(1, 0)
  type_keys('<CR>')
  eq(child.get_lines(), { 'Hello', '' })
end

T['start()'] = new_set({
  hooks = {
    pre_case = function()
      -- Reference lines:
      -- xxxx
      --
      -- xxxx
      set_lines({ 'xxxx', '', 'xxxx' })
      child.set_size(5, 12)
    end,
  },
})

local start = function(...)
  child.lua('MiniJump2d.start(...)', { ... })
  child.poke_eventloop()
end

T['start()']['works'] = function()
  local init_curpos = get_cursor()

  start()
  child.expect_screenshot()
  type_keys('e')
  eq(get_cursor(), { 3, 3 })
  child.expect_screenshot()

  -- Adds previous position to jumplist
  type_keys('<C-o>')
  eq(get_cursor(), init_curpos)
end

T['start()']['works in Visual mode'] = function()
  child.set_size(5, 40)
  child.o.showcmd = false

  type_keys('v')

  start()
  child.expect_screenshot()
  type_keys('d')
  eq(get_cursor(), { 3, 0 })
  child.expect_screenshot()

  eq(child.api.nvim_get_mode().mode, 'v')
end

T['start()']['works in Operator-pending mode'] = function()
  -- Reload module to revert `start()` to being blocking
  reload_module()

  type_keys('d')
  -- Use default mapping to fully imitate Operator-pending mode (and it doesn't
  -- work otherwise)
  type_keys('<CR>')
  child.expect_screenshot()
  type_keys('b')

  child.cmd('redrawstatus')
  child.expect_screenshot()

  -- Allows dot-repeat
  type_keys('.')
  child.expect_screenshot()
  type_keys('c')
  child.expect_screenshot()
end

T['start()']['highlights unique labels with different highlight group'] = function()
  child.cmd('hi MiniJump2dSpotUnique guifg=Green')
  start({ labels = 'jk' })
  type_keys('j')
  child.expect_screenshot()
end

T['start()']['uses only visible lines'] = function()
  -- Check this only on Neovim>=0.11, as there is a slight change in
  -- highlighting command line area
  if child.fn.has('nvim-0.11') == 0 then return end

  set_lines({ '1xxx', '2xxx', '3xxx', '4xxx' })

  -- Make window show only lines 2 and 3
  child.api.nvim_win_set_height(0, 2)
  set_cursor(2, 0)
  type_keys('zt')
  child.expect_screenshot()

  -- Validate
  start()
  child.expect_screenshot()
  type_keys('d')
  eq(get_cursor(), { 3, 3 })
end

T['start()']['ignores cursor position during label computation'] = new_set({
  parametrize = { { 1, 1 }, { 2, 0 }, { 3, 0 }, { 3, 3 } },
}, {
  test = function(line, col)
    child.api.nvim_win_set_cursor(0, { line, col })
    start()
    -- All screenshots should have same labels and spots
    child.expect_screenshot()
  end,
})

T['start()']['uses `<CR>` to jump to first available spot'] = function()
  child.set_size(5, 20)
  local win_width = child.fn.winwidth(0)
  local line = string.rep('- ', math.floor(0.5 * win_width))
  set_lines(vim.fn['repeat']({ line }, child.fn.winheight(0)))

  -- On first step
  set_cursor(1, 9)
  start()
  type_keys('<CR>')
  eq(get_cursor(), { 1, 0 })

  -- On later steps
  set_cursor(1, 9)
  start()
  -- Spots should be labeled `a a b b c c ...`
  child.expect_screenshot()
  type_keys(1, 'b', '<CR>')
  eq(get_cursor(), { 1, 4 })
end

T['start()']['jumps immediately to single spot'] = function()
  set_lines({ '  x' })
  set_cursor(1, 0)

  start()
  eq(get_cursor(), { 1, 2 })
  -- No spots should be shown
  child.expect_screenshot()
end

T['start()']['shows reminder after one idle second'] = function()
  -- Helps create hit-enter-prompt
  child.set_size(5, 60)

  child.lua([[MiniJump2d.config.labels = 'jk']])

  start()
  sleep(reminder_delay + small_time)

  -- Should show helper message without adding it to `:messages` and causing
  -- hit-enter-prompt
  eq(get_latest_message(), '')
  child.expect_screenshot()

  -- Should clean afterwards
  type_keys('j')
  sleep(small_time)
  child.expect_screenshot()

  -- Should show message for every key in sequence
  sleep(reminder_delay + small_time)
  child.expect_screenshot()
end

T['start()']['stops jumping if not label was typed'] = new_set({
  -- <C-c> shouldn't result into error
  parametrize = { { '<Down>' }, { '<Esc>' }, { '<C-c>' } },
}, {
  test = function(key)
    set_cursor(1, 0)
    start()

    type_keys(key)

    -- Cursor shouldn't move
    eq(get_cursor(), { 1, 0 })
    -- No highlighting should be shown
    child.expect_screenshot()
  end,
})

T['start()']['ignores current window during label computation'] = new_set({
  parametrize = { { 'topright' }, { 'bottomleft' } },
}, {
  test = function(window_name)
    child.set_size(10, 50)
    local wins = setup_windows()
    child.api.nvim_set_current_win(wins[window_name])

    start()
    -- Should have same labels even with different current windows
    child.expect_screenshot()
  end,
})

T['start()']['uses only all visible windows by default'] = function()
  child.set_size(10, 50)
  setup_windows()

  local cur_win_id, cur_pos = child.api.nvim_get_current_win(), child.api.nvim_win_get_cursor(0)
  start()
  child.expect_screenshot()

  -- There should be labels from 'a' to 'h'. Typing `i` should not take effect.
  type_keys('i')
  eq(child.api.nvim_get_current_win(), cur_win_id)
  eq(child.api.nvim_win_get_cursor(0), cur_pos)
end

T['start()']['traverses visible "regular" windows based on their layout'] = function()
  child.set_size(10, 50)
  local wins = setup_windows()

  -- Make topright window be "on the right" of bottomright
  child.api.nvim_set_current_win(wins.topright)
  child.cmd('vertical resize -1')
  child.api.nvim_set_current_win(wins.topleft)

  start()
  -- Order should be top to bottom, left to right
  -- Topright is on the right of bottomright, so labels are processed later
  child.expect_screenshot()
end

T['start()']['traverses floating windows at the end'] = function()
  -- Set up windows and buffers
  local buf_regular = child.api.nvim_get_current_buf()
  local win_regular = child.api.nvim_get_current_win()
  local buf_floating = child.api.nvim_create_buf(true, false)
  local win_floating = child.api.nvim_open_win(
    buf_floating,
    false,
    { relative = 'win', win = win_regular, width = 4, height = 1, row = 0, col = 0 }
  )

  child.api.nvim_buf_set_lines(buf_regular, 0, -1, true, { 'xxxx', 'xxxx' })
  child.api.nvim_buf_set_lines(buf_floating, 0, -1, true, { 'xxxx' })

  -- Both windows have same "positions" but different "zindex"
  eq(child.api.nvim_win_get_position(win_regular), child.api.nvim_win_get_position(win_floating))

  start()
  child.expect_screenshot()
end

T['start()']['overrides `config` from `opts` argument'] = function()
  child.lua([[MiniJump2d.config.labels = 'jk']])
  start({ allowed_lines = { blank = false } })
  child.expect_screenshot()
end

T['start()']['respects `spotter`'] = function()
  child.lua('MiniJump2d.start({ spotter = function() return { 1 } end })')
  child.expect_screenshot()

  child.lua('MiniJump2d.stop()')
  child.lua('vim.b.minijump2d_config = { spotter = function() return { 2 } end }')
  child.lua('MiniJump2d.start()')
  child.expect_screenshot()
end

T['start()']['uses `spotter` with correct arguments'] = function()
  child.set_size(5, 40)

  -- Set up windows and buffers. One with empty line, other - with fold
  local win_init, buf_init = child.api.nvim_get_current_win(), child.api.nvim_get_current_buf()
  child.api.nvim_buf_set_lines(buf_init, 0, -1, true, { 'xxxx', '', 'xxxx' })

  child.cmd('rightbelow vsplit aaa')
  local win_other, buf_other = child.api.nvim_get_current_win(), child.api.nvim_get_current_buf()
  child.api.nvim_buf_set_lines(buf_other, 0, -1, true, { 'yyyy', 'yyyy', 'yyyy' })

  set_cursor(2, 0)
  type_keys('zf', 'j')
  eq({ child.fn.foldclosed(2), child.fn.foldclosed(3) }, { 2, 2 })
  set_cursor(1, 0)

  child.api.nvim_set_current_win(win_init)

  -- Validate. `spotter` should be called with signature:
  -- `<line number>, {win_id = <number>, win_id_init = <number>}`
  -- Shouldn't be called on blank and fold lines
  child.lua('_G.args_history = {}')
  child.lua([[
    MiniJump2d.start({
      labels = 'jk',
      spotter = function(...) table.insert(_G.args_history, { ... }); return { 1 } end
    })]])
  eq(child.lua_get('_G.args_history'), {
    { 1, { win_id = win_init, win_id_init = win_init } },
    -- Line 2 is blank, shouldn't be called
    { 3, { win_id = win_init, win_id_init = win_init } },
    { 1, { win_id = win_other, win_id_init = win_init } },
    -- Lines 2 and 3 are folded, shouldn't be called
  })
  child.expect_screenshot()

  -- Should call `spotter` only on jumped start, not on every step
  child.lua('_G.args_history = {}')
  type_keys(1, 'j', '<CR>')
  eq(child.lua_get('_G.args_history'), {})
end

T['start()']['respects `labels`'] = function()
  set_cursor(1, 0)
  start({ labels = 'jk' })
  child.expect_screenshot()
  type_keys('j', 'k')
  eq(get_cursor(), { 2, 0 })

  -- Should also use buffer local config
  child.lua('MiniJump2d.stop()')
  child.b.minijump2d_config = { labels = 'ab' }
  start()
  child.expect_screenshot()
end

T['start()']['respects `view.dim`'] = function()
  -- In argument
  start({ labels = 'jk', view = { dim = true } })

  type_keys('j')
  -- Whole lines with at least one jump spot should be highlighted differently
  child.expect_screenshot()

  type_keys('j')
  child.expect_screenshot()
  child.lua('MiniJump2d.stop()')

  -- In global config
  child.lua('MiniJump2d.config.view.dim = true')
  start({ labels = 'jk' })
  type_keys('j', 'j')
  child.expect_screenshot()
end

T['start()']['respects `view.n_steps_ahead`'] = function()
  -- In argument
  start({ labels = 'jk', view = { n_steps_ahead = 1 } })
  child.expect_screenshot()

  type_keys('j')
  child.expect_screenshot()

  type_keys('j')
  child.expect_screenshot()

  type_keys('k')
  eq(get_cursor(), { 1, 3 })

  -- In global config
  child.lua('MiniJump2d.config.view.n_steps_ahead = 2')
  start({ labels = 'jk' })
  child.expect_screenshot()

  type_keys('j')
  child.expect_screenshot()
end

T['start()']['handles very big `view.n_steps_ahead`'] = function()
  start({ labels = 'jk', view = { n_steps_ahead = math.huge } })
  child.expect_screenshot()
  child.lua('MiniJump2d.stop()')

  start({ labels = 'hjkl', view = { n_steps_ahead = math.huge } })
  child.expect_screenshot()
end

T['start()']['handles overlapping multi-step labels'] = function()
  child.lua([[MiniJump2d.config.spotter = MiniJump2d.gen_spotter.pattern('.')]])
  start({ labels = 'jk', view = { n_steps_ahead = 2 } })
  child.expect_screenshot()

  type_keys('j')
  child.expect_screenshot()

  type_keys('j')
  child.expect_screenshot()

  type_keys('j')
  child.expect_screenshot()
end

T['start()']['respects `allowed_lines.blank`'] = function()
  start({ allowed_lines = { blank = false } })
  child.expect_screenshot()

  -- Should also use buffer local config
  child.lua('MiniJump2d.stop()')
  child.b.minijump2d_config = { allowed_lines = { blank = true } }
  start()
  child.expect_screenshot()
end

T['start()']['respects `allowed_lines.cursor_*`'] = new_set({
  parametrize = { { 'cursor_before' }, { 'cursor_at' }, { 'cursor_after' } },
}, {
  test = function(option_name)
    child.set_size(5, 40)

    -- Should affect all allowed windows and their cursor position
    setup_two_windows()

    local opts = { allowed_lines = {} }
    opts.allowed_lines[option_name] = false
    start(opts)
    child.expect_screenshot()

    -- Should also use buffer local config
    child.lua('MiniJump2d.stop()')
    opts.allowed_lines[option_name] = true
    child.b.minijump2d_config = opts
    start()
    child.expect_screenshot()
  end,
})

T['start()']['respects folds'] = function()
  -- Make fold on lines 2-3
  set_cursor(2, 0)
  type_keys('zf', 'j')
  eq({ child.fn.foldclosed(2), child.fn.foldclosed(3) }, { 2, 2 })
  set_cursor(1, 0)

  -- Validate
  start()
  child.expect_screenshot()

  -- Folds should still be present
  eq({ child.fn.foldclosed(2), child.fn.foldclosed(3) }, { 2, 2 })

  -- After jump should open enough folds to show cursor
  type_keys('c')
  child.expect_screenshot()
  eq(get_cursor(), { 2, 0 })
  eq({ child.fn.foldclosed(2), child.fn.foldclosed(3) }, { -1, -1 })
end

T['start()']['respects `allowed_lines.fold`'] = function()
  -- Make fold on lines 2-3
  set_cursor(2, 0)
  type_keys('zf', 'j')
  eq({ child.fn.foldclosed(2), child.fn.foldclosed(3) }, { 2, 2 })
  set_cursor(1, 0)

  -- Validate
  start({ allowed_lines = { fold = false } })
  child.expect_screenshot()

  -- Should also use buffer local config
  child.lua('MiniJump2d.stop()')
  child.b.minijump2d_config = { allowed_lines = { fold = true } }
  start()
  child.expect_screenshot()
end

T['start()']['respects `allowed_windows`'] = new_set({
  parametrize = { { { current = false } }, { { not_current = false } }, { { current = false, not_current = false } } },
}, {
  test = function(allowed_windows_opts)
    -- Check this only on Neovim>=0.11, as there is a slight change in
    -- highlighting command line area
    if child.fn.has('nvim-0.11') == 0 then return end

    child.set_size(6, 40)
    -- Make all showed messages full width
    child.o.cmdheight = 2

    local wins = setup_two_windows()
    child.api.nvim_set_current_win(wins.left)

    start({ allowed_windows = allowed_windows_opts })
    child.expect_screenshot()

    -- Shouldn't error in this case
    if allowed_windows_opts.current == false and allowed_windows_opts.not_current == false then
      eq(get_latest_message(), '(mini.jump2d) No spots to show.')
    end

    -- Should also use buffer local config
    child.lua('MiniJump2d.stop()')
    local opts = vim.deepcopy(allowed_windows_opts)
    opts.current, opts.not_current = not opts.current, not opts.not_current
    child.b.minijump2d_config = opts
    start()
    child.expect_screenshot()
  end,
})

T['start()']['ignores not focusable windows'] = function()
  child.set_size(6, 40)

  local create_float = function(focusable, col)
    local buf_id = child.api.nvim_create_buf(false, true)
    local l = 'xx' .. buf_id .. 'xx'
    child.api.nvim_buf_set_lines(buf_id, 0, -1, true, { l, l, l })
    local config = { relative = 'editor', row = 0, col = col, height = 3, width = 10, focusable = focusable }
    child.api.nvim_open_win(buf_id, false, config)
  end

  setup_two_windows()
  create_float(false, 9)
  create_float(true, 29)

  start({ allowed_windows = { current = true, not_current = true } })
  child.expect_screenshot()
end

T['start()']['respects `hooks`'] = function()
  child.lua('_G.n_before_start = 0; _G.n_after_jump = 0')

  child.lua([[MiniJump2d.start({
      hooks = {
        before_start = function() _G.n_before_start = _G.n_before_start + 1 end,
        after_jump = function() _G.n_after_jump = _G.n_after_jump + 1 end,
      },
    })]])
  eq(child.lua_get('{ _G.n_before_start, _G.n_after_jump }'), { 1, 0 })
  type_keys('<CR>')
  eq(child.lua_get('{ _G.n_before_start, _G.n_after_jump }'), { 1, 1 })

  child.lua('MiniJump2d.stop()')
  child.lua([[vim.b.minijump2d_config = {
    hooks = { before_start = function() _G.n_before_start = _G.n_before_start + 10 end }
  }]])
  start()
  eq(child.lua_get('{ _G.n_before_start, _G.n_after_jump }'), { 11, 1 })
  type_keys('<CR>')
  eq(child.lua_get('{ _G.n_before_start, _G.n_after_jump }'), { 11, 1 })
end

T['start()']['allows `hook.before_start` to modify spotter'] = function()
  child.lua('_G.opts = { spotter = function() return { 1 } end }')
  child.lua([[_G.opts.hooks = {
      before_start = function()
        _G.opts.spotter = function() return { 2 } end
      end
    }]])

  set_lines({ 'xxxx', 'xxxx' })
  child.lua('MiniJump2d.start(_G.opts)')
  child.expect_screenshot()
end

T['start()']['does not call `hook.after_jump` on jump cancel'] = new_set({
  parametrize = {
    { function() child.lua('MiniJump2d.stop()') end },
    { function() type_keys('<Esc>') end },
    { function() type_keys('<C-c>') end },
  },
}, {
  test = function(cancel_action)
    child.lua('_G.n_after_jump = 0')

    child.lua([[
      MiniJump2d.start({
        hooks = { after_jump = function() _G.n_after_jump = _G.n_after_jump + 1 end },
      })]])

    eq(child.lua_get('_G.n_after_jump'), 0)
    cancel_action()
    eq(child.lua_get('_G.n_after_jump'), 0)
  end,
})

local validate_hl_group = function(hl_group, hl_group_ahead)
  local ns_id = child.api.nvim_get_namespaces()['MiniJump2dSpots']
  local extmarks = child.api.nvim_buf_get_extmarks(0, ns_id, 0, -1, { details = true })

  local all_correct, all_correct_ahead = true, true
  for _, e_mark in ipairs(extmarks) do
    local virt_text = e_mark[4].virt_text
    if virt_text[1][2] ~= hl_group then all_correct = false end
    if virt_text[2] ~= nil and virt_text[2][2] ~= hl_group_ahead then all_correct_ahead = false end
  end

  eq(all_correct, true)
  eq(all_correct_ahead, true)
end

T['start()']['uses `MiniJump2dSpot` highlight group for next step by default'] = function()
  start({ labels = 'jk' })
  validate_hl_group('MiniJump2dSpot')
end

T['start()']['respects `opts.hl_group`'] = function()
  start({ labels = 'jk', hl_group = 'Search' })
  validate_hl_group('Search')
end

T['start()']['uses `MiniJump2dSpotAhead` highlight group by default'] = function()
  start({ labels = 'jk', view = { n_steps_ahead = 1 } })
  validate_hl_group('MiniJump2dSpot', 'MiniJump2dSpotAhead')
end

T['start()']['respects `opts.hl_group_ahead`'] = function()
  start({ labels = 'jk', view = { n_steps_ahead = 1 }, hl_group_ahead = 'Search' })
  validate_hl_group('MiniJump2dSpot', 'Search')
end

T['start()']['uses `MiniJump2dSpotUnique` highlight group for spots with unique next step'] = function()
  start()
  validate_hl_group('MiniJump2dSpotUnique')
end

T['start()']['respects `opts.hl_group_unique`'] = function()
  start({ hl_group_unique = 'Search' })
  validate_hl_group('Search')
end

T['start()']['uses `MiniJump2dDim` highlight group by default'] = function()
  local validate = function(line_numbers)
    local ns_id = child.api.nvim_get_namespaces()['MiniJump2dDim']
    local extmarks = child.api.nvim_buf_get_extmarks(0, ns_id, 0, -1, { details = true })

    for i, e_mark in ipairs(extmarks) do
      eq(e_mark[2], line_numbers[i] - 1)
    end
  end

  start({ labels = 'jk', view = { dim = true } })
  validate({ 1, 2, 3 })

  type_keys('j')
  validate({ 1, 2 })

  type_keys('j')
  validate({ 1 })
end

T['start()']['respects `opts.hl_group_dim`'] = function()
  -- At the moment, `nvim_buf_get_extmarks(..., { details = true })` doesn't
  -- return highlight group specified via `opts.line_hl_group`. So instead test
  -- directly by comparing highlighting in screenshot (should be different).
  local ns_id = child.api.nvim_create_namespace('test-dim')
  --stylua: ignore
  child.api.nvim_buf_set_extmark(
    0, ns_id, 2, 0,
    { hl_mode = 'combine', virt_text_pos = 'overlay', virt_text = { { 'dim', 'MiniJump2dDim' } } }
  )

  start({ labels = 'jk', view = { dim = true }, hl_group_dim = 'Search' })
  type_keys('j', 'j')

  -- Highlighting for first and second whole lines and first three columns of
  -- third line should be different: first is 'Search', second is 'Normal',
  -- third is 'MiniJump2dDim'.
  child.expect_screenshot()
end

T['start()']['respects `vim.{g,b}.minijump2d_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minijump2d_disable = true

    start()
    -- No spots should be shown
    child.expect_screenshot()
  end,
})

T['start()']['respects `config.silent`'] = function()
  child.lua('MiniJump2d.config.silent = true')
  child.set_size(10, 20)

  start()
  sleep(reminder_delay + small_time)

  -- Should not show helper message
  child.expect_screenshot()
end

T['stop()'] = new_set()

T['stop()']['works'] = function()
  child.set_size(10, 12)

  set_lines({ 'xxxx', 'xxxx' })
  child.lua('MiniJump2d.start()')
  child.expect_screenshot()

  child.lua('MiniJump2d.stop()')
  child.expect_screenshot()
end

T['stop()']['clears all highlighting'] = function()
  child.set_size(6, 12)

  set_lines({ 'xxxx', 'xxxx', '' })
  start({ view = { dim = true, n_steps_ahead = 1 }, allowed_lines = { blank = false } })
  child.expect_screenshot()

  child.lua('MiniJump2d.stop()')
  child.expect_screenshot()
end

T['stop()']['works even if not jumping'] = function()
  -- Shouldn't move
  local init_cursor = get_cursor()
  expect.no_error(function() child.lua('MiniJump2d.stop()') end)
  eq(get_cursor(), init_cursor)
end

T['gen_spotter'] = new_set()

T['gen_spotter']['pattern()'] = new_set({
  hooks = {
    pre_case = function()
      set_lines({ 'xxx x_x x.x xxx' })
      child.set_size(5, 20)
    end,
  },
})

local start_gen_pattern = function(pattern, side)
  local command = string.format(
    [[MiniJump2d.start({ spotter = MiniJump2d.gen_spotter.pattern(%s, %s) })]],
    vim.inspect(pattern),
    vim.inspect(side)
  )
  child.lua(command)
end

T['gen_spotter']['pattern()']['works'] = function()
  start_gen_pattern(nil, nil)
  -- By default it matches group of non-whitespace non-punctuation
  child.expect_screenshot()
end

T['gen_spotter']['pattern()']['respects `pattern` argument'] = function()
  start_gen_pattern('%s', nil)
  child.expect_screenshot()
end

T['gen_spotter']['pattern()']['respects `side` argument'] = new_set({
  parametrize = { { '%S+', 'start' }, { '%S+', 'end' }, { '.().', 'none' } },
}, {
  test = function(pattern, side)
    start_gen_pattern(pattern, side)
    child.expect_screenshot()
  end,
})

T['gen_spotter']['pattern()']['handles patterns with "^" and "$"'] = new_set({
  parametrize = {
    { '^...', 'start' },
    { '^...', 'end' },
    { '^.()..', 'none' },
    { '...$', 'start' },
    { '...$', 'end' },
    { '.()..$', 'none' },
  },
}, {
  test = function(pattern, side)
    set_lines({ 'xxx xxx', '', 'xx' })
    start_gen_pattern(pattern, side)
    child.expect_screenshot()
  end,
})

T['gen_spotter']['pattern()']['works with multibyte characters'] = function()
  set_lines({ 'ы ыыы ы_ы ыы' })
  start_gen_pattern('%S')
  child.expect_screenshot()

  child.lua('MiniJump2d.stop()')

  -- It should also work with three and four byte characters
  set_lines({ '███ 🬤🬤🬤 🬤█🬤 █🬤🬤🬤█' })
  start_gen_pattern('%S')
  child.expect_screenshot()
end

T['gen_spotter']['pattern()']['works in edge cases'] = function()
  start_gen_pattern('.%f[%W]')
  child.expect_screenshot()
end

T['gen_spotter']['vimpattern'] = new_set({
  hooks = {
    pre_case = function()
      set_lines({ 'x x xx_xx xx.xx xxx' })
      child.set_size(5, 20)
    end,
  },
})

local start_gen_vimpattern = function(pattern)
  local command =
    string.format([[MiniJump2d.start({ spotter = MiniJump2d.gen_spotter.vimpattern(%s) })]], vim.inspect(pattern))
  child.lua(command)
end

T['gen_spotter']['vimpattern']['works'] = function()
  start_gen_vimpattern()
  child.expect_screenshot()
  child.lua('MiniJump2d.stop()')

  child.o.iskeyword = child.o.iskeyword .. ',.'
  start_gen_vimpattern()
  child.expect_screenshot()
end

T['gen_spotter']['vimpattern']['respects `pattern` argument'] = function()
  start_gen_vimpattern('\\k*\\zs\\k')
  child.expect_screenshot()
end

T['gen_spotter']['vimpattern']['works with multibyte characters'] = function()
  set_lines({ 'ы ыыы ы_ы ыы.ыы ыы' })
  start_gen_vimpattern()
  child.expect_screenshot()
end

T['gen_spotter']['vimpattern']['works with anchored patterns'] = function()
  child.set_size(7, 20)
  child.api.nvim_buf_set_lines(0, 0, -1, false, { 'xxx xxx', 'xxx xxx', 'xx' })

  local validate = function(pattern)
    start_gen_vimpattern(pattern)
    child.expect_screenshot()
    child.lua('MiniJump2d.stop()')
  end

  validate('^')
  validate('$')
  validate('^...\\zs')
  validate('\\zs...$')
end

T['gen_spotter']['union()'] = new_set()

T['gen_spotter']['union()']['works'] = function()
  child.set_size(5, 25)

  child.lua([[
    local nonblank_start = MiniJump2d.gen_spotter.pattern('%S+', 'start')
    _G.args_log = {}
    _G.spotter_1 = function(...)
      table.insert(_G.args_log, { ... })
      return nonblank_start(...)
    end

    local word_start = MiniJump2d.gen_spotter.pattern('%w+', 'start')
    _G.spotter_2 = function(...)
      table.insert(_G.args_log, { ... })
      return word_start(...)
    end

    _G.union_spotter = MiniJump2d.gen_spotter.union(_G.spotter_1, _G.spotter_2)
  ]])

  set_lines({ 'xxx x_x x_x xxx' })
  child.lua('MiniJump2d.start({spotter = _G.union_spotter})')
  child.expect_screenshot()
end

T['gen_spotter']['union()']['validates arguments'] = function()
  expect.error(
    function() child.lua('MiniJump2d.gen_spotter.union(function() end, 1, function() end)') end,
    'All.*callable'
  )
end

T['gen_spotter']['union()']['works with no arguments'] = function()
  child.lua('_G.spotter = MiniJump2d.gen_spotter.union()')

  set_lines({ 'xxx x_x x_x xxx' })
  eq(child.lua_get('_G.spotter(1, {})'), {})
end

T['default_spotter()'] = new_set({
  hooks = {
    pre_case = function() child.set_size(5, 25) end,
  },
})

local start_default_spotter = function() child.lua('MiniJump2d.start({ spotter = MiniJump2d.default_spotter })') end

T['default_spotter()']['works'] = function()
  set_lines({ 'xxx x_x (x) xXXx xXXX' })
  start_default_spotter()
  child.expect_screenshot()
end

T['default_spotter()']['spots start and end of words'] = function()
  set_lines({ 'x xx xxx' })
  start_default_spotter()
  child.expect_screenshot()
end

T['default_spotter()']['spots before and after punctuation'] = function()
  set_lines({ 'xxx_____xxx (x)' })
  start_default_spotter()
  child.expect_screenshot()
end

T['default_spotter()']['spots first capital letter'] = function()
  set_lines({ 'XxxXXxxXXXx' })
  start_default_spotter()
  child.expect_screenshot()
end

T['default_spotter()']['correctly merges "overlapping" spots'] = function()
  set_lines({ 'XX () X_X' })
  start_default_spotter()
  child.expect_screenshot()
end

T['default_spotter()']['works (almost) with multibyte character'] = function()
  set_lines({ 'ы ыы ыыы ы_ы ыЫыы' })
  start_default_spotter()
  -- NOTE: ideally it should end with 'hi j' but 'Ы' is not recognized as
  -- capital letter in Lua patterns (because of different locale)
  child.expect_screenshot()
end

T['builtin_opts.line_start'] = new_set({ hooks = { pre_case = function() child.set_size(5, 12) end } })

T['builtin_opts.line_start']['works'] = function()
  set_lines({ 'xxx', '  xxx', '' })
  child.lua('MiniJump2d.start(MiniJump2d.builtin_opts.line_start)')
  child.expect_screenshot()

  -- It should jump to first non-blank character
  type_keys('b')
  eq(get_cursor(), { 2, 2 })
end

T['builtin_opts.word_start'] = new_set({ hooks = { pre_case = function() child.set_size(5, 20) end } })

T['builtin_opts.word_start']['works'] = function()
  set_lines({ 'x xx xx.xx _xx' })
  child.lua('MiniJump2d.start(MiniJump2d.builtin_opts.word_start)')
  child.expect_screenshot()
  child.lua('MiniJump2d.stop()')

  -- Should respect 'iskeyword' when computing word boundaries
  child.o.iskeyword = child.o.iskeyword .. ',.'
  child.lua('MiniJump2d.start(MiniJump2d.builtin_opts.word_start)')
  child.expect_screenshot()
end

T['builtin_opts.word_start']['works with multibyte characters'] = function()
  set_lines({ 'ы ыы ыы.ыы _ыы' })
  child.lua('MiniJump2d.start(MiniJump2d.builtin_opts.word_start)')
  child.expect_screenshot()
end

-- NOTE: For some reason, testing with screenshots is flaky when user input is
-- involved. Test with moving cursor instead.
T['builtin_opts.single_character'] = new_set()

local start_single_char = function() child.lua_notify('MiniJump2d.start(MiniJump2d.builtin_opts.single_character)') end

T['builtin_opts.single_character']['works'] = function()
  set_lines({ 'x_x y_y yyy' })
  start_single_char()
  type_keys(10, 'y', 'b')
  eq(get_cursor(), { 1, 6 })
end

T['builtin_opts.single_character']['works multibyte characters'] = function()
  set_lines({ 'xx ыы' })

  start_single_char()
  type_keys(10, 'ы', 'b')
  -- Here 5 is a byte column for second 'ы'
  eq(get_cursor(), { 1, 5 })
end

T['builtin_opts.single_character']['works with problematic characters'] = new_set({
  parametrize = { { '.' }, { '%' } },
}, {
  test = function(key)
    set_lines({ 'xxx ' .. key .. key })
    start_single_char()
    type_keys(10, key, 'b')
    eq(get_cursor(), { 1, 5 })
  end,
})

T['builtin_opts.single_character']['notifies if there is no spots'] = function()
  set_cursor(1, 0)
  set_lines({ 'xxx' })
  start_single_char()
  type_keys(10, 'y')

  eq(get_cursor(), { 1, 0 })
  eq(get_latest_message(), '(mini.jump2d) No spots to show.')
end

T['builtin_opts.single_character']['handles special user input'] = new_set({
  parametrize = { { '<C-c>' }, { '<Esc>' }, { '<CR>' } },
}, {
  test = function(key)
    set_cursor(1, 0)
    set_lines({ 'x_x y_y zzz' })
    start_single_char()
    type_keys(10, key)

    eq(get_cursor(), { 1, 0 })
    eq(get_latest_message(), '(mini.jump2d) No spots to show.')
  end,
})

T['builtin_opts.single_character']['shows reminder after one idle second'] = function()
  -- Helps create hit-enter-prompt
  child.set_size(5, 50)

  start_single_char()
  eq(get_latest_message(), '')
  sleep(reminder_delay - small_time)
  eq(get_latest_message(), '')
  sleep(small_time + small_time)

  -- Should show helper message without adding it to `:messages` and causing
  -- hit-enter-prompt
  eq(get_latest_message(), '')
  child.expect_screenshot()
end

-- NOTE: For some reason, testing with screenshots is flaky when user input is
-- involved. Test with moving cursor instead.
T['builtin_opts.query'] = new_set()

local start_query = function() child.lua_notify('MiniJump2d.start(MiniJump2d.builtin_opts.query)') end

T['builtin_opts.query']['works'] = function()
  set_lines({ 'xyzxy' })

  start_query()
  type_keys(10, 'xy<CR>', 'b')
  eq(get_cursor(), { 1, 3 })
end

T['builtin_opts.query']['works multibyte characters'] = function()
  set_lines({ 'xx ыы ыы' })

  start_query()
  type_keys(10, 'ыы<CR>', 'b')
  -- Here 8 is a byte column for second 'ыы'
  eq(get_cursor(), { 1, 8 })
end

T['builtin_opts.query']['works with problematic characters'] = new_set({
  parametrize = { { '..' }, { '%%' } },
}, {
  test = function(keys)
    set_lines({ 'xxx ' .. keys .. keys })
    start_query()
    type_keys(10, keys, '<CR>', 'b')
    eq(get_cursor(), { 1, 6 })
  end,
})

T['builtin_opts.query']['notifies if there is no spots'] = function()
  set_lines({ 'xyz' })
  set_cursor(1, 0)

  start_query()
  type_keys(10, 'yy', '<CR>')
  eq(get_cursor(), { 1, 0 })
  eq(get_latest_message(), '(mini.jump2d) No spots to show.')
end

T['builtin_opts.query']['handles special user input'] = new_set({
  parametrize = { { '<C-c>' }, { '<Esc>' } },
}, {
  test = function(key)
    set_lines({ 'xyz' })
    set_cursor(1, 0)

    start_query()
    type_keys(10, key, '<CR>')
    eq(get_cursor(), { 1, 0 })
    eq(get_latest_message(), '(mini.jump2d) No spots to show.')
  end,
})

T['builtin_opts.query']['matches all cells after immediate <CR> user input'] = function()
  set_lines({ 'xxxyyy' })

  start_query()
  type_keys(10, '<CR>', 'f')
  eq(get_cursor(), { 1, 5 })
end

T['builtin_opts.query']['works in edge cases'] = function()
  set_lines({ 'aaaaaa' })

  start_query()
  -- Should add only 3 spots
  type_keys(10, 'aa<CR>', 'c')
  eq(get_cursor(), { 1, 4 })
end

return T
