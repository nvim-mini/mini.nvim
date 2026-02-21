<p align="center"> <img src="https://github.com/nvim-mini/assets/blob/main/logo-2/logo-pairs_readme.png?raw=true" alt="mini.pairs" style="max-width:100%;border:solid 2px"/> </p>

### Minimal and fast autopairs

See more details in [Features](#features) and [Documentation](../doc/mini-pairs.txt).

---

> [!NOTE]
> This was previously hosted at a personal `echasnovski` GitHub account. It was transferred to a dedicated organization to improve long term project stability. See more details [here](https://github.com/nvim-mini/mini.nvim/discussions/1970).

⦿ This is a part of [mini.nvim](https://nvim-mini.org/mini.nvim) library. Please use [this link](https://nvim-mini.org/mini.nvim/readmes/mini-pairs) if you want to mention this module.

⦿ All contributions (issues, pull requests, discussions, etc.) are done inside of 'mini.nvim'.

⦿ See [whole library documentation](https://nvim-mini.org/mini.nvim/doc/mini-nvim) to learn about general design principles, disable/configuration recipes, and more.

⦿ See [MiniMax](https://nvim-mini.org/MiniMax) for a full config example that uses this module.

---

If you want to help this project grow but don't know where to start, check out [contributing guides of 'mini.nvim'](https://nvim-mini.org/mini.nvim/CONTRIBUTING) or leave a Github star for 'mini.nvim' project and/or any its standalone Git repositories.

## Demo

<!-- Demo source: https://github.com/nvim-mini/assets/blob/main/demo/demo-pairs.mp4 -->
https://user-images.githubusercontent.com/24854248/173044991-18653715-9b4e-444e-a4ba-14eb80bc4e38.mp4

## Features

- Functionality to work with two "paired" characters conditional on cursor's neighborhood (character to its left and character to its right).
- Usage should be through making appropriate mappings using `MiniPairs.map()` or in `MiniPairs.setup()` (for global mapping), `MiniPairs.map_buf()` (for buffer mapping).
- Pairs get automatically registered for special `<BS>` (all configured modes) and `<CR>` (only Insert mode) mappings. Pressing the key inside pair will delete whole pair and insert extra blank line inside pair respectively. Note: these mappings are autocreated if they do not override existing ones.

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
    | Main   | `add('nvim-mini/mini.pairs')`                                   |
    | Stable | `add({ source = 'nvim-mini/mini.pairs', checkout = 'stable' })` |

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
    | Main   | `{ 'nvim-mini/mini.pairs', version = false },` |
    | Stable | `{ 'nvim-mini/mini.pairs', version = '*' },`   |

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
    | Main   | `Plug 'nvim-mini/mini.pairs'`                         |
    | Stable | `Plug 'nvim-mini/mini.pairs', { 'branch': 'stable' }` |

</details>

**Important**: don't forget to call `require('mini.pairs').setup()` to enable its functionality.

**Note**: if you are on Windows, there might be problems with too long file paths (like `error: unable to create file <some file name>: Filename too long`). Try doing one of the following:

- Enable corresponding git global config value: `git config --system core.longpaths true`. Then try to reinstall.
- Install plugin in other place with shorter path.

## Default config

```lua
-- No need to copy this inside `setup()`. Will be used automatically.
{
  -- In which modes mappings from this `config` should be created
  modes = { insert = true, command = false, terminal = false },

  -- Global mappings. Each right hand side should be a pair information, a
  -- table with at least these fields (see more in |MiniPairs.map|):
  -- - <action> - one of 'open', 'close', 'closeopen'.
  -- - <pair> - two character string for pair to be used.
  -- By default pair is not inserted after `\`, quotes are not recognized by
  -- <CR>, `'` does not insert the pair after a letter.
  -- Only parts of tables can be tweaked (others will use these defaults).
  mappings = {
    ['('] = { action = 'open', pair = '()', neigh_pattern = '^[^\\]' },
    ['['] = { action = 'open', pair = '[]', neigh_pattern = '^[^\\]' },
    ['{'] = { action = 'open', pair = '{}', neigh_pattern = '^[^\\]' },

    [')'] = { action = 'close', pair = '()', neigh_pattern = '^[^\\]' },
    [']'] = { action = 'close', pair = '[]', neigh_pattern = '^[^\\]' },
    ['}'] = { action = 'close', pair = '{}', neigh_pattern = '^[^\\]' },

    ['"'] = { action = 'closeopen', pair = '""', neigh_pattern = '^[^\\]',   register = { cr = false } },
    ["'"] = { action = 'closeopen', pair = "''", neigh_pattern = '^[^%a\\]', register = { cr = false } },
    ['`'] = { action = 'closeopen', pair = '``', neigh_pattern = '^[^\\]',   register = { cr = false } },
  },
}
```

## Similar plugins

- [windwp/nvim-autopairs](https://github.com/windwp/nvim-autopairs)
- [jiangmiao/auto-pairs](https://github.com/jiangmiao/auto-pairs)
