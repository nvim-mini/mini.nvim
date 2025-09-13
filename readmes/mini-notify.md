<div align="center"> <img src="https://github.com/nvim-mini/assets/blob/main/logo-2/logo-notify_readme.png" alt="mini.notify"/> </div>

### Show notifications

See more details in [Features](#features) and [help file](../doc/mini-notify.txt).

---

> [!NOTE]
> This was previously hosted at a personal `echasnovski` GitHub account. It was transferred to a dedicated organization to improve long term project stability. See more details [here](https://github.com/nvim-mini/mini.nvim/discussions/1970).

⦿ This is a part of [mini.nvim](https://github.com/nvim-mini/mini.nvim) library. Please use [this link](https://github.com/nvim-mini/mini.nvim/blob/main/readmes/mini-notify.md) if you want to mention this module.

⦿ All contributions (issues, pull requests, discussions, etc.) are done inside of 'mini.nvim'.

⦿ See the repository page to learn about common design principles and configuration recipes.

---

If you want to help this project grow but don't know where to start, check out [contributing guides of 'mini.nvim'](https://github.com/nvim-mini/mini.nvim/blob/main/CONTRIBUTING.md) or leave a Github star for 'mini.nvim' project and/or any its standalone Git repositories.

## Demo

https://github.com/nvim-mini/mini.nvim/assets/24854248/81014300-3380-4b8c-9ab5-ba09345032d7

## Features

- Show one or more highlighted notifications in a single floating window.

- Manage notifications (add, update, remove, clear).

- Custom `vim.notify()` implementation. To adjust, use `MiniNotify.make_notify()` after calling `setup()`.

- Automated show of LSP progress report.

- Track history which can be accessed with `MiniNotify.get_all()` and shown with `MiniNotify.show_history()`.

## Installation

This plugin can be installed as part of 'mini.nvim' library (**recommended**) or as a standalone Git repository.

There are two branches to install from:

- `main` (default, **recommended**) will have latest development version of plugin. All changes since last stable release should be perceived as being in beta testing phase (meaning they already passed alpha-testing and are moderately settled).
- `stable` will be updated only upon releases with code tested during public beta-testing phase in `main` branch.

Here are code snippets for some common installation methods (use only one):

<details>
<summary>With <a href="https://github.com/nvim-mini/mini.nvim/blob/main/readmes/mini-deps.md">mini.deps</a></summary>
<table>
    <thead>
        <tr>
            <th>Github repo</th> <th>Branch</th> <th>Code snippet</th>
        </tr>
    </thead>
    <tbody>
        <tr>
            <td rowspan=2>'mini.nvim' library</td> <td>Main</td> <td rowspan=2><i>Follow recommended 'mini.deps' installation</i></td>
        </tr>
        <tr>
            <td>Stable</td>
        </tr>
        <tr>
            <td rowspan=2>Standalone plugin</td> <td>Main</td> <td><code>add('nvim-mini/mini.notify')</code></td>
        </tr>
        <tr>
            <td>Stable</td> <td><code>add({ source = 'nvim-mini/mini.notify', checkout = 'stable' })</code></td>
        </tr>
    </tbody>
</table>
</details>

<details>
<summary>With <a href="https://github.com/folke/lazy.nvim">folke/lazy.nvim</a></summary>
<table>
    <thead>
        <tr>
            <th>Github repo</th> <th>Branch</th> <th>Code snippet</th>
        </tr>
    </thead>
    <tbody>
        <tr>
            <td rowspan=2>'mini.nvim' library</td> <td>Main</td> <td><code>{ 'nvim-mini/mini.nvim', version = false },</code></td>
        </tr>
        <tr>
            <td>Stable</td> <td><code>{ 'nvim-mini/mini.nvim', version = '*' },</code></td>
        </tr>
        <tr>
            <td rowspan=2>Standalone plugin</td> <td>Main</td> <td><code>{ 'nvim-mini/mini.notify', version = false },</code></td>
        </tr>
        <tr>
            <td>Stable</td> <td><code>{ 'nvim-mini/mini.notify', version = '*' },</code></td>
        </tr>
    </tbody>
</table>
</details>

<details>
<summary>With <a href="https://github.com/junegunn/vim-plug">junegunn/vim-plug</a></summary>
<table>
    <thead>
        <tr>
            <th>Github repo</th> <th>Branch</th> <th>Code snippet</th>
        </tr>
    </thead>
    <tbody>
        <tr>
            <td rowspan=2>'mini.nvim' library</td> <td>Main</td> <td><code>Plug 'nvim-mini/mini.nvim'</code></td>
        </tr>
        <tr>
            <td>Stable</td> <td><code>Plug 'nvim-mini/mini.nvim', { 'branch': 'stable' }</code></td>
        </tr>
        <tr>
            <td rowspan=2>Standalone plugin</td> <td>Main</td> <td><code>Plug 'nvim-mini/mini.notify'</code></td>
        </tr>
        <tr>
            <td>Stable</td> <td><code>Plug 'nvim-mini/mini.notify', { 'branch': 'stable' }</code></td>
        </tr>
    </tbody>
</table>
</details>

<br>

**Important**: don't forget to call `require('mini.notify').setup()` to enable its functionality.

**Note**: if you are on Windows, there might be problems with too long file paths (like `error: unable to create file <some file name>: Filename too long`). Try doing one of the following:
- Enable corresponding git global config value: `git config --system core.longpaths true`. Then try to reinstall.

## Default config

```lua
-- No need to copy this inside `setup()`. Will be used automatically.
{
  -- Content management
  content = {
    -- Function which formats the notification message
    -- By default prepends message with notification time
    format = nil,

    -- Function which orders notification array from most to least important
    -- By default orders first by level and then by update timestamp
    sort = nil,
  },

  -- Notifications about LSP progress
  lsp_progress = {
    -- Whether to enable showing
    enable = true,

    -- Notification level
    level = 'INFO',

    -- Duration (in ms) of how long last message should be shown
    duration_last = 1000,
  },

  -- Window options
  window = {
    -- Floating window config
    config = {},

    -- Maximum window width as share (between 0 and 1) of available columns
    max_width_share = 0.382,

    -- Value of 'winblend' option
    winblend = 25,
  },
}
```

## Similar plugins

- [j-hui/fidget.nvim](https://github.com/j-hui/fidget.nvim)
- [rcarriga/nvim-notify](https://github.com/rcarriga/nvim-notify)
