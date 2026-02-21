<p align="center"> <img src="https://github.com/nvim-mini/assets/blob/main/logo-2/logo-hipatterns_readme.png?raw=true" alt="mini.hipatterns" style="max-width:100%;border:solid 2px"/> </p>

### Highlight patterns in text

See more details in [Features](#features) and [Documentation](../doc/mini-hipatterns.txt).

---

> [!NOTE]
> This was previously hosted at a personal `echasnovski` GitHub account. It was transferred to a dedicated organization to improve long term project stability. See more details [here](https://github.com/nvim-mini/mini.nvim/discussions/1970).

⦿ This is a part of [mini.nvim](https://nvim-mini.org/mini.nvim) library. Please use [this link](https://nvim-mini.org/mini.nvim/readmes/mini-hipatterns) if you want to mention this module.

⦿ All contributions (issues, pull requests, discussions, etc.) are done inside of 'mini.nvim'.

⦿ See [whole library documentation](https://nvim-mini.org/mini.nvim/doc/mini-nvim) to learn about general design principles, disable/configuration recipes, and more.

⦿ See [MiniMax](https://nvim-mini.org/MiniMax) for a full config example that uses this module.

---

If you want to help this project grow but don't know where to start, check out [contributing guides of 'mini.nvim'](https://nvim-mini.org/mini.nvim/CONTRIBUTING) or leave a Github star for 'mini.nvim' project and/or any its standalone Git repositories.

## Demo

<!-- Demo source: https://github.com/nvim-mini/assets/blob/main/demo/demo-hipatterns.mp4 -->
https://github.com/nvim-mini/mini.nvim/assets/24854248/130374e2-4e6c-43cf-af33-43d816b4fa32

## Features

- Highlight text with configurable patterns and highlight groups (can be string or callable).

- Highlighting is updated asynchronously with configurable debounce delay.

- Function to get matches in a buffer.

See `:h MiniHipatterns-examples` for examples of common use cases.

Notes:

- It does not define any highlighters by default. Add to `config.highlighters` to have a visible effect.

## Example usage

```lua
local hipatterns = require('mini.hipatterns')
hipatterns.setup({
  highlighters = {
    -- Highlight standalone 'FIXME', 'HACK', 'TODO', 'NOTE'
    fixme = { pattern = '%f[%w]()FIXME()%f[%W]', group = 'MiniHipatternsFixme' },
    hack  = { pattern = '%f[%w]()HACK()%f[%W]',  group = 'MiniHipatternsHack'  },
    todo  = { pattern = '%f[%w]()TODO()%f[%W]',  group = 'MiniHipatternsTodo'  },
    note  = { pattern = '%f[%w]()NOTE()%f[%W]',  group = 'MiniHipatternsNote'  },

    -- Highlight hex color strings (`#rrggbb`) using that color
    hex_color = hipatterns.gen_highlighter.hex_color(),
  },
})
```

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
    | Main   | `add('nvim-mini/mini.hipatterns')`                                   |
    | Stable | `add({ source = 'nvim-mini/mini.hipatterns', checkout = 'stable' })` |

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
    | Main   | `{ 'nvim-mini/mini.hipatterns', version = false },` |
    | Stable | `{ 'nvim-mini/mini.hipatterns', version = '*' },`   |

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
    | Main   | `Plug 'nvim-mini/mini.hipatterns'`                         |
    | Stable | `Plug 'nvim-mini/mini.hipatterns', { 'branch': 'stable' }` |

</details>

**Important**: don't forget to call `require('mini.hipatterns').setup()` with non-empty `highlighters` to auto-enable highlighting in all normal buffers.

**Note**: if you are on Windows, there might be problems with too long file paths (like `error: unable to create file <some file name>: Filename too long`). Try doing one of the following:

- Enable corresponding git global config value: `git config --system core.longpaths true`. Then try to reinstall.
- Install plugin in other place with shorter path.

## Default config

```lua
-- No need to copy this inside `setup()`. Will be used automatically.
{
  -- Table with highlighters (see |MiniHipatterns.config| for more details).
  -- Nothing is defined by default. Add manually for visible effect.
  highlighters = {},

  -- Delays (in ms) defining asynchronous highlighting process
  delay = {
    -- How much to wait for update after every text change
    text_change = 200,

    -- How much to wait for update after window scroll
    scroll = 50,
  },

}
```

## Similar plugins

- [folke/todo-comments.nvim](https://github.com/folke/todo-comments.nvim)
- [folke/paint.nvim](https://github.com/folke/paint.nvim)
- [NvChad/nvim-colorizer.lua](https://github.com/NvChad/nvim-colorizer.lua)
- [uga-rosa/ccc.nvim](https://github.com/uga-rosa/ccc.nvim)
