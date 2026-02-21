<p align="center"> <img src="https://github.com/nvim-mini/assets/blob/main/logo-2/logo-tabline_readme.png?raw=true" alt="mini.tabline" style="max-width:100%;border:solid 2px"/> </p>

### Minimal and fast tabline showing listed buffers

See more details in [Features](#features) and [Documentation](../doc/mini-tabline.txt).

---

> [!NOTE]
> This was previously hosted at a personal `echasnovski` GitHub account. It was transferred to a dedicated organization to improve long term project stability. See more details [here](https://github.com/nvim-mini/mini.nvim/discussions/1970).

⦿ This is a part of [mini.nvim](https://nvim-mini.org/mini.nvim) library. Please use [this link](https://nvim-mini.org/mini.nvim/readmes/mini-tabline) if you want to mention this module.

⦿ All contributions (issues, pull requests, discussions, etc.) are done inside of 'mini.nvim'.

⦿ See [whole library documentation](https://nvim-mini.org/mini.nvim/doc/mini-nvim) to learn about general design principles, disable/configuration recipes, and more.

⦿ See [MiniMax](https://nvim-mini.org/MiniMax) for a full config example that uses this module.

---

If you want to help this project grow but don't know where to start, check out [contributing guides of 'mini.nvim'](https://nvim-mini.org/mini.nvim/CONTRIBUTING) or leave a Github star for 'mini.nvim' project and/or any its standalone Git repositories.

## Demo

<!-- Demo source: https://github.com/nvim-mini/assets/blob/main/demo/demo-tabline.mp4 -->
https://user-images.githubusercontent.com/24854248/173045373-f5bdea82-fe3e-4488-8c9a-ebba062a373c.mp4

## Features

- Buffers are listed in the order of their identifier.
- Different highlight groups for "states" of buffer affecting 'buffer tabs'.
- Buffer names are made unique by extending paths to files or appending unique identifier to buffers without name.
- Current buffer is displayed "optimally centered" (in center of screen while maximizing the total number of buffers shown) when there are many buffers open.
- 'Buffer tabs' are clickable if Neovim allows it.
- Extra information section in case of multiple Neovim tabpages.
- Truncation symbols which show if there are tabs to the left and/or right. Exact characters are taken from 'listchars' option (`precedes` and `extends` fields) and are shown only if 'list' option is enabled.

## Dependencies

For full experience needs (still works without any of suggestions):

- Enabled ['mini.icons'](https://nvim-mini.org/mini.nvim/readmes/mini-icons) module to show icons near file names. Can fall back to using [nvim-tree/nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons) plugin.

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

    | Branch | Code snippet                                                      |
    |--------|-------------------------------------------------------------------|
    | Main   | `add('nvim-mini/mini.tabline')`                                   |
    | Stable | `add({ source = 'nvim-mini/mini.tabline', checkout = 'stable' })` |

</details>

<details>
<summary>With <a href="https://github.com/folke/lazy.nvim">folke/lazy.nvim</a></summary>

- 'mini.nvim' library:

    | Branch | Code snippet                                  |
    |--------|-----------------------------------------------|
    | Main   | `{ 'nvim-mini/mini.nvim', version = false },` |
    | Stable | `{ 'nvim-mini/mini.nvim', version = '*' },`   |

- Standalone plugin:

    | Branch | Code snippet                                     |
    |--------|--------------------------------------------------|
    | Main   | `{ 'nvim-mini/mini.tabline', version = false },` |
    | Stable | `{ 'nvim-mini/mini.tabline', version = '*' },`   |

</details>

<details>
<summary>With <a href="https://github.com/junegunn/vim-plug">junegunn/vim-plug</a></summary>

- 'mini.nvim' library:

    | Branch | Code snippet                                         |
    |--------|------------------------------------------------------|
    | Main   | `Plug 'nvim-mini/mini.nvim'`                         |
    | Stable | `Plug 'nvim-mini/mini.nvim', { 'branch': 'stable' }` |

- Standalone plugin:

    | Branch | Code snippet                                            |
    |--------|---------------------------------------------------------|
    | Main   | `Plug 'nvim-mini/mini.tabline'`                         |
    | Stable | `Plug 'nvim-mini/mini.tabline', { 'branch': 'stable' }` |

</details>

**Important**: don't forget to call `require('mini.tabline').setup()` to enable its functionality.

**Note**: if you are on Windows, there might be problems with too long file paths (like `error: unable to create file <some file name>: Filename too long`). Try doing one of the following:

- Enable corresponding git global config value: `git config --system core.longpaths true`. Then try to reinstall.
- Install plugin in other place with shorter path.

## Default config

```lua
-- No need to copy this inside `setup()`. Will be used automatically.
{
  -- Whether to show file icons (requires 'mini.icons')
  show_icons = true,

  -- Function which formats the tab label
  -- By default surrounds with space and possibly prepends with icon
  format = nil,

  -- Where to show tabpage section in case of multiple vim tabpages.
  -- One of 'left', 'right', 'none'.
  tabpage_section = 'left',
}
```

## Similar plugins

- [akinsho/bufferline.nvim](https://github.com/akinsho/bufferline.nvim)
- [romgrk/barbar.nvim](https://github.com/romgrk/barbar.nvim)
- [ap/vim-buftabline](https://github.com/ap/vim-buftabline)
