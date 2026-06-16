local new_set = MiniTest.new_set

local T = new_set()

_G.log = {}
local log = function(msg) table.insert(_G.log, msg) end
local logging = function(msg)
  return function() log(msg) end
end
local erroring = function(msg)
  return function()
    log(msg)
    error('Error: ' .. msg, 0)
  end
end

T['n_retry defaults to 1'] = erroring('default')

T['should override'] = new_set({ n_retry = 2 })

T['should override']['case'] = erroring('should override')

T['should override']['nested'] = new_set({ n_retry = 3 })

T['should override']['nested']['case'] = erroring('more override')

local n1 = 0
T['retries until first success'] = new_set({ n_retry = 10 }, {
  test = function()
    n1 = n1 + 1
    log('first success #' .. n1)
    if n1 < 3 then error() end
  end,
})

local n2 = 0
T['reports latest error'] = new_set({ n_retry = 3 }, {
  test = function()
    n2 = n2 + 1
    log('latest error #' .. n2)
    error('Error #' .. n2, 0)
  end,
})

T['does not retry hooks'] = new_set({
  hooks = {
    pre_once = erroring('no retry pre_once'),
    pre_case = erroring('no retry pre_case'),
    post_case = erroring('no retry post_case'),
    post_once = erroring('no retry post_once'),
  },
  n_retry = 2,
}, { test = logging('Should not be present because there were hook errors') })

T['calls all `pre_case` and `post_case` hooks on case retry'] = new_set({
  hooks = {
    pre_once = logging('outer pre_once'),
    pre_case = logging('outer pre_case'),
    post_case = logging('outer post_case'),
    post_once = logging('outer post_once'),
  },
  -- Should ignore this `n_retry` when executing hooks on retry of cases from
  -- inner set with its own `n_retry`
  n_retry = 10,
})

T['calls all `pre_case` and `post_case` hooks on case retry']['inner'] = new_set({
  hooks = {
    pre_once = logging('inner pre_once'),
    pre_case = logging('inner pre_case'),
    post_case = logging('inner post_case'),
    post_once = logging('inner post_once'),
  },
  n_retry = 2,
})

T['calls all `pre_case` and `post_case` hooks on case retry']['inner']['case'] = erroring('hook exec case')

T['screenshot number'] = new_set({ n_retry = 2 }, {
  test = function()
    -- Should compute default path with proper screenshot suffix
    -- Basically a test that cached number of screenshots is reset before
    -- *every* try and not only before first try
    local child = MiniTest.new_child_neovim()
    child.start()
    child.o.lines, child.o.columns = 10, 15

    log('screenshot')
    MiniTest.expect.reference_screenshot(child.get_screenshot())
    error('Expected error')
  end,
})

T['does not retry skipping'] = new_set({ n_retry = 2 }, {
  test = function()
    log('skip')
    MiniTest.skip()
  end,
})

T['works for every parametrize entry'] = new_set({
  parametrize = { { 1 }, { 2 } },
  n_retry = 2,
}, {
  test = function(arg)
    log('parameter ' .. arg)
    error()
  end,
})

T['updates state on every retry'] = new_set({
  hooks = {
    pre_once = function() end,
    pre_case = function() end,
    post_case = function() end,
    post_once = function() end,
  },
  n_retry = 2,
}, { test = function() error() end })

return T
