-- NOTE: These are basic tests which cover basic functionliaty. A lot of
-- nuances are not tested to meet "complexity-necessity" trade-off.
local helpers = dofile('tests/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local eq_partial_tbl = helpers.expect.equality_partial_tbl
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('completion', config) end
local unload_module = function() child.mini_unload('completion') end
local reload_module = function(config) unload_module(); load_module(config) end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
local sleep = function(ms) helpers.sleep(ms, child, true) end
local mock_lsp = function() child.cmd('luafile tests/mock-lsp/months.lua') end
local new_buffer = function() child.api.nvim_set_current_buf(child.api.nvim_create_buf(true, false)) end
--stylua: ignore end

local forward_lua = function(fun_str)
  local lua_cmd = fun_str .. '(...)'
  return function(...) return child.lua_get(lua_cmd, { ... }) end
end

local mock_miniicons = function()
  child.lua([[
    require('mini.icons').setup()
    local _, hl_text = MiniIcons.get('lsp', 'Text')
    local _, hl_function = MiniIcons.get('lsp', 'Function')
    _G.ref_hlgroup = { text = hl_text, func = hl_function}
  ]])
end

local mock_completefunc_lsp_tracking = function()
  child.lua([[
    local completefunc_lsp_orig = MiniCompletion.completefunc_lsp
    MiniCompletion.completefunc_lsp = function(...)
      _G.n_completfunc_lsp = (_G.n_completfunc_lsp or 0) + 1
      return completefunc_lsp_orig(...)
    end
  ]])
end

local mock_lsp_items = function(items, client_id)
  child.lua('_G.input_items = ' .. vim.inspect(items))
  child.lua('_G.client_id = ' .. (client_id or 1))
  child.lua([[
    MiniCompletion.config.lsp_completion.process_items = function(_, base)
      local items = vim.deepcopy(_G.input_items)
      -- Ensure same order
      for i, _ in ipairs(items) do
        items[i].sortText = string.format('%03d', i)
        items[i].client_id = _G.client_id
      end
      return MiniCompletion.default_process_items(items, base)
    end
  ]])
end

local mock_event_log = function()
  child.lua([[
    _G.log = {}
    local events = { 'MiniCompletionWindowOpen', 'MiniCompletionWindowUpdate' }
    local log_event = function(ev)
      table.insert(_G.log, { event = ev.match, data = ev.data })
    end
    vim.api.nvim_create_autocmd('User', { pattern = events, callback = log_event })
  ]])
end

local mock_custom_window_config = function()
  child.lua([[
    vim.api.nvim_create_autocmd('User', {
      pattern = { 'MiniCompletionWindowOpen', 'MiniCompletionWindowUpdate' },
      callback = function(ev)
        local config = vim.api.nvim_win_get_config(ev.data.win_id)
        config.title, config.title_pos = 'Custom', 'right'
        vim.api.nvim_win_set_config(ev.data.win_id, config)
      end,
    })
  ]])
end

-- NOTE: this can't show "what filtered text is actually shown in window".
-- Seems to be because information for `complete_info()`
--- is updated in the very last minute (probably, by UI). This means that the
--- idea of "Type <C-n> -> get selected item" loop doesn't work (because
--- "selected item" is not updated). Can't find a way to force its update.
---
--- Using screen tests to get information about actually shown filtered items.
---
--- More info: https://github.com/vim/vim/issues/10007
local get_completion = function(what)
  what = what or 'word'
  return vim.tbl_map(function(x) return x[what] end, child.fn.complete_info().items)
end

local get_floating_windows = function()
  return vim.tbl_filter(
    function(x) return child.api.nvim_win_get_config(x).relative ~= '' end,
    child.api.nvim_list_wins()
  )
end

local validate_single_floating_win = function(opts)
  opts = opts or {}
  local wins = get_floating_windows()
  eq(#wins, 1)

  local win_id = wins[1]
  if opts.lines ~= nil then
    local buf_id = child.api.nvim_win_get_buf(win_id)
    local lines = child.api.nvim_buf_get_lines(buf_id, 0, -1, true)
    eq(lines, opts.lines)
  end
  if opts.config ~= nil then
    local true_config = child.api.nvim_win_get_config(win_id)
    local compare_config = {}
    for key, _ in pairs(opts.config) do
      compare_config[key] = true_config[key]
    end
    eq(compare_config, opts.config)
  end
end

-- Time constants
local default_completion_delay, default_info_delay, default_signature_delay = 100, 100, 50
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
  eq(child.lua_get('type(_G.MiniCompletion)'), 'table')

  -- Autocommand group
  eq(child.fn.exists('#MiniCompletion'), 1)

  -- Highlight groups
  child.cmd('hi clear')
  load_module()
  expect.match(child.cmd_capture('hi MiniCompletionActiveParameter'), 'links to LspSignatureActiveParameter')
  expect.match(child.cmd_capture('hi MiniCompletionInfoBorderOutdated'), 'links to DiagnosticFloatingWarn')
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniCompletion.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniCompletion.config.' .. field), value) end

  expect_config('delay.completion', 100)
  expect_config('delay.info', 100)
  expect_config('delay.signature', 50)
  expect_config('window.info.height', 25)
  expect_config('window.info.width', 80)
  expect_config('window.info.border', vim.NIL)
  expect_config('window.signature.height', 25)
  expect_config('window.signature.width', 80)
  expect_config('window.signature.border', vim.NIL)
  expect_config('lsp_completion.source_func', 'completefunc')
  expect_config('lsp_completion.auto_setup', true)
  expect_config('lsp_completion.process_items', vim.NIL)
  expect_config('lsp_completion.snippet_insert', vim.NIL)
  expect_config('fallback_action', '<C-n>')
  expect_config('mappings.force_twostep', '<C-Space>')
  expect_config('mappings.force_fallback', '<A-Space>')
  expect_config('mappings.scroll_down', '<C-f>')
  expect_config('mappings.scroll_up', '<C-b>')
end

T['setup()']['respects `config` argument'] = function()
  -- Check setting `MiniCompletion.config` fields
  reload_module({ delay = { completion = 300 } })
  eq(child.lua_get('MiniCompletion.config.delay.completion'), 300)
end

T['setup()']['validates `config` argument'] = function()
  unload_module()

  local expect_config_error = function(config, name, target_type)
    expect.error(load_module, vim.pesc(name) .. '.*' .. vim.pesc(target_type), config)
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ delay = 'a' }, 'delay', 'table')
  expect_config_error({ delay = { completion = 'a' } }, 'delay.completion', 'number')
  expect_config_error({ delay = { info = 'a' } }, 'delay.info', 'number')
  expect_config_error({ delay = { signature = 'a' } }, 'delay.signature', 'number')
  expect_config_error({ window = 'a' }, 'window', 'table')
  expect_config_error({ window = { info = 'a' } }, 'window.info', 'table')
  expect_config_error({ window = { info = { height = 'a' } } }, 'window.info.height', 'number')
  expect_config_error({ window = { info = { width = 'a' } } }, 'window.info.width', 'number')
  expect_config_error({ window = { info = { border = 1 } } }, 'window.info.border', 'string or array')
  expect_config_error({ window = { signature = 'a' } }, 'window.signature', 'table')
  expect_config_error({ window = { signature = { height = 'a' } } }, 'window.signature.height', 'number')
  expect_config_error({ window = { signature = { width = 'a' } } }, 'window.signature.width', 'number')
  expect_config_error({ window = { signature = { border = 1 } } }, 'window.signature.border', 'string or array')
  expect_config_error({ lsp_completion = 'a' }, 'lsp_completion', 'table')
  expect_config_error(
    { lsp_completion = { source_func = 'a' } },
    'lsp_completion.source_func',
    '"completefunc" or "omnifunc"'
  )
  expect_config_error({ lsp_completion = { auto_setup = 'a' } }, 'lsp_completion.auto_setup', 'boolean')
  expect_config_error({ lsp_completion = { process_items = 'a' } }, 'lsp_completion.process_items', 'callable')
  expect_config_error({ lsp_completion = { snippet_insert = 'a' } }, 'lsp_completion.snippet_insert', 'callable')
  expect_config_error({ fallback_action = 1 }, 'fallback_action', 'function or string')
  expect_config_error({ mappings = 'a' }, 'mappings', 'table')
  expect_config_error({ mappings = { force_twostep = 1 } }, 'mappings.force_twostep', 'string')
  expect_config_error({ mappings = { force_fallback = 1 } }, 'mappings.force_fallback', 'string')
  expect_config_error({ mappings = { scroll_down = 1 } }, 'mappings.scroll_down', 'string')
  expect_config_error({ mappings = { scroll_up = 1 } }, 'mappings.scroll_up', 'string')
end

T['setup()']['ensures colors'] = function()
  child.cmd('colorscheme default')
  expect.match(child.cmd_capture('hi MiniCompletionActiveParameter'), 'links to LspSignatureActiveParameter')
end

T['setup()']['properly handles `config.mappings`'] = function()
  local has_map = function(lhs, pattern) return child.cmd_capture('imap ' .. lhs):find(pattern) ~= nil end
  eq(has_map('<C-Space>', 'Complete'), true)

  unload_module()
  child.api.nvim_del_keymap('i', '<C-Space>')

  -- Supplying empty string should mean "don't create keymap"
  load_module({ mappings = { force_twostep = '' } })
  eq(has_map('<C-Space>', 'Complete'), false)
end

T['setup()']['uses `config.lsp_completion`'] = function()
  local validate = function(auto_setup, source_func)
    reload_module({ lsp_completion = { auto_setup = auto_setup, source_func = source_func } })
    local buf_id = child.api.nvim_create_buf(true, false)
    child.api.nvim_set_current_buf(buf_id)

    local omnifunc, completefunc
    if auto_setup == false then
      omnifunc, completefunc = '', ''
    else
      local val = 'v:lua.MiniCompletion.completefunc_lsp'
      omnifunc = source_func == 'omnifunc' and val or ''
      completefunc = source_func == 'completefunc' and val or ''
    end

    eq(child.bo.omnifunc, omnifunc)
    eq(child.bo.completefunc, completefunc)
  end

  validate(false)
  validate(true, 'omnifunc')
  validate(true, 'completefunc')
end

T['setup()']['sets recommended option values'] = function()
  expect.match(child.o.shortmess, 'c')
  expect.match(child.o.shortmess, 'C')
  eq(child.o.completeopt, 'menuone,noselect')

  -- Should not set if was previously set
  child.o.shortmess = 'ltToO'
  child.o.completeopt = 'menu,noinsert'
  reload_module()
  eq(child.o.shortmess, 'ltToO')
  eq(child.o.completeopt, 'menu,noinsert')
end

T['default_process_items()'] = new_set({
  hooks = {
    pre_case = function()
      -- Mock LSP items
      child.lua([[
        _G.items = {
          { kind = 1,   label = "January",  sortText = "001" },
          { kind = 2,   label = "May",      sortText = "005" },
          { kind = 2,   label = "March",    sortText = "003" },
          { kind = 2,   label = "April",    sortText = "004" },
          { kind = 1,   label = "February", sortText = "002" },
          -- Unknown kind
          { kind = 100, label = "July",     sortText = "007" },
          { kind = 3,   label = "June",     sortText = "006" },
        }
      ]])
    end,
  },
})

local default_process_items = forward_lua('MiniCompletion.default_process_items')

local ref_prefix_items = {
  { kind = 2, label = 'March', sortText = '003' },
  { kind = 2, label = 'May', sortText = '005' },
}

local ref_fuzzy_items = {
  { kind = 100, label = 'July', sortText = '007' },
  { kind = 2, label = 'April', sortText = '004' },
}

T['default_process_items()']['works'] = function()
  -- Should use 'prefix' filtersort if no 'fuzzy' in 'completeopt'
  eq(child.lua_get('MiniCompletion.default_process_items(_G.items, "M")'), ref_prefix_items)

  -- Should use 'fuzzy' filtersort if there is 'fuzzy' in 'completeopt'
  if child.fn.has('nvim-0.11') == 0 then MiniTest.skip("Only Neovim>=0.11 has 'fuzzy' flag in 'completeopt'") end
  child.o.completeopt = 'menuone,noselect,fuzzy'
  eq(child.lua_get('MiniCompletion.default_process_items(_G.items, "l")'), ref_fuzzy_items)
end

T['default_process_items()']["highlights LSP kind if 'mini.icons' is enabled"] = function()
  if child.fn.has('nvim-0.11') == 0 then MiniTest.skip("'kind_hlgroup' field is present on Neovim>=0.11") end

  mock_miniicons()
  local ref_hlgroup = child.lua_get('_G.ref_hlgroup')
  local ref_processed_items = {
    { kind = 1, kind_hlgroup = ref_hlgroup.text, label = 'January', sortText = '001' },
    { kind = 3, kind_hlgroup = ref_hlgroup.func, label = 'June', sortText = '006' },
    -- Unknown kind should not get highlighted
    { kind = 100, kind_hlgroup = nil, label = 'July', sortText = '007' },
  }
  eq(child.lua_get('MiniCompletion.default_process_items(_G.items, "J")'), ref_processed_items)

  -- Should not modify original items
  eq(child.lua_get('_G.items[1].kind_hlgroup'), vim.NIL)
end

T['default_process_items()']['works after `MiniIcons.tweak_lsp_kind()`'] = function()
  mock_miniicons()
  child.lua('MiniIcons.tweak_lsp_kind()')

  local ref_hlgroup = child.lua_get('_G.ref_hlgroup')
  local ref_processed_items = {
    { kind = 1, kind_hlgroup = ref_hlgroup.text, label = 'January', sortText = '001' },
    { kind = 3, kind_hlgroup = ref_hlgroup.func, label = 'June', sortText = '006' },
    -- Unknown kind should not get highlighted
    { kind = 100, kind_hlgroup = nil, label = 'July', sortText = '007' },
  }
  eq(child.lua_get('MiniCompletion.default_process_items(_G.items, "J")'), ref_processed_items)
end

T['default_process_items()']['respects `opts.filtersort`'] = function()
  local all_items = child.lua_get('_G.items')
  local validate = function(method, base, ref)
    child.lua('_G.method = ' .. vim.inspect(method))
    child.lua('_G.base = ' .. vim.inspect(base))
    local out = child.lua([[
      local copy_items = vim.deepcopy(_G.items)
      local processed = MiniCompletion.default_process_items(_G.items, _G.base, { filtersort = _G.method })
      local res = vim.deepcopy(processed)
      if processed[1] ~= nil then processed[1].new_field = 'hello' end
      return { processed = res, returns_copy = _G.items[1].new_field == nil}
    ]])
    eq(out.processed, ref)
    eq(out.returns_copy, true)
  end

  validate(nil, 'l', {})
  validate('fuzzy', 'l', ref_fuzzy_items)
  validate('none', 'l', all_items)

  -- Should return all items with empty string base
  local all_items_sorted = vim.deepcopy(all_items)
  table.sort(all_items_sorted, function(a, b) return (a.sortText or a.label) < (b.sortText or b.label) end)

  validate(nil, '', all_items_sorted)
  validate('fuzzy', '', all_items)
  validate('none', '', all_items)

  -- Should allow callable `filtersort`
  child.lua([[
    _G.args = {}
    local filtersort = function(...)
      table.insert(_G.args, { ... })
      return { { label = 'New item' } }
    end
    _G.processed = MiniCompletion.default_process_items(_G.items, "l", { filtersort = filtersort })
  ]])
  eq(child.lua_get('_G.processed'), { { label = 'New item' } })
  eq(child.lua_get('_G.args'), { { all_items, 'l' } })
end

T['default_process_items()']['prefers match at start instead of camel case at end'] = function()
  if child.fn.has('nvim-0.12') == 0 then MiniTest.skip('Only Neovim>=0.12 has improved fuzzy matching support') end

  local items = {
    { kind = 1, label = 'MyClass' },
    { kind = 1, label = 'Class' },
    { kind = 1, label = 'MyOtherClass' },
  }
  child.lua('_G.items = ' .. vim.inspect(items))
  local out = child.lua_get('MiniCompletion.default_process_items(_G.items, "Cl", { filtersort = "fuzzy" })')
  eq(out, { items[2], items[1], items[3] })
end

T['default_process_items()']['respects `opts.kind_priority`'] = function()
  local kind_map = child.lua([[
    _G.kind_map = {}
    for k, v in pairs(vim.lsp.protocol.CompletionItemKind) do
      if type(k) == 'string' then _G.kind_map[k] = v end
    end
    return _G.kind_map
  ]])

  -- Should work even if `vim.lsp.protocol.CompletionItemKind` is tweaked
  mock_miniicons()
  child.lua('MiniIcons.tweak_lsp_kind()')

  local items = {
    { label = 'a', kind = kind_map.Function },
    { label = 'b', kind = kind_map.Snippet },
    { label = 'c', kind = kind_map.Text },
    { label = 'd', kind = kind_map.Function },
    { label = 'e', kind = kind_map.Variable },
    { label = 'f', kind = kind_map.Text },
    { label = 'g', kind = kind_map.Variable },
    -- Should work with unknown/missing kind (with default priority of 100)
    { label = 'h', kind = -13 },
    { label = 'i', kind = 3.14 },
    { label = 'j', kind = nil },
  }
  local opts = { kind_priority = { Variable = 101, Snippet = 99, Text = -1 } }
  --stylua: ignore
  local ref_items = {
    items[5], items[7], -- priority 101
    items[1], items[4], items[8], items[9], items[10], -- priority 100
    items[2], -- priority 99
    -- No items for negative priority
  }
  eq_partial_tbl(default_process_items(items, '', opts), ref_items)

  -- Should apply after `filtersort` and preserve its order within priority
  items = {
    { label = 'ba', kind = kind_map.Snippet },
    { label = 'ca', kind = kind_map.Variable },
    { label = 'ea', kind = kind_map.Text },
    { label = 'da', kind = kind_map.Function },

    { label = 'ac', kind = kind_map.Variable },
    { label = 'ab', kind = kind_map.Snippet },
    { label = 'ad', kind = kind_map.Function },
    { label = 'ae', kind = kind_map.Text },

    { label = 'xx', kind = kind_map.Variable },

    { label = 'cca', kind = kind_map.Variable },
  }
  opts = { filtersort = 'fuzzy', kind_priority = { Variable = 101, Snippet = 99, Text = -1 } }
  --stylua: ignore
  ref_items = {
    items[5], items[2], items[10], -- priority 101
    items[7], items[4],            -- priority 100
    items[6], items[1],            -- priority 99
  }
  eq_partial_tbl(default_process_items(items, 'a', opts), ref_items)
end

T['default_process_items()']['validates input'] = function()
  expect.error(
    function() child.lua('MiniCompletion.default_process_items({}, "", { filtersort = 1 })') end,
    '`filtersort`.*callable or one of'
  )
  expect.error(
    function() child.lua('MiniCompletion.default_process_items({}, "", { kind_priority = 1 })') end,
    '`kind_priority`.*table'
  )
end

T['get_lsp_capabilities()'] = new_set()

T['get_lsp_capabilities()']['works'] = function()
  local validate_keys = function(x, ref_keys)
    local keys = vim.tbl_keys(x)
    table.sort(keys)
    eq(keys, ref_keys)
  end

  local out = child.lua_get('MiniCompletion.get_lsp_capabilities()')
  validate_keys(out, { 'textDocument' })
  validate_keys(out.textDocument, { 'completion', 'signatureHelp' })
  --stylua: ignore
  local completion_keys = {
    'completionItem', 'completionItemKind', 'completionList',
    'contextSupport', 'dynamicRegistration', 'insertTextMode',
  }
  validate_keys(out.textDocument.completion, completion_keys)
  validate_keys(out.textDocument.signatureHelp, { 'contextSupport', 'dynamicRegistration', 'signatureInformation' })

  local ref_resolve_properties = { 'additionalTextEdits', 'detail', 'documentation' }
  eq(out.textDocument.completion.completionItem.resolveSupport.properties, ref_resolve_properties)
end

T['get_lsp_capabilities()']['respects `opts.resolve_additional_text_edits`'] = function()
  local validate = function(out, ref_resolve_properties)
    eq(out.textDocument.completion.completionItem.resolveSupport.properties, ref_resolve_properties)
  end
  local out_false = child.lua_get('MiniCompletion.get_lsp_capabilities({ resolve_additional_text_edits = false })')
  validate(out_false, { 'detail', 'documentation' })
  local out_true = child.lua_get('MiniCompletion.get_lsp_capabilities({ resolve_additional_text_edits = true })')
  validate(out_true, { 'additionalTextEdits', 'detail', 'documentation' })
end

-- Integration tests ==========================================================
T['Autocompletion'] = new_set({
  hooks = {
    pre_case = function()
      -- Create new buffer to set buffer-local `completefunc` or `omnifunc`
      new_buffer()
      -- For details see 'mock-lsp/months.lua'
      mock_lsp()
    end,
  },
})

T['Autocompletion']['works with LSP client'] = function()
  type_keys('i', 'J')
  eq(get_completion(), {})

  -- Shows completion only after delay
  sleep(default_completion_delay - small_time)
  eq(get_completion(), {})
  sleep(small_time + small_time)
  -- Both completion word and kind are shown
  eq(get_completion(), { 'January', 'June', 'July' })
  eq(get_completion('kind'), { 'Text', 'Function', 'Function' })

  -- Completion menu is filtered after entering characters
  type_keys('u')
  child.set_size(10, 20)
  child.expect_screenshot()
end

T['Autocompletion']['works without LSP clients'] = function()
  child.lsp.buf_detach_client(0, child.lua_get('_G.months_lsp_client_id'))

  type_keys('i', 'aab aac aba a')
  eq(get_completion(), {})
  sleep(default_completion_delay - small_time)
  eq(get_completion(), {})
  sleep(small_time + small_time)
  eq(get_completion(), { 'aab', 'aac', 'aba' })

  -- Completion menu is filtered after entering characters
  type_keys('a')
  child.set_size(10, 20)
  child.expect_screenshot()
end

T['Autocompletion']['implements debounce-style delay'] = function()
  type_keys('i', 'J')

  sleep(default_completion_delay - small_time)
  eq(get_completion(), {})
  type_keys('u')
  sleep(default_completion_delay - small_time)
  eq(get_completion(), {})
  sleep(small_time + small_time)
  eq(get_completion(), { 'June', 'July' })
end

T['Autocompletion']['uses fallback'] = function()
  set_lines({ 'Jackpot', '' })
  set_cursor(2, 0)

  type_keys('i', 'Ja')
  sleep(default_completion_delay + small_time)
  eq(get_completion(), { 'January' })

  -- Due to how 'completefunc' and 'omnifunc' currently work, fallback won't
  -- trigger after the first character which lead to empty completion list.
  -- The reason seems to be that at that point Neovim's internal filtering of
  -- completion items is still "in charge" (backspace leads to previous
  -- completion item list without reevaluating completion function). It is
  -- only after the next character completion function gets reevaluated
  -- leading to zero items from LSP which triggers fallback action.
  type_keys('c')
  eq(child.fn.pumvisible(), 0)
  type_keys('k')
  eq(get_completion(), { 'Jackpot' })
end

T['Autocompletion']['forces new LSP completion at LSP trigger'] = new_set(
  -- Test with different source functions because they (may) differ slightly on
  -- how certain completion events (`CompleteDonePre`) are triggered, which
  -- affects whether autocompletion is done in certain cases (for example, when
  -- completion candidate is fully typed).
  -- See https://github.com/nvim-mini/mini.nvim/issues/813
  { parametrize = { { 'completefunc' }, { 'omnifunc' } } },
  {
    test = function(source_func)
      reload_module({ lsp_completion = { source_func = source_func } })
      mock_completefunc_lsp_tracking()
      child.set_size(16, 20)
      child.api.nvim_set_current_buf(child.api.nvim_create_buf(true, false))

      --stylua: ignore
      local all_months = {
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December',
      }
      type_keys('i', '<C-Space>')
      eq(get_completion(), all_months)
      -- - Should only call two times, as per `:h complete-functions`, i.e. not
      --   use it to actually make request (which would have made it 3 times).
      eq(child.lua_get('_G.n_completfunc_lsp'), 2)

      type_keys('May.')
      eq(child.lua_get('_G.n_completfunc_lsp'), 2)
      eq(child.fn.pumvisible(), 0)
      sleep(default_completion_delay - small_time)
      eq(child.fn.pumvisible(), 0)
      sleep(small_time + small_time)
      eq(get_completion(), all_months)
      eq(child.lua_get('_G.n_completfunc_lsp'), 4)
      child.expect_screenshot()

      -- Should show only LSP without fallback, i.e. typing LSP trigger should
      -- show no completion if there is no LSP completion (as is imitated
      -- inside commented lines).
      type_keys('<Esc>o', '# .')
      sleep(default_completion_delay + small_time)
      child.expect_screenshot()
    end,
  }
)

T['Autocompletion']['works with `<BS>`'] = function()
  mock_completefunc_lsp_tracking()
  child.set_size(10, 20)
  child.api.nvim_set_current_buf(child.api.nvim_create_buf(true, false))

  type_keys('i', 'J', 'u', '<C-Space>')
  -- - Should only call two times, as per `:h complete-functions`: first to
  --   find the start column, second to return completion suggestions.
  eq(child.lua_get('_G.n_completfunc_lsp'), 2)

  type_keys('n')
  child.expect_screenshot()
  eq(child.lua_get('_G.n_completfunc_lsp'), 2)

  -- Should keep completion menu and adjust items without extra 'completefunc'
  -- calls (as it is still at or after initial start column)
  type_keys('<BS>')
  child.expect_screenshot()
  eq(child.lua_get('_G.n_completfunc_lsp'), 2)

  -- Should reevaluate completion list as it is past initial start column
  type_keys('<BS>')
  child.expect_screenshot()
  -- - Should call three times: first to make a request, second and third to
  --   act as a regular 'completefunc'/'omnifunc'
  eq(child.lua_get('_G.n_completfunc_lsp'), 5)
end

T['Autocompletion']['forces new LSP completion in case of `isIncomplete`'] = function()
  child.lua('_G.lines_at_request = {}')
  mock_completefunc_lsp_tracking()
  child.set_size(10, 20)
  child.api.nvim_set_current_buf(child.api.nvim_create_buf(true, false))

  -- Mock incomplete completion list which contains only months 1-6
  child.lua('_G.mock_isincomplete = true')
  type_keys('i', 'J', '<C-Space>')
  -- - Should not contain `July` as it is not in the response
  child.expect_screenshot()
  eq(child.lua_get('_G.n_textdocument_completion'), 1)
  -- - Should only call two times, as per `:h complete-functions`: first to
  --   find the start column, second to return completion suggestions.
  eq(child.lua_get('_G.n_completfunc_lsp'), 2)
  eq(child.lua_get('_G.lines_at_request'), { 'J' })

  -- Should force new request which this time will be complete
  child.lua('_G.mock_isincomplete = false')
  type_keys('u')
  child.expect_screenshot()
  eq(child.lua_get('_G.n_textdocument_completion'), 2)
  -- - NOTE: not using completefunc to make an LSP request is a key to reduce
  --   flickering in this use case (as executing `<C-x>...` forces popup hide).
  eq(child.lua_get('_G.n_completfunc_lsp'), 4)
  -- - Should request when line is up to date (i.e. not *exactly* inside
  --   `InsertCharPre`).
  eq(child.lua_get('_G.lines_at_request'), { 'J', 'Ju' })

  -- Shouldn't force new requests or call 'completefunc' for complete responses
  type_keys('n')
  eq(child.lua_get('_G.n_textdocument_completion'), 2)
  eq(child.lua_get('_G.n_completfunc_lsp'), 4)
  eq(child.lua_get('_G.lines_at_request'), { 'J', 'Ju' })
  type_keys('<BS>')
  eq(child.lua_get('_G.n_textdocument_completion'), 2)
  eq(child.lua_get('_G.n_completfunc_lsp'), 4)
  eq(child.lua_get('_G.lines_at_request'), { 'J', 'Ju' })

  -- Should force new request if deleting past the start of previous request.
  -- This time response will be complete.
  type_keys('<BS>')
  child.expect_screenshot()
  eq(child.lua_get('_G.n_textdocument_completion'), 3)
  -- - Should call three times: first to make a request, second and third to
  --   act as a regular 'completefunc'/'omnifunc'
  eq(child.lua_get('_G.n_completfunc_lsp'), 7)
  eq(child.lua_get('_G.lines_at_request'), { 'J', 'Ju', 'J' })
end

T['Autocompletion']['forces new LSP completion for `isIncomplete` even if canceled'] = function()
  child.lua('_G.lines_at_request = {}')
  child.set_size(10, 20)
  child.api.nvim_set_current_buf(child.api.nvim_create_buf(true, false))

  child.lua('_G.mock_request_delay = ' .. small_time)

  -- Mock incomplete completion list which contains only months 1-6
  child.lua('_G.mock_isincomplete = true')
  type_keys('i', 'J', '<C-Space>')
  sleep(small_time + small_time)
  eq(child.lua_get('_G.lines_at_request'), { 'J' })

  -- Should force two requests even though the first one was canceled due to
  -- fast typing
  child.lua('_G.mock_isincomplete = false')
  type_keys('u', 'l')
  sleep(small_time + small_time)
  child.expect_screenshot()
  eq(child.lua_get('_G.lines_at_request'), { 'J', 'Ju', 'Jul' })
end

T['Autocompletion']['sends proper context in request'] = function()
  child.lua('MiniCompletion.config.delay.completion = ' .. small_time)
  -- Make sure that `CompleteDonePre` event is not triggered after typing `.`
  child.o.iskeyword = '@,48-57,_,192-255,.'

  local trigger_kinds = child.lua([[
    local res = {}
    for k, v in pairs(vim.lsp.protocol.CompletionTriggerKind) do
      if type(k) == 'string' then res[k] = v end
    end
    return res
  ]])
  local validate_latest_request_context = function(ref_context)
    local latest_params = child.lua_get('_G.params_log[#_G.params_log]')
    eq(latest_params.method, 'textDocument/completion')
    eq(latest_params.params.context, ref_context)
  end

  -- First request is done after typing non-trigger character
  child.lua('_G.mock_isincomplete = true')
  type_keys('i', 'J')
  sleep(small_time + small_time)
  validate_latest_request_context({ triggerKind = trigger_kinds.Invoked })

  -- Second request is done automatically due to `isIncomplete`
  type_keys('u')
  sleep(small_time + small_time)
  validate_latest_request_context({ triggerKind = trigger_kinds.TriggerForIncompleteCompletions })

  -- Third request is done after typing trigger character, although there is
  -- still `isIncomplete` after previous request
  type_keys('.')
  sleep(small_time + small_time)
  validate_latest_request_context({ triggerKind = trigger_kinds.TriggerCharacter, triggerCharacter = '.' })
end

T['Autocompletion']['respects `config.delay.completion`'] = function()
  child.lua('MiniCompletion.config.delay.completion = ' .. (2 * default_completion_delay))

  type_keys('i', 'J')
  sleep(2 * default_completion_delay - small_time)
  eq(get_completion(), {})
  sleep(small_time + small_time)
  eq(get_completion(), { 'January', 'June', 'July' })

  -- Should also use buffer local config
  child.ensure_normal_mode()
  set_lines({ '' })
  set_cursor(1, 0)
  child.b.minicompletion_config = { delay = { completion = default_completion_delay } }
  type_keys('i', 'J')
  sleep(default_completion_delay - small_time)
  eq(get_completion(), {})
  sleep(small_time + small_time)
  eq(get_completion(), { 'January', 'June', 'July' })
end

T['Autocompletion']['respects `config.lsp_completion.process_items`'] = function()
  child.lua('_G.process_items = function(items, base) return { items[2], items[3] } end')
  child.lua('MiniCompletion.config.lsp_completion.process_items = _G.process_items')

  type_keys('i', 'J')
  sleep(default_completion_delay + small_time)
  eq(get_completion(), { 'February', 'March' })

  child.ensure_normal_mode()
  set_lines({ '' })
  set_cursor(1, 0)
  child.lua('_G.process_items_2 = function(items, base) return { items[4], items[5] } end')
  child.lua('vim.b.minicompletion_config = { lsp_completion = { process_items = _G.process_items_2 } }')

  type_keys('i', 'J')
  sleep(default_completion_delay + small_time)
  eq(get_completion(), { 'April', 'May' })
end

T['Autocompletion']['calls `config.lsp_completion.process_items` once for several servers'] = function()
  child.lua([[
    require('mini.snippets').setup({ snippets = { { prefix = 'Jav', body = 'Java snippet' } } })
    MiniSnippets.start_lsp_server()

    _G.log = {}
    MiniCompletion.config.lsp_completion.process_items = function(items, base)
      table.insert(_G.log, items)
      return MiniCompletion.default_process_items(items, base)
    end
  ]])

  type_keys('i', 'J')
  sleep(default_completion_delay + small_time)
  eq(get_completion(), { 'January', 'June', 'July', 'Java snippet' })

  local log = child.lua_get('_G.log')
  eq(#log, 1)
  eq(log[1][1].label, 'January')
  eq(log[1][#log[1]].label, 'Jav')
end

T['Autocompletion']['respects string `config.fallback_action`'] = function()
  child.set_size(10, 25)
  child.lua([[MiniCompletion.config.fallback_action = '<C-x><C-l>']])

  set_lines({ 'Line number 1', '' })
  set_cursor(2, 0)
  type_keys('i', 'L')
  sleep(default_completion_delay + small_time)
  child.expect_screenshot()

  -- Should also use buffer local config
  child.ensure_normal_mode()
  child.b.minicompletion_config = { fallback_action = '<C-p>' }
  set_lines({ 'Line number 1', '' })
  set_cursor(2, 0)
  type_keys('i', 'L')
  sleep(default_completion_delay + small_time)
  child.expect_screenshot()
end

T['Autocompletion']['respects function `config.fallback_action`'] = function()
  child.lua([[MiniCompletion.config.fallback_action = function() _G.inside_fallback = true end]])
  type_keys('i', 'a')
  sleep(default_completion_delay + small_time)
  eq(child.lua_get('_G.inside_fallback'), true)

  child.ensure_normal_mode()
  child.lua('vim.b.minicompletion_config = { fallback_action = function() _G.inside_local_fallback = true end }')
  type_keys('i', 'a')
  sleep(default_completion_delay + small_time)
  eq(child.lua_get('_G.inside_local_fallback'), true)
end

T['Autocompletion']['respects `vim.{g,b}.minicompletion_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minicompletion_disable = true
    type_keys('i', 'J')
    sleep(default_completion_delay + small_time)
    eq(get_completion(), {})
  end,
})

T['Manual completion'] = new_set({
  hooks = {
    pre_case = function()
      -- Virtually disable auto-completion
      child.lua('MiniCompletion.config.delay.completion = 100000')
      -- Create new buffer to set buffer-local `completefunc` or `omnifunc`
      new_buffer()
      -- For details see 'mock-lsp/months.lua'
      mock_lsp()

      set_lines({ 'Jackpot', '' })
      set_cursor(2, 0)
    end,
  },
})

T['Manual completion']['works with two-step completion'] = function()
  type_keys('i', 'J', '<C-Space>')
  eq(get_completion(), { 'January', 'June', 'July' })

  type_keys('ac')
  eq(child.fn.pumvisible(), 0)

  type_keys('<C-Space>')
  eq(get_completion(), { 'Jackpot' })
end

T['Manual completion']['handles request errors'] = function()
  child.lua('_G.mock_error = { ["textDocument/completion"] = "Error" }')
  type_keys('i', 'J', '<C-Space>')
  eq(get_completion(), { 'Jackpot' })
end

T['Manual completion']['uses `vim.lsp.protocol.CompletionItemKind` in LSP step'] = function()
  child.set_size(17, 30)
  child.lua([[vim.lsp.protocol.CompletionItemKind = {
    [1] = 'Text',         Text = 1,
    [2] = 'Method',       Method = 2,
    [3] = 'S Something',  ['S Something'] = 3,
    [4] = 'Fallback',     Fallback = 4,
  }]])
  type_keys('i', '<C-Space>')
  child.expect_screenshot()
end

T['Manual completion']['sends proper context in request'] = function()
  local trigger_kind_invoked = child.lua_get('vim.lsp.protocol.CompletionTriggerKind.Invoked')
  local validate_latest_request_context = function(ref_context)
    local latest_params = child.lua_get('_G.params_log[#_G.params_log]')
    eq(latest_params.method, 'textDocument/completion')
    eq(latest_params.params.context, ref_context)
  end

  -- First request is done after manual completion invocation
  type_keys('i', 'J', '<C-Space>')
  validate_latest_request_context({ triggerKind = trigger_kind_invoked })

  -- Second request is done via API
  child.lua('MiniCompletion.complete_twostage()')
  eq(child.lua_get('#_G.params_log'), 2)
  validate_latest_request_context({ triggerKind = trigger_kind_invoked })
end

T['Manual completion']['works with fallback action'] = function()
  type_keys('i', 'J', '<M-Space>')
  eq(get_completion(), { 'Jackpot' })
end

T['Manual completion']['works with explicit `<C-x>...`'] = new_set(
  { parametrize = { { 'completefunc' }, { 'omnifunc' } } },
  {
    test = function(source_func)
      reload_module({ lsp_completion = { source_func = source_func } })
      mock_completefunc_lsp_tracking()
      child.api.nvim_set_current_buf(child.api.nvim_create_buf(true, false))

      local source_keys = '<C-x>' .. (source_func == 'completefunc' and '<C-u>' or '<C-o>')
      type_keys('i', 'J', source_keys)
      eq(get_completion(), { 'January', 'June', 'July' })
      -- Should call three times: first to initiate request, second/third to
      -- perform its actions (as per `:h complete-functions`)
      eq(child.lua_get('_G.n_completfunc_lsp'), 3)
    end,
  }
)
T['Manual completion']['respects `config.mappings'] = function()
  reload_module({ mappings = { force_twostep = '<C-z>', force_fallback = '<C-x>' } })
  type_keys('i', 'J', '<C-z>')
  eq(get_completion(), { 'January', 'June', 'July' })
  type_keys('<C-x>')
  eq(get_completion(), { 'Jackpot' })
end

T['Manual completion']['applies `additionalTextEdits` from "textDocument/completion"'] = function()
  local validate = function(confirm_key)
    child.ensure_normal_mode()
    set_lines({})
    type_keys('i', 'Se', '<C-space>')
    child.poke_eventloop()
    type_keys('<C-n>', confirm_key)

    eq(child.fn.mode(), 'i')
    local is_explicit_confirm = confirm_key == '<C-y>'
    eq(
      get_lines(),
      { 'from months.completion import September', 'September' .. (is_explicit_confirm and '' or confirm_key) }
    )
    -- Text edits shouldn't interfere with relative cursor position
    eq(get_cursor(), { 2, 9 + (is_explicit_confirm and 0 or 1) })
  end

  -- 'Confirmation' should be either explicit ('<C-y>') or implicit
  -- (continued typing)
  validate('<C-y>')
  validate(' ')
end

T['Manual completion']['applies `additionalTextEdits` from "completionItem/resolve"'] = function()
  local validate = function(word_start, word)
    child.ensure_normal_mode()
    set_lines({})
    type_keys('i', word_start, '<C-space>')
    child.poke_eventloop()
    type_keys('<C-n>')
    -- Wait until `completionItem/resolve` request is sent
    sleep(default_info_delay + small_time)
    type_keys('<C-y>')

    eq(child.fn.mode(), 'i')
    eq(get_lines(), { 'from months.resolve import ' .. word, word })
    -- Text edits shouldn't interfere with relative cursor position
    eq(get_cursor(), { 2, word:len() })
  end

  -- Case when `textDocument/completion` doesn't have `additionalTextEdits`
  validate('Oc', 'October')

  -- Case when `textDocument/completion` does have `additionalTextEdits`
  validate('No', 'November')

  -- Should clear all possible cache for `additionalTextEdits`
  child.ensure_normal_mode()
  set_lines({})
  type_keys('i', 'Ja', '<C-space>')
  child.poke_eventloop()
  type_keys('<C-n>', '<C-y>')
  eq(get_lines(), { 'January' })
end

T['Manual completion']['prefers completion range from LSP response'] = function()
  set_lines({})
  type_keys('i', 'months.')
  -- Mock `textEdit`+`filterText` as in `tsserver` when called after `.`
  child.lua([[
    _G.mock_textEdit = {
      pos = vim.api.nvim_win_get_cursor(0),
      new_text = function(name) return '.' .. name end,
    }
    _G.mock_filterText = function(name) return '.' .. name end
  ]])
  type_keys('<C-space>')

  eq(get_completion('abbr'), { 'April', 'August' })
  eq(get_completion('word'), { '.April', '.August' })
  type_keys('<C-n>', '<C-y>')
  eq(get_lines(), { 'months.April' })
  eq(get_cursor(), { 1, 12 })

  type_keys('<C-e>', '<Esc>')
  set_lines({})

  -- Should recognize edit range from `itemDefaults` (as in `tailwindcss`)
  type_keys('i', 'months.A')
  child.lua([[_G.mock_itemdefaults = {
    editRange = { start = { line = 0, character = 5 }, ['end'] = { line = 0, character = 7 } },
  }
  _G.mock_filterText = function(name) return 's.' .. name end
  ]])
  type_keys('<C-space>')
  type_keys('<C-n>', '<C-y>')
  eq(get_lines(), { 'month.April' })
end

T['Manual completion']['respects `filterText` from LSP response'] = function()
  set_lines({})
  type_keys('i', 'months.')
  -- Mock `textEdit` and `filterText` as in `tsserver` when called after `.`
  -- (see https://github.com/nvim-mini/mini.nvim/issues/306#issuecomment-1602245446)
  child.lua([[
    _G.mock_textEdit = {
      pos = vim.api.nvim_win_get_cursor(0),
      new_text = function(name) return '[' .. name .. ']' end,
    }
    _G.mock_filterText = function(name) return '.' .. name end
  ]])
  type_keys('<C-space>')

  eq(get_completion('abbr'), { 'April', 'August' })
  eq(get_completion('word'), { '[April]', '[August]' })
  type_keys('<C-n>', '<C-y>')
  eq(get_lines(), { 'months[April]' })
  eq(get_cursor(), { 1, 13 })
end

T['Manual completion']['respects `filterText` during built-in filtering'] = function()
  set_lines({})
  child.set_size(10, 20)
  local format_snippet = child.lua_get('vim.lsp.protocol.InsertTextFormat.Snippet')
  mock_lsp_items({
    { label = 'ab', filterText = 'ba' },
    { label = 'cba', filterText = 'abc' },
    -- Snippets should still be filtered according to 'filterText' and
    -- not what snippet will be inserted later
    { label = 'dcba', filterText = 'ab$1cd', insertTextFormat = format_snippet },
    { label = 'edcba', filterText = 'abcde', insertText = 'snip$1pet', insertTextFormat = format_snippet },
  })

  type_keys('i', '<C-Space>')
  child.expect_screenshot()
  type_keys('a')
  child.expect_screenshot()
end

T['Manual completion']['respects `labelDetails` from LSP response'] = function()
  child.set_size(16, 32)
  child.lua([[
    MiniCompletion.config.lsp_completion.process_items = function(items, base)
      for _, it in ipairs(items) do
        if it.label == 'January' then it.labelDetails = { detail = 'jan' } end
        if it.label == 'February' then it.labelDetails = { description = 'FEB' } end
        -- Should use both `detail` and `description`
        if it.label == 'March' then it.labelDetails = { detail = 'mar', description = 'MAR' } end
      end
      return MiniCompletion.default_process_items(items, base)
    end
  ]])

  set_lines({})
  type_keys('i', '<C-Space>')
  child.expect_screenshot()
end

T['Manual completion']['respects `itemDefaults` from LSP response'] = function()
  local format_snippet = child.lua_get('vim.lsp.protocol.InsertTextFormat.Snippet')
  child.lua([[
    MiniCompletion.config.lsp_completion.process_items = function(items, _)
      _G.latest_items = vim.deepcopy(items)
      return items
    end
  ]])

  child.lua([[
    _G.mock_textEdit = { new_text = function(x) return 'Hello ' .. x end, pos = { 1, 1 } }
    _G.mock_itemdefaults = {
      commitCharacters = { ')' },
      data = { hello = 'world' },
      insertTextFormat = vim.lsp.protocol.InsertTextFormat.Snippet,
      insertTextMode = 1,
    }
  ]])

  -- Mock with `editRange` as regular `Range`
  local edit_range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 1 } }
  child.lua('_G.mock_itemdefaults.editRange = ' .. vim.inspect(edit_range))

  set_lines({})
  type_keys('i', '<C-Space>')

  local items = child.lua_get('_G.latest_items')
  for _, item in ipairs(items) do
    eq(item.commitCharacters, { ')' })
    eq(item.data, { hello = 'world' })
    eq(item.insertTextFormat, format_snippet)
    eq(item.insertTextMode, 1)

    eq(item.textEdit.newText, item.textEdit.newText or item.textEditText or item.label)
    eq(item.textEdit.range, item.textEdit.range or edit_range)
    -- 'April' has mocked 'InsertReplaceEdit' type of `textEdit` in the item
    if item.label ~= 'April' then
      eq(item.textEdit.insert, nil)
      eq(item.textEdit.replace, nil)
    end
  end
  type_keys('<C-e>')
  child.lua('_G.latest_items = nil')

  -- Mock with `editRange` as isnert+replace ranges and partial default data
  child.lua('_G.mock_itemdefaults.data = nil')
  edit_range = {
    replace = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 1 } },
    insert = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 2 } },
  }
  child.lua('_G.mock_itemdefaults.editRange = ' .. vim.inspect(edit_range))

  type_keys('<C-Space>')
  items = child.lua_get('_G.latest_items')
  for _, item in ipairs(items) do
    eq(item.commitCharacters, { ')' })
    eq(item.data, nil)
    eq(item.insertTextFormat, format_snippet)
    eq(item.insertTextMode, 1)

    eq(item.textEdit.newText, item.textEdit.newText or item.textEditText or item.label)
    -- 'August' has mocked 'Range' type of `textEdit` in the item
    if item.label ~= 'August' then eq(item.textEdit.range, nil) end
    eq(item.textEdit.insert, item.textEdit.insert or edit_range.insert)
    eq(item.textEdit.replace, item.textEdit.replace or edit_range.replace)
  end
end

T['Manual completion']['respects `kind_hlgroup` as item field'] = function()
  if child.fn.has('nvim-0.11') == 0 then MiniTest.skip('Kind highlighting is available on Neovim>=0.11') end
  child.set_size(10, 40)
  set_lines({})

  child.lua([[
    MiniCompletion.config.lsp_completion.process_items = function(items, base)
      local res = vim.tbl_filter(function(x) return vim.startswith(x.label, base) end, items)
      table.sort(res, function(a, b) return a.sortText < b.sortText end)
      for _, item in ipairs(res) do
        if item.label == 'January' then item.kind_hlgroup = 'String' end
        if item.label == 'June' then item.kind_hlgroup = 'Comment' end
      end
      return res
    end
  ]])
  type_keys('i', 'J', '<C-Space>')
  child.expect_screenshot()
end

T['Manual completion']['respects `vim.{g,b}.minicompletion_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minicompletion_disable = true
    type_keys('i', '<C-Space>')
    child.poke_eventloop()
    eq(get_completion(), {})

    type_keys('i', '<M-Space>')
    child.poke_eventloop()
    eq(get_completion(), {})
  end,
})

T['Information window'] = new_set({
  hooks = {
    pre_case = function()
      -- Create new buffer to set buffer-local `completefunc` or `omnifunc`
      new_buffer()
      -- For details see 'mock-lsp/months.lua'
      mock_lsp()
    end,
  },
})

local is_info_border_busy = function()
  local win_id = get_floating_windows()[1]
  local winhl = child.api.nvim_get_option_value('winhighlight', { win = win_id })
  return winhl:find('FloatBorder:MiniCompletionInfoBorderOutdated') ~= nil
end

local validate_info_win = function(delay)
  type_keys('i', 'J', '<C-Space>')
  eq(get_completion(), { 'January', 'June', 'July' })

  -- Should implement debounce-style delay
  type_keys('<C-n>')
  eq(get_floating_windows(), {})
  sleep(delay - small_time)
  eq(get_floating_windows(), {})

  type_keys('<C-n>')
  eq(get_floating_windows(), {})
  sleep(delay - small_time)
  eq(get_floating_windows(), {})

  sleep(small_time + small_time)
  validate_single_floating_win({ lines = { 'Month #06' } })
  eq(is_info_border_busy(), false)

  -- Should use properly named buffer
  local info_buf_id = child.api.nvim_win_get_buf(get_floating_windows()[1])
  eq(child.api.nvim_buf_get_name(info_buf_id), 'minicompletion://' .. info_buf_id .. '/item-info')

  -- Should try to keep window opened while visualizing outdated state via
  -- border highlighting
  type_keys('<C-p>')
  validate_single_floating_win({ lines = { 'Month #06' } })
  eq(is_info_border_busy(), true)

  sleep(delay + small_time)
  validate_single_floating_win({ lines = { 'Month #01' } })
  eq(is_info_border_busy(), false)

  -- Should close window immediately if no candidate is selected
  type_keys('<C-p>')
  eq(get_floating_windows(), {})
end

T['Information window']['works'] = function()
  child.set_size(10, 40)
  validate_info_win(default_info_delay)

  -- Should show relevant content without delay upon revisit
  type_keys('<C-n>')
  child.expect_screenshot()
end

T['Information window']['works without attached LSP server'] = function()
  child.set_size(10, 40)
  child.lsp.buf_detach_client(0, child.lua_get('_G.months_lsp_client_id'))
  child.lua([[
    local items = {
      { word = 'aa', info = 'Word aa' },
      { word = 'aaa', info = 'Word aaa' },
    }
    MiniCompletion.config.fallback_action = function() vim.fn.complete(vim.fn.col('.'), items) end
  ]])

  type_keys('i', '<C-Space>')
  type_keys('<C-n>')
  -- Should show info window immediately (as there is no LSP server to resolve
  -- with) with regular border highlight
  child.expect_screenshot()
  eq(is_info_border_busy(), false)
  type_keys('<C-n>')
  child.expect_screenshot()
  eq(is_info_border_busy(), false)
end

T['Information window']['has "busy" visualization until receiving resolve response'] = function()
  local request_delay = 3 * small_time
  child.lua('_G.mock_request_delay = ' .. request_delay)

  type_keys('i', 'J', '<C-Space>')
  sleep(request_delay + small_time)
  eq(child.fn.pumvisible(), 1)

  type_keys('<C-n>')
  sleep(default_info_delay + small_time)
  eq(get_floating_windows(), {})
  sleep(request_delay)
  validate_single_floating_win({ lines = { 'Month #01' } })
  eq(is_info_border_busy(), false)

  type_keys('<C-n>')
  eq(is_info_border_busy(), true)
  sleep(default_info_delay + request_delay - small_time)
  validate_single_floating_win({ lines = { 'Month #01' } })
  eq(is_info_border_busy(), true)
  sleep(small_time + small_time)
  validate_single_floating_win({ lines = { 'Month #06' } })
  eq(is_info_border_busy(), false)
end

T['Information window']['handles no info in candidate'] = function()
  type_keys('i', 'Ma', '<C-Space>', '<C-n>', '<C-n>')
  sleep(default_info_delay + small_time)
  validate_single_floating_win({ lines = { '-No-info-' } })
end

T['Information window']['handles request errors'] = function()
  child.lua('_G.mock_error = { ["completionItem/resolve"] = "Error" }')
  type_keys('i', 'J', '<C-Space>')
  type_keys('<C-n>')
  sleep(default_info_delay + small_time)
  validate_single_floating_win({ lines = { '-No-info-' } })
end

T['Information window']['respects `config.delay.info`'] = function()
  child.lua('MiniCompletion.config.delay.info = ' .. (2 * default_info_delay))
  validate_info_win(2 * default_info_delay)

  -- Should also use buffer local config
  child.ensure_normal_mode()
  set_lines({ '' })
  child.b.minicompletion_config = { delay = { info = default_info_delay } }
  validate_info_win(default_info_delay)
end

T['Information window']['caches info lines for visited candidates'] = function()
  local info_delay = 2 * small_time
  child.lua('MiniCompletion.config.delay.info = ' .. info_delay)
  local validate_n_requests = function(ref) eq(child.lua_get('_G.n_completionitem_resolve'), ref) end
  local validate_win = function(ref_lines, ref_is_border_busy)
    if ref_lines == false then return eq(get_floating_windows(), {}) end
    validate_single_floating_win({ lines = ref_lines })
    eq(is_info_border_busy(), ref_is_border_busy)
  end

  -- Fully compute info lines on first candidate visit
  type_keys('i', 'J', '<C-Space>', '<C-n>')
  validate_win(false)
  sleep(info_delay + small_time)
  validate_win({ 'Month #01' }, false)

  type_keys('<C-n>')
  validate_win({ 'Month #01' }, true)
  sleep(info_delay + small_time)
  validate_win({ 'Month #06' }, false)

  -- For already visited items do not make new LSP requests and show proper
  -- content without delay
  validate_n_requests(2)
  type_keys('<C-p>')
  validate_win({ 'Month #01' }, false)

  type_keys('<C-n>')
  validate_win({ 'Month #06' }, false)
  validate_n_requests(2)

  -- Cached info lines should still be preserved until current completion end
  type_keys('<C-p>', '<C-p>')
  validate_win(false)
  type_keys('<C-n>')
  validate_win({ 'Month #01' }, false)
  validate_n_requests(2)

  type_keys('<C-p>')
  validate_win(false)
  type_keys('u', '<C-n>')
  validate_win({ 'Month #06' }, false)
  validate_n_requests(2)

  type_keys('<C-n>')
  validate_win({ 'Month #06' }, true)
  sleep(info_delay + small_time)
  -- - NOTE: actual lines for "July" entry is too long, so not tested here
  validate_win(nil, false)
  validate_n_requests(3)

  -- Cache for visited lines should be properly cleared after completion end
  type_keys(' ', 'J', '<C-Space>', '<C-n>')
  validate_win(false)
  sleep(info_delay + small_time)
  validate_win({ 'Month #01' }, false)
  validate_n_requests(4)
end

T['Information window']['caches resolved data for visited candidates'] = function()
  type_keys('i', '<C-space>', '<C-p>', '<C-p>', '<C-p>')
  sleep(default_info_delay + small_time)
  validate_single_floating_win({ lines = { 'Month #10' } })

  type_keys('<C-n>', '<C-p>')
  validate_single_floating_win({ lines = { 'Month #10' } })
  type_keys('<C-y>')

  eq(get_lines(), { 'from months.resolve import October', 'October' })
end

T['Information window']['caches data with multiple servers'] = function()
  -- Start another LSP server
  child.cmd('luafile tests/mock-lsp/fruits.lua')

  local info_delay = 2 * small_time
  child.lua('MiniCompletion.config.delay.info = ' .. info_delay)
  local validate_n_requests = function(ref) eq(child.lua_get('_G.n_completionitem_resolve'), ref) end

  local validate_info_content = function(sleep_delay)
    local validate_step = function(lines)
      type_keys('<C-n>')
      if sleep_delay > 0 then sleep(sleep_delay) end
      validate_single_floating_win({ lines = lines })
    end

    validate_step({ 'Month #01' })
    validate_step({ 'Jackfruit is a fruit' })
  end

  type_keys('i', 'Ja', '<C-Space>')
  validate_info_content(info_delay + small_time)

  type_keys('<C-n>')
  validate_n_requests(2)
  validate_info_content(0)
  validate_n_requests(2)
end

T['Information window']['handles caching for items with the same basic data'] = function()
  local info_delay = 2 * small_time
  child.lua('MiniCompletion.config.delay.info = ' .. info_delay)
  local validate_n_requests = function(ref) eq(child.lua_get('_G.n_completionitem_resolve'), ref) end

  mock_lsp_items({
    { label = 'ab', sortText = '01', documentation = 'Item 1' },
    { label = 'ab', sortText = '02', documentation = 'Item 2' },
  })

  type_keys('i', '<C-Space>', '<C-n>')
  sleep(info_delay + small_time)
  validate_single_floating_win({ lines = { 'Item 1' } })
  type_keys('<C-n>')
  sleep(info_delay + small_time)
  validate_single_floating_win({ lines = { 'Item 2' } })

  -- Should use caching mechanism that doesn't rely on fields that can be same
  validate_n_requests(2)
  type_keys('<C-p>')
  validate_single_floating_win({ lines = { 'Item 1' } })
  type_keys('<C-n>')
  validate_single_floating_win({ lines = { 'Item 2' } })
  validate_n_requests(2)
end

T['Information window']['works if server does not support `completionItem/resolve`'] = function()
  child.lsp.buf_detach_client(0, child.lua_get('_G.months_lsp_client_id'))

  -- Start another LSP server in a way that doesn't support resolve
  child.lua('_G.mock_no_resolve = true')
  child.cmd('luafile tests/mock-lsp/fruits.lua')

  local info_delay = 2 * small_time
  child.lua('MiniCompletion.config.delay.info = ' .. info_delay)

  -- Should use data provided at the time of 'textDocument/completion' request
  type_keys('i', '<C-Space>', '<C-n>')
  sleep(info_delay + small_time)
  validate_single_floating_win({ lines = { 'Apple fruit' } })

  type_keys('<C-n>')
  sleep(info_delay + small_time)
  validate_single_floating_win({ lines = { '-No-info-' } })

  -- Should still cache data as visited/resolved
  type_keys('<C-p>')
  validate_single_floating_win({ lines = { 'Apple fruit' } })
  type_keys('<C-n>')
  validate_single_floating_win({ lines = { '-No-info-' } })

  -- Should not do 'completionItem/resolve' requests (as there is no support)
  eq(child.lua_get('_G.n_completionitem_resolve'), vim.NIL)
end

local validate_info_window_config = function(keys, completion_items, win_config)
  type_keys('i', keys, '<C-Space>')
  eq(get_completion(), completion_items)

  type_keys('<C-n>')
  -- Some windows can take a while to process on slow machines. So add `10`
  -- to ensure that processing is finished.
  sleep(default_info_delay + small_time)
  validate_single_floating_win({ config = win_config })
end

T['Information window']['respects `config.window.info`'] = function()
  child.set_size(25, 60)
  local win_config = { height = 20, width = 40, border = 'single' }
  child.lua('MiniCompletion.config.window.info = ' .. vim.inspect(win_config))
  validate_info_window_config('D', { 'December' }, {
    height = 20,
    width = 40,
    border = { '┌', '─', '┐', '│', '┘', '─', '└', '│' },
  })
  child.expect_screenshot()

  -- Should also use buffer local config
  child.ensure_normal_mode()
  set_lines({ '' })
  local test_border = { '1', '2', '3', '4', '5', '6', '7', '8' }
  child.b.minicompletion_config = { window = { info = { height = 10, width = 20, border = test_border } } }
  validate_info_window_config('D', { 'December' }, { height = 10, width = 20, border = test_border })
  child.expect_screenshot()
end

T['Information window']["respects 'winborder' option"] = function()
  if child.fn.has('nvim-0.11') == 0 then MiniTest.skip("'winborder' option is present on Neovim>=0.11") end

  local validate = function(ref_border)
    validate_info_window_config('D', { 'December' }, { border = ref_border })
    type_keys('<C-e>')
    child.ensure_normal_mode()
    set_lines({})
  end

  child.o.winborder = 'rounded'
  validate({ '╭', '─', '╮', '│', '╯', '─', '╰', '│' })

  -- Should prefer explicitly configured value over 'winborder'
  child.lua('MiniCompletion.config.window.info.border = "double"')
  validate({ '╔', '═', '╗', '║', '╝', '═', '╚', '║' })
end

T['Information window']['triggers relevant events'] = function()
  mock_event_log()
  local validate_log = function(ref)
    eq(child.lua_get('_G.log'), ref)
    child.lua('_G.log = {}')
  end

  type_keys('i', 'J', '<C-Space>')
  type_keys('<C-n>')
  sleep(default_info_delay + small_time)
  local win_id = get_floating_windows()[1]
  validate_log({ { event = 'MiniCompletionWindowOpen', data = { kind = 'info', win_id = win_id } } })

  type_keys('<C-n>')
  sleep(default_info_delay + small_time)
  validate_log({ { event = 'MiniCompletionWindowUpdate', data = { kind = 'info', win_id = win_id } } })
end

T['Information window']['can be adjusted in event'] = function()
  if child.fn.has('nvim-0.11') == 0 then MiniTest.skip('"title_pos" window config field was added in Neovim=0.11') end

  mock_custom_window_config()
  child.set_size(10, 40)

  type_keys('i', 'J', '<C-Space>')
  type_keys('<C-n>')
  sleep(default_info_delay + small_time)
  type_keys('<C-n>')
  sleep(default_info_delay + small_time)
  child.expect_screenshot()
end

T['Information window']['accounts for border when picking side'] = function()
  child.set_size(10, 40)
  child.lua([[MiniCompletion.config.window.info.border = 'single']])

  set_lines({ 'aaaaaaaaaaaa ' })
  type_keys('A', 'J', '<C-Space>', '<C-n>')
  sleep(default_info_delay + small_time)
  child.expect_screenshot()
end

T['Information window']['has minimal dimensions for small text'] = function()
  child.set_size(10, 40)
  child.lua('MiniCompletion.config.window.info.height = 1')
  child.lua('MiniCompletion.config.window.info.width = 9')
  validate_info_window_config('J', { 'January', 'June', 'July' }, { height = 1, width = 9 })
  child.expect_screenshot()
end

T['Information window']['adjusts window width'] = function()
  child.set_size(10, 27)
  child.lua([[MiniCompletion.config.window.info = { height = 15, width = 10, border = 'single' }]])

  type_keys('i', 'J', '<C-Space>', '<C-n>')
  sleep(default_info_delay + small_time)
  child.expect_screenshot()
end

T['Information window']['adjusts title'] = function()
  child.set_size(20, 35)

  type_keys('i', '<C-Space>', '<C-n>', '<C-n>')
  sleep(default_info_delay + small_time)
  child.expect_screenshot()
  type_keys('<C-p>')
  sleep(default_info_delay + small_time)
  child.expect_screenshot()
end

T['Information window']['stylizes markdown with concealed characters'] = function()
  if child.fn.has('nvim-0.10') == 0 then MiniTest.skip('Markdown highlighting is different on Neovim<0.10') end

  child.set_size(15, 45)
  type_keys('i', 'Jul', '<C-Space>')
  type_keys('<C-n>')
  eq(get_floating_windows(), {})
  sleep(default_info_delay + small_time)
  child.expect_screenshot()
end

T['Information window']['uses `detail` to construct content'] = function()
  if child.fn.has('nvim-0.10') == 0 then MiniTest.skip('Markdown highlighting is different on Neovim<0.10') end
  child.bo.filetype = 'lua'

  child.set_size(15, 45)
  type_keys('i', 'A', '<C-Space>')

  -- Should show `detail` in language's code block if it is new information
  -- Should also trim `detail` for a more compact view
  type_keys('<C-n>')
  sleep(default_info_delay + small_time)
  child.expect_screenshot()

  -- Should omit `detail` if its content is already present in `documentation`
  type_keys('<C-n>')
  sleep(default_info_delay + small_time)
  child.expect_screenshot()
end

T['Information window']['ignores data from first response if server can resolve completion item'] = function()
  if child.fn.has('nvim-0.10') == 0 then MiniTest.skip('Markdown highlighting is different on Neovim<0.10') end

  child.set_size(10, 45)
  child.lua([[
    MiniCompletion.config.lsp_completion.process_items = function(items, base)
      for _, it in ipairs(items) do
        if it.label == 'April' then
          it.detail = 'Initial detail'
          it.documentation = 'Initial documentation'
        end
      end
      return MiniCompletion.default_process_items(items, base)
    end
  ]])

  set_lines({})
  type_keys('i', 'Apr', '<C-Space>')
  type_keys('<C-n>')
  sleep(default_info_delay + small_time)
  -- Should show resolved data and not initial in order to always prefer
  -- resolved if possible. This is useful if initial response contains only
  -- single `detail` or `documentation` but resolving gets them both (like in
  -- `r-language-server`, for example).
  child.expect_screenshot()
end

T['Information window']['adjusts for top/bottom code block delimiters'] = function()
  child.set_size(10, 30)
  type_keys('i', 'Sep', '<C-Space>')
  type_keys('<C-n>')
  sleep(default_info_delay + small_time)
  -- Should show floating window with height 1, i.e. both top and bottom code
  -- block delimiters should be hidden
  child.expect_screenshot()
end

T['Information window']['uses `info` field from not LSP source'] = function()
  child.set_size(10, 30)
  child.lua([[
    MiniCompletion.config.fallback_action = function()
      vim.fn.complete(1, { { word = 'Fall', abbr = 'Fall', info = 'back' } })
    end
  ]])

  set_lines({})
  type_keys('i', '<A-Space>')
  type_keys('<C-n>')
  sleep(default_info_delay + small_time)
  child.expect_screenshot()
end

T['Information window']['is closed when forced outside of Insert mode'] = new_set(
  { parametrize = { { '<Esc>' }, { '<C-c>' } } },
  {
    test = function(key)
      type_keys('i', 'J', '<C-Space>')
      eq(get_completion(), { 'January', 'June', 'July' })

      type_keys('<C-n>')
      sleep(default_info_delay + small_time)
      validate_single_floating_win({ lines = { 'Month #01' } })

      type_keys(key)
      eq(get_floating_windows(), {})
    end,
  }
)

T['Information window']['handles all buffer wipeout'] = function()
  validate_info_win(default_info_delay)
  child.ensure_normal_mode()

  child.cmd('%bw!')
  new_buffer()
  mock_lsp()

  validate_info_win(default_info_delay)
end

T['Information window']['handles outdated scheduled showing'] = function()
  child.set_size(30, 40)
  child.o.cmdheight = 20
  child.o.completeopt = 'menuone,noinsert'

  type_keys('i')
  local text = 'aa ab ac ad ae af ag ah ai aj ak al am an ao ap aq ar as at au av aw ax ay az'
  child.lua('_G.text = ' .. vim.inspect(text))
  child.lua('_G.delay = ' .. small_time)
  child.lua([[
    MiniCompletion.config.delay.completion = _G.delay
    MiniCompletion.config.delay.info = 0

    local n_char = 0
    local function type_text()
      n_char = n_char + 1
      local char = _G.text:sub(n_char, n_char)
      if char == '' then return end
      vim.api.nvim_input(char)
      vim.defer_fn(type_text, _G.delay + 1)
    end

    type_text()
  ]])

  sleep(small_time * text:len() + small_time)
  eq(child.cmd_capture('messages'), '')
end

T['Information window']['respects `vim.{g,b}.minicompletion_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minicompletion_disable = true

    set_lines({ 'aa ab ', '' })
    set_cursor(2, 0)
    type_keys('i', '<C-n>', '<C-n>')
    sleep(default_info_delay + small_time)
    eq(#get_floating_windows(), 0)
  end,
})

T['Signature help'] = new_set({
  hooks = {
    pre_case = function()
      -- Create new buffer to set buffer-local `completefunc` or `omnifunc`
      new_buffer()
      -- For details see 'mock-lsp/months.lua'
      mock_lsp()
    end,
  },
})

local validate_signature_win = function(delay)
  type_keys('i', 'abc(')

  eq(get_floating_windows(), {})
  sleep(delay - small_time)
  eq(get_floating_windows(), {})
  sleep(small_time + small_time)
  validate_single_floating_win({ lines = { 'abc(param1, param2)' } })

  local signature_buf_id = child.api.nvim_win_get_buf(get_floating_windows()[1])
  eq(child.api.nvim_buf_get_name(signature_buf_id), 'minicompletion://' .. signature_buf_id .. '/signature-help')
end

T['Signature help']['works'] = function()
  child.set_size(7, 30)
  validate_signature_win(default_signature_delay)
  child.expect_screenshot()
end

T['Signature help']['handles request errors'] = function()
  child.lua('_G.mock_error = { ["textDocument/signatureHelp"] = "Error" }')
  type_keys('i', 'abc(')
  sleep(default_signature_delay + small_time)
  eq(get_floating_windows(), {})
end

T['Signature help']['respects `config.delay.signature`'] = function()
  child.lua('MiniCompletion.config.delay.signature = ' .. (2 * default_signature_delay))
  validate_signature_win(2 * default_signature_delay)

  -- Should also use buffer local config
  child.ensure_normal_mode()
  set_lines({ '' })
  child.b.minicompletion_config = { delay = { signature = default_signature_delay } }
  validate_signature_win(default_signature_delay)
end

T['Signature help']['updates highlighting of active parameter'] = function()
  child.set_size(7, 30)
  child.cmd('startinsert')

  type_keys('abc(')
  sleep(default_signature_delay + small_time)
  child.expect_screenshot()

  -- Should update without configurable delay as window is already shown
  type_keys('1,')
  sleep(small_time)
  child.expect_screenshot()

  -- As there are only two parameters, nothing should be highlighted
  type_keys('222,')
  sleep(small_time)
  child.expect_screenshot()

  -- Should update if cursor is moved without typing (like during snippet jump)
  set_cursor(1, 7)
  sleep(small_time)
  child.expect_screenshot()

  type_keys('<Esc>')
  set_lines({ '' })

  -- Should work when LSP server returns paramter label as string
  type_keys('i', 'multiline(')
  sleep(default_signature_delay + small_time)
  child.expect_screenshot()
  type_keys('3,')
  sleep(small_time)
  child.expect_screenshot()

  type_keys('<Esc>')
  set_lines({ '' })

  -- Should not error if parameters contain not correct label data
  type_keys('i', 'bad_signature(')
  sleep(default_signature_delay + small_time)
  eq(child.cmd_capture('messages'):gsub('%s*$', ''), '')
end

T['Signature help']['updates without delay with different window'] = function()
  child.set_size(8, 35)
  set_lines({ 'multiline(', 'abc(111, 222)' })
  child.cmd('startinsert')
  set_cursor(1, 10)

  sleep(default_signature_delay + small_time)
  child.expect_screenshot()

  set_cursor(2, 11)
  sleep(small_time)
  child.expect_screenshot()
end

local validate_signature_window_config = function(keys, win_config)
  child.cmd('startinsert')
  type_keys(keys)
  sleep(default_signature_delay + small_time)
  validate_single_floating_win({ config = win_config })
end

T['Signature help']['respects `config.window.signature`'] = function()
  local keys = { 'l', 'o', 'n', 'g', '(' }
  local win_config = { height = 15, width = 40, border = 'single' }
  child.lua('MiniCompletion.config.window.signature = ' .. vim.inspect(win_config))
  validate_signature_window_config(keys, {
    height = 15,
    width = 40,
    border = { '┌', '─', '┐', '│', '┘', '─', '└', '│' },
  })
  child.expect_screenshot()

  -- Should also use buffer local config
  child.ensure_normal_mode()
  set_lines({ '' })
  local test_border = { '1', '2', '3', '4', '5', '6', '7', '8' }
  child.b.minicompletion_config = { window = { signature = { height = 10, width = 20, border = test_border } } }
  validate_signature_window_config(keys, { height = 10, width = 20, border = test_border })
  child.expect_screenshot()
end

T['Signature help']["respects 'winborder' option"] = function()
  if child.fn.has('nvim-0.11') == 0 then MiniTest.skip("'winborder' option is present on Neovim>=0.11") end

  local validate = function(ref_border)
    validate_signature_window_config('abc(', { border = ref_border })
    type_keys('<C-e>')
    child.ensure_normal_mode()
    set_lines({})
  end

  child.o.winborder = 'rounded'
  validate({ '╭', '─', '╮', '│', '╯', '─', '╰', '│' })

  -- Should prefer explicitly configured value over 'winborder'
  child.lua('MiniCompletion.config.window.signature.border = "double"')
  validate({ '╔', '═', '╗', '║', '╝', '═', '╚', '║' })
end

T['Signature help']['triggers relevant events'] = function()
  mock_event_log()
  local validate_log = function(ref)
    eq(child.lua_get('_G.log'), ref)
    child.lua('_G.log = {}')
  end

  type_keys('i', 'abc(')
  sleep(default_signature_delay + small_time)
  local win_id = get_floating_windows()[1]
  validate_log({ { event = 'MiniCompletionWindowOpen', data = { kind = 'signature', win_id = win_id } } })

  -- Currently signature window is not updated after opened, so no
  -- `MiniCompletionWindowUpdate` event is triggered
end

T['Signature help']['can be adjusted in event'] = function()
  mock_custom_window_config()
  child.set_size(7, 30)
  type_keys('i', 'abc(')
  sleep(default_signature_delay + small_time)
  type_keys('x', ',')
  sleep(small_time)
  child.expect_screenshot()
end

T['Signature help']['accounts for border when picking side'] = function()
  child.set_size(10, 40)
  child.lua([[MiniCompletion.config.window.signature.border = 'single']])

  type_keys('o<CR>', 'abc(')
  sleep(default_signature_delay + small_time)
  child.expect_screenshot()
end

T['Signature help']['has minimal dimensions for small text'] = function()
  child.set_size(7, 30)
  local keys = { 'a', 'b', 'c', '(' }
  child.lua('MiniCompletion.config.window.signature.height = 1')
  child.lua('MiniCompletion.config.window.signature.width = 19')
  validate_signature_window_config(keys, { height = 1, width = 19 })
  child.expect_screenshot()
end

T['Signature help']['adjusts window height'] = function()
  child.set_size(10, 25)
  child.lua([[MiniCompletion.config.window.signature = { height = 15, width = 10, border = 'single' }]])

  type_keys('i', 'long(')
  sleep(default_signature_delay + small_time)
  child.expect_screenshot()
end

T['Signature help']['handles multiline text'] = function()
  child.set_size(10, 35)

  type_keys('i', 'multiline(')
  sleep(default_signature_delay + small_time)
  child.expect_screenshot()
end

T['Signature help']['adjusts title'] = function()
  child.set_size(10, 25)

  type_keys('i', 'short(')
  sleep(default_signature_delay + small_time)
  child.expect_screenshot()
  type_keys('aa,')
  sleep(small_time)
  child.expect_screenshot()
end

T['Signature help']['stylizes markdown with concealed characters'] = function()
  if child.fn.has('nvim-0.10') == 0 then MiniTest.skip('Lua highlighting is different on Neovim<0.10') end

  child.set_size(10, 65)
  child.bo.filetype = 'lua'
  type_keys('i', 'string.format(')
  sleep(default_signature_delay + small_time)
  child.expect_screenshot()
end

T['Signature help']['implements debounce-style delay'] = function()
  child.cmd('startinsert')
  type_keys('abc(')
  sleep(default_signature_delay - small_time)
  type_keys('d')
  sleep(default_signature_delay + small_time)
  eq(#get_floating_windows(), 0)

  type_keys(',')
  sleep(default_signature_delay + small_time)
  validate_single_floating_win({ lines = { 'abc(param1, param2)' } })
end

T['Signature help']['is closed when forced outside of Insert mode'] = new_set(
  { parametrize = { { '<Esc>' }, { '<C-c>' } } },
  {
    test = function(key)
      type_keys('i', 'abc(')
      sleep(default_signature_delay + small_time)
      validate_single_floating_win({ lines = { 'abc(param1, param2)' } })

      type_keys(key)
      eq(get_floating_windows(), {})
    end,
  }
)

T['Signature help']['handles all buffer wipeout'] = function()
  validate_signature_win(default_signature_delay)
  child.ensure_normal_mode()

  child.cmd('%bw!')
  new_buffer()
  mock_lsp()

  validate_signature_win(default_signature_delay)
end

T['Signature help']['respects `vim.{g,b}.minicompletion_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minicompletion_disable = true

    type_keys('i', 'abc(')
    sleep(default_signature_delay + small_time)
    eq(#get_floating_windows(), 0)
  end,
})

T['Scroll'] = new_set({
  hooks = {
    pre_case = function()
      new_buffer()
      mock_lsp()
      child.set_size(10, 25)
    end,
  },
})

T['Scroll']['can be done in info window'] = function()
  child.lua('MiniCompletion.config.window.info.height = 4')

  type_keys('i', 'F', '<C-Space>')
  type_keys('<C-n>')
  sleep(default_info_delay + small_time)
  child.expect_screenshot()

  type_keys('<C-f>')
  child.expect_screenshot()
  type_keys('<C-f>')
  child.expect_screenshot()
  type_keys('<C-f>')
  child.expect_screenshot()

  type_keys('<C-b>')
  child.expect_screenshot()
  type_keys('<C-b>')
  child.expect_screenshot()
  type_keys('<C-b>')
  child.expect_screenshot()
end

T['Scroll']['can be done in signature window'] = function()
  if child.fn.has('nvim-0.10') == 0 then MiniTest.skip("'smoothscroll' requires Neovim>=0.10") end

  child.o.smoothscroll = true
  child.lua('MiniCompletion.config.window.signature.height = 4')
  child.lua('MiniCompletion.config.window.signature.width = 4')

  type_keys('i', 'scroll(')
  sleep(default_signature_delay + small_time)
  child.expect_screenshot()

  type_keys('<C-f>')
  child.expect_screenshot()
  type_keys('<C-f>')
  child.expect_screenshot()

  type_keys('<C-b>')
  child.expect_screenshot()
  type_keys('<C-b>')
  child.expect_screenshot()
end

T['Scroll']['can be done in both windows'] = function()
  child.o.smoothscroll = true
  child.lua('MiniCompletion.config.window.info.height = 4')
  child.lua('MiniCompletion.config.window.signature.height = 4')
  child.lua('MiniCompletion.config.window.signature.width = 4')

  type_keys('i', 'scroll(')
  sleep(default_signature_delay + small_time)

  type_keys('F', '<C-Space>')
  type_keys('<C-n>')
  sleep(default_info_delay + small_time)
  child.expect_screenshot()

  -- Should prefer scrolling in info window if both are visible
  type_keys('<C-f>')
  child.expect_screenshot()
  type_keys('<C-b>')
  child.expect_screenshot()

  if child.fn.has('nvim-0.10') == 0 then MiniTest.skip("'smoothscroll' requires Neovim>=0.10") end
  type_keys('<C-e>')
  type_keys('<C-f>')
  child.expect_screenshot()
end

T['Scroll']['respects `config.mappings`'] = function()
  child.lua([[
    vim.keymap.del('i', '<C-f>')
    vim.keymap.del('i', '<C-b>')
    MiniCompletion.setup({
      lsp_completion = { source_func = 'omnifunc' },
      mappings = { scroll_down = '<C-d>', scroll_up = '<C-u>' },
      window = { info = { height = 4 } },
    })
  ]])

  new_buffer()
  mock_lsp()

  type_keys('i', 'F', '<C-Space>')
  type_keys('<C-n>')
  sleep(default_info_delay + small_time)
  child.expect_screenshot()

  type_keys('<C-d>')
  child.expect_screenshot()
  type_keys('<C-u>')
  child.expect_screenshot()
  type_keys('<C-e>')

  -- Mapped keys can be used without active target window
  set_lines({ '  Line' })
  set_cursor(1, 6)
  type_keys('<C-d>')
  eq(get_lines(), { 'Line' })
  type_keys('<C-u>')
  eq(get_lines(), { '' })
end

local mock_lsp_snippets = function(snippets)
  local kind_snippet = child.lua_get('vim.lsp.protocol.CompletionItemKind.Snippet')
  mock_lsp_items(vim.tbl_map(function(x) return { label = x, kind = kind_snippet } end, snippets))
end

T['Snippets'] = new_set({
  hooks = {
    pre_case = function()
      -- Test snippet insert primarily with 'mini.snippets'
      child.lua('require("mini.snippets").setup()')

      new_buffer()
      mock_lsp()
      child.set_size(10, 25)
    end,
  },
})

T['Snippets']['work'] = function()
  child.set_size(10, 40)

  local kind_snippet = child.lua_get('vim.lsp.protocol.CompletionItemKind.Snippet')
  local kind_function = child.lua_get('vim.lsp.protocol.CompletionItemKind.Function')
  local format_snippet = child.lua_get('vim.lsp.protocol.InsertTextFormat.Snippet')

  local r = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 0 } }

  local items = {
    -- "Regular" snippet kind
    { label = 'Snippet A $1', kind = kind_snippet },

    -- Non-snippet kind, but with "Snippet" format of inserted text,
    { label = 'Snippet B $1', kind = kind_function, insertTextFormat = format_snippet },

    -- Should use `label` in popup and `insertText` after inserting
    { label = 'Snip C', kind = kind_function, insertText = 'Snippet C $1', insertTextFormat = format_snippet },

    -- Should use `label` in popup and `textEdit.newText` after inserting
    {
      label = 'Snip D',
      kind = kind_function,
      textEdit = { newText = 'Snippet D $1', range = vim.deepcopy(r) },
      insertTextFormat = format_snippet,
    },

    -- Same, but `textEdit` is `InsertReplaceEdit`
    {
      label = 'Snip E',
      kind = kind_function,
      textEdit = { newText = 'Snippet E $1', insert = vim.deepcopy(r), replace = vim.deepcopy(r) },
      insertTextFormat = format_snippet,
    },

    -- Multi-line snippets in label
    { label = 'Snippet F\nMulti\nLine $1', kind = kind_snippet },
    {
      label = 'Snip G',
      kind = kind_snippet,
      textEdit = { newText = 'Snippet G\nMulti\nLine $1', range = vim.deepcopy(r) },
    },
  }

  mock_lsp_items(items)
  type_keys('i', '<C-Space>')
  -- Should properly set abbreviation, kind, and "S" symbol
  child.expect_screenshot()

  -- Should show `label` when navigating with `<C-n>`
  for i = 1, #items do
    type_keys('<C-n>')
    local ref_lines = vim.split(items[i].label, '\n')
    -- Built-in multi-line completion is present in Neovim>=0.11
    if not (#ref_lines > 1 and child.fn.has('nvim-0.11') == 0) then eq(get_lines(), ref_lines) end
  end

  type_keys('<C-e>')
  set_lines({ '' })

  -- Should properly insert snippet and start snippet session
  local validate = function(item, ref_lines, ref_cursor)
    mock_lsp_items({ item })
    type_keys('<C-Space>', '<C-n>', '<C-y>')
    eq(get_lines(), ref_lines)
    eq(get_cursor(), ref_cursor)
    eq(child.fn.mode(), 'i')
    eq(child.lua_get('#MiniSnippets.session.get(true)'), 1)

    type_keys('<C-c>')
    set_lines({ '' })
  end

  validate(items[1], { 'Snippet A ' }, { 1, 10 })
  validate(items[2], { 'Snippet B ' }, { 1, 10 })
  validate(items[3], { 'Snippet C ' }, { 1, 10 })
  validate(items[4], { 'Snippet D ' }, { 1, 10 })
  validate(items[5], { 'Snippet E ' }, { 1, 10 })
  validate(items[6], { 'Snippet F', 'Multi', 'Line ' }, { 3, 5 })
  validate(items[7], { 'Snippet G', 'Multi', 'Line ' }, { 3, 5 })
end

T['Snippets']['are inserted after attempting to insert non-keyword charater'] = function()
  mock_lsp_snippets({ 'Snippet A $1' })

  local validate = function(non_keyword_char, ref_line, ref_cursor)
    type_keys('i', '<C-Space>', '<C-n>', non_keyword_char)

    eq(get_lines(), { ref_line })
    eq(get_cursor(), ref_cursor)
    eq(child.fn.pumvisible(), 0)
    eq(child.lua_get('#MiniSnippets.session.get(true)'), 1)

    type_keys('<C-c>', '<Esc>')
    set_lines({ '' })
  end

  -- Should work with regular non-keyword character
  validate(' ', 'Snippet A ', { 1, 10 })
  validate('[', 'Snippet A ', { 1, 10 })
  validate('<Tab>', 'Snippet A ', { 1, 10 })
  validate('<S-Tab>', 'Snippet A ', { 1, 10 })

  -- Should work with `<CR>` (with or without recommended remap)
  validate('<CR>', 'Snippet A ', { 1, 10 })

  child.lua([[
    _G.cr_action = function()
      -- '\25' is <C-y> and '\r' is <CR>
      if vim.fn.pumvisible() ~= 0 then
        local item_selected = vim.fn.complete_info()['selected'] ~= -1
        return item_selected and '\25' or '\25\r'
      else
        return '\r'
      end
    end
    vim.keymap.set('i', '<CR>', 'v:lua._G.cr_action()', { expr = true })
  ]])
  validate('<CR>', 'Snippet A ', { 1, 10 })

  -- Should work when non-keyword char triggers Insert mode mapping that
  -- inserts more characters (like in 'mini.pairs')
  if child.fn.has('nvim-0.10') == 0 then
    -- This is probably due to some fixed issue with extmarks
    MiniTest.skip('Non-keyword character that inserts multiple characters can be used only on Neovim>=0.10 ')
  end

  child.cmd('inoremap ( (abc)<Left><Left><Left>')
  set_lines({ 'Before cursor  text after cursor' })
  set_cursor(1, 14)
  -- - Should no part of `(abc)` be present
  validate('(', 'Before cursor Snippet A  text after cursor', { 1, 24 })
end

T['Snippets']['can be stopped from inserting'] = function()
  local kind_function = child.lua_get('vim.lsp.protocol.CompletionItemKind.Function')
  local format_snippet = child.lua_get('vim.lsp.protocol.InsertTextFormat.Snippet')
  mock_lsp_items({
    { label = 'Snip A', kind = kind_function, insertText = 'Snippet A $1', insertTextFormat = format_snippet },
  })

  local validate_stop = function(key, ref_line, ref_mode)
    type_keys('i', '<C-Space>', '<C-n>')
    type_keys(key)
    eq(get_lines(), { ref_line })
    eq(child.fn.mode(), ref_mode)

    set_lines({ '' })
    child.ensure_normal_mode()
  end

  -- Should do nothing after `<C-e>` (proper completion stop)
  validate_stop('<C-e>', '', 'i')

  -- Should not insert snippet after `<Esc>` / `<C-c>` (exit to Normal mode),
  -- but inserted text
  validate_stop('<Esc>', 'Snip A', 'n')
  validate_stop('<C-c>', 'Snip A', 'n')
end

T['Snippets']['properly show special symbol in popup'] = function()
  child.set_size(10, 35)
  local kind_snippet = child.lua_get('vim.lsp.protocol.CompletionItemKind.Snippet')
  local kind_function = child.lua_get('vim.lsp.protocol.CompletionItemKind.Function')

  local items = {
    -- Should correctly combine with label details
    { label = 'Snippet A1 $1', kind = kind_snippet, labelDetails = { detail = 'Det' } },
    { label = 'Snippet A2 $1', kind = kind_snippet, labelDetails = { description = 'Desc' } },
    { label = 'Snippet A2 $1', kind = kind_snippet, labelDetails = { detail = 'Det', description = 'Desc' } },

    -- No "S", as the text does not contain tabstop (although "Snippet" kind)
    { label = 'OnlyText', kind = kind_snippet },

    -- No "S", as not a snippet at all
    { label = 'NotASnippet', kind = kind_function },
  }

  mock_lsp_items(items)
  type_keys('i', '<C-Space>')
  -- Should show "S" symbol only if item will actually insert snippet
  child.expect_screenshot()
end

T['Snippets']['show full snippet text as info'] = function()
  local kind_function = child.lua_get('vim.lsp.protocol.CompletionItemKind.Function')
  local format_snippet = child.lua_get('vim.lsp.protocol.InsertTextFormat.Snippet')
  mock_lsp_items({
    { label = 'January', kind = kind_function, insertText = 'January is $1', insertTextFormat = format_snippet },
    { label = 'May', kind = kind_function, insertText = 'May the $1 be with you', insertTextFormat = format_snippet },
  })

  -- Should show full snippet text as info
  type_keys('i', 'M', '<C-Space>', '<C-n>')
  sleep(default_info_delay + small_time)
  child.expect_screenshot()

  type_keys('<C-e>', '<Esc>')
  set_lines({ '' })

  -- Should prefer server's documentation and/or detail if it provides one
  type_keys('i', 'J', '<C-Space>', '<C-n>')
  sleep(default_info_delay + small_time)
  child.expect_screenshot()
end

T['Snippets']["can fall back if no 'mini.snippets' is enabled"] = function()
  -- "Unsetup" 'mini.snippets'
  child.lua('_G.MiniSnippets = nil')

  mock_lsp_snippets({ 'Single line $1 snippet', 'Multi\nline $1\\tnsnippet' })

  -- On Neovim<0.10 should insert snippet text as is and set cursor at its end
  if child.fn.has('nvim-0.10') == 0 then
    local validate = function(snippet, ref_lines, ref_cursor)
      mock_lsp_snippets({ snippet })

      type_keys('i', '  Text before ')
      type_keys('<C-Space>', '<C-n>', '<C-y>')
      eq(get_lines(), ref_lines)
      eq(get_cursor(), ref_cursor)
      eq(child.fn.mode(), 'i')

      child.ensure_normal_mode()
      set_lines({ '' })
    end

    validate('Single line $1 snippet', { '  Text before Single line $1 snippet' }, { 1, 36 })
    validate('Multi\nline $1\nsnippet', { '  Text before Multi', 'line $1', 'snippet' }, { 3, 7 })

    return
  end

  -- On Neovim>=0.10 should use `vim.snippet.expand`
  mock_lsp_snippets({ 'Multi\nline $1\nsnippet' })
  type_keys('i', '  Text before ')
  type_keys('<C-Space>', '<C-n>', '<C-y>')
  eq(get_lines(), { '  Text before Multi', '  line ', '  snippet' })
  eq(get_cursor(), { 2, 7 })
  eq(child.fn.mode(), 'i')

  child.lua('vim.snippet.jump(1)')
  eq(get_cursor(), { 3, 9 })
  eq(child.fn.mode(), 'i')
end

T['Snippets']["respect 'mini.snippets' config"] = function()
  child.lua([[
    MiniSnippets.config.expand.insert = function(snippet)
      MiniSnippets.default_insert(snippet, { empty_tabstop = '!', lookup = { VAR = 'Hello' } })
    end
    MiniSnippets.config.mappings.jump_next = '<Tab>'
    MiniSnippets.config.mappings.jump_prev = '<S-Tab>'
  ]])
  mock_lsp_snippets({ 'Snippet_$1($0) $VAR' })
  type_keys('i', '<C-Space>', '<C-n>', '<C-y>')
  -- NOTE: inline virtual text is supported on Neovim>=0.10
  if child.fn.has('nvim-0.10') == 1 then child.expect_screenshot() end
  eq(get_cursor(), { 1, 8 })

  type_keys('<Tab>')
  eq(get_cursor(), { 1, 9 })
  type_keys('<S-Tab>')
  eq(get_cursor(), { 1, 8 })
end

T['Snippets']['can start nested sessions'] = function()
  mock_lsp_snippets({ 'Snippet A $1', 'Snippet B $1' })
  type_keys('i', '<C-Space>', '<C-n>', '<C-y>')
  eq(child.lua_get('#MiniSnippets.session.get(true)'), 1)
  type_keys('<C-Space>', '<C-n>', '<C-n>', '<C-y>')
  eq(child.lua_get('#MiniSnippets.session.get(true)'), 2)

  eq(get_lines(), { 'Snippet A Snippet B ' })
end

T['Snippets']['respect `lsp_completion.snippet_insert`'] = function()
  child.lua([[
    _G.log = {}
    MiniCompletion.config.lsp_completion.snippet_insert = function(...)
      table.insert(_G.log, { ... })
    end
  ]])
  mock_lsp_snippets({ 'Snippet $1' })
  type_keys('i', '<C-Space>', '<C-n>', '<C-y>')
  eq(child.fn.pumvisible(), 0)
  eq(get_lines(), { '' })
  eq(child.lua_get('_G.log'), { { 'Snippet $1' } })
end

T['Snippets']['are not inserted if have no tabstops or variables'] = function()
  -- This allows inserting snippets "implicitly" after typing non-keyword
  -- character. Without this, LSP servers which report any inserted text as
  -- snippet will "eat" the next typed non-keyword charater.
  -- Treating text as snippet if there is a variable is important for a snippet
  -- insert method to expand them.

  child.set_size(19, 52)
  local snippets = {
    -- - No insert:
    'Just\ntext',
    [[Text with \$1 escaped dollar]],
    [[Text with \$TM_FILENAME escaped dollar]],
    [[Text with \${1} escaped dollar]],
    [[Text with \${TM_FILENAME} escaped dollar]],
    -- - Insert:
    'Has $TM_FILENAME variable',
    'Has $var variable',
    'Has $1 tabstop',
    '$1 has tabstop',
    'Has ${1} tabstop',
    '${1} has tabstop',
    'Has ${1:aaa} tabstop',
    'Has $0 tabstop',
    'Has ${0} tabstop',
    'Has tabstop$0',
  }
  mock_lsp_snippets(snippets)

  -- Should not show "S" symbol in popup for "no insert" items
  type_keys('i', '<C-Space>')
  child.expect_screenshot()
  type_keys('<C-e>', '<Esc>')

  child.lua([[
    _G.log = {}
    MiniCompletion.config.lsp_completion.snippet_insert = function(...)
      table.insert(_G.log, { ... })
    end
  ]])
  local validate = function(snip, accept_key, should_insert)
    child.lua('_G.log = {}')
    mock_lsp_snippets({ snip })

    type_keys('i', '<C-Space>', '<C-n>', accept_key)
    eq(child.lua_get('#_G.log > 0'), should_insert)

    type_keys('<C-e>', '<Esc>')
    set_lines({ '' })
  end

  for i = 1, 5 do
    validate(snippets[i], '<C-y>', false)
    validate(snippets[i], '<CR>', false)
    validate(snippets[i], ' ', false)
  end

  for i = 6, #snippets do
    validate(snippets[i], '<C-y>', true)
    validate(snippets[i], '<CR>', true)
    validate(snippets[i], ' ', true)
  end
end

T['Snippets']['prefer snippet from resolved item'] = function()
  -- Although it is not recommended by LSP spec to update/provide `insertText`
  -- or `textEdti` in 'completionItem/resolve', this still can probably happen.
  -- NOTE: There is no such test for regular inserted text because that is
  -- pre-computed after 'textDocument/completion' inside complete-items (as
  -- they are responsible for inserting text).

  child.lua([[
    MiniCompletion.config.lsp_completion.process_items = function(items, base)
      for _, item in ipairs(items) do
        if item.label == 'May' then
          item.kind = vim.lsp.protocol.CompletionItemKind.Snippet
          item.insertText = 'May $1 snippet'
        end
      end
      return MiniCompletion.default_process_items(items, base)
    end
  ]])

  local validate = function(ref_lines)
    type_keys('i', 'May', '<C-Space>', '<C-n>')
    -- - Wait for 'completionItem/resolve' request to be sent
    sleep(default_info_delay + small_time)
    type_keys('<C-y>')
    eq(get_lines(), ref_lines)

    type_keys('<C-c>')
    set_lines({})
    child.ensure_normal_mode()
  end

  -- mock_lsp_snippets({ 'Snippet $1 original' })
  validate({ 'Resolved  May' })

  -- Should handle error in 'completionItem/resolve' response
  child.lua('_G.mock_error = { ["completionItem/resolve"] = "Error" }')
  validate({ 'May  snippet' })
end

T['Snippets']['can be inserted together with additional text edits'] = function()
  local kind_function = child.lua_get('vim.lsp.protocol.CompletionItemKind.Function')
  local format_snippet = child.lua_get('vim.lsp.protocol.InsertTextFormat.Snippet')

  --stylua: ignore
  local items = {
    {
      label = 'Snip A', kind = kind_function, insertText = 'Snippet A $1', insertTextFormat = format_snippet,
      additionalTextEdits = {
        {
          newText = 'New text on first line',
          range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 0 } },
        },
      }
    },
  }
  mock_lsp_items(items)

  local validate = function(ref_lines, ref_cursor)
    type_keys('i', '<C-Space>', '<C-n>', '<C-y>')
    eq(get_lines(), ref_lines)
    eq(get_cursor(), ref_cursor)
    eq(child.lua_get('#MiniSnippets.session.get(true)'), 1)

    type_keys('<C-c>')
    child.ensure_normal_mode()
    set_lines({ '' })
  end

  -- A usual case of additional text edit not near completed item
  set_lines({ '', '' })
  set_cursor(2, 0)
  validate({ 'New text on first line', 'Snippet A ' }, { 2, 10 })

  -- An unusual case of additional text edit in the same line
  set_lines({ '' })
  set_cursor(1, 0)
  validate({ 'New text on first lineSnippet A ' }, { 1, 32 })

  -- Additional text edits should be applied after removing inserted
  -- non-keyword characters used to accept completion item
  if child.fn.has('nvim-0.10') == 0 then
    -- This is probably due to some fixed issue with extmarks
    MiniTest.skip('Non-keyword character that inserts multiple characters can be used only on Neovim>=0.10 ')
  end
  items[1].additionalTextEdits[1].range = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 6 } }
  mock_lsp_items(items)
  child.cmd('inoremap ( (abc)<Left><Left><Left>')

  type_keys('i', '<C-Space>', '<C-n>', '(')
  eq(get_lines(), { 'New text on first lineSnippet A ' })
  eq(get_cursor(), { 1, 32 })
  eq(child.lua_get('#MiniSnippets.session.get(true)'), 1)
end

T['Snippets']['respect covering `textEdit` in candidate'] = function()
  if child.fn.has('nvim-0.10') == 0 then MiniTest.skip('This has problems on Neovim<0.10') end

  child.set_size(10, 25)

  local kind_snippet = child.lua_get('vim.lsp.protocol.CompletionItemKind.Snippet')
  local items = {
    {
      label = 'Snip A',
      kind = kind_snippet,
      textEdit = {
        newText = 'Snippet A $1',
        -- Multi-line range to replace when inserting snippet
        range = { start = { line = 0, character = 1 }, ['end'] = { line = 1, character = 1 } },
      },
    },
    {
      label = 'Snip B',
      kind = kind_snippet,
      textEdit = {
        newText = 'Snippet B $1',
        -- Should remove `insert` range when inserting snippet
        insert = { start = { line = 0, character = 2 }, ['end'] = { line = 0, character = 4 } },
        replace = { start = { line = 0, character = 2 }, ['end'] = { line = 0, character = 5 } },
      },
    },
    {
      label = 'Snip C',
      kind = kind_snippet,
      textEdit = {
        newText = 'Snippet C $1',
        range = { start = { line = 0, character = 3 }, ['end'] = { line = 0, character = 4 } },
      },
      -- Additional text edits both before and after candidate text edit
      additionalTextEdits = {
        {
          newText = 'X',
          range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 2 } },
        },
        {
          newText = 'Y',
          range = { start = { line = 0, character = 5 }, ['end'] = { line = 0, character = 6 } },
        },
      },
    },
  }

  mock_lsp_items(items)
  local validate = function(item, ref_lines, ref_cursor)
    mock_lsp_items({ item })
    set_lines({ 'ab Sdef', 'gh' })
    set_cursor(1, 4)
    type_keys('i', '<C-Space>', '<C-n>', '<C-y>')
    eq(get_lines(), ref_lines)
    eq(get_cursor(), ref_cursor)
    eq(child.fn.mode(), 'i')
    eq(child.lua_get('#MiniSnippets.session.get(true)'), 1)

    type_keys('<C-c>', '<Esc>')
  end

  validate(items[1], { 'aSnippet A h' }, { 1, 11 })
  validate(items[2], { 'abSnippet B def', 'gh' }, { 1, 12 })
  validate(items[3], { 'X Snippet C dYf', 'gh' }, { 1, 12 })
end

T['Snippets']["LSP server from 'mini.snippets'"] = new_set({
  hooks = {
    pre_case = function()
      child.lsp.buf_detach_client(0, child.lua_get('_G.months_lsp_client_id'))

      child.lua([[
        MiniSnippets.config.snippets = {
          { prefix = 'aa', body = 'Snippet $1 aa', desc = 'The aa snippet' },
          { prefix = 'bb cc', body = 'Snippet $1 bb cc', desc = 'The bb cc snippet' },
        }
      ]])

      child.set_size(10, 35)
    end,
  },
})

T['Snippets']["LSP server from 'mini.snippets'"]['works'] = function()
  child.lua('MiniSnippets.start_lsp_server()')

  type_keys('i', '<C-Space>', '<C-n>')
  sleep(default_info_delay + small_time)
  if child.fn.has('nvim-0.10') == 1 then child.expect_screenshot() end

  type_keys(' ')
  eq(get_lines(), { 'Snippet  aa' })
  eq(get_cursor(), { 1, 8 })
  eq(child.fn.mode(), 'i')
  eq(child.lua_get('#MiniSnippets.session.get(true)'), 1)
end

T['Snippets']["LSP server from 'mini.snippets'"]['works with in-server matching'] = function()
  child.lua([[
    local match = function(snippets)
      local res = { snippets[2] }
      res[1].region = { from = { line = 1, col = 1 }, to = { line = 1, col = vim.fn.col('.') - 1 } }
      return res
    end
    MiniSnippets.start_lsp_server({ match = match })
  ]])

  type_keys('i', 'bb c', '<C-Space>')
  child.expect_screenshot()
  type_keys('<C-n>', '<C-y>')
  eq(get_lines(), { 'Snippet  bb cc' })
  eq(get_cursor(), { 1, 8 })
  eq(child.lua_get('#MiniSnippets.session.get(true)'), 1)
end

return T
