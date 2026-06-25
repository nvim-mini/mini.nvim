local helpers = dofile('tests/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

local slash = helpers.is_windows() and '\\' or '/'

-- Helpers with child processes
local load_module = function(config) child.mini_load('input', config) end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end

-- Common test wrappers
local forward_lua = function(fun_str)
  local lua_cmd = fun_str .. '(...)'
  return function(...) return child.lua_get(lua_cmd, { ... }) end
end

local forward_lua_notify = function(fun_str)
  local lua_cmd = fun_str .. '(...)'
  return function(...) return child.lua_notify(lua_cmd, { ... }) end
end

local get = forward_lua_notify('MiniInput.get')
local get_history = forward_lua('MiniInput.get_history')

local get_state = function(state_var)
  if state_var == nil then child.lua('_G.state = MiniInput.get_state()') end
  if state_var ~= nil then child.lua('_G.state = vim.deepcopy(_G.' .. state_var .. ')') end
  return child.lua([[
    local state = _G.state
    _G.state = nil
    if state == nil then return nil end
    -- Adjust function handlers to be able to pass through RPC
    for k, v in pairs(state.opts.handlers) do
      if vim.is_callable(v) then state.opts.handlers[k] = 'function' end
    end
    return state
  ]])
end

local with_prompt_chunks = function(chunks, prompt)
  return vim.list_extend({ { prompt or 'Input', 'MiniInputPrompt' }, { ' ', 'MiniInputNormal' } }, chunks)
end

-- Common mocks
local mock_finished_input = function(input, prompt, scope)
  get({ prompt = prompt, scope = scope })
  type_keys(input, '<CR>')
end

local mock_state = function(incomplete_state)
  child.lua('_G.mock_state = ' .. vim.inspect(incomplete_state))
  child.lua([[
    _G.mock_state.input = _G.mock_state.input or ''
    _G.mock_state.caret = _G.mock_state.caret or (vim.fn.strchars(_G.mock_state.input) + 1)
    _G.mock_state.data = _G.mock_state.data or {}
    _G.mock_state.status = _G.mock_state.status or 'progress'

    local opts = _G.mock_state.opts or {}
    local default_handlers = {
      key = MiniInput.config.handlers.key or MiniInput.default_key,
      highlight = MiniInput.config.handlers.highlight or MiniInput.default_highlight,
      view = MiniInput.config.handlers.view or MiniInput.default_view,
      complete = MiniInput.config.handlers.complete or MiniInput.default_complete,
    }
    opts.completion = opts.completion or ''
    opts.handlers = vim.tbl_extend('force', default_handlers, opts.handlers or {})
    if opts.hide == nil then opts.hide = false end
    opts.init_keys = opts.init_keys or {}
    opts.prompt = opts.prompt or 'Input'
    opts.scope = opts.scope or MiniInput.config.scope
    _G.mock_state.opts = opts
  ]])
end

local mock_notify = function()
  child.lua([[
    _G.notify_log = {}
    vim.notify = function(...) table.insert(_G.notify_log, { ... }) end
  ]])
end

local mock_tracking_default_handlers = function()
  child.lua([[
    local copy_tables
    copy_tables = function(x) return type(x) == 'table' and vim.tbl_map(copy_tables, x) or x end

    -- Sanitize state to be able to pass through RPC
    local sanitize = function(state)
      local res = copy_tables(state)
      for k, v in pairs(state.opts.handlers) do
        if vim.is_callable(v) then res.opts.handlers[k] = 'function' end
      end
      return res
    end

    -- Track all handlers
    _G.handlers_log = {}
    MiniInput.config.handlers.complete = function(state, ...)
      table.insert(_G.handlers_log, { 'complete', sanitize(state), ... })
      return MiniInput.default_complete(state, ...)
    end
    MiniInput.config.handlers.highlight = function(state, ...)
      table.insert(_G.handlers_log, { 'highlight', sanitize(state), ... })
      return MiniInput.default_highlight(state, ...)
    end
    MiniInput.config.handlers.key = function(state, ...)
      table.insert(_G.handlers_log, { 'key', sanitize(state), ... })
      return MiniInput.default_key(state, ...)
    end
    MiniInput.config.handlers.view = function(state, ...)
      table.insert(_G.handlers_log, { 'view', sanitize(state), ... })
      return MiniInput.default_view(state, ...)
    end
  ]])
end

-- Common validators
local validate_input = function(ref_input, ref_caret, ref_scope)
  local state = get_state()
  if state == vim.NIL then
    local msg = 'No active input.'
      .. string.format(' Expected input=%s, caret=%d, scope=%s', vim.inspect(ref_input), ref_caret, ref_scope)
    error(msg)
  end
  local ref = {
    input = ref_input or state.input,
    caret = ref_caret or state.caret,
    scope = ref_scope or state.opts.scope,
  }
  eq({ input = state.input, caret = state.caret, scope = state.opts.scope }, ref)
end

local validate_no_input = function()
  local state = get_state()
  if state == vim.NIL then return end
  local msg = string.format('There is active input: input=%s, caret=%d', vim.inspect(state.input), state.caret)
  error(msg)
end

local validate_log = function(name, ref, preserve)
  eq(child.lua_get(name), ref)
  if not preserve then child.lua(name .. ' = {}') end
end

local compute_changed_values
compute_changed_values = function(left, right)
  if not (type(left) == 'table' and type(right) == 'table') then
    if vim.deep_equal(left, right) then return nil end
    -- Use `vim.NIL` to indicate that the value was set to `nil`
    if right == nil then return vim.NIL end
    return right
  end

  local changed = {}
  for k, v in pairs(left) do
    changed[k] = compute_changed_values(v, right[k])
    if type(changed[k]) == 'table' and vim.tbl_count(changed[k]) == 0 then changed[k] = nil end
  end
  for k, v in pairs(right) do
    if left[k] == nil then changed[k] = v end
  end
  return changed
end

local validate_default_handler = function(name, state, arg, ref_state_changes)
  child.lua('_G.handler_name = ' .. vim.inspect(name))
  mock_state(state)
  child.lua('_G.arg = ' .. vim.inspect(arg))
  child.lua('_G.handler = MiniInput.default_' .. name)

  local old_state = get_state('mock_state')
  child.lua('_G.new_state = _G.handler(_G.mock_state, _G.arg) or _G.mock_state')
  local new_state = get_state('new_state')
  eq(compute_changed_values(old_state, new_state), ref_state_changes)
end

-- Data =======================================================================
local caret_ch = { '▏', 'MiniInputCaret' }

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      load_module()

      -- Make screenshots more robust
      child.set_size(10, 20)
      child.o.laststatus = 0
      child.o.showtabline = 0
      child.o.ruler = false
      child.o.statusline = 'My statusline'
      child.o.tabline = 'My tabline'
      child.o.winminwidth = 1
      child.o.winwidth = 1
    end,
    post_once = child.stop,
    n_retry = helpers.get_n_retry(1),
  },
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  -- Global variable
  eq(child.lua_get('type(_G.MiniInput)'), 'table')

  -- Autocommand group
  eq(child.fn.exists('#MiniInput'), 1)

  -- Highlight groups
  child.cmd('hi clear')
  load_module()
  local has_highlight = function(group, value) expect.match(child.cmd_capture('hi ' .. group), value) end

  has_highlight('MiniInputAdded', 'links to DiagnosticFloatingOk')
  has_highlight('MiniInputBorder', 'links to FloatBorder')
  has_highlight('MiniInputCaret', 'links to MiniInputPrompt')
  has_highlight('MiniInputHide', 'links to DiagnosticFloatingWarn')
  has_highlight('MiniInputHint', 'links to DiagnosticFloatingHint')
  has_highlight('MiniInputNormal', 'links to NormalFloat')
  has_highlight('MiniInputPrompt', 'links to DiagnosticFloatingInfo')
  has_highlight('MiniInputSpecial', 'links to DiagnosticFloatingWarn')
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniInput.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniInput.config.' .. field), value) end

  expect_config('handlers.complete', vim.NIL)
  expect_config('handlers.highlight', vim.NIL)
  expect_config('handlers.key', vim.NIL)
  expect_config('handlers.view', vim.NIL)
  expect_config('scope', 'editor')
end

T['setup()']['validates `config` argument'] = function()
  local expect_config_error = function(config, name, target_type)
    expect.error(function() load_module(config) end, vim.pesc(name) .. '.*' .. vim.pesc(target_type))
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ handlers = 1 }, 'handlers', 'table')
  expect_config_error({ handlers = { complete = 1 } }, 'handlers.complete', 'function')
  expect_config_error({ handlers = { highlight = 1 } }, 'handlers.highlight', 'function')
  expect_config_error({ handlers = { key = 1 } }, 'handlers.key', 'function')
  expect_config_error({ handlers = { view = 1 } }, 'handlers.view', 'function')
end

T['setup()']['ensures colors'] = function()
  child.cmd('colorscheme default')
  expect.match(child.cmd_capture('hi MiniInputBorder'), 'links to FloatBorder')
end

T['setup()']['clears history'] = function()
  get()
  type_keys('one', '<CR>')
  eq(#get_history(), 1)

  load_module()
  eq(#get_history(), 0)
end

T['setup()']['sets `vim.ui.input`'] = function()
  child.lua_notify('vim.ui.input({}, function() end)')
  validate_input('', 1, 'editor')
end

T['setup()']['adjusts `vim.paste`'] = function()
  child.setup()
  mock_notify()

  child.lua([[
    _G.paste_log = {}
    vim.paste = function(lines, phase) table.insert(_G.paste_log, { lines, phase }) end
  ]])

  load_module()
  child.lua([[
    _G.handlers_log = {}
    MiniInput.config.handlers.key = function(state, key)
      table.insert(_G.handlers_log, { 'key', key })
      return MiniInput.default_key(state, key)
    end
    MiniInput.config.handlers.highlight = function(state)
      table.insert(_G.handlers_log, { 'highlight' })
      return MiniInput.default_highlight(state)
    end
    MiniInput.config.handlers.view = function(state)
      table.insert(_G.handlers_log, { 'view' })
      return MiniInput.default_view(state)
    end
  ]])

  get()

  -- Not streaming paste should be inserted at caret and processed by handlers
  type_keys('XY', '<Left>')
  child.lua('_G.handlers_log = {}')
  child.api.nvim_paste('Clipboard', false, -1)
  validate_input('XClipboardY', 11)
  validate_log('paste_log', {})
  validate_log('handlers_log', { { 'key' }, { 'highlight' }, { 'view' } })

  -- Streaming paste is not supported and should do nothing with active input
  child.api.nvim_paste('Not supported', false, 1)
  validate_input('XClipboardY', 11)
  validate_log('paste_log', {})
  validate_log('handlers_log', {})
  local notify_msg = '(mini.input) There is no streaming paste support. Use `<C-r>+` or `<C-r>*`.'
  validate_log('notify_log', { { notify_msg, child.lua_get('vim.log.levels.WARN') } })

  -- Should still work as expected outside of active input
  type_keys('<C-c>')
  child.api.nvim_paste('Should work', false, -1)
  validate_log('paste_log', { { { 'Should work' }, -1 } })
end

T['setup()']['hard-codes special default scopes'] = function()
  if child.fn.has('nvim-0.12.3') == 1 then return end

  child.restart()
  child.lua([[
    _G.rename_log = {}
    local append = function(...) table.insert(_G.rename_log, { ... }) end
    vim.lsp.buf.rename = function(new_name, _)
      if new_name ~= nil then return append('direct', new_name) end
      vim.ui.input({ prompt = 'New name: ' }, function(inp) append('ui.input', inp) end)
    end
  ]])
  load_module()

  -- `vim.lsp.buf.rename()`
  child.lua_notify('vim.lsp.buf.rename()')
  validate_input('', 1, 'cursor')
  type_keys('Hello', '<CR>')
  validate_log('rename_log', { { 'ui.input', 'Hello' } })

  child.lua('vim.lsp.buf.rename("World")')
  validate_no_input()
  validate_log('rename_log', { { 'direct', 'World' } })

  -- Should not have permanent side effect
  get()
  eq(get_state().opts.scope, 'editor')
  type_keys('<C-c>')

  -- - Should be possible to override via a key handler
  child.lua([[
    MiniInput.config.handlers.key = function(state, key)
      if state.opts.prompt == 'New name: ' then state.opts.scope = 'window' end
      return MiniInput.default_key(state, key)
    end
  ]])

  child.lua_notify('vim.lsp.buf.rename()')
  validate_input('', 1, 'window')
  type_keys('New one', '<CR>')
  validate_log('rename_log', { { 'ui.input', 'New one' } })
end

T['get()'] = new_set()

T['get()']['works'] = function()
  mock_tracking_default_handlers()

  -- Should return user's input on accept
  child.lua_notify('_G.input_res = MiniInput.get()')

  local eq_state = function(ref_state, same_data)
    local cur_state = get_state()
    if not same_data then cur_state.data = ref_state.data end
    eq(cur_state, ref_state)
  end

  -- Should start by calling all handlers with proper arguments
  local state = child.lua_get('_G.handlers_log[1][2]')
  eq(state, {
    caret = 1,
    data = {},
    input = '',
    -- Should correctly set default options
    opts = {
      completion = '',
      handlers = { complete = 'function', highlight = 'function', key = 'function', view = 'function' },
      hide = false,
      init_keys = {},
      prompt = 'Input',
      scope = 'editor',
    },
    status = 'start',
  })
  local handlers_log = child.lua_get('_G.handlers_log')
  -- - `key` argument of key handler is `nil` for `status="start"`
  eq(handlers_log, { { 'key', state, nil }, { 'highlight', state }, { 'view', state } })
  child.lua('_G.handlers_log = {}')

  -- Should indicate that input is in progress
  state.status = 'progress'
  eq_state(state)
  -- - Handlers might arbitrarily update `data`
  state.data = get_state().data

  -- Should call all handlers in order after each key press
  type_keys('W')

  handlers_log = child.lua_get('_G.handlers_log')
  eq(#handlers_log, 3)
  eq(handlers_log[1], { 'key', state, 'W' })
  state.input, state.caret = 'W', 2
  eq(handlers_log[2], { 'highlight', state })
  eq(handlers_log[3], { 'view', state })
  child.lua('_G.handlers_log = {}')

  eq_state(state)

  -- Should finish by calling all handlers one more time
  type_keys('<CR>')

  handlers_log = child.lua_get('_G.handlers_log')
  eq(#handlers_log, 6)
  -- - Processing of `<CR>`
  eq(handlers_log[1], { 'key', state, '\r' })
  state.status = 'accept'
  eq(handlers_log[2], { 'highlight', state })
  eq(handlers_log[3], { 'view', state })

  -- - Finishing
  eq(handlers_log[4], { 'key', state, nil })
  eq(handlers_log[5], { 'highlight', state })
  eq(handlers_log[6], { 'view', state })

  eq(get_state(), vim.NIL)

  -- Should return user's input on accept
  eq(child.lua_get('_G.input_res'), 'W')

  -- Should add to history
  eq(get_history(), { { cwd = child.fn.getcwd(), input = 'W', prompt = 'Input', scope = 'editor' } })
end

T['get()']['cancelling returns `nil`'] = function()
  child.lua_notify('_G.input_res = MiniInput.get()')
  type_keys('Cancel', '<C-c>')
  eq(get_state(), vim.NIL)
  eq(child.lua_get('_G.input_res'), vim.NIL)
end

T['get()']['allows only one simultaneous input'] = function()
  child.lua_notify('_G.input_1 = MiniInput.get({ prompt = "One" })')
  eq(get_state().opts.prompt, 'One')

  child.lua_notify('_G.input_2 = MiniInput.get({ prompt = "Two" })')
  eq(get_state().opts.prompt, 'One')

  type_keys('Uno', '<CR>')
  eq(child.lua_get('_G.input_1'), 'Uno')
  eq(child.lua_get('_G.input_2'), vim.NIL)
  eq(get_state(), vim.NIL)
end

T['get()']['stops'] = new_set({
  hooks = {
    pre_case = function()
      child.lua([[
        _G.handlers_log, _G.key_actions = {}, {}
        MiniInput.config.handlers.key = function(state, key)
          local status = state.errmsg == nil and state.status or { state.status, 'errmsg' }
          table.insert(_G.handlers_log, { 'key', status, key })
          if _G.key_actions[key] then _G.key_actions[key](state, key) end
        end
      ]])
    end,
  },
})

T['get()']['stops']['when handler sets ending status'] = function()
  child.lua('_G.key_actions.A = function(state) state.status = "accept" end')
  child.lua('_G.key_actions.C = function(state) state.status = "cancel" end')
  local validate_handler_end = function(key)
    get()
    type_keys(key)
    eq(get_state(), vim.NIL)
    local status = key == 'A' and 'accept' or 'cancel'
    validate_log('handlers_log', { { 'key', 'start', nil }, { 'key', 'progress', key }, { 'key', status, nil } })
  end
  validate_handler_end('A')
  validate_handler_end('C')
end

T['get()']['stops']['when there is an error during handler execution'] = function()
  child.lua('_G.key_actions.E = function(state) error("Very specific error in handler") end')
  local mock_handler_error = function()
    child.lua([[
      vim.defer_fn(function() vim.api.nvim_input('E') end, 50)
      _G.errored_input = MiniInput.get()
    ]])
  end
  expect.error(mock_handler_error, 'Very specific error in handler')
  eq(get_state(), vim.NIL)
  eq(child.lua_get('_G.errored_input'), vim.NIL)
  -- - Should still properly finish with extra input step with `state.errmsg`
  local ref_log = { { 'key', 'start', nil }, { 'key', 'progress', 'E' }, { 'key', { 'cancel', 'errmsg' }, nil } }
  validate_log('handlers_log', ref_log)
end

T['get()']['stops']['right after start'] = function()
  child.lua([[
    MiniInput.config.handlers.highlight = function(state)
      table.insert(_G.handlers_log, { 'hl', state.status })
      state.status = 'cancel'
    end
  ]])
  get()
  eq(get_state(), vim.NIL)
  local ref_log = { { 'key', 'start', nil }, { 'hl', 'start' }, { 'key', 'cancel', nil }, { 'hl', 'cancel' } }
  validate_log('handlers_log', ref_log)
end

T['get()']['stops']['during `init_keys`'] = function()
  child.lua('_G.key_actions.I = function(state) state.input, state.status = "Init", "accept" end')
  child.lua_notify('_G.input_res = MiniInput.get({ init_keys = { "I", "n" } })')
  eq(child.lua_get('_G.input_res'), 'Init')
  eq(get_state(), vim.NIL)
  -- Should stop immediately before processing the rest of `init_keys`
  validate_log('handlers_log', { { 'key', 'start', nil }, { 'key', 'progress', 'I' }, { 'key', 'accept', nil } })
end

T['get()']['stops']['when triggered during waiting for user input'] = function()
  child.lua([[
    _G.handlers_log = {}
    MiniInput.config.handlers.key = function(state, key)
      table.insert(_G.handlers_log, { 'key', state.status, key })
      if key == nil and _G.outside_stop then state.status = _G.outside_stop end
      if key ~= nil then state.input = state.input .. key end
    end
  ]])

  child.lua_notify('_G.input_res = MiniInput.get()')
  type_keys('A')
  child.lua('_G.handlers_log = {}')
  child.lua('_G.outside_stop = "accept"; MiniInput.refresh()')

  eq(child.lua_get('_G.input_res'), 'A')
  eq(get_state(), vim.NIL)
  -- Should stop immediately before processing the rest of `init_keys`
  validate_log('handlers_log', { { 'key', 'progress' }, { 'key', 'accept' } })
end

T['get()']['stops']['always after <C-c>'] = function()
  child.cmd('nnoremap <C-c> <C-\\><C-n>')
  get()
  type_keys('<C-c>')
  validate_no_input()
end

T['get()']['reports first encountered error in handler'] = function()
  child.lua([[
    local has_errored = false
    _G.key_log = {}
    MiniInput.config.handlers.key = function(state, key)
      table.insert(_G.key_log, { state.status, state.errmsg ~= nil and 'errmsg' or nil })
      if has_errored then error('Second handler error') end
      if key == 'E' then
        has_errored = true
        error('First handler error')
      end
    end
  ]])

  local mock_handler_error = function()
    child.lua([[
      vim.defer_fn(function() vim.api.nvim_input('E') end, 50)
      _G.errored_input = MiniInput.get()
    ]])
  end
  expect.error(mock_handler_error, 'First handler error')
  validate_log('key_log', { { 'start' }, { 'progress' }, { 'cancel', 'errmsg' } })
end

T['get()']['resets `state.complete` when needed'] = function()
  -- Mock custom to test that the behavior doesn't come from default handlers
  child.lua([[
    local advance_complete = function(state, increment)
      if state.complete == nil then state = MiniInput.apply_handler(state, 'complete', 'test') end
      state.complete.id = (state.complete.id + increment) % (#state.complete.items + 1)
      return state
    end

    local keycode = function(x) return vim.api.nvim_replace_termcodes(x, true, true, true) end

    MiniInput.config.handlers.key = function(state, key)
      if key == keycode('<Up>') then state = advance_complete(state, -1) end
      if key == keycode('<Down>') then state = advance_complete(state, 1) end
      if key == keycode('<Tab>') then
        state.complete.items = { 'new' }
        state.complete.id = 1
        state.input, state.caret = 'new', 4
      end
      if key == keycode('<C-x>') then state.opts.hide = not state.opts.hide end
      if key == keycode('<Left>') then state.caret = math.max(state.caret - 1, 1) end
      if key ~= nil and key:find('^%w$') ~= nil then
        state.input = state.input .. key
        state.caret = state.caret + 1
      end
      return state
    end

    MiniInput.config.handlers.complete = function(state, method)
      state.complete = { base = '', items = { 'uu', 'vv' } }
    end
  ]])

  local validate = function(input, caret, complete)
    local state = get_state()
    local out = { input = state.input, caret = state.caret, complete = state.complete }
    local ref = { input = input, caret = caret, complete = complete }
    eq(out, ref)
  end

  get()
  local complete = { base = '', id = 2, items = { 'uu', 'vv' }, method = 'test' }

  -- Should reset only after any non-highlight change not in completion
  type_keys('<Up>')
  validate('', 1, complete)

  type_keys('<Down>')
  complete.id = 0
  validate('', 1, complete)

  type_keys('<Tab>')
  complete.id = 1
  complete.items = { 'new' }
  validate('new', 4, complete)

  child.lua('MiniInput.refresh()')
  validate('new', 4, complete)

  -- - Changing input
  type_keys('a')
  validate('newa', 5, nil)

  -- - Move caret
  type_keys('<Up>')
  complete = { base = '', id = 2, items = { 'uu', 'vv' }, method = 'test' }
  validate('newa', 5, complete)

  type_keys('<Left>')
  validate('newa', 4, nil)

  -- - Change option (like `hide`; `get_state()` doesn't contain input+caret)
  type_keys('<Up>')
  complete = { base = '', id = 2, items = { 'uu', 'vv' }, method = 'test' }
  validate('newa', 4, complete)

  type_keys('<C-x>')
  validate(nil, nil, nil)
end

T['get()']['resets `state.highlight` before every step'] = function()
  mock_tracking_default_handlers()
  child.lua([[
    _G.highlight_log = {}
    MiniInput.config.handlers.highlight = function(state)
      table.insert(_G.highlight_log, state.highlight == nil)
      local w = vim.fn.strchars(state.input)
      if w > 0 then state.highlight = { { from = w, to = w, hl = 'AA' } } end
    end
  ]])

  get()
  type_keys('a', 'b', '<Left>', '<C-o>')
  eq(get_state().highlight, { { from = 2, to = 2, hl = 'AA' } })
  validate_log('highlight_log', { true, true, true, true, true })
end

T['get()']['works with language mappings'] = function()
  if child.fn.has('nvim-0.10') == 0 then
    MiniTest.skip('Helper function that gets language mappings is available only on Neovim>=0.10')
  end
  child.o.keymap = 'ukrainian-jcuken'

  eq(child.o.iminsert, 1)
  get()
  type_keys('g', 'h')
  eq(get_state().input, 'пр')

  -- Should allow changing 'iminsert' while picker is active
  child.o.iminsert = 0
  type_keys('g', 'h')
  eq(get_state().input, 'прgh')

  type_keys('<C-c>')

  -- Should work with custom "good" language mappings
  child.o.keymap = ''
  child.o.iminsert = 1
  child.cmd('lmap a 1')
  child.cmd('lmap b <char-0x1f171>')
  child.cmd('lmap cc C')

  get()
  type_keys('a', 'b', 'c', 'c')
  eq(get_state().input, '1bcc')
  type_keys('<C-u>')

  -- Should cache language mappings per input session
  child.cmd('lmap d 4')
  type_keys('d')
  eq(get_state().input, 'd')
end

T['get()']['adds to history'] = function()
  get()
  type_keys('Regular', '<CR>')
  local history = { { cwd = child.fn.getcwd(), input = 'Regular', prompt = 'Input', scope = 'editor' } }
  eq(get_history(), history)

  -- Canceled input should not be added
  get()
  type_keys('x', '<C-c>')
  eq(get_history(), history)

  -- Hidden input should not be added
  get({ hide = true })
  type_keys('Hidden', '<CR>')
  eq(get_history(), history)

  -- - Even if hidden is set interactively
  get({ hide = false })
  type_keys('Another', '<C-x>', '<CR>')
  eq(get_history(), history)

  -- Empty should be accepted
  get()
  type_keys('x', '<C-u>', '<CR>')
  history[2] = vim.deepcopy(history[1])
  history[2].input = ''
  eq(get_history(), history)
end

T['get()']['works with handlers that return new state'] = function()
  child.lua([[
    MiniInput.config.handlers.complete = function(state, method)
      local res = vim.deepcopy(state)
      res.complete = { base = '', items = { 'uu' } }
      return res
    end
    MiniInput.config.handlers.key = function(state, key)
      local res = vim.deepcopy(state)
      if key == '\t' then res = MiniInput.apply_handler(res, 'complete', 'test') end
      if key ~= nil and key:find('^%w$') ~= nil then
        res.input = res.input .. key
        res.caret = res.caret + 1
      end
      return res
    end
    MiniInput.config.handlers.highlight = function(state)
      local res = vim.deepcopy(state)
      local w = vim.fn.strchars(state.input)
      if w > 0 then res.highlight = { { from = w, to = w, hl = 'AA' } } end
      return res
    end
    MiniInput.config.handlers.view = function(state)
      local res = vim.deepcopy(state)
      res.data.n_view = (res.data.n_view or 0) + 1
      return res
    end
  ]])

  local validate = function(input, caret, complete, highlight, n_view)
    local state = get_state()
    eq(state.input, input)
    eq(state.caret, caret)
    eq(state.complete, complete)
    eq(state.highlight, highlight)
    eq(state.data.n_view, n_view)
  end

  get()
  validate('', 1, nil, nil, 1)

  type_keys('a')
  local highlight = { { from = 1, to = 1, hl = 'AA' } }
  validate('a', 2, nil, highlight, 2)

  type_keys('<Tab>')
  local complete = { base = '', id = 0, items = { 'uu' }, method = 'test' }
  validate('a', 2, complete, highlight, 3)
end

T['get()']['sets input options right away'] = function()
  local ref_init_opts = { completion = 'cmdline', hide = true, init_keys = { 's' }, prompt = 'A', scope = 'cursor' }
  child.lua('_G.opts = ' .. vim.inspect(ref_init_opts))

  child.lua_notify([[
    local dummy_handler = function() _G.dummy_handler_visit = true end
    MiniInput.config.handlers = {
      complete = dummy_handler,
      key = dummy_handler,
      highlight = dummy_handler,
      view = dummy_handler,
    }

    local track_init_state = function(state) _G.init_state = _G.init_state or vim.deepcopy(state) end
    _G.opts.handlers = {
      complete = track_init_state,
      key = track_init_state,
      highlight = track_init_state,
      view = track_init_state,
    }

    MiniInput.get(_G.opts)
  ]])

  local out_init_opts = child.lua([[
    local opts = vim.deepcopy(_G.init_state.opts)
    opts.handlers = nil
    return opts
  ]])
  eq(out_init_opts, ref_init_opts)

  eq(child.lua_get('_G.dummy_handler_visit'), vim.NIL)
end

T['get()']['redraws after all `opts.init_keys` are processed'] = function()
  child.lua([[
    local ns_id = vim.api.nvim_create_namespace('test')
    _G.n_redraws = 0
    vim.api.nvim_set_decoration_provider(ns_id, { on_start = function() _G.n_redraws = _G.n_redraws + 1 end})
  ]])

  get({ init_keys = { 'a', 'b', 'c', 'd', 'e', 'f', 'g' } })
  eq(child.lua_get('_G.n_redraws'), 3)
end

T['get()']['reacts to `VimResized`'] = function()
  -- Should refresh on resize
  child.lua([[
    _G.handlers_log = {}
    MiniInput.config.handlers.key = function(state, key)
      table.insert(_G.handlers_log, { 'key', key == nil and 0 or key, state.status })
    end
    MiniInput.config.handlers.highlight = function(state) table.insert(_G.handlers_log, { 'highlight' }) end
    MiniInput.config.handlers.view = function(state) table.insert(_G.handlers_log, { 'view' }) end
  ]])

  get()
  validate_log('handlers_log', { { 'key', 0, 'start' }, { 'highlight' }, { 'view' } })

  child.o.lines = 20
  validate_log('handlers_log', { { 'key', 0, 'progress' }, { 'highlight' }, { 'view' } })
end

T['get()']['works with non-copyable `data`'] = function()
  child.lua([[
    MiniInput.config.handlers.key = function(state, key)
      state.data.timer = state.data.timer or vim.loop.new_timer()
      if key == 'A' then state.status = 'accept' end
    end
  ]])

  local get_and_accept = function()
    child.lua([[
      vim.defer_fn(function() vim.api.nvim_input('A') end, 50)
      MiniInput.get()
    ]])
  end
  expect.no_error(get_and_accept)
end

T['get()']['preserves metatables in `data`'] = function()
  child.lua([[
    MiniInput.config.handlers.key = function(state, key)
      state.data.tbl = state.data.tbl or setmetatable({ 'a', setmetatable({ 'c' }, { 'd' }) }, { 'b' })
    end
  ]])

  get()
  eq(child.lua_get('getmetatable(MiniInput.get_state().data.tbl)'), { 'b' })
  eq(child.lua_get('getmetatable(MiniInput.get_state().data.tbl[2])'), { 'd' })
end

T['get()']['validates arguments'] = function()
  local validate = function(bad_opts, err_pattern)
    expect.error(function() child.lua('MiniInput.get(...)', { bad_opts }) end, err_pattern)
  end
  validate({ completion = 1 }, '`state%.opts%.completion`.*string')
  validate({ handlers = 1 }, '`state%.opts%.handlers`.*table')
  validate({ handlers = { complete = 1 } }, '`state%.opts%.handlers.complete`.*function')
  validate({ handlers = { key = 1 } }, '`state%.opts%.handlers.key`.*function')
  validate({ handlers = { highlight = 1 } }, '`state%.opts%.handlers.highlight`.*function')
  validate({ handlers = { view = 1 } }, '`state%.opts%.handlers.view`.*function')
  validate({ hide = 1 }, '`state%.opts%.hide`.*boolean')
  validate({ init_keys = 1 }, '`state%.opts%.init_keys`.*array')
  validate({ init_keys = { 1 } }, '`state%.opts%.init_keys`.*string')
  validate({ prompt = 1 }, '`state%.opts%.prompt`.*string')
  validate({ scope = 1 }, '`state%.opts%.scope`.*one of')
end

T['get()']['respects `vim.b.miniinput_config`'] = function()
  child.lua('MiniInput.config.scope = "editor"')
  child.b.miniinput_config = { scope = 'cursor' }

  get()
  eq(get_state().opts.scope, 'cursor')
  type_keys('<C-c>')

  -- The values from the call should still have higher priority
  get({ scope = 'window' })
  eq(get_state().opts.scope, 'window')
  type_keys('<C-c>')
end

T['ui_input()'] = new_set()

T['ui_input()']['works'] = function()
  child.lua([[
    _G.choice_log = {}
    _G.on_choice = function(...) table.insert(_G.choice_log, { ... }) end
  ]])

  child.lua_notify('MiniInput.ui_input(nil, _G.on_choice)')
  validate_input('', 1, 'editor')
  type_keys('x', '<CR>')
  validate_log('choice_log', { { 'x' } })

  child.lua_notify([[
    MiniInput.ui_input({ prompt = 'Hello?', default = 'World', completion = 'cmdline', scope = 'cursor' }, _G.on_choice)
  ]])
  local state = get_state()
  eq(state.input, 'World')
  eq(state.caret, 6)
  eq(state.opts.prompt, 'Hello?')
  eq(state.opts.init_keys, { 'World' })
  eq(state.opts.completion, 'cmdline')
  eq(state.opts.scope, 'cursor')
end

T['ui_input()']['converts `opts.highlight` to highlight handler'] = function()
  child.lua([[
    -- Global highlight handler should be respected
    _G.highlight_log = {}
    MiniInput.config.handlers.highlight = function(state)
      if state.status == 'progress' then
        table.insert(_G.highlight_log, { state.input, vim.deepcopy(state.highlight) })
      end
      if state.input == '' then return end
      state.highlight = vim.list_extend(state.highlight or {}, { { from = 1, to = 1, hl = 'Config' } })
    end

    _G.highlight = function(input)
      if input == '' then return {} end
      return {
        -- Zero-based byte indexes should be converted to 1-based char ids
        { 2, 6, 'HL' },
        -- Non-ranges should be ignored
        'plain string', { 'bad', 1, 'AA' }, { 1, 'ignore', 'AA' }, { 1, 2, false },
      }
    end

    -- Error during computation
    _G.error_highlight = function(input) error('Bad highlight function') end
  ]])

  child.lua_notify('MiniInput.ui_input({ default = "фячш", highlight = _G.highlight }, function() end)')
  eq(get_state().highlight, { { from = 2, to = 3, hl = 'HL' }, { from = 1, to = 1, hl = 'Config' } })
  validate_log('highlight_log', { { 'фячш', { { from = 2, to = 3, hl = 'HL' } } } })
  type_keys('<C-c>')

  -- Should handle errors (including properly finishing input process)
  child.lua([[
    _G.key_log = {}
    MiniInput.config.handlers.key = function(state)
      table.insert(_G.key_log, { state.input, state.status, state.errmsg ~= nil and 'errmsg' or nil })
    end
  ]])

  expect.error(
    function() child.lua('MiniInput.ui_input({ highlight = _G.error_highlight }, function() end)') end,
    '[^%)] %(mini%.input%) Error applying `highlight` handler.*[^%)] Bad highlight function'
  )
  -- - Should still properly finish input process
  validate_log('key_log', { { '', 'start' }, { '', 'cancel', 'errmsg' } })
end

T['get_state()'] = new_set()

T['get_state()']['works'] = function()
  get()

  -- Should return correct structure
  local state = get_state()
  eq(type(state), 'table')
  local keys = vim.tbl_keys(state)
  table.sort(keys)
  eq(keys, { 'caret', 'data', 'input', 'opts', 'status' })

  eq(state.caret, 1)
  eq(type(state.data), 'table')
  eq(state.input, '')
  local ref_opts = { completion = '', hide = false, init_keys = {}, prompt = 'Input', scope = 'editor' }
  ref_opts.handlers = { complete = 'function', highlight = 'function', key = 'function', view = 'function' }
  eq(state.opts, ref_opts)
  eq(state.status, 'progress')

  -- Should return up to date information
  type_keys('x')
  state = get_state()
  eq({ input = state.input, caret = state.caret }, { input = 'x', caret = 2 })

  type_keys('<Left>')
  state = get_state()
  eq({ input = state.input, caret = state.caret }, { input = 'x', caret = 1 })

  type_keys('<C-x>', '<C-o>')
  state = get_state()
  eq({ hide = state.opts.hide, scope = state.opts.scope }, { hide = true, scope = 'project' })
end

T['get_state()']['returns copy'] = function()
  get()
  local res = child.lua([[
    local state = MiniInput.get_state()
    state.status = 'cancel'
    return MiniInput.get_state().status == 'progress'
  ]])
  eq(res, true)
end

T['get_state()']['respect `opts.hide`'] = function()
  get({ hide = true })
  validate_input(nil, nil, 'editor')

  type_keys('abc')
  validate_input(nil, nil, 'editor')

  -- After interactive toggling
  type_keys('<C-x>')
  validate_input('abc', 4, 'editor')
  type_keys('<C-x>')
  validate_input(nil, nil, 'editor')
end

T['get_state()']['works with non-copyable `data`'] = function()
  child.lua([[
    MiniInput.config.handlers.key = function(state)
      state.data.timer = state.data.timer or vim.loop.new_timer()
    end
  ]])
  get()
  expect.no_error(function() child.lua('MiniInput.get_state()') end)
end

T['get_history()'] = new_set()

T['get_history()']['works'] = function()
  local cwd = child.fn.getcwd()

  eq(get_history(), {})

  mock_finished_input('World', 'Hello?', 'cursor')
  local ref_1 = { cwd = cwd, input = 'World', prompt = 'Hello?', scope = 'cursor' }
  eq(get_history(), { ref_1 })

  -- Should append new entries
  child.lua('MiniInput.config.scope = "window"')
  get({ prompt = 'Two' })
  type_keys('x', '<C-u>', '<CR>')
  local ref_2 = { cwd = cwd, input = '', prompt = 'Two', scope = 'window' }
  eq(get_history(), { ref_1, ref_2 })
end

T['get_history()']['returns copy'] = function()
  mock_finished_input('one')
  local res = child.lua([[
    local history = MiniInput.get_history()
    history[1] = 'a'
    return type(MiniInput.get_history()[1]) == 'table'
  ]])
  eq(res, true)
end

T['set_history()'] = new_set()

local set_history = forward_lua('MiniInput.set_history')

T['set_history()']['works'] = function()
  local history = { { cwd = child.fn.getcwd(), input = 'World', prompt = 'Hello?', scope = 'cursor' } }
  set_history(history)
  eq(get_history(), history)
end

T['set_history()']['uses copy'] = function()
  local res = child.lua([[
    local history = { { cwd = vim.fn.getcwd(), input = 'World', prompt = 'Hello?', scope = 'cursor' } }
    MiniInput.set_history(history)
    history[1].input = 'New one'
    return MiniInput.get_history()[1].input == 'World'
  ]])
  eq(res, true)
end

T['set_history()']['validates input'] = function()
  local validate = function(arg, pattern)
    expect.error(function() set_history(arg) end, pattern)
  end

  validate('a', '`history`.*array')
  validate({ 'a' }, '`history`.*item.*table')
  validate({ { cwd = 1, input = '', prompt = 'Input', scope = 'cursor' } }, '`history%[1%]%.cwd`.*string')
  validate({ { cwd = 'a', input = 1, prompt = 'Input', scope = 'cursor' } }, '`history%[1%]%.input`.*string')
  validate({ { cwd = 'a', input = '', prompt = 1, scope = 'cursor' } }, '`history%[1%]%.prompt`.*string')
  validate({ { cwd = 'a', input = '', prompt = 'Input', scope = 'xxx' } }, '`history%[1%]%.scope`.*one of')
end

T['refresh()'] = new_set()

local refresh = forward_lua('MiniInput.refresh')

T['refresh()']['works'] = function()
  child.lua([[
    _G.handlers_log = {}
    local key_n = 0
    MiniInput.config.handlers.key = function(state, key)
      table.insert(_G.handlers_log, { 'key', key == nil and 0 or key, state.status, _G.track })
      key_n = key_n + 1
      if key_n < 3 then return end
      state.status = 'cancel'
    end
    MiniInput.config.handlers.highlight = function(state) table.insert(_G.handlers_log, { 'highlight' }) end
    MiniInput.config.handlers.view = function(state) table.insert(_G.handlers_log, { 'view' }) end
  ]])

  -- Should work without active input
  expect.no_error(refresh)

  get()
  validate_log('handlers_log', { { 'key', 0, 'start' }, { 'highlight' }, { 'view' } })

  -- Should call all handlers with `key=nil`
  child.lua('_G.track = true')
  refresh()
  validate_log('handlers_log', { { 'key', 0, 'progress', true }, { 'highlight' }, { 'view' } })

  -- Should react to ending the input
  child.lua('_G.track = nil')
  refresh()
  validate_no_input()
  --stylua: ignore
  local ref_log = {
    { 'key', 0, 'progress' }, { 'highlight' }, { 'view' },
    { 'key', 0, 'cancel' },   { 'highlight' }, { 'view' },
  }
  validate_log('handlers_log', ref_log)
end

T['gen_highlight'] = new_set()

T['gen_highlight']['treesitter()'] = new_set()

T['gen_highlight']['treesitter()']['works'] = function()
  if child.fn.has('nvim-0.10') == 0 then MiniTest.skip('Upstream has issues on Neovim<=0.9') end

  local validate = function(lang, input, hl_ranges)
    child.lua('_G.lang = ' .. vim.inspect(lang))
    mock_state({ input = input })
    child.lua('_G.mock_state.opts.handlers.highlight = MiniInput.gen_highlight.treesitter(_G.lang)')
    child.lua('_G.new_state = MiniInput.apply_handler(vim.deepcopy(_G.mock_state), "highlight")')
    local old_state = get_state('mock_state')
    local new_state = get_state('new_state')

    local highlight
    if hl_ranges ~= nil then
      highlight = vim.tbl_map(function(x) return { from = x[1], to = x[2], hl = x[3] } end, hl_ranges)
    end
    eq(compute_changed_values(old_state, new_state), { highlight = highlight })
  end

  local hl_ranges = { { 1, 3, '@keyword.vim' }, { 5, 14, '@variable.builtin.vim' }, { 15, 15, '@operator.vim' } }
  validate('vim', 'set shiftwidth=2', hl_ranges)

  -- Should work with injections
  hl_ranges =
    { { 1, 3, '@keyword.vim' }, { 5, 5, '@variable.lua' }, { 7, 7, '@operator.lua' }, { 9, 9, '@number.lua' } }
  validate('vim', 'lua a = 1', hl_ranges)

  -- Should work with multibyte characters
  validate('vim', 'echo "фячш"', { { 1, 4, '@keyword.vim' }, { 6, 11, '@string.vim' } })

  -- Should not error on unknown language
  validate('unknown', 'hello', nil)
end

T['gen_highlight']['treesitter()']['appends to existing highlight'] = function()
  if child.fn.has('nvim-0.10') == 0 then MiniTest.skip('Upstream has issues on Neovim<=0.9') end

  mock_state({ input = 'set shiftwidth=2' })
  child.lua([[
    _G.mock_state.highlight = { { from = 1, to = 16, hl = 'AA' } }
    _G.mock_state.opts.handlers.highlight = MiniInput.gen_highlight.treesitter("vim")
    _G.new_state = MiniInput.apply_handler(vim.deepcopy(_G.mock_state), "highlight")
  ]])
  local old_state = get_state('mock_state')
  local new_state = get_state('new_state')

  local ref_changes = {
    highlight = {
      -- Should be appended to already present first range
      [2] = { from = 1, to = 3, hl = '@keyword.vim' },
      [3] = { from = 5, to = 14, hl = '@variable.builtin.vim' },
      [4] = { from = 15, to = 15, hl = '@operator.vim' },
    },
  }
  eq(compute_changed_values(old_state, new_state), ref_changes)
end

T['gen_view'] = new_set()

T['gen_view']['floatwin()'] = new_set({
  hooks = { pre_case = { function() child.lua('MiniInput.config.handlers.view = MiniInput.gen_view.floatwin()') end } },
})

T['gen_view']['floatwin()']['works'] = function()
  local expect_screenshot = function() child.expect_screenshot({ redraw = false, ignore_cmdline = true }) end
  get({ prompt = 'Hello?' })
  expect_screenshot()

  -- Should store relevant data
  local state = get_state()
  local buf_id, win_id = state.data.floatwin_buf_id, state.data.floatwin_win_id
  eq(child.api.nvim_buf_is_valid(buf_id), true)
  eq(child.api.nvim_win_is_valid(win_id), true)

  -- Should use high enough zindex to be on top of other 'mini.nvim' windows
  eq(child.api.nvim_win_get_config(win_id).zindex > 251, true)

  -- Should react to text and caret change
  type_keys('a')
  expect_screenshot()
  type_keys('<Left>')
  expect_screenshot()

  -- Should not have side effect after finishing input
  type_keys('<CR>')
  expect_screenshot()
  eq(child.api.nvim_buf_is_valid(buf_id), false)
  eq(child.api.nvim_win_is_valid(win_id), false)

  get()
  state = get_state()
  buf_id, win_id = state.data.floatwin_buf_id, state.data.floatwin_win_id
  type_keys('<C-c>')
  eq(child.api.nvim_buf_is_valid(buf_id), false)
  eq(child.api.nvim_win_is_valid(win_id), false)
end

T['gen_view']['floatwin()']['uses scope and style for config'] =
  new_set({ hooks = { pre_case = function() child.set_size(15, 30) end } })

local validate_floatwin_scope_style = function(scope, style, prompt, screnshot_path)
  child.lua('_G.style = ' .. vim.inspect(style))
  child.lua('_G.scope = ' .. vim.inspect(scope))
  child.lua('_G.prompt = ' .. vim.inspect(prompt))
  child.lua_notify([[
    local view = MiniInput.gen_view.floatwin({ style = _G.style })
    MiniInput.get({ prompt = _G.prompt or _G.style, scope = scope, handlers = { view = view } })
  ]])
  child.expect_screenshot({ ignore_cmdline = true }, screnshot_path)
  type_keys('<C-c>')
end

T['gen_view']['floatwin()']['uses scope and style for config']['scope=cursor'] = function()
  -- Set up layout to test that window is located around the cursor position
  -- and can cross window boundary
  child.cmd('wincmd s | wincmd v | wincmd j | wincmd v | wincmd k')
  set_lines({ 'aaaaaaaaaaa', '', '', '', '', 'fffffffffff', 'ggggggggggg' })
  set_cursor(7, 10)

  validate_floatwin_scope_style('cursor', 'BL')
  validate_floatwin_scope_style('cursor', 'ML')
  validate_floatwin_scope_style('cursor', 'TL')
  validate_floatwin_scope_style('cursor', 'BM')
  validate_floatwin_scope_style('cursor', 'MM')
  validate_floatwin_scope_style('cursor', 'TM')
  validate_floatwin_scope_style('cursor', 'BR')
  validate_floatwin_scope_style('cursor', 'MR')
  validate_floatwin_scope_style('cursor', 'TR')

  -- Works with too wide prompt
  validate_floatwin_scope_style('cursor', 'BL', 'A very-very-very-very wide prompt')

  -- Works when at the edge of the instance
  if child.fn.has('nvim-0.10') == 1 then
    set_cursor(1, 0)
    validate_floatwin_scope_style('cursor', 'BR')

    child.cmd('wincmd j | wincmd l')
    set_cursor(6, 10)
    validate_floatwin_scope_style('cursor', 'TL')
  end
end

T['gen_view']['floatwin()']['uses scope and style for config']['scope=line'] = function()
  -- Set up layout to test that window is located around the cursor position
  -- and can cross window boundary
  child.cmd('wincmd s | wincmd v | wincmd j | wincmd v | wincmd k')
  set_lines({ 'aaaaaaaaaaa', '', '', '', '', 'fffffffffff', 'ggggggggggg' })
  set_cursor(7, 10)

  validate_floatwin_scope_style('line', 'BL')
  validate_floatwin_scope_style('line', 'ML')
  validate_floatwin_scope_style('line', 'TL')
  validate_floatwin_scope_style('line', 'BM')
  validate_floatwin_scope_style('line', 'MM')
  validate_floatwin_scope_style('line', 'TM')
  validate_floatwin_scope_style('line', 'BR')
  validate_floatwin_scope_style('line', 'MR')
  validate_floatwin_scope_style('line', 'TR')

  -- Works with too wide prompt
  validate_floatwin_scope_style('line', 'BL', 'A very-very-very-very wide prompt')
  validate_floatwin_scope_style('line', 'MM', 'A very-very-very-very wide prompt')
  validate_floatwin_scope_style('line', 'TR', 'A very-very-very-very wide prompt')

  -- Works when at the edge of the instance
  if child.fn.has('nvim-0.10') == 1 then
    set_cursor(1, 0)
    validate_floatwin_scope_style('line', 'BL')

    child.cmd('wincmd j | wincmd l')
    set_cursor(6, 10)
    validate_floatwin_scope_style('line', 'TR')
  end
end

local validate_floatwin_common_layout = function(scope, ref_path_prefix)
  child.cmd('wincmd s | wincmd s | wincmd j | wincmd v | wincmd v | wincmd l | wincmd 5> | wincmd 3+')

  validate_floatwin_scope_style(scope, 'BL', nil, ref_path_prefix)
  validate_floatwin_scope_style(scope, 'ML', nil, ref_path_prefix .. '-002')
  validate_floatwin_scope_style(scope, 'TL', nil, ref_path_prefix .. '-003')
  validate_floatwin_scope_style(scope, 'BM', nil, ref_path_prefix .. '-004')
  validate_floatwin_scope_style(scope, 'MM', nil, ref_path_prefix .. '-005')
  validate_floatwin_scope_style(scope, 'TM', nil, ref_path_prefix .. '-006')
  validate_floatwin_scope_style(scope, 'BR', nil, ref_path_prefix .. '-007')
  validate_floatwin_scope_style(scope, 'MR', nil, ref_path_prefix .. '-008')
  validate_floatwin_scope_style(scope, 'TR', nil, ref_path_prefix .. '-009')

  -- Works with too wide prompt
  validate_floatwin_scope_style(scope, 'BL', 'A very-very-very-very wide prompt', ref_path_prefix .. '-010')
  validate_floatwin_scope_style(scope, 'MM', 'A very-very-very-very wide prompt', ref_path_prefix .. '-011')
  validate_floatwin_scope_style(scope, 'TR', 'A very-very-very-very wide prompt', ref_path_prefix .. '-012')

  child.cmd('wincmd o')
end

T['gen_view']['floatwin()']['uses scope and style for config']['scope=buffer,window'] = function()
  -- Buffer and window scopes should behave exactly the same
  local ref_path_prefix = table.concat({
    'tests',
    'screenshots',
    'tests-test_input.lua---gen_view---floatwin()---uses-scope-and-style-for-config---scope=buffer,window',
  }, '/')
  validate_floatwin_common_layout('buffer', ref_path_prefix)
  validate_floatwin_common_layout('window', ref_path_prefix)

  -- Works when at the edge of the instance
  validate_floatwin_scope_style('buffer', 'TL', nil, ref_path_prefix .. '-013')
  validate_floatwin_scope_style('buffer', 'BR', nil, ref_path_prefix .. '-014')
  validate_floatwin_scope_style('window', 'TL', nil, ref_path_prefix .. '-013')
  validate_floatwin_scope_style('window', 'BR', nil, ref_path_prefix .. '-014')
end

T['gen_view']['floatwin()']['uses scope and style for config']['scope=tabpage,editor,project'] = function()
  -- Tabpage, editor, and project scopes should behave exactly the same
  local ref_path_prefix = table.concat({
    'tests',
    'screenshots',
    'tests-test_input.lua---gen_view---floatwin()---uses-scope-and-style-for-config---scope=tabpagae,editor,project',
  }, '/')
  validate_floatwin_common_layout('tabpage', ref_path_prefix)
  validate_floatwin_common_layout('editor', ref_path_prefix)
  validate_floatwin_common_layout('project', ref_path_prefix)
end

T['gen_view']['floatwin()']['uses correct highlight groups'] = function()
  child.lua([[
    MiniInput.config.handlers.complete = function(state, method)
      state.complete = { base = '', items = { 'uu' } }
    end
  ]])
  local get_win_data = function()
    local win_id = get_state().data.floatwin_win_id
    return win_id, child.api.nvim_win_get_config(win_id)
  end
  local validate_winhl = function(win_id, entry)
    local winhl = child.api.nvim_get_option_value('winhighlight', { win = win_id })
    expect.match(winhl, entry)
  end

  get({ prompt = 'A', completion = 'test' })
  local win_id, config = get_win_data()
  eq(config.title, { { ' A ', 'MiniInputPrompt' } })
  eq(config.footer, child.fn.has('nvim-0.10') == 1 and { { '', 'MiniInputHint' } } or nil)
  validate_winhl(win_id, 'NormalFloat:MiniInputNormal')
  validate_winhl(win_id, 'FloatBorder:MiniInputBorder')

  type_keys('<Tab>')
  win_id, config = get_win_data()
  eq(config.title, { { ' A ', 'MiniInputPrompt' } })
  if child.fn.has('nvim-0.10') == 1 then eq(config.footer, { { ' test 1/1 ', 'MiniInputHint' } }) end

  type_keys('<C-x>')
  eq(get_state().opts.hide, true)
  win_id, config = get_win_data()
  eq(config.title, { { ' A ', 'MiniInputHide' } })
  validate_winhl(win_id, 'NormalFloat:MiniInputNormal')
  validate_winhl(win_id, 'FloatBorder:MiniInputBorder')
end

T['gen_view']['floatwin()']['shows complete hint in footer'] = function()
  if child.fn.has('nvim-0.10') == 0 then MiniTest.skip('Window footer is available only on Neovim>=0.10') end
  child.lua([[
    MiniInput.config.handlers.complete = function(state, method)
      state.complete = { base = '', items = { 'uu' } }
    end
  ]])
  local validate = function(opts_completion, key)
    get({ prompt = 'A', completion = opts_completion })
    type_keys(key)
    child.expect_screenshot({ ignore_cmdline = true })
    type_keys('<C-c>')
  end

  validate(nil, '<Tab>')
  validate('', '<Tab>')
  -- Should show method and try to adjust width to show both title and footer
  validate('cmdline', '<Tab>')
  validate(nil, '<Up>')
end

T['gen_view']['floatwin()']['can hide border text'] = function()
  if child.fn.has('nvim-0.10') == 0 then MiniTest.skip('Window footer is available only on Neovim>=0.10') end
  local expect_screenshot = function() child.expect_screenshot({ ignore_cmdline = true }) end

  child.lua([[
    MiniInput.config.handlers.complete = function(state, method)
      state.complete = { base = '', items = { 'uu' } }
    end
    MiniInput.config.handlers.key = function(state, key)
      if key == 'h' then state.opts.prompt = '' end
      if key == 'q' then state.opts.prompt = 'New' end
      return MiniInput.default_key(state, key)
    end
  ]])

  get({ prompt = 'AAA', completion = 'test' })
  type_keys('<Tab>')
  expect_screenshot()
  type_keys('<Left>')
  expect_screenshot()
  type_keys('h')
  expect_screenshot()
  type_keys('q')
  expect_screenshot()
end

T['gen_view']['floatwin()']['works with multibyte characters'] = function()
  local expect_screenshot = function() child.expect_screenshot({ redraw = false, ignore_cmdline = true }) end

  get({ prompt = 'фt🬗' })
  expect_screenshot()
  type_keys('фt🬗фt🬗')
  expect_screenshot()
  type_keys('<Left><Left><Left>')
  expect_screenshot()
  type_keys('<C-c>')

  -- Double-width characters
  get({ prompt = '「」' })
  expect_screenshot()
  type_keys('「」「」')
  expect_screenshot()
  type_keys('<Left><Left>')
  expect_screenshot()
  type_keys('<C-c>')
end

T['gen_view']['floatwin()']['sanitizes border text'] = function()
  if child.fn.has('nvim-0.10') == 0 then MiniTest.skip('Window footer is available only on Neovim>=0.10') end

  child.set_size(10, 40)
  child.lua([[
    MiniInput.config.handlers.complete = function(state, method)
      state.complete = { base = '', items = { 'uu' } }
    end
  ]])
  get({ prompt = 'Bad\000multi\nline\nprompt\ttext\n', completion = 'Bad\000compl\netion\ttext\n' })
  type_keys('<Tab>')
  child.expect_screenshot()
end

T['gen_view']['floatwin()']['truncates border text'] = function()
  if child.fn.has('nvim-0.10') == 0 then MiniTest.skip('Window footer is available only on Neovim>=0.10') end
  local expect_screenshot = function() child.expect_screenshot({ ignore_cmdline = true }) end

  child.lua([[
    MiniInput.config.handlers.complete = function(state, method)
      state.complete = { base = '', items = { 'uu' } }
    end
  ]])

  local validate = function(ref_text)
    get({ prompt = ref_text, completion = vim.fn.toupper(ref_text) })
    type_keys('<Tab>')
    expect_screenshot()
    type_keys('<C-c>')
  end

  validate('abcdefghijklmnopqrstu')
  validate('абвгґдеєжзиіїйклмноп')
  validate('「」『』《》〈〉【】')
end

T['gen_view']['floatwin()']["respects 'winborder' option"] = function()
  if child.fn.has('nvim-0.11') == 0 then MiniTest.skip("'winborder' option is present on Neovim>=0.11") end

  local validate = function(winborder)
    child.o.winborder = winborder
    get()
    child.expect_screenshot({ ignore_cmdline = true })
    type_keys('<C-c>')
  end

  validate('rounded')

  -- Should work with "string array" 'winborder'
  if child.fn.has('nvim-0.12') == 0 then MiniTest.skip("String array 'winborder' is present on Neovim>=0.12") end
  validate('+,-,+,|,+,-,+,|')
end

T['gen_view']['floatwin()']['works with `winborder=none`'] = function()
  if child.fn.has('nvim-0.11') == 0 then MiniTest.skip("'winborder' option is present on Neovim>=0.11") end

  child.set_size(5, 30)
  child.o.winborder = 'none'

  local cwd = child.fn.getcwd()
  set_history({ { cwd = cwd, prompt = 'Hello?', input = 'World prev', scope = 'editor' } })

  -- Should show prompt and completion hint inline
  get({ prompt = 'Hello?' })
  child.expect_screenshot()
  type_keys('World new')
  child.expect_screenshot()
  type_keys('<Left><Left><Left><Up>')
  child.expect_screenshot()
  type_keys('<C-c>')

  -- Should correctly compute width for maximum chunks width
  child.lua([[
    _G.to_chunks_log = {}
    local to_chunks = function(state, max_width)
      table.insert(_G.to_chunks_log, { state.input, max_width })
      return MiniInput.state_to_chunks(state, max_width)
    end
    MiniInput.config.handlers.view = MiniInput.gen_view.floatwin({ to_chunks = to_chunks })
  ]])
  get({ prompt = 'Truncate?' })
  type_keys('abcdefghijklmnopqrstu')
  child.lua('_G.to_chunks_log = {}')

  type_keys('v')
  validate_log('to_chunks_log', { { 'abcdefghijklmnopqrstuv', nil }, { 'abcdefghijklmnopqrstuv', 30 } })
  child.expect_screenshot()
end

T['gen_view']['floatwin()']["respects tabline, statusline, 'cmdheight'"] = function()
  local validate = function(showtabline, laststatus)
    child.o.showtabline, child.o.laststatus = showtabline, laststatus
    validate_floatwin_scope_style('editor', 'BL')
    validate_floatwin_scope_style('editor', 'TR')
  end

  validate(2, 2)
  validate(2, 0)
  validate(0, 2)
  validate(0, 0)

  child.o.cmdheight = 2
  validate(0, 0)
  child.o.cmdheight = 0
  validate(0, 0)
end

T['gen_view']['floatwin()']['respects `opts.adjust_config`'] = function()
  -- Should prefer explicitly configured value over 'winborder'
  if child.fn.has('nvim-0.11') == 1 then child.o.winborder = 'rounded' end

  child.lua([[
    _G.adjust_config_log = {}
    local adjust_config = function(state, config)
      table.insert(_G.adjust_config_log, { state.input, config.anchor })
      config.border = 'double'
      config.title = state.input
      return config
    end
    MiniInput.config.handlers.view = MiniInput.gen_view.floatwin({ adjust_config = adjust_config })
  ]])

  get()
  type_keys('a')
  child.expect_screenshot({ ignore_cmdline = true })
  validate_log('adjust_config_log', { { '', 'NW' }, { 'a', 'NW' } })
end

T['gen_view']['floatwin()']['respects `opts.to_chunks`'] = function()
  child.set_size(5, 15)

  child.lua([[
    _G.to_chunks_log = {}
    local to_chunks = function(state, max_width)
      table.insert(_G.to_chunks_log, { state.input, max_width })
      return _G.chunks
    end
    MiniInput.config.handlers.view = MiniInput.gen_view.floatwin({ to_chunks = to_chunks })
  ]])

  local validate = function(chunks, ref_log)
    child.lua('_G.chunks = ' .. vim.inspect(chunks))
    get({ prompt = 'A' })
    child.expect_screenshot()
    type_keys('a')
    type_keys('<C-c>')

    validate_log('to_chunks_log', ref_log)
  end

  -- - Should compute chunks twice: first - for window width computation,
  --   second - for final chunks computation with known window width.
  validate({ { 'abcdef', 'Test' } }, { { '', nil }, { '', 6 }, { 'a', nil }, { 'a', 6 } })

  -- Should not wrap text and respect global 'listchars'
  child.o.wrap = true
  child.go.list = true
  child.go.listchars = 'extends:>'
  validate({ { 'very-very wide chunk', 'Test' } }, { { '', nil }, { '', 13 }, { 'a', nil }, { 'a', 13 } })

  -- Should validate `to_chunks` output
  local validate_error = function(chunks, err_pattern)
    child.lua('_G.chunks = ' .. vim.inspect(chunks))
    expect.error(function() child.lua('MiniInput.get()') end, err_pattern)
  end
  validate_error(1, '`opts%.to_chunks%(state, nil%)`.*array')
  validate_error({ 1 }, 'Every `opts%.to_chunks%(state, nil%)` item.*table')
  validate_error({ { 1, 'Test' } }, '`opts%.to_chunks%(state, nil%)%[1%]%[1%]`.*string')
  validate_error({ { 'a', 1 } }, '`opts%.to_chunks%(state, nil%)%[1%]%[2%]`.*string')
end

T['gen_view']['floatwin()']['can change style'] = function()
  get()
  child.expect_screenshot({ ignore_cmdline = true })

  -- Should change style in specific order
  local validate = function()
    type_keys('<C-s>')
    child.expect_screenshot({ ignore_cmdline = true })
  end
  validate()
  validate()
  validate()
  validate()
  validate()
  validate()
  validate()
  validate()
  validate()
end

T['gen_view']['floatwin()']['reacts to `state.opts` change'] = function()
  local expect_screenshot = function() child.expect_screenshot({ ignore_cmdline = true }) end

  -- Scope
  set_lines({ '', '', '', 'aaa' })
  set_cursor(4, 2)
  get({ scope = 'cursor' })
  type_keys('abc')
  expect_screenshot()

  type_keys('<C-o>')
  expect_screenshot()
  type_keys('<C-o>')
  expect_screenshot()

  -- Hide
  type_keys('<C-x>')
  expect_screenshot()
  type_keys('<C-x>')
  expect_screenshot()
end

T['gen_view']['floatwin()']['works with floating current window'] = function()
  child.set_size(10, 30)
  child.cmd('only | mode')
  local buf_id = child.api.nvim_create_buf(false, true)
  local config =
    { relative = 'editor', row = 3, col = 10, height = 5, width = 15, style = 'minimal', border = 'single' }
  local win_id = child.api.nvim_open_win(buf_id, true, config)
  set_lines({ 'ddd', 'eee', 'fff' })
  set_cursor(2, 2)

  local validate = function(scope, style, keys)
    child.lua('_G.style = ' .. vim.inspect(style))
    child.lua('MiniInput.config.handlers.view = MiniInput.gen_view.floatwin({ style = _G.style })')

    get({ prompt = 'Prompt', scope = scope })
    type_keys(keys)
    child.expect_screenshot()
    type_keys('<C-c>')
  end

  validate('cursor', 'BL', { 'aaa' })
  validate('cursor', 'MM', { 'aaa' })
  validate('cursor', 'TR', { 'aaa' })

  local wide_input_keys = { 'very-very-very wide', string.rep('<Left>', 10) }
  validate('line', 'BL', wide_input_keys)
  validate('line', 'MM', wide_input_keys)
  validate('line', 'TR', wide_input_keys)

  validate('window', 'BL', wide_input_keys)
  validate('window', 'MM', wide_input_keys)
  validate('window', 'TR', wide_input_keys)

  -- Should also work with no border
  child.api.nvim_win_set_config(win_id, { border = 'none' })
  validate('cursor', 'BL', { 'aaa' })
  validate('line', 'BL', wide_input_keys)
  validate('window', 'BL', wide_input_keys)
end

T['gen_view']['floatwin()']['validates input'] = function()
  local validate = function(bad_opts, err_pattern)
    expect.error(function() child.lua('MiniInput.gen_view.floatwin(...)', { bad_opts }) end, err_pattern)
  end
  validate({ adjust_config = 1 }, '`opts.adjust_config`.*callable')
  validate({ style = 1 }, '`opts.style`.*one of')
  validate({ to_chunks = 1 }, '`opts.to_chunks`.*callable')
end

T['gen_view']['uiline()'] = new_set({
  hooks = {
    pre_case = function()
      child.set_size(10, 35)

      child.lua([[
        MiniInput.config.handlers.complete = function(state, method)
          state.complete = { base = '', items = { 'uu', 'vv' } }
        end

        MiniInput.config.handlers.view = MiniInput.gen_view.uiline()
      ]])

      -- Set up two windows for testing window-local behavior
      child.cmd('wincmd v')
    end,
  },
})

local validate_uiline = function(style)
  child.lua('_G.style = ' .. vim.inspect(style))
  child.lua('MiniInput.config.handlers.view = MiniInput.gen_view.uiline({ style = _G.style })')

  -- Should handle characters that are special for UI lines
  get({ prompt = 'AA%A' })
  child.expect_screenshot()

  -- Should show typed keys and completion
  type_keys('ab%c', '<Tab>')
  child.expect_screenshot()

  -- Should correctly use correct highlight groups
  local opts_info = style == 'tabline' and { scope = 'global' } or { scope = 'local', win = 0 }
  local statusline_cur = child.api.nvim_get_option_value(style, opts_info)
  local ref_statusline = table.concat({
    '%#MiniInputPrompt#AA%%A',
    '%#MiniInputNormal# ',
    '%#MiniInputNormal#ab%%c',
    '%#MiniInputAdded#uu',
    '%#MiniInputCaret#▏',
    '%#MiniInputHint#(1/2)',
    '%#MiniInputNormal#',
  })
  eq(statusline_cur, ref_statusline)

  -- Should cleanly stop without side effects
  type_keys('<C-c>')
  child.expect_screenshot()

  child.lua('MiniInput.config.handlers.view = MiniInput.gen_view.uiline()')
end

T['gen_view']['uiline()']['works with `style="statusline"`'] = function()
  local validate = function(laststatus)
    child.o.laststatus = laststatus
    validate_uiline('statusline')
    eq(child.o.laststatus, laststatus)
  end

  validate(0)
  validate(1)
  validate(2)
  validate(3)

  -- This should also be the default style
  child.lua('MiniInput.config.handlers.view = MiniInput.gen_view.uiline()')
  get({ prompt = 'AAA' })
  eq(child.o.statusline, '%#MiniInputPrompt#AAA%#MiniInputNormal# %#MiniInputCaret#▏%#MiniInputNormal#')
  if child.fn.has('nvim-0.10') == 1 then eq(child.o.tabline, 'My tabline') end
  eq(child.o.winbar, '')
  type_keys('<C-c>')
end

T['gen_view']['uiline()']['works with `style="tabline"`'] = function()
  if child.fn.has('nvim-0.10') == 0 then MiniTest.skip("'tabline' restoration has upstream issues on Neovim<0.10") end

  local validate = function(showtabline)
    child.o.showtabline = showtabline
    validate_uiline('tabline')
    eq(child.o.showtabline, showtabline)
  end

  validate(0)
  validate(1)
  validate(2)
end

T['gen_view']['uiline()']['works with `style="winbar"`'] = function()
  child.o.winbar = ''
  validate_uiline('winbar')
  eq(child.o.winbar, '')
end

T['gen_view']['uiline()']['respects `opts.to_chunks`'] = function()
  child.set_size(5, 35)

  child.lua([[
    _G.to_chunks_log = {}
    _G.to_chunks = function(state, max_width)
      table.insert(_G.to_chunks_log, { state.input, max_width })
      return _G.chunks
    end
  ]])

  local validate = function(style, chunks, ref_log)
    child.lua('_G.style = ' .. vim.inspect(style))
    child.lua('_G.chunks = ' .. vim.inspect(chunks))
    child.lua([[
      local opts = { style = _G.style, to_chunks = _G.to_chunks }
      MiniInput.config.handlers.view = MiniInput.gen_view.uiline(opts)
    ]])

    get({ prompt = 'A' })
    child.expect_screenshot()
    type_keys('a')
    type_keys('<C-c>')

    validate_log('to_chunks_log', ref_log)
  end

  -- Should correctly compute maximum width for either window or editor
  validate('statusline', { { 'abcdef', 'Test' } }, { { '', 17 }, { 'a', 17 } })
  validate('statusline', { { 'very-very wide chunk', 'Test' } }, { { '', 17 }, { 'a', 17 } })
  validate('tabline', { { 'abcdef', 'Test' } }, { { '', 35 }, { 'a', 35 } })
  validate('tabline', { { 'very-very-very-very-very-very wide chunk', 'Test' } }, { { '', 35 }, { 'a', 35 } })
  validate('winbar', { { 'abcdef', 'Test' } }, { { '', 17 }, { 'a', 17 } })
  validate('winbar', { { 'very-very wide chunk', 'Test' } }, { { '', 17 }, { 'a', 17 } })

  -- Should validate `to_chunks` output
  local validate_error = function(chunks, err_pattern)
    child.lua('_G.chunks = ' .. vim.inspect(chunks))
    expect.error(function() child.lua('MiniInput.get()') end, err_pattern)
  end
  validate_error(1, '`opts%.to_chunks%(state, 17%)`.*array')
  validate_error({ 1 }, 'Every `opts%.to_chunks%(state, 17%)` item.*table')
  validate_error({ { 1, 'Test' } }, '`opts%.to_chunks%(state, 17%)%[1%]%[1%]`.*string')
  validate_error({ { 'a', 1 } }, '`opts%.to_chunks%(state, 17%)%[1%]%[2%]`.*string')
end

T['gen_view']['uiline()']['can change style'] = function()
  get()
  child.expect_screenshot({ ignore_cmdline = true })

  -- Should change style in specific order
  local validate = function()
    type_keys('<C-s>')
    child.expect_screenshot({ ignore_cmdline = true })
  end
  validate()
  validate()
  validate()
end

T['gen_view']['uiline()']['reacts to `state.opts` change'] = function()
  local expect_screenshot = function() child.expect_screenshot({ ignore_cmdline = true }) end

  child.cmd('only | mode')
  child.set_size(10, 20)

  get({ scope = 'cursor' })
  type_keys('abc')
  expect_screenshot()

  -- No reaction to scope change
  type_keys('<C-o>')
  expect_screenshot()

  -- Hide
  child.lua('vim.notify = function() end')
  type_keys('<C-x>')
  expect_screenshot()
  local ref =
    '%#MiniInputHide#Input%#MiniInputNormal# %#MiniInputNormal#•••%#MiniInputCaret#▏%#MiniInputNormal#'
  eq(child.o.statusline, ref)
  type_keys('<C-x>')
  expect_screenshot()
end

T['gen_view']['uiline()']['can choose initial style based on scope'] = function()
  child.lua([[
    local view_tabline = MiniInput.gen_view.uiline({ style = 'tabline' })
    local view_winbar = MiniInput.gen_view.uiline({ style = 'winbar' })
    MiniInput.config.handlers.view = function(state)
      local scope, view = state.opts.scope, view_winbar
      if scope == 'tabpage' or scope == 'editor' or scope == 'project' then view = view_tabline end
      return view(state)
    end
  ]])

  get({ scope = 'cursor' })
  child.expect_screenshot({ ignore_cmdline = true })
  type_keys('<C-c>')

  get({ scope = 'tabpage' })
  child.expect_screenshot({ ignore_cmdline = true })
  type_keys('<C-c>')
end

T['gen_view']['uiline()']['works with floating current window'] = function()
  child.set_size(10, 20)
  child.cmd('only | mode')
  local buf_id = child.api.nvim_create_buf(false, true)
  local config = { relative = 'editor', row = 2, col = 2, height = 2, width = 10, style = 'minimal', border = 'single' }
  child.api.nvim_open_win(buf_id, true, config)
  child.o.laststatus = 2

  local validate = function(style)
    child.lua('_G.style = ' .. vim.inspect(style))
    child.lua('MiniInput.config.handlers.view = MiniInput.gen_view.uiline({ style = _G.style })')

    get({ prompt = 'Prompt' })
    -- - Should correctly compute available width for truncattion
    type_keys('very-very-very wide', string.rep('<Left>', 10))
    child.expect_screenshot()
    type_keys('<CR>')
    child.expect_screenshot()
  end
  validate('tabline')
  validate('winbar')
  -- Statusline in floating windows can only be shown in Neovim>=0.12
  if child.fn.has('nvim-0.12') == 1 then validate('statusline') end
end

T['gen_view']['uiline()']['validates input'] = function()
  local validate = function(bad_opts, err_pattern)
    expect.error(function() child.lua('MiniInput.gen_view.uiline(...)', { bad_opts }) end, err_pattern)
  end
  validate({ style = 1 }, '`opts.style`.*one of')
  validate({ to_chunks = 1 }, '`opts.to_chunks`.*callable')
end

T['gen_view']['virtual()'] = new_set({
  hooks = {
    pre_case = function()
      child.set_size(10, 35)

      child.lua([[
        MiniInput.config.handlers.complete = function(state, method)
          state.complete = { base = '', items = { 'uu', 'vv' } }
        end

        MiniInput.config.handlers.view = MiniInput.gen_view.virtual()
      ]])

      -- Set up two windows and two buffers for testing window-local behavior
      child.api.nvim_set_current_buf(child.api.nvim_create_buf(true, false))
      child.cmd('wincmd v')
      child.api.nvim_win_set_width(0, 25)
      child.api.nvim_set_current_buf(child.api.nvim_create_buf(true, false))
      set_lines({ 'aaa', 'bbb', 'ccc' })
      set_cursor(2, 2)
    end,
  },
})

local validate_single_extmark = function(ref_position, ref_details)
  local all_extmarks = child.api.nvim_buf_get_extmarks(0, -1, 0, -1, { details = true })
  eq(#all_extmarks, 1)

  eq(all_extmarks[1][2], ref_position[1] - 1)
  eq(all_extmarks[1][3], ref_position[2])

  local details = all_extmarks[1][4]
  for k, v in pairs(ref_details) do
    eq(details[k], v)
  end
end

local validate_virtual = function(style, ref_details_1, ref_details_2)
  child.lua('_G.style = ' .. vim.inspect(style))
  child.lua('MiniInput.config.handlers.view = MiniInput.gen_view.virtual({ style = _G.style })')

  local lines = get_lines()
  local cursor = { 2, 2 }
  set_cursor(unpack(cursor))

  -- Should show input while preserving lines and cursor position
  get({ prompt = 'AAA' })
  child.expect_screenshot()
  eq(get_lines(), lines)
  eq(get_cursor(), cursor)
  -- - Should correctly place and use correct extmark details
  validate_single_extmark(cursor, ref_details_1)

  -- Should show typed keys and completion
  type_keys('abc', '<Tab>')
  child.expect_screenshot()
  eq(get_lines(), lines)
  eq(get_cursor(), cursor)
  validate_single_extmark(cursor, ref_details_2)

  -- Should cleanly stop without side effects
  type_keys('<C-c>')
  child.expect_screenshot()
  eq(child.api.nvim_buf_get_extmarks(0, -1, 0, -1, {}), {})

  child.lua('MiniInput.config.handlers.view = nil')
end

local validate_virtual_lines = function(above)
  local priority = child.fn.has('nvim-0.10') == 1 and 4096 or nil
  local ref_details_1 = { priority = priority, virt_lines_above = above }
  -- Should pad with whitespace suffix to occupy the whole line
  local ref_chunks_1 = with_prompt_chunks({ caret_ch, { '                    ', 'MiniInputNormal' } }, 'AAA')
  ref_details_1.virt_lines = { ref_chunks_1 }

  local ref_details_2 = vim.deepcopy(ref_details_1)
  local ref_chunks_2 = with_prompt_chunks({
    { 'abc', 'MiniInputNormal' },
    { 'uu', 'MiniInputAdded' },
    caret_ch,
    { '(1/2)', 'MiniInputHint' },
    { '          ', 'MiniInputNormal' },
  }, 'AAA')
  ref_details_2.virt_lines = { ref_chunks_2 }
  validate_virtual(above and 'above' or 'below', ref_details_1, ref_details_2)
end

T['gen_view']['virtual()']['works with `style="above"`'] = function()
  validate_virtual_lines(true)

  -- Should be the default style
  child.lua('MiniInput.config.handlers.view = MiniInput.gen_view.virtual()')
  set_cursor(2, 0)
  get()
  validate_single_extmark({ 2, 0 }, { virt_lines_above = true })
  type_keys('<C-c>')
end

T['gen_view']['virtual()']['works with `style="below"`'] = function() validate_virtual_lines(false) end

T['gen_view']['virtual()']['works when at the edge of the window'] = function()
  child.cmd('only | mode')
  child.set_size(5, 20)
  set_lines({ 'aaa', 'bbb', 'ccc', 'ddd', 'eee', 'ggg', 'hhh' })
  local n_lines = child.api.nvim_buf_line_count(0)

  local validate = function(style, pos)
    child.lua('_G.style = ' .. vim.inspect(style))
    child.lua('MiniInput.config.handlers.view = MiniInput.gen_view.virtual({ style = _G.style })')
    set_cursor(unpack(pos))
    child.cmd('normal! ' .. (style == 'above' and 'zt' or 'zb'))

    get({ prompt = style })
    child.expect_screenshot()
    validate_single_extmark(pos, { virt_lines_above = style == 'above' })

    type_keys('abc')
    child.expect_screenshot()
    validate_single_extmark(pos, { virt_lines_above = style == 'above' })

    -- Should expectedly restore view
    type_keys('<C-c>')
    child.expect_screenshot()
    eq(get_cursor(), pos)
  end

  validate('above', { 1, 0 })
  validate('above', { 2, 0 })
  validate('below', { n_lines, 0 })
  validate('below', { n_lines - 1, 0 })

  -- With 'winbar' enabled
  child.o.winbar = 'My winbar'
  validate('above', { 1, 0 })
  validate('below', { n_lines, 0 })
end

T['gen_view']['virtual()']['works with `style="inline"`'] = function()
  if child.fn.has('nvim-0.10') == 0 then MiniTest.skip('Inline virtual text is supported on Neovim>=0.10') end

  local ref_details_1 = { priority = 4096, virt_text_pos = 'inline' }
  local ref_chunks_1 = with_prompt_chunks({ caret_ch }, 'AAA')
  ref_details_1.virt_text = ref_chunks_1

  local ref_details_2 = vim.deepcopy(ref_details_1)
  local ref_chunks_2 = with_prompt_chunks(
    { { 'abc', 'MiniInputNormal' }, { 'uu', 'MiniInputAdded' }, caret_ch, { '(1/2)', 'MiniInputHint' } },
    'AAA'
  )
  ref_details_2.virt_text = ref_chunks_2
  validate_virtual('inline', ref_details_1, ref_details_2)
end

T['gen_view']['virtual()']['is not affected by default complete with `style="inline"`'] = function()
  if child.fn.has('nvim-0.10') == 0 then MiniTest.skip('Inline virtual text is supported on Neovim>=0.10') end

  child.lua([[
    MiniInput.config.handlers.view = MiniInput.gen_view.virtual({ style = "inline" })
    MiniInput.config.handlers.complete = MiniInput.default_complete
  ]])
  local lines = { 'aaa', 'bbb', 'ccc' }
  local cursor = { 2, 2 }
  set_lines(lines)
  set_cursor(unpack(cursor))

  get({ prompt = 'AAA' })
  type_keys('a', '<Tab>')
  child.expect_screenshot()
  eq(get_lines(), lines)
  eq(get_cursor(), cursor)
  local ref_chunks = with_prompt_chunks(
    { { 'a', 'MiniInputNormal' }, { 'aa', 'MiniInputAdded' }, caret_ch, { '(1/1)', 'MiniInputHint' } },
    'AAA'
  )
  validate_single_extmark(cursor, { virt_text_pos = 'inline', virt_text = ref_chunks })
end

T['gen_view']['virtual()']['works if all extmarks were cleared'] = function()
  child.cmd('only | mode')
  child.set_size(10, 20)

  local validate = function(style)
    child.lua('_G.style = ' .. vim.inspect(style))
    child.lua('MiniInput.config.handlers.view = MiniInput.gen_view.virtual({ style = _G.style })')

    get({ prompt = 'AAA', init_keys = { 'abc' } })
    validate_single_extmark({ 2, 2 }, {})

    child.api.nvim_buf_clear_namespace(0, -1, 0, -1)
    type_keys('d')
    validate_single_extmark({ 2, 2 }, {})
    child.expect_screenshot()

    type_keys('<C-c>')
    eq(child.api.nvim_buf_get_extmarks(0, -1, 0, -1, {}), {})
  end

  validate('above')
  validate('below')
  if child.fn.has('nvim-0.10') == 1 then validate('inline') end
end

T['gen_view']['virtual()']['respects `opts.to_chunks`'] = function()
  child.lua([[
    _G.to_chunks_log = {}
    _G.to_chunks = function(state, max_width)
      table.insert(_G.to_chunks_log, { state.input, max_width })
      return _G.chunks
    end
  ]])

  local validate = function(style, chunks, ref_log)
    child.lua('_G.style = ' .. vim.inspect(style))
    child.lua('_G.chunks = ' .. vim.inspect(chunks))
    child.lua([[
      local opts = { style = _G.style, to_chunks = _G.to_chunks }
      MiniInput.config.handlers.view = MiniInput.gen_view.virtual(opts)
    ]])

    get({ prompt = 'A' })
    child.expect_screenshot()
    type_keys('a')
    type_keys('<C-c>')

    validate_log('to_chunks_log', ref_log)

    -- Should not modify in place the output of `to_chunks`
    eq(child.lua_get('_G.chunks'), chunks)
  end

  set_lines({ 'aaa', 'bbb', 'ccc' })
  set_cursor(2, 2)

  child.wo.number = true
  child.wo.signcolumn = 'yes'

  -- Should correctly compute maximum width as window width minus gutter
  local ref_log = { { '', 19 }, { 'a', 19 } }
  local ref_chunks = { { 'abcdef', 'Test' } }
  local wide_chunks = { { 'very-very-very-very wide chunk', 'Test' } }

  validate('above', ref_chunks, ref_log)
  -- - Should not wrap text virtual lines
  validate('above', wide_chunks, ref_log)
  validate('below', ref_chunks, ref_log)
  validate('below', wide_chunks, ref_log)

  if child.fn.has('nvim-0.10') == 1 then
    validate('inline', ref_chunks, ref_log)
    -- - Wrapping of virtual text depends on 'wrap'
    child.o.wrap = true
    validate('inline', wide_chunks, ref_log)
    child.o.wrap = false
    validate('inline', wide_chunks, ref_log)
  end

  -- Should validate `to_chunks` output
  local validate_error = function(chunks, err_pattern)
    child.lua('_G.chunks = ' .. vim.inspect(chunks))
    expect.error(function() child.lua('MiniInput.get()') end, err_pattern)
  end
  validate_error(1, '`opts%.to_chunks%(state, 19%)`.*array')
  validate_error({ 1 }, 'Every `opts%.to_chunks%(state, 19%)` item.*table')
  validate_error({ { 1, 'Test' } }, '`opts%.to_chunks%(state, 19%)%[1%]%[1%]`.*string')
  validate_error({ { 'a', 1 } }, '`opts%.to_chunks%(state, 19%)%[1%]%[2%]`.*string')
end

T['gen_view']['virtual()']['can change style'] = function()
  if child.fn.has('nvim-0.10') == 0 then MiniTest.skip('Inline virtual text is supported on Neovim>=0.10') end

  child.cmd('only | mode')
  child.set_size(10, 20)

  get()
  child.expect_screenshot({ ignore_cmdline = true })

  -- Should change style in specific order
  local validate = function()
    type_keys('<C-s>')
    child.expect_screenshot({ ignore_cmdline = true })
  end
  validate()
  validate()
  validate()
end

T['gen_view']['virtual()']['reacts to `state.opts` change'] = function()
  local expect_screenshot = function() child.expect_screenshot({ ignore_cmdline = true }) end

  child.cmd('only | mode')
  child.set_size(10, 20)

  get({ scope = 'cursor' })
  type_keys('abc')
  expect_screenshot()

  -- No reaction to scope change
  type_keys('<C-o>')
  expect_screenshot()

  -- Hide
  child.lua('vim.notify = function() end')
  type_keys('<C-x>')
  expect_screenshot()
  local hidden_chunks = {
    { 'Input', 'MiniInputHide' },
    { ' ', 'MiniInputNormal' },
    { '•••', 'MiniInputNormal' },
    caret_ch,
    { '          ', 'MiniInputNormal' },
  }
  validate_single_extmark({ 2, 2 }, { virt_lines = { hidden_chunks } })
  type_keys('<C-x>')
  expect_screenshot()
end

T['gen_view']['virtual()']['works with floating current window'] = function()
  child.set_size(10, 20)
  child.cmd('only | mode')
  local buf_id = child.api.nvim_create_buf(false, true)
  local config = { relative = 'editor', row = 2, col = 2, height = 2, width = 10, style = 'minimal', border = 'single' }
  child.api.nvim_open_win(buf_id, true, config)
  set_lines({ 'ddd', 'eee', 'fff' })

  local validate = function(style, pos)
    child.lua('_G.style = ' .. vim.inspect(style))
    child.lua('MiniInput.config.handlers.view = MiniInput.gen_view.virtual({ style = _G.style })')

    set_cursor(unpack(pos))

    get({ prompt = 'Prompt' })
    -- - Should correctly compute available width for truncattion
    type_keys('very-very-very wide', string.rep('<Left>', 10))
    child.expect_screenshot()
    type_keys('<CR>')
    child.expect_screenshot()
  end

  validate('above', { 2, 2 })
  validate('below', { 3, 2 })
  if child.fn.has('nvim-0.10') == 1 then validate('inline', { 2, 2 }) end
end

T['gen_view']['virtual()']['validates input'] = function()
  local validate = function(bad_opts, err_pattern)
    expect.error(function() child.lua('MiniInput.gen_view.virtual(...)', { bad_opts }) end, err_pattern)
  end
  validate({ style = 1 }, '`opts.style`.*one of')
  validate({ to_chunks = 1 }, '`opts.to_chunks`.*callable')
end

T['default_key()'] = new_set()

local validate_key = function(state, key, ref_state_change)
  -- Treat `key` as not escaped for easier to read test code
  if key ~= nil then key = child.api.nvim_replace_termcodes(key, true, true, true) end
  validate_default_handler('key', state, key, ref_state_change)
end

T['default_key()']['works'] = function()
  -- Should insert at caret any non-special key
  validate_key({ input = 'ab', caret = 3 }, 'c', { input = 'abc', caret = 4 })
  validate_key({ input = 'ab', caret = 2 }, 'c', { input = 'acb', caret = 3 })
  validate_key({ input = 'ab', caret = 1 }, 'c', { input = 'cab', caret = 2 })

  -- Should do nothing if no key or state is ending
  local validate_no_action = function(status, key) validate_key({ input = 'ab', caret = 3, status = status }, key, {}) end
  validate_no_action('start', nil)
  validate_no_action('progress', nil)
  validate_no_action('accept', nil)
  validate_no_action('cancel', nil)

  validate_no_action('accept', 'c')
  validate_no_action('cancel', 'c')
end

T['default_key()']['can accept and cancel'] = function()
  local validate_status_change = function(key, ref_status)
    validate_key({ status = 'start' }, key, { status = ref_status })
    validate_key({ status = 'progress' }, key, { status = ref_status })
    -- When the state is already ending, nothing should be done
    validate_key({ status = 'accept' }, key, {})
    validate_key({ status = 'cancel' }, key, {})
  end

  validate_status_change('<CR>', 'accept')
  validate_status_change('<Esc>', 'cancel')
  validate_status_change('<C-c>', 'cancel')
end

T['default_key()']['can move caret'] = function()
  local validate_move = function(input, caret, key, ref_caret)
    validate_key({ input = input, caret = caret }, key, { caret = ref_caret ~= caret and ref_caret or nil })
  end

  -- Left/right
  validate_move('ab', 3, '<Left>', 2)
  validate_move('ab', 2, '<Left>', 1)
  validate_move('ab', 1, '<Left>', 1)
  validate_move('ab', 3, '<M-h>', 2)
  validate_move('ab', 2, '<M-h>', 1)
  validate_move('ab', 1, '<M-h>', 1)

  validate_move('ab', 3, '<Right>', 3)
  validate_move('ab', 2, '<Right>', 3)
  validate_move('ab', 1, '<Right>', 2)
  validate_move('ab', 3, '<M-l>', 3)
  validate_move('ab', 2, '<M-l>', 3)
  validate_move('ab', 1, '<M-l>', 2)

  -- Left/right by word. Should jump over all consecutive keyword and non
  -- keyword characters.
  child.o.iskeyword = 'a,b'

  validate_move('axabxxab', 1, '<S-Left>', 1)
  validate_move('axabxxab', 2, '<S-Left>', 1)
  validate_move('axabxxab', 3, '<S-Left>', 2)
  validate_move('axabxxab', 4, '<S-Left>', 3)
  validate_move('axabxxab', 5, '<S-Left>', 3)
  validate_move('axabxxab', 6, '<S-Left>', 5)
  validate_move('axabxxab', 7, '<S-Left>', 5)
  validate_move('axabxxab', 8, '<S-Left>', 7)
  validate_move('axabxxab', 9, '<S-Left>', 7)

  validate_move('axabxxab', 1, '<S-Right>', 2)
  validate_move('axabxxab', 2, '<S-Right>', 3)
  validate_move('axabxxab', 3, '<S-Right>', 5)
  validate_move('axabxxab', 4, '<S-Right>', 5)
  validate_move('axabxxab', 5, '<S-Right>', 7)
  validate_move('axabxxab', 6, '<S-Right>', 7)
  if child.fn.has('nvim-0.10') == 1 then
    validate_move('axabxxab', 7, '<S-Right>', 9)
    validate_move('axabxxab', 8, '<S-Right>', 9)
    validate_move('axabxxab', 9, '<S-Right>', 9)
  end

  -- - Can work with multibyte characters
  child.cmd('set iskeyword&')

  validate_move('фя  фtя  ', 2, '<S-Left>', 1)
  validate_move('фя  фtя  ', 3, '<S-Left>', 1)
  validate_move('фя  фtя  ', 5, '<S-Left>', 3)
  validate_move('фя  фtя  ', 6, '<S-Left>', 5)
  validate_move('фя  фtя  ', 7, '<S-Left>', 5)
  validate_move('фя  фtя  ', 8, '<S-Left>', 5)
  validate_move('фя  фtя  ', 10, '<S-Left>', 8)

  validate_move('фя  фtя  ', 1, '<S-Right>', 3)
  validate_move('фя  фtя  ', 2, '<S-Right>', 3)
  validate_move('фя  фtя  ', 3, '<S-Right>', 5)
  validate_move('фя  фtя  ', 4, '<S-Right>', 5)
  validate_move('фя  фtя  ', 5, '<S-Right>', 8)
  validate_move('фя  фtя  ', 6, '<S-Right>', 8)
  validate_move('фя  фtя  ', 7, '<S-Right>', 8)

  -- Home/End
  validate_move('ab', 1, '<Home>', 1)
  validate_move('ab', 2, '<Home>', 1)
  validate_move('ab', 3, '<Home>', 1)
  validate_move('ab', 1, '<C-b>', 1)
  validate_move('ab', 2, '<C-b>', 1)
  validate_move('ab', 3, '<C-b>', 1)

  validate_move('ab', 1, '<End>', 3)
  validate_move('ab', 2, '<End>', 3)
  validate_move('ab', 3, '<End>', 3)
  validate_move('ab', 1, '<C-e>', 3)
  validate_move('ab', 2, '<C-e>', 3)
  validate_move('ab', 3, '<C-e>', 3)
end

T['default_key()']['can delete'] = function()
  local validate_delete = function(input, caret, key, ref_input, ref_caret)
    local ref_changes = {}
    if ref_input ~= input then ref_changes.input = ref_input end
    if ref_caret ~= caret then ref_changes.caret = ref_caret end
    validate_key({ input = input, caret = caret }, key, ref_changes)
  end

  -- <BS> and <C-h>
  validate_delete('ab', 1, '<BS>', 'ab', 1)
  validate_delete('ab', 2, '<BS>', 'b', 1)
  validate_delete('ab', 3, '<BS>', 'a', 2)
  validate_delete('ab', 1, '<C-h>', 'ab', 1)
  validate_delete('ab', 2, '<C-h>', 'b', 1)
  validate_delete('ab', 3, '<C-h>', 'a', 2)

  validate_delete('a', 2, '<BS>', '', 1)
  validate_delete('a', 2, '<C-h>', '', 1)

  -- - Can work with multibyte characters
  validate_delete('ф', 2, '<BS>', '', 1)
  validate_delete('фt', 3, '<BS>', 'ф', 2)
  validate_delete('фtя', 4, '<BS>', 'фt', 3)

  -- <Del>
  validate_delete('ab', 1, '<Del>', 'b', 1)
  validate_delete('ab', 2, '<Del>', 'a', 2)
  validate_delete('ab', 3, '<Del>', 'ab', 3)

  -- - Can work with multibyte characters
  validate_delete('ф', 1, '<Del>', '', 1)
  validate_delete('фt', 2, '<Del>', 'ф', 2)
  validate_delete('фtя', 3, '<Del>', 'фt', 3)

  -- <C-u>
  validate_delete('ab', 1, '<C-u>', 'ab', 1)
  validate_delete('ab', 2, '<C-u>', 'b', 1)
  validate_delete('ab', 3, '<C-u>', '', 1)

  -- - Can work with multibyte characters
  validate_delete('фt', 2, '<C-u>', 't', 1)
  validate_delete('фtя', 3, '<C-u>', 'я', 1)

  -- <C-w>
  child.o.iskeyword = 'a,b'
  validate_delete('axabxxab', 1, '<C-w>', 'axabxxab', 1)
  validate_delete('axabxxab', 2, '<C-w>', 'xabxxab', 1)
  validate_delete('axabxxab', 3, '<C-w>', 'aabxxab', 2)
  validate_delete('axabxxab', 4, '<C-w>', 'axbxxab', 3)
  validate_delete('axabxxab', 5, '<C-w>', 'axxxab', 3)
  validate_delete('axabxxab', 6, '<C-w>', 'axabxab', 5)
  validate_delete('axabxxab', 7, '<C-w>', 'axabab', 5)
  validate_delete('axabxxab', 8, '<C-w>', 'axabxxb', 7)
  validate_delete('axabxxab', 9, '<C-w>', 'axabxx', 7)

  child.cmd('set iskeyword&')
  validate_delete('фя  фtя  ', 2, '<C-w>', 'я  фtя  ', 1)
  validate_delete('фя  фtя  ', 3, '<C-w>', '  фtя  ', 1)
  validate_delete('фя  фtя  ', 5, '<C-w>', 'фяфtя  ', 3)
  validate_delete('фя  фtя  ', 6, '<C-w>', 'фя  tя  ', 5)
  validate_delete('фя  фtя  ', 7, '<C-w>', 'фя  я  ', 5)
  validate_delete('фя  фtя  ', 8, '<C-w>', 'фя    ', 5)
  validate_delete('фя  фtя  ', 10, '<C-w>', 'фя  фtя', 8)
end

local validate_key_with_extra_keys = function(input, caret, keys, ref_state_changes)
  mock_state({ input = input, caret = caret })
  local old_state = get_state('mock_state')

  local first, extra = keys[1], vim.list_slice(keys, 2)
  child.lua('_G.key = vim.api.nvim_replace_termcodes(' .. vim.inspect(first) .. ', true, true, true)')
  child.lua_notify('_G.new_state = MiniInput.default_key(_G.mock_state, _G.key) or _G.mock_state')
  type_keys(unpack(extra))
  local new_state = get_state('new_state')
  eq(compute_changed_values(old_state, new_state), ref_state_changes)

  child.lua('_G.mock_state, _G.new_state = nil, nil')
end

T['default_key()']['supports <C-k>'] = function()
  local validate = validate_key_with_extra_keys
  local vv_digraph = child.fn.digraph_get('vv')

  validate('', 1, { '<C-k>', 'v', 'v' }, { input = vv_digraph, caret = 2 })
  validate('a', 1, { '<C-k>', 'v', 'v' }, { input = vv_digraph .. 'a', caret = 2 })
  validate('a', 2, { '<C-k>', 'v', 'v' }, { input = 'a' .. vv_digraph, caret = 3 })

  validate('', 1, { '<C-k>', 'x', 'x' }, { input = 'x', caret = 2 })

  -- Should stop on cancelling key
  validate('', 1, { '<C-k>', 'x', '<C-c>' }, {})
  validate('', 1, { '<C-k>', '<C-c>' }, {})

  validate('', 1, { '<C-k>', 'x', '<Esc>' }, {})
  validate('', 1, { '<C-k>', '<Esc>' }, {})
end

T['default_key()']['supports <C-r>'] = function()
  local validate = validate_key_with_extra_keys
  child.fn.setreg('c', 'uuu')
  child.fn.setreg('l', 'vvv', 'V')
  child.fn.setreg('b', 'ww\nxx', 'b2')

  -- Regular registers
  validate('', 1, { '<C-r>', 'c' }, { input = 'uuu', caret = 4 })
  validate('a', 1, { '<C-r>', 'c' }, { input = 'uuua', caret = 4 })
  validate('a', 2, { '<C-r>', 'c' }, { input = 'auuu', caret = 5 })

  validate('', 1, { '<C-r>', 'l' }, { input = 'vvv\n', caret = 5 })

  validate('', 1, { '<C-r>', 'b' }, { input = 'ww\nxx', caret = 6 })

  -- Empty register
  validate('', 1, { '<C-r>', 'x' }, {})

  -- Non-existent register
  validate('', 1, { '<C-r>', '<Del>' }, {})

  -- Special registers
  child.o.iskeyword = child.o.iskeyword .. ',-'
  child.api.nvim_buf_set_lines(0, 0, -1, false, { 'aa bb!cc-dd ee', 'tests/screenshots' })
  set_cursor(1, 7)

  validate('', 1, { '<C-r>', '<C-w>' }, { input = 'cc-dd', caret = 6 })
  validate('', 1, { '<C-r>', '<C-a>' }, { input = 'bb!cc-dd', caret = 9 })
  validate('', 1, { '<C-r>', '<C-l>' }, { input = 'aa bb!cc-dd ee', caret = 15 })

  set_cursor(2, 0)
  validate('', 1, { '<C-r>', '<C-f>' }, { input = 'tests/screenshots', caret = 18 })

  -- Should stop on cancelling or bad key
  validate('', 1, { '<C-r>', '<Esc>' }, {})
  validate('', 1, { '<C-r>', '<C-c>' }, {})

  -- Should not be affected by language mappings
  child.o.iminsert = 1
  child.cmd('lmap c 1')
  validate('', 1, { '<C-r>', 'c' }, { input = 'uuu', caret = 4 })
end

T['default_key()']['supports pasting'] = new_set({ parametrize = { { '<C-q>' }, { '<C-v>' } } }, {
  test = function(key)
    local validate = validate_key_with_extra_keys

    -- Regular
    validate('', 1, { key, 'b' }, { input = 'b', caret = 2 })
    validate('a', 1, { key, 'b' }, { input = 'ba', caret = 2 })
    validate('a', 2, { key, 'b' }, { input = 'ab', caret = 3 })

    -- Special keys that are translated
    validate('', 1, { key, ' ' }, { input = '<Space>', caret = 8 })
    validate('', 1, { key, '<BS>' }, { input = '<BS>', caret = 5 })
    validate('', 1, { key, '<Del>' }, { input = '<Del>', caret = 6 })
    validate('', 1, { key, '<C-S-t>' }, { input = '<C-S-T>', caret = 8 })

    -- With digits as in `:h i_ctrl-V_digit`
    local validate_digit = function(keys_typed, ref_input)
      validate('', 1, { key, unpack(keys_typed) }, { input = ref_input, caret = vim.fn.strchars(ref_input) + 1 })

      -- Typing cancelling key early should stop without side effects
      for i = 1, #keys_typed - 1 do
        local sub_keys = vim.list_slice(keys_typed, 1, i)
        validate('', 1, { key, unpack(sub_keys), '<Esc>' }, {})
        validate('', 1, { key, unpack(sub_keys), '<C-c>' }, {})
      end
    end

    local char_255 = child.fn.nr2char(255)
    validate_digit({ '2', '5', '5' }, char_255)
    validate_digit({ 'o', '3', '7', '7' }, char_255)
    validate_digit({ 'O', '3', '7', '7' }, char_255)
    validate_digit({ 'x', 'f', 'f' }, char_255)
    validate_digit({ 'X', 'f', 'f' }, char_255)
    validate_digit({ 'u', '0', '0', 'f', 'f' }, char_255)
    validate_digit({ 'U', '0', '0', '0', '0', '0', '0', 'f', 'f' }, char_255)

    -- Should insert some special keys without translation
    local validate_no_keytrans = function(key_typed)
      local ref_key_typed = child.api.nvim_replace_termcodes(key_typed, true, true, true)
      validate('', 1, { key, key_typed }, { input = ref_key_typed, caret = 2 })
    end

    -- - Generic control keys
    validate_no_keytrans('<C-a>')
    validate_no_keytrans('<C-h>')

    -- - Whitespace control keys
    validate_no_keytrans('<Tab>')
    validate_no_keytrans('<C-i>')
    validate_no_keytrans('<C-l>')

    -- - Accepting keys
    validate_no_keytrans('<C-m>')
    validate_no_keytrans('<CR>')

    -- - Cancelling keys
    validate_no_keytrans('<Esc>')
    validate_no_keytrans('<C-c>')
  end,
})

T['default_key()']['can complete'] = new_set(
  { parametrize = { { '<Tab>' }, { '<S-Tab>' }, { '<Up>' }, { '<Down>' }, { '<C-n>' }, { '<C-p>' } } },
  {
    test = function(key)
      child.lua([[
        MiniInput.config.handlers.complete = function(state, method)
          -- Should preserve changes to `state.data` made by complete handler
          state.data.n = (state.data.n or 0) + 1
          local input, caret = state.input, state.caret
          local base = vim.fn.strcharpart(input, caret-3, 2)
          state.complete = { base = base, items = { 'uuu', 'vvv', 'www' } }
        end
      ]])
      local is_next = key == '<Tab>' or key == '<C-n>' or key == '<Down>'
      local complete_method = (key == '<Tab>' or key == '<S-Tab>') and 'test' or 'history'

      local state = {}
      local validate_step = function(ref_changes)
        validate_key(state, key, ref_changes)
        state = vim.tbl_deep_extend('force', state, ref_changes)
      end

      -- Should initiate complete if not currently active
      state = { input = 'abcd', caret = 5, opts = { completion = 'test' } }
      local ref_changes = {
        input = is_next and 'abuuu' or 'abwww',
        caret = 6,
        complete = { base = 'cd', id = is_next and 1 or 3, items = { 'uuu', 'vvv', 'www' }, method = complete_method },
        data = { n = 1 },
      }
      validate_step(ref_changes)

      -- Should advance in appropriate direction if complete is active and show
      -- new candidate at caret
      validate_step({ complete = { id = 2 }, input = 'abvvv' })

      validate_step({ complete = { id = is_next and 3 or 1 }, input = is_next and 'abwww' or 'abuuu' })

      -- Should "wrap around the edge" and return to the initial state
      validate_step({ complete = { id = 0 }, input = 'abcd', caret = 5 })

      -- Should be able to continue from `id=0`
      validate_step({ complete = { id = is_next and 1 or 3 }, input = is_next and 'abuuu' or 'abwww', caret = 6 })

      -- Should be able to initiate with caret not at the end
      state = { input = 'abcd', caret = 4, opts = { completion = 'test' } }
      ref_changes = {
        input = is_next and 'auuud' or 'awwwd',
        caret = 5,
        complete = { base = 'bc', id = is_next and 1 or 3, items = { 'uuu', 'vvv', 'www' }, method = complete_method },
        data = { n = 1 },
      }
      validate_step(ref_changes)

      -- Any active completion can be canceled with <C-e>
      validate_key(state, '<C-e>', { input = 'abcd', caret = 4, complete = vim.NIL })

      -- Any active completion can be accepted with <C-y>
      validate_key(state, '<C-y>', { complete = vim.NIL })

      -- Any completion key should navigate through candidates no matter how
      -- completion has started
      state = {
        input = 'abxxx',
        caret = 6,
        complete = { base = 'CD', id = 1, items = { 'xxx', 'yyy' }, method = 'other' },
      }
      local ref_changes_next = { input = 'abyyy', complete = { id = 2 } }
      local ref_changes_prev = { input = 'abCD', caret = 5, complete = { id = 0 } }
      validate_key(state, '<Tab>', ref_changes_next)
      validate_key(state, '<C-n>', ref_changes_next)
      validate_key(state, '<Down>', ref_changes_next)
      validate_key(state, '<S-Tab>', ref_changes_prev)
      validate_key(state, '<C-p>', ref_changes_prev)
      validate_key(state, '<Up>', ref_changes_prev)

      -- Works with multibyte characters
      state = { input = 'фячш', caret = 4, opts = { completion = 'test' } }
      ref_changes = {
        input = is_next and 'фuuuш' or 'фwwwш',
        caret = 5,
        complete = { base = 'яч', id = is_next and 1 or 3, items = { 'uuu', 'vvv', 'www' }, method = complete_method },
        data = { n = 1 },
      }
      validate_step(ref_changes)
    end,
  }
)

T['default_key()']['can change input scope'] = function()
  mock_notify()
  local validate = function(scope, ref_scope)
    validate_key({ opts = { scope = scope } }, '<C-o>', { opts = { scope = ref_scope } })
    validate_log('notify_log', { { '(mini.input) Changed scope to ' .. vim.inspect(ref_scope) } })
  end

  validate('editor', 'project')
  validate('project', 'cursor')
  validate('cursor', 'line')
  validate('line', 'buffer')
  validate('buffer', 'window')
  validate('window', 'tabpage')
  validate('tabpage', 'editor')
end

T['default_key()']['can change view style'] = function()
  mock_notify()
  local validate = function(style, ref_style)
    local state = { data = { all_styles = { 'one', 'two' }, style = style } }
    validate_key(state, '<C-s>', { data = { new_style = ref_style } })
    validate_log('notify_log', { { '(mini.input) Changed style to ' .. vim.inspect(ref_style) } })
  end

  validate('one', 'two')
  validate('two', 'one')
end

T['default_key()']['can toggle hidden'] = function()
  mock_notify()
  local validate = function(hide)
    validate_key({ opts = { hide = hide } }, '<C-x>', { opts = { hide = not hide } })
    validate_log('notify_log', { { '(mini.input) Input is ' .. (hide and 'not ' or '') .. 'hidden' } })
  end

  validate(false)
  validate(true)
end

T['default_key()']['works with special keys'] = function()
  -- Should ignore combos, mouse click, mouse scroll wheel
  validate_key({}, '<C-d>', {})
  validate_key({}, '<C-S-d>', {})
  validate_key({}, '<LeftMouse>', {})
  validate_key({}, '<RightMouse>', {})
  validate_key({}, '<ScrollWheelDown>', {})
  validate_key({}, '<ScrollWheelUp>', {})
  validate_key({}, '<ScrollWheelLeft>', {})
  validate_key({}, '<ScrollWheelRight>', {})

  -- Should allow any not mapped whitespace, like <Space>, <C-j>, and <C-l>
  validate_key({}, ' ', { input = ' ', caret = 2 })
  validate_key({}, '<C-j>', { input = '\n', caret = 2 })
  validate_key({}, '<C-l>', { input = '\f', caret = 2 })

  validate_key({ input = 'a', caret = 1 }, ' ', { input = ' a', caret = 2 })
  validate_key({ input = 'a', caret = 1 }, '<C-j>', { input = '\na', caret = 2 })
  validate_key({ input = 'a', caret = 1 }, '<C-l>', { input = '\fa', caret = 2 })

  -- Should allow more than one character
  validate_key({}, 'ab', { input = 'ab', caret = 3 })
  validate_key({}, ' \n\f', { input = ' \n\f', caret = 4 })
  validate_key({}, ' \t', { input = ' \t', caret = 3 })
end

T['default_key()']['respects `opts.autopair`'] = function()
  local validate = function(state, key, ref_state_changes)
    mock_state(state)
    child.lua('_G.key = ' .. vim.inspect(child.api.nvim_replace_termcodes(key, true, true, true)))

    local old_state = get_state('mock_state')
    child.lua('_G.new_state = MiniInput.default_key(_G.mock_state, _G.key, { autopair = true }) or _G.mock_state')
    local new_state = get_state('new_state')
    eq(compute_changed_values(old_state, new_state), ref_state_changes)
  end

  -- Open
  local validate_open = function(key, pair)
    validate({}, key, { input = pair, caret = 2 })
    validate({ input = 'ab', caret = 2 }, key, { input = 'a' .. pair .. 'b', caret = 3 })

    local left, right = pair:sub(1, 1), pair:sub(2, 2)
    validate({ input = pair, caret = 2 }, key, { input = left .. left .. right .. right, caret = 3 })
  end

  validate_open('(', '()')
  validate_open('[', '[]')
  validate_open('{', '{}')

  -- Close
  local validate_close = function(key, pair)
    validate({}, key, { input = key, caret = 2 })
    validate({ input = 'ab', caret = 2 }, key, { input = 'a' .. key .. 'b', caret = 3 })

    validate({ input = key, caret = 1 }, key, { caret = 2 })
    validate({ input = pair, caret = 2 }, key, { caret = 3 })
  end

  validate_close(')', '()')
  validate_close(']', '[]')
  validate_close('}', '{}')

  -- Closeopen
  local validate_closeopen = function(key, pair)
    validate({}, key, { input = pair, caret = 2 })
    validate({ input = 'ab', caret = 2 }, key, { input = 'a' .. pair .. 'b', caret = 3 })

    validate({ input = key, caret = 1 }, key, { caret = 2 })
    validate({ input = pair, caret = 2 }, key, { caret = 3 })
  end

  validate_closeopen('"', '""')
  validate_closeopen("'", "''")
  validate_closeopen('`', '``')

  -- <BS>
  local validate_bs = function(pair)
    validate({ input = pair, caret = 2 }, '<BS>', { input = '', caret = 1 })
    validate({ input = pair, caret = 3 }, '<BS>', { input = pair:sub(1, 1), caret = 2 })
    validate({ input = 'a' .. pair, caret = 3 }, '<BS>', { input = 'a', caret = 2 })
  end

  validate_bs('()')
  validate_bs('[]')
  validate_bs('{}')
  validate_bs('""')
  validate_bs("''")
  validate_bs('``')

  -- Should insert without autopair with <C-v> / <C-q>
  validate_key_with_extra_keys('', 1, { '<C-v>', '(' }, { input = '(', caret = 2 })
  validate_key_with_extra_keys('', 1, { '<C-v>', '[' }, { input = '[', caret = 2 })
  validate_key_with_extra_keys('', 1, { '<C-v>', '{' }, { input = '{', caret = 2 })

  validate_key_with_extra_keys(')', 1, { '<C-v>', ')' }, { input = '))', caret = 2 })
  validate_key_with_extra_keys(']', 1, { '<C-v>', ']' }, { input = ']]', caret = 2 })
  validate_key_with_extra_keys('}', 1, { '<C-v>', '}' }, { input = '}}', caret = 2 })

  validate_key_with_extra_keys('', 1, { '<C-v>', '"' }, { input = '"', caret = 2 })
  validate_key_with_extra_keys('', 1, { '<C-v>', "'" }, { input = "'", caret = 2 })
  validate_key_with_extra_keys('', 1, { '<C-v>', '`' }, { input = '`', caret = 2 })
  validate_key_with_extra_keys('"', 1, { '<C-v>', '"' }, { input = '""', caret = 2 })
  validate_key_with_extra_keys("'", 1, { '<C-v>', "'" }, { input = "''", caret = 2 })
  validate_key_with_extra_keys('`', 1, { '<C-v>', '`' }, { input = '``', caret = 2 })
end

T['default_highlight()'] = new_set()

local validate_highlight = function(state, hl_ranges)
  local highlight
  if hl_ranges ~= nil then
    highlight = vim.tbl_map(function(x) return { from = x[1], to = x[2], hl = 'MiniInputAdded' } end, hl_ranges)
  end
  validate_default_handler('highlight', state, nil, { highlight = highlight })
end

T['default_highlight()']['works'] = function()
  local validate = function(input, base, item, hl_ranges)
    local state = { input = input, complete = { base = base, id = 1, items = { item }, method = 'test' } }
    validate_highlight(state, hl_ranges)
  end

  -- Should highlight unmatched characters during completion
  validate('abx', 'b', 'bx', { { 3, 3 } })
  validate('axb', 'b', 'xb', { { 2, 2 } })

  validate('abxc', 'bc', 'bxc', { { 3, 3 } })
  validate('abxcx', 'bc', 'bxcx', { { 3, 3 }, { 5, 5 } })
  validate('abxxc', 'bc', 'bxxc', { { 3, 4 } })

  validate('axbxcx', 'bc', 'xbxcx', { { 2, 2 }, { 4, 4 }, { 6, 6 } })

  -- Should work with empty base
  validate('abx', '', 'x', { { 3, 3 } })
  validate('x', '', 'x', { { 1, 1 } })

  -- Should work with base containing spaces
  validate('ab  cd', 'ab  ', 'ab  cd', { { 5, 6 } })

  -- Should work when caret is not at the end
  local state = { input = 'ax bb', caret = 3, complete = { base = 'a', id = 1, items = { 'ax' }, method = 'test' } }
  validate_highlight(state, { { 2, 2 } })

  state = { input = 'x bb', caret = 2, complete = { base = '', id = 1, items = { 'x' }, method = 'test' } }
  validate_highlight(state, { { 1, 1 } })

  -- Should work with multibyte characters
  validate('фячш', 'ч', 'чш', { { 4, 4 } })
  validate('фячш', 'ш', 'чш', { { 3, 3 } })

  validate('фячш', 'я', 'ячш', { { 3, 4 } })
  validate('фячш', 'ч', 'ячш', { { 2, 2 }, { 4, 4 } })
  validate('фячш', 'ш', 'ячш', { { 2, 3 } })
  validate('фячш', 'чш', 'ячш', { { 2, 2 } })
  validate('фячш', 'яш', 'ячш', { { 3, 3 } })
  validate('фячш', 'яч', 'ячш', { { 4, 4 } })
end

T['default_highlight()']['does nothing when expected'] = function()
  -- No active completion
  validate_highlight({}, nil)
  validate_highlight({ input = 'ab' }, nil)

  -- Base is shown during active completion, without or with items
  local state = { input = '', complete = { base = '', id = 0, items = {}, method = 'test' } }
  validate_highlight(state, nil)

  state.input, state.complete.base = 'a', 'a'
  validate_highlight(state, nil)

  state.items = { 'ab' }
  validate_highlight(state, nil)

  -- Input is ending
  state.input, state.complete.id = 'ab', 1
  state.status = 'accept'
  validate_highlight(state, nil)
  state.status = 'cancel'
  validate_highlight(state, nil)
end

T['default_highlight()']['works with already present `state.highlight`'] = function()
  local state = { input = 'abx', complete = { base = 'b', id = 1, items = { 'bx' }, method = 'test' } }
  state.highlight = { { from = 1, to = 3, hl = 'AA' } }
  validate_highlight(state, { [2] = { 3, 3 } })
end

T['default_view()'] = new_set()

-- Most test coverage is done in `gen_vew.floatwin`

T['default_view()']['works'] = function()
  local expect_screenshot = function() child.expect_screenshot({ redraw = false, ignore_cmdline = true }) end

  set_lines({ 'aaa', 'bbb', 'ccc' })
  set_cursor(3, 1)
  get({ prompt = 'Hello?', scope = 'cursor' })
  expect_screenshot()

  local state = get_state()
  local buf_id, win_id = state.data.floatwin_buf_id, state.data.floatwin_win_id
  eq(child.api.nvim_buf_is_valid(buf_id), true)
  eq(child.api.nvim_win_is_valid(win_id), true)

  -- Typing anc caret move
  type_keys('a')
  expect_screenshot()
  type_keys('<Left>')
  expect_screenshot()
  eq(child.api.nvim_buf_get_lines(buf_id, 0, -1, false), { '▏a' })

  -- Interactive scope changing
  type_keys('<C-o>')
  expect_screenshot()
  type_keys('<C-o>')
  expect_screenshot()

  -- Interactive style changing
  type_keys('<C-s>')
  expect_screenshot()
  type_keys('<C-s>')
  expect_screenshot()

  -- Finishing
  type_keys('<CR>')
  expect_screenshot()
  eq(child.api.nvim_buf_is_valid(buf_id), false)
  eq(child.api.nvim_win_is_valid(win_id), false)
end

T['default_complete()'] = new_set()

local validate_complete = function(state, method, ref_state_change)
  validate_default_handler('complete', state, method, ref_state_change)
end

T['default_complete()']['method=""'] = new_set()

T['default_complete()']['method=""']['works'] = function()
  set_lines({ 'ab axb abx xab', 'abb' })

  -- Should compute order based on best fuzzy match
  -- but do not include base itself as the item
  local ref_changes = { complete = { base = 'ab', items = { 'abx', 'abb', 'xab', 'axb' } } }
  validate_complete({ input = 'ab' }, '', ref_changes)
  validate_complete({ input = 'prefix ab' }, '', ref_changes)
  validate_complete({ input = 'abc', caret = 3 }, '', ref_changes)

  -- Cursor position should not affect the result
  set_cursor(1, 10)
  validate_complete({ input = 'ab' }, '', ref_changes)
  set_cursor(2, 0)
  validate_complete({ input = 'ab' }, '', ref_changes)

  -- Should set no items for empty base
  local no_items = { complete = { base = '', items = {} } }
  validate_complete({ input = '' }, '', no_items)
  validate_complete({ input = 'prefix ' }, '', no_items)

  -- Uses keyword at caret as the base and keywords as matches
  child.o.iskeyword = 'a,b,x'
  validate_complete({ input = 'cab' }, '', ref_changes)

  child.o.iskeyword = 'a,b'
  -- - No matches containing "x" since it is not a keyword
  validate_complete({ input = 'cab' }, '', { complete = { base = 'ab', items = { 'abb' } } })
  validate_complete({ input = 'ab' }, '', { complete = { base = 'ab', items = { 'abb' } } })

  child.cmd('set iskeyword&')

  -- Should work with multibyte characters
  set_lines({ 'фячш', 'фяш' })
  validate_complete({ input = 'фш' }, '', { complete = { base = 'фш', items = { 'фяш', 'фячш' } } })

  -- Should work with characters special for search
  child.o.iskeyword = 'a,b,*,/'
  set_lines({ 'ab*/' })
  validate_complete({ input = 'ab' }, '', { complete = { base = 'ab', items = { 'ab*/' } } })
  child.cmd('set iskeyword&')

  -- Should work with very long base
  if child.fn.has('nvim-0.12') == 1 then
    local base = string.rep('abcdefghij', 30)
    local lines = { base .. 'x', base .. 'y' }
    set_lines(lines)
    validate_complete({ input = base }, '', { complete = { base = base, items = lines } })
  end
end

T['default_complete()']['method=""']["respects 'ignorecase' and 'smartcase'"] = function()
  set_lines({ 'ab bA' })

  local validate_case = function(ignorecase, smartcase, input, ref_items)
    child.o.ignorecase, child.o.smartcase = ignorecase, smartcase
    validate_complete({ input = input }, '', { complete = { base = input, items = ref_items } })
    child.o.ignorecase, child.o.smartcase = false, false
  end

  validate_case(false, false, 'a', { 'ab' })
  validate_case(false, false, 'A', { 'bA' })

  validate_case(false, true, 'a', { 'ab' })
  validate_case(false, true, 'A', { 'bA' })

  local ref_ignorecase = child.fn.has('nvim-0.12') == 1 and { 'ab', 'bA' } or { 'bA', 'ab' }
  validate_case(true, false, 'a', ref_ignorecase)
  validate_case(true, false, 'A', ref_ignorecase)

  validate_case(true, true, 'a', ref_ignorecase)
  validate_case(true, true, 'A', { 'bA' })
end

T['default_complete()']['method=""']['does not have side effects'] = function()
  set_lines({ 'ab AB', 'abx axb xab' })
  set_cursor(2, 5)
  child.fn.setreg('/', 'prev')
  child.cmd('let v:hlsearch=0')
  child.cmd('messages clear')

  validate_complete({ input = 'ab' }, '', { complete = { base = 'ab', items = { 'abx', 'xab', 'axb' } } })

  eq(child.g._miniinput_matches, vim.NIL)
  eq(get_cursor(), { 2, 5 })
  eq(child.v.hlsearch, 0)
  eq(child.fn.getreg('/'), 'prev')
  eq(child.cmd_capture('messages'), '')
end

T['default_complete()']['works with method="history"'] = function()
  local cwd = child.fn.getcwd()
  local cwd_alt = cwd .. slash .. 'tests'
  set_history({
    { cwd = cwd, prompt = 'A', input = 'ab', scope = 'editor' },
    { cwd = cwd, prompt = 'A', input = 'ac', scope = 'editor' },
    { cwd = cwd, prompt = 'A', input = 'abc', scope = 'editor' },

    -- Only latest duplicating entry should be present
    { cwd = cwd, prompt = 'A', input = 'ab', scope = 'editor' },

    -- Entries should be ordered as in history, not alphabetically
    { cwd = cwd, prompt = 'A', input = 'aa', scope = 'editor' },

    -- By default should only suggest matches from precisely same history
    { cwd = cwd_alt, prompt = 'A', input = 'au', scope = 'editor' },
    { cwd = cwd, prompt = 'XXX', input = 'av', scope = 'editor' },
    { cwd = cwd, prompt = 'A', input = 'aw', scope = 'cursor' },
  })

  local validate = function(state, ref_complete_changes)
    validate_complete(state, 'history', { complete = ref_complete_changes })
  end

  local state = { input = '', opts = { prompt = 'A', scope = 'editor' } }
  validate(state, { base = '', items = { 'ac', 'abc', 'ab', 'aa' } })

  state.input = 'a'
  validate(state, { base = 'a', items = { 'ac', 'abc', 'ab', 'aa' } })

  state.input = 'x'
  validate(state, { base = 'x', items = {} })

  -- Should not show entries that match exactly
  state.input = 'ab'
  validate(state, { base = 'ab', items = { 'abc' } })
  state.input = 'abc'
  validate(state, { base = 'abc', items = {} })

  -- Only prefix matching, no fuzzy matching
  state.input = 'b'
  validate(state, { base = 'b', items = {} })

  -- Should work with caret not at the end
  state.input, state.caret = 'af', 2
  validate(state, { base = 'a', items = { 'ac', 'abc', 'ab', 'aa' } })
  state.caret = 1
  validate(state, { base = '', items = { 'ac', 'abc', 'ab', 'aa' } })
  state.caret = nil

  -- Should do precise matching
  state.input = 'a'

  child.fn.chdir(cwd_alt)
  validate(state, { base = 'a', items = { 'au' } })
  child.fn.chdir(cwd)

  state.opts.prompt = 'XXX'
  validate(state, { base = 'a', items = { 'av' } })
  state.opts.prompt = 'A'

  state.opts.scope = 'cursor'
  validate(state, { base = 'a', items = { 'aw' } })
  state.opts.scope = 'editor'
end

T['default_complete()']['respects `opts.precise_history`'] = function()
  local cwd = child.fn.getcwd()
  set_history({
    { cwd = cwd, prompt = 'A', input = 'ab', scope = 'editor' },
    { cwd = cwd .. '/tests', prompt = 'A', input = 'au', scope = 'editor' },
    { cwd = cwd, prompt = 'XXX', input = 'av', scope = 'editor' },
    { cwd = cwd, prompt = 'A', input = 'aw', scope = 'cursor' },
  })

  local state = { input = '', opts = { prompt = 'A', scope = 'editor' } }
  local validate = function(precise_history, ref_items)
    mock_state(state)
    child.lua('_G.precise_history = ' .. vim.inspect(precise_history))

    child.lua([[
      local opts = { precise_history = _G.precise_history }
      local state = vim.deepcopy(_G.mock_state)
      _G.new_state = MiniInput.default_complete(state, 'history', opts) or state
    ]])
    local old_state = get_state('mock_state')
    local new_state = get_state('new_state')
    local ref_changes = { complete = { base = '', items = ref_items } }
    eq(compute_changed_values(old_state, new_state), ref_changes)
  end

  validate(true, { 'ab' })
  validate(false, { 'ab', 'au', 'av', 'aw' })

  state.opts.prompt = 'XXX'
  validate(true, { 'av' })
  validate(false, { 'ab', 'au', 'av', 'aw' })

  state.opts.scope = 'cursor'
  validate(true, {})
  validate(false, { 'ab', 'au', 'av', 'aw' })
end

T['default_complete()']['works with method="cmdline"'] = function()
  child.lua('_G.n_modechanged = 0')
  child.cmd('au ModeChanged *:* lua _G.n_modechanged = _G.n_modechanged + 1')
  child.o.wildoptions = 'pum'

  local validate = function(input, caret, ref_base, ref_items)
    ref_items = ref_items or child.fn.getcompletion(input, 'cmdline')
    local ref_changes = { complete = { base = ref_base, items = ref_items } }
    validate_complete({ input = input, caret = caret }, 'cmdline', ref_changes)
  end

  validate('se', nil, 'se', { 'set', 'setfiletype', 'setglobal', 'setlocal' })

  child.cmd('command MyCommand echo "Hello"')
  validate('MyC', nil, 'MyC', { 'MyCommand' })

  validate('set hlse', nil, 'hlse', { 'hlsearch' })
  validate('set ', nil, '', nil)

  validate('lua stri', nil, 'stri', { 'string' })
  validate('lua string.f', nil, 'f', { 'find', 'format' })

  -- Should work with caret not at end
  validate('MyCx', 4, 'MyC', { 'MyCommand' })
  validate('lua string.f', 9, 'stri', { 'string' })

  -- Should work with fuzzy matching
  child.o.wildoptions = 'pum,fuzzy'
  child.g.fuzzy_match_test_axbxcxdxe = 1
  validate('let g:abcde', nil, 'g:abcde', { 'g:fuzzy_match_test_axbxcxdxe' })
  child.o.wildoptions = 'pum'

  -- Should correctly compute base in problmatic cases, with and without fuzzy
  validate('set no', nil, '', nil)
  validate('set inv', nil, '', nil)

  child.g.test_input_var = 1
  validate('let g', nil, '', {})
  validate('let g:', nil, 'g:', nil)
  validate('let g:test_inpu', nil, 'g:test_inpu', { 'g:test_input_var' })

  child.fn.chdir('tests')
  validate('edit dir-inp', nil, 'dir-inp', { 'dir-input' .. slash })
  validate('edit dir-input' .. slash .. 'f', nil, 'dir-input' .. slash .. 'f', { 'dir-input' .. slash .. 'file' })

  child.o.wildoptions = 'pum,fuzzy'
  validate('set no', nil, '', nil)
  validate('set inv', nil, '', nil)
  validate('let g', nil, 'g', nil)

  -- Should never change mode
  eq(child.lua_get('_G.n_modechanged'), 0)
end

T['default_complete()']['works with method="custom[list],v:lua.fun"'] = function()
  child.lua([[
    _G.complete_log = {}
    _G.custom_complete = function(...)
      table.insert(_G.complete_log, { 'custom', ... })
      return 'auu\navv'
    end
    _G.customlist_complete = function(...)
      table.insert(_G.complete_log, { 'customlist', ... })
      return { 'auu', 'avv' }
    end
  ]])

  local ref_changes = { complete = { base = 'a', items = { 'auu', 'avv' } } }
  validate_complete({ input = ' a' }, 'custom,v:lua.custom_complete', ref_changes)
  validate_complete({ input = ' a' }, 'customlist,v:lua.customlist_complete', ref_changes)
  validate_log('complete_log', { { 'custom', 'a', 'a', 0 }, { 'customlist', 'a', 'a', 0 } })
end

T['default_complete()']['works with file system methods'] = function()
  child.fn.chdir('tests')

  local sl = slash
  local file_items = { 'dir-input' .. sl .. 'file', 'dir-input' .. sl .. 'subdir' .. sl }
  local ref_files = { base = 'dir-input' .. sl, items = file_items }
  validate_complete({ input = 'dir-input' .. sl }, 'file', { complete = ref_files })
  validate_complete({ input = 'dir-input' .. sl }, 'file_in_path', { complete = ref_files })

  if child.fn.has('nvim-0.11') == 1 then
    local ref_dirs = { base = 'dir-input' .. sl, items = { 'dir-input' .. sl .. 'subdir' .. sl } }
    validate_complete({ input = 'dir-input' .. sl }, 'dir', { complete = ref_dirs })
    validate_complete({ input = 'dir-input' .. sl }, 'dir_in_path', { complete = ref_dirs })
  end
end

T['default_complete()']['works with built-in methods'] = function()
  child.lua('_G.n_modechanged = 0')
  child.cmd('au ModeChanged *:* lua _G.n_modechanged = _G.n_modechanged + 1')

  -- Should forward to |getcompletion()| for computing items
  local validate = function(input, caret, method, ref_base)
    local ref_items = child.fn.getcompletion(ref_base, method)
    validate_complete({ input = input, caret = caret }, method, { complete = { base = ref_base, items = ref_items } })
  end

  validate('', nil, 'color', '')

  validate('miniw', nil, 'color', 'miniw')
  validate('getcomple', nil, 'help', 'getcomple')
  validate('hls', nil, 'option', 'hls')

  validate('color miniw', nil, 'color', 'miniw')

  -- Should work with caret not at end
  validate('hel', 3, 'help', 'he')

  -- Should use keyword as base
  child.o.iskeyword = 'a,b'
  validate('tab', nil, 'help', 'ab')

  -- Should never change mode
  eq(child.lua_get('_G.n_modechanged'), 0)
end

T['default_complete()']['respects `state.opts.completion`'] = function()
  local ref_changes = { complete = { base = 'tab', items = child.fn.getcompletion('tab', 'help') } }
  validate_complete({ input = 'tab', opts = { completion = 'help' } }, nil, ref_changes)
end

T['default_complete()']['does nothing when expected'] = function()
  set_history({ { cwd = child.fn.getcwd(), prompt = 'A', input = 'ab', scope = 'editor' } })

  -- Input is ending
  local state = { input = '', opts = { prompt = 'A', scope = 'editor' } }

  state.status = 'accept'
  validate_complete(state, 'history', {})
  state.status = 'cancel'
  validate_complete(state, 'history', {})

  -- Not supported method
  validate_complete(state, 'not-supported', {})
end

T['state_to_chunks()'] = new_set()

local state_to_chunks = function(state, max_width, opts)
  mock_state(state)
  child.lua('_G.max_width = ' .. vim.inspect(max_width))
  child.lua('_G.opts = ' .. vim.inspect(opts))
  return child.lua_get('MiniInput.state_to_chunks(_G.mock_state, _G.max_width, _G.opts)')
end

T['state_to_chunks()']['works'] = function()
  local validate = function(input, caret, ref)
    eq(state_to_chunks({ input = input, caret = caret }), with_prompt_chunks(ref))
  end

  validate('', 1, { caret_ch })
  validate('a', 2, { { 'a', 'MiniInputNormal' }, caret_ch })
  validate('a', 1, { caret_ch, { 'a', 'MiniInputNormal' } })
  validate('ab', 3, { { 'ab', 'MiniInputNormal' }, caret_ch })
  validate('ab', 2, { { 'a', 'MiniInputNormal' }, caret_ch, { 'b', 'MiniInputNormal' } })
  validate('ab', 1, { caret_ch, { 'ab', 'MiniInputNormal' } })

  -- Multibyte characters
  validate('ф🬗', 3, { { 'ф🬗', 'MiniInputNormal' }, caret_ch })
  validate('ф🬗', 2, { { 'ф', 'MiniInputNormal' }, caret_ch, { '🬗', 'MiniInputNormal' } })
  validate('ф🬗', 1, { caret_ch, { 'ф🬗', 'MiniInputNormal' } })

  -- Double-width characters
  validate('「」', 3, { { '「」', 'MiniInputNormal' }, caret_ch })
  validate('「」', 2, { { '「', 'MiniInputNormal' }, caret_ch, { '」', 'MiniInputNormal' } })
  validate('「」', 1, { caret_ch, { '「」', 'MiniInputNormal' } })

  -- Should not include empty prompt
  eq(state_to_chunks({ input = '', caret = 1, opts = { prompt = '' } }), { caret_ch })
end

T['state_to_chunks()']['works with hidden input'] = function()
  local validate = function(input, caret, ref)
    eq(state_to_chunks({ input = input, caret = caret, opts = { hide = true } }), ref)
  end

  validate('', 1, { { 'Input', 'MiniInputHide' }, { ' ', 'MiniInputNormal' }, caret_ch })
  validate('a', 2, { { 'Input', 'MiniInputHide' }, { ' ', 'MiniInputNormal' }, { '•', 'MiniInputNormal' }, caret_ch })
  validate('a', 1, { { 'Input', 'MiniInputHide' }, { ' ', 'MiniInputNormal' }, caret_ch, { '•', 'MiniInputNormal' } })
end

T['state_to_chunks()']['works with `state.highlight`'] = function()
  local validate = function(ranges, caret, ref)
    local highlight = vim.tbl_map(function(x) return { from = x[1], to = x[2], hl = x[3] } end, ranges)
    eq(state_to_chunks({ input = 'abcdefghij', caret = caret, highlight = highlight }), with_prompt_chunks(ref))
  end

  local ref = { { 'a', 'AA' }, { 'bcdefghij', 'MiniInputNormal' }, caret_ch }
  validate({ { 1, 1, 'AA' } }, nil, ref)

  ref = { { 'a', 'AA' }, { 'bc', 'BB' }, { 'de', 'CC' }, { 'fghij', 'MiniInputNormal' }, caret_ch }
  validate({ { 1, 1, 'AA' }, { 2, 3, 'BB' }, { 4, 5, 'CC' } }, nil, ref)
  validate({ { 2, 3, 'BB' }, { 4, 5, 'CC' }, { 1, 1, 'AA' } }, nil, ref)
  validate({ { 4, 5, 'CC' }, { 2, 3, 'BB' }, { 1, 1, 'AA' } }, nil, ref)

  -- Should work with inside caret
  validate({ { 1, 1, 'AA' } }, 1, { caret_ch, { 'a', 'AA' }, { 'bcdefghij', 'MiniInputNormal' } })
  validate({ { 1, 2, 'AA' } }, 1, { caret_ch, { 'ab', 'AA' }, { 'cdefghij', 'MiniInputNormal' } })

  ref = { { 'a', 'AA' }, caret_ch, { 'b', 'AA' }, { 'cdefghij', 'MiniInputNormal' } }
  validate({ { 1, 2, 'AA' } }, 2, ref)
  ref = { { 'ab', 'AA' }, caret_ch, { 'cdefghij', 'MiniInputNormal' } }
  validate({ { 1, 2, 'AA' } }, 3, ref)

  ref = { { 'ab', 'AA' }, caret_ch, { 'cd', 'BB' }, { 'efghij', 'MiniInputNormal' } }
  validate({ { 1, 2, 'AA' }, { 3, 4, 'BB' } }, 3, ref)
  ref = { { 'ab', 'AA' }, { 'c', 'BB' }, caret_ch, { 'd', 'BB' }, { 'efghij', 'MiniInputNormal' } }
  validate({ { 1, 2, 'AA' }, { 3, 4, 'BB' } }, 4, ref)
  ref = { { 'ab', 'AA' }, { 'cd', 'BB' }, caret_ch, { 'efghij', 'MiniInputNormal' } }
  validate({ { 1, 2, 'AA' }, { 3, 4, 'BB' } }, 5, ref)

  -- Gaps from not full coverage should be filled with 'MiniInputNormal'
  --stylua: ignore
  ref = {
    { 'a', 'MiniInputNormal' }, { 'bc', 'AA' }, { 'de', 'MiniInputNormal' }, { 'f', 'BB' },
    { 'ghij', 'MiniInputNormal' },
    caret_ch,
  }
  validate({ { 2, 3, 'AA' }, { 6, 6, 'BB' } }, nil, ref)

  -- Should allow `to = math.huge`
  mock_state({ input = 'abc', caret = 4 })
  -- NOTE: Set `math.huge` explicitly as `vim.inpsect()` translates it into `info`
  child.lua('_G.mock_state.highlight = { { from = 2, to = math.huge, hl = "AA" } }')
  ref = with_prompt_chunks({ { 'a', 'MiniInputNormal' }, { 'bc', 'AA' }, caret_ch })
  eq(child.lua_get('MiniInput.state_to_chunks(_G.mock_state)'), ref)
end

T['state_to_chunks()']['handles highlight overlap'] = function()
  -- All combinations of overlapping ranges should work
  -- Later chunks should be applied "on top" on the normalized previous ones
  local validate_overlap = function(ranges, ref_ranges)
    local input = 'abcdefghij'
    local ref_chunks, max_to = {}, 0
    for i, r in ipairs(ref_ranges) do
      ref_chunks[i] = { input:sub(r[1], r[2]), r[3] }
      max_to = math.max(max_to, r[2])
    end
    local rest = string.sub(input, max_to + 1)
    if rest ~= '' then table.insert(ref_chunks, { rest, 'MiniInputNormal' }) end
    vim.list_extend(ref_chunks, { caret_ch })
    ref_chunks = with_prompt_chunks(ref_chunks)

    local highlight = vim.tbl_map(function(x) return { from = x[1], to = x[2], hl = x[3] } end, ranges)
    eq(state_to_chunks({ input = input, caret = 11, highlight = highlight }), ref_chunks)
  end

  -- - Intersect
  validate_overlap(
    { { 1, 4, 'AA' }, { 3, 6, 'BB' }, { 5, 7, 'CC' } },
    { { 1, 2, 'AA' }, { 3, 4, 'BB' }, { 5, 7, 'CC' } }
  )
  validate_overlap(
    { { 1, 2, 'AA' }, { 2, 3, 'BB' }, { 3, 4, 'CC' } },
    { { 1, 1, 'AA' }, { 2, 2, 'BB' }, { 3, 4, 'CC' } }
  )

  -- - Split
  validate_overlap({ { 1, 4, 'AA' }, { 2, 3, 'BB' } }, { { 1, 1, 'AA' }, { 2, 3, 'BB' }, { 4, 4, 'AA' } })
  validate_overlap({ { 1, 4, 'AA' }, { 1, 3, 'BB' } }, { { 1, 3, 'BB' }, { 4, 4, 'AA' } })
  validate_overlap({ { 1, 4, 'AA' }, { 2, 4, 'BB' } }, { { 1, 1, 'AA' }, { 2, 4, 'BB' } })
  validate_overlap({ { 1, 4, 'AA' }, { 1, 4, 'BB' } }, { { 1, 4, 'BB' } })

  validate_overlap({ { 1, 3, 'AA' }, { 2, 2, 'BB' } }, { { 1, 1, 'AA' }, { 2, 2, 'BB' }, { 3, 3, 'AA' } })
  validate_overlap({ { 1, 3, 'AA' }, { 1, 1, 'BB' } }, { { 1, 1, 'BB' }, { 2, 3, 'AA' } })
  validate_overlap({ { 1, 3, 'AA' }, { 3, 3, 'BB' } }, { { 1, 2, 'AA' }, { 3, 3, 'BB' } })
  validate_overlap({ { 1, 1, 'AA' }, { 1, 1, 'BB' } }, { { 1, 1, 'BB' } })

  -- - Cover
  validate_overlap({ { 2, 3, 'AA' }, { 1, 4, 'BB' } }, { { 1, 4, 'BB' } })

  -- - Mix
  validate_overlap(
    { { 1, 2, 'AA' }, { 1, 3, 'BB' }, { 2, 4, 'CC' }, { 3, 5, 'DD' }, { 5, 5, 'EE' } },
    { { 1, 1, 'BB' }, { 2, 2, 'CC' }, { 3, 4, 'DD' }, { 5, 5, 'EE' } }
  )
  validate_overlap(
    { { 1, 6, 'AA' }, { 3, 8, 'BB' }, { 5, 9, 'CC' } },
    { { 1, 2, 'AA' }, { 3, 4, 'BB' }, { 5, 9, 'CC' } }
  )
end

T['state_to_chunks()']['works with `state.highlight` and multibyte input'] = function()
  local validate_one = function(input, ranges, caret, ref)
    local highlight = vim.tbl_map(function(x) return { from = x[1], to = x[2], hl = x[3] } end, ranges)
    eq(state_to_chunks({ input = input, caret = caret, highlight = highlight }), with_prompt_chunks(ref))
  end

  local validate = function(char_1, char_2)
    local input = char_1 .. char_2
    validate_one(input, { { 1, 2, 'AA' } }, 3, { { input, 'AA' }, caret_ch })
    validate_one(input, { { 1, 2, 'AA' } }, 2, { { char_1, 'AA' }, caret_ch, { char_2, 'AA' } })
    validate_one(input, { { 1, 2, 'AA' } }, 1, { caret_ch, { input, 'AA' } })

    validate_one(input, { { 1, 1, 'AA' }, { 2, 2, 'BB' } }, 3, { { char_1, 'AA' }, { char_2, 'BB' }, caret_ch })
    validate_one(input, { { 1, 1, 'AA' }, { 2, 2, 'BB' } }, 2, { { char_1, 'AA' }, caret_ch, { char_2, 'BB' } })
    validate_one(input, { { 1, 1, 'AA' }, { 2, 2, 'BB' } }, 1, { caret_ch, { char_1, 'AA' }, { char_2, 'BB' } })

    validate_one(input, { { 1, 1, 'AA' } }, 3, { { char_1, 'AA' }, { char_2, 'MiniInputNormal' }, caret_ch })
    validate_one(input, { { 2, 2, 'AA' } }, 3, { { char_1, 'MiniInputNormal' }, { char_2, 'AA' }, caret_ch })
    validate_one(input, { { 2, 2, 'AA' } }, 2, { { char_1, 'MiniInputNormal' }, caret_ch, { char_2, 'AA' } })
    validate_one(input, { { 2, 2, 'AA' } }, 1, { caret_ch, { char_1, 'MiniInputNormal' }, { char_2, 'AA' } })
  end

  -- Multibyte characters
  validate('ф', '🬗')

  -- Double-width characters
  validate('「', '」')
end

T['state_to_chunks()']['normalizes highlight ranges'] = function()
  local validate = function(ranges, ref)
    local highlight = vim.tbl_map(function(x) return { from = x[1], to = x[2], hl = x[3] } end, ranges)
    ref = with_prompt_chunks(ref)
    table.insert(ref, caret_ch)
    eq(state_to_chunks({ input = 'abcd', caret = 5, highlight = highlight }), ref)
  end

  -- Ranges completely outside should be ignored
  validate({ { -2, 0, 'UU' }, { 1, 2, 'AA' }, { 5, 10, 'VV' } }, { { 'ab', 'AA' }, { 'cd', 'MiniInputNormal' } })

  -- Ranges partially outside should be clamped to edges
  validate({ { -2, 1, 'AA' }, { 4, 10, 'BB' } }, { { 'a', 'AA' }, { 'bc', 'MiniInputNormal' }, { 'd', 'BB' } })
  validate({ { -2, 2, 'AA' }, { 3, 10, 'BB' } }, { { 'ab', 'AA' }, { 'cd', 'BB' } })
end

T['state_to_chunks()']['works with `state.complete`'] = function()
  local validate = function(id, caret, ref)
    local complete = { base = 'cd', items = { 'cdu', 'cdv' }, id = id, method = '' }
    eq(state_to_chunks({ input = 'abcd', caret = caret, complete = complete }), with_prompt_chunks(ref))
  end

  validate(0, 5, { { 'abcd', 'MiniInputNormal' }, caret_ch, { '(0/2)', 'MiniInputHint' } })
  validate(1, 5, { { 'abcd', 'MiniInputNormal' }, caret_ch, { '(1/2)', 'MiniInputHint' } })
  validate(2, 5, { { 'abcd', 'MiniInputNormal' }, caret_ch, { '(2/2)', 'MiniInputHint' } })

  validate(0, 4, { { 'abc', 'MiniInputNormal' }, caret_ch, { '(0/2)', 'MiniInputHint' }, { 'd', 'MiniInputNormal' } })
  validate(1, 4, { { 'abc', 'MiniInputNormal' }, caret_ch, { '(1/2)', 'MiniInputHint' }, { 'd', 'MiniInputNormal' } })
  validate(0, 1, { caret_ch, { '(0/2)', 'MiniInputHint' }, { 'abcd', 'MiniInputNormal' } })
  validate(1, 1, { caret_ch, { '(1/2)', 'MiniInputHint' }, { 'abcd', 'MiniInputNormal' } })

  -- Method should not matter
  local complete = { base = 'cd', items = { 'cdu', 'cdv' }, id = 0, method = 'custom' }
  local ref = { { 'abcd', 'MiniInputNormal' }, caret_ch, { '(0/2)', 'MiniInputHint' } }
  eq(state_to_chunks({ input = 'abcd', complete = complete }), with_prompt_chunks(ref))
end

T['state_to_chunks()']['works with `state.highlight` and `state.complete`'] = function()
  local validate = function(ranges, caret, ref)
    local complete = { base = 'cd', items = { 'cdu', 'cdv' }, id = 1, method = '' }
    local highlight = vim.tbl_map(function(x) return { from = x[1], to = x[2], hl = x[3] } end, ranges)

    local state = { input = 'abcdu', caret = caret, complete = complete, highlight = highlight }
    eq(state_to_chunks(state), with_prompt_chunks(ref))
  end

  validate({ { 1, 5, 'AA' } }, 6, { { 'abcdu', 'AA' }, caret_ch, { '(1/2)', 'MiniInputHint' } })
  validate({ { 1, 5, 'AA' } }, 5, { { 'abcd', 'AA' }, caret_ch, { '(1/2)', 'MiniInputHint' }, { 'u', 'AA' } })
  validate({ { 1, 5, 'AA' } }, 1, { caret_ch, { '(1/2)', 'MiniInputHint' }, { 'abcdu', 'AA' } })

  local ref = { { 'abcd', 'MiniInputNormal' }, { 'u', 'AA' }, caret_ch, { '(1/2)', 'MiniInputHint' } }
  validate({ { 5, 5, 'AA' } }, 6, ref)
  ref = { { 'abcd', 'MiniInputNormal' }, caret_ch, { '(1/2)', 'MiniInputHint' }, { 'u', 'AA' } }
  validate({ { 5, 5, 'AA' } }, 5, ref)

  -- Complex highlight
  ref = { { 'a', 'BB' }, { 'b', 'CC' }, caret_ch, { '(1/2)', 'MiniInputHint' }, { 'cd', 'CC' }, { 'u', 'AA' } }
  validate({ { 1, 5, 'AA' }, { 1, 3, 'BB' }, { 2, 4, 'CC' } }, 3, ref)
end

T['state_to_chunks()']['respects `max_width`'] = function()
  local validate = function(max_width, ref)
    eq(state_to_chunks({ input = 'def', opts = { prompt = 'ABC' } }, max_width), ref)
  end

  validate(8, { { 'ABC', 'MiniInputPrompt' }, { ' ', 'MiniInputNormal' }, { 'def', 'MiniInputNormal' }, caret_ch })
  validate(7, { { 'BC', 'MiniInputPrompt' }, { ' ', 'MiniInputNormal' }, { 'def', 'MiniInputNormal' }, caret_ch })
  validate(6, { { 'C', 'MiniInputPrompt' }, { ' ', 'MiniInputNormal' }, { 'def', 'MiniInputNormal' }, caret_ch })
  validate(5, { { ' ', 'MiniInputNormal' }, { 'def', 'MiniInputNormal' }, caret_ch })
  validate(4, { { 'def', 'MiniInputNormal' }, caret_ch })
  validate(3, { { 'ef', 'MiniInputNormal' }, caret_ch })
  validate(2, { { 'f', 'MiniInputNormal' }, caret_ch })
  validate(1, { caret_ch })

  -- Can be big values
  local full = { { 'ABC', 'MiniInputPrompt' }, { ' ', 'MiniInputNormal' }, { 'def', 'MiniInputNormal' }, caret_ch }
  validate(100, full)

  mock_state({ input = 'def', opts = { prompt = 'ABC' } })
  eq(child.lua_get('MiniInput.state_to_chunks(_G.mock_state, math.huge)'), full)
end

T['state_to_chunks()']['truncates with centered caret'] = function()
  local validate = function(caret, ref)
    eq(state_to_chunks({ input = 'bcdefg', caret = caret, opts = { prompt = 'A' } }, 5), ref)
  end

  validate(7, { { 'defg', 'MiniInputNormal' }, caret_ch })
  validate(6, { { 'def', 'MiniInputNormal' }, caret_ch, { 'g', 'MiniInputNormal' } })
  validate(5, { { 'de', 'MiniInputNormal' }, caret_ch, { 'fg', 'MiniInputNormal' } })
  validate(4, { { 'cd', 'MiniInputNormal' }, caret_ch, { 'ef', 'MiniInputNormal' } })
  validate(3, { { 'bc', 'MiniInputNormal' }, caret_ch, { 'de', 'MiniInputNormal' } })
  validate(2, { { ' ', 'MiniInputNormal' }, { 'b', 'MiniInputNormal' }, caret_ch, { 'cd', 'MiniInputNormal' } })
  validate(1, { { 'A', 'MiniInputPrompt' }, { ' ', 'MiniInputNormal' }, caret_ch, { 'bc', 'MiniInputNormal' } })

  -- Works with even maximum width
  validate = function(caret, ref)
    eq(state_to_chunks({ input = 'bcdefg', caret = caret, opts = { prompt = 'A' } }, 6), ref)
  end

  validate(7, { { 'cdefg', 'MiniInputNormal' }, caret_ch })
  validate(6, { { 'cdef', 'MiniInputNormal' }, caret_ch, { 'g', 'MiniInputNormal' } })
  validate(5, { { 'cde', 'MiniInputNormal' }, caret_ch, { 'fg', 'MiniInputNormal' } })
  validate(4, { { 'cd', 'MiniInputNormal' }, caret_ch, { 'efg', 'MiniInputNormal' } })
  validate(3, { { 'bc', 'MiniInputNormal' }, caret_ch, { 'def', 'MiniInputNormal' } })
  validate(2, { { ' ', 'MiniInputNormal' }, { 'b', 'MiniInputNormal' }, caret_ch, { 'cde', 'MiniInputNormal' } })
  validate(1, { { 'A', 'MiniInputPrompt' }, { ' ', 'MiniInputNormal' }, caret_ch, { 'bcd', 'MiniInputNormal' } })
end

T['state_to_chunks()']['truncates with multibyte characters'] = function()
  local validate = function(caret, ref)
    eq(state_to_chunks({ input = 'xф「🬗」', caret = caret, opts = { prompt = 'A' } }, 4), ref)
  end

  validate(6, { { '🬗」', 'MiniInputNormal' }, caret_ch })
  validate(5, { { '🬗', 'MiniInputNormal' }, caret_ch, { '」', 'MiniInputNormal' } })
  validate(4, { { '「', 'MiniInputNormal' }, caret_ch, { '🬗', 'MiniInputNormal' } })
  validate(3, { { 'ф', 'MiniInputNormal' }, caret_ch, { '「', 'MiniInputNormal' } })
  validate(2, { { 'x', 'MiniInputNormal' }, caret_ch, { 'ф', 'MiniInputNormal' } })
  validate(1, { { ' ', 'MiniInputNormal' }, caret_ch, { 'xф', 'MiniInputNormal' } })

  -- Should truncate using display width
  local validate_2 = function(caret, max_width, ref)
    eq(state_to_chunks({ input = '「」', caret = caret, opts = { prompt = '' } }, max_width), ref)
  end
  validate_2(1, 2, { caret_ch })
  validate_2(1, 3, { caret_ch, { '「', 'MiniInputNormal' } })
  validate_2(1, 4, { caret_ch, { '「', 'MiniInputNormal' } })
  validate_2(1, 5, { caret_ch, { '「」', 'MiniInputNormal' } })

  validate_2(2, 2, { caret_ch })
  validate_2(2, 3, { { '「', 'MiniInputNormal' }, caret_ch })
  validate_2(2, 4, { { '「', 'MiniInputNormal' }, caret_ch })
  validate_2(2, 5, { { '「', 'MiniInputNormal' }, caret_ch, { '」', 'MiniInputNormal' } })

  validate_2(3, 2, { caret_ch })
  validate_2(3, 3, { { '」', 'MiniInputNormal' }, caret_ch })
  validate_2(3, 4, { { '」', 'MiniInputNormal' }, caret_ch })
  validate_2(3, 5, { { '「」', 'MiniInputNormal' }, caret_ch })
end

T['state_to_chunks()']['truncates to with `state.highlight` and `state.complete`'] = function()
  local state = {}
  local validate = function(caret, max_width, ref)
    local st = vim.deepcopy(state)
    st.caret = caret
    eq(state_to_chunks(st, max_width), ref)
  end

  -- With `state.highlight`
  state = { input = 'bcd', opts = { prompt = 'A' } }
  state.highlight = { { from = 1, to = 2, hl = 'AA' }, { from = 3, to = 3, hl = 'BB' } }

  validate(4, 6, { { 'A', 'MiniInputPrompt' }, { ' ', 'MiniInputNormal' }, { 'bc', 'AA' }, { 'd', 'BB' }, caret_ch })
  validate(3, 6, { { 'A', 'MiniInputPrompt' }, { ' ', 'MiniInputNormal' }, { 'bc', 'AA' }, caret_ch, { 'd', 'BB' } })
  --stylua: ignore
  validate(2, 6, { { 'A', 'MiniInputPrompt' }, { ' ', 'MiniInputNormal' }, { 'b', 'AA' }, caret_ch, { 'c', 'AA' }, { 'd', 'BB' } })
  validate(1, 6, { { 'A', 'MiniInputPrompt' }, { ' ', 'MiniInputNormal' }, caret_ch, { 'bc', 'AA' }, { 'd', 'BB' } })

  validate(4, 4, { { 'bc', 'AA' }, { 'd', 'BB' }, caret_ch })
  validate(4, 3, { { 'c', 'AA' }, { 'd', 'BB' }, caret_ch })
  validate(4, 2, { { 'd', 'BB' }, caret_ch })
  validate(4, 1, { caret_ch })

  validate(3, 4, { { 'bc', 'AA' }, caret_ch, { 'd', 'BB' } })
  validate(3, 3, { { 'c', 'AA' }, caret_ch, { 'd', 'BB' } })
  validate(3, 2, { caret_ch, { 'd', 'BB' } })
  validate(3, 1, { caret_ch })

  validate(2, 4, { { 'b', 'AA' }, caret_ch, { 'c', 'AA' }, { 'd', 'BB' } })
  validate(2, 3, { { 'b', 'AA' }, caret_ch, { 'c', 'AA' } })
  validate(2, 2, { caret_ch, { 'c', 'AA' } })
  validate(2, 1, { caret_ch })

  validate(1, 4, { { ' ', 'MiniInputNormal' }, caret_ch, { 'bc', 'AA' } })
  validate(1, 3, { { ' ', 'MiniInputNormal' }, caret_ch, { 'b', 'AA' } })
  validate(1, 2, { caret_ch, { 'b', 'AA' } })
  validate(1, 1, { caret_ch })

  -- With `state.complete`
  state = { input = 'bcd', opts = { prompt = 'A' } }
  state.complete = { base = '', items = { 'u' }, id = 0, method = '' }

  validate(4, 10, { { ' ', 'MiniInputNormal' }, { 'bcd', 'MiniInputNormal' }, caret_ch, { '(0/1)', 'MiniInputHint' } })
  --stylua: ignore
  validate(3, 10, { { 'A', 'MiniInputPrompt' }, { ' ', 'MiniInputNormal' }, { 'bc', 'MiniInputNormal' }, caret_ch, { '(0/1)', 'MiniInputHint' } })
  --stylua: ignore
  validate(2, 10, { { 'A', 'MiniInputPrompt' }, { ' ', 'MiniInputNormal' }, { 'b', 'MiniInputNormal' }, caret_ch, { '(0/1)', 'MiniInputHint' }, { 'c', 'MiniInputNormal' } })
  --stylua: ignore
  validate(1, 10, { { 'A', 'MiniInputPrompt' }, { ' ', 'MiniInputNormal' }, caret_ch, { '(0/1)', 'MiniInputHint' }, { 'bc', 'MiniInputNormal' }, })

  validate(4, 9, { { ' ', 'MiniInputNormal' }, { 'bcd', 'MiniInputNormal' }, caret_ch, { '(0/1', 'MiniInputHint' } })
  validate(4, 8, { { 'bcd', 'MiniInputNormal' }, caret_ch, { '(0/1', 'MiniInputHint' } })
  validate(4, 7, { { 'bcd', 'MiniInputNormal' }, caret_ch, { '(0/', 'MiniInputHint' } })
  validate(4, 6, { { 'cd', 'MiniInputNormal' }, caret_ch, { '(0/', 'MiniInputHint' } })
  validate(4, 5, { { 'cd', 'MiniInputNormal' }, caret_ch, { '(0', 'MiniInputHint' } })
  validate(4, 4, { { 'd', 'MiniInputNormal' }, caret_ch, { '(0', 'MiniInputHint' } })
  validate(4, 3, { { 'd', 'MiniInputNormal' }, caret_ch, { '(', 'MiniInputHint' } })
  validate(4, 2, { caret_ch, { '(', 'MiniInputHint' } })
  validate(4, 1, { caret_ch })

  validate(3, 5, { { 'bc', 'MiniInputNormal' }, caret_ch, { '(0', 'MiniInputHint' } })
  validate(2, 5, { { ' ', 'MiniInputNormal' }, { 'b', 'MiniInputNormal' }, caret_ch, { '(0', 'MiniInputHint' } })
  validate(1, 5, { { 'A', 'MiniInputPrompt' }, { ' ', 'MiniInputNormal' }, caret_ch, { '(0', 'MiniInputHint' } })

  -- With both `state.highlight` and `state.complete`
  state = { input = 'bcd', opts = { prompt = 'A' } }
  state.highlight = { { from = 1, to = 2, hl = 'AA' }, { from = 3, to = 3, hl = 'BB' } }
  state.complete = { base = '', items = { 'u' }, id = 0, method = '' }
  validate(2, 3, { { 'b', 'AA' }, caret_ch, { '(', 'MiniInputHint' } })
end

T['state_to_chunks()']['truncates to width in special cases'] = function()
  local state = {}
  local validate = function(caret, max_width, ref)
    local st = vim.deepcopy(state)
    st.caret = caret
    eq(state_to_chunks(st, max_width), ref)
  end

  -- With translated special keys
  state = { input = '\n\ra\t\f\3', opts = { prompt = 'A' } }

  validate(7, 9, { { '-L><C-C>', 'MiniInputSpecial' }, caret_ch })
  validate(6, 9, { { 'C-L>', 'MiniInputSpecial' }, caret_ch, { '<C-C', 'MiniInputSpecial' } })
  validate(5, 9, { { 'Tab>', 'MiniInputSpecial' }, caret_ch, { '<C-L', 'MiniInputSpecial' } })
  --stylua: ignore
  validate(4, 9, { { 'CR>', 'MiniInputSpecial' }, { 'a', 'MiniInputNormal' }, caret_ch, { '<Tab', 'MiniInputSpecial' } })
  --stylua: ignore
  validate(3, 9, { { '<CR>', 'MiniInputSpecial' }, caret_ch, { 'a', 'MiniInputNormal' }, { '<Ta', 'MiniInputSpecial' } })
  validate(2, 9, { { '<NL>', 'MiniInputSpecial' }, caret_ch, { '<CR>', 'MiniInputSpecial' } })
  --stylua: ignore
  validate(1, 9, { { 'A', 'MiniInputPrompt' }, { ' ', 'MiniInputNormal' }, caret_ch, { '<NL><C', 'MiniInputSpecial' }, })

  validate(4, 8, { { 'R>', 'MiniInputSpecial' }, { 'a', 'MiniInputNormal' }, caret_ch, { '<Tab', 'MiniInputSpecial' } })
  validate(4, 7, { { 'R>', 'MiniInputSpecial' }, { 'a', 'MiniInputNormal' }, caret_ch, { '<Ta', 'MiniInputSpecial' } })
  validate(4, 6, { { '>', 'MiniInputSpecial' }, { 'a', 'MiniInputNormal' }, caret_ch, { '<Ta', 'MiniInputSpecial' } })
  validate(4, 5, { { '>', 'MiniInputSpecial' }, { 'a', 'MiniInputNormal' }, caret_ch, { '<T', 'MiniInputSpecial' } })
  validate(4, 4, { { 'a', 'MiniInputNormal' }, caret_ch, { '<T', 'MiniInputSpecial' } })
  validate(4, 3, { { 'a', 'MiniInputNormal' }, caret_ch, { '<', 'MiniInputSpecial' } })
  validate(4, 2, { caret_ch, { '<', 'MiniInputSpecial' } })
  validate(4, 1, { caret_ch })

  -- Empty prompt
  state = { input = 'bc', opts = { prompt = '' } }
  validate(3, 3, { { 'bc', 'MiniInputNormal' }, caret_ch })
  validate(2, 3, { { 'b', 'MiniInputNormal' }, caret_ch, { 'c', 'MiniInputNormal' } })
  validate(1, 3, { caret_ch, { 'bc', 'MiniInputNormal' } })

  state.input = ''
  validate(1, 3, { caret_ch })

  -- Multicharacter caret symbol
  local validate_multichar_caret = function(max_width, ref)
    eq(state_to_chunks(state, max_width, { symbol_caret = 'UVW' }), ref)
  end

  state = { input = 'bcd', caret = 4, opts = { prompt = 'A' } }
  local ref = { { 'bcd', 'MiniInputNormal' }, { 'UVW', 'MiniInputCaret' } }
  validate_multichar_caret(10, with_prompt_chunks(ref, 'A'))

  validate_multichar_caret(4, { { 'd', 'MiniInputNormal' }, { 'UVW', 'MiniInputCaret' } })
  validate_multichar_caret(3, { { 'UVW', 'MiniInputCaret' } })
  validate_multichar_caret(2, { { 'VW', 'MiniInputCaret' } })
  validate_multichar_caret(1, { { 'W', 'MiniInputCaret' } })

  state.caret = 3
  ref = { { 'bc', 'MiniInputNormal' }, { 'UVW', 'MiniInputCaret' }, { 'd', 'MiniInputNormal' } }
  validate_multichar_caret(10, with_prompt_chunks(ref, 'A'))

  ref = { { 'c', 'MiniInputNormal' }, { 'UVW', 'MiniInputCaret' }, { 'd', 'MiniInputNormal' } }
  validate_multichar_caret(5, ref)
  validate_multichar_caret(4, { { 'UVW', 'MiniInputCaret' }, { 'd', 'MiniInputNormal' } })
  validate_multichar_caret(3, { { 'VW', 'MiniInputCaret' }, { 'd', 'MiniInputNormal' } })
  validate_multichar_caret(2, { { 'W', 'MiniInputCaret' }, { 'd', 'MiniInputNormal' } })
  validate_multichar_caret(1, { { 'W', 'MiniInputCaret' } })
end

T['state_to_chunks()']['respects `opts.keytrans`'] = function()
  local validate = function(input, caret, ref) eq(state_to_chunks({ input = input, caret = caret }), ref) end

  -- Should translate special control characters
  local ref = with_prompt_chunks({ { '<NL><CR><Tab><C-C><C-V>', 'MiniInputSpecial' }, caret_ch })
  validate('\n\r\t\3\22', 6, ref)

  -- Should place caret between translated characters
  validate('\n\r\t', 4, with_prompt_chunks({ { '<NL><CR><Tab>', 'MiniInputSpecial' }, caret_ch }))
  ref = with_prompt_chunks({ { '<NL><CR>', 'MiniInputSpecial' }, caret_ch, { '<Tab>', 'MiniInputSpecial' } })
  validate('\n\r\t', 3, ref)
  ref = with_prompt_chunks({ { '<NL>', 'MiniInputSpecial' }, caret_ch, { '<CR><Tab>', 'MiniInputSpecial' } })
  validate('\n\r\t', 2, ref)
  validate('\n\r\t', 1, with_prompt_chunks({ caret_ch, { '<NL><CR><Tab>', 'MiniInputSpecial' } }))

  -- Should properly detect control characters
  ref = { { 'a', 'MiniInputNormal' }, { '<Tab>', 'MiniInputSpecial' }, { 'b', 'MiniInputNormal' }, caret_ch }
  validate('a\tb', 4, with_prompt_chunks(ref))
  ref = { { '<CR>', 'MiniInputSpecial' }, { 'a', 'MiniInputNormal' }, { '<NL>', 'MiniInputSpecial' }, caret_ch }
  validate('\ra\n', 4, with_prompt_chunks(ref))
end

T['state_to_chunks()']['respects `opts.include_prompt`'] = function()
  eq(state_to_chunks({}, nil, { include_prompt = false }), { caret_ch })
  eq(state_to_chunks({ input = 'abc' }, nil, { include_prompt = false }), { { 'abc', 'MiniInputNormal' }, caret_ch })
end

T['state_to_chunks()']['respects `opts.include_hint`'] = function()
  local state = { complete = { base = '', items = { 'a', 'b' }, id = 0, method = '' } }
  eq(state_to_chunks(state, nil, { include_hint = false }), with_prompt_chunks({ caret_ch }))
end

T['state_to_chunks()']['respects `opts.symbol_caret`'] = function()
  local state = { input = 'ab', caret = 2 }
  local validate = function(symbol_caret)
    local ref = { { 'a', 'MiniInputNormal' }, { symbol_caret, 'MiniInputCaret' }, { 'b', 'MiniInputNormal' } }
    eq(state_to_chunks(state, nil, { symbol_caret = symbol_caret }), with_prompt_chunks(ref))
  end

  -- Regular
  validate('_')
  validate('│')

  -- Double-width
  validate('「')

  -- Multicharacter
  validate('!@#')

  -- Empty
  local ref = with_prompt_chunks({ { 'a', 'MiniInputNormal' }, { 'b', 'MiniInputNormal' } })
  eq(state_to_chunks(state, nil, { symbol_caret = '' }), ref)
end

T['state_to_chunks()']['respects `opts.symbol_hide`'] = function()
  local validate_one = function(caret, symbol_hide, ref)
    local state = { input = 'ab', caret = caret, opts = { hide = true } }
    eq(state_to_chunks(state, nil, { symbol_hide = symbol_hide }), ref)
  end

  local validate = function(symbol_hide)
    local prompt, pad = { 'Input', 'MiniInputHide' }, { ' ', 'MiniInputNormal' }
    validate_one(3, symbol_hide, { prompt, pad, { symbol_hide .. symbol_hide, 'MiniInputNormal' }, caret_ch })
    --stylua: ignore
    local ref = { prompt, pad, { symbol_hide, 'MiniInputNormal' }, caret_ch, { symbol_hide, 'MiniInputNormal' } }
    validate_one(2, symbol_hide, ref)
    validate_one(1, symbol_hide, { prompt, pad, caret_ch, { symbol_hide .. symbol_hide, 'MiniInputNormal' } })
  end

  -- Regular
  validate('_')

  -- Double-width
  validate('「')

  -- Multicharacter
  validate('!@#')

  -- Empty
  local validate_empty = function(caret)
    local prompt, pad = { 'Input', 'MiniInputHide' }, { ' ', 'MiniInputNormal' }
    validate_one(caret, '', { prompt, pad, caret_ch })
  end

  validate_empty(3)
  validate_empty(2)
  validate_empty(1)
end

T['state_to_chunks()']['validates input'] = function()
  -- No `state` validattion for performance reasons

  local validate_opts = function(bad_opts, pattern)
    expect.error(function() state_to_chunks({}, nil, bad_opts) end, pattern)
  end

  validate_opts({ keytrans = 1 }, '`opts.keytrans`.*boolean')
  validate_opts({ include_prompt = 1 }, '`opts.include_prompt`.*boolean')
  validate_opts({ include_hint = 1 }, '`opts.include_hint`.*boolean')
  validate_opts({ symbol_caret = 1 }, '`opts.symbol_caret`.*string')
  validate_opts({ symbol_hide = 1 }, '`opts.symbol_hide`.*string')
end

T['apply_handler()'] = new_set()

local mock_state_with_tracking_handlers = function(state)
  mock_state(state)
  child.lua([[
    _G.handlers_log = {}
    _G.mock_state.opts.handlers.complete = function(state, ...)
      table.insert(_G.handlers_log, { 'complete', ... })
      state.complete = { base = '', items = { 'u', 'v' } }
    end
    _G.mock_state.opts.handlers.highlight = function(state, ...)
      table.insert(_G.handlers_log, { 'highlight', ... })
      state.highlight = { { from = 1, to = 1, hl = 'AA' } }
    end
    _G.mock_state.opts.handlers.key = function(state, ...)
      table.insert(_G.handlers_log, { 'key', ... })
      state.data.n_key_handler = (state.data.n_key_handler or 0) + 1
    end
    _G.mock_state.opts.handlers.view = function(state, ...)
      table.insert(_G.handlers_log, { 'view', ... })
      state.data.n_view_handler = (state.data.n_view_handler or 0) + 1
    end
  ]])
end

local mock_state_with_returning_handlers = function(state)
  mock_state(state)
  child.lua([[
    _G.handlers_log = {}
    _G.mock_state.opts.handlers.complete = function(state, ...)
      local res = vim.deepcopy(state)
      res.complete = { base = '', items = { 'u', 'v' } }
      return res
    end
    _G.mock_state.opts.handlers.highlight = function(state, ...)
      local res = vim.deepcopy(state)
      res.highlight = { { from = 1, to = 1, hl = 'AA' } }
      return res
    end
    _G.mock_state.opts.handlers.key = function(state, ...)
      local res = vim.deepcopy(state)
      res.data.n_key_handler = (res.data.n_key_handler or 0) + 1
      return res
    end
    _G.mock_state.opts.handlers.view = function(state, ...)
      local res = vim.deepcopy(state)
      res.data.n_view_handler = (res.data.n_view_handler or 0) + 1
      return res
    end
  ]])
end

local apply_handler_to_mock_state = function(name, ...)
  child.lua('_G.name = ' .. vim.inspect(name))
  child.lua('_G.args = ' .. vim.inspect({ ... }))
  child.lua('_G.new_state = MiniInput.apply_handler(vim.deepcopy(_G.mock_state), _G.name, unpack(_G.args))')
end

local validate_apply = function(ref_state_changes)
  local old_state = get_state('mock_state')
  local new_state = get_state('new_state')
  eq(compute_changed_values(old_state, new_state), ref_state_changes)
end

T['apply_handler()']['works'] = function()
  -- Complete
  mock_state_with_tracking_handlers({})
  apply_handler_to_mock_state('complete', 'history')
  -- - Should automatically add `id` and `method` fields
  local ref_complete = { base = '', items = { 'u', 'v' }, id = 0, method = 'history' }
  validate_apply({ complete = ref_complete })

  -- - Should infer `method=''` if argument is `nil`
  mock_state_with_tracking_handlers({})
  apply_handler_to_mock_state('complete', nil)
  ref_complete.method = ''
  validate_apply({ complete = ref_complete })
  validate_log('handlers_log', { { 'complete', '' } })

  -- Highlight
  mock_state_with_tracking_handlers({})
  apply_handler_to_mock_state('highlight')
  validate_apply({ highlight = { { from = 1, hl = 'AA', to = 1 } } })
  validate_log('handlers_log', { { 'highlight' } })

  -- Key
  mock_state_with_tracking_handlers({})
  apply_handler_to_mock_state('key', 'a')
  validate_apply({ data = { n_key_handler = 1 } })
  validate_log('handlers_log', { { 'key', 'a' } })

  -- View
  mock_state_with_tracking_handlers({})
  apply_handler_to_mock_state('view')
  validate_apply({ data = { n_view_handler = 1 } })
  validate_log('handlers_log', { { 'view' } })
end

T['apply_handler()']['works when handler returns new state'] = function()
  mock_state_with_returning_handlers({})
  apply_handler_to_mock_state('complete', 'history')
  local ref_complete = { base = '', items = { 'u', 'v' }, id = 0, method = 'history' }
  validate_apply({ complete = ref_complete })

  mock_state_with_returning_handlers({})
  apply_handler_to_mock_state('highlight')
  validate_apply({ highlight = { { from = 1, hl = 'AA', to = 1 } } })

  mock_state_with_returning_handlers({})
  apply_handler_to_mock_state('key', 'a')
  validate_apply({ data = { n_key_handler = 1 } })

  mock_state_with_returning_handlers({})
  apply_handler_to_mock_state('view')
  validate_apply({ data = { n_view_handler = 1 } })
end

T['apply_handler()']['respects hidden input'] = function()
  -- Should apply key and view handlers, but not complete and highlight
  mock_state_with_tracking_handlers({ opts = { hide = true } })
  apply_handler_to_mock_state('complete', 'history')
  validate_apply({})
  validate_log('handlers_log', {})

  mock_state_with_tracking_handlers({ opts = { hide = true } })
  apply_handler_to_mock_state('highlight')
  validate_apply({})
  validate_log('handlers_log', {})

  mock_state_with_tracking_handlers({ opts = { hide = true } })
  apply_handler_to_mock_state('key', 'a')
  validate_apply({ data = { n_key_handler = 1 } })
  validate_log('handlers_log', { { 'key', 'a' } })

  mock_state_with_tracking_handlers({ opts = { hide = true } })
  apply_handler_to_mock_state('view')
  validate_apply({ data = { n_view_handler = 1 } })
  validate_log('handlers_log', { { 'view' } })
end

T['apply_handler()']['handles bad handler application'] = function()
  -- Should error during handler application
  mock_state({})
  child.lua('_G.mock_state.opts.handlers.key = function(...) error("Bad key handler") end')
  -- - There is an explicit error because there is no active input
  expect.error(function() apply_handler_to_mock_state('key', 'a') end, '%(mini%.input%).*Bad key handler')

  -- Should validate output to be a valid state
  mock_state({})
  child.lua('_G.mock_state.opts.handlers.view = function(state) state.caret = "a" end')
  -- - There is an explicit error because there is no active input
  expect.error(function() apply_handler_to_mock_state('view') end, '[^)] %(mini%.input%) `state.caret`.*number')
end

T['apply_handler()']['works during input key query process'] = function()
  mock_state_with_tracking_handlers({})
  child.lua_notify([[
    local handlers = _G.mock_state.opts.handlers

    handlers.complete = function(state, method)
      table.insert(_G.handlers_log, { 'complete', method })
      if method == 'history' then state.complete = { base = '', items = { 'u', 'v' } } end
      if method == 'error' then
        state.complete = nil
        error('Bad complete method')
      end
    end

    handlers.key = function(state, key)
      if key == ' ' or key == 'e' then
        local method = key == ' ' and 'history' or 'error'
        state = MiniInput.apply_handler(state, 'complete', method)
      end
      table.insert(_G.handlers_log, { 'key', key, state.status, state.complete })
      return state
    end

    MiniInput.get({ handlers = handlers })
  ]])
  child.lua('_G.handlers_log = {}')

  -- Should apply proper complete handler when requested inside key handler
  type_keys(' ')
  local ref_complete = { base = '', items = { 'u', 'v' }, id = 0, method = 'history' }
  local ref_key_entry = { 'key', ' ', 'progress', ref_complete }
  validate_log('handlers_log', { { 'complete', 'history' }, ref_key_entry, { 'highlight' }, { 'view' } })

  -- Should finish current step execution and trigger input finishing step
  child.lua('_G.apply_handler_log = {}')
  type_keys('e')
  --stylua: ignore
  local ref_handlers_log = {
    -- Handle current step
    { 'complete', 'error' }, { 'key', 'e', 'cancel', nil }, { 'highlight' }, { 'view' },
    -- Perform finishing step. `state.complete` is `nil` as new state is still
    -- set during input step processing even if handler application errored.
    { 'key', vim.NIL, 'cancel', nil }, { 'highlight' }, { 'view' },

  }
  if child.fn.has('nvim-0.10') == 1 then validate_log('handlers_log', ref_handlers_log) end
  validate_no_input()
end

T['apply_handler()']['validates arguments and output'] = function()
  -- No input `state` validattion for performance reasons

  expect.error(function() apply_handler_to_mock_state({}, 1) end, '`name`.*one of')
end

return T
