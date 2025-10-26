--- *mini.git* Git integration
---
--- MIT License Copyright (c) 2024 Evgeni Chasnovski

--- Features:
---
--- - Automated tracking of Git related data: root path, status, HEAD, etc.
---   Exposes buffer-local variables for convenient use in statusline.
---   See |MiniGit.enable()| and |MiniGit.get_buf_data()| for more information.
---
--- - |:Git| command for executing any `git` call inside file's repository root with
---   deeper current instance integration (show output as notification/buffer,
---   use to edit commit messages, etc.).
---
--- - Helper functions to inspect Git history:
---     - |MiniGit.show_range_history()| shows how certain line range evolved.
---     - |MiniGit.show_diff_source()| shows file state as it was at diff entry.
---     - |MiniGit.show_at_cursor()| shows Git related data depending on context.
---
--- What it doesn't do:
---
--- - Replace fully featured Git client. Rule of thumb: if feature does not rely
---   on a state of current Neovim (opened buffers, etc.), it is out of scope.
---   For more functionality, use either |mini.diff| or fully featured Git client.
---
--- Sources with more details:
--- - |:Git|
--- - |MiniGit-examples|
--- - |MiniGit.enable()|
--- - |MiniGit.get_buf_data()|
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.git').setup({})` (replace `{}` with
--- your `config` table). It will create global Lua table `MiniGit` which you can use
--- for scripting or manually (with `:lua MiniGit.*`).
---
--- See |MiniGit.config| for `config` structure and default values.
---
--- # Comparisons ~
---
--- - [tpope/vim-fugitive](https://github.com/tpope/vim-fugitive):
---     - Mostly a dedicated Git client, while this module is not (by design).
---     - Provides buffer-local Git data only through fixed statusline component,
---       while this module has richer data in the form of a Lua table.
---     - Both provide |:Git| command with 'vim-fugitive' treating some cases
---       extra specially (like `:Git blame`, etc.), while this module mostly
---       treats all cases the same. See |MiniGit-examples| for how they can be
---       manually customized.
---       Also this module provides slightly different (usually richer)
---       completion suggestions.
---
--- - [NeogitOrg/neogit](https://github.com/NeogitOrg/neogit):
---     - Similar to 'tpope/vim-fugitive', but without `:Git` command.
---
--- - [lewis6991/gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim):
---     - Provides buffer-local Git data with emphasis on granular diff status,
---       while this module is more oriented towards repository and file level
---       data (root, HEAD, file status, etc.). Use |mini.diff| for diff tracking.
---
--- # Disabling ~
---
--- To prevent buffer(s) from being tracked, set `vim.g.minigit_disable` (globally)
--- or `vim.b.minigit_disable` (for a buffer) to `true`. Considering high number of
--- different scenarios and customization intentions, writing exact rules for
--- disabling module's functionality is left to user.
--- See |mini.nvim-disabling-recipes| for common recipes.
---@tag MiniGit

--- # Statusline component ~
---
--- Tracked buffer data can be used in statusline via `vim.b.minigit_summary_string`
--- buffer-local variable. It is expected to be used as is. To show another info,
--- tweak buffer-local variable directly inside `MiniGitUpdated` `User` event: >lua
---
---   -- Use only HEAD name as summary string
---   local format_summary = function(data)
---     -- Utilize buffer-local table summary
---     local summary = vim.b[data.buf].minigit_summary
---     vim.b[data.buf].minigit_summary_string = summary.head_name or ''
---   end
---
---   local au_opts = { pattern = 'MiniGitUpdated', callback = format_summary }
---   vim.api.nvim_create_autocmd('User', au_opts)
--- <
--- # Tweaking command output ~
---
--- Buffer output of |:Git| command can be tweaked inside autocommand for
--- `MiniGitCommandSplit` `User` event (see |MiniGit-command-events|).
--- For example, to make `:vertical Git blame -- %` align blame output with the
--- current window state, use the following code: >lua
---
---   local align_blame = function(au_data)
---     if au_data.data.git_subcommand ~= 'blame' then return end
---
---     -- Align blame output with source
---     local win_src = au_data.data.win_source
---     vim.wo.wrap = false
---     vim.fn.winrestview({ topline = vim.fn.line('w0', win_src) })
---     vim.api.nvim_win_set_cursor(0, { vim.fn.line('.', win_src), 0 })
---
---     -- Bind both windows so that they scroll together
---     vim.wo[win_src].scrollbind, vim.wo.scrollbind = true, true
---   end
---
---   local au_opts = { pattern = 'MiniGitCommandSplit', callback = align_blame }
---   vim.api.nvim_create_autocmd('User', au_opts)
--- <
--- # History navigation ~
---
--- Function |MiniGit.show_at_cursor()| is specifically exported to make Git
--- history navigation easier. Here are some different ways it can be used:
---
--- - Call inside buffer for already committed file to show the evolution of
---   the current line (or visually selected range) through history.
---   It is essentially a `:Git log HEAD` with proper `-L` flag.
---   This also works inside output of |MiniGit.show_diff_source()|.
---
--- - Call with cursor on commit hash to inspect that commit in full.
---   This is usually helpful in the output of `:Git log`.
---
--- - Call with cursor inside diff entry to inspect its file in the state how it
---   was at certain commit. By default it shows state after commit, unless cursor
---   is on the "deleted" line (i.e. line starting with "-") in which case
---   state before commit is shown.
---
--- This workflow can be made more interactive when used with mapping, like this: >lua
---
---   local rhs = '<Cmd>lua MiniGit.show_at_cursor()<CR>'
---   vim.keymap.set({ 'n', 'x' }, '<Leader>gs', rhs, { desc = 'Show at cursor' })
--- <
---@tag MiniGit-examples

--- The `:Git` user command runs `git` CLI call with extra integration for currently
--- opened Neovim process:
--- - Command is executed inside repository root of the currently active file
---   (or |current-directory| if file is not tracked by this module).
---
--- - Command output is shown either in dedicated buffer in window split or as
---   notification via |vim.notify()|. Which method is used depends on whether
---   particular Git subcommand is supposed to show data for user to inspect
---   (like `log`, `status`, etc.) or not (like `commit`, `push`, etc.). This is
---   determined automatically based on the data Git itself provides.
---   Split window is made current after command execution.
---
---   Use split-related |:command-modifiers| (|:vertical|, |:horizontal|, or |:tab|)
---   to force output in a particular type of split. Default split direction is
---   controlled by `command.split` in |MiniGit.config|.
---
---   Use |:silent| command modifier to not show any output.
---
---   Errors and warnings are always shown as notifications.
---
---   See |MiniGit-examples| for the example of tweaking command output.
---
--- - Editor for tasks that require interactive user input (like `:Git commit` or
---   `:Git rebase --interactive`) is opened inside current session in a separate
---   split. Make modifications as in regular buffer, |:write| changes followed by
---   |:close| / |:quit| for Git CLI command to resume.
---
--- Examples of usage:
--- - `:Git log --oneline` - show compact log of current repository.
--- - `:vert Git blame -- %` - show latest commits per line in vertical split.
--- - `:Git help rebase` - show help page for `rebase` subcommand.
--- - `:Git -C <cwd> status` - execute `git status` inside |current-directory|.
---
--- There is also a context aware completion which can be invoked with `<Tab>`:
--- - If completed word starts with "-", options for the current Git subcommand
---   are shown. Like completion at `:Git log -` will suggest `-L`, `--oneline`, etc.
--- - If there is an explicit " -- " to the cursor's left, incremental path
---   suggestions will be shown.
--- - If there is no recognized Git subcommand yet, show list of subcommands.
---   Otherwise for some common subcommands list of its targets will be suggested:
---   like for `:Git branch` it will be list of branches, etc.
---
--- Notes:
--- - Paths are always treated as relative to command's execution directory
---   (file's repository root or |current-directory| if absent).
--- - Don't use quotes for entries containing space, escape it with `\` directly.
---   Like `:Git commit -m Hello\ world` and not `:Git commit -m 'Hello world'`
---   (which treats `'Hello` and `world'` as separate arguments).
---
--- # Events ~
--- *MiniGit-command-events*
---
--- There are several `User` events triggered during command execution:
---
--- - `MiniGitCommandDone` - after command is done executing. For Lua callbacks it
---   provides a special `data` table with the following fields:
---     - <cmd_input> `(table)` - structured data about executed command.
---       Has same structure as Lua function input in |nvim_create_user_command()|.
---     - <cwd> `(string)` - directory path inside which Git command was executed.
---     - <exit_code> `(number)` - exit code of CLI process.
---     - <git_command> `(table)` - array with arguments of full executed command.
---     - <git_subcommand> `(string)` - detected Git subcommand (like "log", etc.).
---     - <stderr> `(string)` - `stderr` process output.
---     - <stdout> `(string)` - `stdout` process output.
---
--- - `MiniGitCommandSplit` - after command showed its output in a split. Triggered
---   after `MiniGitCommandDone` and provides similar `data` table with extra fields:
---     - <win_source> `(number)` - window identifier of "source" window (current at
---       the moment before command execution).
---     - <win_stdout> `(number)` - window identifier of command output.
---@tag :Git

---@alias __git_buf_id number Target buffer identifier. Default: 0 for current buffer.
---@alias __git_split_field <split> `(string)` - split direction. One of "horizontal", "vertical",
---     "tab", or "auto" (default). Value "auto" uses |:vertical| if only 'mini.git'
---     buffers are shown in the tabpage and |:tab| otherwise.

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local
---@diagnostic disable:cast-local-type
---@diagnostic disable:undefined-doc-name
---@diagnostic disable:luadoc-miss-type-name

-- Module definition ==========================================================
local MiniGit = {}
local H = {}

--- Module setup
---
--- Besides general side effects (see |mini.nvim|), it also:
--- - Sets up auto enabling in every normal buffer for an actual file on disk.
--- - Creates |:Git| command.
---
---@param config table|nil Module config table. See |MiniGit.config|.
---
---@usage >lua
---   require('mini.git').setup() -- use default config
---   -- OR
---   require('mini.git').setup({}) -- replace {} with your config table
--- <
MiniGit.setup = function(config)
  -- Export module
  _G.MiniGit = MiniGit

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Ensure proper Git executable
  local exec = config.job.git_executable
  H.has_git = vim.fn.executable(exec) == 1
  if not H.has_git then H.notify('There is no `' .. exec .. '` executable', 'WARN') end

  -- Define behavior
  H.create_autocommands()
  for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
    H.auto_enable({ buf = buf_id })
  end

  -- Create user commands
  H.create_user_commands()
end

--stylua: ignore
--- Defaults ~
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text # Job ~
---
--- `config.job` contains options for customizing CLI executions.
---
--- `job.git_executable` defines a full path to Git executable. Default: "git".
---
--- `job.timeout` is a duration (in ms) from job start until it is forced to stop.
--- Default: 30000.
---
--- # Command ~
---
--- `config.command` contains options for customizing |:Git| command.
---
--- `command.split` defines default split direction for |:Git| command output. Can be
--- one of "horizontal", "vertical", "tab", or "auto". Value "auto" uses |:vertical|
--- if only 'mini.git' buffers are shown in the tabpage and |:tab| otherwise.
--- Default: "auto".
MiniGit.config = {
  -- General CLI execution
  job = {
    -- Path to Git executable
    git_executable = 'git',

    -- Timeout (in ms) for each job before force quit
    timeout = 30000,
  },

  -- Options for `:Git` command
  command = {
    -- Default split direction
    split = 'auto',
  },
}
--minidoc_afterlines_end

--- Show Git related data at cursor
---
--- - If inside |mini.deps| confirmation buffer, show in split relevant commit data.
--- - If there is a commit-like |<cword>|, show it in split.
--- - If possible, show diff source via |MiniGit.show_diff_source()|.
--- - If possible, show range history via |MiniGit.show_range_history()|.
--- - Otherwise throw an error.
---
---@param opts table|nil Options. Possible values:
---   - __git_split_field
---   - Fields appropriate for forwarding to other functions.
MiniGit.show_at_cursor = function(opts)
  -- Try showing commit data at cursor
  local commit, cwd
  if vim.bo.filetype == 'minideps-confirm' then
    commit, cwd = H.deps_pos_to_source()
  else
    local cword = vim.fn.expand('<cword>')
    local is_commit = string.find(cword, '^%x%x%x%x%x%x%x+$') ~= nil and string.lower(cword) == cword
    commit = is_commit and cword or nil
    cwd = is_commit and H.get_git_cwd() or nil
  end

  if commit ~= nil and cwd ~= nil then
    local split = H.normalize_split_opt((opts or {}).split or 'auto', 'opts.split')
    local args = { 'show', '--stat', '--patch', commit }
    local lines = H.git_cli_output(args, cwd)
    if #lines == 0 then return H.notify('Can not show commit ' .. commit .. ' in repo ' .. cwd, 'WARN') end
    H.show_in_split(split, lines, 'show', table.concat(args, ' '))
    vim.bo.filetype = 'git'
    return
  end

  -- Try showing diff source
  if H.diff_pos_to_source() ~= nil then return MiniGit.show_diff_source(opts) end

  -- Try showing range history if possible: either in Git repo (tracked or not;
  -- after resolving symlinks) or diff source output.
  local buf_id, buf_name = vim.api.nvim_get_current_buf(), vim.api.nvim_buf_get_name(0)
  local path = vim.uv.fs_realpath(buf_name)
  local path_dir = path == nil and '' or vim.fn.fnamemodify(path, ':h')

  local is_in_git = H.is_buf_enabled(buf_id) or #H.git_cli_output({ 'rev-parse', '--show-toplevel' }, path_dir) > 0
  local is_diff_source_output = H.parse_diff_source_buf_name(buf_name) ~= nil
  if is_in_git or is_diff_source_output then return MiniGit.show_range_history(opts) end

  H.notify('Nothing Git-related to show at cursor', 'WARN')
end

--- Show diff source
---
--- When buffer contains text formatted as unified patch (like after
--- `:Git log --patch`, `:Git diff`, or |MiniGit.show_range_history()|),
--- show state of the file at the particular state. Target commit/state, path,
--- and line number are deduced from cursor position.
---
--- Notes:
--- - Needs |current-directory| to be the Git root for relative paths to work.
--- - Needs cursor to be inside hunk lines or on "---" / "+++" lines with paths.
--- - Only basic forms of `:Git diff` output is supported: `:Git diff`,
---   `:Git diff --cached`, and `:Git diff <commit>`.
---
---@param opts table|nil Options. Possible values:
---   - __git_split_field
---   - <target> `(string)` - which file state to show. One of "before", "after",
---     "both" (both states in vertical split), "auto" (default). Value "auto"
---     shows "before" state if cursor line starts with "-", otherwise - "after".
MiniGit.show_diff_source = function(opts)
  opts = vim.tbl_deep_extend('force', { split = 'auto', target = 'auto' }, opts or {})
  local split = H.normalize_split_opt(opts.split, 'opts.split')
  local target = opts.target
  if not (target == 'auto' or target == 'before' or target == 'after' or target == 'both') then
    H.error('`opts.target` should be one of "auto", "before", "after", "both".')
  end

  local src = H.diff_pos_to_source()
  if src == nil then
    return H.notify('Could not find diff source. Ensure that cursor is inside a valid diff lines of git log.', 'WARN')
  end
  if target == 'auto' then target = src.init_prefix == '-' and 'before' or 'after' end

  local cwd = H.get_git_cwd()
  local show = function(commit, path, mods)
    local is_worktree, args, lines = commit == true, nil, nil
    if is_worktree then
      args, lines = { 'edit', vim.fn.fnameescape(path) }, vim.fn.readfile(path)
    else
      args = { 'show', commit .. ':' .. path }
      lines = H.git_cli_output(args, cwd)
    end
    if #lines == 0 and not is_worktree then
      return H.notify('Can not show ' .. path .. ' at commit ' .. commit, 'WARN')
    end
    H.show_in_split(mods, lines, 'show', table.concat(args, ' '))
  end

  local has_before_shown = false
  if target ~= 'after' then
    if src.path_before == nil then
      H.notify('No "before" as file was created', 'WARN')
    else
      show(src.commit_before, src.path_before, split)
      vim.api.nvim_win_set_cursor(0, { src.lnum_before, 0 })
      has_before_shown = true
    end
  end

  if target ~= 'before' then
    if src.path_after == nil then
      H.notify('No "after" as file was deleted', 'WARN')
    else
      local mods_after = has_before_shown and 'belowright vertical' or split
      show(src.commit_after, src.path_after, mods_after)
      vim.api.nvim_win_set_cursor(0, { src.lnum_after, 0 })
    end
  end
end

--- Show range history
---
--- Compute and show in split data about how particular line range in current
--- buffer evolved through Git history. Essentially a `git log` with `-L` flag.
---
--- Notes:
--- - Works well with |MiniGit.diff_foldexpr()|.
--- - Does not work if there are uncommited changes, as there is no easy way to
---   compute effective range line numbers.
---
---@param opts table|nil Options. Possible fields:
---   - <line_start> `(number)` - range start line.
---   - <line_end> `(number)` - range end line.
---     If both <line_start> and <line_end> are not supplied, they default to
---     current line in Normal mode and visual selection in Visual mode.
---   - <log_args> `(table)` - array of options to append to `git log` call.
---   - __git_split_field
MiniGit.show_range_history = function(opts)
  local default_opts = { line_start = nil, line_end = nil, log_args = nil, split = 'auto' }
  opts = vim.tbl_deep_extend('force', default_opts, opts or {})
  local line_start, line_end = H.normalize_range_lines(opts.line_start, opts.line_end)
  local log_args = opts.log_args or {}
  if not H.islist(log_args) then H.error('`opts.log_args` should be an array.') end
  local split = H.normalize_split_opt(opts.split, 'opts.split')

  -- Construct `:Git log` command that works both with regular files and
  -- buffers from `show_diff_source()`
  local buf_name, cwd = vim.api.nvim_buf_get_name(0), H.get_git_cwd()
  local commit, rel_path = H.parse_diff_source_buf_name(buf_name)
  if commit == nil then
    commit = 'HEAD'
    local cwd_pattern = '^' .. vim.pesc(cwd:gsub('\\', '/')) .. '/'
    rel_path = H.get_buf_realpath(0):gsub('\\', '/'):gsub(cwd_pattern, '')
  end

  -- Ensure no uncommitted changes as they might result into improper `-L` arg
  local diff = commit == 'HEAD' and H.git_cli_output({ 'diff', '-U0', 'HEAD', '--', rel_path }, cwd) or {}
  if #diff ~= 0 then
    return H.notify('Current file has uncommitted lines. Commit or stash before exploring history.', 'WARN')
  end

  -- Show log in split
  local range_flag = string.format('-L%d,%d:%s', line_start, line_end, rel_path)
  local args = { 'log', range_flag, commit, unpack(log_args) }
  local history = H.git_cli_output(args, cwd)
  if #history == 0 then return H.notify('Could not get range history', 'WARN') end
  H.show_in_split(split, history, 'log', table.concat(args, ' '))
end

--- Fold expression for Git logs
---
--- Folds contents of hunks, file patches, and log entries in unified diff.
--- Useful for filetypes "diff" (like after `:Git diff`) and "git" (like after
--- `:Git log --patch` or `:Git show` for commit).
--- Works well with |MiniGit.show_range_history()|.
---
--- General idea of folding levels (use |zr| and |zm| to adjust interactively):
--- - At level 0 there is one line per whole patch or log entry.
--- - At level 1 there is one line per patched file.
--- - At level 2 there is one line per hunk.
--- - At level 3 there is no folds.
---
--- For automated setup, set the following for "git" and "diff" filetypes (either
--- inside |FileType| autocommand or |ftplugin|): >vim
---
---   setlocal foldmethod=expr foldexpr=v:lua.MiniGit.diff_foldexpr()
--- <
---@param lnum number|nil Line number for which fold level is computed.
---   Default: |v:lnum|.
---
---@return number|string Line fold level. See |fold-expr|.
MiniGit.diff_foldexpr = function(lnum)
  lnum = lnum or vim.v.lnum
  if H.is_log_entry_header(lnum + 1) or H.is_log_entry_header(lnum) then return 0 end
  if H.is_file_entry_header(lnum) then return 1 end
  if H.is_hunk_header(lnum) then return 2 end
  if H.is_hunk_header(lnum - 1) then return 3 end
  return '='
end

--- Enable Git tracking in a file buffer
---
--- Tracking is done by reacting to changes in file content or file's repository
--- in the form of keeping buffer data up to date. The data can be used via:
--- - |MiniGit.get_buf_data()|. See its help for a list of actually tracked data.
--- - `vim.b.minigit_summary` (table) and `vim.b.minigit_summary_string` (string)
---   buffer-local variables which are more suitable for statusline.
---   `vim.b.minigit_summary_string` contains information about HEAD, file status,
---   and in progress action (see |MiniGit.get_buf_data()| for more details).
---   See |MiniGit-examples| for how it can be tweaked and used in statusline.
---
--- Note: this function is called automatically for all new normal buffers.
--- Use it explicitly if buffer was disabled.
---
--- `User` event `MiniGitUpdated` is triggered whenever tracking data is updated.
--- Note that not all data listed in |MiniGit.get_buf_data()| can be present (yet)
--- at the point of event being triggered.
---
---@param buf_id __git_buf_id
MiniGit.enable = function(buf_id)
  buf_id = H.validate_buf_id(buf_id)

  -- Don't enable more than once
  if H.is_buf_enabled(buf_id) or H.is_disabled(buf_id) or not H.has_git then return end

  -- Enable only in buffers which *can* be part of Git repo
  local path = H.get_buf_realpath(buf_id)
  if path == '' or vim.fn.filereadable(path) ~= 1 then return end

  -- Start tracking
  H.cache[buf_id] = {}
  H.setup_buf_behavior(buf_id)
  H.start_tracking(buf_id, path)
end

--- Disable Git tracking in buffer
---
---@param buf_id __git_buf_id
MiniGit.disable = function(buf_id)
  buf_id = H.validate_buf_id(buf_id)

  local buf_cache = H.cache[buf_id]
  if buf_cache == nil then return end
  H.cache[buf_id] = nil

  -- Cleanup
  pcall(vim.api.nvim_del_augroup_by_id, buf_cache.augroup)
  vim.b[buf_id].minigit_summary, vim.b[buf_id].minigit_summary_string = nil, nil

  -- - Unregister buffer from repo watching with possibly more cleanup
  local repo = buf_cache.repo
  if H.repos[repo] == nil then return end
  H.repos[repo].buffers[buf_id] = nil
  if vim.tbl_count(H.repos[repo].buffers) == 0 then
    H.teardown_repo_watch(repo)
    H.repos[repo] = nil
  end
end

--- Toggle Git tracking in buffer
---
--- Enable if disabled, disable if enabled.
---
---@param buf_id __git_buf_id
MiniGit.toggle = function(buf_id)
  buf_id = H.validate_buf_id(buf_id)
  if H.is_buf_enabled(buf_id) then return MiniGit.disable(buf_id) end
  return MiniGit.enable(buf_id)
end

--- Get buffer data
---
---@param buf_id __git_buf_id
---
---@return table|nil Table with buffer Git data or `nil` if buffer is not enabled.
---   If the file is not part of Git repo, table will be empty.
---   Table has the following fields:
---   - <repo> `(string)` - full path to '.git' directory.
---   - <root> `(string)` - full path to worktree root.
---   - <head> `(string)` - full commit of current HEAD.
---   - <head_name> `(string)` - short name of current HEAD (like "master").
---     For detached HEAD it is "HEAD".
---   - <status> `(string)` - two character file status as returned by `git status`.
---   - <in_progress> `(string)` - name of action(s) currently in progress
---     (bisect, merge, etc.). Can be a combination of those separated by ",".
MiniGit.get_buf_data = function(buf_id)
  buf_id = H.validate_buf_id(buf_id)
  local buf_cache = H.cache[buf_id]
  if buf_cache == nil then return nil end
  --stylua: ignore
  return {
    repo   = buf_cache.repo,   root        = buf_cache.root,
    head   = buf_cache.head,   head_name   = buf_cache.head_name,
    status = buf_cache.status, in_progress = buf_cache.in_progress,
  }
end

-- Helper data ================================================================
-- Module default config
H.default_config = MiniGit.config

-- Cache per enabled buffer. Values are tables with fields:
-- - <augroup> - identifier of augroup defining buffer behavior.
-- - <repo> - path to buffer's repo ('.git' directory).
-- - <root> - path to worktree root.
-- - <head> - full commit of `HEAD`.
-- - <head_name> - short name of `HEAD` (`'HEAD'` for detached head).
-- - <status> - current file status.
-- - <in_progress> - string name of action in progress (bisect, merge, etc.)
H.cache = {}

-- Cache per repo (git directory) path. Values are tables with fields:
-- - <fs_event> - `vim.uv` event for watching repo dir.
-- - <timer> - timer to debounce repo changes.
-- - <buffers> - map of buffers which should are part of repo.
H.repos = {}

-- Termporary file used as config for `GIT_EDITOR`
H.git_editor_config = nil

-- Data about supported Git subcommands. Initialized lazily. Fields:
-- - <supported> - array of supported one word commands.
-- - <complete> - array of commands to complete directly after `:Git`.
-- - <info> - map with fields as commands which show something to user.
-- - <options> - map of cached options per command; initialized lazily.
-- - <alias> - map of alias command name to command it implements.
H.git_subcommands = nil

-- Whether to temporarily skip some checks (like when inside `GIT_EDITOR`)
H.skip_timeout = false
H.skip_sync = false

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  H.check_type('job', config.job, 'table')
  H.check_type('command', config.command, 'table')

  H.check_type('job.git_executable', config.job.git_executable, 'string')
  H.check_type('job.timeout', config.job.timeout, 'number')
  if not pcall(H.normalize_split_opt, config.command.split) then
    H.error('`command.split` should be one of "auto", "horizontal", "vertical", "tab"')
  end

  return config
end

H.apply_config = function(config) MiniGit.config = config end

H.create_autocommands = function()
  local gr = vim.api.nvim_create_augroup('MiniGit', {})

  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = gr, pattern = pattern, callback = callback, desc = desc })
  end

  -- NOTE: Try auto enabling buffer on every `BufEnter` to not have `:edit`
  -- disabling buffer, as it calls `on_detach()` from buffer watcher
  au('BufEnter', '*', H.auto_enable, 'Enable Git tracking')
end

H.is_disabled = function(buf_id) return vim.g.minigit_disable == true or vim.b[buf_id or 0].minigit_disable == true end

H.create_user_commands = function()
  local opts = { bang = true, nargs = '+', complete = H.command_complete, desc = 'Execute Git command' }
  vim.api.nvim_create_user_command('Git', H.command_impl, opts)
end

-- Autocommands ---------------------------------------------------------------
H.auto_enable = vim.schedule_wrap(function(data)
  local buf = data.buf
  if not (vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == '' and vim.bo[buf].buflisted) then return end
  MiniGit.enable(data.buf)
end)

-- Command --------------------------------------------------------------------
H.command_impl = function(input)
  if not H.has_git then
    return H.notify('There is no `' .. MiniGit.config.job.git_executable .. '` executable', 'ERROR')
  end

  H.ensure_git_subcommands()

  -- Define Git editor to be used if needed. The way it works is: execute
  -- command, wait for it to exit, use content of edited file. So to properly
  -- wait for user to finish edit, start fresh headless process which opens
  -- file in current session/process. It exits after the user is done editing
  -- (deletes the buffer or closes the window).
  H.ensure_git_editor(input.mods)
  -- NOTE: use `vim.v.progpath` to have same runtime
  local editor = H.cli_escape(vim.v.progpath) .. ' --clean --headless -u ' .. H.cli_escape(H.git_editor_config)

  -- Setup custom environment variables for better reproducibility
  local env_vars = {}
  -- - Use Git related variables to use instance for editing
  env_vars.GIT_EDITOR, env_vars.GIT_SEQUENCE_EDITOR, env_vars.GIT_PAGER = editor, editor, ''
  -- - Make output as much machine readable as possible
  env_vars.NO_COLOR, env_vars.TERM = 1, 'dumb'
  local env = H.make_spawn_env(env_vars)

  -- Setup spawn arguments
  local args = vim.tbl_map(H.expandcmd, input.fargs)
  local command = { MiniGit.config.job.git_executable, unpack(args) }
  local cwd = H.get_git_cwd()

  local cmd_data = { cmd_input = input, git_command = command, cwd = cwd }
  local is_done_track = { done = false }
  local on_done = H.command_make_on_done(cmd_data, is_done_track)

  H.cli_run(command, cwd, on_done, { env = env })

  -- If needed, synchronously wait for job to finish
  local sync_check = function() return H.skip_sync or is_done_track.done end
  if not input.bang then vim.wait(MiniGit.config.job.timeout + 10, sync_check, 1) end
end

--stylua: ignore
H.ensure_git_subcommands = function()
  if H.git_subcommands ~= nil then return end
  local git_subcommands = {}

  -- Compute all supported commands. All 'list-' are taken from Git source
  -- 'command-list.txt' file. Be so granular and not just `main,nohelpers` in
  -- order to not include purely man-page worthy items (like "remote-ext").
  local lists_all = {
    'list-mainporcelain',
    'list-ancillarymanipulators', 'list-ancillaryinterrogators',
    'list-foreignscminterface',
    'list-plumbingmanipulators', 'list-plumbinginterrogators',
    'others', 'alias',
  }
  local supported = H.git_cli_output({ '--list-cmds=' .. table.concat(lists_all, ',') })
  if #supported == 0 then
    -- Fall back only on basics if previous one failed for some reason
    supported = {
      'add', 'bisect', 'branch', 'clone', 'commit', 'diff', 'fetch', 'grep', 'init', 'log', 'merge',
      'mv', 'pull', 'push', 'rebase', 'reset', 'restore', 'rm', 'show', 'status', 'switch', 'tag',
    }
  end
  table.sort(supported)
  git_subcommands.supported = supported

  -- Compute complete list for commands by enhancing with two word commands.
  -- Keep those lists manual as there is no good way to compute lazily.
  local complete = vim.deepcopy(supported)
  local add_twoword = function(prefix, suffixes)
    if not vim.tbl_contains(supported, prefix) then return end
    for _, suf in ipairs(suffixes) do table.insert(complete, prefix .. ' ' .. suf) end
  end
  add_twoword('bundle',           { 'create', 'list-heads', 'unbundle', 'verify' })
  add_twoword('bisect',           { 'bad', 'good', 'log', 'replay', 'reset', 'run', 'skip', 'start', 'terms', 'view', 'visualize' })
  add_twoword('commit-graph',     { 'verify', 'write' })
  add_twoword('maintenance',      { 'run', 'start', 'stop', 'register', 'unregister' })
  add_twoword('multi-pack-index', { 'expire', 'repack', 'verify', 'write' })
  add_twoword('notes',            { 'add', 'append', 'copy', 'edit', 'get-ref', 'list', 'merge', 'prune', 'remove', 'show' })
  add_twoword('p4',               { 'clone', 'rebase', 'submit', 'sync' })
  add_twoword('reflog',           { 'delete', 'exists', 'expire', 'show' })
  add_twoword('remote',           { 'add', 'get-url', 'prune', 'remove', 'rename', 'rm', 'set-branches', 'set-head', 'set-url', 'show', 'update' })
  add_twoword('rerere',           { 'clear', 'diff', 'forget', 'gc', 'remaining', 'status' })
  add_twoword('sparse-checkout',  { 'add', 'check-rules', 'disable', 'init', 'list', 'reapply', 'set' })
  add_twoword('stash',            { 'apply', 'branch', 'clear', 'create', 'drop', 'list', 'pop', 'save', 'show', 'store' })
  add_twoword('submodule',        { 'absorbgitdirs', 'add', 'deinit', 'foreach', 'init', 'set-branch', 'set-url', 'status', 'summary', 'sync', 'update' })
  add_twoword('subtree',          { 'add', 'merge', 'pull', 'push', 'split' })
  add_twoword('worktree',         { 'add', 'list', 'lock', 'move', 'prune', 'remove', 'repair', 'unlock' })
  git_subcommands.complete = complete

  -- Compute commands which are meant to show information. These will show CLI
  -- output in separate buffer opposed to `vim.notify`.
  local info_args = { '--list-cmds=list-info,list-ancillaryinterrogators,list-plumbinginterrogators' }
  local info_commands = H.git_cli_output(info_args)
  if #info_commands == 0 then info_commands = { 'bisect', 'diff', 'grep', 'log', 'show', 'status' } end
  local info = {}
  for _, cmd in ipairs(info_commands) do
    info[cmd] = true
  end
  git_subcommands.info = info

  -- Compute commands which aliases rely on
  local alias_data = H.git_cli_output({ 'config', '--get-regexp', 'alias.*' })
  local alias = {}
  for _, l in ipairs(alias_data) do
    -- Assume simple alias of the form `alias.xxx subcommand ...`
    local alias_cmd, cmd = string.match(l, '^alias%.(%S+) (%S+)')
    if vim.tbl_contains(supported, cmd) then alias[alias_cmd] = cmd end
  end
  git_subcommands.alias = alias

  -- Initialize cache for command options. Initialize with `false` so that
  -- actual values are computed lazily when needed for a command.
  local options = { git = false }
  for _, command in ipairs(supported) do
    options[command] = false
  end
  git_subcommands.options = options

  -- Cache results
  H.git_subcommands = git_subcommands
end

H.ensure_git_editor = function(mods)
  if H.git_editor_config == nil or not vim.fn.filereadable(H.git_editor_config) == 0 then
    H.git_editor_config = vim.fn.tempname()
  end

  -- Create a private function responsible for editing Git file
  MiniGit._edit = function(path, servername)
    -- Define editor state before and after editing path
    H.skip_timeout, H.skip_sync = true, true
    local cleanup = function()
      local _, channel = pcall(vim.fn.sockconnect, 'pipe', servername, { rpc = true })
      pcall(vim.rpcnotify, channel, 'nvim_exec2', 'quitall!', {})
      H.skip_timeout, H.skip_sync = false, false
    end

    -- Start file edit with proper modifiers in a special window
    mods = H.ensure_mods_is_split(mods)
    vim.cmd(mods .. ' split ' .. vim.fn.fnameescape(path))
    H.define_minigit_window(cleanup)
  end

  -- Start editing file from first argument (as how `GIT_EDITOR` works) in
  -- current instance and don't close until explicitly closed later from this
  -- instance as set up in `MiniGit._edit()`
  local lines = {
    'lua << EOF',
    string.format('local channel = vim.fn.sockconnect("pipe", %s, { rpc = true })', vim.inspect(vim.v.servername)),
    'local ins = vim.inspect',
    'local lua_cmd = string.format("MiniGit._edit(%s, %s)", ins(vim.fn.argv(0)), ins(vim.v.servername))',
    'vim.rpcrequest(channel, "nvim_exec_lua", lua_cmd, {})',
    'EOF',
  }
  vim.fn.writefile(lines, H.git_editor_config)
end

H.get_git_cwd = function()
  local buf_cache = H.cache[vim.api.nvim_get_current_buf()] or {}
  return buf_cache.root or vim.fn.getcwd()
end

H.command_make_on_done = function(cmd_data, is_done_track)
  return vim.schedule_wrap(function(code, out, err)
    -- Register that command is done executing (to enable sync execution)
    is_done_track.done = true

    -- Trigger "done" event
    cmd_data.git_subcommand = H.command_parse_subcommand(cmd_data.git_command)
    cmd_data.exit_code, cmd_data.stdout, cmd_data.stderr = code, out, err
    H.trigger_event('MiniGitCommandDone', cmd_data)

    -- Show stderr and stdout
    if H.cli_err_notify(code, out, err) then return end
    H.command_show_stdout(cmd_data)

    -- Ensure that all buffers are up to date (avoids "The file has been
    -- changed since reading it" warning)
    vim.tbl_map(function(buf_id) vim.cmd('checktime ' .. buf_id) end, vim.api.nvim_list_bufs())
  end)
end

H.command_show_stdout = function(cmd_data)
  local stdout, mods, subcommand = cmd_data.stdout, cmd_data.cmd_input.mods, cmd_data.git_subcommand
  if stdout == '' or (mods:find('silent') ~= nil and mods:find('unsilent') == nil) then return end

  -- Show in split if explicitly forced or the command shows info.
  -- Use `vim.notify` otherwise.
  local should_split = H.mods_is_split(mods) or H.git_subcommands.info[subcommand]
  if not should_split then return H.notify(stdout, 'INFO') end

  local lines = vim.split(stdout, '\n')
  local name = table.concat(cmd_data.git_command, ' ')
  cmd_data.win_source, cmd_data.win_stdout = H.show_in_split(mods, lines, subcommand, name)

  -- Trigger "split" event
  H.trigger_event('MiniGitCommandSplit', cmd_data)
end

H.command_parse_subcommand = function(command)
  local res
  for _, cmd in ipairs(command) do
    if res == nil and vim.tbl_contains(H.git_subcommands.supported, cmd) then res = cmd end
  end
  return H.git_subcommands.alias[res] or res
end

H.command_complete = function(_, line, col)
  -- Compute completion base manually to be "at cursor" and respect `\ `
  local base = H.get_complete_base(line:sub(1, col))
  local candidates, compl_type = H.command_get_complete_candidates(line, col, base)
  -- Allow several "//" at the end for path completion for easier "chaining"
  if compl_type == 'path' then base = base:gsub('/+$', '/') end
  return vim.tbl_filter(function(x) return vim.startswith(x, base) end, candidates)
end

H.get_complete_base = function(line)
  local from, _, res = line:find('(%S*)$')
  while from ~= nil do
    local cur_from, _, cur_res = line:sub(1, from - 1):find('(%S*\\ )$')
    if cur_res ~= nil then res = cur_res .. res end
    from = cur_from
  end
  return (res:gsub([[\ ]], ' '))
end

H.command_get_complete_candidates = function(line, col, base)
  H.ensure_git_subcommands()

  -- Determine current Git subcommand as the earliest present supported one
  local subcmd, subcmd_end = nil, math.huge
  for _, cmd in pairs(H.git_subcommands.supported) do
    local _, ind = line:find(' ' .. cmd .. ' ', 1, true)
    if ind ~= nil and ind < subcmd_end then
      subcmd, subcmd_end = cmd, ind
    end
  end

  subcmd = subcmd or 'git'
  local cwd = H.get_git_cwd()

  -- Determine command candidates:
  -- - Commannd options if complete base starts with "-".
  -- - Paths if after explicit "--".
  -- - Git commands if there is none fully formed yet or cursor is at the end
  --   of the command (to also suggest subcommands).
  -- - Command targets specific for each command (if present).
  if vim.startswith(base, '-') then return H.command_complete_option(subcmd) end
  if line:sub(1, col):find(' -- ') ~= nil then return H.command_complete_path(cwd, base) end
  if subcmd_end == math.huge or (subcmd_end - 1) == col then return H.git_subcommands.complete, 'subcommand' end

  subcmd = H.git_subcommands.alias[subcmd] or subcmd
  local complete_targets = H.command_complete_subcommand_targets[subcmd]
  if complete_targets == nil then return {}, nil end
  return complete_targets(cwd, base, line)
end

H.command_complete_option = function(command)
  local cached_candidates = H.git_subcommands.options[command]
  if cached_candidates == nil then return {} end
  if type(cached_candidates) == 'table' then return cached_candidates end

  -- Use alias's command to compute the options but store cache for alias
  local orig_command = command
  command = H.git_subcommands.alias[command] or command

  -- Find command's flag options by parsing its help page. Needs a bit
  -- heuristic approach and ensuring proper `git help` output (as it is done
  -- through `man`), but seems to work good enough.
  -- Alternative is to call command with `--git-completion-helper-all` flag (as
  -- is done in bash and vim-fugitive completion). This has both pros and cons:
  -- - Pros: faster; more targeted suggestions (like for two word subcommands);
  --         presumably more reliable.
  -- - Cons: works on smaller number of commands (for example, `rev-parse` or
  --         pure `git` do not work); does not provide single dash suggestions;
  --         does not work when not inside Git repo; needs recognizing two word
  --         commands before asking for completion.
  local env = H.make_spawn_env({ MANPAGER = 'cat', NO_COLOR = 1, PAGER = 'cat' })
  local lines = H.git_cli_output({ 'help', '--man', command }, nil, env)
  -- - Exit early before caching to try again later
  if #lines == 0 then return {} end
  -- - On some systems (like Mac), output still might contain formatting
  --   sequences, like "a\ba" and "_\ba" meaning bold and italic.
  --   See https://github.com/nvim-mini/mini.nvim/issues/918
  lines = vim.tbl_map(function(l) return l:gsub('.\b', '') end, lines)

  -- Construct non-duplicating candidates by parsing lines of help page
  local candidates_map = {}

  -- Options are assumed to be listed inside "OPTIONS" or "XXX OPTIONS" (like
  -- "MODE OPTIONS" of `git rebase`) section on dedicated lines. Whether a line
  -- contains only options is determined heuristically: it is assumed to start
  -- exactly with "       -" indicating proper indent for subsection start.
  -- Known not parsable options:
  -- - `git reset <mode>` (--soft, --hard, etc.): not listed in "OPTIONS".
  -- - All -<number> options, as they are not really completeable.
  local is_in_options_section = false
  for _, l in ipairs(lines) do
    if is_in_options_section and l:find('^%u[%u ]+$') ~= nil then is_in_options_section = false end
    if not is_in_options_section and l:find('^%u?[%u ]*OPTIONS$') ~= nil then is_in_options_section = true end
    if is_in_options_section and l:find('^       %-') ~= nil then H.parse_options(candidates_map, l) end
  end

  -- Finalize candidates. Should not contain "almost duplicates".
  -- Should also be sorted by relevance: short flags before regular flags.
  -- Inside groups sort alphabetically ignoring case.
  candidates_map['--'] = nil
  for cmd, _ in pairs(candidates_map) do
    -- There can be two explicitly documented options "--xxx" and "--xxx=".
    -- Use only one of them (without "=").
    if cmd:sub(-1, -1) == '=' and candidates_map[cmd:sub(1, -2)] ~= nil then candidates_map[cmd] = nil end
  end

  local res = vim.tbl_keys(candidates_map)
  table.sort(res, function(a, b)
    local a2, b2 = a:sub(2, 2) == '-', b:sub(2, 2) == '-'
    if a2 and not b2 then return false end
    if not a2 and b2 then return true end
    local a_low, b_low = a:lower(), b:lower()
    return a_low < b_low or (a_low == b_low and a < b)
  end)

  -- Cache and return
  H.git_subcommands.options[orig_command] = res
  return res, 'option'
end

H.parse_options = function(map, line)
  -- Options are standalone words starting as "-xxx" or "--xxx"
  -- Include possible "=" at the end indicating mandatory value
  line:gsub('%s(%-[-%w][-%w]*=?)', function(match) map[match] = true end)

  -- Make exceptions for commonly documented "--[no-]xxx" two options
  line:gsub('%s%-%-%[no%-%]([-%w]+=?)', function(match)
    map['--' .. match], map['--no-' .. match] = true, true
  end)
end

H.command_complete_path = function(cwd, base)
  -- Treat base only as path relative to the command's cwd
  cwd = cwd:gsub('/+$', '') .. '/'
  local cwd_len = cwd:len()

  -- List elements from (absolute) target directory
  local target_dir = vim.fn.fnamemodify(base, ':h')
  target_dir = (cwd .. target_dir:gsub('^%.$', '')):gsub('/+$', '') .. '/'
  local ok, fs_entries = pcall(vim.fn.readdir, target_dir)
  if not ok then return {} end

  -- List directories and files separately
  local dirs, files = {}, {}
  for _, entry in ipairs(fs_entries) do
    local entry_abs = target_dir .. entry
    local arr = vim.fn.isdirectory(entry_abs) == 1 and dirs or files
    table.insert(arr, entry_abs)
  end
  dirs = vim.tbl_map(function(x) return x .. '/' end, dirs)

  -- List ordered directories first followed by ordered files
  local order_ignore_case = function(a, b) return a:lower() < b:lower() end
  table.sort(dirs, order_ignore_case)
  table.sort(files, order_ignore_case)

  -- Return candidates relative to command's cwd
  local all = dirs
  vim.list_extend(all, files)
  local res = vim.tbl_map(function(x) return x:sub(cwd_len + 1) end, all)
  return res, 'path'
end

H.command_complete_pullpush = function(cwd, _, line)
  -- Suggest remotes at `Git push |` and `Git push or|`, otherwise - references
  -- Ignore options when deciding which suggestion to compute
  local _, n_words = line:gsub(' (%-%S+)', ''):gsub('%S+ ', '')
  if n_words <= 2 then return H.git_cli_output({ 'remote' }, cwd), 'remote' end
  return H.git_cli_output({ 'rev-parse', '--symbolic', '--branches', '--tags' }, cwd), 'ref'
end

H.make_git_cli_complete = function(args, complete_type)
  return function(cwd, _) return H.git_cli_output(args, cwd), complete_type end
end

-- Cover at least all subcommands listed in `git help`
--stylua: ignore
H.command_complete_subcommand_targets = {
  -- clone - no targets
  -- init  - no targets

  -- Worktree
  add     = H.command_complete_path,
  mv      = H.command_complete_path,
  restore = H.command_complete_path,
  rm      = H.command_complete_path,

  -- Examine history
  -- bisect - no targets
  diff = H.command_complete_path,
  grep = H.command_complete_path,
  log  = H.make_git_cli_complete({ 'rev-parse', '--symbolic', '--branches', '--tags' }, 'ref'),
  show = H.make_git_cli_complete({ 'rev-parse', '--symbolic', '--branches', '--tags' }, 'ref'),
  -- status - no targets

  -- Modify history
  branch = H.make_git_cli_complete({ 'rev-parse', '--symbolic', '--branches' },           'branch'),
  commit = H.command_complete_path,
  merge  = H.make_git_cli_complete({ 'rev-parse', '--symbolic', '--branches' },           'branch'),
  rebase = H.make_git_cli_complete({ 'rev-parse', '--symbolic', '--branches' },           'branch'),
  reset  = H.make_git_cli_complete({ 'rev-parse', '--symbolic', '--branches', '--tags' }, 'ref'),
  switch = H.make_git_cli_complete({ 'rev-parse', '--symbolic', '--branches' },           'branch'),
  tag    = H.make_git_cli_complete({ 'rev-parse', '--symbolic', '--tags' },               'tag'),

  -- Collaborate
  fetch = H.make_git_cli_complete({ 'remote' }, 'remote'),
  push = H.command_complete_pullpush,
  pull = H.command_complete_pullpush,

  -- Miscellaneous
  checkout = H.make_git_cli_complete({ 'rev-parse', '--symbolic', '--branches', '--tags', '--remotes' }, 'checkout'),
  config = H.make_git_cli_complete({ 'help', '--config-for-completion' }, 'config'),
  help = function()
    local res = { 'git', 'everyday' }
    vim.list_extend(res, H.git_subcommands.supported)
    return res, 'help'
  end,
}

H.ensure_mods_is_split = function(mods)
  if not H.mods_is_split(mods) then
    local split_val = H.normalize_split_opt(MiniGit.config.command.split, '`config.command.split`')
    mods = split_val .. ' ' .. mods
  end
  return mods
end

-- NOTE: `mods` is already expanded, so this also covers abbreviated mods
H.mods_is_split = function(mods) return mods:find('vertical') or mods:find('horizontal') or mods:find('tab') end

-- Show stdout ----------------------------------------------------------------
H.show_in_split = function(mods, lines, subcmd, name)
  -- Create a target window split
  mods = H.ensure_mods_is_split(mods)
  local win_source = vim.api.nvim_get_current_win()
  vim.cmd(mods .. ' split')
  local win_stdout = vim.api.nvim_get_current_win()

  -- Prepare buffer
  local buf_id = vim.api.nvim_create_buf(false, true)
  H.set_buf_name(buf_id, name)
  vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)

  vim.api.nvim_set_current_buf(buf_id)
  H.define_minigit_window()

  -- NOTE: set filetype when buffer is in window to allow setting window-local
  -- options in autocommands for `FileType` events
  local filetype
  if subcmd == 'diff' then filetype = 'diff' end
  if subcmd == 'log' or subcmd == 'blame' then filetype = 'git' end
  if subcmd == 'show' then
    -- Try detecting 'git' filetype by content first, as filetype detection can
    -- rely on the buffer name (i.e. command) having proper extension. It isn't
    -- good for cases like `:Git show HEAD file.lua` (which should be 'git').
    local l = lines[1]
    local is_diff = l:find(string.rep('%x', 40)) or l:find('ref:')
    filetype = is_diff and 'git' or vim.filetype.match({ buf = buf_id })
  end

  local has_filetype = not (filetype == nil or filetype == '')
  if has_filetype then vim.bo[buf_id].filetype = filetype end

  -- Completely unfold for no filetype output (like `:Git help`)
  if not has_filetype then vim.wo[win_stdout].foldlevel = 999 end

  return win_source, win_stdout
end

H.define_minigit_window = function(cleanup)
  local buf_id, win_id = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
  vim.bo.swapfile, vim.bo.buflisted = false, false

  -- Define action to finish editing Git related file
  local finish_au_id
  local finish = function(data)
    local should_close = data.buf == buf_id or (data.event == 'WinClosed' and tonumber(data.match) == win_id)
    if not should_close then return end

    pcall(vim.api.nvim_del_autocmd, finish_au_id)
    pcall(vim.api.nvim_win_close, win_id, true)
    vim.schedule(function() pcall(vim.api.nvim_buf_delete, buf_id, { force = true }) end)

    if vim.is_callable(cleanup) then vim.schedule(cleanup) end
  end
  -- - Use `nested` to allow other events (`WinEnter` for 'mini.statusline')
  local events = { 'WinClosed', 'BufDelete', 'BufWipeout', 'VimLeave' }
  local opts = { nested = true, callback = finish, desc = 'Cleanup window and buffer' }
  finish_au_id = vim.api.nvim_create_autocmd(events, opts)
end

H.git_cli_output = function(args, cwd, env)
  if cwd ~= nil and (vim.fn.isdirectory(cwd) ~= 1 or cwd == '') then return {} end
  local command = { MiniGit.config.job.git_executable, '--no-pager', unpack(args) }
  local res = H.cli_run(command, cwd, nil, { env = env }).out
  if res == '' then return {} end
  return vim.split(res, '\n')
end

-- Validators -----------------------------------------------------------------
H.validate_buf_id = function(x)
  if x == nil or x == 0 then return vim.api.nvim_get_current_buf() end
  if not (type(x) == 'number' and vim.api.nvim_buf_is_valid(x)) then
    H.error('`buf_id` should be `nil` or valid buffer id.')
  end
  return x
end

H.normalize_split_opt = function(x, x_name)
  if x == 'auto' then
    -- Show in same tabpage if only minigit buffers visible. Otherwise in new.
    for _, win_id in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local win_buf_id = vim.api.nvim_win_get_buf(win_id)
      local win_buf_name = vim.api.nvim_buf_get_name(win_buf_id)
      local is_minigit_win = win_buf_name:find('^minigit://%d+/') ~= nil
      local is_normal_win = vim.api.nvim_win_get_config(win_id).relative == ''
      if not is_minigit_win and is_normal_win then return 'tab' end
    end
    return 'vertical'
  end
  if x == 'horizontal' or x == 'vertical' or x == 'tab' then return x end
  H.error('`' .. x_name .. '` should be one of "auto", "horizontal", "vertical", "tab"')
end

H.normalize_range_lines = function(line_start, line_end)
  if line_start == nil and line_end == nil then
    line_start = vim.fn.line('.')
    local is_visual = vim.tbl_contains({ 'v', 'V', '\22' }, vim.fn.mode())
    line_end = is_visual and vim.fn.line('v') or vim.fn.line('.')
    line_start, line_end = math.min(line_start, line_end), math.max(line_start, line_end)
  end

  if not (type(line_start) == 'number' and type(line_end) == 'number' and line_start <= line_end) then
    H.error('`line_start` and `line_end` should be non-decreasing numbers.')
  end
  return line_start, line_end
end

-- Enabling -------------------------------------------------------------------
H.is_buf_enabled = function(buf_id) return H.cache[buf_id] ~= nil and vim.api.nvim_buf_is_valid(buf_id) end

H.setup_buf_behavior = function(buf_id)
  local augroup = vim.api.nvim_create_augroup('MiniGitBuffer' .. buf_id, { clear = true })
  H.cache[buf_id].augroup = augroup

  vim.api.nvim_buf_attach(buf_id, false, {
    -- Called when buffer content is changed outside of current session
    -- Needed as otherwise `on_detach()` is called without later auto enabling
    on_reload = function()
      local buf_cache = H.cache[buf_id]
      if buf_cache == nil or buf_cache.root == nil then return end
      -- Don't upate repo/root as it is tracked in 'BufFilePost' autocommand
      H.update_git_head(buf_cache.root, { buf_id })
      H.update_git_in_progress(buf_cache.repo, { buf_id })
      -- Don't upate status as it is tracked in file watcher
    end,

    -- Called when buffer is unloaded from memory (`:h nvim_buf_detach_event`),
    -- **including** `:edit` command. Together with auto enabling it makes
    -- `:edit` command serve as "restart".
    on_detach = function() MiniGit.disable(buf_id) end,
  })

  local reset_if_enabled = vim.schedule_wrap(function(data)
    if not H.is_buf_enabled(data.buf) then return end
    MiniGit.disable(data.buf)
    MiniGit.enable(data.buf)
  end)
  local bufrename_opts = { group = augroup, buffer = buf_id, callback = reset_if_enabled, desc = 'Reset on rename' }
  -- NOTE: `BufFilePost` does not look like a proper event, but it (yet) works
  vim.api.nvim_create_autocmd('BufFilePost', bufrename_opts)

  local buf_disable = function() MiniGit.disable(buf_id) end
  local bufdelete_opts = { group = augroup, buffer = buf_id, callback = buf_disable, desc = 'Disable on delete' }
  vim.api.nvim_create_autocmd('BufDelete', bufdelete_opts)
end

-- Tracking -------------------------------------------------------------------
H.start_tracking = function(buf_id, path)
  local command = H.git_cmd({ 'rev-parse', '--path-format=absolute', '--git-dir', '--show-toplevel' })

  -- If path is not in Git, disable buffer but make sure that it will not try
  -- to re-attach until buffer is properly disabled
  local on_not_in_git = function()
    if H.is_buf_enabled(buf_id) then MiniGit.disable(buf_id) end
    H.cache[buf_id] = {}
  end

  local on_done = vim.schedule_wrap(function(code, out, err)
    -- Watch git directory only if there was no error retrieving path to it
    if code ~= 0 then return on_not_in_git() end
    H.cli_err_notify(code, out, err)

    -- Update buf data
    local repo, root = string.match(out, '^(.-)\n(.*)$')
    if repo == nil or root == nil then return H.notify('No initial data for buffer ' .. buf_id, 'WARN') end
    H.update_buf_data(buf_id, { repo = repo, root = root })

    -- Set up repo watching to react to Git index changes
    H.setup_repo_watch(buf_id, repo)

    -- Set up worktree watching to react to file changes
    H.setup_path_watch(buf_id)

    -- Immediately update buffer tracking data
    H.update_git_head(root, { buf_id })
    H.update_git_in_progress(repo, { buf_id })
    H.update_git_status(root, { buf_id })
  end)

  H.cli_run(command, vim.fn.fnamemodify(path, ':h'), on_done)
end

H.setup_repo_watch = function(buf_id, repo)
  local repo_cache = H.repos[repo] or {}

  -- Ensure repo is watched
  local is_set_up = repo_cache.fs_event ~= nil and repo_cache.fs_event:is_active()
  if not is_set_up then
    H.teardown_repo_watch(repo)
    local fs_event, timer = vim.uv.new_fs_event(), vim.uv.new_timer()

    local on_change = vim.schedule_wrap(function() H.on_repo_change(repo) end)
    local watch = function(_, filename, _)
      -- Ignore temporary changes
      if vim.endswith(filename, 'lock') then return end

      -- Debounce to not overload during incremental staging (like in script)
      timer:stop()
      timer:start(50, 0, on_change)
    end
    -- Watch only '.git' dir (non-recursively), as this seems to be both enough
    -- and not supported by libuv (`recursive` flag does nothing,
    -- see https://github.com/libuv/libuv/issues/1778)
    fs_event:start(repo, {}, watch)

    repo_cache.fs_event, repo_cache.timer = fs_event, timer
    H.repos[repo] = repo_cache
  end

  -- Register buffer to be updated on repo change
  local repo_buffers = repo_cache.buffers or {}
  repo_buffers[buf_id] = true
  repo_cache.buffers = repo_buffers
end

H.teardown_repo_watch = function(repo)
  if H.repos[repo] == nil then return end
  pcall(vim.uv.fs_event_stop, H.repos[repo].fs_event)
  pcall(vim.uv.timer_stop, H.repos[repo].timer)
end

H.setup_path_watch = function(buf_id, repo)
  if not H.is_buf_enabled(buf_id) then return end

  local on_file_change = function(data) H.update_git_status(H.cache[buf_id].root, { buf_id }) end
  local opts =
    { desc = 'Update Git status', group = H.cache[buf_id].augroup, buffer = buf_id, callback = on_file_change }
  vim.api.nvim_create_autocmd({ 'BufWritePost', 'FileChangedShellPost' }, opts)
end

H.on_repo_change = function(repo)
  if H.repos[repo] == nil then return end

  -- Collect repo's worktrees with their buffers while doing cleanup
  local repo_bufs, root_bufs = H.repos[repo].buffers, {}
  for buf_id, _ in pairs(repo_bufs) do
    if H.is_buf_enabled(buf_id) then
      local root = H.cache[buf_id].root
      local bufs = root_bufs[root] or {}
      table.insert(bufs, buf_id)
      root_bufs[root] = bufs
    else
      repo_bufs[buf_id] = nil
      MiniGit.disable(buf_id)
    end
  end

  -- Update Git data
  H.update_git_in_progress(repo, vim.tbl_keys(repo_bufs))
  for root, bufs in pairs(root_bufs) do
    H.update_git_head(root, bufs)
    -- Status could have also changed as it depends on the index
    H.update_git_status(root, bufs)
  end
end

H.update_git_head = function(root, bufs)
  local command = H.git_cmd({ 'rev-parse', 'HEAD', '--abbrev-ref', 'HEAD' })

  local on_done = vim.schedule_wrap(function(code, out, err)
    -- Ensure proper data
    if code ~= 0 then return end
    H.cli_err_notify(code, out, err)

    local head, head_name = string.match(out, '^(.-)\n(.*)$')
    if head == nil or head_name == nil then
      return H.notify('Could not parse HEAD data for root ' .. root .. '\n' .. out, 'WARN')
    end

    -- Update data for all buffers from target `root`
    local new_data = { head = head, head_name = head_name }
    for _, buf_id in ipairs(bufs) do
      H.update_buf_data(buf_id, new_data)
    end

    -- Redraw statusline to have possible statusline component up to date
    H.redrawstatus()
  end)

  H.cli_run(command, root, on_done)
end

H.update_git_in_progress = function(repo, bufs)
  -- Get data about what process is in progress
  local in_progress = {}
  if H.is_fs_present(repo .. '/BISECT_LOG') then table.insert(in_progress, 'bisect') end
  if H.is_fs_present(repo .. '/CHERRY_PICK_HEAD') then table.insert(in_progress, 'cherry-pick') end
  if H.is_fs_present(repo .. '/MERGE_HEAD') then table.insert(in_progress, 'merge') end
  if H.is_fs_present(repo .. '/REVERT_HEAD') then table.insert(in_progress, 'revert') end
  if H.is_fs_present(repo .. '/rebase-apply') then table.insert(in_progress, 'apply') end
  if H.is_fs_present(repo .. '/rebase-merge') then table.insert(in_progress, 'rebase') end

  -- Update data for all buffers from target `root`
  local new_data = { in_progress = table.concat(in_progress, ',') }
  for _, buf_id in ipairs(bufs) do
    H.update_buf_data(buf_id, new_data)
  end

  -- Redraw statusline to have possible statusline component up to date
  H.redrawstatus()
end

H.update_git_status = function(root, bufs)
  --stylua: ignore
  local command = H.git_cmd({
    -- NOTE: Use `--no-optional-locks` to reduce conflicts with other Git tasks
    '--no-optional-locks', 'status',
    '--verbose', '--untracked-files=all', '--ignored', '--porcelain', '-z',
    '--',
  })
  local root_len, path_data = string.len(root), {}
  for _, buf_id in ipairs(bufs) do
    -- Use paths relative to the root as in `git status --porcelain` output
    local rel_path = H.get_buf_realpath(buf_id):sub(root_len + 2)
    table.insert(command, rel_path)
    -- Completely not modified paths should be the only ones missing in the
    -- output. Use this status as default.
    path_data[rel_path] = { status = '  ', buf_id = buf_id }
  end

  local on_done = vim.schedule_wrap(function(code, out, err)
    if code ~= 0 then return end
    H.cli_err_notify(code, out, err)

    -- Parse CLI output, which is separated by `\0` to not escape "bad" paths
    for _, l in ipairs(vim.split(out, '\0')) do
      local status, rel_path = string.match(l, '^(..) (.*)$')
      if path_data[rel_path] ~= nil then path_data[rel_path].status = status end
    end

    -- Update data for all buffers
    for _, data in pairs(path_data) do
      local new_data = { status = data.status }
      H.update_buf_data(data.buf_id, new_data)
    end

    -- Redraw statusline to have possible statusline component up to date
    H.redrawstatus()
  end)

  H.cli_run(command, root, on_done)
end

H.update_buf_data = function(buf_id, new_data)
  if not H.is_buf_enabled(buf_id) then return end

  local summary = vim.b[buf_id].minigit_summary or {}
  for key, val in pairs(new_data) do
    H.cache[buf_id][key], summary[key] = val, val
  end
  vim.b[buf_id].minigit_summary = summary

  -- Format summary string
  local head = summary.head_name or ''
  head = head == 'HEAD' and summary.head:sub(1, 7) or head

  local in_progress = summary.in_progress or ''
  if in_progress ~= '' then head = head .. '|' .. in_progress end

  local summary_string = head
  local status = summary.status or ''
  if status ~= '  ' and status ~= '' then summary_string = string.format('%s (%s)', head, status) end
  vim.b[buf_id].minigit_summary_string = summary_string

  -- Trigger dedicated event with target current buffer (for proper `data.buf`)
  vim.api.nvim_buf_call(buf_id, function() H.trigger_event('MiniGitUpdated') end)
end

-- History navigation ---------------------------------------------------------
-- Assuming buffer contains unified combined diff (with "commit" header),
-- compute path, line number, and commit of both "before" and "after" files.
-- Allow cursor to be between "--- a/xxx" line and last line of a hunk.
H.diff_pos_to_source = function()
  local lines, lnum = vim.api.nvim_buf_get_lines(0, 0, -1, false), vim.fn.line('.')

  local res = { init_prefix = lines[lnum]:sub(1, 1) }
  local paths_lnum = H.diff_parse_paths(res, lines, lnum)
  local hunk_lnum = H.diff_parse_hunk(res, lines, lnum)
  local commit_lnum = H.diff_parse_commits(res, lines, lnum)

  -- Try fall back to inferring target commits from 'mini.git' buffer name
  if res.commit_before == nil or res.commit_after == nil then H.diff_parse_bufname(res) end

  local all_present = (res.lnum_before and res.path_before and res.commit_before)
    or (res.lnum_after and res.path_after and res.commit_after)
  local is_in_order = commit_lnum <= paths_lnum and paths_lnum <= hunk_lnum
  if not (all_present and is_in_order) then return nil end

  return res
end

H.diff_parse_paths = function(out, lines, lnum)
  -- NOTE: with `diff.mnemonicPrefix=true` source and destination prefixes can
  -- be not only `a`/`b`, but other characters or none (if added/deleted file)
  local pattern_before, pattern_after = '^%-%-%- ([acio]?)/(.*)$', '^%+%+%+ ([biw]?)/(.*)$'

  -- Allow placing cursor directly on path defining lines
  local cur_line = lines[lnum]
  local prefix_before, path_before = string.match(cur_line, pattern_before)
  local prefix_after, path_after = string.match(cur_line, pattern_after)
  if path_before ~= nil then
    out.path_before = path_before
    prefix_after, out.path_after = string.match(lines[lnum + 1] or '', pattern_after)
    out.lnum_before, out.lnum_after = 1, 1
  elseif path_after ~= nil then
    prefix_before, out.path_before = string.match(lines[lnum - 1] or '', pattern_before)
    out.path_after = path_after
    out.lnum_before, out.lnum_after = 1, 1
  else
    -- Iterate lines upward to find path patterns
    while out.path_after == nil and lnum > 0 do
      prefix_after, out.path_after = string.match(lines[lnum] or '', pattern_after)
      lnum = lnum - 1
    end
    prefix_before, out.path_before = string.match(lines[lnum] or '', pattern_before)
  end

  -- - Don't treat '--- /dev/null' and '+++ /dev/null' matches as paths
  --   Need to check prefix to work in cases like '--- a/dev/null'
  if prefix_before == '' then out.path_before = nil end
  if prefix_after == '' then out.path_after = nil end

  return lnum
end

H.diff_parse_hunk = function(out, lines, lnum)
  if out.lnum_after ~= nil then return lnum end

  local offsets = { [' '] = 0, ['-'] = 0, ['+'] = 0 }
  while lnum > 0 do
    local prefix = lines[lnum]:sub(1, 1)
    if not (prefix == ' ' or prefix == '-' or prefix == '+') then break end
    offsets[prefix] = offsets[prefix] + 1
    lnum = lnum - 1
  end

  local hunk_start_before, hunk_start_after = string.match(lines[lnum] or '', '^@@ %-(%d+),?%d* %+(%d+),?%d* @@')
  if hunk_start_before ~= nil then
    out.lnum_before = math.max(1, tonumber(hunk_start_before) + offsets[' '] + offsets['-'] - 1)
    out.lnum_after = math.max(1, tonumber(hunk_start_after) + offsets[' '] + offsets['+'] - 1)
  end
  return lnum
end

H.diff_parse_commits = function(out, lines, lnum)
  while out.commit_after == nil and lnum > 0 do
    out.commit_after = string.match(lines[lnum], '^commit (%x+)$')
    lnum = lnum - 1
  end
  if out.commit_after ~= nil then out.commit_before = out.commit_after .. '~' end
  return lnum + 1
end

H.diff_parse_bufname = function(out)
  local buf_name = vim.api.nvim_buf_get_name(0)
  local diff_command = string.match(buf_name, '^minigit://%d+/.* diff ?(.*)$')
  if diff_command == nil then return end

  -- Work with output of common `:Git diff` commands
  diff_command = vim.trim(diff_command)
  -- `Git diff` - compares index and work tree
  if diff_command == '' then
    out.commit_before, out.commit_after = ':0', true
  end
  -- `Git diff --cached` - compares HEAD and index
  if diff_command == '--cached' then
    out.commit_before, out.commit_after = 'HEAD', ':0'
  end
  -- `Git diff HEAD` - compares commit and work tree
  if diff_command:find('^[^-]%S*$') ~= nil then
    out.commit_before, out.commit_after = diff_command, true
  end
end

H.parse_diff_source_buf_name = function(buf_name) return string.match(buf_name, '^minigit://%d+/.*show (%x+~?):(.*)$') end

H.deps_pos_to_source = function()
  local lines = vim.api.nvim_buf_get_lines(0, 0, vim.fn.line('.'), false)
  -- Do nothing if on the title (otherwise it operates on previous plugin info)
  if lines[#lines]:find('^[%+%-!]') ~= nil then return end

  -- Locate lines with commit and repo path data
  local commit, commit_lnum = nil, #lines
  while commit == nil and commit_lnum >= 1 do
    local l = lines[commit_lnum]
    commit = l:match('^[><] (%x%x%x%x%x%x%x%x*) |') or l:match('^State[^:]*: %s*(%x+)')
    commit_lnum = commit_lnum - 1
  end

  local cwd, cwd_lnum = nil, #lines
  while cwd == nil and cwd_lnum >= 1 do
    cwd, cwd_lnum = lines[cwd_lnum]:match('^Path: %s*(%S+)$'), cwd_lnum - 1
  end

  -- Do nothing if something is not found or path corresponds to next repo
  if commit == nil or cwd == nil or commit_lnum <= cwd_lnum then return end
  return commit, cwd
end

-- Folding --------------------------------------------------------------------
H.is_hunk_header = function(lnum) return vim.fn.getline(lnum):find('^@@.*@@') ~= nil end

H.is_log_entry_header = function(lnum) return vim.fn.getline(lnum):find('^commit ') ~= nil end

H.is_file_entry_header = function(lnum) return vim.fn.getline(lnum):find('^diff %-%-git') ~= nil end

-- CLI ------------------------------------------------------------------------
H.git_cmd = function(args)
  -- Use '-c gc.auto=0' to disable `stderr` "Auto packing..." messages
  return { MiniGit.config.job.git_executable, '-c', 'gc.auto=0', unpack(args) }
end

H.make_spawn_env = function(env_vars)
  -- Setup all environment variables (`vim.uv.spawn()` by default has none)
  local environ = vim.tbl_deep_extend('force', vim.uv.os_environ(), env_vars)
  local res = {}
  for k, v in pairs(environ) do
    table.insert(res, string.format('%s=%s', k, tostring(v)))
  end
  return res
end

H.cli_run = function(command, cwd, on_done, opts)
  local spawn_opts = opts or {}
  local executable, args = command[1], vim.list_slice(command, 2, #command)
  local process, stdout, stderr = nil, vim.uv.new_pipe(), vim.uv.new_pipe()
  spawn_opts.args, spawn_opts.cwd, spawn_opts.stdio = args, cwd or vim.fn.getcwd(), { nil, stdout, stderr }

  -- Allow `on_done = nil` to mean synchronous execution
  local is_sync, res = false, nil
  if on_done == nil then
    is_sync = true
    on_done = function(code, out, err) res = { code = code, out = out, err = err } end
  end

  local out, err, is_done = {}, {}, false
  local on_exit = function(code)
    -- Ensure calling this only once
    if is_done then return end
    is_done = true

    if process:is_closing() then return end
    process:close()

    -- Convert to strings appropriate for notifications
    out = H.cli_stream_tostring(out)
    err = H.cli_stream_tostring(err):gsub('\r+', '\n'):gsub('\n%s+\n', '\n\n')
    on_done(code, out, err)
  end

  process = vim.uv.spawn(executable, spawn_opts, on_exit)
  H.cli_read_stream(stdout, out)
  H.cli_read_stream(stderr, err)
  vim.defer_fn(function()
    if H.skip_timeout or not process:is_active() then return end
    H.notify('PROCESS REACHED TIMEOUT', 'WARN')
    on_exit(1)
  end, MiniGit.config.job.timeout)

  if is_sync then vim.wait(MiniGit.config.job.timeout + 10, function() return is_done end, 1) end
  return res
end

H.cli_read_stream = function(stream, feed)
  local callback = function(err, data)
    if err then return table.insert(feed, 1, 'ERROR: ' .. err) end
    if data ~= nil then return table.insert(feed, data) end
    stream:close()
  end
  stream:read_start(callback)
end

H.cli_stream_tostring = function(stream) return (table.concat(stream):gsub('\n+$', '')) end

H.cli_err_notify = function(code, out, err)
  local should_stop = code ~= 0
  if should_stop then H.notify(err .. (out == '' and '' or ('\n' .. out)), 'ERROR') end
  if not should_stop and err ~= '' then H.notify(err, 'WARN') end
  return should_stop
end

H.cli_escape = function(x) return (string.gsub(x, '([ \\])', '\\%1')) end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.git) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.set_buf_name = function(buf_id, name) vim.api.nvim_buf_set_name(buf_id, 'minigit://' .. buf_id .. '/' .. name) end

H.notify = function(msg, level_name) vim.notify('(mini.git) ' .. msg, vim.log.levels[level_name]) end

H.trigger_event = function(event_name, data) vim.api.nvim_exec_autocmds('User', { pattern = event_name, data = data }) end

H.is_fs_present = function(path) return vim.uv.fs_stat(path) ~= nil end

H.expandcmd = function(x)
  if x == '<cwd>' then return vim.fn.getcwd() end
  local ok, res = pcall(vim.fn.expandcmd, x)
  return ok and res or x
end

-- TODO: Remove after compatibility with Neovim=0.9 is dropped
H.islist = vim.fn.has('nvim-0.10') == 1 and vim.islist or vim.tbl_islist

-- Try getting buffer's full real path (after resolving symlinks)
H.get_buf_realpath = function(buf_id) return vim.uv.fs_realpath(vim.api.nvim_buf_get_name(buf_id)) or '' end

H.redrawstatus = function() vim.cmd('redrawstatus') end
if vim.api.nvim__redraw ~= nil then H.redrawstatus = function() vim.api.nvim__redraw({ statusline = true }) end end

return MiniGit
