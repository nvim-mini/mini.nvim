<p align="center"> <img src="https://github.com/nvim-mini/assets/blob/main/logo-2/logo-cursorword_readme.png?raw=true" alt="mini.cursorword"/> </p>

### Automatic highlighting of word under cursor

See more details in [Features](#features) and [help file](../doc/mini-cursorword.txt).

---

> [!NOTE]
> This was previously hosted at a personal `echasnovski` GitHub account. It was transferred to a dedicated organization to improve long term project stability. See more details [here](https://github.com/nvim-mini/mini.nvim/discussions/1970).

⦿ This is a part of [mini.nvim](https://github.com/nvim-mini/mini.nvim) library. Please use [this link](https://github.com/nvim-mini/mini.nvim/blob/main/readmes/mini-cursorword.md) if you want to mention this module.

⦿ All contributions (issues, pull requests, discussions, etc.) are done inside of 'mini.nvim'.

⦿ See the repository page to learn about common design principles and configuration recipes.

---

If you want to help this project grow but don't know where to start, check out [contributing guides of 'mini.nvim'](https://github.com/nvim-mini/mini.nvim/blob/main/CONTRIBUTING.md) or leave a Github star for 'mini.nvim' project and/or any its standalone Git repositories.

## Demo

<!-- Demo source: https://github.com/nvim-mini/assets/blob/main/demo/demo-cursorword.mp4 -->
https://user-images.githubusercontent.com/24854248/173044454-0e4ab873-6e73-448d-838f-45f4b2be876b.mp4

## Features

- Current word under cursor can be highlighted differently.
- "Word under cursor" is meant as in Vim's `<cword>`: something user would get as 'iw' text object.
- Highlighting stops in insert and terminal modes.

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

    | Branch | Code snippet                                                         |
    |--------|----------------------------------------------------------------------|
    | Main   | `add(‘nvim-mini/mini.cursorword’)`                                   |
    | Stable | `add({ source = ‘nvim-mini/mini.cursorword’, checkout = ‘stable’ })` |

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
    | Main   | `{ 'nvim-mini/mini.cursorword', version = false },` |
    | Stable | `{ 'nvim-mini/mini.cursorword', version = '*' },`   |

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
    | Main   | `Plug 'nvim-mini/mini.cursorword'`                         |
    | Stable | `Plug 'nvim-mini/mini.cursorword', { 'branch': 'stable' }` |

</details>

<br>

**Important**: don't forget to call `require('mini.cursorword').setup()` to enable its functionality.

**Note**: if you are on Windows, there might be problems with too long file paths (like `error: unable to create file <some file name>: Filename too long`). Try doing one of the following:

- Enable corresponding git global config value: `git config --system core.longpaths true`. Then try to reinstall.

- Install plugin in other place with shorter path.

## Default config

```lua
-- No need to copy this inside `setup()`. Will be used automatically.
{
  -- Delay (in ms) between when cursor moved and when highlighting appeared
  delay = 100,
}
```

## Similar plugins

- [RRethy/vim-illuminate](https://github.com/RRethy/vim-illuminate)
- [itchyny/vim-cursorword](https://github.com/itchyny/vim-cursorword)
