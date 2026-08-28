<p align="center"> <img src="https://github.com/nvim-mini/assets/blob/main/logo-2/logo-statuscolumn_readme.png?raw=true" alt="mini.statuscolumn" style="max-width:100%;border:solid 2px"/> </p>

### Statuscolumn

See more details in [Features](#features) and [Documentation](../doc/mini-statuscolumn.txt).

---

⦿ This is a part of [mini.nvim](https://nvim-mini.org/mini.nvim) library. Please use [this link](https://nvim-mini.org/mini.nvim/readmes/mini-statuscolumn) if you want to mention this module.

⦿ All contributions (issues, pull requests, discussions, etc.) are done inside of 'mini.nvim'.

⦿ See [whole library documentation](https://nvim-mini.org/mini.nvim/doc/mini-nvim) to learn about general design principles, disable/configuration recipes, and more.

<!-- ⦿ See [MiniMax](https://nvim-mini.org/MiniMax) for a full config example that uses this module. -->

---

If you want to help this project grow but don't know where to start, check out [contributing guides of 'mini.nvim'](https://nvim-mini.org/mini.nvim/CONTRIBUTING) or leave a Github star for 'mini.nvim' project and/or any its standalone Git repositories.

## Demo

<!-- Demo source: https://github.com/nvim-mini/assets/blob/main/demo/demo-statuscolumn.mp4 -->
https://github.com/user-attachments/assets/63ed48eb-9fdf-4b59-b190-bbdc10fd28d9

## Features

- Fast [`'statuscolumn'`](https://neovim.io/doc/user/helptag.html?tag='statuscolumn') with improved defaults.
- Fully customizable content via functions that take precomputed useful data.
- `:h MiniStatuscolumn.gen_content.main()` for simplified customization.
- Automatic dimming inside inactive windows content.

Notes:
- Works best on Neovim>=0.11.
- Default content follows the behavior defined by options for the built-in statuscolumn sections. Like `'number'`, `'signcolumn'`, `'foldcolumn'`, etc.

## Installation

This plugin can be installed as part of 'mini.nvim' library (**recommended**) or as a standalone Git repository.

During beta-testing phase there is only one branch to install from:
<!-- There are two branches to install from: -->

- `main` (default, **recommended**) will have latest development version of plugin. All changes since last stable release should be perceived as being in beta testing phase (meaning they already passed alpha-testing and are moderately settled).
<!-- - `stable` will be updated only upon releases with code tested during public beta-testing phase in `main` branch. -->

Here are code snippets for some common installation methods (use only one):

<details>
<summary><b>(Recommended)</b> With <a href="https://neovim.io/doc/user/helptag.html?tag=vim.pack">vim.pack</a> (on Neovim 0.12 and newer)</summary>

**Full library**

Follow ['mini.nvim' installation](https://nvim-mini.org/mini.nvim#installation).

**Standalone plugin**

Main branch:

```lua
vim.pack.add({ 'https://github.com/nvim-mini/mini.statuscolumn' })
```

<!-- Stable branch: -->
<!---->
<!-- ```lua -->
<!-- vim.pack.add({ -->
<!--   { src = 'https://github.com/nvim-mini/mini.statuscolumn', version = 'stable' }, -->
<!-- }) -->
<!-- ``` -->

</details>

<details>
<summary>With <a href="https://nvim-mini.org/mini.nvim/readmes/mini-deps">mini.deps</a> (before Neovim 0.12)</summary>

**Full library**

Follow [recommended 'mini.deps' installation](https://nvim-mini.org/mini.nvim/readmes/mini-deps#installation).

**Standalone plugin**:

Main branch:

```lua
add('nvim-mini/mini.statuscolumn')
```

<!-- Stable branch: -->
<!---->
<!-- ```lua -->
<!-- add({ source = 'nvim-mini/mini.statuscolumn', checkout = 'stable' }) -->
<!-- ``` -->

</details>

<details>
<summary>With <a href="https://github.com/folke/lazy.nvim">folke/lazy.nvim</a></summary>

**Full library**

Follow ['mini.nvim' installation](https://nvim-mini.org/mini.nvim#installation).

**Standalone plugin**

Main branch:

```lua
{ 'nvim-mini/mini.statuscolumn', version = false },
```

<!-- Stable branch: -->
<!---->
<!-- ```lua -->
<!-- { 'nvim-mini/mini.statuscolumn', version = '*' }, -->
<!-- ``` -->

</details>

**Important**: don't forget to call `require('mini.statuscolumn').setup()` to enable its functionality.

**Note**: if you are on Windows, there might be problems with too long file paths (like `error: unable to create file <some file name>: Filename too long`). Try doing one of the following:

- Enable corresponding git global config value: `git config --system core.longpaths true`. Then try to reinstall.
- Install plugin in other place with shorter path.

## Default config

```lua
-- No need to copy this inside `setup()`. Will be used automatically.
{
  -- Statuscolumn content as functions that return statusline-like string
  content = {
    -- Content of an active window
    active = nil,
    -- Content of an inactive window
    inactive = nil,
  },

  -- Whether to dim column content in inactive windows
  dim_inactive = true,
}
```

## Similar plugins

- [luukvball/statuscol.nvim](https://github.com/luukvbaal/statuscol.nvim):
    - A framework with building blocks and configuration: custom sections, sign filters, fold functions.

      While this module aims to provide a performant `'statuscolumn'` with a sensible default with a limited (yet enough) customization and an entry point to building own `'statuscolumn'`.

- [folke/snacks.nvim#statuscolumn](https://github.com/folke/snacks.nvim/blob/main/docs/statuscolumn.md):
    - An opinionated `'statuscolumn'` implementation with a limited customization.

      While this module provides more opportunities for building custom implementation and more customization.
