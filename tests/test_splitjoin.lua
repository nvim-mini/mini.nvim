local helpers = dofile('tests/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
local load_module = function(config) child.mini_load('splitjoin', config) end
local unload_module = function() child.mini_unload('splitjoin') end
local reload_module = function(config) child.mini_reload('splitjoin', config) end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
local validate_edit = function(...) return child.validate_edit(...) end

-- Helper wrappers
local simplepos_to_pos = function(x) return { line = x[1], col = x[2] } end

local validate_positions = function(out, ref) eq(out, vim.tbl_map(simplepos_to_pos, ref)) end

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
  eq(child.lua_get('type(_G.MiniSplitjoin)'), 'table')
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniSplitjoin.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniSplitjoin.config.' .. field), value) end

  expect_config('mappings.toggle', 'gS')
  expect_config('mappings.split', '')
  expect_config('mappings.join', '')

  expect_config('detect.brackets', vim.NIL)
  expect_config('detect.separator', ',')
  expect_config('detect.exclude_regions', vim.NIL)

  expect_config('split.hooks_pre', {})
  expect_config('split.hooks_post', {})

  expect_config('join.hooks_pre', {})
  expect_config('join.hooks_post', {})
end

T['setup()']['respects `config` argument'] = function()
  unload_module()
  load_module({ detect = { separator = '[,;]' } })
  eq(child.lua_get('MiniSplitjoin.config.detect.separator'), '[,;]')
end

T['setup()']['validates `config` argument'] = function()
  unload_module()

  local expect_config_error = function(config, name, target_type)
    expect.error(function() load_module(config) end, vim.pesc(name) .. '.*' .. vim.pesc(target_type))
  end

  expect_config_error('a', 'config', 'table')

  expect_config_error({ mappings = 'a' }, 'mappings', 'table')
  expect_config_error({ mappings = { toggle = 1 } }, 'mappings.toggle', 'string')
  expect_config_error({ mappings = { split = 1 } }, 'mappings.split', 'string')
  expect_config_error({ mappings = { join = 1 } }, 'mappings.join', 'string')

  expect_config_error({ detect = 'a' }, 'detect', 'table')
  expect_config_error({ detect = { brackets = 1 } }, 'detect.brackets', 'table')
  expect_config_error({ detect = { separator = 1 } }, 'detect.separator', 'string')
  expect_config_error({ detect = { exclude_regions = 1 } }, 'detect.exclude_regions', 'table')

  expect_config_error({ split = 'a' }, 'split', 'table')
  expect_config_error({ split = { hooks_pre = 1 } }, 'split.hooks_pre', 'table')
  expect_config_error({ split = { hooks_post = 1 } }, 'split.hooks_post', 'table')

  expect_config_error({ join = 'a' }, 'join', 'table')
  expect_config_error({ join = { hooks_pre = 1 } }, 'join.hooks_pre', 'table')
  expect_config_error({ join = { hooks_post = 1 } }, 'join.hooks_post', 'table')
end

T['setup()']['properly creates mappings'] = function()
  local has_map = function(mode, lhs, pattern) return child.cmd_capture(mode .. 'map ' .. lhs):find(pattern) ~= nil end
  eq(has_map('n', 'gS', 'Toggle'), true)
  eq(has_map('x', 'gS', 'Toggle'), true)
  eq(has_map('n', 'gj', 'Join'), false)
  eq(has_map('x', 'gj', 'Join'), false)

  unload_module()
  child.api.nvim_del_keymap('n', 'gS')
  child.api.nvim_del_keymap('x', 'gS')

  -- Supplying empty string should mean "don't create keymaps"
  load_module({ mappings = { toggle = '', join = 'gj' } })
  eq(has_map('n', 'gS', 'Toggle'), false)
  eq(has_map('x', 'gS', 'Toggle'), false)
  eq(has_map('n', 'gj', 'Join'), true)
  eq(has_map('x', 'gj', 'Join'), true)
end

-- Most of action specific tests are done in their functions
T['toggle()'] = new_set()

local toggle = function(...) return child.lua_get('MiniSplitjoin.toggle(...)', { ... }) end

T['toggle()']['works'] = function()
  validate_edit({ '(aaa, bb, c)' }, { 1, 0 }, toggle, { '(', '\taaa,', '\tbb,', '\tc', ')' }, { 1, 0 })
  validate_edit({ '[aaa, bb, c]' }, { 1, 0 }, toggle, { '[', '\taaa,', '\tbb,', '\tc', ']' }, { 1, 0 })
  validate_edit({ '{aaa, bb, c}' }, { 1, 0 }, toggle, { '{', '\taaa,', '\tbb,', '\tc', '}' }, { 1, 0 })

  validate_edit({ '(', '\taaa,', '\tbb,', '\tc', ')' }, { 1, 0 }, toggle, { '(aaa, bb, c)' }, { 1, 0 })
  validate_edit({ '[', '\taaa,', '\tbb,', '\tc', ']' }, { 1, 0 }, toggle, { '[aaa, bb, c]' }, { 1, 0 })
  validate_edit({ '{', '\taaa,', '\tbb,', '\tc', '}' }, { 1, 0 }, toggle, { '{aaa, bb, c}' }, { 1, 0 })
end

T['toggle()']['explicitly calls `split()` or `join()`'] = function()
  local default_opts = {
    detect = {
      brackets = { '%b()', '%b[]', '%b{}' },
      exclude_regions = { '%b()', '%b[]', '%b{}', '%b""', "%b''" },
      separator = ',',
    },
    join = {
      hooks_post = {},
      hooks_pre = {},
    },
    split = {
      hooks_post = {},
      hooks_pre = {},
    },
  }

  -- Split
  child.lua('MiniSplitjoin.split = function(...) _G.split_args = {...} end')

  set_lines({ '(aa, b)' })
  set_cursor(1, 1)
  toggle()

  local ref_split_args = vim.deepcopy(default_opts)
  ref_split_args.position = { line = 1, col = 2 }
  ref_split_args.region = { from = { line = 1, col = 1 }, to = { line = 1, col = 7 } }

  eq(child.lua_get('_G.split_args'), { ref_split_args })

  -- Join
  child.lua('MiniSplitjoin.join = function(...) _G.join_args = {...} end')

  set_lines({ '(', 'aa', 'b)' })
  set_cursor(2, 1)
  toggle()

  local ref_join_args = vim.deepcopy(default_opts)
  ref_join_args.position = { line = 2, col = 2 }
  ref_join_args.region = { from = { line = 1, col = 1 }, to = { line = 3, col = 2 } }

  eq(child.lua_get('_G.join_args'), { ref_join_args })
end

T['toggle()']['respects `opts.position`'] = function()
  local f = function() toggle({ position = { line = 1, col = 2 } }) end
  validate_edit({ ' (aa)' }, { 1, 0 }, f, { ' (', ' \taa', ' )' }, { 1, 0 })
  f = function() toggle({ position = { line = 1, col = 1 } }) end
  validate_edit({ ' (aa)' }, { 1, 1 }, f, { ' (aa)' }, { 1, 1 })
end

T['toggle()']['respects `opts.region`'] = function()
  -- Force join instead of split
  set_lines({ '(a, ")"', ')' })
  set_cursor(1, 0)
  toggle({ region = { from = { line = 1, col = 1 }, to = { line = 2, col = 1 } } })
  eq(get_lines(), { '(a, ")")' })

  -- Force split instead of join
  set_lines({ '(a)', ']' })
  set_cursor(1, 0)
  toggle({ region = { from = { line = 1, col = 1 }, to = { line = 2, col = 1 } } })
  eq(get_lines(), { '(a)]' })
end

T['toggle()']['respects `opts.detect.brackets`'] = function()
  -- Global
  child.lua("MiniSplitjoin.config.detect.brackets = { '%b{}' }")
  validate_edit({ '[aaa]' }, { 1, 0 }, toggle, { '[aaa]' }, { 1, 0 })
  validate_edit({ '{aaa}' }, { 1, 0 }, toggle, { '{', '\taaa', '}' }, { 1, 0 })

  -- Local
  local f = function() toggle({ detect = { brackets = {} } }) end
  validate_edit({ '(aaa)' }, { 1, 0 }, f, { '(aaa)' }, { 1, 0 })
  f = function() toggle({ detect = { brackets = { '%b[]' } } }) end
  validate_edit({ '(aaa)' }, { 1, 0 }, f, { '(aaa)' }, { 1, 0 })
end

T['toggle()']['returns `nil` if no positions are found'] = function()
  set_lines({ 'aaa' })
  eq(toggle(), vim.NIL)
  eq(get_lines(), { 'aaa' })
end

T['toggle()']['respects `vim.{g,b}.minisplitjoin_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minisplitjoin_disable = true
    validate_edit({ '(aaa)' }, { 1, 0 }, toggle, { '(aaa)' }, { 1, 0 })
  end,
})

T['toggle()']['respects `vim.b.minisplitjoin_config`'] = function()
  child.lua([[vim.b.minisplitjoin_config = { detect = { brackets = { '%b[]' } } }]])
  validate_edit({ '(aaa)' }, { 1, 0 }, toggle, { '(aaa)' }, { 1, 0 })
end

T['split()'] = new_set()

local split = function(...) return child.lua_get('MiniSplitjoin.split(...)', { ... }) end

T['split()']['works'] = function()
  validate_edit({ '(aaa, bb, c)' }, { 1, 0 }, split, { '(', '\taaa,', '\tbb,', '\tc', ')' }, { 1, 0 })
  validate_edit({ '[aaa, bb, c]' }, { 1, 0 }, split, { '[', '\taaa,', '\tbb,', '\tc', ']' }, { 1, 0 })
  validate_edit({ '{aaa, bb, c}' }, { 1, 0 }, split, { '{', '\taaa,', '\tbb,', '\tc', '}' }, { 1, 0 })
end

T['split()']['works for arguments on multiple lines'] = function()
  validate_edit({ '(a', 'b', 'c)' }, { 1, 0 }, split, { '(', '\ta', '\tb', '\tc', ')' }, { 1, 0 })
  validate_edit({ '(a', '\tb', '\t\tc)' }, { 1, 0 }, split, { '(', '\ta', '\t\tb', '\t\t\tc', '\t\t)' }, { 1, 0 })

  validate_edit({ '(a', 'b, c', 'd)' }, { 1, 0 }, split, { '(', '\ta', '\tb,', '\tc', '\td', ')' }, { 1, 0 })

  -- This can be better, but currently is outside of cost/benefit ratio
  validate_edit({ '(', '\ta,', '\tb', ')' }, { 1, 0 }, split, { '(', '', '\t\ta,', '\t', '\t\tb', '\t)' }, { 1, 0 })
end

T['split()']['works on any part inside or on brackets'] = function()
  validate_edit({ 'b( a )b' }, { 1, 0 }, split, { 'b( a )b' }, { 1, 0 })
  validate_edit({ 'b( a )b' }, { 1, 1 }, split, { 'b(', '\ta', ')b' }, { 1, 1 })
  validate_edit({ 'b( a )b' }, { 1, 2 }, split, { 'b(', '\ta', ')b' }, { 2, 1 })
  validate_edit({ 'b( a )b' }, { 1, 3 }, split, { 'b(', '\ta', ')b' }, { 2, 1 })
  validate_edit({ 'b( a )b' }, { 1, 4 }, split, { 'b(', '\ta', ')b' }, { 2, 1 })
  validate_edit({ 'b( a )b' }, { 1, 5 }, split, { 'b(', '\ta', ')b' }, { 3, 0 })
  validate_edit({ 'b( a )b' }, { 1, 6 }, split, { 'b( a )b' }, { 1, 6 })
end

T['split()']['works on indented line'] = function()
  validate_edit({ '\t (aaa, bb, c)' }, { 1, 2 }, split, { '\t (', '\t \taaa,', '\t \tbb,', '\t \tc', '\t )' }, { 1, 2 })
end

T['split()']['works inside comments'] = function()
  -- After 'commentstring'
  child.bo.commentstring = '# %s'
  validate_edit({ '# (aaa)' }, { 1, 2 }, split, { '# (', '# \taaa', '# )' }, { 1, 2 })

  -- After any entry in 'comments'
  child.bo.comments = ':---,:--'
  validate_edit({ '-- (aaa)' }, { 1, 3 }, split, { '-- (', '-- \taaa', '-- )' }, { 1, 3 })
  validate_edit({ '--- (aaa)' }, { 1, 4 }, split, { '--- (', '--- \taaa', '--- )' }, { 1, 4 })

  -- Respects `b` flag
  child.bo.comments = 'b:*'
  validate_edit({ '*(aaa)' }, { 1, 1 }, split, { '*(', '\taaa', ')' }, { 1, 1 })
  validate_edit({ '* (aaa)' }, { 1, 2 }, split, { '* (', '* \taaa', '* )' }, { 1, 2 })
  validate_edit({ '*\t(aaa)' }, { 1, 2 }, split, { '*\t(', '*\t\taaa', '*\t)' }, { 1, 2 })

  -- Respects `f` flag (ignores as comment leader)
  child.bo.comments = 'f:-'
  validate_edit({ '-(aaa)' }, { 1, 1 }, split, { '-(', '\taaa', ')' }, { 1, 1 })
  validate_edit({ '- (aaa)' }, { 1, 2 }, split, { '- (', '\taaa', ')' }, { 1, 2 })
  validate_edit({ '-\t(aaa)' }, { 1, 2 }, split, { '-\t(', '\taaa', ')' }, { 1, 2 })
end

T['split()']['works with trailing separator'] = function()
  validate_edit({ '(aa, b,)' }, { 1, 0 }, split, { '(', '\taa,', '\tb,', ')' }, { 1, 0 })
end

T['split()']['correctly increases indent of commented line in non-commented block'] = function()
  child.bo.commentstring = '# %s'
  validate_edit({ '(aa', '# b', 'c)' }, { 1, 0 }, split, { '(', '\taa', '\t# b', '\tc', ')' }, { 1, 0 })
end

T['split()']['ignores separators inside nested arguments'] = function()
  validate_edit(
    { '(a, (b, c), [d, e], {f, e})' },
    { 1, 0 },
    split,
    { '(', '\ta,', '\t(b, c),', '\t[d, e],', '\t{f, e}', ')' },
    { 1, 0 }
  )
end

T['split()']['ignores separators inside quotes'] = function()
  validate_edit({ [[(a, 'b, c', "d, e")]] }, { 1, 0 }, split, { '(', '\ta,', "\t'b, c',", '\t"d, e"', ')' }, { 1, 0 })
end

T['split()']['works in empty brackets'] = function()
  validate_edit({ '()' }, { 1, 0 }, split, { '(', ')' }, { 1, 0 })
  validate_edit({ '()' }, { 1, 1 }, split, { '(', ')' }, { 2, 0 })
end

T['split()']["respects 'expandtab' and 'shiftwidth' for indenting"] = function()
  child.o.expandtab = true
  child.o.shiftwidth = 3
  validate_edit({ '(aaa)' }, { 1, 0 }, split, { '(', '   aaa', ')' }, { 1, 0 })
end

T['split()']['returns `nil` if no positions are found'] = function()
  -- Not found during initial step
  set_lines({ 'aaa' })
  eq(split(), vim.NIL)
  eq(get_lines(), { 'aaa' })

  -- Not found after splitting
  set_lines({ '(aa, bb)' })
  local out = child.lua_get('MiniSplitjoin.split({ split = { hooks_pre = { function() return {} end } } })')
  eq(out, vim.NIL)
  eq(get_lines(), { '(aa, bb)' })
end

T['split()']['respects `opts.position`'] = function()
  local f = function() split({ position = { line = 1, col = 2 } }) end
  validate_edit({ ' (aaa)' }, { 1, 0 }, f, { ' (', ' \taaa', ' )' }, { 1, 0 })
  f = function() split({ position = { line = 1, col = 1 } }) end
  validate_edit({ ' (aaa)' }, { 1, 1 }, f, { ' (aaa)' }, { 1, 1 })
end

T['split()']['respects `opts.region`'] = function()
  local lines = { '(a, ")", b)' }
  local region = { from = { line = 1, col = 1 }, to = { line = 1, col = 11 } }
  local f = function() split({ region = region }) end
  validate_edit(lines, { 1, 0 }, f, { '(', '\ta,', '\t")",', '\tb', ')' }, { 1, 0 })
end

T['split()']['respects `opts.detect.brackets`'] = function()
  -- Global
  child.lua("MiniSplitjoin.config.detect.brackets = { '%b{}' }")
  validate_edit({ '[aaa]' }, { 1, 0 }, split, { '[aaa]' }, { 1, 0 })
  validate_edit({ '{aaa}' }, { 1, 0 }, split, { '{', '\taaa', '}' }, { 1, 0 })

  -- Local
  local f = function() split({ detect = { brackets = {} } }) end
  validate_edit({ '(aaa)' }, { 1, 0 }, f, { '(aaa)' }, { 1, 0 })
  f = function() split({ detect = { brackets = { '%b[]' } } }) end
  validate_edit({ '(aaa)' }, { 1, 0 }, f, { '(aaa)' }, { 1, 0 })
end

T['split()']['respects `opts.detect.separator`'] = function()
  -- Global
  child.lua("MiniSplitjoin.config.detect.separator = '|'")
  validate_edit({ '(a|b)' }, { 1, 0 }, split, { '(', '\ta|', '\tb', ')' }, { 1, 0 })

  -- Local
  local f = function() split({ detect = { separator = '[,;]' } }) end
  validate_edit({ '(a, b; c)' }, { 1, 0 }, f, { '(', '\ta,', '\tb;', '\tc', ')' }, { 1, 0 })

  -- Empty separator should mean no internal separator
  f = function() split({ detect = { separator = '' } }) end
  validate_edit({ '(a, b; c)' }, { 1, 0 }, f, { '(', '\ta, b; c', ')' }, { 1, 0 })
end

T['split()']['respects `opts.detect.exclude_regions`'] = function()
  -- Global
  child.lua("MiniSplitjoin.config.detect.exclude_regions = { '%b[]' }")
  validate_edit(
    { '(a, (b, c), [d, e])' },
    { 1, 0 },
    split,
    { '(', '\ta,', '\t(b,', '\tc),', '\t[d, e]', ')' },
    { 1, 0 }
  )

  -- Local
  local f = function() split({ detect = { exclude_regions = { '%b()' } } }) end
  validate_edit({ '(a, (b, c), [d, e])' }, { 1, 0 }, f, { '(', '\ta,', '\t(b, c),', '\t[d,', '\te]', ')' }, { 1, 0 })
end

T['split()']['respects `opts.split.hooks_pre`'] = function()
  child.lua('_G.hook_pre_1 = function(...) _G.hook_pre_1_args = { ... }; return ... end')
  child.lua([[_G.hook_pre_2 = function(positions)
    _G.hook_pre_2_positions = positions
    return { positions[1] } end
  ]])

  local positions_ref = { { line = 1, col = 1 }, { line = 1, col = 4 } }

  -- Global
  child.lua('MiniSplitjoin.config.split.hooks_pre = { _G.hook_pre_2 }')
  set_lines({ '(aaa)' })
  split()
  eq(get_lines(), { '(', 'aaa)' })
  eq(child.lua_get('_G.hook_pre_1_args'), vim.NIL)
  eq(child.lua_get('_G.hook_pre_2_positions'), positions_ref)

  -- Local
  set_lines({ '(aaa)' })
  child.lua('MiniSplitjoin.split({ split = { hooks_pre = { _G.hook_pre_1, _G.hook_pre_2 } } })')
  eq(get_lines(), { '(', 'aaa)' })
  eq(child.lua_get('_G.hook_pre_1_args'), { positions_ref })
  eq(child.lua_get('_G.hook_pre_2_positions'), positions_ref)
end

T['split()']['respects `opts.split.hooks_post`'] = function()
  child.lua('_G.hook_post_1 = function(...) _G.hook_post_1_args = { ... }; return ... end')
  child.lua([[_G.hook_post_2 = function(positions)
    _G.hook_post_2_positions = positions
    return { positions[1] } end
  ]])

  local positions_ref = { { line = 1, col = 1 }, { line = 2, col = 4 }, { line = 3, col = 1 } }

  -- Global
  child.lua('MiniSplitjoin.config.split.hooks_post = { _G.hook_post_2 }')
  set_lines({ '(aaa)' })
  local out = split()
  eq(out, { { line = 1, col = 1 } })

  eq(get_lines(), { '(', '\taaa', ')' })
  eq(child.lua_get('_G.hook_post_1_args'), vim.NIL)
  eq(child.lua_get('_G.hook_post_2_positions'), positions_ref)

  -- Local
  set_lines({ '(aaa)' })
  out = child.lua_get('MiniSplitjoin.split({ split = { hooks_post = { _G.hook_post_1, _G.hook_post_2 } } })')
  eq(out, { { line = 1, col = 1 } })

  eq(get_lines(), { '(', '\taaa', ')' })
  eq(child.lua_get('_G.hook_post_1_args'), { positions_ref })
  eq(child.lua_get('_G.hook_post_2_positions'), positions_ref)
end

T['split()']['respects `vim.{g,b}.minisplitjoin_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minisplitjoin_disable = true
    validate_edit({ '(aaa)' }, { 1, 0 }, split, { '(aaa)' }, { 1, 0 })
  end,
})

T['split()']['respects `vim.b.minisplitjoin_config`'] = function()
  child.lua([[vim.b.minisplitjoin_config = { detect = { brackets = { '%b[]' } } }]])
  validate_edit({ '(aaa)' }, { 1, 0 }, split, { '(aaa)' }, { 1, 0 })
end

T['join()'] = new_set()

local join = function(...) return child.lua_get('MiniSplitjoin.join(...)', { ... }) end

T['join()']['works'] = function()
  validate_edit({ '(', '\taaa,', '\tbb,', '\tc', ')' }, { 1, 0 }, join, { '(aaa, bb, c)' }, { 1, 0 })
  validate_edit({ '[', '\taaa,', '\tbb,', '\tc', ']' }, { 1, 0 }, join, { '[aaa, bb, c]' }, { 1, 0 })
  validate_edit({ '{', '\taaa,', '\tbb,', '\tc', '}' }, { 1, 0 }, join, { '{aaa, bb, c}' }, { 1, 0 })

  validate_edit({ '(', 'aaa)' }, { 1, 0 }, join, { '(aaa)' }, { 1, 0 })
  validate_edit({ ' \t(', 'aaa)' }, { 1, 2 }, join, { ' \t(aaa)' }, { 1, 2 })
end

T['join()']['does nothing if arguments are on single line'] = function()
  validate_edit({ '(aa, b)' }, { 1, 0 }, join, { '(aa, b)' }, { 1, 0 })
end

T['join()']['works inside comments'] = function()
  -- After 'commentstring'
  child.bo.commentstring = '# %s'
  validate_edit({ '# (', '# \taaa', '# )' }, { 1, 2 }, join, { '# (aaa)' }, { 1, 2 })

  -- After any entry in 'comments'
  child.bo.comments = ':---,:--'
  validate_edit({ '-- (', '-- \taaa', '-- )' }, { 1, 3 }, join, { '-- (aaa)' }, { 1, 3 })
  validate_edit({ '--- (', '--- \taaa', '--- )' }, { 1, 4 }, join, { '--- (aaa)' }, { 1, 4 })

  -- Respects `b` flag
  child.bo.comments = 'b:*'
  validate_edit({ '*(', '\t*aaa', '*)' }, { 1, 1 }, join, { '*(*aaa*)' }, { 1, 1 })
  validate_edit({ '* (', '\t* aaa', '* )' }, { 1, 2 }, join, { '* (aaa)' }, { 1, 2 })
  validate_edit({ '*\t(', '\t*\taaa', '*\t)' }, { 1, 2 }, join, { '*\t(aaa)' }, { 1, 2 })

  -- Respects `f` flag (ignores as comment leader)
  child.bo.comments = 'f:-'
  validate_edit({ '(', '-aaa', ')' }, { 1, 0 }, join, { '(-aaa)' }, { 1, 0 })
  validate_edit({ '(', '- aaa', ')' }, { 1, 0 }, join, { '(- aaa)' }, { 1, 0 })
  validate_edit({ '(', '-\taaa', ')' }, { 1, 0 }, join, { '(-\taaa)' }, { 1, 0 })
  validate_edit({ '- (', '- aaa', '- )' }, { 1, 2 }, join, { '- (- aaa- )' }, { 1, 2 })
end

T['join()']['works in empty brackets'] = function() validate_edit({ '()' }, { 1, 0 }, join, { '()' }, { 1, 0 }) end

T['join()']['joins nested multiline argument into single line'] = function()
  validate_edit(
    { '(', '\ta,', '\t(', '\t\tb,', '\t\tc', '\t),', '\td', ')' },
    { 1, 0 },
    join,
    -- To not have padded brackets in nested arguments, join them separately
    { '(a, ( b, c ), d)' },
    { 1, 0 }
  )
end

T['join()']['returns `nil` if no positions are found'] = function()
  -- Not found during initial step
  set_lines({ 'aaa' })
  eq(join(), vim.NIL)
  eq(get_lines(), { 'aaa' })

  -- Not found after splitting
  set_lines({ '(', 'aa', 'bb', ')' })
  local out = child.lua_get('MiniSplitjoin.join({ join = { hooks_pre = { function() return {} end } } })')
  eq(out, vim.NIL)
  eq(get_lines(), { '(', 'aa', 'bb', ')' })
end

T['join()']['respects `opts.position`'] = function()
  local f = function() join({ position = { line = 1, col = 2 } }) end
  validate_edit({ ' (', ' \taaa', ' )' }, { 1, 0 }, f, { ' (aaa)' }, { 1, 0 })
  f = function() join({ position = { line = 1, col = 1 } }) end
  validate_edit({ ' (aaa)' }, { 1, 1 }, f, { ' (aaa)' }, { 1, 1 })
end

T['join()']['respects `opts.region`'] = function()
  local lines = { '(', '\ta,', '\t")",', '\tb', ')' }
  local region = { from = { line = 1, col = 1 }, to = { line = 5, col = 0 } }
  local f = function() join({ region = region }) end
  validate_edit(lines, { 1, 0 }, f, { '(a, ")", b)' }, { 1, 0 })
end

T['join()']['respects `opts.detect.brackets`'] = function()
  -- Global
  child.lua("MiniSplitjoin.config.detect.brackets = { '%b{}' }")
  validate_edit({ '[aaa]' }, { 1, 0 }, join, { '[aaa]' }, { 1, 0 })
  validate_edit({ '{', '\taaa', '}' }, { 1, 0 }, join, { '{aaa}' }, { 1, 0 })

  -- Local
  local f = function() join({ detect = { brackets = {} } }) end
  validate_edit({ '(aaa)' }, { 1, 0 }, f, { '(aaa)' }, { 1, 0 })
  f = function() join({ detect = { brackets = { '%b[]' } } }) end
  validate_edit({ '(aaa)' }, { 1, 0 }, f, { '(aaa)' }, { 1, 0 })
end

T['join()']['respects `opts.detect.separator`'] = function()
  -- Global
  child.lua("MiniSplitjoin.config.detect.separator = '|'")
  validate_edit({ '(', '\ta|', '\tb', ')' }, { 1, 0 }, join, { '(a| b)' }, { 1, 0 })

  -- Local
  local f = function() join({ detect = { separator = '[,;]' } }) end
  validate_edit({ '(', '\ta,', '\tb;', '\tc', ')' }, { 1, 0 }, f, { '(a, b; c)' }, { 1, 0 })

  -- Empty separator should mean no internal separator
  f = function() join({ detect = { separator = '' } }) end
  validate_edit({ '(', '\ta, b; c', ')' }, { 1, 0 }, f, { '(a, b; c)' }, { 1, 0 })
end

T['join()']['respects `opts.detect.exclude_regions`'] = function()
  -- Global
  child.lua("MiniSplitjoin.config.detect.exclude_regions = { '%b[]' }")
  validate_edit({ '(', '\ta,', '\t(b,', '\tc),', '\t[d, e]', ')' }, { 1, 0 }, join, { '(a, (b, c), [d, e])' }, { 1, 0 })

  -- Local
  local f = function() join({ detect = { exclude_regions = { '%b()' } } }) end
  validate_edit({ '(', '\ta,', '\t(b, c),', '\t[d,', '\te]', ')' }, { 1, 0 }, f, { '(a, (b, c), [d, e])' }, { 1, 0 })
end

T['join()']['respects `opts.join.hooks_pre`'] = function()
  child.lua('_G.hook_pre_1 = function(...) _G.hook_pre_1_args = { ... }; return ... end')
  child.lua([[_G.hook_pre_2 = function(positions)
    _G.hook_pre_2_positions = positions
    return { positions[1] } end
  ]])

  local positions_ref = { { line = 1, col = 1 }, { line = 2, col = 3 } }

  -- Global
  child.lua('MiniSplitjoin.config.join.hooks_pre = { _G.hook_pre_2 }')
  set_lines({ '(', 'aaa', ')' })
  join()
  eq(get_lines(), { '(aaa', ')' })
  eq(child.lua_get('_G.hook_pre_1_args'), vim.NIL)
  eq(child.lua_get('_G.hook_pre_2_positions'), positions_ref)

  -- Local
  set_lines({ '(', 'aaa', ')' })
  child.lua('MiniSplitjoin.join({ join = { hooks_pre = { _G.hook_pre_1, _G.hook_pre_2 } } })')
  eq(get_lines(), { '(aaa', ')' })
  eq(child.lua_get('_G.hook_pre_1_args'), { positions_ref })
  eq(child.lua_get('_G.hook_pre_2_positions'), positions_ref)
end

T['join()']['respects `opts.join.hooks_post`'] = function()
  child.lua('_G.hook_post_1 = function(...) _G.hook_post_1_args = { ... }; return ... end')
  child.lua([[_G.hook_post_2 = function(positions)
    _G.hook_post_2_positions = positions
    return { positions[1] } end
  ]])

  local positions_ref = { { line = 1, col = 1 }, { line = 1, col = 4 }, { line = 1, col = 5 } }

  -- Global
  child.lua('MiniSplitjoin.config.join.hooks_post = { _G.hook_post_2 }')
  set_lines({ '(', 'aaa', ')' })
  local out = join()
  eq(out, { { line = 1, col = 1 } })

  eq(get_lines(), { '(aaa)' })
  eq(child.lua_get('_G.hook_post_1_args'), vim.NIL)
  eq(child.lua_get('_G.hook_post_2_positions'), positions_ref)

  -- Local
  set_lines({ '(', 'aaa', ')' })
  out = child.lua_get('MiniSplitjoin.join({ join = { hooks_post = { _G.hook_post_1, _G.hook_post_2 } } })')
  eq(out, { { line = 1, col = 1 } })

  eq(get_lines(), { '(aaa)' })
  eq(child.lua_get('_G.hook_post_1_args'), { positions_ref })
  eq(child.lua_get('_G.hook_post_2_positions'), positions_ref)
end

T['join()']['respects `vim.{g,b}.minisplitjoin_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minisplitjoin_disable = true
    validate_edit({ '(', 'aaa', ')' }, { 1, 0 }, join, { '(', 'aaa', ')' }, { 1, 0 })
  end,
})

T['join()']['respects `vim.b.minisplitjoin_config`'] = function()
  child.lua([[vim.b.minisplitjoin_config = { detect = { brackets = { '%b[]' } } }]])
  validate_edit({ '(', 'aaa', ')' }, { 1, 0 }, join, { '(', 'aaa', ')' }, { 1, 0 })
end

T['gen_hook'] = new_set()

T['gen_hook']['pad_brackets()'] = new_set()

T['gen_hook']['pad_brackets()']['works'] = function()
  child.lua('MiniSplitjoin.config.join.hooks_post = { MiniSplitjoin.gen_hook.pad_brackets() }')
  validate_edit({ '(', '\taaa,', '\tbb,', '\tc', ')' }, { 1, 0 }, join, { '( aaa, bb, c )' }, { 1, 0 })
  validate_edit({ '[', '\taaa,', '\tbb,', '\tc', ']' }, { 1, 0 }, join, { '[ aaa, bb, c ]' }, { 1, 0 })
  validate_edit({ '{', '\taaa,', '\tbb,', '\tc', '}' }, { 1, 0 }, join, { '{ aaa, bb, c }' }, { 1, 0 })

  -- Should return correctly updated input
  set_lines({ '(', 'a,', 'b', ')' })
  local out = join()
  eq(get_lines(), { '( a, b )' })
  eq(out, { { line = 1, col = 1 }, { line = 1, col = 4 }, { line = 1, col = 6 }, { line = 1, col = 8 } })
end

T['gen_hook']['pad_brackets()']['does not act in case of no arguments'] = function()
  child.lua('MiniSplitjoin.config.join.hooks_post = { MiniSplitjoin.gen_hook.pad_brackets() }')
  validate_edit({ '(', ')' }, { 1, 0 }, join, { '()' }, { 1, 0 })
end

T['gen_hook']['pad_brackets()']['respects `opts.pad`'] = function()
  child.lua("MiniSplitjoin.config.join.hooks_post = { MiniSplitjoin.gen_hook.pad_brackets({ pad = '  ' }) }")
  validate_edit({ '(', 'aa,', 'b', ')' }, { 1, 0 }, join, { '(  aa, b  )' }, { 1, 0 })
end

T['gen_hook']['pad_brackets()']['respects `opts.brackets`'] = function()
  child.lua([[MiniSplitjoin.config.join.hooks_post = {
    MiniSplitjoin.gen_hook.pad_brackets({ brackets = { '%b{}' } }),
  }]])
  validate_edit({ '(', 'aa,', 'b', ')' }, { 1, 0 }, join, { '(aa, b)' }, { 1, 0 })
  validate_edit({ '[', 'aa,', 'b', ']' }, { 1, 0 }, join, { '[aa, b]' }, { 1, 0 })
  validate_edit({ '{', 'aa,', 'b', '}' }, { 1, 0 }, join, { '{ aa, b }' }, { 1, 0 })
end

T['gen_hook']['add_trailing_separator()'] = new_set()

T['gen_hook']['add_trailing_separator()']['works'] = function()
  child.lua('MiniSplitjoin.config.split.hooks_post = { MiniSplitjoin.gen_hook.add_trailing_separator() }')
  validate_edit({ '(aa)' }, { 1, 0 }, split, { '(', '\taa,', ')' }, { 1, 0 })
  validate_edit({ '[aa]' }, { 1, 0 }, split, { '[', '\taa,', ']' }, { 1, 0 })
  validate_edit({ '{aa}' }, { 1, 0 }, split, { '{', '\taa,', '}' }, { 1, 0 })

  validate_edit({ '(aa, b)' }, { 1, 0 }, split, { '(', '\taa,', '\tb,', ')' }, { 1, 0 })

  -- Should return correctly updated input
  set_lines({ '(aa)' })
  local out = split()
  eq(get_lines(), { '(', '\taa,', ')' })
  eq(out, { { line = 1, col = 1 }, { line = 2, col = 3 }, { line = 3, col = 1 } })
end

T['gen_hook']['add_trailing_separator()']['does nothing if there is already trailing separator'] = function()
  child.lua('MiniSplitjoin.config.split.hooks_post = { MiniSplitjoin.gen_hook.add_trailing_separator() }')
  validate_edit({ '(aa,)' }, { 1, 0 }, split, { '(', '\taa,', ')' }, { 1, 0 })
  validate_edit({ '(aa, b,)' }, { 1, 0 }, split, { '(', '\taa,', '\tb,', ')' }, { 1, 0 })
end

T['gen_hook']['add_trailing_separator()']['does not act in case of no arguments'] = function()
  child.lua('MiniSplitjoin.config.split.hooks_post = { MiniSplitjoin.gen_hook.add_trailing_separator() }')
  validate_edit({ '()' }, { 1, 0 }, split, { '(', ')' }, { 1, 0 })
end

T['gen_hook']['add_trailing_separator()']['respects `opts.sep`'] = function()
  child.lua([[MiniSplitjoin.config.split.hooks_post = {
    MiniSplitjoin.gen_hook.add_trailing_separator({ sep = '!'}),
  }]])
  validate_edit({ '(aa)' }, { 1, 0 }, split, { '(', '\taa!', ')' }, { 1, 0 })
end

T['gen_hook']['add_trailing_separator()']['respects `opts.brackets`'] = function()
  child.lua([[MiniSplitjoin.config.split.hooks_post = {
    MiniSplitjoin.gen_hook.add_trailing_separator({ brackets = { '%b{}' }}),
  }]])
  validate_edit({ '(aa)' }, { 1, 0 }, split, { '(', '\taa', ')' }, { 1, 0 })
  validate_edit({ '[aa]' }, { 1, 0 }, split, { '[', '\taa', ']' }, { 1, 0 })
  validate_edit({ '{aa}' }, { 1, 0 }, split, { '{', '\taa,', '}' }, { 1, 0 })
end

T['gen_hook']['del_trailing_separator()'] = new_set()

T['gen_hook']['del_trailing_separator()']['works'] = function()
  child.lua('MiniSplitjoin.config.join.hooks_post = { MiniSplitjoin.gen_hook.del_trailing_separator() }')
  validate_edit({ '(', '\taa,', ')' }, { 1, 0 }, join, { '(aa)' }, { 1, 0 })
  validate_edit({ '[', '\taa,', ']' }, { 1, 0 }, join, { '[aa]' }, { 1, 0 })
  validate_edit({ '{', '\taa,', '}' }, { 1, 0 }, join, { '{aa}' }, { 1, 0 })

  validate_edit({ '(', '\taa,', '\tb,', ')' }, { 1, 0 }, join, { '(aa, b)' }, { 1, 0 })

  -- Should return correctly updated input
  set_lines({ '(', '\taa,', ')' })
  local out = join()
  eq(get_lines(), { '(aa)' })
  eq(out, { { line = 1, col = 1 }, { line = 1, col = 4 }, { line = 1, col = 4 } })
end

T['gen_hook']['del_trailing_separator()']['does nothing if there is already no trailing separator'] = function()
  child.lua('MiniSplitjoin.config.join.hooks_post = { MiniSplitjoin.gen_hook.del_trailing_separator() }')
  validate_edit({ '(', '\taa', ')' }, { 1, 0 }, join, { '(aa)' }, { 1, 0 })
  validate_edit({ '(', '\taa,', '\tb', ')' }, { 1, 0 }, join, { '(aa, b)' }, { 1, 0 })
end

T['gen_hook']['del_trailing_separator()']['respects `opts.sep`'] = function()
  child.lua([[MiniSplitjoin.config.join.hooks_post = {
    MiniSplitjoin.gen_hook.del_trailing_separator({ sep = '!'}),
  }]])
  validate_edit({ '(', '\taa!', ')' }, { 1, 0 }, join, { '(aa)' }, { 1, 0 })
end

T['gen_hook']['del_trailing_separator()']['respects `opts.brackets`'] = function()
  child.lua([[MiniSplitjoin.config.join.hooks_post = {
    MiniSplitjoin.gen_hook.del_trailing_separator({ brackets = { '%b{}' }}),
  }]])
  validate_edit({ '(', '\taa,', ')' }, { 1, 0 }, join, { '(aa,)' }, { 1, 0 })
  validate_edit({ '[', '\taa,', ']' }, { 1, 0 }, join, { '[aa,]' }, { 1, 0 })
  validate_edit({ '{', '\taa,', '}' }, { 1, 0 }, join, { '{aa}' }, { 1, 0 })
end

T['split_at()'] = new_set()

local split_at = function(positions)
  return child.lua_get('MiniSplitjoin.split_at(...)', { vim.tbl_map(simplepos_to_pos, positions) })
end

T['split_at()']['works'] = function()
  local f = function() split_at({ { 1, 1 }, { 1, 4 } }) end
  validate_edit({ '(aaa)' }, { 1, 2 }, f, { '(', '\taaa', ')' }, { 2, 2 })

  f = function() split_at({ { 1, 1 }, { 1, 1 } }) end
  validate_edit({ '()' }, { 1, 1 }, f, { '(', '', ')' }, { 3, 0 })

  f = function() split_at({ { 1, 1 }, { 1, 5 }, { 1, 9 }, { 1, 11 } }) end
  validate_edit({ '(aaa, bb, c)' }, { 1, 7 }, f, { '(', '\taaa,', '\tbb,', '\tc', ')' }, { 3, 2 })

  f = function() split_at({}) end
  validate_edit({ '(aaa)' }, { 1, 2 }, f, { '(aaa)' }, { 1, 2 })
end

T['split_at()']['works not on single line'] = function()
  local f = function() split_at({ { 1, 2 }, { 2, 2 } }) end
  validate_edit({ 'aabb', 'ccdd' }, { 1, 3 }, f, { 'aa', '\tbb', '\tcc', 'dd' }, { 2, 2 })
end

T['split_at()']['properly tracks cursor'] = function()
  local f = function() split_at({ { 1, 1 } }) end
  validate_edit({ '()' }, { 1, 0 }, f, { '(', ')' }, { 1, 0 })
  validate_edit({ '()' }, { 1, 1 }, f, { '(', ')' }, { 2, 0 })

  local cursors = {
    { before = { 1, 0 }, after = { 1, 0 } },
    { before = { 1, 1 }, after = { 1, 1 } },
    { before = { 1, 2 }, after = { 2, 1 } },
    { before = { 1, 3 }, after = { 2, 1 } },
    { before = { 1, 4 }, after = { 2, 2 } },
    { before = { 1, 5 }, after = { 2, 3 } },
    { before = { 1, 6 }, after = { 2, 3 } },
    { before = { 1, 7 }, after = { 3, 0 } },
    { before = { 1, 8 }, after = { 3, 1 } },
  }
  f = function() split_at({ { 1, 2 }, { 1, 7 } }) end
  for _, cursor in ipairs(cursors) do
    validate_edit({ 'b( aaa )b' }, cursor.before, f, { 'b(', '\taaa', ')b' }, cursor.after)
  end
end

T['split_at()']['copies indent of current line'] = function()
  local f = function() split_at({ { 1, 4 }, { 1, 7 } }) end
  validate_edit({ ' \t (aaa)' }, { 1, 5 }, f, { ' \t (', ' \t \taaa', ' \t )' }, { 2, 5 })
end

T['split_at()']['does not increase indent of blank lines'] = function()
  local f = function() split_at({ { 1, 1 }, { 2, 2 }, { 2, 3 } }) end
  validate_edit({ '(', 'a,b)' }, { 2, 3 }, f, { '(', '', '\ta,', '\tb', ')' }, { 5, 0 })

  f = function() split_at({ { 1, 3 } }) end
  validate_edit({ '  (', ')' }, { 2, 0 }, f, { '  (', '  ', ')' }, { 3, 0 })
end

T['split_at()']['handles extra whitespace'] = function()
  local f = function() split_at({ { 1, 1 }, { 1, 7 } }) end
  validate_edit({ '(   aaa   )' }, { 1, 5 }, f, { '(', '\taaa', ')' }, { 2, 2 })
  f = function() split_at({ { 1, 3 }, { 1, 9 } }) end
  validate_edit({ '(   aaa   )' }, { 1, 5 }, f, { '(', '\taaa', ')' }, { 2, 2 })
end

T['split_at()']['correctly tracks input positions'] = function()
  set_lines({ '(aaa, bb, c)' })
  local out = split_at({ { 1, 1 }, { 1, 5 }, { 1, 9 }, { 1, 11 } })
  validate_positions(out, { { 1, 1 }, { 2, 5 }, { 3, 4 }, { 4, 2 } })
  eq(get_lines(), { '(', '\taaa,', '\tbb,', '\tc', ')' })
end

--stylua: ignore
T['split_at()']['works inside comments'] = function()
  local validate = function(lines_before, cursor_before, split_at_opts, lines_after, cursor_after)
    local f = function() split_at(split_at_opts) end
    validate_edit(lines_before, cursor_before, f, lines_after, cursor_after)
  end

  -- After 'commentstring'
  child.bo.commentstring = '# %s'
  validate({ '# (aaa)' }, { 1, 2 }, { { 1, 3 }, { 1, 6 } }, { '# (', '# \taaa', '# )' }, { 1, 2 })

  -- After any entry in 'comments'
  child.bo.comments = ':---,:--'
  validate({ '-- (aaa)' },  { 1, 3 }, { { 1, 4 }, { 1, 7 } }, { '-- (',  '-- \taaa',  '-- )' },  { 1, 3 })
  validate({ '--- (aaa)' }, { 1, 4 }, { { 1, 5 }, { 1, 8 } }, { '--- (', '--- \taaa', '--- )' }, { 1, 4 })

  -- Respects `b` flag
  child.bo.comments = 'b:*'
  validate({ '*(aaa)' }, { 1, 1 }, { { 1, 2 }, { 1, 5 } }, { '*(', '\taaa', ')' }, { 1, 1 })
  validate({ '* (aaa)' }, { 1, 2 }, { { 1, 3 }, { 1, 6 } }, { '* (', '* \taaa', '* )' }, { 1, 2 })
  validate({ '*\t(aaa)' }, { 1, 2 }, { { 1, 3 }, { 1, 6 } }, { '*\t(', '*\t\taaa', '*\t)' }, { 1, 2 })

  -- Respects `f` flag (ignores as comment leader)
  child.bo.comments = 'f:-'
  validate({ '-(aaa)' }, { 1, 1 }, { { 1, 2 }, { 1, 5 } }, { '-(', '\taaa', ')' }, { 1, 1 })
  validate({ '- (aaa)' }, { 1, 2 }, { { 1, 3 }, { 1, 6 } }, { '- (', '\taaa', ')' }, { 1, 2 })
  validate({ '-\t(aaa)' }, { 1, 2 }, { { 1, 3 }, { 1, 6 } }, { '-\t(', '\taaa', ')' }, { 1, 2 })
end

T['split_at()']['correctly increases indent of commented line in non-commented block'] = function()
  child.bo.commentstring = '# %s'

  local f = function() split_at({ { 1, 1 }, { 3, 1 } }) end
  validate_edit({ '(aa', '# b', 'c)' }, { 1, 0 }, f, { '(', '\taa', '\t# b', '\tc', ')' }, { 1, 0 })
end

T['split_at()']['uses first and last positions to determine indent range'] = function()
  local f = function() split_at({ { 1, 6 }, { 1, 3 }, { 1, 1 }, { 1, 8 } }) end
  validate_edit({ '(a, b, c)' }, { 1, 0 }, f, { '(', 'a,', 'b,', '\tc', ')' }, { 1, 0 })
end

T['split_at()']["respects 'expandtab' and 'shiftwidth' for indent increase"] = function()
  child.o.expandtab = true
  child.o.shiftwidth = 3
  local f = function() split_at({ { 1, 1 }, { 1, 4 } }) end
  validate_edit({ '(aaa)' }, { 1, 0 }, f, { '(', '   aaa', ')' }, { 1, 0 })
end

T['join_at()'] = new_set()

local join_at = function(positions)
  return child.lua_get('MiniSplitjoin.join_at(...)', { vim.tbl_map(simplepos_to_pos, positions) })
end

T['join_at()']['works'] = function()
  local f = function() join_at({ { 1, 1 }, { 2, 4 }, { 3, 3 }, { 4, 1 } }) end
  validate_edit({ '(', '\taaa,', '   bb,', 'c', ')' }, { 2, 2 }, f, { '(aaa, bb, c)' }, { 1, 2 })

  f = function() join_at({}) end
  validate_edit({ '(', 'aaa', ')' }, { 2, 2 }, f, { '(', 'aaa', ')' }, { 2, 2 })
end

T['join_at()']['works on single line'] = function()
  local f = function() join_at({ { 1, 1 }, { 1, 1 }, { 1, 1 } }) end
  validate_edit({ '(', '\ta', '\tb', ')' }, { 1, 0 }, f, { '(a b)' }, { 1, 0 })
end

T['join_at()']['joins line at any its column'] = function()
  for i = 1, 4 do
    local f = function() join_at({ { 1, i }, { 2, i } }) end
    validate_edit({ '   (', '\taaa', ')' }, { 2, 2 }, f, { '   (aaa)' }, { 1, 5 })
  end
end

T['join_at()']['properly tracks cursor'] = function()
  local f = function() join_at({ { 1, 1 } }) end
  validate_edit({ '(', ')' }, { 1, 0 }, f, { '()' }, { 1, 0 })
  validate_edit({ '(', ')' }, { 2, 0 }, f, { '()' }, { 1, 1 })

  local cursors = {
    { before = { 1, 0 }, after = { 1, 0 } },
    { before = { 1, 1 }, after = { 1, 1 } },
    { before = { 2, 0 }, after = { 1, 2 } },
    { before = { 2, 1 }, after = { 1, 2 } },
    { before = { 2, 2 }, after = { 1, 3 } },
    { before = { 2, 3 }, after = { 1, 4 } },
    { before = { 2, 4 }, after = { 1, 5 } },
    { before = { 3, 0 }, after = { 1, 5 } },
    { before = { 3, 1 }, after = { 1, 6 } },
  }
  f = function() join_at({ { 1, 2 }, { 2, 4 } }) end
  for _, cursor in ipairs(cursors) do
    validate_edit({ 'b(', '\taaa ', ')b' }, cursor.before, f, { 'b(aaa)b' }, cursor.after)
  end
end

T['join_at()']['handles extra whitespace'] = function()
  local f = function() join_at({ { 1, 1 }, { 2, 1 }, { 3, 1 } }) end
  validate_edit({ '( \t', '\t\ta  ', '  b\t\t', ' \t  )' }, { 1, 0 }, f, { '(a b)' }, { 1, 0 })
end

T['join_at()']['correctly works with positions on last line'] = function()
  local f = function() join_at({ { 1, 1 }, { 2, 1 }, { 3, 1 }, { 3, 2 } }) end
  validate_edit({ '(', 'a', ')b' }, { 1, 0 }, f, { '(a )b' }, { 1, 0 })
end

T['join_at()']['correctly tracks input positions'] = function()
  set_lines({ '(', '\taaa,', '\tbb,', '\tc', ')' })
  local out = join_at({ { 1, 1 }, { 2, 5 }, { 3, 4 }, { 4, 2 } })
  validate_positions(out, { { 1, 1 }, { 1, 5 }, { 1, 9 }, { 1, 11 } })
  eq(get_lines(), { '(aaa, bb, c)' })
end

--stylua: ignore
T['join_at()']['works inside comments'] = function()
  local f = function() join_at({ { 1, 1 }, { 2, 1 } }) end

  -- After 'commentstring'
  child.bo.commentstring = '# %s'
  validate_edit({ '# (', '# \taaa', '# )' }, { 1, 2 }, f, { '# (aaa)' }, { 1, 2 })
  validate_edit({ '# (', 'aaa',     '# )' }, { 1, 2 }, f, { '# (aaa)' }, { 1, 2 })

  -- After any entry in 'comments'
  child.bo.comments = ':---,:--'
  validate_edit({ '-- (',  '-- \taaa',  '-- )' },  { 1, 3 }, f, { '-- (aaa)' },  { 1, 3 })
  validate_edit({ '--- (', '--- \taaa', '--- )' }, { 1, 4 }, f, { '--- (aaa)' }, { 1, 4 })

  -- Respects `b` flag
  child.bo.comments = 'b:*'
  validate_edit({ '*(', '\t*aaa', '*)' }, { 1, 1 }, f, { '*(*aaa*)' }, { 1, 1 })
  validate_edit({ '* (', '\t* aaa', '* )' }, { 1, 2 }, f, { '* (aaa)' }, { 1, 2 })
  validate_edit({ '*\t(', '\t*\taaa', '*\t)' }, { 1, 2 }, f, { '*\t(aaa)' }, { 1, 2 })

  -- Respects `f` flag (ignores as comment leader)
  child.bo.comments = 'f:-'
  validate_edit({ '(', '-aaa', ')' }, { 1, 0 }, f, { '(-aaa)' }, { 1, 0 })
  validate_edit({ '(', '- aaa', ')' }, { 1, 0 }, f, { '(- aaa)' }, { 1, 0 })
  validate_edit({ '(', '-\taaa', ')' }, { 1, 0 }, f, { '(-\taaa)' }, { 1, 0 })
  validate_edit({ '- (', '- aaa', '- )' }, { 1, 2 }, f, { '- (- aaa- )' }, { 1, 2 })
end

T['get_visual_region()'] = new_set()

T['get_visual_region()']['works for charwise selection'] = function()
  set_lines({ 'aaa', 'bbb' })
  set_cursor(1, 1)
  type_keys('v')
  set_cursor(2, 1)
  type_keys('<Esc>')

  eq(child.lua_get('MiniSplitjoin.get_visual_region()'), { from = { line = 1, col = 2 }, to = { line = 2, col = 2 } })
end

T['get_visual_region()']['works for linewise selection'] = function()
  set_lines({ 'aaa', 'bbb' })
  set_cursor(1, 1)
  type_keys('V')
  set_cursor(2, 1)
  type_keys('<Esc>')

  -- It should tweak marks to be start/end of lines
  eq(child.lua_get('MiniSplitjoin.get_visual_region()'), { from = { line = 1, col = 1 }, to = { line = 2, col = 3 } })
end

T['get_visual_region()']['works for blockwise selection'] = function()
  set_lines({ 'aaa', 'bbb' })
  set_cursor(1, 1)
  type_keys('<C-v>')
  set_cursor(2, 2)
  type_keys('<Esc>')

  eq(child.lua_get('MiniSplitjoin.get_visual_region()'), { from = { line = 1, col = 2 }, to = { line = 2, col = 3 } })
end

T['get_indent_part()'] = new_set()

local get_indent_part = function(...) return child.lua_get('MiniSplitjoin.get_indent_part(...)', { ... }) end

T['get_indent_part()']['works'] = function()
  local validate = function(input, out_ref) eq(get_indent_part(input), out_ref) end

  -- No indent
  validate('aa', '')

  -- Whitespace indent
  validate(' aa', ' ')
  validate('\taa', '\t')
  validate('\t \taa', '\t \t')

  -- Indent with comment under 'commentstring'
  child.o.commentstring = '# %s'

  validate('#aa', '#')
  validate('# aa', '# ')
  validate(' # aa', ' # ')
  validate('\t# aa', '\t# ')
  validate('\t \t# aa', '\t \t# ')
  validate('#\taa', '#\t')

  -- Indent with comment under 'comments' parts
  child.bo.comments = ':---,:--'

  validate('--aa', '--')
  validate('-- aa', '-- ')
  validate(' -- aa', ' -- ')
  validate('\t-- aa', '\t-- ')
  validate('\t \t-- aa', '\t \t-- ')
  validate('--\taa', '--\t')

  validate('---aa', '---')
  validate('--- aa', '--- ')
  validate(' --- aa', ' --- ')
  validate('\t--- aa', '\t--- ')
  validate('\t \t--- aa', '\t \t--- ')
  validate('---\taa', '---\t')

  -- Should respect `b` flag
  child.bo.comments = 'b:*'
  validate('*aa', '')
  validate(' *aa', ' ')
  validate('\t*aa', '\t')

  validate(' * aa', ' * ')
  validate(' *\taa', ' *\t')
  validate('\t* aa', '\t* ')
  validate('\t*\taa', '\t*\t')

  -- Should respect `f` flag (ignore comment leader)
  child.bo.comments = 'f:-'
  validate('-aa', '')
  validate(' -aa', ' ')
  validate(' - aa', ' ')
  validate('\t-aa', '\t')
  validate('\t-\taa', '\t')
end

T['get_indent_part()']['respects `respect_comments` argument'] = function()
  local validate = function(input, out_ref) eq(get_indent_part(input, false), out_ref) end

  validate('aa', '')

  validate(' aa', ' ')
  validate('\taa', '\t')
  validate('\t \taa', '\t \t')

  child.o.commentstring = '# %s'
  validate('# aa', '')
  validate(' # aa', ' ')
  validate('\t# aa', '\t')
  validate('\t \t# aa', '\t \t')

  child.o.comments = ':---,:--'
  validate('-- aa', '')
  validate(' -- aa', ' ')
  validate('\t-- aa', '\t')
  validate('\t \t-- aa', '\t \t')

  validate('--- aa', '')
  validate(' --- aa', ' ')
  validate('\t--- aa', '\t')
  validate('\t \t--- aa', '\t \t')
end

-- Integration tests ==========================================================
T['Mappings'] = new_set()

T['Mappings']['Toggle'] = new_set()

T['Mappings']['Toggle']['works in Normal mode'] = function()
  validate_edit({ '(aa, b)' }, { 1, 0 }, 'gS', { '(', '\taa,', '\tb', ')' }, { 1, 0 })
  validate_edit({ '(', '\taa,', '\tb', ')' }, { 1, 0 }, 'gS', { '(aa, b)' }, { 1, 0 })

  -- Should also work with dot-repeat
  set_lines({ '(', '(', 'a', ')', ')' })
  set_cursor(3, 0)
  type_keys('gS')
  eq(get_lines(), { '(', '(a)', ')' })

  set_cursor(1, 0)
  type_keys('.')
  eq(get_lines(), { '((a))' })
end

T['Mappings']['Toggle']['works in Visual mode'] = function()
  validate_edit({ '(aa, ")", b)' }, { 1, 0 }, 'VgS', { '(', '\taa,', '\t")",', '\tb', ')' }, { 1, 0 })
  validate_edit({ '(aa)', 'bb' }, { 1, 0 }, 'VjgS', { '(aa)bb' }, { 1, 0 })
end

T['Mappings']['Toggle']['works with different mapping'] = function()
  child.api.nvim_del_keymap('n', 'gS')
  child.api.nvim_del_keymap('x', 'gS')

  reload_module({ mappings = { toggle = 'gs' } })
  validate_edit({ '(aa, b)' }, { 1, 0 }, 'gs', { '(', '\taa,', '\tb', ')' }, { 1, 0 })
  validate_edit({ '(aa, ")", b)' }, { 1, 0 }, 'Vgs', { '(', '\taa,', '\t")",', '\tb', ')' }, { 1, 0 })
end

T['Mappings']['Toggle']['respects `vim.{g,b}.minisplitjoin_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minisplitjoin_disable = true
    validate_edit({ '(aaa)' }, { 1, 0 }, 'gS', { '(aaa)' }, { 1, 0 })
  end,
})

T['Mappings']['Split'] = new_set()

T['Mappings']['Split']['works in Normal mode'] = function()
  reload_module({ mappings = { split = 'S' } })

  validate_edit({ '(aa, b)' }, { 1, 0 }, 'S', { '(', '\taa,', '\tb', ')' }, { 1, 0 })

  -- Should also work with dot-repeat
  set_lines({ '((a))' })
  set_cursor(1, 0)
  type_keys('S')
  eq(get_lines(), { '(', '\t(a)', ')' })

  set_cursor(2, 1)
  type_keys('.')
  eq(get_lines(), { '(', '\t(', '\t\ta', '\t)', ')' })
end

T['Mappings']['Split']['works in Visual mode'] = function()
  reload_module({ mappings = { split = 'S' } })
  validate_edit({ '(aa, ")", b)' }, { 1, 0 }, 'VS', { '(', '\taa,', '\t")",', '\tb', ')' }, { 1, 0 })
end

T['Mappings']['Split']['respects `vim.{g,b}.minisplitjoin_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    reload_module({ mappings = { split = 'S' } })
    child[var_type].minisplitjoin_disable = true
    validate_edit({ '(aaa)' }, { 1, 0 }, 'S', { '(aaa)' }, { 1, 0 })
  end,
})

T['Mappings']['Join'] = new_set()

T['Mappings']['Join']['works in Normal mode'] = function()
  reload_module({ mappings = { join = 'J' } })

  validate_edit({ '(', '\taa,', '\tb', ')' }, { 1, 0 }, 'J', { '(aa, b)' }, { 1, 0 })

  -- Should also work with dot-repeat
  set_lines({ '(', '(', 'a', ')', ')' })
  set_cursor(3, 0)
  type_keys('J')
  eq(get_lines(), { '(', '(a)', ')' })

  set_cursor(1, 0)
  type_keys('.')
  eq(get_lines(), { '((a))' })
end

T['Mappings']['Join']['works in Visual mode'] = function()
  reload_module({ mappings = { join = 'J' } })
  validate_edit({ '(aa)', 'bb' }, { 1, 0 }, 'VjJ', { '(aa)bb' }, { 1, 0 })
end

T['Mappings']['Join']['respects `vim.{g,b}.minisplitjoin_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    reload_module({ mappings = { join = 'J' } })
    child[var_type].minisplitjoin_disable = true
    validate_edit({ '(', 'aaa', ')' }, { 1, 0 }, 'J', { '(', 'aaa', ')' }, { 1, 0 })
  end,
})

return T
