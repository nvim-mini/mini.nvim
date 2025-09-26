--- *mini.hues* Generate configurable color scheme
--- *MiniHues*
---
--- MIT License Copyright (c) 2023 Evgeni Chasnovski
---
--- ==============================================================================
---
--- Features:
--- - Required to set two base colors: background and foreground.
---   Their shades and other non-base colors are computed to be as much
---   perceptually different as reasonably possible.
---   See |MiniHues.config| for setup inspiration.
---
--- - Configurable:
---     - Number of hues used for non-base colors (from 0 to 8).
---     - Saturation level ("low", "lowmedium", "medium", "mediumhigh", "high").
---     - Accent color used for some selected UI elements.
---     - Plugin integration (can be selectively enabled for faster startup).
---
--- - Random generator for base colors. See |MiniHues.gen_random_base_colors()|.
---   Powers |randomhue| color scheme.
---
--- - Lua function to compute palette used in color scheme.
---   See |MiniHues.make_palette()|.
---
--- - Bundled color schemes. See |MiniHues-color-schemes|.
---
--- Supported highlight groups:
--- - All built-in UI and syntax groups.
---
--- - Built-in Neovim LSP and diagnostic.
---
--- - Tree-sitter (|treesitter-highlight-groups|).
---
--- - LSP semantic tokens (|lsp-semantic-highlight|).
---
--- - Plugins (either with explicit definition or by verification that default
---   highlighting works appropriately):
---     - 'nvim-mini/mini.nvim'
---     - 'akinsho/bufferline.nvim'
---     - 'anuvyklack/hydra.nvim'
---     - 'DanilaMihailov/beacon.nvim'
---     - 'folke/lazy.nvim'
---     - 'folke/noice.nvim'
---     - 'folke/todo-comments.nvim'
---     - 'folke/trouble.nvim'
---     - 'folke/which-key.nvim'
---     - 'ggandor/leap.nvim'
---     - 'glepnir/dashboard-nvim'
---     - 'glepnir/lspsaga.nvim'
---     - 'HiPhish/rainbow-delimiters.nvim'
---     - 'hrsh7th/nvim-cmp'
---     - 'ibhagwan/fzf-lua'
---     - 'justinmk/vim-sneak'
---     - 'kevinhwang91/nvim-bqf'
---     - 'kevinhwang91/nvim-ufo'
---     - 'lewis6991/gitsigns.nvim'
---     - 'lukas-reineke/indent-blankline.nvim'
---     - 'MeanderingProgrammer/render-markdown.nvim'
---     - 'neoclide/coc.nvim'
---     - 'NeogitOrg/neogit'
---     - 'nvim-lualine/lualine.nvim'
---     - 'nvim-neo-tree/neo-tree.nvim'
---     - 'nvim-telescope/telescope.nvim'
---     - 'nvim-tree/nvim-tree.lua'
---     - 'OXY2DEV/helpview.nvim'
---     - 'OXY2DEV/markview.nvim'
---     - 'phaazon/hop.nvim'
---     - 'rcarriga/nvim-dap-ui'
---     - 'rcarriga/nvim-notify'
---     - 'rlane/pounce.nvim'
---     - 'romgrk/barbar.nvim'
---     - 'stevearc/aerial.nvim'
---     - 'williamboman/mason.nvim'
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.hues').setup({})` and
--- **mandatory `background` and `foreground` fields** (add more fields to fit
--- your taste). It will create global Lua table `MiniHues` which you can use
--- for scripting or manually (with `:lua MiniHues.*`).
---
--- See |MiniHues.config| for `config` structure and default values.
---
--- This module doesn't have runtime options, so using `vim.b.minihues_config`
--- will have no effect here.
---
--- Example:
--- >
---   require('mini.hues').setup({
---     background = '#11262d',
---     foreground = '#c0c8cc',
---     plugins = {
---       default = false,
---       ['nvim-mini/mini.nvim'] = true,
---     },
---   })
--- <
--- # Notes ~
---
--- - This is used to create some of plugin's color schemes
---   (see |MiniHues-color-schemes|).
---
--- - Using `setup()` doesn't actually create a |colorscheme|. It basically
---   creates a coordinated set of |highlight|s. To create your own scheme:
---     - Put "myscheme.lua" file (name after your chosen theme name) inside
---       any "colors" directory reachable from 'runtimepath' ("colors" inside
---       your Neovim config directory is usually enough).
---     - Inside "myscheme.lua" call `require('mini.hues').setup()` with your
---       palette and only after that set |g:colors_name| to "myscheme".
---
--- - This module doesn't define |cterm-colors| for implementation simplicity.
---   Use |mini.colors| module, |MiniColors-colorscheme:add_cterm_attributes()|
---   in particular.

--- Bundled color schemes
---
--- - *miniwinter* : "icy winter" palette with azure background.
--- - *minispring* : "blooming spring" palette with green background.
--- - *minisummer* : "hot summer" palette with brown/yellow background.
--- - *miniautumn* : "cooling autumn" palette with purple background.
---
--- - *randomhue* : uses randomly generated same hue background and foreground.
---   Every `:colorscheme randomhue` call results in a different (randomly yet
---   carefully selected) colors.
---
---   It is essentially a combination of calls to |MiniHues.setup()| and
---   |MiniHues.gen_random_base_colors()| with a slight adjustments for
---   'background' value.
---
---   Activate it as regular |colorscheme|. Get currently active config with
---   `:lua print(vim.inspect(MiniHues.config))`.
---@tag MiniHues-color-schemes

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local

-- Module definition ==========================================================
local MiniHues = {}
local H = {}

--- Module setup
---
--- Main side effect is to create palette and apply it. Essentially, a combination
--- of |MiniHues.make_palette()| and |MiniHues.apply_palette()|.
---
---@usage >lua
---   require('mini.hues').setup({
---     -- Use config table as you like
---     -- Needs both `background` and `foreground` fields present
---     background = '#11262d',
---     foreground = '#c0c8cc',
---   })
--- <
MiniHues.setup = function(config)
  -- Export module
  _G.MiniHues = MiniHues

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)
end

--- Module config
---
--- See |MiniHues.make_palette()| for more information about how certain
--- settings affect output color scheme.
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text # Options ~
---
--- ## Plugin integrations ~
---
--- `config.plugins` defines for which supported plugins highlight groups will
--- be created. Limiting number of integrations slightly decreases startup time.
--- It is a table with boolean (`true`/`false`) values which are applied as follows:
--- - If plugin name (as listed in |mini.hues|) has entry, it is used.
--- - Otherwise `config.plugins.default` is used.
---
--- Example which will load only "mini.nvim" integration:
--- >
---   require('mini.hues').setup({
---     background = '#11262d',
---     foreground = '#c0c8cc',
---     plugins = {
---       default = false,
---       ['nvim-mini/mini.nvim'] = true,
---     },
---   })
---
--- # Examples ~
---
--- Here are some possible setup configurations (copy first line and then use
--- only one `setup` call): >
---
---   local setup = require('mini.hues').setup
---
---   -- Choose background and foreground
---   setup({ background = '#2f1c22', foreground = '#cdc4c6' }) -- red
---   setup({ background = '#2f1e16', foreground = '#cdc5c1' }) -- orange
---   setup({ background = '#282211', foreground = '#c9c6c0' }) -- yellow
---   setup({ background = '#1c2617', foreground = '#c4c8c2' }) -- green
---   setup({ background = '#112723', foreground = '#c0c9c7' }) -- cyan
---   setup({ background = '#11262d', foreground = '#c0c8cc' }) -- azure
---   setup({ background = '#1d2231', foreground = '#c4c6cd' }) -- blue
---   setup({ background = '#281e2c', foreground = '#c9c5cb' }) -- purple
---
---   -- Choose number of accent colors
---   setup({ background = '#11262d', foreground = '#c0c8cc', n_hues = 6 })
---   setup({ background = '#11262d', foreground = '#c0c8cc', n_hues = 4 })
---   setup({ background = '#11262d', foreground = '#c0c8cc', n_hues = 2 })
---   setup({ background = '#11262d', foreground = '#c0c8cc', n_hues = 0 })
---
---   -- Choose saturation of colored text
---   setup({ background = '#11262d', foreground = '#c0c8cc', saturation = 'low' })
---   setup({ background = '#11262d', foreground = '#c0c8cc', saturation = 'lowmedium' })
---   setup({ background = '#11262d', foreground = '#c0c8cc', saturation = 'medium' })
---   setup({ background = '#11262d', foreground = '#c0c8cc', saturation = 'mediumhigh' })
---   setup({ background = '#11262d', foreground = '#c0c8cc', saturation = 'high' })
---
---   -- Choose accent color
---   setup({ background = '#11262d', foreground = '#c0c8cc', accent = 'bg' })
---   setup({ background = '#11262d', foreground = '#c0c8cc', accent = 'red' })
---   setup({ background = '#11262d', foreground = '#c0c8cc', accent = 'yellow' })
---   setup({ background = '#11262d', foreground = '#c0c8cc', accent = 'cyan' })
---   setup({ background = '#11262d', foreground = '#c0c8cc', accent = 'blue' })
MiniHues.config = {
  -- **Required** base colors as '#rrggbb' hex strings
  background = nil,
  foreground = nil,

  -- Number of hues used for non-base colors
  n_hues = 8,

  -- Saturation. One of 'low', 'lowmedium', 'medium', 'mediumhigh', 'high'.
  saturation = 'medium',

  -- Accent color. One of: 'bg', 'fg', 'red', 'orange', 'yellow', 'green',
  -- 'cyan', 'azure', 'blue', 'purple'
  accent = 'bg',

  -- Plugin integrations. Use `default = false` to disable all integrations.
  -- Also can be set per plugin (see |MiniHues.config|).
  plugins = { default = true },
}
--minidoc_afterlines_end

--- Make palette
---
--- General idea of palette generation is that it is mostly based on color channel
--- information extracted from base colors (background and foreground).
---
--- All operations are done inside `Oklch` color space, meaning that each color
--- is defined by three numbers:
--- - Lightness (`l`) - number between 0 (black) and 100 (white) describing how
---   light is a color.
--- - Chroma (`c`) - positive number describing how colorful is a color (bigger
---   values - more colorful; 0 is gray).
--- - Hue (`h`) - periodic number in [0, 360) describing a value of "true color"
---   on color circle/wheel.
---
--- For more details about `Oklch` see |MiniColors-color-spaces| or
--- https://bottosson.github.io/posts/oklab/.
---
--- Algorithm overview ~
---
--- - Extract lightness, chroma, and hue of base colors.
---
--- - Generate reference lightness values:
---     - Background edge: 0 or 100, whichever is closest to background lightness.
---     - Foreground edge: 0 or 100, different from background edge.
---     - Middle: arithmetic mean of background and foreground lightness values.
---
--- - Compute background and foreground tints and shades by changing lightness
---   of background color: two colors closer to background lightness edge and
---   two closer to middle.
---
--- - Pick chroma value for non-base colors based on `config.saturation`.
---
--- - Generate hues for non-base colors:
---     - Fit an equidistant circular grid with `config.n_hues` points to be as
---       far from both background and foreground hues. This will ensure that
---       non-base colors are as different as possible from base ones (for
---       better visual perception).
---       Example: for background hue 0, foreground hue 180, and `config.n_hues` 2
---       the output grid will be `{ 90, 270 }`.
---
---     - For each hue of reference color (which itself is an equidistant grid
---       of 8 hues) compute the closest value from the grid. This allows
---       operating in same terms (like "red", "green") despite maybe actually
---       having less different hues.
---
--- - Compute for each hue two variants of non-base colors: with background and
---   foreground lightness values.
---
--- - Compute two variants of accent color (with background and foreground
---   lightness) based on `config.accent`.
---
--- Notes:
--- - Some output colors can have not exact values of generated Oklch channels.
---   This is due to actually computed colors being impossible to represent via
---   '#rrggbb' hex string. In this case a process called gamut clipping is done
---   to reduce lightness and chroma in optimal way while maintaining same hue.
---   For more information see |MiniColors-gamut-clip|.
---
--- - Not all colors are actually used in highlight groups and are present for the
---   sake of completeness.
---
---@param config table Configuration for palette. Same structure as |MiniHues.config|.
---   Needs to have <background> and <foreground> fields.
---
---@return table Palette with the following fields:
---   - <bg> and <fg> with supplied `background` and `foreground` colors.
---   - Fields like <bg_*> and <fg_*> are essentially <bg> and <fg> but with
---     different lightness values: `_edge`/`_edge2` - closer to edge lightness,
---     `_mid`/`_mid2` - closer to middle lightness.
---   - Fields for non-base colors (<red>, <orange>, <yellow>, <green>, <cyan>,
---     <azure>, <blue>, <purple>) have the same lightness as foreground.
---   - Fields for non-base colors with <_bg> suffix have the same lightness as
---     background.
---   - <accent> and <accent_bg> represent accent colors with foreground and
---     background lightness values.
---
---@seealso |MiniHues.get_palette()|
MiniHues.make_palette = function(config)
  config = vim.tbl_deep_extend('force', MiniHues.config, config or {})
  local bg = H.validate_hex(config.background, 'background')
  local fg = H.validate_hex(config.foreground, 'foreground')
  local n_hues = H.validate_n_hues(config.n_hues)
  local saturation = H.validate_one_of(config.saturation, H.saturation_values, 'saturation')
  local accent = H.validate_one_of(config.accent, H.accent_values, 'accent')

  local bg_lch, fg_lch = H.hex2oklch(bg), H.hex2oklch(fg)
  local bg_l, fg_l = bg_lch.l, fg_lch.l
  if not ((bg_l <= 50 and 50 < fg_l) or (fg_l <= 50 and 50 < bg_l)) then
    H.error('`background` and `foreground` should have opposite lightness.')
  end

  -- Reference lightness levels
  local is_dark = bg_l <= 50
  local l_bg_edge = is_dark and 0 or 100
  local l_fg_edge = is_dark and 100 or 0
  local l_mid = 0.5 * (bg_l + fg_l)

  -- Configurable chroma level
  local chroma = ({ low = 4, lowmedium = 6, medium = 8, mediumhigh = 12, high = 16 })[saturation]

  -- Hues
  local hues = H.make_hues(bg_lch.h, fg_lch.h, n_hues)

  -- Compute result
  --stylua: ignore
  local res = {
    -- `_edge`/`_mid` are third of the way towards reference (edge/middle)
    -- `_edge2`/`_mid2` are two thirds
    bg_edge2  = H.oklch2hex({ l = 0.33 * bg_l + 0.67 * l_bg_edge, c = bg_lch.c, h = bg_lch.h }),
    bg_edge   = H.oklch2hex({ l = 0.67 * bg_l + 0.33 * l_bg_edge, c = bg_lch.c, h = bg_lch.h }),
    bg        = bg,
    bg_mid    = H.oklch2hex({ l = 0.67 * bg_l + 0.33 * l_mid,     c = bg_lch.c, h = bg_lch.h }),
    bg_mid2   = H.oklch2hex({ l = 0.33 * bg_l + 0.67 * l_mid,     c = bg_lch.c, h = bg_lch.h }),

    fg_edge2  = H.oklch2hex({ l = 0.33 * fg_l + 0.67 * l_fg_edge, c = fg_lch.c, h = fg_lch.h }),
    fg_edge   = H.oklch2hex({ l = 0.67 * fg_l + 0.33 * l_fg_edge, c = fg_lch.c, h = fg_lch.h }),
    fg        = fg,
    fg_mid    = H.oklch2hex({ l = 0.67 * fg_l + 0.33 * l_mid,     c = fg_lch.c, h = fg_lch.h }),
    fg_mid2   = H.oklch2hex({ l = 0.33 * fg_l + 0.67 * l_mid,     c = fg_lch.c, h = fg_lch.h }),

    red       = H.oklch2hex({ l = fg_l, c = chroma, h = hues.red }),
    red_bg    = H.oklch2hex({ l = bg_l, c = chroma, h = hues.red }),

    orange    = H.oklch2hex({ l = fg_l, c = chroma, h = hues.orange }),
    orange_bg = H.oklch2hex({ l = bg_l, c = chroma, h = hues.orange }),

    yellow    = H.oklch2hex({ l = fg_l, c = chroma, h = hues.yellow }),
    yellow_bg = H.oklch2hex({ l = bg_l, c = chroma, h = hues.yellow }),

    green     = H.oklch2hex({ l = fg_l, c = chroma, h = hues.green }),
    green_bg  = H.oklch2hex({ l = bg_l, c = chroma, h = hues.green }),

    cyan      = H.oklch2hex({ l = fg_l, c = chroma, h = hues.cyan }),
    cyan_bg   = H.oklch2hex({ l = bg_l, c = chroma, h = hues.cyan }),

    azure     = H.oklch2hex({ l = fg_l, c = chroma, h = hues.azure }),
    azure_bg  = H.oklch2hex({ l = bg_l, c = chroma, h = hues.azure }),

    blue      = H.oklch2hex({ l = fg_l, c = chroma, h = hues.blue }),
    blue_bg   = H.oklch2hex({ l = bg_l, c = chroma, h = hues.blue }),

    purple    = H.oklch2hex({ l = fg_l, c = chroma, h = hues.purple }),
    purple_bg = H.oklch2hex({ l = bg_l, c = chroma, h = hues.purple }),
  }

  -- Manage 'bg' and 'fg' accents separately to ensure that corresponding
  -- background and foreground colors match exactly
  --stylua: ignore
  if accent == 'bg' then
    res.accent     = H.oklch2hex({ l = fg_l, c = chroma, h = bg_lch.h })
    res.accent_bg  = bg
  elseif accent == 'fg' then
    res.accent     = fg
    res.accent_bg  = H.oklch2hex({ l = bg_l, c = chroma, h = fg_lch.h })
  else
    res.accent     = H.oklch2hex({ l = fg_l, c = chroma, h = hues[accent] })
    res.accent_bg  = H.oklch2hex({ l = bg_l, c = chroma, h = hues[accent] })
  end

  return res
end

-- stylua: ignore
--- Apply palette
---
--- Create color scheme highlight groups and terminal colors based on supplied
--- palette. This is useful if you want to tweak palette colors.
--- For regular usage prefer |MiniHues.setup()|.
---
---@param palette table Table with structure as |MiniHues.make_palette()| output.
---@param plugins table|nil Table with boolean values indicating whether to create
---   highlight groups for specific plugins. See |MiniHues.config| for more details.
---   Default: the value from |MiniHues.config|.
---
---@usage >lua
---   local palette = require('mini.hues').make_palette({
---     background = '#11262d',
---     foreground = '#c0c8cc',
---   })
---   palette.cyan = '#76e0a6'
---   palette.cyan_bg = '#004629'
---   require('mini.hues').apply_palette(palette)
--- <
---@seealso |MiniHues.get_palette()|
MiniHues.apply_palette = function(palette, plugins)
  if type(palette) ~= 'table' then H.error('`palette` should be table with palette colors.') end
  plugins = plugins or MiniHues.config.plugins
  if type(plugins) ~= 'table' then H.error('`plugins` should be table with plugin integrations data.') end

  H.palette = vim.deepcopy(palette)

  -- Prepare highlighting application. Notes:
  -- - Clear current highlight only if other theme was loaded previously.
  -- - No need to `syntax reset` because *all* syntax groups are defined later.
  if vim.g.colors_name then vim.cmd('highlight clear') end

  -- As this doesn't create colorscheme, don't store any name. Not doing it
  -- might cause some issues with `syntax on`.
  vim.g.colors_name = nil

  local p = palette
  local hi = function(name, data) vim.api.nvim_set_hl(0, name, data) end
  local has_integration = function(name)
    local entry = plugins[name]
    if entry == nil then return plugins.default end
    return entry
  end

  -- NOTE: recommendations for adding new highlight groups:
  -- - Put all related groups (like for new plugin) in single paragraph.
  -- - Sort within group alphabetically (by hl-group name) ignoring case.
  -- - Link all repeated groups within paragraph (lowers execution time).
  -- - Align by commas.

  -- Builtin highlighting groups
  hi('ColorColumn',    { fg=nil,       bg=p.bg_mid2 })
  hi('ComplMatchIns',  { fg=nil,       bg=nil })
  hi('Conceal',        { fg=p.azure,   bg=nil })
  hi('CurSearch',      { fg=p.bg,      bg=p.yellow })
  hi('Cursor',         { fg=p.bg,      bg=p.fg })
  hi('CursorColumn',   { fg=nil,       bg=p.bg_mid })
  hi('CursorIM',       { link='Cursor' })
  hi('CursorLine',     { fg=nil,       bg=p.bg_mid })
  hi('CursorLineFold', { fg=p.bg_mid2, bg=nil })
  hi('CursorLineNr',   { fg=p.accent,  bg=nil,       bold=true })
  hi('CursorLineSign', { fg=p.bg_mid2, bg=nil })
  hi('DiffAdd',        { fg=nil,       bg=p.green_bg })
  hi('DiffChange',     { fg=nil,       bg=p.cyan_bg })
  hi('DiffDelete',     { fg=nil,       bg=p.red_bg })
  hi('DiffText',       { fg=nil,       bg=p.yellow_bg })
  hi('DiffTextAdd',    { link='DiffAdd' })
  hi('Directory',      { fg=p.azure,   bg=nil })
  hi('EndOfBuffer',    { fg=p.bg_mid2, bg=nil })
  hi('ErrorMsg',       { fg=p.red,     bg=nil })
  hi('FloatBorder',    { fg=p.accent,  bg=p.bg_edge })
  hi('FloatTitle',     { fg=p.accent,  bg=p.bg_edge, bold=true })
  hi('FoldColumn',     { fg=p.bg_mid2, bg=nil })
  hi('Folded',         { fg=p.fg_mid2, bg=p.bg_edge })
  hi('IncSearch',      { fg=p.bg,      bg=p.yellow })
  hi('lCursor',        { fg=p.bg,      bg=p.fg })
  hi('LineNr',         { fg=p.bg_mid2, bg=nil })
  hi('LineNrAbove',    { link='LineNr' })
  hi('LineNrBelow',    { link='LineNr' })
  hi('MatchParen',     { fg=nil,       bg=p.bg_mid2, bold=true })
  hi('ModeMsg',        { fg=p.green,   bg=nil })
  hi('MoreMsg',        { fg=p.azure,   bg=nil })
  hi('MsgArea',        { link='Normal' })
  hi('MsgSeparator',   { fg=p.fg_mid2, bg=p.bg_mid2 })
  hi('NonText',        { fg=p.bg_mid2, bg=nil })
  hi('Normal',         { fg=p.fg,      bg=p.bg })
  hi('NormalFloat',    { fg=p.fg,      bg=p.bg_edge })
  hi('NormalNC',       { link='Normal' })
  hi('OkMsg',          { fg=p.green,   bg=nil })
  hi('Pmenu',          { fg=p.fg,      bg=p.bg_mid })
  hi('PmenuExtra',     { link='Pmenu' })
  hi('PmenuExtraSel',  { link='PmenuSel' })
  hi('PmenuKind',      { link='Pmenu' })
  hi('PmenuKindSel',   { link='PmenuSel' })
  hi('PmenuMatch',     { fg=p.fg,      bg=p.bg_mid,  bold=true })
  hi('PmenuMatchSel',  { fg=nil,       bg=nil,       bold=true,   blend=0, reverse=true })
  hi('PmenuSbar',      { link='Pmenu' })
  hi('PmenuSel',       { fg=nil,       bg=nil,       blend=0,     reverse=true })
  hi('PmenuThumb',     { fg=nil,       bg=p.bg_mid2 })
  hi('Question',       { fg=p.azure,   bg=nil })
  hi('QuickFixLine',   { fg=nil,       bg=nil,       bold=true })
  hi('Search',         { fg=p.bg,      bg=p.accent })
  hi('SignColumn',     { fg=p.bg_mid2, bg=nil })
  hi('SpecialKey',     { fg=p.bg_mid2, bg=nil })
  hi('SpellBad',       { fg=nil,       bg=nil,       sp=p.red,    undercurl=true })
  hi('SpellCap',       { fg=nil,       bg=nil,       sp=p.cyan,   undercurl=true })
  hi('SpellLocal',     { fg=nil,       bg=nil,       sp=p.yellow, undercurl=true })
  hi('SpellRare',      { fg=nil,       bg=nil,       sp=p.blue,   undercurl=true })
  hi('StatusLine',     { fg=p.fg_mid,  bg=p.accent_bg })
  hi('StatusLineNC',   { fg=p.fg_mid,  bg=p.bg_edge })
  hi('StderrMsg',      { link='ErrorMsg' })
  hi('StdoutMsg',      { link='MsgArea' })
  hi('Substitute',     { fg=p.bg,      bg=p.blue })
  hi('TabLine',        { fg=p.fg_mid,  bg=p.bg_edge })
  hi('TabLineFill',    { link='Tabline' })
  hi('TabLineSel',     { fg=p.accent,  bg=p.bg_edge })
  hi('TermCursor',     { fg=nil,       bg=nil,       reverse=true })
  hi('TermCursorNC',   { fg=nil,       bg=nil,       reverse=true })
  hi('Title',          { fg=p.accent,  bg=nil })
  hi('VertSplit',      { fg=p.accent,  bg=nil })
  hi('Visual',         { fg=nil,       bg=p.bg_mid2 })
  hi('VisualNOS',      { fg=nil,       bg=p.bg_mid })
  hi('WarningMsg',     { fg=p.yellow,  bg=nil })
  hi('Whitespace',     { fg=p.bg_mid2, bg=nil })
  hi('WildMenu',       { link='PmenuSel' })
  hi('WinBar',         { link='StatusLine' })
  hi('WinBarNC',       { link='StatusLineNC' })
  hi('WinSeparator',   { fg=p.accent,  bg=nil })

  -- Standard syntax (affects treesitter)
  hi('Boolean',        { link='Constant' })
  hi('Character',      { link='Constant' })
  hi('Comment',        { fg=p.fg_mid2, bg=nil })
  hi('Conditional',    { link='Statement' })
  hi('Constant',       { fg=p.purple,  bg=nil })
  hi('Debug',          { link='Special' })
  hi('Define',         { link='PreProc' })
  hi('Delimiter',      { fg=p.orange,  bg=nil })
  hi('Error',          { fg=nil,       bg=p.red_bg })
  hi('Exception',      { link='Statement' })
  hi('Float',          { link='Constant' })
  hi('Function',       { fg=p.azure,   bg=nil })
  hi('Identifier',     { fg=p.yellow,  bg=nil })
  hi('Ignore',         { fg=nil,       bg=nil })
  hi('Include',        { link='PreProc' })
  hi('Keyword',        { link='Statement' })
  hi('Label',          { link='Statement' })
  hi('Macro',          { link='PreProc' })
  hi('Number',         { link='Constant' })
  hi('Operator',       { fg=p.fg,      bg=nil })
  hi('PreCondit',      { link='PreProc' })
  hi('PreProc',        { fg=p.blue,    bg=nil })
  hi('Repeat',         { link='Statement' })
  hi('Special',        { fg=p.cyan,    bg=nil })
  hi('SpecialChar',    { link='Special' })
  hi('SpecialComment', { link='Special' })
  hi('Statement',      { fg=p.fg,      bg=nil,         bold=true })
  hi('StorageClass',   { link='Type' })
  hi('String',         { fg=p.green,   bg=nil })
  hi('Structure',      { link='Type' })
  hi('Tag',            { link='Special' })
  hi('Todo',           { fg=p.accent,  bg=p.accent_bg, bold=true })
  hi('Type',           { fg=p.fg,      bg=nil })
  hi('Typedef',        { link='Type' })

  -- Other community standard
  hi('Bold',       { fg=nil, bg=nil, bold=true })
  hi('Italic',     { fg=nil, bg=nil, italic=true })
  hi('Underlined', { fg=nil, bg=nil, underline=true })

  -- Patch diff
  hi('diffAdded',   { fg=p.green,  bg=nil })
  hi('diffChanged', { fg=p.cyan,   bg=nil })
  hi('diffFile',    { fg=p.yellow, bg=nil })
  hi('diffLine',    { fg=p.blue,   bg=nil })
  hi('diffRemoved', { fg=p.red,    bg=nil })
  hi('Added',       { fg=p.green,  bg=nil })
  hi('Changed',     { fg=p.cyan,   bg=nil })
  hi('Removed',     { fg=p.red,    bg=nil })

  -- Git commit
  hi('gitcommitBranch',        { fg=p.orange, bg=nil, bold=true })
  hi('gitcommitComment',       { link='Comment' })
  hi('gitcommitDiscarded',     { link='Comment' })
  hi('gitcommitDiscardedFile', { fg=p.yellow, bg=nil, bold=true })
  hi('gitcommitDiscardedType', { fg=p.azure,  bg=nil })
  hi('gitcommitHeader',        { link='Title' })
  hi('gitcommitOverflow',      { fg=p.yellow, bg=nil })
  hi('gitcommitSelected',      { link='Comment' })
  hi('gitcommitSelectedFile',  { fg=p.green,  bg=nil, bold=true })
  hi('gitcommitSelectedType',  { link='gitcommitDiscardedType' })
  hi('gitcommitSummary',       { fg=p.green,  bg=nil })
  hi('gitcommitUnmergedFile',  { link='gitcommitDiscardedFile' })
  hi('gitcommitUnmergedType',  { link='gitcommitDiscardedType' })
  hi('gitcommitUntracked',     { link='Comment' })
  hi('gitcommitUntrackedFile', { fg=p.cyan,   bg=nil })

  -- Built-in diagnostic
  -- Logic:
  -- - Error is red.
  -- - Distance from hue to error hue should increase the less important it is
  --   (warning - info - ok - hint).
  hi('DiagnosticError', { fg=p.red,    bg=nil })
  hi('DiagnosticHint',  { fg=p.cyan,   bg=nil })
  hi('DiagnosticInfo',  { fg=p.blue,   bg=nil })
  hi('DiagnosticOk',    { fg=p.green,  bg=nil })
  hi('DiagnosticWarn',  { fg=p.yellow, bg=nil })

  hi('DiagnosticUnderlineError', { fg=nil, bg=nil, sp=p.red,    underline=true })
  hi('DiagnosticUnderlineHint',  { fg=nil, bg=nil, sp=p.cyan,   underline=true })
  hi('DiagnosticUnderlineInfo',  { fg=nil, bg=nil, sp=p.blue,   underline=true })
  hi('DiagnosticUnderlineOk',    { fg=nil, bg=nil, sp=p.green,  underline=true })
  hi('DiagnosticUnderlineWarn',  { fg=nil, bg=nil, sp=p.yellow, underline=true })

  hi('DiagnosticFloatingError', { fg=p.red,    bg=p.bg_edge })
  hi('DiagnosticFloatingHint',  { fg=p.cyan,   bg=p.bg_edge })
  hi('DiagnosticFloatingInfo',  { fg=p.blue,   bg=p.bg_edge })
  hi('DiagnosticFloatingOk',    { fg=p.green,  bg=p.bg_edge })
  hi('DiagnosticFloatingWarn',  { fg=p.yellow, bg=p.bg_edge })

  hi('DiagnosticVirtualTextError', { link='DiagnosticError' })
  hi('DiagnosticVirtualTextWarn',  { link='DiagnosticWarn' })
  hi('DiagnosticVirtualTextInfo',  { link='DiagnosticInfo' })
  hi('DiagnosticVirtualTextHint',  { link='DiagnosticHint' })
  hi('DiagnosticVirtualTextOk',    { link='DiagnosticOk' })

  hi('DiagnosticSignError', { link='DiagnosticError' })
  hi('DiagnosticSignWarn',  { link='DiagnosticWarn' })
  hi('DiagnosticSignInfo',  { link='DiagnosticInfo' })
  hi('DiagnosticSignHint',  { link='DiagnosticHint' })
  hi('DiagnosticSignOk',    { link='DiagnosticOk' })

  hi('DiagnosticDeprecated',  { fg=nil, bg=nil, sp=p.red, strikethrough=true })
  hi('DiagnosticUnnecessary', { link='Comment' })

  -- Built-in LSP
  hi('LspReferenceText',  { fg=nil, bg=p.bg_mid2 })
  hi('LspReferenceRead',  { link='LspReferenceText' })
  hi('LspReferenceWrite', { link='LspReferenceText' })

  hi('LspSignatureActiveParameter', { link='LspReferenceText' })

  hi('LspCodeLens',          { link='Comment' })
  hi('LspCodeLensSeparator', { link='Comment' })

  -- Built-in snippets
  hi('SnippetTabstop',       { fg=nil, bg=p.yellow_bg })
  hi('SnippetTabstopActive', { fg=nil, bg=p.green_bg })

  -- Built-in markdown syntax
  hi('markdownH1', { link='@markup.heading.1' })
  hi('markdownH2', { link='@markup.heading.2' })
  hi('markdownH3', { link='@markup.heading.3' })
  hi('markdownH4', { link='@markup.heading.4' })
  hi('markdownH5', { link='@markup.heading.5' })
  hi('markdownH6', { link='@markup.heading.6' })

  -- Tree-sitter
  -- Sources:
  -- - `:h treesitter-highlight-groups`
  -- - https://github.com/nvim-treesitter/nvim-treesitter/blob/master/CONTRIBUTING.md#highlights
  hi('@text.literal',   { link='Special' })
  hi('@text.reference', { link='Identifier' })
  hi('@text.title',     { link='Title' })
  hi('@text.uri',       { link='Underlined' })
  hi('@text.todo',      { link='Todo' })
  hi('@text.note',      { link='MoreMsg' })
  hi('@text.warning',   { link='WarningMsg' })
  hi('@text.danger',    { link='ErrorMsg' })
  hi('@text.strong',    { fg=nil, bg=nil, bold=true          })
  hi('@text.emphasis',  { fg=nil, bg=nil, italic=true        })
  hi('@text.strike',    { fg=nil, bg=nil, strikethrough=true })
  hi('@text.underline', { link='Underlined' })

  hi('@comment',     { link='Comment' })
  hi('@punctuation', { link='Delimiter' })

  hi('@constant',          { link='Constant' })
  hi('@constant.builtin',  { link='Special' })
  hi('@constant.macro',    { link='Macro' })
  hi('@define',            { link='Define' })
  hi('@macro',             { link='Macro' })
  hi('@string',            { link='String' })
  hi('@string.escape',     { link='SpecialChar' })
  hi('@string.special',    { link='SpecialChar' })
  hi('@character',         { link='Character' })
  hi('@character.special', { link='SpecialChar' })
  hi('@number',            { link='Number' })
  hi('@boolean',           { link='Boolean' })
  hi('@float',             { link='Float' })

  hi('@function',         { link='Function' })
  hi('@function.builtin', { link='Special' })
  hi('@function.call',    { link='Function' })
  hi('@function.macro',   { link='Macro' })
  hi('@parameter',        { fg=p.blue, bg=nil })
  hi('@method',           { link='Function' })
  hi('@method.call',      { link='Function' })
  hi('@field',            { link='Identifier' })
  hi('@property',         { link='Identifier' })
  hi('@constructor',      { link='Special' })

  hi('@conditional',    { link='Conditional' })
  hi('@repeat',         { link='Repeat' })
  hi('@label',          { link='Label' })
  hi('@operator',       { link='Operator' })
  hi('@keyword',        { link='Keyword' })
  hi('@keyword.return', { fg=p.orange, bg=nil, bold=true })
  hi('@exception',      { link='Exception' })

  hi('@variable',         { fg=p.fg, bg=nil })
  hi('@variable.builtin', { link='Special' })
  hi('@type',             { link='Type' })
  hi('@type.builtin',     { link='Special' })
  hi('@type.definition',  { link='Typedef' })
  hi('@storageclass',     { link='StorageClass' })
  hi('@structure',        { link='Structure' })
  hi('@namespace',        { link='Identifier' })
  hi('@include',          { link='Include' })
  hi('@preproc',          { link='PreProc' })
  hi('@debug',            { link='Debug' })
  hi('@tag',              { link='Tag' })

  hi('@symbol', { link='Keyword' })
  hi('@none',   {})

  -- Semantic tokens. Source: `:h lsp-semantic-highlight`.
  hi('@lsp.type.class',         { link='@structure' })
  hi('@lsp.type.decorator',     { link='@function' })
  hi('@lsp.type.enum',          { link='@type' })
  hi('@lsp.type.enumMember',    { link='@constant' })
  hi('@lsp.type.function',      { link='@function' })
  hi('@lsp.type.interface',     { link='@type' })
  hi('@lsp.type.macro',         { link='@macro' })
  hi('@lsp.type.method',        { link='@method' })
  hi('@lsp.type.namespace',     { link='@namespace' })
  hi('@lsp.type.parameter',     { link='@parameter' })
  hi('@lsp.type.property',      { link='@property' })
  hi('@lsp.type.struct',        { link='@structure' })
  hi('@lsp.type.type',          { link='@type' })
  hi('@lsp.type.typeParameter', { link='@type.definition' })
  hi('@lsp.type.variable',      { link='@variable' })

  hi('@lsp.mod.deprecated',     { fg=p.red, bg=nil })

  -- New tree-sitter groups
  if vim.fn.has('nvim-0.10') == 1 then
    -- Sources:
    -- - `:h treesitter-highlight-groups`
    -- - https://github.com/nvim-treesitter/nvim-treesitter/commit/1ae9b0e4558fe7868f8cda2db65239cfb14836d0
    -- NOTE: commented groups are the same as in Neovim<0.10 defined earlier

    -- @variable
    -- @variable.builtin
    hi('@variable.parameter', { link='@parameter' })
    hi('@variable.member',    { link='@field' })

    -- @constant
    -- @constant.builtin
    -- @constant.macro

    hi('@module',         { link='@namespace' })
    hi('@module.builtin', { link='@variable.builtin' })
    -- @label

    -- @string
    hi('@string.documentation',  { link='@string' })
    hi('@string.regexp',         { link='SpecialChar' })
    -- @string.escape
    -- @string.special
    hi('@string.special.symbol', { link='@constant' })
    hi('@string.special.path',   { link='Directory' })
    hi('@string.special.url',    { link='@markup.link.url' })
    hi('@string.special.vimdoc', { link='@constant' })

    -- @character
    -- @character.special

    -- @boolean
    -- @number
    hi('@number.float', { link='@float' })

    -- @type
    -- @type.builtin
    -- @type.definition
    hi('@type.qualifier', { link='StorageClass' })

    hi('@attribute', { link='Macro' })
    -- @property

    -- @function
    -- @function.builtin
    -- @function.call
    -- @function.macro

    hi('@function.method',      { link='@method' })
    hi('@function.method.call', { link='@method.call' })

    -- @constructor
    -- @operator

    -- @keyword
    hi('@keyword.coroutine', { link='@keyword' })
    hi('@keyword.function',  { link='@keyword' })
    hi('@keyword.operator',  { link='@keyword' })
    hi('@keyword.import',    { fg=p.blue, bg=nil, bold=true })
    hi('@keyword.storage',   { fg=p.fg,   bg=nil, bold=true })
    hi('@keyword.repeat',    { link='@keyword' })
    -- @keyword.return
    hi('@keyword.debug',     { fg=p.cyan, bg=nil, bold=true })
    hi('@keyword.exception', { link='@keyword' })

    hi('@keyword.conditional',         { link='@keyword' })
    hi('@keyword.conditional.ternary', { link='keyword' })

    hi('@keyword.directive',        { fg=p.blue, bg=nil, bold=true })
    hi('@keyword.directive.define', { link='@keyword.directive' })

    hi('@punctuation.delimiter', { link='@punctuation' })
    hi('@punctuation.bracket',   { link='@punctuation' })
    hi('@punctuation.special',   { link='Special' })

    -- @comment
    hi('@comment.documentation', { link='@comment' })

    hi('@comment.error',   { link='@text.danger' })
    hi('@comment.warning', { link='@text.warning' })
    hi('@comment.todo',    { link='@text.todo' })
    hi('@comment.note',    { link='@text.note' })

    hi('@markup.strong',        { link='@text.strong' })
    hi('@markup.italic',        { link='@text.emphasis' })
    hi('@markup.strikethrough', { link='@text.strike' })
    hi('@markup.underline',     { link='@text.underline' })

    hi('@markup.heading',   { link='@text.title' })
    hi('@markup.heading.1', { fg=p.orange, bg=nil })
    hi('@markup.heading.2', { fg=p.yellow, bg=nil })
    hi('@markup.heading.3', { fg=p.green,  bg=nil })
    hi('@markup.heading.4', { fg=p.cyan,   bg=nil })
    hi('@markup.heading.5', { fg=p.azure,  bg=nil })
    hi('@markup.heading.6', { fg=p.blue,   bg=nil })

    hi('@markup.heading.4.vimdoc', { link='Title' })

    hi('@markup.quote',       { link='@string.special' })
    hi('@markup.math',        { link='@string.special' })
    hi('@markup.environment', { link='@module' })

    hi('@markup.link',       { link='@text.reference' })
    hi('@markup.link.label', { link='@markup.link' })
    hi('@markup.link.url',   { fg=p.fg, bg=nil, underline=true })

    hi('@markup.raw',       { link='@text.literal' })
    hi('@markup.raw.block', { link='@markup.raw' })

    hi('@markup.list',           { link='@punctuation.special' })
    hi('@markup.list.checked',   { link='DiagnosticOk' })
    hi('@markup.list.unchecked', { link='DiagnosticWarn' })

    hi('@diff.plus',  { link='diffAdded' })
    hi('@diff.minus', { link='diffRemoved' })
    hi('@diff.delta', { link='diffChanged' })

    -- @tag
    hi('@tag.attribute', { link='@tag' })
    hi('@tag.delimiter', { link='@punctuation' })
  end

  -- Plugins
  -- nvim-mini/mini.nvim
  -- TODO: Remove 'echasnovski/mini.nvim' fallback after September 2026
  if has_integration('nvim-mini/mini.nvim') or has_integration('echasnovski/mini.nvim') then
    hi('MiniAnimateCursor',      { fg=nil, bg=nil, reverse=true, nocombine=true })
    hi('MiniAnimateNormalFloat', { link='NormalFloat' })

    hi('MiniClueBorder',              { link='FloatBorder' })
    hi('MiniClueDescGroup',           { link='DiagnosticFloatingWarn' })
    hi('MiniClueDescSingle',          { link='NormalFloat' })
    hi('MiniClueNextKey',             { link='DiagnosticFloatingHint' })
    hi('MiniClueNextKeyWithPostkeys', { link='DiagnosticFloatingError' })
    hi('MiniClueSeparator',           { link='DiagnosticFloatingInfo' })
    hi('MiniClueTitle',               { link='FloatTitle' })

    hi('MiniCompletionActiveParameter',    { link='LspSignatureActiveParameter' })
    hi('MiniCompletionDeprecated',         { link='DiagnosticDeprecated' })
    hi('MiniCompletionInfoBorderOutdated', { link='DiagnosticFloatingWarn' })

    hi('MiniCursorword',        { fg=nil, bg=nil, underline=true })
    hi('MiniCursorwordCurrent', { fg=nil, bg=nil, underline=true })

    hi('MiniDepsChangeAdded',   { link='diffAdded' })
    hi('MiniDepsChangeRemoved', { link='diffRemoved' })
    hi('MiniDepsHint',          { link='DiagnosticHint' })
    hi('MiniDepsInfo',          { link='DiagnosticInfo' })
    hi('MiniDepsMsgBreaking',   { link='DiagnosticWarn' })
    hi('MiniDepsPlaceholder',   { link='Comment' })
    hi('MiniDepsTitle',         { link='Title' })
    hi('MiniDepsTitleError',    { link='DiffDelete' })
    hi('MiniDepsTitleSame',     { link='DiffText' })
    hi('MiniDepsTitleUpdate',   { link='DiffAdd' })

    hi('MiniDiffSignAdd',        { link='diffAdded' })
    hi('MiniDiffSignChange',     { link='diffChanged' })
    hi('MiniDiffSignDelete',     { link='diffRemoved' })
    hi('MiniDiffOverAdd',        { link='DiffAdd' })
    hi('MiniDiffOverChange',     { link='DiffText' })
    hi('MiniDiffOverChangeBuf',  { link='MiniDiffOverChange' })
    hi('MiniDiffOverContext',    { link='DiffChange' })
    hi('MiniDiffOverContextBuf', {})
    hi('MiniDiffOverDelete',     { link='DiffDelete' })

    hi('MiniFilesBorder',         { link='FloatBorder' })
    hi('MiniFilesBorderModified', { link='DiagnosticFloatingWarn' })
    hi('MiniFilesCursorLine',     { link='CursorLine' })
    hi('MiniFilesDirectory',      { link='Directory'   })
    hi('MiniFilesFile',           { fg=p.fg, bg=nil })
    hi('MiniFilesNormal',         { link='NormalFloat' })
    hi('MiniFilesTitle',          { link='FloatTitle'  })
    hi('MiniFilesTitleFocused',   { fg=p.fg, bg=p.bg_edge, bold=true })

    hi('MiniHipatternsFixme', { fg=p.bg, bg=p.red,    bold=true })
    hi('MiniHipatternsHack',  { fg=p.bg, bg=p.yellow, bold=true })
    hi('MiniHipatternsNote',  { fg=p.bg, bg=p.cyan,   bold=true })
    hi('MiniHipatternsTodo',  { fg=p.bg, bg=p.blue,   bold=true })

    hi('MiniIconsAzure',  { fg=p.azure,   bg=nil })
    hi('MiniIconsBlue',   { fg=p.blue,    bg=nil })
    hi('MiniIconsCyan',   { fg=p.cyan,    bg=nil })
    hi('MiniIconsGreen',  { fg=p.green,   bg=nil })
    hi('MiniIconsGrey',   { fg=p.fg_edge, bg=nil })
    hi('MiniIconsOrange', { fg=p.orange,  bg=nil })
    hi('MiniIconsPurple', { fg=p.purple,  bg=nil })
    hi('MiniIconsRed',    { fg=p.red,     bg=nil })
    hi('MiniIconsYellow', { fg=p.yellow,  bg=nil })

    hi('MiniIndentscopeSymbol',    { fg=p.accent, bg=nil })
    hi('MiniIndentscopeSymbolOff', { fg=p.red,    bg=nil })

    hi('MiniJump', { fg=nil, bg=nil, sp=p.accent, undercurl=true })

    hi('MiniJump2dDim',        { fg=p.bg_mid2,  bg=nil })
    hi('MiniJump2dSpot',       { fg=p.fg_edge2, bg=p.bg_edge2, bold=true, nocombine=true })
    hi('MiniJump2dSpotAhead',  { fg=p.fg_edge,  bg=p.bg_edge2, nocombine=true })
    hi('MiniJump2dSpotUnique', { link='MiniJump2dSpot' })

    hi('MiniMapNormal',      { fg=p.fg_mid2, bg=p.bg_edge })
    hi('MiniMapSymbolCount', { fg=p.fg_mid2, bg=nil })
    hi('MiniMapSymbolLine',  { fg=p.accent,  bg=nil })
    hi('MiniMapSymbolView',  { fg=p.accent,  bg=nil })

    hi('MiniNotifyBorder',      { link='FloatBorder' })
    hi('MiniNotifyLspProgress', { link='MiniNotifyNormal' })
    hi('MiniNotifyNormal',      { link='NormalFloat' })
    hi('MiniNotifyTitle',       { link='FloatTitle' })

    hi('MiniOperatorsExchangeFrom', { link='IncSearch' })

    hi('MiniPickBorder',        { link='FloatBorder' })
    hi('MiniPickBorderBusy',    { link='DiagnosticFloatingWarn' })
    hi('MiniPickBorderText',    { link='FloatTitle' })
    hi('MiniPickCursor',        { blend=100, nocombine=true })
    hi('MiniPickIconDirectory', { link='Directory' })
    hi('MiniPickIconFile',      { link='MiniPickNormal' })
    hi('MiniPickHeader',        { link='DiagnosticFloatingHint' })
    hi('MiniPickMatchCurrent',  { link='CursorLine' })
    hi('MiniPickMatchMarked',   { link='Visual' })
    hi('MiniPickMatchRanges',   { link='DiagnosticFloatingHint' })
    hi('MiniPickNormal',        { link='NormalFloat' })
    hi('MiniPickPreviewLine',   { link='CursorLine' })
    hi('MiniPickPreviewRegion', { link='IncSearch' })
    hi('MiniPickPrompt',        { link='MiniPickMatchRanges' })
    hi('MiniPickPromptCaret',   { link='DiagnosticFloatingInfo' })
    hi('MiniPickPromptPrefix',  { link='DiagnosticFloatingInfo' })

    hi('MiniSnippetsCurrent',        { fg=nil, bg=nil, sp=p.yellow, underdouble=true })
    hi('MiniSnippetsCurrentReplace', { fg=nil, bg=nil, sp=p.red,    underdouble=true })
    hi('MiniSnippetsFinal',          { fg=nil, bg=nil, sp=p.green,  underdouble=true })
    hi('MiniSnippetsUnvisited',      { fg=nil, bg=nil, sp=p.cyan,   underdouble=true })
    hi('MiniSnippetsVisited',        { fg=nil, bg=nil, sp=p.blue,   underdouble=true })

    hi('MiniStarterCurrent',    { link='MiniStarterItem' })
    hi('MiniStarterFooter',     { link='Comment' })
    hi('MiniStarterHeader',     { fg=p.accent,  bg=nil, bold=true })
    hi('MiniStarterInactive',   { link='Comment' })
    hi('MiniStarterItem',       { fg=nil,       bg=nil })
    hi('MiniStarterItemBullet', { fg=p.fg_mid2, bg=nil })
    hi('MiniStarterItemPrefix', { fg=p.yellow,  bg=nil, bold=true })
    hi('MiniStarterSection',    { fg=p.purple,  bg=nil })
    hi('MiniStarterQuery',      { fg=p.green,   bg=nil, bold=true })

    hi('MiniStatuslineDevinfo',     { fg=p.fg_mid, bg=p.bg_mid })
    hi('MiniStatuslineFileinfo',    { link='MiniStatuslineDevinfo' })
    hi('MiniStatuslineFilename',    { fg=p.fg_mid, bg=p.accent_bg })
    hi('MiniStatuslineInactive',    { link='StatusLineNC' })
    hi('MiniStatuslineModeCommand', { fg=p.bg,     bg=p.yellow, bold=true })
    hi('MiniStatuslineModeInsert',  { fg=p.bg,     bg=p.azure,  bold=true })
    hi('MiniStatuslineModeNormal',  { fg=p.bg,     bg=p.fg,     bold=true })
    hi('MiniStatuslineModeOther',   { fg=p.bg,     bg=p.cyan,   bold=true })
    hi('MiniStatuslineModeReplace', { fg=p.bg,     bg=p.red,    bold=true })
    hi('MiniStatuslineModeVisual',  { fg=p.bg,     bg=p.green,  bold=true })

    hi('MiniSurround', { link='IncSearch' })

    hi('MiniTablineCurrent',         { fg=p.accent,  bg=p.bg,      bold=true })
    hi('MiniTablineFill',            { link='MiniTablineHidden' })
    hi('MiniTablineHidden',          { fg=p.fg_mid,  bg=p.bg_edge })
    hi('MiniTablineModifiedCurrent', { fg=p.bg,      bg=p.accent,  bold=true })
    hi('MiniTablineModifiedHidden',  { fg=p.bg_edge, bg=p.fg_mid })
    hi('MiniTablineModifiedVisible', { fg=p.bg_edge, bg=p.fg_mid,  bold=true })
    hi('MiniTablineTabpagesection',  { fg=p.bg,      bg=p.green,   bold=true })
    hi('MiniTablineTrunc',           { fg=p.accent,  bg=p.bg_edge, bold=true })
    hi('MiniTablineVisible',         { fg=p.fg_mid,  bg=p.bg_edge, bold=true })

    hi('MiniTestEmphasis', { fg=nil,     bg=nil, bold=true })
    hi('MiniTestFail',     { fg=p.red,   bg=nil, bold=true })
    hi('MiniTestPass',     { fg=p.green, bg=nil, bold=true })

    hi('MiniTrailspace', { fg=nil, bg=p.red_bg })
  end

  if has_integration('akinsho/bufferline.nvim') then
    hi('BufferLineBuffer',              { fg=p.fg_mid2, bg=nil })
    hi('BufferLineBufferSelected',      { fg=p.fg,      bg=nil,     bold=true })
    hi('BufferLineBufferVisible',       { fg=p.fg,      bg=nil })
    hi('BufferLineCloseButton',         { link='BufferLineBackground' })
    hi('BufferLineCloseButtonSelected', { link='BufferLineBufferSelected' })
    hi('BufferLineCloseButtonVisible',  { link='BufferLineBufferVisible' })
    hi('BufferLineFill',                { link='Normal' })
    hi('BufferLineTab',                 { fg=p.bg,      bg=p.green })
    hi('BufferLineTabSelected',         { fg=p.bg,      bg=p.green, bold=true })
  end

  if has_integration('anuvyklack/hydra.nvim') then
    hi('HydraRed',      { fg=p.red,    bg=nil })
    hi('HydraBlue',     { fg=p.azure,  bg=nil })
    hi('HydraAmaranth', { fg=p.purple, bg=nil })
    hi('HydraTeal',     { fg=p.cyan,   bg=nil })
    hi('HydraPink',     { fg=p.orange, bg=nil })
    hi('HydraHint',     { link='NormalFloat' })
  end

  if has_integration('DanilaMihailov/beacon.nvim') then
    hi('Beacon', { fg=nil, bg=p.fg_edge2 })
  end

  if has_integration('folke/lazy.nvim') then
    hi('LazyButton',       { fg=nil,      bg=p.bg_mid })
    hi('LazyButtonActive', { fg=nil,      bg=p.bg_mid2 })
    hi('LazyDimmed',       { link='Comment' })
    hi('LazyH1',           { fg=p.accent, bg=p.bg_mid2, bold=true })
  end

  if has_integration('folke/noice.nvim') then
    hi('NoiceCmdlinePopupBorder', { fg=p.azure,  bg=nil })
    hi('NoiceConfirmBorder',      { fg=p.yellow, bg=nil })
  end

  -- folke/trouble.nvim
  if has_integration('folke/trouble.nvim') then
    hi('TroubleCount',           { fg=p.accent,  bg=nil, bold=true })
    hi('TroubleFoldIcon',        { fg=p.accent,  bg=nil, bold=true })
    hi('TroubleIndent',          { fg=p.bg_mid2, bg=nil })
    hi('TroubleLocation',        { fg=p.fg_mid,  bg=nil })
    hi('TroubleSignError',       { link='DiagnosticError' })
    hi('TroubleSignHint',        { link='DiagnosticHint' })
    hi('TroubleSignInformation', { link='DiagnosticInfo' })
    hi('TroubleSignOther',       { link='DiagnosticInfo' })
    hi('TroubleSignWarning',     { link='DiagnosticWarn' })
    hi('TroubleText',            { fg=p.fg,      bg=nil })
    hi('TroubleTextError',       { link='TroubleText' })
    hi('TroubleTextHint',        { link='TroubleText' })
    hi('TroubleTextInformation', { link='TroubleText' })
    hi('TroubleTextWarning',     { link='TroubleText' })
  end

  -- folke/todo-comments.nvim
  -- Everything works correctly out of the box

  if has_integration('folke/which-key.nvim') then
    hi('WhichKey',          { fg=p.cyan,  bg=nil })
    hi('WhichKeyBorder',    { link='FloatBorder' })
    hi('WhichKeyDesc',      { fg=p.fg,    bg=nil })
    hi('WhichKeyFloat',     { fg=p.fg,    bg=p.bg_edge })
    hi('WhichKeyGroup',     { fg=p.red,   bg=nil })
    hi('WhichKeySeparator', { fg=p.green, bg=nil })
    hi('WhichKeyValue',     { link='Comment' })
  end

  if has_integration('ggandor/leap.nvim') then
    hi('LeapMatch',          { fg=p.green,  bg=nil, bold=true, nocombine=true, underline=true })
    hi('LeapLabel',          { fg=p.yellow, bg=nil, bold=true, nocombine=true })
    hi('LeapLabelSelected',  { fg=p.cyan,   bg=nil, bold=true, nocombine=true })
    hi('LeapBackdrop',       { link='Comment' })
  end

  if has_integration('glepnir/dashboard-nvim') then
    hi('DashboardCenter',   { link='Delimiter' })
    hi('DashboardFooter',   { link='Comment' })
    hi('DashboardHeader',   { link='Title' })
    hi('DashboardShortCut', { link='WarningMsg' })
  end

  if has_integration('glepnir/lspsaga.nvim') then
    hi('LspSagaCodeActionBorder',  { fg=p.accent, bg=nil })
    hi('LspSagaCodeActionContent', { fg=p.fg,     bg=nil })
    hi('LspSagaCodeActionTitle',   { fg=p.azure,  bg=nil, bold=true })

    hi('Definitions',            { fg=p.green,  bg=nil })
    hi('DefinitionsIcon',        { fg=p.azure,  bg=nil })
    hi('FinderParam',            { fg=p.yellow, bg=nil })
    hi('FinderVirtText',         { fg=p.orange, bg=nil })
    hi('LspSagaAutoPreview',     { fg=p.blue,   bg=nil })
    hi('LspSagaFinderSelection', { fg=p.cyan,   bg=nil })
    hi('LspSagaLspFinderBorder', { fg=p.accent, bg=nil })
    hi('References',             { fg=p.green,  bg=nil })
    hi('ReferencesIcon',         { fg=p.azure,  bg=nil })
    hi('TargetFileName',         { fg=p.fg,     bg=nil })

    hi('FinderSpinner',       { fg=p.green,  bg=nil })
    hi('FinderSpinnerBorder', { fg=p.accent, bg=nil })
    hi('FinderSpinnerTitle',  { link='Title' })

    hi('LspSagaDefPreviewBorder', { fg=p.accent, bg=nil })

    hi('LspSagaHoverBorder', { fg=p.accent, bg=nil })

    hi('LspSagaRenameBorder', { fg=p.accent, bg=nil })

    hi('LspSagaDiagnosticBorder', { fg=p.accent, bg=nil })
    hi('LspSagaDiagnosticHeader', { link='Title' })
    hi('LspSagaDiagnosticSource', { fg=p.orange, bg=nil })

    hi('LspSagaBorderTitle', { link='FloatTitle' })

    hi('LspSagaSignatureHelpBorder', { fg=p.accent, bg=nil })

    hi('LSOutlinePreviewBorder', { fg=p.accent,  bg=nil })
    hi('OutlineDetail',          { fg=p.bg_mid2, bg=nil })
    hi('OutlineFoldPrefix',      { fg=p.yellow,  bg=nil })
    hi('OutlineIndentEvn',       { fg=p.fg_mid2, bg=nil })
    hi('OutlineIndentOdd',       { fg=p.fg,      bg=nil })
  end

  if has_integration('HiPhish/rainbow-delimiters.nvim') then
    hi('RainbowDelimiterBlue',   { fg=p.azure,  bg=nil })
    hi('RainbowDelimiterCyan',   { fg=p.cyan,   bg=nil })
    hi('RainbowDelimiterGreen',  { fg=p.green,  bg=nil })
    hi('RainbowDelimiterOrange', { fg=p.orange, bg=nil })
    hi('RainbowDelimiterRed',    { fg=p.red,    bg=nil })
    hi('RainbowDelimiterViolet', { fg=p.purple, bg=nil })
    hi('RainbowDelimiterYellow', { fg=p.yellow, bg=nil })
  end

  if has_integration('hrsh7th/nvim-cmp') then
    hi('CmpItemAbbr',           { fg=p.fg, bg=nil })
    hi('CmpItemAbbrDeprecated', { link='Comment' })
    hi('CmpItemAbbrMatch',      { fg=nil,  bg=nil, bold=true })
    hi('CmpItemAbbrMatchFuzzy', { fg=nil,  bg=nil, bold=true })
    hi('CmpItemKind',           { fg=p.fg, bg=nil })
    hi('CmpItemMenu',           { fg=p.fg, bg=nil })

    hi('CmpItemKindClass',         { link='Type' })
    hi('CmpItemKindColor',         { link='Special' })
    hi('CmpItemKindConstant',      { link='Constant' })
    hi('CmpItemKindConstructor',   { link='Type' })
    hi('CmpItemKindEnum',          { link='Structure' })
    hi('CmpItemKindEnumMember',    { link='Structure' })
    hi('CmpItemKindEvent',         { link='Exception' })
    hi('CmpItemKindField',         { link='Structure' })
    hi('CmpItemKindFile',          { link='Tag' })
    hi('CmpItemKindFolder',        { link='Directory' })
    hi('CmpItemKindFunction',      { link='Function' })
    hi('CmpItemKindInterface',     { link='Structure' })
    hi('CmpItemKindKeyword',       { link='Keyword' })
    hi('CmpItemKindMethod',        { link='Function' })
    hi('CmpItemKindModule',        { link='Structure' })
    hi('CmpItemKindOperator',      { link='Operator' })
    hi('CmpItemKindProperty',      { link='Structure' })
    hi('CmpItemKindReference',     { link='Tag' })
    hi('CmpItemKindSnippet',       { link='Special' })
    hi('CmpItemKindStruct',        { link='Structure' })
    hi('CmpItemKindText',          { link='Normal' })
    hi('CmpItemKindTypeParameter', { link='Type' })
    hi('CmpItemKindUnit',          { link='Special' })
    hi('CmpItemKindValue',         { link='Identifier' })
    hi('CmpItemKindVariable',      { link='Delimiter' })
  end

  if has_integration('ibhagwan/fzf-lua') then
    hi('FzfLuaBufFlagAlt', { link='Special' })
    hi('FzfLuaBufFlagCur', { link='CursorLineNr' })
    hi('FzfLuaBufNr',      { link='DiagnosticHint' })
    hi('FzfLuaHeaderBind', { link='DiagnosticWarn' })
    hi('FzfLuaHeaderText', { link='DiagnosticInfo' })
    hi('FzfLuaLiveSym',    { link='DiagnosticHint' })
    hi('FzfLuaPathColNr',  { link='DiagnosticHint' })
    hi('FzfLuaPathLineNr', { link='DiagnosticInfo' })
    hi('FzfLuaTabMarker',  { link='DiagnosticHint' })
    hi('FzfLuaTabTitle',   { link='Title' })
    hi('FzfLuaTitle',      { link='FloatTitle' })
  end

  if has_integration('justinmk/vim-sneak') then
    hi('Sneak',      { fg=p.bg, bg=p.orange })
    hi('SneakScope', { fg=p.bg, bg=p.fg_edge2 })
    hi('SneakLabel', { fg=p.bg, bg=p.orange, bold=true })
  end

  -- 'kevinhwang91/nvim-bqf'
  if has_integration('kevinhwang91/nvim-bqf') then
    hi('BqfPreviewFloat', { link='NormalFloat' })
    hi('BqfPreviewTitle', { link='FloatTitle' })
    hi('BqfSign',         { fg=p.cyan })
  end

  -- 'kevinhwang91/nvim-ufo'
  -- Everything works correctly out of the box

  if has_integration('lewis6991/gitsigns.nvim') then
    hi('GitSignsAdd',             { fg=p.green,  bg=nil })
    hi('GitSignsAddLn',           { link='GitSignsAdd' })
    hi('GitSignsAddInline',       { link='GitSignsAdd' })

    hi('GitSignsChange',          { fg=p.yellow, bg=nil })
    hi('GitSignsChangeLn',        { link='GitSignsChange' })
    hi('GitSignsChangeInline',    { link='GitSignsChange' })

    hi('GitSignsDelete',          { fg=p.red,    bg=nil })
    hi('GitSignsDeleteLn',        { link='GitSignsDelete' })
    hi('GitSignsDeleteInline',    { link='GitSignsDelete' })

    hi('GitSignsUntracked',       { fg=p.azure,  bg=nil })
    hi('GitSignsUntrackedLn',     { link='GitSignsUntracked' })
    hi('GitSignsUntrackedInline', { link='GitSignsUntracked' })
  end

  if has_integration('lukas-reineke/indent-blankline.nvim') then
    hi('IndentBlanklineChar',         { fg=p.bg_mid2, bg=nil, nocombine=true })
    hi('IndentBlanklineContextChar',  { fg=p.accent,  bg=nil, nocombine=true })
    hi('IndentBlanklineContextStart', { fg=nil,       bg=nil, sp=p.accent, underline=true, nocombine=true })
    hi('IndentBlanklineIndent1',      { fg=p.blue,    bg=nil, nocombine=true })
    hi('IndentBlanklineIndent2',      { fg=p.cyan,    bg=nil, nocombine=true })
    hi('IndentBlanklineIndent3',      { fg=p.yellow,  bg=nil, nocombine=true })
    hi('IndentBlanklineIndent4',      { fg=p.red,     bg=nil, nocombine=true })
    hi('IndentBlanklineIndent5',      { fg=p.azure,   bg=nil, nocombine=true })
    hi('IndentBlanklineIndent6',      { fg=p.green,   bg=nil, nocombine=true })
    hi('IndentBlanklineIndent7',      { fg=p.orange,  bg=nil, nocombine=true })
    hi('IndentBlanklineIndent8',      { fg=p.purple,  bg=nil, nocombine=true })
  end

  if has_integration('MeanderingProgrammer/render-markdown.nvim') then
    hi('RenderMarkdownBullet',     { fg=p.accent, bg=nil })
    hi('RenderMarkdownChecked',    { link='DiagnosticOk' })
    hi('RenderMarkdownCode',       { fg=nil,      bg=p.bg_edge })
    hi('RenderMarkdownCodeInline', { fg=nil,      bg=p.bg_edge })
    hi('RenderMarkdownDash',       { fg=p.accent, bg=nil })
    hi('RenderMarkdownH1',         { fg=p.orange, bg=nil })
    hi('RenderMarkdownH1Bg',       { fg=nil,      bg=p.orange_bg })
    hi('RenderMarkdownH2',         { fg=p.yellow, bg=nil })
    hi('RenderMarkdownH2Bg',       { fg=nil,      bg=p.yellow_bg })
    hi('RenderMarkdownH3',         { fg=p.green,  bg=nil })
    hi('RenderMarkdownH3Bg',       { fg=nil,      bg=p.green_bg })
    hi('RenderMarkdownH4',         { fg=p.cyan,   bg=nil })
    hi('RenderMarkdownH4Bg',       { fg=nil,      bg=p.cyan_bg })
    hi('RenderMarkdownH5',         { fg=p.azure,  bg=nil })
    hi('RenderMarkdownH5Bg',       { fg=nil,      bg=p.azure_bg })
    hi('RenderMarkdownH6',         { fg=p.blue,   bg=nil })
    hi('RenderMarkdownH6Bg',       { fg=nil,      bg=p.blue_bg })
    hi('RenderMarkdownTodo',       { link='Todo' })
    hi('RenderMarkdownUnchecked',  { link='DiagnosticWarn' })
  end

  if has_integration('neoclide/coc.nvim') then
    hi('CocCodeLens',             { link='LspCodeLens' })
    hi('CocDisabled',             { link='Comment' })
    hi('CocFadeOut',              { link='Comment' })
    hi('CocMarkdownLink',         { fg=p.blue,   bg=nil })
    hi('CocMenuSel',              { fg=nil,      bg=p.bg_mid2 })
    hi('CocNotificationProgress', { link='CocMarkdownLink' })
    hi('CocPumVirtualText',       { link='CocMarkdownLink' })
    hi('CocSearch',               { fg=p.blue,   bg=nil })
    hi('CocSelectedText',         { fg=p.yellow, bg=nil })
  end

  -- NeogitOrg/neogit
  if has_integration('NeogitOrg/neogit') then
    hi('NeogitCommitViewHeader',    { link='Special' })
    hi('NeogitDiffAddHighlight',    { link='DiffAdd' })
    hi('NeogitDiffAdd',             { link='DiffAdd' })
    hi('NeogitDiffDeleteHighlight', { link='DiffDelete' })
    hi('NeogitDiffDelete',          { link='DiffDelete' })
    hi('NeogitFold',                { link='FoldColumn' })
    hi('NeogitHunkHeader',          { fg=p.accent, bg=nil })
    hi('NeogitHunkHeaderHighlight', { fg=p.accent, bg=nil, bold=true })
    hi('NeogitNotificationError',   { link='DiagnosticError' })
    hi('NeogitNotificationInfo',    { link='DiagnosticInfo' })
    hi('NeogitNotificationWarning', { link='DiagnosticWarn' })
  end

  -- nvim-lualine/lualine.nvim
  -- Everything works correctly out of the box

  if has_integration('nvim-neo-tree/neo-tree.nvim') then
    hi('NeoTreeDimText',              { fg=p.bg_mid2, bg=nil })
    hi('NeoTreeDotfile',              { fg=p.fg_mid,  bg=nil })
    hi('NeoTreeFadeText1',            { link='NeoTreeDimText' })
    hi('NeoTreeFadeText2',            { fg=p.bg_mid2, bg=nil })
    hi('NeoTreeGitAdded',             { fg=p.green,   bg=nil })
    hi('NeoTreeGitConflict',          { fg=p.orange,  bg=nil, bold=true })
    hi('NeoTreeGitDeleted',           { fg=p.red,     bg=nil })
    hi('NeoTreeGitModified',          { fg=p.yellow,  bg=nil })
    hi('NeoTreeGitUnstaged',          { fg=p.purple,  bg=nil })
    hi('NeoTreeGitUntracked',         { fg=p.cyan,    bg=nil })
    hi('NeoTreeMessage',              { fg=p.fg,      bg=p.bg_mid })
    hi('NeoTreeModified',             { fg=p.fg_edge, bg=nil })
    hi('NeoTreeRootName',             { fg=p.accent,  bg=nil, bold=true })
    hi('NeoTreeTabInactive',          { fg=p.fg_mid2, bg=nil })
    hi('NeoTreeTabSeparatorActive',   { fg=p.fg_mid2, bg=p.bg_mid2 })
    hi('NeoTreeTabSeparatorInactive', { fg=p.bg_mid,  bg=p.bg_mid })
  end

  if has_integration('nvim-telescope/telescope.nvim') then
    hi('TelescopeBorder',         { fg=p.accent, bg=nil })
    hi('TelescopeMatching',       { fg=nil,      bg=nil, bold=true })
    hi('TelescopeMultiSelection', { fg=nil,      bg=p.bg_mid2 })
    hi('TelescopeSelection',      { fg=nil,      bg=p.bg_mid })
  end

  if has_integration('nvim-tree/nvim-tree.lua') then
    hi('NvimTreeExecFile',     { fg=p.green,   bg=nil,       bold=true })
    hi('NvimTreeFolderIcon',   { fg=p.fg_mid2, bg=nil })
    hi('NvimTreeGitDeleted',   { fg=p.red,     bg=nil })
    hi('NvimTreeGitDirty',     { fg=p.yellow,  bg=nil })
    hi('NvimTreeGitMerge',     { fg=p.orange,  bg=nil })
    hi('NvimTreeGitNew',       { fg=p.cyan,    bg=nil })
    hi('NvimTreeGitRenamed',   { fg=p.purple,  bg=nil })
    hi('NvimTreeGitStaged',    { fg=p.green,   bg=nil })
    hi('NvimTreeImageFile',    { fg=p.orange,  bg=nil })
    hi('NvimTreeIndentMarker', { link='NvimTreeFolderIcon' })
    hi('NvimTreeOpenedFile',   { link='NvimTreeExecFile' })
    hi('NvimTreeRootFolder',   { fg=p.accent,  bg=nil,       bold=true })
    hi('NvimTreeSpecialFile',  { fg=p.accent,  bg=nil,       underline=true })
    hi('NvimTreeSymlink',      { fg=p.blue,    bg=nil,       bold=true })
    hi('NvimTreeWindowPicker', { fg=p.fg,      bg=p.bg_mid2, bold=true })
  end

  if has_integration('OXY2DEV/helpview.nvim') then
    hi('HelpviewCode',         { fg=nil,      bg=p.bg_edge })
    hi('HelpviewCodeLanguage', { fg=nil,      bg=p.bg_edge })
    hi('HelpviewHeading1',     { link='@markup.heading.1' })
    hi('HelpviewHeading2',     { link='@markup.heading.2' })
    hi('HelpviewHeading3',     { link='@markup.heading.3' })
    hi('HelpviewHeading4',     { link='@markup.heading.4' })
    hi('HelpviewInlineCode',   { fg=nil,      bg=p.bg_edge })
    hi('HelpviewMentionlink',  { fg=p.accent, bg=nil,      underline=true })
    hi('HelpviewOptionlink',   { fg=p.yellow, bg=nil,      underline=true })
    hi('HelpviewTaglink',      { fg=p.accent, bg=nil,      bold=true })
    hi('HelpviewTitle',        { link='Title' })
  end

  if has_integration('OXY2DEV/markview.nvim') then
    hi('MarkviewPalette0',     { fg=p.accent, bg=p.accent_bg })
    hi('MarkviewPalette0Fg',   { fg=p.accent, bg=nil })
    hi('MarkviewPalette0Bg',   { fg=nil,      bg=p.accent_bg })
    hi('MarkviewPalette0Sign', { fg=p.accent, bg=nil })
    hi('MarkviewPalette1',     { fg=p.red,    bg=p.red_bg })
    hi('MarkviewPalette1Fg',   { fg=p.red,    bg=nil })
    hi('MarkviewPalette1Bg',   { fg=nil,      bg=p.red_bg })
    hi('MarkviewPalette1Sign', { fg=p.red,    bg=nil })
    hi('MarkviewPalette2',     { fg=p.orange, bg=p.orange_bg })
    hi('MarkviewPalette2Fg',   { fg=p.orange, bg=nil })
    hi('MarkviewPalette2Bg',   { fg=nil,      bg=p.orange_bg })
    hi('MarkviewPalette2Sign', { fg=p.orange, bg=nil })
    hi('MarkviewPalette3',     { fg=p.yellow, bg=p.yellow_bg })
    hi('MarkviewPalette3Fg',   { fg=p.yellow, bg=nil })
    hi('MarkviewPalette3Bg',   { fg=nil,      bg=p.yellow_bg })
    hi('MarkviewPalette3Sign', { fg=p.yellow, bg=nil })
    hi('MarkviewPalette4',     { fg=p.green,  bg=p.green_bg })
    hi('MarkviewPalette4Fg',   { fg=p.green,  bg=nil })
    hi('MarkviewPalette4Bg',   { fg=nil,      bg=p.green_bg })
    hi('MarkviewPalette4Sign', { fg=p.green,  bg=nil })
    hi('MarkviewPalette5',     { fg=p.cyan,   bg=p.cyan_bg })
    hi('MarkviewPalette5Fg',   { fg=p.cyan,   bg=nil })
    hi('MarkviewPalette5Bg',   { fg=nil,      bg=p.cyan_bg })
    hi('MarkviewPalette5Sign', { fg=p.cyan,   bg=nil })
    hi('MarkviewPalette6',     { fg=p.azure,  bg=p.azure_bg })
    hi('MarkviewPalette6Fg',   { fg=p.azure,  bg=nil })
    hi('MarkviewPalette6Bg',   { fg=nil,      bg=p.azure_bg })
    hi('MarkviewPalette6Sign', { fg=p.azure,  bg=nil })
    hi('MarkviewPalette7',     { fg=p.blue,   bg=p.blue_bg })
    hi('MarkviewPalette7Fg',   { fg=p.blue,   bg=nil })
    hi('MarkviewPalette7Bg',   { fg=nil,      bg=p.blue_bg })
    hi('MarkviewPalette7Sign', { fg=p.blue,   bg=nil })
  end

  if has_integration('phaazon/hop.nvim') then
    hi('HopNextKey',   { fg=p.green,   bg=nil, bold=true, nocombine=true })
    hi('HopNextKey1',  { fg=p.orange,  bg=nil, bold=true, nocombine=true })
    hi('HopNextKey2',  { fg=p.fg_mid,  bg=nil, bold=true, nocombine=true })
    hi('HopPreview',   { fg=p.yellow,  bg=nil, bold=true, nocombine=true })
    hi('HopUnmatched', { fg=p.bg_mid2, bg=nil })
  end

  if has_integration('rcarriga/nvim-dap-ui') then
    hi('DapUIScope',                   { link='Title' })
    hi('DapUIType',                    { link='Type' })
    hi('DapUIModifiedValue',           { fg=p.orange, bg=nil, bold=true })
    hi('DapUIDecoration',              { link='Title' })
    hi('DapUIThread',                  { link='String' })
    hi('DapUIStoppedThread',           { link='Title' })
    hi('DapUISource',                  { link='Directory' })
    hi('DapUILineNumber',              { link='Title' })
    hi('DapUIFloatBorder',             { link='SpecialChar' })
    hi('DapUIWatchesEmpty',            { link='ErrorMsg' })
    hi('DapUIWatchesValue',            { link='String' })
    hi('DapUIWatchesError',            { link='DiagnosticError' })
    hi('DapUIBreakpointsPath',         { link='Directory' })
    hi('DapUIBreakpointsInfo',         { link='DiagnosticInfo' })
    hi('DapUIBreakpointsCurrentLine',  { fg=p.green,  bg=nil, bold=true })
    hi('DapUIBreakpointsDisabledLine', { link='Comment' })
  end

  if has_integration('rcarriga/nvim-notify') then
    hi('NotifyDEBUGBorder', { fg=p.green,  bg=nil })
    hi('NotifyDEBUGIcon',   { link='NotifyDEBUGBorder' })
    hi('NotifyDEBUGTitle',  { link='NotifyDEBUGBorder' })
    hi('NotifyERRORBorder', { fg=p.red,    bg=nil })
    hi('NotifyERRORIcon',   { link='NotifyERRORBorder' })
    hi('NotifyERRORTitle',  { link='NotifyERRORBorder' })
    hi('NotifyINFOBorder',  { fg=p.blue,   bg=nil })
    hi('NotifyINFOIcon',    { link='NotifyINFOBorder' })
    hi('NotifyINFOTitle',   { link='NotifyINFOBorder' })
    hi('NotifyTRACEBorder', { fg=p.cyan,   bg=nil })
    hi('NotifyTRACEIcon',   { link='NotifyTRACEBorder' })
    hi('NotifyTRACETitle',  { link='NotifyTRACEBorder' })
    hi('NotifyWARNBorder',  { fg=p.yellow, bg=nil })
    hi('NotifyWARNIcon',    { link='NotifyWARNBorder' })
    hi('NotifyWARNTitle',   { link='NotifyWARNBorder' })
  end

  if has_integration('rlane/pounce.nvim') then
    hi('PounceMatch',      { fg=p.bg, bg=p.fg,      bold=true, nocombine=true })
    hi('PounceGap',        { fg=p.bg, bg=p.bg_mid2, bold=true, nocombine=true })
    hi('PounceAccept',     { fg=p.bg, bg=p.yellow,  bold=true, nocombine=true })
    hi('PounceAcceptBest', { fg=p.bg, bg=p.green,   bold=true, nocombine=true })
  end

  if has_integration('romgrk/barbar.nvim') then
    hi('BufferCurrent',        { fg=p.accent, bg=p.bg,      bold=true })
    hi('BufferCurrentIcon',    { fg=nil,      bg=p.bg })
    hi('BufferCurrentIndex',   { link='BufferCurrentIcon' })
    hi('BufferCurrentMod',     { fg=p.accent, bg=p.bg_mid,  bold=true })
    hi('BufferCurrentSign',    { link='BufferCurrent' })
    hi('BufferCurrentTarget',  { fg=p.accent, bg=p.bg_mid2, bold=true })

    hi('BufferInactive',       { fg=p.fg,     bg=p.bg_edge })
    hi('BufferInactiveIcon',   { fg=nil,      bg=p.bg_edge })
    hi('BufferInactiveIndex',  { link='BufferInactiveIcon' })
    hi('BufferInactiveMod',    { fg=p.fg,     bg=p.bg_mid })
    hi('BufferInactiveSign',   { link='BufferInactive' })
    hi('BufferInactiveTarget', { fg=p.fg,     bg=p.bg_mid2 })

    hi('BufferOffset',         { link='Normal' })
    hi('BufferTabpages',       { fg=p.bg,     bg=p.green,   bold=true })
    hi('BufferTabpageFill',    { link='Normal' })

    hi('BufferVisible',        { fg=p.fg,     bg=p.bg,      bold=true })
    hi('BufferVisibleIcon',    { fg=nil,      bg=p.bg })
    hi('BufferVisibleIndex',   { link='BufferVisibleIcon' })
    hi('BufferVisibleMod',     { fg=p.fg,     bg=p.bg_mid,  bold=true })
    hi('BufferVisibleSign',    { link='BufferVisible' })
    hi('BufferVisibleTarget',  { fg=p.fg,     bg=p.bg_mid2, bold=true })
  end

  -- stevearc/aerial.nvim
  -- Everything works correctly out of the box

  if has_integration('williamboman/mason.nvim') then
    hi('MasonError',                       { fg=p.red,    bg=nil })
    hi('MasonHeader',                      { fg=p.bg,     bg=p.azure,   bold=true })
    hi('MasonHeaderSecondary',             { fg=p.bg,     bg=p.blue,    bold=true })
    hi('MasonHeading',                     { link='Bold' })
    hi('MasonHighlight',                   { fg=p.accent, bg=nil })
    hi('MasonHighlightBlock',              { fg=p.bg,     bg=p.accent })
    hi('MasonHighlightBlockBold',          { link='MasonHeaderSecondary' })
    hi('MasonHighlightBlockBoldSecondary', { link='MasonHeader' })
    hi('MasonHighlightBlockSecondary',     { fg=p.bg,     bg=p.azure })
    hi('MasonHighlightSecondary',          { fg=p.azure,  bg=nil })
    hi('MasonLink',                        { link='MasonHighlight' })
    hi('MasonMuted',                       { link='Comment' })
    hi('MasonMutedBlock',                  { fg=p.bg,     bg=p.bg_mid2 })
    hi('MasonMutedBlockBold',              { fg=p.bg,     bg=p.bg_mid2, bold=true })
  end

  -- Terminal colors
  local is_bg_dark = H.hex2oklch(p.bg).l < H.hex2oklch(p.fg).l
  local black = is_bg_dark and 'bg' or 'fg'
  local white = is_bg_dark and 'fg' or 'bg'
  vim.g.terminal_color_0  = p[black .. '_edge2']
  vim.g.terminal_color_1  = p.red
  vim.g.terminal_color_2  = p.green
  vim.g.terminal_color_3  = p.yellow
  vim.g.terminal_color_4  = p.azure
  vim.g.terminal_color_5  = p.purple
  vim.g.terminal_color_6  = p.cyan
  vim.g.terminal_color_7  = p[white .. '_mid2']
  vim.g.terminal_color_8  = p[black .. '_mid2']
  vim.g.terminal_color_9  = p.red
  vim.g.terminal_color_10 = p.green
  vim.g.terminal_color_11 = p.yellow
  vim.g.terminal_color_12 = p.azure
  vim.g.terminal_color_13 = p.purple
  vim.g.terminal_color_14 = p.cyan
  vim.g.terminal_color_15 = p[white .. '_edge2']
end

--- Get latest applied palette
---
---@return table Table with structure as |MiniHues.make_palette()| output that was
---   the latest applied (via |MiniHues.apply_palette()|) palette.
MiniHues.get_palette = function() return vim.deepcopy(H.palette) end

--- Generate random base colors
---
--- Compute background and foreground colors based on randomly generated hue
--- and heuristically picked lightness-chroma values.
---
--- You can recreate a similar functionality but tweaked to your taste
--- using |mini.colors|: >
---
---   local convert = require('mini.colors').convert
---   local hue = math.random(0, 359)
---   return {
---     background = convert({ l = 15, c = 3, h = hue }, 'hex'),
---     foreground = convert({ l = 80, c = 1, h = hue }, 'hex'),
---   }
---
--- Notes:
--- - Respects 'background' (uses different lightness and chroma values for
---   "dark" and "light" backgrounds).
---
--- - When used during startup, might require usage of `math.randomseed()` for
---   proper random generation. For example: >
---
---   local hues = require('mini.hues')
---   math.randomseed(vim.loop.hrtime())
---   hues.setup(hues.gen_random_base_colors())
---
---@param opts table|nil Options. Possible values:
---   - <gen_hue> `(function)` - callable which will return single number for
---     output hue. Can be used to limit which hues will be generated.
---     Default: random integer between 0 and 359.
---
---@return table Table with <background> and <foreground> fields containing
---   color hex strings.
MiniHues.gen_random_base_colors = function(opts)
  opts = opts or {}
  local gen_hue = opts.gen_hue or function() return math.random(0, 359) end
  if not vim.is_callable(gen_hue) then H.error('`gen_hue` should be callable.') end

  local is_dark = vim.o.background == 'dark'
  local bg_l = is_dark and 15 or 90
  local fg_l = is_dark and 80 or 20
  local bg_c = is_dark and 3 or 1

  local hue = gen_hue() % 360
  --stylua: ignore
  return {
    background = H.oklch2hex({ l = bg_l, c = bg_c, h = hue }),
    foreground = H.oklch2hex({ l = fg_l, c = 1,    h = hue }),
  }
end

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniHues.config)

-- Color conversion constants
H.tau = 2 * math.pi

H.saturation_values = { 'low', 'lowmedium', 'medium', 'mediumhigh', 'high' }

H.accent_values = { 'bg', 'fg', 'red', 'orange', 'yellow', 'green', 'cyan', 'azure', 'blue', 'purple' }

-- Cusps for Oklch color space. See 'mini.colors' for more details.
--stylua: ignore start
---@diagnostic disable
---@private
H.cusps = {
  [0] = {26.23,64.74},
  {26.14,64.65},{26.06,64.56},{25.98,64.48},{25.91,64.39},{25.82,64.29},{25.76,64.21},{25.70,64.13},{25.65,64.06},
  {25.59,63.97},{25.55,63.90},{25.52,63.83},{25.48,63.77},{25.45,63.69},{25.43,63.63},{25.41,63.55},{25.40,63.50},
  {25.39,63.43},{25.40,63.33},{25.40,63.27},{25.42,63.22},{25.44,63.15},{25.46,63.11},{25.50,63.05},{25.53,63.00},
  {25.58,62.95},{25.63,62.90},{25.69,62.85},{25.75,62.81},{25.77,62.80},{25.34,63.25},{24.84,63.79},{24.37,64.32},
  {23.92,64.83},{23.48,65.35},{23.08,65.85},{22.65,66.38},{22.28,66.86},{21.98,67.27},{21.67,67.70},{21.36,68.14},
  {21.05,68.60},{20.74,69.08},{20.50,69.45},{20.27,69.83},{20.04,70.22},{19.82,70.62},{19.60,71.03},{19.38,71.44},
  {19.17,71.87},{19.03,72.16},{18.83,72.59},{18.71,72.89},{18.52,73.34},{18.40,73.64},{18.28,73.95},{18.17,74.26},
  {18.01,74.74},{17.91,75.05},{17.82,75.38},{17.72,75.70},{17.64,76.03},{17.56,76.36},{17.48,76.69},{17.41,77.03},
  {17.35,77.36},{17.29,77.71},{17.24,78.05},{17.19,78.39},{17.15,78.74},{17.12,79.09},{17.09,79.45},{17.07,79.80},
  {17.05,80.16},{17.04,80.52},{17.04,81.06},{17.04,81.42},{17.05,81.79},{17.07,82.16},{17.08,82.53},{17.11,82.72},
  {17.14,83.09},{17.18,83.46},{17.22,83.84},{17.27,84.22},{17.33,84.60},{17.39,84.98},{17.48,85.56},{17.56,85.94},
  {17.64,86.33},{17.73,86.72},{17.81,87.10},{17.91,87.50},{18.04,88.09},{18.16,88.48},{18.27,88.88},{18.40,89.48},
  {18.57,89.87},{18.69,90.27},{18.88,90.87},{19.03,91.48},{19.22,91.88},{19.44,92.49},{19.66,93.10},{19.85,93.71},
  {20.04,94.33},{20.33,94.94},{20.60,95.56},{20.85,96.18},{21.10,96.80},{21.19,96.48},{21.27,96.24},{21.38,95.93},
  {21.47,95.70},{21.59,95.40},{21.72,95.10},{21.86,94.80},{21.97,94.58},{22.12,94.30},{22.27,94.02},{22.43,93.74},
  {22.64,93.40},{22.81,93.14},{23.04,92.81},{23.22,92.56},{23.45,92.25},{23.68,91.95},{23.92,91.65},{24.21,91.31},
  {24.45,91.04},{24.74,90.72},{25.08,90.36},{25.37,90.07},{25.70,89.74},{26.08,89.39},{26.44,89.07},{26.87,88.69},
  {27.27,88.34},{27.72,87.98},{28.19,87.61},{28.68,87.23},{29.21,86.84},{29.48,86.64},{28.99,86.70},{28.13,86.81},
  {27.28,86.92},{26.56,87.02},{25.83,87.12},{25.18,87.22},{24.57,87.32},{24.01,87.41},{23.53,87.49},{23.03,87.58},
  {22.53,87.68},{22.10,87.76},{21.68,87.84},{21.26,87.93},{20.92,88.01},{20.58,88.08},{20.25,88.16},{19.92,88.24},
  {19.59,88.33},{19.35,88.39},{19.12,88.46},{18.81,88.55},{18.58,88.61},{18.36,88.68},{18.14,88.76},{17.93,88.83},
  {17.79,88.88},{17.59,88.95},{17.39,89.03},{17.26,89.08},{17.08,89.16},{16.96,89.21},{16.79,89.29},{16.68,89.35},
  {16.58,89.41},{16.43,89.49},{16.33,89.55},{16.24,89.60},{16.16,89.66},{16.04,89.75},{15.96,89.81},{15.89,89.87},
  {15.83,89.93},{15.77,89.99},{15.71,90.05},{15.66,90.12},{15.61,90.18},{15.57,90.24},{15.54,90.31},{15.51,90.37},
  {15.48,90.44},{15.46,90.51},{15.40,90.30},{15.30,89.83},{15.21,89.36},{15.12,88.89},{15.03,88.67},{14.99,88.18},
  {14.92,87.71},{14.85,87.24},{14.78,86.77},{14.75,86.53},{14.70,86.06},{14.65,85.59},{14.61,85.12},{14.60,84.89},
  {14.57,84.42},{14.54,83.94},{14.53,83.71},{14.52,83.24},{14.51,82.77},{14.52,82.30},{14.52,81.83},{14.53,81.60},
  {14.55,81.13},{14.58,80.66},{14.59,80.43},{14.63,79.96},{14.68,79.49},{14.70,79.26},{14.76,78.79},{14.82,78.32},
  {14.85,78.09},{14.93,77.62},{15.01,77.16},{15.10,76.69},{15.19,76.23},{15.24,76.00},{15.34,75.54},{15.45,75.07},
  {15.57,74.61},{15.69,74.15},{15.82,73.69},{15.96,73.23},{16.10,72.77},{16.24,72.31},{16.39,71.86},{16.55,71.40},
  {16.71,70.95},{16.96,70.26},{17.14,69.81},{17.32,69.36},{17.59,68.69},{17.88,68.02},{18.07,67.57},{18.37,66.90},
  {18.67,66.24},{18.99,65.58},{19.30,64.93},{19.74,64.06},{20.07,63.42},{20.51,62.57},{20.97,61.73},{21.54,60.69},
  {22.00,59.87},{22.70,58.66},{23.39,57.49},{24.19,56.16},{25.20,54.52},{26.38,52.66},{28.55,49.32},{31.32,45.20},
  {31.15,45.42},{30.99,45.64},{30.85,45.85},{30.72,46.06},{30.57,46.31},{30.47,46.50},{30.34,46.75},{30.23,46.97},
  {30.13,47.20},{30.03,47.45},{29.93,47.71},{29.86,47.91},{29.77,48.20},{29.71,48.43},{29.65,48.66},{29.58,48.98},
  {29.53,49.23},{29.48,49.48},{29.44,49.74},{29.41,50.01},{29.37,50.29},{29.35,50.57},{29.33,50.86},{29.31,51.16},
  {29.30,51.56},{29.29,51.87},{29.29,52.39},{29.30,52.72},{29.31,53.05},{29.33,53.38},{29.35,53.72},{29.37,54.06},
  {29.40,54.41},{29.43,54.76},{29.47,55.12},{29.52,55.60},{29.56,55.97},{29.61,56.34},{29.66,56.72},{29.73,57.22},
  {29.79,57.61},{29.84,57.99},{29.93,58.52},{29.99,58.91},{30.08,59.44},{30.15,59.84},{30.24,60.38},{30.34,60.93},
  {30.42,61.34},{30.52,61.90},{30.63,62.45},{30.73,63.02},{30.85,63.58},{30.96,64.15},{31.08,64.72},{31.19,65.30},
  {31.31,65.88},{31.44,66.46},{31.59,67.20},{31.72,67.79},{31.88,68.53},{32.01,69.12},{32.18,69.87},{32.25,70.17},
  {32.06,69.99},{31.76,69.70},{31.45,69.42},{31.21,69.20},{30.97,68.98},{30.68,68.71},{30.44,68.50},{30.21,68.29},
  {29.98,68.09},{29.75,67.89},{29.53,67.69},{29.31,67.50},{29.09,67.31},{28.88,67.12},{28.72,66.98},{28.52,66.80},
  {28.31,66.63},{28.16,66.50},{27.97,66.33},{27.78,66.17},{27.64,66.05},{27.49,65.94},{27.33,65.77},{27.20,65.66},
  {27.04,65.51},{26.92,65.40},{26.81,65.30},{26.66,65.16},{26.55,65.06},{26.45,64.96},{26.35,64.87},
}
--stylua: ignore end

-- Latest applied palette
H.palette = nil

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  if config.background == nil or config.foreground == nil then
    H.error('`setup()` needs both `background` and `foreground`.')
  end

  H.validate_hex(config.background, 'background')
  H.validate_hex(config.foreground, 'foreground')
  H.validate_n_hues(config.n_hues)
  if not vim.tbl_contains(H.saturation_values, config.saturation) then
    H.error('`saturation` should be one of ' .. table.concat(vim.tbl_map(vim.inspect, H.saturation_values), ', '))
  end
  if not vim.tbl_contains(H.accent_values, config.accent) then
    H.error('`accent` should be one of ' .. table.concat(vim.tbl_map(vim.inspect, H.accent_values), ', '))
  end
  H.check_type('plugins', config.plugins, 'table')

  return config
end

H.apply_config = function(config)
  MiniHues.config = config

  -- Apply palette
  MiniHues.apply_palette(MiniHues.make_palette(config), config.plugins)
end

-- Palette --------------------------------------------------------------------
H.make_hues = function(bg_h, fg_h, n_hues)
  local res = { bg = bg_h, fg = fg_h }
  if n_hues == 0 then return res end

  -- Generate equidistant circular grid of hues which is the most distant from
  -- background and foreground hues. Distance between two sets is assumed as
  -- minimum distance between all pairs of points.
  local period = 360 / n_hues
  local half_period = 0.5 * period

  -- - Compute delta which determines the furthest grid
  local d
  if bg_h == nil and fg_h == nil then d = 0 end
  if bg_h ~= nil and fg_h == nil then d = (bg_h % period + half_period) % period end
  if bg_h == nil and fg_h ~= nil then d = (fg_h % period + half_period) % period end
  if bg_h ~= nil and fg_h ~= nil then
    local ref_bg, ref_fg = bg_h % period, fg_h % period
    local mid = 0.5 * (ref_bg + ref_fg)
    local mid_alt = (mid + half_period) % period

    d = H.dist_period(mid, ref_bg, period) < H.dist_period(mid_alt, ref_bg, period) and mid_alt or mid
  end

  local grid = {}
  for i = 0, n_hues - 1 do
    table.insert(grid, i * period + d)
  end

  -- Normalize equidistant grid to be base 8 colors
  local dist_fun = function(x, y) return H.dist_period(x, y, 360) end
  local approx = function(ref_hue) return H.get_closest(ref_hue, grid, dist_fun) end

  --stylua: ignore start
  res.red    = approx(0)
  res.orange = approx(45)
  res.yellow = approx(90)
  res.green  = approx(135)
  res.cyan   = approx(180)
  res.azure  = approx(225)
  res.blue   = approx(270)
  res.purple = approx(315)
  --stylua: ignore end

  return res
end

H.validate_hex = function(x, name)
  if type(x) == 'string' and x:find('^#%x%x%x%x%x%x$') ~= nil then return x end
  local msg = string.format('`%s` should be hex color string in the form "#rrggbb", not %s', name, vim.inspect(x))
  H.error(msg)
end

H.validate_n_hues = function(x)
  if type(x) == 'number' and 0 <= x and x <= 8 then return x end
  local msg = string.format('`n_hues` should be a number between 0 and 8', name)
  H.error(msg)
end

H.validate_one_of = function(x, choices, name)
  if vim.tbl_contains(choices, x) then return x end
  local choices_string = table.concat(vim.tbl_map(vim.inspect, choices), ', ')
  local msg = string.format('`%s` should be one of %s', name, choices_string)
  H.error(msg)
end

-- Color conversion -----------------------------------------------------------
H.hex2oklch = function(hex) return H.oklab2oklch(H.rgb2oklab(H.hex2rgb(hex))) end

H.oklch2hex = function(lch) return H.rgb2hex(H.oklab2rgb(H.oklch2oklab(H.clip_to_gamut(lch)))) end

-- HEX <-> RGB in [0; 255]
H.hex2rgb = function(hex)
  local dec = tonumber(hex:sub(2), 16)

  local b = math.fmod(dec, 256)
  local g = math.fmod((dec - b) / 256, 256)
  local r = math.floor(dec / 65536)

  return { r = r, g = g, b = b }
end

H.rgb2hex = function(rgb)
  -- Use straightforward clipping to [0; 255] here to ensure correctness.
  -- Modify `rgb` prior to this to ensure only a small distortion.
  local r = H.clip(H.round(rgb.r), 0, 255)
  local g = H.clip(H.round(rgb.g), 0, 255)
  local b = H.clip(H.round(rgb.b), 0, 255)

  return string.format('#%02x%02x%02x', r, g, b)
end

-- RGB in [0; 255] <-> Oklab
-- https://bottosson.github.io/posts/oklab/#converting-from-linear-srgb-to-oklab
H.rgb2oklab = function(rgb)
  -- Convert to linear RGB
  local r, g, b = H.correct_channel(rgb.r / 255), H.correct_channel(rgb.g / 255), H.correct_channel(rgb.b / 255)

  -- Convert to Oklab
  local l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
  local m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
  local s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b

  local l_, m_, s_ = H.cuberoot(l), H.cuberoot(m), H.cuberoot(s)

  local L = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
  local A = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
  local B = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_

  -- Explicitly convert to gray for nearly achromatic colors
  if math.abs(A) < 1e-4 then A = 0 end
  if math.abs(B) < 1e-4 then B = 0 end

  -- Normalize to appropriate range
  return { l = H.correct_lightness(100 * L), a = 100 * A, b = 100 * B }
end

H.oklab2rgb = function(lab)
  local L, A, B = 0.01 * H.correct_lightness_inv(lab.l), 0.01 * lab.a, 0.01 * lab.b

  local l_ = L + 0.3963377774 * A + 0.2158037573 * B
  local m_ = L - 0.1055613458 * A - 0.0638541728 * B
  local s_ = L - 0.0894841775 * A - 1.2914855480 * B

  local l = l_ * l_ * l_
  local m = m_ * m_ * m_
  local s = s_ * s_ * s_

  --stylua: ignore
  local r =  4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
  local g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
  local b = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s

  return { r = 255 * H.correct_channel_inv(r), g = 255 * H.correct_channel_inv(g), b = 255 * H.correct_channel_inv(b) }
end

-- Oklab <-> Oklch
H.oklab2oklch = function(lab)
  local c = math.sqrt(lab.a ^ 2 + lab.b ^ 2)
  -- Treat grays specially
  local h = nil
  if c > 0 then h = H.rad2degree(math.atan2(lab.b, lab.a)) end
  return { l = lab.l, c = c, h = h }
end

H.oklch2oklab = function(lch)
  -- Treat grays specially
  if lch.c <= 0 or lch.h == nil then return { l = lch.l, a = 0, b = 0 } end

  local a = lch.c * math.cos(H.degree2rad(lch.h))
  local b = lch.c * math.sin(H.degree2rad(lch.h))
  return { l = lch.l, a = a, b = b }
end

-- Degree in [0; 360] <-> Radian in [0; 2*pi]
H.rad2degree = function(x) return (x % H.tau) * 360 / H.tau end

H.degree2rad = function(x) return (x % 360) * H.tau / 360 end

-- Functions for RGB channel correction. Assumes input in [0; 1] range
-- https://bottosson.github.io/posts/colorwrong/#what-can-we-do%3F
H.correct_channel = function(x) return 0.04045 < x and math.pow((x + 0.055) / 1.055, 2.4) or (x / 12.92) end

H.correct_channel_inv = function(x)
  return (0.0031308 >= x) and (12.92 * x) or (1.055 * math.pow(x, 0.416666667) - 0.055)
end

-- Functions for lightness correction
-- https://bottosson.github.io/posts/colorpicker/#intermission---a-new-lightness-estimate-for-oklab
H.correct_lightness = function(x)
  x = 0.01 * x
  local k1, k2 = 0.206, 0.03
  local k3 = (1 + k1) / (1 + k2)

  local res = 0.5 * (k3 * x - k1 + math.sqrt((k3 * x - k1) ^ 2 + 4 * k2 * k3 * x))
  return 100 * res
end

H.correct_lightness_inv = function(x)
  x = 0.01 * x
  local k1, k2 = 0.206, 0.03
  local k3 = (1 + k1) / (1 + k2)
  local res = (x / k3) * (x + k1) / (x + k2)
  return 100 * res
end

-- Get gamut ranges for Lch point. More info in 'mini.colors'.
H.get_gamut_points = function(lch)
  local c, l = lch.c, H.clip(lch.l, 0, 100)
  l = H.correct_lightness_inv(l)
  local cusp = H.cusps[math.floor(lch.h % 360)]
  local c_cusp, l_cusp = cusp[1], cusp[2]

  -- Maximum allowed chroma. Used for computing saturation.
  local c_upper = l <= l_cusp and (c_cusp * l / l_cusp) or (c_cusp * (100 - l) / (100 - l_cusp))
  c_upper = H.clip(c_upper, 0, math.huge)

  -- Other points can be computed only in presence of actual chroma
  if c == nil then return { c_upper = c_upper } end

  -- Intersection of segment between (c, l) and (0, l_cusp) with gamut boundary
  -- Used for gamut clipping
  local c_cusp_clip, l_cusp_clip
  if c <= 0 then
    c_cusp_clip, l_cusp_clip = c, l
  elseif l <= l_cusp then
    -- Intersection with lower segment
    local prop = 1 - l / l_cusp
    c_cusp_clip = c_cusp * c / (c_cusp * prop + c)
    l_cusp_clip = l_cusp * c_cusp_clip / c_cusp
  else
    -- Intersection with upper segment
    local prop = 1 - (l - 100) / (l_cusp - 100)
    c_cusp_clip = c_cusp * c / (c_cusp * prop + c)
    l_cusp_clip = 100 + c_cusp_clip * (l_cusp - 100) / c_cusp
  end

  return {
    c_upper = c_upper,
    l_cusp_clip = H.correct_lightness(l_cusp_clip),
    c_cusp_clip = c_cusp_clip,
  }
end

H.clip_to_gamut = function(lch)
  local res = vim.deepcopy(lch)

  -- Gray is always in gamut
  if res.h == nil then return res end

  local gamut_points = H.get_gamut_points(lch)

  local is_inside_gamut = lch.c <= gamut_points.c_upper
  if is_inside_gamut then return res end

  -- Clip by going towards (0, l_cusp) until in gamut
  res.l, res.c = gamut_points.l_cusp_clip, gamut_points.c_cusp_clip

  return res
end

-- ============================================================================
-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.hues) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.round = function(x)
  if x == nil then return nil end
  return math.floor(x + 0.5)
end

H.clip = function(x, from, to) return math.min(math.max(x, from), to) end

H.cuberoot = function(x) return math.pow(x, 0.333333) end

H.dist_period = function(x, y, period)
  period = period or 360
  local d = math.abs((x % period) - (y % period))
  return math.min(d, period - d)
end

H.get_closest = function(x, values, dist_fun)
  local best_val, best_key, best_dist = nil, nil, math.huge
  for key, val in pairs(values) do
    local cur_dist = dist_fun(x, val)
    if cur_dist <= best_dist then
      best_val, best_key, best_dist = val, key, cur_dist
    end
  end

  return best_val, best_key
end

return MiniHues
