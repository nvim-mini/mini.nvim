<p align="center"> <img src="https://github.com/nvim-mini/assets/blob/main/logo-2/logo-statusline_readme.png?raw=true" alt="mini.statusline" style="max-width:100%;border:solid 2px"/> </p>

### Minimal and fast statusline module with opinionated default look

See more details in [Features](#features) and [Documentation](../doc/mini-statusline.txt).

---

> [!NOTE]
> This was previously hosted at a personal `echasnovski` GitHub account. It was transferred to a dedicated organization to improve long term project stability. See more details [here](https://github.com/nvim-mini/mini.nvim/discussions/1970).

⦿ This is a part of [mini.nvim](https://nvim-mini.org/mini.nvim) library. Please use [this link](https://nvim-mini.org/mini.nvim/readmes/mini-statusline) if you want to mention this module.

⦿ All contributions (issues, pull requests, discussions, etc.) are done inside of 'mini.nvim'.

⦿ See [whole library documentation](https://nvim-mini.org/mini.nvim/doc/mini-nvim) to learn about general design principles, disable/configuration recipes, and more.

⦿ See [MiniMax](https://nvim-mini.org/MiniMax) for a full config example that uses this module.

---

If you want to help this project grow but don't know where to start, check out [contributing guides of 'mini.nvim'](https://nvim-mini.org/mini.nvim/CONTRIBUTING) or leave a Github star for 'mini.nvim' project and/or any its standalone Git repositories.

## Demo

<!-- Demo source: https://github.com/nvim-mini/assets/blob/main/demo/demo-statusline.mp4 -->
https://user-images.githubusercontent.com/24854248/173045208-42463c8f-a2ac-488d-9d30-216891f4bb51.mp4

## Features

- Define own custom statusline structure for active and inactive windows. This is done with a function which should return string appropriate for |statusline|. Its code should be similar to default one with structure:
    - Compute string data for every section you want to be displayed.
    - Combine them in groups with `MiniStatusline.combine_groups()`.
- Built-in active mode indicator with colors.
- Sections can hide information when window is too narrow (specific window width is configurable per section).

## Dependencies

For full experience needs (still works without any of suggestions):

- [Nerd font](https://www.nerdfonts.com/) and enabled ['mini.icons'](https://nvim-mini.org/mini.nvim/readmes/mini-icons) module to show filetype icons. Can fall back to using [nvim-tree/nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons) plugin.

- Enabled ['mini.git'](https://nvim-mini.org/mini.nvim/readmes/mini-git) and ['mini.diff'](https://nvim-mini.org/mini.nvim/readmes/mini-diff) modules to show Git and diff related information. Can fall back to using [lewis6991/gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim) plugin.

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

    | Branch | Code snippet                                                         |
    |--------|----------------------------------------------------------------------|
    | Main   | `add('nvim-mini/mini.statusline')`                                   |
    | Stable | `add({ source = 'nvim-mini/mini.statusline', checkout = 'stable' })` |

</details>

<details>
<summary>With <a href="https://github.com/folke/lazy.nvim">folke/lazy.nvim</a></summary>

- 'mini.nvim' library:

    | Branch | Code snippet                                  |
    |--------|-----------------------------------------------|
    | Main   | `{ 'nvim-mini/mini.nvim', version = false },` |
    | Stable | `{ 'nvim-mini/mini.nvim', version = '*' },`   |

- Standalone plugin:

    | Branch | Code snippet                                        |
    |--------|-----------------------------------------------------|
    | Main   | `{ 'nvim-mini/mini.statusline', version = false },` |
    | Stable | `{ 'nvim-mini/mini.statusline', version = '*' },`   |

</details>

<details>
<summary>With <a href="https://github.com/junegunn/vim-plug">junegunn/vim-plug</a></summary>

- 'mini.nvim' library:

    | Branch | Code snippet                                         |
    |--------|------------------------------------------------------|
    | Main   | `Plug 'nvim-mini/mini.nvim'`                         |
    | Stable | `Plug 'nvim-mini/mini.nvim', { 'branch': 'stable' }` |

- Standalone plugin:

    | Branch | Code snippet                                               |
    |--------|------------------------------------------------------------|
    | Main   | `Plug 'nvim-mini/mini.statusline'`                         |
    | Stable | `Plug 'nvim-mini/mini.statusline', { 'branch': 'stable' }` |

</details>

**Important**: don't forget to call `require('mini.statusline').setup()` to enable its functionality.

**Note**: if you are on Windows, there might be problems with too long file paths (like `error: unable to create file <some file name>: Filename too long`). Try doing one of the following:

- Enable corresponding git global config value: `git config --system core.longpaths true`. Then try to reinstall.
- Install plugin in other place with shorter path.

## Default config

```lua
-- No need to copy this inside `setup()`. Will be used automatically.
{
  -- Content of statusline as functions which return statusline string. See
  -- `:h statusline` and code of default contents (used instead of `nil`).
  content = {
    -- Content for active window
    active = nil,
    -- Content for inactive window(s)
    inactive = nil,
  },

  -- Whether to use icons by default
  use_icons = true,
}
```

## Similar plugins

- [nvim-lualine/lualine.nvim](https://github.com/nvim-lualine/lualine.nvim)
