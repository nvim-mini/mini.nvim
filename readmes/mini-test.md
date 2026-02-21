<p align="center"> <img src="https://github.com/nvim-mini/assets/blob/main/logo-2/logo-test_readme.png?raw=true" alt="mini.test" style="max-width:100%;border:solid 2px"/> </p>

### Write and use extensive Neovim plugin tests

- Supports hierarchical tests, hooks, parametrization, filtering (like from current file or cursor position), screen tests, "busted-style" emulation, customizable reporters, and more.
- Designed to be used with provided wrapper for managing child Neovim processes.

See more details in [Features](#features) and [Documentation](../doc/mini-test.txt). For more hands-on introduction based on examples, see [TESTING.md](https://nvim-mini.org/mini.nvim/TESTING). For more in-depth usage see ['mini.nvim' tests](https://github.com/nvim-mini/mini.nvim/tree/main/tests).

---

> [!NOTE]
> This was previously hosted at a personal `echasnovski` GitHub account. It was transferred to a dedicated organization to improve long term project stability. See more details [here](https://github.com/nvim-mini/mini.nvim/discussions/1970).

⦿ This is a part of [mini.nvim](https://nvim-mini.org/mini.nvim) library. Please use [this link](https://nvim-mini.org/mini.nvim/readmes/mini-test) if you want to mention this module.

⦿ All contributions (issues, pull requests, discussions, etc.) are done inside of 'mini.nvim'.

⦿ See [whole library documentation](https://nvim-mini.org/mini.nvim/doc/mini-nvim) to learn about general design principles, disable/configuration recipes, and more.

---

If you want to help this project grow but don't know where to start, check out [contributing guides of 'mini.nvim'](https://nvim-mini.org/mini.nvim/CONTRIBUTING) or leave a Github star for 'mini.nvim' project and/or any its standalone Git repositories.

## Demo

<!-- Demo source: https://github.com/nvim-mini/assets/blob/main/demo/demo-test.mp4 -->
https://user-images.githubusercontent.com/24854248/175773105-f33cd3bb-6f62-4a61-95b1-b175e11905bb.mp4

## Features

- Test action is defined as a named callable entry of a table.
- Helper for creating child Neovim process which is designed to be used in tests (including taking and verifying screenshots). See help for `MiniTest.new_child_neovim()` and `MiniTest.expect.reference_screenshot()`.
- Hierarchical organization of tests with custom hooks, parametrization, and user data. See help for `MiniTest.new_set()`.
- Emulation of [Olivine-Labs/busted](https://github.com/Olivine-Labs/busted) interface (`describe`, `it`, etc.).
- Predefined small yet usable set of expectations (`assert`-like functions). See help for `MiniTest.expect`.
- Customizable definition of what files should be tested.
- Test case filtering. There are predefined wrappers for testing a file (`MiniTest.run_file()`) and case at a location like current cursor position (`MiniTest.run_at_location()`).
- Customizable reporter of output results. There are two predefined ones:
    - `MiniTest.gen_reporter.buffer()` for interactive usage.
    - `MiniTest.gen_reporter.stdout()` for headless Neovim.
- Customizable project specific testing script.
- Works on Unix (Linux, MacOS, etc.) and Windows.

## Installation

This plugin can be installed as part of 'mini.nvim' library (**recommended**) or as a standalone Git repository.

There are two branches to install from:

- `main` (default, **recommended**) will have latest development version of plugin. All changes since last stable release should be perceived as being in beta testing phase (meaning they already passed alpha-testing and are moderately settled).
- `stable` will be updated only upon releases with code tested during public beta-testing phase in `main` branch.

Here are code snippets for some common installation methods (use only one):

<details>
<summary>With <a href="https://nvim-mini.org/mini.nvim/readmes/mini-deps">mini.deps</a></summary>

- 'mini.nvim' library:

    | Branch | Code snippet                                  |
    |--------|-----------------------------------------------|
    | Main   | *Follow recommended 'mini.deps' installation* |
    | Stable | *Follow recommended 'mini.deps' installation* |

- Standalone plugin:

    | Branch | Code snippet                                                   |
    |--------|----------------------------------------------------------------|
    | Main   | `add('nvim-mini/mini.test')`                                   |
    | Stable | `add({ source = 'nvim-mini/mini.test', checkout = 'stable' })` |

</details>

<details>
<summary>With <a href="https://github.com/folke/lazy.nvim">folke/lazy.nvim</a></summary>

- 'mini.nvim' library:

    | Branch | Code snippet                                  |
    |--------|-----------------------------------------------|
    | Main   | `{ 'nvim-mini/mini.nvim', version = false },` |
    | Stable | `{ 'nvim-mini/mini.nvim', version = '*' },`   |

- Standalone plugin:

    | Branch | Code snippet                                  |
    |--------|-----------------------------------------------|
    | Main   | `{ 'nvim-mini/mini.test', version = false },` |
    | Stable | `{ 'nvim-mini/mini.test', version = '*' },`   |

</details>

<details>
<summary>With <a href="https://github.com/junegunn/vim-plug">junegunn/vim-plug</a></summary>

- 'mini.nvim' library:

    | Branch | Code snippet                                         |
    |--------|------------------------------------------------------|
    | Main   | `Plug 'nvim-mini/mini.nvim'`                         |
    | Stable | `Plug 'nvim-mini/mini.nvim', { 'branch': 'stable' }` |

- Standalone plugin:

    | Branch | Code snippet                                         |
    |--------|------------------------------------------------------|
    | Main   | `Plug 'nvim-mini/mini.test'`                         |
    | Stable | `Plug 'nvim-mini/mini.test', { 'branch': 'stable' }` |

</details>

**Important**: don't forget to call `require('mini.test').setup()` to enable its functionality.

**Note**: if you are on Windows, there might be problems with too long file paths (like `error: unable to create file <some file name>: Filename too long`). Try doing one of the following:

- Enable corresponding git global config value: `git config --system core.longpaths true`. Then try to reinstall.
- Install plugin in other place with shorter path.

## Default config

```lua
-- No need to copy this inside `setup()`. Will be used automatically.
{
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
```

## Similar plugins

- [nvim-lua/plenary.nvim](https://github.com/nvim-lua/plenary.nvim) ('test_harness', 'busted', 'luassert' modules)
