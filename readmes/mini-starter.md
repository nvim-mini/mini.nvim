<p align="center"> <img src="https://github.com/nvim-mini/assets/blob/main/logo-2/logo-starter_readme.png?raw=true" alt="mini.starter" style="max-width:100%;border:solid 2px"/> </p>

### Fast and flexible start screen

See more details in [Features](#features) and [Documentation](../doc/mini-starter.txt).

---

> [!NOTE]
> This was previously hosted at a personal `echasnovski` GitHub account. It was transferred to a dedicated organization to improve long term project stability. See more details [here](https://github.com/nvim-mini/mini.nvim/discussions/1970).

⦿ This is a part of [mini.nvim](https://nvim-mini.org/mini.nvim) library. Please use [this link](https://nvim-mini.org/mini.nvim/readmes/mini-starter) if you want to mention this module.

⦿ All contributions (issues, pull requests, discussions, etc.) are done inside of 'mini.nvim'.

⦿ See [whole library documentation](https://nvim-mini.org/mini.nvim/doc/mini-nvim) to learn about general design principles, disable/configuration recipes, and more.

⦿ See [MiniMax](https://nvim-mini.org/MiniMax) for a full config example that uses this module.

---

If you want to help this project grow but don't know where to start, check out [contributing guides of 'mini.nvim'](https://nvim-mini.org/mini.nvim/CONTRIBUTING) or leave a Github star for 'mini.nvim' project and/or any its standalone Git repositories.

## Demo

<!-- Demo source: https://github.com/nvim-mini/assets/blob/main/demo/demo-starter.mp4 -->
https://user-images.githubusercontent.com/24854248/173045153-19087983-0211-4ab9-8278-909616b53c7e.mp4

## Features

- All available actions are defined inside items. There are pre-configured whole sections in `MiniStarter.sections`.
- Configure what items are displayed by supplying an array which can be normalized to an array of items. Read about how supplied items are normalized in `MiniStarter.refresh()`.
- Modify the final look by supplying content hooks. There are pre-configured content hook generators in `MiniStarter.gen_hook`.
- Choosing an item can be done in two ways:
    - Type prefix query to filter item by matching its name (ignoring case). Displayed information is updated after every typed character. For every item its unique prefix is highlighted.
    - Use Down/Up arrows (or `<C-n>`/`<C-p>`, or `<M-j>`/`<M-k>`) and hit Enter.
- Allow multiple simultaneously open Starter buffers.

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

    | Branch | Code snippet                                                      |
    |--------|-------------------------------------------------------------------|
    | Main   | `add('nvim-mini/mini.starter')`                                   |
    | Stable | `add({ source = 'nvim-mini/mini.starter', checkout = 'stable' })` |

</details>

<details>
<summary>With <a href="https://github.com/folke/lazy.nvim">folke/lazy.nvim</a></summary>

- 'mini.nvim' library:

    | Branch | Code snippet                                  |
    |--------|-----------------------------------------------|
    | Main   | `{ 'nvim-mini/mini.nvim', version = false },` |
    | Stable | `{ 'nvim-mini/mini.nvim', version = '*' },`   |

- Standalone plugin:

    | Branch | Code snippet                                     |
    |--------|--------------------------------------------------|
    | Main   | `{ 'nvim-mini/mini.starter', version = false },` |
    | Stable | `{ 'nvim-mini/mini.starter', version = '*' },`   |

</details>

<details>
<summary>With <a href="https://github.com/junegunn/vim-plug">junegunn/vim-plug</a></summary>

- 'mini.nvim' library:

    | Branch | Code snippet                                         |
    |--------|------------------------------------------------------|
    | Main   | `Plug 'nvim-mini/mini.nvim'`                         |
    | Stable | `Plug 'nvim-mini/mini.nvim', { 'branch': 'stable' }` |

- Standalone plugin:

    | Branch | Code snippet                                            |
    |--------|---------------------------------------------------------|
    | Main   | `Plug 'nvim-mini/mini.starter'`                         |
    | Stable | `Plug 'nvim-mini/mini.starter', { 'branch': 'stable' }` |

</details>

**Important**: don't forget to call `require('mini.starter').setup()` to enable its functionality.

**Note**: if you are on Windows, there might be problems with too long file paths (like `error: unable to create file <some file name>: Filename too long`). Try doing one of the following:

- Enable corresponding git global config value: `git config --system core.longpaths true`. Then try to reinstall.
- Install plugin in other place with shorter path.

## Default config

```lua
-- No need to copy this inside `setup()`. Will be used automatically.
{
  -- Whether to open starter buffer on VimEnter. Not opened if Neovim was
  -- started with intent to show something else.
  autoopen = true,

  -- Whether to evaluate action of single active item
  evaluate_single = false,

  -- Items to be displayed. Should be an array with the following elements:
  -- - Item: table with <action>, <name>, and <section> keys.
  -- - Function: should return one of these three categories.
  -- - Array: elements of these three types (i.e. item, array, function).
  -- If `nil` (default), default items will be used (see |mini.starter|).
  items = nil,

  -- Header to be displayed before items. Converted to single string via
  -- `tostring` (use `\n` to display several lines). If function, it is
  -- evaluated first. If `nil` (default), polite greeting will be used.
  header = nil,

  -- Footer to be displayed after items. Converted to single string via
  -- `tostring` (use `\n` to display several lines). If function, it is
  -- evaluated first. If `nil` (default), default usage help will be shown.
  footer = nil,

  -- Array  of functions to be applied consecutively to initial content.
  -- Each function should take and return content for 'Starter' buffer (see
  -- |mini.starter| and |MiniStarter.content| for more details).
  content_hooks = nil,

  -- Characters to update query. Each character will have special buffer
  -- mapping overriding your global ones. Be careful to not add `:` as it
  -- allows you to go into command mode.
  query_updaters = 'abcdefghijklmnopqrstuvwxyz0123456789_-.',

  -- Whether to disable showing non-error feedback
  silent = false,
}
```

## Similar plugins

- [mhinz/vim-startify](https://github.com/mhinz/vim-startify)
- [glepnir/dashboard-nvim](https://github.com/glepnir/dashboard-nvim)
- [goolord/alpha-nvim](https://github.com/goolord/alpha-nvim)
