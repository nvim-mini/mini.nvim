<p align="center"> <img src="https://github.com/nvim-mini/assets/blob/main/logo-3/logo-mini-module-cursorword.svg?raw=true" alt="mini.cursorword" style="max-width:100%;border:solid 2px"/> </p>

### Automatic highlighting of word under cursor

See more details in [Features](#features) and [Documentation](../doc/mini-cursorword.txt).

---

> [!NOTE]
> This was previously hosted at a personal `echasnovski` GitHub account. It was transferred to a dedicated organization to improve long term project stability. See more details [here](https://github.com/nvim-mini/mini.nvim/discussions/1970).

⦿ This is a part of [mini.nvim](https://nvim-mini.org/mini.nvim) library. Please use [this link](https://nvim-mini.org/mini.nvim/readmes/mini-cursorword) if you want to mention this module.

⦿ All contributions (issues, pull requests, discussions, etc.) are done inside of 'mini.nvim'.

⦿ See [whole library documentation](https://nvim-mini.org/mini.nvim/doc/mini-nvim) to learn about general design principles, disable/configuration recipes, and more.

⦿ See [MiniMax](https://nvim-mini.org/MiniMax) for a full config example that uses this module.

---

If you want to help this project grow but don't know where to start, check out [contributing guides of 'mini.nvim'](https://nvim-mini.org/mini.nvim/CONTRIBUTING) or leave a Github star for 'mini.nvim' project and/or any its standalone Git repositories.

## Demo

<!-- Demo source: https://github.com/nvim-mini/assets/blob/main/demo/demo-cursorword.mp4 -->
https://user-images.githubusercontent.com/24854248/173044454-0e4ab873-6e73-448d-838f-45f4b2be876b.mp4

## Features

- Current word under cursor can be highlighted differently.
- "Word under cursor" is meant as in Vim's `<cword>`: something user would get as 'iw' text object.
- Highlighting stops in insert and terminal modes.

## Installation

This plugin can be installed as part of 'mini.nvim' library (**recommended**) or as a standalone Git repository.

There are two branches to install from:

- `main` (default, **recommended**) will have latest development version of plugin. All changes since last stable release should be perceived as being in beta testing phase (meaning they already passed alpha-testing and are moderately settled).
- `stable` will be updated only upon releases with code tested during public beta-testing phase in `main` branch.

Here are code snippets for some common installation methods (use only one):

<details>
<summary><b>(Recommended)</b> With <a href="https://neovim.io/doc/user/helptag.html?tag=vim.pack">vim.pack</a> (on Neovim 0.12 and newer)</summary>

**Full library**

Follow ['mini.nvim' installation](https://nvim-mini.org/mini.nvim#installation).

**Standalone plugin**

Main branch:

```lua
vim.pack.add({ 'https://github.com/nvim-mini/mini.cursorword' })
```

Stable branch:

```lua
vim.pack.add({
  { src = 'https://github.com/nvim-mini/mini.cursorword', version = 'stable' },
})
```

</details>

<details>
<summary>With <a href="https://nvim-mini.org/mini.nvim/readmes/mini-deps">mini.deps</a> (before Neovim 0.12)</summary>

**Full library**

Follow [recommended 'mini.deps' installation](https://nvim-mini.org/mini.nvim/readmes/mini-deps#installation).

**Standalone plugin**:

Main branch:

```lua
add('nvim-mini/mini.cursorword')
```

Stable branch:

```lua
add({ source = 'nvim-mini/mini.cursorword', checkout = 'stable' })
```

</details>

<details>
<summary>With <a href="https://github.com/folke/lazy.nvim">folke/lazy.nvim</a></summary>

**Full library**

Follow ['mini.nvim' installation](https://nvim-mini.org/mini.nvim#installation).

**Standalone plugin**

Main branch:

```lua
{ 'nvim-mini/mini.cursorword', version = false },
```

Stable branch:

```lua
{ 'nvim-mini/mini.cursorword', version = '*' },
```

</details>

**Important**: don't forget to call `require('mini.cursorword').setup()` to enable its functionality.

**Note**: if you are on Windows, there might be problems with too long file paths (like `error: unable to create file <some file name>: Filename too long`). Try doing one of the following:

- Enable corresponding git global config value: `git config --system core.longpaths true`. Then try to reinstall.
- Install plugin in other place with shorter path.

## Default config

```lua
-- No need to copy this inside `setup()`. Will be used automatically.
{
  -- Delay (in ms) between when cursor moved and when highlighting appeared
  delay = 100,
}
```

## Similar plugins

- [RRethy/vim-illuminate](https://github.com/RRethy/vim-illuminate)
- [itchyny/vim-cursorword](https://github.com/itchyny/vim-cursorword)
