local helpers = dofile('tests/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
local load_module = function(config) child.mini_load('trailspace', config) end
local unload_module = function() child.mini_unload('trailspace') end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end

-- Make helpers
local ensure_no_highlighting = function() child.fn.clearmatches() end

-- Data =======================================================================
local example_lines = { 'aa ', 'aa  ', 'aa\t', 'aa\t\t', 'aa \t', 'aa\t ', '  aa', '\taa' }
local example_trimmed_lines = vim.tbl_map(function(x) return x:gsub('%s*$', '') end, example_lines)

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      child.set_size(10, 20)
      child.o.hidden = true
      set_lines(example_lines)
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
  eq(child.lua_get('type(_G.MiniTrailspace)'), 'table')

  -- Autocommand group
  eq(child.fn.exists('#MiniTrailspace'), 1)

  -- Highlight groups
  child.cmd('hi clear')
  load_module()
  expect.match(child.cmd_capture('hi MiniTrailspace'), 'links to Error')
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniTrailspace.config)'), 'table')

  -- Check default values
  eq(child.lua_get('MiniTrailspace.config.only_in_normal_buffers'), true)
end

T['setup()']['respects `config` argument'] = function()
  unload_module()
  load_module({ only_in_normal_buffers = false })
  eq(child.lua_get('MiniTrailspace.config.only_in_normal_buffers'), false)
end

T['setup()']['validates `config` argument'] = function()
  unload_module()

  local expect_config_error = function(config, name, target_type)
    expect.error(function() load_module(config) end, vim.pesc(name) .. '.*' .. vim.pesc(target_type))
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ only_in_normal_buffers = 'a' }, 'only_in_normal_buffers', 'boolean')
end

T['setup()']['ensures colors'] = function()
  child.cmd('colorscheme default')
  expect.match(child.cmd_capture('hi MiniTrailspace'), 'links to Error')
end

T['highlight()'] = new_set({ hooks = { pre_case = ensure_no_highlighting } })

T['highlight()']['works'] = function()
  child.expect_screenshot()
  child.lua('MiniTrailspace.highlight()')
  child.expect_screenshot()
end

T['highlight()']['respects `config.only_in_normal_buffers`'] = new_set({
  parametrize = {
    { true, '' },
    { true, 'nofile' },
    { true, 'help' },
    { false, '' },
    { false, 'nofile' },
    { false, 'help' },
  },
}, {
  test = function(option_value, buftype)
    child.lua('MiniTrailspace.config.only_in_normal_buffers = ' .. tostring(option_value))
    child.bo.buftype = buftype
    child.lua('MiniTrailspace.highlight()')
    child.expect_screenshot()
  end,
})

T['highlight()']['respects `vim.b.minitrailspace_config`'] = function()
  child.b.minitrailspace_config = { only_in_normal_buffers = false }
  child.bo.buftype = 'nofile'
  child.lua('MiniTrailspace.highlight()')
  -- Should highlight
  child.expect_screenshot()
end

T['highlight()']['works only in Normal mode'] = new_set({
  parametrize = { { 'i' }, { 'v' }, { 'R' }, { ':' } },
}, {
  test = function(mode_key)
    type_keys(mode_key)
    child.lua('MiniTrailspace.highlight()')
    -- Should be no highlighting
    child.expect_screenshot()
  end,
})

T['highlight()']['does not unnecessarily create match entry'] = function()
  child.lua('MiniTrailspace.highlight()')
  local matches = child.fn.getmatches()
  eq(#matches, 1)

  child.lua('MiniTrailspace.highlight()')
  eq(child.fn.getmatches(), matches)
end

T['highlight()']['works after `clearmatches()`'] = function()
  child.lua('MiniTrailspace.highlight()')
  child.fn.clearmatches()
  -- Should be no highlight
  child.expect_screenshot()

  child.lua('MiniTrailspace.highlight()')
  -- Should be highlighted again
  child.expect_screenshot()
end

T['highlight()']['respects `vim.{g,b}.minitrailspace_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minitrailspace_disable = true
    child.lua('MiniTrailspace.highlight()')
    -- Should show no highlight
    child.expect_screenshot()
  end,
})

T['unhighlight()'] = new_set({
  hooks = {
    pre_case = function() child.lua('MiniTrailspace.highlight()') end,
  },
})

T['unhighlight()']['works'] = function()
  child.expect_screenshot()
  child.lua('MiniTrailspace.unhighlight()')
  child.expect_screenshot()
end

T['unhighlight()']['works after `clearmatches()`'] = function()
  child.fn.clearmatches()
  child.lua('MiniTrailspace.unhighlight()')
  child.expect_screenshot()
end

T['trim()'] = new_set()

T['trim()']['works'] = function()
  child.lua('MiniTrailspace.trim()')
  eq(get_lines(), example_trimmed_lines)
end

T['trim()']['does not move cursor'] = function()
  set_cursor(4, 1)
  child.lua('MiniTrailspace.trim()')
  eq(get_cursor(), { 4, 1 })
end

T['trim()']['does not update search pattern'] = function()
  type_keys('/', 'aa', '<CR>')
  child.lua('MiniTrailspace.trim()')
  eq(child.fn.getreg('/'), 'aa')
end

T['trim_last_lines()'] = new_set()

local validate_last_lines = function(init_lines, expected_lines)
  set_lines(init_lines)
  child.lua('MiniTrailspace.trim_last_lines()')
  eq(get_lines(), expected_lines)
end

T['trim_last_lines()']['works'] = function()
  validate_last_lines({ 'aa', '' }, { 'aa' })
  validate_last_lines({ 'aa', ' ' }, { 'aa' })
  validate_last_lines({ 'aa', '\t' }, { 'aa' })

  validate_last_lines({ 'aa' }, { 'aa' })
  validate_last_lines({ '' }, { '' })
  validate_last_lines({ 'aa ' }, { 'aa ' })

  validate_last_lines({ 'aa', '', '' }, { 'aa' })
  validate_last_lines({ 'aa', ' ', ' ' }, { 'aa' })
  validate_last_lines({ 'aa', '', ' ', '' }, { 'aa' })

  validate_last_lines({ '', 'aa', '' }, { '', 'aa' })
  validate_last_lines({ ' ', 'aa', '' }, { ' ', 'aa' })

  validate_last_lines({ ' aa', '' }, { ' aa' })
  validate_last_lines({ 'aa ', '' }, { 'aa ' })

  validate_last_lines({ 'aa', 'bb', '' }, { 'aa', 'bb' })
  validate_last_lines({ 'aa', '', 'bb', '' }, { 'aa', '', 'bb' })
  validate_last_lines({ 'aa', ' ', 'bb', ' ' }, { 'aa', ' ', 'bb' })
  validate_last_lines({ '', 'aa', '', 'bb', '' }, { '', 'aa', '', 'bb' })
end

-- Integration tests ==========================================================
T['Trailspace autohighlighting'] = new_set()

T['Trailspace autohighlighting']['respects InsertEnter/InsertLeave'] = function()
  child.lua('MiniTrailspace.highlight()')
  child.expect_screenshot()

  child.cmd('startinsert')
  child.expect_screenshot()

  child.cmd('stopinsert')
  child.expect_screenshot()
end

T['Trailspace autohighlighting']['respects BufEnter/BufLeave'] = function()
  child.lua('MiniTrailspace.highlight()')
  child.expect_screenshot()

  child.cmd('doautocmd BufLeave')
  child.expect_screenshot()

  child.cmd('doautocmd BufEnter')
  child.expect_screenshot()
end

T['Trailspace autohighlighting']['respects WinEnter/WinLeave'] = function()
  child.set_size(10, 40)
  child.lua('MiniTrailspace.highlight()')
  child.cmd('edit bbb | vsplit | edit aaa')
  for _, buf_id in ipairs(child.api.nvim_list_bufs()) do
    child.api.nvim_buf_set_lines(buf_id, 0, -1, true, example_lines)
  end
  local win_list = child.api.nvim_list_wins()

  child.api.nvim_set_current_win(win_list[1])
  child.expect_screenshot()

  child.api.nvim_set_current_win(win_list[2])
  child.expect_screenshot()

  child.api.nvim_set_current_win(win_list[1])
  child.expect_screenshot()
end

T['Trailspace autohighlighting']['respects OptionSet'] = function()
  child.lua('MiniTrailspace.highlight()')

  child.bo.buftype = 'nowrite'
  child.expect_screenshot()

  child.bo.buftype = ''
  child.expect_screenshot()
end

T['Trailspace highlighting on startup'] = new_set()

T['Trailspace highlighting on startup']['works'] = function()
  child.restart({
    '-u',
    'scripts/minimal_init.lua',
    '-c',
    [[lua require('mini.trailspace').setup()]],
    '--',
    'tests/dir-trailspace/file',
  })
  child.set_size(5, 12)
  child.expect_screenshot({ ignore_text = helpers.is_windows() and { 4 } or {} })
end

return T
