local helpers = dofile('tests/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('cmdline', config) end
local unload_module = function(config) child.mini_unload('cmdline', config) end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
local sleep = function(ms) helpers.sleep(ms, child) end
--stylua: ignore end

local test_dir = 'tests/dir-cmdline'

-- Common test wrappers
local forward_lua = function(fun_str)
  local lua_cmd = fun_str .. '(...)'
  return function(...) return child.lua_get(lua_cmd, { ... }) end
end

local validate_cmdline = function(line, pos)
  eq(child.fn.mode(), 'c')
  eq(child.fn.getcmdline(), line)
  eq(child.fn.getcmdpos(), pos or line:len() + 1)
end

local expect_screenshot_after_keys = function(keys)
  type_keys(keys)
  child.expect_screenshot()
end

-- Data =======================================================================
local lines_101 = {}
for i = 1, 101 do
  lines_101[i] = 'Line ' .. i
end

-- Time constants
local small_time = helpers.get_time_const(10)

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = function()
      -- Use `--noplugin` flag for easier testing without built-in plugins
      child.restart({ '--noplugin', '-u', 'scripts/minimal_init.lua' })
      child.bo.readonly = false
    end,
    post_once = child.stop,
    n_retry = helpers.get_n_retry(2),
  },
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  load_module()

  -- Global variable
  eq(child.lua_get('type(_G.MiniCmdline)'), 'table')

  -- Autocommand group
  eq(child.fn.exists('#MiniCmdline'), 1)

  -- Highlight groups
  child.cmd('hi clear')
  load_module()
  local has_highlight = function(group, value) expect.match(child.cmd_capture('hi ' .. group), value) end

  has_highlight('MiniCmdlinePeekBorder', 'links to FloatBorder')
  has_highlight('MiniCmdlinePeekLineNr', 'links to DiagnosticSignWarn')
  has_highlight('MiniCmdlinePeekNormal', 'links to NormalFloat')
  has_highlight('MiniCmdlinePeekSign', 'links to DiagnosticSignHint')
  has_highlight('MiniCmdlinePeekSep', 'links to SignColumn')
  has_highlight('MiniCmdlinePeekTitle', 'links to FloatTitle')
end

T['setup()']['creates `config` field'] = function()
  load_module()
  eq(child.lua_get('type(_G.MiniCmdline.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniCmdline.config.' .. field), value) end

  expect_config('autocomplete.enable', true)
  expect_config('autocomplete.delay', 0)
  expect_config('autocomplete.predicate', vim.NIL)
  expect_config('autocomplete.map_arrows', true)
  expect_config('autocorrect.enable', true)
  expect_config('autocorrect.func', vim.NIL)
  expect_config('autopeek.enable', true)
  expect_config('autopeek.n_context', 1)
  expect_config('autopeek.window.config', {})
  expect_config('autopeek.window.statuscolumn', vim.NIL)
end

T['setup()']['validates `config` argument'] = function()
  local expect_config_error = function(config, name, target_type)
    expect.error(load_module, vim.pesc(name) .. '.*' .. vim.pesc(target_type), config)
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ autocomplete = 1 }, 'autocomplete', 'table')
  expect_config_error({ autocomplete = { enable = 1 } }, 'autocomplete.enable', 'boolean')
  expect_config_error({ autocomplete = { predicate = 1 } }, 'autocomplete.predicate', 'function')
  expect_config_error({ autocomplete = { map_arrows = 1 } }, 'autocomplete.map_arrows', 'boolean')
  expect_config_error({ autocorrect = 1 }, 'autocorrect', 'table')
  expect_config_error({ autocorrect = { enable = 1 } }, 'autocorrect.enable', 'boolean')
  expect_config_error({ autocorrect = { func = 1 } }, 'autocorrect.func', 'function')
  expect_config_error({ autopeek = 1 }, 'autopeek', 'table')
  expect_config_error({ autopeek = { enable = 1 } }, 'autopeek.enable', 'boolean')
  expect_config_error({ autopeek = { window = 1 } }, 'autopeek.window', 'table')
  expect_config_error({ autopeek = { n_context = 'a' } }, 'autopeek.n_context', 'number')
  expect_config_error({ autopeek = { window = { config = 1 } } }, 'autopeek.window.config', 'table or callab')
  expect_config_error({ autopeek = { window = { statuscolumn = 1 } } }, 'autopeek.window.statuscolumn', 'callable')
end

T['setup()']['ensures colors'] = function()
  load_module()
  child.cmd('colorscheme default')
  expect.match(child.cmd_capture('hi MiniCmdlinePeekBorder'), 'links to FloatBorder')
end

T['setup()']['sets recommended option values'] = function()
  local check_wildmode = child.fn.has('nvim-0.11') == 1
  load_module()
  eq(child.o.wildoptions, 'pum,fuzzy')
  if check_wildmode then eq(child.o.wildmode, 'noselect,full') end

  -- Should not set if was previously set
  child.o.wildoptions = 'pum'
  if check_wildmode then child.o.wildmode = 'full' end
  load_module()
  eq(child.o.wildoptions, 'pum')
  if check_wildmode then eq(child.o.wildmode, 'full') end

  -- Should only set 'wildmode' if autocomplete is enabled
  if check_wildmode then
    child.restart({ '--noplugin', '-u', 'scripts/minimal_init.lua' })
    load_module({ autocomplete = { enable = false } })
    eq(child.o.wildmode, 'full')
  end
end

T['default_autocomplete_predicate()'] = new_set()

local default_autocomplete_predicate = forward_lua('MiniCmdline.default_autocomplete_predicate')

T['default_autocomplete_predicate()']['works'] = function()
  load_module({ autocorrect = { enable = false }, autopeek = { enable = false } })

  local line, pos, line_prev, pos_prev = '', 1, '', 1
  eq(default_autocomplete_predicate({ line = line, pos = pos, line_prev = line_prev, pos_prev = pos_prev }), false)

  type_keys(':')

  local validate = function(key, ref)
    type_keys(key)
    line_prev, pos_prev = line, pos
    line, pos = child.fn.getcmdline(), child.fn.getcmdpos()
    eq(default_autocomplete_predicate({ line = line, pos = pos, line_prev = line_prev, pos_prev = pos_prev }), ref)
  end

  -- Should return `true` only if there is alphabetic character
  validate('1', false)
  validate(',', false)
  validate('2', false)
  validate(' ', false)
  validate('h', true)
  validate(' ', true)
  validate("'", true)
  type_keys('<Esc>')

  line, pos, line_prev, pos_prev = '', 1, '', 1
  type_keys(':')
  validate(' ', false)
  validate('h', true)
  validate(' ', true)
  validate("'", true)
  type_keys('<Esc>')
end

T['default_autocorrect_func()'] = new_set({ hooks = { pre_case = load_module } })

local default_autocorrect_func = forward_lua('MiniCmdline.default_autocorrect_func')

T['default_autocorrect_func()']['works'] = function()
  -- Most of the testing is done in 'Autocorrect' test case
  local validate = function(data, ref) eq(default_autocorrect_func(data), ref) end

  -- General
  validate({ word = 'ste', type = 'command' }, 'set')
  validate({ word = 'set', type = 'command' }, 'set')

  -- Strict type
  validate({ word = 'rndomhue', type = 'color' }, 'randomhue')

  -- Not strict type
  validate({ word = 'MniCmdline', type = 'augroup' }, 'MniCmdline')

  -- Empty string
  validate({ word = 'xxx', type = '' }, 'xxx')
  validate({ word = '', type = 'command' }, '')
  validate({ word = '', type = '' }, '')
end

T['default_autocorrect_func()']['respects `opts.strict_type`'] = function()
  local validate = function(data, ref) eq(default_autocorrect_func(data, { strict_type = false }), ref) end
  validate({ word = 'MniCmdline', type = 'augroup' }, 'MiniCmdline')
  validate({ word = 'Nrmal', type = 'highlight' }, 'Normal')
end

T['default_autocorrect_func()']['respects `opts.get_candidates`'] = function()
  local out = child.lua([[
    _G.log = {}
    local get_cand = function(...) table.insert(_G.log, { ... }); return { 'xxx' } end
    return MiniCmdline.default_autocorrect_func({ word = 'ste', type = 'color' }, { get_candidates = get_cand })
  ]])
  eq(out, 'xxx')
  eq(child.lua_get('_G.log'), { { { type = 'color', word = 'ste' } } })
end

T['default_autocorrect_func()']['validates arguments'] = function()
  expect.error(function() default_autocorrect_func(1) end, '`data`.*table')
  expect.error(function() default_autocorrect_func({ word = 1, type = 'command' }) end, '`data.word`.*string')
  expect.error(function() default_autocorrect_func({ word = 'ste', type = 1 }) end, '`data.type`.*string')
end

T['default_autopeek_statuscolumn()'] = new_set({
  hooks = {
    pre_case = function()
      child.set_size(7, 15)
      set_lines(lines_101)

      load_module()

      child.o.showtabline, child.o.laststatus = 0, 0
      child.o.ruler = false
    end,
  },
})

local setup_statuscolumn = function(data, opts)
  child.lua('_G.data = ' .. vim.inspect(data))
  child.lua('_G.opts = ' .. vim.inspect(opts))
  child.lua([[
    _G.test_statuscolumn = function()
      _G.res = MiniCmdline.default_autopeek_statuscolumn(_G.data, _G.opts)
      return _G.res
    end
    vim.wo.statuscolumn = '%{%v:lua.test_statuscolumn()%}'
    vim.cmd('redraw')
  ]])

  -- Ensure more informative screenshots
  child.cmd('hi MiniCmdlinePeekLineNr guibg=Red ctermbg=Red')
  child.cmd('hi MiniCmdlinePeekSign guibg=Green ctermbg=Green')
  child.cmd('hi MiniCmdlinePeekSep guibg=Yellow ctermbg=Yellow')
end

local validate_statuscolumn = function(data, opts)
  setup_statuscolumn(data, opts)
  local last_line = child.o.lines
  child.expect_screenshot({ ignore_text = { last_line }, ignore_attr = { last_line } })
end

T['default_autopeek_statuscolumn()']['works'] = function()
  -- Different type of ranges
  validate_statuscolumn({ left = 2, right = 5 })
  validate_statuscolumn({ left = 4, right = 5 })
  validate_statuscolumn({ left = 4, right = 4 })
  validate_statuscolumn({ left = 5, right = 4 })
  validate_statuscolumn({ left = 5, right = 2 })

  -- Actually uses expected highlight groups
  local ref_pat = '^%%#MiniCmdlinePeekSign#.*%%#MiniCmdlinePeekLineNr#.*%%#MiniCmdlinePeekSep#│$'
  expect.match(child.lua_get('_G.res'), ref_pat)

  -- Line numbers should be aligned to the right, but their highlighting should
  -- start right after the sign (matters if different background).
  set_cursor(7, 0)
  child.cmd('normal! zt')
  validate_statuscolumn({ left = 8, right = 10 })
end

T['default_autopeek_statuscolumn()']['works with wrapped and virtual lines'] = function()
  child.set_size(10, 15)
  set_lines({ '', 'Very big line number one', 'Very big line number two', '' })
  local ns_id = child.api.nvim_create_namespace('Test')
  child.api.nvim_buf_set_extmark(0, ns_id, 1, 0, { virt_lines = { { { 'Virt' } } } })
  child.api.nvim_buf_set_extmark(0, ns_id, 3, 0, { virt_lines = { { { 'Virt above' } } }, virt_lines_above = true })

  validate_statuscolumn({ left = 2, right = 3 })
end

T['default_autopeek_statuscolumn()']['respects `opts`'] = function()
  local opts = {
    signs = { same = '=', left = '<', mid = '-', right = '>', out = '*', virt = '$', wrap = '!' },
    sep = '#',
  }
  -- All usages of `%` should be escaped as `%%`
  local opts_percent = {
    signs = { same = '%%', left = '%%', mid = '%%', right = '%%', out = '%%', virt = '%%', wrap = '%%' },
    sep = '%%',
  }

  validate_statuscolumn({ left = 2, right = 5 }, opts)
  validate_statuscolumn({ left = 2, right = 5 }, opts_percent)

  set_lines({ '', 'Very big line number one', 'Very big line number two', '' })
  local ns_id = child.api.nvim_create_namespace('Test')
  child.api.nvim_buf_set_extmark(0, ns_id, 1, 0, { virt_lines = { { { 'Virt' } } } })
  validate_statuscolumn({ left = 2, right = 2 }, opts)
  validate_statuscolumn({ left = 2, right = 2 }, opts_percent)
end

-- Integration tests ==========================================================
T['Autocomplete'] = new_set({
  hooks = {
    pre_case = function()
      if child.fn.has('nvim-0.11') == 0 then MiniTest.skip('Autocompletion is available only on Neovim>=0.11') end

      load_module({ autocorrect = { enable = false }, autopeek = { enable = false } })
      child.set_size(10, 20)
      child.o.pumheight, child.o.pumwidth = 5, 16
      child.o.showtabline, child.o.laststatus = 0, 0
    end,
  },
})

local has_pum = function() return child.fn.wildmenumode() == 1 end

T['Autocomplete']['works'] = function()
  type_keys(':')

  -- Should be no completion at the start
  child.expect_screenshot()

  -- Should trigger after the first character
  expect_screenshot_after_keys('b')

  -- Should respect `wildmenu=pum,fuzzy`, which is set by default
  expect_screenshot_after_keys('f')

  -- Should react to text deletion
  expect_screenshot_after_keys('<BS>')
  expect_screenshot_after_keys('<C-u>')
end

T['Autocomplete']["works with different 'wildchar'"] = function()
  child.cmd('set wildchar=<Down>')
  type_keys(':', 'b')
  eq(has_pum(), true)
  validate_cmdline('b')
end

T['Autocomplete']['works with different completion types'] = function()
  child.set_size(10, 30)
  child.fn.chdir(test_dir)
  child.o.wildoptions = 'pum'

  type_keys(':', 'set ig')
  child.expect_screenshot()
  type_keys('<Esc>')

  type_keys(':', 'edit ', 'f')
  child.expect_screenshot()
  type_keys('<Esc>')

  type_keys(':', 'grep ', 'f')
  child.expect_screenshot()
  type_keys('<Esc>')
end

T['Autocomplete']['respects mappings'] = function()
  -- Should not work if Command-line mode is both entered and exited
  child.cmd('nnoremap <C-x> :sort<CR>')
  type_keys('<C-x>')
  eq(has_pum(), false)
  eq(get_lines(), { '' })
end

T['Autocomplete']['works in edge cases'] = function()
  -- After "!"
  type_keys(':', 'q', '!')
  validate_cmdline('q!')
  eq(has_pum(), false)
  type_keys('<Esc>')

  -- With special commands
  local validate_special_cmd = function(key)
    set_lines({ 'Line 1', 'Line 2' })
    type_keys(':', key)
    child.api.nvim_input('/')
    child.api.nvim_input('L')
    -- Completion in thiese special cases is available only on Neovim>=0.12
    if child.fn.has('nvim-0.12') == 1 then
      child.expect_screenshot()
    else
      eq(has_pum(), false)
    end
    type_keys('<Esc>')
  end

  -- :substitute
  validate_special_cmd('s')
  -- :global
  validate_special_cmd('g')
  -- :vimgrep
  validate_special_cmd('v')
end

T['Autocomplete']['does not throw completion related errors'] = function()
  type_keys(':tag')
  -- NOTE: Use `nvim_input` instead of `type_keys()` because the latter checks
  -- `v:errmsg` to propagate the error. However, here on Neovim>=0.12 usage of
  -- `vim.fn.wildtrigger()` *does* set `errmsg` but no error is actuall shown.
  child.api.nvim_input(' ')
  -- What actually should be tested is that there is no errors *shown*, but it
  -- doesn't look easy, as behavior in child process and manual testing differ.
  eq(child.cmd('messages'), '')
  expect.no_match(child.v.errmsg, 'cmdline%.lua')
end

T['Autocomplete']['is not triggered when wildmenu is visible'] = function()
  type_keys(':', 'b')
  eq(has_pum(), true)
  expect_screenshot_after_keys('<Tab>')
  type_keys('<Esc>')

  -- In combination with autocorrection
  child.lua('MiniCmdline.config.autocorrect.enable = true')
  child.fn.chdir(test_dir)
  child.cmd('argadd fileA fileB')
  type_keys(':', 'argdel fla', ' ')
  validate_cmdline('argdel fileA ')
  eq(has_pum(), true)
end

T['Autocomplete']['works in different command types'] = function()
  set_lines({ 'aa', 'aaa', 'aaaa' })

  local validate = function(keys)
    eq(child.fn.mode(), 'n')
    type_keys(keys)
    if child.fn.has('nvim-0.12') == 1 then
      child.expect_screenshot()
    else
      eq(has_pum(), false)
    end
    type_keys('<Esc>', '<Esc>')
  end

  -- `/` and `?` can complete on Neovim>=0.12
  validate({ '/', 'a' })
  validate({ '?', 'a' })

  -- Others command types - no completion
  validate({ 'i', '<C-r>=', 'a' })
  validate({ ':call input("")<CR>', 'a' })
end

T['Autocomplete']['works with default predicate'] = function()
  type_keys(':', '1')
  eq(has_pum(), false)

  type_keys('s')
  eq(has_pum(), true)

  type_keys('<BS>')
  eq(has_pum(), false)
end

T['Autocomplete']['respects `config.autocomplete.delay`'] = function()
  local delay = 5 * small_time
  child.lua('MiniCmdline.config.autocomplete.delay = ' .. delay)

  type_keys(':', 'b')
  eq(has_pum(), false)
  sleep(delay - small_time)
  eq(has_pum(), false)

  -- Should implement debounce-style delay
  type_keys('u')
  sleep(delay - small_time)
  eq(has_pum(), false)
  sleep(2 * small_time)
  eq(has_pum(), true)

  -- Should work when pum is visible
  type_keys('f')
  sleep(delay - small_time)
  -- NOTE: Although no pum is present, on Neovim>=0.12 it is still drawn since
  -- that is how `wildtrigger()` works. This results in less flickering.
  eq(has_pum(), false)
  sleep(2 * small_time)
  eq(has_pum(), true)

  -- Should work when deleting text
  type_keys('<BS>')
  sleep(delay - small_time)
  eq(has_pum(), false)
  sleep(2 * small_time)
  eq(has_pum(), true)
end

T['Autocomplete']['should be triggered only during Command-line mode'] = function()
  local delay = 5 * small_time
  child.lua('MiniCmdline.config.autocomplete.delay = ' .. delay)

  set_lines({ 'Line 1', 'Line 2' })
  set_cursor(1, 0)
  child.cmd('set wildchar=<Down>')

  type_keys(':', 'b')
  sleep(small_time)
  type_keys('<Esc>')
  sleep(delay + small_time)

  eq(get_lines(), { 'Line 1', 'Line 2' })
  eq(get_cursor(), { 1, 0 })
end

T['Autocomplete']['respects `config.autocomplete.predicate`'] = function()
  child.lua([[
    _G.res = true
    _G.predicate_log = {}
    MiniCmdline.config.autocomplete.predicate = function(...)
      table.insert(_G.predicate_log, { ... })
      return _G.res
    end
  ]])

  local validate_log = function(ref)
    eq(child.lua_get('_G.predicate_log'), ref)
    child.lua('_G.predicate_log = {}')
  end

  local has_012 = child.fn.has('nvim-0.12') == 1

  -- Should be called with proper data
  type_keys(':')
  eq(has_pum(), false)
  validate_log({})

  type_keys('1')
  validate_log({ { { line = '1', pos = 2, line_prev = '', pos_prev = 1 } } })
  eq(has_pum(), not has_012)

  type_keys('s')
  validate_log({ { { line = '1s', pos = 3, line_prev = '1', pos_prev = 2 } } })
  eq(has_pum(), true)

  type_keys('<C-u>')
  validate_log({ { { line = '', pos = 1, line_prev = '1s', pos_prev = 3 } } })
  eq(has_pum(), not has_012)
  type_keys('<Esc>')

  -- Should not show if `false`
  child.lua('_G.res = false')
  type_keys(':')
  type_keys('s')
  eq(has_pum(), false)
end

T['Autocomplete']['respects `vim.{g,b}.minicmdline_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minicmdline_disable = true
    type_keys(':', 'b')
    eq(has_pum(), false)
    type_keys('<Esc>')

    child[var_type].minicmdline_disable = false
    type_keys(':', 'b')
    eq(has_pum(), true)
  end,
})

T['Autocorrect'] = new_set({
  hooks = {
    pre_case = function() load_module({ autocomplete = { enable = false }, autopeek = { enable = false } }) end,
  },
})

T['Autocorrect']['works for commands'] = function()
  local validate = function(bad_word, ref_word)
    type_keys(':', bad_word, ' ')
    validate_cmdline(ref_word .. ' ')
    type_keys('<Esc>')
  end

  child.cmd('command MyCommand echo "Hello"')
  child.cmd('command Git echo "World"')

  -- Should correct for common edit types
  validate('bbuffer', 'buffer') -- Deletion
  validate('uffer', 'buffer') -- Insertion
  validate('xuffer', 'buffer') -- Substitution
  validate('ste', 'set') -- Transposition

  -- Should respect abbreviations, even for user commands
  validate('nmor', 'nnor')
  validate('nmore', 'nnore')

  validate('MxC', 'MyC')

  validate('W', 'w')
  validate('Q', 'q')

  -- Should respect "ignore case" matches
  validate('WrItE', 'write')
  validate('W', 'w')
  validate('NNO', 'nno')

  validate('myc', 'MyC')

  -- Should prefer "respect case" abbreviation over "ignore case"
  validate('%g', '%g')

  -- Should prefer transposition
  validate('ua', 'au')

  -- Should work with bang
  type_keys(':', 'Q', '!')
  validate_cmdline('q!')
  type_keys('<Esc>')

  -- Should work with range
  type_keys(':', "'a")
  validate_cmdline("'a")
  type_keys(',')
  validate_cmdline("'a,")
  type_keys("'b")
  validate_cmdline("'a,'b")
  type_keys('<Esc>')

  -- Should work with command modifiers
  validate('abvelfet', 'aboveleft')

  -- Should not correct `:=` command
  -- validate('=123', '=123')
  validate('=_G', '=_G')
end

T['Autocorrect']['works for options'] = function()
  local validate_option = function(input, ref)
    -- In progress
    type_keys(':', input, ' ')
    validate_cmdline(ref .. ' ')
    type_keys('<Esc>')

    -- Final
    type_keys(':', input, '<CR>')
    eq(child.fn.histget('cmd', -1), ref)
  end

  -- NOTE: Need to emulate `n-o-...` and `i-n-v-...` as separate keys as these
  -- case detection relies on user interactively typing keys
  validate_option('set expndtb', 'set expandtab')
  validate_option({ 'set ', 'n', 'o', 'expndtb' }, 'set noexpandtab')
  validate_option({ 'set ', 'i', 'n', 'v', 'expndtb' }, 'set invexpandtab')
  validate_option('set ET', 'set et')
  validate_option({ 'set ', 'n', 'o', 'ET' }, 'set noet')
  validate_option({ 'set ', 'i', 'n', 'v', 'ET' }, 'set invet')

  validate_option('setlocal expndtb', 'setlocal expandtab')

  -- Should work multiple times
  type_keys(':', 'set ET', ' ', 'inorecase', ' ', 'nowrp', ' ', 'invmgic', ' ')
  validate_cmdline('set et ignorecase nowrap invmagic ')
  type_keys('<Esc>')

  -- Correction when option is followed by not space
  local validate_option_char = function(char)
    -- Similarly to `n-o-...` case, need to emulate key before tested character
    type_keys(':', 'set lstchar', 's', char)
    validate_cmdline('set listchars' .. char)
    type_keys('<Esc>')

    type_keys(':', 'set LC', 'S', char)
    validate_cmdline('set lcs' .. char)
    type_keys('<Esc>')
  end

  validate_option_char('=')
  validate_option_char('?')
  validate_option_char('!')
  validate_option_char('&')
  validate_option_char('^')
  validate_option_char('+')
  validate_option_char('-')
end

T['Autocorrect']['works for other types'] = function()
  local validate_inprogress = function(input, ref)
    type_keys(':', input, ' ')
    validate_cmdline(ref .. ' ')
    type_keys('<Esc>')
  end
  local validate_final = function(input, ref)
    type_keys(':', input, '<CR>')
    eq(child.fn.histget('cmd', -1), ref)
  end

  child.fn.chdir(test_dir)
  child.cmd([[let &runtimepath.=','.getcwd()]])
  child.cmd([[let &packpath.=','.getcwd()]])

  -- arglist
  child.cmd('argadd fileA fileB')
  validate_inprogress('argdel fla', 'argdel fileA')
  validate_final('argdel flb', 'argdel fileB')

  -- buffer
  child.cmd('edit fileA')
  child.cmd('edit fileB')
  -- - No in-progress check since `:buffer` expects single argument
  validate_final('buffer flB', 'buffer fileB')

  -- color
  -- - No in-progress check since `:colorscheme` expects single argument
  validate_final('colorscheme dfault', 'colorscheme default')

  -- compiler
  -- - No in-progress check since `:compiler` expects single argument
  validate_final('compiler tstcompiler', 'compiler testcompiler')

  -- diff_buffer
  child.cmd('edit fileA')
  child.cmd('diffsplit fileB')
  -- - No in-progress check since `:diffput` expects single argument
  validate_final('diffput flA', 'diffput fileA')

  child.cmd('%bwipeout')
  child.cmd('only')

  -- event
  validate_inprogress('au Cmdlinelve', 'au CmdlineLeave')
  validate_final('au BfEnter', 'au BufEnter')
  type_keys('<C-c>')

  -- filetype
  -- - No in-progress check since `:setfiletype` expects single argument
  validate_final('setfiletype pthon', 'setfiletype python')

  -- history
  -- - No in-progress check since `:history` expects single argument
  validate_final('history srch', 'history search')

  -- keymap
  -- Neovim<0.10 has no 'keymap' `:h :command-complete` value
  if child.fn.has('nvim-0.10') == 1 then
    validate_inprogress('set keymap=tstkeymap', 'set keymap=testkeymap')
    validate_final('set keymap=tstkeymap', 'set keymap=testkeymap')
  end

  -- locale
  -- - No in-progress check since `:language time` expects single argument
  -- No easy way to test locales on non-Linux
  if child.fn.has('linux') == 1 then validate_final('language time PSX', 'language time POSIX') end

  -- mapclear
  -- Neovim<0.11 has wrong `complpat` computation in this case
  if child.fn.has('nvim-0.11') == 1 then
    -- - No in-progress check since `:mapclear` expects single argument
    validate_final({ 'mapclear ', '<', 'bfr', '>' }, 'mapclear <buffer>')
  end

  -- messages
  -- - No in-progress check since `:messages` expects single argument
  validate_final('messages clr', 'messages clear')

  -- packadd
  -- - No in-progress check since `:packadd` expects single argument
  validate_final('packadd tstplugin', 'packadd testplugin')

  -- sign
  validate_inprogress('sign dfine', 'sign define')
  validate_final('sign lst', 'sign list')

  -- syntax
  -- Neovim<0.10 does not set `compltype=syntax` in this case
  if child.fn.has('nvim-0.10') == 1 then
    validate_inprogress('set syntax=LUA', 'set syntax=lua')
    validate_final('set syntax=LUA', 'set syntax=lua')
  end

  -- syntime
  -- - No in-progress check since `:syntime` expects single argument
  validate_final('syntime clr', 'syntime clear')
end

T['Autocorrect']['works multiple times'] = function()
  type_keys(':', 'srot', ' ')
  validate_cmdline('sort ')

  -- After delete
  type_keys('<C-u>', 'abvoelfet', ' ')
  validate_cmdline('aboveleft ')

  -- After another typed autocorrection
  type_keys('noutocmd', ' ')
  validate_cmdline('aboveleft noautocmd ')

  type_keys('sort', ' ')
  validate_cmdline('aboveleft noautocmd sort ')
end

T['Autocorrect']['works only in `:` command type'] = function()
  local validate = function(keys, ref)
    eq(child.fn.mode(), 'n')
    type_keys(keys)
    validate_cmdline(ref)
    type_keys('<Esc>', '<Esc>')
  end
  validate({ '/', 'srot', ' ' }, 'srot ')
  validate({ '?', 'srot', ' ' }, 'srot ')
  validate({ 'i', '<C-r>=', 'srot ' }, 'srot ')
end

T['Autocorrect']['respects mappings'] = function()
  -- Should not work if Command-line mode is both entered and exited
  child.cmd('nnoremap <C-x> :ehco<CR>')
  local ok, err = pcall(type_keys, '<C-x>')
  eq(ok, false)
  eq(err, 'E492: Not an editor command: ehco')

  -- Should work if Command-line mode is only entered
  child.cmd('nnoremap <C-y> :ehco')
  type_keys('<C-y>', '<CR>')
  eq(child.fn.histget('cmd', -1), 'echo')
end

T['Autocorrect']['can act after mappings appended text'] = function()
  -- Should act if text increases latest word
  child.cmd('cnoremap <C-x> www')
  type_keys(':', 'XX', '<C-x>')
  validate_cmdline('XXwww')
  type_keys(' ')
  validate_cmdline('below ')
  type_keys('<Esc>')

  -- Should act if text finishes the last word.
  child.cmd('cnoremap <C-y> www<Space>')
  type_keys(':', 'XX', '<C-y>')
  -- Whole new text from the mapping is treated as "separator text" and is not
  -- included into autocorrected word. It might be good to have the new text
  -- also be part of the word to correct (`XXwww` here instead of `XX`), but it
  -- seems too complex to implement (if reasonably possible even).
  validate_cmdline('exwww ')
  type_keys('<Esc>')
end

T['Autocorrect']['ignores editing previous text'] = function()
  type_keys(':', 'set ', '<Left>')
  type_keys('<BS>')
  validate_cmdline('se ', 3)
  type_keys('T')
  validate_cmdline('seT ', 4)
  type_keys(' ')
  validate_cmdline('seT  ', 5)
  type_keys('<Esc>')

  -- Appending after editing
  MiniTest.skip('Make it work or declare out of scope. Problematic because complpat and pos_prev are not relevant')
  type_keys(':', 'rot', '<Home>', 's', '<End>', ' ')
  validate_cmdline('sort ')
end

T['Autocorrect']['correctly computes word to autocorrect'] = function()
  if child.fn.has('nvim-0.11') == 0 then MiniTest.skip('Requires `getcmdcomplpat()`, present in Neovim>=0.11') end

  local validate = function(text, final_key, ref)
    type_keys(':', text, final_key)
    validate_cmdline(ref)
    type_keys('<Esc>')
  end

  validate("'a,'bsrot", ' ', "'a,'bsort ")
  validate("'a,'bsrot", '!', "'a,'bsort!")
  validate("'a,''srot", ' ', "'a,''sort ")
end

T['Autocorrect']['does not correct valid words'] = function()
  child.cmd('au CmdlineChanged * lua _G.n = (_G.n or 0) + 1')

  local validate = function(word)
    type_keys(':', word)
    child.lua('_G.n = 0')
    type_keys(' ')
    validate_cmdline(word .. ' ')
    eq(child.lua_get('_G.n'), 1)

    type_keys('<Esc>')
  end

  validate('cnoremap')
  validate('cnor')

  child.cmd('command MyCommand echo "Hello"')
  validate('MyCommand')
  validate('MyC')

  child.cmd('vsplit')
  local win_id = child.api.nvim_get_current_win()
  type_keys(':', 'q', '!', '<CR>')
  eq(child.api.nvim_win_is_valid(win_id), false)
end

T['Autocorrect']['suggests only valid abbreviations'] = function()
  -- Should uniquely identify user commands
  child.cmd('command MyCommandA echo "Hello"')
  child.cmd('command MyCommandB echo "World"')

  type_keys(':', 'MyComman', ' ')
  validate_cmdline('MyCommandA ')
  type_keys('<Esc>')

  -- `:def` is not a valid abbreviation
  type_keys(':', 'def', ' ')
  validate_cmdline('de ')
  type_keys('<Esc>')
end

T['Autocorrect']['respects `config.autocorrect.func`'] = function()
  child.lua([[
    _G.log = {}
    MiniCmdline.config.autocorrect.func = function(data)
      table.insert(_G.log, vim.deepcopy(data))
      return _G.correction
    end
  ]])

  child.lua('_G.correction = "xxxx"')
  type_keys(':', 'srot')
  eq(child.lua_get('_G.log'), {})
  type_keys(' ')
  -- NOTE: Should not autocorrect output
  validate_cmdline('xxxx ')
  eq(child.lua_get('_G.log'), { { word = 'srot', type = 'command' } })
  child.lua('_G.log = {}')
  type_keys('<Esc>')

  -- Should not change command line if output is same word or `nil`
  child.cmd('au CmdlineChanged * lua _G.n = (_G.n or 0) + 1')
  local validate_no_change = function(correction)
    child.lua('_G.correction = ' .. vim.inspect(correction))
    type_keys(':', 'srot')
    child.lua('_G.n = 0')

    type_keys(' ')
    validate_cmdline('srot ')
    eq(child.lua_get('_G.n'), 1)

    type_keys('<Esc>')
  end

  validate_no_change('srot')
  validate_no_change(nil)

  -- Handles improper output
  child.lua([[
    _G.notify_log = {}
    vim.notify = function(...) table.insert(_G.notify_log, { ... }) end
    MiniCmdline.config.autocorrect.func = function() return 1 end
  ]])
  type_keys(':', 'srot', ' ')
  validate_cmdline('srot ')
  local warn_level = child.lua_get('vim.log.levels.WARN')
  eq(child.lua_get('_G.notify_log'), { { '(mini.cmdline) Can not autocorrect for "srot"', warn_level } })
end

T['Autocorrect']['works just before final <CR>'] = function()
  local validate = function(bad_word, ref_word)
    type_keys(':', bad_word, '<CR>')
    eq(child.fn.histget('cmd', -1), ref_word)
    eq(child.fn.mode(), 'n')
  end

  local buf_id_other = child.api.nvim_create_buf(true, false)
  validate('bnxxt', 'bnext')
  eq(child.api.nvim_get_current_buf(), buf_id_other)
  type_keys('<Esc>')

  -- Should work with `!`
  child.cmd('vsplit')
  local win_id = child.api.nvim_get_current_win()
  validate({ 'Q', '!' }, 'q!')
  eq(child.api.nvim_win_is_valid(win_id), false)
end

T['Autocorrect']['is not applied when abandoning command line'] = function()
  local validate = function(key)
    type_keys(':', 'xxxx', key)
    eq(child.fn.histget('cmd', -1), 'xxxx')
  end
  validate('<Esc>')
  validate('<C-c>')
end

T['Autocorrect']['uses correct state before final <CR>'] = function()
  child.lua([[
    _G.log = {}
    MiniCmdline.config.autocorrect.func = function(data)
      table.insert(_G.log, vim.deepcopy(data))
      return data.word
    end
  ]])

  -- Changing `type` just before `<CR>`
  type_keys(':', 'cnoremap <C-x> www', '<CR>')
  type_keys(':', 'cn', '<Up>')
  validate_cmdline('cnoremap \24 www')
  child.lua('_G.log = {}')
  type_keys('<CR>')
  local ref_word = child.fn.has('nvim-0.11') == 1 and '\24 www' or 'www'
  eq(child.lua_get('_G.log'), { { word = ref_word, type = 'mapping' } })

  -- Should include `!` in the word (when using `vim.fn.getcmdcomplpat()`)
  if child.fn.has('nvim-0.11') == 0 then return end
  child.cmd('split')
  child.lua('_G.log = {}')
  type_keys(':', 'q!', '<CR>')
  eq(child.lua_get('_G.log'), { { word = 'q!', type = '' } })
end

T['Autocorrect']['respects `vim.{g,b}.minicmdline_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minicmdline_disable = true
    type_keys(':', 'seT', ' ')
    validate_cmdline('seT ')
  end,
})

T['Autopeek'] = new_set({
  hooks = {
    pre_case = function()
      load_module({ autocomplete = { enable = false }, autocorrect = { enable = false } })

      child.set_size(11, 20)
      set_lines(lines_101)

      child.o.tabline, child.o.statusline = 'My tabline', 'My statusline'
      child.o.showtabline, child.o.laststatus = 2, 2

      -- Ensure more informative screenshots
      child.cmd('hi MiniCmdlinePeekLineNr guibg=Red ctermbg=Red')
      child.cmd('hi MiniCmdlinePeekSign guibg=Green ctermbg=Green')
      child.cmd('hi MiniCmdlinePeekSep guibg=Yellow ctermbg=Yellow')
    end,
  },
})

local get_peek_win_id = function()
  local buf_id = child.api.nvim_get_current_buf()
  for _, win_id in ipairs(child.api.nvim_list_wins()) do
    local is_float = child.api.nvim_win_get_config(win_id).relative ~= ''
    if is_float and child.api.nvim_win_get_buf(win_id) == buf_id then return win_id end
  end
end

local get_peek_winheight = function()
  local peek_win_id = get_peek_win_id()
  return peek_win_id == nil and 0 or child.api.nvim_win_get_height(peek_win_id)
end

local validate_no_peek = function() eq(get_peek_winheight() == 0, true) end
local validate_peek = function() eq(get_peek_winheight() > 0, true) end

T['Autopeek']['works'] = function()
  type_keys(':')
  expect_screenshot_after_keys('2')

  -- Empty range end means cursor line
  expect_screenshot_after_keys(',')

  -- Explicit same line range should be the same as one number range
  expect_screenshot_after_keys('2')

  expect_screenshot_after_keys('0')

  -- Should truncate to last available line
  expect_screenshot_after_keys('0')

  -- Should update after deleting text
  expect_screenshot_after_keys('<BS>')
  expect_screenshot_after_keys('<C-w>')
  expect_screenshot_after_keys('<C-u>')

  -- Should work with blank line
  expect_screenshot_after_keys(' ')

  -- Exiting Command-line mode should hide peek window
  type_keys('<Esc>')
  validate_no_peek()
end

T['Autopeek']['persists for the entirety of command typing'] = function()
  type_keys(':')
  expect_screenshot_after_keys('2')
  expect_screenshot_after_keys('delete ')
  expect_screenshot_after_keys('_ 3')
  type_keys('<CR>')
  eq(child.api.nvim_buf_get_lines(0, 0, 2, false), { 'Line 1', 'Line 5' })
end

T['Autopeek']['correctly computes lines to show'] = function()
  type_keys(':')

  -- Apart, near edges
  expect_screenshot_after_keys('<C-u>1,101')
  expect_screenshot_after_keys('<C-u>2,101')
  expect_screenshot_after_keys('<C-u>1,100')
  expect_screenshot_after_keys('<C-u>2,100')

  -- Apart, away from edges
  expect_screenshot_after_keys('<C-u>3,99')

  -- One line in between contexts (no fold should be visible)
  expect_screenshot_after_keys('<C-u>3,7')

  -- Touching contexts
  expect_screenshot_after_keys('<C-u>3,6')

  -- Intersecting contexts
  expect_screenshot_after_keys('<C-u>3,5')

  -- Touching range lines
  expect_screenshot_after_keys('<C-u>3,4')
end

T['Autopeek']['works with inverted range'] = function()
  type_keys(':')

  expect_screenshot_after_keys('<C-u>101,1')
  expect_screenshot_after_keys('<C-u>101,2')
  expect_screenshot_after_keys('<C-u>100,1')
  expect_screenshot_after_keys('<C-u>100,2')
  expect_screenshot_after_keys('<C-u>99,3')
  expect_screenshot_after_keys('<C-u>7,3')
  expect_screenshot_after_keys('<C-u>6,3')
  expect_screenshot_after_keys('<C-u>5,3')
  expect_screenshot_after_keys('<C-u>4,3')
end

T['Autopeek']['can be hidden and opened within same session'] = function()
  type_keys(':')

  validate_no_peek()
  type_keys('2')
  validate_peek()
  type_keys(',')
  validate_peek()
  type_keys('<C-u>')
  validate_no_peek()

  type_keys('1')
  validate_peek()
  type_keys('<BS>')
  validate_no_peek()
end

T['Autopeek']["works with 'inccommand'"] = function()
  type_keys(':')
  local validate = function(keys)
    child.api.nvim_input(keys)
    child.expect_screenshot()
  end
  validate('2s')
  validate('/')
  validate('Li')
  validate('/')
  validate('XX')

  validate('/<CR>')
  validate_no_peek()
  eq(child.api.nvim_buf_get_lines(0, 0, 2, false), { 'Line 1', 'XXne 2' })
end

T['Autopeek']['respects mappings'] = function()
  -- Should not work if Command-line mode is both entered and exited
  child.cmd('nnoremap <C-x> :2,3sort<CR>')
  type_keys('<C-x>')
  validate_no_peek()

  -- Should work if Command-line mode is only entered
  child.cmd('nnoremap <C-y> :3,4')
  expect_screenshot_after_keys('<C-y>')
end

T['Autopeek']['uses correct highlight groups'] = function()
  type_keys(':', '2')
  local win_id = get_peek_win_id()
  local peek_winhl = child.api.nvim_get_option_value('winhighlight', { scope = 'local', win = win_id })
  expect.match(peek_winhl, 'NormalFloat:MiniCmdlinePeekNormal')
  expect.match(peek_winhl, 'FloatBorder:MiniCmdlinePeekBorder')
  expect.match(peek_winhl, 'FloatTitle:MiniCmdlinePeekTitle')
end

T['Autopeek']["ignores 'wrap'"] = function()
  set_lines({ 'Very big line number one', '', '', 'Very big line number two' })
  child.o.wrap = true

  type_keys(':')
  expect_screenshot_after_keys('<C-u>2')
  expect_screenshot_after_keys('<C-u>2,3')
  expect_screenshot_after_keys('<C-u>1,4')
  type_keys('<Esc>')

  -- Should also respect global 'list' and 'listchars'
  type_keys(':')
  child.o.list = true
  child.o.listchars = 'precedes:<,extends:>'
  expect_screenshot_after_keys('<C-u>2,3')
end

T['Autopeek']['works with virtual lines'] = function()
  local ns_id = child.api.nvim_create_namespace('Test')
  child.api.nvim_buf_set_extmark(0, ns_id, 1, 0, { virt_lines = { { { 'Virt' } } } })
  child.api.nvim_buf_set_extmark(0, ns_id, 3, 0, { virt_lines = { { { 'Virt above' } } }, virt_lines_above = true })

  -- Currently context computation doesn't take virtual lines into account.
  -- Ideally their extmarks should not be shown, but doing that is difficult.
  -- It is much easier to show buffer as is and document issue with virtual
  -- lines as a known limitation.
  type_keys(':')
  expect_screenshot_after_keys('<C-u>2')
  expect_screenshot_after_keys('<C-u>4')
  expect_screenshot_after_keys('<C-u>2,4')
  type_keys('<Esc>')

  -- Zero context should work better
  child.lua('MiniCmdline.config.autopeek.n_context = 0')
  type_keys(':')
  expect_screenshot_after_keys('<C-u>2')
  expect_screenshot_after_keys('<C-u>4')
  expect_screenshot_after_keys('<C-u>2,4')
end

T['Autopeek']['hides visual selection'] = function()
  child.set_size(15, 20)

  -- The range preview is already a preview of Visual selection
  set_cursor(2, 1)
  type_keys('v', '2j', ':')
  child.expect_screenshot()
  eq(get_cursor(), { 2, 1 })
  type_keys('<Esc>')

  -- Should be overridable via autocommand before `require('mini.cmdline')`
  unload_module()
  child.lua([[
    local disable = vim.schedule_wrap(function()
      local is_from_visual = vim.startswith(vim.fn.getcmdline(), "'<,'>")
      MiniCmdline.config.autopeek.enable = not is_from_visual
    end)
    local reenable = function() MiniCmdline.config.autopeek.enable = true end

    vim.api.nvim_create_autocmd('CmdlineEnter', { callback = disable })
    vim.api.nvim_create_autocmd('CmdlineLeave', { callback = reenable })
  ]])
  load_module()

  type_keys('v', '2j', ':')
  child.expect_screenshot({ redraw = false })
  type_keys('<Esc>')

  type_keys(':', '5')
  validate_peek()
end

T['Autopeek']['works with every kind of line range'] = function()
  set_cursor(3, 0)
  type_keys('Vj', '<Esc>')

  set_cursor(10, 1)
  type_keys('ma')
  set_cursor(12, 0)
  type_keys('mb')

  set_cursor(2, 0)
  type_keys(':')

  -- `:h :range`
  expect_screenshot_after_keys('<C-u>.,$')
  expect_screenshot_after_keys('<C-u>%')
  expect_screenshot_after_keys('<C-u>*')
  expect_screenshot_after_keys("<C-u>'<LT>,'>")
  expect_screenshot_after_keys("<C-u>'a,'b")
  expect_screenshot_after_keys("<C-u>'b,'a")
  expect_screenshot_after_keys('<C-u>/Line 5/,/Line 4/')
  expect_screenshot_after_keys('<C-u>/Line 5/;/Line 4/')
  expect_screenshot_after_keys('<C-u>?Line 5?,?Line 6?')
  expect_screenshot_after_keys('<C-u>?Line 5?;?Line 6?')

  -- `:h range-offset`
  expect_screenshot_after_keys('<C-u>++,-')
  expect_screenshot_after_keys("<C-u>'<LT>+2,'a--")
  expect_screenshot_after_keys('<C-u>/5/+100,/4/-100')
end

T['Autopeek']['is shown only for line range'] = function()
  type_keys(':')

  -- Should assume line range by default
  type_keys('%')
  validate_peek()

  -- `:bwipeout` doesn't treat range as lines, see `:h :command-addr`
  type_keys('bw')
  validate_no_peek()

  type_keys('<C-w>')
  validate_peek()
end

T['Autopeek']['works when regular command line parsing fails'] = function()
  type_keys('/', 'Line 10', '<CR>')
  child.cmd('nohlsearch')

  type_keys(':')

  -- Line with only range
  expect_screenshot_after_keys('<C-u>%')

  -- Unfinished `/xxx/` range
  expect_screenshot_after_keys('<C-u>/')
  expect_screenshot_after_keys('Li')
  expect_screenshot_after_keys('ne 4')
  expect_screenshot_after_keys('/,')
  expect_screenshot_after_keys('/Line 6')

  -- Unrecognized command
  expect_screenshot_after_keys('<C-u>1xxx')
  expect_screenshot_after_keys('<C-u>1,2xxx')
  expect_screenshot_after_keys('<C-u>%xxx')
end

T['Autopeek']['reacts to command line height change during typing'] = function()
  child.set_size(10, 15)

  local long_line = string.rep('a', 16)
  type_keys(':', '2,5')

  -- Should reposition on top of new command line height
  expect_screenshot_after_keys(long_line)

  -- Should adjust height if not enough space
  expect_screenshot_after_keys(long_line)
  expect_screenshot_after_keys(long_line)
end

T['Autopeek']['reacts to `VimResized`'] = function()
  child.set_size(10, 20)
  type_keys(':')
  expect_screenshot_after_keys('2,5')

  child.set_size(10, 25)
  child.expect_screenshot()

  child.set_size(15, 15)
  child.expect_screenshot()

  child.set_size(6, 20)
  child.expect_screenshot()
end

T['Autopeek']["works with different 'cmdheight'"] = function()
  child.o.cmdheight = 0
  expect_screenshot_after_keys(':2,5')
  type_keys('<Esc>')

  child.o.cmdheight = 2
  expect_screenshot_after_keys(':2,5')
  type_keys('<Esc>')
end

T['Autopeek']['works only in `:` command type'] = function()
  local validate = function(keys)
    eq(child.fn.mode(), 'n')
    type_keys(keys)
    validate_no_peek()
    type_keys('<Esc>', '<Esc>')
  end
  validate({ '/', '2' })
  validate({ '?', '2' })
  validate({ 'i', '<C-r>=', '2' })
  validate({ 'call input("")<CR>', '2' })
end

T['Autopeek']['is shown below pmenu'] = function() expect_screenshot_after_keys({ ':', '1,2sor', '<Tab>' }) end

T['Autopeek']['respects `config.autopeek.window.config`'] = function()
  -- As table
  child.lua([[MiniCmdline.config.autopeek.window.config = { border = 'none', width = 15 }]])
  expect_screenshot_after_keys({ ':', '2' })
  type_keys('<Esc>')

  -- As callable
  child.lua([[MiniCmdline.config.autopeek.window.config = function()
    return { border = 'double', width = 0.25 * vim.o.columns, height = 5, title = 'Custom title to check truncation' }
  end]])
  expect_screenshot_after_keys({ ':', '2' })
end

T['Autopeek']["respects 'winborder'"] = function()
  if child.fn.has('nvim-0.11') == 0 then MiniTest.skip("'winborder' option is present on Neovim>=0.11") end

  local validate = function(winborder)
    child.o.winborder = winborder
    type_keys(':')
    expect_screenshot_after_keys(':2,100')
    type_keys('<Esc>')
  end

  validate('rounded')

  -- Should prefer explicitly configured value over 'winborder'
  child.lua('MiniCmdline.config.autopeek.window.config = { border = "double" }')
  validate('rounded')

  -- Should work with "string array" 'winborder'
  if child.fn.has('nvim-0.12') == 0 then MiniTest.skip("String array 'winborder' is present on Neovim>=0.12") end
  child.lua('MiniCmdline.config.autopeek.window.config.border = nil')
  validate('+,-,+,|,+,-,+,|')
end

T['Autopeek']['correctly shows window without border'] = function()
  child.lua('MiniCmdline.config.autopeek.window.config = { border = "none" }')

  local validate = function(screen_lines, range)
    child.set_size(screen_lines, 20)
    type_keys(':')
    expect_screenshot_after_keys(range)
    type_keys('<Esc>')
  end

  validate(10, '1,101')
  validate(10, '2,100')
  validate(10, '2,5')
  validate(10, '2,2')

  -- No context
  child.lua('MiniCmdline.config.autopeek.n_context = 0')
  validate(10, '2,101')

  -- Extreme available height
  validate(4, '2,4')
end

T['Autopeek']['respects `config.autopeek.n_context`'] = function()
  child.lua('MiniCmdline.config.autopeek.n_context = 0')

  type_keys(':')
  expect_screenshot_after_keys('<C-u>1,101')
  expect_screenshot_after_keys('<C-u>2,101')
  expect_screenshot_after_keys('<C-u>1,100')
  expect_screenshot_after_keys('<C-u>2,100')
  expect_screenshot_after_keys('<C-u>2,4')
  expect_screenshot_after_keys('<C-u>2,3')
  expect_screenshot_after_keys('<C-u>2,2')
end

T['Autopeek']['fits into available height'] = function()
  child.lua('MiniCmdline.config.autopeek.n_context = 2')

  local validate = function(screen_lines, range)
    child.set_size(screen_lines, 20)
    type_keys(':')
    expect_screenshot_after_keys(range)
    type_keys('<Esc>')
  end

  validate(14, '3,10')

  -- Should first hide outer context equally from top and bottom
  validate(13, '3,10')
  validate(12, '3,10')
  validate(11, '3,10')
  validate(10, '3,10')

  -- Should then hide excsess under the fold
  validate(9, '3,10')
  validate(8, '3,10')
  validate(7, '3,10')
  validate(6, '3,10')

  -- Should work with extreme available height
  validate(5, '3,10')
  validate(4, '3,10')

  -- Should work with different kinds of context overlap
  -- - Touching
  validate(13, '3,8')
  validate(12, '3,8')
  validate(11, '3,8')
  validate(10, '3,8')
  validate(9, '3,8')
  validate(8, '3,8')
  validate(7, '3,8')
  validate(6, '3,8')
  validate(5, '3,8')

  -- - Inner intersecting
  validate(11, '3,6')
  validate(10, '3,6')
  validate(9, '3,6')
  validate(8, '3,6')
  validate(7, '3,6')
  validate(6, '3,6')
  validate(5, '3,6')

  -- - Outer intersecting
  validate(9, '3,4')
  validate(8, '3,4')
  validate(7, '3,4')
  validate(6, '3,4')
  validate(5, '3,4')

  -- Inverted range (only selective basic sanity checks)
  validate(12, '10,3')
  validate(9, '10,3')
  validate(12, '8,3')
  validate(8, '8,3')
  validate(8, '4,3')
  validate(5, '4,3')
end

T['Autopeek']['updates when navigating through history'] = function()
  type_keys(':', '2,5sort', '<CR>')
  type_keys(':', 'echo', '<CR>')

  type_keys(':')
  expect_screenshot_after_keys('10')
  expect_screenshot_after_keys('<C-u><Up>')
  expect_screenshot_after_keys('<C-u><Up>')
  expect_screenshot_after_keys('<C-u><Down>')
end

T['Autopeek']['works with command window'] = function()
  -- Command window seems to block child process, so use a workaround to test
  -- if autopeek was shown
  child.lua([[
    _G.statuscolumn_was_used = false
    MiniCmdline.config.autopeek.window.statuscolumn = function(...)
      _G.statuscolumn_was_used = true
      return MiniCmdline.default_autopeek_statuscolumn(...)
    end
  ]])

  -- Should not be shown if command is typed inside command window
  -- NOTE: It would be good to also show it, but it would require much more
  -- explicit work (`CmdlineChanged` is not triggered in cmdwin)
  type_keys('q:', '2', ',5', '<CR>')
  eq(child.lua_get('_G.statuscolumn_was_used'), false)

  -- NOTE: Neovim<0.10 can not detect if buffer belongs to command window
  if child.fn.has('nvim-0.10') == 0 then
    MiniTest.skip('Neovim<0.10 does not have enough capabilities to work with command window')
  end

  -- Should not be shown for command window buffer.
  type_keys('q:')
  type_keys(':', '1', '<CR>')
  type_keys('<CR>')
  eq(child.lua_get('_G.statuscolumn_was_used'), false)

  -- Should hide already visible peek when entering command window
  type_keys(':', '2')
  validate_peek()
  child.lua('_G.statuscolumn_was_used = false')
  type_keys('<C-f>')
  type_keys(',5', '<CR>')
  eq(child.lua_get('_G.statuscolumn_was_used'), false)
end

T['Autopeek']['works when using command-line expression register'] = function()
  type_keys(':', '2,', '<C-r>=', '10+10')
  -- Should not react to "range like" content when entering register
  eq(get_peek_winheight(), 3)

  type_keys('<CR>')
  child.expect_screenshot()

  -- Should keep working as if the number was typed manually
  type_keys('+')
  child.expect_screenshot()
  type_keys('<Esc>')
  validate_no_peek()
end

T['Autopeek']['respects `vim.{g,b}.minicmdline_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minicmdline_disable = true
    type_keys(':', '2')
    validate_no_peek()
    type_keys('<Esc>')

    child[var_type].minicmdline_disable = false
    type_keys(':', '2')
    validate_peek()
  end,
})

T['Arrow mappings'] = new_set()

T['Arrow mappings']['work horizontally'] = function()
  load_module({ autocomplete = { enable = false } })

  -- Left/Right - always move cursor regardless of pum
  type_keys(':', 'so', '<Tab>')
  eq(has_pum(), true)
  type_keys('<Left>')
  validate_cmdline('sort', 4)
  eq(has_pum(), false)

  type_keys('<Tab>')
  eq(has_pum(), true)
  type_keys('<Right>')
  validate_cmdline('sortt', 6)
  eq(has_pum(), false)
end

T['Arrow mappings']['work vertically'] = function()
  if child.fn.has('nvim-0.10') == 0 then MiniTest.skip('Works only on Neovim>=0.10') end

  load_module({ autocomplete = { enable = false } })

  -- Disable fuzzy matching for easier testing
  child.o.wildoptions = 'pum'

  -- Up/Down - navigate history regardless of pum
  type_keys(':', 'setglobal expandtab', '<CR>')
  type_keys(':', 'setglobal ignorecase', '<CR>')

  type_keys(':', 'set', '<Tab>')
  eq(has_pum(), true)

  type_keys('<Up>')
  validate_cmdline('setglobal ignorecase')
  eq(has_pum(), false)
  type_keys('<Up>')
  validate_cmdline('setglobal expandtab')
  eq(has_pum(), false)

  type_keys('<C-u>set', '<Tab>')
  eq(has_pum(), true)

  type_keys('<Down>')
  validate_cmdline('setglobal ignorecase')
  eq(has_pum(), false)
  type_keys('<Down>')
  validate_cmdline('set')
  eq(has_pum(), false)
end

T['Arrow mappings']['respect `config.autocomplete.map_arrows`'] = function()
  load_module({ autocomplete = { map_arrows = false } })
  local validate = function(key) expect.match(child.cmd_capture('cnoremap ' .. key), 'No mapping found') end
  validate('<Left>')
  validate('<Right>')
  validate('<Up>')
  validate('<Down>')
end

return T
