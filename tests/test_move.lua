local helpers = dofile('tests/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
local load_module = function(config) child.mini_load('move', config) end
local unload_module = function() child.mini_unload('move') end
--stylua: ignore
local reload_module = function(config) unload_module(); load_module(config) end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end

local get_fold_range = function(line_num) return { child.fn.foldclosed(line_num), child.fn.foldclosedend(line_num) } end

local setup_registers = function()
  local reginfo_arr = {
    { reg = '0', info = { regcontents = { '0', '0', '0' }, regtype = '\0221' } },
    { reg = '1', info = { regcontents = { '111', '111' }, regtype = 'V' } },
    { reg = '2', info = { regcontents = { '222', '222' }, regtype = 'V' } },
    { reg = '9', info = { regcontents = { '999', '999' }, regtype = 'V' } },
    { reg = '-', info = { regcontents = { '---' }, regtype = 'v' } },
    { reg = 'z', info = { regcontents = { 'zzz' }, regtype = 'v' } },
    { reg = '"', info = { points_to = 'z' } },
  }
  local ref = {}
  for _, data in ipairs(reginfo_arr) do
    child.fn.setreg(data.reg, data.info)
    ref[data.reg] = child.fn.getreginfo(data.reg)
  end
  -- Make sure that 'z' register has proper `isunnamed` field
  ref['z'] = child.fn.getreginfo('z')

  return ref
end

local validate_state = function(lines, selection)
  eq(get_lines(), lines)
  eq({ { child.fn.line('v'), child.fn.col('v') }, { child.fn.line('.'), child.fn.col('.') } }, selection)
end

local validate_state1d = function(line, range) validate_state({ line }, { { 1, range[1] }, { 1, range[2] } }) end

local validate_line_state = function(lines, cursor)
  eq(get_lines(), lines)
  eq(get_cursor(), cursor)
end

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      load_module()
    end,
    post_once = child.stop,
  },
  n_retry = helpers.get_n_retry(1),
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  -- Global variable
  eq(child.lua_get('type(_G.MiniMove)'), 'table')
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniMove.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniMove.config.' .. field), value) end

  -- Check default values
  expect_config('mappings.left', '<M-h>')
  expect_config('mappings.right', '<M-l>')
  expect_config('mappings.down', '<M-j>')
  expect_config('mappings.up', '<M-k>')
  expect_config('mappings.line_left', '<M-h>')
  expect_config('mappings.line_right', '<M-l>')
  expect_config('mappings.line_down', '<M-j>')
  expect_config('mappings.line_up', '<M-k>')
  expect_config('options.reindent_linewise', true)
end

T['setup()']['respects `config` argument'] = function()
  reload_module({ make_global = { 'put' } })
  eq(child.lua_get('MiniMove.config.make_global'), { 'put' })
end

T['setup()']['validates `config` argument'] = function()
  unload_module()

  local expect_config_error = function(config, name, target_type)
    expect.error(function() load_module(config) end, vim.pesc(name) .. '.*' .. vim.pesc(target_type))
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ mappings = 'a' }, 'mappings', 'table')
  expect_config_error({ mappings = { left = 1 } }, 'mappings.left', 'string')
  expect_config_error({ mappings = { down = 1 } }, 'mappings.down', 'string')
  expect_config_error({ mappings = { up = 1 } }, 'mappings.up', 'string')
  expect_config_error({ mappings = { right = 1 } }, 'mappings.right', 'string')
  expect_config_error({ mappings = { line_left = 1 } }, 'mappings.line_left', 'string')
  expect_config_error({ mappings = { line_right = 1 } }, 'mappings.line_right', 'string')
  expect_config_error({ mappings = { line_down = 1 } }, 'mappings.line_down', 'string')
  expect_config_error({ mappings = { line_up = 1 } }, 'mappings.line_up', 'string')
  expect_config_error({ options = 'a' }, 'options', 'table')
  expect_config_error({ options = { reindent_linewise = 1 } }, 'options.reindent_linewise', 'boolean')
end

T['setup()']['properly handles `config.mappings`'] = function()
  local has_map = function(lhs, pattern) return child.cmd_capture('xmap ' .. lhs):find(pattern) ~= nil end
  eq(has_map('<M-h>', 'MiniMove'), true)

  unload_module()
  child.api.nvim_del_keymap('x', '<M-h>')

  -- Supplying empty string should mean "don't create keymap"
  load_module({ mappings = { left = '' } })
  eq(has_map('<M-h>', 'MiniMove'), false)
end

T['move_selection()'] = new_set()

local move = function(direction, opts) child.lua('MiniMove.move_selection(...)', { direction, opts }) end

T['move_selection()']['works charwise horizontally'] = function()
  -- Test for this many moves because there can be special cases when movement
  -- involves second or second to last character
  set_lines({ 'XXabcd' })
  set_cursor(1, 0)
  type_keys('vl')
  validate_state1d('XXabcd', { 1, 2 })

  move('right')
  validate_state1d('aXXbcd', { 2, 3 })
  move('right')
  validate_state1d('abXXcd', { 3, 4 })
  move('right')
  validate_state1d('abcXXd', { 4, 5 })
  move('right')
  validate_state1d('abcdXX', { 5, 6 })
  -- Should allow to try to move past line end without error
  move('right')
  validate_state1d('abcdXX', { 5, 6 })

  move('left')
  validate_state1d('abcXXd', { 4, 5 })
  move('left')
  validate_state1d('abXXcd', { 3, 4 })
  move('left')
  validate_state1d('aXXbcd', { 2, 3 })
  move('left')
  validate_state1d('XXabcd', { 1, 2 })
  -- Should allow to try to move past line start without error
  move('left')
  validate_state1d('XXabcd', { 1, 2 })
end

T['move_selection()']['respects `opts.n_times` charwise horizontally'] = function()
  set_lines({ 'XXabcd' })
  set_cursor(1, 0)
  type_keys('vl')
  validate_state1d('XXabcd', { 1, 2 })

  move('right', { n_times = 3 })
  validate_state1d('abcXXd', { 4, 5 })
  move('left', { n_times = 2 })
  validate_state1d('aXXbcd', { 2, 3 })
end

T['move_selection()']['works charwise vertically'] = function()
  set_lines({ '1XXx', '2a', '3b', '4c', '5d' })
  set_cursor(1, 1)
  type_keys('vl')
  validate_state({ '1XXx', '2a', '3b', '4c', '5d' }, { { 1, 2 }, { 1, 3 } })

  move('down')
  validate_state({ '1x', '2XXa', '3b', '4c', '5d' }, { { 2, 2 }, { 2, 3 } })
  move('down')
  validate_state({ '1x', '2a', '3XXb', '4c', '5d' }, { { 3, 2 }, { 3, 3 } })
  move('down')
  validate_state({ '1x', '2a', '3b', '4XXc', '5d' }, { { 4, 2 }, { 4, 3 } })
  move('down')
  validate_state({ '1x', '2a', '3b', '4c', '5XXd' }, { { 5, 2 }, { 5, 3 } })
  -- Should allow to try to move past last line without error
  move('down')
  validate_state({ '1x', '2a', '3b', '4c', '5XXd' }, { { 5, 2 }, { 5, 3 } })

  move('up')
  validate_state({ '1x', '2a', '3b', '4XXc', '5d' }, { { 4, 2 }, { 4, 3 } })
  move('up')
  validate_state({ '1x', '2a', '3XXb', '4c', '5d' }, { { 3, 2 }, { 3, 3 } })
  move('up')
  validate_state({ '1x', '2XXa', '3b', '4c', '5d' }, { { 2, 2 }, { 2, 3 } })
  move('up')
  validate_state({ '1XXx', '2a', '3b', '4c', '5d' }, { { 1, 2 }, { 1, 3 } })
  -- Should allow to try to move past first line without error
  move('up')
  validate_state({ '1XXx', '2a', '3b', '4c', '5d' }, { { 1, 2 }, { 1, 3 } })
end

T['move_selection()']['respects `opts.n_times` charwise vertically'] = function()
  set_lines({ '1XXx', '2a', '3b', '4c', '5d' })
  set_cursor(1, 1)
  type_keys('vl')
  validate_state({ '1XXx', '2a', '3b', '4c', '5d' }, { { 1, 2 }, { 1, 3 } })

  move('down', { n_times = 3 })
  validate_state({ '1x', '2a', '3b', '4XXc', '5d' }, { { 4, 2 }, { 4, 3 } })
  move('up', { n_times = 2 })
  validate_state({ '1x', '2XXa', '3b', '4c', '5d' }, { { 2, 2 }, { 2, 3 } })
end

T['move_selection()']['works with folds charwise'] = function()
  local setup_folds = function()
    child.ensure_normal_mode()
    set_lines({ '1XX', '2aa', '3bb', '4cc', '5YY' })

    -- Create fold
    type_keys('zE')
    set_cursor(2, 0)
    type_keys('zf', '2j')
  end

  -- Down
  setup_folds()
  set_cursor(1, 1)
  type_keys('vl')
  validate_state({ '1XX', '2aa', '3bb', '4cc', '5YY' }, { { 1, 2 }, { 1, 3 } })
  eq(get_fold_range(2), { 2, 4 })

  -- - When moving "into fold", it should open it
  move('down')
  validate_state({ '1', '2XXaa', '3bb', '4cc', '5YY' }, { { 2, 2 }, { 2, 3 } })
  eq(get_fold_range(2), { -1, -1 })

  -- Up
  setup_folds()
  set_cursor(5, 1)
  type_keys('vl')
  validate_state({ '1XX', '2aa', '3bb', '4cc', '5YY' }, { { 5, 2 }, { 5, 3 } })
  eq(get_fold_range(2), { 2, 4 })

  -- - When moving "into fold", it should open it. But it happens only after
  --   entering fold, so cursor is at the start of fold. Would be nice to
  --   change so that fold is opened before movement, but it requires some
  --   extra non-trivial steps.
  move('up')
  validate_state({ '1XX', '2YYaa', '3bb', '4cc', '5' }, { { 2, 2 }, { 2, 3 } })
  eq(get_fold_range(2), { -1, -1 })
end

T['move_selection()']['works charwise vertically on line start/end'] = function()
  -- Line start
  set_lines({ 'XXx', 'a', 'b' })
  set_cursor(1, 0)
  type_keys('vl')
  validate_state({ 'XXx', 'a', 'b' }, { { 1, 1 }, { 1, 2 } })

  move('down')
  validate_state({ 'x', 'XXa', 'b' }, { { 2, 1 }, { 2, 2 } })
  move('down')
  validate_state({ 'x', 'a', 'XXb' }, { { 3, 1 }, { 3, 2 } })
  move('up')
  validate_state({ 'x', 'XXa', 'b' }, { { 2, 1 }, { 2, 2 } })
  move('up')
  validate_state({ 'XXx', 'a', 'b' }, { { 1, 1 }, { 1, 2 } })

  child.ensure_normal_mode()

  -- Line end
  set_lines({ 'xXX', 'a', 'b' })
  set_cursor(1, 1)
  type_keys('vl')
  validate_state({ 'xXX', 'a', 'b' }, { { 1, 2 }, { 1, 3 } })

  move('down')
  validate_state({ 'x', 'aXX', 'b' }, { { 2, 2 }, { 2, 3 } })
  move('down')
  validate_state({ 'x', 'a', 'bXX' }, { { 3, 2 }, { 3, 3 } })
  move('up')
  validate_state({ 'x', 'aXX', 'b' }, { { 2, 2 }, { 2, 3 } })
  move('up')
  validate_state({ 'xXX', 'a', 'b' }, { { 1, 2 }, { 1, 3 } })

  child.ensure_normal_mode()

  -- Whole line (but in charwise mode)
  set_lines({ 'XX', '', '' })
  set_cursor(1, 0)
  type_keys('vl')
  validate_state({ 'XX', '', '' }, { { 1, 1 }, { 1, 2 } })

  move('down')
  validate_state({ '', 'XX', '' }, { { 2, 1 }, { 2, 2 } })
  move('down')
  validate_state({ '', '', 'XX' }, { { 3, 1 }, { 3, 2 } })
  move('up')
  validate_state({ '', 'XX', '' }, { { 2, 1 }, { 2, 2 } })
  move('up')
  validate_state({ 'XX', '', '' }, { { 1, 1 }, { 1, 2 } })
end

T['move_selection()']['works blockwise horizontally'] = function()
  set_lines({ 'XXabcd', 'XXabcd' })
  set_cursor(1, 0)
  type_keys('<C-v>', 'lj')
  validate_state({ 'XXabcd', 'XXabcd' }, { { 1, 1 }, { 2, 2 } })

  move('right')
  validate_state({ 'aXXbcd', 'aXXbcd' }, { { 1, 2 }, { 2, 3 } })
  move('right')
  validate_state({ 'abXXcd', 'abXXcd' }, { { 1, 3 }, { 2, 4 } })
  move('right')
  validate_state({ 'abcXXd', 'abcXXd' }, { { 1, 4 }, { 2, 5 } })
  move('right')
  validate_state({ 'abcdXX', 'abcdXX' }, { { 1, 5 }, { 2, 6 } })
  -- Should allow to try to move past line end without error
  move('right')
  validate_state({ 'abcdXX', 'abcdXX' }, { { 1, 5 }, { 2, 6 } })

  move('left')
  validate_state({ 'abcXXd', 'abcXXd' }, { { 1, 4 }, { 2, 5 } })
  move('left')
  validate_state({ 'abXXcd', 'abXXcd' }, { { 1, 3 }, { 2, 4 } })
  move('left')
  validate_state({ 'aXXbcd', 'aXXbcd' }, { { 1, 2 }, { 2, 3 } })
  move('left')
  validate_state({ 'XXabcd', 'XXabcd' }, { { 1, 1 }, { 2, 2 } })
  -- Should allow to try to move past line start without error
  move('left')
  validate_state({ 'XXabcd', 'XXabcd' }, { { 1, 1 }, { 2, 2 } })
end

T['move_selection()']['respects `opts.n_times` blockwise horizontally'] = function()
  set_lines({ 'XXabcd', 'XXabcd' })
  set_cursor(1, 0)
  type_keys('<C-v>', 'lj')
  validate_state({ 'XXabcd', 'XXabcd' }, { { 1, 1 }, { 2, 2 } })

  move('right', { n_times = 3 })
  validate_state({ 'abcXXd', 'abcXXd' }, { { 1, 4 }, { 2, 5 } })
  move('left', { n_times = 2 })
  validate_state({ 'aXXbcd', 'aXXbcd' }, { { 1, 2 }, { 2, 3 } })
end

T['move_selection()']['works blockwise vertically'] = function()
  set_lines({ '1XXa', '2YYb', '3c', '4d', '5e' })
  set_cursor(1, 1)
  type_keys('<C-v>', 'lj')
  validate_state({ '1XXa', '2YYb', '3c', '4d', '5e' }, { { 1, 2 }, { 2, 3 } })

  move('down')
  validate_state({ '1a', '2XXb', '3YYc', '4d', '5e' }, { { 2, 2 }, { 3, 3 } })
  move('down')
  validate_state({ '1a', '2b', '3XXc', '4YYd', '5e' }, { { 3, 2 }, { 4, 3 } })
  move('down')
  validate_state({ '1a', '2b', '3c', '4XXd', '5YYe' }, { { 4, 2 }, { 5, 3 } })
  -- Should allow to try to move past last line without error and not
  -- going outside of buffer lines
  move('down')
  validate_state({ '1a', '2b', '3c', '4XXd', '5YYe' }, { { 4, 2 }, { 5, 3 } })

  move('up')
  validate_state({ '1a', '2b', '3XXc', '4YYd', '5e' }, { { 3, 2 }, { 4, 3 } })
  move('up')
  validate_state({ '1a', '2XXb', '3YYc', '4d', '5e' }, { { 2, 2 }, { 3, 3 } })
  move('up')
  validate_state({ '1XXa', '2YYb', '3c', '4d', '5e' }, { { 1, 2 }, { 2, 3 } })
  -- Should allow to try to move past first line without error
  move('up')
  validate_state({ '1XXa', '2YYb', '3c', '4d', '5e' }, { { 1, 2 }, { 2, 3 } })
end

T['move_selection()']['respects `opts.n_times` blockwise vertically'] = function()
  set_lines({ '1XXa', '2YYb', '3c', '4d', '5e' })
  set_cursor(1, 1)
  type_keys('<C-v>', 'lj')
  validate_state({ '1XXa', '2YYb', '3c', '4d', '5e' }, { { 1, 2 }, { 2, 3 } })

  move('down', { n_times = 3 })
  validate_state({ '1a', '2b', '3c', '4XXd', '5YYe' }, { { 4, 2 }, { 5, 3 } })
  move('up', { n_times = 2 })
  validate_state({ '1a', '2XXb', '3YYc', '4d', '5e' }, { { 2, 2 }, { 3, 3 } })
end

T['move_selection()']['works with folds blockwise'] = function()
  local setup_folds = function()
    child.ensure_normal_mode()
    set_lines({ '1XX', '2YY', '3aa', '4bb', '5cc', '6XX', '7YY' })

    -- Create fold
    type_keys('zE')
    set_cursor(3, 0)
    type_keys('zf', '2j')
  end

  -- Down
  setup_folds()
  set_cursor(1, 1)
  type_keys('<C-v>', 'jl')
  validate_state({ '1XX', '2YY', '3aa', '4bb', '5cc', '6XX', '7YY' }, { { 1, 2 }, { 2, 3 } })
  eq(get_fold_range(3), { 3, 5 })

  -- - When moving "into fold", it should open it, but this is determined by
  --   top-left corner of selection. So in this case whole fold is selected.
  move('down')
  validate_state({ '1', '2XX', '3YYaa', '4bb', '5cc', '6XX', '7YY' }, { { 2, 2 }, { 5, 4 } })
  eq(get_fold_range(3), { 3, 5 })

  -- Up
  setup_folds()
  set_cursor(6, 1)
  type_keys('<C-v>', 'jl')
  validate_state({ '1XX', '2YY', '3aa', '4bb', '5cc', '6XX', '7YY' }, { { 6, 2 }, { 7, 3 } })
  eq(get_fold_range(3), { 3, 5 })

  -- - When moving "into fold", it should open it. But it happens only after
  --   entering fold, so cursor is at the start of fold. Would be nice to
  --   change so that fold is opened before movement, but it requires some
  --   extra non-trivial steps.
  move('up')
  validate_state({ '1XX', '2YY', '3XXaa', '4YYbb', '5cc', '6', '7' }, { { 3, 2 }, { 4, 3 } })
  eq(get_fold_range(2), { -1, -1 })
end

T['move_selection()']['works linewise horizontally'] = function()
  -- Should be the same as indent (`>`) and dedent (`<`)
  set_lines({ 'aa', '  bb' })
  set_cursor(1, 0)
  type_keys('Vj')
  validate_state({ 'aa', '  bb' }, { { 1, 1 }, { 2, 1 } })

  -- Should also move cursor along selection
  move('right')
  validate_state({ '\taa', '\t  bb' }, { { 1, 1 }, { 2, 2 } })
  move('right')
  validate_state({ '\t\taa', '\t\t  bb' }, { { 1, 1 }, { 2, 3 } })

  move('left')
  validate_state({ '\taa', '\t  bb' }, { { 1, 1 }, { 2, 2 } })
  move('left')
  validate_state({ 'aa', '  bb' }, { { 1, 1 }, { 2, 1 } })
  move('left')
  validate_state({ 'aa', 'bb' }, { { 1, 1 }, { 2, 1 } })
  -- Should allow to try impossible dedent without error
  move('left')
  validate_state({ 'aa', 'bb' }, { { 1, 1 }, { 2, 1 } })
end

T['move_selection()']['respects `opts.n_times` linewise horizontally'] = function()
  set_lines({ 'aa', '  bb' })
  set_cursor(1, 0)
  type_keys('Vj')
  validate_state({ 'aa', '  bb' }, { { 1, 1 }, { 2, 1 } })

  move('right', { n_times = 3 })
  validate_state({ '\t\t\taa', '\t\t\t  bb' }, { { 1, 1 }, { 2, 4 } })
  move('left', { n_times = 2 })
  validate_state({ '\taa', '\t  bb' }, { { 1, 1 }, { 2, 2 } })
end

T['move_selection()']['linewise horizontally moves cursor along selection in edge cases'] = function()
  -- Empty line
  set_lines({ 'aa', '' })
  set_cursor(1, 0)
  type_keys('Vj')
  validate_state({ 'aa', '' }, { { 1, 1 }, { 2, 1 } })

  move('right')
  validate_state({ '\taa', '' }, { { 1, 1 }, { 2, 1 } })
  move('left')
  validate_state({ 'aa', '' }, { { 1, 1 }, { 2, 1 } })

  child.ensure_normal_mode()

  -- Past line end with default 'virtualedit'
  set_lines({ 'aa', 'bb' })
  set_cursor(1, 0)
  type_keys('Vj$')
  validate_state({ 'aa', 'bb' }, { { 1, 1 }, { 2, 3 } })

  move('right')
  validate_state({ '\taa', '\tbb' }, { { 1, 1 }, { 2, 4 } })
  move('left')
  validate_state({ 'aa', 'bb' }, { { 1, 1 }, { 2, 3 } })

  child.ensure_normal_mode()

  -- Extreme past line end with non-default 'virtualedit'
  child.o.virtualedit = 'all'
  set_lines({ 'aa', 'bb' })
  set_cursor(1, 0)
  type_keys('Vj10l')
  validate_state({ 'aa', 'bb' }, { { 1, 1 }, { 2, 3 } })
  eq(child.fn.getcurpos(), { 0, 2, 3, 8, 11 })

  move('right')
  validate_state({ '\taa', '\tbb' }, { { 1, 1 }, { 2, 4 } })
  eq(child.fn.getcurpos(), { 0, 2, 4, 8, 12 })
end

T['move_selection()']['works linewise vertically'] = function()
  set_lines({ 'XX', 'YY', 'aa', 'bb', 'cc' })
  set_cursor(1, 0)
  type_keys('Vjl')
  validate_state({ 'XX', 'YY', 'aa', 'bb', 'cc' }, { { 1, 1 }, { 2, 2 } })

  -- Should also preserve cursor column
  move('down')
  validate_state({ 'aa', 'XX', 'YY', 'bb', 'cc' }, { { 2, 1 }, { 3, 2 } })
  move('down')
  validate_state({ 'aa', 'bb', 'XX', 'YY', 'cc' }, { { 3, 1 }, { 4, 2 } })
  move('down')
  validate_state({ 'aa', 'bb', 'cc', 'XX', 'YY' }, { { 4, 1 }, { 5, 2 } })
  -- Should allow to try to move past last line without error
  move('down')
  validate_state({ 'aa', 'bb', 'cc', 'XX', 'YY' }, { { 4, 1 }, { 5, 2 } })

  move('up')
  validate_state({ 'aa', 'bb', 'XX', 'YY', 'cc' }, { { 3, 1 }, { 4, 2 } })
  move('up')
  validate_state({ 'aa', 'XX', 'YY', 'bb', 'cc' }, { { 2, 1 }, { 3, 2 } })
  move('up')
  validate_state({ 'XX', 'YY', 'aa', 'bb', 'cc' }, { { 1, 1 }, { 2, 2 } })
  -- Should allow to try to move past first line without error
  move('up')
  validate_state({ 'XX', 'YY', 'aa', 'bb', 'cc' }, { { 1, 1 }, { 2, 2 } })
end

T['move_selection()']['respects `opts.n_times` linewise vertically'] = function()
  set_lines({ 'XX', 'YY', 'aa', 'bb', 'cc' })
  set_cursor(1, 0)
  type_keys('Vjl')
  validate_state({ 'XX', 'YY', 'aa', 'bb', 'cc' }, { { 1, 1 }, { 2, 2 } })

  move('down', { n_times = 3 })
  validate_state({ 'aa', 'bb', 'cc', 'XX', 'YY' }, { { 4, 1 }, { 5, 2 } })
  move('up', { n_times = 2 })
  validate_state({ 'aa', 'XX', 'YY', 'bb', 'cc' }, { { 2, 1 }, { 3, 2 } })
end

T['move_selection()']['works with folds linewise'] = function()
  local setup_folds = function()
    child.ensure_normal_mode()
    set_lines({ '1XX', '2YY', '3aa', '4bb', '5cc', '6XX', '7YY' })

    -- Create fold
    type_keys('zE')
    set_cursor(3, 0)
    type_keys('zf', '2j')
  end

  -- Down
  setup_folds()
  set_cursor(1, 0)
  type_keys('Vj')
  validate_state({ '1XX', '2YY', '3aa', '4bb', '5cc', '6XX', '7YY' }, { { 1, 1 }, { 2, 1 } })
  eq(get_fold_range(3), { 3, 5 })

  -- - Folds should be moved altogether
  move('down')
  validate_state({ '3aa', '4bb', '5cc', '1XX', '2YY', '6XX', '7YY' }, { { 4, 1 }, { 5, 1 } })
  eq(get_fold_range(3), { 1, 3 })

  -- Up
  setup_folds()
  set_cursor(6, 0)
  type_keys('Vj')
  validate_state({ '1XX', '2YY', '3aa', '4bb', '5cc', '6XX', '7YY' }, { { 6, 1 }, { 7, 1 } })
  eq(get_fold_range(3), { 3, 5 })

  -- - Folds should be moved altogether
  move('up')
  validate_state({ '1XX', '2YY', '6XX', '7YY', '3aa', '4bb', '5cc' }, { { 3, 1 }, { 4, 1 } })
  eq(get_fold_range(5), { 5, 7 })
end

--stylua: ignore
T['move_selection()']['reindents linewise vertically'] = function()
  set_lines({ 'XX', 'YY', 'aa', '\tbb', '\t\tcc', '\tdd', 'ee' })
  set_cursor(1, 0)
  type_keys('Vjl')
  validate_state({ 'XX', 'YY',   'aa',     '\tbb',   '\t\tcc', '\tdd', 'ee' }, { { 1, 1 }, { 2, 2 } })

  -- Should also move cursor along selection
  move('down')
  validate_state({ 'aa', 'XX',   'YY',     '\tbb',   '\t\tcc', '\tdd', 'ee' }, { { 2, 1 }, { 3, 2 } })
  move('down')
  validate_state({ 'aa', '\tbb', '\tXX',   '\tYY',   '\t\tcc', '\tdd', 'ee' }, { { 3, 1 }, { 4, 3 } })
  move('down')
  validate_state({ 'aa', '\tbb', '\t\tcc', '\t\tXX', '\t\tYY', '\tdd', 'ee' }, { { 4, 1 }, { 5, 4 } })
  move('down')
  validate_state({ 'aa', '\tbb', '\t\tcc', '\tdd',   '\tXX',   '\tYY', 'ee' }, { { 5, 1 }, { 6, 3 } })
  move('down')
  validate_state({ 'aa', '\tbb', '\t\tcc', '\tdd',   'ee',     'XX',   'YY' }, { { 6, 1 }, { 7, 2 } })
end

T['move_selection()']['respects `opts.reindent_linewise`'] = function()
  set_lines({ 'XX', '\taa' })
  set_cursor(1, 0)
  type_keys('V')
  validate_state({ 'XX', '\taa' }, { { 1, 1 }, { 1, 1 } })

  -- `false` as argument
  move('down', { reindent_linewise = false })
  validate_state({ '\taa', 'XX' }, { { 2, 1 }, { 2, 1 } })

  -- `true` as argument
  move('up')
  validate_state({ 'XX', '\taa' }, { { 1, 1 }, { 1, 1 } })
  move('down', { reindent_linewise = true })
  validate_state({ '\taa', '\tXX' }, { { 2, 1 }, { 2, 2 } })

  -- `false` as global
  move('up')
  validate_state({ 'XX', '\taa' }, { { 1, 1 }, { 1, 1 } })

  child.lua('MiniMove.config.options.reindent_linewise = false')
  move('down')
  validate_state({ '\taa', 'XX' }, { { 2, 1 }, { 2, 1 } })
end

T['move_selection()']['linewise vertically moves cursor along selection in edge cases'] = function()
  -- Empty line
  set_lines({ 'aa', '', 'bb' })
  set_cursor(1, 0)
  type_keys('Vj')
  validate_state({ 'aa', '', 'bb' }, { { 1, 1 }, { 2, 1 } })

  move('down')
  validate_state({ 'bb', 'aa', '' }, { { 2, 1 }, { 3, 1 } })

  child.ensure_normal_mode()

  -- Past line end with default 'virtualedit'
  set_lines({ 'aa', 'bb' })
  set_cursor(1, 0)
  type_keys('V$')
  validate_state({ 'aa', 'bb' }, { { 1, 1 }, { 1, 3 } })

  move('down')
  validate_state({ 'bb', 'aa' }, { { 2, 1 }, { 2, 3 } })

  child.ensure_normal_mode()

  -- Extreme past line end non-default 'virtualedit'
  child.o.virtualedit = 'all'
  set_lines({ 'aa', 'bb' })
  set_cursor(1, 0)
  type_keys('V10l')
  validate_state({ 'aa', 'bb' }, { { 1, 1 }, { 1, 3 } })
  eq(child.fn.getcurpos(), { 0, 1, 3, 8, 11 })

  move('down')
  validate_state({ 'bb', 'aa' }, { { 2, 1 }, { 2, 3 } })
  eq(child.fn.getcurpos(), { 0, 2, 3, 8, 11 })
end

T['move_selection()']['linewise vertically respects cursor side of selection'] = function()
  set_lines({ 'aa', 'bb', 'cc' })
  set_cursor(2, 0)
  type_keys('Vkl')
  validate_state({ 'aa', 'bb', 'cc' }, { { 2, 1 }, { 1, 2 } })

  -- It should put cursor at top line of selection, as it is initially
  move('down')
  validate_state({ 'cc', 'aa', 'bb' }, { { 3, 1 }, { 2, 2 } })
end

T['move_selection()']['moves cursor respecting initial `curswant`'] = function()
  set_lines({ 'aaX', 'aa', 'a', '', 'a', 'aa', 'aa' })
  set_cursor(1, 2)
  type_keys('v')
  validate_state({ 'aaX', 'aa', 'a', '', 'a', 'aa', 'aa' }, { { 1, 3 }, { 1, 3 } })

  move('down')
  validate_state({ 'aa', 'aaX', 'a', '', 'a', 'aa', 'aa' }, { { 2, 3 }, { 2, 3 } })
  move('down')
  validate_state({ 'aa', 'aa', 'aX', '', 'a', 'aa', 'aa' }, { { 3, 2 }, { 3, 2 } })
  move('down')
  validate_state({ 'aa', 'aa', 'a', 'X', 'a', 'aa', 'aa' }, { { 4, 1 }, { 4, 1 } })
  move('down')
  validate_state({ 'aa', 'aa', 'a', '', 'aX', 'aa', 'aa' }, { { 5, 2 }, { 5, 2 } })
  move('down')
  validate_state({ 'aa', 'aa', 'a', '', 'a', 'aaX', 'aa' }, { { 6, 3 }, { 6, 3 } })
  move('down')
  validate_state({ 'aa', 'aa', 'a', '', 'a', 'aa', 'aaX' }, { { 7, 3 }, { 7, 3 } })

  move('up')
  validate_state({ 'aa', 'aa', 'a', '', 'a', 'aaX', 'aa' }, { { 6, 3 }, { 6, 3 } })
  move('up')
  validate_state({ 'aa', 'aa', 'a', '', 'aX', 'aa', 'aa' }, { { 5, 2 }, { 5, 2 } })
  move('up')
  validate_state({ 'aa', 'aa', 'a', 'X', 'a', 'aa', 'aa' }, { { 4, 1 }, { 4, 1 } })
  move('up')
  validate_state({ 'aa', 'aa', 'aX', '', 'a', 'aa', 'aa' }, { { 3, 2 }, { 3, 2 } })
  move('up')
  validate_state({ 'aa', 'aaX', 'a', '', 'a', 'aa', 'aa' }, { { 2, 3 }, { 2, 3 } })
  move('up')
  validate_state({ 'aaX', 'aa', 'a', '', 'a', 'aa', 'aa' }, { { 1, 3 }, { 1, 3 } })

  -- Single horizontal move should reset `curswant`
  move('down')
  validate_state({ 'aa', 'aaX', 'a', '', 'a', 'aa', 'aa' }, { { 2, 3 }, { 2, 3 } })
  move('left')
  validate_state({ 'aa', 'aXa', 'a', '', 'a', 'aa', 'aa' }, { { 2, 2 }, { 2, 2 } })
  move('up')
  validate_state({ 'aXa', 'aa', 'a', '', 'a', 'aa', 'aa' }, { { 1, 2 }, { 1, 2 } })
end

T['move_selection()']['computes `curswant` based on left side'] = function()
  set_lines({ 'aaXXa', '', 'aaaaa' })
  set_cursor(1, 2)
  type_keys('vl')
  validate_state({ 'aaXXa', '', 'aaaaa' }, { { 1, 3 }, { 1, 4 } })

  move('down')
  validate_state({ 'aaa', 'XX', 'aaaaa' }, { { 2, 1 }, { 2, 2 } })
  move('down')
  validate_state({ 'aaa', '', 'aaXXaaa' }, { { 3, 3 }, { 3, 4 } })
end

T['move_selection()']['updates `curswant` when moving horizontally'] = function()
  -- Charwise
  set_lines({ 'abXcd', 'efgh' })
  set_cursor(1, 2)
  type_keys('v')
  validate_state({ 'abXcd', 'efgh' }, { { 1, 3 }, { 1, 3 } })

  move('right')
  validate_state({ 'abcXd', 'efgh' }, { { 1, 4 }, { 1, 4 } })
  move('down')
  validate_state({ 'abcd', 'efgXh' }, { { 2, 4 }, { 2, 4 } })
  move('left')
  validate_state({ 'abcd', 'efXgh' }, { { 2, 3 }, { 2, 3 } })
  move('up')
  validate_state({ 'abXcd', 'efgh' }, { { 1, 3 }, { 1, 3 } })
end

T['move_selection()']['works with multibyte characters'] = function()
  set_lines({ 'ыыXXы', '', 'ыыыыы' })
  set_cursor(1, 4)
  type_keys('vl')
  validate_state({ 'ыыXXы', '', 'ыыыыы' }, { { 1, 5 }, { 1, 6 } })

  move('down')
  validate_state({ 'ыыы', 'XX', 'ыыыыы' }, { { 2, 1 }, { 2, 2 } })
  move('down')
  validate_state({ 'ыыы', '', 'ыыXXыыы' }, { { 3, 5 }, { 3, 6 } })
end

T['move_selection()']['works in small buffers'] = function()
  local validate = function(line_before, vis_mode, direction, line_after)
    child.ensure_normal_mode()
    set_lines({ line_before })
    set_cursor(1, 1)
    type_keys(vis_mode)
    move(direction)
    eq(get_lines(), { line_after or line_before })
  end

  -- Should do nothing in empty buffer
  for _, vis_mode in ipairs({ 'v', 'V', '<C-v>' }) do
    for _, direction in ipairs({ 'up', 'down', 'left', 'right' }) do
      validate('', vis_mode, direction)
    end
  end

  -- Should work only horizontally in single line buffer
  validate('abc', 'v', 'up', 'abc')
  validate('abc', 'v', 'down', 'abc')
  validate('abc', 'V', 'up', 'abc')
  validate('abc', 'V', 'down', 'abc')
  validate('abc', '<C-v>', 'up', 'abc')
  validate('abc', '<C-v>', 'down', 'abc')

  validate('abc', 'v', 'left', 'bac')
  validate('abc', 'v', 'right', 'acb')
  validate('\tabc', 'V', 'left', 'abc')
  validate('abc', 'V', 'right', '\tabc')
  validate('abc', '<C-v>', 'left', 'bac')
  validate('abc', '<C-v>', 'right', 'acb')
end

T['move_selection()']['has no side effects'] = function()
  set_lines({ 'aaa', 'bbb' })

  -- Shouldn't modify any possibly affected registers
  local reginfo_ref = setup_registers()

  -- Shouldn't modify 'virtualedit'
  child.o.virtualedit = 'block,insert'

  -- Shouldn't affect yank history from 'mini.bracketed'
  child.cmd('au TextYankPost * lua if not vim.b.minibracketed_disable then _G.been_here = true end')

  local validate = function()
    for reg, info in pairs(reginfo_ref) do
      eq(child.fn.getreginfo(reg), info)
    end
    eq(child.o.virtualedit, 'block,insert')
    eq(child.lua_get('_G.been_here'), vim.NIL)
    eq(child.lua_get('vim.b.minibracketed_disable'), vim.NIL)
  end

  -- Perform linewise move
  set_cursor(1, 0)
  type_keys('V')
  move('down')
  validate_state({ 'bbb', 'aaa' }, { { 2, 1 }, { 2, 1 } })
  validate()
  child.ensure_normal_mode()

  -- Perform charwise move
  set_cursor(1, 1)
  type_keys('v')
  move('down')
  validate_state({ 'bb', 'abaa' }, { { 2, 2 }, { 2, 2 } })
  validate()
end

T['move_selection()']['works with `virtualedit=all`'] = function()
  child.o.virtualedit = 'all'

  set_lines({ 'abX', '' })
  set_cursor(1, 2)
  type_keys('v')

  move('right')
  validate_state({ 'ab X', '' }, { { 1, 4 }, { 1, 4 } })
  move('down')
  validate_state({ 'ab ', '   X' }, { { 2, 4 }, { 2, 4 } })
end

T['move_selection()']['works silently'] = function()
  -- Horizontal movement should not add "x lines >ed y times" message
  set_lines({ 'aa', 'bb', 'cc' })
  set_cursor(1, 0)
  type_keys('V2j')
  validate_state({ 'aa', 'bb', 'cc' }, { { 1, 1 }, { 3, 1 } })

  child.cmd('messages clear')
  move('right')
  validate_state({ '\taa', '\tbb', '\tcc' }, { { 1, 1 }, { 3, 2 } })
  eq(child.cmd_capture('messages'), '')

  move('left')
  validate_state({ 'aa', 'bb', 'cc' }, { { 1, 1 }, { 3, 1 } })
  eq(child.cmd_capture('messages'), '')

  child.ensure_normal_mode()
  child.cmd('messages clear')

  -- Reindent when moving vertically linewise should not add "x lines to
  -- indent" messages
  set_lines({ 'aa', 'bb', 'cc', '\tdd' })
  set_cursor(1, 0)
  type_keys('V2j')
  validate_state({ 'aa', 'bb', 'cc', '\tdd' }, { { 1, 1 }, { 3, 1 } })

  move('down')
  validate_state({ '\tdd', '\taa', '\tbb', '\tcc' }, { { 2, 1 }, { 4, 2 } })
  eq(child.cmd_capture('messages'), '')
end

T['move_selection()']['undos all movements at once'] = function()
  set_lines({ 'aXbc', 'defg' })
  set_cursor(1, 1)
  type_keys('v')
  validate_state({ 'aXbc', 'defg' }, { { 1, 2 }, { 1, 2 } })

  move('down')
  move('right')
  move('right')
  move('up')
  move('left')
  validate_state({ 'abXc', 'defg' }, { { 1, 3 }, { 1, 3 } })

  type_keys('<Esc>', 'u')
  validate_state({ 'aXbc', 'defg' }, { { 1, 2 }, { 1, 2 } })
end

T['move_selection()']['starts separate undo block on outer cursor move'] = function()
  set_lines({ 'aXbc', 'defg' })
  set_cursor(1, 1)
  type_keys('v')
  validate_state({ 'aXbc', 'defg' }, { { 1, 2 }, { 1, 2 } })

  move('down')
  validate_state({ 'abc', 'dXefg' }, { { 2, 2 }, { 2, 2 } })
  type_keys('l')
  validate_state({ 'abc', 'dXefg' }, { { 2, 2 }, { 2, 3 } })
  move('right')
  validate_state({ 'abc', 'dfXeg' }, { { 2, 3 }, { 2, 4 } })

  type_keys('<Esc>', 'u')
  validate_state({ 'abc', 'dXefg' }, { { 2, 2 }, { 2, 2 } })
  type_keys('u')
  validate_state({ 'aXbc', 'defg' }, { { 1, 2 }, { 1, 2 } })
end

T['move_selection()']['does not create unnecessary jumps'] = function()
  set_lines({ '1Xa', '2b', '3c', '4d' })
  set_cursor(1, 1)
  type_keys('m`')
  type_keys('v')

  move('down')
  move('down')
  move('down')
  validate_state({ '1a', '2b', '3c', '4Xd' }, { { 4, 2 }, { 4, 2 } })

  -- In jump list there should be only single entry
  eq(#child.fn.getjumplist()[1], 1)
end

T['move_selection()']["silently respects 'nomodifiable'"] = function()
  set_lines({ 'aa', '  bb', 'cc' })
  set_cursor(2, 0)
  type_keys('V')

  local validate = function()
    validate_state({ 'aa', '  bb', 'cc' }, { { 2, 1 }, { 2, 1 } })
    eq(child.cmd_capture('messages'), '')
  end
  validate()

  child.o.modifiable = false

  move('left')
  validate()
  move('right')
  validate()
  move('up')
  validate()
  move('down')
  validate()
end

T['move_selection()']['respects `vim.{g,b}.minimove_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minimove_disable = true

    set_lines({ 'aaa', 'bbb' })
    set_cursor(1, 0)
    type_keys('V')
    validate_state({ 'aaa', 'bbb' }, { { 1, 1 }, { 1, 1 } })

    move('down')
    validate_state({ 'aaa', 'bbb' }, { { 1, 1 }, { 1, 1 } })

    child[var_type].minimove_disable = false
    move('down')
    validate_state({ 'bbb', 'aaa' }, { { 2, 1 }, { 2, 1 } })
  end,
})

T['move_line()'] = new_set()

local move_line = function(direction, opts) child.lua('MiniMove.move_line(...)', { direction, opts }) end

T['move_line()']['works vertically'] = function()
  set_lines({ 'XX', 'aa', 'bb', 'cc' })
  set_cursor(1, 1)
  validate_line_state({ 'XX', 'aa', 'bb', 'cc' }, { 1, 1 })

  -- Should also preserve cursor column
  move_line('down')
  validate_line_state({ 'aa', 'XX', 'bb', 'cc' }, { 2, 1 })
  move_line('down')
  validate_line_state({ 'aa', 'bb', 'XX', 'cc' }, { 3, 1 })
  move_line('down')
  validate_line_state({ 'aa', 'bb', 'cc', 'XX' }, { 4, 1 })
  -- Should allow to try to move_line past last line without error
  move_line('down')
  validate_line_state({ 'aa', 'bb', 'cc', 'XX' }, { 4, 1 })

  move_line('up')
  validate_line_state({ 'aa', 'bb', 'XX', 'cc' }, { 3, 1 })
  move_line('up')
  validate_line_state({ 'aa', 'XX', 'bb', 'cc' }, { 2, 1 })
  move_line('up')
  validate_line_state({ 'XX', 'aa', 'bb', 'cc' }, { 1, 1 })
  -- Should allow to try to move_line past first line without error
  move_line('up')
  validate_line_state({ 'XX', 'aa', 'bb', 'cc' }, { 1, 1 })
end

T['move_line()']['respects `opts.n_times` vertically'] = function()
  set_lines({ 'XX', 'aa', 'bb', 'cc' })
  set_cursor(1, 1)
  validate_line_state({ 'XX', 'aa', 'bb', 'cc' }, { 1, 1 })

  move_line('down', { n_times = 3 })
  validate_line_state({ 'aa', 'bb', 'cc', 'XX' }, { 4, 1 })
  move_line('up', { n_times = 2 })
  validate_line_state({ 'aa', 'XX', 'bb', 'cc' }, { 2, 1 })
end

T['move_line()']['works vertically with folds'] = function()
  local setup_folds = function()
    child.ensure_normal_mode()
    set_lines({ '1XX', '2aa', '3bb', '4cc', '5XX' })

    -- Create fold
    type_keys('zE')
    set_cursor(2, 0)
    type_keys('zf', '2j')
  end

  -- Down
  setup_folds()
  set_cursor(1, 0)
  validate_line_state({ '1XX', '2aa', '3bb', '4cc', '5XX' }, { 1, 0 })
  eq(get_fold_range(2), { 2, 4 })

  -- - Folds should be moved altogether
  move_line('down')
  validate_line_state({ '2aa', '3bb', '4cc', '1XX', '5XX' }, { 4, 0 })
  eq(get_fold_range(1), { 1, 3 })

  -- Up
  setup_folds()
  set_cursor(5, 0)
  validate_line_state({ '1XX', '2aa', '3bb', '4cc', '5XX' }, { 5, 0 })
  eq(get_fold_range(2), { 2, 4 })

  -- - Folds should be moved altogether
  move_line('up')
  validate_line_state({ '1XX', '5XX', '2aa', '3bb', '4cc' }, { 2, 0 })
  eq(get_fold_range(3), { 3, 5 })
end

--stylua: ignore
T['move_line()']['reindents while moving cursor along'] = function()
  set_lines({ 'XX', 'aa', '\tbb', '\t\tcc', '\tdd', 'ee' })
  set_cursor(1, 1)
  -- As `get_cursor()` treats '\t' as single character, use 1 and 2 instead of
  -- relying on computing visible cursor position with 'shiftwidth'
  validate_line_state({ 'XX', 'aa',   '\tbb',   '\t\tcc', '\tdd', 'ee' }, { 1, 1 })

  -- Should also move cursor along selection
  move_line('down')
  validate_line_state({ 'aa', 'XX',   '\tbb',   '\t\tcc', '\tdd', 'ee' }, { 2, 1 })
  move_line('down')
  validate_line_state({ 'aa', '\tbb', '\tXX',   '\t\tcc', '\tdd', 'ee' }, { 3, 2 })
  move_line('down')
  validate_line_state({ 'aa', '\tbb', '\t\tcc', '\t\tXX', '\tdd', 'ee' }, { 4, 3 })
  move_line('down')
  validate_line_state({ 'aa', '\tbb', '\t\tcc', '\tdd',   '\tXX', 'ee' }, { 5, 2 })
  move_line('down')
  validate_line_state({ 'aa', '\tbb', '\t\tcc', '\tdd',   'ee',   'XX' }, { 6, 1 })
end

T['move_line()']['respects `opts.reindent_linewise`'] = function()
  set_lines({ 'XX', '\taa' })
  set_cursor(1, 1)
  validate_line_state({ 'XX', '\taa' }, { 1, 1 })

  -- `false` as argument
  move_line('down', { reindent_linewise = false })
  validate_line_state({ '\taa', 'XX' }, { 2, 1 })

  -- `true` as argument
  move_line('up')
  validate_line_state({ 'XX', '\taa' }, { 1, 1 })
  move_line('down', { reindent_linewise = true })
  validate_line_state({ '\taa', '\tXX' }, { 2, 2 })

  -- `false` as global
  move_line('up')
  validate_line_state({ 'XX', '\taa' }, { 1, 1 })

  child.lua('MiniMove.config.options.reindent_linewise = false')
  move_line('down')
  validate_line_state({ '\taa', 'XX' }, { 2, 1 })
end

T['move_line()']['works horizontally'] = function()
  -- Should be the same as indent (`>`) and dedent (`<`)
  set_lines({ '  aa' })
  set_cursor(1, 1)
  validate_line_state({ '  aa' }, { 1, 1 })

  -- Should also move cursor along selection
  move_line('right')
  validate_line_state({ '\t  aa' }, { 1, 2 })
  move_line('right')
  validate_line_state({ '\t\t  aa' }, { 1, 3 })

  move_line('left')
  validate_line_state({ '\t  aa' }, { 1, 2 })
  move_line('left')
  validate_line_state({ '  aa' }, { 1, 1 })
  move_line('left')
  validate_line_state({ 'aa' }, { 1, 0 })
  -- Should allow to try impossible dedent without error
  move_line('left')
  validate_line_state({ 'aa' }, { 1, 0 })
end

T['move_line()']['respects `opts.n_times` horizontally'] = function()
  set_lines({ 'aa' })
  set_cursor(1, 0)
  validate_line_state({ 'aa' }, { 1, 0 })

  move_line('right', { n_times = 3 })
  validate_line_state({ '\t\t\taa' }, { 1, 3 })
  move_line('left', { n_times = 2 })
  validate_line_state({ '\taa' }, { 1, 1 })
end

T['move_line()']['works in small buffers'] = function()
  local validate = function(line_before, direction, line_after)
    set_lines({ line_before })
    set_cursor(1, 0)
    move_line(direction)
    eq(get_lines(), { line_after or line_before })
  end

  -- Should do nothing in empty buffer
  validate('', 'up', '')
  validate('', 'down', '')
  validate('', 'left', '')
  validate('', 'right', '')

  -- Should work only horizontally in single line buffer
  validate('abc', 'up', 'abc')
  validate('abc', 'down', 'abc')
  validate('\tabc', 'left', 'abc')
  validate('abc', 'right', '\tabc')
end

T['move_line()']['has no side effects'] = function()
  set_lines({ 'aaa', 'bbb' })

  -- Shouldn't modify any possibly affected registers
  local reginfo_ref = setup_registers()

  -- Shouldn't affect yank history from 'mini.bracketed'
  child.cmd('au TextYankPost * lua if not vim.b.minibracketed_disable then _G.been_here = true end')

  -- Perform move
  set_cursor(1, 0)
  move_line('down')
  validate_line_state({ 'bbb', 'aaa' }, { 2, 0 })

  -- Check
  for reg, info in pairs(reginfo_ref) do
    eq(child.fn.getreginfo(reg), info)
  end
  eq(child.lua_get('_G.been_here'), vim.NIL)
  eq(child.lua_get('vim.b.minibracketed_disable'), vim.NIL)
end

T['move_line()']['works silently'] = function()
  -- Although at the moment single line moves don't produce messages, test it
  -- to align with 'move_selection()'

  -- Horizontal movement should not add "x lines >ed y times" message
  set_lines({ 'aa' })
  set_cursor(1, 0)
  validate_line_state({ 'aa' }, { 1, 0 })

  child.cmd('messages clear')
  move_line('right')
  validate_line_state({ '\taa' }, { 1, 1 })
  eq(child.cmd_capture('messages'), '')

  move_line('left')
  validate_line_state({ 'aa' }, { 1, 0 })
  eq(child.cmd_capture('messages'), '')

  child.ensure_normal_mode()

  -- Reindent when moving vertically linewise should not add "x lines to
  -- indent" messages
  child.cmd('messages clear')
  set_lines({ 'aa', '\tdd' })
  set_cursor(1, 0)
  validate_line_state({ 'aa', '\tdd' }, { 1, 0 })

  move_line('down')
  validate_line_state({ '\tdd', '\taa' }, { 2, 1 })
  eq(child.cmd_capture('messages'), '')
end

T['move_line()']['undos all movements at once'] = function()
  set_lines({ 'aaa', 'bbb', 'ccc', 'ddd' })
  set_cursor(1, 0)
  validate_line_state({ 'aaa', 'bbb', 'ccc', 'ddd' }, { 1, 0 })

  move_line('down')
  move_line('down')
  move_line('up')
  move_line('down')
  validate_line_state({ 'bbb', 'ccc', 'aaa', 'ddd' }, { 3, 0 })

  type_keys('<Esc>', 'u')
  validate_line_state({ 'aaa', 'bbb', 'ccc', 'ddd' }, { 1, 0 })
end

T['move_line()']['starts separate undo block on outer cursor move'] = function()
  set_lines({ 'aaa', 'bbb', 'ccc', 'ddd' })
  set_cursor(1, 0)
  validate_line_state({ 'aaa', 'bbb', 'ccc', 'ddd' }, { 1, 0 })

  move_line('down')
  validate_line_state({ 'bbb', 'aaa', 'ccc', 'ddd' }, { 2, 0 })
  type_keys('j')
  validate_line_state({ 'bbb', 'aaa', 'ccc', 'ddd' }, { 3, 0 })
  move_line('down')
  validate_line_state({ 'bbb', 'aaa', 'ddd', 'ccc' }, { 4, 0 })

  type_keys('<Esc>', 'u')
  validate_line_state({ 'bbb', 'aaa', 'ccc', 'ddd' }, { 3, 0 })
  type_keys('u')
  validate_line_state({ 'aaa', 'bbb', 'ccc', 'ddd' }, { 1, 0 })
end

T['move_line()']['does not share undo block with visual moves'] = function()
  set_lines({ 'aaa', 'bbb', 'ccc', 'ddd' })
  set_cursor(1, 0)
  type_keys('V')
  validate_state({ 'aaa', 'bbb', 'ccc', 'ddd' }, { { 1, 1 }, { 1, 1 } })

  move('down')
  validate_state({ 'bbb', 'aaa', 'ccc', 'ddd' }, { { 2, 1 }, { 2, 1 } })

  type_keys('<Esc>')
  move_line('down')
  validate_line_state({ 'bbb', 'ccc', 'aaa', 'ddd' }, { 3, 0 })

  type_keys('u')
  validate_line_state({ 'bbb', 'aaa', 'ccc', 'ddd' }, { 2, 0 })
  type_keys('u')
  validate_line_state({ 'aaa', 'bbb', 'ccc', 'ddd' }, { 1, 0 })
end

T['move_line()']['does not create unnecessary jumps'] = function()
  set_lines({ 'aa', 'bb', 'cc', 'dd' })
  set_cursor(1, 1)
  type_keys('m`')

  move_line('down')
  move_line('down')
  move_line('down')
  validate_line_state({ 'bb', 'cc', 'dd', 'aa' }, { 4, 1 })

  -- In jump list there should be only single entry
  eq(#child.fn.getjumplist()[1], 1)
end

T['move_line()']["silently respects 'nomodifiable'"] = function()
  set_lines({ 'aa', '  bb', 'cc' })
  set_cursor(2, 0)

  local validate = function()
    validate_line_state({ 'aa', '  bb', 'cc' }, { 2, 0 })
    eq(child.cmd_capture('messages'), '')
  end
  validate()

  child.o.modifiable = false

  move_line('left')
  validate()
  move_line('right')
  validate()
  move_line('up')
  validate()
  move_line('down')
  validate()
end

T['move_line()']['respects `vim.{g,b}.minimove_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minimove_disable = true

    set_lines({ 'aaa', 'bbb' })
    set_cursor(1, 0)
    validate_line_state({ 'aaa', 'bbb' }, { 1, 0 })

    move_line('down')
    validate_line_state({ 'aaa', 'bbb' }, { 1, 0 })

    child[var_type].minimove_disable = false
    move_line('down')
    validate_line_state({ 'bbb', 'aaa' }, { 2, 0 })
  end,
})

-- Integration tests ==========================================================
T['Mappings'] = new_set()

T['Mappings']['left/right'] = new_set()

T['Mappings']['left/right']['works charwise'] = function()
  set_lines({ 'XXabcd' })
  set_cursor(1, 0)
  type_keys('vl')
  validate_state1d('XXabcd', { 1, 2 })

  type_keys('<M-l>')
  validate_state1d('aXXbcd', { 2, 3 })
  -- Supports `v:count`
  type_keys('2<M-l>')
  validate_state1d('abcXXd', { 4, 5 })
  -- Can allow overshoot without error
  type_keys('2<M-l>')
  validate_state1d('abcdXX', { 5, 6 })

  type_keys('<M-h>')
  validate_state1d('abcXXd', { 4, 5 })
  -- Supports `v:count`
  type_keys('2<M-h>')
  validate_state1d('aXXbcd', { 2, 3 })
  -- Can allow overshoot without error
  type_keys('2<M-h>')
  validate_state1d('XXabcd', { 1, 2 })
end

T['Mappings']['left/right']['works blockwise'] = function()
  set_lines({ 'XXabcd', 'XXabcd' })
  set_cursor(1, 0)
  type_keys('<C-v>', 'lj')
  validate_state({ 'XXabcd', 'XXabcd' }, { { 1, 1 }, { 2, 2 } })

  type_keys('<M-l>')
  validate_state({ 'aXXbcd', 'aXXbcd' }, { { 1, 2 }, { 2, 3 } })
  -- Supports `v:count`
  type_keys('2<M-l>')
  validate_state({ 'abcXXd', 'abcXXd' }, { { 1, 4 }, { 2, 5 } })
  -- Should allow overshoot without error
  type_keys('2<M-l>')
  validate_state({ 'abcdXX', 'abcdXX' }, { { 1, 5 }, { 2, 6 } })

  type_keys('<M-h>')
  validate_state({ 'abcXXd', 'abcXXd' }, { { 1, 4 }, { 2, 5 } })
  -- Supports `v:count`
  type_keys('2<M-h>')
  validate_state({ 'aXXbcd', 'aXXbcd' }, { { 1, 2 }, { 2, 3 } })
  -- Should allow overshoot without error
  type_keys('2<M-h>')
  validate_state({ 'XXabcd', 'XXabcd' }, { { 1, 1 }, { 2, 2 } })
end

T['Mappings']['left/right']['works linewise'] = function()
  set_lines({ '  aa', 'bb' })
  set_cursor(1, 0)
  type_keys('Vjl')
  validate_state({ '  aa', 'bb' }, { { 1, 1 }, { 2, 2 } })

  type_keys('<M-l>')
  validate_state({ '\t  aa', '\tbb' }, { { 1, 1 }, { 2, 3 } })
  -- Supports `v:count`
  type_keys('2<M-l>')
  validate_state({ '\t\t\t  aa', '\t\t\tbb' }, { { 1, 1 }, { 2, 5 } })

  type_keys('<M-h>')
  validate_state({ '\t\t  aa', '\t\tbb' }, { { 1, 1 }, { 2, 4 } })
  -- Supports `v:count`
  type_keys('2<M-h>')
  validate_state({ '  aa', 'bb' }, { { 1, 1 }, { 2, 2 } })
  -- Should allow overshoot without error
  type_keys('2<M-h>')
  validate_state({ 'aa', 'bb' }, { { 1, 1 }, { 2, 2 } })
end

T['Mappings']['down/up'] = new_set()

T['Mappings']['down/up']['works charwise'] = function()
  set_lines({ '1XXx', '2a', '3b', '4c', '5d' })
  set_cursor(1, 1)
  type_keys('vl')
  validate_state({ '1XXx', '2a', '3b', '4c', '5d' }, { { 1, 2 }, { 1, 3 } })

  type_keys('<M-j>')
  validate_state({ '1x', '2XXa', '3b', '4c', '5d' }, { { 2, 2 }, { 2, 3 } })
  -- Supports `v:count`
  type_keys('2<M-j>')
  validate_state({ '1x', '2a', '3b', '4XXc', '5d' }, { { 4, 2 }, { 4, 3 } })
  -- Should allow overshoot without error
  type_keys('2<M-j>')
  validate_state({ '1x', '2a', '3b', '4c', '5XXd' }, { { 5, 2 }, { 5, 3 } })

  type_keys('<M-k>')
  validate_state({ '1x', '2a', '3b', '4XXc', '5d' }, { { 4, 2 }, { 4, 3 } })
  -- Supports `v:count`
  type_keys('2<M-k>')
  validate_state({ '1x', '2XXa', '3b', '4c', '5d' }, { { 2, 2 }, { 2, 3 } })
  -- Should allow overshoot without error
  type_keys('2<M-k>')
  validate_state({ '1XXx', '2a', '3b', '4c', '5d' }, { { 1, 2 }, { 1, 3 } })
end

T['Mappings']['down/up']['works blockwise'] = function()
  set_lines({ '1XXa', '2YYb', '3c', '4d', '5e' })
  set_cursor(1, 1)
  type_keys('<C-v>', 'lj')
  validate_state({ '1XXa', '2YYb', '3c', '4d', '5e' }, { { 1, 2 }, { 2, 3 } })

  type_keys('<M-j>')
  validate_state({ '1a', '2XXb', '3YYc', '4d', '5e' }, { { 2, 2 }, { 3, 3 } })
  -- Supports `v:count`
  type_keys('2<M-j>')
  validate_state({ '1a', '2b', '3c', '4XXd', '5YYe' }, { { 4, 2 }, { 5, 3 } })
  -- Should allow overshoot without error
  type_keys('2<M-j>')
  validate_state({ '1a', '2b', '3c', '4XXd', '5YYe' }, { { 4, 2 }, { 5, 3 } })

  type_keys('<M-k>')
  validate_state({ '1a', '2b', '3XXc', '4YYd', '5e' }, { { 3, 2 }, { 4, 3 } })
  -- Supports `v:count`
  type_keys('2<M-k>')
  validate_state({ '1XXa', '2YYb', '3c', '4d', '5e' }, { { 1, 2 }, { 2, 3 } })
  -- Should allow overshoot without error
  type_keys('2<M-k>')
  validate_state({ '1XXa', '2YYb', '3c', '4d', '5e' }, { { 1, 2 }, { 2, 3 } })
end

T['Mappings']['down/up']['works linewise'] = function()
  set_lines({ 'XX', 'YY', 'aa', 'bb', 'cc' })
  set_cursor(1, 0)
  type_keys('Vj')
  validate_state({ 'XX', 'YY', 'aa', 'bb', 'cc' }, { { 1, 1 }, { 2, 1 } })

  type_keys('<M-j>')
  validate_state({ 'aa', 'XX', 'YY', 'bb', 'cc' }, { { 2, 1 }, { 3, 1 } })
  -- Supports `v:count`
  type_keys('2<M-j>')
  validate_state({ 'aa', 'bb', 'cc', 'XX', 'YY' }, { { 4, 1 }, { 5, 1 } })
  -- Should allow overshoot without error
  type_keys('2<M-j>')
  validate_state({ 'aa', 'bb', 'cc', 'XX', 'YY' }, { { 4, 1 }, { 5, 1 } })

  type_keys('<M-k>')
  validate_state({ 'aa', 'bb', 'XX', 'YY', 'cc' }, { { 3, 1 }, { 4, 1 } })
  -- Supports `v:count`
  type_keys('2<M-k>')
  validate_state({ 'XX', 'YY', 'aa', 'bb', 'cc' }, { { 1, 1 }, { 2, 1 } })
  -- Should allow overshoot without error
  type_keys('2<M-k>')
  validate_state({ 'XX', 'YY', 'aa', 'bb', 'cc' }, { { 1, 1 }, { 2, 1 } })
end

T['Mappings']['line_left/line_right'] = new_set()

T['Mappings']['line_left/line_right']['works'] = function()
  -- Should be the same as indent (`>`) and dedent (`<`)
  set_lines({ '  aa' })
  set_cursor(1, 1)
  validate_line_state({ '  aa' }, { 1, 1 })

  type_keys('<M-l>')
  validate_line_state({ '\t  aa' }, { 1, 2 })
  type_keys('2<M-l>')
  validate_line_state({ '\t\t\t  aa' }, { 1, 4 })

  type_keys('<M-h>')
  validate_line_state({ '\t\t  aa' }, { 1, 3 })
  type_keys('2<M-h>')
  validate_line_state({ '  aa' }, { 1, 1 })
  -- Should allow to try impossible dedent without error
  type_keys('2<M-h>')
  validate_line_state({ 'aa' }, { 1, 0 })
end

T['Mappings']['line_down/line_up'] = new_set()

T['Mappings']['line_down/line_up']['works'] = function()
  set_lines({ 'XX', 'aa', 'bb', 'cc' })
  set_cursor(1, 1)
  validate_line_state({ 'XX', 'aa', 'bb', 'cc' }, { 1, 1 })

  type_keys('<M-j>')
  validate_line_state({ 'aa', 'XX', 'bb', 'cc' }, { 2, 1 })
  -- Supports `v:count`
  type_keys('2<M-j>')
  validate_line_state({ 'aa', 'bb', 'cc', 'XX' }, { 4, 1 })
  -- Should allow overshoot without error
  type_keys('2<M-j>')
  validate_line_state({ 'aa', 'bb', 'cc', 'XX' }, { 4, 1 })

  type_keys('<M-k>')
  validate_line_state({ 'aa', 'bb', 'XX', 'cc' }, { 3, 1 })
  -- Supports `v:count`
  type_keys('2<M-k>')
  validate_line_state({ 'XX', 'aa', 'bb', 'cc' }, { 1, 1 })
  -- Should allow overshoot without error
  type_keys('2<M-k>')
  validate_line_state({ 'XX', 'aa', 'bb', 'cc' }, { 1, 1 })
end

return T
