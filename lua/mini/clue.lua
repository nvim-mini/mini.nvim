--- *mini.clue* Show next key clues
---
--- MIT License Copyright (c) 2023 Evgeni Chasnovski

--- Features:
--- - Implement custom key query process to reach target key combination:
---     - Starts after customizable opt-in triggers (mode + keys).
---
---     - Each key press narrows down set of possible targets.
---       Pressing `<BS>` removes previous user entry.
---       Pressing `<Esc>` or `<C-c>` leads to an early stop.
---       Doesn't depend on 'timeoutlen' and has basic support for 'langmap'.
---
---     - Ends when there is at most one target left or user pressed `<CR>`.
---       Results into emulating pressing all query keys plus possible postkeys.
---
--- - Show window (after configurable delay) with clues. It lists available
---   next keys along with their descriptions (auto generated from descriptions
---   present keymaps and user-supplied clues; preferring the former).
---
--- - Configurable "postkeys" for key combinations - keys which will be emulated
---   after combination is reached during key query process.
---
--- - Provide customizable sets of clues for common built-in keys/concepts:
---     - `g` key.
---     - `z` key.
---     - Window commands.
---     - Built-in completion.
---     - Marks.
---     - Registers.
---
--- - Lua functions to disable/enable triggers globally or per buffer.
---
--- For more details see:
--- - |MiniClue-key-query-process|.
--- - |MiniClue-examples|.
--- - |MiniClue.config|.
--- - |MiniClue.gen_clues|.
---
--- Notes:
--- - There is no functionality to create mappings while defining clues.
---   This is done to clearly separate these two different actions.
---   The best suggested practice is to manually create mappings with
---   descriptions (`desc` field in options), as they will be automatically
---   used inside clue window.
---
--- - Triggers are implemented as special buffer-local mappings. This leads to
---   several caveats:
---     - They will override same regular buffer-local mappings and have
---       precedence over global one.
---
---       Example: having set `<C-w>` as Normal mode trigger means that
---       there should not be another `<C-w>` mapping.
---
---     - They need to be the latest created buffer-local mappings or they will
---       not function properly. Most common indicator of this is that some
---       mapping starts to work only after clue window is shown.
---
---       Example: `g` is set as Normal mode trigger, but `gcc` from |mini.comment|
---       doesn't work right away. This is probably because there are some
---       other buffer-local mappings starting with `g` which were created after
---       mapping for `g` trigger. Most common places for this are in LSP server's
---       `on_attach` or during tree-sitter start in buffer.
---
---       To check if trigger is the most recent buffer-local mapping, execute
---       `:<mode-char>map <trigger-keys>` (like `:nmap g` for previous example).
---       Mapping for trigger should be the first listed.
---
---       This module makes the best effort to work out of the box and cover
---       most common cases, but it is not foolproof. The solution here is to
---       ensure that triggers are created after making all buffer-local mappings:
---       run either |MiniClue.setup()| or |MiniClue.ensure_buf_triggers()|.
---
--- - Descriptions from existing mappings take precedence over user-supplied
---   clues. This is to ensure that information shown in clue window is as
---   relevant as possible. To add/customize description of an already existing
---   mapping, use |MiniClue.set_mapping_desc()|.
---
--- - Due to technical difficulties, there is no foolproof support for
---   Operator-pending mode triggers (like `a`/`i` from |mini.ai|):
---     - Doesn't work as part of a command in "temporary Normal mode" (like
---       after |i_CTRL-O|) due to implementation difficulties.
---     - Can have unexpected behavior with custom operators.
---
--- - Has (mostly solved) issues with macros:
---     - All triggers are disabled during macro recording due to technical
---       reasons.
---     - The `@` and `Q` keys are specially mapped inside |MiniClue.setup()|
---       (if the key is not already mapped) to temporarily disable triggers.
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.clue').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `MiniClue`
--- which you can use for scripting or manually (with `:lua MiniClue.*`).
---
--- Config table **needs to have triggers configured**, none is set up by default.
---
--- See |MiniClue.config| for available config settings.
---
--- You can override runtime config settings (like clues or window options)
--- locally to a buffer inside `vim.b.miniclue_config` which should have same
--- structure as `MiniClue.config`. See |mini.nvim-buffer-local-config| for
--- more details.
---
--- # Comparisons ~
---
--- - [folke/which-key.nvim](https://github.com/folke/which-key.nvim):
---     - Both have the same main goal: show available next keys along with
---       their customizable descriptions.
---     - Has different UI and content layout.
---     - Allows creating mappings inside its configuration, while this module
---       doesn't have this by design (to clearly separate two different tasks).
---     - Doesn't allow creating submodes, while this module does (via `postkeys`).
---
--- - [anuvyklack/hydra.nvim](https://github.com/anuvyklack/hydra.nvim):
---     - Both allow creating submodes: state which starts at certain key
---       combination; treats some keys differently; ends after `<Esc>`.
---     - Doesn't show information about available next keys (outside of
---       submodes), while that is this module's main goal.
---
--- # Highlight groups ~
---
--- - `MiniClueBorder` - window border.
--- - `MiniClueDescGroup` - group description in clue window.
--- - `MiniClueDescSingle` - single target description in clue window.
--- - `MiniClueNextKey` - next key label in clue window.
--- - `MiniClueNextKeyWithPostkeys` - next key label with postkeys in clue window.
--- - `MiniClueSeparator` - separator in clue window.
--- - `MiniClueTitle` - window title.
---
--- To change any highlight group, set it directly with |nvim_set_hl()|.
---
--- # Disabling ~
---
--- To disable creating triggers, set `vim.g.miniclue_disable` (globally) or
--- `vim.b.miniclue_disable` (for a buffer) to `true`. Considering high number
--- of different scenarios and customization intentions, writing exact rules
--- for disabling module's functionality is left to user. See
--- |mini.nvim-disabling-recipes| for common recipes.
---@tag MiniClue

--- # General info ~
---
--- This module implements custom key query process imitating a usual built-in
--- mechanism of user pressing keys in order to execute a mapping. General idea
--- is the same: narrow down key combinations until the target is reached.
---
--- Main goals of its existence are:
---
--- - Allow reaching certain mappings be independent of 'timeoutlen'. That is,
---   there is no fixed timeout after which currently typed keys are executed.
---
--- - Enable automated showing of next key clues after user-supplied delay
---   (also independent of 'timeoutlen').
---
--- - Allow emulating configurable key presses after certain key combination is
---   reached. This granular control allows creating so called "submodes".
---   See more at |MiniClue-examples-submodes|.
---
--- This process is primarily designed for nested `<Leader>` mappings in Normal
--- mode but works in all other main modes: Visual, Insert, Operator-pending
--- (with caveats; no foolproof guarantees), Command-line, Terminal.
---
--- # Lifecycle ~
---
--- - Key query process starts when user types a trigger: certain keys in certain
---   mode. Those keys are put into key query as a single user input. All possible
---   mode key combinations are filtered to ones starting with the trigger keys.
---
---   Note: trigger is implemented as a regular mapping, so if it has at least
---   two keys, they should be pressed within 'timeoutlen' milliseconds.
---
--- - Wait (indefinitely) for user to press a key. Advance depending on the key:
---
---     - Special key:
---
---         - If `<Esc>` or `<C-c>`, stop the process without any action.
---
---         - If `<CR>`, stop the process and execute current key query, meaning
---           emulate (with |nvim_feedkeys()|) user pressing those keys.
---
---         - If `<BS>`, remove previous user input from the query. If query becomes
---           empty, stop the process without any action.
---
---         - If a key for scrolling clue window (`scroll_down` / `scroll_up`
---           in `config.window`; `<C-d>` / `<C-u>` by default), scroll clue window
---           and wait for the next user key.
---           Note: if clue window is not shown, treated as a not special key.
---
---     - Not special key. Add key to the query while filtering all available
---       key combinations to start with the current key query. Advance:
---
---         - If there is a single available key combination matching current
---           key query, execute it.
---
---         - If there is no key combinations starting with the current query,
---           execute it. This, for instance, allows a seamless execution of
---           operators in presence of a longer key combinations. Example: with
---           `g` as trigger in Normal mode and available mappings `gc` / `gcc`
---           (like from |mini.comment|), this allows typing `gcip` to comment
---           current paragraph, although there are no key combinations
---           starting with `gci`.
---
---         - Otherwise wait for the new user key press.
---
--- # Clue window ~
---
--- After initiating key query process and after each key press, a timer is
--- started to show a clue window: floating window with information about
--- available next keys along with their descriptions. Note: if window is
--- already shown, its content is updated right away.
---
--- Clues can have these types:
---
--- - "Terminal next key": when pressed, will lead to query execution.
---
--- - "Terminal next key with postkeys": when pressed, will lead to query
---   execution plus some configured postkeys.
---
--- - "Group next key": when pressed, will narrow down available key combinations
---   and wait for another key press. Note: can have configured description
---   (inside `config.clues`) or it will be auto generated based on the number of
---   available key combinations.
---@tag MiniClue-key-query-process

--- # Full starter example ~
---
--- If not sure where to start, try this example with all provided clues from
--- this module plus all |<Leader>| mappings in Normal and Visual modes: >lua
---
---   local miniclue = require('mini.clue')
---   miniclue.setup({
---     triggers = {
---       -- Leader triggers
---       { mode = 'n', keys = '<Leader>' },
---       { mode = 'x', keys = '<Leader>' },
---
---       -- `[` and `]` keys
---       { mode = 'n', keys = '[' },
---       { mode = 'n', keys = ']' },
---
---       -- Built-in completion
---       { mode = 'i', keys = '<C-x>' },
---
---       -- `g` key
---       { mode = 'n', keys = 'g' },
---       { mode = 'x', keys = 'g' },
---
---       -- Marks
---       { mode = 'n', keys = "'" },
---       { mode = 'n', keys = '`' },
---       { mode = 'x', keys = "'" },
---       { mode = 'x', keys = '`' },
---
---       -- Registers
---       { mode = 'n', keys = '"' },
---       { mode = 'x', keys = '"' },
---       { mode = 'i', keys = '<C-r>' },
---       { mode = 'c', keys = '<C-r>' },
---
---       -- Window commands
---       { mode = 'n', keys = '<C-w>' },
---
---       -- `z` key
---       { mode = 'n', keys = 'z' },
---       { mode = 'x', keys = 'z' },
---     },
---
---     clues = {
---       -- Enhance this by adding descriptions for <Leader> mapping groups
---       miniclue.gen_clues.square_brackets(),
---       miniclue.gen_clues.builtin_completion(),
---       miniclue.gen_clues.g(),
---       miniclue.gen_clues.marks(),
---       miniclue.gen_clues.registers(),
---       miniclue.gen_clues.windows(),
---       miniclue.gen_clues.z(),
---     },
---   })
--- <
--- # Leader clues ~
---
--- Assume there are these |<Leader>| mappings set up: >lua
---
---   -- Set `<Leader>` before making any mappings and configuring 'mini.clue'
---   vim.g.mapleader = ' '
---
---   local nmap_leader = function(suffix, rhs, desc)
---     vim.keymap.set('n', '<Leader>' .. suffix, rhs, { desc = desc })
---   end
---   local xmap_leader = function(suffix, rhs, desc)
---     vim.keymap.set('x', '<Leader>' .. suffix, rhs, { desc = desc })
---   end
---
---   nmap_leader('bd', '<Cmd>lua MiniBufremove.delete()<CR>',  'Delete')
---   nmap_leader('bw', '<Cmd>lua MiniBufremove.wipeout()<CR>', 'Wipeout')
---
---   nmap_leader('lf', '<Cmd>lua vim.lsp.buf.format()<CR>',     'Format')
---   xmap_leader('lf', '<Cmd>lua vim.lsp.buf.format()<CR>',     'Format')
---   nmap_leader('lr', '<Cmd>lua vim.lsp.buf.rename()<CR>',     'Rename')
---   nmap_leader('lR', '<Cmd>lua vim.lsp.buf.references()<CR>', 'References')
--- <
--- The following setup will enable |<Leader>| as trigger in Normal and Visual
--- modes and add descriptions to mapping groups: >lua
---
---   require('mini.clue').setup({
---     -- Register `<Leader>` as trigger
---     triggers = {
---       { mode = 'n', keys = '<Leader>' },
---       { mode = 'x', keys = '<Leader>' },
---     },
---
---     -- Add descriptions for mapping groups
---     clues = {
---       { mode = 'n', keys = '<Leader>b', desc = '+Buffers' },
---       { mode = 'n', keys = '<Leader>l', desc = '+LSP' },
---     },
---   })
--- <
--- # Clues without mappings ~
---
--- Clues can be shown not only for actually present mappings. This is helpful for
--- showing clues for built-in key combinations. Here is an example of clues for
--- a subset of built-in completion (see |MiniClue.gen_clues.builtin_completion()|
--- to generate clues for all available completion sources): >lua
---
---   require('mini.clue').setup({
---     -- Make `<C-x>` a trigger. Otherwise, key query process won't start.
---     triggers = {
---       { mode = 'i', keys = '<C-x>' },
---     },
---
---     -- Register custom clues
---     clues = {
---       { mode = 'i', keys = '<C-x><C-f>', desc = 'File names' },
---       { mode = 'i', keys = '<C-x><C-l>', desc = 'Whole lines' },
---       { mode = 'i', keys = '<C-x><C-o>', desc = 'Omni completion' },
---       { mode = 'i', keys = '<C-x><C-s>', desc = 'Spelling suggestions' },
---       { mode = 'i', keys = '<C-x><C-u>', desc = "With 'completefunc'" },
---     }
---   })
--- <
--- # Triggers in special buffers ~
---
--- By default triggers are automatically created in listed ('buflisted') and some
--- special non-listed buffers. Use |MiniClue.ensure_buf_triggers()| to manually
--- enable in when you need them. For example: >vim
---
---   au FileType special_ft lua MiniClue.ensure_buf_triggers()
--- <
--- # Submodes ~
--- *MiniClue-examples-submodes*
---
--- Submode is a state initiated after pressing certain key combination ("prefix")
--- during which some keys are interpreted differently.
---
--- In this module submode can be implemented following these steps:
---
--- - Create mappings for each key inside submode. Left hand side of mappings
---   should consist from prefix followed by the key.
---
--- - Create clue for each key inside submode with `postkeys` value equal to
---   prefix. It would mean that after executing particular key combination from
---   this submode, pressing its prefix will be automatically emulated (leading
---   back to being inside submode).
---
--- - Register submode prefix (or some of its starting part) as trigger. Do not
---   register "overlapping" triggers, like `<Leader>` and `<Leader>m`.
---
--- ## Submode examples ~
---
--- - Submode for moving with |mini.move|:
---     - Press `<Leader>m` to start submode.
---     - Press any of `h`/`j`/`k`/`l` to move selection/line.
---     - Press `<Esc>` to stop submode.
---
---   The code: >lua
---
---   require('mini.move').setup({
---     mappings = {
---       left       = '<Leader>mh',
---       right      = '<Leader>ml',
---       down       = '<Leader>mj',
---       up         = '<Leader>mk',
---       line_left  = '<Leader>mh',
---       line_right = '<Leader>ml',
---       line_down  = '<Leader>mj',
---       line_up    = '<Leader>mk',
---     },
---   })
---
---   require('mini.clue').setup({
---     triggers = {
---       -- This can also set up directly `<Leader>m` as a trigger, but make
---       -- sure to not also use `<Leader>`, as they would "overlap"
---       { mode = 'n', keys = '<Leader>' },
---       { mode = 'x', keys = '<Leader>' },
---     },
---     clues = {
---       { mode = 'n', keys = '<Leader>m', desc = '+Move' },
---
---       { mode = 'n', keys = '<Leader>mh', postkeys = '<Leader>m' },
---       { mode = 'n', keys = '<Leader>mj', postkeys = '<Leader>m' },
---       { mode = 'n', keys = '<Leader>mk', postkeys = '<Leader>m' },
---       { mode = 'n', keys = '<Leader>ml', postkeys = '<Leader>m' },
---       { mode = 'x', keys = '<Leader>mh', postkeys = '<Leader>m' },
---       { mode = 'x', keys = '<Leader>mj', postkeys = '<Leader>m' },
---       { mode = 'x', keys = '<Leader>mk', postkeys = '<Leader>m' },
---       { mode = 'x', keys = '<Leader>ml', postkeys = '<Leader>m' },
---     },
---   })
--- <
--- - Submode for iterating buffers and windows with |mini.bracketed|:
---     - Press `[` or `]` to start key query process for certain direction.
---     - Press `b` / `w` to iterate buffers/windows until reach target one.
---     - Press `<Esc>` to stop submode.
---
---   The code: >lua
---
---   require('mini.bracketed').setup()
---
---   require('mini.clue').setup({
---     triggers = {
---       { mode = 'n', keys = ']' },
---       { mode = 'n', keys = '[' },
---     },
---     clues = {
---       { mode = 'n', keys = ']b', postkeys = ']' },
---       { mode = 'n', keys = ']w', postkeys = ']' },
---
---       { mode = 'n', keys = '[b', postkeys = '[' },
---       { mode = 'n', keys = '[w', postkeys = '[' },
---     },
---   })
--- <
--- - Submode for window commands using |MiniClue.gen_clues.windows()|:
---     - Press `<C-w>` to start key query process.
---     - Press keys which move / change focus / resize windows.
---     - Press `<Esc>` to stop submode.
---
---   The code: >lua
---
---   local miniclue = require('mini.clue')
---   miniclue.setup({
---     triggers = {
---       { mode = 'n', keys = '<C-w>' },
---     },
---     clues = {
---       miniclue.gen_clues.windows({
---         submode_move = true,
---         submode_navigate = true,
---         submode_resize = true,
---       })
---     },
---   })
--- <
--- # Window config ~
--- >lua
---   require('mini.clue').setup({
---     triggers = { { mode = 'n', keys = '<Leader>' } },
---
---     window = {
---       -- Show window immediately
---       delay = 0,
---
---       config = {
---         -- Compute window width automatically
---         width = 'auto',
---
---         -- Use double-line border
---         border = 'double',
---       },
---     },
---   })
--- <
---@tag MiniClue-examples

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local
---@diagnostic disable:cast-local-type

-- Module definition ==========================================================
local MiniClue = {}
local H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniClue.config|.
---
---@usage >lua
---   require('mini.clue').setup({}) -- replace {} with your config table
---                                  -- needs `triggers` field present
--- <
MiniClue.setup = function(config)
  -- Export module
  _G.MiniClue = MiniClue

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Define behavior
  H.create_autocommands()

  -- Create default highlighting
  H.create_default_hl()
end

--stylua: ignore
--- Defaults ~
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text # General info ~
---
--- - To use |<Leader>| as part of the config (either as trigger or inside clues),
---   set it prior to running |MiniClue.setup()|.
---
--- - See |MiniClue-examples| for examples.
---
--- # Clues ~
---
--- `config.clues` is an array with extra information about key combinations.
--- Each element can be one of:
--- - Clue table.
--- - Array (possibly nested) of clue tables.
--- - Callable (function) returning either of the previous two.
---
--- A clue table is a table with the following fields:
--- - <mode> `(string)` - single character describing **single** mode short-name of
---   key combination as in `nvim_set_keymap()` ('n', 'x', 'i', 'o', 'c', etc.).
--- - <keys> `(string)` - key combination for which clue will be shown.
---   "Human-readable" key names as in |key-notation| (like "<Leader>", "<Space>",
---   "<Tab>", etc.) are allowed.
--- - <desc> `(string|function|nil)` - optional key combination description which is
---   shown in clue window. If function, should return string description.
--- - <postkeys> `(string|nil)` - optional postkeys which will be executed
---   automatically after `keys`. Allows creation of submodes
---   (see |MiniClue-examples-submodes|).
---
--- Notes:
--- - Postkeys are literal simulation of keypresses with |nvim_feedkeys()|.
---
--- - Suggested approach to configuring clues is to create mappings with `desc`
---   field while supplying to `config.clues` only elements describing groups,
---   postkeys, and built-in mappings.
---
--- # Triggers ~
---
--- `config.triggers` is an array with information when |MiniClue-key-query-process|
--- should start. Each element is a trigger table with the fields <mode> and
--- <keys> which are treated the same as in clue table.
---
--- # Window ~
---
--- `config.window` defines behavior of clue window.
---
--- `config.window.delay` is a number of milliseconds after which clue window will
--- appear. Can be 0 to show immediately.
---
--- `config.window.config` is a table defining floating window characteristics
--- or a callable returning such table (will be called with identifier of
--- window's buffer already showing all clues). It should have the same
--- structure as in |nvim_open_win()| with the following enhancements:
--- - <width> field can be equal to `"auto"` leading to window width being
---   computed automatically based on its content. Default is fixed width of 30.
--- - <row> and <col> can be equal to `"auto"` in which case they will be
---   computed to "stick" to set anchor ("SE" by default; see |nvim_open_win()|).
---   This allows changing corner in which window is shown: >lua
---
---   -- Pick one anchor
---   local anchor = 'NW' -- top-left
---   local anchor = 'NE' -- top-right
---   local anchor = 'SW' -- bottom-left
---   local anchor = 'SE' -- bottom-right
---
---   require('mini.clue').setup({
---     window = {
---       config = { anchor = anchor, row = 'auto', col = 'auto' },
---     },
---   })
--- <
--- `config.window.scroll_down` / `config.window.scroll_up` are strings defining
--- keys which will scroll clue window down / up which is useful in case not
--- all clues fit in current window height. Set to empty string `''` to disable
--- either of them.
MiniClue.config = {
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
--minidoc_afterlines_end

--- Enable triggers in all listed and some special buffers
MiniClue.enable_all_triggers = function()
  for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
    -- Map only inside valid listed buffers and ones with special filetypes
    local is_special = H.ft_to_enable[vim.bo[buf_id].filetype]
    if vim.fn.buflisted(buf_id) == 1 or is_special then H.map_buf_triggers(buf_id) end
  end
end

--- Enable triggers in buffer
---
---@param buf_id number|nil Buffer identifier. Default: current buffer.
MiniClue.enable_buf_triggers = function(buf_id)
  buf_id = (buf_id == nil or buf_id == 0) and vim.api.nvim_get_current_buf() or buf_id
  if not H.is_valid_buf(buf_id) then H.error('`buf_id` should be a valid buffer identifier.') end
  H.map_buf_triggers(buf_id)
end

--- Disable triggers in all buffers
MiniClue.disable_all_triggers = function()
  for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
    H.unmap_buf_triggers(buf_id)
  end
end

--- Disable triggers in buffer
---
---@param buf_id number|nil Buffer identifier. Default: current buffer.
MiniClue.disable_buf_triggers = function(buf_id)
  buf_id = (buf_id == nil or buf_id == 0) and vim.api.nvim_get_current_buf() or buf_id
  if not H.is_valid_buf(buf_id) then H.error('`buf_id` should be a valid buffer identifier.') end
  H.unmap_buf_triggers(buf_id)
end

--- Ensure all triggers are valid
MiniClue.ensure_all_triggers = function()
  MiniClue.disable_all_triggers()
  MiniClue.enable_all_triggers()
end

--- Ensure buffer triggers are valid
---
---@param buf_id number|nil Buffer identifier. Default: current buffer.
MiniClue.ensure_buf_triggers = function(buf_id)
  MiniClue.disable_buf_triggers(buf_id)
  MiniClue.enable_buf_triggers(buf_id)
end

--- Update description of an existing mapping
---
--- Notes:
--- - Uses buffer-local mapping in case there are both global and buffer-local
---   mappings with same mode and LHS. Similar to |maparg()|.
---
---@param mode string Mapping mode (as in `maparg()`).
---@param lhs string Mapping left hand side (as `name` in `maparg()`).
---@param desc string New description to set.
MiniClue.set_mapping_desc = function(mode, lhs, desc)
  if type(mode) ~= 'string' then H.error('`mode` should be string.') end
  if type(lhs) ~= 'string' then H.error('`lhs` should be string.') end
  if type(desc) ~= 'string' then H.error('`desc` should be string.') end

  local ok_get, map_data = pcall(vim.fn.maparg, lhs, mode, false, true)
  if not ok_get or vim.tbl_count(map_data) == 0 then
    local msg = string.format('No mapping found for mode %s and LHS %s.', vim.inspect(mode), vim.inspect(lhs))
    H.error(msg)
  end

  map_data.desc = desc
  local ok_set = pcall(vim.fn.mapset, mode, false, map_data)
  if not ok_set then H.error(vim.inspect(desc) .. ' is not a valid description.') end
end

--- Generate pre-configured clues
---
--- This is a table with function elements. Call to actually get array of clues.
MiniClue.gen_clues = {}

--- Generate clues for built-in completion
---
--- Contains clues for the following triggers: >lua
---
---   { mode = 'i', keys = '<C-x>' }
--- <
---@return table Array of clues.
MiniClue.gen_clues.builtin_completion = function()
  --stylua: ignore
  return {
    { mode = 'i', keys = '<C-x><C-d>', desc = 'Defined identifiers' },
    { mode = 'i', keys = '<C-x><C-e>', desc = 'Scroll up' },
    { mode = 'i', keys = '<C-x><C-f>', desc = 'File names' },
    { mode = 'i', keys = '<C-x><C-i>', desc = 'Identifiers' },
    { mode = 'i', keys = '<C-x><C-k>', desc = 'Identifiers from dictionary' },
    { mode = 'i', keys = '<C-x><C-l>', desc = 'Whole lines' },
    { mode = 'i', keys = '<C-x><C-n>', desc = 'Next completion' },
    { mode = 'i', keys = '<C-x><C-o>', desc = 'Omni completion' },
    { mode = 'i', keys = '<C-x><C-p>', desc = 'Previous completion' },
    { mode = 'i', keys = '<C-x><C-s>', desc = 'Spelling suggestions' },
    { mode = 'i', keys = '<C-x><C-t>', desc = 'Identifiers from thesaurus' },
    { mode = 'i', keys = '<C-x><C-y>', desc = 'Scroll down' },
    { mode = 'i', keys = '<C-x><C-u>', desc = "With 'completefunc'" },
    { mode = 'i', keys = '<C-x><C-v>', desc = 'Like in command line' },
    { mode = 'i', keys = '<C-x><C-z>', desc = 'Stop completion' },
    { mode = 'i', keys = '<C-x><C-]>', desc = 'Tags' },
    { mode = 'i', keys = '<C-x>s',     desc = 'Spelling suggestions' },
  }
end

--- Generate clues for `g` key
---
--- Contains clues for the following triggers: >lua
---
---   { mode = 'n', keys = 'g' }
---   { mode = 'x', keys = 'g' }
--- <
---@return table Array of clues.
MiniClue.gen_clues.g = function()
  local gr_clue = vim.fn.has('nvim-0.11') == 1 and { mode = 'n', keys = 'gr', desc = '+LSP' }
    or { mode = 'n', keys = 'gr', desc = 'Virtual replace with character' }
  local gr_clue_viz = vim.fn.has('nvim-0.11') == 1 and { mode = 'x', keys = 'gr', desc = '+LSP' } or {}

  --stylua: ignore
  return {
    { mode = 'n', keys = 'g0',     desc = 'Go to leftmost visible column' },
    { mode = 'n', keys = 'g8',     desc = 'Print hex value of char under cursor' },
    { mode = 'n', keys = 'ga',     desc = 'Print ascii value' },
    { mode = 'n', keys = 'gD',     desc = 'Go to definition in file' },
    { mode = 'n', keys = 'gd',     desc = 'Go to definition in function' },
    { mode = 'n', keys = 'gE',     desc = 'Go backwards to end of previous WORD' },
    { mode = 'n', keys = 'ge',     desc = 'Go backwards to end of previous word' },
    { mode = 'n', keys = 'gF',     desc = 'Edit file under cursor + jump line' },
    { mode = 'n', keys = 'gf',     desc = 'Edit file under cursor' },
    { mode = 'n', keys = 'gg',     desc = 'Go to line (def: first)' },
    { mode = 'n', keys = 'gH',     desc = 'Start Select line mode' },
    { mode = 'n', keys = 'gh',     desc = 'Start Select mode' },
    { mode = 'n', keys = 'gI',     desc = 'Start Insert at column 1' },
    { mode = 'n', keys = 'gi',     desc = 'Start Insert where it stopped' },
    { mode = 'n', keys = 'gJ',     desc = 'Join lines without extra spaces' },
    { mode = 'n', keys = 'gj',     desc = 'Go down by screen lines' },
    { mode = 'n', keys = 'gk',     desc = 'Go up by screen lines' },
    { mode = 'n', keys = 'gM',     desc = 'Go to middle of text line' },
    { mode = 'n', keys = 'gm',     desc = 'Go to middle of screen line' },
    { mode = 'n', keys = 'gN',     desc = 'Select previous search match' },
    { mode = 'n', keys = 'gn',     desc = 'Select next search match' },
    { mode = 'n', keys = 'go',     desc = 'Go to byte' },
    { mode = 'n', keys = 'gP',     desc = 'Put text before cursor + stay after it' },
    { mode = 'n', keys = 'gp',     desc = 'Put text after cursor + stay after it' },
    { mode = 'n', keys = 'gQ',     desc = 'Switch to "Ex" mode' },
    { mode = 'n', keys = 'gq',     desc = 'Format text (operator)' },
    { mode = 'n', keys = 'gR',     desc = 'Enter Virtual Replace mode' },
    gr_clue,
    { mode = 'n', keys = 'gs',     desc = 'Sleep' },
    { mode = 'n', keys = 'gT',     desc = 'Go to previous tabpage' },
    { mode = 'n', keys = 'gt',     desc = 'Go to next tabpage' },
    { mode = 'n', keys = 'gU',     desc = 'Make uppercase (operator)' },
    { mode = 'n', keys = 'gu',     desc = 'Make lowercase (operator)' },
    { mode = 'n', keys = 'gV',     desc = 'Avoid reselect' },
    { mode = 'n', keys = 'gv',     desc = 'Reselect previous Visual area' },
    { mode = 'n', keys = 'gw',     desc = 'Format text + keep cursor (operator)' },
    { mode = 'n', keys = 'gx',     desc = 'Execute app for file under cursor' },
    { mode = 'n', keys = 'g<C-]>', desc = '`:tjump` to tag under cursor' },
    { mode = 'n', keys = 'g<C-a>', desc = 'Dump a memory profile' },
    { mode = 'n', keys = 'g<C-g>', desc = 'Show information about cursor' },
    { mode = 'n', keys = 'g<C-h>', desc = 'Start Select block mode' },
    { mode = 'n', keys = 'g<Tab>', desc = 'Go to last accessed tabpage' },
    { mode = 'n', keys = "g'",     desc = "Jump to mark (don't affect jumplist)" },
    { mode = 'n', keys = 'g#',     desc = 'Search backwards word under cursor' },
    { mode = 'n', keys = 'g$',     desc = 'Go to rightmost visible column' },
    { mode = 'n', keys = 'g%',     desc = 'Cycle through matching groups' },
    { mode = 'n', keys = 'g&',     desc = 'Repeat last `:s` on all lines' },
    { mode = 'n', keys = 'g*',     desc = 'Search word under cursor' },
    { mode = 'n', keys = 'g+',     desc = 'Go to newer text state' },
    { mode = 'n', keys = 'g,',     desc = 'Go to newer position in change list' },
    { mode = 'n', keys = 'g-',     desc = 'Go to older text state' },
    { mode = 'n', keys = 'g;',     desc = 'Go to older position in change list' },
    { mode = 'n', keys = 'g<',     desc = 'Display previous command output' },
    { mode = 'n', keys = 'g?',     desc = 'Rot13 encode (operator)' },
    { mode = 'n', keys = 'g@',     desc = "Call 'operatorfunc' (operator)" },
    { mode = 'n', keys = 'g]',     desc = '`:tselect` tag under cursor' },
    { mode = 'n', keys = 'g^',     desc = 'Go to leftmost visible non-whitespace' },
    { mode = 'n', keys = 'g_',     desc = 'Go to lower line' },
    { mode = 'n', keys = 'g`',     desc = "Jump to mark (don't affect jumplist)" },
    { mode = 'n', keys = 'g~',     desc = 'Swap case (operator)' },

    { mode = 'x', keys = 'gf',     desc = 'Edit selected file' },
    { mode = 'x', keys = 'gJ',     desc = 'Join selected lines without extra spaces' },
    { mode = 'x', keys = 'gq',     desc = 'Format selection' },
    gr_clue_viz,
    { mode = 'x', keys = 'gV',     desc = 'Avoid reselect' },
    { mode = 'x', keys = 'gw',     desc = 'Format selection + keep cursor' },
    { mode = 'x', keys = 'g<C-]>', desc = '`:tjump` to selected tag' },
    { mode = 'x', keys = 'g<C-a>', desc = 'Increment with compound' },
    { mode = 'x', keys = 'g<C-g>', desc = 'Show information about selection' },
    { mode = 'x', keys = 'g<C-x>', desc = 'Decrement with compound' },
    { mode = 'x', keys = 'g]',     desc = '`:tselect` selected tag' },
    { mode = 'x', keys = 'g?',     desc = 'Rot13 encode selection' },
  }
end

--- Generate clues for `[` and `]` keys
---
--- Contains clues for the following triggers: >lua
---
---   { mode = 'n', keys = '[' }
---   { mode = 'n', keys = ']' }
--- <
---@return table Array of clues.
MiniClue.gen_clues.square_brackets = function()
  --stylua: ignore
  return {
    { mode = 'n', keys = '[<C-D>', desc = 'Go to first macro def with cursor word', },
    { mode = 'n', keys = '[<C-I>', desc = 'Go to first match with cursor word', },
    { mode = 'n', keys = '[%', desc = 'Go to previous unmatched group' },
    { mode = 'n', keys = '[#', desc = 'Go to previous unmatched #if/#else/#ifdef' },
    { mode = 'n', keys = "['", desc = 'Go to previous mark, first non-blank' },
    { mode = 'n', keys = '[`', desc = 'Go to previous mark' },
    { mode = 'n', keys = '[(', desc = "Go to previous unmatched '('" },
    { mode = 'n', keys = '[/', desc = 'Go to previous C comment start' },
    { mode = 'n', keys = '[*', desc = 'Go to previous C comment start' },
    { mode = 'n', keys = '[I', desc = 'Show lines with cursor word', },
    { mode = 'n', keys = '[D', desc = 'Show macro defs with cursor word' },
    { mode = 'n', keys = '[p', desc = 'Paste with current indent' },
    { mode = 'n', keys = '[P', desc = 'Paste with current indent' },
    { mode = 'n', keys = '[[', desc = 'Go to previous section' },
    { mode = 'n', keys = '[]', desc = 'Go to previous SECTION' },
    { mode = 'n', keys = '[c', desc = 'Go to previous change' },
    { mode = 'n', keys = '[d', desc = 'Show first macro def with cursor word' },
    { mode = 'n', keys = '[f', desc = 'Edit file under cursor' },
    { mode = 'n', keys = '[i', desc = 'Show first line with cursor word', },
    { mode = 'n', keys = '[m', desc = 'Go to previous method start' },
    { mode = 'n', keys = '[M', desc = 'Go to previous method end' },
    { mode = 'n', keys = '[s', desc = 'Go to previous misspelled word' },
    { mode = 'n', keys = '[z', desc = 'Go to current open fold start' },
    { mode = 'n', keys = '[{', desc = "Go to previous unmatched '{'" },
    { mode = 'n', keys = ']<C-D>', desc = 'Go to next macro def with cursor word', },
    { mode = 'n', keys = ']<C-I>', desc = 'Go to next match with cursor word', },
    { mode = 'n', keys = ']%', desc = 'Go to next unmatched group' },
    { mode = 'n', keys = ']#', desc = 'Go to next unmatched #if/#else/#ifdef' },
    { mode = 'n', keys = "]'", desc = "Go to next mark, first non-blank" },
    { mode = 'n', keys = ']`', desc = 'Go to next mark' },
    { mode = 'n', keys = '])', desc = "Go to next unmatched ')'" },
    { mode = 'n', keys = ']/', desc = 'Go to next C comment end' },
    { mode = 'n', keys = ']*', desc = 'Go to next C comment end' },
    { mode = 'n', keys = ']D', desc = 'Show below macro defs with cursor word' },
    { mode = 'n', keys = ']I', desc = 'Show below lines with cursor word', },
    { mode = 'n', keys = ']P', desc = 'Paste with current indent' },
    { mode = 'n', keys = '][', desc = 'Go to next SECTION' },
    { mode = 'n', keys = ']]', desc = 'Go to next section' },
    { mode = 'n', keys = ']c', desc = 'Go to next change' },
    { mode = 'n', keys = ']d', desc = 'Show next macro def with cursor word' },
    { mode = 'n', keys = ']f', desc = 'Edit file under cursor' },
    { mode = 'n', keys = ']i', desc = 'Show next line with cursor word', },
    { mode = 'n', keys = ']m', desc = 'Go to next method start' },
    { mode = 'n', keys = ']M', desc = 'Go to next method end' },
    { mode = 'n', keys = ']p', desc = 'Paste with current indent' },
    { mode = 'n', keys = ']s', desc = 'Go to next misspelled word' },
    { mode = 'n', keys = ']z', desc = 'Go to current open fold end' },
    { mode = 'n', keys = ']}', desc = "Go to next unmatched '}'" },
  }
end

--- Generate clues for marks
---
--- Contains clues for the following triggers: >lua
---
---   { mode = 'n', keys = "'" }
---   { mode = 'n', keys = "g'" }
---   { mode = 'n', keys = '`' }
---   { mode = 'n', keys = 'g`' }
---   { mode = 'x', keys = "'" }
---   { mode = 'x', keys = "g'" }
---   { mode = 'x', keys = '`' }
---   { mode = 'x', keys = 'g`' }
--- <
--- Note: if you use "g" as trigger (like to enable |MiniClue.gen_clues.g()|),
--- don't add "g'" and "g`" as triggers: they already will be taken into account.
---
---@return table Array of clues.
---
---@seealso |mark-motions|
MiniClue.gen_clues.marks = function()
  local describe_marks = function(mode, prefix)
    local make_clue = function(register, desc) return { mode = mode, keys = prefix .. register, desc = desc } end

    return {
      make_clue('^', 'Latest insert position'),
      make_clue('.', 'Latest change'),
      make_clue('"', 'Latest exited position'),
      make_clue("'", 'Line before jump'),
      make_clue('`', 'Position before jump'),
      make_clue('[', 'Start of latest changed or yanked text'),
      make_clue(']', 'End of latest changed or yanked text'),
      make_clue('(', 'Start of sentence'),
      make_clue(')', 'End of sentence'),
      make_clue('{', 'Start of paragraph'),
      make_clue('}', 'End of paragraph'),
      make_clue('<', 'Start of latest visual selection'),
      make_clue('>', 'End of latest visual selection'),
    }
  end

  --stylua: ignore
  return {
    -- Normal mode
    describe_marks('n', "'"),
    describe_marks('n', "g'"),
    describe_marks('n', "`"),
    describe_marks('n', "g`"),

    -- Visual mode
    describe_marks('x', "'"),
    describe_marks('x', "g'"),
    describe_marks('x', "`"),
    describe_marks('x', "g`"),
  }
end

--- Generate clues for registers
---
--- Contains clues for the following triggers: >lua
---
---   { mode = 'n', keys = '"' }
---   { mode = 'x', keys = '"' }
---   { mode = 'i', keys = '<C-r>' }
---   { mode = 'c', keys = '<C-r>' }
--- <
---@param opts table|nil Options. Possible keys:
---   - <show_contents> `(boolean)` - whether to show contents of all possible
---     registers. If `false`, only description of special registers is shown.
---     Default: `false`.
---
---@return table Array of clues.
---
---@seealso |registers|
MiniClue.gen_clues.registers = function(opts)
  opts = vim.tbl_deep_extend('force', { show_contents = false }, opts or {})

  local describe_registers
  if opts.show_contents then
    describe_registers = H.make_clues_with_register_contents
  else
    describe_registers = function(mode, prefix)
      local make_clue = function(register, desc) return { mode = mode, keys = prefix .. register, desc = desc } end
      return {
        make_clue('0', 'Latest yank'),
        make_clue('1', 'Latest big delete'),
        make_clue('"', 'Default register'),
        make_clue('#', 'Alternate buffer'),
        make_clue('%', 'Name of the current file'),
        make_clue('*', 'Selection clipboard'),
        make_clue('+', 'System clipboard'),
        make_clue('-', 'Latest small delete'),
        make_clue('.', 'Latest inserted text'),
        make_clue('/', 'Latest search pattern'),
        make_clue(':', 'Latest executed command'),
        make_clue('=', 'Result of expression'),
        make_clue('_', 'Black hole'),
      }
    end
  end

  --stylua: ignore
  return {
    -- Normal mode
    describe_registers('n', '"'),

    -- Visual mode
    describe_registers('x', '"'),

    -- Insert mode
    describe_registers('i', '<C-r>'),

    { mode = 'i', keys = '<C-r><C-r>', desc = '+Insert literally' },
    describe_registers('i', '<C-r><C-r>'),

    { mode = 'i', keys = '<C-r><C-o>', desc = '+Insert literally + not auto-indent' },
    describe_registers('i', '<C-r><C-o>'),

    { mode = 'i', keys = '<C-r><C-p>', desc = '+Insert + fix indent' },
    describe_registers('i', '<C-r><C-p>'),

    -- Command-line mode
    describe_registers('c', '<C-r>'),

    { mode = 'c', keys = '<C-r><C-r>', desc = '+Insert literally' },
    describe_registers('c', '<C-r><C-r>'),

    { mode = 'c', keys = '<C-r><C-o>', desc = '+Insert literally' },
    describe_registers('c', '<C-r><C-o>'),
  }
end

--- Generate clues for window commands
---
--- Contains clues for the following triggers: >lua
---
---   { mode = 'n', keys = '<C-w>' }
--- <
--- Note: only non-duplicated commands are included. For full list see |CTRL-W|.
---
---@param opts table|nil Options. Possible keys:
---   - <submode_move> `(boolean)` - whether to make move (change layout)
---     commands a submode by using `postkeys` field. Default: `false`.
---   - <submode_navigate> `(boolean)` - whether to make navigation (change
---     focus) commands a submode by using `postkeys` field. Default: `false`.
---   - <submode_resize> `(boolean)` - whether to make resize (change size)
---     commands a submode by using `postkeys` field. Default: `false`.
---
---@return table Array of clues.
MiniClue.gen_clues.windows = function(opts)
  local default_opts = { submode_navigate = false, submode_move = false, submode_resize = false }
  opts = vim.tbl_deep_extend('force', default_opts, opts or {})

  local postkeys_move, postkeys_navigate, postkeys_resize = nil, nil, nil
  if opts.submode_move then postkeys_move = '<C-w>' end
  if opts.submode_navigate then postkeys_navigate = '<C-w>' end
  if opts.submode_resize then postkeys_resize = '<C-w>' end

  --stylua: ignore
  return {
    { mode = 'n', keys = '<C-w>+',      desc = 'Increase height',         postkeys = postkeys_resize },
    { mode = 'n', keys = '<C-w>-',      desc = 'Decrease height',         postkeys = postkeys_resize },
    { mode = 'n', keys = '<C-w><',      desc = 'Decrease width',          postkeys = postkeys_resize },
    { mode = 'n', keys = '<C-w>>',      desc = 'Increase width',          postkeys = postkeys_resize },
    { mode = 'n', keys = '<C-w>=',      desc = 'Make windows same dimensions' },
    { mode = 'n', keys = '<C-w>]',      desc = 'Split + jump to tag' },
    { mode = 'n', keys = '<C-w>^',      desc = 'Split + edit alternate file' },
    { mode = 'n', keys = '<C-w>_',      desc = 'Set height (def: very high)' },
    { mode = 'n', keys = '<C-w>|',      desc = 'Set width (def: very wide)' },
    { mode = 'n', keys = '<C-w>}',      desc = 'Show tag in preview' },
    { mode = 'n', keys = '<C-w>b',      desc = 'Focus bottom',            postkeys = postkeys_navigate },
    { mode = 'n', keys = '<C-w>c',      desc = 'Close' },
    { mode = 'n', keys = '<C-w>d',      desc = 'Split + jump to definition' },
    { mode = 'n', keys = '<C-w>F',      desc = 'Split + edit file name + jump' },
    { mode = 'n', keys = '<C-w>f',      desc = 'Split + edit file name' },
    { mode = 'n', keys = '<C-w>g',      desc = '+Extra actions' },
    { mode = 'n', keys = '<C-w>g]',     desc = 'Split + list tags' },
    { mode = 'n', keys = '<C-w>g}',     desc = 'Do `:ptjump`' },
    { mode = 'n', keys = '<C-w>g<C-]>', desc = 'Split + jump to tag with `:tjump`' },
    { mode = 'n', keys = '<C-w>g<Tab>', desc = 'Focus last accessed tab', postkeys = postkeys_navigate },
    { mode = 'n', keys = '<C-w>gF',     desc = 'New tabpage + edit file name + jump' },
    { mode = 'n', keys = '<C-w>gf',     desc = 'New tabpage + edit file name' },
    { mode = 'n', keys = '<C-w>gT',     desc = 'Focus previous tabpage',  postkeys = postkeys_navigate },
    { mode = 'n', keys = '<C-w>gt',     desc = 'Focus next tabpage',      postkeys = postkeys_navigate },
    { mode = 'n', keys = '<C-w>H',      desc = 'Move to very left',       postkeys = postkeys_move },
    { mode = 'n', keys = '<C-w>h',      desc = 'Focus left',              postkeys = postkeys_navigate },
    { mode = 'n', keys = '<C-w>i',      desc = 'Split + jump to declaration' },
    { mode = 'n', keys = '<C-w>J',      desc = 'Move to very bottom',     postkeys = postkeys_move },
    { mode = 'n', keys = '<C-w>j',      desc = 'Focus down',              postkeys = postkeys_navigate },
    { mode = 'n', keys = '<C-w>K',      desc = 'Move to very top',        postkeys = postkeys_move },
    { mode = 'n', keys = '<C-w>k',      desc = 'Focus up',                postkeys = postkeys_navigate },
    { mode = 'n', keys = '<C-w>L',      desc = 'Move to very right',      postkeys = postkeys_move },
    { mode = 'n', keys = '<C-w>l',      desc = 'Focus right',             postkeys = postkeys_navigate },
    { mode = 'n', keys = '<C-w>n',      desc = 'Open new' },
    { mode = 'n', keys = '<C-w>o',      desc = 'Close all but current' },
    { mode = 'n', keys = '<C-w>P',      desc = 'Focus preview',           postkeys = postkeys_navigate },
    { mode = 'n', keys = '<C-w>p',      desc = 'Focus last accessed',     postkeys = postkeys_navigate },
    { mode = 'n', keys = '<C-w>q',      desc = 'Quit current' },
    { mode = 'n', keys = '<C-w>R',      desc = 'Rotate up/left',          postkeys = postkeys_move },
    { mode = 'n', keys = '<C-w>r',      desc = 'Rotate down/right',       postkeys = postkeys_move },
    { mode = 'n', keys = '<C-w>s',      desc = 'Split horizontally' },
    { mode = 'n', keys = '<C-w>T',      desc = 'Create new tabpage + move' },
    { mode = 'n', keys = '<C-w>t',      desc = 'Focus top',               postkeys = postkeys_navigate },
    { mode = 'n', keys = '<C-w>v',      desc = 'Split vertically' },
    { mode = 'n', keys = '<C-w>W',      desc = 'Focus previous',          postkeys = postkeys_navigate },
    { mode = 'n', keys = '<C-w>w',      desc = 'Focus next',              postkeys = postkeys_navigate },
    { mode = 'n', keys = '<C-w>x',      desc = 'Exchange windows',        postkeys = postkeys_move },
    { mode = 'n', keys = '<C-w>z',      desc = 'Close preview' },
  }
end

--- Generate clues for `z` key
---
--- Contains clues for the following triggers: >lua
---
---   { mode = 'n', keys = 'z' }
---   { mode = 'x', keys = 'z' }
--- <
---@return table Array of clues.
MiniClue.gen_clues.z = function()
  --stylua: ignore
  return {
    { mode = 'n', keys = 'zA',   desc = 'Toggle folds recursively' },
    { mode = 'n', keys = 'za',   desc = 'Toggle fold' },
    { mode = 'n', keys = 'zb',   desc = 'Redraw at bottom' },
    { mode = 'n', keys = 'zC',   desc = 'Close folds recursively' },
    { mode = 'n', keys = 'zc',   desc = 'Close fold' },
    { mode = 'n', keys = 'zD',   desc = 'Delete folds recursively' },
    { mode = 'n', keys = 'zd',   desc = 'Delete fold' },
    { mode = 'n', keys = 'zE',   desc = 'Eliminate all folds' },
    { mode = 'n', keys = 'ze',   desc = 'Scroll to cursor on right screen side' },
    { mode = 'n', keys = 'zF',   desc = 'Create fold' },
    { mode = 'n', keys = 'zf',   desc = 'Create fold (operator)' },
    { mode = 'n', keys = 'zG',   desc = 'Temporarily mark as correctly spelled' },
    { mode = 'n', keys = 'zg',   desc = 'Permanently mark as correctly spelled' },
    { mode = 'n', keys = 'zH',   desc = 'Scroll left half screen' },
    { mode = 'n', keys = 'zh',   desc = 'Scroll left' },
    { mode = 'n', keys = 'zi',   desc = "Toggle 'foldenable'" },
    { mode = 'n', keys = 'zj',   desc = 'Move to start of next fold' },
    { mode = 'n', keys = 'zk',   desc = 'Move to end of previous fold' },
    { mode = 'n', keys = 'zL',   desc = 'Scroll right half screen' },
    { mode = 'n', keys = 'zl',   desc = 'Scroll right' },
    { mode = 'n', keys = 'zM',   desc = 'Close all folds' },
    { mode = 'n', keys = 'zm',   desc = 'Fold more' },
    { mode = 'n', keys = 'zN',   desc = "Set 'foldenable'" },
    { mode = 'n', keys = 'zn',   desc = "Reset 'foldenable'" },
    { mode = 'n', keys = 'zO',   desc = 'Open folds recursively' },
    { mode = 'n', keys = 'zo',   desc = 'Open fold' },
    { mode = 'n', keys = 'zP',   desc = 'Paste without trailspace' },
    { mode = 'n', keys = 'zp',   desc = 'Paste without trailspace' },
    { mode = 'n', keys = 'zR',   desc = 'Open all folds' },
    { mode = 'n', keys = 'zr',   desc = 'Fold less' },
    { mode = 'n', keys = 'zs',   desc = 'Scroll to cursor on left screen side' },
    { mode = 'n', keys = 'zt',   desc = 'Redraw at top' },
    { mode = 'n', keys = 'zu',   desc = '+Undo spelling commands' },
    { mode = 'n', keys = 'zug',  desc = 'Undo `zg`' },
    { mode = 'n', keys = 'zuG',  desc = 'Undo `zG`' },
    { mode = 'n', keys = 'zuw',  desc = 'Undo `zw`' },
    { mode = 'n', keys = 'zuW',  desc = 'Undo `zW`' },
    { mode = 'n', keys = 'zv',   desc = 'Open enough folds' },
    { mode = 'n', keys = 'zW',   desc = 'Temporarily mark as incorrectly spelled' },
    { mode = 'n', keys = 'zw',   desc = 'Permanently mark as incorrectly spelled' },
    { mode = 'n', keys = 'zX',   desc = 'Update folds' },
    { mode = 'n', keys = 'zx',   desc = 'Update folds + open enough folds' },
    { mode = 'n', keys = 'zy',   desc = 'Yank without trailing spaces (operator)' },
    { mode = 'n', keys = 'zz',   desc = 'Redraw at center' },
    { mode = 'n', keys = 'z+',   desc = 'Redraw under bottom at top' },
    { mode = 'n', keys = 'z-',   desc = 'Redraw at bottom + cursor on first non-blank' },
    { mode = 'n', keys = 'z.',   desc = 'Redraw at center + cursor on first non-blank' },
    { mode = 'n', keys = 'z=',   desc = 'Show spelling suggestions' },
    { mode = 'n', keys = 'z^',   desc = 'Redraw above top at bottom' },

    { mode = 'x', keys = 'zf',   desc = 'Create fold from selection' },
  }
end

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniClue.config)

-- Namespaces
H.ns_id = {
  highlight = vim.api.nvim_create_namespace('MiniClueHighlight'),
}

-- State of user input
H.state = {
  trigger = nil,
  -- Array of raw keys
  query = {},
  clues = {},
  timer = vim.loop.new_timer(),
  buf_id = nil,
  win_id = nil,
  is_after_postkeys = false,
}

-- Default window config
H.default_win_config = {
  anchor = 'SE',
  focusable = false,
  relative = 'editor',
  style = 'minimal',
  width = 30,
  -- Use high enough value to be on top of built-in windows (pmenu, etc.)
  zindex = 251,
}

-- Precomputed raw keys
H.keys = {
  bs = vim.api.nvim_replace_termcodes('<BS>', true, true, true),
  cr = vim.api.nvim_replace_termcodes('<CR>', true, true, true),
  exit = vim.api.nvim_replace_termcodes([[<C-\><C-n>]], true, true, true),
  ctrl_d = vim.api.nvim_replace_termcodes('<C-d>', true, true, true),
  ctrl_u = vim.api.nvim_replace_termcodes('<C-u>', true, true, true),
}

-- Special filetypes for which to enable triggers. These are common interactive
-- not listed filetypes. NOTE: no 'minifiles' as `'` trigger conflicts with its
-- local `'`. Plus it pollutes `g?` content.
H.ft_to_enable = { help = true, git = true, ministarter = true }

-- Timers
H.timers = {
  getcharstr = vim.loop.new_timer(),
}

-- Undo autocommand to be created for several operator tweaks
H.undo_autocommand = 'au ModeChanged * ++once undo!'

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  H.check_type('clues', config.clues, 'table')
  H.check_type('triggers', config.triggers, 'table')

  H.check_type('window', config.window, 'table')
  if not (type(config.window.config) == 'table' or vim.is_callable(config.window.config)) then
    H.error('`window.config` should be table or callable, not ' .. type(config.window.config))
  end
  H.check_type('window.delay', config.window.delay, 'number')
  H.check_type('window.scroll_down', config.window.scroll_down, 'string')
  H.check_type('window.scroll_up', config.window.scroll_up, 'string')

  return config
end

H.apply_config = function(config)
  MiniClue.config = config

  -- Create trigger keymaps for all existing buffers
  MiniClue.enable_all_triggers()

  -- Tweak macro execution
  local exec_macro = function(key, register)
    if register == nil then return end
    MiniClue.disable_all_triggers()
    vim.schedule(function() MiniClue.enable_all_triggers() end)
    -- NOTE: Use `t` flag for "Handle as if typed" for better integration with
    -- other modules/plugins (like 'mini.jump').
    pcall(vim.api.nvim_feedkeys, vim.v.count1 .. key .. register, 'nt', false)
  end

  local macro_keymap_opts = { nowait = true, desc = "Execute macro without 'mini.clue' triggers" }

  local exec_register_macro = function() exec_macro('@', H.getcharstr()) end
  if vim.fn.maparg('@', 'n') == '' then vim.keymap.set('n', '@', exec_register_macro, macro_keymap_opts) end

  local exec_latest_macro = function() exec_macro('Q', '') end
  if vim.fn.maparg('Q', 'n') == '' then vim.keymap.set('n', 'Q', exec_latest_macro, macro_keymap_opts) end
end

H.is_disabled = function(buf_id)
  local buf_disable = H.get_buf_var(buf_id, 'miniclue_disable')
  return vim.g.miniclue_disable == true or buf_disable == true
end

H.create_autocommands = function()
  local gr = vim.api.nvim_create_augroup('MiniClue', {})

  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = gr, pattern = pattern, callback = callback, desc = desc })
  end

  -- Ensure buffer-local mappings for triggers are the latest ones to fully
  -- utilize `<nowait>`. Use `vim.schedule_wrap` to allow other events to
  -- create `vim.b.miniclue_config` and `vim.b.miniclue_disable`.
  local ensure_triggers = vim.schedule_wrap(function(data)
    if not H.is_valid_buf(data.buf) then return end
    MiniClue.ensure_buf_triggers(data.buf)
  end)
  -- - Respect `LspAttach` as it is a common source of buffer-local mappings
  local events = { 'BufAdd', 'LspAttach' }
  au(events, '*', ensure_triggers, 'Ensure buffer-local trigger keymaps')
  au('Filetype', vim.tbl_keys(H.ft_to_enable), ensure_triggers, 'Ensure buffer-local trigger keymaps')

  -- Disable all triggers (current and future) when recording macro as they
  -- interfere with what is actually recorded
  local cache_disable
  local disable_all_plus = function()
    MiniClue.disable_all_triggers()
    cache_disable = vim.g.miniclue_disable
    vim.g.miniclue_disable = true
  end
  local enable_all_plus = function()
    vim.g.miniclue_disable = cache_disable
    MiniClue.enable_all_triggers()
  end
  au('RecordingEnter', '*', disable_all_plus, 'Disable all triggers')
  au('RecordingLeave', '*', enable_all_plus, 'Enable all triggers')

  au('VimResized', '*', H.window_update, 'Update window on resize')
  au('ColorScheme', '*', H.create_default_hl, 'Ensure colors')
end

--stylua: ignore
H.create_default_hl = function()
  local hi = function(name, opts)
    opts.default = true
    vim.api.nvim_set_hl(0, name, opts)
  end

  hi('MiniClueBorder',              { link = 'FloatBorder' })
  hi('MiniClueDescGroup',           { link = 'DiagnosticFloatingWarn' })
  hi('MiniClueDescSingle',          { link = 'NormalFloat' })
  hi('MiniClueNextKey',             { link = 'DiagnosticFloatingHint' })
  hi('MiniClueNextKeyWithPostkeys', { link = 'DiagnosticFloatingError' })
  hi('MiniClueSeparator',           { link = 'DiagnosticFloatingInfo' })
  hi('MiniClueTitle',               { link = 'FloatTitle' })
end

H.get_config = function(config, buf_id)
  config = config or {}
  local buf_config = H.get_buf_var(buf_id, 'miniclue_config') or {}
  local global_config = MiniClue.config

  -- Manually reconstruct to allow array elements to be concatenated
  local res = {
    clues = H.list_concat(global_config.clues, buf_config.clues, config.clues),
    triggers = H.list_concat(global_config.triggers, buf_config.triggers, config.triggers),
    window = vim.tbl_deep_extend('force', global_config.window, buf_config.window or {}, config.window or {}),
  }
  return res
end

H.get_buf_var = function(buf_id, name)
  buf_id = buf_id or vim.api.nvim_get_current_buf()
  if not H.is_valid_buf(buf_id) then return nil end
  return vim.b[buf_id][name]
end

-- Triggers -------------------------------------------------------------------

H.map_buf_triggers = function(buf_id)
  if not H.is_valid_buf(buf_id) or H.is_disabled(buf_id) then return end

  local apply_trigger_key = function(mode, key)
    if type(key) == "table" then
      for _, key in pairs(key) do
        H.map_trigger(buf_id, { mode = mode, keys = key })
      end
    else
      H.map_trigger(buf_id, { mode = mode, keys = key })
    end
  end
  local apply_trigger_mode = function(trigger)
    if type(trigger.mode) == "table" then
      for _, mode in pairs(trigger.mode) do
        apply_trigger_key(mode, trigger.keys)
      end
    else
      apply_trigger_key(trigger.mode, trigger.keys)
    end
  end
  for _, trigger in ipairs(H.get_config(nil, buf_id).triggers) do
    apply_trigger_mode(trigger)
  end
end

H.unmap_buf_triggers = function(buf_id)
  if not H.is_valid_buf(buf_id) or H.is_disabled(buf_id) then return end

  local unapply_trigger_key = function(mode, key)
    if type(key) == "table" then
      for _, key in pairs(key) do
        H.unmap_trigger(buf_id, { mode = mode, keys = key })
      end
    else
      H.unmap_trigger(buf_id, { mode = mode, keys = key })
    end
  end
  local unpaply_trigger_mode = function(trigger)
    if type(trigger.mode) == "table" then
      for _, mode in pairs(trigger.mode) do
        unapply_trigger_key(mode, trigger.keys)
      end
    else
      unapply_trigger_key(trigger.mode, trigger.keys)
    end
  end
  for _, trigger in ipairs(H.get_config(nil, buf_id).triggers) do
    unpaply_trigger_mode(trigger)
  end
end

H.map_trigger = function(buf_id, trigger)
  if not H.is_valid_buf(buf_id) then return end

  -- Compute mapping RHS
  trigger.keys = H.replace_termcodes(trigger.keys)
  local lhs = H.keytrans(trigger.keys)

  local is_ministarter_map = vim.bo[buf_id].filetype == 'ministarter'
    and vim.api.nvim_buf_call(buf_id, function() return vim.fn.maparg(lhs, trigger.mode) ~= '' end)
  if is_ministarter_map then return end

  local rhs = function()
    -- Don't act if for some reason entered the same trigger during state exec
    local is_in_exec = type(H.exec_trigger) == 'table'
      and H.exec_trigger.mode == trigger.mode
      and H.exec_trigger.keys == trigger.keys
    if is_in_exec then
      H.exec_trigger = nil
      return
    end

    -- Start user query
    H.state_set(trigger, { trigger.keys })

    -- Do not advance if no other clues to query. NOTE: it is `<= 1` and not
    -- `<= 0` because the "init query" mapping should match.
    if vim.tbl_count(H.state.clues) <= 1 then return H.state_exec() end

    H.state_advance()
  end

  -- Use buffer-local mappings and `nowait` to make it a primary source of
  -- keymap execution
  local desc = string.format('Query keys after "%s"', lhs)
  local opts = { buffer = buf_id, nowait = true, desc = desc }

  -- Create mapping. Use translated variant to make it work with <F*> keys.
  vim.keymap.set(trigger.mode, lhs, rhs, opts)
end

H.unmap_trigger = function(buf_id, trigger)
  if not H.is_valid_buf(buf_id) then return end
  pcall(vim.keymap.del, trigger.mode, H.keytrans(trigger.keys), { buffer = buf_id })
end

-- State ----------------------------------------------------------------------
H.state_advance = function(opts)
  opts = opts or {}
  local config_window = H.get_config().window

  -- Show clues: delay (debounce) first show; update immediately if shown or
  -- after postkeys (for visual feedback that extra key is needed to stop)
  H.state.timer:stop()
  local show_immediately = H.is_valid_win(H.state.win_id) or H.state.is_after_postkeys
  local delay = show_immediately and 0 or config_window.delay
  H.state.timer:start(delay, 0, function() H.window_update(opts.same_content) end)

  -- Reset postkeys right now to not flicker when trying to close window during
  -- "not querying" check
  H.state.is_after_postkeys = false

  -- Query user for new key
  local key = H.getcharstr()

  -- Handle key
  if key == nil then return H.state_reset() end

  if key == H.keys.cr then return H.state_exec() end

  local is_window_shown = H.is_valid_win(H.state.win_id)
  local is_scroll_down = key == H.replace_termcodes(config_window.scroll_down)
  local is_scroll_up = key == H.replace_termcodes(config_window.scroll_up)
  if is_window_shown and (is_scroll_down or is_scroll_up) then
    H.window_scroll(is_scroll_down)
    return H.state_advance({ same_content = true })
  end

  if key == H.keys.bs then
    H.state_pop()
  else
    H.state_push(key)
  end

  -- Advance state
  -- - Execute if reached single target keymap
  if H.state_is_at_target() then return H.state_exec() end

  -- - Reset if there are no keys (like after `<BS>`)
  if #H.state.query == 0 then return H.state_reset() end

  -- - Query user for more information if there is not enough
  --   NOTE: still advance even if there is single clue because it is still not
  --   a target but can be one.
  if vim.tbl_count(H.state.clues) >= 1 then return H.state_advance() end

  -- - Fall back for executing what user typed
  H.state_exec()
end

H.state_set = function(trigger, query)
  H.state.trigger = trigger
  H.state.query = query
  H.state.clues = H.clues_filter(H.clues_get_all(trigger.mode), query)
end

H.state_reset = function(keep_window)
  H.state.trigger = nil
  H.state.query = {}
  H.state.clues = {}
  H.state.is_after_postkeys = false

  H.state.timer:stop()
  if not keep_window then H.window_close() end
end

H.state_exec = function()
  -- Compute keys to type
  local keys_to_type = H.compute_exec_keys()

  -- Add extra (redundant) safety flag to try to avoid infinite recursion
  local trigger, clue = H.state.trigger, H.state_get_query_clue()
  H.exec_trigger = trigger
  vim.schedule(function() H.exec_trigger = nil end)

  -- Reset state
  local has_postkeys = (clue or {}).postkeys ~= nil
  H.state_reset(has_postkeys)

  -- Disable trigger !!!VERY IMPORTANT!!!
  -- This is a workaround against infinite recursion (like if `g` is trigger
  -- then typing `gg`/`g~` would introduce infinite recursion).
  local buf_id = vim.api.nvim_get_current_buf()
  H.unmap_trigger(buf_id, trigger)

  -- Execute keys. The `i` flag is used to fully support Operator-pending mode.
  -- Flag `t` imitates keys as if user typed, which is reasonable but has small
  -- downside with edge cases of 'langmap' (like ':\;;\;:') as it "inverts" key
  -- meaning second time (at least in Normal mode).
  vim.api.nvim_feedkeys(keys_to_type, 'mit', false)

  -- Enable trigger back after it can no longer harm
  vim.schedule(function() H.map_trigger(buf_id, trigger) end)

  -- Apply postkeys (in scheduled fashion)
  if has_postkeys then H.state_apply_postkeys(clue.postkeys) end
end

H.state_push = function(keys)
  table.insert(H.state.query, keys)
  H.state.clues = H.clues_filter(H.state.clues, H.state.query)
end

H.state_pop = function()
  H.state.query[#H.state.query] = nil
  H.state.clues = H.clues_filter(H.clues_get_all(H.state.trigger.mode), H.state.query)
end

H.state_apply_postkeys = vim.schedule_wrap(function(postkeys)
  -- Register that possible future querying is a result of postkeys.
  -- This enables (keep) showing window immediately.
  H.state.is_after_postkeys = true

  -- Use `nvim_feedkeys()` because using `state_set()` and
  -- `state_advance()` directly does not work: it doesn't guarantee to be
  -- executed **after** keys from `nvim_feedkeys()`.
  vim.api.nvim_feedkeys(postkeys, 'mit', false)

  -- Defer check of whether postkeys resulted into window.
  -- Could not find proper way to check this which guarantees to be executed
  -- after `nvim_feedkeys()` takes effect **end** doesn't result into flicker
  -- when consecutively applying "submode" keys.
  vim.defer_fn(function()
    if #H.state.query == 0 then H.window_close() end
  end, 50)
end)

H.state_is_at_target = function()
  return vim.tbl_count(H.state.clues) == 1 and H.state.clues[H.query_to_keys(H.state.query)] ~= nil
end

H.state_get_query_clue = function()
  local keys = H.query_to_keys(H.state.query)
  return H.state.clues[keys]
end

H.compute_exec_keys = function()
  local keys_count = vim.v.count > 0 and vim.v.count or ''
  local keys_query = H.query_to_keys(H.state.query)
  local res = keys_count .. keys_query

  local cur_mode = vim.fn.mode(1)

  -- Using `feedkeys()` inside Operator-pending mode leads to its cancel into
  -- Normal/Insert mode so extra work should be done to rebuild all keys
  if vim.startswith(cur_mode, 'no') then
    local operator_tweak = H.operator_tweaks[vim.v.operator] or function(x) return x end
    res = operator_tweak(vim.v.operator .. H.get_forced_submode() .. res)
  elseif not vim.startswith(cur_mode, 'i') and H.get_default_register() ~= vim.v.register then
    -- Force non-default register but not in Insert mode
    local expr_reg_keys = vim.v.register == '=' and (vim.fn.getreginfo('=').regcontents[1] .. '\r') or ''
    res = '"' .. vim.v.register .. expr_reg_keys .. res
  end

  -- `feedkeys()` inside "temporary" Normal mode is executed **after** it is
  -- already back from Normal mode. Go into it again with `<C-o>` ('\15').
  -- NOTE: This only works when Normal mode trigger is triggered in
  -- "temporary" Normal mode. Still doesn't work when Operator-pending mode is
  -- triggered afterwards (like in `<C-o>gUiw` with 'i' as trigger).
  if cur_mode:find('^ni') ~= nil then res = '\15' .. res end

  return res
end

-- Some operators needs special tweaking due to their nature:
-- - Some operators perform on register. Solution: add register explicitly.
-- - Some operators end up changing mode which affects `feedkeys()`.
--   Solution: explicitly exit to Normal mode with '<C-\><C-n>'.
-- - Some operators still perform some redundant operation before `feedkeys()`
--   takes effect. Solution: add one-shot autocommand undoing that.
H.operator_tweaks = {
  ['c'] = function(keys)
    -- Doing '<C-\><C-n>' moves cursor one space to left (same as `i<Esc>`).
    -- Solution: add one-shot autocommand correcting cursor position.
    vim.cmd('au InsertLeave * ++once normal! l')
    return H.keys.exit .. '"' .. vim.v.register .. keys
  end,
  ['d'] = function(keys) return '"' .. vim.v.register .. keys end,
  ['y'] = function(keys) return '"' .. vim.v.register .. keys end,
  ['~'] = function(keys)
    if vim.fn.col('.') == 1 then vim.cmd(H.undo_autocommand) end
    return keys
  end,
  ['g~'] = function(keys)
    if vim.fn.col('.') == 1 then vim.cmd(H.undo_autocommand) end
    return keys
  end,
  ['g?'] = function(keys)
    if vim.fn.col('.') == 1 then vim.cmd(H.undo_autocommand) end
    return keys
  end,
  ['!'] = function(keys) return H.keys.exit .. keys end,
  ['>'] = function(keys)
    vim.cmd(H.undo_autocommand)
    return keys
  end,
  ['<'] = function(keys)
    vim.cmd(H.undo_autocommand)
    return keys
  end,
  ['g@'] = function(keys)
    -- Cancelling in-process `g@` operator seems to be particularly hard.
    -- Not even sure why specifically this combination works, but having `x`
    -- flag in `feedkeys()` is crucial.
    vim.api.nvim_feedkeys(H.keys.exit, 'nx', false)
    return H.keys.exit .. keys
  end,
}

H.query_to_keys = function(query) return table.concat(query, '') end

-- Window ---------------------------------------------------------------------
H.window_update = vim.schedule_wrap(function(same_content)
  -- Make sure that outdated windows are not shown
  if #H.state.query == 0 then return H.window_close() end
  local win_id = H.state.win_id

  -- Close window if it is not in current tabpage (as only window is tracked)
  local is_different_tabpage = H.is_valid_win(win_id)
    and vim.api.nvim_win_get_tabpage(win_id) ~= vim.api.nvim_get_current_tabpage()
  if is_different_tabpage then H.window_close() end

  -- Create-update buffer showing clues
  if not same_content then H.state.buf_id = H.buffer_update() end

  -- Create-update window showing buffer
  local win_config = H.window_get_config()
  if not H.is_valid_win(win_id) then
    win_config.noautocmd = true
    win_id = H.window_open(win_config)
    H.state.win_id = win_id
  else
    vim.api.nvim_win_set_config(win_id, win_config)
    vim.wo[win_id].list = true
  end

  -- Make scroll not persist. NOTE: Don't use 'normal! gg' inside target window
  -- as it resets `v:count` and `v:register` which results into invalid keys
  -- reproduction in Operator-pending mode.
  if not same_content then vim.api.nvim_win_set_cursor(win_id, { 1, 0 }) end

  -- Add redraw because Neovim won't do it when `getcharstr()` is active
  vim.cmd('redraw')
end)

H.window_scroll = function(is_scroll_down)
  local scroll_key = is_scroll_down and H.keys.ctrl_d or H.keys.ctrl_u
  local f = function()
    local cache_scroll, bot_line, n_lines = vim.wo.scroll, vim.fn.line('w$'), vim.api.nvim_buf_line_count(0)
    -- Do not scroll past the end of buffer
    local scroll_count = is_scroll_down and math.min(cache_scroll, n_lines - bot_line) or cache_scroll
    if scroll_count > 0 then pcall(vim.cmd, 'normal! ' .. scroll_count .. scroll_key) end
    vim.wo.scroll = cache_scroll
  end
  vim.api.nvim_win_call(H.state.win_id, f)
end

H.window_open = function(config)
  local win_id = vim.api.nvim_open_win(H.state.buf_id, false, config)

  vim.wo[win_id].foldenable = false
  vim.wo[win_id].foldmethod = 'manual'
  vim.wo[win_id].wrap = false
  vim.wo[win_id].list = true
  vim.wo[win_id].listchars = 'extends:…'

  local win_hl = 'FloatBorder:MiniClueBorder,FloatTitle:MiniClueTitle'
  vim.wo[win_id].winhighlight = win_hl

  return win_id
end

H.window_close = function()
  -- Closing floating window when Command-line window is active is not allowed
  -- on Neovim<0.10. Make sure it is closed after leaving it.
  -- See https://github.com/neovim/neovim/issues/24452
  local win_id = H.state.win_id
  if vim.fn.has('nvim-0.10') == 0 and vim.fn.getcmdwintype() ~= '' then
    vim.api.nvim_create_autocmd(
      'CmdwinLeave',
      { once = true, callback = function() pcall(vim.api.nvim_win_close, win_id, true) end }
    )
    return
  else
    pcall(vim.api.nvim_win_close, win_id, true)
  end

  H.state.win_id = nil
end

H.window_get_config = function()
  local has_statusline = vim.o.laststatus > 0
  local has_tabline = vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1)
  -- Remove 2 from maximum height to account for top and bottom borders
  local max_height = vim.o.lines - vim.o.cmdheight - (has_tabline and 1 or 0) - (has_statusline and 1 or 0) - 2
  max_height = math.max(max_height, 1)

  local keys = H.query_to_keys(H.state.query)
  local query_clue = (H.state.clues[keys] or {}).desc or ''
  local title = (#H.state.query <= 1 or query_clue == '') and H.keytrans(keys) or query_clue

  local buf_id = H.state.buf_id
  local cur_config_fields = {
    row = vim.o.lines - vim.o.cmdheight - (has_statusline and 1 or 0),
    col = vim.o.columns,
    height = math.min(vim.api.nvim_buf_line_count(buf_id), max_height),
    title = ' ' .. title .. ' ',
    border = (vim.fn.exists('+winborder') == 0 or vim.o.winborder == '') and 'single' or nil,
  }
  local user_config = H.expand_callable(H.get_config().window.config, buf_id) or {}
  local res = vim.tbl_deep_extend('force', H.default_win_config, cur_config_fields, user_config)

  -- Tweak "auto" fields
  if res.width == 'auto' then res.width = H.buffer_get_width() + 1 end

  if res.row == 'auto' then
    local is_on_top = res.anchor == 'NW' or res.anchor == 'NE'
    res.row = is_on_top and (has_tabline and 1 or 0) or cur_config_fields.row
  end

  if res.col == 'auto' then
    local is_on_left = res.anchor == 'NW' or res.anchor == 'SW'
    res.col = is_on_left and 0 or cur_config_fields.col
  end

  -- Ensure proper config
  res.width = math.min(math.max(res.width, 1), vim.o.columns - 2)
  if type(res.title) == 'string' then res.title = H.fit_to_width(res.title, res.width) end

  return res
end

-- Buffer ---------------------------------------------------------------------
H.buffer_update = function()
  local buf_id = H.state.buf_id
  if not H.is_valid_buf(buf_id) then
    buf_id = vim.api.nvim_create_buf(false, true)
    H.set_buf_name(buf_id, 'content')
  end

  -- Compute content data
  local keys = H.query_to_keys(H.state.query)
  local content = H.clues_to_buffer_content(H.state.clues, keys)

  -- Add lines
  local lines = {}
  for _, line_content in ipairs(content) do
    table.insert(lines, string.format(' %s │ %s', line_content.next_key, line_content.desc))
  end
  vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)

  -- Add highlighting
  local ns_id = H.ns_id.highlight
  vim.api.nvim_buf_clear_namespace(buf_id, ns_id, 0, -1)

  local set_hl = function(hl_group, line_from, col_from, line_to, col_to)
    local opts = { end_row = line_to, end_col = col_to, hl_group = hl_group, hl_eol = true }
    vim.api.nvim_buf_set_extmark(buf_id, ns_id, line_from, col_from, opts)
  end

  for i, line_content in ipairs(content) do
    local sep_start = line_content.next_key:len() + 3
    local next_key_hl_group = line_content.has_postkeys and 'MiniClueNextKeyWithPostkeys' or 'MiniClueNextKey'
    set_hl(next_key_hl_group, i - 1, 0, i - 1, sep_start - 1)

    -- NOTE: Separator '│' is 3 bytes long
    set_hl('MiniClueSeparator', i - 1, sep_start - 1, i - 1, sep_start + 2)

    local desc_hl_group = line_content.is_group and 'MiniClueDescGroup' or 'MiniClueDescSingle'
    set_hl(desc_hl_group, i - 1, sep_start + 2, i, 0)
  end

  return buf_id
end

H.buffer_get_width = function()
  if not H.is_valid_buf(H.state.buf_id) then return end
  local lines = vim.api.nvim_buf_get_lines(H.state.buf_id, 0, -1, false)
  local res = 0
  for _, l in ipairs(lines) do
    res = math.max(res, vim.fn.strdisplaywidth(l))
  end
  return res
end

-- Clues ----------------------------------------------------------------------
H.clues_get_all = function(mode)
  local res = {}

  -- Order of clue precedence: config clues < buffer mappings < global mappings
  local config_clues = H.clues_normalize(H.get_config().clues) or {}
  local mode_clues = vim.tbl_filter(function(x) return x.mode == mode end, config_clues)
  for _, clue in ipairs(mode_clues) do
    local lhsraw = H.replace_termcodes(clue.keys)

    local res_data = res[lhsraw] or {}

    -- - Allow callable clue description
    local desc = H.expand_callable(clue.desc)
    -- - Fall back to possibly already present fields to allow partial
    --   overwrite in later clues. Like to add `postkeys` and inherit `desc`.
    res_data.desc = desc or res_data.desc
    res_data.postkeys = H.replace_termcodes(clue.postkeys) or res_data.postkeys

    res[lhsraw] = res_data
  end

  for _, map_data in ipairs(vim.api.nvim_get_keymap(mode)) do
    local lhsraw = H.replace_termcodes(map_data.lhs)
    local res_data = res[lhsraw] or {}
    res_data.desc = map_data.desc or ''
    res[lhsraw] = res_data
  end

  for _, map_data in ipairs(vim.api.nvim_buf_get_keymap(0, mode)) do
    local lhsraw = H.replace_termcodes(map_data.lhs)
    local res_data = res[lhsraw] or {}
    res_data.desc = map_data.desc or ''
    res[lhsraw] = res_data
  end

  return res
end

H.clues_normalize = function(clues)
  local res = {}
  local process
  process = function(x)
    x = H.expand_callable(x)
    if H.is_clue(x) then return table.insert(res, x) end
    if not H.islist(x) then return nil end
    for _, y in ipairs(x) do
      process(y)
    end
  end

  process(clues)
  return res
end

H.clues_filter = function(clues, query)
  local keys = H.query_to_keys(query)
  for clue_keys, _ in pairs(clues) do
    if not vim.startswith(clue_keys, keys) then clues[clue_keys] = nil end
  end
  return clues
end

H.clues_to_buffer_content = function(clues, keys)
  -- Use translated keys to properly handle cases like `<Del>`, `<End>`, etc.
  keys = H.keytrans(keys)

  -- Gather clue data
  local keys_len = keys:len()
  local keys_pattern = string.format('^%s(.+)$', vim.pesc(keys))

  local next_key_data, next_key_max_width = {}, 0
  for clue_keys, clue_data in pairs(clues) do
    local left, _, rest_keys = H.keytrans(clue_keys):find(keys_pattern)

    -- Add non-trivial next key data only if clue matches current keys plus
    -- something more
    if left ~= nil then
      local next_key = H.clues_get_first_key(rest_keys)

      -- Update description data
      local data = next_key_data[next_key] or {}
      data.n_choices = (data.n_choices or 0) + 1

      -- - Add description directly if it is group clue with description or
      --   a non-group clue
      if next_key == rest_keys then
        data.desc = clue_data.desc or ''
        data.has_postkeys = clue_data.postkeys ~= nil
      end

      next_key_data[next_key] = data

      -- Update width data
      local next_key_width = vim.fn.strchars(next_key)
      data.next_key_width = next_key_width
      next_key_max_width = math.max(next_key_max_width, next_key_width)
    end
  end

  -- Convert to array sorted by keys and finalize content
  local next_keys_extra = vim.tbl_map(
    function(x) return { key = x, keytype = H.clues_get_next_key_type(x) } end,
    vim.tbl_keys(next_key_data)
  )
  table.sort(next_keys_extra, H.clues_compare_next_key)
  local next_keys = vim.tbl_map(function(x) return x.key end, next_keys_extra)

  local res = {}
  for _, key in ipairs(next_keys) do
    local data = next_key_data[key]
    local is_group = data.n_choices > 1
    local desc = data.desc or string.format('+%d choice%s', data.n_choices, is_group and 's' or '')
    local next_key = key .. string.rep(' ', next_key_max_width - data.next_key_width)
    table.insert(res, { next_key = next_key, desc = desc, is_group = is_group, has_postkeys = data.has_postkeys })
  end

  return res
end

H.clues_get_first_key = function(keys)
  -- `keys` are assumed to be translated
  -- Special keys
  local special = keys:match('^(%b<>)')
  if special ~= nil then return special end

  -- <
  if keys:find('^<') ~= nil then return '<' end

  -- Other characters
  return vim.fn.strcharpart(keys, 0, 1)
end

H.clues_get_next_key_type = function(x)
  if x:find('^%w$') ~= nil then return 'alphanum' end
  if x:find('^<.*>$') ~= nil then return 'mod' end
  return 'other'
end

H.clues_compare_next_key = function(a, b)
  local a_type, b_type = a.keytype, b.keytype
  if a_type == b_type then
    local cmp = vim.stricmp(a.key, b.key)
    return cmp == -1 or (cmp == 0 and a.key < b.key)
  end

  if a_type == 'alphanum' then return true end
  if b_type == 'alphanum' then return false end

  if a_type == 'mod' then return true end
  if b_type == 'mod' then return false end
end

-- Clue generators ------------------------------------------------------------
H.make_clues_with_register_contents = function(mode, prefix)
  local make_register_desc = function(register)
    return function()
      local ok, value = pcall(vim.fn.getreg, register, 1)
      if not ok or value == '' then return nil end
      return vim.inspect(value)
    end
  end

  local all_registers = vim.split('0123456789abcdefghijklmnopqrstuvwxyz*+"-:.%/#', '')

  local res = {}
  for _, register in ipairs(all_registers) do
    table.insert(res, { mode = mode, keys = prefix .. register, desc = make_register_desc(register) })
  end
  table.insert(res, { mode = mode, keys = prefix .. '=', desc = 'Result of expression' })

  return res
end

-- Predicates -----------------------------------------------------------------
H.is_trigger = function(x)
  if type(x) ~= table then return false end;
  if type(x.mode) == "string" and type(x.keys) == "string" then
    return true
  else
    if type(x.mode) == "table" then
      for _, v in ipairs(x.mode) do
        if type(v) ~= "string" then return false end
      end
    end
    if type(x.keys) == "table" then
      for _, v in ipairs(x.keys) do
        if type(v) ~= "string" then return false end
      end
    end
  end
  return true
end

H.is_clue = function(x)
  if type(x) ~= 'table' then return false end
  local mandatory = type(x.mode) == 'string' and type(x.keys) == 'string'
  local extra = (x.desc == nil or type(x.desc) == 'string' or vim.is_callable(x.desc))
    and (x.postkeys == nil or type(x.postkeys) == 'string')
  return mandatory and extra
end

H.is_array_of = function(x, predicate)
  if not H.islist(x) then return false end
  for _, v in ipairs(x) do
    if not predicate(v) then return false end
  end
  return true
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.clue) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.set_buf_name = function(buf_id, name) vim.api.nvim_buf_set_name(buf_id, 'miniclue://' .. buf_id .. '/' .. name) end

H.map = function(mode, lhs, rhs, opts)
  if lhs == '' then return end
  opts = vim.tbl_deep_extend('force', { silent = true }, opts or {})
  vim.keymap.set(mode, lhs, rhs, opts)
end

H.replace_termcodes = function(x)
  if x == nil then return nil end
  -- Use `keytrans` prior replacing termcodes to work correctly on already
  -- replaced variant of `<F*>` keys
  return vim.api.nvim_replace_termcodes(H.keytrans(x), true, true, true)
end

H.keytrans = function(x)
  local res = vim.fn.keytrans(x):gsub('<NL>', '<C-J>'):gsub('<S%-NL>', '<C-S-J>'):gsub('<M%-NL>', '<C-M-J>')
  return (res:gsub('<lt>', '<'))
end

H.get_forced_submode = function()
  local mode = vim.fn.mode(1)
  if not mode:sub(1, 2) == 'no' then return '' end
  return mode:sub(3)
end

H.get_default_register = function()
  local clipboard = vim.o.clipboard
  if clipboard:find('unnamedplus') ~= nil then return '+' end
  if clipboard:find('unnamed') ~= nil then return '*' end
  return '"'
end

H.is_valid_buf = function(buf_id) return type(buf_id) == 'number' and vim.api.nvim_buf_is_valid(buf_id) end

H.is_valid_win = function(win_id) return type(win_id) == 'number' and vim.api.nvim_win_is_valid(win_id) end

H.fit_to_width = function(text, width)
  local t_width = vim.fn.strchars(text)
  return t_width <= width and text or ('…' .. vim.fn.strcharpart(text, t_width - width + 1, width - 1))
end

H.expand_callable = function(x, ...)
  if vim.is_callable(x) then return x(...) end
  return x
end

H.redraw_scheduled = vim.schedule_wrap(function() vim.cmd('redraw') end)

H.getcharstr = function()
  -- Ensure redraws still happen
  H.timers.getcharstr:start(0, 50, H.redraw_scheduled)
  local ok, char = pcall(vim.fn.getcharstr)
  H.timers.getcharstr:stop()
  -- Terminate if couldn't get input (like with <C-c>) or it is `<Esc>`
  if not ok or char == '\27' or char == '' then return end
  return H.get_langmap()[char] or char
end

H.get_langmap = function()
  if vim.o.langmap == '' then return {} end

  -- Get langmap parts by splitting at "," not preceded by "\"
  local langmap_parts = vim.fn.split(vim.o.langmap, '[^\\\\]\\zs,')

  -- Process each langmap part
  local res = {}
  for _, part in ipairs(langmap_parts) do
    H.process_langmap_part(res, part)
  end
  return res
end

H.process_langmap_part = function(res, part)
  local semicolon_byte_ind = vim.fn.match(part, '[^\\\\]\\zs;') + 1

  -- Part is without ';', like 'aAbB'
  if semicolon_byte_ind == 0 then
    -- Drop backslash escapes
    part = part:gsub('\\([^\\])', '%1')

    for i = 1, vim.fn.strchars(part), 2 do
      -- `strcharpart()` has 0-based indexes
      local from, to = vim.fn.strcharpart(part, i - 1, 1), vim.fn.strcharpart(part, i, 1)
      if from ~= '' and to ~= '' then res[from] = to end
    end

    return
  end

  -- Part is with ';', like 'ab;AB'
  -- - Drop backslash escape
  local left = part:sub(1, semicolon_byte_ind - 1):gsub('\\([^\\])', '%1')
  local right = part:sub(semicolon_byte_ind + 1):gsub('\\([^\\])', '%1')

  for i = 1, vim.fn.strchars(left) do
    local from, to = vim.fn.strcharpart(left, i - 1, 1), vim.fn.strcharpart(right, i - 1, 1)
    if from ~= '' and to ~= '' then res[from] = to end
  end
end

H.list_concat = function(...)
  local res = {}
  for i = 1, select('#', ...) do
    for _, x in ipairs(select(i, ...) or {}) do
      table.insert(res, x)
    end
  end
  return res
end

-- TODO: Remove after compatibility with Neovim=0.9 is dropped
H.islist = vim.fn.has('nvim-0.10') == 1 and vim.islist or vim.tbl_islist

return MiniClue
