<p align="center"> <img src="https://github.com/nvim-mini/assets/blob/main/logo-2/logo-input_readme.png?raw=true" alt="mini.input" style="max-width:100%;border:solid 2px"/> </p>

### Get user input

See more details in [Features](#features) and [Documentation](../doc/mini-input.txt).

---

⦿ This is a part of [mini.nvim](https://nvim-mini.org/mini.nvim) library. Please use [this link](https://nvim-mini.org/mini.nvim/readmes/mini-input) if you want to mention this module.

⦿ All contributions (issues, pull requests, discussions, etc.) are done inside of 'mini.nvim'.

⦿ See [whole library documentation](https://nvim-mini.org/mini.nvim/doc/mini-nvim) to learn about general design principles, disable/configuration recipes, and more.

<!-- ⦿ See [MiniMax](https://nvim-mini.org/MiniMax) for a full config example that uses this module. -->

---

If you want to help this project grow but don't know where to start, check out [contributing guides of 'mini.nvim'](https://nvim-mini.org/mini.nvim/CONTRIBUTING) or leave a Github star for 'mini.nvim' project and/or any its standalone Git repositories.

## Demo

<!-- Demo source: https://github.com/nvim-mini/assets/blob/main/demo/demo-input.mp4 -->
https://github.com/user-attachments/assets/949968dc-220f-4a2b-bc96-e553f2c05de4

**Note**: This demo uses custom `vim.notify` from [mini.notify](https://nvim-mini.org/mini.nvim/readmes/mini-notify).

## Features

- Get user input with fully customizable key and view handling.

- Built-in configurable views as floating window, statusline/tabline/winbar, virtual line/text.

- Implementation is non-blocking but waits to return the input. It also works in any mode without requiring mode change. See `:h MiniInput-lifecycle`.

- `vim.ui.input()` implementation. To adjust, use `MiniInput.ui_input()` or save-restore `vim.ui.input` manually after calling `MiniInput.setup()`.

For more information see these parts of help:

- `:h MiniInput.get()`
- `:h MiniInput.default_key()`
- `:h MiniInput-state`
- `:h MiniInput-examples`
- `:h MiniInput-in-other-plugins`

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
vim.pack.add({ 'https://github.com/nvim-mini/mini.input' })
```

<!-- Stable branch: -->
<!---->
<!-- ```lua -->
<!-- vim.pack.add({ -->
<!--   { src = 'https://github.com/nvim-mini/mini.input', version = 'stable' }, -->
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
add('nvim-mini/mini.input')
```

<!-- Stable branch: -->
<!---->
<!-- ```lua -->
<!-- add({ source = 'nvim-mini/mini.input', checkout = 'stable' }) -->
<!-- ``` -->

</details>

<details>
<summary>With <a href="https://github.com/folke/lazy.nvim">folke/lazy.nvim</a></summary>

**Full library**

Follow ['mini.nvim' installation](https://nvim-mini.org/mini.nvim#installation).

**Standalone plugin**

Main branch:

```lua
{ 'nvim-mini/mini.input', version = false },
```

<!-- Stable branch: -->
<!---->
<!-- ```lua -->
<!-- { 'nvim-mini/mini.input', version = '*' }, -->
<!-- ``` -->

</details>

**Important**: don't forget to call `require('mini.input').setup()` to enable its functionality.

**Note**: if you are on Windows, there might be problems with too long file paths (like `error: unable to create file <some file name>: Filename too long`). Try doing one of the following:

- Enable corresponding git global config value: `git config --system core.longpaths true`. Then try to reinstall.
- Install plugin in other place with shorter path.

## Default config

```lua
-- No need to copy this inside `setup()`. Will be used automatically.
{
  -- Functions that control input lifecycle
  handlers = {
    -- Compute completion candidates
    complete = nil,

    -- Compute highlighting of current input
    highlight = nil,

    -- Handle input start, every key press, and input end
    key = nil,

    -- Show current input state
    view = nil,
  },

  -- Default input scope: cursor/line/buffer/window/tabpage/editor/project
  scope = 'editor',
}
```

## Similar plugins

- [folke/snacks.nvim#input](https://github.com/folke/snacks.nvim/blob/main/docs/input.md)
- Built-in [input()](https://neovim.io/doc/user/helptag.html?tag=input())
