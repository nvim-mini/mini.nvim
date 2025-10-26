--- *mini.colors* Tweak and save any color scheme
---
--- MIT License Copyright (c) 2023 Evgeni Chasnovski

--- Features:
--- - Create colorscheme object: either manually (|MiniColors.as_colorscheme()|)
---   or by querying present color schemes (including currently active one; see
---   |MiniColors.get_colorscheme()|).
---
--- - Infer data about color scheme and/or modify based on it:
---     - Add transparency by removing background color (requires transparency
---       in terminal emulator).
---     - Infer cterm attributes (|cterm-colors|) based on gui colors making it
---       compatible with 'notermguicolors'.
---     - Resolve highlight group links (|:highlight-link|).
---     - Compress by removing redundant highlight groups.
---     - Extract palette of used colors and/or infer terminal colors
---       (|terminal-config|) based on it.
---
--- - Modify colors to better fit your taste and/or goals (see more in
---   |MiniColors-colorscheme-methods|):
---     - Apply any function to color hex string.
---     - Update channels (like lightness, saturation, hue, temperature, red,
---       green, blue, etc.; see more in |MiniColors-channels|).
---       Use either own function or one of the implemented methods:
---         - Add value to channel or multiply it by coefficient. Like "add 10
---           to saturation of every color" or "multiply saturation by 2" to
---           make colors more saturated (less gray).
---         - Invert. Like "invert lightness" to convert between dark/light theme.
---         - Set to one or more values (picks closest to current one). Like
---           "set to one or two hues" to make mono- or dichromatic color scheme.
---         - Repel from certain source(s) with stronger effect for closer values.
---           Like "repel from hue 30" to remove red color from color scheme.
---           Repel hue (how much is removed) is configurable.
---     - Simulate color vision deficiency.
---
--- - Once color scheme is ready, either apply it to see effects right away or
---   write it into a Lua file as a fully functioning separate color scheme.
---
--- - Experiment interactively with a feedback (|MiniColors.interactive()|).
---
--- - Animate transition between color schemes either with |MiniColors.animate()|
---   or with |:Colorscheme| user command.
---
--- - Convert within supported color spaces (|MiniColors.convert()|):
---     - Hex string.
---     - 8-bit number (terminal colors).
---     - RGB.
---     - Oklab, Oklch, Okhsl (https://bottosson.github.io/posts/oklab/).
---
--- Notes:
--- - There is a collection of |MiniColors-recipes| with code snippets for some
---   common tasks.
--- - There is no goal to support as many color spaces as possible, only the
---   already present ones.
---
--- # Tweak quick start ~
---
--- - Execute `:lua require('mini.colors').interactive()`.
---
--- - Experiment by writing calls to exposed color scheme methods and applying
---   them with `<M-a>`. For more information, see |MiniColors-colorscheme-methods|
---   and |MiniColors-recipes|.
---
--- - If you are happy with result, write color scheme with `<M-w>`. If not,
---   reset to initial color scheme with `<M-r>`.
---
--- - If only some highlight groups can be made better, adjust them manually
---   inside written color scheme file.
---
--- # Setup ~
---
--- This module doesn't need setup, but it can be done to improve usability.
--- Setup with `require('mini.colors').setup({})` (replace `{}` with your
--- `config` table). It will create global Lua table `MiniColors` which you can
--- use for scripting or manually (with `:lua MiniColors.*`).
---
--- See |MiniColors.config| for `config` structure and default values.
---
--- This module doesn't have runtime options, so using `vim.b.minicolors_config`
--- will have no effect here.
---
--- # Comparisons ~
---
--- - [rktjmp/lush.nvim](https://github.com/rktjmp/lush.nvim):
---     - Oriented towards tweaking separate highlight groups, while 'mini.colors'
---       is more designed to work with color scheme as a whole.
---     - Uses HSL and HSLuv color spaces, while 'mini.colors' uses Oklab, Oklch,
---       and Okhsl which have slightly better perceptual uniformity properties.
---     - Doesn't have functionality to infer and repair missing data in color
---       scheme (like cterm attributes, terminal colors, transparency, etc.),
---       while 'mini.colors' does.
---     - Doesn't implement animation of color scheme transition, while
---       'mini.colors' does.
--- - [lifepillar/vim-colortemplate](https://github.com/lifepillar/vim-colortemplate):
---     - Comparisons are similar to that of 'rktjmp/lush.nvim'.
--- - [tjdevries/colorbuddy.nvim](https://github.com/tjdevries/colorbuddy.nvim):
---     - Comparisons are similar to that of 'rktjmp/lush.nvim'.
---@tag MiniColors

--- All following code snippets assume to be executed inside interactive buffer
--- (|MiniColors.interactive()|). They are directly copy-pasteable.
---
--- To apply single method to current color scheme, use >vim
---   :lua MiniColors.get_colorscheme():<method goes here>:apply().
--- <
--- Recipes:
--- - Tweak lightness: >lua
---
---   -- Invert dark/light color scheme to be light/dark
---   chan_invert('lightness', { gamut_clip = 'cusp' })
---
---   -- Ensure constant contrast ratio
---   chan_set('lightness', 15, { filter = 'bg' })
---   chan_set('lightness', 85, { filter = 'fg' })
--- <
--- - Tweak saturation: >lua
---
---   -- Make background colors less saturated and foreground - more
---   chan_add('saturation', -20, { filter = 'bg' })
---   chan_add('saturation', 20,  { filter = 'fg' })
---
---   -- Convert to grayscale
---   chan_set('saturation', 0)
--- <
--- - Tweak hue: >lua
---
---   -- Create monochromatic variant (this uses green color)
---   chan_set('hue', 135)
---
---   -- Create dichromatic variant (this uses Neovim-themed hues)
---   chan_set('hue', { 140, 245 })
--- <
--- - Tweak temperature: >lua
---
---   -- Invert temperature (make cold theme become warm and vice versa)
---   chan_invert('temperature')
---
---   -- Make background colors colder and foreground warmer
---   chan_add('temperature', -40, { filter = 'bg' })
---   chan_add('temperature', 40,  { filter = 'fg' })
--- <
--- - Counter color vision deficiency (try combinations of these to see which
---   one works best for you):
---
---     - Improve text saturation contrast (usually the best starting approach): >lua
---
---       chan_set('saturation', { 10, 90 }, { filter = 'fg' })
--- <
---     - Remove certain hues from all colors (use 30 for red, 90 for yellow,
---       135 for green, 270 for blue): >lua
---
---       -- Repel red color
---       chan_repel('hue', 30, 45)
--- <
---     - Force equally spaced palette (remove ones with which you know you
---       have trouble): >lua
---
---       -- Might be a good choice for red-green color blindness
---       chan_set('hue', { 90, 180, 270})
---
---       -- Might be a good choice for blue-yellow color blindness
---       chan_set('hue', { 0, 90, 180 })
--- <
---     - Inverting temperature or pressure can sometimes improve readability: >lua
---
---       chan_invert('temperature')
---       chan_invert('pressure')
--- <
---     - If all hope is lost, hue random generation might help if you are lucky: >lua
---
---       chan_modify('hue', function() return math.random(0, 359) end)
--- <
--- - For color scheme creators use |MiniColors-colorscheme:simulate_cvd()| to
---   simulate various color vision deficiency types to see how color scheme
---   would look in the eyes of color blind person.
---@tag MiniColors-recipes

--- Color space is a way to quantitatively describe a color. In this module
--- color spaces are used both as source for |MiniColors-channels| and inputs
--- for |MiniColors.convert()|
---
--- List of supported color spaces (along with their id in parenthesis):
--- - 8-bit (`8-bit`) - integer between 16 and 255. Usually values 0-15 are also
---   supported, but they depend on terminal emulator theme which is not reliable.
---   See https://en.wikipedia.org/wiki/ANSI_escape_code#8-bit .
---
--- - Hex (`hex`) - string of the form "#xxxxxx" where `x` is a hexadecimal number.
---
--- - RGB (`rgb`) - table with numeric fields `r` (red), `g` (green), `b` (blue).
---   Visible range is from 0 to 255.
---
--- - Oklab (`oklab`) - table with fields `l` (lightness; numeric in [0; 100]),
---   `a`, `b` (both are unbounded numeric; visible range is usually between
---   -30 to 30). Field `l` describes how light is color; `a` - how "green-red" it is;
---   `b` - how "blue-yellow" it is.
---
--- - Oklch (`oklch`) - table with fields `l` (same as in Oklab),
---   `c` (chroma; positive numeric, visible range usually lower than 32),
---   `h` (`nil` for grays or periodic numeric in [0, 360)). Field `c` describes how
---   colorful a color is; `h` is a value of "true color" on color circle/wheel.
---   NOTE: gray colors, being achromatic by nature, don't have hue.
---
--- - Okhsl (`okhsl`) - Oklch but with `c` replaced by `s` (saturation; numeric
---   in [0; 100]). Field `s` describes a percent of chroma relative to maximum
---   visible chroma for the particular lightness and hue combination. Note,
---   that mathematical model used to compute maximum visible chroma is
---   approximate which might lead to inaccuracies for highly saturated colors
---   with relatively low or high lightness.
---
--- Sources for Oklab/Oklch/Okhsl:
--- - https://bottosson.github.io/posts/oklab/ - initial derivation and
---   introduction of Oklab and Oklch.
--- - https://bottosson.github.io/misc/colorpicker - interactive color picker.
---   Great way for a hands-on introduction to concepts of lightness, chroma,
---   saturation, and hue.
---
--- Note that Oklab/Oklch/Okhsl use channel normalization for `l`, `a`, `b`, `c`, `s` that
--- is more oriented towards integer numbers (according to the above sources).
--- Some implementations (like in CSS) are more oriented towards [0; 1] range or
--- percentages. Adjust accordingly by dividing/multiplying output by 100.
--- Also use `adjust_lightness = false` in |MiniColors.convert()|.
---
--- # Gamut clip ~
--- *MiniColors-gamut-clip*
---
--- In Neovim highlight group colors are usually specified by their red, green,
--- and blue values from 0 to 255 in the form of HEX string (see |gui-colors|).
--- Although plenty, these are not all possible colors.
---
--- When performing color manipulation using |MiniColors-colorscheme-methods|,
--- it is possible to end up with "impossible" color (which can't be directly
--- converted to HEX string). For example, inverting lightness of color "#fce094"
--- will lead to a color `{ l = 10, c = 10, h = 90 }` in Oklch space, i.e.
--- "dark yellow" which is impossible to show in HEX.
---
--- **Gamut clipping** is an action of converting color outside of visible gamut
--- (colors representable with HEX string) to be inside it while preserving
--- certain perceptual characteristics as much as possible.
---
--- Gamut clipping in this module is done inside Oklch color space. The goal is to
--- preserve hue as much as possible while manipulating lightness and/or chroma.
---
--- List of supported gamut clip methods (along with their id in parenthesis):
--- - Clip chroma (`'chroma'`) - reduce chroma while preserving lightness until
---   color is inside visible gamut. Default method.
---
--- - Clip lightness (`'lightness'`) - reduce lightness while preserving chroma
---   until color is inside visible gamut.
---
--- - Clip according to "cusp" (`'cusp'`) - reduce both lightness and chroma in
---   a compromise way depending on hue.
---   Cusp is a color with the highest chroma inside slice of visible gamut
---   with the same hue (hue leaf). It is called that way because the slice has
---   a roughly triangular shape with points at (0, 0) - (0, 100) - "cusp" in
---   (chroma, lightness) coordinates.
---   Gamut clipping using "cusp" as reference is done by changing color towards
---   (0, cusp_lightness) point (gray with lightness equal to that of a current
---   cusp) until color is inside visible gamut.
---
--- In short:
--- - Usually `'chroma'` is enough.
--- - If colors are too desaturated - try `'cusp'`.
--- - If still not colorful enough - try `'lightness'`.
---
--- Notes:
--- - Currently implemented formulas are approximate (by design; to reduce code
---   complexity) so there might be problems for highly saturated colors with
---   relatively low or high lightness.
---@tag MiniColors-color-spaces

--- A color channel is a number describing one particular aspect of a color.
--- It is usually direct or modified coordinate of a color space. See
--- |MiniColors-color-spaces| for information on color spaces.
---
--- List of supported channels (along with their id in parenthesis):
--- - Lightness (`lightness`) - corrected `l` component of Oklch. Describes how
---   light is a color. Ranges from 0 (black dark) to 100 (white light).
---
--- - Chroma (`chroma`) - `c` component of Oklch. Describes how colorful is
---   a color in absolute units. Ranges from 0 (gray) to infinity (more like
---   around 30 in practice).
---
--- - Saturation (`saturation`) - `s` component of Okhsl. Describes how colorful
---   is color in relative units. Ranges from 0 (gray) to 100 (maximum saturation
---   for a given lightness-hue pair).
---
--- - Hue (`hue`) - `h` component of Oklch. Describes "true color value" (like
---   red/green/blue) as a number. It is a periodic value from 0 (included) to
---   360 (not included). Best perceived as a degree on a color circle/wheel.
---
---   Approximate values for common color names:
---     - 0   - pink.
---     - 30  - red.
---     - 60  - orange.
---     - 90  - yellow.
---     - 135 - green.
---     - 180 - cyan.
---     - 225 - light blue.
---     - 270 - blue.
---     - 315 - magenta/purple.
---
--- - Temperature (`temperature`) - circular distance from current hue to hue 270
---   angle (blue). Ranges from 0 (cool) to 180 (hot) anchored at hues 270 (blue)
---   and 90 (yellow). Similar to `b` channel but tries to preserve chroma.
---
--- - Pressure (`pressure`) - circular distance from current hue to hue 180.
---   Ranges from 0 (low; green-ish) to 180 (high; red-ish) anchored at hues
---   180 and 0. Similar to `a` channel but tries to preserve chroma.
---   Not widely used; added to have something similar to temperature.
---
--- - a (`a`) - `a` component of Oklab. Describes how "green-red" a color is.
---   Can have any value. Negative values are "green-ish", positive - "red-ish".
---
--- - b (`b`) - `b` component of Oklab. Describes how "blue-yellow" a color is.
---   Can have any value. Negative values are "blue-ish", positive - "yellow-ish".
---
--- - Red (`red`) - `r` component of RGB. Describes how much red a color has.
---   Ranges from 0 (no red) to 255 (full red).
---
--- - Green (`green`) - `g` component of RGB. Describes how much green a color has.
---   Ranges from 0 (no green) to 255 (full green).
---
--- - Blue (`blue`) - `b` component of RGB. Describes how much blue a color has.
---   Ranges from 0 (no blue) to 255 (full blue).
---@tag MiniColors-channels

---@alias __colors_channel `(string)` One of supported |MiniColors-channels|.
---@alias __colors_chan_opts `(table|nil)` Options. Possible fields:
---   - <filter> `(function|string)` - filter colors to update. Possible values:
---       - String representing target attributes. One of `'fg'`, `'bg'`, `'sp'`,
---         `'term'` (only terminal colors).
---       - Callable with signature as in |MiniColors-colorscheme:color_modify()|.
---     Default: `nil` to update all colors.
---   - <gamut_clip> `(string)` - gamut clipping method. One of `'chroma'`,
---     `'lightness'`, `'cusp'`. See |MiniColors-gamut-clip|. Default: `'chroma'`.

--- Colorscheme object is a central structure of this module. It contains all
--- data relevant to colors in fields and provides methods to modify it.
---
--- Create colorscheme object manually with |MiniColors.as_colorscheme()|: >lua
---
---   MiniColors.as_colorscheme({
---     name = 'my_cs',
---     groups = {
---       Normal   = { fg = '#dddddd', bg = '#222222' },
---       SpellBad = { sp = '#dd2222', undercurl = true },
---     },
---     terminal = { [0] = '#222222', [1] = '#dd2222' },
---   })
--- <
--- Get any registered color scheme (including currently active) as colorscheme
--- object with |MiniColors.get_colorscheme()|: >lua
---
---   -- Get current color scheme
---   MiniColors.get_colorscheme()
---
---   -- Get registered color scheme by name
---   MiniColors.get_colorscheme('minischeme', { new_name = 'maxischeme' })
--- <
---@class Colorscheme
---
--- *MiniColors-colorscheme-fields*
---
---@field name string|nil Name of the color scheme (as in |g:colors_name|).
---
---@field groups table|nil Table with highlight groups data. Keys are group
---   names appropriate for `name` argument of |nvim_set_hl()|, values - tables
---   appropriate for its `val` argument. Note: gui colors are accepted only in
---   short form (`fg`, `bg`, `sp`).
---
---@field terminal table|nil Table with terminal colors data (|terminal-config|).
---   Keys are numbers from 0 to 15, values - strings representing color (hex
---   string or plain color name; see |nvim_get_color_by_name()|).
---
--- # Methods ~
--- *MiniColors-colorscheme-methods*
---
--- Notes about all methods:
--- - They never modify underlying colorscheme object instead returning deep
---   copy with modified fields.
--- - They accept `self` colorscheme object as first argument meaning they should be
---   called with `:` notation (like `cs:method()`).
---
--- Example calling methods: >lua
---
---   -- Get current color scheme, set hue of colors to 135, infer cterm
---   -- attributes and apply
---   local cs = MiniColors.get_colorscheme()
---   cs:chan_set('hue', 135):add_cterm_attributes():apply()
--- <
--- ## add_cterm_attributes() ~
--- *MiniColors-colorscheme:add_cterm_attributes()*
---
--- Infer |cterm-colors| based on present |gui-colors|. It updates `ctermbg`/`ctermfg`
--- based on `fg`/`bg` by approximating in perceptually uniform distance in Oklab
--- space (|MiniColors-color-spaces|).
---
--- ### Parameters ~
--- {opts} `(table|nil)` Options. Possible fields:
---   - <force> `(boolean)` - Whether to replace already present cterm attributes
---     with inferred ones. Default: `true`.
---
--- ## add_terminal_colors() ~
--- *MiniColors-colorscheme:add_terminal_colors()*
---
--- Infer terminal colors (|terminal-config|) based on colorscheme palette
--- (see |MiniColors-colorscheme:get_palette()|). It updates `terminal` field
--- based on color scheme's palette by picking the most appropriate entry to
--- represent terminal color. Colors from 0 to 7 are attempted to be black,
--- red, green, yellow, blue, magenta, cyan, white. Colors from 8 to 15 are
--- the same as from 0 to 7.
---
--- ### Parameters ~
--- {opts} `(table|nil)` Options. Possible fields:
---   - <force> `(boolean)` - Whether to replace already present terminal colors
---     with inferred ones. Default: `true`.
---   - <palette_args> `(table)` - |MiniColors-colorscheme:get_palette()| arguments.
---
--- ## add_transparency() ~
--- *MiniColors-colorscheme:add_transparency()*
---
--- Add transparency by removing background from a certain highlight groups.
--- Requires actual transparency from terminal emulator to see background image.
--- Has no effect on linked groups; use |MiniColors-colorscheme:resolve_links()|
--- explicitly before applying transparency.
---
--- ### Parameters ~
--- {opts} `(table|nil)` Options. Possible fields can be used to configure which
---   sets of highlight groups to update:
---   - <general> `(boolean)` - general groups (like `Normal`). Default: `true`.
---   - <float> `(boolean)` - built-in groups for floating windows. Default: `false`.
---   - <statuscolumn> `(boolean)` - groups related to 'statuscolumn' (signcolumn,
---     numbercolumn, foldcolumn, `DiagnosticSignXxx`, and `XxxMsg` groups). Also
---     updates groups for all currently defined signs. Default: `false`.
---   - <statusline> `(boolean)` - built-in groups for 'statusline'. Default: `false`.
---   - <tabline> `(boolean)` - built-in groups for 'tabline'. Default: `false`.
---   - <winbar> `(boolean)` - built-in groups for 'winbar'. Default: `false`.
---
--- ## apply() ~
--- *MiniColors-colorscheme:apply()*
---
--- Apply colorscheme:
--- - Set |g:colors_name| to a `name` field.
--- - Apply highlight groups in a `groups` field.
--- - Set terminal colors from a `terminal` field.
---
--- ### Parameters ~
--- {opts} `(table|nil)` Options. Possible fields:
---   - <clear> `(boolean)` - whether to execute |:hi-clear| first. Default: `true`.
---
--- ## chan_add() ~
--- *MiniColors-colorscheme:chan_add()*
---
--- Add value to a channel (see |MiniColors-channels|).
---
--- ### Parameters ~
--- {channel} __colors_channel
--- {value} `(number)` Number to add (can be negative).
--- {opts} __colors_chan_opts
---
---
--- ## chan_invert() ~
--- *MiniColors-colorscheme:chan_invert()*
---
--- Invert value in a channel (see |MiniColors-channels|).
---
--- Notes:
--- - Most Oklab/Oklch inversions are not exactly invertible: applying it twice
---   might lead to slightly different colors depending on gamut clip method
---   (|MiniColors-gamut-clip|) like smaller chroma with default `'chroma'` method.
---
--- ### Parameters ~
--- {channel} __colors_channel
--- {opts} __colors_chan_opts
---
--- ## chan_modify() ~
--- *MiniColors-colorscheme:chan_modify()*
---
--- Modify channel with a callable.
---
--- ### Parameters ~
--- {channel} __colors_channel
--- {f} `(function)` - callable which defines modification. Should take current
---   value of a channel and return a new one.
--- {opts} __colors_chan_opts
---
--- ## chan_multiply() ~
--- *MiniColors-colorscheme:chan_multiply()*
---
--- Multiply value of a channel (see |MiniColors-channels|).
---
--- ### Parameters ~
--- {channel} __colors_channel
--- {coef} `(number)` Number to multiply with (can be negative).
--- {opts} __colors_chan_opts
---
--- ## chan_repel() ~
--- *MiniColors-colorscheme:chan_repel()*
---
--- Repel from certain sources.
---
--- Given an array of repel centers (`sources`) and repel degree (`coef`) add to
--- current channel value some amount ("nudge") with the following properties:
--- - Nudges from several sources are added together.
--- - Nudge is directly proportional to `coef`: bigger `coef` means bigger nudge.
--- - Nudge is inversely proportional to the distance between current value and
---   source: for positive `coef` bigger distance means smaller nudge, i.e.
---   repel effect weakens with distance.
--- - With positive `coef` nudges close to source are computed in a way to remove
---   whole `[source - coef; source + coef]` range.
--- - Negative `coef` results into attraction to source. Nudges in
---   `[source - coef; source + coef]` range are computed to completely collapse it
---   into `source`.
---
--- Examples: >lua
---
---   -- Repel hue from red color removing hue in range from 20 to 40
---   chan_repel('hue', 30, 10)
---
---   -- Attract hue to red color collapsing [20; 40] range into 30.
---   chan_repel('hue', 30, -10)
--- <
--- ### Parameters ~
--- {channel} __colors_channel
--- {sources} `(table|number)` Single or multiple source from which to repel.
--- {coef} `(number)` Repel degree (can be negative to attract).
--- {opts} __colors_chan_opts
---
--- ## chan_set() ~
--- *MiniColors-colorscheme:chan_set()*
---
--- Set channel to certain value(s). This can be used to ensure that channel has
--- value(s) only within supplied set. If more than one is supplied, closest
--- element to current value is used.
---
--- ### Parameters ~
--- {channel} __colors_channel
--- {values} `(table|number)` Single or multiple values to set.
--- {opts} __colors_chan_opts
---
--- ## color_modify() ~
--- *MiniColors-colorscheme:color_modify()*
---
--- Modify all colors with a callable. It should return new color value (hex
--- string or `nil` to remove attribute) base on the following input:
--- - Current color as hex string.
--- - Data about the color: a table with fields:
---     - <attr> - one of `'fg'`, `'bg'`, `'sp'`, and `'term'` for terminal color.
---     - <name> - name of color source. Either a name of highlight group or
---       string of the form `terminal_color_x` for terminal color (as in
---       |terminal-config|).
---
--- Example: >lua
---
---   -- Set to '#dd2222' all foreground colors for groups starting with "N"
---   color_modify(function(hex, data)
---     if data.attr == 'fg' and data.name:find('^N') then
---       return '#dd2222'
---     end
---     return hex
---   end)
--- <
--- ### Parameters ~
--- {f} `(function)` Callable returning new color value.
---
--- ## compress() ~
--- *MiniColors-colorscheme:compress()*
---
--- Remove redundant highlight groups. These are one of the two kinds:
--- - Having values identical to ones after |:hi-clear| (meaning they usually
---   don't add new information).
--- - Coming from a curated list of plugins with highlight groups usually not
---   worth keeping around. Current list of such plugins:
---     - [nvim-tree/nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons)
---     - [norcalli/nvim-colorizer.lua](https://github.com/norcalli/nvim-colorizer.lua)
---
--- This method is useful to reduce size of color scheme before writing into
--- the file with |MiniColors-colorscheme:write()|.
---
--- ### Parameters ~
--- {opts} `(table|nil)` Options. Possible fields:
---   - <plugins> `(boolean)` - whether to remove highlight groups from a curated
---     list of plugins. Default: `true`.
---
--- ## get_palette() ~
--- *MiniColors-colorscheme:get_palette()*
---
--- Get commonly used colors. This basically counts number of all color
--- occurrences and filter out rare ones.
---
--- It is usually a good idea to apply both |MiniColors-colorscheme:compress()|
--- and |MiniColors-colorscheme:resolve_links()| before applying this.
---
--- ### Parameters ~
--- {opts} `(table|nil)` Options. Possible fields:
---   - <threshold> `(number)` - relative threshold for groups to keep. A group
---     is not included in output if it has less than this many occurrences
---     relative to a total number of colors. Default: 0.01.
---
--- ## resolve_links() ~
--- *MiniColors-colorscheme:resolve_links()*
---
--- Resolve links (|:highlight-link|). This makes all highlight groups with `link`
--- attribute have data from a linked one.
---
--- Notes:
--- - Resolves nested links.
--- - If some group is linked to a group missing in current colorscheme object,
---   it is not resolved.
---
--- ## simulate_cvd() ~
--- *MiniColors-colorscheme:simulate_cvd()*
---
--- Simulate color vision deficiency (CVD, color blindness). This is basically
--- a wrapper using |MiniColors.simulate_cvd()| as a part of
--- call to |MiniColors-colorscheme:color_modify()| method.
---
--- ### Parameters ~
--- {cvd_type} `(string)` One of `'protan'`, `'deutan'`, `'tritan'`, `'mono'`.
--- {severity} `(number|nil)` Severity of CVD, number between 0 and 1. Default: 1.
---
--- ## write() ~
--- *MiniColors-colorscheme:write()*
---
--- Write color scheme to a file. It will be a Lua script readily usable as
--- a regular color scheme. Useful to both save results of color scheme tweaking
--- and making local snapshot of some other color scheme.
---
--- Sourcing this file on startup usually leads to a better performance that
--- sourcing initial color scheme, as it is essentially a conditioned
--- |:hi-clear| call followed by a series of |nvim_set_hl()| calls.
---
--- Default writing location is a "colors" directory of your Neovim config
--- directory (see |base-directories|). After writing, it should be available
--- for sourcing with |:colorscheme| or |:Colorscheme|.
---
--- Name of the file by default is taken from `name` field (`'mini_colors'` is
--- used if it is `nil`). If color scheme with this name already exists, it
--- appends prefix based on current time to make it unique.
---
--- Notes:
--- - If colors were updated, it is usually a good idea to infer cterm attributes
---   with |MiniColors-colorscheme:add_cterm_attributes()| prior to writing.
---
--- ### Parameters ~
--- {opts} `(table|nil)` Options. Possible fields:
---   - <compress> `(boolean)` - whether to call |MiniColors-colorscheme:compress()|
---     prior to writing. Default: `true`.
---   - <name> `(string|nil)` - basename of written file. Default: `nil` to infer
---     from `name` field.
---   - <directory> `(string)` - directory to where file should be saved.
---     Default: "colors" subdirectory of Neovim home config (`stdpath("config")`).
---@tag MiniColors-colorscheme

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local

-- Module definition ==========================================================
local MiniColors = {}
local H = {}

--- Module setup
---
--- # :Colorscheme ~
--- *:Colorscheme*
---
--- Calling this function creates a `:Colorscheme` user command. It takes one or
--- more registered color scheme names and performs animated transition between
--- them (starting from currently active color scheme).
--- It uses |MiniColors.animate()| with default options.
---
---@param config table|nil Module config table. See |MiniColors.config|.
---
---@usage >lua
---   require('mini.colors').setup() -- use default config
---   -- OR
---   require('mini.colors').setup({}) -- replace {} with your config table
--- <
MiniColors.setup = function(config)
  -- Export module
  _G.MiniColors = MiniColors

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Create user commands
  H.create_user_commands()
end

--- Defaults ~
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
MiniColors.config = {}
--minidoc_afterlines_end

--- Create colorscheme object
---
---@param x table Table to be transformed into |MiniColors-colorscheme| object.
---
---@return table Copy of `x` transformed into a colorscheme object.
MiniColors.as_colorscheme = function(x)
  -- Validate input
  if not H.is_table(x) then H.error('Input of `as_colorscheme()` should be table.') end

  if x.groups ~= nil then
    if not H.is_table(x.groups) then H.error('Field `groups` of colorscheme should be table or nil.') end
    if not H.all(x.groups, H.is_table) then H.error('All elements of `groups` colorscheme field should be tables.') end
  end

  if x.terminal ~= nil then
    if not H.is_table(x.terminal) then H.error('Field `terminal` of colorscheme should be table or nil.') end
    if not H.all(x.terminal, H.is_string) then
      H.error('All elements of `terminal` colorscheme field should be strings.')
    end
  end

  -- Create a proper copy
  local res = vim.deepcopy(x)

  -- - Ensure that tables for highlight groups are independent (can not be the
  --   case if some point to literally the same table)
  if H.is_table(res.groups) then
    for key, val in pairs(res.groups) do
      res.groups[key] = vim.deepcopy(val)
    end
  end

  -- Fields
  res.groups = res.groups or {}
  res.name = res.name
  res.terminal = res.terminal or {}

  -- Methods
  res.add_cterm_attributes = H.cs_add_cterm_attributes
  res.add_terminal_colors = H.cs_add_terminal_colors
  res.add_transparency = H.cs_add_transparency
  res.apply = H.cs_apply
  res.chan_add = H.cs_chan_add
  res.chan_invert = H.cs_chan_invert
  res.chan_modify = H.cs_chan_modify
  res.chan_multiply = H.cs_chan_multiply
  res.chan_repel = H.cs_chan_repel
  res.chan_set = H.cs_chan_set
  res.color_modify = H.cs_color_modify
  res.compress = H.cs_compress
  res.get_palette = H.cs_get_palette
  res.resolve_links = H.cs_resolve_links
  res.simulate_cvd = H.cs_simulate_cvd
  res.write = H.cs_write

  return res
end

--- Get colorscheme object from registered color scheme
---
---@param name string|nil Name of color scheme to use. If `nil` (default) creates
---  colorscheme object based on currently active data (|g:colors_name|,
---  highlight groups, terminal colors). If string, converts color scheme with
---  that name to a colorscheme object.
---@param opts table|nil Options. Possible fields:
---   - <new_name> `(string|nil)` - new name of colorscheme object.
---
---@return table Colorscheme object (|MiniColors-colorscheme|).
MiniColors.get_colorscheme = function(name, opts)
  if not (name == nil or type(name) == 'string') then H.error('Argument `name` should be string or `nil`.') end
  opts = vim.tbl_deep_extend('force', { new_name = nil }, opts or {})

  -- Return current color scheme if no `name` is supplied
  if name == nil then
    return MiniColors.as_colorscheme({
      name = opts.new_name or vim.g.colors_name,
      groups = H.get_current_groups(),
      terminal = H.get_current_terminal(),
    })
  end

  -- Source supplied color scheme, collect it and return back
  local current_cs = MiniColors.get_colorscheme()
  local res, au_id
  au_id = vim.api.nvim_create_autocmd('ColorScheme', {
    callback = function()
      res = MiniColors.get_colorscheme(nil, opts)
      -- Apply right now to avoid flickering
      current_cs:apply()
      -- Explicitly delete autocommand to account for error in `:colorscheme`
      vim.api.nvim_del_autocmd(au_id)
    end,
  })
  local ok, _ = pcall(vim.cmd, 'colorscheme ' .. name)
  if not ok then H.error(string.format('No color scheme named "%s".', name)) end

  return res
end

--- Start interactive experiments
---
--- Create a special buffer in which user can write plain Lua code to tweak
--- color scheme and apply to get visual feedback.
---
--- # General principles ~
--- - Initial colorscheme object is fixed to interactive buffer on its creation.
---
--- - There are special buffer convenience mappings:
---     - Apply (source) current buffer content.
---     - Reset color scheme (make initial colorscheme the current one).
---     - Write to a file the result of applying current buffer content.
---       This sources current content and calls |MiniColors-colorscheme:write()|.
---     - Quit interactive buffer.
---
--- - User is expected to iteratively tweak color scheme by writing general Lua
---   code in interactive buffer and applying it using convenience mapping.
---
--- - Application of interactive buffer is essentially these steps:
---     - Expose `self` as initial colorscheme object on any application.
---       It is always the same for every application.
---     - Expose initial colorscheme methods as standalone functions. So instead
---       of writing `self = self:add_transparency()` user can only write
---       `add_transparency()`.
---     - Source buffer content as plain Lua code.
---
--- Example of interactive buffer content: >lua
---
---   chan_modify('hue', function() return math.random(0, 359) end)
---   simulate_cvd('protan')
---   add_cterm_attributes()
---   add_terminal_colors()
--- <
---@param opts table|nil Options. Possible fields:
---   - <colorscheme> `(table|nil)` - |MiniColors-colorscheme| object to be
---     used as initial colorscheme for executed code. By default uses current
---     color scheme.
---   - <mappings> `table` - buffer mappings for actions. Possible fields:
---       - <Apply> `(string)` - apply buffer code. Default: `'<M-a>'`.
---       - <Reset> `(string)` - apply initial color scheme as is. Default: `'<M-r>'`.
---       - <Quit> `(string)` - close interactive buffer. Default: `'<M-q>'`.
---       - <Write> `(string)` - write result of buffer code into a file.
---         Prompts for file name with |vim.ui.input()| and then
---         uses |MiniColors-colorscheme:write()| with other options being default.
---         Default: `'<M-w>'`.
MiniColors.interactive = function(opts)
  opts = vim.tbl_deep_extend(
    'force',
    { colorscheme = nil, mappings = { Apply = '<M-a>', Reset = '<M-r>', Quit = '<M-q>', Write = '<M-w>' } },
    opts or {}
  )
  local maps = opts.mappings

  -- Prepare
  local init_cs = opts.colorscheme == nil and MiniColors.get_colorscheme()
    or MiniColors.as_colorscheme(opts.colorscheme)
  local buf_id = vim.api.nvim_create_buf(true, true)
  H.set_buf_name(buf_id, 'interactive')

  -- Write header lines
  local header_lines = {
    [[-- Experiment with color scheme using 'mini.colors']],
    '--',
    '-- Treat this as regular Lua file',
    '-- Methods of initial color scheme can be called directly',
    '-- See more in `:h MiniColors.interactive()`',
    '--',
    '-- Initial color scheme: ' .. (init_cs.name or '<unnamed>'),
    '-- Buffer-local mappings (Normal mode):',
    '--   Apply: ' .. maps.Apply,
    '--   Reset: ' .. maps.Reset,
    '--   Quit:  ' .. maps.Quit,
    '--   Write: ' .. maps.Write,
    '--',
    '-- Examples:',
    '--',
    '-- Invert dark/light color scheme to be light/dark',
    "-- chan_invert('lightness', { gamut_clip = 'cusp' })",
    '--',
    '-- Make foreground text more saturated',
    "-- chan_add('saturation', 20,  { filter = 'fg' })",
    '',
    '',
  }
  vim.api.nvim_buf_set_lines(buf_id, 0, -1, true, header_lines)

  -- Make local mappings
  local m = function(action, rhs) vim.keymap.set('n', maps[action], rhs, { desc = action, buffer = buf_id }) end

  m('Apply', function()
    local new_cs = H.apply_interactive_buffer(buf_id, init_cs)
    new_cs:apply()
  end)
  m('Reset', function() init_cs:apply() end)
  m('Quit', function()
    local ok, bufremove = pcall(require, 'mini.bufremove')
    if ok then
      bufremove.wipeout(buf_id, true)
    else
      vim.api.nvim_buf_delete(buf_id, { force = true })
    end
  end)
  m('Write', function()
    vim.ui.input(
      { prompt = [[Write to 'colors/' of your config under this name: ]], default = init_cs.name },
      function(input)
        if input == nil then return end
        local new_cs = H.apply_interactive_buffer(buf_id, init_cs)
        new_cs.name = input
        new_cs:write({ name = input })
      end
    )
  end)

  -- Set local options
  vim.bo[buf_id].filetype = 'lua'

  -- Make current
  vim.api.nvim_set_current_buf(buf_id)
  vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(buf_id), 0 })
end

--- Animate color scheme change
---
--- Start from currently active color scheme and loop through `cs_array`.
---
--- Powers |:Colorscheme| user command created in |MiniColors.setup()|.
---
---@param cs_array table Array of |MiniColors-colorscheme| objects.
---@param opts table|nil Options. Possible fields:
---   - <transition_steps> `(number)` - number of intermediate steps to show
---     during transition between two color schemes. Bigger values result in
---     smoother visual feedback but require more computational power.
---     Default: 25.
---   - <transition_duration> `(number)` - number of milliseconds to spend
---     showing transition. Default: 1000.
---   - <show_duration> `(number)` - number of milliseconds to show intermediate
---     color schemes (all but last in `cs_array`). Default: 1000.
MiniColors.animate = function(cs_array, opts)
  if not (H.islist(cs_array) and H.all(cs_array, H.is_colorscheme)) then
    H.error('Argument `cs_array` should be an array of color schemes.')
  end
  opts = vim.tbl_deep_extend(
    'force',
    { transition_steps = 25, transition_duration = 1000, show_duration = 1000 },
    opts or {}
  )

  if #cs_array == 0 then return end

  -- Pre-compute common data
  local cs_oklab = vim.tbl_map(function(cs) return H.cs_hex_to_oklab(vim.deepcopy(cs)) end, cs_array)
  local cs_oklab_current = H.cs_hex_to_oklab(MiniColors.get_colorscheme())

  -- Make "chain after action" which animates transitions one by one
  local cs_id, after_action = 1, nil
  after_action = function(data)
    -- Ensure authentic color scheme is active
    cs_array[cs_id]:apply()

    -- Advance if possible
    cs_id = cs_id + 1
    if #cs_array < cs_id then return end

    -- Wait before starting another animation
    local callback = function() H.animate_single_transition(cs_oklab[cs_id - 1], cs_oklab[cs_id], after_action, opts) end

    vim.defer_fn(callback, opts.show_duration)
  end

  H.animate_single_transition(cs_oklab_current, cs_oklab[1], after_action, opts)
end

--- Convert between color spaces
---
--- For a list of supported colors spaces see |MiniColors-color-spaces|.
---
---@param x table|string|number|nil Color to convert from. Its color space is
---   inferred automatically.
---@param to_space string Id of allowed color space.
---@param opts table|nil Options. Possible fields:
---   - <adjust_lightness> `(boolean)` - whether to adjust lightness value to have
---     a more uniform progression from 0 to 100. Set `false` for results more
---     compatible with some other Oklab/Oklch implementations (like in CSS).
---     Source: "Intermission - a new lightness estimate for Oklab" section of
---     https://bottosson.github.io/posts/colorpicker
---     Default: `true`.
---   - <gamut_clip> `(string)` - method for |MiniColors-gamut-clip|.
---     Default: `'chroma'`.
---
---@return table|string|number|nil Color in space `to_space` or `nil` if input is `nil`.
MiniColors.convert = function(x, to_space, opts)
  if x == nil then return nil end
  if not vim.tbl_contains(H.allowed_spaces, to_space) then
    local spaces = table.concat(vim.tbl_map(vim.inspect, H.allowed_spaces), ', ')
    H.error('Argument `to_space` should be one of ' .. spaces .. '.')
  end
  opts = vim.tbl_deep_extend('force', { adjust_lightness = true, gamut_clip = 'chroma' }, opts or {})

  -- Set reference value here once to not have to pass it as argument to many
  -- downstream places
  H.adjust_lightness = opts.adjust_lightness
  return H.converters[to_space](x, H.infer_color_space(x), opts)
end

--- Modify channel
---
---@param x table|string|number|nil Color which channel will be modified. Color
---   space is inferred automatically.
---@param channel string One of supported |MiniColors-channels|.
---@param f function Callable which defines modification. Should take current
---   value of a channel and return a new one.
---@param opts table|nil Options. Possible fields:
---   - <gamut_clip> `(string)` - method for |MiniColors-gamut-clip|.
---     Default: `'chroma'`.
---
---@return string|nil Hex string of color with modified channel or `nil` if input is `nil`.
MiniColors.modify_channel = function(x, channel, f, opts)
  channel = H.normalize_channel(channel)
  f = H.normalize_f(f)
  opts = vim.tbl_deep_extend('force', { gamut_clip = 'chroma' }, opts or {})

  local modify_channel = H.channel_modifiers[channel]
  return modify_channel(x, f, opts.gamut_clip)
end

--- Simulate color vision deficiency
---
---@param x table|string|number|nil Color to convert from. Its color space is
---   inferred automatically.
---@param cvd_type string Type of CVD. One of `'protan'`, `'deutan'`,
---`'tritan'`, or `'mono'` (equivalent to converting to graysacle).
---@param severity number|nil Severity of CVD. A number between 0 and 1 (default).
---
---@return string|nil Hex string of simulated color or `nil` if input is `nil`.
MiniColors.simulate_cvd = function(x, cvd_type, severity)
  if x == nil then return nil end
  if not (cvd_type == 'protan' or cvd_type == 'deutan' or cvd_type == 'tritan' or cvd_type == 'mono') then
    H.error('Argument `cvd_type` should be one of "protan", "deutan", "tritan", "mono".')
  end
  severity = severity or 1
  if not H.is_number(severity) then H.error('Argument `severity` should be number.') end

  -- Simulate monochromacy by setting zero 'crhoma'
  if cvd_type == 'mono' then
    local lch = MiniColors.convert(x, 'oklch')
    lch.c, lch.h = 0, nil
    ---@diagnostic disable:return-type-mismatch
    return MiniColors.convert(lch, 'hex')
  end

  -- Simulate regular CVD by multiplying with appropriate matrix
  severity = H.clip(H.round(10 * severity), 0, 10)
  local mat = H.cvd_matricies[cvd_type][severity]
  local rgb = MiniColors.convert(x, 'rgb')
  local new_rgb = {
    r = mat[1][1] * rgb.r + mat[1][2] * rgb.g + mat[1][3] * rgb.b,
    g = mat[2][1] * rgb.r + mat[2][2] * rgb.g + mat[2][3] * rgb.b,
    b = mat[3][1] * rgb.r + mat[3][2] * rgb.g + mat[3][3] * rgb.b,
  }

  return H.rgb2hex(new_rgb)
end

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniColors.config)

-- Color conversion constants
H.tau = 2 * math.pi

-- Cusps for Oklch color space. These represent (c, l) points of Oklch space
-- (with **not corrected lightness**) inside a hue leaf (points with
-- `math.floor(h) = <index>`) with the highest value of chroma (`c`).
-- They are used to model the whole RGB gamut (region inside which sRGB colors
-- are converted in Oklch space). It is modelled as triangle with vertices:
-- (0, 0), (0, 100) and cusp. NOTE: this is an approximation, i.e. not all RGB
-- colors lie inside this triangle **AND** not all points inside triangle are
-- RGB colors. But both proportions are small: around 0.5% with similar modeled
-- RGB color for first one and around 2.16% for second one.
--stylua: ignore start
---@diagnostic disable start
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

-- Matrices used to simulate color vision deficiency (CVD; color blindness).
-- Each first-level entry describes CVD type; second-level - severity times 10.
-- Source:
-- https://www.inf.ufrgs.br/~oliveira/pubs_files/CVD_Simulation/CVD_Simulation.html
H.cvd_matricies = {
  protan = {
    [00]={{1.000000, 0.000000,  -0.000000}, {0.000000,  1.000000, 0.000000}, {-0.000000, -0.000000, 1.000000}},
    [01]={{0.856167, 0.182038,  -0.038205}, {0.029342,  0.955115, 0.015544}, {-0.002880, -0.001563, 1.004443}},
    [02]={{0.734766, 0.334872,  -0.069637}, {0.051840,  0.919198, 0.028963}, {-0.004928, -0.004209, 1.009137}},
    [03]={{0.630323, 0.465641,  -0.095964}, {0.069181,  0.890046, 0.040773}, {-0.006308, -0.007724, 1.014032}},
    [04]={{0.539009, 0.579343,  -0.118352}, {0.082546,  0.866121, 0.051332}, {-0.007136, -0.011959, 1.019095}},
    [05]={{0.458064, 0.679578,  -0.137642}, {0.092785,  0.846313, 0.060902}, {-0.007494, -0.016807, 1.024301}},
    [06]={{0.385450, 0.769005,  -0.154455}, {0.100526,  0.829802, 0.069673}, {-0.007442, -0.022190, 1.029632}},
    [07]={{0.319627, 0.849633,  -0.169261}, {0.106241,  0.815969, 0.077790}, {-0.007025, -0.028051, 1.035076}},
    [08]={{0.259411, 0.923008,  -0.182420}, {0.110296,  0.804340, 0.085364}, {-0.006276, -0.034346, 1.040622}},
    [09]={{0.203876, 0.990338,  -0.194214}, {0.112975,  0.794542, 0.092483}, {-0.005222, -0.041043, 1.046265}},
    [10]={{0.152286, 1.052583,  -0.204868}, {0.114503,  0.786281, 0.099216}, {-0.003882, -0.048116, 1.051998}},
  },
  deutan = {
    [00]={{1.000000, 0.000000,  -0.000000}, {0.000000,  1.000000, 0.000000}, {-0.000000, -0.000000, 1.000000}},
    [01]={{0.866435, 0.177704,  -0.044139}, {0.049567,  0.939063, 0.011370}, {-0.003453, 0.007233,  0.996220}},
    [02]={{0.760729, 0.319078,  -0.079807}, {0.090568,  0.889315, 0.020117}, {-0.006027, 0.013325,  0.992702}},
    [03]={{0.675425, 0.433850,  -0.109275}, {0.125303,  0.847755, 0.026942}, {-0.007950, 0.018572,  0.989378}},
    [04]={{0.605511, 0.528560,  -0.134071}, {0.155318,  0.812366, 0.032316}, {-0.009376, 0.023176,  0.986200}},
    [05]={{0.547494, 0.607765,  -0.155259}, {0.181692,  0.781742, 0.036566}, {-0.010410, 0.027275,  0.983136}},
    [06]={{0.498864, 0.674741,  -0.173604}, {0.205199,  0.754872, 0.039929}, {-0.011131, 0.030969,  0.980162}},
    [07]={{0.457771, 0.731899,  -0.189670}, {0.226409,  0.731012, 0.042579}, {-0.011595, 0.034333,  0.977261}},
    [08]={{0.422823, 0.781057,  -0.203881}, {0.245752,  0.709602, 0.044646}, {-0.011843, 0.037423,  0.974421}},
    [09]={{0.392952, 0.823610,  -0.216562}, {0.263559,  0.690210, 0.046232}, {-0.011910, 0.040281,  0.971630}},
    [10]={{0.367322, 0.860646,  -0.227968}, {0.280085,  0.672501, 0.047413}, {-0.011820, 0.042940,  0.968881}},
  },
  tritan = {
    [00]={{1.000000, 0.000000,  -0.000000}, {0.000000,  1.000000, 0.000000}, {-0.000000, -0.000000, 1.000000}},
    [01]={{0.926670, 0.092514,  -0.019184}, {0.021191,  0.964503, 0.014306}, {0.008437,  0.054813,  0.936750}},
    [02]={{0.895720, 0.133330,  -0.029050}, {0.029997,  0.945400, 0.024603}, {0.013027,  0.104707,  0.882266}},
    [03]={{0.905871, 0.127791,  -0.033662}, {0.026856,  0.941251, 0.031893}, {0.013410,  0.148296,  0.838294}},
    [04]={{0.948035, 0.089490,  -0.037526}, {0.014364,  0.946792, 0.038844}, {0.010853,  0.193991,  0.795156}},
    [05]={{1.017277, 0.027029,  -0.044306}, {-0.006113, 0.958479, 0.047634}, {0.006379,  0.248708,  0.744913}},
    [06]={{1.104996, -0.046633, -0.058363}, {-0.032137, 0.971635, 0.060503}, {0.001336,  0.317922,  0.680742}},
    [07]={{1.193214, -0.109812, -0.083402}, {-0.058496, 0.979410, 0.079086}, {-0.002346, 0.403492,  0.598854}},
    [08]={{1.257728, -0.139648, -0.118081}, {-0.078003, 0.975409, 0.102594}, {-0.003316, 0.501214,  0.502102}},
    [09]={{1.278864, -0.125333, -0.153531}, {-0.084748, 0.957674, 0.127074}, {-0.000989, 0.601151,  0.399838}},
    [10]={{1.255528, -0.076749, -0.178779}, {-0.078411, 0.930809, 0.147602}, {0.004733,  0.691367,  0.303900}},
  },
}
---@diagnostic disable end
--stylua: ignore end

H.allowed_spaces = { '8-bit', 'hex', 'rgb', 'oklab', 'oklch', 'okhsl' }

H.allowed_channels =
  { 'lightness', 'chroma', 'saturation', 'hue', 'temperature', 'pressure', 'a', 'b', 'red', 'green', 'blue' }

H.ns_id = { interactive = vim.api.nvim_create_namespace('MiniColorsInteractive') }

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  return config
end

H.apply_config = function(config) MiniColors.config = config end

H.get_config = function(config)
  return vim.tbl_deep_extend('force', MiniColors.config, vim.b.minicolors_config or {}, config or {})
end

H.create_user_commands = function()
  local callback = function(input)
    local cs_array = vim.tbl_map(MiniColors.get_colorscheme, input.fargs)
    MiniColors.animate(cs_array)
  end
  vim.api.nvim_create_user_command('Colorscheme', callback, { nargs = '+', complete = 'color' })
end

-- Color scheme methods -------------------------------------------------------
H.cs_add_cterm_attributes = function(self, opts)
  local res = vim.deepcopy(self)
  opts = vim.tbl_deep_extend('force', { force = true }, opts or {})

  -- Compute Oklab coordinates of terminal colors for better approximation
  local term_oklab = H.compute_term_oklab()

  local force = opts.force
  for _, gr in pairs(res.groups) do
    if gr.fg and (force or not gr.ctermfg) then gr.ctermfg = H.get_closest_color_id(gr.fg, term_oklab) end
    if gr.bg and (force or not gr.ctermbg) then gr.ctermbg = H.get_closest_color_id(gr.bg, term_oklab) end
  end

  return res
end

H.cs_add_terminal_colors = function(self, opts)
  local res = vim.deepcopy(self)
  opts = vim.tbl_deep_extend('force', { force = true, palette_args = {} }, opts or {})

  -- General meaning of terminal colors are taken from here:
  -- https://en.wikipedia.org/wiki/ANSI_escape_code#3-bit_and_4-bit
  -- Regular and bright versions will be equal (to simplify algorithm)

  -- Compress (for better palette representation) and resolve links (accounts
  -- for possibly linked 'Normal' group)
  local cs = res:compress():resolve_links()

  -- Get palette and convert in Oklch
  local palette = cs:get_palette(opts.palette_args)
  local palette_oklch = vim.tbl_map(function(x) return MiniColors.convert(x, 'oklch') end, palette)

  local terminal = {}

  -- Black and white are colors from `Normal` group.
  local normal = cs.groups.Normal or {}
  local black, white = normal.bg, normal.fg

  terminal[0], terminal[8] = black, black
  terminal[7], terminal[15] = white, white

  -- Colors are computed as closest to reference (pre-defined hue with white
  -- lightness) taking into account only normalized lightness and hue
  local white_oklch = MiniColors.convert(white, 'oklch')
  local ref_l = white ~= nil and white_oklch.l or (vim.o.background == 'dark' and 85 or 15)
  local ref_color_data = {
    { l = ref_l, h = 30 }, -- Red
    { l = ref_l, h = 150 }, -- Green
    { l = ref_l, h = 90 }, -- Yellow
    { l = ref_l, h = 270 }, -- Blue
    { l = ref_l, h = 330 }, -- Magenta
    { l = ref_l, h = 210 }, -- Cyan
  }
  local dist_color = function(x, y) return H.dist(x.l, y.l) / 100 + H.dist_circle(x.h, y.h) / 90 end
  for i, ref in ipairs(ref_color_data) do
    local col = H.get_closest(ref, palette_oklch, dist_color)
    terminal[i], terminal[i + 8] = col, col
  end

  -- Update current `terminal` field
  for i = 0, 15 do
    if opts.force or not res.terminal[i] then res.terminal[i] = MiniColors.convert(terminal[i], 'hex') end
  end

  return res
end

H.cs_add_transparency = function(self, opts)
  opts = vim.tbl_deep_extend('force', {
    general = true,
    float = false,
    statuscolumn = false,
    statusline = false,
    tabline = false,
    winbar = false,
  }, opts or {})

  local res = vim.deepcopy(self)
  local groups = res.groups
  local update = function(names)
    for _, n in pairs(names) do
      local gr = groups[n]
      if gr == nil then return end
      gr.bg, gr.ctermbg = nil, nil
      gr.blend = 0
    end
  end

  if opts.general then
    update({ 'Normal', 'NormalNC', 'EndOfBuffer', 'MsgArea', 'MsgSeparator', 'VertSplit', 'WinSeparator' })
    update({ 'ErrorMsg', 'WarningMsg', 'OkMsg', 'ModeMsg', 'MoreMsg', 'StderrMsg', 'StdoutMsg' })
  end

  if opts.float then update({ 'FloatBorder', 'FloatTitle', 'NormalFloat' }) end

  if opts.statuscolumn then
    update({ 'FoldColumn', 'LineNr', 'LineNrAbove', 'LineNrBelow', 'SignColumn' })
    local diag_hl = vim.tbl_map(function(x) return 'DiagnosticSign' .. x end, { 'Error', 'Warn', 'Info', 'Hint', 'Ok' })
    update(diag_hl)

    -- Remove statuscolumn background coming from signs
    local signs = vim.fn.sign_getdefined()
    local groups = {}
    for _, sign in ipairs(vim.fn.sign_getdefined()) do
      table.insert(groups, sign.texthl)
      table.insert(groups, sign.numhl)
    end
    update(groups)
  end

  if opts.statusline then update({ 'StatusLine', 'StatusLineNC', 'StatusLineTerm', 'StatusLineTermNC' }) end

  if opts.tabline then update({ 'TabLine', 'TabLineFill', 'TabLineSel' }) end

  if opts.winbar then update({ 'WinBar', 'WinBarNC' }) end

  return res
end

H.cs_apply = function(self, opts)
  opts = vim.tbl_deep_extend('force', { clear = true }, opts or {})

  if opts.clear then vim.cmd('highlight clear') end
  vim.g.colors_name = self.name

  -- Highlight groups
  local hi = vim.api.nvim_set_hl
  local groups_arr = H.hl_groups_to_array(self.groups)
  for _, hl_data in ipairs(groups_arr) do
    hi(0, hl_data.name, hl_data.spec)
  end

  -- Terminal colors. Apply all colors in order to possibly remove previously
  -- set ones.
  for i = 0, 15 do
    vim.g['terminal_color_' .. i] = self.terminal[i]
  end

  return self
end

H.cs_chan_add = function(self, channel, value, opts)
  channel = H.normalize_channel(channel)
  value = H.normalize_number(value, 'value')
  if value == 0 then return vim.deepcopy(self) end

  return self:chan_modify(channel, function(x) return x + value end, opts)
end

H.cs_chan_invert = function(self, channel, opts)
  channel = H.normalize_channel(channel)
  -- Don't invert 'chroma' directly because of lack of useful reference point
  if channel == 'chroma' then channel = 'saturation' end
  return self:chan_modify(channel, H.chan_inverters[channel], opts)
end

H.cs_chan_modify = function(self, channel, f, opts)
  channel = H.normalize_channel(channel)
  f = H.normalize_f(f)
  opts = opts or {}
  local filter = H.normalize_filter(opts.filter)
  local gamut_clip = H.normalize_gamut_clip(opts.gamut_clip)

  local modify_channel = H.channel_modifiers[channel]

  local f_color = function(hex, data)
    if not filter(hex, data) then return hex end
    return modify_channel(hex, f, gamut_clip)
  end

  return self:color_modify(f_color)
end

H.cs_chan_multiply = function(self, channel, coef, opts)
  channel = H.normalize_channel(channel)
  coef = H.normalize_number(coef, 'coef')
  if coef == 1 then return vim.deepcopy(self) end

  return self:chan_modify(channel, function(x) return coef * x end, opts)
end

H.cs_chan_repel = function(self, channel, sources, coef, opts)
  channel = H.normalize_channel(channel)
  sources = H.normalize_number_array(sources, 'sources')
  coef = H.normalize_number(coef, 'coef')

  if #sources == {} or coef == 0 then return vim.deepcopy(self) end

  -- Account for periodic nature of "hue" channel
  sources = channel == 'hue' and H.add_circle_sources(sources) or sources
  local tie_breaker = H.repel_tie_breakers[channel]
  local f = function(x) return H.repel(x, sources, coef, tie_breaker) end

  return self:chan_modify(channel, f, opts)
end

H.cs_chan_set = function(self, channel, values, opts)
  channel = H.normalize_channel(channel)
  values = H.normalize_number_array(values, 'values')
  if #values == 0 then return H.error('Argument `values` should not be empty.') end

  local dist_fun = channel == 'hue' and H.dist_circle or H.dist
  local f = function(x) return H.get_closest(x, values, dist_fun) end

  return self:chan_modify(channel, f, opts)
end

H.cs_color_modify = function(self, f)
  f = H.normalize_f(f)

  local res = vim.deepcopy(self)

  -- Highlight groups
  for name, spec in pairs(res.groups) do
    if spec.fg ~= nil then spec.fg = f(spec.fg, { attr = 'fg', name = name }) end
    if spec.bg ~= nil then spec.bg = f(spec.bg, { attr = 'bg', name = name }) end
    if spec.sp ~= nil then spec.sp = f(spec.sp, { attr = 'sp', name = name }) end
  end

  -- Terminal colors
  for i, hex in pairs(res.terminal) do
    res.terminal[i] = f(hex, { attr = 'term', name = 'terminal_color_' .. i })
  end

  return res
end

H.cs_compress = function(self, opts)
  opts = vim.tbl_deep_extend('force', { plugins = true }, opts or {})
  local current_cs = MiniColors.get_colorscheme()

  vim.cmd('highlight clear')
  local clear_cs_groups = MiniColors.get_colorscheme().groups

  local new_groups = {}
  for name, spec in pairs(self.groups) do
    -- Group should stay only if it adds new information compared to the state
    -- after `:hi clear`
    local is_from_clear = vim.deep_equal(clear_cs_groups[name], spec)

    -- `^DevIcon` groups come from 'nvim-tree/nvim-web-devicons' and don't
    -- really have value outside of that plugin. Plus there are **many** of
    -- them and they are created in that plugin.
    local is_devicon = opts.plugins and name:find('^DevIcon') ~= nil

    -- `^colorizer_` groups come from 'norcalli/nvim-colorizer.lua' plugin and
    -- don't really have value outside of that plugin.
    local is_colorizer = opts.plugins and name:find('^colorizer_') ~= nil

    -- 'mini.hipatterns' defines groups for hex color highlighting
    local is_hipatterns_hex_color = opts.plugins and name:find('^MiniHipatterns%x%x%x%x%x%x$') ~= nil

    if not (is_from_clear or is_devicon or is_colorizer) then new_groups[name] = spec end
  end

  current_cs:apply()

  return MiniColors.as_colorscheme({ name = self.name, groups = new_groups, terminal = self.terminal })
end

H.cs_get_palette = function(self, opts)
  opts = vim.tbl_deep_extend('force', { threshold = 0.01 }, opts or {})

  -- Traverse all colors
  local colors, n_color_uses = {}, 0
  self:color_modify(function(hex)
    colors[hex] = (colors[hex] or 0) + 1
    n_color_uses = n_color_uses + 1
  end)

  -- Filter out and sort in descending order of lightness
  local all_colors = {}
  for hex, count in pairs(colors) do
    if opts.threshold <= (count / n_color_uses) then
      table.insert(all_colors, { hex, MiniColors.convert(hex, 'oklch').l })
    end
  end
  table.sort(all_colors, function(a, b) return a[2] < b[2] end)

  return vim.tbl_map(function(x) return x[1] end, all_colors)
end

H.cs_resolve_links = function(self)
  local res = vim.deepcopy(self)

  -- Resolve direct links (highlight groups linking to group without link)
  -- iteratively one level at a time
  repeat
    local n_resolved_links = 0
    for hl_name, hl_data in pairs(res.groups) do
      -- Resolve link only if:
      -- - Current highlight group is linked.
      -- - Target link is present in color scheme and is not itself linked.
      local link_data = res.groups[hl_data.link]
      if link_data ~= nil and link_data.link == nil then
        res.groups[hl_name] = vim.deepcopy(res.groups[hl_data.link])
        n_resolved_links = n_resolved_links + 1
      end
    end
  until n_resolved_links == 0

  return res
end

H.cs_simulate_cvd = function(self, cvd_type, severity, opts)
  local f = function(hex) return MiniColors.simulate_cvd(hex, cvd_type, severity, opts) end
  return self:color_modify(f)
end

H.cs_write = function(self, opts)
  opts = vim.tbl_extend(
    'force',
    { compress = true, directory = (vim.fn.stdpath('config') .. '/colors'), name = nil },
    opts or {}
  )

  local name = opts.name or H.make_file_basename(self.name or 'mini_colors')

  local cs = opts.compress and self:compress() or self

  -- Create file lines
  -- - Header
  local lines = {
    [[-- Made with 'mini.colors' module of https://github.com/nvim-mini/mini.nvim]],
    '',
    [[if vim.g.colors_name ~= nil then vim.cmd('highlight clear') end]],
    'vim.g.colors_name = ' .. vim.inspect(cs.name),
  }

  -- - Highlight groups
  if vim.tbl_count(cs.groups) > 0 then
    vim.list_extend(lines, { '', '-- Highlight groups', 'local hi = vim.api.nvim_set_hl', '' })
  else
    vim.list_extend(lines, { '', '-- No highlight groups defined' })
  end

  local make_hi_line = function(hl)
    local spec = setmetatable(hl.spec, nil)
    return string.format('hi(0, "%s", %s)', hl.name, vim.inspect(spec, { newline = ' ', indent = '' }))
  end
  vim.list_extend(lines, vim.tbl_map(make_hi_line, H.hl_groups_to_array(cs.groups)))

  -- - Terminal colors
  if vim.tbl_count(cs.terminal) > 0 then
    vim.list_extend(lines, { '', '-- Terminal colors', 'local g = vim.g', '' })
  else
    vim.list_extend(lines, { '', '-- No terminal colors defined' })
  end

  for i, hex in pairs(cs.terminal) do
    local l = string.format('g.terminal_color_%d = "%s"', i, hex)
    table.insert(lines, l)
  end

  -- Create file and populate with computed lines
  vim.fn.mkdir(opts.directory, 'p')
  local path = string.format('%s/%s.lua', opts.directory, name)
  vim.fn.writefile(lines, path)

  return self
end

H.is_colorscheme = function(x) return type(x) == 'table' and type(x.groups) == 'table' and type(x.terminal) == 'table' end

H.normalize_f = function(f)
  if not vim.is_callable(f) then H.error('Argument `f` should be callable.') end
  return f
end

H.normalize_channel = function(x)
  if not vim.tbl_contains(H.allowed_channels, x) then
    local allowed = table.concat(vim.tbl_map(vim.inspect, H.allowed_channels), ', ')
    local msg = string.format('Channel should be one of %s. Not %s.', allowed, vim.inspect(x))
    H.error(msg)
  end
  return x
end

H.normalize_filter = function(x)
  -- Treat `nil` filter as no filter
  if x == nil then x = function() return true end end

  -- Treat string filter as filter on attribute ('fg', 'bg', etc.)
  if x == 'fg' or x == 'bg' or x == 'sp' or x == 'term' then
    local attr_val = x
    x = function(_, data) return data.attr == attr_val end
  end

  if not vim.is_callable(x) then
    H.error('Argument `opts.filter` should be either proper attribute string or callable.')
  end

  return x
end

H.normalize_gamut_clip = function(x)
  x = x or 'chroma'
  if x == 'chroma' or x == 'lightness' or x == 'cusp' then return x end
  H.error('Argument `opts.gamut_clip` should one of "chroma", "lightness", "cusp".')
end

H.normalize_number = function(x, arg_name)
  if type(x) ~= 'number' then H.error('Argument `' .. arg_name .. '` should be a number.') end
  return x
end

H.normalize_number_array = function(x, arg_name)
  if H.is_number(x) then x = { x } end
  if not (H.is_table(x) and H.all(x, H.is_number)) then
    H.error('Argument `' .. arg_name .. '` should be number or array of numbers.')
  end
  return x
end

-- Color scheme helpers -------------------------------------------------------
H.make_file_basename = function(name)
  -- If there already is color scheme named `name`, append unique suffix
  local all_colorschemes = vim.fn.getcompletion('', 'color')

  if not vim.tbl_contains(all_colorschemes, name) then return name end
  return name .. vim.fn.strftime('_%Y%m%d_%H%M%S')
end

-- -- TODO: Use `vim.api.nvim_get_hl()` when it is more stable (doesn't have
--    issues with including not created highlight highlight groups for semantic
--    tokens)
-- H.get_current_groups = function()
--   local res = {}
--
--   for name, new_t in pairs(vim.api.nvim_get_hl(0, {})) do
--     -- Return plain `{}` instead of `vim.empty_dict()`
--     local new_t = setmetatable(new_t, nil)
--     -- Use HEX when needed
--     new_t.fg, new_t.bg, new_t.sp = H.dec2hex(new_t.fg), H.dec2hex(new_t.bg), H.dec2hex(new_t.sp)
--     res[name] = new_t
--   end
--
--   return res
-- end

H.get_current_groups = function()
  -- Get present highlight group names and if they are linked
  local group_data = vim.split(vim.api.nvim_exec('highlight', true), '\n')
  local group_names = vim.tbl_map(function(x) return x:match('^(%S+)') end, group_data)
  local link_data = vim.tbl_map(function(x) return x:match('^%S+.* links to (%S+)$') end, group_data)

  local res = {}
  for i, name in pairs(group_names) do
    if link_data[i] ~= nil then
      res[name] = { link = link_data[i] }
    else
      res[name] = H.get_hl_by_name(name)
    end
  end
  return res
end

H.get_hl_by_name = function(name)
  local res = vim.api.nvim_get_hl_by_name(name, true)

  -- Convert decimal colors to hex strings
  res.fg = H.dec2hex(res.foreground)
  res.bg = H.dec2hex(res.background)
  res.sp = H.dec2hex(res.special)

  res.foreground, res.background, res.special = nil, nil, nil

  -- Add terminal colors
  local cterm_data = vim.api.nvim_get_hl_by_name(name, false)
  res.ctermfg = cterm_data.foreground
  res.ctermbg = cterm_data.background

  -- At the moment, having `res[true] = 6` indicates that group is cleared
  -- NOTE: actually return empty dictionary and not `nil` to preserve
  -- information that group was cleared. This might matter if highlight group
  -- was cleared but default links to something else (like if group
  -- `@lsp.type.variable` is cleared to use tree-sitter highlighting but by
  -- default it links to `Identifier`).
  res[true] = nil

  -- Return plain `{}` instead of `vim.empty_dict()`
  return setmetatable(res, nil)
end

H.get_current_terminal = function()
  local res = {}
  for i = 0, 15 do
    local col = vim.g['terminal_color_' .. i]
    if type(col) == 'string' then res[i] = H.dec2hex(vim.api.nvim_get_color_by_name(col)) end
  end

  return res
end

H.dec2hex = function(dec)
  if dec == nil or dec < 0 then return nil end
  return string.format('#%06x', dec)
end

H.hl_groups_to_array = function(hl_groups)
  local res = {}
  for name, spec in pairs(hl_groups) do
    table.insert(res, { name = name, spec = spec })
  end
  table.sort(res, function(a, b) return a.name < b.name end)
  return res
end

-- Terminal colors ------------------------------------------------------------
-- Source: https://en.wikipedia.org/wiki/ANSI_escape_code#8-bit
H.compute_term_oklab = function()
  -- Use cached values if they are already computed
  if H.term_oklab ~= nil then return H.term_oklab end

  local res = {}

  -- Main colors. Don't use 0-15 because they are terminal dependent
  local cterm_basis = { 0, 95, 135, 175, 215, 255 }
  for i = 16, 231 do
    local j = i - 16
    local r = cterm_basis[math.floor(j / 36) % 6 + 1]
    local g = cterm_basis[math.floor(j / 6) % 6 + 1]
    local b = cterm_basis[j % 6 + 1]
    res[i] = MiniColors.convert({ r = r, g = g, b = b }, 'oklab')
  end

  -- Grays
  for i = 232, 255 do
    local c = 8 + (i - 232) * 10
    res[i] = MiniColors.convert({ r = c, g = c, b = c }, 'oklab')
  end

  H.term_oklab = res
  return res
end

H.get_closest_color_id = function(x, ref_oklab)
  local _, res = H.get_closest(MiniColors.convert(x, 'oklab'), ref_oklab, H.dist_oklab)
  return res
end

-- Animation ------------------------------------------------------------------
H.animate_single_transition = function(from_cs, to_cs, after_action, opts)
  local all_group_names = H.union(vim.tbl_keys(from_cs.groups), vim.tbl_keys(to_cs.groups))
  local n_steps = math.max(opts.transition_steps, 1)
  local step_duration = math.max(opts.transition_duration / n_steps, 1)

  -- Start animation
  local cur_step = 1
  local timer = vim.uv.new_timer()

  local apply_step
  apply_step = vim.schedule_wrap(function()
    -- Ensure that current step is not too big. This handles weird issue with
    -- small `step_duration` when this continued calling after `timer:stop()`.
    -- Probably due to considerable time it takes to execute single step.
    if n_steps < cur_step then return end

    -- Compute and apply transition step
    local cs_step = H.compute_animate_step(from_cs, to_cs, cur_step / n_steps, all_group_names)
    -- - Use implementation helper instead of using `as_colorscheme()` to avoid
    --   unnecessary `deepcopy()` increasing performance
    H.cs_apply(cs_step)
    vim.cmd('redraw')

    -- Advance
    cur_step = cur_step + 1
    if n_steps < cur_step then
      timer:stop()
      pcall(after_action, { n_steps = n_steps, cur_step = cur_step })
      return
    end

    -- Handle timer repeat here in order to ensure concurrency of steps
    timer:set_repeat(step_duration)
    timer:again()
  end)

  -- Start non-repeating timer
  timer:start(step_duration, 0, apply_step)
end

H.cs_hex_to_oklab = function(cs)
  local to_oklab = function(hex) return MiniColors.convert(hex, 'oklab') end
  cs.groups = vim.tbl_map(function(gr)
    gr.fg, gr.bg, gr.sp = to_oklab(gr.fg), to_oklab(gr.bg), to_oklab(gr.sp)
    return gr
  end, cs.groups)

  cs.terminal = vim.tbl_map(to_oklab, cs.terminal)

  return cs
end

H.cs_oklab_to_hex = function(cs)
  -- 'chroma' clipping preserves lightness resulting into smoother transitions
  local to_hex = function(lab) return MiniColors.convert(lab, 'hex', { gamut_clip = 'chroma' }) end
  cs.groups = vim.tbl_map(function(gr)
    gr.fg, gr.bg, gr.sp = to_hex(gr.fg), to_hex(gr.bg), to_hex(gr.sp)
    return gr
  end, cs.groups)

  cs.terminal = vim.tbl_map(to_hex, cs.terminal)

  return cs
end

H.compute_animate_step = function(from, to, coef, all_group_names)
  local groups = {}
  for _, name in ipairs(all_group_names) do
    groups[name] = H.convex_hl_group(from.groups[name], to.groups[name], coef)
  end

  local terminal = {}
  for i = 0, 15 do
    terminal[i] = H.convex_lab(from.terminal[i], to.terminal[i], coef)
  end

  local cs_data = { name = 'transition_step', groups = groups, terminal = terminal }
  return H.cs_oklab_to_hex(cs_data)
end

H.convex_hl_group = function(from, to, coef)
  if from == nil or to == nil or from.link ~= nil or to.link ~= nil then return H.convex_discrete(from, to, coef) end

  --stylua: ignore
  return {
    -- No `cterm` in convex combination because it is not trivial to create
    -- proper gradient for them
    fg = H.convex_lab(from.fg, to.fg, coef),
    bg = H.convex_lab(from.bg, to.bg, coef),
    sp = H.convex_lab(from.sp, to.sp, coef),

    blend = H.round(H.convex_continuous(from.blend, to.blend, coef)),

    bold          = H.convex_discrete(from.bold,          to.bold,          coef),
    italic        = H.convex_discrete(from.italic,        to.italic,        coef),
    nocombine     = H.convex_discrete(from.nocombine,     to.nocombine,     coef),
    reverse       = H.convex_discrete(from.reverse,       to.reverse,       coef),
    standout      = H.convex_discrete(from.standout,      to.standout,      coef),
    strikethrough = H.convex_discrete(from.strikethrough, to.strikethrough, coef),
    undercurl     = H.convex_discrete(from.undercurl,     to.undercurl,     coef),
    underdashed   = H.convex_discrete(from.underdashed,   to.underdashed,   coef),
    underdotted   = H.convex_discrete(from.underdotted,   to.underdotted,   coef),
    underdouble   = H.convex_discrete(from.underdouble,   to.underdouble,   coef),
    underline     = H.convex_discrete(from.underline,     to.underline,     coef),
  }
end

H.convex_lab = function(from_lab, to_lab, coef)
  if from_lab == nil or to_lab == nil then return H.convex_discrete(from_lab, to_lab, coef) end
  return {
    l = H.convex_continuous(from_lab.l, to_lab.l, coef),
    a = H.convex_continuous(from_lab.a, to_lab.a, coef),
    b = H.convex_continuous(from_lab.b, to_lab.b, coef),
  }
end

-- Channel modifiers ----------------------------------------------------------
H.channel_modifiers = {}

H.channel_modifiers.lightness = function(hex, f, gamut_clip)
  local lch = MiniColors.convert(hex, 'oklch')
  lch.l = H.clip(f(lch.l), 0, 100)
  return MiniColors.convert(lch, 'hex', { gamut_clip = gamut_clip })
end

H.channel_modifiers.chroma = function(hex, f, gamut_clip)
  local lch = MiniColors.convert(hex, 'oklch')
  lch.c = H.clip(f(lch.c), 0, math.huge)
  return MiniColors.convert(lch, 'hex', { gamut_clip = gamut_clip })
end

H.channel_modifiers.saturation = function(hex, f, gamut_clip)
  local lsh = MiniColors.convert(hex, 'okhsl')
  lsh.s = H.clip(f(lsh.s), 0, 100)
  return MiniColors.convert(lsh, 'hex', { gamut_clip = gamut_clip })
end

H.channel_modifiers.hue = function(hex, f, gamut_clip)
  local lch = MiniColors.convert(hex, 'oklch')
  if lch.h == nil then return hex end
  lch.h = f(lch.h) % 360
  return MiniColors.convert(lch, 'hex', { gamut_clip = gamut_clip })
end

H.channel_modifiers.temperature = function(hex, f, gamut_clip)
  local lch = MiniColors.convert(hex, 'oklch')
  if lch.h == nil then return hex end

  -- Temperature is a circular distance to 270 hue degrees
  -- Output value will lie in the same vertical half plane
  local is_left = 90 <= lch.h and lch.h < 270
  local temp = (is_left and (270 - lch.h) or (lch.h + 90)) % 360
  local new_temp = H.clip(f(temp), 0, 180)
  lch.h = (is_left and (270 - new_temp) or (new_temp - 90)) % 360

  return MiniColors.convert(lch, 'hex', { gamut_clip = gamut_clip })
end

H.channel_modifiers.pressure = function(hex, f, gamut_clip)
  local lch = MiniColors.convert(hex, 'oklch')
  if lch.h == nil then return hex end

  -- Pressure is a circular distance to 180 hue degrees
  -- Output value will lie in the same horizontal half plane
  local is_up = 0 <= lch.h and lch.h < 180
  local press = is_up and (180 - lch.h) or (lch.h - 180)
  local new_press = H.clip(f(press), 0, 180)
  lch.h = is_up and (180 - new_press) or (new_press + 180)

  return MiniColors.convert(lch, 'hex', { gamut_clip = gamut_clip })
end

H.channel_modifiers.a = function(hex, f, gamut_clip)
  local lab = MiniColors.convert(hex, 'oklab')
  lab.a = f(lab.a)
  return MiniColors.convert(lab, 'hex', { gamut_clip = gamut_clip })
end

H.channel_modifiers.b = function(hex, f, gamut_clip)
  local lab = MiniColors.convert(hex, 'oklab')
  lab.b = f(lab.b)
  return MiniColors.convert(lab, 'hex', { gamut_clip = gamut_clip })
end

H.channel_modifiers.red = function(hex, f, gamut_clip)
  local rgb = H.hex2rgb(hex)
  rgb.r = H.clip(f(rgb.r), 0, 255)
  return MiniColors.convert(rgb, 'hex', { gamut_clip = gamut_clip })
end

H.channel_modifiers.green = function(hex, f, gamut_clip)
  local rgb = H.hex2rgb(hex)
  rgb.g = H.clip(f(rgb.g), 0, 255)
  return MiniColors.convert(rgb, 'hex', { gamut_clip = gamut_clip })
end

H.channel_modifiers.blue = function(hex, f, gamut_clip)
  local rgb = H.hex2rgb(hex)
  rgb.b = H.clip(f(rgb.b), 0, 255)
  return MiniColors.convert(rgb, 'hex', { gamut_clip = gamut_clip })
end

-- Channel invert -------------------------------------------------------------
--stylua: ignore
H.chan_inverters = {
  lightness   = function(x) return 100 - x end,
  -- chroma is the same as saturation
  saturation  = function(x) return 100 - x end,
  hue         = function(x) return 360 - x end,
  temperature = function(x) return 180 - x end,
  pressure    = function(x) return 180 - x end,
  a           = function(x) return -x end,
  b           = function(x) return -x end,
  red         = function(x) return 255-x end,
  green       = function(x) return 255-x end,
  blue        = function(x) return 255-x end,
}

-- Channel repel --------------------------------------------------------------
-- Use tie breakers when target is close to source
H.repel_tie_breakers = {
  lightness = 50,
  chroma = 100,
  saturation = 50,
  hue = 180,
  temperature = 90,
  pressure = 90,
  a = 0,
  b = 0,
  red = 127,
  green = 127,
  blue = 127,
}

H.nudge_repel = function(d, coef)
  -- Repel nudge will be added to distance from point to source.
  -- Ideas behind approach:
  -- - Nudge at `d = 0` should be equal to `coef`.
  -- - Nudge should monotonically decrease to 0 as distance tends to infinity.
  -- - The `d + nudge(d)` (distance after adding nudge) should be still
  --   monotonically increasing as to preserve order of repelled points.
  return coef * math.exp(-d / coef)
end

H.nudge_attract = function(d, coef)
  -- Repel nudge will be added to distance from point to source.
  -- Ideas behind approach:
  -- - Adding nudge when `0 <= d <= coef` should lead to 0. This results into all
  --   points from `coef` neighborhood of source collapse into source.
  -- - Nudge should monotonically decrease to 0 as distance tends to infinity.
  -- - The `d + nudge(d)` (distance after adding nudge) should be still
  --   monotonically increasing as to preserve order of repelled points.
  return d <= coef and -d or (-coef * math.exp(1 - d / coef))
end

H.repel = function(x, sources, coef, tie_breaker)
  if coef == 0 then return x end

  local nudge = coef > 0 and H.nudge_repel or H.nudge_attract
  coef = math.abs(coef)

  -- Use direction **towards** `tie_breaker` if `x` is very close to source
  -- to allow more useful repelling from sources on channel allowed edges.
  -- Example: both `repel(0, { 0 }, 10)` and `repel(100, { 100 }, 10)` should
  -- result into repelling **inside** [0; 100] resulting into 10 and 90.
  local tie_breaker_sign = tie_breaker < x and -1 or 1

  local res = x
  for _, src in ipairs(sources) do
    -- Determine which way to move based on how `x` and source are positioned:
    -- - Towards tie breaker if tie.
    -- - To left if `x` is on left of source (and `coef > 0`).
    -- - To right if `x` is on right of source (and `coef > 0`).
    is_tie = math.abs(x - src) < 1e-4
    dir_sign = is_tie and tie_breaker_sign or (x < src and -1 or 1)

    -- Using regular distance is a proper choice even for "hue" channel because
    -- it allows correct computation of nudge. Its periodic nature is accounted
    -- by prior adjustment of `sources` (adding periodic ones)
    res = res + dir_sign * nudge(H.dist(x, src), coef)
  end
  return res
end

H.add_circle_sources = function(sources)
  local res = {}
  -- Adding two new sources in periodic fashion makes repel more periodic
  for _, src in ipairs(sources) do
    table.insert(res, src)
    table.insert(res, src - 360)
    table.insert(res, src + 360)
  end
  return res
end

-- Color conversion -----------------------------------------------------------
H.converters = {}

H.converters['8-bit'] = function(x, _, _) return H.get_closest_color_id(x, H.compute_term_oklab()) end

H.converters.hex = function(x, from_space, opts)
  if from_space == 'hex' then return x end
  return H.rgb2hex(MiniColors.convert(x, 'rgb', opts))
end

H.converters.rgb = function(x, from_space, opts)
  if from_space == '8-bit' then
    local rgb = H.oklab2rgb(H.compute_term_oklab()[x])
    return vim.tbl_map(H.round, rgb)
  end
  if from_space == 'hex' then return H.hex2rgb(x) end

  if from_space == 'rgb' then return { r = H.clip(x.r, 0, 255), g = H.clip(x.g, 0, 255), b = H.clip(x.b, 0, 255) } end

  -- Clip non-gray color to be in gamut
  local lch = MiniColors.convert(x, 'oklch', opts)
  if lch.h ~= nil then lch = H.clip_to_gamut(lch, opts.gamut_clip) end

  return H.oklab2rgb(H.oklch2oklab(lch))
end

H.converters.oklab = function(x, from_space, opts) return H.oklch2oklab(MiniColors.convert(x, 'oklch', opts)) end

H.converters.oklch = function(x, from_space, opts)
  local res = nil
  if from_space == '8-bit' then res = H.oklab2oklch(H.compute_term_oklab()[x]) end
  if from_space == 'hex' then res = H.oklab2oklch(H.rgb2oklab(H.hex2rgb(x))) end
  if from_space == 'rgb' then res = H.oklab2oklch(H.rgb2oklab(x)) end
  if from_space == 'oklab' then res = H.oklab2oklch(x) end
  if from_space == 'oklch' then res = x end
  if from_space == 'okhsl' then res = H.okhsl2oklch(x) end

  -- Normalize
  res.l = H.clip(res.l, 0, 100)

  -- - Deal with grays separately
  if res.c <= 0 or res.h == nil then
    res.c, res.h = 0, nil
  else
    res.c, res.h = H.clip(res.c, 0, 100), res.h % 360
  end

  return res
end

H.converters.okhsl = function(x, from_space, opts) return H.oklch2okhsl(MiniColors.convert(x, 'oklch', opts)) end

H.infer_color_space = function(x)
  if type(x) == 'number' and 16 <= x and x <= 255 then return '8-bit' end
  if type(x) == 'string' and x:find('^#%x%x%x%x%x%x$') ~= nil then return 'hex' end

  local err_msg = 'Can not infer color space of ' .. vim.inspect(x)
  if type(x) ~= 'table' then H.error(err_msg) end

  local is_num = H.is_number
  if is_num(x.l) then
    if is_num(x.c) then return 'oklch' end
    if is_num(x.a) and is_num(x.b) then return 'oklab' end
    if is_num(x.s) then return 'okhsl' end
  end

  if is_num(x.r) and is_num(x.g) and is_num(x.b) then return 'rgb' end

  H.error(err_msg)
end

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

-- Sources for Oklab/Oklch:
-- https://github.com/bottosson/bottosson.github.io/blob/master/misc/colorpicker/colorconversion.js
-- https://bottosson.github.io/posts/oklab/#converting-from-linear-srgb-to-oklab
--
-- Okhsl is a local variant of Oklch with `s` for "saturation" - percent of
-- chroma relative to maximum possible chroma for this lightness and hue.
--
-- NOTEs:
-- - Coordinates ranges: `l` - [0; 100], `a`/`b` - no range, `c` - [0; 100]
--   (way less in gamut), `s` - [0; 100], `h` - [0; 360).
-- - Lightness is always assumed to be corrected

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

  -- Explicitly convert for nearly achromatic colors
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

-- Oklch <-> Okhsl
H.oklch2okhsl = function(lch)
  if lch.c <= 0 or lch.h == nil then return { l = lch.l, s = 0 } end

  local gamut_points = H.get_gamut_points(lch)
  local percent = 100 * lch.c / gamut_points.c_upper

  return { l = lch.l, s = H.clip(percent, 0, 100), h = lch.h }
end

H.okhsl2oklch = function(lsh)
  if lsh.s <= 0 or lsh.h == nil then return { l = lsh.l, c = 0 } end

  local gamut_points = H.get_gamut_points(lsh)
  local c = 0.01 * lsh.s * gamut_points.c_upper

  return { l = lsh.l, c = H.clip(c, 0, math.huge), h = lsh.h }
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
  if not H.adjust_lightness then return x end

  x = 0.01 * x
  local k1, k2 = 0.206, 0.03
  local k3 = (1 + k1) / (1 + k2)

  local res = 0.5 * (k3 * x - k1 + math.sqrt((k3 * x - k1) ^ 2 + 4 * k2 * k3 * x))
  return 100 * res
end

H.correct_lightness_inv = function(x)
  if not H.adjust_lightness then return x end

  x = 0.01 * x
  local k1, k2 = 0.206, 0.03
  local k3 = (1 + k1) / (1 + k2)
  local res = (x / k3) * (x + k1) / (x + k2)
  return 100 * res
end

-- Get gamut ranges for Lch point. They are computed for its hue leaf as
-- segments of triangle in (c, l) coordinates ((0, 0), (0, 100), cusp).
-- Equations for triangle parts:
-- - Lower segment ((0; 0) to cusp): y * c_cusp = x * L_cusp
-- - Upper segment ((0; 100) to cusp): (100 - y) * c_cusp = x * (100 - L_cusp)
-- NOTEs:
-- - It is **very important** that this triangle is computed for **not
--   corrected** lightness. But it is assumed **corrected lightness** in input.
-- - This approach is not entirely accurate and can results in ranges outside
--   of input `lch` for in-gamut point. Put it should be pretty rare: ~0.5%
--   cases for most saturated colors.
H.get_gamut_points = function(lch)
  local c, l = lch.c, H.clip(lch.l, 0, 100)
  l = H.correct_lightness_inv(l)
  local cusp = H.cusps[math.floor(lch.h % 360)]
  local c_cusp, l_cusp = cusp[1], cusp[2]

  -- Maximum allowed chroma is computed based on current lightness and depends
  -- on whether `l` is below or above cusp's `l`:
  -- - If below, then it is from lower triangle segment.
  -- - If above - from upper segment.
  local c_upper = l <= l_cusp and (c_cusp * l / l_cusp) or (c_cusp * (100 - l) / (100 - l_cusp))
  -- - Don't allow negative chroma (can happen if `l` is out of [0; 100])
  c_upper = H.clip(c_upper, 0, math.huge)

  -- Other points can be computed only in presence of actual chroma
  if c == nil then return { c_upper = c_upper } end

  -- Range of allowed lightness is computed based on current chroma:
  -- - Lower is from segment between (0, 0) and cusp.
  -- - Upper is from segment between (0, 100) and cusp.
  local l_lower, l_upper
  if c < 0 then
    l_lower, l_upper = 0, 100
  elseif c_cusp < c then
    l_lower, l_upper = l_cusp, l_cusp
  else
    local saturation = c / c_cusp
    l_lower = saturation * l_cusp
    l_upper = saturation * (l_cusp - 100) + 100
  end

  -- Intersection of segment between (c, l) and (0, l_cusp) with gamut boundary
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
    l_lower = H.correct_lightness(l_lower),
    l_upper = H.correct_lightness(l_upper),
    c_upper = c_upper,
    l_cusp_clip = H.correct_lightness(l_cusp_clip),
    c_cusp_clip = c_cusp_clip,
  }
end

H.clip_to_gamut = function(lch, gamut_clip)
  -- `lch` should have not corrected lightness
  local res = vim.deepcopy(lch)
  local gamut_points = H.get_gamut_points(lch)

  local is_inside_gamut = lch.c <= gamut_points.c_upper
  if is_inside_gamut then return res end

  -- Clip by going towards (0, l_cusp) until in gamut. This approach proved to
  -- be the best because of reasonable compromise between chroma and lightness.
  -- In particular when inverting lightness of dark color schemes:
  -- - Clipping by reducing chroma with constant lightness leads to a dark
  --   foreground with hardly distinguishable colors.
  -- - Clipping by adjusting lightness with constant chroma leads to very low
  --   contrast on a particularly saturated foreground colors.
  if gamut_clip == 'cusp' then
    res.l, res.c = gamut_points.l_cusp_clip, gamut_points.c_cusp_clip
  end

  -- Preserve lightness by clipping chroma
  if gamut_clip == 'chroma' then res.c = H.clip(res.c, 0, gamut_points.c_upper) end

  -- Preserve chroma by clipping lightness
  if gamut_clip == 'lightness' then res.l = H.clip(res.l, gamut_points.l_lower, gamut_points.l_upper) end

  return res
end

-- Interactive ----------------------------------------------------------------
H.apply_interactive_buffer = function(buf_id, init_cs)
  -- Create temporary color scheme
  _G._interactive_cs = vim.deepcopy(init_cs)

  -- Create initial script lines exposing color scheme and its methods
  local lines = { '-- Source code for interactive buffer', 'local self = _G._interactive_cs' }
  for key, val in pairs(_G._interactive_cs) do
    if vim.is_callable(val) then
      local l = string.format('local %s = function(...) self = self:%s(...) end', key, key)
      table.insert(lines, l)
    end
  end

  -- Add current lines
  lines = vim.list_extend(lines, vim.api.nvim_buf_get_lines(buf_id, 0, -1, true))

  -- Return final result
  table.insert(lines, 'return self')

  -- Source
  local ok, res = pcall(loadstring(table.concat(lines, '\n')))
  _G._interactive_cs = nil

  if not ok then error(res) end
  return res
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.colors) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.set_buf_name = function(buf_id, name) vim.api.nvim_buf_set_name(buf_id, 'minicolors://' .. buf_id .. '/' .. name) end

H.round = function(x)
  if x == nil then return nil end
  return math.floor(x + 0.5)
end

H.clip = function(x, from, to) return math.min(math.max(x, from), to) end

H.cuberoot = function(x) return math.pow(x, 0.333333) end

H.dist = function(x, y) return math.abs(x - y) end

H.dist_circle = function(x, y)
  -- Respect gray colors which don't have hue
  if x == nil and y == nil then return 0 end
  if x == nil or y == nil then return math.huge end

  local d = H.dist(x % 360, y % 360)
  return math.min(d, 360 - d)
end

H.dist_oklab = function(x, y) return math.abs(x.l - y.l) + math.abs(x.a - y.a) + math.abs(x.b - y.b) end

H.convex_continuous = function(x, y, coef)
  if x == nil or y == nil then return H.convex_discrete(x, y, coef) end
  return H.round((1 - coef) * x + coef * y)
end

H.convex_discrete = function(x, y, coef)
  -- Using `vim.deepcopy()` ensures no side effects
  if coef < 0.5 then return vim.deepcopy(x) end
  return vim.deepcopy(y)
end

H.union = function(arr1, arr2)
  local value_is_present = {}
  for _, x in ipairs(arr1) do
    value_is_present[x] = true
  end
  for _, x in ipairs(arr2) do
    value_is_present[x] = true
  end
  return vim.tbl_keys(value_is_present)
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

H.is_number = function(x) return type(x) == 'number' end

H.is_table = function(x) return type(x) == 'table' end

H.is_string = function(x) return type(x) == 'string' end

H.all = function(arr, predicate)
  predicate = predicate or function(x) return x end
  for _, x in pairs(arr) do
    if not predicate(x) then return false end
  end
  return true
end

-- TODO: Remove after compatibility with Neovim=0.9 is dropped
H.islist = vim.fn.has('nvim-0.10') == 1 and vim.islist or vim.tbl_islist

return MiniColors
