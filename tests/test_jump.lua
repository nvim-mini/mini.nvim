local helpers = dofile('tests/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('jump', config) end
local unload_module = function() child.mini_unload('jump') end
local reload_module = function(config) unload_module(); load_module(config) end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
local sleep = function(ms) helpers.sleep(ms, child, true) end
--stylua: ignore end

-- Data =======================================================================
local example_lines = {
  'Lorem ipsum dolor sit amet,',
  'consectetur adipiscing elit, sed do eiusmod tempor',
  'incididunt ut labore et dolore magna aliqua.',
  '`!@#$%^&*()_+=.,1234567890',
}

-- Time constants
local default_highlight_delay = 250
local reminder_delay = 1000
local small_time = helpers.get_time_const(10)

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      load_module()
    end,
    post_once = child.stop,
  },
  n_retry = helpers.get_n_retry(2),
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  -- Global variable
  eq(child.lua_get('type(_G.MiniJump)'), 'table')

  -- Autocommand group
  eq(child.fn.exists('#MiniJump'), 1)

  -- Highlight groups
  child.cmd('hi clear')
  load_module()
  expect.match(child.cmd_capture('hi MiniJump'), 'links to SpellRare')
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniJump.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniJump.config.' .. field), value) end

  -- Check default values
  expect_config('delay.highlight', 250)
  expect_config('delay.idle_stop', 10000000)
  expect_config('mappings.forward', 'f')
  expect_config('mappings.backward', 'F')
  expect_config('mappings.forward_till', 't')
  expect_config('mappings.backward_till', 'T')
  expect_config('mappings.repeat_jump', ';')
  expect_config('silent', false)
end

T['setup()']['respects `config` argument'] = function()
  unload_module()
  load_module({ delay = { highlight = 500 } })
  eq(child.lua_get('MiniJump.config.delay.highlight'), 500)
end

T['setup()']['validates `config` argument'] = function()
  unload_module()

  local expect_config_error = function(config, name, target_type)
    expect.error(function() load_module(config) end, vim.pesc(name) .. '.*' .. vim.pesc(target_type))
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ delay = 'a' }, 'delay', 'table')
  expect_config_error({ delay = { highlight = 'a' } }, 'delay.highlight', 'number')
  expect_config_error({ delay = { idle_stop = 'a' } }, 'delay.idle_stop', 'number')
  expect_config_error({ mappings = 'a' }, 'mappings', 'table')
  expect_config_error({ mappings = { forward = 1 } }, 'mappings.forward', 'string')
  expect_config_error({ mappings = { backward = 1 } }, 'mappings.backward', 'string')
  expect_config_error({ mappings = { forward_till = 1 } }, 'mappings.forward_till', 'string')
  expect_config_error({ mappings = { backward_till = 1 } }, 'mappings.backward_till', 'string')
  expect_config_error({ mappings = { repeat_jump = 1 } }, 'mappings.repeat_jump', 'string')
  expect_config_error({ silent = 1 }, 'silent', 'boolean')
end

T['setup()']['ensures colors'] = function()
  child.cmd('colorscheme default')
  expect.match(child.cmd_capture('hi MiniJump'), 'links to SpellRare')
end

T['setup()']['properly handles `config.mappings`'] = function()
  local has_map = function(lhs, pattern) return child.cmd_capture('nmap ' .. lhs):find(pattern) ~= nil end
  eq(has_map('f', 'Jump'), true)

  unload_module()
  child.api.nvim_del_keymap('n', 'f')

  -- Supplying empty string should mean "don't create keymap"
  load_module({ mappings = { forward = '' } })
  eq(has_map('f', 'Jump'), false)
end

T['state'] = new_set({
  hooks = {
    pre_case = function()
      child.lua('MiniJump.stop_jumping()')
      set_lines({ '1e2e3e4e' })
      set_cursor(1, 0)
    end,
  },
})

local get_state = function() return child.lua_get('MiniJump.state') end

T['state']['has correct initial values'] = function()
  eq(get_state(), {
    target = nil,
    backward = false,
    till = false,
    n_times = 1,
    mode = nil,
    jumping = false,
  })
end

T['state']['updates `target`'] = function()
  type_keys('f', 'e')
  eq(get_state().target, 'e')

  child.lua('MiniJump.stop_jumping()')
  child.lua([[MiniJump.jump('3e')]])
  eq(get_state().target, '3e')
end

T['state']['updates `backward`'] = function()
  set_cursor(1, 7)
  type_keys('F', 'e')
  eq(get_state().backward, true)

  type_keys('f')
  eq(get_state().backward, false)
end

T['state']['updates `till`'] = function()
  type_keys('t', 'e')
  eq(get_state().till, true)

  type_keys('f')
  eq(get_state().till, false)
end

T['state']['updates `n_times`'] = function()
  type_keys('2f', 'e')
  eq(get_state().n_times, 2)
end

T['state']['updates `mode`'] = function()
  type_keys('t', 'e')
  eq(get_state().mode, 'n')
  child.lua('MiniJump.stop_jumping()')

  type_keys('V', 't', 'e')
  eq(get_state().mode, 'V')
  child.ensure_normal_mode()

  type_keys('d', 't', 'e')
  eq(get_state().mode, 'nov')

  -- Ensure dot-repeat does not update mode after the jump
  type_keys('V', 't', 'e')
  eq(get_state().mode, 'V')
  child.ensure_normal_mode()
  type_keys('.')
  eq(get_state().mode, 'V')
end

T['state']['updates `jumping`'] = function()
  type_keys('f', 'e')
  eq(get_state().jumping, true)

  child.lua('MiniJump.stop_jumping()')
  eq(get_state().jumping, false)
end

T['jump()'] = new_set({
  hooks = {
    pre_case = function()
      set_lines(example_lines)
      set_cursor(1, 0)
    end,
  },
})

local validate_jump = function(args, final_cursor_pos)
  -- Usage of string arguments is needed because there seems to be no way to
  -- correctly transfer to `child` `nil` values between non-`nil` onces. Like
  -- `child.lua('MiniJump.jump(...)', {'m', nil, true})`. Gives `Cannot
  -- convert given lua table` error.
  child.lua(('MiniJump.jump(%s)'):format(args))
  eq(get_cursor(), final_cursor_pos)
end

T['jump()']['respects `target` argument'] = function()
  -- Can not jump by default without recent target
  expect.match(child.cmd_capture('lua MiniJump.jump()'), 'no recent `target`')

  -- Jump to one letter target
  validate_jump([['m']], { 1, 4 })

  -- By default uses latest used value
  validate_jump('', { 1, 10 })

  -- Accepts more than one letter
  validate_jump([['sit']], { 1, 18 })

  -- Accepts non-letters
  validate_jump([['!']], { 4, 1 })
  validate_jump([['1']], { 4, 16 })
end

T['jump()']['respects `backward` argument'] = function()
  -- Jumps forward by default at first jump
  validate_jump([['d']], { 1, 12 })

  -- Can jump backward
  validate_jump([['m', true]], { 1, 10 })

  -- By default uses latest used value
  validate_jump([['m']], { 1, 4 })
end

T['jump()']['respects `till` argument'] = function()
  -- Jumps on target by default at first jump
  validate_jump([['m']], { 1, 4 })

  -- Can jump till
  validate_jump([['m', nil, true]], { 1, 9 })

  -- By default uses latest used value
  validate_jump([['m']], { 1, 22 })
end

T['jump()']['respects `n_times` argument'] = function()
  -- Jumps once by default at first jump
  validate_jump([['m']], { 1, 4 })

  -- Can jump multiple times
  validate_jump([['m', nil, nil, 2]], { 1, 23 })

  -- By default uses latest used value
  validate_jump([['m']], { 2, 46 })
end

T['jump()']['allows matches at end of line when `till=true`'] = function()
  set_lines({ 'aaa', 'b', 'aaa' })

  local validate_t = function(start_pos, end_pos)
    set_cursor(unpack(start_pos))
    validate_jump([['b', false, true, 1]], end_pos)
  end
  local validate_T = function(start_pos, end_pos)
    set_cursor(unpack(start_pos))
    validate_jump([['b', true, true, 1]], end_pos)
  end

  -- Normal mode when not allowed to put cursor on end of line
  validate_t({ 1, 0 }, { 1, 2 })
  validate_T({ 3, 2 }, { 2, 0 })

  -- Visual mode (allowed to put cursor on end of line)
  type_keys('v')
  validate_t({ 1, 0 }, { 1, 3 })
  child.ensure_normal_mode()

  type_keys('v')
  validate_T({ 3, 2 }, { 2, 1 })
  child.ensure_normal_mode()

  -- Normal mode when allowed to put cursor on end of line
  child.o.virtualedit = 'onemore'
  validate_t({ 1, 0 }, { 1, 3 })
  validate_T({ 3, 2 }, { 2, 1 })
end

T['jump()']['does not jump if there is no place to jump'] = function() validate_jump([['x']], { 1, 0 }) end

T['jump()']['opens enough folds'] = function()
  set_lines({ 'a', 'b', 'c', 'd' })

  -- Manually create two nested closed folds
  set_cursor(3, 0)
  type_keys('zf', 'G')
  type_keys('zf', 'gg')
  eq(child.fn.foldlevel(1), 1)
  eq(child.fn.foldlevel(3), 2)
  eq(child.fn.foldclosed(2), 1)
  eq(child.fn.foldclosed(3), 1)

  -- Jumping should open just enough folds
  set_cursor(1, 0)
  validate_jump([['b']], { 2, 0 })
  eq(child.fn.foldclosed(2), -1)
  eq(child.fn.foldclosed(3), 3)
end

T['smart_jump()'] = new_set({
  hooks = {
    pre_case = function() set_lines(example_lines) end,
  },
})

T['smart_jump()']['works'] = function()
  child.lua_notify('MiniJump.smart_jump()')
  child.poke_eventloop()
  type_keys('m')
  eq(get_cursor(), { 1, 4 })
end

-- Integration tests ==========================================================
T['Jumping with f/t/F/T'] = new_set()

T['Jumping with f/t/F/T']['works in Normal and Visual modes'] = new_set({
  parametrize = {
    { 'Normal', 'f', { { 1, 2 }, { 1, 5 }, { 2, 5 }, { 3, 2 } } },
    { 'Normal', 't', { { 1, 1 }, { 1, 4 }, { 2, 4 }, { 3, 1 } } },
    { 'Normal', 'F', { { 3, 5 }, { 3, 2 }, { 2, 2 }, { 1, 5 } } },
    { 'Normal', 'T', { { 3, 6 }, { 3, 3 }, { 2, 3 }, { 1, 6 } } },

    { 'Visual', 'f', { { 1, 2 }, { 1, 5 }, { 2, 5 }, { 3, 2 } } },
    { 'Visual', 't', { { 1, 1 }, { 1, 4 }, { 2, 4 }, { 3, 1 } } },
    { 'Visual', 'F', { { 3, 5 }, { 3, 2 }, { 2, 2 }, { 1, 5 } } },
    { 'Visual', 'T', { { 3, 6 }, { 3, 3 }, { 2, 3 }, { 1, 6 } } },
  },
}, {
  test = function(test_mode, key, positions)
    set_lines({ '11e22e__', '33e44e__', '55e66e__' })

    local start_pos = key == key:lower() and { 1, 0 } or { 3, 7 }
    set_cursor(unpack(start_pos))

    if test_mode == 'Visual' then
      type_keys('v')
      eq(child.fn.mode(), 'v')
    end

    -- First time should jump and start "jumping" mode
    type_keys(key, 'e')
    eq(get_cursor(), positions[1])

    -- Typing same key should repeat jump
    type_keys(key)
    eq(get_cursor(), positions[2])

    -- Prepending with `count` should work
    type_keys('2', key)
    eq(get_cursor(), positions[3])

    -- Typing same key should ignore previous `count`
    type_keys(key)
    eq(get_cursor(), positions[4])
  end,
})

-- NOTE: for some reason it seems to be very important to do cases for
-- Operator-pending mode in parametrized form, because this way child process
-- is restarted every time. Otherwise it will lead to hanging process somewhere.
T['Jumping with f/t/F/T']['works in Operator-pending mode'] = new_set({
  parametrize = {
    { 'f', { '2e3e4e5e_ ', '4e5e_ ', '_ ' } },
    { 't', { 'e2e3e4e5e_ ', 'e4e5e_ ', 'e_ ' } },
    { 'F', { ' 1e2e3e4e5', ' 1e2e3', ' 1' } },
    { 'T', { ' 1e2e3e4e5e', ' 1e2e3e', ' 1e' } },
  },
}, {
  test = function(key, line_seq)
    set_lines({ ' 1e2e3e4e5e_ ' })

    local start_col = key == key:lower() and 0 or 12
    set_cursor(1, start_col)

    -- Apply once
    type_keys('d', key, 'e')
    eq(get_lines(), { line_seq[1] })

    -- Prepending with `count` should work
    type_keys('2d', key, 'e')
    eq(get_lines(), { line_seq[2] })

    -- Another prepending with `count` should work
    type_keys('d', '2', key, 'e')
    eq(get_lines(), { line_seq[3] })

    -- Just typing `key` shouldn't repeat motion
    local cur_pos = get_cursor()
    type_keys(key)
    eq(get_cursor(), cur_pos)
    -- Stop asking for user input
    type_keys('<Esc>')
  end,
})

T['Jumping with f/t/F/T']['allows dot-repeat'] = new_set({
  parametrize = { { 'f' }, { 't' }, { 'F' }, { 'T' } },
}, {
  test = function(key)
    -- Start with two equal lines (with enough targets) to check equal effect
    set_lines({ ' 1e2e3e4e_ ', ' 1e2e3e4e_ ' })

    local lines = get_lines()
    local start_col = key == key:lower() and 0 or lines[1]:len()
    set_cursor(1, start_col)

    type_keys('2d', key, 'e')

    -- Immediate dot-repeat
    type_keys('.')

    -- Not immediate dot-repeat
    set_cursor(2, start_col)
    type_keys('.', '.')

    -- Check equal effect
    lines = get_lines()
    eq(lines[1], lines[2])
  end,
})

T['Jumping with f/t/F/T']['stops jumping when non-jump movement is done'] = function()
  set_lines({ 'TF', ' 1e2e3e ', 'ft' })

  -- General idea: move once, make non-jump movement 'l', test typing `key`
  -- twice. Can't test once because it should ask for user input and make an
  -- actual movement to `key` letter.
  set_cursor(2, 0)
  type_keys('f', 'e', 'l', 'f', 'f')
  eq(get_cursor(), { 3, 0 })

  set_cursor(2, 0)
  type_keys('t', 'e', 'l', 't', 't')
  eq(get_cursor(), { 3, 0 })

  set_cursor(2, 7)
  type_keys('F', 'e', 'l', 'F', 'F')
  eq(get_cursor(), { 1, 1 })

  set_cursor(2, 7)
  type_keys('T', 'e', 'l', 'T', 'T')
  eq(get_cursor(), { 1, 1 })
end

T['Jumping with f/t/F/T']['works with different mappings'] = function()
  for _, key in ipairs({ 'f', 't', 'F', 'T' }) do
    child.api.nvim_del_keymap('n', key)
  end
  reload_module({ mappings = { forward = 'gf', backward = 'gF', forward_till = 'gt', backward_till = 'gT' } })
  set_lines({ ' 1e2e3e_ ' })

  set_cursor(1, 0)
  type_keys('gf', 'e')
  eq(get_cursor(), { 1, 2 })

  set_cursor(1, 0)
  type_keys('gt', 'e')
  eq(get_cursor(), { 1, 1 })

  set_cursor(1, 8)
  type_keys('gF', 'e')
  eq(get_cursor(), { 1, 6 })

  set_cursor(1, 8)
  type_keys('gT', 'e')
  eq(get_cursor(), { 1, 7 })
end

T['Jumping with f/t/F/T']['allows changing direction during jumping'] = function()
  set_lines({ ' 1e2e3e_ ' })

  -- After typing either one of ftFt, it should enter "jumping" mode, in
  -- which typing any of the five jump keys (including `;`) jumps around
  -- present targets.
  set_cursor(1, 0)
  type_keys('f', 'e', 't')
  eq(get_cursor(), { 1, 3 })

  set_cursor(1, 0)
  type_keys('2f', 'e', 'F')
  eq(get_cursor(), { 1, 2 })

  set_cursor(1, 8)
  type_keys('F', 'e', 'T')
  eq(get_cursor(), { 1, 5 })

  set_cursor(1, 8)
  type_keys('2F', 'e', 't')
  eq(get_cursor(), { 1, 5 })

  set_cursor(1, 0)
  type_keys('f', 'e', 'f', 'T', 't', 'F')
  eq(get_cursor(), { 1, 4 })
end

T['Jumping with f/t/F/T']['enters jumping mode even if first jump is impossible'] = function()
  set_lines({ '1e2e3e' })
  set_cursor(1, 0)

  -- There is no target in backward direction...
  type_keys('F', 'e')

  -- ...but it still should enter jumping mode because target is present
  type_keys('f', 'f')
  eq(get_cursor(), { 1, 3 })
end

T['Jumping with f/t/F/T']['does nothing if there is no place to jump'] = function()
  -- Normal mode
  local validate_normal = function(keys, start_col, ref_mode)
    set_lines({ 'abcdefg' })
    set_cursor(1, start_col)

    type_keys(keys, 'd')

    -- It shouldn't move anywhere and should not modify text
    eq(get_cursor(), { 1, start_col })
    eq(get_lines(), { 'abcdefg' })
    eq(child.fn.mode(), ref_mode)

    -- Ensure there is no jumping
    child.lua('MiniJump.stop_jumping()')
    child.ensure_normal_mode()
  end

  validate_normal('f', 4, 'n')
  validate_normal('t', 4, 'n')
  validate_normal('F', 2, 'n')
  validate_normal('T', 2, 'n')

  validate_normal('vf', 4, 'v')
  validate_normal('vt', 4, 'v')
  validate_normal('vF', 2, 'v')
  validate_normal('vT', 2, 'v')

  validate_normal('df', 4, 'n')
  validate_normal('dt', 4, 'n')
  validate_normal('dF', 2, 'n')
  validate_normal('dT', 2, 'n')
end

T['Jumping with f/t/F/T']['can be dot-repeated if did not jump at first'] = function()
  -- Normal mode
  local validate = function(keys, col_1, col_2, line_2)
    set_lines({ 'abcdefg' })
    set_cursor(1, col_1)

    type_keys(keys, 'd')
    eq(get_cursor(), { 1, col_1 })
    eq(get_lines(), { 'abcdefg' })

    set_cursor(1, col_2)
    type_keys('.')
    eq(get_lines(), { line_2 })

    -- Ensure there is no jumping
    child.lua('MiniJump.stop_jumping()')
    child.ensure_normal_mode()
  end

  validate('df', 5, 1, 'aefg')
  validate('dt', 5, 1, 'adefg')
  validate('dF', 1, 5, 'abcg')
  validate('dT', 1, 5, 'abcdg')
end

T['Jumping with f/t/F/T']['inside dot-repeat is not affected by regular jumping'] = function()
  local validate = function(keys, key_antagonist, result)
    local line = '_xdxdx1x1xdxdx_'
    local tests_forward = key_antagonist == string.upper(key_antagonist)

    set_lines({ line })
    set_cursor(1, tests_forward and 0 or (string.len(line) - 1))

    type_keys(keys)
    type_keys(tests_forward and '$' or '^')
    type_keys(key_antagonist, '1')
    type_keys('.')
    eq(get_lines(), { result })

    -- Ensure there is no jumping
    child.lua('MiniJump.stop_jumping()')
    child.ensure_normal_mode()
  end

  validate('2dfd', 'T', 'x1x1x_')
  validate('2dtd', 'F', 'dx1xdx_')
  validate('2dFd', 't', '_x1x1x')
  validate('2dTd', 'f', '_xdx1xd')
end

T['Jumping with f/t/F/T']['stops prompting for target if hit `<Esc>` or `<C-c>`'] = new_set({
  parametrize = {
    { 'f', '<Esc>' },
    { 't', '<Esc>' },
    { 'F', '<Esc>' },
    { 'T', '<Esc>' },
    { 'f', '<C-c>' },
    { 't', '<C-c>' },
    { 'F', '<C-c>' },
    { 'T', '<C-c>' },
  },
}, {
  test = function(key, test_key)
    set_lines({ 'oooo' })
    set_cursor(1, 0)
    -- Here 'o' should act just like Normal mode 'o'
    -- Wait after every key to poke eventloop
    type_keys(1, key, test_key, 'o')
    eq(get_lines(), { 'oooo', '' })

    child.ensure_normal_mode()

    -- Should also work in Operator-pending mode
    set_lines({ 'oooo' })
    set_cursor(1, 0)
    type_keys(1, 'd', key, test_key, 'o')
    eq(get_lines(), { 'oooo', '' })
  end,
})

T['Jumping with f/t/F/T']['ignores current position if it is acceptable target'] = new_set({
  parametrize = { { 'f' }, { 't' }, { 'F' }, { 'T' } },
}, {
  test = function(key)
    set_lines({ 'xxxx' })
    local start_col, finish_col = 0, 1
    if key ~= key:lower() then
      start_col, finish_col = 3, 2
    end
    set_cursor(1, start_col)

    type_keys(key, 'x')
    eq(get_cursor(), { 1, finish_col })
  end,
})

T['Jumping with f/t/F/T']['for t/T allows matches on end of line'] = function()
  set_lines({ 'aaa', 'b', 'aaa' })

  local validate_t = function(start_pos, end_pos)
    set_cursor(unpack(start_pos))
    type_keys('t', 'b')
    eq(get_cursor(), end_pos)
  end
  local validate_T = function(start_pos, end_pos)
    set_cursor(unpack(start_pos))
    type_keys('T', 'b')
    eq(get_cursor(), end_pos)
  end

  -- Normal mode when not allowed to put cursor on end of line
  validate_t({ 1, 0 }, { 1, 2 })
  validate_T({ 3, 2 }, { 2, 0 })

  -- Visual mode (allowed to put cursor on end of line)
  type_keys('v')
  validate_t({ 1, 0 }, { 1, 3 })
  child.ensure_normal_mode()

  type_keys('v')
  validate_T({ 3, 2 }, { 2, 1 })
  child.ensure_normal_mode()

  -- Normal mode when allowed to put cursor on end of line
  child.o.virtualedit = 'onemore'
  validate_t({ 1, 0 }, { 1, 3 })
  validate_T({ 3, 2 }, { 2, 1 })
end

T['Jumping with f/t/F/T']['shows reminder after one idle second'] = function()
  child.set_size(10, 40)

  -- Execute one time to test if 'needs help message' flag is set per call
  set_lines(example_lines)
  set_cursor(1, 0)
  type_keys('f', 'e')
  sleep(0.5 * reminder_delay)

  -- Start another jump
  type_keys('h', 'f')
  sleep(reminder_delay + small_time)
  -- Should show colored helper message without adding it to `:messages` and
  -- causing hit-enter-prompt
  child.expect_screenshot()
  eq(child.cmd_capture('1messages'), '')

  -- Should clean command line after starting jumping
  type_keys('m')
  child.expect_screenshot()
end

T['Jumping with f/t/F/T']['stops jumping if no target is found'] = function()
  set_lines('ooo')

  -- General idea: there was a bug which didn't reset jumping state if target
  -- was not found by `vim.fn.search()`. In that case, next typing of jumping
  -- key wouldn't make effect, but it should.
  for _, key in ipairs({ 'f', 't', 'F', 'T' }) do
    local start_col = key == key:lower() and 0 or 3
    set_cursor(1, start_col)
    type_keys(key, 'e', key, 'o')
    eq(get_cursor(), { 1, 1 })
    -- Ensure no jumping mode
    child.lua('MiniJump.stop_jumping()')
  end
end

T['Jumping with f/t/F/T']['jumps as far as it can with big `count`'] = function()
  set_lines({ ' 1e2e3e4e_ ' })

  set_cursor(1, 0)
  type_keys('10f', 'e')
  eq(get_cursor(), { 1, 8 })

  set_cursor(1, 0)
  type_keys('10t', 'e')
  eq(get_cursor(), { 1, 7 })

  set_cursor(1, 10)
  type_keys('10F', 'e')
  eq(get_cursor(), { 1, 2 })

  set_cursor(1, 10)
  type_keys('10T', 'e')
  eq(get_cursor(), { 1, 3 })
end

T['Jumping with f/t/F/T']['respects `vim.{g,b}.minijump_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minijump_disable = true
    set_lines({ '1e2e3e4e' })
    set_cursor(1, 0)
    type_keys('f', 'e')
    -- `f` does nothing, while `e` jumps to end of word (otherwise it would
    -- have been `{1, 1}`)
    eq(get_cursor(), { 1, 7 })
  end,
})

T['Jumping with f/t/F/T']['respects `config.silent`'] = function()
  child.lua('MiniJump.config.silent = true')
  child.set_size(10, 20)

  -- Execute one time to test if 'needs help message' flag is set per call
  set_lines({ '1e2e3e4e' })
  set_cursor(1, 0)
  type_keys('f')
  sleep(reminder_delay + small_time)

  -- Should not show helper message
  child.expect_screenshot()
end

T['Jumping with f/t/F/T']["respects 'ignorecase'"] = function()
  child.o.ignorecase = true
  set_lines({ ' 1e2E3E4e_ ' })

  set_cursor(1, 0)
  type_keys('2f', 'E')
  eq(get_cursor(), { 1, 4 })

  set_cursor(1, 0)
  type_keys('2t', 'E')
  eq(get_cursor(), { 1, 3 })

  set_cursor(1, 10)
  type_keys('2F', 'E')
  eq(get_cursor(), { 1, 6 })

  set_cursor(1, 10)
  type_keys('2T', 'E')
  eq(get_cursor(), { 1, 7 })
end

T['Jumping with f/t/F/T']["respects 'smartcase'"] = function()
  child.o.ignorecase = true
  child.o.smartcase = true
  set_lines({ ' 1e2E3E4e_ ' })

  set_cursor(1, 0)
  type_keys('2f', 'E')
  eq(get_cursor(), { 1, 6 })

  set_cursor(1, 0)
  type_keys('2t', 'E')
  eq(get_cursor(), { 1, 5 })

  set_cursor(1, 10)
  type_keys('2F', 'E')
  eq(get_cursor(), { 1, 4 })

  set_cursor(1, 10)
  type_keys('2T', 'E')
  eq(get_cursor(), { 1, 5 })
end

T['Jumping with f/t/F/T']["respects 'selection=exclusive'"] = function()
  child.o.selection = 'exclusive'
  set_lines({ ' 1e2e' })

  set_cursor(1, 0)
  type_keys('v', 'f', 'e')
  eq({ child.fn.col('v'), child.fn.col('.') }, { 1, 4 })

  type_keys('d')
  eq(get_lines(), { '2e' })
end

T['Jumping with f/t/F/T']['can be used with `:normal-range`'] = function()
  -- Basically, it should check that jumping state is restarted even outside of
  -- `CursorMoved` event (which is not issued in this case)
  set_lines({ '11e22e', '11e22e', '11e22e' })
  set_cursor(1, 0)
  type_keys('vip', ':normal fefx<CR>')
  eq(get_lines(), { '11e22', '11e22', '11e22' })
end

T['Repeat jump with ;'] = new_set()

T['Repeat jump with ;']['works'] = function()
  set_lines({ ' 1e2e3e4e_ ' })

  set_cursor(1, 0)
  type_keys('f', 'e', ';')
  eq(get_cursor(), { 1, 4 })

  set_cursor(1, 0)
  type_keys('t', 'e', ';')
  eq(get_cursor(), { 1, 3 })

  set_cursor(1, 10)
  type_keys('F', 'e', ';')
  eq(get_cursor(), { 1, 6 })

  set_cursor(1, 10)
  type_keys('T', 'e', ';')
  eq(get_cursor(), { 1, 7 })
end

-- Other tests are done with 'f' in hope that others keys act the same
T['Repeat jump with ;']['works in Normal and Visual mode'] = new_set({
  parametrize = { { 'Normal' }, { 'Visual' } },
}, {
  test = function(test_mode)
    set_lines({ '1e2e3e4e' })

    if test_mode == 'Visual' then
      type_keys('v')
      eq(child.fn.mode(), 'v')
    end

    -- Repeats simple motion
    set_cursor(1, 0)
    type_keys('f', 'e', ';')
    eq(get_cursor(), { 1, 3 })

    -- Repeats not immediately
    set_cursor(1, 0)
    type_keys(';')
    eq(get_cursor(), { 1, 1 })

    -- Repeats with `count`
    set_cursor(1, 0)
    type_keys('2f', 'e', ';')
    eq(get_cursor(), { 1, 7 })
  end,
})

T['Repeat jump with ;']['works after jump in Operator-pending mode'] = function()
  -- It doesn't repeat actual operation, just performs same jump
  set_lines({ '1e2e3e4e5e' })
  set_cursor(1, 0)

  type_keys('d', 'f', 'e', ';')
  eq(get_lines(), { '2e3e4e5e' })
  eq(get_cursor(), { 1, 1 })

  -- It jumps preserving `count`
  set_lines({ '1e2e3e4e5e' })
  set_cursor(1, 0)

  type_keys('d', '2f', 'e', ';')
  eq(get_lines(), { '3e4e5e' })
  eq(get_cursor(), { 1, 3 })

  -- Should not use the latest dot repeat (like in `nvim --clean`)
  set_lines({ '1e2e__3e4e5e6e' })
  set_cursor(1, 0)

  type_keys('d', '2f', 'e')
  eq(get_lines(), { '__3e4e5e6e' })
  eq(get_cursor(), { 1, 0 })

  type_keys('$', 'T', '_')
  eq(get_lines(), { '__3e4e5e6e' })
  eq(get_cursor(), { 1, 2 })

  -- - Should reuse initial Operator-pending mode state and not the latest one
  type_keys('.')
  eq(get_lines(), { '__5e6e' })
  eq(get_cursor(), { 1, 2 })

  -- - The latest one should still be preserved for regular jumping
  type_keys(';')
  eq(get_lines(), { '__5e6e' })
  eq(get_cursor(), { 1, 1 })
end

T['Repeat jump with ;']['works in Operator-pending mode'] = function()
  set_lines({ '1e2e3e4e5e_' })
  set_cursor(1, 0)

  -- Should repeat without asking for target
  type_keys('f', 'e', 'd', ';')
  eq(get_lines(), { '13e4e5e_' })
  eq(get_cursor(), { 1, 1 })

  -- Should work with dot-repeat as in `nvim --clean`, i.e. use target from the
  -- latest jump, as `;` is exactly for that
  type_keys('.')
  eq(get_lines(), { '14e5e_' })
  eq(get_cursor(), { 1, 1 })

  type_keys('f', '_', '^')
  type_keys('.')
  eq(get_lines(), { '' })
  eq(get_cursor(), { 1, 0 })
end

T['Repeat jump with ;']['works with different mapping'] = function()
  child.api.nvim_del_keymap('n', ';')
  reload_module({ mappings = { repeat_jump = 'g;' } })

  set_lines({ '1e2e' })
  type_keys('f', 'e', 'g;')
  eq(get_cursor(), { 1, 3 })
end

T['Repeat jump with ;']['works not immediately after failed first jump'] = function()
  set_lines({ 'aaa' })
  set_cursor(1, 0)
  type_keys('f', 'e')
  eq(get_cursor(), { 1, 0 })

  set_lines({ 'aaa', 'eee' })
  set_cursor(1, 0)
  type_keys(';')
  eq(get_cursor(), { 2, 0 })
end

T['Repeat jump with ;']['respects `vim.{g,b}.minijump_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    set_lines({ '1e2e3e4e' })
    set_cursor(1, 0)
    type_keys('f', 'e')

    child[var_type].minijump_disable = true
    type_keys(';')
    eq(get_cursor(), { 1, 1 })
  end,
})

T['Delayed highlighting'] = new_set({
  hooks = {
    pre_case = function()
      set_lines({ '1e2e', 'e4e5e_' })
      child.set_size(5, 12)
    end,
  },
})

-- NOTE: Don't use `'f', 't', 'F', 'T'` as parameters because this will lead to
-- conflicting file names for reference screenshots in case-insensitive OS
T['Delayed highlighting']['works'] = new_set(
  { parametrize = { { 'forward' }, { 'forward_till' }, { 'backward' }, { 'backward_till' } } },
  {
    test = function(direction)
      local key = vim.endswith(direction, '_till') and 't' or 'f'
      key = vim.startswith(direction, 'backward') and key:upper() or key

      set_cursor(1, key == key:lower() and 0 or 3)
      type_keys(key, 'e')

      sleep(default_highlight_delay - small_time)
      -- Nothing should yet be shown
      child.expect_screenshot()
      sleep(small_time)
      -- Everything should be shown
      child.expect_screenshot()
    end,
  }
)

T['Delayed highlighting']['respects `config.delay.highlight`'] = new_set(
  { parametrize = { { 'forward' }, { 'forward_till' }, { 'backward' }, { 'backward_till' } } },
  {
    test = function(direction)
      local key = vim.endswith(direction, '_till') and 't' or 'f'
      key = vim.startswith(direction, 'backward') and key:upper() or key

      local new_highlight_delay = 5 * small_time
      child.lua('MiniJump.config.delay.highlight = ' .. new_highlight_delay)

      set_cursor(1, key == key:lower() and 0 or 3)
      type_keys(key, 'e')

      sleep(new_highlight_delay - small_time)
      -- Nothing should yet be shown
      child.expect_screenshot()
      sleep(small_time)
      -- Everything should be shown
      child.expect_screenshot()
    end,
  }
)

T['Delayed highlighting']['respects `vim.b.minijump_config`'] = function()
  child.lua('MiniJump.config.delay.highlight = ' .. (5 * small_time))
  local new_highlight_delay = 3 * small_time
  child.b.minijump_config = { delay = { highlight = new_highlight_delay } }

  set_cursor(1, 0)
  type_keys('f', 'e')

  sleep(new_highlight_delay - small_time)
  -- Nothing should yet be shown
  child.expect_screenshot()
  sleep(small_time)
  -- Everything should be shown
  child.expect_screenshot()
end

T['Delayed highlighting']['implements debounce-style delay'] = function()
  set_lines('1e2e3e')
  set_cursor(1, 0)

  type_keys('f', 'e')
  sleep(default_highlight_delay - small_time)
  -- Nothing should yet be shown
  child.expect_screenshot()

  type_keys('f')
  sleep(default_highlight_delay - small_time)
  -- Nothing should yet be shown (because debounce-style)
  child.expect_screenshot()

  sleep(small_time)
  -- Nothing should yet be shown
  child.expect_screenshot()
end

T['Delayed highlighting']['stops immediately when not jumping'] = function()
  type_keys('f', 'e')
  sleep(default_highlight_delay)
  -- Should be highlighted
  child.expect_screenshot()

  type_keys('l')
  -- Should stop highlighting immediately
  child.expect_screenshot()
end

T['Delayed highlighting']['updates immediately within same jumping'] = function()
  set_lines({ 'e1e2', 'ee' })

  set_cursor(1, 0)
  type_keys('f', 'e')

  sleep(default_highlight_delay)
  child.expect_screenshot()
  type_keys('t')
  child.expect_screenshot()
  type_keys('T')
  -- Last `T` match is highlighted because there is an end of line after it
  child.expect_screenshot()
end

T['Delayed highlighting']['never highlights in Insert mode'] = function()
  child.set_size(5, 15)

  set_lines({ '1e2f' })

  set_cursor(1, 0)
  type_keys('f', 'e')

  sleep(default_highlight_delay)
  child.expect_screenshot()

  type_keys('ct', 'f')
  sleep(default_highlight_delay + small_time)
  -- Shouldn't start highlighting
  child.expect_screenshot()
end

T['Delayed highlighting']["respects 'ignorecase'"] = function()
  child.o.ignorecase = true
  set_lines({ '1e2E' })

  set_cursor(1, 0)
  type_keys('f', 'e')

  sleep(default_highlight_delay)
  -- Should highlight both 'e'and 'E'
  child.expect_screenshot()
end

T['Delayed highlighting']["respects 'smartcase'"] = function()
  child.o.ignorecase = true
  child.o.smartcase = true
  set_lines({ '1e2E3e4E' })

  set_cursor(1, 0)
  type_keys('f', 'E')

  sleep(default_highlight_delay)
  -- Should highlight only 'E'
  child.expect_screenshot()
end

T['Stop jumping after idle'] = new_set({
  hooks = {
    pre_case = function()
      child.lua('MiniJump.config.delay.idle_stop = ' .. (default_highlight_delay + 2 * small_time))
      set_lines({ '1e2e3e4e', 'ff' })
      set_cursor(1, 0)
      child.set_size(5, 12)
    end,
  },
})

T['Stop jumping after idle']['works'] = function()
  local idle_stop_delay = child.lua_get('MiniJump.config.delay.idle_stop')
  type_keys('f', 'e')
  eq(get_cursor(), { 1, 1 })

  -- It works
  sleep(idle_stop_delay - small_time)
  type_keys('f')
  eq(get_cursor(), { 1, 3 })
  -- Should highlight (as idle delay is bigger than highlight delay)
  child.expect_screenshot()

  -- It implements debounce-style delay
  sleep(idle_stop_delay + small_time)
  -- It should have stopped jumping and this should initiate new jump
  type_keys('f', 'f')
  eq(get_cursor(), { 2, 0 })
  -- Should also stop highlighting
  child.expect_screenshot()
end

T['Stop jumping after idle']['works if should be done before target highlighting'] = function()
  child.lua('MiniJump.config.delay.idle_stop = ' .. (default_highlight_delay - small_time))

  type_keys('f', 'e')
  eq(get_cursor(), { 1, 1 })
  sleep(default_highlight_delay + small_time)
  -- Should also not trigger highlighting
  child.expect_screenshot()
end

T['Stop jumping after idle']['respects `vim.b.minijump_config`'] = function()
  local idle_stop_delay = child.lua_get('MiniJump.config.delay.idle_stop')
  local new_idle_stop_delay = idle_stop_delay - 2 * small_time
  child.b.minijump_config = { delay = { idle_stop = new_idle_stop_delay } }
  type_keys('f', 'e')
  sleep(new_idle_stop_delay)

  -- It should have stopped jumping and this should initiate new jump
  type_keys('f', 'f')
  eq(get_cursor(), { 2, 0 })
end

T['Events'] = new_set({
  hooks = {
    pre_case = function()
      child.lua([[
        _G.log = {}
        local pattern = { 'MiniJumpGetTarget', 'MiniJumpStart', 'MiniJumpJump', 'MiniJumpStop' }
        local add_to_log = function(ev)
          table.insert(_G.log, { event = ev.match, data = ev.data, state = vim.deepcopy(MiniJump.state) })
        end
        vim.api.nvim_create_autocmd('User', { pattern = pattern, callback = add_to_log })
      ]])

      set_lines({ '11e22e__', '33e44e__', '55e66e__' })
    end,
  },
})

local validate_log_and_clean = function(ref_log)
  eq(child.lua_get('_G.log'), ref_log)
  child.lua('_G.log = {}')
end

T['Events']['work'] = function()
  local state = { mode = 'n', jumping = false, backward = false, till = false, n_times = 1 }
  type_keys('f')
  validate_log_and_clean({ { event = 'MiniJumpGetTarget', state = state } })

  type_keys('e')
  state.jumping, state.target = true, 'e'
  validate_log_and_clean({
    { event = 'MiniJumpStart', state = state },
    { event = 'MiniJumpJump', state = state },
  })

  local validate_key = function(keys, ref_backward, ref_till)
    state.backward, state.till = ref_backward, ref_till
    type_keys(keys)
    validate_log_and_clean({ { event = 'MiniJumpJump', state = state } })
  end
  validate_key('f', false, false)
  validate_key('F', true, false)
  validate_key('t', false, true)
  validate_key('T', true, true)

  state.backward, state.till, state.n_times = false, false, 2
  type_keys('2f')
  validate_log_and_clean({ { event = 'MiniJumpJump', state = state } })

  child.lua('MiniJump.stop_jumping()')
  state.jumping = false
  validate_log_and_clean({ { event = 'MiniJumpStop', state = state } })
end

T['Events']['work in Visual and Operator-pending modes'] = function()
  local validate = function(mode, ref_init_target)
    local state = { mode = mode, jumping = false, backward = false, till = false, n_times = 1 }
    state.target = ref_init_target

    local mode_key = mode == 'v' and 'v' or 'd'
    type_keys(mode_key, 'f')
    validate_log_and_clean({ { event = 'MiniJumpGetTarget', state = state } })

    type_keys('e')
    state.mode = mode == 'v' and 'v' or 'nov'
    state.jumping, state.target = true, 'e'
    validate_log_and_clean({
      { event = 'MiniJumpStart', state = state },
      { event = 'MiniJumpJump', state = state },
    })

    child.lua('MiniJump.stop_jumping()')
    state.jumping = false
    validate_log_and_clean({ { event = 'MiniJumpStop', state = state } })

    type_keys('<Esc>')
  end

  -- Visual mode
  validate('v', nil)

  -- Operator-pending mode. In `state` target is preserved as it is cached for
  -- possible future `;`.
  validate('no', 'e')
end

T['Events']['work for automatic jump stop'] = function()
  -- Moving cursor outside of jumping
  type_keys('f', 'e')
  child.lua('_G.log = {}')

  type_keys('l')
  local state = { target = 'e', mode = 'n', jumping = false, backward = false, till = false, n_times = 1 }
  validate_log_and_clean({ { event = 'MiniJumpStop', state = state } })

  -- Enter Insert mode
  type_keys('f', 'e')
  child.lua('_G.log = {}')

  type_keys('i')
  validate_log_and_clean({ { event = 'MiniJumpStop', state = state } })
  type_keys('<Esc>')

  -- Idle stop
  local idle_stop = 10 * small_time
  child.lua('MiniJump.config.delay.idle_stop = ' .. idle_stop)
  type_keys('f', 'e')
  child.lua('_G.log = {}')

  sleep(idle_stop - small_time)
  validate_log_and_clean({})
  sleep(small_time + small_time)
  validate_log_and_clean({ { event = 'MiniJumpStop', state = state } })
end

T['Events']['have up to date state before asking for target'] = function()
  local validate = function(keys, ref_state)
    type_keys(keys)
    validate_log_and_clean({ { event = 'MiniJumpGetTarget', state = ref_state } })
    type_keys('<Esc>', '<Esc>')
  end

  local state = { mode = 'n', jumping = false, backward = false, till = false, n_times = 1 }
  validate('f', state)

  state.n_times = 2
  validate('2f', state)
  state.n_times = 1

  state.mode, state.backward, state.till = 'v', true, false
  validate('vF', state)

  state.mode, state.backward, state.till = 'no', false, true
  validate('dt', state)
end

T['Events']['work during repeat with `;`'] = function()
  type_keys('f', 'e')
  child.lua('MiniJump.stop_jumping()')
  child.lua('_G.log = {}')

  eq(child.lua_get('MiniJump.state.jumping'), false)

  local state = { mode = 'n', jumping = true, target = 'e', backward = false, till = false, n_times = 1 }
  type_keys(';')
  validate_log_and_clean({
    { event = 'MiniJumpStart', state = state },
    { event = 'MiniJumpJump', state = state },
  })

  type_keys(';')
  validate_log_and_clean({ { event = 'MiniJumpJump', state = state } })

  type_keys('T')
  state.backward, state.till = true, true
  validate_log_and_clean({ { event = 'MiniJumpJump', state = state } })

  type_keys(';')
  validate_log_and_clean({ { event = 'MiniJumpJump', state = state } })
end

T['Events']['work with dot-repeat'] = function()
  type_keys('df', 'e')
  child.lua('MiniJump.stop_jumping()')
  child.lua('_G.log = {}')

  type_keys('.')
  local state = { mode = 'nov', jumping = true, target = 'e', backward = false, till = false, n_times = 1 }
  validate_log_and_clean({
    { event = 'MiniJumpStart', state = state },
    { event = 'MiniJumpJump', state = state },
  })
end

return T
