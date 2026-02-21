<p align="center"> <img src="https://github.com/nvim-mini/assets/blob/main/logo-2/logo-extra_readme.png?raw=true" alt="mini.extra" style="max-width:100%;border:solid 2px"/> </p>

### Extra 'mini.nvim' functionality

See more details in [Features](#features) and [Documentation](../doc/mini-extra.txt).

---

> [!NOTE]
> This was previously hosted at a personal `echasnovski` GitHub account. It was transferred to a dedicated organization to improve long term project stability. See more details [here](https://github.com/nvim-mini/mini.nvim/discussions/1970).

⦿ This is a part of [mini.nvim](https://nvim-mini.org/mini.nvim) library. Please use [this link](https://nvim-mini.org/mini.nvim/readmes/mini-extra) if you want to mention this module.

⦿ All contributions (issues, pull requests, discussions, etc.) are done inside of 'mini.nvim'.

⦿ See [whole library documentation](https://nvim-mini.org/mini.nvim/doc/mini-nvim) to learn about general design principles, disable/configuration recipes, and more.

⦿ See [MiniMax](https://nvim-mini.org/MiniMax) for a full config example that uses this module.

---

If you want to help this project grow but don't know where to start, check out [contributing guides of 'mini.nvim'](https://nvim-mini.org/mini.nvim/CONTRIBUTING) or leave a Github star for 'mini.nvim' project and/or any its standalone Git repositories.

## Demo

<!-- Demo source: https://github.com/nvim-mini/assets/blob/main/demo/demo-extra.mp4 -->
https://github.com/nvim-mini/mini.nvim/assets/24854248/31ceb716-eefa-4858-b77f-5b6b3fe594f5

## Features

Extra useful functionality which is not essential enough for other 'mini.nvim' modules to include directly.

Features:

- Various pickers for ['mini.pick'](https://nvim-mini.org/mini.nvim/readmes/mini-pick):
    - Built-in diagnostic (`MiniExtra.pickers.diagnostic()`).
    - File explorer (`MiniExtra.pickers.explorer()`).
    - Git branches/commits/files/hunks (`MiniExtra.pickers.git_hunks()`, etc.).
    - Command/search/input history (`MiniExtra.pickers.history()`).
    - LSP references/symbols/etc. (`MiniExtra.pickers.lsp()`).
    - Tree-sitter nodes (`MiniExtra.pickers.treesitter()`).
    - **And much more**.
  See `:h MiniExtra.pickers` for more.

- Various textobject specifications for ['mini.ai'](https://nvim-mini.org/mini.nvim/readmes/mini-ai). See `:h MiniExtra.gen_ai_spec`.

- Various highlighters for ['mini.hipatterns'](https://nvim-mini.org/mini.nvim/readmes/mini-hipatterns). See `:h MiniExtra.gen_highlighter`.

Notes:

- This module requires only those 'mini.nvim' modules which are needed for a particular functionality: 'mini.pick' for pickers, etc.

For more information see these parts of help:

- `:h MiniExtra.pickers`
- `:h MiniExtra.gen_ai_spec`
- `:h MiniExtra.gen_highlighter`

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
    | Main   | `add('nvim-mini/mini.extra')`                                   |
    | Stable | `add({ source = 'nvim-mini/mini.extra', checkout = 'stable' })` |

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
    | Main   | `{ 'nvim-mini/mini.extra', version = false },` |
    | Stable | `{ 'nvim-mini/mini.extra', version = '*' },`   |

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
    | Main   | `Plug 'nvim-mini/mini.extra'`                         |
    | Stable | `Plug 'nvim-mini/mini.extra', { 'branch': 'stable' }` |

</details>

**Important**: don't forget to call `require('mini.extra').setup()` to enable its functionality.

**Note**: if you are on Windows, there might be problems with too long file paths (like `error: unable to create file <some file name>: Filename too long`). Try doing one of the following:

- Enable corresponding git global config value: `git config --system core.longpaths true`. Then try to reinstall.
- Install plugin in other place with shorter path.

## Default config

```lua
-- No need to copy this inside `setup()`. Will be used automatically.
{}
```

## Similar plugins

- [nvim-telescope/telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- [ibhagwan/fzf-lua](https://github.com/ibhagwan/fzf-lua)
