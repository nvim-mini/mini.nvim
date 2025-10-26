local helpers = dofile('tests/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('statusline', config) end
local unload_module = function() child.mini_unload('statusline') end
local reload_module = function(config) unload_module(); load_module(config) end
local set_cursor = function(...) return child.set_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local set_width = function(width, win_id) child.api.nvim_win_set_width(win_id or 0, width) end
local type_keys = function(...) return child.type_keys(...) end
--stylua: ignore end

-- Make helpers
local setup_windows = function()
  child.cmd('%bwipeout!')

  -- Ensure only two windows
  if #child.api.nvim_list_wins() > 1 then child.cmd('only') end
  child.cmd('vsplit')

  local win_list = child.api.nvim_list_wins()
  if win_list[1] == child.api.nvim_get_current_win() then return { active = win_list[1], inactive = win_list[2] } end
  return { active = win_list[2], inactive = win_list[1] }
end

local get_two_windows = function()
  local wins_tabpage = child.api.nvim_tabpage_list_wins(0)
  local cur_win = child.api.nvim_get_current_win()
  return { active = cur_win, inactive = cur_win == wins_tabpage[1] and wins_tabpage[2] or wins_tabpage[1] }
end

local eval_statusline = function(stl, win_id) return child.api.nvim_eval_statusline(stl, { winid = win_id }).str end

local validate_statusline = function(win_id, ref_content_source)
  win_id = win_id == 0 and child.api.nvim_get_current_win() or win_id
  local active = eval_statusline('%{%v:lua.MiniStatusline.active()%}', win_id)
  local inactive = eval_statusline('%{%v:lua.MiniStatusline.inactive()%}', win_id)
  local out = eval_statusline(child.api.nvim_get_option_value('statusline', { win = win_id }), win_id)
  local out_content_source = out == active and 'active' or (out == inactive and 'inactive' or 'unknown')
  eq(out_content_source, ref_content_source)
end

-- Mocks
local mock_miniicons = function() child.lua('require("mini.icons").setup()') end

local mock_gitsigns = function()
  child.b.gitsigns_head, child.b.gitsigns_status = 'main', '+1 ~2 -3'
end

local mock_minigit = function() child.b.minigit_summary_string = 'main|bisect (MM)' end

local mock_minidiff = function() child.b.minidiff_summary_string = '#4 +3 ~2 -1' end

local mock_diagnostics = function()
  child.cmd('luafile tests/dir-statusline/mock-diagnostics.lua')
  child.cmd('doautocmd DiagnosticChanged')
end

local mock_lsp = function() child.cmd('luafile tests/mock-lsp/months.lua') end

local mock_buffer_size = function(bytes)
  -- Reduce bytes for end-of-line: '\n' on Unix and '\r\n' on Windows
  local eol_bytes = helpers.is_windows() and 2 or 1
  child.api.nvim_buf_set_lines(0, 0, -1, false, { string.rep('a', bytes - eol_bytes) })
  child.bo.modified = false
end

-- Time constants
local term_mode_wait = helpers.get_time_const(50)
local small_time = helpers.get_time_const(10)

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      load_module()

      -- Ensure wide enough window
      child.o.columns = 300
      setup_windows()
    end,
    post_once = child.stop,
  },
  n_retry = helpers.get_n_retry(1),
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  -- Global variable
  eq(child.lua_get('type(_G.MiniStatusline)'), 'table')

  -- Autocommand group
  eq(child.fn.exists('#MiniStatusline'), 1)

  -- Highlight groups
  child.cmd('hi clear')
  load_module()
  local has_highlight = function(group, value) expect.match(child.cmd_capture('hi ' .. group), value) end

  has_highlight('MiniStatuslineModeNormal', 'links to Cursor')
  has_highlight('MiniStatuslineModeInsert', 'links to DiffChange')
  has_highlight('MiniStatuslineModeVisual', 'links to DiffAdd')
  has_highlight('MiniStatuslineModeReplace', 'links to DiffDelete')
  has_highlight('MiniStatuslineModeCommand', 'links to DiffText')
  has_highlight('MiniStatuslineModeOther', 'links to IncSearch')
  has_highlight('MiniStatuslineDevinfo', 'links to StatusLine')
  has_highlight('MiniStatuslineFilename', 'links to StatusLineNC')
  has_highlight('MiniStatuslineFileinfo', 'links to StatusLine')
  has_highlight('MiniStatuslineInactive', 'links to StatusLineNC')

  -- Sets global value of 'statusline'
  eq(
    child.go.statusline,
    '%{%(nvim_get_current_win()==#g:actual_curwin || &laststatus==3) ? v:lua.MiniStatusline.active() : v:lua.MiniStatusline.inactive()%}'
  )
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniStatusline.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniStatusline.config.' .. field), value) end

  expect_config('content.active', vim.NIL)
  expect_config('content.inactive', vim.NIL)
  expect_config('use_icons', true)
end

T['setup()']['respects `config` argument'] = function()
  reload_module({ use_icons = false })
  eq(child.lua_get('MiniStatusline.config.use_icons'), false)
end

T['setup()']['validates `config` argument'] = function()
  unload_module()

  local expect_config_error = function(config, name, target_type)
    expect.error(load_module, vim.pesc(name) .. '.*' .. vim.pesc(target_type), config)
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ content = 'a' }, 'content', 'table')
  expect_config_error({ content = { active = 'a' } }, 'content.active', 'function')
  expect_config_error({ content = { inactive = 'a' } }, 'content.inactive', 'function')
  expect_config_error({ use_icons = 'a' }, 'use_icons', 'boolean')
end

T['setup()']['ensures colors'] = function()
  child.cmd('colorscheme default')
  expect.match(child.cmd_capture('hi MiniStatuslineModeNormal'), 'links to Cursor')
end

T['setup()']["sets proper dynamic 'statusline' value"] = function()
  local wins = get_two_windows()

  validate_statusline(wins.active, 'active')
  validate_statusline(wins.inactive, 'inactive')

  child.api.nvim_set_current_win(wins.inactive)
  validate_statusline(wins.active, 'inactive')
  validate_statusline(wins.inactive, 'active')
end

T['setup()']['disables built-in statusline in quickfix window'] = function()
  child.cmd('copen')
  validate_statusline(0, 'active')
end

T['setup()']['ensures content when working with built-in terminal'] = function()
  helpers.skip_on_windows('Terminal emulator testing is not robust/easy on Windows')

  local init_buf_id = child.api.nvim_get_current_buf()

  child.cmd('terminal! bash --noprofile --norc')
  -- Wait for terminal to get active
  vim.uv.sleep(term_mode_wait)
  validate_statusline(0, 'active')
  eq(child.api.nvim_get_current_buf() == init_buf_id, false)

  type_keys('i', 'exit', '<CR>')
  vim.uv.sleep(term_mode_wait)
  type_keys('<CR>')
  validate_statusline(0, 'active')
  eq(child.api.nvim_get_current_buf() == init_buf_id, true)
end

T['setup()']['ensures content when buffer is displayed in non-current window'] = function()
  local init_win_id = child.api.nvim_get_current_win()
  local buf_id = child.api.nvim_create_buf(false, true)

  -- Normal window
  child.cmd('leftabove vertical split')
  local new_win_id = child.api.nvim_get_current_win()
  child.api.nvim_set_current_win(init_win_id)
  child.api.nvim_win_set_buf(new_win_id, buf_id)
  validate_statusline(init_win_id, 'active')

  -- Floating window
  child.api.nvim_open_win(buf_id, false, { relative = 'editor', row = 1, col = 1, height = 4, width = 10 })
  validate_statusline(init_win_id, 'active')
end

T['setup()']['handles `laststatus=3`'] = function()
  -- Should set same active content for all windows
  child.o.laststatus = 3
  local init_win_id = child.api.nvim_get_current_win()
  child.cmd('leftabove vertical split')
  local new_win_id = child.api.nvim_get_current_win()
  validate_statusline(init_win_id, 'active')
  validate_statusline(new_win_id, 'active')

  child.cmd('wincmd w')
  validate_statusline(init_win_id, 'active')
  validate_statusline(new_win_id, 'active')
end

T['combine_groups()'] = new_set()

local combine_groups = function(...) return child.lua_get('MiniStatusline.combine_groups(...)', { ... }) end

local example_groups = {
  { hl = 'AA', strings = { 'a1', 'a2' } },
  { hl = 'BB', strings = { 'b1', '', 'b2' } },
  '%=',
  { hl = 'CC', strings = { 'c1' } },
}

T['combine_groups()']['works'] = function() eq(combine_groups(example_groups), '%#AA# a1 a2 %#BB# b1 b2 %=%#CC# c1 ') end

T['combine_groups()']['handles non-table elements'] = function()
  -- Strings should be used as is, other non-table elements - filtered out
  eq(combine_groups({ 1, 'xxx', example_groups[1] }), 'xxx%#AA# a1 a2 ')
  eq(combine_groups({ example_groups[1], 'xxx' }), '%#AA# a1 a2 xxx')
  eq(combine_groups({ 'xxx', 'yyy' }), 'xxxyyy')
end

T['combine_groups()']['uses only non-empty strings from `strings` field'] = function()
  eq(combine_groups({ { hl = 'AA', strings = { 'a', 1, {}, true, '', 'b' } } }), '%#AA# a b ')
end

T['combine_groups()']['allows empty `hl` to use previous highlight group'] = function()
  eq(combine_groups({ { strings = { 'a' } }, { hl = 'BB', strings = { 'b' } } }), ' a %#BB# b ')
  eq(combine_groups({ { hl = 'BB', strings = { 'b' } }, { strings = { 'a' } } }), '%#BB# b  a ')
end

T['combine_groups()']['allows empty `strings` to start new highlight'] = function()
  eq(combine_groups({ { hl = 'AA' }, { strings = { 'b1', 'b2' } } }), '%#AA# b1 b2 ')
  eq(combine_groups({ { hl = 'AA' }, { hl = 'BB', strings = { 'b1', 'b2' } } }), '%#AA#%#BB# b1 b2 ')
  eq(combine_groups({ { strings = { 'a1', 'a2' } }, { hl = 'BB' }, { strings = { 'c1' } } }), ' a1 a2 %#BB# c1 ')
end

local is_truncated = function(...) return child.lua_get('MiniStatusline.is_truncated(...)', { ... }) end

T['is_truncated()'] = new_set()

T['is_truncated()']['works'] = function()
  child.cmd('wincmd v')
  set_width(50)

  -- Should return `false` ("not trauncated") by default
  eq(is_truncated(), false)

  eq(is_truncated(49), false)
  eq(is_truncated(50), false)
  eq(is_truncated(51), true)
end

T['is_truncated()']['respects global statusline'] = function()
  child.o.laststatus = 3
  child.o.columns = 60
  child.cmd('wincmd v')
  set_width(50)

  eq(is_truncated(51), false)
  eq(is_truncated(59), false)
  eq(is_truncated(60), false)
  eq(is_truncated(61), true)
end

local eval_content = function(field) return child.lua_get(('MiniStatusline.%s()'):format(field)) end

T['active()/inactive()'] = new_set({
  parametrize = { { 'active' }, { 'inactive' } },
})

T['active()/inactive()']['respects `config.content`'] = function(field)
  unload_module()
  local command =
    string.format([[require('mini.statusline').setup({ content = { %s = function() return 'aaa' end } })]], field)
  child.lua(command)
  eq(eval_content(field), 'aaa')

  command = string.format([[vim.b.ministatusline_config = { content = { %s = function() return 'bbb' end } }]], field)
  child.lua(command)
  eq(eval_content(field), 'bbb')
end

T['active()/inactive()']['respects `vim.{g,b}.ministatusline_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(field, var_type)
    child[var_type].ministatusline_disable = true
    eq(eval_content(field), '')
  end,
})

-- Sections -------------------------------------------------------------------
T['section_diagnostics()'] = new_set({ hooks = { pre_case = mock_diagnostics } })

T['section_diagnostics()']['works'] = function()
  local get_n_attached_clients = function()
    return child.lua([[
      return vim.fn.has('nvim-0.10') == 1 and #vim.lsp.get_clients({ bufnr = 0 }) or
      #vim.lsp.get_active_clients({ bufnr = 0 })
    ]])
  end
  eq(child.lua_get('MiniStatusline.section_diagnostics({})'), ' E4 W3 I2 H1')

  -- Should not depend on LSP server attached
  mock_lsp()
  eq(get_n_attached_clients(), 1)
  eq(child.lua_get('MiniStatusline.section_diagnostics({})'), ' E4 W3 I2 H1')

  child.lua('vim.lsp.buf_detach_client(0, _G.months_lsp_client_id)')
  eq(get_n_attached_clients(), 0)
  eq(child.lua_get('MiniStatusline.section_diagnostics({})'), ' E4 W3 I2 H1')

  -- Should use cache on `DiagnosticChanged`
  child.cmd('enew')
  eq(child.lua_get('MiniStatusline.section_diagnostics({})'), '')
  child.cmd('doautocmd DiagnosticChanged')
  eq(child.lua_get('MiniStatusline.section_diagnostics({})'), ' E4 W3 I2 H1')

  -- Should return empty string if no diagnostic entries is set
  child.cmd('buffer #')
  child.lua('vim.diagnostic.get = function(...) return {} end')
  child.lua('vim.diagnostic.count = function(...) return {} end')
  child.cmd('doautocmd DiagnosticChanged')
  eq(child.lua_get('MiniStatusline.section_diagnostics({})'), '')
end

T['section_diagnostics()']['respects `args.trunc_width`'] = function()
  set_width(100)
  eq(child.lua_get('MiniStatusline.section_diagnostics({ trunc_width = 100 })'), ' E4 W3 I2 H1')
  set_width(99)
  eq(child.lua_get('MiniStatusline.section_diagnostics({ trunc_width = 100 })'), '')
end

T['section_diagnostics()']['respects `args.icon`'] = function()
  eq(child.lua_get([[MiniStatusline.section_diagnostics({icon = 'A'})]]), 'A E4 W3 I2 H1')
  eq(child.lua_get([[MiniStatusline.section_diagnostics({icon = 'AAA'})]]), 'AAA E4 W3 I2 H1')
end

T['section_diagnostics()']['respects `args.signs`'] = function()
  local out = child.lua_get(
    [[MiniStatusline.section_diagnostics({ signs = { ERROR = '!', WARN = '?', INFO = '@', HINT = '*' } })]]
  )
  eq(out, ' !4 ?3 @2 *1')
end

T['section_diagnostics()']['respects `config.use_icons`'] = function()
  child.lua('MiniStatusline.config.use_icons = false')
  eq(child.lua_get([[MiniStatusline.section_diagnostics({})]]), 'Diag E4 W3 I2 H1')

  -- Should also use buffer local config
  child.b.ministatusline_config = { use_icons = true }
  eq(child.lua_get([[MiniStatusline.section_diagnostics({})]]), ' E4 W3 I2 H1')
end

T['section_diagnostics()']['works in not normal buffers'] = function()
  -- Should return empty string if there is no diagnostic defined
  child.cmd('help')
  child.cmd('doautocmd DiagnosticChanged')
  eq(child.lua_get('MiniStatusline.section_diagnostics({})'), ' E4 W3 I2 H1')

  child.lua('vim.diagnostic.get = function(...) return {} end')
  child.lua('vim.diagnostic.count = function(...) return {} end')
  child.cmd('doautocmd DiagnosticChanged')
  eq(child.lua_get('MiniStatusline.section_diagnostics({})'), '')
end

T['section_diagnostics()']['is not shown if diagnostics is disabled'] = function()
  local buf_id = child.api.nvim_get_current_buf()
  if child.fn.has('nvim-0.10') == 1 then
    child.diagnostic.enable(false, { bufnr = buf_id })
  else
    child.diagnostic.disable(buf_id)
  end
  eq(child.lua_get('MiniStatusline.section_diagnostics({})'), '')
end

T['section_lsp()'] = new_set({ hooks = { pre_case = mock_lsp } })

T['section_lsp()']['works'] = function()
  eq(child.lua_get('MiniStatusline.section_lsp({})'), '󰰎 +')

  -- Should show number of attached LSP servers
  child.cmd('luafile tests/mock-lsp/fruits.lua')
  eq(child.lua_get('MiniStatusline.section_lsp({})'), '󰰎 ++')

  -- Should work if attached buffer clients is returned not as array
  child.lua('vim.lsp.buf_detach_client(0, _G.months_lsp_client_id)')
  eq(child.lua_get('MiniStatusline.section_lsp({})'), '󰰎 +')

  -- Should show empty string if no attached LSP servers
  child.lua('vim.lsp.buf_detach_client(0, _G.fruits_lsp_client_id)')
  eq(child.lua_get('MiniStatusline.section_lsp({})'), '')
end

T['section_lsp()']['respects `args.trunc_width`'] = function()
  set_width(100)
  eq(child.lua_get('MiniStatusline.section_lsp({ trunc_width = 100 })'), '󰰎 +')
  set_width(99)
  eq(child.lua_get('MiniStatusline.section_lsp({ trunc_width = 100 })'), '')
end

T['section_lsp()']['respects `args.icon`'] = function()
  eq(child.lua_get('MiniStatusline.section_lsp({icon = "A"})'), 'A +')
  eq(child.lua_get('MiniStatusline.section_lsp({icon = "AAA"})'), 'AAA +')
end

T['section_lsp()']['respects `config.use_icons`'] = function()
  child.lua('MiniStatusline.config.use_icons = false')
  eq(child.lua_get('MiniStatusline.section_lsp({})'), 'LSP +')

  -- Should also use buffer local config
  child.b.ministatusline_config = { use_icons = true }
  eq(child.lua_get('MiniStatusline.section_lsp({})'), '󰰎 +')
end

T['section_fileinfo()'] = new_set({ hooks = { pre_case = mock_miniicons } })

local validate_fileinfo = function(args, pattern)
  local command = ('MiniStatusline.section_fileinfo({ %s })'):format(args)
  expect.match(child.lua_get(command), pattern)
end

T['section_fileinfo()']['works'] = function()
  mock_buffer_size(10)
  child.bo.filetype = 'text'
  local encoding = child.bo.fileencoding or child.bo.encoding
  local format = child.bo.fileformat
  local pattern = '^󰦪 text ' .. vim.pesc(encoding) .. '%[' .. vim.pesc(format) .. '%] 10B$'
  validate_fileinfo('', pattern)
end

T['section_fileinfo()']['respects `args.trunc_width`'] = function()
  mock_buffer_size(10)
  child.bo.filetype = 'text'

  set_width(100)
  validate_fileinfo('trunc_width = 100', '^󰦪 text...')
  set_width(99)
  validate_fileinfo('trunc_width = 100', '^󰦪 text$')
end

T['section_fileinfo()']['respects `config.use_icons`'] = function()
  mock_buffer_size(10)
  child.bo.filetype = 'text'

  child.lua('MiniStatusline.config.use_icons = false')
  validate_fileinfo('', '^text...')

  -- Should also use buffer local config
  child.b.ministatusline_config = { use_icons = true }
  validate_fileinfo('', '󰦪 text...')
end

T['section_fileinfo()']["can fall back to 'nvim-web-devicons'"] = function()
  child.lua('_G.MiniIcons = nil')
  reload_module()

  -- Mock 'nvim-web-devicons'
  child.cmd('set rtp+=tests/dir-statusline')

  child.cmd('e tmp.txt')
  validate_fileinfo('', ' text...')
end

T['section_fileinfo()']['uses correct filetype'] = function()
  child.bo.filetype = 'aaa'
  validate_fileinfo('', ' aaa ')
end

T['section_fileinfo()']['shows correct size'] = function()
  -- Should show '0 bytes' on empty buffer
  validate_fileinfo('', '0B')

  -- Should update based on current text (not saved version)
  mock_buffer_size(10)
  validate_fileinfo('', '10B')

  type_keys('i', 'xxx')
  validate_fileinfo('', '13B')

  -- Should show human friendly size version
  mock_buffer_size(1024)
  validate_fileinfo('', '1%.00KiB$')

  mock_buffer_size(1024 * 1024)
  validate_fileinfo('', '1%.00MiB$')
end

T['section_fileinfo()']['works in special buffers'] = function()
  local fileformat = helpers.is_windows() and 'dos' or 'unix'

  -- Should treat normal buffer with empty filetype as failed filetype match
  validate_fileinfo('', '^%[' .. fileformat .. '%] 0B$')

  child.bo.filetype = 'aaa'
  validate_fileinfo('', '^󰈔 aaa %[' .. fileformat .. '%] 0B$')

  -- Should show only filetype for not normal buffers
  child.cmd('help')
  validate_fileinfo('', '^󰋖 help$')
end

T['section_filename()'] = new_set()

T['section_filename()']['works'] = function()
  local name = vim.fn.tempname()
  child.cmd('edit ' .. name)
  eq(child.lua_get('MiniStatusline.section_filename({})'), '%F%m%r')

  -- Should work in terminal
  child.cmd('terminal')
  eq(child.lua_get('MiniStatusline.section_filename({})'), '%t')
end

T['section_filename()']['respects `args.trunc_width`'] = function()
  local name = vim.fn.tempname()
  child.cmd('edit ' .. name)

  set_width(100)
  eq(child.lua_get('MiniStatusline.section_filename({ trunc_width = 100 })'), '%F%m%r')
  set_width(99)
  eq(child.lua_get('MiniStatusline.section_filename({ trunc_width = 100 })'), '%f%m%r')
end

T['section_git()'] = new_set({ hooks = { pre_case = mock_minigit } })

T['section_git()']['works'] = function()
  eq(child.lua_get('MiniStatusline.section_git({})'), ' main|bisect (MM)')

  -- Should return non-empty string even if there is no branch
  child.b.minigit_summary_string = ''
  eq(child.lua_get('MiniStatusline.section_git({})'), ' -')

  -- Should return empty string if no Git data is found
  child.b.minigit_summary_string = nil
  eq(child.lua_get('MiniStatusline.section_git({})'), '')
end

T['section_git()']["falls back to 'gitsigns.nvim'"] = function()
  child.b.minigit_summary_string = nil
  mock_gitsigns()

  eq(child.lua_get('MiniStatusline.section_git({})'), ' main')

  -- Should return non-empty string even if there is no branch
  child.b.gitsigns_head = ''
  eq(child.lua_get('MiniStatusline.section_git({})'), ' -')

  -- Should return empty string if no Git data is found
  child.b.gitsigns_head = nil
  eq(child.lua_get('MiniStatusline.section_git({})'), '')
end

T['section_git()']['respects `args.trunc_width`'] = function()
  set_width(100)
  eq(child.lua_get('MiniStatusline.section_git({ trunc_width = 100 })'), ' main|bisect (MM)')
  set_width(99)
  eq(child.lua_get('MiniStatusline.section_git({ trunc_width = 100 })'), '')
end

T['section_git()']['respects `args.icon`'] = function()
  eq(child.lua_get([[MiniStatusline.section_git({ icon = 'A' })]]), 'A main|bisect (MM)')
  eq(child.lua_get([[MiniStatusline.section_git({ icon = 'AAA' })]]), 'AAA main|bisect (MM)')
end

T['section_git()']['respects `config.use_icons`'] = function()
  child.lua('MiniStatusline.config.use_icons = false')
  eq(child.lua_get([[MiniStatusline.section_git({})]]), 'Git main|bisect (MM)')

  -- Should also use buffer local config
  child.b.ministatusline_config = { use_icons = true }
  eq(child.lua_get([[MiniStatusline.section_git({})]]), ' main|bisect (MM)')
end

T['section_diff()'] = new_set({ hooks = { pre_case = mock_minidiff } })

T['section_diff()']['works'] = function()
  eq(child.lua_get('MiniStatusline.section_diff({})'), ' #4 +3 ~2 -1')

  -- Should return non-empty string even if there is no branch
  child.b.minidiff_summary_string = ''
  eq(child.lua_get('MiniStatusline.section_diff({})'), ' -')

  -- Should return empty string if no Git data is found
  child.b.minidiff_summary_string = nil
  eq(child.lua_get('MiniStatusline.section_diff({})'), '')
end

T['section_diff()']["falls back to 'gitsigns.nvim'"] = function()
  child.b.minidiff_summary_string = nil
  mock_gitsigns()

  eq(child.lua_get('MiniStatusline.section_diff({})'), ' +1 ~2 -3')

  -- Should return non-empty string even if there is no branch
  child.b.gitsigns_status = ''
  eq(child.lua_get('MiniStatusline.section_diff({})'), ' -')

  -- Should return empty string if no Git data is found
  child.b.gitsigns_status = nil
  eq(child.lua_get('MiniStatusline.section_diff({})'), '')
end

T['section_diff()']['respects `args.trunc_width`'] = function()
  set_width(100)
  eq(child.lua_get('MiniStatusline.section_diff({ trunc_width = 100 })'), ' #4 +3 ~2 -1')
  set_width(99)
  eq(child.lua_get('MiniStatusline.section_diff({ trunc_width = 100 })'), '')
end

T['section_diff()']['respects `args.icon`'] = function()
  eq(child.lua_get([[MiniStatusline.section_diff({ icon = 'A' })]]), 'A #4 +3 ~2 -1')
  eq(child.lua_get([[MiniStatusline.section_diff({ icon = 'AAA' })]]), 'AAA #4 +3 ~2 -1')
end

T['section_diff()']['respects `config.use_icons`'] = function()
  child.lua('MiniStatusline.config.use_icons = false')
  eq(child.lua_get([[MiniStatusline.section_diff({})]]), 'Diff #4 +3 ~2 -1')

  -- Should also use buffer local config
  child.b.ministatusline_config = { use_icons = true }
  eq(child.lua_get([[MiniStatusline.section_diff({})]]), ' #4 +3 ~2 -1')
end

T['section_location()'] = new_set()

T['section_location()']['works'] = function()
  eq(child.lua_get('MiniStatusline.section_location({})'), '%l|%L│%2v|%-2{virtcol("$") - 1}')
end

T['section_location()']['respects `args.trunc_width`'] = function()
  set_width(100)
  eq(child.lua_get('MiniStatusline.section_location({ trunc_width = 100 })'), '%l|%L│%2v|%-2{virtcol("$") - 1}')
  set_width(99)
  eq(child.lua_get('MiniStatusline.section_location({ trunc_width = 100 })'), '%l│%2v')
end

T['section_mode()'] = new_set()

local section_mode = function(args) return child.lua_get('{ MiniStatusline.section_mode(...) }', { args or {} }) end

T['section_mode()']['works'] = function() eq(section_mode(), { 'Normal', 'MiniStatuslineModeNormal' }) end

T['section_mode()']['shows correct mode'] = function()
  local validate = function(output)
    eq(section_mode(), output)
    child.ensure_normal_mode()
  end

  child.cmd('startinsert')
  validate({ 'Insert', 'MiniStatuslineModeInsert' })

  type_keys('v')
  validate({ 'Visual', 'MiniStatuslineModeVisual' })

  type_keys('V')
  validate({ 'V-Line', 'MiniStatuslineModeVisual' })

  type_keys('<C-V>')
  validate({ 'V-Block', 'MiniStatuslineModeVisual' })

  type_keys(':')
  validate({ 'Command', 'MiniStatuslineModeCommand' })

  type_keys('R')
  validate({ 'Replace', 'MiniStatuslineModeReplace' })

  child.cmd('terminal')
  child.cmd('startinsert')
  validate({ 'Terminal', 'MiniStatuslineModeOther' })
end

T['section_mode()']['respects `args.trunc_width`'] = function()
  set_width(100)
  eq(section_mode({ trunc_width = 100 }), { 'Normal', 'MiniStatuslineModeNormal' })
  set_width(99)
  eq(section_mode({ trunc_width = 100 }), { 'N', 'MiniStatuslineModeNormal' })
end

T['section_searchcount()'] = new_set({ hooks = { pre_case = function() mock_buffer_size(10) end } })

local section_searchcount = function(args)
  return child.lua_get('MiniStatusline.section_searchcount(...)', { args or {} })
end

T['section_searchcount()']['works'] = function()
  set_lines({ '', 'a a a ' })

  -- Shows nothing if search is not initiated
  eq(section_searchcount(), '')

  type_keys('/', 'a', '<CR>')
  set_cursor(1, 0)
  eq(section_searchcount(), '0/3')

  set_cursor(2, 0)
  eq(section_searchcount(), '1/3')

  set_cursor(2, 1)
  eq(section_searchcount(), '1/3')

  set_cursor(2, 5)
  eq(section_searchcount(), '3/3')
end

T['section_searchcount()']['works with many search matches'] = function()
  local maxcount = child.fn.has('nvim-0.12') == 1 and 999 or 99
  local args = { options = { timeout = 15 * small_time } }

  set_lines({ string.rep('a ', maxcount + 2) })
  type_keys('/', 'a', '<CR>')
  set_cursor(1, 0)

  eq(section_searchcount(args), '1/>' .. maxcount)

  set_cursor(1, maxcount * 2 - 1)
  eq(section_searchcount(args), maxcount .. '/>' .. maxcount)

  set_cursor(1, maxcount * 2)
  eq(section_searchcount(args), '>' .. maxcount .. '/>' .. maxcount)
end

T['section_searchcount()']['respects `args.trunc_width`'] = function()
  set_lines({ '', 'a a a ' })
  type_keys('/', 'a', '<CR>')
  set_cursor(1, 0)

  set_width(100)
  eq(section_searchcount({ trunc_width = 100 }), '0/3')
  set_width(99)
  eq(section_searchcount({ trunc_width = 100 }), '')
end

T['section_searchcount()']['respects `args.options`'] = function()
  -- Disable recomputation from section in default content
  child.lua([[MiniStatusline.config.content.active = function() return '%f' end]])
  set_lines({ '', 'a a a ' })
  type_keys('/', 'a', '<CR>')

  eq(section_searchcount({ options = { recompute = false } }), '1/3')
  set_cursor(2, 5)
  eq(section_searchcount({ options = { recompute = false } }), '1/3')
end

T['section_searchcount()']['does not fail on `searchcount()` error'] = function()
  -- This matters because it is assumed that `section_searchcount` will be
  -- called on every statusline update, which will happen during typing `/\(`
  -- to search for something like `\(\)`.
  child.fn.setreg('/', [[\(]])
  expect.no_error(section_searchcount)
end

-- Integration tests ==========================================================
T['Default content'] = new_set()

T['Default content']['active'] = new_set({
  hooks = {
    pre_case = function()
      child.set_size(5, 160)

      child.lua('require("mini.icons").setup()')
      child.cmd('edit tests/dir-statusline/mocked.lua')
      child.bo.fileencoding = 'utf-8'
      mock_buffer_size(10)

      -- Mock filename section to use relative path for consistent screenshots
      child.lua([[MiniStatusline.section_filename = function() return '%f%m%r' end]])
      mock_diagnostics()
      mock_lsp()
      mock_minigit()
      mock_minidiff()
      type_keys('/a', '<CR>')
    end,
  },
  -- There should also be test for 140, but it is for truncating in
  -- `section_filename` from full to relative paths
  parametrize = { { 120 }, { 75 }, { 40 }, { 39 } },
}, {
  test = function(window_width)
    helpers.skip_on_windows('Windows has different default path separator')

    validate_statusline(0, 'active')
    set_width(window_width)
    child.expect_screenshot()
  end,
})

T['Default content']['inactive'] = function()
  eq(child.lua_get('MiniStatusline.inactive()'), '%#MiniStatuslineInactive#%F%=')
end

T['Default content']['inactive is evaluated in the context of its window'] = function()
  child.set_size(10, 30)
  child.lua([[
    local f = function() return vim.api.nvim_get_current_win() end
    MiniStatusline.config.content = { active = f, inactive = f }
  ]])
  child.cmd('wincmd =')
  child.cmd('redraw!')
  child.expect_screenshot()
  eq(child.api.nvim_get_current_win(), 1001)
end

return T
