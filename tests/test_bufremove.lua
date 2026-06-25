local helpers = dofile('tests/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
local load_module = function(config) child.mini_load('bufremove', config) end
local unload_module = function() child.mini_unload('bufremove') end
local win_get_buf = function(...) return child.api.nvim_win_get_buf(...) end
local buf_get_option = function(...) return child.api.nvim_buf_get_option(...) end

-- Make helpers
local setup_layout = function()
  local res = {}

  child.cmd('silent %bwipeout!')

  -- Create two vertical windows (with ids 'win_left' and 'win_right') with the
  -- same active buffer ('buf') but different alternate buffers (with ids
  -- 'buf_left' and 'buf_right' respectively)
  child.cmd('edit buf')
  res['buf'] = child.api.nvim_get_current_buf()

  child.cmd('edit buf_right')
  res['buf_right'], res['win_right'] = child.api.nvim_get_current_buf(), child.api.nvim_get_current_win()

  child.cmd('edit # | vsplit | edit buf_left')
  res['buf_left'], res['win_left'] = child.api.nvim_get_current_buf(), child.api.nvim_get_current_win()

  child.cmd('edit #')

  return res
end

local validate_unshow_alternate = function(fun_name, layout)
  eq(child.lua_get(('MiniBufremove.%s()'):format(fun_name)), true)

  eq(win_get_buf(layout['win_left']), layout['buf_left'])
  eq(win_get_buf(layout['win_right']), layout['buf_right'])
end

local validate_unshow_bprevious = function(fun_name, layout)
  child.cmd('bwipeout ' .. layout['buf_left'])
  local bprevious_buf = child.api.nvim_create_buf(true, false)

  eq(child.lua_get(('MiniBufremove.%s()'):format(fun_name)), true)

  eq(win_get_buf(layout['win_left']), bprevious_buf)
  eq(win_get_buf(layout['win_right']), layout['buf_right'])
end

local validate_unshow_normal_buf = function(fun_name, layout)
  -- Wipeout all buffers except current
  child.cmd('.+,$bwipeout')

  eq(child.lua_get(('MiniBufremove.%s()'):format(fun_name)), true)

  -- Verify that created buffer is a normal buffer
  local new_buf = child.api.nvim_get_current_buf()
  expect.no_equality(new_buf, layout['buf'])
  eq(buf_get_option(new_buf, 'buflisted'), true)
  eq(buf_get_option(new_buf, 'buftype'), '')
  -- Should be unnamed to allow `:h buffer-reuse`
  eq(child.api.nvim_buf_get_name(new_buf), '')

  eq(win_get_buf(layout['win_left']), new_buf)
  eq(win_get_buf(layout['win_right']), new_buf)
end

local validate_unshow_cmdwin = function(fun_name)
  child.cmd('only')

  child.type_keys('q:')
  eq(child.fn.getcmdwintype(), ':')
  eq(#child.api.nvim_list_wins(), 2)

  local command = ('MiniBufremove.%s()'):format(fun_name)
  local out = child.lua_get(command)
  eq(out, true)

  eq(child.fn.getcmdwintype(), '')
  eq(#child.api.nvim_list_wins(), 1)
end

local validate_args_validation = function(fun_name, args)
  if vim.tbl_contains(args, 'buf_id') then
    local command = ('MiniBufremove.%s(100)'):format(fun_name)
    eq(child.lua_get(command), false)
    local last_message = child.cmd_capture('1messages')
    eq(last_message, '(mini.bufremove) 100 is not a valid buffer id.')
  end

  if args['force'] then
    local command = ('MiniBufremove.%s(nil, 1)'):format(fun_name)
    eq(child.lua_get(command), false)
    local last_message = child.cmd_capture('1messages')
    eq(last_message, '(mini.bufremove) `force` should be boolean.')
  end
end

local validate_unshow_with_buf_id = function(fun_name, layout)
  local command = ('MiniBufremove.%s(...)'):format(fun_name)
  eq(child.lua_get(command, { layout['buf'] }), true)

  eq(win_get_buf(layout['win_left']), layout['buf_left'])
  eq(win_get_buf(layout['win_right']), layout['buf_right'])
end

local mock_confirm = function(user_choice)
  local lua_cmd = string.format('vim.fn.confirm = function(...) _G.confirm_args = { ... }; return %d end', user_choice)
  child.lua(lua_cmd)
end

local validate_force_argument = function(fun_name, layout)
  child.api.nvim_buf_set_lines(layout['buf'], 0, -1, true, { 'aaa' })
  -- Avoid hit-enter prompt due to long message
  child.o.cmdheight = 10

  -- Should ask for confirmation for modified buffer and no `force`
  mock_confirm(1)
  eq(child.bo.modified, true)
  local output = child.lua_get(('MiniBufremove.%s()'):format(fun_name))
  eq(output, false)

  local prompt =
    string.format('Buffer %d has unsaved changes. Do you want to force %s?', child.api.nvim_get_current_buf(), fun_name)
  -- - Default choice should be 'No'
  eq(child.lua_get('_G.confirm_args'), { prompt, '&No\n&Yes', 1, 'Question' })

  eq(win_get_buf(layout['win_left']), layout['buf'])
  eq(win_get_buf(layout['win_right']), layout['buf'])

  -- Should properly remove modified buffer after confirmation
  mock_confirm(2)
  eq(child.bo.modified, true)
  output = child.lua_get(('MiniBufremove.%s()'):format(fun_name))
  eq(output, true)
  eq(win_get_buf(layout['win_left']), layout['buf_left'])
  eq(win_get_buf(layout['win_right']), layout['buf_right'])

  -- Should properly remove buffer with `force`
  output = child.lua_get(('MiniBufremove.%s(nil, true)'):format(fun_name))
  eq(output, true)
  eq(win_get_buf(layout['win_left']), layout['buf_right'])
  eq(win_get_buf(layout['win_right']), layout['buf_right'])
end

local validate_disable = function(var_type, fun_name, layout)
  child[var_type].minibufremove_disable = true
  local output = child.lua_get(('MiniBufremove.%s()'):format(fun_name))
  eq(output, vim.NIL)

  -- Check that lyout didn't change
  eq(win_get_buf(layout['win_left']), layout['buf'])
  eq(win_get_buf(layout['win_right']), layout['buf'])
end

local validate_silent = function(fun_name)
  child.lua('MiniBufremove.config.silent = true')

  local command = ('MiniBufremove.%s(-1)'):format(fun_name)
  eq(child.lua_get(command), false)

  -- Should show no message
  eq(child.cmd_capture('1messages'), '')
end

local validate_bufhidden_option = function(fun_name, bufhidden_value)
  local layout = setup_layout()
  child.api.nvim_buf_set_option(layout['buf'], 'bufhidden', bufhidden_value)

  local command = ('MiniBufremove.%s(...)'):format(fun_name)
  local output = child.lua_get(command, { layout['buf'] })
  eq(output, true)

  if fun_name == 'wipeout' or bufhidden_value == 'wipe' then
    eq(child.api.nvim_buf_is_valid(layout['buf']), false)
  else
    eq(buf_get_option(layout['buf'], 'buflisted'), false)
  end
end

-- Output test set ============================================================
local layout
local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      layout = setup_layout()
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
  eq(child.lua_get('type(_G.MiniBufremove)'), 'table')

  -- Sets appropriate settings
  eq(child.lua_get('vim.o.hidden'), true)
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniBufremove.config)'), 'table')

  -- Check default values
  eq(child.lua_get('MiniBufremove.config.silent'), false)
end

T['setup()']['respects `config` argument'] = function()
  unload_module()
  load_module({ silent = true })
  eq(child.lua_get('MiniBufremove.config.silent'), true)
end

T['setup()']['validates `config` argument'] = function()
  unload_module()

  local expect_config_error = function(config, name, target_type)
    expect.error(function() load_module(config) end, vim.pesc(name) .. '.*' .. vim.pesc(target_type))
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ silent = 'a' }, 'silent', 'boolean')
end

T['unshow()'] = new_set()

T['unshow()']['uses alternate buffer'] = function()
  validate_unshow_alternate('unshow', layout)
  eq(buf_get_option(layout['buf'], 'buflisted'), true)
end

T['unshow()']['uses `bprevious`'] = function()
  validate_unshow_bprevious('unshow', layout)
  eq(buf_get_option(layout['buf'], 'buflisted'), true)
end

T['unshow()']['creates a stand-in listed buffer'] = function()
  validate_unshow_normal_buf('unshow', layout)
  eq(buf_get_option(layout['buf'], 'buflisted'), true)
end

T['unshow()']['validates arguments'] = function() validate_args_validation('unshow', { 'buf_id' }) end

T['unshow()']['closes command-line window'] = function() validate_unshow_cmdwin('unshow') end

T['unshow()']['respects `buf_id` argument'] = function()
  validate_unshow_with_buf_id('unshow', layout)
  eq(buf_get_option(layout['buf'], 'buflisted'), true)
end

T['unshow()']['respects `vim.{g,b}.minibufremove_disable`'] = new_set(
  { parametrize = { { 'g' }, { 'b' } } },
  { test = function(var_type) validate_disable(var_type, 'unshow', layout) end }
)

T['unshow()']['respects `config.silent`'] = function() validate_silent('unshow') end

T['unshow_in_window()'] = new_set()

T['unshow_in_window()']['uses alternate buffer'] = function()
  eq(child.lua_get('MiniBufremove.unshow_in_window()'), true)
  eq(win_get_buf(layout['win_left']), layout['buf_left'])
  eq(win_get_buf(layout['win_right']), layout['buf'])

  -- Ensure that buffer is not deleted
  eq(buf_get_option(layout['buf'], 'buflisted'), true)
end

T['unshow_in_window()']['uses `bprevious`'] = function()
  child.cmd('bwipeout ' .. layout['buf_left'])
  local previous_buf = child.api.nvim_create_buf(true, false)

  eq(child.lua_get('MiniBufremove.unshow_in_window()'), true)
  eq(win_get_buf(layout['win_left']), previous_buf)
  eq(win_get_buf(layout['win_right']), layout['buf'])

  -- Ensure that buffer is not deleted
  eq(buf_get_option(layout['buf'], 'buflisted'), true)
end

T['unshow_in_window()']['creates a normal buffer'] = function()
  child.cmd('.+,$bwipeout')
  eq(child.lua_get('MiniBufremove.unshow_in_window()'), true)

  -- Verify that created buffer is normal buffer
  local new_buf = child.api.nvim_get_current_buf()
  eq(buf_get_option(new_buf, 'buflisted'), true)
  eq(buf_get_option(new_buf, 'buftype'), '')

  eq(win_get_buf(layout['win_left']), new_buf)
  eq(win_get_buf(layout['win_right']), layout['buf'])

  -- Ensure that buffer is not deleted
  eq(buf_get_option(layout['buf'], 'buflisted'), true)
end

T['unshow_in_window()']['validates arguments'] = function()
  eq(child.lua_get('MiniBufremove.unshow_in_window(100)'), false)
  local last_message = child.cmd_capture('1messages')
  eq(last_message, '(mini.bufremove) 100 is not a valid window id.')
end

T['unshow_in_window()']['respects `win_id` argument'] = function()
  local output = child.lua_get('MiniBufremove.unshow_in_window(...)', { layout['win_left'] })
  eq(output, true)
  eq(win_get_buf(layout['win_left']), layout['buf_left'])
  eq(win_get_buf(layout['win_right']), layout['buf'])
end

T['unshow_in_window()']['closes command-line window'] = function() validate_unshow_cmdwin('unshow_in_window') end

T['unshow_in_window()']['respects `vim.{g,b}.minibufremove_disable`'] = new_set(
  { parametrize = { { 'g' }, { 'b' } } },
  { test = function(var_type) validate_disable(var_type, 'unshow_in_window', layout) end }
)

T['unshow_in_window()']['respects `config.silent`'] = function() validate_silent('unshow_in_window') end

T['delete()'] = new_set()

T['delete()']['uses alternate buffer'] = function()
  validate_unshow_alternate('delete', layout)
  eq(buf_get_option(layout['buf'], 'buflisted'), false)
end

T['delete()']['uses `bprevious`'] = function()
  validate_unshow_bprevious('delete', layout)
  eq(buf_get_option(layout['buf'], 'buflisted'), false)
end

T['delete()']['creates a stand-in listed buffer'] = function()
  validate_unshow_normal_buf('delete', layout)
  eq(buf_get_option(layout['buf'], 'buflisted'), false)
end

T['delete()']['validates arguments'] = function() validate_args_validation('delete', { 'buf_id', 'force' }) end

T['delete()']['closes command-line window'] = function() validate_unshow_cmdwin('delete') end

T['delete()']['respects `buf_id` argument'] = function()
  validate_unshow_with_buf_id('delete', layout)
  eq(buf_get_option(layout['buf'], 'buflisted'), false)
end

T['delete()']['respects `force` argument'] = function() validate_force_argument('delete', layout) end

T['delete()']['respects `vim.{g,b}.minibufremove_disable`'] = new_set(
  { parametrize = { { 'g' }, { 'b' } } },
  { test = function(var_type) validate_disable(var_type, 'delete', layout) end }
)

T['delete()']['respects `config.silent`'] = function() validate_silent('delete') end

T['delete()']["works with different 'bufhidden' options"] = function()
  validate_bufhidden_option('delete', 'delete')
  validate_bufhidden_option('delete', 'wipe')
end

T['wipeout()'] = new_set()

T['wipeout()']['uses alternate buffer'] = function()
  validate_unshow_alternate('wipeout', layout)
  eq(child.api.nvim_buf_is_valid(layout['buf']), false)
end

T['wipeout()']['uses `bprevious`'] = function()
  validate_unshow_bprevious('wipeout', layout)
  eq(child.api.nvim_buf_is_valid(layout['buf']), false)
end

T['wipeout()']['creates a stand-in listed buffer'] = function()
  validate_unshow_normal_buf('wipeout', layout)
  eq(child.api.nvim_buf_is_valid(layout['buf']), false)
end

T['wipeout()']['validates arguments'] = function() validate_args_validation('wipeout', { 'buf_id', 'force' }) end

T['wipeout()']['closes command-line window'] = function() validate_unshow_cmdwin('wipeout') end

T['wipeout()']['respects `buf_id` argument'] = function()
  validate_unshow_with_buf_id('wipeout', layout)
  eq(child.api.nvim_buf_is_valid(layout['buf']), false)
end

T['wipeout()']['respects `force` argument'] = function() validate_force_argument('wipeout', layout) end

T['wipeout()']['respects `vim.{g,b}.minibufremove_disable`'] = new_set(
  { parametrize = { { 'g' }, { 'b' } } },
  { test = function(var_type) validate_disable(var_type, 'wipeout', layout) end }
)

T['wipeout()']['respects `config.silent`'] = function() validate_silent('wipeout') end

T['wipeout()']["works with different 'bufhidden' options"] = function()
  validate_bufhidden_option('wipeout', 'delete')
  validate_bufhidden_option('wipeout', 'wipe')
end

return T
