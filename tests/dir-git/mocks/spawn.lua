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
-- Each element is an array of tables with the format:
-- - Element 1 is stdio type. One of "in", "out", "err".
-- - Element 2 is the feed of the pipe. Can be `nil`, `string`, `string[]`.
_G.stdio_queue = {}
local process_pipe_indexes = {}
vim.uv.new_pipe = function()
  local cur_process_id = process_id
  local process_pipe_data = _G.stdio_queue[cur_process_id] or {}

  process_pipe_indexes[cur_process_id] = (process_pipe_indexes[cur_process_id] or 0) + 1
  local cur_pipe_data = process_pipe_data[process_pipe_indexes[cur_process_id]] or {}
  local cur_io_field, cur_feed = cur_pipe_data[1], cur_pipe_data[2]

  if type(cur_feed) ~= 'table' then cur_feed = { cur_feed } end

  return {
    read_start = function(_, callback)
      for _, x in ipairs(cur_feed) do
        if type(x) == 'table' then callback(x.err, nil) end
        if type(x) == 'string' then callback(nil, x) end
      end
      callback(nil, nil)
    end,
    write = function(_, chars)
      local msg = string.format('Stream %s for process %s wrote: %s', cur_io_field, cur_process_id, chars)
      table.insert(_G.process_log, msg)
    end,
    shutdown = function()
      local msg = string.format('Stream %s for process %s was shut down.', cur_io_field, cur_process_id)
      table.insert(_G.process_log, msg)
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
  if vim.is_callable(mock_data.action) then mock_data.action(path, options) end
  vim.defer_fn(function() on_exit(mock_data.exit_code or 0) end, mock_data.duration or 0)

  return new_process(pid), pid
end
