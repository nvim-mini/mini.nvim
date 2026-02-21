<p align="center"> <img src="https://github.com/nvim-mini/assets/blob/main/logo-2/logo-operators_readme.png?raw=true" alt="mini.operators" style="max-width:100%;border:solid 2px"/> </p>

### Text edit operators

See more details in [Features](#features) and [Documentation](../doc/mini-operators.txt).

---

> [!NOTE]
> This was previously hosted at a personal `echasnovski` GitHub account. It was transferred to a dedicated organization to improve long term project stability. See more details [here](https://github.com/nvim-mini/mini.nvim/discussions/1970).

⦿ This is a part of [mini.nvim](https://nvim-mini.org/mini.nvim) library. Please use [this link](https://nvim-mini.org/mini.nvim/readmes/mini-operators) if you want to mention this module.

⦿ All contributions (issues, pull requests, discussions, etc.) are done inside of 'mini.nvim'.

⦿ See [whole library documentation](https://nvim-mini.org/mini.nvim/doc/mini-nvim) to learn about general design principles, disable/configuration recipes, and more.

⦿ See [MiniMax](https://nvim-mini.org/MiniMax) for a full config example that uses this module.

---

If you want to help this project grow but don't know where to start, check out [contributing guides of 'mini.nvim'](https://nvim-mini.org/mini.nvim/CONTRIBUTING) or leave a Github star for 'mini.nvim' project and/or any its standalone Git repositories.

## Demo

<!-- Demo source: https://github.com/nvim-mini/assets/blob/main/demo/demo-operators.mp4 -->
https://github.com/nvim-mini/mini.nvim/assets/24854248/8a3656c4-c92a-4d9f-9711-8d6a751b3e5a

## Features

- Operators:
    - Evaluate text and replace with output.
    - Exchange text regions.
    - Multiply (duplicate) text.
    - Replace text with register.
    - Sort text.

- Automated configurable mappings to operate on textobject, line, selection. Can be disabled in favor of more control with `MiniOperators.make_mappings()`.

- All operators support `[count]` and dot-repeat.

For more information see theses parts of help:
- `:h MiniOperators-overview`
- `:h MiniOperators.config`

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

    | Branch | Code snippet                                                        |
    |--------|---------------------------------------------------------------------|
    | Main   | `add('nvim-mini/mini.operators')`                                   |
    | Stable | `add({ source = 'nvim-mini/mini.operators', checkout = 'stable' })` |

</details>

<details>
<summary>With <a href="https://github.com/folke/lazy.nvim">folke/lazy.nvim</a></summary>

- 'mini.nvim' library:

    | Branch | Code snippet                                  |
    |--------|-----------------------------------------------|
    | Main   | `{ 'nvim-mini/mini.nvim', version = false },` |
    | Stable | `{ 'nvim-mini/mini.nvim', version = '*' },`   |

- Standalone plugin:

    | Branch | Code snippet                                       |
    |--------|----------------------------------------------------|
    | Main   | `{ 'nvim-mini/mini.operators', version = false },` |
    | Stable | `{ 'nvim-mini/mini.operators', version = '*' },`   |

</details>

<details>
<summary>With <a href="https://github.com/junegunn/vim-plug">junegunn/vim-plug</a></summary>

- 'mini.nvim' library:

    | Branch | Code snippet                                         |
    |--------|------------------------------------------------------|
    | Main   | `Plug 'nvim-mini/mini.nvim'`                         |
    | Stable | `Plug 'nvim-mini/mini.nvim', { 'branch': 'stable' }` |

- Standalone plugin:

    | Branch | Code snippet                                              |
    |--------|-----------------------------------------------------------|
    | Main   | `Plug 'nvim-mini/mini.operators'`                         |
    | Stable | `Plug 'nvim-mini/mini.operators', { 'branch': 'stable' }` |

</details>

**Important**: don't forget to call `require('mini.operators').setup()` to enable its functionality.

**Note**: if you are on Windows, there might be problems with too long file paths (like `error: unable to create file <some file name>: Filename too long`). Try doing one of the following:

- Enable corresponding git global config value: `git config --system core.longpaths true`. Then try to reinstall.
- Install plugin in other place with shorter path.

## Default config

```lua
-- No need to copy this inside `setup()`. Will be used automatically.
{
  -- Each entry configures one operator.
  -- `prefix` defines keys mapped during `setup()`: in Normal mode
  -- to operate on textobject and line, in Visual - on selection.

  -- Evaluate text and replace with output
  evaluate = {
    prefix = 'g=',

    -- Function which does the evaluation
    func = nil,
  },

  -- Exchange text regions
  exchange = {
    -- NOTE: Default `gx` is remapped to `gX`
    prefix = 'gx',

    -- Whether to reindent new text to match previous indent
    reindent_linewise = true,
  },

  -- Multiply (duplicate) text
  multiply = {
    prefix = 'gm',

    -- Function which can modify text before multiplying
    func = nil,
  },

  -- Replace text with register
  replace = {
    -- NOTE: Default `gr*` LSP mappings are removed
    prefix = 'gr',

    -- Whether to reindent new text to match previous indent
    reindent_linewise = true,
  },

  -- Sort text
  sort = {
    prefix = 'gs',

    -- Function which does the sort
    func = nil,
  }
}
```

## Similar plugins

- [gbprod/substitute.nvim](https://github.com/gbprod/substitute.nvim)
- [svermeulen/vim-subversive](https://github.com/svermeulen/vim-subversive)
- [tommcdo/vim-exchange](https://github.com/tommcdo/vim-exchange)
- [christoomey/vim-sort-motion](https://github.com/christoomey/vim-sort-motion)
