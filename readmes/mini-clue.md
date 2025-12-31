<p align="center"> <img src="https://github.com/nvim-mini/assets/blob/main/logo-2/logo-clue_readme.png?raw=true" alt="mini.clue" style="max-width:100%;border:solid 2px"/> </p>

### Show next key clues

See more details in [Features](#features) and [Documentation](../doc/mini-clue.txt).

---

> [!NOTE]
> This was previously hosted at a personal `echasnovski` GitHub account. It was transferred to a dedicated organization to improve long term project stability. See more details [here](https://github.com/nvim-mini/mini.nvim/discussions/1970).

⦿ This is a part of [mini.nvim](https://nvim-mini.org/mini.nvim) library. Please use [this link](https://nvim-mini.org/mini.nvim/readmes/mini-clue) if you want to mention this module.

⦿ All contributions (issues, pull requests, discussions, etc.) are done inside of 'mini.nvim'.

⦿ See [whole library documentation](https://nvim-mini.org/mini.nvim/doc/mini-nvim) to learn about general design principles, disable/configuration recipes, and more.

⦿ See [MiniMax](https://nvim-mini.org/MiniMax) for a full config example that uses this module.

---

If you want to help this project grow but don't know where to start, check out [contributing guides of 'mini.nvim'](https://nvim-mini.org/mini.nvim/CONTRIBUTING) or leave a Github star for 'mini.nvim' project and/or any its standalone Git repositories.

## Demo

<!-- Demo source: https://github.com/nvim-mini/assets/blob/main/demo/demo-clue.mp4 -->
https://github.com/nvim-mini/mini.nvim/assets/24854248/ea931966-067c-48af-93e9-36e9b8afb0ae

## Features

- Implement custom key query process to reach target key combination:
    - Starts after customizable opt-in triggers (mode + keys).

    - Each key press narrows down set of possible targets.

      Pressing `<BS>` removes previous user entry.

      Pressing `<Esc>` or `<C-c>` leads to an early stop.

      Doesn't depend on 'timeoutlen' and has basic support for 'langmap'.

    - Ends when there is at most one target left or user pressed `<CR>`. Results into emulating pressing all query keys plus possible postkeys.

- Show window (after configurable delay) with clues. It lists available next keys along with their descriptions (auto generated from descriptions present keymaps and user-supplied clues; preferring the former).

- Configurable "postkeys" for key combinations - keys which will be emulated after combination is reached during key query process.

- Provide customizable sets of clues for common built-in keys/concepts:
    - `g` key.
    - `z` key.
    - Window commands.
    - Built-in completion.
    - Marks.
    - Registers.

- Lua functions to disable/enable triggers globally or per buffer.

For more information see these parts of help:

- `:h MiniClue-key-query-process`
- `:h MiniClue-examples`
- `:h MiniClue.config`
- `:h MiniClue.gen_clues`

Notes:

- There is no functionality to create mappings in order to clearly separate two different tasks.

  The best suggested practice is to manually create mappings with descriptions (`desc` field in options), as they will be automatically used inside clue window.

- Triggers are implemented as special buffer-local mappings. This leads to several caveats:
    - They will override same regular buffer-local mappings and have precedence over global one.

      Example: having set `<C-w>` as Normal mode trigger means that there should not be another `<C-w>` mapping.

    - They need to be the latest created buffer-local mappings or they will not function properly. Most common indicator of this is that some mapping starts to work only after clue window is shown.

      Example: `g` is set as Normal mode trigger, but `gcc` from 'mini.comment' doesn't work right away. This is probably because there are some other buffer-local mappings starting with `g` which were created after mapping for `g` trigger. Most common places for this are in LSP server's `on_attach` or during tree-sitter start in buffer.

      To check if trigger is the most recent buffer-local mapping, execute `:<mode-char>map <trigger-keys>` (like `:nmap g` for previous example). Mapping for trigger should be the first listed.

      This module makes the best effort to work out of the box and cover most common cases, but it is not foolproof. The solution here is to ensure that triggers are created after making all buffer-local mappings: run either `MiniClue.setup()` or `MiniClue.ensure_buf_triggers()`.

- Descriptions from existing mappings take precedence over user-supplied clues. This is to ensure that information shown in clue window is as relevant as possible. To add/customize description of an already existing mapping, use `MiniClue.set_mapping_desc()`.

- Due to technical difficulties, there is no foolproof support for Operator-pending mode triggers (like `a`/`i` from 'mini.ai'):
    - Doesn't work as part of a command in "temporary Normal mode" (like after `<C-o>` in Insert mode) due to implementation difficulties.
    - Can have unexpected behavior with custom operators.

- Has (mostly solved) issues with macros:
    - All triggers are disabled during macro recording due to technical reasons.
    - The `@` and `Q` keys are specially mapped inside `MiniClue.setup()` to temporarily disable triggers.

## Config quick start

```lua
local miniclue = require('mini.clue')
miniclue.setup({
  triggers = {
    -- Leader triggers
    { mode = { 'n', 'x' }, keys = '<Leader>' },

    -- `[` and `]` keys
    { mode = 'n', keys = '[' },
    { mode = 'n', keys = ']' },

    -- Built-in completion
    { mode = 'i', keys = '<C-x>' },

    -- `g` key
    { mode = { 'n', 'x' }, keys = 'g' },

    -- Marks
    { mode = { 'n', 'x' }, keys = "'" },
    { mode = { 'n', 'x' }, keys = '`' },

    -- Registers
    { mode = { 'n', 'x' }, keys = '"' },
    { mode = { 'i', 'c' }, keys = '<C-r>' },

    -- Window commands
    { mode = 'n', keys = '<C-w>' },

    -- `z` key
    { mode = { 'n', 'x' }, keys = 'z' },
  },

  clues = {
    -- Enhance this by adding descriptions for <Leader> mapping groups
    miniclue.gen_clues.square_brackets(),
    miniclue.gen_clues.builtin_completion(),
    miniclue.gen_clues.g(),
    miniclue.gen_clues.marks(),
    miniclue.gen_clues.registers(),
    miniclue.gen_clues.windows(),
    miniclue.gen_clues.z(),
  },
})
```

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
    | Main   | *Follow recommended ‘mini.deps’ installation* |
    | Stable | *Follow recommended ‘mini.deps’ installation* |

- Standalone plugin:

    | Branch | Code snippet                                                   |
    |--------|----------------------------------------------------------------|
    | Main   | `add(‘nvim-mini/mini.clue’)`                                   |
    | Stable | `add({ source = ‘nvim-mini/mini.clue’, checkout = ‘stable’ })` |

</details>

<details>
<summary>With <a href="https://github.com/folke/lazy.nvim">folke/lazy.nvim</a></summary>

- 'mini.nvim' library:

    | Branch | Code snippet                                  |
    |--------|-----------------------------------------------|
    | Main   | `{ 'nvim-mini/mini.nvim', version = false },` |
    | Stable | `{ 'nvim-mini/mini.nvim', version = '*' },`   |

- Standalone plugin:

    | Branch | Code snippet                                  |
    |--------|-----------------------------------------------|
    | Main   | `{ 'nvim-mini/mini.clue', version = false },` |
    | Stable | `{ 'nvim-mini/mini.clue', version = '*' },`   |

</details>

<details>
<summary>With <a href="https://github.com/junegunn/vim-plug">junegunn/vim-plug</a></summary>

- 'mini.nvim' library:

    | Branch | Code snippet                                         |
    |--------|------------------------------------------------------|
    | Main   | `Plug 'nvim-mini/mini.nvim'`                         |
    | Stable | `Plug 'nvim-mini/mini.nvim', { 'branch': 'stable' }` |

- Standalone plugin:

    | Branch | Code snippet                                         |
    |--------|------------------------------------------------------|
    | Main   | `Plug 'nvim-mini/mini.clue'`                         |
    | Stable | `Plug 'nvim-mini/mini.clue', { 'branch': 'stable' }` |

</details>

**Important**: don't forget to call `require('mini.clue').setup()` to enable its functionality. **Needs to have triggers configured**.

**Note**: if you are on Windows, there might be problems with too long file paths (like `error: unable to create file <some file name>: Filename too long`). Try doing one of the following:

- Enable corresponding git global config value: `git config --system core.longpaths true`. Then try to reinstall.
- Install plugin in other place with shorter path.

## Default config

```lua
-- No need to copy this inside `setup()`. Will be used automatically.
{
  -- Array of extra clues to show
  clues = {},

  -- Array of opt-in triggers which start custom key query process.
  -- **Needs to have something in order to show clues**.
  triggers = {},

  -- Clue window settings
  window = {
    -- Floating window config
    config = {},

    -- Delay before showing clue window
    delay = 1000,

    -- Keys to scroll inside the clue window
    scroll_down = '<C-d>',
    scroll_up = '<C-u>',
  },
}
```

## Similar plugins

- [folke/which-key.nvim](https://github.com/folke/which-key.nvim)
- [anuvyklack/hydra.nvim](https://github.com/anuvyklack/hydra.nvim)
