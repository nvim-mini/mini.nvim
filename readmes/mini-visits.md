<p align="center"> <img src="https://github.com/nvim-mini/assets/blob/main/logo-2/logo-visits_readme.png?raw=true" alt="mini.visits" style="max-width:100%;border:solid 2px"/> </p>

### Track and reuse file system visits

See more details in [Features](#features) and [Documentation](../doc/mini-visits.txt).

---

> [!NOTE]
> This was previously hosted at a personal `echasnovski` GitHub account. It was transferred to a dedicated organization to improve long term project stability. See more details [here](https://github.com/nvim-mini/mini.nvim/discussions/1970).

⦿ This is a part of [mini.nvim](https://nvim-mini.org/mini.nvim) library. Please use [this link](https://nvim-mini.org/mini.nvim/readmes/mini-visits) if you want to mention this module.

⦿ All contributions (issues, pull requests, discussions, etc.) are done inside of 'mini.nvim'.

⦿ See [whole library documentation](https://nvim-mini.org/mini.nvim/doc/mini-nvim) to learn about general design principles, disable/configuration recipes, and more.

⦿ See [MiniMax](https://nvim-mini.org/MiniMax) for a full config example that uses this module.

---

If you want to help this project grow but don't know where to start, check out [contributing guides of 'mini.nvim'](https://nvim-mini.org/mini.nvim/CONTRIBUTING) or leave a Github star for 'mini.nvim' project and/or any its standalone Git repositories.

## Demo

<!-- Demo source: https://github.com/nvim-mini/assets/blob/main/demo/demo-visits.mp4 -->
https://github.com/nvim-mini/mini.nvim/assets/24854248/ad8ff054-9b95-4e9c-84b1-b39ddba9d7d3

**Note**: This demo uses custom `vim.ui.select()` from [mini.pick](https://nvim-mini.org/mini.nvim/readmes/mini-pick).

## Features

- Persistently track file system visits (both files and directories) per project directory. Store visit index is human readable and editable.

- Visit index is normalized on every write to contain relevant information. Exact details can be customized. See `:h MiniVisits.normalize()`.

- Built-in ability to persistently use label paths for later use. See `:h MiniVisits.add_label()` and `:h MiniVisits.remove_label()`.

- Exported functions to reuse visit data:
    - List visited paths/labels with custom filter and sort (uses "robust frecency" by default). Can be used as source for pickers.

      See `:h MiniVisits.list_paths()` and `:h MiniVisits.list_labels()`. See `:h MiniVisits.gen_filter` and `:h MiniVisits.gen_sort`.

    - Select visited paths/labels using `vim.ui.select()`.

      See `:h MiniVisits.select_path()` and `:h MiniVisits.select_label()`.

    - Iterate through visit paths in target direction ("forward", "backward", "first", "last"). See `:h MiniVisits.iterate_paths()`.

- Exported functions to manually update visit index allowing persistent track of any user information. See `*_index()` functions.

Notes:

- All data is stored _only_ in in-session Lua variable (for quick operation) and at `config.store.path` on disk (for persistent usage).

- It doesn't account for paths being renamed or moved (because there is no general way to detect that). Usually a manual intervention to the visit index is required after the change but _before_ the next writing to disk (usually before closing current session) because it will treat previous path as deleted and remove it from index.

    There is a `MiniVisits.rename_in_index()` helper for that.
    If rename/move is done with ['mini.files'](https://nvim-mini.org/mini.nvim/readmes/mini-files), index is autoupdated.

For more information see these parts of help:

- `:h MiniVisits-overview`
- `:h MiniVisits-index-specification`
- `:h MiniVisits-examples`

## Overview

### Tracking visits

File system visits (both directory and files) tracking is done in two steps:

- On every dedicated event timer is (re)started to actually register visit after certain amount of time.

- When delay time passes without any dedicated events being triggered (meaning user is "settled" on certain buffer), visit is registered if all of the following conditions are met:
    - Module is not disabled.
    - Buffer is normal with non-empty name (used as visit path).
    - Visit path does not equal to the latest tracked one.

Visit is autoregistered for current directory and leads to increase of count
and latest time of visit. See `:h MiniVisits-index-specification` for more details.

Notes:

- All data is stored _only_ in in-session Lua variable (for quick operation) and in one place on disk (for persistent usage). It is automatically written to disk before every Neovim exit.

- Tracking can be disabled by supplying empty string as `track.event`. Then it is up to the user to properly call `MiniVisits.register_visit()`.

### Reusing visits

Visit data can be reused in at least these ways:

- Get a list of visited paths and use it to visualize/pick/navigate visit history.

- Select one of the visited paths to open it.

- Move along visit history.

- Utilize labels. Any visit can be added one or more labels (like "core", "tmp", etc.). They are bound to the visit and are stored persistently.

    Labels can be used to manually create groups of files and/or directories that have particular interest to the user.

    There is no one right way to use them, though. See `:h MiniVisits-examples` for some inspiration.

- Utilizing custom data. Visit index can be manipulated manually using
  `_index()` set of functions. All "storable" user data inside index is then stored on disk, so it can be used to create any kind of workflow user wants.

See `:h MiniVisits-examples` for some actual configuration and workflow examples.

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

    | Branch | Code snippet                                                     |
    |--------|------------------------------------------------------------------|
    | Main   | `add('nvim-mini/mini.visits')`                                   |
    | Stable | `add({ source = 'nvim-mini/mini.visits', checkout = 'stable' })` |

</details>

<details>
<summary>With <a href="https://github.com/folke/lazy.nvim">folke/lazy.nvim</a></summary>

- 'mini.nvim' library:

    | Branch | Code snippet                                  |
    |--------|-----------------------------------------------|
    | Main   | `{ 'nvim-mini/mini.nvim', version = false },` |
    | Stable | `{ 'nvim-mini/mini.nvim', version = '*' },`   |

- Standalone plugin:

    | Branch | Code snippet                                    |
    |--------|-------------------------------------------------|
    | Main   | `{ 'nvim-mini/mini.visits', version = false },` |
    | Stable | `{ 'nvim-mini/mini.visits', version = '*' },`   |

</details>

<details>
<summary>With <a href="https://github.com/junegunn/vim-plug">junegunn/vim-plug</a></summary>

- 'mini.nvim' library:

    | Branch | Code snippet                                         |
    |--------|------------------------------------------------------|
    | Main   | `Plug 'nvim-mini/mini.nvim'`                         |
    | Stable | `Plug 'nvim-mini/mini.nvim', { 'branch': 'stable' }` |

- Standalone plugin:

    | Branch | Code snippet                                           |
    |--------|--------------------------------------------------------|
    | Main   | `Plug 'nvim-mini/mini.visits'`                         |
    | Stable | `Plug 'nvim-mini/mini.visits', { 'branch': 'stable' }` |

</details>

**Important**: don't forget to call `require('mini.visits').setup()` to enable its functionality.

**Note**: if you are on Windows, there might be problems with too long file paths (like `error: unable to create file <some file name>: Filename too long`). Try doing one of the following:

- Enable corresponding git global config value: `git config --system core.longpaths true`. Then try to reinstall.
- Install plugin in other place with shorter path.

## Default config

```lua
-- No need to copy this inside `setup()`. Will be used automatically.
{
  -- How visit index is converted to list of paths
  list = {
    -- Predicate for which paths to include (all by default)
    filter = nil,

    -- Sort paths based on the visit data (robust frecency by default)
    sort = nil,
  },

  -- Whether to disable showing non-error feedback
  silent = false,

  -- How visit index is stored
  store = {
    -- Whether to write all visits before Neovim is closed
    autowrite = true,

    -- Function to ensure that written index is relevant
    normalize = nil,

    -- Path to store visit index
    path = vim.fn.stdpath('data') .. '/mini-visits-index',
  },

  -- How visit tracking is done
  track = {
    -- Start visit register timer at this event
    -- Supply empty string (`''`) to not do this automatically
    event = 'BufEnter',

    -- Debounce delay after event to register a visit
    delay = 1000,
  },
}
```

## Similar plugins

- [nvim-telescope/telescope-frecency.nvim](https://github.com/nvim-telescope/telescope-frecency.nvim)
- [ThePrimeagen/harpoon](https://github.com/ThePrimeagen/harpoon)
