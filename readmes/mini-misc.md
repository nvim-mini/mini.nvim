<p align="center"> <img src="https://github.com/nvim-mini/assets/blob/main/logo-2/logo-misc_readme.png?raw=true" alt="mini.misc"/> </p>

### Miscellaneous useful functions

See more details in [Features](#features) and [help file](../doc/mini-misc.txt).

---

> [!NOTE]
> This was previously hosted at a personal `echasnovski` GitHub account. It was transferred to a dedicated organization to improve long term project stability. See more details [here](https://github.com/nvim-mini/mini.nvim/discussions/1970).

⦿ This is a part of [mini.nvim](https://github.com/nvim-mini/mini.nvim) library. Please use [this link](https://github.com/nvim-mini/mini.nvim/blob/main/readmes/mini-misc.md) if you want to mention this module.

⦿ All contributions (issues, pull requests, discussions, etc.) are done inside of 'mini.nvim'.

⦿ See the repository page to learn about common design principles and configuration recipes.

---

If you want to help this project grow but don't know where to start, check out [contributing guides of 'mini.nvim'](https://github.com/nvim-mini/mini.nvim/blob/main/CONTRIBUTING.md) or leave a Github star for 'mini.nvim' project and/or any its standalone Git repositories.

## Demo

<!-- Demo source: https://github.com/nvim-mini/assets/blob/main/demo/demo-misc.mp4 -->
https://user-images.githubusercontent.com/24854248/173044891-69b0ccfd-3fe8-4639-bc70-f955bbf4a1a7.mp4

## Features

- `bench_time()` executes function several times and timing how long it took.
- `put()` and `put_text()` print Lua objects in command line and current buffer respectively.
- `setup_auto_root()` sets up automated change of current directory.
- `setup_termbg_sync()` to set up terminal background synchronization (removes possible "frame" around current Neovim instance).
- `setup_restore_cursor()` sets up automated restoration of cursor position on file reopen.
- `stat_summary()` computes summary statistics of numerical array.
- `tbl_head()` and `tbl_tail()` return first and last elements of table.
- `zoom()` makes current buffer full screen in a floating window.
- And more.

## Installation

This plugin can be installed as part of 'mini.nvim' library (**recommended**) or as a standalone Git repository.

There are two branches to install from:

- `main` (default, **recommended**) will have latest development version of plugin. All changes since last stable release should be perceived as being in beta testing phase (meaning they already passed alpha-testing and are moderately settled).
- `stable` will be updated only upon releases with code tested during public beta-testing phase in `main` branch.

Here are code snippets for some common installation methods (use only one):

<details>
<summary>With <a href="https://github.com/nvim-mini/mini.nvim/blob/main/readmes/mini-deps.md">mini.deps</a></summary>

- 'mini.nvim' library:

    | Branch | Code snippet                                  |
    |--------|-----------------------------------------------|
    | Main   | *Follow recommended ‘mini.deps’ installation* |
    | Stable | *Follow recommended ‘mini.deps’ installation* |

- Standalone plugin:

    | Branch | Code snippet                                                   |
    |--------|----------------------------------------------------------------|
    | Main   | `add(‘nvim-mini/mini.misc’)`                                   |
    | Stable | `add({ source = ‘nvim-mini/mini.misc’, checkout = ‘stable’ })` |

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
    | Main   | `{ 'nvim-mini/mini.misc', version = false },` |
    | Stable | `{ 'nvim-mini/mini.misc', version = '*' },`   |

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
    | Main   | `Plug 'nvim-mini/mini.misc'`                         |
    | Stable | `Plug 'nvim-mini/mini.misc', { 'branch': 'stable' }` |

</details>

<br>

**Important**: no need to call `require('mini.misc').setup()`, but it can be done to improve usability.

**Note**: if you are on Windows, there might be problems with too long file paths (like `error: unable to create file <some file name>: Filename too long`). Try doing one of the following:

- Enable corresponding git global config value: `git config --system core.longpaths true`. Then try to reinstall.

- Install plugin in other place with shorter path.

## Default config

```lua
-- No need to copy this inside `setup()`. Will be used automatically.
{
  -- Array of fields to make global (to be used as independent variables)
  make_global = { 'put', 'put_text' },
}
```

## Similar plugins

- [nvim-lua/plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
