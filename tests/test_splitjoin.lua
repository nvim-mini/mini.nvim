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

-- Helper wrappers
local simplepos_to_pos = function(x) return { line = x[1], col = x[2] } end

local validate_positions = function(out, ref) eq(out, vim.tbl_map(simplepos_to_pos, ref)) end

-- More general validators
local validate_edit = function(lines_before, cursor_before, lines_after, cursor_after, fun, ...)
  child.ensure_normal_mode()
  set_lines(lines_before)
  set_cursor(cursor_before[1], cursor_before[2])

  fun(...)

  eq(get_lines(), lines_after)
  eq(get_cursor(), cursor_after)
  child.ensure_normal_mode()
end

local validate_keys = function(lines_before, cursor_before, lines_after, cursor_after, keys)
  child.ensure_normal_mode()
  set_lines(lines_before)
  set_cursor(cursor_before[1], cursor_before[2])

  type_keys(keys)

  eq(get_lines(), lines_after)
  eq(get_cursor(), cursor_after)
  child.ensure_normal_mode()
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
  validate_edit({ '(aaa, bb, c)' }, { 1, 0 }, { '(', '\taaa,', '\tbb,', '\tc', ')' }, { 1, 0 }, toggle)
  validate_edit({ '[aaa, bb, c]' }, { 1, 0 }, { '[', '\taaa,', '\tbb,', '\tc', ']' }, { 1, 0 }, toggle)
  validate_edit({ '{aaa, bb, c}' }, { 1, 0 }, { '{', '\taaa,', '\tbb,', '\tc', '}' }, { 1, 0 }, toggle)

  validate_edit({ '(', '\taaa,', '\tbb,', '\tc', ')' }, { 1, 0 }, { '(aaa, bb, c)' }, { 1, 0 }, toggle)
  validate_edit({ '[', '\taaa,', '\tbb,', '\tc', ']' }, { 1, 0 }, { '[aaa, bb, c]' }, { 1, 0 }, toggle)
  validate_edit({ '{', '\taaa,', '\tbb,', '\tc', '}' }, { 1, 0 }, { '{aaa, bb, c}' }, { 1, 0 }, toggle)
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
  validate_edit({ ' (aa)' }, { 1, 0 }, { ' (', ' \taa', ' )' }, { 1, 0 }, toggle, { position = { line = 1, col = 2 } })
  validate_edit({ ' (aa)' }, { 1, 1 }, { ' (aa)' }, { 1, 1 }, toggle, { position = { line = 1, col = 1 } })
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
  validate_edit({ '[aaa]' }, { 1, 0 }, { '[aaa]' }, { 1, 0 }, toggle)
  validate_edit({ '{aaa}' }, { 1, 0 }, { '{', '\taaa', '}' }, { 1, 0 }, toggle)

  -- Local
  validate_edit({ '(aaa)' }, { 1, 0 }, { '(aaa)' }, { 1, 0 }, toggle, { detect = { brackets = {} } })
  validate_edit({ '(aaa)' }, { 1, 0 }, { '(aaa)' }, { 1, 0 }, toggle, { detect = { brackets = { '%b[]' } } })
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
    validate_edit({ '(aaa)' }, { 1, 0 }, { '(aaa)' }, { 1, 0 }, toggle)
  end,
})

T['toggle()']['respects `vim.b.minisplitjoin_config`'] = function()
  child.lua([[vim.b.minisplitjoin_config = { detect = { brackets = { '%b[]' } } }]])
  validate_edit({ '(aaa)' }, { 1, 0 }, { '(aaa)' }, { 1, 0 }, toggle)
end

T['split()'] = new_set()

local split = function(...) return child.lua_get('MiniSplitjoin.split(...)', { ... }) end

T['split()']['works'] = function()
  validate_edit({ '(aaa, bb, c)' }, { 1, 0 }, { '(', '\taaa,', '\tbb,', '\tc', ')' }, { 1, 0 }, split)
  validate_edit({ '[aaa, bb, c]' }, { 1, 0 }, { '[', '\taaa,', '\tbb,', '\tc', ']' }, { 1, 0 }, split)
  validate_edit({ '{aaa, bb, c}' }, { 1, 0 }, { '{', '\taaa,', '\tbb,', '\tc', '}' }, { 1, 0 }, split)
end

--stylua: ignore
T['split()']['works for arguments on multiple lines'] = function()
  validate_edit({ '(a', 'b',   'c)' },     { 1, 0 }, { '(', '\ta', '\tb', '\tc', ')' }, { 1, 0 }, split)
  validate_edit({ '(a', '\tb', '\t\tc)' }, { 1, 0 }, { '(', '\ta', '\t\tb', '\t\t\tc', '\t\t)' }, { 1, 0 }, split)

  validate_edit({ '(a', 'b, c', 'd)' }, { 1, 0 }, { '(', '\ta', '\tb,', '\tc', '\td', ')' }, { 1, 0 }, split)

  -- This can be better, but currently is outside of cost/benefit ratio
  validate_edit({ '(', '\ta,', '\tb', ')' }, { 1, 0 }, { "(", "", "\t\ta,", "\t", "\t\tb", "\t)" }, { 1, 0 }, split)
end

T['split()']['works on any part inside or on brackets'] = function()
  validate_edit({ 'b( a )b' }, { 1, 0 }, { 'b( a )b' }, { 1, 0 }, split)
  validate_edit({ 'b( a )b' }, { 1, 1 }, { 'b(', '\ta', ')b' }, { 1, 1 }, split)
  validate_edit({ 'b( a )b' }, { 1, 2 }, { 'b(', '\ta', ')b' }, { 2, 1 }, split)
  validate_edit({ 'b( a )b' }, { 1, 3 }, { 'b(', '\ta', ')b' }, { 2, 1 }, split)
  validate_edit({ 'b( a )b' }, { 1, 4 }, { 'b(', '\ta', ')b' }, { 2, 1 }, split)
  validate_edit({ 'b( a )b' }, { 1, 5 }, { 'b(', '\ta', ')b' }, { 3, 0 }, split)
  validate_edit({ 'b( a )b' }, { 1, 6 }, { 'b( a )b' }, { 1, 6 }, split)
end

T['split()']['works on indented line'] = function()
  validate_edit({ '\t (aaa, bb, c)' }, { 1, 2 }, { '\t (', '\t \taaa,', '\t \tbb,', '\t \tc', '\t )' }, { 1, 2 }, split)
end

T['split()']['works inside comments'] = function()
  -- After 'commentstring'
  child.bo.commentstring = '# %s'
  validate_edit({ '# (aaa)' }, { 1, 2 }, { '# (', '# \taaa', '# )' }, { 1, 2 }, split)

  -- After any entry in 'comments'
  child.bo.comments = ':---,:--'
  validate_edit({ '-- (aaa)' }, { 1, 3 }, { '-- (', '-- \taaa', '-- )' }, { 1, 3 }, split)
  validate_edit({ '--- (aaa)' }, { 1, 4 }, { '--- (', '--- \taaa', '--- )' }, { 1, 4 }, split)

  -- Respects `b` flag
  child.bo.comments = 'b:*'
  validate_edit({ '*(aaa)' }, { 1, 1 }, { '*(', '\taaa', ')' }, { 1, 1 }, split)
  validate_edit({ '* (aaa)' }, { 1, 2 }, { '* (', '* \taaa', '* )' }, { 1, 2 }, split)
  validate_edit({ '*\t(aaa)' }, { 1, 2 }, { '*\t(', '*\t\taaa', '*\t)' }, { 1, 2 }, split)

  -- Respects `f` flag (ignores as comment leader)
  child.bo.comments = 'f:-'
  validate_edit({ '-(aaa)' }, { 1, 1 }, { '-(', '\taaa', ')' }, { 1, 1 }, split)
  validate_edit({ '- (aaa)' }, { 1, 2 }, { '- (', '\taaa', ')' }, { 1, 2 }, split)
  validate_edit({ '-\t(aaa)' }, { 1, 2 }, { '-\t(', '\taaa', ')' }, { 1, 2 }, split)
end

T['split()']['works with trailing separator'] = function()
  validate_edit({ '(aa, b,)' }, { 1, 0 }, { '(', '\taa,', '\tb,', ')' }, { 1, 0 }, split)
end

T['split()']['correctly increases indent of commented line in non-commented block'] = function()
  child.bo.commentstring = '# %s'
  validate_edit({ '(aa', '# b', 'c)' }, { 1, 0 }, { '(', '\taa', '\t# b', '\tc', ')' }, { 1, 0 }, split)
end

T['split()']['ignores separators inside nested arguments'] = function()
  validate_edit(
    { '(a, (b, c), [d, e], {f, e})' },
    { 1, 0 },
    { '(', '\ta,', '\t(b, c),', '\t[d, e],', '\t{f, e}', ')' },
    { 1, 0 },
    split
  )
end

T['split()']['ignores separators inside quotes'] = function()
  validate_edit({ [[(a, 'b, c', "d, e")]] }, { 1, 0 }, { '(', '\ta,', "\t'b, c',", '\t"d, e"', ')' }, { 1, 0 }, split)
end

T['split()']['works in empty brackets'] = function()
  validate_edit({ '()' }, { 1, 0 }, { '(', ')' }, { 1, 0 }, split)
  validate_edit({ '()' }, { 1, 1 }, { '(', ')' }, { 2, 0 }, split)
end

T['split()']["respects 'expandtab' and 'shiftwidth' for indenting"] = function()
  child.o.expandtab = true
  child.o.shiftwidth = 3
  validate_edit({ '(aaa)' }, { 1, 0 }, { '(', '   aaa', ')' }, { 1, 0 }, split)
end

T['split()']['returns `nil` if no positions are found'] = function()
  set_lines({ 'aaa' })
  eq(split(), vim.NIL)
  eq(get_lines(), { 'aaa' })
end

T['split()']['respects `opts.position`'] = function()
  validate_edit({ ' (aaa)' }, { 1, 0 }, { ' (', ' \taaa', ' )' }, { 1, 0 }, split, { position = { line = 1, col = 2 } })
  validate_edit({ ' (aaa)' }, { 1, 1 }, { ' (aaa)' }, { 1, 1 }, split, { position = { line = 1, col = 1 } })
end

T['split()']['respects `opts.region`'] = function()
  local lines = { '(a, ")", b)' }
  local region = { from = { line = 1, col = 1 }, to = { line = 1, col = 11 } }
  validate_edit(lines, { 1, 0 }, { '(', '\ta,', '\t")",', '\tb', ')' }, { 1, 0 }, split, { region = region })
end

T['split()']['respects `opts.detect.brackets`'] = function()
  -- Global
  child.lua("MiniSplitjoin.config.detect.brackets = { '%b{}' }")
  validate_edit({ '[aaa]' }, { 1, 0 }, { '[aaa]' }, { 1, 0 }, split)
  validate_edit({ '{aaa}' }, { 1, 0 }, { '{', '\taaa', '}' }, { 1, 0 }, split)

  -- Local
  validate_edit({ '(aaa)' }, { 1, 0 }, { '(aaa)' }, { 1, 0 }, split, { detect = { brackets = {} } })
  validate_edit({ '(aaa)' }, { 1, 0 }, { '(aaa)' }, { 1, 0 }, split, { detect = { brackets = { '%b[]' } } })
end

T['split()']['respects `opts.detect.separator`'] = function()
  -- Global
  child.lua("MiniSplitjoin.config.detect.separator = '|'")
  validate_edit({ '(a|b)' }, { 1, 0 }, { '(', '\ta|', '\tb', ')' }, { 1, 0 }, split)

  -- Local
  local opts = { detect = { separator = '[,;]' } }
  validate_edit({ '(a, b; c)' }, { 1, 0 }, { '(', '\ta,', '\tb;', '\tc', ')' }, { 1, 0 }, split, opts)

  -- Empty separator should mean no internal separator
  opts = { detect = { separator = '' } }
  validate_edit({ '(a, b; c)' }, { 1, 0 }, { '(', '\ta, b; c', ')' }, { 1, 0 }, split, opts)
end

T['split()']['respects `opts.detect.exclude_regions`'] = function()
  -- Global
  child.lua("MiniSplitjoin.config.detect.exclude_regions = { '%b[]' }")
  validate_edit(
    { '(a, (b, c), [d, e])' },
    { 1, 0 },
    { '(', '\ta,', '\t(b,', '\tc),', '\t[d, e]', ')' },
    { 1, 0 },
    split
  )

  -- Local
  local opts = { detect = { exclude_regions = { '%b()' } } }
  validate_edit(
    { '(a, (b, c), [d, e])' },
    { 1, 0 },
    { '(', '\ta,', '\t(b, c),', '\t[d,', '\te]', ')' },
    { 1, 0 },
    split,
    opts
  )
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
    validate_edit({ '(aaa)' }, { 1, 0 }, { '(aaa)' }, { 1, 0 }, split)
  end,
})

T['split()']['respects `vim.b.minisplitjoin_config`'] = function()
  child.lua([[vim.b.minisplitjoin_config = { detect = { brackets = { '%b[]' } } }]])
  validate_edit({ '(aaa)' }, { 1, 0 }, { '(aaa)' }, { 1, 0 }, split)
end

T['join()'] = new_set()

local join = function(...) return child.lua_get('MiniSplitjoin.join(...)', { ... }) end

T['join()']['works'] = function()
  validate_edit({ '(', '\taaa,', '\tbb,', '\tc', ')' }, { 1, 0 }, { '(aaa, bb, c)' }, { 1, 0 }, join)
  validate_edit({ '[', '\taaa,', '\tbb,', '\tc', ']' }, { 1, 0 }, { '[aaa, bb, c]' }, { 1, 0 }, join)
  validate_edit({ '{', '\taaa,', '\tbb,', '\tc', '}' }, { 1, 0 }, { '{aaa, bb, c}' }, { 1, 0 }, join)

  validate_edit({ '(', 'aaa)' }, { 1, 0 }, { '(aaa)' }, { 1, 0 }, join)
  validate_edit({ ' \t(', 'aaa)' }, { 1, 2 }, { ' \t(aaa)' }, { 1, 2 }, join)
end

T['join()']['does nothing if arguments are on single line'] = function()
  validate_edit({ '(aa, b)' }, { 1, 0 }, { '(aa, b)' }, { 1, 0 }, join)
end

T['join()']['works inside comments'] = function()
  -- After 'commentstring'
  child.bo.commentstring = '# %s'
  validate_edit({ '# (', '# \taaa', '# )' }, { 1, 2 }, { '# (aaa)' }, { 1, 2 }, join)

  -- After any entry in 'comments'
  child.bo.comments = ':---,:--'
  validate_edit({ '-- (', '-- \taaa', '-- )' }, { 1, 3 }, { '-- (aaa)' }, { 1, 3 }, join)
  validate_edit({ '--- (', '--- \taaa', '--- )' }, { 1, 4 }, { '--- (aaa)' }, { 1, 4 }, join)

  -- Respects `b` flag
  child.bo.comments = 'b:*'
  validate_edit({ '*(', '\t*aaa', '*)' }, { 1, 1 }, { '*(*aaa*)' }, { 1, 1 }, join)
  validate_edit({ '* (', '\t* aaa', '* )' }, { 1, 2 }, { '* (aaa)' }, { 1, 2 }, join)
  validate_edit({ '*\t(', '\t*\taaa', '*\t)' }, { 1, 2 }, { '*\t(aaa)' }, { 1, 2 }, join)

  -- Respects `f` flag (ignores as comment leader)
  child.bo.comments = 'f:-'
  validate_edit({ '(', '-aaa', ')' }, { 1, 0 }, { '(-aaa)' }, { 1, 0 }, join)
  validate_edit({ '(', '- aaa', ')' }, { 1, 0 }, { '(- aaa)' }, { 1, 0 }, join)
  validate_edit({ '(', '-\taaa', ')' }, { 1, 0 }, { '(-\taaa)' }, { 1, 0 }, join)
  validate_edit({ '- (', '- aaa', '- )' }, { 1, 2 }, { '- (- aaa- )' }, { 1, 2 }, join)
end

T['join()']['works in empty brackets'] = function() validate_edit({ '()' }, { 1, 0 }, { '()' }, { 1, 0 }, join) end

T['join()']['joins nested multiline argument into single line'] = function()
  validate_edit(
    { '(', '\ta,', '\t(', '\t\tb,', '\t\tc', '\t),', '\td', ')' },
    { 1, 0 },
    -- To not have padded brackets in nested arguments, join them separately
    { '(a, ( b, c ), d)' },
    { 1, 0 },
    join
  )
end

T['join()']['returns `nil` if no positions are found'] = function()
  set_lines({ 'aaa' })
  eq(join(), vim.NIL)
  eq(get_lines(), { 'aaa' })
end

T['join()']['respects `opts.position`'] = function()
  validate_edit({ ' (', ' \taaa', ' )' }, { 1, 0 }, { ' (aaa)' }, { 1, 0 }, join, { position = { line = 1, col = 2 } })
  validate_edit({ ' (aaa)' }, { 1, 1 }, { ' (aaa)' }, { 1, 1 }, join, { position = { line = 1, col = 1 } })
end

T['join()']['respects `opts.region`'] = function()
  local lines = { '(', '\ta,', '\t")",', '\tb', ')' }
  local region = { from = { line = 1, col = 1 }, to = { line = 5, col = 0 } }
  validate_edit(lines, { 1, 0 }, { '(a, ")", b)' }, { 1, 0 }, join, { region = region })
end

T['join()']['respects `opts.detect.brackets`'] = function()
  -- Global
  child.lua("MiniSplitjoin.config.detect.brackets = { '%b{}' }")
  validate_edit({ '[aaa]' }, { 1, 0 }, { '[aaa]' }, { 1, 0 }, join)
  validate_edit({ '{', '\taaa', '}' }, { 1, 0 }, { '{aaa}' }, { 1, 0 }, join)

  -- Local
  validate_edit({ '(aaa)' }, { 1, 0 }, { '(aaa)' }, { 1, 0 }, join, { detect = { brackets = {} } })
  validate_edit({ '(aaa)' }, { 1, 0 }, { '(aaa)' }, { 1, 0 }, join, { detect = { brackets = { '%b[]' } } })
end

T['join()']['respects `opts.detect.separator`'] = function()
  -- Global
  child.lua("MiniSplitjoin.config.detect.separator = '|'")
  validate_edit({ '(', '\ta|', '\tb', ')' }, { 1, 0 }, { '(a| b)' }, { 1, 0 }, join)

  -- Local
  local opts = { detect = { separator = '[,;]' } }
  validate_edit({ '(', '\ta,', '\tb;', '\tc', ')' }, { 1, 0 }, { '(a, b; c)' }, { 1, 0 }, join, opts)

  -- Empty separator should mean no internal separator
  opts = { detect = { separator = '' } }
  validate_edit({ '(', '\ta, b; c', ')' }, { 1, 0 }, { '(a, b; c)' }, { 1, 0 }, join, opts)
end

T['join()']['respects `opts.detect.exclude_regions`'] = function()
  -- Global
  child.lua("MiniSplitjoin.config.detect.exclude_regions = { '%b[]' }")
  validate_edit({ '(', '\ta,', '\t(b,', '\tc),', '\t[d, e]', ')' }, { 1, 0 }, { '(a, (b, c), [d, e])' }, { 1, 0 }, join)

  -- Local
  local opts = { detect = { exclude_regions = { '%b()' } } }
  validate_edit(
    { '(', '\ta,', '\t(b, c),', '\t[d,', '\te]', ')' },
    { 1, 0 },
    { '(a, (b, c), [d, e])' },
    { 1, 0 },
    join,
    opts
  )
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
    validate_edit({ '(', 'aaa', ')' }, { 1, 0 }, { '(', 'aaa', ')' }, { 1, 0 }, join)
  end,
})

T['join()']['respects `vim.b.minisplitjoin_config`'] = function()
  child.lua([[vim.b.minisplitjoin_config = { detect = { brackets = { '%b[]' } } }]])
  validate_edit({ '(', 'aaa', ')' }, { 1, 0 }, { '(', 'aaa', ')' }, { 1, 0 }, join)
end

T['gen_hook'] = new_set()

T['gen_hook']['pad_brackets()'] = new_set()

T['gen_hook']['pad_brackets()']['works'] = function()
  child.lua('MiniSplitjoin.config.join.hooks_post = { MiniSplitjoin.gen_hook.pad_brackets() }')
  validate_edit({ '(', '\taaa,', '\tbb,', '\tc', ')' }, { 1, 0 }, { '( aaa, bb, c )' }, { 1, 0 }, join)
  validate_edit({ '[', '\taaa,', '\tbb,', '\tc', ']' }, { 1, 0 }, { '[ aaa, bb, c ]' }, { 1, 0 }, join)
  validate_edit({ '{', '\taaa,', '\tbb,', '\tc', '}' }, { 1, 0 }, { '{ aaa, bb, c }' }, { 1, 0 }, join)

  -- Should return correctly updated input
  set_lines({ '(', 'a,', 'b', ')' })
  local out = join()
  eq(get_lines(), { '( a, b )' })
  eq(out, { { line = 1, col = 1 }, { line = 1, col = 4 }, { line = 1, col = 6 }, { line = 1, col = 8 } })
end

T['gen_hook']['pad_brackets()']['does not act in case of no arguments'] = function()
  child.lua('MiniSplitjoin.config.join.hooks_post = { MiniSplitjoin.gen_hook.pad_brackets() }')
  validate_edit({ '(', ')' }, { 1, 0 }, { '()' }, { 1, 0 }, join)
end

T['gen_hook']['pad_brackets()']['respects `opts.pad`'] = function()
  child.lua("MiniSplitjoin.config.join.hooks_post = { MiniSplitjoin.gen_hook.pad_brackets({ pad = '  ' }) }")
  validate_edit({ '(', 'aa,', 'b', ')' }, { 1, 0 }, { '(  aa, b  )' }, { 1, 0 }, join)
end

T['gen_hook']['pad_brackets()']['respects `opts.brackets`'] = function()
  child.lua([[MiniSplitjoin.config.join.hooks_post = {
    MiniSplitjoin.gen_hook.pad_brackets({ brackets = { '%b{}' } }),
  }]])
  validate_edit({ '(', 'aa,', 'b', ')' }, { 1, 0 }, { '(aa, b)' }, { 1, 0 }, join)
  validate_edit({ '[', 'aa,', 'b', ']' }, { 1, 0 }, { '[aa, b]' }, { 1, 0 }, join)
  validate_edit({ '{', 'aa,', 'b', '}' }, { 1, 0 }, { '{ aa, b }' }, { 1, 0 }, join)
end

T['gen_hook']['add_trailing_separator()'] = new_set()

T['gen_hook']['add_trailing_separator()']['works'] = function()
  child.lua('MiniSplitjoin.config.split.hooks_post = { MiniSplitjoin.gen_hook.add_trailing_separator() }')
  validate_edit({ '(aa)' }, { 1, 0 }, { '(', '\taa,', ')' }, { 1, 0 }, split)
  validate_edit({ '[aa]' }, { 1, 0 }, { '[', '\taa,', ']' }, { 1, 0 }, split)
  validate_edit({ '{aa}' }, { 1, 0 }, { '{', '\taa,', '}' }, { 1, 0 }, split)

  validate_edit({ '(aa, b)' }, { 1, 0 }, { '(', '\taa,', '\tb,', ')' }, { 1, 0 }, split)

  -- Should return correctly updated input
  set_lines({ '(aa)' })
  local out = split()
  eq(get_lines(), { '(', '\taa,', ')' })
  eq(out, { { line = 1, col = 1 }, { line = 2, col = 3 }, { line = 3, col = 1 } })
end

T['gen_hook']['add_trailing_separator()']['does nothing if there is already trailing separator'] = function()
  child.lua('MiniSplitjoin.config.split.hooks_post = { MiniSplitjoin.gen_hook.add_trailing_separator() }')
  validate_edit({ '(aa,)' }, { 1, 0 }, { '(', '\taa,', ')' }, { 1, 0 }, split)
  validate_edit({ '(aa, b,)' }, { 1, 0 }, { '(', '\taa,', '\tb,', ')' }, { 1, 0 }, split)
end

T['gen_hook']['add_trailing_separator()']['does not act in case of no arguments'] = function()
  child.lua('MiniSplitjoin.config.split.hooks_post = { MiniSplitjoin.gen_hook.add_trailing_separator() }')
  validate_edit({ '()' }, { 1, 0 }, { '(', ')' }, { 1, 0 }, split)
end

T['gen_hook']['add_trailing_separator()']['respects `opts.sep`'] = function()
  child.lua([[MiniSplitjoin.config.split.hooks_post = {
    MiniSplitjoin.gen_hook.add_trailing_separator({ sep = '!'}),
  }]])
  validate_edit({ '(aa)' }, { 1, 0 }, { '(', '\taa!', ')' }, { 1, 0 }, split)
end

T['gen_hook']['add_trailing_separator()']['respects `opts.brackets`'] = function()
  child.lua([[MiniSplitjoin.config.split.hooks_post = {
    MiniSplitjoin.gen_hook.add_trailing_separator({ brackets = { '%b{}' }}),
  }]])
  validate_edit({ '(aa)' }, { 1, 0 }, { '(', '\taa', ')' }, { 1, 0 }, split)
  validate_edit({ '[aa]' }, { 1, 0 }, { '[', '\taa', ']' }, { 1, 0 }, split)
  validate_edit({ '{aa}' }, { 1, 0 }, { '{', '\taa,', '}' }, { 1, 0 }, split)
end

T['gen_hook']['del_trailing_separator()'] = new_set()

T['gen_hook']['del_trailing_separator()']['works'] = function()
  child.lua('MiniSplitjoin.config.join.hooks_post = { MiniSplitjoin.gen_hook.del_trailing_separator() }')
  validate_edit({ '(', '\taa,', ')' }, { 1, 0 }, { '(aa)' }, { 1, 0 }, join)
  validate_edit({ '[', '\taa,', ']' }, { 1, 0 }, { '[aa]' }, { 1, 0 }, join)
  validate_edit({ '{', '\taa,', '}' }, { 1, 0 }, { '{aa}' }, { 1, 0 }, join)

  validate_edit({ '(', '\taa,', '\tb,', ')' }, { 1, 0 }, { '(aa, b)' }, { 1, 0 }, join)

  -- Should return correctly updated input
  set_lines({ '(', '\taa,', ')' })
  local out = join()
  eq(get_lines(), { '(aa)' })
  eq(out, { { line = 1, col = 1 }, { line = 1, col = 4 }, { line = 1, col = 4 } })
end

T['gen_hook']['del_trailing_separator()']['does nothing if there is already no trailing separator'] = function()
  child.lua('MiniSplitjoin.config.join.hooks_post = { MiniSplitjoin.gen_hook.del_trailing_separator() }')
  validate_edit({ '(', '\taa', ')' }, { 1, 0 }, { '(aa)' }, { 1, 0 }, join)
  validate_edit({ '(', '\taa,', '\tb', ')' }, { 1, 0 }, { '(aa, b)' }, { 1, 0 }, join)
end

T['gen_hook']['del_trailing_separator()']['respects `opts.sep`'] = function()
  child.lua([[MiniSplitjoin.config.join.hooks_post = {
    MiniSplitjoin.gen_hook.del_trailing_separator({ sep = '!'}),
  }]])
  validate_edit({ '(', '\taa!', ')' }, { 1, 0 }, { '(aa)' }, { 1, 0 }, join)
end

T['gen_hook']['del_trailing_separator()']['respects `opts.brackets`'] = function()
  child.lua([[MiniSplitjoin.config.join.hooks_post = {
    MiniSplitjoin.gen_hook.del_trailing_separator({ brackets = { '%b{}' }}),
  }]])
  validate_edit({ '(', '\taa,', ')' }, { 1, 0 }, { '(aa,)' }, { 1, 0 }, join)
  validate_edit({ '[', '\taa,', ']' }, { 1, 0 }, { '[aa,]' }, { 1, 0 }, join)
  validate_edit({ '{', '\taa,', '}' }, { 1, 0 }, { '{aa}' }, { 1, 0 }, join)
end

T['split_at()'] = new_set()

local split_at = function(positions)
  return child.lua_get('MiniSplitjoin.split_at(...)', { vim.tbl_map(simplepos_to_pos, positions) })
end

T['split_at()']['works'] = function()
  validate_edit({ '(aaa)' }, { 1, 2 }, { '(', '\taaa', ')' }, { 2, 2 }, split_at, { { 1, 1 }, { 1, 4 } })

  validate_edit({ '()' }, { 1, 1 }, { '(', '', ')' }, { 3, 0 }, split_at, { { 1, 1 }, { 1, 1 } })

  validate_edit(
    { '(aaa, bb, c)' },
    { 1, 7 },
    { '(', '\taaa,', '\tbb,', '\tc', ')' },
    { 3, 2 },
    split_at,
    { { 1, 1 }, { 1, 5 }, { 1, 9 }, { 1, 11 } }
  )
end

T['split_at()']['works not on single line'] = function()
  validate_edit(
    { 'aabb', 'ccdd' },
    { 1, 3 },
    { 'aa', '\tbb', '\tcc', 'dd' },
    { 2, 2 },
    split_at,
    { { 1, 2 }, { 2, 2 } }
  )
end

T['split_at()']['properly tracks cursor'] = function()
  validate_edit({ '()' }, { 1, 0 }, { '(', ')' }, { 1, 0 }, split_at, { { 1, 1 } })
  validate_edit({ '()' }, { 1, 1 }, { '(', ')' }, { 2, 0 }, split_at, { { 1, 1 } })

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
  for _, cursor in ipairs(cursors) do
    validate_edit(
      { 'b( aaa )b' },
      cursor.before,
      { 'b(', '\taaa', ')b' },
      cursor.after,
      split_at,
      { { 1, 2 }, { 1, 7 } }
    )
  end
end

T['split_at()']['copies indent of current line'] = function()
  validate_edit(
    { ' \t (aaa)' },
    { 1, 5 },
    { ' \t (', ' \t \taaa', ' \t )' },
    { 2, 5 },
    split_at,
    { { 1, 4 }, { 1, 7 } }
  )
end

T['split_at()']['does not increase indent of blank lines'] = function()
  validate_edit(
    { '(', 'a,b)' },
    { 2, 3 },
    { '(', '', '\ta,', '\tb', ')' },
    { 5, 0 },
    split_at,
    { { 1, 1 }, { 2, 2 }, { 2, 3 } }
  )

  validate_edit({ '  (', ')' }, { 2, 0 }, { '  (', '  ', ')' }, { 3, 0 }, split_at, { { 1, 3 } })
end

T['split_at()']['handles extra whitespace'] = function()
  validate_edit({ '(   aaa   )' }, { 1, 5 }, { '(', '\taaa', ')' }, { 2, 2 }, split_at, { { 1, 1 }, { 1, 7 } })
  validate_edit({ '(   aaa   )' }, { 1, 5 }, { '(', '\taaa', ')' }, { 2, 2 }, split_at, { { 1, 3 }, { 1, 9 } })
end

T['split_at()']['correctly tracks input positions'] = function()
  set_lines({ '(aaa, bb, c)' })
  local out = split_at({ { 1, 1 }, { 1, 5 }, { 1, 9 }, { 1, 11 } })
  validate_positions(out, { { 1, 1 }, { 2, 5 }, { 3, 4 }, { 4, 2 } })
  eq(get_lines(), { '(', '\taaa,', '\tbb,', '\tc', ')' })
end

--stylua: ignore
T['split_at()']['works inside comments'] = function()
  -- After 'commentstring'
  child.bo.commentstring = '# %s'
  validate_edit({ '# (aaa)' }, { 1, 2 }, { '# (', '# \taaa', '# )' }, { 1, 2 }, split_at, { { 1, 3 }, { 1, 6 } })

  -- After any entry in 'comments'
  child.bo.comments = ':---,:--'
  validate_edit({ '-- (aaa)' },  { 1, 3 }, { '-- (',  '-- \taaa',  '-- )' },  { 1, 3 }, split_at, { { 1, 4 }, { 1, 7 } })
  validate_edit({ '--- (aaa)' }, { 1, 4 }, { '--- (', '--- \taaa', '--- )' }, { 1, 4 }, split_at, { { 1, 5 }, { 1, 8 } })

  -- Respects `b` flag
  child.bo.comments = 'b:*'
  validate_edit({ '*(aaa)' }, { 1, 1 }, { '*(', '\taaa', ')' }, { 1, 1 }, split_at, { { 1, 2 }, { 1, 5 } })
  validate_edit({ '* (aaa)' }, { 1, 2 }, { '* (', '* \taaa', '* )' }, { 1, 2 }, split_at, { { 1, 3 }, { 1, 6 } })
  validate_edit({ '*\t(aaa)' }, { 1, 2 }, { '*\t(', '*\t\taaa', '*\t)' }, { 1, 2 }, split_at, { { 1, 3 }, { 1, 6 } })

  -- Respects `f` flag (ignores as comment leader)
  child.bo.comments = 'f:-'
  validate_edit({ '-(aaa)' }, { 1, 1 }, { '-(', '\taaa', ')' }, { 1, 1 }, split_at, { { 1, 2 }, { 1, 5 } })
  validate_edit({ '- (aaa)' }, { 1, 2 }, { '- (', '\taaa', ')' }, { 1, 2 }, split_at, { { 1, 3 }, { 1, 6 } })
  validate_edit({ '-\t(aaa)' }, { 1, 2 }, { '-\t(', '\taaa', ')' }, { 1, 2 }, split_at, { { 1, 3 }, { 1, 6 } })
end

T['split_at()']['correctly increases indent of commented line in non-commented block'] = function()
  child.bo.commentstring = '# %s'

  validate_edit(
    { '(aa', '# b', 'c)' },
    { 1, 0 },
    { '(', '\taa', '\t# b', '\tc', ')' },
    { 1, 0 },
    split_at,
    { { 1, 1 }, { 3, 1 } }
  )
end

T['split_at()']['uses first and last positions to determine indent range'] = function()
  validate_edit(
    { '(a, b, c)' },
    { 1, 0 },
    { '(', 'a,', 'b,', '\tc', ')' },
    { 1, 0 },
    split_at,
    { { 1, 6 }, { 1, 3 }, { 1, 1 }, { 1, 8 } }
  )
end

T['split_at()']["respects 'expandtab' and 'shiftwidth' for indent increase"] = function()
  child.o.expandtab = true
  child.o.shiftwidth = 3
  validate_edit({ '(aaa)' }, { 1, 0 }, { '(', '   aaa', ')' }, { 1, 0 }, split_at, { { 1, 1 }, { 1, 4 } })
end

T['join_at()'] = new_set()

local join_at = function(positions)
  return child.lua_get('MiniSplitjoin.join_at(...)', { vim.tbl_map(simplepos_to_pos, positions) })
end

T['join_at()']['works'] = function()
  validate_edit(
    { '(', '\taaa,', '   bb,', 'c', ')' },
    { 2, 2 },
    { '(aaa, bb, c)' },
    { 1, 2 },
    join_at,
    { { 1, 1 }, { 2, 4 }, { 3, 3 }, { 4, 1 } }
  )
end

T['join_at()']['works on single line'] = function()
  validate_edit({ '(', '\ta', '\tb', ')' }, { 1, 0 }, { '(a b)' }, { 1, 0 }, join_at, { { 1, 1 }, { 1, 1 }, { 1, 1 } })
end

T['join_at()']['joins line at any its column'] = function()
  for i = 1, 4 do
    validate_edit({ '   (', '\taaa', ')' }, { 2, 2 }, { '   (aaa)' }, { 1, 5 }, join_at, { { 1, i }, { 2, i } })
  end
end

T['join_at()']['properly tracks cursor'] = function()
  validate_edit({ '(', ')' }, { 1, 0 }, { '()' }, { 1, 0 }, join_at, { { 1, 1 } })
  validate_edit({ '(', ')' }, { 2, 0 }, { '()' }, { 1, 1 }, join_at, { { 1, 1 } })

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
  for _, cursor in ipairs(cursors) do
    validate_edit({ 'b(', '\taaa ', ')b' }, cursor.before, { 'b(aaa)b' }, cursor.after, join_at, { { 1, 2 }, { 2, 4 } })
  end
end

T['join_at()']['handles extra whitespace'] = function()
  validate_edit(
    { '( \t', '\t\ta  ', '  b\t\t', ' \t  )' },
    { 1, 0 },
    { '(a b)' },
    { 1, 0 },
    join_at,
    { { 1, 1 }, { 2, 1 }, { 3, 1 } }
  )
end

T['join_at()']['correctly works with positions on last line'] = function()
  validate_edit(
    { '(', 'a', ')b' },
    { 1, 0 },
    { '(a )b' },
    { 1, 0 },
    join_at,
    { { 1, 1 }, { 2, 1 }, { 3, 1 }, { 3, 2 } }
  )
end

T['join_at()']['correctly tracks input positions'] = function()
  set_lines({ '(', '\taaa,', '\tbb,', '\tc', ')' })
  local out = join_at({ { 1, 1 }, { 2, 5 }, { 3, 4 }, { 4, 2 } })
  validate_positions(out, { { 1, 1 }, { 1, 5 }, { 1, 9 }, { 1, 11 } })
  eq(get_lines(), { '(aaa, bb, c)' })
end

--stylua: ignore
T['join_at()']['works inside comments'] = function()
  local two_lines_pos = { { 1, 1 }, { 2, 1 } }

  -- After 'commentstring'
  child.bo.commentstring = '# %s'
  validate_edit({ '# (', '# \taaa', '# )' }, { 1, 2 }, { '# (aaa)' }, { 1, 2 }, join_at, two_lines_pos)
  validate_edit({ '# (', 'aaa',     '# )' }, { 1, 2 }, { '# (aaa)' }, { 1, 2 }, join_at, two_lines_pos)

  -- After any entry in 'comments'
  child.bo.comments = ':---,:--'
  validate_edit({ '-- (',  '-- \taaa',  '-- )' },  { 1, 3 }, { '-- (aaa)' },  { 1, 3 }, join_at, two_lines_pos)
  validate_edit({ '--- (', '--- \taaa', '--- )' }, { 1, 4 }, { '--- (aaa)' }, { 1, 4 }, join_at, two_lines_pos)

  -- Respects `b` flag
  child.bo.comments = 'b:*'
  validate_edit({ '*(', '\t*aaa', '*)' }, { 1, 1 }, { '*(*aaa*)' }, { 1, 1 }, join_at, two_lines_pos)
  validate_edit({ '* (', '\t* aaa', '* )' }, { 1, 2 }, { '* (aaa)' }, { 1, 2 }, join_at, two_lines_pos)
  validate_edit({ '*\t(', '\t*\taaa', '*\t)' }, { 1, 2 }, { '*\t(aaa)' }, { 1, 2 }, join_at, two_lines_pos)

  -- Respects `f` flag (ignores as comment leader)
  child.bo.comments = 'f:-'
  validate_edit({ '(', '-aaa', ')' }, { 1, 0 }, { '(-aaa)' }, { 1, 0 }, join_at, two_lines_pos)
  validate_edit({ '(', '- aaa', ')' }, { 1, 0 }, { '(- aaa)' }, { 1, 0 }, join_at, two_lines_pos)
  validate_edit({ '(', '-\taaa', ')' }, { 1, 0 }, { '(-\taaa)' }, { 1, 0 }, join_at, two_lines_pos)
  validate_edit({ '- (', '- aaa', '- )' }, { 1, 2 }, { '- (- aaa- )' }, { 1, 2 }, join_at, two_lines_pos)
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
  validate_keys({ '(aa, b)' }, { 1, 0 }, { '(', '\taa,', '\tb', ')' }, { 1, 0 }, 'gS')
  validate_keys({ '(', '\taa,', '\tb', ')' }, { 1, 0 }, { '(aa, b)' }, { 1, 0 }, 'gS')

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
  validate_keys({ '(aa, ")", b)' }, { 1, 0 }, { '(', '\taa,', '\t")",', '\tb', ')' }, { 1, 0 }, 'VgS')
  validate_keys({ '(aa)', 'bb' }, { 1, 0 }, { '(aa)bb' }, { 1, 0 }, 'VjgS')
end

T['Mappings']['Toggle']['works with different mapping'] = function()
  child.api.nvim_del_keymap('n', 'gS')
  child.api.nvim_del_keymap('x', 'gS')

  reload_module({ mappings = { toggle = 'gs' } })
  validate_keys({ '(aa, b)' }, { 1, 0 }, { '(', '\taa,', '\tb', ')' }, { 1, 0 }, 'gs')
  validate_keys({ '(aa, ")", b)' }, { 1, 0 }, { '(', '\taa,', '\t")",', '\tb', ')' }, { 1, 0 }, 'Vgs')
end

T['Mappings']['Toggle']['respects `vim.{g,b}.minisplitjoin_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minisplitjoin_disable = true
    validate_keys({ '(aaa)' }, { 1, 0 }, { '(aaa)' }, { 1, 0 }, 'gS')
  end,
})

T['Mappings']['Split'] = new_set()

T['Mappings']['Split']['works in Normal mode'] = function()
  reload_module({ mappings = { split = 'S' } })

  validate_keys({ '(aa, b)' }, { 1, 0 }, { '(', '\taa,', '\tb', ')' }, { 1, 0 }, 'S')

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
  validate_keys({ '(aa, ")", b)' }, { 1, 0 }, { '(', '\taa,', '\t")",', '\tb', ')' }, { 1, 0 }, 'VS')
end

T['Mappings']['Split']['respects `vim.{g,b}.minisplitjoin_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    reload_module({ mappings = { split = 'S' } })
    child[var_type].minisplitjoin_disable = true
    validate_keys({ '(aaa)' }, { 1, 0 }, { '(aaa)' }, { 1, 0 }, 'S')
  end,
})

T['Mappings']['Join'] = new_set()

T['Mappings']['Join']['works in Normal mode'] = function()
  reload_module({ mappings = { join = 'J' } })

  validate_keys({ '(', '\taa,', '\tb', ')' }, { 1, 0 }, { '(aa, b)' }, { 1, 0 }, 'J')

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
  validate_keys({ '(aa)', 'bb' }, { 1, 0 }, { '(aa)bb' }, { 1, 0 }, 'VjJ')
end

T['Mappings']['Join']['respects `vim.{g,b}.minisplitjoin_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    reload_module({ mappings = { join = 'J' } })
    child[var_type].minisplitjoin_disable = true
    validate_keys({ '(', 'aaa', ')' }, { 1, 0 }, { '(', 'aaa', ')' }, { 1, 0 }, 'J')
  end,
})

return T
