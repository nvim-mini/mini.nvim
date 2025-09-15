local helpers = dofile('tests/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('ai', config) end
local unload_module = function() child.mini_unload('ai') end
local reload_module = function(config) unload_module(); load_module(config) end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
local sleep = function(ms) helpers.sleep(ms, child) end
--stylua: ignore end

local get_latest_message = function() return child.cmd_capture('1messages') end

local get_mode = function() return child.api.nvim_get_mode()['mode'] end

local validate_edit = function(before_lines, before_cursor, after_lines, after_cursor, ...)
  child.ensure_normal_mode()

  set_lines(before_lines)
  set_cursor(unpack(before_cursor))

  type_keys(...)

  eq(get_lines(), after_lines)
  eq(get_cursor(), after_cursor)
end

local validate_edit1d = function(before_line, before_column, after_line, after_column, ...)
  validate_edit({ before_line }, { 1, before_column }, { after_line }, { 1, after_column }, ...)
end

local validate_next_region = function(keys, next_region)
  type_keys(keys)
  -- Should put cursor at the right edge of selection (as it is done for
  -- built-in textobjects in Visual mode)
  eq({ { child.fn.line('v'), child.fn.col('v') }, { child.fn.line('.'), child.fn.col('.') } }, next_region)
end

local validate_next_region1d = function(keys, next_region)
  type_keys(keys)
  eq({ child.fn.col('v'), child.fn.col('.') }, next_region)
end

local validate_tobj = function(lines, cursor, keys, expected, vis_mode)
  vis_mode = vim.api.nvim_replace_termcodes(vis_mode or 'v', true, true, true)

  child.ensure_normal_mode()
  set_lines(lines)
  set_cursor(unpack(cursor))
  type_keys(vis_mode, keys)
  eq(get_mode(), vis_mode)

  -- Allow supplying number items to verify linewise selection
  local expected_from = type(expected[1]) == 'number' and expected[1] or { expected[1][1], expected[1][2] - 1 }
  local expected_to = type(expected[2]) == 'number' and expected[2] or { expected[2][1], expected[2][2] - 1 }
  child.expect_visual_marks(expected_from, expected_to)
end

local validate_tobj1d = function(line, column, keys, expected)
  validate_tobj({ line }, { 1, column }, keys, { { 1, expected[1] }, { 1, expected[2] } })
end

local validate_no_tobj = function(lines, cursor, keys, vis_mode)
  vis_mode = vim.api.nvim_replace_termcodes(vis_mode or 'v', true, true, true)

  child.ensure_normal_mode()
  set_lines(lines)
  set_cursor(unpack(cursor))

  type_keys(vis_mode, keys)
  eq(get_mode(), 'n')
  eq(get_cursor(), cursor)
  expect.match(get_latest_message(), 'No textobject')
end

local validate_no_tobj1d = function(line, column, keys) validate_no_tobj({ line }, { 1, column }, keys) end

-- Time constants
local helper_message_delay = 1000
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
  eq(child.lua_get('type(_G.MiniAi)'), 'table')
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniAi.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniAi.config.' .. field), value) end

  -- Check default values
  expect_config('custom_textobjects', vim.NIL)
  expect_config('mappings.around', 'a')
  expect_config('mappings.inside', 'i')
  expect_config('mappings.around_next', 'an')
  expect_config('mappings.inside_next', 'in')
  expect_config('mappings.around_last', 'al')
  expect_config('mappings.inside_last', 'il')
  expect_config('mappings.goto_left', 'g[')
  expect_config('mappings.goto_right', 'g]')
  expect_config('n_lines', 50)
  expect_config('search_method', 'cover_or_next')
  expect_config('silent', false)
end

T['setup()']['respects `config` argument'] = function()
  unload_module()
  load_module({ n_lines = 10 })
  eq(child.lua_get('MiniAi.config.n_lines'), 10)
end

T['setup()']['validates `config` argument'] = function()
  unload_module()

  local expect_config_error = function(config, name, target_type)
    expect.error(load_module, vim.pesc(name) .. '.*' .. vim.pesc(target_type), config)
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ custom_textobjects = 'a' }, 'custom_textobjects', 'table')
  expect_config_error({ mappings = 'a' }, 'mappings', 'table')
  expect_config_error({ mappings = { around = 1 } }, 'mappings.around', 'string')
  expect_config_error({ mappings = { inside = 1 } }, 'mappings.inside', 'string')
  expect_config_error({ mappings = { around_next = 1 } }, 'mappings.around_next', 'string')
  expect_config_error({ mappings = { inside_next = 1 } }, 'mappings.inside_next', 'string')
  expect_config_error({ mappings = { around_last = 1 } }, 'mappings.around_last', 'string')
  expect_config_error({ mappings = { inside_last = 1 } }, 'mappings.inside_last', 'string')
  expect_config_error({ mappings = { goto_left = 1 } }, 'mappings.goto_left', 'string')
  expect_config_error({ mappings = { goto_right = 1 } }, 'mappings.goto_right', 'string')
  expect_config_error({ n_lines = 'a' }, 'n_lines', 'number')
  expect_config_error({ search_method = 1 }, 'search_method', 'one of')
  expect_config_error({ silent = 1 }, 'silent', 'boolean')
end

T['setup()']['properly handles `config.mappings`'] = function()
  local has_map = function(lhs, pattern) return child.cmd_capture('xmap ' .. lhs):find(pattern) ~= nil end
  eq(has_map('a', 'Around'), true)

  unload_module()
  child.api.nvim_del_keymap('x', 'a')
  child.api.nvim_del_keymap('x', 'an')
  child.api.nvim_del_keymap('x', 'al')

  -- Supplying empty string should mean "don't create keymap"
  load_module({ mappings = { around = '', around_next = '', around_last = '' } })
  eq(has_map('a', 'Around'), false)
end

local find_textobject = function(...) return child.lua_get('MiniAi.find_textobject(...)', { ... }) end

local validate_find = function(lines, cursor, args, expected)
  set_lines(lines)
  set_cursor(cursor[1], cursor[2])

  local new_expected
  if expected == nil then
    new_expected = vim.NIL
  else
    new_expected = {
      from = { line = expected[1][1], col = expected[1][2] },
      to = { line = expected[2][1], col = expected[2][2] },
      vis_mode = expected.vis_mode,
    }
  end

  eq(find_textobject(unpack(args)), new_expected)
end

local validate_find1d = function(line, column, args, expected)
  local new_expected
  if expected ~= nil then new_expected = { { 1, expected[1] }, { 1, expected[2] } } end
  validate_find({ line }, { 1, column }, args, new_expected)
end

T['find_textobject()'] = new_set()

T['find_textobject()']['works'] = function() validate_find1d('aa(bb)cc', 3, { 'a', ')' }, { 3, 6 }) end

T['find_textobject()']['respects `id` argument'] = function() validate_find1d('(aa[bb]cc)', 4, { 'a', ']' }, { 4, 7 }) end

T['find_textobject()']['respects `ai_type` argument'] = function()
  validate_find1d('aa(bb)cc', 3, { 'i', ')' }, { 4, 5 })
end

T['find_textobject()']['respects `opts.n_lines`'] = function()
  local lines = { '(', '', 'a', '', ')' }
  validate_find(lines, { 3, 1 }, { 'a', ')', { n_lines = 1 } }, nil)
  validate_find(lines, { 3, 1 }, { 'a', ')', { n_lines = 2 } }, { { 1, 1 }, { 5, 1 } })

  -- Should handle 0
  validate_find(lines, { 3, 1 }, { 'a', ')', { n_lines = 0 } }, nil)
end

T['find_textobject()']['respects `opts.n_times`'] = function()
  local line, column = '(aa(bb)cc)', 4
  validate_find1d(line, column, { 'a', ')', { n_times = 1 } }, { 4, 7 })
  validate_find1d(line, column, { 'a', ')', { n_times = 2 } }, { 1, 10 })
  validate_find1d(line, column, { 'i', ')', { n_times = 2 } }, { 2, 9 })

  -- Should handle 0
  validate_find1d(line, 0, { 'a', ')', { n_times = 0 } }, nil)
end

T['find_textobject()']['respects `opts.reference_region`'] = function()
  local line = 'aa(bb(cc)dd)ee'
  local new_opts = function(from, to)
    return { reference_region = { from = { line = 1, col = from }, to = { line = 1, col = to } } }
  end

  validate_find1d(line, 0, { 'a', ')', new_opts(7, 7) }, { 6, 9 })
  validate_find1d(line, 0, { 'a', ')', new_opts(7, 9) }, { 6, 9 })
  validate_find1d(line, 0, { 'a', ')', new_opts(6, 8) }, { 6, 9 })

  -- Even if reference region is a valid text object, it should select another
  -- one. This enables evolving of textobjects during consecutive calls.
  validate_find1d(line, 0, { 'a', ')', new_opts(6, 9) }, { 3, 12 })
  validate_find1d(line, 0, { 'a', ')', new_opts(3, 12) }, nil)

  -- Allows empty reference region
  local empty_opts = { reference_region = { from = { line = 1, col = 6 } } }
  validate_find1d(line, 0, { 'a', ')', empty_opts }, { 6, 9 })
end

T['find_textobject()']['respects `opts.search_method`'] = function()
  local line = '(aa)bbb(cc)'
  local new_opts = function(search_method) return { search_method = search_method } end

  -- By default should be 'cover_or_next'
  validate_find1d(line, 4, { 'a', ')' }, { 8, 11 })

  validate_find1d(line, 1, { 'a', ')', new_opts('cover_or_next') }, { 1, 4 })
  validate_find1d(line, 4, { 'a', ')', new_opts('cover_or_next') }, { 8, 11 })
  validate_find1d(line, 8, { 'a', ')', new_opts('cover_or_next') }, { 8, 11 })

  validate_find1d(line, 1, { 'a', ')', new_opts('cover') }, { 1, 4 })
  validate_find1d(line, 4, { 'a', ')', new_opts('cover') }, nil)
  validate_find1d(line, 8, { 'a', ')', new_opts('cover') }, { 8, 11 })

  validate_find1d(line, 1, { 'a', ')', new_opts('cover_or_prev') }, { 1, 4 })
  validate_find1d(line, 4, { 'a', ')', new_opts('cover_or_prev') }, { 1, 4 })
  validate_find1d(line, 8, { 'a', ')', new_opts('cover_or_prev') }, { 8, 11 })

  validate_find1d(line, 1, { 'a', ')', new_opts('cover_or_nearest') }, { 1, 4 })
  validate_find1d(line, 4, { 'a', ')', new_opts('cover_or_nearest') }, { 1, 4 })
  validate_find1d(line, 5, { 'a', ')', new_opts('cover_or_nearest') }, { 1, 4 })
  validate_find1d(line, 6, { 'a', ')', new_opts('cover_or_nearest') }, { 8, 11 })
  validate_find1d(line, 8, { 'a', ')', new_opts('cover_or_nearest') }, { 8, 11 })

  -- Should validate `opts.search_method`
  expect.error(function() find_textobject('a', ')', { search_method = 'aaa' }) end, 'one of')
end

T['find_textobject()']['respects custom textobjects'] = function()
  local line, column = 'aabbcc', 0

  validate_find1d(line, column, { 'a', 'c' }, nil)
  child.lua([[MiniAi.config.custom_textobjects = { c = { '()c()' } }]])
  validate_find1d(line, column, { 'a', 'c' }, { 5, 5 })
end

T['find_textobject()']['works on multiple lines'] = function()
  local lines, cursor = { '(aa', '(bb', 'cc', 'dd)', 'ee)' }, { 3, 0 }
  validate_find(lines, cursor, { 'a', ')' }, { { 2, 1 }, { 4, 3 } })
  validate_find(lines, cursor, { 'i', ')' }, { { 2, 2 }, { 4, 2 } })
  validate_find(lines, cursor, { 'a', ')', { n_times = 2 } }, { { 1, 1 }, { 5, 3 } })
  validate_find(lines, cursor, { 'i', ')', { n_times = 2 } }, { { 1, 2 }, { 5, 2 } })

  -- Region over multiple lines is not empty (it has newline)
  validate_find({ 'aa(', ')' }, { 1, 1 }, { 'i', ')' }, { { 1, 4 }, { 1, 4 } })
end

T['find_textobject()']['may return position after line end'] = function()
  -- This powers multiline collapsing (calling `di)` leads to '()' single line)
  validate_find({ '(', 'aa', ')' }, { 2, 0 }, { 'i', ')' }, { { 1, 2 }, { 2, 3 } })
end

T['find_textobject()']['works with multibyte characters'] = function()
  -- Each multibyte character takes two column counts
  local line = '(ыы)ффф(ыы)'
  validate_find1d(line, 1, { 'a', ')' }, { 1, 6 })
  validate_find1d(line, 1, { 'a', ')', { n_times = 2 } }, { 13, 18 })
  validate_find1d(line, 6, { 'a', ')' }, { 13, 18 })
end

T['find_textobject()']['handles cursor on textobject edge'] = function()
  validate_find1d('aa(bb)cc', 2, { 'a', ')' }, { 3, 6 })
  validate_find1d('aa(bb)cc', 2, { 'i', ')' }, { 4, 5 })

  validate_find1d('aa(bb)cc', 5, { 'a', ')' }, { 3, 6 })
  validate_find1d('aa(bb)cc', 5, { 'i', ')' }, { 4, 5 })
end

T['find_textobject()']['first searches within current line'] = function()
  local lines, cursor = { '(', 'aa(bb)', ')' }, { 2, 0 }
  validate_find(lines, cursor, { 'a', ')' }, { { 2, 3 }, { 2, 6 } })
  validate_find(lines, cursor, { 'a', ')', { search_method = 'cover' } }, { { 1, 1 }, { 3, 1 } })
end

T['find_textobject()']['handles `n_times > 1` with matches on current line'] = function()
  local lines, cursor = { '((', 'aa(bb)cc(dd)', '))' }, { 2, 0 }
  validate_find(lines, cursor, { 'a', ')', { n_times = 1 } }, { { 2, 3 }, { 2, 6 } })
  validate_find(lines, cursor, { 'a', ')', { n_times = 2 } }, { { 2, 9 }, { 2, 12 } })
  validate_find(lines, cursor, { 'a', ')', { n_times = 3 } }, { { 1, 2 }, { 3, 1 } })
  validate_find(lines, cursor, { 'a', ')', { n_times = 4 } }, { { 1, 1 }, { 3, 2 } })
end

T['find_textobject()']['allows empty output region'] = function()
  set_lines({ 'aa()bb(cc)' })

  for i = 1, 2 do
    set_cursor(1, i)
    eq(find_textobject('i', ')'), { from = { line = 1, col = 4 } })
    eq(find_textobject('i', ')', { n_times = 2 }), { from = { line = 1, col = 8 }, to = { line = 1, col = 9 } })
  end
end

T['find_textobject()']['ensures that output is not covered by reference'] = function()
  set_lines({ 'aa()bb(cc)dd(ee)' })
  set_cursor(1, 0)

  -- Non-empty reference
  eq(
    find_textobject('i', ')', { reference_region = { from = { line = 1, col = 8 }, to = { line = 1, col = 9 } } }),
    { from = { line = 1, col = 14 }, to = { line = 1, col = 15 } }
  )

  -- Empty reference
  eq(
    find_textobject('i', ')', { reference_region = { from = { line = 1, col = 4 } } }),
    { from = { line = 1, col = 8 }, to = { line = 1, col = 9 } }
  )
end

T['find_textobject()']['handles function as textobject spec'] = new_set()

T['find_textobject()']['handles function as textobject spec']['returns composed pattern'] = function()
  child.lua([[MiniAi.config.custom_textobjects = {
    x = function(...) _G.args = {...}; return {'x()x()x'} end
  }]])

  validate_find1d('aaxxxbb', 0, { 'a', 'x' }, { 3, 5 })
  -- Should be called with arguments after expanding defaults
  --stylua: ignore
  eq(
    child.lua_get('_G.args'),
    {
      'a', 'x',
      {
        n_lines = 50,
        n_times = 1,
        reference_region = { from = { line = 1, col = 1 } },
        search_method = 'cover_or_next',
      },
    }
  )
end

T['find_textobject()']['handles function as textobject spec']['returns region'] = function()
  -- Should take arguments from corresponding `find_textobject()` call
  child.lua([[_G.full_buffer = function(ai_type, id, opts)
    local from = { line = 1, col = 1 }
    local to = { line = vim.fn.line('$'), col = vim.fn.getline('$'):len() }
    if ai_type == 'i' then to.col = to.col - 1 end
    return { from = from, to = to }
  end]])
  child.lua([[MiniAi.config.custom_textobjects = { g = _G.full_buffer }]])
  validate_find({ 'aaaaa', 'bbbb', 'ccc' }, { 2, 0 }, { 'a', 'g' }, { { 1, 1 }, { 3, 3 } })
  validate_find({ 'aaaaa', 'bbbb', 'ccc' }, { 2, 0 }, { 'i', 'g' }, { { 1, 1 }, { 3, 2 } })

  -- Should return region as is (taking precedence over options)
  child.lua('MiniAi.config.n_lines = 0')
  child.lua([[MiniAi.config.search_method = 'next']])
  validate_find({ 'aaaaa', 'bbbb', 'ccc' }, { 2, 0 }, { 'a', 'g' }, { { 1, 1 }, { 3, 3 } })
end

T['find_textobject()']['handles function as textobject spec']['returns array of regions'] = function()
  -- Should take arguments from corresponding `find_textobject()` call
  child.lua([[_G.fixed_regions = function(_, _, _)
    local res = {}
    res[1] = { from = { line = 1, col = 1 }, to = { line = 1, col = 2 } }
    res[2] = { from = { line = 1, col = 1 }, to = { line = 1, col = 4 } }
    res[3] = { from = { line = 2, col = 1 }, to = { line = 2, col = 2 } }
    res[4] = { from = { line = 2, col = 1 }, to = { line = 2, col = 4 } }
    return res
  end]])
  child.lua([[MiniAi.config.custom_textobjects = { r = _G.fixed_regions }]])

  local lines = { 'aaaaa', 'bbbb', 'ccc' }
  validate_find(lines, { 1, 0 }, { 'a', 'r' }, { { 1, 1 }, { 1, 2 } })
  validate_find(lines, { 1, 3 }, { 'a', 'r' }, { { 1, 1 }, { 1, 4 } })
  validate_find(lines, { 1, 4 }, { 'a', 'r' }, { { 2, 1 }, { 2, 2 } })
  validate_find(lines, { 3, 0 }, { 'a', 'r' }, nil)

  -- Should pick best region according to options
  child.lua([[MiniAi.config.n_lines = 0]])
  validate_find(lines, { 1, 4 }, { 'a', 'r' }, nil)

  child.lua([[MiniAi.config.n_lines = 10]])
  child.lua([[MiniAi.config.search_method = 'cover']])
  validate_find(lines, { 1, 4 }, { 'a', 'r' }, nil)

  -- Should account for region `vis_mode`
  child.lua([[_G.line_regions = function(_, _, _)
    return {
      { from = { line = 1, col = 1 }, to = { line = 2, col = 1 }, vis_mode = 'V' },
      { from = { line = 3, col = 1 }, to = { line = 4, col = 1 }, vis_mode = 'V' },
    }
  end]])
  child.lua([[MiniAi.config.custom_textobjects = { m = _G.line_regions }]])

  local ref_region_1 = { { 1, 1 }, { 2, 1 }, vis_mode = 'V' }
  validate_find({ 'aaa', 'bbb', 'ccc', 'ddd' }, { 1, 0 }, { 'a', 'm' }, ref_region_1)
  local ref_region_2 = { { 3, 1 }, { 4, 1 }, vis_mode = 'V' }
  validate_find({ 'aaa', 'bbb', 'ccc', 'ddd' }, { 3, 0 }, { 'a', 'm' }, ref_region_2)
end

T['find_textobject()']['handles function as specification item'] = function()
  child.lua([[_G.c_spec = {
    '%b()',
    function(s, init) if init > 1 then return end; return 2, s:len() end,
    '^().*().$'
  }]])
  child.lua([[MiniAi.config.custom_textobjects = { c = _G.c_spec }]])
  validate_find1d('aa(bb)', 0, { 'a', 'c' }, { 4, 6 })
  validate_find1d('aa(bb)', 0, { 'i', 'c' }, { 4, 5 })
end

T['find_textobject()']['handles callable table'] = new_set()

T['find_textobject()']['handles callable table']['as textobject spec'] = function()
  child.lua([[MiniAi.config.custom_textobjects = {
    x = setmetatable({}, {__call = function() return {'x()x()x'} end})
  }]])

  validate_find1d('aaxxxbb', 0, { 'a', 'x' }, { 3, 5 })
end

T['find_textobject()']['handles callable table']['as specification item'] = function()
  child.lua([[_G.c_spec = {
    '%b()',
    setmetatable({}, {__call = function(_, s, init) if init > 1 then return end; return 2, s:len() end}),
    '^().*().$'
  }]])
  child.lua([[MiniAi.config.custom_textobjects = { c = _G.c_spec }]])
  validate_find1d('aa(bb)', 0, { 'a', 'c' }, { 4, 6 })
  validate_find1d('aa(bb)', 0, { 'i', 'c' }, { 4, 5 })
end

T['find_textobject()']['shows message if no region is found'] = function()
  -- Make all showed messages full width
  child.o.cmdheight = 10

  local validate = function(msg, args)
    child.cmd('messages clear')
    validate_find1d('aa', 0, args, nil)
    eq(get_latest_message(), msg)
  end

  validate(
    [[(mini.ai) No textobject "a)" found covering region within 50 lines and `search_method = 'cover_or_next'`.]],
    { 'a', ')' }
  )
  validate(
    [[(mini.ai) No textobject "i]" found covering region 2 times within 1 line and `search_method = 'cover'`.]],
    { 'i', ']', { n_times = 2, n_lines = 1, search_method = 'cover' } }
  )
  validate(
    [[(mini.ai) No textobject "i]" found covering region 0 times within 0 lines and `search_method = 'cover_or_next'`.]],
    { 'i', ']', { n_times = 0, n_lines = 0 } }
  )
end

T['find_textobject()']['respects `config.silent`'] = function()
  child.lua('MiniAi.config.silent = true')

  validate_find1d('aa', 0, { 'a', ')' }, nil)
  eq(get_latest_message(), '')
end

T['find_textobject()']['respects `vim.b.miniai_config`'] = function()
  child.b.miniai_config = { search_method = 'cover' }
  validate_find1d('aa(bb)', 0, { 'a', ')' }, nil)
end

local validate_move = function(lines, cursor, args, expected)
  set_lines(lines)
  set_cursor(cursor[1], cursor[2])
  child.lua([[MiniAi.move_cursor(...)]], args)
  eq(get_cursor(), { expected[1], expected[2] })
end

local validate_move1d = function(line, column, args, expected)
  validate_move({ line }, { 1, column }, args, { 1, expected })
end

T['move_cursor()'] = new_set()

T['move_cursor()']['works'] = function() validate_move1d('aa(bbb)', 4, { 'left', 'a', ')' }, 2) end

T['move_cursor()']['respects `side` argument'] = function()
  local line = '(aa)bb(cc)'
  validate_move1d(line, 1, { 'left', 'a', ')' }, 0)
  validate_move1d(line, 1, { 'right', 'a', ')' }, 3)
  validate_move1d(line, 4, { 'left', 'a', ')' }, 6)
  validate_move1d(line, 4, { 'right', 'a', ')' }, 9)
  validate_move1d(line, 7, { 'left', 'a', ')' }, 6)
  validate_move1d(line, 7, { 'right', 'a', ')' }, 9)

  -- It should validate `side` argument
  expect.error(
    function() child.lua([[MiniAi.move_cursor('leftright', 'a', ')')]]) end,
    vim.pesc([[(mini.ai) `side` should be one of 'left' or 'right'.]])
  )
end

T['move_cursor()']['respects `ai_type` argument'] = function()
  validate_move1d('aa(bbb)', 4, { 'left', 'i', ')' }, 3)
  validate_move1d('aa(bbb)', 4, { 'right', 'i', ')' }, 5)
end

T['move_cursor()']['respects `id` argument'] = function() validate_move1d('aa[bbb]', 4, { 'left', 'a', ']' }, 2) end

T['move_cursor()']['respects `opts` argument'] = function()
  validate_move1d('aa(bbb)cc(ddd)', 4, { 'left', 'a', ')', { n_times = 2 } }, 9)
end

T['move_cursor()']['always jumps exactly `opts.n_times` times'] = function()
  -- It can be not that way if cursor is on edge of one of target textobjects
  local line = 'aa(bb)cc(dd)ee(ff)'
  validate_move1d(line, 0, { 'left', 'a', ')', { n_times = 2 } }, 8) -- 0->2->8
  validate_move1d(line, 2, { 'left', 'a', ')', { n_times = 2 } }, 14) -- 2->8->14
  validate_move1d(line, 3, { 'left', 'a', ')', { n_times = 2 } }, 8) -- 3->2->8
  validate_move1d(line, 5, { 'left', 'a', ')', { n_times = 2 } }, 8) -- 5->2->8

  validate_move1d(line, 0, { 'right', 'a', ')', { n_times = 2 } }, 11) -- 0->5->11
  validate_move1d(line, 2, { 'right', 'a', ')', { n_times = 2 } }, 11) -- 2->5->11
  validate_move1d(line, 3, { 'right', 'a', ')', { n_times = 2 } }, 11) -- 3->5->11
  validate_move1d(line, 5, { 'right', 'a', ')', { n_times = 2 } }, 17) -- 5->11->17
end

T['move_cursor()']['opens just enough folds'] = function()
  set_lines({ '(aa', 'b)', 'c', 'd' })

  -- Manually create two nested closed folds
  set_cursor(3, 0)
  type_keys('zf', 'G')
  type_keys('zf', 'gg')
  eq(child.fn.foldlevel(1), 1)
  eq(child.fn.foldlevel(3), 2)
  eq(child.fn.foldclosed(2), 1)
  eq(child.fn.foldclosed(3), 1)

  -- Moving cursor should open just enough folds
  set_cursor(1, 1)
  child.lua([[MiniAi.move_cursor('right', 'a', ')')]])
  eq(get_cursor(), { 2, 1 })
  eq(child.fn.foldclosed(2), -1)
  eq(child.fn.foldclosed(3), 3)
end

T['move_cursor()']['adds jumplist entry'] = function()
  set_lines({ '(aa', 'b)' })

  local validate = function(init_pos, direction, ref_pos)
    set_cursor(unpack(init_pos))
    child.lua('MiniAi.move_cursor("' .. direction .. '", "a", ")")')
    eq(get_cursor(), ref_pos)
    type_keys('``')
    eq(get_cursor(), init_pos)
  end

  validate({ 1, 1 }, 'right', { 2, 1 })
  validate({ 2, 1 }, 'left', { 1, 0 })
end

T['move_cursor()']['handles function as textobject spec'] = function()
  -- Should call it only once
  child.lua('_G.n = 0')
  child.lua([[MiniAi.config.custom_textobjects = { c = function() _G.n = _G.n + 1; return { '()c()' } end }]])
  validate_move1d('aabbcc', 0, { 'left', 'a', 'c' }, 4)
  eq(child.lua_get('_G.n'), 1)
end

T['move_cursor()']['works with empty region'] = function()
  validate_move1d('f()', 0, { 'left', 'i', ')' }, 2)
  validate_move1d('f()', 0, { 'right', 'i', ')' }, 2)
end

T['move_cursor()']['works with multibyte characters'] = function()
  validate_move1d(' (ыыы) ', 0, { 'left', 'a', ')' }, 1)
  validate_move1d(' (ыыы) ', 0, { 'right', 'a', ')' }, 8)
end

T['gen_spec'] = new_set()

T['gen_spec']['argument()'] = new_set()

T['gen_spec']['argument()']['works'] = function()
  child.lua([[MiniAi.config.custom_textobjects = { A = MiniAi.gen_spec.argument() }]])

  validate_find1d('f(aa, bb)', 0, { 'a', 'A' }, { 3, 5 })
  validate_find1d('f(aa, bb)', 0, { 'i', 'A' }, { 3, 4 })
end

T['gen_spec']['argument()']['respects `opts.brackets`'] = function()
  child.lua([[MiniAi.config.custom_textobjects = { A = MiniAi.gen_spec.argument({ brackets = { '%b()' } }) }]])

  validate_find1d('(aa, bb)', 0, { 'a', 'A' }, { 2, 4 })
  validate_find1d('[aa, bb]', 0, { 'a', 'A' }, nil)
  validate_find1d('{aa, bb}', 0, { 'a', 'A' }, nil)
end

T['gen_spec']['argument()']['respects `opts.separator`'] = function()
  child.lua([[MiniAi.config.custom_textobjects = {
    A = MiniAi.gen_spec.argument({ separator = ';' }),
    B = MiniAi.gen_spec.argument({ separator = '[,;]' }),
    C = MiniAi.gen_spec.argument({ separator = '%s*,%s*' }),
    D = MiniAi.gen_spec.argument({ separator = ', ,' }),
  }]])

  validate_find1d('(aa, bb; cc, dd)', 0, { 'a', 'A', { n_times = 1 } }, { 2, 8 })
  validate_find1d('(aa, bb; cc, dd)', 0, { 'a', 'A', { n_times = 2 } }, { 8, 15 })

  validate_find1d('(aa, bb; cc, dd)', 0, { 'a', 'B', { n_times = 1 } }, { 2, 4 })
  validate_find1d('(aa, bb; cc, dd)', 0, { 'a', 'B', { n_times = 2 } }, { 4, 7 })
  validate_find1d('(aa, bb; cc, dd)', 0, { 'a', 'B', { n_times = 3 } }, { 8, 11 })
  validate_find1d('(aa, bb; cc, dd)', 0, { 'a', 'B', { n_times = 4 } }, { 12, 15 })

  validate_find1d('(aa , bb , cc)', 0, { 'a', 'C', { n_times = 1 } }, { 2, 6 })
  validate_find1d('(aa , bb , cc)', 0, { 'a', 'C', { n_times = 2 } }, { 4, 8 })
  validate_find1d('(aa , bb , cc)', 0, { 'a', 'C', { n_times = 3 } }, { 9, 13 })

  validate_find1d('(aa , bb , cc)', 0, { 'i', 'C', { n_times = 1 } }, { 2, 3 })
  validate_find1d('(aa , bb , cc)', 0, { 'i', 'C', { n_times = 2 } }, { 7, 8 })
  validate_find1d('(aa , bb , cc)', 0, { 'i', 'C', { n_times = 3 } }, { 12, 13 })

  validate_find1d('(aa, bb , , cc, dd)', 0, { 'a', 'D', { n_times = 1 } }, { 2, 11 })
  validate_find1d('(aa, bb , , cc, dd)', 0, { 'a', 'D', { n_times = 2 } }, { 9, 18 })

  validate_find1d('(aa, bb , , cc, dd)', 0, { 'i', 'D', { n_times = 1 } }, { 2, 7 })
  validate_find1d('(aa, bb , , cc, dd)', 0, { 'i', 'D', { n_times = 2 } }, { 13, 18 })
end

T['gen_spec']['argument()']['respects `opts.exclude_regions`'] = function()
  child.lua([[MiniAi.config.custom_textobjects = {
    A = MiniAi.gen_spec.argument({ exclude_regions = { '".-"' } }),
  }]])

  -- Comma inside `()` should not be excluded
  validate_find1d('(aa, (bb, cc))', 4, { 'a', 'A' }, { 4, 8 })
end

T['gen_spec']['function_call()'] = new_set()

T['gen_spec']['function_call()']['works'] = function()
  child.lua([[MiniAi.config.custom_textobjects = { F = MiniAi.gen_spec.function_call() }]])

  validate_find1d('f.g_h(x)', 0, { 'a', 'F' }, { 1, 8 })
  validate_find1d('f.g_h(x)', 0, { 'i', 'F' }, { 7, 7 })
end

T['gen_spec']['function_call()']['respects `opts.name_pattern`'] = function()
  child.lua([[MiniAi.config.custom_textobjects = { F = MiniAi.gen_spec.function_call({ name_pattern = '[%w_]' }) }]])

  validate_find1d('f.g_h(x)', 0, { 'a', 'F' }, { 3, 8 })
  validate_find1d('f.g_h(x)', 0, { 'i', 'F' }, { 7, 7 })
end

T['gen_spec']['pair()'] = new_set()

T['gen_spec']['pair()']['works'] = function()
  child.lua([[MiniAi.config.custom_textobjects = { x = MiniAi.gen_spec.pair('x', 'y') }]])

  validate_find1d('aaxbbycc', 3, { 'a', 'x' }, { 3, 6 })
  validate_find1d('aaxbbycc', 3, { 'i', 'x' }, { 4, 5 })
end

--stylua: ignore
T['gen_spec']['pair()']['validates arguments'] = function()
  expect.error(function() child.lua([[MiniAi.gen_spec.pair(1, 'y')]]) end, '`left`.*string')
  expect.error(function() child.lua([[MiniAi.gen_spec.pair('x', 1)]]) end, '`right`.*string')

  -- For balanced and greedy types arguments should be single character
  expect.error(function() child.lua([[MiniAi.gen_spec.pair('xx', 'y', { type = 'balanced' })]]) end, '`left`.*single.*balanced')
  expect.error(function() child.lua([[MiniAi.gen_spec.pair('x', 'yy', { type = 'balanced' })]]) end, '`left`.*single.*balanced')
  expect.error(function() child.lua([[MiniAi.gen_spec.pair('xx', 'y', { type = 'greedy' })]]) end, '`left`.*single.*greedy')
  expect.error(function() child.lua([[MiniAi.gen_spec.pair('x', 'yy', { type = 'greedy' })]]) end, '`left`.*single.*greedy')

  -- `opts.type` should be one of pre-defined characters
  expect.error(function() child.lua([[MiniAi.gen_spec.pair('x', 'y', { type = 'aaa' })]]) end, 'opts.type.*one of')
end

T['gen_spec']['pair()']['respects `opts.type`'] = function()
  child.lua([[MiniAi.config.custom_textobjects = {
    _ = MiniAi.gen_spec.pair('_', '_', { type = 'non-balanced' }),
    x = MiniAi.gen_spec.pair('_', '_', { type = 'balanced' }),
    b = MiniAi.gen_spec.pair('(', ')', { type = 'balanced' }),
    y = MiniAi.gen_spec.pair('_', '_', { type = 'greedy' }),
  }]])

  -- Non-balanced pair
  validate_find1d('_a_b_c_', 0, { 'a', '_', { n_times = 1 } }, { 1, 3 })
  validate_find1d('_a_b_c_', 0, { 'a', '_', { n_times = 2 } }, { 3, 5 })
  validate_find1d('_a_b_c_', 0, { 'a', '_', { n_times = 3 } }, { 5, 7 })
  validate_find1d('_a_b_c_', 0, { 'i', '_' }, { 2, 2 })

  -- Balanced pair
  validate_find1d('_a_b_c_', 0, { 'a', 'x', { n_times = 1 } }, { 1, 3 })
  validate_find1d('_a_b_c_', 0, { 'a', 'x', { n_times = 2 } }, { 5, 7 })
  validate_find1d('_a_b_c_', 0, { 'i', 'x' }, { 2, 2 })

  -- Should also work with "special" characters
  validate_find1d('((aa))', 2, { 'a', 'b', { n_times = 1 } }, { 2, 5 })
  validate_find1d('((aa))', 2, { 'a', 'b', { n_times = 2 } }, { 1, 6 })

  -- Greedy pair
  validate_find1d('__a__b_', 0, { 'a', 'y', { n_times = 1 } }, { 1, 5 })
  validate_find1d('__a__b_', 0, { 'a', 'y', { n_times = 2 } }, { 4, 7 })
  validate_find1d('__a__b_', 0, { 'i', 'y' }, { 3, 3 })
end

T['gen_spec']['treesitter()'] = new_set({
  hooks = {
    pre_case = function()
      -- Mock tree-sitter queries
      child.cmd('noautocmd set rtp+=tests/mock-treesitter')

      -- Start editing reference file
      child.cmd('edit tests/mock-treesitter/lua-file.lua')
      child.lua('vim.treesitter.start()')

      -- Define "function definition" textobject
      child.lua([[MiniAi.config.custom_textobjects = {
        F = MiniAi.gen_spec.treesitter({ a = '@function.outer', i = '@function.inner' })
      }]])
    end,
  },
})

T['gen_spec']['treesitter()']['works'] = function()
  local lines = get_lines()
  validate_find(lines, { 1, 0 }, { 'a', 'F' }, { { 3, 1 }, { 5, 3 } })
  validate_find(lines, { 1, 0 }, { 'i', 'F' }, { { 4, 3 }, { 4, 38 } })
  validate_find(lines, { 13, 0 }, { 'a', 'F' }, nil)

  -- Should prefer match on current line over multiline covering
  validate_find(lines, { 4, 0 }, { 'a', 'F' }, { { 4, 10 }, { 4, 38 } })

  -- Should prefer range from metadata instead of node itself. This is useful,
  -- for example, with `#offset!` directive to create more precise captures.
  validate_find(lines, { 9, 0 }, { 'i', 'F' }, { { 8, 3 }, { 10, 13 } })
end

T['gen_spec']['treesitter()']['allows array of captures'] = function()
  child.lua([[MiniAi.config.custom_textobjects = {
    o = MiniAi.gen_spec.treesitter({ a = { '@function.outer', '@return.outer' }, i = { '@function.inner', '@return.inner' } })
  }]])

  local lines = get_lines()
  validate_find(lines, { 10, 2 }, { 'a', 'o' }, { { 10, 3 }, { 10, 13 } })
  validate_find(lines, { 10, 2 }, { 'i', 'o' }, { { 10, 10 }, { 10, 13 } })

  validate_find(lines, { 10, 2 }, { 'a', 'o', { n_times = 2 } }, { { 7, 7 }, { 11, 3 } })
  validate_find(lines, { 10, 2 }, { 'i', 'o', { n_times = 2 } }, { { 8, 3 }, { 10, 13 } })

  validate_find(lines, { 13, 0 }, { 'a', 'o' }, { { 13, 1 }, { 13, 8 } })
end

T['gen_spec']['treesitter()']['respects `opts.use_nvim_treesitter`'] = function()
  child.lua([[MiniAi.config.custom_textobjects = {
    F = MiniAi.gen_spec.treesitter({ a = '@function.outer', i = '@function.inner' }),
    o = MiniAi.gen_spec.treesitter({ a = '@plugin_return', i = '@plugin_return' }),
    O = MiniAi.gen_spec.treesitter(
      { a = '@plugin_return', i = '@plugin_return' },
      { use_nvim_treesitter = true }
    )
  }]])
  local lines = get_lines()

  -- By default it should be `false`
  validate_find(lines, { 1, 0 }, { 'a', 'F' }, { { 3, 1 }, { 5, 3 } })
  validate_find(lines, { 1, 0 }, { 'a', 'o' }, nil)
  validate_find(lines, { 1, 0 }, { 'a', 'O' }, nil)

  child.cmd('noautocmd set rtp+=tests/dir-ai/mock-nvim-treesitter')
  validate_find(lines, { 1, 0 }, { 'a', 'F' }, { { 3, 1 }, { 5, 3 } })
  validate_find(lines, { 1, 0 }, { 'a', 'o' }, nil)
  validate_find(lines, { 1, 0 }, { 'a', 'O' }, { { 4, 3 }, { 4, 38 } })

  -- Should prefer range from metadata instead of node itself. This is useful,
  -- for example, with `#offset!` directive to create more precise captures.
  validate_find(lines, { 9, 0 }, { 'i', 'F' }, { { 8, 3 }, { 10, 13 } })
end

T['gen_spec']['treesitter()']['works with directives'] = function()
  child.lua([[MiniAi.config.custom_textobjects = {
    S = MiniAi.gen_spec.treesitter({ a = '@string', i = '@string_offset' }),
  }]])
  local lines = get_lines()
  validate_find(lines, { 9, 9 }, { 'i', 'S' }, { { 9, 10 }, { 9, 16 } })
end

T['gen_spec']['treesitter()']['works with quantified captures'] = function()
  if child.fn.has('nvim-0.10') == 0 then
    MiniTest.skip('`Query:iter_matches()` returning several nodes requires Neovim>=0.10')
  end

  child.lua([[MiniAi.config.custom_textobjects = {
    P = MiniAi.gen_spec.treesitter({ a = '@parameter.outer', i = '@parameter.inner' }),
  }]])

  -- "Around" parameter should include whitespace and comma
  local lines = get_lines()
  validate_find(lines, { 3, 0 }, { 'i', 'P' }, { { 3, 14 }, { 3, 14 } })
  validate_find(lines, { 3, 0 }, { 'a', 'P' }, { { 3, 14 }, { 3, 15 } })
  validate_find(lines, { 3, 0 }, { 'i', 'P', { n_times = 2 } }, { { 3, 17 }, { 3, 18 } })
  validate_find(lines, { 3, 0 }, { 'a', 'P', { n_times = 2 } }, { { 3, 15 }, { 3, 18 } })
  validate_find(lines, { 3, 0 }, { 'i', 'P', { n_times = 3 } }, { { 3, 21 }, { 3, 23 } })
  validate_find(lines, { 3, 0 }, { 'a', 'P', { n_times = 3 } }, { { 3, 19 }, { 3, 23 } })
end

T['gen_spec']['treesitter()']['works with parent of injected language'] = function()
  if child.fn.has('nvim-0.10') == 0 then MiniTest.skip('`LanguageTree:parent()` requires Neovim>=0.10') end

  local lines = {
    'local foo = function()',
    '  vim.cmd([[',
    'set cursorline',
    ']])',
    'end',
  }
  validate_find(lines, { 3, 0 }, { 'a', 'F' }, { { 1, 13 }, { 5, 3 } })
end

T['gen_spec']['treesitter()']['respects plugin options'] = function()
  local lines = get_lines()

  -- `opts.n_lines`
  child.lua('MiniAi.config.n_lines = 0')
  validate_find(lines, { 9, 0 }, { 'a', 'F' }, nil)

  -- `opts.search_method`
  child.lua('MiniAi.config.n_lines = 50')
  child.lua('MiniAi.config.search_method = "next"')
  validate_find(lines, { 9, 0 }, { 'a', 'F' }, nil)
end

T['gen_spec']['treesitter()']['validates `ai_captures` argument'] = function()
  local validate = function(args)
    expect.error(function() child.lua('MiniAi.gen_spec.treesitter(...)', { args }) end, 'ai_captures')
  end

  validate('a')
  validate({})
  -- Each `a` and `i` should be a string starting with '@'
  validate({ a = 1 })
  validate({ a = 'function.outer' })
  validate({ a = { 1 } })
  validate({ a = { 'function.outer' } })
  validate({ i = 1 })
  validate({ i = 'function.inner' })
  validate({ i = { 1 } })
  validate({ i = { 'function.inner' } })
end

T['gen_spec']['treesitter()']['validates builtin treesitter presence'] = function()
  -- Query
  child.bo.filetype = 'vim'
  expect.error(
    function() child.lua('MiniAi.find_textobject("a", "F")') end,
    '%(mini%.ai%) Can not get query for buffer 1 and language "vim"%.'
  )

  -- - Should show local language in error message
  child.cmd('edit tmp.lua')
  set_lines({ 'vim.cmd([[', 'setlocal cursorline', ']])' })
  set_cursor(2, 0)
  expect.error(
    function() child.lua('MiniAi.find_textobject("a", "F")') end,
    '%(mini%.ai%) Can not get query for buffer 2 and language "vim"%.'
  )

  -- Parser
  child.cmd('enew')
  child.bo.filetype = 'aaa'
  expect.error(
    function() child.lua('MiniAi.find_textobject("a", "F")') end,
    '%(mini%.ai%) Can not get parser for buffer 3 and language "aaa"%.'
  )

  -- - Should respect registered language for a filetype
  child.lua('vim.treesitter.language.register("my_aaa", "aaa")')
  expect.error(
    function() child.lua('MiniAi.find_textobject("a", "F")') end,
    '%(mini%.ai%) Can not get parser for buffer 3 and language "my_aaa"%.'
  )

  if child.fn.has('nvim-0.10') == 0 then return end
  -- - Should show each language
  child.cmd('enew')
  child.bo.filetype = 'help'
  set_lines({ '>vim', '    set cursorline', '<' })
  set_cursor(2, 0)
  expect.error(
    function() child.lua('MiniAi.find_textobject("a", "F")') end,
    '%(mini%.ai%) Can not get query for buffer 3 and languages "vimd?o?c?", "vimd?o?c?"%.'
  )

  -- - Should show each language once
  child.cmd('edit tmp.vim')
  set_lines({ 'set indentexpr=VimIndent()' })
  set_cursor(1, 0)
  expect.error(
    function() child.lua('MiniAi.find_textobject("a", "F")') end,
    '%(mini%.ai%) Can not get query for buffer 4 and language "vim"%.'
  )
end

T['gen_spec']['user_prompt()'] = new_set()

-- More tests are done in `T['Builtin']['User prompt']`
T['gen_spec']['user_prompt()']['works'] = function()
  -- Define custom "user prompt" textobject
  child.lua('MiniAi.config.custom_textobjects = { ["/"] = MiniAi.gen_spec.user_prompt() }')

  -- Single character edges
  validate_tobj1d('__e__o__', 0, 'a/e<CR>o<CR>', { 3, 6 })
  validate_tobj1d('__e__o__', 0, 'i/e<CR>o<CR>', { 4, 5 })

  -- Multiple character edges
  validate_tobj1d('__ef__op__', 0, 'a/ef<CR>op<CR>', { 3, 8 })
  validate_tobj1d('__ef__op__', 0, 'i/ef<CR>op<CR>', { 5, 6 })

  -- Supports dot-repeat
  set_lines({ '_e--o_', '+e---o+' })
  set_cursor(1, 0)
  type_keys('da', '/', 'e<CR>', 'o<CR>')
  eq(get_lines(), { '__', '+e---o+' })
  type_keys('j', '.')
  eq(get_lines(), { '__', '++' })

  set_lines({ '_r--t_' })
  set_cursor(1, 0)
  type_keys('di', '/', 'r<CR>', 't<CR>')
  eq(get_lines(), { '_rt_' })
end

local validate_select = function(lines, cursor, args, expected)
  child.ensure_normal_mode()
  set_lines(lines)
  set_cursor(unpack(cursor))
  child.lua([[MiniAi.select_textobject(...)]], args)

  local expected_mode = (args[3] or {}).vis_mode or 'v'
  eq(get_mode(), vim.api.nvim_replace_termcodes(expected_mode, true, true, true))

  -- Allow supplying number items to verify linewise selection
  local expected_from = type(expected[1]) == 'number' and expected[1] or { expected[1][1], expected[1][2] - 1 }
  local expected_to = type(expected[2]) == 'number' and expected[2] or { expected[2][1], expected[2][2] - 1 }
  child.expect_visual_marks(expected_from, expected_to)
end

local validate_select1d = function(line, column, args, expected)
  validate_select({ line }, { 1, column }, args, { { 1, expected[1] }, { 1, expected[2] } })
end

T['select_textobject()'] = new_set()

T['select_textobject()']['works'] = function() validate_select1d('aa(bb)', 3, { 'a', ')' }, { 3, 6 }) end

T['select_textobject()']['respects `ai_type` argument'] = function()
  validate_select1d('aa(bb)', 3, { 'i', ')' }, { 4, 5 })
end

T['select_textobject()']['respects `id` argument'] = function()
  validate_select1d('aa[bb]', 3, { 'a', ']' }, { 3, 6 })
  validate_select1d('aa[bb]', 3, { 'i', ']' }, { 4, 5 })
end

T['select_textobject()']['respects `opts` argument'] = function()
  validate_select1d('aa(bb)cc(dd)', 4, { 'a', ')', { n_times = 2 } }, { 9, 12 })
end

T['select_textobject()']['respects `opts.vis_mode`'] = function()
  local lines, cursor = { '(a', 'a', 'a)' }, { 2, 0 }
  validate_select(lines, cursor, { 'a', ')', { vis_mode = 'v' } }, { { 1, 1 }, { 3, 2 } })
  validate_select(lines, cursor, { 'a', ')', { vis_mode = 'V' } }, { 1, 3 })
  validate_select(lines, cursor, { 'a', ')', { vis_mode = '<C-v>' } }, { { 1, 1 }, { 3, 2 } })
end

T['select_textobject()']['works with empty region'] = function() validate_select1d('a()', 0, { 'i', ')' }, { 3, 3 }) end

T['select_textobject()']['allows selecting past line end'] = function()
  child.o.virtualedit, child.o.whichwrap = 'block', 'b,s'
  validate_select({ '(', 'a', ')' }, { 2, 0 }, { 'i', ')' }, { { 1, 2 }, { 2, 2 } })
  eq(child.o.virtualedit, 'block')
  eq(child.o.whichwrap, 'b,s')
end

T['select_textobject()']["respects 'selection=exclusive'"] = function()
  child.o.selection = 'exclusive'

  local validate = function(ai_type, after)
    set_lines({ ' (aaa) ' })
    set_cursor(1, 3)
    child.lua([[MiniAi.select_textobject(...)]], { ai_type, ')' })
    type_keys('d')
    eq(get_lines(), { after })
  end

  validate('i', ' () ')
  validate('a', '  ')
end

T['select_textobject()']['respects `vis_mode` from textobject region'] = function()
  -- Should respect `vis_mode` in a region
  local validate = function(tobj_vis_mode, type_vis_mode)
    local lua_cmd = string.format(
      [[_G.cur_line = function(ai_type, id, opts)
        return { from = { line = vim.fn.line('.'), col = 1 }, vis_mode = '%s' }
      end]],
      tobj_vis_mode
    )
    child.lua(lua_cmd)
    child.lua([[MiniAi.config.custom_textobjects = { c = _G.cur_line }]])

    set_lines({ 'aaaa', 'bbbb' })
    type_keys(type_vis_mode, 'ac')
    eq(child.fn.mode(), tobj_vis_mode)

    child.ensure_normal_mode()
  end

  validate('v', 'V')
  validate('v', '\22')
  validate('V', 'v')
  validate('V', '\22')
  validate('\22', 'v')
  validate('\22', 'V')
end

T['Search method'] = new_set()

T['Search method']['works with "cover"'] = function()
  local validate = function(lines, cursor, expected)
    validate_find(lines, cursor, { 'a', ')', { search_method = 'cover' } }, expected)
  end

  local validate1d = function(line, column, expected)
    validate_find1d(line, column, { 'a', ')', { search_method = 'cover' } }, expected)
  end

  -- Works (on same line and on multiple lines)
  validate1d('aa (bb) cc', 4, { 4, 7 })
  validate1d('aa (bb) cc', 0, nil)
  validate1d('aa (bb) cc', 9, nil)
  validate({ '(', 'a', ')' }, { 2, 0 }, { { 1, 1 }, { 3, 1 } })

  -- Works when cursor is on edge
  validate1d('aa(bb)', 2, { 3, 6 })
  validate1d('aa(bb)', 5, { 3, 6 })

  -- Should prefer smallest covering
  validate1d('((a))', 2, { 2, 4 })

  -- Should ignore any non-covering textobject on current line
  validate({ '(', '(aa) bb (cc)', ')' }, { 2, 5 }, { { 1, 1 }, { 3, 1 } })

  -- Works with `n_times`
  local validate_n_times = function(lines, cursor, n_times, expected)
    validate_find(lines, cursor, { 'a', ')', { search_method = 'cover', n_times = n_times } }, expected)
  end

  local lines, cursor = { '(', '(aa (bb) (cc))', ')' }, { 2, 5 }
  validate_n_times(lines, cursor, 1, { { 2, 5 }, { 2, 8 } })
  validate_n_times(lines, cursor, 2, { { 2, 1 }, { 2, 14 } })
  validate_n_times(lines, cursor, 3, { { 1, 1 }, { 3, 1 } })
end

T['Search method']['works with "cover" in Operator-pending mode'] = function()
  child.lua([[MiniAi.config.search_method = 'cover']])

  for i = 3, 6 do
    validate_edit1d('(aa(bb))', i, '(aa)', 3, 'ca)')
    validate_edit1d('(aa(bb))', i, '(aa)', 3, 'da)')

    validate_edit1d('(aa(bb))', i, '(aa())', 4, 'ci)')
    validate_edit1d('(aa(bb))', i, '(aa())', 4, 'di)')
  end
end

T['Search method']['works with "cover_or_next"'] = function()
  local validate = function(lines, cursor, expected)
    validate_find(lines, cursor, { 'a', ')', { search_method = 'cover_or_next' } }, expected)
  end

  local validate1d = function(line, column, expected)
    validate_find1d(line, column, { 'a', ')', { search_method = 'cover_or_next' } }, expected)
  end

  -- Works (on same line and on multiple lines)
  validate1d('aa (bb)', 0, { 4, 7 })
  validate({ 'aa', '(bb)' }, { 1, 0 }, { { 2, 1 }, { 2, 4 } })

  -- Works when cursor is on edge
  validate1d('aa(bb)', 2, { 3, 6 })
  validate1d('aa(bb)', 5, { 3, 6 })

  -- Should prefer covering textobject if both are on the same line
  validate1d('(aa) (bb)', 2, { 1, 4 })
  validate1d('(aa (bb))', 2, { 1, 9 })

  -- Should prefer covering textobject if both are not on the same line
  validate({ '(aa', ') (bb)' }, { 1, 1 }, { { 1, 1 }, { 2, 1 } })

  -- Should prefer next textobject if covering is not on same line
  validate({ '(a (bb)', ')' }, { 1, 1 }, { { 1, 4 }, { 1, 7 } })

  -- Should ignore presence of "previous" textobject (even on same line)
  validate({ '(aa) bb (cc)' }, { 1, 5 }, { { 1, 9 }, { 1, 12 } })
  validate({ '(aa) bb', '(cc)' }, { 1, 5 }, { { 2, 1 }, { 2, 4 } })
  validate({ '(aa) (', '(bb) cc)' }, { 2, 5 }, { { 1, 6 }, { 2, 8 } })

  -- Should choose closest textobject based on distance between left edges
  validate1d('aa(bb(cc)dddddddddd)', 0, { 3, 20 })

  -- Works with `n_times`
  local validate_n_times = function(lines, cursor, n_times, expected)
    validate_find(lines, cursor, { 'a', ')', { search_method = 'cover_or_next', n_times = n_times } }, expected)
  end

  local lines, cursor = { '(', 'aa (bb) (cc) )' }, { 2, 0 }
  validate_n_times(lines, cursor, 1, { { 2, 4 }, { 2, 7 } })
  validate_n_times(lines, cursor, 2, { { 2, 9 }, { 2, 12 } })
  validate_n_times(lines, cursor, 3, { { 1, 1 }, { 2, 14 } })
end

T['Search method']['works with "cover_or_next" in Operator-pending mode'] = function()
  child.lua([[MiniAi.config.search_method = 'cover_or_next']])

  for i = 4, 10 do
    validate_edit1d('(aa)bbb(cc)', i, '(aa)bbb', 7, 'ca)')
    validate_edit1d('(aa)bbb(cc)', i, '(aa)bbb', 6, 'da)')

    validate_edit1d('(aa)bbb(cc)', i, '(aa)bbb()', 8, 'ci)')
    validate_edit1d('(aa)bbb(cc)', i, '(aa)bbb()', 8, 'di)')
  end
end

T['Search method']['works with "cover_or_prev"'] = function()
  local validate = function(lines, cursor, expected)
    validate_find(lines, cursor, { 'a', ')', { search_method = 'cover_or_prev' } }, expected)
  end

  local validate1d = function(line, column, expected)
    validate_find1d(line, column, { 'a', ')', { search_method = 'cover_or_prev' } }, expected)
  end

  -- Works (on same line and on multiple lines)
  validate1d('(aa) bb', 5, { 1, 4 })
  validate({ '(aa)', 'bb' }, { 2, 0 }, { { 1, 1 }, { 1, 4 } })

  -- Works when cursor is on edge
  validate1d('aa(bb)', 2, { 3, 6 })
  validate1d('aa(bb)', 5, { 3, 6 })

  -- Should prefer covering textobject if both are on the same line
  validate1d('(aa) (bb)', 6, { 6, 9 })
  validate1d('((aa) bb)', 6, { 1, 9 })

  -- Should prefer covering textobject if both are not on the same line
  validate({ '((aa)', 'bb)' }, { 2, 0 }, { { 1, 1 }, { 2, 3 } })

  -- Should prefer previous textobject if covering is not on same line
  validate({ '((aa) b', ')' }, { 1, 6 }, { { 1, 2 }, { 1, 5 } })

  -- Should ignore presence of "next" textobject (even on same line)
  validate({ '(aa) bb (cc)' }, { 1, 5 }, { { 1, 1 }, { 1, 4 } })
  validate({ '(aa)', 'bb (cc)' }, { 2, 0 }, { { 1, 1 }, { 1, 4 } })
  validate({ '(aa) (', 'bb (cc))' }, { 2, 0 }, { { 1, 6 }, { 2, 8 } })

  -- Should choose closest textobject based on distance between right edges
  validate1d('(aaaaaaaaaa(bb)cc)dd', 19, { 1, 18 })

  -- Works with `n_times`
  local validate_n_times = function(lines, cursor, n_times, expected)
    validate_find(lines, cursor, { 'a', ')', { search_method = 'cover_or_prev', n_times = n_times } }, expected)
  end

  local lines, cursor = { '(', '(aa) (bb) cc )' }, { 2, 10 }
  validate_n_times(lines, cursor, 1, { { 2, 6 }, { 2, 9 } })
  validate_n_times(lines, cursor, 2, { { 2, 1 }, { 2, 4 } })
  validate_n_times(lines, cursor, 3, { { 1, 1 }, { 2, 14 } })
end

T['Search method']['works with "cover_or_prev" in Operator-pending mode'] = function()
  child.lua([[MiniAi.config.search_method = 'cover_or_prev']])

  for i = 0, 6 do
    validate_edit1d('(aa)bbb(cc)', i, 'bbb(cc)', 0, 'ca)')
    validate_edit1d('(aa)bbb(cc)', i, 'bbb(cc)', 0, 'da)')

    validate_edit1d('(aa)bbb(cc)', i, '()bbb(cc)', 1, 'ci)')
    validate_edit1d('(aa)bbb(cc)', i, '()bbb(cc)', 1, 'di)')
  end
end

T['Search method']['works with "cover_or_nearest"'] = function()
  local validate = function(lines, cursor, expected)
    validate_find(lines, cursor, { 'a', ')', { search_method = 'cover_or_nearest' } }, expected)
  end

  local validate1d = function(line, column, expected)
    validate_find1d(line, column, { 'a', ')', { search_method = 'cover_or_nearest' } }, expected)
  end

  -- Works (on same line and on multiple lines)
  validate1d('(aa) bbb (cc)', 5, { 1, 4 })
  validate1d('(aa) bbb (cc)', 6, { 1, 4 })
  validate1d('(aa) bbb (cc)', 7, { 10, 13 })

  validate({ '(aa)', 'bbb', '(cc)' }, { 2, 0 }, { { 1, 1 }, { 1, 4 } })
  validate({ '(aa)', 'bbb', '(cc)' }, { 2, 1 }, { { 1, 1 }, { 1, 4 } })
  validate({ '(aa)', 'bbb', '(cc)' }, { 2, 2 }, { { 3, 1 }, { 3, 4 } })

  -- Works when cursor is on edge
  validate1d('aa(bb)', 2, { 3, 6 })
  validate1d('aa(bb)', 5, { 3, 6 })

  -- Should prefer covering textobject if alternative is on the same line
  validate1d('((aa)  (bb))', 5, { 1, 12 })
  validate1d('((aa)  (bb))', 6, { 1, 12 })

  -- Should prefer covering textobject if both are not on the same line
  validate({ '(aa', ') (bb)' }, { 1, 1 }, { { 1, 1 }, { 2, 1 } })
  validate({ '((aa)', 'bb)' }, { 2, 0 }, { { 1, 1 }, { 2, 3 } })

  -- Should prefer nearest textobject if covering is not on same line
  validate({ '((aa) bbb (cc)', ')' }, { 1, 6 }, { { 1, 2 }, { 1, 5 } })
  validate({ '((aa) bbb (cc)', ')' }, { 1, 7 }, { { 1, 2 }, { 1, 5 } })
  validate({ '((aa) bbb (cc)', ')' }, { 1, 8 }, { { 1, 11 }, { 1, 14 } })

  -- Should choose closest textobject based on minimum distance between
  -- corresponding edges
  local validate_distance = function(region_cols, expected)
    local reference_region = { from = { line = 1, col = region_cols[1] }, to = { line = 1, col = region_cols[2] } }
    validate_find1d(
      '(aa)bbb(cc)',
      0,
      { 'a', ')', { search_method = 'cover_or_nearest', reference_region = reference_region } },
      expected
    )
  end

  validate_distance({ 2, 5 }, { 1, 4 })
  validate_distance({ 2, 9 }, { 1, 4 })
  validate_distance({ 5, 6 }, { 1, 4 })
  validate_distance({ 5, 7 }, { 1, 4 })
  validate_distance({ 6, 7 }, { 8, 11 })
  validate_distance({ 3, 10 }, { 8, 11 })
  validate_distance({ 7, 10 }, { 8, 11 })

  -- Works with `n_times`
  local validate_n_times = function(lines, cursor, n_times, expected)
    validate_find(lines, cursor, { 'a', ')', { search_method = 'cover_or_nearest', n_times = n_times } }, expected)
  end

  local lines, cursor = { '(aaaaa', '(bb) cc (dd))' }, { 2, 5 }
  validate_n_times(lines, cursor, 1, { { 2, 1 }, { 2, 4 } })
  validate_n_times(lines, cursor, 2, { { 2, 9 }, { 2, 12 } })
  -- It enters cycle because two textobjects are nearest to each other
  validate_n_times(lines, cursor, 3, { { 2, 1 }, { 2, 4 } })
end

T['Search method']['works with "cover_or_nearest" in Operator-pending mode'] = function()
  child.lua([[MiniAi.config.search_method = 'cover_or_nearest']])

  for i = 0, 5 do
    validate_edit1d('(aa)bbb(cc)', i, 'bbb(cc)', 0, 'ca)')
    validate_edit1d('(aa)bbb(cc)', i, 'bbb(cc)', 0, 'da)')

    validate_edit1d('(aa)bbb(cc)', i, '()bbb(cc)', 1, 'ci)')
    validate_edit1d('(aa)bbb(cc)', i, '()bbb(cc)', 1, 'di)')
  end
  for i = 6, 10 do
    validate_edit1d('(aa)bbb(cc)', i, '(aa)bbb', 7, 'ca)')
    validate_edit1d('(aa)bbb(cc)', i, '(aa)bbb', 6, 'da)')

    validate_edit1d('(aa)bbb(cc)', i, '(aa)bbb()', 8, 'ci)')
    validate_edit1d('(aa)bbb(cc)', i, '(aa)bbb()', 8, 'di)')
  end
end

T['Search method']['works with "next"'] = function()
  local validate = function(lines, cursor, expected)
    validate_find(lines, cursor, { 'a', ')', { search_method = 'next' } }, expected)
  end

  local validate1d = function(line, column, expected)
    validate_find1d(line, column, { 'a', ')', { search_method = 'next' } }, expected)
  end

  -- Works (on same line and on multiple lines)
  validate1d('aa (bb)', 0, { 4, 7 })
  validate({ 'aa', '(bb)' }, { 1, 0 }, { { 2, 1 }, { 2, 4 } })

  -- Works when cursor is on edge (should prefer next one)
  validate1d('aa(bb)(cc)', 2, { 7, 10 })
  validate1d('aa(bb)(cc)', 5, { 7, 10 })

  -- Should NOT prefer covering textobject if both are on the same line
  validate1d('(aa) (bb)', 2, { 6, 9 })
  validate1d('(aa (bb))', 2, { 5, 8 })

  -- Should NOT prefer covering textobject if both are not on the same line
  validate({ '(aa', ') (bb)' }, { 1, 1 }, { { 2, 3 }, { 2, 6 } })

  -- Should prefer next textobject if covering is not on same line
  validate({ '(a (bb)', ')' }, { 1, 1 }, { { 1, 4 }, { 1, 7 } })

  -- Should ignore presence of "previous" textobject (even on same line)
  validate({ '(aa) bb (cc)' }, { 1, 5 }, { { 1, 9 }, { 1, 12 } })
  validate({ '(aa) bb', '(cc)' }, { 1, 5 }, { { 2, 1 }, { 2, 4 } })
  validate({ '(aa) (', '(bb) cc)' }, { 2, 5 }, nil)

  -- Should choose closest textobject based on distance between left edges
  validate1d('aa(bb(cc)dddddddddd)', 0, { 3, 20 })

  -- Works with `n_times`
  local validate_n_times = function(lines, cursor, n_times, expected)
    validate_find(lines, cursor, { 'a', ')', { search_method = 'next', n_times = n_times } }, expected)
  end

  local lines, cursor = { '(', 'aa (bb) (cc) )' }, { 2, 0 }
  validate_n_times(lines, cursor, 1, { { 2, 4 }, { 2, 7 } })
  validate_n_times(lines, cursor, 2, { { 2, 9 }, { 2, 12 } })
  validate_n_times(lines, cursor, 3, nil)
end

T['Search method']['works with "next" in Operator-pending mode'] = function()
  child.lua([[MiniAi.config.search_method = 'next']])

  for i = 4, 8 do
    validate_edit1d('(aa)(bbb)(cc)', i, '(aa)(bbb)', 9, 'ca)')
    validate_edit1d('(aa)(bbb)(cc)', i, '(aa)(bbb)', 8, 'da)')

    validate_edit1d('(aa)(bbb)(cc)', i, '(aa)(bbb)()', 10, 'ci)')
    validate_edit1d('(aa)(bbb)(cc)', i, '(aa)(bbb)()', 10, 'di)')
  end
end

T['Search method']['works with "prev"'] = function()
  local validate = function(lines, cursor, expected)
    validate_find(lines, cursor, { 'a', ')', { search_method = 'prev' } }, expected)
  end

  local validate1d = function(line, column, expected)
    validate_find1d(line, column, { 'a', ')', { search_method = 'prev' } }, expected)
  end

  -- Works (on same line and on multiple lines)
  validate1d('(aa) bb', 5, { 1, 4 })
  validate({ '(aa)', 'bb' }, { 2, 0 }, { { 1, 1 }, { 1, 4 } })

  -- Works when cursor is on edge
  validate1d('(aa)(bb)', 4, { 1, 4 })
  validate1d('(aa)(bb)', 7, { 1, 4 })

  -- Should NOT prefer covering textobject if both are on the same line
  validate1d('(aa) (bb)', 6, { 1, 4 })
  validate1d('((aa) bb)', 6, { 2, 5 })

  -- Should NOT prefer covering textobject if both are not on the same line
  validate({ '((aa)', 'bb)' }, { 2, 0 }, { { 1, 2 }, { 1, 5 } })

  -- Should ignore presence of "next" textobject (even on same line)
  validate({ '(aa) bb (cc)' }, { 1, 5 }, { { 1, 1 }, { 1, 4 } })
  validate({ '(aa)', 'bb (cc)' }, { 2, 0 }, { { 1, 1 }, { 1, 4 } })
  validate({ '(aa) (', 'bb (cc))' }, { 2, 0 }, { { 1, 1 }, { 1, 4 } })

  -- Should choose closest textobject based on distance between right edges
  validate1d('(aaaaaaaaaa(bb)cc)dd', 19, { 1, 18 })

  -- Works with `n_times`
  local validate_n_times = function(lines, cursor, n_times, expected)
    validate_find(lines, cursor, { 'a', ')', { search_method = 'prev', n_times = n_times } }, expected)
  end

  local lines, cursor = { '(', '(aa) (bb) cc )' }, { 2, 10 }
  validate_n_times(lines, cursor, 1, { { 2, 6 }, { 2, 9 } })
  validate_n_times(lines, cursor, 2, { { 2, 1 }, { 2, 4 } })
  validate_n_times(lines, cursor, 3, nil)
end

T['Search method']['works with "prev" in Operator-pending mode'] = function()
  child.lua([[MiniAi.config.search_method = 'prev']])

  for i = 4, 8 do
    validate_edit1d('(aa)(bbb)(cc)', i, '(bbb)(cc)', 0, 'ca)')
    validate_edit1d('(aa)(bbb)(cc)', i, '(bbb)(cc)', 0, 'da)')

    validate_edit1d('(aa)(bbb)(cc)', i, '()(bbb)(cc)', 1, 'ci)')
    validate_edit1d('(aa)(bbb)(cc)', i, '()(bbb)(cc)', 1, 'di)')
  end
end

T['Search method']['works with "nearest"'] = function()
  local validate = function(lines, cursor, expected)
    validate_find(lines, cursor, { 'a', ')', { search_method = 'nearest' } }, expected)
  end

  local validate1d = function(line, column, expected)
    validate_find1d(line, column, { 'a', ')', { search_method = 'nearest' } }, expected)
  end

  -- Works (on same line and on multiple lines)
  validate1d('(aa) bbb (cc)', 5, { 1, 4 })
  validate1d('(aa) bbb (cc)', 6, { 1, 4 })
  validate1d('(aa) bbb (cc)', 7, { 10, 13 })

  validate({ '(aa)', 'bbb', '(cc)' }, { 2, 0 }, { { 1, 1 }, { 1, 4 } })
  validate({ '(aa)', 'bbb', '(cc)' }, { 2, 1 }, { { 1, 1 }, { 1, 4 } })
  validate({ '(aa)', 'bbb', '(cc)' }, { 2, 2 }, { { 3, 1 }, { 3, 4 } })

  -- Works when cursor is on edge
  validate1d('(aa)(bb)(cc)', 4, { 1, 4 })
  validate1d('(aa)(bb)(cc)', 7, { 9, 12 })

  -- Should NOT prefer covering textobject if alternative is on the same line
  validate1d('((aa)   (bb))', 5, { 2, 5 })
  validate1d('((aa)   (bb))', 7, { 9, 12 })
  -- Here is it still left because distance is measured for empty region at
  -- cursor (for which left block is closer)
  validate1d('((aa)  (bb))', 6, { 2, 5 })

  -- Should NOT prefer covering textobject if both are not on the same line
  validate({ '(aa', ') (bb)' }, { 1, 1 }, { { 2, 3 }, { 2, 6 } })
  validate({ '((aa)', 'bb)' }, { 2, 0 }, { { 1, 2 }, { 1, 5 } })

  -- Should prefer nearest textobject if covering is not on same line
  validate({ '((aa) bbb (cc)', ')' }, { 1, 6 }, { { 1, 2 }, { 1, 5 } })
  validate({ '((aa) bbb (cc)', ')' }, { 1, 7 }, { { 1, 2 }, { 1, 5 } })
  validate({ '((aa) bbb (cc)', ')' }, { 1, 8 }, { { 1, 11 }, { 1, 14 } })

  -- Should choose closest textobject based on minimum distance between
  -- corresponding edges
  local validate_distance = function(region_cols, expected)
    local reference_region = { from = { line = 1, col = region_cols[1] }, to = { line = 1, col = region_cols[2] } }
    validate_find1d(
      '(aa)bbb(cc)',
      0,
      { 'a', ')', { search_method = 'nearest', reference_region = reference_region } },
      expected
    )
  end

  validate_distance({ 2, 5 }, { 1, 4 })
  validate_distance({ 2, 9 }, { 1, 4 })
  validate_distance({ 5, 6 }, { 1, 4 })
  validate_distance({ 5, 7 }, { 1, 4 })
  validate_distance({ 6, 7 }, { 8, 11 })
  validate_distance({ 3, 10 }, { 8, 11 })
  validate_distance({ 7, 10 }, { 8, 11 })

  -- Works with `n_times`
  local validate_n_times = function(lines, cursor, n_times, expected)
    validate_find(lines, cursor, { 'a', ')', { search_method = 'nearest', n_times = n_times } }, expected)
  end

  local lines, cursor = { '(aaaaa', '(bb) cc (dd))' }, { 2, 5 }
  validate_n_times(lines, cursor, 1, { { 2, 1 }, { 2, 4 } })
  validate_n_times(lines, cursor, 2, { { 2, 9 }, { 2, 12 } })
  -- It enters cycle because two textobjects are nearest to each other
  validate_n_times(lines, cursor, 3, { { 2, 1 }, { 2, 4 } })
end

T['Search method']['works with "nearest" in Operator-pending mode'] = function()
  child.lua([[MiniAi.config.search_method = 'nearest']])

  for i = 4, 6 do
    validate_edit1d('(aa)(bbb)(cc)', i, '(bbb)(cc)', 0, 'ca)')
    validate_edit1d('(aa)(bbb)(cc)', i, '(bbb)(cc)', 0, 'da)')

    validate_edit1d('(aa)(bbb)(cc)', i, '()(bbb)(cc)', 1, 'ci)')
    validate_edit1d('(aa)(bbb)(cc)', i, '()(bbb)(cc)', 1, 'di)')
  end
  for i = 7, 8 do
    validate_edit1d('(aa)(bbb)(cc)', i, '(aa)(bbb)', 9, 'ca)')
    validate_edit1d('(aa)(bbb)(cc)', i, '(aa)(bbb)', 8, 'da)')

    validate_edit1d('(aa)(bbb)(cc)', i, '(aa)(bbb)()', 10, 'ci)')
    validate_edit1d('(aa)(bbb)(cc)', i, '(aa)(bbb)()', 10, 'di)')
  end
end

-- Integration tests ==========================================================
T['Textobject'] = new_set()

T['Textobject']['works in Visual mode'] = function()
  local lines, cursor = { 'aa(bb', 'cccc', 'dd)ee' }, { 2, 0 }
  validate_tobj(lines, cursor, 'a)', { { 1, 3 }, { 3, 3 } }, 'v')
  validate_tobj(lines, cursor, 'a)', { 1, 3 }, 'V')
  validate_tobj(lines, cursor, 'a)', { { 1, 3 }, { 3, 3 } }, '<C-v>')

  -- Exits Visual mode if textobject is not found
  set_lines({ 'aa' })
  set_cursor(1, 0)

  type_keys('v', 'a)')
  eq(get_cursor(), { 1, 0 })
  expect.match(get_latest_message(), 'a%)')
  eq(get_mode(), 'n')
end

T['Textobject']['works in Operator-pending mode'] = function()
  local lines, cursor = { 'aa(bb', 'cccc', 'dd)ee' }, { 2, 0 }
  validate_edit(lines, cursor, { 'aaee' }, { 1, 2 }, 'da)')
  validate_edit(lines, cursor, { 'aaee' }, { 1, 2 }, 'dva)')
  validate_edit(lines, cursor, { '' }, { 1, 0 }, 'dVa)')
  validate_edit(lines, cursor, { 'aabb', 'ccc', 'ddee' }, { 1, 2 }, 'd<C-v>a)')
end

T['Textobject']['can be cancelled'] = function()
  local validate = function(keys, mode)
    set_lines({ 'aaa' })
    set_cursor(1, 1)
    type_keys(keys, '<Esc>')

    eq(child.api.nvim_get_mode().mode, mode)
    type_keys('<Esc>')

    eq(get_lines(), { 'aaa' })
    eq(get_cursor(), { 1, 1 })

    child.ensure_normal_mode()
  end

  -- Visual mode should be cancelled without leaving Visual mode
  validate({ 'v', 'i' }, 'v')

  -- Operator-pending mode should be cancelled into Normal mode
  validate({ 'd', 'i' }, 'n')
end

T['Textobject']['works with different mappings'] = function()
  reload_module({ mappings = { around = 'A', inside = 'I' } })

  validate_tobj1d('aa(bb)', 0, 'A)', { 3, 6 })
  validate_tobj1d('aa(bb)', 0, 'I)', { 4, 5 })
end

T['Textobject']['allows dot-repeat'] = function()
  set_lines({ '((aa)bb)', '(cc)dd' })
  set_cursor(1, 2)

  type_keys('da)')
  eq(get_lines(), { '(bb)', '(cc)dd' })
  eq(get_cursor(), { 1, 1 })

  type_keys('.')
  eq(get_lines(), { '', '(cc)dd' })
  eq(get_cursor(), { 1, 0 })

  -- Allows not immediate dot-repeat
  type_keys('j', '.')
  eq(get_lines(), { '', 'dd' })
  eq(get_cursor(), { 2, 0 })
end

T['Textobject']['collapses multiline textobject'] = function()
  local lines = { '(', 'a', ')' }
  validate_edit(lines, { 2, 0 }, { '' }, { 1, 0 }, 'da)')

  local validate = function()
    validate_edit(lines, { 1, 0 }, { '()' }, { 1, 1 }, 'di)')
    validate_edit(lines, { 2, 0 }, { '()' }, { 1, 1 }, 'di)')
    validate_edit(lines, { 3, 0 }, { '()' }, { 1, 1 }, 'di)')
  end

  child.o.selection = 'inclusive'
  validate()
  child.o.selection = 'exclusive'
  validate()
end

T['Textobject']['works with multibyte characters'] = function()
  -- Each multibyte character takes two column counts
  local line = '(ыы)ффф(ыы)'
  validate_edit1d(line, 1, 'ффф(ыы)', 0, 'da)')
  validate_edit1d(line, 1, '()ффф(ыы)', 1, 'di)')
  validate_edit1d(line, 6, '(ыы)ффф', 10, 'da)')
  validate_edit1d(line, 6, '(ыы)ффф()', 13, 'di)')
end

T['Textobject']['respects `v:count`'] = function()
  validate_tobj1d('(aa)bb(cc)dd(ee)', 0, '2a)', { 7, 10 })
  validate_tobj1d('(aa)bb(cc)dd(ee)', 0, '3a)', { 13, 16 })

  -- Don't do anything if not enough is present
  validate_no_tobj1d('(aa)bb(cc)dd(ee)', 0, '4a)')
end

T['Textobject']["respects 'selection=exclusive'"] = function()
  child.o.selection = 'exclusive'

  local validate = function(ai_type, after)
    set_lines({ ' (aaa) ' })
    set_cursor(1, 2)
    type_keys('v', ai_type, ')', 'd')
    eq(get_lines(), { after })
  end

  validate('i', ' () ')
  validate('a', '  ')
end

T['Textobject']['falls back in case of absent textobject id'] = function()
  -- Set low `timeoutlen` to simulate its expiration
  child.o.timeoutlen = 5

  local validate = function(line, column, keys, expected)
    child.ensure_normal_mode()
    set_lines({ line })
    set_cursor(1, column)
    type_keys(10, 'v', keys[1], keys[2])

    child.expect_visual_marks({ 1, expected[1] - 1 }, { 1, expected[2] - 1 })
  end

  -- Builtin textobject
  local pattern = 'mini.*ai'
  -- Visual mode
  expect.match(child.fn.maparg('a', 'x'), pattern)
  validate('aaa bbb', 0, { 'a', 'w' }, { 1, 4 })

  expect.match(child.fn.maparg('i', 'x'), pattern)
  validate('aaa bbb', 0, { 'i', 'w' }, { 1, 3 })

  -- Operator-pending mode
  expect.match(child.fn.maparg('a', 'o'), pattern)
  validate_edit1d('aaa bbb', 0, 'bbb', 0, 20, 'd', 'a', 'w')

  expect.match(child.fn.maparg('i', 'o'), pattern)
  validate_edit1d('aaa bbb', 0, ' bbb', 0, 10, 'd', 'i', 'w')

  -- Custom textobject
  local map = function(mode, lhs)
    child.api.nvim_set_keymap(mode, lhs, '<Cmd>lua vim.api.nvim_win_set_cursor(0, { 1, 5 })<CR>', { noremap = true })
  end

  -- Visual mode
  map('x', 'ac')
  validate('aaa bbb', 0, { 'a', 'c' }, { 1, 6 })

  map('x', 'ic')
  validate('aaa bbb', 0, { 'i', 'c' }, { 1, 6 })

  -- Operator-pending mode
  map('o', 'ac')
  validate_edit1d('aaa bbb', 0, 'bb', 0, 10, 'd', 'a', 'c')

  map('o', 'ic')
  validate_edit1d('aaa bbb', 0, 'bb', 0, 10, 'd', 'i', 'c')
end

T['Textobject']['falls back in case of absent textobject id and different main mapping'] = function()
  reload_module({ mappings = { around = 'A', inside = 'I' } })

  -- Set low `timeoutlen` to simulate its expiration
  child.o.timeoutlen = 5

  local validate = function(line, column, keys, expected)
    child.ensure_normal_mode()
    set_lines({ line })
    set_cursor(1, column)
    type_keys(10, 'v', keys[1], keys[2])

    child.expect_visual_marks({ 1, expected[1] - 1 }, { 1, expected[2] - 1 })
  end

  -- Custom textobject
  local map = function(mode, lhs)
    child.api.nvim_set_keymap(mode, lhs, '<Cmd>lua vim.api.nvim_win_set_cursor(0, { 1, 5 })<CR>', { noremap = true })
  end

  -- Visual mode
  map('x', 'Ac')
  validate('aaa bbb', 0, { 'A', 'c' }, { 1, 6 })

  map('x', 'Ic')
  validate('aaa bbb', 0, { 'I', 'c' }, { 1, 6 })

  -- Operator-pending mode
  map('o', 'Ac')
  validate_edit1d('aaa bbb', 0, 'bb', 0, 10, 'd', 'A', 'c')

  map('o', 'Ic')
  validate_edit1d('aaa bbb', 0, 'bb', 0, 10, 'd', 'I', 'c')
end

T['Textobject']["works with 'langmap'"] = function()
  -- Useful for different keyboard layouts. See
  -- https://github.com/nvim-mini/mini.nvim/issues/195
  child.o.langmap = 'ki,ik'

  local validate_visual = function(line, column, keys, expected)
    child.ensure_normal_mode()
    set_lines({ line })
    set_cursor(1, column)
    type_keys(10, 'v', keys[1], keys[2])

    child.expect_visual_marks({ 1, expected[1] - 1 }, { 1, expected[2] - 1 })
  end

  local map = function(mode, lhs)
    child.api.nvim_set_keymap(mode, lhs, '<Cmd>lua vim.api.nvim_win_set_cursor(0, { 1, 5 })<CR>', { noremap = true })
  end

  -- Visual mode
  -- - Registered textobject
  validate_visual('aa(bb)cc', 3, { 'k', ')' }, { 4, 5 })

  -- - Default textobject
  validate_visual('aa bb cc', 3, { 'k', 'w' }, { 4, 5 })

  -- - Custom textobject
  map('x', 'ic')
  validate_visual('aa bb cc', 3, { 'k', 'c' }, { 4, 6 })

  -- Operator-pending mode
  -- - Registered textobject
  validate_edit1d('aa(bb)cc', 3, 'aa()cc', 3, 'dk)')

  -- - Default textobject
  validate_edit1d('aa bb cc', 3, 'aa  cc', 3, 'dkw')

  -- - Custom textobject
  map('o', 'ic')
  validate_edit1d('aa bb cc', 3, 'aa  cc', 3, 'dkc')
end

T['Textobject']['works with empty output region'] = function()
  local validate = function(start_column)
    validate_edit1d('a()b', start_column, 'a()b', 2, 'ci)')
    eq(get_mode(), 'i')

    validate_edit1d('a()b', start_column, 'a()b', 2, 'di)')
  end

  validate(0)
  validate(1)
end

T['Textobject']['handles horizontal view for out of view textobjects'] = function()
  child.o.wrap = false
  child.set_size(10, 25)

  local validate = function(line, cursor_col, leftcol, keys, ref_leftcol)
    set_lines({ line })
    set_cursor(1, cursor_col)
    child.fn.winrestview({ leftcol = leftcol })
    type_keys(keys)
    eq(child.fn.winsaveview().leftcol, ref_leftcol)

    child.ensure_normal_mode()
  end

  -- Should try to do as least horizontal scroll as possible
  local partially_visible_right = 'abcdefghijklmnopqrst "xxxxx"'
  validate(partially_visible_right, 0, 0, { 'c', 'i', '"' }, 0)
  validate(partially_visible_right, 0, 0, { 'v', 'i', '"' }, 2)

  local completely_to_right = 'abcdefghijklmnopqrst        "xxxxx"'
  validate(completely_to_right, 0, 0, { 'c', 'i', '"' }, 5)
  validate(completely_to_right, 0, 0, { 'v', 'i', '"' }, 9)

  local partially_visible_left = '"xxxxx" abcdefghijklmnopqrst'
  validate(partially_visible_left, 8, 3, { 'c', 'il', '"' }, 1)
  validate(partially_visible_left, 8, 3, { 'v', 'il', '"' }, 3)

  local completely_to_left = '"xxxxx"        abcdefghijklmnopqrst'
  validate(completely_to_left, 34, 10, { 'c', 'il', '"' }, 1)
  validate(completely_to_left, 34, 10, { 'v', 'il', '"' }, 5)

  local outside_left_right = '"xxxxx abcdefghijklmnopqrst xxxxx"'
  validate(outside_left_right, 12, 4, { 'c', 'i', '"' }, 1)
  validate(outside_left_right, 12, 4, { 'v', 'i', '"' }, 8)
end

T['Textobject']['works in command-line window'] = function()
  child.set_size(20, 40)

  local validate = function(before_line, after_line, keys)
    -- Open command-line window
    type_keys('q:')
    eq(child.fn.getcmdwintype(), ':')

    type_keys('i', before_line, '<Esc>')
    type_keys(keys)
    eq(child.fn.getline('.'), after_line)

    -- It shouldn't close command-line window
    eq(child.fn.getcmdwintype(), ':')
    type_keys('<Esc>')
    child.cmd('close')
  end

  validate('(aaa)', '(...)', 'vi)r.')
  validate('(aaa)', '.....', 'va)r.')

  validate('(aaa)', '()', 'di)')
  validate('(aaa)', '', 'da)')

  validate('fun(aaa)', 'fun()', 'cif')
  validate('fun(aaa)', '', 'caf')
end

T['Textobject']['ensures that output is not covered by reference'] = function()
  -- Non-empty region
  set_lines({ 'aa(bb)cc(dd)' })
  set_cursor(1, 3)
  type_keys('vl', 'i)')
  eq({ child.fn.col('v'), child.fn.col('.') }, { 10, 11 })

  -- Empty region
  validate_tobj1d('a()b(c)', 2, 'i)', { 6, 6 })
  -- Probably not very consistent with non-empty case, because `ci)` in 'a(a)b'
  -- on right ')' allows "going backwards" and deleting inside '(a)'. But this
  -- is consistent with "ensure textobject is not covering reference" and
  -- `ci)` <=> `vi)c` equivalence.
  validate_edit1d('a()b(c)', 2, 'a()b()', 5, 'di)')
  validate_edit1d('a()b(c)', 2, 'a()b()', 5, 'ci)')
end

T['Textobject']['opens just enough folds'] = function()
  set_lines({ '(a', 'b', 'c', 'd', 'e', 'f)' })

  -- Manually create two nested closed folds
  set_cursor(1, 0)
  type_keys('zf', 'j')
  set_cursor(3, 0)
  type_keys('zf', 'j')
  set_cursor(5, 0)
  type_keys('zf', 'j')
  eq(child.fn.foldclosed(2), 1)
  eq(child.fn.foldclosed(4), 3)
  eq(child.fn.foldclosed(6), 5)

  -- Selecting textobject should open just enough folds
  set_cursor(1, 0)
  type_keys('v', 'i', ')')
  eq(child.fn.foldclosed(2), -1)
  eq(child.fn.foldclosed(4), 3)
  eq(child.fn.foldclosed(6), -1)
end

T['Textobject']['prompts helper message after one idle second'] = new_set({ parametrize = { { 'a' }, { 'i' } } }, {
  test = function(key)
    child.set_size(5, 70)
    child.o.cmdheight = 1

    -- Both mappings are applied only after `timeoutlen` milliseconds, because
    -- there are `an`/`in`/`al`/`il` mappings.
    -- Wait fixed time after that.
    child.o.timeoutlen = 2 * small_time
    local total_wait_time = helper_message_delay + child.o.timeoutlen + small_time

    set_lines({ '(aaa)' })
    set_cursor(1, 1)

    type_keys('v', key)
    sleep(total_wait_time)

    -- Should show helper message without adding it to `:messages` and causing
    -- hit-enter-prompt
    eq(get_latest_message(), '')
    child.expect_screenshot({ redraw = false })

    -- Should clear afterwards
    type_keys(')')
    child.expect_screenshot({ redraw = false })
  end,
})

T['Textobject']['shows message if no textobject is found'] = function()
  -- Make all showed messages full width
  child.o.cmdheight = 10

  local validate = function(keys, msg)
    child.cmd('messages clear')
    set_lines({ 'aa' })
    set_cursor(1, 0)
    type_keys('v', keys)
    eq(get_cursor(), { 1, 0 })
    eq(get_latest_message(), msg)
  end

  validate(
    'a)',
    [[(mini.ai) No textobject "a)" found covering region within 50 lines and `search_method = 'cover_or_next'`.]]
  )

  child.lua([[MiniAi.config.n_lines = 1; MiniAi.config.search_method = 'cover']])
  validate(
    '2i]',
    [[(mini.ai) No textobject "i]" found covering region 2 times within 1 line and `search_method = 'cover'`.]]
  )
end

T['Textobject']['shows message for empty textobject in Operator-pending mode'] = function()
  child.o.eventignore = ''
  set_lines({ 'a()' })
  set_cursor(1, 0)

  type_keys('yi)')
  eq(child.fn.mode(), 'n')
  eq(get_cursor(), { 1, 0 })
  eq(get_latest_message(), '(mini.ai) Textobject region is empty. Nothing is done.')
  eq(child.o.eventignore, '')
end

T['Textobject']['respects `vim.{g,b}.miniai_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].miniai_disable = true

    -- It should fallback to Neovim builtin behavior
    validate_tobj1d('(  aa  )', 0, 'i(', { 2, 7 })

    -- It shouldn't recognize new textobjects
    validate_edit1d('*bb*', 1, '*bb*', 1, 'ci*')
  end,
})

T['Textobject']['respects `config.silent`'] = function()
  child.set_size(5, 40)
  child.o.showcmd = false
  child.lua('MiniAi.config.silent = true')

  child.o.timeoutlen = 2 * small_time
  local total_wait_time = helper_message_delay + child.o.timeoutlen + small_time

  set_lines({ '(aaa)' })
  set_cursor(1, 1)

  type_keys('v', 'a')
  sleep(total_wait_time)

  -- Should not show helper message
  child.expect_screenshot()

  -- Finish user input for cleaner Neovim restart
  type_keys(')')
end

T['Textobject next/last'] = new_set()

T['Textobject next/last']['works in Visual mode'] = function()
  local lines, cursor

  -- Next
  lines, cursor = { '(aa)(bb', 'cccc', 'dd)(ee)' }, { 1, 1 }
  validate_tobj(lines, cursor, 'an)', { { 1, 5 }, { 3, 3 } }, 'v')
  validate_tobj(lines, cursor, 'in)', { { 1, 6 }, { 3, 2 } }, 'v')
  validate_tobj(lines, cursor, 'an)', { 1, 3 }, 'V')
  validate_tobj(lines, cursor, 'in)', { 1, 3 }, 'V')
  validate_tobj(lines, cursor, 'an)', { { 1, 5 }, { 3, 3 } }, '<C-v>')
  validate_tobj(lines, cursor, 'in)', { { 1, 6 }, { 3, 2 } }, '<C-v>')

  -- Last
  lines, cursor = { '(aa)(bb', 'cccc', 'dd)(ee)' }, { 3, 5 }
  validate_tobj(lines, cursor, 'al)', { { 1, 5 }, { 3, 3 } }, 'v')
  validate_tobj(lines, cursor, 'il)', { { 1, 6 }, { 3, 2 } }, 'v')
  validate_tobj(lines, cursor, 'al)', { 1, 3 }, 'V')
  validate_tobj(lines, cursor, 'il)', { 1, 3 }, 'V')
  validate_tobj(lines, cursor, 'al)', { { 1, 5 }, { 3, 3 } }, '<C-v>')
  validate_tobj(lines, cursor, 'il)', { { 1, 6 }, { 3, 2 } }, '<C-v>')
end

T['Textobject next/last']['works in Operator-pending mode'] = function()
  local lines, cursor

  -- Next
  lines, cursor = { '(aa)(bb', 'ccccc', 'dddd)ee' }, { 1, 0 }
  validate_edit(lines, cursor, { '(aa)ee' }, { 1, 4 }, 'dan)')
  validate_edit(lines, cursor, { '(aa)ee' }, { 1, 4 }, 'dvan)')
  validate_edit(lines, cursor, { '' }, { 1, 0 }, 'dVan)')
  validate_edit(lines, cursor, { '(aa)bb', 'cccc', 'ddddee' }, { 1, 4 }, 'd<C-v>an)')

  -- Last
  lines, cursor = { 'aa(bbbb', 'ccccc', 'dd)(ee)' }, { 3, 5 }
  validate_edit(lines, cursor, { 'aa(ee)' }, { 1, 2 }, 'dal)')
  validate_edit(lines, cursor, { 'aa(ee)' }, { 1, 2 }, 'dval)')
  validate_edit(lines, cursor, { '' }, { 1, 0 }, 'dVal)')
  validate_edit(lines, cursor, { 'aabbbb', 'cccc', 'dd(ee)' }, { 1, 2 }, 'd<C-v>al)')
end

T['Textobject next/last']['works with different mappings'] = function()
  reload_module({ mappings = { around_next = 'An', around_last = 'Al', inside_next = 'In', inside_last = 'Il' } })

  validate_tobj1d('(aa)(bb)', 1, 'An)', { 5, 8 })
  validate_tobj1d('(aa)(bb)', 1, 'In)', { 6, 7 })
  validate_tobj1d('(aa)(bb)', 5, 'Al)', { 1, 4 })
  validate_tobj1d('(aa)(bb)', 5, 'Il)', { 2, 3 })
end

T['Textobject next/last']['allows dot-repeat'] = function()
  -- Next
  set_lines({ '(aa)(bb)', '(cc)(dd)' })
  set_cursor(1, 1)

  type_keys('dan)')
  eq(get_lines(), { '(aa)', '(cc)(dd)' })
  eq(get_cursor(), { 1, 3 })

  type_keys('.')
  eq(get_lines(), { '(aa)', '(dd)' })
  eq(get_cursor(), { 2, 0 })

  -- Allows not immediate dot-repeat
  type_keys('k', '.')
  eq(get_lines(), { '(aa)', '' })
  eq(get_cursor(), { 2, 0 })

  -- Last
  set_lines({ '(aa)(bb)', '(cc)(dd)' })
  set_cursor(2, 6)

  type_keys('dal)')
  eq(get_lines(), { '(aa)(bb)', '(dd)' })
  eq(get_cursor(), { 2, 0 })

  type_keys('.')
  eq(get_lines(), { '(aa)', '(dd)' })
  eq(get_cursor(), { 1, 3 })

  -- Allows not immediate dot-repeat
  type_keys('j', '.')
  eq(get_lines(), { '', '(dd)' })
  eq(get_cursor(), { 1, 0 })
end

T['Textobject next/last']['respects `v:count`'] = function()
  validate_tobj1d('(aa)(bb)(cc)(dd)', 1, '2an)', { 9, 12 })
  validate_tobj1d('(aa)(bb)(cc)(dd)', 1, '2in)', { 10, 11 })
  validate_tobj1d('(aa)(bb)(cc)(dd)', 1, '3an)', { 13, 16 })

  validate_tobj1d('(aa)(bb)(cc)(dd)', 14, '2al)', { 5, 8 })
  validate_tobj1d('(aa)(bb)(cc)(dd)', 14, '2il)', { 6, 7 })
  validate_tobj1d('(aa)(bb)(cc)(dd)', 14, '3al)', { 1, 4 })

  -- Don't do anything if not enough is present
  validate_no_tobj1d('(aa)(bb)(cc)(dd)', 1, '4an)')
  validate_no_tobj1d('(aa)(bb)(cc)(dd)', 14, '4al)')
end

local validate_motion = function(lines, cursor, keys, expected)
  set_lines(lines)
  set_cursor(cursor[1], cursor[2])
  type_keys(keys)
  eq(get_cursor(), { expected[1], expected[2] })
end

local validate_motion1d = function(line, column, keys, expected)
  validate_motion({ line }, { 1, column }, keys, { 1, expected })
end

T['Motion'] = new_set()

T['Motion']['works in Normal mode'] = function()
  validate_motion1d('aa(bbb)', 4, 'g[)', 2)
  validate_motion1d('aa(bbb)', 4, 'g])', 6)
end

T['Motion']['works in Visual mode'] = function()
  validate_motion1d('aa(bbb)', 4, 'vg[)', 2)

  child.ensure_normal_mode()
  validate_motion1d('aa(bbb)', 4, 'vg])', 6)
end

T['Motion']['works in Operator-pending mode'] = function()
  local validate = function(motion_keys, after_line, after_column)
    validate_edit1d('aa(bbb)', 4, after_line, after_column, 'd' .. motion_keys .. ')')

    child.ensure_normal_mode()
    validate_edit1d('aa(bbb)', 4, after_line, after_column, 'c' .. motion_keys .. ')')
    eq(get_mode(), 'i')
  end

  validate('g[', 'aabb)', 2)
  validate('g]', 'aa(b)', 4)
end

T['Motion']['allows with dot-repeat'] = function()
  -- Assumes `g[` has same implementation
  set_lines({ '(aa)  (bb)', '(cc)' })
  set_cursor(1, 0)

  type_keys('dg])')
  eq(get_lines(), { ')  (bb)', '(cc)' })

  type_keys('.')
  eq(get_lines(), { ')', '(cc)' })

  -- Allows not immediate dot-repeat
  type_keys('j0', '.')
  eq(get_lines(), { ')', ')' })
end

T['Motion']['works with different mappings'] = function()
  reload_module({ mappings = { goto_left = 'g{', goto_right = 'g}' } })

  validate_motion1d('aa(bbb)', 4, 'g{)', 2)
  validate_motion1d('aa(bbb)', 4, 'g})', 6)
end

T['Motion']['treats `side` as edge of textobject'] = function()
  local line = '(aa)bb(cc)'
  validate_motion1d(line, 1, 'g[)', 0)
  validate_motion1d(line, 1, 'g])', 3)
  validate_motion1d(line, 4, 'g[)', 6)
  validate_motion1d(line, 4, 'g])', 9)
  validate_motion1d(line, 7, 'g[)', 6)
  validate_motion1d(line, 7, 'g])', 9)
end

T['Motion']['respects `v:count`'] = function()
  validate_motion1d('aa(bb)cc(dd)', 0, '2g[)', 8)
  validate_motion1d('aa(bb)cc(dd)', 0, '2g])', 11)

  -- It should do exactly `v:count` actual jumps. It can be not that way if
  -- cursor is on edge of one of target textobjects
  local line = 'aa(bb)cc(dd)ee(ff)'
  validate_motion1d(line, 0, '2g[)', 8) -- 0->2->8
  validate_motion1d(line, 2, '2g[)', 14) -- 2->8->14
  validate_motion1d(line, 3, '2g[)', 8) -- 3->2->8
  validate_motion1d(line, 5, '2g[)', 8) -- 5->2->8

  validate_motion1d(line, 0, '2g])', 11) -- 0->5->11
  validate_motion1d(line, 2, '2g])', 11) -- 2->5->11
  validate_motion1d(line, 3, '2g])', 11) -- 3->5->11
  validate_motion1d(line, 5, '2g])', 17) -- 5->11->17
end

T['Motion']['works with multibyte characters'] = function()
  validate_motion1d(' (ыыы) ', 0, 'g[)', 1)
  validate_motion1d(' (ыыы) ', 0, 'g])', 8)
end

T['Motion']['works with special textobject id'] = function()
  validate_motion1d([[aa\bb\cc]], 4, [[g[\]], 3)
  validate_motion({ 'aa', 'bb', 'cc' }, { 1, 0 }, 'g[<C-j>', { 2, 0 })
end

T['Motion']['respects `vim.{g,b}.miniai_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].miniai_disable = true

    set_lines({ '  (aaa)  ' })
    set_cursor(1, 4)

    -- Here `)` should serve as builtin motion after unsuccessful use of motion
    type_keys('g[)')
    eq(get_cursor(), { 1, 8 })

    type_keys('g])')
    eq(get_cursor(), { 1, 8 })
  end,
})

T['Builtin'] = new_set()

local brackets = {
  ['('] = { '(', ')', 'open' },
  [')'] = { '(', ')', 'close' },
  ['['] = { '[', ']', 'open' },
  [']'] = { '[', ']', 'close' },
  ['{'] = { '{', '}', 'open' },
  ['}'] = { '{', '}', 'close' },
  ['<'] = { '<', '>', 'open' },
  ['>'] = { '<', '>', 'close' },
}

T['Builtin']['Bracket'] = new_set({ parametrize = vim.tbl_map(function(x) return { x } end, vim.tbl_keys(brackets)) })

T['Builtin']['Bracket']['works'] = function(key)
  local left, right, side = unpack(brackets[key])

  -- Single line
  validate_tobj1d(left .. 'aa' .. right, 0, { 'a', key }, { 1, 4 })
  validate_tobj1d(left .. 'aa' .. right, 0, { 'i', key }, { 2, 3 })

  -- Multiline. End of line is considered to be whitespace, so should be
  -- ignored by open brackets.
  validate_tobj({ left, 'aa', right }, { 2, 0 }, { 'a', key }, { { 1, 1 }, { 3, 1 } })
  local multiline_i_expected = side == 'open' and { { 2, 1 }, { 2, 2 } } or { { 1, 2 }, { 2, 3 } }
  validate_tobj({ left, 'aa', right }, { 2, 0 }, { 'i', key }, multiline_i_expected)
end

T['Builtin']['Bracket']['works consecutively'] = function(key)
  local left, right, side = unpack(brackets[key])

  -- Reference: {'(', 'aa(bb)cc(dd)', ')'}
  set_lines({ left, string.format('aa%sbb%scc%sdd%s', left, right, left, right), right })
  set_cursor(2, 0)

  -- `a`
  type_keys('v')
  validate_next_region({ 'a', key }, { { 2, 3 }, { 2, 6 } })
  validate_next_region({ 'a', key }, { { 2, 9 }, { 2, 12 } })
  validate_next_region({ 'a', key }, { { 1, 1 }, { 3, 1 } })

  -- `i`
  child.ensure_normal_mode()
  set_cursor(2, 0)
  type_keys('v')
  validate_next_region({ 'i', key }, { { 2, 4 }, { 2, 5 } })
  validate_next_region({ 'i', key }, { { 2, 10 }, { 2, 11 } })
  local i_expected = side == 'open' and { { 2, 1 }, { 2, 12 } } or { { 1, 2 }, { 2, 13 } }
  validate_next_region({ 'i', key }, i_expected)
end

T['Builtin']['Bracket']['handles inner whitespace'] = function(key)
  local left, right, side = unpack(brackets[key])

  -- Open brackets should exclude inner edge whitespace.
  validate_tobj1d(left .. 'aa ' .. right, 0, { 'i', key }, side == 'open' and { 2, 3 } or { 2, 4 })
  validate_tobj1d(left .. ' aa' .. right, 0, { 'i', key }, side == 'open' and { 3, 4 } or { 2, 4 })
  validate_tobj1d(left .. ' aa ' .. right, 0, { 'i', key }, side == 'open' and { 3, 4 } or { 2, 5 })

  -- Should also handle only inner whitespace
  local whitespace_line = left .. '  ' .. right
  local after_line = side == 'open' and whitespace_line or (left .. right)
  local after_column = side == 'open' and 3 or 1
  validate_edit1d(whitespace_line, 0, after_line, after_column, { 'ci', key })
  validate_edit1d(whitespace_line, 0, after_line, after_column, { 'di', key })
end

T['Builtin']['Bracket']['is balanced'] = function(key)
  local left, right, _ = unpack(brackets[key])
  -- Reference: 'a(()'
  local line = 'a' .. left .. left .. right
  validate_tobj1d(line, 0, { 'a', key }, { 3, 4 })
end

T['Builtin']['Bracket']['works with empty region'] = function(key)
  -- Emulate "replace" from 'mini.operators'
  child.lua([[
    _G.MiniOperators = {}
    _G.MiniOperators.replace = function(mode)
      if mode == nil then
        vim.o.operatorfunc = 'v:lua.MiniOperators.replace'
        return 'g@'
      end
      vim.fn.setreg('a', 'xxx')
      vim.cmd('normal! `[v`]"aP`[')
    end

    vim.keymap.set('n', 'gr', _G.MiniOperators.replace, { expr = true })
    -- Delete conflicting default `gri` mapping
    pcall(vim.keymap.del, 'n', 'gri')
  ]])

  -- Validate
  local left, right, _ = unpack(brackets[key])

  local line = 'a' .. left .. right
  for i = 0, 1 do
    validate_tobj1d(line, i, { 'i', key }, { 3, 3 })
    validate_edit1d(line, i, line, 2, { 'ci', key })
    validate_edit1d(line, i, line, 2, { 'di', key })

    validate_edit1d(line, i, 'a' .. left .. 'xxx' .. right, 2, { 'gri', key })
  end
end

T['Builtin']['Brackets alias'] = new_set()

T['Builtin']['Brackets alias']['works'] = function()
  -- Single line
  validate_tobj1d('(aa)', 0, 'ab', { 1, 4 })
  validate_tobj1d('[aa]', 0, 'ab', { 1, 4 })
  validate_tobj1d('{aa}', 0, 'ab', { 1, 4 })

  validate_tobj1d('(aa)', 0, 'ib', { 2, 3 })
  validate_tobj1d('[aa]', 0, 'ib', { 2, 3 })
  validate_tobj1d('{aa}', 0, 'ib', { 2, 3 })

  -- Multiline
  local lines = { '{', 'aa(bb)cc[dd]', '}' }
  validate_tobj(lines, { 2, 0 }, 'ab', { { 2, 3 }, { 2, 6 } })
  validate_tobj(lines, { 2, 0 }, '2ab', { { 2, 9 }, { 2, 12 } })
  validate_tobj(lines, { 2, 0 }, '3ab', { { 1, 1 }, { 3, 1 } })

  -- Balanced
  validate_tobj1d('a(()', 0, 'ab', { 3, 4 })
  validate_tobj1d('a[[]', 0, 'ab', { 3, 4 })
  validate_tobj1d('a{{}', 0, 'ab', { 3, 4 })
end

T['Builtin']['Brackets alias']['works consecutively'] = function()
  set_lines({ '{([aa])}' })
  set_cursor(1, 3)

  -- `a`
  type_keys('v')
  validate_next_region1d('ab', { 3, 6 })
  validate_next_region1d('ab', { 2, 7 })
  validate_next_region1d('ab', { 1, 8 })

  -- `i`
  child.ensure_normal_mode()
  set_cursor(1, 3)
  type_keys('v')
  validate_next_region1d('ib', { 4, 5 })
  validate_next_region1d('ib', { 3, 6 })
  validate_next_region1d('ib', { 2, 7 })
end

T['Builtin']['Quote'] = new_set({ parametrize = { { '"' }, { "'" }, { '`' } } })

T['Builtin']['Quote']['works'] = function(key)
  -- Single line
  validate_tobj1d(key .. ' aa ' .. key, 0, 'a' .. key, { 1, 6 })
  validate_tobj1d(key .. ' aa ' .. key, 0, 'i' .. key, { 2, 5 })

  -- Multiline
  validate_tobj({ key, 'aa', key }, { 2, 0 }, 'a' .. key, { { 1, 1 }, { 3, 1 } })
  validate_tobj({ key, 'aa', key }, { 2, 0 }, 'i' .. key, { { 1, 2 }, { 2, 3 } })
end

T['Builtin']['Quote']['works consecutively'] = function(key)
  -- Reference: { 'aa(bb)cc(dd)' }
  set_lines({ string.format('aa%sbb%scc%sdd%s', key, key, key, key) })
  set_cursor(1, 0)

  -- `a`
  type_keys('v')
  validate_next_region1d('a' .. key, { 3, 6 })
  validate_next_region1d('a' .. key, { 9, 12 })

  -- `i`
  child.ensure_normal_mode()
  set_cursor(1, 0)
  type_keys('v')
  validate_next_region1d('i' .. key, { 4, 5 })
  validate_next_region1d('i' .. key, { 10, 11 })
end

T['Builtin']['Quote']['is balanced'] = function(key)
  -- Here by "balanced" it means that it counts in consecutive pairs from start
  -- of neighborhood.

  -- Single line. Reference: 'aa"bb"cc"dd"'
  local line = string.format('aa%sbb%scc%sdd%s', key, key, key, key)
  validate_tobj1d(line, 0, 'a' .. key, { 3, 6 })
  validate_tobj1d(line, 0, '2a' .. key, { 9, 12 })

  -- Multiple lines. Here there is an issue with transitioning from current
  -- line to full neighborhood, but it should be rare and thus acceptable.
  -- Reference: {'(', 'aa(bb)cc(dd)', ')'}
  local lines, cursor = { key, string.format('aa%sbb%scc%sdd%s', key, key, key, key), key }, { 2, 0 }
  validate_tobj(lines, cursor, 'a' .. key, { { 2, 3 }, { 2, 6 } })
  validate_tobj(lines, cursor, '2a' .. key, { { 2, 9 }, { 2, 12 } })
  -- Here, ideally, it should be { { 1, 1 }, { 3, 1 } }
  validate_tobj(lines, cursor, '3a' .. key, { { 2, 12 }, { 3, 1 } })
end

T['Builtin']['Quote']['works with empty region'] = function(key)
  local line = 'a' .. key .. key
  for i = 0, 1 do
    validate_tobj1d(line, i, 'i' .. key, { 3, 3 })
    validate_edit1d(line, i, line, 2, 'ci' .. key)
    validate_edit1d(line, i, line, 2, 'di' .. key)
  end
end

T['Builtin']['Quotes alias'] = new_set()

T['Builtin']['Quotes alias']['works'] = function()
  validate_tobj1d("'aa'", 0, 'aq', { 1, 4 })
  validate_tobj1d('"aa"', 0, 'aq', { 1, 4 })
  validate_tobj1d('`aa`', 0, 'aq', { 1, 4 })

  validate_tobj1d("'aa'", 0, 'iq', { 2, 3 })
  validate_tobj1d('"aa"', 0, 'iq', { 2, 3 })
  validate_tobj1d('`aa`', 0, 'iq', { 2, 3 })

  local lines = { '`', [[aa'bb'cc"dd"]], '`' }
  validate_tobj(lines, { 2, 0 }, 'aq', { { 2, 3 }, { 2, 6 } })
  validate_tobj(lines, { 2, 0 }, '2aq', { { 2, 9 }, { 2, 12 } })
  validate_tobj(lines, { 2, 0 }, '3aq', { { 1, 1 }, { 3, 1 } })

  -- Balanced
  validate_tobj1d("a''''", 0, '2aq', { 4, 5 })
  validate_tobj1d('a""""', 0, '2aq', { 4, 5 })
  validate_tobj1d('a````', 0, '2aq', { 4, 5 })
end

T['Builtin']['Quotes alias']['works consecutively'] = function()
  -- `a`
  set_lines({ [[`"'aa'"`]] })
  set_cursor(1, 3)

  type_keys('v')
  validate_next_region1d('aq', { 3, 6 })
  validate_next_region1d('aq', { 2, 7 })
  validate_next_region1d('aq', { 1, 8 })

  -- `i`
  child.ensure_normal_mode()
  set_cursor(1, 3)
  type_keys('v')
  validate_next_region1d('iq', { 4, 5 })
  validate_next_region1d('iq', { 3, 6 })
  validate_next_region1d('iq', { 2, 7 })

  -- Nested unbalanced pairs
  child.ensure_normal_mode()
  set_lines({ [["aa'bb'cc'"dd`'`]] })
  set_cursor(1, 4)

  type_keys('v')
  validate_next_region1d('aq', { 4, 7 })
  validate_next_region1d('aq', { 1, 11 })
  validate_next_region1d('aq', { 10, 15 })
  validate_next_region1d('aq', { 14, 16 })
end

T['Builtin']['Argument'] = new_set()

T['Builtin']['Argument']['works'] = function()
  -- Don't check on first comma, as it is ambiguous
  for i = 2, 3 do
    validate_tobj1d('f(xx, yy, tt)', i, 'aa', { 3, 5 })
    validate_tobj1d('f(xx, yy, tt)', i, 'ia', { 3, 4 })
  end
  for i = 5, 7 do
    validate_tobj1d('f(xx, yy, tt)', i, 'aa', { 5, 8 })
    validate_tobj1d('f(xx, yy, tt)', i, 'ia', { 7, 8 })
  end
  for i = 8, 11 do
    validate_tobj1d('f(xx, yy, tt)', i, 'aa', { 9, 12 })
    validate_tobj1d('f(xx, yy, tt)', i, 'ia', { 11, 12 })
  end
end

T['Builtin']['Argument']['works consecutively'] = function()
  -- `a` textobject
  set_lines({ 'f(xx, yy, tt)' })
  set_cursor(1, 0)
  type_keys('v')
  validate_next_region1d('aa', { 3, 5 })
  validate_next_region1d('aa', { 5, 8 })
  validate_next_region1d('aa', { 9, 12 })

  -- `i` textobject
  child.ensure_normal_mode()
  set_lines({ 'f(xx, yy, tt)' })
  set_cursor(1, 0)
  type_keys('v')
  validate_next_region1d('ia', { 3, 4 })
  validate_next_region1d('ia', { 7, 8 })
  validate_next_region1d('ia', { 11, 12 })
end

T['Builtin']['Argument']['is ambiguous on first comma'] = function()
  -- It chooses argument with smaller width. This is not good, but is a result
  -- of compromise over comma asymmetry.
  validate_tobj1d('f(x, yyyyyy)', 3, 'aa', { 3, 4 })
  validate_tobj1d('f(xxxxxx, y)', 8, 'aa', { 9, 11 })

  -- It is also true if separator pattern includes whitespace
  child.lua([[MiniAi.config.custom_textobjects = { A = MiniAi.gen_spec.argument({ separator = '%s*,%s*' }) }]])
  validate_tobj1d('f(x , yyyyyy)', 5, 'aA', { 3, 6 })
  validate_tobj1d('f(xxxxxx , y)', 8, 'aA', { 9, 12 })
end

T['Builtin']['Argument']['works inside all balanced brackets'] = function()
  validate_tobj1d('(xx, yy)', 2, 'aa', { 2, 4 })
  validate_tobj1d('[xx, yy]', 2, 'aa', { 2, 4 })
  validate_tobj1d('{xx, yy}', 2, 'aa', { 2, 4 })
end

T['Builtin']['Argument']['ignores commas inside balanced brackets'] = function()
  validate_tobj1d('f(xx, (yy, tt))', 5, 'aa', { 5, 14 })
  validate_tobj1d('f(xx, [yy, tt])', 5, 'aa', { 5, 14 })
  validate_tobj1d('f(xx, {yy, tt})', 5, 'aa', { 5, 14 })

  validate_tobj1d('f((xx, yy) , tt)', 10, 'aa', { 3, 12 })
  validate_tobj1d('f([xx, yy] , tt)', 10, 'aa', { 3, 12 })
  validate_tobj1d('f({xx, yy} , tt)', 10, 'aa', { 3, 12 })
end

T['Builtin']['Argument']['ignores commas inside balanced quotes'] = function()
  validate_tobj1d([[f(xx, 'yy, tt', 'aa, bb')]], 5, 'aa', { 5, 14 })
  validate_tobj1d([[f(xx, 'yy, tt', 'aa, bb')]], 15, 'aa', { 15, 24 })

  validate_tobj1d([[f(xx, "yy, tt", "aa, bb")]], 5, 'aa', { 5, 14 })
  validate_tobj1d([[f(xx, "yy, tt", "aa, bb")]], 15, 'aa', { 15, 24 })

  validate_tobj1d([[f('xx, yy' , tt)]], 10, 'aa', { 3, 12 })
  validate_tobj1d([[f("xx, yy" , tt)]], 10, 'aa', { 3, 12 })
end

T['Builtin']['Argument']['ignores empty arguments'] = function()
  validate_tobj1d('f(,)', 0, 'aa', { 3, 3 })
  validate_tobj1d('f(,)', 0, 'ia', { 3, 3 })

  validate_tobj1d('f(, xx)', 0, 'aa', { 3, 3 })
  validate_tobj1d('f(, xx)', 0, 'ia', { 3, 3 })
  validate_tobj1d('f(, xx)', 0, '2aa', { 3, 6 })
  validate_tobj1d('f(, xx)', 0, '2ia', { 5, 6 })

  validate_tobj1d('f(,, xx)', 0, 'aa', { 3, 3 })
  validate_tobj1d('f(,, xx)', 0, 'ia', { 3, 3 })
  validate_tobj1d('f(,, xx)', 0, '2aa', { 4, 7 })
  validate_tobj1d('f(,, xx)', 0, '2ia', { 6, 7 })

  validate_tobj1d('f(xx,, yy)', 0, 'aa', { 3, 5 })
  validate_tobj1d('f(xx,, yy)', 0, 'ia', { 3, 4 })
  validate_tobj1d('f(xx,, yy)', 0, '2aa', { 6, 9 })
  validate_tobj1d('f(xx,, yy)', 0, '2ia', { 8, 9 })

  validate_tobj1d('f(xx, yy,, tt)', 0, '1aa', { 3, 5 })
  validate_tobj1d('f(xx, yy,, tt)', 0, '2aa', { 5, 8 })
  validate_tobj1d('f(xx, yy,, tt)', 0, '3aa', { 9, 9 })
  validate_tobj1d('f(xx, yy,, tt)', 0, '4aa', { 10, 13 })

  validate_tobj1d('f(xx,,)', 0, 'aa', { 3, 5 })
  validate_tobj1d('f(xx,,)', 0, 'ia', { 3, 4 })
  validate_tobj1d('f(xx,,)', 0, '2aa', { 6, 6 })
  validate_tobj1d('f(xx,,)', 0, '2ia', { 7, 7 })

  validate_tobj1d('f(xx,)', 0, 'aa', { 3, 5 })
  validate_tobj1d('f(xx,)', 0, 'ia', { 3, 4 })
end

T['Builtin']['Argument']['works with whitespace argument'] = function()
  -- Single argument
  validate_tobj1d('f(  )', 0, 'aa', { 3, 4 })

  -- First argument (should ignore whitespace)
  validate_tobj1d('f(  ,x)', 0, 'aa', { 5, 5 })
  validate_tobj1d('f(  ,x)', 0, 'ia', { 5, 5 })

  -- Last argument (should ignore whitespace). It misbehaves (`aa` selects all
  -- insteadd of only separator and `ia` goes to rightmost point instead of to
  -- right of separator), but it is acceptable because it is a rare case.
  validate_tobj1d('f(x,  )', 0, '2aa', { 4, 6 })
  validate_tobj1d('f(x,  )', 0, '2ia', { 7, 7 })

  -- Middle argument
  validate_tobj1d('f(x,  ,y)', 0, '2aa', { 4, 6 })
  validate_tobj1d('f(x,  ,y)', 0, '2ia', { 7, 7 })
end

T['Builtin']['Argument']['does not match with cursor on covering bracket'] = function()
  child.lua([[MiniAi.config.search_method = 'cover']])

  validate_no_tobj1d('f(a)', 1, 'aa')
  validate_no_tobj1d('f(a)', 1, 'ia')
  validate_no_tobj1d('f(a)', 3, 'aa')
  validate_no_tobj1d('f(a)', 3, 'ia')
end

T['Builtin']['Argument']['ignores empty brackets'] = function()
  validate_no_tobj1d('f()', 0, 'aa')
  validate_no_tobj1d('f()', 0, 'ia')
end

T['Builtin']['Argument']['works with single argument'] = function()
  validate_tobj1d('f(x)', 0, 'aa', { 3, 3 })
  validate_tobj1d('f(x)', 0, 'ia', { 3, 3 })
  validate_tobj1d('f(xx)', 0, 'aa', { 3, 4 })
  validate_tobj1d('f(xx)', 0, 'ia', { 3, 4 })

  -- Edge whitespace should be a part of `aa`
  validate_tobj1d('f( x)', 0, 'aa', { 3, 4 })
  validate_tobj1d('f( x)', 0, 'ia', { 4, 4 })
  validate_tobj1d('f(x )', 0, 'aa', { 3, 4 })
  validate_tobj1d('f(x )', 0, 'ia', { 3, 3 })
  validate_tobj1d('f( x )', 0, 'aa', { 3, 5 })
  validate_tobj1d('f( x )', 0, 'ia', { 4, 4 })
end

T['Builtin']['Argument']['handles first and last arguments'] = function()
  -- `aa` should work on edge whitespace but ignore it in output (if more than
  -- 2 arguments)

  for i = 2, 7 do
    validate_tobj1d('f(  xx  ,  yy  )', i, 'aa', { 5, 9 })
    validate_tobj1d('f(  xx  ,  yy  )', i, 'ia', { 5, 6 })
  end
  for i = 9, 14 do
    validate_tobj1d('f(  xx  ,  yy  )', i, 'aa', { 9, 13 })
    validate_tobj1d('f(  xx  ,  yy  )', i, 'ia', { 12, 13 })
  end

  -- Edge whitespace should be recognized as part of current argument even in
  -- presence of a bigger covering one
  validate_tobj1d('g(f(  xx  ,  yy  ))', 4, 'aa', { 7, 11 })
  validate_tobj1d('g(f(  xx  ,  yy  ))', 16, 'aa', { 11, 15 })

  -- Newline character should also be ignored
  local lines, cursor = { 'f(  ', '  aa,', '  bb', '  )' }, { 1, 0 }
  validate_tobj(lines, cursor, 'aa', { { 2, 3 }, { 2, 5 } })
  validate_tobj(lines, cursor, 'ia', { { 2, 3 }, { 2, 4 } })
  validate_tobj(lines, cursor, '2aa', { { 2, 5 }, { 3, 4 } })
  validate_tobj(lines, cursor, '2ia', { { 3, 3 }, { 3, 4 } })
end

--stylua: ignore
T['Builtin']['Argument']['works with whitespace padding in separator pattern'] = function()
  child.lua([[MiniAi.config.custom_textobjects = { A = MiniAi.gen_spec.argument({ separator = '%s*,%s*' }) }]])

  -- Visual mode
  for i = 2, 5 do
    validate_tobj1d('f(  xx  ,  yy  ,  zz  )', i, 'aA', { 5, 11 })
    validate_tobj1d('f(  xx  ,  yy  ,  zz  )', i, 'iA', { 5, 6 })
  end
  for i = 11, 12 do
    validate_tobj1d('f(  xx  ,  yy  ,  zz  )', i, 'aA', { 7, 13 })
    validate_tobj1d('f(  xx  ,  yy  ,  zz  )', i, 'iA', { 12, 13 })
  end
  for i = 18, 21 do
    validate_tobj1d('f(  xx  ,  yy  ,  zz  )', i, 'aA', { 14, 20 })
    validate_tobj1d('f(  xx  ,  yy  ,  zz  )', i, 'iA', { 19, 20 })
  end

  -- Operator-pending mode
  validate_edit1d('f( xx  ,   yy    ,     zz )', 3,  'f( yy    ,     zz )', 3, 'daA')
  validate_edit1d('f( xx  ,   yy    ,     zz )', 11, 'f( xx    ,     zz )', 5, 'daA')
  validate_edit1d('f( xx  ,   yy    ,     zz )', 23, 'f( xx  ,   yy )',    13, 'daA')
end

T['Builtin']['Argument']['works in Operator-pending mode'] = function()
  local validate = function(before_line, before_column, after_line, after_column, keys)
    validate_edit1d(before_line, before_column, after_line, after_column, 'd' .. keys)
    validate_edit1d(before_line, before_column, after_line, after_column, 'c' .. keys)
    eq(child.fn.mode(), 'i')
  end

  -- Normal cases
  validate('f(x)', 2, 'f()', 2, 'aa')
  validate('f(x)', 2, 'f()', 2, 'ia')

  validate('f(  x)', 2, 'f()', 2, 'aa')
  validate('f(  x)', 2, 'f(  )', 4, 'ia')

  validate('f(x  )', 2, 'f()', 2, 'aa')
  validate('f(x  )', 2, 'f(  )', 2, 'ia')

  validate('f(  x  )', 2, 'f()', 2, 'aa')
  validate('f(  x  )', 2, 'f(    )', 4, 'ia')

  validate('f(x, y, t)', 2, 'f( y, t)', 2, 'aa')
  validate('f(x, y, t)', 2, 'f(, y, t)', 2, 'ia')
  validate('f(x, y, t)', 5, 'f(x, t)', 3, 'aa')
  validate('f(x, y, t)', 5, 'f(x, , t)', 5, 'ia')
  validate('f(x, y, t)', 8, 'f(x, y)', 6, 'aa')
  validate('f(x, y, t)', 8, 'f(x, y, )', 8, 'ia')

  -- Edge cases
  validate('f( )', 2, 'f()', 2, 'aa')
  validate('f( )', 2, 'f( )', 3, 'ia')

  validate('f(  ,x)', 0, 'f(  x)', 4, 'aa')
  validate('f(  ,x)', 0, 'f(  ,x)', 4, 'ia')
  -- Not ideal but acceptable behavior (see case for whitespace argument)
  validate('f(x,  )', 0, 'f(x)', 3, '2aa')
  validate('f(x,  )', 0, 'f(x,  )', 6, '2ia')

  validate('f(x,,)', 4, 'f(x,)', 4, 'aa')
  validate('f(x,,)', 4, 'f(x,,)', 5, 'ia')
end

T['Builtin']['Function call'] = new_set()

T['Builtin']['Function call']['works'] = function()
  -- Single line
  validate_tobj1d('ff(aa, bb)', 0, 'af', { 1, 10 })
  validate_tobj1d('ff(aa, bb)', 0, 'if', { 4, 9 })

  -- Multiple lines
  validate_tobj({ 'ff(', 'aa, bb', ')' }, { 1, 0 }, 'af', { { 1, 1 }, { 3, 1 } })
  validate_tobj({ 'ff(', 'aa, bb', ')' }, { 1, 0 }, 'if', { { 1, 4 }, { 2, 7 } })

  -- Empty arguments
  validate_tobj1d('ff()', 0, 'af', { 1, 4 })
  validate_tobj1d('ff()', 0, 'if', { 4, 4 })
  validate_edit1d('ff()', 0, 'ff()', 3, 'di)')
  validate_edit1d('ff()', 0, 'ff()', 3, 'ci)')
end

T['Builtin']['Function call']['works consecutively'] = function()
  set_lines({ 'ff(', 'gg(aa) hh(bb)', ')' })
  set_cursor(2, 0)

  -- `a`
  type_keys('v')
  validate_next_region('af', { { 2, 1 }, { 2, 6 } })
  validate_next_region('af', { { 2, 8 }, { 2, 13 } })
  validate_next_region('af', { { 1, 1 }, { 3, 1 } })

  -- `i`
  child.ensure_normal_mode()
  set_cursor(2, 0)
  type_keys('v')
  validate_next_region('if', { { 2, 4 }, { 2, 5 } })
  validate_next_region('if', { { 2, 11 }, { 2, 12 } })
  validate_next_region('if', { { 1, 4 }, { 2, 14 } })
end

T['Builtin']['Function call']['does not work in some cases'] = function()
  -- Although, it would be great if it did

  -- It does not take into account that part is inside string
  validate_tobj1d([[ff(aa, ')', bb)]], 0, 'af', { 1, 9 })

  -- It does not take into account that part is inside comment
  child.bo.commentstring = '# %s'
  validate_tobj({ 'ff(', '# )', ')' }, { 1, 0 }, 'af', { { 1, 1 }, { 2, 3 } })
end

T['Builtin']['Function call']['is detected with "_" and "." in name'] = function()
  validate_tobj1d('ff_ff(aa)', 0, 'af', { 1, 9 })
  validate_tobj1d('ff.ff(aa)', 0, 'af', { 1, 9 })

  validate_tobj1d('big-ff_ff.ff(aa)', 0, 'af', { 5, 16 })
  validate_tobj1d('big ff_ff.ff(aa)', 0, 'af', { 5, 16 })
  validate_tobj1d('[(ff(aa))]', 0, 'af', { 3, 8 })
end

T['Builtin']['Function call']['has limited support of multibyte characters'] = function()
  -- It doesn't support multibyte characters in name due to Lua patterns nature
  validate_no_tobj1d('ыы(aa)', 0, 'af')

  -- But it should work with multibyte characters inside parenthesis
  validate_tobj1d('ff(ыы, фф)', 0, 'af', { 1, 14 })
end

T['Builtin']['Tag'] = new_set()

T['Builtin']['Tag']['works'] = function()
  -- Sinle line
  validate_tobj1d('<x>aaa</x>', 0, 'at', { 1, 10 })
  validate_tobj1d('<x>aaa</x>', 0, 'it', { 4, 6 })

  -- Multiple lines line
  validate_tobj({ '<x>', 'aaa', '</x>' }, { 2, 0 }, 'at', { { 1, 1 }, { 3, 4 } })
  validate_tobj({ '<x>', 'aaa', '</x>' }, { 2, 0 }, 'it', { { 1, 4 }, { 2, 4 } })

  -- Should work with empty tag name
  validate_tobj1d('<>aaa</>', 3, 'at', { 1, 8 })

  -- Should work with empty region
  validate_tobj1d('<x></x>', 0, 'it', { 4, 4 })
  validate_edit1d('<x></x>', 0, '<x></x>', 3, 'dit')
  validate_edit1d('<x></x>', 0, '<x></x>', 3, 'cit')
end

T['Builtin']['Tag']['works consecutively'] = function()
  -- Even with same tags, but not covering
  set_lines({ '<x>', 'aa <y>bb</y> <y>cc</y>', '</x>' })
  set_cursor(2, 0)

  -- `a`
  type_keys('v')
  validate_next_region('at', { { 2, 4 }, { 2, 12 } })
  validate_next_region('at', { { 2, 14 }, { 2, 22 } })
  validate_next_region('at', { { 1, 1 }, { 3, 4 } })

  -- `i`
  child.ensure_normal_mode()
  set_cursor(2, 0)
  type_keys('v')
  validate_next_region('it', { { 2, 7 }, { 2, 8 } })
  validate_next_region('it', { { 2, 17 }, { 2, 18 } })
  validate_next_region('it', { { 1, 4 }, { 2, 23 } })
end

T['Builtin']['Tag']['does not work in some cases'] = function()
  -- Although, it would be great if it did

  -- It does not take into account that part is inside string
  validate_tobj1d([[<x> '</x>' </x>]], 0, 'at', { 1, 9 })

  -- It does not take into account that part is inside comment
  child.bo.commentstring = '# %s'
  validate_tobj({ '<x>', '# </x>', '</x>' }, { 2, 0 }, 'at', { { 1, 1 }, { 2, 6 } })

  -- It can select tags that don't contain same tags inside
  validate_no_tobj1d('<x><x>aaa</x></x>', 7, '2at')
end

T['Builtin']['Tag']['allows extra symbols in opening tag'] = function()
  validate_tobj1d('<x bbb cc_dd!>aaa</x>', 0, 'at', { 1, 21 })

  -- Symbol `<` is not allowed
  validate_no_tobj1d('<x <>aaa</x>', 0, 'at')
end

T['Builtin']['Tag']['detects covering with smallest width'] = function()
  -- In all cases width of `<y>...</y>` is smaller than of `<x>...</x>`
  validate_tobj1d('<x>  <y>a</x></y>', 8, 'at', { 6, 17 })
  validate_tobj1d('<y><x>a</y>  </x>', 6, 'at', { 1, 11 })

  -- Width should be from the left-most point to right-most
  validate_tobj1d('<y><x bbb>a</y></x>', 10, 'at', { 1, 15 })

  -- Works with identical nested tags
  validate_tobj1d('<x><x>aaa</x></x>', 7, 'at', { 4, 13 })
end

T['Builtin']['Tag']['works in edge cases'] = function()
  -- Nesting different tags
  validate_tobj1d('<x><y></y></x>', 1, 'at', { 1, 14 })
  validate_tobj1d('<x><y></y></x>', 3, 'at', { 4, 10 })

  -- End of overlapping tags
  validate_tobj1d('<y><x></y></x>', 12, 'at', { 4, 14 })

  -- `>` between tags
  validate_tobj1d('<x>>aaa</x>', 0, 'at', { 1, 11 })

  -- Similar but different names shouldn't match
  validate_no_tobj1d('<xy>aaa</x>', 0, 'at')
end

T['Builtin']['Tag']['has limited support of multibyte characters'] = function()
  -- It doesn't support multibyte characters in name due to Lua patterns nature
  validate_no_tobj1d('<ы>aaa</ы>', 0, 'at')

  -- But it should work with multibyte characters inside tag
  validate_tobj1d('<x>ыыы</x>', 0, 'at', { 1, 13 })
end

T['Builtin']['User prompt'] = new_set()

T['Builtin']['User prompt']['works'] = function()
  -- Single character edges
  validate_tobj1d('__e__o__', 0, 'a?e<CR>o<CR>', { 3, 6 })
  validate_tobj1d('__e__o__', 0, 'i?e<CR>o<CR>', { 4, 5 })

  -- Multiple character edges
  validate_tobj1d('__ef__op__', 0, 'a?ef<CR>op<CR>', { 3, 8 })
  validate_tobj1d('__ef__op__', 0, 'i?ef<CR>op<CR>', { 5, 6 })
end

T['Builtin']['User prompt']['works consecutively'] = function()
  local keys

  -- Single character edges
  keys = { 'a?', 'e<CR>', 'o<CR>' }
  set_lines({ 'e_e_o_e_o_o' })
  set_cursor(1, 0)

  type_keys('v')
  validate_next_region1d(keys, { 3, 5 })
  validate_next_region1d(keys, { 7, 9 })

  -- Prompt can be changed
  validate_next_region1d({ 'a?', 'o<CR>', 'o<CR>' }, { 5, 9 })

  -- `i` textobject
  child.ensure_normal_mode()
  keys = { 'i?', 'e<CR>', 'o<CR>' }
  set_cursor(1, 0)

  type_keys('v')
  validate_next_region1d(keys, { 4, 4 })
  validate_next_region1d(keys, { 8, 8 })

  -- Multiple character edges
  child.ensure_normal_mode()
  keys = { 'a?', 'ef<CR>', 'op<CR>' }
  set_lines({ 'ef_ef_op_ef_oq_op' })
  set_cursor(1, 0)

  type_keys('v')
  validate_next_region1d(keys, { 4, 8 })
  validate_next_region1d(keys, { 10, 17 })
end

T['Builtin']['User prompt']['works with empty region'] = function() validate_tobj1d('_eo', 0, 'i?e<CR>o<CR>', { 3, 3 }) end

T['Builtin']['User prompt']['can not be covering'] = function()
  set_lines({ 'e_e_o_o' })
  set_cursor(1, 0)
  local keys = { 'a?', 'e<CR>', 'o<CR>' }

  type_keys('v')
  validate_next_region1d(keys, { 3, 5 })

  -- Can't result into covering, so no more matches
  type_keys(keys)
  eq(get_mode(), 'n')
  eq(get_cursor(), { 1, 4 })
  expect.match(get_latest_message(), 'a%?')
end

T['Builtin']['User prompt']['allows dot-repeat'] = function()
  local keys = { 'a?', 'e<CR>', 'o<CR>' }
  set_lines({ 'e1_e2_o3_e4_o5_o6', 'e7_o8' })
  set_cursor(1, 0)

  type_keys('d', keys)
  eq(get_lines(), { 'e1_3_e4_o5_o6', 'e7_o8' })
  type_keys('.')
  eq(get_lines(), { 'e1_3_5_o6', 'e7_o8' })

  -- Allows not immediate dot-repeat
  type_keys('j0', '.')
  eq(get_lines(), { 'e1_3_5_o6', '8' })
end

T['Builtin']['User prompt']['detects covering with smallest width'] = function()
  local keys = { 'a?', '**<CR>', '**<CR>' }
  validate_tobj1d('**a**aa**', 4, keys, { 1, 5 })
  validate_tobj1d('**aa**a**', 4, keys, { 5, 9 })
end

T['Builtin']['User prompt']['works with special characters in prompt'] = function()
  -- "Lua pattern" special
  validate_tobj1d('aa.bb%', 0, { 'a?', '.<CR>', '%<CR>' }, { 3, 6 })

  -- "Multibyte" special. Each multibyte character takes two column counts.
  validate_tobj1d('ы ы ф', 0, { 'a?', 'ы<CR>', 'ф<CR>' }, { 4, 7 })
end

T['Builtin']['User prompt']['handles <C-c>, <Esc>, <CR> in user input'] = function()
  local validate_nothing = function(ai_type, key)
    validate_edit1d('(aaa)', 2, '(aaa)', 2, { 'v', ai_type, '?', key })
    validate_edit1d('(aaa)', 2, '(aaa)', 2, { 'v', ai_type, '?', '(<CR>', key })
  end

  -- Should do nothing on any `<C-c>` and `<Esc>` (in both input and output)
  validate_nothing('a', '<Esc>')
  validate_nothing('i', '<Esc>')
  validate_nothing('a', '<C-c>')
  validate_nothing('i', '<C-c>')
  -- Should stop on `<CR>` because can't use empty string in pattern search
  validate_nothing('a', '<CR>')
  validate_nothing('i', '<CR>')
end

T['Builtin']['User prompt']['colors its prompts'] = function()
  child.set_size(5, 40)
  child.o.showmode = false

  set_lines({ '_aaa!' })
  set_cursor(1, 2)
  type_keys('v', 'a?', '_')
  child.expect_screenshot()
  type_keys('<CR>', '!')
  child.expect_screenshot()
  type_keys('<CR>')

  -- Should clean command line afterwards
  child.expect_screenshot()
end

T['Builtin']['User prompt']['works in edge cases'] = function()
  -- It can't contain edge characters inside
  validate_tobj1d('aa(bb(cc))', 0, { 'a?', '(<CR>', ')<CR>' }, { 6, 9 })
end

T['Builtin']['Default'] = new_set()

T['Builtin']['Default']['works'] = function()
  -- Should allow all possible `getcharstr()` output (but not Latin letters)
  -- Should include only right edge

  local chars = { ',', '.', '_', '*', '-', '0', '1', ' ', '\t', '\\', '\r' }
  for _, key in ipairs(chars) do
    -- Single line
    validate_tobj1d('a' .. key .. 'bb' .. key, 0, 'a' .. key, { 3, 5 })
    validate_tobj1d('a' .. key .. 'bb' .. key, 0, 'i' .. key, { 3, 4 })

    -- Multiple lines
    validate_tobj({ key, 'aa', key }, { 2, 0 }, 'a' .. key, { { 1, 2 }, { 3, 1 } })
    validate_tobj({ key, 'aa', key }, { 2, 0 }, 'i' .. key, { { 1, 2 }, { 2, 3 } })
  end
end

T['Builtin']['Default']['supports any identifier which can be `getcharstr()` output'] = function()
  -- - <C-j> is '\n'
  validate_edit({ 'aaa', 'bbb', 'ccc' }, { 2, 0 }, { 'aaa', 'ccc' }, { 2, 0 }, 'd', 'a', '<C-j>')
  -- - Actually used multibyte (not like `<BS>`)
  validate_edit1d('aыbbы', 0, 'aы', 1, 'd', 'a', 'ы')
  validate_edit1d('a“bb“', 0, 'a“', 1, 'd', 'a', '“')
end

T['Builtin']['Default']['includes maximum right edge characters'] = function()
  validate_tobj1d('aa_bb__cc___', 0, 'a_', { 4, 7 })
  validate_tobj1d('aa_bb__cc___', 0, 'i_', { 4, 5 })
  validate_tobj1d('aa_bb__cc___', 7, 'a_', { 8, 12 })
  validate_tobj1d('aa_bb__cc___', 7, 'i_', { 8, 9 })
end

T['Builtin']['Default']['works consecutively'] = function()
  set_lines({ 'aa_bb__cc___', 'dd__' })
  set_cursor(1, 0)

  -- `a`
  type_keys('v')
  validate_next_region('a_', { { 1, 4 }, { 1, 7 } })
  validate_next_region('a_', { { 1, 8 }, { 1, 12 } })
  validate_next_region('a_', { { 1, 13 }, { 2, 4 } })

  -- `i`
  child.ensure_normal_mode()
  set_cursor(1, 3)
  type_keys('v')
  validate_next_region('i_', { { 1, 4 }, { 1, 5 } })
  validate_next_region('i_', { { 1, 8 }, { 1, 9 } })
  validate_next_region('i_', { { 1, 13 }, { 2, 2 } })
end

T['Builtin']['Default']['works with empty region'] = function()
  validate_tobj1d('a__bb_', 0, 'i_', { 3, 3 })
  validate_edit1d('a__bb_', 0, 'a__bb_', 2, 'di_')
  validate_edit1d('a__bb_', 0, 'a__bb_', 2, 'ci_')

  validate_tobj1d('____', 0, 'i_', { 2, 2 })
  validate_edit1d('____', 0, '____', 1, 'di_')
  validate_edit1d('____', 0, '____', 1, 'ci_')
end

T['Builtin']['Default']['can not be covering'] = function()
  set_lines({ '_aa_bb_' })
  set_cursor(1, 0)

  type_keys('v')
  validate_next_region1d('a_', { 2, 4 })
  validate_next_region1d('a_', { 5, 7 })

  -- Can't result into covering, so no more matches
  type_keys('a_')
  eq(get_mode(), 'n')
  eq(get_cursor(), { 1, 6 })
  expect.match(get_latest_message(), 'a_')
end

T['Builtin']['Default']['detects covering with smallest width'] = function()
  validate_edit1d('_a_bb_', 2, '__bb_', 1, 'di_')
  validate_edit1d('_aa_b_', 3, '_aa__', 4, 'di_')

  validate_edit1d('_a_b_c_b_a_', 5, '_a_b__b_a_', 5, 'di_')
end

local set_custom_tobj = function(tbl) child.lua('MiniAi.config.custom_textobjects = ' .. vim.inspect(tbl)) end

T['Custom textobject'] = new_set()

T['Custom textobject']['works'] = function()
  -- From `MiniAi.config`
  child.lua([[MiniAi.config.custom_textobjects = { x = { 'x()x()x' } }]])
  validate_tobj1d('aaxxxbb', 0, 'ax', { 3, 5 })
  validate_tobj1d('aaxxxbb', 0, 'ix', { 4, 4 })

  -- From `vim.b.miniai_config`
  child.b.miniai_config = { custom_textobjects = { x = { 'y()y()y' } } }
  validate_tobj1d('aayyybb', 0, 'ax', { 3, 5 })
  validate_tobj1d('aayyybb', 0, 'ix', { 4, 4 })
end

T['Custom textobject']['supports any identifier which can be `getcharstr()` output'] = function()
  child.lua([[
    MiniAi.config.custom_textobjects = {
      ['\22'] = { '@().-()#' },
      ['ы']   = { 'Ы().-()Ы' },
      ['「']  = { '「().-()」' },
    }
  ]])

  validate_edit({ '@aaa#' }, { 1, 3 }, { '@#' }, { 1, 1 }, 'd', 'i', '<C-v>')
  validate_edit({ 'ЫaaaЫ' }, { 1, 3 }, { 'ЫЫ' }, { 1, 2 }, 'd', 'i', 'ы')
  validate_edit({ '「aaa」' }, { 1, 3 }, { '「」' }, { 1, 3 }, 'd', 'i', '「')
end

T['Custom textobject']['overrides module builtin'] = function()
  set_custom_tobj({ a = { 'a()a()a' } })
  validate_tobj1d('__aaa__', 0, 'aa', { 3, 5 })
  validate_no_tobj1d('ff(xx)', 0, 'aa')
end

T['Custom textobject']['allows reverting to external mapping'] = function()
  -- Neovim's builtin
  set_custom_tobj({ b = false })
  validate_tobj1d('([{ aaa }])', 5, 'ab', { 1, 11 })

  -- Manual external mapping
  set_custom_tobj({ f = false })
  child.api.nvim_set_keymap('x', 'af', 'iw', { noremap = true })

  child.o.timeoutlen = 5
  set_lines({ 'func(xxx)' })
  set_cursor(1, 0)
  type_keys(10, 'v', 'a', 'f')
  child.expect_visual_marks({ 1, 0 }, { 1, 3 })
end

T['Custom textobject']['works consecutively'] = function()
  set_custom_tobj({ x = { 'x()x()x' } })
  set_lines({ 'xxxxx' })
  set_cursor(1, 0)

  type_keys('v')
  validate_next_region1d('ax', { 1, 3 })
  validate_next_region1d('ax', { 2, 4 })
  validate_next_region1d('ax', { 3, 5 })
end

T['Custom textobject']['expands specification'] = function()
  -- Expantion of array item in multiple arrays
  -- Here this is identical to taking the best match among {'xxx', '.().().'}
  -- and {'aaa', '.().().'}
  set_custom_tobj({ x = { { 'xxx', 'aaa' }, '.().().' } })

  validate_tobj1d('xxxaaaxxx', 0, 'ax', { 1, 3 })
  validate_tobj1d('xxxaaaxxx', 0, 'ix', { 2, 2 })
  validate_tobj1d('xxxaaaxxx', 0, '2ix', { 5, 5 })
  validate_tobj1d('xxxaaaxxx', 0, '3ix', { 8, 8 })

  -- Array items are allowed to be arrays themselves. Here this is identical to
  -- taking the best match among
  -- {'%b()', '^. .* .$', '^.().*().$'} (balanced `()` with inner spaces) and
  -- {'%b[]', '^.[^ ].*[^ ].$', '^.().*().$'} (balanced `[]` without it).
  set_custom_tobj({ y = { { { '%b()', '^. .* .$' }, { '%b[]', '^.[^ ].*[^ ].$' } }, '^.().*().$' } })

  validate_tobj1d('( a ) (b) [ c ] [ddd]', 0, 'ay', { 1, 5 })
  validate_tobj1d('( a ) (b) [ c ] [ddd]', 0, 'iy', { 2, 4 })
  validate_tobj1d('( a ) (b) [ c ] [ddd]', 0, '2ay', { 17, 21 })
  validate_tobj1d('( a ) (b) [ c ] [ddd]', 0, '2iy', { 18, 20 })
end

T['Custom textobject']['handles function as textobject spec'] = function()
  -- Function which returns composed pattern
  child.lua([[MiniAi.config.custom_textobjects = {
    x = function(...) _G.args = {...}; return {'x()x()x'} end
  }]])

  validate_tobj1d('aaxxxbb', 0, 'ax', { 3, 5 })
  -- Should be called with arguments after expanding defaults
  --stylua: ignore
  eq(
    child.lua_get('_G.args'),
    {
      'a', 'x',
      {
        n_lines = 50,
        n_times = 1,
        reference_region = { from = { line = 1, col = 1 }, to = { line = 1, col = 1 } },
        search_method = 'cover_or_next',
      },
    }
  )

  -- Function which returns region. Should take arguments from corresponding
  -- `find_textobject()` call.
  child.lua([[_G.full_buffer = function(ai_type, id, opts)
    local from = { line = 1, col = 1 }
    local to = { line = vim.fn.line('$'), col = vim.fn.getline('$'):len() }
    if ai_type == 'i' then to.col = to.col - 1 end
    return { from = from, to = to }
  end]])
  child.lua([[MiniAi.config.custom_textobjects = { g = _G.full_buffer }]])
  validate_tobj({ 'aaaaa', 'bbbb', 'ccc' }, { 2, 0 }, 'ag', { { 1, 1 }, { 3, 3 } })
  validate_tobj({ 'aaaaa', 'bbbb', 'ccc' }, { 2, 0 }, 'ig', { { 1, 1 }, { 3, 2 } })

  -- Function which returns region array
  child.lua([[_G.long_lines = function(_, _, _)
    local res = {}
    for i = 1, vim.api.nvim_buf_line_count(0) do
      local cur_line = vim.fn.getline(i)
      if vim.fn.strdisplaywidth(cur_line) > 80 then
        local region = { from = { line = i, col = 1 }, to = { line = i, col = cur_line:len() } }
        table.insert(res, region)
      end
    end
    return res
  end]])
  child.lua('MiniAi.config.custom_textobjects = { L = _G.long_lines }')

  local lines = { string.rep('a', 80), string.rep('b', 81), string.rep('c', 80), string.rep('d', 81) }
  validate_tobj(lines, { 1, 0 }, 'aL', { { 2, 1 }, { 2, 81 } })
  validate_tobj(lines, { 2, 0 }, 'aL', { { 2, 1 }, { 2, 81 } })

  child.lua([[MiniAi.config.search_method = 'next']])
  validate_tobj(lines, { 2, 0 }, 'aL', { { 4, 1 }, { 4, 81 } })

  child.lua('MiniAi.config.n_lines = 0')
  validate_no_tobj(lines, { 2, 0 }, 'aL')

  -- Function which returns region array with `vis_mode` set
  child.lua([[MiniAi.config.search_method = 'cover']])
  child.lua('MiniAi.config.n_lines = 50')
  child.lua([[_G.line_regions = function(_, _, _)
    return {
      { from = { line = 1, col = 1 }, to = { line = 2, col = 1 }, vis_mode = 'V' },
      { from = { line = 3, col = 1 }, to = { line = 4, col = 1 }, vis_mode = 'V' },
    }
  end]])
  child.lua('MiniAi.config.custom_textobjects = { m = _G.line_regions }')

  set_lines({ 'aaa', 'bbb', 'ccc', 'ddd' })
  set_cursor(3, 0)
  type_keys('d', 'a', 'm')
  eq(get_lines(), { 'aaa', 'bbb' })
end

T['Custom textobject']['handles function as specification item'] = function()
  child.lua([[_G.c_spec = {
    '%b()',
    function(s, init) if init > 1 then return end; return 2, s:len() end,
    '^().*().$'
  }]])
  child.lua([[MiniAi.config.custom_textobjects = { c = _G.c_spec }]])
  validate_tobj1d('aa(bb)', 0, 'ac', { 4, 6 })
  validate_tobj1d('aa(bb)', 0, 'ic', { 4, 5 })
end

T['Custom textobject']['handles different extractions in last spec item'] = new_set({
  parametrize = {
    { 'xxx', { 1, 3 }, { 1, 3 } },
    { 'x()x()x', { 1, 3 }, { 2, 2 } },
    { '()x()x()x()', { 1, 3 }, { 2, 2 } },
    { 'x()()()xx()', { 2, 3 }, { 2, 2 } },
    { '()xx()()()x', { 1, 2 }, { 3, 3 } },
  },
}, {
  test = function(pattern, a_result, i_result)
    set_custom_tobj({ x = { pattern } })
    validate_tobj1d('xxx', 0, 'ax', a_result)
    validate_tobj1d('xxx', 0, 'ix', i_result)
  end,
})

T['Custom textobject']['works with special patterns'] = new_set()

T['Custom textobject']['works with special patterns']['%bxx'] = function()
  -- `%bxx` should represent balanced character
  set_custom_tobj({ e = { '%bee' } })

  local line = 'e e e e e'
  for i = 0, 2 do
    validate_tobj1d(line, i, 'ae', { 1, 3 })
  end
  for i = 3, 6 do
    validate_tobj1d(line, i, 'ae', { 5, 7 })
  end
  for i = 7, 8 do
    validate_no_tobj1d(line, i, 'ae')
  end
end

T['Custom textobject']['works with special patterns']['x.-y'] = function()
  -- `x.-y` should match the smallest possible width
  set_custom_tobj({ x = { 'e.-o', '^.().*().$' } })
  validate_tobj1d('e e o o e o', 0, 'ax', { 3, 5 })
  validate_tobj1d('e e o o e o', 0, '2ax', { 9, 11 })

  -- `x.-y` should work with `a%.-a` and `a.%-a`
  set_custom_tobj({ y = { 'y%.-y' } })
  validate_tobj1d('y.y yay y..y', 0, 'ay', { 1, 3 })
  validate_tobj1d('y.y yay y..y', 0, '2ay', { 9, 12 })

  set_custom_tobj({ c = { 'c.%-c' } })
  validate_tobj1d('c_-c c__c c+-c', 0, 'ac', { 1, 4 })
  validate_tobj1d('c_-c c__c c+-c', 0, '2ac', { 11, 14 })

  -- `x.-y` should allow patterns with `+` quantifiers
  -- To improve, force other character in between (`%f[x]x+[^x]-x+%f[^x]`)
  set_custom_tobj({ r = { 'r+.-r+' } })
  validate_tobj1d('rraarr', 0, 'ar', { 5, 6 })
  validate_tobj1d('rrrr', 0, 'ar', { 3, 4 })
end

T['Custom textobject']['works with empty region'] = function()
  set_custom_tobj({ x = { 'x()()()xx()' } })
  validate_tobj1d('xxx', 0, 'ix', { 2, 2 })
  validate_edit1d('xxx', 0, 'xxx', 1, 'dix')
  validate_edit1d('xxx', 0, 'xxx', 1, 'cix')
end

T['Custom textobject']['works with quantifiers in patterns'] = function()
  set_custom_tobj({ x = { '%f[x]x+%f[^x]' } })
  validate_tobj1d('axaxxaxxx', 0, 'ax', { 2, 2 })
  validate_tobj1d('axaxxaxxx', 0, '2ax', { 4, 5 })
  validate_tobj1d('axaxxaxxx', 0, '3ax', { 7, 9 })
end

T['Custom textobject']['works with multibyte characters'] = function()
  set_custom_tobj({ x = { 'ыы фф', '^.-() ().-$' } })
  validate_tobj1d('ыы ыы фф фф', 0, 'ax', { 6, 13 })
end

T['Custom textobject']['documented examples'] = new_set()

T['Custom textobject']['documented examples']['function call with name from user input'] = function()
  child.lua([[_G.fun_prompt = function()
    local left_edge = vim.pesc(vim.fn.input('Function name: '))
    return { string.format('%s+%%b()', left_edge), '^.-%(().*()%)$' }
  end]])
  child.lua('MiniAi.config.custom_textobjects = { F = _G.fun_prompt }')

  validate_tobj1d('aa(xx) bb(xx)', 0, 'aFbb<CR>', { 8, 13 })
  validate_tobj1d('aa(xx) bb(xx)', 0, 'iFbb<CR>', { 11, 12 })
end

T['Custom textobject']['documented examples']['full buffer'] = function()
  child.lua([[_G.full_buffer = function()
    local from = { line = 1, col = 1 }
    local to = { line = vim.fn.line('$'), col = math.max(vim.fn.getline('$'):len(), 1) }
    return { from = from, to = to, vis_mode = 'V' }
  end]])
  child.lua('MiniAi.config.custom_textobjects = { g = _G.full_buffer }')

  validate_tobj({ 'aaaa', 'bbb', 'cc' }, { 2, 0 }, 'ag', { 1, 3 }, 'V')
  validate_tobj({ '' }, { 1, 0 }, 'ag', { 1, 1 }, 'V')
end

T['Custom textobject']['documented examples']['wide lines'] = function()
  child.lua([[_G.long_lines = function(_, _, _)
    local res = {}
    for i = 1, vim.api.nvim_buf_line_count(0) do
      local cur_line = vim.fn.getline(i)
      if vim.fn.strdisplaywidth(cur_line) > 80 then
        local region = { from = { line = i, col = 1 }, to = { line = i, col = cur_line:len() } }
        table.insert(res, region)
      end
    end
    return res
  end]])
  child.lua('MiniAi.config.custom_textobjects = { L = _G.long_lines }')

  local lines = { string.rep('a', 80), string.rep('b', 81), string.rep('c', 80), string.rep('d', 81) }
  validate_tobj(lines, { 1, 0 }, 'aL', { { 2, 1 }, { 2, 81 } })
  validate_tobj(lines, { 2, 0 }, 'aL', { { 2, 1 }, { 2, 81 } })

  child.lua([[MiniAi.config.search_method = 'next']])
  validate_tobj(lines, { 2, 0 }, 'aL', { { 4, 1 }, { 4, 81 } })

  child.lua([[MiniAi.config.n_lines = 0]])
  validate_no_tobj(lines, { 2, 0 }, 'aL')
end

T['Custom textobject']['documented examples']['balanced parenthesis with big enough width'] = function()
  child.lua([[_G.wide_parens_spec = {
    '%b()',
    function(s, init)
      if init > 1 or s:len() < 5 then return end
      return 1, s:len()
    end,
    '^.().*().$'
  }]])
  child.lua('MiniAi.config.custom_textobjects = { p = _G.wide_parens_spec }')

  validate_tobj1d('() (a) (aa) (aaa)', 0, 'ap', { 13, 17 })
end

T['Custom textobject']['documented examples']['word'] = function()
  set_custom_tobj({ w = { '()()%f[%w]%w+()[ \t]*()' } })

  validate_tobj1d('  aaa  bb_cc.dd ', 0, 'aw', { 3, 7 })
  validate_tobj1d('  aaa  bb_cc.dd ', 0, 'iw', { 3, 5 })
  validate_tobj1d('  aaa  bb_cc.dd ', 0, '2aw', { 8, 9 })
  validate_tobj1d('  aaa  bb_cc.dd ', 0, '3aw', { 11, 12 })
  validate_tobj1d('  aaa  bb_cc.dd ', 0, '4aw', { 14, 16 })

  validate_tobj({ 'aaa ' }, { 1, 0 }, 'aw', { { 1, 1 }, { 1, 4 } })
  validate_tobj({ 'aaa\t' }, { 1, 0 }, 'aw', { { 1, 1 }, { 1, 4 } })
  validate_tobj({ 'aaa', 'bbb' }, { 1, 0 }, 'aw', { { 1, 1 }, { 1, 3 } })
end

T['Custom textobject']['documented examples']['camel case word'] = function()
  set_custom_tobj({
    c = {
      { '%u[%l%d]+%f[^%l%d]', '%f[%S][%l%d]+%f[^%l%d]', '%f[%P][%l%d]+%f[^%l%d]', '^[%l%d]+%f[^%l%d]' },
      '^().*()$',
    },
  })

  validate_tobj1d('  aaaBbb_ccc_Ddd', 0, 'ac', { 3, 5 })
  validate_tobj1d('  aaaBbb_ccc_Ddd', 0, '2ac', { 6, 8 })
  validate_tobj1d('  aaaBbb_ccc_Ddd', 0, '3ac', { 10, 12 })
  validate_tobj1d('  aaaBbb_ccc_Ddd', 0, '4ac', { 14, 16 })
  validate_tobj1d('aaa', 0, 'ac', { 1, 3 })

  validate_no_tobj1d('  A', 0, 'ac')
end

T['Custom textobject']['documented examples']['number'] = function()
  set_custom_tobj({ N = { '%f[%d]%d+' } })

  validate_tobj1d(' 1 10_11', 0, 'aN', { 2, 2 })
  validate_tobj1d(' 1 10_11', 0, '2aN', { 4, 5 })
  validate_tobj1d(' 1 10_11', 0, '3aN', { 7, 8 })
end

T['Custom textobject']['documented examples']['date'] = function()
  set_custom_tobj({ d = { '()%d%d%d%d%-%d%d%-%d%d()' } })

  validate_tobj1d(' 2022-07-26 9999-99-99', 0, 'ad', { 2, 11 })
  validate_tobj1d(' 2022-07-26 9999-99-99', 0, '2ad', { 13, 22 })
end

T['Custom textobject']['documented examples']['Lua block string'] = function()
  set_custom_tobj({ s = { '%[%[().-()%]%]' } })
  validate_tobj1d([=[aa[[bb]]]=], 0, 'as', { 3, 8 })
  validate_tobj1d([=[aa[[bb]]]=], 0, 'is', { 5, 6 })

  local line = [=[aa[[]]]=]
  validate_tobj1d(line, 0, 'is', { 5, 5 })
  validate_edit1d(line, 0, line, 4, 'dis')
  validate_edit1d(line, 0, line, 4, 'cis')
end

return T
