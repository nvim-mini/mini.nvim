local Helpers = {}

-- Add extra expectations
Helpers.expect = vim.deepcopy(MiniTest.expect)

Helpers.expect.match = MiniTest.new_expectation(
  'string matching',
  function(str, pattern) return str:find(pattern) ~= nil end,
  function(str, pattern) return string.format('Pattern: %s\nObserved string: %s', vim.inspect(pattern), str) end
)

Helpers.expect.no_match = MiniTest.new_expectation(
  'no string matching',
  function(str, pattern) return str:find(pattern) == nil end,
  function(str, pattern) return string.format('Pattern: %s\nObserved string: %s', vim.inspect(pattern), str) end
)

Helpers.expect.equality_approx = MiniTest.new_expectation(
  'approximate equality',
  function(x, y, tol)
    if type(x) ~= type(y) then return false end
    if type(x) == 'number' then return math.abs(x - y) <= tol end
    if type(x) ~= 'table' then return vim.deep_equal(x, y) end

    local x_keys, y_keys = vim.tbl_keys(x), vim.tbl_keys(y)
    table.sort(x_keys)
    table.sort(y_keys)
    if not vim.deep_equal(x_keys, y_keys) then return false end
    for _, key in ipairs(x_keys) do
      if math.abs(x[key] - y[key]) > tol then return false end
    end

    return true
  end,
  function(x, y, tol) return string.format('Left: %s\nRight: %s\nTolerance: %s', vim.inspect(x), vim.inspect(y), tol) end
)

Helpers.make_partial_tbl = function(tbl, ref)
  local res = {}
  for k, v in pairs(ref) do
    res[k] = (type(tbl[k]) == 'table' and type(v) == 'table') and Helpers.make_partial_tbl(tbl[k], v) or tbl[k]
  end
  for i = 1, #tbl do
    if ref[i] == nil then res[i] = tbl[i] end
  end
  return res
end

Helpers.expect.equality_partial_tbl = MiniTest.new_expectation(
  'equality of tables only in reference fields',
  function(x, y)
    if type(x) == 'table' and type(y) == 'table' then x = Helpers.make_partial_tbl(x, y, {}) end
    return vim.deep_equal(x, y)
  end,
  function(x, y)
    return string.format('Left: %s\nRight: %s', vim.inspect(Helpers.make_partial_tbl(x, y, {})), vim.inspect(y))
  end
)

-- Monkey-patch `MiniTest.new_child_neovim` with helpful wrappers
Helpers.new_child_neovim = function()
  local child = MiniTest.new_child_neovim()

  local prevent_hanging = function(method)
    if not child.is_blocked() then return end

    local msg = string.format('Can not use `child.%s` because child process is blocked.', method)
    error(msg)
  end

  child.setup = function()
    child.restart({ '-u', 'scripts/minimal_init.lua' })

    -- Change initial buffer to be readonly. This not only increases execution
    -- speed, but more closely resembles manually opened Neovim.
    child.bo.readonly = false
  end

  child.set_lines = function(arr, start, finish)
    prevent_hanging('set_lines')

    if type(arr) == 'string' then arr = vim.split(arr, '\n') end

    child.api.nvim_buf_set_lines(0, start or 0, finish or -1, false, arr)
  end

  child.get_lines = function(start, finish)
    prevent_hanging('get_lines')

    return child.api.nvim_buf_get_lines(0, start or 0, finish or -1, false)
  end

  child.set_cursor = function(line, column, win_id)
    prevent_hanging('set_cursor')

    child.api.nvim_win_set_cursor(win_id or 0, { line, column })
  end

  child.get_cursor = function(win_id)
    prevent_hanging('get_cursor')

    return child.api.nvim_win_get_cursor(win_id or 0)
  end

  child.set_size = function(lines, columns)
    prevent_hanging('set_size')

    if type(lines) == 'number' then child.o.lines = lines end

    if type(columns) == 'number' then child.o.columns = columns end
  end

  child.get_size = function()
    prevent_hanging('get_size')

    return { child.o.lines, child.o.columns }
  end

  --- Assert visual marks
  ---
  --- Useful to validate visual selection
  ---
  ---@param first number|table Table with start position or number to check linewise.
  ---@param last number|table Table with finish position or number to check linewise.
  ---@private
  child.expect_visual_marks = function(first, last)
    child.ensure_normal_mode()

    first = type(first) == 'number' and { first, 0 } or first
    last = type(last) == 'number' and { last, 2147483647 } or last

    MiniTest.expect.equality(child.api.nvim_buf_get_mark(0, '<'), first)
    MiniTest.expect.equality(child.api.nvim_buf_get_mark(0, '>'), last)
  end

  -- Work with 'mini.nvim':
  -- - `mini_load` - load with "normal" table config
  -- - `mini_load_strconfig` - load with "string" config, which is still a
  --   table but with string values. Final loading is done by constructing
  --   final string table. Needed to be used if one of the config entries is a
  --   function (as currently there is no way to communicate a function object
  --   through RPC).
  -- - `mini_unload` - unload module and revert common side effects.
  child.mini_load = function(name, config)
    local lua_cmd = ([[require('mini.%s').setup(...)]]):format(name)
    child.lua(lua_cmd, { config })
  end

  child.mini_load_strconfig = function(name, strconfig)
    local t = {}
    for key, val in pairs(strconfig) do
      table.insert(t, key .. ' = ' .. val)
    end
    local str = string.format('{ %s }', table.concat(t, ', '))

    local command = ([[require('mini.%s').setup(%s)]]):format(name, str)
    child.lua(command)
  end

  child.mini_unload = function(name)
    local module_name = 'mini.' .. name
    local tbl_name = 'Mini' .. name:sub(1, 1):upper() .. name:sub(2)

    -- Unload Lua module
    child.lua(([[package.loaded['%s'] = nil]]):format(module_name))

    -- Remove global table
    child.lua(('_G["%s"] = nil'):format(tbl_name))

    -- Remove autocmd group
    if child.fn.exists('#' .. tbl_name) == 1 then child.api.nvim_del_augroup_by_name(tbl_name) end
  end

  child.expect_screenshot = function(opts, path)
    opts = opts or {}
    local screenshot_opts = { redraw = opts.redraw }
    opts.redraw = nil
    MiniTest.expect.reference_screenshot(child.get_screenshot(screenshot_opts), path, opts)
  end

  -- Poke child's event loop to make it up to date
  child.poke_eventloop = function() child.api.nvim_eval('1') end

  return child
end

-- Detect CI
Helpers.is_ci = function() return os.getenv('CI') ~= nil end
Helpers.skip_in_ci = function(msg)
  if Helpers.is_ci() then MiniTest.skip(msg or 'Does not test properly in CI') end
end

-- Detect OS
Helpers.is_windows = function() return vim.fn.has('win32') == 1 end
Helpers.skip_on_windows = function(msg)
  if Helpers.is_windows() then MiniTest.skip(msg or 'Does not test properly on Windows') end
end

Helpers.is_macos = function() return vim.fn.has('mac') == 1 end
Helpers.skip_on_macos = function(msg)
  if Helpers.is_macos() then MiniTest.skip(msg or 'Does not test properly on MacOS') end
end

Helpers.is_linux = function() return vim.fn.has('linux') == 1 end
Helpers.skip_on_linux = function(msg)
  if Helpers.is_linux() then MiniTest.skip(msg or 'Does not test properly on Linux') end
end

-- Standardized way of dealing with time
Helpers.is_slow = function() return Helpers.is_ci() and (Helpers.is_windows() or Helpers.is_macos()) end
Helpers.skip_if_slow = function(msg)
  if Helpers.is_slow() then MiniTest.skip(msg or 'Does not test properly in slow context') end
end

Helpers.get_time_const = function(delay)
  local coef = 1
  if Helpers.is_ci() then
    if Helpers.is_linux() then coef = 2 end
    if Helpers.is_windows() then coef = 5 end
    if Helpers.is_macos() then coef = 15 end
  end
  return coef * delay
end

Helpers.sleep = function(ms, child, skip_slow)
  if skip_slow then
    Helpers.skip_if_slow('Skip because state checks after sleep are hard to make robust in slow context')
  end
  vim.uv.sleep(math.max(ms, 1))
  if child ~= nil then child.poke_eventloop() end
end

-- Standardized way of setting number of retries
Helpers.get_n_retry = function(n)
  local coef = 1
  if Helpers.is_ci() then
    if Helpers.is_linux() then coef = 2 end
    if Helpers.is_windows() then coef = 3 end
    if Helpers.is_macos() then coef = 4 end
  end
  return coef * n
end

return Helpers
