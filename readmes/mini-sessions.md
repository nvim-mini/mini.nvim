<p align="center"> <img src="https://github.com/nvim-mini/assets/blob/main/logo-2/logo-sessions_readme.png?raw=true" alt="mini.sessions" style="max-width:100%;border:solid 2px"/> </p>

### Session management (read, write, delete)

See more details in [Features](#features) and [Documentation](../doc/mini-sessions.txt).

---

> [!NOTE]
> This was previously hosted at a personal `echasnovski` GitHub account. It was transferred to a dedicated organization to improve long term project stability. See more details [here](https://github.com/nvim-mini/mini.nvim/discussions/1970).

⦿ This is a part of [mini.nvim](https://nvim-mini.org/mini.nvim) library. Please use [this link](https://nvim-mini.org/mini.nvim/readmes/mini-sessions) if you want to mention this module.

⦿ All contributions (issues, pull requests, discussions, etc.) are done inside of 'mini.nvim'.

⦿ See [whole library documentation](https://nvim-mini.org/mini.nvim/doc/mini-nvim) to learn about general design principles, disable/configuration recipes, and more.

⦿ See [MiniMax](https://nvim-mini.org/MiniMax) for a full config example that uses this module.

---

If you want to help this project grow but don't know where to start, check out [contributing guides of 'mini.nvim'](https://nvim-mini.org/mini.nvim/CONTRIBUTING) or leave a Github star for 'mini.nvim' project and/or any its standalone Git repositories.

## Demo

<!-- Demo source: https://github.com/nvim-mini/assets/blob/main/demo/demo-sessions.mp4 -->
https://user-images.githubusercontent.com/24854248/173045087-3d18affc-c76f-4d22-8afc-fef687166ef0.mp4

## Features

- Works using `:mksession` (`'sessionoptions'` is fully respected).
- Implements both global (from configured directory) and local (from current directory) sessions.
- No automated new session creation. Use `MiniSessions.write()` manually.
- Autoread default session (local if detected, else latest written global) if Neovim was called without intention to show something else.
- Autowrite currently read session before quitting Neovim.
- Configurable severity level of all actions.

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

    | Branch | Code snippet                                                       |
    |--------|--------------------------------------------------------------------|
    | Main   | `add('nvim-mini/mini.sessions')`                                   |
    | Stable | `add({ source = 'nvim-mini/mini.sessions', checkout = 'stable' })` |

</details>

<details>
<summary>With <a href="https://github.com/folke/lazy.nvim">folke/lazy.nvim</a></summary>

- 'mini.nvim' library:

    | Branch | Code snippet                                  |
    |--------|-----------------------------------------------|
    | Main   | `{ 'nvim-mini/mini.nvim', version = false },` |
    | Stable | `{ 'nvim-mini/mini.nvim', version = '*' },`   |

- Standalone plugin:

    | Branch | Code snippet                                      |
    |--------|---------------------------------------------------|
    | Main   | `{ 'nvim-mini/mini.sessions', version = false },` |
    | Stable | `{ 'nvim-mini/mini.sessions', version = '*' },`   |

</details>

<details>
<summary>With <a href="https://github.com/junegunn/vim-plug">junegunn/vim-plug</a></summary>

- 'mini.nvim' library:

    | Branch | Code snippet                                         |
    |--------|------------------------------------------------------|
    | Main   | `Plug 'nvim-mini/mini.nvim'`                         |
    | Stable | `Plug 'nvim-mini/mini.nvim', { 'branch': 'stable' }` |

- Standalone plugin:

    | Branch | Code snippet                                             |
    |--------|----------------------------------------------------------|
    | Main   | `Plug 'nvim-mini/mini.sessions'`                         |
    | Stable | `Plug 'nvim-mini/mini.sessions', { 'branch': 'stable' }` |

</details>

**Important**: don't forget to call `require('mini.sessions').setup()` to enable its functionality.

**Note**: if you are on Windows, there might be problems with too long file paths (like `error: unable to create file <some file name>: Filename too long`). Try doing one of the following:

- Enable corresponding git global config value: `git config --system core.longpaths true`. Then try to reinstall.
- Install plugin in other place with shorter path.

## Default config

```lua
-- No need to copy this inside `setup()`. Will be used automatically.
{
  -- Whether to read default session if Neovim opened without file arguments
  autoread = false,

  -- Whether to write currently read session before leaving it
  autowrite = true,

  -- Directory where global sessions are stored (use `''` to disable)
  directory = --<"session" subdir of user data directory from |stdpath()|>,

  -- File for local session (use `''` to disable)
  file = 'Session.vim',

  -- Whether to force possibly harmful actions (meaning depends on function)
  force = { read = false, write = true, delete = false },

  -- Hook functions for actions. Default `nil` means 'do nothing'.
  hooks = {
    -- Before successful action
    pre = { read = nil, write = nil, delete = nil },
    -- After successful action
    post = { read = nil, write = nil, delete = nil },
  },

  -- Whether to print session path after action
  verbose = { read = false, write = true, delete = true },
}
```

## Similar plugins

- [mhinz/vim-startify](https://github.com/mhinz/vim-startify)
- [Shatur/neovim-session-manager](https://github.com/Shatur/neovim-session-manager)
