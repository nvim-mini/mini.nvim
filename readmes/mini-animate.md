<p align="center"> <img src="https://github.com/nvim-mini/assets/blob/main/logo-2/logo-animate_readme.png?raw=true" alt="mini.animate" style="max-width:100%;border:solid 2px"/> </p>

### Animate common Neovim actions

See more details in [Features](#features) and [Documentation](../doc/mini-animate.txt).

---

> [!NOTE]
> This was previously hosted at a personal `echasnovski` GitHub account. It was transferred to a dedicated organization to improve long term project stability. See more details [here](https://github.com/nvim-mini/mini.nvim/discussions/1970).

⦿ This is a part of [mini.nvim](https://nvim-mini.org/mini.nvim) library. Please use [this link](https://nvim-mini.org/mini.nvim/readmes/mini-animate) if you want to mention this module.

⦿ All contributions (issues, pull requests, discussions, etc.) are done inside of 'mini.nvim'.

⦿ See [whole library documentation](https://nvim-mini.org/mini.nvim/doc/mini-nvim) to learn about general design principles, disable/configuration recipes, and more.

⦿ See [MiniMax](https://nvim-mini.org/MiniMax) for a full config example that uses this module.

---

If you want to help this project grow but don't know where to start, check out [contributing guides of 'mini.nvim'](https://nvim-mini.org/mini.nvim/CONTRIBUTING) or leave a Github star for 'mini.nvim' project and/or any its standalone Git repositories.

## Demo

<!-- Demo source: https://github.com/nvim-mini/assets/blob/main/demo/demo-animate.mp4 -->
https://user-images.githubusercontent.com/24854248/215829092-5aba4e8d-94a5-43da-8ef0-243bf0708f76.mp4

## Features

- Works out of the box with a single `require('mini.animate').setup()`. No extra mappings or commands needed.
- Animate **cursor movement** inside same buffer by showing customizable path.
- Animate **scrolling** with a series of subscrolls ("smooth scrolling").
- Animate **window resize** by gradually changing sizes of all windows.
- Animate **window open/close** with visually updating floating window.
- Timings for all actions can be customized independently.
- Action animations can be enabled/disabled independently.
- All animations are asynchronous/non-blocking and trigger a targeted event which can be used to perform actions after animation is done.
- `MiniAnimate.animate()` function which can be used to perform own animations.

Notes:

- Scroll and resize animations actually change Neovim state to achieve their effects and are asynchronous. This can cause following issues:
    - If you have remapped any movement operation to center after it is done (like with `nzvzz` or `<C-d>zz`), you need to change those mappings. Either remove them or update to use `MiniAnimate.execute_after()` (see `:h MiniAnimate.config.scroll`)
    - Using mouse wheel to scroll can appear slower or can have visual jitter. This usually happens due to high number of wheel turns per second: each turn is taking over previous one to start new animation. To mitigate this, you can either modify 'mousescroll' option (set vertical scroll to 1 and use high turn speed or set to high value and use one turn at a time) or `config.scroll` to fine tune when/how scroll animation is done.

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

    | Branch | Code snippet                                                      |
    |--------|-------------------------------------------------------------------|
    | Main   | `add('nvim-mini/mini.animate')`                                   |
    | Stable | `add({ source = 'nvim-mini/mini.animate', checkout = 'stable' })` |

</details>

<details>
<summary>With <a href="https://github.com/folke/lazy.nvim">folke/lazy.nvim</a></summary>

- 'mini.nvim' library:

    | Branch | Code snippet                                  |
    |--------|-----------------------------------------------|
    | Main   | `{ 'nvim-mini/mini.nvim', version = false },` |
    | Stable | `{ 'nvim-mini/mini.nvim', version = '*' },`   |

- Standalone plugin:

    | Branch | Code snippet                                     |
    |--------|--------------------------------------------------|
    | Main   | `{ 'nvim-mini/mini.animate', version = false },` |
    | Stable | `{ 'nvim-mini/mini.animate', version = '*' },`   |

</details>

<details>
<summary>With <a href="https://github.com/junegunn/vim-plug">junegunn/vim-plug</a></summary>

- 'mini.nvim' library:

    | Branch | Code snippet                                         |
    |--------|------------------------------------------------------|
    | Main   | `Plug 'nvim-mini/mini.nvim'`                         |
    | Stable | `Plug 'nvim-mini/mini.nvim', { 'branch': 'stable' }` |

- Standalone plugin:

    | Branch | Code snippet                                            |
    |--------|---------------------------------------------------------|
    | Main   | `Plug 'nvim-mini/mini.animate'`                         |
    | Stable | `Plug 'nvim-mini/mini.animate', { 'branch': 'stable' }` |

</details>

**Important**: don't forget to call `require('mini.animate').setup()` to enable its functionality.

**Note**: if you are on Windows, there might be problems with too long file paths (like `error: unable to create file <some file name>: Filename too long`). Try doing one of the following:

- Enable corresponding git global config value: `git config --system core.longpaths true`. Then try to reinstall.
- Install plugin in other place with shorter path.

## Default config

```lua
-- No need to copy this inside `setup()`. Will be used automatically.
{
  -- Cursor path
  cursor = {
    -- Whether to enable this animation
    enable = true,

    -- Timing of animation (how steps will progress in time)
    timing = --<function: implements linear total 250ms animation duration>,

    -- Path generator for visualized cursor movement
    path = --<function: implements shortest line path no longer than 1000>,
  },

  -- Vertical scroll
  scroll = {
    -- Whether to enable this animation
    enable = true,

    -- Timing of animation (how steps will progress in time)
    timing = --<function: implements linear total 250ms animation duration>,

    -- Subscroll generator based on total scroll
    subscroll = --<function: implements equal scroll with at most 60 steps>,
  },

  -- Window resize
  resize = {
    -- Whether to enable this animation
    enable = true,

    -- Timing of animation (how steps will progress in time)
    timing = --<function: implements linear total 250ms animation duration>,

    -- Subresize generator for all steps of resize animations
    subresize = --<function: implements equal linear steps>,
  },

  -- Window open
  open = {
    -- Whether to enable this animation
    enable = true,

    -- Timing of animation (how steps will progress in time)
    timing = --<function: implements linear total 250ms animation duration>,

    -- Floating window config generator visualizing specific window
    winconfig = --<function: implements static window for 25 steps>,

    -- 'winblend' (window transparency) generator for floating window
    winblend = --<function: implements equal linear steps from 80 to 100>,
  },

  -- Window close
  close = {
    -- Whether to enable this animation
    enable = true,

    -- Timing of animation (how steps will progress in time)
    timing = --<function: implements linear total 250ms animation duration>,

    -- Floating window config generator visualizing specific window
    winconfig = --<function: implements static window for 25 steps>,

    -- 'winblend' (window transparency) generator for floating window
    winblend = --<function: implements equal linear steps from 80 to 100>,
  },
}
```

## Similar plugins

- [Neovide](https://neovide.dev/) (Neovim GUI, not a plugin)
- [edluffy/specs.nvim](https://github.com/edluffy/specs.nvim)
- [karb94/neoscroll.nvim](https://github.com/karb94/neoscroll.nvim)
- [anuvyklack/windows.nvim](https://github.com/anuvyklack/windows.nvim)
