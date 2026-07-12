local helpers = dofile('tests/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
local load_module = function(config) child.mini_load('surround', config) end
local unload_module = function() child.mini_unload('surround') end
local reload_module = function(config) child.mini_reload('surround', config) end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
local sleep = function(ms) helpers.sleep(ms, child) end
local validate_edit = function(...) return child.validate_edit(...) end
local validate_edit1d = function(...) return child.validate_edit1d(...) end

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

local validate_miniinput = function(prompt, scope, input)
  local out = child.lua([[
    local state = MiniInput.get_state()
    if state == nil then return {} end
    return { state.opts.prompt, state.opts.scope, state.input }
  ]])
  eq(out, { prompt, scope, input })
end

-- Time constants
local default_highlight_duraion = 500
local reminder_delay = 1000
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
  expect_config('custom_surroundings', {})
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
    expect.error(function() load_module(config) end, vim.pesc(name) .. '.*' .. vim.pesc(target_type))
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
  local has_surround_map = function(lhs, mode) return child.fn.maparg(lhs, mode):find('[Ss]urround') ~= nil end

  local make_clean_state = function()
    unload_module()
    for _, map in ipairs(child.api.nvim_get_keymap('n')) do
      child.api.nvim_del_keymap('n', map.lhs)
    end
    for _, map in ipairs(child.api.nvim_get_keymap('x')) do
      child.api.nvim_del_keymap('x', map.lhs)
    end
  end

  -- Regular mappings
  eq(has_surround_map('sa', 'n'), true)

  -- Should map "s" to <Nop>, but only if needed
  eq(child.fn.maparg('s', 'n'), '<Nop>')
  eq(child.fn.maparg('s', 'x'), '<Nop>')

  -- Supplying empty string should mean "don't create keymap"
  make_clean_state()
  load_module({ mappings = { add = '' } })
  eq(has_surround_map('sa', 'n'), false)

  -- Extended mappings
  eq(has_surround_map('sdl', 'n'), true)
  eq(has_surround_map('sdn', 'n'), true)

  make_clean_state()
  load_module({ mappings = { delete = '', suffix_last = '' } })
  eq(has_surround_map('sdl', 'n'), false)
  eq(has_surround_map('sdn', 'n'), false)
  eq(has_surround_map('srl', 'n'), false)
  eq(has_surround_map('srn', 'n'), true)

  -- Should precisely set 's' keymap
  make_clean_state()
  load_module({ mappings = { add = 'cs', delete = 'sd', find = '', find_left = '' } })
  eq(child.fn.maparg('s', 'n'), '<Nop>')
  eq(child.fn.maparg('s', 'x'), '')

  -- - Should ignore presence of buffer-local mappings
  local vim_surround_mappings = {
    add = 'ys',
    delete = 'ds',
    find = '',
    find_left = '',
    highlight = '',
    replace = 'cs',
    suffix_last = '',
    suffix_next = '',
  }
  -- - Should also not override already present user mapping for `s`
  make_clean_state()
  child.cmd('nmap s <Cmd>echo 1<CR>')
  load_module({ mappings = vim_surround_mappings })
  eq(child.fn.maparg('s', 'n'), '<Cmd>echo 1<CR>')
  eq(child.fn.maparg('s', 'x'), '')

  -- - Should allow creating a plain `s` as a mapping
  vim_surround_mappings.add = 's'
  make_clean_state()
  load_module({ mappings = vim_surround_mappings })
  eq(has_surround_map('s', 'n'), true)
  eq(has_surround_map('s', 'x'), true)

  -- - Should ignore buffer-local `s` mappings and still create global `<Nop>`
  make_clean_state()
  child.cmd('nmap <buffer> s <Cmd>echo 1<CR>')
  child.cmd('xmap <buffer> s <Cmd>echo 2<CR>')
  load_module()
  eq(child.fn.maparg('s', 'n'), '<Cmd>echo 1<CR>')
  eq(child.fn.maparg('s', 'x'), '<Cmd>echo 2<CR>')

  local get_global_mapping = function(mode, lhs)
    for _, map in ipairs(child.api.nvim_get_keymap(mode)) do
      if map.lhs == lhs then return map end
    end
    return {}
  end
  -- - NOTE: `nvim_get_keymap()` return `rhs=''` if it is mapped to `<Nop>`
  --   For absent mapping it would have been `nil`
  eq(get_global_mapping('n', 's').rhs, '')
  eq(get_global_mapping('x', 's').rhs, '')

  -- - Should work when there are both buffer-local and global mappings
  make_clean_state()
  child.cmd('nmap          s <Cmd>echo 1<CR>')
  child.cmd('nmap <buffer> s <Cmd>echo 10<CR>')
  child.cmd('xmap          s <Cmd>echo 2<CR>')
  child.cmd('xmap <buffer> s <Cmd>echo 20<CR>')

  load_module()

  eq(child.fn.maparg('s', 'n'), '<Cmd>echo 10<CR>')
  eq(child.fn.maparg('s', 'x'), '<Cmd>echo 20<CR>')
  eq(get_global_mapping('n', 's').rhs, '<Cmd>echo 1<CR>')
  eq(get_global_mapping('x', 's').rhs, '<Cmd>echo 2<CR>')
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

T['gen_spec']['input']['treesitter()']['ensures that inner capture is strictly nested'] = function()
  child.lua([[MiniSurround.config.custom_surroundings = {
    C = { input = MiniSurround.gen_spec.input.treesitter({ outer = '@call.outer', inner = '@call.inner' }) },
  }]])
  local lines = { 'local aaa = function(x) end', 'local bbb = function(y) end', 'return aaa(bbb(1))' }

  set_lines(lines)
  set_cursor(3, 7)
  type_keys('sr', 'C', '>')
  eq(get_lines()[3], 'return <bbb(1)>')

  set_lines(lines)
  set_cursor(3, 11)
  type_keys('sr', 'C', '>')
  eq(get_lines()[3], 'return aaa(<1>)')
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

T['gen_spec']['input']['treesitter()']['works with parent of injected language'] = function()
  local lines = {
    'local foo = function()',
    '  vim.cmd([[',
    'set cursorline',
    ']])',
    'end',
  }

  validate_find(lines, { 3, 0 }, { { 4, 2 }, { 5, 2 }, { 1, 12 }, { 2, 1 } }, type_keys, 'sf', 'F')
  validate_no_find(lines, { 1, 0 }, type_keys, 'sf', 'F')
end

T['gen_spec']['input']['treesitter()']['works with injected child language'] = function()
  local lines = {
    'vim.cmd([[',
    'set cursorline',
    'lua local a = function() return true end',
    ']])',
  }
  validate_find(lines, { 1, 0 }, { { 3, 14 } }, type_keys, 'sfn', 'F')
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

T['gen_spec']['input']['treesitter()']['works with row-exclusive, col-0 end range'] = function()
  child.lua([[MiniSurround.config.custom_surroundings = {
    c = { input = MiniSurround.gen_spec.input.treesitter({ outer = '@chunk.outer', inner = '@chunk.inner' }) }
  }]])

  local lines = get_lines()
  validate_find(lines, { 4, 0 }, { { 13, 0 }, { 13, 7 }, { 1, 0 }, { 1, 11 } }, type_keys, 'sf', 'c')
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
  validate_edit({ 'aaa' }, { 1, 0 }, { 'sa', 'iw', ')' }, { '(aaa)' }, { 1, 1 })
  validate_edit({ ' aaa ' }, { 1, 1 }, { 'sa', 'iw', ')' }, { ' (aaa) ' }, { 1, 2 })

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

  validate_edit({ ' aaa ' }, { 1, 1 }, { 'viw', 'sa', ')' }, { ' (aaa) ' }, { 1, 2 })
  eq(child.fn.mode(), 'n')

  -- Does not allow dot-repeat. Should do `dd`.
  type_keys('.')
  eq(get_lines(), { '' })
end

T['Add surrounding']['works in line and block Visual mode'] = function()
  validate_edit({ 'aaa' }, { 1, 0 }, { 'V', 'sa', ')' }, { '(aaa)' }, { 1, 1 })

  validate_edit({ 'aaa', 'bbb' }, { 1, 0 }, { '<C-v>j$', 'sa', ')' }, { '(aaa', 'bbb)' }, { 1, 1 })
end

--stylua: ignore
T['Add surrounding']['respects `config.respect_selection_type` in linewise mode'] = function()
  child.lua('MiniSurround.config.respect_selection_type = true')

  local validate = function(before_lines, before_cursor, after_lines, after_cursor, selection_keys)
    validate_edit(before_lines, before_cursor, { selection_keys, 'sa', ')' }, after_lines, after_cursor)
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
  validate_edit({ 'aaa' }, { 1, 0 }, { 'V', 'sa', 'f', 'ff<CR>' }, { 'ff(', '\taaa', ')' }, { 2, 1 })

  -- General test in Operator-pending mode
  validate_edit({ 'aaa' }, { 1, 0 }, { 'sa', 'ip', ')' }, { '(', '\taaa', ')' }, { 2, 1 })

  -- Respects `expandtab`
  child.o.expandtab = true
  child.o.shiftwidth = 3
  validate({ 'aaa' }, { 1, 0 }, { '(', '   aaa', ')' }, { 2, 3 }, 'V')
end

T['Add surrounding']['respects `config.respect_selection_type` in blockwise mode'] = function()
  -- NOTE: this doesn't work with mix of multibyte and normal characters,
  -- as well as outside of text lines.
  child.lua('MiniSurround.config.respect_selection_type = true')

  local validate = function(before_lines, before_cursor, after_lines, after_cursor, selection_keys)
    validate_edit(before_lines, before_cursor, { selection_keys, 'sa', ')' }, after_lines, after_cursor)
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
  validate_edit({ 'aaa', 'bbb' }, { 1, 1 }, { '<C-v>j', 'sa', 'f', 'ff<CR>' }, { 'aff(a)a', 'bff(b)b' }, { 1, 4 })

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

--stylua: ignore
T['Add surrounding']['places cursor to the right of left surrounding'] = function()
  -- Same line
  validate_edit({ 'aaa' }, { 1, 0 }, { 'sa', 'iw', 'f', 'myfunc', '<CR>' }, { 'myfunc(aaa)' }, { 1, 7 })
  validate_edit({ 'aaa' }, { 1, 0 }, { 'viw', 'sa', 'f', 'myfunc', '<CR>' }, { 'myfunc(aaa)' }, { 1, 7 })
  validate_edit({ 'aaa' }, { 1, 0 }, { 'V', 'sa', 'f', 'myfunc', '<CR>' }, { 'myfunc(aaa)' }, { 1, 7 })

  -- Not the same line
  validate_edit({ 'aaa', 'bbb', 'ccc' }, { 2, 0 }, { 'sa', 'ip', 'f', 'myfunc', '<CR>' }, { 'myfunc(aaa', 'bbb', 'ccc)' }, { 1, 7 })
  validate_edit({ 'aaa', 'bbb', 'ccc' }, { 2, 0 }, { 'vip', 'sa', 'f', 'myfunc', '<CR>' }, { 'myfunc(aaa', 'bbb', 'ccc)' }, { 1, 7 })
  validate_edit({ 'aaa', 'bbb', 'ccc' }, { 2, 0 }, { 'Vip', 'sa', 'f', 'myfunc', '<CR>' }, { 'myfunc(aaa', 'bbb', 'ccc)' }, { 1, 7 })
end

T['Add surrounding']['shows reminder after one idle second'] = function()
  child.set_size(5, 70)
  child.o.cmdheight = 1

  set_lines({ ' aaa ' })
  set_cursor(1, 1)

  -- Execute one time to test if 'needs help message' flag is set per call
  type_keys('sa', 'iw', ')')
  sleep(0.1 * reminder_delay)

  type_keys('sa', 'iw')
  sleep(reminder_delay + small_time)

  -- Should show helper message without adding it to `:messages` and causing
  -- hit-enter-prompt
  eq(get_latest_message(), '')
  child.expect_screenshot()

  -- Should clear afterwards
  type_keys(')')
  child.expect_screenshot()
end

T['Add surrounding']['works with multibyte characters'] = function()
  validate_edit({ '  ыыы  ' }, { 1, 2 }, { 'sa', 'iw', ')' }, { '  (ыыы)  ' }, { 1, 3 })
  validate_edit({ 'ыыы ttt' }, { 1, 2 }, { 'sa', 'iw', ')' }, { '(ыыы) ttt' }, { 1, 1 })
  validate_edit({ 'ttt ыыы' }, { 1, 4 }, { 'sa', 'iw', ')' }, { 'ttt (ыыы)' }, { 1, 5 })

  -- Test 4-byte characters (might be a cause of incorrect marks retrieval)
  --stylua: ignore
  validate_edit({ '🬗 🬗 🬗 🬗 🬗' }, { 1, 20 }, { 'sa', 'iw', ')' }, { '🬗 🬗 🬗 🬗 (🬗)' }, { 1, 21 })
end

T['Add surrounding']['works on whole line'] = function()
  -- Should ignore both indent (leading whitespace) at start line and trailing
  -- whitespace and end line. Should work with both tabs and spaces.
  validate_edit({ ' \t aaa\t ', '' }, { 1, 0 }, { 'sa', '_', ')' }, { ' \t (aaa)\t ', '' }, { 1, 4 })
  validate_edit({ ' \t aaa\t ', '' }, { 1, 0 }, { 'V', 'sa', ')' }, { ' \t (aaa)\t ', '' }, { 1, 4 })
end

T['Add surrounding']['works on multiple lines'] = function()
  local saap = { 'sa', 'ap', ')' }
  local vapsa = { 'Vap', 'sa', ')' }

  -- Should ignore both indent (leading whitespace) at start line and trailing
  -- whitespace and end line. Should work with both tabs and spaces.
  validate_edit({ ' \t aaa ', 'bbb', ' ccc\t ' }, { 1, 0 }, saap, { ' \t (aaa ', 'bbb', ' ccc)\t ' }, { 1, 4 })
  validate_edit({ ' \t aaa ', 'bbb', ' ccc\t ' }, { 1, 0 }, vapsa, { ' \t (aaa ', 'bbb', ' ccc)\t ' }, { 1, 4 })
  validate_edit({ ' \t aaa ', '\t ' }, { 1, 0 }, saap, { ' \t (aaa ', ')\t ' }, { 1, 4 })
  validate_edit({ ' \t aaa ', '\t ' }, { 1, 0 }, vapsa, { ' \t (aaa ', ')\t ' }, { 1, 4 })
end

T['Add surrounding']['works with multiline output surroundings'] = function()
  child.lua([[MiniSurround.config.custom_surroundings = {
    a = { output = { left = '\n(\n', right = '\n)\n' } }
  }]])
  validate_edit({ '  xxx' }, { 1, 3 }, { 'sa', 'iw', 'a' }, { '  ', '(', 'xxx', ')', '' }, { 1, 1 })
end

T['Add surrounding']['works when using $ motion'] = function()
  -- It might not work because cursor column is outside of line width
  validate_edit({ 'aaa' }, { 1, 0 }, { 'sa', '$', ')' }, { '(aaa)' }, { 1, 1 })
  validate_edit({ 'aaa' }, { 1, 0 }, { 'v$', 'sa', ')' }, { '(aaa)' }, { 1, 1 })
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

  -- <C-c> should stop even if it doesn't make `getcharstr` error
  child.cmd('nnoremap <C-c> <C-\\><C-n>')
  validate_cancel('<C-c>')
end

T['Add surrounding']['works with different mapping'] = function()
  reload_module({ mappings = { add = 'SA' } })

  validate_edit({ 'aaa' }, { 1, 0 }, { 'SA', 'iw', ')' }, { '(aaa)' }, { 1, 1 })
  child.api.nvim_del_keymap('n', 'SA')
end

T['Add surrounding']['respects two types of `[count]` in Normal mode'] = function()
  -- Built-in surroundings
  validate_edit1d('aa bb cc dd', 0, { '2sa', 'aw', ')' }, '((aa ))bb cc dd', 2)
  validate_edit1d('aa bb cc dd', 0, { 'sa', '3aw', ')' }, '(aa bb cc )dd', 1)
  validate_edit1d('aa bb cc dd', 0, { '2sa', '3aw', ')' }, '((aa bb cc ))dd', 2)

  -- - Should work with dot-repeat
  validate_edit1d('aa bb cc dd ee', 0, { '2sa2aw)', 'fc', '.' }, '((aa bb ))((cc dd ))ee', 12)

  -- Custom surroundings
  child.lua('MiniSurround.config.custom_surroundings = { ["!"] = { output = { left = "<", right = ">" } } }')
  validate_edit1d('aa bb cc dd', 0, { '2sa', 'aw', '!' }, '<<aa >>bb cc dd', 2)
  validate_edit1d('aa bb cc dd', 0, { 'sa', '3w', '!' }, '<aa bb cc >dd', 1)
  validate_edit1d('aa bb cc dd', 0, { '2sa', '3aw', '!' }, '<<aa bb cc >>dd', 2)

  validate_edit1d('aa bb cc dd ee', 0, { '2sa2aw!', 'fc', '.' }, '<<aa bb >><<cc dd >>ee', 12)

  -- Default (fallback) surroundings
  validate_edit1d('aa bb cc dd', 0, { '2sa', 'aw', '@' }, '@@aa @@bb cc dd', 2)
  validate_edit1d('aa bb cc dd', 0, { 'sa', '3w', '@' }, '@aa bb cc @dd', 1)
  validate_edit1d('aa bb cc dd', 0, { '2sa', '3aw', '@' }, '@@aa bb cc @@dd', 2)

  validate_edit1d('aa bb cc dd ee', 0, { '2sa2aw@', 'fc', '.' }, '@@aa bb @@@@cc dd @@ee', 12)
end

T['Add surrounding']['respects `[count]` in Visual mode'] = function()
  -- Built-in surroundings
  validate_edit1d('aa bb cc dd', 0, { 'vaw', '2sa', ')' }, '((aa ))bb cc dd', 2)
  validate_edit1d('aa bb cc dd', 0, { 'v3aw', '2sa', ')' }, '((aa bb cc ))dd', 2)

  -- Custom surroundings
  child.lua('MiniSurround.config.custom_surroundings = { ["!"] = { output = { left = "<", right = ">" } } }')
  validate_edit1d('aa bb cc dd', 0, { 'vaw', '2sa', '!' }, '<<aa >>bb cc dd', 2)
  validate_edit1d('aa bb cc dd', 0, { 'v3aw', '2sa', '!' }, '<<aa bb cc >>dd', 2)

  -- Default (fallback) surroundings
  validate_edit1d('aa bb cc dd', 0, { 'vaw', '2sa', '@' }, '@@aa @@bb cc dd', 2)
  validate_edit1d('aa bb cc dd', 0, { 'v3aw', '2sa', '@' }, '@@aa bb cc @@dd', 2)
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

  -- Regular case
  validate_edit({ ' aaa ' }, { 1, 1 }, { 'v2l', 'sa', ')' }, { ' (aa)a ' }, { 1, 2 })

  -- Multibyte characters
  validate_edit({ ' ыыы ' }, { 1, 1 }, { 'v2l', 'sa', ')' }, { ' (ыы)ы ' }, { 1, 2 })
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
  sleep(reminder_delay + small_time)
  child.expect_screenshot()
end

T['Add surrounding']['respects `vim.b.minisurround_config`'] = function()
  child.b.minisurround_config = { custom_surroundings = { ['<'] = { output = { left = '>', right = '<' } } } }
  validate_edit({ 'aaa' }, { 1, 1 }, { 'sa', 'iw', '<' }, { '>aaa<' }, { 1, 1 })
end

T['Delete surrounding'] = new_set()

T['Delete surrounding']['works with dot-repeat'] = function()
  validate_edit({ '(aaa)' }, { 1, 0 }, { 'sd', ')' }, { 'aaa' }, { 1, 0 })
  validate_edit({ '(aaa)' }, { 1, 4 }, { 'sd', ')' }, { 'aaa' }, { 1, 0 })
  validate_edit({ '(aaa)' }, { 1, 2 }, { 'sd', ')' }, { 'aaa' }, { 1, 0 })

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
    validate_edit(before_lines, before_cursor, { 'sd', ')' }, after_lines, after_cursor)
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
  validate_edit1d('(aa) (bb) (cc)', 1, { 'sdn', ')' }, '(aa) bb (cc)', 5)
  validate_edit1d('(aa) (bb) (cc)', 1, { '2sdn', ')' }, '(aa) (bb) cc', 10)

  validate_edit1d('(aa) (bb) (cc)', 11, { 'sdl', ')' }, '(aa) bb (cc)', 5)
  validate_edit1d('(aa) (bb) (cc)', 11, { '2sdl', ')' }, 'aa (bb) (cc)', 0)

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
  validate_edit(lines, { 4, 0 }, { 'sd', ')' }, lines, { 4, 0 })
  has_message_about_not_found(')', 2)

  -- Should also use buffer local config
  child.b.minisurround_config = { n_lines = 10 }
  validate_edit(lines, { 4, 0 }, { 'sd', ')' }, { '', '', '', 'a', '', '', '' }, { 1, 0 })
end

T['Delete surrounding']['respects `config.search_method`'] = function()
  local lines = { 'aaa (bbb)' }

  -- By default uses 'cover'
  validate_edit(lines, { 1, 0 }, { 'sd', ')' }, lines, { 1, 0 })
  has_message_about_not_found(')')

  -- Should change behavior according to `config.search_method`
  reload_module({ search_method = 'cover_or_next' })
  validate_edit(lines, { 1, 0 }, { 'sd', ')' }, { 'aaa bbb' }, { 1, 4 })

  -- Should also use buffer local config
  child.b.minisurround_config = { search_method = 'cover' }
  validate_edit(lines, { 1, 0 }, { 'sd', ')' }, lines, { 1, 0 })
end

T['Delete surrounding']['places cursor to the right of left surrounding'] = function()
  -- Same line
  validate_edit({ 'myfunc(aaa)' }, { 1, 7 }, { 'sd', 'f' }, { 'aaa' }, { 1, 0 })

  -- Not the same line
  validate_edit({ 'myfunc(aaa', 'bbb', 'ccc)' }, { 1, 8 }, { 'sd', 'f' }, { 'aaa', 'bbb', 'ccc' }, { 1, 0 })
  validate_edit({ 'myfunc(aaa', 'bbb', 'ccc)' }, { 2, 0 }, { 'sd', 'f' }, { 'aaa', 'bbb', 'ccc' }, { 1, 0 })
  validate_edit({ 'myfunc(aaa', 'bbb', 'ccc)' }, { 3, 2 }, { 'sd', 'f' }, { 'aaa', 'bbb', 'ccc' }, { 1, 0 })
end

T['Delete surrounding']['shows reminder after one idle second'] = function()
  child.set_size(5, 70)
  child.o.cmdheight = 1

  -- Mapping is applied only after `timeoutlen` milliseconds, because
  -- there are `sdn`/`sdl` mappings. Wait 1000 seconds after that.
  child.o.timeoutlen = 5 * small_time
  local total_wait_time = reminder_delay + child.o.timeoutlen + small_time

  set_lines({ '((aaa))' })
  set_cursor(1, 1)

  -- Execute one time to test if 'needs help message' flag is set per call
  type_keys('sd', ')')
  sleep(0.1 * reminder_delay)

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
  validate_edit({ '  (ыыы)  ' }, { 1, 3 }, { 'sd', ')' }, { '  ыыы  ' }, { 1, 2 })
  validate_edit({ '(ыыы) ttt' }, { 1, 1 }, { 'sd', ')' }, { 'ыыы ttt' }, { 1, 0 })
  validate_edit({ 'ttt (ыыы)' }, { 1, 5 }, { 'sd', ')' }, { 'ttt ыыы' }, { 1, 4 })
end

T['Delete surrounding']['works on multiple lines'] = function()
  validate_edit({ '(aaa', 'bbb', 'ccc)' }, { 1, 3 }, { 'sd', ')' }, { 'aaa', 'bbb', 'ccc' }, { 1, 0 })
  validate_edit({ '(aaa', 'bbb', 'ccc)' }, { 2, 0 }, { 'sd', ')' }, { 'aaa', 'bbb', 'ccc' }, { 1, 0 })
end

T['Delete surrounding']['works with multiline input surroundings'] = function()
  child.lua([[MiniSurround.config.custom_surroundings = {
    a = { input = { '%(\na().-()a\n%)' } },
    b = { input = { '%(\n().-()\n%)' } },
    c = { input = { '\na().-()a\n' } },
    d = { input = { '\n().-()\n' } },
  }]])
  local lines = { 'xxx(', 'aaa', ')xxx' }

  validate_edit(lines, { 1, 3 }, { 'sd', 'a' }, { 'xxxaxxx' }, { 1, 3 })
  validate_edit(lines, { 2, 1 }, { 'sd', 'a' }, { 'xxxaxxx' }, { 1, 3 })
  validate_edit(lines, { 3, 0 }, { 'sd', 'a' }, { 'xxxaxxx' }, { 1, 3 })

  validate_edit(lines, { 1, 3 }, { 'sd', 'b' }, { 'xxxaaaxxx' }, { 1, 3 })
  validate_edit(lines, { 2, 1 }, { 'sd', 'b' }, { 'xxxaaaxxx' }, { 1, 3 })
  validate_edit(lines, { 3, 0 }, { 'sd', 'b' }, { 'xxxaaaxxx' }, { 1, 3 })

  -- No case for first line because there is no covering match
  validate_edit(lines, { 2, 1 }, { 'sd', 'c' }, { 'xxx(a)xxx' }, { 1, 4 })
  -- No case for third line because there is no covering match

  -- No case for first line because there is no covering match
  validate_edit(lines, { 2, 1 }, { 'sd', 'd' }, { 'xxx(aaa)xxx' }, { 1, 4 })
  -- There is a `\n` at the end of last line, so it is matched
  validate_edit(lines, { 3, 0 }, { 'sd', 'd' }, { 'xxx(', 'aaa)xxx' }, { 2, 3 })
end

T['Delete surrounding']['allows cancelling with `<Esc> and <C-c>`'] = function()
  local validate_cancel = function(key)
    child.ensure_normal_mode()
    set_lines({ '\3aaa\3' })
    set_cursor(1, 1)

    type_keys(1, 'sd', key)
    eq(get_lines(), { '\3aaa\3' })
    eq(get_cursor(), { 1, 1 })
  end

  validate_cancel('<Esc>')

  -- <C-c> should stop even if it doesn't make `getcharstr` error
  child.cmd('nnoremap <C-c> <C-\\><C-n>')
  validate_cancel('<C-c>')
end

T['Delete surrounding']['works with different mapping'] = function()
  reload_module({ mappings = { delete = 'SD' } })
  validate_edit({ '(aaa)' }, { 1, 1 }, { 'SD', ')' }, { 'aaa' }, { 1, 0 })
end

T['Delete surrounding']['respects `v:count` for input surrounding'] = function()
  validate_edit({ '(a(b(c)b)a)' }, { 1, 5 }, { '2sd', ')' }, { '(ab(c)ba)' }, { 1, 2 })

  -- Should give informative message on failure
  validate_edit({ '(a)' }, { 1, 0 }, { '2sd', ')' }, { '(a)' }, { 1, 0 })
  has_message_about_not_found(')', nil, nil, 2)

  -- Should respect search method
  child.lua([[MiniSurround.config.search_method = 'cover_or_next']])
  validate_edit({ '(aa) (bb) (cc)' }, { 1, 1 }, { '2sd', ')' }, { '(aa) bb (cc)' }, { 1, 5 })
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
  local total_wait_time = reminder_delay + child.o.timeoutlen + small_time

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
  validate_edit({ '>aaa<' }, { 1, 2 }, { 'sd', '<' }, { 'aaa' }, { 1, 0 })
end

T['Replace surrounding'] = new_set()

-- NOTE: use `>` for replacement because it itself is not a blocking key.
-- Like if you type `}` or `]`, Neovim will have to wait for the next key,
-- which blocks `child`.
T['Replace surrounding']['works with dot-repeat'] = function()
  validate_edit({ '(aaa)' }, { 1, 0 }, { 'sr', ')', '>' }, { '<aaa>' }, { 1, 1 })
  validate_edit({ '(aaa)' }, { 1, 4 }, { 'sr', ')', '>' }, { '<aaa>' }, { 1, 1 })
  validate_edit({ '(aaa)' }, { 1, 2 }, { 'sr', ')', '>' }, { '<aaa>' }, { 1, 1 })

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
  validate_edit1d('(aa) (bb) (cc)', 1, { 'srn', ')', '>' }, '(aa) <bb> (cc)', 6)
  validate_edit1d('(aa) (bb) (cc)', 1, { '2srn', ')', '>' }, '(aa) (bb) <cc>', 11)

  validate_edit1d('(aa) (bb) (cc)', 11, { 'srl', ')', '>' }, '(aa) <bb> (cc)', 6)
  validate_edit1d('(aa) (bb) (cc)', 11, { '2srl', ')', '>' }, '<aa> (bb) (cc)', 1)

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
  validate_edit(lines, { 4, 0 }, { 'sr', ')', '>' }, lines, { 4, 0 })
  has_message_about_not_found(')', 2)

  -- Should also use buffer local config
  child.b.minisurround_config = { n_lines = 10 }
  validate_edit(lines, { 4, 0 }, { 'sr', ')', '>' }, { '<', '', '', 'a', '', '', '>' }, { 1, 0 })
end

T['Replace surrounding']['respects `config.search_method`'] = function()
  local lines = { 'aaa (bbb)' }

  -- By default uses 'cover'
  validate_edit(lines, { 1, 0 }, { 'sr', ')', '>' }, lines, { 1, 0 })
  has_message_about_not_found(')')

  -- Should change behavior according to `config.search_method`
  reload_module({ search_method = 'cover_or_next' })
  validate_edit(lines, { 1, 0 }, { 'sr', ')', '>' }, { 'aaa <bbb>' }, { 1, 5 })

  -- Should also use buffer local config
  child.b.minisurround_config = { search_method = 'cover' }
  validate_edit(lines, { 1, 0 }, { 'sr', ')', '>' }, lines, { 1, 0 })
end

T['Replace surrounding']['places cursor to the right of left surrounding'] = function()
  -- Same line
  validate_edit({ 'myfunc(aaa)' }, { 1, 7 }, { 'sr', 'f', '>' }, { '<aaa>' }, { 1, 1 })

  -- Not the same line
  validate_edit({ 'myfunc(aaa', 'bbb', 'ccc)' }, { 1, 8 }, { 'sr', 'f', '>' }, { '<aaa', 'bbb', 'ccc>' }, { 1, 1 })
  validate_edit({ 'myfunc(aaa', 'bbb', 'ccc)' }, { 2, 0 }, { 'sr', 'f', '>' }, { '<aaa', 'bbb', 'ccc>' }, { 1, 1 })
  validate_edit({ 'myfunc(aaa', 'bbb', 'ccc)' }, { 3, 2 }, { 'sr', 'f', '>' }, { '<aaa', 'bbb', 'ccc>' }, { 1, 1 })
end

T['Replace surrounding']['shows reminder after one idle second'] = function()
  child.set_size(5, 70)
  child.o.cmdheight = 1

  -- Mapping is applied only after `timeoutlen` milliseconds, because
  -- there are `srn`/`srl` mappings. Wait 1000 seconds after that.
  child.o.timeoutlen = 5 * small_time
  local total_wait_time = reminder_delay + child.o.timeoutlen + small_time

  set_lines({ '((aaa))' })
  set_cursor(1, 1)

  -- Execute one time to test if 'needs help message' flag is set per call
  type_keys('sr', ')', '>')
  sleep(0.1 * reminder_delay)

  type_keys('sr')
  sleep(total_wait_time)

  -- Should show helper message without adding it to `:messages` and causing
  -- hit-enter-prompt
  eq(get_latest_message(), '')
  child.expect_screenshot()

  clear_messages()
  type_keys(')')

  -- Here mapping collision doesn't matter any more
  sleep(reminder_delay + small_time)
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
  validate_edit({ '  (ыыы)  ' }, { 1, 3 }, { 'sr', ')', '>' }, { '  <ыыы>  ' }, { 1, 3 })
  validate_edit({ '(ыыы) ttt' }, { 1, 1 }, { 'sr', ')', '>' }, { '<ыыы> ttt' }, { 1, 1 })
  validate_edit({ 'ttt (ыыы)' }, { 1, 5 }, { 'sr', ')', '>' }, { 'ttt <ыыы>' }, { 1, 5 })
end

T['Replace surrounding']['works on multiple lines'] = function()
  validate_edit({ '(aaa', 'bbb', 'ccc)' }, { 1, 3 }, { 'sr', ')', '>' }, { '<aaa', 'bbb', 'ccc>' }, { 1, 1 })
  validate_edit({ '(aaa', 'bbb', 'ccc)' }, { 2, 0 }, { 'sr', ')', '>' }, { '<aaa', 'bbb', 'ccc>' }, { 1, 1 })
end

T['Replace surrounding']['works with multiline input surroundings'] = function()
  child.lua([[MiniSurround.config.custom_surroundings = {
    a = { input = { '%(\na().-()a\n%)' } },
    b = { input = { '%(\n().-()\n%)' } },
    c = { input = { '\na().-()a\n' } },
    d = { input = { '\n().-()\n' } },
  }]])
  local lines = { 'xxx(', 'aaa', ')xxx' }

  validate_edit(lines, { 1, 3 }, { 'sr', 'a', '>' }, { 'xxx<a>xxx' }, { 1, 4 })
  validate_edit(lines, { 2, 1 }, { 'sr', 'a', '>' }, { 'xxx<a>xxx' }, { 1, 4 })
  validate_edit(lines, { 3, 0 }, { 'sr', 'a', '>' }, { 'xxx<a>xxx' }, { 1, 4 })

  validate_edit(lines, { 1, 3 }, { 'sr', 'b', '>' }, { 'xxx<aaa>xxx' }, { 1, 4 })
  validate_edit(lines, { 2, 1 }, { 'sr', 'b', '>' }, { 'xxx<aaa>xxx' }, { 1, 4 })
  validate_edit(lines, { 3, 0 }, { 'sr', 'b', '>' }, { 'xxx<aaa>xxx' }, { 1, 4 })

  -- No case for first line because there is no covering match
  validate_edit(lines, { 2, 1 }, { 'sr', 'c', '>' }, { 'xxx(<a>)xxx' }, { 1, 5 })
  -- No case for third line because there is no covering match

  -- No case for first line because there is no covering match
  validate_edit(lines, { 2, 1 }, { 'sr', 'd', '>' }, { 'xxx(<aaa>)xxx' }, { 1, 5 })
  -- There is a `\n` at the end of last line. It is matched but can't be replaced.
  validate_edit(lines, { 3, 0 }, { 'sr', 'd', '>' }, { 'xxx(', 'aaa<)xxx' }, { 2, 4 })
end

T['Replace surrounding']['works with multiline output surroundings'] = function()
  child.lua([[MiniSurround.config.custom_surroundings = {
    a = { output = { left = '\n(\n', right = '\n)\n' } }
  }]])
  validate_edit({ '  [xxx]' }, { 1, 3 }, { 'sr', ']', 'a' }, { '  ', '(', 'xxx', ')', '' }, { 1, 1 })
end

T['Replace surrounding']['allows cancelling with `<Esc> and <C-c>`'] = function()
  local validate_cancel = function(key)
    -- Cancel before input surrounding
    child.ensure_normal_mode()
    set_lines({ '\3aaa\3' })
    set_cursor(1, 1)
    type_keys(1, 'sr', key, '>')
    eq(get_lines(), { '\3aaa\3' })
    eq(get_cursor(), { 1, 1 })

    -- Cancel before output surrounding
    child.ensure_normal_mode()
    set_lines({ '<aaa>' })
    set_cursor(1, 1)
    type_keys(1, 'sr', '>', key)
    eq(get_lines(), { '<aaa>' })
    eq(get_cursor(), { 1, 1 })
  end

  validate_cancel('<Esc>')

  -- <C-c> should stop even if it doesn't make `getcharstr` error
  child.cmd('nnoremap <C-c> <C-\\><C-n>')
  validate_cancel('<C-c>')
end

T['Replace surrounding']['works with different mapping'] = function()
  reload_module({ mappings = { replace = 'SR' } })
  validate_edit({ '(aaa)' }, { 1, 1 }, { 'SR', ')', '>' }, { '<aaa>' }, { 1, 1 })
end

T['Replace surrounding']['respects `v:count` for input surrounding'] = function()
  validate_edit({ '(a(b(c)b)a)' }, { 1, 5 }, { '2sr', ')', '>' }, { '(a<b(c)b>a)' }, { 1, 3 })

  -- Should give informative message on failure
  validate_edit({ '(a)' }, { 1, 0 }, { '2sr', ')', '>' }, { '(a)' }, { 1, 0 })
  has_message_about_not_found(')', nil, nil, 2)

  -- Should respect search method
  child.lua([[MiniSurround.config.search_method = 'cover_or_next']])
  validate_edit({ '(aa) (bb) (cc)' }, { 1, 1 }, { '2sr', ')', '>' }, { '(aa) <bb> (cc)' }, { 1, 6 })
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
  local total_wait_time = reminder_delay + child.o.timeoutlen + small_time

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
  validate_edit({ '<aaa>' }, { 1, 2 }, { 'sr', '>', '<' }, { '>aaa<' }, { 1, 1 })
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

--stylua: ignore
T['Find surrounding']['works with "non single character" surroundings'] = function()
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
end

T['Find surrounding']['works in extended mappings'] = function()
  -- "Find right" when outside of outer surroundings puts cursor on left-most
  -- position. If cursor is on the left, that is obvious. When on the right -
  -- it behaves as on the right-most surrounding position.
  -- "Find left" puts on right-most position for the same reasons.
  validate_edit1d('(aa) (bb) (cc)', 1, { 'sfn', ')' }, '(aa) (bb) (cc)', 5)
  validate_edit1d('(aa) (bb) (cc)', 1, { '2sfn', ')' }, '(aa) (bb) (cc)', 10)
  validate_edit1d('(aa) (bb) (cc)', 1, { 'sFn', ')' }, '(aa) (bb) (cc)', 8)
  validate_edit1d('(aa) (bb) (cc)', 1, { '2sFn', ')' }, '(aa) (bb) (cc)', 13)

  validate_edit1d('(aa) (bb) (cc)', 11, { 'sfl', ')' }, '(aa) (bb) (cc)', 5)
  validate_edit1d('(aa) (bb) (cc)', 11, { '2sfl', ')' }, '(aa) (bb) (cc)', 0)
  validate_edit1d('(aa) (bb) (cc)', 11, { 'sFl', ')' }, '(aa) (bb) (cc)', 8)
  validate_edit1d('(aa) (bb) (cc)', 11, { '2sFl', ')' }, '(aa) (bb) (cc)', 3)

  -- Does not override dot-repeat
  set_lines({ '(aa) (bb) (cc)' })
  set_cursor(1, 0)
  type_keys('r[', 'u') -- dot-repeatable action
  type_keys('sfn', ')')
  type_keys('.')
  eq(get_lines(), { '(aa) [bb) (cc)' })
  eq(get_cursor(), { 1, 5 })
end

T['Find surrounding']['works in Visual mode'] = function()
  local validate = function(line, before_column, after_column, keys)
    set_lines({ line })
    set_cursor(1, before_column)

    type_keys('v', keys)
    eq(get_cursor(), { 1, after_column })
    eq(child.fn.col('v'), before_column + 1)
    eq(child.fn.mode(), 'v')

    child.ensure_normal_mode()
  end

  validate('(aa) (bb) (cc)', 1, 3, 'sf(')
  validate('(aa) (bb) (cc)', 1, 5, 'sfn(')
  validate('(aa) (bb) (cc)', 1, 10, '2sfn(')
  validate('(aa) (bb) (cc)', 11, 5, 'sfl(')
  validate('(aa) (bb) (cc)', 11, 0, '2sfl(')

  validate('(aa) (bb) (cc)', 2, 0, 'sF)')
  validate('(aa) (bb) (cc)', 2, 8, 'sFn)')
  validate('(aa) (bb) (cc)', 2, 13, '2sFn)')
  validate('(aa) (bb) (cc)', 11, 8, 'sFl)')
  validate('(aa) (bb) (cc)', 11, 3, '2sFl)')
end

T['Find surrounding']['works in Operator-pending mode'] = function()
  validate_edit1d('(aa) (bb) (cc)', 1, { 'dsf(' }, '() (bb) (cc)', 1)
  validate_edit1d('(aa) (bb) (cc)', 1, { 'dsfn(' }, '((bb) (cc)', 1)
  validate_edit1d('(aa) (bb) (cc)', 1, { 'd2sfn(' }, '((cc)', 1)
  validate_edit1d('(aa) (bb) (cc)', 11, { 'dsfl(' }, '(aa) cc)', 5)
  validate_edit1d('(aa) (bb) (cc)', 11, { 'd2sfl(' }, 'cc)', 0)

  validate_edit1d('(aa) (bb) (cc)', 2, { 'dsF)' }, 'a) (bb) (cc)', 0)
  validate_edit1d('(aa) (bb) (cc)', 2, { 'dsFn)' }, '(a) (cc)', 2)
  validate_edit1d('(aa) (bb) (cc)', 2, { 'd2sFn)' }, '(a)', 2)
  validate_edit1d('(aa) (bb) (cc)', 11, { 'dsFl(' }, '(aa) (bbcc)', 8)
  validate_edit1d('(aa) (bb) (cc)', 11, { 'd2sFl(' }, '(aacc)', 3)

  -- Works with dot-repeat
  local validate_dot = function(before_line, column_1, keys, column_2, after_line)
    set_lines({ before_line })
    set_cursor(1, column_1)
    type_keys('d', keys)
    set_cursor(1, column_2)
    type_keys('.')
    eq(get_lines(), { after_line })
  end

  validate_dot('(aa) (bb) (cc)', 1, 'sf(', 4, '() () (cc)')
  validate_dot('(aa) (bb) (cc)', 1, 'sfn(', 2, '(((cc)')
  validate_dot('(aa) (bb) (cc)', 11, 'sfl(', 5, 'cc)')

  validate_dot('(aa) (bb) (cc)', 2, 'sF(', 5, 'a) b) (cc)')
  validate_dot('(aa) (bb) (cc)', 2, 'sFn(', 2, '(a)')
  validate_dot('(aa) (bb) (cc)', 11, 'sFl(', 8, '(aacc)')
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

T['Find surrounding']['shows reminder after one idle second'] = function()
  child.set_size(5, 70)
  child.o.cmdheight = 1

  -- Mapping is applied only after `timeoutlen` milliseconds, because
  -- there are `sfn`/`sfl` mappings. Wait 1000 seconds after that.
  child.o.timeoutlen = 5 * small_time
  local total_wait_time = reminder_delay + child.o.timeoutlen + small_time

  set_lines({ '(aaa)' })
  set_cursor(1, 2)

  -- Execute one time to test if 'needs help message' flag is set per call
  type_keys('sf', ')')
  sleep(0.1 * reminder_delay)

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
    -- It should work with `sf`
    child.ensure_normal_mode()
    set_lines({ '\3aaa\3' })
    set_cursor(1, 1)
    type_keys(1, 'sf', key)
    eq(get_lines(), { '\3aaa\3' })
    eq(get_cursor(), { 1, 1 })

    -- It should work with `sF`
    child.ensure_normal_mode()
    type_keys(1, 'sF', key)
    eq(get_lines(), { '\3aaa\3' })
    eq(get_cursor(), { 1, 1 })
  end

  validate_cancel('<Esc>')

  -- <C-c> should stop even if it doesn't make `getcharstr` error
  child.cmd('nnoremap <C-c> <C-\\><C-n>')
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
  validate_edit({ '(a(b(c)b)a)' }, { 1, 5 }, { '2sf', ')' }, { '(a(b(c)b)a)' }, { 1, 8 })
  validate_edit({ '(a(b(c)b)a)' }, { 1, 5 }, { '2sF', ')' }, { '(a(b(c)b)a)' }, { 1, 2 })

  -- Should give informative message on failure
  validate_edit({ '(a)' }, { 1, 0 }, { '2sf', ')' }, { '(a)' }, { 1, 0 })
  has_message_about_not_found(')', nil, nil, 2)

  -- Should respect search method
  child.lua([[MiniSurround.config.search_method = 'cover_or_next']])
  validate_edit({ '(aa) (bb) (cc)' }, { 1, 1 }, { '2sf', ')' }, { '(aa) (bb) (cc)' }, { 1, 5 })

  child.lua([[MiniSurround.config.search_method = 'cover_or_prev']])
  validate_edit({ '(aa) (bb) (cc)' }, { 1, 13 }, { '2sF', ')' }, { '(aa) (bb) (cc)' }, { 1, 8 })
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
  validate_edit({ '>aaa<' }, { 1, 2 }, { 'sf', '<' }, { '>aaa<' }, { 1, 4 })
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
  validate_edit({ '>aaa<' }, { 1, 2 }, { 'sd', '<' }, { 'aaa' }, { 1, 0 })

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
  local keys = { 'sr', ')', '>' }

  -- Works (on same line and on multiple lines)
  validate_edit({ '(aaa) bbb' }, { 1, 7 }, keys, { '<aaa> bbb' }, { 1, 1 })
  validate_edit({ '(aaa)', 'bbb' }, { 2, 0 }, keys, { '<aaa>', 'bbb' }, { 1, 1 })

  -- Should prefer covering surrounding if both are on the same line
  validate_edit({ '(aaa) (bbb)' }, { 1, 8 }, keys, { '(aaa) <bbb>' }, { 1, 7 })
  validate_edit({ '((aaa) bbb)' }, { 1, 8 }, keys, { '<(aaa) bbb>' }, { 1, 1 })

  -- Should prefer covering surrounding if both are not on the same line
  validate_edit({ '(aaa) (', 'bbb)' }, { 2, 0 }, keys, { '(aaa) <', 'bbb>' }, { 1, 6 })

  -- Should prefer "previous" if it is on the same line, but covering is not
  validate_edit({ '(aaa) (bbb', ')' }, { 1, 8 }, keys, { '<aaa> (bbb', ')' }, { 1, 1 })

  -- Should ignore presence of "next" surrounding (even on same line)
  validate_edit({ '(aaa) bbb (ccc)' }, { 1, 7 }, keys, { '<aaa> bbb (ccc)' }, { 1, 1 })
  validate_edit({ '(aaa)', 'bbb (ccc)' }, { 2, 1 }, keys, { '<aaa>', 'bbb (ccc)' }, { 1, 1 })
  validate_edit({ '(aaa) (', 'bbb (ccc))' }, { 2, 0 }, keys, { '(aaa) <', 'bbb (ccc)>' }, { 1, 6 })
end

T['Search method']['works with "cover_or_next"'] = function()
  reload_module({ search_method = 'cover_or_next' })
  local keys = { 'sr', ')', '>' }

  -- Works (on same line and on multiple lines)
  validate_edit({ 'aaa (bbb)' }, { 1, 0 }, keys, { 'aaa <bbb>' }, { 1, 5 })
  validate_edit({ 'aaa', '(bbb)' }, { 1, 0 }, keys, { 'aaa', '<bbb>' }, { 2, 1 })

  -- Should prefer covering surrounding if both are on the same line
  validate_edit({ '(aaa) (bbb)' }, { 1, 2 }, keys, { '<aaa> (bbb)' }, { 1, 1 })
  validate_edit({ '(aaa (bbb))' }, { 1, 2 }, keys, { '<aaa (bbb)>' }, { 1, 1 })

  -- Should prefer covering surrounding if both are not on the same line
  validate_edit({ '(aaa', ') (bbb)' }, { 1, 2 }, keys, { '<aaa', '> (bbb)' }, { 1, 1 })

  -- Should prefer "next" if it is on the same line, but covering is not
  validate_edit({ '(', 'aaa) (bbb)' }, { 2, 1 }, keys, { '(', 'aaa) <bbb>' }, { 2, 6 })

  -- Should ignore presence of "previous" surrounding (even on same line)
  validate_edit({ '(aaa) bbb (ccc)' }, { 1, 7 }, keys, { '(aaa) bbb <ccc>' }, { 1, 11 })
  validate_edit({ '(aaa) bbb', '(ccc)' }, { 1, 7 }, keys, { '(aaa) bbb', '<ccc>' }, { 2, 1 })
  validate_edit({ '(aaa) (', '(bbb) ccc)' }, { 2, 7 }, keys, { '(aaa) <', '(bbb) ccc>' }, { 1, 6 })
end

T['Search method']['works with "cover_or_nearest"'] = function()
  reload_module({ search_method = 'cover_or_nearest' })
  local keys = { 'sr', ')', '>' }

  -- Works (on same line and on multiple lines)
  validate_edit({ '(aaa) bbb (ccc)' }, { 1, 6 }, keys, { '<aaa> bbb (ccc)' }, { 1, 1 })
  validate_edit({ '(aaa) bbb (ccc)' }, { 1, 7 }, keys, { '<aaa> bbb (ccc)' }, { 1, 1 })
  validate_edit({ '(aaa) bbb (ccc)' }, { 1, 8 }, keys, { '(aaa) bbb <ccc>' }, { 1, 11 })

  validate_edit({ '(aaa)', 'bbb', '(ccc)' }, { 2, 0 }, keys, { '<aaa>', 'bbb', '(ccc)' }, { 1, 1 })
  validate_edit({ '(aaa)', 'bbb', '(ccc)' }, { 2, 1 }, keys, { '<aaa>', 'bbb', '(ccc)' }, { 1, 1 })
  validate_edit({ '(aaa)', 'bbb', '(ccc)' }, { 2, 2 }, keys, { '(aaa)', 'bbb', '<ccc>' }, { 3, 1 })

  -- Should prefer covering surrounding if both are on the same line
  validate_edit({ '(aaa) (bbb) (ccc)' }, { 1, 7 }, keys, { '(aaa) <bbb> (ccc)' }, { 1, 7 })
  validate_edit({ '((aaa) bbb (ccc))' }, { 1, 7 }, keys, { '<(aaa) bbb (ccc)>' }, { 1, 1 })

  -- Should prefer covering surrounding if both are not on the same line
  validate_edit({ '(aaa) (', 'bbb', ') (ccc)' }, { 2, 0 }, keys, { '(aaa) <', 'bbb', '> (ccc)' }, { 1, 6 })

  -- Should prefer "nearest" if it is on the same line, but covering is not
  validate_edit({ '(aaa) (', 'bbb) (ccc)' }, { 2, 1 }, keys, { '(aaa) (', 'bbb) <ccc>' }, { 2, 6 })

  -- Computes "nearest" based on closest part of candidate surroundings (based
  -- on distance between *left* part of current cell and span edges)
  validate_edit({ '(aaaaaaa) b  (c)' }, { 1, 7 }, keys, { '<aaaaaaa> b  (c)' }, { 1, 1 })
  validate_edit({ '(a)   b (ccccccc)' }, { 1, 6 }, keys, { '(a)   b <ccccccc>' }, { 1, 9 })

  -- If either "previous" or "next" is missing, should return the present one
  validate_edit({ '(aaa) bbb' }, { 1, 7 }, keys, { '<aaa> bbb' }, { 1, 1 })
  validate_edit({ '(aaa)', 'bbb' }, { 2, 0 }, keys, { '<aaa>', 'bbb' }, { 1, 1 })
  validate_edit({ 'aaa (bbb)' }, { 1, 0 }, keys, { 'aaa <bbb>' }, { 1, 5 })
  validate_edit({ 'aaa', '(bbb)' }, { 1, 0 }, keys, { 'aaa', '<bbb>' }, { 2, 1 })
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
  validate_edit({ 'aaa (bbb)' }, { 1, 0 }, { 'sr', ')', '>' }, { 'aaa <bbb>' }, { 1, 5 })
end

-- Surroundings ---------------------------------------------------------------
T['Builtin'] = new_set()

T['Builtin']['Bracket'] = new_set()

T['Builtin']['Bracket']['works with open character'] = function()
  local validate = function(key, pair)
    -- Should work as input surrounding (by removing )
    local input = pair:sub(1, 1) .. '  aaa  ' .. pair:sub(2, 2)
    validate_edit({ input }, { 1, 2 }, { 'sd', key }, { 'aaa' }, { 1, 0 })

    -- Should work as output surrounding
    local output = string.format('%s aaa %s', pair:sub(1, 1), pair:sub(2, 2))
    validate_edit({ '_aaa_' }, { 1, 2 }, { 'sr', '_', key }, { output }, { 1, 2 })
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
    validate_edit({ input }, { 1, 2 }, { 'sd', key }, { '  aaa  ' }, { 1, 0 })

    -- Should work as output surrounding
    local output = pair:sub(1, 1) .. 'aaa' .. pair:sub(2, 2)
    validate_edit({ '_aaa_' }, { 1, 2 }, { 'sr', '_', key }, { output }, { 1, 1 })
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

  -- It does not take into account that part is inside string
  validate_edit({ [[(a, ')', b)]] }, { 1, 1 }, { 'sr', ')', '>' }, { "<a, '>', b)" }, { 1, 1 })

  -- It does not take into account that part is inside comment
  child.bo.commentstring = '# %s'
  validate_edit({ '(a', '# )', 'b)' }, { 1, 1 }, { 'sr', ')', '>' }, { '<a', '# >', 'b)' }, { 1, 1 })
end

T['Builtin']['Bracket']['is indeed balanced'] = function()
  local keys = { 'sr', ')', '>' }

  validate_edit({ '(a())' }, { 1, 1 }, keys, { '<a()>' }, { 1, 1 })
  validate_edit({ '(()a)' }, { 1, 3 }, keys, { '<()a>' }, { 1, 1 })

  validate_edit({ '((()))' }, { 1, 0 }, keys, { '<(())>' }, { 1, 1 })
  validate_edit({ '((()))' }, { 1, 1 }, keys, { '(<()>)' }, { 1, 2 })
  validate_edit({ '((()))' }, { 1, 2 }, keys, { '((<>))' }, { 1, 3 })
  validate_edit({ '((()))' }, { 1, 3 }, keys, { '((<>))' }, { 1, 3 })
  validate_edit({ '((()))' }, { 1, 4 }, keys, { '(<()>)' }, { 1, 2 })
  validate_edit({ '((()))' }, { 1, 5 }, keys, { '<(())>' }, { 1, 1 })
end

T['Builtin']['Brackets alias'] = new_set()

T['Builtin']['Brackets alias']['works'] = function()
  local keys

  -- Input
  keys = { 'sd', 'b' }
  validate_edit({ '(aa)' }, { 1, 0 }, keys, { 'aa' }, { 1, 0 })
  validate_edit({ '[aa]' }, { 1, 0 }, keys, { 'aa' }, { 1, 0 })
  validate_edit({ '{aa}' }, { 1, 0 }, keys, { 'aa' }, { 1, 0 })

  -- Output
  keys = { 'sr', '_', 'b' }
  validate_edit({ '_aa_' }, { 1, 0 }, keys, { '(aa)' }, { 1, 1 })

  -- Balanced
  keys = { 'sd', 'b' }
  validate_edit({ '(aa())' }, { 1, 0 }, keys, { 'aa()' }, { 1, 0 })
  validate_edit({ '[aa[]]' }, { 1, 0 }, keys, { 'aa[]' }, { 1, 0 })
  validate_edit({ '{aa{}}' }, { 1, 0 }, keys, { 'aa{}' }, { 1, 0 })
end

T['Builtin']['Quotes alias'] = new_set()

T['Builtin']['Quotes alias']['works'] = function()
  local keys

  -- Input
  keys = { 'sd', 'q' }
  validate_edit({ "'aa'" }, { 1, 0 }, keys, { 'aa' }, { 1, 0 })
  validate_edit({ '"aa"' }, { 1, 0 }, keys, { 'aa' }, { 1, 0 })
  validate_edit({ '`aa`' }, { 1, 0 }, keys, { 'aa' }, { 1, 0 })

  -- Output
  keys = { 'sr', '_', 'q' }
  validate_edit({ '_aa_' }, { 1, 0 }, keys, { '"aa"' }, { 1, 1 })

  -- Not balanced
  keys = { 'sd', 'q' }
  validate_edit({ "'aa'bb'cc'" }, { 1, 4 }, keys, { "'aabbcc'" }, { 1, 3 })
  validate_edit({ '"aa"bb"cc"' }, { 1, 4 }, keys, { '"aabbcc"' }, { 1, 3 })
  validate_edit({ '`aa`bb`cc`' }, { 1, 4 }, keys, { '`aabbcc`' }, { 1, 3 })
end

T['Builtin']['Default'] = new_set()

T['Builtin']['Default']['works'] = function()
  local validate = function(key)
    local s = key .. 'aaa' .. key

    -- Should work as input surrounding
    validate_edit({ s }, { 1, 2 }, { 'sd', key }, { 'aaa' }, { 1, 0 })

    -- Should work as output surrounding
    validate_edit({ '(aaa)' }, { 1, 2 }, { 'sr', ')', key }, { s }, { 1, 1 })
  end

  validate(' ')
  validate('_')
  validate('*')
  validate('"')
  validate("'")
end

T['Builtin']['Default']['does not work in some cases'] = function()
  -- Although, it would be great if it did

  -- It does not take into account that part is inside string
  validate_edit({ [[_a, '_', b_]] }, { 1, 1 }, { 'sr', '_', '>' }, { "<a, '>', b_" }, { 1, 1 })

  -- It does not take into account that part is inside comment
  child.bo.commentstring = '# %s'
  validate_edit({ '_a', '# _', 'b_' }, { 1, 1 }, { 'sr', '_', '>' }, { '<a', '# >', 'b_' }, { 1, 1 })
end

T['Builtin']['Default']['detects covering with smallest width'] = function()
  validate_edit({ '"a"aa"' }, { 1, 2 }, { 'sr', '"', ')' }, { '(a)aa"' }, { 1, 1 })
  validate_edit({ '"aa"a"' }, { 1, 3 }, { 'sr', '"', ')' }, { '"aa(a)' }, { 1, 4 })

  validate_edit({ '"""a"""' }, { 1, 3 }, { 'sr', '"', ')' }, { '""(a)""' }, { 1, 3 })
end

T['Builtin']['Default']['works in edge cases'] = function()
  local keys = { 'sr', '*', ')' }

  -- Consecutive identical matching characters
  validate_edit({ '****' }, { 1, 0 }, keys, { '()**' }, { 1, 1 })
  validate_edit({ '****' }, { 1, 1 }, keys, { '()**' }, { 1, 1 })
  validate_edit({ '****' }, { 1, 2 }, keys, { '*()*' }, { 1, 2 })
  validate_edit({ '****' }, { 1, 3 }, keys, { '**()' }, { 1, 3 })
end

T['Builtin']['Default']['supports any identifier which can be `getcharstr()` output'] = function()
  validate_edit({ 'aaa' }, { 1, 0 }, { 'sa', 'iw', 'ы' }, { 'ыaaaы' }, { 1, 2 })
  validate_edit({ 'ыaaaы' }, { 1, 3 }, { 'sd', 'ы' }, { 'aaa' }, { 1, 0 })
  validate_edit({ '(aaa)' }, { 1, 2 }, { 'sr', ')', 'ы' }, { 'ыaaaы' }, { 1, 2 })

  validate_edit({ 'aaa' }, { 1, 0 }, { 'sa', 'iw', '「' }, { '「aaa「' }, { 1, 3 })
  validate_edit({ '「aaa「' }, { 1, 3 }, { 'sd', '「' }, { 'aaa' }, { 1, 0 })
  validate_edit({ '(aaa)' }, { 1, 1 }, { 'sr', ')', '「' }, { '「aaa「' }, { 1, 3 })

  -- <C-j> is `\n`
  validate_edit({ 'aaa' }, { 1, 0 }, { 'sa', 'iw', '<C-j>' }, { '', 'aaa', '' }, { 1, 0 })
  validate_edit({ 'aaa', 'bbb', 'ccc' }, { 2, 0 }, { 'sd', '<C-j>' }, { 'aaabbbccc' }, { 1, 3 })
  validate_edit({ 'aaa', 'bbb', 'ccc' }, { 2, 0 }, { 'sr', '<C-j>', ')' }, { 'aaa(bbb)ccc' }, { 1, 4 })
end

T['Builtin']['Function call'] = new_set()

T['Builtin']['Function call']['works'] = function()
  -- Should work as input surrounding
  validate_edit({ 'myfunc(aaa)' }, { 1, 8 }, { 'sd', 'f' }, { 'aaa' }, { 1, 0 })

  -- Should work as output surrounding
  validate_edit({ '(aaa)' }, { 1, 2 }, { 'sr', ')', 'f', 'myfunc<CR>' }, { 'myfunc(aaa)' }, { 1, 7 })

  -- Should work with empty arguments
  validate_edit({ 'myfunc()' }, { 1, 0 }, { 'sd', 'f' }, { '' }, { 1, 0 })
end

T['Builtin']['Function call']['does not work in some cases'] = function()
  -- Although, it would be great if it did

  -- It does not take into account that part is inside string
  validate_edit({ [[myfunc(a, ')', b)]] }, { 1, 7 }, { 'sr', 'f', '>' }, { "<a, '>', b)" }, { 1, 1 })

  -- It does not take into account that part is inside comment
  child.bo.commentstring = '# %s'
  validate_edit({ 'myfunc(a', '# )', 'b)' }, { 1, 7 }, { 'sr', 'f', '>' }, { '<a', '# >', 'b)' }, { 1, 1 })
end

T['Builtin']['Function call']['is detected with "_" and "." in name'] = function()
  local keys = { 'sd', 'f' }
  validate_edit({ 'my_func(aaa)' }, { 1, 9 }, keys, { 'aaa' }, { 1, 0 })
  validate_edit({ 'my.func(aaa)' }, { 1, 9 }, keys, { 'aaa' }, { 1, 0 })
  validate_edit({ 'big-new_my.func(aaa)' }, { 1, 17 }, keys, { 'big-aaa' }, { 1, 4 })
  validate_edit({ 'big new_my.func(aaa)' }, { 1, 17 }, keys, { 'big aaa' }, { 1, 4 })

  validate_edit({ '[(myfun(aaa))]' }, { 1, 9 }, keys, { '[(aaa)]' }, { 1, 2 })
end

T['Builtin']['Function call']['works in different parts of line and neighborhood'] = function()
  local keys = { 'sd', 'f' }

  -- This check is viable because of complex nature of Lua patterns
  validate_edit({ 'myfunc(aaa)' }, { 1, 8 }, keys, { 'aaa' }, { 1, 0 })
  validate_edit({ 'Hello myfunc(aaa)' }, { 1, 14 }, keys, { 'Hello aaa' }, { 1, 6 })
  validate_edit({ 'myfunc(aaa) world' }, { 1, 8 }, keys, { 'aaa world' }, { 1, 0 })
  validate_edit({ 'Hello myfunc(aaa) world' }, { 1, 14 }, keys, { 'Hello aaa world' }, { 1, 6 })

  validate_edit({ 'myfunc(aaa)', 'Hello', 'world' }, { 1, 8 }, keys, { 'aaa', 'Hello', 'world' }, { 1, 0 })
  validate_edit({ 'Hello', 'myfunc(aaa)', 'world' }, { 2, 8 }, keys, { 'Hello', 'aaa', 'world' }, { 2, 0 })
  validate_edit({ 'Hello', 'world', 'myfunc(aaa)' }, { 3, 8 }, keys, { 'Hello', 'world', 'aaa' }, { 3, 0 })
end

T['Builtin']['Function call']['has limited support of multibyte characters'] = function()
  -- Due to limitations of Lua patterns used for detecting surrounding, it
  -- currently doesn't support detecting function calls with multibyte
  -- character in name. It would be great to fix this.
  expect.error(function() validate_edit({ 'ыыы(aaa)' }, { 1, 8 }, { 'sd', 'f' }, { 'aaa' }, { 1, 0 }) end)

  -- Should work in output surrounding
  validate_edit({ '(aaa)' }, { 1, 2 }, { 'sr', ')', 'f', 'ыыы<CR>' }, { 'ыыы(aaa)' }, { 1, 7 })
end

T['Builtin']['Function call']['handles <C-c>, <Esc>, <CR> in user input'] = function()
  -- Should do always nothing on `<C-c>` and `<Esc>`
  child.cmd('nnoremap <C-c> <C-\\><C-n>')
  validate_edit({ '(aaa)' }, { 1, 2 }, { 'sr', ')', 'f', '<Esc>' }, { '(aaa)' }, { 1, 2 })
  validate_edit({ '(aaa)' }, { 1, 2 }, { 'sr', ')', 'f', '<C-c>' }, { '(aaa)' }, { 1, 2 })

  -- Should treat `<CR>` as empty string input
  validate_edit({ '[aaa]' }, { 1, 2 }, { 'sr', ']', 'f', '<CR>' }, { '(aaa)' }, { 1, 1 })
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

T['Builtin']['Function call']["works with 'mini.input'"] = function()
  child.lua('require("mini.input").setup()')
  set_lines({ 'aaa' })

  type_keys('sa', 'iw', 'f')
  validate_miniinput('(mini.surround) Function name', 'cursor', '')
  type_keys('fun')
  validate_miniinput('(mini.surround) Function name', 'cursor', 'fun')
  type_keys('<CR>')
  validate_miniinput(nil, nil, nil)
  eq(get_lines(), { 'fun(aaa)' })
end

T['Builtin']['Tag'] = new_set()

T['Builtin']['Tag']['works'] = function()
  -- Should work as input surrounding
  validate_edit({ '<x>aaa</x>' }, { 1, 4 }, { 'sd', 't' }, { 'aaa' }, { 1, 0 })

  -- Should work as output surrounding
  validate_edit({ '(aaa)' }, { 1, 2 }, { 'sr', ')', 't', 'x<CR>' }, { '<x>aaa</x>' }, { 1, 3 })

  -- Should work with empty tag name
  validate_edit({ '<>aaa</>' }, { 1, 3 }, { 'sd', 't' }, { 'aaa' }, { 1, 0 })

  -- Should work with empty inside content
  validate_edit({ '<x></x>' }, { 1, 2 }, { 'sd', 't' }, { '' }, { 1, 0 })
end

T['Builtin']['Tag']['does not work in some cases'] = function()
  -- Although, it would be great if it did

  -- It does not take into account that part is inside string
  validate_edit({ [[<x>a, '</x>', b</x>]] }, { 1, 3 }, { 'sr', 't', '>' }, { "<a, '>', b</x>" }, { 1, 1 })

  -- It does not take into account that part is inside comment
  child.bo.commentstring = '# %s'
  validate_edit({ '<x>a', '# </x>', 'b</x>' }, { 1, 3 }, { 'sr', 't', '>' }, { '<a', '# >', 'b</x>' }, { 1, 1 })

  -- Tags result into smallest width
  validate_edit({ '<x><x></x></x>' }, { 1, 1 }, { 'sr', 't', '.' }, { '<x><x></x></x>' }, { 1, 1 })

  child.lua([[MiniSurround.config.search_method = 'cover_or_next']])
  validate_edit({ '<x><x></x></x>' }, { 1, 1 }, { 'sr', 't', '.' }, { '<x>..</x>' }, { 1, 4 })
  child.lua([[MiniSurround.config.search_method = 'cover']])

  -- Don't work at end of self-nesting tags
  validate_edit({ '<x><x></x></x>' }, { 1, 12 }, { 'sr', 't' }, { '<x><x></x></x>' }, { 1, 12 })
  has_message_about_not_found('t')
end

T['Builtin']['Tag']['detects tag with the same name'] = function()
  validate_edit({ '<x><y>a</x></y>' }, { 1, 1 }, { 'sr', 't', '_' }, { '_<y>a_</y>' }, { 1, 1 })
end

T['Builtin']['Tag']['allows extra symbols in opening tag on input'] = function()
  validate_edit({ '<x bbb cc_dd!>aaa</x>' }, { 1, 15 }, { 'sr', 't', '_' }, { '_aaa_' }, { 1, 1 })

  -- Symbol `<` is not allowed
  validate_edit({ '<x <>aaa</x>' }, { 1, 6 }, { 'sr', 't' }, { '<x <>aaa</x>' }, { 1, 6 })
  has_message_about_not_found('t')
end

T['Builtin']['Tag']['allows extra symbols in opening tag on output'] = function()
  validate_edit({ 'aaa' }, { 1, 0 }, { 'sa', 'iw', 't', 'a b', '<CR>' }, { '<a b>aaa</a>' }, { 1, 5 })
  validate_edit({ '<a b>aaa</a>' }, { 1, 5 }, { 'sr', 't', 't', 'a c', '<CR>' }, { '<a c>aaa</a>' }, { 1, 5 })
end

T['Builtin']['Tag']['detects covering with smallest width'] = function()
  local keys = { 'sr', 't', '_' }

  -- In all cases width of `<y>...</y>` is smaller than of `<x>...</x>`
  validate_edit({ '<x>  <y>a</x></y>' }, { 1, 8 }, keys, { '<x>  _a</x>_' }, { 1, 6 })
  validate_edit({ '<y><x>a</y>  </x>' }, { 1, 6 }, keys, { '_<x>a_  </x>' }, { 1, 1 })

  -- Width should be from the left-most point to right-most
  validate_edit({ '<y><x bbb>a</y></x>' }, { 1, 10 }, keys, { '_<x bbb>a_</x>' }, { 1, 1 })

  -- Works with identical nested tags
  validate_edit({ '<x><x>aaa</x></x>' }, { 1, 7 }, keys, { '<x>_aaa_</x>' }, { 1, 4 })
end

T['Builtin']['Tag']['works in edge cases'] = function()
  local keys = { 'sr', 't', '_' }

  -- Nesting different tags
  validate_edit({ '<x><y></y></x>' }, { 1, 1 }, keys, { '_<y></y>_' }, { 1, 1 })
  validate_edit({ '<x><y></y></x>' }, { 1, 4 }, keys, { '<x>__</x>' }, { 1, 4 })

  -- End of overlapping tags
  validate_edit({ '<y><x></y></x>' }, { 1, 12 }, keys, { '<y>_</y>_' }, { 1, 4 })

  -- `>` between tags
  validate_edit({ '<x>>aaa</x>' }, { 1, 5 }, keys, { '_>aaa_' }, { 1, 1 })

  -- Similar but different names shouldn't match
  validate_edit({ '<xy>aaa</x>' }, { 1, 5 }, { 'sd', 't' }, { '<xy>aaa</x>' }, { 1, 5 })
end

T['Builtin']['Tag']['has limited support of multibyte characters'] = function()
  -- Due to limitations of Lua patterns used for detecting surrounding, it
  -- currently doesn't support detecting tag with multibyte character in
  -- name. It would be great to fix this.
  expect.error(function() validate_edit({ '<ы>aaa</ы>' }, { 1, 5 }, { 'sd', 't' }, { 'aaa' }, { 1, 0 }) end)

  -- Should work in output surrounding
  validate_edit({ '(aaa)' }, { 1, 8 }, { 'sr', ')', 't', 'ы<CR>' }, { '<ы>aaa</ы>' }, { 1, 4 })
end

T['Builtin']['Tag']['handles <C-c>, <Esc>, <CR> in user input'] = function()
  -- Should do nothing on `<C-c>` and `<Esc>`
  validate_edit({ '(aaa)' }, { 1, 2 }, { 'sr', ')', 't', '<Esc>' }, { '(aaa)' }, { 1, 2 })
  validate_edit({ '(aaa)' }, { 1, 2 }, { 'sr', ')', 't', '<C-c>' }, { '(aaa)' }, { 1, 2 })

  -- Should treat `<CR>` as empty string input
  validate_edit({ '(aaa)' }, { 1, 2 }, { 'sr', ')', 't', '<CR>' }, { '<>aaa</>' }, { 1, 2 })
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

T['Builtin']['Tag']["works with 'mini.input'"] = function()
  child.lua('require("mini.input").setup()')
  set_lines({ 'aaa' })

  type_keys('sa', 'iw', 't')
  validate_miniinput('(mini.surround) Tag', 'cursor', '')
  type_keys('x')
  validate_miniinput('(mini.surround) Tag', 'cursor', 'x')
  type_keys('<CR>')
  validate_miniinput(nil, nil, nil)
  eq(get_lines(), { '<x>aaa</x>' })
end

T['Builtin']['User prompt'] = new_set()

T['Builtin']['User prompt']['works'] = function()
  -- Should work as input surrounding
  validate_edit({ '%*aaa*%' }, { 1, 3 }, { 'sd', '?', '%*<CR>', '*%<CR>' }, { 'aaa' }, { 1, 0 })

  -- Should work as output surrounding
  validate_edit({ '(aaa)' }, { 1, 2 }, { 'sr', ')', '?', '%*<CR>', '*%<CR>' }, { '%*aaa*%' }, { 1, 2 })
end

T['Builtin']['User prompt']['does not work in some cases'] = function()
  -- Although, it would be great if it did
  local keys = { 'sr', '?', '**<CR>', '**<CR>', '>' }

  -- It does not take into account that part is inside string
  validate_edit({ [[**a, '**', b**]] }, { 1, 2 }, keys, { "<a, '>', b**" }, { 1, 1 })

  -- It does not take into account that part is inside comment
  child.bo.commentstring = '# %s'
  validate_edit({ '**a', '# **', 'b**' }, { 1, 2 }, keys, { '<a', '# >', 'b**' }, { 1, 1 })

  -- It does not work sometimes in presence of many identical valid parts
  -- (basically because it is a `%(.-%)` and not `%(.*%)`).
  local keys = { 'sr', '?', '(<CR>', ')<CR>', '>' }
  validate_edit({ '((()))' }, { 1, 3 }, keys, { '((<>))' }, { 1, 3 })
  validate_edit({ '((()))' }, { 1, 4 }, keys, { '((()))' }, { 1, 4 })
  validate_edit({ '((()))' }, { 1, 5 }, keys, { '((()))' }, { 1, 5 })
end

T['Builtin']['User prompt']['detects covering with smallest width'] = function()
  local keys = { 'sr', '?', '**<CR>', '**<CR>', ')' }

  validate_edit({ '**a**aa**' }, { 1, 4 }, keys, { '(a)aa**' }, { 1, 1 })
  validate_edit({ '**aa**a**' }, { 1, 4 }, keys, { '**aa(a)' }, { 1, 5 })
end

T['Builtin']['User prompt']['works in edge cases'] = function()
  local keys = { 'sr', '?', '(<CR>', ')<CR>', '>' }

  -- Having `.-` in pattern means the smallest matching span
  validate_edit({ '(())' }, { 1, 0 }, keys, { '(())' }, { 1, 0 })
  validate_edit({ '(())' }, { 1, 1 }, keys, { '(<>)' }, { 1, 2 })
end

T['Builtin']['User prompt']['works with multibyte characters in parts'] = function()
  -- Should work as input surrounding
  validate_edit({ 'ыtttю' }, { 1, 3 }, { 'sd', '?', 'ы<CR>', 'ю<CR>' }, { 'ttt' }, { 1, 0 })

  -- Should work as output surrounding
  validate_edit({ 'ыtttю' }, { 1, 3 }, { 'sr', '?', 'ы<CR>', 'ю<CR>', ')' }, { '(ttt)' }, { 1, 1 })
end

T['Builtin']['User prompt']['handles <C-c>, <Esc>, <CR> in user input'] = function()
  local validate_single = function(...)
    child.ensure_normal_mode()
    -- Wait before every keygroup because otherwise it seems to randomly
    -- break for `<C-c>`
    child.ensure_normal_mode()

    set_lines({ '(aaa)' })
    set_cursor(1, 2)

    type_keys(10, ...)

    eq(child.get_lines(), { '(aaa)' })
    eq(child.get_cursor(), { 1, 2 })
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
  validate_edit({ '(aaa)' }, { 1, 2 }, { 'sr', ')', '?', '_<CR>', '<CR>' }, { '_aaa' }, { 1, 1 })
  validate_edit({ '(aaa)' }, { 1, 2 }, { 'sr', ')', '?', '<CR>', '_<CR>' }, { 'aaa_' }, { 1, 0 })
  validate_edit({ '(aaa)' }, { 1, 2 }, { 'sr', ')', '?', '<CR>', '<CR>' }, { 'aaa' }, { 1, 0 })

  -- Should stop on `<CR>` in input surrounding because can't use empty
  -- string in pattern search
  validate_edit({ '**aaa**' }, { 1, 3 }, { 'sr', '?', '<CR>' }, { '**aaa**' }, { 1, 3 })
  validate_edit({ '**aaa**' }, { 1, 3 }, { 'sr', '?', '**<CR>', '<CR>' }, { '**aaa**' }, { 1, 3 })
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

T['Builtin']['User prompt']["works with 'mini.input'"] = function()
  child.lua('require("mini.input").setup()')

  -- Output surrounding
  set_lines({ 'aaa' })
  type_keys('sa', 'iw', '?')
  validate_miniinput('(mini.surround) Left surrounding', 'cursor', '')
  type_keys('%*')
  validate_miniinput('(mini.surround) Left surrounding', 'cursor', '%*')
  type_keys('<CR>')
  validate_miniinput('(mini.surround) Right surrounding', 'cursor', '')
  type_keys('*%')
  validate_miniinput('(mini.surround) Right surrounding', 'cursor', '*%')
  type_keys('<CR>')
  validate_miniinput(nil, nil, nil)
  eq(get_lines(), { '%*aaa*%' })

  -- Input surrounding
  set_lines({ '%*aaa*%' })
  type_keys('sd', '?')
  validate_miniinput('(mini.surround) Left surrounding', 'cursor', '')
  type_keys('%*')
  validate_miniinput('(mini.surround) Left surrounding', 'cursor', '%*')
  type_keys('<CR>')
  validate_miniinput('(mini.surround) Right surrounding', 'cursor', '')
  type_keys('*%')
  validate_miniinput('(mini.surround) Right surrounding', 'cursor', '*%')
  type_keys('<CR>')
  validate_miniinput(nil, nil, nil)
  eq(get_lines(), { 'aaa' })
end

local set_custom_surr = function(tbl) child.lua('MiniSurround.config.custom_surroundings = ' .. vim.inspect(tbl)) end

T['Custom surrounding'] = new_set()

T['Custom surrounding']['works'] = function()
  set_custom_surr({ q = { input = { '@().-()#' }, output = { left = '@', right = '#' } } })

  validate_edit({ '@aaa#' }, { 1, 2 }, { 'sd', 'q' }, { 'aaa' }, { 1, 0 })
  validate_edit({ '(aaa)' }, { 1, 2 }, { 'sr', ')', 'q' }, { '@aaa#' }, { 1, 1 })
end

T['Custom surrounding']['supports any identifier which can be `getcharstr()` output'] = function()
  set_custom_surr({
    ['\22'] = { input = { '@().-()#' }, output = { left = '@', right = '#' } },
    ['ы'] = { input = { 'Ы().-()Ы' }, output = { left = 'Ы', right = 'Ы' } },
    ['「'] = { input = { '「().-()」' }, output = { left = '「', right = '」' } },
  })

  validate_edit({ ' aaa ' }, { 1, 1 }, { 'sa', 'iw', '「' }, { ' 「aaa」 ' }, { 1, 4 })
  validate_edit({ 'ЫaaaЫ' }, { 1, 3 }, { 'sd', 'ы' }, { 'aaa' }, { 1, 0 })
  validate_edit({ '@aaa#' }, { 1, 2 }, { 'sr', '<C-v>', '「' }, { '「aaa」' }, { 1, 3 })
  validate_edit({ '「aaa」' }, { 1, 3 }, { 'sr', '「', '<C-v>' }, { '@aaa#' }, { 1, 1 })
end

T['Custom surrounding']['overrides builtins'] = function()
  set_custom_surr({ ['('] = { input = { '%(%(().-()%)%)' }, output = { left = '((', right = '))' } } })

  validate_edit({ '((aaa))' }, { 1, 2 }, { 'sd', '(' }, { 'aaa' }, { 1, 0 })
  validate_edit({ 'aaa' }, { 1, 0 }, { 'sa', 'iw', '(' }, { '((aaa))' }, { 1, 2 })
end

T['Custom surrounding']['allows setting partial information'] = function()
  -- Modifying present single character identifier (takes from present)
  set_custom_surr({ [')'] = { output = { left = '( ', right = ' )' } } })

  validate_edit({ '(aaa)' }, { 1, 2 }, { 'sd', ')' }, { 'aaa' }, { 1, 0 })
  validate_edit({ '<aaa>' }, { 1, 2 }, { 'sr', '>', ')' }, { '( aaa )' }, { 1, 2 })

  -- New single character identifier (takes from default)
  set_custom_surr({ ['#'] = { input = { '#_().-()_#' } } })

  -- Should find '#_' and '_#' and extract first and last two characters
  validate_edit({ '_#_aaa_#_' }, { 1, 4 }, { 'sd', '#' }, { '_aaa_' }, { 1, 1 })
  -- `output` should be taken from default
  validate_edit({ '(aaa)' }, { 1, 2 }, { 'sr', ')', '#' }, { '#aaa#' }, { 1, 1 })
end

T['Custom surrounding']['validates captures in extract pattern'] = function()
  -- Avoid hit-enter-prompt from three big error message
  child.o.cmdheight = 40

  local validate = function(line, col, key)
    set_lines({ line })
    set_cursor(1, col)
    expect.error(function() type_keys('sd', key) end, 'two or four empty captures')

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
  local keys = { 'sr', '#', '>' }

  set_custom_surr({ ['#'] = { input = { '#().-()@' } } })

  -- Using `.-` results into match with smallest width
  validate_edit({ '##@@' }, { 1, 0 }, keys, { '##@@' }, { 1, 0 })
  validate_edit({ '##@@' }, { 1, 1 }, keys, { '#<>@' }, { 1, 2 })

  child.lua([[MiniSurround.config.search_method = 'cover_or_next']])
  validate_edit({ '##@@' }, { 1, 0 }, keys, { '#<>@' }, { 1, 2 })
end

T['Custom surrounding']['works with empty parts in input surrounding'] = function()
  set_custom_surr({ x = { input = { 'x()().-()x()' } } })
  validate_edit1d('axbbbxc', 3, { 'sd', 'x' }, 'axbbbc', 2)
  validate_edit1d('axbbbxc', 3, { 'sr', 'x', '>' }, 'ax<bbb>c', 3)

  set_custom_surr({ y = { input = { '()y().-y()()' } } })
  validate_edit1d('aybbbyc', 3, { 'sd', 'y' }, 'abbbyc', 1)
  validate_edit1d('aybbbyc', 3, { 'sr', 'y', '>' }, 'a<bbby>c', 2)

  set_custom_surr({ t = { input = { '()()t.-t()()' } } })
  validate_edit1d('atbbbtc', 3, { 'sd', 't' }, 'atbbbtc', 1)
  validate_edit1d('atbbbtc', 3, { 'sr', 't', '>' }, 'a<tbbbt>c', 2)
end

T['Custom surrounding']['handles function as surrounding spec'] = function()
  -- Function which returns composed pattern
  child.lua([[MiniSurround.config.custom_surroundings = {
    x = { input = function(...) _G.args = {...}; return {'x()x()x'} end }
  }]])

  validate_edit1d('aaxxxbb', 2, { 'sr', 'x', '>' }, 'aa<x>bb', 3)
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
  validate_edit({ 'aa', 'bb', '' }, { 2, 0 }, { 'sr', 'e', ')' }, { '(', 'bb', ')' }, { 1, 0 })

  -- Function which returns array of region pairs
end

T['Custom surrounding']['handles function as specification item'] = function()
  child.lua([[_G.c_spec = {
    '%b()',
    function(s, init) if init > 1 then return end; return 2, s:len() end,
    '^().*().$'
  }]])
  child.lua([[MiniSurround.config.custom_surroundings = { c = { input = _G.c_spec } }]])
  validate_edit1d('aa(bb)', 3, { 'sr', 'c', '>' }, 'aa(<bb>', 4)
end

T['Custom surrounding']['works with special patterns'] = new_set()

T['Custom surrounding']['works with special patterns']['%bxx'] = function()
  -- Avoid hit-enter-prompt from three big error message
  child.o.cmdheight = 40

  -- `%bxx` should represent balanced character
  set_custom_surr({ e = { input = { '%bee', '^e().*()e$' } } })

  local line = 'e e e e e'
  local keys = { 'sr', 'e', '>' }

  for i = 0, 2 do
    validate_edit1d(line, i, keys, '< > e e e', 1)
  end
  for i = 4, 6 do
    validate_edit1d(line, i, keys, 'e e < > e', 5)
  end

  for _, i in ipairs({ 3, 7, 8 }) do
    validate_edit1d(line, i, keys, 'e e e e e', i)
  end
end

T['Custom surrounding']['works with special patterns']['x.-y'] = function()
  child.lua([[MiniSurround.config.search_method = 'cover_or_next']])

  -- `x.-y` should match the smallest possible width
  set_custom_surr({ x = { input = { 'e.-o', '^.().*().$' } } })
  validate_edit1d('e e o o e o', 0, { 'sr', 'x', '>' }, 'e < > o e o', 3)
  validate_edit1d('e e o o e o', 0, { '2sr', 'x', '>' }, 'e e o o < >', 9)

  -- `x.-y` should work with `a%.-a` and `a.%-a`
  set_custom_surr({ y = { input = { 'y()%.-()y' } } })
  validate_edit1d('y.y yay y..y', 0, { 'sr', 'y', '>' }, '<.> yay y..y', 1)
  validate_edit1d('y.y yay y..y', 0, { '2sr', 'y', '>' }, 'y.y yay <..>', 9)

  set_custom_surr({ c = { input = { 'c().%-()c' } } })
  validate_edit1d('c_-c c__c c+-c', 0, { 'sr', 'c', '>' }, '<_-> c__c c+-c', 1)
  validate_edit1d('c_-c c__c c+-c', 0, { '2sr', 'c', '>' }, 'c_-c c__c <+->', 11)

  -- `x.-y` should allow patterns with `+` quantifiers
  -- To improve, force other character in between (`%f[x]x+[^x]-x+%f[^x]`)
  set_custom_surr({ r = { input = { 'r+().-()r+' } } })
  validate_edit1d('rraarr', 0, { 'sr', 'r', '>' }, 'rraa<>', 5)
  validate_edit1d('rrrr', 0, { 'sr', 'r', '>' }, 'rr<>', 3)
end

T['Custom surrounding']['works with quantifiers in patterns'] = function()
  child.lua([[MiniSurround.config.search_method = 'cover_or_next']])

  set_custom_surr({ x = { input = { '%f[x]x+%f[^x]', '^x().*()x$' } } })
  validate_edit1d('axxaxxx', 0, { 'sr', 'x', '>' }, 'a<>axxx', 2)
  validate_edit1d('axxaxxx', 0, { '2sr', 'x', '>' }, 'axxa<x>', 5)
end

T['Custom surrounding']['works with multibyte characters'] = function()
  set_custom_surr({ x = { input = { 'ыы фф', '^.-() ().-$' } } })
  validate_edit1d('ыы ыы фф фф', 9, { 'sr', 'x', '>' }, 'ыы < > фф', 6)
end

T['Custom surrounding']['documented examples'] = new_set()

T['Custom surrounding']['documented examples']['function call with name from user input'] = function()
  child.lua([[MiniSurround.config.search_method = 'cover_or_next']])
  child.lua([[_G.fun_prompt = function()
    local left_edge = vim.pesc(vim.fn.input('Function name: '))
    return { string.format('%s+%%b()', left_edge), '^.-%(().*()%)$' }
  end]])
  child.lua('MiniSurround.config.custom_surroundings = { F = { input = _G.fun_prompt} }')

  validate_edit1d('aa(xx) bb(xx)', 0, { 'sr', 'F', 'bb<CR>', '>' }, 'aa(xx) <xx>', 8)
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
  validate_edit({ 'aa', 'bb', '' }, { 2, 0 }, { 'sr', 'e', ')' }, { '(', 'bb', ')' }, { 1, 0 })
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
  validate_edit1d('aa[[bb]]cc', 2, { 'sr', 's', '>' }, 'aa<bb>cc', 3)
  validate_edit1d('aa(bb)cc', 2, { 'sr', ')', 's' }, 'aa[[bb]]cc', 4)
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

  validate_edit1d('() (a) (aa) (aaa)', 0, { 'sr', 'p', '>' }, '() (a) (aa) <aaa>', 13)
end

T['Custom surrounding']['documented examples']['handles function as specification item'] = function()
  child.lua([[_G.c_spec = {
    '%b()',
    function(s, init) if init > 1 then return end; return 2, s:len() end,
    '^().*().$'
  }]])
  child.lua([[MiniSurround.config.custom_surroundings = { c = { input = _G.c_spec } }]])
  validate_edit1d('aa(bb)', 3, { 'sr', 'c', '>' }, 'aa(<bb>', 4)
end

T['Custom surrounding']['documented examples']['brackets with newlines'] = function()
  child.lua([=[MiniSurround.config.custom_surroundings = {
    x = { output = { left = '(\n', right = '\n)' } }
  }]=])
  validate_edit({ '  aaa' }, { 1, 2 }, { 'sa', 'iw', 'x' }, { '  (', 'aaa', ')' }, { 1, 2 })
end

return T
