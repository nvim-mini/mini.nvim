local helpers = dofile('tests/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('align', config) end
local unload_module = function() child.mini_unload('align') end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
local sleep = function(ms) helpers.sleep(ms, child) end
--stylua: ignore end

local set_config_steps = function(tbl)
  for key, value in pairs(tbl) do
    child.lua('MiniAlign.config.steps.' .. key .. ' = ' .. value)
  end
end

local set_config_opts = function(tbl)
  for key, value in pairs(tbl) do
    child.lua('MiniAlign.config.options.' .. key .. ' = ' .. vim.inspect(value))
  end
end

local validate_step = function(var_name, step_name)
  eq(child.lua_get(('type(%s)'):format(var_name)), 'table')

  local keys = child.lua_get(('vim.tbl_keys(%s)'):format(var_name))
  table.sort(keys)
  eq(keys, { 'action', 'name' })

  eq(child.lua_get(('type(%s.name)'):format(var_name)), 'string')
  if step_name ~= nil then eq(child.lua_get(('%s.name'):format(var_name)), step_name) end

  eq(child.lua_get(('vim.is_callable(%s.action)'):format(var_name)), true)
end

local get_latest_message = function() return child.cmd_capture('1messages') end

local get_mode = function() return child.api.nvim_get_mode()['mode'] end

local eq_tostring = function(var_name1, var_name2)
  local cmd = string.format('tostring(%s) == tostring(%s)', var_name1, var_name2)
  eq(child.lua_get(cmd), true)
end

-- Time constants
local show_state_delay, error_message_force_delay = 1000, 500
local small_time = helpers.get_time_const(10)

-- Output test set
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
  eq(child.lua_get('type(_G.MiniAlign)'), 'table')
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniAlign.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniAlign.config.' .. field), value) end
  local expect_config_type = function(field, type_val)
    eq(child.lua_get('type(MiniAlign.config.' .. field .. ')'), type_val)
  end

  -- Check default values
  expect_config('mappings.start', 'ga')
  expect_config('mappings.start_with_preview', 'gA')

  expect_config_type('modifiers.s', 'function')
  expect_config_type('modifiers.j', 'function')
  expect_config_type('modifiers.m', 'function')
  expect_config_type('modifiers.f', 'function')
  expect_config_type('modifiers.t', 'function')
  expect_config_type('modifiers.p', 'function')
  expect_config_type(
    string.format('modifiers["%s"]', child.api.nvim_replace_termcodes('<BS>', true, true, true)),
    'function'
  )
  expect_config_type('modifiers["="]', 'function')
  expect_config_type('modifiers[","]', 'function')
  expect_config_type('modifiers[" "]', 'function')

  expect_config('options.split_pattern', '')
  expect_config('options.justify_side', 'left')
  expect_config('options.merge_delimiter', '')

  expect_config('steps.pre_split', {})
  expect_config('steps.split', vim.NIL)
  expect_config('steps.pre_justify', {})
  expect_config('steps.justify', vim.NIL)
  expect_config('steps.pre_merge', {})
  expect_config('steps.merge', vim.NIL)

  expect_config('silent', false)
end

T['setup()']['respects `config` argument'] = function()
  unload_module()
  load_module({ options = { justify_side = 'center' } })
  eq(child.lua_get('MiniAlign.config.options.justify_side'), 'center')
end

T['setup()']['validates `config` argument'] = function()
  unload_module()

  local expect_config_error = function(config, name, target_type)
    expect.error(function() load_module(config) end, vim.pesc(name) .. '.*' .. vim.pesc(target_type))
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ mappings = 'a' }, 'mappings', 'table')
  expect_config_error({ mappings = { start = 1 } }, 'mappings.start', 'string')
  expect_config_error({ mappings = { start_with_preview = 1 } }, 'mappings.start_with_preview', 'string')
  expect_config_error({ modifiers = 'a' }, 'modifiers', 'table')
  expect_config_error({ modifiers = { x = 1 } }, 'modifiers["x"]', 'callable')
  expect_config_error({ options = 'a' }, 'options', 'table')
  expect_config_error({ steps = { pre_split = 1 } }, 'steps.pre_split', 'array of steps')
  expect_config_error({ steps = { split = 1 } }, 'steps.split', 'step')
  expect_config_error({ steps = { pre_justify = 1 } }, 'steps.pre_justify', 'array of steps')
  expect_config_error({ steps = { justify = 1 } }, 'steps.justify', 'step')
  expect_config_error({ steps = { pre_merge = 1 } }, 'steps.pre_merge', 'array of steps')
  expect_config_error({ steps = { merge = 1 } }, 'steps.merge', 'step')
  expect_config_error({ silent = 'a' }, 'silent', 'boolean')
end

T['setup()']['properly handles `config.mappings`'] = function()
  local has_map = function(lhs, pattern) return child.cmd_capture('xmap ' .. lhs):find(pattern) ~= nil end
  eq(has_map('ga', 'Align'), true)

  unload_module()
  child.api.nvim_del_keymap('x', 'ga')

  -- Supplying empty string should mean "don't create keymap"
  load_module({ mappings = { start = '' } })
  eq(has_map('ga', 'Align'), false)
end

local validate_align_strings = function(input_strings, opts, ref_strings, steps)
  local output = child.lua_get('MiniAlign.align_strings(...)', { input_strings, opts or {}, steps or {} })
  eq(output, ref_strings)
end

T['align_strings()'] = new_set()

T['align_strings()']['works'] = function()
  validate_align_strings({ 'a=b', 'aa=b' }, { split_pattern = '=' }, { 'a =b', 'aa=b' })
end

T['align_strings()']['validates `strings` argument'] = function()
  expect.error(function() child.lua([[MiniAlign.align_strings({'a', 1})]]) end, 'string')
  expect.error(function() child.lua([[MiniAlign.align_strings('a')]]) end, 'array')
end

T['align_strings()']['respects `strings` argument'] = function()
  validate_align_strings({ 'aaa=b', 'aa=b' }, { split_pattern = '=' }, { 'aaa=b', 'aa =b' })
end

T['align_strings()']['respects `opts` argument'] = function()
  -- Should take default values from `MiniAlign.config.options`
  child.lua([[MiniAlign.config.options.test = 'xxx']])
  child.lua([[ MiniAlign.config.steps.pre_split = {
    MiniAlign.new_step('test', function(strings, opts) strings[1] = opts.test end)
  }]])
  eq(child.lua_get([[MiniAlign.align_strings({ 'a=b', 'aa=b' }, { split_pattern = '=' }, {})]]), { 'xxx', 'aa=b' })
end

T['align_strings()']['respects `opts.split_pattern`'] = function()
  -- Single string
  validate_align_strings({ 'a,b', 'aa,b' }, { split_pattern = ',' }, { 'a ,b', 'aa,b' })

  -- Array of strings (should be recycled)
  validate_align_strings(
    { 'a,b=c,d=e,', 'aa,bb=cc,dd=ee,' },
    { split_pattern = { ',', '=' } },
    { 'a ,b =c ,d =e ,', 'aa,bb=cc,dd=ee,' }
  )
end

T['align_strings()']['respects `opts.justify_side` argument'] = function()
  -- Single string
  --stylua: ignore start
  validate_align_strings({ 'a=b', 'aaa=b' }, { split_pattern = '=', justify_side = 'left' },   { 'a  =b', 'aaa=b' })
  validate_align_strings({ 'a=b', 'aaa=b' }, { split_pattern = '=', justify_side = 'center' }, { ' a =b', 'aaa=b' })
  validate_align_strings({ 'a=b', 'aaa=b' }, { split_pattern = '=', justify_side = 'right' },  { '  a=b', 'aaa=b' })
  validate_align_strings({ 'a=b', 'aaa=b' }, { split_pattern = '=', justify_side = 'none' },   { 'a=b',   'aaa=b' })
  --stylua: ignore end

  -- Array of strings (should be recycled)
  validate_align_strings(
    { 'a=b=c=d=e', 'aaa  =bbb  =ccc  =ddd  =eee' },
    { split_pattern = '%s*=', justify_side = { 'left', 'center', 'right' } },
    -- Part resulted from separator is treated the same as any other part
    { 'a   =   b=   c   =d   =   e', 'aaa  =bbb  =ccc  =ddd  =eee' }
  )
end

T['align_strings()']['respects `opts.merge_delimiter` argument'] = function()
  -- Single string
  validate_align_strings({ 'a=b' }, { split_pattern = '=', merge_delimiter = '-' }, { 'a-=-b' })

  -- Array of strings (should be recycled)
  validate_align_strings(
    { 'a=b=c=' },
    { split_pattern = '=', merge_delimiter = { '-', '!' } },
    -- Part resulted from separator is treated the same as any other part
    { 'a-=!b-=!c-=' }
  )
end

T['align_strings()']['same `opts` is used for all steps'] = function()
  -- So that it can be used by steps to pass information to later steps
  set_config_steps({
    pre_split = [[{ MiniAlign.new_step('sss', function(strings, opts) opts.sss = 'sss' end) }]],
    merge = [[MiniAlign.new_step('mmm', function(parts, opts) return { opts.sss } end)]],
  })
  validate_align_strings({ 'a=b' }, { split_pattern = '=' }, { 'sss' })
end

T['align_strings()']['validates `steps` argument'] = function()
  -- `split_pattern` is `''` by default but it is needed for `align_strings()`
  set_config_opts({ split_pattern = '=' })

  local validate = function(steps_str, error_pattern)
    expect.error(function()
      local cmd = string.format([[MiniAlign.align_strings({'a=b', 'aa=b'}, {}, %s)]], steps_str)
      child.lua(cmd)
    end, error_pattern)
  end

  validate([[{ pre_split = 1 }]], 'pre_split.*array of steps')
  validate([[{ pre_split = { function() end } }]], 'pre_split.*array of steps')

  validate([[{ split = 1 }]], 'split.*step')
  validate([[{ split = function() end }]], 'split.*step')

  validate([[{ pre_justify = 1 }]], 'pre_justify.*array of steps')
  validate([[{ pre_justify = { function() end } }]], 'pre_justify.*array of steps')

  validate([[{ justify = 1 }]], 'justify.*step')
  validate([[{ justify = function() end }]], 'justify.*step')

  validate([[{ pre_merge = 1 }]], 'pre_merge.*array of steps')
  validate([[{ pre_merge = { function() end } }]], 'pre_merge.*array of steps')

  validate([[{ merge = 1 }]], 'merge.*step')
  validate([[{ merge = function() end }]], 'merge.*step')
end

T['align_strings()']['respects `steps.pre_split` argument'] = function()
  set_config_opts({ split_pattern = '=' })
  local step_str, cmd

  -- Array of steps
  step_str = [[MiniAlign.new_step('tmp', function(strings) strings[1] = 'a=b' end)]]
  cmd = string.format([[MiniAlign.align_strings({ 'aaa=b', 'aa=b' }, {}, { pre_split = { %s } })]], step_str)
  eq(child.lua_get(cmd), { 'a =b', 'aa=b' })

  -- Should validate that step correctly modified in place
  step_str = [[MiniAlign.new_step('tmp', function(strings) strings[1] = 1 end)]]
  cmd = string.format([[MiniAlign.align_strings({ 'a=b', 'aa=b' }, {}, { pre_split = { %s } })]], step_str)
  expect.error(function() child.lua(cmd) end, 'Step `tmp` of `pre_split` should preserve structure of `strings`.')

  -- Uses `MiniAlign.config.steps` as default
  set_config_steps({ pre_split = [[{ MiniAlign.new_step('tmp', function(strings) strings[1] = 'a=b' end) }]] })
  validate_align_strings({ 'aaa=b', 'aa=b' }, { split_pattern = '=' }, { 'a =b', 'aa=b' })

  -- Is called with `opts`
  step_str = [[MiniAlign.new_step('tmp', function(strings, opts) strings[1] = opts.tmp end)]]
  cmd =
    string.format([[MiniAlign.align_strings({ 'aaa=b', 'aa=b' }, { tmp = 'xxx' }, { pre_split = { %s } })]], step_str)
  eq(child.lua_get(cmd), { 'xxx', 'aa=b' })
end

T['align_strings()']['respects `steps.split` argument'] = function()
  local step_str, cmd

  -- Action output should be parts or convertible to it.
  step_str = [[MiniAlign.new_step('tmp', function(strings) return { { 'a', 'b' }, {'aa', 'b'} } end)]]
  cmd = string.format([[MiniAlign.align_strings({ 'a=b', 'aa=b' }, {}, { split = %s })]], step_str)
  eq(child.lua_get(cmd), { 'a b', 'aab' })

  step_str =
    [[MiniAlign.new_step('tmp', function(strings) return MiniAlign.as_parts({ { 'a', 'b' }, {'aa', 'b'} }) end)]]
  cmd = string.format([[MiniAlign.align_strings({ 'a=b', 'aa=b' }, {}, { split = %s })]], step_str)
  eq(child.lua_get(cmd), { 'a b', 'aab' })

  -- Uses `MiniAlign.config.steps` as default
  set_config_steps({
    split = [[MiniAlign.new_step('tmp', function(strings) return MiniAlign.as_parts({ { 'a', 'b' }, {'aa', 'b'} }) end)]],
  })
  validate_align_strings({ 'a,b', 'aa,b' }, {}, { 'a b', 'aab' })

  -- Should validate that step's output is convertible to parts
  step_str = [[MiniAlign.new_step('tmp', function(strings) return { { 'a', 1 }, {'aa', 'b'} } end)]]
  cmd = string.format([[MiniAlign.align_strings({ 'a=b', 'aa=b' }, {}, { split = %s })]], step_str)
  expect.error(function() child.lua(cmd) end, 'convertible to parts')

  -- Is called with `opts`
  step_str = [[MiniAlign.new_step('tmp', function(strings, opts) return MiniAlign.as_parts(opts.tmp) end)]]
  cmd = string.format([[MiniAlign.align_strings({ 'a=b', 'aa=b' }, { tmp = { { 'xxx' } } }, { split = %s })]], step_str)
  eq(child.lua_get(cmd), { 'xxx' })
end

T['align_strings()']['respects `steps.pre_justify` argument'] = function()
  set_config_opts({ split_pattern = '=' })
  local step_str, cmd

  -- Array of steps
  step_str = [[MiniAlign.new_step('tmp', function(parts) parts[1][1] = 'xxx' end)]]
  cmd = string.format([[MiniAlign.align_strings({ 'aaa=b', 'aa=b' }, {}, { pre_justify = { %s } })]], step_str)
  eq(child.lua_get(cmd), { 'xxx=b', 'aa =b' })

  -- Should validate that step correctly modified in place
  step_str = [[MiniAlign.new_step('tmp', function(parts) parts[1][1] = 1 end)]]
  cmd = string.format([[MiniAlign.align_strings({ 'a=b', 'aa=b' }, {}, { pre_justify = { %s } })]], step_str)
  local ref_text = 'Step `tmp` of `pre_justify` should preserve structure of `parts`. See `:h MiniAlign.as_parts()`.'
  expect.error(function() child.lua(cmd) end, vim.pesc(ref_text))

  -- Uses `MiniAlign.config.steps` as default
  set_config_steps({ pre_justify = [[{ MiniAlign.new_step('tmp', function(parts) parts[1][1] = 'xxx' end) }]] })
  validate_align_strings({ 'aaa=b', 'aa=b' }, { split_pattern = '=' }, { 'xxx=b', 'aa =b' })

  -- Is called with `opts`
  step_str = [[MiniAlign.new_step('tmp', function(parts, opts) parts[1][1] = opts.tmp end)]]
  cmd =
    string.format([[MiniAlign.align_strings({ 'aaa=b', 'aa=b' }, { tmp = 'xxx' }, { pre_justify = { %s } })]], step_str)
  eq(child.lua_get(cmd), { 'xxx=b', 'aa =b' })
end

T['align_strings()']['respects `steps.justify` argument'] = function()
  set_config_opts({ split_pattern = '=' })
  local step_str, cmd

  -- Action should modify parts in place.
  step_str = [[MiniAlign.new_step('tmp', function(parts) parts[1][1] = 'xxx' end)]]
  cmd = string.format([[MiniAlign.align_strings({ 'a=b', 'aa=b' }, {}, { justify = %s })]], step_str)
  eq(child.lua_get(cmd), { 'xxx=b', 'aa=b' })

  -- Uses `MiniAlign.config.steps` as default
  set_config_steps({
    justify = [[MiniAlign.new_step('tmp', function(parts) parts[1][1] = 'xxx' end)]],
  })
  validate_align_strings({ 'a=b', 'aa=b' }, { split_pattern = '=' }, { 'xxx=b', 'aa=b' })

  -- Should validate that step correctly modified in place
  step_str = [[MiniAlign.new_step('tmp', function(parts) parts[1][1] = 1 end)]]
  cmd = string.format([[MiniAlign.align_strings({ 'a=b', 'aa=b' }, {}, { justify = %s })]], step_str)
  local ref_text = 'Step `tmp` of `justify` should preserve structure of `parts`. See `:h MiniAlign.as_parts()`.'
  expect.error(function() child.lua(cmd) end, vim.pesc(ref_text))

  -- Is called with `opts`
  step_str = [[MiniAlign.new_step('tmp', function(parts, opts) parts[1][1] = opts.tmp end)]]
  cmd = string.format([[MiniAlign.align_strings({ 'a=b', 'aa=b' }, { tmp = 'xxx' }, { justify = %s })]], step_str)
  eq(child.lua_get(cmd), { 'xxx=b', 'aa=b' })
end

T['align_strings()']['respects `steps.pre_merge` argument'] = function()
  set_config_opts({ split_pattern = '=' })
  local step_str, cmd

  -- Array of steps
  step_str = [[MiniAlign.new_step('tmp', function(parts) parts[1][1] = 'xxx' end)]]
  cmd = string.format([[MiniAlign.align_strings({ 'aaa=b', 'aa=b' }, {}, { pre_merge = { %s } })]], step_str)
  eq(child.lua_get(cmd), { 'xxx=b', 'aa =b' })

  -- Should validate that step correctly modified in place
  step_str = [[MiniAlign.new_step('tmp', function(parts) parts[1][1] = 1 end)]]
  cmd = string.format([[MiniAlign.align_strings({ 'a=b', 'aa=b' }, {}, { pre_merge = { %s } })]], step_str)
  local ref_text = 'Step `tmp` of `pre_merge` should preserve structure of `parts`. See `:h MiniAlign.as_parts()`.'
  expect.error(function() child.lua(cmd) end, vim.pesc(ref_text))

  -- Uses `MiniAlign.config.steps` as default
  set_config_steps({ pre_merge = [[{ MiniAlign.new_step('tmp', function(parts) parts[1][1] = 'xxx' end) }]] })
  validate_align_strings({ 'aaa=b', 'aa=b' }, { split_pattern = '=' }, { 'xxx=b', 'aa =b' })

  -- Is called with `opts`
  step_str = [[MiniAlign.new_step('tmp', function(parts, opts) parts[1][1] = opts.tmp end)]]
  cmd =
    string.format([[MiniAlign.align_strings({ 'aaa=b', 'aa=b' }, { tmp = 'xxx' }, { pre_merge = { %s } })]], step_str)
  eq(child.lua_get(cmd), { 'xxx=b', 'aa =b' })
end

T['align_strings()']['respects `steps.merge` argument'] = function()
  set_config_opts({ split_pattern = '=' })
  local step_str, cmd

  -- Action should return array of strings.
  step_str = [[MiniAlign.new_step('tmp', function(parts) return { 'xxx' } end)]]
  cmd = string.format([[MiniAlign.align_strings({ 'a=b', 'aa=b' }, {}, { merge = %s })]], step_str)
  eq(child.lua_get(cmd), { 'xxx' })

  -- Uses `MiniAlign.config.steps` as default
  set_config_steps({ merge = [[MiniAlign.new_step('tmp', function(parts) return { 'xxx' } end)]] })
  validate_align_strings({ 'a=b' }, { split_pattern = '=' }, { 'xxx' })

  -- Should validate that output is an array of strings
  step_str = [[MiniAlign.new_step('tmp', function(parts) return { 'a', 1 } end)]]
  cmd = string.format([[MiniAlign.align_strings({ 'a=b', 'aa=b' }, {}, { merge = %s })]], step_str)
  expect.error(function() child.lua(cmd) end, vim.pesc('Output of `merge` step should be array of strings.'))

  -- Is called with `opts`
  step_str = [[MiniAlign.new_step('tmp', function(parts, opts) return { opts.tmp } end)]]
  cmd = string.format([[MiniAlign.align_strings({ 'a=b', 'aa=b' }, { tmp = 'xxx' }, { merge = %s })]], step_str)
  eq(child.lua_get(cmd), { 'xxx' })
end

T['align_strings()']['works with multibyte characters'] = function()
  validate_align_strings(
    { 'ыффццц', 'ыыыффц' },
    { split_pattern = 'ф', justify_side = 'center', merge_delimiter = 'ю' },
    { ' ы юфюфюццц', 'ыыыюфюфю ц' }
  )
end

T['align_strings()']['works in edge cases'] = function()
  validate_align_strings({}, {}, {})
  validate_align_strings({ '' }, {}, { '' })
  validate_align_strings({ '', '' }, {}, { '', '' })
  validate_align_strings({ '', ' ' }, {}, { '', ' ' })
end

T['align_strings()']['does not affect input array'] = function()
  child.lua([[strings = { 'a=b', 'aa=b' }]])
  child.lua([[pre_split = { MiniAlign.new_step('aaa', function(s, _) s[1] = 'xxx' end) }]])
  child.lua([[MiniAlign.align_strings(strings, { split_pattern = '=' }, { pre_split = pre_split })]])
  eq(child.lua_get('strings'), { 'a=b', 'aa=b' })
end

T['align_strings()']['respects `vim.b.minialign_config`'] = function()
  child.b.minialign_config = { options = { split_pattern = '=' } }
  validate_align_strings({ 'a=b', 'aa=b' }, {}, { 'a =b', 'aa=b' })

  -- Should take precedence over global cofnfig
  set_config_opts({ split_pattern = ',' })
  validate_align_strings({ 'a=b', 'aa=b' }, {}, { 'a =b', 'aa=b' })
end

local is_parts = function(var_name)
  local cmd = string.format('getmetatable(%s).class', var_name)
  eq(child.lua_get(cmd), 'parts')
end

T['as_parts()'] = new_set()

T['as_parts()']['works'] = function()
  child.lua([[parts = MiniAlign.as_parts({ { 'a', 'b' }, { 'c' } })]])
  eq(child.lua_get('type(parts.get_dims)'), 'function')
end

T['as_parts()']['validates arguments'] = function()
  local validate = function(input_str, err_pattern)
    expect.error(function() child.lua('MiniAlign.as_parts(' .. input_str .. ')') end, err_pattern)
  end

  validate('', 'Input of `as_parts%(%)` should be table')
  validate('1', 'table')
  validate([[{ 'a' }]], 'Input of `as_parts%(%)` values should be an array of strings')
  validate([[{ { 1 } }]], 'array of strings')
  validate([[{ { 'a' }, 'a' }]], 'array of strings')
end

T['as_parts()']['works with empty table'] = function()
  -- Empty parts
  child.lua('empty = MiniAlign.as_parts({})')
  is_parts('empty')

  -- All methods should work
  local validate_method = function(method_call, output, ...)
    child.lua('empty = MiniAlign.as_parts({})')
    local cmd = string.format('empty.%s', method_call)
    if output ~= nil then
      eq(child.lua_get(cmd, { ... }), output)
    else
      child.lua(cmd, { ... })
      eq(child.lua_get('empty'), {})
    end
  end

  validate_method([[apply_inplace(function(s) return 'a' end)]])
  validate_method('group()')
  validate_method('pair()')
  validate_method('trim()')

  validate_method('apply(function(s) return 1 end)', {})
  validate_method('get_dims()', { row = 0, col = 0 })
  validate_method('slice_col(1)', {})
  validate_method('slice_row(1)', {})
end

T['as_parts()']['`apply()` method'] = function()
  child.lua([[parts = MiniAlign.as_parts({ { 'a', 'b' }, { 'c' } })]])
  eq(
    child.lua_get('parts.apply(function(x, data) return x .. data.row .. data.col end)'),
    { { 'a11', 'b12' }, { 'c21' } }
  )
end

T['as_parts()']['`apply_inplace()` method'] = function()
  child.lua([[parts = MiniAlign.as_parts({ { 'a', 'b' }, { 'c' } })]])
  child.lua('new_parts = parts.apply_inplace(function(x, data) return x .. data.row .. data.col end)')
  eq(child.lua_get('parts'), { { 'a11', 'b12' }, { 'c21' } })

  -- Should return itself to enable chaining
  eq_tostring('parts', 'new_parts')
end

T['as_parts()']['`get_dims()` method'] = function()
  local validate = function(arr2d_str, dims)
    local cmd = string.format('MiniAlign.as_parts(%s).get_dims()', arr2d_str)
    eq(child.lua_get(cmd), dims)
  end

  validate([[{ { 'a' } }]], { row = 1, col = 1 })
  validate([[{ { 'a', 'b' } }]], { row = 1, col = 2 })
  validate([[{ { 'a', 'b' }, { 'c' } }]], { row = 2, col = 2 })
  validate([[{ { 'a', 'b' }, { 'c', 'd', 'e' } }]], { row = 2, col = 3 })
  validate([[{}]], { row = 0, col = 0 })
end

local validate_parts_group = function(arr2d_str, mask_str, output, direction)
  child.lua(('parts = MiniAlign.as_parts(%s)'):format(arr2d_str))
  direction = direction == nil and '' or (', ' .. vim.inspect(direction))
  child.lua(('new_parts = parts.group(%s%s)'):format(mask_str, direction))
  eq(child.lua_get('parts'), output)

  -- Should return itself to enable chaining
  eq_tostring('parts', 'new_parts')
end

T['as_parts()']['`group()` method'] = new_set()

T['as_parts()']['`group()` method']['works'] = function()
  validate_parts_group(
    [[{ { 'a', 'b', 'c' }, { 'd' } }]],
    '{ { false, false, true }, { true } }',
    { { 'abc' }, { 'd' } }
  )
end

T['as_parts()']['`group()` method']['respects `mask` argument'] = function()
  local arr2d_str

  arr2d_str = [[{ { 'a', 'b' } }]]
  validate_parts_group(arr2d_str, '{ { false, false } }', { { 'ab' } })
  validate_parts_group(arr2d_str, '{ { false, true } }', { { 'ab' } })
  validate_parts_group(arr2d_str, '{ { true, false } }', { { 'a', 'b' } })
  validate_parts_group(arr2d_str, '{ { true, true } }', { { 'a', 'b' } })

  arr2d_str = [[{ { 'a', 'b' }, { 'c', 'd', 'e' } }]]
  validate_parts_group(arr2d_str, '{ { false, true }, { true, false, true } }', { { 'ab' }, { 'c', 'de' } })

  -- Default direction is 'left'
  arr2d_str = [[{ { 'a', 'b', 'c', 'd' } }]]
  validate_parts_group(arr2d_str, '{ { false, true, false, false } }', { { 'ab', 'cd' } })
end

T['as_parts()']['`group()` method']['respects `direction` argument'] = function()
  local validate = function(...)
    local dots = { ... }
    table.insert(dots, 'right')
    validate_parts_group(unpack(dots))
  end

  local arr2d_str

  arr2d_str = [[{ { 'a', 'b' } }]]
  validate(arr2d_str, '{ { false, false } }', { { 'ab' } })
  validate(arr2d_str, '{ { false, true } }', { { 'a', 'b' } })
  validate(arr2d_str, '{ { true, false } }', { { 'ab' } })
  validate(arr2d_str, '{ { true, true } }', { { 'a', 'b' } })

  arr2d_str = [[{ { 'a', 'b' }, { 'c', 'd', 'e' } }]]
  validate(arr2d_str, '{ { false, true }, { true, false, true } }', { { 'a', 'b' }, { 'cd', 'e' } })

  -- Should differ from default 'left' direction
  arr2d_str = [[{ { 'a', 'b', 'c', 'd' } }]]
  validate(arr2d_str, '{ { false, true, false, false } }', { { 'a', 'bcd' } })
end

T['as_parts()']['`pair()` method'] = new_set()

T['as_parts()']['`pair()` method']['works'] = function()
  child.lua([[parts = MiniAlign.as_parts({ { 'a' }, { 'b', 'c' }, { 'd', 'e', 'f' } })]])
  child.lua('new_parts = parts.pair()')
  eq(child.lua_get('parts'), { { 'a' }, { 'bc' }, { 'de', 'f' } })

  -- Should return itself to enable chaining
  eq_tostring('parts', 'new_parts')
end

T['as_parts()']['`pair()` method']['respects `direction` argument'] = function()
  child.lua([[parts = MiniAlign.as_parts({ { 'a' }, { 'b', 'c' }, { 'd', 'e', 'f' } })]])
  child.lua([[parts.pair('right')]])
  eq(child.lua_get('parts'), { { 'a' }, { 'bc' }, { 'd', 'ef' } })
end

T['as_parts()']['`slice_col()` method'] = function()
  child.lua([[parts = MiniAlign.as_parts({ { 'a' }, { 'b', 'c' }, { 'd' } })]])

  eq(child.lua_get('parts.slice_col(0)'), {})
  eq(child.lua_get('parts.slice_col(1)'), { 'a', 'b', 'd' })
  -- `slice_col()` may not return array (table with only 1, ..., n keys)
  eq(child.lua_get([[vim.deep_equal(parts.slice_col(2), { [2] = 'c' })]]), true)
  eq(child.lua_get('parts.slice_col(3)'), {})
end

T['as_parts()']['`slice_row()` method'] = function()
  child.lua([[parts = MiniAlign.as_parts({ { 'a' }, { 'b', 'c' } })]])

  eq(child.lua_get('parts.slice_row(0)'), {})
  eq(child.lua_get('parts.slice_row(1)'), { 'a' })
  eq(child.lua_get('parts.slice_row(2)'), { 'b', 'c' })
  eq(child.lua_get('parts.slice_col(3)'), {})
end

T['as_parts()']['`trim()` method'] = new_set()

T['as_parts()']['`trim()` method']['works'] = function()
  child.lua([[parts = MiniAlign.as_parts({ { ' a ', ' b ', ' c', 'd ', 'e' }, { '  f ' } })]])
  child.lua('new_parts = parts.trim()')
  -- By default trims from both directions and keeps indentation (left
  -- whitespace of every first row string)
  eq(child.lua_get('parts'), { { ' a', 'b', 'c', 'd', 'e' }, { '  f' } })

  -- Should return itself to enable chaining
  eq_tostring('parts', 'new_parts')
end

T['as_parts()']['`trim()` method']['validates arguments'] = function()
  child.lua([[parts = MiniAlign.as_parts({ { ' a ' } })]])
  local err_pattern

  -- `direction`
  err_pattern = '`direction` should be one of "both", "left", "none", "right"'
  expect.error(function() child.lua([[parts.trim(1)]]) end, err_pattern)
  expect.error(function() child.lua([[parts.trim('a')]]) end, err_pattern)

  -- `indent`
  err_pattern = '`indent` should be one of "high", "keep", "low", "remove"'
  expect.error(function() child.lua([[parts.trim('both', 1)]]) end, err_pattern)
  expect.error(function() child.lua([[parts.trim('both', 'a')]]) end, err_pattern)
end

T['as_parts()']['`trim()` method']['respects `direction` argument'] = function()
  local validate = function(direction, output)
    child.lua([[parts = MiniAlign.as_parts({ { ' a ', ' b ', ' c', 'd ', 'e' }, { '  f ' } })]])
    child.lua(([[parts.trim('%s')]]):format(direction))
    eq(child.lua_get('parts'), output)
  end

  --stylua: ignore start
  validate('both',  { { ' a',  'b',   'c',  'd',  'e' }, { '  f' } })
  validate('left',  { { ' a ', 'b ',  'c',  'd ', 'e' }, { '  f ' } })
  validate('right', { { ' a',  ' b',  ' c', 'd',  'e' }, { '  f' } })
  validate('none',  { { ' a ', ' b ', ' c', 'd ', 'e' }, { '  f ' } })
  --stylua: ignore end
end

T['as_parts()']['`trim()` method']['respects `indent` argument'] = function()
  local validate = function(indent, output)
    child.lua([[parts = MiniAlign.as_parts({ { ' a ', ' b ' }, { '  c ', ' d ' } })]])
    child.lua(([[parts.trim('both', '%s')]]):format(indent))
    eq(child.lua_get('parts'), output)
  end

  --stylua: ignore start
  validate('keep',   { { ' a',  'b' }, { '  c', 'd' } })
  validate('low',    { { ' a',  'b' }, { ' c',  'd' } })
  validate('high',   { { '  a', 'b' }, { '  c', 'd' } })
  validate('remove', { { 'a',   'b' }, { 'c',   'd' } })
  --stylua: ignore end
end

T['new_step()'] = new_set()

T['new_step()']['works'] = function()
  child.lua([[step = MiniAlign.new_step('aaa', function() end)]])
  validate_step('step', 'aaa')

  -- Allows callable table as action
  child.lua([[action = setmetatable({}, { __call = function() end })]])
  child.lua([[step = MiniAlign.new_step('aaa', action)]])
  validate_step('step', 'aaa')
end

T['new_step()']['validates arguments'] = function()
  local validate = function(args_str, err_pattern)
    expect.error(function() child.lua('MiniAlign.new_step(' .. args_str .. ')') end, err_pattern)
  end

  validate([[1]], 'Step name should be string')
  validate([['aaa', 1]], 'Step action should be callable')
end

T['gen_step'] = new_set()

T['gen_step']['default_split()'] = new_set({
  hooks = { pre_case = function() set_config_steps({ split = [[MiniAlign.gen_step.default_split('test')]] }) end },
})

T['gen_step']['default_split()']['works'] = function()
  -- Returns proper step
  child.lua([[step = MiniAlign.gen_step.default_split()]])
  validate_step('step', 'split')

  -- Single string
  validate_align_strings({ 'a,b', 'aa,b' }, { split_pattern = ',' }, { 'a ,b', 'aa,b' })

  -- Array of strings (should be recycled)
  validate_align_strings({ 'a,b', 'aa,b' }, { split_pattern = { ',' } }, { 'a ,b', 'aa,b' })
  validate_align_strings(
    { 'a,b=c,d=e,', 'aa,bb=cc,dd=ee,' },
    { split_pattern = { ',', '=' } },
    { 'a ,b =c ,d =e ,', 'aa,bb=cc,dd=ee,' }
  )
end

T['gen_step']['default_split()']['verifies relevant options'] = function()
  local pat = 'Option `split_pattern`.*string or array of strings'
  expect.error(function() child.lua('MiniAlign.align_strings({ "a" }, { split_pattern = 1 }, {})') end, pat)
  pat = 'Option `split_exclude_patterns`.*array of strings'
  expect.error(function() child.lua('MiniAlign.align_strings({ "a" }, { split_exclude_patterns = 1 }, {})') end, pat)
end

T['gen_step']['default_split()']['allows split Lua pattern'] = function()
  set_config_opts({ split_pattern = '%s*=%s*', merge_delimiter = '-' })
  validate_align_strings({ 'a=b  =c=  d  =  e' }, {}, { 'a-=-b-  =-c-=  -d-  =  -e' })
end

T['gen_step']['default_split()']['verifies bad split pattern'] = function()
  local pat = vim.pesc('(mini.align) Pattern "%f[%s]" can not advance search.')
  expect.error(function() child.lua('MiniAlign.align_strings({ "a " }, { split_pattern = "%f[%s]" })') end, pat)
end

T['gen_step']['default_split()']['works with different number of output parts'] = function()
  set_config_opts({ split_pattern = ',', merge_delimiter = '-' })
  validate_align_strings({ 'a', 'b,', 'c,d' }, {}, { 'a', 'b-,', 'c-,-d' })
end

T['gen_step']['default_split()']['works with empty input strings'] = function()
  child.lua('step = MiniAlign.gen_step.default_split()')
  eq(
    child.lua_get([[step.action({ 'a=b', '', '=', '' }, { split_pattern = '=' })]]),
    { { 'a', '=', 'b' }, { '' }, { '', '=' }, { '' } }
  )
end

T['gen_step']['default_split()']['works with no split pattern found'] = function()
  set_config_opts({ split_pattern = ',', merge_delimiter = '-' })

  -- In some lines
  validate_align_strings({ 'a,b', 'a=b' }, { justify_side = 'center' }, { ' a -,-b', 'a=b' })

  -- In all lines
  validate_align_strings({ 'a=b', 'a=bb' }, {}, { 'a=b', 'a=bb' })
end

T['gen_step']['default_split()']['works with special split patterns'] = function()
  set_config_opts({ merge_delimiter = '-' })

  -- Treat `''` as no split pattern is found
  set_config_opts({ split_pattern = '' })
  validate_align_strings({ 'a=b', 'a=bbb' }, {}, { 'a=b', 'a=bbb' })

  -- Treat `'.'` as any character is a split
  set_config_opts({ split_pattern = '.' })
  validate_align_strings({ 'a=b', 'a=bbb' }, {}, { 'a-=-b', 'a-=-b-b-b' })

  -- Works with `^`
  set_config_opts({ split_pattern = '^.' })
  validate_align_strings({ 'a=b', 'a=bbb' }, {}, { 'a-=b', 'a-=bbb' })

  -- Works with `$`
  set_config_opts({ split_pattern = '.$' })
  validate_align_strings({ 'a=b', 'a=bbb' }, {}, { 'a=  -b', 'a=bb-b' })
end

T['gen_step']['default_split()']['respects `split_exclude_patterns` option'] = function()
  validate_align_strings(
    { [[a="=="'=='b=c]], 'a=b=c' },
    { split_pattern = '=', split_exclude_patterns = { [[".-"]], [['.-']] } },
    { [[a="=="'=='b=c]], 'a=b        =c' }
  )

  -- Split match should be ignored if any its edge is inside any forbidden span
  validate_align_strings(
    { 'a"<"=b<"=c', 'a<"=b' },
    { split_pattern = '<"=', split_exclude_patterns = { [[".-"]] } },
    { 'a"<"=b<"=c', 'a     <"=b' }
  )
end

T['gen_step']['default_split()']['works with special exclude patterns'] = function()
  local lines = { 'a=b', 'cc=d', 'eee=f' }
  local output_lines = { 'a=b', 'cc =d', 'eee=f' }

  -- Start of line
  validate_align_strings(lines, { split_pattern = '=', split_exclude_patterns = { '^a.*' } }, output_lines)

  -- End of line
  validate_align_strings(lines, { split_pattern = '=', split_exclude_patterns = { 'a.*$' } }, output_lines)

  -- Both start of line and end of line
  validate_align_strings(lines, { split_pattern = '=', split_exclude_patterns = { '^a.*$' } }, output_lines)
end

--stylua: ignore
T['gen_step']['default_split()']['matches inside forbidden spans do not affect split pattern recycling'] = function()
  validate_align_strings(
    { [[a,"b=b"=c,d]], 'aa,bb=cc,dd' },
    { split_pattern = { ',', '=' }, split_exclude_patterns = { [[".-"]] } },
    { [[a ,"b=b"=c ,d]], 'aa,bb   =cc,dd' }
  )
end

T['gen_step']['default_justify()'] = new_set({
  hooks = {
    pre_case = function() set_config_steps({ justify = [[MiniAlign.gen_step.default_justify('test')]] }) end,
  },
})

T['gen_step']['default_justify()']['works'] = function()
  -- Returns proper step
  child.lua([[step = MiniAlign.gen_step.default_justify()]])
  validate_step('step', 'justify')

  -- Single string
  set_config_opts({ split_pattern = '=' })

  --stylua: ignore start
  validate_align_strings({ 'a=b', 'aaa=b' }, { justify_side = 'left' },   { 'a  =b', 'aaa=b' })
  validate_align_strings({ 'a=b', 'aaa=b' }, { justify_side = 'center' }, { ' a =b', 'aaa=b' })
  validate_align_strings({ 'a=b', 'aaa=b' }, { justify_side = 'right' },  { '  a=b', 'aaa=b' })
  validate_align_strings({ 'a=b', 'aaa=b' }, { justify_side = 'none' },   { 'a=b',   'aaa=b' })
  --stylua: ignore end

  -- Array of strings (should be recycled)
  set_config_opts({ split_pattern = '%s*=' })
  validate_align_strings(
    { 'a=b=c=d=e', 'aaa  =bbb  =ccc  =ddd  =eee' },
    { justify_side = { 'left', 'center', 'right' } },
    -- Part resulted from separator is treated the same as any other part
    { 'a   =   b=   c   =d   =   e', 'aaa  =bbb  =ccc  =ddd  =eee' }
  )
end

T['gen_step']['default_justify()']['verifies relevant options'] = function()
  local pat = 'Option `justify_side`.*one of.*or array'
  expect.error(function() child.lua('MiniAlign.align_strings({ "a" }, { justify_side = 1 }, {})') end, pat)
end

T['gen_step']['default_justify()']['works with multibyte characters'] = function()
  set_config_opts({ split_pattern = '=' })

  --stylua: ignore start
  validate_align_strings({ 'ы=ю', 'ыыы=ююю' }, { justify_side = 'left' },   { 'ы  =ю',   'ыыы=ююю' })
  validate_align_strings({ 'ы=ю', 'ыыы=ююю' }, { justify_side = 'center' }, { ' ы = ю',  'ыыы=ююю' })
  validate_align_strings({ 'ы=ю', 'ыыы=ююю' }, { justify_side = 'right' },  { '  ы=  ю', 'ыыы=ююю' })
  validate_align_strings({ 'ы=ю', 'ыыы=ююю' }, { justify_side = 'none' },   { 'ы=ю',     'ыыы=ююю' })
  --stylua: ignore end
end

T['gen_step']['default_justify()']['does not add trailing whitespace'] = function()
  set_config_opts({ split_pattern = '=' })

  --stylua: ignore start
  validate_align_strings({ 'a=b', '', 'a=bbb' }, { justify_side = 'left' },   { 'a=b',   '', 'a=bbb' })
  validate_align_strings({ 'a=b', '', 'a=bbb' }, { justify_side = 'center' }, { 'a= b',  '', 'a=bbb' })
  validate_align_strings({ 'a=b', '', 'a=bbb' }, { justify_side = 'right' },  { 'a=  b', '', 'a=bbb' })
  validate_align_strings({ 'a=b', '', 'a=bbb' }, { justify_side = 'none' },   { 'a=b',   '', 'a=bbb' })
  --stylua: ignore end

  -- Also shouldn't add trailing whitespace in multicharacter split
  validate_align_strings({ 'aa==bb', 'c=' }, { split_pattern = '=+' }, { 'aa==bb', 'c =' })
end

T['gen_step']['default_justify()']['last row element width is ignored for left justify side'] = function()
  set_config_opts({ split_pattern = '=', justify_side = 'left' })

  -- It won't be padded so shouldn't contribute to column width
  validate_align_strings({ 'a=b', 'aa=b', 'aaaaa' }, {}, { 'a =b', 'aa=b', 'aaaaa' })
  validate_align_strings({ 'a=b=c', 'a=bb=c', 'a=bbbbb' }, {}, { 'a=b =c', 'a=bb=c', 'a=bbbbb' })
end

T['gen_step']['default_justify()']['prefers padding left for center justify side'] = function()
  set_config_opts({ split_pattern = '=', justify_side = 'center' })

  validate_align_strings({ 'a=b', 'aaaa=b' }, {}, { '  a =b', 'aaaa=b' })
end

T['gen_step']['default_justify()']['output step uses `opts.justify_offsets`'] = function()
  set_config_opts({ split_pattern = '=' })

  -- Using `opts.justify_offsets` allows to respect string prefixes but without
  -- processing them. So in this case output should be the same as with
  -- `{ '   a=b', '  a=b', 'a=b' }` and equal offsets (but without indents).
  validate_align_strings({ 'a=b', 'a=b', 'a=b' }, { justify_offsets = { 3, 2, 0 } }, { 'a=b', 'a =b', 'a   =b' })
end

T['gen_step']['default_merge()'] = new_set({
  hooks = {
    pre_case = function() set_config_steps({ merge = [[MiniAlign.gen_step.default_merge('test')]] }) end,
  },
})

T['gen_step']['default_merge()']['works'] = function()
  set_config_opts({ split_pattern = '=' })

  -- Returns proper step
  child.lua([[step = MiniAlign.gen_step.default_merge()]])
  validate_step('step', 'merge')

  -- Single string
  validate_align_strings({ 'a=b' }, { merge_delimiter = '-' }, { 'a-=-b' })

  -- Array of strings (should be recycled)
  validate_align_strings(
    { 'a=b=c=' },
    { merge_delimiter = { '-', '!' } },
    -- Part resulted from separator is treated the same as any other part
    { 'a-=!b-=!c-=' }
  )
end

T['gen_step']['default_merge()']['works in edge cases'] = function()
  validate_align_strings({}, {}, {})
  validate_align_strings({ '' }, {}, { '' })
  validate_align_strings({ '', '' }, {}, { '', '' })
  validate_align_strings({ '', ' ' }, {}, { '', ' ' })
end

T['gen_step']['default_merge()']['verifies relevant options'] = function()
  local pat = 'Option `merge_delimiter`.*string or array of strings'
  expect.error(function() child.lua('MiniAlign.align_strings({ "a" }, { merge_delimiter = 1 }, {})') end, pat)
end

T['gen_step']['default_merge()']['does not merge empty strings in parts'] = function()
  set_config_opts({ split_pattern = '=' })

  -- Shouldn't result into adding extra merge
  validate_align_strings({ 'a===b' }, { merge_delimiter = '-' }, { 'a-=-=-=-b' })
  validate_align_strings({ '=a' }, { merge_delimiter = '-' }, { '=-a' })
end

T['gen_step']['default_merge()']['preserves indentation with whitespace in merge delimmiter'] = function()
  set_config_opts({ split_pattern = '=' })

  -- Should not add whitespace to the first part if all of them are indent
  validate_align_strings({ ' =a=b', '  =c=d' }, { merge_delimiter = ' ' }, { '  = a = b', '  = c = d' })
  validate_align_strings({ ' =a=b', '=c=d' }, { merge_delimiter = ' ' }, { ' = a = b', ' = c = d' })
  validate_align_strings({ '=a=b', '=c=d' }, { merge_delimiter = ' ' }, { '= a = b', '= c = d' })

  validate_align_strings({ ' =a=b', '  =c=d' }, { merge_delimiter = ' _' }, { '  _= _a _= _b', '  _= _c _= _d' })

  validate_align_strings({ ' =a=b', 'x=c=d' }, { merge_delimiter = ' ' }, { '  = a = b', 'x = c = d' })

  child.o.tabstop = 2
  validate_align_strings({ '\t=a=b', '\t\t=c=d' }, { merge_delimiter = '\t' }, { '\t  =\ta\t=\tb', '\t\t=\tc\t=\td' })
  validate_align_strings({ '\t=a=b', '\t\t=c=d' }, { merge_delimiter = ' ' }, { '\t  = a = b', '\t\t= c = d' })
end

T['gen_step']['filter()'] = new_set()

T['gen_step']['filter()']['works'] = function()
  set_config_opts({ split_pattern = '=', justify_side = 'center' })

  set_config_steps({ pre_justify = [[{ MiniAlign.gen_step.filter('n == 1') }]] })
  validate_align_strings({ 'a=b=c', 'aaa=bbb=ccc' }, {}, { ' a =  b=c', 'aaa=bbb=ccc' })

  -- `nil` allowed as input
  eq(child.lua_get('MiniAlign.gen_step.filter()'), vim.NIL)
end

T['gen_step']['filter()']['validates input'] = function()
  local pat = '%(mini%.align%) "%(" is not a valid filter expression'
  expect.error(function() child.lua('MiniAlign.gen_step.filter("(")') end, pat)
end

T['gen_step']['filter()']['handles special input'] = function()
  -- `nil`
  eq(child.lua_get('MiniAlign.gen_step.filter()'), vim.NIL)

  -- `''` (treated as `true`, i.e. nothing is filtered out)
  set_config_steps({ pre_justify = [[{ MiniAlign.gen_step.filter('') }]] })
  set_config_opts({ split_pattern = '=' })
  validate_align_strings({ 'a=b=c', 'aaa=bbb=ccc' }, {}, { 'a  =b  =c', 'aaa=bbb=ccc' })
end

T['gen_step']['filter()']['allows special variables'] = function()
  set_config_opts({ split_pattern = '=' })
  local set = function(expr)
    set_config_steps({ pre_justify = ([[{ MiniAlign.gen_step.filter(%s) }]]):format(vim.inspect(expr)) })
  end

  --stylua:ignore start
  set('row == 2 or row == 3')
  validate_align_strings({ 'a=b=c', 'aa=bb=cc', 'aaa=bbb=ccc' }, {}, { 'a=b=c', 'aa =bb =cc', 'aaa=bbb=ccc' })

  set('row ~= ROW')
  validate_align_strings({ 'a=b=c', 'aa=bb=cc', 'aaa=bbb=ccc' }, {}, { 'a =b =c', 'aa=bb=cc', 'aaa=bbb=ccc' })

  set('col > 1')
  validate_align_strings({ 'a=b=c', 'aa=bb=cc', 'aaa=bbb=ccc' }, {}, { 'a=  b  =c', 'aa= bb =cc', 'aaa=bbb=ccc' })

  set('col >= COL - 1')
  validate_align_strings({ 'a=b=c', 'aa=bb=cc', 'aaa=bbb=ccc' }, {}, { 'a=b=    c', 'aa=bb=  cc', 'aaa=bbb=ccc' })
  --stylua:ignore end
end

T['gen_step']['filter()']['allows usage of global objects'] = function()
  set_config_steps({ pre_justify = [[{ MiniAlign.gen_step.filter('row ~= first_row') }]] })
  set_config_opts({ split_pattern = '=' })
  child.lua('_G.first_row = 1')
  validate_align_strings({ 'a=b=c', 'aa=bb=cc', 'aaa=bbb=ccc' }, {}, { 'a=b=c', 'aa =bb =cc', 'aaa=bbb=ccc' })
end

T['gen_step']['ignore_split()'] = new_set()

T['gen_step']['ignore_split()']['works'] = function()
  child.lua([[step = MiniAlign.gen_step.ignore_split()]])
  validate_step('step', 'ignore')

  -- With default arguments should ignore inside `"` and comments
  child.o.commentstring = '# %s'
  set_config_steps({ pre_split = [[{ MiniAlign.gen_step.ignore_split() }]] })
  validate_align_strings(
    { '# aaaa=b', 'a"====="=b', 'a=b' },
    { split_pattern = '=' },
    { '# aaaa=b', 'a"====="=b', 'a       =b' }
  )
end

T['gen_step']['ignore_split()']['validates input'] = function()
  local pat = 'Argument `patterns`.*array of strings'
  expect.error(function() child.lua('MiniAlign.gen_step.ignore_split("(")') end, pat)
  pat = 'Argument `exclude_comment`.*boolean'
  expect.error(function() child.lua('MiniAlign.gen_step.ignore_split({}, 1)') end, pat)
end

T['gen_step']['ignore_split()']['respects `patterns` argument'] = function()
  set_config_steps({ pre_split = [[{ MiniAlign.gen_step.ignore_split({ '*.-*' }) }]] })
  validate_align_strings({ 'a"="b', 'a*=*=b', 'a=b' }, { split_pattern = '=' }, { 'a"  ="b', 'a*=*=b', 'a   =b' })

  -- Shouldn't add duplicates
  child.lua([[test_step = MiniAlign.new_step(
    'test',
    function(strings, opts) _G.split_exclude_patterns = opts.split_exclude_patterns end
  )]])
  child.o.commentstring = '# %s'
  set_config_steps({ pre_split = [[{ MiniAlign.gen_step.ignore_split({ '*.-*', '".-"' }), test_step }]] })
  set_config_opts({ split_exclude_patterns = { '".-"' } })

  child.lua([[MiniAlign.align_strings({'a'})]])
  eq(child.lua_get('_G.split_exclude_patterns'), { '".-"', '*.-*', '# .*' })
end

T['gen_step']['ignore_split()']['respects `exclude_comment` argument'] = function()
  set_config_opts({ split_pattern = '=' })
  child.o.commentstring = '# %s'

  set_config_steps({ pre_split = [[{ MiniAlign.gen_step.ignore_split({}, true) }]] })
  validate_align_strings({ '# aaa=b', 'a=b', 'aa=b' }, {}, { '# aaa=b', 'a =b', 'aa=b' })

  set_config_steps({ pre_split = [[{ MiniAlign.gen_step.ignore_split({}, false) }]] })
  validate_align_strings({ '# aaa=b', 'a=b', 'aa=b' }, {}, { '# aaa=b', 'a    =b', 'aa   =b' })

  -- Should work with both `xxx%s` and `xxx%syyy` type of comments
  child.o.commentstring = '/ %s /'
  set_config_steps({ pre_split = [[{ MiniAlign.gen_step.ignore_split({}, true) }]] })
  validate_align_strings(
    { 'a/ = /=b/ = /=c', 'a=b=c', '/ == /' },
    {},
    { 'a/ = /=b/ = /=c', 'a     =b     =c', '/ == /' }
  )
end

T['gen_step']['pair()'] = new_set()

T['gen_step']['pair()']['works'] = function()
  set_config_steps({ pre_justify = [[{ MiniAlign.gen_step.pair() }]] })
  set_config_opts({ split_pattern = ',', justify_side = 'center' })

  eq(child.lua_get('MiniAlign.config.steps.pre_justify[1].name'), 'pair')

  validate_align_strings({ 'a,b,c', 'aaa,bbb,c' }, {}, { ' a,  b, c', 'aaa,bbb,c' })
end

T['gen_step']['pair()']['respects `direction` argument'] = function()
  set_config_opts({ split_pattern = ',', justify_side = 'center' })

  set_config_steps({ pre_justify = [[{ MiniAlign.gen_step.pair('left') }]] })
  validate_align_strings({ 'a,b,c', 'aaa,bbb,c' }, {}, { ' a,  b, c', 'aaa,bbb,c' })

  set_config_steps({ pre_justify = [[{ MiniAlign.gen_step.pair('right') }]] })
  validate_align_strings({ 'a,b,c', 'aaa,bbb,c' }, {}, { ' a  ,b ,c', 'aaa,bbb,c' })
end

T['gen_step']['trim()'] = new_set()

T['gen_step']['trim()']['works'] = function()
  set_config_steps({ pre_justify = [[{ MiniAlign.gen_step.trim() }]] })
  set_config_opts({ split_pattern = '=' })

  eq(child.lua_get('MiniAlign.config.steps.pre_justify[1].name'), 'trim')

  validate_align_strings({ ' a  = b  =  c = d', '  e = ' }, {}, { ' a =b=c=d', '  e=' })
end

T['gen_step']['trim()']['respects `direction` argument'] = function()
  set_config_opts({ split_pattern = '=' })
  local set = function(direction)
    set_config_steps({ pre_justify = ([[{ MiniAlign.gen_step.trim(%s) }]]):format(vim.inspect(direction)) })
  end

  set('both')
  validate_align_strings({ ' a =b = c=d' }, {}, { ' a=b=c=d' })

  set('left')
  validate_align_strings({ ' a =b = c=d' }, {}, { ' a =b =c=d' })

  set('right')
  validate_align_strings({ ' a =b = c=d' }, {}, { ' a=b= c=d' })
end

T['gen_step']['trim()']['respects `indent` argument'] = function()
  set_config_opts({ split_pattern = '=' })
  local set = function(indent)
    set_config_steps({ pre_justify = ([[{ MiniAlign.gen_step.trim('both', %s) }]]):format(vim.inspect(indent)) })
  end

  set('keep')
  validate_align_strings({ ' a ', '  b ' }, {}, { ' a', '  b' })

  set('low')
  validate_align_strings({ ' a ', '  b ' }, {}, { ' a', ' b' })

  set('high')
  validate_align_strings({ ' a ', '  b ' }, {}, { '  a', '  b' })

  set('remove')
  validate_align_strings({ ' a ', '  b ' }, {}, { 'a', 'b' })
end

-- Integration tests ==========================================================
local validate_keys = function(input_lines, keys, output_lines)
  set_lines(input_lines)
  set_cursor(1, 0)
  type_keys(keys)
  eq(get_lines(), output_lines)
end

T['Align'] = new_set()

T['Align']['works'] = function()
  -- Use neutral split pattern to avoid testing builtin modifiers
  validate_keys({ 'a_b', 'aaa_b' }, { 'Vj', 'ga', '_' }, { 'a  _b', 'aaa_b' })

  -- Allows non-split related modifiers
  validate_keys({ 'a_b', 'aaa_b' }, { 'V1j', 'ga', 'jc', '_' }, { ' a _b', 'aaa_b' })
end

T['Align']['works in Normal mode'] = function()
  -- Should accept any textobject or motion
  validate_keys({ 'a_b', 'aaa_b', '', 'aaaaa_b' }, { 'ga', 'Vip', '_' }, { 'a  _b', 'aaa_b', '', 'aaaaa_b' })
  eq(get_cursor(), { 1, 0 })

  validate_keys({ 'a_b', 'aaa_c' }, { 'ga', [[/_\zsc<CR>]], '_' }, { 'a  _b', 'aaa_c' })
end

T['Align']['allows dot-repeat'] = function()
  set_lines({ 'a_b', 'aaa_b', '', 'aaaaa_b', 'a_b' })
  set_cursor(1, 0)
  type_keys('ga', 'Vip', '_')
  eq(get_lines(), { 'a  _b', 'aaa_b', '', 'aaaaa_b', 'a_b' })

  set_cursor(4, 0)
  type_keys('.')
  eq(get_lines(), { 'a  _b', 'aaa_b', '', 'aaaaa_b', 'a    _b' })
end

T['Align']['works in Visual charwise mode'] = function()
  -- Should use visual selection to extract strings and correctly place result
  -- Should return to Normal mode after finish
  validate_keys({ 'a_b', 'aaa_b' }, { 'v', '1j4l', 'ga', '_' }, { 'a  _b', 'aaa_b' })
  eq(get_cursor(), { 2, 4 })
  eq(get_mode(), 'n')

  -- Respects offset of first line
  set_lines({ 'xx_xxa_b', 'a_b' })
  set_cursor(1, 5)
  type_keys('vj', 'ga', '_')
  eq(get_lines(), { 'xx_xxa_b', 'a     _b' })

  -- Allows using non-split related modifiers
  validate_keys({ 'a_b', 'aaa_b' }, { 'v', '1j4l', 'ga', 'jc', '_' }, { ' a _b', 'aaa_b' })

  -- Should align for second `_` because it is not inside selection
  validate_keys({ 'a_b_c', 'aaa_bbb_ccc' }, { 'v', '/bb_<CR>', 'ga', '_' }, { 'a  _b_c', 'aaa_bbb_ccc' })

  -- Can use `$` without `end_col out of bounds`
  validate_keys({ 'a_b', 'aaa_b' }, { 'v', '1j$', 'ga', '_' }, { 'a  _b', 'aaa_b' })
end

T['Align']['works in Visual linewise mode'] = function()
  validate_keys({ 'a_b_c', 'aaa_bbb_ccc' }, { 'V', 'ip', 'ga', '_' }, { 'a  _b  _c', 'aaa_bbb_ccc' })
  eq(get_mode(), 'n')

  -- Allows using non-split related modifiers
  validate_keys({ 'a_b', 'aaa_b' }, { 'V', '1j', 'ga', 'jc', '_' }, { ' a _b', 'aaa_b' })
end

T['Align']['works in Visual blockwise mode'] = function()
  validate_keys({ 'a_b_c', 'aaa_bbb_c' }, { '<C-v>', '1j3l', 'ga', '_' }, { 'a  _b_c', 'aaa_bbb_c' })
  eq(get_mode(), 'n')

  child.o.virtualedit = 'block'

  -- Selection goes over empty line (at start/middle/end of selection)
  validate_keys({ '', 'a_b_c', 'aaa_bbb_c' }, { '<C-v>', '2j3l', 'ga', '_' }, { '', 'a  _b_c', 'aaa_bbb_c' })
  validate_keys({ 'a_b_c', '', 'aaa_bbb_c' }, { '<C-v>', '2j3l', 'ga', '_' }, { 'a  _b_c', '', 'aaa_bbb_c' })
  validate_keys({ 'a_b_c', 'aaa_bbb_c', '' }, { '<C-v>', '2j3l', 'ga', '_' }, { 'a  _b_c', 'aaa_bbb_c', '' })

  -- Works when selection goes past the line (only right column, both columns)
  validate_keys({ 'a_b', 'aa_b', 'aaa_b' }, { '1l', '<C-v>', '2j2l', 'ga', '_' }, { 'a  _b', 'aa _b', 'aaa_b' })
  validate_keys({ 'a_b', 'aaa_b', 'aaaa_b' }, { '2j3l', '<C-v>', '2k2l', 'ga', '_' }, { 'a_b', 'aaa _b', 'aaaa_b' })

  -- Correctly works in presence of multibyte characters
  validate_keys({ 'ыы_ф', 'ыыы_ф' }, { '1l', '<C-v>', '1j3l', 'ga', '_' }, { 'ыы _ф', 'ыыы_ф' })

  -- Correctly selects in presence of wide characters
  validate_keys({ 'の', '_', 'a_' }, { '<C-v>2j', 'ga', '_' }, { 'の', ' _', 'a_' })
end

T['Align']['works independently with :normal command'] = function()
  -- Works for each line individually when running under :normal command
  validate_keys({ 'a   _b', 'aa  _b', 'aaa _b' }, { ':%normal ga_t_<CR>' }, { 'a_b', 'aa_b', 'aaa_b' })
  validate_keys({ 'a   _  b', 'aa  _  b', 'aaa _  b' }, { ':%normal ga_ A;<CR>' }, { 'a _ b;', 'aa _ b;', 'aaa _ b;' })
end

T['Align']['registers visual selection'] = function()
  set_lines({ 'a_b', 'aa_b', 'vvv', 'vvv' })

  -- Make preceding visual selection
  set_cursor(3, 0)
  type_keys('V', 'j', 'u')

  -- Align in Visual mode
  set_cursor(1, 0)
  type_keys('V', 'j', 'ga', '_')
  eq(get_lines(), { 'a _b', 'aa_b', 'vvv', 'vvv' })

  -- Verify that Visual selection got updated
  type_keys('gv')
  eq(get_mode(), 'V')
  eq(child.fn.getpos('v'), { 0, 1, 1, 0 })
end

T['Align']['works with different mapping'] = function()
  unload_module()
  child.api.nvim_del_keymap('n', 'ga')
  child.api.nvim_del_keymap('x', 'ga')
  load_module({ mappings = { start = 'gl' } })

  validate_keys({ 'a_b', 'aaa_b' }, { 'gl', 'Vj', '_' }, { 'a  _b', 'aaa_b' })
  validate_keys({ 'a_b', 'aaa_b' }, { 'Vj', 'gl', '_' }, { 'a  _b', 'aaa_b' })
end

T['Align']['works with multibyte characters'] = function()
  local before, after = { 'ыффцццф', 'ыыыффцф' }, { 'ы  ффцццф', 'ыыыффц  ф' }
  validate_keys(before, { 'Vj', 'ga', 'ф' }, after)
  validate_keys(before, { '<C-v>$j', 'ga', 'ф' }, after)
end

T['Align']['works with wide characters'] = function()
  -- Wide characters may or may not be designed to occupy more than a one cell
  -- NOTE: deliberately do not account for 'ambiwidth=double' option as it does
  -- not look reasonable (two cells for Cyrillic) and adds extra complexity
  local before, after = { 'ыыффццф', 'ыфのфцф' }, { 'ыыф  фццф', 'ы фのфц ф' }
  validate_keys(before, { 'Vj', 'ga', 'ф' }, after)
  validate_keys(before, { '<C-v>$j', 'ga', 'ф' }, after)
end

T['Align']['works with combining characters'] = function(mode)
  -- 0xCC 0x81 is the UTF-8 representation of U+0301 COMBINING ACUTE ACCENT. It
  -- is zero-width when combined with the preceding character.
  local before, after = { 'aá_e\xcc\x81e_', 'aa_e_' }, { 'aá_e\xcc\x81e_', 'aa_e _' }
  validate_keys(before, { 'Vj', 'ga', '_' }, after)
  validate_keys(before, { '<C-v>$j', 'ga', '_' }, after)
end

T['Align']['does not ask for modifier if `split_pattern` is not default'] = function()
  set_config_opts({ split_pattern = '_' })
  set_lines({ 'a_b', 'aa_b' })
  set_cursor(1, 0)
  type_keys('Vj', 'ga')
  eq(get_lines(), { 'a _b', 'aa_b' })
end

T['Align']['treats non-config modifier as explicit split pattern'] = function()
  validate_keys({ 'a.b', 'aaa.b' }, { 'ga', 'Vj', '.' }, { 'a  .b', 'aaa.b' })
  validate_keys({ 'a(b', 'aaa(b' }, { 'ga', 'Vj', '(' }, { 'a  (b', 'aaa(b' })
end

T['Align']['stops on `<Esc>` and `<C-c>`'] = function()
  for _, stop_key in ipairs({ '<Esc>', '<C-c>' }) do
    validate_keys({ 'a_b', 'aa_b' }, { 'Vj', 'ga', stop_key }, { 'a_b', 'aa_b' })
    eq(get_mode(), 'n')
  end
end

T['Align']['has guard against infinite loop'] = function()
  set_lines({ 'a_b', 'aa_b' })
  set_cursor(1, 0)
  type_keys('Vj', 'ga')
  eq(get_mode(), 'V')

  for _ = 1, 1001 do
    type_keys('m', ' ', '<CR>')
  end
  eq(get_mode(), 'n')
  eq(get_latest_message(), '(mini.align) Too many modifiers typed.')
end

T['Align']['does not stop on error during modifier execution'] = function()
  child.lua([[MiniAlign.config.modifiers.e = function() error('Bad modifier') end]])

  set_lines({ 'a_b', 'aa_b' })
  set_cursor(1, 0)

  -- Error in modifier execution should lead to a pause to make message visible
  local before_time = vim.loop.hrtime()
  type_keys('Vj', 'ga', 'e')
  local duration = 0.000001 * (vim.loop.hrtime() - before_time)
  eq(error_message_force_delay <= duration and duration <= error_message_force_delay + 2 * small_time, true)
  expect.match(get_latest_message(), '^%(mini.align%) Modifier "e" should be properly callable%. Reason:')
end

T['Align']['validates steps after each modifier'] = function()
  child.lua([[MiniAlign.config.modifiers.e = function(steps) steps.pre_split = 1 end]])
  set_lines({ 'a_b', 'aa_b' })
  set_cursor(1, 0)
  type_keys('Vj', 'ga')
  expect.error(function() type_keys('e', '_') end, 'pre_split.*array of steps')
end

T['Align']['shows state after one idle second'] = new_set({
  parametrize = { { 'Normal' }, { 'Visual' } },
}, {
  test = function(test_mode)
    -- Check this only on Neovim>=0.11, as there is a slight change in
    -- highlighting command line area
    if child.fn.has('nvim-0.11') == 0 then return end
    helpers.skip_if_slow()

    local expect_screenshot = function() child.expect_screenshot({ redraw = false }) end
    child.set_size(12, 20)
    child.o.cmdheight = 5

    -- Prompts message in debounce-style fashion
    set_lines({ 'a_b', 'aa_b' })
    set_cursor(1, 0)
    local keys = test_mode == 'Normal' and { 'ga', 'Vip' } or { 'Vip', 'ga' }
    type_keys(unpack(keys))

    sleep(show_state_delay - small_time)
    -- Should show no state
    expect_screenshot()
    type_keys('j')
    -- Should show state of modifier 'j'
    expect_screenshot()
    type_keys('r')
    -- Should show effect of hitting `r` and redraw if `showmode` is set (which
    -- it is by default)
    sleep(show_state_delay - small_time)
    -- Should still not show state
    expect_screenshot()
    sleep(small_time + small_time)
    -- Should now show state
    expect_screenshot()

    -- Should show state immediately if it was already shown
    type_keys('j', 'c')
    expect_screenshot()

    -- Ending alignment should remove shown state
    type_keys('_')
    expect_screenshot()
  end,
})

T['Align']['showing state does not cause hit-enter-prompt'] = function()
  child.set_size(6, 20)
  child.o.cmdheight = 2
  set_lines({ 'a_b', 'aa_b' })
  set_cursor(1, 0)

  type_keys('ga', 'Vj')
  sleep(show_state_delay + small_time)
  child.expect_screenshot()
end

T['Align']['cleans command line only if state was shown'] = function()
  child.set_size(12, 20)
  child.cmd([[echo 'My echo']])
  validate_keys({ 'a_b', 'aa_b' }, { 'ga', 'ip', '_' }, { 'a _b', 'aa_b' })
  child.expect_screenshot()
end

--stylua: ignore
T['Align']["respects 'selection=exclusive'"] = function()
  child.o.selection = 'exclusive'

  -- Normal mode charwise
  validate_keys({ 'a_b_c', 'aa_bb_cc' }, { 'ga', 'v', [[/bb\zs_<CR>]], '_' }, { 'a _b_c', 'aa_bb_cc' })
  validate_keys({ 'ы_ю_я', 'ыы_юю_яя' }, { 'ga', 'v', [[/юю\zs_<CR>]], '_' }, { 'ы _ю_я', 'ыы_юю_яя' })

  -- Normal mode blockwise
  validate_keys({ 'a_b_c', 'aa_bb_cc' }, { 'ga', '<C-v>', [[/bb\zs_<CR>]], '_' }, { 'a _b_c', 'aa_bb_cc' })
  validate_keys({ 'ы_ю_я', 'ыы_юю_яя' }, { 'ga', '<C-v>', [[/юю\zs_<CR>]], '_' }, { 'ы _ю_я', 'ыы_юю_яя' })

  -- Visual mode
  validate_keys({ 'a_b_c', 'aa_bb_cc' }, { 'v1j5l', 'ga', '_' }, { 'a _b_c', 'aa_bb_cc' })
  validate_keys({ 'ы_ю_я', 'ыы_юю_яя' }, { 'v1j5l', 'ga', '_' }, { 'ы _ю_я', 'ыы_юю_яя' })

  -- Visual mode blockwise
  validate_keys({ 'a_b_c', 'aa_bb_cc' }, { '<C-v>', '1j5l', 'ga', '_' }, { 'a _b_c', 'aa_bb_cc' })
  validate_keys({ 'ы_ю_я', 'ыы_юю_яя' }, { '<C-v>', '1j5l', 'ga', '_' }, { 'ы _ю_я', 'ыы_юю_яя' })
end

T['Align']['does not affect marks'] = function()
  local validate = function(start_keys)
    set_lines({ 'a_b', 'aa_b', 'aaa_b' })
    child.fn.setpos("'a", { 0, 1, 1, 0 })
    child.fn.setpos("'b", { 0, 3, 1, 0 })
    set_cursor(1, 0)

    type_keys(start_keys, '_')
    eq(get_lines(), { 'a _b', 'aa_b', 'aaa_b' })
    eq(child.api.nvim_buf_get_mark(0, 'a'), { 1, 0 })
    eq(child.api.nvim_buf_get_mark(0, 'b'), { 3, 0 })
  end

  -- Normal mode
  validate({ 'ga', 'v', [[2/_\zsb]], '<CR>' })
  validate({ 'ga', 'V', 'j' })
  validate({ 'ga', '<C-v>', [[2/_\zsb]], '<CR>' })

  -- Visual mode
  validate({ 'v', [[2/_\zsb]], '<CR>', 'ga' })
  validate({ 'V', 'j', 'ga' })
  validate({ '<C-v>', [[2/_\zsb]], '<CR>', 'ga' })
end

T['Align']['respects `vim.{g,b}.minialign_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minialign_disable = true

    validate_keys({ 'a_b', 'aa_b' }, { 'Vj', 'ga', '_' }, { 'a_b', 'aa_b' })
  end,
})

T['Align']['respects `config.silent`'] = function()
  child.set_size(12, 20)
  child.lua('MiniAlign.config.silent = true')

  -- Should not prompt message after idle second
  set_lines({ 'a_b', 'aa_b' })
  set_cursor(1, 0)
  type_keys('Vip', 'ga')

  sleep(show_state_delay + small_time)
  child.expect_screenshot()
end

-- Test mostly "preview" part. Hope that other is covered in 'Align' tests.
T['Align with preview'] =
  new_set({ hooks = {
    pre_case = function()
      child.set_size(12, 30)
      child.o.cmdheight = 5
    end,
  } })

T['Align with preview']['works'] = new_set({
  parametrize = {
    { 'Normal-char' },
    { 'Normal-line' },
    { 'Normal-block' },
    { 'Visual-char' },
    { 'Visual-line' },
    { 'Visual-block' },
  },
}, {
  test = function(test_mode)
    set_lines({ 'a_b_c', 'aaa_bbb_ccc' })
    set_cursor(1, 0)
    child.fn.setpos("'a", { 0, 2, 5, 0 })

    local init_keys = ({
      ['Normal-char'] = { 'gA', 'v', '`a' },
      ['Normal-line'] = { 'gA', 'V', 'j' },
      ['Normal-block'] = { 'gA', '<C-v>', '`a' },
      ['Visual-char'] = { 'v', '`a', 'gA' },
      ['Visual-line'] = { 'V', 'j', 'gA' },
      ['Visual-block'] = { '<C-v>', '`a', 'gA' },
    })[test_mode]
    type_keys(init_keys)

    -- Should show state immediately
    child.expect_screenshot()

    -- Should show result and not stop preview
    type_keys('_')
    child.expect_screenshot()

    type_keys('j', 'r')
    child.expect_screenshot()

    type_keys('m', '-', '<CR>')
    child.expect_screenshot()

    -- Hitting `<CR>` accepts current result and echoes status
    type_keys('<CR>')
    -- This should start Insert mode and not right justify by 'a'
    type_keys('a')
    child.expect_screenshot()
  end,
})

T['Align with preview']['correctly shows all steps in status'] = function()
  child.set_size(12, 30)
  child.o.cmdheight = 5

  child.lua('_G.dummy_step = function(name) return MiniAlign.new_step(name, function() end) end')
  set_config_steps({ pre_split = [[{ _G.dummy_step('sss1'), _G.dummy_step('sss2') }]] })
  set_config_steps({ pre_justify = [[{ _G.dummy_step('jjj1'), _G.dummy_step('jjj2') }]] })
  set_config_steps({ pre_merge = [[{ _G.dummy_step('mmm1'), _G.dummy_step('mmm2') }]] })

  set_lines({ 'a_b', 'aa_b' })
  type_keys('gA', 'ip', '_')
  child.expect_screenshot()
end

T['Align with preview']['uses option names for main steps'] = function()
  child.set_size(12, 30)
  child.o.cmdheight = 5
  set_config_steps({ split = [[MiniAlign.gen_step.default_split('aaa')]] })
  set_config_steps({ justify = [[MiniAlign.gen_step.default_justify('bbb')]] })
  set_config_steps({ merge = [[MiniAlign.gen_step.default_merge('ccc')]] })

  -- Should show option names instead of step names
  set_lines({ 'a_b', 'aa_b' })
  type_keys('gA', 'ip')
  child.expect_screenshot()
end

T['Align with preview']['stops preview after `<Esc>` and `<C-c>`'] = function()
  -- Don't show mode because it causes hit-enter-prompt with Visual selection
  child.o.showmode = false
  local validate = function(init_keys, stop_key)
    child.ensure_normal_mode()

    local lines = { 'a_b', 'aa_b' }
    set_lines(lines)
    set_cursor(1, 0)
    type_keys(init_keys, '_')
    -- Justify to right side
    type_keys('jr')
    eq(get_lines(), { ' a_b', 'aa_b' })

    -- Should reset text to its initial form
    type_keys(stop_key)
    eq(get_mode(), 'n')
    eq(get_lines(), lines)
    -- This should start Insert mode and not right justify by 'a'
    type_keys('a')
    eq(get_mode(), 'i')
  end

  -- Normal mode
  validate({ 'gA', 'Vj' }, '<Esc>')
  validate({ 'gA', 'Vj' }, '<C-c>')

  -- Visual mode
  validate({ 'Vj', 'gA' }, '<Esc>')
  validate({ 'Vj', 'gA' }, '<C-c>')
end

T['Align with preview']['correctly restores visual selection'] = new_set(
  { parametrize = { { 'Visual-char' }, { 'Visual-line' }, { 'Visual-block' } } },
  {
    test = function(test_mode)
      set_lines({ 'a_b_c', 'aaa_bbb_ccc', '', 'previous selection' })
      child.fn.setpos("'a", { 0, 2, 5, 0 })

      -- Make "previous selection" to complicate setup
      set_cursor(4, 9)
      type_keys('v', '8l', '<Esc>')

      set_cursor(1, 0)
      local init_keys = ({
        ['Visual-char'] = { 'v', '`a', 'gA' },
        ['Visual-line'] = { 'V', 'j', 'gA' },
        ['Visual-block'] = { '<C-v>', '`a', 'gA' },
      })[test_mode]
      type_keys(init_keys, '_')
      child.expect_screenshot()

      -- Make undo of current result and redo alignment
      type_keys('jr')
      child.expect_screenshot()
    end,
  }
)

T['Align with preview']['processes region before first modifier'] = function()
  set_config_opts({ split_pattern = '_', merge_delimiter = '--' })
  set_lines({ 'a_b', 'aaa_b' })
  set_cursor(1, 0)
  type_keys('Vj', 'gA')
  eq(get_lines(), { 'a  --_--b', 'aaa--_--b' })
end

T['Align with preview']['respects `vim.{g,b}.minialign_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minialign_disable = true

    local lines = { 'a_b', 'aa_b' }
    set_lines(lines)
    set_cursor(1, 0)
    type_keys('Vj', 'gA', '_', '<CR>')
    eq(get_lines(), lines)
  end,
})

T['Align with preview']['respects `config.silent`'] = function()
  child.set_size(12, 20)
  child.lua('MiniAlign.config.silent = true')

  set_lines({ 'a_b_c', 'aaa_bbb_ccc' })
  set_cursor(1, 0)
  type_keys('V', 'j', 'gA')

  -- Should not show helper message
  child.expect_screenshot()
end

local init_preview_align = function(lines, keys)
  child.ensure_normal_mode()
  set_lines(lines or { 'a_b', 'aaa_b' })
  set_cursor(1, 0)
  type_keys(keys or { 'Vj', 'gA' })
end

local validate_modifier_stops = function(modifier_key, stop_key)
  local lines = { 'a_b', 'aaa_b' }
  init_preview_align(lines)

  type_keys(modifier_key, stop_key)
  eq(get_mode(), 'V')
  eq(get_lines(), lines)

  -- Aligning should still be active
  type_keys('_')
  eq(get_lines(), { 'a  _b', 'aaa_b' })
end

T['Modifiers'] =
  new_set({ hooks = {
    pre_case = function()
      child.set_size(12, 30)
      child.o.cmdheight = 5
    end,
  } })

T['Modifiers']['s'] = new_set()

T['Modifiers']['s']['works'] = function()
  set_lines({ 'a_b', 'aaa_b' })
  set_cursor(1, 0)
  type_keys('ga', 'ip')

  type_keys('s')
  child.expect_screenshot()
  type_keys('_', '<CR>')
  child.expect_screenshot()
end

T['Modifiers']['s']['stops on `<Esc>` and `<C-c>`'] = function()
  validate_modifier_stops('s', '<Esc>')
  validate_modifier_stops('s', '<C-c>')
end

T['Modifiers']['s']['allows empty input'] = function()
  set_config_opts({ justify_side = 'right' })
  local lines = { 'a_b', 'aaa_b' }
  init_preview_align(lines)
  type_keys('s', '<CR>')

  -- Using `''` as split means that strings act as single-cell rows
  eq(get_lines(), { '  a_b', 'aaa_b' })
end

T['Modifiers']['j'] = new_set()

T['Modifiers']['j']['works'] = new_set({
  -- Test for all actionable values and one not actionable (should do nothing)
  parametrize = { { 'l' }, { 'c' }, { 'r' }, { 'n' }, { 'u' } },
}, {
  test = function(user_key)
    set_config_opts({ split_pattern = '_' })
    if user_key == 'l' then set_config_opts({ justify_side = 'right' }) end

    init_preview_align()

    type_keys('j')
    child.expect_screenshot()

    type_keys(user_key)
    child.expect_screenshot()
  end,
})

T['Modifiers']['j']['stops on `<Esc>` and `<C-c>`'] = function()
  local validate = function(stop_key)
    local lines = { 'a_b', 'aaa_b' }
    init_preview_align(lines)

    type_keys('j', stop_key)

    -- Aligning should still be active
    eq(get_mode(), 'V')
    type_keys('_')
    eq(get_lines(), { 'a  _b', 'aaa_b' })
  end

  validate('<Esc>')
  validate('<C-c>')
end

T['Modifiers']['m'] = new_set()

T['Modifiers']['m']['works'] = function()
  set_lines({ 'a_b', 'aaa_b' })
  set_cursor(1, 0)
  type_keys('ga', 'ip')

  type_keys('m')
  child.expect_screenshot()
  type_keys('--', '<CR>')
  type_keys('_')
  child.expect_screenshot()
end

T['Modifiers']['m']['stops on `<Esc>` and `<C-c>`'] = function()
  validate_modifier_stops('m', '<Esc>')
  validate_modifier_stops('m', '<C-c>')
end

T['Modifiers']['m']['allows empty input'] = function()
  set_config_opts({ split_pattern = '_', merge_delimiter = '--' })
  local lines = { 'a_b', 'aaa_b' }
  init_preview_align(lines)
  eq(get_lines(), { 'a  --_--b', 'aaa--_--b' })

  -- Should result into `merge = ''`
  type_keys('m', '<CR>')
  eq(get_lines(), { 'a  _b', 'aaa_b' })
end

T['Modifiers']['f'] = new_set()

T['Modifiers']['f']['works'] = function()
  set_lines({ 'a_b', 'aa_b', 'aaa_b' })
  set_cursor(1, 0)
  type_keys('ga', 'ip')

  type_keys('f')
  child.expect_screenshot()

  type_keys('row ~= 1', '<CR>')
  type_keys('_')
  eq(get_lines(), { 'a_b', 'aa _b', 'aaa_b' })
end

T['Modifiers']['f']['stops on `<Esc>` and `<C-c>`'] = function()
  validate_modifier_stops('f', '<Esc>')
  validate_modifier_stops('f', '<C-c>')
end

T['Modifiers']['f']['allows empty input'] = function()
  set_config_opts({ split_pattern = '_' })
  init_preview_align()

  -- Should result into having `''` as special input (filter step without actual filtering)
  type_keys('f', '<CR>')
  child.expect_screenshot()
end

T['Modifiers']['i'] = new_set()

T['Modifiers']['i']['works'] = function()
  child.o.commentstring = '# %s'
  init_preview_align({ '# aaaaa=b', '"aaaaa=b"', 'a=b', 'aa=b' }, { 'V3j', 'gA' })

  type_keys('s', '=', '<CR>')
  child.expect_screenshot()

  type_keys('i')
  child.expect_screenshot()
end

T['Modifiers']['p'] = new_set()

T['Modifiers']['p']['works'] = function()
  set_config_opts({ split_pattern = '_' })
  init_preview_align({ 'a_b_c', 'aaa_bbb_ccc' })

  eq(get_lines(), { 'a  _b  _c', 'aaa_bbb_ccc' })
  type_keys('p')
  child.expect_screenshot()
  eq(get_lines(), { 'a_  b_  c', 'aaa_bbb_ccc' })
end

T['Modifiers']['t'] = new_set()

T['Modifiers']['t']['works'] = function()
  set_config_opts({ split_pattern = '_' })
  init_preview_align({ ' a _ b _ c', '  aaa _ bbb _  ccc' })

  eq(get_lines(), { ' a    _ b   _ c', '  aaa _ bbb _  ccc' })
  type_keys('t')
  child.expect_screenshot()
  eq(get_lines(), { ' a   _b  _c', '  aaa_bbb_ccc' })
end

T['Modifiers']['<BS>'] = new_set()

T['Modifiers']['<BS>']['works'] = new_set({ parametrize = { { 'pre_split' }, { 'pre_justify' }, { 'pre_merge' } } }, {
  test = function(pre_step_name)
    set_config_steps({ [pre_step_name] = [[{ MiniAlign.new_step('aaa', function() end) }]] })
    init_preview_align()
    child.expect_screenshot()
    type_keys('<BS>')
    child.expect_screenshot()
  end,
})

T['Modifiers']['<BS>']['does nothing if no pre-steps'] = function()
  local lines = { 'a_b', 'aaa_b' }
  init_preview_align(lines)
  child.expect_screenshot()
  type_keys('<BS>')
  child.expect_screenshot()

  -- Aligning should still be active
  type_keys('_')
  eq(get_lines(), { 'a  _b', 'aaa_b' })
end

T['Modifiers']['<BS>']['prompts to choose if ambiguous'] = function()
  child.lua('_G.dummy_step = function(name) return MiniAlign.new_step(name, function() end) end')
  set_config_steps({ pre_split = [[{ _G.dummy_step('sss') }]] })
  set_config_steps({ pre_justify = [[{ _G.dummy_step('jjj') }]] })
  set_config_steps({ pre_merge = [[{ _G.dummy_step('mmm') }]] })

  set_lines({ 'a_b', 'aa_b' })
  type_keys('gA', 'ip', '_')
  child.expect_screenshot()

  type_keys('<BS>')
  child.expect_screenshot()
  type_keys('s')
  child.expect_screenshot()

  type_keys('<BS>')
  child.expect_screenshot()
  type_keys('j')
  child.expect_screenshot()
end

local validate_common_split = function(init_lines, modifier_key)
  set_lines(init_lines)
  set_cursor(1, 0)
  type_keys('VG', 'gA')

  child.expect_screenshot()
  type_keys(modifier_key)
  child.expect_screenshot()
end

T['Modifiers']['<equal sign>'] = function() validate_common_split({ 'a=b', 'aaa=bbb' }, '=') end

T['Modifiers']['<comma>'] = function() validate_common_split({ 'a,b', 'aaa,bbb' }, ',') end

T['Modifiers']['<bar>'] = function() validate_common_split({ '|a|b|', '|aaa|bbb|' }, '|') end

T['Modifiers']['<space bar>'] = function() validate_common_split({ '  a  b', '    aaa    bbb', 'a b' }, ' ') end

T['Documented examples'] = new_set()

T['Documented examples']['trim with highest indentation'] = function()
  local lines = { ' a _ b', '   aaa _ bbb' }
  local keys = { 'Vj', 'ga', 't', '_' }

  validate_keys(lines, keys, { ' a    _b', '   aaa_bbb' })

  unload_module()
  child.lua([[require('mini.align').setup({
    modifiers = {
      t = function(steps, _) table.insert(steps.pre_justify, MiniAlign.gen_step.trim('both', 'high')) end
    },
  })]])

  validate_keys(lines, keys, { '   a  _b', '   aaa_bbb' })
end

T['Documented examples']['use "j" to cycle through justify values'] = function()
  unload_module()
  child.lua([[require('mini.align').setup({
    modifiers = {
      j = function(_, opts)
        local next_option = ({
          left = 'center', center = 'right', right = 'none', none = 'left'
        })[opts.justify_side]
        opts.justify_side = next_option or 'left'
      end
    },
  })]])

  set_lines({ 'a_b', 'aaa_b' })
  set_cursor(1, 0)
  type_keys('Vip', 'gA', '_')
  eq(get_lines(), { 'a  _b', 'aaa_b' })

  type_keys('j')
  eq(get_lines(), { ' a _b', 'aaa_b' })

  type_keys('j')
  eq(get_lines(), { '  a_b', 'aaa_b' })

  type_keys('j')
  eq(get_lines(), { 'a_b', 'aaa_b' })

  type_keys('j')
  eq(get_lines(), { 'a  _b', 'aaa_b' })
end

T['Documented examples']['align by default only by first pair of columns'] = function()
  local lines = { 'a_b_c', 'aa_bb_cc' }
  local keys = { 'Vip', 'ga', '_' }

  validate_keys(lines, keys, { 'a _b _c', 'aa_bb_cc' })

  unload_module()
  child.lua([[
  local align = require('mini.align')
  align.setup({
    steps = {
      pre_justify = { align.gen_step.filter('n == 1') }
    },
  })]])

  validate_keys(lines, keys, { 'a _b_c', 'aa_bb_cc' })
end

return T
