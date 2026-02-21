<p align="center"> <img src="https://github.com/nvim-mini/assets/blob/main/logo-2/logo-trailspace_readme.png?raw=true" alt="mini.trailspace" style="max-width:100%;border:solid 2px"/> </p>

### Work with trailing whitespace

See more details in [Features](#features) and [Documentation](../doc/mini-trailspace.txt).

---

> [!NOTE]
> This was previously hosted at a personal `echasnovski` GitHub account. It was transferred to a dedicated organization to improve long term project stability. See more details [here](https://github.com/nvim-mini/mini.nvim/discussions/1970).

⦿ This is a part of [mini.nvim](https://nvim-mini.org/mini.nvim) library. Please use [this link](https://nvim-mini.org/mini.nvim/readmes/mini-trailspace) if you want to mention this module.

⦿ All contributions (issues, pull requests, discussions, etc.) are done inside of 'mini.nvim'.

⦿ See [whole library documentation](https://nvim-mini.org/mini.nvim/doc/mini-nvim) to learn about general design principles, disable/configuration recipes, and more.

⦿ See [MiniMax](https://nvim-mini.org/MiniMax) for a full config example that uses this module.

---

If you want to help this project grow but don't know where to start, check out [contributing guides of 'mini.nvim'](https://nvim-mini.org/mini.nvim/CONTRIBUTING) or leave a Github star for 'mini.nvim' project and/or any its standalone Git repositories.

## Demo

<!-- Demo source: https://github.com/nvim-mini/assets/blob/main/demo/demo-trailspace.mp4 -->
https://user-images.githubusercontent.com/24854248/173045420-7aaf21b6-1d2e-4333-8a23-dea7e49c3a01.mp4

## Features

- Highlighting is done only in modifiable buffer by default, only in Normal mode, and stops in Insert mode and when leaving window.
- Trim all trailing whitespace with `MiniTrailspace.trim()`.
- Trim all trailing empty lines with `MiniTrailspace.trim_last_lines()`.

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
    | Main   | `add('nvim-mini/mini.trailspace')`                                   |
    | Stable | `add({ source = 'nvim-mini/mini.trailspace', checkout = 'stable' })` |

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
    | Main   | `{ 'nvim-mini/mini.trailspace', version = false },` |
    | Stable | `{ 'nvim-mini/mini.trailspace', version = '*' },`   |

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
    | Main   | `Plug 'nvim-mini/mini.trailspace'`                         |
    | Stable | `Plug 'nvim-mini/mini.trailspace', { 'branch': 'stable' }` |

</details>

**Important**: don't forget to call `require('mini.trailspace').setup()` to enable its functionality.

**Note**: if you are on Windows, there might be problems with too long file paths (like `error: unable to create file <some file name>: Filename too long`). Try doing one of the following:

- Enable corresponding git global config value: `git config --system core.longpaths true`. Then try to reinstall.
- Install plugin in other place with shorter path.

## Default config

```lua
-- No need to copy this inside `setup()`. Will be used automatically.
{
  -- Highlight only in normal buffers (ones with empty 'buftype'). This is
  -- useful to not show trailing whitespace where it usually doesn't matter.
  only_in_normal_buffers = true,
}
```

## Similar plugins

- [ntpeters/vim-better-whitespace](https://github.com/ntpeters/vim-better-whitespace)
