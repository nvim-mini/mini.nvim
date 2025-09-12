local MiniTerm = {}
local H = {}

-- Setup ----------------------------------------------------------------------
MiniTerm.setup = function(config)
  _G.MiniTerm = MiniTerm

  config = H.setup_config(config)
  H.apply_config(config)
  H.create_keybinds()
  H.create_user_commands()
end

-- Run Command in Floating Window ---------------------------------------------
MiniTerm.run_cmd = function(command)
  if not vim.fn.executable(command) == 1 then
    print('!!! Please Install ' .. command .. ' !!!')
    return
  end
  MiniTerm.state.job = H.createFloatingWin({ buf = MiniTerm.state.job.buf, title = command })
  vim.fn.jobstart(command, {
    term = true,
    on_exit = function()
      vim.api.nvim_win_close(MiniTerm.state.job.win, true)
      vim.api.nvim_buf_delete(MiniTerm.state.job.buf, { force = true })
    end,
  })
  vim.cmd.startinsert()
end

-- Open Terminal in Floating Window -------------------------------------------
MiniTerm.terminal = function()
  MiniTerm.state.terminal = H.createFloatingWin({ buf = MiniTerm.state.terminal.buf })
  if vim.bo[MiniTerm.state.terminal.buf].buftype ~= 'terminal' then
    vim.cmd.terminal()
    vim.keymap.set('n', '<c-q>', function() vim.api.nvim_win_hide(0) end, { buffer = true })
  end
  vim.cmd.startinsert()
end

-- Default Config -------------------------------------------------------------
MiniTerm.config = {
  win = {
    height = 0.8,
    width = 0.8,
    border = vim.o.winborder or 'rounded',
  },
}

-- Terminal & Job Data --------------------------------------------------------
MiniTerm.state = {
  terminal = {
    win = -1,
    buf = -1,
  },
  job = {
    buf = -1,
    win = -1,
  },
}

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniTerm.config)

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})
  H.check_type('config.win', config.win, 'table', true)
  H.check_type('config.win.height', config.win.height, 'number', true)
  H.check_type('config.win.width', config.win.width, 'number', true)
  H.check_type('config.win.border', config.win.border, 'string', true)

  return config
end

H.apply_config = function(config) MiniTerm.config = config end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

-- Keybinds -------------------------------------------------------------------
H.create_keybinds = function() vim.keymap.set('t', '<c-q>', '<c-\\><c-n>', { desc = 'Exit Terminal Mode' }) end

-- Window --------------------------------------------------------------------
H.createFloatingWin = function(opts)
  opts = opts or {}
  local width = math.floor(vim.o.columns * (MiniTerm.config.win.width or 0.8))
  local height = math.floor(vim.o.lines * (MiniTerm.config.win.height or 0.8))
  local buf = nil
  if vim.api.nvim_buf_is_valid(opts.buf) then
    buf = opts.buf
  else
    buf = vim.api.nvim_create_buf(false, true)
  end

  local config = {
    relative = 'editor',
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = opts.style or 'minimal',
    border = opts.border or 'rounded',
    title = opts.title or 'Floating Window',
    title_pos = 'center',
  }
  local win = vim.api.nvim_open_win(buf, true, config)

  return { buf = buf, win = win }
end

-- Command --------------------------------------------------------------------
H.create_user_commands = function()
  vim.api.nvim_create_user_command('MiniTerm', function(opts)
    if opts.args == '' then
      MiniTerm.terminal()
    else
      MiniTerm.run_cmd(opts.args)
    end
  end, { nargs = '*' })
end

return MiniTerm
