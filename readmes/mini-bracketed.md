<p align="center"> <img src="https://github.com/nvim-mini/assets/blob/main/logo-2/logo-bracketed_readme.png?raw=true" alt="mini.bracketed" style="max-width:100%;border:solid 2px"/> </p>

### Go forward/backward with square brackets

See more details in [Features](#features) and [Documentation](../doc/mini-bracketed.txt).

---

> [!NOTE]
> This was previously hosted at a personal `echasnovski` GitHub account. It was transferred to a dedicated organization to improve long term project stability. See more details [here](https://github.com/nvim-mini/mini.nvim/discussions/1970).

⦿ This is a part of [mini.nvim](https://nvim-mini.org/mini.nvim) library. Please use [this link](https://nvim-mini.org/mini.nvim/readmes/mini-bracketed) if you want to mention this module.

⦿ All contributions (issues, pull requests, discussions, etc.) are done inside of 'mini.nvim'.

⦿ See [whole library documentation](https://nvim-mini.org/mini.nvim/doc/mini-nvim) to learn about general design principles, disable/configuration recipes, and more.

⦿ See [MiniMax](https://nvim-mini.org/MiniMax) for a full config example that uses this module.

---

If you want to help this project grow but don't know where to start, check out [contributing guides of 'mini.nvim'](https://nvim-mini.org/mini.nvim/CONTRIBUTING) or leave a Github star for 'mini.nvim' project and/or any its standalone Git repositories.

## Demo

<!-- Demo source: https://github.com/nvim-mini/assets/blob/main/demo/demo-bracketed.mp4 -->
https://user-images.githubusercontent.com/24854248/220173251-cd905d8f-ad07-4654-bba5-971220fad80a.mp4

## Features

- Configurable Lua functions to go forward/backward to a certain target. Each function can be customized with:
    - Direction. One of "forward", "backward", "first" (forward starting from first one), "last" (backward starting from last one).
    - Number of times to go.
    - Whether to wrap on edges (going forward on last one goes to first).
    - Some other target specific options.

- Mappings using square brackets. They are created using configurable target suffix and can be selectively disabled.

  Each mapping supports |[count]|. Mappings are created in Normal mode; for targets which move cursor in current buffer also Visual and Operator-pending (with dot-repeat) modes are supported.

  Using `lower-suffix` and `upper-suffix` (lower and upper case suffix) for a single target the following mappings are created:
    - `[` + `upper-suffix` : go first.
    - `[` + `lower-suffix` : go backward.
    - `]` + `lower-suffix` : go forward.
    - `]` + `upper-suffix` : go last.

- Supported targets (for more information see help for corresponding Lua function):

    | Target                                            | Mappings            | Lua function                 |
    |---------------------------------------------------|---------------------|------------------------------|
    | Buffer                                            | `[B` `[b` `]b` `]B` | `MiniBracketed.buffer()`     |
    | Comment block                                     | `[C` `[c` `]c` `]C` | `MiniBracketed.comment()`    |
    | Conflict marker                                   | `[X` `[x` `]x` `]X` | `MiniBracketed.conflict()`   |
    | Diagnostic                                        | `[D` `[d` `]d` `]D` | `MiniBracketed.diagnostic()` |
    | File on disk                                      | `[F` `[f` `]f` `]F` | `MiniBracketed.file()`       |
    | Indent change                                     | `[I` `[i` `]i` `]I` | `MiniBracketed.indent()`     |
    | Jump from jumplist inside current buffer          | `[J` `[j` `]j` `]J` | `MiniBracketed.jump()`       |
    | Location from location list                       | `[L` `[l` `]l` `]L` | `MiniBracketed.location()`   |
    | Old files                                         | `[O` `[o` `]o` `]O` | `MiniBracketed.oldfile()`    |
    | Quickfix entry from quickfix list                 | `[Q` `[q` `]q` `]Q` | `MiniBracketed.quickfix()`   |
    | Tree-sitter node and parents                      | `[T` `[t` `]t` `]T` | `MiniBracketed.treesitter()` |
    | Undo states from specially tracked linear history | `[U` `[u` `]u` `]U` | `MiniBracketed.undo()`       |
    | Window in current tab                             | `[W` `[w` `]w` `]W` | `MiniBracketed.window()`     |
    | Yank selection replacing latest put region        | `[Y` `[y` `]y` `]Y` | `MiniBracketed.yank()`       |

Notes:

- The `undo` target remaps `u` and `<C-R>` keys to register undo state after undo and redo respectively. If this conflicts with your setup, either disable `undo` target or make your remaps after calling `MiniBracketed.setup()`. To use `undo` target, remap your undo/redo keys to call `MiniBracketed.register_undo_state()` after the action.

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
    | Main   | `add('nvim-mini/mini.bracketed')`                                   |
    | Stable | `add({ source = 'nvim-mini/mini.bracketed', checkout = 'stable' })` |

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
    | Main   | `{ 'nvim-mini/mini.bracketed', version = false },` |
    | Stable | `{ 'nvim-mini/mini.bracketed', version = '*' },`   |

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
    | Main   | `Plug 'nvim-mini/mini.bracketed'`                         |
    | Stable | `Plug 'nvim-mini/mini.bracketed', { 'branch': 'stable' }` |

</details>

**Important**: don't forget to call `require('mini.bracketed').setup()` to enable its functionality.

**Note**: if you are on Windows, there might be problems with too long file paths (like `error: unable to create file <some file name>: Filename too long`). Try doing one of the following:

- Enable corresponding git global config value: `git config --system core.longpaths true`. Then try to reinstall.
- Install plugin in other place with shorter path.

## Default config

```lua
-- No need to copy this inside `setup()`. Will be used automatically.
{
  -- First-level elements are tables describing behavior of a target:
  --
  -- - <suffix> - single character suffix. Used after `[` / `]` in mappings.
  --   For example, with `b` creates `[B`, `[b`, `]b`, `]B` mappings.
  --   Supply empty string `''` to not create mappings.
  --
  -- - <options> - table overriding target options.
  --
  -- See `:h MiniBracketed.config` for more info.

  buffer     = { suffix = 'b', options = {} },
  comment    = { suffix = 'c', options = {} },
  conflict   = { suffix = 'x', options = {} },
  diagnostic = { suffix = 'd', options = {} },
  file       = { suffix = 'f', options = {} },
  indent     = { suffix = 'i', options = {} },
  jump       = { suffix = 'j', options = {} },
  location   = { suffix = 'l', options = {} },
  oldfile    = { suffix = 'o', options = {} },
  quickfix   = { suffix = 'q', options = {} },
  treesitter = { suffix = 't', options = {} },
  undo       = { suffix = 'u', options = {} },
  window     = { suffix = 'w', options = {} },
  yank       = { suffix = 'y', options = {} },
}
```

## Similar plugins

- [tpope/vim-unimpaired](https://github.com/tpope/vim-unimpaired)
