local helpers = dofile('tests/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('pairs', config) end
local unload_module = function() child.mini_unload('pairs') end
local reload_module = function(config) unload_module(); load_module(config) end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
local sleep = function(ms) helpers.sleep(ms, child) end
--stylua: ignore end

-- Make helpers
local get_term_channel = function()
  local term_chans = vim.tbl_filter(function(x) return x.mode == 'terminal' end, child.api.nvim_list_chans())[1]['id']
  return term_chans[1]['id']
end

-- Time constants
local term_mode_wait = helpers.get_time_const(50)

--- Make simple test on empty entity
---@private
local validate_action = function(mode, test)
  mode = mode or 'i'

  -- Expects to start in Normal mode
  if mode == 'i' then
    -- Setup
    local lines, cursor = get_lines(), get_cursor()
    set_lines({})
    child.cmd('startinsert')

    -- Test
    test()

    -- Cleanup
    type_keys('<Esc>')
    set_lines(lines)
    set_cursor(unpack(cursor))
  elseif mode == 'c' then
    -- Setup
    type_keys(':')

    -- Test
    test()

    -- Cleanup
    type_keys('<Esc>')
  elseif mode == 't' then
    helpers.skip_on_windows('Terminal emulator testing is not robust/easy on Windows')
    helpers.skip_on_macos('Terminal emulator testing is not robust/easy on MacOS')

    -- Setup
    child.cmd('terminal! bash --noprofile --norc')
    -- Wait for terminal to get active
    sleep(term_mode_wait)
    child.cmd('startinsert')

    -- Test
    test()

    -- Cleanup
    type_keys([[<C-\>]], '<C-n>')
    child.cmd('bwipeout!')
  end
end

--- Validate that `key` on its own inserts `pair` (whatever it is: for smaller
--- code, it might be single character to test in 'MiniPairs.close()').
---@private
local validate_open = function(mode, key, pair)
  local test = ({
    i = function()
      type_keys(key)
      eq(get_lines(), { pair })
      eq(get_cursor(), { 1, 1 })
    end,
    c = function()
      type_keys(key)
      eq(child.fn.getcmdline(), pair)
      eq(child.fn.getcmdpos(), 2)
    end,
    t = function()
      -- Need to wait after each keystroke to allow shell to process it
      local wait = 50
      type_keys(wait, key)

      local pair_pattern = vim.pesc(pair) .. '$'
      expect.match(get_lines()[1], pair_pattern)
    end,
  })[mode]

  validate_action(mode, test)
end

--- Validate that `key` jumps over right hand side of `pair` if it is next.
---@private
local validate_close = function(mode, key, pair)
  local test = ({
    i = function()
      set_lines({ pair })
      set_cursor(1, 1)
      type_keys(key)
      eq(get_lines(), { pair })
      eq(get_cursor(), { 1, 2 })
    end,
    c = function()
      type_keys('<C-v>', pair:sub(1, 1), '<C-v>', pair:sub(2, 2), '<Left>')
      type_keys(key)
      eq(child.fn.getcmdline(), pair)
      eq(child.fn.getcmdpos(), 3)
    end,
    t = function()
      local term_channel = get_term_channel()

      -- Jumps over right hand side of `pair` if it is next
      child.fn.chansend(term_channel, pair)
      -- Need to wait after each keystroke to allow shell to process it
      sleep(term_mode_wait)
      type_keys(term_mode_wait, '<Left>')
      type_keys(term_mode_wait, key)

      local pair_pattern = vim.pesc(pair) .. '$'
      expect.match(get_lines()[1], pair_pattern)
    end,
  })[mode]

  validate_action(mode, test)
end

--- Validate that `<BS>` deletes whole pair if inside of it.
---@private
local validate_bs = function(mode, pair)
  local test = ({
    i = function()
      set_lines({ pair })
      set_cursor(1, 1)
      type_keys('<BS>')
      eq(get_lines(), { '' })
    end,
    c = function()
      type_keys('<C-v>', pair:sub(1, 1), '<C-v>', pair:sub(2, 2), '<Left>')
      type_keys('<BS>')
      eq(child.fn.getcmdline(), '')
      eq(child.fn.getcmdpos(), 1)
    end,
    t = function()
      local term_channel = get_term_channel()

      child.fn.chansend(term_channel, pair)
      -- Need to wait after each keystroke to allow shell to process it
      sleep(term_mode_wait)
      type_keys(term_mode_wait, '<Left>')
      type_keys(term_mode_wait, '<BS>')

      local pair_pattern = vim.pesc(pair) .. '$'
      expect.no_match(get_lines()[1], pair_pattern)
    end,
  })[mode]

  validate_action(mode, test)
end

--- Validate that `<CR>` acts like `<CR><C-o>O` in Insert mode if inside pair.
---@private
local validate_cr = function(pair)
  local test = function()
    -- Reference pass to get baseline data for default behavior
    set_lines({ pair })
    set_cursor(1, 0)
    local keys = child.api.nvim_replace_termcodes('<Esc>a<CR><C-o>O', true, true, true)
    child.api.nvim_feedkeys(keys, 'nx', false)

    local ref_lines, ref_cursor = get_lines(), get_cursor()

    -- Test pass
    set_lines({ pair })
    set_cursor(1, 0)
    type_keys('<Esc>', 'a', '<CR>')

    eq(get_lines(), ref_lines)
    eq(get_cursor(), ref_cursor)
    eq(child.fn.mode(), 'i')
  end

  validate_action('i', test)
end

local validate_neigh_disable = function(neigh, key)
  set_lines({ neigh })
  set_cursor(1, 0)
  type_keys('a')

  type_keys(key)
  eq(get_lines(), { neigh:sub(1, 1) .. key .. neigh:sub(2, 2) })

  child.ensure_normal_mode()
end

local validate_slash = function(key) validate_neigh_disable([[\]], key) end

local validate_no = function(action, ...)
  local val_f = ({
    open = validate_open,
    close = validate_close,
    bs = validate_bs,
    cr = validate_cr,
    neigh_disable = validate_neigh_disable,
  })[action]

  -- Validation function `val_f` should throw error
  local ok, _ = pcall(val_f, ...)
  child.ensure_normal_mode()
  eq(ok, false)
end

local validate_disable = function(var_type, key)
  child[var_type].minipairs_disable = true
  set_lines({})
  child.cmd('startinsert')
  type_keys(key)
  eq(get_lines(), { key })

  child[var_type].minipairs_disable = nil
end

local apply_map = function(fun_name, args_string)
  -- If testing `MiniPairs.map_buf()`, apply it in current buffer
  local is_buf_local = fun_name == 'map_buf' or fun_name == 'unmap_buf'

  -- Apply mapping function of same scope
  local fun_name_actual = ({ map = 'map', unmap = 'map', map_buf = 'map_buf', unmap_buf = 'map_buf' })[fun_name]

  local command = ('MiniPairs.%s(%s%s)'):format(fun_name_actual, is_buf_local and '0, ' or '', args_string)
  child.lua(command)
end

local apply_unmap = function(fun_name, args_string)
  -- If testing `MiniPairs.map_buf()`, apply it in current buffer
  local is_buf_local = fun_name == 'map_buf' or fun_name == 'unmap_buf'

  -- Apply mapping function of same scope
  local fun_name_actual = ({ map = 'unmap', unmap = 'unmap', map_buf = 'unmap_buf', unmap_buf = 'unmap_buf' })[fun_name]

  local command = ('MiniPairs.%s(%s%s)'):format(fun_name_actual, is_buf_local and '0, ' or '', args_string)
  child.lua(command)
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
  eq(child.lua_get('type(_G.MiniPairs)'), 'table')

  -- Autocommand group
  eq(child.fn.exists('#MiniPairs'), 1)
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniPairs.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniPairs.config.' .. field), value) end

  -- Check default values
  expect_config('modes', { insert = true, command = false, terminal = false })
  expect_config("mappings['(']", { action = 'open', pair = '()', neigh_pattern = '[^\\].' })
  expect_config("mappings['[']", { action = 'open', pair = '[]', neigh_pattern = '[^\\].' })
  expect_config("mappings['{']", { action = 'open', pair = '{}', neigh_pattern = '[^\\].' })
  expect_config("mappings[')']", { action = 'close', pair = '()', neigh_pattern = '[^\\].' })
  expect_config("mappings[']']", { action = 'close', pair = '[]', neigh_pattern = '[^\\].' })
  expect_config("mappings['}']", { action = 'close', pair = '{}', neigh_pattern = '[^\\].' })
  expect_config(
    "mappings['\"']",
    { action = 'closeopen', pair = '""', neigh_pattern = '[^\\].', register = { cr = false } }
  )
  expect_config(
    'mappings["\'"]',
    { action = 'closeopen', pair = "''", neigh_pattern = '[^%a\\].', register = { cr = false } }
  )
  expect_config(
    "mappings['`']",
    { action = 'closeopen', pair = '``', neigh_pattern = '[^\\].', register = { cr = false } }
  )
end

T['setup()']['respects `config` argument'] = function()
  unload_module()
  load_module({ modes = { command = true } })
  eq(child.lua_get('MiniPairs.config.modes.command'), true)
end

T['setup()']['validates `config` argument'] = function()
  unload_module()

  local expect_config_error = function(config, name, target_type)
    expect.error(load_module, vim.pesc(name) .. '.*' .. vim.pesc(target_type), config)
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ modes = 'a' }, 'modes', 'table')
  expect_config_error({ modes = { insert = 'a' } }, 'modes.insert', 'boolean')
  expect_config_error({ modes = { command = 'a' } }, 'modes.command', 'boolean')
  expect_config_error({ modes = { terminal = 'a' } }, 'modes.terminal', 'boolean')

  local expect_mapping_pair_info = function(key)
    local quote = key == "'" and '"' or "'"
    local prefix = ('mappings[%s%s%s]'):format(quote, key, quote)
    expect_config_error({ mappings = { [key] = { action = 1 } } }, prefix .. '.action', 'string')
    expect_config_error({ mappings = { [key] = { action = 1 } } }, prefix .. '.action', 'string')
    expect_config_error({ mappings = { [key] = { pair = 1 } } }, prefix .. '.pair', 'string')
    expect_config_error({ mappings = { [key] = { neigh_pattern = 1 } } }, prefix .. '.neigh_pattern', 'string')
    expect_config_error({ mappings = { [key] = { register = 'a' } } }, prefix .. '.register', 'table')
    expect_config_error({ mappings = { [key] = { register = { bs = 1 } } } }, prefix .. '.register.bs', 'boolean')
    expect_config_error({ mappings = { [key] = { register = { cr = 1 } } } }, prefix .. '.register.cr', 'boolean')
  end

  expect_config_error({ mappings = 'a' }, 'mappings', 'table')
  expect_mapping_pair_info('(')
  expect_mapping_pair_info('[')
  expect_mapping_pair_info('{')
  expect_mapping_pair_info(')')
  expect_mapping_pair_info(']')
  expect_mapping_pair_info('}')
  expect_mapping_pair_info('"')
  expect_mapping_pair_info("'")
  expect_mapping_pair_info('`')
end

local has_map = function(lhs, rhs, mode)
  mode = mode or 'i'
  local map_capture = child.cmd_capture(mode .. 'map ' .. lhs)
  return map_capture:find(vim.pesc(rhs)) ~= nil
end

T['setup()']['makes default `config.mappings`'] = function()
  eq(has_map('(', [[v:lua.MiniPairs.open("()", "[^\\].")]]), true)
  eq(has_map('[', [[v:lua.MiniPairs.open("[]", "[^\\].")]]), true)
  eq(has_map('{', [[v:lua.MiniPairs.open("{}", "[^\\].")]]), true)
  eq(has_map(')', [[v:lua.MiniPairs.close("()", "[^\\].")]]), true)
  eq(has_map(']', [[v:lua.MiniPairs.close("[]", "[^\\].")]]), true)
  eq(has_map('}', [[v:lua.MiniPairs.close("{}", "[^\\].")]]), true)
  eq(has_map('"', [[v:lua.MiniPairs.closeopen('""', "[^\\].")]]), true)
  eq(has_map("'", [[v:lua.MiniPairs.closeopen("''", "[^%a\\].")]]), true)
  eq(has_map('`', [[v:lua.MiniPairs.closeopen("``", "[^\\].")]]), true)

  eq(has_map('<CR>', 'v:lua.MiniPairs.cr()'), true)
  eq(has_map('<BS>', 'v:lua.MiniPairs.bs()'), true)
end

T['setup()']['makes custom `config.mappings`'] = function()
  reload_module({ mappings = { ['('] = { pair = '[]', action = 'close' } } })
  eq(has_map('(', [[v:lua.MiniPairs.close("[]", "[^\\].")]]), true)

  reload_module({ mappings = { ['*'] = { pair = '**', action = 'closeopen' } } })
  eq(has_map('*', 'v:lua.MiniPairs.closeopen("**", "..")'), true)
end

T['setup()']['makes mappings in supplied modes'] = function()
  child.api.nvim_del_keymap('i', '(')
  reload_module({ modes = { insert = false, command = true, terminal = false } })

  eq(has_map('(', [[v:lua.MiniPairs.open("()", "[^\\].")]]), false)
  eq(has_map('(', [[v:lua.MiniPairs.open("()", "[^\\].")]], 'c'), true)
end

T['setup()']['allows `false` as `mappings` entry to not create mapping'] = function()
  eq(has_map('(', [[v:lua.MiniPairs.open("()", "[^\\].")]]), true)
  child.api.nvim_del_keymap('i', '(')

  reload_module({ mappings = { ['('] = false } })
  eq(has_map('(', [[v:lua.MiniPairs.open("()", "[^\\].")]]), false)
end

T['map()/map_buf()'] = new_set({
  hooks = {
    pre_case = function()
      -- Allow switching between buffers with unsaved changes
      child.o.hidden = true
    end,
  },
  parametrize = { { 'map' }, { 'map_buf' } },
})

T['map()/map_buf()']['work'] = function(fun_name)
  validate_no('open', 'i', '<', '<>')
  validate_no('bs', 'i', '<>')
  validate_no('cr', '<>')

  apply_map(fun_name, [['i', '<', { action = 'open', pair = '<>' }]])

  validate_open('i', '<', '<>')
  validate_bs('i', '<>')
  validate_cr('<>')
end

T['map()/map_buf()']['create mapping properly'] = function(fun_name)
  local has_open = function()
    validate_open('i', '<', '<>')
    validate_bs('i', '<>')
    validate_cr('<>')
  end
  local no_open = function()
    validate_no('open', 'i', '<', '<>')
    validate_no('bs', 'i', '<>')
    validate_no('cr', '<>')
  end

  -- Set up two buffers
  local buffers = { cur = child.api.nvim_get_current_buf(), new = child.api.nvim_create_buf(true, false) }

  child.api.nvim_set_current_buf(buffers.cur)
  no_open()
  child.api.nvim_set_current_buf(buffers.new)
  no_open()

  child.api.nvim_set_current_buf(buffers.cur)
  apply_map(fun_name, [['i', '<', { action = 'open', pair = '<>' }]])
  has_open()

  child.api.nvim_set_current_buf(buffers.new)
  if fun_name == 'map_buf' then
    no_open()
  else
    has_open()
  end
end

T['map()/map_buf()']['respect `mode` argument'] = function(fun_name)
  local validate = function(mode)
    local command = ([['%s', '<', { action = 'open', pair = '<>' }]]):format(mode)
    apply_map(fun_name, command)
    validate_open(mode, '<', '<>')
  end

  validate('i')
  -- If making global mapping, also test in other modes
  if fun_name == 'map' then
    validate('c')
    validate('t')
  end
end

T['map()/map_buf()']['respect `lhs` argument'] = function(fun_name)
  apply_map(fun_name, [['i', '<', { action = 'open', pair = '<>' }]])
  validate_open('i', '<', '<>')

  apply_map(fun_name, [['i', '$', { action = 'open', pair = '$%' }]])
  validate_open('i', '$', '$%')
end

T['map()/map_buf()']['respect `action` and `pair` of `pair_info` argument'] = function(fun_name)
  apply_map(fun_name, [['i', '>', { action = 'close', pair = '<>' }]])
  validate_close('i', '>', '<>')
end

T['map()/map_buf()']['respect `neigh_pattern` of `pair_info` argument'] = function(fun_name)
  -- It should insert pair only when cursor after whitespace and before
  -- letter 'a'
  apply_map(fun_name, [['i', '<', { action = 'open', pair = '<>', neigh_pattern = '%sa' }]])

  local test = function()
    -- Use typing delay to poke eventloop and enable correct neighbor pattern
    -- checks
    local wait = 1

    -- Shouldn't work in general
    type_keys(wait, 'a', '<')
    eq(get_lines(), { 'a<' })

    -- Should work only within specified pattern
    set_lines({})
    type_keys(wait, ' a', '<Left>', '<')
    eq(get_lines(), { ' <>a' })
  end

  validate_action('i', test)
end

T['map()/map_buf()']['respect `register` of `pair_info` argument'] = function(fun_name)
  apply_map(fun_name, [['i', '<', { action = 'open', pair = '<>', register = { bs = true, cr = false } }]])

  validate_bs('i', '<>')
  validate_no('cr', '<>')
end

T['map()/map_buf()']['respect `opts` or `pair_info` argument'] = function(fun_name)
  -- Throws error because mapping `(` should already exist
  expect.error(
    function() apply_map(fun_name, [['i', '(', { action = 'open', pair = '()' }, { unique = true }]]) end,
    '[Mm]apping.*exists'
  )
end

T['map()/map_buf()']['create mappings for `<BS>` in new mode'] = function(fun_name)
  -- Should not override existing one
  child.cmd('cnoremap <BS> <Cmd>echo "Hello"<CR>')
  apply_map(fun_name, '"c", "<", { action = "open", pair = "<>" }')
  expect.match(child.cmd_capture('cmap <BS>'), 'echo "Hello"')
  child.cmd('cunmap <BS>')

  apply_map(fun_name, '"c", "<", { action = "open", pair = "<>" }')
  expect.match(child.cmd_capture('cmap <BS>'), 'MiniPairs%.bs')
  validate_bs('c', '<>')
end

T['map()/map_buf()']['create mappings for `<CR>` in new mode'] = function(fun_name)
  -- Should not override existing one
  child.cmd('inoremap <CR> <Cmd>echo "Hello"<CR>')
  apply_map(fun_name, '"i", "<", { action = "open", pair = "<>" }')
  expect.match(child.cmd_capture('imap <CR>'), 'echo "Hello"')
  child.cmd('iunmap <CR>')

  apply_map(fun_name, '"i", "<", { action = "open", pair = "<>" }')
  expect.match(child.cmd_capture('imap <CR>'), 'MiniPairs%.cr')
  validate_cr('<>')
end

local make_test_map = function(fun_name) apply_map(fun_name, [['i', '<', { action = 'open', pair = '<>' }]]) end

local has_test_map = function()
  validate_open('i', '<', '<>')
  validate_bs('i', '<>')
  validate_cr('<>')
end

local no_test_map = function()
  validate_no('open', 'i', '<', '<>')
  validate_no('bs', 'i', '<>')
  validate_no('cr', '<>')
end

T['unmap()/unmap_buf()'] = new_set({
  hooks = {
    pre_case = function()
      -- Allow switching between buffers with unsaved changes
      child.o.hidden = true
    end,
  },
  parametrize = { { 'unmap' }, { 'unmap_buf' } },
})

T['unmap()/unmap_buf()']['work'] = function(fun_name)
  make_test_map(fun_name)
  has_test_map()

  apply_unmap(fun_name, [['i', '<', '<>']])
  no_test_map()
end

T['unmap()/unmap_buf()']['delete mapping properly'] = function(fun_name)
  -- Set up two buffers
  local buffers = { cur = child.api.nvim_get_current_buf(), new = child.api.nvim_create_buf(true, false) }

  child.api.nvim_set_current_buf(buffers.cur)
  make_test_map(fun_name)
  has_test_map()
  child.api.nvim_set_current_buf(buffers.new)
  make_test_map(fun_name)
  has_test_map()

  child.api.nvim_set_current_buf(buffers.cur)
  apply_unmap(fun_name, [['i', '<', '<>']])
  no_test_map()

  child.api.nvim_set_current_buf(buffers.new)
  if fun_name == 'unmap_buf' then
    has_test_map()
  else
    no_test_map()
  end
end

T['unmap()/unmap_buf()']['respect `mode` argument'] = function(fun_name)
  apply_map(fun_name, [['c', '<', { action = 'open', pair = '<>' }]])
  validate_open('c', '<', '<>')
  validate_bs('c', '<>')

  apply_unmap(fun_name, [['c', '<', '<>']])
  validate_no('open', 'c', '<', '<>')
  validate_no('bs', 'c', '<>')
end

T['unmap()/unmap_buf()']['require explicit `pair` argument'] = function(fun_name)
  expect.error(function() apply_unmap(fun_name, [['i', '(']]) end, 'pair.*string')
end

T['unmap()/unmap_buf()']['allow empty string for `pair` argument to not unregister pair'] = function(fun_name)
  make_test_map(fun_name)
  has_test_map()

  apply_unmap(fun_name, [['i', '<', '']])
  validate_no('open', 'i', '<', '<>')
  validate_bs('i', '<>')
  validate_cr('<>')
end

T['unmap()/unmap_buf()']['work for already missing mapping'] = function(fun_name)
  expect.no_error(function() apply_unmap(fun_name, [['c', '%', '%%']]) end)
end

-- Integration tests ==========================================================
T['Open action'] = new_set()

T['Open action']['works'] = function()
  validate_open('i', '(', '()')
  validate_open('i', '[', '[]')
  validate_open('i', '{', '{}')

  -- There should be no side effects
  eq(child.o.lazyredraw, false)
end

T['Open action']['works with multibyte characters'] = function()
  -- Insert mode
  child.lua('MiniPairs.map("i", "ы", { action = "open", pair = "ы」" } )')
  type_keys('i', 'ы')
  eq(get_lines(), { 'ы」' })
  eq(get_cursor(), { 1, 2 })
  type_keys('ы')
  eq(get_lines(), { 'ыы」」' })
  eq(get_cursor(), { 1, 4 })

  -- - Should also work for `<BS>`
  type_keys('<BS>')
  eq(get_lines(), { 'ы」' })
  eq(get_cursor(), { 1, 2 })

  -- - Should also work for `<CR>`
  type_keys('<CR>')
  eq(get_lines(), { 'ы', '', '」' })
  eq(get_cursor(), { 2, 0 })

  -- Command-line mode
  child.ensure_normal_mode()
  child.lua('MiniPairs.map("c", "ы", { action = "open", pair = "ы」" } )')
  type_keys(':', 'ы')
  eq(child.fn.getcmdline(), 'ы」')
  eq(child.fn.getcmdpos(), 3)
  type_keys('ы')
  eq(child.fn.getcmdline(), 'ыы」」')
  eq(child.fn.getcmdpos(), 5)

  -- - Should also work for `<BS>`
  type_keys('<BS>')
  eq(child.fn.getcmdline(), 'ы」')
  eq(child.fn.getcmdpos(), 3)

  -- Omit testing Terminal mode in the hope that it is the same
end

T['Open action']['does not break undo sequence in Insert mode'] = function()
  type_keys('i', '((', '<Esc>')
  eq(get_lines(), { '(())' })
  eq(get_cursor(), { 1, 1 })

  type_keys('u')
  eq(get_lines(), { '' })
end

T['Open action']['respects neighbor pattern'] = function()
  validate_slash('(')
  validate_slash('[')
  validate_slash('{')
end

T['Open action']['is correctly initiated in `config.mappings`'] = function()
  child.api.nvim_del_keymap('i', '(')
  reload_module({ mappings = { ['('] = { action = 'open', pair = '()', neigh_pattern = '..' } } })
  validate_no('neigh_disable', [[\]], '(')
end

T['Open action']['works with `nvim_feedkeys()`'] = function()
  child.cmd('inoremap <C-j> <Cmd>call nvim_feedkeys("((", "", v:true)<CR>')
  type_keys('i', '<C-j>')
  eq(child.o.lazyredraw, false)
end

T['Open action']['respects `vim.{g,b}.minipairs_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    validate_disable(var_type, '(')
    validate_disable(var_type, '[')
    validate_disable(var_type, '{')
  end,
})

T['Close action'] = new_set()

T['Close action']['works'] = function()
  validate_open('i', ')', ')')
  validate_open('i', ']', ']')
  validate_open('i', '}', '}')
  validate_close('i', ')', '()')
  validate_close('i', ']', '[]')
  validate_close('i', '}', '{}')
end

T['Close action']['works with multibyte characters'] = function()
  -- Insert mode
  child.lua('MiniPairs.map("i", "」", { action = "close", pair = "ы」" } )')
  type_keys('i', 'ы', '」', '<Left>')
  eq(get_lines(), { 'ы」' })
  eq(get_cursor(), { 1, 2 })
  type_keys('」')
  eq(get_lines(), { 'ы」' })
  eq(get_cursor(), { 1, 5 })
  type_keys('」')
  eq(get_lines(), { 'ы」」' })
  eq(get_cursor(), { 1, 8 })

  -- - Should also work for `<BS>`
  type_keys('<Left>', '<Left>', '<BS>')
  eq(get_lines(), { '」' })
  eq(get_cursor(), { 1, 0 })

  -- - Should also work for `<CR>`
  type_keys('<C-v>', 'ы', '<CR>')
  eq(get_lines(), { 'ы', '', '」' })
  eq(get_cursor(), { 2, 0 })

  -- Command-line mode
  child.ensure_normal_mode()
  child.lua('MiniPairs.map("c", "」", { action = "close", pair = "ы」" } )')
  type_keys(':', 'ы', '」', '<Left>')
  eq(child.fn.getcmdline(), 'ы」')
  eq(child.fn.getcmdpos(), 3)
  type_keys('」')
  eq(child.fn.getcmdline(), 'ы」')
  eq(child.fn.getcmdpos(), 6)
  type_keys('」')
  eq(child.fn.getcmdline(), 'ы」」')
  eq(child.fn.getcmdpos(), 9)

  -- - Should also work for `<BS>`
  type_keys('<Left>', '<Left>', '<BS>')
  eq(child.fn.getcmdline(), '」')
  eq(child.fn.getcmdpos(), 1)

  -- Omit testing Terminal mode in the hope that it is the same
end

T['Close action']['does not break undo sequence in Insert mode'] = function()
  set_lines({ '(())' })
  set_cursor(1, 2)

  type_keys('i', ')) ', '<Esc>')
  type_keys('u')
  eq(get_lines(), { '(())' })
end

local validate_slash_close = function(key, pair)
  set_lines({ pair })
  set_cursor(1, 1)
  child.cmd('startinsert')

  -- Wait to poke eventloop to enable pattern check
  type_keys(1, [[\]], key)
  eq(get_lines(), { pair:sub(1, 1) .. [[\]] .. key .. pair:sub(2, 2) })
end

T['Close action']['respects neighbor pattern'] = function()
  validate_slash_close(')', '()')
  validate_slash_close(']', '[]')
  validate_slash_close('}', '{}')
end

T['Close action']['is correctly initiated in `config.mappings`'] = function()
  child.api.nvim_del_keymap('i', ')')
  reload_module({ mappings = { [')'] = { action = 'close', pair = '()', neigh_pattern = '..' } } })
  expect.error(function() validate_slash_close(')', '()') end)
end

T['Close action']['respects `vim.{g,b}.minipairs_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    validate_disable(var_type, ')')
    validate_disable(var_type, ']')
    validate_disable(var_type, '}')
  end,
})

T['Closeopen action'] = new_set()

T['Closeopen action']['works'] = function()
  validate_open('i', '"', '""')
  validate_open('i', "'", "''")
  validate_open('i', '`', '``')
  validate_close('i', '"', '""')
  validate_close('i', "'", "''")
  validate_close('i', '`', '``')
end

T['Closeopen action']['works with multibyte characters'] = function()
  -- Insert mode
  child.lua('MiniPairs.map("i", "」", { action = "closeopen", pair = "」」" } )')
  type_keys('i', '」')
  eq(get_lines(), { '」」' })
  eq(get_cursor(), { 1, 3 })
  type_keys('」')
  eq(get_lines(), { '」」' })
  eq(get_cursor(), { 1, 6 })
  type_keys('」')
  eq(get_lines(), { '」」」」' })
  eq(get_cursor(), { 1, 9 })

  -- - Should also work for `<BS>`
  type_keys('<BS>')
  eq(get_lines(), { '」」' })
  eq(get_cursor(), { 1, 6 })

  -- - Should also work for `<CR>`
  type_keys('<Left>', '<CR>')
  eq(get_lines(), { '」', '', '」' })
  eq(get_cursor(), { 2, 0 })

  -- Command-line mode
  child.ensure_normal_mode()
  child.lua('MiniPairs.map("c", "」", { action = "closeopen", pair = "」」" } )')
  type_keys(':', '」')
  eq(child.fn.getcmdline(), '」」')
  eq(child.fn.getcmdpos(), 4)
  type_keys('」')
  eq(child.fn.getcmdline(), '」」')
  eq(child.fn.getcmdpos(), 7)
  type_keys('」')
  eq(child.fn.getcmdline(), '」」」」')
  eq(child.fn.getcmdpos(), 10)

  -- - Should also work for `<BS>`
  type_keys('<BS>')
  eq(child.fn.getcmdline(), '」」')
  eq(child.fn.getcmdpos(), 7)

  -- Omit testing Terminal mode in the hope that it is the same
end

T['Closeopen action']['does not break undo sequence in Insert mode'] = function()
  -- Open
  set_lines({})

  type_keys('i', '""', '<Esc>')
  type_keys('u')
  eq(get_lines(), { '' })

  -- Close
  set_lines({ '""""' })
  set_cursor(1, 2)

  type_keys('i', '"" ', '<Esc>')
  type_keys('u')
  eq(get_lines(), { '""""' })
end

T['Closeopen action']['respects neighbor pattern'] = function()
  validate_slash('"')
  validate_slash("'")
  validate_slash('`')

  validate_neigh_disable('a ', "'")

  validate_no('neigh_disable', '__', '"')
  validate_no('neigh_disable', '__', "'")
  validate_no('neigh_disable', '__', '`')
end

T['Closeopen action']['is correctly initiated in `config.mappings`'] = function()
  child.api.nvim_del_keymap('i', '"')
  reload_module({ mappings = { ['"'] = { action = 'closeopen', pair = '""', neigh_pattern = '..' } } })
  validate_no('neigh_disable', [[\]], '"')
end

T['Closeopen action']['respects `vim.{g,b}.minipairs_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    validate_disable(var_type, '"')
    validate_disable(var_type, "'")
    validate_disable(var_type, '`')
  end,
})

T['<BS> action'] = new_set()

T['<BS> action']['works'] = function()
  validate_bs('i', '()')
  validate_bs('i', '[]')
  validate_bs('i', '{}')
  validate_bs('i', '""')
  validate_bs('i', "''")
  validate_bs('i', '``')

  -- Should work in Command-line with redraw
  child.set_size(10, 12)
  reload_module({ modes = { command = true } })
  type_keys(':aa()bb', '<Left>', '<Left>', '<Left>')
  type_keys('<BS>')
  child.expect_screenshot()
end

T['<BS> action']['respects `key` argument'] = function()
  child.lua([[
    local map_bs = function(lhs, rhs)
      vim.keymap.set('i', lhs, rhs, { expr = true, replace_keycodes = false })
    end

    map_bs('<C-h>', 'v:lua.MiniPairs.bs()')
    map_bs('<C-w>', 'v:lua.MiniPairs.bs("\23")')
    map_bs('<C-u>', 'v:lua.MiniPairs.bs("\21")')
  ]])
  local validate_key = function(key, line_before, col_before, line_after, col_after)
    child.ensure_normal_mode()
    set_lines({ line_before })
    set_cursor(1, col_before)
    type_keys('a')

    type_keys(key)

    eq(child.api.nvim_get_mode().mode, 'i')
    eq(get_lines(), { line_after })
    eq(get_cursor(), { 1, col_after })
  end

  -- `<C-h>`
  validate_key('<C-h>', 'aa(b)', 3, 'aa()', 3)
  validate_key('<C-h>', 'aa()', 2, 'aa', 2)
  validate_key('<C-h>', 'aa', 1, 'a', 1)

  -- `<C-w>`
  validate_key('<C-w>', 'aa(bb)', 4, 'aa()', 3)
  validate_key('<C-w>', 'aa()', 2, 'aa', 2)
  validate_key('<C-w>', 'aa', 1, '', 0)

  -- `<C-u>`
  validate_key('<C-u>', 'aa()cc', 1, '()cc', 0)
  validate_key('<C-u>', 'aa()cc', 2, 'cc', 0)
  validate_key('<C-u>', 'aa()cc', 5, '', 0)
end

T['<BS> action']['does not break undo sequence in Insert mode'] = function()
  set_lines({ 'a()' })
  set_cursor(1, 2)
  child.cmd('startinsert')

  type_keys('<BS><BS>', '<Esc>')
  eq(get_lines(), { '' })
  type_keys('u')
  eq(get_lines(), { 'a()' })
end

local reload_unregister_bs = function()
  child.api.nvim_del_keymap('i', '<BS>')
  reload_module({
    mappings = {
      ['('] = { register = { bs = false } },
      ['['] = { register = { bs = false } },
      ['{'] = { register = { bs = false } },
      [')'] = { register = { bs = false } },
      [']'] = { register = { bs = false } },
      ['}'] = { register = { bs = false } },
      ['"'] = { register = { bs = false } },
      ["'"] = { register = { bs = false } },
      ['`'] = { register = { bs = false } },
    },
  })
end

T['<BS> action']['does not create mapping if nothing is registered in `config.mappings`'] = function()
  expect.match(child.cmd_capture('imap <BS>'), 'MiniPairs%.bs')
  reload_unregister_bs()
  expect.match(child.cmd_capture('imap <BS>'), 'No mapping found')
end

T['<BS> action']['works as normal if nothing is registered'] = function()
  reload_unregister_bs()

  set_lines({ '()' })
  set_cursor(1, 1)
  child.cmd('startinsert')

  type_keys('<BS>')
  eq(get_lines(), { ')' })
  eq(get_cursor(), { 1, 0 })
end

T['<BS> action']['respects `vim.{g,b}.minipairs_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minipairs_disable = true
    set_lines({ '()' })
    set_cursor(1, 1)
    child.cmd('startinsert')
    type_keys('<BS>')
    eq(get_lines(), { ')' })
  end,
})

T['<CR> action'] = new_set()

T['<CR> action']['works'] = function()
  validate_cr('()')
  validate_cr('[]')
  validate_cr('{}')
  validate_no('cr', '""')
  validate_no('cr', "''")
  validate_no('cr', '``')

  -- There should be no side effects
  eq(child.o.eventignore, '')
  eq(child.o.lazyredraw, false)
end

T['<CR> action']['respects `key` argument'] = function()
  child.api.nvim_set_keymap('i', '<C-u>', 'v:lua.MiniPairs.cr("\21")', { noremap = true, expr = true })

  local validate_key = function(key, lines_before, cursor_before, lines_after, cursor_after)
    child.ensure_normal_mode()
    set_lines(lines_before)
    set_cursor(unpack(cursor_before))
    type_keys('a')

    type_keys(key)

    eq(child.api.nvim_get_mode().mode, 'i')
    eq(get_lines(), lines_after)
    eq(get_cursor(), cursor_after)
  end

  -- `<C-u>`
  validate_key('<C-u>', { 'aa()cc' }, { 1, 1 }, { '()cc' }, { 1, 0 })
  validate_key('<C-u>', { 'aa()cc' }, { 1, 2 }, { '', ')cc' }, { 1, 0 })
  validate_key('<C-u>', { 'aa()cc' }, { 1, 5 }, { '' }, { 1, 0 })
end

T['<CR> action']['does not break undo sequence in Insert mode'] = function()
  set_lines({ '()' })
  set_cursor(1, 1)
  child.cmd('startinsert')

  type_keys('<CR>', 'a', '<Esc>')
  type_keys('u')
  eq(get_lines(), { '()' })
end

T['<CR> action']['reindents the line'] = function()
  child.bo.cindent = true
  set_lines({ '{}' })
  set_cursor(1, 1)
  child.cmd('startinsert')

  type_keys('<CR>')
  eq(get_lines(), { '{', '\t', '}' })
end

T['<CR> action']['does not trigger mode change'] = function()
  child.o.eventignore = 'CursorHold'
  set_lines({ '{}' })
  set_cursor(1, 1)
  child.cmd('startinsert')
  child.cmd('au InsertLeave,InsertLeavePre,InsertEnter,TextChanged,ModeChanged * lua _G.n = (_G.n or 0) + 1')
  type_keys('<CR>')
  eq(child.lua_get('_G.n'), vim.NIL)
  eq(child.o.eventignore, 'CursorHold')
end

local reload_unregister_cr = function()
  child.api.nvim_del_keymap('i', '<CR>')
  reload_module({
    mappings = {
      ['('] = { register = { cr = false } },
      ['['] = { register = { cr = false } },
      ['{'] = { register = { cr = false } },
      [')'] = { register = { cr = false } },
      [']'] = { register = { cr = false } },
      ['}'] = { register = { cr = false } },
      ['"'] = { register = { cr = false } },
      ["'"] = { register = { cr = false } },
      ['`'] = { register = { cr = false } },
    },
  })
end

T['<CR> action']['does not create mapping if nothing is registered in `config.mappings`'] = function()
  expect.match(child.cmd_capture('imap <CR>'), 'MiniPairs%.cr')
  reload_unregister_cr()
  expect.match(child.cmd_capture('imap <CR>'), 'No mapping found')
end

T['<CR> action']['works as normal if nothing is registered'] = function()
  reload_unregister_cr()

  set_lines({ '()' })
  set_cursor(1, 1)
  child.cmd('startinsert')

  type_keys('<CR>')
  eq(get_lines(), { '(', ')' })
  eq(get_cursor(), { 2, 0 })
end

T['<CR> action']['works with `feedkeys()`'] = function()
  child.cmd('inoremap <C-j> <Cmd>call nvim_feedkeys("(\\r(\\r", "", v:true)<CR>')
  type_keys('i', '<C-j>')
  eq(child.o.eventignore, '')
  eq(child.o.lazyredraw, false)
end

T['<CR> action']['respects `vim.{g,b}.minipairs_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minipairs_disable = true
    set_lines({ '()' })
    set_cursor(1, 1)
    child.cmd('startinsert')
    type_keys('<CR>')
    eq(get_lines(), { '(', ')' })
  end,
})

return T
