<p align="center"> <img src="https://github.com/nvim-mini/assets/blob/main/logo-2/logo-surround_readme.png?raw=true" alt="mini.surround" style="max-width:100%;border:solid 2px"/> </p>

### Fast and feature-rich surround actions

- Add, delete, replace, find, highlight surrounding (like pair of parenthesis, quotes, etc.).
- Supports dot-repeat for text edits, `v:count`, different search methods, "last"/"next" extended mappings, customization via Lua patterns or functions, and more.
- Has builtins for brackets, function call, tag, user prompt, and any alphanumeric/punctuation/whitespace character.
- Has maintained configuration of setup similar to 'tpope/vim-surround'.

See more details in [Features](#features) and [Documentation](../doc/mini-surround.txt).

---

> [!NOTE]
> This was previously hosted at a personal `echasnovski` GitHub account. It was transferred to a dedicated organization to improve long term project stability. See more details [here](https://github.com/nvim-mini/mini.nvim/discussions/1970).

⦿ This is a part of [mini.nvim](https://nvim-mini.org/mini.nvim) library. Please use [this link](https://nvim-mini.org/mini.nvim/readmes/mini-surround) if you want to mention this module.

⦿ All contributions (issues, pull requests, discussions, etc.) are done inside of 'mini.nvim'.

⦿ See [whole library documentation](https://nvim-mini.org/mini.nvim/doc/mini-nvim) to learn about general design principles, disable/configuration recipes, and more.

⦿ See [MiniMax](https://nvim-mini.org/MiniMax) for a full config example that uses this module.

---

If you want to help this project grow but don't know where to start, check out [contributing guides of 'mini.nvim'](https://nvim-mini.org/mini.nvim/CONTRIBUTING) or leave a Github star for 'mini.nvim' project and/or any its standalone Git repositories.

## Demo

<!-- Demo source: https://github.com/nvim-mini/assets/blob/main/demo/demo-surround.mp4 -->
https://github.com/user-attachments/assets/e91b6e16-7a9c-44aa-afb4-7e07efc3e811

## Features

- Actions (text editing actions are dot-repeatable out of the box and respect `[count]`) with configurable mappings:
    - Add surrounding with `sa` (in visual mode or on motion).
    - Delete surrounding with `sd`.
    - Replace surrounding with `sr`.
    - Find surrounding with `sf` or `sF` (move cursor right or left).
    - Highlight surrounding with `sh`.
- Surrounding is identified by a single character as both "input" (in `delete` and `replace` start, `find`, and `highlight`) and "output" (in `add` and `replace` end):
    - 'f' - function call (string of alphanumeric symbols or '_' or '.' followed by balanced '()'). In "input" finds function call, in "output" prompts user to enter function name.
    - 't' - tag. In "input" finds tag with same identifier, in "output" prompts user to enter tag name.
    - All symbols in brackets '()', '[]', '{}', '<>". In "input' represents balanced brackets (open - with whitespace pad, close - without), in "output" - left and right parts of brackets.
    - '?' - interactive. Prompts user to enter left and right parts.
    - All other single character identifiers (supported by `getcharstr()`) represent surrounding with identical left and right parts.
- Configurable search methods to find not only covering but possibly next, previous, or nearest surrounding. See more in help for `MiniSurround.config`.
- All actions involving finding surrounding (delete, replace, find, highlight) can be used with suffix that changes search method to find previous/last. See more in help for `MiniSurround.config`.

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

    | Branch | Code snippet                                                       |
    |--------|--------------------------------------------------------------------|
    | Main   | `add('nvim-mini/mini.surround')`                                   |
    | Stable | `add({ source = 'nvim-mini/mini.surround', checkout = 'stable' })` |

</details>

<details>
<summary>With <a href="https://github.com/folke/lazy.nvim">folke/lazy.nvim</a></summary>

- 'mini.nvim' library:

    | Branch | Code snippet                                  |
    |--------|-----------------------------------------------|
    | Main   | `{ 'nvim-mini/mini.nvim', version = false },` |
    | Stable | `{ 'nvim-mini/mini.nvim', version = '*' },`   |

- Standalone plugin:

    | Branch | Code snippet                                      |
    |--------|---------------------------------------------------|
    | Main   | `{ 'nvim-mini/mini.surround', version = false },` |
    | Stable | `{ 'nvim-mini/mini.surround', version = '*' },`   |

</details>

<details>
<summary>With <a href="https://github.com/junegunn/vim-plug">junegunn/vim-plug</a></summary>

- 'mini.nvim' library:

    | Branch | Code snippet                                         |
    |--------|------------------------------------------------------|
    | Main   | `Plug 'nvim-mini/mini.nvim'`                         |
    | Stable | `Plug 'nvim-mini/mini.nvim', { 'branch': 'stable' }` |

- Standalone plugin:

    | Branch | Code snippet                                             |
    |--------|----------------------------------------------------------|
    | Main   | `Plug 'nvim-mini/mini.surround'`                         |
    | Stable | `Plug 'nvim-mini/mini.surround', { 'branch': 'stable' }` |

</details>

**Important**: don't forget to call `require('mini.surround').setup()` to enable its functionality.

**Note**: if you are on Windows, there might be problems with too long file paths (like `error: unable to create file <some file name>: Filename too long`). Try doing one of the following:

- Enable corresponding git global config value: `git config --system core.longpaths true`. Then try to reinstall.
- Install plugin in other place with shorter path.

## Default config

```lua
-- No need to copy this inside `setup()`. Will be used automatically.
{
  -- Add custom surroundings to be used on top of builtin ones. For more
  -- information with examples, see `:h MiniSurround.config`.
  custom_surroundings = nil,

  -- Duration (in ms) of highlight when calling `MiniSurround.highlight()`
  highlight_duration = 500,

  -- Module mappings. Use `''` (empty string) to disable one.
  mappings = {
    add = 'sa', -- Add surrounding in Normal and Visual modes
    delete = 'sd', -- Delete surrounding
    find = 'sf', -- Find surrounding (to the right)
    find_left = 'sF', -- Find surrounding (to the left)
    highlight = 'sh', -- Highlight surrounding
    replace = 'sr', -- Replace surrounding

    suffix_last = 'l', -- Suffix to search with "prev" method
    suffix_next = 'n', -- Suffix to search with "next" method
  },

  -- Number of lines within which surrounding is searched
  n_lines = 20,

  -- Whether to respect selection type:
  -- - Place surroundings on separate lines in linewise mode.
  -- - Place surroundings on each line in blockwise mode.
  respect_selection_type = false,

  -- How to search for surrounding (first inside current line, then inside
  -- neighborhood). One of 'cover', 'cover_or_next', 'cover_or_prev',
  -- 'cover_or_nearest', 'next', 'prev', 'nearest'. For more details,
  -- see `:h MiniSurround.config`.
  search_method = 'cover',

  -- Whether to disable showing non-error feedback
  -- This also affects (purely informational) helper messages shown after
  -- idle time if user input is required.
  silent = false,
}
```

## Similar plugins

- [tpope/vim-surround](https://github.com/tpope/vim-surround)
- [kylechui/nvim-surround](https://github.com/kylechui/nvim-surround)
- [machakann/vim-sandwich](https://github.com/machakann/vim-sandwich)
