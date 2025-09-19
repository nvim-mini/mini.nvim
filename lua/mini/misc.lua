--- *mini.misc* Miscellaneous functions
--- *MiniMisc*
---
--- MIT License Copyright (c) 2021 Evgeni Chasnovski
---
--- ==============================================================================
---
--- Features the following functions:
--- - |MiniMisc.bench_time()| to benchmark function execution time.
---   Useful in combination with `stat_summary()`.
---
--- - |MiniMisc.peek()| to peek a line by entering the linenr in cmdline.
---
--- - |MiniMisc.put()| and |MiniMisc.put_text()| to pretty print its arguments
---   into command line and current buffer respectively.
---
--- - |MiniMisc.setup_auto_root()| to set up automated change of current directory.
---
--- - |MiniMisc.setup_termbg_sync()| to set up terminal background synchronization
---   (removes possible "frame" around current Neovim instance).
---
--- - |MiniMisc.setup_restore_cursor()| to set up automated restoration of
---   cursor position on file reopen.
---
--- - |MiniMisc.stat_summary()| to compute summary statistics of numerical array.
---   Useful in combination with `bench_time()`.
---
--- - |MiniMisc.tbl_head()| and |MiniMisc.tbl_tail()| to return "first" and "last"
---   elements of table.
---
--- - |MiniMisc.zoom()| to zoom in and out of a buffer, making it full screen
---   in a floating window.
---
--- - And more.
---
--- # Setup ~
---
--- This module doesn't need setup, but it can be done to improve usability.
--- Setup with `require('mini.misc').setup({})` (replace `{}` with your
--- `config` table). It will create global Lua table `MiniMisc` which you can
--- use for scripting or manually (with `:lua MiniMisc.*`).
---
--- See |MiniMisc.config| for `config` structure and default values.
---
--- This module doesn't have runtime options, so using `vim.b.minimisc_config`
--- will have no effect here.

-- Module definition ==========================================================
local MiniMisc = {}
local H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniMisc.config|.
---
---@usage >lua
---   require('mini.misc').setup() -- use default config
---   -- OR
---   require('mini.misc').setup({}) -- replace {} with your config table
--- <
MiniMisc.setup = function(config)
  -- Export module
  _G.MiniMisc = MiniMisc

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)
end

--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
MiniMisc.config = {
  -- Array of fields to make global (to be used as independent variables)
  make_global = { 'put', 'put_text' },
}
--minidoc_afterlines_end

-- Module functionality =======================================================
--- Execute `f` several times and time how long it took
---
---@param f function Function which execution to benchmark.
---@param n number|nil Number of times to execute `f(...)`. Default: 1.
---@param ... any Arguments when calling `f`.
---
---@return ... Table with durations (in seconds; up to nanoseconds) and
---   output of (last) function execution.
MiniMisc.bench_time = function(f, n, ...)
  n = n or 1
  local durations, output = {}, nil
  for _ = 1, n do
    local start_time = vim.loop.hrtime()
    output = f(...)
    local end_time = vim.loop.hrtime()
    table.insert(durations, 0.000000001 * (end_time - start_time))
  end

  return durations, output
end

--- Compute width of gutter (info column on the left of the window)
---
---@param win_id number|nil Window identifier (see |win_getid()|) for which gutter
---   width is computed. Default: 0 for current.
MiniMisc.get_gutter_width = function(win_id)
  win_id = (win_id == nil or win_id == 0) and vim.api.nvim_get_current_win() or win_id
  return vim.fn.getwininfo(win_id)[1].textoff
end

--- Peek a line by entering the linenr in cmdline.
MiniMisc.peek = function()
  local win_states = {}
  local options = { foldenable = false, cursorline = true, number = true, relativenumber = false }

  local function save_win_state(winnr)
    win_states[winnr] = {}
    for option, _ in pairs(options) do
      win_states[winnr][option] = vim.api.nvim_get_option_value(option, { win = winnr })
    end
    win_states[winnr].cursor = vim.api.nvim_win_get_cursor(winnr)
  end

  local function restore_win_state(winnr)
    if not win_states[winnr] then return end

    for option, _ in pairs(options) do
      vim.api.nvim_set_option_value(option, win_states[winnr][option], { win = winnr })
    end
    vim.api.nvim_win_set_cursor(winnr, win_states[winnr].cursor)

    win_states[winnr] = nil
  end

  local goto_linenr = function(winnr, linenr)
    linenr = math.max(math.min(linenr, vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(winnr))), 1)

    if not win_states[winnr] then save_win_state(winnr) end

    for option, value in pairs(options) do
      vim.api.nvim_set_option_value(option, value, { win = winnr })
    end
    vim.api.nvim_win_set_cursor(winnr, { linenr, 1 })

    vim.cmd('redraw')
  end

  vim.api.nvim_create_autocmd('CmdlineChanged', {
    pattern = '*',
    callback = function()
      local cmdline_str = vim.api.nvim_call_function('getcmdline', {})
      if tonumber(cmdline_str) then goto_linenr(vim.api.nvim_get_current_win(), tonumber(cmdline_str)) end
    end,
  })

  vim.api.nvim_create_autocmd('CmdlineLeave', {
    pattern = '*',
    callback = function() restore_win_state(vim.api.nvim_get_current_win()) end,
  })
end

--- Print Lua objects in command line
---
---@param ... any Any number of objects to be printed each on separate line.
MiniMisc.put = function(...)
  local objects = {}
  -- Not using `{...}` because it removes `nil` input
  for i = 1, select('#', ...) do
    local v = select(i, ...)
    table.insert(objects, vim.inspect(v))
  end

  print(table.concat(objects, '\n'))

  return ...
end

--- Print Lua objects in current buffer
---
---@param ... any Any number of objects to be printed each on separate line.
MiniMisc.put_text = function(...)
  local objects = {}
  -- Not using `{...}` because it removes `nil` input
  for i = 1, select('#', ...) do
    local v = select(i, ...)
    table.insert(objects, vim.inspect(v))
  end

  local lines = vim.split(table.concat(objects, '\n'), '\n')
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  vim.fn.append(lnum, lines)

  return ...
end

--- Resize window to have exact number of editable columns
---
---@param win_id number|nil Window identifier (see |win_getid()|) to be resized.
---   Default: 0 for current.
---@param text_width number|nil Number of editable columns resized window will
---   display. Default: first element of 'colorcolumn' or otherwise 'textwidth'
---   (using screen width as its default but not more than 79).
MiniMisc.resize_window = function(win_id, text_width)
  win_id = win_id or 0
  text_width = text_width or H.default_text_width(win_id)

  vim.api.nvim_win_set_width(win_id, text_width + MiniMisc.get_gutter_width(win_id))
end

H.default_text_width = function(win_id)
  local buf = vim.api.nvim_win_get_buf(win_id)
  local textwidth = vim.bo[buf].textwidth
  textwidth = (textwidth == 0) and math.min(vim.o.columns, 79) or textwidth

  local colorcolumn = vim.wo[win_id].colorcolumn
  if colorcolumn ~= '' then
    local cc = vim.split(colorcolumn, ',')[1]
    local is_cc_relative = vim.tbl_contains({ '-', '+' }, cc:sub(1, 1))

    if is_cc_relative then
      return textwidth + tonumber(cc)
    else
      return tonumber(cc)
    end
  else
    return textwidth
  end
end

--- Set up automated change of current directory
---
--- What it does:
--- - Creates autocommand which on every |BufEnter| event with |MiniMisc.find_root()|
---   finds root directory for current buffer file and sets |current-directory|
---   to it (using |chdir()|).
--- - Resets |autochdir| to `false`.
---
---@param names table|function|nil Forwarded to |MiniMisc.find_root()|.
---@param fallback function|nil Forwarded to |MiniMisc.find_root()|.
---
---@usage >lua
---   require('mini.misc').setup()
---   MiniMisc.setup_auto_root()
--- <
MiniMisc.setup_auto_root = function(names, fallback)
  names = names or { '.git', 'Makefile' }
  if not (H.is_array_of(names, H.is_string) or vim.is_callable(names)) then
    H.error('Argument `names` of `setup_auto_root()` should be array of string file names or a callable.')
  end

  fallback = fallback or function() return nil end
  if not vim.is_callable(fallback) then H.error('Argument `fallback` of `setup_auto_root()` should be callable.') end

  -- Disable conflicting option
  vim.o.autochdir = false

  -- Create autocommand
  local set_root = vim.schedule_wrap(function(data)
    if data.buf ~= vim.api.nvim_get_current_buf() then return end
    local root = MiniMisc.find_root(data.buf, names, fallback)
    if root == nil then return end
    vim.fn.chdir(root)
  end)
  local augroup = vim.api.nvim_create_augroup('MiniMiscAutoRoot', {})
  local opts = { group = augroup, nested = true, callback = set_root, desc = 'Find root and change current directory' }
  vim.api.nvim_create_autocmd('BufEnter', opts)
end

--- Find root directory
---
--- Based on a buffer name (full path to file opened in a buffer) find a root
--- directory. If buffer is not associated with file, returns `nil`.
---
--- Root directory is a directory containing at least one of pre-defined files.
--- It is searched using |vim.fn.find()| with `upward = true` starting from
--- directory of current buffer file until first occurrence of root file(s).
---
--- Notes:
--- - Uses directory path caching to speed up computations. This means that no
---   changes in root directory will be detected after directory path was already
---   used in this function. Reload Neovim to account for that.
---
---@param buf_id number|nil Buffer identifier (see |bufnr()|) to use.
---   Default: 0 for current.
---@param names table|function|nil Array of file names or a callable used to
---   identify a root directory. Forwarded to |vim.fs.find()|.
---   Default: `{ '.git', 'Makefile' }`.
---@param fallback function|nil Callable fallback to use if no root is found
---   with |vim.fs.find()|. Will be called with a buffer path and should return
---   a valid directory path.
MiniMisc.find_root = function(buf_id, names, fallback)
  buf_id = buf_id or 0
  names = names or { '.git', 'Makefile' }
  fallback = fallback or function() return nil end

  if not H.is_valid_buf(buf_id) then H.error('Argument `buf_id` of `find_root()` should be valid buffer id.') end
  if not (H.is_array_of(names, H.is_string) or vim.is_callable(names)) then
    H.error('Argument `names` of `find_root()` should be array of string file names or a callable.')
  end
  if not vim.is_callable(fallback) then H.error('Argument `fallback` of `find_root()` should be callable.') end

  -- Compute directory to start search from. NOTEs on why not using file path:
  -- - This has better performance because `vim.fs.find()` is called less.
  -- - *Needs* to be a directory for callable `names` to work.
  -- - Later search is done including initial `path` if directory, so this
  --   should work for detecting buffer directory as root.
  local path = vim.api.nvim_buf_get_name(buf_id)
  if path == '' then return end
  local dir_path = vim.fs.dirname(path)

  -- Try using cache
  local res = H.root_cache[dir_path]
  if res ~= nil then return res end

  -- Find root
  local root_file = vim.fs.find(names, { path = dir_path, upward = true })[1]
  if root_file ~= nil then
    res = vim.fs.dirname(root_file)
  else
    res = fallback(path)
  end

  -- Use absolute path to an existing directory
  if type(res) ~= 'string' then return end
  res = vim.fs.normalize(vim.fn.fnamemodify(res, ':p'))
  if vim.fn.isdirectory(res) == 0 then return end

  -- Cache result per directory path
  H.root_cache[dir_path] = res

  return res
end

H.root_cache = {}

--- Set up terminal background synchronization
---
--- What it does:
--- - Checks if terminal emulator supports OSC 11 control sequence through
---   appropriate `stdout`. Stops if not.
--- - Creates autocommands for |ColorScheme| and |VimResume| events, which
---   change terminal background to have same color as |guibg| of |hl-Normal|.
--- - Creates autocommands for |VimLeavePre| and |VimSuspend| events which set
---   terminal background back to the color at the time this function was
---   called first time in current session.
--- - Synchronizes background immediately to allow not depend on loading order.
---
--- Primary use case is to remove possible "frame" around current Neovim instance
--- which appears if Neovim's |hl-Normal| background color differs from what is
--- used by terminal emulator itself.
---
--- Works only on Neovim>=0.10.
MiniMisc.setup_termbg_sync = function()
  -- Handling `'\027]11;?\007'` response was added in Neovim 0.10
  if vim.fn.has('nvim-0.10') == 0 then return H.notify('`setup_termbg_sync()` requires Neovim>=0.10', 'WARN') end

  -- Proceed only if there is a valid stdout to use
  local has_stdout_tty = false
  for _, ui in ipairs(vim.api.nvim_list_uis()) do
    has_stdout_tty = has_stdout_tty or ui.stdout_tty
  end
  if not has_stdout_tty then return end

  local augroup = vim.api.nvim_create_augroup('MiniMiscTermbgSync', { clear = true })
  local track_au_id, bad_responses, had_proper_response = nil, {}, false
  local f = function(args)
    -- Process proper response only once
    if had_proper_response then return end

    -- Neovim=0.10 uses string sequence as response, while Neovim>=0.11 sets it
    -- in `sequence` table field
    local seq = type(args.data) == 'table' and args.data.sequence or args.data
    local ok, termbg = pcall(H.parse_osc11, seq)
    if not (ok and type(termbg) == 'string') then return table.insert(bad_responses, seq) end
    had_proper_response = true
    pcall(vim.api.nvim_del_autocmd, track_au_id)

    -- Set up reset to the color returned from the very first call
    H.termbg_init = H.termbg_init or termbg
    local reset = function() io.stdout:write('\027]11;' .. H.termbg_init .. '\007') end
    vim.api.nvim_create_autocmd({ 'VimLeavePre', 'VimSuspend' }, { group = augroup, callback = reset })

    -- Set up sync
    local sync = function()
      local normal = vim.api.nvim_get_hl_by_name('Normal', true)
      if normal.background == nil then return reset() end
      -- NOTE: use `io.stdout` instead of `io.write` to ensure correct target
      -- Otherwise after `io.output(file); file:close()` there is an error
      io.stdout:write(string.format('\027]11;#%06x\007', normal.background))
    end
    vim.api.nvim_create_autocmd({ 'VimResume', 'ColorScheme' }, { group = augroup, callback = sync })

    -- Sync immediately
    sync()
  end

  -- Ask about current background color and process the proper response.
  -- NOTE: do not use `once = true` as Neovim itself triggers `TermResponse`
  -- events during startup, so this should wait until the proper one.
  track_au_id = vim.api.nvim_create_autocmd('TermResponse', { group = augroup, callback = f, nested = true })
  io.stdout:write('\027]11;?\007')
  vim.defer_fn(function()
    if had_proper_response then return end
    pcall(vim.api.nvim_del_augroup_by_id, augroup)
    local bad_suffix = #bad_responses == 0 and '' or (', only these: ' .. vim.inspect(bad_responses))
    local msg = '`setup_termbg_sync()` did not get proper response from terminal emulator' .. bad_suffix
    H.notify(msg, 'WARN')
  end, 1000)
end

-- Source: 'runtime/lua/vim/_defaults.lua' in Neovim source
H.parse_osc11 = function(x)
  local r, g, b = x:match('^\027%]11;rgb:(%x+)/(%x+)/(%x+)$')
  if not (r and g and b) then
    local a
    r, g, b, a = x:match('^\027%]11;rgba:(%x+)/(%x+)/(%x+)/(%x+)$')
    if not (a and a:len() <= 4) then return end
  end
  if not (r and g and b) then return end
  if not (r:len() <= 4 and g:len() <= 4 and b:len() <= 4) then return end
  local parse_osc_hex = function(c) return c:len() == 1 and (c .. c) or c:sub(1, 2) end
  return '#' .. parse_osc_hex(r) .. parse_osc_hex(g) .. parse_osc_hex(b)
end

--- Restore cursor position on file open
---
--- When reopening a file this will make sure the cursor is placed back to the
--- position where you left before. This implements |restore-cursor| in a nicer way.
--- File should have a recognized file type (see 'filetype') and be opened in
--- a normal buffer (see 'buftype').
---
--- Note: it relies on file mark data stored in 'shadafile' (see |shada-f|).
--- Be sure to enable it.
---
---@param opts table|nil Options for |MiniMisc.restore_cursor|. Possible fields:
---   - <center> - (boolean) Center the window after we restored the cursor.
---     Default: `true`.
---   - <ignore_filetype> - Array with file types to be ignored (see 'filetype').
---     Default: `{ "gitcommit", "gitrebase" }`.
---
---@usage >lua
---   require('mini.misc').setup_restore_cursor()
--- <
MiniMisc.setup_restore_cursor = function(opts)
  opts = opts or {}

  opts.ignore_filetype = opts.ignore_filetype or { 'gitcommit', 'gitrebase' }
  if not H.is_array_of(opts.ignore_filetype, H.is_string) then
    H.error('In `setup_restore_cursor()` `opts.ignore_filetype` should be an array of strings.')
  end

  if opts.center == nil then opts.center = true end
  if type(opts.center) ~= 'boolean' then H.error('In `setup_restore_cursor()` `opts.center` should be a boolean.') end

  -- Create autocommand which runs once on `FileType` for every new buffer
  local augroup = vim.api.nvim_create_augroup('MiniMiscRestoreCursor', {})
  vim.api.nvim_create_autocmd('BufReadPre', {
    group = augroup,
    callback = function(data)
      vim.api.nvim_create_autocmd('FileType', {
        buffer = data.buf,
        once = true,
        callback = function() H.restore_cursor(opts) end,
      })
    end,
  })
end

H.restore_cursor = function(opts)
  -- Stop if not a normal buffer
  if vim.bo.buftype ~= '' then return end

  -- Stop if filetype is ignored
  if vim.tbl_contains(opts.ignore_filetype, vim.bo.filetype) then return end

  -- Stop if line is already specified (like during start with `nvim file +num`)
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  if cursor_line > 1 then return end

  -- Stop if can't restore proper line for some reason
  local mark_line = vim.api.nvim_buf_get_mark(0, [["]])[1]
  local n_lines = vim.api.nvim_buf_line_count(0)
  if not (1 <= mark_line and mark_line <= n_lines) then return end

  -- Restore cursor and open just enough folds
  vim.cmd([[normal! g`"zv]])

  -- Center window
  if opts.center then vim.cmd('normal! zz') end
end

--- Compute summary statistics of numerical array
---
--- This might be useful to compute summary of time benchmarking with
--- |MiniMisc.bench_time|.
---
---@param t table Array (table suitable for `ipairs`) of numbers.
---
---@return table Table with summary values under following keys (may be
---   extended in the future): <maximum>, <mean>, <median>, <minimum>, <n>
---   (number of elements), <sd> (sample standard deviation).
MiniMisc.stat_summary = function(t)
  if not H.is_array_of(t, H.is_number) then
    H.error('Input of `MiniMisc.stat_summary()` should be an array of numbers.')
  end

  -- Welford algorithm of computing variance
  -- Source: https://www.johndcook.com/blog/skewness_kurtosis/
  local n = #t
  local delta, m1, m2 = 0, 0, 0
  local minimum, maximum = math.huge, -math.huge
  for i, x in ipairs(t) do
    delta = x - m1
    m1 = m1 + delta / i
    m2 = m2 + delta * (x - m1)

    -- Extremums
    minimum = x < minimum and x or minimum
    maximum = x > maximum and x or maximum
  end

  return {
    maximum = maximum,
    mean = m1,
    median = H.compute_median(t),
    minimum = minimum,
    n = n,
    sd = math.sqrt(n > 1 and m2 / (n - 1) or 0),
  }
end

H.compute_median = function(t)
  local n = #t
  if n == 0 then return 0 end

  local t_sorted = vim.deepcopy(t)
  table.sort(t_sorted)
  return 0.5 * (t_sorted[math.ceil(0.5 * n)] + t_sorted[math.ceil(0.5 * (n + 1))])
end

--- Return "first" elements of table as decided by `pairs`
---
--- Note: order of elements might vary.
---
---@param t table Input table.
---@param n number|nil Maximum number of first elements. Default: 5.
---
---@return table Table with at most `n` first elements of `t` (with same keys).
MiniMisc.tbl_head = function(t, n)
  n = n or 5
  local res, n_res = {}, 0
  for k, val in pairs(t) do
    if n_res >= n then return res end
    res[k] = val
    n_res = n_res + 1
  end
  return res
end

--- Return "last" elements of table as decided by `pairs`
---
--- This function makes two passes through elements of `t`:
--- - First to count number of elements.
--- - Second to construct result.
---
--- Note: order of elements might vary.
---
---@param t table Input table.
---@param n number|nil Maximum number of last elements. Default: 5.
---
---@return table Table with at most `n` last elements of `t` (with same keys).
MiniMisc.tbl_tail = function(t, n)
  n = n or 5

  -- Count number of elements on first pass
  local n_all = 0
  for _, _ in pairs(t) do
    n_all = n_all + 1
  end

  -- Construct result on second pass
  local res = {}
  local i, start_i = 0, n_all - n + 1
  for k, val in pairs(t) do
    i = i + 1
    if i >= start_i then res[k] = val end
  end
  return res
end

--- Add possibility of nested comment leader
---
--- This works by parsing 'commentstring' buffer option, extracting
--- non-whitespace comment leader (symbols on the left of commented line), and
--- locally modifying 'comments' option (by prepending `n:<leader>`). Does
--- nothing if 'commentstring' is empty or has comment symbols both in front
--- and back (like "/*%s*/").
---
--- Nested comment leader added with this function is useful for formatting
--- nested comments. For example, have in Lua "first-level" comments with '--'
--- and "second-level" comments with '----'. With nested comment leader second
--- type can be formatted with `gq` in the same way as first one.
---
--- Recommended usage is with |autocmd|: >lua
---
---   local use_nested_comments = function() MiniMisc.use_nested_comments() end
---   vim.api.nvim_create_autocmd('BufEnter', { callback = use_nested_comments })
--- <
--- Note: for most filetypes 'commentstring' option is added only when buffer
--- with this filetype is entered, so using non-current `buf_id` can not lead
--- to desired effect.
---
---@param buf_id number|nil Buffer identifier (see |bufnr()|) in which function
---   will operate. Default: 0 for current.
MiniMisc.use_nested_comments = function(buf_id)
  buf_id = buf_id or 0

  local commentstring = vim.bo[buf_id].commentstring
  if commentstring == '' then return end

  -- Extract raw comment leader from 'commentstring' option
  local comment_parts = vim.tbl_filter(function(x) return x ~= '' end, vim.split(commentstring, '%s', true))

  -- Don't do anything if 'commentstring' is like '/*%s*/' (as in 'json')
  if #comment_parts > 1 then return end

  -- Get comment leader by removing whitespace
  local leader = vim.trim(comment_parts[1])

  local comments = vim.bo[buf_id].comments
  vim.bo[buf_id].comments = string.format('n:%s,%s', leader, comments)
end

--- Zoom in and out of a buffer, making it full screen in a floating window
---
--- This function is useful when working with multiple windows but temporarily
--- needing to zoom into one to see more of the code from that buffer. Call it
--- again (without arguments) to zoom out.
---
---@param buf_id number|nil Buffer identifier (see |bufnr()|) to be zoomed.
---   Default: 0 for current.
---@param config table|nil Optional config for window (as for |nvim_open_win()|).
---
---@return boolean Whether current buffer is zoomed in.
MiniMisc.zoom = function(buf_id, config)
  -- Hide
  if H.zoom_winid and vim.api.nvim_win_is_valid(H.zoom_winid) then
    pcall(vim.api.nvim_del_augroup_by_name, 'MiniMiscZoom')
    vim.api.nvim_win_close(H.zoom_winid, true)
    H.zoom_winid = nil
    return false
  end

  -- Show
  local compute_config = function()
    -- Use precise dimensions for no Command line interactions (better scroll)
    local max_width, max_height = vim.o.columns, vim.o.lines - vim.o.cmdheight
    local default_border = (vim.fn.exists('+winborder') == 1 and vim.o.winborder ~= '') and vim.o.winborder or 'none'
    --stylua: ignore
    local default_config = {
      relative = 'editor', row = 0, col = 0,
      width = max_width, height = max_height,
      title = ' Zoom ', border = default_border,
    }
    local res = vim.tbl_deep_extend('force', default_config, config or {})

    -- Adjust dimensions to fit actually present border parts
    local bor = res.border == 'none' and { '' } or res.border
    local n = type(bor) == 'table' and #bor or 0
    local height_offset = n == 0 and 2 or ((bor[1 % n + 1] == '' and 0 or 1) + (bor[5 % n + 1] == '' and 0 or 1))
    local width_offset = n == 0 and 2 or ((bor[3 % n + 1] == '' and 0 or 1) + (bor[7 % n + 1] == '' and 0 or 1))
    res.height = math.min(res.height, max_height - height_offset)
    res.width = math.min(res.width, max_width - width_offset)

    -- Ensure proper title
    if type(res.title) == 'string' then res.title = H.fit_to_width(res.title, res.width) end

    return res
  end
  H.zoom_winid = vim.api.nvim_open_win(buf_id or 0, true, compute_config())
  vim.wo[H.zoom_winid].winblend = 0
  vim.cmd('normal! zz')

  -- - Make sure zoom window is adjusting to changes in its hyperparameters
  local gr = vim.api.nvim_create_augroup('MiniMiscZoom', { clear = true })
  local adjust_config = function()
    if not (type(H.zoom_winid) == 'number' and vim.api.nvim_win_is_valid(H.zoom_winid)) then
      pcall(vim.api.nvim_del_augroup_by_name, 'MiniMiscZoom')
      return
    end
    vim.api.nvim_win_set_config(H.zoom_winid, compute_config())
  end
  vim.api.nvim_create_autocmd('VimResized', { group = gr, callback = adjust_config })
  vim.api.nvim_create_autocmd('OptionSet', { group = gr, pattern = 'cmdheight', callback = adjust_config })
  return true
end

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniMisc.config)

-- Window identifier of current zoom (for `zoom()`)
H.zoom_winid = nil

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  -- NOTE: Don't use `tbl_deep_extend` to prefer full input `make_global` array
  -- Needs adjusting if there is a new setting with nested tables
  config = vim.tbl_extend('force', vim.deepcopy(H.default_config), config or {})

  H.check_type('make_global', config.make_global, 'table')
  for _, v in pairs(config.make_global) do
    if MiniMisc[v] == nil then H.error("`make_global` should be a table with exported 'mini.misc' methods") end
  end

  return config
end

H.apply_config = function(config)
  MiniMisc.config = config

  for _, v in pairs(config.make_global) do
    _G[v] = MiniMisc[v]
  end
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.misc) ' .. msg) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.notify = function(msg, level) vim.notify('(mini.misc) ' .. msg, vim.log.levels[level]) end

H.is_valid_buf = function(buf_id) return type(buf_id) == 'number' and vim.api.nvim_buf_is_valid(buf_id) end

H.is_array_of = function(x, predicate)
  if not H.islist(x) then return false end
  for _, v in ipairs(x) do
    if not predicate(v) then return false end
  end
  return true
end

H.is_number = function(x) return type(x) == 'number' end

H.is_string = function(x) return type(x) == 'string' end

H.fit_to_width = function(text, width)
  local t_width = vim.fn.strchars(text)
  return t_width <= width and text or ('…' .. vim.fn.strcharpart(text, t_width - width + 1, width - 1))
end

-- TODO: Remove after compatibility with Neovim=0.9 is dropped
H.islist = vim.fn.has('nvim-0.10') == 1 and vim.islist or vim.tbl_islist

return MiniMisc
