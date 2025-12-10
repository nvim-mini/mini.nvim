local mock_title = function(x)
  if type(x) ~= 'string' then return x end
  -- Make sure that full path title is same on any machine
  return x:gsub('^.*/tests/dir%-files', 'MOCK_ROOT/tests/dir-files')
end

_G.nvim_open_win_orig = vim.api.nvim_open_win

vim.api.nvim_open_win = function(buf_id, enter, config)
  config.title = mock_title(config.title)
  return nvim_open_win_orig(buf_id, enter, config)
end

_G.nvim_win_set_config_orig = vim.api.nvim_win_set_config

vim.api.nvim_win_set_config = function(win_id, config)
  config.title = mock_title(config.title)
  return nvim_win_set_config_orig(win_id, config)
end
