<p align="center"> <img src="https://github.com/nvim-mini/assets/blob/main/logo-2/logo-icons_readme.png?raw=true" alt="mini.icons" style="max-width:100%;border:solid 2px"/> </p>

### Icon provider

See more details in [Features](#features) and [Documentation](../doc/mini-icons.txt).

---

> [!NOTE]
> This was previously hosted at a personal `echasnovski` GitHub account. It was transferred to a dedicated organization to improve long term project stability. See more details [here](https://github.com/nvim-mini/mini.nvim/discussions/1970).

⦿ This is a part of [mini.nvim](https://nvim-mini.org/mini.nvim) library. Please use [this link](https://nvim-mini.org/mini.nvim/readmes/mini-icons) if you want to mention this module.

⦿ All contributions (issues, pull requests, discussions, etc.) are done inside of 'mini.nvim'.

⦿ See [whole library documentation](https://nvim-mini.org/mini.nvim/doc/mini-nvim) to learn about general design principles, disable/configuration recipes, and more.

⦿ See [MiniMax](https://nvim-mini.org/MiniMax) for a full config example that uses this module.

---

If you want to help this project grow but don't know where to start, check out [contributing guides of 'mini.nvim'](https://nvim-mini.org/mini.nvim/CONTRIBUTING) or leave a Github star for 'mini.nvim' project and/or any its standalone Git repositories.

## Demo

![demo-icons_glyph-dark](https://github.com/nvim-mini/assets/blob/main/demo/demo-icons_glyph-dark.png?raw=true)

![demo-icons_ascii](https://github.com/nvim-mini/assets/blob/main/demo/demo-icons_ascii.png?raw=true)

![demo-icons_glyph-light](https://github.com/nvim-mini/assets/blob/main/demo/demo-icons_glyph-light.png?raw=true)

## Features

- Provide icons with their highlighting via a single `MiniIcons.get()` for various categories: filetype, file/directory path, extension, operating system, LSP kind values. Icons and category defaults can be overridden.

- Configurable styles: "glyph" (icon glyphs) or "ascii" (non-glyph fallback).

- Fixed set of highlight groups (linked to built-in groups by default) for better blend with color scheme.

- Caching for maximum performance.

- Integration with `vim.filetype.add()` and `vim.filetype.match()`.

- Mocking methods of 'nvim-tree/nvim-web-devicons' for better integrations with plugins outside 'mini.nvim'. See `:h MiniIcons.mock_nvim_web_devicons()`.

- Tweaking built-in maps for "LSP kind" to include icons. In particular, this makes ['mini.completion'](https://nvim-mini.org/mini.nvim/readmes/mini-completion) use icons in LSP step. See `:h MiniIcons.tweak_lsp_kind()`.

Notes:

- It is not a goal to become a collection of icons for as much use cases as possible. There are specific criteria for icon data to be included as built-in in each category (see `:h MiniIcons.get()`). The main supported category is "filetype".

Recommendations for plugin authors using 'mini.icons' as a dependency:

- Check if `_G.MiniIcons` table is present (which means that user explicitly enabled 'mini.icons') and provide icons only if it is.

- Use `MiniIcons.get()` function to get icon string and more data about it.

- For file icons prefer using full path instead of relative or only basename. It makes a difference if path matches pattern that uses parent directories. The `:h MiniIcons.config` has an example of that.

## Dependencies

Suggested dependencies:

- Terminal emulator that supports showing special utf8 glyphs, possibly with "overflow" view (displaying is done not in one but two visual cells). Most modern feature-rich terminal emulators support this out of the box: WezTerm, Kitty, Alacritty, iTerm2, Ghostty.

  Not having "overflow" feature only results into smaller icons. Not having support for special utf8 glyphs will result into seemingly random symbols (or question mark squares) instead of icon glyphs.

- Font that supports [Nerd Fonts](https://www.nerdfonts.com) icons from version 3.0.0+ (in particular `nf-md-*` class).
  This should be configured on terminal emulator level either by using font patched with Nerd Fonts icons or using [`NerdFontsSymbolsOnly`](https://github.com/ryanoasis/nerd-fonts/releases) font as a fallback for glyphs that are not supported in main font.

If using terminal emulator and/or font with icon support is impossible, use `config.style = 'ascii'`. It will use a (less visually appealing) set of non-glyph icons.

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
    | Main   | `add('nvim-mini/mini.icons')`                                   |
    | Stable | `add({ source = 'nvim-mini/mini.icons', checkout = 'stable' })` |

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
    | Main   | `{ 'nvim-mini/mini.icons', version = false },` |
    | Stable | `{ 'nvim-mini/mini.icons', version = '*' },`   |

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
    | Main   | `Plug 'nvim-mini/mini.icons'`                         |
    | Stable | `Plug 'nvim-mini/mini.icons', { 'branch': 'stable' }` |

</details>

**Important**: don't forget to call `require('mini.icons').setup()` to enable its functionality.

**Note**: if you are on Windows, there might be problems with too long file paths (like `error: unable to create file <some file name>: Filename too long`). Try doing one of the following:

- Enable corresponding git global config value: `git config --system core.longpaths true`. Then try to reinstall.
- Install plugin in other place with shorter path.

## Default config

```lua
-- No need to copy this inside `setup()`. Will be used automatically.
{
  -- Icon style: 'glyph' or 'ascii'
  style = 'glyph',

  -- Customize per category. See `:h MiniIcons.config` for details.
  default   = {},
  directory = {},
  extension = {},
  file      = {},
  filetype  = {},
  lsp       = {},
  os        = {},

  -- Control which extensions will be considered during "file" resolution
  use_file_extension = function(ext, file) return true end,
}
```

## Similar plugins

- [nvim-tree/nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons)
- [onsails/lspkind.nvim](https://github.com/onsails/lspkind.nvim)
