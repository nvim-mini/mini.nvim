local helpers = dofile('tests/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
local load_module = function(config) child.mini_load('basics', config) end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end

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
  expect_config('mappings.search', false)
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
    expect.error(function() load_module(config) end, vim.pesc(name) .. '.*' .. vim.pesc(target_type))
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
  expect_config_error({ mappings = { search = 1 } }, 'mappings.search', 'boolean')
  expect_config_error({ autocommands = 'a' }, 'autocommands', 'table')
  expect_config_error({ autocommands = { basic = 1 } }, 'autocommands.basic', 'boolean')
  expect_config_error({ autocommands = { relnum_in_visual_mode = 1 } }, 'autocommands.relnum_in_visual_mode', 'boolean')
  expect_config_error({ silent = 'a' }, 'silent', 'boolean')
end

T['toggle_diagnostic()'] = new_set()

local toggle_diagnostic = function() return child.lua_get('MiniBasics.toggle_diagnostic()') end

T['toggle_diagnostic()']['works'] = function()
  child.lua('vim.diagnostic.enable = function(enable) vim.b.diag_status = enable and "enabled" or "disabled" end')
  child.lua('vim.diagnostic.is_enabled = function(enable) return vim.b.diag_status ~= "disabled" end')
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
  local is_disabled = function() return not child.diagnostic.is_enabled({ bufnr = 0 }) end

  child.diagnostic.enable(false, { bufnr = 0 })
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
  child.cmd('nnoremap n nzvzz')

  local mappings = { basic = true, option_toggle_prefix = ',', windows = true, move_with_alt = true, search = true }
  load_module({ mappings = mappings })

  expect.match(child.cmd_capture('nmap j'), 'aaaaa')
  expect.match(child.cmd_capture('nmap ,s'), 'bbbbb')
  expect.match(child.cmd_capture('nmap <C-l>'), 'Test')
  expect.match(child.cmd_capture('imap <M-h>'), 'ddddd')
  expect.match(child.cmd_capture('nmap n'), 'nzvzz')
end

T['Mappings']['ignores buffer-local mappings when deciding whether to create one'] = function()
  child.api.nvim_buf_set_keymap(0, 'n', 'j', 'aaaaa', { noremap = true })
  child.api.nvim_buf_set_keymap(0, 'n', ',s', 'bbbbb', { noremap = true })
  child.api.nvim_buf_set_keymap(0, 'n', '<C-h>', 'ccccc', { noremap = true })
  child.api.nvim_buf_set_keymap(0, 'i', '<M-h>', 'ddddd', { noremap = true })
  child.api.nvim_buf_set_keymap(0, 'n', 'n', 'nzvzz', { noremap = true })

  local mappings = { basic = true, option_toggle_prefix = ',', windows = true, move_with_alt = true, search = true }
  load_module({ mappings = mappings })

  child.api.nvim_buf_del_keymap(0, 'n', 'j')
  child.api.nvim_buf_del_keymap(0, 'n', ',s')
  child.api.nvim_buf_del_keymap(0, 'n', '<C-h>')
  child.api.nvim_buf_del_keymap(0, 'i', '<M-h>')
  child.api.nvim_buf_del_keymap(0, 'n', 'n')

  expect.match(child.cmd_capture('nmap j'), 'gj')
  expect.match(child.cmd_capture('nmap ,s'), 'spell')
  expect.match(child.cmd_capture('nmap <C-h>'), '<C%-W>')
  expect.match(child.cmd_capture('imap <M-h>'), '<Left>')
  expect.match(child.cmd_capture('nmap n'), 'Search forward')
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

  -- Works with multicursor
  if child.fn.has('nvim-0.13') == 1 then
    local lines_before = { string.rep('a', 48), string.rep('b', 48) }
    child.validate_mc_edit(lines_before, { 1, 0 }, { 'QG0q=', 'j' }, lines_before, { 2, 12 }, { { 1, 12 } })
    local lines_after = { string.rep('A', 13) .. string.rep('a', 35), string.rep('B', 13) .. string.rep('b', 35) }
    child.validate_mc_edit(lines_before, { 1, 0 }, { 'QG0', 'vj', 'gU' }, lines_after, { 2, 0 }, { { 1, 0 } })

    -- TODO: Test `zq` when it works with Lua RHS and/or `<Cmd>...<CR>`
  end
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
  type_keys({ '1', '.' })
  eq(get_lines(), { 'aaa', '', '', '', '', '', '' })
  eq(get_cursor(), { 1, 1 })

  -- Works with multicursor
  if child.fn.has('nvim-0.13') == 1 then
    local before, after = { 'aaa', 'bbb' }, { 'aaa', '', '', 'bbb', '', '' }
    child.validate_mc_edit(before, { 1, 0 }, { 'Qj', 'go', '.' }, after, { 4, 0 }, { { 1, 0 } })
    child.validate_mc_edit(before, { 1, 0 }, { 'QjQ', 'go', '.' }, after, { 4, 0 }, { { 1, 0 }, { 4, 0 } })
    child.validate_mc_edit(before, { 1, 0 }, { 'Qjq=', 'go', '.' }, after, { 4, 0 }, { { 1, 0 } })
    child.validate_mc_edit(before, { 1, 0 }, { 'QjQq=', 'go', '.' }, after, { 4, 0 }, { { 1, 0 }, { 4, 0 } })
  end
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
  type_keys({ '1', '.' })
  eq(get_lines(), { '', '', '', '', '', '', 'aaa' })
  eq(get_cursor(), { 7, 1 })

  -- Works with multicursor
  if child.fn.has('nvim-0.13') == 1 then
    local before, after = { 'aaa', 'bbb' }, { '', '', 'aaa', '', '', 'bbb' }
    child.validate_mc_edit(before, { 1, 0 }, { 'Qj', 'gO', '.' }, after, { 6, 0 }, { { 3, 0 } })
    child.validate_mc_edit(before, { 1, 0 }, { 'QjQ', 'gO', '.' }, after, { 6, 0 }, { { 3, 0 }, { 6, 0 } })
    child.validate_mc_edit(before, { 1, 0 }, { 'Qjq=', 'gO', '.' }, after, { 6, 0 }, { { 3, 0 } })
    child.validate_mc_edit(before, { 1, 0 }, { 'QjQq=', 'gO', '.' }, after, { 6, 0 }, { { 3, 0 }, { 6, 0 } })
  end
end

T['Mappings']['Basic']['gy/gY'] = function()
  load_module()
  eq(child.fn.maparg('gy', 'n'), '"+y')
  eq(child.fn.maparg('gy', 'x'), '"+y')
  eq(child.fn.maparg('gY', 'n'), '"+y$')
  -- There should be no Visual mode mapping to align with `:h Y-default`
  eq(child.fn.maparg('gY', 'x'), '')
end

T['Mappings']['Basic']['gp/gP'] = function()
  load_module()

  -- Has problems with CI testing, so test mapping themselves. Should be enough
  -- as they are quite basic.
  local created_mappings = {}

  local normal_keymaps = child.api.nvim_get_keymap('n')
  for _, keymap in ipairs(normal_keymaps) do
    if keymap.lhs == 'gP' then
      table.insert(created_mappings, 'n_gP')
      eq(keymap.rhs, '"+P')
    end
    if keymap.lhs == 'gp' then
      table.insert(created_mappings, 'n_gp')
      eq(keymap.rhs, '"+p')
    end
  end

  local visual_keymaps = child.api.nvim_get_keymap('x')
  for _, keymap in ipairs(visual_keymaps) do
    if keymap.lhs == 'gP' then
      table.insert(created_mappings, 'x_gP')
      eq(keymap.rhs, '"+P')
    end
    if keymap.lhs == 'gp' then
      table.insert(created_mappings, 'x_gp')
      -- Should use `P` to not cut visual selection in `""` register
      eq(keymap.rhs, '"+P')
    end
  end

  table.sort(created_mappings)
  eq(created_mappings, { 'n_gP', 'n_gp', 'x_gP', 'x_gp' })
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

T['Mappings']['Basic']['<C-c>'] = function()
  child.set_size(10, 20)
  load_module()
  child.o.cursorline = false
  child.o.number = false
  child.o.laststatus = 0

  set_lines({ 'aaa', 'bbb', 'bbb' })
  child.cmd('echo "Hello!"')
  if child.fn.has('nvim-0.13') == 1 then type_keys('Q') end
  type_keys('/', 'bbb', '<CR>')

  eq(child.v.hlsearch, 1)
  type_keys('<C-c>')
  child.expect_screenshot()
  eq(child.cmd_capture('messages'), '')
  eq(child.v.hlsearch, 0)
  if child.fn.has('nvim-0.13') == 1 then eq(child.get_multicursor(), {}) end

  -- Should actually disable hlsearch and not toggle it
  type_keys('<C-c>')
  eq(child.v.hlsearch, 0)
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
  child.lua('vim.diagnostic.enable = function(enable) vim.b.diag_status = enable and "enabled" or "disabled" end')
  child.lua('vim.diagnostic.is_enabled = function(enable) return vim.b.diag_status ~= "disabled" end')
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

  -- Works with multicursor
  if child.fn.has('nvim-0.13') == 1 then
    local lines = { 'aaa', 'bbb', 'ccc', 'ddd' }
    child.validate_mc_edit(lines, { 2, 1 }, { 'Qjq=', 'i', '<M-h>' }, lines, { 3, 0 }, { { 2, 0 } })
    child.validate_mc_edit(lines, { 2, 1 }, { 'Qjq=', 'i', '<M-l>' }, lines, { 3, 2 }, { { 2, 2 } })
    child.validate_mc_edit(lines, { 2, 1 }, { 'Qjq=', 'i', '<M-j>' }, lines, { 4, 1 }, { { 3, 1 } })
    child.validate_mc_edit(lines, { 2, 1 }, { 'Qjq=', 'i', '<M-k>' }, lines, { 2, 1 }, { { 1, 1 } })
  end
end

T['Mappings']['Move with alt']['works in Terminal mode'] = function()
  load_module({ mappings = { move_with_alt = true } })

  -- Too unstable to actually verify in Terminal mode
  expect.match(child.cmd_capture('tmap <M-h>'), '<Left>')
  expect.match(child.cmd_capture('tmap <M-j>'), '<Down>')
  expect.match(child.cmd_capture('tmap <M-k>'), '<Up>')
  expect.match(child.cmd_capture('tmap <M-l>'), '<Right>')
end

T['Mappings']['Move with alt']['works in Command-line mode'] = function()
  load_module({ mappings = { move_with_alt = true } })

  type_keys(':hello')

  eq(child.fn.getcmdpos(), 6)
  type_keys('<M-h>')
  eq(child.fn.getcmdpos(), 5)
  type_keys('<M-l>')
  eq(child.fn.getcmdpos(), 6)
end

T['Mappings']['Search'] = new_set({
  hooks = {
    pre_case = function()
      -- Watch specific search `v:` variables to test that this is possible
      child.cmd([[
        lua _G.n_hlsearch = 0
        function! WatchHlsearch(d,k,z)
          lua _G.n_hlsearch = _G.n_hlsearch + 1
        endfunction
        call dictwatcheradd(v:, 'hlsearch', 'WatchHlsearch')

        lua _G.n_searchforward = 0
        function! WatchSearchforward(d,k,z)
          lua _G.n_searchforward = _G.n_searchforward + 1
        endfunction
        call dictwatcheradd(v:, 'searchforward', 'WatchSearchforward')
      ]])

      -- Mock constant clipboard for better reproducibility of system registers
      -- (mostly on CI).
      child.lua([[
        local empty = function() return {} end
        vim.g.clipboard = {
          name  = 'myClipboard',
          copy  = { ['+'] = empty, ['*'] = empty },
          paste = { ['+'] = empty, ['*'] = empty },
        }
      ]])
    end,
  },
})

T['Mappings']['Search']['n/N'] = function()
  load_module({ mappings = { search = true } })

  set_lines({ 'aa', 'bb', 'aa', 'cc', 'aa' })
  type_keys('/aa', '<CR>')
  child.cmd('nohlsearch')

  local validate = function(init_keys, key, lnum_arr)
    set_cursor(1, 0)
    if init_keys ~= '' then type_keys(init_keys) end
    local mode = child.fn.mode()

    local n_hlsearch = child.lua_get('_G.n_hlsearch')
    eq(child.v.hlsearch, 0)
    for _, lnum in ipairs(lnum_arr) do
      type_keys(key)
      eq(get_cursor(), { lnum, 0 })
      eq(child.fn.mode(), mode)
    end

    -- Should set correct variables
    eq(child.v.hlsearch, 1)

    -- Should be possible to watch necessary `v:` variables and
    -- they should be set only if was different initially
    eq(child.lua_get('_G.n_hlsearch'), n_hlsearch + 1)

    -- Clean up
    child.cmd('nohlsearch')
    child.ensure_normal_mode()
  end

  -- Normal mode
  validate('', 'n', { 3, 5, 1 })
  validate('', 'N', { 5, 3, 1 })

  -- Visual mode
  validate('v', 'n', { 3, 5, 1 })
  validate('v', 'N', { 5, 3, 1 })

  -- Operator-pending mode
  local validate_op = function(key)
    set_lines({ 'aa 1', 'bb', 'aa 2', 'cc', 'aa 3' })
    set_cursor(3, 0)
    local n_hlsearch = child.lua_get('_G.n_hlsearch')
    type_keys('d', key, key == 'n' and 'gg' or 'G', 'd', key)
    eq(get_lines(), { 'aa 3' })
    eq(child.v.hlsearch, 1)
    eq(child.lua_get('_G.n_hlsearch'), n_hlsearch + 1)
    child.cmd('nohlsearch')
  end

  validate_op('n')
  validate_op('N')

  -- Should open just enough folds
  set_lines({ 'aa', '  aa', '  bb', '    aa', '    bb', '  aa', '  bb', 'aa' })
  child.wo.foldmethod = 'indent'
  child.bo.expandtab = true
  child.bo.shiftwidth = 2
  local validate_fold_open = function(key, ref_lnum)
    type_keys('zM')
    for lnum, lnum_end in ipairs({ -1, 7, 7, 7, 7, 7, 7, -1 }) do
      eq(child.fn.foldclosedend(lnum), lnum_end)
    end
    set_cursor(key == 'n' and 1 or 8, 0)
    type_keys(key)
    eq(get_cursor(), { ref_lnum, 2 })
    for lnum, lnum_end in ipairs({ -1, -1, -1, 5, 5, -1, -1, -1 }) do
      eq(child.fn.foldclosedend(lnum), lnum_end)
    end
  end

  validate_fold_open('n', 2)
  validate_fold_open('N', 6)

  set_cursor(1, 0)
  type_keys('n')

  -- Should work with multicursor
  if child.fn.has('nvim-0.13') == 1 then
    set_lines({ 'aa', 'aa' })
    set_cursor(1, 0)
    type_keys('zq', 'n')
    eq(child.get_multicursor(), { { 1, 0 }, { 2, 0 } })
    child.clear_multicursor()
  end
end

T['Mappings']['Search']['*/#'] = function()
  load_module({ mappings = { search = true } })

  set_lines({ [[aa?/\bb]], 'aa', [[aa?/\bb]], 'aa', [[aa?/\bb]], 'aa', [[aa?/\bb XX]] })
  child.fn.setreg('"', 'xxx')

  local get_nonsearch_registers = function() return child.cmd_capture('registers'):gsub('\n%s+c%s+"/.+$', '') end

  local validate_line_traversal = function(key, lnum_arr)
    for _, lnum in ipairs(lnum_arr) do
      type_keys(key)
      eq(get_cursor(), { lnum, 0 })
    end
  end

  local validate = function(select_keys, search_key, lines_n, lines_N)
    local registers = get_nonsearch_registers()
    local n_hlsearch = child.lua_get('_G.n_hlsearch')
    local n_searchforward = child.lua_get('_G.n_searchforward')
    set_cursor(1, 0)
    if select_keys ~= '' then type_keys(select_keys) end
    local cursor = get_cursor()

    type_keys(search_key)

    -- Should initially not move cursor
    eq(get_cursor(), cursor)

    -- Should not modify any unwanted registers except `/` (for search)
    eq(get_nonsearch_registers(), registers)

    -- Should set correct variable values
    eq(child.v.hlsearch, 1)
    eq(child.v.searchforward, search_key == '*' and 1 or 0)

    -- Should be possible to watch necessary `v:` variables
    eq(child.lua_get('_G.n_hlsearch'), n_hlsearch + 1)
    eq(child.lua_get('_G.n_searchforward'), n_searchforward + 1)

    -- Should traverse in correct direction with `n` and `N`
    set_cursor(1, 0)
    validate_line_traversal('n', lines_n)
    set_cursor(1, 0)
    validate_line_traversal('N', lines_N)

    -- Should not have known side effects
    eq(child.g._minibasics, vim.NIL)
    eq(child.b._minibasics, vim.NIL)

    -- Clean up
    child.cmd('nohlsearch')
    child.ensure_normal_mode()
  end

  -- Normal mode
  validate('', '*', { 2, 3, 4, 5, 6, 7, 1 }, { 7, 6, 5, 4, 3, 2, 1 })
  validate('', '#', { 7, 6, 5, 4, 3, 2, 1 }, { 2, 3, 4, 5, 6, 7, 1 })
  -- - Should respect `'iskeyword'` and escape bad characters
  child.bo.iskeyword = child.bo.iskeyword .. ',?,/,\\'
  validate('', '*', { 3, 5, 7, 1 }, { 7, 5, 3, 1 })
  validate('', '#', { 7, 5, 3, 1 }, { 3, 5, 7, 1 })

  -- Visual mode
  validate('v$ho', '*', { 3, 5, 7, 1 }, { 7, 5, 3, 1 })
  -- - Order of region selection should not matter
  validate('$v0', '*', { 3, 5, 7, 1 }, { 7, 5, 3, 1 })
  -- - Should work with linewise selection
  validate('V', '*', { 3, 5, 1 }, { 5, 3, 1 })
  -- - Should work with multiline selection
  validate('vj', '*', { 3, 5, 1 }, { 5, 3, 1 })
  validate('Vj', '*', { 3, 5, 1 }, { 5, 3, 1 })

  validate('v$ho', '#', { 7, 5, 3, 1 }, { 3, 5, 7, 1 })
  validate('$v0', '#', { 7, 5, 3, 1 }, { 3, 5, 7, 1 })
  validate('V', '#', { 5, 3, 1 }, { 3, 5, 1 })
  validate('vj', '#', { 5, 3, 1 }, { 3, 5, 1 })
  validate('Vj', '#', { 5, 3, 1 }, { 3, 5, 1 })
end

T['Autocommands'] = new_set()

T['Autocommands']['work'] = function()
  child.lua([[
    local module = vim.fn.has('nvim-0.11') == 1 and vim.hl or vim.highlight
    local hl_op_name = vim.fn.has('nvim-0.13') == 1 and 'hl_op' or 'on_yank'
    module[hl_op_name] = function() _G.been_here = true end
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
