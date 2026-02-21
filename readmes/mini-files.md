<p align="center"> <img src="https://github.com/nvim-mini/assets/blob/main/logo-2/logo-files_readme.png?raw=true" alt="mini.files" style="max-width:100%;border:solid 2px"/> </p>

### Navigate and manipulate file system

See more details in [Features](#features) and [Documentation](../doc/mini-files.txt).

---

> [!NOTE]
> This was previously hosted at a personal `echasnovski` GitHub account. It was transferred to a dedicated organization to improve long term project stability. See more details [here](https://github.com/nvim-mini/mini.nvim/discussions/1970).

⦿ This is a part of [mini.nvim](https://nvim-mini.org/mini.nvim) library. Please use [this link](https://nvim-mini.org/mini.nvim/readmes/mini-files) if you want to mention this module.

⦿ All contributions (issues, pull requests, discussions, etc.) are done inside of 'mini.nvim'.

⦿ See [whole library documentation](https://nvim-mini.org/mini.nvim/doc/mini-nvim) to learn about general design principles, disable/configuration recipes, and more.

⦿ See [MiniMax](https://nvim-mini.org/MiniMax) for a full config example that uses this module.

---

If you want to help this project grow but don't know where to start, check out [contributing guides of 'mini.nvim'](https://nvim-mini.org/mini.nvim/CONTRIBUTING) or leave a Github star for 'mini.nvim' project and/or any its standalone Git repositories.

## Demo

<!-- Demo source: https://github.com/nvim-mini/assets/blob/main/demo/demo-files.mp4 -->
https://github.com/nvim-mini/mini.nvim/assets/24854248/530483a5-fe9a-4e18-9813-a6d609fc89ff

## Features

- Navigate file system using column view (Miller columns) to display nested directories. See `:h MiniFiles-navigation` for overview.

- Opt-in preview of file or directory under cursor.

- Manipulate files and directories by editing text buffers: create, delete, copy, rename, move. See `:h MiniFiles-manipulation` for overview.

- Use as default file explorer instead of `netrw`.

- Configurable:
    - Filter/prefix/sort of file system entries.
    - Mappings used for common explorer actions.
    - UI options: whether to show preview of file/directory under cursor, etc.
    - Bookmarks for quicker navigation.

See `:h MiniFiles-examples` for some common configuration examples.

Notes:

- This module is written and thoroughly tested on Linux. Support for other platform/OS (like Windows or MacOS) is a goal, but there is no guarantee.

- This module silently reacts to not enough permissions:
    - In case of missing file, check its or its parent read permissions.
    - In case of no manipulation result, check write permissions.

## Dependencies

For full experience needs (still works without any of suggestions):

- Enabled ['mini.icons'](https://nvim-mini.org/mini.nvim/readmes/mini-icons) module to show icons near file/directory names. Can fall back to using [nvim-tree/nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons) plugin.

## Quick start

### Navigation

- Run `:lua MiniFiles.open()`.

- Navigate:
    - Press `j`/`k` to navigate down/up.
    - Press `l` to expand entry under cursor: show directory or open file in the most recent window.
    - Press `h` to go to parent directory.
    - Type `m<char>` to set directory path of focused window as bookmark `<char>`. Jump to it with `'<char>`. Go back to before the latest jump with `''`.
    - Type `g?` for more information about other available mappings and bookmarks.
    - Move as in any other buffer (`$`, `G`, `f`/`t`, etc.).

For deeper overview, see `:h MiniFiles-navigation`.

### Manipulation

- Navigate to the directory in which manipulation should be done.

- Edit buffer in the way representing file system action:
    - **Create file/directory**: create new line like `file` or `dir/`.
    - **Create file/directory in the descendant directory**: create new line like `dir/file` or `dir/nested/`.
    - **Delete file/directory**: delete whole line representing that entry.
    - **Rename file/directory**: change text to the right of that entry's icon.
    - **Copy file/directory**: copy whole line and paste it in target directory.
    - **Move file/directory**: cut whole line and paste it in target directory.

- Press `=`; **read confirmation dialog**; confirm with `y`/`<CR>` or not confirm with `n`/`<Esc>`.

For deeper overview, see `:h MiniFiles-manipulation`.

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

    | Branch | Code snippet                                                    |
    |--------|-----------------------------------------------------------------|
    | Main   | `add('nvim-mini/mini.files')`                                   |
    | Stable | `add({ source = 'nvim-mini/mini.files', checkout = 'stable' })` |

</details>

<details>
<summary>With <a href="https://github.com/folke/lazy.nvim">folke/lazy.nvim</a></summary>

- 'mini.nvim' library:

    | Branch | Code snippet                                  |
    |--------|-----------------------------------------------|
    | Main   | `{ 'nvim-mini/mini.nvim', version = false },` |
    | Stable | `{ 'nvim-mini/mini.nvim', version = '*' },`   |

- Standalone plugin:

    | Branch | Code snippet                                   |
    |--------|------------------------------------------------|
    | Main   | `{ 'nvim-mini/mini.files', version = false },` |
    | Stable | `{ 'nvim-mini/mini.files', version = '*' },`   |

</details>

<details>
<summary>With <a href="https://github.com/junegunn/vim-plug">junegunn/vim-plug</a></summary>

- 'mini.nvim' library:

    | Branch | Code snippet                                         |
    |--------|------------------------------------------------------|
    | Main   | `Plug 'nvim-mini/mini.nvim'`                         |
    | Stable | `Plug 'nvim-mini/mini.nvim', { 'branch': 'stable' }` |

- Standalone plugin:

    | Branch | Code snippet                                          |
    |--------|-------------------------------------------------------|
    | Main   | `Plug 'nvim-mini/mini.files'`                         |
    | Stable | `Plug 'nvim-mini/mini.files', { 'branch': 'stable' }` |

</details>

**Important**: don't forget to call `require('mini.files').setup()` to enable its functionality.

**Note**: if you are on Windows, there might be problems with too long file paths (like `error: unable to create file <some file name>: Filename too long`). Try doing one of the following:

- Enable corresponding git global config value: `git config --system core.longpaths true`. Then try to reinstall.
- Install plugin in other place with shorter path.

## Default config

```lua
-- No need to copy this inside `setup()`. Will be used automatically.
{
  -- Customization of shown content
  content = {
    -- Predicate for which file system entries to show
    filter = nil,
    -- Highlight group to use for a file system entry
    highlight = nil,
    -- Prefix text and highlight to show to the left of file system entry
    prefix = nil,
    -- Order in which to show file system entries
    sort = nil,
  },

  -- Module mappings created only inside explorer.
  -- Use `''` (empty string) to not create one.
  mappings = {
    close       = 'q',
    go_in       = 'l',
    go_in_plus  = 'L',
    go_out      = 'h',
    go_out_plus = 'H',
    mark_goto   = "'",
    mark_set    = 'm',
    reset       = '<BS>',
    reveal_cwd  = '@',
    show_help   = 'g?',
    synchronize = '=',
    trim_left   = '<',
    trim_right  = '>',
  },

  -- General options
  options = {
    -- Whether to delete permanently or move into module-specific trash
    permanent_delete = true,
    -- Whether to use for editing directories
    use_as_default_explorer = true,
  },

  -- Customization of explorer windows
  windows = {
    -- Maximum number of windows to show side by side
    max_number = math.huge,
    -- Whether to show preview of file/directory under cursor
    preview = false,
    -- Width of focused window
    width_focus = 50,
    -- Width of non-focused window
    width_nofocus = 15,
    -- Width of preview window
    width_preview = 25,
  },
}
```

## Similar plugins

- [nvim-tree/nvim-tree.lua](https://github.com/nvim-tree/nvim-tree.lua)
- [stevearc/oil.nvim](https://github.com/stevearc/oil.nvim)
- [nvim-neo-tree/neo-tree.nvim](https://github.com/nvim-neo-tree/neo-tree.nvim)
