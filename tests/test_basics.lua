local helpers = dofile('tests/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('basics', config) end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
--stylua: ignore end

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = child.setup,
    post_once = child.stop,
  },
  n_retry = helpers.get_n_retry(1),
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  load_module()

  -- Global variable
  eq(child.lua_get('type(_G.MiniBasics)'), 'table')
end

T['setup()']['creates `config` field'] = function()
  load_module()

  eq(child.lua_get('type(_G.MiniBasics.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniBasics.config.' .. field), value) end

  -- Check default values
  expect_config('options.basic', true)
  expect_config('options.extra_ui', false)
  expect_config('options.win_borders', 'auto')
  expect_config('mappings.basic', true)
  expect_config('mappings.option_toggle_prefix', [[\]])
  expect_config('mappings.windows', false)
  expect_config('mappings.move_with_alt', false)
  expect_config('autocommands.basic', true)
  expect_config('autocommands.relnum_in_visual_mode', false)
  expect_config('silent', false)
end

T['setup()']['respects `config` argument'] = function()
  load_module({ options = { basic = false } })
  eq(child.lua_get('MiniBasics.config.options.basic'), false)
end

T['setup()']['validates `config` argument'] = function()
  local expect_config_error = function(config, name, target_type)
    expect.error(load_module, vim.pesc(name) .. '.*' .. vim.pesc(target_type), config)
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ options = 'a' }, 'options', 'table')
  expect_config_error({ options = { basic = 1 } }, 'options.basic', 'boolean')
  expect_config_error({ options = { extra_ui = 1 } }, 'options.extra_ui', 'boolean')
  expect_config_error({ options = { win_borders = 1 } }, 'options.win_borders', 'string')
  expect_config_error({ mappings = 'a' }, 'mappings', 'table')
  expect_config_error({ mappings = { basic = 1 } }, 'mappings.basic', 'boolean')
  expect_config_error({ mappings = { option_toggle_prefix = 1 } }, 'mappings.option_toggle_prefix', 'string')
  expect_config_error({ mappings = { windows = 1 } }, 'mappings.windows', 'boolean')
  expect_config_error({ mappings = { move_with_alt = 1 } }, 'mappings.move_with_alt', 'boolean')
  expect_config_error({ autocommands = 'a' }, 'autocommands', 'table')
  expect_config_error({ autocommands = { basic = 1 } }, 'autocommands.basic', 'boolean')
  expect_config_error({ autocommands = { relnum_in_visual_mode = 1 } }, 'autocommands.relnum_in_visual_mode', 'boolean')
  expect_config_error({ silent = 'a' }, 'silent', 'boolean')
end

T['toggle_diagnostic()'] = new_set()

local toggle_diagnostic = function() return child.lua_get('MiniBasics.toggle_diagnostic()') end

T['toggle_diagnostic()']['works'] = function()
  if child.fn.has('nvim-0.10') == 1 then
    child.lua('vim.diagnostic.enable = function(enable) vim.b.diag_status = enable and "enabled" or "disabled" end')
    child.lua('vim.diagnostic.is_enabled = function(enable) return vim.b.diag_status ~= "disabled" end')
  else
    child.lua('vim.diagnostic.enable = function() vim.b.diag_status = "enabled" end')
    child.lua('vim.diagnostic.disable = function() vim.b.diag_status = "disabled" end')
    child.lua('vim.diagnostic.is_disabled = function() return vim.b.diag_status == "disabled" end')
  end

  load_module()

  -- Should disable on per-buffer basis
  local buf_id_one = child.api.nvim_get_current_buf()
  local buf_id_two = child.api.nvim_create_buf(true, false)

  child.api.nvim_set_current_buf(buf_id_one)
  eq(child.b.diag_status, vim.NIL)
  eq(toggle_diagnostic(), 'nodiagnostic')
  eq(child.b.diag_status, 'disabled')

  child.api.nvim_set_current_buf(buf_id_two)
  eq(child.b.diag_status, vim.NIL)
  eq(toggle_diagnostic(), 'nodiagnostic')
  eq(child.b.diag_status, 'disabled')

  child.api.nvim_set_current_buf(buf_id_one)
  eq(child.b.diag_status, 'disabled')
  eq(toggle_diagnostic(), '  diagnostic')
  eq(child.b.diag_status, 'enabled')

  child.api.nvim_set_current_buf(buf_id_two)
  eq(child.b.diag_status, 'disabled')
  eq(toggle_diagnostic(), '  diagnostic')
  eq(child.b.diag_status, 'enabled')
end

T['toggle_diagnostic()']['works if initially disabled'] = function()
  load_module()
  local buf_id = child.api.nvim_get_current_buf()

  local disable, is_disabled
  if child.fn.has('nvim-0.10') == 1 then
    disable = function() child.diagnostic.enable(false, { bufnr = buf_id }) end
    is_disabled = function() return not child.diagnostic.is_enabled({ bufnr = buf_id }) end
  else
    disable = function() child.diagnostic.disable(buf_id) end
    is_disabled = function() return child.diagnostic.is_disabled(buf_id) end
  end

  disable()
  eq(is_disabled(), true)
  toggle_diagnostic()
  eq(is_disabled(), false)
  toggle_diagnostic()
  eq(is_disabled(), true)
end

-- Integration tests ==========================================================
T['Options'] = new_set()

T['Options']['work'] = function()
  -- Basic options (should be set by default)
  eq(child.g.mapleader, vim.NIL)
  eq(child.o.number, false)
  eq(child.o.signcolumn, 'auto')
  eq(child.o.fillchars, '')

  -- Extra options (should not be set by default)
  eq(child.o.pumblend, 0)

  load_module()

  eq(child.g.mapleader, ' ')
  eq(child.o.number, true)
  eq(child.o.signcolumn, 'yes')
  eq(child.o.fillchars, 'eob: ')

  eq(child.o.pumblend, 0)
end

T['Options']['do not override manually set options'] = function()
  -- Shouldn't modify options manually set to non-default value
  child.g.mapleader = ';'
  child.cmd('set signcolumn=no')
  child.cmd('set pumblend=50')

  -- Shouldn't modify option manually set to default value
  child.cmd('set nonumber')
  child.cmd('set nolist')

  load_module({ options = { basic = true, extra_ui = true } })

  eq(child.g.mapleader, ';')
  eq(child.o.signcolumn, 'no')
  eq(child.o.pumblend, 50)
  eq(child.o.number, false)
  eq(child.o.list, false)
end

T['Options']['respect `config.options.basic`'] = function()
  eq(child.g.mapleader, vim.NIL)
  local tgc = child.o.termguicolors
  eq(child.o.number, false)
  eq(child.o.signcolumn, 'auto')

  load_module({ options = { basic = false } })

  eq(child.g.mapleader, vim.NIL)
  eq(child.o.termguicolors, tgc)
  eq(child.o.number, false)
  eq(child.o.signcolumn, 'auto')
end

T['Options']['respect `config.options.extra_ui`'] = function()
  eq(child.o.pumblend, 0)
  eq(child.o.list, false)

  load_module({ options = { extra_ui = true } })

  eq(child.o.pumblend, 10)
  eq(child.o.list, true)

  -- 'listchars' should have `tab` defined to not show `^I` instead of tab
  expect.match(child.o.listchars, 'tab')
end

T['Options']['respect `config.options.win_borders`'] = function()
  local validate = function(opt_value, ref_fillchars)
    child.o.fillchars = ''
    load_module({ options = { basic = false, win_borders = opt_value } })
    eq(child.o.fillchars, ref_fillchars)
  end

  validate(nil, '')
  validate('double', 'horiz:═,horizdown:╦,horizup:╩,msgsep:═,vert:║,verthoriz:╬,vertleft:╣,vertright:╠')
  -- - Should not respect 'winborder' style names directly
  validate('none', '')

  if child.fn.has('nvim-0.11') == 0 then return end

  -- With default 'auto' should infer from 'winborder' option
  local validate_winborder = function(winborder_value, ref_fillchars)
    child.o.winborder = winborder_value
    validate(nil, ref_fillchars)
    validate('auto', ref_fillchars)
  end

  validate_winborder('', '')

  local single_fcs = 'horiz:─,horizdown:┬,horizup:┴,msgsep:─,vert:│,verthoriz:┼,vertleft:┤,vertright:├'
  validate_winborder('single', single_fcs)
  validate_winborder('rounded', single_fcs)

  local solid_fcs = 'horiz: ,horizdown: ,horizup: ,msgsep: ,vert: ,verthoriz: ,vertleft: ,vertright: '
  validate_winborder('solid', solid_fcs)
  validate_winborder('none', solid_fcs)
  validate_winborder('shadow', solid_fcs)

  if child.fn.has('nvim-0.12') == 0 then return end

  -- With custom list 'winborder' should do nothing
  validate_winborder('+,-,+,|,+,-,+,|', '')
end

T['Mappings'] = new_set()

T['Mappings']['work'] = function()
  expect.match(child.cmd_capture('nmap go'), 'No mapping')

  load_module()

  expect.match(child.cmd_capture('nmap go'), 'MiniBasics')
end

T['Mappings']['do not override manually created mappings'] = function()
  child.api.nvim_set_keymap('n', 'j', 'aaaaa', { noremap = true })
  child.api.nvim_set_keymap('n', ',s', 'bbbbb', { noremap = true })
  child.lua([[vim.keymap.set('n', '<C-l>', function() end, { desc = 'Test' })]])
  child.api.nvim_set_keymap('i', '<M-h>', 'ddddd', { noremap = true })

  load_module({ mappings = { basic = true, option_toggle_prefix = ',', windows = true, move_with_alt = true } })

  expect.match(child.cmd_capture('nmap j'), 'aaaaa')
  expect.match(child.cmd_capture('nmap ,s'), 'bbbbb')
  expect.match(child.cmd_capture('nmap <C-l>'), 'Test')
  expect.match(child.cmd_capture('imap <M-h>'), 'ddddd')
end

T['Mappings']['ignores buffer-local mappings when deciding whether to create one'] = function()
  child.api.nvim_buf_set_keymap(0, 'n', 'j', 'aaaaa', { noremap = true })
  child.api.nvim_buf_set_keymap(0, 'n', ',s', 'bbbbb', { noremap = true })
  child.api.nvim_buf_set_keymap(0, 'n', '<C-h>', 'ccccc', { noremap = true })
  child.api.nvim_buf_set_keymap(0, 'i', '<M-h>', 'ddddd', { noremap = true })

  load_module({ mappings = { basic = true, option_toggle_prefix = ',', windows = true, move_with_alt = true } })

  child.api.nvim_buf_del_keymap(0, 'n', 'j')
  child.api.nvim_buf_del_keymap(0, 'n', ',s')
  child.api.nvim_buf_del_keymap(0, 'n', '<C-h>')
  child.api.nvim_buf_del_keymap(0, 'i', '<M-h>')

  expect.match(child.cmd_capture('nmap j'), 'gj')
  expect.match(child.cmd_capture('nmap ,s'), 'spell')
  expect.match(child.cmd_capture('nmap <C-h>'), '<C%-W>')
  expect.match(child.cmd_capture('imap <M-h>'), '<Left>')
end

T['Mappings']['Basic'] = new_set()

T['Mappings']['Basic']['can be disabled'] = function()
  expect.match(child.cmd_capture('nmap go'), 'No mapping')

  load_module({ mappings = { basic = false } })

  expect.match(child.cmd_capture('nmap go'), 'No mapping')
end

T['Mappings']['Basic']['j/k'] = function()
  local validate = function()
    -- Goes by visible lines without `[count]`
    set_cursor(1, 0)
    type_keys('jj')
    eq(get_cursor(), { 1, 24 })
    type_keys('k')
    eq(get_cursor(), { 1, 12 })

    -- Goes by usual lines with `[count]`
    set_cursor(1, 0)
    type_keys('1j')
    eq(get_cursor(), { 2, 0 })
    type_keys('1k')
    eq(get_cursor(), { 1, 0 })
  end

  load_module()

  child.o.number = false
  child.o.signcolumn = 'no'
  child.o.wrap = true
  child.set_size(10, 12)
  set_lines({ string.rep('a', 48), 'bbb' })

  -- Normal mode
  child.ensure_normal_mode()
  validate()

  -- Visual mode
  set_cursor(1, 0)
  type_keys('v')
  eq(child.fn.mode(), 'v')
  child.ensure_normal_mode()
end

T['Mappings']['Basic']['go'] = function()
  load_module()

  -- Should add empty line(s) below with cursor staying on line
  set_lines({ 'aaa' })
  set_cursor(1, 1)

  type_keys('go')
  eq(get_lines(), { 'aaa', '' })
  eq(get_cursor(), { 1, 1 })

  -- Should respect `[count]`
  type_keys('2go')
  eq(get_lines(), { 'aaa', '', '', '' })
  eq(get_cursor(), { 1, 1 })

  -- Should work with dot-repeat
  type_keys('.')
  eq(get_lines(), { 'aaa', '', '', '', '', '' })
  eq(get_cursor(), { 1, 1 })

  -- Should allow different `v:count` in dot-repeat
  type_keys('1.')
  eq(get_lines(), { 'aaa', '', '', '', '', '', '' })
  eq(get_cursor(), { 1, 1 })
end

T['Mappings']['Basic']['gO'] = function()
  load_module()

  -- Should add empty line(s) above with cursor staying on line
  set_lines({ 'aaa' })
  set_cursor(1, 1)

  type_keys('gO')
  eq(get_lines(), { '', 'aaa' })
  eq(get_cursor(), { 2, 1 })

  -- Should respect `[count]`
  type_keys('2gO')
  eq(get_lines(), { '', '', '', 'aaa' })
  eq(get_cursor(), { 4, 1 })

  -- Should work with dot-repeat
  type_keys('.')
  eq(get_lines(), { '', '', '', '', '', 'aaa' })
  eq(get_cursor(), { 6, 1 })

  -- Should allow different `v:count` in dot-repeat
  type_keys('1.')
  eq(get_lines(), { '', '', '', '', '', '', 'aaa' })
  eq(get_cursor(), { 7, 1 })
end

T['Mappings']['Basic']['gy'] = function()
  load_module()
  eq(child.fn.maparg('gy', 'n'), '"+y')
  eq(child.fn.maparg('gy', 'x'), '"+y')
end

T['Mappings']['Basic']['gp'] = function()
  load_module()

  -- Has problems with CI testing, so test mapping themselves. Should be enough
  -- as they are quite basic.
  local created_mappings = {}

  local normal_keymaps = child.api.nvim_get_keymap('n')
  for _, keymap in ipairs(normal_keymaps) do
    if keymap.lhs == 'gy' then
      table.insert(created_mappings, 'n_gy')
      eq(keymap.rhs, '"+y')
    end
    if keymap.lhs == 'gp' then
      table.insert(created_mappings, 'n_gp')
      eq(keymap.rhs, '"+p')
    end
  end

  local visual_keymaps = child.api.nvim_get_keymap('x')
  for _, keymap in ipairs(visual_keymaps) do
    if keymap.lhs == 'gy' then
      table.insert(created_mappings, 'x_gy')
      eq(keymap.rhs, '"+y')
    end
    if keymap.lhs == 'gp' then
      table.insert(created_mappings, 'x_gp')
      -- Should use `P` to not cut visual selection in `""` register
      eq(keymap.rhs, '"+P')
    end
  end

  table.sort(created_mappings)
  eq(created_mappings, { 'n_gp', 'n_gy', 'x_gp', 'x_gy' })
end

T['Mappings']['Basic']['gV'] = function()
  local validate_cur_selection = function(ref_selection)
    eq({ { child.fn.line('v'), child.fn.col('v') }, { child.fn.line('.'), child.fn.col('.') } }, ref_selection)
  end
  load_module()

  -- Should reselect previously pasted or yanked text

  -- Charwise mode
  set_lines({ 'aaa', 'bbb', 'ccc' })
  set_cursor(1, 0)
  type_keys('yiw')
  set_cursor(2, 0)
  type_keys('P')

  -- - Result selection should not depend on latest Visual selection type
  set_cursor(1, 0)
  type_keys('V', '<Esc>')

  type_keys('gV')
  validate_cur_selection({ { 2, 1 }, { 2, 3 } })
  eq(child.fn.mode(), 'v')

  child.ensure_normal_mode()

  -- Linewise mode
  set_lines({ 'aaa', 'bbb', 'ccc' })
  set_cursor(1, 0)
  type_keys('yy', 'p')
  -- - Add location to the jumplist
  type_keys('gg')

  -- - Result selection should not depend on latest Visual selection type
  set_cursor(1, 0)
  type_keys('viw', '<Esc>')

  type_keys('gV')
  validate_cur_selection({ { 2, 1 }, { 2, 3 } })
  eq(child.fn.mode(), 'V')

  child.ensure_normal_mode()

  -- - Selection should not have overwritten jumplist
  type_keys('<C-o>')
  eq(get_cursor(), { 1, 0 })

  -- Blockwise mode
  set_lines({ 'aaa', 'bbb', 'ccc' })
  set_cursor(1, 0)
  type_keys('<C-v>ly')
  set_cursor(2, 0)
  type_keys('P')

  -- - Result selection should not depend on latest Visual selection type
  set_cursor(1, 0)
  type_keys('viw', '<Esc>')

  type_keys('gV')
  validate_cur_selection({ { 2, 1 }, { 2, 2 } })
  eq(child.fn.mode(), '\22')
end

T['Mappings']['Basic']['g/'] = function()
  load_module()

  -- Should search inside visual selection
  set_lines({ 'abc', 'abc', 'abc' })
  set_cursor(1, 0)
  type_keys('Vj', 'g/', 'a<CR>')

  eq(get_cursor(), { 1, 0 })
  type_keys('n')
  eq(get_cursor(), { 2, 0 })
  -- Should not recognize match outside visual selection
  type_keys('n')
  eq(get_cursor(), { 1, 0 })
end

T['Mappings']['Basic']['*/#'] = function()
  load_module()

  -- Should work just like in Normal mode but for visual selection and even
  -- with bad characters present

  -- *
  set_lines({ [[aa?/\bb]], 'aa', [[aa?/\bb]], 'aa', [[aa?/\bb]] })
  set_cursor(1, 0)
  type_keys('v$ho', '*')

  eq(get_cursor(), { 3, 0 })
  type_keys('n')
  eq(get_cursor(), { 5, 0 })
  type_keys('n')
  eq(get_cursor(), { 1, 0 })
  type_keys('n')
  eq(get_cursor(), { 3, 0 })

  child.cmd('nohlsearch')
  child.ensure_normal_mode()

  -- #
  set_lines({ [[aa?/\bb]], 'aa', [[aa?/\bb]], 'aa', [[aa?/\bb]] })
  set_cursor(1, 0)
  type_keys('v$ho', '#')

  eq(get_cursor(), { 5, 0 })
  type_keys('n')
  eq(get_cursor(), { 3, 0 })
  type_keys('n')
  eq(get_cursor(), { 1, 0 })
  type_keys('n')
  eq(get_cursor(), { 5, 0 })
end

T['Mappings']['Basic']['<C-s>'] = function()
  local test_file_path = 'tests/ctrl-s.txt'
  MiniTest.finally(function() child.fn.delete(test_file_path) end)

  load_module()

  child.cmd('write ' .. test_file_path)

  -- Should save in Normal mode
  eq(child.bo.modified, false)
  set_lines({ 'aaa' })
  eq(child.bo.modified, true)

  type_keys('<C-s>')
  eq(child.bo.modified, false)
  eq(child.fn.mode(), 'n')

  -- Should save in Insert mode and leave in Normal mode
  eq(child.bo.modified, false)
  set_lines({ 'aaa' })
  set_cursor(1, 0)
  child.cmd('startinsert')
  eq(child.bo.modified, true)
  eq(child.fn.mode(), 'i')

  type_keys('<C-s>')
  eq(child.bo.modified, false)
  eq(child.fn.mode(), 'n')

  -- Should save in Visual mode and leave in Normal mode
  eq(child.bo.modified, false)
  set_lines({ 'aaa' })
  set_cursor(1, 0)
  type_keys('v')
  eq(child.bo.modified, true)
  eq(child.fn.mode(), 'v')

  type_keys('<C-s>')
  eq(child.bo.modified, false)
  eq(child.fn.mode(), 'n')
end

T['Mappings']['Toggle options'] = new_set()

T['Mappings']['Toggle options']['work'] = function()
  -- NOTE: these mappings should also give feedback about new option values.
  -- But there doesn't seem to be a way of testing it without screenshots.
  -- So later test only for 'spell'.
  local validate = function(keys, option, before, after)
    child.o[option] = before
    type_keys(keys)
    eq(child.o[option], after)
    type_keys(keys)
    eq(child.o[option], before)
  end

  child.g.mapleader = ' '
  load_module({ options = { basic = false } })

  validate([[\b]], 'background', 'dark', 'light')
  validate([[\c]], 'cursorline', false, true)
  validate([[\C]], 'cursorcolumn', false, true)
  -- \d should toggle diagnostic
  -- \h should almost toggle 'hlsearch'
  validate([[\i]], 'ignorecase', false, true)
  validate([[\l]], 'list', false, true)
  validate([[\n]], 'number', false, true)
  validate([[\r]], 'relativenumber', false, true)
  validate([[\s]], 'spell', false, true)
  validate([[\w]], 'wrap', true, false)
end

T['Mappings']['Toggle options']['shows feedback about new value'] = function()
  child.set_size(10, 20)
  load_module()
  type_keys([[\s]])
  child.expect_screenshot()
end

T['Mappings']['Toggle options']['works with diagnostic'] = function()
  if child.fn.has('nvim-0.10') == 1 then
    child.lua('vim.diagnostic.enable = function(enable) vim.b.diag_status = enable and "enabled" or "disabled" end')
    child.lua('vim.diagnostic.is_enabled = function(enable) return vim.b.diag_status ~= "disabled" end')
  else
    child.lua('vim.diagnostic.enable = function() vim.b.diag_status = "enabled" end')
    child.lua('vim.diagnostic.disable = function() vim.b.diag_status = "disabled" end')
    child.lua('vim.diagnostic.is_disabled = function() return vim.b.diag_status == "disabled" end')
  end

  load_module()

  -- Should disable on per-buffer basis
  local buf_id_one = child.api.nvim_get_current_buf()
  local buf_id_two = child.api.nvim_create_buf(true, false)

  child.api.nvim_set_current_buf(buf_id_one)
  eq(child.b.diag_status, vim.NIL)
  type_keys([[\d]])
  eq(child.b.diag_status, 'disabled')

  child.api.nvim_set_current_buf(buf_id_two)
  eq(child.b.diag_status, vim.NIL)
  type_keys([[\d]])
  eq(child.b.diag_status, 'disabled')

  child.api.nvim_set_current_buf(buf_id_one)
  eq(child.b.diag_status, 'disabled')
  type_keys([[\d]])
  eq(child.b.diag_status, 'enabled')

  child.api.nvim_set_current_buf(buf_id_two)
  eq(child.b.diag_status, 'disabled')
  type_keys([[\d]])
  eq(child.b.diag_status, 'enabled')
end

T['Mappings']['Toggle options']["does not disables 'hlsearch' directly"] = function()
  load_module()

  set_lines({ 'abc', 'abc' })

  eq(child.o.hlsearch, true)
  type_keys('/', 'a', '<CR>')
  eq(child.o.hlsearch, true)
  type_keys([[\h]])
  eq(child.o.hlsearch, true)
  eq(child.v.hlsearch, 0)

  -- Typing `n` should still show matches
  type_keys('n')
  eq(child.o.hlsearch, true)
  eq(child.v.hlsearch, 1)
end

T['Mappings']['Toggle options']['can be disabled'] = function()
  expect.match(child.cmd_capture([[nmap \w]]), 'No mapping')

  load_module({ mappings = { option_toggle_prefix = '' } })

  expect.match(child.cmd_capture([[nmap \w]]), 'No mapping')
end

T['Mappings']['Toggle options']['can work with `<Leader>`'] = function()
  vim.g.mapleader = ' '
  load_module({ mappings = { option_toggle_prefix = '<Leader>t' } })

  expect.match(child.cmd_capture([[nmap <Space>tw]]), 'wrap')
end

T['Mappings']['Toggle options']['respects `config.silent`'] = function()
  child.set_size(10, 20)

  load_module({ silent = true })
  type_keys([[\s]])
  child.expect_screenshot()
end

T['Mappings']['Windows'] = new_set()

T['Mappings']['Windows']['work for common navigation'] = function()
  local validate_cur_win = function(x) eq(child.api.nvim_get_current_win(), x) end

  load_module({ options = { basic = false }, mappings = { windows = true } })

  child.cmd('wincmd v | wincmd s | wincmd s')

  validate_cur_win(1003)
  type_keys('<C-l>')
  validate_cur_win(1000)
  type_keys('<C-h>')
  validate_cur_win(1003)
  type_keys('<C-j>')
  validate_cur_win(1002)
  type_keys('<C-k>')
  validate_cur_win(1003)

  -- Works with `[count]`
  type_keys('2<C-j>')
  validate_cur_win(1001)
end

T['Mappings']['Windows']['work for resizing'] = function()
  local validate = function(dims) eq({ child.fn.winheight(0), child.fn.winwidth(0) }, dims) end

  load_module({ options = { basic = false }, mappings = { windows = true } })

  child.cmd('wincmd v | wincmd s')

  -- Should change correct dimension and respect `[count]`
  local start_height, start_width = child.fn.winheight(0), child.fn.winwidth(0)

  type_keys('<C-left>')
  validate({ start_height, start_width - 1 })
  type_keys('2<C-left>')
  validate({ start_height, start_width - 3 })

  type_keys('<C-right>')
  validate({ start_height, start_width - 2 })
  type_keys('2<C-right>')
  validate({ start_height, start_width })

  type_keys('<C-down>')
  validate({ start_height - 1, start_width })
  type_keys('2<C-down>')
  validate({ start_height - 3, start_width })

  type_keys('<C-up>')
  validate({ start_height - 2, start_width })
  type_keys('2<C-up>')
  validate({ start_height, start_width })
end

T['Mappings']['Move with alt'] = new_set()

T['Mappings']['Move with alt']['works in Insert mode'] = function()
  load_module({ mappings = { move_with_alt = true } })

  set_lines({ 'aaa', 'bbb' })
  set_cursor(1, 1)
  type_keys('a')

  eq(get_cursor(), { 1, 2 })
  type_keys('<M-h>')
  eq(get_cursor(), { 1, 1 })
  type_keys('<M-l>')
  eq(get_cursor(), { 1, 2 })
  type_keys('<M-j>')
  eq(get_cursor(), { 2, 2 })
  type_keys('<M-k>')
  eq(get_cursor(), { 1, 2 })
end

T['Mappings']['Move with alt']['works in Terminal mode'] = function()
  load_module({ mappings = { move_with_alt = true } })

  -- Too unstable to actually verify in Terminal mode
  expect.match(child.cmd_capture('tmap <M-h>'), '<Left>')
  expect.match(child.cmd_capture('tmap <M-j>'), '<Down>')
  expect.match(child.cmd_capture('tmap <M-k>'), '<Up>')
  expect.match(child.cmd_capture('tmap <M-l>'), '<Right>')
end

T['Mappings']['Move with alt']['works in Insert mode'] = function()
  load_module({ mappings = { move_with_alt = true } })

  type_keys(':hello')

  eq(child.fn.getcmdpos(), 6)
  type_keys('<M-h>')
  eq(child.fn.getcmdpos(), 5)
  type_keys('<M-l>')
  eq(child.fn.getcmdpos(), 6)
end

T['Autocommands'] = new_set()

T['Autocommands']['work'] = function()
  child.lua([[
    local on_yank = function() _G.been_here = true end
    local module = vim.fn.has('nvim-0.11') == 1 and vim.hl or vim.highlight
    module.on_yank = on_yank
  ]])
  load_module()

  -- Highlight on yank
  set_lines({ 'aaa' })
  type_keys('yiw')
  eq(child.lua_get('_G.been_here'), true)

  -- Start terminal in Insert mode
  child.cmd('terminal')
  eq(child.fn.mode(), 't')
end

T['Autocommands']['starts Terminal mode only in proper terminals'] = function()
  load_module()
  child.api.nvim_open_term(0, {})
  eq(child.fn.mode(), 'n')
end

T['Autocommands']['start Terminal mode only if target terminal is current'] = function()
  load_module()

  local init_buf_id = child.api.nvim_get_current_buf()
  child.lua([[vim.api.nvim_buf_call(vim.api.nvim_create_buf(true, false), function() vim.cmd('terminal') end)]])

  eq(child.api.nvim_get_current_buf(), init_buf_id)
  eq(child.fn.mode(), 'n')
end

T['Autocommands']['can be disabled'] = function()
  load_module({ autocommands = { basic = false } })
  child.cmd('terminal')
  eq(child.fn.mode(), 'n')
end

T['Autocommands']['respects `config.autocommands.relnum_in_visual_mode`'] = function()
  eq(child.o.relativenumber, false)
  type_keys('V')
  eq(child.o.relativenumber, false)
  type_keys('<C-v>')
  eq(child.o.relativenumber, false)
  type_keys('<Esc>')
  eq(child.o.relativenumber, false)

  load_module({ autocommands = { relnum_in_visual_mode = true } })

  eq(child.o.relativenumber, false)
  type_keys('V')
  eq(child.o.relativenumber, true)
  type_keys('<C-v>')
  eq(child.o.relativenumber, true)
  type_keys('<Esc>')
  eq(child.o.relativenumber, false)
end

return T
