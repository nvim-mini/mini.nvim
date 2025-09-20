<p align="center"> <img src="https://github.com/nvim-mini/assets/blob/main/logo-2/logo-deps_readme.png?raw=true" alt="mini.deps"/> </p>

### Plugin manager

Depends on [`git`](https://git-scm.com/) CLI tool being installed and callable. Make sure to have it set up.

See more details in [Features](#features) and [help file](../doc/mini-deps.txt).

---

> [!NOTE]
> This was previously hosted at a personal `echasnovski` GitHub account. It was transferred to a dedicated organization to improve long term project stability. See more details [here](https://github.com/nvim-mini/mini.nvim/discussions/1970).

⦿ This is a part of [mini.nvim](https://github.com/nvim-mini/mini.nvim) library. Please use [this link](https://github.com/nvim-mini/mini.nvim/blob/main/readmes/mini-deps.md) if you want to mention this module.

⦿ All contributions (issues, pull requests, discussions, etc.) are done inside of 'mini.nvim'.

⦿ See the repository page to learn about common design principles and configuration recipes.

---

If you want to help this project grow but don't know where to start, check out [contributing guides of 'mini.nvim'](https://github.com/nvim-mini/mini.nvim/blob/main/CONTRIBUTING.md) or leave a Github star for 'mini.nvim' project and/or any its standalone Git repositories.

## Demo

<!-- Demo source: https://github.com/nvim-mini/assets/blob/main/demo/demo-deps.mp4 -->
https://github.com/nvim-mini/mini.nvim/assets/24854248/e3b0659b-ce79-4464-8601-e0117f38569f

**Note**: This demo features custom `vim.notify()` from [mini.notify](https://github.com/nvim-mini/mini.nvim/blob/main/readmes/mini-notify.md).

## Features

- Manage plugins utilizing Git and built-in packages with these actions:
    - Add plugin to current session, download if absent.
    - Update with/without confirm, with/without parallel download of new data.
    - Delete unused plugins with/without confirm.
    - Get / set / save / load snapshot.

- Minimal yet flexible plugin specification:
    - Plugin source.
    - Name of target plugin directory.
    - Checkout target: branch, commit, tag, etc.
    - Monitor branch to track updates without checking out.
    - Dependencies to be set up prior to the target plugin.
    - Hooks to call before/after plugin is created/changed.

- Helpers implementing two-stage startup: `now()` and `later()`.

Read more information, see these tags in help file:
- `*MiniDeps-overview*`
- `*MiniDeps-plugin-specification*`
- `*MiniDeps-commands*`

## Installation

This plugin can be installed as part of 'mini.nvim' library (**recommended**) or as a standalone Git repository.

Installation should be done manually with `git clone` in the proper directory. Here is a suggested snippet to put at the top of your 'init.lua':

```lua
-- Clone 'mini.nvim' manually in a way that it gets managed by 'mini.deps'
local path_package = vim.fn.stdpath('data') .. '/site/'
local mini_path = path_package .. 'pack/deps/start/mini.nvim'
if not vim.loop.fs_stat(mini_path) then
  vim.cmd('echo "Installing `mini.nvim`" | redraw')
  local clone_cmd = {
    'git', 'clone', '--filter=blob:none',
    'https://github.com/nvim-mini/mini.nvim', mini_path
  }
  vim.fn.system(clone_cmd)
  vim.cmd('packadd mini.nvim | helptags ALL')
  vim.cmd('echo "Installed `mini.nvim`" | redraw')
end

-- Set up 'mini.deps' (customize to your liking)
require('mini.deps').setup({ path = { package = path_package } })
```

Using default 'main' branch is OK, as changes there rarely accidentally break something (so far). However, if you want to be extra safe and use only stable releases of 'mini.nvim', add `MiniDeps.add({ name = 'mini.nvim', checkout = 'stable' })` call after 'mini.deps' is set up and execute `:DepsUpdateOffline mini.nvim`.

To install from standalone repository, replace any occurrence of 'mini.nvim' in the code snippet to 'mini.deps'.

**NOTE**: 'mini.nvim' is installed in 'pack/deps/start' and not 'pack/deps/opt' to always be included in 'mini.deps' session. If you want to make it "opt" plugin (as any other installed plugin), use 'pack/deps/opt' but add `MiniDeps.add('mini.nvim')` call after 'mini.deps' is set up.

## Overview

See and use [example 'init.lua' file](../scripts/init-deps-example.lua) as a quick demo of how 'mini.deps' can be used:
- Copy its contents into a '~/.config/nvim-deps/init.lua' file (on UNIX systems).
- Run `NVIM_APPNAME=nvim-deps nvim -- ~/.config/nvim-deps/init.lua` (on Neovim<0.10 might display tree-sitter issues on first start). This will run Neovim with that 'init.lua' as the only config **while completely not affecting your current config**.

### Directory structure

This module uses built-in packages to make plugins usable in current session. It works with "pack/deps" package inside `config.path.package` directory.

By default "opt" subdirectory is used to install optional plugins which are loaded on demand with `MiniDeps.add()`.
Non-optional plugins in "start" subdirectory are supported but only if moved there manually after initial install.

### Add plugin

Use `MiniDeps.add()` to add plugin to current session. Supply plugin's URL source as a string or plugin specification in general. If plugin is not present in "pack/deps" package, it will be created (a.k.a. installed) before processing anything else.

The recommended way of adding a plugin is by calling `MiniDeps.add()` in the 'init.lua' file (make sure `MiniDeps.setup()` is called prior):

```lua
local add = MiniDeps.add

-- Add to current session (install if absent)
add({
  source = 'neovim/nvim-lspconfig',
  -- Supply dependencies near target plugin
  depends = { 'williamboman/mason.nvim' },
})

add({
  source = 'nvim-treesitter/nvim-treesitter',
  -- Use 'master' while monitoring updates in 'main'
  checkout = 'master',
  monitor = 'main',
  -- Perform action after every checkout
  hooks = { post_checkout = function() vim.cmd('TSUpdate') end },
})
-- Possible to immediately execute code which depends on the added plugin
require('nvim-treesitter.configs').setup({
  ensure_installed = { 'lua', 'vimdoc' },
  highlight = { enable = true },
})
```

NOTE:
- To increase performance, `add()` only ensures presence on disk and nothing else. In particular, it doesn't ensure `opts.checkout` state. Update or modify plugin state explicitly (see later sections).

### Plugin specification

Specification can be a single string which is inferred as:
- Plugin `name` if it doesn't contain "/".
- Plugin `source` otherwise.

Primarily, specification is a table with the following fields (see `*MiniDeps-plugin-specification*` tag in help for more details):

| Field      | Description                  |
|------------|------------------------------|
| `source`   | URI of plugin source         |
| `name`     | Name to be used on disk      |
| `checkout` | Target state                 |
| `monitor`  | Monitor branch               |
| `depends`  | Array of plugin dependencies |
| `hooks`    | Table with hooks             |

### Lazy loading

Any lazy-loading is assumed to be done manually by calling `MiniDeps.add()` at appropriate time. This module provides helpers implementing special safe two-stage loading:
- `MiniDeps.now()` safely executes code immediately. Use it to load plugins with UI necessary to make initial screen draw.
- `MiniDeps.later()` schedules code to be safely executed later, preserving order. Use it (with caution) for everything else which doesn't need precisely timed effect, as it will be executed some time soon on one of the next event loops.

```lua
local now, later = MiniDeps.now, MiniDeps.later

-- Safely execute immediately
now(function() vim.cmd('colorscheme miniwinter') end)
now(function() require('mini.statusline').setup() end)

-- Safely execute later
later(function() require('mini.pick').setup() end)
```

### Update

To update plugins from current session with new data from their sources, use `:DepsUpdate`. This will download updates (utilizing multiple cores) and show confirmation buffer. Follow instructions at its top to finish an update.

NOTE: This updates plugins on disk which most likely won't affect current session. Restart Nvim to have them properly loaded.

### Modify

To change plugin's specification (like set different `checkout`, etc.):
- Update corresponding `MiniDeps.add()` call.
- Run `:DepsUpdateOffline <plugin_name>`.
- Review changes and confirm.
- Restart Nvim.

NOTE: if `add()` prior used a single source string, make sure to convert its argument to `{ source = '<previous_argument>', checkout = '<state>'}`

### Snapshots

Use `:DepsSnapSave` to save state of all plugins from current session into a snapshot file (see `config.path.snapshot`).

Use `:DepsSnapLoad` to load snapshot. This will change (without confirmation) state on disk. Plugins present in both snapshot file and current session will be affected. Restart Nvim to see the effect.

NOTE: loading snapshot does not change plugin's specification defined inside `MiniDeps.add()` call. This means that next update might change plugin's state. To make it permanent, freeze plugin in target state manually.

### Freeze

Modify plugin's specification to have `checkout` pointing to a static target: tag, state (commit hash), or 'HEAD' (to freeze in current state).

Frozen plugins will not receive updates. You can monitor any new changes from its source by "subscribing" to `monitor` branch which will be shown inside confirmation buffer after `:DepsUpdate`.

Example: use `checkout = 'v0.10.0'` to freeze plugin at tag "v0.10.0" while monitoring new versions in the log from `monitor` (usually default) branch.

### Rollback

To roll back after an unfortunate update:
- Get identifier of latest working state:
    - Use `:DepsShowLog` to see update log, look for plugin's name, and copy
      identifier listed as "State before:".
    - See previously saved snapshot file for plugin's name and copy
      identifier next to it.
- Freeze plugin at that state while monitoring appropriate branch.
  Revert to previous shape of `MiniDeps.add()` call to resume updating.

### Remove

- Make sure that target plugin is not registered in current session.
  Usually it means removing corresponding `MiniDeps.add()` call.
- Run `:DepsClean`. This will show confirmation buffer with a list of plugins to
  be deleted from disk. Follow instructions at its top to finish cleaning.

Alternatively, manually delete plugin's directory from "pack/deps" package.

## Default config

```lua
-- No need to copy this inside `setup()`. Will be used automatically.
{
  -- Parameters of CLI jobs
  job = {
    -- Number of parallel threads to use. Default: 80% of all available.
    n_threads = nil,

    -- Timeout (in ms) for each job before force quit
    timeout = 30000,
  },

  -- Paths describing where to store data
  path = {
    -- Directory for built-in package.
    -- All plugins are actually stored in 'pack/deps' subdirectory.
    package = vim.fn.stdpath('data') .. '/site',

    -- Default file path for a snapshot
    snapshot = vim.fn.stdpath('config') .. '/mini-deps-snap',

    -- Log file
    log = vim.fn.stdpath('log') .. '/mini-deps.log'
  },

  -- Whether to disable showing non-error feedback
  silent = false,
}
```

## Similar plugins

- [folke/lazy.nvim](https://github.com/folke/lazy.nvim)
- [savq/paq-nvim](https://github.com/savq/paq-nvim)
- [junegunn/vim-plug](https://github.com/junegunn/vim-plug)
