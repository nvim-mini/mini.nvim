--- *mini.animate* Animate common Neovim actions
---
--- MIT License Copyright (c) 2022 Evgeni Chasnovski

--- Features:
--- - Works out of the box with a single `require('mini.animate').setup()`.
---   No extra mappings or commands needed.
---
--- - Animate cursor movement inside same buffer by showing customizable path.
---   See |MiniAnimate.config.cursor| for more details.
---
--- - Animate scrolling with a series of subscrolls ("smooth scrolling").
---   See |MiniAnimate.config.scroll| for more details.
---
--- - Animate window resize by gradually changing sizes of all windows.
---   See |MiniAnimate.config.resize| for more details.
---
--- - Animate window open/close with visually updating floating window.
---   See |MiniAnimate.config.open| and |MiniAnimate.config.close| for more details.
---
--- - Timings for all actions can be customized independently.
---   See |MiniAnimate-timing| for more details.
---
--- - Action animations can be enabled/disabled independently.
---
--- - All animations are asynchronous/non-blocking and trigger a targeted event
---   which can be used to perform actions after animation is done.
---
--- - |MiniAnimate.animate()| function which can be used to perform own animations.
---
--- Notes:
--- - Cursor movement is animated inside same window and buffer, not as cursor
---   moves across the screen.
---
--- - Scroll and resize animations are done with "side effects": they actually
---   change the state of what is animated (window view and sizes
---   respectively). This has a downside of possibly needing extra work to
---   account for asynchronous nature of animation (like adjusting certain
---   mappings, etc.). See |MiniAnimate.config.scroll| and
---   |MiniAnimate.config.resize| for more details.
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.animate').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `MiniAnimate`
--- which you can use for scripting or manually (with `:lua MiniAnimate.*`).
---
--- See |MiniAnimate.config| for available config settings.
---
--- You can override runtime config settings (like `config.modifiers`) locally
--- to buffer inside `vim.b.minianimate_config` which should have same structure
--- as `MiniAnimate.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- # Comparisons ~
---
--- - [Neovide](https://neovide.dev/):
---     - Neovide is a standalone GUI which has more control over its animations.
---       While 'mini.animate' works inside terminal emulator (with all its
---       limitations, like lack of pixel-size control over animations).
---     - Neovide animates cursor movement across screen, while 'mini.animate' -
---       as it moves across same buffer.
---     - Neovide has fixed number of animation effects per action, while
---       'mini.animate' is fully customizable.
---     - 'mini.animate' implements animations for window open/close, while
---       Neovide does not.
--- - [edluffy/specs.nvim](https://github.com/edluffy/specs.nvim):
---     - 'mini.animate' approaches cursor movement visualization via
---       customizable path function (uses extmarks), while 'specs.nvim' can
---       customize within its own visual effects (shading and floating
---       window resizing).
--- - [karb94/neoscroll.nvim](https://github.com/karb94/neoscroll.nvim):
---     - Scroll animation is triggered only inside dedicated mappings.
---       'mini.animate' animates scroll resulting from any window view change.
--- - [anuvyklack/windows.nvim](https://github.com/anuvyklack/windows.nvim):
---     - Resize animation is done only within custom commands and mappings,
---       while 'mini.animate' animates any resize with appropriate values of
---       'winheight' / 'winwidth' and 'winminheight' / 'winminwidth').
---
--- # Highlight groups ~
---
--- - `MiniAnimateCursor` - highlight of cursor during its animated movement.
--- - `MiniAnimateNormalFloat` - highlight of floating window for `open` and
---   `close` animations.
---
--- To change any highlight group, set it directly with |nvim_set_hl()|.
---
--- # Disabling ~
---
--- To disable, set `vim.g.minianimate_disable` (globally) or
--- `vim.b.minianimate_disable` (for a buffer) to `true`. Considering high
--- number of different scenarios and customization intentions, writing exact
--- rules for disabling module's functionality is left to user. See
--- |mini.nvim-disabling-recipes| for common recipes.
---@tag MiniAnimate

---@diagnostic disable:undefined-field

-- Module definition ==========================================================
local MiniAnimate = {}
local H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniAnimate.config|.
---
---@usage >lua
---   require('mini.animate').setup() -- use default config
---   -- OR
---   require('mini.animate').setup({}) -- replace {} with your config table
--- <
MiniAnimate.setup = function(config)
  -- Export module
  _G.MiniAnimate = MiniAnimate

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Define behavior
  H.create_autocommands()
  H.track_scroll_state()

  -- Create default highlighting
  H.create_default_hl()
end

--- Defaults ~
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text # General ~
---
--- - *MiniAnimate-timing* Every animation is a non-blockingly scheduled series of
---   specific actions. They are executed in a sequence of timed steps controlled
---   by `timing` option. It is a callable which, given next and total step numbers,
---   returns wait time (in ms).
---   See |MiniAnimate.gen_timing| for builtin timing functions.
---   See |MiniAnimate.animate()| for more details about animation process.
---
--- - Every animation can be enabled/disabled independently by setting `enable`
---   option to `true`/`false`.
---
--- - *MiniAnimate-done-event* Every animation triggers custom |User| event when it
---   is finished. It is named `MiniAnimateDoneXxx` with `Xxx` replaced by capitalized
---   supported animation action name (like `MiniAnimateDoneCursor`). Use it to
---   schedule some action after certain animation is completed. Alternatively,
---   you can use |MiniAnimate.execute_after()| (usually preferred in mappings).
---
--- - Each animation has its main step generator which defines how particular
---   animation is done. They all are callables which take some input data and
---   return an array of step data. Length of that array determines number of
---   animation steps. Outputs `nil` and empty table result in no animation.
---
--- # Cursor ~
--- *MiniAnimate.config.cursor*
---
--- This animation is triggered for each movement of cursor inside same window
--- and buffer. Its visualization step consists from placing single extmark (see
--- |extmarks|) at certain position. This extmark contains single space and is
--- highlighted with `MiniAnimateCursor` highlight group.
---
--- Exact places of extmark and their number is controlled by `path` option. It
--- is a callable which takes `destination` argument (2d integer point in
--- `(line, col)` coordinates) and returns array of relative to `(0, 0)` places
--- for extmark to be placed. Example:
--- - Input `(2, -3)` means cursor jumped 2 lines forward and 3 columns backward.
--- - Output `{ {0, 0 }, { 0, -1 }, { 0, -2 }, { 0, -3 }, { 1, -3 } }` means
---   that path is first visualized along the initial line and then along final
---   column.
---
--- See |MiniAnimate.gen_path| for builtin path generators.
---
--- Notes:
--- - Input `destination` value is computed ignoring folds. This is by design
---   as it helps better visualize distance between two cursor positions.
--- - Outputs of path generator resulting in a place where extmark can't be
---   placed are silently omitted during animation: this step won't show any
---   visualization.
---
--- Configuration example: >lua
---
---   local animate = require('mini.animate')
---   animate.setup({
---     cursor = {
---       -- Animate for 200 milliseconds with linear easing
---       timing = animate.gen_timing.linear({ duration = 200, unit = 'total' }),
---
---       -- Animate with shortest line for any cursor move
---       path = animate.gen_path.line({
---         predicate = function() return true end,
---       }),
---     }
---   })
--- <
--- After animation is done, `MiniAnimateDoneCursor` event is triggered.
---
--- # Scroll ~
--- *MiniAnimate.config.scroll*
---
--- This animation is triggered for each vertical scroll of current window.
--- Its visualization step consists from performing a small subscroll which all
--- in total will result into needed total scroll.
---
--- Exact subscroll values and their number is controlled by `subscroll` option.
--- It is a callable which takes `total_scroll` argument (single non-negative
--- integer) and returns array of non-negative integers each representing the
--- amount of lines needed to be scrolled inside corresponding step. All
--- subscroll values should sum to input `total_scroll`.
--- Example:
--- - Input `5` means that total scroll consists from 5 lines (either up or down,
---   which doesn't matter).
--- - Output of `{ 1, 1, 1, 1, 1 }` means that there are 5 equal subscrolls.
---
--- See |MiniAnimate.gen_subscroll| for builtin subscroll generators.
---
--- Notes:
--- - Input value of `total_scroll` is computed taking folds into account.
--- - As scroll animation is essentially a precisely scheduled non-blocking
---   subscrolls, this has two important interconnected consequences:
---     - If another scroll is attempted during the animation, it is done based
---       on the **currently visible** window view. Example: if user presses
---       |CTRL-D| and then |CTRL-U| when animation is half done, window will not
---       display the previous view half of 'scroll' above it. This especially
---       affects mouse wheel scrolling, as each its turn results in a new scroll
---       for number of lines defined by 'mousescroll'. Tweak it to your liking.
---     - It breaks the use of several relative scrolling commands in the same
---       command. Use |MiniAnimate.execute_after()| to schedule action after
---       reaching target window view.
---       Example: a useful `nnoremap n nzvzz` mapping (consecutive application
---       of |n|, |zv|, and |zz|) should be expressed in the following way: >lua
---
---         '<Cmd>lua vim.cmd("normal! n"); ' ..
---           'MiniAnimate.execute_after("scroll", "normal! zvzz")<CR>'
--- <
--- - Default timing might conflict with scrolling via holding a key (like `j` or `k`
---   with 'wrap' enabled) due to high key repeat rate: next scroll is done before
---   first step of current one finishes. Resolve this by not scrolling like that
---   or by ensuring maximum value of step duration to be lower than between
---   repeated keys: set timing like `function(_, n) return math.min(250/n, 10) end`
---   or use timing with constant step duration.
---
--- Configuration example: >lua
---
---   local animate = require('mini.animate')
---   animate.setup({
---     scroll = {
---       -- Animate for 200 milliseconds with linear easing
---       timing = animate.gen_timing.linear({ duration = 200, unit = 'total' }),
---
---       -- Animate equally but with at most 120 steps instead of default 60
---       subscroll = animate.gen_subscroll.equal({ max_output_steps = 120 }),
---     }
---   })
--- <
--- After animation is done, `MiniAnimateDoneScroll` event is triggered.
---
--- # Resize ~
--- *MiniAnimate.config.resize*
---
--- This animation is triggered for window resize while having same layout of
--- same windows. For example, it won't trigger when window is opened/closed or
--- after something like |CTRL-W_K|. Its visualization step consists from setting
--- certain sizes to all visible windows (last step being for "true" final sizes).
---
--- Exact window step sizes and their number is controlled by `subresize` option.
--- It is a callable which takes `sizes_from` and `sizes_to` arguments (both
--- tables with window id as keys and dimension table as values) and returns
--- array of same shaped data.
--- Example:
--- - Input: >lua
---
---   -- First
---   { [1000] = {width = 7, height = 5}, [1001] = {width = 7, height = 10} }
---   -- Second
---   { [1000] = {width = 9, height = 5}, [1001] = {width = 5, height = 10} }
---   -- Means window 1000 increased its width by 2 in expense of window 1001
--- <
--- - The following output demonstrates equal resizing: >lua
---
---   {
---     { [1000] = {width = 8, height = 5}, [1001] = {width = 6, height = 10} },
---     { [1000] = {width = 9, height = 5}, [1001] = {width = 5, height = 10} },
---   }
--- <
--- See |MiniAnimate.gen_subresize| for builtin subresize generators.
---
--- Notes:
---
--- - As resize animation is essentially a precisely scheduled non-blocking
---   subresizes, this has two important interconnected consequences:
---     - If another resize is attempted during the animation, it is done based
---       on the **currently visible** window sizes. This might affect relative
---       resizing.
---     - It breaks the use of several relative resizing commands in the same
---       command. Use |MiniAnimate.execute_after()| to schedule action after
---       reaching target window sizes.
---
--- Configuration example: >lua
---
---   local is_many_wins = function(sizes_from, sizes_to)
---     return vim.tbl_count(sizes_from) >= 3
---   end
---   local animate = require('mini.animate')
---   animate.setup({
---     resize = {
---       -- Animate for 200 milliseconds with linear easing
---       timing = animate.gen_timing.linear({ duration = 200, unit = 'total' }),
---
---       -- Animate only if there are at least 3 windows
---       subresize = animate.gen_subscroll.equal({ predicate = is_many_wins }),
---     }
---   })
--- <
--- After animation is done, `MiniAnimateDoneResize` event is triggered.
---
--- # Window open/close ~
--- *MiniAnimate.config.open*
--- *MiniAnimate.config.close*
---
--- These animations are similarly triggered for regular (non-floating) window
--- open/close. Their visualization step consists from drawing empty floating
--- window with customizable config and transparency.
---
--- Exact window visualization characteristics are controlled by `winconfig`
--- and `winblend` options.
---
--- The `winconfig` option is a callable which takes window id (|window-ID|) as
--- input and returns an array of floating window configs (as in `config`
--- argument of |nvim_open_win()|). Its length determines number of animation steps.
--- Example:
--- - The following output results into two animation steps with second being
---   upper left quarter of a first: >lua
---
---   {
---     {
---       row      = 0,        col    = 0,
---       width    = 10,       height = 10,
---       relative = 'editor', anchor = 'NW',   focusable = false,
---       zindex   = 1,        border = 'none', style  = 'minimal',
---     },
---     {
---       row      = 0,        col    = 0,
---       width    = 5,        height = 5,
---       relative = 'editor', anchor = 'NW',   focusable = false,
---       zindex   = 1,        border = 'none', style  = 'minimal',
---     },
---   }
--- <
--- The `winblend` option is similar to `timing` option: it is a callable
--- which, given current and total step numbers, returns value of floating
--- window's 'winblend' option. Note, that it is called for current step (so
--- starts from 0), as opposed to `timing` which is called before step.
--- Example:
--- - Function `function(s, n) return 80 + 20 * s / n end` results in linear
---   transition from `winblend` value of 80 to 100.
---
--- See |MiniAnimate.gen_winconfig| for builtin window config generators.
--- See |MiniAnimate.gen_winblend| for builtin window transparency generators.
---
--- Configuration example: >lua
---
---   local animate = require('mini.animate')
---   animate.setup({
---     open = {
---       -- Animate for 400 milliseconds with linear easing
---       timing = animate.gen_timing.linear({ duration = 400, unit = 'total' }),
---
---       -- Animate with wiping from nearest edge instead of default static one
---       winconfig = animate.gen_winconfig.wipe({ direction = 'from_edge' }),
---
---       -- Make bigger windows more transparent
---       winblend = animate.gen_winblend.linear({ from = 80, to = 100 }),
---     },
---
---     close = {
---       -- Animate for 400 milliseconds with linear easing
---       timing = animate.gen_timing.linear({ duration = 400, unit = 'total' }),
---
---       -- Animate with wiping to nearest edge instead of default static one
---       winconfig = animate.gen_winconfig.wipe({ direction = 'to_edge' }),
---
---       -- Make bigger windows more transparent
---       winblend = animate.gen_winblend.linear({ from = 100, to = 80 }),
---     },
---   })
--- <
--- After animation is done, `MiniAnimateDoneOpen` or `MiniAnimateDoneClose`
--- event is triggered for `open` and `close` animation respectively.
MiniAnimate.config = {
  -- Cursor path
  cursor = {
    -- Whether to enable this animation
    enable = true,

    -- Timing of animation (how steps will progress in time)
    --minidoc_replace_start timing = --<function: linear animation, total 250ms>,
    timing = function(_, n) return 250 / n end,
    --minidoc_replace_end

    -- Path generator for visualized cursor movement
    --minidoc_replace_start path = --<function: implements shortest line path no longer than 1000>,
    path = function(destination)
      return H.path_line(destination, { predicate = H.default_path_predicate, max_output_steps = 1000 })
    end,
    --minidoc_replace_end
  },

  -- Vertical scroll
  scroll = {
    -- Whether to enable this animation
    enable = true,

    -- Timing of animation (how steps will progress in time)
    --minidoc_replace_start timing = --<function: linear animation, total 250ms>,
    timing = function(_, n) return 250 / n end,
    --minidoc_replace_end

    -- Subscroll generator based on total scroll
    --minidoc_replace_start subscroll = --<function: implements equal scroll with at most 60 steps>,
    subscroll = function(total_scroll)
      return H.subscroll_equal(total_scroll, { predicate = H.default_subscroll_predicate, max_output_steps = 60 })
    end,
    --minidoc_replace_end
  },

  -- Window resize
  resize = {
    -- Whether to enable this animation
    enable = true,

    -- Timing of animation (how steps will progress in time)
    --minidoc_replace_start timing = --<function: linear animation, total 250ms>,
    timing = function(_, n) return 250 / n end,
    --minidoc_replace_end

    -- Subresize generator for all steps of resize animations
    --minidoc_replace_start subresize = --<function: implements equal linear steps>,
    subresize = function(sizes_from, sizes_to)
      return H.subresize_equal(sizes_from, sizes_to, { predicate = H.default_subresize_predicate })
    end,
    --minidoc_replace_end
  },

  -- Window open
  open = {
    -- Whether to enable this animation
    enable = true,

    -- Timing of animation (how steps will progress in time)
    --minidoc_replace_start timing = --<function: linear animation, total 250ms>,
    timing = function(_, n) return 250 / n end,
    --minidoc_replace_end

    -- Floating window config generator visualizing specific window
    --minidoc_replace_start winconfig = --<function: implements static window for 25 steps>,
    winconfig = function(win_id)
      return H.winconfig_static(win_id, { predicate = H.default_winconfig_predicate, n_steps = 25 })
    end,
    --minidoc_replace_end

    -- 'winblend' (window transparency) generator for floating window
    --minidoc_replace_start winblend = --<function: implements equal linear steps from 80 to 100>,
    winblend = function(s, n) return 80 + 20 * (s / n) end,
    --minidoc_replace_end
  },

  -- Window close
  close = {
    -- Whether to enable this animation
    enable = true,

    -- Timing of animation (how steps will progress in time)
    --minidoc_replace_start timing = --<function: linear animation, total 250ms>,
    timing = function(_, n) return 250 / n end,
    --minidoc_replace_end

    -- Floating window config generator visualizing specific window
    --minidoc_replace_start winconfig = --<function: implements static window for 25 steps>,
    winconfig = function(win_id)
      return H.winconfig_static(win_id, { predicate = H.default_winconfig_predicate, n_steps = 25 })
    end,
    --minidoc_replace_end

    -- 'winblend' (window transparency) generator for floating window
    --minidoc_replace_start winblend = --<function: implements equal linear steps from 80 to 100>,
    winblend = function(s, n) return 80 + 20 * (s / n) end,
    --minidoc_replace_end
  },
}
--minidoc_afterlines_end

-- Module functionality =======================================================
--- Check animation activity
---
---@param animation_type string One of supported animation types
---   (entries of |MiniAnimate.config|, like `'cursor'`, etc.).
---
---@return boolean Whether the animation is currently active.
MiniAnimate.is_active = function(animation_type)
  local res = H.cache[animation_type .. '_is_active']
  if res == nil then H.error('Wrong `animation_type` for `is_active()`.') end
  return res
end

--- Execute action after some animation is done
---
--- Execute action immediately if animation is not active (checked with
--- |MiniAnimate.is_active()|). Else, schedule its execution until after
--- animation is done (on corresponding "done event", see
--- |MiniAnimate-done-event|).
---
--- Mostly meant to be used inside mappings.
---
--- Example:
---
--- A useful `nnoremap n nzvzz` mapping (consecutive application of |n|, |zv|, and |zz|)
--- should be expressed in the following way: >lua
---
---   '<Cmd>lua vim.cmd("normal! n"); ' ..
---     'MiniAnimate.execute_after("scroll", "normal! zvzz")<CR>'
--- <
---@param animation_type string One of supported animation types
---   (as in |MiniAnimate.is_active()|).
---@param action string|function Action to be executed. If string, executed as
---   command (via |vim.cmd()|).
MiniAnimate.execute_after = function(animation_type, action)
  local event_name = H.animation_done_events[animation_type]
  if event_name == nil then H.error('Wrong `animation_type` for `execute_after`.') end

  local callable = action
  if type(callable) == 'string' then callable = function() vim.cmd(action) end end
  if not vim.is_callable(callable) then
    H.error('Argument `action` of `execute_after()` should be string or callable.')
  end

  -- Schedule conditional action execution to allow animation to actually take
  -- effect. This helps creating more universal mappings, because some commands
  -- (like `n`) not always result into scrolling.
  vim.schedule(function()
    if MiniAnimate.is_active(animation_type) then
      vim.api.nvim_create_autocmd('User', { pattern = event_name, once = true, callback = callable })
    else
      callable()
    end
  end)
end

-- Action (step 0) - wait (step 1) - action (step 1) - ...
-- `step_action` should return `false` or `nil` (equivalent to not returning anything explicitly) in order to stop animation.
--- Animate action
---
--- This is equivalent to asynchronous execution of the following algorithm:
--- - Call `step_action(0)` immediately after calling this function. Stop if
---   action returned `false` or `nil`.
--- - Wait `step_timing(1)` milliseconds.
--- - Call `step_action(1)`. Stop if it returned `false` or `nil`.
--- - Wait `step_timing(2)` milliseconds.
--- - Call `step_action(2)`. Stop if it returned `false` or `nil`.
--- - ...
---
--- Notes:
--- - Animation is also stopped on action error or if maximum number of steps
---   is reached.
--- - Asynchronous execution is done with |uv.new_timer()|. It only allows
---   integer parts as repeat value. This has several implications:
---     - Outputs of `step_timing()` are accumulated in order to preserve total
---       execution time.
---     - Any wait time less than 1 ms means that action will be executed
---       immediately.
---
---@param step_action function|table Callable which takes `step` (integer 0, 1, 2,
---   etc. indicating current step) and executes some action. Its return value
---   defines when animation should stop: values `false` and `nil` (equivalent
---   to no explicit return) stop animation timer; any other continues it.
---@param step_timing function|table Callable which takes `step` (integer 1, 2, etc.
---   indicating next step) and returns how many milliseconds to wait before
---   executing this step action.
---@param opts table|nil Options. Possible fields:
---   - <max_steps> - Maximum value of allowed step to execute. Default: 10000000.
MiniAnimate.animate = function(step_action, step_timing, opts)
  opts = vim.tbl_deep_extend('force', { max_steps = 10000000 }, opts or {})

  local step, max_steps = 0, opts.max_steps
  local timer, wait_time = vim.uv.new_timer(), 0

  local draw_step
  draw_step = vim.schedule_wrap(function()
    local ok, should_continue = pcall(step_action, step)
    if not (ok and should_continue and step < max_steps) then
      timer:stop()
      return
    end

    step = step + 1
    wait_time = wait_time + step_timing(step)

    -- Repeat value of `timer` seems to be rounded down to milliseconds. This
    -- means that values less than 1 will lead to timer stop repeating. Instead
    -- call next step function directly.
    if wait_time < 1 then
      timer:set_repeat(0)
      -- Use `return` to make this proper "tail call"
      return draw_step()
    else
      timer:set_repeat(wait_time)
      wait_time = wait_time - timer:get_repeat()
      timer:again()
    end
  end)

  -- Start non-repeating timer without callback execution
  timer:start(10000000, 0, draw_step)

  -- Draw step zero (at origin) immediately
  draw_step()
end

--- Generate animation timing
---
--- Each field corresponds to one family of progression which can be customized
--- further by supplying appropriate arguments.
---
--- This is a table with function elements. Call to actually get timing function.
---
--- Example: >lua
---
---   local animate = require('mini.animate')
---   animate.setup({
---     cursor = {
---       timing = animate.gen_timing.linear({ duration = 100, unit = 'total' })
---     },
---   })
--- <
---@seealso |MiniIndentscope.gen_animation| for similar concept in 'mini.indentscope'.
MiniAnimate.gen_timing = {}

---@alias __animate_timing_opts table|nil Options that control progression. Possible keys:
---   - <easing> `(string)` - a subtype of progression. One of "in"
---     (accelerating from zero speed), "out" (decelerating to zero speed),
---     "in-out" (default; accelerating halfway, decelerating after).
---   - <duration> `(number)` - duration (in ms) of a unit. Default: 20.
---   - <unit> `(string)` - which unit's duration `opts.duration` controls. One
---     of "step" (default; ensures average duration of step to be `opts.duration`)
---     or "total" (ensures fixed total duration regardless of scope's range).
---@alias __animate_timing_return function Timing function (see |MiniAnimate-timing|).

--- Generate timing with no animation
---
--- Show final result immediately. Usually better to use `enable` field in `config`
--- if you want to disable animation.
MiniAnimate.gen_timing.none = function()
  return function() return 0 end
end

--- Generate timing with linear progression
---
---@param opts __animate_timing_opts
---
---@return __animate_timing_return
MiniAnimate.gen_timing.linear = function(opts) return H.timing_arithmetic(0, H.normalize_timing_opts(opts)) end

--- Generate timing with quadratic progression
---
---@param opts __animate_timing_opts
---
---@return __animate_timing_return
MiniAnimate.gen_timing.quadratic = function(opts) return H.timing_arithmetic(1, H.normalize_timing_opts(opts)) end

--- Generate timing with cubic progression
---
---@param opts __animate_timing_opts
---
---@return __animate_timing_return
MiniAnimate.gen_timing.cubic = function(opts) return H.timing_arithmetic(2, H.normalize_timing_opts(opts)) end

--- Generate timing with quartic progression
---
---@param opts __animate_timing_opts
---
---@return __animate_timing_return
MiniAnimate.gen_timing.quartic = function(opts) return H.timing_arithmetic(3, H.normalize_timing_opts(opts)) end

--- Generate timing with exponential progression
---
---@param opts __animate_timing_opts
---
---@return __animate_timing_return
MiniAnimate.gen_timing.exponential = function(opts) return H.timing_geometrical(H.normalize_timing_opts(opts)) end

--- Generate cursor animation path
---
--- For more information see |MiniAnimate.config.cursor|.
---
--- This is a table with function elements. Call to actually get generator.
---
--- Example: >lua
---
---   local animate = require('mini.animate')
---   animate.setup({
---     cursor = {
---       -- Animate with line-column angle instead of shortest line
---       path = animate.gen_path.angle(),
---     }
---   })
--- <
MiniAnimate.gen_path = {}

---@alias __animate_path_opts_common table|nil Options that control generator. Possible keys:
---   - <predicate> `(function)` - a callable which takes `destination` as input and
---     returns boolean value indicating whether animation should be done.
---     Default: `false` if `destination` is within one line of origin (reduces
---     flickering), `true` otherwise.
---@alias __animate_path_return function Path function (see |MiniAnimate.config.cursor|).

--- Generate path as shortest line
---
---@param opts __animate_path_opts_common
---   - <max_output_steps> `(number)` - maximum number of steps in output.
---     Default: 1000.
---
---@return __animate_path_return
MiniAnimate.gen_path.line = function(opts)
  opts = vim.tbl_deep_extend('force', { predicate = H.default_path_predicate, max_output_steps = 1000 }, opts or {})

  return function(destination) return H.path_line(destination, opts) end
end

--- Generate path as line/column angle
---
---@param opts __animate_path_opts_common
---   - <max_output_steps> `(number)` - maximum number of steps per side in output.
---     Default: 1000.
---   - <first_direction> `(string)` - one of `"horizontal"` (default; animates
---     across initial line first) or `"vertical"` (animates across initial
---     column first).
---
---@return __animate_path_return
MiniAnimate.gen_path.angle = function(opts)
  local default_opts = { predicate = H.default_path_predicate, max_output_steps = 1000, first_direction = 'horizontal' }
  opts = vim.tbl_deep_extend('force', default_opts, opts or {})

  local append_horizontal = function(res, dest_col, const_line)
    if dest_col == 0 then return end
    local n_steps = math.min(math.abs(dest_col), opts.max_output_steps)
    local coef = dest_col / n_steps
    for i = 0, n_steps - 1 do
      table.insert(res, { const_line, H.round(coef * i) })
    end
  end

  local append_vertical = function(res, dest_line, const_col)
    if dest_line == 0 then return end
    local n_steps = math.min(math.abs(dest_line), opts.max_output_steps)
    local coef = dest_line / n_steps
    for i = 0, n_steps - 1 do
      table.insert(res, { H.round(coef * i), const_col })
    end
  end

  return function(destination)
    -- Don't animate in case of false predicate
    if not opts.predicate(destination) then return {} end

    -- Travel along horizontal/vertical lines
    local res = {}
    if opts.first_direction == 'horizontal' then
      append_horizontal(res, destination[2], 0)
      append_vertical(res, destination[1], destination[2])
    else
      append_vertical(res, destination[1], 0)
      append_horizontal(res, destination[2], destination[1])
    end

    return res
  end
end

--- Generate path as closing walls at final position
---
---@param opts __animate_path_opts_common
---   - <width> `(number)` - initial width of left and right walls. Default: 10.
---
---@return __animate_path_return
MiniAnimate.gen_path.walls = function(opts)
  opts = opts or {}
  local predicate = opts.predicate or H.default_path_predicate
  local width = opts.width or 10

  return function(destination)
    -- Don't animate in case of false predicate
    if not predicate(destination) then return {} end

    -- Don't animate in case of no movement
    if destination[1] == 0 and destination[2] == 0 then return {} end

    local dest_line, dest_col = destination[1], destination[2]
    local res = {}
    for i = width, 1, -1 do
      table.insert(res, { dest_line, dest_col + i })
      table.insert(res, { dest_line, dest_col - i })
    end
    return res
  end
end

--- Generate path as diminishing spiral at final position
---
---@param opts __animate_path_opts_common
---   - <width> `(number)` - initial width of spiral. Default: 2.
---
---@return __animate_path_return
MiniAnimate.gen_path.spiral = function(opts)
  opts = opts or {}
  local predicate = opts.predicate or H.default_path_predicate
  local width = opts.width or 2

  local add_layer = function(res, w, destination)
    local dest_line, dest_col = destination[1], destination[2]
    --stylua: ignore start
    for j = -w, w-1 do table.insert(res, { dest_line - w, dest_col + j }) end
    for i = -w, w-1 do table.insert(res, { dest_line + i, dest_col + w }) end
    for j = -w, w-1 do table.insert(res, { dest_line + w, dest_col - j }) end
    for i = -w, w-1 do table.insert(res, { dest_line - i, dest_col - w }) end
    --stylua: ignore end
  end

  return function(destination)
    -- Don't animate in case of false predicate
    if not predicate(destination) then return {} end

    -- Don't animate in case of no movement
    if destination[1] == 0 and destination[2] == 0 then return {} end

    local res = {}
    for w = width, 1, -1 do
      add_layer(res, w, destination)
    end
    return res
  end
end

--- Generate scroll animation subscroll
---
--- For more information see |MiniAnimate.config.scroll|.
---
--- This is a table with function elements. Call to actually get generator.
---
--- Example: >lua
---
---   local animate = require('mini.animate')
---   animate.setup({
---     scroll = {
---       -- Animate equally but with 120 maximum steps instead of default 60
---       subscroll = animate.gen_subscroll.equal({ max_output_steps = 120 }),
---     }
---   })
--- <
MiniAnimate.gen_subscroll = {}

--- Generate subscroll with equal steps
---
---@param opts table|nil Options that control generator. Possible keys:
---   - <predicate> `(function)` - a callable which takes `total_scroll` as
---     input and returns boolean value indicating whether animation should be
---     done. Default: `false` if `total_scroll` is 1 or less (reduces
---     unnecessary waiting), `true` otherwise.
---   - <max_output_steps> `(number)` - maximum number of subscroll steps in output.
---     Adjust this to reduce computations in expense of reduced smoothness.
---     Default: 60.
---
---@return function Subscroll function (see |MiniAnimate.config.scroll|).
MiniAnimate.gen_subscroll.equal = function(opts)
  opts = vim.tbl_deep_extend('force', { predicate = H.default_subscroll_predicate, max_output_steps = 60 }, opts or {})

  return function(total_scroll) return H.subscroll_equal(total_scroll, opts) end
end

--- Generate resize animation subresize
---
--- For more information see |MiniAnimate.config.resize|.
---
--- This is a table with function elements. Call to actually get generator.
---
--- Example: >lua
---
---   local is_many_wins = function(sizes_from, sizes_to)
---     return vim.tbl_count(sizes_from) >= 3
---   end
---   local animate = require('mini.animate')
---   animate.setup({
---     resize = {
---       -- Animate only if there are at least 3 windows
---       subresize = animate.gen_subresize.equal({ predicate = is_many_wins }),
---     }
---   })
--- <
MiniAnimate.gen_subresize = {}

--- Generate subresize with equal steps
---
---@param opts table|nil Options that control generator. Possible keys:
---   - <predicate> `(function)` - a callable which takes `sizes_from` and
---     `sizes_to` as input and returns boolean value indicating whether
---     animation should be done. Default: always `true`.
---
---@return function Subresize function (see |MiniAnimate.config.resize|).
MiniAnimate.gen_subresize.equal = function(opts)
  opts = vim.tbl_deep_extend('force', { predicate = H.default_subresize_predicate }, opts or {})

  return function(sizes_from, sizes_to) return H.subresize_equal(sizes_from, sizes_to, opts) end
end

--- Generate open/close animation winconfig
---
--- For more information see |MiniAnimate.config.open| or |MiniAnimate.config.close|.
---
--- This is a table with function elements. Call to actually get generator.
---
--- Example: >lua
---
---   local is_not_single_window = function(win_id)
---     local tabpage_id = vim.api.nvim_win_get_tabpage(win_id)
---     return #vim.api.nvim_tabpage_list_wins(tabpage_id) > 1
---   end
---   local animate = require('mini.animate')
---   animate.setup({
---     open = {
---       -- Animate with wiping from nearest edge instead of default static one
---       -- and only if it is not a single window in tabpage
---       winconfig = animate.gen_winconfig.wipe({
---         predicate = is_not_single_window,
---         direction = 'from_edge',
---       }),
---     },
---     close = {
---       -- Animate with wiping to nearest edge instead of default static one
---       -- and only if it is not a single window in tabpage
---       winconfig = animate.gen_winconfig.wipe({
---         predicate = is_not_single_window,
---         direction = 'to_edge',
---       }),
---     },
---   })
--- <
MiniAnimate.gen_winconfig = {}

---@alias __animate_winconfig_opts_common table|nil Options that control generator. Possible keys:
---   - <predicate> `(function)` - a callable which takes `win_id` as input and
---     returns boolean value indicating whether animation should be done.
---     Default: always `true`.
---@alias __animate_winconfig_return function Winconfig function (see |MiniAnimate.config.open|
---   or |MiniAnimate.config.close|).

--- Generate winconfig for static floating window
---
--- This will result into floating window statically covering whole target
--- window.
---
---@param opts __animate_winconfig_opts_common
---   - <n_steps> `(number)` - number of output steps, all with same config.
---     Useful to tweak smoothness of transparency animation (done inside
---     `winblend` config option). Default: 25.
---
---@return __animate_winconfig_return
MiniAnimate.gen_winconfig.static = function(opts)
  opts = vim.tbl_deep_extend('force', { predicate = H.default_winconfig_predicate, n_steps = 25 }, opts or {})

  return function(win_id) return H.winconfig_static(win_id, opts) end
end

--- Generate winconfig for center-focused animated floating window
---
--- This will result into floating window growing from or shrinking to the
--- target window center.
---
---@param opts __animate_winconfig_opts_common
---   - <direction> `(string)` - one of `"to_center"` (default; window will
---     shrink from full coverage to center) or `"from_center"` (window will
---     grow from center to full coverage).
---
---@return __animate_winconfig_return
MiniAnimate.gen_winconfig.center = function(opts)
  opts = opts or {}
  local predicate = opts.predicate or H.default_winconfig_predicate
  local direction = opts.direction or 'to_center'

  return function(win_id)
    -- Don't animate in case of false predicate
    if not predicate(win_id) then return {} end

    local pos = vim.fn.win_screenpos(win_id)
    local row, col = pos[1] - 1, pos[2] - 1
    local height, width = vim.api.nvim_win_get_height(win_id), vim.api.nvim_win_get_width(win_id)

    local n_steps = math.max(height, width)
    local res = {}
    -- Progression should be between fully covering target window and minimal
    -- dimensions in target window center.
    for i = 1, n_steps do
      local coef = (i - 1) / n_steps

      -- Reverse output if progression is from center
      local res_ind = direction == 'to_center' and i or (n_steps - i + 1)

      --stylua: ignore
      res[res_ind] = {
        relative  = 'editor',
        anchor    = 'NW',
        row       = H.round(row + 0.5 * coef * height),
        col       = H.round(col + 0.5 * coef * width),
        width     = math.ceil((1 - coef) * width),
        height    = math.ceil((1 - coef) * height),
        focusable = false,
        zindex    = 1,
        border    = 'none',
        style     = 'minimal',
      }
    end

    return res
  end
end

--- Generate winconfig for wiping animated floating window
---
--- This will result into floating window growing from or shrinking to the
--- nearest edge. This also takes into account the split type of target window:
--- vertically split window will progress towards vertical edge; horizontally -
--- towards horizontal.
---
---@param opts __animate_winconfig_opts_common
---   - <direction> `(string)` - one of `"to_edge"` (default; window will
---     shrink from full coverage to nearest edge) or `"from_edge"` (window
---     will grow from edge to full coverage).
---
---@return __animate_winconfig_return
MiniAnimate.gen_winconfig.wipe = function(opts)
  opts = opts or {}
  local predicate = opts.predicate or H.default_winconfig_predicate
  local direction = opts.direction or 'to_edge'

  return function(win_id)
    -- Don't animate in case of false predicate
    if not predicate(win_id) then return {} end

    -- Get window data
    local win_pos = vim.fn.win_screenpos(win_id)
    local top_row, left_col = win_pos[1], win_pos[2]
    local win_height, win_width = vim.api.nvim_win_get_height(win_id), vim.api.nvim_win_get_width(win_id)

    -- Compute progression data
    local cur_row, cur_col = top_row, left_col
    local cur_width, cur_height = win_width, win_height

    local increment_row, increment_col, increment_height, increment_width
    local n_steps

    local win_container = H.get_window_parent_container(win_id)
    --stylua: ignore
    if win_container == 'col' then
      -- Determine closest top/bottom screen edge and progress to it
      local bottom_row = top_row + win_height - 1
      local is_top_edge_closer = top_row < (vim.o.lines - bottom_row + 1)

      increment_row,   increment_col    = (is_top_edge_closer and 0 or 1), 0
      increment_width, increment_height = 0,                               -1
      n_steps = win_height
    else
      -- Determine closest left/right screen edge and progress to it
      local right_col = left_col + win_width - 1
      local is_left_edge_closer = left_col < (vim.o.columns - right_col + 1)

      increment_row,   increment_col    =  0, (is_left_edge_closer and 0 or 1)
      increment_width, increment_height = -1, 0
      n_steps = win_width
    end

    -- Make step configs
    local res = {}
    for i = 1, n_steps do
      -- Reverse output if progression is from edge
      local res_ind = direction == 'to_edge' and i or (n_steps - i + 1)
      res[res_ind] = {
        relative = 'editor',
        anchor = 'NW',
        row = cur_row - 1,
        col = cur_col - 1,
        width = cur_width,
        height = cur_height,
        focusable = false,
        zindex = 1,
        border = 'none',
        style = 'minimal',
      }
      cur_row = cur_row + increment_row
      cur_col = cur_col + increment_col
      cur_height = cur_height + increment_height
      cur_width = cur_width + increment_width
    end
    return res
  end
end

--- Generate open/close animation `winblend` progression
---
--- For more information see |MiniAnimate.config.open| or |MiniAnimate.config.close|.
---
--- This is a table with function elements. Call to actually get transparency
--- function.
---
--- Example: >lua
---
---   local animate = require('mini.animate')
---   animate.setup({
---     open = {
---       -- Change transparency from 60 to 80 instead of default 80 to 100
---       winblend = animate.gen_winblend.linear({ from = 60, to = 80 }),
---     },
---     close = {
---       -- Change transparency from 60 to 80 instead of default 80 to 100
---       winblend = animate.gen_winblend.linear({ from = 60, to = 80 }),
---     },
---   })
--- <
MiniAnimate.gen_winblend = {}

--- Generate linear `winblend` progression
---
---@param opts table|nil Options that control generator. Possible keys:
---   - <from> `(number)` - initial value of 'winblend'.
---   - <to> `(number)` - final value of 'winblend'.
---
---@return function Winblend function (see |MiniAnimate.config.open|
---   or |MiniAnimate.config.close|).
MiniAnimate.gen_winblend.linear = function(opts)
  opts = opts or {}
  local from = opts.from or 80
  local to = opts.to or 100
  local diff = to - from

  return function(s, n) return from + (s / n) * diff end
end

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniAnimate.config)

-- Cache for various operations
H.cache = {
  -- Cursor move animation data
  cursor_event_id = 0,
  cursor_is_active = false,
  cursor_state = { buf_id = nil, pos = {} },

  -- Scroll animation data
  scroll_event_id = 0,
  scroll_is_active = false,
  scroll_state = { buf_id = nil, win_id = nil, view = {}, cursor = {} },

  -- Resize animation data
  resize_event_id = 0,
  resize_is_active = false,
  resize_state = { layout = {}, sizes = {}, views = {} },

  -- Window open animation data
  open_event_id = 0,
  open_is_active = false,
  open_active_windows = {},

  -- Window close animation data
  close_event_id = 0,
  close_is_active = false,
  close_active_windows = {},
}

-- Namespaces for module operations
H.ns_id = {
  -- Extmarks used to show cursor path
  cursor = vim.api.nvim_create_namespace('MiniAnimateCursor'),
}

-- Identifier of empty buffer used inside open/close animations
H.empty_buf_id = nil

-- Names of `User` events triggered after certain type of animation is done
H.animation_done_events = {
  cursor = 'MiniAnimateDoneCursor',
  scroll = 'MiniAnimateDoneScroll',
  resize = 'MiniAnimateDoneResize',
  open = 'MiniAnimateDoneOpen',
  close = 'MiniAnimateDoneClose',
}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  H.check_type('cursor', config.cursor, 'table')
  H.check_type('cursor.enable', config.cursor.enable, 'boolean')
  H.check_type('cursor.timing', config.cursor.timing, 'callable')
  H.check_type('cursor.path', config.cursor.path, 'callable')

  H.check_type('scroll', config.scroll, 'table')
  H.check_type('scroll.enable', config.scroll.enable, 'boolean')
  H.check_type('scroll.timing', config.scroll.timing, 'callable')
  H.check_type('scroll.subscroll', config.scroll.subscroll, 'callable')

  H.check_type('resize', config.resize, 'table')
  H.check_type('resize.enable', config.resize.enable, 'boolean')
  H.check_type('resize.timing', config.resize.timing, 'callable')
  H.check_type('resize.subresize', config.resize.subresize, 'callable')

  H.check_type('open', config.open, 'table')
  H.check_type('open.enable', config.open.enable, 'boolean')
  H.check_type('open.timing', config.open.timing, 'callable')
  H.check_type('open.winconfig', config.open.winconfig, 'callable')
  H.check_type('open.winblend', config.open.winblend, 'callable')

  H.check_type('close', config.close, 'table')
  H.check_type('close.enable', config.close.enable, 'boolean')
  H.check_type('close.timing', config.close.timing, 'callable')
  H.check_type('close.winconfig', config.close.winconfig, 'callable')
  H.check_type('close.winblend', config.close.winblend, 'callable')

  return config
end

H.apply_config = function(config) MiniAnimate.config = config end

H.create_autocommands = function()
  local gr = vim.api.nvim_create_augroup('MiniAnimate', {})

  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = gr, pattern = pattern, callback = callback, desc = desc })
  end

  au('CursorMoved', '*', H.auto_cursor, 'Animate cursor')

  au('WinScrolled', '*', function()
    -- Inside `WinScrolled` first animate resize before scroll to avoid flicker
    H.auto_resize()
    H.auto_scroll()
  end, 'Animate resize and animate scroll')
  -- Track scroll state on buffer and window enter to animate its first scroll.
  -- Use `vim.schedule_wrap()` to allow other immediate commands to change view
  -- (like builtin cursor center on buffer change) to avoid unnecessary
  -- animated scroll.
  au({ 'BufEnter', 'WinEnter' }, '*', vim.schedule_wrap(H.track_scroll_state), 'Track scroll state')
  -- Track immediately scroll state after leaving terminal mode. Otherwise it
  -- will lead to scroll animation starting at latest non-Terminal mode view.
  au('TermLeave', '*', H.track_scroll_state, 'Track scroll state')
  -- Track scroll state (partially) on every cursor move to keep cursor
  -- position up to date. This enables visually better cursor positioning
  -- during scroll animation (convex progression from start cursor position to
  -- end). Use `vim.schedule()` to make it affect state only after scroll is
  -- done and cursor is already in correct final position.
  au('CursorMoved', '*', vim.schedule_wrap(H.track_scroll_state_partial), 'Track partial scroll state')
  au('CmdlineLeave', '*', H.on_cmdline_leave, 'On CmdlineLeave')

  -- Use `vim.schedule_wrap()` animation to get a window data used for
  -- displaying (and not one after just opening). Useful for 'nvim-tree'.
  au('WinNew', '*', vim.schedule_wrap(function() H.auto_openclose('open') end), 'Animate window open')

  au('WinClosed', '*', function() H.auto_openclose('close') end, 'Animate window close')

  au('ColorScheme', '*', H.create_default_hl, 'Ensure colors')
end

H.create_default_hl = function()
  vim.api.nvim_set_hl(0, 'MiniAnimateCursor', { default = true, reverse = true, nocombine = true })
  vim.api.nvim_set_hl(0, 'MiniAnimateNormalFloat', { default = true, link = 'NormalFloat' })
end

H.is_disabled = function() return vim.g.minianimate_disable == true or vim.b.minianimate_disable == true end

H.get_config = function(config)
  return vim.tbl_deep_extend('force', MiniAnimate.config, vim.b.minianimate_config or {}, config or {})
end

-- Autocommands ---------------------------------------------------------------
H.auto_cursor = function()
  -- Don't animate if disabled
  local cursor_config = H.get_config().cursor
  if not cursor_config.enable or H.is_disabled() then
    -- Reset state to not use an outdated one if enabled again
    H.cache.cursor_state = { buf_id = nil, pos = {} }
    return
  end

  -- Don't animate if inside scroll animation
  if H.cache.scroll_is_active then return end

  -- Update necessary information. NOTE: update state only on `CursorMoved` and
  -- not inside every animation step (like in scroll animation) for performance
  -- reasons: cursor movement is much more common action than scrolling.
  local prev_state, new_state = H.cache.cursor_state, H.get_cursor_state()
  H.cache.cursor_state = new_state
  H.cache.cursor_event_id = H.cache.cursor_event_id + 1

  -- Don't animate if changed buffer
  if new_state.buf_id ~= prev_state.buf_id then return end

  -- Make animation step data and possibly animate
  local animate_step = H.make_cursor_step(prev_state, new_state, cursor_config)
  if not animate_step then return end

  H.start_cursor()
  MiniAnimate.animate(animate_step.step_action, animate_step.step_timing)
end

H.auto_resize = function()
  -- Don't animate if disabled
  local resize_config = H.get_config().resize
  if not resize_config.enable or H.is_disabled() then
    -- Reset state to not use an outdated one if enabled again
    H.cache.resize_state = { layout = {}, sizes = {}, views = {} }
    return
  end

  -- Don't animate if inside scroll animation. This reduces computations and
  -- occasional flickering.
  if H.cache.scroll_is_active then return end

  -- Update state. This also ensures that window views are up to date.
  local prev_state, new_state = H.cache.resize_state, H.get_resize_state()
  H.cache.resize_state = new_state

  -- Don't animate if there is nothing to animate (should be same layout but
  -- different sizes). This also stops triggering animation on window scrolls.
  local same_state = H.is_equal_resize_state(prev_state, new_state)
  if not (same_state.layout and not same_state.sizes) then return end

  -- Register new event only in case there is something to animate
  H.cache.resize_event_id = H.cache.resize_event_id + 1

  -- Make animation step data and possibly animate
  local animate_step = H.make_resize_step(prev_state, new_state, resize_config)
  if not animate_step then return end

  H.start_resize(prev_state)
  MiniAnimate.animate(animate_step.step_action, animate_step.step_timing)
end

H.auto_scroll = function()
  -- Don't animate if disabled
  local scroll_config = H.get_config().scroll
  if not scroll_config.enable or H.is_disabled() then
    -- Reset state to not use an outdated one if enabled again
    H.cache.scroll_state = { buf_id = nil, win_id = nil, view = {}, cursor = {} }
    return
  end

  -- Get states
  local prev_state, new_state = H.cache.scroll_state, H.get_scroll_state()

  -- Don't animate if nothing to animate. Mostly used to distinguish
  -- `WinScrolled` resulting from module animation from the other ones.
  local is_same_bufwin = new_state.buf_id == prev_state.buf_id and new_state.win_id == prev_state.win_id
  local is_same_topline = new_state.view.topline == prev_state.view.topline
  if is_same_topline and is_same_bufwin then return end

  -- Update necessary information
  H.cache.scroll_state = new_state
  H.cache.scroll_event_id = H.cache.scroll_event_id + 1

  -- Don't animate if changed buffer or window
  if not is_same_bufwin then return end

  -- Don't animate if inside resize animation. This reduces computations and
  -- occasional flickering.
  if H.cache.resize_is_active then return end

  -- Make animation step data and possibly animate
  local animate_step = H.make_scroll_step(prev_state, new_state, scroll_config)
  if not animate_step then return end

  H.start_scroll(prev_state)
  MiniAnimate.animate(animate_step.step_action, animate_step.step_timing)
end

H.track_scroll_state = function() H.cache.scroll_state = H.get_scroll_state() end

H.track_scroll_state_partial = function()
  -- This not only improves computation load, but seems to be crucial for
  -- a proper state tracking
  if H.cache.scroll_is_active then return end

  H.cache.scroll_state.cursor = { line = vim.fn.line('.'), virtcol = vim.fn.virtcol('.') }
end

H.on_cmdline_leave = function()
  local cmd_type = vim.fn.getcmdtype()
  local is_insearch = vim.o.incsearch and (cmd_type == '/' or cmd_type == '?')
  if not is_insearch then return end

  -- Update scroll state so that there is no scroll animation after confirming
  -- incremental search. Otherwise it leads to unnecessary animation from
  -- initial scroll state to the one **already shown**.
  H.track_scroll_state()
end

H.auto_openclose = function(action_type)
  action_type = action_type or 'open'

  -- Don't animate if disabled
  local config = H.get_config()[action_type]
  if not config.enable or H.is_disabled() then return end

  -- Get window id to act upon
  local win_id
  if action_type == 'close' then win_id = tonumber(vim.fn.expand('<amatch>')) end
  if action_type == 'open' then win_id = math.max(unpack(vim.api.nvim_list_wins())) end

  -- Don't animate if created window is not right (valid and not floating)
  if win_id == nil or not vim.api.nvim_win_is_valid(win_id) then return end
  if vim.api.nvim_win_get_config(win_id).relative ~= '' then return end

  -- Register new event only in case there is something to animate
  local event_id_name = action_type .. '_event_id'
  H.cache[event_id_name] = H.cache[event_id_name] + 1

  -- Make animation step data and possibly animate
  local animate_step = H.make_openclose_step(action_type, win_id, config)
  if not animate_step then return end

  H.start_openclose(action_type)
  MiniAnimate.animate(animate_step.step_action, animate_step.step_timing)
end

-- General animation ----------------------------------------------------------
H.trigger_done_event = function(animation_type) vim.cmd('doautocmd User ' .. H.animation_done_events[animation_type]) end

-- Cursor ---------------------------------------------------------------------
H.make_cursor_step = function(state_from, state_to, opts)
  local pos_from, pos_to = state_from.pos, state_to.pos
  local destination = { pos_to[1] - pos_from[1], pos_to[2] - pos_from[2] }
  local path = opts.path(destination)
  if path == nil or #path == 0 then return end

  local n_steps = #path
  local timing = opts.timing

  -- Using explicit buffer id allows correct animation stop after buffer switch
  local event_id, buf_id = H.cache.cursor_event_id, state_from.buf_id

  return {
    step_action = function(step)
      -- Undraw previous mark. Doing it before early return allows to clear
      -- last animation mark.
      H.undraw_cursor_mark(buf_id)

      -- Stop animation if another cursor movement is active. Don't use
      -- `stop_cursor()` because it will also stop parallel animation.
      if H.cache.cursor_event_id ~= event_id then return false end

      -- Don't draw outside of set number of steps or not inside current buffer
      if n_steps <= step or vim.api.nvim_get_current_buf() ~= buf_id then return H.stop_cursor() end

      -- Draw cursor mark (starting from initial zero step)
      local pos = path[step + 1]
      H.draw_cursor_mark(pos_from[1] + pos[1], pos_from[2] + pos[2], buf_id)
      return true
    end,
    step_timing = function(step) return timing(step, n_steps) end,
  }
end

H.get_cursor_state = function()
  -- Use virtual column to respect position outside of line width and tabs
  return { buf_id = vim.api.nvim_get_current_buf(), pos = { vim.fn.line('.'), vim.fn.virtcol('.') } }
end

H.draw_cursor_mark = function(line, virt_col, buf_id)
  -- Use only absolute coordinates. Allows to not draw outside of buffer.
  if line <= 0 or virt_col <= 0 then return end

  -- Compute window column at which to place mark. Don't use explicit `col`
  -- argument because it won't allow placing mark outside of text line.
  local win_col = virt_col - vim.fn.winsaveview().leftcol
  if win_col < 1 then return end

  -- Set extmark
  local extmark_opts = {
    id = 1,
    hl_mode = 'combine',
    priority = 1000,
    right_gravity = false,
    virt_text = { { ' ', 'MiniAnimateCursor' } },
    virt_text_win_col = win_col - 1,
    virt_text_pos = 'overlay',
  }
  pcall(vim.api.nvim_buf_set_extmark, buf_id, H.ns_id.cursor, line - 1, 0, extmark_opts)
end

H.undraw_cursor_mark = function(buf_id) pcall(vim.api.nvim_buf_del_extmark, buf_id, H.ns_id.cursor, 1) end

H.start_cursor = function()
  H.cache.cursor_is_active = true
  return true
end

H.stop_cursor = function()
  H.cache.cursor_is_active = false
  H.trigger_done_event('cursor')
  return false
end

-- Scroll ---------------------------------------------------------------------
H.make_scroll_step = function(state_from, state_to, opts)
  -- Do not animate in Select mode because it resets it
  local is_select_mode = ({ s = true, S = true, ['\19'] = true })[vim.fn.mode()]
  if is_select_mode then return end

  -- Compute how subscrolling is done
  local from_line, to_line = state_from.view.topline, state_to.view.topline
  local total_scroll = H.get_n_visible_lines(from_line, to_line) - 1
  local step_scrolls = opts.subscroll(total_scroll)

  -- Don't animate if no subscroll steps is returned
  if step_scrolls == nil or #step_scrolls == 0 then return end

  -- Compute scrolling key ('\25' and '\5' are escaped '<C-Y>' and '<C-E>')
  local scroll_key = from_line < to_line and '\5' or '\25'

  -- Cache frequently accessed data
  local from_cur_line, to_cur_line = state_from.cursor.line, state_to.cursor.line
  local from_cur_virtcol, to_cur_virtcol = state_from.cursor.virtcol, state_to.cursor.virtcol

  local event_id, buf_id, win_id = H.cache.scroll_event_id, state_from.buf_id, state_from.win_id
  local n_steps, timing = #step_scrolls, opts.timing

  return {
    step_action = function(step)
      -- Stop animation if another scroll is active. Don't use `stop_scroll()`
      -- because it will stop parallel animation.
      if H.cache.scroll_event_id ~= event_id then return false end

      -- Stop animation if jumped to different buffer or window. Don't restore
      -- window view as it can only operate on current window.
      local is_same_win_buf = vim.api.nvim_get_current_buf() == buf_id and vim.api.nvim_get_current_win() == win_id
      if not is_same_win_buf then return H.stop_scroll() end

      -- Compute intermediate cursor position. This relies on `virtualedit=all`
      -- to be able to place cursor anywhere on screen (has better animation;
      -- at least for default equally spread subscrolls).
      local coef = step / n_steps
      local cursor_line = H.convex_point(from_cur_line, to_cur_line, coef)
      local cursor_virtcol = H.convex_point(from_cur_virtcol, to_cur_virtcol, coef)
      local cursor_data = { line = cursor_line, virtcol = cursor_virtcol }

      -- Perform scroll. Possibly stop on error.
      local ok, _ = pcall(H.scroll_action, scroll_key, step_scrolls[step], cursor_data)
      if not ok then return H.stop_scroll(state_to) end

      -- Update current scroll state for two reasons:
      -- - Be able to distinguish manual `WinScrolled` event from one created
      --   by `H.scroll_action()`.
      -- - Be able to start manual scrolling at any animation step.
      H.cache.scroll_state = H.get_scroll_state()

      -- Properly stop animation if step is too big
      if n_steps <= step then return H.stop_scroll(state_to) end

      return true
    end,
    step_timing = function(step) return timing(step, n_steps) end,
  }
end

H.scroll_action = function(key, n, cursor_data)
  -- Scroll. Allow supplying non-valid `n` for initial "scroll" which sets
  -- cursor immediately, which reduces flicker.
  if n ~= nil and n > 0 then
    local command = string.format('normal! %d%s', n, key)
    vim.cmd(command)
  end

  -- Set cursor to properly handle cursor position
  -- Computation of available top/bottom line depends on `scrolloff = 0`
  -- because otherwise it will go out of bounds causing scroll overshoot with
  -- later "bounce" back on view restore (see
  -- https://github.com/nvim-mini/mini.nvim/issues/177).
  local top, bottom = vim.fn.line('w0'), vim.fn.line('w$')
  local line = math.min(math.max(cursor_data.line, top), bottom)

  -- Cursor can only be set using byte column. To place it in the most correct
  -- virtual column, tweak output of `virtcol2col()`
  local virtcol = cursor_data.virtcol
  local col = vim.fn.virtcol2col(0, line, virtcol)
  -- - Correct for virtual column being outside of line's last virtual column
  local virtcol_past_lineend = vim.fn.virtcol({ line, '$' })
  if virtcol_past_lineend <= virtcol then col = col + virtcol - virtcol_past_lineend + 1 end

  pcall(vim.api.nvim_win_set_cursor, 0, { line, col - 1 })
end

H.start_scroll = function(start_state)
  H.cache.scroll_is_active = true
  -- Disable scrolloff in order to be able to place cursor on top/bottom window
  -- line inside scroll step.
  -- Incorporating `vim.wo.scrolloff` in computation of available top and
  -- bottom window lines works, but only in absence of folds. It gets tricky
  -- otherwise, so disabling on scroll start and restore on scroll end is
  -- better solution.
  vim.wo.scrolloff = 0
  -- Allow placing cursor anywhere on screen for better cursor placing
  vim.wo.virtualedit = 'all'

  if start_state ~= nil then
    vim.fn.winrestview(start_state.view)
    -- Track state because `winrestview()` later triggers `WinScrolled`.
    -- Otherwise mapping like `u<Cmd>lua _G.n = 0<CR>` (as in 'mini.bracketed')
    -- can result into "inverted scroll": from destination to current state.
    H.track_scroll_state()
  end

  return true
end

H.stop_scroll = function(end_state)
  if end_state ~= nil then
    vim.fn.winrestview(end_state.view)
    H.track_scroll_state()
  end

  vim.wo.scrolloff = end_state.scrolloff
  vim.wo.virtualedit = end_state.virtualedit

  H.cache.scroll_is_active = false
  H.trigger_done_event('scroll')

  return false
end

H.get_scroll_state = function()
  return {
    buf_id = vim.api.nvim_get_current_buf(),
    win_id = vim.api.nvim_get_current_win(),
    view = vim.fn.winsaveview(),
    cursor = { line = vim.fn.line('.'), virtcol = vim.fn.virtcol('.') },
    scrolloff = H.cache.scroll_is_active and H.cache.scroll_state.scrolloff or vim.wo.scrolloff,
    virtualedit = H.cache.scroll_is_active and H.cache.scroll_state.virtualedit or vim.wo.virtualedit,
  }
end

-- Resize ---------------------------------------------------------------------
H.make_resize_step = function(state_from, state_to, opts)
  -- Compute number of animation steps
  local step_sizes = opts.subresize(state_from.sizes, state_to.sizes)
  if step_sizes == nil or #step_sizes == 0 then return end
  local n_steps = #step_sizes

  -- Create animation step
  local event_id, timing = H.cache.resize_event_id, opts.timing

  return {
    step_action = function(step)
      -- Do nothing on initialization
      if step == 0 then return true end

      -- Stop animation if another resize animation is active. Don't use
      -- `stop_resize()` because it will also stop parallel animation.
      if H.cache.resize_event_id ~= event_id then return false end

      -- Perform animation. Possibly stop on error.
      -- Use `false` to not restore cursor position to avoid horizontal flicker
      local ok, _ = pcall(H.apply_resize_state, { sizes = step_sizes[step] }, false)
      if not ok then return H.stop_resize(state_to) end

      -- Properly stop animation if step is too big
      if n_steps <= step then return H.stop_resize(state_to) end

      return true
    end,
    step_timing = function(step) return timing(step, n_steps) end,
  }
end

H.start_resize = function(start_state)
  H.cache.resize_is_active = true
  -- Don't restore cursor position to avoid horizontal flicker
  if start_state ~= nil then H.apply_resize_state(start_state, false) end
  return true
end

H.stop_resize = function(end_state)
  if end_state ~= nil then H.apply_resize_state(end_state, true) end
  H.cache.resize_is_active = false
  H.trigger_done_event('resize')
  return false
end

H.get_resize_state = function()
  local layout = vim.fn.winlayout()

  local windows = H.get_layout_windows(layout)
  local sizes, views = {}, {}
  for _, win_id in ipairs(windows) do
    sizes[win_id] = { height = vim.api.nvim_win_get_height(win_id), width = vim.api.nvim_win_get_width(win_id) }
    views[win_id] = vim.api.nvim_win_call(win_id, function() return vim.fn.winsaveview() end)
  end

  return { layout = layout, sizes = sizes, views = views }
end

H.is_equal_resize_state = function(state_1, state_2)
  return {
    layout = vim.deep_equal(state_1.layout, state_2.layout),
    sizes = vim.deep_equal(state_1.sizes, state_2.sizes),
  }
end

H.get_layout_windows = function(layout)
  local res = {}
  local traverse
  traverse = function(l)
    if l[1] == 'leaf' then
      table.insert(res, l[2])
      return
    end
    for _, sub_l in ipairs(l[2]) do
      traverse(sub_l)
    end
  end
  traverse(layout)

  return res
end

H.apply_resize_state = function(state, full_view)
  -- Set window sizes while ensuring that 'cmdheight' will not change. Can
  -- happen if changing height of window main row layout or increase terminal
  -- height quickly (see #270)
  local cache_cmdheight = vim.o.cmdheight

  for win_id, dims in pairs(state.sizes) do
    vim.api.nvim_win_set_height(win_id, dims.height)
    vim.api.nvim_win_set_width(win_id, dims.width)
  end

  vim.o.cmdheight = cache_cmdheight

  -- Use `or {}` to allow states without `view` (mainly inside animation)
  for win_id, view in pairs(state.views or {}) do
    vim.api.nvim_win_call(win_id, function()
      -- Allow to not restore full view. It mainly solves horizontal flickering
      -- when resizing from small to big width and cursor is on the end of long
      -- line. This is especially visible for high 'winwidth'.
      -- Example: `set winwidth=120 winheight=40` and hop between two
      -- vertically split windows with cursor on `$` of long line.
      if full_view then
        vim.fn.winrestview(view)
        return
      end

      -- This triggers `CursorMoved` event, but nothing can be done
      -- (`noautocmd` is of no use, see https://github.com/vim/vim/issues/2084)
      pcall(vim.api.nvim_win_set_cursor, win_id, { view.lnum, view.leftcol })
      vim.fn.winrestview({ topline = view.topline, leftcol = view.leftcol })
    end)
  end

  -- Update current resize state to be able to start another resize animation
  -- at any current animation step. Recompute state to also capture `view`.
  H.cache.resize_state = H.get_resize_state()
end

-- Open/close -----------------------------------------------------------------
H.make_openclose_step = function(action_type, win_id, config)
  -- Compute winconfig progression
  local step_winconfigs = config.winconfig(win_id)
  if step_winconfigs == nil or #step_winconfigs == 0 then return end

  -- Produce animation steps.
  local n_steps, event_id_name = #step_winconfigs, action_type .. '_event_id'
  local timing, winblend, event_id = config.timing, config.winblend, H.cache[event_id_name]
  local float_win_id

  return {
    step_action = function(step)
      -- Stop animation if another similar animation is active. Don't use
      -- `stop_openclose()` because it will also stop parallel animation.
      if H.cache[event_id_name] ~= event_id then
        pcall(vim.api.nvim_win_close, float_win_id, true)
        return false
      end

      -- Stop animation if exceeded number of steps
      if n_steps <= step then
        pcall(vim.api.nvim_win_close, float_win_id, true)
        return H.stop_openclose(action_type)
      end

      -- Empty buffer should always be valid (might have been closed by user command)
      if H.empty_buf_id == nil or not vim.api.nvim_buf_is_valid(H.empty_buf_id) then
        H.empty_buf_id = vim.api.nvim_create_buf(false, true)
        H.set_buf_name(H.empty_buf_id, 'open-close-scratch')
      end

      -- Set step config to window. Possibly (re)open (it could have been
      -- manually closed like after `:only`)
      local float_config = step_winconfigs[step + 1]
      if step == 0 or not vim.api.nvim_win_is_valid(float_win_id) then
        float_win_id = vim.api.nvim_open_win(H.empty_buf_id, false, float_config)
        vim.wo[float_win_id].winhighlight = 'Normal:MiniAnimateNormalFloat'
      else
        vim.api.nvim_win_set_config(float_win_id, float_config)
      end

      vim.wo[float_win_id].winblend = H.round(winblend(step, n_steps))

      return true
    end,
    step_timing = function(step) return timing(step, n_steps) end,
  }
end

H.start_openclose = function(action_type)
  H.cache[action_type .. '_is_active'] = true
  return true
end

H.stop_openclose = function(action_type)
  H.cache[action_type .. '_is_active'] = false
  H.trigger_done_event(action_type)
  return false
end

-- Animation timings ----------------------------------------------------------
H.normalize_timing_opts = function(x)
  x = vim.tbl_deep_extend('force', H.get_config(), { easing = 'in-out', duration = 20, unit = 'step' }, x or {})
  H.validate_if(H.is_valid_timing_opts, x, 'opts')
  return x
end

H.is_valid_timing_opts = function(x)
  if type(x.duration) ~= 'number' or x.duration < 0 then
    return false, [[In `gen_timing` option `duration` should be a positive number.]]
  end

  if not vim.tbl_contains({ 'in', 'out', 'in-out' }, x.easing) then
    return false, [[In `gen_timing` option `easing` should be one of 'in', 'out', or 'in-out'.]]
  end

  if not vim.tbl_contains({ 'total', 'step' }, x.unit) then
    return false, [[In `gen_timing` option `unit` should be one of 'step' or 'total'.]]
  end

  return true
end

--- Imitate common power easing function
---
--- Every step is preceded by waiting time decreasing/increasing in power
--- series fashion (`d` is "delta", ensures total duration time):
--- - "in":  d*n^p; d*(n-1)^p; ... ; d*2^p;     d*1^p
--- - "out": d*1^p; d*2^p;     ... ; d*(n-1)^p; d*n^p
--- - "in-out": "in" until 0.5*n, "out" afterwards
---
--- This way it imitates `power + 1` common easing function because animation
--- progression behaves as sum of `power` elements.
---
---@param power number Power of series.
---@param opts table Options from `MiniAnimate.gen_timing` entry.
---@private
H.timing_arithmetic = function(power, opts)
  -- Sum of first `n_steps` natural numbers raised to `power`
  local arith_power_sum = ({
    [0] = function(n_steps) return n_steps end,
    [1] = function(n_steps) return n_steps * (n_steps + 1) / 2 end,
    [2] = function(n_steps) return n_steps * (n_steps + 1) * (2 * n_steps + 1) / 6 end,
    [3] = function(n_steps) return n_steps ^ 2 * (n_steps + 1) ^ 2 / 4 end,
  })[power]

  -- Function which computes common delta so that overall duration will have
  -- desired value (based on supplied `opts`)
  local duration_unit, duration_value = opts.unit, opts.duration
  local make_delta = function(n_steps, is_in_out)
    local total_time = duration_unit == 'total' and duration_value or (duration_value * n_steps)
    local total_parts
    if is_in_out then
      -- Examples:
      -- - n_steps=5: 3^d, 2^d, 1^d, 2^d, 3^d
      -- - n_steps=6: 3^d, 2^d, 1^d, 1^d, 2^d, 3^d
      total_parts = 2 * arith_power_sum(math.ceil(0.5 * n_steps)) - (n_steps % 2 == 1 and 1 or 0)
    else
      total_parts = arith_power_sum(n_steps)
    end
    return total_time / total_parts
  end

  return ({
    ['in'] = function(s, n) return make_delta(n) * (n - s + 1) ^ power end,
    ['out'] = function(s, n) return make_delta(n) * s ^ power end,
    ['in-out'] = function(s, n)
      local n_half = math.ceil(0.5 * n)
      local s_halved
      if n % 2 == 0 then
        s_halved = s <= n_half and (n_half - s + 1) or (s - n_half)
      else
        s_halved = s < n_half and (n_half - s + 1) or (s - n_half + 1)
      end
      return make_delta(n, true) * s_halved ^ power
    end,
  })[opts.easing]
end

--- Imitate common exponential easing function
---
--- Every step is preceded by waiting time decreasing/increasing in geometric
--- progression fashion (`d` is 'delta', ensures total duration time):
--- - 'in':  (d-1)*d^(n-1); (d-1)*d^(n-2); ...; (d-1)*d^1;     (d-1)*d^0
--- - 'out': (d-1)*d^0;     (d-1)*d^1;     ...; (d-1)*d^(n-2); (d-1)*d^(n-1)
--- - 'in-out': 'in' until 0.5*n, 'out' afterwards
---
---@param opts table Options from `MiniAnimate.gen_timing` entry.
---@private
H.timing_geometrical = function(opts)
  -- Function which computes common delta so that overall duration will have
  -- desired value (based on supplied `opts`)
  local duration_unit, duration_value = opts.unit, opts.duration
  local make_delta = function(n_steps, is_in_out)
    local total_time = duration_unit == 'step' and (duration_value * n_steps) or duration_value
    -- Exact solution to avoid possible (bad) approximation
    if n_steps == 1 then return total_time + 1 end
    if is_in_out then
      local n_half = math.ceil(0.5 * n_steps)
      if n_steps % 2 == 1 then total_time = total_time + math.pow(0.5 * total_time + 1, 1 / n_half) - 1 end
      return math.pow(0.5 * total_time + 1, 1 / n_half)
    end
    return math.pow(total_time + 1, 1 / n_steps)
  end

  return ({
    ['in'] = function(s, n)
      local delta = make_delta(n)
      return (delta - 1) * delta ^ (n - s)
    end,
    ['out'] = function(s, n)
      local delta = make_delta(n)
      return (delta - 1) * delta ^ (s - 1)
    end,
    ['in-out'] = function(s, n)
      local n_half, delta = math.ceil(0.5 * n), make_delta(n, true)
      local s_halved
      if n % 2 == 0 then
        s_halved = s <= n_half and (n_half - s) or (s - n_half - 1)
      else
        s_halved = s < n_half and (n_half - s) or (s - n_half)
      end
      return (delta - 1) * delta ^ s_halved
    end,
  })[opts.easing]
end

-- Animation path -------------------------------------------------------------
H.path_line = function(destination, opts)
  -- Don't animate in case of false predicate
  if not opts.predicate(destination) then return {} end

  -- Travel along the biggest horizontal/vertical difference, but stop one
  -- step before destination
  local l, c = destination[1], destination[2]
  local l_abs, c_abs = math.abs(l), math.abs(c)
  local max_diff = math.min(math.max(l_abs, c_abs), opts.max_output_steps)

  local res = {}
  for i = 0, max_diff - 1 do
    local prop = i / max_diff
    table.insert(res, { H.round(prop * l), H.round(prop * c) })
  end
  return res
end

H.default_path_predicate = function(destination) return destination[1] < -1 or 1 < destination[1] end

-- Animation subscroll --------------------------------------------------------
H.subscroll_equal = function(total_scroll, opts)
  -- Don't animate in case of false predicate
  if not opts.predicate(total_scroll) then return {} end

  -- Make equal steps, but no more than `max_output_steps`
  local n_steps = math.min(total_scroll, opts.max_output_steps)
  local res, coef = {}, total_scroll / n_steps
  for i = 1, n_steps do
    res[i] = math.floor(i * coef) - math.floor((i - 1) * coef)
  end
  return res
end

H.default_subscroll_predicate = function(total_scroll) return total_scroll > 1 end

-- Animation subresize --------------------------------------------------------
H.subresize_equal = function(sizes_from, sizes_to, opts)
  -- Don't animate in case of false predicate
  if not opts.predicate(sizes_from, sizes_to) then return {} end

  -- Don't animate single window
  if #vim.tbl_keys(sizes_from) == 1 then return {} end

  -- Compute number of steps
  local n_steps = 0
  for win_id, dims_from in pairs(sizes_from) do
    local height_absidff = math.abs(sizes_to[win_id].height - dims_from.height)
    local width_absidff = math.abs(sizes_to[win_id].width - dims_from.width)
    n_steps = math.max(n_steps, height_absidff, width_absidff)
  end
  if n_steps <= 1 then return {} end

  -- Make subresize array
  local res = {}
  for i = 1, n_steps do
    local coef = i / n_steps
    local sub_res = {}
    for win_id, dims_from in pairs(sizes_from) do
      sub_res[win_id] = {
        height = H.convex_point(dims_from.height, sizes_to[win_id].height, coef),
        width = H.convex_point(dims_from.width, sizes_to[win_id].width, coef),
      }
    end
    res[i] = sub_res
  end

  return res
end

H.default_subresize_predicate = function(sizes_from, sizes_to) return true end

-- Animation winconfig --------------------------------------------------------
H.winconfig_static = function(win_id, opts)
  -- Don't animate in case of false predicate
  if not opts.predicate(win_id) then return {} end

  local pos = vim.fn.win_screenpos(win_id)
  local width, height = vim.api.nvim_win_get_width(win_id), vim.api.nvim_win_get_height(win_id)
  local res = {}
  for i = 1, opts.n_steps do
      --stylua: ignore
      res[i] = {
        relative  = 'editor',
        anchor    = 'NW',
        row       = pos[1] - 1,
        col       = pos[2] - 1,
        width     = width,
        height    = height,
        focusable = false,
        zindex    = 1,
        border    = 'none',
        style     = 'minimal',
      }
  end
  return res
end

H.get_window_parent_container = function(win_id)
  local f
  f = function(layout, parent_container)
    local container, second = layout[1], layout[2]
    if container == 'leaf' then
      if second == win_id then return parent_container end
      return
    end

    for _, sub_layout in ipairs(second) do
      local res = f(sub_layout, container)
      if res ~= nil then return res end
    end
  end

  -- Important to get layout of tabpage window actually belongs to (as it can
  -- already be not current tabpage)
  -- NOTE: `winlayout()` takes tabpage number (non unique), not tabpage id
  local tabpage_id = vim.api.nvim_win_get_tabpage(win_id)
  local tabpage_nr = vim.api.nvim_tabpage_get_number(tabpage_id)
  return f(vim.fn.winlayout(tabpage_nr), 'single')
end

H.default_winconfig_predicate = function(win_id) return true end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.animate) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.set_buf_name = function(buf_id, name) vim.api.nvim_buf_set_name(buf_id, 'minianimate://' .. buf_id .. '/' .. name) end

H.validate_if = function(predicate, x, x_name)
  local is_valid, msg = predicate(x, x_name)
  if not is_valid then H.error(msg) end
end

H.get_n_visible_lines = function(from_line, to_line)
  local min_line, max_line = math.min(from_line, to_line), math.max(from_line, to_line)

  -- If `max_line` is inside fold, scrol should stop on the fold (not after)
  local max_line_fold_start = vim.fn.foldclosed(max_line)
  local target_line = max_line_fold_start == -1 and max_line or max_line_fold_start

  local i, res = min_line, 1
  while i < target_line do
    res = res + 1
    local end_fold_line = vim.fn.foldclosedend(i)
    i = (end_fold_line == -1 and i or end_fold_line) + 1
  end
  return res
end

H.round = function(x) return math.floor(x + 0.5) end

H.convex_point = function(x, y, coef) return H.round((1 - coef) * x + coef * y) end

return MiniAnimate
