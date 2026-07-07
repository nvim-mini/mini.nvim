_G.process_log = {}

local n_pid, n_stdout = 0, 0
local new_process = function(pid)
  return {
    pid = pid,

    _is_active_indicator = true,
    is_active = function(process) return process._is_active_indicator end,
    kill = function(process)
      process._is_active_indicator = false
      table.insert(_G.process_log, 'Process ' .. pid .. ' was killed.')
    end,

    _is_closing_indicator = false,
    is_closing = function(process) return process._is_closing_indicator end,
    close = function(process)
      process._is_closing_indicator = true
      table.insert(_G.process_log, 'Process ' .. pid .. ' was closed.')
    end,
  }
end

-- Mock `stdout` by using global `_G.stdout_data_feed` array as source.
-- Each feed's element should be either string (for usable data) or a table
-- with `err` field (for error).
vim.loop.new_pipe = function()
  n_stdout = n_stdout + 1
  local cur_stdout_id = 'Stdout_' .. n_stdout

  return {
    _is_active_indicator = true,
    is_active = function(stream) return stream._is_active_indicator end,
    read_start = function(stream, callback)
      -- Not possible to execute `vim.fn` functions during `pipe:read_start()`
      local vim_fn_orig = vim.deepcopy(vim.fn)
      vim.fn = setmetatable({}, { __index = function() error('Can not use `vim.fn` during `read_start`.') end })

      -- A stream/pipe is active if it is actually reading data at the moment
      stream._is_active_indicator = true
      for _, x in ipairs(_G.stdout_data_feed or {}) do
        if type(x) == 'table' then callback(x.err, nil) end
        if type(x) == 'string' then callback(nil, x) end
      end

      table.insert(_G.process_log, 'Stdout ' .. cur_stdout_id .. ' finished reading.')
      stream._is_active_indicator = false
      callback(nil, nil)

      vim.fn = vim_fn_orig
    end,
    read_stop = function(stream)
      stream._is_active_indicator = false
      table.insert(_G.process_log, 'Stdout ' .. cur_stdout_id .. ' was stopped.')
    end,

    _is_closing_indicator = false,
    is_closing = function(stream) return stream._is_closing_indicator end,
    close = function(stream)
      stream._is_closing_indicator = true
      table.insert(_G.process_log, 'Stdout ' .. cur_stdout_id .. ' was closed.')
    end,
  }
end

_G.spawn_log = {}
vim.loop.spawn = function(path, options, on_exit)
  local options_without_callables = vim.deepcopy(options)
  options_without_callables.stdio = nil
  table.insert(_G.spawn_log, { executable = path, options = options_without_callables })

  vim.schedule(function() on_exit() end)

  n_pid = n_pid + 1
  local pid = 'Pid_' .. n_pid
  return new_process(pid), pid
end
