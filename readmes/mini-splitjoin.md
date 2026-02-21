<p align="center"> <img src="https://github.com/nvim-mini/assets/blob/main/logo-2/logo-splitjoin_readme.png?raw=true" alt="mini.splitjoin" style="max-width:100%;border:solid 2px"/> </p>

### Split and join arguments

See more details in [Features](#features) and [Documentation](../doc/mini-splitjoin.txt).

---

> [!NOTE]
> This was previously hosted at a personal `echasnovski` GitHub account. It was transferred to a dedicated organization to improve long term project stability. See more details [here](https://github.com/nvim-mini/mini.nvim/discussions/1970).

⦿ This is a part of [mini.nvim](https://nvim-mini.org/mini.nvim) library. Please use [this link](https://nvim-mini.org/mini.nvim/readmes/mini-splitjoin) if you want to mention this module.

⦿ All contributions (issues, pull requests, discussions, etc.) are done inside of 'mini.nvim'.

⦿ See [whole library documentation](https://nvim-mini.org/mini.nvim/doc/mini-nvim) to learn about general design principles, disable/configuration recipes, and more.

⦿ See [MiniMax](https://nvim-mini.org/MiniMax) for a full config example that uses this module.

---

If you want to help this project grow but don't know where to start, check out [contributing guides of 'mini.nvim'](https://nvim-mini.org/mini.nvim/CONTRIBUTING) or leave a Github star for 'mini.nvim' project and/or any its standalone Git repositories.

## Demo

<!-- Demo source: https://github.com/nvim-mini/assets/blob/main/demo/demo-splitjoin.mp4 -->
https://user-images.githubusercontent.com/24854248/223969793-e0e461ff-5a98-444f-9bc3-7b490ebfe59e.mp4

## Features

- Mappings and Lua functions that modify arguments (regions inside brackets between allowed separators) under cursor.

  Supported actions:
    - Toggle - split if arguments are on single line, join otherwise. Main supported function of the module. See `MiniSplitjoin.toggle()` in help file.
    - Split - make every argument separator be on end of separate line. See `MiniSplitjoin.split()` in help file.
    - Join - make all arguments be on single line. See `MiniSplitjoin.join()` in help file.

- Mappings are dot-repeatable in Normal mode and work in Visual mode.

- Customizable argument detection (see `MiniSplitjoin.config.detect` in help file):
    - Which brackets can contain arguments.
    - Which strings can separate arguments.
    - Which regions exclude when looking for separators (like inside nested brackets or quotes).

- Customizable pre and post hooks for both split and join. See `split` and `join` of `MiniSplitjoin.config` in help file.

- Works inside comments by using modified notion of indent. See `MiniSplitjoin.get_indent_part()` in help file.

- Provides low-level Lua functions for split and join at positions. See `MiniSplitjoin.split_at()` and `MiniSplitjoin.join_at()` in help file.

Notes:

- Search for arguments is done using Lua patterns (regex-like approach). Certain amount of false positives is to be expected.

- This module is mostly designed around `MiniSplitjoin.toggle()`. If initial split positions are on different lines, join first and then split.

- Actions can be done on Visual mode selection, which mostly present as a safety route in case of incorrect detection of initial region. It uses `MiniSplitjoin.get_visual_region()` which treats selection as full brackets (use `va)` and not `vi)`).

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
    | Main   | `add('nvim-mini/mini.splitjoin')`                                   |
    | Stable | `add({ source = 'nvim-mini/mini.splitjoin', checkout = 'stable' })` |

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
    | Main   | `{ 'nvim-mini/mini.splitjoin', version = false },` |
    | Stable | `{ 'nvim-mini/mini.splitjoin', version = '*' },`   |

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
    | Main   | `Plug 'nvim-mini/mini.splitjoin'`                         |
    | Stable | `Plug 'nvim-mini/mini.splitjoin', { 'branch': 'stable' }` |

</details>

**Important**: don't forget to call `require('mini.splitjoin').setup()` to enable its functionality.

**Note**: if you are on Windows, there might be problems with too long file paths (like `error: unable to create file <some file name>: Filename too long`). Try doing one of the following:

- Enable corresponding git global config value: `git config --system core.longpaths true`. Then try to reinstall.
- Install plugin in other place with shorter path.

## Default config

```lua
-- No need to copy this inside `setup()`. Will be used automatically.
{
  -- Module mappings. Use `''` (empty string) to disable one.
  -- Created for both Normal and Visual modes.
  mappings = {
    toggle = 'gS',
    split = '',
    join = '',
  },

  -- Detection options: where split/join should be done
  detect = {
    -- Array of Lua patterns to detect region with arguments.
    -- Default: { '%b()', '%b[]', '%b{}' }
    brackets = nil,

    -- String Lua pattern defining argument separator
    separator = ',',

    -- Array of Lua patterns for sub-regions to exclude separators from.
    -- Enables correct detection in presence of nested brackets and quotes.
    -- Default: { '%b()', '%b[]', '%b{}', '%b""', "%b''" }
    exclude_regions = nil,
  },

  -- Split options
  split = {
    hooks_pre = {},
    hooks_post = {},
  },

  -- Join options
  join = {
    hooks_pre = {},
    hooks_post = {},
  },
}
```

## Similar plugins

- [FooSoft/vim-argwrap](https://github.com/FooSoft/vim-argwrap)
- [AndrewRadev/splitjoin.vim](https://github.com/AndrewRadev/splitjoin.vim)
- [Wansmer/treesj](https://github.com/Wansmer/treesj)
