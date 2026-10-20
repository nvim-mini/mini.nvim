_G.process_log = {}

local process_id = 1
local new_process = function(pid)
  local is_active, is_closing = true, false
  return {
    pid = pid,
    close = function(_)
      table.insert(_G.process_log, 'Process ' .. pid .. ' was closed.')
      is_active, is_closing = false, true
    end,
    is_closing = function(_) return is_closing end,
    is_active = function(_) return is_active end,
  }
end

-- Define object containing the queue with mocking stdio data.
-- Each element is a table with `out` and `err` fields, both can be `nil`,
-- `string`, or `string[]`. **Heavy** assumptions about how `new_pipe` is used:
-- - It is called twice before each `vim.uv.spawn`.
-- - It is first called for `stdout`, then for `stderr`.
_G.stdio_queue = {}
local io_field = 'out'
vim.uv.new_pipe = function()
  local cur_process_id, cur_io_field = process_id, io_field
  local cur_feed = (_G.stdio_queue[cur_process_id] or {})[cur_io_field]
  if type(cur_feed) ~= 'table' then cur_feed = { cur_feed } end
  io_field = io_field == 'out' and 'err' or 'out'

  return {
    read_start = function(_, callback)
      for _, x in ipairs(cur_feed) do
        if type(x) == 'table' then callback(x.err, nil) end
        if type(x) == 'string' then callback(nil, x) end
      end
      callback(nil, nil)
    end,
    close = function()
      table.insert(_G.process_log, string.format('Stream %s for process %s was closed.', cur_io_field, cur_process_id))
    end,
  }
end

-- Array of data to mock the process. Each element can be either `nil` or
-- a table with the following fields:
-- - <action> `(function|nil)` - callable to simulate job's side-effects.
-- - <duration> `(number|nil)` - how long a process should take. Default: 0.
-- - <exit_code> `(number|nil)` - exit code. Default: 0.
_G.process_mock_data = {}
_G.spawn_log = {}
vim.uv.spawn = function(path, options, on_exit)
  local options_without_callables = vim.deepcopy(options) or {}
  options_without_callables.stdio = nil
  table.insert(_G.spawn_log, { executable = path, options = options_without_callables })

  local pid = process_id
  process_id = process_id + 1

  local mock_data = _G.process_mock_data[pid] or {}
  if vim.is_callable(mock_data.action) then mock_data.action() end
  vim.defer_fn(function() on_exit(mock_data.exit_code or 0) end, mock_data.duration or 0)

  return new_process(pid), pid
end

vim.uv.process_kill = function(process) table.insert(_G.process_log, 'Process ' .. process.pid .. ' was killed.') end

_G.n_cpu_info = 4
vim.uv.cpu_info = function()
  local res = {}
  for i = 1, _G.n_cpu_info do
    res[i] = { model = 'A Very High End CPU' }
  end
  return res
end
