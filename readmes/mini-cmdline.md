<p align="center"> <img src="https://github.com/nvim-mini/assets/blob/main/logo-2/logo-cmdline_readme.png?raw=true" alt="mini.cmdline" style="max-width:100%;border:solid 2px"/> </p>

### Command line tweaks

See more details in [Features](#features) and [Documentation](../doc/mini-cmdline.txt).

---

⦿ This is a part of [mini.nvim](https://nvim-mini.org/mini.nvim) library. Please use [this link](https://nvim-mini.org/mini.nvim/readmes/mini-cmdline) if you want to mention this module.

⦿ All contributions (issues, pull requests, discussions, etc.) are done inside of 'mini.nvim'.

⦿ See [whole library documentation](https://nvim-mini.org/mini.nvim/doc/mini-nvim) to learn about general design principles, disable/configuration recipes, and more.

<!-- ⦿ See [MiniMax](https://nvim-mini.org/MiniMax) for a full config example that uses this module. -->

---

If you want to help this project grow but don't know where to start, check out [contributing guides of 'mini.nvim'](https://nvim-mini.org/mini.nvim/CONTRIBUTING) or leave a Github star for 'mini.nvim' project and/or any its standalone Git repositories.

## Demo

<!-- Demo source: https://github.com/nvim-mini/assets/blob/main/demo/demo-cmdline.mp4 -->
https://github.com/user-attachments/assets/7395e06c-d535-4911-ab53-164a1497d09a

## Features

- Autocomplete with customizable delay. Enhances [`:h cmdline-completion`](https://neovim.io/doc/user/helptag.html?tag=cmdline-completion) and manual [`:h 'wildchar'`](https://neovim.io/doc/user/helptag.html?tag='wildchar') pressing experience. Requires Neovim>=0.11, though Neovim>=0.12 is recommended.

- Autocorrect words as-you-type. Only words that must come from a fixed set of candidates (like commands and options) are autocorrected by default.

- Autopeek command range as-you-type. Shows a floating window with range lines along with customizable context lines.

What it doesn't do:

- Customization of command line UI. Use [`:h vim._extui`](https://neovim.io/doc/user/helptag.html?tag=vim._extui) (on Neovim>=0.12).

- Customization of autocompletion candidates. They are computed via [`:h cmdline-completion`](https://neovim.io/doc/user/helptag.html?tag=cmdline-completion).

## Installation

This plugin can be installed as part of 'mini.nvim' library (**recommended**) or as a standalone Git repository.

During beta-testing phase there is only one branch to install from:

- `main` (default, **recommended**) will have latest development version of plugin.
<!-- - `main` (default, **recommended**) will have latest development version of plugin. All changes since last stable release should be perceived as being in beta testing phase (meaning they already passed alpha-testing and are moderately settled). -->
<!-- - `stable` will be updated only upon releases with code tested during public beta-testing phase in `main` branch. -->

Here are code snippets for some common installation methods (use only one):

<details>
<summary>With <a href="https://nvim-mini.org/mini.nvim/readmes/mini-deps">mini.deps</a></summary>

- 'mini.nvim' library:

    | Branch | Code snippet                                  |
    |--------|-----------------------------------------------|
    | Main   | *Follow recommended ‘mini.deps’ installation* |
    <!-- | Stable | *Follow recommended ‘mini.deps’ installation* | -->

- Standalone plugin:

    | Branch | Code snippet                                                     |
    |--------|------------------------------------------------------------------|
    | Main   | `add(‘nvim-mini/mini.cmdline’)`                                   |
    <!-- | Stable | `add({ source = ‘nvim-mini/mini.cmdline’, checkout = ‘stable’ })` | -->

</details>

<details>
<summary>With <a href="https://github.com/folke/lazy.nvim">folke/lazy.nvim</a></summary>

- 'mini.nvim' library:

    | Branch | Code snippet                                  |
    |--------|-----------------------------------------------|
    | Main   | `{ 'nvim-mini/mini.nvim', version = false },` |
    <!-- | Stable | `{ 'nvim-mini/mini.nvim', version = '*' },`   | -->

- Standalone plugin:

    | Branch | Code snippet                                    |
    |--------|-------------------------------------------------|
    | Main   | `{ 'nvim-mini/mini.cmdline', version = false },` |
    <!-- | Stable | `{ 'nvim-mini/mini.cmdline', version = '*' },`   | -->

</details>

<details>
<summary>With <a href="https://github.com/junegunn/vim-plug">junegunn/vim-plug</a></summary>

- 'mini.nvim' library:

    | Branch | Code snippet                                         |
    |--------|------------------------------------------------------|
    | Main   | `Plug 'nvim-mini/mini.nvim'`                         |
    <!-- | Stable | `Plug 'nvim-mini/mini.nvim', { 'branch': 'stable' }` | -->

- Standalone plugin:

    | Branch | Code snippet                                           |
    |--------|--------------------------------------------------------|
    | Main   | `Plug 'nvim-mini/mini.cmdline'`                         |
    <!-- | Stable | `Plug 'nvim-mini/mini.cmdline', { 'branch': 'stable' }` | -->

</details>

**Important**: no need to call `require('mini.cmdline').setup()`, but it can be done to improve usability.

**Note**: if you are on Windows, there might be problems with too long file paths (like `error: unable to create file <some file name>: Filename too long`). Try doing one of the following:

- Enable corresponding git global config value: `git config --system core.longpaths true`. Then try to reinstall.
- Install plugin in other place with shorter path.

## Default config

```lua
-- No need to copy this inside `setup()`. Will be used automatically.
{
  -- Autocompletion: show `:h 'wildmenu'` as you type
  autocomplete = {
    enable = true,

    -- Delay (in ms) after which to trigger completion
    -- Neovim>=0.12 is recommended for positive values
    delay = 0,

    -- Custom rule of when to trigger completion
    predicate = nil,

    -- Whether to map arrow keys for more consistent wildmenu behavior
    map_arrows = true,
  },

  -- Autocorrection: adjust non-existing words (commands, options, etc.)
  autocorrect = {
    enable = true,

    -- Custom autocorrection rule
    func = nil,
  },

  -- Autopeek: show command's target range in a floating window
  autopeek = {
    enable = true,

    -- Number of lines to show above and below range lines
    n_context = 1,

    -- Window options
    window = {
      -- Floating window config
      config = {},

      -- Function to render statuscolumn
      statuscolumn = nil,
    },
  },
}
```

## Similar plugins

- [folke/noice.nvim](https://github.com/folke/noice.nvim)
- [nacro90/numb.nvim](https://github.com/nacro90/numb.nvim)
- Built-in [cmdline-autocompletion](https://neovim.io/doc/user/helptag.html?tag=cmdline-autocompletion) (on Neovim>=0.12):
