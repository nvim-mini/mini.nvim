local helpers = dofile('tests/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq, no_eq = helpers.expect, helpers.expect.equality, helpers.expect.no_equality
local new_set = MiniTest.new_set

-- Helpers with child processes
local load_module = function(config) child.mini_load('keymap', config) end
local unload_module = function() child.mini_unload('keymap') end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
local sleep = function(ms) helpers.sleep(ms, child) end

local test_dir = 'tests/dir-keymap'

-- Common test wrappers
local forward_lua = function(fun_str)
  local lua_cmd = fun_str .. '(...)'
  return function(...) return child.lua_get(lua_cmd, { ... }) end
end

local mock_plugin = function(name) child.cmd('noautocmd set rtp+=tests/dir-keymap/mock-plugins/' .. name) end

local mock_test_steps = function(method_name)
  child.lua([[
    -- Action returns nothing
    _G.step_1 = {
      condition = function() table.insert(_G.log, 'cond 1'); return _G.step_1_cond end,
      action = function() table.insert(_G.log, 'action 1') end,
    }

    -- Action returns string keys to be emulated as if typed
    _G.step_2 = {
      condition = function() table.insert(_G.log, 'cond 2'); return _G.step_2_cond end,
      action = function() table.insert(_G.log, 'action 2'); return 'dd' end,
    }

    -- Action returns `<Cmd>...<CR>` string to be executed
    _G.step_3 = {
      condition = function() table.insert(_G.log, 'cond 3'); return _G.step_3_cond end,
      action = function()
        table.insert(_G.log, 'action 3')
        return '<Cmd>lua vim.api.nvim_buf_set_lines(0, 0, -1, false, { "From step 3" })<CR>'
      end,
    }

    -- Action returns `false` to indicate "keep processing next steps"
    _G.step_4 = {
      condition = function() table.insert(_G.log, 'cond 4'); return _G.step_4_cond end,
      action = function() table.insert(_G.log, 'action 4'); return false end,
    }

    -- Action returns callable to be executed later
    _G.step_5 = {
      condition = function() table.insert(_G.log, 'cond 5'); return _G.step_5_cond end,
      action = function()
        table.insert(_G.log, 'action 5')
        local upvalue = 'From step 5 with upvalue'
        return function() vim.api.nvim_buf_set_lines(0, 0, -1, false, { upvalue }) end
      end,
    }

    _G.steps = { _G.step_1, _G.step_2, _G.step_3, _G.step_4, _G.step_5 }
  ]])
end

local validate_log_and_clean = function(ref)
  eq(child.lua_get('_G.log'), ref)
  child.lua('_G.log = {}')
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

local validate_jumps = function(key, ref_pos_seq)
  -- Should keep initial mode (relevant for Insert mode)
  local start_mode = child.fn.mode()
  for _, ref_pos in ipairs(ref_pos_seq) do
    type_keys(key)
    eq(get_cursor(), ref_pos)
    eq(child.fn.mode(), start_mode)
  end
  child.ensure_normal_mode()
end

local is_pumvisible = function() return child.fn.pumvisible() == 1 end

-- Time constants
local small_time = helpers.get_time_const(10)
local term_mode_wait = helpers.get_time_const(50)
-- - Use custom combo delay for more robust tests on slower systems
local default_combo_delay = 200
local test_combo_delay = 3 * small_time

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      child.lua('_G.log = {}')
    end,
    post_once = child.stop,
    n_retry = helpers.get_n_retry(2),
  },
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  load_module()
  -- Global variable
  eq(child.lua_get('type(_G.MiniKeymap)'), 'table')
end

T['setup()']['creates `config` field'] = function()
  load_module()
  eq(child.lua_get('type(_G.MiniKeymap.config)'), 'table')
end

T['setup()']['validates `config` argument'] = function()
  local expect_config_error = function(config, name, target_type)
    expect.error(function() load_module(config) end, vim.pesc(name) .. '.*' .. vim.pesc(target_type))
  end

  expect_config_error('a', 'config', 'table')
end

T['map_multistep()'] = new_set()

local map_multistep = forward_lua('require("mini.keymap").map_multistep')

T['map_multistep()']['works'] = function()
  mock_test_steps()
  child.lua('require("mini.keymap").map_multistep("i", "<Tab>", _G.steps)')

  type_keys('i')

  -- Can pass through
  type_keys('<Tab>')
  validate_log_and_clean({ 'cond 1', 'cond 2', 'cond 3', 'cond 4', 'cond 5' })
  -- - Act as if unmapped
  eq(get_lines(), { '\t' })

  -- Can handle an action returning nothing
  child.lua('_G.step_1_cond = true')
  type_keys('<Tab>')
  validate_log_and_clean({ 'cond 1', 'action 1' })
  -- - Do nothing
  eq(get_lines(), { '\t' })
  child.lua('_G.step_1_cond = false')

  -- Can emulate returned keys
  child.lua('_G.step_2_cond = true')
  type_keys('<Tab>')
  validate_log_and_clean({ 'cond 1', 'cond 2', 'action 2' })
  -- - Emulate pressing returned keys
  eq(get_lines(), { '\tdd' })
  child.lua('_G.step_2_cond = false')

  -- Can execute `<Cmd>...<CR>` string
  child.lua('_G.step_3_cond = true')
  type_keys('<Tab>')
  validate_log_and_clean({ 'cond 1', 'cond 2', 'cond 3', 'action 3' })
  -- - Execute `<Cmd>...<CR>` string
  eq(get_lines(), { 'From step 3' })
  child.lua('_G.step_3_cond = false')

  -- Respects action returning `false` to indicate processing further steps
  child.lua('_G.step_4_cond = true')
  set_cursor(1, 11)
  type_keys('<Tab>')
  validate_log_and_clean({ 'cond 1', 'cond 2', 'cond 3', 'cond 4', 'action 4', 'cond 5' })
  -- - Respect `false` action return as "pass through"
  eq(get_lines(), { 'From step 3\t' })
  child.lua('_G.step_4_cond = false')

  -- Can execute callable returned from action
  child.lua('_G.step_5_cond = true')
  type_keys('<Tab>')
  validate_log_and_clean({ 'cond 1', 'cond 2', 'cond 3', 'cond 4', 'cond 5', 'action 5' })
  -- - Execute callable returned from action
  eq(get_lines(), { 'From step 5 with upvalue' })
  child.lua('_G.step_5_cond = false')
  -- - Should not create side effects
  eq(child.lua_get('type(_G.MiniKeymap)'), 'nil')
end

T['map_multistep()']['works with empty steps'] = function()
  map_multistep('i', '<Tab>', {})
  type_keys('i', '<Tab>')
  eq(get_lines(), { '\t' })
end

T['map_multistep()']['respects `opts`'] = function()
  local validate_mapping = function(is_buffer_local, ref_desc)
    local info = child.lua([[
      local map_info = vim.fn.maparg('<Tab>', 'i', false, true)
      return { is_buffer_local = map_info.buffer == 1, desc = map_info.desc }
    ]])
    eq(info, { is_buffer_local = is_buffer_local, desc = ref_desc })
  end

  mock_test_steps()

  child.lua('require("mini.keymap").map_multistep("i", "<Tab>", { _G.step_3 })')
  validate_mapping(false, 'Multi <Tab>')

  -- Should create a separate buffer-local mapping with custom description
  child.lua([[require('mini.keymap').map_multistep(
    'i',
    '<Tab>',
    { _G.step_5 },
    { buffer = 0, desc = 'My multi', expr = false, replace_keycodes = false }
  )]])
  validate_mapping(true, 'My multi')

  -- Should be independent and actually use only buffer-local mapping
  child.lua('_G.step_3_cond, _G.step_5_cond = true, true')
  type_keys('i', '<Tab>')
  eq(get_lines(), { 'From step 5 with upvalue' })
  eq(child.lua_get('_G.log'), { 'cond 5', 'action 5' })
  child.lua('_G.log = {}')

  child.cmd('iunmap <buffer> <Tab>')
  type_keys('<Tab>')
  eq(get_lines(), { 'From step 3' })
  eq(child.lua_get('_G.log'), { 'cond 3', 'action 3' })
end

T['map_multistep()']['respects `vim.{g,b}.minikeymap_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    mock_test_steps()
    child.lua('require("mini.keymap").map_multistep("i", "<Tab>", _G.steps)')
    type_keys('i')

    child[var_type].minikeymap_disable = true
    type_keys('<Tab>')
    eq(get_lines(), { '\t' })
    validate_log_and_clean({})

    child[var_type].minikeymap_disable = false
    type_keys('<Tab>')
    eq(get_lines(), { '\t\t' })
    validate_log_and_clean({ 'cond 1', 'cond 2', 'cond 3', 'cond 4', 'cond 5' })
  end,
})

T['map_multistep()']['validates input'] = function()
  expect.error(function() map_multistep('a', '<Tab>', {}) end, 'mode')
  expect.error(function() map_multistep('i', 1, {}) end, '`lhs`.*string')
  expect.error(function() map_multistep('i', '<Tab>', { 'a' }) end, '`steps`.*valid steps.*not')
  expect.error(function() map_multistep('i', '<Tab>', { {} }) end, '`steps`.*valid steps.*not')
  expect.error(function() map_multistep('i', '<Tab>', { { condition = 'a' } }) end, '`steps`.*valid steps.*not')
  local lua_cmd = 'require("mini.keymap").map_multistep("i", "<Tab>", { { condition = function() end, action = "a" } })'
  expect.error(function() child.lua(lua_cmd) end, '`steps`.*valid steps.*not')
end

T['map_multistep()']['built-in steps'] = new_set()

T['map_multistep()']['built-in steps']['pmenu_next'] = function()
  child.o.completeopt = 'menuone,noselect'
  map_multistep('i', '<Tab>', { 'pmenu_next' })

  type_keys('i', '<Tab>')
  eq(get_lines(), { '\t' })
  type_keys('aa ab ', '<C-n>')
  eq(is_pumvisible(), true)

  -- Should act as pressing `<C-n>`
  type_keys('<Tab>')
  eq(is_pumvisible(), true)
  eq(get_lines(), { '\taa ab aa' })

  type_keys('<C-e>')
  eq(is_pumvisible(), false)
  eq(get_lines(), { '\taa ab ' })
  type_keys('<Tab>')
  eq(get_lines(), { '\taa ab \t' })
end

T['map_multistep()']['built-in steps']['pmenu_prev'] = function()
  child.o.completeopt = 'menuone,noselect'
  map_multistep('i', '<S-Tab>', { 'pmenu_prev' })

  type_keys('i', '<S-Tab>')
  eq(get_lines(), { '\t' })
  type_keys('aa ab ', '<C-n>')
  eq(is_pumvisible(), true)

  -- Should act as pressing `<C-p>`
  type_keys('<S-Tab>')
  eq(is_pumvisible(), true)
  eq(get_lines(), { '\taa ab ab' })

  type_keys('<C-e>')
  eq(is_pumvisible(), false)
  eq(get_lines(), { '\taa ab ' })
  type_keys('<S-Tab>')
  eq(get_lines(), { '\taa ab \t' })
end

T['map_multistep()']['built-in steps']['pmenu_accept'] = function()
  child.o.completeopt = 'menuone,noselect'
  map_multistep('i', '<CR>', { 'pmenu_accept' })

  type_keys('i', '<CR>')
  eq(get_lines(), { '', '' })

  -- Should accept selected (and only selected) item, i.e. act like `<C-y>`
  type_keys('aa ab ', '<C-n>', '<C-n>')
  eq(is_pumvisible(), true)
  eq(get_lines(), { '', 'aa ab aa' })

  type_keys('<CR>')
  eq(is_pumvisible(), false)
  eq(get_lines(), { '', 'aa ab aa' })
end

T['map_multistep()']['built-in steps']['minisnippets_next'] = function()
  map_multistep('i', '<Tab>', { 'minisnippets_next' })

  -- Should work if 'mini.snippets' is not set up
  type_keys('i', '<Tab>')
  eq(get_lines(), { '\t' })

  child.lua('require("mini.snippets").setup()')

  -- Should pass through if there is no active session
  type_keys('<Tab>')
  eq(get_lines(), { '\t\t' })

  child.lua('MiniSnippets.default_insert({ prefix = "ab", body = "Snippet $1 ${2:placeholder} ab$0" })')
  eq(get_lines(), { '\t\tSnippet  placeholder ab' })
  eq(get_cursor(), { 1, 10 })

  type_keys('<Tab>')
  eq(get_lines(), { '\t\tSnippet  placeholder ab' })
  eq(get_cursor(), { 1, 11 })
  type_keys('<Tab>')
  eq(get_lines(), { '\t\tSnippet  placeholder ab' })
  eq(get_cursor(), { 1, 25 })
end

T['map_multistep()']['built-in steps']['minisnippets_prev'] = function()
  -- child.lua([[require("mini.snippets").setup({
  --   snippets = { { prefix = 'ab', body = 'Snippet $1 ab$0', desc = 'Test snippet' } },
  -- })]])
  map_multistep('i', '<S-Tab>', { 'minisnippets_prev' })

  -- Should work if 'mini.snippets' is not set up
  type_keys('i', '<S-Tab>')
  eq(get_lines(), { '\t' })

  child.lua('require("mini.snippets").setup()')

  -- Should pass through if there is no active session
  type_keys('<S-Tab>')
  eq(get_lines(), { '\t\t' })

  child.lua('MiniSnippets.default_insert({ prefix = "ab", body = "Snippet $1 ${2:placeholder} ab$0" })')
  eq(get_lines(), { '\t\tSnippet  placeholder ab' })
  eq(get_cursor(), { 1, 10 })

  type_keys('<S-Tab>')
  eq(get_lines(), { '\t\tSnippet  placeholder ab' })
  eq(get_cursor(), { 1, 25 })
  type_keys('<S-Tab>')
  eq(get_lines(), { '\t\tSnippet  placeholder ab' })
  eq(get_cursor(), { 1, 11 })
end

T['map_multistep()']['built-in steps']['minisnippets_expand'] = function()
  map_multistep('i', '<Tab>', { 'minisnippets_next', 'minisnippets_expand' })

  -- Should work if 'mini.snippets' is not set up
  type_keys('i', '<Tab>')
  eq(get_lines(), { '\t' })

  child.lua(
    'require("mini.snippets").setup({ snippets = { { prefix = "ab", body = "Snippet $1 ${2:placeholder} ab$0" } } })'
  )

  -- Should expand if no active session
  type_keys('ab', '<Tab>')
  eq(get_lines(), { '\tSnippet  placeholder ab' })
  eq(get_cursor(), { 1, 9 })

  -- Should jump if there is active session
  type_keys('<Tab>')
  eq(get_lines(), { '\tSnippet  placeholder ab' })
  eq(get_cursor(), { 1, 10 })
  type_keys('<Tab>')
  eq(get_lines(), { '\tSnippet  placeholder ab' })
  eq(get_cursor(), { 1, 24 })
end

T['map_multistep()']['built-in steps']['minipairs_cr'] = function()
  map_multistep('i', '<CR>', { 'minipairs_cr' })

  -- Should work if 'mini.pairs' is not set up
  type_keys('i', '<CR>')
  eq(get_lines(), { '', '' })

  child.lua('require("mini.pairs").setup()')

  -- Should respect pairs
  type_keys('(')
  eq(get_lines(), { '', '()' })
  type_keys('<CR>')
  eq(get_lines(), { '', '(', '', ')' })
end

T['map_multistep()']['built-in steps']['minipairs_bs'] = function()
  map_multistep('i', '<BS>', { 'minipairs_bs' })

  -- Should work if 'mini.pairs' is not set up
  type_keys('i', '()', '<Left>', '<BS>')
  eq(get_lines(), { ')' })

  child.lua('require("mini.pairs").setup()')

  -- Should respect pairs
  set_lines({ 'a()' })
  set_cursor(1, 2)
  eq(get_lines(), { 'a()' })
  type_keys('<BS>')
  eq(get_lines(), { 'a' })
end

T['map_multistep()']['built-in steps']['jump_after_tsnode'] = function()
  map_multistep({ 'i', 'n', 'x' }, '<Tab>', { 'jump_after_tsnode' })

  -- Should work if there is no tree-sitter parser
  type_keys('i', '<Tab>')
  eq(get_lines(), { '\t' })
  child.ensure_normal_mode()

  child.cmd('edit ' .. test_dir .. '/tree-sitter-tests.lua')

  -- Insert mode
  type_keys('i')
  set_cursor(3, 4)
  validate_jumps('<Tab>', {
    -- Should jump just after the end of current node
    { 3, 6 },
    -- Should be possible to "chain" jumps and place cursor after end of line
    { 5, 3 },
    { 6, 3 },
    { 8, 16 },
    -- Should be possible to call at end of buffer without movement
    { 8, 16 },
  })

  -- Normal mode
  set_cursor(3, 4)
  validate_jumps('<Tab>', {
    { 3, 6 },
    -- Should be possible to chain, although not possible to place after EOL
    { 5, 2 },
    { 6, 2 },
    { 8, 15 },
    -- Should be possible to call at end of buffer without movement
    { 8, 15 },
  })

  -- - Should place after line end if possible
  child.o.virtualedit = 'onemore'
  set_cursor(3, 4)
  validate_jumps('<Tab>', { { 3, 6 }, { 5, 3 }, { 6, 3 }, { 8, 16 }, { 8, 16 } })
  child.o.virtualedit = ''

  -- Visual mode
  set_cursor(3, 4)
  type_keys('v')
  validate_jumps('<Tab>', { { 3, 6 }, { 5, 3 }, { 6, 3 }, { 8, 16 }, { 8, 16 } })

  set_cursor(3, 4)
  type_keys('V')
  validate_jumps('<Tab>', { { 3, 6 }, { 5, 3 }, { 6, 3 }, { 8, 16 }, { 8, 16 } })

  set_cursor(3, 4)
  type_keys('<C-v>')
  validate_jumps('<Tab>', { { 3, 6 }, { 5, 3 }, { 6, 3 }, { 8, 16 }, { 8, 16 } })

  -- Should hide possibly visible popup menu
  set_cursor(3, 4)
  type_keys('i', '<C-n>')
  eq(is_pumvisible(), true)
  type_keys('<Tab>')
  eq(is_pumvisible(), false)
end

T['map_multistep()']['built-in steps']['jump_before_tsnode'] = function()
  map_multistep({ 'i', 'n', 'x' }, '<S-Tab>', { 'jump_before_tsnode' })

  -- Should work if there is no tree-sitter parser
  type_keys('i', '<S-Tab>')
  eq(get_lines(), { '\t' })
  child.ensure_normal_mode()

  child.cmd('edit ' .. test_dir .. '/tree-sitter-tests.lua')

  -- Insert mode
  type_keys('i')
  set_cursor(3, 5)
  validate_jumps('<S-Tab>', {
    -- Should jump just at the start of current node (as in Insert mode cursor
    -- will be just before the node) while keeping Insert mode
    { 3, 4 },
    -- Should be possible to "chain" jumps (although cursor is in the same node)
    { 2, 9 },
    { 2, 2 },
    { 1, 0 },
    -- Should be possible to call at end of buffer without movement
    { 1, 0 },
  })

  -- Normal mode
  set_cursor(3, 5)
  validate_jumps('<S-Tab>', { { 3, 4 }, { 2, 9 }, { 2, 2 }, { 1, 0 }, { 1, 0 } })

  -- Visual mode
  set_cursor(3, 5)
  type_keys('v')
  validate_jumps('<S-Tab>', { { 3, 4 }, { 2, 9 }, { 2, 2 }, { 1, 0 }, { 1, 0 } })

  set_cursor(3, 5)
  type_keys('V')
  validate_jumps('<S-Tab>', { { 3, 4 }, { 2, 9 }, { 2, 2 }, { 1, 0 }, { 1, 0 } })

  set_cursor(3, 5)
  type_keys('<C-v>')
  validate_jumps('<S-Tab>', { { 3, 4 }, { 2, 9 }, { 2, 2 }, { 1, 0 }, { 1, 0 } })

  -- Should hide possibly visible popup menu
  set_cursor(3, 4)
  type_keys('i', '<C-n>')
  eq(is_pumvisible(), true)
  type_keys('<S-Tab>')
  eq(is_pumvisible(), false)
end

T['map_multistep()']['built-in steps']['jump_after_close'] = function()
  map_multistep('i', '<Tab>', { 'jump_after_close' })

  set_lines({ [=[([{"'` x `'"}])]=], '', ')', ']', '}', '"', "'", '`' })
  set_cursor(1, 7)
  type_keys('i')

  validate_jumps('<Tab>', {
    -- Should put cursor on the right of closing character
    { 1, 10 },

    -- Should be able to "chain" to work with consecutive characters
    { 1, 11 },
    { 1, 12 },
    { 1, 13 },
    { 1, 14 },
    -- - Should be possible to put cursor after end of line
    { 1, 15 },

    -- Should work across multiple lines and with not necessarily balanced pairs
    { 3, 1 },
    { 4, 1 },
    { 5, 1 },
    { 6, 1 },
    { 7, 1 },
    { 8, 1 },

    -- Should do nothing if there is no search matches
    { 8, 1 },
  })
  eq(get_lines()[8], '`')

  -- Does not adjust cursor when not needed
  set_lines({ 'x)xxx' })
  set_cursor(1, 0)
  type_keys('i')
  validate_jumps('<Tab>', { { 1, 2 }, { 1, 2 } })

  -- Should hide possibly visible popup menu
  set_lines({ 'xx ( yy )' })
  set_cursor(1, 5)
  type_keys('i', '<C-n>')
  eq(is_pumvisible(), true)
  type_keys('<Tab>')
  eq(is_pumvisible(), false)
end

T['map_multistep()']['built-in steps']['jump_before_open'] = function()
  map_multistep('i', '<S-Tab>', { 'jump_before_open' })

  set_lines({ '`', "'", '"', '{', '[', '(', '', [=[([{"'` x `'"}])]=] })
  set_cursor(8, 7)
  type_keys('i')

  validate_jumps('<S-Tab>', {
    -- Should put cursor on the left of closing character
    { 8, 5 },

    -- Should be able to "chain" to work with consecutive characters
    { 8, 4 },
    { 8, 3 },
    { 8, 2 },
    { 8, 1 },
    -- - Should be possible to put cursor at first column
    { 8, 0 },

    -- Should work across multiple lines and with not necessarily balanced pairs
    { 6, 0 },
    { 5, 0 },
    { 4, 0 },
    { 3, 0 },
    { 2, 0 },
    { 1, 0 },

    -- Should do nothing if there is no search matches
    { 1, 0 },
  })
  eq(get_lines()[1], '`')

  -- Does not adjust cursor when not needed
  set_lines({ 'xxx(x' })
  set_cursor(1, 4)
  type_keys('i')
  validate_jumps('<S-Tab>', { { 1, 3 }, { 1, 3 } })

  -- Should hide possibly visible popup menu
  set_lines({ 'xx ( yy )' })
  set_cursor(1, 5)
  type_keys('i', '<C-n>')
  eq(is_pumvisible(), true)
  type_keys('<S-Tab>')
  eq(is_pumvisible(), false)
end

T['map_multistep()']['built-in steps']['increase_indent'] = function()
  map_multistep({ 'n', 'i', 'x' }, '<Tab>', { 'increase_indent' })

  -- Should work as with built-in keys, i.e. respecting relevant options
  child.bo.expandtab = true
  child.bo.shiftwidth = 2
  child.bo.tabstop = 4

  --  Should only work when inside indent (even empty)
  -- - Insert mode (cursor can be "just after indent", i.e. on next cell)
  validate_edit1d('abc', 0, 'i<Tab>', '  abc', 2)
  validate_edit1d('abc', 1, 'i<Tab>', 'a   bc', 4)
  validate_edit1d('  abc', 0, 'i<Tab>', '    abc', 2)
  validate_edit1d('  abc', 2, 'i<Tab>', '    abc', 4)
  validate_edit1d('  abc', 3, 'i<Tab>', '  a bc', 4)

  -- - Normal mode (cursor should be exactly on indent)
  validate_edit1d('abc', 0, '<Tab>', 'abc', 0)
  validate_edit1d('abc', 1, '<Tab>', 'abc', 1)
  validate_edit1d('  abc', 0, '<Tab>', '    abc', 0)
  validate_edit1d('  abc', 1, '<Tab>', '    abc', 1)
  validate_edit1d('  abc', 2, '<Tab>', '  abc', 2)

  -- - Visual mode (cursor should be exactly on indent)
  local validate_vis_mode = function(key, before_line, before_col, after_line, after_col)
    validate_edit1d(before_line, before_col, key .. '<Tab>', after_line, after_col)
    eq(child.fn.mode(), 'n')
  end

  validate_vis_mode('v', 'abc', 0, 'abc', 0)
  validate_vis_mode('v', 'abc', 1, 'abc', 1)
  validate_vis_mode('v', '  abc', 0, '    abc', 0)
  validate_vis_mode('v', '  abc', 1, '    abc', 1)
  validate_vis_mode('v', '  abc', 2, '  abc', 2)

  validate_vis_mode('V', 'abc', 0, 'abc', 0)
  validate_vis_mode('V', 'abc', 1, 'abc', 1)
  validate_vis_mode('V', '  abc', 0, '    abc', 0)
  validate_vis_mode('V', '  abc', 1, '    abc', 1)
  validate_vis_mode('V', '  abc', 2, '  abc', 2)

  -- - Is not well defined for blockwise visual selection
end

T['map_multistep()']['built-in steps']['decrease_indent'] = function()
  map_multistep({ 'n', 'i', 'x' }, '<S-Tab>', { 'decrease_indent' })

  -- Should work as with built-in keys, i.e. respecting relevant options
  child.bo.expandtab = true
  child.bo.shiftwidth = 2
  child.bo.tabstop = 4

  --  Should only work when inside indent (even empty)
  -- - Insert mode (cursor can be "just after indent", i.e. on next cell)
  validate_edit1d('abc', 0, 'i<S-Tab>', 'abc', 0)
  validate_edit1d('abc', 1, 'i<S-Tab>', 'a   bc', 4)
  validate_edit1d('  abc', 0, 'i<S-Tab>', 'abc', 0)
  validate_edit1d('  abc', 2, 'i<S-Tab>', 'abc', 0)
  validate_edit1d('  abc', 3, 'i<S-Tab>', '  a bc', 4)

  -- - Normal mode (cursor should be exactly on indent)
  validate_edit1d('abc', 0, '<S-Tab>', 'abc', 0)
  validate_edit1d('abc', 1, '<S-Tab>', 'abc', 1)
  validate_edit1d('  abc', 0, '<S-Tab>', 'abc', 0)
  validate_edit1d('  abc', 1, '<S-Tab>', 'abc', 1)
  validate_edit1d('  abc', 2, '<S-Tab>', '  abc', 2)

  -- - Visual mode (cursor should be exactly on indent)
  local validate_vis_mode = function(key, before_line, before_col, after_line, after_col)
    validate_edit1d(before_line, before_col, key .. '<S-Tab>', after_line, after_col)
    eq(child.fn.mode(), 'n')
  end

  validate_vis_mode('v', 'abc', 0, 'abc', 0)
  validate_vis_mode('v', 'abc', 1, 'abc', 1)
  validate_vis_mode('v', '  abc', 0, 'abc', 0)
  validate_vis_mode('v', '  abc', 1, 'abc', 1)
  validate_vis_mode('v', '  abc', 2, '  abc', 2)

  validate_vis_mode('V', 'abc', 0, 'abc', 0)
  validate_vis_mode('V', 'abc', 1, 'abc', 1)
  validate_vis_mode('V', '  abc', 0, 'abc', 0)
  validate_vis_mode('V', '  abc', 1, 'abc', 1)
  validate_vis_mode('V', '  abc', 2, '  abc', 2)

  -- - Is not well defined for blockwise visual selection
end

T['map_multistep()']['built-in steps']['hungry_bs'] = function()
  map_multistep({ 'n', 'i', 'x' }, '<BS>', { 'hungry_bs', 'minipairs_bs' })

  -- Should delete all consecutive whitespace before cursor
  validate_edit1d('', 0, 'i<BS>', '', 0)
  validate_edit1d('   ', 1, 'i<BS>', '  ', 0)
  validate_edit1d('   ', 2, 'a<BS>', '', 0)

  validate_edit1d('\t\t\t', 2, 'a<BS>', '', 0)
  validate_edit1d(' \t ', 2, 'a<BS>', '', 0)

  validate_edit1d(' a  bc', 0, 'i<BS>', ' a  bc', 0)
  validate_edit1d(' a  bc', 1, 'i<BS>', 'a  bc', 0)
  validate_edit1d(' a  bc', 2, 'i<BS>', '   bc', 1)
  validate_edit1d(' a  bc', 3, 'i<BS>', ' a bc', 2)
  validate_edit1d(' a  bc', 4, 'i<BS>', ' abc', 2)
  validate_edit1d(' a  bc', 5, 'i<BS>', ' a  c', 4)
  validate_edit1d(' a  bc', 6, 'a<BS>', ' a  b', 5)

  -- Should not span across line
  validate_edit({ 'a  ', '  b' }, { 2, 2 }, 'i<BS>', { 'a  ', 'b' }, { 2, 0 })
  validate_edit({ '  ', '  b' }, { 2, 2 }, 'i<BS>', { '  ', 'b' }, { 2, 0 })
  validate_edit({ '', '  b' }, { 2, 2 }, 'i<BS>', { '', 'b' }, { 2, 0 })

  -- Should work in all modes (but cursor should be exactly on whitespace)
  -- - Normal (unmapped <BS> moves cursor to the left)
  validate_edit1d(' a  bc', 0, '<BS>', 'a  bc', 0)
  validate_edit1d(' a  bc', 1, '<BS>', ' a  bc', 0)
  validate_edit1d(' a  bc', 2, '<BS>', ' a bc', 2)
  validate_edit1d(' a  bc', 3, '<BS>', ' abc', 2)
  validate_edit1d(' a  bc', 4, '<BS>', ' a  bc', 3)
  validate_edit1d(' a  bc', 5, '<BS>', ' a  bc', 4)

  local validate_vis_mode = function(key, before_line, before_col, after_line, after_col)
    set_lines({ before_line })
    set_cursor(1, before_col)
    type_keys(key .. '<BS>')
    eq(get_lines(), { after_line })
    eq(get_cursor(), { 1, after_col })

    local ref_mode = key == '<C-v>' and '\22' or key
    eq(child.fn.mode(), ref_mode)
    child.ensure_normal_mode()
  end

  validate_vis_mode('v', ' a  bc', 0, 'a  bc', 0)
  validate_vis_mode('v', ' a  bc', 1, ' a  bc', 0)
  validate_vis_mode('v', ' a  bc', 2, ' a bc', 2)
  validate_vis_mode('v', ' a  bc', 3, ' abc', 2)
  validate_vis_mode('v', ' a  bc', 4, ' a  bc', 3)
  validate_vis_mode('v', ' a  bc', 5, ' a  bc', 4)

  -- - Is not well defined for linewise and blockwise visual selection

  -- Should work well with 'mini.pairs'
  child.lua('require("mini.pairs").setup()')
  validate_edit1d('(   )', 4, 'i<BS><BS>', '', 0)
end

T['map_multistep()']['built-in steps']['vimsnippet_next'] = function()
  if child.fn.has('nvim-0.10') == 0 then MiniTest.skip('`vim.snippet` is available only on Neovim>=0.10') end

  -- Make sure to not test built-in <Tab> mappings from Neovim>=0.11
  pcall(child.cmd, 'iunmap <Tab>')
  pcall(child.cmd, 'sunmap <Tab>')

  map_multistep({ 'i', 's' }, '<Tab>', { 'vimsnippet_next' })

  -- Should pass through if there is no active session
  type_keys('i', '<Tab>')
  eq(get_lines(), { '\t' })
  set_lines({})

  -- Should jump to next tabstop
  child.lua('vim.snippet.expand("Snippet $1 ${2:placeholder} ab$0")')
  eq(get_lines(), { 'Snippet  placeholder ab' })
  eq(get_cursor(), { 1, 8 })
  eq(child.fn.mode(), 'i')

  type_keys('<Tab>')
  eq(get_lines(), { 'Snippet  placeholder ab' })
  eq(get_cursor(), { 1, 9 })
  eq(child.fn.mode(), 's')

  type_keys('<Tab>')
  eq(get_lines(), { 'Snippet  placeholder ab' })
  eq(get_cursor(), { 1, 23 })
  eq(child.fn.mode(), 'i')
end

T['map_multistep()']['built-in steps']['vimsnippet_prev'] = function()
  if child.fn.has('nvim-0.10') == 0 then MiniTest.skip('`vim.snippet` is available only on Neovim>=0.10') end

  -- Make sure to not test built-in <Tab> mappings from Neovim>=0.11
  pcall(child.cmd, 'iunmap <S-Tab>')
  pcall(child.cmd, 'sunmap <S-Tab>')

  map_multistep({ 'i', 's' }, '<S-Tab>', { 'vimsnippet_prev' })

  -- Should pass through if there is no active session
  type_keys('i', '<Tab>')
  eq(get_lines(), { '\t' })
  set_lines({})

  -- Should jump to next tabstop
  child.lua('vim.snippet.expand("Snippet $1 ${2:placeholder} $3ab$0")')
  child.lua('vim.snippet.jump(1)')
  child.lua('vim.snippet.jump(1)')
  eq(get_lines(), { 'Snippet  placeholder ab' })
  eq(get_cursor(), { 1, 21 })
  eq(child.fn.mode(), 'i')

  type_keys('<S-Tab>')
  eq(get_lines(), { 'Snippet  placeholder ab' })
  eq(get_cursor(), { 1, 9 })
  eq(child.fn.mode(), 's')

  type_keys('<S-Tab>')
  eq(get_lines(), { 'Snippet  placeholder ab' })
  eq(get_cursor(), { 1, 8 })
  eq(child.fn.mode(), 'i')
end

T['map_multistep()']['built-in steps']['cmp_next'] = function()
  map_multistep('i', '<Tab>', { 'cmp_next' })

  -- Should work if 'cmp' module is not present
  type_keys('i', '<Tab>')
  eq(get_lines(), { '\t' })
  validate_log_and_clean({})

  mock_plugin('nvim-cmp')

  -- Should pass through if there is no visible nvim-cmp menu
  type_keys('<Tab>')
  eq(get_lines(), { '\t\t' })
  validate_log_and_clean({ 'cmp.visible' })

  child.lua('_G.cmp_visible_res = true')
  type_keys('<Tab>')
  -- - Should not modify text
  eq(get_lines(), { '\t\t' })
  validate_log_and_clean({ 'cmp.visible', 'cmp.select_next_item' })
end

T['map_multistep()']['built-in steps']['cmp_prev'] = function()
  map_multistep('i', '<S-Tab>', { 'cmp_prev' })

  -- Should work if 'cmp' module is not present
  type_keys('i', '<S-Tab>')
  eq(get_lines(), { '\t' })
  validate_log_and_clean({})

  mock_plugin('nvim-cmp')

  -- Should pass through if there is no visible nvim-cmp menu
  type_keys('<S-Tab>')
  eq(get_lines(), { '\t\t' })
  validate_log_and_clean({ 'cmp.visible' })

  child.lua('_G.cmp_visible_res = true')
  type_keys('<S-Tab>')
  -- - Should not modify text
  eq(get_lines(), { '\t\t' })
  validate_log_and_clean({ 'cmp.visible', 'cmp.select_prev_item' })
end

T['map_multistep()']['built-in steps']['cmp_accept'] = function()
  map_multistep('i', '<CR>', { 'cmp_accept' })

  -- Should work if 'cmp' module is not present
  type_keys('i', '<CR>')
  eq(get_lines(), { '', '' })
  validate_log_and_clean({})

  mock_plugin('nvim-cmp')

  -- Should pass through if there is no selected nvim-cmp item
  type_keys('<CR>')
  eq(get_lines(), { '', '', '' })
  validate_log_and_clean({ 'cmp.get_selected_entry' })

  child.lua('_G.cmp_get_selected_entry_res = {}')
  type_keys('<CR>')
  -- - Should not modify text
  eq(get_lines(), { '', '', '' })
  validate_log_and_clean({ 'cmp.get_selected_entry', 'cmp.confirm' })
end

T['map_multistep()']['built-in steps']['blink_next'] = function()
  map_multistep('i', '<Tab>', { 'blink_next' })

  -- Should work if 'blink.cmp' module is not present
  type_keys('i', '<Tab>')
  eq(get_lines(), { '\t' })
  validate_log_and_clean({})

  mock_plugin('blink.cmp')

  -- Should pass through if there is no visible blink menu
  type_keys('<Tab>')
  eq(get_lines(), { '\t\t' })
  validate_log_and_clean({ 'blink.is_menu_visible' })

  child.lua('_G.blink_is_menu_visible_res = true')
  type_keys('<Tab>')
  -- - Should not modify text
  eq(get_lines(), { '\t\t' })
  validate_log_and_clean({ 'blink.is_menu_visible', 'blink.select_next' })
end

T['map_multistep()']['built-in steps']['blink_prev'] = function()
  map_multistep('i', '<S-Tab>', { 'blink_prev' })

  -- Should work if 'blink.cmp' module is not present
  type_keys('i', '<S-Tab>')
  eq(get_lines(), { '\t' })
  validate_log_and_clean({})

  mock_plugin('blink.cmp')

  -- Should pass through if there is no visible blink.cmp menu
  type_keys('<S-Tab>')
  eq(get_lines(), { '\t\t' })
  validate_log_and_clean({ 'blink.is_menu_visible' })

  child.lua('_G.blink_is_menu_visible_res = true')
  type_keys('<S-Tab>')
  -- - Should not modify text
  eq(get_lines(), { '\t\t' })
  validate_log_and_clean({ 'blink.is_menu_visible', 'blink.select_prev' })
end

T['map_multistep()']['built-in steps']['blink_accept'] = function()
  map_multistep('i', '<CR>', { 'blink_accept' })

  -- Should work if 'blink.mp' module is not present
  type_keys('i', '<CR>')
  eq(get_lines(), { '', '' })
  validate_log_and_clean({})

  mock_plugin('blink.cmp')

  -- Should pass through if there is no selected blink.cmp item
  child.lua('_G.blink_is_menu_visible_res = true')
  type_keys('<CR>')
  eq(get_lines(), { '', '', '' })
  validate_log_and_clean({ 'blink.is_menu_visible', 'blink.get_selected_item' })

  child.lua('_G.blink_get_selected_item_res = {}')
  type_keys('<CR>')
  -- - Should not modify text
  eq(get_lines(), { '', '', '' })
  validate_log_and_clean({ 'blink.is_menu_visible', 'blink.get_selected_item', 'blink.accept' })
end

T['map_multistep()']['built-in steps']['luasnip_next'] = function()
  map_multistep('i', '<Tab>', { 'luasnip_next' })

  -- Should work if 'luasnip' module is not present
  type_keys('i', '<Tab>')
  eq(get_lines(), { '\t' })
  validate_log_and_clean({})

  mock_plugin('luasnip')

  -- Should pass through if there is no active session
  type_keys('<Tab>')
  eq(get_lines(), { '\t\t' })
  validate_log_and_clean({ 'luasnip.jumpable' })

  child.lua('_G.luasnip_jumpable_res = true')
  type_keys('<Tab>')
  -- - Should not modify text
  eq(get_lines(), { '\t\t' })
  validate_log_and_clean({ 'luasnip.jumpable', 'luasnip.jump 1' })
end

T['map_multistep()']['built-in steps']['luasnip_prev'] = function()
  map_multistep('i', '<S-Tab>', { 'luasnip_prev' })

  -- Should work if 'luasnip' module is not present
  type_keys('i', '<S-Tab>')
  eq(get_lines(), { '\t' })
  validate_log_and_clean({})

  mock_plugin('luasnip')

  -- Should pass through if there is no active session
  type_keys('<S-Tab>')
  eq(get_lines(), { '\t\t' })
  validate_log_and_clean({ 'luasnip.jumpable' })

  child.lua('_G.luasnip_jumpable_res = true')
  type_keys('<S-Tab>')
  -- - Should not modify text
  eq(get_lines(), { '\t\t' })
  validate_log_and_clean({ 'luasnip.jumpable', 'luasnip.jump -1' })
end

T['map_multistep()']['built-in steps']['luasnip_expand'] = function()
  map_multistep('i', '<Tab>', { 'luasnip_next', 'luasnip_expand' })

  -- Should work if 'luasnip' module is not present
  type_keys('i', '<Tab>')
  eq(get_lines(), { '\t' })
  validate_log_and_clean({})

  mock_plugin('luasnip')

  -- Should pass through if there is no active session or expandable prefix
  type_keys('<Tab>')
  eq(get_lines(), { '\t\t' })
  validate_log_and_clean({ 'luasnip.jumpable', 'luasnip.expandable' })

  child.lua('_G.luasnip_expandable_res = true')
  type_keys('<Tab>')
  -- - Should not modify text
  eq(get_lines(), { '\t\t' })
  validate_log_and_clean({ 'luasnip.jumpable', 'luasnip.expandable', 'luasnip.expand' })

  child.lua('_G.luasnip_jumpable_res = true')
  type_keys('<Tab>')
  -- - Should not modify text
  eq(get_lines(), { '\t\t' })
  validate_log_and_clean({ 'luasnip.jumpable', 'luasnip.jump 1' })
end

T['map_multistep()']['built-in steps']['nvimautopairs_cr'] = function()
  map_multistep('i', '<CR>', { 'nvimautopairs_cr' })

  -- Should work if 'nvim-autopairs' module is not present
  type_keys('i', '<CR>')
  eq(get_lines(), { '', '' })

  mock_plugin('nvim-autopairs')
  child.bo.autoindent = false

  -- Should respect pairs
  type_keys('()', '<Left>')
  eq(get_lines(), { '', '()' })
  type_keys('<CR>')
  eq(get_lines(), { '', '(', '', ')' })
end

T['map_multistep()']['built-in steps']['nvimautopairs_bs'] = function()
  map_multistep('i', '<BS>', { 'nvimautopairs_bs' })

  -- Should work if 'nvim-autopairs' module is not present
  type_keys('i', '()', '<Left>', '<BS>')
  eq(get_lines(), { ')' })

  mock_plugin('nvim-autopairs')

  -- Should respect pairs
  set_lines({ 'a()' })
  set_cursor(1, 2)
  eq(get_lines(), { 'a()' })
  type_keys('<BS>')
  eq(get_lines(), { 'a' })
end

T['gen_step'] = new_set()

T['gen_step']['search_pattern()'] = new_set()

T['gen_step']['search_pattern()']['works'] = function()
  child.lua([=[
    local keymap = require('mini.keymap')
    local step = keymap.gen_step.search_pattern([[[(\[{]\+]], 'bW')
    keymap.map_multistep({ 'i', 'n', 'x' }, '<S-Tab>', { step })
  ]=])

  set_lines({ 'xx[_{(_[[[', '[_(' })

  -- Insert mode
  set_cursor(2, 1)
  local ref_jumps = {
    -- Should respect pattern and flags (search backward, no wrapping)
    { 2, 0 },
    { 1, 7 },
    { 1, 4 },
    { 1, 2 },

    -- Should silently do nothing if can not jump
    { 1, 2 },
  }
  type_keys('i')
  validate_jumps('<S-Tab>', ref_jumps)

  -- Normal mode
  set_cursor(2, 1)
  validate_jumps('<S-Tab>', ref_jumps)

  -- Visual mode
  set_cursor(2, 1)
  type_keys('v')
  validate_jumps('<S-Tab>', ref_jumps)

  set_cursor(2, 1)
  type_keys('V')
  validate_jumps('<S-Tab>', ref_jumps)

  set_cursor(2, 1)
  type_keys('<C-v>')
  validate_jumps('<S-Tab>', ref_jumps)
end

T['gen_step']['search_pattern()']['respects `opts.side`'] = function()
  child.lua([=[
    local keymap = require('mini.keymap')
    local step = keymap.gen_step.search_pattern([[[)\]}]\+]], 'ceW', { side = 'after' })
    keymap.map_multistep('i', '<Tab>', { step })
  ]=])

  set_lines({ ']_)', ']_})_]]]xx' })
  set_cursor(1, 1)
  type_keys('i')

  validate_jumps('<Tab>', {
    -- Should respect pattern and flags (search forward, no wrapping) and put
    -- cursor to the right
    { 1, 3 },
    { 2, 1 },
    { 2, 4 },
    { 2, 8 },

    -- Should silently do nothing if can not jump
    { 2, 8 },
  })
end

T['gen_step']['search_pattern()']['respects `opts.stopline`'] = function()
  child.lua([=[
    local keymap = require('mini.keymap')
    local step_num = keymap.gen_step.search_pattern(')', 'W', { stopline = 1 })
    keymap.map_multistep('n', '<Tab>', { step_num })
    local step_fun = keymap.gen_step.search_pattern('(', 'bW', { stopline = function() return vim.fn.line('.') end })
    keymap.map_multistep('n', '<S-Tab>', { step_fun })
  ]=])

  set_lines({ '()', '()' })
  set_cursor(1, 0)
  validate_jumps('<Tab>', { { 1, 1 }, { 1, 1 } })
  set_cursor(2, 1)
  validate_jumps('<S-Tab>', { { 2, 0 }, { 2, 0 } })
end

T['gen_step']['search_pattern()']['respects `opts.timeout` and `opts.skip`'] = function()
  child.lua([[
    local search_orig = vim.fn.search
    vim.fn.search = function(...)
      _G.args = { ... }
      return search_orig(...)
    end
    local keymap = require('mini.keymap')
    local step = keymap.gen_step.search_pattern(')', 'W', { timeout = 1, skip = 'a' })
    keymap.map_multistep('n', '<Tab>', { step })
  ]])

  type_keys('<Tab>')
  eq(child.lua_get('vim.deep_equal(_G.args, { ")", "W", nil, 1, "a" })'), true)
end

T['gen_step']['search_pattern()']['validates input'] = function()
  local validate = function(args, ref_pattern)
    expect.error(function() child.lua('require("mini.keymap").gen_step.search_pattern(...)', args) end, ref_pattern)
  end
  validate({ 1, '' }, '`pattern`.*string')
  validate({ 'a', 1 }, '`flags`.*string')
  validate({ 'a', '', { side = 1 } }, '`opts.side`.*one of')
end

T['gen_step']['search_pattern()']['hides pmenu'] = function()
  child.lua([[
    local keymap = require('mini.keymap')
    local step = keymap.gen_step.search_pattern(')')
    keymap.map_multistep({ 'i' }, '<Tab>', { step })
  ]])

  set_lines({ 'xx ( yy )' })
  set_cursor(1, 5)
  type_keys('i', '<C-n>')
  eq(is_pumvisible(), true)
  type_keys('<Tab>')
  eq(is_pumvisible(), false)
end

T['map_combo()'] = new_set({ n_retry = helpers.get_n_retry(5) })

local map_combo = forward_lua('require("mini.keymap").map_combo')

T['map_combo()']['works with string RHS'] = function()
  map_combo('i', 'jk', '<BS><BS><Esc>')

  -- Should be emulated as if pressing keys
  type_keys('i')
  -- - Key should be processed immediately
  type_keys('j')
  eq(get_lines(), { 'j' })
  sleep(default_combo_delay - small_time)
  type_keys('k')
  eq(get_lines(), { '' })
  eq(child.fn.mode(), 'n')

  -- Can use full key name in LHS
  map_combo('i', '<BS><CR>', 'hello', { delay = test_combo_delay })
  type_keys('i', 'ab', '<BS>')
  eq(get_lines(), { 'a' })
  sleep(small_time)
  type_keys('<CR>')
  eq(get_lines(), { 'a', 'hello' })

  set_lines({ '' })
  child.ensure_normal_mode()

  -- Can use more than two keys
  map_combo('i', 'asdf', ' world', { delay = test_combo_delay })
  type_keys('i', 'a')
  eq(get_lines(), { 'a' })

  sleep(small_time)
  type_keys('s')
  eq(get_lines(), { 'as' })

  sleep(small_time)
  type_keys('d')
  eq(get_lines(), { 'asd' })

  sleep(small_time)
  type_keys('f')
  eq(get_lines(), { 'asdf world' })
end

T['map_combo()']['works with callable RHS'] = function()
  child.lua('_G.delay = ' .. test_combo_delay)
  -- Output string should be mimicked as if supplied as right hand side
  child.lua([[
    local rhs = function() table.insert(_G.log, "rhs"); return 'yy' end
    require("mini.keymap").map_combo("i", "xx", rhs, { delay = _G.delay })
  ]])

  -- Should be executed while intermediate keys immediately processed as usual
  type_keys('i', 'x')
  eq(get_lines(), { 'x' })
  sleep(small_time)
  type_keys('x')
  eq(get_lines(), { 'xxyy' })
  eq(child.fn.mode(), 'i')
  validate_log_and_clean({ 'rhs' })
end

T['map_combo()']['allows RHS to change mode and operate in it'] = function()
  map_combo('i', 'jk', '<Esc>viwUo', { delay = test_combo_delay })
  type_keys('i')
  type_keys(small_time, 'j', 'k')
  eq(get_lines(), { 'JK', '' })
end

T['map_combo()']['works with array LHS'] = function()
  map_combo('i', { 'ы', '<Space>', '半' }, '<Tab>', { delay = test_combo_delay })

  type_keys('i', 'ы')
  sleep(small_time)
  type_keys(' ')
  sleep(small_time)
  type_keys('半')
  eq(get_lines(), { 'ы 半\t' })
  eq(child.fn.mode(), 'i')
end

T['map_combo()']['resets if typed above delay'] = function()
  map_combo('i', 'jk', 'hello', { delay = test_combo_delay })
  map_combo('i', 'asd', 'world', { delay = test_combo_delay })

  type_keys('i', 'j')
  sleep(test_combo_delay + small_time)
  type_keys('k')
  eq(get_lines(), { 'jk' })

  -- Should stop on any step
  type_keys(small_time, 'a', 's')
  sleep(test_combo_delay + small_time)
  type_keys('d')
  eq(get_lines(), { 'jkasd' })
end

T['map_combo()']['works in different modes'] = function()
  map_combo({ 'n', 'x', 'c', 't' }, 'jj', 'll', { delay = test_combo_delay })

  set_lines({ 'aaa', 'bbb', 'ccc' })
  set_cursor(1, 0)

  -- Normal mode
  type_keys(small_time, 'j', 'j')
  eq(get_cursor(), { 3, 2 })

  -- Visual mode
  local validate_visual = function(mode_key_raw)
    set_cursor(1, 0)
    type_keys(small_time, mode_key_raw, 'j', 'j')
    eq(get_cursor(), { 3, 2 })
    eq(child.fn.mode(), mode_key_raw)
    child.ensure_normal_mode()
  end

  validate_visual('v')
  validate_visual('V')
  validate_visual('\22')

  -- Command-line mode
  type_keys(small_time, ':', 'j', 'j')
  eq(child.fn.getcmdline(), 'jjll')
  child.ensure_normal_mode()

  -- Terminal mode
  helpers.skip_on_windows('Terminal emulator testing is not robust/easy on Windows')
  helpers.skip_on_macos('Terminal emulator testing is not robust/easy on MacOS')

  -- Setup
  child.cmd('terminal! bash --noprofile --norc')
  -- Wait for terminal to get active
  sleep(term_mode_wait)
  child.cmd('startinsert')

  -- Need to wait after each keystroke to allow shell to process it
  type_keys(small_time, 'j', 'j')
  sleep(5 * small_time)
  expect.match(get_lines()[1], 'jjll$')
end

T['map_combo()']['takes user mappings into account when executing RHS'] = function()
  map_combo('n', 'jj', 'll', { delay = test_combo_delay })
  child.cmd('nnoremap ll <Cmd>lua table.insert(_G.log, "custom ll")<CR>')

  type_keys(small_time, 'j', 'j')
  validate_log_and_clean({ 'custom ll' })
end

T['map_combo()']['not recursive during RHS keys execution'] = function()
  map_combo('i', 'jk', 'jk', { delay = test_combo_delay })
  type_keys('i')
  type_keys(small_time, 'j', 'k')
  eq(get_lines(), { 'jkjk' })

  type_keys(small_time, 'j', 'k')
  eq(get_lines(), { 'jkjkjkjk' })
end

T['map_combo()']['ignores RHS keys in tracking'] = function()
  map_combo('n', 'll', 'ww', { delay = test_combo_delay })
  map_combo('n', 'ww', 'dd', { delay = test_combo_delay })
  map_combo('n', 'lll', '$', { delay = test_combo_delay })

  set_lines({ 'aaaaa bbbbb ccccc ddddd eeeee' })
  set_cursor(1, 0)
  type_keys(small_time, 'l', 'l')
  eq(get_cursor(), { 1, 12 })
  type_keys('l')
  eq(get_cursor(), { 1, 28 })
end

T['map_combo()']['detecting combo does not depend on preceding keys'] = function()
  map_combo('i', 'jk', 'xy', { delay = test_combo_delay })
  type_keys('i')
  type_keys(small_time, 'j', 'j', 'k', 'j')
  eq(get_lines(), { 'jjkxyj' })
  set_lines({ '' })
  child.ensure_normal_mode()

  map_combo('i', 'jj', 'XY', { delay = test_combo_delay })
  type_keys('i', 'j')
  sleep(test_combo_delay + small_time)
  type_keys(small_time, 'j', 'j')
  eq(get_lines(), { 'jjjXY' })
end

T['map_combo()']['works when typing already mapped keys'] = function()
  -- On Neovim>=0.11 for a `jk` LHS. On Neovim<0.11 for a `gjgk` LHS.
  child.cmd('xnoremap j gj', { delay = test_combo_delay })

  -- Neovim<0.11 doesn't have functionality to truly track "keys as typed",
  -- only after "mappings are applied" (see `:h vim.on_key()`)
  local lhs = child.fn.has('nvim-0.11') == 1 and 'jj' or 'gjgj'
  map_combo('x', lhs, 'll', { delay = test_combo_delay })
  set_lines({ 'aaa', 'bbb', 'ccc' })
  type_keys('v')
  type_keys(small_time, 'j', 'j')
  eq(get_cursor(), { 3, 2 })
end

T['map_combo()']['works with tricky LHS'] = function()
  -- Should recognise LHS as three keys (`<`, `\t`, `>`)
  map_combo('i', '<<Tab>>', 'hello', { delay = test_combo_delay })
  type_keys('i')
  type_keys(small_time, '<', '\t', '>')
  eq(get_lines(), { '<\t>hello' })
end

T['map_combo()']['creates namespaces with informative names'] = function()
  map_combo('i', 'jk', '<BS><BS><Esc>')
  map_combo('i', 'jk', 'hello')
  map_combo({ 'n', 'x' }, '<Space>\t', 'hello')
  local namespaces = child.api.nvim_get_namespaces()
  eq(namespaces['MiniKeymap-combo-0-i-jk'] ~= nil, true)
  eq(namespaces['MiniKeymap-combo-1-i-jk'] ~= nil, true)
  eq(namespaces['MiniKeymap-combo-2-nx-<Space><Tab>'] ~= nil, true)
end

T['map_combo()']['separate combos act independently'] = function()
  child.lua('_G.delay = ' .. test_combo_delay)
  child.lua([[
    local combo = function(lhs, rhs)
      require("mini.keymap").map_combo('i', lhs, rhs, { delay = _G.delay })
    end
    _G.n1, _G.n2, _G.n3, _G.n4 = 0, 0, 0, 0
    combo('jk',  function() _G.n1 = _G.n1 + 1 end)
    combo('jjk', function() _G.n2 = _G.n2 + 1 end)
    combo('kj',  function() _G.n3 = _G.n3 + 1 end)
    combo('kjj', function() _G.n4 = _G.n4 + 1 end)
  ]])

  type_keys('i')
  type_keys(small_time, 'j', 'j', 'k', 'j', 'j')
  eq(child.lua_get('{ _G.n1, _G.n2, _G.n3, _G.n4 }'), { 1, 1, 1, 1 })
end

T['map_combo()']['allows several combos for the same mode-lhs pair'] = function()
  child.lua('_G.delay = ' .. test_combo_delay)
  child.lua([[
    local combo = function(lhs, rhs)
      require("mini.keymap").map_combo('i', lhs, rhs, { delay = _G.delay })
    end
    _G.n1, _G.n2 = 0, 0
    combo('jk', function() _G.n1 = _G.n1 + 1 end)
    combo('jk', function() _G.n2 = _G.n2 + 1 end)
  ]])

  type_keys('i')
  type_keys(small_time, 'j', 'k')
  eq(child.lua_get('{ _G.n1, _G.n2 }'), { 1, 1 })
end

T['map_combo()']['works inside macros'] = function()
  map_combo('i', 'jk', '<BS><BS><Esc>', { delay = test_combo_delay })

  type_keys('q', 'q', 'i')
  type_keys(small_time, 'j', 'j', 'k')
  type_keys('yy', 'p')
  type_keys('q')
  eq(get_lines(), { 'j', 'j' })
  eq(get_cursor(), { 2, 0 })
  eq(child.fn.mode(), 'n')

  type_keys('@', 'q')
  eq(get_lines(), { 'j', 'jj', 'jj' })
  eq(get_cursor(), { child.fn.has('nvim-0.11') == 1 and 3 or 2, 0 })
  eq(child.fn.mode(), 'n')
end

T['map_combo()']['respects `opts.delay`'] = function()
  map_combo('i', 'jk', 'xy', { delay = 1.5 * default_combo_delay + 2 * small_time })
  type_keys('i', 'j')
  sleep(1.5 * default_combo_delay)
  type_keys('k')
  eq(get_lines(), { 'jkxy' })
end

T['map_combo()']['validates input'] = function()
  expect.error(function() map_combo(1, 'jk', '<Esc>') end, '`mode`.*string or array of strings')
  expect.error(function() map_combo('i', 1, '<Esc>') end, '`lhs`.*string or array of strings')
  expect.error(function() map_combo('i', 'jk', 1) end, '`action`.*string.*callable')
  expect.error(function() map_combo('i', 'jk', 'xy', { delay = 'a' }) end, '`opts%.delay`.*number')
  expect.error(function() map_combo('i', 'jk', 'xy', { delay = 0 }) end, '`opts%.delay`.*positive')
  expect.error(function() map_combo('i', 'jk', 'xy', { delay = -1 }) end, '`opts%.delay`.*positive')
end

T['map_combo()']['respects `vim.{g,b}.minikeymap_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    map_combo('i', 'jk', 'hello', { delay = test_combo_delay })
    type_keys('i')

    child[var_type].minikeymap_disable = true
    type_keys(small_time, 'j', 'k')
    eq(get_lines(), { 'jk' })

    child[var_type].minikeymap_disable = false
    type_keys(small_time, 'j', 'k')
    eq(get_lines(), { 'jkjkhello' })
  end,
})

-- Integration tests ==========================================================
return T
