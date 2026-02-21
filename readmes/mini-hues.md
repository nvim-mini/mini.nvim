<p align="center"> <img src="https://github.com/nvim-mini/assets/blob/main/logo-2/logo-hues_readme.png?raw=true" alt="mini.hues" style="max-width:100%;border:solid 2px"/> </p>

### Generate configurable color scheme

See more details in [Features](#features) and [Documentation](../doc/mini-hues.txt).

---

> [!NOTE]
> This was previously hosted at a personal `echasnovski` GitHub account. It was transferred to a dedicated organization to improve long term project stability. See more details [here](https://github.com/nvim-mini/mini.nvim/discussions/1970).

⦿ This is a part of [mini.nvim](https://nvim-mini.org/mini.nvim) library. Please use [this link](https://nvim-mini.org/mini.nvim/readmes/mini-hues) if you want to mention this module.

⦿ All contributions (issues, pull requests, discussions, etc.) are done inside of 'mini.nvim'.

⦿ See [whole library documentation](https://nvim-mini.org/mini.nvim/doc/mini-nvim) to learn about general design principles, disable/configuration recipes, and more.

⦿ See [MiniMax](https://nvim-mini.org/MiniMax) for a full config example that uses this module.

---

If you want to help this project grow but don't know where to start, check out [contributing guides of 'mini.nvim'](https://nvim-mini.org/mini.nvim/CONTRIBUTING) or leave a Github star for 'mini.nvim' project and/or any its standalone Git repositories.

## Demo

<!-- Demo source: https://github.com/nvim-mini/assets/blob/main/demo/demo-hues.mp4 -->
https://user-images.githubusercontent.com/24854248/236634787-ab0c33df-f697-4d96-a754-d77eccee7513.mp4

### Bundled color schemes

#### Four seasons

- `miniwinter`: "icy winter" palette with azure background

<a href="https://github.com/nvim-mini/assets/blob/main/demo/demo-miniwinter-dark.png?raw=true"> <img alt="miniwinter dark" src="https://github.com/nvim-mini/assets/blob/main/demo/demo-miniwinter-dark.png?raw=true" style="width: 45%"/> </a>
<a href="https://github.com/nvim-mini/assets/blob/main/demo/demo-miniwinter-light.png?raw=true"> <img alt="miniwinter light" src="https://github.com/nvim-mini/assets/blob/main/demo/demo-miniwinter-light.png?raw=true" style="width: 45%"/> </a>

- `minispring`: "blooming spring" palette with green background

<a href="https://github.com/nvim-mini/assets/blob/main/demo/demo-minispring-dark.png?raw=true"> <img alt="minispring dark" src="https://github.com/nvim-mini/assets/blob/main/demo/demo-minispring-dark.png?raw=true" style="width: 45%"/> </a>
<a href="https://github.com/nvim-mini/assets/blob/main/demo/demo-minispring-light.png?raw=true"> <img alt="minispring light" src="https://github.com/nvim-mini/assets/blob/main/demo/demo-minispring-light.png?raw=true" style="width: 45%"/> </a>

- `minisummer`: "hot summer" palette with brown/yellow background

<a href="https://github.com/nvim-mini/assets/blob/main/demo/demo-minisummer-dark.png?raw=true"> <img alt="minisummer dark" src="https://github.com/nvim-mini/assets/blob/main/demo/demo-minisummer-dark.png?raw=true" style="width: 45%"/> </a>
<a href="https://github.com/nvim-mini/assets/blob/main/demo/demo-minisummer-light.png?raw=true"> <img alt="minisummer light" src="https://github.com/nvim-mini/assets/blob/main/demo/demo-minisummer-light.png?raw=true" style="width: 45%"/> </a>

- `miniautumn`: "cooling autumn" palette with purple background

<a href="https://github.com/nvim-mini/assets/blob/main/demo/demo-miniautumn-dark.png?raw=true"> <img alt="miniautumn dark" src="https://github.com/nvim-mini/assets/blob/main/demo/demo-miniautumn-dark.png?raw=true" style="width: 45%"/> </a>
<a href="https://github.com/nvim-mini/assets/blob/main/demo/demo-miniautumn-light.png?raw=true"> <img alt="miniautumn light" src="https://github.com/nvim-mini/assets/blob/main/demo/demo-miniautumn-light.png?raw=true" style="width: 45%"/> </a>

#### `randomhue`

`randomhue` uses **randomly generated** background and foreground of same hue (color will change on every `:colorscheme randomhue` call):

<a href="https://github.com/nvim-mini/assets/blob/main/demo/demo-randomhue_dark-purple.png?raw=true"> <img alt="Dark purple" src="https://github.com/nvim-mini/assets/blob/main/demo/demo-randomhue_dark-purple.png?raw=true" style="width: 45%"/> </a>
<a href="https://github.com/nvim-mini/assets/blob/main/demo/demo-randomhue_light-purple.png?raw=true"> <img alt="Light purple" src="https://github.com/nvim-mini/assets/blob/main/demo/demo-randomhue_light-purple.png?raw=true" style="width: 45%"/> </a>

<a href="https://github.com/nvim-mini/assets/blob/main/demo/demo-randomhue_dark-azure.png?raw=true"> <img alt="Dark azure" src="https://github.com/nvim-mini/assets/blob/main/demo/demo-randomhue_dark-azure.png?raw=true" style="width: 45%"/> </a>
<a href="https://github.com/nvim-mini/assets/blob/main/demo/demo-randomhue_light-azure.png?raw=true"> <img alt="Light azure" src="https://github.com/nvim-mini/assets/blob/main/demo/demo-randomhue_light-azure.png?raw=true" style="width: 45%"/> </a>

<a href="https://github.com/nvim-mini/assets/blob/main/demo/demo-randomhue_dark-green.png?raw=true"> <img alt="Dark green" src="https://github.com/nvim-mini/assets/blob/main/demo/demo-randomhue_dark-green.png?raw=true" style="width: 45%"/> </a>
<a href="https://github.com/nvim-mini/assets/blob/main/demo/demo-randomhue_light-green.png?raw=true"> <img alt="Light green" src="https://github.com/nvim-mini/assets/blob/main/demo/demo-randomhue_light-green.png?raw=true" style="width: 45%"/> </a>

<a href="https://github.com/nvim-mini/assets/blob/main/demo/demo-randomhue_dark-orange.png?raw=true"> <img alt="Dark orange" src="https://github.com/nvim-mini/assets/blob/main/demo/demo-randomhue_dark-orange.png?raw=true" style="width: 45%"/> </a>
<a href="https://github.com/nvim-mini/assets/blob/main/demo/demo-randomhue_light-orange.png?raw=true"> <img alt="Light orange" src="https://github.com/nvim-mini/assets/blob/main/demo/demo-randomhue_light-orange.png?raw=true" style="width: 45%"/> </a>

## Example configurations

```lua
-- Choose background and foreground
require('mini.hues').setup({ background = '#351721', foreground = '#cdc4c6' }) -- red
require('mini.hues').setup({ background = '#361a0d', foreground = '#cdc5c1' }) -- orange
require('mini.hues').setup({ background = '#2c2101', foreground = '#c9c6c0' }) -- yellow
require('mini.hues').setup({ background = '#17280e', foreground = '#c4c8c2' }) -- green
require('mini.hues').setup({ background = '#002923', foreground = '#c0c9c7' }) -- cyan
require('mini.hues').setup({ background = '#002734', foreground = '#c0c8cc' }) -- azure
require('mini.hues').setup({ background = '#19213a', foreground = '#c4c6cd' }) -- blue
require('mini.hues').setup({ background = '#2b1a33', foreground = '#c9c5cb' }) -- purple

-- Different number of non-base hues
require('mini.hues').setup({ background = '#002734', foreground = '#c0c8cc', n_hues = 6 })
require('mini.hues').setup({ background = '#002734', foreground = '#c0c8cc', n_hues = 4 })
require('mini.hues').setup({ background = '#002734', foreground = '#c0c8cc', n_hues = 2 })
require('mini.hues').setup({ background = '#002734', foreground = '#c0c8cc', n_hues = 0 })

-- Different text saturation
require('mini.hues').setup({ background = '#002734', foreground = '#c0c8cc', saturation = 'low' })
require('mini.hues').setup({ background = '#002734', foreground = '#c0c8cc', saturation = 'lowmedium' })
require('mini.hues').setup({ background = '#002734', foreground = '#c0c8cc', saturation = 'medium' })
require('mini.hues').setup({ background = '#002734', foreground = '#c0c8cc', saturation = 'mediumhigh' })
require('mini.hues').setup({ background = '#002734', foreground = '#c0c8cc', saturation = 'high' })

-- Choose accent color
require('mini.hues').setup({ background = '#002734', foreground = '#c0c8cc', accent = 'yellow' })
require('mini.hues').setup({ background = '#002734', foreground = '#c0c8cc', accent = 'blue' })
```

## Features

- Required to set two base colors: background and foreground. Their shades and other non-base colors are computed to be as much perceptually different as reasonably possible.

- Configurable:
    - Number of hues used for non-base colors (from 0 to 8).
    - Saturation level ('low', 'lowmedium', 'medium', 'mediumhigh', 'high').
    - Accent color used for some selected UI elements.
    - Plugin integration (can be selectively enabled for faster startup).

- Random generator for base colors. Powers `randomhue` color scheme.

- Lua function to compute palette used in color scheme.

- Bundled color schemes. See [bundled-color-schemes]().

Supported highlight groups:

- All built-in UI and syntax groups.

- Built-in Neovim LSP and diagnostic.

- Tree-sitter.

- LSP semantic tokens.

- Plugins (either with explicit definition or by verification that default highlighting works appropriately):
    - [nvim-mini/mini.nvim](https://nvim-mini.org/mini.nvim)
    - [akinsho/bufferline.nvim](https://github.com/akinsho/bufferline.nvim)
    - [anuvyklack/hydra.nvim](https://github.com/anuvyklack/hydra.nvim)
    - [DanilaMihailov/beacon.nvim](https://github.com/DanilaMihailov/beacon.nvim)
    - [folke/lazy.nvim](https://github.com/folke/lazy.nvim)
    - [folke/noice.nvim](https://github.com/folke/noice.nvim)
    - [folke/snacks.nvim](https://github.com/folke/snacks.nvim)
    - [folke/todo-comments.nvim](https://github.com/folke/todo-comments.nvim)
    - [folke/trouble.nvim](https://github.com/folke/trouble.nvim)
    - [folke/which-key.nvim](https://github.com/folke/which-key.nvim)
    - [ggandor/leap.nvim](https://github.com/ggandor/leap.nvim)
    - [glepnir/dashboard-nvim](https://github.com/glepnir/dashboard-nvim)
    - [glepnir/lspsaga.nvim](https://github.com/glepnir/lspsaga.nvim)
    - [HiPhish/rainbow-delimiters.nvim](https://github.com/HiPhish/rainbow-delimiters.nvim)
    - [hrsh7th/nvim-cmp](https://github.com/hrsh7th/nvim-cmp)
    - [ibhagwan/fzf-lua](https://github.com/ibhagwan/fzf-lua)
    - [justinmk/vim-sneak](https://github.com/justinmk/vim-sneak)
    - [kevinhwang91/nvim-bqf](https://github.com/kevinhwang91/nvim-bqf)
    - [kevinhwang91/nvim-ufo](https://github.com/kevinhwang91/nvim-ufo)
    - [lewis6991/gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim)
    - [lukas-reineke/indent-blankline.nvim](https://github.com/lukas-reineke/indent-blankline.nvim)
    - [MeanderingProgrammer/render-markdown.nvim](https://github.com/MeanderingProgrammer/render-markdown.nvim)
    - [neoclide/coc.nvim](https://github.com/neoclide/coc.nvim)
    - [NeogitOrg/neogit](https://github.com/NeogitOrg/neogit)
    - [nvim-lualine/lualine.nvim](https://github.com/nvim-lualine/lualine.nvim)
    - [nvim-neo-tree/neo-tree.nvim](https://github.com/nvim-neo-tree/neo-tree.nvim)
    - [nvim-telescope/telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
    - [nvim-tree/nvim-tree.lua](https://github.com/nvim-tree/nvim-tree.lua)
    - [OXY2DEV/helpview.nvim](https://github.com/OXY2DEV/helpview.nvim)
    - [OXY2DEV/markview.nvim](https://github.com/OXY2DEV/markview.nvim)
    - [phaazon/hop.nvim](https://github.com/phaazon/hop.nvim)
    - [rcarriga/nvim-dap-ui](https://github.com/rcarriga/nvim-dap-ui)
    - [rcarriga/nvim-notify](https://github.com/rcarriga/nvim-notify)
    - [rlane/pounce.nvim](https://github.com/rlane/pounce.nvim)
    - [romgrk/barbar.nvim](https://github.com/romgrk/barbar.nvim)
    - [stevearc/aerial.nvim](https://github.com/stevearc/aerial.nvim)
    - [williamboman/mason.nvim](https://github.com/williamboman/mason.nvim)

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
    | Main   | `add('nvim-mini/mini.hues')`                                   |
    | Stable | `add({ source = 'nvim-mini/mini.hues', checkout = 'stable' })` |

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
    | Main   | `{ 'nvim-mini/mini.hues', version = false },` |
    | Stable | `{ 'nvim-mini/mini.hues', version = '*' },`   |

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
    | Main   | `Plug 'nvim-mini/mini.hues'`                         |
    | Stable | `Plug 'nvim-mini/mini.hues', { 'branch': 'stable' }` |

</details>

**Important**: don't forget to call `require('mini.hues').setup()` **with `background` and `foreground` fields** to enable its functionality.

**Note**: if you are on Windows, there might be problems with too long file paths (like `error: unable to create file <some file name>: Filename too long`). Try doing one of the following:

- Enable corresponding git global config value: `git config --system core.longpaths true`. Then try to reinstall.
- Install plugin in other place with shorter path.

## Default config

```lua
-- No need to copy this inside `setup()`. Will be used automatically.
{
  -- **Required** base colors as '#rrggbb' hex strings
  background = nil,
  foreground = nil,

  -- Number of hues used for non-base colors
  n_hues = 8,

  -- Saturation. One of 'low', 'lowmedium', 'medium', 'mediumhigh', 'high'.
  saturation = 'medium',

  -- Accent color. One of: 'bg', 'fg', 'red', 'orange', 'yellow', 'green',
  -- 'cyan', 'azure', 'blue', 'purple'
  accent = 'bg',

  -- Plugin integrations. Use `default = false` to disable all integrations.
  -- Also can be set per plugin (see |MiniHues.config|).
  plugins = { default = true },

  -- Whether to auto adjust highlight groups based on certain events
  autoadjust = true,
}
```

## Similar plugins

- [mini.base16](https://nvim-mini.org/mini.nvim/readmes/mini-base16)
