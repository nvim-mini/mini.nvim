# How to test with 'mini.test'

Writing tests for Neovim Lua plugin is hard. Writing good tests for Neovim Lua plugin is even harder. The 'mini.test' module is designed to make it reasonably easier while still allowing lots of flexibility. It deliberately favors a more verbose and program-like style of writing tests, opposite to "human readable, DSL like" approach of [nvim-lua/plenary.nvim](https://github.com/nvim-lua/plenary.nvim) ("busted-style testing" from [Olivine-Labs/busted](https://github.com/Olivine-Labs/busted)). Although the latter is also possible.

This file is intended as a hands-on introduction to 'mini.test' with examples. For more details, see [its documentation](doc/mini-test.txt) and tests of this plugin's modules.

General approach of writing test files:

- Organize tests in separate Lua files.
- Each file should be associated with a test set table (output of `MiniTest.new_set()`). Recommended approach is to create it manually in each test file and then return it.
- Each test action should be defined in separate function assign to an entry of test set.
- It is strongly encouraged to use custom Neovim processes to do actual testing inside test action. See [Using child process](#using-child-process).

**NOTES**:

- All commands are assumed to be executed with current working directory being a root of your Neovim plugin project. That is both for shell and Neovim commands.
- All paths are assumed to be relative to current working directory.

## Example plugin

In this file we will be testing 'hello_lines' plugin (once some basic concepts are introduced). It will have functionality to add prefix 'Hello ' to lines implemented in a single file 'lua/hello_lines/init.lua':

<details><summary>'lua/hello_lines/init.lua'</summary>

```lua
local M = {}

--- Prepend 'Hello ' to every element
---@param lines table Array. Default: { 'world' }.
---@return table Array of strings.
M.compute = function(lines)
  lines = lines or { 'world' }
  return vim.tbl_map(function(x) return 'Hello ' .. tostring(x) end, lines)
end

local ns_id = vim.api.nvim_create_namespace('hello_lines')

--- Set lines with highlighted 'Hello ' prefix
---@param buf_id number Buffer handle where lines should be set. Default: 0.
---@param lines table Array. Default: { 'world' }.
M.set_lines = function(buf_id, lines)
  buf_id = buf_id or 0
  lines = lines or { 'world' }
  vim.api.nvim_buf_clear_namespace(buf_id, ns_id, 0, -1)
  vim.api.nvim_buf_set_lines(buf_id or 0, 0, -1, true, M.compute(lines))
  for i = 1, #lines do
    local extmark_opts = { end_row = i - 1, end_col = 5, hl_group = 'Special' }
    vim.api.nvim_buf_set_extmark(buf_id, ns_id, i - 1, 0, extmark_opts)
  end
end

return M
```

</details>

## Quick demo

Here is a quick demo of how tests with 'mini.test' look like:

<details><summary>'tests/test_hello_lines.lua'</summary>

```lua
-- Define helper aliases
local new_set = MiniTest.new_set
local expect, eq = MiniTest.expect, MiniTest.expect.equality

-- Create (but not start) child Neovim object
local child = MiniTest.new_child_neovim()

-- Define main test set of this file
local T = new_set({
  -- Register hooks
  hooks = {
    -- This will be executed before every (even nested) case
    pre_case = function()
      -- Restart child process with custom 'init.lua' script
      child.restart({ '-u', 'scripts/minimal_init.lua' })
      -- Load tested plugin
      child.lua([[M = require('hello_lines')]])
    end,
    -- This will be executed one after all tests from this set are finished
    post_once = child.stop,
  },
})

-- Test set fields define nested structure
T['compute()'] = new_set()

-- Define test action as callable field of test set.
-- If it produces error - test fails.
T['compute()']['works'] = function()
  -- Execute Lua code inside child process, get its result and compare with
  -- expected result
  eq(child.lua_get([[M.compute({'a', 'b'})]]), { 'Hello a', 'Hello b' })
end

T['compute()']['uses correct defaults'] = function()
  eq(child.lua_get([[M.compute()]]), { 'Hello world' })
end

-- Make parametrized tests. This will create three copies of each case
T['set_lines()'] = new_set({ parametrize = { {}, { 0, { 'a' } }, { 0, { 1, 2, 3 } } } })

-- Use arguments from test parametrization
T['set_lines()']['works'] = function(buf_id, lines)
  -- Directly modify some options to make better test
  child.o.lines, child.o.columns = 10, 20
  child.bo.readonly = false

  -- Execute Lua code without returning value
  child.lua('M.set_lines(...)', { buf_id, lines })

  -- Test screen state. On first run it will automatically create reference
  -- screenshots with text and look information in predefined location. On
  -- later runs it will compare current screenshot with reference. Will throw
  -- informative error with helpful information if they don't match exactly.
  expect.reference_screenshot(child.get_screenshot())
end

-- Return test set which will be collected and execute inside `MiniTest.run()`
return T
```

</details>

## File organization

It might be a bit overwhelming. It actually is for most of the people. However, it should be done once and then you rarely need to touch it.

Overview of full file structure used in for testing 'hello_lines' plugin:

```
.
├── deps
│   └── mini.nvim # Mandatory
├── lua
│   └── hello_lines
│       └── init.lua # Mandatory
├── Makefile # Recommended
├── scripts
│   ├── minimal_init.lua # Mandatory
│   └── minitest.lua # Recommended
└── tests
    └── test_hello_lines.lua # Mandatory
```

To write tests, you'll need these files:

Mandatory:

- **Your Lua plugin in 'lua' directory**. Here we will be testing 'hello_lines' plugin.

- **Test files**. By default they should be Lua files located in 'tests/' directory and named with 'test_' prefix. For example, we will write everything in 'test_hello_lines.lua'. It is usually a good idea to follow this template (will be assumed for the rest of this file):

    <details><summary>Template for test files</summary>

    ```lua
    local new_set = MiniTest.new_set
    local expect, eq = MiniTest.expect, MiniTest.expect.equality

    local T = new_set()

    -- Actual tests definitions will go here

    return T
    ```

    </details>

- **'mini.nvim' dependency**. It is needed to use its 'mini.test' module. Proposed way to store it is in 'deps/mini.nvim' directory. Create it with `git`:

    ```bash
    mkdir -p deps
    git clone --filter=blob:none https://github.com/nvim-mini/mini.nvim deps/mini.nvim
    ```

- **Manual Neovim startup file** (a.k.a 'init.lua') with proposed path 'scripts/minimal_init.lua'. It will be used to ensure that Neovim processes can recognize your tested plugin and 'mini.nvim' dependency. Proposed minimal content:

    <details><summary>'scripts/minimal_init.lua'</summary>

    ```lua
    -- Add current directory to 'runtimepath' to be able to use 'lua' files
    vim.cmd([[let &rtp.=','.getcwd()]])

    -- Set up 'mini.test' only when calling headless Neovim (like with `make test`)
    if #vim.api.nvim_list_uis() == 0 then
      -- Add 'mini.nvim' to 'runtimepath' to be able to use 'mini.test'
      -- Assumed that 'mini.nvim' is stored in 'deps/mini.nvim'
      vim.cmd('set rtp+=deps/mini.nvim')

      -- Set up 'mini.test'
      require('mini.test').setup()
    end
    ```

    </details>

Recommended:

- **Makefile**. In order to simplify running tests from shell and inside Continuous Integration services (like Github Actions), it is recommended to define Makefile. It will define steps for running tests. Proposed template:

    <details><summary>Template for Makefile</summary>

    ```
    # Run all test files
    test: deps/mini.nvim
    	nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run()"

    # Run test from file at `$FILE` environment variable
    test_file: deps/mini.nvim
    	nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run_file('$(FILE)')"

    # Download 'mini.nvim' to use its 'mini.test' testing module
    deps/mini.nvim:
    	@mkdir -p deps
    	git clone --filter=blob:none https://github.com/nvim-mini/mini.nvim $@
    ```

    </details>

- **'mini.test' script** at 'scripts/minitest.lua'. Use it to customize what is tested (which files, etc.) and how. Usually not needed, but otherwise should have some variant of a call to `MiniTest.run()`.

## Running tests

The 'mini.test' module out of the box supports two major ways of running tests:

- **Interactive**. All test files will be run directly inside current Neovim session. This proved to be very useful for debugging while writing tests. To run tests, simply execute `:lua MiniTest.run()` / `:lua MiniTest.run_file()` / `:lua MiniTest.run_at_location()` (assuming, you already have 'mini.test' set up with `require('mini.test').setup()`). With default configuration this will result into floating window with information about results of test execution. Press `q` to close it. **Note**: Be careful though, as it might affect your current setup. To avoid this, [use child processes](#using-child-process) inside tests.
- **Headless** (from shell). Start headless Neovim process with proper startup file and execute `lua MiniTest.run()`. Assuming full file organization from previous section, this can be achieved with `make test`. This will show information about results of test execution directly in shell.

## Basics

These sections will show some basic capabilities of 'mini.test' and how to use them. In all examples code blocks represent some whole test file (like 'tests/test_basics.lua').

### First test

A test is defined as function assigned to a field of test set. If it throws error, test has failed. Test file should return single test set. Here is an example:

```lua
local T = MiniTest.new_set()

T['works'] = function()
  local x = 1 + 1
  if x ~= 2 then
    error('`x` is not equal to 2')
  end
end

return T
```

Writing `if .. error() .. end` is too tiresome. That is why 'mini.test' comes with very minimal but usually quite enough set of *expectations*: `MiniTest.expect`. They display the intended expectation between objects and will throw error with informative message if it doesn't hold. Here is a rewritten previous example:

```lua
local T = MiniTest.new_set()

T['works'] = function()
  local x = 1 + 1
  MiniTest.expect.equality(x, 2)
end

return T
```

Test sets can be nested. This will be useful in combination with [hooks](#hooks) and [parametrization](#test-parametrization):

```lua
local T = MiniTest.new_set()

T['big scope'] = new_set()

T['big scope']['works'] = function()
  local x = 1 + 1
  MiniTest.expect.equality(x, 2)
end

T['big scope']['also works'] = function()
  local x = 2 + 2
  MiniTest.expect.equality(x, 4)
end

T['out of scope'] = function()
  local x = 3 + 3
  MiniTest.expect.equality(x, 6)
end

return T
```

**NOTE**: 'mini.test' supports emulation of busted-style testing by default. So previous example can be written like this:

```lua
describe('big scope', function()
  it('works', function()
    local x = 1 + 1
    MiniTest.expect.equality(x, 2)
  end)

  it('also works', function()
    local x = 2 + 2
    MiniTest.expect.equality(x, 4)
  end)
end)

it('out of scope', function()
  local x = 3 + 3
  MiniTest.expect.equality(x, 6)
end)

-- NOTE: when using this style, no test set should be returned
```

Although this is possible, the rest of this file will use a recommended test set approach.

### Builtin expectations

These four builtin expectations are the ones used most commonly:

```lua
local T = MiniTest.new_set()
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local x = 1 + 1

-- This is so frequently used that having short alias proved useful
T['expect.equality'] = function()
  eq(x, 2)
end

T['expect.no_equality'] = function()
  expect.no_equality(x, 1)
end

T['expect.error'] = function()
  -- This expectation will pass because function will throw an error
  expect.error(function()
    if x == 2 then error('Deliberate error') end
  end)
end

T['expect.no_error'] = function()
  -- This expectation will pass because function will *not* throw an error
  expect.no_error(function()
    if x ~= 2 then error('This should not be thrown') end
  end)
end

return T
```

### Writing custom expectation

Although you can use `if ... error() ... end` approach, there is `MiniTest.new_expectation()` to simplify this process for some repetitive expectation. Here is an example used in this plugin:

```lua
local T = MiniTest.new_set()

local expect_match = MiniTest.new_expectation(
  -- Expectation subject
  'string matching',
  -- Predicate
  function(str, pattern) return str:find(pattern) ~= nil end,
  -- Fail context
  function(str, pattern)
    return string.format('Pattern: %s\nObserved string: %s', vim.inspect(pattern), str)
  end
)

T['string matching'] = function()
  local x = 'abcd'
  -- This will pass
  expect_match(x, '^a')

  -- This will fail
  expect_match(x, 'x')
end

return T
```

Executing this content from file 'tests/test_basics.lua' will fail with the following message:

```
FAIL in "tests/test_basics.lua | string matching":
  Failed expectation for string matching.
  Pattern: "x"
  Observed string: abcd
  Traceback:
    tests/test_basics.lua:20
```

### Hooks

Hooks are functions that will be called without arguments at predefined stages of test execution. They are defined for a test set. There are four types of hooks:

- **pre_once** - executed before first (filtered) node.
- **pre_case** - executed before each case (even nested).
- **post_case** - executed after each case (even nested).
- **post_once** - executed after last (filtered) node.

Example:

```lua
local new_set = MiniTest.new_set
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = new_set()

local n = 0
local increase_n = function() n = n + 1 end

T['hooks'] = new_set({
  hooks = { pre_once = increase_n, pre_case = increase_n, post_case = increase_n, post_once = increase_n },
})

T['hooks']['work'] = function()
  -- `n` will be increased twice: in `pre_once` and `pre_case`
  eq(n, 2)
end

T['hooks']['work again'] = function()
  -- `n` will be increased twice: in `post_case` from previous case and
  -- `pre_case` before this one
  eq(n, 4)
end

T['after hooks set'] = function()
  -- `n` will be again increased twice: in `post_case` from previous case and
  -- `post_once` after last case in T['hooks'] test set
  eq(n, 6)
end

return T
```

### Test parametrization

One of the distinctive features of 'mini.test' is ability to leverage test parametrization. As hooks, it is a feature of test set.

Example of simple parametrization:

```lua
local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local T = new_set()

-- Each parameter should be an array to allow parametrizing multiple arguments
T['parametrize'] = new_set({ parametrize = { { 1 }, { 2 } } })

-- This will result into two cases. First will fail.
T['parametrize']['works'] = function(x)
  eq(x, 2)
end

-- Parametrization can be nested. Cases are "multiplied" with every combination
-- of parameters.
T['parametrize']['nested'] = new_set({ parametrize = { { '1' }, { '2' } } })

-- This will result into four cases. Two of them will fail.
T['parametrize']['nested']['works'] = function(x, y)
  eq(tostring(x), y)
end

-- Parametrizing multiple arguments
T['parametrize multiple arguments'] = new_set({ parametrize = { { 1, 1 }, { 2, 2 } } })

-- This will result into two cases. Both will pass.
T['parametrize multiple arguments']['works'] = function(x, y)
  eq(x, y)
end

return T
```

### Retry

Some tests can be inherently flaky (can randomly fail even if its tested feature is correct). For example, testing that sequence of events is executed with correct delay between each other. Such tests can work reliably on fast machines, but can spuriously fail on slow ones (like during Continuous Integrations checks) while underlying feature is correct.

To reduce flakiness, there is a feature of test set called `n_retry`: a maximum number of times to retry each its test case until success.

Example of how it can be used:

```lua
local new_set = MiniTest.new_set

local T = new_set()

-- Each case will be attempted until first success at most 5 times
T['n_retry'] = new_set({ n_retry = 5 })

-- With default `n_retry = 1` this case will fail 1 out of 2 runs.
-- With `n_retry = 5` this case will fail 1 out of 32 runs.
T['n_retry']['case'] = function()
  math.randomseed(vim.uv.hrtime())
  assert(math.random() < 0.5)
end

return T
```

### Runtime access to current cases

There is `MiniTest.current` table containing information about "current" test cases. It has `all_cases` and `case` fields with all currently executed tests and *the* current case.

Test case is a single unit of sequential test execution. It contains all information needed to execute test case along with data about its execution. Example:

```lua
local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local T = new_set()

T['MiniTest.current.all_cases'] = function()
  -- A useful hack: show runtime data with expecting it to be something else
  eq(MiniTest.current.all_cases, 0)
end

T['MiniTest.current.case'] = function()
  eq(MiniTest.current.case, 0)
end

return T
```

This will result into following lengthy fails:

<details><summary>Fail information</summary>

```
FAIL in "tests/test_basics.lua | MiniTest.current.all_cases":
  Failed expectation for equality.
  Left: { {
      args = {},
      data = {},
      desc = { "tests/test_basics.lua", "MiniTest.current.all_cases" },
      exec = {
        fails = {},
        notes = {},
        state = "Executing test"
      },
      hooks = {
        post = {},
        pre = {}
      },
      test = <function 1>
    }, {
      args = {},
      data = {},
      desc = { "tests/test_basics.lua", "MiniTest.current.case" },
      hooks = {
        post = {},
        pre = {}
      },
      test = <function 2>
    } }
  Right: 0
  Traceback:
    tests/test_basics.lua:8

FAIL in "tests/test_basics.lua | MiniTest.current.case":
  Failed expectation for equality.
  Left: {
    args = {},
    data = {},
    desc = { "tests/test_basics.lua", "MiniTest.current.case" },
    exec = {
      fails = {},
      notes = {},
      state = "Executing test"
    },
    hooks = {
      post = {},
      pre = {}
    },
    test = <function 1>
  }
  Right: 0
  Traceback:
    tests/test_basics.lua:12
```

</details>

### Case helpers

There are some functions intended to help writing more robust cases: `skip()`, `finally()`, and `add_note()`. The `MiniTest.current` table contains useful information about the current state of tests execution.

Example:

```lua
local T = MiniTest.new_set()

-- `MiniTest.skip()` allows skipping rest of test execution while giving an
-- informative note. This test will pass with notes.
T['skip()'] = function()
  if 1 + 1 == 2 then
    MiniTest.skip('Apparently, 1 + 1 is 2')
  end
  error('1 + 1 is not 2')
end

-- `MiniTest.add_note()` allows adding notes. Final state will have
-- "with notes" suffix.
T['add_note()'] = function()
  MiniTest.add_note('This test is not important.')
  error('Custom error.')
end

-- `MiniTest.finally()` allows registering some function to be executed after
-- this case is finished executing (with or without an error).
T['finally()'] = function()
  -- Add note only if test fails
  MiniTest.finally(function()
    if #MiniTest.current.case.exec.fails > 0 then
      MiniTest.add_note('This test is flaky.')
    end
  end)
  error('Expected error from time to time')
end

return T
```

This will result into following messages:

```
NOTE in "tests/test_basics.lua | skip()": Apparently, 1 + 1 is 2

FAIL in "tests/test_basics.lua | add_note()": tests/test_basics.lua:16: Custom error.
NOTE in "tests/test_basics.lua | add_note()": This test is not important.

FAIL in "tests/test_basics.lua | finally()": tests/test_basics.lua:28: Expected error from time to time
NOTE in "tests/test_basics.lua | finally()": This test is flaky.
```

## Customizing test run

Test run consists from two stages:

- **Collection**. It will source each appropriate file (customizable), combine all test sets into single test set, convert it from hierarchical to sequential form (array of test cases), and filter cases based on customizable predicate.
- **Execution**. It will safely execute array of test cases (with each pre-hooks, test action, post-hooks) one after another in scheduled asynchronous fashion while collecting information about how it went and calling customizable reporter methods.

All configuration goes into `opts` argument of `MiniTest.run()`.

### Collection: custom files and filter

You can customize which files will be sourced and which cases will be later executed. Example:

```lua
local new_set = MiniTest.new_set

local T = new_set()

-- Use `data` field to pass custom information for easier test management
T['fast'] = new_set({ data = { type = 'fast' } })
T['fast']['first test'] = function() end
T['fast']['second test'] = function() end

T['slow'] = new_set({ data = { type = 'slow' } })
T['slow']['first test'] = function() vim.uv.sleep(1000) end
T['slow']['second test'] = function() vim.uv.sleep(1000) end

return T
```

You can run only this file ('tests/test_basics.lua') and only "fast" cases with this call:

```lua
MiniTest.run({
  collect = {
    find_files = function() return { 'tests/test_basics.lua' } end,
    filter_cases = function(case) return case.data.type == 'fast' end,
  }
})
```

### Execution: custom reporter and stop on first error

You can customize execution of test cases with custom reporter (how test results are displayed in real time) and whether to stop execution after the first test case fail/error. Execution doesn't result into any output, instead it updates `MiniTest.current.all_cases` in place: each case gets an `exec` field with information about how its execution went.

Example of showing status summary table in the command line after everything is finished:

```lua
local reporter = {
  -- Other used methods are `start(cases)` and `update(case_num)`
  finish = function()
    local summary = {}
    for _, c in ipairs(MiniTest.current.all_cases) do
      local state = c.exec.state
      summary[state] = (summary[state] or 0) + 1
    end

    print(vim.inspect(summary, { newline = ' ', indent = '' }))
  end,
}

MiniTest.run({ execute = { reporter = reporter } })
```

## Using child process

Main feature of 'mini.test' which makes it different from other Lua testing frameworks is its design towards **custom usage of child Neovim process inside tests**. Ultimately, each test should be done with fresh Neovim process initialized with bare minimum setup (like allowing to load your plugin). To make this easier, there is a dedicated function `MiniTest.new_child_neovim()`. It returns an object with many useful helper methods, like for start/stop/restart, redirected execution (write code in current process, it gets executed in child one), emulating typing keys, **testing screen state**, etc.

### Start/stop/restart

You can start/stop/restart child process associated with this child Neovim object. Current (from which testing is initiated) and child Neovim processes can "talk" to each through RPC messages (see `:h RPC`). It means you can programmatically execute code inside child process, get its output inside current process, and test if it meets your expectation. Child process is headless but fully functioning process which allows you to test things such as extmarks, floating windows, etc.

Although this approach proved to be useful and efficient, it is not ideal. Here are some limitations:
  - Due to current RPC protocol implementation functions and userdata can't be used in both input and output with child process. Indicator of this issue is a `Cannot convert given lua type` error. Usual solution is to move some logic on the side of child process, like create and use global functions (note that they will be "forgotten" after next restart).
  - Sometimes hanging process will occur: it stops executing without any output. Most of the time it is because Neovim process is "blocked", i.e. it waits for user input and won't return from other call. Common causes are active hit-enter-prompt (solution: increase prompt height to a bigger value) or Operator-pending mode (solution: exit it). To mitigate this experience, most helper methods will throw an error if they can deduce that immediate execution will lead to hanging state.

Here is recommended setup for managing child processes. It will make fresh Neovim process before every test case:

```lua
local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      -- Restart child process with custom 'init.lua' script
      child.restart({ '-u', 'scripts/minimal_init.lua' })
      -- Load tested plugin
      child.lua([[M = require('hello_lines')]])
    end,
    -- Stop once all test cases are finished
    post_once = child.stop,
  },
})

-- Define some tests here

return T
```

### Executing Lua code

Previous section already demonstrated that there is a `child.lua()` method. It will execute arbitrary Lua code in the form of a single string. This is basically a wrapper for `vim.api.nvim_exec_lua()`. There is also a convenience wrapper `child.lua_get()` which is essentially a `child.lua('return ' .. s, ...)`. Examples:

```lua
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ '-u', 'scripts/minimal_init.lua' })
      child.lua([[M = require('hello_lines')]])
    end,
    post_once = child.stop,
  },
})

T['lua()'] = MiniTest.new_set()

T['lua()']['works'] = function()
  child.lua('_G.n = 0; _G.n = _G.n + 1')
  eq(child.lua('return _G.n'), 1)
end

T['lua()']['can use tested plugin'] = function()
  eq(child.lua('return M.compute()'), { 'Hello world' })
  eq(child.lua([[return M.compute({'a', 'b'})]]), { 'Hello a', 'Hello b' })
end

T['lua_get()'] = function()
  child.lua('_G.n = 0')
  eq(child.lua_get('_G.n'), child.lua('return _G.n'))
end

return T
```

### Managing Neovim options and state

Although ability to execute arbitrary Lua code is technically enough to write any tests, it gets cumbersome very quickly due it using only string input. That is why there are many convenience helpers with the same idea: write code inside current Neovim process that will be automatically executed same way in child process. Here is the showcase:

```lua
local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ '-u', 'scripts/minimal_init.lua' })
      child.lua([[M = require('hello_lines')]])
    end,
    post_once = child.stop,
  },
})

-- These methods will "redirect" execution to child through `vim.rpcrequest()`
-- and `vim.rpcnotify()` respectively. Any call `child.api.xxx(...)` returns
-- the output of `vim.api.xxx(...)` executed inside child process.
T['api()/api_notify()'] = function()
  -- Set option. For some reason, first buffer is 'readonly' which leads to
  -- high delay in test execution
  child.api.nvim_set_option_value('readonly', false, { buf = 0 })

  -- Set all lines
  child.api.nvim_buf_set_lines(0, 0, -1, true, { 'aaa' })

  -- Get all lines and test with expected ones
  eq(child.api.nvim_buf_get_lines(0, 0, -1, true), { 'aaa' })
end

-- Execute Vimscript with or without capturing its output
T['cmd()/cmd()'] = function()
  child.cmd('hi Comment guifg=#aaaaaa')
  eq(child.cmd_capture('hi Comment'), 'Comment        xxx guifg=#aaaaaa')
end

-- There are redirection tables for most of the main Neovim functionality
T['various redirection tables with methods'] = function()
  eq(child.fn.fnamemodify('hello_lines.lua', ':t:r'), 'hello_lines')
  eq(child.uv.hrtime() > 0, true)
  eq(child.lsp.get_clients(), {})

  -- And more
end

-- There are redirection tables for scoped (buffer, window, etc.) variables
-- You can use them to both set and get values
T['redirection tables for variables'] = function()
  child.b.aaa = true
  eq(child.b.aaa, true)
  eq(child.b.aaa, child.lua_get('vim.b.aaa'))
end

-- There are redirection tables for scoped (buffer, window, etc.) options
-- You can use them to both set and get values
T['redirection tables for options'] = function()
  child.o.lines, child.o.columns = 5, 12
  eq(child.o.lines, 5)
  eq({ child.o.lines, child.o.columns }, child.lua_get('{ vim.o.lines, vim.o.columns }'))
end

return T
```

### Emulate typing keys

Very important part of testing is emulating user typing keys. There is a special `child.type_keys()` helper method for that. Examples:

```lua
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ '-u', 'scripts/minimal_init.lua' })
      child.bo.readonly = false
      child.lua([[M = require('hello_lines')]])
    end,
    post_once = child.stop,
  },
})

local get_lines = function() return child.api.nvim_buf_get_lines(0, 0, -1, true) end

T['type_keys()'] = MiniTest.new_set()

T['type_keys()']['works'] = function()
  -- It can take one string
  child.type_keys('iabcde<Esc>')
  eq(get_lines(), { 'abcde' })
  eq(child.fn.mode(), 'n')

  -- Or several strings which improves readability
  child.type_keys('cc', 'fghij', '<Esc>')
  eq(get_lines(), { 'fghij' })

  -- Or tables of strings (possibly nested)
  child.type_keys({ 'cc', { 'j', 'k', 'l', 'm', 'n' } })
  eq(get_lines(), { 'jklmn' })
end

T['type_keys()']['allows custom delay'] = function()
  -- This adds delay of 500 ms after each supplied string (three times here)
  child.type_keys(500, 'i', 'abcde', '<Esc>')
  eq(get_lines(), { 'abcde' })
end

return T
```

### Test screen state with screenshots

One of the main difficulties in testing Neovim plugins is verifying that something is actually displayed in the way you intend. Like general highlighting, statusline, tabline, sign column, extmarks, etc. Testing screen state with screenshots makes this a lot easier. There is a `child.get_screenshot()` method which basically calls `screenstring()` (`:h screenstring()`) and `screenattr()` (`:h screenattr()`) for every visible cell (row from 1 to 'lines' option, column from 1 to 'columns' option). It then returns screenshot with two layers:

- `text` - "2d array" (row-column) of single characters displayed at particular cells.
- `attr` - "2d array" (row-column) of symbols representing how text is displayed (basically, "coded" appearance/highlighting). They should be used only in relation to each other: same/different symbols for two cells mean same/different visual appearance. Note: there will be false positives if there are more than 94 different attribute values. To make output more portable and visually useful, outputs of `screenattr()` are coded with single character symbols.

Couple of caveats:

- As is apparent from use of `screenattr()`, these screenshots **can't tell how exactly cell is highlighted**, only **if two cells are highlighted the same**. This is due to the currently lacking functionality in Neovim itself. This might change in the future.

To help manage testing screen state, there is a special `MiniTest.expect.reference_screenshot(screenshot, path, opts)` method. It takes screenshot table along with optional path of where to save this screenshot (if not supplied, inferred from test case description and put in 'tests/screenshots' directory). On first run it will automatically create reference screenshot at `path`. On later runs it will compare current screenshot with reference. Will throw informative error with helpful information if they don't match exactly.

Example:

```lua
local expect = MiniTest.expect

local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ '-u', 'scripts/minimal_init.lua' })
      child.bo.readonly = false
      child.lua([[M = require('hello_lines')]])
    end,
    post_once = child.stop,
  },
})

T['set_lines()'] = MiniTest.new_set({ parametrize = { {}, { 0, { 'a' } }, { 0, { 1, 2, 3 } } } })

T['set_lines()']['works'] = function(buf_id, lines)
  child.o.lines, child.o.columns = 10, 15
  child.lua('M.set_lines(...)', { buf_id, lines })
  expect.reference_screenshot(child.get_screenshot())
end

return T
```

This will result into three files in 'tests/screenshots' with names containing test case description along with supplied arguments. Here is example reference screenshot for `{ 0, { 1, 2, 3 } }` arguments (line numbers and ruler for columns is added as file specification to make it easier to find differences between two screenshots):

```
--|---------|-----
01|Hello 1        
02|Hello 2        
03|Hello 3        
04|~              
05|~              
06|~              
07|~              
08|~              
09|<e] [+] 1,1 All
10|               

--|---------|-----
01|000001111111111
02|000001111111111
03|000001111111111
04|222222222222222
05|222222222222222
06|222222222222222
07|222222222222222
08|222222222222222
09|333333333333333
10|444444444444444
```

To update already existing screenshot either delete the corresponding screenshot file and rerun test case or temporarily add `{ force = true }` option to `reference_screenshot()` to force updating the screenshot file.

## General tips

- Create a 'tests/helpers.lua' file with code that can be useful in multiple files. It can have "monkey-patched" versions of 'mini.test' functions. Example:

```lua
local Helpers = {}

Helpers.new_child_neovim = function()
  local child = MiniTest.new_child_neovim()

  child.setup = function()
    child.restart({'-u', 'scripts/minimal_init.lua'})
    child.bo.readonly = false
    child.lua([[M = require('hello_lines')]])
  end

  return child
end

return Helpers
```

- Write aliases for commonly used functions at top of the file. It will make your life a little bit easier and usually will lead to more readable tests. Example:

```lua
-- Some code setting up `child`
local set_lines = function(lines) child.api.nvim_buf_set_lines(0, 0, -1, true, lines) end
```

- When working with automatically named screenshots, beware of the following caveats:
    - Some systems are case insensitive (like usually Windows and MacOS). So having two different file names which are the same ignoring case will introduce problems for users to properly install plugin.
    - Some system setups have restrictions on full path length (like 260 bytes on some Git+Windows combinations) or file name length (like 255 bytes on ext4 Windows partitions and 143 bytes on eCryptfs Linux partitions). Restriction on full path is hard to accommodate for (apart from limiting file name size to some reasonable number), but trying to not have file names longer than 143 bytes (by having shorter test case names) should be reasonable.

- To make reading strings that contain Lua code easier (for `child.lua` and `child.lua_get`), you can add the following tree-sitter capture to your personal configuration. Put it in the file 'after/queries/lua/injections.scm'. Don't forget to add `; extends` at the beginning of the file (see `:h treesitter-query-modeline-extends`):

    ```query
    ; extends
    (function_call
      name: (dot_index_expression
        table: (identifier) @_table
        field: (identifier) @_field)
      arguments: (arguments
        (string
          content: (string_content) @injection.content))
      (#eq? @_table child)
      (#any-of? @_field lua lua_get)
      (#set! injection.language "lua"))
    ```
