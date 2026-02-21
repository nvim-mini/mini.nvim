<p align="center"> <img src="https://github.com/nvim-mini/assets/blob/main/logo-2/logo-git_readme.png?raw=true" alt="mini.git" style="max-width:100%;border:solid 2px"/> </p>

### Git integration

See more details in [Features](#features) and [Documentation](../doc/mini-git.txt).

---

> [!NOTE]
> This was previously hosted at a personal `echasnovski` GitHub account. It was transferred to a dedicated organization to improve long term project stability. See more details [here](https://github.com/nvim-mini/mini.nvim/discussions/1970).

⦿ This is a part of [mini.nvim](https://nvim-mini.org/mini.nvim) library. Please use [this link](https://nvim-mini.org/mini.nvim/readmes/mini-git) if you want to mention this module.

⦿ All contributions (issues, pull requests, discussions, etc.) are done inside of 'mini.nvim'.

⦿ See [whole library documentation](https://nvim-mini.org/mini.nvim/doc/mini-nvim) to learn about general design principles, disable/configuration recipes, and more.

⦿ See [MiniMax](https://nvim-mini.org/MiniMax) for a full config example that uses this module.

---

If you want to help this project grow but don't know where to start, check out [contributing guides of 'mini.nvim'](https://nvim-mini.org/mini.nvim/CONTRIBUTING) or leave a Github star for 'mini.nvim' project and/or any its standalone Git repositories.

## Demo

<!-- Demo source: https://github.com/nvim-mini/assets/blob/main/demo/demo-git.mp4 -->
https://github.com/nvim-mini/mini.nvim/assets/24854248/3c2b34cd-f04f-4e30-9ca4-1ff51e2d65a2

**Note**: This demo uses custom `vim.notify()` from [mini.notify](https://nvim-mini.org/mini.nvim/readmes/mini-notify) and diff line number highlighting from [mini.diff](https://nvim-mini.org/mini.nvim/readmes/mini-diff).

## Features

- Automated tracking of [Git](https://git-scm.com/) related data: root path, status, HEAD, etc. Exposes buffer-local variables for convenient use in statusline.

- `:Git` command for executing any `git` call inside file's repository root with deeper current instance integration (show output as notification/buffer, use to edit commit messages, etc.).

- Helper functions to inspect Git history:
    - `MiniGit.show_range_history()` shows how certain line range evolved.
    - `MiniGit.show_diff_source()` shows file state as it was at diff entry.
    - `MiniGit.show_at_cursor()` shows Git related data depending on context.

What it doesn't do:

- Replace fully featured Git client. Rule of thumb: if feature does not rely on a state of current Neovim (opened buffers, etc.), it is out of scope. For more functionality, use either ['mini.diff'](https://nvim-mini.org/mini.nvim/readmes/mini-diff) or fully featured Git client.

For more information see these parts of help:

- `:h :Git`
- `:h MiniGit-examples`
- `:h MiniGit.enable()`
- `:h MiniGit.get_buf_data()`

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

    | Branch | Code snippet                                                  |
    |--------|---------------------------------------------------------------|
    | Main   | `add('nvim-mini/mini-git')`                                   |
    | Stable | `add({ source = 'nvim-mini/mini-git', checkout = 'stable' })` |

</details>

<details>
<summary>With <a href="https://github.com/folke/lazy.nvim">folke/lazy.nvim</a></summary>

- 'mini.nvim' library:

    | Branch | Code snippet                                  |
    |--------|-----------------------------------------------|
    | Main   | `{ 'nvim-mini/mini.nvim', version = false },` |
    | Stable | `{ 'nvim-mini/mini.nvim', version = '*' },`   |

- Standalone plugin:

    | Branch | Code snippet                                 |
    |--------|----------------------------------------------|
    | Main   | `{ 'nvim-mini/mini-git', version = false },` |
    | Stable | `{ 'nvim-mini/mini-git', version = '*' },`   |

</details>

<details>
<summary>With <a href="https://github.com/junegunn/vim-plug">junegunn/vim-plug</a></summary>

- 'mini.nvim' library:

    | Branch | Code snippet                                         |
    |--------|------------------------------------------------------|
    | Main   | `Plug 'nvim-mini/mini.nvim'`                         |
    | Stable | `Plug 'nvim-mini/mini.nvim', { 'branch': 'stable' }` |

- Standalone plugin:

    | Branch | Code snippet                                        |
    |--------|-----------------------------------------------------|
    | Main   | `Plug 'nvim-mini/mini-git'`                         |
    | Stable | `Plug 'nvim-mini/mini-git', { 'branch': 'stable' }` |

</details>

**Important**: don't forget to call `require('mini.git').setup()` to enable its functionality.

**Note**: if you are on Windows, there might be problems with too long file paths (like `error: unable to create file <some file name>: Filename too long`). Try doing one of the following:

- Enable corresponding git global config value: `git config --system core.longpaths true`. Then try to reinstall.
- Install plugin in other place with shorter path.

## Default config

```lua
-- No need to copy this inside `setup()`. Will be used automatically.
{
  -- General CLI execution
  job = {
    -- Path to Git executable
    git_executable = 'git',

    -- Timeout (in ms) for each job before force quit
    timeout = 30000,
  },

  -- Options for `:Git` command
  command = {
    -- Default split direction
    split = 'auto',
  },
}
```

## Similar plugins

- [tpope/vim-fugitive](https://github.com/tpope/vim-fugitive)
- [NeogitOrg/neogit](https://github.com/NeogitOrg/neogit)
- [lewis6991/gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim)
