<p align="center"> <img src="https://github.com/nvim-mini/assets/blob/main/logo-2/logo-basics_readme.png?raw=true" alt="mini.basics" style="max-width:100%;border:solid 2px"/> </p>

### Common configuration presets

See more details in [Features](#features) and [Documentation](../doc/mini-basics.txt).

---

> [!NOTE]
> This was previously hosted at a personal `echasnovski` GitHub account. It was transferred to a dedicated organization to improve long term project stability. See more details [here](https://github.com/nvim-mini/mini.nvim/discussions/1970).

⦿ This is a part of [mini.nvim](https://nvim-mini.org/mini.nvim) library. Please use [this link](https://nvim-mini.org/mini.nvim/readmes/mini-basics) if you want to mention this module.

⦿ All contributions (issues, pull requests, discussions, etc.) are done inside of 'mini.nvim'.

⦿ See [whole library documentation](https://nvim-mini.org/mini.nvim/doc/mini-nvim) to learn about general design principles, disable/configuration recipes, and more.

⦿ See [MiniMax](https://nvim-mini.org/MiniMax) for a full config example that uses this module.

---

If you want to help this project grow but don't know where to start, check out [contributing guides of 'mini.nvim'](https://nvim-mini.org/mini.nvim/CONTRIBUTING) or leave a Github star for 'mini.nvim' project and/or any its standalone Git repositories.

## Demo

<!-- Demo source: https://github.com/nvim-mini/assets/blob/main/demo/demo-basics.mp4 -->
https://user-images.githubusercontent.com/24854248/215277747-c0dea3eb-e8f7-4550-85ce-200b111fff55.mp4

## Features

- Presets for common options. It will only change option if it wasn't manually set before. See `:h MiniBasics.config.options` for more details.
- Presets for common mappings. It will only add a mapping if it wasn't manually created before. See `:h MiniBasics.config.mappings` for more details.
- Presets for common autocommands. See `:h MiniBasics.config.autocommands` for more details.
- Reverse compatibility is a high priority. Any decision to change already present behavior will be made with great care.

Notes:

- Main goal of this module is to provide a relatively easier way for new-ish Neovim users to have better "works out of the box" experience while having documented relevant options/mappings/autocommands to study. It is based partially on survey among Neovim users and partially is coming from personal preferences.

    However, more seasoned users almost surely will find something useful.

    Still, it is recommended to read about used options/mappings/autocommands and decide if they are needed. The main way to do that is by reading Neovim's help pages (linked in help file) and this module's source code (thoroughly documented for easier comprehension).

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
    | Main   | `add('nvim-mini/mini.basics')`                                   |
    | Stable | `add({ source = 'nvim-mini/mini.basics', checkout = 'stable' })` |

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
    | Main   | `{ 'nvim-mini/mini.basics', version = false },` |
    | Stable | `{ 'nvim-mini/mini.basics', version = '*' },`   |

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
    | Main   | `Plug 'nvim-mini/mini.basics'`                         |
    | Stable | `Plug 'nvim-mini/mini.basics', { 'branch': 'stable' }` |

</details>

**Important**: don't forget to call `require('mini.basics').setup()` to enable its functionality.

**Note**: if you are on Windows, there might be problems with too long file paths (like `error: unable to create file <some file name>: Filename too long`). Try doing one of the following:

- Enable corresponding git global config value: `git config --system core.longpaths true`. Then try to reinstall.
- Install plugin in other place with shorter path.

## Default config

```lua
-- No need to copy this inside `setup()`. Will be used automatically.
{
  -- Options. Set field to `false` to disable.
  options = {
    -- Basic options ('number', 'ignorecase', and many more)
    basic = true,

    -- Extra UI features ('winblend', 'listchars', 'pumheight', ...)
    extra_ui = false,

    -- Presets for window borders ('single', 'double', ...)
    -- Default 'auto' infers from 'winborder' option
    win_borders = 'auto',
  },

  -- Mappings. Set field to `false` to disable.
  mappings = {
    -- Basic mappings (better 'jk', save with Ctrl+S, ...)
    basic = true,

    -- Prefix for mappings that toggle common options ('wrap', 'spell', ...).
    -- Supply empty string to not create these mappings.
    option_toggle_prefix = [[\]],

    -- Window navigation with <C-hjkl>, resize with <C-arrow>
    windows = false,

    -- Move cursor in Insert, Command, and Terminal mode with <M-hjkl>
    move_with_alt = false,
  },

  -- Autocommands. Set field to `false` to disable
  autocommands = {
    -- Basic autocommands (highlight on yank, start Insert in terminal, ...)
    basic = true,

    -- Set 'relativenumber' only in linewise and blockwise Visual mode
    relnum_in_visual_mode = false,
  },

  -- Whether to disable showing non-error feedback
  silent = false,
}
```

## Similar plugins

- [tpope/vim-sensible](https://github.com/tpope/vim-sensible)
- [tpope/vim-unimpaired](https://github.com/tpope/vim-unimpaired)
