<p align="center"> <img src="https://github.com/nvim-mini/assets/blob/main/logo-2/logo-colors_readme.png?raw=true" alt="mini.colors" style="max-width:100%;border:solid 2px"/> </p>

### Tweak and save any color scheme

See more details in [Features](#features) and [Documentation](../doc/mini-colors.txt).

---

> [!NOTE]
> This was previously hosted at a personal `echasnovski` GitHub account. It was transferred to a dedicated organization to improve long term project stability. See more details [here](https://github.com/nvim-mini/mini.nvim/discussions/1970).

⦿ This is a part of [mini.nvim](https://nvim-mini.org/mini.nvim) library. Please use [this link](https://nvim-mini.org/mini.nvim/readmes/mini-colors) if you want to mention this module.

⦿ All contributions (issues, pull requests, discussions, etc.) are done inside of 'mini.nvim'.

⦿ See [whole library documentation](https://nvim-mini.org/mini.nvim/doc/mini-nvim) to learn about general design principles, disable/configuration recipes, and more.

⦿ See [MiniMax](https://nvim-mini.org/MiniMax) for a full config example that uses this module.

---

If you want to help this project grow but don't know where to start, check out [contributing guides of 'mini.nvim'](https://nvim-mini.org/mini.nvim/CONTRIBUTING) or leave a Github star for 'mini.nvim' project and/or any its standalone Git repositories.

## Demo

<!-- Demo source: https://github.com/nvim-mini/assets/blob/main/demo/demo-colors.mp4 -->
https://user-images.githubusercontent.com/24854248/232283566-9a51fa55-d20a-4650-8205-763b55e21366.mp4

## Features

- Create colorscheme object (see `:h MiniColors-colorscheme`): either manually (`:h MiniColors.as_colorscheme()`) or by querying present color schemes (including currently active one; see `:h MiniColors.get_colorscheme()`).

- Infer data about color scheme and/or modify based on it:
    - Add transparency by removing background color (requires transparency in terminal emulator).
    - Infer cterm attributes based on gui colors making it compatible with 'notermguicolors'.
    - Resolve highlight group links.
    - Compress by removing redundant highlight groups.
    - Extract palette of used colors and/or infer terminal colors based on it.

- Modify colors to better fit your taste and/or goals:
    - Apply any function to color hex string.
    - Update channels (like lightness, saturation, hue, temperature, red, green, blue, etc.).
      Use either own function or one of the implemented methods:
        - Add value to channel or multiply it by coefficient. Like "add 10 to saturation of every color" or "multiply saturation by 2" to make colors more saturated (less gray).
        - Invert. Like "invert lightness" to convert between dark/light theme.
        - Set to one or more values (picks closest to current one). Like "set to one or two hues" to make mono- or dichromatic color scheme.
        - Repel from certain source(s) with stronger effect for closer values. Like "repel from hue 30" to remove red color from color scheme. Repel hue (how much is removed) is configurable.
    - Simulate color vision deficiency.

- Once color scheme is ready, either apply it to see effects right away or write it into a Lua file as a fully functioning separate color scheme.

- Experiment interactively with a feedback.

- Animate transition between color schemes either with `MiniColors.animate()` or with `:Colorscheme` user command.

- Convert within supported color spaces (`MiniColors.convert()`):
    - Hex string.
    - 8-bit number (terminal colors).
    - RGB.
    - Oklab, Oklch, Okhsl (https://bottosson.github.io/posts/oklab/).

## Tweak quick start

- Execute `:lua require('mini.colors').interactive()`.
- Experiment by writing calls to exposed color scheme methods and applying them with `<M-a>`. For more information, see `:h MiniColors-colorscheme-methods` and `:h MiniColors-recipes`.
- If you are happy with result, write color scheme with `<M-w>`. If not, reset to initial color scheme with `<M-r>`.
- If only some highlight groups can be made better, adjust them manually inside written color scheme file.

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
    | Main   | `add('nvim-mini/mini.colors')`                                   |
    | Stable | `add({ source = 'nvim-mini/mini.colors', checkout = 'stable' })` |

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
    | Main   | `{ 'nvim-mini/mini.colors', version = false },` |
    | Stable | `{ 'nvim-mini/mini.colors', version = '*' },`   |

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
    | Main   | `Plug 'nvim-mini/mini.colors'`                         |
    | Stable | `Plug 'nvim-mini/mini.colors', { 'branch': 'stable' }` |

</details>

**Important**: no need to call `require('mini.colors').setup()`, but it can be done to improve usability.

**Note**: if you are on Windows, there might be problems with too long file paths (like `error: unable to create file <some file name>: Filename too long`). Try doing one of the following:

- Enable corresponding git global config value: `git config --system core.longpaths true`. Then try to reinstall.
- Install plugin in other place with shorter path.

## Default config

```lua
-- No need to copy this inside `setup()`. Will be used automatically.
{}
```

## Similar plugins

- [rktjmp/lush.nvim](https://github.com/rktjmp/lush.nvim)
- [lifepillar/vim-colortemplate](https://github.com/lifepillar/vim-colortemplate)
- [tjdevries/colorbuddy.nvim](https://github.com/tjdevries/colorbuddy.nvim)
