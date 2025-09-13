-- NOTE: These are basic tests which cover basic functionality. A lot of
-- nuances are not tested to meet "complexity-necessity" trade-off. Feel free
-- to add tests for new behavior and found edge cases.
local helpers = dofile('tests/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('starter', config) end
local unload_module = function() child.mini_unload('starter') end
local reload_module = function(config) unload_module(); load_module(config) end
local reload_from_strconfig = function(strconfig) unload_module(); child.mini_load_strconfig('starter', strconfig) end
local get_cursor = function(...) return child.get_cursor(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
--stylua: ignore end

-- Make helpers
local is_starter_shown = function() return child.bo.filetype == 'ministarter' end

local validate_starter_shown = function() eq(is_starter_shown(), true) end

local validate_starter_not_shown = function() eq(is_starter_shown(), false) end

local validate_equal_starter = function(strconfig_1, strconfig_2)
  -- Reload with first config
  reload_from_strconfig(strconfig_1)
  child.lua('MiniStarter.open()')
  local lines_1 = get_lines()

  -- Reload with first config
  reload_from_strconfig(strconfig_2)
  child.lua('MiniStarter.open()')
  local lines_2 = get_lines()

  eq(lines_1, lines_2)

  reload_module()
end

local get_latest_message = function() return child.cmd_capture('1messages') end

local get_active_items_names = function(buf_id)
  buf_id = buf_id or child.api.nvim_get_current_buf()
  local items = child.lua_get('MiniStarter.content_to_items(MiniStarter.get_content(...))', { buf_id })
  local active_items = vim.tbl_filter(function(x) return x._active == true end, items)
  return vim.tbl_map(function(x) return x.name end, active_items)
end

local mock_user_and_time = function()
  child.lua([[vim.loop.os_get_passwd = function() return { username = 'MINI' } end]])
  child.lua([[vim.fn.strftime = function(x) return x == '%H' and '12' or '' end]])
end

local mock_item = function(name, section)
  return { name = name, action = ('lua _G.item_name = %s'):format(vim.inspect(name)), section = section }
end

local mock_itemstring = function(name, section)
  return ([[{ name = '%s', action = 'lua _G.item_name = "%s"', section = '%s' }]]):format(name, name, section)
end

-- Data =======================================================================
local example_items = { mock_item('aaab', 'A'), mock_item('aaba', 'A'), mock_item('abaa', 'B'), mock_item('baaa', 'B') }

local example_itemstring = '{ '
  .. table.concat({
    mock_itemstring('aaab', 'A'),
    mock_itemstring('aaba', 'A'),
    mock_itemstring('abaa', 'B'),
    mock_itemstring('baaa', 'B'),
  }, ', ')
  .. ' }'

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      load_module()
      mock_user_and_time()
    end,
    post_once = child.stop,
  },
  n_retry = helpers.get_n_retry(1),
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  -- Global variable
  eq(child.lua_get('type(_G.MiniStarter)'), 'table')

  -- Autocommand group
  eq(child.fn.exists('#MiniStarter'), 1)

  -- Highlight groups
  child.cmd('hi clear')
  load_module()
  local has_highlight = function(group, value) expect.match(child.cmd_capture('hi ' .. group), value) end

  has_highlight('MiniStarterCurrent', 'links to MiniStarterItem')
  has_highlight('MiniStarterFooter', 'links to Title')
  has_highlight('MiniStarterHeader', 'links to Title')
  has_highlight('MiniStarterInactive', 'links to Comment')
  has_highlight('MiniStarterItem', 'links to Normal')
  has_highlight('MiniStarterItemBullet', 'links to Delimiter')
  has_highlight('MiniStarterItemPrefix', 'links to WarningMsg')
  has_highlight('MiniStarterSection', 'links to Delimiter')
  has_highlight('MiniStarterQuery', 'links to MoreMsg')
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniStarter.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniStarter.config.' .. field), value) end

  expect_config('autoopen', true)
  expect_config('evaluate_single', false)
  expect_config('items', vim.NIL)
  expect_config('header', vim.NIL)
  expect_config('footer', vim.NIL)
  expect_config('content_hooks', vim.NIL)
  expect_config('query_updaters', 'abcdefghijklmnopqrstuvwxyz0123456789_-.')
  expect_config('silent', false)
end

T['setup()']['respects `config` argument'] = function()
  reload_module({ autoopen = false })
  eq(child.lua_get('MiniStarter.config.autoopen'), false)
end

T['setup()']['validates `config` argument'] = function()
  unload_module()

  local expect_config_error = function(config, name, target_type)
    expect.error(load_module, vim.pesc(name) .. '.*' .. vim.pesc(target_type), config)
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ autoopen = 'a' }, 'autoopen', 'boolean')
  expect_config_error({ evaluate_single = 'a' }, 'evaluate_single', 'boolean')
  expect_config_error({ items = 'a' }, 'items', 'table')
  -- `header` and `footer` can have any type
  expect_config_error({ content_hooks = 'a' }, 'content_hooks', 'table')
  expect_config_error({ query_updaters = 1 }, 'query_updaters', 'string')
  expect_config_error({ silent = 1 }, 'silent', 'boolean')
end

T['setup()']['ensures colors'] = function()
  child.cmd('colorscheme default')
  expect.match(child.cmd_capture('hi MiniStarterCurrent'), 'links to MiniStarterItem')
end

-- Work with Starter buffer ---------------------------------------------------
T['open()'] = new_set()

T['open()']['works'] = function()
  local init_buf_id = child.api.nvim_get_current_buf()

  child.lua('MiniStarter.open()')

  local buf_cur = child.api.nvim_get_current_buf()
  expect.no_equality(buf_cur, init_buf_id)
  eq(child.api.nvim_buf_get_name(0), 'ministarter://' .. buf_cur .. '/welcome')
  validate_starter_shown()

  expect.match(table.concat(get_lines(), '\n'), 'Builtin actions')
end

T['open()']['sets local options'] = function()
  -- Cache initial data for future verification
  child.o.showtabline = 2
  local init_laststatus = child.o.laststatus

  -- Open Starter buffer
  child.lua('MiniStarter.open()')

  -- Should set essential local options (not all actually set are tested)
  eq(child.bo.bufhidden, 'wipe')
  eq(child.bo.buflisted, false)
  eq(child.bo.buftype, 'nofile')
  eq(child.wo.colorcolumn, '')
  eq(child.wo.foldlevel, 999)
  eq(child.bo.modifiable, false)
  eq(child.wo.signcolumn, 'no')
  eq(child.wo.statuscolumn, '')
  eq(child.wo.wrap, false)

  -- Should hide tabline but not touch statusline
  eq(child.o.showtabline, 1)
  eq(child.o.laststatus, init_laststatus)

  -- Verify that tabline resets to its initial value
  child.cmd('bwipeout')
  eq(child.o.showtabline, 2)
end

T['open()']['ends up in Normal mode'] = new_set(
  { parametrize = { { 'Insert' }, { 'Visual' }, { 'Replace' }, { 'Command' }, { 'Terminal' } } },
  {
    test = function(test_mode)
      local keys = ({ Insert = 'i', Visual = 'v', Replace = 'R', Command = ':', Terminal = ':terminal<CR>i' })[test_mode]
      type_keys(keys)
      local cur_mode_id = ({ Insert = 'i', Visual = 'v', Replace = 'R', Command = 'c', Terminal = 't' })[test_mode]
      eq(child.fn.mode(), cur_mode_id)

      -- Ensure no `InsertEnter` event is triggered (see #183)
      child.cmd('au InsertEnter * lua _G.been_inside_insertenter = true')

      -- Ensure `<C-\>` mapping is respected (see #189)
      child.cmd([[nnoremap <C-\> <Cmd>lua _G.been_inside_ctrlslash = true<CR>]])
      if test_mode ~= 'Replace' then
        child.cmd(cur_mode_id .. [[noremap <C-\> <Cmd>lua _G.been_inside_ctrlslash = true<CR>]])
      end

      child.lua('MiniStarter.open()')
      validate_starter_shown()
      eq(child.fn.mode(), 'n')

      eq(child.lua_get('_G.been_inside_insertenter'), vim.NIL)
      eq(child.lua_get('_G.been_inside_ctrlslash'), vim.NIL)
    end,
  }
)

local has_map = function(key, value)
  value = value or ''
  local cmd = 'nmap <buffer> ' .. key
  local pattern = vim.pesc('MiniStarter.' .. value)
  return child.cmd_capture(cmd):find(pattern) ~= nil
end

T['open()']['makes buffer mappings'] = function()
  child.lua('MiniStarter.open()')

  eq(has_map('<CR>', 'eval_current_item()'), true)
  eq(has_map('<Up>', [[update_current_item('prev')]]), true)
  eq(has_map('<C-p>', [[update_current_item('prev')]]), true)
  eq(has_map('<M-k>', [[update_current_item('prev')]]), true)
  eq(has_map('<Down>', [[update_current_item('next')]]), true)
  eq(has_map('<C-n>', [[update_current_item('next')]]), true)
  eq(has_map('<M-j>', [[update_current_item('next')]]), true)
  eq(has_map('<Esc>', [[set_query('')]]), true)
  eq(has_map('<BS>', 'add_to_query()'), true)
  eq(has_map('<C-c>', 'close()'), true)

  -- Defines query updaters
  eq(has_map('a', 'add_to_query("a")'), true)
end

T['open()']['handles special query updaters'] = function()
  reload_module({ query_updaters = [["'\]] })
  child.lua('MiniStarter.open()')

  eq(has_map('"', [[add_to_query('"')]]), true)
  eq(has_map("'", [[add_to_query("'")]]), true)
  eq(has_map([[\]], [[add_to_query("\\")]]), true)
end

T['open()']['makes buffer autocommands'] = function()
  child.lua('MiniStarter.open()')
  expect.match(child.cmd_capture('au MiniStarterBuffer'), '<buffer=%d')
end

T['open()']['respects `buf_id` argument'] = function()
  local cur_buf_id = child.api.nvim_get_current_buf()
  child.lua(('MiniStarter.open(%s)'):format(cur_buf_id))
  eq(child.api.nvim_get_current_buf(), cur_buf_id)
  eq(child.api.nvim_buf_get_name(0), 'ministarter://' .. cur_buf_id .. '/welcome')
end

T['open()']['issues an autocommand after finished opening'] = function()
  -- Finished opening
  child.lua('_G.n = 0')
  child.cmd('au User MiniStarterOpened lua _G.n = _G.n + 1')
  child.lua('MiniStarter.open()')

  eq(child.lua_get('_G.n'), 1)

  -- Not finished opening
  child.lua('_G.n = 0')
  child.lua('pcall(MiniStarter.open, "a")')
  eq(child.lua_get('_G.n'), 0)
end

T['open()']['creates unique buffer names'] = function()
  child.lua('MiniStarter.open()')
  eq(child.api.nvim_buf_get_name(0), 'ministarter://' .. child.api.nvim_get_current_buf() .. '/welcome')

  child.lua('MiniStarter.close()')
  child.lua('MiniStarter.open()')
  eq(child.api.nvim_buf_get_name(0), 'ministarter://' .. child.api.nvim_get_current_buf() .. '/welcome')
end

T['open()']['works with `:edit`'] = function()
  child.lua('MiniStarter.open()')
  child.cmd('edit')
  eq(child.cmd_capture('messages'), '')
  eq(#get_lines() > 1, true)
end

T['open()']['respects `vim.{g,b}.ministarter_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].ministarter_disable = true

    child.lua('MiniStarter.open()')
    validate_starter_not_shown()
  end,
})

T['open()']['respects `vim.b.ministarter_config`'] = function()
  -- Although this is defined inside current buffer, it should affect Starter buffer
  child.b.ministarter_config = { header = 'Hello', footer = 'World', content_hooks = {} }
  child.lua('MiniStarter.open()')
  child.expect_screenshot()
end

T['refresh()'] = new_set()

T['refresh()']['does `header` normalization'] = function()
  validate_equal_starter({ header = '100' }, { header = [['100']] })
  validate_equal_starter({ header = [[function() return 'aaa' end]] }, { header = [['aaa']] })
  validate_equal_starter({ header = [[function() return 'aaa\nbbb' end]] }, { header = [['aaa\nbbb']] })
  validate_equal_starter({ header = 'function() return 100 end' }, { header = [['100']] })
  validate_equal_starter({ header = 'function() return end' }, { header = [['nil']] })
end

T['refresh()']['does `header` normalization for empty string'] = function()
  reload_module({ content_hooks = {}, header = '' })
  child.lua('MiniStarter.open()')
  -- Empty header should result into no header and no empty line after it
  expect.no_equality(get_lines()[1], '')
end

T['refresh()']['does `footer` normalization'] = function()
  validate_equal_starter({ footer = '100' }, { footer = [['100']] })
  validate_equal_starter({ footer = [[function() return 'aaa' end]] }, { footer = [['aaa']] })
  validate_equal_starter({ footer = [[function() return 'aaa\nbbb' end]] }, { footer = [['aaa\nbbb']] })
  validate_equal_starter({ footer = 'function() return 100 end' }, { footer = [['100']] })
  validate_equal_starter({ footer = 'function() return end' }, { footer = [['nil']] })
end

T['refresh()']['does `footer` normalization for empty string'] = function()
  reload_module({ content_hooks = {}, footer = '' })
  child.lua('MiniStarter.open()')
  -- Empty footer should result into no footer and no empty line before it
  local lines = get_lines()
  expect.no_equality(lines[#lines], '')
end

T['refresh()']['does `items` normalization'] = function()
  local item = mock_itemstring('a', 'Section a')
  local item_2 = mock_itemstring('ba', 'Section b')
  local item_3 = mock_itemstring('bb', 'Section b')
  local item_empty = mock_itemstring('empty', '')
  local item_empty_2 = mock_itemstring('empty2', '')

  -- Evaluates functions
  validate_equal_starter({ items = ('{ function() return %s end }'):format(item) }, {
    items = ('{ %s }'):format(item),
  })

  -- Flattens nested tables
  validate_equal_starter({ items = ('{{%s}}'):format(item) }, { items = ('{%s}'):format(item) })

  -- Sorts items
  validate_equal_starter(
    { items = ('{%s, %s, %s}'):format(item_2, item, item_3) },
    { items = ('{%s, %s, %s}'):format(item_2, item_3, item) }
  )

  -- Sorts after flattening
  validate_equal_starter(
    { items = ('{{%s, %s}, {%s}}'):format(item_2, item, item_3) },
    { items = ('{%s, %s, %s}'):format(item_2, item_3, item) }
  )

  -- Sorts empty section name as any other section name
  validate_equal_starter(
    { items = ('{%s, %s, %s, %s}'):format(item_2, item_empty, item_3, item_empty_2) },
    { items = ('{%s, %s, %s, %s}'):format(item_2, item_3, item_empty, item_empty_2) }
  )
end

T['refresh()']['allows empty `items`'] = function()
  validate_equal_starter(
    { items = '{}' },
    { items = [[{ { name = '`config.items` is empty', action = '', section = '' } }]] }
  )
  -- It shouldn't give any messages
  eq(get_latest_message(), '')
end

T['refresh()']['prevents infinite recursion in `items` normalization'] = function()
  local item = mock_itemstring('a', 'A')
  reload_from_strconfig({ items = ('{ %s }'):format(item) })
  child.lua('MiniStarter.open()')
  local lines_1 = get_lines()

  child.lua('_G.f = function() return _G.f end')
  reload_from_strconfig({ items = ('{ _G.f, %s }'):format(item) })
  child.lua('MiniStarter.open()')
  local lines_2 = get_lines()

  eq(get_latest_message(), '(mini.starter) Too many nested functions in `config.items`.')

  eq(lines_1, lines_2)
end

T['refresh()']['does normalization on every call'] = function()
  child.lua('_G.n = 0')

  local strconfig_1 = {
    header = 'function() _G.n = _G.n + 1; return _G.n end',
    items = [[{ function() return { action = 'echo "a"', name = tostring(_G.n), section = 'Section a' } end }]],
    footer = 'function() return _G.n end',
  }
  local strconfig_2 = {
    header = [['2']],
    items = [[{ action = 'echo "a"', name = '2', section = 'Section a' }]],
    footer = [['2']],
  }

  reload_from_strconfig(strconfig_1)
  child.lua('MiniStarter.open()')
  child.lua('MiniStarter.refresh()')
  local lines_1 = get_lines()

  reload_from_strconfig(strconfig_2)
  child.lua('MiniStarter.open()')
  local lines_2 = get_lines()

  eq(lines_1, lines_2)
end

T['refresh()']['uses current `MiniStarter.config`'] = function()
  child.lua('MiniStarter.open()')
  child.lua('MiniStarter.config.header = "New header"')
  child.lua('MiniStarter.refresh()')
  local lines_1 = get_lines()

  reload_from_strconfig({ header = [['New header']] })
  child.lua('MiniStarter.open()')
  local lines_2 = get_lines()

  eq(lines_1, lines_2)
end

local reload_with_hooks = function()
  unload_module()
  child.lua('_G.hooks_history = {}')
  child.lua([[
    require('mini.starter').setup({ content_hooks = {
      function(x) table.insert(_G.hooks_history, 'a'); return x end,
      function(x) table.insert(_G.hooks_history, 'b'); return x end,
    } })]])
end

T['refresh()']['applies `content_hooks` sequentially'] = function()
  reload_with_hooks()
  child.lua('MiniStarter.open()')
  eq(child.lua_get('_G.hooks_history'), { 'a', 'b' })
end

T['refresh()']['calls `content_hooks` on every call'] = function()
  reload_with_hooks()
  child.lua('MiniStarter.open()')
  child.lua('MiniStarter.refresh()')
  eq(child.lua_get('_G.hooks_history'), { 'a', 'b', 'a', 'b' })
end

T['refresh()']['calls `content_hooks` with proper signature'] = function()
  child.lua([[MiniStarter.config.content_hooks = {
    function(...) local dots = {...}; _G.args = dots; return dots[1] end
  }]])
  child.lua('MiniStarter.open()')
  local buf_id = child.api.nvim_get_current_buf()

  -- Hooks should be called with `(content, buf_id)` signature
  child.lua('MiniStarter.refresh()')
  local args = child.lua_get('_G.args')

  eq(#args, 2)
  eq(child.lua_get('MiniStarter.get_content()'), args[1])
  eq(buf_id, args[2])
end

T['refresh()']['respects `vim.b.ministarter_config`'] = function()
  child.lua('MiniStarter.open()')
  child.expect_screenshot()

  child.b.ministarter_config = {
    header = 'Hello',
    footer = 'World',
    content_hooks = {},
    items = { { name = 'aaa', action = 'echo "aaa"', section = 'AAA' } },
  }
  child.lua('MiniStarter.refresh()')
  child.expect_screenshot()
end

T['refresh()']['respects `vim.b.ministarter_config`'] = function()
  child.lua('MiniStarter.open()')
  child.expect_screenshot()

  child.b.ministarter_config = {
    header = 'Hello',
    footer = 'World',
    content_hooks = {},
    items = { { name = 'aaa', action = 'echo "aaa"', section = 'AAA' } },
  }
  child.lua('MiniStarter.refresh()')
  child.expect_screenshot()
end

T['refresh()']['respects `config.silent`'] = function()
  child.lua('MiniStarter.open()')
  child.expect_screenshot()

  -- Clear command line
  child.cmd([[echo '']])
  child.lua('MiniStarter.config.silent = true')

  type_keys('a')
  child.expect_screenshot()
end

T['close()'] = new_set()

T['close()']['works'] = function()
  child.lua('MiniStarter.open()')
  local buf_id = child.api.nvim_get_current_buf()
  validate_starter_shown()

  child.lua('MiniStarter.close()')
  eq(child.api.nvim_buf_is_valid(buf_id), false)
  validate_starter_not_shown()
end

T['close()']['can be used when no Starter buffer is shown'] = function()
  validate_starter_not_shown()
  expect.no_error(function() child.lua('MiniStarter.close()') end)
end

T['eval_current_item()'] = new_set()

T['eval_current_item()']['works'] = function()
  reload_module({ items = example_items })
  child.lua('MiniStarter.open()')
  eq(get_active_items_names(), { 'aaab', 'aaba', 'abaa', 'baaa' })
  child.lua('_G.item_name = nil')

  type_keys('b')
  eq(get_active_items_names(), { 'baaa' })
  child.lua('_G.item_name = nil')

  -- It should reset query along with evaluating item
  child.lua('MiniStarter.eval_current_item()')
  eq(get_active_items_names(), { 'aaab', 'aaba', 'abaa', 'baaa' })
  eq(child.lua_get('_G.item_name'), 'baaa')
end

-- Work with content ----------------------------------------------------------
T['Default content'] = new_set({
  hooks = {
    pre_case = function()
      child.set_size(24, 80)
      -- Mock functions used to compute header
      mock_user_and_time()
    end,
  },
})

T['Default content']['works'] = function()
  child.lua('MiniStarter.open()')
  child.expect_screenshot()
end

T['Default content']['computes `header` depending on time of day'] = new_set({
  parametrize = { { '00' }, { '04' }, { '08' }, { '12' }, { '16' }, { '20' } },
}, {
  test = function(hour)
    local cmd = ([[vim.fn.strftime = function(x) return x == '%%H' and '%s' or '' end]]):format(hour)
    child.lua(cmd)
    child.lua('MiniStarter.open()')
    child.expect_screenshot()
  end,
})

T['Default content']["'Sessions' section"] = new_set()

T['Default content']["'Sessions' section"]['works'] = function()
  -- Should show local (first and with `(local)` note) and global sessions
  child.cmd('cd tests/dir-starter/sessions')
  child.lua([[require('mini.sessions').setup({ directory = '.' })]])

  child.lua('MiniStarter.open()')
  child.expect_screenshot()
end

T['Default content']["'Sessions' section"]['present even if no sessions detected'] = function()
  child.lua([[require('mini.sessions').setup({ file = '', directory = '' })]])
  child.lua('MiniStarter.open()')
  child.expect_screenshot()
end

T['Default content']["'Recent files' section"] = new_set()

T['Default content']["'Recent files' section"]['displays only readable files'] = function()
  child.v.oldfiles = { 'README.md', 'non-existent.lua' }
  child.lua('MiniStarter.open()')
  child.expect_screenshot()
end

T['Default content']["'Recent files' section"]['present even if no recent files'] = function()
  child.v.oldfiles = {}
  child.lua('MiniStarter.open()')
  child.expect_screenshot()
end

T['get_content()'] = new_set({ hooks = { pre_case = function() child.set_size(10, 40) end } })

T['get_content()']['works'] = function()
  local item = mock_item('a', 'Section a')
  load_module({ content_hooks = {}, header = 'Hello', footer = 'World', items = { item } })
  child.lua('MiniStarter.open()')
  child.expect_screenshot()

  -- Every element of array should contain content for a particular line
  local content = child.lua_get('MiniStarter.get_content()')
  eq(content[1], { { hl = 'MiniStarterHeader', string = 'Hello', type = 'header' } })
  eq(content[2], { { string = '', type = 'empty' } })
  eq(content[3], { { hl = 'MiniStarterSection', string = 'Section a', type = 'section' } })
  eq(content[4], { { hl = 'MiniStarterItem', item = content[4][1].item, string = 'a', type = 'item' } })
  eq(content[5], { { string = '', type = 'empty' } })
  eq(content[6], { { hl = 'MiniStarterFooter', string = 'World', type = 'footer' } })

  local content_item = content[4][1].item
  eq({ name = content_item.name, action = content_item.action, section = content_item.section }, item)
end

T['content_coords()'] = new_set({
  hooks = {
    pre_case = function()
      local item = mock_item('a', 'Section A')
      reload_module({ content_hooks = {}, header = 'Hello', footer = 'World', items = { item } })
      child.lua('MiniStarter.open()')
    end,
  },
})

T['content_coords()']['works with function argument'] = function()
  local coords = child.lua_get([[
    MiniStarter.content_coords(MiniStarter.get_content(), function(x)
      return vim.tbl_contains({'Hello', 'World'}, x.string)
    end)]])
  eq(coords, { { line = 1, unit = 1 }, { line = 6, unit = 1 } })
end

T['content_coords()']['works with string argument'] = function()
  local coords = child.lua_get([[MiniStarter.content_coords(MiniStarter.get_content(), 'empty')]])
  eq(coords, { { line = 2, unit = 1 }, { line = 5, unit = 1 } })
end

T['content_coords()']['works with no argument'] = function()
  local coords = child.lua_get('MiniStarter.content_coords(MiniStarter.get_content(), nil)')
  for i = 1, 6 do
    eq(coords[i], { line = i, unit = 1 })
  end
end

T['content_to_lines()'] = new_set({
  hooks = {
    pre_case = function() child.lua('MiniStarter.open()') end,
  },
})

T['content_to_lines()']['works'] = function()
  eq(child.lua_get('MiniStarter.content_to_lines(MiniStarter.get_content())'), get_lines())
end

T['content_to_items()'] = new_set()

T['content_to_items()']['works'] = function()
  reload_module({ content_hooks = {}, items = example_items })
  child.lua('MiniStarter.open()')

  local output = child.lua_get('MiniStarter.content_to_items(MiniStarter.get_content())')

  -- Should contain all information from input items
  for i, item in ipairs(output) do
    eq({ name = item.name, action = item.action, section = item.section }, example_items[i])
  end

  -- Should correctly compute length of minimum unique prefix
  eq(vim.tbl_map(function(x) return x._nprefix end, output), { 3, 3, 2, 1 })
end

T['content_to_items()']["modifies `item`'s name to equal content unit's `string`"] = function()
  local content = {
    { { type = 'item', string = 'aaa', item = mock_item('bbb', '') } },
    { { type = 'item', string = 'c\nc\nc', item = mock_item('ddd', '') } },
    { { type = 'empty', string = 'eee', item = mock_item('fff', '') } },
  }
  local output = child.lua_get('MiniStarter.content_to_items(...)', { content })
  eq(#output, 2)
  eq({ output[1].name, output[1].action }, { 'aaa', content[1][1].item.action })
  eq({ output[2].name, output[2].action }, { 'c c c', content[2][1].item.action })
end

T['gen_hook'] = new_set({
  hooks = {
    pre_case = function()
      child.set_size(20, 60)
      mock_user_and_time()
    end,
  },
})

T['gen_hook']['adding_bullet()'] = new_set()

T['gen_hook']['adding_bullet()']['works'] = function()
  reload_from_strconfig({ content_hooks = '{ require("mini.starter").gen_hook.adding_bullet() }' })
  child.lua('MiniStarter.open()')
  child.expect_screenshot()
end

T['gen_hook']['adding_bullet()']['respects `bullet` argument'] = function()
  reload_from_strconfig({ content_hooks = '{ require("mini.starter").gen_hook.adding_bullet("> ") }' })
  child.lua('MiniStarter.open()')
  child.expect_screenshot()
end

T['gen_hook']['adding_bullet() respects `place_cursor` argument'] = function()
  local reload = function(place_cursor)
    reload_from_strconfig({
      header = [['']],
      footer = [['']],
      items = ('{ %s }'):format(mock_itemstring('bbb', '')),
      content_hooks = ('{ require("mini.starter").gen_hook.adding_bullet("aaa", %s) }'):format(place_cursor),
    })
  end

  reload(false)
  child.lua('MiniStarter.open()')
  eq(get_cursor(), { 2, 3 })

  reload(true)
  child.lua('MiniStarter.open()')
  eq(get_cursor(), { 2, 0 })
end

T['gen_hook']['aligning()'] = new_set()

T['gen_hook']['aligning()']['works'] = function()
  reload_from_strconfig({ content_hooks = '{ require("mini.starter").gen_hook.aligning() }' })
  child.lua('MiniStarter.open()')
  -- By default shouldn't do any aligning
  child.expect_screenshot()
end

T['gen_hook']['aligning()']['respects arguments'] = new_set({
  parametrize = {
    { [['left', 'top']] },
    { [['left', 'center']] },
    { [['left', 'bottom']] },
    { [['center', 'top']] },
    { [['center', 'center']] },
    { [['center', 'bottom']] },
    { [['right', 'top']] },
    { [['right', 'center']] },
    { [['right', 'bottom']] },
  },
  hooks = {
    pre_case = function() child.set_size(10, 40) end,
  },
}, {
  test = function(args)
    reload_from_strconfig({
      content_hooks = ('{ require("mini.starter").gen_hook.aligning(%s) }'):format(args),
      header = [['']],
      footer = [['']],
      items = ('{ %s, %s }'):format(mock_itemstring('aaa', 'AAA'), mock_itemstring('bbb', 'AAA')),
    })
    child.lua('MiniStarter.open()')
    child.expect_screenshot()
  end,
})

T['gen_hook']['aligning()']['handles small windows'] = function()
  child.set_size(15, 40)
  child.cmd('vsplit | split')
  child.api.nvim_win_set_width(0, 2)
  child.api.nvim_win_set_height(0, 2)
  reload_from_strconfig({
    content_hooks = '{ require("mini.starter").gen_hook.aligning("right", "bottom") }',
    header = [['']],
    footer = [['']],
    items = ('{ %s, %s }'):format(mock_itemstring('aaa', 'AAA'), mock_itemstring('bbb', 'AAA')),
  })

  child.lua('MiniStarter.open()')
  child.expect_screenshot()
end

T['gen_hook']['aligning()']['has output respecting `buf_id` argument'] = function()
  child.set_size(15, 40)
  reload_from_strconfig({
    content_hooks = '{ require("mini.starter").gen_hook.aligning("center", "center") }',
    header = [['']],
    footer = [['']],
    items = ('{ %s, %s }'):format(mock_itemstring('aaa', 'AAA'), mock_itemstring('bbb', 'AAA')),
  })

  child.cmd('vsplit | split | wincmd l')
  child.lua('MiniStarter.open()')
  local starter_buf_id = child.api.nvim_get_current_buf()
  child.expect_screenshot()

  child.cmd('wincmd h')
  child.api.nvim_win_set_width(0, 5)
  child.lua('MiniStarter.refresh(...)', { starter_buf_id })
  child.expect_screenshot()
end

local reload_indexing = function(args)
  local itemstrings = {
    mock_itemstring('a', 'AAA'),
    mock_itemstring('aa', 'AAA'),
    mock_itemstring('b', 'BBB'),
    mock_itemstring('bb', 'BBB'),
  }
  reload_from_strconfig({
    header = [['']],
    footer = [['']],
    items = '{ ' .. table.concat(itemstrings, ', ') .. '}',
    content_hooks = ('{ require("mini.starter").gen_hook.indexing(%s) }'):format(args),
  })
end

T['gen_hook']['indexing()'] = new_set({ hooks = {
  pre_case = function() child.set_size(15, 40) end,
} })

T['gen_hook']['indexing()']['works'] = function()
  reload_indexing('')
  child.lua('MiniStarter.open()')
  child.expect_screenshot()
end

T['gen_hook']['indexing()']['respects arguments'] = new_set({
  parametrize = { { [['all', nil]] }, { [['section', nil]] }, { 'nil, {}' }, { [[nil, { 'AAA' }]] } },
}, {
  test = function(args)
    reload_indexing(args)
    child.lua('MiniStarter.open()')
    child.expect_screenshot()
  end,
})

T['gen_hook']['padding()'] = new_set()

T['gen_hook']['padding()']['works'] = function()
  reload_from_strconfig({ content_hooks = '{ require("mini.starter").gen_hook.padding() }' })
  child.lua('MiniStarter.open()')
  -- By default shouldn't do any aligning
  child.expect_screenshot()
end

T['gen_hook']['padding()']['respects arguments'] = new_set({
  parametrize = { { '2, 0' }, { '0, 2' }, { '2, 2' } },
}, {
  test = function(args)
    local command = string.format('{ require("mini.starter").gen_hook.padding(%s) }', args)
    reload_from_strconfig({ content_hooks = command })
    child.lua('MiniStarter.open()')
    child.expect_screenshot()
  end,
})

T['sections'] = new_set()

T['sections']['works'] = function()
  child.set_size(30, 60)
  child.lua([[MiniStarter.config.items = {
    MiniStarter.sections.builtin_actions,
    MiniStarter.sections.recent_files,
    MiniStarter.sections.sessions,
    MiniStarter.sections.pick,
    MiniStarter.sections.telescope,
  }]])
  child.lua([[MiniStarter.config.header = '']])
  child.lua([[MiniStarter.config.footer = '']])
  child.lua('MiniStarter.open()')
  child.expect_screenshot()
end

T['sections']['has correct items'] = function()
  local types = child.lua_get('vim.tbl_map(type, MiniStarter.sections)')
  --stylua: ignore
  eq(
    types,
    { builtin_actions = 'function', recent_files = 'function', sessions = 'function', pick = 'function', telescope = 'function' }
  )
end

T['sections']['recent_files()'] = new_set()

T['sections']['recent_files()']['correctly identifies files from current directory'] = function()
  local dir, dir_similar = 'tests/dir-starter/dir', 'tests/dir-starter/directory'
  local file = dir_similar .. '/file'

  -- Make recent file with absolute path having current directory as substring
  -- but not inside current directory
  child.v.oldfiles = { child.fn.fnamemodify(file, ':p') }
  child.cmd('cd ' .. dir)

  -- Set up to show files only in current directory
  child.lua('MiniStarter.config.items = { MiniStarter.sections.recent_files(5, true, true) }')
  child.lua('MiniStarter.open()')
  -- "Recent files" section should be empty
  child.expect_screenshot()
end

T['sections']['recent_files()']['opens path in relative form'] = function()
  local file = 'tests/dir-starter/dir/file1'
  child.v.oldfiles = { child.fn.fnamemodify(file, ':p') }
  child.lua('MiniStarter.open()')
  local n_bufs = #child.api.nvim_list_bufs()
  type_keys('<CR>')
  expect.match(child.cmd_capture('buffers'):gsub('\\', '/'), '[^/]tests/dir%-starter/dir/file1')
  -- Should properly hide Starter buffer
  eq(#child.api.nvim_list_bufs(), n_bufs)
end

T['sections']['recent_files()']['respects files in subdirectories'] = function()
  local dir = 'tests/dir-starter/dir'
  local dir_nested = dir .. '/subdir'
  local file, file_nested = dir .. '/file1', dir_nested .. '/file2'

  child.v.oldfiles = { child.fn.fnamemodify(file, ':p'), child.fn.fnamemodify(file_nested, ':p') }
  child.cmd('cd ' .. dir)

  -- Mock forward slash for more robust screenshot testing
  child.lua([[
    local fnamemodify_orig = vim.fn.fnamemodify
    vim.fn.fnamemodify = function(...) return (fnamemodify_orig(...):gsub('\\', '/')) end
  ]])

  -- Set up to show files only in current directory
  child.lua('MiniStarter.config.items = { MiniStarter.sections.recent_files(5, true, true) }')
  child.lua('MiniStarter.open()')
  -- "Recent files" section should show both files
  child.expect_screenshot()
end

T['sections']['recent_files()']['respects `n`'] = function()
  local dir = 'tests/dir-starter/dir'
  local test_file1, test_file3 = dir .. '/file1', dir .. '/file3'

  child.v.oldfiles = { child.fn.fnamemodify(test_file1, ':p'), child.fn.fnamemodify(test_file3, ':p') }
  eq(child.lua_get('#MiniStarter.sections.recent_files(1, false)()'), 1)
end

T['sections']['recent_files()']['respects `show_path`'] = function()
  local test_file = 'tests/dir-starter/dir/file1'

  child.v.oldfiles = { child.fn.fnamemodify(test_file, ':p') }

  child.lua([[MiniStarter.config.items = {
    MiniStarter.sections.recent_files(5, false, function() return '__hello__' end ),
  }]])
  child.lua('MiniStarter.open()')
  child.expect_screenshot()

  -- Should validate it
  expect.error(
    function() child.lua('MiniStarter.sections.recent_files(5, false, 1)') end,
    '`show_path`.*boolean or callable'
  )
end

-- Work with query ------------------------------------------------------------
T['set_query()'] = new_set({
  hooks = {
    pre_case = function()
      child.lua('MiniStarter.config.items = ' .. example_itemstring)
      child.lua('MiniStarter.open()')
    end,
  },
})

T['set_query()']['works'] = function()
  eq(get_active_items_names(), { 'aaab', 'aaba', 'abaa', 'baaa' })

  child.lua([[MiniStarter.set_query('aaa')]])
  eq(get_active_items_names(), { 'aaab' })

  child.lua([[MiniStarter.set_query('a')]])
  eq(get_active_items_names(), { 'aaab', 'aaba', 'abaa' })

  child.lua([[MiniStarter.set_query('aa')]])
  eq(get_active_items_names(), { 'aaab', 'aaba' })
end

T['set_query()']['uses `buf_id` argument'] = function()
  child.lua('MiniStarter.open()')
  local buf_id = child.api.nvim_get_current_buf()

  child.lua('MiniStarter.set_query(...)', { 'aaa', buf_id })
  eq(get_active_items_names(buf_id), { 'aaab' })
end

T['set_query()']['validates argument'] = function()
  expect.error(function() child.lua('MiniStarter.set_query(1)') end, '`query`.*`nil` or string')
end

T['set_query()']['does not allow query resulting in no active items'] = function()
  -- Make all showed messages full width
  child.o.cmdheight = 2

  child.lua([[MiniStarter.set_query('a')]])
  eq(get_active_items_names(), { 'aaab', 'aaba', 'abaa' })

  child.lua([[MiniStarter.set_query('c')]])
  eq(get_active_items_names(), { 'aaab', 'aaba', 'abaa' })
  expect.match(get_latest_message(), '%(mini%.starter%) Query "c" results into no active items%. Current query: a')
end

T['set_query()']['resets query with empty string'] = function()
  child.lua([[MiniStarter.set_query('a')]])
  eq(get_active_items_names(), { 'aaab', 'aaba', 'abaa' })

  child.lua([[MiniStarter.set_query('')]])
  eq(get_active_items_names(), { 'aaab', 'aaba', 'abaa', 'baaa' })
end

T['add_to_query()'] = new_set({
  hooks = {
    pre_case = function()
      child.lua('MiniStarter.config.items = ' .. vim.inspect(example_items))
      child.lua('MiniStarter.open()')
    end,
  },
})

T['add_to_query()']['works'] = function()
  -- Make all showed messages full width
  child.o.cmdheight = 2

  eq(get_active_items_names(), { 'aaab', 'aaba', 'abaa', 'baaa' })

  child.lua([[MiniStarter.add_to_query('a')]])
  eq(get_active_items_names(), { 'aaab', 'aaba', 'abaa' })

  child.lua([[MiniStarter.add_to_query('a')]])
  eq(get_active_items_names(), { 'aaab', 'aaba' })

  child.lua([[MiniStarter.add_to_query('a')]])
  eq(get_active_items_names(), { 'aaab' })

  child.lua([[MiniStarter.add_to_query('b')]])
  eq(get_active_items_names(), { 'aaab' })

  -- Allows empty string with no effect
  child.lua([[MiniStarter.add_to_query('')]])
  eq(get_active_items_names(), { 'aaab' })

  -- Doesn't allow adding to query resulting into no active items
  child.lua([[MiniStarter.add_to_query('c')]])
  eq(get_active_items_names(), { 'aaab' })
  expect.match(get_latest_message(), 'Query "aaabc".*no active items.*Current query: aaab')
end

T['add_to_query()']['uses `buf_id` argument'] = function()
  child.lua('MiniStarter.open()')
  local buf_id = child.api.nvim_get_current_buf()

  child.lua('MiniStarter.add_to_query(...)', { 'a', buf_id })
  eq(get_active_items_names(buf_id), { 'aaab', 'aaba', 'abaa' })
end

T['add_to_query()']['removes from query with no argument'] = function()
  child.lua([[MiniStarter.add_to_query('a')]])
  child.lua([[MiniStarter.add_to_query('a')]])
  eq(get_active_items_names(), { 'aaab', 'aaba' })

  child.lua('MiniStarter.add_to_query()')
  eq(get_active_items_names(), { 'aaab', 'aaba', 'abaa' })

  child.lua('MiniStarter.add_to_query()')
  eq(get_active_items_names(), { 'aaab', 'aaba', 'abaa', 'baaa' })

  -- Works even when current query is already empty
  child.lua('MiniStarter.add_to_query()')
  eq(get_active_items_names(), { 'aaab', 'aaba', 'abaa', 'baaa' })
end

-- Integration tests ==========================================================
T['Autoopening'] = new_set()

T['Autoopening']['works'] = function()
  child.restart({ '-u', 'tests/dir-starter/init-files/test-init.lua' })
  validate_starter_shown()

  -- It should result into total single buffer
  eq(#child.api.nvim_list_bufs(), 1)

  -- It should trigger `MiniStarterOpened` `User` event
  eq(child.lua_get('_G.n_event'), 1)
end

T['Autoopening']['does not autoopen if Neovim started to show something'] = function()
  local init_autoopen = 'tests/dir-starter/init-files/test-init.lua'
  local validate = function(...)
    child.restart({ '-u', init_autoopen, ... })
    validate_starter_not_shown()
    eq(child.lua_get('_G.n_event'), 0)
  end

  -- There are files in arguments (like `nvim foo.txt` with new file).
  validate('new-file.txt')

  -- Several buffers are listed (like session with placeholder buffers)
  validate('-c', 'e foo | set buflisted | e bar | set buflisted')

  -- Unlisted buffers (like from `nvim-tree`) don't affect decision
  child.restart({ '-u', init_autoopen, '-c', 'e foo | set nobuflisted | e bar | set buflisted' })
  validate_starter_shown()
  eq(child.lua_get('_G.n_event'), 1)

  -- Current buffer is meant to show something else
  validate('-c', 'set filetype=text')

  -- Current buffer has any lines (something opened explicitly)
  validate('-c', [[call setline(1, 'a')]])
end

T['Querying'] = new_set()

T['Querying']['works'] = function()
  -- Make all showed messages full width
  child.o.cmdheight = 2

  reload_module({ items = example_items })
  child.lua('MiniStarter.open()')
  eq(get_active_items_names(), { 'aaab', 'aaba', 'abaa', 'baaa' })

  type_keys('a')
  eq(get_active_items_names(), { 'aaab', 'aaba', 'abaa' })

  type_keys('b')
  eq(get_active_items_names(), { 'abaa' })

  -- Doesn't allow adding to query resulting into no active items
  type_keys('c')
  eq(get_active_items_names(), { 'abaa' })
  expect.match(get_latest_message(), 'Query "abc".*no active items.*Current query: ab')
end

T['Querying']['respects `config.query_updaters`'] = function()
  local validate = function()
    child.lua('MiniStarter.open()')
    eq(get_active_items_names(), { 'aaab', 'aaba', 'abaa', 'baaa' })

    type_keys('a')
    eq(get_active_items_names(), { 'aaab', 'aaba', 'abaa' })

    type_keys('b')
    eq(get_active_items_names(), { 'aaab', 'aaba', 'abaa' })
    eq(get_latest_message(), '')
  end

  reload_module({ items = example_items, query_updaters = 'a' })
  validate()

  -- Should also use buffer local config
  child.lua('MiniStarter.close()')
  reload_module()
  child.b.ministarter_config = { items = example_items, query_updaters = 'a' }
  validate()
end

T['Querying']['respects `config.evaluate_single`'] = function()
  local validate = function()
    child.lua('MiniStarter.open()')
    eq(get_active_items_names(), { 'aaab', 'aaba', 'abaa', 'baaa' })
    child.lua('_G.item_name = nil')

    type_keys('b')
    -- It should reset query along with evaluating item
    eq(get_active_items_names(), { 'aaab', 'aaba', 'abaa', 'baaa' })
    eq(child.lua_get('_G.item_name'), 'baaa')
  end

  reload_module({ evaluate_single = true, items = example_items })
  validate()

  -- Should also use buffer local config
  child.lua('MiniStarter.close()')
  reload_module()
  child.b.ministarter_config = { evaluate_single = true, items = example_items }
  validate()
end

T['Querying']['works with `cmdheight=0`'] = function()
  child.set_size(20, 50)
  child.o.cmdheight = 0
  reload_module({ items = example_items })

  child.lua('MiniStarter.open()')

  -- It should work without giving hit-enter-prompt
  type_keys('a')
  type_keys('a')
  eq(child.api.nvim_get_mode().blocking, false)

  -- There should be no query showed
  child.expect_screenshot()

  -- There shouldn't be hit-enter-prompt after leaving buffer
  type_keys(':bw<CR>')
  eq(child.api.nvim_get_mode().blocking, false)
end

T['Keybindings'] = new_set({
  hooks = {
    pre_case = function()
      reload_module({ items = example_items, content_hooks = {}, header = '', footer = '' })
      child.lua('MiniStarter.open()')
    end,
  },
})

T['Keybindings']['have working <BS>'] = function()
  child.lua([[MiniStarter.set_query('aa')]])
  eq(get_active_items_names(), { 'aaab', 'aaba' })

  type_keys('<BS>')
  eq(get_active_items_names(), { 'aaab', 'aaba', 'abaa' })
end

T['Keybindings']['have working <Esc>'] = function()
  child.lua([[MiniStarter.set_query('aa')]])
  eq(get_active_items_names(), { 'aaab', 'aaba' })

  type_keys('<Esc>')
  eq(get_active_items_names(), { 'aaab', 'aaba', 'abaa', 'baaa' })
end

T['Keybindings']['arrows'] = new_set({
  parametrize = {
    { { down = '<Down>', up = '<Up>' } },
    { { down = '<C-n>', up = '<C-p>' } },
    { { down = '<M-j>', up = '<M-k>' } },
  },
}, {
  function(keys)
    eq(get_lines(), { 'A', 'aaab', 'aaba', '', 'B', 'abaa', 'baaa' })
    eq(get_cursor(), { 2, 0 })

    -- Basics work
    type_keys(keys.down)
    eq(get_cursor(), { 3, 0 })
    type_keys(keys.up)
    eq(get_cursor(), { 2, 0 })

    -- Movement ignores not active items
    child.lua([[MiniStarter.set_query('aa')]])
    eq(get_cursor(), { 2, 0 })

    type_keys(keys.down)
    type_keys(keys.down)
    eq(get_cursor(), { 2, 0 })

    type_keys(keys.up)
    type_keys(keys.up)
    eq(get_cursor(), { 2, 0 })

    -- Works with single active item
    child.lua([[MiniStarter.set_query('aaab')]])
    eq(get_cursor(), { 2, 0 })

    type_keys(keys.down)
    eq(get_cursor(), { 2, 0 })

    type_keys(keys.up)
    eq(get_cursor(), { 2, 0 })
  end,
})

T['Keybindings']['have working <CR>'] = function()
  child.lua([[MiniStarter.set_query('aaab')]])
  eq(get_active_items_names(), { 'aaab' })
  child.lua('_G.item_name = nil')

  type_keys('<CR>')
  eq(child.lua_get('_G.item_name'), 'aaab')
end

T['Keybindings']['have working <C-c>'] = function()
  validate_starter_shown()
  type_keys('<C-c>')
  validate_starter_not_shown()
end

T['Highlighting'] = new_set({
  hooks = {
    pre_case = function()
      reload_module({ items = example_items, content_hooks = {}, header = 'Hello', footer = 'World' })
      child.set_size(15, 40)
    end,
  },
})

T['Highlighting']['works for querying'] = function()
  child.lua('MiniStarter.open()')
  child.expect_screenshot()

  type_keys('a')
  child.expect_screenshot()

  type_keys('b')
  child.expect_screenshot()
end

T['Highlighting']['works for current item'] = function()
  child.cmd('hi MiniStarterCurrent ctermbg=1')
  child.lua('MiniStarter.open()')
  child.expect_screenshot()

  type_keys('<Down>')
  child.expect_screenshot()
end

T['Highlighting']['uses `MiniStarterItemBullet`'] = function()
  reload_from_strconfig({
    items = example_itemstring,
    content_hooks = '{ require("mini.starter").gen_hook.adding_bullet() }',
    header = [['']],
    footer = [['']],
  })
  child.lua('MiniStarter.open()')
  child.expect_screenshot()

  -- Should now show bullets same as prefix
  child.cmd('hi! link MiniStarterItemBullet MiniStarterItemPrefix')
  child.cmd('redraw')
  child.expect_screenshot()
end

T['Cursor positioning'] = new_set({
  hooks = {
    pre_case = function() reload_module({ items = example_items, content_hooks = {}, header = '', footer = '' }) end,
  },
})

T['Cursor positioning']['reacts to keys'] = function()
  child.lua('MiniStarter.open()')
  eq(get_lines(), { 'A', 'aaab', 'aaba', '', 'B', 'abaa', 'baaa' })
  eq(get_cursor(), { 2, 0 })

  type_keys('<Down>')
  eq(get_cursor(), { 3, 0 })

  type_keys('<Down>')
  eq(get_cursor(), { 6, 0 })

  type_keys('<Down><Down>')
  eq(get_cursor(), { 2, 0 })

  type_keys('<Up>')
  eq(get_cursor(), { 7, 0 })
end

T['Cursor positioning']['updates when current item becomes inactive'] = function()
  child.lua('MiniStarter.open()')
  eq(get_cursor(), { 2, 0 })

  child.lua([[MiniStarter.set_query('baaa')]])
  eq(get_cursor(), { 7, 0 })

  -- It should stay the same even if previous item again becomes active
  child.lua([[MiniStarter.set_query('')]])
  eq(get_cursor(), { 7, 0 })
end

T['Cursor positioning']['works with bullets'] = new_set({
  parametrize = { { true, { 2, 0 }, { 3, 0 } }, { false, { 2, 4 }, { 3, 4 } } },
}, {
  test = function(place_cursor, cursor_start, cursor_finish)
    reload_from_strconfig({
      items = example_itemstring,
      content_hooks = ('{ require("mini.starter").gen_hook.adding_bullet(nil, %s) }'):format(place_cursor),
      header = [['']],
      footer = [['']],
    })

    child.lua('MiniStarter.open()')
    eq(get_lines(), { 'A', '░ aaab', '░ aaba', '', 'B', '░ abaa', '░ baaa' })
    eq(get_cursor(), cursor_start)

    type_keys('<Down>')
    eq(get_cursor(), cursor_finish)
  end,
})

T['Resize'] = new_set()

T['Resize']['updates Starter buffer'] = function()
  child.lua('MiniStarter.config.items = ' .. example_itemstring)
  child.lua('MiniStarter.config.header = "Header"')
  child.lua('MiniStarter.config.footer = "Footer"')

  child.set_size(12, 20)
  child.lua('MiniStarter.open()')

  child.set_size(20, 40)
  child.expect_screenshot()
end

T['Multiple buffers'] = new_set()

T['Multiple buffers']['are allowed'] = function()
  child.lua('MiniStarter.config.items = ' .. example_itemstring)
  child.cmd('autocmd TabNewEntered * lua MiniStarter.open(vim.api.nvim_get_current_buf())')

  child.lua('MiniStarter.open()')
  local buf_id_1 = child.api.nvim_get_current_buf()
  child.lua([[MiniStarter.set_query('aa')]])
  eq(get_active_items_names(buf_id_1), { 'aaab', 'aaba' })

  -- It should open new Starter buffer while keeping previous one
  child.cmd('tabe')
  validate_starter_shown()
  eq(child.api.nvim_buf_get_name(0), 'ministarter://' .. child.api.nvim_get_current_buf() .. '/welcome')

  eq(child.api.nvim_buf_is_valid(buf_id_1), true)
  eq(child.api.nvim_buf_get_option(buf_id_1, 'filetype'), 'ministarter')
  eq(get_active_items_names(), { 'aaab', 'aaba', 'abaa', 'baaa' })

  -- State of first Starter buffer should not be affected by second one
  child.cmd('tabc')
  eq(get_active_items_names(), { 'aaab', 'aaba' })
end

return T
