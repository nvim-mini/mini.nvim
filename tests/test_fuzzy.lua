local helpers = dofile('tests/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
local load_module = function(config) child.mini_load('fuzzy', config) end
local unload_module = function() child.mini_unload('fuzzy') end
local reload_module = function(config) child.mini_reload('fuzzy', config) end

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      load_module()
    end,
    post_once = child.stop,
  },
  n_retry = helpers.get_n_retry(1),
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  -- Global variable
  eq(child.lua_get('type(_G.MiniFuzzy)'), 'table')
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniFuzzy.config)'), 'table')

  -- Check default values
  eq(child.lua_get('MiniFuzzy.config.cutoff'), 100)
end

T['setup()']['respects `config` argument'] = function()
  unload_module()
  load_module({ cutoff = 300 })
  eq(child.lua_get('MiniFuzzy.config.cutoff'), 300)
end

T['setup()']['validates `config` argument'] = function()
  unload_module()

  local expect_config_error = function(config, name, target_type)
    expect.error(function() load_module(config) end, vim.pesc(name) .. '.*' .. vim.pesc(target_type))
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ cutoff = 'a' }, 'cutoff', 'number')
  expect_config_error({ cutoff = 0 }, 'cutoff', 'not less than 1')
end

T['match()'] = new_set()

T['match()']['works'] = function()
  eq(
    child.lua_get([[MiniFuzzy.match('gettime', 'get_cur_time')]]),
    { positions = { 1, 2, 3, 9, 10, 11, 12 }, score = 1201 }
  )
  eq(child.lua_get([[MiniFuzzy.match('gettime', 'time_get')]]), { score = -1 })
end

T['match()']['handles cases when match is impossible'] = function()
  -- Smaller candidate
  eq(child.lua_get([[MiniFuzzy.match('a', '')]]), { score = -1 })
  eq(child.lua_get([[MiniFuzzy.match('ab', 'a')]]), { score = -1 })

  -- Empty word
  eq(child.lua_get([[MiniFuzzy.match('', 'abc')]]), { positions = {}, score = -1 })
end

local validate_match = function(word, candidate, positions)
  local output = child.lua_get('MiniFuzzy.match(...)', { word, candidate })
  eq(output.positions, positions)
end

T['match()']['uses smart case'] = function()
  validate_match('ab', 'aB', { 1, 2 })
  validate_match('ab', 'Ab', { 1, 2 })
  validate_match('ab', 'AB', { 1, 2 })

  validate_match('Ab', 'ab', nil)
  validate_match('Ab', 'Ab', { 1, 2 })
  validate_match('Ab', 'AB', nil)
end

T['match()']['respects order of letters'] = function() validate_match('abc', 'bcacbac', { 3, 5, 7 }) end

T['match()']['handles special characters'] = function()
  validate_match('(.+*%-)', 'a(a.a+a*a%a-a)', { 2, 4, 6, 8, 10, 12, 14 })
end

T['match()']['finds best match in presence of many'] = function()
  validate_match('ab', 'a__b_a__b_ab', { 11, 12 })
  validate_match('ab', 'a__b_ab_a__b', { 6, 7 })
  validate_match('ab', 'ab_a__b_a__b', { 1, 2 })

  validate_match('ab', 'ab__ab', { 1, 2 })
end

T['match()']['has allowed limitations'] = function()
  -- Output may be unintuitive if there are several optimal matches with same
  -- score (same width and start position)
  validate_match('abc', 'abbbc', { 1, 4, 5 })
end

local validate_score = function(word, candidate, score)
  local output = child.lua_get('MiniFuzzy.match(...)', { word, candidate })
  eq(output.score, score)
end

T['match()']['computes correct score'] = function()
  validate_score('a', 'a', 101)
  validate_score('a', '_a', 102)
  validate_score('a', '__a', 103)

  validate_score('ab', 'ab_', 201)
  validate_score('ab', '_ab', 202)
  validate_score('ab', 'a_b', 301)

  validate_score('abc', 'abc__', 301)
  validate_score('abc', '_abc_', 302)
  validate_score('abc', '__abc', 303)
  validate_score('abc', 'a_bc_', 401)
  validate_score('abc', 'ab_c_', 401)
  validate_score('abc', '_a_bc', 402)
  validate_score('abc', '_ab_c', 402)
  validate_score('abc', 'a__bc', 501)
  validate_score('abc', 'a_b_c', 501)
  validate_score('abc', 'ab__c', 501)

  -- No match
  validate_score('a', 'bcd', -1)
  validate_score('ab', 'ba', -1)
end

T['match()']['respects `config.cutoff`'] = function()
  child.lua('MiniFuzzy.config.cutoff = 10')
  validate_score('ab', 'ab_', 21)

  -- Should also use buffer local config
  child.b.minifuzzy_config = { cutoff = 5 }
  validate_score('ab', 'ab_', 11)
end

T['match()']['treats features bigger than `config.cutoff` the same'] = function()
  reload_module({ cutoff = 4 })

  validate_score('a', '__a', 7)
  validate_score('a', '___a', 8)
  validate_score('a', '____a', 8)

  validate_score('ab', 'a_b', 13)
  validate_score('ab', 'a__b', 17)
  validate_score('ab', 'a___b', 17)
end

T['filtersort()'] = new_set()

local filtersort = function(...) return child.lua_get('{ MiniFuzzy.filtersort(...) }', { ... }) end

local validate_filtersort = function(word, candidate_array, matched_candidates)
  local output = filtersort(word, candidate_array)
  eq(output[1], matched_candidates)
end

T['filtersort()']['works'] = function()
  eq(filtersort('a', { '_a', '__a', 'b', 'a' }), { { 'a', '_a', '__a' }, { 4, 1, 2 } })
  eq(filtersort('a', {}), { {}, {} })
end

T['filtersort()']['uses smart case'] = function()
  validate_filtersort('ab', { 'ab', 'aB', 'Ab', 'AB' }, { 'ab', 'aB', 'Ab', 'AB' })
  validate_filtersort('Ab', { 'ab', 'aB', 'Ab', 'AB' }, { 'Ab' })
end

T['filtersort()']['preserves original order with equal matching score'] = function()
  validate_filtersort(
    'abc',
    { 'ab__c', 'a__bc', 'a_b_c', '__abc', 'abc__' },
    { 'abc__', '__abc', 'ab__c', 'a__bc', 'a_b_c' }
  )
end

T['filtersort()']['works with empty arguments'] = function()
  validate_filtersort('', { 'a', 'b', '_a' }, { 'a', 'b', '_a' })
  validate_filtersort('a', {}, {})
end

T['process_lsp_items()'] = new_set()

local new_item = function(filterText, label, newText, insertText)
  return { filterText = filterText, label = label, textEdit = { newText = newText }, insertText = insertText }
end

local process_lsp_items = function(...) return child.lua_get('MiniFuzzy.process_lsp_items(...)', { ... }) end

T['process_lsp_items()']['works'] = function()
  local validate = function(items) eq(process_lsp_items(items, 'a'), { items[3], items[2], items[1] }) end
  validate({ new_item('___a'), new_item('__a'), new_item('_a') })
  validate({ new_item(nil, '___a'), new_item(nil, '__a'), new_item(nil, '_a') })

  -- Should match all as is for empty string `base`
  local items = { new_item(nil, '___a'), new_item(nil, '__a'), new_item(nil, '_a') }
  eq(process_lsp_items(items, ''), items)
end

T['process_lsp_items()']['correctly extracts candidate from fields'] = function()
  -- filterText > label; no other fields should matter
  local validate = function(items) eq(process_lsp_items(items, 'a'), { items[2], items[1] }) end

  validate({ new_item('__a', '_a'), new_item('_a', '__a') })
  validate({ new_item('__a', nil, '_a'), new_item('_a', nil, '__a') })
  validate({ new_item(nil, '__a', '_a'), new_item(nil, '_a', '__a') })
  validate({ new_item('__a', nil, nil, '_a'), new_item('_a', nil, nil, '__a') })
  validate({ new_item(nil, '__a', nil, '_a'), new_item(nil, '_a', nil, '__a') })
end

T['get_telescope_sorter()'] = new_set()

T['get_telescope_sorter()']['is present'] = function() eq(child.lua_get('MiniFuzzy.get_telescope_sorter ~= nil'), true) end

return T
