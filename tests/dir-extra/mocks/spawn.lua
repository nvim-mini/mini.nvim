_G.process_log = {}

local n_pid = 0
local new_process = function(pid)
  return {
    _is_active_indicator = true,
    pid = pid,
    is_active = function(process) return process._is_active_indicator end,
    close = function(process)
      process._is_active_indicator = false
      table.insert(_G.process_log, 'Process ' .. pid .. ' was closed.')
    end,
  }
end

-- Mock streams by using global `_G.stdout_data_feed` and `_G.stderr_data_feed`
-- arrays as source. Each feed's element should be either string (for usable
-- data) or a table with `err` field (for error).
local stream_counts = {}
vim.uv.new_pipe = function()
  -- NOTE: Use `_G.stream_type_queue` to determine which stream type to create
  -- (for log purposes). This is to account for `vim.uv.spawn` creating
  -- different sets of streams. Assume 'stdout' by default.
  if _G.stream_type_queue == nil or #_G.stream_type_queue == 0 then _G.stream_type_queue = { 'stdout' } end
  local stream_type = _G.stream_type_queue[1]
  table.remove(_G.stream_type_queue, 1)

  local new_count = (stream_counts[stream_type] or 0) + 1
  stream_counts[stream_type] = new_count
  local cur_stream_id = stream_type .. '_' .. new_count

  return {
    read_start = function(_, callback)
      -- It is not possible in Neovim<0.10 to execute `vim.fn` functions during
      -- `pipe:read_start()`
      local data_feed = stream_type == 'stdout' and _G.stdout_data_feed or _G.stderr_data_feed
      for _, x in ipairs(data_feed or {}) do
        if type(x) == 'table' then callback(x.err, nil) end
        if type(x) == 'string' then callback(nil, x) end
      end
      callback(nil, nil)
    end,
    close = function() table.insert(_G.process_log, string.format('%s was closed.', cur_stream_id)) end,
  }
end

_G.spawn_log = {}
vim.uv.spawn = function(path, options, on_exit)
  local options_without_callables = vim.deepcopy(options)
  options_without_callables.stdio = nil
  table.insert(_G.spawn_log, { executable = path, options = options_without_callables })

  vim.schedule(function() on_exit() end)

  n_pid = n_pid + 1
  local pid = 'Pid_' .. n_pid
  return new_process(pid), pid
end

vim.uv.process_kill = function(process)
  process._is_active_indicator = false
  table.insert(_G.process_log, 'Process ' .. process.pid .. ' was killed.')
end
