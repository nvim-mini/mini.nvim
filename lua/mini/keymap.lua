--- *mini.keymap* Special key mappings
---
--- MIT License Copyright (c) 2025 Evgeni Chasnovski

--- Features:
---
--- - Map keys to perform configurable multi-step actions: if condition for step
---   one is true - execute step one action, else check step two, and so on until
---   falling back to executing original keys. This is usually referred to as
---   "smart" keys (like "smart tab"). See |MiniKeymap.map_multistep()|.
---
---   There are many built-in steps targeted for Insert mode mappings of special
---   keys like <Tab>, <S-Tab>, <CR>, and <BS>:
---   - Navigate and accept |popupmenu-completion|. Useful for |mini.completion|.
---   - Navigate and expand |mini.snippets|.
---   - Execute <CR> and <BS> respecting |mini.pairs|.
---   - Jump before/after current tree-sitter node.
---   - Jump before opening and after closing characters (brackets and quotes).
---   - Increase/decrease indent when cursor is inside of it.
---   - Delete all whitespace to the left ("hungry backspace").
---   - Navigate |vim.snippet|.
---   - Navigate and accept in [hrsh7th/nvim-cmp](https://github.com/hrsh7th/nvim-cmp) completion.
---   - Navigate and accept in [Saghen/blink.cmp](https://github.com/Saghen/blink.cmp) completion.
---   - Navigate and expand [L3MON4D3/LuaSnip](https://github.com/L3MON4D3/LuaSnip) snippets.
---   - Execute <CR> and <BS> respecting [windwp/nvim-autopairs](https://github.com/windwp/nvim-autopairs).
---
--- - Map keys as "combo": each key acts immediately plus execute extra action if
---   all are typed within configurable delay between each other.
---   See |MiniKeymap.map_combo()|. Some of the common use cases include:
---     - Map insertable keys (like "jk", "kj") in Insert and Command-line mode
---       to exit into Normal mode.
---     - Fight against bad habits of pressing the same navigation key by showing
---       a notification if there are too many of them pressed in a row.
---
--- Sources with more details:
--- - |MiniKeymap-examples|
---
--- # Setup ~
---
--- This module doesn't need setup, but it can be done to improve usability.
--- Setup with `require('mini.keymap').setup({})` (replace `{}` with your `config`
--- table). It will create global Lua table `MiniKeymap` which you can use for
--- scripting or manually (with `:lua MiniKeymap.*`).
---
--- See |MiniKeymap.config| for `config` structure and default values.
---
--- This module doesn't have runtime options, so using `vim.b.minikeymap_config`
--- will have no effect here.
---
--- # Comparisons ~
---
--- - [max397574/better-escape.nvim](https://github.com/max397574/better-escape.nvim):
---     - Mostly similar to |MiniKeymap.map_combo()| with a different approach
---       to creating mappings.
---     - Mostly targeted for Insert mode mappings as pressed keys get removed
---       automatically after typed. This module allows more general cases while
---       requiring explicit removal of keys (usually via explicit `<BS><BS>`).
---
--- - [abecodes/tabout.nvim](https://github.com/abecodes/tabout.nvim):
---     - Similar general idea as in `'jump_{after,before}_tsnode'` steps
---       of |MiniKeymap.map_multistep()|.
---     - Works only with enabled tree-sitter parser. This module provides
---       fallback via 'jump_after_close' and 'jump_before_open' that work
---       without tree-sitter parser.
---     - 'tabout.nvim' has finer control of how the tree-sitter node movement
---       is done, while this module has "jump outside of current node" behavior.
---
--- # Disabling ~
---
--- To disable acting in mappings, set `vim.g.minikeymap_disable` (globally) or
--- `vim.b.minikeymap_disable` (for a buffer) to `true`. Considering high number
--- of different scenarios and customization intentions, writing exact rules
--- for disabling module's functionality is left to user.
--- See |mini.nvim-disabling-recipes| for common recipes.
---@tag MiniKeymap

--- # Multi-step ~
---
--- See |MiniKeymap.map_multistep()| for a general description of how multi-step
--- mappings work and what built-in steps are available.
---
--- Setup that works well with |mini.completion| and |mini.pairs|: >lua
---
---   local map_multistep = require('mini.keymap').map_multistep
---   map_multistep('i', '<Tab>',   { 'pmenu_next' })
---   map_multistep('i', '<S-Tab>', { 'pmenu_prev' })
---   map_multistep('i', '<CR>',    { 'pmenu_accept', 'minipairs_cr' })
---   map_multistep('i', '<BS>',    { 'minipairs_bs' })
--- <
--- Use <Tab> / <S-Tab> to also navigate and expand |mini.snippets|: >lua
---
---   local map_multistep = require('mini.keymap').map_multistep
---
---   local tab_steps = { 'minisnippets_next','minisnippets_expand','pmenu_next' }
---   map_multistep('i', '<Tab>', tab_steps)
---
---   local shifttab_steps = { 'minisnippets_prev', 'pmenu_prev' }
---   map_multistep('i', '<S-Tab>', shifttab_steps)
--- <
--- An extra smart <Tab> and <S-Tab>: >lua
---
---   local map_multistep = require('mini.keymap').map_multistep
---
---   -- NOTE: this will never insert tab, press <C-v><Tab> for that
---   local tab_steps = {
---     'minisnippets_next', 'minisnippets_expand', 'pmenu_next',
---     'jump_after_tsnode', 'jump_after_close',
---   }
---   map_multistep('i', '<Tab>', tab_steps)
---
---   local shifttab_steps = {
---     'minisnippets_prev',  'pmenu_prev',
---     'jump_before_tsnode', 'jump_before_open',
---   }
---   map_multistep('i', '<S-Tab>', shifttab_steps)
--- <
--- Navigation in active |vim.snippet| session also requires mapping in |Select-mode|: >lua
---
---   local map_multistep = require('mini.keymap').map_multistep
---   map_multistep({ 'i', 's' }, '<Tab>',   { 'vimsnippet_next', 'pmenu_next' })
---   map_multistep({ 'i', 's' }, '<S-Tab>', { 'vimsnippet_prev', 'pmenu_prev' })
--- <
--- # Combos ~
---
--- See |MiniKeymap.map_combo()| for a general description of what is a combo and
--- more caveats about its usage.
---
--- All combos require their left hand side keys to be typed relatively quickly.
--- To adjust the delay between keys, add `{ delay = 500 }` (use custom value) as
--- fourth argument.
---
--- ## "Better escape" to Normal mode ~
---
--- Leave into |Normal-mode| without having to reach for <Esc> key: >lua
---
---   -- Support most common modes. This can also contain 't', but would
---   -- only mean to press `<Esc>` inside terminal.
---   local mode = { 'i', 'c', 'x', 's' }
---   require('mini.keymap').map_combo(mode, 'jk', '<BS><BS><Esc>')
---
---   -- To not have to worry about the order of keys, also map "kj"
---   require('mini.keymap').map_combo(mode, 'kj', '<BS><BS><Esc>')
---
---   -- Escape into Normal mode from Terminal mode
---   require('mini.keymap').map_combo('t', 'jk', '<BS><BS><C-\\><C-n>')
---   require('mini.keymap').map_combo('t', 'kj', '<BS><BS><C-\\><C-n>')
--- <
--- ## Show bad navigation habits ~
---
--- Show notification if there is too much movement by repeating same key: >lua
---
---   local notify_many_keys = function(key)
---     local lhs = string.rep(key, 5)
---     local action = function() vim.notify('Too many ' .. key) end
---     require('mini.keymap').map_combo({ 'n', 'x' }, lhs, action)
---   end
---   notify_many_keys('h')
---   notify_many_keys('j')
---   notify_many_keys('k')
---   notify_many_keys('l')
--- <
--- ## Fix previous spelling mistake ~
---
--- Fix previous spelling mistake (see |[s| and |z=|) without manually leaving
--- Insert mode: >lua
---
---   local action = '<BS><BS><Esc>[s1z=gi<Right>'
---   require('mini.keymap').map_combo('i', 'kk', action)
--- <
--- ## Hide search highlighting ~
---
--- Use double <Esc><Esc> to execute |:nohlsearch|. Although this can also be done
--- with `nmap <Esc> <Cmd>nohl<CR>`, the combo approach also exists and can be used
--- to free <Esc> mapping in Normal mode for something else. >lua
---
---   local action = function() vim.cmd('nohlsearch') end
---   require('mini.keymap').map_combo({ 'n','i','x','c' }, '<Esc><Esc>', action)
--- <
--- ## Buffer navigation ~
---
--- Replace some movements with easier to type alternatives: >lua
---
---   local map_combo = require('mini.keymap').map_combo
---   map_combo({ 'n', 'x' }, 'll', 'g$')
---   map_combo({ 'n', 'x' }, 'hh', 'g^')
---   map_combo({ 'n', 'x' }, 'jj', '}')
---   map_combo({ 'n', 'x' }, 'kk', '{')
--- <
---@tag MiniKeymap-examples

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local

-- Module definition ==========================================================
local MiniKeymap = {}
local H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniKeymap.config|.
---
---@usage >lua
---   require('mini.keymap').setup({}) -- replace {} with your config table
---                                    -- needs `keymap` field present
--- <
MiniKeymap.setup = function(config)
  -- Export module
  _G.MiniKeymap = MiniKeymap

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)
end

--- Defaults ~
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
MiniKeymap.config = {}
--minidoc_afterlines_end

--- Map multi-step action
---
--- Mapping of a multi-step action is an expression mapping (|:map-expression|).
--- Executing a multi-step action is essentially:
--- - Check condition for step one. If `true` - execute step one action and stop.
--- - Check condition for step two, and so on.
--- - If there is no more steps, fall back to returning mapped key.
---
--- For better user experience there are many built-in steps mostly designed
--- to create Insert mode "smart" mappings of <Tab>, <S-Tab>, <CR>, and <BS>.
--- Available built-in steps ("For key" is a suggestion, any can be used):
--- >
---  ┌─────────────────────┬────────────────┬──────────────────────────┬─────────┐
---  │      Step name      │   Condition    │          Action          │ For key │
---  ├─────────────────────┴────────────────┴──────────────────────────┴─────────┤
---  ├┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈ |ins-completion-menu| ┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┤
---  │ pmenu_next          │ Pmenu visible  │ Select next (as <C-n>)   │ <Tab>   │
---  │ pmenu_prev          │ Pmenu visible  │ Select prev (as <C-p>)   │ <S-Tab> │
---  │ pmenu_accept        │ Item selected  │ Accept (as <C-y>)        │ <CR>    │
---  ├┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈ |mini.snippets| ┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┤
---  │ minisnippets_next   │ Session active │ Jump to next tabstop     │ <Tab>   │
---  │ minisnippets_prev   │ Session active │ Jump to prev tabstop     │ <S-Tab> │
---  │ minisnippets_expand │ Can expand     │ Expand snippet at cursor │ <Tab>   │
---  ├┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈ |mini.pairs| ┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┤
---  │ minipairs_cr        │ Module set up  │ <CR> respecting pairs    │ <CR>    │
---  │ minipairs_bs        │ Module set up  │ <BS> respecting pairs    │ <BS>    │
---  ├┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈ Jump around in Insert mode ┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┤
---  │ jump_after_tsnode   │ TS parser      │ Jump after node end      │ <Tab>   │
---  │ jump_before_tsnode  │ TS parser      │ Jump before node start   │ <S-Tab> │
---  │ jump_after_close    │ Insert mode    │ Jump after  )]}"'`       │ <Tab>   │
---  │ jump_before_open    │ Insert mode    │ Jump before ([{"'`       │ <S-Tab> │
---  ├┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈ Work with whitespace ┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┤
---  │ increase_indent     │ Is on indent   │ Increase indent          │ <Tab>   │
---  │ decrease_indent     │ Is on indent   │ Decrease indent          │ <S-Tab> │
---  │ hungry_bs           │ Space to left  │ Delete all space to left │ <BS>    │
---  ├┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈ |vim.snippet| ┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┤
---  │ vimsnippet_next     │ Session active │ Jump to next tabstop     │ <Tab>   │
---  │ vimsnippet_prev     │ Session active │ Jump to prev tabstop     │ <S-Tab> │
---  ├┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈ 'hrsh7th/nvim-cmp' ┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┤
---  │ cmp_next            │ Menu visible   │ Select next item         │ <Tab>   │
---  │ cmp_prev            │ Menu visible   │ Select prev item         │ <S-Tab> │
---  │ cmp_accept          │ Item selected  │ Accept selected item     │ <CR>    │
---  ├┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈ 'Saghen/blink.cmp' ┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┤
---  │ blink_next          │ Menu visible   │ Select next item         │ <Tab>   │
---  │ blink_prev          │ Menu visible   │ Select prev item         │ <S-Tab> │
---  │ blink_accept        │ Item selected  │ Accept selected item     │ <CR>    │
---  ├┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈ 'L3MON4D3/LuaSnip' ┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┤
---  │ luasnip_next        │ Session active │ Jump to next tabstop     │ <Tab>   │
---  │ luasnip_prev        │ Session active │ Jump to prev tabstop     │ <S-Tab> │
---  │ luasnip_expand      │ Can expand     │ Expand snippet at cursor │ <Tab>   │
---  ├┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈ 'windwp/nvim-autopairs' ┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┤
---  │ nvimautopairs_cr    │ Module present │ <CR> respecting pairs    │ <CR>    │
---  │ nvimautopairs_bs    │ Module present │ <BS> respecting pairs    │ <BS>    │
---  └─────────────────────┴────────────────┴──────────────────────────┴─────────┘
--- <
--- Notes:
--- - Executing action has limitations of |:map-expression| (like not allowed text
---   or buffer changes, etc.). To execute complex lua code, use |vim.schedule()|
---   inside action, return the code as string in |:map-cmd| format, or return
---   a function to be later executed. See usage examples.
---
--- - Some mapped keys (like <Tab>, <CR>) might require disabling smart presets
---   in plugins (like 'nvim-cmp', 'blink-cmp', 'nvim-autopairs').
---
---@param mode string|table Same as for |vim.keymap.set()|.
---@param lhs string Same as for |vim.keymap.set()|.
---@param steps table Array of steps. Each step can be a string with the name
---   of built-in step or a table with two callable methods (will be called
---   without arguments):
---   - <condition> - return `true` if the action should be executed.
---   - <action> - action to be executed if <condition> returns `true`.
---     For more flexibility, it can also return a value which can be:
---       - String - will be returned as expression output. Can be something like
---         `"<Tab>"` (treat as <Tab> key) or `"<Cmd>lua vim.notify('Hello')<CR>"`.
---         Should not escape keycodes (i.e. return "<Tab>" and not "\t").
---         To undo already done escape, use |keytrans()|.
---       - Function - will be executed as if `"<Cmd>lua f()<CR>"`, but does not
---         need to create a global function for that.
---       - `false` - do not stop going through steps.
---@param opts table|nil Same as for |vim.keymap.set()|.
---
---@usage See |MiniKeymap-examples| for practical examples.
---
--- Some illustrative examples: >lua
---
---   _G.log = {}
---   local steps = {}
---   steps[1] = {
---     condition = function() table.insert(_G.log, 'C1'); return _G.cond1 end,
---     -- Compute and return keys. Will be emulated as pressed.
---     action = function() table.insert(_G.log, 'A1'); return 'hello' end,
---   }
---
---   steps[2] = {
---     condition = function() table.insert(_G.log, 'C2'); return _G.cond2 end,
---     -- Perform action immediately, return `false` to keep asking other steps
---     action = function() table.insert(_G.log, 'A2'); return false end,
---   }
---
---   steps[3] = {
---     condition = function() table.insert(_G.log, 'C3'); return _G.cond3 end,
---     -- Perform action later (to overcom expression mapping limitations)
---     action = function()
---       table.insert(_G.log, 'A3_1')
---       return function() table.insert(_G.log, 'A3_2') end
---     end,
---   }
---
---   -- Make Insert mode <Tab> mapping
---   require('mini.keymap').map_multistep('i', '<Tab>', steps)
---
---   -- Pressing <Tab> inserts fallback `\t`; logs C1+C2+C3
---   _G.cond1, _G.cond2, _G.cond3 = false, false, false
---
---   -- Pressing <Tab> inserts `hello`; logs C1+A1
---   _G.cond1, _G.cond2, _G.cond3 = true, false, false
---
---   -- Pressing <Tab> inserts nothing; logs C1+C2+A2+C3+A3_1+A3_2
---   _G.cond1, _G.cond2, _G.cond3 = false, true, true
--- <
MiniKeymap.map_multistep = function(mode, lhs, steps, opts)
  H.check_type('lhs', lhs, 'string')
  local lhs_raw, n_steps = vim.api.nvim_replace_termcodes(lhs, true, true, true), #steps
  local lhs_keycode = vim.fn.keytrans(lhs_raw)
  steps = H.normalize_steps(steps)

  local rhs = function()
    if H.is_disabled() then return lhs_keycode end
    for i = 1, n_steps do
      if steps[i].condition() then
        local out = steps[i].action()
        -- Allow custom string as output of expression mapping
        if type(out) == 'string' then return out end
        -- Allow callable output to be properly wrapped in `<Cmd>...<CR>`
        if vim.is_callable(out) then return H.wrap_in_cmd_lua(out) end
        -- Allow `false` output to indicate "keep processing next steps"
        if out ~= false then return '' end
      end
    end
    return lhs_keycode
  end

  local desc = 'Multi ' .. lhs_keycode
  opts = vim.tbl_extend('force', { desc = desc }, opts or {}, { expr = true, replace_keycodes = true })
  vim.keymap.set(mode, lhs, rhs, opts)
end

--- Generate step for multi-step mappings
---
--- This is a table with function elements. Call to actually get a step.
MiniKeymap.gen_step = {}

--- Search pattern step
---
--- Use |search()| to jump to pattern match. Possibly adjust final position to
--- be just to the right of the match (useful in Insert mode).
---
---@param pattern string Same as for |search()|.
---@param flags string|nil Same as for |search()|.
---@param opts table|nil Options. Possible fields:
---   - <side> `(string)` - one of `"before"` (default) or `"after"`.
---   - <stopline> `(number|function)` - forwarded to |search()| (as number or
---     as function's output after calling it before every search).
---   - <timeout> `(number)` - forwarded to |search()|.
---   - <skip> `(string|function)` - forwarded to |search()|.
---
---@return table Step which searches pattern.
---
---@usage Built-in |MiniKeymap.map_multistep()| steps "jump_after_close" and
--- "jump_before_open" use this, but only in Insert mode.
---
--- Steps that jump before/after all consecutive brackets in several modes: >lua
---
---   local keymap = require('mini.keymap')
---   local tab_step_insert = keymap.gen_step.search_pattern(
---     -- Need to use 'c' flag and 'after' side for robust "chaining"
---     [=[[)\]}]\+]=], 'ceW', { side = 'after' }
---   )
---   keymap.map_multistep('i', '<Tab>', { tab_step_insert })
---   local tab_step = keymap.gen_step.search_pattern([=[[)\]}]\+]=], 'eW')
---   keymap.map_multistep({ 'n', 'x' }, '<Tab>', { tab_step })
---
---   local stab_step = keymap.gen_step.search_pattern([=[[(\[{]\+]=], 'bW')
---   keymap.map_multistep({ 'i', 'n', 'x' }, '<S-Tab>', { stab_step })
--- <
MiniKeymap.gen_step.search_pattern = function(pattern, flags, opts)
  if type(pattern) ~= 'string' then H.error('`pattern` should be string, not ' .. vim.inspect(type(pattern))) end
  flags = flags or ''
  if type(flags) ~= 'string' then H.error('`flags` should be string, not ' .. vim.inspect(type(flags))) end

  opts = vim.tbl_extend('force', { side = 'before', stopline = nil, timeout = nil, skip = nil }, opts or {})
  local side = opts.side
  if not (side == 'before' or side == 'after') then H.error('`opts.side` should be one of "before" or "after"') end

  local stopline = opts.stopline or function() return nil end
  if type(stopline) == 'number' then
    local line = stopline
    stopline = function() return line end
  end
  if not vim.is_callable(stopline) then H.error('`opts.stopline` should be number or callable') end

  -- NOTEs:
  -- - Using `normal!` doesn't go past the end of line and triggers
  --   mode-change-related events.
  -- - Adjusting pattern with `\zs` prefix doesn't work for consecutive matches
  --   (like `)))`), as it will match every other one (first, third, etc.).
  -- - Using `\@<=` quantifier doesn't work for the last match in consecutive
  --   matches at end of line. Like `)))` at end of line won't put cursor at
  --   end of line. The `[)\]}]\@<=\_.` also doesn't seem to work.
  local adjust_cursor = function()
    local pos = vim.api.nvim_win_get_cursor(0)
    vim.api.nvim_win_set_cursor(0, { pos[1], pos[2] + 1 })
  end
  if side == 'before' then adjust_cursor = function() end end

  local act = function()
    H.hide_completion()
    local had_match = vim.fn.search(pattern, flags, stopline(), opts.timeout, opts.skip)
    if had_match ~= 0 then adjust_cursor() end
  end

  return { condition = function() return true end, action = function() return act end }
end

--- Map combo post action
---
--- Create a combo: sequence of keys where each acts immediately plus execute
--- an extra action if all are typed within configurable delay between each other.
---
--- Example for Insert mode "better escape" `jk` combo with `<BS><BS><Esc>` action:
--- - Press `j`. It is visible immediately without any side effects.
--- - Quickly (no more than default 200 ms after) press `k`. This triggers the
---   action which is equivalent to typing <BS><BS> (delete already present `jk`)
---   and <Esc> to exit into Normal mode.
---
--- Notes:
--- - IMPORTANT! Combo is not a regular mapping but a separate key tracking
---   with |vim.on_key()|. This is important as combos will not be visible and
---   can not be managed as regular mappings. Instead each combo is associated
---   with a dedicated |namespace| (named for human readability). However, it is not
---   really expected to manage them on the fly after they are created.
---
--- - String action is executed with |nvim_input()|, i.e. emulated keys will
---   respect custom mappings.
---
--- - Different combos are tracked and act independent of each other. For example,
---   if there are combos for `jjk` and `jk` keys, fast typing `jjk` will execute both.
---
--- - Neovim>=0.11 is recommended due to |vim.on_key()| improvement to allow
---   watching for keys as they are typed and not as if coming from mappings.
---   For example, this matters when creating a `jk` combo for Visual mode while
---   also having `xnoremap j gj` style of remaps. On Neovim<0.11 the fix is to
---   use `gjgk` as combo's left hand side.
---
--- - Each combo adds very small but non-zero overhead on each keystroke.
---   Usually about 1-3 microseconds (i.e. 0.001-0.003 ms), which should be
---   fast enough for most setups. For a "normal, real world" coding session
---   with a total of ~20000 keystrokes it results in extra ~40ms of overhead
---   for a single created combo. Create many combos with caution.
---
---@param mode string|table String or array of string mode id (like "n", "i", etc.).
---   Array of several modes is more performant than several single mode combos.
---@param lhs string|table String with tracked key sequence or an array of
---   tracked keys (one element - one key).
---@param action string|function Action to perform after key sequence is detected.
---   If string, treated as keys and emulated with |nvim_input()|.
---   If function, executed in |vim.schedule()|. Can return string keys which will
---   be emulated.
---@param opts table|nil Options. Possible fields:
---   - <delay> `(number)` - delay in milliseconds within which keys should be
---     pressed to detect a key sequence. Default: 200.
---
---@usage See |MiniKeymap-examples| for practical examples.
---
--- Some illustrative examples: >lua
---
---   local map_combo = require('mini.keymap').map_combo
---
---   -- In Insert mode pressing `x` followed by `x` within 1 second logs 'A'
---   -- and emulates extra pressing of `yy`
---   _G.log = {}
---   local action = function() table.insert(_G.log, 'A'); return 'yy' end
---   map_combo('i', 'xx', action, { delay = 1000 })
--- <
MiniKeymap.map_combo = function(mode, lhs, action, opts)
  if type(mode) == 'string' then mode = { mode } end
  if not H.is_array_of(mode, H.is_string) then H.error('`mode` should be string or array of strings') end
  local mode_tbl = H.combo_make_mode_tbl(mode)

  local seq = H.combo_lhs_to_seq(lhs)
  seq = vim.tbl_map(function(x) return vim.api.nvim_replace_termcodes(x, true, true, true) end, seq)

  if not (type(action) == 'string' or vim.is_callable(action)) then
    H.error('`action` should be either string of keys or callable')
  end

  -- Cache local values for better speed
  opts = opts or {}
  local delay = opts.delay or 200
  if not (type(delay) == 'number' and delay > 0) then H.error('`opts.delay` should be a positive number') end

  local hrtime, get_key = vim.uv.hrtime, H.combo_get_key
  local i, last_time, n_seq = 0, hrtime(), #seq
  local delay_ns = 1000000 * delay
  -- NOTE: It is possible to track mode in 'ModeChanged' event and use it for
  -- all combos (instead of `get_mode()` for each). Although it scales well
  -- (O(1) instead of O(n) by number of combos), it can fail when something is
  -- executed with 'eventignore' blocking 'ModeChanged' event (can happen with
  -- plugins). Median `get_mode()` execution time is 0.15 microseconds and it
  -- gets executed on every keystroke. If it proves to be too much, can be
  -- reverted to 'ModeChanged' approach.
  local get_mode = vim.fn.mode

  -- Explicitly ignore keys from action. Otherwise they will be processed
  -- because `nvim_input` mocks "as if typed" approach.
  local input_keys = vim.schedule_wrap(function(keys)
    H.combo_ignore = true
    vim.api.nvim_input(keys)
    -- NOTE: Can't unignore right away because `nvim_input` is executed later
    H.combo_unignore_later()
  end)

  if type(action) == 'string' then
    local keys = action
    action = function() input_keys(keys) end
  end
  local act = vim.schedule_wrap(function()
    if H.is_disabled() then return end
    -- Allow action to return keys to manually mimic
    local keys = action()
    if type(keys) == 'string' and keys ~= '' then input_keys(keys) end
  end)
  local reset = function(key)
    -- Make latest key start new combo, like for 'jjk' or j-wait-jj for 'jj'
    i = seq[1] == key and 1 or 0
    last_time = i == 0 and last_time or hrtime()
  end

  local watcher = function(key, typed)
    -- Use only keys "as if typed" and in proper mode
    key = get_key(key, typed)
    if key == '' or (i == 0 and not mode_tbl[get_mode()]) or H.combo_ignore then return end

    -- Advance tracking and reset if not in sequence
    i = i + 1
    if seq[i] ~= key then return reset(key) end

    -- Reset if time between key presses is too big
    local cur_time = hrtime()
    if (cur_time - last_time) > delay_ns and i > 1 then return reset(key) end
    last_time = cur_time

    -- Wait for more info if sequence is not exhausted, act otherwise
    if i < n_seq then return end
    i = 0
    act()
  end

  local combo_keys = table.concat(vim.tbl_map(vim.fn.keytrans, seq), '')
  local ns_name = string.format('MiniKeymap-combo-%s-%s-%s', #H.ns_id_combo, table.concat(mode, ''), combo_keys)
  local ns_id = vim.api.nvim_create_namespace(ns_name)
  table.insert(H.ns_id_combo, ns_id)

  return vim.on_key(watcher, ns_id)
end

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniKeymap.config)

-- Namespaces for `on_key`
H.ns_id_combo = {}

-- Current mode used in "combo" mappings, for better speed
H.cur_mode = 'n'

-- Whether to ignore current keys as part of the combo. Needs to be global for
-- combo's RHS keys not interfering with tracking of other combos.
H.combo_ignore = false

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})
  return config
end

H.apply_config = function(config) MiniKeymap.config = config end

H.is_disabled = function() return vim.g.minikeymap_disable == true or vim.b.minikeymap_disable == true end

-- Combo ----------------------------------------------------------------------
H.combo_lhs_to_seq = function(lhs)
  if H.is_array_of(lhs, H.is_string) then return vim.deepcopy(lhs) end
  if type(lhs) ~= 'string' then H.error('`lhs` should be string or array of strings') end

  local res, i = {}, 1
  while i <= lhs:len() do
    local k, new_i = string.match(lhs, '^(%b<>)()', i)
    if k == nil or k:find('^.+<') ~= nil then
      k, new_i = vim.fn.strcharpart(lhs, i - 1, 1), i + 1
    end
    table.insert(res, k)
    i = new_i
  end
  return res
end

H.combo_make_mode_tbl = function(mode)
  local res = {}
  for _, m in ipairs(mode) do
    if m == 'x' then
      res.v, res.V, res['\22'] = true, true, true
    elseif m == 'v' then
      res.s, res.v, res.V, res['\22'] = true, true, true, true
    else
      res[m] = true
    end
  end
  return res
end

H.combo_unignore_later = vim.schedule_wrap(function() H.combo_ignore = false end)

H.combo_get_key = function(_, typed) return typed end
if vim.fn.has('nvim-0.11') == 0 then H.combo_get_key = function(key) return key end end

-- Multi-step -----------------------------------------------------------------
H.normalize_steps = function(steps)
  if not H.islist(steps) then H.error('`steps` should be array') end
  local res = {}
  for i, step in ipairs(steps) do
    local s = type(step) == 'string' and H.steps_builtin[step] or step
    local is_step = type(s) == 'table' and vim.is_callable(s.condition) and vim.is_callable(s.action)
    if not is_step then H.error('`steps` should contain valid steps, not ' .. vim.inspect(step)) end
    table.insert(res, s)
  end

  return res
end

H.wrap_in_cmd_lua = function(f)
  local needs_global_cleanup = _G.MiniKeymap == nil
  _G.MiniKeymap = _G.MiniKeymap or {}
  _G.MiniKeymap._f = f
  local extra_cleanup = needs_global_cleanup and '; MiniKeymap = nil' or ''
  return '<Cmd>lua MiniKeymap._f(); MiniKeymap._f = nil' .. extra_cleanup .. '<CR>'
end

H.make_cmd_lua_action = function(cmd_string)
  return function() return '<Cmd>lua ' .. cmd_string .. '<CR>' end
end

H.has_module = function(name) return (pcall(require, name)) end

--stylua: ignore start
H.steps_builtin = {}

H.is_visible_pmenu  = function() return vim.fn.pumvisible() == 1 end
H.is_selected_pmenu = function() return vim.fn.complete_info({ 'selected' }).selected ~= -1 end

H.steps_builtin.pmenu_next   = { condition = H.is_visible_pmenu,  action = function() return '<C-n>' end }
H.steps_builtin.pmenu_prev   = { condition = H.is_visible_pmenu,  action = function() return '<C-p>' end }
H.steps_builtin.pmenu_accept = { condition = H.is_selected_pmenu, action = function() return '<C-y>' end }

H.is_minisnippets_session  = function() return _G.MiniSnippets ~= nil and _G.MiniSnippets.session.get() ~= nil end
H.is_minisnippets_matched  = function() return _G.MiniSnippets ~= nil and #_G.MiniSnippets.expand({ insert = false }) > 0 end
H.make_minisnippets_action = function(dir) return H.make_cmd_lua_action('MiniSnippets.session.jump("' .. dir .. '")') end

H.steps_builtin.minisnippets_next   = { condition = H.is_minisnippets_session, action = H.make_minisnippets_action('next') }
H.steps_builtin.minisnippets_prev   = { condition = H.is_minisnippets_session, action = H.make_minisnippets_action('prev') }
H.steps_builtin.minisnippets_expand = { condition = H.is_minisnippets_matched, action = H.make_cmd_lua_action('MiniSnippets.expand()') }

H.has_minipairs = function() return _G.MiniPairs ~= nil end

H.steps_builtin.minipairs_cr = { condition = H.has_minipairs, action = function() return vim.fn.keytrans(_G.MiniPairs.cr()) end }
H.steps_builtin.minipairs_bs = { condition = H.has_minipairs, action = function() return vim.fn.keytrans(_G.MiniPairs.bs()) end }

H.can_jump_tsnode = function()
  -- TODO: Remove `opts.error` after compatibility with Neovim=0.11 is dropped
  local has_parser, parser = pcall(vim.treesitter.get_parser, 0, nil, { error = false })
  return has_parser and parser ~= nil
end

H.make_jump_tsnode = function(side)
  local act = function()
    local node, pos, new_pos = H.get_tsnode(), vim.api.nvim_win_get_cursor(0), nil
    while node ~= nil do
      -- Output of `get_node_range` is 0-indexed with "from" data inclusive and
      -- "to" data exclusive. This is exactly what is needed here:
      -- - For "before" direction exact left end is needed. This will be used
      --   in Insert mode and cursor will be between target and its left cell.
      -- - For "after" direction the one cell to right (after normalization) is
      --   needed because cursor in Insert mode will be just after the node.
      local from_row, from_col, to_row, to_col = vim.treesitter.get_node_range(node)
      local row = side == 'before' and from_row or to_row
      local col = side == 'before' and from_col or to_col
      new_pos = H.normalize_pos(row, col)
      -- Iterate up the tree until different position is found. This is useful
      -- for "before" direction and non-Insert mode.
      if not (new_pos[1] == pos[1] and new_pos[2] == pos[2]) then
        H.hide_completion()
        pcall(vim.api.nvim_win_set_cursor, 0, new_pos)
        new_pos = vim.api.nvim_win_get_cursor(0)
      end
      if not (new_pos[1] == pos[1] and new_pos[2] == pos[2]) then break end
      node = node:parent()
    end
  end

  -- Return callable which is wrapped to be executed after expression mapping
  return function() return act end
end

H.steps_builtin.jump_after_tsnode  = { condition = H.can_jump_tsnode, action = H.make_jump_tsnode('after') }
H.steps_builtin.jump_before_tsnode = { condition = H.can_jump_tsnode, action = H.make_jump_tsnode('before') }

H.steps_builtin.jump_after_close = {
  condition = function() return vim.fn.mode() == 'i' end,
  -- NOTE: In Insert mode 'c' flag (accept at cursor) with 'after' adjust are
  -- needed for working "chaining". In other modes it is no flag and no adjust,
  -- which is why these steps only work in Insert mode.
  action = MiniKeymap.gen_step.search_pattern([=[[)\]}"'`]]=], 'cW', { side = 'after' }).action,
}
H.steps_builtin.jump_before_open = {
  condition = function() return vim.fn.mode() == 'i' end,
  action = MiniKeymap.gen_step.search_pattern([=[[(\[{"'`]]=], 'bW', { side = 'before' }).action,
}

H.is_in_indent = function()
  local line, col = vim.api.nvim_get_current_line(), vim.fn.col('.')
  local offset = vim.fn.mode() == 'i' and 1 or 0
  return line:sub(1, col - offset):find('^%s*$') ~= nil
end

H.increase_indent_keys = { i = '<C-t>', v = '>', V = '>', ['\22'] = '>' }
H.decrease_indent_keys = { i = '<C-d>', v = '<', V = '<', ['\22'] = '<' }

H.steps_builtin.increase_indent = { condition = H.is_in_indent, action = function() return H.increase_indent_keys[vim.fn.mode()] or '>>' end }
H.steps_builtin.decrease_indent = { condition = H.is_in_indent, action = function() return H.decrease_indent_keys[vim.fn.mode()] or '<<' end }

H.hungry_bs_condition = function()
  local line, col = vim.api.nvim_get_current_line(), vim.fn.col('.')
  local offset = vim.fn.mode() == 'i' and 1 or 0
  return line:sub(1, col - offset):find('%s+$') ~= nil
end

H.hungry_bs_action = function()
  return function()
    local line, lnum, col = vim.api.nvim_get_current_line(), vim.fn.line('.'), vim.fn.col('.')
    local offset = vim.fn.mode() == 'i' and 1 or 0
    local from_col = line:sub(1, col - offset):match('()%s+$')
    vim.api.nvim_buf_set_text(0, lnum - 1, from_col - 1, lnum - 1, col - offset, {})
    vim.api.nvim_win_set_cursor(0, { lnum, from_col - 1 })
  end
end

H.steps_builtin.hungry_bs = { condition = H.hungry_bs_condition, action = H.hungry_bs_action }

H.make_vimsnippet_condition = function(dir) return function() return vim.snippet.active({ direction = dir }) end end
H.make_vimsnippet_action    = function(dir) return H.make_cmd_lua_action('vim.snippet.jump(' .. dir .. ')') end

H.steps_builtin.vimsnippet_next = { condition = H.make_vimsnippet_condition(1),  action = H.make_vimsnippet_action(1) }
H.steps_builtin.vimsnippet_prev = { condition = H.make_vimsnippet_condition(-1), action = H.make_vimsnippet_action(-1) }

H.is_visible_cmp  = function() return H.has_module('cmp') and require('cmp').visible() end
H.is_selected_cmp = function() return H.has_module('cmp') and require('cmp').get_selected_entry() ~= nil end
H.make_cmp_action = function(action) return H.make_cmd_lua_action('require("cmp").' .. action .. '()') end

H.steps_builtin.cmp_next   = { condition = H.is_visible_cmp,  action = H.make_cmp_action('select_next_item') }
H.steps_builtin.cmp_prev   = { condition = H.is_visible_cmp,  action = H.make_cmp_action('select_prev_item') }
H.steps_builtin.cmp_accept = { condition = H.is_selected_cmp, action = H.make_cmp_action('confirm') }

H.is_visible_blink  = function() return H.has_module('blink.cmp') and require('blink.cmp').is_menu_visible() end
H.is_selected_blink = function() return H.is_visible_blink() and require('blink.cmp').get_selected_item() ~= nil end
H.make_blink_action = function(action) return H.make_cmd_lua_action('require("blink.cmp").' .. action .. '()') end

H.steps_builtin.blink_next   = { condition = H.is_visible_blink,  action = H.make_blink_action('select_next') }
H.steps_builtin.blink_prev   = { condition = H.is_visible_blink,  action = H.make_blink_action('select_prev') }
H.steps_builtin.blink_accept = { condition = H.is_selected_blink, action = H.make_blink_action('accept') }

H.make_luasnip_condition = function(dir) return function() return H.has_module('luasnip') and require('luasnip').jumpable(dir) end end
H.is_luasnip_expandable  = function() return H.has_module('luasnip') and require('luasnip').expandable() end
H.make_luasnip_action    = function(dir) return H.make_cmd_lua_action('require("luasnip").jump(' .. dir .. ')') end

H.steps_builtin.luasnip_next   = { condition = H.make_luasnip_condition(1),  action = H.make_luasnip_action(1) }
H.steps_builtin.luasnip_prev   = { condition = H.make_luasnip_condition(-1), action = H.make_luasnip_action(-1) }
H.steps_builtin.luasnip_expand = { condition = H.is_luasnip_expandable,      action = H.make_cmd_lua_action('require("luasnip").expand()') }

H.has_nvimautopairs         = function() return H.has_module('nvim-autopairs') end
H.make_nvimautopairs_action = function(method) return function() return vim.fn.keytrans(require('nvim-autopairs')[method]()) end end

H.steps_builtin.nvimautopairs_cr = { condition = H.has_nvimautopairs, action = H.make_nvimautopairs_action('autopairs_cr') }
H.steps_builtin.nvimautopairs_bs = { condition = H.has_nvimautopairs, action = H.make_nvimautopairs_action('autopairs_bs') }
--stylua: ignore end

-- Validators -----------------------------------------------------------------
H.is_string = function(x) return type(x) == 'string' end

H.is_array_of = function(x, predicate)
  if not H.islist(x) then return false end
  for i = 1, #x do
    if not predicate(x[i]) then return false end
  end
  return true
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.keymap) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.notify = function(msg, level_name, silent)
  if not silent then vim.notify('(mini.keymap) ' .. msg, vim.log.levels[level_name]) end
end

H.normalize_pos = function(row, col)
  -- Input is {0,0} indexed, output is {1,0} indexed
  if row < 0 or (row == 0 and col < 0) then return { 1, 0 } end
  local last_row = vim.api.nvim_buf_line_count(0) - 1
  local n_col_last_row = H.get_row_cols(last_row)
  -- Assume this is used in Insert node, so placing just after EOL can be done
  if row > last_row or (row == last_row and col > n_col_last_row) then return { last_row + 1, n_col_last_row } end

  if col < 0 then return { row, H.get_row_cols(row - 1) } end
  if col > H.get_row_cols(row) then return { row + 2, 0 } end
  return { row + 1, col }
end

H.get_row_cols = function(row) return vim.fn.getline(row + 1):len() end

H.get_tsnode = function() return vim.treesitter.get_node() end

H.hide_completion = function()
  -- NOTE: `complete()` instead of emulating <C-y> works immediately (without
  -- the need to `vim.schedule()`). See 'mini.snippets' for more details.
  -- NOTE: Checking 'pumvisible() == 1' should not lead to edge cases from
  -- 'mini.snippets' (as there is no extmarks involved).
  if vim.fn.mode() == 'i' and vim.fn.pumvisible() == 1 then vim.cmd('silent noautocmd call complete(col("."), [])') end
end

-- TODO: Remove after compatibility with Neovim=0.9 is dropped
H.islist = vim.fn.has('nvim-0.10') == 1 and vim.islist or vim.tbl_islist

return MiniKeymap
