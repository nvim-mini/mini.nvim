<p align="center"> <img src="https://github.com/nvim-mini/assets/blob/main/logo-2/logo-keymap_readme.png?raw=true" alt="mini.keymap" style="max-width:100%;border:solid 2px"/> </p>

### Special key mappings

See more details in [Features](#features) and [Documentation](../doc/mini-keymap.txt).

---

> [!NOTE]
> This was previously hosted at a personal `echasnovski` GitHub account. It was transferred to a dedicated organization to improve long term project stability. See more details [here](https://github.com/nvim-mini/mini.nvim/discussions/1970).

⦿ This is a part of [mini.nvim](https://nvim-mini.org/mini.nvim) library. Please use [this link](https://nvim-mini.org/mini.nvim/readmes/mini-keymap) if you want to mention this module.

⦿ All contributions (issues, pull requests, discussions, etc.) are done inside of 'mini.nvim'.

⦿ See [whole library documentation](https://nvim-mini.org/mini.nvim/doc/mini-nvim) to learn about general design principles, disable/configuration recipes, and more.

⦿ See [MiniMax](https://nvim-mini.org/MiniMax) for a full config example that uses this module.

---

If you want to help this project grow but don't know where to start, check out [contributing guides of 'mini.nvim'](https://nvim-mini.org/mini.nvim/CONTRIBUTING) or leave a Github star for 'mini.nvim' project and/or any its standalone Git repositories.

## Demo

<!-- Demo source: https://github.com/nvim-mini/assets/blob/main/demo/demo-keymap.mp4 -->
https://github.com/user-attachments/assets/a3e34e9f-6901-4e57-a5bd-9508b2c6d065

## Features

- Map keys to perform configurable multi-step actions: if condition for step one is true - execute step one action, else check step two, and so on until falling back to executing original keys. This is usually referred to as "smart" keys (like "smart tab"). See `:h MiniKeymap.map_multistep()`.

  There are many built-in steps targeted for Insert mode mappings of special keys like `<Tab>`, `<S-Tab>`, `<CR>`, and `<BS>`:
  - Navigate and accept built-in Insert mode completion. Useful for [mini.completion](https://nvim-mini.org/mini.nvim/readmes/mini-completion).
  - Navigate and expand [mini.snippets](https://nvim-mini.org/mini.nvim/readmes/mini-snippets).
  - Execute `<CR>` and `<BS>` respecting [mini.pairs](https://nvim-mini.org/mini.nvim/readmes/mini-pairs).
  - Jump before/after current tree-sitter node.
  - Jump before opening and after closing characters (brackets and quotes).
  - Increase/decrease indent when cursor is inside of it.
  - Delete all whitespace to the left ("hungry backspace").
  - Navigate built-in snippet engine (`:h vim.snippet`).
  - Navigate and accept in [hrsh7th/nvim-cmp](https://github.com/hrsh7th/nvim-cmp) completion.
  - Navigate and accept in [Saghen/blink.cmp](https://github.com/Saghen/blink.cmp) completion.
  - Navigate and expand [L3MON4D3/LuaSnip](https://github.com/L3MON4D3/LuaSnip) snippets.
  - Execute `<CR>` and `<BS>` respecting [windwp/nvim-autopairs](https://github.com/windwp/nvim-autopairs).

- Map keys as "combo": each key acts immediately plus execute extra action if all are typed within configurable delay between each other. See `:h MiniKeymap.map_combo()`.

  Some of the common use cases include:
    - Map insertable keys (like "jk", "kj") in Insert and Command-line mode to exit into Normal mode.
    - Fight against bad habits of pressing the same navigation key by showing a notification if there are too many of them pressed in a row.

Sources with more details:

- `:h MiniKeymap-examples`

## Quickstart

### Multi-step

Setup that works well with 'mini.completion' and 'mini.pairs':

```lua
local map_multistep = require('mini.keymap').map_multistep

map_multistep('i', '<Tab>',   { 'pmenu_next' })
map_multistep('i', '<S-Tab>', { 'pmenu_prev' })
map_multistep('i', '<CR>',    { 'pmenu_accept', 'minipairs_cr' })
map_multistep('i', '<BS>',    { 'minipairs_bs' })
```

### Combos

"Better escape" to Normal mode without having to reach for `<Esc>` key:

```lua
local map_combo = require('mini.keymap').map_combo

-- Support most common modes. This can also contain 't', but would
-- only mean to press `<Esc>` inside terminal.
local mode = { 'i', 'c', 'x', 's' }
map_combo(mode, 'jk', '<BS><BS><Esc>')

-- To not have to worry about the order of keys, also map "kj"
map_combo(mode, 'kj', '<BS><BS><Esc>')

-- Escape into Normal mode from Terminal mode
map_combo('t', 'jk', '<BS><BS><C-\\><C-n>')
map_combo('t', 'kj', '<BS><BS><C-\\><C-n>')
```

Show notification if there is too much movement by repeating same key:

```lua
local notify_many_keys = function(key)
  local lhs = string.rep(key, 5)
  local action = function() vim.notify('Too many ' .. key) end
  require('mini.keymap').map_combo({ 'n', 'x' }, lhs, action)
end
notify_many_keys('h')
notify_many_keys('j')
notify_many_keys('k')
notify_many_keys('l')
```

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

    | Branch | Code snippet                                                     |
    |--------|------------------------------------------------------------------|
    | Main   | `add('nvim-mini/mini.keymap')`                                   |
    | Stable | `add({ source = 'nvim-mini/mini.keymap', checkout = 'stable' })` |

</details>

<details>
<summary>With <a href="https://github.com/folke/lazy.nvim">folke/lazy.nvim</a></summary>

- 'mini.nvim' library:

    | Branch | Code snippet                                  |
    |--------|-----------------------------------------------|
    | Main   | `{ 'nvim-mini/mini.nvim', version = false },` |
    | Stable | `{ 'nvim-mini/mini.nvim', version = '*' },`   |

- Standalone plugin:

    | Branch | Code snippet                                    |
    |--------|-------------------------------------------------|
    | Main   | `{ 'nvim-mini/mini.keymap', version = false },` |
    | Stable | `{ 'nvim-mini/mini.keymap', version = '*' },`   |

</details>

<details>
<summary>With <a href="https://github.com/junegunn/vim-plug">junegunn/vim-plug</a></summary>

- 'mini.nvim' library:

    | Branch | Code snippet                                         |
    |--------|------------------------------------------------------|
    | Main   | `Plug 'nvim-mini/mini.nvim'`                         |
    | Stable | `Plug 'nvim-mini/mini.nvim', { 'branch': 'stable' }` |

- Standalone plugin:

    | Branch | Code snippet                                           |
    |--------|--------------------------------------------------------|
    | Main   | `Plug 'nvim-mini/mini.keymap'`                         |
    | Stable | `Plug 'nvim-mini/mini.keymap', { 'branch': 'stable' }` |

</details>

**Important**: no need to call `require('mini.keymap').setup()`, but it can be done to improve usability.

**Note**: if you are on Windows, there might be problems with too long file paths (like `error: unable to create file <some file name>: Filename too long`). Try doing one of the following:

- Enable corresponding git global config value: `git config --system core.longpaths true`. Then try to reinstall.
- Install plugin in other place with shorter path.

## Default config

```lua
-- No need to copy this inside `setup()`. Will be used automatically.
{}
```

## Similar plugins

- [max397574/better-escape.nvim](https://github.com/max397574/better-escape.nvim)
- [abecodes/tabout.nvim](https://github.com/abecodes/tabout.nvim)
