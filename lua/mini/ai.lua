--- *mini.ai* Extend and create a/i textobjects
---
--- MIT License Copyright (c) 2022 Evgeni Chasnovski

--- Enhance some builtin |text-objects| (like |a(|, |a)|, |a'|, and more),
--- create new ones (like `a*`, `a<Space>`, `af`, `a?`, and more), and allow
--- user to create their own.
---
--- Features:
--- - Customizable creation of `a`/`i` textobjects using Lua patterns and functions.
---   Supports:
---     - Dot-repeat.
---     - |v:count|.
---     - Different search methods (see |MiniAi.config|).
---     - Consecutive application (update selection without leaving Visual mode).
---     - Aliases for multiple textobjects.
---
--- - Comprehensive builtin textobjects (see more in |MiniAi-builtin-textobjects|):
---     - Balanced brackets (with and without whitespace) plus alias.
---     - Balanced quotes plus alias.
---     - Function call.
---     - Argument.
---     - Tag.
---     - Derived from user prompt.
---     - Default for anything but Latin letters (to fall back to |text-objects|).
---
---     For more textobjects see |MiniExtra.gen_ai_spec|.
---
--- - Motions for jumping to left/right edge of textobject.
---
--- - Set of specification generators to tweak some builtin textobjects (see
---   |MiniAi.gen_spec|).
---
--- - Treesitter textobjects (through |MiniAi.gen_spec.treesitter()| helper).
---
--- This module works by defining mappings for both `a` and `i` in Visual and
--- Operator-pending mode. After typing, they wait for single character user input
--- treated as textobject identifier and apply resolved textobject specification
--- (fall back to other mappings if can't find proper textobject id). For more
--- information see |MiniAi-textobject-specification| and |MiniAi-algorithm|.
---
--- Known issues which won't be resolved:
--- - Search for builtin textobjects is done mostly using Lua patterns
---   (regex-like approach). Certain amount of false positives is to be expected.
---
--- - During search for builtin textobjects there is no distinction if it is
---   inside string or comment. For example, in the following case there will
---   be wrong match for a function call: `f(a = ")", b = 1)`.
---
--- General rule of thumb: any instrument using available parser for document
--- structure (like treesitter) will usually provide more precise results. This
--- module has builtins mostly for plain text textobjects which are useful
--- most of the times (like "inside brackets", "around quotes/underscore", etc.).
--- For advanced use cases define function specification for custom textobjects.
---
--- What it doesn't (and probably won't) do:
--- - Have special operators to specially handle whitespace (like `I` and `A`
---   in 'targets.vim'). Whitespace handling is assumed to be done inside
---   textobject specification (like `i(` and `i)` handle whitespace differently).
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.ai').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `MiniAi`
--- which you can use for scripting or manually (with `:lua MiniAi.*`).
---
--- See |MiniAi.config| for available config settings.
---
--- You can override runtime config settings (like `config.custom_textobjects`)
--- locally to buffer inside `vim.b.miniai_config` which should have same structure
--- as `MiniAi.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- To stop module from showing non-error feedback, set `config.silent = true`.
---
--- # Comparisons ~
---
--- - [wellle/targets.vim](https://github.com/wellle/targets.vim):
---     - Has limited support for creating own textobjects: it is constrained
---       to pre-defined detection rules. 'mini.ai' allows creating own rules
---       via Lua patterns and functions (see |MiniAi-textobject-specification|).
---     - Doesn't provide any programmatical API for getting information about
---       textobjects. 'mini.ai' does it via |MiniAi.find_textobject()|.
---     - Has no implementation of "moving to edge of textobject". 'mini.ai'
---       does it via |MiniAi.move_cursor()| and `g[` and `g]` default mappings.
---     - Both implement the notion of manual "next"/"last" search directions.
---     - Implements `A`, `I` operators. 'mini.ai' does not by design: it is
---       assumed to be a property of textobject, not operator.
---     - Doesn't implement "function call" and "user prompt" textobjects.
---       'mini.ai' does (with `f` and `?` identifiers).
---     - Has limited support for "argument" textobject. Although it works in
---       most situations, it often misdetects commas as argument separator
---       (like if it is inside quotes or `{}`). 'mini.ai' deals with these cases.
--- - [nvim-treesitter/nvim-treesitter-textobjects](https://github.com/nvim-treesitter/nvim-treesitter-textobjects):
---     - Along with textobject functionality provides a curated and maintained
---       set of popular textobject queries for many languages (which can power
---       |MiniAi.gen_spec.treesitter()| functionality).
---     - Both support working with |treesitter-directives| allowing more
---       fine-tuned textobjects.
---     - Implements only textobjects based on treesitter.
---     - Doesn't support |v:count|.
---     - Doesn't support multiple search method (basically, only 'cover').
---     - Doesn't support consecutive application of target textobject.
---
--- # Disabling ~
---
--- To disable, set `vim.g.miniai_disable` (globally) or `vim.b.miniai_disable`
--- (for a buffer) to `true`. Considering high number of different scenarios
--- and customization intentions, writing exact rules for disabling module's
--- functionality is left to user. See |mini.nvim-disabling-recipes| for common
--- recipes.
---@tag MiniAi

--- This table describes all builtin textobjects along with what they
--- represent. Explanation:
--- - `Key` represents the textobject identifier: single character which should
---   be typed after `a`/`i`.
--- - `Name` is a description of textobject.
--- - `Example line` contains a string for which examples are constructed. The
---   `*` denotes the cursor position.
--- - `a`/`i` describe inclusive region representing `a` and `i` textobjects.
---   Use numbers in separators for easier navigation.
--- - `2a`/`2i` describe either `2a`/`2i` (support for |v:count|) textobjects
---   or `a`/`i` textobject followed by another `a`/`i` textobject (consecutive
---   application leads to incremental selection).
---
--- Example: typing `va)` with cursor on `*` leads to selection from column 2
--- to column 12. Another typing `a)` changes selection to [1; 13]. Also, besides
--- visual selection, any |operator| can be used or `g[`/`g]` motions to move
--- to left/right edge of `a` textobject.
--- >
---  ┌───┬───────────────┬──────────────────┬────────┬────────┬────────┬────────┐
---  │Key│     Name      │   Example line   │   a    │   i    │   2a   │   2i   │
---  ├───┴───────────────┴──────────────────┴────────┴────────┴────────┴────────┤
---  ├┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈1234567890123456┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┤
---  │ ( │  Balanced ()  │ (( *a (bb) ))    │        │        │        │        │
---  │ [ │  Balanced []  │ [[ *a [bb] ]]    │ [2;12] │ [4;10] │ [1;13] │ [2;12] │
---  │ { │  Balanced {}  │ {{ *a {bb} }}    │        │        │        │        │
---  │ < │  Balanced <>  │ << *a <bb> >>    │        │        │        │        │
---  ├┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈1234567890123456┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┤
---  │ ) │  Balanced ()  │ (( *a (bb) ))    │        │        │        │        │
---  │ ] │  Balanced []  │ [[ *a [bb] ]]    │        │        │        │        │
---  │ } │  Balanced {}  │ {{ *a {bb} }}    │ [2;12] │ [3;11] │ [1;13] │ [2;12] │
---  │ > │  Balanced <>  │ << *a <bb> >>    │        │        │        │        │
---  │ b │  Alias for    │ [( *a {bb} )]    │        │        │        │        │
---  │   │  ), ], or }   │                  │        │        │        │        │
---  ├┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈1234567890123456┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┤
---  │ " │  Balanced "   │ "*a" " bb "      │        │        │        │        │
---  │ ' │  Balanced '   │ '*a' ' bb '      │        │        │        │        │
---  │ ` │  Balanced `   │ `*a` ` bb `      │ [1;4]  │ [2;3]  │ [6;11] │ [7;10] │
---  │ q │  Alias for    │ '*a' " bb "      │        │        │        │        │
---  │   │  ", ', or `   │                  │        │        │        │        │
---  ├┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈1234567890123456┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┤
---  │ ? │  User prompt  │ e*e o e o o      │ [3;5]  │ [4;4]  │ [7;9]  │ [8;8]  │
---  │   │(typed e and o)│                  │        │        │        │        │
---  ├┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈1234567890123456┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┤
---  │ t │      Tag      │ <x><y>*a</y></x> │ [4;12] │ [7;8]  │ [1;16] │ [4;12] │
---  ├┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈1234567890123456┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┤
---  │ f │ Function call │ f(a, g(*b, c) )  │ [6;13] │ [8;12] │ [1;15] │ [3;14] │
---  ├┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈1234567890123456┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┤
---  │ a │   Argument    │ f(*a, g(b, c) )  │ [3;5]  │ [3;4]  │ [5;14] │ [7;13] │
---  ├┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈1234567890123456┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┤
---  │   │    Default    │ aa_*b__cc___     │ [4;7]  │ [4;5]  │ [8;12] │ [8;9]  │
---  │   │   (typed _)   │                  │        │        │        │        │
---  └───┴───────────────┴──────────────────┴────────┴────────┴────────┴────────┘
--- <
--- Notes:
--- - All examples assume default `config.search_method`.
--- - Open brackets differ from close brackets by how they treat inner edge
---   whitespace for `i` textobject: open ignores it, close - includes.
--- - Default textobject is activated for identifiers which are not Latin letters.
---   They are designed to be treated as separators, so include only right edge
---   in `a` textobject. To include both edges, use custom textobjects
---   (see |MiniAi-textobject-specification| and |MiniAi.config|). Note:
---     - When cursor is exactly on the identifier character while there are
---       two matching candidates on both left and right, the resulting region
---       with smaller width is preferred.
---@tag MiniAi-builtin-textobjects

--- Note: this is similar to |MiniSurround-glossary|.
---
--- REGION ~
--- Table representing region in a buffer. Fields:
--- - <from> and <to> for inclusive start and end positions (<to> might be
---   `nil` to describe empty region). Each position is also a table with
---   line <line> and column <col> (both start at 1).
--- - <vis_mode> for which Visual mode will be used to select textobject.
---   See `opts` argument of |MiniAi.select_textobject()|.
---   One of `'v'`, `'V'`, `'\22'` (escaped `'<C-v>'`).
---
--- Examples: >lua
---
---   { from = { line = 1, col = 1 }, to = { line = 2, col = 1 } }
---
---   -- Forced linewise mode
---   {
---     from = { line = 1, col = 1 }, to = { line = 2, col = 1 },
---     vis_mode = 'V',
---   }
---
---   -- Empty region
---   { from = { line = 10, col = 10 } }
--- <
--- PATTERN ~
--- String describing Lua pattern.
---
--- SPAN ~
--- Interval inside a string (end-exclusive). Like [1, 5). Equal `from` and `to` edges
--- describe empty span at that point.
---
--- Span `A = [a1, a2)` covers `B = [b1, b2)` if every element of `B` is within
--- `A` (`a1 <= b < a2`). It also is described as "B is nested inside A".
---
--- NESTED PATTERN ~
--- Array of patterns aimed to describe nested spans.
---
--- SPAN MATCHES NESTED PATTERN ~
--- If there is a sequence of consecutively nested spans each matching
--- corresponding pattern within substring of previous span (or input string
--- for first span). Example: >lua
---
---   -- Nested patterns for balanced `()` with inner space
---   { '%b()', '^. .* .$' }
---
---   -- Example input string (with columns underneath for easier reading):
---      "( ( () ( ) ) )"
---   --  12345678901234
--- <
--- Here are all matching spans [1, 15) and [3, 13). Both [5, 7) and [8, 10)
--- match first pattern but not second. All other combinations of `(` and `)`
--- don't match first pattern (not balanced).
---
--- COMPOSED PATTERN ~
--- Array with each element describing possible pattern (or array of them) at
--- that place. Composed pattern basically defines all possible combinations of
--- nested pattern (their cartesian product). Examples:
---
--- 1. Either balanced `()` or balanced `[]` but both with inner edge space: >lua
---
---     -- Composed pattern
---     { { '%b()', '%b[]' }, '^. .* .$' }
---
---     -- Composed pattern expanded into equivalent array of nested patterns
---     { '%b()', '^. .* .$' } -- and
---     { '%b[]', '^. .* .$' }
--- <
--- 2. Either "balanced `()` with inner edge space" or "balanced `[]` with no
---    inner edge space", both with 5 or more characters: >lua
---
---     -- Composed pattern
---     { { { '%b()', '^. .* .$' }, { '%b[]', '^.[^ ].*[^ ].$' } }, '.....' }
---
---     -- Composed pattern expanded into equivalent array of nested patterns
---     { '%b()', '^. .* .$', '.....' } -- and
---     { '%b[]', '^.[^ ].*[^ ].$', '.....' }
--- <
--- SPAN MATCHES COMPOSED PATTERN ~
--- If it matches at least one nested pattern from expanded composed pattern.
---@tag MiniAi-glossary

--- Textobject specification has a structure of composed pattern (see
--- |MiniAi-glossary|) with two differences:
--- - Last pattern(s) should have even number of empty capture groups denoting
---   how the last string should be processed to extract `a` or `i` textobject:
---     - Zero captures mean that whole string represents both `a` and `i`.
---       Example: `xxx` will define textobject matching string `xxx` literally.
---     - Two captures represent `i` textobject inside of them. `a` - whole string.
---       Example: `x()x()x` defines `a` textobject to be `xxx`, `i` - middle `x`.
---     - Four captures define `a` textobject inside captures 1 and 4, `i` -
---       inside captures 2 and 3. Example: `x()()x()x()` defines `a`
---       textobject to be last `xx`, `i` - middle `x`.
--- - Allows callable objects (see |vim.is_callable()|) in certain places
---   (enables more complex textobjects in exchange of increase in configuration
---   complexity and computations):
---     - If specification itself is a callable, it will be called with the same
---       arguments as |MiniAi.find_textobject()| and should return one of:
---         - Composed pattern. Useful for implementing user input. Example of
---           simplified variant of textobject for function call with name taken
---           from user prompt: >lua
---
---             function()
---               local left_edge = vim.pesc(vim.fn.input('Function name: '))
---               return { left_edge .. '%b()', '^.-%(().*()%)$' }
---             end
--- <
---         - Single output region. Useful to allow full control over
---           textobject. Will be taken as is. Example of returning whole buffer: >lua
---
---             function()
---               local from = { line = 1, col = 1 }
---               local to = {
---                 line = vim.fn.line('$'),
---                 col = math.max(vim.fn.getline('$'):len(), 1)
---               }
---               return { from = from, to = to, vis_mode = 'V' }
---             end
--- <
---         - Array of output region(s). Useful for incorporating other
---           instruments, like treesitter (see |MiniAi.gen_spec.treesitter()|).
---           The best region will be picked in the same manner as with composed
---           pattern (respecting options `n_lines`, `search_method`, etc.).
---           Example of selecting "best" line with display width more than 80: >lua
---
---             function(_, _, _)
---               local res = {}
---               for i = 1, vim.api.nvim_buf_line_count(0) do
---                 local cur_line = vim.fn.getline(i)
---                 if vim.fn.strdisplaywidth(cur_line) > 80 then
---                   local region = {
---                     from = { line = i, col = 1 },
---                     to = { line = i, col = cur_line:len() },
---                   }
---                   table.insert(res, region)
---                 end
---               end
---               return res
---             end
--- <
---     - If there is a callable instead of assumed string pattern, it is expected
---       to have signature `(line, init)` and behave like `pattern:find()`.
---       It should return two numbers representing span in `line` next after
---       or at `init` (`nil` if there is no such span).
---       !IMPORTANT NOTE!: it means that output's `from` shouldn't be strictly
---       to the left of `init` (it will lead to infinite loop). Not allowed as
---       last item (as it should be pattern with captures).
---       Example of matching only balanced parenthesis with big enough width: >lua
---
---         {
---           '%b()',
---           function(s, init)
---             if init > 1 or s:len() < 5 then return end
---             return 1, s:len()
---           end,
---           '^.().*().$'
---         }
--- <
--- More examples: >lua
---
---   -- Pair of balanced brackets from set (used for builtin `b` identifier):
---   { { '%b()', '%b[]', '%b{}' }, '^.().*().$' }
---
---   -- Imitate word ignoring digits and punctuation (only for Latin alphabet):
---   { '()()%f[%w]%w+()[ \t]*()' }
---
---   -- Word with camel case support (also supports only Latin alphabet):
---   {
---     {
---       '%u[%l%d]+%f[^%l%d]',
---       '%f[%S][%l%d]+%f[^%l%d]',
---       '%f[%P][%l%d]+%f[^%l%d]',
---       '^[%l%d]+%f[^%l%d]',
---     },
---     '^().*()$'
---   }
---
---   -- Number:
---   { '%f[%d]%d+' }
---
---   -- Date in 'YYYY-MM-DD' format:
---   { '()%d%d%d%d%-%d%d%-%d%d()' }
---
---   -- Lua block string:
---   { '%[%[().-()%]%]' }
--- <
--- See |MiniAi.gen_spec| for function wrappers to create commonly used
--- textobject specifications.
---@tag MiniAi-textobject-specification

--- Search for the textobjects relies on these principles:
--- - It uses same input data as described in |MiniAi.find_textobject()|,
---   i.e. whether it is `a` or `i` textobject, its identifier, reference region, etc.
--- - Textobject specification is constructed based on textobject identifier
---   (see |MiniAi-textobject-specification|).
--- - General search is done by converting some 2d buffer region (neighborhood
---   of reference region) into 1d string (each line is appended with `\n`).
---   Then search for a best span matching textobject specification is done
---   inside string (see |MiniAi-glossary|). After that, span is converted back
---   into 2d region. Note: first search is done inside reference region lines,
---   and only after that - inside its neighborhood within `config.n_lines`
---   (see |MiniAi.config|).
--- - The best matching span is chosen by iterating over all spans matching
---   textobject specification and comparing them with "current best".
---   Comparison also depends on reference region (tighter covering is better,
---   otherwise closer is better) and search method (if span is even considered).
--- - Extract span based on extraction pattern (last item in nested pattern).
--- - If task is to perform a consecutive search (`opts.n_times` is greater than 1),
---   steps are repeated with current best match becoming reference region.
---   One such additional step is also done if final region is equal to
---   reference region (this enables consecutive application).
---
--- Notes:
--- - Iteration over all matched spans is done in depth-first fashion with
---   respect to nested pattern.
--- - It is guaranteed that span is compared only once.
--- - For the sake of increasing functionality, during iteration over all
---   matching spans, some Lua patterns in composed pattern are handled
---   specially.
---     - `%bxx` (`xx` is two identical characters). It denotes balanced pair
---       of identical characters and results into "paired" matches. For
---       example, `%b""` for `"aa" "bb"` would match `"aa"` and `"bb"`, but
---       not middle `" "`.
---     - `x.-y` (`x` and `y` are different strings). It results only in matches with
---       smallest width. For example, `e.-o` for `e e o o` will result only in
---       middle `e o`. Note: it has some implications for when parts have
---       quantifiers (like `+`, etc.), which usually can be resolved with
---       frontier pattern `%f[]` (see examples in |MiniAi-textobject-specification|).
---@tag MiniAi-algorithm

-- Module definition ==========================================================
local MiniAi = {}
local H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniAi.config|.
---
---@usage >lua
---   require('mini.ai').setup() -- use default config
---   -- OR
---   require('mini.ai').setup({}) -- replace {} with your config table
--- <
MiniAi.setup = function(config)
  -- Export module
  _G.MiniAi = MiniAi

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)
end

--- Defaults ~
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text # Custom textobjects ~
---
--- User can define own textobjects by supplying `config.custom_textobjects`.
--- It should be a table with keys being single character textobject identifier
--- (supported by |getcharstr()|) and values - textobject specification
--- (see |MiniAi-textobject-specification|).
---
--- General recommendations:
--- - This can be used to override builtin ones (|MiniAi-builtin-textobjects|).
---   Supply non-valid input (not in specification format) to disable module's
---   builtin textobject in favor of external or Neovim's builtin mapping.
--- - Keys should use character representation which can be |getcharstr()| output.
---   For example, `'\r'` and not `'<CR>'`.
---
--- Examples:
--- >lua
---   require('mini.ai').setup({
---     custom_textobjects = {
---       -- Tweak argument textobject
---       a = require('mini.ai').gen_spec.argument({ brackets = { '%b()' } }),
---
---       -- Disable brackets alias in favor of builtin block textobject
---       b = false,
---
---       -- Now `vax` should select `xxx` and `vix` - middle `x`
---       x = { 'x()x()x' },
---
---       -- Whole buffer
---       g = function()
---         local from = { line = 1, col = 1 }
---         local to = {
---           line = vim.fn.line('$'),
---           col = math.max(vim.fn.getline('$'):len(), 1)
---         }
---         return { from = from, to = to }
---       end
---     }
---   })
---
---   -- Use `vim.b.miniai_config` to customize per buffer
---   -- Example of specification useful for Markdown files:
---   local spec_pair = require('mini.ai').gen_spec.pair
---   vim.b.miniai_config = {
---     custom_textobjects = {
---       ['*'] = spec_pair('*', '*', { type = 'greedy' }),
---       ['_'] = spec_pair('_', '_', { type = 'greedy' }),
---     },
---   }
--- <
--- There are more example specifications in |MiniAi-textobject-specification|.
---
--- # Search method ~
---
--- Value of `config.search_method` defines how best match search is done.
--- Based on its value, one of the following matches will be selected:
--- - Covering match. Left/right edge is before/after left/right edge of
---   reference region.
--- - Previous match. Left/right edge is before left/right edge of reference
---   region.
--- - Next match. Left/right edge is after left/right edge of reference region.
--- - Nearest match. Whichever is closest among previous and next matches.
---
--- Possible values are:
--- - `'cover'` - use only covering match. Don't use either previous or
---   next; report that there is no textobject found.
--- - `'cover_or_next'` (default) - use covering match. If not found, use next.
--- - `'cover_or_prev'` - use covering match. If not found, use previous.
--- - `'cover_or_nearest'` - use covering match. If not found, use nearest.
--- - `'next'` - use next match.
--- - `'prev'` - use previous match.
--- - `'nearest'` - use nearest match.
---
--- Note: search is first performed on the reference region lines and only
--- after failure - on the whole neighborhood defined by `config.n_lines`. This
--- means that with `config.search_method` not equal to `'cover'`, "prev" or
--- "next" textobject will end up as search result if they are found on first
--- stage although covering match might be found in bigger, whole neighborhood.
--- This design is based on observation that most of the time operation is done
--- within reference region lines (usually cursor line).
---
--- Here is an example of what `a)` textobject is based on a value of
--- `'config.search_method'` when cursor is inside `bbb` word:
--- - `'cover'`:         `(a) bbb (c)` -> none
--- - `'cover_or_next'`: `(a) bbb (c)` -> `(c)`
--- - `'cover_or_prev'`: `(a) bbb (c)` -> `(a)`
--- - `'cover_or_nearest'`: depends on cursor position.
---   For first and second `b` - as in `cover_or_prev` (as previous match is
---   nearer), for third - as in `cover_or_next` (as next match is nearer).
--- - `'next'`: `(a) bbb (c)` -> `(c)`. Same outcome for `(bbb)`.
--- - `'prev'`: `(a) bbb (c)` -> `(a)`. Same outcome for `(bbb)`.
--- - `'nearest'`: depends on cursor position (same as in `'cover_or_nearest'`).
---
--- # Mappings ~
---
--- Mappings `around_next` / `inside_next` and `around_last` / `inside_last` are
--- essentially `around` / `inside` but using search method `'next'` and `'prev'`.
---
--- NOTE: with default config, built-in LSP mappings |v_an| and |v_in| on Neovim>=0.12
--- are overridden. Either use different `around_next` / `inside_next` keys or
--- map manually using |vim.lsp.buf.selection_range()|. For example: >lua
---
---   local map_lsp_selection = function(lhs, desc)
---     local s = vim.startswith(desc, 'Increase') and 1 or -1
---     local rhs = function() vim.lsp.buf.selection_range(s * vim.v.count1) end
---     vim.keymap.set('x', lhs, rhs, { desc = desc })
---   end
---   map_lsp_selection('<Leader>ls', 'Increase selection')
---   map_lsp_selection('<Leader>lS', 'Decrease selection')
--- <
MiniAi.config = {
  -- Table with textobject id as fields, textobject specification as values.
  -- Also use this to disable builtin textobjects. See |MiniAi.config|.
  custom_textobjects = nil,

  -- Module mappings. Use `''` (empty string) to disable one.
  mappings = {
    -- Main textobject prefixes
    around = 'a',
    inside = 'i',

    -- Next/last textobjects
    -- NOTE: These override built-in LSP selection mappings on Neovim>=0.12
    -- Map LSP selection manually to use it (see `:h MiniAi.config`)
    around_next = 'an',
    inside_next = 'in',
    around_last = 'al',
    inside_last = 'il',

    -- Move cursor to corresponding edge of `a` textobject
    goto_left = 'g[',
    goto_right = 'g]',
  },

  -- Number of lines within which textobject is searched
  n_lines = 50,

  -- How to search for object (first inside current line, then inside
  -- neighborhood). One of 'cover', 'cover_or_next', 'cover_or_prev',
  -- 'cover_or_nearest', 'next', 'prev', 'nearest'.
  search_method = 'cover_or_next',

  -- Whether to disable showing non-error feedback
  -- This also affects (purely informational) helper messages shown after
  -- idle time if user input is required.
  silent = false,
}
--minidoc_afterlines_end

-- Module functionality =======================================================
--- Find textobject region
---
---@param ai_type string One of `'a'` or `'i'`.
---@param id string Single character string representing textobject id. It is
---   used to get specification which is later used to compute textobject region.
---   Note: if specification is a function, it is called with all present
---   arguments (`opts` is populated with default arguments).
---@param opts table|nil Options. Possible fields:
---   - <n_lines> - Number of lines within which textobject is searched.
---     Default: `config.n_lines` (see |MiniAi.config|).
---   - <n_times> - Number of times to perform a consecutive search. Each one
---     is done with reference region being previous found textobject region.
---     Default: 1.
---   - <reference_region> - region to try to cover (see |MiniAi-glossary|). It
---     is guaranteed that output region will not be inside or equal to this one.
---     Default: empty region at cursor position.
---   - <search_method> - Search method. Default: `config.search_method`.
---
---@return table|nil Region of textobject or `nil` if no textobject different
---   from `opts.reference_region` was consecutively found `opts.n_times` times.
MiniAi.find_textobject = function(ai_type, id, opts)
  if not (ai_type == 'a' or ai_type == 'i') then H.error([[`ai_type` should be one of 'a' or 'i'.]]) end
  opts = vim.tbl_deep_extend('force', H.get_default_opts(), opts or {})
  H.validate_search_method(opts.search_method)

  -- Get textobject specification
  local tobj_spec = H.get_textobject_spec(id, { ai_type, id, opts })
  if tobj_spec == nil then return end
  if H.is_region(tobj_spec) then return tobj_spec end

  -- Find region
  local res = H.find_textobject_region(tobj_spec, ai_type, opts)

  if res == nil then
    local msg = string.format(
      [[No textobject %s found covering region%s within %d line%s and `search_method = '%s'`.]],
      vim.inspect(ai_type .. id),
      opts.n_times == 1 and '' or (' %s times'):format(opts.n_times),
      opts.n_lines,
      opts.n_lines == 1 and '' or 's',
      opts.search_method
    )
    H.message(msg)
  end

  return res
end

--- Move cursor to edge of textobject
---
---@param side string One of `'left'` or `'right'`.
---@param ai_type string One of `'a'` or `'i'`.
---@param id string Single character string representing textobject id.
---@param opts table|nil Same as in |MiniAi.find_textobject()|.
---   `opts.n_times` means number of actual jumps (important when cursor
---   already on the potential jump spot).
MiniAi.move_cursor = function(side, ai_type, id, opts)
  if not (side == 'left' or side == 'right') then H.error([[`side` should be one of 'left' or 'right'.]]) end
  opts = opts or {}
  local init_pos = vim.api.nvim_win_get_cursor(0)

  -- Compute single textobject first to find out if it would move the cursor.
  -- If not, then eventual `n_times` should be bigger by 1 to imitate `n_times`
  -- *actual* jumps. This implements consecutive jumps and has logic of "If
  -- cursor is strictly inside region, move to its side first".
  local new_opts = vim.tbl_deep_extend('force', opts, { n_times = 1 })
  local tobj_single = MiniAi.find_textobject(ai_type, id, new_opts)
  if tobj_single == nil then return end
  local tobj_side = side == 'left' and 'from' or 'to'

  -- Allow empty region
  tobj_single.to = tobj_single.to or tobj_single.from

  new_opts.n_times = opts.n_times or 1
  if (init_pos[1] == tobj_single[tobj_side].line) and (init_pos[2] == tobj_single[tobj_side].col - 1) then
    new_opts.n_times = new_opts.n_times + 1
  end

  -- Compute actually needed textobject while avoiding unnecessary computation
  -- in a most common usage (`v:count1 == 1`)
  local pos = tobj_single[tobj_side]
  if new_opts.n_times > 1 then
    local tobj = MiniAi.find_textobject(ai_type, id, new_opts)
    if tobj == nil then return end
    tobj.to = tobj.to or tobj.from
    pos = tobj[tobj_side]
  end

  -- Move cursor and open enough folds
  vim.cmd("normal! m'")
  vim.api.nvim_win_set_cursor(0, { pos.line, pos.col - 1 })
  vim.cmd('normal! zv')
end

--- Generate common textobject specifications
---
--- This is a table with function elements. Call to actually get specification.
---
--- Example: >lua
---
---   local gen_spec = require('mini.ai').gen_spec
---   require('mini.ai').setup({
---     custom_textobjects = {
---       -- Tweak argument to be recognized only inside `()` between `;`
---       a = gen_spec.argument({ brackets = { '%b()' }, separator = ';' }),
---
---       -- Tweak function call to not detect dot in function name
---       f = gen_spec.function_call({ name_pattern = '[%w_]' }),
---
---       -- Function definition (needs treesitter queries with these captures)
---       F = gen_spec.treesitter({ a = '@function.outer', i = '@function.inner' }),
---
---       -- Make `|` select both edges in non-balanced way
---       ['|'] = gen_spec.pair('|', '|', { type = 'non-balanced' }),
---     }
---   })
--- <
MiniAi.gen_spec = {}

--- Argument specification
---
--- Argument textobject (has default `a` identifier) is a region inside
--- balanced bracket between allowed not excluded separators. Use this function
--- to tweak how it works.
---
--- Examples:
--- - `argument({ brackets = { '%b()' } })` will search for an argument only
---   inside balanced `()`.
--- - `argument({ separator = '[,;]' })` will treat both `,` and `;` as separators.
--- - `argument({ exclude_regions = { '%b()' } })` will exclude separators
---   which are inside balanced `()` (inside outer brackets).
---
---@param opts table|nil Options. Allowed fields:
---   - <brackets> - array of patterns for outer balanced brackets.
---     Default: `{ '%b()', '%b[]', '%b{}' }` (any `()`, `[]`, or `{}` can
---     enclose arguments).
---   - <separator> - separator pattern. Default: `','`.
---     One of the practical usages of this option is to include whitespace
---     around character to be a part of separator. For example, `'%s*,%s*'`
---     will treat as separator not only ',', but its possible surrounding
---     whitespace. This has both positive and negative effects. On one hand,
---     `daa` executed over the first argument will delete whitespace after
---     first comma, leading to a more expected outcome. On the other hand it
---     is ambiguous which argument is picked when cursor is over whitespace
---     near the character separator.
---   - <exclude_regions> - array with patterns for regions inside which
---     separators will be ignored.
---     Default: `{ '%b""', "%b''", '%b()', '%b[]', '%b{}' }` (separators
---     inside balanced quotes or brackets are ignored).
MiniAi.gen_spec.argument = function(opts)
  opts = vim.tbl_extend('force', {
    brackets = { '%b()', '%b[]', '%b{}' },
    separator = ',',
    exclude_regions = { '%b""', "%b''", '%b()', '%b[]', '%b{}' },
  }, opts or {})

  local brackets, separator, exclude_regions = opts.brackets, opts.separator, opts.exclude_regions

  local res = {}
  -- Match brackets
  res[1] = brackets

  -- Match argument with both left and right separators/brackets
  res[2] = function(s, init)
    -- Cache string separators per spec as they are used multiple times.
    -- Storing per spec allows coexistence of several argument specifications.
    H.cache.argument_sep_spans = H.cache.argument_sep_spans or {}
    H.cache.argument_sep_spans[res] = H.cache.argument_sep_spans[res] or {}
    local sep_spans = H.cache.argument_sep_spans[res][s] or H.arg_get_separator_spans(s, separator, exclude_regions)
    H.cache.argument_sep_spans[res][s] = sep_spans

    -- Return span fully on right of `init`, `nil` otherwise
    -- For first argument returns left bracket; for last - right one.
    for i = 1, #sep_spans - 1 do
      if init <= sep_spans[i][1] then return sep_spans[i][1], sep_spans[i + 1][2] end
    end

    return nil
  end

  -- Make extraction part
  --
  -- Extraction of `a` type depends on argument number, `i` - as `a` but
  -- without separators and inner whitespace. The reason for this complex
  -- solution are the following requirements:
  -- - Don't match argument region when cursor is on the outer bracket.
  --   Example: `f(xxx)` should select argument only when cursor is on 'x'.
  -- - Don't select edge whitespace for first and last argument BUT MATCH WHEN
  --   CURSOR IS ON THEM which needs to match edge whitespace right until the
  --   extraction part. This is useful when working with padded brackets.
  --   Example for `f(  xx  ,  yy  )`:
  --     - `a` object should select 'xx  ,' when cursor is on all '  xx  ';
  --       should select ',  yy' when cursor is on all '  yy  '.
  --     - `i` object should select 'xx' when cursor is on all '  xx  ';
  --       should select 'yy' when cursor is on all '  yy  '.
  --
  -- At this stage whether argument is first, middle, last, or single is
  -- determined by presence of matching separator at either left or right edge.
  -- If edge matches separator pattern - it has separator. If not - a bracket.
  local left_edge_separator = '^' .. separator
  local find_after_left_separator = function(s)
    local _, sep_end = s:find(left_edge_separator)
    if sep_end == nil then return nil end
    return sep_end + 1
  end
  local find_after_left_bracket = function(s)
    local left_sep = find_after_left_separator(s)
    if left_sep ~= nil then return nil end
    return 2
  end

  local right_edge_sep = separator .. '$'
  local find_before_right_separator = function(s)
    local sep_start, _ = s:find(right_edge_sep)
    if sep_start == nil then return nil end
    return sep_start - 1
  end
  local find_before_right_bracket = function(s)
    local right_sep = find_before_right_separator(s)
    if right_sep ~= nil then return nil end
    return s:len() - 1
  end

  local match_and_include = function(left_type, left_include, right_type, right_include)
    local find_after_left = left_type == 'bracket' and find_after_left_bracket or find_after_left_separator
    local find_before_right = right_type == 'bracket' and find_before_right_bracket or find_before_right_separator

    return function(s, init)
      -- Match only once
      if init > 1 then return nil end

      -- Make sure that string matches left and right targets
      local left_after, right_before = find_after_left(s), find_before_right(s)
      if left_after == nil or right_before == nil then return nil end

      -- Possibly include matched edge targets
      local left = left_include and 1 or left_after
      local right = right_include and s:len() or right_before

      return left, right
    end
  end

  local extract_first_arg = '^%s*()().-()%s*' .. separator .. '()$'
  local extract_nonfirst_arg = '^()' .. separator .. '%s*().-()()%s*$'
  local extract_single_arg = '^%s*().-()%s*$'

  res[3] = {
    -- First argument. Include right separator, exclude left whitespace.
    { match_and_include('bracket', false, 'separator', true), extract_first_arg },

    -- Middle argument. Include only left separator.
    { match_and_include('separator', true, 'separator', false), extract_nonfirst_arg },

    -- Last argument. Include left separator, exclude right whitespace.
    -- NOTE: it misbehaves for whitespace argument. It's OK because it's rare.
    { match_and_include('separator', true, 'bracket', false), extract_nonfirst_arg },

    -- Single argument. Include both whitespace (makes `aa` and `ia` differ).
    { match_and_include('bracket', false, 'bracket', false), extract_single_arg },
  }

  return res
end

--- Function call specification
---
--- Function call textobject (has default `f` identifier) is a region with some
--- characters followed by balanced `()`. Use this function to tweak how it works.
---
--- Example:
--- - `function_call({ name_pattern = '[%w_]' })` will recognize function name with
---   only alphanumeric or underscore (not dot).
---
---@param opts table|nil Options. Allowed fields:
---   - <name_pattern> - string pattern of character set allowed in function name.
---     Default: `'[%w_%.]'` (alphanumeric, underscore, or dot).
---     Note: should be enclosed in `[]`.
MiniAi.gen_spec.function_call = function(opts)
  opts = vim.tbl_deep_extend('force', { name_pattern = '[%w_%.]' }, opts or {})
  -- Use frontier pattern to select widest possible name
  return { '%f' .. opts.name_pattern .. opts.name_pattern .. '+%b()', '^.-%(().*()%)$' }
end

--- Pair specification
---
--- Use it to define textobject for region surrounded with `left` from left and
--- `right` from right. The `a` textobject includes both edges, `i` - excludes them.
---
--- Region can be one of several types (controlled with `opts.type`). All
--- examples are for default search method, `a` textobject, and use `'_'` as
--- both `left` and `right`:
--- - Non-balanced (`{ type = 'non-balanced' }`), default. Equivalent to using
---   `x.-y` as first pattern. Example: on line '_a_b_c_' it consecutively
---   matches '_a_', '_b_', '_c_'.
--- - Balanced (`{ type = 'balanced' }`). Equivalent to using `%bxy` as first
---   pattern. Example: on line '_a_b_c_' it consecutively matches '_a_', '_c_'.
---   Note: both `left` and `right` should be single character.
--- - Greedy (`{ type = 'greedy' }`). Like non-balanced but will select maximum
---   consecutive `left` and `right` edges. Example: on line '__a__b_' it
---   consecutively selects '__a__' and '__b_'. Note: both `left` and `right`
---   should be single character.
---
---@param left string Left edge.
---@param right string Right edge.
---@param opts table|nil Options. Possible fields:
---   - <type> - Type of a pair. One of `'non-balanced'` (default), `'balanced'`,
---   `'greedy'`.
MiniAi.gen_spec.pair = function(left, right, opts)
  if not (type(left) == 'string' and type(right) == 'string') then
    H.error('Both `left` and `right` should be strings.')
  end
  opts = vim.tbl_deep_extend('force', { type = 'non-balanced' }, opts or {})

  if (opts.type == 'balanced' or opts.type == 'greedy') and not (left:len() == 1 and right:len() == 1) then
    local msg =
      string.format([[Both `left` and `right` should be single character for `opts.type == '%s'`.]], opts.type)
    H.error(msg)
  end

  local left_esc = vim.pesc(left)
  local right_esc = vim.pesc(right)

  if opts.type == 'balanced' then return { string.format('%%b%s%s', left, right), '^.().*().$' } end
  if opts.type == 'non-balanced' then return { string.format('%s().-()%s', left_esc, right_esc) } end
  if opts.type == 'greedy' then
    return { string.format('%%f[%s]%s+()[^%s]-()%s+%%f[^%s]', left_esc, left_esc, left_esc, right_esc, right_esc) }
  end

  H.error([[`opts.type` should be one of 'balanced', 'non-balanced', 'greedy'.]])
end

--- Treesitter specification
---
--- This is a specification in function form. When called with a pair of
--- treesitter captures, it returns a specification function outputting an
--- array of regions that match corresponding (`a` or `i`) capture.
---
--- In order for this to work, apart from working treesitter parser for desired
--- language, user should have a reachable language-specific 'textobjects'
--- query (see |vim.treesitter.query.get()|).
--- The most straightforward way for this is to have 'textobjects.scm' query
--- file with treesitter captures stored in some recognized path. This is
--- primarily designed to be compatible with plugin
--- 'nvim-treesitter/nvim-treesitter-textobjects', but can be used without it.
---
--- Two most common approaches for having a query file:
--- - Install 'nvim-treesitter/nvim-treesitter-textobjects'. It has curated and
---   well maintained builtin query files for many languages with a standardized
---   capture names, like `function.outer`, `function.inner`, etc.
--- - Manually create file 'after/queries/<language name>/textobjects.scm' in
---   your |$XDG_CONFIG_HOME| directory. It should contain queries with
---   captures (later used to define textobjects). See |lua-treesitter-query|.
--- To verify that query file is reachable, run (example for "lua" language,
--- output should have at least an intended file): >vim
---
---   :lua print(vim.inspect(vim.treesitter.query.get_files('lua','textobjects')))
--- <
--- Example configuration for function definition textobject with
--- 'nvim-treesitter/nvim-treesitter-textobjects' captures:
--- >lua
---   local spec_treesitter = require('mini.ai').gen_spec.treesitter
---   require('mini.ai').setup({
---     custom_textobjects = {
---       F = spec_treesitter({ a = '@function.outer', i = '@function.inner' }),
---       o = spec_treesitter({
---         a = { '@conditional.outer', '@loop.outer' },
---         i = { '@conditional.inner', '@loop.inner' },
---       })
---     }
---   })
--- <
--- Notes:
--- - Be sure that query files don't contain unknown |treesitter-directives|
---   (like `#make-range!`, for example). Otherwise textobject for such capture
---   might not be found as |lua-treesitter-core| won't treat them as captures.
---   Verify with `:=vim.treesitter.query.get('lang', 'textobjects')` and see
---   if the target capture is recognized as one.
--- - It uses buffer's |filetype| to determine query language.
--- - On large files it is slower than pattern-based textobjects. Still very
---   fast though (one search should be magnitude of milliseconds or tens of
---   milliseconds on really large file).
---
---@param ai_captures table Captures for `a` and `i` textobjects: table with
---   <a> and <i> fields with captures for `a` and `i` textobjects respectively.
---   Each value can be either a string capture (should start with `'@'`) or an
---   array of such captures (best among all matches will be chosen).
---@param opts table|nil Options. Possible values:
---   - <use_nvim_treesitter> - whether to try to use 'nvim-treesitter' plugin
---     (if present) to do the query. It used to implement more advanced behavior
---     and more coherent experience if 'nvim-treesitter-textobjects' queries are
---     used. However, as |lua-treesitter-core| methods are more capable now,
---     the option will soon be removed. Only present for backward compatibility.
---     Default: `false`.
---
---@return function Function with |MiniAi.find_textobject()| signature which
---   returns array of current buffer regions representing matches for
---   corresponding (`a` or `i`) treesitter capture.
---
---@seealso - |MiniAi-textobject-specification| for how this type of textobject
---   specification is processed.
--- - |vim.treesitter.query.get()| for how query is fetched.
--- - |Query:iter_captures()| for how all query captures are iterated in case of
---   no 'nvim-treesitter'.
MiniAi.gen_spec.treesitter = function(ai_captures, opts)
  -- TODO: Remove after releasing 'mini.nvim' 0.17.0
  opts = vim.tbl_deep_extend('force', { use_nvim_treesitter = false }, opts or {})
  ai_captures = H.prepare_ai_captures(ai_captures)

  -- Tree-sitter ranges are 0-based, end-exclusive, and usually
  -- `row1-col1-byte1-row2-col2-byte2` (i.e. "range six") format.
  local ts_range_to_region = function(r)
    -- The `master` branch of 'nvim-treesitter' can return "range four" format
    -- if it uses custom directives, like `#make-range!`. Due to the fact that
    -- it doesn't fully mock the `TSNode:range()` method to return "range six".
    -- TODO: Remove after 'nvim-treesitter' `master` branch support is dropped.
    local offset = #r == 4 and -1 or 0
    local res = { from = { line = r[1] + 1, col = r[2] + 1 }, to = { line = r[4 + offset] + 1, col = r[5 + offset] } }

    -- NOTE: Adjust "row-exclusive, col-0" range that means "all previous row
    -- including the newline character"
    if res.to.col == 0 then
      res.to.line = res.to.line - 1
      res.to.col = vim.fn.col({ res.to.line, '$' })
    end

    return res
  end

  return function(ai_type, _, _)
    -- Get array of matched treesitter nodes
    local target_captures = ai_captures[ai_type]
    local has_nvim_treesitter = pcall(require, 'nvim-treesitter') and pcall(require, 'nvim-treesitter.query')
    local range_querier = (has_nvim_treesitter and opts.use_nvim_treesitter) and H.get_matched_ranges_plugin
      or H.get_matched_ranges_builtin
    local matched_ranges = range_querier(target_captures)
    return vim.tbl_map(ts_range_to_region, matched_ranges)
  end
end

--- Specification from user prompt
---
--- - Ask user for left and right textobject edges as raw strings (no pattern).
--- - Construct specification for a textobject that matches from left edge string
---   to right edge string: `a` includes both strings, `i` only insides.
---
--- Used for |MiniAi-builtin-textobjects| with identifier `?`.
---
---@return function Textobject specification as function.
MiniAi.gen_spec.user_prompt = function()
  return function()
    -- Using cache allows for a dot-repeat without another user input
    if H.cache.prompted_textobject ~= nil then return H.cache.prompted_textobject end

    local left = H.user_input('Left edge')
    if left == nil or left == '' then return end
    local right = H.user_input('Right edge')
    if right == nil or right == '' then return end

    -- Clean command line from prompt messages (does not work in Visual mode)
    vim.cmd([[echo '' | redraw]])

    local left_esc, right_esc = vim.pesc(left), vim.pesc(right)
    local res = { string.format('%s().-()%s', left_esc, right_esc) }
    H.cache.prompted_textobject = res
    return res
  end
end

--- Visually select textobject region
---
--- Does nothing if no region is found.
---
---@param ai_type string One of `'a'` or `'i'`.
---@param id string Single character string representing textobject id.
---@param opts table|nil Same as in |MiniAi.find_textobject()|. Extra fields:
---   - <vis_mode> - One of `'v'`, `'V'`, or `'\22'` (escaped version of `'<C-v>'`).
---     Default: Latest visual mode.
---   - <operator_pending> - Whether selection is for Operator-pending mode.
---     Used in that mode's mappings, shouldn't be used directly. Default: `false`.
MiniAi.select_textobject = function(ai_type, id, opts)
  if H.is_disabled() then return end

  opts = opts or {}
  local operator_pending = opts.operator_pending

  -- Exit to Normal before getting textobject id. This way invalid id doesn't
  -- result into staying in current mode (which seems to be more convenient).
  H.exit_to_normal_mode()

  local tobj = MiniAi.find_textobject(ai_type, id, opts)
  if tobj == nil then return end

  local set_cursor = function(position) vim.api.nvim_win_set_cursor(0, { position.line, position.col - 1 }) end

  -- Allow empty regions
  local tobj_is_empty = tobj.to == nil
  tobj.to = tobj.to or tobj.from

  -- Compute selection type preferring the one coming from textobject
  local vis_mode = tobj.vis_mode
  if vis_mode == nil or not H.is_visual_mode(vis_mode) then
    local prev_vis_mode = vim.fn.visualmode()
    prev_vis_mode = prev_vis_mode == '' and 'v' or prev_vis_mode
    vis_mode = opts.vis_mode and vim.api.nvim_replace_termcodes(opts.vis_mode, true, true, true) or prev_vis_mode
  end

  local cache_eventignore = vim.o.eventignore
  -- Allow going past end of line in order to collapse multiline regions
  local cache_virtualedit, cache_whichwrap = vim.o.virtualedit, vim.o.whichwrap

  -- Cache window horizontal view data to possibly counter unwanted side scroll
  local leftcol = vim.fn.winsaveview().leftcol

  pcall(function()
    -- Do nothing in Operator-pending mode for empty region (except `c`, `d`,
    -- or selected "replace" operators). These are hand picked because they
    -- completely remove selected text, which is necessary for currently only
    -- possible empty region selection implementation.
    local is_empty_opending = tobj_is_empty and opts.operator_pending
    if is_empty_opending then
      local is_allowed_empty_opending = vim.v.operator == 'c'
        or vim.v.operator == 'd'
        or (vim.v.operator == 'g@' and vim.o.operatorfunc:find('MiniOperators%.replace') ~= nil)
        or (vim.v.operator == 'g@' and vim.o.operatorfunc:find('substitute') ~= nil)
      if not is_allowed_empty_opending then return H.message('Textobject region is empty. Nothing is done.') end
    end

    -- Allow setting cursor past line end (allows collapsing multiline region)
    -- NOTE: This doesn't work for 'virtualedit=all' and 'selection=inclusive'
    -- (default). The reason is that later option restoring is done immediately
    -- leading to a selection obey 'virtualedit=all' rules and thus won't treat
    -- end-of-line as '\n' and collapse multiline region. The solution is to
    -- `vim.schedule()` option restore, but it feels too much for a niche case.
    vim.o.virtualedit = 'onemore'

    -- Select region:
    -- - Go from start to end stay at range end in Visual mode (as done in
    --   built-in visual selection).
    -- - Open just enough folds to have both ends visible.
    -- - Respect exclusive selection (including when selecting end of line)
    set_cursor(tobj.from)
    vim.cmd('normal! zv')
    vim.cmd('normal! ' .. vis_mode)
    set_cursor(tobj.to)
    if vim.o.selection == 'exclusive' and not tobj_is_empty then vim.cmd('set whichwrap=l | normal! l') end
    vim.cmd('normal! zv')

    -- Restore horizontal view which was possibly affected by moving cursor
    -- NOTE: It seems to not affect cursor if it is outside of restored view
    vim.fn.winrestview({ leftcol = leftcol })

    if is_empty_opending then
      -- Add single space (without triggering events) and visually select it.
      -- Seems like the only way to make `ci)` and `di)` move inside empty
      -- brackets. Original idea is from 'wellle/targets.vim'.
      vim.o.eventignore = 'all'

      -- First escape from previously started Visual mode
      vim.cmd([[silent! execute "normal! \<Esc>i \<Esc>v"]])
    end
  end)

  -- Restore options
  vim.o.eventignore = cache_eventignore
  vim.o.virtualedit, vim.o.whichwrap = cache_virtualedit, cache_whichwrap
end

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniAi.config)

-- Cache for various operations
H.cache = {}

-- Builtin textobjects
H.builtin_textobjects = {
  -- Use balanced pair for brackets. Use opening ones to possibly remove edge
  -- whitespace from `i` textobject.
  ['('] = { '%b()', '^.%s*().-()%s*.$' },
  [')'] = { '%b()', '^.().*().$' },
  ['['] = { '%b[]', '^.%s*().-()%s*.$' },
  [']'] = { '%b[]', '^.().*().$' },
  ['{'] = { '%b{}', '^.%s*().-()%s*.$' },
  ['}'] = { '%b{}', '^.().*().$' },
  ['<'] = { '%b<>', '^.%s*().-()%s*.$' },
  ['>'] = { '%b<>', '^.().*().$' },
  -- Use special "same balanced" pattern to select quotes in pairs
  ["'"] = { "%b''", '^.().*().$' },
  ['"'] = { '%b""', '^.().*().$' },
  ['`'] = { '%b``', '^.().*().$' },
  -- Derived from user prompt
  ['?'] = MiniAi.gen_spec.user_prompt(),
  -- Argument
  ['a'] = MiniAi.gen_spec.argument(),
  -- Brackets
  ['b'] = { { '%b()', '%b[]', '%b{}' }, '^.().*().$' },
  -- Function call
  ['f'] = MiniAi.gen_spec.function_call(),
  -- Tag
  ['t'] = { '<(%w-)%f[^<%w][^<>]->.-</%1>', '^<.->().*()</[^/]->$' },
  -- Quotes
  ['q'] = { { "%b''", '%b""', '%b``' }, '^.().*().$' },
}

-- Module's namespaces
H.ns_id = {
  -- Track user input
  input = vim.api.nvim_create_namespace('MiniAiInput'),
}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  H.check_type('custom_textobjects', config.custom_textobjects, 'table', true)

  H.check_type('mappings', config.mappings, 'table')
  H.check_type('mappings.around', config.mappings.around, 'string')
  H.check_type('mappings.inside', config.mappings.inside, 'string')
  H.check_type('mappings.around_next', config.mappings.around_next, 'string')
  H.check_type('mappings.inside_next', config.mappings.inside_next, 'string')
  H.check_type('mappings.around_last', config.mappings.around_last, 'string')
  H.check_type('mappings.inside_last', config.mappings.inside_last, 'string')
  H.check_type('mappings.goto_left', config.mappings.goto_left, 'string')
  H.check_type('mappings.goto_right', config.mappings.goto_right, 'string')

  H.check_type('n_lines', config.n_lines, 'number')
  H.validate_search_method(config.search_method, 'search_method')
  H.check_type('silent', config.silent, 'boolean')

  return config
end

--stylua: ignore
H.apply_config = function(config)
  MiniAi.config = config

  -- Make mappings
  local maps = config.mappings
  local m = function(mode, lhs, rhs, opts)
    opts.expr = true
    -- Allow recursive mapping to support falling back on user defined mapping
    opts.remap = true
    H.map(mode, lhs, rhs, opts)
  end

  m({ 'n', 'x', 'o' }, maps.goto_left,  function() return H.expr_motion('left') end,   { desc = 'Move to left "around"' })
  m({ 'n', 'x', 'o' }, maps.goto_right, function() return H.expr_motion('right') end,  { desc = 'Move to right "around"' })

  local make_tobj = function(mode, ai_type, search_method)
    return function() return H.expr_textobject(mode, ai_type, { search_method = search_method }) end
  end

  m('x', maps.around, make_tobj('x', 'a'), { desc = 'Around textobject' })
  m('x', maps.inside, make_tobj('x', 'i'), { desc = 'Inside textobject' })
  m('o', maps.around, make_tobj('o', 'a'), { desc = 'Around textobject' })
  m('o', maps.inside, make_tobj('o', 'i'), { desc = 'Inside textobject' })

  m('x', maps.around_next, make_tobj('x', 'a', 'next'), { desc = 'Around next textobject' })
  m('x', maps.around_last, make_tobj('x', 'a', 'prev'), { desc = 'Around last textobject' })
  m('x', maps.inside_next, make_tobj('x', 'i', 'next'), { desc = 'Inside next textobject' })
  m('x', maps.inside_last, make_tobj('x', 'i', 'prev'), { desc = 'Inside last textobject' })
  m('o', maps.around_next, make_tobj('o', 'a', 'next'), { desc = 'Around next textobject' })
  m('o', maps.around_last, make_tobj('o', 'a', 'prev'), { desc = 'Around last textobject' })
  m('o', maps.inside_next, make_tobj('o', 'i', 'next'), { desc = 'Inside next textobject' })
  m('o', maps.inside_last, make_tobj('o', 'i', 'prev'), { desc = 'Inside last textobject' })
end

H.is_disabled = function() return vim.g.miniai_disable == true or vim.b.miniai_disable == true end

H.get_config = function(config)
  return vim.tbl_deep_extend('force', MiniAi.config, vim.b.miniai_config or {}, config or {})
end

H.is_search_method = function(x, x_name)
  x = x or H.get_config().search_method
  x_name = x_name or '`config.search_method`'

  local allowed_methods = vim.tbl_keys(H.span_compare_methods)
  if vim.tbl_contains(allowed_methods, x) then return true end

  table.sort(allowed_methods)
  local allowed_methods_string = table.concat(vim.tbl_map(vim.inspect, allowed_methods), ', ')
  local msg = ([[%s should be one of %s.]]):format(x_name, allowed_methods_string)
  return false, msg
end

H.validate_search_method = function(x, x_name)
  local is_valid, msg = H.is_search_method(x, x_name)
  if not is_valid then H.error(msg) end
end

-- Mappings -------------------------------------------------------------------
H.expr_textobject = function(mode, ai_type, opts)
  local tobj_id = H.user_textobject_id(ai_type)

  if tobj_id == nil then return mode == 'o' and '<Esc>' or '' end

  -- Possibly fall back to builtin `a`/`i` textobjects
  if H.is_disabled() or not H.is_valid_textobject_id(tobj_id) then
    local mappings = H.get_config().mappings
    local main_key = mappings[ai_type == 'a' and 'around' or 'inside']
    local res = main_key .. tobj_id
    -- If fallback is an existing user mapping, prepend it with '<Ignore>'.
    -- This deals with `:h recursive_mapping`. Shouldn't prepend if it is a
    -- builtin textobject. Also see https://github.com/vim/vim/issues/10907 .
    if vim.fn.maparg(res, mode) ~= '' then res = '<Ignore>' .. res end
    return res
  end
  opts = vim.tbl_deep_extend('force', H.get_default_opts(), opts or {})

  -- Clear cache
  H.cache = {}

  -- Construct call options based on mode
  local reference_region_field, operator_pending_field, vis_mode_field = 'nil', 'nil', 'nil'

  if mode == 'x' then
    -- Use Visual selection as reference region for Visual mode mappings
    reference_region_field = vim.inspect(H.get_visual_region(), { newline = '', indent = '' })
  end

  if mode == 'o' then
    -- Supply `operator_pending` flag in Operator-pending mode
    operator_pending_field = 'true'

    -- Take into account forced Operator-pending modes ('nov', 'noV', 'no<C-V>')
    vis_mode_field = vim.fn.mode(1):gsub('^no', '')
    vis_mode_field = vim.inspect(vis_mode_field == '' and 'v' or vis_mode_field)
  end

  -- Make expression
  return '<Cmd>lua '
    .. string.format(
      [[MiniAi.select_textobject('%s', %s, { search_method = %s, n_times = %d, reference_region = %s, operator_pending = %s, vis_mode = %s })]],
      ai_type,
      vim.inspect(tobj_id),
      vim.inspect(opts.search_method),
      vim.v.count1,
      reference_region_field,
      operator_pending_field,
      vis_mode_field
    )
    .. '<CR>'
end

H.expr_motion = function(side)
  if H.is_disabled() then return '' end

  if not (side == 'left' or side == 'right') then H.error([[`side` should be one of 'left' or 'right'.]]) end

  -- Get user input
  local tobj_id = H.user_textobject_id('a')
  if tobj_id == nil then return end

  -- Clear cache
  H.cache = {}

  -- Make expression for moving cursor
  return '<Cmd>lua '
    .. string.format([[MiniAi.move_cursor('%s', 'a', %s, { n_times = %d })]], side, vim.inspect(tobj_id), vim.v.count1)
    .. '<CR>'
end

-- Work with textobject info --------------------------------------------------
H.make_textobject_table = function()
  -- Extend builtins with data from `config`. Don't use `tbl_deep_extend()`
  -- because only top level keys should be merged.
  local textobjects = vim.tbl_extend('force', H.builtin_textobjects, H.get_config().custom_textobjects or {})

  -- Use default textobject pattern for anything excluding Latin characters, as
  -- they are needed to fall back to Neovim's built-in textobjects (like `aw`)
  return setmetatable(textobjects, {
    __index = function(_, key)
      if type(key) == 'string' and string.find(key, '^%a$') ~= nil then return end
      local key_esc = vim.pesc(key)
      -- Use `%f[]` to ensure maximum stretch in both directions. Include only
      -- right edge in `a` textobject.
      -- Example output: '_()()[^_]-()_+%f[^_]()'
      return { string.format('%s()()[^%s]-()%s+%%f[^%s]()', key_esc, key_esc, key_esc, key_esc) }
    end,
  })
end

H.get_textobject_spec = function(id, args)
  local textobject_tbl = H.make_textobject_table()
  local spec = textobject_tbl[id]

  -- Allow function returning spec or region(s)
  if vim.is_callable(spec) then spec = spec(unpack(args)) end

  -- Wrap callable tables to be an actual functions. Otherwise they might be
  -- confused with list of patterns.
  if H.is_composed_pattern(spec) then return vim.tbl_map(H.wrap_callable_table, spec) end

  if not (H.is_region(spec) or H.is_region_array(spec)) then return nil end
  return spec
end

H.is_valid_textobject_id = function(id)
  local spec = H.make_textobject_table()[id]
  return type(spec) == 'table' or vim.is_callable(spec)
end

H.is_region = function(x)
  if type(x) ~= 'table' then return false end
  local from_is_valid = type(x.from) == 'table' and type(x.from.line) == 'number' and type(x.from.col) == 'number'
  -- Allow `to` to be `nil` to describe empty regions
  local to_is_valid = true
  if x.to ~= nil then
    to_is_valid = type(x.to) == 'table' and type(x.to.line) == 'number' and type(x.to.col) == 'number'
  end
  return from_is_valid and to_is_valid
end

H.is_region_array = function(x)
  if not H.islist(x) then return false end
  for _, v in ipairs(x) do
    if not H.is_region(v) then return false end
  end
  return true
end

H.is_composed_pattern = function(x)
  if not (H.islist(x) and #x > 0) then return false end
  for _, val in ipairs(x) do
    local val_type = type(val)
    if not (val_type == 'table' or val_type == 'string' or vim.is_callable(val)) then return false end
  end
  return true
end

-- Work with finding textobjects ----------------------------------------------
---@param tobj_spec table Composed pattern. Last item(s) - extraction template.
---@param ai_type string One of `'a'` or `'i'`.
---@param opts table Textobject options with all fields present.
---@private
H.find_textobject_region = function(tobj_spec, ai_type, opts)
  local reference_region, n_times, n_lines = opts.reference_region, opts.n_times, opts.n_lines

  if n_times == 0 then return end

  -- Find `n_times` matching spans evolving from reference region span
  -- First try to find inside 0-neighborhood
  local neigh = H.get_neighborhood(reference_region, 0)
  local reference_span = neigh.region_to_span(reference_region)

  local find_next = function(cur_reference_span)
    local res = H.find_best_match(neigh, tobj_spec, cur_reference_span, opts)

    -- If didn't find in 0-neighborhood, possibly try extend one
    if res.span == nil then
      -- Stop if no need to extend neighborhood
      if n_lines == 0 or neigh.n_neighbors > 0 then return {} end

      -- Update data with respect to new neighborhood
      local cur_reference_region = neigh.span_to_region(cur_reference_span)
      neigh = H.get_neighborhood(reference_region, n_lines)
      reference_span = neigh.region_to_span(reference_region)
      cur_reference_span = neigh.region_to_span(cur_reference_region)

      -- Recompute based on new neighborhood
      res = H.find_best_match(neigh, tobj_spec, cur_reference_span, opts)
    end

    return res
  end

  local find_res = { span = reference_span }
  for _ = 1, n_times do
    find_res = find_next(find_res.span)
    if find_res.span == nil then return end
  end

  -- Extract final span
  local extract = function(span, extract_pattern)
    -- Use `nil` extract pattern to allow array of regions as textobject spec
    if extract_pattern == nil then return span end

    -- First extract local (with respect to best matched span) span
    local s = neigh['1d']:sub(span.from, span.to - 1)
    local local_span = H.extract_span(s, extract_pattern, ai_type)

    -- Convert local span to global
    local offset = span.from - 1
    return { from = local_span.from + offset, to = local_span.to + offset }
  end

  local final_span = extract(find_res.span, find_res.extract_pattern)

  -- Ensure that output region is different from reference. This is needed if
  -- final span was shrunk during extraction and resulted into equal to input
  -- reference. This powers consecutive application of most `i` textobjects.
  if H.is_span_covering(reference_span, final_span) then
    find_res = find_next(find_res.span)
    if find_res.span == nil then return end
    final_span = extract(find_res.span, find_res.extract_pattern)
    if H.is_span_covering(reference_span, final_span) then return end
  end

  -- Convert to region
  return neigh.span_to_region(final_span, find_res.vis_mode)
end

H.get_default_opts = function()
  local config = H.get_config()
  local cur_pos = vim.api.nvim_win_get_cursor(0)
  return {
    n_lines = config.n_lines,
    n_times = vim.v.count1,
    -- Empty region at cursor position
    reference_region = { from = { line = cur_pos[1], col = cur_pos[2] + 1 } },
    search_method = config.search_method,
  }
end

-- Work with argument textobject ----------------------------------------------
H.arg_get_separator_spans = function(s, sep_pattern, exclude_regions)
  if s:len() <= 2 then return {} end

  -- Pre-compute edge separator spans (assumes edge characters are brackets)
  local left_bracket_span = { 1, 1 }
  local right_bracket_span = { s:len(), s:len() }

  -- Get all separator spans (meaning separator is allowed to match more than
  -- a single character)
  local sep_spans = {}
  s:gsub('()' .. sep_pattern .. '()', function(l, r) table.insert(sep_spans, { l, r - 1 }) end)
  if #sep_spans == 0 then return { left_bracket_span, right_bracket_span } end

  -- Remove separators that are in "excluded regions": by default, inside
  -- brackets or quotes
  local inner_s, forbidden = s:sub(2, -2), {}
  local add_to_forbidden = function(l, r) table.insert(forbidden, { l + 1, r }) end

  for _, pat in ipairs(exclude_regions) do
    local capture_pat = string.format('()%s()', pat)
    inner_s:gsub(capture_pat, add_to_forbidden)
  end

  local res = vim.tbl_filter(function(x) return not H.is_span_inside_spans(x, forbidden) end, sep_spans)

  -- Append edge separators (assumes first and last characters are from
  -- brackets). This allows single argument and ensures at least 2 elements.
  table.insert(res, 1, left_bracket_span)
  table.insert(res, right_bracket_span)
  return res
end

-- Work with treesitter textobject --------------------------------------------
H.prepare_ai_captures = function(ai_captures)
  local is_capture = function(x)
    if type(x) == 'string' then x = { x } end
    if not H.islist(x) then return false end

    for _, v in ipairs(x) do
      if not (type(v) == 'string' and v:sub(1, 1) == '@') then return false end
    end
    return true
  end

  if not (type(ai_captures) == 'table' and is_capture(ai_captures.a) and is_capture(ai_captures.i)) then
    H.error('Wrong format for `ai_captures`. See `MiniAi.gen_spec.treesitter()` for details.')
  end

  local prepare = function(x)
    if type(x) == 'string' then return { x } end
    return x
  end

  return { a = prepare(ai_captures.a), i = prepare(ai_captures.i) }
end

H.get_matched_ranges_plugin = function(captures)
  local ts_queries = require('nvim-treesitter.query')
  local buf_id = vim.api.nvim_get_current_buf()
  local matches = ts_queries.get_capture_matches_recursively(buf_id, captures, 'textobjects')
  local res = vim.tbl_map(function(m) return vim.treesitter.get_range(m.node, buf_id, m.metadata) end, matches)
  return res
end

H.get_matched_ranges_builtin = function(captures)
  -- Get buffer's parser (LanguageTree)
  local buf_id = vim.api.nvim_get_current_buf()
  -- TODO: Remove `opts.error` after compatibility with Neovim=0.11 is dropped
  local has_parser, parser = pcall(vim.treesitter.get_parser, buf_id, nil, { error = false })
  if not has_parser or parser == nil then H.error_treesitter('parser') end

  -- Get parser (LanguageTree) at cursor (important for injected languages)
  local pos = vim.api.nvim_win_get_cursor(0)
  local lang_tree = parser:language_for_range({ pos[1] - 1, pos[2], pos[1] - 1, pos[2] })

  local missing_query_langs = {}
  local res = {}
  -- Maybe go up parent trees to work with injected languages
  while vim.tbl_isempty(res) and lang_tree ~= nil do
    local lang = lang_tree:lang()
    -- Get query file depending on the local language
    local query = vim.treesitter.query.get(lang, 'textobjects')

    if query ~= nil then H.append_ranges(res, buf_id, query, captures, lang_tree) end
    if query == nil then missing_query_langs[lang] = true end

    -- `LanguageTree:parent()` was added in Neovim<0.10
    -- TODO: Drop extra check after compatibility with Neovim=0.9 is dropped
    lang_tree = lang_tree.parent and lang_tree:parent() or nil
  end

  if vim.tbl_isempty(res) and not vim.tbl_isempty(missing_query_langs) then
    H.error_treesitter('query', vim.tbl_keys(missing_query_langs))
  end

  return res
end

H.append_ranges = function(res, buf_id, query, captures, lang_tree)
  -- Compute ranges of matched captures
  local capture_is_requested = vim.tbl_map(function(c) return vim.tbl_contains(captures, '@' .. c) end, query.captures)

  for _, tree in ipairs(lang_tree:trees()) do
    -- TODO: Remove `opts.all`after compatibility with Neovim=0.10 is dropped
    for _, match, metadata in query:iter_matches(tree:root(), buf_id, nil, nil, { all = true }) do
      for capture_id, nodes in pairs(match) do
        local mt = metadata[capture_id]
        if capture_is_requested[capture_id] then table.insert(res, H.get_nodes_range_builtin(nodes, buf_id, mt)) end
      end
    end
  end
end

H.get_nodes_range_builtin = function(nodes, buf_id, metadata)
  -- In Neovim<0.10 `Query:iter_matches()` has `match` map to single node.
  -- TODO: Remove `opts.all`after compatibility with Neovim=0.9 is dropped
  nodes = type(nodes) == 'table' and nodes or { nodes }

  -- Get matched range as spanning from left most node start to right most node
  -- end. This accounts for several matched nodes that are intentionally there
  -- to cover complex cases. Approach is named "quantified captures".
  local left, right
  for _, node in ipairs(nodes) do
    local range = vim.treesitter.get_range(node, buf_id, metadata)
    if left == nil or range[3] < left[3] then left = range end
    if right == nil or range[6] > right[6] then right = range end
  end
  return { left[1], left[2], left[3], right[4], right[5], right[6] }
end

H.error_treesitter = function(failed_get, langs)
  local buf_id, ft = vim.api.nvim_get_current_buf(), vim.bo.filetype
  if langs == nil then
    local has_lang, ft_lang = pcall(vim.treesitter.language.get_lang, ft)
    -- `vim.treesitter.language.get_lang()` defaults to `ft` on Neovim>0.11
    -- TODO: Drop check after compatibility with Neovim=0.10 is dropped
    langs = (has_lang and ft_lang ~= nil) and { ft_lang } or { ft }
  end
  table.sort(langs)
  local langs_str = table.concat(vim.tbl_map(vim.inspect, langs), ', ')
  local langs_noun = #langs == 1 and 'language' or 'languages'
  local msg = string.format('Can not get %s for buffer %d and %s %s.', failed_get, buf_id, langs_noun, langs_str)
  H.error(msg)
end

-- Work with matching spans ---------------------------------------------------
---@param neighborhood table Output of `get_neighborhood()`.
---@param tobj_spec table Textobject specification.
---@param reference_span table Span to cover.
---@param opts table Fields: <search_method>.
---@private
H.find_best_match = function(neighborhood, tobj_spec, reference_span, opts)
  local best_span, best_nested_pattern, best_vis_mode, current_nested_pattern
  local f = function(span, vis_mode)
    if H.is_better_span(span, best_span, reference_span, opts) then
      best_span, best_nested_pattern, best_vis_mode = span, current_nested_pattern, vis_mode
    end
  end

  if H.is_region_array(tobj_spec) then
    -- Iterate over all spans representing regions in array
    for _, region in ipairs(tobj_spec) do
      -- Consider region only if it is completely within neighborhood
      if neighborhood.is_region_inside(region) then f(neighborhood.region_to_span(region), region.vis_mode) end
    end
  else
    -- Iterate over all matched spans
    for _, nested_pattern in ipairs(H.cartesian_product(tobj_spec)) do
      current_nested_pattern = nested_pattern
      H.iterate_matched_spans(neighborhood['1d'], nested_pattern, f)
    end
  end

  local extract_pattern
  if best_nested_pattern ~= nil then extract_pattern = best_nested_pattern[#best_nested_pattern] end
  return { span = best_span, vis_mode = best_vis_mode, extract_pattern = extract_pattern }
end

H.iterate_matched_spans = function(line, nested_pattern, f)
  local max_level = #nested_pattern
  -- Keep track of visited spans to ensure only one call of `f`.
  -- Example: `((a) (b))`, `{'%b()', '%b()'}`
  local visited = {}

  local process
  process = function(level, level_line, level_offset)
    local pattern = nested_pattern[level]
    local next_span = function(s, init) return H.string_find(s, pattern, init) end
    if vim.is_callable(pattern) then next_span = pattern end

    local is_same_balanced = type(pattern) == 'string' and pattern:match('^%%b(.)%1$') ~= nil
    local init = 1
    while init <= level_line:len() do
      local from, to = next_span(level_line, init)
      if from == nil then break end

      if level == max_level then
        local found_match = H.new_span(from + level_offset, to + level_offset)
        local found_match_id = string.format('%s_%s', found_match.from, found_match.to)
        if not visited[found_match_id] then
          f(found_match)
          visited[found_match_id] = true
        end
      else
        local next_level_line = level_line:sub(from, to)
        local next_level_offset = level_offset + from - 1
        process(level + 1, next_level_line, next_level_offset)
      end

      -- Start searching from right end to implement "balanced" pair.
      -- This doesn't work with regular balanced pattern because it doesn't
      -- capture nested brackets.
      init = (is_same_balanced and to or from) + 1
    end
  end

  process(1, line, 0)
end

-- NOTE: spans are end-exclusive to allow empty spans via `from == to`
H.new_span = function(from, to) return { from = from, to = to == nil and from or (to + 1) } end

---@param candidate table Candidate span to test against `current`.
---@param current table|nil Current best span.
---@param reference table Reference span to cover.
---@param opts table Fields: <search_method>.
---@private
H.is_better_span = function(candidate, current, reference, opts)
  -- Candidate should be never equal or nested inside reference
  if H.is_span_covering(reference, candidate) or H.is_span_equal(candidate, reference) then return false end

  return H.span_compare_methods[opts.search_method](candidate, current, reference)
end

H.span_compare_methods = {
  cover = function(candidate, current, reference)
    local res = H.is_better_covering_span(candidate, current, reference)
    if res ~= nil then return res end
    -- If both are not covering, `candidate` is not better (as it must cover)
    return false
  end,

  cover_or_next = function(candidate, current, reference)
    local res = H.is_better_covering_span(candidate, current, reference)
    if res ~= nil then return res end

    -- If not covering, `candidate` must be "next" and closer to reference
    if not H.is_span_on_left(reference, candidate) then return false end
    if current == nil then return true end

    local dist = H.span_distance.next
    return dist(candidate, reference) < dist(current, reference)
  end,

  cover_or_prev = function(candidate, current, reference)
    local res = H.is_better_covering_span(candidate, current, reference)
    if res ~= nil then return res end

    -- If not covering, `candidate` must be "previous" and closer to reference
    if not H.is_span_on_left(candidate, reference) then return false end
    if current == nil then return true end

    local dist = H.span_distance.prev
    return dist(candidate, reference) < dist(current, reference)
  end,

  cover_or_nearest = function(candidate, current, reference)
    local res = H.is_better_covering_span(candidate, current, reference)
    if res ~= nil then return res end

    -- If not covering, `candidate` must be closer to reference
    if current == nil then return true end

    local dist = H.span_distance.near
    return dist(candidate, reference) < dist(current, reference)
  end,

  next = function(candidate, current, reference)
    if H.is_span_covering(candidate, reference) then return false end

    -- `candidate` must be "next" and closer to reference
    if not H.is_span_on_left(reference, candidate) then return false end
    if current == nil then return true end

    local dist = H.span_distance.next
    return dist(candidate, reference) < dist(current, reference)
  end,

  prev = function(candidate, current, reference)
    if H.is_span_covering(candidate, reference) then return false end

    -- `candidate` must be "previous" and closer to reference
    if not H.is_span_on_left(candidate, reference) then return false end
    if current == nil then return true end

    local dist = H.span_distance.prev
    return dist(candidate, reference) < dist(current, reference)
  end,

  nearest = function(candidate, current, reference)
    if H.is_span_covering(candidate, reference) then return false end

    -- `candidate` must be closer to reference
    if current == nil then return true end

    local dist = H.span_distance.near
    return dist(candidate, reference) < dist(current, reference)
  end,
}

H.span_distance = {
  -- Other possible choices of distance between [a1, a2] and [b1, b2]:
  -- - Hausdorff distance: max(|a1 - b1|, |a2 - b2|).
  --   Source:
  --   https://math.stackexchange.com/questions/41269/distance-between-two-ranges
  -- - Minimum distance: min(|a1 - b1|, |a2 - b2|).

  -- Distance is chosen so that "next span" in certain direction is the closest
  next = function(span_1, span_2) return math.abs(span_1.from - span_2.from) end,
  prev = function(span_1, span_2) return math.abs(span_1.to - span_2.to) end,
  near = function(span_1, span_2) return math.min(math.abs(span_1.from - span_2.from), math.abs(span_1.to - span_2.to)) end,
}

H.is_better_covering_span = function(candidate, current, reference)
  local candidate_is_covering = H.is_span_covering(candidate, reference)
  local current_is_covering = H.is_span_covering(current, reference)

  if candidate_is_covering and current_is_covering then
    -- Covering candidate is better than covering current if it is narrower
    return (candidate.to - candidate.from) < (current.to - current.from)
  end
  if candidate_is_covering and not current_is_covering then return true end
  if not candidate_is_covering and current_is_covering then return false end

  -- Return `nil` if neither span is covering
  return nil
end

--stylua: ignore
H.is_span_covering = function(span, span_to_cover)
  if span == nil or span_to_cover == nil then return false end
  if span.from == span.to then
    return (span.from == span_to_cover.from) and (span_to_cover.to == span.to)
  end
  if span_to_cover.from == span_to_cover.to then
    return (span.from <= span_to_cover.from) and (span_to_cover.to < span.to)
  end

  return (span.from <= span_to_cover.from) and (span_to_cover.to <= span.to)
end

H.is_span_equal = function(span_1, span_2)
  if span_1 == nil or span_2 == nil then return false end
  return (span_1.from == span_2.from) and (span_1.to == span_2.to)
end

H.is_span_on_left = function(span_1, span_2)
  if span_1 == nil or span_2 == nil then return false end
  return (span_1.from <= span_2.from) and (span_1.to <= span_2.to)
end

H.is_span_inside_spans = function(ref_span, spans)
  for _, span in ipairs(spans) do
    if span[1] <= ref_span[1] and ref_span[2] <= span[2] then return true end
  end
  return false
end

-- Work with Lua patterns -----------------------------------------------------
H.extract_span = function(s, extract_pattern, ai_type)
  local positions = { s:match(extract_pattern) }

  if #positions == 1 and type(positions[1]) == 'string' then
    if s:len() == 0 then return H.new_span(0, 0) end
    return H.new_span(1, s:len())
  end

  local is_all_numbers = true
  for _, pos in ipairs(positions) do
    if type(pos) ~= 'number' then is_all_numbers = false end
  end

  local is_valid_positions = is_all_numbers and (#positions == 2 or #positions == 4)
  if not is_valid_positions then
    local msg = 'Could not extract proper positions (two or four empty captures) from '
      .. string.format([[string '%s' with extraction pattern '%s'.]], s, extract_pattern)
    H.error(msg)
  end

  local ai_spans
  if #positions == 2 then
    ai_spans = { a = H.new_span(1, s:len()), i = H.new_span(positions[1], positions[2] - 1) }
  else
    ai_spans = { a = H.new_span(positions[1], positions[4] - 1), i = H.new_span(positions[2], positions[3] - 1) }
  end

  return ai_spans[ai_type]
end

-- Work with cursor neighborhood ----------------------------------------------
---@param reference_region table Reference region.
---@param n_neighbors number Maximum number of neighbors to include before
---   start line and after end line.
---@private
H.get_neighborhood = function(reference_region, n_neighbors)
  -- Compute '2d neighborhood' of (possibly empty) region
  local from_line, to_line = reference_region.from.line, (reference_region.to or reference_region.from).line
  local line_start = math.max(1, from_line - n_neighbors)
  local line_end = math.min(vim.api.nvim_buf_line_count(0), to_line + n_neighbors)
  local neigh2d = vim.api.nvim_buf_get_lines(0, line_start - 1, line_end, false)
  -- Append 'newline' character to distinguish between lines in 1d case
  for k, v in pairs(neigh2d) do
    neigh2d[k] = v .. '\n'
  end

  -- '1d neighborhood': position is determined by offset from start
  local neigh1d = table.concat(neigh2d, '')

  -- Convert 2d buffer position to 1d offset
  local pos_to_offset = function(pos)
    if pos == nil then return nil end
    local line_num = line_start
    local offset = 0
    while line_num < pos.line do
      offset = offset + neigh2d[line_num - line_start + 1]:len()
      line_num = line_num + 1
    end

    return offset + pos.col
  end

  -- Convert 1d offset to 2d buffer position
  local offset_to_pos = function(offset)
    if offset == nil then return nil end
    local line_num = 1
    local line_offset = 0
    while line_num <= #neigh2d and line_offset + neigh2d[line_num]:len() < offset do
      line_offset = line_offset + neigh2d[line_num]:len()
      line_num = line_num + 1
    end

    return { line = line_start + line_num - 1, col = offset - line_offset }
  end

  -- Convert 2d region to 1d span
  local region_to_span = function(region)
    if region == nil then return nil end
    local is_empty = region.to == nil
    local to = region.to or region.from
    return { from = pos_to_offset(region.from), to = pos_to_offset(to) + (is_empty and 0 or 1) }
  end

  -- Convert 1d span to 2d region
  local span_to_region = function(span, vis_mode)
    if span == nil then return nil end
    -- NOTE: this might lead to outside of line positions due to added `\n` at
    -- the end of lines in 1d-neighborhood. However, this is crucial for
    -- allowing `i` textobjects to collapse multiline selections.
    local res = { from = offset_to_pos(span.from), vis_mode = vis_mode }

    -- Convert empty span to empty region
    if span.from < span.to then res.to = offset_to_pos(span.to - 1) end
    return res
  end

  local is_region_inside = function(region)
    local res = line_start <= region.from.line
    if region.to ~= nil then res = res and (region.to.line <= line_end) end
    return res
  end

  return {
    n_neighbors = n_neighbors,
    region = reference_region,
    ['1d'] = neigh1d,
    ['2d'] = neigh2d,
    pos_to_offset = pos_to_offset,
    offset_to_pos = offset_to_pos,
    region_to_span = region_to_span,
    span_to_region = span_to_region,
    is_region_inside = is_region_inside,
  }
end

-- Work with user input -------------------------------------------------------
H.user_textobject_id = function(ai_type)
  -- Get from user single character textobject identifier
  local needs_reminder = true
  vim.defer_fn(function()
    if not needs_reminder then return end

    local msg = string.format('Reminder to press `%s` textobject id ', ai_type)
    H.echo(msg)
    H.cache.msg_shown = true
  end, 1000)
  local ok, char = pcall(vim.fn.getcharstr)
  needs_reminder = false
  H.unecho()

  -- Terminate if couldn't get input (like with <C-c>) or it is `<Esc>`
  if not ok or char == '\27' then return nil end
  return char
end

H.user_input = function(prompt, text)
  -- Use `on_key` to distinguish cancel with `<Esc>` and immediate `<CR>`
  local was_cancelled = false
  vim.on_key(function(key) was_cancelled = was_cancelled or key == '\27' end, H.ns_id.input)

  -- Ask for input. Use `pcall` to allow `<C-c>` to cancel user input
  vim.cmd('echohl Question')
  local ok, res = pcall(vim.fn.input, { prompt = '(mini.ai) ' .. prompt .. ': ', default = text or '' })
  vim.cmd('echohl None | echo "" | redraw')

  vim.on_key(nil, H.ns_id.input)
  return (ok and not was_cancelled) and res or nil
end

-- Work with Visual mode ------------------------------------------------------
H.is_visual_mode = function(mode)
  mode = mode or vim.fn.mode()
  -- '\22' is an escaped `<C-v>`
  return mode == 'v' or mode == 'V' or mode == '\22', mode
end

H.exit_to_normal_mode = function()
  -- Don't use `<C-\><C-n>` in command-line window as they close it
  if vim.fn.getcmdwintype() ~= '' then
    local is_vis, cur_mode = H.is_visual_mode()
    if is_vis then vim.cmd('normal! ' .. cur_mode) end
  else
    -- '\28\14' is an escaped version of `<C-\><C-n>`
    vim.cmd('normal! \28\14')
  end
end

H.get_visual_region = function()
  local is_vis, _ = H.is_visual_mode()
  if not is_vis then return end
  local res = {
    from = { line = vim.fn.line('v'), col = vim.fn.col('v') },
    to = { line = vim.fn.line('.'), col = vim.fn.col('.') },
  }
  if res.from.line > res.to.line or (res.from.line == res.to.line and res.from.col > res.to.col) then
    res = { from = res.to, to = res.from }
  end
  return res
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.ai) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.echo = function(msg, is_important)
  if H.get_config().silent then return end

  -- Construct message chunks
  msg = type(msg) == 'string' and { { msg } } or msg
  table.insert(msg, 1, { '(mini.ai) ', 'WarningMsg' })

  -- Avoid hit-enter-prompt
  local max_width = vim.o.columns * math.max(vim.o.cmdheight - 1, 0) + vim.v.echospace
  local chunks, tot_width = {}, 0
  for _, ch in ipairs(msg) do
    local new_ch = { vim.fn.strcharpart(ch[1], 0, max_width - tot_width), ch[2] }
    table.insert(chunks, new_ch)
    tot_width = tot_width + vim.fn.strdisplaywidth(new_ch[1])
    if tot_width >= max_width then break end
  end

  -- Echo. Force redraw to ensure that it is effective (`:h echo-redraw`)
  vim.cmd([[echo '' | redraw]])
  vim.api.nvim_echo(chunks, is_important, {})
end

H.unecho = function()
  if H.cache.msg_shown then vim.cmd([[echo '' | redraw]]) end
end

H.message = function(msg) H.echo(msg, true) end

H.map = function(mode, lhs, rhs, opts)
  if lhs == '' then return end
  opts = vim.tbl_deep_extend('force', { silent = true }, opts or {})
  vim.keymap.set(mode, lhs, rhs, opts)
end

H.string_find = function(s, pattern, init)
  init = init or 1

  -- Match only start of full string if pattern says so.
  -- This is needed because `string.find()` doesn't do this.
  -- Example: `string.find('(aaa)', '^.*$', 4)` returns `4, 5`
  if pattern:sub(1, 1) == '^' then
    if init > 1 then return nil end
    return string.find(s, pattern)
  end

  -- Handle patterns `x.-y` differently: make match as small as possible. This
  -- doesn't allow `x` be present inside `.-` match, just as with `yyy`. Which
  -- also leads to a behavior similar to punctuation id (like with `va_`): no
  -- covering is possible, only next, previous, or nearest.
  local check_left, _, prev = string.find(pattern, '(.)%.%-')
  local is_pattern_special = check_left ~= nil and prev ~= '%'
  if not is_pattern_special then return string.find(s, pattern, init) end

  -- Make match as small as possible
  local from, to = string.find(s, pattern, init)
  if from == nil then return end

  local cur_from, cur_to = from, to
  while cur_to == to do
    from, to = cur_from, cur_to
    cur_from, cur_to = string.find(s, pattern, cur_from + 1)
  end

  return from, to
end

---@param arr table List of items. If item is list, consider as set for
---   product. Else - make it single item list.
---@private
H.cartesian_product = function(arr)
  if not (type(arr) == 'table' and #arr > 0) then return {} end
  arr = vim.tbl_map(function(x) return H.islist(x) and x or { x } end, arr)

  local res, cur_item = {}, {}
  local process
  process = function(level)
    for i = 1, #arr[level] do
      table.insert(cur_item, arr[level][i])
      if level == #arr then
        -- Flatten array to allow tables as elements of step tables
        table.insert(res, H.tbl_flatten(cur_item))
      else
        process(level + 1)
      end
      table.remove(cur_item, #cur_item)
    end
  end

  process(1)
  return res
end

H.wrap_callable_table = function(x)
  if vim.is_callable(x) and type(x) == 'table' then
    return function(...) return x(...) end
  end
  return x
end

-- TODO: Remove after compatibility with Neovim=0.9 is dropped
H.islist = vim.fn.has('nvim-0.10') == 1 and vim.islist or vim.tbl_islist
H.tbl_flatten = vim.fn.has('nvim-0.10') == 1 and function(x) return vim.iter(x):flatten(math.huge):totable() end
  or vim.tbl_flatten

return MiniAi
