--- *mini.pick* Pick anything
---
--- MIT License Copyright (c) 2023 Evgeni Chasnovski

--- Features:
---
--- - Single window general purpose interface for picking element from any array.
---
--- - On demand toggleable preview and info views.
---
--- - Interactive query matching (filter+sort) with fast non-blocking default
---   which does fuzzy matching and allows other modes (|MiniPick.default_match()|).
---
--- - Built-in pickers (see |MiniPick.builtin|):
---     - Files.
---     - Pattern match (for fixed pattern or with live feedback; both allow
---       file filtering via glob patterns).
---     - Buffers.
---     - Help tags.
---     - CLI output.
---     - Resume latest picker.
---
--- - |:Pick| command to work with extensible |MiniPick.registry|.
---
--- - |vim.ui.select()| implementation. To adjust, use |MiniPick.ui_select()|
---   or save-restore `vim.ui.select` manually after calling |MiniPick.setup()|.
---
--- - Rich and customizable built-in |MiniPick-actions| when picker is active:
---     - Manually change currently focused item.
---     - Scroll vertically and horizontally.
---     - Toggle preview or info view.
---     - Mark/unmark items to choose later.
---     - Refine current matches (make them part of a new picker).
---     - And many more.
---
--- - Minimal yet flexible |MiniPick-source| specification with:
---     - Items (array, callable, or manually set later).
---     - Source name.
---     - Working directory.
---     - Matching algorithm.
---     - Way matches are shown in main window.
---     - Item preview.
---     - "On choice" action for current and marked items.
---
--- - Custom actions/keys can be configured globally, per buffer, or per picker.
---
--- - Out of the box support for 'ignorecase' and 'smartcase'.
---
--- - Match caching to increase responsiveness on repeated prompts.
---
--- Notes:
--- - Works on all supported versions but Neovim>=0.10 will give more visual
---   feedback in floating window footer.
---
--- - For more pickers see |MiniExtra.pickers|.
---
--- Sources with more details:
--- - |MiniPick-overview|
--- - |MiniPick-source|
--- - |MiniPick-actions|
--- - |MiniPick-examples|
--- - |MiniPick.builtin|
---
--- # Dependencies ~
---
--- Suggested dependencies (provide extra functionality, will work without them):
---
--- - Enabled |mini.icons| module to show icons near the items for actual paths.
---   Falls back to 'nvim-tree/nvim-web-devicons' plugin or no icons will be used.
---
--- - *MiniPick-cli-tools* CLI tool(s) to power |MiniPick.builtin.files()|,
---   |MiniPick.builtin.grep()|, and |MiniPick.builtin.grep_live()| built-in pickers:
---     - `rg` (github.com/BurntSushi/ripgrep; enough for all three; recommended).
---     - `fd` (github.com/sharkdp/fd; for `files` only).
---     - `git` (github.com/git/git; enough for all three).
---
---   Note: CLI tools are called only with basic arguments needed to get items.
---   To customize the output, use their respective configuration approaches.
---   Here are some examples of where to start:
---     - github.com/BurntSushi/ripgrep/blob/master/GUIDE.md#configuration-file
---     - github.com/sharkdp/fd#excluding-specific-files-or-directories
---     - git-scm.com/docs/gitignore
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.pick').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `MiniPick`
--- which you can use for scripting or manually (with `:lua MiniPick.*`).
---
--- See |MiniPick.config| for available config settings.
---
--- You can override runtime config settings locally to buffer inside
--- `vim.b.minipick_config` which should have same structure as `MiniPick.config`.
--- See |mini.nvim-buffer-local-config| for more details.
---
--- # Comparisons ~
---
--- - [nvim-telescope/telescope.nvim](https://github.com/nvim-telescope/telescope.nvim):
---     - The main inspiration for this module, so there is significant overlap.
---     - Has three (or two) window UI (prompt, matches, preview), while this
---       module combines everything in one window. It allows more straightforward
---       customization for unusual scenarios.
---     - Default match algorithm is somewhat slow, while this module should
---       match relatively lag-free for at least 100K+ items.
---     - Has many built-in pickers, while this module has handful at its core
---       relying on other 'mini.nvim' modules to provide more (see |mini.extra|).
---
--- - [ibhagwan/fzf-lua](https://github.com/ibhagwan/fzf-lua):
---     - Mostly same comparison as with 'nvim-telescope/telescope.nvim'.
---     - Requires [junegunn/fzf](https://github.com/junegunn/fzf) installed to
---       power fuzzy matching, while this module provides built-in Lua matching.
---
--- # Highlight groups ~
---
--- - `MiniPickBorder` - window border.
--- - `MiniPickBorderBusy` - window border while picker is busy processing.
--- - `MiniPickBorderText` - non-prompt on border.
--- - `MiniPickCursor` - cursor during active picker (hidden by default).
--- - `MiniPickIconDirectory` - default icon for directory.
--- - `MiniPickIconFile` - default icon for file.
--- - `MiniPickHeader` - headers in info buffer and previews.
--- - `MiniPickMatchCurrent` - current matched item.
--- - `MiniPickMatchMarked` - marked matched items.
--- - `MiniPickMatchRanges` - ranges matching query elements.
--- - `MiniPickNormal` - basic foreground/background highlighting.
--- - `MiniPickPreviewLine` - target line in preview.
--- - `MiniPickPreviewRegion` - target region in preview.
--- - `MiniPickPrompt` - prompt.
--- - `MiniPickPromptCaret` - caret in prompt.
--- - `MiniPickPromptPrefix` - prefix of the prompt.
---
--- To change any highlight group, set it directly with |nvim_set_hl()|.
---@tag MiniPick

--- To allow user customization and integration of external tools, certain |User|
--- autocommand events are triggered under common circumstances:
---
--- - `MiniPickMatch` - just after updating query matches or setting items.
--- - `MiniPickStart` - just after picker has started.
--- - `MiniPickStop` - just before picker is stopped.
---@tag MiniPick-events

--- General idea is to take array of objects, display them with interactive
--- filter/sort/navigate/preview, and allow to choose one or more items.
---
--- # How to start a picker ~
---
--- - Use |MiniPick.start()| with `opts.source` defining |MiniPick-source|.
---   Example: `MiniPick.start({ source = { items = vim.fn.readdir('.') } })`
---
--- - Use any of |MiniPick.builtin| pickers directly.
---   Example: `MiniPick.builtin.files({ tool = 'git' })`
---
--- - Use |:Pick| command which uses customizable pickers from |MiniPick.registry|.
---   Example: `:Pick files tool='git'`
---
--- # User interface ~
---
--- UI consists from a single window capable of displaying three different views:
--- - "Main" - where current query matches are shown.
--- - "Preview" - preview of current item (toggle with `<Tab>`).
--- - "Info" - general info about picker and its state (toggle with `<S-Tab>`).
---
--- Current prompt is displayed at the top left of the window border with vertical
--- line indicating caret (current input position).
---
--- Bottom part of window border displays (in Neovim>=0.10) extra visual feedback:
--- - Left part is a picker name.
--- - Right part contains information in the format >
---
---   <current index in matches> | <match count> | <marked count> / <total count>
--- <
--- When picker is busy (like if there are no items yet set or matching is active)
--- window border changes color to be `MiniPickBorderBusy` after `config.delay.busy`
--- milliseconds of idle time.
---
--- # Life cycle ~
---
--- - Type characters to filter and sort matches. It uses |MiniPick.default_match()|
---   with `query` being an array of pressed characters.
---   Overview of how it matches:
---     - If query starts with `'`, the match is exact.
---     - If query starts with `^`, the match is exact at start.
---     - If query ends with `$`, the match is exact at end.
---     - If query starts with `*`, the match is forced to be fuzzy.
---     - Otherwise match is fuzzy.
---     - Sorting is done to first minimize match width and then match start.
---       Nothing more: no favoring certain places in string, etc.
---
--- - Type special keys to perform |MiniPick-actions|. Here are some basic ones:
---     - `<C-n>` / `<Down>` moves down; `<C-p>` / `<Up>` moves up.
---     - `<Left>` / `<Right>` moves prompt caret left / right.
---     - `<S-Tab>` toggles information window with all available mappings.
---     - `<Tab>` toggles preview.
---     - `<C-x>` / `<C-a>` toggles current / all item(s) as (un)marked.
---     - `<C-Space>` / `<M-Space>` makes all matches or marked items as new picker.
---     - `<CR>` / `<M-CR>` chooses current/marked item(s).
---     - `<Esc>` / `<C-c>` stops picker.
---
--- # Implementation details ~
---
--- - Processing key typing is done via a dedicated key query process for more
---   control over their side effects. As a result, regular mappings don't work
---   here and picker's window needs to be current as long as it is shown.
---   Changing window focus leads to automatic picker stop (after small delay).
--- - Any picker is non-blocking but waits to return the chosen item. Example:
---   `file = MiniPick.builtin.files()` allows other actions to be executed when
---   picker is shown while still assigning `file` with value of the chosen item.
---@tag MiniPick-overview

--- Source is defined as a `source` field inside one of (in increasing priority):
--- - |MiniPick.config| - has global effect.
--- - `vim.b.minipick_config` - has buffer-local effect.
--- - `opts.source` in picker call - has effect for that particular call.
---
--- Example of source to choose from |arglist|: >lua
---
---   { items = vim.fn.argv, name = 'Arglist' }
--- <
--- Note: this is mostly useful for writing pickers. Can safely skip if you
--- want to just use provided pickers.
---
--- # Items ~
--- *MiniPick-source.items*
---
--- `source.items` defines items to choose from. It should be one of the following:
--- - Array of objects which can have different types. Any type is allowed.
--- - `nil`. Picker waits for explicit |MiniPick.set_picker_items()| call.
--- - Callable returning any of the previous types. Will be called once on start
---   with source's `cwd` set as |current-directory|.
---
--- *MiniPick-source.items-stritems*
--- Matching is done for items array based on the string representation of its
--- elements (here called "stritems"). For single item it is computed as follows:
--- - Callable is called once with output used in next steps.
--- - String item is used as is.
--- - String <text> field of table item is used (if present).
--- - Use output of |vim.inspect()|.
---
--- Example: >lua
---
---   items = { 'aaa.txt', { text = 'bbb' }, function() return 'ccc' end }
---   -- corresponding stritems are { 'aaa.txt', 'bbb', 'ccc' }
--- <
--- Default value is `nil`, assuming it always be supplied by the caller.
---
--- *MiniPick-source.items-common*
--- There are some recommendations for common item types in order for them to work
--- out of the box with |MiniPick.default_show()|, |MiniPick.default_preview()|,
--- |MiniPick.default_choose()|, |MiniPick.default_choose_marked()|:
---
--- - Path (file or directory). Use string or `path` field of a table. Path can
---   be either absolute, relative to the `source.cwd`, or have a general URI format
---   (only if supplied as table field).
---   Examples: `'aaa.txt'`, `{ path = 'aaa.txt' }`
---
--- - Buffer. Use buffer id as number, string, or `bufnr` / `buf_id` / `buf`
---   field of a table (any name is allowed).
---   Examples: `1`, `'1'`, `{ bufnr = 1 }`, `{ buf_id = 1 }`, `{ buf = 1 }`
---
--- - Line in file or buffer. Use table representation with `lnum` field with line
---   number (starting from 1) or string in "<path>\0<line>" format (`\0` is
---   an actual null character; don't escape the slash; may need to be `\000`).
---   Examples: >lua
---
---     { path = 'aaa.txt', lnum = 2 }, 'aaa.txt\0002', { bufnr = 1, lnum = 3 }
--- <
--- - Position in file or buffer. Use table representation with `lnum` and `col`
---   fields with line and column numbers (starting from 1) or string in
---   "<path>\0<line>\0<col>" format (`\0` is an actual null character, don't
---   escape the slash; may need to be `\000`).
---   Examples: >lua
---
---     { path = 'aaa.txt', lnum = 2, col = 3 }, 'aaa.txt\0' .. '2\0003',
---     { bufnr = 1, lnum = 3, col = 4 }
--- <
--- - Region in file or buffer. Use table representation with `lnum`, `col`,
---   `end_lnum`, `end_col` fields for start and end line/column. All numbers
---   start from 1, end line is inclusive, end column is exclusive.
---   This naming is similar to |getqflist()| and |diagnostic-structure|.
---   Examples: >lua
---
---     { path = 'aaa.txt', lnum = 2, col = 3, end_lnum = 4, end_col = 5 },
---     { bufnr = 1, lnum = 3, col = 4, end_lnum = 5, end_col = 6 }
--- <
--- Note: all table items will benefit from having `text` field for better matching.
---
--- # Name ~
--- *MiniPick-source.name*
---
--- `source.name` defines the name of the picker to be used for visual feedback.
---
--- Default value is "<No name>".
---
--- # Current working directory ~
--- *MiniPick-source.cwd*
---
--- `source.cwd` is a string defining the current working directory in which
--- picker operates. It should point to a valid actually present directory path.
--- This is a part of source to allow persistent way to use relative paths,
--- i.e. not depend on current directory being constant after picker start.
--- It also makes the |MiniPick.builtin.resume()| picker more robust.
---
--- It will be set as local |current-directory| (|:lcd|) of picker's main window
--- to allow simpler code for "in window" functions (choose/preview/custom/etc.).
---
--- Default value is |current-directory|.
---
--- # Match ~
--- *MiniPick-source.match*
---
--- `source.match` is a callable defining how stritems
--- (see |MiniPick-source.items-stritems|) are matched (filtered and sorted) based
--- on the query.
---
--- It will be called with the following arguments:
--- - `stritems` - all available stritems for current picker.
--- - `inds` - array of `stritems` indexes usually pointing at current matches.
---   It does point to current matches in the case of interactively appending
---   character at the end of the query. It assumes that matches for such bigger
---   query is a subset of previous matches (implementation can ignore it).
---   This can be utilized to increase performance by checking fewer stritems.
--- - `query` - array of strings. Usually (like is common case of user interactively
---   typing query) each string represents one character. However, any strings are
---   allowed, as query can be set with |MiniPick.set_picker_query()|.
---
--- It should either return array of match indexes for stritems elements matching
--- the query (synchronous) or explicitly use |MiniPick.set_picker_match_inds()|
--- to set them (may be asynchronous).
---
--- Notes:
--- - The result can be any array of `stritems` indexes, i.e. not necessarily
---   a subset of input `inds`.
---
--- - Both `stritems` and `query` depend on values of 'ignorecase' and 'smartcase'.
---   If query shows "ignore case" properties (only 'ignorecase' is set or both
---   'ignorecase' / 'smartcase' are set and query has only lowercase characters),
---   then `stritems` and `query` will have only lowercase characters.
---   This allows automatic support for case insensitive matching while being
---   faster and having simpler match function implementation.
---
--- - Writing custom `source.match` usually means also changing |MiniPick-source.show|
---   because it is used to highlight stritems parts actually matching the query.
---
--- Example of simple "exact" `match()` preserving initial order: >lua
---
---   local match_exact = function(stritems, inds, query)
---     local prompt_pattern = vim.pesc(table.concat(query))
---     local f = function(i) return stritems[i]:find(prompt_pattern) ~= nil end
---     return vim.tbl_filter(f, inds)
---   end
---   -- For non-blocking version see `:h MiniPick.poke_is_picker_active()`
--- <
--- Default value is |MiniPick.default_match()|.
---
--- # Show ~
--- *MiniPick-source.show*
---
--- `source.show` is a callable defining how matched items are shown in the window.
---
--- It will be called with the following arguments:
--- - `buf_id` - identifier of the target buffer.
--- - `items_to_show` - array of actual items to be shown in `buf_id`. This is
---   a subset of currently matched items computed to fit in current window view.
--- - `query` - array of strings. Same as in `source.match`.
---
--- It should update buffer `buf_id` to visually represent `items_to_show`
--- __one item per line starting from line one__ (it shouldn't depend on
--- `options.content_from_bottom`). This also includes possible visualization
--- of which parts of stritem actually matched query.
---
--- Example (assuming string items; without highlighting): >lua
---
---   local show_prepend = function(buf_id, items_arr, query)
---     local lines = vim.tbl_map(function(x) return 'Item: ' .. x end, items_arr)
---     vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
---   end
--- <
--- Default value is |MiniPick.default_show()|.
---
--- # Preview ~
--- *MiniPick-source.preview*
---
--- `source.preview` is a callable defining how item preview is done.
---
--- It will be called with the following arguments:
--- - `buf_id` - identifier of the target buffer. Note: for every separate instance
---   of item previewing new scratch buffer is be created.
--- - `item` - item to preview.
---
--- It should update buffer `buf_id` to visually represent `item`. It can also
--- directly set another buffer in picker's main window, but usually it is more
--- robust to update given `buf_id` directly.
---
--- Example: >lua
---
---   local preview_inspect = function(buf_id, item)
---     local lines = vim.split(vim.inspect(item), '\n')
---     vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
---   end
--- <
--- Default value is |MiniPick.default_preview()|.
---
--- # Choose an item ~
--- *MiniPick-source.choose*
---
--- `source.choose` is a callable defining what to do when an item is chosen.
---
--- It will be called with the following arguments:
--- - `item` - chosen item. Always non-`nil`.
---
--- It should perform any intended "choose" action for an item and return
--- a value indicating whether picker should continue (i.e. not stop):
--- `nil` and `false` will stop picker, other values will continue.
---
--- Notes:
--- - It is called when picker window is still current. Use `windows.target` value
---   from |MiniPick.get_picker_state()| output to do something with target window.
---
--- Example: >lua
---
---   local choose_file_continue = function(item)
---     if vim.fn.filereadable(item) == 0 then return end
---     vim.api.nvim_win_call(
---       MiniPick.get_picker_state().windows.main,
---       function() vim.cmd('edit ' .. item) end
---     )
---     return true
---   end
--- <
--- Default value is |MiniPick.default_choose()|.
---
--- # Choose marked items ~
--- *MiniPick-source.choose_marked*
---
--- `source.choose_marked` is a callable defining what to do when marked items
--- (see |MiniPick-actions-mark|) are chosen. Serves as a companion to
--- `source.choose` which can choose several items.
---
--- It will be called with the following arguments:
--- - `items_marked` - array of marked items. Can be empty.
---
--- It should perform any intended "choose" action for several items and return
--- a value indicating whether picker should continue (i.e. not stop):
--- `nil` and `false` will stop picker, other values will continue.
---
--- Notes:
--- - It is called when picker window is still current. Use `windows.target` value
---   from |MiniPick.get_picker_state()| output to do something with target window.
---
--- Example: >lua
---
---   local choose_marked_print = function(items) print(vim.inspect(items)) end
--- <
--- Default value is |MiniPick.default_choose_marked()|.
---@tag MiniPick-source

--- When picker is active, `mappings` table defines a set of special keys which when
--- pressed will execute certain actions. Those can be of two types:
--- - Built-in: actions present in default `config.mappings`. Can be only overridden
---   with a different key.
--- - Custom: user defined actions. Should be a table with `char` and `func` fields.
---
---
--- # Built-in ~
---
--- ## Caret ~
--- *MiniPick-actions-caret*
---
--- User can add character not only at query end, but more generally at caret.
---
--- - `mappings.caret_left` - move caret to left.
--- - `mappings.caret_right` - move caret to right.
---
--- ## Choose ~
--- *MiniPick-actions-choose*
---
--- Choose is a fundamental action that actually implements the intent of
--- calling a picker, i.e. pick an item.
---
--- - `mappings.choose` - choose as is, i.e. apply `source.choose` for current item.
--- - `mappings.choose_in_split` - make horizontal split at target window, update
---   target window to the new split, and choose.
--- - `mappings.choose_in_tabpage` - same as `choose_in_split`, but create tabpage.
--- - `mappings.choose_in_vsplit` - same as `choose_in_split`, but split vertically.
--- - `mappings.choose_marked` - choose marked items as is, i.e.
---   apply `source.choose_marked` at current marked items.
---
--- ## Delete ~
--- *MiniPick-actions-delete*
---
--- Delete actions are for deleting elements from query.
---
--- - `mappings.delete_char` - delete one character to the left.
--- - `mappings.delete_char_right` - delete one character to the right.
--- - `mappings.delete_left` - delete everything to the left (like |i_CTRL-U|).
--- - `mappings.delete_word` - delete word to the left (like |i_CTRL-W|).
---
--- ## Mark ~
--- *MiniPick-actions-mark*
---
--- Marking is an action of adding certain items to a separate list which then can
--- be chosen with `mappings.choose_marked` (for example, sent to quickfix list).
--- This is a companion to a regular choosing which can pick only one item.
---
--- - `mappings.mark` - toggle marked/unmarked state of current item.
--- - `mappings.mark_all` - toggle marked/unmarked state (mark all if not all
---   marked; unmark all otherwise) of all currently matched items.
---
--- Notes:
--- - Marks persist across queries and matches. For example, user can make a query
---   with marking all matches several times and marked items from all queries
---   will be preserved.
---
--- ## Move ~
--- *MiniPick-actions-move*
---
--- Move is a fundamental action of changing which item is current.
---
--- - `mappings.move_down` - change focus to the item below.
--- - `mappings.move_start` change focus to the first currently matched item
--- - `mappings.move_up` - change focus to the item above.
---
--- Notes:
--- - Up and down wrap around edges: `move_down` on last item moves to first,
---   `move_up` on first moves to last.
--- - Moving when preview or info view is shown updates the view with new item.
--- - These also work with non-overridable alternatives:
---     - `<Down>` moves down.
---     - `<Home>` moves to first matched.
---     - `<Up>` moves up.
---
--- ## Paste ~
--- *MiniPick-actions-paste*
---
--- Paste is an action to paste content of |registers| at caret.
---
--- - `mappings.paste` - paste from register defined by the next key press.
---
--- Notes:
--- - Does not support expression register `=`.
--- - Supports special cases of register: <C-f> (as |c_CTRL-R_CTRL-F|),
---   <C-w> (as |c_CTRL-R_CTRL-W|), <C-a> (as |c_CTRL-R_CTRL-A|),
---   <C-l> (as |c_CTRL-R_CTRL-L|).
---
--- ## Refine ~
--- *MiniPick-actions-refine*
---
--- Refine is an action that primarily executes the following:
--- - Takes certain items and makes them be all items (in order they are present).
--- - Resets query.
--- - Updates `source.match` to be the one from config.
---
--- - `mappings.refine` - refine currently matched items.
--- - `mappings.refine_marked` - refine currently marked items.
---
--- This action is useful in at least two cases:
--- - Perform consecutive "narrowing" queries. Example: to get items that contain
---   both "hello" and "world" exact matches (in no particular order) with default
---   matching, type "'hello" (notice "'" at the start) followed by `<C-Space>` and
---   another "'world".
--- - Reset `match` to default. Particularly useful in |MiniPick.builtin.grep_live()|
---   and |MiniExtra.pickers.lsp()| with "workspace_symbol_live" scope.
---
--- ## Scroll ~
--- *MiniPick-actions-scroll*
---
--- Scroll is an action to either move current item focus further than to the
--- neighbor item or adjust window view to see more information.
---
--- - `mappings.scroll_down` - when matches are shown, go down by the amount of
---   visible matches. In preview and info view - scroll down as with |CTRL-F|.
--- - `mappings.scroll_left` - scroll left as with |zH|.
--- - `mappings.scroll_right` - scroll right as with |zL|.
--- - `mappings.scroll_up` - when matches are shown, go up by the amount of
---   visible matches. In preview and info view - scroll up as with |CTRL-B|.
---
--- ## Stop ~
--- *MiniPick-actions-stop*
---
--- `mappings.stop` stops the picker. <C-c> also always stops the picker.
---
---
--- ## Toggle ~
--- *MiniPick-actions-toggle*
---
--- Toggle action is a way to change view: show if target is not shown, reset to
--- main view otherwise.
---
--- - `mappings.toggle_info` - toggle info view.
--- - `mappings.toggle_preview` - toggle preview.
---
--- Note:
--- - Updating query in any way resets window view to show matches.
--- - Moving current item focus keeps preview or info view with updated item.
---
--- # Custom ~
--- *MiniPick-actions-custom*
---
--- Along with built-in actions, users can define custom actions. This can be
--- done by supplying custom elements to `mappings` table. The field defines action
--- name (used to infer an action description in info view). The value is a table
--- with the following fields:
--- - <char> `(string)` - single character acting as action trigger.
--- - <func> `(function)` - callable to be executed without arguments after
---   user presses <char>. Its return value is treated as "should stop picker
---   after execution", i.e. returning nothing, `nil`, or `false` continues
---   picker while everything else (prefer `true`) stops it.
---
--- Example of `execute` custom mapping: >lua
---
---   execute = {
---     char = '<C-e>',
---     func = function() vim.cmd(vim.fn.input('Execute: ')) end,
---   }
--- <
---@tag MiniPick-actions

--- # Disable icons ~
---
--- Disable icons in |MiniPick.builtin| pickers related to paths: >lua
---
---   local pick = require('mini.pick')
---   pick.setup({ source = { show = pick.default_show } })
--- <
--- # Switch toggle and move keys ~
--- >lua
---   require('mini.pick').setup({
---     mappings = {
---       toggle_info    = '<C-k>',
---       toggle_preview = '<C-p>',
---       move_down      = '<Tab>',
---       move_up        = '<S-Tab>',
---     }
---   })
--- <
--- # Different window styles ~
--- >lua
---   -- Different border
---   { window = { config = { border = 'double' } } }
---
---   -- "Cursor tooltip"
---   {
---     window = {
---       config = {
---         relative = 'cursor', anchor = 'NW',
---         row = 0, col = 0, width = 40, height = 20,
---       },
---     },
---   }
---
---   -- Centered on screen
---   local win_config = function()
---     local height = math.floor(0.618 * vim.o.lines)
---     local width = math.floor(0.618 * vim.o.columns)
---     return {
---       anchor = 'NW', height = height, width = width,
---       row = math.floor(0.5 * (vim.o.lines - height)),
---       col = math.floor(0.5 * (vim.o.columns - width)),
---     }
---   end
---   { window = { config = win_config } }
--- <
---@tag MiniPick-examples

---@alias __pick_builtin_opts table|nil Options forwarded to |MiniPick.start()|.
---@alias __pick_builtin_local_opts table|nil Options defining behavior of this particular picker.
---@alias __pick_builtin_grep_globs <globs> `(table)` - array of string glob patterns to restrict search to
---     matching files. Supported only by "rg" and "git" tools, respects their
---     specific glob syntax and effects. Default: `{}` (no restriction).
---     Example: `{ '*.lua', 'lua/**' }` for Lua files and files in "lua" directory.

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local
---@diagnostic disable:cast-local-type

-- Module definition ==========================================================
local MiniPick = {}
local H = {}

--- Module setup
---
--- # :Pick ~
--- *:Pick*
---
--- Calling this function creates a `:Pick` user command. It takes picker name
--- from |MiniPick.registry| as mandatory first argument and executes it with
--- following (expanded, |expandcmd()|) |<f-args>| combined in a single table.
--- To add custom pickers, update |MiniPick.registry|.
---
--- Example: >vim
---
---   :Pick files tool='git'
---   :Pick grep pattern='<cword>'
--- <
---
--- It also sets custom |vim.ui.select()| implementation to use the module.
--- See |MiniPick.ui_select()|.
---
---@param config table|nil Module config table. See |MiniPick.config|.
---
---@usage >lua
---   require('mini.pick').setup() -- use default config
---   -- OR
---   require('mini.pick').setup({}) -- replace {} with your config table
--- <
MiniPick.setup = function(config)
  -- Export module
  _G.MiniPick = MiniPick

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Define behavior
  H.create_autocommands()

  -- Create default highlighting
  H.create_default_hl()

  -- Create user commands
  H.create_user_commands()

  -- Disable terminal emulator's pasting with active picker
  local paste_orig = vim.paste
  vim.paste = function(...)
    if not MiniPick.is_picker_active() then return paste_orig(...) end
    H.notify('Use `mappings.paste` (`<C-r>` by default) with "*" or "+" register.', 'HINT')
  end

  -- Set custom implementation
  vim.ui.select = MiniPick.ui_select
end

--stylua: ignore
--- Defaults ~
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text # Delays ~
---
--- `config.delay` defines plugin delays (in ms). All should be strictly positive.
---
--- `delay.async` is a delay between forcing asynchronous behavior. This usually
--- means making screen redraws and utilizing |MiniPick.poke_is_picker_active()|
--- (for example, to stop current matching if query has updated).
--- Smaller values give smoother user experience at the cost of more computations.
---
--- `delay.busy` is a delay between when some computation starts and showing
--- visual feedback about it by making window border to have `MiniPickBorderBusy`
--- highlight group.
--- Smaller values will give feedback faster at the cost of feeling like flicker.
---
--- # Mappings ~
---
--- `config.mappings` defines keys for special actions to be triggered after certain
--- keys. See |MiniPick-actions| for more information.
---
--- # Options ~
---
--- `config.options` contains some general purpose options.
---
--- `options.content_from_bottom` is a boolean indicating whether content should be
--- shown from bottom to top. That means that best matches will be shown at
--- the bottom. Note: for better experience use Neovim>=0.10, which has floating
--- window footer capability. Default: `false`.
---
--- `options.use_cache` is a boolean indicating whether match results should be
--- cached per prompt (i.e. concatenated query). This results into faster response
--- on repeated prompts (like when deleting query entries) at the cost of using
--- more memory. Default: `false`.
---
--- # Source ~
---
--- `config.source` defines fallbacks for source specification. For example, this
--- can be used to change default `match` to use different implementation or `show`
--- to not show icons for some |MiniPick.builtin| pickers (see |MiniPick-examples|).
--- See |MiniPick-source| for more information.
---
--- # Window ~
---
--- `config.window` contains window specific configurations.
---
--- `window.config` defines a (parts of) default floating window config for the main
--- picker window. This can be either a table overriding some parts or a callable
--- returning such table. See |MiniPick-examples| for some examples.
---
--- `window.prompt_caret` defines how caret is displayed in window's prompt.
--- Default: '▏'.
---
--- `window.prompt_prefix` defines what prefix is used in window's prompt.
--- Default: '> '.
MiniPick.config = {
  -- Delays (in ms; should be at least 1)
  delay = {
    -- Delay between forcing asynchronous behavior
    async = 10,

    -- Delay between computation start and visual feedback about it
    busy = 50,
  },

  -- Keys for performing actions. See `:h MiniPick-actions`.
  mappings = {
    caret_left  = '<Left>',
    caret_right = '<Right>',

    choose            = '<CR>',
    choose_in_split   = '<C-s>',
    choose_in_tabpage = '<C-t>',
    choose_in_vsplit  = '<C-v>',
    choose_marked     = '<M-CR>',

    delete_char       = '<BS>',
    delete_char_right = '<Del>',
    delete_left       = '<C-u>',
    delete_word       = '<C-w>',

    mark     = '<C-x>',
    mark_all = '<C-a>',

    move_down  = '<C-n>',
    move_start = '<C-g>',
    move_up    = '<C-p>',

    paste = '<C-r>',

    refine        = '<C-Space>',
    refine_marked = '<M-Space>',

    scroll_down  = '<C-f>',
    scroll_left  = '<C-h>',
    scroll_right = '<C-l>',
    scroll_up    = '<C-b>',

    stop = '<Esc>',

    toggle_info    = '<S-Tab>',
    toggle_preview = '<Tab>',
  },

  -- General options
  options = {
    -- Whether to show content from bottom to top
    content_from_bottom = false,

    -- Whether to cache matches (more speed and memory on repeated prompts)
    use_cache = false,
  },

  -- Source definition. See `:h MiniPick-source`.
  source = {
    items = nil,
    name  = nil,
    cwd   = nil,

    match   = nil,
    show    = nil,
    preview = nil,

    choose        = nil,
    choose_marked = nil,
  },

  -- Window related options
  window = {
    -- Float window config (table or callable returning it)
    config = nil,

    -- String to use as caret in prompt
    prompt_caret = '▏',

    -- String to use as prefix in prompt
    prompt_prefix = '> ',
  },
}
--minidoc_afterlines_end

--- Start picker
---
--- Notes:
--- - If there is currently an active picker, it is properly stopped and new one
---   is started "soon" in the main event-loop (see |vim.schedule()|).
--- - Current window at the moment of this function call is treated as "target".
---   It will be set back as current after |MiniPick.stop()|.
---   See |MiniPick.get_picker_state()| and |MiniPick.set_picker_target_window()|.
---
---@param opts table|nil Options. Should have same structure as |MiniPick.config|.
---   Default values are inferred from there.
---   Usually should have proper |MiniPick-source.items| defined.
---
---@return any Item which was current when picker is stopped; `nil` if aborted.
MiniPick.start = function(opts)
  if MiniPick.is_picker_active() then
    -- Try proper 'key query process' stop
    MiniPick.stop()
    -- NOTE: Needs `defer_fn()` for `stop()` to properly finish code flow and
    -- not be executed before it
    return vim.defer_fn(function()
      -- NOTE: if `MiniPick.stop()` still didn't stop, force abort
      if MiniPick.is_picker_active() then H.picker_stop(H.pickers.active, true) end
      MiniPick.start(opts)
    end, 0.5)
  end

  H.cache = {}
  opts = H.validate_picker_opts(opts)
  local picker = H.picker_new(opts)
  H.pickers.active = picker

  H.picker_set_busy(picker, true)
  local items = H.expand_callable(opts.source.items)
  -- - Set items on next event loop to not block when computing stritems
  if H.islist(items) then vim.schedule(function() MiniPick.set_picker_items(items) end) end

  H.picker_track_lost_focus(picker)
  return H.picker_advance(picker)
end

--- Stop active picker
MiniPick.stop = function()
  if not MiniPick.is_picker_active() then return end
  H.cache.is_force_stop_advance = true
  if H.cache.is_in_getcharstr then vim.api.nvim_feedkeys('\3', 't', true) end
end

--- Refresh active picker
MiniPick.refresh = function()
  if not MiniPick.is_picker_active() then return end
  H.picker_update(H.pickers.active, false, true)
end

--- Default match
---
--- Filter target stritems to contain query and sort from best to worst matches.
---
--- Implements default value for |MiniPick-source.match|.
---
--- By default (if no special modes apply) it does the following fuzzy matching:
---
--- - Stritem contains query if it contains all its elements verbatim in the same
---   order (possibly with gaps, i.e. not strictly one after another).
---   Note: empty query and empty string element is contained in any string.
---
--- - Sorting is done with the following ordering (same as in |mini.fuzzy|):
---     - The smaller the match width (end column minus start column) the better.
---     - Among same match width, the smaller start column the better.
---     - Among same match width and start column, preserve original order.
---
--- Notes:
--- - Most common interactive usage results into `query` containing one typed
---   character per element.
---
--- # Special modes ~
---
--- - Forced modes:
---     - Query starts with "*": match the rest fuzzy (without other modes).
---     - Query starts with "'": match the rest exactly (without gaps).
---
--- - Place modes:
---     - Query starts with '^': match the rest exactly at start.
---     - Query ends with '$': match the rest exactly at end.
---     - Both modes can be used simultaneously.
---
--- - Grouped: query contains at least one whitespace element. Output is computed
---   as if query is split at whitespace indexes with concatenation between them.
---
--- Precedence of modes:
---   "forced exact" = "forced fuzzy" > "place start/end" > "grouped" > "default"
---
--- # Examples ~
---
--- Assuming `stritems` are `{ '_abc', 'a_bc', 'ab_c', 'abc_' }`, here are some
--- example matches based on prompt (concatenated query): >
---
---   | Prompt | Matches                |
---   |--------|------------------------|
---   | abc    | All                    |
---   | *abc   | All                    |
---   |        |                        |
---   | 'abc   | abc_, _abc             |
---   | *'abc  | None (no "'" in items) |
---   |        |                        |
---   | ^abc   | abc_                   |
---   | *^abc  | None (no "^" in items) |
---   |        |                        |
---   | abc$   | _abc                   |
---   | *abc$  | None (no "$" in items) |
---   |        |                        |
---   | ab c   | abc_, _abc, ab_c       |
---   | *ab c  | None (no " " in items) |
--- <
--- Having query `{ 'ab', 'c' }` is the same as "ab c" prompt.
---
--- You can have a feel of how this works with this command: >lua
---
---   MiniPick.start({ source = { items = { '_abc', 'a_bc', 'ab_c', 'abc_' } } })
--- <
---@param stritems table Array of all stritems.
---@param inds table Array of `stritems` indexes to match. All of them should point
---   at string elements of `stritems`. No check is done for performance reasons.
---@param query table Array of strings.
---@param opts table|nil Options. Possible fields:
---   - <sync> `(boolean)` - Whether to match synchronously. Default: `false`.
---   - <preserve_order> `(boolean)` - Whether to skip sort step. Default: `false`.
---
---@return table|nil Depending on whether computation is synchronous (either `opts.sync`
---   is `true` or there is an active picker):
---   - If yes, array of `stritems` indexes matching the `query` (from best to worst).
---   - If no, `nil` is returned with |MiniPick.set_picker_match_inds()| used later.
MiniPick.default_match = function(stritems, inds, query, opts)
  opts = opts or {}
  local is_sync = opts.sync or not MiniPick.is_picker_active()
  local set_match_inds = is_sync and function(x) return x end or MiniPick.set_picker_match_inds
  local f = function()
    if #query == 0 then return set_match_inds(H.seq_along(stritems)) end
    local match_data, match_type = H.match_filter(inds, stritems, query)
    if match_data == nil then return end
    if match_type == 'useall' then return set_match_inds(H.seq_along(stritems)) end
    if opts.preserve_order then return set_match_inds(H.match_no_sort(match_data)) end
    local match_inds = H.match_sort(match_data)
    if match_inds == nil then return end
    return set_match_inds(match_inds)
  end

  if is_sync then return f() end
  coroutine.resume(coroutine.create(f))
end

--- Default show
---
--- Show items in a buffer and highlight parts that actually match query (assuming
--- match is done with |MiniPick.default_match()|). Lines are computed based on
--- the |MiniPick-source.items-stritems|.
---
--- Implements default value for |MiniPick-source.show|.
---
--- Uses the following highlight groups (see |mini.pick| for their description):
---
--- - `MiniPickIconDirectory`
--- - `MiniPickIconFile`
--- - `MiniPickMatchCurrent`
--- - `MiniPickMatchMarked`
--- - `MiniPickMatchRanges`
---
---@param buf_id number Identifier of target buffer.
---@param items table Array of items to show.
---@param query table Array of strings representing query.
---@param opts table|nil Options. Possible fields:
---   - <show_icons> `(boolean)` - whether to show icons for entries recognized as
---     valid actually present paths on disk (see |MiniPick-source.items-common|),
---     empty space otherwise. Tries to use `text` field as fallback for path.
---     Default: `false`. Note: |MiniPick.builtin| pickers showing file/directory
---     paths use `true` by default.
---   - <icons> `(table)` - table with fallback icons used if icon provider
---     does not itself supply default icons for category. Can have fields:
---       - <directory> `(string)` - icon for directory. Default: " ".
---       - <file> `(string)` - icon for file. Default: " ".
---       - <none> `(string)` - icon for non-valid path. Default: "  ".
MiniPick.default_show = function(buf_id, items, query, opts)
  local default_icons = { directory = ' ', file = ' ', none = '  ' }
  opts = vim.tbl_deep_extend('force', { show_icons = false, icons = default_icons }, opts or {})

  -- Compute and set lines. Compute prefix based on the whole items to allow
  -- separate `text` and `path` table fields (preferring second one).
  local get_prefix_data = opts.show_icons and function(item) return H.get_icon(item, opts.icons) end
    or function() return { text = '' } end
  local prefix_data = vim.tbl_map(get_prefix_data, items)

  local lines = vim.tbl_map(H.item_to_string, items)
  local tab_spaces = string.rep(' ', vim.o.tabstop)
  lines = vim.tbl_map(function(l) return l:gsub('%z', '│'):gsub('[\r\n]', ' '):gsub('\t', tab_spaces) end, lines)

  local lines_to_show = {}
  for i, l in ipairs(lines) do
    lines_to_show[i] = prefix_data[i].text .. l
  end

  H.set_buflines(buf_id, lines_to_show)

  -- Extract match ranges
  local ns_id = H.ns_id.ranges
  H.clear_namespace(buf_id, ns_id)

  if H.query_is_ignorecase(query) then
    lines, query = vim.tbl_map(H.tolower, lines), vim.tbl_map(H.tolower, query)
  end
  local match_data, match_type, query_adjusted = H.match_filter(H.seq_along(lines), lines, query)
  if match_data == nil then return end

  local match_ranges_fun = match_type == 'fuzzy' and H.match_ranges_fuzzy or H.match_ranges_exact
  local match_ranges = match_ranges_fun(match_data, query_adjusted, lines)

  -- Place range highlights accounting for possible shift due to prefixes
  local extmark_opts = { hl_group = 'MiniPickMatchRanges', hl_mode = 'combine', priority = 200 }
  for i = 1, #match_data do
    local row, ranges = match_data[i][3], match_ranges[i]
    local start_offset = prefix_data[row].text:len()
    for _, range in ipairs(ranges) do
      extmark_opts.end_row, extmark_opts.end_col = row - 1, start_offset + range[2]
      H.set_extmark(buf_id, ns_id, row - 1, start_offset + range[1] - 1, extmark_opts)
    end
  end

  -- Highlight prefixes
  if not opts.show_icons then return end
  local icon_extmark_opts = { hl_mode = 'combine', priority = 200 }
  for i = 1, #prefix_data do
    icon_extmark_opts.hl_group = prefix_data[i].hl
    icon_extmark_opts.end_row, icon_extmark_opts.end_col = i - 1, prefix_data[i].text:len()
    H.set_extmark(buf_id, ns_id, i - 1, 0, icon_extmark_opts)
  end
end

--- Default preview
---
--- Preview item. Logic follows the rules in |MiniPick-source.items-common|:
--- - File and buffer are shown at the start.
--- - Directory has its content listed.
--- - Line/position/region in file or buffer is shown at start.
--- - Others are shown directly with |vim.inspect()|.
---
--- Implements default value for |MiniPick-source.preview|.
---
--- Uses the following highlight groups (see |mini.pick| for their description):
---
--- - `MiniPickPreviewLine`
--- - `MiniPickPreviewRegion`
---
---@param buf_id number Identifier of target buffer.
---@param item any Item to preview.
---@param opts table|nil Options. Possible values:
---   - <n_context_lines> `(number)` - number of lines to load past target position
---     when reading from disk. Useful to explore context. Default: 'lines' twice.
---   - <line_position> `(string)` - where in the window to show item position.
---     One of "top", "center", "bottom". Default: "top".
MiniPick.default_preview = function(buf_id, item, opts)
  opts = vim.tbl_deep_extend('force', { n_context_lines = 2 * vim.o.lines, line_position = 'top' }, opts or {})
  local item_data = H.parse_item(item)
  if item_data.type == 'file' then return H.preview_file(buf_id, item_data, opts) end
  if item_data.type == 'directory' then return H.preview_directory(buf_id, item_data) end
  if item_data.type == 'buffer' then return H.preview_buffer(buf_id, item_data, opts) end
  if item_data.type == 'uri' then return H.preview_uri(buf_id, item_data, opts) end
  H.preview_inspect(buf_id, item)
end

--- Default choose
---
--- Choose item. Logic follows the rules in |MiniPick-source.items-common|:
--- - File uses |bufadd()| and sets cursor at the start of line/position/region.
--- - Buffer is set as current in target window and sets cursor similarly.
--- - Directory is called with |:edit| in the target window.
--- - Others have the output of |vim.inspect()| printed in Command line.
---
--- Implements default value for |MiniPick-source.choose|.
---
---@param item any Item to choose.
MiniPick.default_choose = function(item)
  if item == nil then return end
  local picker_state = MiniPick.get_picker_state()
  local win_target = picker_state ~= nil and picker_state.windows.target or vim.api.nvim_get_current_win()
  if not H.is_valid_win(win_target) then win_target = H.get_first_valid_normal_window() end

  local item_data = H.parse_item(item)
  if item_data.type == 'file' or item_data.type == 'directory' or item_data.type == 'uri' then
    return H.choose_path(win_target, item_data)
  end
  if item_data.type == 'buffer' then return H.choose_buffer(win_target, item_data) end
  H.choose_print(item)
end

--- Default choose marked items
---
--- Choose marked items. Logic follows the rules in |MiniPick-source.items-common|:
--- - If among items there is at least one file or buffer, quickfix list is opened
---   with all file or buffer lines/positions/regions.
--- - Otherwise, picker's `source.choose` is called on the first item.
---
--- Implements default value for |MiniPick-source.choose_marked|.
---
---@param items table Array of items to choose.
---@param opts table|nil Options. Possible fields:
---   - <list_type> `(string)` - which type of list to open. One of "quickfix"
---     or "location". Default: "quickfix".
MiniPick.default_choose_marked = function(items, opts)
  if not H.islist(items) then H.error('`items` should be an array') end
  if #items == 0 then return end
  opts = vim.tbl_deep_extend('force', { list_type = 'quickfix' }, opts or {})

  -- Construct a potential quickfix/location list
  local list = {}
  for _, item in ipairs(items) do
    local item_data = H.parse_item(item)
    if item_data.type == 'file' or item_data.type == 'buffer' or item_data.type == 'uri' then
      local entry = { bufnr = item_data.buf_id, filename = H.parse_uri(item_data.path) or item_data.path }
      entry.lnum, entry.col = item_data.lnum or 1, item_data.col or 1
      entry.text = (item_data.text or ''):gsub('%z', '│')
      entry.end_lnum, entry.end_col = item_data.end_lnum, item_data.end_col
      table.insert(list, entry)
    end
  end

  -- Fall back to choosing first item if no quickfix list was constructed
  local is_active = MiniPick.is_picker_active()
  if #list == 0 then
    if not is_active then return end
    local choose = MiniPick.get_picker_opts().source.choose
    return choose(items[1])
  end

  -- Set as quickfix or location list
  local title = '<No picker>'
  if is_active then
    ---@diagnostic disable:param-type-mismatch
    local source_name, prompt = MiniPick.get_picker_opts().source.name, table.concat(MiniPick.get_picker_query())
    title = source_name .. (prompt == '' and '' or (' : ' .. prompt))
  end
  local list_data = { items = list, title = title, nr = '$' }

  if opts.list_type == 'location' then
    local win_target = MiniPick.get_picker_state().windows.target
    if not H.is_valid_win(win_target) then win_target = H.get_first_valid_normal_window() end
    vim.fn.setloclist(win_target, {}, ' ', list_data)
    vim.schedule(function() vim.cmd('lopen') end)
  else
    vim.fn.setqflist({}, ' ', list_data)
    vim.schedule(function() vim.cmd('copen') end)
  end
end

--- Select rewrite
---
--- Function which can be used to directly override |vim.ui.select()| to use
--- 'mini.pick' for any "select" type of tasks.
--- Set automatically in |MiniPick.setup()|.
---
--- Implements required by `vim.ui.select()` signature, with some differencies:
--- - Allows `opts.preview_item` that returns an array of lines for item preview.
--- - Allows fourth `start_opts` argument to customize |MiniPick.start()| call.
---
--- Notes:
--- - `on_choice` is called when target window is current.
---
---@usage >lua
---   -- Customize with fourth argument inside a function wrapper
---   vim.ui.select = function(items, opts, on_choice)
---     local start_opts = { window = { config = { width = vim.o.columns } } }
---     return MiniPick.ui_select(items, opts, on_choice, start_opts)
---   end
--- <
--- To preserve original `vim.ui.select()`: >lua
---
---   local ui_select_orig = vim.ui.select
---   require('mini.pick').setup()
---   vim.ui.select = ui_select_orig
--- <
MiniPick.ui_select = function(items, opts, on_choice, start_opts)
  local format_item = opts.format_item or H.item_to_string
  local items_ext = {}
  for i = 1, #items do
    table.insert(items_ext, { text = format_item(items[i]), item = items[i], index = i })
  end

  local preview_item = vim.is_callable(opts.preview_item) and opts.preview_item
    or function(x) return vim.split(vim.inspect(x), '\n') end
  local preview = function(buf_id, item) H.set_buflines(buf_id, preview_item(item.item)) end

  local was_aborted = true
  local choose = function(item)
    was_aborted = false
    if item == nil then return end
    local win_target = MiniPick.get_picker_state().windows.target
    if not H.is_valid_win(win_target) then win_target = H.get_first_valid_normal_window() end
    vim.api.nvim_win_call(win_target, function()
      on_choice(items[item.index], item.index)
      MiniPick.set_picker_target_window(vim.api.nvim_get_current_win())
    end)
  end

  local source = { items = items_ext, name = opts.prompt or opts.kind, preview = preview, choose = choose }
  start_opts = vim.tbl_deep_extend('force', start_opts or {}, { source = source })
  local item = MiniPick.start(start_opts)
  if item == nil and was_aborted then on_choice(nil) end
end

--- Table with built-in pickers
MiniPick.builtin = {}

--- Pick from files
---
--- Lists all files recursively in all subdirectories. Tries to use one of the
--- CLI tools to create items (see |MiniPick-cli-tools|): `rg`, `fd`, `git`.
--- If none is present, uses fallback which utilizes |vim.fs.dir()|.
---
--- To customize CLI tool search, either use tool's global configuration approach
--- or directly |MiniPick.builtin.cli()| with specific command.
---
---@param local_opts __pick_builtin_local_opts
---   Possible fields:
---   - <tool> `(string)` - which tool to use. One of "rg", "fd", "git", "fallback".
---     Default: whichever tool is present, trying in that same order.
---@param opts __pick_builtin_opts
MiniPick.builtin.files = function(local_opts, opts)
  local_opts = vim.tbl_deep_extend('force', { tool = nil }, local_opts or {})
  local tool = local_opts.tool or H.files_get_tool()
  local show = H.get_config().source.show or H.show_with_icons
  local default_opts = { source = { name = string.format('Files (%s)', tool), show = show } }
  opts = vim.tbl_deep_extend('force', default_opts, opts or {})

  if tool == 'fallback' then
    local cwd = H.full_path(opts.source.cwd or vim.fn.getcwd())
    opts.source.items = function() H.files_fallback_items(cwd) end
    return MiniPick.start(opts)
  end

  return MiniPick.builtin.cli({ command = H.files_get_command(tool) }, opts)
end

--- Pick from pattern matches
---
--- Lists all pattern matches recursively in all subdirectories.
--- Tries to use one of the CLI tools to create items (see |MiniPick-cli-tools|):
--- `rg`, `git`. If none is present, uses fallback which utilizes |vim.fs.dir()| and
--- Lua pattern matches (NOT recommended in large directories).
---
--- To customize CLI tool search, either use tool's global configuration approach
--- or directly |MiniPick.builtin.cli()| with specific command.
--- Options 'ignorecase' and 'smartcase' are respected via forcing appropriate
--- flags to CLI tool (i.e. overriding tool's global config).
---
---@param local_opts __pick_builtin_local_opts
---   Possible fields:
---   - <tool> `(string)` - which tool to use. One of "rg", "git", "fallback".
---     Default: whichever tool is present, trying in that same order.
---   - <pattern> `(string)` - string pattern to search. If not given, asks user
---     interactively with |input()|.
---   - __pick_builtin_grep_globs
---@param opts __pick_builtin_opts
MiniPick.builtin.grep = function(local_opts, opts)
  local_opts = vim.tbl_extend('force', { tool = nil, pattern = nil, globs = {} }, local_opts or {})
  local tool = local_opts.tool or H.grep_get_tool()
  local globs = H.is_array_of(local_opts.globs, 'string') and local_opts.globs or {}
  local name_suffix = #globs == 0 and '' or (' | ' .. table.concat(globs, ', '))
  local show = H.get_config().source.show or H.show_with_icons
  local default_opts = { source = { name = string.format('Grep (%s%s)', tool, name_suffix), show = show } }
  opts = vim.tbl_deep_extend('force', default_opts, opts or {})

  local pattern = type(local_opts.pattern) == 'string' and local_opts.pattern or vim.fn.input('Grep pattern: ')
  if tool == 'fallback' then
    local cwd = H.full_path(opts.source.cwd or vim.fn.getcwd())
    opts.source.items = function() H.grep_fallback_items(pattern, cwd) end
    return MiniPick.start(opts)
  end

  return MiniPick.builtin.cli({ command = H.grep_get_command(tool, pattern, globs) }, opts)
end

--- Pick from pattern matches with live feedback
---
--- Perform pattern matching treating prompt as pattern. Gives live feedback on
--- which matches are found. Use |MiniPick-actions-refine| to revert to regular
--- matching. Use `<C-o>` to restrict search to files matching glob patterns.
--- Tries to use one of the CLI tools to create items (see |MiniPick-cli-tools|):
--- `rg`, `git`. If none is present, error is thrown (for performance reasons).
---
--- To customize search, use tool's global configuration approach.
--- Options 'ignorecase' and 'smartcase' are respected via forcing appropriate
--- flags to CLI tool (i.e. overriding tool's global config).
---
---@param local_opts __pick_builtin_local_opts
---   Possible fields:
---   - <tool> `(string)` - which tool to use. One of "rg", "git".
---     Default: whichever tool is present, trying in that same order.
---   - __pick_builtin_grep_globs
---     Use `<C-o>` custom mapping to add glob to the array.
---@param opts __pick_builtin_opts
MiniPick.builtin.grep_live = function(local_opts, opts)
  local_opts = vim.tbl_extend('force', { tool = nil, globs = {} }, local_opts or {})
  local tool = local_opts.tool or H.grep_get_tool()
  if tool == 'fallback' or not H.is_executable(tool) then H.error('`grep_live` needs non-fallback executable tool.') end

  local globs = H.is_array_of(local_opts.globs, 'string') and local_opts.globs or {}
  local name_suffix = #globs == 0 and '' or (' | ' .. table.concat(globs, ', '))
  local show = H.get_config().source.show or H.show_with_icons
  local default_source = { name = string.format('Grep live (%s%s)', tool, name_suffix), show = show }
  opts = vim.tbl_deep_extend('force', { source = default_source }, opts or {})

  local cwd = H.full_path(opts.source.cwd or vim.fn.getcwd())
  local set_items_opts, spawn_opts = { do_match = false, querytick = H.querytick }, { cwd = cwd }
  local process
  local match = function(_, _, query)
    pcall(vim.loop.process_kill, process)
    if H.querytick == set_items_opts.querytick then return end
    if #query == 0 then return MiniPick.set_picker_items({}, set_items_opts) end

    set_items_opts.querytick = H.querytick
    local command = H.grep_get_command(tool, table.concat(query), globs)
    process = MiniPick.set_picker_items_from_cli(command, { set_items_opts = set_items_opts, spawn_opts = spawn_opts })
  end

  local add_glob = function()
    local ok, glob = pcall(vim.fn.input, 'Glob pattern: ')
    if ok then table.insert(globs, glob) end
    name_suffix = #globs == 0 and '' or (' | ' .. table.concat(globs, ', '))
    MiniPick.set_picker_opts({ source = { name = string.format('Grep live (%s%s)', tool, name_suffix) } })
    MiniPick.set_picker_query(MiniPick.get_picker_query())
  end
  local mappings = { add_glob = { char = '<C-o>', func = add_glob } }

  opts = vim.tbl_deep_extend('force', opts or {}, { source = { items = {}, match = match }, mappings = mappings })
  return MiniPick.start(opts)
end

--- Pick from help tags
---
--- Notes:
--- - On choose directly executes |:help| command with appropriate modifier
---   (none, |:vertical|, |:tab|). This is done through custom mappings named
---   `show_help_in_{split,vsplit,tab}`. Not `choose_in_{split,vsplit,tab}` because
---   there is no split guarantee (like if there is already help window opened).
---
---@param local_opts __pick_builtin_local_opts
---   Possible fields:
---   - <default_split> `(string)` - direction of a split for `choose` action.
---     One of "horizontal", "vertical", "tab". Default: "horizontal".
---@param opts __pick_builtin_opts
MiniPick.builtin.help = function(local_opts, opts)
  local_opts = vim.tbl_deep_extend('force', { default_split = 'horizontal' }, local_opts or {})
  local default_modifier = ({ horizontal = '', vertical = 'vert ', tab = 'tab ' })[local_opts.default_split]
  if default_modifier == nil then H.error('`opts.default_split` should be one of "horizontal", "vertical", "tab"') end

  -- Get all tags
  local help_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[help_buf].buftype = 'help'
  -- - NOTE: no dedicated buffer name because it is immediately wiped out
  local tags = vim.api.nvim_buf_call(help_buf, function() return vim.fn.taglist('.*') end)
  vim.api.nvim_buf_delete(help_buf, { force = true })
  vim.tbl_map(function(t) t.text = t.name end, tags)

  -- NOTE: Choosing is done on next event loop to properly overcome special
  -- nature of `:help {subject}` command. For example, it didn't quite work
  -- when choosing tags in same file consecutively.
  local choose = function(item, modifier)
    if item == nil then return end
    vim.schedule(function() vim.cmd((modifier or default_modifier) .. 'help ' .. (item.name or '')) end)
  end
  local preview = function(buf_id, item)
    -- Take advantage of `taglist` output on how to open tag
    vim.api.nvim_buf_call(buf_id, function()
      vim.cmd('noautocmd edit ' .. vim.fn.fnameescape(item.filename))
      vim.bo.buftype, vim.bo.buflisted, vim.bo.bufhidden = 'nofile', false, 'wipe'
      local has_ts = pcall(vim.treesitter.start, 0)
      if not has_ts then vim.bo.syntax = 'help' end

      local cache_hlsearch = vim.v.hlsearch
      -- Make a "very nomagic" search to account for special characters in tag
      local search_cmd = string.gsub(item.cmd, '^/', '/\\V')
      vim.cmd('silent keeppatterns ' .. search_cmd)
      -- Here `vim.v` doesn't work: https://github.com/neovim/neovim/issues/25294
      vim.cmd('let v:hlsearch=' .. cache_hlsearch)
      vim.cmd('normal! zt')
    end)
  end

  -- Modify default mappings to work with special `:help` command
  local map_custom = function(char, modifier)
    local f = function()
      choose(MiniPick.get_picker_matches().current, modifier)
      return true
    end
    return { char = char, func = f }
  end

  local config_mappings = H.get_config().mappings
  --stylua: ignore
  local mappings = {
    choose_in_split   = '', show_help_in_split   = map_custom(config_mappings.choose_in_split, ''),
    choose_in_vsplit  = '', show_help_in_vsplit  = map_custom(config_mappings.choose_in_vsplit, 'vertical '),
    choose_in_tabpage = '', show_help_in_tabpage = map_custom(config_mappings.choose_in_tabpage, 'tab '),
  }

  local source = { items = tags, name = 'Help', choose = choose, preview = preview }
  opts = vim.tbl_deep_extend('force', { source = source, mappings = mappings }, opts or {})
  return MiniPick.start(opts)
end

--- Pick from buffers
---
--- Notes:
--- - There are not built-in mappings for buffer manipulation. Here is an example
---   of how to call this function with mapping to wipeout the current item: >lua
---
---   local wipeout_cur = function()
---     vim.api.nvim_buf_delete(MiniPick.get_picker_matches().current.bufnr, {})
---   end
---   local buffer_mappings = { wipeout = { char = '<C-d>', func = wipeout_cur } }
---   MiniPick.builtin.buffers(local_opts, { mappings = buffer_mappings })
--- <
---@param local_opts __pick_builtin_local_opts
---   Possible fields:
---   - <include_current> `(boolean)` - whether to include current buffer in
---     the output. Default: `true`.
---   - <include_unlisted> `(boolean)` - whether to include |unlisted-buffer|s in
---     the output. Default: `false`.
---@param opts __pick_builtin_opts
MiniPick.builtin.buffers = function(local_opts, opts)
  local_opts = vim.tbl_deep_extend('force', { include_current = true, include_unlisted = false }, local_opts or {})

  local buffers_output = vim.api.nvim_exec('buffers' .. (local_opts.include_unlisted and '!' or ''), true)
  local cur_buf_id, include_current = vim.api.nvim_get_current_buf(), local_opts.include_current
  local items = {}
  for _, l in ipairs(vim.split(buffers_output, '\n')) do
    local buf_str, name = l:match('^%s*%d+'), l:match('"(.*)"')
    local buf_id = tonumber(buf_str)
    local item = { text = name, bufnr = buf_id }
    if buf_id ~= cur_buf_id or include_current then table.insert(items, item) end
  end

  local show = H.get_config().source.show or H.show_with_icons
  local default_opts = { source = { name = 'Buffers', show = show } }
  opts = vim.tbl_deep_extend('force', default_opts, opts or {}, { source = { items = items } })
  return MiniPick.start(opts)
end

--- Pick from CLI output
---
--- Executes command line tool and constructs items based on its output.
--- Uses |MiniPick.set_picker_items_from_cli()|.
---
--- Example: `MiniPick.builtin.cli({ command = { 'echo', 'a\nb\nc' } })`
---
---@param local_opts __pick_builtin_local_opts
---   Possible fields:
---   - <command> `(table)` - forwarded to `set_picker_items_from_cli()`.
---   - <postprocess> `(function)` - forwarded to `set_picker_items_from_cli()`.
---   - <spawn_opts> `(table)` - forwarded to `set_picker_items_from_cli()`.
---     Note: if `cwd` field is absent, it is inferred from |MiniPick-source.cwd|.
---@param opts __pick_builtin_opts
MiniPick.builtin.cli = function(local_opts, opts)
  local_opts = vim.tbl_deep_extend('force', { command = {}, postprocess = nil, spawn_opts = {} }, local_opts or {})
  local name = string.format('CLI (%s)', tostring(local_opts.command[1] or ''))
  opts = vim.tbl_deep_extend('force', { source = { name = name } }, opts or {})
  -- Explicitly use full path to not conflict with `set_picker_items_from_cli`
  -- behavior of treating `spawn_opts.cwd` relative to source's cwd
  local_opts.spawn_opts.cwd = H.full_path(local_opts.spawn_opts.cwd or opts.source.cwd or vim.fn.getcwd())

  local command = local_opts.command
  local set_from_cli_opts = { postprocess = local_opts.postprocess, spawn_opts = local_opts.spawn_opts }
  opts.source.items = vim.schedule_wrap(function() MiniPick.set_picker_items_from_cli(command, set_from_cli_opts) end)
  return MiniPick.start(opts)
end

--- Resume latest picker
MiniPick.builtin.resume = function()
  local picker = H.pickers.latest
  if picker == nil then H.error('There is no picker to resume.') end

  H.cache = {}
  local buf_id = H.picker_new_buf()
  local win_target = vim.api.nvim_get_current_win()
  local win_id = H.picker_new_win(buf_id, picker.opts.window.config, picker.opts.source.cwd)
  picker.buffers = { main = buf_id }
  picker.windows = { main = win_id, target = win_target }
  picker.view_state = 'main'
  H.pickers.active = picker

  return H.picker_advance(picker)
end

--- Picker registry
---
--- Place for users and extensions to manage pickers with their commonly used
--- local options. By default contains all |MiniPick.builtin| pickers.
--- All entries should accept only a single `local_opts` table argument.
---
--- Serves as a source for |:Pick| command.
---
--- Customization examples: >lua
---
---   -- Adding custom picker to pick `register` entries
---   MiniPick.registry.registry = function()
---     local items = vim.tbl_keys(MiniPick.registry)
---     table.sort(items)
---     local source = {items = items, name = 'Registry', choose = function() end}
---     local chosen_picker_name = MiniPick.start({ source = source })
---     if chosen_picker_name == nil then return end
---     return MiniPick.registry[chosen_picker_name]()
---   end
---
---   -- Make `:Pick files` accept `cwd`
---   MiniPick.registry.files = function(local_opts)
---     local opts = { source = { cwd = local_opts.cwd } }
---     local_opts.cwd = nil
---     return MiniPick.builtin.files(local_opts, opts)
---   end
--- <
MiniPick.registry = {}

for name, f in pairs(MiniPick.builtin) do
  MiniPick.registry[name] = function(local_opts) return f(local_opts) end
end

--- Get items of active picker
---
---@return table|nil Picker items or `nil` if no active picker.
---
---@seealso |MiniPick.set_picker_items()| and |MiniPick.set_picker_items_from_cli()|
MiniPick.get_picker_items = function() return vim.deepcopy((H.pickers.active or {}).items) end

--- Get stritems of active picker
---
---@return table|nil Picker stritems (|MiniPick-source.items-stritems|) or `nil` if
---   no active picker.
---
---@seealso |MiniPick.set_picker_items()| and |MiniPick.set_picker_items_from_cli()|
MiniPick.get_picker_stritems = function() return vim.deepcopy((H.pickers.active or {}).stritems) end

--- Get matches of active picker
---
---@return table|nil Picker matches or `nil` if no active picker. Matches is a table
---   with the following fields:
---   - <all> `(table|nil)` - all currently matched items.
---   - <all_inds> `(table|nil)` - indexes of all currently matched items.
---   - <current> `(any)` - current matched item.
---   - <current_ind> `(number|nil)` - index of current matched item.
---   - <marked> `(table|nil)` - marked items.
---   - <marked_inds> `(table|nil)` - indexes of marked items.
---   - <shown> `(table|nil)` - shown items (from top to bottom).
---   - <shown_inds> `(table|nil)` - indexes of shown items (from top to bottom).
---
---@seealso |MiniPick.set_picker_match_inds()|
MiniPick.get_picker_matches = function()
  if not MiniPick.is_picker_active() then return end
  local picker = H.pickers.active
  local items = picker.items
  if items == nil or #items == 0 then return {} end

  local match_inds = vim.deepcopy(picker.match_inds)
  local res = { all_inds = match_inds, current_ind = match_inds[picker.current_ind] }
  res.all = vim.tbl_map(function(ind) return items[ind] end, match_inds)
  res.current = picker.items[res.current_ind]
  local marked_inds = vim.tbl_keys(picker.marked_inds_map)
  table.sort(marked_inds)
  res.marked_inds, res.marked = marked_inds, vim.tbl_map(function(ind) return items[ind] end, marked_inds)
  res.shown_inds = vim.tbl_map(function(ind) return match_inds[ind] end, picker.shown_inds)
  res.shown = vim.tbl_map(function(ind) return items[ind] end, res.shown_inds)
  return res
end

--- Get config of active picker
---
---@return table|nil Picker config (`start()`'s input `opts` table) or `nil` if
---   no active picker.
---
---@seealso |MiniPick.set_picker_opts()|
MiniPick.get_picker_opts = function() return vim.deepcopy((H.pickers.active or {}).opts) end

--- Get state data of active picker
---
---@return table|nil Table with picker state data or `nil` if no active picker.
---   State data is a table with the following fields:
---   - <buffers> `(table)` - table with `main`, `preview`, `info` fields representing
---     buffer identifier (or `nil`) for corresponding view.
---   - <windows> `(table)` - table with `main` and `target` fields representing
---     window identifiers for main and target windows.
---   - <caret> `(number)` - caret column.
---   - <is_busy> `(boolean)` - whether picker is busy with computations.
---
---@seealso |MiniPick.set_picker_target_window()|
MiniPick.get_picker_state = function()
  if not MiniPick.is_picker_active() then return end
  local picker = H.pickers.active
  --stylua: ignore
  return vim.deepcopy({
    buffers = picker.buffers, windows = picker.windows, caret = picker.caret, is_busy = picker.is_busy
  })
end

--- Get query of active picker
---
---@return table|nil Array of picker query or `nil` if no active picker.
---
---@seealso |MiniPick.set_picker_query()|
MiniPick.get_picker_query = function() return vim.deepcopy((H.pickers.active or {}).query) end

--- Set items for active picker
---
--- Note: sets items asynchronously in non-blocking fashion.
---
---@param items table Array of items.
---@param opts table|nil Options. Possible fields:
---   - <do_match> `(boolean)` - whether to perform match after setting items.
---     Default: `true`.
---   - <querytick> `(number|nil)` - value of querytick (|MiniPick.get_querytick()|)
---     to periodically check against when setting items. If checked querytick
---     differs from supplied, no items are set.
---
---@seealso |MiniPick.get_picker_items()| and |MiniPick.get_picker_stritems()|
MiniPick.set_picker_items = function(items, opts)
  if not H.islist(items) then H.error('`items` should be an array.') end
  opts = vim.tbl_deep_extend('force', { do_match = true, querytick = nil }, opts or {})
  if not MiniPick.is_picker_active() then return end

  -- Set items in async because computing lower `stritems` can block much time
  coroutine.wrap(H.picker_set_items)(H.pickers.active, items, opts)
end

--- Set items for active picker based on CLI output
---
--- Asynchronously executes `command` and sets items to its postprocessed output.
---
--- Example: >lua
---
---   local items = vim.schedule_wrap(function()
---     MiniPick.set_picker_items_from_cli({ 'echo', 'a\nb\nc' })
---   end)
---   MiniPick.start({ source = { items = items, name = 'Echo abc' } })
--- <
---@param command table Array with (at least one) string command parts.
---@param opts table|nil Options. Possible fields:
---   - <postprocess> `(function)` - callable performing postprocessing of output.
---     Will be called with array of lines as input, should return array of items.
---     Default: removes trailing empty lines and uses rest as string items.
---   - <spawn_opts> `(table)` - `options` for |uv.spawn()|, except `args` and `stdio`.
---     Note: relative `cwd` path is resolved against active picker's `cwd`.
---   - <set_items_opts> `(table)` - table forwarded to |MiniPick.set_picker_items()|.
---
---@seealso |MiniPick.get_picker_items()| and |MiniPick.get_picker_stritems()|
MiniPick.set_picker_items_from_cli = function(command, opts)
  local is_valid_command = H.is_array_of(command, 'string') and #command >= 1
  if not is_valid_command then H.error('`command` should be an array of strings.') end
  local default_opts = { postprocess = H.cli_postprocess, set_items_opts = {}, spawn_opts = {} }
  opts = vim.tbl_deep_extend('force', default_opts, opts or {})
  if not MiniPick.is_picker_active() then return end

  local executable, args = command[1], vim.list_slice(command, 2, #command)
  local process, pid, stdout = nil, nil, vim.loop.new_pipe()
  local spawn_opts = vim.tbl_deep_extend('force', opts.spawn_opts, { args = args, stdio = { nil, stdout, nil } })
  if type(spawn_opts.cwd) == 'string' then spawn_opts.cwd = H.full_path(spawn_opts.cwd) end
  process, pid = vim.loop.spawn(executable, spawn_opts, function()
    if process:is_active() then process:close() end
  end)

  -- Make sure to stop the process if picker is stopped
  local kill_process = function() pcall(vim.loop.process_kill, process) end
  vim.api.nvim_create_autocmd('User', { pattern = 'MiniPickStop', once = true, callback = kill_process })

  local data_feed = {}
  stdout:read_start(function(err, data)
    assert(not err, err)
    if data ~= nil then return table.insert(data_feed, data) end

    local items = vim.split(table.concat(data_feed), '\r?\n')
    data_feed = nil
    stdout:close()
    vim.schedule(function() MiniPick.set_picker_items(opts.postprocess(items), opts.set_items_opts) end)
  end)

  return process, pid
end

--- Set match indexes for active picker
---
--- There are two intended use cases:
--- - Inside custom asynchronous |MiniPick-source.match| function to set which of
---   picker's stritems match the query. See |MiniPick.poke_is_picker_active()|.
--- - To programmatically set current match and marked items.
---   See |MiniPick.get_picker_matches()|.
---
---@param match_inds table Array of numbers with picker's items indexes.
---@param match_type string|nil Type of match indexes to set. One of:
---   - `"all"` (default) - indexes of items that match query.
---   - `"current"` - index of current match. Only first element is used and should
---     also be present among query matches.
---   - `"marked"` - indexes of marked items. Values can be not among query matches.
---     Will make only input indexes be marked, i.e. current marks are reset.
---   Note: no `"shown"` match type as those indexes are computed automatically.
---
---@seealso |MiniPick.get_picker_matches()|
MiniPick.set_picker_match_inds = function(match_inds, match_type)
  if not H.is_array_of(match_inds, 'number') then H.error('`match_inds` should be an array of numbers.') end
  local set = H.picker_set_inds[match_type or 'all']
  if set == nil then H.error('`match_type` should be one of "all", "marked", "current"') end
  if not MiniPick.is_picker_active() then return end

  set(H.pickers.active, match_inds)
  H.picker_update(H.pickers.active, false)
end

--- Set config for active picker
---
---@param opts table Table overriding initial `opts` input of |MiniPick.start()|.
---
---@seealso |MiniPick.get_picker_opts()|
MiniPick.set_picker_opts = function(opts)
  if not MiniPick.is_picker_active() then return end
  local picker, cur_cwd = H.pickers.active, H.pickers.active.opts.source.cwd
  picker.opts = vim.tbl_deep_extend('force', picker.opts, opts or {})
  picker.action_keys = H.normalize_mappings(picker.opts.mappings)
  if cur_cwd ~= picker.opts.source.cwd then H.win_set_cwd(picker.windows.main, picker.opts.source.cwd) end
  local do_match = ((opts or {}).source or {}).match ~= nil
  H.picker_update(picker, do_match, true)
end

--- Set target window for active picker
---
---@param win_id number Valid window identifier to be used as the new target window.
---
---@seealso |MiniPick.get_picker_state()|
MiniPick.set_picker_target_window = function(win_id)
  if not H.is_valid_win(win_id) then H.error('`win_id` is not a valid window identifier.') end
  if not MiniPick.is_picker_active() then return end
  H.pickers.active.windows.target = win_id
end

--- Set query for active picker
---
---@param query table Array of strings to be set as the new picker query.
---
---@seealso |MiniPick.get_picker_query()|
MiniPick.set_picker_query = function(query)
  if not H.is_array_of(query, 'string') then H.error('`query` should be an array of strings.') end
  if not MiniPick.is_picker_active() then return end

  H.pickers.active.query, H.pickers.active.caret = vim.deepcopy(query), #query + 1
  H.querytick = H.querytick + 1
  H.pickers.active.match_inds = H.seq_along(MiniPick.get_picker_items())
  H.picker_update(H.pickers.active, true)
end

--- Get query tick
---
--- Query tick is a unique query identifier. Intended to be used to detect user
--- activity during and between |MiniPick.start()| calls for efficient non-blocking
--- functionality. Updates after any query change, picker start and stop.
---
--- See |MiniPick.poke_is_picker_active()| for usage example.
---
---@return number Query tick.
MiniPick.get_querytick = function() return H.querytick end

--- Check if there is an active picker
---
---@return boolean Whether there is currently an active picker.
---
---@seealso |MiniPick.poke_is_picker_active()|
MiniPick.is_picker_active = function() return H.pickers.active ~= nil end

--- Poke if picker is active
---
--- Intended to be used for non-blocking implementation of source methods.
--- Returns an output of |MiniPick.is_picker_active()|, but depending on
--- whether there is a coroutine running:
--- - If no, return it immediately.
--- - If yes, return it after `coroutine.yield()` with `coroutine.resume()`
---   called "soon" by the main event-loop (see |vim.schedule()|).
---
--- Example of non-blocking exact `match` (as demo; can be optimized further): >lua
---
---   local match_nonblock = function(match_inds, stritems, query)
---     local prompt, querytick = table.concat(query), MiniPick.get_querytick()
---     local f = function()
---       local res = {}
---       for _, ind in ipairs(match_inds) do
---         local should_stop = not MiniPick.poke_is_picker_active() or
---           MiniPick.get_querytick() ~= querytick
---         if should_stop then return end
---
---         if stritems[ind]:find(prompt) ~= nil then table.insert(res, ind) end
---       end
---
---       MiniPick.set_picker_match_inds(res)
---     end
---
---     coroutine.resume(coroutine.create(f))
---   end
--- <
---@return boolean Whether there is an active picker.
---
---@seealso |MiniPick.is_picker_active()|
MiniPick.poke_is_picker_active = function()
  local co = coroutine.running()
  if co == nil then return MiniPick.is_picker_active() end
  H.schedule_resume_is_active(co)
  return coroutine.yield()
end

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniPick.config)

-- Namespaces
H.ns_id = {
  matches = vim.api.nvim_create_namespace('MiniPickMatches'),
  headers = vim.api.nvim_create_namespace('MiniPickHeaders'),
  preview = vim.api.nvim_create_namespace('MiniPickPreview'),
  ranges = vim.api.nvim_create_namespace('MiniPickRanges'),
}

-- Timers
H.timers = {
  busy = vim.loop.new_timer(),
  focus = vim.loop.new_timer(),
  getcharstr = vim.loop.new_timer(),
}

-- Pickers
H.pickers = { active = nil, latest = nil }

-- Picker-independent counter of query updates
H.querytick = 0

-- General purpose cache
H.cache = {}

-- File system information
H.is_windows = vim.loop.os_uname().sysname == 'Windows_NT'

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  H.check_type('delay', config.delay, 'table')
  H.check_type('delay.async', config.delay.async, 'number')
  H.check_type('delay.busy', config.delay.busy, 'number')

  H.check_type('mappings', config.mappings, 'table')
  H.check_type('mappings.caret_left', config.mappings.caret_left, 'string')
  H.check_type('mappings.caret_right', config.mappings.caret_right, 'string')
  H.check_type('mappings.choose', config.mappings.choose, 'string')
  H.check_type('mappings.choose_in_split', config.mappings.choose_in_split, 'string')
  H.check_type('mappings.choose_in_tabpage', config.mappings.choose_in_tabpage, 'string')
  H.check_type('mappings.choose_in_vsplit', config.mappings.choose_in_vsplit, 'string')
  H.check_type('mappings.choose_marked', config.mappings.choose_marked, 'string')
  H.check_type('mappings.delete_char', config.mappings.delete_char, 'string')
  H.check_type('mappings.delete_char_right', config.mappings.delete_char_right, 'string')
  H.check_type('mappings.delete_left', config.mappings.delete_left, 'string')
  H.check_type('mappings.delete_word', config.mappings.delete_word, 'string')
  H.check_type('mappings.mark', config.mappings.mark, 'string')
  H.check_type('mappings.mark_all', config.mappings.mark_all, 'string')
  H.check_type('mappings.move_down', config.mappings.move_down, 'string')
  H.check_type('mappings.move_start', config.mappings.move_start, 'string')
  H.check_type('mappings.move_up', config.mappings.move_up, 'string')
  H.check_type('mappings.paste', config.mappings.paste, 'string')
  H.check_type('mappings.refine', config.mappings.refine, 'string')
  H.check_type('mappings.refine_marked', config.mappings.refine_marked, 'string')
  H.check_type('mappings.scroll_down', config.mappings.scroll_down, 'string')
  H.check_type('mappings.scroll_up', config.mappings.scroll_up, 'string')
  H.check_type('mappings.scroll_left', config.mappings.scroll_left, 'string')
  H.check_type('mappings.scroll_right', config.mappings.scroll_right, 'string')
  H.check_type('mappings.stop', config.mappings.stop, 'string')
  H.check_type('mappings.toggle_info', config.mappings.toggle_info, 'string')
  H.check_type('mappings.toggle_preview', config.mappings.toggle_preview, 'string')

  H.check_type('options', config.options, 'table')
  H.check_type('options.content_from_bottom', config.options.content_from_bottom, 'boolean')
  H.check_type('options.use_cache', config.options.use_cache, 'boolean')

  H.check_type('source', config.source, 'table')
  H.check_type('source.items', config.source.items, 'table', true)
  H.check_type('source.name', config.source.name, 'string', true)
  H.check_type('source.cwd', config.source.cwd, 'string', true)
  H.check_type('source.match', config.source.match, 'function', true)
  H.check_type('source.show', config.source.show, 'function', true)
  H.check_type('source.preview', config.source.preview, 'function', true)
  H.check_type('source.choose', config.source.choose, 'function', true)
  H.check_type('source.choose_marked', config.source.choose_marked, 'function', true)

  H.check_type('window', config.window, 'table')
  local is_table_or_callable = function(x) return x == nil or type(x) == 'table' or vim.is_callable(x) end
  if not is_table_or_callable(config.window.config) then
    H.error('`window.config` should be table or callable, not ' .. type(config.window.config))
  end
  -- TODO: Remove after releasing 'mini.nvim' 0.16.0
  if config.window.prompt_cursor ~= nil then
    local msg = '`prompt_cursor` in `config.window` is renamed to `prompt_caret` for better naming consistency.'
      .. ' It works for now, but will stop in the next release. Sorry for the inconvenience.'
    H.notify(msg, 'WARN')
    config.window.prompt_caret = config.window.prompt_cursor
    config.window.prompt_cursor = nil
  end
  H.check_type('window.prompt_caret', config.window.prompt_caret, 'string')
  H.check_type('window.prompt_prefix', config.window.prompt_prefix, 'string')

  return config
end

H.apply_config = function(config)
  MiniPick.config = config

  -- Register 'mini.extra' pickers
  if type(_G.MiniExtra) == 'table' then
    for name, f in pairs(_G.MiniExtra.pickers) do
      MiniPick.registry[name] = MiniPick.registry[name] or function(local_opts) return f(local_opts) end
    end
  end
end

H.get_config = function(config)
  return vim.tbl_deep_extend('force', MiniPick.config, vim.b.minipick_config or {}, config or {})
end

H.create_autocommands = function()
  local gr = vim.api.nvim_create_augroup('MiniPick', {})

  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = gr, pattern = pattern, callback = callback, desc = desc })
  end

  au('VimResized', '*', MiniPick.refresh, 'Refresh on resize')
  au('ColorScheme', '*', H.create_default_hl, 'Ensure colors')
end

--stylua: ignore
H.create_default_hl = function()
  local hi = function(name, opts)
    opts.default = true
    vim.api.nvim_set_hl(0, name, opts)
  end

  hi('MiniPickBorder',        { link = 'FloatBorder' })
  hi('MiniPickBorderBusy',    { link = 'DiagnosticFloatingWarn' })
  hi('MiniPickBorderText',    { link = 'FloatTitle' })
  hi('MiniPickCursor',        { blend = 100, nocombine = true })
  hi('MiniPickIconDirectory', { link = 'Directory' })
  hi('MiniPickIconFile',      { link = 'MiniPickNormal' })
  hi('MiniPickHeader',        { link = 'DiagnosticFloatingHint' })
  hi('MiniPickMatchCurrent',  { link = 'CursorLine' })
  hi('MiniPickMatchMarked',   { link = 'Visual' })
  hi('MiniPickMatchRanges',   { link = 'DiagnosticFloatingHint' })
  hi('MiniPickNormal',        { link = 'NormalFloat' })
  hi('MiniPickPreviewLine',   { link = 'CursorLine' })
  hi('MiniPickPreviewRegion', { link = 'IncSearch' })
  hi('MiniPickPrompt',        { link = 'DiagnosticFloatingInfo' })
  hi('MiniPickPromptCaret',   { link = 'MiniPickPrompt' })
  hi('MiniPickPromptPrefix',  { link = 'MiniPickPrompt' })
end

H.create_user_commands = function()
  local callback = function(input)
    local name, local_opts = H.command_parse_fargs(input.fargs)
    local f = MiniPick.registry[name]
    if f == nil then H.error(string.format('There is no picker named "%s" in registry.', name)) end
    f(local_opts)
  end
  local opts = { nargs = '+', complete = H.command_complete, desc = "Pick from 'mini.pick' registry" }
  vim.api.nvim_create_user_command('Pick', callback, opts)
end

-- Command --------------------------------------------------------------------
H.command_parse_fargs = function(fargs)
  local name, opts_parts = fargs[1], vim.tbl_map(H.expandcmd, vim.list_slice(fargs, 2, #fargs))
  local tbl_string = string.format('{ %s }', table.concat(opts_parts, ', '))
  local lua_load = loadstring('return ' .. tbl_string)
  if lua_load == nil then H.error('Could not convert extra command arguments to table: ' .. tbl_string) end
  return name, lua_load()
end

H.command_complete = function(_, line, col)
  local prefix_from, prefix_to, prefix = string.find(line, '^%S+%s+(%S*)')
  if col < prefix_from or prefix_to < col then return {} end
  local candidates = vim.tbl_filter(
    function(x) return tostring(x):find(prefix, 1, true) ~= nil end,
    vim.tbl_keys(MiniPick.registry)
  )
  table.sort(candidates)
  return candidates
end

-- Picker object --------------------------------------------------------------
H.validate_picker_opts = function(opts)
  opts = opts or {}
  if type(opts) ~= 'table' then H.error('Picker options should be table.') end

  opts = vim.deepcopy(H.get_config(opts))

  local validate_callable = function(x, x_name)
    if not vim.is_callable(x) then H.error(string.format('`%s` should be callable.', x_name)) end
  end

  -- Source
  local source = opts.source

  local items = source.items or {}
  local is_valid_items = H.islist(items) or vim.is_callable(items)
  if not is_valid_items then H.error('`source.items` should be array or callable.') end

  source.name = tostring(source.name or '<No name>')

  if type(source.cwd) == 'string' then source.cwd = H.full_path(source.cwd) end
  if source.cwd == nil then source.cwd = vim.fn.getcwd() end
  if vim.fn.isdirectory(source.cwd) == 0 then H.error('`source.cwd` should be a valid directory path.') end

  source.match = source.match or MiniPick.default_match
  validate_callable(source.match, 'source.match')

  source.show = source.show or MiniPick.default_show
  validate_callable(source.show, 'source.show')

  source.preview = source.preview or MiniPick.default_preview
  validate_callable(source.preview, 'source.preview')

  source.choose = source.choose or MiniPick.default_choose
  validate_callable(source.choose, 'source.choose')

  source.choose_marked = source.choose_marked or MiniPick.default_choose_marked
  validate_callable(source.choose_marked, 'source.choose_marked')

  -- Delay
  for key, value in pairs(opts.delay) do
    local is_valid_value = type(value) == 'number' and value > 0
    if not is_valid_value then H.error(string.format('`delay.%s` should be a positive number.', key)) end
  end

  -- Mappings
  local default_mappings = H.default_config.mappings
  for field, x in pairs(opts.mappings) do
    if type(field) ~= 'string' then H.error('`mappings` should have only string fields.') end
    local is_builtin_action = default_mappings[field] ~= nil
    if is_builtin_action and type(x) ~= 'string' then
      H.error(string.format('Mapping for built-in action "%s" should be string.', field))
    end
    if not is_builtin_action and not (type(x) == 'table' and type(x.char) == 'string' and vim.is_callable(x.func)) then
      H.error(string.format('Mapping for custom action "%s" should be table with `char` and `func`.', field))
    end
  end

  -- Options
  local options = opts.options
  if type(options.content_from_bottom) ~= 'boolean' then H.error('`options.content_from_bottom` should be boolean.') end
  if type(options.use_cache) ~= 'boolean' then H.error('`options.use_cache` should be boolean.') end

  -- Window
  local win_config = opts.window.config
  local is_valid_winconfig = win_config == nil or type(win_config) == 'table' or vim.is_callable(win_config)
  if not is_valid_winconfig then H.error('`window.config` should be table or callable.') end

  return opts
end

H.picker_new = function(opts)
  -- Create buffer
  local buf_id = H.picker_new_buf()

  -- Create window
  local win_target = vim.api.nvim_get_current_win()
  local win_id = H.picker_new_win(buf_id, opts.window.config, opts.source.cwd)

  -- Construct and return object
  local picker = {
    -- Permanent data about picker (should not change)
    opts = opts,

    -- Items to pick from
    items = nil,
    stritems = nil,
    stritems_ignorecase = nil,

    -- Associated Neovim objects
    buffers = { main = buf_id, preview = nil, info = nil },
    windows = { main = win_id, target = win_target },

    -- Query data
    query = {},
    -- - Query index at which new entry will be inserted
    caret = 1,
    -- - Array of `stritems` indexes matching current query
    match_inds = nil,
    -- - Map of of currently marked `stritems` indexes (as keys)
    marked_inds_map = {},
    -- - Action keys which should be processed as described in mappings
    action_keys = H.normalize_mappings(opts.mappings),

    -- Whether picker is currently busy processing data
    is_busy = false,

    -- Cache for `matches` per prompt for more performant querying
    cache = {},

    -- View data
    -- - Which buffer should currently be shown
    view_state = 'main',

    -- - Index range of `match_inds` currently visible. Present for significant
    --   performance increase to render only what is visible.
    visible_range = { from = nil, to = nil },

    -- - Index of `match_inds` pointing at current item
    current_ind = nil,
    -- - Array of indexes of `match_inds` pointing at currently shown items
    shown_inds = {},
  }

  H.querytick = H.querytick + 1

  return picker
end

H.picker_advance = function(picker)
  vim.schedule(function() vim.api.nvim_exec_autocmds('User', { pattern = 'MiniPickStart' }) end)

  local do_match, is_aborted = false, false
  local lmap = H.get_lmap()
  for _ = 1, 1000000 do
    if H.cache.is_force_stop_advance then break end
    H.picker_update(picker, do_match)

    local char = H.getcharstr(picker.opts.delay.async, lmap)
    if H.cache.is_force_stop_advance then break end

    is_aborted = char == nil
    if is_aborted then break end

    local cur_action = picker.action_keys[char] or {}
    do_match = cur_action.name == nil or vim.startswith(cur_action.name, 'delete') or cur_action.name == 'paste'
    is_aborted = cur_action.name == 'stop'

    local should_stop
    if cur_action.is_custom then
      should_stop = cur_action.func()
    else
      should_stop = (cur_action.func or H.picker_query_add)(picker, char)
    end
    if should_stop then break end
  end

  local item
  if not is_aborted then item = H.picker_get_current_item(picker) end
  H.cache.is_force_stop_advance = nil
  H.picker_stop(picker)
  return item
end

H.picker_update = function(picker, do_match, update_window)
  if do_match then H.picker_match(picker) end
  if update_window then
    local config = H.picker_compute_win_config(picker.opts.window.config)
    vim.api.nvim_win_set_config(picker.windows.main, config)
    H.picker_set_current_ind(picker, picker.current_ind, true)
  end
  H.picker_set_bordertext(picker)
  H.picker_set_lines(picker)
  H.redraw()
end

H.picker_new_buf = function()
  local buf_id = H.create_scratch_buf('main')
  vim.bo[buf_id].filetype = 'minipick'
  return buf_id
end

H.picker_new_win = function(buf_id, win_config, cwd)
  -- Hide cursor while picker is active (to not be visible in the window)
  -- This mostly follows a hack from 'folke/noice.nvim'
  H.cache.guicursor = vim.o.guicursor
  vim.o.guicursor = 'a:MiniPickCursor'

  -- Create window and focus on it
  local win_id = vim.api.nvim_open_win(buf_id, true, H.picker_compute_win_config(win_config, true))

  -- Set window-local data
  vim.wo[win_id].foldenable = false
  vim.wo[win_id].foldmethod = 'manual'
  vim.wo[win_id].list = true
  vim.wo[win_id].listchars = 'extends:…'
  vim.wo[win_id].scrolloff = 0
  vim.wo[win_id].wrap = false
  H.win_update_hl(win_id, 'NormalFloat', 'MiniPickNormal')
  H.win_update_hl(win_id, 'FloatBorder', 'MiniPickBorder')
  vim.fn.clearmatches(win_id)

  -- Set window's local "current directory" for easier choose/preview/etc.
  H.win_set_cwd(nil, cwd)

  return win_id
end

H.picker_compute_win_config = function(win_config, is_for_open)
  local has_tabline = vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1)
  local has_statusline = vim.o.laststatus > 0
  local max_height = vim.o.lines - vim.o.cmdheight - (has_tabline and 1 or 0) - (has_statusline and 1 or 0)
  local max_width = vim.o.columns

  local winborder = vim.fn.exists('+winborder') == 0 and '' or vim.o.winborder
  local default_config = {
    relative = 'editor',
    anchor = 'SW',
    width = math.floor(0.618 * max_width),
    height = math.floor(0.618 * max_height),
    col = 0,
    row = max_height + (has_tabline and 1 or 0),
    border = winborder == '' and 'single' or nil,
    style = 'minimal',
    noautocmd = is_for_open,
    -- Use high enough value to be on top of built-in windows (pmenu, etc.)
    zindex = 251,
  }
  local config = vim.tbl_deep_extend('force', default_config, H.expand_callable(win_config) or {})

  -- Tweak config values to ensure they are proper
  if (config.border or winborder) == 'none' then config.border = { '', ' ', '', '', '', ' ', '', '' } end
  -- - Adjust dimensions accounting for actually present border parts
  local bor, n = config.border, type(config.border) == 'table' and #config.border or 0
  local height_offset = n == 0 and 2 or ((bor[1 % n + 1] == '' and 0 or 1) + (bor[5 % n + 1] == '' and 0 or 1))
  local width_offset = n == 0 and 2 or ((bor[3 % n + 1] == '' and 0 or 1) + (bor[7 % n + 1] == '' and 0 or 1))
  config.height = math.max(math.min(config.height, max_height - height_offset), 1)
  config.width = math.max(math.min(config.width, max_width - width_offset), 1)

  return config
end

H.picker_track_lost_focus = function(picker)
  local track = vim.schedule_wrap(function()
    local is_cur_win = vim.api.nvim_get_current_win() == picker.windows.main
    local is_proper_focus = is_cur_win and (H.cache.is_in_getcharstr or vim.fn.mode() ~= 'n')
    if is_proper_focus then return end
    if H.cache.is_in_getcharstr then return vim.api.nvim_feedkeys('\3', 't', true) end
    H.picker_stop(picker, true)
  end)
  H.timers.focus:start(1000, 1000, track)
end

H.picker_set_items = function(picker, items, opts)
  -- Compute string items to work with (along with their lower variants)
  local stritems, stritems_ignorecase, tolower = {}, {}, H.tolower
  local poke_picker = H.poke_picker_throttle(opts.querytick)
  for i, x in ipairs(items) do
    if not poke_picker() then return end
    local to_add = H.item_to_string(x)
    table.insert(stritems, to_add)
    table.insert(stritems_ignorecase, tolower(to_add))
  end

  picker.items, picker.stritems, picker.stritems_ignorecase = items, stritems, stritems_ignorecase
  picker.cache, picker.marked_inds_map = {}, {}
  H.picker_set_busy(picker, false)

  H.picker_set_match_inds(picker, H.seq_along(items))
  -- Force update visible range for correct "show" lines computation
  H.picker_set_current_ind(picker, picker.current_ind, true)
  H.picker_update(picker, opts.do_match)
end

H.item_to_string = function(item)
  item = H.expand_callable(item)
  if type(item) == 'string' then return item end
  if type(item) == 'table' and type(item.text) == 'string' then return item.text end
  return vim.inspect(item, { newline = ' ', indent = '' })
end

H.picker_set_busy = function(picker, value)
  picker.is_busy = value

  -- NOTE: Don't precompute highlight group to always set a valid one
  local update_border_hl = function()
    H.timers.busy:stop()
    H.win_update_hl(picker.windows.main, 'FloatBorder', picker.is_busy and 'MiniPickBorderBusy' or 'MiniPickBorder')
  end

  if value then return H.timers.busy:start(picker.opts.delay.busy, 0, vim.schedule_wrap(update_border_hl)) end
  update_border_hl()
end

H.picker_set_match_inds = function(picker, inds)
  if inds == nil then return end
  H.picker_set_busy(picker, false)

  picker.match_inds = inds

  local cache_prompt = table.concat(picker.query)
  if picker.opts.options.use_cache then picker.cache[cache_prompt] = { inds = inds } end

  -- Always show result of updated matches
  H.picker_show_main(picker)

  -- Reset current index if match indexes are updated
  H.picker_set_current_ind(picker, 1)

  -- Trigger relevant event if not already inside it
  if not H.inside_minipickmatch then
    H.inside_minipickmatch = true
    vim.api.nvim_exec_autocmds('User', { pattern = 'MiniPickMatch' })
    H.inside_minipickmatch = nil
  end
end

H.picker_set_current_ind = function(picker, ind, force_update)
  if picker.items == nil or #picker.match_inds == 0 then
    picker.current_ind, picker.visible_range = nil, {}
    return
  end

  -- Wrap index around edges
  local n_matches = #picker.match_inds
  ind = (ind - 1) % n_matches + 1

  -- (Re)Compute visible range (centers current index if it is currently outside)
  local from, to, querytick = picker.visible_range.from, picker.visible_range.to, picker.visible_range.querytick
  local needs_update = H.querytick ~= querytick or from == nil or to == nil or not (from <= ind and ind <= to)
  if (force_update or needs_update) and H.is_valid_win(picker.windows.main) then
    local win_height = vim.api.nvim_win_get_height(picker.windows.main)
    to = math.min(n_matches, math.floor(ind + 0.5 * win_height))
    from = math.max(1, to - win_height + 1)
    to = from + math.min(win_height, n_matches) - 1
  end

  -- Set data
  picker.current_ind = ind
  picker.visible_range = { from = from, to = to, querytick = H.querytick }
end

H.picker_set_inds = {
  all = function(picker, inds) H.picker_set_match_inds(H.pickers.active, inds) end,
  current = function(picker, inds)
    if inds[1] == nil or picker.match_inds == nil then return end
    local current_match_ind, current_abs_ind = nil, inds[1]
    for i, match_abs_ind in ipairs(picker.match_inds) do
      if match_abs_ind == current_abs_ind then current_match_ind = i end
    end
    if current_match_ind == nil then H.error('Current match index should be present among all current matches') end
    H.picker_set_current_ind(picker, current_match_ind, true)
  end,
  marked = function(picker, inds)
    if picker.items == nil then return end
    local marked_inds_map, n_items = {}, #picker.items
    for _, ind in ipairs(inds) do
      if not (1 <= ind and ind <= n_items) then H.error('Marked indexes should be from 1 to number of items') end
      marked_inds_map[ind] = true
    end
    picker.marked_inds_map = marked_inds_map
  end,
}

H.picker_set_lines = function(picker)
  local buf_id, win_id = picker.buffers.main, picker.windows.main
  if not (H.is_valid_buf(buf_id) and H.is_valid_win(win_id)) then return end

  if picker.is_busy then return end

  local visible_range, query = picker.visible_range, picker.query
  if picker.items == nil or visible_range.from == nil or visible_range.to == nil then
    picker.shown_inds = {}
    picker.opts.source.show(buf_id, {}, query)
    H.clear_namespace(buf_id, H.ns_id.matches)
    return
  end

  -- Construct target items
  local items_to_show, items, shown_inds, match_inds = {}, picker.items, {}, picker.match_inds
  local cur_ind, cur_line = picker.current_ind, nil
  local marked_inds_map, marked_lnums = picker.marked_inds_map, {}
  local is_from_bottom = picker.opts.options.content_from_bottom
  local from = is_from_bottom and visible_range.to or visible_range.from
  local to = is_from_bottom and visible_range.from or visible_range.to
  for i = from, to, (from <= to and 1 or -1) do
    table.insert(shown_inds, i)
    table.insert(items_to_show, items[match_inds[i]])
    if i == cur_ind then cur_line = #items_to_show end
    if marked_inds_map[match_inds[i]] then table.insert(marked_lnums, #items_to_show) end
  end

  local n_empty_top_lines = is_from_bottom and (vim.api.nvim_win_get_height(win_id) - #items_to_show) or 0
  cur_line = cur_line + n_empty_top_lines
  marked_lnums = vim.tbl_map(function(x) return x + n_empty_top_lines end, marked_lnums)

  -- Update visible lines accounting for "from_bottom" direction
  picker.shown_inds = shown_inds
  picker.opts.source.show(buf_id, items_to_show, query)
  if n_empty_top_lines > 0 then
    local empty_lines = vim.fn['repeat']({ '' }, n_empty_top_lines)
    vim.api.nvim_buf_set_lines(buf_id, 0, 0, true, empty_lines)
  end

  local ns_id = H.ns_id.matches
  H.clear_namespace(buf_id, ns_id)

  -- Add highlighting for marked lines
  local marked_opts = { end_col = 0, hl_group = 'MiniPickMatchMarked', priority = 202 }
  for _, lnum in ipairs(marked_lnums) do
    marked_opts.end_row = lnum
    H.set_extmark(buf_id, ns_id, lnum - 1, 0, marked_opts)
  end

  -- Update current item
  if cur_line > vim.api.nvim_buf_line_count(buf_id) then return end

  local cur_opts = { end_row = cur_line, end_col = 0, hl_eol = true, hl_group = 'MiniPickMatchCurrent', priority = 201 }
  H.set_extmark(buf_id, ns_id, cur_line - 1, 0, cur_opts)

  -- - Update cursor if showing item matches (needed for 'scroll_{left,right}')
  local cursor = vim.api.nvim_win_get_cursor(win_id)
  if picker.view_state == 'main' and cursor[1] ~= cur_line then H.set_cursor(win_id, cur_line, cursor[2] + 1) end
end

H.picker_match = function(picker)
  if picker.items == nil then return end

  -- Try to use cache first
  local prompt_cache
  if picker.opts.options.use_cache then prompt_cache = picker.cache[table.concat(picker.query)] end
  if prompt_cache ~= nil then return H.picker_set_match_inds(picker, prompt_cache.inds) end

  local is_ignorecase = H.query_is_ignorecase(picker.query)
  local stritems = is_ignorecase and picker.stritems_ignorecase or picker.stritems
  local query = is_ignorecase and vim.tbl_map(H.tolower, picker.query) or picker.query

  H.picker_set_busy(picker, true)
  local new_inds = picker.opts.source.match(stritems, picker.match_inds, query)
  H.picker_set_match_inds(picker, new_inds)
end

H.query_is_ignorecase = function(query)
  if not vim.o.ignorecase then return false end
  if not vim.o.smartcase then return true end
  local prompt = table.concat(query)
  return prompt == vim.fn.tolower(prompt)
end

H.normalize_mappings = function(mappings, skip_alternatives)
  local res = {}
  local add_to_res = function(char, data)
    local key = H.replace_termcodes(char)
    -- Omit disabled keys and prefer custom actions over built-ins
    if (key == nil or key == '') or (res[key] ~= nil and res[key].is_custom) then return end
    res[key] = data
  end

  -- Use alternative keys for some common actions
  local alt_chars = {}
  if not skip_alternatives then alt_chars = { move_down = '<Down>', move_start = '<Home>', move_up = '<Up>' } end

  -- Process
  for name, rhs in pairs(mappings) do
    local is_custom = type(rhs) == 'table'
    local char = is_custom and rhs.char or rhs
    local data = { char = char, name = name, func = is_custom and rhs.func or H.actions[name], is_custom = is_custom }
    add_to_res(char, data)
    add_to_res(alt_chars[name], data)
  end

  return res
end

H.picker_set_bordertext = function(picker)
  local opts = picker.opts
  local win_id = picker.windows.main
  if not H.is_valid_win(win_id) then return end

  -- Compute main text managing views separately and truncating from left
  local view_state, win_width = picker.view_state, vim.api.nvim_win_get_width(win_id)
  local config
  if view_state == 'main' then
    local caret, query = picker.caret, picker.query
    local prompt_prefix, prompt_caret = opts.window.prompt_prefix, opts.window.prompt_caret
    local max_width = math.max(1, win_width - vim.fn.strchars(prompt_prefix) - vim.fn.strchars(prompt_caret))

    -- Try to put caret in the center if there is not enough room to show the
    -- whole query (as in 'mini.tabline'). Do that after concatenating query
    -- parts as (after `set_picker_query()`) they can have multiple characters.
    local before_caret = table.concat(vim.list_slice(query, 1, caret - 1))
    local after_caret = table.concat(vim.list_slice(query, caret, #query))
    local w_before, w_after = vim.fn.strchars(before_caret), vim.fn.strchars(after_caret)

    local w_right = math.min(math.floor(0.5 * max_width), w_after)
    local w_left = math.min(math.max(max_width - w_right, 0), w_before)
    w_right = math.min(math.max(max_width - w_left, 0), w_after)

    -- Show standard "there is more" padding symbols if needed
    local pad_left, pad_right = w_left == w_before and '' or '…', w_right == w_after and '' or '…'
    w_left, w_right = w_left - (pad_left == '' and 0 or 1), w_right - (pad_right == '' and 0 or 1)

    before_caret = vim.fn.strcharpart(before_caret, w_before - w_left, w_left)
    after_caret = vim.fn.strcharpart(after_caret, 0, w_right)

    local prompt = { { prompt_prefix, 'MiniPickPromptPrefix' }, { prompt_caret, 'MiniPickPromptCaret' } }
    if after_caret ~= '' then table.insert(prompt, 3, { after_caret .. pad_right, 'MiniPickPrompt' }) end
    if before_caret ~= '' then table.insert(prompt, 2, { pad_left .. before_caret, 'MiniPickPrompt' }) end
    config = { title = prompt }
  end

  local has_items = picker.items ~= nil
  if view_state == 'preview' and has_items then
    local stritem_cur = picker.stritems[picker.match_inds[picker.current_ind]] or ''
    -- Sanitize title
    stritem_cur = stritem_cur:gsub('%z', '│'):gsub('%s', ' ')
    config = { title = { { H.fit_to_width(' ' .. stritem_cur .. ' ', win_width), 'MiniPickBorderText' } } }
  end

  if view_state == 'info' then
    config = { title = { { H.fit_to_width(' Info ', win_width), 'MiniPickBorderText' } } }
  end

  -- Compute helper footer only if Neovim version permits and not in busy
  -- picker (otherwise it will flicker number of matches data on char delete)
  local nvim_has_window_footer = vim.fn.has('nvim-0.10') == 1
  if nvim_has_window_footer and not picker.is_busy then
    config.footer, config.footer_pos = H.picker_compute_footer(picker, win_id), 'left'
  end

  -- Respect `options.content_from_bottom`
  if nvim_has_window_footer and opts.options.content_from_bottom then
    config.title, config.footer = config.footer, config.title
  end

  vim.api.nvim_win_set_config(win_id, config)
  vim.wo[win_id].list = true
end

H.picker_compute_footer = function(picker, win_id)
  local info = H.picker_get_general_info(picker)
  local source_name = string.format(' %s ', info.source_name):gsub('[%z%s]', ' ')
  local n_marked_text = info.n_marked == 0 and '' or (info.n_marked .. '/')
  local inds = string.format(' %s|%s|%s%s ', info.relative_current_ind, info.n_matched, n_marked_text, info.n_total)
  local win_width, source_width, inds_width =
    vim.api.nvim_win_get_width(win_id), vim.fn.strchars(source_name), vim.fn.strchars(inds)

  local footer = { { H.fit_to_width(source_name, win_width), 'MiniPickBorderText' } }
  local n_spaces_between = win_width - (source_width + inds_width)
  if n_spaces_between > 0 then
    local border_hl = picker.is_busy and 'MiniPickBorderBusy' or 'MiniPickBorder'
    local part_id = picker.opts.options.content_from_bottom and 2 or 6
    footer[2] = { H.win_get_bottom_border(win_id, part_id):rep(n_spaces_between), border_hl }
    footer[3] = { inds, 'MiniPickBorderText' }
  end
  return footer
end

H.picker_stop = function(picker, abort)
  vim.tbl_map(function(timer) pcall(vim.loop.timer_stop, timer) end, H.timers)

  -- Show cursor (work around `guicursor=''` actually leaving cursor hidden)
  if H.cache.guicursor == '' then vim.cmd('set guicursor=a: | redraw') end
  pcall(function() vim.o.guicursor = H.cache.guicursor end)

  if picker == nil then return end

  vim.api.nvim_exec_autocmds('User', { pattern = 'MiniPickStop' })

  if abort then
    H.pickers = {}
  else
    local new_latest = vim.deepcopy(picker)
    H.picker_free(H.pickers.latest)
    H.pickers = { active = nil, latest = new_latest }
  end

  H.set_curwin(picker.windows.target)
  pcall(vim.api.nvim_win_close, picker.windows.main, true)
  pcall(vim.api.nvim_buf_delete, picker.buffers.main, { force = true })
  pcall(vim.api.nvim_buf_delete, picker.buffers.info, { force = true })
  picker.windows, picker.buffers = {}, {}

  H.querytick = H.querytick + 1
end

H.picker_free = function(picker)
  if picker == nil then return end
  picker.match_inds = nil
  picker.shown_inds = {}
  picker.cache = nil
  picker.stritems, picker.stritems_ignorecase, picker.marked_inds_map = nil, nil, nil
  picker.items = nil
  picker = nil
  vim.schedule(function() collectgarbage('collect') end)
end

--stylua: ignore
H.actions = {
  caret_left  = function(picker, _) H.picker_move_caret(picker, -1) end,
  caret_right = function(picker, _) H.picker_move_caret(picker, 1)  end,

  choose            = function(picker, _) return H.picker_choose(picker, nil)      end,
  choose_in_split   = function(picker, _) return H.picker_choose(picker, 'split')  end,
  choose_in_tabpage = function(picker, _) return H.picker_choose(picker, 'tab split') end,
  choose_in_vsplit  = function(picker, _) return H.picker_choose(picker, 'vsplit') end,
  choose_marked     = function(picker, _)
    local ok, res = pcall(picker.opts.source.choose_marked, MiniPick.get_picker_matches().marked)
    if not ok then vim.schedule(function() H.error('Error during choose marked:\n' .. res) end) end
    return not (ok and res)
  end,

  delete_char       = function(picker, _) H.picker_query_delete(picker, 1)                end,
  delete_char_right = function(picker, _) H.picker_query_delete(picker, 0)                end,
  delete_left       = function(picker, _) H.picker_query_delete(picker, picker.caret - 1) end,
  delete_word = function(picker, _)
    local init, n_del = picker.caret - 1, 0
    if init == 0 then return end
    local ref_is_keyword = vim.fn.match(picker.query[init], '[[:keyword:]]') >= 0
    for i = init, 1, -1 do
      local cur_is_keyword = vim.fn.match(picker.query[i], '[[:keyword:]]') >= 0
      if (ref_is_keyword and not cur_is_keyword) or (not ref_is_keyword and cur_is_keyword) then break end
      n_del = n_del + 1
    end
    H.picker_query_delete(picker, n_del)
  end,

  mark     = function(picker, _) H.picker_mark_indexes(picker, 'current') end,
  mark_all = function(picker, _) H.picker_mark_indexes(picker, 'all') end,

  move_down  = function(picker, _) H.picker_move_current(picker, 1)  end,
  move_start = function(picker, _) H.picker_move_current(picker, nil, 1)  end,
  move_up    = function(picker, _) H.picker_move_current(picker, -1) end,

  paste = function(picker, _)
    local reg_contents = H.picker_get_register_contents(picker):gsub('[\n\t]', ' ')
    for i = 1, vim.fn.strchars(reg_contents) do
      H.picker_query_add(picker, vim.fn.strcharpart(reg_contents, i - 1, 1))
    end
  end,

  refine        = function(picker, _) H.picker_refine(picker, 'all') end,
  refine_marked = function(picker, _) H.picker_refine(picker, 'marked') end,

  scroll_down  = function(picker, _) H.picker_scroll(picker, 'down')  end,
  scroll_up    = function(picker, _) H.picker_scroll(picker, 'up')    end,
  scroll_left  = function(picker, _) H.picker_scroll(picker, 'left')  end,
  scroll_right = function(picker, _) H.picker_scroll(picker, 'right') end,

  toggle_info = function(picker, _)
    if picker.view_state == 'info' then return H.picker_show_main(picker) end
    H.picker_show_info(picker)
  end,

  toggle_preview = function(picker, _)
    if picker.view_state == 'preview' then return H.picker_show_main(picker) end
    H.picker_show_preview(picker)
  end,

  stop = function(_, _) return true end,
}

H.picker_query_add = function(picker, char)
  -- Determine if it **is** proper single character
  if not H.is_query_char(char) then return end
  table.insert(picker.query, picker.caret, char)
  picker.caret = picker.caret + 1
  H.querytick = H.querytick + 1

  -- Adding character inside query might not result into narrowing matches, so
  -- reset match indexes. Use cache to speed this up.
  local should_reset = picker.items ~= nil and picker.caret <= #picker.query
  if should_reset then picker.match_inds = H.seq_along(picker.items) end
end

H.is_query_char = function(char) return vim.fn.strchars(char) == 1 and vim.fn.char2nr(char) > 31 end

H.picker_query_delete = function(picker, n)
  local delete_to_left = n > 0
  local left = delete_to_left and math.max(picker.caret - n, 1) or picker.caret
  local right = delete_to_left and picker.caret - 1 or math.min(picker.caret + n, #picker.query)
  for i = right, left, -1 do
    table.remove(picker.query, i)
  end
  picker.caret = left
  H.querytick = H.querytick + 1

  -- Deleting query character increases number of possible matches, so need to
  -- reset already matched indexes prior deleting. Use cache to speed this up.
  if picker.items ~= nil then picker.match_inds = H.seq_along(picker.items) end
end

H.picker_choose = function(picker, pre_command)
  local cur_item = H.picker_get_current_item(picker)
  if cur_item == nil then return true end

  local win_id_target = picker.windows.target
  if pre_command ~= nil and H.is_valid_win(win_id_target) then
    -- Work around Neovim not preserving cwd during `nvim_win_call`
    -- See: https://github.com/neovim/neovim/issues/32203
    local picker_cwd, global_cwd = vim.fn.getcwd(0), vim.fn.getcwd(-1, -1)
    vim.fn.chdir(global_cwd)
    vim.api.nvim_win_call(win_id_target, function()
      vim.cmd(pre_command)
      picker.windows.target = vim.api.nvim_get_current_win()
    end)
    vim.fn.chdir(picker_cwd)
  end

  local ok, res = pcall(picker.opts.source.choose, cur_item)
  -- Delay error to have time to hide picker window
  if not ok then vim.schedule(function() H.error('Error during choose:\n' .. res) end) end
  -- Error or returning nothing, `nil`, or `false` should lead to picker stop
  return not (ok and res)
end

H.picker_mark_indexes = function(picker, range_type)
  if picker.items == nil then return end
  local test_inds = range_type == 'current' and { picker.match_inds[picker.current_ind] } or picker.match_inds

  -- Mark if not all marked, unmark otherwise
  local marked_inds_map, is_all_marked = picker.marked_inds_map, true
  for _, ind in ipairs(test_inds) do
    is_all_marked = is_all_marked and marked_inds_map[ind]
  end

  -- NOTE: Set to `nil` and not `false` for easier counting of present values
  local new_val
  if not is_all_marked then new_val = true end
  for _, ind in ipairs(test_inds) do
    marked_inds_map[ind] = new_val
  end

  if picker.view_state == 'info' then H.picker_show_info(picker) end
end

H.picker_move_caret = function(picker, n) picker.caret = math.min(math.max(picker.caret + n, 1), #picker.query + 1) end

H.picker_move_current = function(picker, by, to)
  if picker.items == nil then return end
  local n_matches = #picker.match_inds
  if n_matches == 0 then return end

  if to == nil then
    -- Account for content direction
    by = (picker.opts.options.content_from_bottom and -1 or 1) * by

    -- Wrap around edges only if current index is at edge
    to = picker.current_ind
    if to == 1 and by < 0 then
      to = n_matches
    elseif to == n_matches and by > 0 then
      to = 1
    else
      to = to + by
    end
    to = math.min(math.max(to, 1), n_matches)
  end

  H.picker_set_current_ind(picker, to)

  -- Update not main buffer(s)
  if picker.view_state == 'info' then H.picker_show_info(picker) end
  if picker.view_state == 'preview' then H.picker_show_preview(picker) end
end

H.picker_refine = function(picker, refine_type)
  if picker.items == nil then return end

  -- Make current matches be new items to be matched with default match
  picker.opts.source.match = H.get_config().source.match or MiniPick.default_match
  picker.query, picker.caret = {}, 1
  MiniPick.set_picker_items(MiniPick.get_picker_matches()[refine_type] or {})

  picker._refine = picker._refine or { orig_name = picker.opts.source.name, count = 0 }
  picker._refine.count = picker._refine.count + 1
  local count_suffix = picker._refine.count == 1 and '' or (' ' .. picker._refine.count)
  picker.opts.source.name = string.format('%s (Refine%s)', picker._refine.orig_name, count_suffix)
end

H.picker_scroll = function(picker, direction)
  local win_id = picker.windows.main
  if picker.view_state == 'main' and (direction == 'down' or direction == 'up') then
    local n = (direction == 'down' and 1 or -1) * vim.api.nvim_win_get_height(win_id)
    H.picker_move_current(picker, n)
  else
    local keys = ({ down = '<C-f>', up = '<C-b>', left = 'zH', right = 'zL' })[direction]
    vim.api.nvim_win_call(win_id, function() vim.cmd('normal! ' .. H.replace_termcodes(keys)) end)
  end
end

H.picker_get_current_item = function(picker)
  if picker.items == nil then return nil end
  return picker.items[picker.match_inds[picker.current_ind]]
end

H.picker_get_register_contents = function(picker)
  local register = H.getcharstr(picker.opts.delay.async, {})
  -- Mimic some "insert object under cursor" behavior of Command-line mode
  local expand_var = ({ ['\1'] = '<cWORD>', ['\6'] = '<cfile>', ['\23'] = '<cword>' })[register]
  if expand_var then
    return vim.api.nvim_win_call(picker.windows.target, function() return vim.fn.expand(expand_var) end)
  end
  if register == '\f' then
    return vim.api.nvim_win_call(picker.windows.target, function() return vim.fn.getline('.') end)
  end
  local has_register, res = pcall(vim.fn.getreg, register)
  return has_register and res or ''
end

H.picker_show_main = function(picker)
  H.set_winbuf(picker.windows.main, picker.buffers.main)
  picker.view_state = 'main'
end

H.picker_show_info = function(picker)
  -- General information
  local info = H.picker_get_general_info(picker)
  local lines = {
    'General',
    'Source name   │ ' .. info.source_name,
    'Source cwd    │ ' .. info.source_cwd,
    'Total items   │ ' .. info.n_total,
    'Matched items │ ' .. info.n_matched,
    'Marked items  │ ' .. info.n_marked,
    'Current index │ ' .. info.relative_current_ind,
  }
  local hl_lines = { 1 }

  local append_char_data = function(data, header)
    if #data == 0 then return end
    table.insert(lines, '')
    table.insert(lines, header)
    table.insert(hl_lines, #lines)

    local width_max = 0
    for _, t in ipairs(data) do
      local desc = t.name:gsub('[%s%p]', ' ')
      t.desc = vim.fn.toupper(desc:sub(1, 1)) .. desc:sub(2)
      t.width = vim.fn.strchars(t.desc)
      width_max = math.max(width_max, t.width)
    end
    table.sort(data, function(a, b) return a.desc < b.desc end)

    for _, t in ipairs(data) do
      table.insert(lines, string.format('%s%s │ %s', t.desc, string.rep(' ', width_max - t.width), t.char))
    end
  end

  local action_keys = H.normalize_mappings(picker.opts.mappings, true)
  append_char_data(vim.tbl_filter(function(x) return x.is_custom end, action_keys), 'Mappings (custom)')
  append_char_data(vim.tbl_filter(function(x) return not x.is_custom end, action_keys), 'Mappings (built-in)')

  -- Manage buffer/window/state
  local buf_id_info = picker.buffers.info
  if not H.is_valid_buf(buf_id_info) then buf_id_info = H.create_scratch_buf('info') end
  picker.buffers.info = buf_id_info

  H.set_buflines(buf_id_info, lines)
  H.set_winbuf(picker.windows.main, buf_id_info)
  picker.view_state = 'info'

  local ns_id = H.ns_id.headers
  H.clear_namespace(buf_id_info, ns_id)
  for _, lnum in ipairs(hl_lines) do
    H.set_extmark(buf_id_info, ns_id, lnum - 1, 0, { end_row = lnum, end_col = 0, hl_group = 'MiniPickHeader' })
  end
end

H.picker_get_general_info = function(picker)
  local has_items = picker.items ~= nil
  return {
    source_name = picker.opts.source.name or '---',
    source_cwd = vim.fn.fnamemodify(picker.opts.source.cwd, ':~') or '---',
    n_total = has_items and #picker.items or '-',
    n_matched = has_items and #picker.match_inds or '-',
    n_marked = has_items and vim.tbl_count(picker.marked_inds_map) or '-',
    relative_current_ind = has_items and picker.current_ind or '-',
  }
end

H.picker_show_preview = function(picker)
  local preview = picker.opts.source.preview
  local item = H.picker_get_current_item(picker)
  if item == nil then return end

  local win_id, buf_id = picker.windows.main, H.create_scratch_buf('preview')
  vim.bo[buf_id].bufhidden = 'wipe'
  H.set_winbuf(win_id, buf_id)
  preview(buf_id, item)
  picker.buffers.preview = vim.api.nvim_win_get_buf(win_id)
  picker.view_state = 'preview'
end

-- Default match --------------------------------------------------------------
H.match_filter = function(inds, stritems, query)
  -- 'abc' and '*abc' - fuzzy; "'abc" and 'a' - exact substring;
  -- 'ab c' - grouped fuzzy; '^abc' and 'abc$' - exact substring at start/end.
  local is_fuzzy_forced, is_exact_plain, is_exact_start, is_exact_end =
    query[1] == '*', query[1] == "'", query[1] == '^', query[#query] == '$'
  local is_grouped, grouped_parts = H.match_query_group(query)

  if is_fuzzy_forced or is_exact_plain or is_exact_start or is_exact_end then
    local start_offset = (is_fuzzy_forced or is_exact_plain or is_exact_start) and 2 or 1
    local end_offset = #query - ((not is_fuzzy_forced and not is_exact_plain and is_exact_end) and 1 or 0)
    query = vim.list_slice(query, start_offset, end_offset)
  elseif is_grouped then
    query = grouped_parts
  end

  if #query == 0 then return {}, 'useall', query end

  local is_fuzzy_plain = not (is_exact_plain or is_exact_start or is_exact_end) and #query > 1
  if is_fuzzy_forced or is_fuzzy_plain then return H.match_filter_fuzzy(inds, stritems, query), 'fuzzy', query end

  local prefix = is_exact_start and '^' or ''
  local suffix = is_exact_end and '$' or ''
  local pattern = prefix .. vim.pesc(table.concat(query)) .. suffix

  return H.match_filter_exact(inds, stritems, query, pattern), 'exact', query
end

H.match_filter_exact = function(inds, stritems, query, pattern)
  local match_single = H.match_filter_exact_single
  local poke_picker = H.poke_picker_throttle(H.querytick)
  local match_data = {}
  for _, ind in ipairs(inds) do
    if not poke_picker() then return nil end
    local data = match_single(stritems[ind], ind, pattern)
    if data ~= nil then table.insert(match_data, data) end
  end

  return match_data
end

H.match_filter_exact_single = function(candidate, index, pattern)
  local start = string.find(candidate, pattern)
  if start == nil then return nil end

  return { 0, start, index }
end

H.match_ranges_exact = function(match_data, query)
  -- All matches have same match ranges relative to match start
  local cur_start, rel_ranges = 0, {}
  for i = 1, #query do
    rel_ranges[i] = { cur_start, cur_start + query[i]:len() - 1 }
    cur_start = rel_ranges[i][2] + 1
  end

  local res = {}
  for i = 1, #match_data do
    local start = match_data[i][2]
    res[i] = vim.tbl_map(function(x) return { start + x[1], start + x[2] } end, rel_ranges)
  end

  return res
end

H.match_filter_fuzzy = function(inds, stritems, query)
  local match_single, find_query = H.match_filter_fuzzy_single, H.match_find_query
  local poke_picker = H.poke_picker_throttle(H.querytick)
  local match_data = {}
  for _, ind in ipairs(inds) do
    if not poke_picker() then return nil end
    local data = match_single(stritems[ind], ind, query, find_query)
    if data ~= nil then table.insert(match_data, data) end
  end
  return match_data
end

H.match_filter_fuzzy_single = function(candidate, index, query, find_query)
  -- Search for query chars match positions with the following properties:
  -- - All are present in `candidate` in the same order.
  -- - Has smallest width among all such match positions.
  -- - Among same width has smallest first match.

  -- Search forward to find matching positions with left-most last char match
  local first, last = find_query(candidate, query, 1)
  if first == nil then return nil end
  if first == last then return { 0, first, index, { first } } end

  -- NOTE: This approach doesn't iterate **all** query matches. It is fine for
  -- width optimization but maybe not for more (like contiguous groups number).
  -- Example: for query {'a', 'b', 'c'} candidate 'aaxbbbc' will be matched as
  -- having 3 groups (indexes 2, 4, 7) but correct one is 2 groups (2, 6, 7).

  -- Iteratively try to find better matches by advancing last match
  local best_first, best_last, best_width = first, last, last - first
  while last do
    local width = last - first
    if width < best_width then
      best_first, best_last, best_width = first, last, width
    end

    first, last = find_query(candidate, query, first + 1)
  end

  -- NOTE: No field names is not clear code, but consistently better performant
  return { best_last - best_first, best_first, index }
end

H.match_ranges_fuzzy = function(match_data, query, stritems)
  local res, n_query, query_lens = {}, #query, vim.tbl_map(string.len, query)
  for i_match, data in ipairs(match_data) do
    local s, from, to = stritems[data[3]], data[2], data[2] + query_lens[1] - 1
    local ranges = { { from, to } }
    for j_query = 2, n_query do
      from, to = string.find(s, query[j_query], to + 1, true)
      ranges[j_query] = { from, to }
    end
    res[i_match] = ranges
  end
  return res
end

H.match_find_query = function(s, query, init)
  local first, to = string.find(s, query[1], init, true)
  if first == nil then return nil, nil end

  -- Both `first` and `last` indicate the start byte of first and last match
  local last = first
  for i = 2, #query do
    last, to = string.find(s, query[i], to + 1, true)
    if not last then return nil, nil end
  end
  return first, last
end

H.match_query_group = function(query)
  local parts = { {} }
  for _, x in ipairs(query) do
    local is_whitespace = x:find('^%s+$') ~= nil
    if is_whitespace then table.insert(parts, {}) end
    if not is_whitespace then table.insert(parts[#parts], x) end
  end
  return #parts > 1, vim.tbl_map(table.concat, parts)
end

H.match_sort = function(match_data)
  -- Spread indexes in width-start buckets
  local buckets, max_width, width_max_start = {}, 0, {}
  for i = 1, #match_data do
    local data, width, start = match_data[i], match_data[i][1], match_data[i][2]
    local buck_width = buckets[width] or {}
    local buck_start = buck_width[start] or {}
    table.insert(buck_start, data[3])
    buck_width[start] = buck_start
    buckets[width] = buck_width

    max_width = math.max(max_width, width)
    width_max_start[width] = math.max(width_max_start[width] or 0, start)
  end

  -- Sort index in place (to make stable sort) within buckets
  local poke_picker = H.poke_picker_throttle(H.querytick)
  for _, buck_width in pairs(buckets) do
    for _, buck_start in pairs(buck_width) do
      if not poke_picker() then return nil end
      table.sort(buck_start)
    end
  end

  -- Gather indexes back in order
  local res = {}
  for width = 0, max_width do
    local buck_width = buckets[width]
    for start = 1, (width_max_start[width] or 0) do
      local buck_start = buck_width[start] or {}
      for i = 1, #buck_start do
        table.insert(res, buck_start[i])
      end
    end
  end

  return res
end

H.match_no_sort = function(match_data)
  return vim.tbl_map(function(x) return x[3] end, match_data)
end

-- Default show ---------------------------------------------------------------
H.get_icon = function(x, icons)
  local item_data = H.parse_item(x)
  local path = item_data.path or item_data.text or ''
  local path_type = H.get_fs_type(path)
  if path_type == 'none' then return { text = icons.none, hl = 'MiniPickNormal' } end

  -- Prefer 'mini.icons'
  if _G.MiniIcons ~= nil then
    local category = path_type == 'directory' and 'directory' or 'file'
    local icon, hl = _G.MiniIcons.get(category, path)
    return { text = icon .. ' ', hl = hl }
  end

  -- Try falling back to 'nvim-web-devicons'
  if path_type == 'directory' then return { text = icons.directory, hl = 'MiniPickIconDirectory' } end
  local has_devicons, devicons = pcall(require, 'nvim-web-devicons')
  if not has_devicons then return { text = icons.file, hl = 'MiniPickIconFile' } end

  local icon, hl = devicons.get_icon(vim.fn.fnamemodify(path, ':t'), nil, { default = false })
  icon = type(icon) == 'string' and (icon .. ' ') or icons.file
  return { text = icon, hl = hl or 'MiniPickIconFile' }
end

H.show_with_icons = function(buf_id, items, query) MiniPick.default_show(buf_id, items, query, { show_icons = true }) end

-- Items helpers for default functions ----------------------------------------
H.parse_item = function(item)
  -- Try parsing table item first
  if type(item) == 'table' then return H.parse_item_table(item) end

  -- Parse item's string representation
  local stritem = H.item_to_string(item)

  -- - Buffer
  local ok, numitem = pcall(tonumber, stritem)
  if ok and H.is_valid_buf(numitem) then return { type = 'buffer', buf_id = numitem } end

  -- File or Directory
  local path_type, path, lnum, col, rest = H.parse_path(stritem)
  if path_type ~= 'none' then return { type = path_type, path = path, lnum = lnum, col = col, text = rest } end

  return {}
end

H.parse_item_table = function(item)
  -- Buffer
  local buf_id = item.bufnr or item.buf_id or item.buf
  if H.is_valid_buf(buf_id) then
    --stylua: ignore
    return {
      type = 'buffer',  buf_id   = buf_id, path = item.path or vim.api.nvim_buf_get_name(buf_id),
      lnum = item.lnum, end_lnum = item.end_lnum,
      col  = item.col,  end_col  = item.end_col,
      text = item.text,
    }
  end

  -- File or Directory
  if type(item.path) == 'string' then
    local path_type = H.get_fs_type(item.path)
    if path_type == 'file' or path_type == 'uri' then
      --stylua: ignore
      return {
        type = path_type, path     = item.path,
        lnum = item.lnum, end_lnum = item.end_lnum,
        col  = item.col,  end_col  = item.end_col,
        text = item.text,
      }
    end

    if path_type == 'directory' then return { type = 'directory', path = item.path } end
  end

  return {}
end

H.parse_path = function(x)
  if type(x) ~= 'string' or x == '' then return nil end
  -- Allow inputs like 'aa/bb', 'aa-5'. Also allow inputs for line/position
  -- separated by null character:
  -- - 'aa/bb\00010' (line 10).
  -- - 'aa/bb\00010\0005' (line 10, col 5).
  -- - 'aa/bb\00010\0005\000xx' (line 10, col 5, with "xx" description).
  local location_pattern = '()%z(%d+)%z?(%d*)%z?(.*)$'
  local from, lnum, col, rest = x:match(location_pattern)
  local path = x:sub(1, (from or 0) - 1)
  path = path:sub(1, 1) == '~' and ((vim.loop.os_homedir() or '~') .. path:sub(2)) or path

  -- Verify that path is real
  local path_type = H.get_fs_type(path)
  if path_type == 'none' and path ~= '' then
    local cwd = H.pickers.active == nil and vim.fn.getcwd() or H.pickers.active.opts.source.cwd
    path = string.format('%s/%s', cwd, path)
    path_type = H.get_fs_type(path)
  end

  return path_type, path, tonumber(lnum), tonumber(col), rest or ''
end

H.get_fs_type = function(path)
  if path == '' then return 'none' end
  if vim.fn.filereadable(path) == 1 then return 'file' end
  if vim.fn.isdirectory(path) == 1 then return 'directory' end
  if H.parse_uri(path) ~= nil then return 'uri' end
  return 'none'
end

-- Default preview ------------------------------------------------------------
H.preview_file = function(buf_id, item_data, opts)
  -- Fully preview only accessible text files
  local is_text = H.is_file_text(item_data.path)
  if not is_text then return H.set_buflines(buf_id, { is_text == nil and '-No-access-' or '-Non-text-file-' }) end

  -- Compute lines. Limit number of read lines to work better on large files.
  local has_lines, lines = pcall(vim.fn.readfile, item_data.path, '', (item_data.lnum or 1) + opts.n_context_lines)
  if not has_lines then return end

  item_data.line_position = opts.line_position
  H.preview_set_lines(buf_id, lines, item_data)
end

H.preview_directory = function(buf_id, item_data)
  local path = item_data.path
  local format = function(x) return x .. (vim.fn.isdirectory(path .. '/' .. x) == 1 and '/' or '') end
  local lines = vim.tbl_map(format, vim.fn.readdir(path))
  H.set_buflines(buf_id, lines)
end

H.preview_buffer = function(buf_id, item_data, opts)
  -- NOTE: ideally just setting target buffer to window would be enough, but it
  -- has side effects. See https://github.com/neovim/neovim/issues/24973 .
  -- Reading lines and applying custom styling is a passable alternative.
  local buf_id_source = item_data.buf_id

  -- Get lines from buffer ensuring it is loaded without important consequences
  local cache_eventignore = vim.o.eventignore
  vim.o.eventignore = 'BufEnter'
  vim.fn.bufload(buf_id_source)
  vim.o.eventignore = cache_eventignore
  local lines = vim.api.nvim_buf_get_lines(buf_id_source, 0, (item_data.lnum or 1) + opts.n_context_lines, false)

  item_data.filetype, item_data.line_position = vim.bo[buf_id_source].filetype, opts.line_position
  H.preview_set_lines(buf_id, lines, item_data)
end

H.preview_uri = function(buf_id, item_data, opts)
  item_data.buf_id = vim.uri_to_bufnr(item_data.path)
  H.preview_buffer(buf_id, item_data, opts)
end

H.preview_inspect = function(buf_id, obj) H.set_buflines(buf_id, vim.split(vim.inspect(obj), '\n')) end

H.preview_set_lines = function(buf_id, lines, extra)
  -- Lines
  H.set_buflines(buf_id, lines)

  -- Highlighting
  H.preview_highlight_region(buf_id, extra.lnum, extra.col, extra.end_lnum, extra.end_col)

  if H.preview_should_highlight(buf_id) then
    local ft = extra.filetype or vim.filetype.match({ buf = buf_id, filename = extra.path })
    local has_lang, lang = pcall(vim.treesitter.language.get_lang, ft)
    lang = has_lang and lang or ft
    -- TODO: Remove `opts.error` after compatibility with Neovim=0.11 is dropped
    local has_parser, parser = pcall(vim.treesitter.get_parser, buf_id, lang, { error = false })
    has_parser = has_parser and parser ~= nil
    if has_parser then has_parser = pcall(vim.treesitter.start, buf_id, lang) end
    if not has_parser then vim.bo[buf_id].syntax = ft end
  end

  -- Cursor position and window view. Find window (and not use picker window)
  -- for "outside window preview" (preview and main are different) to work.
  local win_id = vim.fn.bufwinid(buf_id)
  if win_id == -1 then return end
  H.set_cursor(win_id, extra.lnum, extra.col)
  local pos_keys = ({ top = 'zt', center = 'zz', bottom = 'zb' })[extra.line_position] or 'zt'
  pcall(vim.api.nvim_win_call, win_id, function() vim.cmd('normal! ' .. pos_keys) end)
end

H.preview_should_highlight = function(buf_id)
  -- Highlight if buffer size is not too big, both in total and per line
  local buf_size = vim.api.nvim_buf_call(buf_id, function() return vim.fn.line2byte(vim.fn.line('$') + 1) end)
  return buf_size <= 1000000 and buf_size <= 1000 * vim.api.nvim_buf_line_count(buf_id)
end

H.preview_highlight_region = function(buf_id, lnum, col, end_lnum, end_col)
  -- Highlight line
  if lnum == nil then return end
  local hl_line_opts = { end_row = lnum, end_col = 0, hl_eol = true, hl_group = 'MiniPickPreviewLine', priority = 201 }
  H.set_extmark(buf_id, H.ns_id.preview, lnum - 1, 0, hl_line_opts)

  -- Highlight position/region
  if col == nil then return end

  local ext_end_row, ext_end_col = lnum - 1, col
  if end_lnum ~= nil and end_col ~= nil then
    ext_end_row, ext_end_col = end_lnum - 1, end_col - 1
  end
  ext_end_col = H.get_next_char_bytecol(vim.fn.getbufline(buf_id, ext_end_row + 1)[1], ext_end_col)

  local hl_region_opts = { end_row = ext_end_row, end_col = ext_end_col, priority = 202 }
  hl_region_opts.hl_group = 'MiniPickPreviewRegion'
  H.set_extmark(buf_id, H.ns_id.preview, lnum - 1, col - 1, hl_region_opts)
end

-- Default choose -------------------------------------------------------------
H.choose_path = function(win_target, item_data)
  local path = H.parse_uri(item_data.path) or item_data.path
  if item_data.type == 'directory' then
    return vim.api.nvim_win_call(win_target, function() vim.cmd('edit ' .. vim.fn.fnameescape(path)) end)
  end
  pcall(vim.api.nvim_win_call, win_target, function() vim.cmd("normal! m'") end)
  H.edit(path, win_target)
  H.choose_set_cursor(win_target, item_data.lnum, item_data.col)
end

H.choose_buffer = function(win_target, item_data)
  pcall(vim.api.nvim_win_call, win_target, function() vim.cmd("normal! m'") end)
  H.set_winbuf(win_target, item_data.buf_id)
  H.choose_set_cursor(win_target, item_data.lnum, item_data.col)
end

H.choose_print = function(x) print(vim.inspect(x)) end

H.choose_set_cursor = function(win_id, lnum, col)
  if lnum == nil then return end
  H.set_cursor(win_id, lnum, col)
  pcall(vim.api.nvim_win_call, win_id, function() vim.cmd('normal! zvzz') end)
end

-- Builtins -------------------------------------------------------------------
H.cli_postprocess = function(items)
  while items[#items] == '' do
    items[#items] = nil
  end
  return items
end

H.is_executable = function(tool)
  if tool == 'fallback' then return true end
  return vim.fn.executable(tool) == 1
end

H.files_get_tool = function()
  if H.is_executable('rg') then return 'rg' end
  if H.is_executable('fd') then return 'fd' end
  if H.is_executable('git') then return 'git' end
  return 'fallback'
end

H.files_get_command = function(tool)
  if tool == 'rg' then return { 'rg', '--files', '--color=never' } end
  if tool == 'fd' then return { 'fd', '--type=f', '--color=never' } end
  if tool == 'git' then
    return { 'git', '-c', 'core.quotepath=false', 'ls-files', '--cached', '--others', '--exclude-standard' }
  end
  H.error([[Wrong 'tool' for `files` builtin.]])
end

H.files_fallback_items = function(cwd)
  local poke_picker = H.poke_picker_throttle()
  local f = function()
    local items = {}
    for path, path_type in vim.fs.dir(cwd, { depth = math.huge }) do
      if not poke_picker() then return end
      if path_type == 'file' and H.is_file_text(string.format('%s/%s', cwd, path)) then table.insert(items, path) end
    end
    MiniPick.set_picker_items(items)
  end

  vim.schedule(coroutine.wrap(f))
end

H.grep_get_tool = function()
  if H.is_executable('rg') then return 'rg' end
  if H.is_executable('git') then return 'git' end
  return 'fallback'
end

--stylua: ignore
H.grep_get_command = function(tool, pattern, globs)
  if tool == 'rg' then
    local res = {
      'rg', '--column', '--line-number', '--no-heading', '--field-match-separator', '\\x00', '--color=never'
    }
    for _, g in ipairs(globs) do
      table.insert(res, '--glob')
      -- NOTE: no `*` as default is important to not "override" ignoring files
      table.insert(res, g)
    end
    local case = vim.o.ignorecase and (vim.o.smartcase and 'smart-case' or 'ignore-case') or 'case-sensitive'
    vim.list_extend(res, { '--' .. case,  '--', pattern })
    return res
  end
  if tool == 'git' then
    local res = { 'git', 'grep', '--column', '--line-number', '--null', '--color=never', '-e', pattern, '--', unpack(globs) }
    if vim.o.ignorecase then table.insert(res, 6, '--ignore-case') end
    return res
  end
  H.error([[Wrong 'tool' for `grep` builtin.]])
end

H.grep_fallback_items = function(pattern, cwd)
  local poke_picker = H.poke_picker_throttle()
  local f = function()
    local files, files_full = {}, {}
    for path, path_type in vim.fs.dir(cwd, { depth = math.huge }) do
      if not poke_picker() then return end
      local path_full = string.format('%s/%s', cwd, path)
      if path_type == 'file' and H.is_file_text(path_full) then
        table.insert(files, path)
        table.insert(files_full, path_full)
      end
    end

    local items = {}
    for i, path in ipairs(files_full) do
      local file = files[i]
      if not poke_picker() then return end
      for lnum, l in ipairs(vim.fn.readfile(path)) do
        local col = string.find(l, pattern)
        if col ~= nil then table.insert(items, string.format('%s\0%d\0%d\0%s', file, lnum, col, l)) end
      end
    end

    MiniPick.set_picker_items(items)
  end

  vim.schedule(coroutine.wrap(f))
end

-- Async ----------------------------------------------------------------------
H.schedule_resume_is_active = vim.schedule_wrap(function(co) coroutine.resume(co, MiniPick.is_picker_active()) end)

H.poke_picker_throttle = function(querytick_ref)
  -- Allow calling this even if no picker is active
  if not MiniPick.is_picker_active() then
    return function() return true end
  end

  local latest_time, dont_check_querytick = vim.loop.hrtime(), querytick_ref == nil
  local threshold = 1000000 * H.get_config().delay.async
  local hrtime = vim.loop.hrtime
  local poke_is_picker_active = MiniPick.poke_is_picker_active
  return function()
    local now = hrtime()
    if (now - latest_time) < threshold then return true end
    latest_time = now
    -- Return positive if picker is active and no query updates (if asked)
    return poke_is_picker_active() and (dont_check_querytick or querytick_ref == H.querytick)
  end
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.pick) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.set_buf_name = function(buf_id, name) vim.api.nvim_buf_set_name(buf_id, 'minipick://' .. buf_id .. '/' .. name) end

H.notify = function(msg, level_name) vim.notify('(mini.pick) ' .. msg, vim.log.levels[level_name]) end

H.edit = function(path, win_id)
  if type(path) ~= 'string' then return end
  local b = vim.api.nvim_win_get_buf(win_id or 0)
  local try_mimic_buf_reuse = (vim.fn.bufname(b) == '' and vim.bo[b].buftype ~= 'quickfix' and not vim.bo[b].modified)
    and (#vim.fn.win_findbuf(b) == 1 and vim.deep_equal(vim.fn.getbufline(b, 1, '$'), { '' }))
  local buf_id = vim.fn.bufadd(vim.fn.fnamemodify(path, ':.'))
  -- Showing in window also loads. Use `pcall` to not error with swap messages.
  pcall(vim.api.nvim_win_set_buf, win_id or 0, buf_id)
  vim.bo[buf_id].buflisted = true
  if try_mimic_buf_reuse then pcall(vim.api.nvim_buf_delete, b, { unload = false }) end
  return buf_id
end

H.is_valid_buf = function(buf_id) return type(buf_id) == 'number' and vim.api.nvim_buf_is_valid(buf_id) end

H.is_valid_win = function(win_id) return type(win_id) == 'number' and vim.api.nvim_win_is_valid(win_id) end

H.is_array_of = function(x, ref_type)
  if not H.islist(x) then return false end
  for i = 1, #x do
    if type(x[i]) ~= ref_type then return false end
  end
  return true
end

H.create_scratch_buf = function(name)
  local buf_id = vim.api.nvim_create_buf(false, true)
  H.set_buf_name(buf_id, name)
  vim.bo[buf_id].matchpairs = ''
  vim.b[buf_id].minicursorword_disable = true
  vim.b[buf_id].miniindentscope_disable = true
  return buf_id
end

H.get_first_valid_normal_window = function()
  for _, win_id in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(win_id).relative == '' then return win_id end
  end
end

H.set_buflines = function(buf_id, lines) pcall(vim.api.nvim_buf_set_lines, buf_id, 0, -1, false, lines) end

H.set_winbuf = function(win_id, buf_id) vim.api.nvim_win_set_buf(win_id, buf_id) end

H.set_extmark = function(...) pcall(vim.api.nvim_buf_set_extmark, ...) end

H.set_cursor = function(win_id, lnum, col) pcall(vim.api.nvim_win_set_cursor, win_id, { lnum or 1, (col or 1) - 1 }) end

H.set_curwin = function(win_id)
  if not H.is_valid_win(win_id) then return end
  -- Explicitly preserve cursor to fix Neovim<0.10 after choosing position in
  -- already shown buffer
  local cursor = vim.api.nvim_win_get_cursor(win_id)
  vim.api.nvim_set_current_win(win_id)
  H.set_cursor(win_id, cursor[1], cursor[2] + 1)
end

H.clear_namespace = function(buf_id, ns_id) pcall(vim.api.nvim_buf_clear_namespace, buf_id, ns_id, 0, -1) end

H.replace_termcodes = function(x)
  if x == nil then return nil end
  return vim.api.nvim_replace_termcodes(x, true, true, true)
end

H.expand_callable = function(x, ...)
  if vim.is_callable(x) then return x(...) end
  return x
end

H.expandcmd = function(x)
  local ok, res = pcall(vim.fn.expandcmd, x)
  return ok and res or x
end

H.redraw = function() vim.cmd('redraw') end

H.redraw_scheduled = vim.schedule_wrap(H.redraw)

H.getcharstr = function(delay_async, lmap)
  -- Ensure that redraws still happen
  H.timers.getcharstr:start(0, delay_async, H.redraw_scheduled)
  H.cache.is_in_getcharstr = true
  local ok, char = pcall(vim.fn.getcharstr)
  H.cache.is_in_getcharstr = nil
  H.timers.getcharstr:stop()

  -- Terminate if no input, on hard-coded <C-c>, or outside mouse click
  local main_win_id
  if H.pickers.active ~= nil then main_win_id = H.pickers.active.windows.main end
  local is_bad_mouse_click = vim.v.mouse_winid ~= 0 and vim.v.mouse_winid ~= main_win_id
  if not ok or char == '' or char == '\3' or is_bad_mouse_click then return end
  -- Respect language mappings only if needed
  return vim.o.iminsert == 0 and char or (lmap[char] or char)
end

H.tolower = (function()
  -- Cache `tolower` for speed
  local tolower = vim.fn.tolower
  return function(x)
    -- `vim.fn.tolower` can throw errors on bad string (like with '\0')
    local ok, res = pcall(tolower, x)
    return ok and res or string.lower(x)
  end
end)()

H.win_update_hl = function(win_id, new_from, new_to)
  if not H.is_valid_win(win_id) then return end

  local new_entry = new_from .. ':' .. new_to
  local replace_pattern = string.format('(%s:[^,]*)', vim.pesc(new_from))
  local new_winhighlight, n_replace = vim.wo[win_id].winhighlight:gsub(replace_pattern, new_entry)
  if n_replace == 0 then new_winhighlight = new_winhighlight .. ',' .. new_entry end

  vim.wo[win_id].winhighlight = new_winhighlight
end

H.fit_to_width = function(text, width)
  local t_width = vim.fn.strchars(text)
  return t_width <= width and text or ('…' .. vim.fn.strcharpart(text, t_width - width + 1, width - 1))
end

H.win_get_bottom_border = function(win_id, border_part_id)
  local border = vim.api.nvim_win_get_config(win_id).border or {}
  local res = border[border_part_id]
  return (type(res) == 'table' and res[1] or res) or ' '
end

H.win_set_cwd = function(win_id, cwd)
  -- Avoid needlessly setting cwd as it has side effects (like for `:buffers`)
  if cwd == nil or vim.fn.getcwd(win_id or 0) == cwd then return end
  local f = function() vim.cmd('lcd ' .. vim.fn.fnameescape(cwd)) end
  if win_id == nil or win_id == vim.api.nvim_get_current_win() then return f() end
  vim.api.nvim_win_call(win_id, f)
end

H.seq_along = function(arr)
  if arr == nil then return nil end
  local res = {}
  for i = 1, #arr do
    table.insert(res, i)
  end
  return res
end

H.str_utfindex = function(s, i) return vim.str_utfindex(s, 'utf-32', i) end
if vim.fn.has('nvim-0.11') == 0 then H.str_utfindex = function(s, i) return (vim.str_utfindex(s, i)) end end

H.str_byteindex = function(s, i) return vim.str_byteindex(s, 'utf-32', i) end
if vim.fn.has('nvim-0.11') == 0 then H.str_byteindex = function(s, i) return vim.str_byteindex(s, i) end end

H.get_next_char_bytecol = function(line_str, col)
  if type(line_str) ~= 'string' then return col end
  local utf_index = H.str_utfindex(line_str, math.min(line_str:len(), col))
  return H.str_byteindex(line_str, utf_index)
end

H.is_file_text = function(path)
  local fd = vim.loop.fs_open(path, 'r', 1)
  if fd == nil then return nil end
  local is_text = vim.loop.fs_read(fd, 1024):find('\0') == nil
  vim.loop.fs_close(fd)
  return is_text
end

H.full_path = function(path) return (vim.fn.fnamemodify(path, ':p'):gsub('(.)/$', '%1')) end
if H.is_windows then
  H.full_path = function(path) return (vim.fn.fnamemodify(path, ':p'):gsub('(.)[\\/]$', '%1')) end
end

H.parse_uri = function(x)
  local ok, path = pcall(vim.uri_to_fname, x)
  if not ok then return nil end
  -- Don't accept Windows paths with volume letter as URI
  if H.is_windows and x:find('^%a:') ~= nil and path:find('^%a:') ~= nil then return nil end
  return path
end

-- TODO: Remove after compatibility with Neovim=0.9 is dropped
H.islist = vim.fn.has('nvim-0.10') == 1 and vim.islist or vim.tbl_islist

H.get_lmap = function()
  local lmap = {}
  for _, map in ipairs(vim.fn.maplist()) do
    -- NOTE: Account only for characters that resolve to proper query character
    local is_query_lmap = map.mode == 'l' and H.is_query_char(map.rhs)
    if is_query_lmap then lmap[map.lhs] = map.rhs end
  end
  return lmap
end
if vim.fn.has('nvim-0.10') == 0 then H.get_lmap = function() return {} end end

return MiniPick
