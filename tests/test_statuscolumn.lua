local helpers = dofile('tests/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('statuscolumn', config) end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local sleep = function(ms) helpers.sleep(ms, child) end
local forward_lua = function(fun_str) return helpers.forward_lua(child, fun_str) end
--stylua: ignore end

-- Tweak `expect_screenshot()` to ignore attributes on Neovim<0.11 as it has
-- different with highlights for signs in custom statuscolumn
child.expect_screenshot_orig = child.expect_screenshot
child.expect_screenshot = function(opts)
  if child.fn.has('nvim-0.10') == 0 then return end
  opts = opts or {}
  if opts.ignore_attr == nil then opts.ignore_attr = child.fn.has('nvim-0.11') == 0 end
  child.expect_screenshot_orig(opts)
end

-- Common test wrappers
local set_win_option = function(win_id, name, value)
  child.api.nvim_set_option_value(name, value, { scope = 'local', win = win_id })
end

local set_all_win_option = function(name, value)
  for _, win_id in ipairs(child.api.nvim_list_wins()) do
    set_win_option(win_id, name, value)
  end
end

local refresh_statuscolumn = function()
  -- Setting 'statuscolumn' re-computes it and possibly shrinks width
  for _, win_id in ipairs(child.api.nvim_list_wins()) do
    local cur = child.api.nvim_get_option_value('statuscolumn', { scope = 'local', win = win_id })
    set_win_option(win_id, 'statuscolumn', cur)
  end
end

local n_different_attr = 0
local set_unique_hl = function(hl_group)
  n_different_attr = n_different_attr + 1
  child.api.nvim_set_hl(0, hl_group, { fg = string.format('#%06x', n_different_attr) })
end

local set_statuscol_unique_hl = function()
  child.cmd('hi clear')
  n_different_attr = 0

  set_unique_hl('MiniStatuscolumnDim')
  set_unique_hl('MiniStatuscolumnDimCursor')
  set_unique_hl('MiniStatuscolumnSep')
  set_unique_hl('MiniStatuscolumnSepCursor')

  set_unique_hl('CursorLineFold')
  set_unique_hl('CursorLineNr')
  set_unique_hl('CursorLineSign')
  set_unique_hl('FoldColumn')
  set_unique_hl('LineNr')
  set_unique_hl('LineNrAbove')
  set_unique_hl('LineNrBelow')
  set_unique_hl('SignColumn')
end

local prepare_main_content_layout = function()
  -- Ensure visually distinctive highlight groups that are getting dimmed
  set_statuscol_unique_hl()

  child.o.foldmethod = 'manual'
  child.lua('_G.foldtext = function() return "+--" end')
  child.o.foldtext = 'v:lua.foldtext()'
  child.o.laststatus = 2
  child.o.statusline = '%{%nvim_get_current_win()==#g:actual_curwin ? "active" : "inactive"%}'
  child.o.wrap = true

  child.api.nvim_win_set_buf(0, child.api.nvim_create_buf(true, false))
  set_lines({ 'one', 'twoooooooooooo', 'cursor', 'fold1', 'fold2', 'six', 'sevennnnnnnnnn' })
  set_cursor(3, 0)

  child.cmd('4,5fold')

  local ns_id_sign = child.api.nvim_create_namespace('sign')
  child.api.nvim_buf_set_extmark(0, ns_id_sign, 0, 0, { sign_text = 'SA' })
  child.api.nvim_buf_set_extmark(0, ns_id_sign, 5, 0, { sign_text = 'SB' })

  local ns_id_virt_lines = child.api.nvim_create_namespace('virt_lines')
  local virt_lines = { { { 'VIR', 'String' } }, { { 'LINE', 'Function' } } }
  child.api.nvim_buf_set_extmark(0, ns_id_virt_lines, 1, 0, { virt_lines = virt_lines })
  child.api.nvim_buf_set_extmark(0, ns_id_virt_lines, 6, 0, { virt_lines = virt_lines })

  child.cmd('vsplit')
end

-- Time constants
local term_mode_wait = helpers.get_time_const(50)

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      load_module()

      -- Make screenshots more robust
      child.set_size(10, 20)
      child.o.laststatus = 0
      child.o.showtabline = 0
      child.o.winwidth = 1
      child.o.winminwidth = 1
    end,
    post_once = child.stop,
    n_retry = helpers.get_n_retry(1),
  },
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  -- Global variable
  eq(child.lua_get('type(_G.MiniStatuscolumn)'), 'table')

  -- Autocommand group
  eq(child.fn.exists('#MiniStatuscolumn'), 1)

  -- Highlight groups
  child.cmd('hi clear')
  child.api.nvim_set_hl(0, 'LineNr', { fg = '#AAAAAA', bg = '#111111' })
  load_module()
  local has_highlight = function(group, value) expect.match(child.cmd_capture('hi ' .. group), value) end

  has_highlight('MiniStatuscolumnDim', 'guifg=#4b4b4b guibg=#111111')
  has_highlight('MiniStatuscolumnDimCursor', 'links to MiniStatuscolumnDim')
  has_highlight('MiniStatuscolumnSep', 'links to LineNr')
  has_highlight('MiniStatuscolumnSepCursor', 'links to CursorLineNr')

  -- Sets custom 'statuscolumn'
  expect.no_equality(child.o.statuscolumn, '')
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniStatuscolumn.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniStatuscolumn.config.' .. field), value) end

  expect_config('content', {})
  expect_config('dim_inactive', true)
end

T['setup()']['validates `config` argument'] = function()
  local expect_config_error = function(config, name, target_type)
    expect.error(function() load_module(config) end, vim.pesc(name) .. '.*' .. vim.pesc(target_type))
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ content = 1 }, 'content', 'table')
  expect_config_error({ content = { active = 1 } }, 'content.active', 'function')
  expect_config_error({ content = { inactive = 1 } }, 'content.inactive', 'function')
  expect_config_error({ dim_inactive = 1 }, 'dim_inactive', 'boolean')
end

T['setup()']['ensures colors'] = function()
  child.cmd('colorscheme default')
  expect.match(child.cmd_capture('hi MiniStatuscolumnSep'), 'links to LineNr')
end

--stylua: ignore
T['setup()']['correctly computes dimmed highlight attributes'] = function()
  -- Should make effective foreground closer to the effective background.
  -- Should prefer attribute from `LineNr` with possible fall back to `Normal`.
  -- When not enough attribute info, should fall back to linkining to `LineNr`
  local validate = function(hl_linenr, hl_normal, hl_ref)
    child.cmd('hi clear')
    child.api.nvim_set_hl(0, 'LineNr', hl_linenr)
    child.api.nvim_set_hl(0, 'Normal', hl_normal)
    load_module()

    local ref = child.api.nvim_get_hl(0, { name = 'MiniStatuscolumnDim', link = true })
    if ref.fg then ref.fg = string.format('#%06x', ref.fg) end
    if ref.bg then ref.bg = string.format('#%06x', ref.bg) end
    eq(ref, hl_ref)
  end

  validate({ fg = '#656667', bg = '#010203' }, { fg = '#757677', bg = '#111213' }, { fg = '#272829', bg = '#010203' })
  validate({ fg = '#656667', bg = '#010203' }, { fg = '#757677',                }, { fg = '#272829', bg = '#010203' })
  validate({ fg = '#656667', bg = '#010203' }, {                 bg = '#111213' }, { fg = '#272829', bg = '#010203' })
  validate({ fg = '#656667', bg = '#010203' }, {                                }, { fg = '#272829', bg = '#010203' })

  validate({                 bg = '#010203' }, { fg = '#757677', bg = '#111213' }, { fg = '#2d2e2f', bg = '#010203' })
  validate({                 bg = '#010203' }, { fg = '#757677',                }, { fg = '#2d2e2f', bg = '#010203' })
  validate({                 bg = '#010203' }, {                 bg = '#111213' }, { link = 'LineNr' })
  validate({                 bg = '#010203' }, {                                }, { link = 'LineNr' })

  validate({ fg = '#656667',                }, { fg = '#757677', bg = '#111213' }, { fg = '#313233', bg = '#111213' })
  validate({ fg = '#656667',                }, { fg = '#757677',                }, { link = 'LineNr' })
  validate({ fg = '#656667',                }, {                 bg = '#111213' }, { fg = '#313233', bg = '#111213' })
  validate({ fg = '#656667',                }, {                                }, { link = 'LineNr' })

  validate({                                }, { fg = '#757677', bg = '#111213' }, { fg = '#373839', bg = '#111213' })
  validate({                                }, { fg = '#757677',                }, { link = 'LineNr' })
  validate({                                }, {                 bg = '#111213' }, { link = 'LineNr' })
  validate({                                }, {                                }, { link = 'LineNr' })

  -- Should recompute after changing color scheme
  child.cmd('hi clear')
  child.api.nvim_set_hl(0, 'LineNr', { fg = '#656565', bg = '#010101' })
  expect.match(child.cmd_capture('hi MiniStatuscolumnDim'), 'cleared')
  child.cmd('doautocmd ColorScheme')
  expect.match(child.cmd_capture('hi MiniStatuscolumnDim'), 'guifg=#272727 guibg=#010101')
end

T['setup()']['correctly infers missing content functions'] = function()
  child.lua('_G.wins = {}')
  child.lua('_G.content_fun = function(win_data) _G.wins[tostring(win_data.win_id)] = true end')
  local wins = { [tostring(child.api.nvim_get_current_win())] = true }
  child.cmd('vsplit')
  wins[tostring(child.api.nvim_get_current_win())] = true

  -- One missing function should be inferred as the other
  child.lua('require("mini.statuscolumn").setup({ content = { active = content_fun } })')
  child.lua('_G.wins = {}')
  child.cmd('redraw!')
  eq(child.lua_get('_G.wins'), wins)

  child.lua('require("mini.statuscolumn").setup({ content = { inactive = content_fun } })')
  child.lua('_G.wins = {}')
  child.cmd('redraw!')
  eq(child.lua_get('_G.wins'), wins)
end

T['gen_content'] = new_set()

T['gen_content']['main()'] = new_set({
  hooks = {
    pre_case = function()
      child.set_size(18, 25)
      child.o.number = true
      child.o.foldcolumn = '1'
      child.o.signcolumn = 'yes'
      prepare_main_content_layout()
    end,
  },
})

T['gen_content']['main()']['works'] = function()
  child.lua('MiniStatuscolumn.setup({ content = MiniStatuscolumn.gen_content.main() })')
  eq(child.lua_get('type(MiniStatuscolumn.config.content.active)'), 'function')
  eq(child.lua_get('type(MiniStatuscolumn.config.content.inactive)'), 'function')
  eq(child.o.statuscolumn == '', false)

  local validate = function(spec)
    child.lua('_G.spec = ' .. vim.inspect(spec))
    child.lua('MiniStatuscolumn.setup({ content = MiniStatuscolumn.gen_content.main(_G.spec) })')
    child.expect_screenshot()
  end

  -- By default should show the same content as the default statuscolumn
  validate()
  validate({})

  -- Should be possible to customize sections
  validate({ { sep = '/' } })

  -- Should correctly normalize specification: filter by coordinate field(s)
  -- (win, pos, ltype) and set info field(s) (format, fold, lnum, sign, sep)
  validate({
    { win = 'active', fold = 'x', lnum = 'l' },
    { win = 'inactive', fold = 'f' },
    { pos = 'above', lnum = 'a' },
    { pos = 'below', lnum = 'b' },
    { ltype = 'wrap', sign = '>' },
    -- Should treat several "coordinates" as "AND" filters
    { pos = 'below', ltype = 'virt', sign = '?' },
    { win = 'active', pos = 'cursor', ltype = 'wrap', sign = '#' },
    -- - Later entries should override previous ones (only newly supplied)
    { win = 'active', fold = 'F' },
  })

  -- Should allow not all sections in `format`
  validate({ { format = '=l' } })

  -- Should allow empty sections
  validate({ { win = 'inactive', fold = '', lnum = '', sign = '', sep = '' } })
end

T['gen_content']['main()']["respects 'cursorline'"] = function()
  -- Dedicated separator highlighting at cursor line should be applied only
  -- in cases described in `:h hl-CursorLineNr`. It should span across wrapped
  -- parts and line's virtual text.
  child.o.cursorline = true
  set_cursor(7, 0)
  child.lua('MiniStatuscolumn.setup({ content = MiniStatuscolumn.gen_content.main({ { sep = "|" } }) })')
  child.expect_screenshot()

  child.o.cursorlineopt = 'line'
  child.expect_screenshot()
end

T['gen_content']['main()']['highlights separator on cursor virtual lines'] = function()
  child.set_size(12, 15)
  child.cmd('%bwipeout! | mode')
  child.lua('MiniStatuscolumn.setup({ content = MiniStatuscolumn.gen_content.main({ { sep = "|" } }) })')

  child.o.cursorline = true
  child.o.number = true
  set_lines({ 'one', 'twoooooooo', 'three', 'four', 'five' })
  local ns_id = child.api.nvim_create_namespace('virt_lines')
  child.api.nvim_buf_set_extmark(0, ns_id, 1, 0, { virt_lines = { { { 'AAA', 'String' } } } })
  child.api.nvim_buf_set_extmark(0, ns_id, 2, 0, { virt_lines = { { { 'BBB', 'String' } } } })
  child.api.nvim_buf_set_extmark(0, ns_id, 3, 0, { virt_lines = { { { 'CCC', 'String' } } }, virt_lines_above = true })

  local validate_lnum = function(lnum)
    set_cursor(lnum, 0)
    child.expect_screenshot()
  end
  local validate = function()
    validate_lnum(2)
    validate_lnum(3)
    validate_lnum(4)
    validate_lnum(5)
    validate_lnum(4)
    validate_lnum(3)
    validate_lnum(2)
    validate_lnum(1)
  end

  -- Normal mode
  validate()

  -- Insert mode
  child.cmd('startinsert')
  validate()
end

T['gen_content']['main()']['respects `opts.click`'] = function()
  -- Make line number section narrower to overcome some performance trade-offs
  -- of 'statuscolumn' implementation when it comes to computing which areas
  -- are clickable. This makes section follow the following placements:
  -- fssllS (fold, sign, lnum, sep)
  child.o.numberwidth = 2
  child.lua([[
    _G.log = {}
    local click = function(...) table.insert(_G.log, { ... }) end
    local spec = { { sep = "|" }, { ltype = 'virt', lnum = '!' }, { ltype = 'wrap', lnum = '?' } }
    local content = MiniStatuscolumn.gen_content.main(spec, { click = click })
    MiniStatuscolumn.setup({ content = content })
  ]])

  local ref_data = {}
  local validate_single = function(button, action, modifier, row, col)
    child.api.nvim_input_mouse(button, action, modifier, 0, row, col)
    ref_data.mousepos = child.fn.getmousepos()
    eq(child.lua_get('_G.log'), { { ref_data } })
    child.lua('_G.log = {}')
  end

  local validate_line = function(lnum, ltype)
    lnum = lnum - 1
    -- NOTE: Neovim<0.13 had too much optimizations when it came to clickable
    -- areas. See: https://github.com/neovim/neovim/issues/40210
    if child.fn.has('nvim-0.13') == 0 then ltype = 'text' end
    ref_data = { button = 'l', modifiers = '    ', n_clicks = 1, ltype = ltype, section = 'fold' }
    validate_single('left', 'press', '', lnum, 0)

    ref_data.section = 'sign'
    validate_single('left', 'press', '', lnum, 1)
    -- NOTE: There doesn't seem to be a way to mock pressing with modifiers
    ref_data.button = 'r'
    validate_single('right', 'press', '', lnum, 2)
    ref_data.button = 'l'

    ref_data.section = 'lnum'
    validate_single('left', 'press', '', lnum, 3)

    ref_data.section = 'sep'
    validate_single('left', 'press', '', lnum, 4)
  end

  validate_line(1, 'text')
  validate_line(2, 'text')
  validate_line(3, 'wrap')
  validate_line(4, 'virt')
  validate_line(5, 'virt')

  -- Double click
  child.api.nvim_input_mouse('left', 'press', '', 0, 0, 0)
  child.api.nvim_input_mouse('left', 'press', '', 0, 0, 0)
  local mousepos = child.fn.getmousepos()
  local ref_log = {
    -- NOTE: It doesn't look right that both single and double clicks are
    -- recorded, but that is how it works in manual testing with real mouse.
    { { button = 'l', modifiers = '    ', mousepos = mousepos, n_clicks = 1, ltype = 'text', section = 'fold' } },
    { { button = 'l', modifiers = '    ', mousepos = mousepos, n_clicks = 2, ltype = 'text', section = 'fold' } },
  }
  eq(child.lua_get('_G.log'), ref_log)
end

T['gen_content']['main()']['validates input'] = function()
  local validate = function(spec, err_pattern)
    expect.error(
      function() child.lua('MiniStatuscolumn.gen_content.main(' .. vim.inspect(spec) .. ')') end,
      err_pattern
    )
  end

  validate('a', '`spec`.*array')
  validate({ 'a' }, '`spec` item.*table')
  validate({ { win = 'w' } }, '`spec%[1%]%.win`.*one of')
  validate({ { pos = 'p' } }, '`spec%[1%]%.pos`.*one of')
  validate({ { ltype = 'l' } }, '`spec%[1%]%.ltype`.*one of')

  validate({ { win = 'active', format = 1 } }, '`spec%[1%]%.format`.*string')
  validate({ { win = 'active', format = 'a' } }, '`spec%[1%]%.format`.*contain only')
  validate({ { win = 'active', fold = 1 } }, '`spec%[1%]%.fold`.*string')
  validate({ { win = 'active', lnum = 1 } }, '`spec%[1%]%.lnum`.*string')
  validate({ { win = 'active', sign = 1 } }, '`spec%[1%]%.sign`.*string')
  validate({ { win = 'active', sep = 1 } }, '`spec%[1%]%.sep`.*string')

  validate({ { win = 'active' } }, '`spec%[1%]`.*at least one info')
  validate({ { pos = 'cursor' } }, '`spec%[1%]`.*at least one info')
  validate({ { ltype = 'text' } }, '`spec%[1%]`.*at least one info')
  validate({ { win = 'active', pos = 'cursor', ltype = 'text' } }, '`spec%[1%]`.*at least one info')

  validate({ { win = 'active', fold = 'f' }, { win = 'w' } }, '`spec%[2%]%.win`.*one of')
  validate({ { win = 'active', fold = 'f' }, { win = 'inactive' } }, '`spec%[2%]`.*at least one info')
end

T['default_click()'] = new_set()

local default_click = forward_lua('MiniStatuscolumn.default_click')

T['default_click()']['works'] = function()
  child.set_size(10, 15)
  set_lines({ 'a', 'bb', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k' })
  set_cursor(1, 0)
  local win_id_other = child.api.nvim_get_current_win()
  child.cmd('vsplit')

  -- Should focus the target window and place cursor at the clicked line
  default_click({ mousepos = { winid = win_id_other, line = 2, column = 2 }, n_clicks = 1 })
  eq(child.api.nvim_get_current_win(), win_id_other)
  eq(get_cursor(), { 2, 1 })
  eq(child.fn.line('w0'), 1)

  -- Should center line on double click
  default_click({ mousepos = { winid = win_id_other, line = 6, column = 1 }, n_clicks = 2 })
  eq(get_cursor(), { 6, 0 })
  eq(child.fn.line('w0'), 2)
end

T['default_click()']['fails silently'] = function()
  local win_id = child.api.nvim_get_current_win()
  expect.no_error(function() default_click({ mousepos = { winid = -1, line = 1, column = 0 }, n_clicks = 1 }) end)
  expect.no_error(function() default_click({ mousepos = { winid = win_id, line = -1, column = 1 }, n_clicks = 1 }) end)
  expect.no_error(function() default_click({ mousepos = { winid = win_id, line = 1, column = -1 }, n_clicks = 1 }) end)
end

T['default_click()']['validates input'] = function()
  local validate = function(data, err_pattern)
    expect.error(function() default_click(data) end, err_pattern)
  end
  local win_id = child.api.nvim_get_current_win()

  validate(1, '`data`.*table')
  validate({ mousepos = 1 }, '`data%.mousepos`.*table')
  validate({ mousepos = { winid = 'a', line = 1, column = 1 }, n_clicks = 1 }, '`data%.mousepos%.winid`.*number')
  validate({ mousepos = { winid = win_id, line = 'a', column = 1 }, n_clicks = 1 }, '`data%.mousepos%.line`.*number')
  validate({ mousepos = { winid = win_id, line = 1, column = 'a' }, n_clicks = 1 }, '`data%.mousepos%.column`.*number')
  validate({ mousepos = { winid = win_id, line = 1, column = 1 }, n_clicks = 'a' }, '`data%.n_clicks`.*number')
end

-- Integration tests ==========================================================
local mock_dim_test_content = function()
  child.lua([[
    local make_content = function(win_type)
      return function()
        local is_cur = vim.v.relnum == 0
        local cur_lnum = vim.api.nvim_win_get_cursor(0)[1]

        local win = win_type == 'active' and 'a' or 'i'
        local pos = is_cur and 'c' or (vim.v.lnum < cur_lnum and 'a' or 'b')
        local ltype = vim.v.virtnum == 0 and 't' or (vim.v.virtnum < 0 and 'v' or 'w')

        local fold_hl = is_cur and 'CursorLineFold' or 'FoldColumn'
        local line_hl = is_cur and 'CursorLineNr' or (vim.v.lnum > 3 and 'LineNr' or (pos == 'a' and 'LineNrAbove' or 'LineNrBelow'))
        local sign_hl = is_cur and 'CursorLineSign' or 'SignColumn'
        local sep_hl  = is_cur and 'MiniStatuscolumnSepCursor' or 'MiniStatuscolumnSep'

        return string.format('%%#%s#%s%%#%s#%s%%#%s#%s%%#%s#|', fold_hl, win, line_hl, pos, sign_hl, ltype, sep_hl)
      end
    end
    require('mini.statuscolumn').setup({
      content = {
        active = make_content('active'),
        inactive = make_content('inactive'),
      },
    })
  ]])
end

T['Dim'] = new_set({
  hooks = {
    pre_case = function()
      child.set_size(10, 39)
      mock_dim_test_content()

      -- Prepare main buffer to show. Add reference highlight to check that the
      -- correct highlight group is used when dimming.
      set_lines({ 'uuu', 'vvv', 'www', 'xxxxxxxxx' })
      local ns_id = child.api.nvim_create_namespace('test')
      local dim_hl, dim_cur_hl = 'MiniStatuscolumnDim', 'MiniStatuscolumnDimCursor'
      child.api.nvim_buf_set_extmark(0, ns_id, 0, 0, { end_row = 1, end_col = 0, hl_group = dim_hl })
      child.api.nvim_buf_set_extmark(0, ns_id, 1, 0, { end_row = 2, end_col = 0, hl_group = dim_cur_hl })
      child.api.nvim_buf_set_extmark(0, ns_id, 2, 0, { virt_lines = { { { 'VIR', 'String' } } } })

      -- Ensure visually distinctive highlight groups that are getting dimmed
      set_statuscol_unique_hl()
    end,
  },
})

T['Dim']['works'] = function()
  -- Prepare windows to show various combinations of lines
  set_cursor(4, 0)
  child.cmd('vsplit')
  set_cursor(3, 0)
  child.cmd('vsplit')
  set_cursor(2, 0)
  child.cmd('vsplit')
  set_cursor(1, 0)
  -- NOTE: force redraw since statuscolumn is not re-computed on cursor move
  child.cmd('redraw!')

  -- Should properly dim only inside inactive windows
  child.expect_screenshot()
  child.cmd('wincmd l')
  child.expect_screenshot()
  child.cmd('wincmd l')
  child.expect_screenshot()
  child.cmd('wincmd l')
  child.expect_screenshot()
end

T['Dim']['works when switching tabpage'] = function()
  child.cmd('vsplit | tabnew | vsplit')
  child.expect_screenshot()
  child.cmd('tabprev')
  child.expect_screenshot()
end

T['Dim']['works when showing buffer in inactive window'] = function()
  child.o.laststatus = 2
  child.o.statusline = '%{%nvim_get_current_win()==#g:actual_curwin ? "active" : "inactive"%}'
  local win_id_other = child.api.nvim_get_current_win()
  child.cmd('vsplit')

  local buf_id_other = child.api.nvim_create_buf(false, true)
  child.api.nvim_buf_set_lines(buf_id_other, 0, -1, false, { 'other', 'buf', 'lines' })
  child.api.nvim_win_set_buf(0, buf_id_other)
  child.api.nvim_win_set_buf(win_id_other, buf_id_other)
  child.expect_screenshot()
end

T['Dim']['keeps highlights from extmarks'] = function()
  if child.fn.has('nvim-0.11') == 0 then MiniTest.skip('Highlighting on Neovim<0.11 is correct but a bit different') end

  child.lua('require("mini.statuscolumn").setup({ content = MiniStatuscolumn.gen_content.main() })')
  child.o.number = true
  child.o.numberwidth = 1
  child.o.cursorline = true
  child.o.cursorlineopt = 'number'
  child.o.signcolumn = 'yes'
  child.o.laststatus = 2
  child.o.statusline = '%{%nvim_get_current_win()==#g:actual_curwin ? "active" : "inactive"%}'

  set_lines({ 'uuu', 'vvv', 'www', 'xxx' })
  local ns_id = child.api.nvim_create_namespace('test')
  local dim_hl, dim_cur_hl = 'MiniStatuscolumnDim', 'MiniStatuscolumnDimCursor'
  child.api.nvim_buf_set_extmark(0, ns_id, 0, 0, { end_row = 1, end_col = 0, hl_group = dim_hl })
  child.api.nvim_buf_set_extmark(0, ns_id, 1, 0, { end_row = 2, end_col = 0, hl_group = dim_cur_hl })

  -- Highlighting that was set from extmarks should not be dimmed
  set_unique_hl('AAA')
  set_unique_hl('BBB')
  set_unique_hl('CCC')
  local sign_extmark_opts = { sign_text = 'S', sign_hl_group = 'AAA', cursorline_hl_group = 'BBB' }
  child.api.nvim_buf_set_extmark(0, ns_id, 0, 0, sign_extmark_opts)
  child.api.nvim_buf_set_extmark(0, ns_id, 1, 0, { number_hl_group = 'CCC' })

  local win_id_other = child.api.nvim_get_current_win()
  child.cmd('vsplit')
  child.expect_screenshot()

  child.api.nvim_win_set_cursor(win_id_other, { 4, 0 })
  child.cmd('redraw!')
  child.expect_screenshot()
end

T['Content'] = new_set({
  hooks = {
    pre_case = function()
      child.set_size(10, 20)
      child.lua([[
        local make_content = function(log_name, res)
          return function(...)
            local v = { lnum = vim.v.lnum, relnum = vim.v.relnum, virtnum = vim.v.virtnum }
            table.insert(_G[log_name], { args = { ... }, v = v })
            return res
          end
        end
        _G.log_active, _G.log_inactive = {}, {}
        require('mini.statuscolumn').setup({
          content = {
            active = make_content('log_active', 'act'),
            inactive = make_content('log_inactive', 'ina'),
          },
        })
      ]])
    end,
  },
})

local get_content_args = function(win_type)
  local log_tbl = '_G.log_' .. win_type
  child.lua(log_tbl .. ' = {}')
  child.cmd('redraw!')
  return child.lua_get(log_tbl .. '[1].args[1]')
end

local setup_two_windows = function()
  local win_id_inactive = child.api.nvim_get_current_win()
  local buf_id_inactive = child.api.nvim_create_buf(true, false)
  child.api.nvim_win_set_buf(win_id_inactive, buf_id_inactive)
  set_lines({ 'one', 'twoooooooo' })
  local ns_id = child.api.nvim_create_namespace('test')
  child.api.nvim_buf_set_extmark(0, ns_id, 1, 0, { virt_lines = { { { 'VIR', 'String' } } } })

  child.cmd('wincmd v | enew')
  set_lines({ 'ONE', 'TWO', 'THREE' })
  return {
    active = { buf_id = child.api.nvim_get_current_buf(), win_id = child.api.nvim_get_current_win() },
    inactive = { buf_id = buf_id_inactive, win_id = win_id_inactive },
  }
end

T['Content']['works'] = function()
  local layout = setup_two_windows()
  child.lua('_G.log_active, _G.log_inactive = {}, {}')
  child.cmd('redraw!')

  local get_win_option = function(win_id, option_name)
    return child.api.nvim_get_option_value(option_name, { scope = 'local', win = win_id })
  end

  -- Content function should be called once per drawn line
  local win_active = layout.active.win_id
  local ref_args_active = {
    buf_id = layout.active.buf_id,
    is_cursorlinenr = false,
    is_foldcolumn_fixed = true,
    is_signcolumn_fixed = false,
    is_statuscolumn_empty = true,
    opt_cursorline = get_win_option(win_active, 'cursorline'),
    opt_cursorlineopt = get_win_option(win_active, 'cursorlineopt'),
    opt_foldcolumn = get_win_option(win_active, 'foldcolumn'),
    opt_number = get_win_option(win_active, 'number'),
    opt_relativenumber = get_win_option(win_active, 'relativenumber'),
    opt_signcolumn = get_win_option(win_active, 'signcolumn'),
    win_id = win_active,
  }
  local ref_log_active = {
    { args = { ref_args_active }, v = { lnum = 1, relnum = 0, virtnum = 0 } },
    { args = { ref_args_active }, v = { lnum = 2, relnum = 1, virtnum = 0 } },
    { args = { ref_args_active }, v = { lnum = 3, relnum = 2, virtnum = 0 } },
  }
  eq(child.lua_get('_G.log_active'), ref_log_active)

  local win_inactive = layout.inactive.win_id
  local ref_args_inactive = vim.deepcopy(ref_args_active)
  ref_args_inactive.buf_id = layout.inactive.buf_id
  ref_args_inactive.win_id = win_inactive
  local ref_log_inactive = {
    { args = { ref_args_inactive }, v = { lnum = 1, relnum = 0, virtnum = 0 } },
    { args = { ref_args_inactive }, v = { lnum = 2, relnum = 1, virtnum = 0 } },
    { args = { ref_args_inactive }, v = { lnum = 2, relnum = 1, virtnum = 1 } },
    { args = { ref_args_inactive }, v = { lnum = 2, relnum = 1, virtnum = -1 } },
  }
  eq(child.lua_get('_G.log_inactive'), ref_log_inactive)
end

T['Content']['reacts to buf/win changes'] = function()
  local layout = setup_two_windows()
  local ref

  -- Window focus change
  ref = get_content_args('active')
  child.api.nvim_set_current_win(layout.inactive.win_id)
  ref.buf_id, ref.win_id = layout.inactive.buf_id, layout.inactive.win_id
  eq(get_content_args('active'), ref)

  ref = get_content_args('inactive')
  child.api.nvim_set_current_win(layout.active.win_id)
  ref.buf_id, ref.win_id = layout.inactive.buf_id, layout.inactive.win_id
  eq(get_content_args('inactive'), ref)

  -- Showing new buffer in a window
  ref = get_content_args('active')
  ref.buf_id = child.api.nvim_create_buf(false, true)
  child.api.nvim_win_set_buf(layout.active.win_id, ref.buf_id)
  eq(get_content_args('active'), ref)

  ref = get_content_args('inactive')
  ref.buf_id = child.api.nvim_create_buf(false, true)
  child.api.nvim_win_set_buf(layout.inactive.win_id, ref.buf_id)
  eq(get_content_args('inactive'), ref)

  -- New window
  ref = get_content_args('active')
  child.cmd('wincmd v')
  ref.win_id = child.api.nvim_get_current_win()
  eq(get_content_args('active'), ref)

  child.lua('_G.win_id = ' .. layout.inactive.win_id)
  local new_win_id = child.lua([[
    return vim.api.nvim_win_call(_G.win_id, function()
      vim.cmd('wincmd v')
      return vim.api.nvim_get_current_win()
    end)
  ]])
  local all_win_inactive = {}
  for _, t in ipairs(child.lua_get('_G.log_inactive')) do
    all_win_inactive[t.args[1].win_id] = true
  end
  -- NOTE: The window that was active in initial layout is now inactive
  eq(all_win_inactive, { [layout.inactive.win_id] = true, [layout.active.win_id] = true, [new_win_id] = true })
end

T['Content']['reacts to starting a terminal'] = function()
  if child.fn.has('nvim-0.11') == 0 then MiniTest.skip('Neovim<0.11 has problems with detecting empty statuscolumn') end
  helpers.skip_on_windows('Terminal emulator testing is not robust/easy on Windows')
  helpers.skip_on_macos('Terminal emulator testing is not robust/easy on MacOS')

  -- Special options auto-set by `:terminal` should be shown in content args
  child.o.number = true
  child.o.signcolumn = 'yes'
  local ref = get_content_args('active')

  child.cmd('terminal! bash --noprofile --norc')
  sleep(term_mode_wait)

  ref.opt_number = false
  ref.opt_signcolumn = 'no'
  ref.is_statuscolumn_empty = true
  eq(get_content_args('active'), ref)
end

T['Content']['reacts to option changes'] = function()
  if child.fn.has('nvim-0.11') == 0 then MiniTest.skip('Neovim<0.11 has problems with detecting empty statuscolumn') end

  child.o.number = false
  child.o.foldcolumn = '0'
  child.o.signcolumn = 'auto'

  local layout = setup_two_windows()
  local validate_single = function(win_type, option_name, option_value, args_changes)
    local before = get_content_args(win_type)
    set_win_option(layout[win_type].win_id, option_name, option_value)
    local after = get_content_args(win_type)

    eq(after, vim.tbl_extend('force', before, args_changes))
  end

  --stylua: ignore
  local validate_win = function(win_type)
    validate_single(win_type, 'cursorline', true, { is_cursorlinenr = true, opt_cursorline = true })
    validate_single(win_type, 'cursorlineopt', 'line', { is_cursorlinenr = false, opt_cursorlineopt = 'line' })
    validate_single(win_type, 'foldcolumn', '1', { is_statuscolumn_empty = false, opt_foldcolumn = '1' })
    validate_single(win_type, 'foldcolumn', 'auto', { is_statuscolumn_empty = true, is_foldcolumn_fixed = false, opt_foldcolumn = 'auto' })
    validate_single(win_type, 'foldcolumn', 'auto:1', { opt_foldcolumn = 'auto:1' })
    validate_single(win_type, 'foldcolumn', '0', { is_statuscolumn_empty = true, is_foldcolumn_fixed = true, opt_foldcolumn = '0' })
    validate_single(win_type, 'number', true, { is_statuscolumn_empty = false, opt_number = true })
    validate_single(win_type, 'number', false, { is_statuscolumn_empty = true, opt_number = false })
    validate_single(win_type, 'relativenumber', true, { is_statuscolumn_empty = false, opt_relativenumber = true })
    validate_single(win_type, 'relativenumber', false, { is_statuscolumn_empty = true, opt_relativenumber = false })
    validate_single(win_type, 'signcolumn', 'auto:1', { opt_signcolumn = 'auto:1' })
    validate_single(win_type, 'signcolumn', 'number', { opt_signcolumn = 'number' })
    validate_single(win_type, 'signcolumn', 'yes', { is_statuscolumn_empty = false, is_signcolumn_fixed = true, opt_signcolumn = 'yes' })
    validate_single(win_type, 'signcolumn', 'no', { is_statuscolumn_empty = true, opt_signcolumn = 'no' })
    validate_single(win_type, 'signcolumn', 'auto', { is_signcolumn_fixed = false, opt_signcolumn = 'auto' })
  end

  validate_win('active')
  validate_win('inactive')
end

T['Content']['tracks non-fixed signcolumn'] = function()
  local layout = setup_two_windows()
  local ns_id = child.api.nvim_create_namespace('test')

  local validate_single = function(win_type, ref_empty)
    eq(get_content_args(win_type).is_statuscolumn_empty, ref_empty)

    -- Adding sign to any enabled sign column makes statuscolumn non-empty
    child.api.nvim_buf_set_extmark(layout[win_type].buf_id, ns_id, 1, 0, { sign_text = 'S' })
    local signcolumn = child.api.nvim_get_option_value('signcolumn', { scope = 'local', win = layout[win_type].win_id })
    eq(get_content_args(win_type).is_statuscolumn_empty, signcolumn == 'no')

    -- Removing all signs makes statuscolumn empty for non-fixed sign column
    child.api.nvim_buf_clear_namespace(layout[win_type].buf_id, ns_id, 0, -1)
    eq(get_content_args(win_type).is_statuscolumn_empty, ref_empty)
  end

  local validate = function(signcolumn, ref_fixed, ref_empty)
    set_win_option(layout.active.win_id, 'signcolumn', signcolumn)
    eq(get_content_args('active').is_signcolumn_fixed, ref_fixed)
    validate_single('active', ref_empty)

    set_win_option(layout.inactive.win_id, 'signcolumn', signcolumn)
    eq(get_content_args('inactive').is_signcolumn_fixed, ref_fixed)
    validate_single('inactive', ref_empty)
  end

  validate('auto', false, true)
  validate('auto:1', false, true)
  validate('yes', true, false)
  validate('no', true, true)
  validate('number', false, true)
end

T['Content']['tracks non-fixed foldcolumn'] = function()
  local layout = setup_two_windows()

  local validate_single = function(win_type, ref_empty)
    eq(get_content_args(win_type).is_statuscolumn_empty, ref_empty)
    child.lua('_G.win_id = ' .. layout[win_type].win_id)

    -- Adding fold to any enabled fold column makes statuscolumn non-empty
    child.lua('vim.api.nvim_win_call(_G.win_id, function() vim.cmd("1,2fold") end)')
    local foldcolumn = child.api.nvim_get_option_value('foldcolumn', { scope = 'local', win = layout[win_type].win_id })
    eq(get_content_args(win_type).is_statuscolumn_empty, foldcolumn == '0')

    -- Removing all folds makes statuscolumn empty for non-fixed fold column
    child.lua('vim.api.nvim_win_call(_G.win_id, function() vim.cmd("normal! zd") end)')
    eq(get_content_args(win_type).is_statuscolumn_empty, ref_empty)
  end

  local validate = function(foldcolumn, ref_fixed, ref_empty)
    set_win_option(layout.active.win_id, 'foldcolumn', foldcolumn)
    eq(get_content_args('active').is_foldcolumn_fixed, ref_fixed)
    validate_single('active', ref_empty)

    set_win_option(layout.inactive.win_id, 'foldcolumn', foldcolumn)
    eq(get_content_args('inactive').is_foldcolumn_fixed, ref_fixed)
    validate_single('inactive', ref_empty)
  end

  validate('auto', false, true)
  validate('auto:1', false, true)
  validate('0', true, true)
  validate('1', true, false)
end

T['Content']['draws correct width after its change'] = function()
  child.lua([[
    require('mini.statuscolumn').setup({
      content = {
        active = function(win_data) return win_data.is_statuscolumn_empty and '' or 'act|' end,
        inactive = function(win_data) return win_data.is_statuscolumn_empty and '' or 'ina|' end,
      }
    })
  ]])

  child.o.signcolumn, child.o.foldcolumn = 'auto', 'auto'
  local layout = setup_two_windows()
  child.lua('_G.win_inactive = ' .. layout.inactive.win_id)
  local ns_id = child.api.nvim_create_namespace('sign')
  local expect_screenshot = function() child.expect_screenshot({ redraw = false }) end

  -- Sign column
  child.api.nvim_buf_set_extmark(layout.active.buf_id, ns_id, 1, 0, { sign_text = 'S' })
  expect_screenshot()
  child.api.nvim_buf_set_extmark(layout.inactive.buf_id, ns_id, 1, 0, { sign_text = 'I' })
  expect_screenshot()

  child.api.nvim_buf_clear_namespace(layout.active.buf_id, ns_id, 0, -1)
  expect_screenshot()
  child.api.nvim_buf_clear_namespace(layout.inactive.buf_id, ns_id, 0, -1)
  expect_screenshot()

  -- Fold column
  child.cmd('1,2fold')
  expect_screenshot()
  child.lua('vim.api.nvim_win_call(_G.win_inactive, function() vim.cmd("1,2fold") end)')
  expect_screenshot()

  child.cmd('normal! zd')
  expect_screenshot()
  child.lua('vim.api.nvim_win_call(_G.win_inactive, function() vim.cmd("normal! zd") end)')
  expect_screenshot()

  -- Same buffer in several windows
  -- - Signs are per buffer, so statuscolumn should be shown in both windows
  child.api.nvim_win_set_buf(layout.inactive.win_id, layout.active.buf_id)
  child.api.nvim_buf_set_extmark(layout.active.buf_id, ns_id, 1, 0, { sign_text = 'S' })
  expect_screenshot()

  child.api.nvim_buf_clear_namespace(layout.active.buf_id, ns_id, 0, -1)
  expect_screenshot()

  -- - Folds are per window, so statuscolumn should be shown in one window
  child.cmd('1,2fold')
  expect_screenshot()
end

T['Content']['handles temporary windows when tracking window data'] = function()
  child.lua([[
    vim.cmd('vsplit')
    vim.cmd('redraw!')
    vim.cmd('close')
  ]])
  eq(child.cmd_capture('messages'), '')
end

T['Default content'] = new_set({
  hooks = {
    pre_case = function()
      child.set_size(18, 25)
      child.o.number = false
      child.o.foldcolumn = '0'
      child.o.signcolumn = 'no'
      prepare_main_content_layout()
    end,
  },
})

local validate_with_win_options = function(number, foldcolumn, signcolumn)
  set_all_win_option('number', number)
  set_all_win_option('foldcolumn', foldcolumn)
  set_all_win_option('signcolumn', signcolumn)
  refresh_statuscolumn()

  child.expect_screenshot()
end

T['Default content']['works'] = function()
  validate_with_win_options(false, '0', 'no')

  -- Special symbols for wrapped/virtual lines should be shown regardless of
  -- whether 'number' is enabled.
  validate_with_win_options(true, '0', 'no')
  validate_with_win_options(false, '1', 'no')
  validate_with_win_options(false, '0', 'yes')

  validate_with_win_options(true, '1', 'no')
  validate_with_win_options(true, '0', 'yes')
  validate_with_win_options(false, '1', 'yes')

  validate_with_win_options(true, '1', 'yes')
end

T['Default content']['works with non-fixed sign column'] = function()
  if child.fn.has('nvim-0.11') == 0 then MiniTest.skip('Neovim<0.11 has problems with signcolumn=number') end

  validate_with_win_options(true, '0', 'auto')
  validate_with_win_options(true, '0', 'auto:1')
  validate_with_win_options(true, '0', 'number')

  local ns_id_sign = child.api.nvim_create_namespace('sign')
  for _, buf_id in ipairs(child.api.nvim_list_bufs()) do
    child.api.nvim_buf_clear_namespace(buf_id, ns_id_sign, 0, -1)
  end

  validate_with_win_options(true, '0', 'auto')
  validate_with_win_options(true, '0', 'auto:1')
  validate_with_win_options(true, '0', 'number')
end

T['Default content']['works with non-fixed fold column'] = function()
  validate_with_win_options(true, 'auto', 'no')
  validate_with_win_options(true, 'auto:1', 'no')

  child.lua([[
    for _, win_id in ipairs(vim.api.nvim_list_wins()) do
      -- Delete existing fold on line 4
      vim.api.nvim_win_call(win_id, function() vim.cmd('normal! 4Gzd') end)
    end
  ]])

  validate_with_win_options(true, 'auto', 'no')
  validate_with_win_options(true, 'auto:1', 'no')
end

T['Default content']["respects 'numberwidth'"] = function()
  set_all_win_option('numberwidth', 2)
  validate_with_win_options(true, '0', 'no')
end

return T
