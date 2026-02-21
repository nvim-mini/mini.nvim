<p align="center"> <img src="https://github.com/nvim-mini/assets/blob/main/logo-2/logo-snippets_readme.png?raw=true" alt="mini.snippets" style="max-width:100%;border:solid 2px"/> </p>

### Manage and expand snippets

See more details in [Features](#features) and [Documentation](../doc/mini-snippets.txt).

---

> [!NOTE]
> This was previously hosted at a personal `echasnovski` GitHub account. It was transferred to a dedicated organization to improve long term project stability. See more details [here](https://github.com/nvim-mini/mini.nvim/discussions/1970).

⦿ This is a part of [mini.nvim](https://nvim-mini.org/mini.nvim) library. Please use [this link](https://nvim-mini.org/mini.nvim/readmes/mini-snippets) if you want to mention this module.

⦿ All contributions (issues, pull requests, discussions, etc.) are done inside of 'mini.nvim'.

⦿ See [whole library documentation](https://nvim-mini.org/mini.nvim/doc/mini-nvim) to learn about general design principles, disable/configuration recipes, and more.

⦿ See [MiniMax](https://nvim-mini.org/MiniMax) for a full config example that uses this module.

---

If you want to help this project grow but don't know where to start, check out [contributing guides of 'mini.nvim'](https://nvim-mini.org/mini.nvim/CONTRIBUTING) or leave a Github star for 'mini.nvim' project and/or any its standalone Git repositories.

## Demo

<!-- Demo source: https://github.com/nvim-mini/assets/blob/main/demo/demo-snippets.mp4 -->
https://github.com/user-attachments/assets/2cb38960-a26c-48ae-83cd-5fbcaa57d1cf

## Features

- Manage snippet collection by adding it explicitly or with a flexible set of performant built-in loaders. See `:h MiniSnippets.gen_loader`.

- Configured snippets are efficiently resolved before every expand based on current local context. This, for example, allows using different snippets in different local tree-sitter languages (like in markdown code blocks). See `:h MiniSnippets.default_prepare()`.

- Match which snippet to insert based on the currently typed text. Supports both exact and fuzzy matching. See `:h MiniSnippets.default_match()`.

- Select from several matched snippets via `vim.ui.select()`. See `:h MiniSnippets.default_select()`.

- Start specialized in-process LSP server to show loaded snippets inside (auto)completion engines (like [mini.completion](https://nvim-mini.org/mini.nvim/readmes/mini-completion)). See `:h MiniSnippets.start_lsp_server()`.

- Insert, jump, and edit during snippet session in a configurable manner:
    - Configurable mappings for jumping and stopping.
    - Jumping wraps around the tabstops for easier navigation.
    - Easy to reason rules for when session automatically stops.
    - Text synchronization of linked tabstops preserving relative indent.
    - Dynamic tabstop state visualization (current/visited/unvisited, etc.)
    - Inline visualization of empty tabstops (requires Neovim>=0.10).
    - Works inside comments by preserving comment leader on new lines.
    - Supports nested sessions (expand snippet while there is an active one).

    See `:h MiniSnippets.default_insert()`.

- Exported function to parse snippet body into easy-to-reason data structure. See `:h MiniSnippets.parse()`.

Notes:

- It does not set up any snippet collection by default. Explicitly populate `config.snippets` to have snippets to match from.
- It does not come with a built-in snippet collection. It is expected from users to add their own snippets, manually or with dedicated plugin(s).
- It does not support variable/tabstop transformations in default snippet session. This requires ECMAScript Regular Expression parser which can not be implemented concisely.

Sources with more details:

- [Overview](#overview)
- `:h MiniSnippets-glossary`
- `:h MiniSnippets-examples`
- `:h MiniSnippets-in-other-plugins` (for plugin authors)

## Dependencies

This module doesn't come with snippet collection. Either create it manually or install a dedicated plugin. For example, [rafamadriz/friendly-snippets](https://github.com/rafamadriz/friendly-snippets).

## Quickstart

- Use the following setup:

    ```lua
    local gen_loader = require('mini.snippets').gen_loader
    require('mini.snippets').setup({
      snippets = {
        -- Load custom file with global snippets first (adjust for Windows)
        gen_loader.from_file('~/.config/nvim/snippets/global.json'),

        -- Load snippets based on current language by reading files from
        -- "snippets/" subdirectories from 'runtimepath' directories.
        gen_loader.from_lang(),
      },
    })
    ```

    This setup allows having single file with custom "global" snippets (will be present in every buffer) and snippets which will be loaded based on the local language (see `:h MiniSnippets.gen_loader.from_lang()`).

    Create language snippets manually (like by creating and populating '`$XDG_CONFIG_HOME`/nvim/snippets/lua.json' file) or by installing dedicated snippet collection plugin (like [rafamadriz/friendly-snippets](https://github.com/rafamadriz/friendly-snippets)).


    **Note**: all built-in loaders cache their output by default. It means that after a file is first read, changing it won't have effect during current Neovim session. See `:h MiniSnippets.gen_loader` about how to reset cache if necessary.

- Open Neovim in a file with dedicated language (like 'init.lua' from your config) and press `<C-j>`.

The best way to grasp the design of snippet management and expansion is to
try them out yourself. Here are extra steps for a basic demo:

- Create 'snippets/global.json' file in the config directory with the content:

    ```json
    {
      "Basic":        { "prefix": "ba", "body": "T1=$1 T2=$2 T0=$0"         },
      "Placeholders": { "prefix": "pl", "body": "T1=${1:aa}\nT2=${2:<$1>}"  },
      "Choices":      { "prefix": "ch", "body": "T1=${1|a,b|} T2=${2|c,d|}" },
      "Linked":       { "prefix": "li", "body": "T1=$1\n\tT1=$1"            },
      "Variables":    { "prefix": "va", "body": "Runtime: $VIMRUNTIME\n"    },
      "Complex":      {
        "prefix": "co",
        "body": [ "T1=${1:$RANDOM}", "T3=${3:$1_${2:$1}}", "T2=$2" ]
      }
    }
    ```
- Open Neovim. Type each snippet prefix and press `<C-j>` (even if there is still active session). Explore from there.

## Overview

Snippet is a template for a frequently used text. Typical workflow is to type snippet's (configurable) prefix and expand it into a snippet session: add some pre-defined text and allow user to interactively change/add at certain places.

This overview assumes default config for mappings and expand. See `:h MiniSnippets.config` and `:h MiniSnippets-examples` for more details.

### Snippet structure

Snippet consists from three parts:

- `Prefix` - identifier used to match against current text.
- `Body` - actually inserted content with appropriate syntax.
- `Desc` - description in human readable form.

Example: `{ prefix = 'tis', body = 'This is snippet', desc = 'Snip' }`
Typing `tis` and pressing "expand" mapping (`<C-j>` by default) will remove "tis", add "This is snippet", and place cursor at the end in Insert mode.

### Syntax

Inserting just text after typing smaller prefix is already powerful enough. For more flexibility, snippet body can be formatted in a special way to provide extra features. This module implements support for syntax defined in [LSP specification](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.18/specification/#snippet_syntax) (with small deviations).

A quick overview of basic syntax features:

- Tabstops are snippet parts meant for interactive editing at their location. They are denoted as `$1`, `$2`, etc.

  Navigating between them is called "jumping" and is done in numerical order of tabstop identifiers by pressing special keys: `<C-l>` and `<C-h>` to jump to next and previous tabstop respectively.

  Special tabstop `$0` is called "final tabstop": it is used to decide when snippet session is automatically stopped and is visited last during jumping.

  Example: `T1=$1 T2=$2 T0=$0` is expanded as `T1= T2= T0=` with three tabstops.

- Tabstop can have placeholder: a text used if tabstop is not yet edited. Text is preserved if no editing is done. It follows this same syntax, which means it can itself contain tabstops with placeholders (i.e. be nested). Tabstop with placeholder is denoted as `${1:placeholder}` (`$1` is `${1:}`).

  Example: `T1=${1:text} T2=${2:<$1>}` is expanded as `T1=text T2=<text>`; typing `x` at first placeholder results in `T1=x T2=<x>`; jumping once and typing `y` results in `T1=x T2=y`.

- There can be several tabstops with same identifier. They are linked and updated in sync during text editing. Can also have different placeholders; they are forced to be the same as in the first (from left to right) tabstop.

  Example: `T1=${1:text} T1=$1` is expanded as `T1=text T1=text`; typing `x` at first placeholder results in `T1=x T1=x`.

- Tabstop can also have choices: suggestions about tabstop text. It is denoted as `${1|a,b,c|}`. Choices are shown (with `:h ins-completion` like interface) after jumping to tabstop. First choice is used as placeholder.

  Example: `T1=${1|left,right|}` is expanded as `T1=left`.

- Variables can be used to automatically insert text without user interaction. As tabstops, each one can have a placeholder which is used if variable is not defined. There is a special set of variables describing editor state.

  Example: `V1=$TM_FILENAME V2=${NOTDEFINED:placeholder}` is expanded as `V1=current-file-basename V2=placeholder`.

There are several differences LSP specification: not supporting variable transformations, wider set of supported special variables, and couple more. For more details see `:h MiniSnippets-syntax-specification`.

There is a `:h MiniSnippets.parse()` function for programmatically parsing snippet body into a comprehensible data structure.

### Expand

Using snippets is done via what is called "expanding". It goes like this:

- Type snippet prefix or its recognizable part.
- Press `<C-j>` to expand. It will perform the following steps:
    - Prepare available snippets in current context (buffer + local language). This allows snippet setup to have general function loaders which return different snippets in different contexts.
    - Match text to the left of cursor with available prefixes. It first tries to do exact match and falls back to fuzzy matching.
    - If there are several matches, use `vim.ui.select()` to choose one.
    - Insert single matching snippet. If snippet contains tabstops, start snippet session.

For more information see these parts of help:

- `:h MiniSnippets.default_prepare()`
- `:h MiniSnippets.default_match()`
- `:h MiniSnippets.default_select()`
- `:h MiniSnippets.default_insert()`

Snippet session allows interactive editing at tabstop locations:

- All tabstop locations are visualized depending on tabstop "state" (whether it is current/visited/unvisited/final and whether it was already edited).

  Empty tabstops are visualized with inline virtual text (`•` / `∎` for regular/final tabstops). It is removed after session is stopped.

- Start session at first tabstop. Type text to replace placeholder. When finished with current tabstop, jump to next with `<C-l>`. Repeat. If changed mind about some previous tabstop, jump back with `<C-h>`. Jumping also wraps around the edge (first tabstop is next after final).

- If tabstop has choices, use `<C-n>` / `<C-p>` to select next / previous item.

- Starting another snippet session while there is an active one is allowed. This creates nested sessions: suspend current, start the new one. After newly created is stopped, resume the suspended one.

- Stop session manually by pressing `<C-c>` or make it stop automatically: if final tabstop is current either make a text edit or exit to Normal mode. If snippet doesn't explicitly define final tabstop, it is added at the end of the snippet.

For more information about snippet session see `:h MiniSnippets-session`.

To select and insert snippets via completion engine (that supports LSP completion; like [mini.completion](https://nvim-mini.org/mini.nvim/readmes/mini-completion) or `:h vim.lsp.completion`), call `:h MiniSnippets.start_lsp_server()` after `require('mini.snippets').setup()`. This sets up an LSP server that matches and provides snippets loaded with 'mini.snippets'. To match with completion engine, use `start_lsp_server({ match = false })`.

### Management

**Important**: Out of the box 'mini.snippets' doesn't load any snippets, it should be done explicitly inside `:h MiniSnippets.setup()` following `:h MiniSnippets.config`.

The suggested approach to snippet management is to create dedicated files with snippet data and load them through function loaders in `config.snippets`. See [Quickstart](#quickstart) for basic (yet capable) snippet management config.

General idea of supported files is to have at least out of the box experience with common snippet collections. Namely [rafamadriz/friendly-snippets](https://github.com/rafamadriz/friendly-snippets).

The following files are supported:

- Extensions:
    - Read/decoded as JSON object: `*.json`, `*.code-snippets`
    - Executed as Lua file and uses returned value: `*.lua`

- Content:
    - Dict-like: object in JSON; returned table in Lua; no order guarantees.
    - Array-like: array in JSON; returned array table in Lua; preserves order.

Example of file content with a single snippet:

- Lua dict-like:   `return { name = { prefix = 't', body = 'Text' } }`
- Lua array-like:  `return { { prefix = 't', body = 'Text', desc = 'name' } }`
- JSON dict-like:  `{ "name": { "prefix": "t", "body": "Text" } }`
- JSON array-like: `[ { "prefix": "t", "body": "Text", "desc": "name" } ]`

General advice:

- Put files in "snippets" subdirectory of any path in 'runtimepath' (like '`$XDG_CONFIG_HOME`/nvim/snippets/global.json'). This is compatible with `:h MiniSnippets.gen_loader.from_runtime()` and [Quickstart](#quickstart).
- Prefer `*.json` files with dict-like content if you want more cross platform setup. Otherwise use `*.lua` files with array-like content.

Notes:

- There is no built-in support for VSCode-like "package.json" files. Define structure manually in `:h MiniSnippets.setup()` via built-in or custom loaders.
- There is no built-in support for `scope` field of snippet data. Snippets are expected to be manually separated into smaller files and loaded on demand.

For supported snippet syntax see `:h MiniSnippets-syntax-specification` or [Syntax](#syntax).

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
    | Main   | `add('nvim-mini/mini.snippets')`                                   |
    | Stable | `add({ source = 'nvim-mini/mini.snippets', checkout = 'stable' })` |

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
    | Main   | `{ 'nvim-mini/mini.snippets', version = false },` |
    | Stable | `{ 'nvim-mini/mini.snippets', version = '*' },`   |

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
    | Main   | `Plug 'nvim-mini/mini.snippets'`                         |
    | Stable | `Plug 'nvim-mini/mini.snippets', { 'branch': 'stable' }` |

</details>

**Important**: don't forget to call `require('mini.snippets').setup()` with non-empty `snippets` to have snippets to match from.

**Note**: if you are on Windows, there might be problems with too long file paths (like `error: unable to create file <some file name>: Filename too long`). Try doing one of the following:

- Enable corresponding git global config value: `git config --system core.longpaths true`. Then try to reinstall.
- Install plugin in other place with shorter path.

## Default config

```lua
-- No need to copy this inside `setup()`. Will be used automatically.
{
  -- Array of snippets and loaders (see |MiniSnippets.config| for details).
  -- Nothing is defined by default. Add manually to have snippets to match.
  snippets = {},

  -- Module mappings. Use `''` (empty string) to disable one.
  mappings = {
    -- Expand snippet at cursor position. Created globally in Insert mode.
    expand = '<C-j>',

    -- Interact with default `expand.insert` session.
    -- Created for the duration of active session(s)
    jump_next = '<C-l>',
    jump_prev = '<C-h>',
    stop = '<C-c>',
  },

  -- Functions describing snippet expansion. If `nil`, default values
  -- are `MiniSnippets.default_<field>()`.
  expand = {
    -- Resolve raw config snippets at context
    prepare = nil,
    -- Match resolved snippets at cursor position
    match = nil,
    -- Possibly choose among matched snippets
    select = nil,
    -- Insert selected snippet
    insert = nil,
  },
}
```

## Similar plugins

- [L3MON4D3/LuaSnip](https://github.com/L3MON4D3/LuaSnip)
- Built-in snippet expansion in Neovim>=0.10, see `:h vim.snippet` (doesn't provide snippet management, only snippet expansion).
- [rafamadriz/friendly-snippets](https://github.com/rafamadriz/friendly-snippets) (a curated collection of snippet files)
- [abeldekat/cmp-mini-snippets](https://github.com/abeldekat/cmp-mini-snippets) (a source for [hrsh7th/nvim-cmp](https://github.com/hrsh7th/nvim-cmp) that integrates 'mini.snippets')
