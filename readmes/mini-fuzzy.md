<p align="center"> <img src="https://github.com/nvim-mini/assets/blob/main/logo-2/logo-fuzzy_readme.png?raw=true" alt="mini.fuzzy" style="max-width:100%;border:solid 2px"/> </p>

### Minimal and fast fuzzy matching

See more details in [Features](#features) and [Documentation](../doc/mini-fuzzy.txt).

---

> [!NOTE]
> This was previously hosted at a personal `echasnovski` GitHub account. It was transferred to a dedicated organization to improve long term project stability. See more details [here](https://github.com/nvim-mini/mini.nvim/discussions/1970).

⦿ This is a part of [mini.nvim](https://nvim-mini.org/mini.nvim) library. Please use [this link](https://nvim-mini.org/mini.nvim/readmes/mini-fuzzy) if you want to mention this module.

⦿ All contributions (issues, pull requests, discussions, etc.) are done inside of 'mini.nvim'.

⦿ See [whole library documentation](https://nvim-mini.org/mini.nvim/doc/mini-nvim) to learn about general design principles, disable/configuration recipes, and more.

---

If you want to help this project grow but don't know where to start, check out [contributing guides of 'mini.nvim'](https://nvim-mini.org/mini.nvim/CONTRIBUTING) or leave a Github star for 'mini.nvim' project and/or any its standalone Git repositories.

## Demo

<!-- Demo source: https://github.com/nvim-mini/assets/blob/main/demo/demo-fuzzy.mp4 -->
https://user-images.githubusercontent.com/24854248/173044594-3599fcec-02d6-4bb7-a47d-23f8400f6656.mp4

## Features

- Function to perform fuzzy matching of one string to others.
- Sorter for [nvim-telescope/telescope.nvim](https://github.com/nvim-telescope/telescope.nvim).

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
    | Main   | `add('nvim-mini/mini.fuzzy')`                                   |
    | Stable | `add({ source = 'nvim-mini/mini.fuzzy', checkout = 'stable' })` |

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
    | Main   | `{ 'nvim-mini/mini.fuzzy', version = false },` |
    | Stable | `{ 'nvim-mini/mini.fuzzy', version = '*' },`   |

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
    | Main   | `Plug 'nvim-mini/mini.fuzzy'`                         |
    | Stable | `Plug 'nvim-mini/mini.fuzzy', { 'branch': 'stable' }` |

</details>

**Important**: no need to call `require('mini.fuzzy').setup()`, but it can be done to improve usability.

**Note**: if you are on Windows, there might be problems with too long file paths (like `error: unable to create file <some file name>: Filename too long`). Try doing one of the following:

- Enable corresponding git global config value: `git config --system core.longpaths true`. Then try to reinstall.
- Install plugin in other place with shorter path.

## Default config

```lua
-- No need to copy this inside `setup()`. Will be used automatically.
{
  -- Maximum allowed value of match features (width and first match). All
  -- feature values greater than cutoff can be considered "equally bad".
  cutoff = 100,
}
```

## Similar plugins

- [nvim-telescope/telescope-fzy-native.nvim](https://github.com/nvim-telescope/telescope-fzy-native.nvim)
