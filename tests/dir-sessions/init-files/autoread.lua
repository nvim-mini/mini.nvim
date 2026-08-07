-- Avoid hit-enter-prompt
vim.o.cmdheight = 10
-- Avoid storing unnecessary data (also sometimes avoid hit-enter-prompt)
vim.o.swapfile = false

-- Track session relevant events to test that they are triggered
_G.event_log = {}
local f = function(ev) table.insert(_G.event_log, ev.event) end
local events = vim.fn.has('nvim-0.12') == 1 and { 'SessionLoadPre', 'SessionLoadPost' } or { 'SessionLoadPost' }
vim.api.nvim_create_autocmd(events, { callback = f })

vim.cmd('set rtp+=.')
require('mini.sessions').setup({ autoread = true, autowrite = false, directory = 'tests/dir-sessions/local' })
