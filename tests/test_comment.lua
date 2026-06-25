local helpers = dofile('tests/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
local load_module = function(config) child.mini_load('comment', config) end
local unload_module = function() child.mini_unload('comment') end
local reload_module = function(config) child.mini_reload('comment', config) end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end

-- Common helpers
local reload_with_hooks = function()
  unload_module()
  child.lua([[
    _G.hook_args = {}
    require('mini.comment').setup({
      hooks = {
        pre = function(...)
          table.insert(_G.hook_args, { 'pre', vim.deepcopy({ ... }) })
          -- Allow this to successfully change 'commentstring' option
          vim.bo.commentstring = vim.bo.commentstring == '# %s' and '// %s' or '# %s'
        end,
        post = function(...) table.insert(_G.hook_args, { 'post', vim.deepcopy({ ... }) }) end,
      },
    })]])
end

local forward_lua = function(fun_str)
  local lua_cmd = fun_str .. '(...)'
  return function(...) return child.lua_get(lua_cmd, { ... }) end
end

-- Data =======================================================================
-- Reference text
-- aa
--  aa
--   aa
--
--   aa
--  aa
-- aa
local example_lines = { 'aa', ' aa', '  aa', '', '  aa', ' aa', 'aa' }

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      load_module()
      set_lines(example_lines)
      child.bo.commentstring = '# %s'
    end,
    post_once = child.stop,
  },
  n_retry = helpers.get_n_retry(1),
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  -- Global variable
  eq(child.lua_get('type(_G.MiniComment)'), 'table')
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniComment.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniComment.config.' .. field), value) end

  expect_config('options.custom_commentstring', vim.NIL)
  expect_config('options.ignore_blank_line', false)
  expect_config('options.start_of_line', false)
  expect_config('options.pad_comment_parts', true)
  expect_config('mappings.comment', 'gc')
  expect_config('mappings.comment_line', 'gcc')
  expect_config('mappings.comment_visual', 'gc')
  expect_config('mappings.textobject', 'gc')
end

T['setup()']['respects `config` argument'] = function()
  unload_module()
  load_module({ mappings = { comment = 'gC' } })
  eq(child.lua_get('MiniComment.config.mappings.comment'), 'gC')
end

T['setup()']['validates `config` argument'] = function()
  unload_module()

  local expect_config_error = function(config, name, target_type)
    expect.error(function() load_module(config) end, vim.pesc(name) .. '.*' .. vim.pesc(target_type))
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ options = 'a' }, 'options', 'table')
  expect_config_error({ options = { custom_commentstring = 1 } }, 'options.custom_commentstring', 'function')
  expect_config_error({ options = { ignore_blank_line = 1 } }, 'options.ignore_blank_line', 'boolean')
  expect_config_error({ options = { start_of_line = 1 } }, 'options.start_of_line', 'boolean')
  expect_config_error({ options = { pad_comment_parts = 1 } }, 'options.pad_comment_parts', 'boolean')
  expect_config_error({ mappings = 'a' }, 'mappings', 'table')
  expect_config_error({ mappings = { comment = 1 } }, 'mappings.comment', 'string')
  expect_config_error({ mappings = { comment_line = 1 } }, 'mappings.comment_line', 'string')
  expect_config_error({ mappings = { comment_visual = 1 } }, 'mappings.comment_visual', 'string')
  expect_config_error({ mappings = { textobject = 1 } }, 'mappings.textobject', 'string')
  expect_config_error({ hooks = 'a' }, 'hooks', 'table')
  expect_config_error({ hooks = { pre = 1 } }, 'hooks.pre', 'function')
  expect_config_error({ hooks = { post = 1 } }, 'hooks.post', 'function')
end

T['setup()']['properly handles `config.mappings`'] = function()
  local has_map = function(lhs, pattern) return child.cmd_capture('omap ' .. lhs):find(pattern) ~= nil end
  eq(has_map('gc', 'Comment'), true)

  unload_module()
  child.api.nvim_del_keymap('o', 'gc')

  -- Supplying empty string should mean "don't create keymap"
  load_module({ mappings = { textobject = '' } })
  eq(has_map('gc', 'Comment'), false)
end

T['toggle_lines()'] = new_set()

local toggle_lines = forward_lua('MiniComment.toggle_lines')

T['toggle_lines()']['works'] = function()
  toggle_lines(3, 5)
  eq(get_lines(2, 5), { '  # aa', '  #', '  # aa' })

  toggle_lines(3, 5)
  eq(get_lines(2, 5), { '  aa', '', '  aa' })
end

--stylua: ignore
T['toggle_lines()']['validates arguments'] = function()
  set_lines({ 'aa', 'aa', 'aa' })

  expect.error(function() toggle_lines(-1, 1)    end, 'line_start.*1')
  expect.error(function() toggle_lines(100, 101) end, 'line_start.*3')
  expect.error(function() toggle_lines(1, -1)    end, 'line_end.*1')
  expect.error(function() toggle_lines(1, 100)   end, 'line_end.*3')
  expect.error(function() toggle_lines(2, 1)     end, 'line_start.*less than or equal.*line_end')
end

T['toggle_lines()']["works with different 'commentstring' options"] = function()
  -- Two-sided
  set_lines(example_lines)
  child.bo.commentstring = '/* %s */'
  toggle_lines(3, 5)
  eq(get_lines(2, 5), { '  /* aa */', '  /**/', '  /* aa */' })

  toggle_lines(3, 5)
  eq(get_lines(2, 5), { '  aa', '', '  aa' })

  -- Right-sided
  set_lines(example_lines)
  child.bo.commentstring = '%s #'
  toggle_lines(3, 5)
  eq(get_lines(2, 5), { '  aa #', '  #', '  aa #' })

  toggle_lines(3, 5)
  eq(get_lines(2, 5), { '  aa', '', '  aa' })

  -- Latex (#25)
  set_lines(example_lines)
  child.bo.commentstring = '% %s'
  toggle_lines(3, 5)
  eq(get_lines(2, 5), { '  % aa', '  %', '  % aa' })

  toggle_lines(3, 5)
  eq(get_lines(2, 5), { '  aa', '', '  aa' })
end

T['toggle_lines()']['respects tree-sitter injections'] = function()
  -- NOTE: This leverages bundled Vimscript and Lua tree-sitter parsers
  local lines = {
    'set background=dark',
    'lua << EOF',
    'print(1)',
    'vim.api.nvim_exec2([[',
    '    set background=light',
    ']])',
    'EOF',
  }
  set_lines(lines)
  child.bo.filetype = 'vim'
  child.lua('vim.treesitter.start()')

  -- Single line comments
  local validate = function(line, ref_output)
    toggle_lines(line, line)
    eq(get_lines()[line], ref_output)
    -- Cleanup
    set_lines(lines)
  end

  validate(1, '" set background=dark')
  validate(2, '" lua << EOF')
  validate(3, '-- print(1)')
  validate(4, '-- vim.api.nvim_exec2([[')
  validate(5, '    " set background=light')
  validate(6, '-- ]])')
  validate(7, '" EOF')

  -- Multiline comments should be computed based on first line 'commentstring'
  set_lines(lines)
  toggle_lines(1, 3)
  local out_lines = get_lines()
  eq(out_lines[1], '" set background=dark')
  eq(out_lines[2], '" lua << EOF')
  eq(out_lines[3], '" print(1)')
end

T['toggle_lines()']['respects `opts.ref_position`'] = function()
  -- NOTE: This leverages bundled Vimscript and Lua tree-sitter parsers
  local lines = {
    'lua << EOF',
    '  print(1)',
    'EOF',
  }
  set_lines(lines)
  child.bo.filetype = 'vim'
  child.lua('vim.treesitter.start()')

  toggle_lines(2, 2, { ref_position = { 1, 0 } })
  eq(get_lines()[2], '  " print(1)')

  set_lines(lines)
  toggle_lines(2, 2, { ref_position = { 2, 3 } })
  eq(get_lines()[2], '  -- print(1)')
end

T['toggle_lines()']['correctly computes indent'] = function()
  toggle_lines(2, 4)
  eq(get_lines(1, 4), { ' # aa', ' #  aa', ' #' })
end

--stylua: ignore
T['toggle_lines()']['correctly detects comment/uncomment'] = function()
  local validate = function(from, to, ref_lines)
    set_lines({ '', 'aa', '# aa', '# aa', 'aa', '' })
    toggle_lines(from, to)
    eq(get_lines(), ref_lines)
  end

  -- It should uncomment only if all lines are comments
  validate(3, 4, { '',  'aa',   'aa',     'aa',     'aa',   '' })
  validate(2, 4, { '',  '# aa', '# # aa', '# # aa', 'aa',   '' })
  validate(3, 5, { '',  'aa',   '# # aa', '# # aa', '# aa', '' })
  validate(1, 6, { '#', '# aa', '# # aa', '# # aa', '# aa', '#' })

  -- Blank lines should be ignored when making a decision
  set_lines({ '# aa', '', '  ', '\t', '# aa' })
  toggle_lines(1, 5)
  eq(get_lines(), { 'aa', '', '  ', '\t', 'aa' })
end

T['toggle_lines()']['matches comment parts strictly when detecting comment/uncomment'] = function()
  local validate = function(from, to, ref_lines)
    set_lines({ '/*aa*/', '/* aa */', '/*  aa  */' })
    toggle_lines(from, to)
    eq(get_lines(), ref_lines)
  end

  -- Should first try to match 'commentstring' parts exactly with their
  -- whitespace, with fallback on trimmed parts
  child.bo.commentstring = '/* %s */'
  validate(1, 3, { 'aa', 'aa', ' aa ' })
  validate(2, 3, { '/*aa*/', 'aa', ' aa ' })
  validate(3, 3, { '/*aa*/', '/* aa */', ' aa ' })

  -- With `pad_comment_parts = false` should treat parts as is
  child.lua('MiniComment.config.options.pad_comment_parts = false')

  child.bo.commentstring = '/*%s*/'
  validate(1, 3, { 'aa', ' aa ', '  aa  ' })
  validate(2, 3, { '/*aa*/', ' aa ', '  aa  ' })
  validate(3, 3, { '/*aa*/', '/* aa */', '  aa  ' })

  child.bo.commentstring = '/*  %s  */'
  validate(1, 3, { 'aa', ' aa ', 'aa' })
  validate(2, 3, { '/*aa*/', ' aa ', 'aa' })
  validate(3, 3, { '/*aa*/', '/* aa */', 'aa' })

  child.bo.commentstring = ' /*%s*/ '
  validate(1, 3, { 'aa', ' aa ', '  aa  ' })
  validate(2, 3, { '/*aa*/', ' aa ', '  aa  ' })
  validate(3, 3, { '/*aa*/', '/* aa */', '  aa  ' })
end

T['toggle_lines()']['respects `config.options.custom_commentstring`'] = function()
  local lines = { 'aa', '  aa' }

  -- Works correctly and called with proper arguments
  child.lua([[MiniComment.config.options.custom_commentstring = function(...)
    _G.args = { ... }
    return '++ %s'
  end]])

  set_lines(lines)
  toggle_lines(1, 2, { ref_position = { 2, 3 } })
  eq(get_lines(), { '++ aa', '++   aa' })
  eq(child.lua_get('_G.args'), { { 2, 3 } })

  -- Allows `nil` output to indicate usage of default rules
  child.lua('MiniComment.config.options.custom_commentstring = function() return nil end')
  set_lines(lines)
  toggle_lines(1, 2)
  eq(get_lines(), { '# aa', '#   aa' })

  -- Validates output
  child.lua('MiniComment.config.options.custom_commentstring = function() return 2 end')
  expect.error(function() toggle_lines(1, 2) end, "2.*valid 'commentstring'")

  child.lua('MiniComment.config.options.custom_commentstring = function() return "ab %c" end')
  expect.error(function() toggle_lines(1, 2) end, [["ab %%c".*valid 'commentstring']])
end

T['toggle_lines()']['respects `config.options.start_of_line`'] = function()
  child.lua('MiniComment.config.options.start_of_line = true')
  local lines = { ' # aa', '  # aa', '# aa', '#  aa' }

  -- Should recognize as commented only lines with zero indent
  set_lines(lines)
  toggle_lines(1, 3)
  eq(get_lines(), { '#  # aa', '#   # aa', '# # aa', '#  aa' })
  toggle_lines(1, 3)
  eq(get_lines(), lines)

  set_lines(lines)
  toggle_lines(3, 4)
  eq(get_lines(), { ' # aa', '  # aa', 'aa', ' aa' })
  toggle_lines(3, 4)
  eq(get_lines(), { ' # aa', '  # aa', '# aa', '#  aa' })
end

T['toggle_lines()']['respects `config.options.ignore_blank_line`'] = function()
  child.lua('MiniComment.config.options.ignore_blank_line = true')
  local lines = { '  aa', '', '  aa', '  ', '  aa' }

  -- Should not add comment to blank (empty or with only whitespace) lines
  set_lines(lines)
  toggle_lines(1, 5)
  eq(get_lines(), { '  # aa', '', '  # aa', '  ', '  # aa' })

  -- Should ignore blank lines when deciding comment/uncomment action
  toggle_lines(1, 5)
  eq(get_lines(), lines)
end

T['toggle_lines()']['respects `config.options.pad_comment_parts`'] = function()
  child.lua('MiniComment.config.options.pad_comment_parts = false')

  local validate = function(lines_before, lines_after, lines_again)
    set_lines(lines_before)
    toggle_lines(1, #lines_before)
    eq(get_lines(), lines_after)
    toggle_lines(1, #lines_before)
    eq(get_lines(), lines_again or lines_before)
  end

  -- No whitespace in parts
  child.bo.commentstring = '#%s#'
  -- - General case
  validate({ 'aa', '  aa', 'aa  ', '  aa  ' }, { '#aa#', '#  aa#', '#aa  #', '#  aa  #' })
  -- - Tabs
  validate({ 'aa', '\taa', 'aa\t', '\taa\t' }, { '#aa#', '#\taa#', '#aa\t#', '#\taa\t#' })
  -- - With indent
  validate({ ' aa', '  aa' }, { ' #aa#', ' # aa#' })
  -- - With blank/empty lines
  validate({ '  aa', '', '  ', '\t' }, { '  #aa#', '  ##', '  ##', '  ##' }, { '  aa', '', '', '' })

  child.bo.commentstring = '#%s'
  validate({ 'aa', '  aa', 'aa  ', '  aa  ' }, { '#aa', '#  aa', '#aa  ', '#  aa  ' })
  validate({ 'aa', '\taa', 'aa\t', '\taa\t' }, { '#aa', '#\taa', '#aa\t', '#\taa\t' })
  validate({ ' aa', '  aa' }, { ' #aa', ' # aa' })
  validate({ '  aa', '', '  ', '\t' }, { '  #aa', '  #', '  #', '  #' }, { '  aa', '', '', '' })

  child.bo.commentstring = '%s#'
  validate({ 'aa', '  aa', 'aa  ', '  aa  ' }, { 'aa#', '  aa#', 'aa  #', '  aa  #' })
  validate({ 'aa', '\taa', 'aa\t', '\taa\t' }, { 'aa#', '\taa#', 'aa\t#', '\taa\t#' })
  validate({ ' aa', '  aa' }, { ' aa#', '  aa#' })
  validate({ '  aa', '', '  ', '\t' }, { '  aa#', '  #', '  #', '  #' }, { '  aa', '', '', '' })

  -- Whitespace inside comment parts
  child.bo.commentstring = '#  %s  #'
  validate({ 'aa', '  aa', 'aa  ', '  aa  ' }, { '#  aa  #', '#    aa  #', '#  aa    #', '#    aa    #' })
  validate({ 'aa', '\taa', 'aa\t', '\taa\t' }, { '#  aa  #', '#  \taa  #', '#  aa\t  #', '#  \taa\t  #' })
  validate({ ' aa', '  aa' }, { ' #  aa  #', ' #   aa  #' })
  validate({ '  aa', '', '  ', '\t' }, { '  #  aa  #', '  ##', '  ##', '  ##' }, { '  aa', '', '', '' })

  child.bo.commentstring = '#  %s'
  validate({ 'aa', '  aa', 'aa  ', '  aa  ' }, { '#  aa', '#    aa', '#  aa  ', '#    aa  ' })
  validate({ 'aa', '\taa', 'aa\t', '\taa\t' }, { '#  aa', '#  \taa', '#  aa\t', '#  \taa\t' })
  validate({ ' aa', '  aa' }, { ' #  aa', ' #   aa' })
  validate({ '  aa', '', '  ', '\t' }, { '  #  aa', '  #', '  #', '  #' }, { '  aa', '', '', '' })

  child.bo.commentstring = '%s  #'
  validate({ 'aa', '  aa', 'aa  ', '  aa  ' }, { 'aa  #', '  aa  #', 'aa    #', '  aa    #' })
  validate({ 'aa', '\taa', 'aa\t', '\taa\t' }, { 'aa  #', '\taa  #', 'aa\t  #', '\taa\t  #' })
  validate({ ' aa', '  aa' }, { ' aa  #', '  aa  #' })
  validate({ '  aa', '', '  ', '\t' }, { '  aa  #', '  #', '  #', '  #' }, { '  aa', '', '', '' })

  -- Whitespace outside of comment parts
  child.bo.commentstring = ' # %s # '
  validate({ 'aa', '  aa', 'aa  ', '  aa  ' }, { ' # aa # ', ' #   aa # ', ' # aa   # ', ' #   aa   # ' })
  validate({ 'aa', '\taa', 'aa\t', '\taa\t' }, { ' # aa # ', ' # \taa # ', ' # aa\t # ', ' # \taa\t # ' })
  validate({ ' aa', '  aa' }, { '  # aa # ', '  #  aa # ' })
  validate({ '  aa', '', '  ', '\t' }, { '   # aa # ', '  ##', '  ##', '  ##' }, { '  aa', '', '', '' })

  child.bo.commentstring = ' # %s '
  validate({ 'aa', '  aa', 'aa  ', '  aa  ' }, { ' # aa ', ' #   aa ', ' # aa   ', ' #   aa   ' })
  validate({ 'aa', '\taa', 'aa\t', '\taa\t' }, { ' # aa ', ' # \taa ', ' # aa\t ', ' # \taa\t ' })
  validate({ ' aa', '  aa' }, { '  # aa ', '  #  aa ' })
  validate({ '  aa', '', '  ', '\t' }, { '   # aa ', '  #', '  #', '  #' }, { '  aa', '', '', '' })

  child.bo.commentstring = ' %s # '
  validate({ 'aa', '  aa', 'aa  ', '  aa  ' }, { ' aa # ', '   aa # ', ' aa   # ', '   aa   # ' })
  validate({ 'aa', '\taa', 'aa\t', '\taa\t' }, { ' aa # ', ' \taa # ', ' aa\t # ', ' \taa\t # ' })
  validate({ ' aa', '  aa' }, { '  aa # ', '   aa # ' })
  validate({ '  aa', '', '  ', '\t' }, { '   aa # ', '  #', '  #', '  #' }, { '  aa', '', '', '' })
end

T['toggle_lines()']['uncomments on inconsistent indent levels'] = function()
  set_lines({ '# aa', ' # aa', '  # aa' })
  toggle_lines(1, 3)
  eq(get_lines(), { 'aa', ' aa', '  aa' })
end

T['toggle_lines()']['respects tabs (#20)'] = function()
  child.bo.expandtab = false
  set_lines({ '\t\taa', '\t\taa' })

  toggle_lines(1, 2)
  eq(get_lines(), { '\t\t# aa', '\t\t# aa' })

  toggle_lines(1, 2)
  eq(get_lines(), { '\t\taa', '\t\taa' })
end

T['toggle_lines()']['adds spaces inside non-empty lines'] = function()
  -- Two-sided
  set_lines(example_lines)
  child.bo.commentstring = '/*%s*/'
  toggle_lines(3, 5)
  eq(get_lines(2, 5), { '  /* aa */', '  /**/', '  /* aa */' })

  -- Right-sided
  set_lines(example_lines)
  child.bo.commentstring = '%s#'
  toggle_lines(3, 5)
  eq(get_lines(2, 5), { '  aa #', '  #', '  aa #' })
end

T['toggle_lines()']['works with trailing whitespace'] = function()
  -- Without right-hand side
  child.bo.commentstring = '# %s'
  set_lines({ ' aa', ' aa  ', '  ' })
  toggle_lines(1, 3)
  eq(get_lines(), { ' # aa', ' # aa  ', ' #' })
  toggle_lines(1, 3)
  eq(get_lines(), { ' aa', ' aa  ', '' })

  -- With right-hand side
  child.bo.commentstring = '%s #'
  set_lines({ ' aa', ' aa  ', '  ' })
  toggle_lines(1, 3)
  eq(get_lines(), { ' aa #', ' aa   #', ' #' })
  toggle_lines(1, 3)
  eq(get_lines(), { ' aa', ' aa  ', '' })

  -- Trailing whitespace after right side should be preserved for non-blanks
  child.bo.commentstring = '%s #'
  set_lines({ ' aa #  ', ' aa #\t', ' #  ', ' #\t' })
  toggle_lines(1, 4)
  eq(get_lines(), { ' aa  ', ' aa\t', '', '' })
end

T['toggle_lines()']['applies hooks'] = function()
  reload_with_hooks()
  eq(child.bo.commentstring, '# %s')

  set_lines({ 'aa', 'aa' })
  toggle_lines(1, 2)
  -- It should allow change of `commentstring` in `pre` hook
  eq(get_lines(), { '// aa', '// aa' })
  --stylua: ignore
  eq(child.lua_get('_G.hook_args'), {
    { 'pre',  { { line_start = 1, line_end = 2, ref_position = { 1, 1 }, action = 'toggle' } } },
    { 'post', { { line_start = 1, line_end = 2, ref_position = { 1, 1 }, action = 'comment' } } },
  })

  -- Should correctly identify `action`
  child.lua('_G.hook_args = {}')
  set_lines({ '// aa', '// aa' })
  child.bo.commentstring = '# %s'
  toggle_lines(1, 1)
  eq(get_lines(), { 'aa', '// aa' })
  --stylua: ignore
  eq(child.lua_get('_G.hook_args'), {
    { 'pre',  { { line_start = 1, line_end = 1, ref_position = { 1, 1 }, action = 'toggle' } } },
    { 'post', { { line_start = 1, line_end = 1, ref_position = { 1, 1 }, action = 'uncomment' } } },
  })
end

T['toggle_lines()']['stops when hook returns `false`'] = function()
  local lines = { 'aa', 'aa' }
  set_lines(lines)

  child.lua('MiniComment.config.hooks.pre = function() return false end')
  toggle_lines(1, 2)
  eq(get_lines(), lines)

  -- Currently can't really check for `hooks.post`
end

T['toggle_lines()']['respects `vim.b.minicomment_config`'] = function()
  child.lua('vim.b.minicomment_config = { options = { start_of_line = true } }')
  set_lines({ '  # aa', '  # aa' })

  toggle_lines(1, 2)
  eq(get_lines(), { '#   # aa', '#   # aa' })
end

T['get_commentstring()'] = new_set()

local get_commentstring = function(...) return child.lua_get('MiniComment.get_commentstring(...)', { ... }) end

T['get_commentstring()']['works'] = function()
  -- Uses buffer's 'commentstring'
  child.bo.commentstring = '# %s'

  eq(get_commentstring(), '# %s')

  local lines = {
    'lua << EOF',
    '  print(1)',
    'EOF',
  }
  set_lines(lines)
  child.bo.filetype = 'vim'
  child.lua('vim.treesitter.start()')

  eq(get_commentstring({ 1, 1 }), '"%s')
  eq(get_commentstring({ 2, 3 }), '-- %s')
  eq(get_commentstring({ 3, 1 }), '"%s')
end

-- Integration tests ==========================================================
T['Operator'] = new_set()

T['Operator']['works in Normal mode'] = function()
  set_cursor(2, 2)
  type_keys('gc', 'ap')
  eq(get_lines(), { '# aa', '#  aa', '#   aa', '#', '  aa', ' aa', 'aa' })
  -- Cursor moves to start line
  eq(get_cursor(), { 1, 0 })

  -- Supports `v:count`
  set_lines(example_lines)
  set_cursor(2, 0)
  type_keys('2gc', 'ap')
  eq(get_lines(), { '# aa', '#  aa', '#   aa', '#', '#   aa', '#  aa', '# aa' })
end

T['Operator']['allows dot-repeat in Normal mode'] = function()
  local doubly_commented = { '# # aa', '# #  aa', '# #   aa', '# #', '#   aa', '#  aa', '# aa' }

  set_lines(example_lines)
  set_cursor(2, 2)
  type_keys('gc', 'ap')
  type_keys('.')
  eq(get_lines(), doubly_commented)

  -- Not immediate dot-repeat
  set_lines(example_lines)
  set_cursor(2, 2)
  type_keys('gc', 'ap')
  set_cursor(7, 0)
  type_keys('.')
  eq(get_lines(), doubly_commented)
end

T['Operator']['works in Visual mode'] = function()
  set_cursor(2, 2)
  type_keys('v', 'ap', 'gc')
  eq(get_lines(), { '# aa', '#  aa', '#   aa', '#', '  aa', ' aa', 'aa' })

  -- Cursor moves to start line
  eq(get_cursor(), { 1, 0 })
end

T['Operator']['allows dot-repeat after initial Visual mode'] = function()
  -- local example_lines = { 'aa', ' aa', '  aa', '', '  aa', ' aa', 'aa' }

  set_lines(example_lines)
  set_cursor(2, 2)
  type_keys('vip', 'gc')
  eq(get_lines(), { '# aa', '#  aa', '#   aa', '', '  aa', ' aa', 'aa' })
  eq(get_cursor(), { 1, 0 })

  -- Dot-repeat after first application in Visual mode should apply to the same
  -- relative region
  type_keys('.')
  eq(get_lines(), example_lines)

  set_cursor(3, 0)
  type_keys('.')
  eq(get_lines(), { 'aa', ' aa', '  # aa', '  #', '  # aa', ' aa', 'aa' })
end

T['Operator']['works with different mapping'] = function()
  reload_module({ mappings = { comment = 'gC', comment_visual = 'C' } })

  -- Normal mode
  set_cursor(2, 2)
  type_keys('gC', 'ap')
  eq(get_lines(), { '# aa', '#  aa', '#   aa', '#', '  aa', ' aa', 'aa' })

  -- Visual mode
  set_lines(example_lines)
  set_cursor(2, 2)
  type_keys('v', 'ap', 'C')
  eq(get_lines(), { '# aa', '#  aa', '#   aa', '#', '  aa', ' aa', 'aa' })
end

T['Operator']["respects 'commentstring'"] = function()
  child.bo.commentstring = '/*%s*/'
  set_cursor(2, 2)
  type_keys('gc', 'ap')
  eq(get_lines(), { '/* aa */', '/*  aa */', '/*   aa */', '/**/', '  aa', ' aa', 'aa' })
end

T['Operator']["works with empty 'commentstring'"] = function()
  child.bo.commentstring = ''
  set_cursor(2, 2)
  type_keys('gc', 'ap')
  eq(get_lines(), example_lines)
  eq(child.cmd_capture('1messages'), [[(mini.comment) Option 'commentstring' is empty.]])
end

T['Operator']['respects tree-sitter injections'] = function()
  -- NOTE: This leverages bundled Vimscript and Lua tree-sitter parsers
  local lines = {
    'set background=dark',
    'lua << EOF',
    'print(1)',
    'vim.api.nvim_exec2([[',
    '    set background=light',
    ']])',
    'EOF',
  }
  set_lines(lines)
  child.bo.filetype = 'vim'
  child.lua('vim.treesitter.start()')

  -- Single line comments
  local validate = function(line, ref_output)
    set_cursor(line, 0)
    type_keys('gc_')
    eq(get_lines()[line], ref_output)
    -- Cleanup
    set_lines(lines)
  end

  validate(1, '" set background=dark')
  validate(2, '" lua << EOF')
  validate(3, '-- print(1)')
  validate(4, '-- vim.api.nvim_exec2([[')
  validate(5, '    " set background=light')
  validate(6, '-- ]])')
  validate(7, '" EOF')

  -- Has proper dot-repeat which recomputes 'commentstring'
  set_lines(lines)

  set_cursor(1, 0)
  type_keys('gc_')
  eq(get_lines()[1], '" set background=dark')

  set_cursor(3, 0)
  type_keys('.')
  eq(get_lines()[3], '-- print(1)')

  -- Multiline comments should be computed based on cursor position
  -- which in case of Visual selection means its left part
  set_lines(lines)
  set_cursor(1, 0)
  type_keys('v2j', 'gc')
  local out_lines = get_lines()
  eq(out_lines[1], '" set background=dark')
  eq(out_lines[2], '" lua << EOF')
  eq(out_lines[3], '" print(1)')
end

T['Operator']['respects `options.custom_commentstring`'] = function()
  local lines = { 'aa', '  aa' }

  -- Works correctly and called with proper arguments
  child.lua([[MiniComment.config.options.custom_commentstring = function(...)
    _G.args = { ... }
    return '++ %s'
  end]])

  set_lines(lines)
  set_cursor(2, 2)
  type_keys('gc', '_')
  eq(get_lines(), { 'aa', '  ++ aa' })
  eq(child.lua_get('_G.args'), { { 2, 3 } })
end

T['Operator']['does not break with loaded tree-sitter'] = function()
  set_lines({ 'set background=dark' })
  child.bo.filetype = 'vim'
  child.lua('vim.treesitter.start()')

  type_keys('gcip')
  eq(get_lines(), { '" set background=dark' })
end

T['Operator']['preserves marks'] = function()
  set_cursor(2, 0)
  -- Set '`<' and '`>' marks
  type_keys('VV')
  type_keys('gc', 'ip')
  child.expect_visual_marks(2, 2)
end

T['Operator']['respects `vim.{g,b}.minicomment_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minicomment_disable = true
    set_cursor(2, 2)
    local lines = get_lines()
    type_keys('gc', 'j')
    eq(get_lines(), lines)
  end,
})

T['Operator']['applies hooks'] = function()
  reload_with_hooks()
  eq(child.bo.commentstring, '# %s')

  set_lines({ 'aa', 'aa' })
  set_cursor(1, 0)
  type_keys('gc', 'ip')
  -- It should allow change of `commentstring` in `pre` hook
  eq(get_lines(), { '// aa', '// aa' })
  --stylua: ignore
  eq(child.lua_get('_G.hook_args'), {
    { 'pre',  { { line_start = 1, line_end = 2, ref_position = { 1, 1 }, action = 'toggle' } } },
    { 'post', { { line_start = 1, line_end = 2, ref_position = { 1, 1 }, action = 'comment' } } },
  })

  -- It should work with dot-repeat
  child.lua('_G.hook_args = {}')
  set_lines({ '// aa', '// aa', '// aa' })
  set_cursor(1, 0)
  type_keys('.')
  eq(get_lines(), { '# // aa', '# // aa', '# // aa' })
  --stylua: ignore
  eq(child.lua_get('_G.hook_args'), {
    { 'pre',  { { line_start = 1, line_end = 3, ref_position = { 1, 1 }, action = 'toggle' } } },
    { 'post', { { line_start = 1, line_end = 3, ref_position = { 1, 1 }, action = 'comment' } } },
  })
end

T['Operator']['stops when hook returns `false`'] = function()
  local lines = { 'aa', 'aa' }
  set_lines(lines)
  set_cursor(1, 0)

  child.lua('MiniComment.config.hooks.pre = function() return false end')
  type_keys('gc', 'ip')
  eq(get_lines(), lines)

  -- Currently can't really check for `hooks.post`
end

T['Operator']['respects `vim.b.minicomment_config`'] = function()
  set_lines({ 'aa', 'aa' })
  set_cursor(1, 0)
  reload_with_hooks()
  child.lua('vim.b.minicomment_config = { hooks = { pre = function() _G.pre_n = _G.pre_n + 10 end } }')

  child.lua([[vim.b.minicomment_config = {
    hooks = {
      pre = function(...) table.insert(_G.hook_args, { 'buf_pre', vim.deepcopy({ ... }) }) end,
    },
  }]])

  type_keys('gc', 'ip')
  --stylua: ignore
  eq(child.lua_get('_G.hook_args'), {
    { 'buf_pre', { { line_start = 1, line_end = 2, ref_position = { 1, 1 }, action = 'toggle' } } },
    { 'post',    { { line_start = 1, line_end = 2, ref_position = { 1, 1 }, action = 'comment' } } },
  })
end

T['Current line'] = new_set()

T['Current line']['works'] = function()
  set_lines(example_lines)
  set_cursor(1, 1)
  type_keys('gcc')
  eq(get_lines(0, 2), { '# aa', ' aa' })

  -- Does not comment empty line
  set_lines(example_lines)
  set_cursor(4, 0)
  type_keys('gcc')
  eq(get_lines(2, 5), { '  aa', '', '  aa' })

  -- Supports `v:count`
  set_lines(example_lines)
  set_cursor(2, 0)
  type_keys('2gcc')
  eq(get_lines(0, 3), { 'aa', ' # aa', ' #  aa' })
end

T['Current line']['works with different mapping'] = function()
  reload_module({ mappings = { comment_line = 'gCC' } })

  set_cursor(1, 0)
  type_keys('gCC')
  eq(get_lines(0, 1), { '# aa' })
end

T['Current line']['respects tree-sitter injections'] = function()
  -- NOTE: This leverages bundled Vimscript and Lua tree-sitter parsers
  local lines = {
    'set background=dark',
    'lua << EOF',
    'print(1)',
    'EOF',
  }
  set_lines(lines)
  child.bo.filetype = 'vim'
  child.lua('vim.treesitter.start()')

  set_cursor(1, 0)
  type_keys('gcc')
  eq(get_lines(), { '" set background=dark', 'lua << EOF', 'print(1)', 'EOF' })

  -- Should work with dot-repeat
  set_cursor(3, 0)
  type_keys('.')
  eq(get_lines(), { '" set background=dark', 'lua << EOF', '-- print(1)', 'EOF' })
end

T['Current line']["computes local 'commentstring' based on cursor position"] = function()
  local lines = {
    'lua << EOF',
    '  print(1)',
    'EOF',
  }
  set_lines(lines)
  child.bo.filetype = 'vim'
  child.lua('vim.treesitter.start()')

  set_cursor(1, 0)
  type_keys('gcc')
  eq(get_lines()[1], '" lua << EOF')

  set_lines(lines)
  set_cursor(2, 2)
  type_keys('gcc')
  eq(get_lines()[2], '  -- print(1)')
end

T['Current line']['allows dot-repeat'] = function()
  set_lines(example_lines)
  set_cursor(1, 1)
  type_keys('gcc')
  type_keys('.')
  eq(get_lines(), example_lines)

  -- Not immediate dot-repeat
  set_lines(example_lines)
  set_cursor(1, 1)
  type_keys('gcc')
  set_cursor(7, 0)
  type_keys('.')
  eq(get_lines(6, 7), { '# aa' })
end

T['Current line']['applies hooks'] = function()
  reload_with_hooks()
  eq(child.bo.commentstring, '# %s')

  set_lines({ 'aa', 'aa' })
  set_cursor(1, 0)
  type_keys('gcc')
  -- It should allow change of `commentstring` in `pre` hook
  eq(get_lines(), { '// aa', 'aa' })
  --stylua: ignore
  eq(child.lua_get('_G.hook_args'), {
    { 'pre',  { { line_start = 1, line_end = 1, ref_position = { 1, 1 }, action = 'toggle' } } },
    { 'post', { { line_start = 1, line_end = 1, ref_position = { 1, 1 }, action = 'comment' } } },
  })

  -- It should work with dot-repeat
  child.lua('_G.hook_args = {}')
  set_lines({ '// aa', 'aa' })
  set_cursor(1, 0)
  type_keys('.')
  eq(get_lines(), { '# // aa', 'aa' })
  --stylua: ignore
  eq(child.lua_get('_G.hook_args'), {
    { 'pre',  { { line_start = 1, line_end = 1, ref_position = { 1, 1 }, action = 'toggle' } } },
    { 'post', { { line_start = 1, line_end = 1, ref_position = { 1, 1 }, action = 'comment' } } },
  })
end

T['Current line']['respects `vim.b.minicomment_config`'] = function()
  set_lines({ 'aa', 'aa' })
  set_cursor(1, 0)
  reload_with_hooks()
  child.lua([[vim.b.minicomment_config = {
    hooks = {
      pre = function(...) table.insert(_G.hook_args, { 'buf_pre', vim.deepcopy({ ... }) }) end,
    },
  }]])

  type_keys('gcc')
  --stylua: ignore
  eq(child.lua_get('_G.hook_args'), {
    { 'buf_pre', { { line_start = 1, line_end = 1, ref_position = { 1, 1 }, action = 'toggle' } } },
    { 'post',    { { line_start = 1, line_end = 1, ref_position = { 1, 1 }, action = 'comment' } } },
  })
end

T['Textobject'] = new_set()

T['Textobject']['works'] = function()
  set_lines({ 'aa', '# aa', '# aa', 'aa' })
  set_cursor(2, 0)
  type_keys('d', 'gc')
  eq(get_lines(), { 'aa', 'aa' })
end

T['Textobject']['does nothing when not inside textobject'] = function()
  local validate_no_action = function(lines, keys, pos)
    set_lines(lines)
    set_cursor(unpack(pos))
    type_keys(keys, 'gc')
    eq(get_lines(), lines)
  end

  -- Should not treat blank lines as part of textobject by default
  local blanks_between_comments = { '# aa', '', '', '# aa' }

  -- Comment operator
  -- Main problem here at time of writing happened while calling `gc` on
  -- comment textobject when not on comment line. This sets `]` mark right to
  -- the left of `[` (but not when cursor in (1, 0)).
  validate_no_action(example_lines, 'gc', { 1, 1 })
  validate_no_action(example_lines, 'gc', { 2, 2 })
  validate_no_action(blanks_between_comments, 'gc', { 2, 1 })
  validate_no_action(blanks_between_comments, 'gc', { 3, 1 })

  -- Builtin operators
  validate_no_action(example_lines, 'd', { 1, 1 })
  validate_no_action(example_lines, 'd', { 2, 2 })
  validate_no_action(blanks_between_comments, 'd', { 2, 1 })
  validate_no_action(blanks_between_comments, 'd', { 3, 1 })

  -- Doesn't work (but should) because both `[` and `]` are set to (1, 0)
  -- (instead of more reasonable (1, -1) or (0, 2147483647)).
  -- validate_no_action(1, 0)
end

T['Textobject']['works with different mapping'] = function()
  reload_module({ mappings = { textobject = 'gC' } })

  set_lines({ 'aa', '# aa', '# aa', 'aa' })
  set_cursor(2, 0)
  type_keys('d', 'gC')
  eq(get_lines(), { 'aa', 'aa' })

  -- Should work in Visual mode as it differs from `comment_visual` mapping
  set_lines({ 'aa', '# bb', '# cc', '# dd', 'ee' })
  set_cursor(3, 0)
  type_keys('v', 'gC', 'd')
  eq(get_lines(), { 'aa', 'ee' })
end

T['Textobject']['respects tree-sitter injections'] = function()
  -- NOTE: This leverages bundled Vimscript and Lua tree-sitter parsers
  local lines = {
    '" set background=dark',
    '" set termguicolors',
    'lua << EOF',
    '-- print(1)',
    '-- print(2)',
    'EOF',
  }
  set_lines(lines)
  child.bo.filetype = 'vim'
  child.lua('vim.treesitter.start()')

  set_cursor(1, 0)
  type_keys('dgc')
  eq(get_lines(), { 'lua << EOF', '-- print(1)', '-- print(2)', 'EOF' })

  -- Should work with dot-repeat
  set_cursor(2, 0)
  type_keys('.')
  eq(get_lines(), { 'lua << EOF', 'EOF' })
end

T['Textobject']['allows dot-repeat'] = function()
  set_lines({ 'aa', '# aa', '# aa', 'aa', '# aa' })
  set_cursor(2, 0)
  type_keys('d', 'gc')
  set_cursor(3, 0)
  type_keys('.')
  eq(get_lines(), { 'aa', 'aa' })
end

T['Textobject']['respects `config.options.start_of_line`'] = function()
  child.lua('MiniComment.config.options.start_of_line = true')

  local lines = { ' # aa', '  # aa', '# aa', '#  aa' }
  set_lines(lines)

  set_cursor(1, 0)
  type_keys('d', 'gc')
  eq(get_lines(), lines)

  set_cursor(3, 0)
  type_keys('d', 'gc')
  eq(get_lines(), { ' # aa', '  # aa' })
end

T['Textobject']['respects `config.options.ignore_blank_line`'] = function()
  child.lua('MiniComment.config.options.ignore_blank_line = true')

  local validate = function(lines_before, cursor_line, lines_after)
    set_lines(lines_before)
    set_cursor(cursor_line, 0)
    type_keys('d', 'gc')
    eq(get_lines(), lines_after)
  end

  local lines = { 'aa', '# bb', '', ' ', '# dd', '# ee', '\t', '# gg', 'hh' }
  local lines_without_comment = { 'aa', 'hh' }
  validate(lines, 1, lines)
  validate(lines, 2, lines_without_comment)
  validate(lines, 3, lines_without_comment)
  validate(lines, 4, lines_without_comment)
  validate(lines, 5, lines_without_comment)
  validate(lines, 6, lines_without_comment)
  validate(lines, 7, lines_without_comment)
  validate(lines, 8, lines_without_comment)
  validate(lines, 9, lines)

  lines = { '# aa', '', ' ', 'dd', '', '\t', '# gg' }
  validate(lines, 1, { '', ' ', 'dd', '', '\t', '# gg' })
  validate(lines, 2, lines)
  validate(lines, 3, lines)
  validate(lines, 4, lines)
  validate(lines, 5, lines)
  validate(lines, 6, lines)
  validate(lines, 7, { '# aa', '', ' ', 'dd', '', '\t' })

  lines = { '# aa', '', ' ', '\t', '# ee' }
  lines_without_comment = { '' }
  validate(lines, 1, lines_without_comment)
  validate(lines, 2, lines_without_comment)
  validate(lines, 3, lines_without_comment)
  validate(lines, 4, lines_without_comment)
  validate(lines, 5, lines_without_comment)

  -- Should not recognize blank lines before/after as textobject
  lines = { 'aa', '', ' ', '# dd', '', ' ', '# gg', '', '\t', 'jj' }
  lines_without_comment = { 'aa', '', ' ', '', '\t', 'jj' }
  validate(lines, 2, lines)
  validate(lines, 3, lines)
  validate(lines, 4, lines_without_comment)
  validate(lines, 5, lines_without_comment)
  validate(lines, 6, lines_without_comment)
  validate(lines, 7, lines_without_comment)
  validate(lines, 8, lines)
  validate(lines, 9, lines)

  lines = { '', ' ', '# dd', '', '\t' }
  lines_without_comment = { '', ' ', '', '\t' }
  validate(lines, 1, lines)
  validate(lines, 2, lines)
  validate(lines, 3, lines_without_comment)
  validate(lines, 4, lines)
  validate(lines, 5, lines)

  -- Should work in buffer with only blank lines
  reload_with_hooks()
  child.lua('MiniComment.config.options.ignore_blank_line = true')
  lines = { '', ' ', '\t', '' }
  validate(lines, 2, lines)
  eq(
    child.lua_get('_G.hook_args'),
    { { 'pre', { { action = 'textobject' } } }, { 'post', { { action = 'textobject' } } } }
  )
end

T['Textobject']['respects `vim.{g,b}.minicomment_disable`'] = new_set({
  parametrize = { { 'g' }, { 'b' } },
}, {
  test = function(var_type)
    child[var_type].minicomment_disable = true
    local lines = { 'aa', '# aa', '# aa', 'aa' }
    set_lines(lines)
    set_cursor(2, 0)
    type_keys('d', 'gc')
    eq(get_lines(), lines)
  end,
})

T['Textobject']['applies hooks'] = function()
  -- It should allow change of `commentstring` in `pre` hook
  reload_with_hooks()
  eq(child.bo.commentstring, '# %s')

  local validate = function(lines_before, keys, lines_after, ref_hook_args)
    child.lua('_G.hook_args = {}')
    set_lines(lines_before)
    set_cursor(1, 0)
    type_keys(keys)
    eq(get_lines(), lines_after)
    eq(child.lua_get('_G.hook_args'), ref_hook_args)
  end

  local ref_args = {
    { 'pre', { { action = 'textobject' } } },
    { 'post', { { line_start = 1, line_end = 1, action = 'textobject' } } },
  }
  validate({ '// aa', 'bb' }, { 'd', 'gc' }, { 'bb' }, ref_args)

  -- It should work with dot-repeat
  validate({ '# aa', 'bb' }, { '.' }, { 'bb' }, ref_args)

  -- Correctly not detecting absence of comment textobject should still be
  -- considered a successful usage of a textobject
  ref_args = { { 'pre', { { action = 'textobject' } } }, { 'post', { { action = 'textobject' } } } }
  validate({ 'aa', 'bb' }, { 'd', 'gc' }, { 'aa', 'bb' }, ref_args)
end

T['Textobject']['respects `vim.b.minicomment_config`'] = function()
  reload_with_hooks()
  child.lua([[vim.b.minicomment_config = {
    hooks = {
      pre = function(...) table.insert(_G.hook_args, { 'buf_pre', vim.deepcopy({ ... }) }) end,
    },
  }]])

  set_lines({ '// aa', 'aa' })
  set_cursor(1, 0)
  type_keys('d', 'gc')
  eq(
    child.lua_get('_G.hook_args'),
    { { 'buf_pre', { { action = 'textobject' } } }, { 'post', { { action = 'textobject' } } } }
  )
end

return T
