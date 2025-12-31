local helpers = dofile('tests/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('clue', config) end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
local sleep = function(ms) helpers.sleep(ms, child) end
--stylua: ignore end

local get_window = function() return child.api.nvim_get_current_win() end
local set_window = function(win_id) return child.api.nvim_set_current_win(win_id) end

local forward_lua = function(fun_str)
  local lua_cmd = fun_str .. '(...)'
  return function(...) return child.lua_get(lua_cmd, { ... }) end
end

-- Mapping helpers
local replace_termcodes = function(x) return child.api.nvim_replace_termcodes(x, true, true, true) end

local reset_test_map_count = function(mode, lhs)
  lhs = vim.fn.escape(replace_termcodes(lhs), [[\]])
  local lua_cmd = string.format([[_G['test_map_%s_%s'] = 0]], mode, lhs)
  child.lua(lua_cmd)
end

local get_test_map_count = function(mode, lhs)
  lhs = vim.fn.escape(replace_termcodes(lhs), [[\]])
  local lua_cmd = string.format([=[_G['test_map_%s_%s']]=], mode, lhs)
  return child.lua_get(lua_cmd)
end

local make_test_map = function(mode, lhs, opts)
  lhs = vim.fn.escape(replace_termcodes(lhs), [[\]])
  opts = opts or {}
  opts.desc = 'LHS: ' .. vim.inspect(lhs)

  reset_test_map_count(mode, lhs)

  --stylua: ignore
  local lua_cmd = string.format(
    [[vim.keymap.set('%s', '%s', function() _G['test_map_%s_%s'] = _G['test_map_%s_%s'] + 1 end, %s)]],
    mode, lhs,
    mode, lhs,
    mode, lhs,
    vim.inspect(opts)
  )
  child.lua(lua_cmd)
end

-- Custom validators
local validate_trigger_keymap = function(mode, keys, buf_id)
  buf_id = buf_id or child.api.nvim_get_current_buf()
  local lua_cmd = string.format(
    [[vim.api.nvim_buf_call(%s, function() return vim.fn.maparg(%s, %s, false, true).desc end)]],
    buf_id,
    vim.inspect(keys),
    vim.inspect(mode)
  )
  local map_desc = child.lua_get(lua_cmd)
  if map_desc == vim.NIL then error('No such trigger.') end

  local desc_pattern = 'keys after.*"' .. vim.pesc(keys) .. '"'
  expect.match(map_desc, desc_pattern)
end

local validate_no_trigger_keymap = function(mode, keys, buf_id)
  expect.error(function() validate_trigger_keymap(mode, keys, buf_id) end, 'No such trigger')
end

local validate_edit = function(lines_before, cursor_before, keys, lines_after, cursor_after)
  child.ensure_normal_mode()
  set_lines(lines_before)
  set_cursor(cursor_before[1], cursor_before[2])

  type_keys(keys)

  eq(get_lines(), lines_after)
  eq(get_cursor(), cursor_after)

  child.ensure_normal_mode()
end

local validate_edit1d = function(line_before, col_before, keys, line_after, col_after)
  validate_edit({ line_before }, { 1, col_before }, keys, { line_after }, { 1, col_after })
end

local validate_move = function(lines, cursor_before, keys, cursor_after)
  validate_edit(lines, cursor_before, keys, lines, cursor_after)
end

local validate_move1d = function(line, col_before, keys, col_after)
  validate_edit1d(line, col_before, keys, line, col_after)
end

local validate_selection = function(lines, cursor, keys, selection_from, selection_to, visual_mode)
  visual_mode = visual_mode or 'v'
  child.ensure_normal_mode()
  set_lines(lines)
  set_cursor(cursor[1], cursor[2])

  type_keys(keys)

  eq(child.fn.mode(), visual_mode)

  -- Compute two correctly ordered edges
  local from = { child.fn.line('v'), child.fn.col('v') - 1 }
  local to = { child.fn.line('.'), child.fn.col('.') - 1 }
  if to[1] < from[1] or (to[1] == from[1] and to[2] < from[2]) then
    from, to = to, from
  end
  eq(from, selection_from)
  eq(to, selection_to)

  child.ensure_normal_mode()
end

local validate_selection1d = function(line, col, keys, selection_col_from, selection_col_to, visual_mode)
  validate_selection({ line }, { 1, col }, keys, { 1, selection_col_from }, { 1, selection_col_to }, visual_mode)
end

-- Custom mocks
local mock_comment_operators = function()
  -- Imitate Lua commenting
  child.lua([[
    _G.comment_operator = function()
      vim.o.operatorfunc = 'v:lua.operatorfunc'
      return 'g@'
    end

    _G.comment_line = function() return _G.comment_operator() .. '_' end

    _G.operatorfunc = function()
      local from, to = vim.fn.line("'["), vim.fn.line("']")
      local lines = vim.api.nvim_buf_get_lines(0, from - 1, to, false)
      local new_lines = vim.tbl_map(function(x) return '-- ' .. x end, lines)
      vim.api.nvim_buf_set_lines(0, from - 1, to, false, new_lines)
    end

    vim.keymap.set('n', 'gc', _G.comment_operator, { expr = true, replace_keycodes = false })
    vim.keymap.set('n', 'gcc', _G.comment_line, { expr = true, replace_keycodes = false })
  ]])
end

-- Time constants
local default_delay, postkeys_check_delay, redraw_interval = 1000, 50, 50
local small_time = helpers.get_time_const(10)

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = function() child.setup() end,
    post_once = child.stop,
  },
  n_retry = helpers.get_n_retry(2),
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  load_module()

  -- Global variable
  eq(child.lua_get('type(_G.MiniClue)'), 'table')

  -- Autocommand group
  eq(child.fn.exists('#MiniClue'), 1)

  -- Highlight groups
  child.cmd('hi clear')
  load_module()
  local validate_hl_group = function(name, ref) expect.match(child.cmd_capture('hi ' .. name), ref) end

  validate_hl_group('MiniClueBorder', 'links to FloatBorder')
  validate_hl_group('MiniClueDescGroup', 'links to DiagnosticFloatingWarn')
  validate_hl_group('MiniClueDescSingle', 'links to NormalFloat')
  validate_hl_group('MiniClueNextKey', 'links to DiagnosticFloatingHint')
  validate_hl_group('MiniClueNextKeyWithPostkeys', 'links to DiagnosticFloatingError')
  validate_hl_group('MiniClueSeparator', 'links to DiagnosticFloatingInfo')
  validate_hl_group('MiniClueTitle', 'links to FloatTitle')
end

T['setup()']['creates `config` field'] = function()
  load_module()

  eq(child.lua_get('type(_G.MiniClue.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniClue.config.' .. field), value) end

  expect_config('clues', {})
  expect_config('triggers', {})

  expect_config('window.delay', 1000)
  expect_config('window.config', {})
  expect_config('window.scroll_down', '<C-d>')
  expect_config('window.scroll_up', '<C-u>')
end

T['setup()']['respects `config` argument'] = function()
  load_module({ window = { delay = 10 } })
  eq(child.lua_get('MiniClue.config.window.delay'), 10)
end

T['setup()']['validates `config` argument'] = function()
  local expect_config_error = function(config, name, target_type)
    expect.error(load_module, vim.pesc(name) .. '.*' .. vim.pesc(target_type), config)
  end

  expect_config_error('a', 'config', 'table')

  expect_config_error({ clues = 'a' }, 'clues', 'table')
  expect_config_error({ triggers = 'a' }, 'triggers', 'table')

  expect_config_error({ window = 'a' }, 'window', 'table')
  expect_config_error({ window = { delay = 'a' } }, 'window.delay', 'number')
  expect_config_error({ window = { config = 'a' } }, 'window.config', 'table or callable')
  expect_config_error({ window = { scroll_down = 1 } }, 'window.scroll_down', 'string')
  expect_config_error({ window = { scroll_up = 1 } }, 'window.scroll_up', 'string')
end

T['setup()']['ensures colors'] = function()
  load_module()
  child.cmd('colorscheme default')
  expect.match(child.cmd_capture('hi MiniClueBorder'), 'links to FloatBorder')
end

T['setup()']['creates mappings for `@` and `Q`'] = function()
  load_module()
  expect.match(child.lua_get("vim.fn.maparg('@', 'n', false, true).desc"), 'macro.*mini%.clue')
  expect.match(child.lua_get("vim.fn.maparg('Q', 'n', false, true).desc"), 'macro.*mini%.clue')

  -- Mappings should respect [count]
  type_keys('qq', 'ia<Esc>', 'q')

  type_keys('2@q')
  eq(get_lines(), { 'aaa' })

  type_keys('2Q')
  eq(get_lines(), { 'aaaaa' })

  -- Should not create mapping if it is already taken
  child.api.nvim_set_keymap('n', 'Q', '<Cmd>echo 1<CR>', { desc = 'My Q' })
  child.api.nvim_set_keymap('n', '@', '<Cmd>echo 2<CR>', { desc = 'My @' })

  load_module()
  eq(child.lua_get("vim.fn.maparg('Q', 'n', false, true).desc"), 'My Q')
  eq(child.lua_get("vim.fn.maparg('@', 'n', false, true).desc"), 'My @')
end

T['setup()']['respects "human-readable" key names'] = function()
  child.g.mapleader = '_'
  make_test_map('n', '<Space><Space>')
  make_test_map('n', '<Space><C-x>')
  make_test_map('n', '<Leader>a')

  load_module({
    clues = {
      { mode = 'n', keys = '<Space><Space>', postkeys = '<Space>' },
      { mode = 'n', keys = '<Space><C-x>', postkeys = '<Space>' },
      { mode = 'n', keys = '<Leader>a', postkeys = '<Leader>' },
    },
    triggers = { { mode = 'n', keys = '<Space>' }, { mode = 'n', keys = '<Leader>' } },
  })
  validate_trigger_keymap('n', '<Space>')
  validate_trigger_keymap('n', '_')

  type_keys(' ', ' ', '<C-x>')
  eq(get_test_map_count('n', '  '), 1)
  eq(get_test_map_count('n', ' <C-x>'), 1)

  type_keys('<Esc>')

  type_keys('_', 'a', 'a')
  eq(get_test_map_count('n', '_a'), 2)
end

T['setup()']['respects "raw" key names'] = function()
  local ctrl_x = replace_termcodes('<C-x>')
  make_test_map('n', '<Space><Space>')
  make_test_map('n', '<Space><C-x>')

  load_module({
    clues = {
      { mode = 'n', keys = '  ', postkeys = ' ' },
      { mode = 'n', keys = ' ' .. ctrl_x, postkeys = ' ' },
    },
    triggers = { { mode = 'n', keys = ' ' } },
  })
  validate_trigger_keymap('n', '<Space>')

  type_keys(' ', ' ', '<C-x>')
  eq(get_test_map_count('n', '  '), 1)
  eq(get_test_map_count('n', replace_termcodes(' <C-x>')), 1)
end

T['setup()']['creates triggers for already created buffers'] = function()
  local init_buf_id = child.api.nvim_get_current_buf()
  local other_buf_id = child.api.nvim_create_buf(true, false)

  load_module({ triggers = { { mode = 'n', keys = 'g' } } })
  validate_trigger_keymap('n', 'g')

  validate_trigger_keymap('n', 'g', init_buf_id)
  validate_trigger_keymap('n', 'g', other_buf_id)
end

T['setup()']['creates triggers for an array of modes'] = function()
  load_module({ triggers = { { mode = { 'n', 'x' }, keys = 'g' } } })
  validate_trigger_keymap('n', 'g')
  validate_trigger_keymap('x', 'g')
  validate_no_trigger_keymap('c', 'g')
end

T['setup()']['creates triggers only in listed buffers'] = function()
  local buf_id_nolisted = child.api.nvim_create_buf(false, true)
  make_test_map('n', '<Space>a')
  load_module({ triggers = { { mode = 'n', keys = '<Space>' } }, window = { delay = 0 } })
  validate_no_trigger_keymap('n', '<Space>', buf_id_nolisted)

  local buf_id_nolisted_new = child.api.nvim_create_buf(false, true)
  validate_no_trigger_keymap('n', '<Space>', buf_id_nolisted_new)
end

T['setup()']['ensures valid triggers on `LspAttach` event'] = function()
  child.set_size(10, 40)
  child.cmd([[au LspAttach * lua vim.keymap.set('n', '<Space>a', ':echo 1<CR>', { buffer = true })]])
  load_module({ triggers = { { mode = 'n', keys = '<Space>' } }, window = { delay = 0 } })

  child.cmd('doautocmd LspAttach')

  type_keys(' ')
  child.expect_screenshot()
end

T['setup()']['ensures valid triggers on selected special buffers'] = function()
  local make_ft_buf = function(ft)
    local buf_id = child.api.nvim_create_buf(false, true)
    child.api.nvim_set_option_value('filetype', ft, { buf = buf_id })
    return buf_id
  end

  local validate_trigger = function(ft, buf_id_existing)
    child.api.nvim_set_current_buf(child.api.nvim_create_buf(false, true))
    child.bo.filetype = ft
    validate_trigger_keymap('n', '<Space>', 0)
    validate_trigger_keymap('n', '<Space>', buf_id_existing)
  end

  child.cmd('au FileType help,git nmap <buffer> <Space>a :echo 1<CR>')

  local buf_id_help = make_ft_buf('help')
  local buf_id_git = make_ft_buf('git')

  load_module({ triggers = { { mode = 'n', keys = '<Space>' } }, window = { delay = 0 } })

  validate_trigger('help', buf_id_help)
  validate_trigger('git', buf_id_git)
end

T['setup()']["works with 'mini.starter'"] = function()
  child.lua('require("mini.starter").open()')
  local triggers = {
    { mode = 'n', keys = '<Space>' },
    { mode = 'n', keys = 'g' },
  }
  load_module({ triggers = triggers, window = { delay = 0 } })

  -- Should not override query updaters (common for "g", "s", "z" triggers)
  validate_trigger_keymap('n', '<Space>', 0)
  validate_no_trigger_keymap('n', 'g', 0)
end

T['setup()']['respects `vim.b.miniclue_disable`'] = function()
  local init_buf_id = child.api.nvim_get_current_buf()
  local other_buf_id = child.api.nvim_create_buf(true, false)
  child.api.nvim_buf_set_var(other_buf_id, 'miniclue_disable', true)

  load_module({ triggers = { { mode = 'n', keys = 'g' } } })
  validate_trigger_keymap('n', 'g')

  validate_trigger_keymap('n', 'g', init_buf_id)
  validate_no_trigger_keymap('n', 'g', other_buf_id)

  -- Should allow setting `vim.b.miniclue_disable` inside autocommand
  child.lua([[vim.api.nvim_create_autocmd(
    'BufAdd',
    { callback = function(data) vim.b[data.buf].miniclue_disable = true end }
  )]])
  local another_buf_id = child.api.nvim_create_buf(true, false)
  validate_no_trigger_keymap('n', 'g', another_buf_id)
end

T['setup()']['respects `vim.b.miniclue_config`'] = function()
  local init_buf_id = child.api.nvim_get_current_buf()
  child.lua([[
    _G.miniclue_config = { triggers = { { mode = 'n', keys = '<Space>' } } }
    vim.b.miniclue_config = _G.miniclue_config

    vim.api.nvim_create_autocmd(
      'BufAdd',
      { callback = function(data) vim.b[data.buf].miniclue_config = _G.miniclue_config end }
    )]])

  load_module({ triggers = { { mode = 'n', keys = 'g' } } })
  validate_trigger_keymap('n', 'g', init_buf_id)
  validate_trigger_keymap('n', '<Space>', init_buf_id)

  local other_buf_id = child.api.nvim_create_buf(true, false)
  validate_trigger_keymap('n', 'g', other_buf_id)
  validate_trigger_keymap('n', '<Space>', other_buf_id)
end

T['setup()']['respects `vim.b.miniclue_config` in "natural" `FileType` event'] = function()
  child.lua([[
    vim.api.nvim_create_autocmd(
      'FileType',
      {
        callback = function(data)
          vim.b[data.buf].miniclue_config = { triggers = { { mode = 'n', keys = '<Space>' } } }
        end
      }
    )]])

  load_module()
  child.cmd('edit tmp.lua')
  validate_trigger_keymap('n', '<Space>')
end

T['enable_all_triggers()'] = new_set()

local enable_all_triggers = forward_lua('MiniClue.enable_all_triggers')

T['enable_all_triggers()']['works'] = function()
  local init_buf_id = child.api.nvim_get_current_buf()
  local other_buf_id = child.api.nvim_create_buf(true, false)
  local disabled_buf_id = child.api.nvim_create_buf(true, false)
  child.g.miniclue_disable = true
  -- Should respect `vim.b.miniclue_disable`
  child.api.nvim_buf_set_var(disabled_buf_id, 'miniclue_disable', true)

  load_module({ triggers = { { mode = 'n', keys = '<Space>' } } })
  validate_no_trigger_keymap('n', '<Space>', init_buf_id)
  validate_no_trigger_keymap('n', '<Space>', other_buf_id)
  validate_no_trigger_keymap('n', '<Space>', disabled_buf_id)

  child.g.miniclue_disable = false

  enable_all_triggers()
  validate_trigger_keymap('n', '<Space>', init_buf_id)
  validate_trigger_keymap('n', '<Space>', other_buf_id)
  validate_no_trigger_keymap('n', '<Space>', disabled_buf_id)
end

T['enable_all_triggers()']['respects `vim.b.miniclue_config`'] = function()
  local init_buf_id = child.api.nvim_get_current_buf()
  local other_buf_id = child.api.nvim_create_buf(true, false)
  child.g.miniclue_disable = true

  load_module({ triggers = { { mode = 'n', keys = '<Space>' } } })
  validate_no_trigger_keymap('n', '<Space>', init_buf_id)
  validate_no_trigger_keymap('n', '<Space>', other_buf_id)

  child.g.miniclue_disable = false
  child.b.miniclue_config = { triggers = { { mode = 'n', keys = 'g' } } }

  enable_all_triggers()
  validate_trigger_keymap('n', '<Space>', init_buf_id)
  validate_trigger_keymap('n', 'g', init_buf_id)
  validate_trigger_keymap('n', '<Space>', other_buf_id)
  validate_no_trigger_keymap('n', 'g', other_buf_id)
end

T['enable_buf_triggers()'] = new_set()

local enable_buf_triggers = forward_lua('MiniClue.enable_buf_triggers')

T['enable_buf_triggers()']['works'] = function()
  child.g.miniclue_disable = true
  load_module({ triggers = { { mode = 'n', keys = '<Space>' } } })
  validate_no_trigger_keymap('n', '<Space>')

  child.g.miniclue_disable = false

  -- Uses current buffer by default
  enable_buf_triggers()
  validate_trigger_keymap('n', '<Space>')
end

T['enable_buf_triggers()']['allows 0 for current buffer'] = function()
  child.g.miniclue_disable = true
  load_module({ triggers = { { mode = 'n', keys = '<Space>' } } })
  validate_no_trigger_keymap('n', '<Space>')

  child.g.miniclue_disable = false

  enable_buf_triggers(0)
  validate_trigger_keymap('n', '<Space>')
end

T['enable_buf_triggers()']['respects `buf_id`'] = function()
  local init_buf_id = child.api.nvim_get_current_buf()
  local other_buf_id = child.api.nvim_create_buf(true, false)

  child.g.miniclue_disable = true
  load_module({ triggers = { { mode = 'n', keys = '<Space>' } } })

  validate_no_trigger_keymap('n', '<Space>', init_buf_id)
  validate_no_trigger_keymap('n', '<Space>', other_buf_id)

  child.g.miniclue_disable = false
  enable_buf_triggers(init_buf_id)

  validate_trigger_keymap('n', '<Space>', init_buf_id)
  validate_no_trigger_keymap('n', '<Space>', other_buf_id)
end

T['enable_buf_triggers()']['can be used in non-listed buffers'] = function()
  child.g.miniclue_disable = true
  load_module({ triggers = { { mode = 'n', keys = '<Space>' } } })

  -- Scratch
  local buf_id_scratch = child.api.nvim_create_buf(false, true)
  child.api.nvim_set_current_buf(buf_id_scratch)
  validate_no_trigger_keymap('n', '<Space>')

  child.g.miniclue_disable = false

  enable_buf_triggers()
  validate_trigger_keymap('n', '<Space>')

  -- Help
  child.g.miniclue_disable = true
  child.cmd('help')
  validate_no_trigger_keymap('n', '<Space>')

  child.g.miniclue_disable = false

  enable_buf_triggers()
  validate_trigger_keymap('n', '<Space>')
end

T['enable_buf_triggers()']['validates arguments'] = function()
  load_module()
  expect.error(function() enable_buf_triggers('a') end, '`buf_id`.*buffer identifier')
end

T['enable_buf_triggers()']['respects `vim.b.miniclue_config`'] = function()
  child.g.miniclue_disable = true
  load_module({ triggers = { { mode = 'n', keys = '<Space>' } } })
  validate_no_trigger_keymap('n', '<Space>')

  child.b.miniclue_config = { triggers = { { mode = 'n', keys = 'g' } } }
  child.g.miniclue_disable = false

  enable_buf_triggers(0)
  validate_trigger_keymap('n', '<Space>')
  validate_trigger_keymap('n', 'g')
end

T['disable_all_triggers()'] = new_set()

local disable_all_triggers = forward_lua('MiniClue.disable_all_triggers')

T['disable_all_triggers()']['works'] = function()
  local init_buf_id = child.api.nvim_get_current_buf()
  local other_buf_id = child.api.nvim_create_buf(true, false)
  local disabled_buf_id = child.api.nvim_create_buf(true, false)

  -- Should respect `vim.b.miniclue_disable` and do nothing in disabled buffers
  child.api.nvim_buf_set_var(disabled_buf_id, 'miniclue_disable', true)
  child.api.nvim_buf_set_keymap(disabled_buf_id, 'n', '<Space>', '<Cmd>echo 1<CR>', {})
  local has_custom_mapping_in_disabled_buffer = function()
    local lua_cmd =
      string.format([[vim.api.nvim_buf_call(%d, function() return vim.fn.maparg(' ', 'n') end)]], disabled_buf_id)
    local rhs = child.lua_get(lua_cmd)
    return rhs:find('echo 1') ~= nil
  end

  load_module({ triggers = { { mode = 'n', keys = '<Space>' }, { mode = 'i', keys = '<C-R>' } } })
  validate_trigger_keymap('n', '<Space>', init_buf_id)
  validate_trigger_keymap('i', '<C-R>', init_buf_id)
  validate_trigger_keymap('n', '<Space>', other_buf_id)
  validate_trigger_keymap('i', '<C-R>', other_buf_id)
  eq(has_custom_mapping_in_disabled_buffer(), true)

  disable_all_triggers()
  validate_no_trigger_keymap('n', '<Space>', init_buf_id)
  validate_no_trigger_keymap('i', '<C-R>', init_buf_id)
  validate_no_trigger_keymap('n', '<Space>', other_buf_id)
  validate_no_trigger_keymap('i', '<C-R>', other_buf_id)
  eq(has_custom_mapping_in_disabled_buffer(), true)
end

T['disable_all_triggers()']['respects `vim.b.miniclue_config`'] = function()
  local init_buf_id = child.api.nvim_get_current_buf()
  local other_buf_id = child.api.nvim_create_buf(true, false)

  child.b.miniclue_config = { triggers = { { mode = 'n', keys = 'g' } } }
  load_module({ triggers = { { mode = 'n', keys = '<Space>' } } })
  validate_trigger_keymap('n', '<Space>', init_buf_id)
  validate_trigger_keymap('n', 'g', init_buf_id)
  validate_trigger_keymap('n', '<Space>', other_buf_id)

  disable_all_triggers()
  validate_no_trigger_keymap('n', '<Space>', init_buf_id)
  validate_no_trigger_keymap('n', 'g', init_buf_id)
  validate_no_trigger_keymap('n', '<Space>', other_buf_id)
end

T['disable_buf_triggers()'] = new_set()

local disable_buf_triggers = forward_lua('MiniClue.disable_buf_triggers')

T['disable_buf_triggers()']['works'] = function()
  load_module({ triggers = { { mode = 'n', keys = '<Space>' }, { mode = 'i', keys = '<C-R>' } } })
  validate_trigger_keymap('n', '<Space>')
  validate_trigger_keymap('i', '<C-R>')

  -- Uses current buffer by default
  disable_buf_triggers()
  validate_no_trigger_keymap('n', '<Space>')
  validate_no_trigger_keymap('i', '<C-R>')
end

T['disable_buf_triggers()']['allows 0 for current buffer'] = function()
  load_module({ triggers = { { mode = 'n', keys = '<Space>' } } })
  validate_trigger_keymap('n', '<Space>')

  disable_buf_triggers(0)
  validate_no_trigger_keymap('n', '<Space>')
end

T['disable_buf_triggers()']['respects `buf_id`'] = function()
  local init_buf_id = child.api.nvim_get_current_buf()
  local other_buf_id = child.api.nvim_create_buf(true, false)

  load_module({ triggers = { { mode = 'n', keys = '<Space>' } } })

  validate_trigger_keymap('n', '<Space>', init_buf_id)
  validate_trigger_keymap('n', '<Space>', other_buf_id)

  disable_buf_triggers(init_buf_id)

  validate_no_trigger_keymap('n', '<Space>', init_buf_id)
  validate_trigger_keymap('n', '<Space>', other_buf_id)
end

T['disable_buf_triggers()']['validates arguments'] = function()
  load_module()
  expect.error(function() disable_buf_triggers('a') end, '`buf_id`.*buffer identifier')
end

T['disable_buf_triggers()']['respects `vim.b.miniclue_config`'] = function()
  child.b.miniclue_config = { triggers = { { mode = 'n', keys = 'g' } } }
  load_module({ triggers = { { mode = 'n', keys = '<Space>' } } })
  validate_trigger_keymap('n', '<Space>')
  validate_trigger_keymap('n', 'g')

  disable_buf_triggers(0)
  validate_no_trigger_keymap('n', '<Space>')
  validate_no_trigger_keymap('n', 'g')
end

T['ensure_all_triggers()'] = new_set()

local ensure_all_triggers = forward_lua('MiniClue.ensure_all_triggers')

T['ensure_all_triggers()']['works'] = function()
  child.set_size(10, 40)
  make_test_map('n', '<Space>a')
  load_module({ triggers = { { mode = 'n', keys = '<Space>' } }, window = { delay = 0 } })

  -- Create buffer-local mappings **after** enabling triggers which disrupts
  -- trigger mapping (although it is `<nowait>`). `ensure_all_triggers()`
  -- should fix this for all buffers.
  child.api.nvim_buf_set_keymap(0, 'n', '<Space>b', ':echo 1CR>', {})

  local buf_id_new = child.api.nvim_create_buf(true, false)
  child.api.nvim_buf_set_keymap(buf_id_new, 'n', '<Space>c', ':echo 2CR>', {})

  ensure_all_triggers()

  type_keys(' ')
  child.expect_screenshot()
  type_keys('<Esc>')

  child.api.nvim_set_current_buf(buf_id_new)
  type_keys(' ')
  child.expect_screenshot()
end

T['ensure_buf_triggers()'] = new_set()

local ensure_buf_triggers = forward_lua('MiniClue.ensure_buf_triggers')

T['ensure_buf_triggers()']['works'] = function()
  child.set_size(10, 40)
  make_test_map('n', '<Space>a')
  load_module({ triggers = { { mode = 'n', keys = '<Space>' } }, window = { delay = 0 } })

  -- Create a buffer-local mapping **after** enabling triggers which disrupts
  -- trigger mapping (although it is `<nowait>`). `ensure_buf_triggers()`
  -- should fix this.
  child.api.nvim_buf_set_keymap(0, 'n', '<Space>b', ':echo 1CR>', {})

  ensure_buf_triggers()

  type_keys(' ')
  child.expect_screenshot()
end

T['ensure_buf_triggers()']['validates arguments'] = function()
  load_module()
  expect.error(function() ensure_buf_triggers('a') end, '`buf_id`.*buffer identifier')
end

T['set_mapping_desc()'] = new_set()

local set_mapping_desc = forward_lua('MiniClue.set_mapping_desc')

local validate_mapping_desc = function(mode, lhs, ref_desc) eq(child.fn.maparg(lhs, mode, false, true).desc, ref_desc) end

T['set_mapping_desc()']['adds new description'] = function()
  child.api.nvim_set_keymap('n', '<Space>a', ':echo 1<CR>', {})

  load_module()
  set_mapping_desc('n', '<Space>a', 'New desc')
  validate_mapping_desc('n', '<Space>a', 'New desc')
end

T['set_mapping_desc()']['updates existing description'] = function()
  child.api.nvim_set_keymap('n', '<Space>a', ':echo 1<CR>', { desc = 'Old desc' })

  load_module()
  set_mapping_desc('n', '<Space>a', 'New desc')
  validate_mapping_desc('n', '<Space>a', 'New desc')
end

T['set_mapping_desc()']['prefers buffer-local mapping'] = function()
  child.api.nvim_set_keymap('n', '<Space>a', ':echo 1<CR>', {})
  child.api.nvim_buf_set_keymap(0, 'n', '<Space>a', ':echo 2<CR>', {})

  load_module()
  set_mapping_desc('n', '<Space>a', 'New desc')
  validate_mapping_desc('n', '<Space>a', 'New desc')

  child.api.nvim_buf_del_keymap(0, 'n', '<Space>a')
  child.lua([[_G.map_data = vim.fn.maparg('<Space>a', 'n', false, true)]])
  eq(child.lua_get('_G.map_data.desc'), vim.NIL)
  eq(child.lua_get('_G.map_data.buffer'), 0)
end

T['set_mapping_desc()']['works for mapping with callback'] = function()
  child.lua([[vim.keymap.set('n', '<Space>a', function() _G.been_here = true end)]])

  load_module()
  set_mapping_desc('n', '<Space>a', 'New desc')
  child.lua([[_G.map_data = vim.fn.maparg('<Space>a', 'n', false, true)]])
  eq(child.lua_get('_G.map_data.desc'), 'New desc')
  eq(child.lua_get('type(_G.map_data.callback)'), 'function')
end

T['set_mapping_desc()']['validates input'] = function()
  load_module()
  expect.error(function() set_mapping_desc(1, 'aaa', 'New') end, '`mode`.*string')
  expect.error(function() set_mapping_desc('n', 1, 'New') end, '`lhs`.*string')
  expect.error(function() set_mapping_desc('n', 'aaa', 1) end, '`desc`.*string')
end

T['set_mapping_desc()']['handles incorrect usage'] = function()
  load_module()

  -- When no mapping found
  expect.error(function() set_mapping_desc('n', 'aaa', 'New') end, 'No mapping found for mode "n" and LHS "aaa"')

  -- When input is not valid
  make_test_map('n', 'aaa')
  expect.error(function() set_mapping_desc('n', 'aaa', 'Improper desc\0') end, 'not a valid desc')
end

T['gen_clues'] = new_set()

T['gen_clues']['g()'] = new_set()

T['gen_clues']['g()']['works'] = function()
  -- Check this only on Neovim>=0.11, as there are many new built-in mappings
  if child.fn.has('nvim-0.11') == 0 then return end

  child.lua([[
    local miniclue = require('mini.clue')
    miniclue.setup({
      clues = { miniclue.gen_clues.g() },
      triggers = { { mode = 'n', keys = 'g' }, { mode = 'x', keys = 'g' } },
      window = { delay = 0, config = { width = 50 } },
    })
  ]])
  child.cmd('unmap g%')

  child.set_size(67, 55)
  type_keys('g')
  child.expect_screenshot()

  type_keys('<Esc>')
  child.set_size(19, 55)
  type_keys('v', 'g')
  child.expect_screenshot()
end

T['gen_clues']['square_brackets()'] = new_set()

T['gen_clues']['square_brackets()']['works'] = function()
  -- Check this only on Neovim>=0.11, as there are many new built-in mappings
  if child.fn.has('nvim-0.11') == 0 then return end
  child.set_size(43, 66)

  child.lua([[
    local miniclue = require('mini.clue')
    miniclue.setup({
      clues = { miniclue.gen_clues.square_brackets() },
      triggers = { { mode = 'n', keys = '[' }, { mode = 'n', keys = ']' } },
      window = { delay = 0, config = { width = 66 } },
    })
  ]])

  type_keys('[')
  local ignore_text = child.fn.has('nvim-0.12') == 0 and { 28 } or {}
  child.expect_screenshot({ ignore_text = ignore_text })
  type_keys('<Esc>')
  type_keys(']')
  child.expect_screenshot()
end

T['gen_clues']['z()'] = new_set()

T['gen_clues']['z()']['works'] = function()
  child.lua([[
    local miniclue = require('mini.clue')
    miniclue.setup({
      clues = { miniclue.gen_clues.z() },
      triggers = { { mode = 'n', keys = 'z' }, { mode = 'x', keys = 'z' } },
      window = { delay = 0, config = { width = 52 } },
    })
  ]])

  child.set_size(51, 55)
  type_keys('z')
  child.expect_screenshot()

  type_keys('<Esc>')
  child.set_size(10, 55)
  type_keys('v', 'z')
  child.expect_screenshot()
end

T['gen_clues']['windows()'] = new_set()

T['gen_clues']['windows()']['works'] = function()
  -- Check this only on Neovim>=0.10, as there are many new built-in mappings
  if child.fn.has('nvim-0.10') == 0 then return end

  child.lua([[
    local miniclue = require('mini.clue')
    miniclue.setup({
      clues = { miniclue.gen_clues.windows() },
      triggers = { { mode = 'n', keys = '<C-w>' } },
      window = { delay = 0, config = { width = 45 } },
    })
  ]])

  child.set_size(47, 48)
  type_keys('<C-w>')
  child.expect_screenshot()

  child.set_size(15, 48)
  type_keys('g')
  child.expect_screenshot()
end

T['gen_clues']['windows()']['respects `opts.submode_move`'] = function()
  child.lua([[
    local miniclue = require('mini.clue')
    miniclue.setup({
      clues = { miniclue.gen_clues.windows({ submode_move = true }) },
      triggers = { { mode = 'n', keys = '<C-w>' } },
    })
  ]])

  local win_init = get_window()
  local validate = function(keys_layouts)
    -- Set up
    set_window(win_init)
    type_keys('<C-w>')

    -- Test
    for _, v in ipairs(keys_layouts) do
      type_keys(v[1])
      eq(child.fn.winlayout(), v[2])
    end

    -- Clean up
    type_keys('<Esc>')
    set_window(win_init)
    child.cmd('only')
  end

  -- Left-right
  set_window(win_init)
  child.cmd('rightbelow vertical split')
  local win_right = get_window()

  validate({
    { 'L', { 'row', { { 'leaf', win_right }, { 'leaf', win_init } } } },
    { 'H', { 'row', { { 'leaf', win_init }, { 'leaf', win_right } } } },
    { 'L', { 'row', { { 'leaf', win_right }, { 'leaf', win_init } } } },
  })

  -- Top-bottom
  set_window(win_init)
  child.cmd('rightbelow split')
  local win_bottom = get_window()

  validate({
    { 'J', { 'col', { { 'leaf', win_bottom }, { 'leaf', win_init } } } },
    { 'K', { 'col', { { 'leaf', win_init }, { 'leaf', win_bottom } } } },
    { 'J', { 'col', { { 'leaf', win_bottom }, { 'leaf', win_init } } } },
  })

  -- Rotate up/left
  set_window(win_init)
  child.cmd('rightbelow vertical split')
  local win_row_two = get_window()
  child.cmd('rightbelow vertical split')
  local win_row_three = get_window()

  validate({
    { 'R', { 'row', { { 'leaf', win_row_two }, { 'leaf', win_row_three }, { 'leaf', win_init } } } },
    { 'R', { 'row', { { 'leaf', win_row_three }, { 'leaf', win_init }, { 'leaf', win_row_two } } } },
  })

  -- Rotate down/right
  set_window(win_init)
  child.cmd('rightbelow split')
  local win_col_two = get_window()
  child.cmd('rightbelow split')
  local win_col_three = get_window()

  validate({
    { 'r', { 'col', { { 'leaf', win_col_three }, { 'leaf', win_init }, { 'leaf', win_col_two } } } },
    { 'r', { 'col', { { 'leaf', win_col_two }, { 'leaf', win_col_three }, { 'leaf', win_init } } } },
  })

  -- Exchange
  set_window(win_init)
  child.cmd('rightbelow vertical split')
  local win_two = get_window()
  child.cmd('rightbelow vertical split')
  local win_three = get_window()

  validate({
    { 'x', { 'row', { { 'leaf', win_two }, { 'leaf', win_init }, { 'leaf', win_three } } } },
    { 'x', { 'row', { { 'leaf', win_init }, { 'leaf', win_two }, { 'leaf', win_three } } } },
  })
end

T['gen_clues']['windows()']['respects `opts.submode_navigate`'] = function()
  child.lua([[
    local miniclue = require('mini.clue')
    miniclue.setup({
      clues = { miniclue.gen_clues.windows({ submode_navigate = true }) },
      triggers = { { mode = 'n', keys = '<C-w>' } },
    })
  ]])

  local win_init = get_window()
  local validate = function(keys_wins)
    -- Set up
    set_window(win_init)
    type_keys('<C-w>')

    -- Test
    for _, v in ipairs(keys_wins) do
      type_keys(v[1])
      eq(get_window(), v[2])
    end

    -- Clean up
    type_keys('<Esc>')
    set_window(win_init)
    child.cmd('only')
  end

  -- Left-right
  set_window(win_init)
  child.cmd('rightbelow vertical split')
  local win_right = get_window()

  validate({ { 'l', win_right }, { 'h', win_init }, { 'l', win_right } })

  -- Next-previous
  set_window(win_init)
  child.cmd('rightbelow vertical split')
  local win_next = get_window()

  validate({ { 'w', win_next }, { 'W', win_init }, { 'w', win_next } })

  -- Up-down
  set_window(win_init)
  child.cmd('rightbelow split')
  local win_down = get_window()

  validate({ { 'j', win_down }, { 'k', win_init }, { 'j', win_down } })

  -- Top-bottom
  set_window(win_init)
  child.cmd('rightbelow split')
  local win_bottom = get_window()

  validate({ { 'b', win_bottom }, { 't', win_init }, { 'b', win_bottom } })

  -- Last accessed
  set_window(win_init)
  child.cmd('rightbelow vertical split')
  child.cmd('rightbelow vertical split')
  local win_alt = get_window()

  validate({ { 'p', win_alt }, { 'p', win_init }, { 'p', win_alt } })

  -- Tabs
  child.cmd('tabnew')
  local win_tab = get_window()

  validate({ { { 'g', 't' }, win_tab }, { { 'g', 'T' }, win_init }, { { 'g', '<Tab>' }, win_tab } })
end

T['gen_clues']['windows()']['respects `opts.submode_resize`'] = function()
  child.lua([[
    local miniclue = require('mini.clue')
    miniclue.setup({
      clues = { miniclue.gen_clues.windows({ submode_resize = true }) },
      triggers = { { mode = 'n', keys = '<C-w>' } },
    })
  ]])

  local win_init = get_window()
  local get_height = function() return child.api.nvim_win_get_height(0) end
  local get_width = function() return child.api.nvim_win_get_width(0) end

  -- Width
  set_window(win_init)
  child.cmd('rightbelow vertical split')
  local init_width = get_width()

  type_keys('<C-w>')

  type_keys('>')
  eq(get_width(), init_width + 1)
  type_keys('>')
  eq(get_width(), init_width + 2)

  type_keys('<')
  eq(get_width(), init_width + 1)
  type_keys('<')
  eq(get_width(), init_width)

  type_keys('<Esc>')
  set_window(win_init)
  child.cmd('only')

  -- Height
  set_window(win_init)
  child.cmd('rightbelow split')
  local init_height = get_height()

  type_keys('<C-w>')

  type_keys('+')
  eq(get_height(), init_height + 1)
  type_keys('+')
  eq(get_height(), init_height + 2)

  type_keys('-')
  eq(get_height(), init_height + 1)
  type_keys('-')
  eq(get_height(), init_height)
end

T['gen_clues']['builtin_completion()'] = new_set()

T['gen_clues']['builtin_completion()']['works'] = function()
  child.lua([[
    local miniclue = require('mini.clue')
    miniclue.setup({
      clues = { miniclue.gen_clues.builtin_completion() },
      triggers = { { mode = 'i', keys = '<C-x>' } },
      window = { delay = 0, config = { width = 40 } },
    })
  ]])
  child.set_size(23, 45)

  type_keys('i', '<C-x>')
  child.expect_screenshot()
end

T['gen_clues']['marks()'] = new_set()

T['gen_clues']['marks()']['works'] = function()
  child.lua([[
    local miniclue = require('mini.clue')
    miniclue.setup({
      clues = { miniclue.gen_clues.marks() },
      triggers = {
        { mode = 'n', keys = '`' },
        { mode = 'n', keys = 'g`' },
        { mode = 'n', keys = "'" },
        { mode = 'n', keys = "g'" },
        { mode = 'x', keys = '`' },
        { mode = 'x', keys = 'g`' },
        { mode = 'x', keys = "'" },
        { mode = 'x', keys = "g'" },
      },
      window = { delay = 0, config = { width = 45 } },
    })
  ]])
  child.set_size(20, 48)

  -- Normal mode
  type_keys("'")
  child.expect_screenshot()

  type_keys('<Esc>')
  type_keys("g'")
  child.expect_screenshot()

  type_keys('<Esc>')
  type_keys('`')
  child.expect_screenshot()

  type_keys('<Esc>')
  type_keys('g`')
  child.expect_screenshot()

  -- Visual mode
  type_keys('<Esc>')
  type_keys('v', "'")
  child.expect_screenshot()

  type_keys('<Esc>', '<Esc>')
  type_keys('v', "g'")
  child.expect_screenshot()

  type_keys('<Esc>', '<Esc>')
  type_keys('v', '`')
  child.expect_screenshot()

  type_keys('<Esc>', '<Esc>')
  type_keys('v', 'g`')
  child.expect_screenshot()
end

T['gen_clues']['registers()'] = new_set()

T['gen_clues']['registers()']['works'] = function()
  child.lua([[
    local miniclue = require('mini.clue')
    miniclue.setup({
      clues = { miniclue.gen_clues.registers() },
      triggers = {
        { mode = 'n', keys = '"' },
        { mode = 'x', keys = '"' },
        { mode = 'i', keys = '<C-r>' },
        { mode = 'c', keys = '<C-r>' },
      },
      window = { delay = 0, config = { width = 45 } },
    })
  ]])
  child.set_size(25, 48)

  type_keys('"')
  child.expect_screenshot()

  type_keys('<Esc>', 'v', '"')
  child.expect_screenshot()

  type_keys('<Esc>', '<Esc>', 'i', '<C-r>')
  child.expect_screenshot()
  type_keys('<C-o>')
  child.expect_screenshot()
  type_keys('<BS>', '<C-p>')
  child.expect_screenshot()
  type_keys('<BS>', '<C-r>')
  child.expect_screenshot()

  type_keys('<Esc>', '<Esc>', ':', '<C-r>')
  child.expect_screenshot()
  type_keys('<C-o>')
  child.expect_screenshot()
  type_keys('<BS>', '<C-r>')
  child.expect_screenshot()
end

T['gen_clues']['registers()']['respects `opts.show_contents`'] = function()
  child.lua([[
    local miniclue = require('mini.clue')
    miniclue.setup({
      clues = { miniclue.gen_clues.registers({ show_contents = true }) },
      triggers = {
        { mode = 'n', keys = '"' },
        { mode = 'x', keys = '"' },
        { mode = 'i', keys = '<C-r>' },
        { mode = 'c', keys = '<C-r>' },
      },
      window = { delay = 0, config = { width = 30 } },
    })
  ]])
  child.set_size(52, 35)

  -- Mock constant clipboard for better reproducibility of system registers
  -- (mostly on CI). As `setreg('+', '')` is not guaranteed to be working for
  -- system clipboard, use `g:clipboard` which copies/pastes nothing.
  child.lua([[
    local empty = function() return '' end
    vim.g.clipboard = {
      name  = 'myClipboard',
      copy  = { ['+'] = empty, ['*'] = empty },
      paste = { ['+'] = empty, ['*'] = empty },
    }
  ]])

  -- Populate registers
  set_lines({ 'aaa', 'bbb' })
  type_keys('"ayiw')
  type_keys('"xyip')
  type_keys('G', 'yiw')
  type_keys('gg', 'diw')

  type_keys('"')
  child.expect_screenshot()

  -- Assume all other triggers also show contents
end

-- Integration tests ==========================================================
T['Showing keys'] = new_set({ hooks = { pre_case = function() child.set_size(10, 40) end } })

T['Showing keys']['works'] = function()
  helpers.skip_if_slow()

  make_test_map('n', '<Space>aa')
  make_test_map('n', '<Space>ab')
  load_module({ triggers = { { mode = 'n', keys = '<Space>' } } })

  -- Window should be shown after debounced delay
  type_keys(' ')
  sleep(default_delay - small_time)
  child.expect_screenshot()

  type_keys('a')
  sleep(default_delay - small_time)
  child.expect_screenshot()
  sleep(small_time + small_time)
  child.expect_screenshot()

  -- Should use proper buffer name
  local buf_id = child.api.nvim_win_get_buf(1002)
  eq(child.api.nvim_buf_get_name(buf_id), 'miniclue://' .. buf_id .. '/content')
end

T['Showing keys']['respects `config.window.delay`'] = function()
  helpers.skip_if_slow()

  make_test_map('n', '<Space>aa')
  make_test_map('n', '<Space>ab')
  load_module({
    triggers = { { mode = 'n', keys = '<Space>' } },
    window = { delay = 0.5 * default_delay },
  })

  type_keys(' ')
  sleep(0.5 * default_delay - small_time)
  child.expect_screenshot()

  type_keys('a')
  sleep(0.5 * default_delay - small_time)
  child.expect_screenshot()
  sleep(small_time + small_time)
  child.expect_screenshot()
end

T['Showing keys']['allows zero delay'] = function()
  make_test_map('n', '<Space>a')
  load_module({
    triggers = { { mode = 'n', keys = '<Space>' } },
    window = { delay = 0 },
  })

  -- Window should be shown immediately
  type_keys(' ')
  child.expect_screenshot()
end

T['Showing keys']['respects `config.window.config`'] = function()
  make_test_map('n', '<Space>a')
  load_module({
    triggers = { { mode = 'n', keys = '<Space>' } },
    window = { delay = 0, config = { border = 'double', title = 'Custom title to check truncation' } },
  })

  type_keys(' ')
  child.expect_screenshot()
  type_keys('<Esc>')

  -- Should properly truncate title
  child.lua([[
    local title = string.sub('abcdefgijklmnopqrstuvwxyzabcdefgijklmnopqrstuvwxyz', -vim.o.columns)
    MiniClue.config.window.config = { width = vim.o.columns, title = title }
  ]])
  type_keys(' ')
  child.expect_screenshot()
end

T['Showing keys']["respects 'winborder' option"] = function()
  if child.fn.has('nvim-0.11') == 0 then MiniTest.skip("'winborder' option is present on Neovim>=0.11") end
  make_test_map('n', '<Space>a')
  load_module({ triggers = { { mode = 'n', keys = '<Space>' } }, window = { delay = 0 } })

  local validate = function(winborder)
    child.o.winborder = winborder
    type_keys(' ')
    child.expect_screenshot()
    type_keys('<Esc>')
  end

  validate('rounded')

  -- Should prefer explicitly configured value over 'winborder'
  child.lua('MiniClue.config.window.config.border = "double"')
  validate('rounded')

  -- Should work with "string array" 'winborder'
  if child.fn.has('nvim-0.12') == 0 then MiniTest.skip("String array 'winborder' is present on Neovim>=0.12") end
  child.lua('MiniClue.config.window.config.border = nil')
  validate('+,-,+,|,+,-,+,|')
end

T['Showing keys']['can have `config.window.config.width="auto"`'] = function()
  make_test_map('n', '<Space>a')
  load_module({
    triggers = { { mode = 'n', keys = '<Space>' } },
    window = { delay = 0, config = { width = 'auto' } },
  })

  type_keys(' ')
  child.expect_screenshot()
end

T['Showing keys']['can have callable `config.window.config`'] = function()
  make_test_map('n', '<Space>a')
  make_test_map('n', '<Space>b')
  load_module({ triggers = { { mode = 'n', keys = '<Space>' } }, window = { delay = 0 } })

  -- Should be called with buffer identifier with already set lines
  child.lua([[MiniClue.config.window.config = function(buf_id)
    -- Should also allow special non-built-in values
    return { height = vim.api.nvim_buf_line_count(buf_id) + 2, width = 'auto' }
  end]])
  type_keys(' ')
  child.expect_screenshot()
end

T['Showing keys']['can have "auto" for `row` and `col` in window config'] = function()
  make_test_map('n', '<Space>a')
  load_module({
    triggers = { { mode = 'n', keys = '<Space>' } },
    window = { delay = 0, config = { row = 'auto', col = 'auto' } },
  })

  -- Should "stick" to anchor ('SE' by default)
  type_keys(' ')
  child.expect_screenshot()

  type_keys('<Esc>')
  child.lua('MiniClue.config.window.config.anchor = "SW"')
  type_keys(' ')
  child.expect_screenshot()

  type_keys('<Esc>')
  child.lua('MiniClue.config.window.config.anchor = "NW"')
  type_keys(' ')
  child.expect_screenshot()

  type_keys('<Esc>')
  child.lua('MiniClue.config.window.config.anchor = "NE"')
  type_keys(' ')
  child.expect_screenshot()
end

T['Showing keys']['can work with small instance dimensions'] = function()
  --Stylua: ignore
  load_module({
    clues = {
      { mode = 'n', keys = '<Space>a' },
      { mode = 'n', keys = '<Space>b' },
      { mode = 'n', keys = '<Space>c' },
      { mode = 'n', keys = '<Space>d' },
    },
    triggers = { { mode = 'n', keys = '<Space>' } },
    window = { delay = 0 },
  })

  child.set_size(5, 12)
  type_keys(' ')
  child.expect_screenshot()
end

T['Showing keys']['indicates that description is truncated'] = function()
  load_module({
    clues = {
      { mode = 'n', keys = '<Space>a', desc = 'A very long description' },
    },
    triggers = { { mode = 'n', keys = '<Space>' } },
    window = { delay = 0, config = { width = 15 } },
  })

  child.set_size(5, 20)
  type_keys(' ')
  child.expect_screenshot()
end

T['Showing keys']['uses query clue as title'] = function()
  load_module({
    clues = {
      { mode = 'n', keys = '<Space>a', desc = 'Group a' },
      { mode = 'n', keys = '<Space>aa', desc = 'Subgroup aa' },
      { mode = 'n', keys = '<Space>ba', desc = 'Subgroup ba' },
    },
    triggers = { { mode = 'n', keys = '<Space>' } },
    window = { delay = 0, config = { width = 20 } },
  })

  child.api.nvim_set_keymap('n', '<Space>aaa', '<Nop>', { desc = 'Do aaa' })
  child.api.nvim_set_keymap('n', '<Space>aab', '<Nop>', { desc = 'Do aab' })
  child.api.nvim_set_keymap('n', '<Space>baa', '<Nop>', { desc = 'Do baa' })
  child.api.nvim_set_keymap('n', '<Space>bab', '<Nop>', { desc = 'Do bab' })
  child.api.nvim_set_keymap('n', '<Space>caa', '<Nop>', { desc = 'Do caa' })

  child.set_size(10, 30)
  local validate = function(keys)
    type_keys(keys)
    child.expect_screenshot()
  end

  -- Should show trigger keys (not description/clue)
  validate(' ')
  -- Should show `<Space>a` clue
  validate('a')
  -- Should show `<Space>aa` clue, even if is a subgroup
  validate('a')
  -- Should work after `<BS>`
  validate('<BS>')
  -- Should fall back to showing keys if they have no clue
  type_keys('<BS>')
  validate('b')
  -- Should try using only current subgroup (even if there is no parent clue)
  validate('a')
  -- Should work for a group with 1 key
  type_keys('<BS>', '<BS>')
  validate('c')
  validate('a')
end

T['Showing keys']['respects `scroll_down` and `scroll_up` in `config.window`'] = function()
  child.set_size(8, 40)

  --stylua: ignore
  load_module({
    clues = {
      { mode = 'n', keys = '<Space>a' }, { mode = 'n', keys = '<Space>b' },
      { mode = 'n', keys = '<Space>c' }, { mode = 'n', keys = '<Space>d' },
      { mode = 'n', keys = '<Space>e' }, { mode = 'n', keys = '<Space>f' },
      { mode = 'n', keys = '<Space>g' }
    },
    triggers = { { mode = 'n', keys = '<Space>' } },
    window = { delay = 0 },
  })

  -- With default key
  type_keys(' ')
  child.expect_screenshot()

  -- Should not change `'scroll'` window option
  child.lua('_G.clue_win_id = math.max(unpack(vim.api.nvim_list_wins()))')
  local clue_win_scroll_value = child.lua_get('vim.wo[_G.clue_win_id].scroll')
  local validate_scroll_opt = function() eq(child.lua_get('vim.wo[_G.clue_win_id].scroll'), clue_win_scroll_value) end

  type_keys('<C-d>')
  child.expect_screenshot()
  -- - Should not be able to scroll past edge
  type_keys('<C-d>')
  child.expect_screenshot()
  validate_scroll_opt()

  type_keys('<C-u>')
  child.expect_screenshot()
  -- - Should not be able to scroll past edge
  type_keys('<C-u>')
  child.expect_screenshot()
  validate_scroll_opt()

  type_keys('<Esc>')

  -- With different keys
  child.lua([[MiniClue.config.window.scroll_down = '<C-f>']])
  child.lua([[MiniClue.config.window.scroll_up = '<C-b>']])

  type_keys(' ')
  child.expect_screenshot()

  type_keys('<C-f>')
  child.expect_screenshot()

  type_keys('<C-b>')
  child.expect_screenshot()

  type_keys('<Esc>')

  -- With empty string (should disable special treatment)
  child.lua([[MiniClue.config.window.scroll_down = '']])
  child.lua([[MiniClue.config.window.scroll_up = '']])

  type_keys('<Space>', '<C-d>')
  child.expect_screenshot()

  type_keys('<Space>', '<C-u>')
  child.expect_screenshot()
end

T['Showing keys']['highlights group descriptions differently'] = function()
  load_module({
    clues = {
      { mode = 'n', keys = '<Space>a', desc = 'Single #1' },
      { mode = 'n', keys = '<Space>b', desc = '+Group' },
      { mode = 'n', keys = '<Space>c', desc = 'Single #2' },
      { mode = 'n', keys = '<Space>ba' },
      { mode = 'n', keys = '<Space>bb' },
    },
    triggers = { { mode = 'n', keys = '<Space>' } },
    window = { delay = 0 },
  })

  type_keys(' ')
  child.expect_screenshot()
end

T['Showing keys']['highlights next key with postkeys differently'] = function()
  load_module({
    clues = {
      { mode = 'n', keys = '<Space>a', desc = 'Without postkeys #1' },
      { mode = 'n', keys = '<Space>b', desc = 'With postkey', postkeys = '<Space>' },
      { mode = 'n', keys = '<Space>c', desc = 'Without postkeys #2' },
    },
    triggers = { { mode = 'n', keys = '<Space>' } },
    window = { delay = 0 },
  })

  type_keys(' ')
  child.expect_screenshot()
end

T['Showing keys']['scroll is not persistent'] = function()
  child.set_size(7, 40)
  --stylua: ignore
  load_module({
    clues = {
      { mode = 'n', keys = '<Space>a' }, { mode = 'n', keys = '<Space>b' },
      { mode = 'n', keys = '<Space>c' }, { mode = 'n', keys = '<Space>d' },
      { mode = 'n', keys = '<Space>e' }, { mode = 'n', keys = '<Space>f' },

      { mode = 'n', keys = '<Space>ga' }, { mode = 'n', keys = '<Space>gb' },
      { mode = 'n', keys = '<Space>gc' }, { mode = 'n', keys = '<Space>gd' },
      { mode = 'n', keys = '<Space>ge' }, { mode = 'n', keys = '<Space>gf' },

      { mode = 'n', keys = '_a' }, { mode = 'n', keys = '_b' },
      { mode = 'n', keys = '_c' }, { mode = 'n', keys = '_d' },
      { mode = 'n', keys = '_e' }, { mode = 'n', keys = '_f' },
    },
    triggers = { { mode = 'n', keys = '<Space>' }, { mode = 'n', keys = '_' } },
    window = { delay = 0 },
  })

  type_keys(' ', '<C-d>', '<C-d>', '<C-d>', '<C-d>')
  child.expect_screenshot()

  type_keys('g')
  child.expect_screenshot()

  type_keys('<Esc>')
  type_keys('_')
  child.expect_screenshot()
end

T['Showing keys']['properly translates special keys'] = function()
  make_test_map('n', '<Space><Space><<f')
  make_test_map('n', '<Space><Space><<g')
  load_module({ triggers = { { mode = 'n', keys = '<Space>' } }, window = { delay = 0 } })

  type_keys(' ')
  child.expect_screenshot()
  type_keys(' ')
  child.expect_screenshot()
  type_keys('<')
  child.expect_screenshot()
  type_keys('<')
  child.expect_screenshot()
end

T['Showing keys']['respects tabline, statusline, cmdheight'] = function()
  child.set_size(7, 40)

  --stylua: ignore
  load_module({
    clues = {
      { mode = 'n', keys = '<Space>a' }, { mode = 'n', keys = '<Space>b' },
      { mode = 'n', keys = '<Space>c' }, { mode = 'n', keys = '<Space>d' },
      { mode = 'n', keys = '<Space>e' }, { mode = 'n', keys = '<Space>f' },
    },
    triggers = { { mode = 'n', keys = '<Space>' } },
    window = { delay = 0 },
  })

  local validate = function(screenshot_opts)
    type_keys(' ')
    child.expect_screenshot(screenshot_opts)
    type_keys('<Esc>')
  end

  -- Tabline
  child.o.showtabline = 2
  validate({ ignore_text = { 1 }, ignore_attr = { 1 } })
  child.o.showtabline = 0

  -- Statusline
  child.o.laststatus = 0
  validate()
  child.o.laststatus = 2

  -- Command line height
  child.o.cmdheight = 2
  validate({ ignore_text = { 6, 7 }, ignore_attr = { 6, 7 } })

  -- - Zero command line height
  child.o.cmdheight = 0
  validate()
end

T['Showing keys']['works with small available dimensions'] = function()
  -- Check this only on Neovim>=0.12, as there is a slight change in
  -- highlighting command line area
  if child.fn.has('nvim-0.12') == 0 then return end

  child.set_size(5, 40)
  child.o.showtabline, child.o.laststatus = 0, 0
  child.o.cmdheight = 4

  load_module({
    clues = { { mode = 'n', keys = '<Space>a' }, { mode = 'n', keys = '<Space>b' } },
    triggers = { { mode = 'n', keys = '<Space>' } },
    window = { delay = 0 },
  })

  type_keys(' ')
  child.expect_screenshot()
end

T['Showing keys']['reacts to `VimResized`'] = function()
  child.set_size(7, 20)
  load_module({
    clues = {
      { mode = 'n', keys = '<Space>a' },
      { mode = 'n', keys = '<Space>b' },
      { mode = 'n', keys = '<Space>c' },
      { mode = 'n', keys = '<Space>d' },
    },
    triggers = { { mode = 'n', keys = '<Space>' } },
    window = { delay = 0 },
  })

  type_keys(' ')
  child.expect_screenshot()

  child.set_size(10, 40)
  child.expect_screenshot()
end

T['Showing keys']['works with multibyte characters'] = function()
  load_module({
    clues = {
      { mode = 'n', keys = '<Space>f', desc = 'Single-byte #1' },
      { mode = 'n', keys = '<Space>y', desc = 'Single-byte #2' },
      { mode = 'n', keys = '<Space>ф', desc = 'Не англомовний опис' },
      { mode = 'n', keys = '<Space>ы', desc = 'Тест на коректну ширину' },
      { mode = 'n', keys = '<Space>э', desc = 'Многобайтовая группа' },
      { mode = 'n', keys = '<Space>эю', desc = 'фыва' },
      { mode = 'n', keys = '<Space>эя', desc = 'йцукен' },
    },
    triggers = { { mode = 'n', keys = '<Space>' } },
    window = { delay = 0, config = { width = 'auto' } },
  })

  type_keys(' ')
  child.expect_screenshot()
  helpers.skip_on_windows('Windows has different collation order')
  type_keys('э')
  child.expect_screenshot()
end

T['Showing keys']['works in Command-line window'] = function()
  make_test_map('n', '<Space>f')
  load_module({ triggers = { { mode = 'n', keys = '<Space>' } }, window = { delay = 0 } })
  child.o.timeoutlen = small_time

  type_keys('q:')
  type_keys(' ')

  child.expect_screenshot()

  sleep(small_time + small_time)
  type_keys('f')

  -- Closing floating window is allowed only on Neovim>=0.10.
  -- See https://github.com/neovim/neovim/issues/24452 .
  if child.fn.has('nvim-0.10') == 1 then child.expect_screenshot() end

  eq(get_test_map_count('n', '<Space>f'), 1)

  type_keys(':q<CR>')
end

T['Showing keys']['does not trigger unnecessary events'] = function()
  make_test_map('n', '<Space>aa')
  load_module({ triggers = { { mode = 'n', keys = '<Space>' } }, window = { delay = 0 } })

  -- Window should be shown after debounced delay
  child.cmd('au BufEnter,BufWinEnter,BufLeave * lua _G.n_events = (_G.n_events or 0) + 1')
  type_keys(' ')
  child.expect_screenshot()

  type_keys('a', 'a')
  eq(get_test_map_count('n', ' aa'), 1)
  eq(child.lua_get('_G.n_events'), vim.NIL)
end

T['Showing keys']['respects `vim.b.miniclue_config`'] = function()
  make_test_map('n', '<Space>a')
  load_module({ triggers = { { mode = 'n', keys = '<Space>' } }, window = { delay = 0 } })
  child.b.miniclue_config = { window = { config = { width = 20 } } }

  type_keys(' ')
  child.expect_screenshot()
end

T['Clues'] = new_set({ hooks = { pre_case = function() child.set_size(10, 40) end } })

T['Clues']['can be configured after load'] = function()
  load_module({ triggers = { { mode = 'n', keys = '<Space>' } }, window = { delay = 0 } })
  child.lua([[MiniClue.config.clues = { { mode = 'n', keys = '<Space>a' } }]])

  type_keys(' ')
  child.expect_screenshot()
end

T['Clues']['uses human-readable names for special keys'] = function()
  child.set_size(20, 40)
  child.cmd('nmap <Space><Space> :echo 1<CR>')
  child.cmd('nmap <Space><Tab> :echo 2<CR>')
  child.cmd('nmap <Space><End> :echo 3<CR>')
  child.cmd('nmap <Space><PageUp> :echo 4<CR>')
  child.cmd('nmap <Space><C-x> :echo 5<CR>')
  child.cmd('nmap <Space><C-j> :echo 6<CR>')
  child.cmd('nmap <Space><C-S-j> :echo 6.1<CR>')
  child.cmd('nmap <Space><C-M-j> :echo 6.2<CR>')
  child.cmd('nmap <Space><Right> :echo 7<CR>')
  child.cmd('nmap <Space><C-Right> :echo 8<CR>')
  child.cmd('nmap <Space><S-Right> :echo 9<CR>')
  child.cmd('nmap <Space><kRight> :echo 10<CR>')
  child.cmd('nmap <Space>< :echo 11<CR>')
  child.cmd('nmap <Space><F1> :echo 12<CR>')
  child.cmd('nmap <Space><S-F1> :echo 13<CR>')
  load_module({ triggers = { { mode = 'n', keys = '<Space>' } }, window = { delay = 0 } })

  type_keys(' ')
  child.expect_screenshot()
end

T['Clues']['are properly sorted'] = function()
  child.set_size(15, 40)
  --stylua: ignore
  local lhs_arr = {
    '<Space>0',     '<Space>9',     '<Space>a', '<Space>A', '<Space>x', '<Space>X',
    '<Space><C-a>', '<Space><C-x>', '<Space>:', '<Space>/'
  }
  vim.tbl_map(function(lhs) make_test_map('n', lhs) end, lhs_arr)

  load_module({ triggers = { { mode = 'n', keys = '<Space>' } }, window = { delay = 0 } })

  type_keys(' ')
  child.expect_screenshot()
end

T['Clues']['has proper precedence'] = function()
  -- config.clue < global mapping desc < buffer mapping desc.
  -- If mapping doesn't have description, clue should use empty string because
  -- it shows the most accurate information.
  child.api.nvim_buf_set_keymap(0, 'n', '<Space>a', '<Nop>', { desc = 'Buffer-local <Space>a' })
  child.api.nvim_buf_set_keymap(0, 'n', '<Space>b', '<Nop>', {})
  child.api.nvim_set_keymap('n', '<Space>a', '<Nop>', { desc = 'Global <Space>a' })
  child.api.nvim_set_keymap('n', '<Space>b', '<Nop>', { desc = 'Global <Space>b' })
  child.api.nvim_set_keymap('n', '<Space>c', '<Nop>', { desc = 'Global <Space>c' })
  child.api.nvim_set_keymap('n', '<Space>d', '<Nop>', {})

  load_module({
    clues = {
      { mode = 'n', keys = '<Space>a', desc = 'Clue <Space>a' },
      { mode = 'n', keys = '<Space>b', desc = 'Clue <Space>b' },
      { mode = 'n', keys = '<Space>c', desc = 'Clue <Space>c' },
      { mode = 'n', keys = '<Space>d', desc = 'Clue <Space>d' },
      { mode = 'n', keys = '<Space>e', desc = 'Clue <Space>e' },
    },
    triggers = { { mode = 'n', keys = '<Space>' } },
    window = { delay = 0 },
  })

  type_keys(' ')
  child.expect_screenshot()
end

T['Clues']['handles no description'] = function()
  child.api.nvim_set_keymap('n', '<Space>a', '<Nop>', {})
  load_module({
    clues = {
      { mode = 'n', keys = '<Space>b' },
      { mode = 'n', keys = '<Space>ca' },
      { mode = 'n', keys = '<Space>cb' },
    },
    triggers = { { mode = 'n', keys = '<Space>' } },
    window = { delay = 0 },
  })

  type_keys(' ')
  child.expect_screenshot()
end

T['Clues']['handles an array of modes'] = function()
  load_module({
    clues = { { mode = { 'n', 'x' }, keys = '<Space>a', desc = 'Clue <Space>a' } },
    triggers = { { mode = { 'n', 'x' }, keys = '<Space>' } },
    window = { delay = 0 },
  })

  type_keys(' ')
  child.expect_screenshot()

  type_keys('<Esc>')
  type_keys('v', ' ')
  child.expect_screenshot()
end

T['Clues']['shows as group a single non-exact clue'] = function()
  load_module({
    clues = { { mode = 'n', keys = '<Space>aaa', desc = 'Clue <Space>a' } },
    triggers = { { mode = 'n', keys = '<Space>' } },
    window = { delay = 0 },
  })

  type_keys(' ')
  child.expect_screenshot()
  type_keys('a')
  child.expect_screenshot()
  type_keys('a')
  child.expect_screenshot()
end

T['Clues']['can have nested subarrays'] = function()
  load_module({
    clues = {
      { mode = 'n', keys = '<Space>a' },
      { { mode = 'n', keys = '<Space>b' } },
      { { { mode = 'n', keys = '<Space>c' } } },
    },
    triggers = { { mode = 'n', keys = '<Space>' } },
    window = { delay = 0 },
  })

  type_keys(' ')
  child.expect_screenshot()
end

T['Clues']['can have callables'] = function()
  child.lua([[
    _G.callable_clue_direct = function() return { mode = 'n', keys = '<Space>a' } end
    _G.callable_clue_direct_with_callable_desc = function()
      return { mode = 'n', keys = '<Space>b', desc = function() return 'From <Space>b callable' end }
    end
    _G.callable_clue_array = function()
      return {
        { mode = 'n', keys = '<Space>c' },
        { mode = 'n', keys = '<Space>d', desc = function() return 'From <Space>d callable' end },
      }
    end
  ]])
  load_module({ triggers = { { mode = 'n', keys = '<Space>' } }, window = { delay = 0 } })

  local validate = function()
    type_keys(' ')
    child.expect_screenshot()
    type_keys('<Esc>')
  end

  -- Direct
  child.lua([[MiniClue.config.clues = { _G.callable_clue_direct }]])
  validate()

  -- Nested in subarray
  child.lua([[MiniClue.config.clues = { { _G.callable_clue_direct } }]])
  validate()

  -- With callable description
  child.lua([[MiniClue.config.clues = { _G.callable_clue_direct_with_callable_desc }]])
  validate()

  -- Returns array of clues with normal and callable descriptions
  child.lua([[MiniClue.config.clues = { _G.callable_clue_array }]])
  validate()
end

T['Clues']['can have callable description'] = function()
  child.lua([[
    require('mini.clue').setup({
      clues = { { mode = 'n', keys = '<Space>a', desc = function() return 'From callable desc' end } },
      triggers = { { mode = 'n', keys = '<Space>' } },
      window = { delay = 0 },
    })
  ]])

  type_keys(' ')
  child.expect_screenshot()
end

T['Clues']['silently ignores non-valid clues'] = function()
  load_module({
    clues = {
      -- Valid
      { mode = 'n', keys = '<Space>a' },

      -- Non-valid
      '<Space>b',
      { mode = 1, keys = '<Space>c' },
      { mode = 'n', keys = 1 },
      { mode = 'n', keys = '<Space>e', desc = 1 },
      { mode = 'n', keys = '<Space>f', postkeys = 1 },
    },
    triggers = { { mode = 'n', keys = '<Space>' } },
    window = { delay = 0 },
  })

  type_keys(' ')
  child.expect_screenshot()
end

T['Clues']['can be overridden in later entries'] = function()
  -- Like if there is table entry which later is partially overridden in
  -- user-supplied one
  load_module({
    clues = {
      { { mode = 'n', keys = '<Space>a', desc = 'First <Space>a' } },
      { mode = 'n', keys = '<Space>a', desc = 'Second <Space>a' },

      { mode = 'n', keys = '<Space>b', desc = 'First <Space>b' },
      { mode = 'n', keys = '<Space>b', postkeys = '<Space>' },
    },
    triggers = { { mode = 'n', keys = '<Space>' } },
    window = { delay = 0 },
  })

  type_keys(' ')
  child.expect_screenshot()
end

T['Clues']['handles showing group clues after executing key with postkeys'] = function()
  make_test_map('n', '<Space>f')
  make_test_map('n', '<Space>ga')
  make_test_map('n', '<Space>gb')

  load_module({
    clues = {
      { mode = 'n', keys = '<Space>f', desc = 'With postkeys', postkeys = '<Space>' },
      { mode = 'n', keys = '<Space>g', desc = 'Group' },
      { mode = 'n', keys = '<Space>ga', desc = 'Key a' },
      { mode = 'n', keys = '<Space>gb', desc = 'Key b' },
    },
    triggers = { { mode = 'n', keys = '<Space>' } },
    window = { delay = 0 },
  })

  type_keys(' ', 'f')
  child.expect_screenshot()
  type_keys('g')
  child.expect_screenshot()
end

T['Clues']['respects `vim.b.miniclue_config`'] = function()
  load_module({
    clues = {
      { mode = 'n', keys = '<Space>a', desc = 'From global config' },
      { mode = 'n', keys = '<Space>b' },
    },
    triggers = { { mode = 'n', keys = '<Space>' } },
    window = { delay = 0 },
  })
  child.b.miniclue_config = {
    clues = {
      { mode = 'n', keys = '<Space>a', desc = 'From buffer-local config' },
      { mode = 'n', keys = '<Space>c' },
    },
  }

  type_keys(' ')
  child.expect_screenshot()
end

T['Postkeys'] = new_set({ hooks = { pre_case = function() child.set_size(10, 40) end } })

T['Postkeys']['works'] = function()
  make_test_map('n', '<Space>f')
  make_test_map('n', '<Space>x')

  load_module({
    clues = {
      { mode = 'n', keys = '<Space>f', postkeys = '<Space>' },
      { mode = 'n', keys = '<Space>x', postkeys = '<Space>' },
    },
    triggers = { { mode = 'n', keys = '<Space>' } },
    window = { delay = 0 },
  })

  type_keys(' ')
  child.expect_screenshot()
  type_keys('f')
  child.expect_screenshot()
  type_keys('x')
  child.expect_screenshot()

  type_keys('f', '<Esc>')

  eq(get_test_map_count('n', ' f'), 2)
  eq(get_test_map_count('n', ' x'), 1)
end

T['Postkeys']['works in edge cases'] = function()
  -- With "looped" submodes
  make_test_map('n', '<Space>a')
  make_test_map('n', '_b')

  load_module({
    clues = {
      { mode = 'n', keys = '<Space>a', postkeys = '_' },
      { mode = 'n', keys = '_b', postkeys = '<Space>' },
    },
    triggers = { { mode = 'n', keys = '<Space>' }, { mode = 'n', keys = '_' } },
    window = { delay = 0 },
  })

  type_keys(' ')
  child.expect_screenshot()
  type_keys('a')
  child.expect_screenshot()
  type_keys('b')
  child.expect_screenshot()

  type_keys('<Esc>')

  eq(get_test_map_count('n', ' a'), 1)
  eq(get_test_map_count('n', '_b'), 1)
end

T['Postkeys']['shows window immediately'] = function()
  make_test_map('n', '<Space>f')
  make_test_map('n', '<Space>x')

  load_module({
    clues = {
      { mode = 'n', keys = '<Space>f', postkeys = '<Space>' },
      { mode = 'n', keys = '<Space>x', postkeys = '<Space>' },
    },
    triggers = { { mode = 'n', keys = '<Space>' } },
    window = { delay = 10 },
  })

  type_keys(' ', 'f')
  child.expect_screenshot()
end

T['Postkeys']['closes window if postkeys do not end up key querying'] = function()
  load_module({
    clues = { { mode = 'n', keys = '<Space>a', desc = 'Desc', postkeys = 'G' } },
    triggers = { { mode = 'n', keys = '<Space>' } },
    window = { delay = 0 },
  })

  type_keys(' ', 'a')
  sleep(postkeys_check_delay + small_time)
  child.expect_screenshot()
end

T['Postkeys']['persists window if action changes tabpage'] = function()
  -- Check this only on Neovim>=0.10, as there are many new built-in mappings
  if child.fn.has('nvim-0.10') == 0 then return end

  load_module({
    clues = { { mode = 'n', keys = '<C-w>T', desc = 'Move to new tabpage', postkeys = '<C-w>' } },
    triggers = { { mode = 'n', keys = '<C-w>' } },
    window = { delay = 0 },
  })

  child.cmd('wincmd v')

  type_keys('<C-w>')
  child.expect_screenshot()
  type_keys('T')
  child.expect_screenshot({ ignore_text = { 1 }, ignore_attr = { 1 } })
end

T['Querying keys'] = new_set()

T['Querying keys']['works'] = function()
  make_test_map('n', '<Space>f')
  load_module({ triggers = { { mode = 'n', keys = '<Space>' } } })
  validate_trigger_keymap('n', '<Space>')

  type_keys(' ', 'f')
  eq(get_test_map_count('n', ' f'), 1)

  type_keys(10, ' ', 'f')
  eq(get_test_map_count('n', ' f'), 2)
end

T['Querying keys']['does not entirely block redraws'] = function()
  child.set_size(10, 40)
  set_lines({ 'aaaa' })
  child.lua([[
    local ns_id = vim.api.nvim_create_namespace('test')
    local n = 0
    _G.add_hl = function()
      local col = n
      local vim_hl = vim.fn.has('nvim-0.11') == 1 and vim.hl or vim.highlight
      vim.defer_fn(function()
        vim_hl.range(0, ns_id, 'Comment', { 0, col }, { 0, col + 1 }, {})
      end, 5)
      n = n + 1
    end
    vim.keymap.set('n', '<Space>f', _G.add_hl, { desc = 'Add hl' })]])

  load_module({
    clues = { { mode = 'n', keys = '<Space>f', postkeys = '<Space>' } },
    triggers = { { mode = 'n', keys = '<Space>' } },
  })

  type_keys('<Space>', 'f')
  -- - Redraws don't happen immediately but inside a repeating timer
  sleep(redraw_interval + small_time)
  child.expect_screenshot()

  type_keys('f')
  sleep(redraw_interval + small_time)
  child.expect_screenshot()
end

T['Querying keys']['allows trigger with more than one character'] = function()
  make_test_map('n', '<Space>aa')
  load_module({ triggers = { { mode = 'n', keys = '<Space>a' } } })
  validate_trigger_keymap('n', '<Space>a')

  type_keys(' ', 'a', 'a')
  eq(get_test_map_count('n', ' aa'), 1)

  type_keys(10, ' ', 'a', 'a')
  eq(get_test_map_count('n', ' aa'), 2)
end

T['Querying keys']["does not time out after 'timeoutlen'"] = function()
  make_test_map('n', '<Space>f')
  make_test_map('n', '<Space>ff')
  load_module({ triggers = { { mode = 'n', keys = '<Space>' } } })

  -- Should wait for next key as there are still multiple clues available
  child.o.timeoutlen = small_time
  type_keys(' ', 'f')
  sleep(2 * small_time)
  eq(get_test_map_count('n', ' f'), 0)
end

T['Querying keys']['takes into account user-supplied clues'] = function()
  child.set_size(10, 40)
  load_module({
    clues = {
      { mode = 'n', keys = '<Space>a', desc = 'My space a' },
    },
    triggers = { { mode = 'n', keys = '<Space>' } },
    window = { delay = 0 },
  })
  validate_trigger_keymap('n', '<Space>')

  type_keys(' ')
  child.expect_screenshot()
  type_keys('a')
  child.expect_screenshot()
end

T['Querying keys']['respects `<CR>`'] = function()
  make_test_map('n', '<Space>f')
  make_test_map('n', '<Space>ff')
  load_module({ triggers = { { mode = 'n', keys = '<Space>' } } })
  validate_trigger_keymap('n', '<Space>')

  -- `<CR>` should execute current query
  child.o.timeoutlen = small_time
  type_keys(' ', 'f', '<CR>')
  sleep(small_time + small_time)
  eq(get_test_map_count('n', ' f'), 1)
end

T['Querying keys']['respects `<Esc>`/`<C-c>`'] = function()
  make_test_map('n', '<Space>f')
  load_module({ triggers = { { mode = 'n', keys = '<Space>' } } })
  validate_trigger_keymap('n', '<Space>')

  -- `<Esc>` and `<C-c>` should stop current query
  local validate = function(key)
    type_keys(' ', key, 'f')
    child.ensure_normal_mode()
    eq(get_test_map_count('n', ' f'), 0)
  end

  validate('<Esc>')
  validate('<C-c>')
end

T['Querying keys']['respects `<BS>`'] = function()
  make_test_map('n', '<Space>f')
  make_test_map('n', '<Space>ff')
  load_module({ triggers = { { mode = 'n', keys = '<Space>' } } })
  validate_trigger_keymap('n', '<Space>')

  -- `<BS>` should remove latest key
  type_keys(' ', 'f', '<BS>', 'f', 'f')
  eq(get_test_map_count('n', ' f'), 0)
  eq(get_test_map_count('n', ' ff'), 1)
end

T['Querying keys']['can `<BS>` on first element'] = function()
  make_test_map('n', '<Space>f')
  make_test_map('n', ',gg')
  load_module({ triggers = { { mode = 'n', keys = '<Space>' }, { mode = 'n', keys = ',g' } } })
  validate_trigger_keymap('n', '<Space>')
  validate_trigger_keymap('n', ',g')

  type_keys(' ', '<BS>', ' ', 'f')
  eq(get_test_map_count('n', ' f'), 1)

  -- Removes first trigger element at once, not by characters
  type_keys(',g', '<BS>', ',g', 'g')
  eq(get_test_map_count('n', ',gg'), 1)
end

T['Querying keys']['can use scroll keys when window is not shown'] = function()
  make_test_map('n', '<Space>f')
  make_test_map('n', '<Space><C-f>')
  make_test_map('n', '<Space><C-b>')
  load_module({
    triggers = { { mode = 'n', keys = '<Space>' } },
    window = { scroll_down = '<C-f>', scroll_up = '<C-b>' },
  })
  validate_trigger_keymap('n', '<Space>')

  type_keys(' ', '<C-f>')
  eq(get_test_map_count('n', ' <C-f>'), 1)

  type_keys(' ', '<C-b>')
  eq(get_test_map_count('n', ' <C-b>'), 1)
end

T['Querying keys']['allows reaching longest keymap'] = function()
  make_test_map('n', '<Space>f')
  make_test_map('n', '<Space>fff')
  load_module({ triggers = { { mode = 'n', keys = '<Space>' } } })
  validate_trigger_keymap('n', '<Space>')

  child.o.timeoutlen = small_time
  type_keys(' ', 'f', 'f')
  sleep(small_time + small_time)
  type_keys('f')
  eq(get_test_map_count('n', ' f'), 0)
  eq(get_test_map_count('n', ' fff'), 1)
end

T['Querying keys']['executes even if no extra clues is set'] = function()
  load_module({ triggers = { { mode = 'c', keys = 'g' }, { mode = 'i', keys = 'g' } } })
  validate_trigger_keymap('c', 'g')
  validate_trigger_keymap('i', 'g')

  type_keys(':', 'g')
  eq(child.fn.getcmdline(), 'g')

  child.ensure_normal_mode()
  type_keys('i', 'g')
  eq(get_lines(), { 'g' })
end

T['Querying keys']['works with multibyte characters'] = function()
  make_test_map('n', '<Space>фф')
  make_test_map('n', '<Space>фы')
  load_module({
    clues = {
      { mode = 'n', keys = '<Space>фф', postkeys = '<Space>ф' },
      { mode = 'n', keys = '<Space>фы', postkeys = '<Space>ф' },
    },
    triggers = { { mode = 'n', keys = '<Space>ф' } },
  })
  validate_trigger_keymap('n', '<Space>ф')

  type_keys(' ф', 'ф', 'ы', 'ф', '<Esc>')
  eq(get_test_map_count('n', '<Space>фф'), 2)
  eq(get_test_map_count('n', '<Space>фы'), 1)
end

T['Querying keys']['works with special keys'] = function()
  child.cmd('nmap <Space><Space>  <Cmd>lua _G.space_space  = true<CR>')
  child.cmd('nmap <Space><Tab>    <Cmd>lua _G.space_tab    = true<CR>')
  child.cmd('nmap <Space><End>    <Cmd>lua _G.space_end    = true<CR>')
  child.cmd('nmap <Space><PageUp> <Cmd>lua _G.space_pageup = true<CR>')
  child.cmd('nmap <Space><C-x>    <Cmd>lua _G.space_ctrlx  = true<CR>')
  child.cmd('nmap <Space><        <Cmd>lua _G.space_lt     = true<CR>')
  load_module({ triggers = { { mode = 'n', keys = '<Space>' } } })

  local validate = function(key, suffix)
    type_keys(' ', key)
    eq(child.lua_get('_G.space_' .. suffix), true)
  end

  validate(' ', 'space')
  validate('<Tab>', 'tab')
  validate('<End>', 'end')
  validate('<PageUp>', 'pageup')
  validate('<C-x>', 'ctrlx')
  validate('<', 'lt')
end

T['Querying keys']["respects 'langmap'"] = function()
  make_test_map('n', '<Space>a')
  make_test_map('n', '<Space>A')
  make_test_map('n', '<Space>s')
  make_test_map('n', '<Space>S')
  make_test_map('n', '<Space>d')
  make_test_map('n', '<Space>D')

  child.o.langmap = [[фФ;aA,ыs,ЫS,вdВD]]
  load_module({ triggers = { { mode = 'n', keys = '<Space>' } } })

  local validate_key = function(from, to)
    local init_count = get_test_map_count('n', ' ' .. to)
    type_keys(' ', from)
    eq(get_test_map_count('n', ' ' .. to), init_count + 1)
  end

  validate_key('ф', 'a')
  validate_key('Ф', 'A')
  validate_key('ы', 's')
  validate_key('Ы', 'S')
  validate_key('в', 'd')
  validate_key('В', 'D')

  -- Special cases of 'langmap' currently don't work because later key
  -- reproducing with `nvim_feedkeys(keys, 'mit')` will inverse meaning second
  -- time.
  --
  -- make_test_map('n', '<Space>;')
  -- make_test_map('n', '<Space>:')
  -- child.o.langmap = [[:\;;\;:]]
  -- child.o.langmap = [[:\;\;:]]
  --
  -- make_test_map('n', '<Space>/')
  -- make_test_map('n', [[<Space>\]])
  -- child.o.langmap = [[\\/;/\\]]
  -- child.o.langmap = [[\\//\\]]
end

T['Reproducing keys'] = new_set()

T['Reproducing keys']['works for builtin keymaps in Normal mode'] = function()
  load_module({ triggers = { { mode = 'n', keys = 'g' } } })
  validate_trigger_keymap('n', 'g')

  -- `ge` (basic test)
  validate_move1d('aa bb', 3, { 'g', 'e' }, 1)

  -- `gg` (should avoid infinite recursion)
  validate_move({ 'aa', 'bb' }, { 2, 0 }, { 'g', 'g' }, { 1, 0 })

  -- `g~` (should work with operators)
  validate_edit1d('aa bb', 0, { 'g', '~', 'iw' }, 'AA bb', 0)

  -- `g'a` (should work with more than one character ahead)
  set_lines({ 'aa', 'bb' })
  set_cursor(2, 0)
  type_keys('ma')
  set_cursor(1, 0)
  type_keys("g'", 'a')
  eq(get_cursor(), { 2, 0 })
end

T['Reproducing keys']['works for user keymaps in Normal mode'] = function()
  -- Should work for both keymap created before and after making trigger
  make_test_map('n', '<Space>f')
  load_module({ triggers = { { mode = 'n', keys = '<Space>' } } })
  make_test_map('n', '<Space>g')

  validate_trigger_keymap('n', '<Space>')

  type_keys(' ', 'f')
  eq(get_test_map_count('n', ' f'), 1)
  eq(get_test_map_count('n', ' g'), 0)

  type_keys(' ', 'g')
  eq(get_test_map_count('n', ' f'), 1)
  eq(get_test_map_count('n', ' g'), 1)
end

T['Reproducing keys']['respects `[count]` in Normal mode'] = function()
  load_module({ triggers = { { mode = 'n', keys = 'g' } } })
  validate_trigger_keymap('n', 'g')

  validate_move1d('aa bb cc', 6, { '2', 'g', 'e' }, 1)
end

T['Reproducing keys']['respects `[register]` in Normal mode'] = function()
  child.lua([[
    _G.track_register = function()
      _G.register = vim.v.register
      vim.cmd('normal! g~iw')
    end
    vim.keymap.set('n', 'ge', _G.track_register)

    _G.track_register_expr = function()
      _G.register_expr = vim.v.register
      return 'g~iw'
    end
    vim.keymap.set('n', 'gE', _G.track_register_expr, { expr = true })
  ]])
  load_module({ triggers = { { mode = 'n', keys = 'g' } } })
  validate_trigger_keymap('n', 'g')

  validate_edit1d('AaA', 0, { '"x', 'g', 'e' }, 'aAa', 0)
  eq(child.lua_get('_G.register'), 'x')

  validate_edit1d('AaA', 0, { '"y', 'g', 'E' }, 'aAa', 0)
  eq(child.lua_get('_G.register_expr'), 'y')

  -- Works with special expression register "="
  child.lua([[
    vim.keymap.set('n', 'gd', function() return 'P' end, { expr = true })
  ]])
  validate_edit1d('xxx', 0, { '"=', '1+1<CR>', 'g', 'd' }, '2xxx', 0)
  eq(child.fn.mode(1), 'n')
end

T['Reproducing keys']['works in temporary Normal mode'] = function()
  load_module({
    triggers = { { mode = 'n', keys = 'g' }, { mode = 'o', keys = 'i' } },
  })
  validate_trigger_keymap('n', 'g')
  validate_trigger_keymap('o', 'i')

  -- One step keymap
  set_lines({ 'aa bb' })
  child.cmd('startinsert')
  type_keys('<C-o>', 'g', '~', 'tb')
  eq(child.fn.mode(), 'i')
  eq(get_lines(), { 'AA bb' })

  -- Currently doesn't work when there is trigger in Operator-pending mode
  -- Would be great if it could
  -- child.ensure_normal_mode()
  --
  -- set_lines({ 'aa bb' })
  -- child.cmd('startinsert')
  -- type_keys('<C-o>', 'g', '~', 'i', 'w')
  -- eq(child.fn.mode(), 'i')
  -- eq(get_lines(), { 'AA bb' })
end

T['Reproducing keys']['works for builtin keymaps in Insert mode'] = function()
  load_module({ triggers = { { mode = 'i', keys = '<C-x>' } } })
  validate_trigger_keymap('i', '<C-X>')

  set_lines({ 'aa aa', 'bb bb', '' })
  set_cursor(3, 0)
  type_keys('i', '<C-x>', '<C-l>')

  eq(child.fn.mode(), 'i')
  local complete_words = vim.tbl_map(function(x) return x.word end, child.fn.complete_info().items)
  eq(vim.tbl_contains(complete_words, 'aa aa'), true)
  eq(vim.tbl_contains(complete_words, 'bb bb'), true)
end

T['Reproducing keys']['works for user keymaps in Insert mode'] = function()
  -- Should work for both keymap created before and after making trigger
  make_test_map('i', '<Space>f')
  load_module({ triggers = { { mode = 'i', keys = '<Space>' } } })
  make_test_map('i', '<Space>g')

  validate_trigger_keymap('i', '<Space>')

  child.cmd('startinsert')

  type_keys(' ', 'f')
  eq(child.fn.mode(), 'i')
  eq(get_test_map_count('i', ' f'), 1)
  eq(get_test_map_count('i', ' g'), 0)

  type_keys(' ', 'g')
  eq(child.fn.mode(), 'i')
  eq(get_test_map_count('i', ' f'), 1)
  eq(get_test_map_count('i', ' g'), 1)
end

T['Reproducing keys']['does not reproduce register in Insert mode'] = function()
  child.api.nvim_buf_set_keymap(0, 'n', 'i', '"_cc', { noremap = true })
  load_module({ triggers = { { mode = 'i', keys = '<C-x>' } } })

  set_lines({ 'aa', '' })
  set_cursor(2, 0)
  type_keys('i', '<C-x>', '<C-v>')
  eq(get_lines()[2] ~= '"_', true)
end

T['Reproducing keys']['works for builtin keymaps in Visual mode'] = function()
  load_module({ triggers = { { mode = 'x', keys = 'g' }, { mode = 'x', keys = 'a' } } })
  validate_trigger_keymap('x', 'g')
  validate_trigger_keymap('x', 'a')

  -- `a'` (should work to update selection)
  validate_selection1d("'aa'", 1, { 'v', 'a', "'" }, 0, 3)

  -- Should preserve Visual submode
  validate_selection({ 'aa', 'bb', '', 'cc' }, { 1, 0 }, { 'V', 'a', 'p' }, { 1, 0 }, { 3, 0 }, 'V')
  validate_selection1d("'aa'", 1, "<C-v>a'", 0, 3, replace_termcodes('<C-v>'))

  -- `g?` (should work to manipulation selection)
  validate_edit1d('aa bb', 0, { 'v', 'iw', 'g', '?' }, 'nn bb', 0)
end

T['Reproducing keys']['works for user keymaps in Visual mode'] = function()
  -- Should work for both keymap created before and after making trigger
  make_test_map('x', '<Space>f')
  load_module({ triggers = { { mode = 'x', keys = '<Space>' } } })
  make_test_map('x', '<Space>g')

  validate_trigger_keymap('x', '<Space>')

  type_keys('v')

  type_keys(' ', 'f')
  eq(child.fn.mode(), 'v')
  eq(get_test_map_count('x', ' f'), 1)
  eq(get_test_map_count('x', ' g'), 0)

  type_keys(' ', 'g')
  eq(child.fn.mode(), 'v')
  eq(get_test_map_count('x', ' f'), 1)
  eq(get_test_map_count('x', ' g'), 1)

  -- Should preserve Visual submode
  child.ensure_normal_mode()
  type_keys('V')
  type_keys(' ', 'f')
  eq(child.fn.mode(), 'V')
  eq(get_test_map_count('x', ' f'), 2)

  child.ensure_normal_mode()
  type_keys('<C-v>')
  type_keys(' ', 'f')
  eq(child.fn.mode(), replace_termcodes('<C-v>'))
  eq(get_test_map_count('x', ' f'), 3)
end

T['Reproducing keys']['respects `[count]` in Visual mode'] = function()
  load_module({ triggers = { { mode = 'x', keys = 'a' } } })
  validate_trigger_keymap('x', 'a')

  validate_selection1d('aa bb cc', 0, { 'v', '2', 'a', 'w' }, 0, 5)
end

T['Reproducing keys']['respects `[register]` in Visual mode'] = function()
  child.lua([[
    _G.track_register = function()
      _G.register = vim.v.register
      vim.fn.feedkeys('g~', 'nx')
    end
    vim.keymap.set('x', 'ge', _G.track_register)

    _G.track_register_expr = function()
      _G.register_expr = vim.v.register
      return 'g~'
    end
    vim.keymap.set('x', 'gE', _G.track_register_expr, { expr = true })
  ]])
  load_module({ triggers = { { mode = 'x', keys = 'g' } } })
  validate_trigger_keymap('x', 'g')

  validate_edit1d('AaA', 0, { 'viw', '"x', 'g', 'e' }, 'aAa', 0)
  eq(child.lua_get('_G.register'), 'x')

  validate_edit1d('AaA', 0, { 'viw', '"y', 'g', 'E' }, 'aAa', 0)
  eq(child.lua_get('_G.register_expr'), 'y')
end

T['Reproducing keys']['works in Select mode'] = function()
  -- Should work for both keymap created before and after making trigger
  make_test_map('s', '<Space>f')
  load_module({ triggers = { { mode = 's', keys = '<Space>' } } })
  validate_trigger_keymap('s', '<Space>')

  type_keys('v', '<C-g>')
  eq(child.fn.mode(), 's')
  type_keys(' ', 'f')
  eq(get_test_map_count('s', ' f'), 1)
end

T['Reproducing keys']['Operator-pending mode'] = new_set({
  hooks = {
    pre_case = function()
      -- Make user keymap
      child.api.nvim_set_keymap('o', 'if', 'iw', {})
      child.api.nvim_set_keymap('o', 'iF', 'ip', {})

      -- Register trigger. Use zero delay in window to account for possible
      -- clearance of `v:count` and `v:register` inside window update.
      load_module({ triggers = { { mode = 'o', keys = 'i' } }, window = { delay = 0 } })
      validate_trigger_keymap('o', 'i')
    end,
  },
})

T['Reproducing keys']['Operator-pending mode']['c'] = function()
  validate_edit1d('aa bb cc', 3, { 'c', 'i', 'w', 'dd' }, 'aa dd cc', 5)

  -- Dot-repeat
  validate_edit1d('aa bb', 0, { 'c', 'i', 'w', 'dd', '<Esc>w.' }, 'dd dd', 4)

  -- Should respect register
  validate_edit1d('aaa', 0, { '"ac', 'i', 'w', 'xxx' }, 'xxx', 3)
  eq(child.fn.getreg('a'), 'aaa')

  -- User keymap
  validate_edit1d('aa bb cc', 3, { 'c', 'i', 'f', 'dd' }, 'aa dd cc', 5)

  -- Should respect `[count]`
  validate_edit1d('aa bb cc', 0, { 'c2', 'i', 'w', 'dd' }, 'ddbb cc', 2)
end

T['Reproducing keys']['Operator-pending mode']['d'] = function()
  validate_edit1d('aa bb cc', 3, { 'd', 'i', 'w' }, 'aa  cc', 3)

  -- Dot-rpeat
  validate_edit1d('aa bb cc', 0, { 'd', 'i', 'w', 'w.' }, '  cc', 1)

  -- Should respect register
  validate_edit1d('aaa', 0, { '"ad', 'i', 'w' }, '', 0)
  eq(child.fn.getreg('a'), 'aaa')

  -- User keymap
  validate_edit1d('aa bb cc', 3, { 'd', 'i', 'f' }, 'aa  cc', 3)

  -- Should respect `[count]`
  validate_edit1d('aa bb cc', 0, { 'd2', 'i', 'w' }, 'bb cc', 0)
end

T['Reproducing keys']['Operator-pending mode']['y'] = function()
  validate_edit1d('aa bb cc', 3, { 'y', 'i', 'w', 'P' }, 'aa bbbb cc', 4)

  -- Should respect register
  validate_edit1d('aaa', 0, { '"ay', 'i', 'w' }, 'aaa', 0)
  eq(child.fn.getreg('a'), 'aaa')

  -- User keymap
  validate_edit1d('aa bb cc', 3, { 'y', 'i', 'f', 'P' }, 'aa bbbb cc', 4)

  -- Should respect `[count]`
  validate_edit1d('aa bb cc', 0, { 'y2', 'i', 'w', 'P' }, 'aa aa bb cc', 2)
end

T['Reproducing keys']['Operator-pending mode']['~'] = function()
  child.o.tildeop = true

  validate_edit1d('aa bb', 0, { '~', 'i', 'w' }, 'AA bb', 0)
  validate_edit1d('aa bb', 1, { '~', 'i', 'w' }, 'AA bb', 0)
  validate_edit1d('aa bb', 3, { '~', 'i', 'w' }, 'aa BB', 3)

  -- Dot-repeat
  validate_edit1d('aa bb', 0, { '~', 'i', 'w', 'w.' }, 'AA BB', 3)

  -- User keymap
  validate_edit1d('aa bb', 0, { '~', 'i', 'f' }, 'AA bb', 0)

  -- Should respect `[count]`
  validate_edit1d('aa bb cc', 0, { '~3', 'i', 'w' }, 'AA BB cc', 0)
end

T['Reproducing keys']['Operator-pending mode']['g~'] = function()
  validate_edit1d('aa bb', 0, { 'g~', 'i', 'w' }, 'AA bb', 0)
  validate_edit1d('aa bb', 1, { 'g~', 'i', 'w' }, 'AA bb', 0)
  validate_edit1d('aa bb', 3, { 'g~', 'i', 'w' }, 'aa BB', 3)

  -- Dot-repeat
  validate_edit1d('aa bb', 0, { 'g~', 'i', 'w', 'w.' }, 'AA BB', 3)

  -- User keymap
  validate_edit1d('aa bb', 0, { 'g~', 'i', 'f' }, 'AA bb', 0)

  -- Should respect `[count]`
  validate_edit1d('aa bb cc', 0, { 'g~3', 'i', 'w' }, 'AA BB cc', 0)
end

T['Reproducing keys']['Operator-pending mode']['gu'] = function()
  validate_edit1d('AA BB', 0, { 'gu', 'i', 'w' }, 'aa BB', 0)
  validate_edit1d('AA BB', 1, { 'gu', 'i', 'w' }, 'aa BB', 0)
  validate_edit1d('AA BB', 3, { 'gu', 'i', 'w' }, 'AA bb', 3)

  -- Dot-repeat
  validate_edit1d('AA BB', 0, { 'gu', 'i', 'w', 'w.' }, 'aa bb', 3)

  -- User keymap
  validate_edit1d('AA BB', 0, { 'gu', 'i', 'f' }, 'aa BB', 0)

  -- Should respect `[count]`
  validate_edit1d('AA BB CC', 0, { 'gu3', 'i', 'w' }, 'aa bb CC', 0)
end

T['Reproducing keys']['Operator-pending mode']['gU'] = function()
  validate_edit1d('aa bb', 0, { 'gU', 'i', 'w' }, 'AA bb', 0)
  validate_edit1d('aa bb', 1, { 'gU', 'i', 'w' }, 'AA bb', 0)
  validate_edit1d('aa bb', 3, { 'gU', 'i', 'w' }, 'aa BB', 3)

  -- Dot-repeat
  validate_edit1d('aa bb', 0, { 'gU', 'i', 'w', 'w.' }, 'AA BB', 3)

  -- User keymap
  validate_edit1d('aa bb', 0, { 'gU', 'i', 'f' }, 'AA bb', 0)

  -- Should respect `[count]`
  validate_edit1d('aa bb cc', 0, { 'gU3', 'i', 'w' }, 'AA BB cc', 0)
end

T['Reproducing keys']['Operator-pending mode']['gq'] = function()
  child.lua([[_G.formatexpr = function()
    local from, to = vim.v.lnum, vim.v.lnum + vim.v.count - 1
    local new_lines = {}
    for _ = 1, vim.v.count do table.insert(new_lines, 'xxx') end
    vim.api.nvim_buf_set_lines(0, from - 1, to, false, new_lines)
  end]])
  child.bo.formatexpr = 'v:lua.formatexpr()'

  validate_edit({ 'aa', 'aa', '', 'bb' }, { 1, 0 }, { 'gq', 'i', 'p' }, { 'xxx', 'xxx', '', 'bb' }, { 1, 0 })

  -- Dot-repeat
  validate_edit(
    { 'aa', 'aa', '', 'bb', 'bb' },
    { 1, 0 },
    { 'gq', 'i', 'p', 'G.' },
    { 'xxx', 'xxx', '', 'xxx', 'xxx' },
    { 4, 0 }
  )

  -- User keymap
  validate_edit({ 'aa', 'aa', '', 'bb' }, { 1, 0 }, { 'gq', 'i', 'F' }, { 'xxx', 'xxx', '', 'bb' }, { 1, 0 })

  -- Should respect `[count]`
  validate_edit(
    { 'aa', '', 'bb', '', 'cc' },
    { 1, 0 },
    { 'gq3', 'i', 'p' },
    { 'xxx', 'xxx', 'xxx', '', 'cc' },
    { 1, 0 }
  )
end

T['Reproducing keys']['Operator-pending mode']['gw'] = function()
  child.o.textwidth = 5

  validate_edit({ 'aaa aaa', '', 'bb' }, { 1, 0 }, { 'gw', 'i', 'p' }, { 'aaa', 'aaa', '', 'bb' }, { 1, 0 })

  -- Dot-repeat
  validate_edit(
    { 'aaa aaa', '', 'bbb bbb' },
    { 1, 0 },
    { 'gw', 'i', 'p', 'G.' },
    { 'aaa', 'aaa', '', 'bbb', 'bbb' },
    { 4, 0 }
  )

  -- User keymap
  validate_edit({ 'aaa aaa', '', 'bb' }, { 1, 0 }, { 'gw', 'i', 'F' }, { 'aaa', 'aaa', '', 'bb' }, { 1, 0 })

  -- Should respect `[count]`
  validate_edit(
    { 'aaa aaa', '', 'bbb bbb', '', 'cc' },
    { 1, 0 },
    { 'gw3i', 'p', '' },
    { 'aaa', 'aaa', '', 'bbb', 'bbb', '', 'cc' },
    { 1, 0 }
  )
end

T['Reproducing keys']['Operator-pending mode']['g?'] = function()
  validate_edit1d('aa bb', 0, { 'g?', 'i', 'w' }, 'nn bb', 0)
  validate_edit1d('aa bb', 1, { 'g?', 'i', 'w' }, 'nn bb', 0)
  validate_edit1d('aa bb', 3, { 'g?', 'i', 'w' }, 'aa oo', 3)

  -- Dot-repeat
  validate_edit1d('aa bb', 0, { 'g?', 'i', 'w', 'w.' }, 'nn oo', 3)

  -- User keymap
  validate_edit1d('aa bb', 0, { 'g?', 'i', 'f' }, 'nn bb', 0)

  -- Should respect `[count]`
  validate_edit1d('aa bb cc', 0, { 'g?3', 'i', 'w' }, 'nn oo cc', 0)
end

T['Reproducing keys']['Operator-pending mode']['!'] = function()
  validate_edit({ 'cc', 'bb', '', 'aa' }, { 1, 0 }, { '!', 'i', 'p', 'sort<CR>' }, { 'bb', 'cc', '', 'aa' }, { 1, 0 })

  -- Dot-repeat
  validate_edit(
    { 'cc', 'bb', '', 'dd', 'aa' },
    { 1, 0 },
    { '!', 'i', 'p', 'sort<CR>G.' },
    { 'bb', 'cc', '', 'aa', 'dd' },
    { 4, 0 }
  )

  -- User keymap
  validate_edit({ 'cc', 'bb', '', 'aa' }, { 1, 0 }, { '!', 'i', 'F', 'sort<CR>' }, { 'bb', 'cc', '', 'aa' }, { 1, 0 })

  -- Should respect `[count]`
  validate_edit(
    { 'cc', 'bb', '', 'ee', 'dd', '', 'aa' },
    { 1, 0 },
    { '!3', 'i', 'p', 'sort<CR>' },
    { '', 'bb', 'cc', 'dd', 'ee', '', 'aa' },
    { 1, 0 }
  )
end

T['Reproducing keys']['Operator-pending mode']['='] = function()
  validate_edit({ 'aa', '\taa', '', 'bb' }, { 1, 0 }, { '=', 'i', 'p' }, { 'aa', 'aa', '', 'bb' }, { 1, 0 })

  -- Dot-repeat
  validate_edit(
    { 'aa', '\taa', '', 'bb', '\tbb' },
    { 1, 0 },
    { '=', 'i', 'p', 'G.' },
    { 'aa', 'aa', '', 'bb', 'bb' },
    { 4, 0 }
  )

  -- User keymap
  validate_edit({ 'aa', '\taa', '', 'bb' }, { 1, 0 }, { '=', 'i', 'F' }, { 'aa', 'aa', '', 'bb' }, { 1, 0 })

  -- Should respect `[count]`
  validate_edit(
    { 'aa', '\taa', '', 'bb', '\tbb', '', 'cc' },
    { 1, 0 },
    { '=3', 'i', 'p' },
    { 'aa', 'aa', '', 'bb', 'bb', '', 'cc' },
    { 1, 0 }
  )
end

T['Reproducing keys']['Operator-pending mode']['>'] = function()
  validate_edit({ 'aa', '', 'bb' }, { 1, 0 }, { '>', 'i', 'p' }, { '\taa', '', 'bb' }, { 1, 0 })

  -- Dot-repeat
  validate_edit({ 'aa', '', 'bb' }, { 1, 0 }, { '>', 'i', 'p', '.2j.' }, { '\t\taa', '', '\tbb' }, { 3, 0 })

  -- User keymap
  validate_edit({ 'aa', '', 'bb' }, { 1, 0 }, { '>', 'i', 'F' }, { '\taa', '', 'bb' }, { 1, 0 })

  -- Should respect `[count]`
  validate_edit({ 'aa', '', 'bb', '', 'cc' }, { 1, 0 }, { '>3', 'i', 'p' }, { '\taa', '', '\tbb', '', 'cc' }, { 1, 0 })
end

T['Reproducing keys']['Operator-pending mode']['<'] = function()
  validate_edit({ '\t\taa', '', 'bb' }, { 1, 0 }, { '<', 'i', 'p' }, { '\taa', '', 'bb' }, { 1, 0 })

  -- Dot-repeat
  validate_edit({ '\t\t\taa', '', '\tbb' }, { 1, 0 }, { '<', 'i', 'p', '.2j.' }, { '\taa', '', 'bb' }, { 3, 1 })

  -- User keymap
  validate_edit({ '\t\taa', '', 'bb' }, { 1, 0 }, { '<', 'i', 'F' }, { '\taa', '', 'bb' }, { 1, 0 })

  -- Should respect `[count]`
  validate_edit(
    { '\t\taa', '', '\t\tbb', '', 'cc' },
    { 1, 0 },
    { '<', '3', 'i', 'p' },
    { '\taa', '', '\tbb', '', 'cc' },
    { 1, 0 }
  )
end

T['Reproducing keys']['Operator-pending mode']['zf'] = function()
  local validate = function(keys, ref_last_folded_line)
    local lines = { 'aa', 'aa', '', 'bb', '', 'cc' }
    set_lines(lines)
    set_cursor(1, 0)

    type_keys(keys)

    for i = 1, ref_last_folded_line do
      eq(child.fn.foldclosed(i), 1)
    end

    for i = ref_last_folded_line + 1, #lines do
      eq(child.fn.foldclosed(i), -1)
    end
  end

  validate({ 'zf', 'i', 'p' }, 2)
  validate({ 'zf', 'i', 'F' }, 2)

  -- Should respect `[count]`
  validate({ 'zf3', 'i', 'p' }, 4)
end

T['Reproducing keys']['Operator-pending mode']['g@'] = function()
  child.o.operatorfunc = 'v:lua.operatorfunc'

  -- Charwise
  child.lua([[_G.operatorfunc = function()
    local from, to = vim.fn.col("'["), vim.fn.col("']")
    local line = vim.fn.line('.')

    vim.api.nvim_buf_set_text(0, line - 1, from - 1, line - 1, to, { 'xx' })
  end]])

  validate_edit1d('aa bb cc', 3, { 'g@', 'i', 'w' }, 'aa xx cc', 3)

  -- - Dot-repeat
  validate_edit1d('aa bb cc', 3, { 'g@', 'i', 'w', 'w.' }, 'aa xx xx', 6)

  -- - User keymap
  validate_edit1d('aa bb cc', 3, { 'g@', 'i', 'f' }, 'aa xx cc', 3)

  -- - Should respect `[count]`
  validate_edit1d('aa bb cc', 0, { 'g@3', 'i', 'w' }, 'xx cc', 0)

  -- Linewise
  child.lua([[_G.operatorfunc = function() vim.cmd("'[,']sort") end]])

  validate_edit({ 'cc', 'bb', '', 'aa' }, { 1, 0 }, { 'g@', 'i', 'p' }, { 'bb', 'cc', '', 'aa' }, { 1, 0 })

  -- - Dot-repeat
  validate_edit(
    { 'cc', 'bb', '', 'dd', 'aa' },
    { 1, 0 },
    { 'g@', 'i', 'p', 'G.' },
    { 'bb', 'cc', '', 'aa', 'dd' },
    { 4, 0 }
  )

  -- - User keymap
  validate_edit({ 'cc', 'bb', '', 'aa' }, { 1, 0 }, { 'g@', 'i', 'F' }, { 'bb', 'cc', '', 'aa' }, { 1, 0 })

  -- Should respect `[count]`
  validate_edit(
    { 'cc', 'bb', '', 'ee', 'dd', '', 'aa' },
    { 1, 0 },
    { 'g@3', 'i', 'p' },
    { '', 'bb', 'cc', 'dd', 'ee', '', 'aa' },
    { 1, 0 }
  )
end

T['Reproducing keys']['Operator-pending mode']['works with operator and textobject from triggers'] = function()
  load_module({ triggers = { { mode = 'n', keys = 'g' }, { mode = 'o', keys = 'i' } } })
  validate_trigger_keymap('n', 'g')
  validate_trigger_keymap('o', 'i')

  -- `g~`
  validate_edit1d('aa bb', 0, { 'g~', 'i', 'w' }, 'AA bb', 0)

  -- `g@`
  child.lua([[_G.operatorfunc = function() vim.cmd("'[,']sort") end]])
  child.o.operatorfunc = 'v:lua.operatorfunc'

  validate_edit({ 'cc', 'bb', '', 'aa' }, { 1, 0 }, { 'g@', 'i', 'p' }, { 'bb', 'cc', '', 'aa' }, { 1, 0 })
end

T['Reproducing keys']['Operator-pending mode']['respects forced submode'] = function()
  load_module({ triggers = { { mode = 'o', keys = '`' } } })
  validate_trigger_keymap('o', '`')

  -- Linewise
  set_lines({ 'aa', 'bbbb', 'cc' })
  set_cursor(2, 1)
  type_keys('mb')
  set_cursor(1, 0)
  type_keys('dV', '`', 'b')
  eq(get_lines(), { 'cc' })

  -- Blockwise
  set_lines({ 'aa', 'bbbb', 'cc' })
  set_cursor(3, 1)
  type_keys('mc')
  set_cursor(1, 0)
  type_keys('d\22', '`', 'c')
  eq(get_lines(), { '', 'bb', '' })
end

T['Reproducing keys']['works for builtin keymaps in Terminal mode'] = function()
  load_module({ triggers = { { mode = 't', keys = [[<C-\>]] } } })
  validate_trigger_keymap('t', [[<C-\>]])

  child.cmd('wincmd v')
  child.cmd('terminal')
  -- Wait for terminal to load
  vim.loop.sleep(6 * small_time)
  child.cmd('startinsert')
  eq(child.fn.mode(), 't')

  type_keys([[<C-\>]], '<C-n>')
  eq(child.fn.mode(), 'n')
end

T['Reproducing keys']['works for user keymaps in Terminal mode'] = function()
  -- Should work for both keymap created before and after making trigger
  make_test_map('t', '<Space>f')
  load_module({ triggers = { { mode = 't', keys = '<Space>' } } })
  make_test_map('t', '<Space>g')

  validate_trigger_keymap('t', '<Space>')

  child.cmd('wincmd v')
  child.cmd('terminal')
  -- Wait for terminal to load
  vim.loop.sleep(6 * small_time)
  child.cmd('startinsert')
  eq(child.fn.mode(), 't')

  type_keys(' ', 'f')
  eq(child.fn.mode(), 't')
  eq(get_test_map_count('t', ' f'), 1)
  eq(get_test_map_count('t', ' g'), 0)

  type_keys(' ', 'g')
  eq(child.fn.mode(), 't')
  eq(get_test_map_count('t', ' f'), 1)
  eq(get_test_map_count('t', ' g'), 1)
end

T['Reproducing keys']['works for builtin keymaps in Command-line mode'] = function()
  load_module({ triggers = { { mode = 'c', keys = '<C-r>' } } })
  validate_trigger_keymap('c', '<C-R>')

  set_lines({ 'aaa' })
  set_cursor(1, 0)
  type_keys(':', '<C-r>', '<C-w>')
  eq(child.fn.getcmdline(), 'aaa')
end

T['Reproducing keys']['works for user keymaps in Command-line mode'] = function()
  -- Should work for both keymap created before and after making trigger
  make_test_map('c', '<Space>f')
  load_module({ triggers = { { mode = 'c', keys = '<Space>' } } })
  make_test_map('c', '<Space>g')

  validate_trigger_keymap('c', '<Space>')

  type_keys(':')

  type_keys(' ', 'f')
  eq(child.fn.mode(), 'c')
  eq(get_test_map_count('c', ' f'), 1)
  eq(get_test_map_count('c', ' g'), 0)

  type_keys(' ', 'g')
  eq(child.fn.mode(), 'c')
  eq(get_test_map_count('c', ' f'), 1)
  eq(get_test_map_count('c', ' g'), 1)
end

T['Reproducing keys']['works for registers'] = function()
  load_module({ triggers = { { mode = 'n', keys = '"' }, { mode = 'x', keys = '"' } } })
  validate_trigger_keymap('n', '"')
  validate_trigger_keymap('x', '"')

  -- Normal mode
  set_lines({ 'aa' })
  set_cursor(1, 0)
  type_keys('"', 'a', 'yiw')
  eq(child.fn.getreg('"a'), 'aa')

  -- Visual mode
  set_lines({ 'bb' })
  set_cursor(1, 0)
  type_keys('viw', '"', 'b', 'y')
  eq(child.fn.getreg('"b'), 'bb')
end

T['Reproducing keys']['works for marks'] = function()
  load_module({ triggers = { { mode = 'n', keys = "'" }, { mode = 'n', keys = '`' } } })
  validate_trigger_keymap('n', "'")
  validate_trigger_keymap('n', '`')

  set_lines({ 'aa', 'bb' })
  set_cursor(1, 1)
  type_keys('ma')

  -- Line jump
  set_cursor(2, 0)
  type_keys("'", 'a')
  eq(get_cursor(), { 1, 0 })

  -- Exact jump
  set_cursor(2, 0)
  type_keys('`', 'a')
  eq(get_cursor(), { 1, 1 })
end

T['Reproducing keys']['works with macros'] = function()
  mock_comment_operators()
  load_module({ triggers = { { mode = 'n', keys = 'g' }, { mode = 'o', keys = 'i' }, { mode = 'i', keys = '<C-r>' } } })
  validate_trigger_keymap('n', 'g')
  validate_trigger_keymap('o', 'i')

  local init_buf_id = child.api.nvim_get_current_buf()
  local new_buf_id = child.api.nvim_create_buf(true, false)

  local setup = function()
    child.api.nvim_buf_set_lines(init_buf_id, 0, -1, false, { 'aa', 'bb' })
    child.api.nvim_buf_set_lines(new_buf_id, 0, -1, false, { 'cc', 'dd' })

    child.api.nvim_set_current_buf(init_buf_id)
    set_cursor(1, 0)
  end

  local validate = function()
    eq(child.api.nvim_buf_get_lines(init_buf_id, 0, -1, false), { '-- AA', '-- bb' })
    eq(child.api.nvim_buf_get_lines(new_buf_id, 0, -1, false), { '-- CC', '-- dd' })

    -- Make sure that triggers persist because they are temporarily disabled
    -- for the duration of macro execution
    validate_trigger_keymap('n', 'g')
    validate_trigger_keymap('o', 'i')
  end

  setup()

  type_keys('qq', 'g~', 'i', 'w', 'gc', 'i', 'p')
  type_keys(':bnext<CR>', 'g~', 'i', 'w', 'gc', 'i', 'p')
  type_keys('q')

  validate()

  eq(child.fn.getreg('q', 1, 1), { 'g~iwgcip:bnext\rg~iwgcip' })

  -- Should work reproducing multiple times with different keys
  setup()
  type_keys('@q')
  validate()

  setup()
  type_keys('@@')
  validate()

  setup()
  type_keys('Q')
  validate()

  -- Should not throw error if user aborted with `<C-c>`
  setup()
  type_keys('@', '<C-c>')
  child.api.nvim_buf_set_lines(init_buf_id, 0, -1, false, { 'aa', 'bb' })
  child.api.nvim_buf_set_lines(new_buf_id, 0, -1, false, { 'cc', 'dd' })
  validate_trigger_keymap('n', 'g')
  validate_trigger_keymap('o', 'i')

  -- Should work when creating new buffer inside macro (i.e. auto-creating
  -- triggers should not intefere)
  child.fn.setreg('a', 'word')
  type_keys('qw', ':enew<CR>', 'i', '<C-r>', 'a', '<Esc>', 'q')
  eq(child.fn.getreg('w'), ':enew\ri\18a\27')
end

T['Reproducing keys']["works with macros and 'mini.jump'"] = function()
  if child.fn.has('nvim-0.10') == 0 then MiniTest.skip('The solution works only on Neovim>=0.10') end
  child.lua("require('mini.jump').setup()")
  load_module()
  set_lines({ '  [aaa][bbb][ccc]' })

  type_keys(small_time, 'qq', '0f', '[', 'r(f', ']', 'r)', 'q')
  eq(get_lines(), { '  (aaa)[bbb][ccc]' })

  type_keys('Q')
  eq(get_lines(), { '  (aaa)(bbb)[ccc]' })

  type_keys('@q')
  eq(get_lines(), { '  (aaa)(bbb)(ccc)' })
end

T['Reproducing keys']['works when key query is executed in presence of longer keymaps'] = function()
  mock_comment_operators()
  load_module({ triggers = { { mode = 'n', keys = 'g' }, { mode = 'o', keys = 'i' } } })
  validate_trigger_keymap('n', 'g')
  validate_trigger_keymap('o', 'i')

  validate_edit({ 'aa', 'bb', '', 'cc' }, { 1, 0 }, { 'g', 'c', 'i', 'p' }, { '-- aa', '-- bb', '', 'cc' }, { 1, 0 })
end

T['Reproducing keys']['works with `<Cmd>` mappings'] = function()
  child.api.nvim_set_keymap('n', '<Space>f', '<Cmd>lua _G.been_here = true<CR>', {})
  load_module({ triggers = { { mode = 'n', keys = '<Space>' } } })

  type_keys(' ', 'f')
  eq(child.lua_get('_G.been_here'), true)
end

T['Reproducing keys']['works with buffer-local mappings'] = function()
  child.api.nvim_buf_set_keymap(0, 'n', '<Space>f', '<Cmd>lua _G.been_here = true<CR>', {})
  load_module({ triggers = { { mode = 'n', keys = '<Space>' } } })

  type_keys(' ', 'f')
  eq(child.lua_get('_G.been_here'), true)
end

T['Reproducing keys']['does not register new triggers'] = function()
  load_module({ triggers = { { mode = 'o', keys = 'i' } } })
  validate_trigger_keymap('o', 'i')

  set_lines('aaa')
  type_keys('"adiw')

  validate_trigger_keymap('o', 'i')
end

T['Reproducing keys']["respects 'clipboard'"] = function()
  -- Mock constant clipboard for better reproducibility of system registers
  -- (mostly on CI).
  child.lua([[
    local empty = function() return '' end
    vim.g.clipboard = {
      name  = 'myClipboard',
      copy  = { ['+'] = empty, ['*'] = empty },
      paste = { ['+'] = empty, ['*'] = empty },
    }
  ]])

  load_module({ triggers = { { mode = 'c', keys = 'g' }, { mode = 'i', keys = 'g' } } })
  validate_trigger_keymap('c', 'g')
  validate_trigger_keymap('i', 'g')

  local validate_clipboard = function(clipboard_value)
    child.ensure_normal_mode()
    set_lines({})

    child.o.clipboard = clipboard_value

    child.ensure_normal_mode()
    type_keys('i', 'g')
    eq(get_lines(), { 'g' })
  end

  validate_clipboard('unnamed')
  validate_clipboard('unnamedplus')
  validate_clipboard('unnamed,unnamedplus')
  validate_clipboard('unnamedplus,unnamed')
end

T['Reproducing keys']['works with <F*> keys'] = function()
  child.lua([[vim.g.mapleader = vim.api.nvim_replace_termcodes('<F2>', true, true, true)]])
  child.cmd('nnoremap <Leader>a <Cmd>lua _G.n = (_G.n or 0) + 1<CR>')
  child.cmd('nnoremap <F3>b <Cmd>lua _G.m = (_G.m or 0) + 1<CR>')

  load_module({
    clues = { { mode = 'n', keys = '<Leader>a', postkeys = '<Leader>' } },
    triggers = { { mode = 'n', keys = '<Leader>' }, { mode = 'n', keys = '<F3>' } },
  })

  type_keys('<F2>', 'a', 'a', '<Esc>')
  eq(child.lua_get('_G.n'), 2)

  type_keys('<F3>', 'b')
  eq(child.lua_get('_G.m'), 1)
end

T["'mini.nvim' compatibility"] = new_set()

T["'mini.nvim' compatibility"]['mini.ai'] = function()
  child.lua('require("mini.ai").setup()')

  load_module({ triggers = { { mode = 'o', keys = 'i' }, { mode = 'o', keys = 'a' } }, window = { delay = 0 } })
  validate_trigger_keymap('o', 'i')
  validate_trigger_keymap('o', 'a')

  -- `i` in Visual mode
  validate_selection1d('aa(bb)', 0, 'vi)', 3, 4)
  validate_selection1d('aa ff(bb)', 0, 'vif', 6, 7)

  validate_selection1d('(a(b(cc)b)a)', 5, 'v2i)', 3, 8)
  validate_selection1d('(a(b(cc)b)a)', 5, 'vi)i)', 3, 8)

  validate_selection1d('(aa) (bb) (cc)', 6, 'vil)', 1, 2)
  validate_selection1d('(aa) (bb) (cc)', 11, 'v2il)', 1, 2)

  validate_selection1d('(aa) (bb) (cc)', 6, 'vin)', 11, 12)
  validate_selection1d('(aa) (bb) (cc)', 1, 'v2in)', 11, 12)

  -- `a` in Visual mode
  validate_selection1d('aa(bb)', 0, 'va)', 2, 5)
  validate_selection1d('aa ff(bb)', 0, 'vaf', 3, 8)

  validate_selection1d('(a(b(cc)b)a)', 5, 'v2a)', 2, 9)
  validate_selection1d('(a(b(cc)b)a)', 5, 'va)a)', 2, 9)

  validate_selection1d('(aa) (bb) (cc)', 6, 'val)', 0, 3)
  validate_selection1d('(aa) (bb) (cc)', 11, 'v2al)', 0, 3)

  validate_selection1d('(aa) (bb) (cc)', 6, 'van)', 10, 13)
  validate_selection1d('(aa) (bb) (cc)', 1, 'v2an)', 10, 13)

  -- `i` in Operator-pending mode
  validate_edit1d('aa(bb)', 0, 'di)', 'aa()', 3)
  validate_edit1d('aa(bb)', 0, 'ci)cc', 'aa(cc)', 5)
  validate_edit1d('aa(bb)', 0, 'yi)P', 'aa(bbbb)', 4)
  validate_edit1d('aa ff(bb)', 0, 'dif', 'aa ff()', 6)

  validate_edit1d('(a(b(cc)b)a)', 5, 'd2i)', '(a()a)', 3)

  validate_edit1d('(a(b(cc)b)a)', 5, 'di).', '(a()a)', 3)
  validate_edit1d('(aa) (bb)', 1, 'ci)cc<Esc>W.', '(cc) (cc)', 7)

  validate_edit1d('(aa) (bb) (cc)', 6, 'dil)', '() (bb) (cc)', 1)
  validate_edit1d('(aa) (bb) (cc)', 11, 'd2il)', '() (bb) (cc)', 1)

  validate_edit1d('(aa) (bb) (cc)', 6, 'din)', '(aa) (bb) ()', 11)
  validate_edit1d('(aa) (bb) (cc)', 1, 'd2in)', '(aa) (bb) ()', 11)

  -- `a` in Operator-pending mode
  validate_edit1d('aa(bb)', 0, 'da)', 'aa', 1)
  validate_edit1d('aa(bb)', 0, 'ca)cc', 'aacc', 4)
  validate_edit1d('aa(bb)', 0, 'ya)P', 'aa(bb)(bb)', 5)
  validate_edit1d('aa ff(bb)', 0, 'daf', 'aa ', 2)

  validate_edit1d('(a(b(cc)b)a)', 5, 'd2a)', '(aa)', 2)

  validate_edit1d('(a(b(cc)b)a)', 5, 'da).', '(aa)', 2)
  validate_edit1d('(aa) (bb)', 1, 'ca)cc<Esc>W.', 'cc cc', 4)

  validate_edit1d('(aa) (bb) (cc)', 6, 'dal)', ' (bb) (cc)', 0)
  validate_edit1d('(aa) (bb) (cc)', 11, 'd2al)', ' (bb) (cc)', 0)

  validate_edit1d('(aa) (bb) (cc)', 6, 'dan)', '(aa) (bb) ', 9)
  validate_edit1d('(aa) (bb) (cc)', 1, 'd2an)', '(aa) (bb) ', 9)
end

T["'mini.nvim' compatibility"]['mini.align'] = function()
  child.set_size(10, 30)
  child.o.cmdheight = 5

  child.lua('require("mini.align").setup()')

  -- Works together with 'mini.ai' without `g` as trigger
  child.lua('require("mini.ai").setup()')
  load_module({ triggers = { { mode = 'o', keys = 'i' } } })
  validate_edit({ 'f(', 'a_b', 'aa_b', ')' }, { 2, 0 }, { 'ga', 'if', '_' }, { 'f(', 'a _b', 'aa_b', ')' }, { 1, 1 })

  -- Works with `g` as trigger
  load_module({ triggers = { { mode = 'n', keys = 'g' }, { mode = 'o', keys = 'i' } }, window = { delay = 0 } })
  validate_trigger_keymap('n', 'g')

  -- - No preview
  validate_edit({ 'a_b', 'aa_b' }, { 1, 0 }, 'vapga_', { 'a _b', 'aa_b' }, { 2, 0 })
  validate_edit({ 'a_b', 'aa_b' }, { 1, 0 }, 'gaap_', { 'a _b', 'aa_b' }, { 1, 0 })

  validate_edit(
    { 'a_b', 'aa_b', '', 'c_d', 'cc_d' },
    { 1, 0 },
    'gaap_G.',
    { 'a _b', 'aa_b', '', 'c _d', 'cc_d' },
    { 3, 0 }
  )

  -- - With preview
  local validate_preview = function(keys)
    set_lines({ 'a_b', 'aa_b' })
    set_cursor(1, 0)
    type_keys(keys)
    child.expect_screenshot({ redraw = false })
    type_keys('_<CR>')
    eq(get_lines(), { 'a _b', 'aa_b' })
  end

  validate_preview('vapgA')
  validate_preview('gAap')

  -- Works together with 'mini.ai' with `g` as trigger
  if has_ai then
    validate_edit({ 'f(', 'a_b', 'aa_b', ')' }, { 2, 0 }, { 'ga', 'if', '_' }, { 'f(', 'a _b', 'aa_b', ')' }, { 1, 1 })
  end
end

T["'mini.nvim' compatibility"]['mini.basics'] = function()
  child.lua('require("mini.basics").setup()')

  load_module({ triggers = { { mode = 'n', keys = 'g' } }, window = { delay = 0 } })
  validate_trigger_keymap('n', 'g')

  set_lines({ 'aa' })

  type_keys('g', 'O', '.')
  eq(get_lines(), { '', '', 'aa' })
  eq(get_cursor(), { 3, 0 })

  type_keys('g', 'o', '.')
  eq(get_lines(), { '', '', 'aa', '', '' })
  eq(get_cursor(), { 3, 0 })
end

T["'mini.nvim' compatibility"]['mini.bracketed'] = function()
  child.lua('require("mini.bracketed").setup()')

  load_module({
    triggers = {
      { mode = 'n', keys = '[' },
      { mode = 'x', keys = '[' },
      { mode = 'o', keys = '[' },
      { mode = 'n', keys = ']' },
      { mode = 'x', keys = ']' },
      { mode = 'o', keys = ']' },
    },
    window = { delay = 0 },
  })
  validate_trigger_keymap('n', '[')
  validate_trigger_keymap('x', '[')
  validate_trigger_keymap('o', '[')
  validate_trigger_keymap('n', ']')
  validate_trigger_keymap('x', ']')
  validate_trigger_keymap('o', ']')

  -- Normal mode
  -- - Not same buffer
  local get_buf = child.api.nvim_get_current_buf
  local init_buf_id = get_buf()
  local new_buf_id = child.api.nvim_create_buf(true, false)

  type_keys(']b')
  eq(get_buf(), new_buf_id)

  type_keys('[b')
  eq(get_buf(), init_buf_id)

  type_keys(']B')
  eq(get_buf(), new_buf_id)

  type_keys('[B')
  eq(get_buf(), init_buf_id)

  type_keys('2[b')
  eq(get_buf(), init_buf_id)

  -- - Same buffer
  local indent_lines = { 'aa', '\tbb', '\t\tcc', '\tdd', 'ee' }
  validate_move(indent_lines, { 3, 2 }, '[i', { 2, 1 })
  validate_move(indent_lines, { 3, 2 }, ']i', { 4, 1 })
  validate_move(indent_lines, { 3, 2 }, '2[i', { 1, 0 })

  -- Visual mode
  validate_selection(indent_lines, { 3, 2 }, 'v[i', { 2, 1 }, { 3, 2 })
  validate_selection(indent_lines, { 3, 2 }, 'v]i', { 3, 2 }, { 4, 1 })
  validate_selection(indent_lines, { 3, 2 }, 'v2[i', { 1, 0 }, { 3, 2 })

  validate_selection(indent_lines, { 3, 2 }, 'V[i', { 2, 1 }, { 3, 2 }, 'V')

  -- Operator-pending mode
  validate_edit(indent_lines, { 3, 2 }, 'd[i', { 'aa', '\tdd', 'ee' }, { 2, 2 })
  validate_edit(indent_lines, { 3, 2 }, 'd]i', { 'aa', '\tbb', 'ee' }, { 3, 1 })
  validate_edit(indent_lines, { 3, 2 }, 'd2[i', { '\tdd', 'ee' }, { 1, 2 })
end

T["'mini.nvim' compatibility"]['mini.comment'] = function()
  child.o.commentstring = '## %s'

  child.lua('require("mini.comment").setup()')

  -- Works together with 'mini.ai' without `g` as trigger
  child.lua('require("mini.ai").setup()')
  load_module({ triggers = { { mode = 'o', keys = 'i' } }, window = { delay = 0 } })
  validate_edit({ 'aa', 'bb', '', 'cc' }, { 1, 0 }, { 'gc', 'ip' }, { '## aa', '## bb', '', 'cc' }, { 1, 0 })

  -- Works with `g` as trigger
  load_module({
    triggers = {
      { mode = 'n', keys = 'g' },
      { mode = 'x', keys = 'g' },
      { mode = 'o', keys = 'g' },

      { mode = 'o', keys = 'i' },
    },
    window = { delay = 0 },
  })
  validate_trigger_keymap('n', 'g')

  -- Normal mode
  validate_edit({ 'aa', 'bb', '', 'cc' }, { 1, 0 }, { 'gc', 'ap' }, { '## aa', '## bb', '##', 'cc' }, { 1, 0 })
  validate_edit(
    { 'aa', '', 'bb', '', 'cc' },
    { 1, 0 },
    { '2gc', 'ap' },
    { '## aa', '##', '## bb', '##', 'cc' },
    { 1, 0 }
  )
  validate_edit(
    { 'aa', '', 'bb', '', 'cc' },
    { 1, 0 },
    { 'gc', 'ap', '.' },
    { '## ## aa', '## ##', '## bb', '##', 'cc' },
    { 1, 0 }
  )

  validate_edit({ 'aa', 'bb', '' }, { 1, 0 }, { 'gcc' }, { '## aa', 'bb', '' }, { 1, 0 })
  validate_edit({ 'aa', 'bb', '' }, { 1, 0 }, { '2gcc' }, { '## aa', '## bb', '' }, { 1, 0 })
  validate_edit({ 'aa', 'bb', '' }, { 1, 0 }, { 'gcc', 'j', '.' }, { '## aa', '## bb', '' }, { 2, 0 })

  -- Visual mode
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'V', 'gc' }, { '## aa', 'bb' }, { 1, 0 })

  -- Operator-pending mode
  validate_edit({ '## aa', 'bb' }, { 1, 0 }, { 'dgc' }, { 'bb' }, { 1, 0 })
  validate_edit({ '## aa', 'bb', '## cc' }, { 1, 0 }, { 'dgc', 'j', '.' }, { 'bb' }, { 1, 0 })

  -- Works together with 'mini.ai' when `g` is trigger
  if has_ai then
    validate_edit({ 'aa', 'bb', '', 'cc' }, { 1, 0 }, { 'gc', 'ip' }, { '## aa', '## bb', '', 'cc' }, { 1, 0 })
  end
end

T["'mini.nvim' compatibility"]['mini.indentscope'] = function()
  child.lua('require("mini.indentscope").setup()')

  load_module({
    triggers = {
      { mode = 'n', keys = '[' },
      { mode = 'n', keys = ']' },

      { mode = 'x', keys = '[' },
      { mode = 'x', keys = ']' },
      { mode = 'x', keys = 'a' },
      { mode = 'x', keys = 'i' },

      { mode = 'o', keys = '[' },
      { mode = 'o', keys = ']' },
      { mode = 'o', keys = 'a' },
      { mode = 'o', keys = 'i' },
    },
    window = { delay = 0 },
  })
  validate_trigger_keymap('n', '[')
  validate_trigger_keymap('n', ']')
  validate_trigger_keymap('x', '[')
  validate_trigger_keymap('x', ']')
  validate_trigger_keymap('x', 'a')
  validate_trigger_keymap('x', 'i')
  validate_trigger_keymap('o', '[')
  validate_trigger_keymap('o', ']')
  validate_trigger_keymap('o', 'a')
  validate_trigger_keymap('o', 'i')

  local lines = { 'aa', '\tbb', '\t\tcc', '\tdd', 'ee' }
  local cursor = { 3, 2 }

  -- Normal mode
  validate_move(lines, cursor, '[i', { 2, 1 })
  validate_move(lines, cursor, '2[i', { 1, 0 })

  validate_move(lines, cursor, ']i', { 4, 1 })
  validate_move(lines, cursor, '2]i', { 5, 0 })

  -- Visual mode
  validate_selection(lines, cursor, 'v[i', { 2, 1 }, { 3, 2 })
  validate_selection(lines, cursor, 'v2[i', { 1, 0 }, { 3, 2 })

  validate_selection(lines, cursor, 'v]i', { 3, 2 }, { 4, 1 })
  validate_selection(lines, cursor, 'v2]i', { 3, 2 }, { 5, 0 })

  validate_selection(lines, cursor, 'vai', { 2, 1 }, { 4, 1 }, 'V')
  validate_selection(lines, cursor, 'v2ai', { 1, 0 }, { 5, 0 }, 'V')

  validate_selection(lines, cursor, 'vii', { 3, 2 }, { 3, 2 }, 'V')
  validate_selection(lines, cursor, 'v2ii', { 3, 2 }, { 3, 2 }, 'V')

  -- Operator-pending mode
  validate_edit(lines, cursor, 'd[i', { 'aa', '\tcc', '\tdd', 'ee' }, { 2, 1 })
  validate_edit(lines, cursor, 'd2[i', { 'cc', '\tdd', 'ee' }, { 1, 0 })
  validate_edit(lines, cursor, 'd[i.', { 'cc', '\tdd', 'ee' }, { 1, 0 })

  validate_edit(lines, cursor, 'd]i', { 'aa', '\tbb', '\t\tdd', 'ee' }, { 3, 2 })
  validate_edit(lines, cursor, 'd2]i', { 'aa', '\tbb', 'ee' }, { 3, 0 })
  validate_edit(lines, cursor, 'd]i.', { 'aa', '\tbb', 'ee' }, { 3, 0 })

  validate_edit(lines, cursor, 'dai', { 'aa', 'ee' }, { 2, 1 })
  validate_edit(lines, cursor, 'd2ai', { '' }, { 1, 0 })
  validate_edit(lines, cursor, 'dai.', { 'aa', 'ee' }, { 2, 1 })

  validate_edit(lines, cursor, 'dii', { 'aa', '\tbb', '\tdd', 'ee' }, { 3, 2 })
  validate_edit(lines, cursor, 'd2ii', { 'aa', '\tbb', '\tdd', 'ee' }, { 3, 2 })
  validate_edit(lines, cursor, 'dii.', { 'aa', 'ee' }, { 2, 1 })
end

T["'mini.nvim' compatibility"]['mini.surround'] = function()
  -- `saiw` works as expected when `s` and `i` are triggers: doesn't move cursor, no messages.

  child.lua('require("mini.surround").setup()')

  -- Works together with 'mini.ai' without `s` as trigger
  child.lua('require("mini.ai").setup()')
  load_module({ triggers = { { mode = 'o', keys = 'i' } }, window = { delay = 0 } })
  validate_edit1d('aa bb', 0, { 'sa', 'iw', ')' }, '(aa) bb', 1)
  validate_edit1d('aa ff(bb)', 0, { 'sa', 'if', ']' }, 'aa ff([bb])', 7)

  -- Works with `s` as trigger
  load_module({ triggers = { { mode = 'n', keys = 's' }, { mode = 'o', keys = 'i' } }, window = { delay = 0 } })
  validate_trigger_keymap('n', 's')
  validate_trigger_keymap('o', 'i')

  -- Add
  validate_edit1d('aa bb', 0, { 'sa', 'iw', ')' }, '(aa) bb', 1)
  validate_edit1d('aa bb', 0, { '2sa', 'iw', ')' }, '((aa)) bb', 2)
  validate_edit1d('aa bb', 0, { 'sa', '3iw', ')' }, '(aa bb)', 1)
  validate_edit1d('aa bb', 0, { '2sa', '3iw', ')' }, '((aa bb))', 2)

  validate_edit1d('aa bb', 0, { 'viw', 'sa', ')' }, '(aa) bb', 1)
  validate_edit1d('aa bb', 0, { 'viw', '2sa', ')' }, '((aa)) bb', 2)

  validate_edit1d('aa bb', 0, { 'sa', 'iw', ')', 'W', '.' }, '(aa) (bb)', 6)

  -- Delete
  validate_edit1d('(a(b(cc)b)a)', 5, 'sd)', '(a(bccb)a)', 4)
  validate_edit1d('(a(b(cc)b)a)', 5, '2sd)', '(ab(cc)ba)', 2)

  validate_edit1d('(a(b(cc)b)a)', 5, 'sd).', '(abccba)', 2)

  validate_edit1d('(aa) (bb) (cc)', 6, 'sdl)', 'aa (bb) (cc)', 0)
  validate_edit1d('(aa) (bb) (cc)', 11, '2sdl)', 'aa (bb) (cc)', 0)

  validate_edit1d('(aa) (bb) (cc)', 6, 'sdn)', '(aa) (bb) cc', 10)
  validate_edit1d('(aa) (bb) (cc)', 1, '2sdn)', '(aa) (bb) cc', 10)

  -- Replace
  validate_edit1d('(a(b(cc)b)a)', 5, 'sr)>', '(a(b<cc>b)a)', 5)
  validate_edit1d('(a(b(cc)b)a)', 5, '2sr)>', '(a<b(cc)b>a)', 3)

  validate_edit1d('(a(b(cc)b)a)', 5, 'sr)>.', '(a<b<cc>b>a)', 3)

  validate_edit1d('(aa) (bb) (cc)', 6, 'srl)>', '<aa> (bb) (cc)', 1)
  validate_edit1d('(aa) (bb) (cc)', 11, '2srl)>', '<aa> (bb) (cc)', 1)

  validate_edit1d('(aa) (bb) (cc)', 6, 'srn)>', '(aa) (bb) <cc>', 11)
  validate_edit1d('(aa) (bb) (cc)', 1, '2srn)>', '(aa) (bb) <cc>', 11)
end

return T
