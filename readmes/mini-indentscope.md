<p align="center"> <img src="https://github.com/nvim-mini/assets/blob/main/logo-2/logo-indentscope_readme.png?raw=true" alt="mini.indentscope" style="max-width:100%;border:solid 2px"/> </p>

### Visualize and work with indent scope

- Customizable debounce delay, animation style, and scope computation options.
- Implements scope-related motions and textobjects.

See more details in [Features](#features) and [Documentation](../doc/mini-indentscope.txt).

---

> [!NOTE]
> This was previously hosted at a personal `echasnovski` GitHub account. It was transferred to a dedicated organization to improve long term project stability. See more details [here](https://github.com/nvim-mini/mini.nvim/discussions/1970).

⦿ This is a part of [mini.nvim](https://nvim-mini.org/mini.nvim) library. Please use [this link](https://nvim-mini.org/mini.nvim/readmes/mini-indentscope) if you want to mention this module.

⦿ All contributions (issues, pull requests, discussions, etc.) are done inside of 'mini.nvim'.

⦿ See [whole library documentation](https://nvim-mini.org/mini.nvim/doc/mini-nvim) to learn about general design principles, disable/configuration recipes, and more.

⦿ See [MiniMax](https://nvim-mini.org/MiniMax) for a full config example that uses this module.

---

If you want to help this project grow but don't know where to start, check out [contributing guides of 'mini.nvim'](https://nvim-mini.org/mini.nvim/CONTRIBUTING) or leave a Github star for 'mini.nvim' project and/or any its standalone Git repositories.

## Demo

<!-- Demo source: https://github.com/nvim-mini/assets/blob/main/demo/demo-indentscope.mp4 -->
https://user-images.githubusercontent.com/24854248/173044654-f5f0b928-6bd9-4064-a916-1f980044c7ad.mp4

## Features

- Visualize scope with **animated** vertical line. It is very fast and done automatically in a non-blocking way (other operations can be performed, like moving cursor). You can customize debounce delay and animation rule.
- Customization of scope computation options can be done on global level (in `MiniIndentscope.config`), for a certain buffer (using `vim.b.miniindentscope_config` buffer variable), or within a call (using `opts` variable in `MiniIndentscope.get_scope()`).
- Customizable notion of a border: which adjacent lines with strictly lower indent are recognized as such. This is useful for a certain filetypes (for example, Python or plain text).
- Customizable way of line to be considered "border first". This is useful if you want to place cursor on function header and get scope of its body.
- There are textobjects and motions to operate on scope. Support `v:count` and dot-repeat (in operator pending mode).

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

    | Branch | Code snippet                                                          |
    |--------|-----------------------------------------------------------------------|
    | Main   | `add('nvim-mini/mini.indentscope')`                                   |
    | Stable | `add({ source = 'nvim-mini/mini.indentscope', checkout = 'stable' })` |

</details>

<details>
<summary>With <a href="https://github.com/folke/lazy.nvim">folke/lazy.nvim</a></summary>

- 'mini.nvim' library:

    | Branch | Code snippet                                  |
    |--------|-----------------------------------------------|
    | Main   | `{ 'nvim-mini/mini.nvim', version = false },` |
    | Stable | `{ 'nvim-mini/mini.nvim', version = '*' },`   |

- Standalone plugin:

    | Branch | Code snippet                                         |
    |--------|------------------------------------------------------|
    | Main   | `{ 'nvim-mini/mini.indentscope', version = false },` |
    | Stable | `{ 'nvim-mini/mini.indentscope', version = '*' },`   |

</details>

<details>
<summary>With <a href="https://github.com/junegunn/vim-plug">junegunn/vim-plug</a></summary>

- 'mini.nvim' library:

    | Branch | Code snippet                                         |
    |--------|------------------------------------------------------|
    | Main   | `Plug 'nvim-mini/mini.nvim'`                         |
    | Stable | `Plug 'nvim-mini/mini.nvim', { 'branch': 'stable' }` |

- Standalone plugin:

    | Branch | Code snippet                                                |
    |--------|-------------------------------------------------------------|
    | Main   | `Plug 'nvim-mini/mini.indentscope'`                         |
    | Stable | `Plug 'nvim-mini/mini.indentscope', { 'branch': 'stable' }` |

</details>

**Important**: don't forget to call `require('mini.indentscope').setup()` to enable its functionality.

**Note**: if you are on Windows, there might be problems with too long file paths (like `error: unable to create file <some file name>: Filename too long`). Try doing one of the following:

- Enable corresponding git global config value: `git config --system core.longpaths true`. Then try to reinstall.
- Install plugin in other place with shorter path.

## Default config

```lua
-- No need to copy this inside `setup()`. Will be used automatically.
{
  -- Draw options
  draw = {
    -- Delay (in ms) between event and start of drawing scope indicator
    delay = 100,

    -- Animation rule for scope's first drawing. A function which, given
    -- next and total step numbers, returns wait time (in ms). See
    -- |MiniIndentscope.gen_animation| for builtin options. To disable
    -- animation, use `require('mini.indentscope').gen_animation.none()`.
    animation = --<function: implements constant 20ms between steps>,

    -- Whether to auto draw scope: return `true` to draw, `false` otherwise.
    -- Default draws only fully computed scope (see `options.n_lines`).
    predicate = function(scope) return not scope.body.is_incomplete end,

    -- Symbol priority. Increase to display on top of more symbols.
    priority = 2,
  },

  -- Module mappings. Use `''` (empty string) to disable one.
  mappings = {
    -- Textobjects
    object_scope = 'ii',
    object_scope_with_border = 'ai',

    -- Motions (jump to respective border line; if not present - body line)
    goto_top = '[i',
    goto_bottom = ']i',
  },

  -- Options which control scope computation
  options = {
    -- Type of scope's border: which line(s) with smaller indent to
    -- categorize as border. Can be one of: 'both', 'top', 'bottom', 'none'.
    border = 'both',

    -- Whether to use cursor column when computing reference indent.
    -- Useful to see incremental scopes with horizontal cursor movements.
    indent_at_cursor = true,

    -- Maximum number of lines above or below within which scope is computed
    n_lines = 10000,

    -- Whether to first check input line to be a border of adjacent scope.
    -- Use it if you want to place cursor on function header to get scope of
    -- its body.
    try_as_border = false,
  },

  -- Which character to use for drawing scope indicator
  symbol = '╎',
}
```

## Similar plugins

- [lukas-reineke/indent-blankline.nvim](https://github.com/lukas-reineke/indent-blankline.nvim)
- [michaeljsmith/vim-indent-object](https://github.com/michaeljsmith/vim-indent-object)
