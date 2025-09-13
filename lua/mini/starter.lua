--- *mini.starter* Start screen
--- *MiniStarter*
---
--- MIT License Copyright (c) 2021 Evgeni Chasnovski
---
--- ==============================================================================
---
--- Displayed items are fully customizable both in terms of what they do and
--- how they look (with reasonable defaults). Item selection can be done using
--- prefix query with instant visual feedback.
---
--- Key design ideas:
--- - All available actions are defined inside items. Each item should have the
---   following info:
---     - <action> - function or string for |vim.cmd| which is executed when
---       item is chosen. Empty string result in placeholder "inactive" item.
---     - <name> - string which will be displayed and used for choosing.
---     - <section> - string representing to which section item belongs.
---   There are pre-configured whole sections in |MiniStarter.sections|.
---
--- - Configure what items are displayed by supplying an array which can be
---   normalized to an array of items. Read about how supplied items are
---   normalized in |MiniStarter.refresh|.
---
--- - Modify the final look by supplying content hooks: functions which take
---   buffer content (see |MiniStarter.get_content()|) and identifier as input
---   while returning buffer content as output. There are pre-configured
---   content hook generators in |MiniStarter.gen_hook|.
---
--- - Choosing an item can be done in two ways:
---     - Type prefix query to filter item by matching its name (ignoring
---       case). Displayed information is updated after every typed character.
---       For every item its unique prefix is highlighted.
---     - Use Up/Down arrows and hit Enter.
---
--- - Allow multiple simultaneously open Starter buffers.
---
--- What is doesn't do:
--- - It doesn't support fuzzy query for items. And probably will never do.
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.starter').setup({})`
--- (replace `{}` with your `config` table). It will create global Lua table
--- `MiniStarter` which you can use for scripting or manually (with
--- `:lua MiniStarter.*`).
---
--- See |MiniStarter.config| for `config` structure and default values. For
--- some configuration examples (including one similar to 'vim-startify' and
--- 'dashboard-nvim'), see |MiniStarter-example-config|.
---
--- You can override runtime config settings locally to buffer inside
--- `vim.b.ministarter_config` which should have same structure as
--- `MiniStarter.config`. See |mini.nvim-buffer-local-config| for more details.
--- Note: `vim.b.ministarter_config` is copied to Starter buffer from current
--- buffer allowing full customization.
---
--- To stop module from showing non-error feedback, set `config.silent = true`.
---
--- # Highlight groups ~
---
--- * `MiniStarterCurrent` - current item.
--- * `MiniStarterFooter` - footer units.
--- * `MiniStarterHeader` - header units.
--- * `MiniStarterInactive` - inactive item.
--- * `MiniStarterItem` - item name.
--- * `MiniStarterItemBullet` - units from |MiniStarter.gen_hook.adding_bullet|.
--- * `MiniStarterItemPrefix` - unique query for item.
--- * `MiniStarterSection` - section units.
--- * `MiniStarterQuery` - current query in active items.
---
--- To change any highlight group, modify it directly with |:highlight|.
---
--- # Disabling ~
---
--- To disable core functionality, set `vim.g.ministarter_disable` (globally) or
--- `vim.b.ministarter_disable` (for a buffer) to `true`. Considering high number
--- of different scenarios and customization intentions, writing exact rules
--- for disabling module's functionality is left to user. See
--- |mini.nvim-disabling-recipes| for common recipes.

--- Example configurations
---
--- Configuration similar to 'mhinz/vim-startify': >lua
---
---   local starter = require('mini.starter')
---   starter.setup({
---     evaluate_single = true,
---     items = {
---       starter.sections.builtin_actions(),
---       starter.sections.recent_files(10, false),
---       starter.sections.recent_files(10, true),
---       -- Use this if you set up 'mini.sessions'
---       starter.sections.sessions(5, true)
---     },
---     content_hooks = {
---       starter.gen_hook.adding_bullet(),
---       starter.gen_hook.indexing('all', { 'Builtin actions' }),
---       starter.gen_hook.padding(3, 2),
---     },
---   })
--- <
--- Configuration similar to 'glepnir/dashboard-nvim': >lua
---
---   local starter = require('mini.starter')
---   starter.setup({
---     items = {
---       starter.sections.telescope(),
---     },
---     content_hooks = {
---       starter.gen_hook.adding_bullet(),
---       starter.gen_hook.aligning('center', 'center'),
---     },
---   })
--- <
--- Elaborated configuration showing capabilities of custom items,
--- header/footer, and content hooks: >lua
---
---   local my_items = {
---     { name = 'Echo random number', action = 'lua print(math.random())', section = 'Section 1' },
---     function()
---       return {
---         { name = 'Item #1 from function', action = [[echo 'Item #1']], section = 'From function' },
---         { name = 'Placeholder (always inactive) item', action = '', section = 'From function' },
---         function()
---           return {
---             name = 'Item #1 from double function',
---             action = [[echo 'Double function']],
---             section = 'From double function',
---           }
---         end,
---       }
---     end,
---     { name = [[Another item in 'Section 1']], action = 'lua print(math.random() + 10)', section = 'Section 1' },
---   }
---
---   local footer_n_seconds = (function()
---     local timer = vim.loop.new_timer()
---     local n_seconds = 0
---     timer:start(0, 1000, vim.schedule_wrap(function()
---       if vim.bo.filetype ~= 'ministarter' then
---         timer:stop()
---         return
---       end
---       n_seconds = n_seconds + 1
---       MiniStarter.refresh()
---     end))
---
---     return function()
---       return 'Number of seconds since opening: ' .. n_seconds
---     end
---   end)()
---
---   local hook_top_pad_10 = function(content)
---     -- Pad from top
---     for _ = 1, 10 do
---       -- Insert at start a line with single content unit
---       table.insert(content, 1, { { type = 'empty', string = '' } })
---     end
---     return content
---   end
---
---   local starter = require('mini.starter')
---   starter.setup({
---     items = my_items,
---     footer = footer_n_seconds,
---     content_hooks = { hook_top_pad_10 },
---   })
--- <
---@tag MiniStarter-example-config

--- # Lifecycle of Starter buffer ~
---
--- - Open with |MiniStarter.open()|. It includes creating buffer with
---   appropriate options, mappings, behavior; call to |MiniStarter.refresh()|;
---   issue `MiniStarterOpened` |User| event.
--- - Wait for user to choose an item. This is done using following logic:
---     - Typing any character from `MiniStarter.config.query_updaters` leads
---       to updating query. Read more in |MiniStarter.add_to_query|.
---     - <BS> deletes latest character from query.
---     - <Down>/<Up>, <C-n>/<C-p>, <M-j>/<M-k> move current item.
---     - <CR> executes action of current item.
---     - <C-c> closes Starter buffer.
--- - Evaluate current item when appropriate (after `<CR>` or when there is a
---   single item and `MiniStarter.config.evaluate_single` is `true`). This
---   executes item's `action`.
---@tag MiniStarter-lifecycle

---@alias __starter_buf_id number|nil Buffer identifier of a valid Starter buffer.
---   Default: current buffer.
---@alias __starter_section_fun function Function which returns array of items.

-- Module definition ==========================================================
local MiniStarter = {}
local H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniStarter.config|.
---
---@usage >lua
---   require('mini.starter').setup() -- use default config
---   -- OR
---   require('mini.starter').setup({}) -- replace {} with your config table
--- <
MiniStarter.setup = function(config)
  -- Export module
  _G.MiniStarter = MiniStarter

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Define behavior
  H.create_autocommands(config)

  -- Create default highlighting
  H.create_default_hl()
end

--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
MiniStarter.config = {
  -- Whether to open Starter buffer on VimEnter. Not opened if Neovim was
  -- started with intent to show something else.
  autoopen = true,

  -- Whether to evaluate action of single active item
  evaluate_single = false,

  -- Items to be displayed. Should be an array with the following elements:
  -- - Item: table with <action>, <name>, and <section> keys.
  -- - Function: should return one of these three categories.
  -- - Array: elements of these three types (i.e. item, array, function).
  -- If `nil` (default), default items will be used (see |mini.starter|).
  items = nil,

  -- Header to be displayed before items. Converted to single string via
  -- `tostring` (use `\n` to display several lines). If function, it is
  -- evaluated first. If `nil` (default), polite greeting will be used.
  header = nil,

  -- Footer to be displayed after items. Converted to single string via
  -- `tostring` (use `\n` to display several lines). If function, it is
  -- evaluated first. If `nil` (default), default usage help will be shown.
  footer = nil,

  -- Array  of functions to be applied consecutively to initial content.
  -- Each function should take and return content for Starter buffer (see
  -- |mini.starter| and |MiniStarter.get_content()| for more details).
  content_hooks = nil,

  -- Characters to update query. Each character will have special buffer
  -- mapping overriding your global ones. Be careful to not add `:` as it
  -- allows you to go into command mode.
  query_updaters = 'abcdefghijklmnopqrstuvwxyz0123456789_-.',

  -- Whether to disable showing non-error feedback
  silent = false,
}
--minidoc_afterlines_end

-- Module functionality =======================================================
--- Open Starter buffer
---
--- - Create buffer if necessary and move into it.
--- - Set buffer options. Note that settings are done with |noautocmd| to
---   achieve a massive speedup.
--- - Set buffer mappings. Besides basic mappings (described inside "Lifecycle
---   of Starter buffer" of |mini.starter|), map every character from
---   `MiniStarter.config.query_updaters` to add itself to query with
---   |MiniStarter.add_to_query|.
--- - Populate buffer with |MiniStarter.refresh|.
--- - Issue custom `MiniStarterOpened` event to allow acting upon opening
---   Starter buffer. Use it with
---   `autocmd User MiniStarterOpened <your command>`.
---
--- Note: to fully use it in autocommand, use |autocmd-nested|. Example: >lua
---
---   local starter_open = function() MiniStarter.open() end
---   local au_opts = { nested = true, callback = starter_open }
---   vim.api.nvim_create_autocmd('TabNewEntered', au_opts)
--- <
---@param buf_id number|nil Identifier of existing valid buffer (see |bufnr()|) to
---   open inside. Default: create a new one.
MiniStarter.open = function(buf_id)
  if H.is_disabled() then return end

  -- Ensure proper buffer and open it
  if H.is_in_vimenter then
    -- Use current buffer as it should be empty and not needed. This also
    -- solves the issue of redundant buffer when opening a file from Starter.
    buf_id = vim.api.nvim_get_current_buf()
  end

  if buf_id == nil or not vim.api.nvim_buf_is_valid(buf_id) then buf_id = vim.api.nvim_create_buf(false, true) end

  -- Create buffer data entry
  H.buffer_data[buf_id] = { current_item_id = 1, query = '' }

  -- Ensure that local config in opened Starter buffer is the same as current.
  -- This allow more advanced usage of buffer local configuration.
  local config_local = vim.b.ministarter_config
  vim.api.nvim_set_current_buf(buf_id)
  vim.b.ministarter_config = config_local

  -- Setup buffer behavior
  H.set_buf_name(buf_id, 'welcome')
  H.make_buffer_autocmd(buf_id)
  H.apply_buffer_options(buf_id)
  H.apply_buffer_mappings(buf_id)

  -- Populate buffer
  MiniStarter.refresh()

  -- Issue custom event. Delay at startup, as it is executed with `noautocmd`.
  local trigger_event = function() vim.api.nvim_exec_autocmds('User', { pattern = 'MiniStarterOpened' }) end
  if H.is_in_vimenter then trigger_event = vim.schedule_wrap(trigger_event) end
  trigger_event()

  -- Ensure not being in VimEnter
  H.is_in_vimenter = false
end

--- Refresh Starter buffer
---
--- - Normalize `MiniStarter.config.items`:
---     - Flatten: recursively (in depth-first fashion) parse its elements. If
---       function is found, execute it and continue with parsing its output
---       (this allows deferring item collection up until it is actually
---       needed).  If proper item is found (table with fields `action`,
---       `name`, `section`), add it to output.
---     - Sort: order first by section and then by item id (both in order of
---       appearance).
--- - Normalize `MiniStarter.config.header` and `MiniStarter.config.footer` to
---   be multiple lines by splitting at `\n`. If function - evaluate it first.
--- - Make initial buffer content (see |MiniStarter.get_content()| for a
---   description of what a buffer content is). It consist from content lines
---   with single content unit:
---     - First lines contain strings of normalized header.
---     - Body is for normalized items. Section names have own lines preceded
---       by empty line.
---     - Last lines contain separate strings of normalized footer.
--- - Sequentially apply hooks from `MiniStarter.config.content_hooks` to
---   content. All hooks are applied with `(content, buf_id)` signature. Output
---   of one hook serves as first argument to the next.
--- - Gather final items from content with |MiniStarter.content_to_items|.
--- - Convert content to buffer lines with |MiniStarter.content_to_lines| and
---   add them to buffer.
--- - Add highlighting of content units.
--- - Position cursor.
--- - Make current query. This results into some items being marked as
---   "inactive" and updating highlighting of current query on "active" items.
---
--- Note: this function is executed on every |VimResized| to allow more
--- responsive behavior.
---
---@param buf_id __starter_buf_id
MiniStarter.refresh = function(buf_id)
  buf_id = buf_id or vim.api.nvim_get_current_buf()
  if not H.validate_starter_buf_id(buf_id, 'refresh()') then return end

  local data = H.buffer_data[buf_id]
  local config = H.get_config()

  -- Normalize certain config values
  data.header = H.normalize_header_footer(config.header or H.default_header)
  local items = H.normalize_items(config.items or H.default_items)
  data.footer = H.normalize_header_footer(config.footer or H.default_footer)

  -- Evaluate content
  local content = H.make_initial_content(data.header, items, data.footer)
  local hooks = config.content_hooks or H.default_content_hooks
  for _, f in ipairs(hooks) do
    content = f(content, buf_id)
  end
  data.content = content

  -- Set items. Possibly reset current item id if items have changed.
  local old_items = data.items
  data.items = MiniStarter.content_to_items(content)
  if not vim.deep_equal(data.items, old_items) then data.current_item_id = 1 end

  -- Add content
  vim.bo[buf_id].modifiable = true
  vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, MiniStarter.content_to_lines(content))
  vim.bo[buf_id].modifiable = false

  -- Add highlighting
  H.content_highlight(buf_id)
  H.items_highlight(buf_id)

  -- -- Always position cursor on current item
  H.position_cursor_on_current_item(buf_id)
  H.add_hl_current_item(buf_id)

  -- Apply current query (clear command line afterwards)
  H.make_query(buf_id)
end

--- Close Starter buffer
---
---@param buf_id __starter_buf_id
MiniStarter.close = function(buf_id)
  buf_id = buf_id or vim.api.nvim_get_current_buf()
  if not H.validate_starter_buf_id(buf_id, 'close()') then return end

  -- Use `pcall` to allow calling for already non-existing buffer
  pcall(vim.api.nvim_buf_delete, buf_id, {})
end

-- Sections -------------------------------------------------------------------
--- Table of pre-configured sections
MiniStarter.sections = {}

--- Section with builtin actions
---
---@return table Array of items.
MiniStarter.sections.builtin_actions = function()
  return {
    { name = 'Edit new buffer', action = 'enew', section = 'Builtin actions' },
    { name = 'Quit Neovim', action = 'qall', section = 'Builtin actions' },
  }
end

--- Section with |MiniSessions| sessions
---
--- Sessions are taken from |MiniSessions.detected|. Notes:
--- - If it shows "'mini.sessions' is not set up", it means that you didn't
---   call `require('mini.sessions').setup()`.
--- - If it shows "There are no detected sessions in 'mini.sessions'", it means
---   that there are no sessions at the current sessions directory. Either
---   create session or supply different directory where session files are
---   stored (see |MiniSessions.setup|).
--- - Local session (if detected) is always displayed first.
---
---@param n number|nil Number of returned items. Default: 5.
---@param recent boolean|nil Whether to use recent sessions (instead of
---   alphabetically by name). Default: true.
---
---@return __starter_section_fun
MiniStarter.sections.sessions = function(n, recent)
  n = n or 5
  if recent == nil then recent = true end

  return function()
    if _G.MiniSessions == nil then
      return { { name = [['mini.sessions' is not set up]], action = '', section = 'Sessions' } }
    end

    local items = {}
    for session_name, session in pairs(_G.MiniSessions.detected) do
      table.insert(items, {
        _session = session,
        name = ('%s%s'):format(session_name, session.type == 'local' and ' (local)' or ''),
        action = ([[lua _G.MiniSessions.read('%s')]]):format(session_name),
        section = 'Sessions',
      })
    end

    if vim.tbl_count(items) == 0 then
      return { { name = [[There are no detected sessions in 'mini.sessions']], action = '', section = 'Sessions' } }
    end

    local sort_fun
    if recent then
      sort_fun = function(a, b)
        local a_time = a._session.type == 'local' and math.huge or a._session.modify_time
        local b_time = b._session.type == 'local' and math.huge or b._session.modify_time
        return a_time > b_time
      end
    else
      sort_fun = function(a, b)
        local a_name = a._session.type == 'local' and '' or a.name
        local b_name = b._session.type == 'local' and '' or b.name
        return a_name < b_name
      end
    end
    table.sort(items, sort_fun)

    -- Take only first `n` elements and remove helper fields
    return vim.tbl_map(function(x)
      x._session = nil
      return x
    end, vim.list_slice(items, 1, n))
  end
end

--- Section with most recently used files
---
--- Files are taken from |vim.v.oldfiles|.
---
---@param n number|nil Number of returned items. Default: 5.
---@param current_dir boolean|nil Whether to return files only from current working
---   directory and its subdirectories. Default: `false`.
---@param show_path boolean|function|nil Whether to append file name with its path.
---   If callable, will be called with full path and should return string to be
---   directly appended to file name. Default: `true`.
---
---@return __starter_section_fun
MiniStarter.sections.recent_files = function(n, current_dir, show_path)
  n = n or 5
  if current_dir == nil then current_dir = false end

  if show_path == nil then show_path = true end
  if show_path == false then show_path = function() return '' end end
  if show_path == true then
    show_path = function(path) return string.format(' (%s)', vim.fn.fnamemodify(path, ':~:.')) end
  end
  if not vim.is_callable(show_path) then H.error('`show_path` should be boolean or callable.') end

  return function()
    local section = string.format('Recent files%s', current_dir and ' (current directory)' or '')
    local sep = vim.loop.os_uname().sysname == 'Windows_NT' and '\\' or '/'
    local cwd = vim.fn.getcwd() .. sep

    local files = {}
    for _, f in ipairs(vim.v.oldfiles) do
      -- Use only actually readable files possibly respecting current directory
      if vim.fn.filereadable(f) == 1 and (not current_dir or vim.startswith(f, cwd)) then
        table.insert(files, f)
        if #files >= n then break end
      end
    end

    if #files == 0 then
      local suffix = current_dir and 'in current directory' or '(`v:oldfiles` is empty)'
      local text = 'There are no recent files ' .. suffix
      return { { name = text, action = '', section = section } }
    end

    -- Create items
    local items = {}
    for _, f in ipairs(files) do
      local name = vim.fn.fnamemodify(f, ':t') .. show_path(f)
      table.insert(items, { action = function() H.edit(f) end, name = name, section = section })
    end

    return items
  end
end

-- stylua: ignore
--- Section with 'mini.pick' pickers
---
--- Notes:
--- - All actions require |mini.pick| module of 'mini.nvim'.
--- - "Command history", "Explorer", and "Visited paths" items
---   require |mini.extra| module of 'mini.nvim'.
--- - "Visited paths" items requires |mini.visits| module of 'mini.nvim'.
---
---@return __starter_section_fun
MiniStarter.sections.pick = function()
  return function()
    return {
      { action = 'Pick history scope=":"', name = 'Command history', section = 'Pick' },
      { action = 'Pick explorer',          name = 'Explorer',        section = 'Pick' },
      { action = 'Pick files',             name = 'Files',           section = 'Pick' },
      { action = 'Pick grep_live',         name = 'Grep live',       section = 'Pick' },
      { action = 'Pick help',              name = 'Help tags',       section = 'Pick' },
      { action = 'Pick visit_paths',       name = 'Visited paths',   section = 'Pick' },
    }
  end
end

-- stylua: ignore
--- Section with basic Telescope pickers relevant to start screen
---
--- Notes:
--- - All actions require 'nvim-telescope/telescope.nvim' plugin.
--- - "Browser" item requires 'nvim-telescope/telescope-file-browser.nvim'.
---
---@return __starter_section_fun
MiniStarter.sections.telescope = function()
  return function()
    return {
      { action = 'Telescope file_browser',    name = 'Browser',         section = 'Telescope' },
      { action = 'Telescope command_history', name = 'Command history', section = 'Telescope' },
      { action = 'Telescope find_files',      name = 'Files',           section = 'Telescope' },
      { action = 'Telescope help_tags',       name = 'Help tags',       section = 'Telescope' },
      { action = 'Telescope live_grep',       name = 'Live grep',       section = 'Telescope' },
      { action = 'Telescope oldfiles',        name = 'Old files',       section = 'Telescope' },
    }
  end
end

-- Content hooks --------------------------------------------------------------
--- Table with pre-configured content hook generators
---
--- Each element is a function which returns content hook. So to use them
--- inside |MiniStarter.setup|, call them.
MiniStarter.gen_hook = {}

--- Hook generator for padding
---
--- Output is a content hook which adds constant padding from left and top.
--- This allows tweaking the screen position of buffer content.
---
---@param left number|nil Number of empty spaces to add to start of each content
---   line. Default: 0.
---@param top number|nil Number of empty lines to add to start of content.
---   Default: 0.
---
---@return function Content hook.
MiniStarter.gen_hook.padding = function(left, top)
  left = math.max(left or 0, 0)
  top = math.max(top or 0, 0)
  return function(content, _)
    -- Add left padding
    local left_pad = string.rep(' ', left)
    for _, line in ipairs(content) do
      local is_empty_line = #line == 0 or (#line == 1 and line[1].string == '')
      if not is_empty_line then table.insert(line, 1, H.content_unit(left_pad, 'empty', nil)) end
    end

    -- Add top padding
    local top_lines = {}
    for _ = 1, top do
      table.insert(top_lines, { H.content_unit('', 'empty', nil) })
    end
    content = vim.list_extend(top_lines, content)

    return content
  end
end

--- Hook generator for adding bullet to items
---
--- Output is a content hook which adds supplied string to be displayed to the
--- left of item.
---
---@param bullet string|nil String to be placed to the left of item name.
---   Default: "░ ".
---@param place_cursor boolean|nil Whether to place cursor on the first character
---   of bullet when corresponding item becomes current. Default: true.
---
---@return function Content hook.
MiniStarter.gen_hook.adding_bullet = function(bullet, place_cursor)
  bullet = bullet or '░ '
  if place_cursor == nil then place_cursor = true end
  return function(content)
    local coords = MiniStarter.content_coords(content, 'item')
    -- Go backwards to avoid conflict when inserting units
    for i = #coords, 1, -1 do
      local l_num, u_num = coords[i].line, coords[i].unit
      local bullet_unit = {
        string = bullet,
        type = 'item_bullet',
        hl = 'MiniStarterItemBullet',
        -- Use `_item` instead of `item` because it is better to be 'private'
        _item = content[l_num][u_num].item,
        _place_cursor = place_cursor,
      }
      table.insert(content[l_num], u_num, bullet_unit)
    end

    return content
  end
end

--- Hook generator for indexing items
---
--- Output is a content hook which adds unique index to the start of item's
--- name. It results into shortening queries required to choose an item (at
--- expense of clarity).
---
---@param grouping string|nil One of "all" (number indexing across all sections) or
---   "section" (letter-number indexing within each section). Default: "all".
---@param exclude_sections table|nil Array of section names (values of `section`
---   element of item) for which index won't be added. Default: `{}`.
---
---@return function Content hook.
MiniStarter.gen_hook.indexing = function(grouping, exclude_sections)
  grouping = grouping or 'all'
  exclude_sections = exclude_sections or {}
  local per_section = grouping == 'section'

  return function(content, _)
    local cur_section, n_section, n_item = nil, 0, 0
    local coords = MiniStarter.content_coords(content, 'item')

    for _, c in ipairs(coords) do
      local unit = content[c.line][c.unit]
      local item = unit.item

      if not vim.tbl_contains(exclude_sections, item.section) then
        n_item = n_item + 1
        if cur_section ~= item.section then
          cur_section = item.section
          -- Cycle through lower case letters
          n_section = math.fmod(n_section, 26) + 1
          n_item = per_section and 1 or n_item
        end

        local section_index = per_section and string.char(96 + n_section) or ''
        unit.string = ('%s%s. %s'):format(section_index, n_item, unit.string)
      end
    end

    return content
  end
end

--- Hook generator for aligning content
---
--- Output is a content hook which independently aligns content horizontally
--- and vertically. Window width and height are taken from first window in current
--- tabpage displaying the Starter buffer.
---
--- Basically, this computes left and top pads for |MiniStarter.gen_hook.padding|
--- such that output lines would appear aligned in certain way.
---
---@param horizontal string|nil One of "left", "center", "right". Default: "left".
---@param vertical string|nil One of "top", "center", "bottom". Default: "top".
---
---@return function Content hook.
MiniStarter.gen_hook.aligning = function(horizontal, vertical)
  horizontal = horizontal or 'left'
  vertical = vertical or 'top'

  local horiz_coef = ({ left = 0, center = 0.5, right = 1.0 })[horizontal]
  local vert_coef = ({ top = 0, center = 0.5, bottom = 1.0 })[vertical]

  return function(content, buf_id)
    local win_id = vim.fn.bufwinid(buf_id)
    if win_id < 0 then return end

    local line_strings = MiniStarter.content_to_lines(content)

    -- Align horizontally
    -- Don't use `string.len()` to account for multibyte characters
    local lines_width = vim.tbl_map(function(l) return vim.fn.strdisplaywidth(l) end, line_strings)
    local min_right_space = vim.api.nvim_win_get_width(win_id) - math.max(unpack(lines_width))
    local left_pad = math.max(math.floor(horiz_coef * min_right_space), 0)

    -- Align vertically
    local bottom_space = vim.api.nvim_win_get_height(win_id) - #line_strings
    local top_pad = math.max(math.floor(vert_coef * bottom_space), 0)

    return MiniStarter.gen_hook.padding(left_pad, top_pad)(content)
  end
end

-- Work with content ----------------------------------------------------------
--- Get content of Starter buffer
---
--- Generally, buffer content is a table in the form of "2d array" (or rather
--- "2d list" because number of elements can differ):
--- - Each element represents content line: an array with content units to be
---   displayed in one buffer line.
--- - Each content unit is a table with at least the following elements:
---     - "type" - string with type of content. Something like "item",
---       "section", "header", "footer", "empty", etc.
---     - "string" - which string should be displayed. May be an empty string.
---     - "hl" - which highlighting should be applied to content string. May be
---       `nil` for no highlighting.
---
--- See |MiniStarter.content_to_lines| for converting content to buffer lines
--- and |MiniStarter.content_to_items| - to list of parsed items.
---
--- Notes:
--- - Content units with type "item" also have `item` element with all
---   information about an item it represents. Those elements are used directly
---   to create an array of items used for query.
---
---@param buf_id __starter_buf_id
MiniStarter.get_content = function(buf_id)
  buf_id = buf_id or vim.api.nvim_get_current_buf()
  if not H.validate_starter_buf_id(buf_id, 'get_content()', 'error') then return end

  return H.buffer_data[buf_id].content
end

--- Helper to iterate through content
---
--- Basically, this traverses content "2d array" (in depth-first fashion; top
--- to bottom, left to right) and returns "coordinates" of units for which
--- `predicate` is true-ish.
---
---@param content table|nil Content "2d array". Default: content of current buffer.
---@param predicate function|string|nil Predictate to filter units. If it is:
---    - Function, then it is evaluated with unit as input.
---    - String, then it checks unit to have this type (allows easy getting of
---      units with some type).
---    - `nil`, all units are kept.
---
---@return table Array of resulting units' coordinates. Each coordinate is a
---   table with <line> and <unit> keys. To retrieve actual unit from coordinate
---   `c`, use `content[c.line][c.unit]`.
MiniStarter.content_coords = function(content, predicate)
  content = content or MiniStarter.get_content()
  if predicate == nil then predicate = function(_) return true end end
  if type(predicate) == 'string' then
    local pred_type = predicate
    predicate = function(unit) return unit.type == pred_type end
  end

  local res = {}
  for l_num, line in ipairs(content) do
    for u_num, unit in ipairs(line) do
      if predicate(unit) then table.insert(res, { line = l_num, unit = u_num }) end
    end
  end
  return res
end

-- stylua: ignore start
--- Convert content to buffer lines
---
--- One buffer line is made by concatenating `string` element of units within
--- same content line.
---
---@param content table|nil Content "2d array". Default: content of current buffer.
---
---@return table Array of strings for each buffer line.
MiniStarter.content_to_lines = function(content)
  return vim.tbl_map(
    function(content_line)
      return table.concat(
      -- Ensure that each content line is indeed a single buffer line
        vim.tbl_map(function(x) return x.string:gsub('\n', ' ') end, content_line), ''
      )
    end,
    content or MiniStarter.get_content()
  )
end
-- stylua: ignore end

--- Convert content to items
---
--- Parse content (in depth-first fashion) and retrieve each item from `item`
--- element of content units with type "item". This also:
--- - Computes some helper information about how item will be actually
---   displayed (after |MiniStarter.content_to_lines|) and minimum number of
---   prefix characters needed for a particular item to be queried single.
--- - Modifies item's `name` element taking it from corresponding `string`
---   element of content unit. This allows modifying item's `name` at the stage
---   of content hooks (like, for example, in |MiniStarter.gen_hook.indexing|).
---
---@param content table|nil Content "2d array". Default: content of current buffer.
---
---@return table Array of items.
MiniStarter.content_to_items = function(content)
  content = content or MiniStarter.get_content()

  -- NOTE: this havily utilizes 'modify by reference' nature of Lua tables
  local items = {}
  for l_num, line in ipairs(content) do
    -- Track 0-based starting column of current unit (using byte length)
    local start_col = 0
    for _, unit in ipairs(line) do
      -- Cursor position is (1, 0)-based
      local cursorpos = { l_num, start_col }

      if unit.type == 'item' then
        local item = unit.item
        -- Take item's name from content string
        item.name = unit.string:gsub('\n', ' ')
        item._line = l_num - 1
        item._start_col = start_col
        item._end_col = start_col + unit.string:len()
        -- Don't overwrite possible cursor position from item's bullet
        item._cursorpos = item._cursorpos or cursorpos

        table.insert(items, item)
      end

      -- Prefer placing cursor at start of item's bullet
      if unit.type == 'item_bullet' and unit._place_cursor then
        -- Item bullet uses 'private' `_item` element instead of `item`
        unit._item._cursorpos = cursorpos
      end

      start_col = start_col + unit.string:len()
    end
  end

  -- Compute length of unique prefix for every item's name (ignoring case)
  local strings = vim.tbl_map(function(x) return x.name:lower() end, items)
  local nprefix = H.unique_nprefix(strings)
  for i, n in ipairs(nprefix) do
    items[i]._nprefix = n
  end

  return items
end

-- Other exported functions ---------------------------------------------------
--- Evaluate current item
---
--- Note that it resets current query before evaluation, as it is rarely needed
--- any more.
---
---@param buf_id __starter_buf_id
MiniStarter.eval_current_item = function(buf_id)
  buf_id = buf_id or vim.api.nvim_get_current_buf()
  if not H.validate_starter_buf_id(buf_id, 'eval_current_item()') then return end

  -- Reset query before evaluation without query echo (avoids hit-enter-prompt)
  H.make_query(vim.api.nvim_get_current_buf(), '', false)

  local data = H.buffer_data[buf_id]
  H.eval_fun_or_string(data.items[data.current_item_id].action, true)
end

--- Update current item
---
--- This makes next (with respect to `direction`) active item to be current.
---
---@param direction string One of "next" or "previous".
---@param buf_id __starter_buf_id
MiniStarter.update_current_item = function(direction, buf_id)
  buf_id = buf_id or vim.api.nvim_get_current_buf()
  if not H.validate_starter_buf_id(buf_id, 'update_current_item()') then return end

  local data = H.buffer_data[buf_id]

  -- Advance current item
  local prev_current = data.current_item_id
  data.current_item_id = H.next_active_item_id(buf_id, data.current_item_id, direction)
  if data.current_item_id == prev_current then return end

  -- Update cursor position
  H.position_cursor_on_current_item(buf_id)

  -- Highlight current item
  vim.api.nvim_buf_clear_namespace(buf_id, H.ns.current_item, 0, -1)
  H.add_hl_current_item(buf_id)
end

--- Add character to current query
---
--- - Update current query by appending `char` to its end (only if it results
---   into at least one active item) or delete latest character if `char` is `nil`.
--- - Recompute status of items: "active" if its name starts with new query,
---   "inactive" otherwise.
--- - Update highlighting: whole strings for "inactive" items, current query
---   for "active" items.
---
---@param char string|nil Single character to be added to query. If `nil`, deletes
---   latest character from query.
---@param buf_id __starter_buf_id
MiniStarter.add_to_query = function(char, buf_id)
  buf_id = buf_id or vim.api.nvim_get_current_buf()
  if not H.validate_starter_buf_id(buf_id, 'add_to_query()') then return end

  local data = H.buffer_data[buf_id]

  local new_query
  if char == nil then
    new_query = data.query:sub(0, data.query:len() - 1)
  else
    new_query = ('%s%s'):format(data.query, char)
  end
  H.make_query(buf_id, new_query)
end

--- Set current query
---
---@param query string|nil Query to be set (only if it results into at least one
---   active item). Default: `nil` for setting query to empty string, which
---   essentially resets query.
---@param buf_id __starter_buf_id
MiniStarter.set_query = function(query, buf_id)
  query = query or ''
  if type(query) ~= 'string' then error('`query` should be either `nil` or string.') end

  buf_id = buf_id or vim.api.nvim_get_current_buf()
  if not H.validate_starter_buf_id(buf_id, 'add_to_query()') then return end

  H.make_query(buf_id, query)
end

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniStarter.config)

-- Default config values
H.default_items = {
  function()
    if _G.MiniSessions == nil then return {} end
    return MiniStarter.sections.sessions(5, true)()
  end,
  MiniStarter.sections.recent_files(5, false, false),
  MiniStarter.sections.builtin_actions(),
}

H.default_header = function()
  local hour = tonumber(vim.fn.strftime('%H'))
  -- [04:00, 12:00) - morning, [12:00, 20:00) - day, [20:00, 04:00) - evening
  local part_id = math.floor((hour + 4) / 8) + 1
  local day_part = ({ 'evening', 'morning', 'afternoon', 'evening' })[part_id]
  local username = vim.loop.os_get_passwd()['username'] or 'USERNAME'

  return ('Good %s, %s'):format(day_part, username)
end

H.default_footer = [[
Type query to filter items
<BS> deletes latest character from query
<Esc> resets current query
<Down/Up>, <C-n/p>, <M-j/k> move current item
<CR> executes action of current item
<C-c> closes this buffer]]

H.default_content_hooks = { MiniStarter.gen_hook.adding_bullet(), MiniStarter.gen_hook.aligning('center', 'center') }

-- Storage for all Starter buffers. Fields - buffer number. Values - table:
-- - <content> - buffer content (2d array of units)
-- - <current_item_id> - identifier of current item
-- - <footer> - table of strings
-- - <header> - table of strings
-- - <items> - normalized items gathered from final content
-- - <query> - current search query
H.buffer_data = {}

-- Namespaces for highlighting
H.ns = {
  activity = vim.api.nvim_create_namespace(''),
  current_item = vim.api.nvim_create_namespace(''),
  general = vim.api.nvim_create_namespace(''),
}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  H.check_type('autoopen', config.autoopen, 'boolean')
  H.check_type('evaluate_single', config.evaluate_single, 'boolean')
  H.check_type('items', config.items, 'table', true)
  -- `header` and `footer` can have any type
  H.check_type('content_hooks', config.content_hooks, 'table', true)
  H.check_type('query_updaters', config.query_updaters, 'string')
  H.check_type('silent', config.silent, 'boolean')

  return config
end

H.apply_config = function(config) MiniStarter.config = config end

H.create_autocommands = function(config)
  local gr = vim.api.nvim_create_augroup('MiniStarter', {})

  if config.autoopen then
    local on_vimenter = function()
      if H.is_something_shown() then return end

      -- Set indicator used to make different decision on startup
      H.is_in_vimenter = true
      -- Use 'noautocmd' for better startup time
      vim.cmd('noautocmd lua MiniStarter.open()')
    end

    local au_opts = { group = gr, nested = true, once = true, callback = on_vimenter, desc = 'Open on VimEnter' }
    vim.api.nvim_create_autocmd('VimEnter', au_opts)
  end

  vim.api.nvim_create_autocmd('ColorScheme', { group = gr, callback = H.create_default_hl, desc = 'Ensure colors' })
end

--stylua: ignore
H.create_default_hl = function()
  local set_default_hl = function(name, data)
    data.default = true
    vim.api.nvim_set_hl(0, name, data)
  end

  set_default_hl('MiniStarterCurrent',    { link = 'MiniStarterItem' })
  set_default_hl('MiniStarterFooter',     { link = 'Title' })
  set_default_hl('MiniStarterHeader',     { link = 'Title' })
  set_default_hl('MiniStarterInactive',   { link = 'Comment' })
  set_default_hl('MiniStarterItem',       { link = 'Normal' })
  set_default_hl('MiniStarterItemBullet', { link = 'Delimiter' })
  set_default_hl('MiniStarterItemPrefix', { link = 'WarningMsg' })
  set_default_hl('MiniStarterSection',    { link = 'Delimiter' })
  set_default_hl('MiniStarterQuery',      { link = 'MoreMsg' })
end

H.is_disabled = function() return vim.g.ministarter_disable == true or vim.b.ministarter_disable == true end

H.get_config = function(config)
  return vim.tbl_deep_extend('force', MiniStarter.config, vim.b.ministarter_config or {}, config or {})
end

-- Normalize config elements --------------------------------------------------
H.normalize_items = function(items)
  local res = H.items_flatten(items)
  if #res == 0 then return { { name = '`config.items` is empty', action = '', section = '' } } end
  return H.items_sort(res)
end

H.normalize_header_footer = function(x)
  if type(x) == 'function' then x = x() end
  local res = tostring(x)
  if res == '' then return {} end
  return vim.split(res, '\n')
end

-- Work with buffer content ---------------------------------------------------
H.make_initial_content = function(header, items, footer)
  local content = {}

  -- Add header lines
  for _, l in ipairs(header) do
    H.content_add_line(content, { H.content_unit(l, 'header', 'MiniStarterHeader') })
  end
  H.content_add_empty_lines(content, #header > 0 and 1 or 0)

  -- Add item lines
  H.content_add_items(content, items)

  -- Add footer lines
  H.content_add_empty_lines(content, #footer > 0 and 1 or 0)
  for _, l in ipairs(footer) do
    H.content_add_line(content, { H.content_unit(l, 'footer', 'MiniStarterFooter') })
  end

  return content
end

H.content_unit = function(string, type, hl, extra)
  return vim.tbl_extend('force', { string = string, type = type, hl = hl }, extra or {})
end

H.content_add_line = function(content, content_line) table.insert(content, content_line) end

H.content_add_empty_lines = function(content, n)
  for _ = 1, n do
    H.content_add_line(content, { H.content_unit('', 'empty', nil) })
  end
end

H.content_add_items = function(content, items)
  local cur_section
  for _, item in ipairs(items) do
    -- Possibly add section line
    if cur_section ~= item.section then
      -- Don't add empty line before first section line
      H.content_add_empty_lines(content, cur_section == nil and 0 or 1)
      H.content_add_line(content, { H.content_unit(item.section, 'section', 'MiniStarterSection') })
      cur_section = item.section
    end

    H.content_add_line(content, { H.content_unit(item.name, 'item', 'MiniStarterItem', { item = item }) })
  end
end

H.content_highlight = function(buf_id)
  for l_num, content_line in ipairs(MiniStarter.get_content(buf_id)) do
    -- Track 0-based starting column of current unit (using byte length)
    local start_col = 0
    for _, unit in ipairs(content_line) do
      if unit.hl ~= nil then
        H.buf_hl(buf_id, H.ns.general, unit.hl, l_num - 1, start_col, start_col + unit.string:len(), 50)
      end
      start_col = start_col + unit.string:len()
    end
  end
end

-- Work with items -----------------------------------------------------------
H.items_flatten = function(items)
  local res, f = {}, nil
  f = function(x)
    -- Expand (possibly recursively) functions immediately
    local n_nested = 0
    while type(x) == 'function' and n_nested <= 100 do
      n_nested = n_nested + 1
      if n_nested > 100 then H.message('Too many nested functions in `config.items`.') end
      x = x()
    end

    if H.is_item(x) then
      -- Use deepcopy to allow adding fields to items without changing original
      table.insert(res, vim.deepcopy(x))
      return
    end

    if type(x) ~= 'table' then return end
    return vim.tbl_map(f, x)
  end

  f(items)
  return res
end

H.items_sort = function(items)
  -- Order first by section and then by item id (both in order of appearance)
  -- Gather items grouped per section in order of their appearance
  local sections, section_order = {}, {}
  for _, item in ipairs(items) do
    local sec = item.section
    if section_order[sec] == nil then
      table.insert(sections, {})
      section_order[sec] = #sections
    end
    table.insert(sections[section_order[sec]], item)
  end

  -- Unroll items in depth-first fashion
  local res = {}
  for _, section_items in ipairs(sections) do
    for _, item in ipairs(section_items) do
      table.insert(res, item)
    end
  end

  return res
end

H.items_highlight = function(buf_id)
  for _, item in ipairs(H.buffer_data[buf_id].items) do
    H.buf_hl(
      buf_id,
      H.ns.general,
      'MiniStarterItemPrefix',
      item._line,
      item._start_col,
      item._start_col + item._nprefix,
      52
    )
  end
end

H.next_active_item_id = function(buf_id, item_id, direction)
  local items = H.buffer_data[buf_id].items

  -- Advance in cyclic fashion
  local id = item_id
  local n_items = vim.tbl_count(items)
  local increment = direction == 'next' and 1 or (n_items - 1)

  -- Increment modulo `n` but for 1-based indexing
  id = math.fmod(id + increment - 1, n_items) + 1
  while not (items[id]._active or id == item_id) do
    id = math.fmod(id + increment - 1, n_items) + 1
  end

  return id
end

H.position_cursor_on_current_item = function(buf_id)
  local data = H.buffer_data[buf_id]
  local cursorpos = data.items[data.current_item_id]._cursorpos
  for _, win_id in ipairs(H.get_buffer_windows(buf_id)) do
    vim.api.nvim_win_set_cursor(win_id, cursorpos)
  end
end

H.item_is_active = function(item, query)
  -- Item is active = item's name starts with query (ignoring case) and item's
  -- action is non-empty
  return vim.startswith(item.name:lower(), query) and item.action ~= ''
end

-- Work with queries ----------------------------------------------------------
H.make_query = function(buf_id, query, echo_msg)
  if echo_msg == nil then echo_msg = true end

  local data = H.buffer_data[buf_id]
  -- Ignore case
  query = (query or data.query):lower()

  -- Don't make query if it results into no active items
  local n_active = 0
  for _, item in ipairs(data.items) do
    n_active = n_active + (H.item_is_active(item, query) and 1 or 0)
  end

  if n_active == 0 and query ~= '' then
    H.message(('Query %s results into no active items. Current query: %s'):format(vim.inspect(query), data.query))
    return
  end

  -- Update current query and active items
  data.query = query
  for _, item in ipairs(data.items) do
    item._active = H.item_is_active(item, query)
  end

  -- Move to next active item if current is not active
  if not data.items[data.current_item_id]._active then MiniStarter.update_current_item('next', buf_id) end

  -- Update activity highlighting. This should go before `evaluate_single`
  -- check because evaluation might not result into closing Starter buffer.
  vim.api.nvim_buf_clear_namespace(buf_id, H.ns.activity, 0, -1)
  H.add_hl_activity(buf_id, query)

  -- Possibly evaluate single active item
  if H.get_config().evaluate_single and n_active == 1 then
    MiniStarter.eval_current_item(buf_id)
    return
  end

  -- Notify about new query if not in VimEnter, where it might lead to
  -- unpleasant flickering due to startup process (lazy loading, etc.).
  if echo_msg and not H.is_in_vimenter and vim.o.cmdheight > 0 then
    -- Make sure that output of `echo` will be shown
    vim.cmd('redraw')

    H.echo(('Query: %s'):format(query))
  end
end

-- Work with Starter buffer ---------------------------------------------------
H.make_buffer_autocmd = function(buf_id)
  local augroup = vim.api.nvim_create_augroup('MiniStarterBuffer', {})

  local au = function(event, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = augroup, buffer = buf_id, callback = callback, desc = desc })
  end

  au({ 'VimResized', 'BufEnter' }, function() MiniStarter.refresh(buf_id) end, 'Refresh')
  au('CursorMoved', function() H.position_cursor_on_current_item(buf_id) end, 'Position cursor')

  local cache_showtabline = vim.o.showtabline
  au('BufLeave', function()
    if vim.o.cmdheight > 0 then vim.cmd("echo ''") end
    if vim.o.showtabline == 1 then vim.o.showtabline = cache_showtabline end
  end, 'On BufLeave')
end

H.apply_buffer_options = function(buf_id)
  -- NOTE: assumed that it is executing with `buf_id` being current buffer

  -- Force Normal mode. NOTEs:
  -- - Using `vim.cmd('normal! \28\14')` weirdly does not work.
  -- - Using `vim.api.nvim_input([[<C-\><C-n>]])` doesn't play nice if `<C-\>`
  --   mapping is present (maybe due to non-blocking nature of `nvim_input()`).
  vim.api.nvim_feedkeys('\28\14', 'nx', false)

  -- Having `noautocmd` is crucial for performance: ~9ms without it, ~1.6ms with it
  vim.cmd('noautocmd silent! set filetype=ministarter')

  local options = {
    -- Taken from 'vim-startify'
    'bufhidden=wipe',
    'colorcolumn=',
    'foldcolumn=0',
    'matchpairs=',
    'nobuflisted',
    'nocursorcolumn',
    'nocursorline',
    'nolist',
    'nonumber',
    'noreadonly',
    'norelativenumber',
    'nospell',
    'noswapfile',
    'signcolumn=no',
    'statuscolumn=',
    'synmaxcol&',
    -- Differ from 'vim-startify'
    'buftype=nofile',
    'nomodeline',
    'nomodifiable',
    'foldlevel=999',
    'nowrap',
  }
  -- Vim's `setlocal` is currently more robust compared to `opt_local`
  vim.cmd(('silent! noautocmd setlocal %s'):format(table.concat(options, ' ')))

  -- Hide tabline on single tab by setting `showtabline` to default value (but
  -- not statusline as it weirdly feels 'naked' without it).
  vim.o.showtabline = 1

  -- Make it a better user experience with other modules
  vim.b.minicursorword_disable = true
  vim.b.minitrailspace_disable = true
  if _G.MiniTrailspace ~= nil then _G.MiniTrailspace.unhighlight() end
end

H.apply_buffer_mappings = function(buf_id)
  local buf_keymap = function(key, cmd)
    vim.keymap.set('n', key, ('<Cmd>lua %s<CR>'):format(cmd), { buffer = buf_id, nowait = true, silent = true })
  end

  buf_keymap('<CR>', 'MiniStarter.eval_current_item()')

  buf_keymap('<Up>', [[MiniStarter.update_current_item('prev')]])
  buf_keymap('<C-p>', [[MiniStarter.update_current_item('prev')]])
  buf_keymap('<M-k>', [[MiniStarter.update_current_item('prev')]])
  buf_keymap('<Down>', [[MiniStarter.update_current_item('next')]])
  buf_keymap('<C-n>', [[MiniStarter.update_current_item('next')]])
  buf_keymap('<M-j>', [[MiniStarter.update_current_item('next')]])

  -- Make all special symbols to update query
  for _, key in ipairs(vim.split(H.get_config().query_updaters, '')) do
    local key_string = vim.inspect(tostring(key))
    buf_keymap(key, ('MiniStarter.add_to_query(%s)'):format(key_string))
  end

  buf_keymap('<Esc>', [[MiniStarter.set_query('')]])
  buf_keymap('<BS>', 'MiniStarter.add_to_query()')
  buf_keymap('<C-c>', 'MiniStarter.close()')
end

H.add_hl_activity = function(buf_id, query)
  for _, item in ipairs(H.buffer_data[buf_id].items) do
    local l = item._line
    local s = item._start_col
    local e = item._end_col
    if item._active then
      H.buf_hl(buf_id, H.ns.activity, 'MiniStarterQuery', l, s, s + query:len(), 53)
    else
      H.buf_hl(buf_id, H.ns.activity, 'MiniStarterInactive', l, s, e, 53)
    end
  end
end

H.add_hl_current_item = function(buf_id)
  local data = H.buffer_data[buf_id]
  local cur_item = data.items[data.current_item_id]
  H.buf_hl(buf_id, H.ns.current_item, 'MiniStarterCurrent', cur_item._line, cur_item._start_col, cur_item._end_col, 51)
end

-- Predicates -----------------------------------------------------------------
H.is_fun_or_string = function(x, allow_nil)
  if allow_nil == nil then allow_nil = true end
  return (allow_nil and x == nil) or type(x) == 'function' or type(x) == 'string'
end

H.is_item = function(x)
  return type(x) == 'table'
    and H.is_fun_or_string(x['action'], false)
    and type(x['name']) == 'string'
    and type(x['section']) == 'string'
end

H.is_something_shown = function()
  -- Don't open Starter buffer if Neovim is opened to show something. That is
  -- when at least one of the following is true:
  -- - There are files in arguments (like `nvim foo.txt` with new file).
  if vim.fn.argc() > 0 then return true end

  -- - Several buffers are listed (like session with placeholder buffers). That
  --   means unlisted buffers (like from `nvim-tree`) don't affect decision.
  local listed_buffers = vim.tbl_filter(
    function(buf_id) return vim.fn.buflisted(buf_id) == 1 end,
    vim.api.nvim_list_bufs()
  )
  if #listed_buffers > 1 then return true end

  -- - Current buffer is meant to show something else
  if vim.bo.filetype ~= '' then return true end

  -- - Current buffer has any lines (something opened explicitly).
  -- NOTE: Usage of `line2byte(line('$') + 1) < 0` seemed to be fine, but it
  -- doesn't work if some automated changed was made to buffer while leaving it
  -- empty (returns 2 instead of -1). This was also the reason of not being
  -- able to test with child Neovim process from 'tests/helpers'.
  local n_lines = vim.api.nvim_buf_line_count(0)
  if n_lines > 1 then return true end
  local first_line = vim.api.nvim_buf_get_lines(0, 0, 1, true)[1]
  if string.len(first_line) > 0 then return true end

  return false
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.starter) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.set_buf_name = function(buf_id, name) vim.api.nvim_buf_set_name(buf_id, 'ministarter://' .. buf_id .. '/' .. name) end

H.echo = function(msg, is_important)
  if H.get_config().silent then return end

  -- Construct message chunks
  msg = type(msg) == 'string' and { { msg } } or msg
  table.insert(msg, 1, { '(mini.starter) ', 'WarningMsg' })

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

H.message = function(msg) H.echo(msg, true) end

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

H.validate_starter_buf_id = function(buf_id, fun_name, severity)
  local is_starter_buf_id = type(buf_id) == 'number'
    and vim.tbl_contains(vim.tbl_keys(H.buffer_data), buf_id)
    and vim.api.nvim_buf_is_valid(buf_id)
  if is_starter_buf_id then return true end

  local msg = string.format('`buf_id` in `%s` is not an identifier of valid Starter buffer.', fun_name)
  if severity == 'error' then H.error(msg) end

  H.message(msg)
  return false
end

H.eval_fun_or_string = function(x, string_as_cmd)
  if type(x) == 'function' then return x() end
  if type(x) == 'string' then
    if string_as_cmd then
      vim.cmd(x)
    else
      return x
    end
  end
end

-- Use `priority` because of the regression bug (highlights are not stacked
-- properly): https://github.com/neovim/neovim/issues/17358
H.buf_hl = function(buf_id, ns_id, hl_group, line, col_start, col_end, priority)
  local opts = { end_row = line, end_col = col_end, hl_group = hl_group, priority = priority }
  vim.api.nvim_buf_set_extmark(buf_id, ns_id, line, col_start, opts)
end

H.get_buffer_windows = function(buf_id)
  return vim.tbl_filter(
    function(win_id) return vim.api.nvim_win_get_buf(win_id) == buf_id end,
    vim.api.nvim_list_wins()
  )
end

H.unique_nprefix = function(strings)
  -- For every string compute minimum width of unique prefix. NOTE: this can be
  -- done simpler but it would be O(n^2) which *will* have noticeable effect
  -- when there are a) many items and b) some of them are identical and have
  -- big length (like recent files with full paths).

  -- Make copy because it will be modified
  local str_set = vim.deepcopy(strings)
  local res, cur_n = {}, 0
  while vim.tbl_count(str_set) > 0 do
    cur_n = cur_n + 1

    -- `prefix_tbl`: string id's with current prefix
    -- `nowhere_to_go` is `true` if all strings have lengths less than `cur_n`
    local prefix_tbl, nowhere_to_go = {}, true
    for id, s in pairs(str_set) do
      nowhere_to_go = nowhere_to_go and (#s < cur_n)
      local prefix = s:sub(1, cur_n)
      prefix_tbl[prefix] = prefix_tbl[prefix] == nil and {} or prefix_tbl[prefix]
      table.insert(prefix_tbl[prefix], id)
    end

    -- Output for non-unique string is its length
    if nowhere_to_go then
      for k, s in pairs(str_set) do
        res[k] = #s
      end
      break
    end

    for _, keys_with_prefix in pairs(prefix_tbl) do
      -- If prefix is seen only once, it is unique
      if #keys_with_prefix == 1 then
        local k = keys_with_prefix[1]
        -- Use `math.min` to account for empty strings and non-unique ones
        res[k] = math.min(#str_set[k], cur_n)
        -- Remove this string as it already has final nprefix
        str_set[k] = nil
      end
    end
  end

  return res
end

return MiniStarter
