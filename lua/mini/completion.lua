--- *mini.completion* Completion and signature help
---
--- MIT License Copyright (c) 2021 Evgeni Chasnovski

--- Key design ideas:
--- - Have an async (with customizable "debounce" delay) "two-stage chain
---   completion": first try to get completion items from LSP client (if set
---   up) and if no result, fallback to custom action.
---
--- - Managing completion is done as much with Neovim's built-in tools as
---   possible. |popupmenu-completion| is used to show completion suggestions.
---
--- Features:
--- - Two-stage chain completion:
---     - First stage is an LSP completion implemented via
---       |MiniCompletion.completefunc_lsp()|. It should be set up as either
---       |'completefunc'| or |'omnifunc'|. It tries to get completion items from
---       LSP client (via 'textDocument/completion' request). Custom
---       preprocessing of response items is possible (with
---       `MiniCompletion.config.lsp_completion.process_items`), for example
---       with fuzzy matching. By default items directly starting with completed
---       word are kept and are sorted according to LSP specification.
---       Supports `additionalTextEdits`, like auto-import and others (see 'Notes'),
---       and snippet items (best results require |mini.snippets| dependency).
---     - If first stage is not set up or resulted into no candidates, fallback
---       action is executed. The most tested actions are Neovim's built-in
---       insert completion (see |ins-completion|).
---
--- - Automatic display in floating window of completion item info (via
---   'completionItem/resolve' request) and signature help (with highlighting
---   of active parameter if LSP server provides such information).
---   Signature help is shown if character to cursor's left is a dedicated trigger
---   character (configured in `signatureHelpProvider.triggerCharacters` of LSP
---   server capabilities) and updated without delay if is currently opened.
---   Already shown window for signature help is fixed and is closed when there
---   is nothing to show, its text is different, or when leaving Insert mode.
---   Scroll in either info/signature window with `<C-f>` / `<C-b>` (by default).
---
--- - Automatic actions are done after some configurable amount of delay. This
---   reduces computational load and allows fast typing (completion and
---   signature help) and item selection (item info)
---
--- - Force two-stage/fallback completion (`<C-Space>` / `<A-Space>` by default).
---
--- - Customizable highlighting of LSP items. Requires Neovim>=0.11.
---   Use `config.lsp_completion.process_items` to set dedicated highlight group
---   in supported fields:
---     - <abbr_hlgroup> - item label (`abbr` in terms of |complete-items|).
---       By default only checks if item is marked as deprecated and sets
---       `MiniCompletionDeprecated` highlight group.
---     - <kind_hlgroup> - LSP kind ("Function", "Keyword", etc.). By default
---       uses "lsp" category of |mini.icons| (if enabled).
---
--- What it doesn't do:
--- - Many configurable sources.
--- - Automatic mapping of `<CR>`, `<Tab>`, etc. Those tend to have highly
---   variable user expectations. See 'Helpful mappings' for suggestions or
---   use |MiniKeymap.map_multistep()| with `"pmenu_*"` built-in steps.
---
--- # Dependencies ~
---
--- Suggested dependencies (provide extra functionality, will work without them):
---
--- - Enabled |mini.icons| module to highlight LSP kind (requires Neovim>=0.11).
---   If absent, |MiniCompletion.default_process_items()| does not add highlighting.
---   Also take a look at |MiniIcons.tweak_lsp_kind()|.
--- - Enabled |mini.snippets| module for better snippet handling (much recommended).
---   If absent and custom snippet insert is not configured, |vim.snippet.expand()|
---   is used on Neovim>=0.10 (nothing extra is done on earlier versions).
---   See |MiniCompletion.default_snippet_insert()|.
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.completion').setup({})`
--- (replace `{}` with your `config` table). It will create global Lua table
--- `MiniCompletion` which you can use for scripting or manually (with
--- `:lua MiniCompletion.*`).
---
--- See |MiniCompletion.config| for `config` structure and default values.
---
--- You can override runtime config settings locally to buffer inside
--- `vim.b.minicompletion_config` which should have same structure as
--- `MiniCompletion.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- # Suggested option values ~
---
--- Some options are set automatically (if not set before |MiniCompletion.setup()|):
--- - 'completeopt' is set to "menuone,noselect" for less intrusive popup.
---   To enable fuzzy matching, manually set to "menuone,noselect,fuzzy". Consider
---   also adding "nosort" flag to preserve initial order when filtering.
--- - 'shortmess' is appended with "c" flag for silent <C-n> fallback.
--- - 'complete' gets removed "t" flag (if fallback action is default), as it
---   leads to visible lags.
---
--- # Snippets ~
---
--- As per LSP specification, some completion items can be supplied in the form of
--- snippet - a template with both pre-defined text and places (called "tabstops")
--- for user to interactively change/add text during snippet session.
---
--- In 'mini.completion' items that will insert snippet have "S" symbol shown in
--- the popup (as part of `menu` in |complete-items|). To actually insert a snippet:
--- - Select an item via <C-n> / <C-p>. This will insert item's label (usually not
---   full snippet) first to reduce visual flicker. The full snippet text will be
---   shown in info window if LSP server doesn't provide its own info for an item.
--- - Press <C-y> (|complete_CTRL-Y|) or attempt inserting a non-keyword character
---   (like <CR>; new character will be removed). It will clear text from previous
---   step, set cursor, and call `lsp_completion.snippet_insert` with snippet text.
--- - Press <C-e> (|complete_CTRL-E|) to cancel snippet insert and properly end
---   completion.
---
--- See |MiniCompletion.default_snippet_insert()| for overview of how to work with
--- inserted snippets.
---
--- Notes:
--- - To stop LSP server from suggesting snippets, disable (set to `false`) the
---   following capability during LSP server start:
---   `textDocument.completion.completionItem.snippetSupport`.
--- - If snippet body doesn't contain tabstop, variable, tab, or newline,
---   `lsp_completion.snippet_insert` is not called and text is inserted as-is.
---
--- # Notes ~
---
--- - A more appropriate (albeit slightly advanced) LSP completion setup is to set
---   it not on every |BufEnter| event (default), but on every attach of LSP client.
---   To do that:
---     - Use in |MiniCompletion.setup()| config: >lua
---
---       lsp_completion = { source_func = 'omnifunc', auto_setup = false }
--- <
---     - Set 'omnifunc' option to exactly `v:lua.MiniCompletion.completefunc_lsp`
---       for every client attach in an |LspAttach| event. Like this: >lua
---
---       local on_attach = function(args)
---         vim.bo[args.buf].omnifunc = 'v:lua.MiniCompletion.completefunc_lsp'
---       end
---       vim.api.nvim_create_autocmd('LspAttach', { callback = on_attach })
--- <
---   This setup is not default to allow simultaneous usage of filetype-specific
---   'omnifunc' (with manual |i_CTRL-X_CTRL-O|) and automated LSP completion.
---
--- - Use |MiniCompletion.get_lsp_capabilities()| to get/set information about part
---   of LSP specification supported by module. See its help for usability notes.
---
--- - Uses `vim.lsp.protocol.CompletionItemKind` map in LSP step to show a readable
---   version of item's kind. Modify it directly to change what is displayed.
---   If you have |mini.icons| enabled, take a look at |MiniIcons.tweak_lsp_kind()|.
---
--- - If you have trouble using custom (overridden) |vim.ui.input()|, disable
---   'mini.completion' for input buffer (usually based on its 'filetype').
---
--- # Comparisons ~
---
--- - [hrsh7th/nvim-cmp](https://github.com/hrsh7th/nvim-cmp):
---     - Implements own popup menu to show completion candidates, while this
---       module reuses |ins-completion-menu|.
---     - Has more complex design which allows multiple sources, each in a form of
---       a separate plugin. This module has two built-in: LSP and fallback.
---     - Requires separate plugin for automated signature help.
---     - Implements own "ghost text" feature, while this module does not.
---
--- - [Saghen/blink.cmp](https://github.com/Saghen/blink.cmp):
---     - Mostly similar to 'nvim-cmp' comparison: provides more features at the
---       cost of more code and config complexity, while this module is designed
---       to provide only a handful of "enough" features while relying on Neovim's
---       built-in capabilities as much as possible.
---     - Both provide automated signature help out of the box.
---
--- # Helpful mappings ~
---
--- If there is |mini.keymap| available, prefer using |MiniKeymap.map_multistep()|
--- with `"pmenu_*"` built-in steps. See |MiniKeymap-examples| for examples.
---
--- To use `<Tab>` and `<S-Tab>` for navigation through completion list, make
--- these mappings: >lua
---
---   local imap_expr = function(lhs, rhs)
---     vim.keymap.set('i', lhs, rhs, { expr = true })
---   end
---   imap_expr('<Tab>',   [[pumvisible() ? "\<C-n>" : "\<Tab>"]])
---   imap_expr('<S-Tab>', [[pumvisible() ? "\<C-p>" : "\<S-Tab>"]])
--- <
--- To get more consistent behavior of `<CR>`, you can use this template in
--- your 'init.lua' to make customized mapping: >lua
---
---   _G.cr_action = function()
---     -- If there is selected item in popup, accept it with <C-y>
---     if vim.fn.complete_info()['selected'] ~= -1 then return '\25' end
---     -- Fall back to plain `<CR>`. You might want to customize according
---     -- to other plugins. For example if 'mini.pairs' is set up, replace
---     -- next line with `return MiniPairs.cr()`
---     return '\r'
---   end
---
---   vim.keymap.set('i', '<CR>', 'v:lua.cr_action()', { expr = true })
--- <
--- # Highlight groups ~
---
--- - `MiniCompletionActiveParameter` - signature active parameter.
--- - `MiniCompletionDeprecated` - candidates that marked as deprecated.
--- - `MiniCompletionInfoBorderOutdated` - info window border when text is outdated
---   due to explicit delay during fast movement through candidates.
---
--- To change any highlight group, set it directly with |nvim_set_hl()|.
---
--- # Disabling ~
---
--- To disable, set `vim.g.minicompletion_disable` (globally) or
--- `vim.b.minicompletion_disable` (for a buffer) to `true`. Considering high
--- number of different scenarios and customization intentions, writing exact
--- rules for disabling module's functionality is left to user. See
--- |mini.nvim-disabling-recipes| for common recipes.
---@tag MiniCompletion

--- To allow user customization, certain |User| autocommand events are
--- triggered under common circumstances:
---
--- - Info and signature help window:
---     - `MiniCompletionWindowOpen` - after opening new window.
---     - `MiniCompletionWindowUpdate` - after updating existing window.
---
---     Each event's |event-data| table contains `kind` (one of "info" or "signature")
---     and `win_id` (affected window identifier) fields.
---@tag MiniCompletion-events

-- Overall implementation design:
-- - Completion:
--     - On `InsertCharPre` event try to start auto completion. If needed,
--       start timer which after delay will start completion process. Stop this
--       timer if it is not needed.
--     - When timer is activated, first execute LSP source (if set up and there
--       is an active LSP client) by calling built-in complete function
--       (`completefunc` or `omnifunc`) which tries LSP completion by
--       asynchronously sending LSP 'textDocument/completion' request to all
--       LSP clients. When all are done, execute callback which processes
--       results, stores them in LSP cache and reruns built-in complete
--       function which produces completion popup.
--     - If previous step didn't result into any completion, execute (in Insert
--       mode and if no popup) fallback action.
-- - Documentation:
--     - On `CompleteChanged` start auto info with similar to completion timer
--       pattern.
--     - If timer is activated, try these sources of item info:
--         - 'info' field of completion item (see `:h complete-items`).
--         - 'documentation' field of LSP's previously returned result.
--         - 'documentation' field in result of asynchronous
--           'completeItem/resolve' LSP request.
--     - If info doesn't consist only from whitespace, show floating window
--       with its content. Its dimensions and position are computed based on
--       current state of Neovim's data and content itself (which will be
--       displayed wrapped with `linebreak` option).
-- - Signature help (similar to item info):
--     - On `CursorMovedI` start auto signature (if there is any active LSP
--       client) with similar to completion timer pattern. Better event might
--       be `InsertCharPre` but there are issues with 'autopair-type' plugins.
--       Update immediately if already shown or after delay if character to the
--       left is signature help trigger (after delay has passed).
--     - If timer is activated, send 'textDocument/signatureHelp' request to
--       all LSP clients. On callback, process their results. Window is opened
--       if not already with the same text (its characteristics are computed
--       similar to item info). For every LSP client it shows only active
--       signature (in case there are many). If LSP response has data about
--       active parameter, it is highlighted with
--       `MiniCompletionActiveParameter` highlight group.

-- Module definition ==========================================================
local MiniCompletion = {}
local H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniCompletion.config|.
---
---@usage >lua
---   require('mini.completion').setup() -- use default config
---   -- OR
---   require('mini.completion').setup({}) -- replace {} with your config table
--- <
MiniCompletion.setup = function(config)
  -- Export module
  _G.MiniCompletion = MiniCompletion

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Define behavior
  H.create_autocommands(config)

  -- Create default highlighting
  H.create_default_hl()
end

--- Defaults ~
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
MiniCompletion.config = {
  -- Delay (debounce type, in ms) between certain Neovim event and action.
  -- This can be used to (virtually) disable certain automatic actions by
  -- setting very high delay time (like 10^7).
  delay = { completion = 100, info = 100, signature = 50 },

  -- Configuration for action windows:
  -- - `height` and `width` are maximum dimensions.
  -- - `border` defines border (as in `nvim_open_win()`; default "single").
  window = {
    info = { height = 25, width = 80, border = nil },
    signature = { height = 25, width = 80, border = nil },
  },

  -- Way of how module does LSP completion
  lsp_completion = {
    -- `source_func` should be one of 'completefunc' or 'omnifunc'.
    source_func = 'completefunc',

    -- `auto_setup` should be boolean indicating if LSP completion is set up
    -- on every `BufEnter` event.
    auto_setup = true,

    -- A function which takes LSP 'textDocument/completion' response items
    -- (each with `client_id` field for item's server) and word to complete.
    -- Output should be a table of the same nature as input. Common use case
    -- is custom filter/sort. Default: `default_process_items`
    process_items = nil,

    -- A function which takes a snippet as string and inserts it at cursor.
    -- Default: `default_snippet_insert` which tries to use 'mini.snippets'
    -- and falls back to `vim.snippet.expand` (on Neovim>=0.10).
    snippet_insert = nil,
  },

  -- Fallback action as function/string. Executed in Insert mode.
  -- To use built-in completion (`:h ins-completion`), set its mapping as
  -- string. Example: set '<C-x><C-l>' for 'whole lines' completion.
  fallback_action = '<C-n>',

  -- Module mappings. Use `''` (empty string) to disable one. Some of them
  -- might conflict with system mappings.
  mappings = {
    -- Force two-step/fallback completions
    force_twostep = '<C-Space>',
    force_fallback = '<A-Space>',

    -- Scroll info/signature window down/up. When overriding, check for
    -- conflicts with built-in keys for popup menu (like `<C-u>`/`<C-o>`
    -- for 'completefunc'/'omnifunc' source function; or `<C-n>`/`<C-p>`).
    scroll_down = '<C-f>',
    scroll_up = '<C-b>',
  },
}
--minidoc_afterlines_end

-- Module functionality =======================================================
--- Run two-stage completion
---
---@param fallback boolean|nil Whether to use fallback completion. Default: `true`.
---@param force boolean|nil Whether to force update of completion popup.
---   Default: `true`.
MiniCompletion.complete_twostage = function(fallback, force)
  if H.is_disabled() then return end
  if fallback == nil then fallback = true end
  if force == nil then force = true end

  H.stop_completion()
  H.completion.fallback, H.completion.force = fallback, force
  H.trigger_twostep()
end

--- Run fallback completion
MiniCompletion.complete_fallback = function()
  if H.is_disabled() then return end

  H.stop_completion()
  H.completion.fallback, H.completion.force = true, true
  H.trigger_fallback()
end

--- Scroll in info/signature window
---
--- Designed to be used in |:map-<expr>|.
--- Scrolling is done as if |CTRL-F| and |CTRL-B| is pressed inside target window.
--- Used in default `config.mappings.scroll_xxx` mappings.
---
---@param direction string One of `"down"` or `"up"`.
---
---@return boolean Whether scroll is scheduled to be done.
MiniCompletion.scroll = function(direction)
  if not (direction == 'down' or direction == 'up') then H.error('`direction` should be one of "up" or "down"') end
  local win_id = H.is_valid_win(H.info.win_id) and H.info.win_id
    or (H.is_valid_win(H.signature.win_id) and H.signature.win_id or nil)
  if win_id == nil then return false end

  -- Schedule execution as scrolling is not allowed in expression mappings
  local key = direction == 'down' and '\6' or '\2'
  vim.schedule(function()
    if not H.is_valid_win(win_id) then return end
    vim.api.nvim_win_call(win_id, function() vim.cmd('noautocmd normal! ' .. key) end)
  end)
  return true
end

--- Stop actions
---
--- This stops currently active (because of module delay or LSP answer delay)
--- actions.
---
--- Designed to be used with |autocmd|. No need to use it directly, everything
--- is setup in |MiniCompletion.setup()|.
---
---@param actions table|nil Array containing any of 'completion', 'info', or
---   'signature' string. Default: array containing all of them.
MiniCompletion.stop = function(actions)
  actions = actions or { 'completion', 'info', 'signature' }
  for _, n in ipairs(actions) do
    H.stop_actions[n]()
  end
end

--- Module's |complete-functions|
---
--- This is the main function which enables two-stage completion. It should be
--- set as one of |'completefunc'| or |'omnifunc'|.
---
--- No need to use it directly, everything is setup in |MiniCompletion.setup()|.
MiniCompletion.completefunc_lsp = function(findstart, base)
  -- Early return
  if not H.has_lsp_clients('completionProvider') or H.completion.lsp.status == 'sent' then
    return findstart == 1 and -3 or {}
  end

  -- NOTE: having code for request inside this function enables its use
  -- directly with `<C-x><...>` and as a reaction to `<BS>`.
  if H.completion.lsp.status ~= 'received' then
    -- NOTE: it is CRUCIAL to make LSP request on the first call to
    -- 'complete-function' (as in Vim's help). This is due to the fact that
    -- cursor line and position are different on the first and second calls to
    -- 'complete-function'. For example, when calling this function at the end
    -- of the line '  he', cursor position on the first call will be
    -- (<linenum>, 4) and line will be '  he' but on the second call -
    -- (<linenum>, 2) and '  ' (because 2 is a column of completion start).
    --
    -- This request is not executed on second call because it returns `-3` on
    -- first call (which means cancel and leave completion mode).
    H.make_completion_request()

    -- End completion and wait for LSP callback to re-trigger this
    return findstart == 1 and -3 or {}
  else
    if findstart == 1 then
      local from, to = H.get_completion_range(H.completion.lsp.result)
      -- Cache initial completion state to revert to it when inserting snippet
      -- NOTE: Track only length of base for performance, since this is enough
      H.completion.init_base = { lnum = from[1], col = from[2], length = math.max(to[2] - from[2], 0) }
      return from[2]
    end

    local is_incomplete = false
    local all_items = H.process_lsp_response(H.completion.lsp.result, function(response, client_id)
      is_incomplete = is_incomplete or (response.isIncomplete == true)
      -- Response can be `CompletionList` with 'items' field plus their
      -- defaults or `CompletionItem[]`
      local items = H.table_get(response, { 'items' }) or response
      if type(items) ~= 'table' then return {} end

      items = H.apply_item_defaults(items, response.itemDefaults)
      for _, item in ipairs(items) do
        item.client_id = client_id
      end
      return items
    end)

    -- Process items
    local process_items = H.get_config().lsp_completion.process_items or MiniCompletion.default_process_items
    all_items = process_items(all_items, base)
    local candidates = H.lsp_completion_response_items_to_complete_items(all_items)

    H.completion.lsp.status = 'done'
    H.completion.lsp.is_incomplete = is_incomplete

    -- Maybe trigger fallback action
    if vim.tbl_isempty(candidates) and H.completion.fallback then return H.trigger_fallback() end

    -- Track from which source is current popup
    H.completion.source = 'lsp'
    return candidates
  end
end

--- Default processing of LSP items
---
--- Steps:
--- - Filter and sort items according to supplied method.
--- - Arrange items further by completion item kind according to their priority.
--- - Add `MiniCompletionDeprecated` <abbr_hlgroup> if item is marked as deprecated.
--- - If |mini.icons| is enabled, add <kind_hlgroup> based on the "lsp" category.
---
--- Example of forcing fuzzy matching, filtering out `Text` items, and putting
--- `Snippet` items last: >lua
---
---   local kind_priority = { Text = -1, Snippet = 99 }
---   local opts = { filtersort = 'fuzzy', kind_priority = kind_priority }
---   local process_items = function(items, base)
---     return MiniCompletion.default_process_items(items, base, opts)
---   end
---   require('mini.completion').setup({
---     lsp_completion = { process_items = process_items },
---   })
--- <
---@param items table Array of items from LSP response.
---@param base string Base for which completion is done. See |complete-functions|.
---@param opts table|nil Options. Possible fields:
---   - <filtersort> `(string|function)` - method of filtering and sorting items.
---     If string, should be one of the following:
---       - `'prefix'` - filter out items not starting with `base`, sort according
---         to LSP specification. Use `filterText` and `sortText` respectively with
---         fallback to `label`.
---       - `'fuzzy'` - filter and sort with |matchfuzzy()| using `filterText`.
---       - `'none'` - no filter and no sort.
---     If callable, should take `items` and `base` arguments and return items array.
---     Default: `'fuzzy'` if 'completeopt' contains "fuzzy", `'prefix'` otherwise.
---   - <kind_priority> `(table)` - map of completion item kinds (like `Variable`,
---     `Snippet`; see string keys of `vim.lsp.protocol.CompletionItemKind`) to
---     their numerical priority. It will be used after applying <filtersort> to
---     arrange by completion item kind: items with negative priority kinds will
---     be filtered out, the rest are sorted by decreasing priority (preserving
---     order in case of same priority).
---     Priorities can be any number, only matters how they compare to each other.
---     Value 100 is used for missing kinds (i.e. not all can be supplied).
---     Default: `{}` (all equal priority).
---
---@return table Array of processed items from LSP response.
MiniCompletion.default_process_items = function(items, base, opts)
  opts = opts or {}

  -- Filter+sort (important with frequent `isIncomplete`)
  local fs = opts.filtersort or (vim.o.completeopt:find('fuzzy') ~= nil and 'fuzzy' or 'prefix')
  if type(fs) == 'string' then fs = H.filtersort_methods[fs] end
  if not vim.is_callable(fs) then H.error('`filtersort` should be callable or one of "prefix", "fuzzy", "none"') end
  local res = fs(items, base)

  -- Arrange by kind
  if opts.kind_priority ~= nil then res = H.lsp_arrange_by_kind(res, opts.kind_priority) end

  -- Add custom highlighting
  local add_abbr_hlgroup = H.make_add_abbr_hlgroup()
  local add_kind_hlgroup = H.make_add_kind_hlgroup()
  for _, item in ipairs(res) do
    add_abbr_hlgroup(item)
    add_kind_hlgroup(item)
  end
  return res
end

--- Default snippet insert
---
--- Order of preference:
--- - Use |mini.snippets| if set up (i.e. after `require('mini.snippets').setup()`).
--- - Use |vim.snippet.expand()| on Neovim>=0.10
--- - Add snippet text at cursor as is.
---
--- After snippet is inserted, user is expected to navigate/jump between dedicated
--- places (tabstops) to adjust inserted text as needed:
--- - |mini.snippets| by default uses <C-l> / <C-h> to jump to next/previous tabstop.
---   Can be adjusted in `mappings` of |MiniSnippets.config|.
--- - |vim.snippet| on Neovim=0.10 requires manually created mappings for jumping
---   between tabstops (see |vim.snippet.jump()|). Neovim>=0.11 sets them up
---   automatically to <Tab> / <S-Tab> (if not overridden by user).
---
--- End session by navigating all the way to the last tabstop. In 'mini.snippets':
--- - Also make any text edit or exit Insert mode to end the session. This allows
---   smoother navigation to previous tabstops in case of a lately spotted typo.
--- - Press `<C-c>` to force session stop.
---
---@param snippet string Snippet body to insert at cursor.
---
---@seealso - |MiniSnippets-session| if 'mini.snippets' is set up.
--- - |vim.snippet| for Neovim's built-in snippet engine.
MiniCompletion.default_snippet_insert = function(snippet)
  if _G.MiniSnippets then
    local insert = MiniSnippets.config.expand.insert or MiniSnippets.default_insert
    return insert({ body = snippet })
  end
  if vim.fn.has('nvim-0.10') == 1 then return vim.snippet.expand(snippet) end

  local pos, lines = vim.api.nvim_win_get_cursor(0), vim.split(snippet, '\n')
  vim.api.nvim_buf_set_text(0, pos[1] - 1, pos[2], pos[1] - 1, pos[2], lines)
  local n = #lines
  local new_pos = n == 1 and { pos[1], pos[2] + lines[n]:len() } or { pos[1] + n - 1, lines[n]:len() }
  vim.api.nvim_win_set_cursor(0, new_pos)
end

--- Get client LSP capabilities
---
--- Possible usages:
--- - On Neovim>=0.11 via |vim.lsp.config()|: >lua
---
---   vim.lsp.config('*', {capabilities = MiniCompletion.get_lsp_capabilities()})
--- <
--- - Together with |vim.lsp.protocol.make_client_capabilities()| to get the full
---   client capabilities (use |vim.tbl_deep_extend()| to merge tables).
---
--- - Manually execute `:=MiniCompletion.get_lsp_capabilities()` to see the info.
---
--- Notes:
--- - It declares completion resolve support for `'additionalTextEdits'` (usually
---   used for something like auto-import feature), as it is usually a more robust
---   choice for various LSP servers. As a consequence, this requires selecting
---   completion item and waiting for `config.delay.info` milliseconds plus server
---   response time (i.e. until information window shows relevant text).
---   To not have to wait after an item selection and if the server handles absent
---   `'additionalTextEdits'` well, set `opts.resolve_additional_text_edits = false`.
---
---@param opts table|nil Options. Possible fields:
---   - <resolve_additional_text_edits> `(boolean)` - whether to declare
---     `'additionalTextEdits'` as possible to resolve in `'completionitem/resolve'`
---     requrest. See above "Notes" section.
---     Default: `true`.
---
---@return table Data about LSP capabilities supported by 'mini.completion'. Has same
---   structure as relevant parts of |vim.lsp.protocol.make_client_capabilities()|.
---
---@seealso Structures of `completionClientCapabilities` and `signatureHelpClientCapabilities`
--- at https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification
MiniCompletion.get_lsp_capabilities = function(opts)
  opts = vim.tbl_extend('force', { resolve_additional_text_edits = true }, opts or {})

  local resolve_support = { 'detail', 'documentation' }
  if opts.resolve_additional_text_edits then table.insert(resolve_support, 1, 'additionalTextEdits') end

  local tag_valueset = vim.fn.has('nvim-0.11') == 1 and { vim.lsp.protocol.CompletionTag.Deprecated } or {}

  return {
    textDocument = {
      -- https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#completionClientCapabilities
      completion = {
        dynamicRegistration = false,
        completionItem = {
          snippetSupport = true,
          commitCharactersSupport = false,
          documentationFormat = { 'markdown', 'plaintext' },
          deprecatedSupport = true,
          preselectSupport = false,
          tagSupport = { valueSet = tag_valueset },
          insertReplaceSupport = true,
          resolveSupport = { properties = resolve_support },
          insertTextModeSupport = { valueSet = { 1 } },
          labelDetailsSupport = true,
        },
        completionItemKind = {
          valueSet = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25 },
        },
        contextSupport = true,
        insertTextMode = 1,
        completionList = {
          itemDefaults = { 'commitCharacters', 'editRange', 'insertTextFormat', 'insertTextMode', 'data' },
        },
      },
      -- https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#signatureHelpClientCapabilities
      signatureHelp = {
        dynamicRegistration = false,
        signatureInformation = {
          documentationFormat = { 'markdown', 'plaintext' },
          parameterInformation = {
            labelOffsetSupport = true,
          },
          activeParameterSupport = true,
        },
        contextSupport = false,
      },
    },
  }
end

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniCompletion.config)

-- Track Insert mode changes
H.text_changed_id = 0

-- Namespace for highlighting
H.ns_id = vim.api.nvim_create_namespace('MiniCompletion')

-- Commonly used key sequences
H.keys = {
  completefunc = vim.api.nvim_replace_termcodes('<C-x><C-u>', true, false, true),
  omnifunc = vim.api.nvim_replace_termcodes('<C-x><C-o>', true, false, true),
  ctrl_n = vim.api.nvim_replace_termcodes('<C-g><C-g><C-n>', true, false, true),
}

-- Flags for whether there is support for dedicated options
H.has_no_winborder = vim.fn.has('nvim-0.11') == 0
H.has_pumborder = vim.fn.exists('+pumborder') == 1 -- Neovim>=0.12

-- Caches for different actions -----------------------------------------------
-- Field `lsp` is a table describing state of all used LSP requests. It has the
-- following structure:
-- - id: identifier (consecutive numbers).
-- - status: one of 'sent', 'received', 'done', 'canceled'
-- - is_incomplete: whether request was incomplete and require recomputing
-- - result: result of request.
-- - cancel_fun: function which cancels current request.

-- Cache for completion
H.completion = {
  fallback = true,
  force = false,
  source = nil,
  text_changed_id = 0,
  timer = vim.loop.new_timer(),
  lsp = { id = 0, status = nil, is_incomplete = false, result = nil, resolved = {}, cancel_fun = nil, context = nil },
  init_base = { lnum = nil, col = nil, length = nil },
}

-- Cache for completion item info
H.info = {
  bufnr = nil,
  event = nil,
  id = 0,
  timer = vim.loop.new_timer(),
  win_id = nil,
  lsp = { id = 0, status = nil, result = nil, cancel_fun = nil },
}

-- Cache for signature help
H.signature = {
  bufnr = nil,
  text = nil,
  timer = vim.loop.new_timer(),
  win_id = nil,
  lsp = { id = 0, status = nil, result = nil, cancel_fun = nil },
}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  H.check_type('delay', config.delay, 'table')
  H.check_type('window', config.window, 'table')
  H.check_type('lsp_completion', config.lsp_completion, 'table')
  if not (type(config.fallback_action) == 'function' or type(config.fallback_action) == 'string') then
    H.error('`fallback_action` should be function or string, not ' .. type(config.fallback_action))
  end
  H.check_type('mappings', config.mappings, 'table')

  H.check_type('delay.completion', config.delay.completion, 'number')
  H.check_type('delay.info', config.delay.info, 'number')
  H.check_type('delay.signature', config.delay.signature, 'number')

  H.check_type('window.info', config.window.info, 'table')
  H.check_type('window.signature', config.window.signature, 'table')

  if not (config.lsp_completion.source_func == 'completefunc' or config.lsp_completion.source_func == 'omnifunc') then
    H.error('`lsp_completion.source_func` should be one of "completefunc" or "omnifunc"')
  end
  H.check_type('lsp_completion.auto_setup', config.lsp_completion.auto_setup, 'boolean')
  H.check_type('lsp_completion.process_items', config.lsp_completion.process_items, 'callable', true)
  H.check_type('lsp_completion.snippet_insert', config.lsp_completion.snippet_insert, 'callable', true)

  H.check_type('mappings.force_twostep', config.mappings.force_twostep, 'string')
  H.check_type('mappings.force_fallback', config.mappings.force_fallback, 'string')
  H.check_type('mappings.scroll_down', config.mappings.scroll_down, 'string')
  H.check_type('mappings.scroll_up', config.mappings.scroll_up, 'string')

  local is_string_or_array = function(x) return type(x) == 'string' or H.islist(x) end
  H.check_type('window.info.height', config.window.info.height, 'number')
  H.check_type('window.info.width', config.window.info.width, 'number')
  if not is_string_or_array(config.window.info.border or 'single') then
    H.error('`config.window.info.border` should be either string or array, not ' .. type(config.window.info.border))
  end
  H.check_type('window.signature.height', config.window.signature.height, 'number')
  H.check_type('window.signature.width', config.window.signature.width, 'number')
  if not is_string_or_array(config.window.signature.border or 'single') then
    H.error(
      '`config.window.signature.border` should be either string or array, not ' .. type(config.window.signature.border)
    )
  end

  return config
end

H.apply_config = function(config)
  MiniCompletion.config = config

  H.map('i', config.mappings.force_twostep, MiniCompletion.complete_twostage, { desc = 'Complete with two-stage' })
  H.map('i', config.mappings.force_fallback, MiniCompletion.complete_fallback, { desc = 'Complete with fallback' })

  local map_scroll = function(lhs, direction)
    local rhs = function() return MiniCompletion.scroll(direction) and '' or lhs end
    H.map('i', lhs, rhs, { expr = true, desc = 'Scroll info/signature ' .. direction })
  end
  map_scroll(config.mappings.scroll_down, 'down')
  map_scroll(config.mappings.scroll_up, 'up')

  -- Try setting suggested option values
  -- - More common completion behavior
  local was_set = vim.api.nvim_get_option_info2('completeopt', { scope = 'global' }).was_set
  if not was_set then vim.o.completeopt = 'menuone,noselect' end

  -- - Don't show ins-completion-menu messages ("C" is default on Neovim>=0.10)
  local shortmess_flags = 'c' .. (vim.fn.has('nvim-0.10') == 0 and 'C' or '')
  was_set = vim.api.nvim_get_option_info2('shortmess', { scope = 'global' }).was_set
  if not was_set then vim.opt.shortmess:append(shortmess_flags) end

  -- - Remove "t" flag to reduce visible lags
  was_set = vim.api.nvim_get_option_info2('complete', { scope = 'global' }).was_set
  if not was_set and config.fallback_action == '<C-n>' then vim.opt.complete:remove('t') end
end

H.create_autocommands = function(config)
  local gr = vim.api.nvim_create_augroup('MiniCompletion', {})

  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = gr, pattern = pattern, callback = callback, desc = desc })
  end

  au('InsertCharPre', '*', H.auto_completion, 'Auto show completion')
  au('CompleteChanged', '*', H.auto_info, 'Auto show info')
  au('CursorMovedI', '*', H.auto_signature, 'Auto show signature')
  au('ModeChanged', 'i*:[^i]*', function() MiniCompletion.stop() end, 'Stop completion')
  au('CompleteDonePre', '*', H.on_completedonepre, 'On CompleteDonePre')
  au('TextChangedI', '*', H.on_text_changed_i, 'On TextChangedI')
  au('TextChangedP', '*', H.on_text_changed_p, 'On TextChangedP')

  if config.lsp_completion.auto_setup then
    local source_func = config.lsp_completion.source_func
    local callback = function() vim.bo[source_func] = 'v:lua.MiniCompletion.completefunc_lsp' end
    au('BufEnter', '*', callback, 'Set completion function')
  end

  au('ColorScheme', '*', H.create_default_hl, 'Ensure colors')
  au('FileType', 'TelescopePrompt', function() vim.b.minicompletion_disable = true end, 'Disable locally')
end

H.create_default_hl = function()
  vim.api.nvim_set_hl(0, 'MiniCompletionActiveParameter', { default = true, link = 'LspSignatureActiveParameter' })
  vim.api.nvim_set_hl(0, 'MiniCompletionDeprecated', { default = true, link = 'DiagnosticDeprecated' })
  vim.api.nvim_set_hl(0, 'MiniCompletionInfoBorderOutdated', { default = true, link = 'DiagnosticFloatingWarn' })
end

H.is_disabled = function() return vim.g.minicompletion_disable == true or vim.b.minicompletion_disable == true end

H.get_config = function(config)
  return vim.tbl_deep_extend('force', MiniCompletion.config, vim.b.minicompletion_config or {}, config or {})
end

-- Autocommands ---------------------------------------------------------------
H.auto_completion = function()
  if H.is_disabled() then return end

  H.completion.timer:stop()

  local is_incomplete = H.completion.lsp.is_incomplete
  local is_trigger = H.is_lsp_trigger(vim.v.char, 'completion')
  local force = is_trigger or is_incomplete
  if force then
    -- Force fresh LSP completion if needed. Check before checking pumvisible
    -- because it should be forced even if there are visible candidates.
    -- Keep positive `is_incomplete` to allow fast typing and not "forget" that
    -- list was incomplete after the second fast key press. This will force LSP
    -- completion until `isIncomplete=false` response or general `stop()`.
    H.stop_completion(false, is_incomplete)
  elseif H.pumvisible() then
    -- Do nothing if popup is visible. `H.pumvisible()` might be `true` even if
    -- there is no popup. It is common when manually typing candidate followed
    -- by an LSP trigger (like ".").
    -- Keep completion source as it is needed all time when popup is visible.
    -- Keep resolved candidates because they should be relevant in this route.
    return H.stop_completion(true, false, true)
  elseif not H.is_char_keyword(vim.v.char) then
    -- Stop everything if inserted character is not appropriate. Check this
    -- after popup check to allow completion candidates to have bad characters.
    return H.stop_completion(false)
  end

  -- Start non-forced completion with fallback or forced LSP source for trigger
  H.completion.fallback, H.completion.force = not force, force

  -- Cache id of Insert mode "text changed" event for a later tracking (reduces
  -- false positive delayed triggers). The intention is to trigger completion
  -- after the delay only if text wasn't changed during waiting. Using only
  -- `InsertCharPre` is not enough though, as not every Insert mode change
  -- triggers `InsertCharPre` event (notable example - hitting `<CR>`).
  -- Also, using `+ 1` here because it is a `Pre` event and needs to cache
  -- after inserting character.
  H.completion.text_changed_id = H.text_changed_id + 1

  -- If completion was requested after 'lsp' source exhausted itself (there
  -- were matches on typing start, but they disappeared during filtering), call
  -- fallback immediately.
  if H.completion.source == 'lsp' then return H.trigger_fallback() end

  -- Set completion context with information about how it was triggered
  -- Prefer manual `TriggerCharacter` over automated `...ForIncomplete...`.
  local trigger_kind_name = is_trigger and 'TriggerCharacter'
    or (is_incomplete and 'TriggerForIncompleteCompletions' or 'Invoked')
  local trigger_kind = vim.lsp.protocol.CompletionTriggerKind[trigger_kind_name]
  local trigger_char = trigger_kind_name == 'TriggerCharacter' and vim.v.char or nil
  H.completion.lsp.context = { triggerKind = trigger_kind, triggerCharacter = trigger_char }

  -- Debounce delay improves experience (can type fast without many popups)
  -- Request right away if improving incomplete suggestions (less flickering),
  -- but still with `vim.schedule` because line is still not up to date during
  -- `InsertCharPre` event.
  local delay = is_incomplete and 0 or H.get_config().delay.completion
  H.completion.timer:start(delay, 0, vim.schedule_wrap(H.trigger_twostep))
end

H.auto_info = function()
  if H.is_disabled() then return end

  -- Stop current LSP request that tries to get already not current data
  H.cancel_lsp({ H.info })

  -- Update metadata before leaving to register a `CompleteChanged` event
  H.info.timer:stop()
  H.info.event = vim.v.event
  H.info.id = H.info.id + 1

  -- Stop showing window if no candidate is selected
  local completed_item = H.info.event.completed_item or {}
  if completed_item.word == nil then
    return vim.schedule(function() H.close_action_window(H.info) end)
  end

  -- Show info content without delay for visited and resolved LSP item.
  -- Otherwise delay to not spam LSP requests on up/down navigation.
  local item_id = H.table_get(completed_item, { 'user_data', 'lsp', 'item_id' })
  local is_resolved = item_id == nil or H.completion.lsp.resolved[item_id] ~= nil
  local delay = is_resolved and 0 or H.get_config().delay.info

  -- Mark visually that currently shown content will be outdated for a while
  local win_id = H.info.win_id
  if H.is_valid_win(win_id) and delay > 0 then
    vim.wo[win_id].winhighlight = vim.wo[win_id].winhighlight .. ',FloatBorder:MiniCompletionInfoBorderOutdated'
  end
  local cur_info_id = H.info.id
  H.info.timer:start(delay, 0, function() H.show_info_window(cur_info_id) end)
end

H.auto_signature = function()
  if H.is_disabled() then return end

  H.signature.timer:stop()
  if not H.has_lsp_clients('signatureHelpProvider') then return end

  local is_shown = H.is_valid_win(H.signature.win_id)
  local left_char_is_trigger = H.is_lsp_trigger(H.get_left_char(), 'signature')
  if not (is_shown or left_char_is_trigger) then return end

  local delay = is_shown and 0 or H.get_config().delay.signature
  H.signature.timer:start(delay, 0, vim.schedule_wrap(H.show_signature_window))
end

H.on_completedonepre = function()
  -- Do nothing if it is triggered inside `trigger_lsp()` as a result of
  -- emulating 'completefunc'/'omnifunc' keys. This can happen if popup is
  -- visible and pressing keys first hides it with 'CompleteDonePre' event.
  if H.completion.lsp.status == 'received' then return end

  -- Do extra actions for LSP completion items
  local lsp_data = H.table_get(vim.v.completed_item, { 'user_data', 'lsp' })
  if lsp_data ~= nil then H.make_lsp_extra_actions(lsp_data) end

  -- Stop processes
  MiniCompletion.stop({ 'completion', 'info' })
end

H.on_text_changed_i = function()
  -- Track Insert mode changes
  H.text_changed_id = H.text_changed_id + 1

  -- Stop 'info' processes in case no completion event is triggered but popup
  -- is not visible. See https://github.com/neovim/neovim/issues/15077
  H.stop_info()
end

H.on_text_changed_p = function()
  -- Track Insert mode changes
  H.text_changed_id = H.text_changed_id + 1
end

-- Completion triggers --------------------------------------------------------
H.trigger_twostep = function()
  -- Trigger only in Insert mode and if text didn't change after trigger
  -- request, unless completion is forced
  -- NOTE: check for `text_changed_id` equality is still not 100% solution as
  -- there are cases when, for example, `<CR>` is hit just before this check.
  -- Because of asynchronous id update and this function call (called after
  -- delay), these still match.
  local allow_trigger = (vim.fn.mode() == 'i')
    and (H.completion.force or (H.completion.text_changed_id == H.text_changed_id))
  if not allow_trigger then return end

  if H.has_lsp_clients('completionProvider') and H.has_lsp_completion() then
    H.trigger_lsp()
  elseif H.completion.fallback then
    H.trigger_fallback()
  end
end

H.trigger_lsp = function()
  -- Check for popup visibility is needed to reduce flickering.
  -- Possible issue timeline (with 100ms delay with set up LSP):
  -- 0ms: Key is pressed.
  -- 100ms: LSP is triggered from first key press.
  -- 110ms: Another key is pressed.
  -- 200ms: LSP callback is processed, triggers complete-function which
  --   processes "received" LSP request.
  -- 201ms: LSP request is processed, completion is (should be almost
  --   immediately) provided, request is marked as "done".
  -- 210ms: LSP is triggered from second key press. As previous request is
  --   "done", it will once make whole LSP request. Having check for visible
  --   popup should prevent here the call to complete-function.

  -- Do not trigger if not needed and/or allowed
  if vim.fn.mode() ~= 'i' or (H.pumvisible() and not H.completion.force) then return end

  -- Overall idea: first make LSP request and re-trigger this same function
  -- inside its callback to take the "received" route. This reduces flickering
  -- in case popup is visible (like for `isIncomplete` and trigger characters)
  -- as pressing 'completefunc'/'omnifunc' keys first hides completion menu.
  -- There are still minor visual defects: typing new character reduces number
  -- of matched items which can visually shrink popup while later increase it
  -- again after LSP response is received. This is usually fine (especially
  -- with not huge 'pumheight').
  if H.completion.lsp.status ~= 'received' then return H.make_completion_request() end
  local keys = H.keys[H.get_config().lsp_completion.source_func]
  vim.api.nvim_feedkeys(keys, 'n', false)
end

H.trigger_fallback = function()
  -- Fallback only in Insert mode when no popup is visible
  local has_popup = H.pumvisible() and not H.completion.force
  if has_popup or vim.fn.mode() ~= 'i' then return end

  -- Track from which source is current popup
  H.completion.source = 'fallback'

  -- Execute fallback action
  local fallback_action = H.get_config().fallback_action or H.default_fallback_action
  fallback_action = fallback_action == '<C-n>' and H.default_fallback_action or fallback_action
  if vim.is_callable(fallback_action) then return fallback_action() end
  if type(fallback_action) ~= 'string' then return end

  -- Having `<C-g><C-g>` also (for some mysterious reason) helps to avoid
  -- some weird behavior. For example, if `keys = '<C-x><C-l>'` then Neovim
  -- starts new line when there is no suggestions.
  local keys = string.format('<C-g><C-g>%s', fallback_action)
  local trigger_keys = vim.api.nvim_replace_termcodes(keys, true, false, true)
  vim.api.nvim_feedkeys(trigger_keys, 'n', false)
end

H.default_fallback_action = function() vim.api.nvim_feedkeys(H.keys.ctrl_n, 'n', false) end

-- Stop actions ---------------------------------------------------------------
H.stop_completion = function(keep_source, keep_lsp_is_incomplete, keep_lsp_resolved)
  H.completion.timer:stop()
  H.cancel_lsp({ H.completion })
  H.completion.lsp.context = nil
  H.completion.fallback, H.completion.force = true, false
  if not keep_source then H.completion.source = nil end
  if not keep_lsp_is_incomplete then H.completion.lsp.is_incomplete = false end
  if not keep_lsp_resolved then H.completion.lsp.resolved = {} end
end

H.stop_info = function()
  -- Id update is needed to notify that all previous work is not current
  H.info.id = H.info.id + 1
  H.info.timer:stop()
  H.cancel_lsp({ H.info })
  H.close_action_window(H.info)
end

H.stop_signature = function()
  H.signature.text = nil
  H.signature.timer:stop()
  H.cancel_lsp({ H.signature })
  H.close_action_window(H.signature)
end

H.stop_actions = {
  completion = H.stop_completion,
  info = H.stop_info,
  signature = H.stop_signature,
}

-- LSP ------------------------------------------------------------------------
---@param capability string|table|nil Server capability (possibly nested
---   supplied via table) to check.
---
---@return boolean Whether at least one LSP client supports `capability`.
---@private
H.has_lsp_clients = function(capability)
  local clients = H.get_buf_lsp_clients()
  if vim.tbl_isempty(clients) then return false end
  if not capability then return true end

  for _, c in pairs(clients) do
    local has_capability = H.table_get(c.server_capabilities, capability)
    if has_capability then return true end
  end
  return false
end

H.has_lsp_completion = function()
  local source_func = H.get_config().lsp_completion.source_func
  local func = vim.bo[source_func]
  return func == 'v:lua.MiniCompletion.completefunc_lsp'
end

H.is_lsp_trigger = function(char, type)
  local triggers
  local providers = { completion = 'completionProvider', signature = 'signatureHelpProvider' }

  for _, client in ipairs(H.get_buf_lsp_clients()) do
    triggers = H.table_get(client, { 'server_capabilities', providers[type], 'triggerCharacters' })
    if vim.tbl_contains(triggers or {}, char) then return true end
  end
  return false
end

H.cancel_lsp = function(caches)
  caches = caches or { H.completion, H.info, H.signature }
  for _, c in ipairs(caches) do
    if vim.tbl_contains({ 'sent', 'received' }, c.lsp.status) then
      if c.lsp.cancel_fun then c.lsp.cancel_fun() end
      c.lsp.status = 'canceled'
    end

    c.lsp.result, c.lsp.cancel_fun = nil, nil
  end
end

H.process_lsp_response = function(request_result, processor)
  if not request_result then return {} end

  local res = {}
  for client_id, item in pairs(request_result) do
    -- TODO: Use only `.err` after compatibility with Neovim=0.10 is dropped
    if not (item.err or item.error) and item.result then
      vim.list_extend(res, processor(item.result, client_id) or {})
    end
  end

  return res
end

H.is_lsp_current = function(cache, id) return cache.lsp.id == id and cache.lsp.status == 'sent' end

H.filtersort_methods = {
  prefix = function(items, base)
    local res = vim.tbl_filter(function(x) return vim.startswith(H.lsp_get_filterword(x), base) end, items)
    res = vim.deepcopy(res)
    table.sort(res, H.lsp_item_compare)
    return res
  end,
  fuzzy = function(items, base)
    if base == '' then return vim.deepcopy(items) end
    return vim.fn.matchfuzzy(items, base, { text_cb = H.lsp_get_filterword })
  end,
  none = function(items, _) return vim.deepcopy(items) end,
}

H.lsp_arrange_by_kind = function(items, kind_priority)
  if type(kind_priority) ~= 'table' then H.error('`kind_priority` should be table') end

  H.ensure_kind_map()

  local res_raw = {}
  for i, item in ipairs(items) do
    local priority = kind_priority[H.kind_map[item.kind]] or 100
    if priority >= 0 then table.insert(res_raw, { priority, i, item }) end
  end

  local compare = function(a, b) return a[1] > b[1] or (a[1] == b[1] and a[2] < b[2]) end
  table.sort(res_raw, compare)
  return vim.tbl_map(function(x) return x[3] end, res_raw)
end

H.lsp_get_filterword = function(x) return x.filterText or x.label end

H.lsp_item_compare = function(a, b) return (a.sortText or a.label) < (b.sortText or b.label) end

-- Completion -----------------------------------------------------------------
H.make_completion_request = function()
  local current_id = H.completion.lsp.id + 1
  H.completion.lsp.id = current_id
  H.completion.lsp.status = 'sent'

  local context = H.completion.lsp.context or { triggerKind = vim.lsp.protocol.CompletionTriggerKind.Invoked }
  local buf_id, params = vim.api.nvim_get_current_buf(), H.make_position_params(context)
  -- NOTE: use `buf_request_all()` (instead of `buf_request()`) to easily
  -- handle possible fallback and to have all completion suggestions be later
  -- filtered with one `base`. Anyway, the most common situation is with one
  -- attached LSP client.
  local cancel_fun = vim.lsp.buf_request_all(buf_id, 'textDocument/completion', params, function(result)
    if not H.is_lsp_current(H.completion, current_id) then return end

    H.completion.lsp.status = 'received'
    H.completion.lsp.result = result

    -- Trigger LSP completion to use completefunc/omnifunc route
    H.trigger_lsp()
  end)

  -- Cache cancel function to disable requests when they are not needed
  H.completion.lsp.cancel_fun = cancel_fun
end

H.apply_item_defaults = function(items, defaults)
  if type(defaults) ~= 'table' then return items end

  local edit_range, has_edit_range = defaults.editRange, type(defaults.editRange) == 'table'
  local edit_range_range = (edit_range or {}).start ~= nil and edit_range or nil
  for _, item in ipairs(items) do
    item.commitCharacters = item.commitCharacters or defaults.commitCharacters
    item.data = item.data or defaults.data
    item.insertTextFormat = item.insertTextFormat or defaults.insertTextFormat
    item.insertTextMode = item.insertTextMode or defaults.insertTextMode
    if has_edit_range then
      item.textEdit = item.textEdit or {}
      -- Infer new text from `item.textEditText` designed for default edit case
      item.textEdit.newText = item.textEdit.newText or item.textEditText or item.label
      -- Default `editRange` is range (start+end) or insert+replace ranges
      item.textEdit.range = item.textEdit.range or edit_range_range
      item.textEdit.insert = item.textEdit.insert or edit_range.insert
      item.textEdit.replace = item.textEdit.replace or edit_range.replace
    end
  end
  return items
end

-- Source:
-- https://microsoft.github.io/language-server-protocol/specifications/specification-3-14/#textDocument_completion
H.lsp_completion_response_items_to_complete_items = function(items)
  if vim.tbl_count(items) == 0 then return {} end

  local res, item_kinds = {}, vim.lsp.protocol.CompletionItemKind
  local snippet_kind = vim.lsp.protocol.CompletionItemKind.Snippet
  local snippet_inserttextformat = vim.lsp.protocol.InsertTextFormat.Snippet
  for i, item in ipairs(items) do
    local word = H.get_completion_word(item)

    local is_snippet_kind = item.kind == snippet_kind
    local is_snippet_format = item.insertTextFormat == snippet_inserttextformat
    -- Treat item as snippet only if it has tabstop, variable, tab, or newline.
    -- It is important to make "implicit" expand work with LSP servers that
    -- report even regular words as `InsertTextFormat.Snippet` (like `gopls`).
    -- Otherwise it will "eat" the next typed non-keyword charater.
    -- Account for tabs and newline to allow `snippet_insert` to deal with
    -- reindenting and tab expansion.
    local has_snippet_features = (word:find('[^\\]%${?%w') or word:find('^%${?%w') or word:find('[\n\t]')) ~= nil
    local needs_snippet_insert = (is_snippet_kind or is_snippet_format) and has_snippet_features

    local details = item.labelDetails or {}
    -- NOTE: Using `table.concat({}, ' ')` would be cleaner but less performant
    local snip, detail, desc = needs_snippet_insert and 'S' or '', details.detail or '', details.description or ''
    local pad = (snip ~= '' and detail ~= '') and ' ' or ''
    local label_detail = snip .. pad .. detail
    pad = (label_detail ~= '' and desc ~= '') and ' ' or ''
    label_detail = label_detail .. pad .. desc

    local lsp_data = { item = item, item_id = i }
    lsp_data.needs_snippet_insert = needs_snippet_insert
    table.insert(res, {
      -- Show less for snippet items (usually less confusion), but preserve
      -- built-in filtering capabilities (as it uses `word` to filter).
      word = needs_snippet_insert and H.lsp_get_filterword(item) or word,
      abbr = item.label,
      abbr_hlgroup = item.abbr_hlgroup,
      kind = item_kinds[item.kind] or 'Unknown',
      kind_hlgroup = item.kind_hlgroup,
      menu = label_detail,
      -- NOTE: info will be attempted to resolve, use snippet text as fallback
      info = needs_snippet_insert and word or nil,
      icase = 1,
      dup = 1,
      empty = 1,
      user_data = { lsp = lsp_data },
    })
  end
  return res
end

H.make_add_abbr_hlgroup = function()
  local deprecated_tag = vim.lsp.protocol.CompletionTag.Deprecated
  local contains = vim.list_contains
  return function(item)
    local is_deprecated = item.deprecated or (item.tags and contains(item.tags, deprecated_tag))
    item.abbr_hlgroup = item.abbr_hlgroup or (is_deprecated and 'MiniCompletionDeprecated' or nil)
  end
end
if vim.fn.has('nvim-0.11') == 0 then H.make_add_abbr_hlgroup = function()
  return function() end
end end

H.make_add_kind_hlgroup = function()
  -- Account for possible effect of `MiniIcons.tweak_lsp_kind()` which modifies
  -- only array part of `CompletionItemKind` but not "map" part
  H.ensure_kind_map()

  if _G.MiniIcons == nil then
    return function() end
  end

  return function(item)
    local _, hl, is_default = _G.MiniIcons.get('lsp', H.kind_map[item.kind] or 'Unknown')
    item.kind_hlgroup = item.kind_hlgroup or (not is_default and hl or nil)
  end
end

H.ensure_kind_map = function()
  if H.kind_map ~= nil then return end

  -- Cache kind map so as to not recompute it each time (as it will be called
  -- in performance sensitive context). Assumes `tweak_lsp_kind()` is called
  -- right after `require('mini.icons').setup()`.
  H.kind_map = {}
  for k, v in pairs(vim.lsp.protocol.CompletionItemKind) do
    if type(k) == 'string' and type(v) == 'number' then H.kind_map[v] = k end
  end
end

H.get_completion_word = function(item)
  return H.table_get(item, { 'textEdit', 'newText' }) or item.insertText or H.lsp_get_filterword(item) or ''
end

H.make_lsp_extra_actions = function(lsp_data)
  -- Prefer resolved item over the one from 'textDocument/completion'
  local item = H.completion.lsp.resolved[lsp_data.item_id] or lsp_data.item

  if item.additionalTextEdits == nil and not lsp_data.needs_snippet_insert then return end
  local snippet = lsp_data.needs_snippet_insert and H.get_completion_word(item) or nil

  -- Make extra actions not only after an explicit `<C-y>` (accept completed
  -- item), but also after implicit non-keyword character. This needs:
  -- - Keeping track of newly added non-keyword character and cursor move (like
  --   after 'mini.pairs') for a later undo. Do it via using expanding extmark.
  -- - Delay actual execution to operate *after* characters are inserted (as it
  --   is not immediate). Otherwise those characters will get "inserted" after
  --   snippet is inserted and its session is active.
  local cur = vim.api.nvim_win_get_cursor(0)
  local extmark_opts = { end_row = cur[1] - 1, end_col = cur[2], right_gravity = false, end_right_gravity = true }
  local track_extmark_id = vim.api.nvim_buf_set_extmark(0, H.ns_id, cur[1] - 1, cur[2], extmark_opts)

  vim.schedule(function()
    -- Do nothing if user exited Insert mode
    if vim.fn.mode() ~= 'i' then return end

    -- Undo possible non-keyword character(s) and cursor move. Do this before
    -- text edits to have more proper state (as it was at the time edits were
    -- created by server), but only if there is snippet (keep new characters
    -- for *only* text edits).
    if snippet ~= nil then
      H.del_extmark(track_extmark_id, true)
      pcall(vim.api.nvim_win_set_cursor, 0, cur)
    end

    -- Try to only apply additional text edits for non-snippet items
    if snippet == nil then return H.apply_text_edits(item.client_id, item.additionalTextEdits) end

    -- Revert to initial completion state to respect text edit coordinates
    local init_base = H.completion.init_base
    local from, to = { init_base.lnum, init_base.col }, vim.api.nvim_win_get_cursor(0)
    -- NOTE: actual base string should not be relevant here, only byte count
    local prefix = string.rep('x', init_base.length)
    pcall(vim.api.nvim_buf_set_text, 0, from[1] - 1, from[2], to[1] - 1, to[2], { prefix })
    to = { from[1], from[2] + init_base.length }
    local prefix_extmark_opts = { end_row = to[1] - 1, end_col = to[2] }
    local prefix_extmark_id = vim.api.nvim_buf_set_extmark(0, H.ns_id, from[1] - 1, from[2], prefix_extmark_opts)

    -- Possibly adjust tracked range to come from LSP item. Clamp to existing
    -- text state because some LSP servers update `textEdit` during resolve
    -- (although the must not to) which can error when setting extmarks.
    local edit_range = H.get_lsp_edit_range({ result = { item } })
    if edit_range ~= nil then
      local n_lines = vim.api.nvim_buf_line_count(0)
      local start_lnum = math.min(edit_range.start.line + 1, n_lines)
      local end_lnum = math.min(edit_range['end'].line + 1, n_lines)
      local start_col = math.min(edit_range.start.character, vim.fn.getline(start_lnum):len())
      local end_col = math.min(edit_range['end'].character, vim.fn.getline(end_lnum):len())
      from, to = { start_lnum, start_col }, { end_lnum, end_col }
    end

    -- Try to apply additional text edits *after* restoring state because their
    -- data is computed by the server at that state. Keep track of the range
    -- that needs clearing as it might change during edits.
    from, to = H.apply_tracked_text_edits(item.client_id, item.additionalTextEdits, from, to)

    -- Expand snippet: remove base and insert at cursor
    pcall(vim.api.nvim_buf_set_text, 0, from[1] - 1, from[2], to[1] - 1, to[2], { '' })
    -- - Ensure to work with bad `textEdit`, like not covering cursor position
    vim.api.nvim_win_set_cursor(0, from)
    H.del_extmark(prefix_extmark_id, true)
    local insert = H.get_config().lsp_completion.snippet_insert or MiniCompletion.default_snippet_insert
    insert(snippet)
  end)
end

H.apply_text_edits = function(client_id, text_edits)
  if text_edits == nil then return end
  local offset_encoding = client_id == nil and 'utf-16' or vim.lsp.get_client_by_id(client_id).offset_encoding
  vim.lsp.util.apply_text_edits(text_edits, vim.api.nvim_get_current_buf(), offset_encoding)
end

H.apply_tracked_text_edits = function(client_id, text_edits, from, to)
  if text_edits == nil then return from, to end

  -- Prepare extmarks to track relevant positions
  local cur_pos = vim.api.nvim_win_get_cursor(0)
  local cursor_extmark_id = vim.api.nvim_buf_set_extmark(0, H.ns_id, cur_pos[1] - 1, cur_pos[2], {})

  local from_extmark_id = vim.api.nvim_buf_set_extmark(0, H.ns_id, from[1] - 1, from[2], {})
  local to_extmark_id = vim.api.nvim_buf_set_extmark(0, H.ns_id, to[1] - 1, to[2], {})

  -- Do text edits
  H.apply_text_edits(client_id, text_edits)

  -- Restore cursor position
  local cursor_data = H.del_extmark(cursor_extmark_id)
  pcall(vim.api.nvim_win_set_cursor, 0, { cursor_data[1] + 1, cursor_data[2] })

  -- Update in place tracked range
  local from_data = H.del_extmark(from_extmark_id)
  local to_data = H.del_extmark(to_extmark_id)
  return { from_data[1] + 1, from_data[2] }, { to_data[1] + 1, to_data[2] }
end

-- Completion item info -------------------------------------------------------
H.show_info_window = vim.schedule_wrap(function(info_id)
  -- Do nothing if completion item was changed. For example, after autoinvoked
  -- in timer with zero delay but after it there is another `CompleteChanged`
  -- that closes popup. This only stops the timer *but* not actually cancelling
  -- this function.
  if H.info.id ~= info_id then return end

  -- Get info lines to show. Wait for resolve if returned `false`.
  local lines = H.info_window_lines(info_id)
  if lines == false then return end
  if lines == nil or H.is_whitespace(lines) then lines = { '-No-info-' } end

  -- Ensure permanent buffer with "markdown" highlighting to display info
  H.ensure_buffer(H.info, 'item-info')
  H.ensure_highlight(H.info, 'markdown')
  H.ensure_no_concealed_lines(H.info.bufnr)
  vim.api.nvim_buf_set_lines(H.info.bufnr, 0, -1, false, lines)

  -- Compute floating window options
  local opts = H.info_window_options()

  -- Adjust section separator with better visual alternative
  lines = vim.tbl_map(function(l) return l:gsub('^%-%-%-%-*$', string.rep('─', opts.width)) end, lines)
  vim.api.nvim_buf_set_lines(H.info.bufnr, 0, -1, false, lines)

  -- Defer execution because of textlock during `CompleteChanged` event
  vim.schedule(function()
    -- Ensure that window doesn't open when it shouldn't be
    if not (H.pumvisible() and vim.fn.mode() == 'i') then return end
    H.ensure_action_window('info', opts)
    local win_id = H.info.win_id
    if not H.is_valid_win(win_id) then return end

    -- Hide helper syntax elements (like ``` code blocks, etc.)
    vim.wo[H.info.win_id].conceallevel = 3

    -- Scroll past first line if it is a visible (Neovim<0.11) codeblock start
    if vim.fn.has('nvim-0.11') == 0 and lines[1]:find('^```%S*$') ~= nil then
      vim.api.nvim_win_call(win_id, function() vim.fn.winrestview({ topline = 2 }) end)
    end
  end)
end)

H.info_window_lines = function(info_id)
  local completed_item = H.info.event.completed_item
  local info = completed_item.info or ''
  local lsp_data = H.table_get(completed_item, { 'user_data', 'lsp' })

  -- If popup is not from a known LSP server, use 'info' field of complete-item
  if lsp_data == nil or lsp_data.item.client_id == nil then return vim.split(info, '\n') end

  -- Prefer reusing (without new LSP request) already resolved completion item
  local item_id, resolved_cache = lsp_data.item_id, H.completion.lsp.resolved
  if resolved_cache[item_id] ~= nil then return H.normalize_item_doc(resolved_cache[item_id], info) end

  -- Try to get documentation from LSP's latest resolved info
  if H.info.lsp.status == 'received' then
    local lines = H.normalize_item_doc(H.info.lsp.result, info)
    H.info.lsp.status = 'done'
    return lines
  end

  -- If server doesn't support resolve or not known, reuse first response
  local client = vim.lsp.get_client_by_id(lsp_data.item.client_id) or {}
  local can_resolve = H.table_get(client.server_capabilities, { 'completionProvider', 'resolveProvider' })
  if not can_resolve or client.id == nil then
    resolved_cache[item_id] = lsp_data.item
    return H.normalize_item_doc(lsp_data.item, info)
  end

  -- Finally, request to resolve current completion to add more documentation
  local bufnr = vim.api.nvim_get_current_buf()
  local current_id = H.info.lsp.id + 1
  H.info.lsp.id = current_id
  H.info.lsp.status = 'sent'

  local cancel_fun = H.client_request(client, 'completionItem/resolve', lsp_data.item, function(err, result, _)
    -- Don't do anything if there is other LSP request in action
    if not H.is_lsp_current(H.info, current_id) then return end

    H.info.lsp.status = 'received'

    -- Do nothing if completion item was changed
    if H.info.id ~= info_id then return end

    -- Still use original item if there was no response (usually due to error)
    result = result or lsp_data.item

    H.info.lsp.result = result
    -- - Cache resolved item to not have to send same request on revisit.
    --   Do this outside of `H.info.event.completed_item` because it will not
    --   have persistent effect as it will come fresh from Vimscript `v:event`.
    resolved_cache[item_id] = result
    H.show_info_window(info_id)
  end, bufnr)

  H.info.lsp.cancel_fun = cancel_fun
  return false
end

H.info_window_options = function()
  local win_config = H.get_config().window.info
  local default_border = (H.has_no_winborder or vim.o.winborder == '') and 'single' or nil
  local border = win_config.border or default_border
  local pumborder = H.has_pumborder and vim.o.pumborder or ''

  -- Compute dimensions based on actually visible lines to be displayed
  local lines = H.compute_visible_md_lines(vim.api.nvim_buf_get_lines(H.info.bufnr, 0, -1, false))
  local info_height, info_width = H.floating_dimensions(lines, win_config.height, win_config.width)

  -- Compute position
  local event = H.info.event
  local left_to_pum = event.col - 1
  local offset = (pumborder == '' or pumborder == 'none') and (event.scrollbar and 1 or 0) or 2
  local right_to_pum = event.col + event.width + offset

  local border_offset = border == 'none' and 0 or 2
  local space_left = left_to_pum - border_offset
  local space_right = vim.o.columns - right_to_pum - border_offset

  -- Decide side at which info window will be displayed
  local anchor, col, space
  if info_width <= space_right or space_left <= space_right then
    anchor, col, space = 'NW', right_to_pum, space_right
  else
    anchor, col, space = 'NE', left_to_pum, space_left
  end

  -- Possibly adjust floating window dimensions to fit screen
  if space < info_width then
    info_height, info_width = H.floating_dimensions(lines, win_config.height, space)
  end

  return {
    relative = 'editor',
    anchor = anchor,
    row = event.row,
    col = col,
    width = info_width,
    height = info_height,
    focusable = false,
    style = 'minimal',
    border = border,
    title = H.fit_to_width(' Info ', info_width),
  }
end

-- Signature help -------------------------------------------------------------
H.show_signature_window = function()
  -- If there is no received LSP result, make request and exit
  if H.signature.lsp.status ~= 'received' then
    local current_id = H.signature.lsp.id + 1
    H.signature.lsp.id = current_id
    H.signature.lsp.status = 'sent'

    local bufnr = vim.api.nvim_get_current_buf()
    local params = H.make_position_params()

    local cancel_fun = vim.lsp.buf_request_all(bufnr, 'textDocument/signatureHelp', params, function(result)
      if not H.is_lsp_current(H.signature, current_id) then return end

      H.signature.lsp.status = 'received'
      H.signature.lsp.result = result

      -- Trigger `show_signature` again to take 'received' route
      H.show_signature_window()
    end)

    -- Cache cancel function to disable requests when they are not needed
    H.signature.lsp.cancel_fun = cancel_fun

    return
  end

  -- Make lines to show in floating window
  local lines, hl_ranges = H.signature_window_lines()
  H.signature.lsp.status = 'done'

  -- Close window and exit if there is nothing to show
  if not lines or H.is_whitespace(lines) then return H.close_action_window(H.signature) end

  -- Ensure permanent buffer with current highlighting to display signature
  H.ensure_buffer(H.signature, 'signature-help')
  H.ensure_highlight(H.signature, vim.bo.filetype)
  vim.api.nvim_buf_set_lines(H.signature.bufnr, 0, -1, false, lines)

  -- Add highlighting of active parameter
  local buf_id = H.signature.bufnr
  vim.api.nvim_buf_clear_namespace(buf_id, H.ns_id, 0, -1)
  for i, hl_range in ipairs(hl_ranges) do
    if hl_range[1] ~= nil and hl_range[2] ~= nil then
      local opts = { end_row = i - 1, end_col = hl_range[2], hl_group = 'MiniCompletionActiveParameter' }
      vim.api.nvim_buf_set_extmark(buf_id, H.ns_id, i - 1, hl_range[1], opts)
    end
  end

  -- If window is already opened and displays the same text, don't reopen it
  local cur_text = table.concat(lines, '\n')
  if H.signature.win_id and cur_text == H.signature.text then return end

  -- Cache lines for later checks if window should be reopened
  H.signature.text = cur_text

  -- Ensure window is closed
  H.close_action_window(H.signature)

  -- Compute floating window options
  local opts = H.signature_window_opts()

  -- Ensure that window doesn't open when it shouldn't
  if vim.fn.mode() == 'i' then H.ensure_action_window('signature', opts) end
end

H.signature_window_lines = function()
  local signature_data = H.process_lsp_response(H.signature.lsp.result, H.process_signature_response)
  -- Each line is a single-line active signature string from one attached LSP
  -- client. Each highlight range is a table which indicates (if not empty)
  -- what parameter to highlight for every LSP client's signature string.
  local lines, hl_ranges = {}, {}
  for _, t in ipairs(signature_data) do
    -- `t` is allowed to be an empty table (in which case nothing is added) or
    -- a table with two entries. This ensures that `hl_range`'s integer index
    -- points to an actual line in future buffer.
    table.insert(lines, t.label)
    table.insert(hl_ranges, t.hl_range)
  end

  return lines, hl_ranges
end

H.process_signature_response = function(response)
  if not response.signatures or vim.tbl_isempty(response.signatures) then return {} end

  -- Get active signature (based on textDocument/signatureHelp specification)
  local signature_id = response.activeSignature or 0
  -- This is according to specification: "If ... value lies outside ...
  -- defaults to zero"
  local n_signatures = vim.tbl_count(response.signatures or {})
  if signature_id < 0 or signature_id >= n_signatures then signature_id = 0 end
  local signature = response.signatures[signature_id + 1]

  -- Get displayed signature label
  local res = { label = signature.label:gsub('\n', ' ') }

  -- Get start and end of active parameter (for highlighting)
  local n_params = #(signature.parameters or {})
  local has_params = type(signature.parameters) == 'table' and n_params > 0

  -- Take values in this order because data inside signature takes priority
  local parameter_id = signature.activeParameter or response.activeParameter or 0
  local param_id_inrange = 0 <= parameter_id and parameter_id < n_params

  -- Computing active parameter only when parameter id is inside bounds is not
  -- strictly based on specification, as currently (v3.16) it says to treat
  -- out-of-bounds value as first parameter. However, some clients seem to use
  -- those values to indicate that nothing needs to be highlighted.
  -- Sources:
  -- https://github.com/microsoft/pyright/pull/1876
  -- https://github.com/microsoft/language-server-protocol/issues/1271
  if has_params and param_id_inrange then
    local param_label = signature.parameters[parameter_id + 1].label

    -- Compute highlight range based on type of supplied parameter label: can
    -- be string label which should be a part of signature label or direct start
    -- (inclusive) and end (exclusive) range values
    local label_is_string = type(param_label) == 'string'
    res.hl_range = label_is_string and { res.label:find(param_label, 1, true) } or (param_label or {})
    -- - Make zero-indexed and end-exclusive
    if res.hl_range[1] ~= nil then res.hl_range[1] = res.hl_range[1] - (label_is_string and 1 or 0) end
  end

  -- Return nested table because this will be a second argument of
  -- `vim.list_extend()` and the whole inner table is a target value here.
  return { res }
end

H.signature_window_opts = function()
  local win_config = H.get_config().window.signature
  local default_border = (H.has_no_winborder or vim.o.winborder == '') and 'single' or nil
  local border = win_config.border or default_border
  local lines = vim.api.nvim_buf_get_lines(H.signature.bufnr, 0, -1, false)
  local height, width = H.floating_dimensions(lines, win_config.height, win_config.width)

  -- Compute position
  local win_line = vim.fn.winline()
  local border_offset = border == 'none' and 0 or 2
  local space_above = win_line - 1 - border_offset
  local space_below = vim.api.nvim_win_get_height(0) - win_line - border_offset

  local anchor, row, space
  if height <= space_above or space_below <= space_above then
    anchor, row, space = 'SW', 0, space_above
  else
    anchor, row, space = 'NW', 1, space_below
  end

  -- Possibly adjust floating window dimensions to fit screen
  if space < height then
    height, width = H.floating_dimensions(lines, space, win_config.width)
  end

  -- Get zero-indexed current cursor position
  local bufpos = vim.api.nvim_win_get_cursor(0)
  bufpos[1] = bufpos[1] - 1

  return {
    relative = 'win',
    bufpos = bufpos,
    anchor = anchor,
    row = row,
    col = 0,
    width = width,
    height = height,
    focusable = false,
    style = 'minimal',
    border = border,
    title = H.fit_to_width(' Signature ', width),
  }
end

-- Helpers for floating windows -----------------------------------------------
H.ensure_buffer = function(cache, name)
  if H.is_valid_buf(cache.bufnr) then return end

  local buf_id = vim.api.nvim_create_buf(false, true)
  cache.bufnr = buf_id
  H.set_buf_name(buf_id, name)
  vim.bo[buf_id].buftype = 'nofile'
end

H.ensure_highlight = function(cache, filetype)
  if cache.hl_filetype == filetype then return end
  cache.hl_filetype = filetype
  local buf_id = cache.bufnr

  local has_lang, lang = pcall(vim.treesitter.language.get_lang, filetype)
  lang = has_lang and lang or filetype
  -- TODO: Remove `opts.error` after compatibility with Neovim=0.11 is dropped
  local has_parser, parser = pcall(vim.treesitter.get_parser, buf_id, lang, { error = false })
  has_parser = has_parser and parser ~= nil
  if has_parser then has_parser = pcall(vim.treesitter.start, buf_id, lang) end
  if not has_parser then vim.bo[buf_id].syntax = filetype end
end

-- Returns tuple of height and width
H.floating_dimensions = function(lines, max_height, max_width)
  max_height, max_width = math.max(max_height, 1), math.max(max_width, 1)

  -- Simulate how lines will look in window with `wrap` and `linebreak`.
  -- This is not 100% accurate (mostly because of concealed characters and
  -- multibyte manifest into empty space at bottom), but does the job
  local lines_wrap = {}
  for _, l in ipairs(lines) do
    vim.list_extend(lines_wrap, H.wrap_line(l, max_width))
  end
  -- Height is a number of wrapped lines truncated to maximum height
  local height = math.min(#lines_wrap, max_height)

  -- Width is a maximum width of the first `height` wrapped lines truncated to
  -- maximum width
  local width = 0
  local l_width
  for i, l in ipairs(lines_wrap) do
    -- Use `strdisplaywidth()` to account for 'non-UTF8' characters
    l_width = vim.fn.strdisplaywidth(l)
    if i <= height and width < l_width then width = l_width end
  end
  -- It should already be less that that because of wrapping, so this is "just
  -- in case"
  width = math.min(width, max_width)

  return math.max(height, 1), math.max(width, 1)
end

H.ensure_action_window = function(window_kind, opts)
  local cache = H[window_kind]
  local is_shown = H.is_valid_win(cache.win_id)
  if is_shown then vim.api.nvim_win_set_config(cache.win_id, opts) end
  if not is_shown then cache.win_id = vim.api.nvim_open_win(cache.bufnr, false, opts) end

  local win_id = cache.win_id
  vim.wo[win_id].breakindent = false
  vim.wo[win_id].foldenable = false
  vim.wo[win_id].foldmethod = 'manual'
  vim.wo[win_id].linebreak = true
  vim.wo[win_id].winhighlight = vim.wo[win_id].winhighlight:gsub(',FloatBorder:MiniCompletionInfoBorderOutdated', '')
  vim.wo[win_id].wrap = true

  local event = 'MiniCompletionWindow' .. (is_shown and 'Update' or 'Open')
  local data = { kind = window_kind, win_id = win_id }
  vim.api.nvim_exec_autocmds('User', { pattern = event, data = data })
end

H.close_action_window = function(cache)
  cache.timer:stop()

  if H.is_valid_win(cache.win_id) then vim.api.nvim_win_close(cache.win_id, true) end
  cache.win_id = nil

  -- For some reason 'buftype' might be reset. Ensure that buffer is scratch.
  if H.is_valid_buf(cache.bufnr) then vim.bo[cache.bufnr].buftype = 'nofile' end
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.completion) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.set_buf_name = function(buf_id, name) vim.api.nvim_buf_set_name(buf_id, 'minicompletion://' .. buf_id .. '/' .. name) end

H.is_valid_buf = function(buf_id) return type(buf_id) == 'number' and vim.api.nvim_buf_is_valid(buf_id) end

H.is_valid_win = function(win_id) return type(win_id) == 'number' and vim.api.nvim_win_is_valid(win_id) end

H.is_char_keyword = function(char)
  -- Using Vim's `match()` and `keyword` enables respecting Cyrillic letters
  return vim.fn.match(char, '[[:keyword:]]') >= 0
end

-- NOTE: Might return `true` even if there is no visible completion popup, but
-- built-in completion is still "active" (`<BS>` will show previous completion
-- immediately).
H.pumvisible = function() return vim.fn.pumvisible() > 0 end

H.get_completion_range = function(lsp_result)
  local pos = vim.api.nvim_win_get_cursor(0)

  -- Prefer completion start from LSP response(s)
  for _, response_data in pairs(lsp_result or {}) do
    local range = H.get_lsp_edit_range(response_data)
    if range ~= nil then return { range.start.line + 1, range.start.character }, pos end
  end

  -- Fall back to start position of latest keyword
  local line = vim.api.nvim_get_current_line()
  return { pos[1], vim.fn.match(line:sub(1, pos[2]), '\\k*$') }, pos
end

H.get_lsp_edit_range = function(response_data)
  -- TODO: Use only `.err` after compatibility with Neovim=0.10 is dropped
  if response_data.err or response_data.error or type(response_data.result) ~= 'table' then return end

  -- Try using item defaults if they contain edit range (which can be either
  -- `Range` or contain `insert` field of `Range` type)
  local edit_range = H.table_get(response_data.result, { 'itemDefaults', 'editRange' })
  if type(edit_range) == 'table' then return edit_range.insert or edit_range end

  -- Try using all items to find the first one with edit range
  local items = response_data.result.items or response_data.result
  for _, item in ipairs(items) do
    -- Account for `textEdit` can be either `TextEdit` or `InsertReplaceEdit`
    if type(item.textEdit) == 'table' then return item.textEdit.range or item.textEdit.insert end
  end
end

H.del_extmark = function(extmark_id, with_text)
  local data = vim.api.nvim_buf_get_extmark_by_id(0, H.ns_id, extmark_id, { details = true })
  vim.api.nvim_buf_del_extmark(0, H.ns_id, extmark_id)
  -- Possibly remove extmark's text
  if not with_text or data[1] == nil or data[3].end_row == nil then return data end
  local start_row, start_col, end_row, end_col = data[1], data[2], data[3].end_row, data[3].end_col
  if start_row < end_row or (start_row == end_row and start_col < end_col) then
    vim.api.nvim_buf_set_text(0, start_row, start_col, end_row, end_col, { '' })
  end
  return data
end

H.is_whitespace = function(s)
  if type(s) == 'string' then return s:find('^%s*$') end
  if type(s) == 'table' then
    for _, val in ipairs(s) do
      if not H.is_whitespace(val) then return false end
    end
    return true
  end
  return false
end

H.fit_to_width = function(text, width)
  local t_width = vim.fn.strchars(text)
  return t_width <= width and text or ('…' .. vim.fn.strcharpart(text, t_width - width + 1, width - 1))
end

H.str_byteindex = function(s, i) return vim.str_byteindex(s, 'utf-32', i) end
if vim.fn.has('nvim-0.11') == 0 then H.str_byteindex = function(s, i) return vim.str_byteindex(s, i) end end

-- Simulate splitting single line `l` like how it would look inside window with
-- `wrap` and `linebreak` set to `true`
H.wrap_line = function(l, width)
  local res = {}

  local success, width_id = true, nil
  -- Use `strdisplaywidth()` to account for multibyte characters
  while success and vim.fn.strdisplaywidth(l) > width do
    -- Simulate wrap by looking at breaking character from end of current break
    -- Use `pcall()` to handle complicated multibyte characters (like Chinese)
    -- for which even `strdisplaywidth()` seems to return incorrect values.
    success, width_id = pcall(H.str_byteindex, l, width)

    if success then
      local break_match = vim.fn.match(l:sub(1, width_id):reverse(), '[- \t.,;:!?]')
      -- If no breaking character found, wrap at whole width
      local break_id = width_id - (break_match < 0 and 0 or break_match)
      table.insert(res, l:sub(1, break_id))
      l = l:sub(break_id + 1)
    end
  end
  table.insert(res, l)

  return res
end

H.table_get = function(t, id)
  if type(id) ~= 'table' then return H.table_get(t, { id }) end
  local success, res = true, t
  for _, i in ipairs(id) do
    --stylua: ignore start
    success, res = pcall(function() return res[i] end)
    if not success or res == nil then return end
    --stylua: ignore end
  end
  return res
end

H.get_left_char = function()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]

  return string.sub(line, col, col)
end

H.map = function(mode, lhs, rhs, opts)
  if lhs == '' then return end
  opts = vim.tbl_deep_extend('force', { silent = true }, opts or {})
  vim.keymap.set(mode, lhs, rhs, opts)
end

H.normalize_item_doc = function(lsp_item, fallback_info)
  local detail, doc = lsp_item.detail, lsp_item.documentation
  -- Fall back to explicit info only of there is no data in completion item
  -- Assume that explicit info is a code that needs highlighting
  detail = (detail == nil and doc == nil) and fallback_info or detail
  if detail == nil and doc == nil then return {} end

  -- Extract string content. Treat markdown and plain kinds the same.
  -- Show both `detail` and `documentation` if the first provides new info.
  detail, doc = detail or '', type(doc) == 'table' and (doc.value or '') or (doc or '')
  -- Wrap details in language's code block to (usually) improve highlighting
  -- This approach seems to work in 'hrsh7th/nvim-cmp'
  detail = (H.is_whitespace(detail) or doc:find(detail, 1, true) ~= nil) and '' or (H.wrap_in_codeblock(detail) .. '\n')
  local text = detail .. doc

  -- Ensure consistent line separators
  text = text:gsub('\r\n?', '\n')
  -- Remove trailing whitespace (converts blank lines to empty)
  text = text:gsub('[ \t]+\n', '\n'):gsub('[ \t]+$', '\n')
  -- Collapse multiple empty lines, remove top and bottom padding
  text = text:gsub('\n\n+', '\n\n'):gsub('^\n+', ''):gsub('\n+$', '')
  -- Ensure single line pads around code blocks: on Neovim<0.11 top and bottom
  -- lines just appear empty, on Neovim>=0.11 they disappear (account for that)
  local pad = vim.fn.has('nvim-0.11') == 1 and '\n' or ''
  text = text:gsub('\n*(\n```%S+\n)', pad .. '%1'):gsub('(\n```\n)\n*', '%1' .. pad)

  if text == '' and fallback_info ~= '' then text = H.wrap_in_codeblock(fallback_info) end
  return text == '' and {} or vim.split(text, '\n')
end

-- Neovim>=0.11 has visually impactful issue of TS (markdown) highlighting:
-- sometimes concealing extmarks are not removed. Remove after 0.11.1 release.
-- See https://github.com/neovim/neovim/issues/33333
H.ensure_no_concealed_lines = function(buf_id)
  local ts_ns_id = vim.api.nvim_get_namespaces()['nvim.treesitter.highlighter']
  pcall(vim.api.nvim_buf_clear_namespace, buf_id, ts_ns_id, 0, -1)
end
if vim.fn.has('nvim-0.11') == 0 then H.ensure_no_concealed_lines = function(buf_id) end end

-- Neovim>=0.11 has markdown codeblock delimiters hidden. Neovim<0.11 shows
-- them as empty line (so ignore only top and bottom for more compact view).
H.compute_visible_md_lines = function(lines)
  return vim.tbl_filter(function(l) return l:find('^```%S*$') == nil end, lines)
end
if vim.fn.has('nvim-0.11') == 0 then
  H.compute_visible_md_lines = function(lines)
    if lines[1]:find('^```%S*$') ~= nil then table.remove(lines, 1) end
    if lines[#lines]:find('^```$') ~= nil then table.remove(lines, #lines) end
    return lines
  end
end

H.wrap_in_codeblock = function(x) return string.format('```%s\n%s\n```', vim.bo.filetype:match('^[^%.]*'), vim.trim(x)) end

-- TODO: Remove after compatibility with Neovim=0.9 is dropped
H.islist = vim.fn.has('nvim-0.10') == 1 and vim.islist or vim.tbl_islist

H.get_buf_lsp_clients = function() return vim.lsp.get_clients({ bufnr = 0 }) end
if vim.fn.has('nvim-0.10') == 0 then H.get_buf_lsp_clients = function() return vim.lsp.buf_get_clients() end end

-- TODO: Remove after compatibility with Neovim=0.10 is dropped
H.make_position_params = function(context)
  local res = vim.lsp.util.make_position_params()
  res.context = context
  return res
end
if vim.fn.has('nvim-0.11') == 1 then
  -- Use callable `params` to workaround mandatory non-nil `offset_encoding` in
  -- `vim.lsp.util.make_position_params()` on Neovim>=0.11
  H.make_position_params = function(context)
    return function(client, _)
      local res = vim.lsp.util.make_position_params(0, client.offset_encoding)
      res.context = context
      return res
    end
  end
end

-- TODO: Remove after compatibility with Neovim=0.10 is dropped
H.client_request = function(client, method, params, handler, bufnr)
  local ok, request_id = client:request(method, params, handler, bufnr)
  return ok and function() pcall(client.cancel_request, client, request_id) end or function() end
end
if vim.fn.has('nvim-0.11') == 0 then
  H.client_request = function(client, method, params, handler, bufnr)
    local ok, request_id = client.request(method, params, handler, bufnr)
    return ok and function() pcall(client.cancel_request, request_id) end or function() end
  end
end

return MiniCompletion
