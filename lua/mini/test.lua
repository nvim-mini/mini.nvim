--- *mini.test* Test Neovim plugins
--- *MiniTest*
---
--- MIT License Copyright (c) 2022 Evgeni Chasnovski
---
--- ==============================================================================
---
--- Features:
--- - Test action is defined as a named callable entry of a table.
---
--- - Helper for creating child Neovim process which is designed to be used in
---   tests (including taking and verifying screenshots). See
---   |MiniTest.new_child_neovim()| and |Minitest.expect.reference_screenshot()|.
---
--- - Hierarchical organization of tests with custom hooks, parametrization,
---   and user data. See |MiniTest.new_set()|.
---
--- - Emulation of 'Olivine-Labs/busted' interface (`describe`, `it`, etc.).
---
--- - Predefined small yet usable set of expectations (`assert`-like functions).
---   See |MiniTest.expect|.
---
--- - Customizable definition of what files should be tested.
---
--- - Test case filtering. There are predefined wrappers for testing a file
---   (|MiniTest.run_file()|) and case at a location like current cursor position
---   (|MiniTest.run_at_location()|).
---
--- - Customizable reporter of output results. There are two predefined ones:
---     - |MiniTest.gen_reporter.buffer()| for interactive usage.
---     - |MiniTest.gen_reporter.stdout()| for headless Neovim.
---
--- - Customizable project specific testing script.
---
--- - Works on Unix (Linux, MacOS, etc.) and Windows.
---
--- What it doesn't support:
--- - Parallel execution. Due to idea of limiting implementation complexity.
---
--- - Mocks, stubs, etc. Use child Neovim process and manually override what is
---   needed. Reset child process it afterwards.
---
--- - "Overly specific" expectations. Tests for (no) equality and (absence of)
---   errors usually cover most of the needs. Adding new expectations is a
---   subject to weighing its usefulness against additional implementation
---   complexity. Use |MiniTest.new_expectation()| to create custom ones.
---
--- For more information see:
--- - 'TESTING.md' file for a hands-on introduction based on examples.
---
--- - Code of this plugin's tests. Consider it to be an example of intended
---   way to use 'mini.test' for test organization and creation.
---
--- # Workflow
---
--- - Organize tests in separate files. Each test file should return a test set
---   (explicitly or implicitly by using "busted" style functions).
---
--- - Write test actions as callable entries of test set. Use child process
---   inside test actions (see |MiniTest.new_child_neovim()|) and builtin
---   expectations (see |MiniTest.expect|).
---
--- - Run tests. This does two steps:
---     - *Collect*. This creates single hierarchical test set, flattens into
---       array of test cases (see |MiniTest-test-case|) while expanding with
---       parametrization, and possibly filters them.
---     - *Execute*. This safely calls hooks and main test actions in specified
---       order while allowing reporting progress in asynchronous fashion.
---       Detected errors means test case fail; otherwise - pass.
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.test').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `MiniTest`
--- which you can use for scripting or manually (with `:lua MiniTest.*`).
---
--- See |MiniTest.config| for available config settings.
---
--- You can override runtime config settings locally to buffer inside
--- `vim.b.minitest_config` which should have same structure as `MiniTest.config`.
--- See |mini.nvim-buffer-local-config| for more details.
---
--- To stop module from showing non-error feedback, set `config.silent = true`.
---
--- # Comparisons ~
---
--- - Testing infrastructure from 'nvim-lua/plenary.nvim':
---     - Executes each file in separate headless Neovim process with customizable
---       'init.vim' file. While 'mini.test' executes everything in current
---       Neovim process encouraging writing tests with help of manually
---       managed child Neovim process (see |MiniTest.new_child_neovim()|).
---     - Tests are expected to be written with embedded simplified versions of
---       'Olivine-Labs/busted' and 'Olivine-Labs/luassert'. While 'mini.test'
---       uses concepts of test set (see |MiniTest.new_set()|) and test case
---       (see |MiniTest-test-case|). It also can emulate bigger part of
---       "busted" framework.
---     - Has single way of reporting progress (shows result after every case
---       without summary). While 'mini.test' can have customized reporters
---       with defaults for interactive and headless usage (provide more
---       compact and user-friendly summaries).
---     - Allows parallel execution, while 'mini.test' does not.
---     - Allows making mocks, stubs, and spies, while 'mini.test' does not in
---       favor of manually overwriting functionality in child Neovim process.
---
--- Although 'mini.test' supports emulation of "busted style" testing, it will
--- be more stable to use its designed approach of defining tests (with
--- `MiniTest.new_set()` and explicit table fields). Couple of reasons:
--- - "Busted" syntax doesn't support full capabilities offered by 'mini.test'.
---   Mainly it is about parametrization and supplying user data to test sets.
--- - It is an emulation, not full support. So some subtle things might not
---   work the way you expect.
---
--- Some hints for converting from 'plenary.nvim' tests to 'mini.test':
--- - Rename files from "***_spec.lua" to "test_***.lua" and put them in
---   "tests" directory.
--- - Replace `assert` calls with 'mini.test' expectations. See |MiniTest.expect|.
--- - Create main test set `T = MiniTest.new_set()` and eventually return it.
--- - Make new sets (|MiniTest.new_set()|) from `describe` blocks. Convert
---   `before_each()` and `after_each` to `pre_case` and `post_case` hooks.
--- - Make test cases from `it` blocks.
---
--- # Highlight groups ~
---
--- * `MiniTestEmphasis` - emphasis highlighting. By default it is a bold text.
--- * `MiniTestFail` - highlighting of failed cases. By default it is a bold
---   text with `vim.g.terminal_color_1` color (red).
--- * `MiniTestPass` - highlighting of passed cases. By default it is a bold
---   text with `vim.g.terminal_color_2` color (green).
---
--- To change any highlight group, modify it directly with |:highlight|.
---
--- # Disabling ~
---
--- To disable, set `vim.g.minitest_disable` (globally) or `vim.b.minitest_disable`
--- (for a buffer) to `true`. Considering high number of different scenarios
--- and customization intentions, writing exact rules for disabling module's
--- functionality is left to user. See |mini.nvim-disabling-recipes| for common
--- recipes.

-- Module definition ==========================================================
local MiniTest = {}
local H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniTest.config|.
---
---@usage >lua
---   require('mini.test').setup() -- use default config
---   -- OR
---   require('mini.test').setup({}) -- replace {} with your config table
--- <
MiniTest.setup = function(config)
  -- Export module
  _G.MiniTest = MiniTest

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Define behavior
  H.create_autocommands()

  -- Create default highlighting
  H.create_default_hl()
end

--stylua: ignore start
--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
MiniTest.config = {
  -- Options for collection of test cases. See `:h MiniTest.collect()`.
  collect = {
    -- Temporarily emulate functions from 'busted' testing framework
    -- (`describe`, `it`, `before_each`, `after_each`, and more)
    emulate_busted = true,

    -- Function returning array of file paths to be collected.
    -- Default: all Lua files in 'tests' directory starting with 'test_'.
    find_files = function()
      return vim.fn.globpath('tests', '**/test_*.lua', true, true)
    end,

    -- Predicate function indicating if test case should be executed
    filter_cases = function(case) return true end,
  },

  -- Options for execution of test cases. See `:h MiniTest.execute()`.
  execute = {
    -- Table with callable fields `start()`, `update()`, and `finish()`
    reporter = nil,

    -- Whether to stop execution after first error
    stop_on_error = false,
  },

  -- Path (relative to current directory) to script which handles project
  -- specific test running
  script_path = 'scripts/minitest.lua',

  -- Whether to disable showing non-error feedback
  silent = false,
}
--minidoc_afterlines_end
--stylua: ignore end

-- Module data ================================================================
--- Table with information about current state of test execution
---
--- Use it to examine result of |MiniTest.execute()|. It is reset at the
--- beginning of every call.
---
--- At least these keys are supported:
--- - <all_cases> - array with all cases being currently executed. Basically,
---   an input of `MiniTest.execute()`.
--- - <case> - currently executed test case. See |MiniTest-test-case|. Use it
---   to customize execution output (like adding custom notes, etc).
MiniTest.current = { all_cases = nil, case = nil }

-- Module functionality =======================================================
--- Create test set
---
--- Test set is one of the two fundamental data structures. It is a table that
--- defines hierarchical test organization as opposed to sequential
--- organization with |MiniTest-test-case|.
---
--- All its elements are one of three categories:
--- - A callable (object that can be called; function or table with `__call`
---   metatble entry) is considered to define a test action. It will be called
---   with "current arguments" (result of all nested `parametrize` values, read
---   further). If it throws error, test has failed.
--- - A test set (output of this function) defines nested structure. Its
---   options during collection (see |MiniTest.collect()|) will be extended
---   with options of this (parent) test set.
--- - Any other elements are considered helpers and don't directly participate
---   in test structure.
---
--- Set options allow customization of test collection and execution (more
--- details in `opts` description):
--- - `hooks` - table with elements that will be called without arguments at
---   predefined stages of test execution.
--- - `parametrize` - array defining different arguments with which main test
---   actions will be called. Any non-trivial parametrization will lead to
---   every element (even nested) be "multiplied" and processed with every
---   element of `parametrize`. This allows handling many different combination
---   of tests with little effort.
--- - `data` - table with user data that will be forwarded to cases. Primary
---   objective is to be used for customized case filtering.
---
--- Notes:
--- - Preferred way of adding elements is by using syntax `T[name] = element`.
---   This way order of added elements will be preserved. Any other way won't
---   guarantee any order.
--- - Supplied options `opts` are stored in `opts` field of metatable
---   (`getmetatable(set).opts`).
---
---@param opts table|nil Allowed options:
---   - <hooks> - table with fields:
---       - <pre_once> - executed before first filtered node.
---       - <pre_case> - executed before each case (even nested).
---       - <post_case> - executed after each case (even nested).
---       - <post_once> - executed after last filtered node.
---   - <parametrize> - array where each element is itself an array of
---     parameters to be appended to "current parameters" of callable fields.
---     Note: don't use plain `{}` as it is equivalent to "parametrization into
---     zero cases", so no cases will be collected from this set. Calling test
---     actions with no parameters is equivalent to `{{}}` or not supplying
---     `parametrize` option at all.
---   - <data> - user data to be forwarded to cases. Can be used for a more
---     granular filtering.
---   - <n_retry> - number of times to retry each case until success.
---     Default: 1.
---@param tbl table|nil Initial test items (possibly nested). Will be executed
---   without any guarantees on order.
---
---@return table A single test set.
---
---@usage >lua
---   -- Use with defaults
---   T = MiniTest.new_set()
---   T['works'] = function() MiniTest.expect.equality(1, 1) end
---
---   -- Use with custom options. This will result into two actual cases: first
---   -- will pass, second - fail after two attempts.
---   T['nested'] = MiniTest.new_set({
---     hooks = { pre_case = function() _G.x = 1 end },
---     parametrize = { { 1 }, { 2 } },
---     n_retry = 2,
---   })
---
---   T['nested']['works'] = function(x) MiniTest.expect.equality(_G.x, x) end
--- <
MiniTest.new_set = function(opts, tbl)
  opts = opts or {}
  tbl = tbl or {}

  -- Keep track of new elements order. This allows to iterate through elements
  -- in order they were added.
  local metatbl = { class = 'testset', key_order = vim.tbl_keys(tbl), opts = opts }
  metatbl.__newindex = function(t, key, value)
    table.insert(metatbl.key_order, key)
    rawset(t, key, value)
  end

  return setmetatable(tbl, metatbl)
end

--- Test case
---
--- An item of sequential test organization, as opposed to hierarchical with
--- test set (see |MiniTest.new_set()|). It is created as result of test
--- collection with |MiniTest.collect()| to represent all necessary information
--- of test execution.
---
--- Execution of test case goes by the following rules:
--- - Call functions in order:
---     - All elements of `hooks.pre` from first to last without arguments.
---     - Field `test` with arguments unpacked from `args`. If execution fails,
---       retry it (along with hooks that come from `pre_case` and `post_case`)
---       at most `n_retry` times until first success (if any).
---     - All elements of `hooks.post` from first to last without arguments.
--- - Error in any call gets appended to `exec.fails`, meaning error in any
---   hook will lead to test fail.
--- - State (`exec.state`) is changed before every call and after last call.
---
---@class Test-case
---
---@field args table Array of arguments with which `test` will be called.
---@field data table User data: all fields of `opts.data` from nested test sets.
---@field desc table Description: array of fields from nested test sets.
---@field exec table|nil Information about test case execution. Value of `nil` means
---   that this particular case was not (yet) executed. Has following fields:
---     - <fails> - array of strings with failing information.
---     - <notes> - array of strings with non-failing information.
---     - <state> - state of test execution. One of:
---         - 'Executing <name of what is being executed>' (during execution).
---         - 'Pass' (no fails, no notes).
---         - 'Pass with notes' (no fails, some notes).
---         - 'Fail' (some fails, no notes).
---         - 'Fail with notes' (some fails, some notes).
---@field hooks table Hooks to be executed as part of test case. Has fields:
---   - <pre> and <post> - arrays of functions to be consecutively executed
---     before and after every execution of `test`.
---   - <pre_source> and <post_source> - arrays of strings with sources of
---     corresponding elements in <pre> and <post> arrays. Source is one of
---     `"once"` (for `pre_once` and `post_once` hooks) and
---     `"case"` (for `pre_case` and `post_case` hooks).
---@field test function|table Main callable object representing test action.
---@tag MiniTest-test-case

--- Skip the rest of current case
---
--- Notes:
--- - When called inside test case, stops execution while adding message to notes.
--- - When called inside `pre_case` hook, registers skip at the start of its
---   test case. Calling in other hooks has no effect.
--- - Currently implemented as a specially handled type of error.
---
---@param msg string|nil Message to be added to current case notes.
MiniTest.skip = function(msg)
  H.cache.skip_message = msg or 'Skip test'
  error(H.cache.skip_message, 0)
end

--- Add note to currently executed test case
---
--- Appends `msg` to `exec.notes` field of |MiniTest.current.case|.
---
---@param msg string Note to add.
MiniTest.add_note = function(msg)
  local case = MiniTest.current.case
  case.exec = case.exec or {}
  case.exec.notes = case.exec.notes or {}
  table.insert(case.exec.notes, msg)
end

--- Register callable execution after current callable
---
--- Can be used several times inside hooks and main test callable of test case.
---
---@param f function|table Callable to be executed after current callable is
---   finished executing (regardless of whether it ended with error or not).
MiniTest.finally = function(f) table.insert(H.cache.finally, f) end

--- Run tests
---
--- - Try executing project specific script at path `opts.script_path`. If
---   successful (no errors), then stop.
--- - Collect cases with |MiniTest.collect()| and `opts.collect`.
--- - Execute collected cases with |MiniTest.execute()| and `opts.execute`.
---
---@param opts table|nil Options with structure similar to |MiniTest.config|.
---   Absent values are inferred from there.
MiniTest.run = function(opts)
  if H.is_disabled() then return end

  -- Try sourcing project specific script first
  local success = H.execute_project_script(opts)
  if success then return end

  -- Collect and execute
  opts = H.get_config(opts)
  local cases = MiniTest.collect(opts.collect)
  MiniTest.execute(cases, opts.execute)
end

--- Run specific test file
---
--- Basically a |MiniTest.run()| wrapper with custom `collect.find_files` option.
---
---@param file string|nil Path to test file. By default a path of current buffer.
---@param opts table|nil Options for |MiniTest.run()|.
MiniTest.run_file = function(file, opts)
  file = vim.fn.fnamemodify(file or vim.api.nvim_buf_get_name(0), ':p:.')

  local stronger_opts = { collect = { find_files = function() return { file } end } }
  opts = vim.tbl_deep_extend('force', opts or {}, stronger_opts)

  MiniTest.run(opts)
end

--- Run case(s) covering location
---
--- Try filtering case(s) covering location, meaning that definition of its
--- main `test` action (as taken from builtin `debug.getinfo`) is located in
--- specified file and covers specified line. Note that it can result in
--- multiple cases if they come from parametrized test set (see `parametrize`
--- option in |MiniTest.new_set()|).
---
--- Basically a |MiniTest.run()| wrapper with custom `collect.find_files` option.
---
---@param location table|nil Table with fields <file> (path to file) and <line>
---   (line number in that file). Default is taken from current cursor position.
MiniTest.run_at_location = function(location, opts)
  if location == nil then
    local cur_file = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':.')
    local cur_pos = vim.api.nvim_win_get_cursor(0)
    location = { file = cur_file, line = cur_pos[1] }
  end

  local stronger_opts = {
    collect = {
      find_files = function() return { location.file } end,
      filter_cases = function(case)
        local info = debug.getinfo(case.test)

        return info.short_src == location.file
          and info.linedefined <= location.line
          and location.line <= info.lastlinedefined
      end,
    },
  }
  opts = vim.tbl_deep_extend('force', opts or {}, stronger_opts)

  MiniTest.run(opts)
end

--- Collect test cases
---
--- Overview of collection process:
--- - If `opts.emulate_busted` is `true`, temporary make special global
---   functions (removed at the end of collection). They can be used inside
---   test files to create hierarchical structure of test cases.
--- - Source each file from array output of `opts.find_files`. It should output
---   a test set (see |MiniTest.new_set()|) or `nil` (if "busted" style is used;
---   test set is created implicitly).
--- - Combine all test sets into single set with fields equal to its file path.
--- - Convert from hierarchical test configuration to sequential: from single
---   test set to array of test cases (see |MiniTest-test-case|). Conversion is
---   done in the form of "for every table element do: for every `parametrize`
---   element do: ...". Details:
---     - If element is a callable, construct test case with it being main
---       `test` action. Description is appended with key of element in current
---       test set table. Hooks, arguments, and data are taken from "current
---       nested" ones. Add case to output array.
---     - If element is a test set, process it in similar, recursive fashion.
---       The "current nested" information is expanded:
---         - `args` is extended with "current element" from `parametrize`.
---         - `desc` is appended with element key.
---         - `hooks` are appended to their appropriate places. `*_case` hooks
---           will be inserted closer to all child cases than hooks from parent
---           test sets: `pre_case` at end, `post_case` at start.
---         - `data` is extended via |vim.tbl_deep_extend()|.
---     - Any other element is not processed.
--- - Filter array with `opts.filter_cases`. Note that input case doesn't contain
---   all hooks, as `*_once` hooks will be added after filtration.
--- - Add `*_once` hooks to appropriate cases.
---
---@param opts table|nil Options controlling case collection. Possible fields:
---   - <emulate_busted> - whether to emulate 'Olivine-Labs/busted' interface.
---     It emulates these global functions: `describe`, `it`, `setup`, `teardown`,
---     `before_each`, `after_each`. Use |MiniTest.skip()| instead of `pending()`
---     and |MiniTest.finally()| instead of `finally`.
---   - <find_files> - function which when called without arguments returns
---     array with file paths. Each file should be a Lua file returning single
---     test set or `nil`.
---   - <filter_cases> - function which when called with single test case
---     (see |MiniTest-test-case|) returns `false` if this case should be filtered
---     out; `true` otherwise.
---
---@return table Array of test cases ready to be used by |MiniTest.execute()|.
MiniTest.collect = function(opts)
  opts = vim.tbl_deep_extend('force', H.get_config().collect, opts or {})

  -- Make single test set
  local set = MiniTest.new_set()

  for _, file in ipairs(opts.find_files()) do
    -- Possibly emulate 'busted' with current file. This allows to wrap all
    -- implicit cases from that file into single set with file's name.
    if opts.emulate_busted then
      set[file] = MiniTest.new_set()
      H.busted_emulate(set[file])
    end

    -- Execute file
    local ok, t = pcall(dofile, file)

    -- Catch errors
    if not ok then
      local msg = string.format('Sourcing %s resulted into following error: %s', vim.inspect(file), t)
      H.error(msg)
    end
    local is_output_correct = (opts.emulate_busted and vim.tbl_count(set[file]) > 0) or H.is_instance(t, 'testset')
    if not is_output_correct then
      local msg = string.format(
        [[%s does not define a test set. Did you return `MiniTest.new_set()` or created 'busted' tests?]],
        vim.inspect(file)
      )
      H.error(msg)
    end

    -- If output is test set, always use it (even if 'busted' tests were added)
    if H.is_instance(t, 'testset') then set[file] = t end
  end

  H.busted_deemulate()

  -- Convert to test cases. This also creates separate aligned array of hooks
  -- which should be executed once regarding test case. This is needed to
  -- correctly inject those hooks after filtering is done.
  local raw_cases, raw_hooks_once = H.set_to_testcases(set)

  -- Filter cases (at this stage don't have injected `hooks_once`)
  local cases, hooks_once = {}, {}
  for i, c in ipairs(raw_cases) do
    if opts.filter_cases(c) then
      table.insert(cases, c)
      table.insert(hooks_once, raw_hooks_once[i])
    end
  end

  -- Inject `hooks_once` into appropriate cases
  H.inject_hooks_once(cases, hooks_once)

  return cases
end

--- Execute array of test cases
---
--- Overview of execution process:
--- - Reset `all_cases` in |MiniTest.current| with `cases` input.
--- - Call `reporter.start(cases)` (if present).
--- - Execute each case in natural array order (aligned with their integer
---   keys). Set `MiniTest.current.case` to currently executed case. Detailed
---   test case execution is described in |MiniTest-test-case|. After any state
---   change (including case retry attempts), call `reporter.update(case_num)`
---   (if present), where `case_num` is an integer key of current test case.
--- - Call `reporter.finish()` (if present).
---
--- Notes:
--- - Execution is done in asynchronous fashion with scheduling. This allows
---   making meaningful progress report during execution.
--- - This function doesn't return anything. Instead, it updates `cases` in
---   place with proper `exec` field. Use `all_cases` at |MiniTest.current| to
---   look at execution result.
---
---@param cases table Array of test cases (see |MiniTest-test-case|).
---@param opts table|nil Options controlling case collection. Possible fields:
---   - <reporter> - table with possible callable fields `start`, `update`,
---     `finish`. Default: |MiniTest.gen_reporter.buffer()| in interactive
---     usage and |MiniTest.gen_reporter.stdout()| in headless usage.
---   - <stop_on_error> - whether to stop execution (see |MiniTest.stop()|)
---     after first error. Default: `false`.
MiniTest.execute = function(cases, opts)
  H.check_type('cases', cases, 'table')

  MiniTest.current.all_cases = cases

  -- Verify correct arguments
  if #cases == 0 then
    H.message('No cases to execute.')
    return
  end

  opts = vim.tbl_deep_extend('force', H.get_config().execute, opts or {})
  local reporter = opts.reporter or (H.is_headless and MiniTest.gen_reporter.stdout() or MiniTest.gen_reporter.buffer())
  if type(reporter) ~= 'table' then
    H.message('`opts.reporter` should be table or `nil`.')
    return
  end
  opts.reporter = reporter

  -- Start execution
  H.cache = { is_executing = true }

  vim.schedule(function() H.exec_callable(reporter.start, cases) end)

  for case_num, cur_case in ipairs(cases) do
    H.schedule_case(cur_case, case_num, opts)
  end

  vim.schedule(function() H.exec_callable(reporter.finish) end)
  -- Use separate call to ensure that `reporter.finish` error won't interfere
  vim.schedule(function() H.cache.is_executing = false end)
end

--- Stop test execution
---
---@param opts table|nil Options with fields:
---   - <close_all_child_neovim> - whether to close all child neovim processes
---     created with |MiniTest.new_child_neovim()|. Default: `true`.
MiniTest.stop = function(opts)
  opts = vim.tbl_deep_extend('force', { close_all_child_neovim = true }, opts or {})

  -- Register intention to stop execution
  H.cache.should_stop_execution = true

  -- Possibly stop all child Neovim processes
  if not opts.close_all_child_neovim then return end

  for _, child in ipairs(H.child_neovim_registry) do
    pcall(child.stop)
  end
  H.child_neovim_registry = {}
end

--- Check if tests are being executed
---
---@return boolean
MiniTest.is_executing = function() return H.cache.is_executing == true end

-- Expectations ---------------------------------------------------------------
--- Table with expectation functions
---
--- Each function has the following behavior:
--- - Silently returns `true` if expectation is fulfilled.
--- - Throws an informative error with information helpful for debugging.
---
--- Mostly designed to be used within 'mini.test' framework.
---
---@usage >lua
---   local x = 1 + 1
---   MiniTest.expect.equality(x, 2) -- passes
---   MiniTest.expect.equality(x, 1) -- fails
--- <
MiniTest.expect = {}

--- Expect equality of two objects
---
--- Equality is tested via |vim.deep_equal()|.
---
---@param left any First object.
---@param right any Second object.
---@param opts table|nil Options:
---   - <msg> `(string)` Fails with the supplied failure message. Default: nil
MiniTest.expect.equality = function(left, right, opts)
  if vim.deep_equal(left, right) then return true end

  local context = string.format('Left:  %s\nRight: %s', vim.inspect(left), vim.inspect(right))
  opts = opts or {}
  if opts.msg then context = string.format('%s\n%s', opts.msg, context) end
  H.error_expect('equality', context)
end

--- Expect no equality of two objects
---
--- Equality is tested via |vim.deep_equal()|.
---
---@param left any First object.
---@param right any Second object.
---@param opts table|nil Options:
---   - <msg> `(string)` Fails with the supplied failure message. Default: nil
MiniTest.expect.no_equality = function(left, right, opts)
  opts = opts or {}
  if not vim.deep_equal(left, right) then return true end

  local context = string.format('Object: %s', vim.inspect(left))
  opts = opts or {}
  if opts.msg then context = string.format('%s\n%s', opts.msg, context) end
  H.error_expect('*no* equality', context)
end

--- Expect function call to raise error
---
---@param f function|table Callable to be tested for raising error.
---@param pattern string|nil Pattern which error message should match.
---   Use `nil` or empty string to not test for pattern matching.
---@param ... any Extra arguments with which `f` will be called.
MiniTest.expect.error = function(f, pattern, ...)
  H.check_type('pattern', pattern, 'string', true)

  local ok, err = pcall(f, ...)
  err = err or ''
  local has_matched_error = not ok and string.find(err, pattern or '') ~= nil
  if has_matched_error then return true end

  local matching_pattern = pattern == nil and '' or (' matching pattern %s'):format(vim.inspect(pattern))
  local subject = 'error' .. matching_pattern
  local context = ok and 'Observed no error' or ('Observed error: ' .. err)

  H.error_expect(subject, context)
end

--- Expect function call to not raise error
---
---@param f function|table Callable to be tested for raising error.
---@param ... any Extra arguments with which `f` will be called.
MiniTest.expect.no_error = function(f, ...)
  local ok, err = pcall(f, ...)
  err = err or ''
  if ok then return true end

  H.error_expect('*no* error', 'Observed error: ' .. err)
end

--- Expect equality to reference screenshot
---
---@param screenshot table|nil Array with screenshot information. Usually an output
---   of `child.get_screenshot()` (see |MiniTest-child-neovim.get_screenshot()|).
---   If `nil`, expectation passed.
---@param path string|nil Path to reference screenshot. If `nil`, constructed
---   automatically in directory `opts.directory` from current case info and
---   total number of times it was called inside current case. If there is no
---   file at `path`, it is created with content of `screenshot`.
---@param opts table|nil Options:
---   - <force> `(boolean)` - whether to forcefully create reference screenshot.
---     Temporary useful during test writing. Default: `false`.
---   - <ignore_text> `(boolean|table)` - whether to ignore all or some text lines.
---     If `true` - ignore all, if number array - ignore text of those lines,
---     if `false` - do not ignore any. Default: `false`.
---   - <ignore_attr> `(boolean|table)` - whether to ignore all or some attr lines.
---     If `true` - ignore all, if number array - ignore attr of those lines,
---     if `false` - do not ignore any. Default: `false`.
---   - <directory> `(string)` - directory where automatically constructed `path`
---     is located. Default: "tests/screenshots".
---   - <msg> `(string)` - Fails with the supplied failure message. Default: nil
MiniTest.expect.reference_screenshot = function(screenshot, path, opts)
  if screenshot == nil then return true end

  local default_opts = { force = false, ignore_text = false, ignore_attr = false, directory = 'tests/screenshots' }
  opts = vim.tbl_extend('force', default_opts, opts or {})

  -- TODO: Remove after releasing 'mini.nvim' 0.17.0
  if opts.ignore_lines ~= nil then
    vim.notify(
      '(mini.test) `ignore_lines` is soft deprecated in favor of separate `ignore_text` and `ignore_attr`.'
        .. ' It will work at least until the next release, after which its support will be removed.'
        .. ' Sorry for the inconvenience.'
    )
  end
  opts.ignore_lines = opts.ignore_lines or {}

  H.cache.n_screenshots = H.cache.n_screenshots + 1

  if path == nil then
    -- Sanitize path. Replace any control characters, whitespace, OS specific
    -- forbidden characters with '-' (with some useful exception)
    local linux_forbidden = [[/]]
    local windows_forbidden = [[<>:"/\|?*]]
    local pattern = string.format('[%%c%%s%s%s]', vim.pesc(linux_forbidden), vim.pesc(windows_forbidden))
    local replacements = setmetatable({ ['"'] = "'" }, { __index = function() return '-' end })
    local name = H.case_to_stringid(MiniTest.current.case):gsub(pattern, replacements)

    -- Don't end with whitespace or dot (forbidden on Windows)
    name = name:gsub('[%s%.]$', '-')
    path = vim.fs.normalize(opts.directory) .. '/' .. name

    -- Deal with multiple screenshots
    if H.cache.n_screenshots > 1 then path = path .. string.format('-%03d', H.cache.n_screenshots) end
  end

  -- If there is no readable screenshot file, create it. Pass with note.
  if opts.force or vim.fn.filereadable(path) == 0 then
    local dir_path = vim.fn.fnamemodify(path, ':p:h')
    vim.fn.mkdir(dir_path, 'p')
    H.screenshot_write(screenshot, path)

    MiniTest.add_note('Created reference screenshot at path ' .. vim.inspect(path))
    return true
  end

  local reference = H.screenshot_read(path)

  -- Compare
  local same_text, cause_text = H.screenshot_compare_part('text', reference, screenshot, opts)
  local same_attr, cause_attr = H.screenshot_compare_part('attr', reference, screenshot, opts)
  if same_text and same_attr then return true end

  local cause = same_text and cause_attr or cause_text
  local subject = 'screenshot equality to reference at ' .. vim.inspect(path)
  local context = string.format('%s\nReference:\n%s\n\nObserved:\n%s', cause, tostring(reference), tostring(screenshot))
  if opts.msg then context = string.format('%s\n%s', opts.msg, context) end
  H.error_expect(subject, context)
end

--- Create new expectation function
---
--- Helper for writing custom functions with behavior similar to other methods
--- of |MiniTest.expect|.
---
---@param subject string|function|table Subject of expectation. If callable,
---   called with expectation input arguments to produce string value.
---@param predicate function|table Predicate callable. Called with expectation
---   input arguments. Output `false` or `nil` means failed expectation.
---@param fail_context string|function|table Information about fail. If callable,
---   called with expectation input arguments to produce string value.
---
---@return function Expectation function.
---
---@usage >lua
---   local expect_truthy = MiniTest.new_expectation(
---     'truthy',
---     function(x) return x end,
---     function(x) return 'Object: ' .. vim.inspect(x) end
---   )
--- <
MiniTest.new_expectation = function(subject, predicate, fail_context)
  return function(...)
    if predicate(...) then return true end

    local cur_subject = vim.is_callable(subject) and subject(...) or subject
    local cur_context = vim.is_callable(fail_context) and fail_context(...) or fail_context
    H.error_expect(cur_subject, cur_context)
  end
end

-- Reporters ------------------------------------------------------------------
--- Table with pre-configured report generators
---
--- Each element is a function which returns reporter - table with callable
--- `start`, `update`, and `finish` fields.
MiniTest.gen_reporter = {}

--- Generate buffer reporter
---
--- This is a default choice for interactive (not headless) usage. Opens a window
--- with dedicated non-terminal buffer and updates it with throttled redraws.
---
--- Opened buffer has the following helpful Normal mode mappings:
--- - `<Esc>` - stop test execution if executing (see |MiniTest.is_executing()|
---   and |MiniTest.stop()|). Close window otherwise.
--- - `q` - same as `<Esc>` for convenience and compatibility.
---
--- General idea:
--- - Group cases by concatenating first `opts.group_depth` elements of case
---   description (`desc` field). Groups by collected files if using default values.
--- - In `start()` show some stats to know how much is scheduled to be executed.
--- - In `update()` show symbolic overview of current group and state of current
---   case. Each symbol represents one case and its state:
---     - `?` - case didn't finish executing.
---     - `o` - pass.
---     - `O` - pass with notes.
---     - `x` - fail.
---     - `X` - fail with notes.
--- - In `finish()` show all fails and notes ordered by case.
---
---@param opts table|nil Table with options. Used fields:
---   - <group_depth> - number of first elements of case description (can be zero)
---     used for grouping. Higher values mean higher granularity of output.
---     Default: 1.
---   - <throttle_delay> - minimum number of milliseconds to wait between
---     redrawing. Reduces screen flickering but not amount of computations.
---     Default: 10.
---   - <window> - definition of window to open. Can take one of the forms:
---       - Callable. It is called expecting output to be target window id
---         (current window is used if output is `nil`). Use this to open in
---         "normal" window (like `function() vim.cmd('vsplit') end`).
---       - Table. Used as `config` argument in |nvim_open_win()|.
---     Default: table for centered floating window.
MiniTest.gen_reporter.buffer = function(opts)
  -- NOTE: another choice of implementing this is to use terminal buffer
  -- `vim.api.nvim_open_term()`.
  -- Pros:
  -- - Renders ANSI escape sequences (mostly) correctly, i.e. no need in
  --   replacing them with Neovim range highlights.
  -- - This reporter and `stdout` one can share more of a codebase.
  -- Cons:
  -- - Couldn't manage to implement "redraw on every update".
  -- - Extra steps still are needed in order to have richer output information.
  --   This involves ANSI sequences that move cursor, which have same issues as
  --   in `stdout`, albeit easier to overcome:
  --     - Handling of scroll.
  --     - Hard wrapping of lines leading to need of using window width.
  opts = vim.tbl_deep_extend(
    'force',
    { group_depth = 1, throttle_delay = 10, window = H.buffer_reporter.default_window_opts() },
    opts or {}
  )

  local buf_id, win_id
  local is_valid_buf_win = function() return vim.api.nvim_buf_is_valid(buf_id) and vim.api.nvim_win_is_valid(win_id) end

  -- Helpers
  local set_cursor = function(line)
    vim.api.nvim_win_set_cursor(win_id, { line or vim.api.nvim_buf_line_count(buf_id), 0 })
  end

  -- Define "write from cursor line" function with throttled redraw
  local latest_draw_time = 0
  local replace_last = function(n_replace, lines, force)
    H.buffer_reporter.set_lines(buf_id, lines, -n_replace - 1, -1)

    -- Throttle redraw to reduce flicker
    local cur_time = vim.loop.hrtime()
    local is_enough_time_passed = (cur_time - latest_draw_time) > opts.throttle_delay * 1000000
    if is_enough_time_passed or force then
      vim.cmd('redraw')
      latest_draw_time = cur_time
    end
  end

  -- Create reporter functions
  local res = {}
  local all_cases, all_groups, latest_group_name

  res.start = function(cases)
    -- Set up buffer and window
    buf_id, win_id = H.buffer_reporter.setup_buf_and_win(opts.window)

    -- Set up data (taking into account possible not first time run)
    all_cases = cases
    all_groups = H.overview_reporter.compute_groups(cases, opts.group_depth)
    latest_group_name = nil

    -- Write lines
    local lines = H.overview_reporter.start_lines(all_cases, all_groups)
    replace_last(1, lines)
    set_cursor()
  end

  res.update = function(case_num)
    if not is_valid_buf_win() then return end

    local case, cur_group_name = all_cases[case_num], all_groups[case_num].name

    -- Update symbol
    local state = type(case.exec) == 'table' and case.exec.state or nil
    all_groups[case_num].symbol = H.reporter_symbols[state]

    local n_replace = H.buffer_reporter.update_step_n_replace(latest_group_name, cur_group_name)
    local lines = H.buffer_reporter.update_step_lines(case_num, all_cases, all_groups)
    replace_last(n_replace, lines)
    set_cursor()

    latest_group_name = cur_group_name
  end

  res.finish = function()
    if not is_valid_buf_win() then return end

    -- Cache final cursor position to overwrite 'Current case state' header
    local start_line = vim.api.nvim_buf_line_count(buf_id) - 1

    -- Force writing lines
    local lines = H.overview_reporter.finish_lines(all_cases)
    replace_last(2, lines, true)
    set_cursor(start_line)
  end

  return res
end

--- Generate stdout reporter
---
--- This is a default choice for headless usage. Writes to `stdout`. Uses
--- coloring ANSI escape sequences to make pretty and informative output
--- (should work in most modern terminals and continuous integration providers).
---
--- It has same general idea as |MiniTest.gen_reporter.buffer()| with slightly
--- less output (it doesn't overwrite previous text) to overcome typical
--- terminal limitations.
---
---@param opts table|nil Table with options. Used fields:
---   - <group_depth> - number of first elements of case description (can be zero)
---     used for grouping. Higher values mean higher granularity of output.
---     Default: 1.
---   - <quit_on_finish> - whether to quit after finishing test execution.
---     Default: `true`.
MiniTest.gen_reporter.stdout = function(opts)
  opts = vim.tbl_deep_extend('force', { group_depth = 1, quit_on_finish = true }, opts or {})

  local write = function(text)
    text = type(text) == 'table' and table.concat(text, '\n') or text
    io.stdout:write(text)
    io.flush()
  end

  local all_cases, all_groups, latest_group_name
  local default_symbol = H.reporter_symbols[nil]

  local res = {}

  res.start = function(cases)
    -- Set up data
    all_cases = cases
    all_groups = H.overview_reporter.compute_groups(cases, opts.group_depth)

    -- Write lines
    local lines = H.overview_reporter.start_lines(all_cases, all_groups)
    write(lines)
  end

  res.update = function(case_num)
    local cur_case = all_cases[case_num]
    local cur_group_name = all_groups[case_num].name

    -- Possibly start overview of new group
    if cur_group_name ~= latest_group_name then
      write('\n')
      write(cur_group_name)
      if cur_group_name ~= '' then write(': ') end
    end

    -- Possibly show new symbol
    local state = type(cur_case.exec) == 'table' and cur_case.exec.state or nil
    local cur_symbol = H.reporter_symbols[state]
    if cur_symbol ~= default_symbol then write(cur_symbol) end

    latest_group_name = cur_group_name
  end

  res.finish = function()
    write('\n\n')
    local lines = H.overview_reporter.finish_lines(all_cases)
    write(lines)
    write('\n')

    -- Possibly quit
    if not opts.quit_on_finish then return end
    local command = string.format('silent! %scquit', H.has_fails(all_cases) and 1 or 0)
    vim.cmd(command)
  end

  return res
end

-- Exported utility functions -------------------------------------------------
--- Create child Neovim process
---
--- This creates an object designed to be a fundamental piece of 'mini.test'
--- methodology. It can start/stop/restart a separate (child) Neovim process
--- (headless, but fully functioning) together with convenience helpers to
--- interact with it through |RPC| messages.
---
--- For more information see |MiniTest-child-neovim|.
---
---@return MiniTest.child Object of |MiniTest-child-neovim|.
---
---@usage >lua
---   -- Initiate
---   local child = MiniTest.new_child_neovim()
---   child.start()
---
---   -- Use API functions
---   child.api.nvim_buf_set_lines(0, 0, -1, true, { 'Line inside child Neovim' })
---
---   -- Execute Lua code, Vimscript commands, etc.
---   child.lua('_G.n = 0')
---   child.cmd('au CursorMoved * lua _G.n = _G.n + 1')
---   child.type_keys('l')
---   print(child.lua_get('_G.n')) -- Should be 1
---
---   -- Use other `vim.xxx` Lua wrappers (executed inside child process)
---   vim.b.aaa = 'current process'
---   child.b.aaa = 'child process'
---   print(child.lua_get('vim.b.aaa')) -- Should be 'child process'
---
---   -- Always stop process after it is not needed
---   child.stop()
--- <
MiniTest.new_child_neovim = function()
  local child = {}
  local start_args, start_opts

  local ensure_running = function()
    if child.is_running() then return end
    H.error('Child process is not running. Did you call `child.start()`?')
  end

  local prevent_hanging = function(method)
    if not child.is_blocked() then return end

    local msg = string.format('Can not use `child.%s` because child process is blocked.', method)
    H.error_with_emphasis(msg)
  end

  -- Start headless Neovim instance
  child.start = function(args, opts)
    if child.is_running() then
      H.message('Child process is already running. Use `child.restart()`.')
      return
    end

    args = args or {}
    opts = vim.tbl_deep_extend('force', { nvim_executable = vim.v.progpath, connection_timeout = 5000 }, opts or {})

    -- Make unique name for `--listen` pipe
    local job = { address = vim.fn.tempname() }

    if vim.fn.has('win32') == 1 then
      -- Use special local pipe prefix on Windows with (hopefully) unique name
      -- Source: https://learn.microsoft.com/en-us/windows/win32/ipc/pipe-names
      job.address = [[\\.\pipe\mininvim]] .. vim.fn.fnamemodify(job.address, ':t')
    end

    --stylua: ignore
    local full_args = {
      opts.nvim_executable, '--clean', '-n', '--listen', job.address,
      -- Setting 'lines' and 'columns' makes headless process more like
      -- interactive for closer to reality testing
      '--headless', '--cmd', 'set lines=24 columns=80'
    }
    vim.list_extend(full_args, args)

    -- Using 'jobstart' for creating a job is crucial for getting this to work
    -- in Github Actions. Other approaches:
    -- - Using `{ pty = true }` seems crucial to make this work on GitHub CI.
    -- - Using `vim.loop.spawn()` is doable, but has some issues:
    --     - https://github.com/neovim/neovim/issues/21630
    --     - https://github.com/neovim/neovim/issues/21886
    job.id = vim.fn.jobstart(full_args)

    local step = 10
    local connected, i, max_tries = nil, 0, math.floor(opts.connection_timeout / step)
    repeat
      i = i + 1
      vim.loop.sleep(step)
      connected, job.channel = pcall(vim.fn.sockconnect, 'pipe', job.address, { rpc = true })
    until connected or i >= max_tries

    if not connected then
      local err = '  ' .. job.channel:gsub('\n', '\n  ')
      H.error('Failed to make connection to child Neovim with the following error:\n' .. err)
      child.stop()
    end

    child.job = job
    start_args, start_opts = args, opts
  end

  child.stop = function()
    if not child.is_running() then return end

    -- Properly exit Neovim. `pcall` avoids `channel closed by client` error.
    -- Also wait for it to actually close. This reduces simultaneously opened
    -- Neovim instances and CPU load (overall reducing flacky tests).
    pcall(child.cmd, 'silent! 0cquit')
    vim.fn.jobwait({ child.job.id }, 1000)

    -- Close all used channels. Prevents `too many open files` type of errors.
    pcall(vim.fn.chanclose, child.job.channel)
    pcall(vim.fn.chanclose, child.job.id)

    -- Remove file for address to reduce chance of "can't open file" errors, as
    -- address uses temporary unique files
    pcall(vim.fn.delete, child.job.address)

    child.job = nil
  end

  child.restart = function(args, opts)
    args = args or start_args
    opts = vim.tbl_deep_extend('force', start_opts or {}, opts or {})

    child.stop()
    child.start(args, opts)
  end

  -- Wrappers for common `vim.xxx` objects (will get executed inside child)
  child.api = setmetatable({}, {
    __index = function(_, key)
      ensure_running()
      return function(...) return vim.rpcrequest(child.job.channel, key, ...) end
    end,
  })

  -- Variant of `api` functions called with `vim.rpcnotify`. Useful for making
  -- blocking requests (like `getcharstr()`).
  child.api_notify = setmetatable({}, {
    __index = function(_, key)
      ensure_running()
      return function(...) return vim.rpcnotify(child.job.channel, key, ...) end
    end,
  })

  ---@return table Emulates `vim.xxx` table (like `vim.fn`)
  ---@private
  local redirect_to_child = function(tbl_name)
    -- TODO: try to figure out the best way to operate on tables with function
    -- values (needs "deep encode/decode" of function objects)
    return setmetatable({}, {
      __index = function(_, key)
        ensure_running()

        local short_name = ('%s.%s'):format(tbl_name, key)
        local obj_name = ('vim[%s][%s]'):format(vim.inspect(tbl_name), vim.inspect(key))

        prevent_hanging(short_name)
        local value_type = child.api.nvim_exec_lua(('return type(%s)'):format(obj_name), {})

        if value_type == 'function' then
          -- This allows syntax like `child.fn.mode(1)`
          return function(...)
            prevent_hanging(short_name)
            return child.api.nvim_exec_lua(('return %s(...)'):format(obj_name), { ... })
          end
        end

        -- This allows syntax like `child.bo.buftype`
        prevent_hanging(short_name)
        return child.api.nvim_exec_lua(('return %s'):format(obj_name), {})
      end,
      __newindex = function(_, key, value)
        ensure_running()

        local short_name = ('%s.%s'):format(tbl_name, key)
        local obj_name = ('vim[%s][%s]'):format(vim.inspect(tbl_name), vim.inspect(key))

        -- This allows syntax like `child.b.aaa = function(x) return x + 1 end`
        -- (inherits limitations of `string.dump`: no upvalues, etc.)
        if type(value) == 'function' then
          local dumped = vim.inspect(string.dump(value))
          value = ('loadstring(%s)'):format(dumped)
        else
          value = vim.inspect(value)
        end

        prevent_hanging(short_name)
        child.api.nvim_exec_lua(('%s = %s'):format(obj_name, value), {})
      end,
    })
  end

  --stylua: ignore start
  local supported_vim_tables = {
    -- Collections
    'diagnostic', 'fn', 'highlight', 'hl', 'json', 'loop', 'lsp', 'mpack', 'spell', 'treesitter', 'ui', 'fs',
    -- Variables
    'g', 'b', 'w', 't', 'v', 'env',
    -- Options (no 'opt' because not really useful due to use of metatables)
    'o', 'go', 'bo', 'wo',
  }
  --stylua: ignore end
  for _, v in ipairs(supported_vim_tables) do
    child[v] = redirect_to_child(v)
  end

  -- Convenience wrappers
  child.type_keys = function(wait, ...)
    ensure_running()

    local has_wait = type(wait) == 'number'
    local keys = has_wait and { ... } or { wait, ... }
    keys = H.tbl_flatten(keys)

    -- From `nvim_input` docs: "On execution error: does not fail, but
    -- updates v:errmsg.". So capture it manually. NOTE: Have it global to
    -- allow sending keys which will block in the middle (like `[[<C-\>]]` and
    -- `<C-n>`). Otherwise, later check will assume that there was an error.
    local cur_errmsg
    for _, k in ipairs(keys) do
      if type(k) ~= 'string' then
        error('In `type_keys()` each argument should be either string or array of strings.')
      end

      -- But do that only if Neovim is not "blocked". Otherwise, usage of
      -- `child.v` will block execution.
      if not child.is_blocked() then
        cur_errmsg = child.v.errmsg
        child.v.errmsg = ''
      end

      -- Need to escape bare `<` (see `:h nvim_input`)
      child.api.nvim_input(k == '<' and '<LT>' or k)

      -- Possibly throw error manually
      if not child.is_blocked() then
        if child.v.errmsg ~= '' then
          error(child.v.errmsg, 2)
        else
          child.v.errmsg = cur_errmsg or ''
        end
      end

      -- Possibly wait
      if has_wait and wait > 0 then vim.loop.sleep(wait) end
    end
  end

  child.cmd = function(str)
    ensure_running()
    prevent_hanging('cmd')
    return child.api.nvim_exec(str, false)
  end

  child.cmd_capture = function(str)
    ensure_running()
    prevent_hanging('cmd_capture')
    return child.api.nvim_exec(str, true)
  end

  child.lua = function(str, args)
    ensure_running()
    prevent_hanging('lua')
    return child.api.nvim_exec_lua(str, args or {})
  end

  child.lua_notify = function(str, args)
    ensure_running()
    return child.api_notify.nvim_exec_lua(str, args or {})
  end

  child.lua_get = function(str, args)
    ensure_running()
    prevent_hanging('lua_get')
    return child.api.nvim_exec_lua('return ' .. str, args or {})
  end

  child.lua_func = function(f, ...)
    ensure_running()
    prevent_hanging('lua_func')
    return child.api.nvim_exec_lua(
      'local f = ...; return assert(loadstring(f))(select(2, ...))',
      { string.dump(f), ... }
    )
  end

  child.is_blocked = function()
    ensure_running()
    return child.api.nvim_get_mode()['blocking']
  end

  child.is_running = function() return child.job ~= nil end

  -- Various wrappers
  child.ensure_normal_mode = function()
    ensure_running()
    child.type_keys([[<C-\>]], '<C-n>')
  end

  child.get_screenshot = function(opts)
    ensure_running()
    prevent_hanging('get_screenshot')

    opts = vim.tbl_deep_extend('force', { redraw = true }, opts or {})

    if opts.redraw then child.cmd('redraw') end

    local res = child.lua([[
      local text, attr = {}, {}
      for i = 1, vim.o.lines do
        local text_line, attr_line = {}, {}
        for j = 1, vim.o.columns do
          table.insert(text_line, vim.fn.screenstring(i, j))
          table.insert(attr_line, vim.fn.screenattr(i, j))
        end
        table.insert(text, text_line)
        table.insert(attr, attr_line)
      end
      return { text = text, attr = attr }
    ]])
    res.attr = H.screenshot_encode_attr(res.attr)

    return H.screenshot_new(res)
  end

  -- Register `child` for automatic stop in case of emergency
  table.insert(H.child_neovim_registry, child)

  return child
end

--- Child class
---
--- It offers a great set of tools to write reliable and reproducible tests by
--- allowing to use fresh process in any test action. Interaction with it is done
--- through |RPC| protocol.
---
--- Although quite flexible, at the moment it has certain limitations:
--- - Doesn't allow using functions or userdata for child's both inputs and
---   outputs. Usual solution is to move computations from current Neovim process
---   to child process. Use `child.lua()` and `child.lua_get()` for that.
--- - When writing tests, it is common to end up with "hanging" process: it
---   stops executing without any output. Most of the time it is because Neovim
---   process is "blocked", i.e. it waits for user input and won't return from
---   other call (like `child.api.nvim_exec_lua()`). Common causes are active
---   |hit-enter-prompt| (increase prompt height to a bigger value) or
---   Operator-pending mode (exit it). To mitigate this experience, most helpers
---   will throw an error if its immediate execution will lead to hanging state.
---   Also in case of hanging state try `child.api_notify` instead of `child.api`.
---
--- Notes:
--- - An important type of field is a "redirection table". It acts as a
---   convenience wrapper for corresponding `vim.*` table. Can be used both to
---   return and set values. Examples:
---     - `child.api.nvim_buf_line_count(0)` will execute
---       `vim.api.nvim_buf_line_count(0)` inside child process and return its
---       output to current process.
---     - `child.bo.filetype = 'lua'` will execute `vim.bo.filetype = 'lua'`
---       inside child process.
---   They still have same limitations listed above, so are not perfect. In
---   case of a doubt, use `child.lua()`.
--- - Almost all methods use |vim.rpcrequest()| (i.e. wait for call to finish and
---   then return value). See for `*_notify` variant to use |vim.rpcnotify()|.
--- - All fields and methods should be called with `.`, not `:`.
---
---@class MiniTest.child
---
---@field start function Start child process. See |MiniTest-child-neovim.start()|.
---@field stop function Stop current child process.
---@field restart function Restart child process: stop if running and then
---   start a new one. Takes same arguments as `child.start()` but uses values
---   from most recent `start()` call as defaults.
---
---@field type_keys function Emulate typing keys.
---   See |MiniTest-child-neovim.type_keys()|. Doesn't check for blocked state.
---
---@field cmd function Execute Vimscript code from a string.
---   A wrapper for |nvim_exec()| without capturing output.
---@field cmd_capture function Execute Vimscript code from a string and
---   capture output. A wrapper for |nvim_exec()| with capturing output.
---
---@field lua function Execute Lua code. A wrapper for |nvim_exec_lua()|.
---@field lua_notify function Execute Lua code without waiting for output.
---@field lua_get function Execute Lua code and return result. A wrapper
---   for |nvim_exec_lua()| but prepends string code with `return`.
---@field lua_func function Execute Lua function and return it's result.
---   Function will be called with all extra parameters (second one and later).
---   Note: usage of upvalues (data from outside function scope) is not allowed.
---
---@field is_blocked function Check whether child process is blocked.
---@field is_running function Check whether child process is currently running.
---
---@field ensure_normal_mode function Ensure normal mode.
---@field get_screenshot function Returns table with two "2d arrays" of single
---   characters representing what is displayed on screen and how it looks.
---   Has `opts` table argument for optional configuratnion.
---
---@field job table|nil Information about current job. If `nil`, child is not running.
---
---@field api table Redirection table for `vim.api`. Doesn't check for blocked state.
---@field api_notify table Same as `api`, but uses |vim.rpcnotify()|.
---
---@field diagnostic table Redirection table for |vim.diagnostic|.
---@field fn table Redirection table for |vim.fn|.
---@field highlight table Redirection table for `vim.highlight` (|lua-highlight)|.
---@field hl table Redirection table for |vim.hl|.
---@field json table Redirection table for `vim.json`.
---@field loop table Redirection table for |vim.loop|.
---@field lsp table Redirection table for `vim.lsp` (|lsp-core)|.
---@field mpack table Redirection table for |vim.mpack|.
---@field spell table Redirection table for |vim.spell|.
---@field treesitter table Redirection table for |vim.treesitter|.
---@field ui table Redirection table for `vim.ui` (|lua-ui|). Currently of no
---   use because it requires sending function through RPC, which is impossible
---   at the moment.
---@field fs table Redirection table for |vim.fs|.
---
---@field g table Redirection table for |vim.g|.
---@field b table Redirection table for |vim.b|.
---@field w table Redirection table for |vim.w|.
---@field t table Redirection table for |vim.t|.
---@field v table Redirection table for |vim.v|.
---@field env table Redirection table for |vim.env|.
---
---@field o table Redirection table for |vim.o|.
---@field go table Redirection table for |vim.go|.
---@field bo table Redirection table for |vim.bo|.
---@field wo table Redirection table for |vim.wo|.
---@tag MiniTest-child-neovim

--- child.start(args, opts) ~
---
--- Start child process and connect to it. Won't work if child is already running.
---
---@param args table Array with arguments for executable. Will be prepended with
---   the following default arguments (see |startup-options|): >lua
---   { '--clean', '-n', '--listen', <some address>,
---     '--headless', '--cmd', 'set lines=24 columns=80' }
---@param opts table|nil Options:
---   - <nvim_executable> - name of Neovim executable. Default: |v:progpath|.
---   - <connection_timeout> - stop trying to connect after this amount of
---     milliseconds. Default: 5000.
---
---@usage >lua
---   child = MiniTest.new_child_neovim()
---
---   -- Start default clean Neovim instance
---   child.start()
---
---   -- Start with custom 'init.lua' file
---   child.start({ '-u', 'scripts/minimal_init.lua' })
--- <
---@tag MiniTest-child-neovim.start()

--- child.type_keys(wait, ...) ~
---
--- Basically a wrapper for |nvim_input()| applied inside child process.
--- Differences:
--- - Can wait after each group of characters.
--- - Raises error if typing keys resulted into error in child process (i.e. its
---   |v:errmsg| was updated).
--- - Key '<' as separate entry may not be escaped as '<LT>'.
---
---@param wait number|nil Number of milliseconds to wait after each entry. May be
---   omitted, in which case no waiting is done.
---@param ... string|table<number,string> Separate entries for |nvim_input()|,
---   after which `wait` will be applied. Can be either string or array of strings.
---
---@usage >lua
---   -- All of these type keys 'c', 'a', 'w'
---   child.type_keys('caw')
---   child.type_keys('c', 'a', 'w')
---   child.type_keys('c', { 'a', 'w' })
---
---   -- Waits 5 ms after `c` and after 'w'
---   child.type_keys(5, 'c', { 'a', 'w' })
---
---   -- Special keys can also be used
---   child.type_keys('i', 'Hello world', '<Esc>')
--- <
---@tag MiniTest-child-neovim.type_keys()

--- child.get_screenshot() ~
---
--- Compute what is displayed on (default TUI) screen and how it is displayed.
--- This basically calls |screenstring()| and |screenattr()| for every visible
--- cell (row from 1 to 'lines', column from 1 to 'columns').
---
--- Notes:
--- - To make output more portable and visually useful, outputs of
---   `screenattr()` are coded with single character symbols. Those are taken from
---   94 characters (ASCII codes between 33 and 126), so there will be duplicates
---   in case of more than 94 different ways text is displayed on screen.
---
---@param opts table|nil Options. Possieble fields:
---   - <redraw> `(boolean)` - whether to call |:redraw| prior to computing
---     screenshot. Default: `true`.
---
---@return table|nil Screenshot table with the following fields:
---   - <text> - "2d array" (row-column) of single characters displayed at
---     particular cells.
---   - <attr> - "2d array" (row-column) of symbols representing how text is
---     displayed (basically, "coded" appearance/highlighting). They should be
---     used only in relation to each other: same/different symbols for two
---     cells mean same/different visual appearance. Note: there will be false
---     positives if there are more than 94 different attribute values.
---   It also can be used with `tostring()` to convert to single string (used
---   for writing to reference file). It results into two visual parts
---   (separated by empty line), for `text` and `attr`. Each part has "ruler"
---   above content and line numbers for each line.
---   Returns `nil` if couldn't get a reasonable screenshot.
---
---@usage >lua
---   local screenshot = child.get_screenshot()
---
---   -- Show character displayed row=3 and column=4
---   print(screenshot.text[3][4])
---
---   -- Convert to string
---   tostring(screenshot)
--- <
---@tag MiniTest-child-neovim.get_screenshot()

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniTest.config)

-- Whether instance is running in headless mode
H.is_headless = #vim.api.nvim_list_uis() == 0

-- Cache for various data
H.cache = {
  -- Message with which case is meant to be skipped
  skip_message = nil,
  -- Queue of callables to be executed after step (hook or test function)
  finally = {},
  -- Whether to stop async execution
  should_stop_execution = false,
  -- Number of screenshots made in current case
  n_screenshots = 0,
}

-- Registry of all Neovim child processes
H.child_neovim_registry = {}

-- ANSI codes for common cases
H.ansi_codes = {
  fail = '\27[1;31m', -- Bold red
  pass = '\27[1;32m', -- Bold green
  emphasis = '\27[1m', -- Bold
  reset = '\27[0m',
}

-- Highlight groups for common ANSI codes
H.hl_groups = {
  ['\27[1;31m'] = 'MiniTestFail',
  ['\27[1;32m'] = 'MiniTestPass',
  ['\27[1m'] = 'MiniTestEmphasis',
}

-- Symbols used in reporter output
--stylua: ignore
H.reporter_symbols = setmetatable({
  ['Pass']            = H.ansi_codes.pass .. 'o' .. H.ansi_codes.reset,
  ['Pass with notes'] = H.ansi_codes.pass .. 'O' .. H.ansi_codes.reset,
  ['Fail']            = H.ansi_codes.fail .. 'x' .. H.ansi_codes.reset,
  ['Fail with notes'] = H.ansi_codes.fail .. 'X' .. H.ansi_codes.reset,
}, {
  __index = function() return H.ansi_codes.emphasis .. '?' .. H.ansi_codes.reset end,
})

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  H.check_type('collect', config.collect, 'table')
  H.check_type('collect.emulate_busted', config.collect.emulate_busted, 'boolean')
  H.check_type('collect.find_files', config.collect.find_files, 'function')
  H.check_type('collect.filter_cases', config.collect.filter_cases, 'function')

  H.check_type('execute', config.execute, 'table')
  H.check_type('execute.reporter', config.execute.reporter, 'table', true)
  H.check_type('execute.stop_on_error', config.execute.stop_on_error, 'boolean')

  H.check_type('script_path', config.script_path, 'string')
  H.check_type('silent', config.silent, 'boolean')

  return config
end

H.apply_config = function(config) MiniTest.config = config end

H.create_autocommands = function()
  local gr = vim.api.nvim_create_augroup('MiniTest', {})
  vim.api.nvim_create_autocmd('ColorScheme', { group = gr, callback = H.create_default_hl, desc = 'Ensure colors' })
end

H.create_default_hl = function()
  local set_default_hl = function(name, data)
    data.default = true
    vim.api.nvim_set_hl(0, name, data)
  end

  set_default_hl('MiniTestFail', { fg = vim.g.terminal_color_1 or '#FF0000', bold = true })
  set_default_hl('MiniTestPass', { fg = vim.g.terminal_color_2 or '#00FF00', bold = true })
  set_default_hl('MiniTestEmphasis', { bold = true })
end

H.is_disabled = function() return vim.g.minitest_disable == true or vim.b.minitest_disable == true end

H.get_config = function(config)
  return vim.tbl_deep_extend('force', MiniTest.config, vim.b.minitest_config or {}, config or {})
end

-- Work with collection -------------------------------------------------------
H.busted_emulate = function(set)
  local cur_set = set

  _G.describe = function(name, f)
    local cur_set_parent = cur_set
    cur_set_parent[name] = MiniTest.new_set()
    cur_set = cur_set_parent[name]
    f()
    cur_set = cur_set_parent
  end

  _G.it = function(name, f) cur_set[name] = f end

  local setting_hook = function(hook_name)
    return function(hook)
      local metatbl = getmetatable(cur_set)
      metatbl.opts.hooks = metatbl.opts.hooks or {}
      metatbl.opts.hooks[hook_name] = hook
    end
  end

  _G.setup = setting_hook('pre_once')
  _G.before_each = setting_hook('pre_case')
  _G.after_each = setting_hook('post_case')
  _G.teardown = setting_hook('post_once')
end

H.busted_deemulate = function()
  local fun_names = { 'describe', 'it', 'setup', 'before_each', 'after_each', 'teardown' }
  for _, f_name in ipairs(fun_names) do
    _G[f_name] = nil
  end
end

-- Work with execution --------------------------------------------------------
H.execute_project_script = function(...)
  -- Don't process script if there are more than one active `run` calls
  if H.is_inside_script then return false end

  -- Don't process script if at least one argument is not default (`nil`)
  if #{ ... } > 0 then return end

  -- Store information
  local config_cache = vim.deepcopy(MiniTest.config)
  local local_config_cache = vim.b.minitest_config

  -- Pass information to a possible `run()` call inside script
  H.is_inside_script = true

  -- Execute script
  local success = pcall(vim.cmd, 'luafile ' .. H.get_config().script_path)

  -- Restore information
  MiniTest.config = config_cache
  vim.b.minitest_config = local_config_cache
  H.is_inside_script = nil

  return success
end

H.schedule_case = function(case, case_num, opts)
  local update_state = function(state)
    case.exec.state = state
    H.exec_callable(opts.reporter.update, case_num)
  end

  local is_case_executed = false
  local on_err = function(e)
    if H.cache.skip_message ~= nil then
      -- Add skip message to notes (not fails) only during main case execution
      if is_case_executed then
        table.insert(case.exec.notes, H.cache.skip_message)
        H.cache.skip_message = nil
      end
      return true
    end

    -- Append traceback to error message and indent lines for pretty print
    local error_lines = { tostring(e), 'Traceback:', unpack(H.traceback()) }
    local error_msg = table.concat(error_lines, '\n'):gsub('\n', '\n  ')
    table.insert(case.exec.fails, error_msg)

    return false
  end

  local exec_step = function(f, state)
    update_state(state)

    H.cache.finally, H.cache.n_screenshots = {}, 0
    local ok_f, ok_err = xpcall(f, on_err)

    for _, fin in ipairs(H.cache.finally) do
      H.exec_callable(fin)
    end

    return ok_f or ok_err
  end

  local exec_hooks = function(name, source)
    local source_arr = case.hooks[name .. '_source']
    local state_prefix = "Executing '" .. name .. "' hook #"
    for i, h in ipairs(case.hooks[name]) do
      if source_arr[i] == source then exec_step(h, state_prefix .. i) end
    end
  end

  vim.schedule(function()
    if H.cache.should_stop_execution then return end

    case.exec = { fails = {}, notes = {} }
    MiniTest.current.case = case

    exec_hooks('pre', 'once')
    local exec_data = case.exec

    local ok_case
    for cur_try = 1, case.n_retry do
      -- Ensure that fails and notes are not accumulated during retries
      case.exec = vim.deepcopy(exec_data)

      -- Ensure that `skip()` affects only `pre_case` hooks and case
      H.cache.skip_message = nil

      -- Executing `*_case` hooks on every retry should ensure same case setup
      -- (like cleanly restarted child process)
      exec_hooks('pre', 'case')

      local case_f = function() case.test(unpack(case.args)) end
      if #case.exec.fails > 0 then
        case_f = function() table.insert(case.exec.notes, 'Skip case due to error(s) in hooks.') end
      end
      if H.cache.skip_message ~= nil then case_f = function() MiniTest.skip(H.cache.skip_message) end end

      is_case_executed = true
      ok_case = exec_step(case_f, 'Executing test')
      is_case_executed = false

      exec_hooks('post', 'case')

      if ok_case then break end
    end

    exec_hooks('post', 'once')

    update_state(H.case_final_state(case))

    if not ok_case and opts.stop_on_error then MiniTest.stop() end
  end)
end

-- Work with test cases -------------------------------------------------------
--- Convert test set to array of test cases
---
---@return ... Tuple of aligned arrays: with test cases and hooks that should
---   be executed only once before corresponding item.
---@private
H.set_to_testcases = function(set, template, hooks_once)
  template = template or { args = {}, desc = {}, hooks = { pre = {}, post = {} }, data = {}, n_retry = 1 }
  hooks_once = hooks_once or { pre = {}, post = {} }

  local metatbl = getmetatable(set)
  local opts, key_order = metatbl.opts, metatbl.key_order
  local hooks, parametrize, data, n_retry = opts.hooks or {}, opts.parametrize or { {} }, opts.data or {}, opts.n_retry

  -- Convert to steps only callable or test set nodes
  -- Ensure that all elements of `set` are being considered (might not be the
  -- case if `table.insert` was used, for example)
  key_order = H.ensure_all_vals(key_order, vim.tbl_keys(set))
  local node_keys = vim.tbl_filter(function(key)
    local node = set[key]
    return vim.is_callable(node) or H.is_instance(node, 'testset')
  end, key_order)

  if #node_keys == 0 then return {}, {} end

  -- Ensure that newly added hooks are represented by new functions.
  -- This is needed to count them later only within current set. Example: use
  -- the same function in several `_once` hooks. In `H.inject_hooks_once` it
  -- will be injected only once overall whereas it should be injected only once
  -- within corresponding test set.
  hooks_once =
    H.extend_hooks(hooks_once, { pre = H.wrap_callable(hooks.pre_once), post = H.wrap_callable(hooks.post_once) })

  local testcase_arr, hooks_once_arr = {}, {}
  -- Process nodes in order they were added as `T[...] = x`
  for _, key in ipairs(node_keys) do
    local node = set[key]
    for _, args in ipairs(parametrize) do
      if type(args) ~= 'table' then H.error('`parametrize` should have only tables. Got ' .. vim.inspect(args)) end

      local cur_template = H.extend_template(template, {
        args = args,
        desc = type(key) == 'string' and key:gsub('\n', '\\n') or key,
        hooks = { pre = hooks.pre_case, post = hooks.post_case },
        data = data,
        n_retry = n_retry,
      })

      if vim.is_callable(node) then
        table.insert(testcase_arr, H.new_testcase(cur_template, node))
        table.insert(hooks_once_arr, hooks_once)
      elseif H.is_instance(node, 'testset') then
        local nest_testcase_arr, nest_hooks_once_arr = H.set_to_testcases(node, cur_template, hooks_once)
        vim.list_extend(testcase_arr, nest_testcase_arr)
        vim.list_extend(hooks_once_arr, nest_hooks_once_arr)
      end
    end
  end

  return testcase_arr, hooks_once_arr
end

H.ensure_all_vals = function(arr_subset, arr_all)
  local vals_registry = {}
  for _, v in ipairs(arr_subset) do
    vals_registry[v] = true
  end

  for _, v in ipairs(arr_all) do
    if not vals_registry[v] then
      table.insert(arr_subset, v)
      vals_registry[v] = true
    end
  end

  return arr_subset
end

H.inject_hooks_once = function(cases, hooks_once)
  -- NOTE: this heavily relies on the equivalence of "have same object id" and
  -- "are same hooks"
  local already_injected, n = {}, #cases

  -- Inject 'pre' hooks moving forwards
  for i = 1, n do
    local case, hooks = cases[i], hooks_once[i].pre
    case.hooks.pre_source = vim.tbl_map(function() return 'case' end, case.hooks.pre)
    local target_tbl_id = 1
    for j = 1, #hooks do
      local h = hooks[j]
      if not already_injected[h] then
        table.insert(case.hooks.pre, target_tbl_id, h)
        table.insert(case.hooks.pre_source, target_tbl_id, 'once')
        target_tbl_id, already_injected[h] = target_tbl_id + 1, true
      end
    end
  end

  -- Inject 'post' hooks moving backwards
  for i = n, 1, -1 do
    local case, hooks = cases[i], hooks_once[i].post
    case.hooks.post_source = vim.tbl_map(function() return 'case' end, case.hooks.post)
    local target_tbl_id = #case.hooks.post + 1
    for j = #hooks, 1, -1 do
      local h = hooks[j]
      if not already_injected[h] then
        table.insert(case.hooks.post, target_tbl_id, h)
        table.insert(case.hooks.post_source, target_tbl_id, 'once')
        already_injected[h] = true
      end
    end
  end

  return cases
end

H.new_testcase = function(template, test)
  template.test = test
  return template
end

H.extend_template = function(template, layer)
  local res = vim.deepcopy(template)

  vim.list_extend(res.args, layer.args)
  table.insert(res.desc, layer.desc)
  res.hooks = H.extend_hooks(res.hooks, layer.hooks, false)
  res.data = vim.tbl_deep_extend('force', res.data, layer.data)
  res.n_retry = layer.n_retry or res.n_retry or 1

  return res
end

H.extend_hooks = function(hooks, layer, do_deepcopy)
  local res = hooks
  if do_deepcopy == nil or do_deepcopy then res = vim.deepcopy(hooks) end

  -- Closer (in terms of nesting) hooks should be closer to test callable
  if vim.is_callable(layer.pre) then table.insert(res.pre, layer.pre) end
  if vim.is_callable(layer.post) then table.insert(res.post, 1, layer.post) end

  return res
end

H.case_to_stringid = function(case)
  local desc = table.concat(case.desc, ' | ')
  if #case.args == 0 then return desc end
  local args = vim.inspect(case.args, { newline = '', indent = '' })
  return ('%s + args %s'):format(desc, args)
end

H.case_final_state = function(case)
  local pass_fail = #case.exec.fails == 0 and 'Pass' or 'Fail'
  local with_notes = #case.exec.notes == 0 and '' or ' with notes'
  return string.format('%s%s', pass_fail, with_notes)
end

-- Dynamic overview reporter --------------------------------------------------
H.overview_reporter = {}

H.overview_reporter.compute_groups = function(cases, group_depth)
  local default_symbol = H.reporter_symbols[nil]
  return vim.tbl_map(function(c)
    local desc_trunc = vim.list_slice(c.desc, 1, group_depth)
    local name = table.concat(desc_trunc, ' | ')
    return { name = name, symbol = default_symbol }
  end, cases)
end

H.overview_reporter.start_lines = function(cases, groups)
  local unique_names = {}
  for _, g in ipairs(groups) do
    unique_names[g.name] = true
  end
  local n_groups = #vim.tbl_keys(unique_names)

  return {
    string.format('%s %s', H.add_style('Total number of cases:', 'emphasis'), #cases),
    string.format('%s %s', H.add_style('Total number of groups:', 'emphasis'), n_groups),
    '',
  }
end

H.overview_reporter.finish_lines = function(cases)
  local res = {}

  -- Show all fails and notes
  local n_fails, n_notes = 0, 0
  for _, c in ipairs(cases) do
    local stringid = H.case_to_stringid(c)
    local exec = c.exec == nil and { fails = {}, notes = {} } or c.exec

    local fail_prefix = string.format('%s in %s: ', H.add_style('FAIL', 'fail'), stringid)
    local note_color = #exec.fails > 0 and 'fail' or 'pass'
    local note_prefix = string.format('%s in %s: ', H.add_style('NOTE', note_color), stringid)

    n_fails = n_fails + #exec.fails
    n_notes = n_notes + #exec.notes

    local cur_fails_notes = {}
    vim.list_extend(cur_fails_notes, H.add_prefix(exec.fails, fail_prefix))
    vim.list_extend(cur_fails_notes, H.add_prefix(exec.notes, note_prefix))

    if #cur_fails_notes > 0 then
      cur_fails_notes = vim.split(table.concat(cur_fails_notes, '\n'), '\n')
      vim.list_extend(res, cur_fails_notes)

      -- Add empty line to separate fails and notes from different cases
      table.insert(res, '')
    end
  end

  local header = string.format('Fails (%s) and Notes (%s)', n_fails, n_notes)
  table.insert(res, 1, H.add_style(header, 'emphasis'))

  return res
end

-- Buffer reporter utilities --------------------------------------------------
H.buffer_reporter = { ns_id = vim.api.nvim_create_namespace('MiniTestBuffer'), n_buffer = 0 }

H.buffer_reporter.setup_buf_and_win = function(window_opts)
  local buf_id = vim.api.nvim_create_buf(true, true)
  H.set_buf_name(buf_id, 'buffer-reporter')

  local win_id
  if vim.is_callable(window_opts) then
    win_id = window_opts()
  elseif type(window_opts) == 'table' then
    -- Ensure proper title
    if type(window_opts.title) == 'string' then
      window_opts.title = H.fit_to_width(window_opts.title, window_opts.width)
    end
    win_id = vim.api.nvim_open_win(buf_id, true, window_opts)
  end
  win_id = win_id or vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win_id, buf_id)

  H.buffer_reporter.set_options(buf_id, win_id)
  H.buffer_reporter.set_mappings(buf_id)

  return buf_id, win_id
end

H.buffer_reporter.default_window_opts = function()
  return {
    relative = 'editor',
    width = math.floor(0.618 * vim.o.columns),
    height = math.floor(0.618 * vim.o.lines),
    row = math.floor(0.191 * vim.o.lines),
    col = math.floor(0.191 * vim.o.columns),
    border = (vim.fn.exists('+winborder') == 1 and vim.o.winborder ~= '') and vim.o.winborder or 'single',
    title = ' Test results ',
  }
end

H.buffer_reporter.set_options = function(buf_id, win_id)
  -- Set unique name
  local n_buffer = H.buffer_reporter.n_buffer + 1
  local suffix = n_buffer == 1 and '' or (' ' .. n_buffer)
  H.buffer_reporter.n_buffer = n_buffer

  vim.cmd('silent! set filetype=minitest')

  --stylua: ignore start
  -- Set options for "temporary" buffer
  local buf_options = {
    bufhidden = 'wipe', buflisted = false, buftype = 'nofile', modeline = false, swapfile = false,
  }
  for name, value in pairs(buf_options) do
    vim.bo[buf_id][name] = value
  end

  -- Set options for "clean" window
  local win_options = {
    colorcolumn = '', fillchars = 'eob: ',    foldcolumn = '0', foldlevel = 999,
    number = false,   relativenumber = false, spell = false,    signcolumn = 'no',
    wrap = true,
  }
  for name, value in pairs(win_options) do
    vim.wo[win_id][name] = value
  end
  --stylua: ignore end
end

H.buffer_reporter.set_mappings = function(buf_id)
  local rhs = [[<Cmd>lua if MiniTest.is_executing() then MiniTest.stop() else vim.cmd('close') end<CR>]]
  vim.keymap.set('n', '<Esc>', rhs, { buffer = buf_id, desc = 'Stop execution or close window' })
  vim.keymap.set('n', 'q', rhs, { buffer = buf_id, desc = 'Stop execution or close window' })
end

H.buffer_reporter.set_lines = function(buf_id, lines, start, finish)
  local ns_id = H.buffer_reporter.ns_id

  local n_lines = vim.api.nvim_buf_line_count(buf_id)
  start = (start < 0) and (n_lines + 1 + start) or start
  finish = (finish < 0) and (n_lines + 1 + finish) or finish

  -- Remove ANSI codes while tracking appropriate highlight data
  local new_lines, hl_ranges = {}, {}
  for i, l in ipairs(lines) do
    local n_removed = 0
    local new_l = l:gsub('\n', '\\n'):gsub('()(\27%[.-m)(.-)\27%[0m', function(...)
      local dots = { ... }
      local left = dots[1] - n_removed
      table.insert(
        hl_ranges,
        { hl = H.hl_groups[dots[2]], line = start + i - 1, left = left - 1, right = left + dots[3]:len() - 1 }
      )

      -- Here `4` is `string.len('\27[0m')`
      n_removed = n_removed + dots[2]:len() + 4
      return dots[3]
    end)
    table.insert(new_lines, new_l)
  end

  -- Clear highlighting on updated lines. Crucial because otherwise it will
  -- lead to A LOT of memory consumption.
  vim.api.nvim_buf_clear_namespace(buf_id, H.buffer_reporter.ns_id, start, finish)

  -- Set lines
  vim.api.nvim_buf_set_lines(buf_id, start, finish, true, new_lines)

  -- Add highlight
  for _, hl_data in ipairs(hl_ranges) do
    H.highlight_range(buf_id, ns_id, hl_data.hl, { hl_data.line, hl_data.left }, { hl_data.line, hl_data.right })
  end
end

H.buffer_reporter.update_step_lines = function(case_num, cases, groups)
  local cur_case = cases[case_num]
  local cur_group = groups[case_num].name

  -- Don't show anything before empty group name (when `group_depth` is 0)
  local cur_group_suffix = cur_group == '' and '' or ': '
  local cur_group_symbols = vim.tbl_map(
    function(g) return g.symbol end,
    vim.tbl_filter(function(g) return g.name == cur_group end, groups)
  )

  return {
    -- Group overview
    string.format('%s%s%s', cur_group, cur_group_suffix, table.concat(cur_group_symbols)),
    '',
    H.add_style('Current case state', 'emphasis'),
    string.format('%s: %s', H.case_to_stringid(cur_case), cur_case.exec.state),
  }
end

H.buffer_reporter.update_step_n_replace = function(latest_group_name, cur_group_name)
  -- By default rewrite latest group symbol overview
  local res = 4

  if latest_group_name == nil then
    -- Nothing to rewrite on first ever call
    res = 0
  elseif latest_group_name ~= cur_group_name then
    -- Write just under latest group symbol overview
    res = 3
  end

  return res
end

-- Predicates -----------------------------------------------------------------
H.is_instance = function(x, class)
  local metatbl = getmetatable(x)
  return type(metatbl) == 'table' and metatbl.class == class
end

H.has_fails = function(cases)
  for _, c in ipairs(cases) do
    local n_fails = c.exec == nil and 0 or #c.exec.fails
    if n_fails > 0 then return true end
  end
  return false
end

-- Expectation utilities ------------------------------------------------------
H.error_expect = function(subject, ...)
  local msg = string.format('Failed expectation for %s.', subject)
  H.error_with_emphasis(msg, ...)
end

H.error_with_emphasis = function(msg, ...)
  local lines = { '', H.add_style(msg, 'emphasis'), ... }
  error(table.concat(lines, '\n'), 0)
end

H.traceback = function()
  local level, res = 1, {}
  local info = debug.getinfo(level, 'Snl')
  local this_short_src = info.short_src
  while info ~= nil do
    local is_from_file = info.source:sub(1, 1) == '@'
    local is_from_this_file = info.short_src == this_short_src
    if is_from_file and not is_from_this_file then
      local line = string.format([[  %s:%s]], info.short_src, info.currentline)
      table.insert(res, line)
    end
    level = level + 1
    info = debug.getinfo(level, 'Snl')
  end

  return res
end

-- Screenshots ----------------------------------------------------------------
H.screenshot_new = function(t)
  local process_screen = function(arr_2d)
    local n_lines, n_cols = #arr_2d, #arr_2d[1]

    -- Prepend lines with line number of the form `01|`
    local n_digits = math.floor(math.log10(n_lines)) + 1
    local format = string.format('%%0%dd|%%s', n_digits)
    local lines = {}
    for i = 1, n_lines do
      table.insert(lines, string.format(format, i, table.concat(arr_2d[i])))
    end

    -- Make ruler
    local prefix = string.rep('-', n_digits) .. '|'
    local ruler = prefix .. ('---------|'):rep(math.ceil(0.1 * n_cols)):sub(1, n_cols)

    return string.format('%s\n%s', ruler, table.concat(lines, '\n'))
  end

  return setmetatable(t, {
    __tostring = function(x) return string.format('%s\n\n%s', process_screen(x.text), process_screen(x.attr)) end,
  })
end

H.screenshot_encode_attr = function(attr)
  local attr_codes, res = {}, {}
  -- Use 48 so that codes start from `'0'`
  local cur_code_id = 48
  for _, l in ipairs(attr) do
    local res_line = {}
    for _, s in ipairs(l) do
      -- Assign character codes to numerical attributes in order of their
      -- appearance on the screen. This leads to be a more reliable way of
      -- comparing two different screenshots (at cost of bigger effect when
      -- screenshot changes slightly).
      if not attr_codes[s] then
        attr_codes[s] = string.char(cur_code_id)
        -- Cycle through 33...126
        cur_code_id = math.fmod(cur_code_id + 1 - 33, 94) + 33
      end
      table.insert(res_line, attr_codes[s])
    end
    table.insert(res, res_line)
  end

  return res
end

H.screenshot_compare_part = function(part, ref, obs, opts)
  local ignore_part, ignore_lines = opts['ignore_' .. part], opts.ignore_lines
  if ignore_part == true then return true, '' end

  local compare = function(x, y, desc)
    if x == y then return true, '' end
    return false, ('Different %s. Reference: %s. Observed: %s.'):format(desc, vim.inspect(x), vim.inspect(y))
  end

  local ok, cause
  ok, cause = compare(#ref[part], #obs[part], 'number of `' .. part .. '` lines')
  if not ok then return ok, cause end

  local lines_to_check = {}
  for i = 1, #ref[part] do
    local is_ignore_part = type(ignore_part) == 'table' and vim.tbl_contains(ignore_part, i)
    if not (is_ignore_part or vim.tbl_contains(ignore_lines, i)) then table.insert(lines_to_check, i) end
  end

  for _, i in ipairs(lines_to_check) do
    ok, cause = compare(#ref[part][i], #obs[part][i], 'number of columns in `' .. part .. '` line ' .. i)
    if not ok then return ok, cause end

    for j = 1, #ref[part][i] do
      ok, cause = compare(ref[part][i][j], obs[part][i][j], '`' .. part .. '` cell at line ' .. i .. ' column ' .. j)
      if not ok then return ok, cause end
    end
  end

  return true, ''
end

H.screenshot_write = function(screenshot, path) vim.fn.writefile(vim.split(tostring(screenshot), '\n'), path) end

H.screenshot_read = function(path)
  -- General structure of screenshot with `n` lines:
  -- 1: ruler-separator
  -- 2, n+1: `prefix`|`text`
  -- n+2: empty line
  -- n+3: ruler-separator
  -- n+4, 2n+3: `prefix`|`attr`
  local lines = vim.fn.readfile(path)
  local n = 0.5 * (#lines - 3)
  local text_lines, attr_lines = vim.list_slice(lines, 2, n + 1), vim.list_slice(lines, n + 4, 2 * n + 3)

  local f = function(x) return H.string_to_chars(x:gsub('^%d+|', '')) end
  return H.screenshot_new({ text = vim.tbl_map(f, text_lines), attr = vim.tbl_map(f, attr_lines) })
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.test) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.set_buf_name = function(buf_id, name) vim.api.nvim_buf_set_name(buf_id, 'minitest://' .. buf_id .. '/' .. name) end

H.echo = function(msg, is_important)
  if H.get_config().silent then return end

  -- Construct message chunks
  msg = type(msg) == 'string' and { { msg } } or msg
  table.insert(msg, 1, { '(mini.test) ', 'WarningMsg' })

  -- Echo. Force redraw to ensure that it is effective (`:h echo-redraw`)
  vim.cmd([[echo '' | redraw]])
  vim.api.nvim_echo(msg, is_important, {})
end

H.message = function(msg) H.echo(msg, true) end

H.wrap_callable = function(f)
  if not vim.is_callable(f) then return end
  return function(...) return f(...) end
end

H.exec_callable = function(f, ...)
  if not vim.is_callable(f) then return end
  return f(...)
end

H.add_prefix = function(tbl, prefix)
  return vim.tbl_map(function(x)
    local p = prefix
    -- Do not create trailing whitespace
    if x:sub(1, 1) == '\n' then p = p:gsub('%s*$', '') end
    return ('%s%s'):format(p, x)
  end, tbl)
end

H.add_style = function(x, ansi_code) return string.format('%s%s%s', H.ansi_codes[ansi_code], x, H.ansi_codes.reset) end

H.fit_to_width = function(text, width)
  local t_width = vim.fn.strchars(text)
  return t_width <= width and text or ('…' .. vim.fn.strcharpart(text, t_width - width + 1, width - 1))
end

H.string_to_chars = function(s)
  -- Can't use `vim.split(s, '')` because of multibyte characters
  local res = {}
  for i = 1, vim.fn.strchars(s) do
    table.insert(res, vim.fn.strcharpart(s, i - 1, 1))
  end
  return res
end

-- TODO: Remove after compatibility with Neovim=0.9 is dropped
H.tbl_flatten = vim.fn.has('nvim-0.10') == 1 and function(x) return vim.iter(x):flatten(math.huge):totable() end
  or vim.tbl_flatten

-- TODO: Remove after compatibility with Neovim=0.10 is dropped
H.highlight_range = function(...) vim.hl.range(...) end
if vim.fn.has('nvim-0.11') == 0 then H.highlight_range = function(...) vim.highlight.range(...) end end

return MiniTest
