--- *mini.snippets* Manage and expand snippets
---
--- MIT License Copyright (c) 2024 Evgeni Chasnovski

--- Snippet is a template for a frequently used text. Typical workflow is to type
--- snippet's (configurable) prefix and expand it into a snippet session.
---
--- The template usually contains both pre-defined text and places (called
--- "tabstops") for user to interactively change/add text during snippet session.
---
--- This module supports (only) snippet syntax defined in LSP specification (with
--- small deviations). See |MiniSnippets-syntax-specification|.
---
--- Features:
--- - Manage snippet collection by adding it explicitly or with a flexible set of
---   performant built-in loaders. See |MiniSnippets.gen_loader|.
---
--- - Configured snippets are efficiently resolved before every expand based on
---   current local context. This, for example, allows using different snippets
---   in different local tree-sitter languages (like in markdown code blocks).
---   See |MiniSnippets.default_prepare()|.
---
--- - Match which snippet to insert based on the currently typed text.
---   Supports both exact and fuzzy matching. See |MiniSnippets.default_match()|.
---
--- - Select from several matched snippets via `vim.ui.select()`.
---   See |MiniSnippets.default_select()|.
---
--- - Start specialized in-process LSP server to show loaded snippets inside
---   (auto)completion engines (like |mini.completion|).
---   See |MiniSnippets.start_lsp_server()|.
---
--- - Insert, jump, and edit during snippet session in a configurable manner:
---     - Configurable mappings for jumping and stopping.
---     - Jumping wraps around the tabstops for easier navigation.
---     - Easy to reason rules for when session automatically stops.
---     - Text synchronization of linked tabstops preserving relative indent.
---     - Dynamic tabstop state visualization (current/visited/unvisited, etc.)
---     - Inline visualization of empty tabstops (requires Neovim>=0.10).
---     - Works inside comments by preserving comment leader on new lines.
---     - Supports nested sessions (expand snippet while there is an active one).
---   See |MiniSnippets.default_insert()|.
---
--- - Exported function to parse snippet body into easy-to-reason data structure.
---   See |MiniSnippets.parse()|.
---
--- Notes:
--- - It does not set up any snippet collection by default. Explicitly populate
---   `config.snippets` to have snippets to match from.
--- - It does not come with a built-in snippet collection. It is expected from
---   users to add their own snippets, manually or with dedicated plugin(s).
--- - It does not support variable/tabstop transformations in default snippet
---   session. This requires ECMAScript Regular Expression parser which can not
---   be implemented concisely.
---
--- Sources with more details:
--- - |MiniSnippets-glossary|
--- - |MiniSnippets-overview|
--- - |MiniSnippets-examples|
--- - |MiniSnippets-in-other-plugins| (for plugin authors)
---
--- # Dependencies ~
---
--- This module doesn't come with snippet collection. Either create it manually
--- or install a dedicated plugin. For example,
--- [rafamadriz/friendly-snippets](https://github.com/rafamadriz/friendly-snippets).
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.snippets').setup({})` (replace `{}`
--- with your `config` table). It will create global Lua table `MiniSnippets` which
--- you can use for scripting or manually (with `:lua MiniSnippets.*`).
---
--- See |MiniSnippets.config| for `config` structure and default values.
---
--- You can override runtime config settings locally to buffer inside
--- `vim.b.minisnippets_config` which should have same structure as
--- `MiniSnippets.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- # Comparisons ~
---
--- - [L3MON4D3/LuaSnip](https://github.com/L3MON4D3/LuaSnip):
---     - Both contain functionality to load snippets from file system.
---       This module provides several common loader generators while 'LuaSnip'
---       contains a more elaborate loading setup.
---       Also both require explicit opt-in for which snippets to load.
---     - Both support LSP snippet format. 'LuaSnip' also provides own more
---       elaborate snippet format which is out of scope for this module.
---     - 'LuaSnip' can autoexpand snippets, while this module always requires
---       an explicit user action to expand (by design).
---     - Both contain snippet expand functionality which differs in some aspects:
---         - 'LuaSnip' has an elaborate dynamic tabstop visualization config.
---           This module provides a handful of dedicated highlight groups.
---         - This module provides configurable visualization of empty tabstops.
---         - 'LusSnip' implements nested sessions by essentially merging them
---           into one. This module treats each nested session separately (to not
---           visually overload) while storing them in stack (first in last out).
---         - 'LuaSnip' uses |Select-mode| to power replacing current tabstop,
---           while this module always stays in |Insert-mode|. This enables easier
---           mapping understanding and more targeted highlighting.
---         - This module implements jumping which wraps after final tabstop
---           for more flexible navigation (enhanced with by a more flexible
---           autostopping rules), while 'LuaSnip' autostops session once
---           jumping reached the final tabstop.
---
--- - Built-in |vim.snippet| (on Neovim>=0.10):
---     - Does not contain functionality to load or match snippets (by design),
---       while this module does.
---     - Both contain expand functionality based on LSP snippet format.
---       Differences in how snippet sessions are handled are similar to
---       comparison with 'LuaSnip'.
---
--- - [rafamadriz/friendly-snippets](https://github.com/rafamadriz/friendly-snippets):
---     - A snippet collection plugin without features to manage or expand them.
---       This module is designed with 'friendly-snippets' compatibility in mind.
---
--- - [abeldekat/cmp-mini-snippets](https://github.com/abeldekat/cmp-mini-snippets):
---     - A source for [hrsh7th/nvim-cmp](https://github.com/hrsh7th/nvim-cmp)
---       that integrates 'mini.snippets'.
---
--- # Highlight groups ~
---
--- - `MiniSnippetsCurrent` - current tabstop.
--- - `MiniSnippetsCurrentReplace` - current tabstop, placeholder is to be replaced.
--- - `MiniSnippetsFinal` - special `$0` tabstop.
--- - `MiniSnippetsUnvisited` - not yet visited tabstop(s).
--- - `MiniSnippetsVisited` - visited tabstop(s).
---
--- To change any highlight group, set it directly with |nvim_set_hl()|.
---
--- # Disabling ~
---
--- To disable core functionality, set `vim.g.minisnippets_disable` (globally) or
--- `vim.b.minisnippets_disable` (for a buffer) to `true`. Considering high number
--- of different scenarios and customization intentions, writing exact rules
--- for disabling module's functionality is left to user. See
--- |mini.nvim-disabling-recipes| for common recipes.
---@tag MiniSnippets

--- POSITION ~
--- Table representing position in a buffer. Fields:
--- - <line> `(number)` - line number (starts at 1).
--- - <col> `(number)` - column number (starts at 1).
---
--- REGION ~
--- Table representing region in a buffer.
--- Fields: <from> and <to> for inclusive start/end POSITIONs.
---
--- SNIPPET ~
--- Data about template to insert. Should contain fields:
--- - <prefix> - string snippet identifier.
--- - <body> - string snippet content with appropriate syntax.
--- - <desc> - string snippet description in human readable form.
---
--- Can also be used to mean snippet body if distinction is clear.
---
--- SNIPPET SESSION ~
--- Interactive state for user to adjust inserted snippet.
---
--- MATCHED SNIPPET ~
--- Snippet which contains <region> field with region that matched it.
--- Usually region needs to be removed.
---
--- SNIPPET NODE ~
--- Unit of parsed snippet body. See |MiniSnippets.parse()|.
---
--- TABSTOP ~
--- Dedicated places in snippet body for users to interactively adjust.
--- Specified in snippet body with `$` followed by digit(s).
---
--- LINKED TABSTOPS ~
--- Different nodes assigned the same tabstop. Updated in sync.
---
--- REFERENCE NODE ~
--- First (from left to right) node of linked tabstops. Used to determine
--- synced text and cursor placement after jump.
---
--- EXPAND ~
--- Action to start snippet session based on currently typed text.
--- Always done in current buffer at cursor. Executed steps:
--- - `PREPARE` - resolve raw config snippets at context.
--- - `MATCH` - match resolved snippets at cursor position.
--- - `SELECT` - possibly choose among matched snippets.
--- - `INSERT` - insert selected snippet and start snippet session.
---@tag MiniSnippets-glossary

--- Snippet is a template for a frequently used text. Typical workflow is to type
--- snippet's (configurable) prefix and expand it into a snippet session: add some
--- pre-defined text and allow user to interactively change/add at certain places.
---
--- This overview assumes default config for mappings and expand.
--- See |MiniSnippets.config| and |MiniSnippets-examples| for more details.
---
--- # Snippet structure ~
---
--- Snippet consists from three parts:
--- - `Prefix` - identifier used to match against current text.
--- - `Body` - actually inserted content with appropriate syntax.
--- - `Desc` - description in human readable form.
---
--- Example: `{ prefix = 'tis', body = 'This is snippet', desc = 'Snip' }`
--- Typing `tis` and pressing "expand" mapping (<C-j> by default) will remove "tis",
--- add "This is snippet", and place cursor at the end in Insert mode.
---
--- # Syntax ~
--- *MiniSnippets-syntax-specification*
---
--- Inserting just text after typing smaller prefix is already powerful enough.
--- For more flexibility, snippet body can be formatted in a special way to
--- provide extra features. This module implements support for syntax defined
--- in LSP specification (with small deviations). See this link for reference:
--- https://microsoft.github.io/language-server-protocol/specifications/lsp/3.18/specification/#snippet_syntax
---
--- A quick overview of basic syntax features:
---
--- - Tabstops are snippet parts meant for interactive editing at their location.
---   They are denoted as `$1`, `$2`, etc.
---   Navigating between them is called "jumping" and is done in numerical order
---   of tabstop identifiers by pressing special keys: <C-l> and <C-h> to jump
---   to next and previous tabstop respectively.
---   Special tabstop `$0` is called "final tabstop": it is used to decide when
---   snippet session is automatically stopped and is visited last during jumping.
---
---   Example: `T1=$1 T2=$2 T0=$0` is expanded as `T1= T2= T0=` with three tabstops.
---
--- - Tabstop can have placeholder: a text used if tabstop is not yet edited.
---   Text is preserved if no editing is done. It follows this same syntax, which
---   means it can itself contain tabstops with placeholders (i.e. be nested).
---   Tabstop with placeholder is denoted as `${1:placeholder}` (`$1` is `${1:}`).
---
---   Example: `T1=${1:text} T2=${2:<$1>}` is expanded as `T1=text T2=<text>`;
---            typing `x` at first placeholder results in `T1=x T2=<x>`;
---            jumping once and typing `y` results in `T1=x T2=y`.
---
--- - There can be several tabstops with same identifier. They are linked and
---   updated in sync during text editing. Can also have different placeholders;
---   they are forced to be the same as in the first (from left to right) tabstop.
---
---   Example: `T1=${1:text} T1=$1` is expanded as `T1=text T1=text`;
---            typing `x` at first placeholder results in `T1=x T1=x`.
---
--- - Tabstop can also have choices: suggestions about tabstop text. It is denoted
---   as `${1|a,b,c|}`. First choice is used as placeholder.
---
---   Example: `T1=${1|left,right|}` is expanded as `T1=left`.
---
--- - Variables can be used to automatically insert text without user interaction.
---   As tabstops, each one can have a placeholder which is used if variable is
---   not defined. There is a special set of variables describing editor state.
---
---   Example: `V1=$TM_FILENAME V2=${NOTDEFINED:placeholder}` is expanded as
---            `V1=current-file-basename V2=placeholder`.
---
--- What's different from LSP specification:
--- - Special set of variables is wider and is taken from VSCode specification:
---   https://code.visualstudio.com/docs/editor/userdefinedsnippets#_variables
---   Exceptions are `BLOCK_COMMENT_START` and `BLOCK_COMMENT_END` as Neovim doesn't
---   provide this information.
--- - Variable `TM_SELECTED_TEXT` is resolved as contents of |quote_quote| register.
---   It assumes that text is put there prior to expanding. For example, visually
---   select, press |c|, type prefix, and expand.
---   See |MiniSnippets-examples| for how to adjust this.
--- - Environment variables are recognized and supported: `V1=$VIMRUNTIME` will
---   use an actual value of |$VIMRUNTIME|.
--- - Variable transformations are not supported during snippet session. It would
---   require interacting with ECMAScript-like regular expressions for which there
---   is no easy way in Neovim. It may change in the future.
---   Transformations are recognized during parsing, though, with some exceptions:
---     - The `}` inside `if` of `${1:?if:else}` needs escaping (for technical reasons).
---
--- There is a |MiniSnippets.parse()| function for programmatically parsing
--- snippet body into a comprehensible data structure.
---
--- # Expand ~
---
--- Using snippets is done via what is called "expanding". It goes like this:
--- - Type snippet prefix or its recognizable part.
--- - Press <C-j> to expand. It will perform the following steps:
---     - Prepare available snippets in current context (buffer + local language).
---       This allows snippet setup to have general function loaders which return
---       different snippets in different contexts.
---     - Match text to the left of cursor with available prefixes. It first tries
---       to do exact match and falls back to fuzzy matching.
---     - If there are several matches, use `vim.ui.select()` to choose one.
---     - Insert single matching snippet. If snippet contains tabstops, start
---       snippet session.
---
--- For more details about each step see:
--- - |MiniSnippets.default_prepare()|
--- - |MiniSnippets.default_match()|
--- - |MiniSnippets.default_select()|
--- - |MiniSnippets.default_insert()|
---
--- Snippet session allows interactive editing at tabstop locations:
---
--- - All tabstop locations are visualized depending on tabstop "state" (whether
---   it is current/visited/unvisited/final and whether it was already edited).
---   Empty tabstops are visualized with inline virtual text ("•"/"∎" for
---   regular/final tabstops). It is removed after session is stopped.
---
--- - Start session at first tabstop. Type text to replace placeholder.
---   When finished with current tabstop, jump to next with <C-l>. Repeat.
---   If changed mind about some previous tabstop, jump back with <C-h>.
---   Jumping also wraps around the edge (first tabstop is next after final).
---
--- - If tabstop has choices, use <C-n> / <C-p> to select next / previous item.
---
--- - Starting another snippet session while there is an active one is allowed.
---   This creates nested sessions: suspend current, start the new one.
---   After newly created is stopped, resume the suspended one.
---
--- - Stop session manually by pressing <C-c> or make it stop automatically:
---   if final tabstop is current either make a text edit or exit to Normal mode.
---   If snippet doesn't explicitly define final tabstop, it is added at the end
---   of the snippet.
---
--- For more details about snippet session see |MiniSnippets-session|.
---
--- To select and insert snippets via completion engine (that supports LSP
--- completion; like |mini.completion| or |lsp-autocompletion|),
--- call |MiniSnippets.start_lsp_server()| after |MiniSnippets.setup()|. This sets up
--- an LSP server that matches and provides snippets loaded with 'mini.snippets'.
--- To match with completion engine, use `start_lsp_server({ match = false })`.
---
--- # Management ~
---
--- Out of the box 'mini.snippets' doesn't load any snippets, it should be done
--- explicitly inside |MiniSnippets.setup()| following |MiniSnippets.config|.
---
--- The suggested approach to snippet management is to create dedicated files with
--- snippet data and load them through function loaders in `config.snippets`.
--- See |MiniSnippets-examples| for basic (yet capable) snippet management config.
---
--- ## File specification ~
--- *MiniSnippets-file-specification*
---
--- General idea of supported files is to have at least out of the box experience
--- with common snippet collections. Namely "rafamadriz/friendly-snippets".
--- The following files are supported:
---
--- - Extensions:
---     - Read/decoded as JSON object (|vim.json.decode()|): `*.json`, `*.code-snippets`
---     - Executed as Lua file (|dofile()|) and uses returned value: `*.lua`
---
--- - Content:
---     - Dict-like: object in JSON; returned table in Lua; no order guarantees.
---     - Array-like: array in JSON; returned array table in Lua; preserves order.
---
--- Example of file content with a single snippet:
--- - Lua dict-like:   `return { name = { prefix = 't', body = 'Text' } }`
--- - Lua array-like:  `return { { prefix = 't', body = 'Text', desc = 'name' } }`
--- - JSON dict-like:  `{ "name": { "prefix": "t", "body": "Text" } }`
--- - JSON array-like: `[ { "prefix": "t", "body": "Text", "desc": "name" } ]`
---
--- Notes:
--- - There is no built-in support for VSCode-like "package.json" files. Define
---   structure manually in |MiniSnippets.setup()| via built-in or custom loaders.
--- - There is no built-in support for `scope` field of snippet data. Snippets are
---   expected to be manually separated into smaller files and loaded on demand.
---
--- For supported snippet syntax see |MiniSnippets-syntax-specification|.
---
--- ## General advice ~
---
--- - Put files in "snippets" subdirectory of any path in 'runtimepath' (like
---   '`$XDG_CONFIG_HOME`/nvim/snippets/global.json').
---   This is compatible with |MiniSnippets.gen_loader.from_runtime()| and
---   example from |MiniSnippets-examples|.
--- - Prefer `*.json` files with dict-like content if you want more cross platfrom
---   setup. Otherwise use `*.lua` files with array-like content.
--- - To implement "dynamic snippet" that changes data (usually <body>) depending
---   on the context, use `*.lua` file with function returning snippet data.
---   It should be an element in the output table (dict or array like).
---
--- # Demo ~
---
--- The best way to grasp the design of snippet management and expansion is to
--- try them out yourself. Here are steps for a basic demo:
--- - Create 'snippets/global.json' file in the config directory with the content: >json
---
---   {
---     "Basic":        { "prefix": "ba", "body": "T1=$1 T2=$2 T0=$0"         },
---     "Placeholders": { "prefix": "pl", "body": "T1=${1:aa}\nT2=${2:<$1>}"  },
---     "Choices":      { "prefix": "ch", "body": "T1=${1|a,b|} T2=${2|c,d|}" },
---     "Linked":       { "prefix": "li", "body": "T1=$1\n\tT1=$1"            },
---     "Variables":    { "prefix": "va", "body": "Runtime: $VIMRUNTIME\n"    },
---     "Complex":      {
---       "prefix": "co",
---       "body": [ "T1=${1:$RANDOM}", "T3=${3:$1_${2:$1}}", "T2=$2" ]
---     }
---   }
--- <
--- - Set up 'mini.snippets' as recommended in |MiniSnippets-examples|.
--- - Open Neovim. Type each snippet prefix and press <C-j> (even if there is
---   still active session). Explore from there.
---@tag MiniSnippets-overview

--- # Basic snippet management config ~
---
--- Example of snippet management setup that should cover most cases: >lua
---
---   -- Setup
---   local gen_loader = require('mini.snippets').gen_loader
---   require('mini.snippets').setup({
---     snippets = {
---       -- Load custom file with global snippets first
---       gen_loader.from_file('~/.config/nvim/snippets/global.json'),
---
---       -- Load snippets based on current language by reading files from
---       -- "snippets/" subdirectories from 'runtimepath' directories.
---       gen_loader.from_lang(),
---     },
---   })
--- <
--- This setup allows having single file with custom "global" snippets (will be
--- present in every buffer) and snippets which will be loaded based on the local
--- language (see |MiniSnippets.gen_loader.from_lang()|).
---
--- Create language snippets manually (by creating and populating
--- '`$XDG_CONFIG_HOME`/nvim/snippets/lua.json' file) or by installing dedicated
--- snippet collection plugin (like 'rafamadriz/friendly-snippets').
---
--- Note: all built-in loaders and |MiniSnippets.read_file()| cache their output
--- by default. It means that after a file is first read, changing it won't have
--- effect during current Neovim session. See |MiniSnippets.gen_loader| about how
--- to reset cache if necessary.
---
--- # Select from all available snippets in current context ~
---
--- With |MiniSnippets.default_match()|, expand snippets (<C-j> by default) at line
--- start or after whitespace. To be able to always select from all current
--- context snippets, make mapping similar to the following: >lua
---
---   local rhs = function() MiniSnippets.expand({ match = false }) end
---   vim.keymap.set('i', '<C-g><C-j>', rhs, { desc = 'Expand all' })
--- <
--- # "Supertab"-like <Tab> / <S-Tab> mappings ~
---
--- This module intentionally by default uses separate keys to expand and jump as
--- it enables cleaner use of nested sessions. Here is an example of setting up
--- custom <Tab> to "expand or jump" and <S-Tab> to "jump to previous": >lua
---
---   local snippets = require('mini.snippets')
---   local match_strict = function(snips)
---     -- Do not match with whitespace to cursor's left
---     return snippets.default_match(snips, { pattern_fuzzy = '%S+' })
---   end
---   snippets.setup({
---     -- ... Set up snippets ...
---     mappings = { expand = '', jump_next = '', jump_prev = '' },
---     expand   = { match = match_strict },
---   })
---   local expand_or_jump = function()
---     local can_expand = #MiniSnippets.expand({ insert = false }) > 0
---     if can_expand then vim.schedule(MiniSnippets.expand); return '' end
---     local is_active = MiniSnippets.session.get() ~= nil
---     if is_active then MiniSnippets.session.jump('next'); return '' end
---     return '\t'
---   end
---   local jump_prev = function() MiniSnippets.session.jump('prev') end
---   vim.keymap.set('i', '<Tab>', expand_or_jump, { expr = true })
---   vim.keymap.set('i', '<S-Tab>', jump_prev)
--- <
--- # Stop session immediately after jumping to final tabstop ~
---
--- Utilize a dedicated |MiniSnippets-events|: >lua
---
---   local fin_stop = function(args)
---     if args.data.tabstop_to == '0' then MiniSnippets.session.stop() end
---   end
---   local au_opts = { pattern = 'MiniSnippetsSessionJump', callback = fin_stop }
---   vim.api.nvim_create_autocmd('User', au_opts)
--- <
--- # Stop all sessions on Normal mode exit ~
---
--- Use |ModeChanged| and |MiniSnippets-events| events: >lua
---
---   local make_stop = function()
---     local au_opts = { pattern = '*:n', once = true }
---     au_opts.callback = function()
---       while MiniSnippets.session.get() do
---         MiniSnippets.session.stop()
---       end
---     end
---     vim.api.nvim_create_autocmd('ModeChanged', au_opts)
---   end
---   local opts = { pattern = 'MiniSnippetsSessionStart', callback = make_stop }
---   vim.api.nvim_create_autocmd('User', opts)
--- <
--- # Customize variable evaluation ~
---
--- Create environment variables and `config.expand.insert` wrapper: >lua
---
---   -- Use evnironment variables with value is same for all snippet sessions
---   vim.loop.os_setenv('USERNAME', 'user')
---
---   -- Compute custom lookup for variables with dynamic values
---   local insert_with_lookup = function(snippet)
---     local lookup = {
---       TM_SELECTED_TEXT = table.concat(vim.fn.getreg('a', true, true), '\n'),
---     }
---     return MiniSnippets.default_insert(snippet, { lookup = lookup })
---   end
---
---   require('mini.snippets').setup({
---     -- ... Set up snippets ...
---     expand = { insert = insert_with_lookup },
---   })
--- <
--- # Using Neovim's built-ins to insert snippet ~
---
--- Define custom `expand.insert` in |MiniSnippets.config| and mappings: >lua
---
---   require('mini.snippets').setup({
---     -- ... Set up snippets ...
---     expand = {
---       insert = function(snippet, _) vim.snippet.expand(snippet.body) end
---     }
---   })
---   -- Make jump mappings or skip to use built-in <Tab>/<S-Tab> in Neovim>=0.11
---   local jump_next = function()
---     if vim.snippet.active({direction = 1}) then return vim.snippet.jump(1) end
---   end
---   local jump_prev = function()
---     if vim.snippet.active({direction = -1}) then vim.snippet.jump(-1) end
---   end
---   vim.keymap.set({ 'i', 's' }, '<C-l>', jump_next)
---   vim.keymap.set({ 'i', 's' }, '<C-h>', jump_prev)
--- <
--- # Using 'mini.snippets' in other plugins ~
--- *MiniSnippets-in-other-plugins*
---
--- - Perform a `_G.MiniSnippets ~= nil` check before using any feature. This
---   ensures that user explicitly set up 'mini.snippets'.
---
--- - To insert snippet given its body (like |vim.snippet.expand()|), use: >lua
---
---      -- Use configured `insert` method with falling back to default
---      local insert = MiniSnippets.config.expand.insert
---        or MiniSnippets.default_insert
---      -- Insert at cursor
---      insert({ body = snippet })
--- <
--- - To get available snippets, use: >lua
---
---   -- Get snippets matched at cursor
---   MiniSnippets.expand({ insert = false })
---
---   -- Get all snippets available at cursor context
---   MiniSnippets.expand({ match = false, insert = false })
--- <
---@tag MiniSnippets-examples

---@alias __minisnippets_cache_opt <cache> `(boolean)` - whether to use cached output. Default: `true`.
---@alias __minisnippets_silent_opt <silent> `(boolean)` - whether to hide non-error messages. Default: `false`.
---@alias __minisnippets_loader_return function Snippet loader.

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local

-- Module definition ==========================================================
local MiniSnippets = {}
local H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniSnippets.config|.
---
---@usage >lua
---   require('mini.snippets').setup({}) -- replace {} with your config table
---                                      -- needs `snippets` field present
--- <
MiniSnippets.setup = function(config)
  -- Export module
  _G.MiniSnippets = MiniSnippets

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Define behavior
  H.create_autocommands()

  -- Create default highlighting
  H.create_default_hl()
end

--- Defaults ~
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text # Loaded snippets ~
---
--- `config.snippets` is an array containing snippet data which can be: snippet
--- table, function loader, or (however deeply nested) array of snippet data.
---
--- Snippet is a table with the following fields:
---
--- - <prefix> `(string|table|nil)` - string used to match against current text.
---    If array, all strings should be used as separate prefixes.
--- - <body> `(string|table|nil)` - content of a snippet which should follow
---    the |MiniSnippets-syntax-specification|. Array is concatenated with `"\n"`.
--- - <desc> `(string|table|nil)` - description of snippet. Can be used to display
---   snippets in a more human readable form. Array is concatenated with `"\n"`.
---
--- Function loaders are expected to be called with single `context` table argument
--- (containing any data about current context) and return same as `config.snippets`
--- data structure.
---
--- `config.snippets` is resolved with `config.prepare` on every expand.
--- See |MiniSnippets.default_prepare()| for how it is done by default.
---
--- For a practical example see |MiniSnippets-examples|.
--- Here is an illustration of `config.snippets` customization capabilities: >lua
---
---   local gen_loader = require('mini.snippets').gen_loader
---   require('mini.snippets').setup({
---     snippets = {
---       -- Load custom file with global snippets first (order matters)
---       gen_loader.from_file('~/.config/nvim/snippets/global.json'),
---
---       -- Or add them here explicitly
---       { prefix='cdate', body='$CURRENT_YEAR-$CURRENT_MONTH-$CURRENT_DATE' },
---
---       -- Load snippets based on current language by reading files from
---       -- "snippets/" subdirectories from 'runtimepath' directories.
---       gen_loader.from_lang(),
---
---       -- Load project-local snippets with `gen_loader.from_file()`
---       -- and relative path (file doesn't have to be present)
---       gen_loader.from_file('.vscode/project.code-snippets'),
---
---       -- Custom loader for language-specific project-local snippets
---       function(context)
---         local rel_path = '.vscode/' .. context.lang .. '.code-snippets'
---         if vim.fn.filereadable(rel_path) == 0 then return end
---         return MiniSnippets.read_file(rel_path)
---       end,
---
---       -- Ensure that some prefixes are not used (as there is no `body`)
---       { prefix = { 'bad', 'prefix' } },
---     }
---   })
--- <
--- # Mappings ~
---
--- `config.mappings` describes which mappings are automatically created.
---
--- `mappings.expand` is created globally in Insert mode and is used to expand
--- snippet at cursor. Use |MiniSnippets.expand()| for custom mappings.
---
--- `mappings.jump_next`, `mappings.jump_prev`, and `mappings.stop` are created for
--- the duration of active snippet session(s) from |MiniSnippets.default_insert()|.
--- Used to jump to next/previous tabstop and stop active session respectively.
--- Use |MiniSnippets.session.jump()| and |MiniSnippets.session.stop()| for custom
--- Insert mode mappings.
--- Note: do not use `"<C-n>"` or `"<C-p>"` for any action as they conflict with
--- built-in completion: it forces them to mean "change focus to next/previous
--- completion item". This matters more frequently than when there is a tabstop
--- with choices due to how this module handles built-in completion during jumps.
---
--- # Expand ~
---
--- `config.expand` defines expand steps (see |MiniSnippets-glossary|), either after
--- pressing `mappings.expand` or starting manually via |MiniSnippets.expand()|.
---
--- `expand.prepare` is a function that takes `raw_snippets` in the form of
--- `config.snippets` and should return a plain array of snippets (as described
--- in |MiniSnippets-glossary|). Will be called on every |MiniSnippets.expand()| call.
--- If returns second value, it will be used as context for warning messages.
--- Default: |MiniSnippets.default_prepare()|.
---
--- `expand.match` is a function that takes `expand.prepare` output and returns
--- an array of matched snippets: one or several snippets user might intend to
--- eventually insert. Should sort matches in output from best to worst.
--- Entries can contain `region` field with current buffer region used to do
--- the match; usually it needs to be removed (similar to how |ins-completion|
--- and |abbreviations| work).
--- Default: |MiniSnippets.default_match()|
---
--- `expand.select` is a function that takes output of `expand.match` and function
--- that inserts snippet (and also ensures Insert mode and removes snippet's match
--- region). Should allow user to perform interactive snippet selection and
--- insert the chosen one. Designed to be compatible with |vim.ui.select()|.
--- Called for any non-empty `expand.match` output (even with single entry).
--- Default: |MiniSnippets.default_select()|
---
--- `expand.insert` is a function that takes single snippet table as input and
--- inserts snippet at cursor position. This is a main entry point for adding
--- text template to buffer and starting a snippet session.
--- If called inside |MiniSnippets.expand()| (which is a usual interactive case),
--- all it has to do is insert snippet at cursor position. Ensuring Insert mode
--- and removing matched snippet region is done beforehand.
--- Default: |MiniSnippets.default_insert()|
---
--- Illustration of `config.expand` customization: >lua
---
---   -- Supply extra data as context
---   local my_p = function(raw_snippets)
---     local _, cont = MiniSnippets.default_prepare({})
---     cont.cursor = vim.api.nvim_win_get_cursor()
---     return MiniSnippets.default_prepare(raw_snippets, { context = cont })
---   end
---   -- Perform fuzzy match based only on alphanumeric characters
---   local my_m = function(snippets)
---     return MiniSnippets.default_match(snippets, { pattern_fuzzy = '%w*' })
---   end
---   -- Always insert the best matched snippet
---   local my_s = function(snippets, insert) return insert(snippets[1]) end
---   -- Use different string to show empty tabstop as inline virtual text
---   local my_i = function(snippet)
---     return MiniSnippets.default_insert(snippet, { empty_tabstop = '$' })
---   end
---
---   require('mini.snippets').setup({
---     -- ... Set up snippets ...
---     expand = { prepare = my_p, match = my_m, select = my_s, insert = my_i }
---   })
--- <
MiniSnippets.config = {
  -- Array of snippets and loaders (see |MiniSnippets.config| for details).
  -- Nothing is defined by default. Add manually to have snippets to match.
  snippets = {},

  -- Module mappings. Use `''` (empty string) to disable one.
  mappings = {
    -- Expand snippet at cursor position. Created globally in Insert mode.
    expand = '<C-j>',

    -- Interact with default `expand.insert` session.
    -- Created for the duration of active session(s)
    jump_next = '<C-l>',
    jump_prev = '<C-h>',
    stop = '<C-c>',
  },

  -- Functions describing snippet expansion. If `nil`, default values
  -- are `MiniSnippets.default_<field>()`.
  expand = {
    -- Resolve raw config snippets at context
    prepare = nil,
    -- Match resolved snippets at cursor position
    match = nil,
    -- Possibly choose among matched snippets
    select = nil,
    -- Insert selected snippet
    insert = nil,
  },
}
--minidoc_afterlines_end

--- Expand snippet at cursor position
---
--- Perform expand steps (see |MiniSnippets-glossary|).
--- Initial raw snippets are taken from `config.snippets` in current buffer.
--- Snippets from `vim.b.minisnippets_config` are appended to global snippet array.
---
---@param opts table|nil Options. Same structure as `expand` in |MiniSnippets.config|
---   and uses its values as default. There are differences in allowed values:
---   - Use `match = false` to have all buffer snippets as matches.
---   - Use `select = false` to always expand the best match (if any).
---   - Use `insert = false` to return all matches without inserting.
---
---   Note: `opts.insert` is called after ensuring Insert mode, removing snippet's
---   match region, and positioning cursor.
---
---@return table|nil If `insert` is `false`, an array of matched snippets (`expand.match`
---   output). Otherwise `nil`.
---
---@usage >lua
---   -- Match, maybe select, and insert
---   MiniSnippets.expand()
---
---   -- Match and force expand the best match (if any)
---   MiniSnippets.expand({ select = false })
---
---   -- Use all current context snippets as matches
---   MiniSnippets.expand({ match = false })
---
---   -- Get all matched snippets
---   local matches = MiniSnippets.expand({ insert = false })
---
---   -- Get all current context snippets
---   local all = MiniSnippets.expand({ match = false, insert = false })
--- <
---
---@seealso |MiniSnippets.start_lsp_server()| to instead show loaded snippets
---   in (auto)completion engines (like |mini.completion|).
MiniSnippets.expand = function(opts)
  if H.is_disabled() then return end
  local config = H.get_config()
  opts = vim.tbl_extend('force', config.expand, opts or {})

  -- Validate
  local prepare = opts.prepare or MiniSnippets.default_prepare
  if not vim.is_callable(prepare) then H.error('`opts.prepare` should be callable') end

  local match = false
  if opts.match ~= false then match = opts.match or MiniSnippets.default_match end
  if not (match == false or vim.is_callable(match)) then H.error('`opts.match` should be `false` or callable') end

  local select = false
  if opts.select ~= false then select = opts.select or MiniSnippets.default_select end
  if not (select == false or vim.is_callable(select)) then H.error('`opts.select` should be `false` or callable') end

  local insert = false
  if opts.insert ~= false then insert = opts.insert or MiniSnippets.default_insert end
  if not (insert == false or vim.is_callable(insert)) then H.error('`opts.insert` should be `false` or callable') end

  -- Match
  local all_snippets, context = prepare(config.snippets)
  if not H.is_array_of(all_snippets, H.is_snippet) then H.error('`prepare` should return array of snippets') end
  local matches = match == false and all_snippets or match(all_snippets)
  if not H.is_array_of(matches, H.is_snippet) then H.error('`match` should return array of snippets') end

  -- Act
  if insert == false then return matches end
  if #all_snippets == 0 then return H.notify('No snippets in context:\n' .. vim.inspect(context), 'WARN') end
  if #matches == 0 then return H.notify('No matches in context:\n' .. vim.inspect(context), 'WARN') end

  local insert_ext = H.make_extended_insert(insert)

  if select == false then return insert_ext(matches[1]) end
  select(matches, insert_ext)
end

--- Generate snippet loader
---
--- This is a table with function elements. Call to actually get a loader.
---
--- Common features for all produced loaders:
--- - Designed to work with |MiniSnippets-file-specification|.
--- - Cache output by default, i.e. second and later calls with same input value
---   don't read file system. Different loaders from same generator share cache.
---   Disable by setting `opts.cache` to `false`.
---   To clear all cache, call |MiniSnippets.setup()|. For example:
---   `MiniSnippets.setup(MiniSnippets.config)`
--- - Use |vim.notify()| to show problems during loading while trying to load as
---   much correctly defined snippet data as possible.
---   Disable by setting `opts.silent` to `true`.
MiniSnippets.gen_loader = {}

--- Generate language loader
---
--- Output loads files from "snippets/" subdirectories of 'runtimepath' matching
--- configured language patterns.
--- See |MiniSnippets.gen_loader.from_runtime()| for runtime loading details.
---
--- Language is taken from <lang> field (if present with string value) of `context`
--- argument used in loader calls during "prepare" stage.
--- This is compatible with |MiniSnippets.default_prepare()| and most snippet
--- collection plugins.
---
---@param opts table|nil Options. Possible values:
---   - <lang_patterns> `(table)` - map from language to array of runtime patterns
---     used to find snippet files, as in |MiniSnippets.gen_loader.from_runtime()|.
---     Patterns will be processed in order. With |MiniSnippets.default_prepare()|
---     it means if snippets have same prefix, data from later patterns is used.
---     To interactively check the current language with default context, execute
---     `:=MiniSnippets.default_prepare({})` and see data in the second table.
---
---     Default pattern array (for non-empty language) is constructed as to read
---     `*.json` and `*.lua` files that are:
---     - Inside "snippets/" subdirectory named as language (files can be however
---       deeply nested).
---     - Named as language and is in "snippets/" directory (however deep).
---     Example for "lua" language: >lua
---         { 'lua/**/*.json', 'lua/**/*.lua', '**/lua.json', '**/lua.lua' }
--- <
---     Add entry for `""` (empty string) as language to be sourced when `lang`
---     context is empty string (which is usually temporary scratch buffers).
---
---   - __minisnippets_cache_opt
---     Note: caching is done per used runtime pattern, not `lang` value to allow
---     different `from_lang()` loaders to share cache.
---   - __minisnippets_silent_opt
---
---@return __minisnippets_loader_return
---
---@usage >lua
---   -- Adjust language patterns
---   local latex_patterns = { 'latex/**/*.json', '**/latex.json' }
---   local lang_patterns = {
---     tex = latex_patterns, plaintex = latex_patterns,
---     -- Recognize special injected language of markdown tree-sitter parser
---     markdown_inline = { 'markdown.json' },
---   }
---   local gen_loader = require('mini.snippets').gen_loader
---   require('mini.snippets').setup({
---     snippets = {
---       gen_loader.from_lang({ lang_patterns = lang_patterns }),
---     },
---   })
--- <
MiniSnippets.gen_loader.from_lang = function(opts)
  opts = vim.tbl_extend('force', { lang_patterns = {}, cache = true, silent = false }, opts or {})
  for lang, tbl in pairs(opts.lang_patterns) do
    if type(lang) ~= 'string' then H.error('Keys of `opts.lang_patterns` should be string language names') end
    if not H.is_array_of(tbl, H.is_string) then H.error('Values of `opts.lang_patterns` should be string arrays') end
  end

  local loaders, loader_opts = {}, { cache = opts.cache, silent = opts.silent }

  return function(context)
    local lang = (context or {}).lang
    if type(lang) ~= 'string' then return {} end

    local patterns = opts.lang_patterns[lang]
    if patterns == nil and lang == '' then return {} end
    -- NOTE: Don't use `{json,lua}` for better compatibility, as it seems that
    -- its support might depend on the shell (and might not work on Windows).
    -- Which is shame because fewer patterns used mean fewer calls to cache.
    patterns = patterns
      or { lang .. '/**/*.json', lang .. '/**/*.lua', '**/' .. lang .. '.json', '**/' .. lang .. '.lua' }

    local res = {}
    for _, pat in ipairs(patterns) do
      local loader = loaders[pat] or MiniSnippets.gen_loader.from_runtime(pat, loader_opts)
      loaders[pat] = loader
      table.insert(res, loader(context))
    end
    return res
  end
end

--- Generate runtime loader
---
--- Output loads files which match `pattern` inside "snippets/" directories from
--- 'runtimepath'. This is useful to simultaneously read several similarly
--- named files from different sources. Order from 'runtimepath' is preserved.
---
--- Typical case is loading snippets for a language from files like `xxx.{json,lua}`
--- but located in different "snippets/" directories inside 'runtimepath'.
--- - `<config>`/snippets/lua.json - manually curated snippets in user config.
--- - `<path/to/installed/plugin>`/snippets/lua.json - from installed plugin.
--- - `<config>`/after/snippets/lua.json - used to adjust snippets from plugins.
---   For example, remove some snippets by using prefixes and no body.
---
---@param pattern string Pattern of files to read. Can have wildcards as described
---   in |nvim_get_runtime_file()|. Example for "lua" language: `'lua.{json,lua}'`.
---@param opts table|nil Options. Possible fields:
---   - <all> `(boolean)` - whether to load from all matching runtime files.
---     Default: `true`.
---   - __minisnippets_cache_opt
---     Note: caching is done per `pattern` value, which assumes that both
---     'runtimepath' value and snippet files do not change during Neovim session.
---     Caching this way gives significant speed improvement by reducing the need
---     to traverse file system on every snippet expand.
---   - __minisnippets_silent_opt
---
---@return __minisnippets_loader_return
MiniSnippets.gen_loader.from_runtime = function(pattern, opts)
  if type(pattern) ~= 'string' then H.error('`pattern` should be string') end
  opts = vim.tbl_extend('force', { all = true, cache = true, silent = false }, opts or {})

  pattern = 'snippets/' .. pattern
  local cache, read_opts = opts.cache, { cache = opts.cache, silent = opts.silent }
  local read = function(p) return MiniSnippets.read_file(p, read_opts) end
  return function()
    if cache and H.cache.runtime[pattern] ~= nil then return vim.deepcopy(H.cache.runtime[pattern]) end

    local res = vim.tbl_map(read, vim.api.nvim_get_runtime_file(pattern, opts.all))
    if cache then H.cache.runtime[pattern] = vim.deepcopy(res) end
    return res
  end
end

--- Generate single file loader
---
--- Output is a thin wrapper around |MiniSnippets.read_file()| which will skip
--- warning if file is absent (other messages are still shown). Use it to load
--- file which is not guaranteed to exist (like project-local snippets).
---
---@param path string Same as in |MiniSnippets.read_file()|.
---@param opts table|nil Same as in |MiniSnippets.read_file()|.
---
---@return __minisnippets_loader_return
MiniSnippets.gen_loader.from_file = function(path, opts)
  if type(path) ~= 'string' then H.error('`path` should be string') end
  opts = vim.tbl_extend('force', { cache = true, silent = false }, opts or {})

  return function()
    local full_path = vim.fn.fnamemodify(path, ':p')
    if vim.fn.filereadable(full_path) ~= 1 then return {} end
    return MiniSnippets.read_file(full_path, opts) or {}
  end
end

--- Read file with snippet data
---
---@param path string Path to file with snippets. Can be relative.
---   See |MiniSnippets-file-specification| for supported file formats.
---@param opts table|nil Options. Possible fields:
---   - __minisnippets_cache_opt
---     Note: Caching is done per full path only after successful reading.
---   - __minisnippets_silent_opt
---
---@return table|nil Array of snippets or `nil` if failed (also warn with |vim.notify()|
---   about the reason).
MiniSnippets.read_file = function(path, opts)
  if type(path) ~= 'string' then H.error('`path` should be string') end
  opts = vim.tbl_extend('force', { cache = true, silent = false }, opts or {})

  path = vim.fn.fnamemodify(path, ':p')
  local problem_prefix = 'There were problems reading file ' .. path .. ':\n'
  if opts.cache and H.cache.file[path] ~= nil then return vim.deepcopy(H.cache.file[path]) end

  if vim.fn.filereadable(path) ~= 1 then
    return H.notify(problem_prefix .. 'File is absent or not readable', 'WARN', opts.silent)
  end
  local ext = path:match('%.([^%.]+)$')
  if ext == nil or not (ext == 'lua' or ext == 'json' or ext == 'code-snippets') then
    return H.notify(problem_prefix .. 'Extension is not supported', 'WARN', opts.silent)
  end

  local res = H.file_readers[ext](path, opts.silent)

  -- Notify about problems but still cache if there are read snippets
  local prob = table.concat(res.problems, '\n')
  if prob ~= '' then H.notify(problem_prefix .. prob, 'WARN', opts.silent) end

  if res.snippets == nil then return nil end
  if opts.cache then H.cache.file[path] = vim.deepcopy(res.snippets) end
  return res.snippets
end

--- Default prepare
---
--- Normalize raw snippets (as in `snippets` from |MiniSnippets.config|) based on
--- supplied context:
--- - Traverse and flatten nested arrays. Function loaders are executed with
---   `opts.context` as argument and output is processed recursively.
--- - Ensure unique non-empty prefixes: later ones completely override earlier
---   ones (similar to how |ftplugin| and similar runtime design behave).
---   Empty string prefixes are all added (to allow inserting without matching).
--- - Transform and infer fields:
---     - Multiply array `prefix` into several snippets with same body/description.
---       Infer absent `prefix` as empty string.
---     - Concatenate array `body` with `"\n"`. Do not infer absent `body` to have
---       it remove previously added snippet with the same prefix.
---     - Concatenate array `desc` with `"\n"`. Infer `desc` field from `description`
---       (for compatibility) or `body` fields, in that order.
--- - Sort output by prefix.
---
--- Unlike |MiniSnippets.gen_loader| entries, there is no output caching. This
--- avoids duplicating data from `gen_loader` cache and reduces memory usage.
--- It also means that every |MiniSnippets.expand()| call prepares snippets, which
--- is usually fast enough. If not, consider manual caching: >lua
---
---   local cache = {}
---   local prepare_cached = function(raw_snippets)
---     local _, cont = MiniSnippets.default_prepare({})
---     local id = 'buf=' .. cont.buf_id .. ',lang=' .. cont.lang
---     if cache[id] then return unpack(vim.deepcopy(cache[id])) end
---     local snippets = MiniSnippets.default_prepare(raw_snippets)
---     cache[id] = vim.deepcopy({ snippets, cont })
---     return snippets, cont
---   end
--- <
---@param raw_snippets table Array of snippet data as from |MiniSnippets.config|.
---@param opts table|nil Options. Possible fields:
---   - <context> `(any)` - Context used as an argument for callable snippet data.
---     Default: table with <buf_id> (current buffer identifier) and <lang> (local
---     language) fields. Language is computed from tree-sitter parser at cursor
---     (allows different snippets in injected languages), 'filetype' otherwise.
---
---@return ... Array of snippets and supplied context (default if none was supplied).
MiniSnippets.default_prepare = function(raw_snippets, opts)
  if not H.islist(raw_snippets) then H.error('`raw_snippets` should be array') end
  opts = vim.tbl_extend('force', { context = nil }, opts or {})
  local context = opts.context
  if context == nil then context = H.get_default_context() end

  -- Traverse snippets to have unique non-empty prefixes
  local res = {}
  H.traverse_raw_snippets(raw_snippets, res, context)

  -- Convert to array ordered by prefix
  res = vim.tbl_values(res)
  table.sort(res, function(a, b) return a.prefix < b.prefix end)
  return res, context
end

--- Default match
---
--- Match snippets based on the line before cursor.
---
--- Tries two matching approaches consecutively:
--- - Find exact snippet prefix (if present and non-empty) to the left of cursor.
---   It should also be preceded with a byte that matches `pattern_exact_boundary`.
---   In case of any match, return the one with the longest prefix.
--- - Match fuzzily snippet prefixes against the base (text to the left of cursor
---   extracted via `opts.pattern_fuzzy`). Matching is done via |matchfuzzy()|.
---   Empty base results in all snippets being matched. Return all fuzzy matches.
---
---@param snippets table Array of snippets which can be matched.
---@param opts table|nil Options. Possible fields:
---   - <pattern_exact_boundary> `(string)` - Lua pattern for the byte to the left
---     of exact match to accept it. Line start is matched against empty string;
---     use `?` quantifier to allow it as boundary.
---     Default: `[%s%p]?` (accept only whitespace and punctuation as boundary,
---     allow match at line start).
---     Example: prefix "l" matches in lines `l`, `_l`, `x l`; but not `1l`, `ll`.
---   - <pattern_fuzzy> `(string)` - Lua pattern to extract base to the left of
---     cursor for fuzzy matching. Supply empty string to skip this step.
---     Default: `'%S*'` (as many as possible non-whitespace; allow empty string).
---
---@return table Array of matched snippets ordered from best to worst match.
---
---@usage >lua
---   -- Accept any exact match
---   MiniSnippets.default_match(snippets, { pattern_exact_boundary = '.?' })
---
---   -- Perform fuzzy match based only on alphanumeric characters
---   MiniSnippets.default_match(snippets, { pattern_fuzzy = '%w*' })
--- <
MiniSnippets.default_match = function(snippets, opts)
  if not H.is_array_of(snippets, H.is_snippet) then H.error('`snippets` should be array of snippets') end
  opts = vim.tbl_extend('force', { pattern_exact_boundary = '[%s%p]?', pattern_fuzzy = '%S*' }, opts or {})
  if not H.is_string(opts.pattern_exact_boundary) then H.error('`opts.pattern_exact_boundary` should be string') end

  -- Compute line before cursor. Treat Insert mode as exclusive for right edge.
  local lnum, col = vim.fn.line('.'), vim.fn.col('.')
  local to = col - (vim.fn.mode() == 'i' and 1 or 0)
  local line = vim.fn.getline(lnum):sub(1, to)

  -- Exact. Use 0 as initial best match width to not match empty prefixes.
  local best_id, best_match_width = nil, 0
  local pattern_boundary = '^' .. opts.pattern_exact_boundary .. '$'
  for i, s in pairs(snippets) do
    local w = (s.prefix or ''):len()
    if best_match_width < w and line:sub(-w) == s.prefix and line:sub(-w - 1, -w - 1):find(pattern_boundary) then
      best_id, best_match_width = i, w
    end
  end
  if best_id ~= nil then
    local res = vim.deepcopy(snippets[best_id])
    res.region = { from = { line = lnum, col = to - best_match_width + 1 }, to = { line = lnum, col = to } }
    return { res }
  end

  -- Fuzzy
  if not H.is_string(opts.pattern_fuzzy) then H.error('`opts.pattern_fuzzy` should be string') end
  if opts.pattern_fuzzy == '' then return {} end

  local base = string.match(line, opts.pattern_fuzzy .. '$')
  if base == nil then return {} end
  if base == '' then return vim.deepcopy(snippets) end

  local snippets_with_prefix = vim.tbl_filter(function(s) return s.prefix ~= nil end, snippets)
  local fuzzy_matches = vim.fn.matchfuzzy(snippets_with_prefix, base, { key = 'prefix' })
  local from_col = to - base:len() + 1
  for _, s in ipairs(fuzzy_matches) do
    s.region = { from = { line = lnum, col = from_col }, to = { line = lnum, col = to } }
  end

  return fuzzy_matches
end

--- Default select
---
--- Show snippets as |vim.ui.select()| items and insert the chosen one.
--- For best interactive experience requires `vim.ui.select()` to work from Insert
--- mode (be properly called and restore Insert mode after choice).
--- This is the case for at least |MiniPick.ui_select()| and Neovim's default.
---
---@param snippets table Array of snippets (as an output of `config.expand.match`).
---@param insert function|nil Function to insert chosen snippet (passed as the only
---   argument). Expected to remove snippet's match region (if present as a field)
---   and ensure proper cursor position in Insert mode.
---   Default: |MiniSnippets.default_insert()|.
---@param opts table|nil Options. Possible fields:
---   - <insert_single> `(boolean)` - whether to skip |vim.ui.select()| for `snippets`
---     with a single entry and insert it directly. Default: `true`.
MiniSnippets.default_select = function(snippets, insert, opts)
  if not H.is_array_of(snippets, H.is_snippet) then H.error('`snippets` should be an array of snippets') end
  if #snippets == 0 then return H.notify('No snippets to select from', 'WARN') end
  insert = insert or MiniSnippets.default_insert
  if not vim.is_callable(insert) then H.error('`insert` should be callable') end
  opts = opts or {}

  if #snippets == 1 and (opts.insert_single == nil or opts.insert_single == true) then
    insert(snippets[1])
    return
  end

  -- Format
  local prefix_width = 0
  for i, s in ipairs(snippets) do
    local prefix = s.prefix or '<No prefix>'
    prefix_width = math.max(prefix_width, vim.fn.strdisplaywidth(prefix))
  end
  local format_item = function(s)
    local prefix, desc = s.prefix or '<No prefix>', s.desc or s.description or '<No description>'
    local pad = string.rep(' ', prefix_width - vim.fn.strdisplaywidth(prefix))
    return prefix .. pad .. ' │ ' .. desc
  end

  -- Schedule insert to allow `vim.ui.select` override to restore window/cursor
  local on_choice = vim.schedule_wrap(function(item, _) insert(item) end)
  vim.ui.select(snippets, { prompt = 'Snippets', format_item = format_item }, on_choice)
end

--- Default insert
---
--- Prepare for snippet insert and do it:
--- - Ensure Insert mode.
--- - Delete snippet's match region (if present as <region> field). Ensure cursor.
--- - Parse snippet body with |MiniSnippets.parse()| and enabled `normalize`.
---   In particular, evaluate variables, ensure final node presence and same
---   text for nodes with same tabstops. Stop if not able to.
--- - Insert snippet at cursor:
---     - Add snippet's text. Lines are split at "\n".
---       Indent and left comment leaders (inferred from 'commentstring' and
---       'comments') of current line are repeated on the next.
---       Tabs ("\t") are expanded according to 'expandtab' and 'shiftwidth'.
---     - If there is an actionable tabstop (not final), start snippet session.
---
--- # Session life cycle ~
--- *MiniSnippets-session*
---
--- - Start with cursor at first tabstop. If there are linked tabstops, cursor
---   is placed at start of reference node (see |MiniSnippets-glossary|).
---   All tabstops are visualized with dedicated highlight groups (see "Highlight
---   groups" section in |mini.snippets|).
---   Empty tabstops are visualized with inline virtual text ("•"/"∎" for
---   regular/final tabstops) meaning that it is not an actual text in the
---   buffer and will be removed after session is stopped.
---
--- - Decide whether you want to replace the placeholder. If not, jump to next or
---   previous tabstop. If yes, edit it: add new and/or delete already added text.
---   While doing so, several things happen in all linked tabstops (if any):
---
---     - After first typed character the placeholder is removed and highlighting
---       changes from `MiniSnippetsCurrentReplace` to `MiniSnippetsCurrent`.
---     - Text in all tabstop nodes is synchronized with the reference one.
---       Relative indent of reference tabstop's text is preserved: all but first
---       lines in linked tabstops are reindented based on the first line indent.
---       Note: text sync is forced only for current tabstop (for performance).
---
--- - Jump with <C-l> / <C-h> to next / previous tabstop. Exact keys can be
---   adjusted in |MiniSnippets.config| `mappings`.
---   See |MiniSnippets.session.jump()| for jumping details.
---
--- - If tabstop has choices, all of them are shown after each jump and deleting
---   tabstop text. It is done with |complete()|, so use <C-n> / <C-p> to select
---   next / previous choice. Type text to narrow down the list.
---   Works best when 'completeopt' option contains `menuone` and `noselect` flags.
---   Note: deleting character hides the list due to how |complete()| works;
---   delete whole tabstop text (for example with one or more |i_CTRL-W|) for
---   full list to reappear.
---
--- - Nest another session by expanding snippet in the same way as without
---   active session (can be even done in another buffer). If snippet has no
---   actionable tabstop, text is just inserted. Otherwise start nested session:
---
---     - Suspend current session: hide highlights, keep text change tracking.
---     - Start new session and act as if it is the only one (edit/jump/nest).
---     - When ready (possibly after even more nested sessions), stop the session.
---       This will resume previous one: sync text for its current tabstop and
---       show highlighting.
---       The experience of text synchronization only after resuming session is
---       similar to how editing in |visual-block| mode works.
---       Nothing else (like cursor/mode/buffer) is changed for a smoother
---       automated session stop.
---
---   Notes about the choice of the "session stack" approach to nesting over more
---   common "merge into single session" approach:
---   - Does not overload with highlighting.
---   - Allows nested sessions in different buffers.
---   - Doesn't need a complex logic of injecting one session into another.
---
--- - Repeat edit/jump/nest steps any number of times.
---
--- - Stop. It can be done in two ways:
---
---     - Manually by pressing <C-c> or calling |MiniSnippets.session.stop()|.
---       Exact key can be adjusted in |MiniSnippets.config| `mappings`.
---     - Automatically: any text edit or switching to Normal mode stops session
---       if final tabstop (`$0`) is current. Its presence is ensured after insert.
---       Not stopping session right away after jumping to final mode (as most
---       other snippet plugins do) allows going back to other tabstops in case
---       of a late missed typo. Wrapping around the edge during jumping also
---       helps with that.
---       If current tabstop is not final, exiting into Normal mode for quick edit
---       outside of snippets range (or carefully inside) is fine. Later get back
---       into Insert mode and jump to next tabstop or manually stop session.
---   See |MiniSnippets-examples| for how to set up custom stopping rules.
---
--- Use |MiniSnippets.session.get()| to get data about active/nested session(s).
--- Use |MiniSnippets.session.jump()| / |MiniSnippets.session.stop()| in mappings.
---
--- What is allowed but not officially supported/recommended:
---
--- - Editing text within snippet range but outside of session life cycle. Mostly
---   behaves as expected, but may harm tracking metadata (|extmarks|).
---   In general anything but deleting tabstop range should be OK.
---   Text synchronization of current tabstop would still be active.
---
--- # Events ~
--- *MiniSnippets-events*
---
--- General session activity (autocommand data contains <session> field):
--- - `MiniSnippetsSessionStart` - after a session is started.
--- - `MiniSnippetsSessionStop` - before a session is stopped.
---
--- Nesting session activity (autocommand data contains <session> field):
--- - `MiniSnippetsSessionSuspend` - before a session is suspended.
--- - `MiniSnippetsSessionResume` - after a session is resumed.
---
--- Jumping between tabstops (autocommand data contains <tabstop_from> and
--- <tabstop_new> fields):
--- - `MiniSnippetsSessionJumpPre` - before jumping to a new tabstop.
--- - `MiniSnippetsSessionJump` - after jumping to a new tabstop.
---
---@param snippet table Snippet table. Field <body> is mandatory.
---@param opts table|nil Options. Possible fields:
---   - <empty_tabstop> `(string)` - used to visualize empty regular tabstops.
---     Default: "•".
---   - <empty_tabstop_final> `(string)` - used to visualize empty final tabstop(s).
---     Default: "∎".
---   - <lookup> `(table)` - passed to |MiniSnippets.parse()|. Use it to adjust
---     how variables are evaluated. Default: `{}`.
MiniSnippets.default_insert = function(snippet, opts)
  if not H.is_snippet(snippet) then H.error('`snippet` should be a snippet table') end

  local default_opts = { empty_tabstop = '•', empty_tabstop_final = '∎', lookup = {} }
  opts = vim.tbl_deep_extend('force', default_opts, opts or {})
  if not H.is_string(opts.empty_tabstop) then H.error('`empty_tabstop` should be string') end
  if not H.is_string(opts.empty_tabstop_final) then H.error('`empty_tabstop_final` should be string') end
  if type(opts.lookup) ~= 'table' then H.error('`lookup` should be table') end

  local nodes = MiniSnippets.parse(snippet.body, { normalize = true, lookup = opts.lookup })

  -- Ensure insert in Insert mode (for proper cursor positioning at EOL)
  H.call_in_insert_mode(function()
    H.delete_region(snippet.region)
    H.session_init(H.session_new(nodes, snippet, opts), true)
  end)
end

--- Work with snippet session from |MiniSnippets.default_insert()|
MiniSnippets.session = {}

--- Get data about active session
---
---@param all boolean|nil Whether to return array with the whole session stack.
---   Default: `false`.
---
---@return table Single table with session data (if `all` is `false`) or array of them.
---   Session data contains the following fields:
---    - <buf_id> `(number)` - identifier of session's buffer.
---    - <cur_tabstop> `(string)` - identifier of session's current tabstop.
---    - <extmark_id> `(number)` - |extmark| identifier which track session range.
---    - <insert_args> `(table)` - |MiniSnippets.default_insert()| arguments used to
---      create the session. A table with <snippet> and <opts> fields.
---    - <nodes> `(table)` - parsed array of snippet nodes which is kept up to date
---      during session. Has the structure of a normalized |MiniSnippets.parse()|
---      output, plus every node contains `extmark_id` field with |extmark| identifier
---      which can be used to get data about the current node state.
---    - <ns_id> `(number)` - |namespace| identifier for all session's extmarks.
---    - <tabstops> `(table)` - data about session's tabstops. Fields are string
---      tabstop identifiers and values are tables with the following fields:
---        - <is_visited> `(boolean)` - whether tabstop was visited.
---        - <next> `(string)` - identifier of the next tabstop.
---        - <prev> `(string)` - identifier of the previous tabstop.
MiniSnippets.session.get = function(all) return vim.deepcopy(all and H.sessions or H.get_active_session()) end

--- Jump to next/previous tabstop
---
--- Make next/previous tabstop be current. Executes the following steps:
--- - Mark current tabstop as visited.
--- - Find the next/previous tabstop id assuming they are sorted as numbers.
---   Tabstop "0" is always last. Search is wrapped around the edges: first and
---   final tabstops are next/previous for one another.
--- - Focus on target tabstop:
---     - Ensure session's buffer is current.
---     - Adjust highlighting of affected nodes.
---     - Set cursor at tabstop's reference node (first node among linked).
---       Cursor is placed on left edge if tabstop has not been edited yet (so
---       typing text replaces placeholder), on right edge otherwise (to update
---       already edited text).
---     - Show all choices for tabstop with choices. Navigating through choices
---       will update tabstop's text.
---
---@param direction string One of "next" or "prev".
MiniSnippets.session.jump = function(direction)
  if not (direction == 'prev' or direction == 'next') then H.error('`direction` should be one of "prev", "next"') end
  H.call_in_insert_mode(function() H.session_jump(H.get_active_session(), direction) end)
end

--- Stop (only) active session
---
--- To stop all nested sessions use the following code: >lua
---
---   while MiniSnippets.session.get() do
---     MiniSnippets.session.stop()
---   end
--- <
MiniSnippets.session.stop = function()
  local cur_session = H.get_active_session()
  if cur_session == nil then return end
  H.session_deinit(cur_session, true)
  H.sessions[#H.sessions] = nil
  if #H.sessions == 0 then
    vim.api.nvim_del_augroup_by_name('MiniSnippetsTrack')
    H.unmap_in_sessions()
  end
  H.clean_sessions()
  H.session_init(H.get_active_session(), false)
end

--- Parse snippet
---
---@param snippet_body string|table Snippet body as string or array of strings.
---   Should follow |MiniSnippets-syntax-specification|.
---@param opts table|nil Options. Possible fields:
---   - <normalize> `(boolean)` - whether to normalize nodes:
---     - Evaluate variable nodes and add output as a `text` field.
---       If variable is not set, `text` field is `nil`.
---       Values from `opts.lookup` are preferred over evaluation output.
---       See |MiniSnippets-syntax-specification| for more info about variables.
---     - Add `text` field for tabstops present in `opts.lookup`.
---     - Ensure every node contains exactly one of `text` or `placeholder` fields.
---       If there are none, add default `placeholder` (one text node with first
---       choice or empty string). If there are both, remove `placeholder` field.
---     - Ensure present final tabstop: append to end if absent.
---     - Ensure that nodes for same tabstop have same placeholder. Use the one
---       from the first node.
---     Default: `false`.
---   - <lookup> `(table)` - map from variable/tabstop (string) name to its value.
---     Default: `{}`.
---
---@return table Array of nodes. Node is a table with fields depending on node type:
---   - Text node:
---     - <text> `(string)` - node's text.
---   - Tabstop node:
---     - <tabstop> `(string)` - tabstop identifier.
---     - <text> `(string|nil)` - tabstop value (if present in <lookup>).
---     - <placeholder> `(table|nil)` - array of nodes to be used as placeholder.
---     - <choices> `(table|nil)` - array of string choices.
---     - <transform> `(table|nil)` - array of transformation string parts.
---   - Variable node:
---     - <var> `(string)` - variable name.
---     - <text> `(string|nil)` - variable value.
---     - <placeholder> `(table|nil)` - array of nodes to be used as placeholder.
---     - <transform> `(table|nil)` - array of transformation string parts.
MiniSnippets.parse = function(snippet_body, opts)
  if H.is_array_of(snippet_body, H.is_string) then snippet_body = table.concat(snippet_body, '\n') end
  if type(snippet_body) ~= 'string' then H.error('Snippet body should be string or array of strings') end

  opts = vim.tbl_extend('force', { normalize = false, lookup = {} }, opts or {})

  -- Overall idea: implement a state machine which updates on every character.
  -- This leads to a bit spaghetti code, but doesn't require `vim.lpeg` DSL
  -- knowledge and can provide more information in error messages.
  -- Output is array of nodes representing the snippet body.
  -- Format is mostly based on grammar in LSP spec 3.18 with small differences.

  -- State table. Each future string is tracked as array and merged later.
  --stylua: ignore
  local state = {
    name = 'text',
    -- Node array for depths of currently processed nested placeholders.
    -- Depth 1 is the original snippet.
    depth_arrays = { { { text = {} } } },
    set_name = function(self, name) self.name = name; return self end,
    add_node = function(self, node) table.insert(self.depth_arrays[#self.depth_arrays], node); return self end,
    set_in = function(self, node, field, value) node[field] = value; return self end,
    is_not_top_level = function(self) return #self.depth_arrays > 1 end,
  }

  for i = 0, vim.fn.strchars(snippet_body) - 1 do
    -- Infer helper data (for more concise manipulations inside processor)
    local depth = #state.depth_arrays
    local arr = state.depth_arrays[depth]
    local processor, node = H.parse_processors[state.name], arr[#arr]
    processor(vim.fn.strcharpart(snippet_body, i, 1), state, node)
  end

  -- Verify, post-process, normalize
  H.parse_verify(state)
  local nodes = H.parse_post_process(state.depth_arrays[1], state.name)
  return opts.normalize and H.parse_normalize(nodes, opts) or nodes
end

--- Start completion LSP server
---
--- This starts (|vim.lsp.start()|) an LSP server with the purpose of displaying
--- snippets in (auto)completion engines (|mini.completion| in particular).
--- The server:
--- - Only implements `textDocument/completion` method which prepares and matches
---   snippets at cursor (via |MiniSnippets.expand()|).
--- - Auto-attaches to all loaded buffers by default.
---
---@param opts table|nil Options. Possible fields:
---   - <before_attach> `(function)` - function executed before every attach to
---     the buffer. Takes buffer id as input and can return `false` (not `nil`) to
---     cancel attaching to the buffer. Default: attach to loaded normal buffers.
---   - <match> `(false|function)` - value of `opts.match` forwarded to
---     the |MiniSnippets.expand()| when computing completion candidates.
---     Supply `false` to not do matching at cursor, return all available snippets
---     in cursor context, and rely on completion engine to match and sort items.
---     Default: `nil` (equivalent to |MiniSnippets.default_match()|).
---   - <server_config> `(table)` - server config to be used as basis for first
---     argument to |vim.lsp.start()| (`cmd` will be overridden). Default: `{}`.
---   - <triggers> `(table)` - array of trigger characters to be used as
---     `completionProvider.triggerCharacters` server capability. Default: `{}`.
---
---@return integer|nil Identifier of started LSP server.
MiniSnippets.start_lsp_server = function(opts)
  local default_opts = { before_attach = H.lsp_default_before_attach, match = nil, server_config = {}, triggers = {} }
  opts = vim.tbl_extend('force', default_opts, opts or {})
  H.check_type('opts.before_attch', opts.before_attach, 'callable')
  H.check_type('opts.server_config', opts.server_config, 'table')
  H.check_type('opts.triggers', opts.triggers, 'table')

  local config = vim.deepcopy(opts.server_config)
  -- NOTE: set `root_dir` for a working `reuse_client` on Neovim<0.11
  config.name, config.root_dir = config.name or 'mini.snippets', config.root_dir or vim.fn.getcwd()
  config.cmd = H.lsp_make_cmd(opts)
  local ok, client_id = pcall(vim.lsp.start, config, { attach = false })
  if not (ok and type(client_id) == 'number') then H.error("Could not start 'mini.snippets' in-process LSP server") end
  if vim.fn.has('nvim-0.11') == 0 then pcall(vim.lsp.buf_detach_client, 0, client_id) end

  local attach = function(buf_id)
    if not vim.api.nvim_buf_is_valid(buf_id) or opts.before_attach(buf_id) == false then return end
    vim.lsp.buf_attach_client(buf_id, client_id)
  end
  for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
    attach(buf_id)
  end

  local gr = vim.api.nvim_create_augroup('MiniSnippetsLsp', {})
  -- NOTE: schedule to auto-attach only on explicit buffer ente (not temporary
  -- from script) and have buffer properties (like 'filetype') set up.
  local auto_attach = vim.schedule_wrap(function(ev)
    if ev.buf ~= vim.api.nvim_get_current_buf() then return end
    attach(ev.buf)
  end)
  vim.api.nvim_create_autocmd('BufEnter', { callback = auto_attach, desc = "Auto attach 'mini.snippets' LSP server" })

  return client_id
end

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniSnippets.config)

-- Namespaces for extmarks
H.ns_id = {
  nodes = vim.api.nvim_create_namespace('MiniSnippetsNodes'),
}

-- Array of current (nested) snippet sessions from `default_insert`
H.sessions = {}

-- Various cache
H.cache = {
  -- Loaders output
  runtime = {},
  file = {},
  -- Data for possibly overridden session mappings
  mappings = {},
}

-- Capabilties of current Neovim version
H.nvim_supports_inline_extmarks = vim.fn.has('nvim-0.10') == 1

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  H.check_type('snippets', config.snippets, 'table')

  H.check_type('mappings', config.mappings, 'table')
  H.check_type('mappings.expand', config.mappings.expand, 'string')
  H.check_type('mappings.jump_next', config.mappings.jump_next, 'string')
  H.check_type('mappings.jump_prev', config.mappings.jump_prev, 'string')
  H.check_type('mappings.stop', config.mappings.stop, 'string')

  H.check_type('expand', config.expand, 'table')
  H.check_type('expand.prepare', config.expand.prepare, 'function', true)
  H.check_type('expand.match', config.expand.match, 'function', true)
  H.check_type('expand.select', config.expand.select, 'function', true)
  H.check_type('expand.insert', config.expand.insert, 'function', true)

  return config
end

H.apply_config = function(config)
  MiniSnippets.config = config

  -- Reset loader cache
  H.cache = { runtime = {}, file = {}, mappings = {} }

  -- Make mappings
  local mappings = config.mappings
  local map = function(lhs, rhs, desc)
    if lhs == '' then return end
    vim.keymap.set('i', lhs, rhs, { desc = desc })
  end
  map(mappings.expand, '<Cmd>lua MiniSnippets.expand()<CR>', 'Expand snippet')

  -- Register 'code-snippets' extension as JSON (helps with highlighting)
  vim.schedule(function() vim.filetype.add({ extension = { ['code-snippets'] = 'json' } }) end)
end

H.create_autocommands = function()
  local gr = vim.api.nvim_create_augroup('MiniSnippets', {})

  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = gr, pattern = pattern, callback = callback, desc = desc })
  end

  au('ColorScheme', '*', H.create_default_hl, 'Ensure colors')

  -- Clean up invalid sessions (i.e. which have outdated or corrupted data)
  -- - Use `vim.schedule_wrap` to make it work with `:edit` command
  au('BufUnload', '*', vim.schedule_wrap(H.clean_sessions), 'Clean sessions stack')
end

H.create_default_hl = function()
  local hi_link_underdouble = function(to, from)
    local data = vim.api.nvim_get_hl(0, { name = from, link = false })
    data.default = true
    data.underdouble, data.underline, data.undercurl, data.underdotted, data.underdashed =
      true, false, false, false, false
    data.cterm = { underdouble = true }
    data.fg, data.bg, data.ctermfg, data.ctermbg = 'NONE', 'NONE', 'NONE', 'NONE'
    vim.api.nvim_set_hl(0, to, data)
  end
  hi_link_underdouble('MiniSnippetsCurrent', 'DiagnosticUnderlineWarn')
  hi_link_underdouble('MiniSnippetsCurrentReplace', 'DiagnosticUnderlineError')
  hi_link_underdouble('MiniSnippetsFinal', 'DiagnosticUnderlineOk')
  hi_link_underdouble('MiniSnippetsUnvisited', 'DiagnosticUnderlineHint')
  hi_link_underdouble('MiniSnippetsVisited', 'DiagnosticUnderlineInfo')
end

H.is_disabled = function() return vim.g.minisnippets_disable == true or vim.b.minisnippets_disable == true end

H.get_config = function()
  local global, buf = MiniSnippets.config, vim.b.minisnippets_config
  -- Fast path for most common case
  if buf == nil then return vim.deepcopy(global) end
  -- Manually reconstruct to allow snippet array to be concatenated
  buf = buf or {}
  return {
    snippets = vim.list_extend(vim.deepcopy(global.snippets), buf.snippets or {}),
    mappings = vim.tbl_extend('force', global.mappings, buf.mappings or {}),
    expand = vim.tbl_extend('force', global.expand, buf.expand or {}),
  }
end

-- Read -----------------------------------------------------------------------
H.file_readers = {}

H.file_readers.lua = function(path, silent)
  local ok, contents = pcall(dofile, path)
  if not ok then return { problems = { 'Could not execute Lua file' } } end
  if type(contents) ~= 'table' then return { problems = { 'Returned object is not a table' } } end
  return H.read_snippet_data(contents)
end

H.file_readers.json = function(path, silent)
  local file = io.open(path)
  if file == nil then return { problems = { 'Could not open file' } } end
  local raw = file:read('*all')
  file:close()

  local ok, contents = pcall(vim.json.decode, raw)
  if not (ok and type(contents) == 'table') then
    local msg = ok and 'Object is not a dictionary or array' or contents
    return { problems = { 'File does not contain a valid JSON object. Reason: ' .. msg } }
  end

  return H.read_snippet_data(contents)
end

H.file_readers['code-snippets'] = H.file_readers.json

H.read_snippet_data = function(contents)
  local res, problems = {}, {}
  for name, t in pairs(contents) do
    if H.is_snippet(t) then
      -- Try inferring description from dict's field (if appropriate)
      if type(name) == 'string' and (t.desc == nil and t.description == nil) then t.desc = name end
      table.insert(res, t)
    elseif vim.is_callable(t) then
      -- Allow entries to be functions (relevant for Lua files)
      table.insert(res, t)
    else
      table.insert(problems, 'The following is not a valid snippet data:\n' .. vim.inspect(t))
    end
  end
  return { snippets = res, problems = problems }
end

-- Context snippets -----------------------------------------------------------
H.get_default_context = function()
  local buf_id = vim.api.nvim_get_current_buf()

  -- TODO: Remove `opts.error` after compatibility with Neovim=0.11 is dropped
  local has_parser, parser = pcall(vim.treesitter.get_parser, buf_id, nil, { error = false })
  if not has_parser or parser == nil then return { buf_id = buf_id, lang = vim.bo[buf_id].filetype } end

  -- Compute local (at cursor) TS language
  local pos = vim.api.nvim_win_get_cursor(0)
  local lang_tree = parser:language_for_range({ pos[1] - 1, pos[2], pos[1] - 1, pos[2] })
  local lang = lang_tree:lang() or vim.bo[buf_id].filetype
  return { buf_id = buf_id, lang = lang }
end

H.traverse_raw_snippets = function(x, target, context)
  if H.is_snippet(x) then
    local body
    if x.body ~= nil then body = type(x.body) == 'string' and x.body or table.concat(x.body, '\n') end

    local desc = x.desc or x.description or body
    if desc ~= nil then desc = type(desc) == 'string' and desc or table.concat(desc, '\n') end

    local prefix = x.prefix or ''
    prefix = type(prefix) == 'string' and { prefix } or prefix

    for _, pr in ipairs(prefix) do
      -- Add snippets with empty prefixes separately
      local index = pr == '' and (#target + 1) or pr
      -- Allow absent `body` to result in completely removing prefix(es)
      target[index] = body ~= nil and { prefix = pr, body = body, desc = desc } or nil
    end
  end

  if H.islist(x) then
    for _, v in ipairs(x) do
      H.traverse_raw_snippets(v, target, context)
    end
  end

  if vim.is_callable(x) then H.traverse_raw_snippets(x(context), target, context) end
end

-- Expand ---------------------------------------------------------------------
H.make_extended_insert = function(insert)
  return function(snippet)
    if snippet == nil then return end

    -- Ensure Insert mode. This helps to properly position cursor at EOL.
    H.call_in_insert_mode(function()
      -- Delete snippet's region and remove the data from the snippet (as it
      -- wouldn't need to be removed and will represent outdated information)
      H.delete_region(snippet.region)
      snippet = vim.deepcopy(snippet)
      snippet.region = nil

      -- Insert snippet at cursor
      insert(snippet)
    end)
  end
end

-- Parse ----------------------------------------------------------------------
H.parse_verify = function(state)
  if state.name == 'dollar_lbrace' then H.error('"${" should be closed with "}"') end
  if state.name == 'choice' then H.error('Tabstop with choices should be closed with "|}"') end
  if vim.startswith(state.name, 'transform_') then
    H.error('Transform should contain 3 "/" outside of `${...}` and be closed with "}"')
  end
  if #state.depth_arrays > 1 then H.error('Placeholder should be closed with "}"') end
end

H.parse_post_process = function(node_arr, state_name)
  -- Allow "$" at the end of the snippet
  if state_name == 'dollar' then table.insert(node_arr, { text = { '$' } }) end

  -- Process
  local traverse
  traverse = function(arr)
    for _, node in ipairs(arr) do
      -- Clean up trailing `\`
      if node.after_slash and node.text ~= nil then table.insert(node.text, '\\') end
      node.after_slash = nil

      -- Convert arrays to strings
      if node.text then node.text = table.concat(node.text) end
      if node.tabstop then node.tabstop = table.concat(node.tabstop) end
      if node.choices then node.choices = vim.tbl_map(table.concat, node.choices) end
      if node.var then node.var = table.concat(node.var) end
      if node.transform then node.transform = vim.tbl_map(table.concat, node.transform) end

      -- Recursively post-process placeholders
      if node.placeholder ~= nil then node.placeholder = traverse(node.placeholder) end
    end
    arr = vim.tbl_filter(function(n) return n.text == nil or (n.text ~= nil and n.text:len() > 0) end, arr)
    if #arr == 0 then return { { text = '' } } end
    return arr
  end

  return traverse(node_arr)
end

H.parse_normalize = function(node_arr, opts)
  local lookup = {}
  for key, val in pairs(opts.lookup) do
    if type(key) == 'string' then lookup[key] = tostring(val) end
  end

  local has_final_tabstop = false
  local normalize = function(n)
    -- Evaluate variable
    local var_value
    if n.var ~= nil then var_value = H.parse_eval_var(n.var, lookup) end
    if type(var_value) == 'string' then n.text = var_value end

    -- Look up tabstop
    if n.tabstop ~= nil then n.text = lookup[n.tabstop] end

    -- Ensure text-or-placeholder (use first choice for choice node)
    if n.text == nil and n.placeholder == nil then n.placeholder = { { text = (n.choices or {})[1] or '' } } end
    if n.text ~= nil and n.placeholder ~= nil then n.placeholder = nil end

    -- Track presence of final tabstop
    has_final_tabstop = has_final_tabstop or n.tabstop == '0'
  end
  -- - Ensure proper random random variables
  math.randomseed(vim.loop.hrtime())
  H.nodes_traverse(node_arr, normalize)

  -- Possibly append final tabstop as a regular normalized tabstop
  if not has_final_tabstop then table.insert(node_arr, { tabstop = '0', placeholder = { { text = '' } } }) end

  -- Ensure same resolved text in linked tabstops
  local tabstop_ref = {}
  local sync_linked_tabstops = function(n)
    if n.tabstop == nil then return end
    local ref = tabstop_ref[n.tabstop]
    if ref ~= nil then
      -- Set data for repeated tabstops. Do not sync transforms (for future).
      n.text, n.placeholder, n.choices = ref.text, vim.deepcopy(ref.placeholder), vim.deepcopy(ref.choices)
      return
    end
    -- Compute reference data for repeated tabstops
    if n.placeholder ~= nil and H.parse_nodes_contain_tabstop(n.placeholder, n.tabstop) then
      H.error('Placeholder can not contain its tabstop')
    end
    tabstop_ref[n.tabstop] = { text = n.text, placeholder = n.placeholder, choices = n.choices }
  end
  H.nodes_traverse(node_arr, sync_linked_tabstops)

  return node_arr
end

H.parse_nodes_contain_tabstop = function(node_arr, tabstop)
  for _, n in ipairs(node_arr) do
    if n.tabstop == tabstop then return true end
    if n.placeholder ~= nil and H.parse_nodes_contain_tabstop(n.placeholder, tabstop) then return true end
  end
  return false
end

H.parse_get_text = function(node_arr)
  local parts = {}
  for _, n in ipairs(node_arr) do
    table.insert(parts, n.text or H.parse_get_text(n.placeholder))
  end
  return table.concat(parts, '')
end

H.parse_rise_depth = function(state)
  -- Set the deepest array as a placeholder of the last node in previous layer.
  -- This can happen only after `}` which does not close current node.
  local depth = #state.depth_arrays
  local cur_layer, prev_layer = state.depth_arrays[depth], state.depth_arrays[depth - 1]
  prev_layer[#prev_layer].placeholder = vim.deepcopy(cur_layer)
  state.depth_arrays[depth] = nil
  state:add_node({ text = {} }):set_name('text')
end

-- Each method processes single character based on the character (`c`),
-- state (`s`), and current node (`n`).
H.parse_processors = {}

H.parse_processors.text = function(c, s, n)
  if n.after_slash then
    -- Escape `$}\` and allow unescaped '\\' to preceed any character
    if not (c == '$' or c == '}' or c == '\\') then table.insert(n.text, '\\') end
    n.text[#n.text + 1], n.after_slash = c, nil
    return
  end
  if c == '}' and s:is_not_top_level() then return H.parse_rise_depth(s) end
  if c == '\\' then return s:set_in(n, 'after_slash', true) end
  if c == '$' then return s:set_name('dollar') end
  table.insert(n.text, c)
end

H.parse_processors.dollar = function(c, s, n)
  if c == '}' and s:is_not_top_level() then
    if n.text ~= nil then table.insert(n.text, '$') end
    if n.text == nil then s:add_node({ text = { '$' } }) end
    s:set_name('text')
    H.parse_rise_depth(s)
    return
  end

  if c:find('^[0-9]$') then return s:add_node({ tabstop = { c } }):set_name('dollar_tabstop') end -- Tabstops
  if c:find('^[_a-zA-Z]$') then return s:add_node({ var = { c } }):set_name('dollar_var') end -- Variables
  if c == '{' then return s:set_name('dollar_lbrace') end -- Cases of `${...}`
  table.insert(n.text, '$') -- Case of unescaped `$`
  if c == '$' then return end -- Case of `$$1` and `$${1}`
  table.insert(n.text, c)
  s:set_name('text')
end

H.parse_processors.dollar_tabstop = function(c, s, n)
  if c:find('^[0-9]$') then return table.insert(n.tabstop, c) end
  if c == '}' and s:is_not_top_level() then return H.parse_rise_depth(s) end
  local new_node = { text = {} }
  s:add_node(new_node)
  if c == '$' then return s:set_name('dollar') end -- Case of `$1$2` and `$1$a`
  s:set_name('text')
  if c == '\\' then return s:set_in(new_node, 'after_slash', true) end -- Case of `${1:{$2\}}`
  table.insert(new_node.text, c) -- Case of `$1a`
end

H.parse_processors.dollar_var = function(c, s, n)
  if c:find('^[_a-zA-Z0-9]$') then return table.insert(n.var, c) end
  if c == '}' and s:is_not_top_level() then return H.parse_rise_depth(s) end
  local new_node = { text = {} }
  s:add_node(new_node)
  if c == '$' then return s:set_name('dollar') end -- Case of `$a$b` and `$a$1`
  s:set_name('text')
  if c == '\\' then return s:set_in(new_node, 'after_slash', true) end -- Case of `${AAA:{$1\}}`
  table.insert(new_node.text, c) -- Case of `$a-`
end

H.parse_processors.dollar_lbrace = function(c, s, n)
  if n.tabstop == nil and n.var == nil then -- Detect the type of `${...}`
    if c:find('^[0-9]$') then return s:add_node({ tabstop = { c } }) end
    if c:find('^[_a-zA-Z]$') then return s:add_node({ var = { c } }) end
    H.error('`${` should be followed by digit (in tabstop) or letter/underscore (in variable), not ' .. vim.inspect(c))
  end
  if c == '}' then return s:add_node({ text = {} }):set_name('text') end -- Cases of `${1}` and `${a}`
  if c == ':' then -- Placeholder
    table.insert(s.depth_arrays, { { text = {} } })
    return s:set_name('text')
  end
  if c == '/' then return s:set_in(n, 'transform', { {}, {}, {} }):set_name('transform_regex') end -- Transform
  if n.var ~= nil then -- Variable
    if c:find('^[_a-zA-Z0-9]$') then return table.insert(n.var, c) end
    H.error('Variable name should be followed by "}", ":" or "/", not ' .. vim.inspect(c))
  else -- Tabstop
    if c:find('^[0-9]$') then return table.insert(n.tabstop, c) end
    if c == '|' then return s:set_name('choice') end
    H.error('Tabstop id should be followed by "}", ":", "|", or "/" not ' .. vim.inspect(c))
  end
end

H.parse_processors.choice = function(c, s, n)
  n.choices = n.choices or { {} }
  if n.after_bar then
    if c ~= '}' then H.error('Tabstop with choices should be closed with "|}"') end
    return s:set_in(n, 'after_bar', nil):add_node({ text = {} }):set_name('text')
  end

  local cur = n.choices[#n.choices]
  if n.after_slash then
    -- Escape `$}\` and allow unescaped '\\' to preceed any character
    if not (c == ',' or c == '|' or c == '\\') then table.insert(cur, '\\') end
    cur[#cur + 1], n.after_slash = c, nil
    return
  end
  if c == ',' then return table.insert(n.choices, {}) end
  if c == '\\' then return s:set_in(n, 'after_slash', true) end
  if c == '|' then return s:set_in(n, 'after_bar', true) end
  table.insert(cur, c)
end

-- Silently gather all the transform data and wait until proper `}`
H.parse_processors.transform_regex = function(c, s, n)
  table.insert(n.transform[1], c)
  if n.after_slash then return s:set_in(n, 'after_slash', nil) end
  if c == '\\' then return s:set_in(n, 'after_slash', true) end
  if c == '/' then return s:set_in(n.transform[1], #n.transform[1], nil):set_name('transform_format') end -- Assumes any `/` is escaped in regex
end

H.parse_processors.transform_format = function(c, s, n)
  table.insert(n.transform[2], c)
  if n.after_slash then return s:set_in(n, 'after_slash', nil) end
  if n.after_dollar then
    n.after_dollar = nil
    -- Inside `${}` wait until the first (unescaped) `}`. Techincally, this
    -- breaks LSP spec in `${1:?if:else}` (`if` doesn't have to escape `}`).
    -- Accept this as known limitation and ask to escape `}` in such cases.
    if c == '{' and not n.inside_braces then return s:set_in(n, 'inside_braces', true) end
  end
  if c == '\\' then return s:set_in(n, 'after_slash', true) end
  if c == '$' then return s:set_in(n, 'after_dollar', true) end
  if c == '}' and n.inside_braces then return s:set_in(n, 'inside_braces', nil) end
  if c == '/' and not n.inside_braces then
    return s:set_in(n.transform[2], #n.transform[2], nil):set_name('transform_options')
  end
end

H.parse_processors.transform_options = function(c, s, n)
  table.insert(n.transform[3], c)
  if n.after_slash then return s:set_in(n, 'after_slash', nil) end
  if c == '\\' then return s:set_in(n, 'after_slash', true) end
  if c == '}' then return s:set_in(n.transform[3], #n.transform[3], nil):add_node({ text = {} }):set_name('text') end
end

--stylua: ignore
H.parse_eval_var = function(var, lookup)
  -- Always prefer using lookup
  if lookup[var] ~= nil then return lookup[var] end

  -- Evaluate variable
  local value
  if H.var_evaluators[var] ~= nil then value = H.var_evaluators[var]() end
  -- - Fall back to environment variable or `-1` to not evaluate twice
  if value == nil then value = vim.loop.os_getenv(var) or -1 end

  -- Skip caching random variables (to allow several different in one snippet)
  if not (var == 'RANDOM' or var == 'RANDOM_HEX' or var == 'UUID') then lookup[var] = value end
  return value
end

--stylua: ignore
H.var_evaluators = {
  -- LSP
  TM_SELECTED_TEXT = function() return table.concat(vim.fn.getreg('"', true, true), '\n') end,
  TM_CURRENT_LINE  = function() return vim.api.nvim_get_current_line() end,
  TM_CURRENT_WORD  = function() return vim.fn.expand('<cword>') end,
  TM_LINE_INDEX    = function() return tostring(vim.fn.line('.') - 1) end,
  TM_LINE_NUMBER   = function() return tostring(vim.fn.line('.')) end,
  TM_FILENAME      = function() return vim.fn.expand('%:t') end,
  TM_FILENAME_BASE = function() return vim.fn.expand('%:t:r') end,
  TM_DIRECTORY     = function() return vim.fn.expand('%:p:h') end,
  TM_FILEPATH      = function() return vim.fn.expand('%:p') end,

  -- VS Code
  CLIPBOARD         = function() return vim.fn.getreg('+') end,
  CURSOR_INDEX      = function() return tostring(vim.fn.col('.') - 1) end,
  CURSOR_NUMBER     = function() return tostring(vim.fn.col('.')) end,
  RELATIVE_FILEPATH = function() return vim.fn.expand('%:.') end,
  WORKSPACE_FOLDER  = function() return vim.fn.getcwd() end,

  LINE_COMMENT      = function() return vim.bo.commentstring:gsub('%s*%%s.*$', '') end,
  -- No BLOCK_COMMENT_{START,END} as there is no built-in way to get them

  CURRENT_YEAR             = function() return vim.fn.strftime('%Y') end,
  CURRENT_YEAR_SHORT       = function() return vim.fn.strftime('%y') end,
  CURRENT_MONTH            = function() return vim.fn.strftime('%m') end,
  CURRENT_MONTH_NAME       = function() return vim.fn.strftime('%B') end,
  CURRENT_MONTH_NAME_SHORT = function() return vim.fn.strftime('%b') end,
  CURRENT_DATE             = function() return vim.fn.strftime('%d') end,
  CURRENT_DAY_NAME         = function() return vim.fn.strftime('%A') end,
  CURRENT_DAY_NAME_SHORT   = function() return vim.fn.strftime('%a') end,
  CURRENT_HOUR             = function() return vim.fn.strftime('%H') end,
  CURRENT_MINUTE           = function() return vim.fn.strftime('%M') end,
  CURRENT_SECOND           = function() return vim.fn.strftime('%S') end,
  CURRENT_TIMEZONE_OFFSET  = function() return vim.fn.strftime('%z') end,

  CURRENT_SECONDS_UNIX = function() return tostring(os.time()) end,

  -- Random
  RANDOM     = function() return string.format('%06d', math.random(0, 999999)) end,
  RANDOM_HEX = function() return string.format('%06x', math.random(0, 16777216 - 1)) end,
  UUID       = function()
    -- Source: https://gist.github.com/jrus/3197011
    local template ='xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return string.gsub(template, '[xy]', function (c)
      local v = c == 'x' and math.random(0, 0xf) or math.random(8, 0xb)
      return string.format('%x', v)
    end)
  end
}

-- Session --------------------------------------------------------------------
H.get_active_session = function() return H.sessions[#H.sessions] end

H.session_new = function(nodes, snippet, opts)
  -- Compute all present tabstops in session traverse order
  local taborder = H.compute_tabstop_order(nodes)
  local tabstops = {}
  for i, id in ipairs(taborder) do
    tabstops[id] =
      { prev = taborder[i - 1] or taborder[#taborder], next = taborder[i + 1] or taborder[1], is_visited = false }
  end

  return {
    buf_id = vim.api.nvim_get_current_buf(),
    cur_tabstop = taborder[1],
    extmark_id = H.extmark_new(0, vim.fn.line('.') - 1, vim.fn.col('.') - 1),
    insert_args = vim.deepcopy({ snippet = snippet, opts = opts }),
    nodes = nodes,
    ns_id = H.ns_id.nodes,
    tabstops = tabstops,
  }
end

H.session_init = function(session, full)
  if session == nil then return end
  local buf_id = session.buf_id

  -- Prepare
  if full then
    -- Set buffer text preserving snippet text relative indent
    local indent = H.get_indent(vim.fn.getline('.'):sub(1, vim.fn.col('.') - 1))
    H.nodes_set_text(buf_id, session.nodes, session.extmark_id, indent)

    -- No session if no input needed: single final tabstop without placeholder
    if session.cur_tabstop == '0' then
      local ref_node = H.session_get_ref_node(session)
      local row, col, opts = H.extmark_get(buf_id, ref_node.extmark_id)
      local is_empty = row == opts.end_row and col == opts.end_col
      if is_empty then
        -- Clean up
        H.nodes_traverse(session.nodes, function(n) H.extmark_del(buf_id, n.extmark_id) end)
        H.extmark_del(buf_id, session.extmark_id)
        return H.set_cursor({ row + 1, col })
      end
    end

    -- Register new session
    local cur_session = H.get_active_session()
    if cur_session ~= nil then
      -- Sync before deinit to allow removing current placeholder
      H.session_sync_current_tabstop(cur_session)
      H.session_deinit(cur_session, false)
    end
    table.insert(H.sessions, session)

    -- Focus on the current tabstop
    H.session_tabstop_focus(session, session.cur_tabstop)

    -- Possibly set behavior for all sessions
    H.track_sessions()
    H.map_in_sessions()
  else
    -- Sync current tabstop for resumed session. This is useful when nested
    -- session was done inside reference tabstop node (most common case).
    -- On purpose don't change cursor/buffer/focus to allow smoother typing.
    H.session_sync_current_tabstop(session)
    H.session_update_hl(session)
    H.session_ensure_gravity(session)
  end

  -- Trigger proper event
  H.trigger_event('MiniSnippetsSession' .. (full and 'Start' or 'Resume'), { session = vim.deepcopy(session) })
end

H.track_sessions = function()
  -- Create tracking autocommands only once for all nested sessions
  if #H.sessions > 1 then return end
  local gr = vim.api.nvim_create_augroup('MiniSnippetsTrack', { clear = true })

  -- React to text changes. NOTE: Use 'TextChangedP' to update linked tabstops
  -- with visible popup. It has downsides though:
  -- - Placeholder is removed after selecting first choice. Together with
  --   showing choices in empty tabstops, feels like a good compromise.
  -- - Tabstop sync runs more frequently (especially with 'mini.completion'),
  --   because of how built-in completion constantly 'delete-add' completion
  --   leader text (which is treated as text change).
  local on_textchanged = function(args)
    local session, buf_id = H.get_active_session(), args.buf
    -- React only to text changes in session's buffer for performance
    if session.buf_id ~= buf_id then return end
    -- Ensure that session is valid, like no extmarks got corrupted
    if not H.session_is_valid(session) then
      H.notify('Session contains corrupted data (deleted or out of range extmarks). It is stopped.', 'WARN')
      return MiniSnippets.session.stop()
    end
    H.session_sync_current_tabstop(session)
  end
  local text_events = { 'TextChanged', 'TextChangedI', 'TextChangedP' }
  vim.api.nvim_create_autocmd(text_events, { group = gr, callback = on_textchanged, desc = 'React to text change' })

  -- Stop if final tabstop is current: exit to Normal mode or *any* text change
  local latest_changedtick = vim.b.changedtick
  local stop_if_final = function(args)
    -- *Actual* text change check is a workaround for `TextChangedI` sometimes
    -- getting triggered unnecessarily and too late with built-in completion
    if vim.b.changedtick == latest_changedtick and args.event ~= 'ModeChanged' then return end
    latest_changedtick = vim.b.changedtick

    -- React only on text changes in session's buffer
    local session, buf_id = H.get_active_session(), args.buf
    if not ((session or {}).buf_id == buf_id and session.cur_tabstop == '0') then return end

    -- Stop without forcing to hide completion
    H.cache.stop_is_auto = true
    MiniSnippets.session.stop()
    H.cache.stop_is_auto = nil
  end
  local modechanged_opts = { group = gr, pattern = '*:n', callback = stop_if_final, desc = 'Stop on final tabstop' }
  vim.api.nvim_create_autocmd('ModeChanged', modechanged_opts)
  vim.api.nvim_create_autocmd(text_events, { group = gr, callback = stop_if_final, desc = 'Stop on final tabstop' })
end

H.clean_sessions = function()
  for i = #H.sessions - 1, 1, -1 do
    if not H.session_is_valid(H.sessions[i]) then
      H.session_deinit(H.sessions[i], true)
      table.remove(H.sessions, i)
    end
  end
  if #H.sessions > 0 and not H.session_is_valid(H.get_active_session()) then MiniSnippets.session.stop() end
end

H.map_in_sessions = function()
  -- Create mapping only once for all nested sessions
  if #H.sessions > 1 then return end
  local mappings = H.get_config().mappings
  local map_with_cache = function(lhs, call, desc)
    if lhs == '' then return end
    H.cache.mappings[lhs] = vim.fn.maparg(lhs, 'i', false, true)
    -- NOTE: Map globally to work in nested sessions in different buffers
    vim.keymap.set('i', lhs, '<Cmd>lua MiniSnippets.session.' .. call .. '<CR>', { desc = desc })
  end
  map_with_cache(mappings.jump_next, 'jump("next")', 'Jump to next snippet tabstop')
  map_with_cache(mappings.jump_prev, 'jump("prev")', 'Jump to previous snippet tabstop')
  map_with_cache(mappings.stop, 'stop()', 'Stop active snippet session')
end

H.unmap_in_sessions = function()
  for lhs, data in pairs(H.cache.mappings) do
    local needs_restore = vim.tbl_count(data) > 0
    if needs_restore then vim.fn.mapset('i', false, data) end
    if not needs_restore then vim.keymap.del('i', lhs) end
  end
  H.cache.mappings = {}
end

H.session_tabstop_focus = function(session, tabstop_id)
  session.cur_tabstop = tabstop_id
  session.tabstops[tabstop_id].is_visited = true

  -- Ensure target buffer is current
  H.ensure_cur_buf(session.buf_id)

  -- Update highlighting
  H.session_update_hl(session)

  -- Ensure proper gravity as reference node has changed
  H.session_ensure_gravity(session)

  -- Set cursor based on reference node: left side if there is placeholder (and
  -- will be replaced), right side otherwise (to append).
  local ref_node = H.session_get_ref_node(session)
  local row, col, end_row, end_col = H.extmark_get_range(session.buf_id, ref_node.extmark_id)
  local pos = ref_node.placeholder ~= nil and { row + 1, col } or { end_row + 1, end_col }
  H.set_cursor(pos)

  -- Show choices: if present and match node text (or all if still placeholder)
  H.show_completion(ref_node.choices, col + 1)
end

H.session_ensure_gravity = function(session)
  -- Ensure proper gravity relative to reference node (first node with current
  -- tabstop): "left" before, "expand" at and all its parents, "right" after.
  -- This accounts for typing in snippets like `$1$2$1$2$1` (in both 1 and 2)
  -- and correct tracking of $2 in `${2:$1}` (should expand if typing in 1).
  local buf_id, cur_tabstop, base_gravity = session.buf_id, session.cur_tabstop, 'left'
  local parent_extmarks = {}
  local ensure = function(n)
    local is_ref_node = n.tabstop == cur_tabstop and base_gravity == 'left'
    if is_ref_node then
      for _, extmark_id in ipairs(parent_extmarks) do
        H.extmark_set_gravity(buf_id, extmark_id, 'expand')
      end
      -- Disable parent stack tracking, as reference node is accounted for
      parent_extmarks = nil
    end
    H.extmark_set_gravity(buf_id, n.extmark_id, is_ref_node and 'expand' or base_gravity)
    base_gravity = (is_ref_node or base_gravity == 'right') and 'right' or 'left'
  end

  local ensure_in_nodes
  ensure_in_nodes = function(nodes)
    for _, n in ipairs(nodes) do
      -- NOTE: apply first to the node and only later to placeholder nodes,
      -- which makes them have "right" gravity and thus being removable during
      -- replacing placeholder (as they will not cover newly inserted text).
      ensure(n)
      if n.placeholder ~= nil then
        if parent_extmarks ~= nil then table.insert(parent_extmarks, n.extmark_id) end
        ensure_in_nodes(n.placeholder)
        if parent_extmarks ~= nil then parent_extmarks[#parent_extmarks] = nil end
      end
    end
  end
  ensure_in_nodes(session.nodes)
end

H.session_get_ref_node = function(session)
  local res, cur_tabstop = nil, session.cur_tabstop
  local find = function(n) res = res or (n.tabstop == cur_tabstop and n or nil) end
  H.nodes_traverse(session.nodes, find)
  return res
end

H.session_is_valid = function(session)
  local buf_id = session.buf_id
  if not H.is_loaded_buf(buf_id) then return false end
  local res, f, n_lines = true, nil, vim.api.nvim_buf_line_count(buf_id)
  f = function(n)
    -- NOTE: Invalid extmark tracking (via `invalidate=true`) should be doable,
    -- but comes with constraints: manually making tabstop empty should be
    -- allowed; deleting placeholder also deletes extmark's range. Both make
    -- extmark invalid, so deligate to users to see that extmarks are broken.
    local ok, row, _, _ = pcall(H.extmark_get, buf_id, n.extmark_id)
    res = res and (ok and row < n_lines)
  end
  H.nodes_traverse(session.nodes, f)
  return res
end

H.session_sync_current_tabstop = function(session)
  if session._no_sync then return end

  local buf_id, ref_node = session.buf_id, H.session_get_ref_node(session)
  local ref_extmark_id = ref_node.extmark_id

  -- With present placeholder, decide whether there was a valid change (then
  -- remove placeholder) or not (then no sync)
  -- NOTE: Only current tabstop is synced *and* only after its first edit is
  -- mostly done to limit code complexity. This is a reasonable compromise
  -- together with `parse()` syncing all tabstops in its normalization. Doing
  -- more is better for cases which are outside of suggested workflow (like
  -- editing text outside of "jump-edit-jump-edit-stop" loop).
  if ref_node.placeholder ~= nil then
    local ref_row, ref_col = H.extmark_get_range(buf_id, ref_extmark_id)
    local phd_row, phd_col = H.extmark_get_range(buf_id, ref_node.placeholder[1].extmark_id)
    if ref_row == phd_row and ref_col == phd_col then return end

    -- Remove placeholder to get extmark representing newly added text
    H.nodes_del(buf_id, ref_node.placeholder)
    ref_node.placeholder = nil
  end

  -- Compute reference text: dedented version of reference node's text to later
  -- reindent linked tabstops so that they preserve relative indent
  local row, col, end_row, end_col = H.extmark_get_range(buf_id, ref_extmark_id)
  local ref_text = vim.api.nvim_buf_get_text(0, row, col, end_row, end_col, {})
  ref_node.text = table.concat(ref_text, '\n')

  ref_text = H.dedent(ref_text, row, col)

  -- Sync nodes with current tabstop to have text from reference node
  local cur_tabstop = session.cur_tabstop
  local sync = function(n)
    -- Make expanding extmark for all nodes because current tabstop might be
    -- placed inside any placeholder. This allows proper extmark tracking.
    H.extmark_set_gravity(buf_id, n.extmark_id, 'expand')
    if not (n.tabstop == cur_tabstop and n.extmark_id ~= ref_extmark_id) then return end

    -- Ensure no placeholder because reference doesn't have one
    if n.placeholder ~= nil then H.nodes_del(buf_id, n.placeholder) end

    -- Set reference text reindented based on the start line's indent
    local cur_row, cur_col, cur_end_row, cur_end_col = H.extmark_get_range(buf_id, n.extmark_id)
    local cur_text = H.reindent(vim.deepcopy(ref_text), cur_row, cur_col)
    vim.api.nvim_buf_set_text(buf_id, cur_row, cur_col, cur_end_row, cur_end_col, cur_text)
    n.placeholder, n.text = nil, table.concat(cur_text, '\n')
  end
  local sync_cleanup = function(n)
    -- Make sure node's extmark doesn't move when setting later text
    -- Set this *after* traversing placeholder to have proper tracking in
    -- cases like `$1 ${2:$1}` - $2 extmark should be still expanding to track
    -- setting new text in $1.
    H.extmark_set_gravity(buf_id, n.extmark_id, 'left')
  end
  -- - Temporarily disable running this function (as autocommands will trigger)
  session._no_sync = true
  H.nodes_traverse(session.nodes, sync, sync_cleanup)
  session._no_sync = nil
  H.session_ensure_gravity(session)

  -- Maybe show choices for empty tabstop at cursor
  local cur_pos = vim.api.nvim_win_get_cursor(0)
  if ref_node.text == '' and cur_pos[1] == (row + 1) and cur_pos[2] == col then H.show_completion(ref_node.choices) end

  -- Make highlighting up to date
  H.session_update_hl(session)
end

H.session_jump = vim.schedule_wrap(function(session, direction)
  -- NOTE: Use `schedule_wrap` to workaround some edge cases when used inside
  -- expression mapping (as recommended for `<Tab>`)
  if session == nil then return end

  -- Compute target tabstop accounting for possibly missing ones.
  -- Example why needed: `${1:$2}$3`, setting text in $1 removes $2 tabstop
  -- and jumping should be done from 1 to 3.
  local present_tabstops, all_tabstops = {}, session.tabstops
  H.nodes_traverse(session.nodes, function(n) present_tabstops[n.tabstop or true] = true end)
  local cur_tabstop, new_tabstop = session.cur_tabstop, nil
  -- - NOTE: This can't be infinite as `prev`/`next` traverse all tabstops
  if not present_tabstops[cur_tabstop] then return end
  while not present_tabstops[new_tabstop] do
    new_tabstop = all_tabstops[new_tabstop or cur_tabstop][direction]
  end

  local event_data = { tabstop_from = cur_tabstop, tabstop_to = new_tabstop }
  H.trigger_event('MiniSnippetsSessionJumpPre', event_data)
  H.session_tabstop_focus(session, new_tabstop)
  H.trigger_event('MiniSnippetsSessionJump', event_data)
end)

H.session_update_hl = function(session)
  local buf_id, insert_opts = session.buf_id, session.insert_args.opts
  local empty_tabstop, empty_tabstop_final = insert_opts.empty_tabstop, insert_opts.empty_tabstop_final
  local cur_tabstop, tabstops = session.cur_tabstop, session.tabstops
  local is_replace = H.session_get_ref_node(session).placeholder ~= nil
  local current_hl = 'MiniSnippetsCurrent' .. (is_replace and 'Replace' or '')
  local priority = 101

  local update_hl = function(n, is_in_cur_tabstop)
    if n.tabstop == nil then return end

    -- Compute tabstop's features
    local row, col, opts = H.extmark_get(buf_id, n.extmark_id)
    local is_empty = row == opts.end_row and col == opts.end_col
    local is_final = n.tabstop == '0'
    local is_visited = tabstops[n.tabstop].is_visited
    local hl_group = (n.tabstop == cur_tabstop or is_in_cur_tabstop) and current_hl
      or (is_final and 'MiniSnippetsFinal' or (is_visited and 'MiniSnippetsVisited' or 'MiniSnippetsUnvisited'))

    -- Ensure up to date highlighting
    opts.hl_group, opts.virt_text_pos, opts.virt_text = nil, nil, nil

    if is_empty then
      if H.nvim_supports_inline_extmarks then
        opts.virt_text_pos = 'inline'
        opts.virt_text = { { is_final and empty_tabstop_final or empty_tabstop, hl_group } }
      end
    else
      opts.hl_group = hl_group
    end

    -- Make inline extmarks preserve order if placed at same position
    priority = priority + 1
    opts.priority = priority

    -- Update extmark
    vim.api.nvim_buf_set_extmark(buf_id, H.ns_id.nodes, row, col, opts)
  end

  -- Use custom traversing to ensure that nested tabstops inside current
  -- tabstop's placeholder are highlighted the same, even inline virtual text.
  local update_hl_in_nodes
  update_hl_in_nodes = function(nodes, is_in_cur_tabstop)
    for _, n in ipairs(nodes) do
      update_hl(n, is_in_cur_tabstop)
      if n.placeholder ~= nil then update_hl_in_nodes(n.placeholder, is_in_cur_tabstop or n.tabstop == cur_tabstop) end
    end
  end
  update_hl_in_nodes(session.nodes, false)
end

H.session_deinit = function(session, full)
  if session == nil then return end

  -- Trigger proper event
  H.trigger_event('MiniSnippetsSession' .. (full and 'Stop' or 'Suspend'), { session = vim.deepcopy(session) })
  if not H.is_loaded_buf(session.buf_id) then return end

  -- Delete or hide (make invisible) extmarks
  local extmark_fun = full and H.extmark_del or H.extmark_hide
  extmark_fun(session.buf_id, session.extmark_id)
  H.nodes_traverse(session.nodes, function(n) extmark_fun(session.buf_id, n.extmark_id) end)

  -- Hide completion if stopping was done manually
  if not H.cache.stop_is_auto then H.hide_completion() end
end

H.nodes_set_text = function(buf_id, nodes, tracking_extmark_id, indent, cur_body_line)
  local sw = vim.bo.shiftwidth
  local tab_text = vim.bo.expandtab and string.rep(' ', sw == 0 and vim.bo.tabstop or sw) or '\t'

  cur_body_line = cur_body_line or ''
  for _, n in ipairs(nodes) do
    -- Add tracking extmark
    local _, _, row, col = H.extmark_get_range(buf_id, tracking_extmark_id)
    n.extmark_id = H.extmark_new(buf_id, row, col)

    -- Adjust node's text and append it to currently set text
    if n.text ~= nil then
      -- Make variable/tabstop lines preserve relative indent
      local body_indent = (n.var == nil and n.tabstop == nil) and '' or H.get_indent(cur_body_line)
      local new_text = n.text:gsub('\n', '\n' .. indent .. body_indent):gsub('\t', tab_text)
      H.extmark_set_text(buf_id, tracking_extmark_id, 'right', new_text)

      -- NOTE: Compute current body line *before* setting node's actual text
      cur_body_line = (cur_body_line .. n.text):match('[^\n]*$')
      n.text = new_text
    end

    -- Process (possibly nested) placeholder nodes
    if n.placeholder ~= nil then H.nodes_set_text(buf_id, n.placeholder, tracking_extmark_id, indent, cur_body_line) end

    -- Make sure that node's extmark doesn't move when adding next node text
    H.extmark_set_gravity(buf_id, n.extmark_id, 'left')
  end
end

H.nodes_del = function(buf_id, nodes)
  local del = function(n)
    H.extmark_set_text(buf_id, n.extmark_id, 'inside', {})
    H.extmark_del(buf_id, n.extmark_id)
  end
  H.nodes_traverse(nodes, del)
end

H.nodes_traverse = function(nodes, f, f_post)
  for i, n in ipairs(nodes) do
    -- Prefer visiting whole node first to allow `f` to modify placeholder.
    -- It is also important to ensure proper gravity inside placeholder nodes.
    n = f(n) or n
    if n.placeholder ~= nil then n.placeholder = H.nodes_traverse(n.placeholder, f, f_post) end
    if f_post then n = f_post(n) or n end
    nodes[i] = n
  end
  return nodes
end

H.compute_tabstop_order = function(nodes)
  local tabstops_map = {}
  H.nodes_traverse(nodes, function(n) tabstops_map[n.tabstop or true] = true end)
  tabstops_map[true] = nil

  -- Order as numbers while allowing leading zeros. Put special `$0` last.
  local tabstops = vim.tbl_map(function(x) return { tonumber(x), x } end, vim.tbl_keys(tabstops_map))
  table.sort(tabstops, function(a, b)
    if a[2] == '0' then return false end
    if b[2] == '0' then return true end
    return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2])
  end)
  return vim.tbl_map(function(x) return x[2] end, tabstops)
end

-- Extmarks -------------------------------------------------------------------
-- All extmark functions work in current buffer with same global namespace.
-- This is because interaction with snippets eventually requires buffer to be
-- current, so instead rely on it becoming such as soon as possible.
H.extmark_new = function(buf_id, row, col)
  -- Create expanding extmark by default
  local opts = { end_row = row, end_col = col, right_gravity = false, end_right_gravity = true }
  return vim.api.nvim_buf_set_extmark(buf_id, H.ns_id.nodes, row, col, opts)
end

H.extmark_get = function(buf_id, ext_id)
  local data = vim.api.nvim_buf_get_extmark_by_id(buf_id, H.ns_id.nodes, ext_id, { details = true })
  data[3].id, data[3].ns_id = ext_id, nil
  return data[1], data[2], data[3]
end

H.extmark_get_range = function(buf_id, ext_id)
  local row, col, opts = H.extmark_get(buf_id, ext_id)
  return row, col, opts.end_row, opts.end_col
end

H.extmark_del = function(buf_id, ext_id) vim.api.nvim_buf_del_extmark(buf_id, H.ns_id.nodes, ext_id or -1) end

H.extmark_hide = function(buf_id, ext_id)
  local row, col, opts = H.extmark_get(buf_id, ext_id)
  opts.hl_group, opts.virt_text, opts.virt_text_pos = nil, nil, nil
  vim.api.nvim_buf_set_extmark(buf_id, H.ns_id.nodes, row, col, opts)
end

H.extmark_set_gravity = function(buf_id, ext_id, gravity)
  local row, col, opts = H.extmark_get(buf_id, ext_id)
  opts.right_gravity, opts.end_right_gravity = gravity == 'right', gravity ~= 'left'
  vim.api.nvim_buf_set_extmark(buf_id, H.ns_id.nodes, row, col, opts)
end

--stylua: ignore
H.extmark_set_text = function(buf_id, ext_id, side, text)
  local row, col, end_row, end_col = H.extmark_get_range(buf_id, ext_id)
  if side == 'left'  then end_row, end_col = row,     col     end
  if side == 'right' then row,     col     = end_row, end_col end
  text = type(text) == 'string' and vim.split(text, '\n') or text
  vim.api.nvim_buf_set_text(buf_id, row, col, end_row, end_col, text)
end

-- Indent ---------------------------------------------------------------------
H.get_indent = function(line)
  line = line or vim.fn.getline('.')
  local comment_indent = ''
  -- Treat comment leaders as part of indent
  for _, leader in ipairs(H.get_comment_leaders()) do
    local cur_match = line:match('^%s*' .. vim.pesc(leader) .. '%s*')
    -- Use biggest match in case of several matches. Allows respecting "nested"
    -- comment leaders like "---" and "--".
    if type(cur_match) == 'string' and comment_indent:len() < cur_match:len() then comment_indent = cur_match end
  end
  return comment_indent ~= '' and comment_indent or line:match('^%s*')
end

H.get_comment_leaders = function()
  local res = {}

  -- From 'commentstring'
  local main_leader = vim.split(vim.bo.commentstring, '%%s')[1]
  table.insert(res, vim.trim(main_leader))

  -- From 'comments'
  for _, comment_part in ipairs(vim.opt_local.comments:get()) do
    local prefix, suffix = comment_part:match('^(.*):(.*)$')
    suffix = vim.trim(suffix)
    if prefix:find('b') then
      -- Respect `b` flag (for blank) requiring space, tab or EOL after it
      table.insert(res, suffix .. ' ')
      table.insert(res, suffix .. '\t')
    elseif prefix:find('f') == nil then
      -- Add otherwise ignoring `f` flag (only first line should have it)
      table.insert(res, suffix)
    end
  end

  return res
end

H.dedent = function(lines, row, col)
  if #lines <= 1 then return lines end
  -- Compute common (smallest) indent width. Not accounting for actual indent
  -- characters is easier and works for common cases but breaks for weird ones,
  -- like `# a\n\t# b`.
  local init_line_at_pos = vim.fn.getline(row + 1):sub(1, col)
  local indent_width = H.get_indent(init_line_at_pos):len()
  for i = 2, #lines do
    -- Don't count "only indent" lines (i.e. blank with/without comment leader)
    local cur_indent = H.get_indent(lines[i])
    if cur_indent:len() < indent_width and cur_indent ~= lines[i] then indent_width = cur_indent:len() end
  end

  for i = 2, #lines do
    lines[i] = lines[i]:sub(indent_width + 1)
  end

  return lines
end

H.reindent = function(lines, row, col)
  if #lines <= 1 then return lines end
  local init_line_at_pos = vim.fn.getline(row + 1):sub(1, col)
  local indent = H.get_indent(init_line_at_pos)
  for i = 2, #lines do
    -- NOTE: reindent even "pure indent" lines, as it seems more natural
    lines[i] = indent .. lines[i]
  end
  return lines
end

-- LSP server -----------------------------------------------------------------
H.lsp_make_cmd = function(opts)
  local capabilities = {
    capabilities = { completionProvider = { triggerCharacters = opts.triggers, resolveProvider = false } },
  }
  local textdocument_completion = H.lsp_make_textdocument_completion(opts)

  return function(dispatchers)
    -- Loose adaptation of https://github.com/neovim/neovim/pull/24338
    local is_closing, request_id = false, 0
    return {
      request = function(method, params, callback, notify_reply_callback)
        if method == 'initialize' then callback(nil, capabilities) end
        if method == 'textDocument/completion' then textdocument_completion(params, callback) end
        if method == 'shutdown' then callback(nil, nil) end
        request_id = request_id + 1
        -- NOTE: This is needed to not accumulated "pending" `Client.requests`
        if notify_reply_callback then vim.schedule(function() pcall(notify_reply_callback, request_id) end) end
        return true, request_id
      end,
      notify = function(method, params)
        if method == 'exit' then dispatchers.on_exit(0, 15) end
        return false
      end,
      is_closing = function() return is_closing end,
      terminate = function() is_closing = true end,
    }
  end
end

H.lsp_make_textdocument_completion = function(opts)
  local expand_opts = { match = opts.match, insert = false }
  local insert_text_format_snippet = vim.lsp.protocol.InsertTextFormat.Snippet
  local kind_snippet = vim.lsp.protocol.CompletionItemKind.Snippet

  return vim.schedule_wrap(function(params, callback)
    local res = {}
    for _, s in ipairs(MiniSnippets.expand(expand_opts)) do
      local candidate = { label = s.prefix, insertText = s.body, documentation = s.desc }
      -- NOTE: set `detail` along with `documentation` if it provides new info
      candidate.detail = s.body ~= s.desc and s.body or nil
      candidate.insertTextFormat, candidate.kind = insert_text_format_snippet, kind_snippet
      if s.region ~= nil then
        local from, to = s.region.from, s.region.to
        local range_start = { line = from.line - 1, character = from.col - 1 }
        local range_end = { line = to.line - 1, character = to.col }
        candidate.textEdit = { newText = s.body, range = { start = range_start, ['end'] = range_end } }
        candidate.insertText = nil
      end
      table.insert(res, candidate)
    end

    callback(nil, res)
  end)
end

H.lsp_default_before_attach = function(buf_id)
  return vim.api.nvim_buf_is_loaded(buf_id) and vim.bo[buf_id].buftype == ''
end

-- Validators -----------------------------------------------------------------
H.is_string = function(x) return type(x) == 'string' end

H.is_maybe_string_or_arr = function(x) return x == nil or H.is_string(x) or H.is_array_of(x, H.is_string) end

H.is_snippet = function(x)
  return type(x) == 'table'
    -- Allow nil `prefix`: inferred as empty string
    and H.is_maybe_string_or_arr(x.prefix)
    -- Allow nil `body` to remove snippet with `prefix`
    and H.is_maybe_string_or_arr(x.body)
    -- Allow nil `desc` / `description`, in which case "prefix" is used
    and H.is_maybe_string_or_arr(x.desc)
    and H.is_maybe_string_or_arr(x.description)
    -- Allow nil `region` because it is not mandatory
    and (x.region == nil or H.is_region(x.region))
end

H.is_position = function(x) return type(x) == 'table' and type(x.line) == 'number' and type(x.col) == 'number' end

H.is_region = function(x) return type(x) == 'table' and H.is_position(x.from) and H.is_position(x.to) end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.snippets) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.notify = function(msg, level_name, silent)
  if not silent then vim.notify('(mini.snippets) ' .. msg, vim.log.levels[level_name]) end
end

H.trigger_event = function(event_name, data) vim.api.nvim_exec_autocmds('User', { pattern = event_name, data = data }) end

H.is_array_of = function(x, predicate)
  if not H.islist(x) then return false end
  for i = 1, #x do
    if not predicate(x[i]) then return false end
  end
  return true
end

H.is_loaded_buf = function(buf_id) return type(buf_id) == 'number' and vim.api.nvim_buf_is_loaded(buf_id) end

H.ensure_cur_buf = function(buf_id)
  if buf_id == 0 or buf_id == vim.api.nvim_get_current_buf() or not H.is_loaded_buf(buf_id) then return end
  local win_id = vim.fn.win_findbuf(buf_id)[1]
  if win_id == nil then return vim.api.nvim_win_set_buf(0, buf_id) end
  vim.api.nvim_set_current_win(win_id)
end

H.set_cursor = function(pos)
  -- Ensure no built-in completion window
  -- HACK: Always clearing (and not *only* when pumvisible) accounts for weird
  -- edge case when it is not visible (i.e. candidates *just* got exhausted)
  -- but will still "clear and restore" text leading to squashing of extmarks.
  H.hide_completion()

  -- NOTE: This won't put cursor past enf of line (for cursor in Insert mode to
  -- append text to the line). Ensure that Insert mode is active prior.
  vim.api.nvim_win_set_cursor(0, pos)
end

H.call_in_insert_mode = function(f)
  if vim.fn.mode() == 'i' then return f() end

  -- This is seemingly the only "good" way to ensure Insert mode.
  -- Mostly because it works with `vim.snippet.expand()` as its implementation
  -- uses `vim.api.nvim_feedkeys(k, 'n', true)` to select text in Select mode.
  vim.api.nvim_feedkeys('\28\14i', 'n', false)

  -- NOTE: mode changing is not immediate, only on some next tick. So schedule
  -- to execute `f` precisely when Insert mode is active.
  local cb = function() f() end
  vim.api.nvim_create_autocmd('ModeChanged', { pattern = '*:i*', once = true, callback = cb, desc = 'Call in Insert' })
end

H.delete_region = function(region)
  if not H.is_region(region) then return end
  vim.api.nvim_buf_set_text(0, region.from.line - 1, region.from.col - 1, region.to.line - 1, region.to.col, {})
  H.set_cursor({ region.from.line, region.from.col - 1 })
end

H.show_completion = function(items, startcol)
  if items == nil or #items == 0 or vim.fn.mode() ~= 'i' then return end
  vim.fn.complete(startcol or vim.fn.col('.'), items)
end

H.hide_completion = function()
  -- NOTE: `complete()` instead of emulating <C-y> has immediate effect
  -- (without the need to `vim.schedule()`). The downsides are that `fn.mode(1)`
  -- returns 'ic' (i.e. not "i" for clean Insert mode) and <C-n>/<C-p> act as if
  -- there is completion active (thus not allowing them as custom mappings).
  -- Appending ` | call feedkeys("\\<C-y>", "n")` removes that, but still would
  -- require workarounds to work in edge cases.
  -- NOTE: Use `silent` to not show "Pattern not found" messages. It also hides
  -- '--INSERT--' temporarily when 'showmode' is active, but seems acceptable.
  if vim.fn.mode() == 'i' then vim.cmd('silent noautocmd call complete(col("."), [])') end
end

-- TODO: Remove after compatibility with Neovim=0.9 is dropped
H.islist = vim.fn.has('nvim-0.10') == 1 and vim.islist or vim.tbl_islist

return MiniSnippets
