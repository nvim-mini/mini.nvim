--- *mini.base16* Base16 colorscheme creation
---
--- MIT License Copyright (c) 2021 Evgeni Chasnovski

--- Fast implementation of [chriskempson/base16](https://github.com/chriskempson/base16)
--- color scheme (with Copyright (C) 2012 Chris Kempson) adapted for modern Neovim
--- Lua plugins. Extra features:
--- - Configurable automatic support of cterm colors (see |highlight-cterm|).
--- - Opinionated palette generator based only on background and foreground
---   colors.
---
--- Supported highlight groups:
--- - Built-in Neovim LSP and diagnostic.
---
--- - Plugins (either with explicit definition or by verification that default
---   highlighting works appropriately):
---     - [nvim-mini/mini.nvim](https://nvim-mini.org/mini.nvim)
---     - [akinsho/bufferline.nvim](https://github.com/akinsho/bufferline.nvim)
---     - [anuvyklack/hydra.nvim](https://github.com/anuvyklack/hydra.nvim)
---     - [DanilaMihailov/beacon.nvim](https://github.com/DanilaMihailov/beacon.nvim)
---     - [folke/lazy.nvim](https://github.com/folke/lazy.nvim)
---     - [folke/noice.nvim](https://github.com/folke/noice.nvim)
---     - [folke/todo-comments.nvim](https://github.com/folke/todo-comments.nvim)
---     - [folke/trouble.nvim](https://github.com/folke/trouble.nvim)
---     - [folke/which-key.nvim](https://github.com/folke/which-key.nvim)
---     - [ggandor/leap.nvim](https://github.com/ggandor/leap.nvim)
---     - [ggandor/lightspeed.nvim](https://github.com/ggandor/lightspeed.nvim)
---     - [glepnir/dashboard-nvim](https://github.com/glepnir/dashboard-nvim)
---     - [glepnir/lspsaga.nvim](https://github.com/glepnir/lspsaga.nvim)
---     - [HiPhish/rainbow-delimiters.nvim](https://github.com/HiPhish/rainbow-delimiters.nvim)
---     - [hrsh7th/nvim-cmp](https://github.com/hrsh7th/nvim-cmp)
---     - [justinmk/vim-sneak](https://github.com/justinmk/vim-sneak)
---     - [ibhagwan/fzf-lua](https://github.com/ibhagwan/fzf-lua)
---     - [kevinhwang91/nvim-bqf](https://github.com/kevinhwang91/nvim-bqf)
---     - [kevinhwang91/nvim-ufo](https://github.com/kevinhwang91/nvim-ufo)
---     - [lewis6991/gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim)
---     - [lukas-reineke/indent-blankline.nvim](https://github.com/lukas-reineke/indent-blankline.nvim)
---     - [MeanderingProgrammer/render-markdown.nvim](https://github.com/MeanderingProgrammer/render-markdown.nvim)
---     - [neoclide/coc.nvim](https://github.com/neoclide/coc.nvim)
---     - [NeogitOrg/neogit](https://github.com/NeogitOrg/neogit)
---     - [nvim-lualine/lualine.nvim](https://github.com/nvim-lualine/lualine.nvim)
---     - [nvim-neo-tree/neo-tree.nvim](https://github.com/nvim-neo-tree/neo-tree.nvim)
---     - [nvim-telescope/telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
---     - [nvim-tree/nvim-tree.lua](https://github.com/nvim-tree/nvim-tree.lua)
---     - [OXY2DEV/helpview.nvim](https://github.com/OXY2DEV/helpview.nvim)
---     - [OXY2DEV/markview.nvim](https://github.com/OXY2DEV/markview.nvim)
---     - [phaazon/hop.nvim](https://github.com/phaazon/hop.nvim)
---     - [rcarriga/nvim-dap-ui](https://github.com/rcarriga/nvim-dap-ui)
---     - [rcarriga/nvim-notify](https://github.com/rcarriga/nvim-notify)
---     - [rlane/pounce.nvim](https://github.com/rlane/pounce.nvim)
---     - [romgrk/barbar.nvim](https://github.com/romgrk/barbar.nvim)
---     - [stevearc/aerial.nvim](https://github.com/stevearc/aerial.nvim)
---     - [williamboman/mason.nvim](https://github.com/williamboman/mason.nvim)
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.base16').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table
--- `MiniBase16` which you can use for scripting or manually (with
--- `:lua MiniBase16.*`).
---
--- See |MiniBase16.config| for `config` structure and default values.
---
--- This module doesn't have runtime options, so using `vim.b.minibase16_config`
--- will have no effect here.
---
--- Example: >lua
---
---   require('mini.base16').setup({
---     palette = {
---       base00 = '#112641',
---       base01 = '#3a475e',
---       base02 = '#606b81',
---       base03 = '#8691a7',
---       base04 = '#d5dc81',
---       base05 = '#e2e98f',
---       base06 = '#eff69c',
---       base07 = '#fcffaa',
---       base08 = '#ffcfa0',
---       base09 = '#cc7e46',
---       base0A = '#46a436',
---       base0B = '#9ff895',
---       base0C = '#ca6ecf',
---       base0D = '#42f7ff',
---       base0E = '#ffc4ff',
---       base0F = '#00a5c5',
---     },
---     use_cterm = true,
---     plugins = {
---       default = false,
---       ['nvim-mini/mini.nvim'] = true,
---     },
---   })
--- <
--- # Notes ~
---
--- 1. This is used to create some of plugin's color schemes
---    (see |MiniBase16-color-schemes|).
--- 2. Using `setup()` doesn't actually create a |:colorscheme|. It basically
---    creates a coordinated set of |highlight-groups|. To create your own theme:
---     - Put "myscheme.lua" file (name after your chosen theme name) inside
---       any "colors" directory reachable from 'runtimepath' ("colors" inside
---       your Neovim config directory is usually enough).
---     - Inside "myscheme.lua" call `require('mini.base16').setup()` with your
---       palette and only after that set |g:colors_name| to "myscheme".
---@tag MiniBase16

--- # Base16 colorschemes ~
---
--- This module comes with several pre-built color schemes. Each of them is
--- a |mini.base16| theme created with faster version of the following Lua code: >lua
---
---   require('mini.base16').setup({ palette = palette, use_cterm = true })
--- <
--- Activate them as regular |:colorscheme| (for example, `:colorscheme minischeme`).
---
--- ## minischeme ~
--- *minischeme*
---
--- Blue and yellow main colors with high contrast and saturation palette.
--- Palettes are: >lua
---
---   -- For dark 'background':
---   MiniBase16.mini_palette('#112641', '#e2e98f', 75)
---
---   -- For light 'background':
---   MiniBase16.mini_palette('#e2e5ca', '#002a83', 75)
--- <
--- ## minicyan ~
--- *minicyan*
---
--- Cyan and grey main colors with moderate contrast and saturation palette.
--- Palettes are: >lua
---
---   -- For dark 'background':
---   MiniBase16.mini_palette('#0A2A2A', '#D0D0D0', 50)
---
---   -- For light 'background':
---   MiniBase16.mini_palette('#C0D2D2', '#262626', 80)
--- <
---@tag MiniBase16-color-schemes

-- Module definition ==========================================================
local MiniBase16 = {}
local H = {}

--- Module setup
---
--- Setup is done by applying base16 palette to enable colorscheme. Highlight
--- groups make an extended set from original
--- [base16-vim](https://github.com/chriskempson/base16-vim/) plugin. It is a
--- good idea to have `config.palette` respect the original [styling
--- principles](https://github.com/chriskempson/base16/blob/master/styling.md).
---
--- By default only 'gui highlighting' (see |highlight-gui| and
--- |'termguicolors'|) is supported. To support 'cterm highlighting' (see
--- |highlight-cterm|) supply `config.use_cterm` argument in one of the formats:
--- - `true` to auto-generate from `palette` (as closest colors).
--- - Table with similar structure to `palette` but having terminal colors
---   (integers from 0 to 255) instead of hex strings.
---
---@param config table Module config table. See |MiniBase16.config|.
---
---@usage >lua
---   require('mini.base16').setup({}) -- replace {} with your config table
---                                    -- needs `palette` field present
--- <
MiniBase16.setup = function(config)
  -- Export module
  _G.MiniBase16 = MiniBase16

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)
end

--- Defaults ~
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text # Plugin integrations ~
---
--- `config.plugins` defines for which supported plugins highlight groups will
--- be created. Limiting number of integrations slightly decreases startup time.
--- It is a table with boolean (`true`/`false`) values which are applied as follows:
--- - If plugin name (as listed in |mini.base16|) has entry, it is used.
--- - Otherwise `config.plugins.default` is used.
---
--- Example which will load only "mini.nvim" integration: >lua
---
---   require('mini.base16').setup({
---     palette = require('mini.base16').mini_palette('#112641', '#e2e98f', 75),
---     plugins = {
---       default = false,
---       ['nvim-mini/mini.nvim'] = true,
---     }
---   })
--- <
MiniBase16.config = {
  -- Table with names from `base00` to `base0F` and values being strings of
  -- HEX colors with format "#RRGGBB". NOTE: this should be explicitly
  -- supplied in `setup()`.
  palette = nil,

  -- Whether to support cterm colors. Can be boolean, `nil` (same as
  -- `false`), or table with cterm colors. See `setup()` documentation for
  -- more information.
  use_cterm = nil,

  -- Plugin integrations. Use `default = false` to disable all integrations.
  -- Also can be set per plugin (see |MiniBase16.config|).
  plugins = { default = true },
}
--minidoc_afterlines_end

-- Module functionality =======================================================
--- Create 'mini' palette
---
--- Create base16 palette based on the HEX (string '#RRGGBB') colors of main
--- background and foreground with optional setting of accent chroma (see
--- details).
---
--- # Algorithm design ~
---
--- - Main operating color space is
---   [CIELCh(uv)](https://en.wikipedia.org/wiki/CIELUV#Cylindrical_representation_(CIELCh))
---   which is a cylindrical representation of a perceptually uniform CIELUV
---   color space. It defines color by three values: lightness L (values from 0
---   to 100), chroma (positive values), and hue (circular values from 0 to 360
---   degrees). Useful converting tool: https://www.easyrgb.com/en/convert.php
--- - There are four important lightness values: background, foreground, focus
---   (around the middle of background and foreground, leaning towards
---   foreground), and edge (extreme lightness closest to foreground).
--- - First four colors have the same chroma and hue as `background` but
---   lightness progresses from background towards focus.
--- - Second four colors have the same chroma and hue as `foreground` but
---   lightness progresses from foreground towards edge in such a way that
---   'base05' color is main foreground color.
--- - The rest eight colors are accent colors which are created in pairs
---     - Each pair has same hue from set of hues 'most different' to
---       background and foreground hues (if respective chorma is positive).
---     - All colors have the same chroma equal to `accent_chroma` (if not
---       provided, chroma of foreground is used, as they will appear next
---       to each other). Note: this means that in case of low foreground
---       chroma, it is a good idea to set `accent_chroma` manually.
---       Values from 30 (low chorma) to 80 (high chroma) are common.
---     - Within pair there is base lightness (equal to foreground
---       lightness) and alternative (equal to focus lightness). Base
---       lightness goes to colors which will be used more frequently in
---       code: base08 (variables), base0B (strings), base0D (functions),
---       base0E (keywords).
---   How exactly accent colors are mapped to base16 palette is a result of
---   trial and error. One rule of thumb was: colors within one hue pair should
---   be more often seen next to each other. This is because it is easier to
---   distinguish them and seems to be more visually appealing. That is why
---   `base0D` and `base0F` have same hues because they usually represent
---   functions and delimiter (brackets included).
---
---@param background string Background HEX color (formatted as `#RRGGBB`).
---@param foreground string Foreground HEX color (formatted as `#RRGGBB`).
---@param accent_chroma number Optional positive number (usually between 0
---   and 100). Default: chroma of foreground color.
---
---@return table Table with base16 palette.
---
---@usage >lua
---   local p = require('mini.base16').mini_palette('#112641', '#e2e98f', 75)
---   require('mini.base16').setup({ palette = p })
--- <
MiniBase16.mini_palette = function(background, foreground, accent_chroma)
  H.validate_hex(background, 'background')
  H.validate_hex(foreground, 'foreground')
  if accent_chroma and not (type(accent_chroma) == 'number' and accent_chroma >= 0) then
    error('(mini.base16) `accent_chroma` should be a positive number or `nil`.')
  end
  local bg, fg = H.hex2lch(background), H.hex2lch(foreground)
  accent_chroma = accent_chroma or fg.c

  local palette = {}

  -- Target lightness values
  -- Justification for skewness towards foreground in focus is mainly because
  -- it will be paired with foreground lightness and used for text.
  local focus_l = 0.4 * bg.l + 0.6 * fg.l
  local edge_l = fg.l > 50 and 99 or 1

  -- Background colors
  local bg_step = (focus_l - bg.l) / 3
  palette[1] = { l = bg.l + 0 * bg_step, c = bg.c, h = bg.h }
  palette[2] = { l = bg.l + 1 * bg_step, c = bg.c, h = bg.h }
  palette[3] = { l = bg.l + 2 * bg_step, c = bg.c, h = bg.h }
  palette[4] = { l = bg.l + 3 * bg_step, c = bg.c, h = bg.h }

  -- Foreground colors Possible negative value of `palette[5].l` will be
  -- handled in future conversion to hex.
  local fg_step = (edge_l - fg.l) / 2
  palette[5] = { l = fg.l - 1 * fg_step, c = fg.c, h = fg.h }
  palette[6] = { l = fg.l + 0 * fg_step, c = fg.c, h = fg.h }
  palette[7] = { l = fg.l + 1 * fg_step, c = fg.c, h = fg.h }
  palette[8] = { l = fg.l + 2 * fg_step, c = fg.c, h = fg.h }

  -- Accent colors

  -- Only try to avoid color if it has positive chroma, because with zero
  -- chroma hue is meaningless (as in polar coordinates)
  local present_hues = {}
  if bg.c > 0 then table.insert(present_hues, bg.h) end
  if fg.c > 0 then table.insert(present_hues, fg.h) end
  local hues = H.make_different_hues(present_hues, 4)

  -- stylua: ignore start
  palette[9]  = { l = fg.l,    c = accent_chroma, h = hues[1] }
  palette[10] = { l = focus_l, c = accent_chroma, h = hues[1] }
  palette[11] = { l = focus_l, c = accent_chroma, h = hues[2] }
  palette[12] = { l = fg.l,    c = accent_chroma, h = hues[2] }
  palette[13] = { l = focus_l, c = accent_chroma, h = hues[4] }
  palette[14] = { l = fg.l,    c = accent_chroma, h = hues[3] }
  palette[15] = { l = fg.l,    c = accent_chroma, h = hues[4] }
  palette[16] = { l = focus_l, c = accent_chroma, h = hues[3] }
  -- stylua: ignore end

  -- Convert to base16 palette
  local base16_palette = {}
  for i, lch in ipairs(palette) do
    local name = H.base16_names[i]
    -- It is ensured in `lch2hex` that only valid HEX values are produced
    base16_palette[name] = H.lch2hex(lch)
  end

  return base16_palette
end

--- Converts palette with RGB colors to terminal colors
---
--- Useful for caching `use_cterm` variable to increase speed.
---
---@param palette table Table with base16 palette (same as in
---   `MiniBase16.config.palette`).
---
---@return table Table with base16 palette using |highlight-cterm|.
MiniBase16.rgb_palette_to_cterm_palette = function(palette)
  H.validate_base16_palette(palette, 'palette')

  -- Create cterm palette only when it is needed to decrease load time
  H.ensure_cterm_palette()

  return vim.tbl_map(function(hex) return H.nearest_rgb_id(H.hex2rgb(hex), H.cterm_palette) end, palette)
end

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniBase16.config)

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  -- Validate settings
  H.validate_base16_palette(config.palette, 'config.palette')
  H.validate_use_cterm(config.use_cterm, 'config.use_cterm')
  H.check_type('plugins', config.plugins, 'table')

  return config
end

H.apply_config = function(config)
  MiniBase16.config = config

  H.apply_palette(config.palette, config.use_cterm)
end

-- Validators -----------------------------------------------------------------
H.base16_names = {
  'base00',
  'base01',
  'base02',
  'base03',
  'base04',
  'base05',
  'base06',
  'base07',
  'base08',
  'base09',
  'base0A',
  'base0B',
  'base0C',
  'base0D',
  'base0E',
  'base0F',
}

H.validate_base16_palette = function(x, x_name)
  if type(x) ~= 'table' then error(string.format('(mini.base16) `%s` is not a table.', x_name)) end

  for _, color_name in pairs(H.base16_names) do
    local c = x[color_name]
    if c == nil then
      local msg = string.format('(mini.base16) `%s` does not have value %s.', x_name, color_name)
      error(msg)
    end
    H.validate_hex(c, string.format('%s.%s', x_name, color_name))
  end

  return true
end

H.validate_use_cterm = function(x, x_name)
  if not x or type(x) == 'boolean' then return true end

  if type(x) ~= 'table' then
    local msg = string.format('(mini.base16) `%s` should be boolean or table with cterm colors.', x_name)
    error(msg)
  end

  for _, color_name in pairs(H.base16_names) do
    local c = x[color_name]
    if c == nil then
      local msg = string.format('(mini.base16) `%s` does not have value %s.', x_name, color_name)
      error(msg)
    end
    if not (type(c) == 'number' and 0 <= c and c <= 255) then
      local msg = string.format('(mini.base16) `%s.%s` is not a cterm color.', x_name, color_name)
      error(msg)
    end
  end

  return true
end

H.validate_hex = function(x, x_name)
  local is_hex = type(x) == 'string' and x:len() == 7 and x:sub(1, 1) == '#' and (tonumber(x:sub(2), 16) ~= nil)

  if not is_hex then
    local msg = string.format('(mini.base16) `%s` is not a HEX color (string "#RRGGBB").', x_name)
    error(msg)
  end

  return true
end

-- Highlighting ---------------------------------------------------------------
H.apply_palette = function(palette, use_cterm)
  -- Prepare highlighting application. Notes:
  -- - Clear current highlight only if other theme was loaded previously.
  -- - No need to `syntax reset` because *all* syntax groups are defined later.
  if vim.g.colors_name then vim.cmd('highlight clear') end
  -- As this doesn't create colorscheme, don't store any name. Not doing it
  -- might cause some issues with `syntax on`.
  vim.g.colors_name = nil

  local p, hi
  if use_cterm then
    p, hi = H.make_compound_palette(palette, use_cterm), H.highlight_both
  else
    p, hi = palette, H.highlight_gui
  end

  -- NOTE: recommendations for adding new highlight groups:
  -- - Put all related groups (like for new plugin) in single paragraph.
  -- - Sort within group alphabetically (by hl-group name) ignoring case.
  -- - Link all repeated groups within paragraph (lowers execution time).
  -- - Align by commas.

  -- stylua: ignore start
  -- Builtin highlighting groups. Some groups which are missing in 'base16-vim'
  -- are added based on groups to which they are linked.
  hi('ColorColumn',    {fg=nil,      bg=p.base01, attr=nil,            sp=nil})
  hi('ComplMatchIns',  {fg=nil,      bg=nil,      attr=nil,            sp=nil})
  hi('Conceal',        {fg=p.base0D, bg=nil,      attr=nil,            sp=nil})
  hi('CurSearch',      {fg=p.base01, bg=p.base09, attr=nil,            sp=nil})
  hi('Cursor',         {fg=p.base00, bg=p.base05, attr=nil,            sp=nil})
  hi('CursorColumn',   {fg=nil,      bg=p.base01, attr=nil,            sp=nil})
  hi('CursorIM',       {fg=p.base00, bg=p.base05, attr=nil,            sp=nil})
  hi('CursorLine',     {fg=nil,      bg=p.base01, attr=nil,            sp=nil})
  hi('CursorLineFold', {fg=p.base0C, bg=p.base01, attr=nil,            sp=nil})
  hi('CursorLineNr',   {fg=p.base04, bg=p.base01, attr=nil,            sp=nil})
  hi('CursorLineSign', {fg=p.base03, bg=p.base01, attr=nil,            sp=nil})
  hi('DiffAdd',        {fg=p.base0B, bg=p.base01, attr=nil,            sp=nil})
  -- Differs from base16-vim, but according to general style guide
  hi('DiffChange',     {fg=p.base0E, bg=p.base01, attr=nil,            sp=nil})
  hi('DiffDelete',     {fg=p.base08, bg=p.base01, attr=nil,            sp=nil})
  hi('DiffText',       {fg=p.base0D, bg=p.base01, attr=nil,            sp=nil})
  hi('DiffTextAdd',    {link='DiffAdd'})
  hi('Directory',      {fg=p.base0D, bg=nil,      attr=nil,            sp=nil})
  hi('EndOfBuffer',    {fg=p.base03, bg=nil,      attr=nil,            sp=nil})
  hi('ErrorMsg',       {fg=p.base08, bg=nil,      attr=nil,            sp=nil})
  hi('FloatBorder',    {link='NormalFloat'})
  hi('FoldColumn',     {fg=p.base0C, bg=p.base01, attr=nil,            sp=nil})
  hi('Folded',         {fg=p.base03, bg=p.base01, attr=nil,            sp=nil})
  hi('IncSearch',      {fg=p.base01, bg=p.base09, attr=nil,            sp=nil})
  hi('lCursor',        {fg=p.base00, bg=p.base05, attr=nil,            sp=nil})
  hi('LineNr',         {fg=p.base03, bg=p.base01, attr=nil,            sp=nil})
  hi('LineNrAbove',    {fg=p.base03, bg=p.base01, attr=nil,            sp=nil})
  hi('LineNrBelow',    {fg=p.base03, bg=p.base01, attr=nil,            sp=nil})
  -- Slight difference from base16, where `bg=base03` is used. This makes
  -- it possible to comfortably see this highlighting in comments.
  hi('MatchParen',     {fg=nil,      bg=p.base02, attr=nil,            sp=nil})
  hi('ModeMsg',        {fg=p.base0B, bg=nil,      attr=nil,            sp=nil})
  hi('MoreMsg',        {fg=p.base0B, bg=nil,      attr=nil,            sp=nil})
  hi('MsgArea',        {link='Normal'})
  hi('MsgSeparator',   {fg=p.base02, bg=p.base02, attr=nil,            sp=nil})
  hi('NonText',        {fg=p.base03, bg=nil,      attr=nil,            sp=nil})
  hi('Normal',         {fg=p.base05, bg=p.base00, attr=nil,            sp=nil})
  hi('NormalFloat',    {fg=p.base05, bg=p.base01, attr=nil,            sp=nil})
  hi('NormalNC',       {fg=p.base05, bg=p.base00, attr=nil,            sp=nil})
  hi('OkMsg',          {fg=p.base0B, bg=nil,      attr=nil,            sp=nil})
  hi('Pmenu',          {fg=p.base05, bg=p.base01, attr=nil,            sp=nil})
  hi('PmenuExtra',     {link='Pmenu'})
  hi('PmenuExtraSel',  {link='PmenuSel'})
  hi('PmenuKind',      {link='Pmenu'})
  hi('PmenuKindSel',   {link='PmenuSel'})
  hi('PmenuMatch',     {fg=p.base05, bg=nil,      attr='bold',         sp=nil})
  hi('PmenuMatchSel',  {fg=p.base05, bg=nil,      attr='bold,reverse', sp=nil})
  hi('PmenuSbar',      {fg=nil,      bg=p.base02, attr=nil,            sp=nil})
  hi('PmenuSel',       {fg=p.base05, bg=p.base01, attr='reverse',      sp=nil})
  hi('PmenuThumb',     {fg=nil,      bg=p.base07, attr=nil,            sp=nil})
  hi('Question',       {fg=p.base0D, bg=nil,      attr=nil,            sp=nil})
  hi('QuickFixLine',   {fg=nil,      bg=p.base01, attr=nil,            sp=nil})
  hi('Search',         {fg=p.base01, bg=p.base0A, attr=nil,            sp=nil})
  hi('SignColumn',     {fg=p.base03, bg=p.base01, attr=nil,            sp=nil})
  hi('SpecialKey',     {fg=p.base03, bg=nil,      attr=nil,            sp=nil})
  hi('SpellBad',       {fg=nil,      bg=nil,      attr='undercurl',    sp=p.base08})
  hi('SpellCap',       {fg=nil,      bg=nil,      attr='undercurl',    sp=p.base0D})
  hi('SpellLocal',     {fg=nil,      bg=nil,      attr='undercurl',    sp=p.base0C})
  hi('SpellRare',      {fg=nil,      bg=nil,      attr='undercurl',    sp=p.base0E})
  hi('StatusLine',     {fg=p.base04, bg=p.base02, attr=nil,            sp=nil})
  hi('StatusLineNC',   {fg=p.base03, bg=p.base01, attr=nil,            sp=nil})
  hi('StderrMsg',      {link='ErrorMsg'})
  hi('StdoutMsg',      {link='MsgArea'})
  hi('Substitute',     {fg=p.base01, bg=p.base0A, attr=nil,            sp=nil})
  hi('TabLine',        {fg=p.base03, bg=p.base01, attr=nil,            sp=nil})
  hi('TabLineFill',    {fg=p.base03, bg=p.base01, attr=nil,            sp=nil})
  hi('TabLineSel',     {fg=p.base0B, bg=p.base01, attr=nil,            sp=nil})
  hi('TermCursor',     {fg=nil,      bg=nil,      attr='reverse',      sp=nil})
  hi('TermCursorNC',   {fg=nil,      bg=nil,      attr='reverse',      sp=nil})
  hi('Title',          {fg=p.base0D, bg=nil,      attr=nil,            sp=nil})
  hi('VertSplit',      {fg=p.base02, bg=p.base02, attr=nil,            sp=nil})
  hi('Visual',         {fg=nil,      bg=p.base02, attr=nil,            sp=nil})
  hi('VisualNOS',      {fg=p.base08, bg=nil,      attr=nil,            sp=nil})
  hi('WarningMsg',     {fg=p.base08, bg=nil,      attr=nil,            sp=nil})
  hi('Whitespace',     {fg=p.base03, bg=nil,      attr=nil,            sp=nil})
  hi('WildMenu',       {fg=p.base08, bg=p.base0A, attr=nil,            sp=nil})
  hi('WinBar',         {fg=p.base04, bg=p.base02, attr=nil,            sp=nil})
  hi('WinBarNC',       {fg=p.base03, bg=p.base01, attr=nil,            sp=nil})
  hi('WinSeparator',   {fg=p.base02, bg=p.base02, attr=nil,            sp=nil})

  -- Standard syntax (affects treesitter)
  hi('Boolean',        {fg=p.base09, bg=nil,      attr=nil, sp=nil})
  hi('Character',      {fg=p.base08, bg=nil,      attr=nil, sp=nil})
  hi('Comment',        {fg=p.base03, bg=nil,      attr=nil, sp=nil})
  hi('Conditional',    {fg=p.base0E, bg=nil,      attr=nil, sp=nil})
  hi('Constant',       {fg=p.base09, bg=nil,      attr=nil, sp=nil})
  hi('Debug',          {fg=p.base08, bg=nil,      attr=nil, sp=nil})
  hi('Define',         {fg=p.base0E, bg=nil,      attr=nil, sp=nil})
  hi('Delimiter',      {fg=p.base0F, bg=nil,      attr=nil, sp=nil})
  hi('Error',          {fg=p.base00, bg=p.base08, attr=nil, sp=nil})
  hi('Exception',      {fg=p.base08, bg=nil,      attr=nil, sp=nil})
  hi('Float',          {fg=p.base09, bg=nil,      attr=nil, sp=nil})
  hi('Function',       {fg=p.base0D, bg=nil,      attr=nil, sp=nil})
  hi('Identifier',     {fg=p.base08, bg=nil,      attr=nil, sp=nil})
  hi('Ignore',         {fg=p.base0C, bg=nil,      attr=nil, sp=nil})
  hi('Include',        {fg=p.base0D, bg=nil,      attr=nil, sp=nil})
  hi('Keyword',        {fg=p.base0E, bg=nil,      attr=nil, sp=nil})
  hi('Label',          {fg=p.base0A, bg=nil,      attr=nil, sp=nil})
  hi('Macro',          {fg=p.base08, bg=nil,      attr=nil, sp=nil})
  hi('Number',         {fg=p.base09, bg=nil,      attr=nil, sp=nil})
  hi('Operator',       {fg=p.base05, bg=nil,      attr=nil, sp=nil})
  hi('PreCondit',      {fg=p.base0A, bg=nil,      attr=nil, sp=nil})
  hi('PreProc',        {fg=p.base0A, bg=nil,      attr=nil, sp=nil})
  hi('Repeat',         {fg=p.base0A, bg=nil,      attr=nil, sp=nil})
  hi('Special',        {fg=p.base0C, bg=nil,      attr=nil, sp=nil})
  hi('SpecialChar',    {fg=p.base0F, bg=nil,      attr=nil, sp=nil})
  hi('SpecialComment', {fg=p.base0C, bg=nil,      attr=nil, sp=nil})
  hi('Statement',      {fg=p.base08, bg=nil,      attr=nil, sp=nil})
  hi('StorageClass',   {fg=p.base0A, bg=nil,      attr=nil, sp=nil})
  hi('String',         {fg=p.base0B, bg=nil,      attr=nil, sp=nil})
  hi('Structure',      {fg=p.base0E, bg=nil,      attr=nil, sp=nil})
  hi('Tag',            {fg=p.base0A, bg=nil,      attr=nil, sp=nil})
  hi('Todo',           {fg=p.base0A, bg=p.base01, attr=nil, sp=nil})
  hi('Type',           {fg=p.base0A, bg=nil,      attr=nil, sp=nil})
  hi('Typedef',        {fg=p.base0A, bg=nil,      attr=nil, sp=nil})

  -- Other from 'base16-vim'
  hi('Bold',       {fg=nil,      bg=nil, attr='bold',      sp=nil})
  hi('Italic',     {fg=nil,      bg=nil, attr='italic',    sp=nil})
  hi('TooLong',    {fg=p.base08, bg=nil, attr=nil,         sp=nil})
  hi('Underlined', {fg=nil,      bg=nil, attr='underline', sp=nil})

  -- Patch diff
  hi('diffAdded',   {fg=p.base0B, bg=nil, attr=nil, sp=nil})
  hi('diffChanged', {fg=p.base0E, bg=nil, attr=nil, sp=nil})
  hi('diffFile',    {fg=p.base09, bg=nil, attr=nil, sp=nil})
  hi('diffLine',    {fg=p.base0C, bg=nil, attr=nil, sp=nil})
  hi('diffRemoved', {fg=p.base08, bg=nil, attr=nil, sp=nil})
  hi('Added',       {fg=p.base0B, bg=nil, attr=nil, sp=nil})
  hi('Changed',     {fg=p.base0E, bg=nil, attr=nil, sp=nil})
  hi('Removed',     {fg=p.base08, bg=nil, attr=nil, sp=nil})

  -- Git commit
  hi('gitcommitBranch',        {fg=p.base09, bg=nil, attr='bold', sp=nil})
  hi('gitcommitComment',       {link='Comment'})
  hi('gitcommitDiscarded',     {link='Comment'})
  hi('gitcommitDiscardedFile', {fg=p.base08, bg=nil, attr='bold', sp=nil})
  hi('gitcommitDiscardedType', {fg=p.base0D, bg=nil, attr=nil,    sp=nil})
  hi('gitcommitHeader',        {fg=p.base0E, bg=nil, attr=nil,    sp=nil})
  hi('gitcommitOverflow',      {fg=p.base08, bg=nil, attr=nil,    sp=nil})
  hi('gitcommitSelected',      {link='Comment'})
  hi('gitcommitSelectedFile',  {fg=p.base0B, bg=nil, attr='bold', sp=nil})
  hi('gitcommitSelectedType',  {link='gitcommitDiscardedType'})
  hi('gitcommitSummary',       {fg=p.base0B, bg=nil, attr=nil,    sp=nil})
  hi('gitcommitUnmergedFile',  {link='gitcommitDiscardedFile'})
  hi('gitcommitUnmergedType',  {link='gitcommitDiscardedType'})
  hi('gitcommitUntracked',     {link='Comment'})
  hi('gitcommitUntrackedFile', {fg=p.base0A, bg=nil, attr=nil,    sp=nil})

  -- Built-in diagnostic
  hi('DiagnosticError', {fg=p.base08, bg=nil, attr=nil, sp=nil})
  hi('DiagnosticHint',  {fg=p.base0D, bg=nil, attr=nil, sp=nil})
  hi('DiagnosticInfo',  {fg=p.base0C, bg=nil, attr=nil, sp=nil})
  hi('DiagnosticOk',    {fg=p.base0B, bg=nil, attr=nil, sp=nil})
  hi('DiagnosticWarn',  {fg=p.base0E, bg=nil, attr=nil, sp=nil})

  hi('DiagnosticFloatingError', {fg=p.base08, bg=p.base01, attr=nil, sp=nil})
  hi('DiagnosticFloatingHint',  {fg=p.base0D, bg=p.base01, attr=nil, sp=nil})
  hi('DiagnosticFloatingInfo',  {fg=p.base0C, bg=p.base01, attr=nil, sp=nil})
  hi('DiagnosticFloatingOk',    {fg=p.base0B, bg=p.base01, attr=nil, sp=nil})
  hi('DiagnosticFloatingWarn',  {fg=p.base0E, bg=p.base01, attr=nil, sp=nil})

  hi('DiagnosticSignError', {link='DiagnosticFloatingError'})
  hi('DiagnosticSignHint',  {link='DiagnosticFloatingHint'})
  hi('DiagnosticSignInfo',  {link='DiagnosticFloatingInfo'})
  hi('DiagnosticSignOk',    {link='DiagnosticFloatingOk'})
  hi('DiagnosticSignWarn',  {link='DiagnosticFloatingWarn'})

  hi('DiagnosticUnderlineError', {fg=nil, bg=nil, attr='underline', sp=p.base08})
  hi('DiagnosticUnderlineHint',  {fg=nil, bg=nil, attr='underline', sp=p.base0D})
  hi('DiagnosticUnderlineInfo',  {fg=nil, bg=nil, attr='underline', sp=p.base0C})
  hi('DiagnosticUnderlineOk',    {fg=nil, bg=nil, attr='underline', sp=p.base0B})
  hi('DiagnosticUnderlineWarn',  {fg=nil, bg=nil, attr='underline', sp=p.base0E})

  -- Built-in LSP
  hi('LspReferenceText',  {fg=nil, bg=p.base02, attr=nil, sp=nil})
  hi('LspReferenceRead',  {link='LspReferenceText'})
  hi('LspReferenceWrite', {link='LspReferenceText'})

  hi('LspSignatureActiveParameter', {link='LspReferenceText'})

  hi('LspCodeLens',          {link='Comment'})
  hi('LspCodeLensSeparator', {link='Comment'})

  -- Built-in snippets
  hi('SnippetTabstop',       {link='Visual'})
  hi('SnippetTabstopActive', {link='SnippetTabstop'})

  -- Built-in markdown syntax
  hi('markdownH1', {fg=p.base09, bg=nil, attr=nil, sp=nil})
  hi('markdownH2', {fg=p.base0A, bg=nil, attr=nil, sp=nil})
  hi('markdownH3', {fg=p.base0B, bg=nil, attr=nil, sp=nil})
  hi('markdownH4', {fg=p.base0C, bg=nil, attr=nil, sp=nil})
  hi('markdownH5', {fg=p.base0D, bg=nil, attr=nil, sp=nil})
  hi('markdownH6', {fg=p.base0F, bg=nil, attr=nil, sp=nil})

  -- Tree-sitter
  -- Sources:
  -- - `:h treesitter-highlight-groups`
  -- - https://github.com/nvim-treesitter/nvim-treesitter/blob/master/CONTRIBUTING.md#highlights
  -- Included only those differing from default links
  hi('@keyword.return', {fg=p.base08, bg=nil, attr=nil, sp=nil})
  hi('@symbol',         {fg=p.base0E, bg=nil, attr=nil, sp=nil})
  hi('@variable',       {fg=p.base05, bg=nil, attr=nil, sp=nil})

  hi('@text.strong',    {fg=nil, bg=nil, attr='bold',          sp=nil})
  hi('@text.emphasis',  {fg=nil, bg=nil, attr='italic',        sp=nil})
  hi('@text.strike',    {fg=nil, bg=nil, attr='strikethrough', sp=nil})
  hi('@text.underline', {link='Underlined'})

  -- Semantic tokens. Source: `:h lsp-semantic-highlight`.
  -- Included only those differing from default links
  hi('@lsp.type.variable',  {fg=p.base05, bg=nil, attr=nil, sp=nil})
  hi('@lsp.mod.deprecated', {fg=p.base08, bg=nil, attr=nil, sp=nil})

  -- New tree-sitter groups
  if vim.fn.has('nvim-0.10') == 1 then
    -- Source: `:h treesitter-highlight-groups`
    -- Included only those differing from default links
    hi('@markup.strong',        {link='@text.strong'})
    hi('@markup.italic',        {link='@text.emphasis'})
    hi('@markup.strikethrough', {link='@text.strike'})
    hi('@markup.underline',     {link='@text.underline'})

    hi('@markup.heading.1', {link='markdownH1'})
    hi('@markup.heading.2', {link='markdownH2'})
    hi('@markup.heading.3', {link='markdownH3'})
    hi('@markup.heading.4', {link='markdownH4'})
    hi('@markup.heading.5', {link='markdownH5'})
    hi('@markup.heading.6', {link='markdownH6'})

    hi('@string.special.vimdoc',     {link='SpecialChar'})
    hi('@variable.parameter.vimdoc', {fg=p.base09, bg=nil, attr=nil, sp=nil})
    hi('@markup.heading.4.vimdoc',   {link='Title'})
  end

  -- Plugins
  -- nvim-mini/mini.nvim
  -- TODO: Remove 'echasnovski/mini.nvim' fallback after September 2026
  if H.has_integration('nvim-mini/mini.nvim') or H.has_integration('echasnovski/mini.nvim') then
    hi('MiniAnimateCursor',      {fg=nil, bg=nil, attr='reverse,nocombine', sp=nil})
    hi('MiniAnimateNormalFloat', {link='NormalFloat'})

    hi('MiniClueBorder',              {link='FloatBorder'})
    hi('MiniClueDescGroup',           {link='DiagnosticFloatingWarn'})
    hi('MiniClueDescSingle',          {link='NormalFloat'})
    hi('MiniClueNextKey',             {link='DiagnosticFloatingHint'})
    hi('MiniClueNextKeyWithPostkeys', {link='DiagnosticFloatingError'})
    hi('MiniClueSeparator',           {link='DiagnosticFloatingInfo'})
    hi('MiniClueTitle',               {fg=p.base0D, bg=p.base01, attr='bold', sp=nil})

    hi('MiniCmdlinePeekBorder', {link='FloatBorder'})
    hi('MiniCmdlinePeekLineNr', {link='DiagnosticSignWarn'})
    hi('MiniCmdlinePeekNormal', {link='NormalFloat'})
    hi('MiniCmdlinePeekSep',    {link='SignColumn'})
    hi('MiniCmdlinePeekSign',   {link='DiagnosticSignHint'})
    hi('MiniCmdlinePeekTitle',  {fg=p.base0D, bg=p.base01, attr='bold', sp=nil})

    hi('MiniCompletionActiveParameter',    {link='LspSignatureActiveParameter'})
    hi('MiniCompletionDeprecated',         {link='DiagnosticDeprecated'})
    hi('MiniCompletionInfoBorderOutdated', {link='DiagnosticFloatingWarn'})

    hi('MiniCursorword',        {fg=nil, bg=nil, attr='underline', sp=nil})
    hi('MiniCursorwordCurrent', {fg=nil, bg=nil, attr='underline', sp=nil})

    hi('MiniDepsChangeAdded',   {link='diffAdded'})
    hi('MiniDepsChangeRemoved', {link='diffRemoved'})
    hi('MiniDepsHint',          {link='DiagnosticHint'})
    hi('MiniDepsInfo',          {link='DiagnosticInfo'})
    hi('MiniDepsMsgBreaking',   {link='DiagnosticWarn'})
    hi('MiniDepsPlaceholder',   {link='Comment'})
    hi('MiniDepsTitle',         {link='Title'})
    hi('MiniDepsTitleError',    {link='DiffDelete'})
    hi('MiniDepsTitleSame',     {link='DiffText'})
    hi('MiniDepsTitleUpdate',   {link='DiffAdd'})

    hi('MiniDiffSignAdd',        {fg=p.base0B, bg=p.base01, attr=nil, sp=nil})
    hi('MiniDiffSignChange',     {fg=p.base0E, bg=p.base01, attr=nil, sp=nil})
    hi('MiniDiffSignDelete',     {fg=p.base08, bg=p.base01, attr=nil, sp=nil})
    hi('MiniDiffOverAdd',        {link='DiffAdd'})
    hi('MiniDiffOverChange',     {link='DiffText'})
    hi('MiniDiffOverChangeBuf',  {link='MiniDiffOverChange'})
    hi('MiniDiffOverContext',    {link='DiffChange'})
    hi('MiniDiffOverContextBuf', {})
    hi('MiniDiffOverDelete',     {link='DiffDelete'})

    hi('MiniFilesBorder',         {link='FloatBorder'})
    hi('MiniFilesBorderModified', {link='DiagnosticFloatingWarn'})
    hi('MiniFilesCursorLine',     {fg=nil,      bg=p.base02, attr=nil,    sp=nil})
    hi('MiniFilesDirectory',      {link='Directory'})
    hi('MiniFilesFile',           {fg=p.base05, bg=nil,      attr=nil,    sp=nil})
    hi('MiniFilesNormal',         {link='NormalFloat'})
    hi('MiniFilesTitle',          {fg=p.base0D, bg=p.base01, attr=nil,    sp=nil})
    hi('MiniFilesTitleFocused',   {fg=p.base0D, bg=p.base01, attr='bold', sp=nil})

    hi('MiniHipatternsFixme', {fg=p.base00, bg=p.base08, attr='bold', sp=nil})
    hi('MiniHipatternsHack',  {fg=p.base00, bg=p.base0E, attr='bold', sp=nil})
    hi('MiniHipatternsNote',  {fg=p.base00, bg=p.base0D, attr='bold', sp=nil})
    hi('MiniHipatternsTodo',  {fg=p.base00, bg=p.base0C, attr='bold', sp=nil})

    hi('MiniIconsAzure',  {fg=p.base0D, bg=nil, attr=nil, sp=nil})
    hi('MiniIconsBlue',   {fg=p.base0F, bg=nil, attr=nil, sp=nil})
    hi('MiniIconsCyan',   {fg=p.base0C, bg=nil, attr=nil, sp=nil})
    hi('MiniIconsGreen',  {fg=p.base0B, bg=nil, attr=nil, sp=nil})
    hi('MiniIconsGrey',   {fg=p.base07, bg=nil, attr=nil, sp=nil})
    hi('MiniIconsOrange', {fg=p.base09, bg=nil, attr=nil, sp=nil})
    hi('MiniIconsPurple', {fg=p.base0E, bg=nil, attr=nil, sp=nil})
    hi('MiniIconsRed',    {fg=p.base08, bg=nil, attr=nil, sp=nil})
    hi('MiniIconsYellow', {fg=p.base0A, bg=nil, attr=nil, sp=nil})

    hi('MiniIndentscopeSymbol',    {fg=p.base0F, bg=nil, attr=nil, sp=nil})
    hi('MiniIndentscopeSymbolOff', {fg=p.base08, bg=nil, attr=nil, sp=nil})

    hi('MiniJump', {link='SpellRare'})

    hi('MiniJump2dDim',        {link='Comment'})
    hi('MiniJump2dSpot',       {fg=p.base07, bg=p.base01, attr='bold,nocombine', sp=nil})
    hi('MiniJump2dSpotAhead',  {fg=p.base06, bg=p.base00, attr='nocombine',      sp=nil})
    hi('MiniJump2dSpotUnique', {link='MiniJump2dSpot'})

    hi('MiniMapNormal',      {fg=p.base05, bg=p.base01, attr=nil, sp=nil})
    hi('MiniMapSymbolCount', {fg=p.base0C, bg=nil,      attr=nil, sp=nil})
    hi('MiniMapSymbolLine',  {fg=p.base0D, bg=nil,      attr=nil, sp=nil})
    hi('MiniMapSymbolView',  {fg=p.base0F, bg=nil,      attr=nil, sp=nil})

    hi('MiniNotifyBorder',      {link='FloatBorder'})
    hi('MiniNotifyLspProgress', {link='MiniNotifyNormal'})
    hi('MiniNotifyNormal',      {link='NormalFloat'})
    hi('MiniNotifyTitle',       {link='FloatTitle'})

    hi('MiniOperatorsExchangeFrom', {link='IncSearch'})

    hi('MiniPickBorder',        {link='FloatBorder'})
    hi('MiniPickBorderBusy',    {fg=p.base0E, bg=p.base01, attr=nil,         sp=nil})
    hi('MiniPickBorderText',    {fg=p.base0D, bg=p.base01, attr='bold',      sp=nil})
    hi('MiniPickCursor',        {fg=nil,      bg=nil,      attr='nocombine', sp=nil, blend=100})
    hi('MiniPickIconDirectory', {link='Directory'})
    hi('MiniPickIconFile',      {fg=p.base05, bg=nil,      attr=nil,         sp=nil})
    hi('MiniPickHeader',        {link='DiagnosticFloatingHint'})
    hi('MiniPickMatchCurrent',  {fg=nil,      bg=p.base02, attr=nil,         sp=nil})
    hi('MiniPickMatchMarked',   {fg=nil,      bg=p.base03, attr=nil,         sp=nil})
    hi('MiniPickMatchRanges',   {link='DiagnosticFloatingHint'})
    hi('MiniPickNormal',        {link='NormalFloat'})
    hi('MiniPickPreviewLine',   {fg=nil,      bg=p.base02, attr=nil,         sp=nil})
    hi('MiniPickPreviewRegion', {link='IncSearch'})
    hi('MiniPickPrompt',        {link='MiniPickMatchRanges'})
    hi('MiniPickPromptCaret' ,  {fg=p.base0B, bg=p.base01, attr=nil,         sp=nil})
    hi('MiniPickPromptPrefix',  {fg=p.base0B, bg=p.base01, attr=nil,         sp=nil})

    hi('MiniSnippetsCurrent',        {fg=nil, bg=nil, attr='underdouble', sp=p.base0E})
    hi('MiniSnippetsCurrentReplace', {fg=nil, bg=nil, attr='underdouble', sp=p.base08})
    hi('MiniSnippetsFinal',          {fg=nil, bg=nil, attr='underdouble', sp=p.base0B})
    hi('MiniSnippetsUnvisited',      {fg=nil, bg=nil, attr='underdouble', sp=p.base0D})
    hi('MiniSnippetsVisited',        {fg=nil, bg=nil, attr='underdouble', sp=p.base0C})

    hi('MiniStarterCurrent',    {link='MiniStarterItem'})
    hi('MiniStarterFooter',     {fg=p.base0D, bg=nil, attr=nil,    sp=nil})
    hi('MiniStarterHeader',     {fg=p.base0D, bg=nil, attr=nil,    sp=nil})
    hi('MiniStarterInactive',   {link='Comment'})
    hi('MiniStarterItem',       {fg=p.base05, bg=nil, attr=nil,    sp=nil})
    hi('MiniStarterItemBullet', {fg=p.base0F, bg=nil, attr=nil,    sp=nil})
    hi('MiniStarterItemPrefix', {fg=p.base08, bg=nil, attr='bold', sp=nil})
    hi('MiniStarterSection',    {fg=p.base0F, bg=nil, attr=nil,    sp=nil})
    hi('MiniStarterQuery',      {fg=p.base0B, bg=nil, attr='bold', sp=nil})

    hi('MiniStatuslineDevinfo',     {fg=p.base04, bg=p.base02, attr=nil,    sp=nil})
    hi('MiniStatuslineFileinfo',    {link='MiniStatuslineDevinfo'})
    hi('MiniStatuslineFilename',    {fg=p.base03, bg=p.base01, attr=nil,    sp=nil})
    hi('MiniStatuslineInactive',    {link='StatusLineNC'})
    hi('MiniStatuslineModeCommand', {fg=p.base00, bg=p.base08, attr='bold', sp=nil})
    hi('MiniStatuslineModeInsert',  {fg=p.base00, bg=p.base0D, attr='bold', sp=nil})
    hi('MiniStatuslineModeNormal',  {fg=p.base00, bg=p.base05, attr='bold', sp=nil})
    hi('MiniStatuslineModeOther',   {fg=p.base00, bg=p.base03, attr='bold', sp=nil})
    hi('MiniStatuslineModeReplace', {fg=p.base00, bg=p.base0E, attr='bold', sp=nil})
    hi('MiniStatuslineModeVisual',  {fg=p.base00, bg=p.base0B, attr='bold', sp=nil})

    hi('MiniSurround', {link='IncSearch'})

    hi('MiniTablineCurrent',         {fg=p.base05, bg=p.base02, attr='bold', sp=nil})
    hi('MiniTablineFill',            {link='Normal'})
    hi('MiniTablineHidden',          {fg=p.base04, bg=p.base01, attr=nil,    sp=nil})
    hi('MiniTablineModifiedCurrent', {fg=p.base02, bg=p.base05, attr='bold', sp=nil})
    hi('MiniTablineModifiedHidden',  {fg=p.base01, bg=p.base04, attr=nil,    sp=nil})
    hi('MiniTablineModifiedVisible', {fg=p.base02, bg=p.base04, attr='bold', sp=nil})
    hi('MiniTablineTabpagesection',  {fg=p.base01, bg=p.base0A, attr='bold', sp=nil})
    hi('MiniTablineTrunc',           {fg=p.base05, bg=p.base01, attr='bold', sp=nil})
    hi('MiniTablineVisible',         {fg=p.base05, bg=p.base01, attr='bold', sp=nil})

    hi('MiniTestEmphasis', {fg=nil,      bg=nil, attr='bold', sp=nil})
    hi('MiniTestFail',     {fg=p.base08, bg=nil, attr='bold', sp=nil})
    hi('MiniTestPass',     {fg=p.base0B, bg=nil, attr='bold', sp=nil})

    hi('MiniTrailspace', {link='Error'})
  end

  if H.has_integration('akinsho/bufferline.nvim') then
    hi('BufferLineBuffer',              {fg=p.base04, bg=nil,      attr=nil,    sp=nil})
    hi('BufferLineBufferSelected',      {fg=p.base05, bg=nil,      attr='bold', sp=nil})
    hi('BufferLineBufferVisible',       {fg=p.base05, bg=nil,      attr=nil,    sp=nil})
    hi('BufferLineCloseButton',         {link='BufferLineBackground'})
    hi('BufferLineCloseButtonSelected', {link='BufferLineBufferSelected'})
    hi('BufferLineCloseButtonVisible',  {link='BufferLineBufferVisible'})
    hi('BufferLineFill',                {link='Normal'})
    hi('BufferLineTab',                 {fg=p.base00, bg=p.base0A, attr=nil,    sp=nil})
    hi('BufferLineTabSelected',         {fg=p.base00, bg=p.base0A, attr='bold', sp=nil})
  end

  if H.has_integration('anuvyklack/hydra.nvim') then
    hi('HydraRed',      {fg=p.base08, bg=nil, attr=nil, sp=nil})
    hi('HydraBlue',     {fg=p.base0D, bg=nil, attr=nil, sp=nil})
    hi('HydraAmaranth', {fg=p.base0E, bg=nil, attr=nil, sp=nil})
    hi('HydraTeal',     {fg=p.base0B, bg=nil, attr=nil, sp=nil})
    hi('HydraPink',     {fg=p.base09, bg=nil, attr=nil, sp=nil})
    hi('HydraHint',     {link='NormalFloat'})
  end

  if H.has_integration('DanilaMihailov/beacon.nvim') then
    hi('Beacon', {fg=nil, bg=p.base07, attr=nil, sp=nil})
  end

  if H.has_integration('folke/lazy.nvim') then
    hi('LazyButton',       {fg=nil, bg=p.base01, attr=nil,    sp=nil})
    hi('LazyButtonActive', {fg=nil, bg=p.base02, attr=nil,    sp=nil})
    hi('LazyDimmed',       {link='Comment'})
    hi('LazyH1',           {fg=nil, bg=p.base02, attr='bold', sp=nil})
  end

  if H.has_integration('folke/noice.nvim') then
    hi('NoiceCmdlinePopupBorder', {fg=p.base0D, bg=nil, attr=nil, sp=nil})
    hi('NoiceConfirmBorder',      {fg=p.base0E, bg=nil, attr=nil, sp=nil})
  end

  -- folke/trouble.nvim
  if H.has_integration('folke/trouble.nvim') then
    hi('TroubleCount',           {fg=p.base0B, bg=nil, attr='bold', sp=nil})
    hi('TroubleFoldIcon',        {fg=p.base05, bg=nil, attr=nil,    sp=nil})
    hi('TroubleIndent',          {fg=p.base02, bg=nil, attr=nil,    sp=nil})
    hi('TroubleLocation',        {fg=p.base04, bg=nil, attr=nil,    sp=nil})
    hi('TroubleSignError',       {link='DiagnosticError'})
    hi('TroubleSignHint',        {link='DiagnosticHint'})
    hi('TroubleSignInformation', {link='DiagnosticInfo'})
    hi('TroubleSignOther',       {link='DiagnosticInfo'})
    hi('TroubleSignWarning',     {link='DiagnosticWarn'})
    hi('TroubleText',            {fg=p.base05, bg=nil, attr=nil,    sp=nil})
    hi('TroubleTextError',       {link='TroubleText'})
    hi('TroubleTextHint',        {link='TroubleText'})
    hi('TroubleTextInformation', {link='TroubleText'})
    hi('TroubleTextWarning',     {link='TroubleText'})
  end

  -- folke/todo-comments.nvim
  -- Everything works correctly out of the box

  if H.has_integration('folke/which-key.nvim') then
    hi('WhichKey',          {fg=p.base0D, bg=nil,      attr=nil, sp=nil})
    hi('WhichKeyDesc',      {fg=p.base05, bg=nil,      attr=nil, sp=nil})
    hi('WhichKeyFloat',     {fg=p.base05, bg=p.base01, attr=nil, sp=nil})
    hi('WhichKeyGroup',     {fg=p.base0E, bg=nil,      attr=nil, sp=nil})
    hi('WhichKeySeparator', {fg=p.base0B, bg=p.base01, attr=nil, sp=nil})
    hi('WhichKeyValue',     {fg=p.base03, bg=nil,      attr=nil, sp=nil})
  end

  if H.has_integration('ggandor/leap.nvim') then
    hi('LeapMatch',          {fg=p.base0E, bg=nil, attr='bold,nocombine,underline', sp=nil})
    hi('LeapLabel',          {fg=p.base08, bg=nil, attr='bold,nocombine',           sp=nil})
    hi('LeapLabelSelected',  {fg=p.base09, bg=nil, attr='bold,nocombine',           sp=nil})
    hi('LeapBackdrop',       {link='Comment'})
  end

  if H.has_integration('ggandor/lightspeed.nvim') then
    hi('LightspeedLabel',          {fg=p.base0E, bg=nil, attr='bold,underline', sp=nil})
    hi('LightspeedLabelDistant',   {fg=p.base0D, bg=nil, attr='bold,underline', sp=nil})
    hi('LightspeedShortcut',       {fg=p.base07, bg=nil, attr='bold', sp=nil})
    hi('LightspeedMaskedChar',     {fg=p.base04, bg=nil, attr=nil, sp=nil})
    hi('LightspeedUnlabeledMatch', {fg=p.base05, bg=nil, attr='bold', sp=nil})
    hi('LightspeedGreyWash',       {link='Comment'})
    hi('LightspeedUniqueChar',     {link='LightspeedUnlabeledMatch'})
    hi('LightspeedOneCharMatch',   {link='LightspeedShortcut'})
    hi('LightspeedPendingOpArea',  {link='IncSearch'})
    hi('LightspeedCursor',         {link='Cursor'})
  end

  if H.has_integration('glepnir/dashboard-nvim') then
    hi('DashboardCenter',   {link='Delimiter'})
    hi('DashboardFooter',   {link='Title'})
    hi('DashboardHeader',   {link='Title'})
    hi('DashboardShortCut', {link='WarningMsg'})
  end

  if H.has_integration('glepnir/lspsaga.nvim') then
    hi('LspSagaCodeActionBorder',  {fg=p.base0F, bg=nil, attr=nil,    sp=nil})
    hi('LspSagaCodeActionContent', {fg=p.base05, bg=nil, attr=nil,    sp=nil})
    hi('LspSagaCodeActionTitle',   {fg=p.base0D, bg=nil, attr='bold', sp=nil})

    hi('Definitions',            {fg=p.base0B, bg=nil, attr=nil, sp=nil})
    hi('DefinitionsIcon',        {fg=p.base0D, bg=nil, attr=nil, sp=nil})
    hi('FinderParam',            {fg=p.base08, bg=nil, attr=nil, sp=nil})
    hi('FinderVirtText',         {fg=p.base09, bg=nil, attr=nil, sp=nil})
    hi('LspSagaAutoPreview',     {fg=p.base0F, bg=nil, attr=nil, sp=nil})
    hi('LspSagaFinderSelection', {fg=p.base0A, bg=nil, attr=nil, sp=nil})
    hi('LspSagaLspFinderBorder', {fg=p.base0F, bg=nil, attr=nil, sp=nil})
    hi('References',             {fg=p.base0B, bg=nil, attr=nil, sp=nil})
    hi('ReferencesIcon',         {fg=p.base0D, bg=nil, attr=nil, sp=nil})
    hi('TargetFileName',         {fg=p.base05, bg=nil, attr=nil, sp=nil})

    hi('FinderSpinner',       {fg=p.base0B, bg=nil, attr=nil, sp=nil})
    hi('FinderSpinnerBorder', {fg=p.base0F, bg=nil, attr=nil, sp=nil})
    hi('FinderSpinnerTitle',  {link='Title'})

    hi('LspSagaDefPreviewBorder', {fg=p.base0F, bg=nil, attr=nil, sp=nil})

    hi('LspSagaHoverBorder', {fg=p.base0F, bg=nil, attr=nil, sp=nil})

    hi('LspSagaRenameBorder', {fg=p.base0F, bg=nil, attr=nil, sp=nil})

    hi('LspSagaDiagnosticBorder', {fg=p.base0F, bg=nil, attr=nil, sp=nil})
    hi('LspSagaDiagnosticHeader', {link='Title'})
    hi('LspSagaDiagnosticSource', {fg=p.base0E, bg=nil, attr=nil, sp=nil})

    hi('LspSagaBorderTitle', {link='Title'})

    hi('LspSagaSignatureHelpBorder', {fg=p.base0F, bg=nil, attr=nil, sp=nil})

    hi('LSOutlinePreviewBorder', {fg=p.base0F, bg=nil, attr=nil, sp=nil})
    hi('OutlineDetail',          {fg=p.base03, bg=nil, attr=nil, sp=nil})
    hi('OutlineFoldPrefix',      {fg=p.base08, bg=nil, attr=nil, sp=nil})
    hi('OutlineIndentEvn',       {fg=p.base04, bg=nil, attr=nil, sp=nil})
    hi('OutlineIndentOdd',       {fg=p.base05, bg=nil, attr=nil, sp=nil})
  end

  if H.has_integration('HiPhish/rainbow-delimiters.nvim') then
    hi('RainbowDelimiterBlue',   {fg=p.base0D, bg=nil, attr=nil, sp=nil})
    hi('RainbowDelimiterCyan',   {fg=p.base0C, bg=nil, attr=nil, sp=nil})
    hi('RainbowDelimiterGreen',  {fg=p.base0B, bg=nil, attr=nil, sp=nil})
    hi('RainbowDelimiterOrange', {fg=p.base09, bg=nil, attr=nil, sp=nil})
    hi('RainbowDelimiterRed',    {fg=p.base08, bg=nil, attr=nil, sp=nil})
    hi('RainbowDelimiterViolet', {fg=p.base0E, bg=nil, attr=nil, sp=nil})
    hi('RainbowDelimiterYellow', {fg=p.base0A, bg=nil, attr=nil, sp=nil})
  end

  if H.has_integration('hrsh7th/nvim-cmp') then
    hi('CmpItemAbbr',           {fg=p.base05, bg=nil,      attr=nil,    sp=nil})
    hi('CmpItemAbbrDeprecated', {fg=p.base03, bg=nil,      attr=nil,    sp=nil})
    hi('CmpItemAbbrMatch',      {fg=p.base0A, bg=nil,      attr='bold', sp=nil})
    hi('CmpItemAbbrMatchFuzzy', {fg=p.base0A, bg=nil,      attr='bold', sp=nil})
    hi('CmpItemKind',           {fg=p.base0F, bg=p.base01, attr=nil,    sp=nil})
    hi('CmpItemMenu',           {fg=p.base05, bg=p.base01, attr=nil,    sp=nil})

    hi('CmpItemKindClass',         {link='Type'})
    hi('CmpItemKindColor',         {link='Special'})
    hi('CmpItemKindConstant',      {link='Constant'})
    hi('CmpItemKindConstructor',   {link='Type'})
    hi('CmpItemKindEnum',          {link='Structure'})
    hi('CmpItemKindEnumMember',    {link='Structure'})
    hi('CmpItemKindEvent',         {link='Exception'})
    hi('CmpItemKindField',         {link='Structure'})
    hi('CmpItemKindFile',          {link='Tag'})
    hi('CmpItemKindFolder',        {link='Directory'})
    hi('CmpItemKindFunction',      {link='Function'})
    hi('CmpItemKindInterface',     {link='Structure'})
    hi('CmpItemKindKeyword',       {link='Keyword'})
    hi('CmpItemKindMethod',        {link='Function'})
    hi('CmpItemKindModule',        {link='Structure'})
    hi('CmpItemKindOperator',      {link='Operator'})
    hi('CmpItemKindProperty',      {link='Structure'})
    hi('CmpItemKindReference',     {link='Tag'})
    hi('CmpItemKindSnippet',       {link='Special'})
    hi('CmpItemKindStruct',        {link='Structure'})
    hi('CmpItemKindText',          {link='Statement'})
    hi('CmpItemKindTypeParameter', {link='Type'})
    hi('CmpItemKindUnit',          {link='Special'})
    hi('CmpItemKindValue',         {link='Identifier'})
    hi('CmpItemKindVariable',      {link='Delimiter'})
  end

  if H.has_integration('ibhagwan/fzf-lua') then
    hi('FzfLuaBufFlagAlt', {link='Special'})
    hi('FzfLuaBufFlagCur', {link='CursorLineNr'})
    hi('FzfLuaBufNr',      {link='DiagnosticHint'})
    hi('FzfLuaHeaderBind', {link='DiagnosticWarn'})
    hi('FzfLuaHeaderText', {link='DiagnosticInfo'})
    hi('FzfLuaLiveSym',    {link='DiagnosticHint'})
    hi('FzfLuaPathColNr',  {link='DiagnosticHint'})
    hi('FzfLuaPathLineNr', {link='DiagnosticInfo'})
    hi('FzfLuaTabMarker',  {link='DiagnosticHint'})
    hi('FzfLuaTabTitle',   {link='Title'})
    hi('FzfLuaTitle',      {link='FloatTitle'})
  end

  if H.has_integration('justinmk/vim-sneak') then
    hi('Sneak',      {fg=p.base00, bg=p.base0E, attr=nil,    sp=nil})
    hi('SneakScope', {fg=p.base00, bg=p.base07, attr=nil,    sp=nil})
    hi('SneakLabel', {fg=p.base00, bg=p.base0E, attr='bold', sp=nil})
  end

  -- 'kevinhwang91/nvim-bqf'
  if H.has_integration('kevinhwang91/nvim-bqf') then
    hi('BqfPreviewFloat', {link='NormalFloat'})
    hi('BqfPreviewTitle', {fg=p.base0D, bg=p.base01, attr=nil, sp=nil})
    hi('BqfSign',         {fg=p.base0C, bg=p.base01, attr=nil, sp=nil})
  end

  -- 'kevinhwang91/nvim-ufo'
  -- Everything works correctly out of the box

  if H.has_integration('lewis6991/gitsigns.nvim') then
    hi('GitSignsAdd',             {fg=p.base0B, bg=p.base01, attr=nil, sp=nil})
    hi('GitSignsAddLn',           {link='GitSignsAdd'})
    hi('GitSignsAddInline',       {link='GitSignsAdd'})

    hi('GitSignsChange',          {fg=p.base0E, bg=p.base01, attr=nil, sp=nil})
    hi('GitSignsChangeLn',        {link='GitSignsChange'})
    hi('GitSignsChangeInline',    {link='GitSignsChange'})

    hi('GitSignsDelete',          {fg=p.base08, bg=p.base01, attr=nil, sp=nil})
    hi('GitSignsDeleteLn',        {link='GitSignsDelete'})
    hi('GitSignsDeleteInline',    {link='GitSignsDelete'})

    hi('GitSignsUntracked',       {fg=p.base0D, bg=p.base01, attr=nil, sp=nil})
    hi('GitSignsUntrackedLn',     {link='GitSignsUntracked'})
    hi('GitSignsUntrackedInline', {link='GitSignsUntracked'})
  end

  if H.has_integration('lukas-reineke/indent-blankline.nvim') then
    hi('IndentBlanklineChar',         {fg=p.base02, bg=nil, attr='nocombine',           sp=nil})
    hi('IndentBlanklineContextChar',  {fg=p.base0F, bg=nil, attr='nocombine',           sp=nil})
    hi('IndentBlanklineContextStart', {fg=nil,      bg=nil, attr='underline,nocombine', sp=p.base0F})
    hi('IndentBlanklineIndent1',      {fg=p.base08, bg=nil, attr='nocombine',           sp=nil})
    hi('IndentBlanklineIndent2',      {fg=p.base09, bg=nil, attr='nocombine',           sp=nil})
    hi('IndentBlanklineIndent3',      {fg=p.base0A, bg=nil, attr='nocombine',           sp=nil})
    hi('IndentBlanklineIndent4',      {fg=p.base0B, bg=nil, attr='nocombine',           sp=nil})
    hi('IndentBlanklineIndent5',      {fg=p.base0C, bg=nil, attr='nocombine',           sp=nil})
    hi('IndentBlanklineIndent6',      {fg=p.base0D, bg=nil, attr='nocombine',           sp=nil})
    hi('IndentBlanklineIndent7',      {fg=p.base0E, bg=nil, attr='nocombine',           sp=nil})
    hi('IndentBlanklineIndent8',      {fg=p.base0F, bg=nil, attr='nocombine',           sp=nil})
  end

  if H.has_integration('MeanderingProgrammer/render-markdown.nvim') then
    hi('RenderMarkdownBullet',     {fg=p.base0E, bg=nil,      attr=nil, sp=nil})
    hi('RenderMarkdownChecked',    {link='DiagnosticOk'})
    hi('RenderMarkdownCode',       {fg=nil,      bg=p.base01, attr=nil, sp=nil})
    hi('RenderMarkdownCodeInline', {link='Normal'})
    hi('RenderMarkdownDash',       {fg=p.base0E, bg=nil,      attr=nil, sp=nil})
    hi('RenderMarkdownH1',         {fg=p.base09, bg=nil,      attr=nil, sp=nil})
    hi('RenderMarkdownH1Bg',       {fg=nil,      bg=p.base01, attr=nil, sp=nil})
    hi('RenderMarkdownH2',         {fg=p.base0A, bg=nil,      attr=nil, sp=nil})
    hi('RenderMarkdownH2Bg',       {fg=nil,      bg=p.base01, attr=nil, sp=nil})
    hi('RenderMarkdownH3',         {fg=p.base0B, bg=nil,      attr=nil, sp=nil})
    hi('RenderMarkdownH3Bg',       {fg=nil,      bg=p.base01, attr=nil, sp=nil})
    hi('RenderMarkdownH4',         {fg=p.base0C, bg=nil,      attr=nil, sp=nil})
    hi('RenderMarkdownH4Bg',       {fg=nil,      bg=p.base01, attr=nil, sp=nil})
    hi('RenderMarkdownH5',         {fg=p.base0D, bg=nil,      attr=nil, sp=nil})
    hi('RenderMarkdownH5Bg',       {fg=nil,      bg=p.base01, attr=nil, sp=nil})
    hi('RenderMarkdownH6',         {fg=p.base0F, bg=nil,      attr=nil, sp=nil})
    hi('RenderMarkdownH6Bg',       {fg=nil,      bg=p.base01, attr=nil, sp=nil})
    hi('RenderMarkdownTodo',       {link='Todo'})
    hi('RenderMarkdownUnchecked',  {link='DiagnosticWarn'})
  end

  if H.has_integration('neoclide/coc.nvim') then
    hi('CocCodeLens',             {link='LspCodeLens'})
    hi('CocDisabled',             {link='Comment'})
    hi('CocFadeOut',              {link='Comment'})
    hi('CocMarkdownLink',         {fg=p.base0F, bg=nil,      attr=nil, sp=nil})
    hi('CocMenuSel',              {fg=nil,      bg=p.base02, attr=nil, sp=nil})
    hi('CocNotificationProgress', {link='CocMarkdownLink'})
    hi('CocPumVirtualText',       {link='CocMarkdownLink'})
    hi('CocSearch',               {fg=p.base0A, bg=nil,      attr=nil, sp=nil})
    hi('CocSelectedText',         {fg=p.base08, bg=nil,      attr=nil, sp=nil})
  end

  -- NeogitOrg/neogit
  if H.has_integration('NeogitOrg/neogit') then
    hi('NeogitCommitViewHeader',    {link='Special'})
    hi('NeogitDiffAddHighlight',    {link='DiffAdd'})
    hi('NeogitDiffAdd',             {link='DiffAdd'})
    hi('NeogitDiffDeleteHighlight', {link='DiffDelete'})
    hi('NeogitDiffDelete',          {link='DiffDelete'})
    hi('NeogitFold',                {link='FoldColumn'})
    hi('NeogitHunkHeader',          {fg=p.base0D, bg=nil, attr=nil,    sp=nil})
    hi('NeogitHunkHeaderHighlight', {fg=p.base0D, bg=nil, attr='bold', sp=nil})
    hi('NeogitNotificationError',   {link='DiagnosticError'})
    hi('NeogitNotificationInfo',    {link='DiagnosticInfo'})
    hi('NeogitNotificationWarning', {link='DiagnosticWarn'})
  end

  -- nvim-lualine/lualine.nvim
  -- Everything works correctly out of the box

  if H.has_integration('nvim-neo-tree/neo-tree.nvim') then
    hi('NeoTreeDimText',              {fg=p.base03, bg=nil,      attr=nil,    sp=nil})
    hi('NeoTreeDotfile',              {fg=p.base04, bg=nil,      attr=nil,    sp=nil})
    hi('NeoTreeFadeText1',            {link='NeoTreeDimText'})
    hi('NeoTreeFadeText2',            {fg=p.base02, bg=nil,      attr=nil,    sp=nil})
    hi('NeoTreeGitAdded',             {fg=p.base0B, bg=nil,      attr=nil,    sp=nil})
    hi('NeoTreeGitConflict',          {fg=p.base08, bg=nil,      attr='bold', sp=nil})
    hi('NeoTreeGitDeleted',           {fg=p.base08, bg=nil,      attr=nil,    sp=nil})
    hi('NeoTreeGitModified',          {fg=p.base0E, bg=nil,      attr=nil,    sp=nil})
    hi('NeoTreeGitUnstaged',          {fg=p.base08, bg=nil,      attr=nil,    sp=nil})
    hi('NeoTreeGitUntracked',         {fg=p.base0A, bg=nil,      attr=nil,    sp=nil})
    hi('NeoTreeMessage',              {fg=p.base05, bg=p.base01, attr=nil,    sp=nil})
    hi('NeoTreeModified',             {fg=p.base07, bg=nil,      attr=nil,    sp=nil})
    hi('NeoTreeRootName',             {fg=p.base0D, bg=nil,      attr='bold', sp=nil})
    hi('NeoTreeTabInactive',          {fg=p.base04, bg=nil,      attr=nil,    sp=nil})
    hi('NeoTreeTabSeparatorActive',   {fg=p.base03, bg=p.base02, attr=nil,    sp=nil})
    hi('NeoTreeTabSeparatorInactive', {fg=p.base01, bg=p.base01, attr=nil,    sp=nil})
  end

  if H.has_integration('nvim-telescope/telescope.nvim') then
    hi('TelescopeBorder',         {fg=p.base0F, bg=nil,      attr=nil,    sp=nil})
    hi('TelescopeMatching',       {fg=p.base0A, bg=nil,      attr=nil,    sp=nil})
    hi('TelescopeMultiSelection', {fg=nil,      bg=p.base01, attr='bold', sp=nil})
    hi('TelescopeSelection',      {fg=nil,      bg=p.base01, attr='bold', sp=nil})
  end

  if H.has_integration('nvim-tree/nvim-tree.lua') then
    hi('NvimTreeExecFile',     {fg=p.base0B, bg=nil,      attr='bold',           sp=nil})
    hi('NvimTreeFolderIcon',   {fg=p.base03, bg=nil,      attr=nil,              sp=nil})
    hi('NvimTreeGitDeleted',   {fg=p.base08, bg=nil,      attr=nil,              sp=nil})
    hi('NvimTreeGitDirty',     {fg=p.base08, bg=nil,      attr=nil,              sp=nil})
    hi('NvimTreeGitMerge',     {fg=p.base0C, bg=nil,      attr=nil,              sp=nil})
    hi('NvimTreeGitNew',       {fg=p.base0A, bg=nil,      attr=nil,              sp=nil})
    hi('NvimTreeGitRenamed',   {fg=p.base0E, bg=nil,      attr=nil,              sp=nil})
    hi('NvimTreeGitStaged',    {fg=p.base0B, bg=nil,      attr=nil,              sp=nil})
    hi('NvimTreeImageFile',    {fg=p.base0E, bg=nil,      attr='bold',           sp=nil})
    hi('NvimTreeIndentMarker', {link='NvimTreeFolderIcon'})
    hi('NvimTreeOpenedFile',   {link='NvimTreeExecFile'})
    hi('NvimTreeRootFolder',   {link='NvimTreeGitRenamed'})
    hi('NvimTreeSpecialFile',  {fg=p.base0D, bg=nil,      attr='bold,underline', sp=nil})
    hi('NvimTreeSymlink',      {fg=p.base0F, bg=nil,      attr='bold',           sp=nil})
    hi('NvimTreeWindowPicker', {fg=p.base05, bg=p.base01, attr="bold",           sp=nil})
  end

  if H.has_integration('OXY2DEV/helpview.nvim') then
    hi('HelpviewHeading1',     {link='markdownH1'})
    hi('HelpviewHeading2',     {link='markdownH2'})
    hi('HelpviewHeading3',     {link='markdownH3'})
    hi('HelpviewHeading4',     {link='markdownH4'})
    hi('HelpviewMentionlink',  {fg=nil,      bg=nil, attr='underline', sp=nil})
    hi('HelpviewOptionlink',   {fg=p.base0D, bg=nil, attr='underline', sp=nil})
    hi('HelpviewTaglink',      {fg=p.base0A, bg=nil, attr='bold',      sp=nil})
    hi('HelpviewTitle',        {link='Title'})
  end

  if H.has_integration('OXY2DEV/markview.nvim') then
    hi('MarkviewPalette0',     {fg=p.base0E, bg=p.base00, attr=nil, sp=nil})
    hi('MarkviewPalette0Fg',   {fg=p.base0E, bg=nil,      attr=nil, sp=nil})
    hi('MarkviewPalette0Bg',   {fg=nil,      bg=p.base00, attr=nil, sp=nil})
    hi('MarkviewPalette0Sign', {fg=p.base0E, bg=nil,      attr=nil, sp=nil})
    hi('MarkviewPalette1',     {fg=p.base08, bg=p.base00, attr=nil, sp=nil})
    hi('MarkviewPalette1Fg',   {fg=p.base08, bg=nil,      attr=nil, sp=nil})
    hi('MarkviewPalette1Bg',   {fg=nil,      bg=p.base00, attr=nil, sp=nil})
    hi('MarkviewPalette1Sign', {fg=p.base08, bg=nil,      attr=nil, sp=nil})
    hi('MarkviewPalette2',     {fg=p.base09, bg=p.base00, attr=nil, sp=nil})
    hi('MarkviewPalette2Fg',   {fg=p.base09, bg=nil,      attr=nil, sp=nil})
    hi('MarkviewPalette2Bg',   {fg=nil,      bg=p.base00, attr=nil, sp=nil})
    hi('MarkviewPalette2Sign', {fg=p.base09, bg=nil,      attr=nil, sp=nil})
    hi('MarkviewPalette3',     {fg=p.base0A, bg=p.base00, attr=nil, sp=nil})
    hi('MarkviewPalette3Fg',   {fg=p.base0A, bg=nil,      attr=nil, sp=nil})
    hi('MarkviewPalette3Bg',   {fg=nil,      bg=p.base00, attr=nil, sp=nil})
    hi('MarkviewPalette3Sign', {fg=p.base0A, bg=nil,      attr=nil, sp=nil})
    hi('MarkviewPalette4',     {fg=p.base0B, bg=p.base00, attr=nil, sp=nil})
    hi('MarkviewPalette4Fg',   {fg=p.base0B, bg=nil,      attr=nil, sp=nil})
    hi('MarkviewPalette4Bg',   {fg=nil,      bg=p.base00, attr=nil, sp=nil})
    hi('MarkviewPalette4Sign', {fg=p.base0B, bg=nil,      attr=nil, sp=nil})
    hi('MarkviewPalette5',     {fg=p.base0C, bg=p.base00, attr=nil, sp=nil})
    hi('MarkviewPalette5Fg',   {fg=p.base0C, bg=nil,      attr=nil, sp=nil})
    hi('MarkviewPalette5Bg',   {fg=nil,      bg=p.base00, attr=nil, sp=nil})
    hi('MarkviewPalette5Sign', {fg=p.base0C, bg=nil,      attr=nil, sp=nil})
    hi('MarkviewPalette6',     {fg=p.base0D, bg=p.base00, attr=nil, sp=nil})
    hi('MarkviewPalette6Fg',   {fg=p.base0D, bg=nil,      attr=nil, sp=nil})
    hi('MarkviewPalette6Bg',   {fg=nil,      bg=p.base00, attr=nil, sp=nil})
    hi('MarkviewPalette6Sign', {fg=p.base0D, bg=nil,      attr=nil, sp=nil})
    hi('MarkviewPalette7',     {fg=p.base0F, bg=p.base00, attr=nil, sp=nil})
    hi('MarkviewPalette7Fg',   {fg=p.base0F, bg=nil,      attr=nil, sp=nil})
    hi('MarkviewPalette7Bg',   {fg=nil,      bg=p.base00, attr=nil, sp=nil})
    hi('MarkviewPalette7Sign', {fg=p.base0F, bg=nil,      attr=nil, sp=nil})
  end

  if H.has_integration('phaazon/hop.nvim') then
    hi('HopNextKey',   {fg=p.base0E, bg=nil, attr='bold,nocombine', sp=nil})
    hi('HopNextKey1',  {fg=p.base08, bg=nil, attr='bold,nocombine', sp=nil})
    hi('HopNextKey2',  {fg=p.base04, bg=nil, attr='bold,nocombine', sp=nil})
    hi('HopPreview',   {fg=p.base09, bg=nil, attr='bold,nocombine', sp=nil})
    hi('HopUnmatched', {link='Comment'})
  end

  if H.has_integration('rcarriga/nvim-dap-ui') then
    hi('DapUIScope',                   {link='Title'})
    hi('DapUIType',                    {link='Type'})
    hi('DapUIModifiedValue',           {fg=p.base0E, bg=nil, attr='bold', sp=nil})
    hi('DapUIDecoration',              {link='Title'})
    hi('DapUIThread',                  {link='String'})
    hi('DapUIStoppedThread',           {link='Title'})
    hi('DapUISource',                  {link='Directory'})
    hi('DapUILineNumber',              {link='Title'})
    hi('DapUIFloatBorder',             {link='SpecialChar'})
    hi('DapUIWatchesEmpty',            {link='ErrorMsg'})
    hi('DapUIWatchesValue',            {link='String'})
    hi('DapUIWatchesError',            {link='DiagnosticError'})
    hi('DapUIBreakpointsPath',         {link='Directory'})
    hi('DapUIBreakpointsInfo',         {link='DiagnosticInfo'})
    hi('DapUIBreakpointsCurrentLine',  {fg=p.base0B, bg=nil, attr='bold', sp=nil})
    hi('DapUIBreakpointsDisabledLine', {link='Comment'})
  end

  if H.has_integration('rcarriga/nvim-notify') then
    hi('NotifyDEBUGBorder', {fg=p.base03, bg=nil, attr=nil, sp=nil})
    hi('NotifyDEBUGIcon',   {link='NotifyDEBUGBorder'})
    hi('NotifyDEBUGTitle',  {link='NotifyDEBUGBorder'})
    hi('NotifyERRORBorder', {fg=p.base08, bg=nil, attr=nil, sp=nil})
    hi('NotifyERRORIcon',   {link='NotifyERRORBorder'})
    hi('NotifyERRORTitle',  {link='NotifyERRORBorder'})
    hi('NotifyINFOBorder',  {fg=p.base0C, bg=nil, attr=nil, sp=nil})
    hi('NotifyINFOIcon',    {link='NotifyINFOBorder'})
    hi('NotifyINFOTitle',   {link='NotifyINFOBorder'})
    hi('NotifyTRACEBorder', {fg=p.base0D, bg=nil, attr=nil, sp=nil})
    hi('NotifyTRACEIcon',   {link='NotifyTRACEBorder'})
    hi('NotifyTRACETitle',  {link='NotifyTRACEBorder'})
    hi('NotifyWARNBorder',  {fg=p.base0E, bg=nil, attr=nil, sp=nil})
    hi('NotifyWARNIcon',    {link='NotifyWARNBorder'})
    hi('NotifyWARNTitle',   {link='NotifyWARNBorder'})
  end

  if H.has_integration('rlane/pounce.nvim') then
    hi('PounceMatch',      {fg=p.base00, bg=p.base05, attr='bold,nocombine', sp=nil})
    hi('PounceGap',        {fg=p.base00, bg=p.base03, attr='bold,nocombine', sp=nil})
    hi('PounceAccept',     {fg=p.base00, bg=p.base08, attr='bold,nocombine', sp=nil})
    hi('PounceAcceptBest', {fg=p.base00, bg=p.base0B, attr='bold,nocombine', sp=nil})
  end

  if H.has_integration('romgrk/barbar.nvim') then
    hi('BufferCurrent',       {fg=p.base05, bg=p.base02, attr='bold', sp=nil})
    hi('BufferCurrentIcon',   {fg=nil,      bg=p.base02, attr=nil,    sp=nil})
    hi('BufferCurrentIndex',  {link='BufferCurrentIcon'})
    hi('BufferCurrentMod',    {fg=p.base08, bg=p.base02, attr='bold', sp=nil})
    hi('BufferCurrentSign',   {link='BufferCurrent'})
    hi('BufferCurrentTarget', {fg=p.base0E, bg=p.base02, attr='bold', sp=nil})

    hi('BufferInactive',       {fg=p.base04, bg=p.base01, attr=nil,    sp=nil})
    hi('BufferInactiveIcon',   {fg=nil,      bg=p.base01, attr=nil,    sp=nil})
    hi('BufferInactiveIndex',  {link='BufferInactiveIcon'})
    hi('BufferInactiveMod',    {fg=p.base08, bg=p.base01, attr=nil,    sp=nil})
    hi('BufferInactiveSign',   {link='BufferInactive'})
    hi('BufferInactiveTarget', {fg=p.base0E, bg=p.base01, attr='bold', sp=nil})

    hi('BufferOffset',      {link='Normal'})
    hi('BufferTabpages',    {fg=p.base01, bg=p.base0A, attr='bold', sp=nil})
    hi('BufferTabpageFill', {link='Normal'})

    hi('BufferVisible',       {fg=p.base05, bg=p.base01, attr='bold', sp=nil})
    hi('BufferVisibleIcon',   {fg=nil,      bg=p.base01, attr=nil,    sp=nil})
    hi('BufferVisibleIndex',  {link='BufferVisibleIcon'})
    hi('BufferVisibleMod',    {fg=p.base08, bg=p.base01, attr='bold', sp=nil})
    hi('BufferVisibleSign',   {link='BufferVisible'})
    hi('BufferVisibleTarget', {fg=p.base0E, bg=p.base01, attr='bold', sp=nil})
  end

  -- stevearc/aerial.nvim
  -- Everything works correctly out of the box

  if H.has_integration('williamboman/mason.nvim') then
    hi('MasonError',                       {fg=p.base08, bg=nil,      attr=nil,    sp=nil})
    hi('MasonHeader',                      {fg=p.base00, bg=p.base0D, attr='bold', sp=nil})
    hi('MasonHeaderSecondary',             {fg=p.base00, bg=p.base0F, attr='bold', sp=nil})
    hi('MasonHeading',                     {link='Bold'})
    hi('MasonHighlight',                   {fg=p.base0F, bg=nil,      attr=nil,    sp=nil})
    hi('MasonHighlightBlock',              {fg=p.base00, bg=p.base0F, attr=nil,    sp=nil})
    hi('MasonHighlightBlockBold',          {link='MasonHeaderSecondary'})
    hi('MasonHighlightBlockBoldSecondary', {link='MasonHeader'})
    hi('MasonHighlightBlockSecondary',     {fg=p.base00, bg=p.base0D, attr=nil,    sp=nil})
    hi('MasonHighlightSecondary',          {fg=p.base0D, bg=nil,      attr=nil,    sp=nil})
    hi('MasonLink',                        {link='MasonHighlight'})
    hi('MasonMuted',                       {link='Comment'})
    hi('MasonMutedBlock',                  {fg=p.base00, bg=p.base03, attr=nil,    sp=nil})
    hi('MasonMutedBlockBold',              {fg=p.base00, bg=p.base03, attr='bold', sp=nil})
  end
  -- stylua: ignore end

  -- Terminal colors
  vim.g.terminal_color_0 = palette.base00
  vim.g.terminal_color_1 = palette.base08
  vim.g.terminal_color_2 = palette.base0B
  vim.g.terminal_color_3 = palette.base0A
  vim.g.terminal_color_4 = palette.base0D
  vim.g.terminal_color_5 = palette.base0E
  vim.g.terminal_color_6 = palette.base0C
  vim.g.terminal_color_7 = palette.base05
  vim.g.terminal_color_8 = palette.base03
  vim.g.terminal_color_9 = palette.base08
  vim.g.terminal_color_10 = palette.base0B
  vim.g.terminal_color_11 = palette.base0A
  vim.g.terminal_color_12 = palette.base0D
  vim.g.terminal_color_13 = palette.base0E
  vim.g.terminal_color_14 = palette.base0C
  vim.g.terminal_color_15 = palette.base07
end

H.has_integration = function(name)
  local entry = MiniBase16.config.plugins[name]
  if entry == nil then return MiniBase16.config.plugins.default end
  return entry
end

H.highlight_gui = function(group, args)
  -- NOTE: using `string.format` instead of gradually growing string with `..`
  -- is faster. Crude estimate for this particular case: whole colorscheme
  -- loading decreased from ~3.6ms to ~3.0ms, i.e. by about 20%.
  local command
  if args.link ~= nil then
    command = string.format('highlight! link %s %s', group, args.link)
  else
    command = string.format(
      'highlight %s guifg=%s guibg=%s gui=%s guisp=%s blend=%s',
      group,
      args.fg or 'NONE',
      args.bg or 'NONE',
      args.attr or 'NONE',
      args.sp or 'NONE',
      args.blend or 'NONE'
    )
  end
  vim.cmd(command)
end

H.highlight_both = function(group, args)
  local command
  if args.link ~= nil then
    command = string.format('highlight! link %s %s', group, args.link)
  else
    command = string.format(
      'highlight %s guifg=%s ctermfg=%s guibg=%s ctermbg=%s gui=%s cterm=%s guisp=%s blend=%s',
      group,
      args.fg and args.fg.gui or 'NONE',
      args.fg and args.fg.cterm or 'NONE',
      args.bg and args.bg.gui or 'NONE',
      args.bg and args.bg.cterm or 'NONE',
      args.attr or 'NONE',
      args.attr or 'NONE',
      args.sp and args.sp.gui or 'NONE',
      args.blend or 'NONE'
    )
  end
  vim.cmd(command)
end

-- Compound (gui and cterm) palette -------------------------------------------
H.make_compound_palette = function(palette, use_cterm)
  local cterm_table = use_cterm
  if type(use_cterm) == 'boolean' then cterm_table = MiniBase16.rgb_palette_to_cterm_palette(palette) end

  local res = {}
  for name, _ in pairs(palette) do
    res[name] = { gui = palette[name], cterm = cterm_table[name] }
  end
  return res
end

-- Optimal scales. Make a set of equally spaced hues which are as different to
-- present hues as possible
H.make_different_hues = function(present_hues, n)
  local max_offset = math.floor(360 / n + 0.5)

  local dist, best_dist = nil, -math.huge
  local best_hues, new_hues

  for offset = 0, max_offset - 1, 1 do
    new_hues = H.make_hue_scale(n, offset)

    -- Compute distance as usual 'minimum distance' between two sets
    dist = H.dist_circle_set(new_hues, present_hues)

    -- Decide if it is the best
    if dist > best_dist then
      best_hues, best_dist = new_hues, dist
    end
  end

  return best_hues
end

H.make_hue_scale = function(n, offset)
  local step = math.floor(360 / n + 0.5)
  local res = {}
  for i = 0, n - 1, 1 do
    table.insert(res, (offset + i * step) % 360)
  end
  return res
end

-- Terminal colors ------------------------------------------------------------
-- Sources:
-- - https://github.com/shawncplus/Vim-toCterm/blob/master/lib/Xterm.php
-- - https://gist.github.com/MicahElliott/719710
-- stylua: ignore start
H.cterm_first16 = {
  { r = 0,   g = 0,   b = 0 },
  { r = 205, g = 0,   b = 0 },
  { r = 0,   g = 205, b = 0 },
  { r = 205, g = 205, b = 0 },
  { r = 0,   g = 0,   b = 238 },
  { r = 205, g = 0,   b = 205 },
  { r = 0,   g = 205, b = 205 },
  { r = 229, g = 229, b = 229 },
  { r = 127, g = 127, b = 127 },
  { r = 255, g = 0,   b = 0 },
  { r = 0,   g = 255, b = 0 },
  { r = 255, g = 255, b = 0 },
  { r = 92,  g = 92,  b = 255 },
  { r = 255, g = 0,   b = 255 },
  { r = 0,   g = 255, b = 255 },
  { r = 255, g = 255, b = 255 },
}
-- stylua: ignore end

H.cterm_basis = { 0, 95, 135, 175, 215, 255 }

H.cterm2rgb = function(i)
  if i < 16 then return H.cterm_first16[i + 1] end
  if 16 <= i and i <= 231 then
    i = i - 16
    local r = H.cterm_basis[math.floor(i / 36) % 6 + 1]
    local g = H.cterm_basis[math.floor(i / 6) % 6 + 1]
    local b = H.cterm_basis[i % 6 + 1]
    return { r = r, g = g, b = b }
  end
  if 232 <= i and i <= 255 then
    local c = 8 + (i - 232) * 10
    return { r = c, g = c, b = c }
  end
end

H.ensure_cterm_palette = function()
  if H.cterm_palette then return end
  H.cterm_palette = {}
  for i = 0, 255 do
    H.cterm_palette[i] = H.cterm2rgb(i)
  end
end

-- Color conversion -----------------------------------------------------------
-- Source: https://www.easyrgb.com/en/math.php
-- Accuracy is usually around 2-3 decimal digits, which should be fine

-- HEX <-> CIELCh(uv)
H.hex2lch = function(hex)
  local res = hex
  for _, f in pairs({ H.hex2rgb, H.rgb2xyz, H.xyz2luv, H.luv2lch }) do
    res = f(res)
  end
  return res
end

H.lch2hex = function(lch)
  local res = lch
  for _, f in pairs({ H.lch2luv, H.luv2xyz, H.xyz2rgb, H.rgb2hex }) do
    res = f(res)
  end
  return res
end

-- HEX <-> RGB
H.hex2rgb = function(hex)
  local dec = tonumber(hex:sub(2), 16)

  local b = math.fmod(dec, 256)
  local g = math.fmod((dec - b) / 256, 256)
  local r = math.floor(dec / 65536)

  return { r = r, g = g, b = b }
end

H.rgb2hex = function(rgb)
  -- Round and trim values
  local t = vim.tbl_map(function(x)
    x = math.min(math.max(x, 0), 255)
    return math.floor(x + 0.5)
  end, rgb)

  return '#' .. string.format('%02x', t.r) .. string.format('%02x', t.g) .. string.format('%02x', t.b)
end

-- RGB <-> XYZ
H.rgb2xyz = function(rgb)
  local t = vim.tbl_map(function(c)
    c = c / 255
    if c > 0.04045 then
      c = ((c + 0.055) / 1.055) ^ 2.4
    else
      c = c / 12.92
    end
    return 100 * c
  end, rgb)

  -- Source of better matrix: http://brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
  local x = 0.41246 * t.r + 0.35757 * t.g + 0.18043 * t.b
  local y = 0.21267 * t.r + 0.71515 * t.g + 0.07217 * t.b
  local z = 0.01933 * t.r + 0.11919 * t.g + 0.95030 * t.b
  return { x = x, y = y, z = z }
end

H.xyz2rgb = function(xyz)
  -- Source of better matrix: http://brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
  -- stylua: ignore start
  local r =  3.24045 * xyz.x - 1.53713 * xyz.y - 0.49853 * xyz.z
  local g = -0.96927 * xyz.x + 1.87601 * xyz.y + 0.04155 * xyz.z
  local b =  0.05564 * xyz.x - 0.20403 * xyz.y + 1.05722 * xyz.z
  -- stylua: ignore end

  return vim.tbl_map(function(c)
    c = c / 100
    if c > 0.0031308 then
      c = 1.055 * (c ^ (1 / 2.4)) - 0.055
    else
      c = 12.92 * c
    end
    return 255 * c
  end, {
    r = r,
    g = g,
    b = b,
  })
end

-- XYZ <-> CIELuv
-- Using white reference for D65 and 2 degrees
H.ref_u = (4 * 95.047) / (95.047 + (15 * 100) + (3 * 108.883))
H.ref_v = (9 * 100) / (95.047 + (15 * 100) + (3 * 108.883))

H.xyz2luv = function(xyz)
  local x, y, z = xyz.x, xyz.y, xyz.z
  if x + y + z == 0 then return { l = 0, u = 0, v = 0 } end

  local var_u = 4 * x / (x + 15 * y + 3 * z)
  local var_v = 9 * y / (x + 15 * y + 3 * z)
  local var_y = y / 100
  if var_y > 0.008856 then
    var_y = var_y ^ (1 / 3)
  else
    var_y = (7.787 * var_y) + (16 / 116)
  end

  local l = (116 * var_y) - 16
  local u = 13 * l * (var_u - H.ref_u)
  local v = 13 * l * (var_v - H.ref_v)
  return { l = l, u = u, v = v }
end

H.luv2xyz = function(luv)
  if luv.l == 0 then return { x = 0, y = 0, z = 0 } end

  local var_y = (luv.l + 16) / 116
  if var_y ^ 3 > 0.008856 then
    var_y = var_y ^ 3
  else
    var_y = (var_y - 16 / 116) / 7.787
  end

  local var_u = luv.u / (13 * luv.l) + H.ref_u
  local var_v = luv.v / (13 * luv.l) + H.ref_v

  local y = var_y * 100
  local x = -(9 * y * var_u) / ((var_u - 4) * var_v - var_u * var_v)
  local z = (9 * y - 15 * var_v * y - var_v * x) / (3 * var_v)
  return { x = x, y = y, z = z }
end

-- CIELuv <-> CIELCh(uv)
H.tau = 2 * math.pi

H.luv2lch = function(luv)
  local c = math.sqrt(luv.u ^ 2 + luv.v ^ 2)
  local h
  if c == 0 then
    h = 0
  else
    -- Convert [-pi, pi] radians to [0, 360] degrees
    h = (math.atan2(luv.v, luv.u) % H.tau) * 360 / H.tau
  end
  return { l = luv.l, c = c, h = h }
end

H.lch2luv = function(lch)
  local angle = lch.h * H.tau / 360
  local u = lch.c * math.cos(angle)
  local v = lch.c * math.sin(angle)
  return { l = lch.l, u = u, v = v }
end

-- Distances ------------------------------------------------------------------
H.dist_circle = function(x, y)
  local d = math.abs(x - y) % 360
  return d > 180 and (360 - d) or d
end

H.dist_circle_set = function(set1, set2)
  -- Minimum distance between all pairs
  local dist = math.huge
  local d
  for _, x in pairs(set1) do
    for _, y in pairs(set2) do
      d = H.dist_circle(x, y)
      if dist > d then dist = d end
    end
  end
  return dist
end

H.nearest_rgb_id = function(rgb_target, rgb_palette)
  local best_dist = math.huge
  local best_id, dist
  for id, rgb in pairs(rgb_palette) do
    dist = math.abs(rgb_target.r - rgb.r) + math.abs(rgb_target.g - rgb.g) + math.abs(rgb_target.b - rgb.b)
    if dist < best_dist then
      best_id, best_dist = id, dist
    end
  end

  return best_id
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.base16) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

return MiniBase16
