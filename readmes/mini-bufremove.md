<p align="center"> <img src="https://github.com/nvim-mini/assets/blob/main/logo-2/logo-bufremove_readme.png?raw=true" alt="mini.bufremove" style="max-width:100%;border:solid 2px"/> </p>

### Buffer removing (unshow, delete, wipeout), which saves window layout

See more details in [Features](#features) and [Documentation](../doc/mini-bufremove.txt).

---

> [!NOTE]
> This was previously hosted at a personal `echasnovski` GitHub account. It was transferred to a dedicated organization to improve long term project stability. See more details [here](https://github.com/nvim-mini/mini.nvim/discussions/1970).

⦿ This is a part of [mini.nvim](https://nvim-mini.org/mini.nvim) library. Please use [this link](https://nvim-mini.org/mini.nvim/readmes/mini-bufremove) if you want to mention this module.

⦿ All contributions (issues, pull requests, discussions, etc.) are done inside of 'mini.nvim'.

⦿ See [whole library documentation](https://nvim-mini.org/mini.nvim/doc/mini-nvim) to learn about general design principles, disable/configuration recipes, and more.

⦿ See [MiniMax](https://nvim-mini.org/MiniMax) for a full config example that uses this module.

---

If you want to help this project grow but don't know where to start, check out [contributing guides of 'mini.nvim'](https://nvim-mini.org/mini.nvim/CONTRIBUTING) or leave a Github star for 'mini.nvim' project and/or any its standalone Git repositories.

## Demo

<!-- Demo source: https://github.com/nvim-mini/assets/blob/main/demo/demo-bufremove.mp4 -->
https://user-images.githubusercontent.com/24854248/173044032-7874cf95-2e41-49fb-8abe-3aa73526972f.mp4

## Features

Which buffer to show in window(s) after its current buffer is removed is decided by the algorithm:

- If alternate buffer is listed, use it.
- If previous listed buffer is different, use it.
- Otherwise create a scratch one with `nvim_create_buf(true, true)` and use it.

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

    | Branch | Code snippet                                                        |
    |--------|---------------------------------------------------------------------|
    | Main   | `add('nvim-mini/mini.bufremove')`                                   |
    | Stable | `add({ source = 'nvim-mini/mini.bufremove', checkout = 'stable' })` |

</details>

<details>
<summary>With <a href="https://github.com/folke/lazy.nvim">folke/lazy.nvim</a></summary>

- 'mini.nvim' library:

    | Branch | Code snippet                                  |
    |--------|-----------------------------------------------|
    | Main   | `{ 'nvim-mini/mini.nvim', version = false },` |
    | Stable | `{ 'nvim-mini/mini.nvim', version = '*' },`   |

- Standalone plugin:

    | Branch | Code snippet                                       |
    |--------|----------------------------------------------------|
    | Main   | `{ 'nvim-mini/mini.bufremove', version = false },` |
    | Stable | `{ 'nvim-mini/mini.bufremove', version = '*' },`   |

</details>

<details>
<summary>With <a href="https://github.com/junegunn/vim-plug">junegunn/vim-plug</a></summary>

- 'mini.nvim' library:

    | Branch | Code snippet                                         |
    |--------|------------------------------------------------------|
    | Main   | `Plug 'nvim-mini/mini.nvim'`                         |
    | Stable | `Plug 'nvim-mini/mini.nvim', { 'branch': 'stable' }` |

- Standalone plugin:

    | Branch | Code snippet                                              |
    |--------|-----------------------------------------------------------|
    | Main   | `Plug 'nvim-mini/mini.bufremove'`                         |
    | Stable | `Plug 'nvim-mini/mini.bufremove', { 'branch': 'stable' }` |

</details>

**Important**: no need to call `require('mini.bufremove').setup()`, but it can be done to improve usability.

**Note**: if you are on Windows, there might be problems with too long file paths (like `error: unable to create file <some file name>: Filename too long`). Try doing one of the following:

- Enable corresponding git global config value: `git config --system core.longpaths true`. Then try to reinstall.
- Install plugin in other place with shorter path.

## Default config

```lua
-- No need to copy this inside `setup()`. Will be used automatically.
{
  -- Whether to disable showing non-error feedback
  silent = false,
}
```

## Similar plugins

- [mhinz/vim-sayonara](https://github.com/mhinz/vim-sayonara)
- [moll/vim-bbye](https://github.com/moll/vim-bbye)
