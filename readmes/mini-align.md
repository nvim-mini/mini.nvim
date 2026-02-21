<p align="center"> <img src="https://github.com/nvim-mini/assets/blob/main/logo-2/logo-align_readme.png?raw=true" alt="mini.align" style="max-width:100%;border:solid 2px"/> </p>

### Align text interactively

See more details in [Features](#features) and [Documentation](../doc/mini-align.txt).

---

> [!NOTE]
> This was previously hosted at a personal `echasnovski` GitHub account. It was transferred to a dedicated organization to improve long term project stability. See more details [here](https://github.com/nvim-mini/mini.nvim/discussions/1970).

⦿ This is a part of [mini.nvim](https://nvim-mini.org/mini.nvim) library. Please use [this link](https://nvim-mini.org/mini.nvim/readmes/mini-align) if you want to mention this module.

⦿ All contributions (issues, pull requests, discussions, etc.) are done inside of 'mini.nvim'.

⦿ See [whole library documentation](https://nvim-mini.org/mini.nvim/doc/mini-nvim) to learn about general design principles, disable/configuration recipes, and more.

⦿ See [MiniMax](https://nvim-mini.org/MiniMax) for a full config example that uses this module.

---

If you want to help this project grow but don't know where to start, check out [contributing guides of 'mini.nvim'](https://nvim-mini.org/mini.nvim/CONTRIBUTING) or leave a Github star for 'mini.nvim' project and/or any its standalone Git repositories.

## Demo

<!-- Demo source: https://github.com/nvim-mini/assets/blob/main/demo/demo-align.mp4 -->
https://user-images.githubusercontent.com/24854248/191686791-2c8b345a-2bcc-4de7-a065-5e7a36e2eb1a.mp4

## Features

- Alignment is done in three main steps:
    - **Split** lines into parts based on Lua pattern(s) or user-supplied rule.
    - **Justify** parts for certain side(s) to be same width inside columns.
    - **Merge** parts to be lines, with customizable delimiter(s).

    Each main step can be preceded by other steps (pre-steps) to achieve highly customizable outcome. See `steps` value in `:h MiniAlign.config`. For more details, see `:h MiniAlign-glossary` and `:h MiniAlign-algorithm`.
- User can control alignment interactively by pressing customizable modifiers (single keys representing how alignment steps and/or options should change). Some of default modifiers:
    - Press `s` to enter split Lua pattern.
    - Press `j` to choose justification side from available ones ("left", "center", "right", "none").
    - Press `m` to enter merge delimiter.
    - Press `f` to enter filter Lua expression to configure which parts will be affected (like "align only first column").
    - Press `i` to ignore some commonly unwanted split matches.
    - Press `p` to pair neighboring parts so they be aligned together.
    - Press `t` to trim whitespace from parts.
    - Press `<BS>` (backspace) to delete some last pre-step.

    For more details, see `:h MiniAlign-modifiers-builtin` and `:h MiniAlign-examples`.
- Alignment can be done with instant preview (result is updated after each modifier) or without it (result is shown and accepted after non-default split pattern is set).
- Every user interaction is accompanied with helper status message showing relevant information about current alignment process.

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

    | Branch | Code snippet                                                    |
    |--------|-----------------------------------------------------------------|
    | Main   | `add('nvim-mini/mini.align')`                                   |
    | Stable | `add({ source = 'nvim-mini/mini.align', checkout = 'stable' })` |

</details>

<details>
<summary>With <a href="https://github.com/folke/lazy.nvim">folke/lazy.nvim</a></summary>

- 'mini.nvim' library:

    | Branch | Code snippet                                  |
    |--------|-----------------------------------------------|
    | Main   | `{ 'nvim-mini/mini.nvim', version = false },` |
    | Stable | `{ 'nvim-mini/mini.nvim', version = '*' },`   |

- Standalone plugin:

    | Branch | Code snippet                                   |
    |--------|------------------------------------------------|
    | Main   | `{ 'nvim-mini/mini.align', version = false },` |
    | Stable | `{ 'nvim-mini/mini.align', version = '*' },`   |

</details>

<details>
<summary>With <a href="https://github.com/junegunn/vim-plug">junegunn/vim-plug</a></summary>

- 'mini.nvim' library:

    | Branch | Code snippet                                         |
    |--------|------------------------------------------------------|
    | Main   | `Plug 'nvim-mini/mini.nvim'`                         |
    | Stable | `Plug 'nvim-mini/mini.nvim', { 'branch': 'stable' }` |

- Standalone plugin:

    | Branch | Code snippet                                          |
    |--------|-------------------------------------------------------|
    | Main   | `Plug 'nvim-mini/mini.align'`                         |
    | Stable | `Plug 'nvim-mini/mini.align', { 'branch': 'stable' }` |

</details>

**Important**: don't forget to call `require('mini.align').setup()` to enable its functionality.

**Note**: if you are on Windows, there might be problems with too long file paths (like `error: unable to create file <some file name>: Filename too long`). Try doing one of the following:

- Enable corresponding git global config value: `git config --system core.longpaths true`. Then try to reinstall.
- Install plugin in other place with shorter path.

## Default config

```lua
-- No need to copy this inside `setup()`. Will be used automatically.
{
  -- Module mappings. Use `''` (empty string) to disable one.
  mappings = {
    start = 'ga',
    start_with_preview = 'gA',
  },

  -- Modifiers changing alignment steps and/or options
  modifiers = {
    -- Main option modifiers
    ['s'] = --<function: enter split pattern>,
    ['j'] = --<function: choose justify side>,
    ['m'] = --<function: enter merge delimiter>,

    -- Modifiers adding pre-steps
    ['f'] = --<function: filter parts by entering Lua expression>,
    ['i'] = --<function: ignore some split matches>,
    ['p'] = --<function: pair parts>,
    ['t'] = --<function: trim parts>,

    -- Delete some last pre-step
    ['<BS>'] = --<function: delete some last pre-step>,

    -- Special configurations for common splits
    ['='] = --<function: enhanced setup for '='>,
    [','] = --<function: enhanced setup for ','>,
    ['|'] = --<function: enhanced setup for '|'>,
    [' '] = --<function: enhanced setup for ' '>,
  },

  -- Default options controlling alignment process
  options = {
    split_pattern = '',
    justify_side = 'left',
    merge_delimiter = '',
  },

  -- Default steps performing alignment (if `nil`, default is used)
  steps = {
    pre_split = {},
    split = nil,
    pre_justify = {},
    justify = nil,
    pre_merge = {},
    merge = nil,
  },

  -- Whether to disable showing non-error feedback
  -- This also affects (purely informational) helper messages shown after
  -- idle time if user input is required.
  silent = false,
}
```

## Similar plugins

- [junegunn/vim-easy-align](https://github.com/junegunn/vim-easy-align)
- [godlygeek/tabular](https://github.com/godlygeek/tabular)
- [tommcdo/vim-lion](https://github.com/tommcdo/vim-lion)
- [Vonr/align.nvim](https://github.com/Vonr/align.nvim)
