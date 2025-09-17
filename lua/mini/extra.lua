--- *mini.extra* Extra 'mini.nvim' functionality
--- *MiniExtra*
---
--- MIT License Copyright (c) 2023 Evgeni Chasnovski
---
--- ==============================================================================
---
--- Extra useful functionality which is not essential enough for other 'mini.nvim'
--- modules to include directly.
---
--- Features:
---
--- - Various pickers for 'mini.pick':
---     - Built-in diagnostic (|MiniExtra.pickers.diagnostic()|).
---     - File explorer (|MiniExtra.pickers.explorer()|).
---     - Git branches/commits/files/hunks (|MiniExtra.pickers.git_hunks()|, etc.).
---     - Command/search/input history (|MiniExtra.pickers.history()|).
---     - LSP references/symbols/etc. (|MiniExtra.pickers.lsp()|).
---     - Tree-sitter nodes (|MiniExtra.pickers.treesitter()|).
---     - And much more.
---   See |MiniExtra.pickers| for more.
---
--- - Various textobject specifications for 'mini.ai'. See |MiniExtra.gen_ai_spec|.
---
--- - Various highlighters for 'mini.hipatterns'. See |MiniExtra.gen_highlighter|.
---
--- Notes:
--- - This module requires only those 'mini.nvim' modules which are needed for
---   a particular functionality: 'mini.pick' for pickers, etc.
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.extra').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `MiniExtra`
--- which you can use for scripting or manually (with `:lua MiniExtra.*`).
---
--- See |MiniExtra.config| for `config` structure and default values.
---
--- This module doesn't have runtime options, so using `vim.b.miniextra_config`
--- will have no effect here.
---
--- # Comparisons ~
---
--- - 'nvim-telescope/telescope.nvim':
---     - With |MiniExtra.pickers|, 'mini.pick' is reasonably on par when it comes
---       to built-in pickers.
---
--- - 'ibhagwan/fzf-lua':
---     - Same as 'nvim-telescope/telescope.nvim'.

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local
---@diagnostic disable:cast-local-type
---@diagnostic disable:undefined-doc-name
---@diagnostic disable:luadoc-miss-type-name

---@alias __extra_ai_spec_return function Function implementing |MiniAi-textobject-specification|.
---@alias __extra_pickers_local_opts table|nil Options defining behavior of this particular picker.
---@alias __extra_pickers_opts table|nil Options forwarded to |MiniPick.start()|.
---@alias __extra_pickers_return any Output of the called picker.
---@alias __extra_pickers_git_notes Notes:
--- - Requires executable `git`.
--- - Requires target path to be part of git repository.
--- - Present for exploration and navigation purposes. Doing any Git operations
---   is suggested to be done in a dedicated Git client and is not planned.
---@alias __extra_pickers_preserve_order - <preserve_order> `(boolean)` - whether to preserve original order
---     during query. Default: `false`.
---@alias __extra_pickers_git_path - <path> `(string|nil)` - target path for Git operation (if required). Also
---     used to find Git repository inside which to construct items.
---     Default: `nil` for root of Git repository containing |current-directory|.

-- Module definition ==========================================================
local MiniExtra = {}
local H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniExtra.config|.
---
---@usage >lua
---   require('mini.extra').setup() -- use default config
---   -- OR
---   require('mini.extra').setup({}) -- replace {} with your config table
--- <
MiniExtra.setup = function(config)
  -- Export module
  _G.MiniExtra = MiniExtra

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)
end

--stylua: ignore
--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
MiniExtra.config = {}
--minidoc_afterlines_end

--- 'mini.ai' textobject specification generators
---
--- This is a table with function elements. Call to actually get specification.
---
--- Assumed to be used as part of |MiniAi.setup()|. Example: >lua
---
---   local gen_ai_spec = require('mini.extra').gen_ai_spec
---   require('mini.ai').setup({
---     custom_textobjects = {
---       B = gen_ai_spec.buffer(),
---       D = gen_ai_spec.diagnostic(),
---       I = gen_ai_spec.indent(),
---       L = gen_ai_spec.line(),
---       N = gen_ai_spec.number(),
---     },
---   })
--- <
MiniExtra.gen_ai_spec = {}

--- Current buffer textobject
---
--- Notes:
--- - `a` textobject selects all lines in a buffer.
--- - `i` textobject selects all lines except blank lines at start and end.
---
---@return __extra_ai_spec_return
MiniExtra.gen_ai_spec.buffer = function()
  return function(ai_type)
    local start_line, end_line = 1, vim.fn.line('$')
    if ai_type == 'i' then
      -- Skip first and last blank lines for `i` textobject
      local first_nonblank, last_nonblank = vim.fn.nextnonblank(start_line), vim.fn.prevnonblank(end_line)
      -- Do nothing for buffer with all blanks
      if first_nonblank == 0 or last_nonblank == 0 then return { from = { line = start_line, col = 1 } } end
      start_line, end_line = first_nonblank, last_nonblank
    end

    local to_col = math.max(vim.fn.getline(end_line):len(), 1)
    return { from = { line = start_line, col = 1 }, to = { line = end_line, col = to_col } }
  end
end

--- Current buffer diagnostic textobject
---
--- Notes:
--- - Both `a` and `i` textobjects return |vim.diagnostic.get()| output for the
---   current buffer. It is modified to fit |MiniAi-textobject-specification|.
---
---@param severity any Which severity to use. Forwarded to |vim.diagnostic.get()|.
---   Default: `nil` to use all diagnostic entries.
---
---@return __extra_ai_spec_return
MiniExtra.gen_ai_spec.diagnostic = function(severity)
  return function(ai_type)
    local cur_diag = vim.diagnostic.get(0, { severity = severity })

    local regions = {}
    for _, diag in ipairs(cur_diag) do
      local from = { line = diag.lnum + 1, col = diag.col + 1 }
      local to = { line = diag.end_lnum + 1, col = diag.end_col }
      if to.line == nil or to.col == nil then to = { line = diag.lnum + 1, col = diag.col + 1 } end
      table.insert(regions, { from = from, to = to })
    end
    return regions
  end
end

--- Current buffer indent scopes textobject
---
--- Indent scope is a set of consecutive lines with the following properties:
--- - Lines above first and below last are non-blank. They are called borders.
--- - There is at least one non-blank line in a set.
--- - All non-blank lines between borders have strictly greater indent
---   (perceived leading space respecting |tabstop|) than either of borders.
---
--- Notes:
--- - `a` textobject selects scope including borders.
--- - `i` textobject selects the scope charwise.
--- - Differences with |MiniIndentscope.textobject|:
---     - This textobject always treats blank lines on top and bottom of `i`
---       textobject as part of it, while 'mini.indentscope' can configure that.
---     - This textobject can select non-covering scopes, while 'mini.indentscope'
---       can not (by design).
---     - In this textobject scope computation is done only by "casting rays" from
---       top to bottom and not in both ways as in 'mini.indentscope'.
---       This works in most common scenarios and doesn't work only if indent of
---       of the bottom border is expected to be larger than the top.
---
---@return function Function implementing |MiniAi-textobject-specification|.
---   It returns array of regions representing all indent scopes in the buffer
---   ordered increasingly by the start line.
MiniExtra.gen_ai_spec.indent = function() return H.ai_indent_spec end

--- Current line textobject
---
--- Notes:
--- - `a` textobject selects whole line.
--- - `i` textobject selects line after initial indent.
---
---@return __extra_ai_spec_return
MiniExtra.gen_ai_spec.line = function()
  return function(ai_type)
    local line_num = vim.fn.line('.')
    local line = vim.fn.getline(line_num)
    -- Ignore indentation for `i` textobject
    local from_col = ai_type == 'a' and 1 or (line:match('^(%s*)'):len() + 1)
    -- Don't select `\n` past the line to operate within a line
    local to_col = line:len()

    return { from = { line = line_num, col = from_col }, to = { line = line_num, col = to_col } }
  end
end

--- Number textobject
---
--- Notes:
--- - `a` textobject selects a whole number possibly preceded with "-" and
---   possibly followed by decimal part (dot and digits).
--- - `i` textobject selects consecutive digits.
---
---@return __extra_ai_spec_return
MiniExtra.gen_ai_spec.number = function()
  local digits_pattern = '%f[%d]%d+%f[%D]'

  local find_a_number = function(line, init)
    -- First find consecutive digits
    local from, to = line:find(digits_pattern, init)
    if from == nil then return nil, nil end

    -- Make sure that these digits were not processed before. This can happen
    -- because 'miin.ai' does next with `init = from + 1`, meaning that
    -- "-12.34" was already matched, then it would try to match starting from
    -- "1": we want to avoid matching that right away and avoid matching "34"
    -- from this number.
    if from == init and line:sub(from - 1, from - 1) == '-' then
      init = to + 1
      from, to = line:find(digits_pattern, init)
    end
    if from == nil then return nil, nil end

    if line:sub(from - 2):find('^%d%.') ~= nil then
      init = to + 1
      from, to = line:find(digits_pattern, init)
    end
    if from == nil then return nil, nil end

    -- Match the whole number with minus and decimal part
    if line:sub(from - 1, from - 1) == '-' then from = from - 1 end
    local dec_part = line:sub(to + 1):match('^%.%d+()')
    if dec_part ~= nil then to = to + dec_part - 1 end
    return from, to
  end

  return function(ai_type)
    if ai_type == 'i' then return { digits_pattern } end
    return { find_a_number, { '^().*()$' } }
  end
end

--- 'mini.hipatterns' highlighter generators
---
--- This is a table with function elements. Call to actually get specification.
---
--- Assumed to be used as part of |MiniHipatterns.setup()|. Example: >lua
---
---   local hi_words = require('mini.extra').gen_highlighter.words
---   require('mini.hipatterns').setup({
---     highlighters = {
---       todo = hi_words({ 'TODO', 'Todo', 'todo' }, 'MiniHipatternsTodo'),
---     },
---   })
--- <
MiniExtra.gen_highlighter = {}

--- Highlight words
---
--- Notes:
--- - Words should start and end with alphanumeric symbol (latin letter or digit).
--- - Words will be highlighted only in full and not if part bigger word, i.e.
---   there should not be alphanumeric symbol before and after it.
---
---@param words table Array of words to highlight. Will be matched as is, not
---   as Lua pattern.
---@param group string|function Proper `group` field for `highlighter`.
---   See |MiniHipatterns.config|.
---@param extmark_opts any Proper `extmark_opts` field for `highlighter`.
---   See |MiniHipatterns.config|.
MiniExtra.gen_highlighter.words = function(words, group, extmark_opts)
  if not H.islist(words) then H.error('`words` should be an array.') end
  if not (type(group) == 'string' or vim.is_callable(group)) then H.error('`group` should be string or callable.') end
  local pattern = vim.tbl_map(function(x)
    if type(x) ~= 'string' then H.error('All elements of `words` should be strings.') end
    return '%f[%w]()' .. vim.pesc(x) .. '()%f[%W]'
  end, words)
  return { pattern = pattern, group = group, extmark_opts = extmark_opts }
end

--- 'mini.pick' pickers
---
--- A table with |MiniPick| pickers (which is a hard dependency).
--- Notes:
--- - All have the same signature:
---     - <local_opts> - optional table with options local to picker.
---     - <opts> - optional table with options forwarded to |MiniPick.start()|.
--- - All of them are automatically registered in |MiniPick.registry| inside
---   both |MiniExtra.setup()| or |MiniPick.setup()| (only one is enough).
--- - All use default versions of |MiniPick-source.preview|, |MiniPick-source.choose|,
---   and |MiniPick-source.choose_marked| if not stated otherwise.
---   Shown text and |MiniPick-source.show| are targeted to the picked items.
---
--- Examples of usage:
--- - As Lua code: `MiniExtra.pickers.buf_lines()`.
--- - With |:Pick| command: `:Pick buf_lines scope='current'`
---   Note: this requires calling |MiniExtra.setup()|.
MiniExtra.pickers = {}

--- Buffer lines picker
---
--- Pick from buffer lines. Notes:
--- - Loads all target buffers which are currently unloaded.
---
---@param local_opts __extra_pickers_local_opts
---   Possible fields:
---   - <scope> `(string)` - one of "all" (normal listed buffers) or "current".
---     Default: "all".
---   __extra_pickers_preserve_order
---@param opts __extra_pickers_opts
---
---@return __extra_pickers_return
MiniExtra.pickers.buf_lines = function(local_opts, opts)
  local pick = H.validate_pick('buf_lines')
  local_opts = vim.tbl_deep_extend('force', { scope = 'all', preserve_order = false }, local_opts or {})

  local scope = H.pick_validate_scope(local_opts, { 'all', 'current' }, 'buf_lines')
  local is_scope_all = scope == 'all'

  -- Define non-blocking callable `items` because getting all lines from all
  -- buffers (plus loading them) may take visibly long time
  local buffers = {}
  if is_scope_all then
    for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
      if vim.bo[buf_id].buflisted and vim.bo[buf_id].buftype == '' then table.insert(buffers, buf_id) end
    end
  else
    buffers = { vim.api.nvim_get_current_buf() }
  end

  local poke_picker = pick.poke_is_picker_active
  local f = function()
    local items = {}
    for _, buf_id in ipairs(buffers) do
      if not poke_picker() then return end
      H.buf_ensure_loaded(buf_id)
      local buf_name = H.buf_get_name(buf_id) or ''
      local n_digits = math.floor(math.log10(vim.api.nvim_buf_line_count(buf_id))) + 1
      local format_pattern = '%s%' .. n_digits .. 'd\0%s'
      for lnum, l in ipairs(vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)) do
        local prefix = is_scope_all and (buf_name .. '\0') or ''
        table.insert(items, { text = format_pattern:format(prefix, lnum, l), bufnr = buf_id, lnum = lnum })
      end
    end
    pick.set_picker_items(items)
  end
  local items = vim.schedule_wrap(coroutine.wrap(f))

  local show = H.pick_get_config().source.show
  if is_scope_all and show == nil then show = H.show_with_icons end
  local match_opts = { preserve_order = local_opts.preserve_order }
  local match = function(stritems, inds, query) pick.default_match(stritems, inds, query, match_opts) end
  local default_source = { name = string.format('Buffer lines (%s)', scope), show = show, match = match }
  return H.pick_start(items, { source = default_source }, opts)
end

--- Color scheme picker
---
--- Pick and apply color scheme. Preview temporarily applies item's color scheme
--- and shows how selected highlight groups look.
--- Canceling reverts to color scheme before picker start:
--- - With |MiniColors-colorscheme:apply()| if |mini.colors| was available.
--- - With |:colorscheme| if |g:colors_name| was available.
---
---@param local_opts __extra_pickers_local_opts
---   Possible fields:
---   - <names> `(table)` - array of color scheme names to pick from.
---     Default: all available color schemes.
---   - <preview_hl_groups> `(table)` - array of highlight groups to show in preview
---     window. Default: all defined highlight groups in alphabetical order.
---
---@param opts __extra_pickers_opts
---
---@return __extra_pickers_return
MiniExtra.pickers.colorschemes = function(local_opts, opts)
  local pick = H.validate_pick('colorschemes')
  local_opts = local_opts or {}

  -- Infer data to show
  local all_cs = vim.fn.getcompletion('', 'color')
  local items = local_opts.names or all_cs
  if not H.islist(items) then H.error('`names` should be array of color scheme names') end
  for _, item in ipairs(items) do
    if not vim.tbl_contains(all_cs, item) then H.error(vim.inspect(item) .. ' is not a color scheme name') end
  end

  local hl_groups = local_opts.preview_hl_groups
  if hl_groups ~= nil and not H.islist(hl_groups) then H.error('`preview_hl_groups` should be array') end

  -- Compute original color scheme to restore
  local bg_orig = vim.o.background
  local has_minicolors, minicolors = pcall(require, 'mini.colors')
  local cs_orig = has_minicolors and minicolors.get_colorscheme() or vim.g.colors_name
  local restore = function()
    vim.o.background = bg_orig
    if cs_orig == nil then return end
    if type(cs_orig) == 'string' then return vim.cmd('colorscheme ' .. cs_orig) end
    cs_orig:apply()
    -- Trigger to indicate actual color scheme application
    vim.api.nvim_exec_autocmds('ColorScheme', {})
  end

  -- Define source
  local choose = function(item) vim.cmd('colorscheme ' .. item) end
  local choose_marked = function(items_to_mark) choose(items_to_mark[1] or '') end

  local needs_restore = false
  local preview = function(buf_id, item)
    needs_restore = true
    -- Ensure that previewed color scheme tries to use the initial background.
    -- This can be not the case if previous preview forced new background.
    vim.o.background = bg_orig
    vim.cmd('colorscheme ' .. item)
    H.preview_cs_hl_groups(buf_id, hl_groups)
  end

  local default_source = { name = 'Colorschemes', preview = preview, choose = choose, choose_marked = choose_marked }
  local result = H.pick_start(items, { source = default_source }, opts)

  if result == nil and needs_restore then restore() end
  return result
end

--- Neovim commands picker
---
--- Pick from Neovim built-in (|ex-commands|) and |user-commands|.
--- Notes:
--- - Preview shows information about the command (if available).
--- - Choosing either executes command (if reliably known that it doesn't need
---   arguments) or populates Command line with the command.
---
---@param local_opts __extra_pickers_local_opts
---   Not used at the moment.
---@param opts __extra_pickers_opts
---
---@return __extra_pickers_return
MiniExtra.pickers.commands = function(local_opts, opts)
  local pick = H.validate_pick('commands')

  local commands = vim.tbl_deep_extend('force', vim.api.nvim_get_commands({}), vim.api.nvim_buf_get_commands(0, {}))

  local preview = function(buf_id, item)
    local data = commands[item]
    local lines = data == nil and { string.format('No command data for `%s` is yet available.', item) }
      or vim.split(vim.inspect(data), '\n')
    H.set_buflines(buf_id, lines)
  end

  local choose = function(item)
    local data = commands[item] or {}
    -- If no arguments needed, execute immediately
    local keys = string.format(':%s%s', item, data.nargs == '0' and '\r' or ' ')
    vim.schedule(function() vim.fn.feedkeys(keys) end)
  end

  local items = vim.fn.getcompletion('', 'command')
  local default_opts = { source = { name = 'Commands', preview = preview, choose = choose } }
  return H.pick_start(items, default_opts, opts)
end

--- Built-in diagnostic picker
---
--- Pick from |vim.diagnostic| using |vim.diagnostic.get()|.
---
---@param local_opts __extra_pickers_local_opts
---   Possible fields:
---   - <get_opts> `(table)` - options for |vim.diagnostic.get()|. Can be used
---     to limit severity or namespace. Default: `{}`.
---   - <scope> `(string)` - one of "all" (available) or "current" (buffer).
---     Default: "all".
---   - <sort_by> `(string)` - sort priority. One of "severity", "path", "none".
---     Default: "severity".
---@param opts __extra_pickers_opts
---
---@return __extra_pickers_return
MiniExtra.pickers.diagnostic = function(local_opts, opts)
  local pick = H.validate_pick('diagnostic')
  local_opts = vim.tbl_deep_extend('force', { get_opts = {}, scope = 'all', sort_by = 'severity' }, local_opts or {})

  local scope = H.pick_validate_scope(local_opts, { 'all', 'current' }, 'diagnostic')
  local sort_by = H.pick_validate_one_of('sort_by', local_opts, { 'severity', 'path', 'none' }, 'diagnostic')

  local plus_one = function(x)
    if x == nil then return nil end
    return x + 1
  end

  local diag_buf_id
  if scope == 'current' then diag_buf_id = vim.api.nvim_get_current_buf() end
  local items = vim.deepcopy(vim.diagnostic.get(diag_buf_id, local_opts.get_opts))

  -- Compute final path width
  local path_width = 0
  for _, item in ipairs(items) do
    item.path = H.buf_get_name(item.bufnr) or ''
    item.severity = item.severity or 0
    path_width = math.max(path_width, vim.fn.strchars(item.path))
  end

  -- Sort
  local compare = H.diagnostic_make_compare(sort_by)
  if vim.is_callable(compare) then table.sort(items, compare) end

  -- Update items
  for _, item in ipairs(items) do
    local severity = vim.diagnostic.severity[item.severity] or ' '
    local text = item.message:gsub('\n', ' ')
    item.text = string.format('%s │ %s │ %s', severity:sub(1, 1), H.ensure_text_width(item.path, path_width), text)
    item.lnum, item.col, item.end_lnum, item.end_col =
      plus_one(item.lnum), plus_one(item.col), plus_one(item.end_lnum), plus_one(item.end_col)
  end

  local hl_groups_ref = {
    [vim.diagnostic.severity.ERROR] = 'DiagnosticFloatingError',
    [vim.diagnostic.severity.WARN] = 'DiagnosticFloatingWarn',
    [vim.diagnostic.severity.INFO] = 'DiagnosticFloatingInfo',
    [vim.diagnostic.severity.HINT] = 'DiagnosticFloatingHint',
  }

  -- Define source
  local show = function(buf_id, items_to_show, query)
    pick.default_show(buf_id, items_to_show, query)

    H.pick_clear_namespace(buf_id, H.ns_id.pickers)
    for i, item in ipairs(items_to_show) do
      H.pick_highlight_line(buf_id, i, hl_groups_ref[item.severity], 199)
    end
  end

  local name = string.format('Diagnostic (%s)', scope)
  return H.pick_start(items, { source = { name = name, choose = H.choose_with_buflisted, show = show } }, opts)
end

--- File explorer picker
---
--- Explore file system and open file.
--- Notes:
--- - Choosing a directory navigates inside it, changing picker's items and
---   current working directory.
--- - Query and preview work as usual (not only `move_next`/`move_prev` can be used).
--- - Preview works for any item.
---
--- Examples ~
---
--- - `MiniExtra.pickers.explorer()`
--- - `:Pick explorer cwd='..'` - open explorer in parent directory.
---
---@param local_opts __extra_pickers_local_opts
---   Possible fields:
---   - <cwd> `(string)` - initial directory to explore. Should be a valid
---     directory path. Default: `nil` for |current-directory|.
---   - <filter> `(function)` - callable predicate to filter items to show.
---     Will be called for every item and should return `true` if it should be
---     shown. Each item is a table with the following fields:
---       - <fs_type> `(string)` - path type. One of "directory" or "file".
---       - <path> `(string)` - item path.
---       - <text> `(string)` - shown text (path's basename).
---   - <sort> `(function)` - callable item sorter. Will be called with array
---     of items (each element with structure as described above) and should
---     return sorted array of items.
---@param opts __extra_pickers_opts
---
---@return __extra_pickers_return
MiniExtra.pickers.explorer = function(local_opts, opts)
  local pick = H.validate_pick('explorer')

  local_opts = vim.tbl_deep_extend('force', { cwd = nil, filter = nil, sort = nil }, local_opts or {})
  local cwd = local_opts.cwd or vim.fn.getcwd()
  if vim.fn.isdirectory(cwd) == 0 then H.error('`local_opts.cwd` should be valid directory path.') end
  -- - Call twice "full path" to make sure that possible '..' are collapsed
  cwd = H.full_path(vim.fn.fnamemodify(cwd, ':p'))
  local filter = local_opts.filter or function() return true end
  if not vim.is_callable(filter) then H.error('`local_opts.filter` should be callable.') end
  local sort = local_opts.sort or H.explorer_default_sort
  if not vim.is_callable(sort) then H.error('`local_opts.sort` should be callable.') end

  -- Define source
  local choose = function(item)
    local path = item.path
    if vim.fn.filereadable(path) == 1 then return pick.default_choose(path) end
    if vim.fn.isdirectory(path) == 0 then return false end

    pick.set_picker_items(H.explorer_make_items(path, filter, sort))
    pick.set_picker_opts({ source = { cwd = path } })
    pick.set_picker_query({})
    return true
  end

  local show = H.pick_get_config().source.show or H.show_with_icons

  local items = H.explorer_make_items(cwd, filter, sort)
  local source = { items = items, name = 'File explorer', cwd = cwd, show = show, choose = choose }
  opts = vim.tbl_deep_extend('force', { source = source }, opts or {})
  return pick.start(opts)
end

--- Git branches picker
---
--- Pick from Git branches using `git branch`.
--- __extra_pickers_git_notes
--- - On choose opens scratch buffer with branch's history.
---
--- Examples ~
---
--- - `MiniExtra.pickers.git_branches({ scope = 'local' })` - local branches of
---   the |current-directory| parent Git repository.
--- - `:Pick git_branches path='%'` - all branches of the current file parent
---   Git repository.
---
---@param local_opts __extra_pickers_local_opts
---   Possible fields:
---   __extra_pickers_git_path
---   - <scope> `(string)` - branch scope to show. One of "all", "local", "remotes".
---     Default: "all".
---@param opts __extra_pickers_opts
---
---@return __extra_pickers_return
MiniExtra.pickers.git_branches = function(local_opts, opts)
  local pick = H.validate_pick('git_branches')
  H.validate_git('git_branches')

  local_opts = vim.tbl_deep_extend('force', { path = nil, scope = 'all' }, local_opts or {})

  local scope = H.pick_validate_scope(local_opts, { 'all', 'local', 'remotes' }, 'git_branches')

  -- Compute path to repo with target path (as it might differ from current)
  local path, path_type = H.git_normalize_path(local_opts.path, 'git_branches')
  local repo_dir = H.git_get_repo_dir(path, path_type, 'git_branches')

  -- Define source
  local preview = function(buf_id, item)
    local branch = item:match('^%*?%s*(%S+)')
    H.cli_show_output(buf_id, { 'git', '-C', repo_dir, 'log', branch, '--format=format:%h %s' })
  end
  local choose = function(item)
    local win_target = (pick.get_picker_state().windows or {}).target
    if win_target == nil or not H.is_valid_win(win_target) then return end
    local buf_id = vim.api.nvim_create_buf(true, true)
    H.set_buf_name(buf_id, item:match('^%*?%s*(%S+)'))
    preview(buf_id, item)
    vim.api.nvim_win_set_buf(win_target, buf_id)
  end

  local command = { 'git', 'branch', '-v', '--no-color', '--list' }
  if scope == 'all' or scope == 'remotes' then table.insert(command, 3, '--' .. scope) end

  local name = string.format('Git branches (%s)', scope)
  local default_source = { name = name, cwd = repo_dir, preview = preview, choose = choose }
  opts = vim.tbl_deep_extend('force', { source = default_source }, opts or {})
  return pick.builtin.cli({ command = command }, opts)
end

--- Git commits picker
---
--- Pick from Git commits using `git log`.
--- __extra_pickers_git_notes
--- - On choose opens scratch buffer with commit's diff.
---
--- Examples ~
---
--- - `MiniExtra.pickers.git_commits()` - all commits from parent Git
---   repository of |current-directory|.
--- - `MiniExtra.pickers.git_commits({ path = 'subdir' })` - commits affecting
---   files from 'subdir' subdirectory.
--- - `:Pick git_commits path='%'` commits affecting current file.
---
---@param local_opts __extra_pickers_local_opts
---   Possible fields:
---   __extra_pickers_git_path
---@param opts __extra_pickers_opts
---
---@return __extra_pickers_return
MiniExtra.pickers.git_commits = function(local_opts, opts)
  local pick = H.validate_pick('git_commits')
  H.validate_git('git_commits')

  local_opts = vim.tbl_deep_extend('force', { path = nil }, local_opts or {})

  -- Compute path to repo with target path (as it might differ from current)
  local path, path_type = H.git_normalize_path(local_opts.path, 'git_commits')
  local repo_dir = H.git_get_repo_dir(path, path_type, 'git_commits')
  if local_opts.path == nil then path = repo_dir end

  -- Define source
  local preview = function(buf_id, item)
    if type(item) ~= 'string' then return end
    local has_parser, parser = pcall(vim.treesitter.get_parser, buf_id, 'git', { error = false })
    has_parser = has_parser and parser ~= nil
    if has_parser then has_parser = pcall(vim.treesitter.start, buf_id, 'git') end
    if not has_parser then vim.bo[buf_id].syntax = 'git' end
    H.cli_show_output(buf_id, { 'git', '-C', repo_dir, '--no-pager', 'show', item:match('^(%S+)') })
  end
  local choose = function(item)
    local win_target = (pick.get_picker_state().windows or {}).target
    if win_target == nil or not H.is_valid_win(win_target) then return end
    local buf_id = vim.api.nvim_create_buf(true, true)
    H.set_buf_name(buf_id, item:match('^(%S+)'))
    preview(buf_id, item)
    -- Set filetype on opened buffer to trigger appropriate `FileType` event
    vim.bo[buf_id].filetype = 'git'
    vim.api.nvim_win_set_buf(win_target, buf_id)
  end

  local command = { 'git', 'log', [[--format=format:%h %s]], '--', path }

  local name = string.format('Git commits (%s)', local_opts.path == nil and 'all' or 'for path')
  local default_source = { name = name, cwd = repo_dir, preview = preview, choose = choose }
  opts = vim.tbl_deep_extend('force', { source = default_source }, opts or {})
  return pick.builtin.cli({ command = command }, opts)
end

--- Git files picker
---
--- Pick from Git files using `git ls-files`.
--- __extra_pickers_git_notes
---
--- Examples ~
---
--- - `MiniExtra.pickers.git_files({ scope = 'ignored' })` - ignored files from
---   parent Git repository of |current-directory|.
--- - `:Pick git_files path='subdir' scope='modified'` - files from 'subdir'
---   subdirectory which are ignored by Git.
---
---@param local_opts __extra_pickers_local_opts
---   Possible fields:
---   __extra_pickers_git_path
---   - <scope> `(string)` - files scope to show. One of
---       - "tracked"   (`--cached`   Git flag).
---       - "modified"  (`--modified` Git flag).
---       - "untracked" (`--others`   Git flag).
---       - "ignored"   (`--ignored`  Git flag).
---       - "deleted"   (`--deleted`  Git flag).
---     Default: "tracked".
---@param opts __extra_pickers_opts
---
---@return __extra_pickers_return
MiniExtra.pickers.git_files = function(local_opts, opts)
  local pick = H.validate_pick('git_files')
  H.validate_git('git_files')

  local_opts = vim.tbl_deep_extend('force', { path = nil, scope = 'tracked' }, local_opts or {})
  local allowed_scope = { 'tracked', 'modified', 'untracked', 'ignored', 'deleted' }
  local scope = H.pick_validate_scope(local_opts, allowed_scope, 'git_files')

  -- Compute path to repo with target path (as it might differ from current)
  local path, path_type = H.git_normalize_path(local_opts.path, 'git_files')
  H.git_get_repo_dir(path, path_type, 'git_files')
  local path_dir = path_type == 'directory' and path or vim.fn.fnamemodify(path, ':h')

  -- Define source
  local show = H.pick_get_config().source.show or H.show_with_icons

  --stylua: ignore
  local command = ({
    tracked   = { 'git', '-C', path_dir, 'ls-files', '--cached' },
    modified  = { 'git', '-C', path_dir, 'ls-files', '--modified' },
    untracked = { 'git', '-C', path_dir, 'ls-files', '--others' },
    ignored   = { 'git', '-C', path_dir, 'ls-files', '--others', '--ignored', '--exclude-standard' },
    deleted   = { 'git', '-C', path_dir, 'ls-files', '--deleted' },
  })[local_opts.scope]

  local name = string.format('Git files (%s)', local_opts.scope)
  local default_source = { name = name, cwd = path_dir, show = show }
  opts = vim.tbl_deep_extend('force', { source = default_source }, opts or {})
  return pick.builtin.cli({ command = command }, opts)
end

--- Git hunks picker
---
--- Pick from Git hunks using `git diff`.
--- __extra_pickers_git_notes
--- - On choose navigates to hunk's first change.
---
--- Examples ~
---
--- - `MiniExtra.pickers.git_hunks({ scope = 'staged' })` - staged hunks from
---   parent Git repository of |current-directory|.
--- - `:Pick git_hunks path='%' n_context=0` - hunks from current file computed
---   with no context.
---
---@param local_opts __extra_pickers_local_opts
---   Possible fields:
---   - <n_context> `(number)` - number of context lines to show in hunk's preview.
---     Default: 3.
---   __extra_pickers_git_path
---   - <scope> `(string)` - hunks scope to show. One of "unstaged" or "staged".
---     Default: "unstaged".
---@param opts __extra_pickers_opts
---
---@return __extra_pickers_return
MiniExtra.pickers.git_hunks = function(local_opts, opts)
  local pick = H.validate_pick('git_hunks')
  H.validate_git('git_hunks')

  local default_local_opts = { n_context = 3, path = nil, scope = 'unstaged' }
  local_opts = vim.tbl_deep_extend('force', default_local_opts, local_opts or {})

  if not (type(local_opts.n_context) == 'number' and local_opts.n_context >= 0) then
    H.error('`n_context` option in `pickers.git_hunks` picker should be non-negative number.')
  end
  local n_context = math.floor(local_opts.n_context)
  local scope = H.pick_validate_scope(local_opts, { 'unstaged', 'staged' }, 'git_hunks')

  -- Compute path to repo with target path (as it might differ from current)
  local path, path_type = H.git_normalize_path(local_opts.path, 'git_hunks')
  local repo_dir = H.git_get_repo_dir(path, path_type, 'git_hunks')
  if local_opts.path == nil then path = repo_dir end

  -- Define source
  local show = H.pick_get_config().source.show or H.show_with_icons
  local preview = function(buf_id, item)
    local has_parser, parser = pcall(vim.treesitter.get_parser, buf_id, 'diff', { error = false })
    has_parser = has_parser and parser ~= nil
    if has_parser then has_parser = pcall(vim.treesitter.start, buf_id, 'diff') end
    if not has_parser then vim.bo[buf_id].syntax = 'diff' end
    local lines = vim.deepcopy(item.header)
    vim.list_extend(lines, item.hunk)
    H.set_buflines(buf_id, lines)
  end

  local command = { 'git', 'diff', '--patch', '--unified=' .. n_context, '--color=never', '--', path }
  if scope == 'staged' then table.insert(command, 4, '--cached') end

  local postprocess = function(lines) return H.git_difflines_to_hunkitems(lines, n_context) end

  local name = string.format('Git hunks (%s %s)', scope, local_opts.path == nil and 'all' or 'for path')
  local default_source = { name = name, cwd = repo_dir, show = show, preview = preview }
  opts = vim.tbl_deep_extend('force', { source = default_source }, opts or {})
  return pick.builtin.cli({ command = command, postprocess = postprocess }, opts)
end

--- Matches from 'mini.hipatterns' picker
---
--- Pick from |MiniHipatterns| matches using |MiniHipatterns.get_matches()|.
--- Notes:
--- - Requires 'mini.hipatterns'.
--- - Highlighter identifier is highlighted with its highlight group.
---
---@param local_opts __extra_pickers_local_opts
---   Possible fields:
---   - <scope> `(string)` - one of "all" (buffers with enabled 'mini.hipatterns')
---     or "current" (buffer). Default: "all".
---   - <highlighters> `(table|nil)` - highlighters for which to find matches.
---     Forwarded to |MiniHipatterns.get_matches()|. Default: `nil`.
---@param opts __extra_pickers_opts
---
---@return __extra_pickers_return
MiniExtra.pickers.hipatterns = function(local_opts, opts)
  local pick = H.validate_pick('hipatterns')
  local has_hipatterns, hipatterns = pcall(require, 'mini.hipatterns')
  if not has_hipatterns then H.error([[`pickers.hipatterns` requires 'mini.hipatterns' which can not be found.]]) end

  local_opts = vim.tbl_deep_extend('force', { highlighters = nil, scope = 'all' }, local_opts or {})
  if local_opts.highlighters ~= nil and not H.islist(local_opts.highlighters) then
    H.error('`local_opts.highlighters` should be an array of highlighter identifiers.')
  end
  local highlighters = local_opts.highlighters
  local scope = H.pick_validate_scope(local_opts, { 'all', 'current' }, 'hipatterns')

  -- Get items
  local buffers = scope == 'all' and hipatterns.get_enabled_buffers() or { vim.api.nvim_get_current_buf() }
  local items, highlighter_width = {}, 0
  for _, buf_id in ipairs(buffers) do
    local lines = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)
    local buf_name = H.buf_get_name(buf_id)
    if buf_name == '' then buf_name = 'Buffer_' .. buf_id end

    for _, match in ipairs(hipatterns.get_matches(buf_id, highlighters)) do
      match.highlighter = tostring(match.highlighter)
      match.buf_name, match.line = buf_name, lines[match.lnum]
      table.insert(items, match)
      highlighter_width = math.max(highlighter_width, vim.fn.strchars(match.highlighter))
    end
  end

  for _, item in ipairs(items) do
    --stylua: ignore
    item.text = string.format(
      '%s │ %s│%d│%d│%s',
      H.ensure_text_width(item.highlighter, highlighter_width),
      item.buf_name, item.lnum, item.col, item.line
    )
    item.buf_name, item.line = nil, nil
  end

  local show = function(buf_id, items_to_show, query)
    pick.default_show(buf_id, items_to_show, query)

    H.pick_clear_namespace(buf_id, H.ns_id.pickers)
    for i, item in ipairs(items_to_show) do
      local end_col = string.len(item.highlighter)
      local extmark_opts = { hl_group = item.hl_group, end_row = i - 1, end_col = end_col, priority = 1 }
      vim.api.nvim_buf_set_extmark(buf_id, H.ns_id.pickers, i - 1, 0, extmark_opts)
    end
  end

  local name = string.format('Mini.hipatterns matches (%s)', scope)
  return H.pick_start(items, { source = { name = name, show = show } }, opts)
end

--- Neovim history picker
---
--- Pick from output of |:history|. Use `<C-e>` to edit current match in
--- Command line.
---
--- Notes:
--- - Has no preview.
--- - Choosing action depends on scope:
---     - For "cmd" / ":" scopes, the command is executed.
---     - For "search" / "/" / "?" scopes, search is redone.
---     - For other scopes nothing is done (but chosen item is still returned).
--- - `<C-e>` only works for "cmd" / ":" / "search" / "/" / "?" scopes.
---
--- Examples ~
---
--- - Command history: `MiniExtra.pickers.history({ scope = ':' })`
--- - Search history: `:Pick history scope='/'`
---
---@param local_opts __extra_pickers_local_opts
---   Possible fields:
---   - <scope> `(string)` - any allowed {name} flag of |:history| command.
---     Note: word abbreviations are not allowed. Default: "all".
---@param opts __extra_pickers_opts
---
---@return __extra_pickers_return
MiniExtra.pickers.history = function(local_opts, opts)
  local pick = H.validate_pick('history')
  local_opts = vim.tbl_deep_extend('force', { scope = 'all' }, local_opts or {})

  local allowed_scope = { 'all', 'cmd', 'search', 'expr', 'input', 'debug', ':', '/', '?', '=', '@', '>' }
  local scope = H.pick_validate_scope(local_opts, allowed_scope, 'history')

  --stylua: ignore
  local type_ids = {
    cmd = ':',   search = '/', expr  = '=', input = '@', debug = '>',
    [':'] = ':', ['/']  = '/', ['='] = '=', ['@'] = '@', ['>'] = '>',
    ['?'] = '?',
  }

  -- Construct items
  local items = {}
  local names = scope == 'all' and { 'cmd', 'search', 'expr', 'input', 'debug' } or { scope }
  for _, cur_name in ipairs(names) do
    local id = type_ids[cur_name]
    for i = 1, vim.fn.histnr(cur_name) do
      local hist_entry = vim.fn.histget(cur_name, -i)
      if hist_entry == '' then break end
      table.insert(items, string.format('%s %s', id, hist_entry))
    end
  end

  -- Define source
  local preview = H.pick_make_no_preview('history')

  local choose = function(item)
    if not (type(item) == 'string' and vim.fn.mode() == 'n') then return end
    local id, entry = item:match('^(.) (.*)$')
    if id == ':' or id == '/' or id == '?' then
      vim.schedule(function() vim.fn.feedkeys(id .. entry .. '\r', 'nxt') end)
    end
  end

  local edit_command = function()
    local cur_match = MiniPick.get_picker_matches().current
    local cur_scope, cur_item = cur_match:match('^(.) (.*)$')
    if not (cur_scope == ':' or cur_scope == '/' or cur_scope == '?') then return end
    vim.schedule(function() vim.api.nvim_input(cur_scope .. cur_item) end)
    return true
  end
  local mappings = { edit_command = { char = '<C-e>', func = edit_command } }

  opts = vim.tbl_deep_extend('force', opts or {}, { mappings = mappings })
  local default_source = { name = string.format('History (%s)', scope), preview = preview, choose = choose }
  return H.pick_start(items, { source = default_source }, opts)
end

--- Highlight groups picker
---
--- Pick and preview highlight groups.
--- Notes:
--- - Item line is colored with same highlight group it represents.
--- - Preview shows highlight's definition (as in |:highlight| with {group-name}).
--- - Choosing places highlight definition in Command line to update and apply.
---
---@param local_opts __extra_pickers_local_opts
---   Not used at the moment.
---@param opts __extra_pickers_opts
---
---@return __extra_pickers_return
MiniExtra.pickers.hl_groups = function(local_opts, opts)
  local pick = H.validate_pick('hl_groups')

  -- Construct items
  local group_data = vim.split(vim.api.nvim_exec('highlight', true), '\n')
  local items = {}
  for _, l in ipairs(group_data) do
    local group = l:match('^(%S+)')
    if group ~= nil then table.insert(items, group) end
  end

  local show = function(buf_id, items_to_show, query)
    H.set_buflines(buf_id, items_to_show)
    H.pick_clear_namespace(buf_id, H.ns_id.pickers)
    -- Highlight line with highlight group of its item
    for i = 1, #items_to_show do
      H.pick_highlight_line(buf_id, i, items_to_show[i], 300)
    end
  end

  -- Define source
  local preview = function(buf_id, item)
    local lines = vim.split(vim.api.nvim_exec('hi ' .. item, true), '\n')
    H.set_buflines(buf_id, lines)
  end

  local choose = function(item)
    local hl_def = vim.split(vim.api.nvim_exec('hi ' .. item, true), '\n')[1]
    hl_def = hl_def:gsub('^(%S+)%s+xxx%s+', '%1 ')
    vim.schedule(function() vim.fn.feedkeys(':hi ' .. hl_def, 'n') end)
  end

  local default_source = { name = 'Highlight groups', show = show, preview = preview, choose = choose }
  return H.pick_start(items, { source = default_source }, opts)
end

--- Neovim keymaps picker
---
--- Pick and preview data about Neovim keymaps.
--- Notes:
--- - Item line contains data about keymap mode, whether it is buffer local, its
---   left hand side, and inferred description.
--- - Preview shows keymap data or callback source (if present and reachable).
--- - Choosing emulates pressing the left hand side of the keymap.
---
---@param local_opts __extra_pickers_local_opts
---   Possible fields:
---   - <mode> `(string)` - modes to show. One of "all" or appropriate mode
---     for |nvim_set_keymap()|. Default: "all".
---   - <scope> `(string)` - scope to show. One of "all", "global", "buf".
---     Default: "all".
---@param opts __extra_pickers_opts
---
---@return __extra_pickers_return
MiniExtra.pickers.keymaps = function(local_opts, opts)
  local pick = H.validate_pick('keymaps')
  local_opts = vim.tbl_deep_extend('force', { mode = 'all', scope = 'all' }, local_opts or {})

  local mode = H.pick_validate_one_of('mode', local_opts, { 'all', 'n', 'x', 's', 'o', 'i', 'l', 'c', 't' }, 'keymaps')
  local scope = H.pick_validate_scope(local_opts, { 'all', 'global', 'buf' }, 'keymaps')

  -- Create items
  local items = {}
  local populate_modes = mode == 'all' and { 'n', 'x', 's', 'o', 'i', 'l', 'c', 't' } or { mode }
  local max_lhs_width = 0
  local populate_items = function(source)
    for _, m in ipairs(populate_modes) do
      for _, maparg in ipairs(source(m)) do
        local desc = maparg.desc ~= nil and vim.inspect(maparg.desc) or maparg.rhs
        local lhs = vim.fn.keytrans(maparg.lhsraw or maparg.lhs)
        max_lhs_width = math.max(vim.fn.strchars(lhs), max_lhs_width)
        table.insert(items, { lhs = lhs, desc = desc, maparg = maparg })
      end
    end
  end

  if scope == 'all' or scope == 'buf' then populate_items(function(m) return vim.api.nvim_buf_get_keymap(0, m) end) end
  if scope == 'all' or scope == 'global' then populate_items(vim.api.nvim_get_keymap) end

  for _, item in ipairs(items) do
    local buf_map_indicator = item.maparg.buffer == 0 and ' ' or '@'
    local lhs_text = H.ensure_text_width(item.lhs, max_lhs_width)
    item.text = string.format('%s %s │ %s │ %s', item.maparg.mode, buf_map_indicator, lhs_text, item.desc or '')
  end

  -- Define source
  local get_callback_pos = function(maparg)
    if type(maparg.callback) ~= 'function' then return nil, nil end
    local info = debug.getinfo(maparg.callback)
    local path = info.source:gsub('^@', '')
    if vim.fn.filereadable(path) == 0 then return nil, nil end
    return path, info.linedefined
  end

  local preview = function(buf_id, item)
    local path, lnum = get_callback_pos(item.maparg)
    if path ~= nil then
      item.path, item.lnum = path, lnum
      return pick.default_preview(buf_id, item)
    end
    local lines = vim.split(vim.inspect(item.maparg), '\n')
    H.set_buflines(buf_id, lines)
  end

  local choose = function(item)
    local keys = vim.api.nvim_replace_termcodes(item.maparg.lhs, true, true, true)
    -- Restore Visual mode (should be active previously at least once)
    if item.maparg.mode == 'x' then keys = 'gv' .. keys end
    vim.schedule(function() vim.api.nvim_input(keys) end)
  end

  local default_opts = { source = { name = string.format('Keymaps (%s)', scope), preview = preview, choose = choose } }
  return H.pick_start(items, default_opts, opts)
end

--- Neovim lists picker
---
--- Pick and navigate to elements of the following Neovim lists:
--- - |quickfix| list.
--- - |location-list| of current window.
--- - |jumplist|.
--- - |changelist|.
---
--- Note: it requires explicit `scope`.
---
--- Examples ~
---
--- - `MiniExtra.pickers.list({ scope = 'quickfix' })` - quickfix list.
--- - `:Pick list scope='jump'` - jump list.
---
---@param local_opts __extra_pickers_local_opts
---   Possible fields:
---   - <scope> `(string)` - type of list to show. One of "quickfix", "location",
---     "jump", "change". Default: `nil` which means explicit scope is needed.
---@param opts __extra_pickers_opts
---
---@return __extra_pickers_return
MiniExtra.pickers.list = function(local_opts, opts)
  local pick = H.validate_pick('list')
  local_opts = vim.tbl_deep_extend('force', { scope = nil }, local_opts or {})

  if local_opts.scope == nil then H.error('`pickers.list` needs an explicit scope.') end
  local allowed_scopes = { 'quickfix', 'location', 'jump', 'change' }
  local scope = H.pick_validate_scope(local_opts, allowed_scopes, 'list')

  local has_items, items = pcall(H.list_get[scope])
  if not has_items then items = {} end

  items = vim.tbl_filter(function(x) return H.is_valid_buf(x.bufnr) end, items)
  items = vim.tbl_map(H.list_enhance_item, items)

  local name = string.format('List (%s)', scope)
  local show = H.pick_get_config().source.show or H.show_with_icons
  return H.pick_start(items, { source = { name = name, show = show, choose = H.choose_with_buflisted } }, opts)
end

--- LSP picker
---
--- Pick and navigate with LSP methods.
--- Notes:
--- - Needs an explicit scope from a list of supported ones:
---     - "declaration".
---     - "definition".
---     - "document_symbol".
---     - "implementation".
---     - "references".
---     - "type_definition".
---     - "workspace_symbol".
--- - Directly relies on `vim.lsp.buf` methods which support |lsp-on-list-handler|.
---   In particular, it means that picker is started only if LSP server returns
---   list of locations and not a single location.
--- - Doesn't return anything due to async nature of `vim.lsp.buf` methods.
--- - Requires set up |mini.icons| to show extra icons and highlighting in
---   "document_symbol" and "workspace_symbol" scopes.
---
--- Examples ~
---
--- - `MiniExtra.pickers.lsp({ scope = 'references' })` - references of the symbol
---   under cursor.
--- - `:Pick lsp scope='document_symbol'` - symbols in current file.
---
---@param local_opts __extra_pickers_local_opts
---   Possible fields:
---   - <scope> `(string)` - LSP method to use. One of the supported ones (see
---     list above). Default: `nil` which means explicit scope is needed.
---   - <symbol_query> `(string)` - query for |vim.lsp.buf.workspace_symbol()|.
---     Default: empty string for all symbols (according to LSP specification).
---@param opts __extra_pickers_opts
---
---@return nil Nothing is returned.
MiniExtra.pickers.lsp = function(local_opts, opts)
  local pick = H.validate_pick('lsp')
  local_opts = vim.tbl_deep_extend('force', { scope = nil, symbol_query = '' }, local_opts or {})

  if local_opts.scope == nil then H.error('`pickers.lsp` needs an explicit scope.') end
  --stylua: ignore
  local allowed_scopes = {
    'declaration', 'definition', 'document_symbol', 'implementation', 'references', 'type_definition', 'workspace_symbol',
  }
  local scope = H.pick_validate_scope(local_opts, allowed_scopes, 'lsp')

  if scope == 'references' then return vim.lsp.buf[scope](nil, { on_list = H.lsp_make_on_list(scope, opts) }) end
  if scope == 'workspace_symbol' then
    local query = tostring(local_opts.symbol_query)
    return vim.lsp.buf[scope](query, { on_list = H.lsp_make_on_list(scope, opts) })
  end
  vim.lsp.buf[scope]({ on_list = H.lsp_make_on_list(scope, opts) })
end

--- Neovim marks picker
---
--- Pick and preview position of Neovim |mark|s.
---
---@param local_opts __extra_pickers_local_opts
---   Possible fields:
---   - <scope> `(string)` - scope to show. One of "all", "global", "buf".
---     Default: "all".
---@param opts __extra_pickers_opts
---
---@return __extra_pickers_return
MiniExtra.pickers.marks = function(local_opts, opts)
  local pick = H.validate_pick('marks')
  local_opts = vim.tbl_deep_extend('force', { scope = 'all' }, local_opts or {})

  local scope = H.pick_validate_scope(local_opts, { 'all', 'global', 'buf' }, 'marks')

  -- Create items
  local items = {}
  local populate_items = function(mark_list)
    for _, info in ipairs(mark_list) do
      local path
      if type(info.file) == 'string' then path = vim.fn.fnamemodify(info.file, ':.') end
      local buf_id
      if path == nil then buf_id = info.pos[1] end

      local line, col = info.pos[2], math.abs(info.pos[3])
      local text = string.format('%s │ %s%s│%s', info.mark:sub(2), path == nil and '' or (path .. '│'), line, col)
      table.insert(items, { text = text, bufnr = buf_id, path = path, lnum = line, col = col })
    end
  end

  if scope == 'all' or scope == 'buf' then populate_items(vim.fn.getmarklist(vim.api.nvim_get_current_buf())) end
  if scope == 'all' or scope == 'global' then populate_items(vim.fn.getmarklist()) end

  local default_opts = { source = { name = string.format('Marks (%s)', scope) } }
  return H.pick_start(items, default_opts, opts)
end

--- Old files picker
---
--- Pick from |v:oldfiles| entries representing readable files.
---
---@param local_opts __extra_pickers_local_opts
---   Possible fields:
---   - <current_dir> `(boolean)` - whether to return files only from current
---     working directory and its subdirectories. Default: `false`.
---   __extra_pickers_preserve_order
---@param opts __extra_pickers_opts
---
---@return __extra_pickers_return
MiniExtra.pickers.oldfiles = function(local_opts, opts)
  local pick = H.validate_pick('oldfiles')
  local_opts = vim.tbl_deep_extend('force', { current_dir = false, preserve_order = false }, local_opts or {})
  local oldfiles = vim.v.oldfiles
  if not H.islist(oldfiles) then H.error('`pickers.oldfiles` picker needs valid `v:oldfiles`.') end

  local show_all = not local_opts.current_dir
  local items = vim.schedule_wrap(function()
    local cwd = H.normalize_path(pick.get_picker_opts().source.cwd) .. '/'
    local res = {}
    for _, path in ipairs(oldfiles) do
      path = H.normalize_path(path)
      if vim.fn.filereadable(path) == 1 and (show_all or vim.startswith(path, cwd)) then
        table.insert(res, H.short_path(path, cwd))
      end
    end
    pick.set_picker_items(res)
  end)

  local show = H.pick_get_config().source.show or H.show_with_icons
  local match_opts = { preserve_order = local_opts.preserve_order }
  local match = function(stritems, inds, query) pick.default_match(stritems, inds, query, match_opts) end
  return H.pick_start(items, { source = { name = 'Old files', show = show, match = match } }, opts)
end

--- Neovim options picker
---
--- Pick and preview data about Neovim options.
--- Notes:
--- - Item line is colored based on whether it was set (dimmed if wasn't).
--- - Preview shows option value in target window and its general information.
--- - Choosing places option name in Command line to update and apply.
---
---@param local_opts __extra_pickers_local_opts
---   Possible fields:
---   - <scope> `(string)` - options to show. One of "all", "global", "win", "buf".
---     Default: "all".
---@param opts __extra_pickers_opts
---
---@return __extra_pickers_return
MiniExtra.pickers.options = function(local_opts, opts)
  local pick = H.validate_pick('options')
  local_opts = vim.tbl_deep_extend('force', { scope = 'all' }, local_opts or {})

  local scope = H.pick_validate_scope(local_opts, { 'all', 'global', 'win', 'buf' }, 'options')

  local items = {}
  for name, info in pairs(vim.api.nvim_get_all_options_info()) do
    if scope == 'all' or scope == info.scope then table.insert(items, { text = name, info = info }) end
  end
  table.sort(items, function(a, b) return a.text < b.text end)

  local show = function(buf_id, items_to_show, query)
    pick.default_show(buf_id, items_to_show, query)

    H.pick_clear_namespace(buf_id, H.ns_id.pickers)
    for i, item in ipairs(items_to_show) do
      if not item.info.was_set then H.pick_highlight_line(buf_id, i, 'Comment', 199) end
    end
  end

  local preview = function(buf_id, item)
    local pick_windows = pick.get_picker_state().windows
    local target_win_id = pick_windows.target
    if not H.is_valid_win(target_win_id) then target_win_id = pick_windows.main end
    local value_source = ({ global = 'o', win = 'wo', buf = 'bo' })[item.info.scope]
    local has_value, value = pcall(function()
      return vim.api.nvim_win_call(target_win_id, function() return vim[value_source][item.info.name] end)
    end)
    -- TODO: consider removing after Neovim<=0.10 compatibility is dropped
    if not has_value then value = '<Option is deprecated (will be removed in later Neovim versions)>' end

    local lines = { 'Value:', unpack(vim.split(vim.inspect(value), '\n')), '', 'Info:' }
    local hl_lines = { 1, #lines }
    lines = vim.list_extend(lines, vim.split(vim.inspect(item.info), '\n'))

    H.set_buflines(buf_id, lines)
    H.pick_highlight_line(buf_id, hl_lines[1], 'MiniPickHeader', 200)
    H.pick_highlight_line(buf_id, hl_lines[2], 'MiniPickHeader', 200)
  end

  local choose = function(item)
    local keys = string.format(':set %s%s', item.info.name, item.info.type == 'boolean' and '' or '=')
    vim.schedule(function() vim.fn.feedkeys(keys) end)
  end

  local name = string.format('Options (%s)', scope)
  local default_source = { name = name, show = show, preview = preview, choose = choose }
  return H.pick_start(items, { source = default_source }, opts)
end

--- Neovim registers picker
---
--- Pick from Neovim |registers|.
--- Notes:
--- - There is no preview (all information is in the item's text).
--- - Choosing pastes content of a register: with |i_CTRL-R| in Insert mode,
---   |c_CTRL-R| in Command-line mode, and |P| otherwise.
---   Expression register |quote=| is reevaluated (if present) and pasted.
---
---@param local_opts __extra_pickers_local_opts
---   Not used at the moment.
---@param opts __extra_pickers_opts
---
---@return __extra_pickers_return
MiniExtra.pickers.registers = function(local_opts, opts)
  local pick = H.validate_pick('registers')

  local describe_register = function(regname)
    local ok, value = pcall(vim.fn.getreg, regname, 1)
    if not ok then return '' end
    return value
  end

  local all_registers = vim.split('"*+:.%/#=-0123456789abcdefghijklmnopqrstuvwxyz', '')

  local items = {}
  for _, regname in ipairs(all_registers) do
    local regcontents = describe_register(regname)
    local text = string.format('%s │ %s', regname, regcontents)
    table.insert(items, { regname = regname, regcontents = regcontents, text = text })
  end

  local choose = vim.schedule_wrap(function(item)
    local reg, regcontents, mode = item.regname, item.regcontents, vim.fn.mode()
    if reg == '=' and regcontents ~= '' then reg = reg .. item.regcontents .. '\r' end
    local keys = string.format('"%s%s', reg, reg == '=' and '' or 'P')
    -- In Insert and Command-line modes use `<C-r><regname>`
    if mode == 'i' or mode == 'c' then keys = '\18' .. reg end
    vim.fn.feedkeys(keys)
  end)

  local preview = function(buf_id, item) H.set_buflines(buf_id, vim.split(item.regcontents, '\n')) end

  return H.pick_start(items, { source = { name = 'Registers', preview = preview, choose = choose } }, opts)
end

--- Neovim spell suggestions picker
---
--- Pick and apply spell suggestions.
--- Notes:
--- - No preview is available.
--- - Choosing replaces current word (|<cword>|) with suggestion.
---
---@param local_opts __extra_pickers_local_opts
---   Possible fields:
---   - <n_suggestions> `(number)` - number of spell suggestions. Default: 25.
---
---@param opts __extra_pickers_opts
---
---@return __extra_pickers_return
MiniExtra.pickers.spellsuggest = function(local_opts, opts)
  local pick = H.validate_pick('spellsuggest')
  local_opts = vim.tbl_deep_extend('force', { n_suggestions = 25 }, local_opts or {})

  local n_suggestions = local_opts.n_suggestions
  if not (type(n_suggestions) == 'number' and n_suggestions > 0) then
    H.error('`local_opts.n_suggestions` should be a positive number.')
  end

  local word = vim.fn.expand('<cword>')
  local suggestions = vim.fn.spellsuggest(word, n_suggestions)
  local items = {}
  for i, sugg in ipairs(suggestions) do
    table.insert(items, { text = sugg, index = i })
  end

  -- Define scope
  local preview = H.pick_make_no_preview('spellsuggest')
  local choose = vim.schedule_wrap(function(item) vim.cmd('normal! ' .. item.index .. 'z=') end)

  local name = 'Spell suggestions for ' .. vim.inspect(word)
  return H.pick_start(items, { source = { name = name, preview = preview, choose = choose } }, opts)
end

--- Tree-sitter nodes picker
---
--- Pick and navigate to |treesitter| nodes of current buffer.
--- Notes:
--- - Requires active tree-sitter parser in the current buffer.
---
---@param local_opts __extra_pickers_local_opts
---   Not used at the moment.
---@param opts __extra_pickers_opts
---
---@return __extra_pickers_return
MiniExtra.pickers.treesitter = function(local_opts, opts)
  local pick = H.validate_pick('treesitter')

  local buf_id = vim.api.nvim_get_current_buf()
  -- TODO: Remove `opts.error` after compatibility with Neovim=0.11 is dropped
  local has_parser, parser = pcall(vim.treesitter.get_parser, buf_id, nil, { error = false })
  if not has_parser or parser == nil then H.error('`pickers.treesitter` requires active tree-sitter parser.') end

  -- Make items by traversing roots of all trees (including injections)
  local items, traverse = {}, nil
  traverse = function(node, depth)
    if depth >= 1000 then return end
    for child in node:iter_children() do
      if child:named() then
        local lnum, col, end_lnum, end_col = child:range()
        lnum, col, end_lnum, end_col = lnum + 1, col + 1, end_lnum + 1, end_col + 1
        local indent = string.rep(' ', depth)
        local text = string.format('%s%s (%s│%s - %s│%s)', indent, child:type() or '', lnum, col, end_lnum, end_col)
        local item = { text = text, bufnr = buf_id, lnum = lnum, col = col, end_lnum = end_lnum, end_col = end_col }
        table.insert(items, item)

        traverse(child, depth + 1)
      end
    end
  end

  parser:for_each_tree(function(ts_tree, _) traverse(ts_tree:root(), 0) end)

  return H.pick_start(items, { source = { name = 'Tree-sitter nodes' } }, opts)
end

--- Visit paths from 'mini.visits' picker
---
--- Pick paths from |MiniVisits| using |MiniVisits.list_paths()|.
--- Notes:
--- - Requires 'mini.visits'.
---
--- Examples ~
---
--- - `MiniExtra.pickers.visit_paths()` - visits registered for |current-directory|
---   and ordered by "robust frecency".
--- - `:Pick visit_paths cwd='' recency_weight=1 filter='core'` - all visits with
---   "core" label ordered from most to least recent.
---
---@param local_opts __extra_pickers_local_opts
---   Possible fields:
---   - <cwd> `(string)` - forwarded to |MiniVisits.list_paths()|.
---     Default: `nil` to get paths registered for |current-directory|.
---   - <filter> `(function|string)` - forwarded to |MiniVisits.list_paths()|.
---     Default: `nil` to use all paths.
---   __extra_pickers_preserve_order
---   - <recency_weight> `(number)` - forwarded to |MiniVisits.gen_sort.default()|.
---     Default: 0.5 to use "robust frecency" sorting.
---   - <sort> `(function)` - forwarded to |MiniVisits.list_paths()|.
---     Default: `nil` to use "robust frecency".
---     Note: if supplied, has precedence over `recency_weight`.
---@param opts __extra_pickers_opts
---
---@return __extra_pickers_return
MiniExtra.pickers.visit_paths = function(local_opts, opts)
  local pick = H.validate_pick('visit_paths')
  local has_visits, visits = pcall(require, 'mini.visits')
  if not has_visits then H.error([[`pickers.visit_paths` requires 'mini.visits' which can not be found.]]) end

  local default_local_opts = { cwd = nil, filter = nil, preserve_order = false, recency_weight = 0.5, sort = nil }
  local_opts = vim.tbl_deep_extend('force', default_local_opts, local_opts or {})

  local cwd = local_opts.cwd or vim.fn.getcwd()
  -- NOTE: Use separate cwd to allow `cwd = ''` to not mean "current directory"
  local is_for_cwd = cwd ~= ''
  local picker_cwd = H.normalize_path(cwd == '' and vim.fn.getcwd() or H.full_path(cwd))

  -- Define source
  local filter = local_opts.filter or visits.gen_filter.default()
  local sort = local_opts.sort or visits.gen_sort.default({ recency_weight = local_opts.recency_weight })
  local items = vim.schedule_wrap(function()
    local paths = visits.list_paths(cwd, { filter = filter, sort = sort })
    paths = vim.tbl_map(function(x) return H.normalize_path(H.short_path(x, picker_cwd)) end, paths)
    pick.set_picker_items(paths)
  end)

  local show = H.pick_get_config().source.show or H.show_with_icons
  local match_opts = { preserve_order = local_opts.preserve_order }
  local match = function(stritems, inds, query) pick.default_match(stritems, inds, query, match_opts) end

  local name = string.format('Visit paths (%s)', is_for_cwd and 'cwd' or 'all')
  local default_source = { name = name, cwd = picker_cwd, match = match, show = show }
  return H.pick_start(items, { source = default_source }, opts)
end

--- Visit labels from 'mini.visits' picker
---
--- Pick labels from |MiniVisits| using |MiniVisits.list_labels()|
--- and |MiniVisits.list_paths()|.
--- Notes:
--- - Requires 'mini.visits'.
--- - Preview shows target visit paths filtered to those having previewed label.
--- - Choosing essentially starts |MiniExtra.pickers.visit_paths()| for paths
---   with the chosen label.
---
--- Examples ~
---
--- - `MiniExtra.pickers.visit_labels()` - labels from visits registered
---   for |current-directory|.
--- - `:Pick visit_labels cwd=''` - labels from all visits.
---
---@param local_opts __extra_pickers_local_opts
---   Possible fields:
---   - <cwd> `(string)` - forwarded to |MiniVisits.list_labels()|.
---     Default: `nil` to get labels from visits registered for |current-directory|.
---   - <filter> `(function|string)` - forwarded to |MiniVisits.list_labels()|.
---     Default: `nil` to use all visits.
---   - <path> `(string)` - forwarded to |MiniVisits.list_labels()|.
---     Default: `""` to get labels from all visits for target `cwd`.
---   - <sort> `(function)` - forwarded to |MiniVisits.list_paths()| for
---     preview and choose. Default: `nil` to use "robust frecency".
---@param opts __extra_pickers_opts
---
---@return ... Chosen path.
MiniExtra.pickers.visit_labels = function(local_opts, opts)
  local pick = H.validate_pick('visit_labels')
  local has_visits, visits = pcall(require, 'mini.visits')
  if not has_visits then H.error([[`pickers.visit_labels` requires 'mini.visits' which can not be found.]]) end

  local default_local_opts = { cwd = nil, filter = nil, path = '', sort = nil }
  local_opts = vim.tbl_deep_extend('force', default_local_opts, local_opts or {})

  local cwd = local_opts.cwd or vim.fn.getcwd()
  -- NOTE: Use separate cwd to allow `cwd = ''` to not mean "current directory"
  local is_for_cwd = cwd ~= ''
  local picker_cwd = H.normalize_path(cwd == '' and vim.fn.getcwd() or H.full_path(cwd))

  local filter = local_opts.filter or visits.gen_filter.default()
  local items = visits.list_labels(local_opts.path, local_opts.cwd, { filter = filter })

  -- Define source
  local list_label_paths = function(label)
    local new_filter = function(path_data)
      return filter(path_data) and type(path_data.labels) == 'table' and path_data.labels[label]
    end
    local all_paths = visits.list_paths(local_opts.cwd, { filter = new_filter, sort = local_opts.sort })
    return vim.tbl_map(function(x) return H.normalize_path(H.short_path(x, picker_cwd)) end, all_paths)
  end

  local preview = function(buf_id, label) vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, list_label_paths(label)) end
  local choose = function(label)
    if label == nil then return end

    pick.set_picker_items(list_label_paths(label), { do_match = false })
    pick.set_picker_query({})
    local name = string.format('Paths for %s label', vim.inspect(label))
    local show = H.pick_get_config().source.show or H.show_with_icons
    pick.set_picker_opts({ source = { name = name, show = show, choose = pick.default_choose } })
    return true
  end

  local name = string.format('Visit labels (%s)', is_for_cwd and 'cwd' or 'all')
  local default_source = { name = name, cwd = picker_cwd, preview = preview, choose = choose }
  return H.pick_start(items, { source = default_source }, opts)
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniExtra.config

-- Namespaces
H.ns_id = {
  pickers = vim.api.nvim_create_namespace('MiniExtraPickers'),
}

-- Various cache
H.cache = {}

-- File system information
H.is_windows = vim.loop.os_uname().sysname == 'Windows_NT'

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  return config
end

H.apply_config = function(config)
  MiniExtra.config = config

  -- Register pickers in 'mini.pick'
  if type(_G.MiniPick) == 'table' then
    for name, f in pairs(MiniExtra.pickers) do
      _G.MiniPick.registry[name] = _G.MiniPick.registry[name] or function(local_opts) return f(local_opts) end
    end
  end
end

-- Mini.ai specifications -----------------------------------------------------
H.ai_indent_spec = function(ai_type)
  -- Compute buffer data
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local tab_spaces = string.rep(' ', vim.bo.tabstop)

  -- Traverse lines from top to bottom casting rays
  local indents, rays, rays_final = {}, {}, {}
  for i, l in ipairs(lines) do
    indents[i] = l:match('^([ \t]*)')

    -- Ray can be updated only on non-blank line
    local is_blank = indents[i]:len() ~= l:len()
    if is_blank then H.ai_indent_update_rays(i, indents[i]:gsub('\t', tab_spaces):len(), rays, rays_final) end
  end

  -- The `rays` stack can be not empty at this point which means that there are
  -- non-empty lines at buffer end without "closing". Ignore them.

  -- Sort for better output
  table.sort(rays_final, function(a, b) return a.from_line < b.from_line end)

  -- Compute regions:
  -- - `a` is as if linewise from start to end.
  -- - `i` is as if charwise not including edge whitespace on start and end.
  local from_offset, to_offset, to_col_offset = 0, 0, 1
  if ai_type == 'i' then
    from_offset, to_offset, to_col_offset = 1, -1, 0
  end
  local res = {}
  for i, ray in ipairs(rays_final) do
    local from_line, to_line = ray.from_line + from_offset, ray.to_line + to_offset
    local from_col = ai_type == 'a' and 1 or (indents[from_line]:len() + 1)
    local to_col = lines[to_line]:len() + to_col_offset
    res[i] = { from = { line = from_line, col = from_col }, to = { line = to_line, col = to_col } }
  end
  return res
end

H.ai_indent_update_rays = function(line_num, indent, rays, rays_final)
  -- Update rays with finite indent
  -- `rays` is a stack of cast rays (sorted by increasing start indent).
  -- Each ray has `from_line` and `to_line` indicating start of `a` textobject.
  for i = #rays, 1, -1 do
    local ray = rays[i]
    -- If current indent is bigger, then ray is cast over non-blank region.
    -- This assumes that line at `line_num` is not blank.
    if ray.indent < indent then
      ray.is_empty = false
      -- All previously cast rays are already marked as non-blank if they are
      break
    end

    -- If ray was cast from bigger indent then current and spans over
    -- non-empty region, finalize it as it has hit its limit
    if not ray.is_empty then
      ray.to_line = line_num
      table.insert(rays_final, ray)
    end
    rays[i] = nil
  end

  -- Start new ray
  table.insert(rays, { indent = indent, from_line = line_num, is_empty = true })
end

-- Pickers --------------------------------------------------------------------
H.validate_pick = function(fun_name)
  local has_pick, pick = pcall(require, 'mini.pick')
  if not has_pick then
    H.error(string.format([[`pickers.%s()` requires 'mini.pick' which can not be found.]], fun_name))
  end
  return pick
end

H.pick_start = function(items, default_opts, opts)
  local pick = H.validate_pick()
  local opts_final = vim.tbl_deep_extend('force', default_opts, opts or {}, { source = { items = items } })
  return pick.start(opts_final)
end

H.pick_highlight_line = function(buf_id, line, hl_group, priority)
  local opts = { end_row = line, end_col = 0, hl_mode = 'blend', hl_group = hl_group, priority = priority }
  vim.api.nvim_buf_set_extmark(buf_id, H.ns_id.pickers, line - 1, 0, opts)
end

H.pick_prepend_position = function(item)
  local path
  if item.path ~= nil then
    path = item.path
  elseif H.is_valid_buf(item.bufnr) then
    local name = vim.api.nvim_buf_get_name(item.bufnr)
    path = name == '' and ('Buffer_' .. item.bufnr) or name
  end
  if path == nil then return item end

  path = vim.fn.fnamemodify(path, ':p:.')
  local text = item.text or ''
  local suffix = text == '' and '' or ('│ ' .. text)
  item.text = string.format('%s│%s│%s%s', path, item.lnum or 1, item.col or 1, suffix)
  return item
end

H.pick_clear_namespace = function(buf_id, ns_id) pcall(vim.api.nvim_buf_clear_namespace, buf_id, ns_id, 0, -1) end

H.pick_make_no_preview = function(picker_name)
  local lines = { string.format('No preview available for `%s` picker', picker_name) }
  return function(buf_id, _) H.set_buflines(buf_id, lines) end
end

H.pick_validate_one_of = function(target, opts, values, picker_name)
  if vim.tbl_contains(values, opts[target]) then return opts[target] end
  local msg = string.format(
    '`pickers.%s` has wrong "%s" local option (%s). Should be one of %s.',
    picker_name,
    target,
    vim.inspect(opts[target]),
    table.concat(vim.tbl_map(vim.inspect, values), ', ')
  )
  H.error(msg)
end

H.pick_validate_scope = function(...) return H.pick_validate_one_of('scope', ...) end

H.pick_get_config = function()
  return vim.tbl_deep_extend('force', (require('mini.pick') or {}).config or {}, vim.b.minipick_config or {})
end

H.show_with_icons = function(buf_id, items, query)
  require('mini.pick').default_show(buf_id, items, query, { show_icons = true })
end

H.choose_with_buflisted = function(item)
  local pick = require('mini.pick')
  pick.default_choose(item)

  -- Force 'buflisted' on opened item
  local win_target = pick.get_picker_state().windows.target
  local buf_id = vim.api.nvim_win_get_buf(win_target)
  vim.bo[buf_id].buflisted = true
end

-- Colorscheme picker ----------------------------------------------------------
H.preview_cs_hl_groups = function(buf_id, hl_groups)
  local lines = hl_groups
  if lines == nil then
    lines = vim.tbl_keys(vim.api.nvim_get_hl(0, {}))
    table.sort(lines)
  end
  vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)

  local ns_id = H.ns_id.pickers
  vim.api.nvim_buf_clear_namespace(buf_id, ns_id, 0, -1)
  for i, hl in ipairs(lines) do
    pcall(vim.api.nvim_buf_set_extmark, buf_id, ns_id, i - 1, 0, { end_row = i, end_col = 0, hl_group = hl })
  end
end

-- Diagnostic picker ----------------------------------------------------------
H.diagnostic_make_compare = function(sort_by)
  if sort_by == 'severity' then
    return function(a, b)
      if a.severity < b.severity then return true end
      if a.severity > b.severity then return false end
      if a.path < b.path then return true end
      if a.path > b.path then return false end
      if a.lnum < b.lnum then return true end
      if a.lnum > b.lnum then return false end
      return a.col < b.col
    end
  end
  if sort_by == 'path' then
    return function(a, b)
      if a.path < b.path then return true end
      if a.path > b.path then return false end
      if a.severity < b.severity then return true end
      if a.severity > b.severity then return false end
      if a.lnum < b.lnum then return true end
      if a.lnum > b.lnum then return false end
      return a.col < b.col
    end
  end

  return nil
end

-- Git pickers ----------------------------------------------------------------
H.validate_git = function(picker_name)
  if vim.fn.executable('git') == 1 then return true end
  local msg = string.format('`pickers.%s` requires executable `git`.', picker_name)
  H.error(msg)
end

H.git_normalize_path = function(path, picker_name)
  path = type(path) == 'string' and path or vim.fn.getcwd()
  if path == '' then H.error(string.format('Path in `%s` is empty.', picker_name)) end
  path = H.full_path(path)
  local path_is_dir, path_is_file = vim.fn.isdirectory(path) == 1, vim.fn.filereadable(path) == 1
  if not (path_is_dir or path_is_file) then H.error('Path ' .. path .. ' is not a valid path.') end
  return path, path_is_dir and 'directory' or 'file'
end

H.git_get_repo_dir = function(path, path_type, picker_name)
  local path_dir = path_type == 'directory' and path or vim.fn.fnamemodify(path, ':h')
  local repo_dir = vim.fn.systemlist({ 'git', '-C', path_dir, 'rev-parse', '--show-toplevel' })[1]
  if vim.v.shell_error ~= 0 then
    local msg = string.format('`pickers.%s` could not find Git repo for %s.', picker_name, path)
    H.error(msg)
  end
  return repo_dir
end

H.git_difflines_to_hunkitems = function(lines, n_context)
  local header_pattern = '^diff %-%-git'
  local hunk_pattern = '^@@ %-%d+,?%d* %+(%d+),?%d* @@'
  local to_path_pattern = '^%+%+%+ b/(.*)$'

  -- Parse diff lines
  local cur_header, cur_path, is_in_hunk = {}, nil, false
  local items = {}
  for _, l in ipairs(lines) do
    -- Separate path header and hunk for better granularity
    if l:find(header_pattern) ~= nil then
      is_in_hunk = false
      cur_header = {}
    end

    local path_match = l:match(to_path_pattern)
    if path_match ~= nil and not is_in_hunk then cur_path = path_match end

    local hunk_start = l:match(hunk_pattern)
    if hunk_start ~= nil then
      is_in_hunk = true
      local item = { path = cur_path, lnum = tonumber(hunk_start), header = vim.deepcopy(cur_header), hunk = {} }
      table.insert(items, item)
    end

    if is_in_hunk then
      table.insert(items[#items].hunk, l)
    else
      table.insert(cur_header, l)
    end
  end

  -- Correct line number to point at the first change
  local try_correct_lnum = function(item, i)
    if item.hunk[i]:find('^[+-]') == nil then return false end
    item.lnum = item.lnum + i - 2
    return true
  end
  for _, item in ipairs(items) do
    for i = 2, #item.hunk do
      if try_correct_lnum(item, i) then break end
    end
  end

  -- Construct aligned text from path and hunk header
  local text_parts, path_width, coords_width = {}, 0, 0
  for i, item in ipairs(items) do
    local coords, title = item.hunk[1]:match('@@ (.-) @@ ?(.*)$')
    coords, title = coords or '', title or ''
    text_parts[i] = { item.path, coords, title }
    path_width = math.max(path_width, vim.fn.strchars(item.path))
    coords_width = math.max(coords_width, vim.fn.strchars(coords))
  end

  for i, item in ipairs(items) do
    local parts = text_parts[i]
    local path, coords = H.ensure_text_width(parts[1], path_width), H.ensure_text_width(parts[2], coords_width)
    item.text = string.format('%s │ %s │ %s', path, coords, parts[3])
  end

  return items
end

-- LSP picker -----------------------------------------------------------------
H.lsp_make_on_list = function(source, opts)
  local is_symbol = source == 'document_symbol' or source == 'workspace_symbol'

  -- Prepend file position info to item, add decortion, and sort
  local add_decor_data = function() end
  if is_symbol and _G.MiniIcons == nil then
    -- Try using '@...' style highlight group with same name as "kind"
    add_decor_data = function(item) item.hl = string.format('@%s', string.lower(item.kind or 'unknown')) end
  end
  if is_symbol and _G.MiniIcons ~= nil then
    add_decor_data = function(item)
      if type(item.kind) ~= 'string' then return end
      local icon, hl = MiniIcons.get('lsp', item.kind)
      -- If kind is not original, assume it already contains an icon
      local icon_prefix = item.kind_orig == item.kind and (icon .. ' ') or ''
      item.text, item.hl = icon_prefix .. item.text, hl
    end
  end

  local process = function(items)
    if source ~= 'document_symbol' then items = vim.tbl_map(H.pick_prepend_position, items) end
    -- Input `item.kind` is a string (resolved before `on_list`). Account for
    -- possibly tweaked symbol map (like after `MiniIcons.tweak_lsp_kind`).
    local kind_map = H.get_symbol_kind_map()
    for _, item in ipairs(items) do
      item.kind_orig, item.kind = item.kind, kind_map[item.kind]
      add_decor_data(item)
      item.kind_orig = nil
    end
    table.sort(items, H.lsp_items_compare)
    return items
  end

  local pick = H.validate_pick()
  local show_explicit = H.pick_get_config().source.show
  local show = function(buf_id, items_to_show, query)
    if show_explicit ~= nil then return show_explicit(buf_id, items_to_show, query) end
    if is_symbol then
      pick.default_show(buf_id, items_to_show, query)

      -- Highlight whole lines with pre-computed symbol kind highlight groups
      H.pick_clear_namespace(buf_id, H.ns_id.pickers)
      for i, item in ipairs(items_to_show) do
        H.pick_highlight_line(buf_id, i, item.hl, 199)
      end
      return
    end
    -- Show with icons as the non-symbol scopes should have paths
    return H.show_with_icons(buf_id, items_to_show, query)
  end

  local choose = function(item)
    pick.default_choose(item)
    -- Ensure relative path in `:buffers` output with hacky workaround.
    -- `default_choose` ensures it with `bufadd(fnamemodify(path, ':.'))`, but
    -- somehow that doesn't work inside `on_list` of `vim.lsp.buf` methods.
    vim.fn.chdir(vim.fn.getcwd())
  end

  return function(data)
    if vim.tbl_count(data.items) == 1 then
      vim.lsp.buf[source]()
      return
    end
    local items = data.items
    for _, item in ipairs(data.items) do
      item.text, item.path = item.text or '', item.filename or nil
    end
    items = process(items)

    local source_opts = { name = string.format('LSP (%s)', source), show = show, choose = choose }
    return H.pick_start(items, { source = source_opts }, opts)
  end
end

H.get_symbol_kind_map = function()
  -- Compute symbol kind map from "resolved" string kind to its "original" (as in
  -- LSP protocol). Those can be different after `MiniIcons.tweak_lsp_kind()`.
  local res = {}
  local double_map = vim.lsp.protocol.SymbolKind
  for k, v in pairs(double_map) do
    if type(k) == 'string' and type(v) == 'number' then res[double_map[v]] = k end
  end
  return res
end

H.lsp_items_compare = function(a, b)
  local a_path, b_path = a.path or '', b.path or ''
  if a_path < b_path then return true end
  if a_path > b_path then return false end

  local a_lnum, b_lnum = a.lnum or 1, b.lnum or 1
  if a_lnum < b_lnum then return true end
  if a_lnum > b_lnum then return false end

  local a_col, b_col = a.col or 1, b.col or 1
  if a_col < b_col then return true end
  if a_col > b_col then return false end

  return tostring(a) < tostring(b)
end

-- List picker ----------------------------------------------------------------
H.list_get = {
  quickfix = function() return vim.tbl_map(H.list_enhance_qf_loc, vim.fn.getqflist()) end,

  location = function() return vim.tbl_map(H.list_enhance_qf_loc, vim.fn.getloclist(0)) end,

  jump = function()
    local raw = vim.fn.getjumplist()[1]
    -- Tweak output: reverse for more relevance; make 1-based column
    local res, n = {}, #raw
    for i, x in ipairs(raw) do
      x.col = x.col + 1
      res[n - i + 1] = x
    end
    return res
  end,

  change = function()
    local cur_buf = vim.api.nvim_get_current_buf()
    local res = vim.fn.getchangelist(cur_buf)[1]
    for _, x in ipairs(res) do
      x.col = x.col + 1
      x.bufnr = cur_buf
    end
    return res
  end,
}

H.list_enhance_qf_loc = function(item)
  if item.end_lnum == 0 then item.end_lnum = nil end
  if item.end_col == 0 then item.end_col = nil end
  if H.is_valid_buf(item.bufnr) then
    local filename = vim.api.nvim_buf_get_name(item.bufnr)
    if filename ~= '' then item.filename = filename end
  end
  return item
end

H.list_enhance_item = function(item)
  if vim.fn.filereadable(item.filename) == 1 then item.path = item.filename end
  return H.pick_prepend_position(item)
end

-- Explorer picker ------------------------------------------------------------
H.explorer_make_items = function(path, filter, sort)
  if vim.fn.isdirectory(path) == 0 then return {} end
  local res = { { fs_type = 'directory', path = vim.fn.fnamemodify(path, ':h'), text = '..' } }
  for _, basename in ipairs(vim.fn.readdir(path)) do
    local subpath = string.format('%s/%s', path, basename)
    local fs_type = vim.fn.isdirectory(subpath) == 1 and 'directory' or 'file'
    table.insert(res, { fs_type = fs_type, path = subpath, text = basename .. (fs_type == 'directory' and '/' or '') })
  end

  return sort(vim.tbl_filter(filter, res))
end

H.explorer_default_sort = function(items)
  -- Sort ignoring case
  local res = vim.tbl_map(function(x)
      --stylua: ignore
      return {
        fs_type = x.fs_type, path = x.path, text = x.text,
        is_dir = x.fs_type == 'directory', lower_name = x.text:lower(),
      }
  end, items)

  local compare = function(a, b)
    -- Put directory first
    if a.is_dir and not b.is_dir then return true end
    if not a.is_dir and b.is_dir then return false end

    -- Otherwise order alphabetically ignoring case
    return a.lower_name < b.lower_name
  end

  table.sort(res, compare)

  return vim.tbl_map(function(x) return { fs_type = x.fs_type, path = x.path, text = x.text } end, res)
end

-- CLI ------------------------------------------------------------------------
H.cli_run = function(command, stdout_hook)
  stdout_hook = stdout_hook or function() end
  local executable, args = command[1], vim.list_slice(command, 2, #command)
  local process, stdout, stderr = nil, vim.loop.new_pipe(), vim.loop.new_pipe()
  local spawn_opts = { args = args, stdio = { nil, stdout, stderr } }
  process = vim.loop.spawn(executable, spawn_opts, function() process:close() end)

  H.cli_read_stream(stdout, stdout_hook)
  H.cli_read_stream(stderr, function(lines)
    local msg = table.concat(lines, '\n')
    if msg == '' then return end
    H.error(msg)
  end)
end

H.cli_show_output = function(buf_id, command)
  local stdout_hook = vim.schedule_wrap(function(lines)
    if not H.is_valid_buf(buf_id) then return end
    H.set_buflines(buf_id, lines)
  end)
  H.cli_run(command, stdout_hook)
end

H.cli_read_stream = function(stream, post_hook)
  local data_feed = {}
  local callback = function(err, data)
    assert(not err, err)
    if data ~= nil then return table.insert(data_feed, data) end

    local lines = vim.split(table.concat(data_feed), '\n')
    data_feed = nil
    stream:close()
    post_hook(lines)
  end
  stream:read_start(callback)
end

-- Buffers --------------------------------------------------------------------
H.is_valid_buf = function(buf_id) return type(buf_id) == 'number' and vim.api.nvim_buf_is_valid(buf_id) end

H.buf_ensure_loaded = function(buf_id)
  if type(buf_id) ~= 'number' or vim.api.nvim_buf_is_loaded(buf_id) then return end
  local cache_eventignore = vim.o.eventignore
  vim.o.eventignore = 'BufEnter'
  pcall(vim.fn.bufload, buf_id)
  vim.o.eventignore = cache_eventignore
end

H.buf_get_name = function(buf_id)
  if not H.is_valid_buf(buf_id) then return nil end
  local buf_name = vim.api.nvim_buf_get_name(buf_id)
  if buf_name ~= '' then buf_name = vim.fn.fnamemodify(buf_name, ':~:.') end
  return buf_name
end

H.set_buflines = function(buf_id, lines) vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines) end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.extra) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.set_buf_name = function(buf_id, name) vim.api.nvim_buf_set_name(buf_id, 'miniextra://' .. buf_id .. '/' .. name) end

H.is_valid_win = function(win_id) return type(win_id) == 'number' and vim.api.nvim_win_is_valid(win_id) end

H.ensure_text_width = function(text, width)
  local text_width = vim.fn.strchars(text)
  if text_width <= width then return text .. string.rep(' ', width - text_width) end
  return '…' .. vim.fn.strcharpart(text, text_width - width + 1, width - 1)
end

H.full_path = function(path) return (vim.fn.fnamemodify(path, ':p'):gsub('(.)/$', '%1')) end
H.normalize_path = function(path) return path end
if H.is_windows then
  H.full_path = function(path) return (vim.fn.fnamemodify(path, ':p'):gsub('(.)[\\/]$', '%1')) end
  H.normalize_path = function(path) return path:gsub('\\', '/') end
end

H.short_path = function(path, cwd)
  cwd = cwd or vim.fn.getcwd()
  -- Ensure `cwd` is treated as directory path (to not match similar prefix)
  cwd = cwd:sub(-1) == '/' and cwd or (cwd .. '/')
  return vim.startswith(path, cwd) and path:sub(cwd:len() + 1) or vim.fn.fnamemodify(path, ':~')
end

-- TODO: Remove after compatibility with Neovim=0.9 is dropped
H.islist = vim.fn.has('nvim-0.10') == 1 and vim.islist or vim.tbl_islist

return MiniExtra
