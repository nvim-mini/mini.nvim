local helpers = dofile('tests/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
local load_module = function(config) child.mini_load('cursorword', config) end
local unload_module = function() child.mini_unload('cursorword') end
local set_cursor = function(...) return child.set_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
local sleep = function(ms) helpers.sleep(ms, child, true) end

-- Make helpers
local word_is_highlighted = function(word)
  local general_n, current_n = 0, 0
  local current_word_pattern = [[\k*\%#\k*]]
  local noncurrent_pattern = string.format([[\(%s\)\@!\&\V\<%s\>]], current_word_pattern, word)

  for _, m in ipairs(child.fn.getmatches()) do
    if m.group == 'MiniCursorword' and m.pattern == noncurrent_pattern and m.priority == -1 then
      general_n = general_n + 1
    end
    if m.group == 'MiniCursorwordCurrent' and m.pattern == current_word_pattern and m.priority == -1 then
      current_n = current_n + 1
    end
  end
  return general_n == 1 and current_n == 1
end

local get_match = function(hl_group)
  return vim.tbl_filter(function(x) return x.group == hl_group end, child.fn.getmatches())
end

-- Data =======================================================================
local example_lines = { 'aa', 'aa', 'aaa' }

-- Time constants
local default_delay = 100
local small_time = helpers.get_time_const(10)

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      load_module()
    end,
    post_once = child.stop,
  },
  n_retry = helpers.get_n_retry(2),
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  -- Global variable
  eq(child.lua_get('type(_G.MiniCursorword)'), 'table')

  -- Autocommand group
  eq(child.fn.exists('#MiniCursorword'), 1)

  -- Highlight groups
  child.cmd('hi clear')
  load_module()
  expect.match(child.cmd_capture('hi MiniCursorword'), 'gui=underline')
  expect.match(child.cmd_capture('hi MiniCursorwordCurrent'), 'links to MiniCursorword')
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniCursorword.config)'), 'table')

  -- Check default values
  eq(child.lua_get('MiniCursorword.config.delay'), 100)
end

T['setup()']['respects `config` argument'] = function()
  unload_module()
  load_module({ delay = 300 })
  eq(child.lua_get('MiniCursorword.config.delay'), 300)
end

T['setup()']['validates `config` argument'] = function()
  unload_module()

  local expect_config_error = function(config, name, target_type)
    expect.error(function() load_module(config) end, vim.pesc(name) .. '.*' .. vim.pesc(target_type))
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ delay = 'a' }, 'delay', 'number')
end

T['setup()']['ensures colors'] = function()
  child.cmd('colorscheme default')
  expect.match(child.cmd_capture('hi MiniCursorword'), 'gui=underline')
  expect.match(child.cmd_capture('hi MiniCursorwordCurrent'), 'links to MiniCursorword')
end

T['setup()']['properly resets module highlighting'] = function()
  child.lua('MiniCursorword.config.delay = 0')
  set_lines({ 'aa a aaa aa a aaa', 'a aa aaa a aa aaa' })
  set_cursor(1, 0)
  eq(#child.fn.getmatches(), 2)

  child.lua([[package.loaded['mini.cursorword'] = nil]])
  load_module({ delay = 0 })
  eq(#child.fn.getmatches(), 0)
  set_cursor(2, 0)
  eq(#child.fn.getmatches(), 2)
end

-- Integration tests ==========================================================
T['Highlighting'] = new_set({
  hooks = {
    pre_case = function()
      child.set_size(5, 12)
      child.lua('MiniCursorword.config.delay = 0')
      set_lines({ 'a aa aaa', 'aa aaa a', 'aaa a aa' })
      set_cursor(1, 0)
    end,
  },
})

T['Highlighting']['works'] = function() child.expect_screenshot() end

T['Highlighting']['works on multibyte character'] = function()
  set_lines({ 'ы ыы ыыы', 'ыы ыыы ы', 'ыыы ы ыы' })
  set_cursor(1, 0)
  child.expect_screenshot()

  set_lines({ '  ', '  ', '  ' })
  set_cursor(1, 0)
  child.expect_screenshot()
end

T['Highlighting']['respects MiniCursorwordCurrent highlight group'] = function()
  child.cmd('hi! MiniCursorwordCurrent gui=nocombine guifg=NONE guibg=NONE')
  child.expect_screenshot()
end

T['Highlighting']['works with multiple windows'] = function()
  child.set_size(5, 40)
  child.cmd('vsplit | wincmd =')
  set_cursor(2, 0)
  child.expect_screenshot()
end

T['Highlighting']['can stop'] = function()
  child.set_size(5, 15)
  type_keys('i')
  child.expect_screenshot()
end

T['Autohighlighting'] = new_set({
  hooks = {
    pre_case = function() set_lines(example_lines) end,
  },
})

local validate_cursorword = function(delay)
  set_cursor(2, 0)
  eq(word_is_highlighted('aa'), false)
  sleep(delay - small_time)
  eq(word_is_highlighted('aa'), false)
  sleep(small_time)
  eq(word_is_highlighted('aa'), true)
end

T['Autohighlighting']['works'] = function() validate_cursorword(default_delay) end

T['Autohighlighting']['respects `config.delay`'] = function()
  child.lua('MiniCursorword.config.delay = ' .. (3 * default_delay))
  validate_cursorword(3 * default_delay)

  -- Should also use buffer local config
  set_cursor(3, 0)
  child.b.minicursorword_config = { delay = default_delay }
  validate_cursorword(default_delay)
end

T['Autohighlighting']['removes highlight immediately after move'] = function()
  set_cursor(2, 0)
  sleep(default_delay)
  eq(word_is_highlighted('aa'), true)
  set_cursor(3, 0)
  eq(child.fn.getmatches(), {})
end

local validate_immediate = function(move_command)
  set_cursor(2, 0)
  sleep(default_delay)
  eq(word_is_highlighted('aa'), true)

  local match_gen = get_match('MiniCursorword')
  child.cmd(move_command)
  child.poke_eventloop()
  eq(word_is_highlighted('aa'), true)

  -- Check that general match group didn't change (as word is same)
  eq(match_gen, get_match('MiniCursorword'))
end

T['Autohighlighting']['highlights immediately inside current word'] = function() validate_immediate('normal! l') end

T['Autohighlighting']['highlights immediately same word in other place'] = function() validate_immediate('normal! k') end

T['Autohighlighting']['highlights only "keyword" symbols'] = function()
  local validate_highlighted = function(cursor_pos, hl_word)
    set_cursor(unpack(cursor_pos))
    if hl_word == nil then
      eq(child.fn.getmatches(), {})
    else
      eq(word_is_highlighted(hl_word), true)
    end
  end

  child.lua('MiniCursorword.config.delay = 0')
  set_lines({ 'a_111', '  ', 'aa bb', 'aa.bb', '!!!' })

  validate_highlighted({ 1, 1 }, 'a_111')
  validate_highlighted({ 1, 2 }, 'a_111')
  validate_highlighted({ 2, 0 }, nil)
  validate_highlighted({ 3, 1 }, 'aa')
  validate_highlighted({ 3, 2 }, nil)
  validate_highlighted({ 4, 0 }, 'aa')
  validate_highlighted({ 4, 2 }, nil)
  validate_highlighted({ 4, 3 }, 'bb')
  validate_highlighted({ 5, 0 }, nil)
end

T['Autohighlighting']['stops in Insert mode'] = function()
  set_cursor(2, 0)
  sleep(default_delay)
  eq(word_is_highlighted('aa'), true)
  type_keys('i')
  eq(word_is_highlighted('aa'), false)
end

T['Autohighlighting']['stops in Terminal mode'] = function()
  set_cursor(2, 0)
  sleep(default_delay)
  eq(word_is_highlighted('aa'), true)
  child.cmd('doautocmd TermEnter')
  eq(word_is_highlighted('aa'), false)
end

T['Autohighlighting']['respects ModeChanged'] = function()
  -- Add disabling in Visual mode
  unload_module()
  child.cmd([[
      augroup VisualDisable
        au!
        au ModeChanged *:[vV\x16]* lua vim.b.minicursorword_disable = true
        au ModeChanged [vV\x16]*:* lua vim.b.minicursorword_disable = false
      augroup END
    ]])
  child.lua([[require('mini.cursorword').setup({ delay = 0 })]])

  set_cursor(2, 0)
  eq(word_is_highlighted('aa'), true)

  type_keys('v')
  eq(word_is_highlighted('aa'), false)

  type_keys('v')
  eq(word_is_highlighted('aa'), true)
end

T['Autohighlighting']['respects `vim.{g,b}.minicursorword_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    set_cursor(1, 1)

    child[var_type].minicursorword_disable = true
    set_cursor(1, 0)
    sleep(default_delay)
    eq(word_is_highlighted('aa'), false)

    child[var_type].minicursorword_disable = false
    set_cursor(1, 1)
    sleep(default_delay)
    eq(word_is_highlighted('aa'), true)
  end,
})

T['Autohighlighting']['respects deferred `vim.{g,b}.minicursorword_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    set_cursor(1, 1)

    local lua_cmd = string.format(
      'vim.defer_fn(function() vim.%s.minicursorword_disable = true end, %d)',
      var_type,
      math.floor(0.5 * default_delay)
    )
    child.lua(lua_cmd)
    set_cursor(1, 0)

    sleep(default_delay)
    eq(word_is_highlighted('aa'), false)
  end,
})

return T
