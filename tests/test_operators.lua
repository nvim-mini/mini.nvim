local helpers = dofile('tests/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('operators', config) end
local unload_module = function() child.mini_unload('operators') end
local reload_module = function(config) unload_module(); load_module(config) end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
--stylua: ignore end

local forward_lua = function(fun_str)
  local lua_cmd = fun_str .. '(...)'
  return function(...) return child.lua_get(lua_cmd, { ... }) end
end

-- Custom validators
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
  eq(child.lua_get('type(_G.MiniOperators)'), 'table')

  -- Autocommand group
  eq(child.fn.exists('#MiniOperators'), 1)

  -- Highlight groups
  child.cmd('hi clear')
  load_module()
  local validate_hl_group = function(name, ref) expect.match(child.cmd_capture('hi ' .. name), ref) end

  validate_hl_group('MiniOperatorsExchangeFrom', 'links to IncSearch')
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniOperators.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniOperators.config.' .. field), value) end

  expect_config('evaluate.prefix', 'g=')
  expect_config('evaluate.func', vim.NIL)

  expect_config('exchange.prefix', 'gx')
  expect_config('exchange.reindent_linewise', true)

  expect_config('multiply.prefix', 'gm')
  expect_config('multiply.func', vim.NIL)

  expect_config('replace.prefix', 'gr')
  expect_config('replace.reindent_linewise', true)

  expect_config('sort.prefix', 'gs')
  expect_config('sort.func', vim.NIL)
end

T['setup()']['respects `config` argument'] = function()
  reload_module({ exchange = { reindent_linewise = false } })
  eq(child.lua_get('MiniOperators.config.exchange.reindent_linewise'), false)
end

T['setup()']['validates `config` argument'] = function()
  unload_module()
  local expect_config_error = function(config, name, target_type)
    expect.error(function() load_module(config) end, vim.pesc(name) .. '.*' .. vim.pesc(target_type))
  end

  expect_config_error('a', 'config', 'table')

  expect_config_error({ evaluate = 'a' }, 'evaluate', 'table')
  expect_config_error({ evaluate = { prefix = 1 } }, 'evaluate.prefix', 'string')
  expect_config_error({ evaluate = { func = 'a' } }, 'evaluate.func', 'function')

  expect_config_error({ exchange = 'a' }, 'exchange', 'table')
  expect_config_error({ exchange = { prefix = 1 } }, 'exchange.prefix', 'string')
  expect_config_error({ exchange = { reindent_linewise = 'a' } }, 'exchange.reindent_linewise', 'boolean')

  expect_config_error({ multiply = 'a' }, 'multiply', 'table')
  expect_config_error({ multiply = { prefix = 1 } }, 'multiply.prefix', 'string')
  expect_config_error({ multiply = { func = 'a' } }, 'multiply.func', 'function')

  expect_config_error({ replace = 'a' }, 'replace', 'table')
  expect_config_error({ replace = { prefix = 1 } }, 'replace.prefix', 'string')
  expect_config_error({ replace = { reindent_linewise = 'a' } }, 'replace.reindent_linewise', 'boolean')

  expect_config_error({ sort = 'a' }, 'sort', 'table')
  expect_config_error({ sort = { prefix = 1 } }, 'sort.prefix', 'string')
  expect_config_error({ sort = { func = 'a' } }, 'sort.func', 'function')
end

T['setup()']['ensures colors'] = function()
  child.cmd('colorscheme default')
  expect.match(child.cmd_capture('hi MiniOperatorsExchangeFrom'), 'links to IncSearch')
end

T['setup()']['removes built-in LSP mappings'] = function()
  eq(child.fn.maparg('gra'), '')
  eq(child.fn.maparg('gri'), '')
  eq(child.fn.maparg('grn'), '')
  eq(child.fn.maparg('grt'), '')
end

T['setup()']['remaps built-in `gx` mappings'] = function()
  if child.fn.has('nvim-0.10') == 0 then MiniTest.skip('Neovim<0.10 does not have built-in `gx` mappings') end

  child.lua('vim.ui.open = function() _G.n = (_G.n or 0) + 1 end')
  local validate = function(keys, ref_n)
    type_keys(keys)
    eq(child.lua_get('_G.n'), ref_n)
  end

  validate('gX', 1)
  validate('vgX', 2)

  -- Should remap only built-in `gx`
  child.lua('vim.keymap.del({ "n", "x" }, "gX")')
  child.lua('vim.keymap.set({ "n", "x" }, "gx", function() _G.n = _G.n + 5 end)')
  child.lua('MiniOperators.setup()')
  validate('gX', 2)
  validate('vgX', 2)

  -- Should not override already present mapping
  child.lua('vim.keymap.set({ "n", "x" }, "gx", function() _G.n = _G.n + 5 end, { desc = "URI under cursor" })')
  child.lua('vim.keymap.set({ "n", "x" }, "gX", function() _G.n = _G.n + 10 end)')
  child.lua('MiniOperators.setup()')
  validate('gX', 12)
  validate('vgX', 22)
end

T['evaluate()'] = new_set()

T['evaluate()']['is present'] = function() eq(child.lua_get('type(MiniOperators.evaluate)'), 'function') end

T['exchange()'] = new_set()

T['exchange()']['is present'] = function() eq(child.lua_get('type(MiniOperators.exchange)'), 'function') end

T['replace()'] = new_set()

T['replace()']['is present'] = function() eq(child.lua_get('type(MiniOperators.replace)'), 'function') end

T['sort()'] = new_set()

T['sort()']['is present'] = function() eq(child.lua_get('type(MiniOperators.sort)'), 'function') end

T['make_mappings()'] = new_set()

local make_mappings = forward_lua('MiniOperators.make_mappings')

-- Targeted tests for each operator is done in tests for every operator

T['make_mappings()']['respects empty string as lhs'] = function()
  child.api.nvim_del_keymap('n', 'gr')
  child.api.nvim_del_keymap('n', 'grr')
  child.api.nvim_del_keymap('x', 'gr')

  -- Should not create mapping for that particular variant
  local lhs_tbl_ref = { textobject = 'cs', line = 'css', selection = 'cs' }

  local validate = function(variant)
    pcall(child.api.nvim_del_keymap, 'n', 'cs')
    pcall(child.api.nvim_del_keymap, 'n', 'css')
    pcall(child.api.nvim_del_keymap, 'x', 'cs')

    local lhs_tbl = vim.deepcopy(lhs_tbl_ref)
    lhs_tbl[variant] = ''
    -- Creating mapping for line is not allowed without textobject mapping
    if variant == 'textobject' then lhs_tbl.line = '' end
    make_mappings('replace', lhs_tbl)

    local mode = variant == 'selection' and 'x' or 'n'
    eq(child.fn.maparg(lhs_tbl_ref[variant], mode), '')
  end

  validate('textobject')
  validate('line')
  validate('selection')
end

T['make_mappings()']['validates arguments'] = function()
  expect.error(function() make_mappings(1, {}) end, '`operator_name`')

  expect.error(function() make_mappings('replace', 1) end, '`lhs_tbl`')
  expect.error(function() make_mappings('replace', { textobject = 1, line = 'crr', selection = 'cr' }) end, '`lhs_tbl`')
  expect.error(function() make_mappings('replace', { textobject = 'cr', line = 1, selection = 'cr' }) end, '`lhs_tbl`')
  expect.error(function() make_mappings('replace', { textobject = 'cr', line = 'crr', selection = 1 }) end, '`lhs_tbl`')

  expect.error(
    function() make_mappings('replace', { textobject = '', line = 'crr', selection = 'cr' }) end,
    '`line`.*`textobject`'
  )
end

T['default_sort_func()'] = new_set()

local default_sort_func = forward_lua('MiniOperators.default_sort_func')

T['default_sort_func()']['works for charwise'] = function()
  local validate = function(lines_input, ref_output)
    eq(default_sort_func({ lines = lines_input, submode = 'v' }), ref_output)
  end

  -- Basic tests
  validate({ 'b, a' }, { 'a, b' })
  validate({ 'b; a' }, { 'a; b' })
  validate({ 'b a' }, { 'a b' })
  validate({ 'ba' }, { 'ab' })

  -- Already sorted
  validate({ 'a, b' }, { 'a, b' })

  -- Correctly picks split pattern (',' > ';' > '%s*' > '')
  validate({ 'c, a; b' }, { 'a; b, c' })
  validate({ 'c a; b' }, { 'b; c a' })
  validate({ 'c a b' }, { 'a b c' })

  -- Works with whitespace (preserves and sorts without it)
  validate({ 'e ,  d,   b    ,a,c' }, { 'a ,  b,   c    ,d,e' })
  validate({ 'e ;  d;   b    ;a;c' }, { 'a ;  b;   c    ;d;e' })
  validate({ 'c a  b' }, { 'a b  c' })

  -- Works with multiline region
  validate({ 'c, a, ', 'b' }, { 'a, b, ', 'c' })
  -- - Here there are essentially three parts: 'c', 'd\na', 'b\ne'.
  --   They are sorted and then resplit by '\n'.
  validate({ 'c, d', 'a, b', 'e' }, { 'b', 'e, c, d', 'a' })

  -- Works with empty parts
  validate({ 'b,,a,' }, { ',,a,b' })
end

T['default_sort_func()']['works for linewise'] = function()
  local validate = function(lines_input, ref_output)
    eq(default_sort_func({ lines = lines_input, submode = 'V' }), ref_output)
  end

  validate({ 'c', 'a', 'b' }, { 'a', 'b', 'c' })
  validate({ 'xc', 'xa', 'xb' }, { 'xa', 'xb', 'xc' })

  -- Already sorted
  validate({ 'a', 'b' }, { 'a', 'b' })

  -- Doesn't ignore whitespace
  validate({ 'a', ' b' }, { ' b', 'a' })
end

T['default_sort_func()']['works for blockwise'] = function()
  local validate = function(lines_input, ref_output)
    eq(default_sort_func({ lines = lines_input, submode = '\22' }), ref_output)
  end

  validate({ 'c', 'a', 'b' }, { 'a', 'b', 'c' })
  validate({ 'xc', 'xa', 'xb' }, { 'xa', 'xb', 'xc' })

  -- Already sorted
  validate({ 'a', 'b' }, { 'a', 'b' })

  -- Doesn't ignore whitespace
  validate({ 'a', ' b' }, { ' b', 'a' })
end

T['default_sort_func()']['respects `opts.compare_fun`'] = function()
  -- Compare by the second character
  child.lua('_G.compare_fun = function(a, b) return a:sub(2, 2) < b:sub(2, 2) end')

  eq(
    child.lua_get([[MiniOperators.default_sort_func(
        { lines = { 'ab', 'ba' }, submode = 'V' },
        { compare_fun = _G.compare_fun }
      )]]),
    { 'ba', 'ab' }
  )
end

T['default_sort_func()']['respects `opts.split_patterns`'] = function()
  local validate = function(lines_input, ref_output, split_patterns)
    eq(default_sort_func({ lines = lines_input, submode = 'v' }, { split_patterns = split_patterns }), ref_output)
  end

  validate({ 'b + c+a' }, { ' c+a+b ' }, { '%+' })
  validate({ 'b + c+a' }, { 'a + b+c' }, { '%s*%+%s*' })

  validate({ 'b++c+++a' }, { '+++a+b+c' }, { '%+' })
  validate({ 'b++c+++a' }, { 'a++b+++c' }, { '%++' })

  -- Correctly picks in order
  validate({ 'c+b-a' }, { 'b-a+c' }, { '%+', '%-' })
  validate({ 'c-b-a' }, { 'a-b-c' }, { '%+', '%-' })

  -- Allows empty string as pattern
  validate({ 'c a b' }, { '  abc' }, { '' })

  -- Does nothing if no pattern is found
  validate({ 'c a b' }, { 'c a b' }, { ',' })
end

T['default_sort_func()']['validates arguments'] = function()
  expect.error(function() default_sort_func(1) end, '`content`')
  expect.error(function() default_sort_func({}) end, '`content`')
  expect.error(function() default_sort_func({ submode = 'v' }) end, '`content`')
  expect.error(function() default_sort_func({ lines = { 'a' } }) end, '`content`')

  local content = { lines = { 'a', 'b' }, submode = 'V' }
  expect.error(function() default_sort_func(content, { compare_fun = 1 }) end, '`opts.compare_fun`')
  expect.error(function() default_sort_func(content, { split_patterns = 1 }) end, '`opts.split_patterns`')
end

T['default_evaluate_func()'] = new_set()

local default_evaluate_func = forward_lua('MiniOperators.default_evaluate_func')

T['default_evaluate_func()']['works for charwise and linewise'] = new_set({ parametrize = { { 'v' }, { 'V' } } }, {
  test = function(submode)
    local validate = function(lines_input, ref_output)
      eq(default_evaluate_func({ lines = lines_input, submode = submode }), ref_output)
    end

    validate({ '1 + 1' }, { '2' })
    validate({ 'local x = 1', 'x + 1' }, { '2' })
    eq(child.lua_get('x'), vim.NIL)

    -- Should allow `return` in last line
    validate({ 'return 1 + 1' }, { '2' })
    validate({ 'local x = 1', 'return x + 1' }, { '2' })

    -- Should be possible to use global variables
    child.lua('_G.y = 1')
    validate({ '_G.y + 1' }, { '2' })

    -- Should `vim.inspect()` returned object(s)
    validate({ 'local t = {}', 't.a = 1', 't' }, { '{', '  a = 1', '}' })

    -- Should allow returning tuple
    validate({ 'local t = { a = 1 }', 't, 1' }, { '{', '  a = 1', '}', '1' })

    -- Should allow `nil` in tuple
    validate({ 'local x = 1', 'x - 1, nil, x + 1, nil' }, { '0', 'nil', '2', 'nil' })

    -- Should allow comments
    validate({ '-- A comment', '1 + 1' }, { '2' })
  end,
})

T['default_evaluate_func()']['works for blockwise'] = function()
  local validate = function(lines_input, ref_output)
    eq(default_evaluate_func({ lines = lines_input, submode = '\22' }), ref_output)
  end

  -- Should evaluate each line separately
  validate({ '1 + 1' }, { '2' })
  validate({ '1 + 1', '1 + 2' }, { '2', '3' })
  validate({ '1 + 1', 'return 1 + 2' }, { '2', '3' })

  -- Should be possible to use global variables
  child.lua('_G.y = 1')
  validate({ '_G.y + 1' }, { '2' })
end

T['default_evaluate_func()']['does not modify input'] = function()
  local validate = function(content)
    local lua_cmd = string.format(
      [[_G.content = %s
        MiniOperators.default_evaluate_func(_G.content)]],
      vim.inspect(content)
    )
    child.lua(lua_cmd)
    eq(child.lua_get('_G.content'), content)
  end

  validate({ lines = { '1 + 1' }, submode = 'v' })
  validate({ lines = { '1 + 1' }, submode = 'V' })
  validate({ lines = { '1 + 1', '1 + 2' }, submode = '\22' })
end

T['default_evaluate_func()']['validates arguments'] = function()
  expect.error(function() default_evaluate_func(1) end, '`content`')
  expect.error(function() default_evaluate_func({}) end, '`content`')
  expect.error(function() default_evaluate_func({ submode = 'v' }) end, '`content`')
  expect.error(function() default_evaluate_func({ lines = { 'a' } }) end, '`content`')
end

-- Integration tests ==========================================================
T['Evaluate'] = new_set()

-- More testing is done in `default_evaluate_func()` tests

T['Evaluate']['works charwise in Normal mode'] = function()
  validate_edit1d('1 + 1 = 1 + 1', 8, { 'g=$' }, '1 + 1 = 2', 8)

  validate_edit({ 'local x = 1', 'x + 1 ' }, { 1, 0 }, { 'g=/ $<CR>' }, { '2 ' }, { 1, 0 })

  -- With dot-repeat
  validate_edit({ '1 + 1', '1 + 2' }, { 1, 0 }, { 'g=$', 'j', '.' }, { '2', '3' }, { 2, 0 })
end

T['Evaluate']['works linewise in Normal mode'] = function()
  validate_edit(
    { 'Not evaluated', 'local x = 1', 'return x + 1' },
    { 2, 0 },
    { 'g=j' },
    { 'Not evaluated', '2' },
    { 2, 0 }
  )

  -- With dot-repeat
  validate_edit({ '1 + 1', '1 + 2' }, { 1, 0 }, { 'g=_', 'j', '.' }, { '2', '3' }, { 2, 0 })
end

T['Evaluate']['works blockwise in Normal mode'] = function()
  child.lua([[vim.keymap.set('o', 'ia', function() vim.cmd('normal! \22j$') end)]])
  child.lua([[vim.keymap.set('o', 'ib', function() vim.cmd('normal! \22j4l') end)]])

  validate_edit({ '1 + 1', '1 + 2' }, { 1, 0 }, { 'g=ia' }, { '2', '3' }, { 1, 0 })
  validate_edit({ 'x=10-10=x', 'y=20-20=y' }, { 1, 2 }, { 'g=ib' }, { 'x=0    =x', 'y=0    =y' }, { 1, 2 })

  -- With dot-repeat
  validate_edit(
    { '1 + 1', '1 + 2', '1 + 3', '1 + 4' },
    { 1, 0 },
    { 'g=ia', '2j', '.' },
    { '2', '3', '4', '5' },
    { 3, 0 }
  )
end

T['Evaluate']['works in Normal mode for line'] = function()
  validate_edit({ '1 + 1' }, { 1, 0 }, { 'g==' }, { '2' }, { 1, 0 })

  -- With dot-repeat
  validate_edit({ '1 + 1', '1 + 2' }, { 1, 0 }, { 'g==', 'j', '.' }, { '2', '3' }, { 2, 0 })
end

T['Evaluate']['works with empty textobject/motion'] = function()
  child.api.nvim_set_keymap('o', 'w', '<Cmd><CR>', {})
  child.lua('_G.x = 1')
  set_lines({ 'xxx' })
  set_cursor(1, 1)
  type_keys('g=', 'w')
  eq(get_lines(), { 'xxx' })
end

T['Evaluate']['works in Visual mode'] = function()
  -- Charwise
  validate_edit({ '1 + 1 = (1 + 1)' }, { 1, 8 }, { 'va)', 'g=' }, { '1 + 1 = 2' }, { 1, 8 })
  validate_edit({ 'local x = 1', 'x - 1, x + 1' }, { 1, 0 }, { 'vj$', 'g=' }, { '0', '2' }, { 1, 0 })

  -- Linewise
  validate_edit({ 'local x = 1', 'x - 1, x + 1' }, { 1, 0 }, { 'Vj', 'g=' }, { '0', '2' }, { 1, 0 })

  -- Blockwise
  validate_edit({ '1 + 1', '1 + 2' }, { 1, 0 }, { '<C-v>j$', 'g=' }, { '2', '3' }, { 1, 0 })
end

T['Evaluate']['works with different `virtualedit`'] = function()
  local validate = function()
    -- Charwise
    validate_edit1d('1+1=x', 0, { 'g=', '3l' }, '2=x', 0)
    validate_edit1d('x=1+1=x', 2, { 'g=', '3l' }, 'x=2=x', 2)
    validate_edit1d('x=1+1', 2, { 'g=', '3l' }, 'x=2', 2)

    validate_edit1d('1+1=x', 0, { 'v2l', 'g=' }, '2=x', 0)
    validate_edit1d('x=1+1=x', 2, { 'v2l', 'g=' }, 'x=2=x', 2)
    validate_edit1d('x=1+1', 2, { 'v2l', 'g=' }, 'x=2', 2)

    -- Linewise
    validate_edit({ '0+1', '0+2', '0+3' }, { 1, 0 }, { 'g==' }, { '1', '0+2', '0+3' }, { 1, 0 })
    validate_edit({ '0+1', '0+2', '0+3' }, { 2, 0 }, { 'g==' }, { '0+1', '2', '0+3' }, { 2, 0 })
    validate_edit({ '0+1', '0+2', '0+3' }, { 3, 0 }, { 'g==' }, { '0+1', '0+2', '3' }, { 3, 0 })

    validate_edit({ '0+1', '0+2', '0+3' }, { 1, 0 }, { 'V', 'g=' }, { '1', '0+2', '0+3' }, { 1, 0 })
    validate_edit({ '0+1', '0+2', '0+3' }, { 2, 0 }, { 'V', 'g=' }, { '0+1', '2', '0+3' }, { 2, 0 })
    validate_edit({ '0+1', '0+2', '0+3' }, { 3, 0 }, { 'V', 'g=' }, { '0+1', '0+2', '3' }, { 3, 0 })

    -- Blockwise
    child.lua([[vim.keymap.set('o', 'iL', function() vim.cmd('normal! \22jll') end)]])
    validate_edit({ '1+1=x', '1+2=y' }, { 1, 0 }, { 'g=', 'iL' }, { '2  =x', '3  =y' }, { 1, 0 })
    validate_edit({ 'x=1+1=x', 'y=1+2=y' }, { 1, 2 }, { 'g=', 'iL' }, { 'x=2  =x', 'y=3  =y' }, { 1, 2 })
    validate_edit({ 'x=1+1', 'y=1+2' }, { 1, 2 }, { 'g=', 'iL' }, { 'x=2', 'y=3' }, { 1, 2 })

    validate_edit({ '1+1=x', '1+2=y' }, { 1, 0 }, { '<C-v>jll', 'g=' }, { '2  =x', '3  =y' }, { 1, 0 })
    validate_edit({ 'x=1+1=x', 'y=1+2=y' }, { 1, 2 }, { '<C-v>jll', 'g=' }, { 'x=2  =x', 'y=3  =y' }, { 1, 2 })
    validate_edit({ 'x=1+1', 'y=1+2' }, { 1, 2 }, { '<C-v>jll', 'g=' }, { 'x=2', 'y=3' }, { 1, 2 })
  end

  child.o.virtualedit = 'all'
  validate()
  child.o.virtualedit = 'onemore'
  validate()
  child.o.virtualedit = 'block'
  validate()
end

T['Evaluate']['respects `config.evaluate.func`'] = function()
  child.lua([[MiniOperators.config.evaluate.func = function() return { 'a', 'b' } end]])

  validate_edit({ '1 + 1' }, { 1, 0 }, { 'g=ip' }, { 'a', 'b' }, { 1, 0 })
end

T['Evaluate']["works with 'y' in 'cpoptions'"] = function()
  child.cmd('set cpoptions+=y')

  -- Dot-repeat should still work
  validate_edit1d('(1 + 1) (1 + 2)', 0, { 'g=i)', 'f(', '.' }, '(2) (3)', 5)
end

T['Evaluate']['does not have side effects'] = function()
  set_lines({ 'local x = 1', 'x + 1', 'xy' })

  -- All non-operator related marks and registers 'x', '"'
  set_cursor(3, 0)
  type_keys('ma')
  type_keys('v"xy')

  set_cursor(3, 1)
  type_keys('mx')
  type_keys('vy')

  -- Do evaluate
  set_cursor(1, 0)
  type_keys('g=j')

  -- Validate
  eq(get_lines(), { '2', 'xy' })
  eq(child.api.nvim_buf_get_mark(0, 'a'), { 2, 0 })
  eq(child.api.nvim_buf_get_mark(0, 'x'), { 2, 1 })
  eq(child.fn.getreg('x'), 'x')
  eq(child.fn.getreg('"'), 'y')
end

T['Evaluate']['preserves visual marks'] = function()
  set_lines({ 'local x = 1', 'x + 1', 'select' })

  -- Create marks
  set_cursor(3, 0)
  type_keys('viw', '<Esc>')

  -- Sort
  set_cursor(1, 0)
  type_keys('g=j')
  eq(get_lines(), { '2', 'select' })
  eq(child.api.nvim_buf_get_mark(0, '<'), { 2, 0 })
  eq(child.api.nvim_buf_get_mark(0, '>'), { 2, 5 })
end

T['Evaluate']['respects `config.evaluate.prefix`'] = function()
  child.api.nvim_del_keymap('n', 'g=')
  child.api.nvim_del_keymap('n', 'g==')
  child.api.nvim_del_keymap('x', 'g=')

  load_module({ evaluate = { prefix = 'c=' } })

  validate_edit1d('1 + 1', 0, { 'c=$' }, '2', 0)
  validate_edit1d('1 + 1', 0, { 'c==' }, '2', 0)
  validate_edit1d('1 + 1', 0, { 'v$', 'c=' }, '2', 0)
end

T['Evaluate']['works with `make_mappings()`'] = function()
  child.api.nvim_del_keymap('n', 'g=')
  child.api.nvim_del_keymap('n', 'g==')
  child.api.nvim_del_keymap('x', 'g=')

  load_module({ evaluate = { prefix = '' } })
  make_mappings('evaluate', { textobject = 'c=', line = 'c==', selection = 'c=' })

  validate_edit1d('1 + 1', 0, { 'c=$' }, '2', 0)
  validate_edit1d('1 + 1', 0, { 'c==' }, '2', 0)
  validate_edit1d('1 + 1', 0, { 'v$', 'c=' }, '2', 0)
end

T['Evaluate']["respects 'selection=exclusive'"] = function()
  child.lua([[vim.keymap.set('o', 'ie', function() vim.cmd('normal! \22j3l') end)]])
  child.o.selection = 'exclusive'

  validate_edit1d('x = (1 + 1) = y', 5, { 'g=i)' }, 'x = (2) = y', 5)
  validate_edit({ 'local x = 1', 'x + 1' }, { 1, 0 }, { 'g=ip' }, { '2' }, { 1, 0 })
  validate_edit({ 'x=1-1=x', 'y=1+1=y' }, { 1, 2 }, { 'g=ie' }, { 'x=0  =x', 'y=2  =y' }, { 1, 2 })

  validate_edit1d('x = (1 + 1) = y', 5, { 'vi)', 'g=' }, 'x = (2) = y', 5)
  validate_edit({ 'local x = 1', 'x + 1' }, { 1, 0 }, { 'Vip', 'g=' }, { '2' }, { 1, 0 })
  validate_edit({ 'x=1-1=x', 'y=1+1=y' }, { 1, 2 }, { '<C-v>j3l', 'g=' }, { 'x=0  =x', 'y=2  =y' }, { 1, 2 })
end

T['Evaluate']["respects 'nomodifiable'"] = function()
  set_lines({ '1 + 1' })
  set_cursor(1, 0)
  child.bo.modifiable = false
  type_keys('g=$')
  eq(get_lines(), { '1 + 1' })
  eq(get_cursor(), { 1, 4 })
end

T['Evaluate']['does not trigger `TextYankPost` event'] = function()
  child.cmd('au TextYankPost * lua _G.been_here = true')
  -- Should also not block other events, like ModeChanged
  child.cmd('au ModeChanged * lua _G.n = (_G.n or 0) + 1')

  validate_edit1d('1 + 1', 0, { 'g=$' }, '2', 0)

  eq(child.lua_get('_G.been_here'), vim.NIL)
  eq(child.lua_get('_G.n') >= 8, true)
  eq(child.o.eventignore, '')
end

T['Evaluate']['respects `vim.{g,b}.minioperators_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minioperators_disable = true
    validate_edit1d('1 + 1', 0, { 'g=$' }, '1 + 1', 4)
  end,
})

T['Evaluate']['respects `vim.b.minioperators_config`'] = function()
  child.lua([[vim.b.minioperators_config = { evaluate = { func = function() return { 'a', 'b' } end } }]])
  validate_edit({ '1 + 1' }, { 1, 0 }, { 'g=ip' }, { 'a', 'b' }, { 1, 0 })
end

T['Exchange'] = new_set()

T['Exchange']['works charwise in Normal mode'] = function()
  local keys = { 'gxiw', 'w', 'gxiw' }
  validate_edit1d('a bb', 0, keys, 'bb a', 3)
  validate_edit1d('a bb ccc', 0, keys, 'bb a ccc', 3)
  validate_edit1d('a bb ccc', 3, keys, 'a ccc bb', 6)
  validate_edit1d('a bb ccc dddd', 3, keys, 'a ccc bb dddd', 6)

  -- With dot-repeat allowing multiple exchanges
  validate_edit1d('a bb', 0, { 'gxiw', 'w', '.' }, 'bb a', 3)
  validate_edit1d('a bb ccc dddd', 0, { 'gxiw', 'w', '.', 'w.w.' }, 'bb a dddd ccc', 10)

  -- Different order
  local keys_back = { 'gxiw', 'b', 'gxiw' }
  validate_edit1d('a bb', 2, keys_back, 'bb a', 0)
  validate_edit1d('a bb ccc', 2, keys_back, 'bb a ccc', 0)
  validate_edit1d('a bb ccc', 5, keys_back, 'a ccc bb', 2)
  validate_edit1d('a bb ccc dddd', 5, keys_back, 'a ccc bb dddd', 2)

  -- Over several lines
  set_lines({ 'aa bb', 'cc dd', 'ee ff', 'gg hh' })

  -- - Set marks
  set_cursor(2, 2)
  type_keys('ma')
  set_cursor(4, 2)
  type_keys('mb')

  -- - Validate
  set_cursor(1, 0)
  type_keys('gx`a', '2j', 'gx`b')
  eq(get_lines(), { 'ee ff', 'gg dd', 'aa bb', 'cc hh' })
  eq(get_cursor(), { 3, 0 })

  -- Single cell
  validate_edit1d('aa bb', 0, { 'gxl', 'w', 'gxl' }, 'ba ab', 3)
end

T['Exchange']['works linewise in Normal mode'] = function()
  local keys = { 'gx_', 'j', 'gx_' }
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, keys, { 'bb', 'aa' }, { 2, 0 })
  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, keys, { 'bb', 'aa', 'cc' }, { 2, 0 })
  validate_edit({ 'aa', 'bb', 'cc' }, { 2, 0 }, keys, { 'aa', 'cc', 'bb' }, { 3, 0 })
  validate_edit({ 'aa', 'bb', 'cc', 'dd' }, { 2, 0 }, keys, { 'aa', 'cc', 'bb', 'dd' }, { 3, 0 })

  -- With dot-repeat allowing multiple exchanges
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'gx_', 'j', '.' }, { 'bb', 'aa' }, { 2, 0 })
  validate_edit({ 'aa', 'bb', 'cc', 'dd' }, { 1, 0 }, { 'gx_', 'j', '.', 'j.j.' }, { 'bb', 'aa', 'dd', 'cc' }, { 4, 0 })

  -- Different order
  local keys_back = { 'gx_', 'k', 'gx_' }
  validate_edit({ 'aa', 'bb' }, { 2, 0 }, keys_back, { 'bb', 'aa' }, { 1, 0 })
  validate_edit({ 'aa', 'bb', 'cc' }, { 2, 0 }, keys_back, { 'bb', 'aa', 'cc' }, { 1, 0 })
  validate_edit({ 'aa', 'bb', 'cc' }, { 3, 0 }, keys_back, { 'aa', 'cc', 'bb' }, { 2, 0 })
  validate_edit({ 'aa', 'bb', 'cc', 'dd' }, { 3, 0 }, keys_back, { 'aa', 'cc', 'bb', 'dd' }, { 2, 0 })

  -- Empty line
  validate_edit({ 'aa', '' }, { 1, 0 }, { 'gx_', 'G', 'gx_' }, { '', 'aa' }, { 2, 0 })
  validate_edit({ 'aa', '', 'bb' }, { 1, 0 }, { 'gx_', 'G', 'gx_' }, { 'bb', '', 'aa' }, { 3, 0 })

  -- Over several lines
  validate_edit({ 'aa', 'bb', '', 'cc' }, { 1, 0 }, { 'gxip', 'G', 'gxip' }, { 'cc', '', 'aa', 'bb' }, { 3, 0 })

  -- Blank line(s)
  child.lua('MiniOperators.config.exchange.reindent_linewise = false')
  validate_edit({ 'aa', '  ' }, { 1, 0 }, { 'gx_', 'G', 'gx_' }, { '  ', 'aa' }, { 2, 0 })
  validate_edit({ ' ', '  ' }, { 1, 0 }, { 'gx_', 'G', 'gx_' }, { '  ', ' ' }, { 2, 0 })
end

T['Exchange']['works blockwise in Normal mode'] = function()
  child.lua([[vim.keymap.set('o', 'io', function() vim.cmd('normal! \22') end)]])
  child.lua([[vim.keymap.set('o', 'ie', function() vim.cmd('normal! \22j') end)]])
  child.lua([[vim.keymap.set('o', 'iE', function() vim.cmd('normal! \22jj') end)]])
  child.lua([[vim.keymap.set('o', 'il', function() vim.cmd('normal! \22jl') end)]])

  local keys = { 'gxie', 'w', 'gxil' }
  validate_edit({ 'a bb', 'c dd' }, { 1, 0 }, keys, { 'bb a', 'dd c' }, { 1, 3 })
  validate_edit({ 'a bb x', 'c dd y' }, { 1, 0 }, keys, { 'bb a x', 'dd c y' }, { 1, 3 })
  validate_edit({ 'a b xx', 'c d yy' }, { 1, 2 }, keys, { 'a xx b', 'c yy d' }, { 1, 5 })
  validate_edit({ 'a b xx u', 'c d yy v' }, { 1, 2 }, keys, { 'a xx b u', 'c yy d v' }, { 1, 5 })

  -- With dot-repeat allowing multiple exchanges
  validate_edit({ 'a bb', 'c dd' }, { 1, 0 }, { 'gxie', 'w', '.' }, { 'b ab', 'd cd' }, { 1, 2 })
  validate_edit({ 'a b x y', 'c d u v' }, { 1, 0 }, { 'gxie', 'w', '.', 'w.w.' }, { 'b a y x', 'd c v u' }, { 1, 6 })

  -- Different order
  local keys_back = { 'gxil', 'b', 'gxie' }
  validate_edit({ 'a bb', 'c dd' }, { 1, 2 }, keys_back, { 'bb a', 'dd c' }, { 1, 0 })
  validate_edit({ 'a bb x', 'c dd y' }, { 1, 2 }, keys_back, { 'bb a x', 'dd c y' }, { 1, 0 })
  validate_edit({ 'a b xx', 'c d yy' }, { 1, 4 }, keys_back, { 'a xx b', 'c yy d' }, { 1, 2 })
  validate_edit({ 'a b xx u', 'c d yy v' }, { 1, 4 }, keys_back, { 'a xx b u', 'c yy d v' }, { 1, 2 })

  -- Spanning empty/blank line
  validate_edit({ 'a b', '', 'c d' }, { 1, 0 }, { 'gxiE', 'w', 'gxiE' }, { 'b a', '  ', 'd c' }, { 1, 2 })
  validate_edit({ 'a b', '   ' }, { 1, 0 }, { 'gxie', 'w', 'gxie' }, { 'b a', '   ' }, { 1, 2 })

  -- Single cell
  validate_edit1d('aa bb', 0, { 'gxio', 'w', 'gxio' }, 'ba ab', 3)
end

T['Exchange']['works with mixed submodes in Normal mode'] = function()
  child.lua([[vim.keymap.set('o', 'ie', function() vim.cmd('normal! \22j') end)]])

  -- Charwise from - Linewise to
  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, { 'gxiw', 'j', 'gx_' }, { 'bb', 'aa', 'cc' }, { 2, 0 })
  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, { 'gx/b$<CR>', 'G', 'gx_' }, { 'ccb', 'aa', 'b' }, { 2, 0 })

  -- Charwise from - Blockwise to
  validate_edit({ 'aa', 'bc', 'de' }, { 1, 0 }, { 'gxiw', 'j', 'gxie' }, { 'b', 'd', 'aac', 'e' }, { 3, 0 })
  validate_edit({ 'aa', 'bc', 'de' }, { 1, 0 }, { 'gx/c<CR>', 'jl', 'gxie' }, { 'c', 'eaa', 'db' }, { 2, 1 })

  -- Linewise from - Charwise to
  validate_edit({ 'aa', 'bb bb' }, { 1, 0 }, { 'gx_', 'j', 'gxiw' }, { 'bb', 'aa bb' }, { 2, 0 })
  validate_edit({ 'aa', 'bb', 'cc cc' }, { 1, 0 }, { 'gxj', '2j', 'gxiw' }, { 'cc', 'aa', 'bb cc' }, { 2, 0 })

  -- Linewise from - Blockwise to
  validate_edit({ 'aa', 'bc', 'de' }, { 1, 0 }, { 'gx_', 'j', 'gxie' }, { 'b', 'd', 'aac', 'e' }, { 3, 0 })
  validate_edit({ 'aa', 'bb', 'cd', 'ef' }, { 1, 0 }, { 'gxj', '2j', 'gxie' }, { 'c', 'e', 'aad', 'bbf' }, { 3, 0 })

  -- Blockwise from - Charwise to
  validate_edit({ 'aa', 'bb bb' }, { 1, 0 }, { '<C-v>gx', 'j', 'gxiw' }, { 'bba', 'a bb' }, { 2, 0 })
  validate_edit({ 'aa', 'bb bb' }, { 1, 0 }, { '<C-v>jgx', 'jw', 'gxiw' }, { 'bba', 'b a', 'b' }, { 2, 2 })

  -- Blockwise from - Linewise to
  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, { '<C-v>gx', 'j', 'gx_' }, { 'bba', 'a', 'cc' }, { 2, 0 })
  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, { '<C-v>jgx', 'G', 'gx_' }, { 'cca', 'b', 'a', 'b' }, { 3, 0 })
end

T['Exchange']['works with `[count]` in Normal mode'] = function()
  validate_edit1d('aa bb cc dd ee ', 0, { '2gxaw', '2w', 'gx3aw' }, 'cc dd ee aa bb ', 9)

  -- With dot-repeat
  validate_edit1d('aa bb cc dd ', 0, { '2gxaw', '2w', '.', '0.2w.' }, 'aa bb cc dd ', 6)
end

T['Exchange']['works in Normal mode for line'] = function()
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'gxx', 'j', 'gxx' }, { 'bb', 'aa' }, { 2, 0 })

  -- With dot-repeat
  validate_edit({ 'aa', 'bb', 'cc', 'dd' }, { 1, 0 }, { 'gxx', 'j', '.', 'j.j.' }, { 'bb', 'aa', 'dd', 'cc' }, { 4, 0 })
end

T['Exchange']['works with `[count]` in Normal mode for line'] = function()
  validate_edit(
    { 'aa', 'bb', 'cc', 'dd', 'ee' },
    { 1, 0 },
    { '2gxx', '2j', '3gxx' },
    { 'cc', 'dd', 'ee', 'aa', 'bb' },
    { 4, 0 }
  )

  -- With dot-repeat
  validate_edit(
    { 'aa', 'bb', 'cc', 'dd' },
    { 1, 0 },
    { '2gxx', '2j', '.', 'gg.2j.' },
    { 'aa', 'bb', 'cc', 'dd' },
    { 3, 0 }
  )
end

T['Exchange']['works with empty textobject/motion'] = function()
  child.api.nvim_set_keymap('o', 'w', '<Cmd><CR>', {})

  -- On step one
  set_lines({ 'xxx', 'yyy' })
  set_cursor(1, 1)
  type_keys('gx', 'w')
  eq(child.fn.maparg('<C-c>'), '')
  -- - Should ignore previous time and treat this as step one
  type_keys('j', 'gx', '$')
  eq(get_lines(), { 'xxx', 'yyy' })
  type_keys('k', 'gx', '$')
  eq(get_lines(), { 'xyy', 'yxx' })

  -- On step two
  set_lines({ 'xxx', 'yyy' })
  set_cursor(1, 1)
  type_keys('gx', 'iw')
  -- - Should ignore this one while still allowing proper step two
  type_keys('jl', 'gx', 'w')
  eq(get_lines(), { 'xxx', 'yyy' })
  type_keys('gx', '$')
  eq(get_lines(), { 'yy', 'yxxx' })
end

T['Exchange']['works in Visual mode'] = function()
  -- Charwise from - Charwise to
  validate_edit1d('aa bb', 0, { 'viwgx', 'w', 'viwgx' }, 'bb aa', 3)
  validate_edit1d('aa bb', 3, { 'viwgx', '0', 'viwgx' }, 'bb aa', 0)

  -- Charwise from - Linewise to
  validate_edit({ 'aa x', 'bb' }, { 1, 0 }, { 'viwgx', 'j', 'Vgx' }, { 'bb x', 'aa' }, { 2, 0 })
  validate_edit({ 'aa x', 'bb' }, { 2, 0 }, { 'Vgx', 'k0', 'viwgx' }, { 'bb x', 'aa' }, { 1, 0 })

  -- Charwise from - Blockwise to
  validate_edit({ 'aa x', 'bb', 'cc' }, { 1, 0 }, { 'viwgx', 'j0', '<C-v>jgx' }, { 'b', 'c x', 'aab', 'c' }, { 3, 0 })
  validate_edit({ 'aa x', 'bb', 'cc' }, { 2, 0 }, { '<C-v>jgx', 'gg0', 'viwgx' }, { 'b', 'c x', 'aab', 'c' }, { 1, 0 })

  -- Linewise from - Charwise to
  validate_edit({ 'aa', 'bb x' }, { 1, 0 }, { 'Vgx', 'j0', 'viwgx' }, { 'bb', 'aa x' }, { 2, 0 })
  validate_edit({ 'aa', 'bb x' }, { 2, 0 }, { 'viwgx', 'k', 'Vgx' }, { 'bb', 'aa x' }, { 1, 0 })

  -- Linewise from - Linewise to
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'Vgx', 'j', 'Vgx' }, { 'bb', 'aa' }, { 2, 0 })
  validate_edit({ 'aa', 'bb' }, { 2, 0 }, { 'Vgx', 'k', 'Vgx' }, { 'bb', 'aa' }, { 1, 0 })

  -- Linewise from - Blockwise to
  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, { 'Vgx', 'j0', '<C-v>jgx' }, { 'b', 'c', 'aab', 'c' }, { 3, 0 })
  validate_edit({ 'aa', 'bb', 'cc' }, { 2, 0 }, { '<C-v>jgx', 'gg0', 'Vgx' }, { 'b', 'c', 'aab', 'c' }, { 1, 0 })

  -- Blockwise from - Charwise to
  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, { '<C-v>jgx', 'G', 'viwgx' }, { 'cca', 'b', 'a', 'b' }, { 3, 0 })
  validate_edit({ 'aa', 'bb', 'cc' }, { 3, 0 }, { 'viwgx', 'gg0', '<C-v>jgx' }, { 'cca', 'b', 'a', 'b' }, { 1, 0 })

  -- Blockwise from - Linewise to
  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, { '<C-v>jgx', 'G', 'Vgx' }, { 'cca', 'b', 'a', 'b' }, { 3, 0 })
  validate_edit({ 'aa', 'bb', 'cc' }, { 3, 0 }, { 'Vgx', 'gg0', '<C-v>jgx' }, { 'cca', 'b', 'a', 'b' }, { 1, 0 })

  -- Blockwise from - Blockwise to
  validate_edit({ 'ab', 'cd' }, { 1, 0 }, { '<C-v>jgx', 'l', '<C-v>jgx' }, { 'ba', 'dc' }, { 1, 1 })
  validate_edit({ 'ab', 'cd' }, { 1, 1 }, { '<C-v>jgx', 'h', '<C-v>jgx' }, { 'ba', 'dc' }, { 1, 0 })
end

T['Exchange']['works with different `virtualedit`'] = function()
  local validate = function()
    -- Charwise
    validate_edit1d('aa bb cc', 3, { 'gx', 'iw', 'b', 'gx', 'iw' }, 'bb aa cc', 0)
    validate_edit1d('aa bb cc', 0, { 'gx', 'iw', 'w', 'gx', 'iw' }, 'bb aa cc', 3)
    validate_edit1d('aa bb cc', 0, { 'gx', 'iw', '2w', 'gx', 'iw' }, 'cc bb aa', 6)

    validate_edit1d('aa bb cc', 3, { 'viw', 'gx', '2b', 'viw', 'gx' }, 'bb aa cc', 0)
    validate_edit1d('aa bb cc', 0, { 'viw', 'gx', 'w', 'viw', 'gx' }, 'bb aa cc', 3)
    validate_edit1d('aa bb cc', 0, { 'viw', 'gx', '2w', 'viw', 'gx' }, 'cc bb aa', 6)

    -- Linewise
    validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, { 'gxx', 'j', 'gxx' }, { 'bb', 'aa', 'cc' }, { 2, 0 })
    validate_edit({ 'aa', 'bb', 'cc' }, { 2, 0 }, { 'gxx', 'j', 'gxx' }, { 'aa', 'cc', 'bb' }, { 3, 0 })
    validate_edit({ 'aa', 'bb', 'cc' }, { 3, 0 }, { 'gxx', 'k', 'gxx' }, { 'aa', 'cc', 'bb' }, { 2, 0 })

    validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, { 'V', 'gx', 'j', 'V', 'gx' }, { 'bb', 'aa', 'cc' }, { 2, 0 })
    validate_edit({ 'aa', 'bb', 'cc' }, { 2, 0 }, { 'V', 'gx', 'j', 'V', 'gx' }, { 'aa', 'cc', 'bb' }, { 3, 0 })
    validate_edit({ 'aa', 'bb', 'cc' }, { 3, 0 }, { 'V', 'gx', 'k', 'V', 'gx' }, { 'aa', 'cc', 'bb' }, { 2, 0 })

    -- Blockwise
    child.lua([[vim.keymap.set('o', 'ie', function() vim.cmd('normal! \22j') end)]])
    validate_edit({ 'abc', 'def' }, { 1, 0 }, { 'gx', 'ie', 'l', 'gx', 'ie' }, { 'bac', 'edf' }, { 1, 1 })
    validate_edit({ 'abc', 'def' }, { 1, 1 }, { 'gx', 'ie', 'l', 'gx', 'ie' }, { 'acb', 'dfe' }, { 1, 2 })
    validate_edit({ 'abc', 'def' }, { 1, 2 }, { 'gx', 'ie', 'h', 'gx', 'ie' }, { 'acb', 'dfe' }, { 1, 1 })

    validate_edit({ 'abc', 'def' }, { 1, 0 }, { '<C-v>jgx', 'l', '<C-v>jgx' }, { 'bac', 'edf' }, { 1, 1 })
    validate_edit({ 'abc', 'def' }, { 1, 1 }, { '<C-v>jgx', 'l', '<C-v>jgx' }, { 'acb', 'dfe' }, { 1, 2 })
    validate_edit({ 'abc', 'def' }, { 1, 2 }, { '<C-v>jgx', 'h', '<C-v>jgx' }, { 'acb', 'dfe' }, { 1, 1 })
  end

  child.o.virtualedit = 'all'
  validate()
  child.o.virtualedit = 'onemore'
  validate()
  child.o.virtualedit = 'block'
  validate()
end

T['Exchange']['works when regions are made in different modes'] = function()
  child.lua([[vim.keymap.set('o', 'ie', function() vim.cmd('normal! \22j') end)]])

  -- Normal from - Visual to
  validate_edit1d('aa bb', 0, { 'gxiw', 'w', 'viwgx' }, 'bb aa', 3)
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'gx_', 'j', 'Vgx' }, { 'bb', 'aa' }, { 2, 0 })
  validate_edit({ 'ab', 'cd' }, { 1, 0 }, { 'gxie', 'l', '<C-v>jgx' }, { 'ba', 'dc' }, { 1, 1 })

  -- Normal to - Visual from
  validate_edit1d('aa bb', 0, { 'viwgx', 'w', 'gxiw' }, 'bb aa', 3)
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'Vgx', 'j', 'gx_' }, { 'bb', 'aa' }, { 2, 0 })
  validate_edit({ 'ab', 'cd' }, { 1, 0 }, { '<C-v>jgx', 'l', 'gxie' }, { 'ba', 'dc' }, { 1, 1 })
end

T['Exchange']['correctly reindents linewise'] = function()
  -- Should exchange indents
  validate_edit({ '\taa', 'bb' }, { 1, 0 }, { 'gx_', 'j', 'gx_' }, { '\tbb', 'aa' }, { 2, 0 })
  validate_edit({ '\taa', 'bb' }, { 2, 0 }, { 'gx_', 'k', 'gx_' }, { '\tbb', 'aa' }, { 1, 0 })
  validate_edit({ '\taa', '\t\tbb' }, { 1, 0 }, { 'gx_', 'j', 'gx_' }, { '\tbb', '\t\taa' }, { 2, 0 })
  validate_edit({ '\taa', '\t\tbb' }, { 2, 0 }, { 'gx_', 'k', 'gx_' }, { '\tbb', '\t\taa' }, { 1, 0 })

  validate_edit({ '  aa', 'bb' }, { 1, 0 }, { 'gx_', 'j', 'gx_' }, { '  bb', 'aa' }, { 2, 0 })
  validate_edit({ '  aa', 'bb' }, { 2, 0 }, { 'gx_', 'k', 'gx_' }, { '  bb', 'aa' }, { 1, 0 })
  validate_edit({ '  aa', '    bb' }, { 1, 0 }, { 'gx_', 'j', 'gx_' }, { '  bb', '    aa' }, { 2, 0 })
  validate_edit({ '  aa', '    bb' }, { 2, 0 }, { 'gx_', 'k', 'gx_' }, { '  bb', '    aa' }, { 1, 0 })

  -- Should replace current region indent with new one
  validate_edit({ '\taa', '\t\tbb', 'cc' }, { 1, 0 }, { 'gxj', 'G', 'gx_' }, { '\tcc', 'aa', '\tbb' }, { 2, 0 })

  -- Should preserve tabs vs spaces
  validate_edit({ '\taa', '  bb' }, { 1, 0 }, { 'gx_', 'j', 'gx_' }, { '\tbb', '  aa' }, { 2, 0 })
  validate_edit({ '\taa', '  bb' }, { 2, 0 }, { 'gx_', 'k', 'gx_' }, { '\tbb', '  aa' }, { 1, 0 })

  -- Should correctly work in presence of blank lines (compute indent and not
  -- reindent them)
  validate_edit(
    { '\t\taa', '', '\t', '\tcc' },
    { 1, 0 },
    { 'gx2j', 'G', 'gx_' },
    { '\t\tcc', '\taa', '', '\t' },
    { 2, 0 }
  )

  -- Should correctly work exchanging **only** blank lines region
  validate_edit({ 'aa', '\t\t', '\t' }, { 1, 0 }, { 'gx_', 'j', 'gxj' }, { '\t\t', '\t', '\taa' }, { 3, 0 })
end

T['Exchange']['respects `config.exchange.reindent_linewise`'] = function()
  child.lua('MiniOperators.config.exchange.reindent_linewise = false')
  validate_edit({ '\taa', 'bb' }, { 1, 0 }, { 'gx_', 'j', 'gx_' }, { 'bb', '\taa' }, { 2, 0 })
end

T['Exchange']['highlights first step'] = new_set(
  { parametrize = { { 'charwise' }, { 'linewise' }, { 'blockwise' } } },
  {
    test = function(mode)
      child.set_size(5, 12)
      local keys = ({ charwise = 'gxiw', linewise = 'gx_', blockwise = '<C-v>jlgx' })[mode]

      set_lines({ 'aa aa', 'bb' })
      set_cursor(1, 0)
      type_keys(keys)
      child.expect_screenshot()
    end,
  }
)

T['Exchange']["correctly highlights first step with 'selection=exclusive'"] = function()
  child.set_size(5, 12)
  child.o.selection = 'exclusive'

  set_lines({ 'aaa bbb' })
  set_cursor(1, 0)
  type_keys('v2l', 'gx')
  child.expect_screenshot()
end

T['Exchange']['can be canceled'] = function()
  child.set_size(5, 12)
  set_lines({ 'aa bb' })
  set_cursor(1, 0)

  type_keys('gxiw')
  child.expect_screenshot()

  -- Should reset highlighting and "exchange state"
  type_keys('<C-c>')
  child.expect_screenshot()

  type_keys('gxiw', 'w', 'gxiw')
  eq(get_lines(), { 'bb aa' })

  -- Should cleanup temporary mapping
  eq(child.fn.maparg('<C-c>'), '')
end

T['Exchange']['works for intersecting regions'] = function()
  -- Charwise
  validate_edit1d('abcd', 0, { 'gx3l', 'l', 'gx3l' }, 'bcdabc', 3)
  validate_edit1d('abcd', 0, { 'gx4l', 'l', 'gx2l' }, 'abcd', 2)
  validate_edit1d('abcd', 1, { 'gx2l', '0', 'gx4l' }, 'bc', 0)

  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, { 'vjgx', 'vjgx' }, { 'bb', 'caa', 'bc' }, { 2, 1 })

  -- Linewise
  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, { 'Vjgx', 'Vjgx' }, { 'bb', 'cc', 'aa', 'bb' }, { 3, 0 })
  validate_edit({ 'aa', 'bb', 'cc', '' }, { 1, 0 }, { 'Vipgx', 'k', 'Vgx' }, { 'aa', 'bb', 'cc', '' }, { 2, 0 })
  validate_edit({ 'aa', 'bb', 'cc', '' }, { 2, 0 }, { 'Vgx', 'Vipgx' }, { 'bb', '' }, { 1, 0 })

  -- Blockwise
  validate_edit({ 'abc', 'def' }, { 1, 0 }, { '<C-v>jlgx', 'l', '<C-v>jlgx' }, { 'bcab', 'efde' }, { 1, 2 })
  validate_edit({ 'abc', 'def' }, { 1, 0 }, { '<C-v>jllgx', 'l', '<C-v>jgx' }, { 'abc', 'def' }, { 1, 1 })
  validate_edit({ 'abc', 'def' }, { 1, 1 }, { '<C-v>jgx', 'h', '<C-v>jllgx' }, { 'b', 'e' }, { 1, 0 })
end

T['Exchange']['works for regions in different buffers'] = function()
  local buf_1 = child.api.nvim_create_buf(true, false)
  local buf_2 = child.api.nvim_create_buf(true, false)

  child.api.nvim_buf_set_lines(buf_1, 0, -1, true, { 'aa', 'aa' })
  child.api.nvim_buf_set_lines(buf_2, 0, -1, true, { 'bb', 'bb' })

  child.api.nvim_set_current_buf(buf_1)
  type_keys('gx_')
  child.api.nvim_set_current_buf(buf_2)
  type_keys('gx_')

  eq(child.api.nvim_buf_get_lines(buf_1, 0, -1, true), { 'bb', 'aa' })
  eq(child.api.nvim_buf_get_lines(buf_2, 0, -1, true), { 'aa', 'bb' })
end

T['Exchange']['accounts for outdated first step buffer'] = function()
  local buf_1 = child.api.nvim_create_buf(true, false)
  local buf_2 = child.api.nvim_create_buf(true, false)

  child.api.nvim_buf_set_lines(buf_1, 0, -1, true, { 'aa', 'aa' })
  child.api.nvim_buf_set_lines(buf_2, 0, -1, true, { 'bb', 'cc' })

  child.api.nvim_set_current_buf(buf_1)
  type_keys('gx_')
  child.api.nvim_set_current_buf(buf_2)

  child.api.nvim_buf_delete(buf_1, { force = true })
  -- Should not error and restart exchange process
  type_keys('gx_')
  eq(get_lines(), { 'bb', 'cc' })

  type_keys('j', 'gx_')
  eq(get_lines(), { 'cc', 'bb' })
end

T['Exchange']['works for same region'] = function()
  -- Charwise
  validate_edit1d('aa bb cc', 4, { 'gxiw', 'gxiw' }, 'aa bb cc', 3)

  -- Linewise
  validate_edit1d('aa bb cc', 4, { 'gx_', 'gx_' }, 'aa bb cc', 0)

  -- Blockwise
  validate_edit({ 'ab', 'cd' }, { 1, 0 }, { '<C-v>jgx', '<C-v>jgx' }, { 'ab', 'cd' }, { 2, 0 })
end

T['Exchange']['works with multibyte characters'] = function()
  child.set_size(5, 12)

  -- Charwise 2 bytes
  set_lines({ '  ыыы ффф' })
  set_cursor(1, 2)
  type_keys('gx2l')
  -- - Should properly highlight range
  child.expect_screenshot()

  type_keys('w', 'gx2l')
  eq(get_lines(), { '  ффы ыыф' })
  eq(get_cursor(), { 1, 9 })

  -- Charwise 3 bytes
  set_lines({ '  ╔═╗ ╚═╝' })
  set_cursor(1, 2)
  type_keys('gx2l')
  child.expect_screenshot()

  type_keys('w', 'gx2l')
  eq(get_lines(), { '  ╚═╗ ╔═╝' })
  eq(get_cursor(), { 1, 12 })

  -- Charwise 4 bytes
  set_lines({ '  🬕🬂🬨  🬲🬭🬷' })
  set_cursor(1, 2)
  type_keys('gx2l')
  child.expect_screenshot()

  type_keys('w', 'gx2l')
  eq(get_lines(), { '  🬲🬭🬨  🬕🬂🬷' })
  eq(get_cursor(), { 1, 16 })

  -- Linewise
  set_lines({ '  ыыы ффф', '  эээ ююю' })
  set_cursor(1, 2)
  type_keys('gx_')
  child.expect_screenshot()

  type_keys('j', 'gx_')
  eq(get_lines(), { '  эээ ююю', '  ыыы ффф' })
  eq(get_cursor(), { 2, 0 })

  -- Blockwise
  set_lines({ '  ыыы ффф', '  эээ ююю' })
  set_cursor(1, 2)
  type_keys('<C-v>jl', 'gx')
  child.expect_screenshot()

  type_keys('w', '<C-v>jl', 'gx')
  eq(get_lines(), { '  ффы ыыф', '  ююэ ээю' })
  eq(get_cursor(), { 1, 9 })
end

T['Exchange']['does not have side effects'] = function()
  set_lines({ 'rst', 'aa', 'bb' })

  -- Marks `x`, `y` and registers `a`, `b`, '"'
  set_cursor(1, 0)
  type_keys('mx')
  type_keys('v"ay')

  set_cursor(1, 1)
  type_keys('my')
  type_keys('v"by')

  set_cursor(1, 2)
  type_keys('vy')

  -- Should properly manage stop mapping
  child.api.nvim_set_keymap('n', '<C-c>', ':echo 1<CR>', {})

  -- Do exchange
  set_cursor(2, 0)
  type_keys('gx_', 'j', 'gx_')

  -- Validate
  eq(get_lines(), { 'rst', 'bb', 'aa' })
  eq(child.api.nvim_buf_get_mark(0, 'x'), { 1, 0 })
  eq(child.api.nvim_buf_get_mark(0, 'y'), { 1, 1 })
  eq(child.fn.getreg('a'), 'r')
  eq(child.fn.getreg('b'), 's')
  eq(child.fn.getreg('"'), 't')
  eq(child.fn.maparg('<C-c>'), ':echo 1<CR>')
end

T['Exchange']['preserves visual marks'] = function()
  set_lines({ 'aa', 'bb', 'select', 'cc' })

  -- Create marks
  set_cursor(3, 0)
  type_keys('viw', '<Esc>')

  -- Exchange
  set_cursor(1, 0)
  type_keys('gxj', 'G', 'gx_')
  eq(get_lines(), { 'cc', 'select', 'aa', 'bb' })
  eq(child.api.nvim_buf_get_mark(0, '<'), { 2, 0 })
  eq(child.api.nvim_buf_get_mark(0, '>'), { 2, 5 })
end

T['Exchange']['respects `config.exchange.prefix`'] = function()
  child.api.nvim_del_keymap('n', 'gx')
  child.api.nvim_del_keymap('n', 'gxx')
  child.api.nvim_del_keymap('x', 'gx')

  load_module({ exchange = { prefix = 'cx' } })

  validate_edit1d('aa bb', 0, { 'cxiw', 'w', 'cxiw' }, 'bb aa', 3)
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'cxx', 'j', 'cxx' }, { 'bb', 'aa' }, { 2, 0 })
  validate_edit1d('aa bb', 0, { 'viwcx', 'w', 'viwcx' }, 'bb aa', 3)
end

T['Exchange']['works with `make_mappings()`'] = function()
  child.api.nvim_del_keymap('n', 'gx')
  child.api.nvim_del_keymap('n', 'gxx')
  child.api.nvim_del_keymap('x', 'gx')

  load_module({ exchange = { prefix = '' } })
  make_mappings('exchange', { textobject = 'cx', line = 'cxx', selection = 'cx' })

  validate_edit1d('aa bb', 0, { 'cxiw', 'w', 'cxiw' }, 'bb aa', 3)
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'cxx', 'j', 'cxx' }, { 'bb', 'aa' }, { 2, 0 })
  validate_edit1d('aa bb', 0, { 'viwcx', 'w', 'viwcx' }, 'bb aa', 3)
end

T['Exchange']['works on visual selection with leading newline'] = function()
  set_lines({ 'a(', '  b', ')', 'c{', '  d,', '}' })

  set_cursor(2, 2)
  type_keys('vk', 'gx')
  set_cursor(5, 2)
  type_keys('vk', 'gx')
  eq(get_lines(), { 'a(', '  d', ')', 'c{', '  b,', '}' })
  eq(get_cursor(), { 4, 1 })
end

T['Exchange']['respects `selection=exclusive`'] = function()
  child.lua([[vim.keymap.set('o', 'ie', function() vim.cmd('normal! \22j') end)]])
  child.o.selection = 'exclusive'

  validate_edit1d('aaa bbb x', 0, { 'gxiw', 'w', 'gxiw' }, 'bbb aaa x', 4)
  validate_edit({ 'aa', 'bb', 'x' }, { 1, 0 }, { 'gx_', 'j', 'gx_' }, { 'bb', 'aa', 'x' }, { 2, 0 })
  validate_edit({ 'a b c', 'a b c' }, { 1, 0 }, { 'gxie', 'w', 'gxie' }, { 'b a c', 'b a c' }, { 1, 2 })

  validate_edit1d('aaa bbb x', 0, { 'v2l', 'gx', 'w', 'v2l', 'gx' }, 'bba aab x', 4)
  validate_edit({ 'aa', 'bb', 'x' }, { 1, 0 }, { 'V', 'gx', 'j', 'V', 'gx' }, { 'bb', 'aa', 'x' }, { 2, 0 })
  validate_edit(
    { 'aaa bbb', 'ccc ddd' },
    { 1, 0 },
    { '<C-v>jll', 'gx', 'w', '<C-v>jll', 'gx' },
    { 'bba aab', 'ddc ccd' },
    { 1, 4 }
  )
end

T['Exchange']["respects 'nomodifiable'"] = function()
  set_lines({ 'aa bb' })
  set_cursor(1, 0)
  child.bo.modifiable = false
  type_keys('gxe', 'w', 'gx$')
  eq(get_lines(), { 'aa bb' })
  eq(get_cursor(), { 1, 4 })
end

T['Exchange']['does not trigger `TextYankPost` event'] = function()
  child.cmd('au TextYankPost * lua _G.been_here = true')
  -- Should also not block other events, like ModeChanged
  child.cmd('au ModeChanged * lua _G.n = (_G.n or 0) + 1')

  validate_edit1d('aa bb', 0, { 'gxiw', 'w', 'gxiw' }, 'bb aa', 3)

  eq(child.lua_get('_G.been_here'), vim.NIL)
  eq(child.lua_get('_G.n') >= 16, true)
  eq(child.o.eventignore, '')
end

T['Exchange']['respects `vim.{g,b}.minioperators_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minioperators_disable = true
    validate_edit1d('aa bb', 0, { 'gxiw' }, 'waa bb', 1)
  end,
})

T['Exchange']['respects `vim.b.minioperators_config`'] = function()
  child.b.minioperators_config = { exchange = { reindent_linewise = false } }

  validate_edit(
    { '\taa', '\tbb', 'cc', 'dd' },
    { 2, 0 },
    { 'gx_', 'G', 'gx_' },
    { '\taa', 'dd', 'cc', '\tbb' },
    { 4, 0 }
  )
end

T['Multiply'] = new_set()

T['Multiply']['works charwise in Normal mode'] = function()
  validate_edit1d('aa bb', 0, { 'gmiw' }, 'aaaa bb', 2)
  validate_edit1d('aa bb', 0, { 'gmaw' }, 'aa aa bb', 3)

  -- With dot-repeat
  validate_edit1d('aa bb', 0, { 'gmiw', 'w', '.' }, 'aaaa bbbb', 7)

  -- With [count] and dot-repeat
  validate_edit1d('aa bb', 0, { '2gmiw', 'w', '.' }, 'aaaaaa bbbbbb', 9)

  -- Over several lines
  validate_edit({ 'aa', 'bb_cc' }, { 1, 0 }, { 'gm/c<CR>' }, { 'aa', 'bb_aa', 'bb_cc' }, { 2, 3 })
end

T['Multiply']['works linewise in Normal mode'] = function()
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'gm_' }, { 'aa', 'aa', 'bb' }, { 2, 0 })
  validate_edit({ 'aa', ' ', 'bb' }, { 1, 0 }, { 'gmap' }, { 'aa', ' ', 'aa', ' ', 'bb' }, { 3, 0 })

  -- With dot-repeat
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'gm_', 'j', '.' }, { 'aa', 'aa', 'bb', 'bb' }, { 4, 0 })

  -- Should put cursor on first non-blank of paste
  validate_edit({ '  aa', 'bb' }, { 1, 0 }, { 'gm_' }, { '  aa', '  aa', 'bb' }, { 2, 2 })
  validate_edit({ '\taa', 'bb' }, { 1, 0 }, { 'gm_' }, { '\taa', '\taa', 'bb' }, { 2, 1 })

  -- With [count] and dot-repeat. Should put cursor on first new non-blank.
  validate_edit(
    { '\taa', '\tbb' },
    { 1, 0 },
    { '2gm_', '2j', '.' },
    { '\taa', '\taa', '\taa', '\tbb', '\tbb', '\tbb' },
    { 5, 1 }
  )
end

T['Multiply']['works blockwise in Normal mode'] = function()
  -- Validate for all four ways to create block
  child.lua([[vim.keymap.set('o', 'ia', function() vim.cmd('normal! \22jl') end)]])
  child.lua([[vim.keymap.set('o', 'ib', function() vim.cmd('normal! \22jh') end)]])
  child.lua([[vim.keymap.set('o', 'ic', function() vim.cmd('normal! \22kl') end)]])
  child.lua([[vim.keymap.set('o', 'id', function() vim.cmd('normal! \22kh') end)]])

  local lines = { 'ab rs', 'cd uv' }

  local ref_lines, ref_cursor = { 'abab rs', 'cdcd uv' }, { 1, 2 }
  validate_edit(lines, { 1, 0 }, { 'gmia' }, ref_lines, ref_cursor)
  validate_edit(lines, { 1, 1 }, { 'gmib' }, ref_lines, ref_cursor)
  validate_edit(lines, { 2, 0 }, { 'gmic' }, ref_lines, ref_cursor)
  validate_edit(lines, { 2, 1 }, { 'gmid' }, ref_lines, ref_cursor)

  -- With dot-repeat
  local ref_lines_dot, ref_cursor_dot = { 'abab rsrs', 'cdcd uvuv' }, { 1, 7 }
  validate_edit(lines, { 1, 0 }, { 'gmia', 'w', '.' }, ref_lines_dot, ref_cursor_dot)
  validate_edit(lines, { 1, 1 }, { 'gmib', 'we', '.' }, ref_lines_dot, ref_cursor_dot)
  validate_edit(lines, { 2, 0 }, { 'gmic', 'wj', '.' }, ref_lines_dot, ref_cursor_dot)
  validate_edit(lines, { 2, 1 }, { 'gmid', 'wej', '.' }, ref_lines_dot, ref_cursor_dot)

  -- With [count] and dot-repeat
  local ref_lines_count, ref_cursor_count = { 'ababab rsrsrs', 'cdcdcd uvuvuv' }, { 1, 9 }
  validate_edit(lines, { 1, 0 }, { '2gmia', 'w', '.' }, ref_lines_count, ref_cursor_count)
  validate_edit(lines, { 1, 1 }, { '2gmib', 'we', '.' }, ref_lines_count, ref_cursor_count)
  validate_edit(lines, { 2, 0 }, { '2gmic', 'wj', '.' }, ref_lines_count, ref_cursor_count)
  validate_edit(lines, { 2, 1 }, { '2gmid', 'wej', '.' }, ref_lines_count, ref_cursor_count)
end

T['Multiply']['works with two types of `[count]` in Normal mode'] = function()
  child.lua([[vim.keymap.set('o', 'ia', function() vim.cmd('normal! \22j' .. vim.v.count1 .. 'l') end)]])

  -- Second `[count]` for textobject with dot-repeat
  validate_edit1d('aa bb cc dd x', 0, { 'gm2aw', '2w', '.' }, 'aa bb aa bb cc dd cc dd x', 18)
  validate_edit(
    { 'aa', 'bb', 'cc', 'dd', 'x' },
    { 1, 0 },
    { 'gm2_', '2j', '.' },
    { 'aa', 'bb', 'aa', 'bb', 'cc', 'dd', 'cc', 'dd', 'x' },
    { 7, 0 }
  )
  validate_edit(
    { 'abc rst', 'def uvw' },
    { 1, 0 },
    { 'gm2ia', 'w', '.' },
    { 'abcabc rstrst', 'defdef uvwuvw' },
    { 1, 10 }
  )

  -- Both `[count]`s with dot-repeat
  validate_edit1d('aa bb cc dd x', 0, { '2gm2aw', '4w', '.' }, 'aa bb aa bb aa bb cc dd cc dd cc dd x', 24)
  validate_edit(
    { 'aa', 'bb', 'cc', 'dd', 'x' },
    { 1, 0 },
    { '2gm2_', '4j', '.' },
    { 'aa', 'bb', 'aa', 'bb', 'aa', 'bb', 'cc', 'dd', 'cc', 'dd', 'cc', 'dd', 'x' },
    { 9, 0 }
  )
  validate_edit(
    { 'abc rst', 'def uvw' },
    { 1, 0 },
    { '2gm2ia', 'w', '.' },
    { 'abcabcabc rstrstrst', 'defdefdef uvwuvwuvw' },
    { 1, 13 }
  )
end

T['Multiply']['works in Normal mode for line'] = function()
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'gmm' }, { 'aa', 'aa', 'bb' }, { 2, 0 })
  validate_edit({ '  aa', 'bb' }, { 1, 0 }, { 'gmm' }, { '  aa', '  aa', 'bb' }, { 2, 2 })

  -- With dot-repeat
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'gmm', 'j', '.' }, { 'aa', 'aa', 'bb', 'bb' }, { 4, 0 })
end

T['Multiply']['works with `[count]` in Normal mode for line'] = function()
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { '2gmm' }, { 'aa', 'aa', 'aa', 'bb' }, { 2, 0 })

  -- With dot-repeat
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { '2gmm', '2j', '.' }, { 'aa', 'aa', 'aa', 'bb', 'bb', 'bb' }, { 5, 0 })
end

T['Multiply']['works with `cmdheight=0`'] = function()
  child.set_size(7, 20)
  child.o.cmdheight = 0
  child.o.statusline = 'My statusline'
  -- Force quick test for regular `gm` operator
  child.api.nvim_del_keymap('n', 'gmm')

  set_lines({ 'aa bb' })
  type_keys('gm')
  child.expect_screenshot({ redraw = false })
  type_keys('iw')
  child.expect_screenshot({ redraw = false })
end

T['Multiply']['works with empty textobject/motion'] = function()
  child.api.nvim_set_keymap('o', 'w', '<Cmd><CR>', {})
  set_lines({ 'xxx' })
  set_cursor(1, 1)
  type_keys('gm', 'w')
  eq(get_lines(), { 'xxx' })
end

T['Multiply']['works in Visual mode'] = function()
  validate_edit1d('aa bb', 0, { 'viw', 'gm' }, 'aaaa bb', 2)

  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'V', 'gm' }, { 'aa', 'aa', 'bb' }, { 2, 0 })
  validate_edit({ '  aa', 'bb' }, { 1, 0 }, { 'V', 'gm' }, { '  aa', '  aa', 'bb' }, { 2, 2 })

  local lines = { 'ab rs', 'cd uv' }
  local ref_lines, ref_cursor = { 'abab rs', 'cdcd uv' }, { 1, 2 }
  validate_edit(lines, { 1, 0 }, { '<C-v>jl', 'gm' }, ref_lines, ref_cursor)
  validate_edit(lines, { 1, 1 }, { '<C-v>jh', 'gm' }, ref_lines, ref_cursor)
  validate_edit(lines, { 2, 0 }, { '<C-v>kl', 'gm' }, ref_lines, ref_cursor)
  validate_edit(lines, { 2, 1 }, { '<C-v>kh', 'gm' }, ref_lines, ref_cursor)
end

T['Multiply']['works with `[count]` in Visual mode'] = function()
  validate_edit1d('aa bb', 0, { 'viw', '2gm' }, 'aaaaaa bb', 2)

  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'V', '2gm' }, { 'aa', 'aa', 'aa', 'bb' }, { 2, 0 })
  validate_edit({ '  aa', 'bb' }, { 1, 0 }, { 'V', '2gm' }, { '  aa', '  aa', '  aa', 'bb' }, { 2, 2 })

  local lines = { 'ab rs', 'cd uv' }
  local ref_lines, ref_cursor = { 'ababab rs', 'cdcdcd uv' }, { 1, 2 }
  validate_edit(lines, { 1, 0 }, { '<C-v>jl', '2gm' }, ref_lines, ref_cursor)
  validate_edit(lines, { 1, 1 }, { '<C-v>jh', '2gm' }, ref_lines, ref_cursor)
  validate_edit(lines, { 2, 0 }, { '<C-v>kl', '2gm' }, ref_lines, ref_cursor)
  validate_edit(lines, { 2, 1 }, { '<C-v>kh', '2gm' }, ref_lines, ref_cursor)
end

T['Multiply']['works with different `virtualedit`'] = function()
  local validate = function()
    -- Charwise
    validate_edit1d('aa bb cc', 0, { 'gm', 'iw' }, 'aaaa bb cc', 2)
    validate_edit1d('aa bb cc', 3, { 'gm', 'iw' }, 'aa bbbb cc', 5)
    validate_edit1d('aa bb cc', 6, { 'gm', 'iw' }, 'aa bb cccc', 8)

    validate_edit1d('aa bb cc', 0, { 'viw', 'gm' }, 'aaaa bb cc', 2)
    validate_edit1d('aa bb cc', 3, { 'viw', 'gm' }, 'aa bbbb cc', 5)
    validate_edit1d('aa bb cc', 6, { 'viw', 'gm' }, 'aa bb cccc', 8)

    -- Linewise
    validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, { 'gmm' }, { 'aa', 'aa', 'bb', 'cc' }, { 2, 0 })
    validate_edit({ 'aa', 'bb', 'cc' }, { 2, 0 }, { 'gmm' }, { 'aa', 'bb', 'bb', 'cc' }, { 3, 0 })
    validate_edit({ 'aa', 'bb', 'cc' }, { 3, 0 }, { 'gmm' }, { 'aa', 'bb', 'cc', 'cc' }, { 4, 0 })

    validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, { 'V', 'gm' }, { 'aa', 'aa', 'bb', 'cc' }, { 2, 0 })
    validate_edit({ 'aa', 'bb', 'cc' }, { 2, 0 }, { 'V', 'gm' }, { 'aa', 'bb', 'bb', 'cc' }, { 3, 0 })
    validate_edit({ 'aa', 'bb', 'cc' }, { 3, 0 }, { 'V', 'gm' }, { 'aa', 'bb', 'cc', 'cc' }, { 4, 0 })

    -- Blockwise
    child.lua([[vim.keymap.set('o', 'ie', function() vim.cmd('normal! \22j') end)]])
    validate_edit({ 'abc', 'def' }, { 1, 0 }, { 'gm', 'ie' }, { 'aabc', 'ddef' }, { 1, 1 })
    validate_edit({ 'abc', 'def' }, { 1, 1 }, { 'gm', 'ie' }, { 'abbc', 'deef' }, { 1, 2 })
    validate_edit({ 'abc', 'def' }, { 1, 2 }, { 'gm', 'ie' }, { 'abcc', 'deff' }, { 1, 3 })

    validate_edit({ 'abc', 'def' }, { 1, 0 }, { '<C-v>j', 'gm' }, { 'aabc', 'ddef' }, { 1, 1 })
    validate_edit({ 'abc', 'def' }, { 1, 1 }, { '<C-v>j', 'gm' }, { 'abbc', 'deef' }, { 1, 2 })
    validate_edit({ 'abc', 'def' }, { 1, 2 }, { '<C-v>j', 'gm' }, { 'abcc', 'deff' }, { 1, 3 })
  end

  child.o.virtualedit = 'all'
  validate()
  child.o.virtualedit = 'onemore'
  validate()
  child.o.virtualedit = 'block'
  validate()
end

T['Multiply']['works with multibyte characters'] = function()
  -- Charwise
  validate_edit({ 'ыыы', 'aa x' }, { 1, 0 }, { 'gm/x<CR>' }, { 'ыыы', 'aa ыыы', 'aa x' }, { 2, 3 })

  -- Linewise
  validate_edit({ 'ыыы', 'aaa', 'x' }, { 1, 0 }, { 'gmj' }, { 'ыыы', 'aaa', 'ыыы', 'aaa', 'x' }, { 3, 0 })

  -- All four blockwise selections
  local validate_blockwise = function(init_cursor, keys)
    validate_edit({ 'ыыы x', 'aaa x' }, init_cursor, keys, { 'ыыыыыы x', 'aaaaaa x' }, { 1, 6 })
  end

  validate_blockwise({ 1, 0 }, { '<C-v>je', 'gm' })
  validate_blockwise({ 1, 4 }, { '<C-v>jb', 'gm' })
  validate_blockwise({ 2, 0 }, { '<C-v>ke', 'gm' })
  validate_blockwise({ 2, 2 }, { '<C-v>kb', 'gm' })
end

T['Multiply']['works in edge cases'] = function()
  -- End of line
  validate_edit1d('aa bb', 3, { 'gmiw' }, 'aa bbbb', 5)
  validate_edit1d('aa bb', 4, { 'gmiw' }, 'aa bbbb', 5)

  -- Last line
  validate_edit({ 'aa' }, { 1, 0 }, { 'gm_' }, { 'aa', 'aa' }, { 2, 0 })
  validate_edit({ 'aa', 'bb' }, { 2, 0 }, { 'gm_' }, { 'aa', 'bb', 'bb' }, { 3, 0 })
end

T['Multiply']['respects `config.multiply.func`'] = function()
  -- Indent by two spaces only for linewise content
  child.lua([[MiniOperators.config.multiply.func = function(content)
    if content.submode ~= 'V' then return content.lines end
    return vim.tbl_map(function(l) return '  ' .. l end, content.lines)
  end]])

  validate_edit1d('aa bb', 0, { 'gmiw' }, 'aaaa bb', 2)
  validate_edit({ 'aa', 'bb', '', 'cc' }, { 1, 0 }, { 'gmip' }, { 'aa', 'bb', '  aa', '  bb', '', 'cc' }, { 3, 2 })
  validate_edit({ 'ab', 'cd' }, { 1, 0 }, { '<C-v>j', 'gm' }, { 'aab', 'ccd' }, { 1, 1 })
end

T['Multiply']["works with 'y' in 'cpoptions'"] = function()
  child.cmd('set cpoptions+=y')

  -- Dot-repeat should still work
  validate_edit1d('aa bb', 0, { 'gmiw', 'w', '.' }, 'aaaa bbbb', 7)
end

T['Multiply']['does not have side effects'] = function()
  set_lines({ 'aa', 'bb', 'xy' })

  -- All non-operator related marks and registers 'x', '"'
  set_cursor(3, 0)
  type_keys('ma')
  type_keys('v"xy')

  set_cursor(3, 1)
  type_keys('mx')
  type_keys('vy')

  -- Do multiply
  set_cursor(1, 0)
  type_keys('gmj')

  -- Validate
  eq(get_lines(), { 'aa', 'bb', 'aa', 'bb', 'xy' })
  eq(child.api.nvim_buf_get_mark(0, 'a'), { 5, 0 })
  eq(child.api.nvim_buf_get_mark(0, 'x'), { 5, 1 })
  eq(child.fn.getreg('x'), 'x')
  eq(child.fn.getreg('"'), 'y')
end

T['Multiply']['preserves visual marks'] = function()
  set_lines({ 'aa', 'bb', 'select' })

  -- Create marks
  set_cursor(3, 0)
  type_keys('viw', '<Esc>')

  -- Multiply
  set_cursor(1, 0)
  type_keys('gmj')
  eq(get_lines(), { 'aa', 'bb', 'aa', 'bb', 'select' })
  eq(child.api.nvim_buf_get_mark(0, '<'), { 5, 0 })
  eq(child.api.nvim_buf_get_mark(0, '>'), { 5, 5 })
end

T['Multiply']['respects `config.multiply.prefix`'] = function()
  child.api.nvim_del_keymap('n', 'gm')
  child.api.nvim_del_keymap('n', 'gmm')
  child.api.nvim_del_keymap('x', 'gm')

  load_module({ multiply = { prefix = 'cm' } })

  validate_edit1d('aa bb', 0, { 'cmiw' }, 'aaaa bb', 2)
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'cmm' }, { 'aa', 'aa', 'bb' }, { 2, 0 })
  validate_edit1d('aa bb', 0, { 'viw', 'cm' }, 'aaaa bb', 2)
end

T['Multiply']['works with `make_mappings()`'] = function()
  child.api.nvim_del_keymap('n', 'gm')
  child.api.nvim_del_keymap('n', 'gmm')
  child.api.nvim_del_keymap('x', 'gm')

  load_module({ multiply = { prefix = '' } })
  make_mappings('multiply', { textobject = 'cm', line = 'cmm', selection = 'cm' })

  validate_edit1d('aa bb', 0, { 'cmiw' }, 'aaaa bb', 2)
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'cmm' }, { 'aa', 'aa', 'bb' }, { 2, 0 })
  validate_edit1d('aa bb', 0, { 'viw', 'cm' }, 'aaaa bb', 2)
end

T['Multiply']['works on visual selection with leading newline'] = function()
  validate_edit({ 'a(', '  b', ')' }, { 2, 2 }, { 'vk', 'gm' }, { 'a(', '  b', '  b', ')' }, { 2, 2 })
end

T['Multiply']['respects `selection=exclusive`'] = function()
  child.o.selection = 'exclusive'

  -- Charwise
  validate_edit1d('aa bb', 0, { 'gmiw' }, 'aaaa bb', 2)
  validate_edit1d('aa bb', 0, { 'viw', 'gm', '<Esc>' }, 'aaaa bb', 2)

  -- Linewise
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'gm_' }, { 'aa', 'aa', 'bb' }, { 2, 0 })
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'V', 'gm' }, { 'aa', 'aa', 'bb' }, { 2, 0 })

  -- Blockwise for all four ways to create block
  -- - Normal mode
  child.lua([[_G.block_object = function(keys)
    return function()
      vim.o.selection = 'inclusive'
      vim.cmd('normal! \22' .. keys)
      vim.schedule(function() vim.o.selection = 'exclusive' end)
    end
  end]])
  child.lua([[vim.keymap.set('o', 'ia', _G.block_object('jl'))]])
  child.lua([[vim.keymap.set('o', 'ib', _G.block_object('jh'))]])
  child.lua([[vim.keymap.set('o', 'ic', _G.block_object('kl'))]])
  child.lua([[vim.keymap.set('o', 'id', _G.block_object('kh'))]])

  local lines = { 'ab rs', 'cd uv' }
  local ref_lines, ref_cursor = { 'abab rs', 'cdcd uv' }, { 1, 2 }
  validate_edit(lines, { 1, 0 }, { 'gmia' }, ref_lines, ref_cursor)
  validate_edit(lines, { 1, 1 }, { 'gmib' }, ref_lines, ref_cursor)
  validate_edit(lines, { 2, 0 }, { 'gmic' }, ref_lines, ref_cursor)
  validate_edit(lines, { 2, 1 }, { 'gmid' }, ref_lines, ref_cursor)

  -- - Visual mode
  validate_edit(lines, { 1, 0 }, { '<C-v>jll', 'gm' }, ref_lines, ref_cursor)
  validate_edit(lines, { 1, 1 }, { '<C-v>jh', 'gm' }, ref_lines, ref_cursor)
  validate_edit(lines, { 2, 0 }, { '<C-v>kl', 'gm' }, ref_lines, ref_cursor)
  validate_edit(lines, { 2, 2 }, { '<C-v>khh', 'gm' }, ref_lines, ref_cursor)
end

T['Multiply']["respects 'nomodifiable'"] = function()
  set_lines({ 'aa bb' })
  set_cursor(1, 0)
  child.bo.modifiable = false
  type_keys('gm$')
  eq(get_lines(), { 'aa bb' })
  eq(get_cursor(), { 1, 4 })
end

T['Multiply']['does not trigger `TextYankPost` event'] = function()
  child.cmd('au TextYankPost * lua _G.been_here = true')
  -- Should also not block other events, like ModeChanged
  child.cmd('au ModeChanged * lua _G.n = (_G.n or 0) + 1')

  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'gmm' }, { 'aa', 'aa', 'bb' }, { 2, 0 })

  eq(child.lua_get('_G.been_here'), vim.NIL)
  eq(child.lua_get('_G.n') >= 5, true)
  eq(child.o.eventignore, '')
end

T['Multiply']['respects `vim.{g,b}.minioperators_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minioperators_disable = true
    validate_edit1d('aa bb', 0, { 'gmiw' }, 'waa bb', 1)
  end,
})

T['Multiply']['respects `vim.b.minioperators_config`'] = function()
  -- Indent by two spaces
  child.lua([[_G.multiply_func = function(content)
    return vim.tbl_map(function(l) return '  ' .. l end, content.lines)
  end
  vim.b.minioperators_config = { multiply = { func = _G.multiply_func } }
  ]])

  validate_edit({ 'aa', 'bb', '', 'cc' }, { 1, 0 }, { 'gmip' }, { 'aa', 'bb', '  aa', '  bb', '', 'cc' }, { 3, 2 })
end

T['Replace'] = new_set()

T['Replace']['works charwise in Normal mode'] = function()
  validate_edit1d('aa bb cc', 0, { 'yiw', 'w', 'graW' }, 'aa aacc', 3)

  -- With dot-repeat
  validate_edit1d('aa bb cc', 0, { 'yiw', 'w', 'graW', '.' }, 'aaaa', 2)

  -- Over several lines
  set_lines({ 'aa bb', 'cc dd' })

  -- - Set mark
  set_cursor(2, 2)
  type_keys('ma')

  -- - Validate
  set_cursor(1, 0)
  type_keys('yiw', 'w', 'gr`a')
  eq(get_lines(), { 'aa aa dd' })
  eq(get_cursor(), { 1, 3 })

  -- Single cell
  validate_edit1d('aa bb', 0, { 'yl', 'w', 'grl' }, 'aa ab', 3)
end

T['Replace']['works linewise in Normal mode'] = function()
  local lines = { 'aa', '', 'bb', 'cc', '', 'dd', 'ee' }
  validate_edit(lines, { 1, 0 }, { 'yy', '2j', 'grip' }, { 'aa', '', 'aa', '', 'dd', 'ee' }, { 3, 0 })

  -- - With dot-repeat
  validate_edit(lines, { 1, 0 }, { 'yy', '2j', 'grip', '2j', '.' }, { 'aa', '', 'aa', '', 'aa' }, { 5, 0 })
end

T['Replace']['correctly reindents linewise in Normal mode'] = function()
  -- Should use indent from text being replaced
  validate_edit({ '\taa', 'bb' }, { 1, 0 }, { 'yy', 'j', 'gr_' }, { '\taa', 'aa' }, { 2, 0 })
  validate_edit({ '\taa', 'bb' }, { 2, 0 }, { 'yy', 'k', 'gr_' }, { '\tbb', 'bb' }, { 1, 0 })
  validate_edit({ '\taa', '\t\tbb' }, { 1, 0 }, { 'yy', 'j', 'gr_' }, { '\taa', '\t\taa' }, { 2, 0 })
  validate_edit({ '\taa', '\t\tbb' }, { 2, 0 }, { 'yy', 'k', 'gr_' }, { '\tbb', '\t\tbb' }, { 1, 0 })

  validate_edit({ '  aa', 'bb' }, { 1, 0 }, { 'yy', 'j', 'gr_' }, { '  aa', 'aa' }, { 2, 0 })
  validate_edit({ '  aa', 'bb' }, { 2, 0 }, { 'yy', 'k', 'gr_' }, { '  bb', 'bb' }, { 1, 0 })
  validate_edit({ '  aa', '    bb' }, { 1, 0 }, { 'yy', 'j', 'gr_' }, { '  aa', '    aa' }, { 2, 0 })
  validate_edit({ '  aa', '    bb' }, { 2, 0 }, { 'yy', 'k', 'gr_' }, { '  bb', '    bb' }, { 1, 0 })

  -- Should replace current region indent with new one
  validate_edit(
    { '\taa', '\t\tbb', 'cc' },
    { 1, 0 },
    { 'yj', 'G', 'gr_' },
    { '\taa', '\t\tbb', 'aa', '\tbb' },
    { 3, 0 }
  )

  -- Should preserve tabs vs spaces
  validate_edit({ '\taa', '  bb' }, { 1, 0 }, { 'yy', 'j', 'gr_' }, { '\taa', '  aa' }, { 2, 2 })
  validate_edit({ '\taa', '  bb' }, { 2, 0 }, { 'yy', 'k', 'gr_' }, { '\tbb', '  bb' }, { 1, 0 })

  -- Should correctly work in presence of blank lines (compute indent and not
  -- reindent them)
  validate_edit(
    { '\t\taa', '', '\t', '\tcc' },
    { 1, 0 },
    { 'y2j', 'G', 'gr_' },
    { '\t\taa', '', '\t', '\taa', '', '\t' },
    { 4, 0 }
  )

  -- Should correctly work replacing **only** blank lines
  validate_edit({ 'aa', '\t\t', '\t' }, { 1, 0 }, { 'yy', 'j', 'grj' }, { 'aa', '\taa' }, { 2, 0 })
end

T['Replace']['works blockwise in Normal mode'] = function()
  child.lua([[vim.keymap.set('o', 'io', function() vim.cmd('normal! \22') end)]])
  child.lua([[vim.keymap.set('o', 'ie', function() vim.cmd('normal! \22j') end)]])

  validate_edit({ 'a b c', 'a b c' }, { 1, 0 }, { 'y<C-v>j', 'w', 'grie' }, { 'a a c', 'a a c' }, { 1, 2 })

  -- With dot-repeat
  validate_edit({ 'a b c', 'a b c' }, { 1, 0 }, { 'y<C-v>j', 'w', 'grie', 'w', '.' }, { 'a a a', 'a a a' }, { 1, 4 })

  -- Single cell
  validate_edit1d('aa bb', 0, { '<C-v>y', 'w', 'grio' }, 'aa ab', 3)
end

T['Replace']['works with mixed submodes in Normal mode'] = function()
  child.lua([[vim.keymap.set('o', 'ie', function() vim.cmd('normal! \22j') end)]])

  -- Charwise paste - Linewise region
  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, { 'yiw', 'j', 'gr_' }, { 'aa', 'aa', 'cc' }, { 2, 0 })
  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, { 'y/b$<CR>', 'j', 'gr_' }, { 'aa', 'aa', 'b', 'cc' }, { 2, 0 })

  -- Charwise paste - Blockwise region
  validate_edit({ 'aa', 'bc', 'de' }, { 1, 0 }, { 'yiw', 'j', 'grie' }, { 'aa', 'aac', 'e' }, { 2, 0 })
  validate_edit({ 'aa', 'bc', 'de' }, { 1, 0 }, { 'y/c<CR>', 'j', 'grie' }, { 'aa', 'aac', 'b e' }, { 2, 0 })

  -- Linewise paste - Charwise region
  validate_edit({ 'aa', 'bb bb' }, { 1, 0 }, { 'yy', 'j', 'griw' }, { 'aa', 'aa bb' }, { 2, 0 })
  validate_edit({ 'aa', 'bb', 'cc cc' }, { 1, 0 }, { 'yj', '2j', 'griw' }, { 'aa', 'bb', 'aa', 'bb cc' }, { 3, 0 })

  -- Linewise paste - Blockwise region
  validate_edit({ 'aa', 'bc', 'de' }, { 1, 0 }, { 'yy', 'j', 'grie' }, { 'aa', 'aac', 'e' }, { 2, 0 })
  validate_edit({ 'aa', 'bb', 'cd', 'ef' }, { 1, 0 }, { 'yj', '2j', 'grie' }, { 'aa', 'bb', 'aad', 'bbf' }, { 3, 0 })

  -- Blockwise paste - Charwise region
  validate_edit({ 'aa', 'bb bb' }, { 1, 0 }, { '<C-v>y', 'j', 'griw' }, { 'aa', 'a bb' }, { 2, 0 })
  validate_edit({ 'aa', 'bb bb' }, { 1, 0 }, { 'y<C-v>j', 'j', 'griw' }, { 'aa', 'a', 'b bb' }, { 2, 0 })

  -- Blockwise paste - Linewise region
  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, { '<C-v>y', 'j', 'gr_' }, { 'aa', 'a', 'cc' }, { 2, 0 })
  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, { 'y<C-v>j', 'j', 'gr_' }, { 'aa', 'a', 'b', 'cc' }, { 2, 0 })
end

T['Replace']['works with two types of `[count]` in Normal mode'] = function()
  -- First `[count]` for paste with dot-repeat
  validate_edit1d('aa bb cc dd', 0, { 'yiw', 'w', '2graW' }, 'aa aaaacc dd', 3)
  validate_edit1d('aa bb cc dd', 0, { 'yiw', 'w', '2graW', 'w', '.' }, 'aa aaaaccaaaa', 9)

  -- Second `[count]` for textobject with dot-repeat
  validate_edit1d('aa bb cc dd ee', 0, { 'yiw', 'w', 'gr2aW' }, 'aa aadd ee', 3)
  validate_edit1d('aa bb cc dd ee', 0, { 'yiw', 'w', 'gr2aW', '.' }, 'aaaa', 2)

  -- Both `[count]`s with dot-repeat
  validate_edit1d('aa bb cc dd ee', 0, { 'yiw', 'w', '2gr2aW' }, 'aa aaaadd ee', 3)
  validate_edit1d('aa bb cc dd ee', 0, { 'yiw', 'w', '2gr2aW', '.' }, 'aaaaaa', 2)
end

T['Replace']['works with `cmdheight=0`'] = function()
  child.set_size(7, 20)
  child.o.cmdheight = 0
  child.o.statusline = 'My statusline'
  -- Force quick test for regular `gr` operator
  child.api.nvim_del_keymap('n', 'grr')

  set_lines({ 'aa bb' })
  type_keys('yiw', 'w')
  type_keys('gr')
  child.expect_screenshot({ redraw = false })
  type_keys('iw')
  child.expect_screenshot({ redraw = false })
end

T['Replace']['works in Normal mode for line'] = function()
  validate_edit({ 'aa', 'bb' }, { 1, 1 }, { 'yy', 'j', 'grr' }, { 'aa', 'aa' }, { 2, 0 })

  -- With dot-repeat
  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 1 }, { 'yy', 'j', 'grr', 'j', '.' }, { 'aa', 'aa', 'aa' }, { 3, 0 })
end

T['Replace']['works with `[count]` in Normal mode for line'] = function()
  validate_edit({ 'aa', 'bb' }, { 1, 1 }, { 'yy', 'j', '2grr' }, { 'aa', 'aa', 'aa' }, { 2, 0 })

  -- With dot-repeat
  validate_edit(
    { 'aa', 'bb', 'cc' },
    { 1, 1 },
    { 'yy', 'j', '2grr', '2j', '.' },
    { 'aa', 'aa', 'aa', 'aa', 'aa' },
    { 4, 0 }
  )
end

T['Replace']['works with empty textobject/motion'] = function()
  child.api.nvim_set_keymap('o', 'w', '<Cmd><CR>', {})
  set_lines({ 'xxx', 'yyy' })
  set_cursor(1, 1)
  type_keys('yiw', 'jl')
  type_keys('gr', 'w')
  eq(get_lines(), { 'xxx', 'yyy' })
end

T['Replace']['works in Visual mode'] = function()
  -- Charwise selection
  validate_edit({ 'aa bb' }, { 1, 0 }, { 'yiw', 'w', 'viw', 'gr' }, { 'aa aa' }, { 1, 3 })
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'yy', 'j', 'viw', 'gr' }, { 'aa', 'aa' }, { 2, 0 })
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'y<C-v>j', 'viw', 'gr' }, { 'a', 'b', 'bb' }, { 1, 0 })

  -- Linewise selection
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'yiw', 'j', 'V', 'gr' }, { 'aa', 'aa' }, { 2, 0 })
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'yy', 'j', 'V', 'gr' }, { 'aa', 'aa' }, { 2, 0 })
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'y<C-v>j', 'j', 'V', 'gr' }, { 'aa', 'a', 'b' }, { 2, 0 })

  -- Blockwise selection
  validate_edit({ 'a b', 'a b' }, { 1, 0 }, { 'yiw', 'w', '<C-v>j', 'gr' }, { 'a a', 'a ' }, { 1, 2 })
  validate_edit({ 'a b', 'a b' }, { 1, 0 }, { 'yy', 'w', '<C-v>j', 'gr' }, { 'a a b', 'a ' }, { 1, 2 })
  validate_edit({ 'a b', 'a b' }, { 1, 0 }, { 'y<C-v>j', 'w', '<C-v>j', 'gr' }, { 'a a', 'a a' }, { 1, 2 })
end

T['Replace']['works with different `virtualedit`'] = function()
  local validate = function()
    -- Charwise
    validate_edit1d('aa bb cc', 3, { 'yiw', 'b', 'gr', 'iw' }, 'bb bb cc', 0)
    validate_edit1d('aa bb cc', 0, { 'yiw', 'w', 'gr', 'iw' }, 'aa aa cc', 3)
    validate_edit1d('aa bb cc', 0, { 'yiw', '2w', 'gr', 'iw' }, 'aa bb aa', 6)

    validate_edit1d('aa bb cc', 3, { 'yiw', 'b', 'viw', 'gr' }, 'bb bb cc', 0)
    validate_edit1d('aa bb cc', 0, { 'yiw', 'w', 'viw', 'gr' }, 'aa aa cc', 3)
    validate_edit1d('aa bb cc', 0, { 'yiw', '2w', 'viw', 'gr' }, 'aa bb aa', 6)

    -- Linewise
    validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, { 'yy', 'j', 'grr' }, { 'aa', 'aa', 'cc' }, { 2, 0 })
    validate_edit({ 'aa', 'bb', 'cc' }, { 2, 0 }, { 'yy', 'j', 'grr' }, { 'aa', 'bb', 'bb' }, { 3, 0 })
    validate_edit({ 'aa', 'bb', 'cc' }, { 3, 0 }, { 'yy', 'k', 'grr' }, { 'aa', 'cc', 'cc' }, { 2, 0 })

    validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, { 'yy', 'j', 'V', 'gr' }, { 'aa', 'aa', 'cc' }, { 2, 0 })
    validate_edit({ 'aa', 'bb', 'cc' }, { 2, 0 }, { 'yy', 'j', 'V', 'gr' }, { 'aa', 'bb', 'bb' }, { 3, 0 })
    validate_edit({ 'aa', 'bb', 'cc' }, { 3, 0 }, { 'yy', 'k', 'V', 'gr' }, { 'aa', 'cc', 'cc' }, { 2, 0 })

    -- Blockwise
    child.lua([[vim.keymap.set('o', 'ie', function() vim.cmd('normal! \22j') end)]])
    validate_edit({ 'abc', 'def' }, { 1, 0 }, { 'y', 'ie', 'l', 'gr', 'ie' }, { 'aac', 'ddf' }, { 1, 1 })
    validate_edit({ 'abc', 'def' }, { 1, 1 }, { 'y', 'ie', 'l', 'gr', 'ie' }, { 'abb', 'dee' }, { 1, 2 })
    validate_edit({ 'abc', 'def' }, { 1, 2 }, { 'y', 'ie', 'h', 'gr', 'ie' }, { 'acc', 'dff' }, { 1, 1 })

    validate_edit({ 'abc', 'def' }, { 1, 0 }, { 'y', 'ie', 'l', '<C-v>j', 'gr' }, { 'aac', 'ddf' }, { 1, 1 })
    validate_edit({ 'abc', 'def' }, { 1, 1 }, { 'y', 'ie', 'l', '<C-v>j', 'gr' }, { 'abb', 'dee' }, { 1, 2 })
    validate_edit({ 'abc', 'def' }, { 1, 2 }, { 'y', 'ie', 'h', '<C-v>j', 'gr' }, { 'acc', 'dff' }, { 1, 1 })
  end

  child.o.virtualedit = 'all'
  validate()
  child.o.virtualedit = 'onemore'
  validate()
  child.o.virtualedit = 'block'
  validate()
end

T['Replace']['correctly reindents linewise in Visual mode'] = function()
  -- Should use indent from text being replaced
  validate_edit({ '\taa', 'bb' }, { 1, 0 }, { 'yy', 'j', 'V', 'gr' }, { '\taa', 'aa' }, { 2, 0 })
  validate_edit({ '\taa', 'bb' }, { 2, 0 }, { 'yy', 'k', 'V', 'gr' }, { '\tbb', 'bb' }, { 1, 0 })
  validate_edit({ '  aa', '    bb' }, { 1, 0 }, { 'yy', 'j', 'V', 'gr' }, { '  aa', '    aa' }, { 2, 0 })
  validate_edit({ '  aa', '    bb' }, { 2, 0 }, { 'yy', 'k', 'V', 'gr' }, { '  bb', '    bb' }, { 1, 0 })

  -- Should replace current region indent with new one
  validate_edit(
    { '\taa', '\t\tbb', 'cc' },
    { 1, 0 },
    { 'yj', 'G', 'V', 'gr' },
    { '\taa', '\t\tbb', 'aa', '\tbb' },
    { 3, 0 }
  )

  -- Should preserve tabs vs spaces
  validate_edit({ '\taa', '  bb' }, { 1, 0 }, { 'yy', 'j', 'V', 'gr' }, { '\taa', '  aa' }, { 2, 0 })
  validate_edit({ '\taa', '  bb' }, { 2, 0 }, { 'yy', 'k', 'V', 'gr' }, { '\tbb', '  bb' }, { 1, 0 })

  -- Should correctly work in presence of blank lines (compute indent and not
  -- reindent them)
  validate_edit(
    { '\t\taa', '', '\t', '\tcc' },
    { 1, 0 },
    { 'y2j', 'G', 'V', 'gr' },
    { '\t\taa', '', '\t', '\taa', '', '\t' },
    { 4, 0 }
  )

  -- Should correctly work replacing **only** blank lines
  validate_edit({ 'aa', '\t\t', '\t' }, { 1, 0 }, { 'yy', 'j', 'Vj', 'gr' }, { 'aa', '\taa' }, { 2, 0 })
end

T['Replace']['works with `[count]` in Visual mode'] = function()
  validate_edit1d('aa bb', 0, { 'yiw', 'w', 'viw', '2gr' }, 'aa aaaa', 3)
end

T['Replace']['respects `config.replace.reindent_linewise`'] = function()
  child.lua('MiniOperators.config.replace.reindent_linewise = false')
  validate_edit({ '\taa', 'bb' }, { 1, 0 }, { 'yy', 'j', 'gr_' }, { '\taa', '\taa' }, { 2, 0 })
end

T['Replace']['works with `[register]`'] = function()
  -- Normal mode
  validate_edit1d('aa bb cc', 0, { '"xyiw', 'w', 'yiw', 'w', '"xgriw' }, 'aa bb aa', 6)

  -- Visual mode
  validate_edit1d('aa bb cc', 0, { '"xyiw', 'w', 'yiw', 'w', 'viw', '"xgr' }, 'aa bb aa', 6)

  -- Readonly registers
  child.o.cmdheight = 15
  set_lines({ 'aaa' })
  type_keys('"xyy')

  -- - Empty yet valid registers (as they were not written yet)
  expect.error(function() type_keys('"%griw') end, 'Register "%%" is empty')
  expect.error(function() type_keys('".griw') end, 'Register "%." is empty')
  expect.error(function() type_keys('":griw') end, 'Register "%:" is empty')

  child.api.nvim_buf_set_name(0, 'xxx')
  type_keys('"%griw')
  eq(get_lines(), { 'xxx' })

  type_keys('o', 'bbb', '<Esc>', 'k')
  type_keys('".griw')
  eq(get_lines(), { 'bbb', 'bbb' })

  type_keys(':lua print(1)', '<CR>')
  type_keys('":griw')
  eq(get_lines(), { 'lua print(1)', 'bbb' })

  -- Special registers
  -- - Temporary register used in the implementation
  type_keys('"xgriw')
  eq(get_lines(), { 'aaa print(1)', 'bbb' })

  -- - Alternate file
  expect.error(function() type_keys('"#griw') end, 'Register "#" is empty')
  child.api.nvim_set_current_buf(child.api.nvim_create_buf(true, false))
  set_lines({ 'yyy' })
  type_keys('"#griw')
  eq(get_lines(), { 'xxx' })

  -- - Expression register
  type_keys('"=', '1+1<CR>', 'griw')
  eq(get_lines(), { '2' })

  -- - Black hole
  type_keys('"_griw')
  eq(get_lines(), { '' })

  -- Should all work with linewise operator
  set_lines({ 'uuu', 'vvv' })
  set_cursor(1, 0)
  type_keys('"#grr')
  eq(get_lines(), { 'xxx', 'vvv' })
  type_keys('"=', '["a"]<CR>', 'grr')
  eq(get_lines(), { 'a', 'vvv' })

  child.cmd('b#')
  set_cursor(1, 0)
  type_keys('"%grr')
  eq(get_lines(), { 'xxx', 'bbb' })
  type_keys('".grr')
  eq(get_lines(), { 'bbb', 'bbb' })
  type_keys('":grr')
  eq(get_lines(), { 'lua print(1)', 'bbb' })
end

T['Replace']['propagates informative error about `[register]` content'] = function()
  child.o.cmdheight = 15
  set_lines({ 'aa bb' })
  type_keys('yiw', 'w')

  expect.error(function() type_keys('"agriw') end, 'Register "a" is empty')
  expect.error(function() type_keys('"Agriw') end, 'Register "A" is invalid')
end

T['Replace']['works in edge cases'] = function()
  -- Start of line
  validate_edit1d('aa bb', 3, { 'yiw', '0', 'griw' }, 'bb bb', 0)

  -- End of line
  validate_edit1d('aa bb', 0, { 'yiw', 'w', 'griw' }, 'aa aa', 3)

  -- First line
  validate_edit({ 'aa', 'bb' }, { 2, 0 }, { 'yy', 'k', 'grr' }, { 'bb', 'bb' }, { 1, 0 })

  -- Last line
  validate_edit({ 'aa', 'bb', 'cc' }, { 1, 0 }, { 'yy', 'G', 'grr' }, { 'aa', 'bb', 'aa' }, { 3, 0 })
end

T['Replace']['can replace whole buffer'] = function()
  set_lines({ 'aa', 'bb' })
  type_keys('yip')

  set_lines({ 'cc', 'dd' })
  type_keys('grip')
  eq(get_lines(), { 'aa', 'bb' })
end

T['Replace']['does not have side effects'] = function()
  set_lines({ 'aa', 'bb', 'cc', 'xy' })

  -- All non-operator related marks, target and temporary register
  set_cursor(4, 0)
  type_keys('ma')
  type_keys('v"xy')

  set_cursor(4, 1)
  type_keys('mx')
  type_keys('vy')

  -- Do replace
  set_cursor(1, 0)
  type_keys('yiw')
  local target_register_info = child.fn.getreginfo('"')
  local temp_register_info = child.fn.getreginfo('x')
  set_cursor(2, 0)
  type_keys('grj')

  -- Validate
  eq(get_lines(), { 'aa', 'aa', 'xy' })
  eq(child.api.nvim_buf_get_mark(0, 'a'), { 3, 0 })
  eq(child.api.nvim_buf_get_mark(0, 'x'), { 3, 1 })
  eq(child.fn.getreginfo('"'), target_register_info)
  eq(child.fn.getreginfo('x'), temp_register_info)
end

T['Replace']['preserves visual marks'] = function()
  set_lines({ 'aa', 'bb', 'cc', 'select' })

  -- Create marks
  set_cursor(4, 0)
  type_keys('viw', '<Esc>')

  -- Replace
  set_cursor(1, 0)
  type_keys('yy', 'j', 'grj')
  eq(get_lines(), { 'aa', 'aa', 'select' })
  eq(child.api.nvim_buf_get_mark(0, '<'), { 3, 0 })
  eq(child.api.nvim_buf_get_mark(0, '>'), { 3, 5 })
end

T['Replace']['respects `config.replace.prefix`'] = function()
  child.api.nvim_del_keymap('n', 'gr')
  child.api.nvim_del_keymap('n', 'grr')
  child.api.nvim_del_keymap('x', 'gr')

  load_module({ replace = { prefix = 'gR' } })

  validate_edit1d('aa bb', 0, { 'yiw', 'w', 'gRiw' }, 'aa aa', 3)
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'yy', 'j', 'gRR' }, { 'aa', 'aa' }, { 2, 0 })
  validate_edit1d('aa bb', 0, { 'yiw', 'w', 'viw', 'gR' }, 'aa aa', 3)
end

T['Replace']['works with `make_mappings()`'] = function()
  child.api.nvim_del_keymap('n', 'gr')
  child.api.nvim_del_keymap('n', 'grr')
  child.api.nvim_del_keymap('x', 'gr')

  load_module({ replace = { prefix = '' } })
  make_mappings('replace', { textobject = 'gR', line = 'gRr', selection = 'gR' })

  validate_edit1d('aa bb', 0, { 'yiw', 'w', 'gRiw' }, 'aa aa', 3)
  validate_edit({ 'aa', 'bb' }, { 1, 0 }, { 'yy', 'j', 'gRr' }, { 'aa', 'aa' }, { 2, 0 })
  validate_edit1d('aa bb', 0, { 'yiw', 'w', 'viw', 'gR' }, 'aa aa', 3)
end

T['Replace']['works on visual selection with leading newline'] = function()
  validate_edit({ 'a(', '  b', ')' }, { 2, 2 }, { 'vky', 'gvgr' }, { 'a(', '  b', ')' }, { 1, 1 })
end

T['Replace']['works on visual selection with trailing newline'] = function()
  validate_edit({ 'a(', '  b', ')' }, { 2, 2 }, { 'vkoly', 'gvgr' }, { 'a(', '  b', '', ')' }, { 1, 1 })
end

T['Replace']['respects `selection=exclusive`'] = function()
  child.lua([[vim.keymap.set('o', 'ie', function() vim.cmd('normal! \22j') end)]])
  child.o.selection = 'exclusive'

  validate_edit1d('aaa bbb x', 0, { 'yiw', 'w', 'griw' }, 'aaa aaa x', 4)
  validate_edit({ 'aa', 'bb', 'x' }, { 1, 0 }, { 'yy', 'j', 'gr_' }, { 'aa', 'aa', 'x' }, { 2, 0 })
  validate_edit({ 'a b c', 'a b c' }, { 1, 0 }, { 'y<C-v>j', 'w', 'grie' }, { 'a a c', 'a a c' }, { 1, 2 })

  validate_edit1d('aaa bbb x', 0, { 'yiw', 'w', 'viw', 'gr' }, 'aaa aaa x', 4)
  validate_edit({ 'aa', 'bb', 'x' }, { 1, 0 }, { 'yy', 'j', 'V', 'gr' }, { 'aa', 'aa', 'x' }, { 2, 0 })
  validate_edit({ 'a b c', 'a b c' }, { 1, 0 }, { 'y<C-v>j', 'w', '<C-v>j', 'gr' }, { 'a a c', 'a a c' }, { 1, 2 })
end

T['Replace']["respects 'nomodifiable'"] = function()
  set_lines({ 'aa bb' })
  set_cursor(1, 0)
  child.bo.modifiable = false
  type_keys('yiw', 'w', 'gr$')
  eq(get_lines(), { 'aa bb' })
  eq(get_cursor(), { 1, 4 })
end

T['Replace']['does not trigger `TextYankPost` event'] = function()
  set_lines({ 'aa' })
  type_keys('yiw')

  child.cmd('au TextYankPost * lua _G.been_here = true')
  -- Should also not block other events, like ModeChanged
  child.cmd('au ModeChanged * lua _G.n = (_G.n or 0) + 1')

  validate_edit1d('bb', 0, { 'griw' }, 'aa', 0)

  eq(child.lua_get('_G.been_here'), vim.NIL)
  eq(child.lua_get('_G.n') >= 5, true)
  eq(child.o.eventignore, '')
end

T['Replace']['respects `vim.{g,b}.minioperators_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minioperators_disable = true
    validate_edit1d('aa bb', 0, { 'yiw', 'w', 'griw' }, 'aa wbb', 4)
  end,
})

T['Replace']['respects `vim.b.minioperators_config`'] = function()
  child.b.minioperators_config = { replace = { reindent_linewise = false } }

  validate_edit(
    { '\taa', '\tbb', 'cc', 'dd' },
    { 2, 0 },
    { 'yy', 'G', 'gr_' },
    { '\taa', '\tbb', 'cc', '\tbb' },
    { 4, 0 }
  )
end

T['Sort'] = new_set()

-- More testing is done in `default_sort_func()` tests

T['Sort']['works charwise in Normal mode'] = function()
  validate_edit1d('c, a, b', 0, { 'gs$' }, 'a, b, c', 0)

  -- With dot-repeat
  validate_edit1d('(b, a) (d, c)', 0, { 'gsi)', 'f(', '.' }, '(a, b) (c, d)', 8)

  -- Over several lines
  set_lines({ 'b, a', 'd, cx' })

  -- - Set mark
  set_cursor(2, 4)
  type_keys('ma')

  -- - Validate
  set_cursor(1, 0)
  type_keys('gs`a')
  eq(get_lines(), { 'a', 'd, b, cx' })
  eq(get_cursor(), { 1, 0 })

  -- Already sorted
  validate_edit1d('a, b, c', 0, { 'gs$' }, 'a, b, c', 0)

  -- Correctly picks split pattern
  validate_edit1d('b, a; c', 0, { 'gs$' }, 'a; c, b', 0)
  validate_edit1d('b a c', 0, { 'gs$' }, 'a b c', 0)
  validate_edit1d('bac', 0, { 'gs$' }, 'abc', 0)

  -- Works with empty parts
  validate_edit1d('a,,b,', 0, { 'gs$' }, ',,a,b', 0)

  -- Preserves whitespace
  validate_edit1d('e ,  d,   b    ,a,c', 0, { 'gs$' }, 'a ,  b,   c    ,d,e', 0)
end

T['Sort']['works linewise in Normal mode'] = function()
  validate_edit({ 'cc', 'bb', 'aa' }, { 1, 0 }, { 'gsip' }, { 'aa', 'bb', 'cc' }, { 1, 0 })
  validate_edit({ 'xc', 'xb', 'xa' }, { 1, 0 }, { 'gsip' }, { 'xa', 'xb', 'xc' }, { 1, 0 })

  -- - With dot-repeat
  validate_edit({ 'd', 'c', '', 'b', 'a' }, { 1, 0 }, { 'gsip', 'G', '.' }, { 'c', 'd', '', 'a', 'b' }, { 4, 0 })
end

T['Sort']['works blockwise in Normal mode'] = function()
  child.lua([[vim.keymap.set('o', 'ie', function() vim.cmd('normal! \22j') end)]])
  child.lua([[vim.keymap.set('o', 'il', function() vim.cmd('normal! \22jl') end)]])

  validate_edit({ 'cb', 'ba', 'ac' }, { 1, 1 }, { 'gsie' }, { 'ca', 'bb', 'ac' }, { 1, 1 })
  validate_edit({ 'cxb', 'bxa', 'axc' }, { 1, 1 }, { 'gsil' }, { 'cxa', 'bxb', 'axc' }, { 1, 1 })

  -- With dot-repeat
  validate_edit({ 'cbt', 'bar', 'acs' }, { 1, 1 }, { 'gsie', 'l', '.' }, { 'car', 'bbt', 'acs' }, { 1, 2 })
end

T['Sort']['works in Normal mode for line'] = function()
  -- Should apply charwise sort on non-blank part of line
  validate_edit1d('c, a, b', 0, { 'gss' }, 'a, b, c', 0)
  validate_edit1d('c; a; b', 0, { 'gss' }, 'a; b; c', 0)
  validate_edit1d('c a b', 0, { 'gss' }, 'a b c', 0)

  validate_edit({ 't, r, s', 'c, a, b' }, { 1, 0 }, { 'gss' }, { 'r, s, t', 'c, a, b' }, { 1, 0 })

  validate_edit1d('c, a, b', 3, { 'gss' }, 'a, b, c', 0)
  validate_edit1d('  c, a, b  ', 0, { 'gss' }, '  a, b, c  ', 2)

  validate_edit1d('  c a b  ', 0, { 'gss' }, '  a b c  ', 2)

  -- With dot-repeat
  validate_edit({ 't, r, s', 'c, a, b' }, { 1, 0 }, { 'gss', 'j', '.' }, { 'r, s, t', 'a, b, c' }, { 2, 0 })
end

T['Sort']['works with empty textobject/motion'] = function()
  child.api.nvim_set_keymap('o', 'w', '<Cmd><CR>', {})
  set_lines({ 'fedcba' })
  set_cursor(1, 1)
  type_keys('gs', 'w')
  eq(get_lines(), { 'fedcba' })
end

T['Sort']['works in Visual mode'] = function()
  -- Charwise region
  validate_edit1d('c, a, b', 0, { 'v$', 'gs' }, 'a, b, c', 0)
  validate_edit1d('(s, r), a', 0, { 'vi)', 'gs' }, '(r, s), a', 1)

  -- Linewise region
  validate_edit({ 'cc', 'aa', 'bb' }, { 1, 0 }, { 'vip', 'gs' }, { 'aa', 'bb', 'cc' }, { 1, 0 })
  validate_edit({ 'ss', 'rr', '', 'aa' }, { 1, 0 }, { 'vip', 'gs' }, { 'rr', 'ss', '', 'aa' }, { 1, 0 })

  -- Blockwise region
  validate_edit({ 'cbx', 'bax', 'acx' }, { 1, 1 }, { '<C-v>2j', 'gs' }, { 'cax', 'bbx', 'acx' }, { 1, 1 })
  validate_edit({ 'cxb', 'bxa', 'axc' }, { 1, 1 }, { '<C-v>jl', 'gs' }, { 'cxa', 'bxb', 'axc' }, { 1, 1 })
end

T['Sort']['works with different `virtualedit`'] = function()
  local validate = function()
    -- Charwise
    validate_edit1d('cc bb aa', 0, { 'gs', '2e' }, 'bb cc aa', 0)
    validate_edit1d('cc bb aa', 3, { 'gs', '2e' }, 'cc aa bb', 3)
    validate_edit1d('cc bb aa', 0, { 'gs', '3e' }, 'aa bb cc', 0)

    validate_edit1d('cc bb aa', 0, { 'v2e', 'gs' }, 'bb cc aa', 0)
    validate_edit1d('cc bb aa', 3, { 'v2e', 'gs' }, 'cc aa bb', 3)
    validate_edit1d('cc bb aa', 0, { 'v3e', 'gs' }, 'aa bb cc', 0)

    -- Linewise
    validate_edit({ 'cc', 'bb', 'aa' }, { 1, 0 }, { 'gs', 'j' }, { 'bb', 'cc', 'aa' }, { 1, 0 })
    validate_edit({ 'cc', 'bb', 'aa' }, { 2, 0 }, { 'gs', 'j' }, { 'cc', 'aa', 'bb' }, { 2, 0 })
    validate_edit({ 'cc', 'bb', 'aa' }, { 1, 0 }, { 'gs', '2j' }, { 'aa', 'bb', 'cc' }, { 1, 0 })

    validate_edit({ 'cc', 'bb', 'aa' }, { 1, 0 }, { 'Vj', 'gs' }, { 'bb', 'cc', 'aa' }, { 1, 0 })
    validate_edit({ 'cc', 'bb', 'aa' }, { 2, 0 }, { 'Vj', 'gs' }, { 'cc', 'aa', 'bb' }, { 2, 0 })
    validate_edit({ 'cc', 'bb', 'aa' }, { 1, 0 }, { 'V2j', 'gs' }, { 'aa', 'bb', 'cc' }, { 1, 0 })

    -- Blockwise
    child.lua([[vim.keymap.set('o', 'iE', function() vim.cmd('normal! \22jj') end)]])
    validate_edit({ 'cba', 'bac', 'acb' }, { 1, 0 }, { 'gs', 'iE' }, { 'aba', 'bac', 'ccb' }, { 1, 0 })
    validate_edit({ 'cba', 'bac', 'acb' }, { 1, 1 }, { 'gs', 'iE' }, { 'caa', 'bbc', 'acb' }, { 1, 1 })
    validate_edit({ 'cba', 'bac', 'acb' }, { 1, 2 }, { 'gs', 'iE' }, { 'cba', 'bab', 'acc' }, { 1, 2 })

    validate_edit({ 'cba', 'bac', 'acb' }, { 1, 0 }, { '<C-v>jj', 'gs' }, { 'aba', 'bac', 'ccb' }, { 1, 0 })
    validate_edit({ 'cba', 'bac', 'acb' }, { 1, 1 }, { '<C-v>jj', 'gs' }, { 'caa', 'bbc', 'acb' }, { 1, 1 })
    validate_edit({ 'cba', 'bac', 'acb' }, { 1, 2 }, { '<C-v>jj', 'gs' }, { 'cba', 'bab', 'acc' }, { 1, 2 })
  end

  child.o.virtualedit = 'all'
  validate()
  child.o.virtualedit = 'onemore'
  validate()
  child.o.virtualedit = 'block'
  validate()
end

T['Sort']['respects `config.sort.func`'] = function()
  -- Compare by the second character
  child.lua([[MiniOperators.config.sort.func = function(content)
    local compare_second = function(a, b) return a:sub(2, 2) < b:sub(2, 2) end
    return MiniOperators.default_sort_func(content, { compare_fun = compare_second })
  end
  ]])

  validate_edit({ 'ab', 'ba' }, { 1, 0 }, { 'gsip' }, { 'ba', 'ab' }, { 1, 0 })
end

T['Sort']["works with 'y' in 'cpoptions'"] = function()
  child.cmd('set cpoptions+=y')

  -- Dot-repeat should still work
  validate_edit1d('(b, a) (d, c)', 0, { 'gsi)', 'f(', '.' }, '(a, b) (c, d)', 8)
end

T['Sort']['does not have side effects'] = function()
  set_lines({ 'bb', 'aa', 'xy' })

  -- All non-operator related marks and registers 'x', '"'
  set_cursor(3, 0)
  type_keys('ma')
  type_keys('v"xy')

  set_cursor(3, 1)
  type_keys('mx')
  type_keys('vy')

  -- Do sort
  set_cursor(1, 0)
  type_keys('gsj')

  -- Validate
  eq(child.api.nvim_buf_get_mark(0, 'a'), { 3, 0 })
  eq(child.api.nvim_buf_get_mark(0, 'x'), { 3, 1 })
  eq(child.fn.getreg('x'), 'x')
  eq(child.fn.getreg('"'), 'y')
end

T['Sort']['preserves visual marks'] = function()
  set_lines({ 'cc', 'aa', 'bb', 'select' })

  -- Create marks
  set_cursor(4, 0)
  type_keys('viw', '<Esc>')

  -- Sort
  set_cursor(1, 0)
  type_keys('gs2j')
  eq(get_lines(), { 'aa', 'bb', 'cc', 'select' })
  eq(child.api.nvim_buf_get_mark(0, '<'), { 4, 0 })
  eq(child.api.nvim_buf_get_mark(0, '>'), { 4, 5 })
end

T['Sort']['respects `config.sort.prefix`'] = function()
  child.api.nvim_del_keymap('n', 'gs')
  child.api.nvim_del_keymap('n', 'gss')
  child.api.nvim_del_keymap('x', 'gs')

  load_module({ sort = { prefix = 'cs' } })

  validate_edit1d('c, a, b', 0, { 'cs$' }, 'a, b, c', 0)
  validate_edit1d('  c, a, b  ', 0, { 'css' }, '  a, b, c  ', 2)
  validate_edit1d('(c, a, b)', 0, { 'vi)', 'cs' }, '(a, b, c)', 1)
end

T['Sort']['works with `make_mappings()`'] = function()
  child.api.nvim_del_keymap('n', 'gs')
  child.api.nvim_del_keymap('n', 'gss')
  child.api.nvim_del_keymap('x', 'gs')

  load_module({ sort = { prefix = '' } })
  make_mappings('sort', { textobject = 'cs', line = 'css', selection = 'cs' })

  validate_edit1d('c, a, b', 0, { 'cs$' }, 'a, b, c', 0)
  validate_edit1d('  c, a, b  ', 0, { 'css' }, '  a, b, c  ', 2)
  validate_edit1d('(c, a, b)', 0, { 'vi)', 'cs' }, '(a, b, c)', 1)
end

T['Sort']["respects 'selection=exclusive'"] = function()
  child.lua([[vim.keymap.set('o', 'ie', function() vim.cmd('normal! \22jll') end)]])
  child.o.selection = 'exclusive'

  validate_edit1d('(c, a, b)', 1, { 'gsi)' }, '(a, b, c)', 1)
  validate_edit({ 'bb', 'aa' }, { 1, 0 }, { 'gsip' }, { 'aa', 'bb' }, { 1, 0 })
  validate_edit({ 'xbax', 'yaby' }, { 1, 1 }, { 'gsie' }, { 'xabx', 'ybay' }, { 1, 1 })

  validate_edit1d('(c, a, b)', 1, { 'vi)', 'gs' }, '(a, b, c)', 1)
  validate_edit({ 'bb', 'aa' }, { 1, 0 }, { 'Vip', 'gs' }, { 'aa', 'bb' }, { 1, 0 })
  validate_edit({ 'xbax', 'yaby' }, { 1, 1 }, { '<C-v>jll', 'gs' }, { 'xabx', 'ybay' }, { 1, 1 })
end

T['Sort']["respects 'nomodifiable'"] = function()
  set_lines({ 'b, a' })
  set_cursor(1, 0)
  child.bo.modifiable = false
  type_keys('gs$')
  eq(get_lines(), { 'b, a' })
  eq(get_cursor(), { 1, 3 })
end

T['Sort']['does not trigger `TextYankPost` event'] = function()
  child.cmd('au TextYankPost * lua _G.been_here = true')
  -- Should also not block other events, like ModeChanged
  child.cmd('au ModeChanged * lua _G.n = (_G.n or 0) + 1')

  validate_edit1d('b, a', 0, { 'gs$' }, 'a, b', 0)

  eq(child.lua_get('_G.been_here'), vim.NIL)
  eq(child.lua_get('_G.n') >= 8, true)
  eq(child.o.eventignore, '')
end

T['Sort']['respects `vim.{g,b}.minioperators_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minioperators_disable = true
    validate_edit1d('b, a', 0, { 'gs$' }, 'b, a', 3)
  end,
})

T['Sort']['respects `vim.b.minioperators_config`'] = function()
  -- Compare by the second character
  child.lua([[
    _G.sort_by_second = function(content)
      local compare_second = function(a, b) return a:sub(2, 2) < b:sub(2, 2) end
      return MiniOperators.default_sort_func(content, { compare_fun = compare_second })
    end
    vim.b.minioperators_config = { sort = { func = _G.sort_by_second } }
  ]])

  validate_edit({ 'ab', 'ba' }, { 1, 0 }, { 'gsip' }, { 'ba', 'ab' }, { 1, 0 })
end

return T
