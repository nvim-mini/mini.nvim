--- *mini.input* Get user input
---
--- MIT License Copyright (c) 2026 Evgeni Chasnovski

--- Features:
---
--- - Get user input with fully customizable key and view handling.
---
--- - Built-in configurable views as floating window, statusline/tabline/winbar,
---   virtual line/text.
---
--- - Implementation is non-blocking but waits to return the input. It also works
---   in any mode without requiring mode change. See |MiniInput-lifecycle|.
---
--- - |vim.ui.input()| implementation. To adjust, use |MiniInput.ui_input()| or
---   save-restore `vim.ui.input` manually after calling |MiniInput.setup()|.
---
--- Sources with more details:
--- - |MiniInput.get()|
--- - |MiniInput.default_key()|
--- - |MiniInput-state|
--- - |MiniInput-examples|
--- - |MiniInput-in-other-plugins| (for plugin authors)
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.input').setup({})` (replace `{}`
--- with your `config` table). It will create global Lua table `MiniInput` which
--- you can use for scripting or manually (with `:lua MiniInput.*`).
---
--- See |MiniInput.config| for `config` structure and default values.
---
--- You can override runtime config settings locally to buffer inside
--- `vim.b.miniinput_config` which should have same structure as
--- `MiniInput.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- # Comparisons ~
---
--- - [folke/snacks.nvim#input](https://github.com/folke/snacks.nvim):
---     - Both provide |vim.ui.input()| implementation.
---     - Has asynchronous implementation (i.e. does not wait for user to finish
---       input), while this module has synchronous non-blocking implementation.
---     - Uses floating window and forced Insert mode. This module allows more
---       view customizations and can be used in any mode without interruptions.
---
--- - |input()|:
---     - Both are synchronous.
---     - Both allow custom highlight and completion.
---     - This module also allows supplying input scope and visibility,
---       customizing keys and view.
---
--- # Highlight groups ~
--- *MiniInput-hl-groups*
---
--- - `MiniInputAdded`   - added text during completion navigation.
--- - `MiniInputBorder`  - border of a |MiniInput.gen_view.floatwin()| handler.
--- - `MiniInputCaret`   - caret symbol shown in a prompt area.
--- - `MiniInputHide`    - input is hidden, usually used instead of `MiniInputPrompt`.
--- - `MiniInputHint`    - hints shown during completion navigation.
--- - `MiniInputNormal`  - basic foreground/background.
--- - `MiniInputPrompt`  - input prompt (intention of the input).
--- - `MiniInputSpecial` - special keys (like literal `\t`, `\n`, etc.) in input.
---@tag MiniInput

--- Information about the state of the input. It is passed as a handler argument.
--- Use |MiniInput.get_state()| to get information about the current state (if any).
--- A table with the following fields:
---
--- - <caret> `(number)` - character (not byte) index at which to modify input.
---   Should be from 1 (prepend input) to "input width plus 1" (append input).
---
--- - <complete> `(table|nil)` - information about active completion navigation.
---   If present, it means that completion navigation is in action.
---   Its fields describe the state of navigation:
---     - <base> `(string)` - reference text to the left of caret at the start
---       of completion. Used to compute candidates. Can be empty string.
---     - <id> `(number)` - identifier of current completion item. Can be zero to
---       mean that the base is shown. If not zero, must mean that a `items[id]`
---       candidate is now shown to the left of caret as the part of the input.
---     - <items> `(table)` - string array of completion candidates. May be empty.
---       Are intended to fully replace <base>, so should contain it in any sense.
---     - <method> `(string)` - completion method. Like `"default"`, `"history"`, etc.
---       Can be `""` (empty string) to mean "default method of complete handler".
---
--- - <data> `(table)` - any information to be reused within the same input session.
---   Note: handlers should not change fields that they don't "own".
---
--- - <errmsg> `(errmsg)` - first error message caught during input process.
---
--- - <highlight> `(table|nil)` - information about current input highlighting.
---   If absent, the whole input is highlighted using `MiniInputNormal` group.
---   Should be an array of highlight ranges. They might be not ordered, overlap,
---   go outside of input width. It is up to the view handler to decide how to
---   interpret them. See |MiniInput.state_to_chunks()| for a helper.
---   Fields of a single highlight range:
---     - <from> `(number)` - character index (one-indexed) of range start.
---     - <to> `(number)` - character index (one-indexed) of range end (inclusive).
---       Should not be smaller than <from>. Can be |math.huge|.
---     - <hl> `(string)` - highlight group to use for highlighting.
---
--- - <input> `(string)` - current user input. Returned by |MiniInput.get()|.
---
--- - <opts> `(table)` - input options, same as in |MiniInput.get()|.
---
--- - <prompt> `(string)` - intention of the input. May be empty.
---
--- - <status> `(string)` - one of `"start"`, `"progress"`, `"accept"`, `"cancel"`.
---@tag MiniInput-state

--- # General ~
---
--- ## Initial input ~
---
--- Use `opts.init_keys` to imitate the initial state of the input: >lua
---
---   MiniInput.get({ init_keys = { 'Default' } })
--- <
--- ## Custom mappings ~
---
--- Override `handlers.key` in |MiniInput.config|: >lua
---
---   local key_handler = function(state, key)
---     -- <C-a> - move caret to start of line
---     if key == '\1' then
---       state.caret = 1
---     -- <S-BS> - clear all input
---     elseif key == vim.keycode('<S-BS>') then
---       state.input, state.caret = '', 1
---     else
---       -- IMPORTANT: Fall back to processing as usual
---       return MiniInput.default_key(state, key)
---     end
---   end
---
---   require('mini.input').setup({ handlers = { key = key_handler } })
--- <
--- ## Basic command line ~
---
--- An alternative |Command-line| with highlighting and completion: >lua
---
---   -- Construct reusable `MiniInput.get()` options
---   local cmdline_opts = { prompt = 'Command', scope = 'editor' }
---   -- - Highlight using bundled Vim tree-sitter parser and default handler
---   local highlight_vim = MiniInput.gen_highlight.treesitter('vim')
---   local highlight_cmdline = function(state)
---     state = highlight_vim(state) or state
---     return MiniInput.default_highlight(state) or state
---   end
---   cmdline_opts.handlers = { highlight = highlight_cmdline }
---   -- - Complete as if it is Command line input
---   cmdline_opts.completion = 'cmdline'
---
---   -- Create a mapping for `:`
---   local input_cmdline = function()
---     local cmd = MiniInput.get(cmdline_opts)
---     if cmd ~= nil then vim.cmd(cmd) end
---   end
---   vim.keymap.set('n', ':', input_cmdline)
--- <
--- # Handlers ~
---
--- ## Key ~
---
--- Perform custom actions based on arbitrary conditions: >lua
---
---   local key_handler = function(state, key)
---     -- Adjust prompt
---     state.opts.prompt = state.opts.prompt:gsub('[?:]%s*$', '')
---
---     -- Adjust scope
---     if state.opts.prompt == 'Editor action' then
---       state.opts.scope = 'editor'
---     end
---
---     -- Hide from view and history
---     if state.opts.prompt:find('[Pp]assword') ~= nil then
---       state.opts.hide = true
---     end
---
---     -- IMPORTANT: Process as usual
---     state = MiniInput.default_key(state, key) or state
---
---     -- Auto fill and accept
---     if state.input == 'AF' then
---       state.input, state.status = 'Autofilled input', 'accept'
---     end
---   end
---   require('mini.input').setup({ handlers = { key = key_handler } })
--- <
--- ## View ~
---
--- Show no view: >lua
---
---   require('mini.input').setup({ handlers = { view = function() end } })
--- <
--- Compute initial style depending on scope: >lua
---
---   local input = require('mini.input')
---   local view_virtline = input.gen_view.virtual({ style = 'above' })
---   local view_tabline = input.gen_view.uiline({ style = 'tabline' })
---   local view_winbar = input.gen_view.uiline({ style = 'winbar' })
---   local view_handler = function(state)
---     -- NOTE: does not support interactive scope change
---     local scope, view = state.opts.scope, view_tabline
---     if scope == 'buffer' or scope == 'window' then view = view_winbar end
---     if scope == 'cursor' or scope == 'line' then view = view_virtline end
---     return view(state)
---   end
---
---   input.setup({ handlers = { view = view_handler } })
--- <
--- Change symbols for caret and hidden input: see |MiniInput.gen_view|.
---
--- # Using 'mini.input' in other plugins ~
--- *MiniInput-in-other-plugins*
---
--- - Prefer using |vim.ui.input()| for more user coverage. Use |MiniInput.get()|
---   only when getting input synchronously is absolutely necessary.
---
--- - Perform a `_G.MiniInput ~= nil` check before using any feature. This ensures
---   that user explicitly set up 'mini.input'.
---@tag MiniInput-examples

---@alias __input_to_chunks - <to_chunks> `(function)` - a function that takes |MiniInput-state| and
---     `max_width` arguments and returns an array of `{ text, hl }` chunks that fit
---     into `max_width` display width. See |MiniInput.state_to_chunks()|.

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local

-- Module definition ==========================================================
local MiniInput = {}
local H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniInput.config|.
---
---@usage >lua
---   require('mini.input').setup() -- use default config
---   -- OR
---   require('mini.input').setup({}) -- replace {} with your config table
--- <
MiniInput.setup = function(config)
  -- TODO: Remove after Neovim=0.9 support is dropped
  if vim.fn.has('nvim-0.10') == 0 then
    vim.notify(
      '(mini.input) Neovim<0.10 is soft deprecated (module works but is not supported).'
        .. " It will be deprecated after the next 'mini.nvim' release (module might not work)."
        .. ' Please update your Neovim version.'
    )
  end

  -- Export module
  _G.MiniInput = MiniInput

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Define behavior
  H.create_autocommands()

  -- Create default highlighting
  H.create_default_hl()

  -- Set custom implementation
  vim.ui.input = MiniInput.ui_input

  -- Adjust terminal emulator's pasting with active input
  H.adjust_vim_paste()
end

--- Defaults ~
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text # Handlers ~
--- *MiniInput.config.handlers*
---
--- `config.handlers` defines functions that are applied during |MiniInput-lifecycle|.
--- Every handler takes |MiniInput-state| as the first argument and is expected to
--- either modify it in place or return a new state table.
---
--- Use |MiniInput.apply_handler()| to apply a handler for a given |MiniInput-state|.
--- They can be set up as part of the config (will be used as default) or passed
--- directly as a part of |MiniInput.get()| call.
---
--- ## Complete ~
---
--- `handlers.complete` is a handler intended to compute completion suggestions.
--- Takes |MiniInput-state| and `method` as arguments and is expected to modify
--- <complete> field. Default: |MiniInput.default_complete()|.
---
--- Only `complete.base` and `complete.items` are expected to be set by a complete
--- handler. Setting and modifying other fields (`complete.id` and `complete.method`)
--- is done in other handlers and as part of |MiniInput.apply_handler()|. Actually
--- showing completion information is up to the view handler.
---
--- This handler is usually applied manually inside a key handler via using
--- `MiniInput.apply_handler(state, 'complete', method)`. Like, for example,
--- in |MiniInput.default_key()| after <Tab> or <Up>.
---
--- Here is an example of a simple demo complete handler: >lua
---
---   local complete_handler = function(state, method)
---     if method == '' or method == 'xy' then
---       local text = vim.fn.strcharpart(state.input, 0, state.caret - 1)
---       local base = text:match('%S*$')
---       state.complete = { base = base, items = { base .. 'x', base .. 'y' } }
---       return
---     end
---     return MiniInput.default_complete(state, method)
---   end
---
---   require('mini.input').setup({ handlers = { complete = complete_handler } })
--- <
--- ## Key ~
---
--- `handlers.key` is a handler intended to process every user key press.
--- Takes |MiniInput-state| and `key` as arguments. Argument `key` represents a key
--- that needs to be processed: a string if from the user input or `nil` if input
--- needs to be set up, refreshed, or torn down. Default: |MiniInput.default_key()|.
---
--- A string `key` can be two kinds:
--- - Forwarded from |getcharstr()| verbatim as a result of interactive key press.
---   Meaning it will be in escaped form and not as a |key-notation|: i.e. `"\r"`
---   and not `"<CR>"`. It also means that all kinds of combos (`<M-...>`, `<C-S-...>`),
---   mouse clicks, and wheel scrolls are also forwarded to key handler.
--- - Any string as part of `opts.init_keys` in |MiniInput.get()|. If a string
---   doesn't look like it came from |getcharstr()|, it is usually a good idea
---   to insert this string at caret as is.
---
--- The suggested overall approach for custom key handler is "if `key` is special -
--- act on it, if can be used in the input - insert at caret, ignore otherwise".
--- It is also important to never change the current mode (as in |vim-modes|)
--- for |MiniInput.get()| to work as expected.
---
--- Here is an example of a basic custom key handler: >lua
---
---   local custom_actions = {
---     [vim.keycode('<Left>')] = function(state)
---       state.caret = math.max(state.caret - 1, 1)
---     end,
---     [vim.keycode('<Right>')] = function(state)
---       local input_width = vim.fn.strchars(state.input)
---       state.caret = math.min(state.caret + 1, input_width + 1)
---     end,
---     [vim.keycode('<CR>')] = function(state) state.status = 'accept' end,
---     [vim.keycode('<Esc>')] = function(state) state.status = 'cancel' end,
---   }
---
---   local key_handler = function(state, key)
---     -- No need for special setup or teardown
---     if key == nil then return end
---
---     -- If key is special - act on it
---     if custom_actions[key] then return custom_actions[key](state) end
---
---     -- If key is not printable - do nothing
---     if vim.fn.match(key, '^[[:print:]]\\+$') < 0 then return end
---
---     -- Insert at caret
---     local caret, input = state.caret, state.input
---     local before_caret = vim.fn.strcharpart(input, 0, caret - 1)
---     local after_caret = vim.fn.strcharpart(input, caret - 1)
---     state.input = before_caret .. key .. after_caret
---     state.caret = caret + vim.fn.strchars(key)
---
---     -- No need to return anything as `state` is modified in place
---   end
---
---   require('mini.input').setup({ handlers = { key = key_handler } })
--- <
--- ## Highlight ~
---
--- `handlers.highlight` is a handler intended to compute and set highlight info
--- about the current input. Takes |MiniInput-state| as the only argument and is
--- expected to modify <highlight> field. Default: |MiniInput.default_highlight()|.
---
--- See |MiniInput.gen_highlight| for built-in highlight handler generators.
---
--- It is usually a good idea to append to a <highlight> if it already exists.
--- This makes it work more robustly when combining highlights.
---
--- Here is a basic example that highlights all letters `a`: >lua
---
---   local hl_handler = function(state)
---     local highlight = {}
---     for col in string.gmatch(state.input, '()a') do
---       -- NOTE: range should use character (not byte) indexes
---       local char_col = vim.fn.charidx(state.input, col)
---       local range = { from = char_col, to = char_col, hl = 'Special' }
---       table.insert(highlight, range)
---     end
---
---     state.highlight = vim.list_extend(state.highlight or {}, highlight)
---
---     -- Possibly also apply default handler afterwards
---     return MiniInput.default_highlight(state)
---   end
---
---   require('mini.input').setup({ handlers = { highlight = hl_handler } })
--- <
--- ## View ~
---
--- `handlers.view` is a handler intended to show the input state on screen.
--- Takes |MiniInput-state| as the only argument. Default: |MiniInput.default_view()|.
---
--- See |MiniInput.gen_view| for built-in view handler generators.
---
--- Example of view that uses |nvim_echo()| to show the input: >lua
---
---   local view_handler = function(state)
---     -- Process start and end of the input lifecycle
---     local is_start = state.status == 'start'
---     local is_end = state.status == 'accept' or state.status == 'cancel'
---     if is_start or is_end then vim.cmd('mode') end
---     if is_end then return end
---
---     -- Compute text-hl chunks that fit and show them
---     local chunks = MiniInput.state_to_chunks(state, vim.v.echospace)
---     vim.api.nvim_echo(chunks, false, {})
---   end
---
---   require('mini.input').setup({ handlers = { view = view_handler } })
--- <
--- # Scope ~
---
--- `config.scope` is a string that defines an input scope. It is meant as an extra
--- information for handlers to tweak their behavior (`view` style, etc.). Possible
--- values: `"cursor"`, `"line"`, `"buffer"`, `"window"`, `"tabpage"`, `"editor"`, `"project"`.
MiniInput.config = {
  -- Functions that control input lifecycle
  handlers = {
    -- Compute completion candidates
    complete = nil,

    -- Compute highlighting of current input
    highlight = nil,

    -- Handle input start, every key press, and input end
    key = nil,

    -- Show current input state
    view = nil,
  },

  -- Default input scope: cursor/line/buffer/window/tabpage/editor/project
  scope = 'editor',
}
--minidoc_afterlines_end

--- Get input from the user
---
--- # Lifecycle ~
--- *MiniInput-lifecycle*
---
--- This module implements custom lifecycle to interact with the user. It starts
--- when calling |MiniInput.get()| and ends when a value is returned.
--- Only one active input is allowed simultaneously.
---
--- The basic cycle unit is a step that processes a `key` (string or `nil`). It is
--- done by calling relevant handlers in order: key handler with `key` as a second
--- argument, highlight handler, view handler. |MiniInput.apply_handler()| is used
--- to apply each handler and the output of one is used as the input for the next.
---
--- During a step some state fields are automatically removed:
--- - <highlight> is removed before applying a key handler to always have the most
---   up to date highlighting.
--- - <complete> is removed if it was not changed after applying a key handler but
---   something else in the state besides <highlight> did change. This is meant as
---   an automatic stop of completion when it is not advancing.
---
--- If a step sets an ending state <status> (i.e. `"accept"` or `"cancel"`), the input
--- is finished by extra finishing step (see below).
---
--- The order of operations is as follows:
--- - Create initial |MiniInput-state| based on the input `opts`, with defaults
---   inferred from |MiniInput.config|, and `vim.b.miniinput_config`.
--- - Set <status> to `"start"`.
--- - Advance one step with `key=nil`. This is meant as a "setup" step for handlers.
--- - Set <status> to `"progress"`.
--- - Process `opts.init_keys` one item per step with `key` set to the string item.
--- - Wait for user to press a key (via |getcharstr()|). The key string (in escaped
---   form and not as a |key-notation|; i.e. `"\r"` and not `"<CR>"`) is then used
---   to advance a step. Note: <C-c> is hard coded to cancel the input.
--- - Repeat previous step until the ending <status> (`"accept"` or `"cancel"`).
--- - Finish the input:
---     - Perform a "teardown"' step with `key=nil`.
---     - If <errmsg> is set, throw an |error()|.
---     - If input is accepted (even if empty) and not hidden, add <input> to
---       the history. Get the whole history with |MiniInput.get_history()|.
---     - Return <input> if <status> is `"accept"`, `nil` otherwise.
---
---@param opts table|nil Options. Possible fields:
---   - <completion> `(string)` - completion method. Default: `''` to use default
---     completion method of the `complete` handler.
---   - <handlers> `(table)` - same as in |MiniInput.config.handlers|, used only for
---     the duration of the current input.
---   - <hide> `(boolean)` - whether input should be hidden. Default: `false`.
---     Note: this does not guarantee a total security of the input, only that
---     the typed characters are expected to not be shown on screen and not added
---     to the history. If set:
---       - The `view` handler is expected to not directly show current input.
---         Like replace characters with pre-defined string or fully not show.
---       - The `complete` and `highlight` handlers are not called.
---       - Accepted input will not be added to the history.
---   - <init_keys> `(table)` - array of string keys that are emulated before asking
---     for the user input. Using values that can be an output of |getcharstr()|
---     should be preferred, but a key handler should work with any string.
---     Default: `{}`.
---   - <prompt> `(string)` - intention of the input, same as in |input()|.
---     Default: `"Input"`.
---   - <scope> `(string)` - same as in |MiniInput.config|. Default: the value from
---     `MiniInput.config` with some hard coded exceptions (on Neovim<0.12.3):
---       - |vim.lsp.buf.rename()| will use `"cursor"` if no `new_name` is supplied.
---
---@return string|nil User input (from the <input> state field) if accepted, even if
---   empty. `nil` if canceled or there was an active input.
---
---@usage >lua
---   local input = MiniInput.get({
---     -- Intention of the input
---     prompt = 'New value',
---     -- The input is for something at cursor
---     scope = 'cursor',
---     -- Emulate pressing `a`, `<BS>`, and `b`
---     init_keys = { 'a', vim.keycode('<BS>'), 'b' },
---   })
--- <
MiniInput.get = function(opts)
  H.check_type('opts', opts, 'table', true)
  opts = opts or {}
  opts.scope = opts.scope or (_G.MiniInput or {})._temp_default_scope

  -- Only allow one input at a time
  if H.state ~= nil then return nil end

  local init_state = H.state_new(H.get_config(opts))
  H.state_validate(init_state)
  H.state = init_state

  H.handle_step(nil)
  if H.state_is_end() then return H.state_finish() end
  H.state.status = 'progress'

  for _, k in ipairs(H.state.opts.init_keys) do
    H.handle_step(k, true)
    if H.state_is_end() then return H.state_finish() end
  end
  H.redraw()

  local lmap = H.get_lmap()
  for _ = 1, 1000000 do
    local key = H.getcharstr(lmap)
    if key == nil and not H.state_is_end() then H.state.status = 'cancel' end
    if H.state_is_end() then break end
    H.handle_step(key)
    if H.state_is_end() then break end
  end

  return H.state_finish()
end

--- A |vim.ui.input()| implementation
---
--- Function which can be used to directly override |vim.ui.input()| to use this
--- module functionality. Set automatically in |MiniInput.setup()|.
---
---@usage To preserve original `vim.ui.input()`: >lua
---
---   local ui_input_orig = vim.ui.input
---   require('mini.input').setup()
---   vim.ui.input = ui_input_orig
--- <
MiniInput.ui_input = function(opts, on_confirm)
  opts = opts or {}
  local input_opts = { completion = opts.completion, prompt = opts.prompt, scope = opts.scope }
  input_opts.handlers = { highlight = H.make_ui_select_hl_fun(opts.highlight) }
  input_opts.init_keys = { opts.default }

  on_confirm(MiniInput.get(input_opts))
end

--- Get current input state
---
---@return table|nil Current |MiniInput-state| if input is active, `nil` otherwise. Notes:
---   - For hidden input (`state.opts.hide=true`), both <caret> and <input> are `nil`
---     to actually hide the input.
MiniInput.get_state = function()
  if H.state == nil then return nil end
  local res = H.copy_tables(H.state)
  if res.opts.hide then
    res.input, res.caret = nil, nil
  end
  return res
end

--- Get input history
---
---@return table Array with data about all previous non-hidden inputs (from earliest
---   to latest). Each element is a table with the following fields:
---   - <cwd> `(string)` - |current-directory| at the time of input's end.
---   - <input> `(string)` - input result.
---   - <prompt> `(string)` - `opts.prompt` supplied in |MiniInput.get()|.
---   - <scope> `(string)` - `opts.scope` supplied in |MiniInput.get()|.
MiniInput.get_history = function() return vim.deepcopy(H.history) end

--- Set input history
---
---@param history table Array describing all previous inputs. Same structure
---   as |MiniInput.get_history()| output.
MiniInput.set_history = function(history)
  H.check_array_of('history', history, 'table')
  for i, h in ipairs(history) do
    local item = string.format('history[%d]', i)
    H.check_type(item .. '.cwd', h.cwd, 'string')
    H.check_type(item .. '.input', h.input, 'string')
    H.check_type(item .. '.prompt', h.prompt, 'string')
    H.check_one_of(item .. '.scope', h.scope, H.allowed_scopes)
  end

  H.history = vim.deepcopy(history)
end

--- Refresh active input
---
--- Performs one step of |MiniInput-lifecycle| with `key=nil`.
MiniInput.refresh = function()
  if H.state == nil then return end
  H.handle_step(nil)
  if H.state_is_end() then H.state_finish() end
  vim.schedule(H.redraw)
end

--- Highlight generators
---
--- This is a table with function elements. Call to actually get a view function.
MiniInput.gen_highlight = {}

--- Highlight with tree-sitter
---
---@param lang string A language of tree-sitter parser to use.
---
---@return function A highlight handler. Seem |MiniInput.config.handlers|.
MiniInput.gen_highlight.treesitter = function(lang)
  local append_ts_hl_range = function(arr, line, tstree, tree)
    local query = tstree and vim.treesitter.query.get(tree:lang(), 'highlights')
    if query == nil then return end
    for capture, node in query:iter_captures(tstree:root(), line) do
      -- Ignore private captures
      if query.captures[capture]:sub(1, 1) ~= '_' then
        local _, from, _, to = node:range()
        local hl = string.format('@%s.%s', query.captures[capture], query.lang)
        from, to = vim.fn.charidx(line, from) + 1, vim.fn.charidx(line, to)
        if from <= to then table.insert(arr, { from = from, to = to, hl = hl }) end
      end
    end
  end

  return function(state)
    local line = state.input
    local ok, parser = pcall(vim.treesitter.get_string_parser, line, lang)
    if not ok or parser == nil then return end

    -- Traverse all trees and compute highlight ranges
    parser:parse(true)
    local highlight = {}
    parser:for_each_tree(function(tstree, tree) append_ts_hl_range(highlight, line, tstree, tree) end)

    -- Respect maybe already present <highlight>
    state.highlight = vim.list_extend(state.highlight or {}, highlight)
  end
end

--- View generators
---
--- This is a table with function elements. Call to actually get a view function.
---
--- Each element accepts <style> option which fine tunes the input view.
--- With default key handler (|MiniInput.default_key()|) it can be adjusted
--- interactively by pressing <C-s>.
---
--- Each element also accepts <to_chunks> option. It is a function that takes
--- a |MiniInput-state| and `max_width` arguments and returns an array of `{ text, hl }`
--- chunks that fit into `max_width` display width (as in |strdisplaywidth()|).
---
--- This is a way to adjust how input is shown. Like caret/hide symbols, etc.
--- By default uses |MiniInput.state_to_chunks()|, which also means:
--- - All control characters (like literal `\t`, `\n`, etc.) will be translated
---   via |keytrans()|.
---
--- Example: >lua
---
---   local input = require('mini.input')
---
---   -- Adjust how state is converted to text-hl chunks
---   local to_chunks_opts = {
---     symbol_caret = '_',
---     symbol_hide = '*',
---     -- Do not include prompt and hint in `floatwin` handler
---     include_prompt = false,
---     include_hint = false,
---   }
---   local to_chunks = function(state, max_width)
---     return MiniInput.state_to_chunks(state, max_width, to_chunks_opts)
---   end
---
---   -- Supply custom `to_chunks` as an option
---   local view_opts = { to_chunks = to_chunks }
---   input.setup({ handlers = { view = input.gen_view.floatwin(view_opts) } })
--- <
MiniInput.gen_view = {}

--- Floating window view
---
--- Show input inside a floating window. Prompt and completion hints are shown
--- in title and footer.
---
--- Window position and dimensions are computed based on state's <scope> and
--- `opts.style`:
--- - `scope="cursor"` is shown near the cursor. For example, `style="BL"` will
---   have bottom left corner at nearest top right cell relative to the cursor.
--- - `scope="line"` is shown near the current line. For example, `style="BL"` will
---   have bottom left corner at left side above the line.
--- - `scope="buffer"` and `scope="window"` will be shown relative to the current
---   window. For example, `style="BL"` will be shown in the bottom left corner.
--- - `scope="tabpage"`, `scope="editor"`, `scope="project"` will be shown relative to
---   the overall Neovim instance. For example, `style="BL"` will be shown in the
---   bottom left corner.
---
--- Identifiers of floating window and its buffer are stored as `floatwin_win_id`
--- and `floatwin_buf_id` in |MiniInput-state| <data> field. Floating window is
--- not focused and cursor position is not the same as caret position.
---
---@param opts table|nil Options. Possible fields:
---   - <adjust_config> `(function)` - function to adjust default config. Will be
---     called with two arguments: current |MiniInput-state| and a window config
---     (always with `relative="editor"` and `anchor="NW"`) computed based
---     on `opts.style`. Should return an adjusted window config.
---     Default: `function(state, config) return config end`.
---
---   - <style> `(string)` - a two character description of how to show the window.
---     Default: `"BL"`.
---
---       First character describes vertical position:
---       - `"T"` - top window border will be at scope's reference top border.
---       - `"M"` - middle between top and bottom window borders will be at the
---         middle of scope's reference top and bottom borders.
---       - `"B"` - bottom window border will be at scope's reference bottom border.
---
---       Second character describes horizontal position:
---       - `"L"` - left window border will be at scope's reference left border.
---       - `"M"` - middle between left and right window borders will be at the
---         middle of scope's reference left and right borders.
---       - `"R"` - right window border will be at scope's reference right border.
---
---   __input_to_chunks
---
---@usage >lua
---   local input = require('mini.input')
---
---   -- Use border different from 'winborder'
---   local adjust_config = function(_, config)
---     config.border = 'double'
---     return config
---   end
---
---   -- Choose initial style based on the scope
---   local floatwin = input.gen_view.floatwin
---   local view_tm = floatwin({ style = 'TM', adjust_config = adjust_config })
---   local view_bl = floatwin({ style = 'BL', adjust_config = adjust_config })
---   local view_handler = function(state)
---     local scope, view = state.opts.scope, view_tm
---     if scope == 'cursor' or scope == 'line' then view = view_bl end
---     return view(state)
---   end
---
---   input.setup({ handlers = { view = view_handler } })
--- <
MiniInput.gen_view.floatwin = function(opts)
  local default_opts = { style = 'BL' }
  default_opts.adjust_config = function(_, config) return config end
  local default_to_chunks_opts = { include_prompt = false, include_hint = false }
  default_opts.to_chunks = function(state, max_width)
    return MiniInput.state_to_chunks(state, max_width, default_to_chunks_opts)
  end
  opts = vim.tbl_extend('force', default_opts, opts or {})
  H.check_type('opts.adjust_config', opts.adjust_config, 'callable')
  H.check_one_of('opts.style', opts.style, { 'TL', 'TM', 'TR', 'ML', 'MM', 'MR', 'BL', 'BM', 'BR' })
  H.check_type('opts.to_chunks', opts.to_chunks, 'callable')

  -- Change style in vertical-horizontal order
  local all_styles = { 'BL', 'ML', 'TL', 'BM', 'MM', 'TM', 'BR', 'MR', 'TR' }

  return function(state)
    if H.state_is_end(state) then
      pcall(vim.api.nvim_win_close, state.data.floatwin_win_id, true)
      pcall(vim.api.nvim_buf_delete, state.data.floatwin_buf_id, { force = true })
      return
    end
    local style, _ = H.handle_view_style(state, opts.style, all_styles)

    -- Try to fit all chunks first, but later still truncate to window width
    local winborder = vim.fn.exists('+winborder') == 0 and '' or vim.o.winborder
    default_to_chunks_opts = { include_prompt = winborder == 'none', include_hint = winborder == 'none' }
    local chunks = H.get_chunks(opts, state)
    local default_config = H.default_floatwin_config(state, style, H.get_chunks_displaywidth(chunks))
    local config = opts.adjust_config(state, default_config)
    chunks = H.get_chunks(opts, state, config.width)

    H.ensure_floatwin_buf(state, chunks)
    H.ensure_floatwin_win(state, config)
  end
end

--- UI line (statusline, tabline, winbar) view
---
---@param opts table|nil Options. Possible fields:
---   - <style> `(string)` - which UI line to use. One of `"statusline"`,
---     `"tabline"`, `"winbar"`. Default: `"statusline"`.
---
---   __input_to_chunks
---
---@usage >lua
---   local input = require('mini.input')
---
---   -- Choose initial style based on the scope
---   local view_tabline = input.gen_view.uiline({ style = 'tabline' })
---   local view_winbar = input.gen_view.uiline({ style = 'winbar' })
---   local view_handler = function(state)
---     local scope, view = state.opts.scope, view_winbar
---     if scope == 'tabpage' or scope == 'editor' or scope == 'project' then
---       view = view_tabline
---     end
---     return view(state)
---   end
---
---   input.setup({ handlers = { view = view_handler } })
--- <
MiniInput.gen_view.uiline = function(opts)
  opts = vim.tbl_extend('force', { style = 'statusline', to_chunks = MiniInput.state_to_chunks }, opts or {})
  H.check_one_of('opts.style', opts.style, { 'statusline', 'tabline', 'winbar' })
  H.check_type('opts.to_chunks', opts.to_chunks, 'callable')

  local all_styles = { 'statusline', 'winbar', 'tabline' }
  local escape_stl = function(x) return (x:gsub('%%', '%%%%')) end

  return function(state)
    local style, style_is_new = H.handle_view_style(state, opts.style, all_styles)
    H.uiline_handle_option_values(state, style_is_new)
    if H.state_is_end(state) then return end

    local max_width = style == 'tabline' and vim.o.columns or vim.fn.winwidth(0)
    local chunks = H.get_chunks(opts, state, max_width)
    local parts = vim.tbl_map(function(c) return '%#' .. escape_stl(c[2]) .. '#' .. escape_stl(c[1]) end, chunks)
    local uiline_value = table.concat(parts) .. '%#MiniInputNormal#'

    local opt = style == 'tabline' and vim.o or vim.wo
    opt[style] = uiline_value
    if style == 'statusline' and vim.o.laststatus < 2 then vim.o.laststatus = 2 end
    if style == 'tabline' and vim.o.showtabline < 2 then vim.o.showtabline = 2 end
  end
end

--- Virtual (line, text) view
---
---@param opts table|nil Options. Possible fields:
---   - <style> `(string)` - how to display virtual text. One of `"above"`, `"below"`,
---     `"inline"`. Default: `"above"`.
---
---   __input_to_chunks
---
---@usage >lua
---   -- Choose different initial style
---   local input = require('mini.input')
---   local view_handler = input.gen_view.virtual({ style = 'inline' })
---   input.setup({ handlers = { view = view_handler } })
--- <
MiniInput.gen_view.virtual = function(opts)
  opts = vim.tbl_extend('force', { style = 'above', to_chunks = MiniInput.state_to_chunks }, opts or {})

  H.check_one_of('opts.style', opts.style, { 'above', 'below', 'inline' })
  H.check_type('opts.to_chunks', opts.to_chunks, 'callable')

  local ns_id = H.ns_id.view
  local all_styles = { 'above', 'below', 'inline' }

  return function(state)
    -- Cleanup
    local buf_id, extmark_id = vim.api.nvim_get_current_buf(), state.data.extmark_id
    if H.state_is_end(state) then
      pcall(vim.api.nvim_buf_del_extmark, state.data.buf_id, ns_id, extmark_id)
      return
    end
    local ok_extmark = pcall(vim.api.nvim_get_extmark_by_id, state.data.buf_id, ns_id, extmark_id, {})
    if not (buf_id == state.data.buf_id and ok_extmark) then
      pcall(vim.api.nvim_buf_del_extmark, state.data.buf_id, ns_id, extmark_id)
    end
    state.data.buf_id = buf_id

    local style, style_is_new = H.handle_view_style(state, opts.style, all_styles)
    local is_virtline = style == 'above' or style == 'below'

    -- Get chunks
    local win_info = H.get_curwin_info()
    local max_width = win_info.width - win_info.textoff
    local chunks = H.get_chunks(opts, state, max_width)
    local chunks_width = H.get_chunks_displaywidth(chunks)
    if is_virtline and chunks_width < max_width then
      chunks = vim.deepcopy(chunks)
      table.insert(chunks, { string.rep(' ', max_width - chunks_width), 'MiniInputNormal' })
    end

    -- Set
    local extmark_opts = { id = state.data.extmark_id, priority = 4096 }
    if is_virtline then
      extmark_opts.virt_lines = { chunks }
      extmark_opts.virt_lines_above = style == 'above'
    else
      extmark_opts.virt_text = chunks
      extmark_opts.virt_text_pos = 'inline'
    end
    local cur_pos = vim.api.nvim_win_get_cursor(0)
    state.data.extmark_id = vim.api.nvim_buf_set_extmark(0, ns_id, cur_pos[1] - 1, cur_pos[2], extmark_opts)

    -- Ensure that both current and virtual lines are visible
    if is_virtline and (state.status == 'start' or style_is_new) then
      local win_line, win_height = vim.fn.winline(), vim.fn.winheight(0)
      if win_line == 1 and style == 'above' then vim.cmd('normal! \25') end
      -- With 'above' the cursor line is moved down, with 'below' - no move
      -- local is_below_screen = style == 'above' and win_line > win_height or win_line >= win_height
      local is_below_screen = (win_line - (style == 'above' and 1 or 0)) >= win_height
      if is_below_screen then vim.cmd('normal! \5') end
    end
  end
end

--- Default key handler
---
--- Emulates most of |Command-line-mode| editing (|cmdline-editing|):
---
--- - Accept: <CR>. To insert literal newline, type `<C-j>`.
---
--- - Cancel: <Esc> or <C-c>.
---
--- - Move caret:
---     - <Left>, <Right> - one character to left / right.
---     - <M-h>, <M-l> - one character to left / right.
---     - <S-Left>, <S-Right> - one word to left / right.
---     - <C-b>, <C-e> (if no completion) - to start / end of input.
---     - <Home>, <End> - to start / end of input.
---
--- - Delete:
---     - <BS> / <C-h> - to caret's left. If `opts.autopair` is enabled, also delete
---       a character to caret's right if it formed a respected character pair.
---       See "Autopair".
---     - <Del> - at caret.
---     - <C-u> - from start to caret. As |c_CTRL-U|.
---     - <C-w> - contiguous keyword or non-keyword to caret's left. As |c_CTRL-W|.
---
--- - Insert at caret:
---     - <C-k> - digraph based on the next two pressed keys. As |c_CTRL-K|.
---     - <C-r> - content of a register. As |c_CTRL-R| including support for
---       special <C-a>, <C-f>, <C-l>, <C-w> keys for a register.
---     - <C-v>, <C-q> - next key literally. As |c_CTRL-V| and |i_CTRL-V_digit|
---       (all digits must be typed in full or stopped with <C-c>).
---     - Pasting from system |clipboard| is supported for "non-streaming" paste (as
---       described in |vim.paste()|).
---
--- - Autopair (if `opts.autopair` is set) is similar to |mini.pairs|:
---     - Opening characters `(`, `[`, `{` always insert a `()`, `[]`, `{}` pair and places
---       caret inside of it.
---     - Closing characters `)`, `]`, `}` move caret to the right if there is the same
---       character to the right.
---     - Closeopen characters `'`, `"`, <`> perform "close" action if possible and
---       "open" action if not.
---     - In all cases press <C-v> before special character to insert it verbatim.
---
--- - Completion:
---     - <Tab>, <S-Tab> - start with `state.opts.completion` method if not active
---       and advance through active completion (i.e. replace currently displayed
---       at caret item with the next one).
---       Note: type `<C-v><Tab>` to insert literal `\t`.
---     - <C-n>, <C-p>, <Up>, <Down> - start with `"history"` method if not active
---       and advance through active completion.
---     - <C-e> - cancel and return to initial input and caret.
---     - <C-y> - accept current candidate. Note: it will also be accepted after
---       any key that doesn't advance completion.
---
--- - Miscellaneous:
---     - <C-o> - change scope of the input. Cycles through all available ones.
---     - <C-s> - change view style. Works only with |MiniInput.gen_view| view
---       handlers. Cycles through all available ones.
---     - <C-x> - toggle hide/unhide of the input.
---
--- - Special keys (combo, mouse, but not whitespace) not listed above - ignored.
---   Anything else (even more than a single character) - inserted at caret.
---
---@param state table Current |MiniInput-state|.
---@param key string|nil A key to process. Should be escaped (`"\r"`, not `"<CR>"`).
---   See |vim.keycode()|.
---@param opts table|nil Options. Possible fields:
---   - <autopair> `(boolean)` - whether perform add autopair. Default: `false`.
MiniInput.default_key = function(state, key, opts)
  opts = opts or {}
  if key == nil or H.state_is_end(state) then return end
  if opts.autopair and H.key_methods_autopair[key] ~= nil then return H.key_methods_autopair[key](state) end
  if H.key_methods[key] ~= nil then return H.key_methods[key](state, opts) end
  if H.is_special_char(key) then return end
  H.insert_at_caret(state, key)
end

--- Default highlight handler
---
--- During active completion highlights added (computed via |matchfuzzy()|)
--- characters with `MiniInputAdded` group.
---
---@param state table Current |MiniInput-state|.
MiniInput.default_highlight = function(state)
  if H.state_is_end(state) then return end

  -- Only show characters added during completion navigation
  if state.complete == nil or state.complete.id == 0 then return end

  local cur_item = state.complete.items[state.complete.id]
  local base = state.complete.base
  local pos = base == '' and {} or vim.fn.matchfuzzypos({ cur_item }, base, { matchseq = 1 })[2][1]
  if pos == nil then return end

  -- Matches are increasing character zero-based indexes. Highlight ranges
  -- between them, including start and end edges.
  local cur_item_width = vim.fn.strchars(cur_item)
  table.insert(pos, 1, -1)
  table.insert(pos, cur_item_width)
  local offset, ranges = state.caret - cur_item_width - 1, {}
  for i = 2, #pos do
    if pos[i] - pos[i - 1] > 1 then
      local from = offset + pos[i - 1] + 1
      local to = offset + pos[i] - 1
      table.insert(ranges, { from = from + 1, to = to + 1, hl = 'MiniInputAdded' })
    end
  end

  -- Respect maybe already present <highlight>
  state.highlight = vim.list_extend(state.highlight or {}, ranges)
end

--- Default view handler
---
--- Same as |MiniInput.gen_view.floatwin()| with default options.
---
---@param state table Current |MiniInput-state|.
MiniInput.default_view = function(state) end -- Generated later

--- Default complete handler
---
--- Supported methods:
--- - `""` (default) - complete with buffer keywords (|'iskeyword'|) that match
---   a keyword at caret's left.
--- - `"history"` - complete with |MiniInput.get_history()| inputs that have current
---   input to caret's left as a prefix. If `opts.precise_history`, only use history
---   entries that have all info fields same as the current state. Orders from
---   earliest to latest. To initiate with the latest history match, press
---   <Up> or <C-p> with default key handler.
--- - `"cmdline"` - treat input as |Command-line| text and show completions at caret.
---   Note: as there is no |getcmdcomplpat()| variant to use outside of Command-line
---   mode, the base is inferred from |getcompletion()| output as the widest text to
---   caret's left that matches all candidates: fuzzily if |'wildoptions'| contains
---   `fuzzy`, as a prefix otherwise. If none - empty string is used. This approach
---   has limitations, but it is good enough.
--- - Every method supported by |getcompletion()|. Base is computed as the keyword
---   at caret's left.
---
---@param state table Current |MiniInput-state|.
---@param method string Completion method.
---@param opts table|nil Options. Possible fields:
---   - <precise_history> `(boolean)` - whether for `method='history'` try to match
---     only entries that have <cwd> as |current-directory|, same <scope> and
---     <prompt> as in current state. Default: `true`.
---
---@usage >lua
---   -- Do not match history precisely
---   local complete_opts = { precise_history = false }
---   local complete_handler = function(state, method)
---     return MiniInput.default_complete(state, method, complete_opts)
---   end
---   require('mini.input').setup({ handlers = { complete = complete_handler } })
--- <
MiniInput.default_complete = function(state, method, opts)
  opts = vim.tbl_extend('force', { precise_history = true }, opts or {})

  if H.state_is_end(state) then return end
  if method == 'history' then return H.complete_history(state, opts.precise_history) end
  method = method or state.opts.completion or ''

  local caret, input = state.caret, state.input
  local text = vim.fn.strcharpart(input, 0, caret - 1)
  local is_fs_method = method == 'file' or method == 'file_in_path' or method == 'dir' or method == 'dir_in_path'
  local base_pattern = is_fs_method and '[[:fname:]]*$' or '[[:keyword:]]*$'
  local base = vim.fn.strcharpart(text, vim.fn.match(text, base_pattern))

  if method == '' then
    state.complete = { items = H.complete_buf_words(base), base = base }
    return
  end

  local pat = method == 'cmdline' and vim.fn.strcharpart(input, 0, caret - 1) or base
  local ok, items = pcall(vim.fn.getcompletion, pat, method)
  if not ok then return end
  base = method == 'cmdline' and H.get_base_from_items(text, items) or base
  state.complete = { items = items, base = base }
end

--- Convert state into text-hl chunks
---
--- - Treat `state.highlight` elements in increasing priority, i.e. later ones
---   are placed "on top" of the previous ones if they overlap.
--- - Uses |MiniInput-hl-groups|.
--- - Multiline input (i.e. with newline characters `\n`) is shown as a single line.
--- - Treats `max_width` as display width (|strdisplaywidth()|).
--- - Truncates output chunks trying to center the caret.
---
---@param state table A |MiniInput-state|.
---@param max_width number|nil Maximum allowed display width. Can be |math.huge|.
---@param opts table|nil Options. Possible fields:
---   - <keytrans> `(boolean)` - whether to translate control characters (escaped
---     version of `<C-...>`). Default: `true`.
---   - <include_prompt> `(boolean)` - whether to start chunks with state prompt.
---     Default: `true`.
---   - <include_hint> `(boolean)` - whether to show complete hint to caret's right.
---     Default: `true`.
---   - <symbol_caret> `(string)` - string to use for caret. Default: `"▏"`.
---   - <symbol_hide> `(string)` - string to use for each input character when
---     input is hidden. Default: `"•"`.
---
---@return table An array of text-hl chunks that fit `max_width` display width.
MiniInput.state_to_chunks = function(state, max_width, opts)
  H.check_type('max_width', max_width, 'number', true)
  local default_opts = { keytrans = true, include_prompt = true, include_hint = true }
  default_opts.symbol_caret = '▏'
  default_opts.symbol_hide = '•'
  opts = vim.tbl_extend('force', default_opts, opts or {})
  H.check_type('opts.keytrans', opts.keytrans, 'boolean')
  H.check_type('opts.include_prompt', opts.include_prompt, 'boolean')
  H.check_type('opts.include_hint', opts.include_hint, 'boolean')
  H.check_type('opts.symbol_caret', opts.symbol_caret, 'string')
  H.check_type('opts.symbol_hide', opts.symbol_hide, 'string')

  -- Precompute state data
  local hide, symbol_hide = state.opts.hide, opts.symbol_hide
  local input = hide and string.rep(symbol_hide, vim.fn.strchars(state.input)) or state.input
  local caret = (hide and vim.fn.strchars(symbol_hide) or 1) * (state.caret - 1) + 1

  -- Compute input chunks to left and right of caret
  local max_to = vim.fn.strchars(input)
  local hl_ranges = { { from = 1, to = max_to, hl = 'MiniInputNormal' } }
  for _, range in ipairs(state.highlight or {}) do
    hl_ranges = H.insert_hl_range(hl_ranges, max_to, range.from, range.to, range.hl)
  end

  local input_chunks = {}
  for i, r in ipairs(hl_ranges) do
    input_chunks[i] = { vim.fn.strcharpart(input, r.from - 1, r.to - r.from + 1), r.hl }
  end
  local input_chunks_left, input_chunks_right = H.split_chunks_at(input_chunks, caret - 1)

  -- Compute chunks in specific order:
  -- prompt - input_left - caret - complete_hint - input_right
  local chunks, keytrans = {}, opts.keytrans
  if opts.include_prompt and state.opts.prompt ~= '' then
    local prompt = vim.trim(state.opts.prompt)
    local prompt_hl = hide and 'MiniInputHide' or 'MiniInputPrompt'
    local new = { { prompt, prompt_hl }, { ' ', 'MiniInputNormal' } }
    H.append_chunks(chunks, new, keytrans)
  end

  H.append_chunks(chunks, input_chunks_left, keytrans)

  if opts.symbol_caret ~= '' then H.append_chunks(chunks, { { opts.symbol_caret, 'MiniInputCaret' } }, keytrans) end
  local caret_offset = H.get_chunks_displaywidth(chunks)

  if opts.include_hint and state.complete ~= nil then
    local hint = string.format('(%d/%d)', state.complete.id, #state.complete.items)
    H.append_chunks(chunks, { { hint, 'MiniInputHint' } }, keytrans)
  end

  H.append_chunks(chunks, input_chunks_right, keytrans)

  return H.fit_chunks_to_displaywidth(chunks, max_width, caret_offset)
end

--- Apply state's handler
---
--- Given |MiniInput-state|, apply its handler (from `state.opts.handlers`) and
--- return the modified state.
---
--- Notes:
--- - Nothing is done for highlight and complete handlers when input is hidden.
--- - Applying complete handler ensures that <complete> state field has <id> set
---   to 0 (as it assumes new completion) and <method> to the input argument
---   (empty string if there was no argument).
--- - Error during handler application is stored as <errmsg> field of output state
---   if there is an active input. It is propagated via |error()| otherwise.
--- - Handler output is validated to be a valid |MiniInput-state|. If not - return
---   input `state`. Note: it still could be changed if handler modified in place.
---
---@param state table A |MiniInput-state|.
---@param name string Valid handler name.
---@param arg any Extra handler argument: like `key` for key handler and `method`
---   for complete handler.
---
---@return table A |MiniInput-state| as a result of applied handler. If handler returned
---   nothing, the input `state` is returned (assumes it was modified in place).
MiniInput.apply_handler = function(state, name, arg)
  H.check_one_of('name', name, { 'complete', 'highlight', 'key', 'view' })
  H.check_type('arg', arg, 'string', true)
  if arg == nil and name == 'complete' then arg = '' end

  if state.opts.hide and (name == 'highlight' or name == 'complete') then return state end
  local ok_handler, res = pcall(state.opts.handlers[name], state, arg)
  if not ok_handler then H.cache_error(state, 'Error applying `' .. name .. '` handler: ' .. res) end

  local new_state = (ok_handler and res or nil) or state
  if name == 'complete' and type(new_state.complete) == 'table' then
    new_state.complete.id = 0
    new_state.complete.method = arg
  end

  local ok_state, msg = pcall(H.state_validate, new_state)
  if not ok_state then H.cache_error(state, msg) end

  return ok_state and new_state or state
end

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniInput.config)

-- Current state of user input
H.state = nil

-- History of inputs
H.history = {}

-- Supported scopes
H.allowed_scopes = { 'cursor', 'line', 'buffer', 'window', 'tabpage', 'editor', 'project' }

-- Various cache
H.cache = {}

-- Namespaces
H.ns_id = {
  view = vim.api.nvim_create_namespace('MiniInputView'),
}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  H.check_type('handlers', config.handlers, 'table')
  H.check_type('handlers.complete', config.handlers.complete, 'function', true)
  H.check_type('handlers.highlight', config.handlers.highlight, 'function', true)
  H.check_type('handlers.key', config.handlers.key, 'function', true)
  H.check_type('handlers.view', config.handlers.view, 'function', true)

  H.check_type('scope', config.scope, 'string')

  return config
end

H.apply_config = function(config)
  MiniInput.config = config

  -- Ensure clear history
  H.history = {}

  -- Ensure default scope for some core functions
  if vim.fn.has('nvim-0.12.3') == 0 then
    -- NOTE: Use `vim.schedule` to not load `vim.lsp` during startup
    vim.schedule(function() vim.lsp.buf.rename = H.mock_lsp_buf_rename(vim.lsp.buf.rename) end)
  end
end

H.create_autocommands = function()
  local gr = vim.api.nvim_create_augroup('MiniInput', {})

  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = gr, pattern = pattern, callback = callback, desc = desc })
  end

  au('VimResized', '*', function() MiniInput.refresh() end, 'Refresh on resize')
  au('ColorScheme', '*', H.create_default_hl, 'Ensure colors')
end

H.create_default_hl = function()
  local hi = function(name, opts)
    opts.default = true
    vim.api.nvim_set_hl(0, name, opts)
  end

  hi('MiniInputAdded', { link = 'DiagnosticFloatingOk' })
  hi('MiniInputBorder', { link = 'FloatBorder' })
  hi('MiniInputCaret', { link = 'MiniInputPrompt' })
  hi('MiniInputHide', { link = 'DiagnosticFloatingWarn' })
  hi('MiniInputHint', { link = 'DiagnosticFloatingHint' })
  hi('MiniInputNormal', { link = 'NormalFloat' })
  hi('MiniInputPrompt', { link = 'DiagnosticFloatingInfo' })
  hi('MiniInputSpecial', { link = 'DiagnosticFloatingWarn' })
end

H.adjust_vim_paste = function()
  local paste_orig = vim.paste
  vim.paste = function(lines, phase)
    if MiniInput.get_state() == nil then return paste_orig(lines, phase) end
    if phase ~= -1 then return H.notify('There is no streaming paste support. Use `<C-r>+` or `<C-r>*`.', 'WARN') end
    H.insert_at_caret(H.state, table.concat(lines, '\n'))
    H.handle_step(nil)
  end
end

H.get_config = function(config)
  return vim.tbl_deep_extend('force', MiniInput.config, vim.b.miniinput_config or {}, config or {})
end

-- State ----------------------------------------------------------------------
H.state_new = function(opts)
  opts.completion = opts.completion or ''
  H.check_type('state.opts.handlers', opts.handlers, 'table')
  opts.handlers.complete = opts.handlers.complete or MiniInput.default_complete
  opts.handlers.highlight = opts.handlers.highlight or MiniInput.default_highlight
  opts.handlers.key = opts.handlers.key or MiniInput.default_key
  opts.handlers.view = opts.handlers.view or MiniInput.default_view
  if opts.hide == nil then opts.hide = false end
  opts.init_keys = opts.init_keys or {}
  opts.prompt = opts.prompt or 'Input'
  -- opts.scope should already be precomputed

  return { caret = 1, data = {}, input = '', opts = opts, status = 'start' }
end

H.state_validate = function(x)
  H.check_type('state', x, 'table')

  H.check_type('state.caret', x.caret, 'number')
  H.check_type('state.data', x.data, 'table')
  H.check_type('state.input', x.input, 'string')
  H.check_one_of('state.status', x.status, { 'start', 'progress', 'accept', 'cancel' })

  if not (1 <= x.caret and x.caret <= (vim.fn.strchars(x.input) + 1)) then
    H.error('`state.caret` should be between 1 and input width plus 1')
  end

  if x.complete ~= nil then
    H.check_type('state.complete', x.complete, 'table')
    H.check_type('state.complete.base', x.complete.base, 'string')
    H.check_array_of('state.complete.items', x.complete.items, 'string')
    H.check_type('state.complete.id', x.complete.id, 'number')
    H.check_type('state.complete.method', x.complete.method, 'string')
  end

  if x.highlight ~= nil then
    H.check_array_of('state.highlight', x.highlight, 'table')
    for i, h in ipairs(x.highlight) do
      local item = string.format('state.highlight[%d]', i)
      H.check_type(item .. '.from', h.from, 'number')
      H.check_type(item .. '.to', h.to, 'number')
      H.check_type(item .. '.hl', h.hl, 'string')
      if h.from > h.to then H.error(string.format('%s.from is bigger than %s.to', item, item)) end
    end
  end

  H.check_type('state.opts.completion', x.opts.completion, 'string')
  H.check_type('state.opts.handlers.complete', x.opts.handlers.complete, 'function')
  H.check_type('state.opts.handlers.highlight', x.opts.handlers.highlight, 'function')
  H.check_type('state.opts.handlers.key', x.opts.handlers.key, 'function')
  H.check_type('state.opts.handlers.view', x.opts.handlers.view, 'function')
  H.check_type('state.opts.hide', x.opts.hide, 'boolean')
  H.check_array_of('state.opts.init_keys', x.opts.init_keys, 'string')
  H.check_type('state.opts.prompt', x.opts.prompt, 'string')
  H.check_one_of('state.opts.scope', x.opts.scope, H.allowed_scopes)
end

H.state_finish = function()
  if H.cache.is_in_getcharstr then return vim.api.nvim_feedkeys('\3', 't', true) end

  H.handle_step(nil)

  local res = H.state.status == 'accept' and H.state.input or nil
  local errmsg, opts = H.state.errmsg, vim.deepcopy(H.state.opts)
  H.state, H.cache = nil, {}
  (_G.MiniInput or {})._temp_default_scope = nil

  if errmsg ~= nil then error(errmsg) end

  if res ~= nil and not opts.hide then
    local hist = { input = res, prompt = opts.prompt, scope = opts.scope, cwd = vim.fn.getcwd() }
    table.insert(H.history, hist)
  end
  return res
end

H.state_is_end = function(state)
  state = state or H.state
  return state.status == 'accept' or state.status == 'cancel'
end

H.mock_lsp_buf_rename = function(f)
  return function(new_name, opts)
    if new_name == nil then (_G.MiniInput or {})._temp_default_scope = 'cursor' end
    return f(new_name, opts)
  end
end

-- Handlers -------------------------------------------------------------------
H.handle_step = function(key, skip_redraw)
  local state, ref_state = H.copy_tables(H.state), H.copy_tables(H.state)

  -- Stop previous highlighting, as it is not up to date
  state.highlight, ref_state.highlight = nil, nil

  state = MiniInput.apply_handler(state, 'key', key)

  -- Stop completion if something has changed outside of completion
  local is_complete_stop = vim.deep_equal(state.complete, ref_state.complete) and not vim.deep_equal(state, ref_state)
  if is_complete_stop then state.complete = nil end

  state = MiniInput.apply_handler(state, 'highlight')
  state = MiniInput.apply_handler(state, 'view')

  H.state = state
  if not skip_redraw then H.redraw() end
end

-- Default key handler --------------------------------------------------------
H.key_methods = {}

H.keycode = vim.fn.has('nvim-0.10') == 1 and vim.keycode
  or function(s) return vim.api.nvim_replace_termcodes(s, true, true, true) end
local kc = H.keycode

-- General
H.key_methods[kc('<CR>')] = function(state, _) state.status = 'accept' end
H.key_methods[kc('<Esc>')] = function(state, _) state.status = 'cancel' end
H.key_methods[kc('<C-c>')] = H.key_methods[kc('<Esc>')]

-- Caret movement
H.key_methods[kc('<Left>')] = function(state, _)
  state.caret = H.clamp(state.caret - 1, 1, vim.fn.strchars(state.input) + 1)
end
H.key_methods[kc('<Right>')] = function(state, _)
  state.caret = H.clamp(state.caret + 1, 1, vim.fn.strchars(state.input) + 1)
end
H.key_methods[kc('<M-h>')] = H.key_methods[kc('<Left>')]
H.key_methods[kc('<M-l>')] = H.key_methods[kc('<Right>')]
H.key_methods[kc('<S-Left>')] = function(state, _)
  local caret, input = state.caret, state.input
  local to = H.match_keyword_chars(input, caret, 'left')
  state.caret = H.clamp(to + 1, 1, vim.fn.strchars(state.input) + 1)
end
H.key_methods[kc('<S-Right>')] = function(state, _)
  local caret, input = state.caret, state.input
  local to = H.match_keyword_chars(input, caret, 'right')
  state.caret = H.clamp(to + 1, 1, vim.fn.strchars(state.input) + 1)
end
H.key_methods[kc('<C-b>')] = function(state, _) state.caret = 1 end
H.key_methods[kc('<C-e>')] = function(state, _)
  if state.complete == nil then
    state.caret = vim.fn.strchars(state.input) + 1
    return
  end
  H.advance_state_complete(state, -state.complete.id)
  state.complete = nil
end
H.key_methods[kc('<Home>')] = H.key_methods[kc('<C-b>')]
H.key_methods[kc('<End>')] = function(state, _) state.caret = vim.fn.strchars(state.input) + 1 end

-- Delete
H.key_methods[kc('<BS>')] = function(state, opts)
  local caret, input = state.caret, state.input
  if caret <= 1 then return end
  local right_offset = (opts.autopair and H.is_inside_pair(state)) and 1 or 0
  state.input = vim.fn.strcharpart(input, 0, caret - 2) .. vim.fn.strcharpart(input, caret - 1 + right_offset)
  state.caret = caret - 1
end
H.key_methods[kc('<C-h>')] = H.key_methods[kc('<BS>')]
H.key_methods[kc('<Del>')] = function(state, _)
  local caret, input = state.caret, state.input
  if caret > vim.fn.strchars(input) then return end
  state.input = vim.fn.strcharpart(input, 0, caret - 1) .. vim.fn.strcharpart(input, caret)
end
H.key_methods[kc('<C-u>')] = function(state, _)
  state.input = vim.fn.strcharpart(state.input, state.caret - 1)
  state.caret = 1
end
H.key_methods[kc('<C-w>')] = function(state, _)
  local caret, input = state.caret, state.input
  local left_to = H.match_keyword_chars(input, caret, 'left')
  state.input = vim.fn.strcharpart(input, 0, left_to) .. vim.fn.strcharpart(input, caret - 1)
  state.caret = H.clamp(left_to + 1, 1, vim.fn.strchars(state.input) + 1)
end

-- Special insert
H.key_methods[kc('<C-k>')] = function(state, _)
  local ok, new = pcall(vim.fn.digraph_get, H.getcharstr_many(2, { ['\27'] = true }))
  if not ok then return end
  H.insert_at_caret(state, new)
end

H.key_methods[kc('<C-r>')] = function(state, _)
  -- Get register content
  local register = H.getcharstr()
  if register == nil then return end
  -- - Mimic some "insert object under cursor" behavior of Command-line mode
  local reg_content
  local expand_var = ({ ['\1'] = '<cWORD>', ['\6'] = '<cfile>', ['\23'] = '<cword>' })[register]
  if expand_var then reg_content = vim.fn.expand(expand_var) end
  if register == '\f' then reg_content = vim.fn.getline('.') end
  if reg_content == nil then
    local has_register, r = pcall(vim.fn.getreg, register)
    reg_content = has_register and r or ''
  end

  H.insert_at_caret(state, reg_content)
end

H.key_methods[kc('<C-q>')] = function(state, _)
  local char = H.getcharstr({}, true)
  if char == nil then return end

  -- See `:h i_CTRL-V_digit`
  if char:find('^[%doOxXuU]$') ~= nil then
    local new_text = H.get_ctrl_v_digits(char)
    if new_text ~= nil then H.insert_at_caret(state, new_text) end
    return
  end

  local ok, new_text = pcall(vim.fn.keytrans, char)
  if not ok or (ok and vim.fn.char2nr(char) <= 31) then new_text = char end
  H.insert_at_caret(state, new_text)
end
H.key_methods[kc('<C-v>')] = H.key_methods[kc('<C-q>')]

-- History navigation
H.key_methods[kc('<Up>')] = function(state, _)
  if state.complete == nil then state = MiniInput.apply_handler(state, 'complete', 'history') end
  return H.advance_state_complete(state, -1)
end
H.key_methods[kc('<Down>')] = function(state, _)
  if state.complete == nil then state = MiniInput.apply_handler(state, 'complete', 'history') end
  return H.advance_state_complete(state, 1)
end
H.key_methods[kc('<C-n>')] = H.key_methods[kc('<Down>')]
H.key_methods[kc('<C-p>')] = H.key_methods[kc('<Up>')]
H.key_methods[kc('<C-y>')] = function(state, _) state.complete = nil end

-- Completion navigation
H.key_methods[kc('<Tab>')] = function(state, _)
  if state.complete == nil then state = MiniInput.apply_handler(state, 'complete', state.opts.completion) end
  return H.advance_state_complete(state, 1)
end
H.key_methods[kc('<S-Tab>')] = function(state, _)
  if state.complete == nil then state = MiniInput.apply_handler(state, 'complete', state.opts.completion) end
  return H.advance_state_complete(state, -1)
end

-- Miscellaneous
H.key_methods[kc('<C-o>')] = function(state, _)
  state.opts.scope = H.advance_from_choices(H.allowed_scopes, state.opts.scope, 'scope')
end
H.key_methods[kc('<C-s>')] = function(state, _)
  state.data.new_style = H.advance_from_choices(state.data.all_styles, state.data.style, 'style')
end
H.key_methods[kc('<C-x>')] = function(state, _)
  state.opts.hide = not state.opts.hide
  H.notify('Input is ' .. (state.opts.hide and '' or 'not ') .. 'hidden')
end

-- Autopair keys
H.key_methods_autopair = {}
H.key_methods_autopair['('] = function(state) H.autopair_open(state, '()') end
H.key_methods_autopair['['] = function(state) H.autopair_open(state, '[]') end
H.key_methods_autopair['{'] = function(state) H.autopair_open(state, '{}') end
H.key_methods_autopair[')'] = function(state) H.autopair_close(state, ')') end
H.key_methods_autopair[']'] = function(state) H.autopair_close(state, ']') end
H.key_methods_autopair['}'] = function(state) H.autopair_close(state, '}') end
H.key_methods_autopair['"'] = function(state) H.autopair_closeopen(state, '""', '"') end
H.key_methods_autopair["'"] = function(state) H.autopair_closeopen(state, "''", "'") end
H.key_methods_autopair['`'] = function(state) H.autopair_closeopen(state, '``', '`') end

-- Local helpers
H.insert_at_caret = function(state, new_text)
  local caret, input = state.caret, state.input
  state.input = vim.fn.strcharpart(input, 0, caret - 1) .. new_text .. vim.fn.strcharpart(input, caret - 1)
  state.caret = caret + vim.fn.strchars(new_text)
end

H.match_keyword_chars = function(input, caret, side)
  local text = side == 'left' and vim.fn.strcharpart(input, 0, caret - 1) or vim.fn.strcharpart(input, caret - 1)
  local pat_keyword = side == 'left' and '[[:keyword:]]\\+$' or '^[[:keyword:]]\\+\\zs'
  local pat_non_keyword = side == 'left' and '[^[:keyword:]]\\+$' or '^[^[:keyword:]]\\+\\zs'

  local res = math.max(vim.fn.match(text, pat_keyword), vim.fn.match(text, pat_non_keyword), 0)
  return vim.fn.charidx(text, res) + (side == 'left' and 0 or (caret - 1))
end

H.get_ctrl_v_digits = function(submode)
  local n_extra = ({ o = 3, O = 3, u = 4, U = 8 })[submode] or 2
  local digits = H.getcharstr_many(n_extra, { ['\27'] = true })
  if digits == nil then return nil end
  digits = (submode:find('%d') ~= nil and submode or '') .. digits

  local base = ({ o = 8, O = 8, x = 16, X = 16, u = 16, U = 16 })[submode] or 10
  local ok, res = pcall(vim.fn.nr2char, tonumber(digits, base))
  return ok and res or nil
end

H.advance_state_complete = function(state, increment)
  local no_complete = H.state_is_end(state) or not (type(state.complete) == 'table' and #state.complete.items > 0)
  if no_complete then return state end

  local old_id, base = state.complete.id, state.complete.base
  local old = state.complete.items[old_id] or base
  local new_id = (old_id + increment) % (#state.complete.items + 1)
  local new = state.complete.items[new_id] or base
  state.complete.id = new_id

  -- Replace currently shown candidate with the new one
  local caret, input = state.caret, state.input
  local old_len = vim.fn.strchars(old)
  state.input = vim.fn.strcharpart(input, 0, caret - old_len - 1) .. new .. vim.fn.strcharpart(input, caret - 1)
  state.caret = caret + (vim.fn.strchars(new) - old_len)

  return state
end

H.advance_from_choices = function(all, cur, name)
  local new, n = nil, #all
  for i, v in ipairs(all) do
    if v == cur then new = all[i % n + 1] end
  end
  if not (new == nil or new == cur) then H.notify(string.format('Changed %s to %s', name, vim.inspect(new))) end
  return new
end

H.autopair_open = function(state, pair)
  H.insert_at_caret(state, pair)
  state.caret = state.caret - 1
end

H.autopair_close = function(state, close_char)
  local is_before_close = vim.fn.strcharpart(state.input, state.caret - 1, 1) == close_char
  if is_before_close then state.caret = state.caret + 1 end
  if not is_before_close then H.insert_at_caret(state, close_char) end
end

H.autopair_closeopen = function(state, pair, close_char)
  local is_before_close = vim.fn.strcharpart(state.input, state.caret - 1, 1) == close_char
  if is_before_close then H.autopair_close(state, close_char) end
  if not is_before_close then H.autopair_open(state, pair) end
end

H.is_inside_pair = function(state)
  local neigh = vim.fn.strcharpart(state.input, state.caret - 2, 2)
  return ({ ['()'] = true, ['[]'] = true, ['{}'] = true, ['""'] = true, ["''"] = true, ['``'] = true })[neigh] ~= nil
end

-- Default complete handler ---------------------------------------------------
H.complete_history = function(state, precise_history)
  local cwd, scope, prompt = vim.fn.getcwd(), state.opts.scope, state.opts.prompt
  local is_precise = function(h) return h.cwd == cwd and h.scope == scope and h.prompt == prompt end
  if not precise_history then is_precise = function(x) return true end end

  local base = vim.fn.strcharpart(state.input, 0, state.caret - 1)
  local is_match = function(x) return vim.startswith(x, base) and x ~= base end

  local raw, matched, seen = MiniInput.get_history(), {}, {}
  for i = #raw, 1, -1 do
    local val = raw[i].input
    if not seen[val] and is_match(val) and is_precise(raw[i]) then table.insert(matched, val) end
    seen[val] = true
  end
  local items, n = {}, #matched
  for i = 1, #raw do
    items[n - i + 1] = matched[i]
  end
  state.complete = { base = base, items = items }
end

H.complete_buf_words = function(base)
  -- Do not match all words for performance reasons
  if base == '' then return {} end

  -- Get keywords in current buffer that fuzzy match base
  local pattern_parts = {}
  for i = 1, vim.fn.strchars(base) do
    table.insert(pattern_parts, vim.fn.strcharpart(base, i - 1, 1))
  end
  -- NOTE: This looks hacky, but it is very fast in common cases and already
  -- respects 'ignorecase' and 'smartcase'
  local pattern = '\\V\\k\\*' .. table.concat(pattern_parts, '\\k\\*') .. '\\k\\*'
  vim.g._miniinput_matches = {}

  local cache_hlsearch, cache_cursor = vim.v.hlsearch, vim.api.nvim_win_get_cursor(0)
  local search_cmd = 'silent! keeppatterns %s/' .. pattern .. '/\\=add(g:_miniinput_matches, submatch(0))/gn'
  vim.cmd(search_cmd)
  -- Here `vim.v` doesn't work: https://github.com/neovim/neovim/issues/25294
  vim.cmd('let v:hlsearch=' .. cache_hlsearch)
  vim.api.nvim_win_set_cursor(0, cache_cursor)
  local matches = vim.g._miniinput_matches
  vim.g._miniinput_matches = nil

  -- Compute final unique matches sorted by how good fuzzy match is
  local uniq, seen = {}, { [base] = true }
  for _, m in ipairs(matches) do
    if not seen[m] then table.insert(uniq, m) end
    seen[m] = true
  end
  local ref = (vim.o.ignorecase and not vim.o.smartcase) and vim.fn.tolower(base) or base
  return vim.fn.matchfuzzy(uniq, ref, { matchseq = 1 })
end

H.get_base_from_items = function(text, items)
  if #items == 0 then return '' end

  local is_match = function(base_cur)
    for _, item in ipairs(items) do
      if not vim.startswith(item, base_cur) then return false end
    end
    return true
  end
  if vim.o.wildoptions:find('fuzzy') ~= nil then
    is_match = function(base_cur) return #vim.fn.matchfuzzy(items, base_cur, { matchseq = 1 }) == #items end
  end

  local res
  for i = vim.fn.strchars(text), 1, -1 do
    local base_cur = vim.fn.strcharpart(text, i - 1)
    if is_match(base_cur) then res = base_cur end
  end
  return res or ''
end

-- Views ----------------------------------------------------------------------
H.handle_view_style = function(state, init_style, all_styles)
  if state.status == 'start' then state.data.all_styles = all_styles end
  local style_is_new = state.data.new_style ~= nil and state.data.new_style ~= state.data.style
  state.data.style = state.data.new_style or state.data.style or init_style
  state.data.new_style = nil
  return state.data.style, style_is_new
end

H.default_floatwin_config = function(state, style, target_width)
  local ver, hor = style:sub(1, 1), style:sub(2, 2)
  local wininfo = H.get_curwin_info()

  local has_tabline = vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1)
  local has_statusline = vim.o.laststatus > 0
  local max_height = vim.o.lines - vim.o.cmdheight - (has_tabline and 1 or 0) - (has_statusline and 1 or 0)
  local max_width = vim.o.columns

  -- Compute window config
  local winborder = vim.fn.exists('+winborder') == 0 and '' or vim.o.winborder
  local border = winborder == '' and 'single' or nil
  local has_border = winborder ~= 'none'

  local prompt = state.opts.prompt:gsub('[\t\n%z]', ' ')
  local title_text = prompt == '' and '' or (' ' .. vim.trim(prompt) .. ' ')
  local footer_text, complete = '', state.complete
  if complete ~= nil then
    local method_prefix = complete.method == '' and '' or (' ' .. vim.trim(complete.method))
    footer_text = string.format('%s %d/%d ', (method_prefix:gsub('[\t\n%z]', ' ')), complete.id, #complete.items)
  end
  local title_width, footer_width = vim.fn.strdisplaywidth(title_text), vim.fn.strdisplaywidth(footer_text)

  local width = H.clamp(target_width, math.max(title_width, footer_width), max_width)
  local height = 1
  local width_offset = has_border and 2 or 0
  local height_offset = has_border and 2 or 0

  local config = { relative = 'editor', anchor = 'NW', border = border, style = 'minimal', noautocmd = true }
  -- - Make sure the window is shown on top of other 'mini.nvim' windows
  config.zindex = 252

  -- Compute position and dimensions based on scope
  local ref_rect = { row = has_tabline and 1 or 0, col = 0, width = max_width, height = max_height }
  local scope = state.opts.scope
  if not (scope == 'editor' or scope == 'tabpage' or scope == 'project') then
    -- NOTE: use window for "cursor" as it works when called from command line
    local winwidth, winheight = wininfo.width, wininfo.height
    local win_config = vim.api.nvim_win_get_config(0)
    local win_no_border = win_config.relative == '' or win_config.border == 'none' or win_config.border == nil
    local win_row = wininfo.winrow - (win_no_border and 1 or 0)
    local win_col = wininfo.wincol - (win_no_border and 1 or 0)
    ref_rect = { row = win_row, col = win_col, width = winwidth, height = winheight }

    -- - Nudges to not cover cursor if not 'center'
    local row_nudge = (ver == 'T' and 1 or ver == 'B' and -1 or 0)
    local col_nudge = (hor == 'L' and 1 or hor == 'R' and -1 or 0)

    if scope == 'cursor' then
      local cur_row = win_row + vim.fn.winline() - 1 + row_nudge
      local cur_col = win_col + vim.fn.wincol() - 1 + col_nudge
      ref_rect = { row = cur_row, col = cur_col, width = 1, height = 1 }
    end
    if scope == 'line' then
      local cur_row = win_row + vim.fn.winline() - 1 + row_nudge
      local cur_col = win_col + wininfo.textoff
      ref_rect = { row = cur_row, col = cur_col, width = winwidth - wininfo.textoff, height = 1 }
    end

    -- Ensure floating window does not go outside of reference rectangle
    if scope ~= 'cursor' then width = H.clamp(width, 1, ref_rect.width - width_offset) end
  end

  local ver_coef = ver == 'T' and 0 or (ver == 'M' and 0.5 or 1)
  local hor_coef = hor == 'L' and 0 or (hor == 'M' and 0.5 or 1)

  config.row = ref_rect.row + math.floor(ver_coef * (ref_rect.height - height - height_offset))
  config.col = ref_rect.col + math.floor(hor_coef * (ref_rect.width - width - width_offset))
  config.height = math.min(height, max_height - height_offset)
  config.width = math.min(width, max_width - width_offset)

  -- Set title and footer (even if empty string, to remove previous one)
  if has_border then
    local title_hl = state.opts.hide and 'MiniInputHide' or 'MiniInputPrompt'
    config.title = { { H.fit_to_displaywidth(title_text, config.width), title_hl } }
    config.title_pos = 'left'
    if vim.fn.has('nvim-0.10') == 1 then
      config.footer = { { H.fit_to_displaywidth(footer_text, config.width), 'MiniInputHint' } }
      config.footer_pos = 'right'
    end
  end

  return config
end

H.ensure_floatwin_buf = function(state, chunks)
  local buf_id = state.data.floatwin_buf_id
  if H.is_valid_buf(buf_id) then
    vim.api.nvim_buf_clear_namespace(buf_id, H.ns_id.view, 0, -1)
  else
    buf_id = vim.api.nvim_create_buf(false, true)
    H.set_buf_name(buf_id, 'content')
    vim.bo[buf_id].filetype = 'miniinput'
    state.data.floatwin_buf_id = buf_id
  end

  local text_arr, extmark_data, cur_len = {}, {}, 0
  for _, ch in ipairs(chunks) do
    table.insert(text_arr, ch[1])
    local new_len = cur_len + ch[1]:len()
    table.insert(extmark_data, { cur_len, { end_row = 0, end_col = new_len, hl_group = ch[2] } })
    cur_len = new_len
  end

  -- Show input as a single line with special chars taken care of
  vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, { H.get_chunks_text(chunks) })
  for _, ext in ipairs(extmark_data) do
    pcall(vim.api.nvim_buf_set_extmark, buf_id, H.ns_id.view, 0, ext[1], ext[2])
  end
end

H.ensure_floatwin_win = function(state, config)
  local buf_id = state.data.floatwin_buf_id
  local win_id = state.data.floatwin_win_id
  if H.is_valid_win(win_id) then
    config.noautocmd = nil
    vim.api.nvim_win_set_config(win_id, config)
  else
    win_id = vim.api.nvim_open_win(buf_id, false, config)
    vim.wo[win_id].list = vim.go.list
    vim.wo[win_id].listchars = vim.go.listchars
    vim.wo[win_id].winhighlight = 'NormalFloat:MiniInputNormal,FloatBorder:MiniInputBorder'
    vim.wo[win_id].wrap = false
    state.data.floatwin_win_id = win_id
  end

  return win_id
end

H.uiline_handle_option_values = function(state, style_was_changed)
  local win_id = vim.api.nvim_get_current_win()
  local needs_reset = win_id ~= state.data.win_id or style_was_changed
  if not (H.state_is_end(state) or needs_reset) then return end

  -- Unset all previously set option values
  H.uiline_unset_option_value(state, 'laststatus')
  H.uiline_unset_option_value(state, 'showtabline')
  H.uiline_unset_option_value(state, 'statusline', win_id)
  H.uiline_unset_option_value(state, 'tabline')
  H.uiline_unset_option_value(state, 'winbar', win_id)

  if not needs_reset then return end

  -- Cache all necessary values
  state.data.laststatus = vim.o.laststatus
  state.data.showtabline = vim.o.showtabline
  state.data.statusline = vim.wo.statusline
  state.data.status_height = H.get_curwin_info().status_height
  state.data.tabline = vim.o.tabline
  state.data.winbar = vim.wo.winbar

  state.data.win_id = win_id
end

H.uiline_unset_option_value = function(state, option_name, win_id)
  -- Make sure to not set 'statusline' if it was not previously used
  local new_val = state.data[option_name]
  if option_name == 'statusline' and (state.data.status_height or 1) == 0 and state.data.laststatus < 3 then
    new_val = nil
  end
  local option_opts = { scope = win_id ~= nil and 'local' or nil, win = win_id }
  local cur_val = vim.api.nvim_get_option_value(option_name, option_opts)
  if cur_val == state.data[option_name] then return end
  pcall(vim.api.nvim_set_option_value, option_name, new_val, option_opts)
end

-- Chunks ---------------------------------------------------------------------
H.get_chunks = function(opts, state, max_width)
  local res = opts.to_chunks(state, max_width)

  -- Validate
  local name = string.format('opts.to_chunks(state, %s)', vim.inspect(max_width))
  H.check_array_of(name, res, 'table')
  for i, ch in ipairs(res) do
    local item = string.format('%s[%d]', name, i)
    H.check_type(item .. '[1]', ch[1], 'string')
    H.check_type(item .. '[2]', ch[2], 'string')
  end

  return res
end

H.append_chunks = function(arr, new, keytrans)
  if not keytrans then return vim.list_extend(arr, new) end

  -- Sanitize chunks for view to display special keys in special way
  for _, ch in ipairs(new) do
    for s, special in string.gmatch(ch[1], '(%C*)(%c*)') do
      if s ~= '' then table.insert(arr, { s, ch[2] }) end
      if special ~= '' then table.insert(arr, { vim.fn.keytrans(special), 'MiniInputSpecial' }) end
    end
  end
end

-- Split chunks at character index
-- All chunks for text to the left of and including `at` index go to left.
-- The rest - to right. Split chunk if `at` is in between.
---@private
H.split_chunks_at = function(chunks, at)
  local left, right, cur_width = {}, {}, 0
  for _, ch in ipairs(chunks) do
    local w = vim.fn.strchars(ch[1])
    local to_left, to_right = at - cur_width, cur_width + w - at
    cur_width = cur_width + w

    if to_right <= 0 then table.insert(left, ch) end
    if to_left <= 0 then table.insert(right, ch) end
    if to_left > 0 and to_right > 0 then
      table.insert(left, { vim.fn.strcharpart(ch[1], 0, to_left), ch[2] })
      table.insert(right, { vim.fn.strcharpart(ch[1], to_left), ch[2] })
    end
  end

  return left, right
end

H.fit_chunks_to_displaywidth = function(chunks, width, center_offset)
  local chunks_text = H.get_chunks_text(chunks)
  local chunks_width = vim.fn.strdisplaywidth(chunks_text)
  if width == nil or chunks_width < width then return chunks end

  -- Show center with as much and as equally as possible to left and right
  local right = math.min(chunks_width, math.floor(center_offset + 0.5 * width))
  local left = math.max(1, right - width + 1)
  right = left + math.min(width, chunks_width) - 1

  -- Convert display cols into char cols (matters with double width characters)
  local left_char, right_char, cur_w = nil, nil, 0
  for i = 1, vim.fn.strchars(chunks_text) do
    local w = vim.fn.strdisplaywidth(vim.fn.strcharpart(chunks_text, i - 1, 1))

    -- `left_char` = first char id with end at `left` or more, but only if the
    -- start is within `width` from center offset (otherwise - next char).
    if left_char == nil and left <= (cur_w + w) then
      local is_within_width_from_center = center_offset - cur_w <= width
      left_char = i + (is_within_width_from_center and 0 or 1)
      -- Update `left` display column to point at left character start
      left = cur_w + (is_within_width_from_center and 0 or w) + 1
    end

    -- `right_char` = last char id with end at most `width` from updated `left`
    if (cur_w + w - left + 1) <= width then right_char = i end

    cur_w = cur_w + w
  end

  local res, _ = H.split_chunks_at(chunks, right_char)
  _, res = H.split_chunks_at(res, left_char - 1)
  return res
end

H.get_chunks_text = function(chunks)
  return table.concat(vim.tbl_map(function(ch) return ch[1] end, chunks))
end

H.get_chunks_displaywidth = function(chunks) return vim.fn.strdisplaywidth(H.get_chunks_text(chunks)) end

-- Highlight ranges -----------------------------------------------------------
--- Add new proper highlight range on top of an array of ranges that don't
--- intersect and are orderd from left to right.
---@private
H.insert_hl_range = function(arr, max_to, from, to, hl)
  -- Insert only proper range that fits constraints
  if from == nil or to == nil or to < 1 or from > max_to then return arr end
  from, to = H.clamp(from, 1, max_to), H.clamp(to, 1, max_to)
  if from > to then return arr end

  local res, was_inserted = {}, false
  for _, cur in ipairs(arr) do
    -- No overlap
    if cur.to < from or to < cur.from then table.insert(res, cur) end
    -- Overlap with outside left part of current
    if cur.from < from and from <= cur.to then table.insert(res, { from = cur.from, to = from - 1, hl = cur.hl }) end
    -- Overlap
    if from <= cur.to and cur.from <= to and not was_inserted then
      table.insert(res, { from = from, to = to, hl = hl })
      was_inserted = true
    end
    -- Overlap with outside right part of current
    if cur.from <= to and to < cur.to then table.insert(res, { from = to + 1, to = cur.to, hl = cur.hl }) end
  end
  if not was_inserted then table.insert(res, { from = from, to = to, hl = hl }) end
  return res
end

H.make_ui_select_hl_fun = function(hl_fun)
  if not vim.is_callable(hl_fun) then return end

  local hl_handler = H.get_config().handlers.highlight or MiniInput.default_highlight
  return function(state)
    local input = state.input
    local hl_ranges = hl_fun(input)
    if not H.islist(hl_ranges) then hl_ranges = {} end

    -- Convert from Vim ranges `r` to 'mini.input' ranges:
    -- - r[1] - zero-based byte index at first multibyte start
    -- - r[2] - zero-based byte index one more than last multibyte end
    -- - 'mini.input' ranges: named fields, 1-based char indexes
    local highlight = {}
    for i, r in ipairs(hl_ranges) do
      if type(r) == 'table' and type(r[1]) == 'number' and type(r[2]) == 'number' and type(r[3]) == 'string' then
        highlight[i] = { from = vim.fn.charidx(input, r[1]) + 1, to = vim.fn.charidx(input, r[2]), hl = r[3] }
      end
    end
    state.highlight = highlight

    -- Combine with user-defined handler, like to show added completion chars
    hl_handler(state)
  end
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.input) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.check_one_of = function(name, x, choices)
  if vim.tbl_contains(choices, x) then return end
  local choices_string = table.concat(vim.tbl_map(vim.inspect, choices), ', ')
  local msg = string.format('`%s` should be one of %s', name, choices_string)
  H.error(msg)
end

H.check_array_of = function(name, x, ref_type)
  if not H.islist(x) then H.error('`' .. name .. '` should be array') end
  for i, k in ipairs(x) do
    if type(k) ~= ref_type then H.error('Every `' .. name .. '` item should be ' .. ref_type) end
  end
end

H.set_buf_name = function(buf_id, name) vim.api.nvim_buf_set_name(buf_id, 'miniinput://' .. buf_id .. '/' .. name) end

H.notify = function(msg, level_name) vim.notify('(mini.input) ' .. msg, vim.log.levels[level_name]) end

H.getcharstr = function(lmap, allow_ctrl_c)
  H.cache.is_in_getcharstr = true
  local ok, char = H.safe_fn_getcharstr()
  H.cache.is_in_getcharstr = nil

  -- Cache possible error if it doesn't come from pressing <C-c>
  local is_ctrl_c = (not ok and char == 'Keyboard interrupt') or (ok and char == '\3')
  if not ok and not is_ctrl_c then H.cache_error(H.state, char) end

  -- Terminate if no input or on hard-coded <C-c>
  if allow_ctrl_c and is_ctrl_c then return '\3' end
  if not ok or char == '' or char == '\3' then return nil end

  -- Respect language mappings only if needed
  return vim.o.iminsert == 0 and char or ((lmap or {})[char] or char)
end

-- TODO: Remove after compatibility with Neovim=0.10 is dropped
H.safe_fn_getcharstr = function() return pcall(vim.fn.getcharstr, -1, { cursor = 'hide' }) end
if vim.fn.has('nvim-0.11') == 0 then H.safe_fn_getcharstr = function() return pcall(vim.fn.getcharstr) end end

H.getcharstr_many = function(n, early_stop)
  local res = {}
  for i = 1, n do
    res[i] = H.getcharstr()
    if res[i] == nil or early_stop[res[i]] then return nil end
  end
  return table.concat(res)
end

H.is_special_char = function(x)
  -- Remove allowed character that are specially translated
  x = x:gsub('[%s<]', '')
  return vim.fn.keytrans(x) ~= x
end

H.cache_error = function(state, msg)
  if not vim.startswith(msg, '(mini.input) ') then msg = '(mini.input) ' .. msg end
  if H.state == nil then error(msg) end
  state.errmsg = state.errmsg or msg
  state.status = 'cancel'
end

H.redraw = function() vim.cmd('redraw!') end

H.clamp = function(x, from, to) return math.min(math.max(x, from), to) end

H.is_valid_buf = function(buf_id) return type(buf_id) == 'number' and vim.api.nvim_buf_is_valid(buf_id) end

H.is_valid_win = function(win_id) return type(win_id) == 'number' and vim.api.nvim_win_is_valid(win_id) end

H.is_valid_char = function(char) return vim.fn.strchars(char) == 1 and vim.fn.char2nr(char) > 31 end

H.get_curwin_info = function()
  local res = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1]
  -- TODO: Remove after compatibility with Neovim=0.11 is dropped
  res.status_height = res.status_height or (vim.api.nvim_win_get_config(0).relative == '' and 1 or 0)
  return res
end

H.fit_to_displaywidth = function(text, width)
  if vim.fn.strdisplaywidth(text) <= width then return text end
  for i = 1, vim.fn.strchars(text) do
    local truncated = '…' .. vim.fn.strcharpart(text, i)
    if vim.fn.strdisplaywidth(truncated) <= width then return truncated end
  end
  return ''
end

-- TODO: Remove after compatibility with Neovim=0.9 is dropped
H.islist = vim.fn.has('nvim-0.10') == 1 and vim.islist or vim.tbl_islist

H.get_lmap = function()
  local lmap = {}
  for _, map in ipairs(vim.fn.maplist()) do
    -- NOTE: Account only for characters that resolve to proper input character
    local is_query_lmap = map.mode == 'l' and H.is_valid_char(map.rhs)
    if is_query_lmap then lmap[map.lhs] = map.rhs end
  end
  return lmap
end
if vim.fn.has('nvim-0.10') == 0 then H.get_lmap = function() return {} end end

-- A copy of `vim.deepcopy()` that doesn't error on userdata and threads
H.copy_tables = function(x)
  return type(x) == 'table' and setmetatable(vim.tbl_map(H.copy_tables, x), getmetatable(x)) or x
end

MiniInput.default_view = MiniInput.gen_view.floatwin()
return MiniInput
