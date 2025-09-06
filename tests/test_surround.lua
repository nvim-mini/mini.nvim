local helpers = dofile('tests/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('surround', config) end
local unload_module = function() child.mini_unload('surround') end
local reload_module = function(config) unload_module(); load_module(config) end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
local sleep = function(ms) helpers.sleep(ms, child) end
--stylua: ignore end

-- Make helpers
local clear_messages = function() child.cmd('messages clear') end

local get_latest_message = function() return child.cmd_capture('1messages') end

local has_message_about_not_found = function(char, n_lines, search_method, n_times)
  n_lines = n_lines or 20
  search_method = search_method or 'cover'
  n_times = n_times or 1
  local msg = string.format(
    [[(mini.surround) No surrounding %s found within %s lines and `config.search_method = '%s'`.]],
    vim.inspect((n_times > 1 and n_times or '') .. char),
    n_lines,
    search_method
  )
  eq(get_latest_message(), msg)
end

-- Custom validators
local validate_edit = function(before_lines, before_cursor, after_lines, after_cursor, test_action, ...)
  child.ensure_normal_mode()

  set_lines(before_lines)
  set_cursor(unpack(before_cursor))

  test_action(...)

  eq(get_lines(), after_lines)
  eq(get_cursor(), after_cursor)
end

local validate_edit1d = function(before_line, before_column, after_line, after_column, test_action, ...)
  validate_edit({ before_line }, { 1, before_column }, { after_line }, { 1, after_column }, test_action, ...)
end

local validate_find = function(lines, start_pos, positions, f, ...)
  set_lines(lines)
  set_cursor(unpack(start_pos))

  for _, pos in ipairs(positions) do
    f(...)
    eq(get_lines(), lines)
    eq(get_cursor(), pos)
  end
end

local validate_no_find = function(lines, start_pos, f, ...)
  set_lines(lines)
  set_cursor(unpack(start_pos))
  f(...)
  eq(get_cursor(), start_pos)
end

-- Time constants
local default_highlight_duraion = 500
local helper_message_delay = 1000
local small_time = helpers.get_time_const(10)

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      load_module()

      -- Make all showed messages full width
      child.o.cmdheight = 10
    end,
    post_once = child.stop,
  },
  n_retry = helpers.get_n_retry(2),
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  -- Global variable
  eq(child.lua_get('type(_G.MiniSurround)'), 'table')

  -- Autocommand group
  eq(child.fn.exists('#MiniSurround'), 1)

  -- Highlight groups
  child.cmd('hi clear')
  load_module()
  expect.match(child.cmd_capture('hi MiniSurround'), 'links to IncSearch')
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniSurround.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniSurround.config.' .. field), value) end

  -- Check default values
  expect_config('custom_surroundings', vim.NIL)
  expect_config('n_lines', 20)
  expect_config('highlight_duration', 500)
  expect_config('mappings.add', 'sa')
  expect_config('mappings.delete', 'sd')
  expect_config('mappings.find', 'sf')
  expect_config('mappings.find_left', 'sF')
  expect_config('mappings.highlight', 'sh')
  expect_config('mappings.replace', 'sr')
  expect_config('mappings.suffix_last', 'l')
  expect_config('mappings.suffix_next', 'n')
  expect_config('respect_selection_type', false)
  expect_config('search_method', 'cover')
  expect_config('silent', false)
end

T['setup()']['respects `config` argument'] = function()
  unload_module()
  load_module({ n_lines = 10 })
  eq(child.lua_get('MiniSurround.config.n_lines'), 10)
end

T['setup()']['validates `config` argument'] = function()
  unload_module()

  local expect_config_error = function(config, name, target_type)
    expect.error(load_module, vim.pesc(name) .. '.*' .. vim.pesc(target_type), config)
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ custom_surroundings = 'a' }, 'custom_surroundings', 'table')
  expect_config_error({ highlight_duration = 'a' }, 'highlight_duration', 'number')
  expect_config_error({ mappings = 'a' }, 'mappings', 'table')
  expect_config_error({ mappings = { add = 1 } }, 'mappings.add', 'string')
  expect_config_error({ mappings = { delete = 1 } }, 'mappings.delete', 'string')
  expect_config_error({ mappings = { find = 1 } }, 'mappings.find', 'string')
  expect_config_error({ mappings = { find_left = 1 } }, 'mappings.find_left', 'string')
  expect_config_error({ mappings = { highlight = 1 } }, 'mappings.highlight', 'string')
  expect_config_error({ mappings = { replace = 1 } }, 'mappings.replace', 'string')
  expect_config_error({ mappings = { suffix_last = 1 } }, 'mappings.suffix_last', 'string')
  expect_config_error({ mappings = { suffix_next = 1 } }, 'mappings.suffix_next', 'string')
  expect_config_error({ n_lines = 'a' }, 'n_lines', 'number')
  expect_config_error({ respect_selection_type = 1 }, 'respect_selection_type', 'boolean')
  expect_config_error({ search_method = 1 }, 'search_method', 'one of')
  expect_config_error({ silent = 1 }, 'silent', 'boolean')
end

T['setup()']['ensures colors'] = function()
  child.cmd('colorscheme default')
  expect.match(child.cmd_capture('hi MiniSurround'), 'links to IncSearch')
end

T['setup()']['properly handles `config.mappings`'] = function()
  local has_map = function(lhs, pattern) return child.cmd_capture('nmap ' .. lhs):find(pattern) ~= nil end

  -- Regular mappings
  eq(has_map('sa', 'surround'), true)

  unload_module()
  child.api.nvim_del_keymap('n', 'sa')

  -- Supplying empty string should mean "don't create keymap"
  load_module({ mappings = { add = '' } })
  eq(has_map('sa', 'surround'), false)

  -- Extended mappings
  eq(has_map('sdl', 'previous'), true)
  eq(has_map('sdn', 'next'), true)

  unload_module()
  child.api.nvim_del_keymap('n', 'sd')
  child.api.nvim_del_keymap('n', 'sdl')
  child.api.nvim_del_keymap('n', 'sdn')
  child.api.nvim_del_keymap('n', 'srl')
  child.api.nvim_del_keymap('n', 'srn')

  load_module({ mappings = { delete = '', suffix_last = '' } })
  eq(has_map('sdl', 'previous'), false)
  eq(has_map('sdn', 'next'), false)
  eq(has_map('srl', 'previous'), false)
  eq(has_map('srn', 'next'), true)
end

T['update_n_lines()'] = new_set({
  hooks = {
    pre_case = function() child.lua('vim.keymap.set("n", "sn", "<Cmd>lua MiniSurround.update_n_lines()<CR>")') end,
  },
})

T['update_n_lines()']['works'] = function()
  local cur_n_lines = child.lua_get('MiniSurround.config.n_lines')

  -- Should ask for input, display prompt text and current value of `n_lines`
  type_keys('sn')
  eq(child.fn.mode(), 'c')
  eq(child.fn.getcmdline(), tostring(cur_n_lines))

  type_keys('0', '<CR>')
  eq(child.lua_get('MiniSurround.config.n_lines'), 10 * cur_n_lines)
end

T['update_n_lines()']['allows cancelling with `<Esc> and <C-c>`'] = function()
  local validate_cancel = function(key)
    child.ensure_normal_mode()
    local cur_n_lines = child.lua_get('MiniSurround.config.n_lines')

    type_keys('sn')
    eq(child.fn.mode(), 'c')

    type_keys(key)
    eq(child.fn.mode(), 'n')
    eq(child.lua_get('MiniSurround.config.n_lines'), cur_n_lines)
  end

  validate_cancel('<Esc>')
  validate_cancel('<C-c>')
end

T['gen_spec'] = new_set()

T['gen_spec']['input'] = new_set()

T['gen_spec']['input']['treesitter()'] = new_set({
  hooks = {
    pre_case = function()
      -- Mock tree-sitter queries
      child.cmd('noautocmd set rtp+=tests/mock-treesitter')

      -- Start editing reference file
      child.cmd('edit tests/mock-treesitter/lua-file.lua')
      child.lua('vim.treesitter.start()')

      -- Define "function definition" surrounding
      child.lua([[MiniSurround.config.custom_surroundings = {
        F = { input = MiniSurround.gen_spec.input.treesitter({ outer = '@function.outer', inner = '@function.inner' }) }
      }]])
    end,
  },
})

T['gen_spec']['input']['treesitter()']['works'] = function()
  local lines = get_lines()

  -- Should prefer range from metadata instead of node itself. This is useful,
  -- for example, with `#offset!` directive to create more precise captures.
  validate_find(lines, { 9, 0 }, { { 10, 12 }, { 11, 2 }, { 7, 6 }, { 8, 1 } }, type_keys, 'sf', 'F')
  validate_no_find(lines, { 13, 0 }, type_keys, 'sf', 'F')

  -- Should prefer match on current line over multiline covering
  child.lua('MiniSurround.config.search_method = "cover_or_next"')
  validate_find(lines, { 4, 0 }, { { 4, 9 }, { 4, 19 }, { 4, 34 }, { 4, 37 } }, type_keys, 'sf', 'F')
end

T['gen_spec']['input']['treesitter()']['works with empty region'] = function()
  child.lua([[MiniSurround.config.custom_surroundings = {
    o = { input = MiniSurround.gen_spec.input.treesitter({ outer = '@return.outer', inner = '@return.inner' }) },
  }]])
  local lines = get_lines()

  -- Delete
  set_lines(lines)
  set_cursor(10, 2)
  type_keys('sd', 'o')
  eq(get_lines()[10], '  true')

  -- Replace
  set_lines(lines)
  set_cursor(10, 2)
  type_keys('sr', 'o', '>')
  eq(get_lines()[10], '  <true>')

  -- Find
  validate_find(lines, { 10, 2 }, { { 10, 8 }, { 10, 2 } }, type_keys, 'sf', 'o')

  -- Highlight
  child.set_size(15, 40)
  child.o.cmdheight = 1
  set_lines(lines)
  set_cursor(10, 2)
  type_keys('sh', 'o')
  -- It highlights `return` differently from other places
  if child.fn.has('nvim-0.11') == 1 then child.expect_screenshot() end

  -- Edge case for empty region on end of last line
  set_lines(lines)
  set_cursor(13, 0)
  type_keys('sd', 'o')
  eq(get_lines()[13], 'M')
end

T['gen_spec']['input']['treesitter()']['works with no inner captures'] = function()
  child.lua([[MiniSurround.config.custom_surroundings = {
    o = { input = MiniSurround.gen_spec.input.treesitter({ outer = '@return.outer', inner = '@string' }) },
  }]])
  local lines = get_lines()

  -- Delete
  set_lines(lines)
  set_cursor(10, 2)
  type_keys('sd', 'o')
  -- - Should treat the whole "outer" match as left surrounding with
  --   right surrounding being a single position right match edge.
  eq(get_lines()[10], '  ')

  -- Replace
  set_lines(lines)
  set_cursor(10, 2)
  type_keys('sr', 'o', '>')
  eq(get_lines()[10], '  <>')

  -- Find
  validate_find(lines, { 10, 2 }, { { 10, 12 }, { 10, 2 } }, type_keys, 'sf', 'o')
end

T['gen_spec']['input']['treesitter()']['respects `opts.use_nvim_treesitter`'] = function()
  child.lua([[MiniSurround.config.custom_surroundings = {
    F = { input = MiniSurround.gen_spec.input.treesitter({ outer = '@function.outer', inner = '@function.inner' }) },
    o = { input = MiniSurround.gen_spec.input.treesitter({ outer = '@plugin_other.outer', inner = '@plugin_other.inner' }) },
    O = {
      input = MiniSurround.gen_spec.input.treesitter(
        { outer = '@plugin_other.outer', inner = '@plugin_other.inner' },
        { use_nvim_treesitter = true }
      )
    },
  }]])
  local lines = get_lines()

  -- By default it should be `false`
  validate_find(lines, { 9, 0 }, { { 10, 12 }, { 11, 2 }, { 7, 6 }, { 8, 1 } }, type_keys, 'sf', 'F')
  validate_no_find(lines, { 1, 0 }, type_keys, 'sf', 'o')
  validate_no_find(lines, { 1, 0 }, type_keys, 'sf', 'O')

  child.cmd('noautocmd set rtp+=tests/dir-surround/mock-nvim-treesitter')
  -- Should prefer range from metadata instead of node itself. This is useful,
  -- for example, with `#offset!` directive to create more precise captures.
  validate_find(lines, { 9, 0 }, { { 10, 12 }, { 11, 2 }, { 7, 6 }, { 8, 1 } }, type_keys, 'sf', 'F')
  validate_no_find(lines, { 1, 0 }, type_keys, 'sf', 'o')
  validate_find(lines, { 1, 0 }, { { 1, 5 }, { 1, 0 } }, type_keys, 'sf', 'O')
end

T['gen_spec']['input']['treesitter()']['works with directives'] = function()
  child.lua([[MiniSurround.config.custom_surroundings = {
    S = { input = MiniSurround.gen_spec.input.treesitter({ outer = '@string', inner = '@string_offset' }) }
  }]])
  local lines = get_lines()
  validate_find(lines, { 9, 9 }, { { 9, 16 }, { 9, 17 }, { 9, 8 }, { 9, 16 } }, type_keys, 'sf', 'S')
end

T['gen_spec']['input']['treesitter()']['works with quantified captures'] = function()
  if child.fn.has('nvim-0.10') == 0 then
    MiniTest.skip('`Query:iter_matches()` returning several nodes requires Neovim>=0.10')
  end

  child.lua([[MiniSurround.config.custom_surroundings = {
    P = { input = MiniSurround.gen_spec.input.treesitter({ outer = '@parameter.outer', inner = '@parameter.inner' }) }
  }]])

  local lines = get_lines()
  local validate = function(col, ref_line)
    set_lines(lines)
    set_cursor(3, col)
    type_keys('sr', 'P', '>')
    eq(get_lines()[3], ref_line)
  end
  validate(13, 'function M.a(<u> vv, www)')
  validate(16, 'function M.a(u<vv>, www)')
  validate(21, 'function M.a(u, vv<www>)')
end

T['gen_spec']['input']['treesitter()']['respects plugin options'] = function()
  local lines = get_lines()

  -- `opts.n_lines`
  child.lua('MiniSurround.config.n_lines = 0')
  validate_no_find(lines, { 1, 0 }, type_keys, 'sf', 'F')

  -- `opts.search_method`
  child.lua('MiniSurround.config.n_lines = 50')
  child.lua('MiniSurround.config.search_method = "next"')
  validate_no_find(lines, { 9, 0 }, type_keys, 'sf', 'F')
end

T['gen_spec']['input']['treesitter()']['validates `captures` argument'] = function()
  local validate = function(args)
    expect.error(function() child.lua([[MiniSurround.gen_spec.input.treesitter(...)]], { args }) end, 'captures')
  end

  validate('a')
  validate({})
  -- Each `outer` and `inner` should be a string starting with '@'
  validate({ outer = 1 })
  validate({ outer = 'function.outer' })
  validate({ inner = 1 })
  validate({ inner = 'function.inner' })
end

T['gen_spec']['input']['treesitter()']['validates builtin treesitter presence'] = function()
  child.cmdheight = 40

  -- Query
  child.bo.filetype = 'vim'
  expect.error(
    function() type_keys('sd', 'F', '<CR>') end,
    '%(mini%.surround%) Can not get query for buffer 1 and language "vim"%.'
  )

  -- Parser
  child.bo.filetype = 'aaa'
  expect.error(
    function() type_keys('sd', 'F', '<CR>') end,
    '%(mini%.surround%) Can not get parser for buffer 1 and language "aaa"%.'
  )

  -- - Should respect registered language for a filetype
  child.lua('vim.treesitter.language.register("my_aaa", "aaa")')
  expect.error(
    function() type_keys('sd', 'F', '<CR>') end,
    '%(mini%.surround%) Can not get parser for buffer 1 and language "my_aaa"%.'
  )
end

-- Integration tests ==========================================================
-- Operators ------------------------------------------------------------------
T['Add surrounding'] = new_set()

T['Add surrounding']['works in Normal mode with dot-repeat'] = function()
  validate_edit({ 'aaa' }, { 1, 0 }, { '(aaa)' }, { 1, 1 }, type_keys, 'sa', 'iw', ')')
  validate_edit({ ' aaa ' }, { 1, 1 }, { ' (aaa) ' }, { 1, 2 }, type_keys, 'sa', 'iw', ')')

  -- Allows immediate dot-repeat
  type_keys('.')
  eq(get_lines(), { ' ((aaa)) ' })
  eq(get_cursor(), { 1, 3 })

  -- Allows not immediate dot-repeat
  set_lines({ 'aaa bbb' })
  set_cursor(1, 5)
  type_keys('.')
  eq(get_lines(), { 'aaa (bbb)' })
end

T['Add surrounding']['works in Visual mode without dot-repeat'] = function()
  -- Reset dot-repeat
  set_lines({ ' aaa ' })
  type_keys('dd')

  validate_edit({ ' aaa ' }, { 1, 1 }, { ' (aaa) ' }, { 1, 2 }, type_keys, 'viw', 'sa', ')')
  eq(child.fn.mode(), 'n')

  -- Does not allow dot-repeat. Should do `dd`.
  type_keys('.')
  eq(get_lines(), { '' })
end

T['Add surrounding']['works in line and block Visual mode'] = function()
  validate_edit({ 'aaa' }, { 1, 0 }, { '(aaa)' }, { 1, 1 }, type_keys, 'V', 'sa', ')')

  validate_edit({ 'aaa', 'bbb' }, { 1, 0 }, { '(aaa', 'bbb)' }, { 1, 1 }, type_keys, '<C-v>j$', 'sa', ')')
end

--stylua: ignore
T['Add surrounding']['respects `config.respect_selection_type` in linewise mode'] = function()
  child.lua('MiniSurround.config.respect_selection_type = true')

  local validate = function(before_lines, before_cursor, after_lines, after_cursor, selection_keys)
    validate_edit(before_lines, before_cursor, after_lines, after_cursor, type_keys, selection_keys, 'sa', ')')
  end

  -- General test in Visual mode
  validate({ 'aaa' }, { 1, 0 }, { '(', '\taaa', ')' }, { 2, 1 }, 'V')

  -- Correctly computes indentation
  validate({ 'aaa',   ' bbb', '  ccc' }, { 2, 0 }, { 'aaa', ' (',      '\t bbb', '\t  ccc', ' )' },  { 3, 2 }, 'Vj')
  validate({ ' aaa',  '',     ' bbb' },  { 1, 0 }, { ' (',  '\t aaa',  '',       '\t bbb',  ' )' },  { 2, 2 }, 'V2j')
  validate({ '  aaa', ' ',    '  bbb' }, { 1, 0 }, { '  (', '\t  aaa', '\t ',    '\t  bbb', '  )' }, { 2, 3 }, 'V2j')

  -- Handles empty/blank lines
  validate({ '  aaa', '', ' ', '  bbb' }, { 1, 0 }, { '  (', '\t  aaa', '', '\t ', '\t  bbb', '  )' }, { 2, 3 }, 'V3j')

  validate({ '',  '  aaa', '' },  { 1, 0 }, { '  (', '',    '\t  aaa', '',    '  )' }, { 2, 0 }, 'V2j')
  validate({ ' ', '  aaa', ' ' }, { 1, 0 }, { '  (', '\t ', '\t  aaa', '\t ', '  )' }, { 2, 1 }, 'V2j')

  -- Doesn't produce messages
  validate({ 'aa', 'bb', 'cc' }, { 1, 0 }, { '(', '\taa', '\tbb', '\tcc', ')' }, { 2, 1 }, 'Vip')
  eq(child.cmd_capture('1messages'), '')

  -- Works with different surroundings
  validate_edit({ 'aaa' }, { 1, 0 }, { 'ff(', '\taaa', ')' }, { 2, 1 }, type_keys, 'V', 'sa', 'f', 'ff<CR>')

  -- General test in Operator-pending mode
  validate_edit({ 'aaa' }, { 1, 0 }, { '(', '\taaa', ')' }, { 2, 1 }, type_keys, 'sa', 'ip', ')')

  -- Respects `expandtab`
  child.o.expandtab = true
  child.o.shiftwidth = 3
  validate({ 'aaa' }, { 1, 0 }, { '(', '   aaa', ')' }, { 2, 3 }, 'V')
end

--stylua: ignore
T['Add surrounding']['respects `config.respect_selection_type` in blockwise mode'] = function()
  -- NOTE: this doesn't work with mix of multibyte and normal characters,
  -- as well as outside of text lines.
  child.lua('MiniSurround.config.respect_selection_type = true')

  local validate = function(before_lines, before_cursor, after_lines, after_cursor, selection_keys)
    validate_edit(before_lines, before_cursor, after_lines, after_cursor, type_keys, selection_keys, 'sa', ')')
  end

  -- General test in Visual mode
  validate({ 'aaa', 'bbb' }, { 1, 1 }, { 'a(a)a', 'b(b)b' }, { 1, 2 }, '<C-v>j')
  validate({ 'aaaa', 'bbbb' }, { 1, 1 }, { 'a(aa)a', 'b(bb)b' }, { 1, 2 }, '<C-v>jl')

  -- Works on single line
  validate({ 'aaaa' }, { 1, 1 }, { 'a(aa)a' }, { 1, 2 }, '<C-v>l')

  -- Works when selection is created in different directions
  validate({ 'aaaa', 'bbbb' }, { 1, 2 }, { 'a(aa)a', 'b(bb)b' }, { 1, 2 }, '<C-v>jh')
  validate({ 'aaaa', 'bbbb' }, { 2, 1 }, { 'a(aa)a', 'b(bb)b' }, { 1, 2 }, '<C-v>kl')
  validate({ 'aaaa', 'bbbb' }, { 2, 2 }, { 'a(aa)a', 'b(bb)b' }, { 1, 2 }, '<C-v>kh')

  -- Works with different surroundings
  validate_edit({ 'aaa', 'bbb' }, { 1, 1 }, { 'aff(a)a', 'bff(b)b' }, { 1, 4 }, type_keys, '<C-v>j', 'sa', 'f', 'ff<CR>')

  -- General test in Operator-pending mode
  set_lines({ 'aaaaa', 'bbbbb' })

  -- - Create mark to be able to perform non-trivial movement
  set_cursor(2, 3)
  type_keys('ma')

  set_cursor(1, 1)
  type_keys('sa', '<C-v>', '`a', ')')
  -- - As motion is end-exclusive, it registers end mark one column short.
  eq(get_lines(), { 'a(aa)aa', 'b(bb)bb' })
  eq(get_cursor(), { 1, 2 })
end

T['Add surrounding']['places cursor to the right of left surrounding'] = function()
  local f = function(surrounding, visual_key)
    if visual_key == nil then
      type_keys('sa', surrounding)
    else
      type_keys(visual_key, surrounding, 'sa')
    end
    type_keys('f', 'myfunc', '<CR>')
  end

  -- Same line
  validate_edit({ 'aaa' }, { 1, 0 }, { 'myfunc(aaa)' }, { 1, 7 }, f, 'iw')
  validate_edit({ 'aaa' }, { 1, 0 }, { 'myfunc(aaa)' }, { 1, 7 }, f, 'iw', 'v')
  validate_edit({ 'aaa' }, { 1, 0 }, { 'myfunc(aaa)' }, { 1, 7 }, f, '', 'V')

  -- Not the same line
  validate_edit({ 'aaa', 'bbb', 'ccc' }, { 2, 0 }, { 'myfunc(aaa', 'bbb', 'ccc)' }, { 1, 7 }, f, 'ip')
  validate_edit({ 'aaa', 'bbb', 'ccc' }, { 2, 0 }, { 'myfunc(aaa', 'bbb', 'ccc)' }, { 1, 7 }, f, 'ip', 'v')
  validate_edit({ 'aaa', 'bbb', 'ccc' }, { 2, 0 }, { 'myfunc(aaa', 'bbb', 'ccc)' }, { 1, 7 }, f, 'ip', 'V')
end

T['Add surrounding']['prompts helper message after one idle second'] = function()
  child.set_size(5, 70)
  child.o.cmdheight = 1

  set_lines({ ' aaa ' })
  set_cursor(1, 1)

  -- Execute one time to test if 'needs help message' flag is set per call
  type_keys('sa', 'iw', ')')
  sleep(0.1 * helper_message_delay)

  type_keys('sa', 'iw')
  sleep(helper_message_delay + small_time)

  -- Should show helper message without adding it to `:messages` and causing
  -- hit-enter-prompt
  eq(get_latest_message(), '')
  child.expect_screenshot()

  -- Should clear afterwards
  type_keys(')')
  child.expect_screenshot()
end

T['Add surrounding']['works with multibyte characters'] = function()
  local f = function() type_keys('sa', 'iw', ')') end

  validate_edit({ '  ыыы  ' }, { 1, 2 }, { '  (ыыы)  ' }, { 1, 3 }, f)
  validate_edit({ 'ыыы ttt' }, { 1, 2 }, { '(ыыы) ttt' }, { 1, 1 }, f)
  validate_edit({ 'ttt ыыы' }, { 1, 4 }, { 'ttt (ыыы)' }, { 1, 5 }, f)

  -- Test 4-byte characters (might be a cause of incorrect marks retrieval)
  validate_edit({ '🬗 🬗 🬗 🬗 🬗' }, { 1, 20 }, { '🬗 🬗 🬗 🬗 (🬗)' }, { 1, 21 }, f)
end

T['Add surrounding']['works on whole line'] = function()
  -- Should ignore both indent (leading whitespace) at start line and trailing
  -- whitespace and end line. Should work with both tabs and spaces.
  validate_edit({ ' \t aaa\t ', '' }, { 1, 0 }, { ' \t (aaa)\t ', '' }, { 1, 4 }, type_keys, 'sa', '_', ')')
  validate_edit({ ' \t aaa\t ', '' }, { 1, 0 }, { ' \t (aaa)\t ', '' }, { 1, 4 }, type_keys, 'V', 'sa', ')')
end

T['Add surrounding']['works on multiple lines'] = function()
  local f = function() type_keys('sa', 'ap', ')') end
  local f_vis = function() type_keys('Vap', 'sa', ')') end

  -- Should ignore both indent (leading whitespace) at start line and trailing
  -- whitespace and end line. Should work with both tabs and spaces.
  validate_edit({ ' \t aaa ', 'bbb', ' ccc\t ' }, { 1, 0 }, { ' \t (aaa ', 'bbb', ' ccc)\t ' }, { 1, 4 }, f)
  validate_edit({ ' \t aaa ', 'bbb', ' ccc\t ' }, { 1, 0 }, { ' \t (aaa ', 'bbb', ' ccc)\t ' }, { 1, 4 }, f_vis)
  validate_edit({ ' \t aaa ', '\t ' }, { 1, 0 }, { ' \t (aaa ', ')\t ' }, { 1, 4 }, f)
  validate_edit({ ' \t aaa ', '\t ' }, { 1, 0 }, { ' \t (aaa ', ')\t ' }, { 1, 4 }, f_vis)
end

T['Add surrounding']['works with multiline output surroundings'] = function()
  child.lua([[MiniSurround.config.custom_surroundings = {
    a = { output = { left = '\n(\n', right = '\n)\n' } }
  }]])
  local lines = { '  xxx' }
  validate_edit(lines, { 1, 3 }, { '  ', '(', 'xxx', ')', '' }, { 1, 1 }, type_keys, 'sa', 'iw', 'a')
end

T['Add surrounding']['works when using $ motion'] = function()
  -- It might not work because cursor column is outside of line width
  validate_edit({ 'aaa' }, { 1, 0 }, { '(aaa)' }, { 1, 1 }, type_keys, 'sa', '$', ')')
  validate_edit({ 'aaa' }, { 1, 0 }, { '(aaa)' }, { 1, 1 }, type_keys, 'v$', 'sa', ')')
end

T['Add surrounding']['allows cancelling with `<Esc> and <C-c>`'] = function()
  local validate_cancel = function(key)
    child.ensure_normal_mode()
    set_lines({ ' aaa ' })
    set_cursor(1, 1)

    -- Cancel before surrounding
    type_keys(1, 'sa', key)
    eq(get_lines(), { ' aaa ' })
    eq(get_cursor(), { 1, 1 })

    -- Cancel before output surrounding
    type_keys(1, 'sa', 'iw', key)
    eq(get_lines(), { ' aaa ' })
    eq(get_cursor(), { 1, 1 })
  end

  validate_cancel('<Esc>')
  validate_cancel('<C-c>')
end

T['Add surrounding']['works with different mapping'] = function()
  reload_module({ mappings = { add = 'SA' } })

  validate_edit({ 'aaa' }, { 1, 0 }, { '(aaa)' }, { 1, 1 }, type_keys, 'SA', 'iw', ')')
  child.api.nvim_del_keymap('n', 'SA')
end

T['Add surrounding']['respects two types of `[count]` in Normal mode'] = function()
  validate_edit1d('aa bb cc dd', 0, '((aa ))bb cc dd', 2, type_keys, '2sa', 'aw', ')')
  validate_edit1d('aa bb cc dd', 0, '(aa bb cc )dd', 1, type_keys, 'sa', '3aw', ')')
  validate_edit1d('aa bb cc dd', 0, '((aa bb cc ))dd', 2, type_keys, '2sa', '3aw', ')')

  -- Should work with dot-repeat
  validate_edit1d('aa bb cc dd ee', 0, '((aa bb ))((cc dd ))ee', 12, type_keys, '2sa2aw)', 'fc', '.')
end

T['Add surrounding']['respects `[count]` in Visual mode'] = function()
  validate_edit1d('aa bb cc dd', 0, '((aa ))bb cc dd', 2, type_keys, 'vaw', '2sa', ')')
  validate_edit1d('aa bb cc dd', 0, '((aa bb cc ))dd', 2, type_keys, 'v3aw', '2sa', ')')
end

T['Add surrounding']['handles `[count]` cache'] = function()
  set_lines({ 'aa bb' })
  set_cursor(1, 0)

  type_keys('2saiw)')
  eq(get_lines(), { '((aa)) bb' })

  set_cursor(1, 7)
  type_keys('viw', 'sa)')
  eq(get_lines(), { '((aa)) (bb)' })
end

T['Add surrounding']['works with `cmdheight=0`'] = function()
  child.set_size(7, 20)
  child.o.cmdheight = 0
  child.o.statusline = 'My statusline'
  set_lines({ 'aa bb' })
  type_keys('sa')
  child.expect_screenshot({ redraw = false })
  type_keys('iw')
  child.expect_screenshot({ redraw = false })
  type_keys(')')
  child.expect_screenshot({ redraw = false })
end

T['Add surrounding']['respects `selection=exclusive` option'] = function()
  child.o.selection = 'exclusive'
  local f = function() type_keys('v2l', 'sa', ')') end

  -- Regular case
  validate_edit({ ' aaa ' }, { 1, 1 }, { ' (aa)a ' }, { 1, 2 }, f)

  -- Multibyte characters
  validate_edit({ ' ыыы ' }, { 1, 1 }, { ' (ыы)ы ' }, { 1, 2 }, f)
end

T['Add surrounding']['respects `vim.{g,b}.minisurround_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minisurround_disable = true

    set_lines({ ' aaa ' })
    set_cursor(1, 1)

    -- It should ignore `sa` and start typing in Insert mode after `i`
    type_keys('sa', 'iw', ')')
    eq(get_lines(), { ' w)aaa ' })
    eq(get_cursor(), { 1, 3 })
  end,
})

T['Add surrounding']['respects `config.silent`'] = function()
  child.lua('MiniSurround.config.silent = true')
  child.set_size(10, 20)

  set_lines({ ' aaa ' })
  set_cursor(1, 1)

  -- It should not show helper message after one idle second
  type_keys('sa', 'iw')
  sleep(helper_message_delay + small_time)
  child.expect_screenshot()
end

T['Add surrounding']['respects `vim.b.minisurround_config`'] = function()
  child.b.minisurround_config = { custom_surroundings = { ['<'] = { output = { left = '>', right = '<' } } } }
  validate_edit({ 'aaa' }, { 1, 1 }, { '>aaa<' }, { 1, 1 }, type_keys, 'sa', 'iw', '<')
end

T['Delete surrounding'] = new_set()

T['Delete surrounding']['works with dot-repeat'] = function()
  validate_edit({ '(aaa)' }, { 1, 0 }, { 'aaa' }, { 1, 0 }, type_keys, 'sd', ')')
  validate_edit({ '(aaa)' }, { 1, 4 }, { 'aaa' }, { 1, 0 }, type_keys, 'sd', ')')
  validate_edit({ '(aaa)' }, { 1, 2 }, { 'aaa' }, { 1, 0 }, type_keys, 'sd', ')')

  -- Allows immediate dot-repeat
  set_lines({ '((aaa))' })
  set_cursor(1, 2)
  type_keys('sd', ')')
  type_keys('.')
  eq(get_lines(), { 'aaa' })
  eq(get_cursor(), { 1, 0 })

  -- Allows not immediate dot-repeat
  set_lines({ 'aaa (bbb)' })
  set_cursor(1, 5)
  type_keys('.')
  eq(get_lines(), { 'aaa bbb' })
end

--stylua: ignore
T['Delete surrounding']['respects `config.respect_selection_type` in linewise mode'] = function()
  child.lua('MiniSurround.config.respect_selection_type = true')

  local validate = function(before_lines, before_cursor, after_lines, after_cursor)
    validate_edit(before_lines, before_cursor, after_lines, after_cursor, type_keys, 'sd', ')')
  end

  -- General test
  validate({ '(', '\taaa', ')' }, { 2, 0 }, { 'aaa' }, { 1, 0 })

  -- Works when cursor is on any part of region
  validate({ '(', '\taaa', ')' }, { 1, 0 }, { 'aaa' }, { 1, 0 })
  validate({ '(', '\taaa', ')' }, { 3, 0 }, { 'aaa' }, { 1, 0 })

  -- Correctly applies when it should
  validate({ '(',   '\t\taaa', '\tbbb', ')' },   { 2, 2 }, { '\taaa', 'bbb' }, { 1, 1 })
  validate({ '  (', '\t\taaa', '\tbbb', ')  ' }, { 2, 2 }, { '\taaa', 'bbb' }, { 1, 1 })

  -- Correctly doesn't apply when it shouldn't
  validate({ 'aaa',  '  ()  ', 'bbb' },  { 2, 2 }, { 'aaa', '    ',  'bbb' }, { 2, 2 })
  validate({ 'aaa(', '\tbbb',  ')' },    { 2, 2 }, { 'aaa', '\tbbb', '' },    { 1, 2 })
  validate({ '(',    '\tbbb',  ')ccc' }, { 2, 2 }, { '',    '\tbbb', 'ccc' }, { 1, 0 })

  -- Correctly dedents
  validate({ '(', 'aaa', ')' }, { 2, 0 }, { 'aaa' }, { 1, 0 })

  -- Doesn't produce messages
  validate({ '(', '\taa', '\tbb', '\tcc', ')' }, { 2, 1 }, { 'aa', 'bb', 'cc' }, { 1, 0 })
  eq(child.cmd_capture('1messages'), '')

  child.o.shiftwidth = 3
  validate({ '(', '    aaa', ')' }, { 2, 0 }, { ' aaa' }, { 1, 1 })

  child.o.expandtab = true
  validate({ '(', '    aaa', ')' }, { 2, 0 }, { ' aaa' }, { 1, 1 })
end

T['Delete surrounding']['works in extended mappings'] = function()
  validate_edit1d('(aa) (bb) (cc)', 1, '(aa) bb (cc)', 5, type_keys, 'sdn', ')')
  validate_edit1d('(aa) (bb) (cc)', 1, '(aa) (bb) cc', 10, type_keys, '2sdn', ')')

  validate_edit1d('(aa) (bb) (cc)', 11, '(aa) bb (cc)', 5, type_keys, 'sdl', ')')
  validate_edit1d('(aa) (bb) (cc)', 11, 'aa (bb) (cc)', 0, type_keys, '2sdl', ')')

  -- Dot-repeat
  set_lines({ '(aa) (bb) (cc)' })
  set_cursor(1, 0)
  type_keys('sdn', ')')
  type_keys('.')
  eq(get_lines(), { '(aa) bb cc' })
  eq(get_cursor(), { 1, 8 })
end

T['Delete surrounding']['respects `config.n_lines`'] = function()
  reload_module({ n_lines = 2 })
  local lines = { '(', '', '', 'a', '', '', ')' }
  validate_edit(lines, { 4, 0 }, lines, { 4, 0 }, type_keys, 'sd', ')')
  has_message_about_not_found(')', 2)

  -- Should also use buffer local config
  child.b.minisurround_config = { n_lines = 10 }
  validate_edit(lines, { 4, 0 }, { '', '', '', 'a', '', '', '' }, { 1, 0 }, type_keys, 'sd', ')')
end

T['Delete surrounding']['respects `config.search_method`'] = function()
  local lines = { 'aaa (bbb)' }

  -- By default uses 'cover'
  validate_edit(lines, { 1, 0 }, lines, { 1, 0 }, type_keys, 'sd', ')')
  has_message_about_not_found(')')

  -- Should change behavior according to `config.search_method`
  reload_module({ search_method = 'cover_or_next' })
  validate_edit(lines, { 1, 0 }, { 'aaa bbb' }, { 1, 4 }, type_keys, 'sd', ')')

  -- Should also use buffer local config
  child.b.minisurround_config = { search_method = 'cover' }
  validate_edit(lines, { 1, 0 }, lines, { 1, 0 }, type_keys, 'sd', ')')
end

T['Delete surrounding']['places cursor to the right of left surrounding'] = function()
  local f = function() type_keys('sd', 'f') end

  -- Same line
  validate_edit({ 'myfunc(aaa)' }, { 1, 7 }, { 'aaa' }, { 1, 0 }, f)

  -- Not the same line
  validate_edit({ 'myfunc(aaa', 'bbb', 'ccc)' }, { 1, 8 }, { 'aaa', 'bbb', 'ccc' }, { 1, 0 }, f)
  validate_edit({ 'myfunc(aaa', 'bbb', 'ccc)' }, { 2, 0 }, { 'aaa', 'bbb', 'ccc' }, { 1, 0 }, f)
  validate_edit({ 'myfunc(aaa', 'bbb', 'ccc)' }, { 3, 2 }, { 'aaa', 'bbb', 'ccc' }, { 1, 0 }, f)
end

T['Delete surrounding']['prompts helper message after one idle second'] = function()
  child.set_size(5, 70)
  child.o.cmdheight = 1

  -- Mapping is applied only after `timeoutlen` milliseconds, because
  -- there are `sdn`/`sdl` mappings. Wait 1000 seconds after that.
  child.o.timeoutlen = 5 * small_time
  local total_wait_time = helper_message_delay + child.o.timeoutlen + small_time

  set_lines({ '((aaa))' })
  set_cursor(1, 1)

  -- Execute one time to test if 'needs help message' flag is set per call
  type_keys('sd', ')')
  sleep(0.1 * helper_message_delay)

  type_keys('sd')
  sleep(total_wait_time)

  -- Should show helper message without adding it to `:messages` and causing
  -- hit-enter-prompt
  eq(get_latest_message(), '')
  child.expect_screenshot()

  -- Should clear afterwards
  type_keys(')')
  child.expect_screenshot()
end

T['Delete surrounding']['handles special characters in "not found" message'] = function()
  type_keys('sd', '\t')
  has_message_about_not_found('\t')
  type_keys('sd', '<C-j>')
  has_message_about_not_found('\n')
end

T['Delete surrounding']['works with multibyte characters'] = function()
  local f = function() type_keys('sd', ')') end

  validate_edit({ '  (ыыы)  ' }, { 1, 3 }, { '  ыыы  ' }, { 1, 2 }, f)
  validate_edit({ '(ыыы) ttt' }, { 1, 1 }, { 'ыыы ttt' }, { 1, 0 }, f)
  validate_edit({ 'ttt (ыыы)' }, { 1, 5 }, { 'ttt ыыы' }, { 1, 4 }, f)
end

T['Delete surrounding']['works on multiple lines'] = function()
  local f = function() type_keys('sd', ')') end

  validate_edit({ '(aaa', 'bbb', 'ccc)' }, { 1, 3 }, { 'aaa', 'bbb', 'ccc' }, { 1, 0 }, f)
  validate_edit({ '(aaa', 'bbb', 'ccc)' }, { 2, 0 }, { 'aaa', 'bbb', 'ccc' }, { 1, 0 }, f)
end

T['Delete surrounding']['works with multiline input surroundings'] = function()
  child.lua([[MiniSurround.config.custom_surroundings = {
    a = { input = { '%(\na().-()a\n%)' } },
    b = { input = { '%(\n().-()\n%)' } },
    c = { input = { '\na().-()a\n' } },
    d = { input = { '\n().-()\n' } },
  }]])
  local lines = { 'xxx(', 'aaa', ')xxx' }
  local f

  f = function() type_keys('sd', 'a') end
  validate_edit(lines, { 1, 3 }, { 'xxxaxxx' }, { 1, 3 }, f)
  validate_edit(lines, { 2, 1 }, { 'xxxaxxx' }, { 1, 3 }, f)
  validate_edit(lines, { 3, 0 }, { 'xxxaxxx' }, { 1, 3 }, f)

  f = function() type_keys('sd', 'b') end
  validate_edit(lines, { 1, 3 }, { 'xxxaaaxxx' }, { 1, 3 }, f)
  validate_edit(lines, { 2, 1 }, { 'xxxaaaxxx' }, { 1, 3 }, f)
  validate_edit(lines, { 3, 0 }, { 'xxxaaaxxx' }, { 1, 3 }, f)

  f = function() type_keys('sd', 'c') end
  -- No case for first line because there is no covering match
  validate_edit(lines, { 2, 1 }, { 'xxx(a)xxx' }, { 1, 4 }, f)
  -- No case for third line because there is no covering match

  f = function() type_keys('sd', 'd') end
  -- No case for first line because there is no covering match
  validate_edit(lines, { 2, 1 }, { 'xxx(aaa)xxx' }, { 1, 4 }, f)
  -- There is a `\n` at the end of last line, so it is matched
  validate_edit(lines, { 3, 0 }, { 'xxx(', 'aaa)xxx' }, { 2, 3 }, f)
end

T['Delete surrounding']['allows cancelling with `<Esc> and <C-c>`'] = function()
  local validate_cancel = function(key)
    child.ensure_normal_mode()
    set_lines({ '<aaa>' })
    set_cursor(1, 1)

    type_keys(1, 'sd', key)
    eq(get_lines(), { '<aaa>' })
    eq(get_cursor(), { 1, 1 })
  end

  validate_cancel('<Esc>')
  validate_cancel('<C-c>')
end

T['Delete surrounding']['works with different mapping'] = function()
  reload_module({ mappings = { delete = 'SD' } })

  validate_edit({ '(aaa)' }, { 1, 1 }, { 'aaa' }, { 1, 0 }, type_keys, 'SD', ')')
  child.api.nvim_del_keymap('n', 'SD')
end

T['Delete surrounding']['respects `v:count` for input surrounding'] = function()
  validate_edit({ '(a(b(c)b)a)' }, { 1, 5 }, { '(ab(c)ba)' }, { 1, 2 }, type_keys, '2sd', ')')

  -- Should give informative message on failure
  validate_edit({ '(a)' }, { 1, 0 }, { '(a)' }, { 1, 0 }, type_keys, '2sd', ')')
  has_message_about_not_found(')', nil, nil, 2)

  -- Should respect search method
  child.lua([[MiniSurround.config.search_method = 'cover_or_next']])
  validate_edit({ '(aa) (bb) (cc)' }, { 1, 1 }, { '(aa) bb (cc)' }, { 1, 5 }, type_keys, '2sd', ')')
end

T['Delete surrounding']['respects `vim.{g,b}.minisurround_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minisurround_disable = true

    set_lines({ '<aaa>' })
    set_cursor(1, 1)

    -- It should ignore `sd`
    type_keys('sd', '>')
    eq(get_lines(), { '<aaa>' })
    eq(get_cursor(), { 1, 1 })
  end,
})

T['Delete surrounding']['respects `config.silent`'] = function()
  child.lua('MiniSurround.config.silent = true')
  child.set_size(10, 20)

  child.o.timeoutlen = 5 * small_time
  local total_wait_time = helper_message_delay + child.o.timeoutlen + small_time

  set_lines({ '<aaa>' })
  set_cursor(1, 1)

  -- It should not show helper message after one idle second
  type_keys('sd')
  sleep(total_wait_time)
  child.expect_screenshot()

  -- It should not show message about "No surrounding found"
  type_keys(')')
  child.expect_screenshot()
end

T['Delete surrounding']['respects `vim.b.minisurround_config`'] = function()
  child.b.minisurround_config = { custom_surroundings = { ['<'] = { input = { '>().-()<' } } } }
  validate_edit({ '>aaa<' }, { 1, 2 }, { 'aaa' }, { 1, 0 }, type_keys, 'sd', '<')
end

T['Replace surrounding'] = new_set()

-- NOTE: use `>` for replacement because it itself is not a blocking key.
-- Like if you type `}` or `]`, Neovim will have to wait for the next key,
-- which blocks `child`.
T['Replace surrounding']['works with dot-repeat'] = function()
  validate_edit({ '(aaa)' }, { 1, 0 }, { '<aaa>' }, { 1, 1 }, type_keys, 'sr', ')', '>')
  validate_edit({ '(aaa)' }, { 1, 4 }, { '<aaa>' }, { 1, 1 }, type_keys, 'sr', ')', '>')
  validate_edit({ '(aaa)' }, { 1, 2 }, { '<aaa>' }, { 1, 1 }, type_keys, 'sr', ')', '>')

  -- Allows immediate dot-repeat
  set_lines({ '((aaa))' })
  set_cursor(1, 2)
  type_keys('sr', ')', '>')
  type_keys('.')
  eq(get_lines(), { '<<aaa>>' })
  eq(get_cursor(), { 1, 1 })

  -- Allows not immediate dot-repeat
  set_lines({ 'aaa (bbb)' })
  set_cursor(1, 5)
  type_keys('.')
  eq(get_lines(), { 'aaa <bbb>' })
end

T['Replace surrounding']['works in extended mappings'] = function()
  validate_edit1d('(aa) (bb) (cc)', 1, '(aa) <bb> (cc)', 6, type_keys, 'srn', ')', '>')
  validate_edit1d('(aa) (bb) (cc)', 1, '(aa) (bb) <cc>', 11, type_keys, '2srn', ')', '>')

  validate_edit1d('(aa) (bb) (cc)', 11, '(aa) <bb> (cc)', 6, type_keys, 'srl', ')', '>')
  validate_edit1d('(aa) (bb) (cc)', 11, '<aa> (bb) (cc)', 1, type_keys, '2srl', ')', '>')

  -- Dot-repeat
  set_lines({ '(aa) (bb) (cc)' })
  set_cursor(1, 0)
  type_keys('srn', ')', '>')
  type_keys('.')
  eq(get_lines(), { '(aa) <bb> <cc>' })
  eq(get_cursor(), { 1, 11 })
end

T['Replace surrounding']['respects `config.n_lines`'] = function()
  reload_module({ n_lines = 2 })
  local lines = { '(', '', '', 'a', '', '', ')' }
  validate_edit(lines, { 4, 0 }, lines, { 4, 0 }, type_keys, 'sr', ')', '>')
  has_message_about_not_found(')', 2)

  -- Should also use buffer local config
  child.b.minisurround_config = { n_lines = 10 }
  validate_edit(lines, { 4, 0 }, { '<', '', '', 'a', '', '', '>' }, { 1, 0 }, type_keys, 'sr', ')', '>')
end

T['Replace surrounding']['respects `config.search_method`'] = function()
  local lines = { 'aaa (bbb)' }

  -- By default uses 'cover'
  validate_edit(lines, { 1, 0 }, lines, { 1, 0 }, type_keys, 'sr', ')', '>')
  has_message_about_not_found(')')

  -- Should change behavior according to `config.search_method`
  reload_module({ search_method = 'cover_or_next' })
  validate_edit(lines, { 1, 0 }, { 'aaa <bbb>' }, { 1, 5 }, type_keys, 'sr', ')', '>')

  -- Should also use buffer local config
  child.b.minisurround_config = { search_method = 'cover' }
  validate_edit(lines, { 1, 0 }, lines, { 1, 0 }, type_keys, 'sr', ')', '>')
end

T['Replace surrounding']['places cursor to the right of left surrounding'] = function()
  local f = function() type_keys('sr', 'f', '>') end

  -- Same line
  validate_edit({ 'myfunc(aaa)' }, { 1, 7 }, { '<aaa>' }, { 1, 1 }, f)

  -- Not the same line
  validate_edit({ 'myfunc(aaa', 'bbb', 'ccc)' }, { 1, 8 }, { '<aaa', 'bbb', 'ccc>' }, { 1, 1 }, f)
  validate_edit({ 'myfunc(aaa', 'bbb', 'ccc)' }, { 2, 0 }, { '<aaa', 'bbb', 'ccc>' }, { 1, 1 }, f)
  validate_edit({ 'myfunc(aaa', 'bbb', 'ccc)' }, { 3, 2 }, { '<aaa', 'bbb', 'ccc>' }, { 1, 1 }, f)
end

T['Replace surrounding']['prompts helper message after one idle second'] = function()
  child.set_size(5, 70)
  child.o.cmdheight = 1

  -- Mapping is applied only after `timeoutlen` milliseconds, because
  -- there are `srn`/`srl` mappings. Wait 1000 seconds after that.
  child.o.timeoutlen = 5 * small_time
  local total_wait_time = helper_message_delay + child.o.timeoutlen + small_time

  set_lines({ '((aaa))' })
  set_cursor(1, 1)

  -- Execute one time to test if 'needs help message' flag is set per call
  type_keys('sr', ')', '>')
  sleep(0.1 * helper_message_delay)

  type_keys('sr')
  sleep(total_wait_time)

  -- Should show helper message without adding it to `:messages` and causing
  -- hit-enter-prompt
  eq(get_latest_message(), '')
  child.expect_screenshot()

  clear_messages()
  type_keys(')')

  -- Here mapping collision doesn't matter any more
  sleep(helper_message_delay + small_time)
  eq(get_latest_message(), '')
  child.expect_screenshot()

  -- Should clear afterwards
  type_keys('>')
  child.expect_screenshot()
end

T['Replace surrounding']['handles special characters in "not found" message'] = function()
  type_keys('sr', '\t', ')')
  has_message_about_not_found('\t')
  type_keys('sr', '<C-j>', ')')
  has_message_about_not_found('\n')
end

T['Replace surrounding']['works with multibyte characters'] = function()
  local f = function() type_keys('sr', ')', '>') end

  validate_edit({ '  (ыыы)  ' }, { 1, 3 }, { '  <ыыы>  ' }, { 1, 3 }, f)
  validate_edit({ '(ыыы) ttt' }, { 1, 1 }, { '<ыыы> ttt' }, { 1, 1 }, f)
  validate_edit({ 'ttt (ыыы)' }, { 1, 5 }, { 'ttt <ыыы>' }, { 1, 5 }, f)
end

T['Replace surrounding']['works on multiple lines'] = function()
  local f = function() type_keys('sr', ')', '>') end

  validate_edit({ '(aaa', 'bbb', 'ccc)' }, { 1, 3 }, { '<aaa', 'bbb', 'ccc>' }, { 1, 1 }, f)
  validate_edit({ '(aaa', 'bbb', 'ccc)' }, { 2, 0 }, { '<aaa', 'bbb', 'ccc>' }, { 1, 1 }, f)
end

T['Replace surrounding']['works with multiline input surroundings'] = function()
  child.lua([[MiniSurround.config.custom_surroundings = {
    a = { input = { '%(\na().-()a\n%)' } },
    b = { input = { '%(\n().-()\n%)' } },
    c = { input = { '\na().-()a\n' } },
    d = { input = { '\n().-()\n' } },
  }]])
  local lines = { 'xxx(', 'aaa', ')xxx' }
  local f

  f = function() type_keys('sr', 'a', '>') end
  validate_edit(lines, { 1, 3 }, { 'xxx<a>xxx' }, { 1, 4 }, f)
  validate_edit(lines, { 2, 1 }, { 'xxx<a>xxx' }, { 1, 4 }, f)
  validate_edit(lines, { 3, 0 }, { 'xxx<a>xxx' }, { 1, 4 }, f)

  f = function() type_keys('sr', 'b', '>') end
  validate_edit(lines, { 1, 3 }, { 'xxx<aaa>xxx' }, { 1, 4 }, f)
  validate_edit(lines, { 2, 1 }, { 'xxx<aaa>xxx' }, { 1, 4 }, f)
  validate_edit(lines, { 3, 0 }, { 'xxx<aaa>xxx' }, { 1, 4 }, f)

  f = function() type_keys('sr', 'c', '>') end
  -- No case for first line because there is no covering match
  validate_edit(lines, { 2, 1 }, { 'xxx(<a>)xxx' }, { 1, 5 }, f)
  -- No case for third line because there is no covering match

  f = function() type_keys('sr', 'd', '>') end
  -- No case for first line because there is no covering match
  validate_edit(lines, { 2, 1 }, { 'xxx(<aaa>)xxx' }, { 1, 5 }, f)
  -- There is a `\n` at the end of last line. It is matched but can't be replaced.
  validate_edit(lines, { 3, 0 }, { 'xxx(', 'aaa<)xxx' }, { 2, 4 }, f)
end

T['Replace surrounding']['works with multiline output surroundings'] = function()
  child.lua([[MiniSurround.config.custom_surroundings = {
    a = { output = { left = '\n(\n', right = '\n)\n' } }
  }]])
  local lines = { '  [xxx]' }
  validate_edit(lines, { 1, 3 }, { '  ', '(', 'xxx', ')', '' }, { 1, 1 }, type_keys, 'sr', ']', 'a')
end

T['Replace surrounding']['allows cancelling with `<Esc> and <C-c>`'] = function()
  local validate_cancel = function(key)
    child.ensure_normal_mode()
    set_lines({ '<aaa>' })
    set_cursor(1, 1)

    -- Cancel before input surrounding
    type_keys(1, 'sr', key)
    eq(get_lines(), { '<aaa>' })
    eq(get_cursor(), { 1, 1 })

    -- Cancel before output surrounding
    type_keys(1, 'sr', '>', key)
    eq(get_lines(), { '<aaa>' })
    eq(get_cursor(), { 1, 1 })
  end

  validate_cancel('<Esc>')
  validate_cancel('<C-c>')
end

T['Replace surrounding']['works with different mapping'] = function()
  reload_module({ mappings = { replace = 'SR' } })

  validate_edit({ '(aaa)' }, { 1, 1 }, { '<aaa>' }, { 1, 1 }, type_keys, 'SR', ')', '>')
  child.api.nvim_del_keymap('n', 'SR')
end

T['Replace surrounding']['respects `v:count` for input surrounding'] = function()
  validate_edit({ '(a(b(c)b)a)' }, { 1, 5 }, { '(a<b(c)b>a)' }, { 1, 3 }, type_keys, '2sr', ')', '>')

  -- Should give informative message on failure
  validate_edit({ '(a)' }, { 1, 0 }, { '(a)' }, { 1, 0 }, type_keys, '2sr', ')', '>')
  has_message_about_not_found(')', nil, nil, 2)

  -- Should respect search method
  child.lua([[MiniSurround.config.search_method = 'cover_or_next']])
  validate_edit({ '(aa) (bb) (cc)' }, { 1, 1 }, { '(aa) <bb> (cc)' }, { 1, 6 }, type_keys, '2sr', ')', '>')
end

T['Replace surrounding']['respects `vim.{g,b}.minisurround_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minisurround_disable = true

    set_lines({ '<aaa>' })
    set_cursor(1, 1)

    -- It should ignore `sr`
    type_keys('sr', '>', '"')
    eq(get_lines(), { '<aaa>' })
    eq(get_cursor(), { 1, 1 })
  end,
})

T['Replace surrounding']['respects `config.silent`'] = function()
  child.lua('MiniSurround.config.silent = true')
  child.set_size(10, 20)

  child.o.timeoutlen = 5 * small_time
  local total_wait_time = helper_message_delay + child.o.timeoutlen + small_time

  set_lines({ '<aaa>' })
  set_cursor(1, 1)

  -- It should not show helper message after one idle second
  type_keys('sr')
  sleep(total_wait_time)
  child.expect_screenshot()

  -- It should not show message about "No surrounding found"
  type_keys(')')
  child.expect_screenshot()
end

T['Replace surrounding']['respects `vim.b.minisurround_config`'] = function()
  child.b.minisurround_config = { custom_surroundings = { ['<'] = { output = { left = '>', right = '<' } } } }
  validate_edit({ '<aaa>' }, { 1, 2 }, { '>aaa<' }, { 1, 1 }, type_keys, 'sr', '>', '<')
end

T['Find surrounding'] = new_set()

-- NOTE: most tests are done for `sf` ('find right') in hope that `sF` ('find
-- left') is implemented similarly
T['Find surrounding']['works without dot-repeat'] = function()
  validate_find({ '(aaa)' }, { 1, 0 }, { { 1, 4 }, { 1, 0 }, { 1, 4 } }, type_keys, 'sf', ')')
  validate_find({ '(aaa)' }, { 1, 2 }, { { 1, 4 }, { 1, 0 }, { 1, 4 } }, type_keys, 'sf', ')')
  validate_find({ '(aaa)' }, { 1, 4 }, { { 1, 0 }, { 1, 4 }, { 1, 0 } }, type_keys, 'sf', ')')

  -- Does not override dot-repeat
  set_lines({ '(aaa)' })
  set_cursor(1, 0)
  type_keys('r]', 'u') -- dot-repeatable action
  set_cursor(1, 2)
  type_keys('sf', ')')
  type_keys('.')
  eq(get_lines(), { '(aaa]' })
  eq(get_cursor(), { 1, 4 })
end

T['Find surrounding']['works in left direction without dot-repeat'] = function()
  validate_find({ '(aaa)' }, { 1, 0 }, { { 1, 4 }, { 1, 0 }, { 1, 4 } }, type_keys, 'sF', ')')
  validate_find({ '(aaa)' }, { 1, 4 }, { { 1, 0 }, { 1, 4 }, { 1, 0 } }, type_keys, 'sF', ')')
  validate_find({ '(aaa)' }, { 1, 2 }, { { 1, 0 }, { 1, 4 }, { 1, 0 } }, type_keys, 'sF', ')')

  -- Does not override dot-repeat
  set_lines({ '(aaa)' })
  set_cursor(1, 0)
  type_keys('r[', 'u') -- dot-repeatable action
  set_cursor(1, 2)
  type_keys('sF', ')')
  type_keys('.')
  eq(get_lines(), { '[aaa)' })
  eq(get_cursor(), { 1, 0 })
end

T['Find surrounding']['works with "non single character" surroundings'] = function()
  --stylua: ignore start
  -- Cursor is strictly inside surroundings
  validate_find({ 'myfunc(aaa)' }, { 1, 9 }, { {1,10}, {1,0}, {1,6}, {1,10} }, type_keys, 'sf', 'f')
  validate_find({ '<t>aaa</t>' }, { 1, 4 }, { {1,6}, {1,9}, {1,0}, {1,2}, {1,6} }, type_keys, 'sf', 't')
  validate_find({ '_aaa*^' }, { 1, 2 }, { {1,4}, {1,5}, {1,0}, {1,4} }, type_keys, 'sf', '?', '_<CR>', '*^<CR>')

  -- Cursor is inside one of the surrounding parts
  validate_find({ 'myfunc(aaa)' }, { 1, 2 }, { {1,6}, {1,10}, {1,0}, {1,6} }, type_keys, 'sf', 'f')
  validate_find({ '<t>aaa</t>' }, { 1, 1 }, { {1,2}, {1,6}, {1,9}, {1,0}, {1,2} }, type_keys, 'sf', 't')
  validate_find({ '_aaa*^' }, { 1, 4 }, { {1,5}, {1,0}, {1,4}, {1,5} }, type_keys, 'sf', '?', '_<CR>', '*^<CR>')

  -- Moving in left direction
  validate_find({ 'myfunc(aaa)' }, { 1, 8 }, { {1,6}, {1,0}, {1,10}, {1,6} }, type_keys, 'sF', 'f')
  validate_find({ '<t>aaa</t>' }, { 1, 4 }, { {1,2}, {1,0}, {1,9}, {1,6}, {1,2} }, type_keys, 'sF', 't')
  validate_find({ '_aaa*^' }, { 1, 2 }, { {1,0}, {1,5}, {1,4}, {1,0} }, type_keys, 'sF', '?', '_<CR>', '*^<CR>')
  --stylua: ignore end
end

T['Find surrounding']['works in extended mappings'] = function()
  -- "Find right" when outside of outer surroundings puts cursor on left-most
  -- position. If cursor is on the left, that is obvious. When on the right -
  -- it behaves as on the right-most surrounding position.
  -- "Find left" puts on right-most position for the same reasons.
  validate_edit1d('(aa) (bb) (cc)', 1, '(aa) (bb) (cc)', 5, type_keys, 'sfn', ')')
  validate_edit1d('(aa) (bb) (cc)', 1, '(aa) (bb) (cc)', 10, type_keys, '2sfn', ')')
  validate_edit1d('(aa) (bb) (cc)', 1, '(aa) (bb) (cc)', 8, type_keys, 'sFn', ')')
  validate_edit1d('(aa) (bb) (cc)', 1, '(aa) (bb) (cc)', 13, type_keys, '2sFn', ')')

  validate_edit1d('(aa) (bb) (cc)', 11, '(aa) (bb) (cc)', 5, type_keys, 'sfl', ')')
  validate_edit1d('(aa) (bb) (cc)', 11, '(aa) (bb) (cc)', 0, type_keys, '2sfl', ')')
  validate_edit1d('(aa) (bb) (cc)', 11, '(aa) (bb) (cc)', 8, type_keys, 'sFl', ')')
  validate_edit1d('(aa) (bb) (cc)', 11, '(aa) (bb) (cc)', 3, type_keys, '2sFl', ')')

  -- Does not override dot-repeat
  set_lines({ '(aa) (bb) (cc)' })
  set_cursor(1, 0)
  type_keys('r[', 'u') -- dot-repeatable action
  type_keys('sfn', ')')
  type_keys('.')
  eq(get_lines(), { '(aa) [bb) (cc)' })
  eq(get_cursor(), { 1, 5 })
end

T['Find surrounding']['respects `config.n_lines`'] = function()
  reload_module({ n_lines = 2 })
  local lines = { '(', '', '', 'a', '', '', ')' }
  validate_find(lines, { 4, 0 }, { { 4, 0 } }, type_keys, 'sf', ')')
  has_message_about_not_found(')', 2)

  -- Should also use buffer local config
  child.b.minisurround_config = { n_lines = 10 }
  validate_find(lines, { 4, 0 }, { { 7, 0 } }, type_keys, 'sf', ')')
end

T['Find surrounding']['respects `config.search_method`'] = function()
  local lines = { 'aaa (bbb)' }

  -- By default uses 'cover'
  validate_find(lines, { 1, 0 }, { { 1, 0 } }, type_keys, 'sf', ')')
  has_message_about_not_found(')')

  clear_messages()
  validate_find(lines, { 1, 0 }, { { 1, 0 } }, type_keys, 'sF', ')')
  has_message_about_not_found(')')

  -- Should change behavior according to `config.search_method`
  reload_module({ search_method = 'cover_or_next' })
  validate_find(lines, { 1, 0 }, { { 1, 4 } }, type_keys, 'sf', ')')
  validate_find(lines, { 1, 0 }, { { 1, 8 } }, type_keys, 'sF', ')')

  -- Should also use buffer local config
  child.b.minisurround_config = { search_method = 'cover' }
  validate_find(lines, { 1, 0 }, { { 1, 0 } }, type_keys, 'sf', ')')
end

T['Find surrounding']['prompts helper message after one idle second'] = function()
  child.set_size(5, 70)
  child.o.cmdheight = 1

  -- Mapping is applied only after `timeoutlen` milliseconds, because
  -- there are `sfn`/`sfl` mappings. Wait 1000 seconds after that.
  child.o.timeoutlen = 5 * small_time
  local total_wait_time = helper_message_delay + child.o.timeoutlen + small_time

  set_lines({ '(aaa)' })
  set_cursor(1, 2)

  -- Execute one time to test if 'needs help message' flag is set per call
  type_keys('sf', ')')
  sleep(0.1 * helper_message_delay)

  type_keys('sf')
  sleep(total_wait_time)

  -- Should show helper message without adding it to `:messages` and causing
  -- hit-enter-prompt
  eq(get_latest_message(), '')
  child.expect_screenshot()

  -- Should clear afterwards
  type_keys(')')
  child.expect_screenshot()
end

T['Find surrounding']['handles special characters in "not found" message'] = function()
  type_keys('sf', '\t')
  has_message_about_not_found('\t')
  type_keys('sf', '<C-j>')
  has_message_about_not_found('\n')
end

T['Find surrounding']['works with multibyte characters'] = function()
  local f = function() type_keys('sf', ')') end

  validate_find({ '  (ыыы)  ' }, { 1, 5 }, { { 1, 9 }, { 1, 2 } }, f)
  validate_find({ '(ыыы) ttt' }, { 1, 3 }, { { 1, 7 }, { 1, 0 } }, f)
  validate_find({ 'ttt (ыыы)' }, { 1, 7 }, { { 1, 11 }, { 1, 4 } }, f)
end

T['Find surrounding']['works on multiple lines'] = function()
  validate_find({ '(aaa', 'bbb', 'ccc)' }, { 1, 3 }, { { 3, 3 }, { 1, 0 } }, type_keys, 'sf', ')')
  validate_find({ '(aaa', 'bbb', 'ccc)' }, { 1, 3 }, { { 1, 0 }, { 3, 3 } }, type_keys, 'sF', ')')
end

T['Find surrounding']['works with multiline input surroundings'] = function()
  child.lua([[MiniSurround.config.custom_surroundings = {
    a = { input = { '%(\na().-()a\n%)' } },
    b = { input = { '%(\n().-()\n%)' } },
    c = { input = { '\na().-()a\n' } },
    d = { input = { '\n().-()\n' } },
  }]])
  local lines = { 'xxx(', 'aaa', ')xxx' }

  validate_find(lines, { 2, 1 }, { { 2, 2 }, { 3, 0 }, { 1, 3 }, { 2, 0 } }, type_keys, 'sf', 'a')
  validate_find(lines, { 2, 1 }, { { 2, 0 }, { 1, 3 }, { 3, 0 }, { 2, 2 } }, type_keys, 'sF', 'a')

  -- Same as `a` because new line characters are normalized "inside" surrounding
  validate_find(lines, { 2, 1 }, { { 2, 2 }, { 3, 0 }, { 1, 3 }, { 2, 0 } }, type_keys, 'sf', 'b')
  validate_find(lines, { 2, 1 }, { { 2, 0 }, { 1, 3 }, { 3, 0 }, { 2, 2 } }, type_keys, 'sF', 'b')

  validate_find(lines, { 2, 1 }, { { 2, 2 }, { 2, 0 } }, type_keys, 'sf', 'c')
  validate_find(lines, { 2, 1 }, { { 2, 0 }, { 2, 2 } }, type_keys, 'sF', 'c')

  -- Same as `c` because new line characters are normalized "inside" surrounding
  validate_find(lines, { 2, 1 }, { { 2, 2 }, { 2, 0 } }, type_keys, 'sf', 'd')
  validate_find(lines, { 2, 1 }, { { 2, 0 }, { 2, 2 } }, type_keys, 'sF', 'd')
end

T['Find surrounding']['allows cancelling with `<Esc> and <C-c>`'] = function()
  local validate_cancel = function(key)
    child.ensure_normal_mode()
    set_lines({ '<aaa>' })
    set_cursor(1, 1)

    -- It should work with `sf`
    type_keys(1, 'sf', key)
    eq(get_lines(), { '<aaa>' })
    eq(get_cursor(), { 1, 1 })

    -- It should work with `sF`
    type_keys(1, 'sF', key)
    eq(get_lines(), { '<aaa>' })
    eq(get_cursor(), { 1, 1 })
  end

  validate_cancel('<Esc>')
  validate_cancel('<C-c>')
end

T['Find surrounding']['works with different mapping'] = function()
  reload_module({ mappings = { find = 'SF', find_left = 'Sf' } })

  validate_find({ '(aaa)' }, { 1, 2 }, { { 1, 4 }, { 1, 0 } }, type_keys, 'SF', ')')
  validate_find({ '(aaa)' }, { 1, 2 }, { { 1, 0 }, { 1, 4 } }, type_keys, 'Sf', ')')
  child.api.nvim_del_keymap('n', 'SF')
  child.api.nvim_del_keymap('n', 'Sf')
end

T['Find surrounding']['respects `v:count` for input surrounding'] = function()
  validate_edit({ '(a(b(c)b)a)' }, { 1, 5 }, { '(a(b(c)b)a)' }, { 1, 8 }, type_keys, '2sf', ')')
  validate_edit({ '(a(b(c)b)a)' }, { 1, 5 }, { '(a(b(c)b)a)' }, { 1, 2 }, type_keys, '2sF', ')')

  -- Should give informative message on failure
  validate_edit({ '(a)' }, { 1, 0 }, { '(a)' }, { 1, 0 }, type_keys, '2sf', ')')
  has_message_about_not_found(')', nil, nil, 2)

  -- Should respect search method
  child.lua([[MiniSurround.config.search_method = 'cover_or_next']])
  validate_edit({ '(aa) (bb) (cc)' }, { 1, 1 }, { '(aa) (bb) (cc)' }, { 1, 5 }, type_keys, '2sf', ')')

  child.lua([[MiniSurround.config.search_method = 'cover_or_prev']])
  validate_edit({ '(aa) (bb) (cc)' }, { 1, 13 }, { '(aa) (bb) (cc)' }, { 1, 8 }, type_keys, '2sF', ')')
end

T['Find surrounding']['respects `vim.{g,b}.minisurround_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minisurround_disable = true

    set_lines({ '<aaa>' })
    set_cursor(1, 1)

    -- It should ignore `sf`
    type_keys('sf', '>')
    eq(get_lines(), { '<aaa>' })
    eq(get_cursor(), { 1, 1 })

    -- It should ignore `sF`
    type_keys('sF', '>')
    eq(get_lines(), { '<aaa>' })
    eq(get_cursor(), { 1, 1 })
  end,
})

T['Find surrounding']['respects `vim.b.minisurround_config`'] = function()
  child.b.minisurround_config = { custom_surroundings = { ['<'] = { input = { '>().-()<' } } } }
  validate_edit({ '>aaa<' }, { 1, 2 }, { '>aaa<' }, { 1, 4 }, type_keys, 'sf', '<')
end

-- NOTE: most tests are done specifically for highlighting in hope that
-- finding of surrounding is done properly
T['Highlight surrounding'] = new_set({
  hooks = {
    pre_case = function()
      -- Reduce default highlight duration to speed up tests execution
      child.lua('MiniSurround.config.highlight_duration = ' .. (5 * small_time))
      child.set_size(5, 12)
      child.o.cmdheight = 1
    end,
  },
})

local activate_highlighting = function()
  type_keys('sh)')
  child.poke_eventloop()
end

T['Highlight surrounding']['works without dot-repeat'] = function()
  -- Check this only on Neovim>=0.11, as there is a slight change in
  -- highlighting command line area
  if child.fn.has('nvim-0.11') == 0 then return end

  local test_duration = child.lua_get('MiniSurround.config.highlight_duration')
  set_lines({ ' ' })
  set_cursor(1, 0)
  type_keys('rx') -- dot-repeatable action

  set_lines({ '(aaa) (bbb)' })
  set_cursor(1, 2)

  -- Should show highlighting immediately
  activate_highlighting()
  child.expect_screenshot()

  -- Should still highlight
  sleep(test_duration - 2 * small_time)
  child.expect_screenshot()

  -- Should stop highlighting
  sleep(2 * small_time + small_time)
  child.expect_screenshot()

  -- Does not override dot-repeat
  type_keys('.')

  -- - No highlighting should be present
  child.expect_screenshot()
end

T['Highlight surrounding']['works in extended mappings'] = function()
  child.set_size(5, 15)
  local test_duration = child.lua_get('MiniSurround.config.highlight_duration')
  set_lines({ ' ' })
  set_cursor(1, 0)
  type_keys('rx') -- dot-repeatable action
  set_lines({ '(aa) (bb) (cc)' })
  set_cursor(1, 0)

  set_cursor(1, 1)
  type_keys('shn', ')')
  child.poke_eventloop()
  child.expect_screenshot()
  sleep(test_duration + small_time)

  set_cursor(1, 12)
  type_keys('shl', ')')
  child.poke_eventloop()
  child.expect_screenshot()
  sleep(test_duration + small_time)

  -- Does not override dot-repeat
  type_keys('.')

  -- - No highlighting should be present
  child.expect_screenshot()
end

T['Highlight surrounding']['respects `config.highlight_duration`'] = function()
  -- Currently tested in every `pre_case()`
end

T['Highlight surrounding']['respects `config.n_lines`'] = function()
  child.set_size(15, 40)
  child.o.cmdheight = 3

  child.lua('MiniSurround.config.n_lines = 2')
  set_lines({ '(', '', '', 'a', '', '', ')' })
  set_cursor(4, 0)
  activate_highlighting()

  -- Shouldn't highlight anything
  child.expect_screenshot()
  has_message_about_not_found(')', 2)
end

T['Highlight surrounding']['works with multiline input surroundings'] = function()
  -- Check this only on Neovim>=0.11, as there is a slight change in
  -- highlighting command line area
  if child.fn.has('nvim-0.11') == 0 then return end

  child.lua('MiniSurround.config.highlight_duration = ' .. small_time)
  child.lua([[MiniSurround.config.custom_surroundings = {
    a = { input = { '%(\na().-()a\n%)' } },
    b = { input = { '%(\n().-()\n%)' } },
    c = { input = { '\na().-()a\n' } },
    d = { input = { '\n().-()\n' } },
  }]])
  set_lines({ 'xxx(', 'aaa', ')xxx' })
  set_cursor(2, 1)

  type_keys('sh', 'a')
  child.expect_screenshot()
  sleep(small_time + small_time)

  type_keys('sh', 'b')
  child.expect_screenshot()
  sleep(small_time + small_time)

  type_keys('sh', 'c')
  child.expect_screenshot()
  sleep(small_time + small_time)

  type_keys('sh', 'd')
  child.expect_screenshot()
end

T['Highlight surrounding']['removes highlighting in correct buffer'] = function()
  child.set_size(5, 60)
  local test_duration = child.lua_get('MiniSurround.config.highlight_duration')

  set_lines({ '(aaa)' })
  set_cursor(1, 2)
  activate_highlighting()

  child.cmd('vsplit current')
  set_lines({ '(bbb)' })
  set_cursor(1, 2)
  sleep(0.5 * test_duration + small_time)
  activate_highlighting()

  -- Highlighting should be removed only in previous buffer
  child.expect_screenshot()
  sleep(0.5 * test_duration + small_time)
  child.expect_screenshot()
end

T['Highlight surrounding']['removes highlighting per line'] = function()
  -- Check this only on Neovim>=0.11, as there is a slight change in
  -- highlighting command line area
  if child.fn.has('nvim-0.11') == 0 then return end

  local test_duration = child.lua_get('MiniSurround.config.highlight_duration')
  local half_duration = 0.5 * test_duration
  set_lines({ '(aaa)', '(bbb)' })

  -- Create situation when there are two highlights simultaneously but on
  -- different lines. Check that they are properly and independently removed.
  set_cursor(1, 2)
  activate_highlighting()
  sleep(half_duration)
  set_cursor(2, 2)
  activate_highlighting()

  -- Should highlight in both lines
  child.expect_screenshot()

  -- Should highlight only in second line
  sleep(half_duration + small_time)
  child.expect_screenshot()

  -- Should stop highlighting at all
  sleep(half_duration + small_time)
  child.expect_screenshot()
end

T['Highlight surrounding']['respects `v:count` for input surrounding'] = function()
  set_lines({ '(a(b(c)b)a)' })
  set_cursor(1, 5)
  type_keys('2sh', ')')
  -- Check this only on Neovim>=0.11, as there is a slight change in
  -- highlighting command line area
  if child.fn.has('nvim-0.11') == 1 then child.expect_screenshot() end

  -- Should give informative message on failure
  child.set_size(10, 80)
  child.o.cmdheight = 10
  set_lines({ '(a)' })
  set_cursor(1, 0)
  type_keys('2sh', ')')

  has_message_about_not_found(')', nil, nil, 2)
end

T['Highlight surrounding']['respects `vim.{g,b}.minisurround_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    -- Check this only on Neovim>=0.11, as there is a slight change in
    -- highlighting command line area
    if child.fn.has('nvim-0.11') == 0 then return end

    child[var_type].minisurround_disable = true

    set_lines({ '(aaa)', 'bbb' })
    set_cursor(1, 2)
    type_keys('sh', ')')
    child.poke_eventloop()

    -- Shouldn't highlight anything (instead moves cursor with `)` motion)
    child.expect_screenshot()
  end,
})

T['Highlight surrounding']['respects `vim.b.minisurround_config`'] = function()
  child.b.minisurround_config = {
    custom_surroundings = { ['<'] = { input = { '>().-()<' } } },
    highlight_duration = 5 * small_time,
  }
  validate_edit({ '>aaa<' }, { 1, 2 }, { 'aaa' }, { 1, 0 }, type_keys, 'sd', '<')

  set_lines({ '>aaa<', 'bbb' })
  set_cursor(1, 2)
  type_keys('sh', '<')
  child.poke_eventloop()
  child.expect_screenshot({ ignore_attr = { 5 } })

  -- Should stop highlighting after duration from local config
  sleep(5 * small_time + small_time)
  child.expect_screenshot({ ignore_attr = { 5 } })
end

T['Search method'] = new_set()

T['Search method']['works with "cover_or_prev"'] = function()
  reload_module({ search_method = 'cover_or_prev' })
  local f = function() type_keys('sr', ')', '>') end

  -- Works (on same line and on multiple lines)
  validate_edit({ '(aaa) bbb' }, { 1, 7 }, { '<aaa> bbb' }, { 1, 1 }, f)
  validate_edit({ '(aaa)', 'bbb' }, { 2, 0 }, { '<aaa>', 'bbb' }, { 1, 1 }, f)

  -- Should prefer covering surrounding if both are on the same line
  validate_edit({ '(aaa) (bbb)' }, { 1, 8 }, { '(aaa) <bbb>' }, { 1, 7 }, f)
  validate_edit({ '((aaa) bbb)' }, { 1, 8 }, { '<(aaa) bbb>' }, { 1, 1 }, f)

  -- Should prefer covering surrounding if both are not on the same line
  validate_edit({ '(aaa) (', 'bbb)' }, { 2, 0 }, { '(aaa) <', 'bbb>' }, { 1, 6 }, f)

  -- Should prefer "previous" if it is on the same line, but covering is not
  validate_edit({ '(aaa) (bbb', ')' }, { 1, 8 }, { '<aaa> (bbb', ')' }, { 1, 1 }, f)

  -- Should ignore presence of "next" surrounding (even on same line)
  validate_edit({ '(aaa) bbb (ccc)' }, { 1, 7 }, { '<aaa> bbb (ccc)' }, { 1, 1 }, f)
  validate_edit({ '(aaa)', 'bbb (ccc)' }, { 2, 1 }, { '<aaa>', 'bbb (ccc)' }, { 1, 1 }, f)
  validate_edit({ '(aaa) (', 'bbb (ccc))' }, { 2, 0 }, { '(aaa) <', 'bbb (ccc)>' }, { 1, 6 }, f)
end

T['Search method']['works with "cover_or_next"'] = function()
  reload_module({ search_method = 'cover_or_next' })
  local f = function() type_keys('sr', ')', '>') end

  -- Works (on same line and on multiple lines)
  validate_edit({ 'aaa (bbb)' }, { 1, 0 }, { 'aaa <bbb>' }, { 1, 5 }, f)
  validate_edit({ 'aaa', '(bbb)' }, { 1, 0 }, { 'aaa', '<bbb>' }, { 2, 1 }, f)

  -- Should prefer covering surrounding if both are on the same line
  validate_edit({ '(aaa) (bbb)' }, { 1, 2 }, { '<aaa> (bbb)' }, { 1, 1 }, f)
  validate_edit({ '(aaa (bbb))' }, { 1, 2 }, { '<aaa (bbb)>' }, { 1, 1 }, f)

  -- Should prefer covering surrounding if both are not on the same line
  validate_edit({ '(aaa', ') (bbb)' }, { 1, 2 }, { '<aaa', '> (bbb)' }, { 1, 1 }, f)

  -- Should prefer "next" if it is on the same line, but covering is not
  validate_edit({ '(', 'aaa) (bbb)' }, { 2, 1 }, { '(', 'aaa) <bbb>' }, { 2, 6 }, f)

  -- Should ignore presence of "previous" surrounding (even on same line)
  validate_edit({ '(aaa) bbb (ccc)' }, { 1, 7 }, { '(aaa) bbb <ccc>' }, { 1, 11 }, f)
  validate_edit({ '(aaa) bbb', '(ccc)' }, { 1, 7 }, { '(aaa) bbb', '<ccc>' }, { 2, 1 }, f)
  validate_edit({ '(aaa) (', '(bbb) ccc)' }, { 2, 7 }, { '(aaa) <', '(bbb) ccc>' }, { 1, 6 }, f)
end

T['Search method']['works with "cover_or_nearest"'] = function()
  reload_module({ search_method = 'cover_or_nearest' })
  local f = function() type_keys('sr', ')', '>') end

  -- Works (on same line and on multiple lines)
  validate_edit({ '(aaa) bbb (ccc)' }, { 1, 6 }, { '<aaa> bbb (ccc)' }, { 1, 1 }, f)
  validate_edit({ '(aaa) bbb (ccc)' }, { 1, 7 }, { '<aaa> bbb (ccc)' }, { 1, 1 }, f)
  validate_edit({ '(aaa) bbb (ccc)' }, { 1, 8 }, { '(aaa) bbb <ccc>' }, { 1, 11 }, f)

  validate_edit({ '(aaa)', 'bbb', '(ccc)' }, { 2, 0 }, { '<aaa>', 'bbb', '(ccc)' }, { 1, 1 }, f)
  validate_edit({ '(aaa)', 'bbb', '(ccc)' }, { 2, 1 }, { '<aaa>', 'bbb', '(ccc)' }, { 1, 1 }, f)
  validate_edit({ '(aaa)', 'bbb', '(ccc)' }, { 2, 2 }, { '(aaa)', 'bbb', '<ccc>' }, { 3, 1 }, f)

  -- Should prefer covering surrounding if both are on the same line
  validate_edit({ '(aaa) (bbb) (ccc)' }, { 1, 7 }, { '(aaa) <bbb> (ccc)' }, { 1, 7 }, f)
  validate_edit({ '((aaa) bbb (ccc))' }, { 1, 7 }, { '<(aaa) bbb (ccc)>' }, { 1, 1 }, f)

  -- Should prefer covering surrounding if both are not on the same line
  validate_edit({ '(aaa) (', 'bbb', ') (ccc)' }, { 2, 0 }, { '(aaa) <', 'bbb', '> (ccc)' }, { 1, 6 }, f)

  -- Should prefer "nearest" if it is on the same line, but covering is not
  validate_edit({ '(aaa) (', 'bbb) (ccc)' }, { 2, 1 }, { '(aaa) (', 'bbb) <ccc>' }, { 2, 6 }, f)

  -- Computes "nearest" based on closest part of candidate surroundings (based
  -- on distance between *left* part of current cell and span edges)
  validate_edit({ '(aaaaaaa) b  (c)' }, { 1, 7 }, { '<aaaaaaa> b  (c)' }, { 1, 1 }, f)
  validate_edit({ '(a)   b (ccccccc)' }, { 1, 6 }, { '(a)   b <ccccccc>' }, { 1, 9 }, f)

  -- If either "previous" or "next" is missing, should return the present one
  validate_edit({ '(aaa) bbb' }, { 1, 7 }, { '<aaa> bbb' }, { 1, 1 }, f)
  validate_edit({ '(aaa)', 'bbb' }, { 2, 0 }, { '<aaa>', 'bbb' }, { 1, 1 }, f)
  validate_edit({ 'aaa (bbb)' }, { 1, 0 }, { 'aaa <bbb>' }, { 1, 5 }, f)
  validate_edit({ 'aaa', '(bbb)' }, { 1, 0 }, { 'aaa', '<bbb>' }, { 2, 1 }, f)
end

T['Search method']['throws error on incorrect `config.search_method`'] = function()
  child.lua([[MiniSurround.config.search_method = 'aaa']])
  local lines = { 'aaa (bbb)' }
  -- Avoid hit-enter-prompt from three big error message
  child.o.cmdheight = 40

  set_lines(lines)
  set_cursor(1, 0)
  expect.error(function() type_keys('sd', ')') end, 'one of')
  eq(get_lines(), lines)
  eq(get_cursor(), { 1, 0 })
end

T['Search method']['respects `vim.b.minisurround_config`'] = function()
  child.b.minisurround_config = { search_method = 'cover_or_next' }
  validate_edit({ 'aaa (bbb)' }, { 1, 0 }, { 'aaa <bbb>' }, { 1, 5 }, type_keys, 'sr', ')', '>')
end

-- Surroundings ---------------------------------------------------------------
T['Builtin'] = new_set()

T['Builtin']['Bracket'] = new_set()

T['Builtin']['Bracket']['works with open character'] = function()
  local validate = function(key, pair)
    -- Should work as input surrounding (by removing )
    local input = pair:sub(1, 1) .. '  aaa  ' .. pair:sub(2, 2)
    validate_edit({ input }, { 1, 2 }, { 'aaa' }, { 1, 0 }, type_keys, 'sd', key)

    -- Should work as output surrounding
    local output = string.format('%s aaa %s', pair:sub(1, 1), pair:sub(2, 2))
    validate_edit({ '_aaa_' }, { 1, 2 }, { output }, { 1, 2 }, type_keys, 'sr', '_', key)
  end

  validate('(', '()')
  validate('[', '[]')
  validate('{', '{}')
  validate('<', '<>')
end

T['Builtin']['Bracket']['works with close character'] = function()
  local validate = function(key, pair)
    -- Should work as input surrounding (by removing )
    local input = pair:sub(1, 1) .. '  aaa  ' .. pair:sub(2, 2)
    validate_edit({ input }, { 1, 2 }, { '  aaa  ' }, { 1, 0 }, type_keys, 'sd', key)

    -- Should work as output surrounding
    local output = pair:sub(1, 1) .. 'aaa' .. pair:sub(2, 2)
    validate_edit({ '_aaa_' }, { 1, 2 }, { output }, { 1, 1 }, type_keys, 'sr', '_', key)
  end

  validate(')', '()')
  validate(']', '[]')
  validate('}', '{}')
  validate('>', '<>')
end

-- All remaining tests are done with ')' and '>' in hope that others work
-- similarly
T['Builtin']['Bracket']['does not work in some cases'] = function()
  -- Although, it would be great if it did
  local f = function() type_keys('sr', ')', '>') end

  -- It does not take into account that part is inside string
  validate_edit({ [[(a, ')', b)]] }, { 1, 1 }, { "<a, '>', b)" }, { 1, 1 }, f)

  -- It does not take into account that part is inside comment
  child.bo.commentstring = '# %s'
  validate_edit({ '(a', '# )', 'b)' }, { 1, 1 }, { '<a', '# >', 'b)' }, { 1, 1 }, f)
end

T['Builtin']['Bracket']['is indeed balanced'] = function()
  local f = function() type_keys('sr', ')', '>') end

  validate_edit({ '(a())' }, { 1, 1 }, { '<a()>' }, { 1, 1 }, f)
  validate_edit({ '(()a)' }, { 1, 3 }, { '<()a>' }, { 1, 1 }, f)

  validate_edit({ '((()))' }, { 1, 0 }, { '<(())>' }, { 1, 1 }, f)
  validate_edit({ '((()))' }, { 1, 1 }, { '(<()>)' }, { 1, 2 }, f)
  validate_edit({ '((()))' }, { 1, 2 }, { '((<>))' }, { 1, 3 }, f)
  validate_edit({ '((()))' }, { 1, 3 }, { '((<>))' }, { 1, 3 }, f)
  validate_edit({ '((()))' }, { 1, 4 }, { '(<()>)' }, { 1, 2 }, f)
  validate_edit({ '((()))' }, { 1, 5 }, { '<(())>' }, { 1, 1 }, f)
end

T['Builtin']['Brackets alias'] = new_set()

T['Builtin']['Brackets alias']['works'] = function()
  local f

  -- Input
  f = function() type_keys('sd', 'b') end
  validate_edit({ '(aa)' }, { 1, 0 }, { 'aa' }, { 1, 0 }, f)
  validate_edit({ '[aa]' }, { 1, 0 }, { 'aa' }, { 1, 0 }, f)
  validate_edit({ '{aa}' }, { 1, 0 }, { 'aa' }, { 1, 0 }, f)

  -- Output
  f = function() type_keys('sr', '_', 'b') end
  validate_edit({ '_aa_' }, { 1, 0 }, { '(aa)' }, { 1, 1 }, f)

  -- Balanced
  f = function() type_keys('sd', 'b') end
  validate_edit({ '(aa())' }, { 1, 0 }, { 'aa()' }, { 1, 0 }, f)
  validate_edit({ '[aa[]]' }, { 1, 0 }, { 'aa[]' }, { 1, 0 }, f)
  validate_edit({ '{aa{}}' }, { 1, 0 }, { 'aa{}' }, { 1, 0 }, f)
end

T['Builtin']['Quotes alias'] = new_set()

T['Builtin']['Quotes alias']['works'] = function()
  local f

  -- Input
  f = function() type_keys('sd', 'q') end
  validate_edit({ "'aa'" }, { 1, 0 }, { 'aa' }, { 1, 0 }, f)
  validate_edit({ '"aa"' }, { 1, 0 }, { 'aa' }, { 1, 0 }, f)
  validate_edit({ '`aa`' }, { 1, 0 }, { 'aa' }, { 1, 0 }, f)

  -- Output
  f = function() type_keys('sr', '_', 'q') end
  validate_edit({ '_aa_' }, { 1, 0 }, { '"aa"' }, { 1, 1 }, f)

  -- Not balanced
  f = function() type_keys('sd', 'q') end
  validate_edit({ "'aa'bb'cc'" }, { 1, 4 }, { "'aabbcc'" }, { 1, 3 }, f)
  validate_edit({ '"aa"bb"cc"' }, { 1, 4 }, { '"aabbcc"' }, { 1, 3 }, f)
  validate_edit({ '`aa`bb`cc`' }, { 1, 4 }, { '`aabbcc`' }, { 1, 3 }, f)
end

T['Builtin']['Default'] = new_set()

T['Builtin']['Default']['works'] = function()
  local validate = function(key)
    local s = key .. 'aaa' .. key

    -- Should work as input surrounding
    validate_edit({ s }, { 1, 2 }, { 'aaa' }, { 1, 0 }, type_keys, 'sd', key)

    -- Should work as output surrounding
    validate_edit({ '(aaa)' }, { 1, 2 }, { s }, { 1, 1 }, type_keys, 'sr', ')', key)
  end

  validate(' ')
  validate('_')
  validate('*')
  validate('"')
  validate("'")
end

T['Builtin']['Default']['does not work in some cases'] = function()
  -- Although, it would be great if it did
  local f = function() type_keys('sr', '_', '>') end

  -- It does not take into account that part is inside string
  validate_edit({ [[_a, '_', b_]] }, { 1, 1 }, { "<a, '>', b_" }, { 1, 1 }, f)

  -- It does not take into account that part is inside comment
  child.bo.commentstring = '# %s'
  validate_edit({ '_a', '# _', 'b_' }, { 1, 1 }, { '<a', '# >', 'b_' }, { 1, 1 }, f)
end

T['Builtin']['Default']['detects covering with smallest width'] = function()
  local f = function() type_keys('sr', '"', ')') end

  validate_edit({ '"a"aa"' }, { 1, 2 }, { '(a)aa"' }, { 1, 1 }, f)
  validate_edit({ '"aa"a"' }, { 1, 3 }, { '"aa(a)' }, { 1, 4 }, f)

  validate_edit({ '"""a"""' }, { 1, 3 }, { '""(a)""' }, { 1, 3 }, f)
end

T['Builtin']['Default']['works in edge cases'] = function()
  local f = function() type_keys('sr', '*', ')') end

  -- Consecutive identical matching characters
  validate_edit({ '****' }, { 1, 0 }, { '()**' }, { 1, 1 }, f)
  validate_edit({ '****' }, { 1, 1 }, { '()**' }, { 1, 1 }, f)
  validate_edit({ '****' }, { 1, 2 }, { '*()*' }, { 1, 2 }, f)
  validate_edit({ '****' }, { 1, 3 }, { '**()' }, { 1, 3 }, f)
end

T['Builtin']['Default']['supports any identifier which can be `getcharstr()` output'] = function()
  validate_edit({ 'aaa' }, { 1, 0 }, { 'ыaaaы' }, { 1, 2 }, type_keys, 'sa', 'iw', 'ы')
  validate_edit({ 'ыaaaы' }, { 1, 3 }, { 'aaa' }, { 1, 0 }, type_keys, 'sd', 'ы')
  validate_edit({ '(aaa)' }, { 1, 2 }, { 'ыaaaы' }, { 1, 2 }, type_keys, 'sr', ')', 'ы')

  validate_edit({ 'aaa' }, { 1, 0 }, { '「aaa「' }, { 1, 3 }, type_keys, 'sa', 'iw', '「')
  validate_edit({ '「aaa「' }, { 1, 3 }, { 'aaa' }, { 1, 0 }, type_keys, 'sd', '「')
  validate_edit({ '(aaa)' }, { 1, 1 }, { '「aaa「' }, { 1, 3 }, type_keys, 'sr', ')', '「')

  -- <C-j> is `\n`
  validate_edit({ 'aaa' }, { 1, 0 }, { '', 'aaa', '' }, { 1, 0 }, type_keys, 'sa', 'iw', '<C-j>')
  validate_edit({ 'aaa', 'bbb', 'ccc' }, { 2, 0 }, { 'aaabbbccc' }, { 1, 3 }, type_keys, 'sd', '<C-j>')
  validate_edit({ 'aaa', 'bbb', 'ccc' }, { 2, 0 }, { 'aaa(bbb)ccc' }, { 1, 4 }, type_keys, 'sr', '<C-j>', ')')
end

T['Builtin']['Function call'] = new_set()

T['Builtin']['Function call']['works'] = function()
  -- Should work as input surrounding
  validate_edit({ 'myfunc(aaa)' }, { 1, 8 }, { 'aaa' }, { 1, 0 }, type_keys, 'sd', 'f')

  -- Should work as output surrounding
  validate_edit({ '(aaa)' }, { 1, 2 }, { 'myfunc(aaa)' }, { 1, 7 }, type_keys, 'sr', ')', 'f', 'myfunc<CR>')

  -- Should work with empty arguments
  validate_edit({ 'myfunc()' }, { 1, 0 }, { '' }, { 1, 0 }, type_keys, 'sd', 'f')
end

T['Builtin']['Function call']['does not work in some cases'] = function()
  -- Although, it would be great if it did
  local f = function() type_keys('sr', 'f', '>') end

  -- It does not take into account that part is inside string
  validate_edit({ [[myfunc(a, ')', b)]] }, { 1, 7 }, { "<a, '>', b)" }, { 1, 1 }, f)

  -- It does not take into account that part is inside comment
  child.bo.commentstring = '# %s'
  validate_edit({ 'myfunc(a', '# )', 'b)' }, { 1, 7 }, { '<a', '# >', 'b)' }, { 1, 1 }, f)
end

T['Builtin']['Function call']['is detected with "_" and "." in name'] = function()
  validate_edit({ 'my_func(aaa)' }, { 1, 9 }, { 'aaa' }, { 1, 0 }, type_keys, 'sd', 'f')
  validate_edit({ 'my.func(aaa)' }, { 1, 9 }, { 'aaa' }, { 1, 0 }, type_keys, 'sd', 'f')
  validate_edit({ 'big-new_my.func(aaa)' }, { 1, 17 }, { 'big-aaa' }, { 1, 4 }, type_keys, 'sd', 'f')
  validate_edit({ 'big new_my.func(aaa)' }, { 1, 17 }, { 'big aaa' }, { 1, 4 }, type_keys, 'sd', 'f')

  validate_edit({ '[(myfun(aaa))]' }, { 1, 9 }, { '[(aaa)]' }, { 1, 2 }, type_keys, 'sd', 'f')
end

T['Builtin']['Function call']['works in different parts of line and neighborhood'] = function()
  -- This check is viable because of complex nature of Lua patterns
  validate_edit({ 'myfunc(aaa)' }, { 1, 8 }, { 'aaa' }, { 1, 0 }, type_keys, 'sd', 'f')
  validate_edit({ 'Hello myfunc(aaa)' }, { 1, 14 }, { 'Hello aaa' }, { 1, 6 }, type_keys, 'sd', 'f')
  validate_edit({ 'myfunc(aaa) world' }, { 1, 8 }, { 'aaa world' }, { 1, 0 }, type_keys, 'sd', 'f')
  validate_edit({ 'Hello myfunc(aaa) world' }, { 1, 14 }, { 'Hello aaa world' }, { 1, 6 }, type_keys, 'sd', 'f')

  --stylua: ignore start
  validate_edit({ 'myfunc(aaa)', 'Hello', 'world' }, { 1, 8 }, { 'aaa', 'Hello', 'world' }, { 1, 0 }, type_keys, 'sd', 'f')
  validate_edit({ 'Hello', 'myfunc(aaa)', 'world' }, { 2, 8 }, { 'Hello', 'aaa', 'world' }, { 2, 0 }, type_keys, 'sd', 'f')
  validate_edit({ 'Hello', 'world', 'myfunc(aaa)' }, { 3, 8 }, { 'Hello', 'world', 'aaa' }, { 3, 0 }, type_keys, 'sd', 'f')
  --stylua: ignore end
end

T['Builtin']['Function call']['has limited support of multibyte characters'] = function()
  -- Due to limitations of Lua patterns used for detecting surrounding, it
  -- currently doesn't support detecting function calls with multibyte
  -- character in name. It would be great to fix this.
  expect.error(function() validate_edit({ 'ыыы(aaa)' }, { 1, 8 }, { 'aaa' }, { 1, 0 }, type_keys, 'sd', 'f') end)

  -- Should work in output surrounding
  validate_edit({ '(aaa)' }, { 1, 2 }, { 'ыыы(aaa)' }, { 1, 7 }, type_keys, 'sr', ')', 'f', 'ыыы<CR>')
end

T['Builtin']['Function call']['handles <C-c>, <Esc>, <CR> in user input'] = function()
  -- Should do nothing on `<C-c>` and `<Esc>`
  validate_edit({ '(aaa)' }, { 1, 2 }, { '(aaa)' }, { 1, 2 }, type_keys, 1, 'sr', ')', 'f', '<Esc>')
  validate_edit({ '(aaa)' }, { 1, 2 }, { '(aaa)' }, { 1, 2 }, type_keys, 1, 'sr', ')', 'f', '<C-c>')

  -- Should treat `<CR>` as empty string input
  validate_edit({ '[aaa]' }, { 1, 2 }, { '(aaa)' }, { 1, 1 }, type_keys, 'sr', ']', 'f', '<CR>')
end

T['Builtin']['Function call']['colors its prompts'] = function()
  child.set_size(5, 40)

  set_lines({ '(aaa)' })
  set_cursor(1, 2)
  type_keys('sr', ')', 'f', 'hello')
  child.expect_screenshot()
  type_keys('<CR>')

  -- Should clean command line afterwards
  child.expect_screenshot()
end

T['Builtin']['Tag'] = new_set()

T['Builtin']['Tag']['works'] = function()
  -- Should work as input surrounding
  validate_edit({ '<x>aaa</x>' }, { 1, 4 }, { 'aaa' }, { 1, 0 }, type_keys, 'sd', 't')

  -- Should work as output surrounding
  validate_edit({ '(aaa)' }, { 1, 2 }, { '<x>aaa</x>' }, { 1, 3 }, type_keys, 'sr', ')', 't', 'x<CR>')

  -- Should work with empty tag name
  validate_edit({ '<>aaa</>' }, { 1, 3 }, { 'aaa' }, { 1, 0 }, type_keys, 'sd', 't')

  -- Should work with empty inside content
  validate_edit({ '<x></x>' }, { 1, 2 }, { '' }, { 1, 0 }, type_keys, 'sd', 't')
end

T['Builtin']['Tag']['does not work in some cases'] = function()
  -- Although, it would be great if it did
  local f = function() type_keys('sr', 't', '>') end

  -- It does not take into account that part is inside string
  validate_edit({ [[<x>a, '</x>', b</x>]] }, { 1, 3 }, { "<a, '>', b</x>" }, { 1, 1 }, f)

  -- It does not take into account that part is inside comment
  child.bo.commentstring = '# %s'
  validate_edit({ '<x>a', '# </x>', 'b</x>' }, { 1, 3 }, { '<a', '# >', 'b</x>' }, { 1, 1 }, f)

  -- Tags result into smallest width
  validate_edit({ '<x><x></x></x>' }, { 1, 1 }, { '<x><x></x></x>' }, { 1, 1 }, type_keys, 'sr', 't', '.')

  child.lua([[MiniSurround.config.search_method = 'cover_or_next']])
  validate_edit({ '<x><x></x></x>' }, { 1, 1 }, { '<x>..</x>' }, { 1, 4 }, type_keys, 'sr', 't', '.')
  child.lua([[MiniSurround.config.search_method = 'cover']])

  -- Don't work at end of self-nesting tags
  validate_edit({ '<x><x></x></x>' }, { 1, 12 }, { '<x><x></x></x>' }, { 1, 12 }, type_keys, 'sr', 't')
  has_message_about_not_found('t')
end

T['Builtin']['Tag']['detects tag with the same name'] = function()
  validate_edit({ '<x><y>a</x></y>' }, { 1, 1 }, { '_<y>a_</y>' }, { 1, 1 }, type_keys, 'sr', 't', '_')
end

T['Builtin']['Tag']['allows extra symbols in opening tag on input'] = function()
  validate_edit({ '<x bbb cc_dd!>aaa</x>' }, { 1, 15 }, { '_aaa_' }, { 1, 1 }, type_keys, 'sr', 't', '_')

  -- Symbol `<` is not allowed
  validate_edit({ '<x <>aaa</x>' }, { 1, 6 }, { '<x <>aaa</x>' }, { 1, 6 }, type_keys, 'sr', 't')
  has_message_about_not_found('t')
end

T['Builtin']['Tag']['allows extra symbols in opening tag on output'] = function()
  validate_edit({ 'aaa' }, { 1, 0 }, { '<a b>aaa</a>' }, { 1, 5 }, type_keys, 'sa', 'iw', 't', 'a b', '<CR>')
  validate_edit({ '<a b>aaa</a>' }, { 1, 5 }, { '<a c>aaa</a>' }, { 1, 5 }, type_keys, 'sr', 't', 't', 'a c', '<CR>')
end

T['Builtin']['Tag']['detects covering with smallest width'] = function()
  local f = function() type_keys('sr', 't', '_') end

  -- In all cases width of `<y>...</y>` is smaller than of `<x>...</x>`
  validate_edit({ '<x>  <y>a</x></y>' }, { 1, 8 }, { '<x>  _a</x>_' }, { 1, 6 }, f)
  validate_edit({ '<y><x>a</y>  </x>' }, { 1, 6 }, { '_<x>a_  </x>' }, { 1, 1 }, f)

  -- Width should be from the left-most point to right-most
  validate_edit({ '<y><x bbb>a</y></x>' }, { 1, 10 }, { '_<x bbb>a_</x>' }, { 1, 1 }, f)

  -- Works with identical nested tags
  validate_edit({ '<x><x>aaa</x></x>' }, { 1, 7 }, { '<x>_aaa_</x>' }, { 1, 4 }, f)
end

T['Builtin']['Tag']['works in edge cases'] = function()
  local f = function() type_keys('sr', 't', '_') end

  -- Nesting different tags
  validate_edit({ '<x><y></y></x>' }, { 1, 1 }, { '_<y></y>_' }, { 1, 1 }, f)
  validate_edit({ '<x><y></y></x>' }, { 1, 4 }, { '<x>__</x>' }, { 1, 4 }, f)

  -- End of overlapping tags
  validate_edit({ '<y><x></y></x>' }, { 1, 12 }, { '<y>_</y>_' }, { 1, 4 }, f)

  -- `>` between tags
  validate_edit({ '<x>>aaa</x>' }, { 1, 5 }, { '_>aaa_' }, { 1, 1 }, f)

  -- Similar but different names shouldn't match
  validate_edit({ '<xy>aaa</x>' }, { 1, 5 }, { '<xy>aaa</x>' }, { 1, 5 }, type_keys, 'sd', 't')
end

T['Builtin']['Tag']['has limited support of multibyte characters'] = function()
  -- Due to limitations of Lua patterns used for detecting surrounding, it
  -- currently doesn't support detecting tag with multibyte character in
  -- name. It would be great to fix this.
  expect.error(function() validate_edit({ '<ы>aaa</ы>' }, { 1, 5 }, { 'aaa' }, { 1, 0 }, type_keys, 'sd', 't') end)

  -- Should work in output surrounding
  validate_edit({ '(aaa)' }, { 1, 8 }, { '<ы>aaa</ы>' }, { 1, 4 }, type_keys, 'sr', ')', 't', 'ы<CR>')
end

T['Builtin']['Tag']['handles <C-c>, <Esc>, <CR> in user input'] = function()
  -- Should do nothing on `<C-c>` and `<Esc>`
  validate_edit({ '(aaa)' }, { 1, 2 }, { '(aaa)' }, { 1, 2 }, type_keys, 1, 'sr', ')', 't', '<Esc>')
  validate_edit({ '(aaa)' }, { 1, 2 }, { '(aaa)' }, { 1, 2 }, type_keys, 1, 'sr', ')', 't', '<C-c>')

  -- Should treat `<CR>` as empty string input
  validate_edit({ '(aaa)' }, { 1, 2 }, { '<>aaa</>' }, { 1, 2 }, type_keys, 'sr', ')', 't', '<CR>')
end

T['Builtin']['Tag']['colors its prompts'] = function()
  child.set_size(5, 40)

  set_lines({ '(aaa)' })
  set_cursor(1, 2)
  type_keys('sr', ')', 't', 'hello')
  child.expect_screenshot()
  type_keys('<CR>')

  -- Should clean command line afterwards
  child.expect_screenshot()
end

T['Builtin']['User prompt'] = new_set()

T['Builtin']['User prompt']['works'] = function()
  -- Should work as input surrounding
  validate_edit({ '%*aaa*%' }, { 1, 3 }, { 'aaa' }, { 1, 0 }, type_keys, 'sd', '?', '%*<CR>', '*%<CR>')

  -- Should work as output surrounding
  validate_edit({ '(aaa)' }, { 1, 2 }, { '%*aaa*%' }, { 1, 2 }, type_keys, 'sr', ')', '?', '%*<CR>', '*%<CR>')
end

T['Builtin']['User prompt']['does not work in some cases'] = function()
  -- Although, it would be great if it did
  local f = function() type_keys('sr', '?', '**<CR>', '**<CR>', '>') end

  -- It does not take into account that part is inside string
  validate_edit({ [[**a, '**', b**]] }, { 1, 2 }, { "<a, '>', b**" }, { 1, 1 }, f)

  -- It does not take into account that part is inside comment
  child.bo.commentstring = '# %s'
  validate_edit({ '**a', '# **', 'b**' }, { 1, 2 }, { '<a', '# >', 'b**' }, { 1, 1 }, f)

  -- It does not work sometimes in presence of many identical valid parts
  -- (basically because it is a `%(.-%)` and not `%(.*%)`).
  f = function() type_keys('sr', '?', '(<CR>', ')<CR>', '>') end
  validate_edit({ '((()))' }, { 1, 3 }, { '((<>))' }, { 1, 3 }, f)
  validate_edit({ '((()))' }, { 1, 4 }, { '((()))' }, { 1, 4 }, f)
  validate_edit({ '((()))' }, { 1, 5 }, { '((()))' }, { 1, 5 }, f)
end

T['Builtin']['User prompt']['detects covering with smallest width'] = function()
  local f = function() type_keys('sr', '?', '**<CR>', '**<CR>', ')') end

  validate_edit({ '**a**aa**' }, { 1, 4 }, { '(a)aa**' }, { 1, 1 }, f)
  validate_edit({ '**aa**a**' }, { 1, 4 }, { '**aa(a)' }, { 1, 5 }, f)
end

T['Builtin']['User prompt']['works in edge cases'] = function()
  local f = function() type_keys('sr', '?', '(<CR>', ')<CR>', '>') end

  -- Having `.-` in pattern means the smallest matching span
  validate_edit({ '(())' }, { 1, 0 }, { '(())' }, { 1, 0 }, f)
  validate_edit({ '(())' }, { 1, 1 }, { '(<>)' }, { 1, 2 }, f)
end

T['Builtin']['User prompt']['works with multibyte characters in parts'] = function()
  -- Should work as input surrounding
  validate_edit({ 'ыtttю' }, { 1, 3 }, { 'ttt' }, { 1, 0 }, type_keys, 'sd', '?', 'ы<CR>', 'ю<CR>')

  -- Should work as output surrounding
  validate_edit({ 'ыtttю' }, { 1, 3 }, { '(ttt)' }, { 1, 1 }, type_keys, 'sr', '?', 'ы<CR>', 'ю<CR>', ')')
end

T['Builtin']['User prompt']['handles <C-c>, <Esc>, <CR> in user input'] = function()
  local validate_single = function(...)
    child.ensure_normal_mode()
    -- Wait before every keygroup because otherwise it seems to randomly
    -- break for `<C-c>`
    validate_edit({ '(aaa)' }, { 1, 2 }, { '(aaa)' }, { 1, 2 }, type_keys, 10, ...)
  end

  local validate_nothing = function(key)
    -- Should do nothing on any `<C-c>` and `<Esc>` (in both input and output)
    validate_single('sr', '?', key)
    validate_single('sr', '?', '(<CR>', key)
    validate_single('sr', ')', '?', key)
    validate_single('sr', ')', '?', '*<CR>', key)
  end

  validate_nothing('<Esc>')
  validate_nothing('<C-c>')

  -- Should treat `<CR>` as empty string in output surrounding
  validate_edit({ '(aaa)' }, { 1, 2 }, { '_aaa' }, { 1, 1 }, type_keys, 'sr', ')', '?', '_<CR>', '<CR>')
  validate_edit({ '(aaa)' }, { 1, 2 }, { 'aaa_' }, { 1, 0 }, type_keys, 'sr', ')', '?', '<CR>', '_<CR>')
  validate_edit({ '(aaa)' }, { 1, 2 }, { 'aaa' }, { 1, 0 }, type_keys, 'sr', ')', '?', '<CR>', '<CR>')

  -- Should stop on `<CR>` in input surrounding because can't use empty
  -- string in pattern search
  validate_edit({ '**aaa**' }, { 1, 3 }, { '**aaa**' }, { 1, 3 }, type_keys, 'sr', '?', '<CR>')
  validate_edit({ '**aaa**' }, { 1, 3 }, { '**aaa**' }, { 1, 3 }, type_keys, 'sr', '?', '**<CR>', '<CR>')
end

T['Builtin']['User prompt']['colors its prompts'] = function()
  child.set_size(5, 40)

  set_lines({ '(aaa)' })
  set_cursor(1, 2)
  type_keys('sr', ')', '?', 'xxx')
  child.expect_screenshot()
  type_keys('<CR>', 'yyy')
  child.expect_screenshot()
  type_keys('<CR>')

  -- Should clean command line afterwards
  child.expect_screenshot()
end

local set_custom_surr = function(tbl) child.lua('MiniSurround.config.custom_surroundings = ' .. vim.inspect(tbl)) end

T['Custom surrounding'] = new_set()

T['Custom surrounding']['works'] = function()
  set_custom_surr({ q = { input = { '@().-()#' }, output = { left = '@', right = '#' } } })

  validate_edit({ '@aaa#' }, { 1, 2 }, { 'aaa' }, { 1, 0 }, type_keys, 'sd', 'q')
  validate_edit({ '(aaa)' }, { 1, 2 }, { '@aaa#' }, { 1, 1 }, type_keys, 'sr', ')', 'q')
end

T['Custom surrounding']['supports any identifier which can be `getcharstr()` output'] = function()
  set_custom_surr({
    ['\22'] = { input = { '@().-()#' }, output = { left = '@', right = '#' } },
    ['ы'] = { input = { 'Ы().-()Ы' }, output = { left = 'Ы', right = 'Ы' } },
    ['「'] = { input = { '「().-()」' }, output = { left = '「', right = '」' } },
  })

  validate_edit({ ' aaa ' }, { 1, 1 }, { ' 「aaa」 ' }, { 1, 4 }, type_keys, 'sa', 'iw', '「')
  validate_edit({ 'ЫaaaЫ' }, { 1, 3 }, { 'aaa' }, { 1, 0 }, type_keys, 'sd', 'ы')
  validate_edit({ '@aaa#' }, { 1, 2 }, { '「aaa」' }, { 1, 3 }, type_keys, 'sr', '<C-v>', '「')
  validate_edit({ '「aaa」' }, { 1, 3 }, { '@aaa#' }, { 1, 1 }, type_keys, 'sr', '「', '<C-v>')
end

T['Custom surrounding']['overrides builtins'] = function()
  set_custom_surr({ ['('] = { input = { '%(%(().-()%)%)' }, output = { left = '((', right = '))' } } })

  validate_edit({ '((aaa))' }, { 1, 2 }, { 'aaa' }, { 1, 0 }, type_keys, 'sd', '(')
  validate_edit({ 'aaa' }, { 1, 0 }, { '((aaa))' }, { 1, 2 }, type_keys, 'sa', 'iw', '(')
end

T['Custom surrounding']['allows setting partial information'] = function()
  -- Modifying present single character identifier (takes from present)
  set_custom_surr({ [')'] = { output = { left = '( ', right = ' )' } } })

  validate_edit({ '(aaa)' }, { 1, 2 }, { 'aaa' }, { 1, 0 }, type_keys, 'sd', ')')
  validate_edit({ '<aaa>' }, { 1, 2 }, { '( aaa )' }, { 1, 2 }, type_keys, 'sr', '>', ')')

  -- New single character identifier (takes from default)
  set_custom_surr({ ['#'] = { input = { '#_().-()_#' } } })

  -- Should find '#_' and '_#' and extract first and last two characters
  validate_edit({ '_#_aaa_#_' }, { 1, 4 }, { '_aaa_' }, { 1, 1 }, type_keys, 'sd', '#')
  -- `output` should be taken from default
  validate_edit({ '(aaa)' }, { 1, 2 }, { '#aaa#' }, { 1, 1 }, type_keys, 'sr', ')', '#')
end

T['Custom surrounding']['validates captures in extract pattern'] = function()
  -- Avoid hit-enter-prompt from three big error message
  child.o.cmdheight = 40

  local validate = function(line, col, key)
    set_lines({ line })
    set_cursor(1, col)
    expect.error(type_keys, 'two or four empty captures', 'sd', key)

    -- Clear command line to error accumulation and hit-enter-prompt
    type_keys(':<Esc>')
  end

  set_custom_surr({ ['#'] = { input = { '#.-#' } } })
  validate('#a#', 1, '#')

  set_custom_surr({ ['_'] = { input = { '_.-()_' } } })
  validate('_a_', 1, '_')

  set_custom_surr({ ['@'] = { input = { '(@).-(@)' } } })
  validate('@a@', 1, '@')
end

T['Custom surrounding']['works with `.-`'] = function()
  local f = function() type_keys('sr', '#', '>') end

  set_custom_surr({ ['#'] = { input = { '#().-()@' } } })

  -- Using `.-` results into match with smallest width
  validate_edit({ '##@@' }, { 1, 0 }, { '##@@' }, { 1, 0 }, f)
  validate_edit({ '##@@' }, { 1, 1 }, { '#<>@' }, { 1, 2 }, f)

  child.lua([[MiniSurround.config.search_method = 'cover_or_next']])
  validate_edit({ '##@@' }, { 1, 0 }, { '#<>@' }, { 1, 2 }, f)
end

T['Custom surrounding']['works with empty parts in input surrounding'] = function()
  set_custom_surr({ x = { input = { 'x()().-()x()' } } })
  validate_edit1d('axbbbxc', 3, 'axbbbc', 2, type_keys, 'sd', 'x')
  validate_edit1d('axbbbxc', 3, 'ax<bbb>c', 3, type_keys, 'sr', 'x', '>')

  set_custom_surr({ y = { input = { '()y().-y()()' } } })
  validate_edit1d('aybbbyc', 3, 'abbbyc', 1, type_keys, 'sd', 'y')
  validate_edit1d('aybbbyc', 3, 'a<bbby>c', 2, type_keys, 'sr', 'y', '>')

  set_custom_surr({ t = { input = { '()()t.-t()()' } } })
  validate_edit1d('atbbbtc', 3, 'atbbbtc', 1, type_keys, 'sd', 't')
  validate_edit1d('atbbbtc', 3, 'a<tbbbt>c', 2, type_keys, 'sr', 't', '>')
end

T['Custom surrounding']['handles function as surrounding spec'] = function()
  -- Function which returns composed pattern
  child.lua([[MiniSurround.config.custom_surroundings = {
    x = { input = function(...) _G.args = {...}; return {'x()x()x'} end }
  }]])

  validate_edit1d('aaxxxbb', 2, 'aa<x>bb', 3, type_keys, 'sr', 'x', '>')
  -- Should be called without arguments
  eq(child.lua_get('_G.args'), {})

  -- Function which returns region pair
  child.lua([[_G.edge_lines = function()
    local n_lines = vim.fn.line('$')
    return {
      left = {
        from = { line = 1, col = 1 },
        to = { line = 1, col = vim.fn.getline(1):len() },
      },
      right = {
        from = { line = n_lines, col = 1 },
        to = { line = n_lines, col = vim.fn.getline(n_lines):len() },
      },
    }
  end]])
  child.lua('MiniSurround.config.custom_surroundings = { e = { input = _G.edge_lines} }')

  set_lines({ 'aaa', '', 'bbb', '' })
  set_cursor(3, 0)
  validate_edit({ 'aa', 'bb', '' }, { 2, 0 }, { '(', 'bb', ')' }, { 1, 0 }, type_keys, 'sr', 'e', ')')

  -- Function which returns array of region pairs
end

T['Custom surrounding']['handles function as specification item'] = function()
  child.lua([[_G.c_spec = {
    '%b()',
    function(s, init) if init > 1 then return end; return 2, s:len() end,
    '^().*().$'
  }]])
  child.lua([[MiniSurround.config.custom_surroundings = { c = { input = _G.c_spec } }]])
  validate_edit1d('aa(bb)', 3, 'aa(<bb>', 4, type_keys, 'sr', 'c', '>')
end

T['Custom surrounding']['works with special patterns'] = new_set()

T['Custom surrounding']['works with special patterns']['%bxx'] = function()
  -- Avoid hit-enter-prompt from three big error message
  child.o.cmdheight = 40

  -- `%bxx` should represent balanced character
  set_custom_surr({ e = { input = { '%bee', '^e().*()e$' } } })

  local line = 'e e e e e'
  local f = function() type_keys('sr', 'e', '>') end

  for i = 0, 2 do
    validate_edit1d(line, i, '< > e e e', 1, f)
  end
  for i = 4, 6 do
    validate_edit1d(line, i, 'e e < > e', 5, f)
  end

  for _, i in ipairs({ 3, 7, 8 }) do
    validate_edit1d(line, i, 'e e e e e', i, f)
  end
end

T['Custom surrounding']['works with special patterns']['x.-y'] = function()
  child.lua([[MiniSurround.config.search_method = 'cover_or_next']])

  -- `x.-y` should match the smallest possible width
  set_custom_surr({ x = { input = { 'e.-o', '^.().*().$' } } })
  validate_edit1d('e e o o e o', 0, 'e < > o e o', 3, type_keys, 'sr', 'x', '>')
  validate_edit1d('e e o o e o', 0, 'e e o o < >', 9, type_keys, '2sr', 'x', '>')

  -- `x.-y` should work with `a%.-a` and `a.%-a`
  set_custom_surr({ y = { input = { 'y()%.-()y' } } })
  validate_edit1d('y.y yay y..y', 0, '<.> yay y..y', 1, type_keys, 'sr', 'y', '>')
  validate_edit1d('y.y yay y..y', 0, 'y.y yay <..>', 9, type_keys, '2sr', 'y', '>')

  set_custom_surr({ c = { input = { 'c().%-()c' } } })
  validate_edit1d('c_-c c__c c+-c', 0, '<_-> c__c c+-c', 1, type_keys, 'sr', 'c', '>')
  validate_edit1d('c_-c c__c c+-c', 0, 'c_-c c__c <+->', 11, type_keys, '2sr', 'c', '>')

  -- `x.-y` should allow patterns with `+` quantifiers
  -- To improve, force other character in between (`%f[x]x+[^x]-x+%f[^x]`)
  set_custom_surr({ r = { input = { 'r+().-()r+' } } })
  validate_edit1d('rraarr', 0, 'rraa<>', 5, type_keys, 'sr', 'r', '>')
  validate_edit1d('rrrr', 0, 'rr<>', 3, type_keys, 'sr', 'r', '>')
end

T['Custom surrounding']['works with quantifiers in patterns'] = function()
  child.lua([[MiniSurround.config.search_method = 'cover_or_next']])

  set_custom_surr({ x = { input = { '%f[x]x+%f[^x]', '^x().*()x$' } } })
  validate_edit1d('axxaxxx', 0, 'a<>axxx', 2, type_keys, 'sr', 'x', '>')
  validate_edit1d('axxaxxx', 0, 'axxa<x>', 5, type_keys, '2sr', 'x', '>')
end

T['Custom surrounding']['works with multibyte characters'] = function()
  set_custom_surr({ x = { input = { 'ыы фф', '^.-() ().-$' } } })
  validate_edit1d('ыы ыы фф фф', 9, 'ыы < > фф', 6, type_keys, 'sr', 'x', '>')
end

T['Custom surrounding']['documented examples'] = new_set()

T['Custom surrounding']['documented examples']['function call with name from user input'] = function()
  child.lua([[MiniSurround.config.search_method = 'cover_or_next']])
  child.lua([[_G.fun_prompt = function()
    local left_edge = vim.pesc(vim.fn.input('Function name: '))
    return { string.format('%s+%%b()', left_edge), '^.-%(().*()%)$' }
  end]])
  child.lua('MiniSurround.config.custom_surroundings = { F = { input = _G.fun_prompt} }')

  validate_edit1d('aa(xx) bb(xx)', 0, 'aa(xx) <xx>', 8, type_keys, 'sr', 'F', 'bb<CR>', '>')
end

T['Custom surrounding']['documented examples']['first and last buffer lines'] = function()
  child.lua([[_G.edge_lines = function()
    local n_lines = vim.fn.line('$')
    return {
      left = {
        from = { line = 1, col = 1 },
        to = { line = 1, col = vim.fn.getline(1):len() },
      },
      right = {
        from = { line = n_lines, col = 1 },
        to = { line = n_lines, col = vim.fn.getline(n_lines):len() },
      },
    }
  end]])
  child.lua('MiniSurround.config.custom_surroundings = { e = { input = _G.edge_lines} }')

  set_lines({ 'aaa', '', 'bbb', '' })
  set_cursor(3, 0)
  validate_edit({ 'aa', 'bb', '' }, { 2, 0 }, { '(', 'bb', ')' }, { 1, 0 }, type_keys, 'sr', 'e', ')')
end

T['Custom surrounding']['documented examples']['edges of wide lines'] = function()
  child.lua([[MiniSurround.config.search_method = 'cover_or_next']])
  child.lua([[_G.wide_line_edges = function()
    local make_line_region_pair = function(n)
      local left = { line = n, col = 1 }
      local right = { line = n, col = vim.fn.getline(n):len() }
      return { left = { from = left, to = left }, right = { from = right, to = right } }
    end

    local res = {}
    for i = 1, vim.fn.line('$') do
      if vim.fn.getline(i):len() > 80 then table.insert(res, make_line_region_pair(i)) end
    end
    return res
  end]])
  child.lua([[MiniSurround.config.custom_surroundings = { L = { input = _G.wide_line_edges } }]])

  local lines = { string.rep('a', 80), string.rep('b', 81), string.rep('c', 80), string.rep('d', 81) }

  local validate = function(start_line, target_line)
    set_lines(lines)
    set_cursor(start_line, 1)
    type_keys('sr', 'L', '>')
    local target = get_lines()[target_line]
    eq(target:sub(1, 1), '<')
    eq(target:sub(-1, -1), '>')
  end

  validate(1, 2)
  validate(2, 2)

  child.lua([[MiniSurround.config.search_method = 'next']])
  validate(2, 4)

  child.lua([[MiniSurround.config.n_lines = 0]])
  set_lines(lines)
  set_cursor(1, 1)
  type_keys('sr', 'L', '>')
  eq(get_lines(), lines)
end

T['Custom surrounding']['documented examples']['Lua block string'] = function()
  child.lua([=[MiniSurround.config.custom_surroundings = {
    s = { input = { '%[%[().-()%]%]' }, output = { left = '[[', right = ']]' } }
  }]=])
  validate_edit1d('aa[[bb]]cc', 2, 'aa<bb>cc', 3, type_keys, 'sr', 's', '>')
  validate_edit1d('aa(bb)cc', 2, 'aa[[bb]]cc', 4, type_keys, 'sr', ')', 's')
end

T['Custom surrounding']['documented examples']['balanced parenthesis with big enough width'] = function()
  child.lua([[_G.wide_parens_spec = {
    '%b()',
    function(s, init)
      if init > 1 or s:len() < 5 then return end
      return 1, s:len()
    end,
    '^.().*().$'
  }]])
  child.lua('MiniSurround.config.custom_surroundings = { p = { input = _G.wide_parens_spec } }')
  child.lua([[MiniSurround.config.search_method = 'cover_or_next']])

  validate_edit1d('() (a) (aa) (aaa)', 0, '() (a) (aa) <aaa>', 13, type_keys, 'sr', 'p', '>')
end

T['Custom surrounding']['documented examples']['handles function as specification item'] = function()
  child.lua([[_G.c_spec = {
    '%b()',
    function(s, init) if init > 1 then return end; return 2, s:len() end,
    '^().*().$'
  }]])
  child.lua([[MiniSurround.config.custom_surroundings = { c = { input = _G.c_spec } }]])
  validate_edit1d('aa(bb)', 3, 'aa(<bb>', 4, type_keys, 'sr', 'c', '>')
end

T['Custom surrounding']['documented examples']['brackets with newlines'] = function()
  child.lua([=[MiniSurround.config.custom_surroundings = {
    x = { output = { left = '(\n', right = '\n)' } }
  }]=])
  validate_edit({ '  aaa' }, { 1, 2 }, { '  (', 'aaa', ')' }, { 1, 2 }, type_keys, 'sa', 'iw', 'x')
end

return T
