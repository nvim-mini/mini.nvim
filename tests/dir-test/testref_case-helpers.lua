local T = MiniTest.new_set()

local finally_with_error, finally_no_error = false, false

T['finally() with error'] = function()
  MiniTest.finally(function() finally_with_error = true end)
  error()
end

T['finally() with error; check'] = function() MiniTest.expect.equality(finally_with_error, true) end

T['finally() no error'] = function()
  MiniTest.finally(function() finally_no_error = true end)
  local res = true
  return res
end

T['finally() no error; check'] = function() MiniTest.expect.equality(finally_no_error, true) end

_G.finally_log = {}
T['finally() can be called several times in same function'] = function()
  MiniTest.finally(function() table.insert(_G.finally_log, 'one') end)
  MiniTest.finally(function() table.insert(_G.finally_log, 'two') end)
end

T['skip(); no message'] = function()
  MiniTest.skip()
  error('This error should not take effect')
end

T['skip(); with message'] = function()
  MiniTest.skip('This is a custom skip message')
  error('This error should not take effect')
end

local skip_helper = function() MiniTest.skip('Skip from helper') end
T['skip() can be called from helper'] = function() skip_helper() end

T['skip() can be called in `pre_case` hooks'] = MiniTest.new_set({
  hooks = { pre_case = function() MiniTest.skip('Should skip case') end },
})

T['skip() can be called in `pre_case` hooks']['skip one'] = function() error() end
T['skip() can be called in `pre_case` hooks']['skip two'] = function() error() end

T['skip() has no effect in not `pre_case` hooks'] = MiniTest.new_set({
  hooks = {
    pre_once = function() MiniTest.skip('pre_once') end,
    post_case = function() MiniTest.skip('post_case') end,
    post_once = function() MiniTest.skip('post_once') end,
  },
}, { ['skip() in other hooks'] = function() error() end })

T['add_note()'] = MiniTest.new_set({
  hooks = {
    pre_once = function() MiniTest.add_note('pre_once') end,
    pre_case = function() MiniTest.add_note('pre_case') end,
    post_case = function() MiniTest.add_note('post_case') end,
    post_once = function() MiniTest.add_note('post_once') end,
  },
}, { ['add_note() case'] = function() MiniTest.add_note('test case') end })

return T
