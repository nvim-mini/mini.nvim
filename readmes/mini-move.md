<p align="center"> <img src="https://github.com/nvim-mini/assets/blob/main/logo-2/logo-move_readme.png?raw=true" alt="mini.move" style="max-width:100%;border:solid 2px"/> </p>

### Move any selection in any direction

See more details in [Features](#features) and [Documentation](../doc/mini-move.txt).

---

> [!NOTE]
> This was previously hosted at a personal `echasnovski` GitHub account. It was transferred to a dedicated organization to improve long term project stability. See more details [here](https://github.com/nvim-mini/mini.nvim/discussions/1970).

⦿ This is a part of [mini.nvim](https://nvim-mini.org/mini.nvim) library. Please use [this link](https://nvim-mini.org/mini.nvim/readmes/mini-move) if you want to mention this module.

⦿ All contributions (issues, pull requests, discussions, etc.) are done inside of 'mini.nvim'.

⦿ See [whole library documentation](https://nvim-mini.org/mini.nvim/doc/mini-nvim) to learn about general design principles, disable/configuration recipes, and more.

⦿ See [MiniMax](https://nvim-mini.org/MiniMax) for a full config example that uses this module.

---

If you want to help this project grow but don't know where to start, check out [contributing guides of 'mini.nvim'](https://nvim-mini.org/mini.nvim/CONTRIBUTING) or leave a Github star for 'mini.nvim' project and/or any its standalone Git repositories.

## Demo

<!-- Demo source: https://github.com/nvim-mini/assets/blob/main/demo/demo-move.mp4 -->
https://user-images.githubusercontent.com/24854248/213466308-2e732d83-7c49-452d-8974-6b18b38bf89f.mp4

## Features

- Works in two modes:
    - Visual mode. Select text (charwise with `v`, linewise with `V`, and blockwise with `CTRL-V`) and press customizable mapping to move in all four directions (left, right, down, up). It keeps Visual mode.
    - Normal mode. Press customizable mapping to move current line in all four directions (left, right, down, up).
    - Special handling of linewise movement:
        - Vertical movement gets reindented with `=`.
        - Horizontal movement is improved indent/dedent with `>` / `<`.
        - Cursor moves along with selection.
- Provides both mappings and Lua functions for motions. See `:h MiniMove.move_selection()` and `:h MiniMove.move_line()`.
- Respects `v:count`. Movement mappings can be preceded by a number which multiplies command effect.
- All consecutive moves (regardless of direction) can be undone by a single `u`.
- Respects preferred column for vertical movement. It will vertically move selection as how cursor is moving (not strictly vertically if target column is not present in target line).

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
    | Main   | `add('nvim-mini/mini.move')`                                   |
    | Stable | `add({ source = 'nvim-mini/mini.move', checkout = 'stable' })` |

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
    | Main   | `{ 'nvim-mini/mini.move', version = false },` |
    | Stable | `{ 'nvim-mini/mini.move', version = '*' },`   |

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
    | Main   | `Plug 'nvim-mini/mini.move'`                         |
    | Stable | `Plug 'nvim-mini/mini.move', { 'branch': 'stable' }` |

</details>

**Important**: don't forget to call `require('mini.move').setup()` to enable its functionality.

**Note**: if you are on Windows, there might be problems with too long file paths (like `error: unable to create file <some file name>: Filename too long`). Try doing one of the following:

- Enable corresponding git global config value: `git config --system core.longpaths true`. Then try to reinstall.
- Install plugin in other place with shorter path.

## Default config

```lua
-- No need to copy this inside `setup()`. Will be used automatically.
{
  -- Module mappings. Use `''` (empty string) to disable one.
  mappings = {
    -- Move visual selection in Visual mode. Defaults are Alt (Meta) + hjkl.
    left = '<M-h>',
    right = '<M-l>',
    down = '<M-j>',
    up = '<M-k>',

    -- Move current line in Normal mode
    line_left = '<M-h>',
    line_right = '<M-l>',
    line_down = '<M-j>',
    line_up = '<M-k>',
  },

  -- Options which control moving behavior
  options = {
    -- Automatically reindent selection during linewise vertical move
    reindent_linewise = true,
  },
}
```

## Similar plugins

- [matze/vim-move](https://github.com/matze/vim-move)
- [booperlv/nvim-gomove](https://github.com/booperlv/nvim-gomove)
