<div align="center"> <img src="https://github.com/nvim-mini/assets/blob/main/logo-2/logo-surround_readme.png" alt="mini.surround"/> </div>

### Fast and feature-rich surround actions

- Add, delete, replace, find, highlight surrounding (like pair of parenthesis, quotes, etc.).
- Supports dot-repeat for text edits, `v:count`, different search methods, "last"/"next" extended mappings, customization via Lua patterns or functions, and more.
- Has builtins for brackets, function call, tag, user prompt, and any alphanumeric/punctuation/whitespace character.
- Has maintained configuration of setup similar to 'tpope/vim-surround'.

See more details in [Features](#features) and [help file](../doc/mini-surround.txt).

---

> [!NOTE]
> This was previously hosted at a personal `echasnovski` GitHub account. It was transferred to a dedicated organization to improve long term project stability. See more details [here](https://github.com/nvim-mini/mini.nvim/discussions/1970).

⦿ This is a part of [mini.nvim](https://github.com/nvim-mini/mini.nvim) library. Please use [this link](https://github.com/nvim-mini/mini.nvim/blob/main/readmes/mini-surround.md) if you want to mention this module.

⦿ All contributions (issues, pull requests, discussions, etc.) are done inside of 'mini.nvim'.

⦿ See the repository page to learn about common design principles and configuration recipes.

---

If you want to help this project grow but don't know where to start, check out [contributing guides of 'mini.nvim'](https://github.com/nvim-mini/mini.nvim/blob/main/CONTRIBUTING.md) or leave a Github star for 'mini.nvim' project and/or any its standalone Git repositories.

## Demo

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
<summary>With <a href="https://github.com/nvim-mini/mini.nvim/blob/main/readmes/mini-deps.md">mini.deps</a></summary>
<table>
    <thead>
        <tr>
            <th>Github repo</th>
            <th>Branch</th> <th>Code snippet</th>
        </tr>
    </thead>
    <tbody>
        <tr>
            <td rowspan=2>'mini.nvim' library</td> <td>Main</td> <td rowspan=2><i>Follow recommended 'mini.deps' installation</i></td>
        </tr>
        <tr>
            <td>Stable</td>
        </tr>
        <tr>
            <td rowspan=2>Standalone plugin</td> <td>Main</td> <td><code>add('nvim-mini/mini.surround')</code></td>
        </tr>
        <tr>
            <td>Stable</td> <td><code>add({ source = 'nvim-mini/mini.surround', checkout = 'stable' })</code></td>
        </tr>
    </tbody>
</table>
</details>

<details>
<summary>With <a href="https://github.com/folke/lazy.nvim">folke/lazy.nvim</a></summary>
<table>
    <thead>
        <tr>
            <th>Github repo</th>
            <th>Branch</th> <th>Code snippet</th>
        </tr>
    </thead>
    <tbody>
        <tr>
            <td rowspan=2>'mini.nvim' library</td>
            <td>Main</td> <td><code>{ 'nvim-mini/mini.nvim', version = false },</code></td>
        </tr>
        <tr>
            <td>Stable</td> <td><code>{ 'nvim-mini/mini.nvim', version = '*' },</code></td>
        </tr>
        <tr>
            <td rowspan=2>Standalone plugin</td>
            <td>Main</td> <td><code>{ 'nvim-mini/mini.surround', version = false },</code></td>
        </tr>
        <tr>
            <td>Stable</td> <td><code>{ 'nvim-mini/mini.surround', version = '*' },</code></td>
        </tr>
    </tbody>
</table>
</details>

<details>
<summary>With <a href="https://github.com/junegunn/vim-plug">junegunn/vim-plug</a></summary>
<table>
    <thead>
        <tr>
            <th>Github repo</th>
            <th>Branch</th> <th>Code snippet</th>
        </tr>
    </thead>
    <tbody>
        <tr>
            <td rowspan=2>'mini.nvim' library</td>
            <td>Main</td> <td><code>Plug 'nvim-mini/mini.nvim'</code></td>
        </tr>
        <tr>
            <td>Stable</td> <td><code>Plug 'nvim-mini/mini.nvim', { 'branch': 'stable' }</code></td>
        </tr>
        <tr>
            <td rowspan=2>Standalone plugin</td> <td>Main</td> <td><code>Plug 'nvim-mini/mini.surround'</code></td>
        </tr>
        <tr>
            <td>Stable</td> <td><code>Plug 'nvim-mini/mini.surround', { 'branch': 'stable' }</code></td>
        </tr>
    </tbody>
</table>
</details>

<br>

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
