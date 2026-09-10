if _G.MiniDoc == nil then require('mini.doc').setup() end

-- Do multiple `generate()` while reporting progress
-- Generate tags and notify after all are done
local modules = vim.tbl_map(function(p) return vim.fn.fnamemodify(p, ':t:r') end, vim.fn.readdir('lua/mini'))
local n_modules = #modules

local write_post = function(d)
  -- Reload buffer with output file (helps during writing annotations)
  local ok, buf_id = pcall(vim.fn.bufnr, d.info.output)
  if type(buf_id) == 'number' and vim.api.nvim_buf_is_valid(buf_id) then
    vim.api.nvim_buf_call(buf_id, function() vim.cmd('noautocmd silent edit | set ft=help') end)
  end
end
local config = { hooks = { write_post = write_post } }

local progress_opts = { kind = 'progress', source = 'minidoc', title = 'minidoc', status = 'running', percent = 0 }
progress_opts.id = vim.api.nvim_echo({}, false, progress_opts)
local generate = function(i, basename)
  local to = 'mini-' .. (basename == 'init' and 'nvim' or basename)
  MiniDoc.generate({ './lua/mini/' .. basename .. '.lua' }, './doc/' .. to .. '.txt', config)

  progress_opts.percent = math.floor(100 * i / (n_modules + 1))
  vim.api.nvim_echo({ { basename } }, false, progress_opts)
end

for i, m in ipairs(modules) do
  generate(i, m)
end

vim.cmd('helptags ./doc')
progress_opts.percent, progress_opts.status = 100, 'success'
vim.api.nvim_echo({ { 'Done' } }, false, progress_opts)
