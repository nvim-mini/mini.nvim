--- *mini.fuzzy* Fuzzy matching
---
--- MIT License Copyright (c) 2021 Evgeni Chasnovski

--- Features:
--- - Minimal and fast fuzzy matching algorithm which prioritizes match width.
---
--- - Functions to for common fuzzy matching operations:
---     - |MiniFuzzy.match()|.
---     - |MiniFuzzy.filtersort()|.
---     - |MiniFuzzy.process_lsp_items()|.
---
--- - Generator of |telescope.nvim| sorter: |MiniFuzzy.get_telescope_sorter()|.
---
--- # Setup ~
---
--- This module doesn't need setup, but it can be done to improve usability.
--- Setup with `require('mini.fuzzy').setup({})` (replace `{}` with your
--- `config` table). It will create global Lua table `MiniFuzzy` which you can
--- use for scripting or manually (with `:lua MiniFuzzy.*`).
---
--- See |MiniFuzzy.config| for `config` structure and default values.
---
--- You can override runtime config settings locally to buffer inside
--- `vim.b.minifuzzy_config` which should have same structure as
--- `MiniFuzzy.config`.
--- See |mini.nvim-buffer-local-config| for more details.
---
--- # Notes ~
---
--- 1. Currently there is no explicit design to work with multibyte symbols,
---    but simple examples should work.
--- 2. Smart case is used: case insensitive if input word (which is usually a
---    user input) is all lower case. Case sensitive otherwise.
---@tag MiniFuzzy

--- # Algorithm design ~
---
--- General design uses only width of found match and index of first letter
--- match. No special characters or positions (like in fzy and fzf) are used.
---
--- Given non-empty input `word` and target `candidate`:
--- - The goal is to find matching between `word`'s letters and letters in
---   `candidate` which minimizes certain score. It is assumed that order of
---   letters in `word` and those matched in `candidate` should be the same.
---
--- - Matching is represented by matched positions: an array `positions` of
---   integers with length equal to number of letters in `word`. The following
---   should be always true in case of a match: `candidate`'s letter at index
---   `positions[i]` is letters[i]` for all valid `i`.
---
--- - Matched positions are evaluated based only on two features: their width
---   (number of indexes between first and last positions) and first match
---   (index of first letter match). There is a global setting `cutoff` for
---   which all feature values greater than it can be considered "equally bad".
---
--- - Score of matched positions is computed with following explicit formula:
---   `cutoff * min(width, cutoff) + min(first, cutoff)`. It is designed to be
---   equivalent to first comparing widths (lower is better) and then comparing
---   first match (lower is better). For example, if `word = 'time'`:
---     - '_time' (width 4) will have a better match than 't_ime' (width 5).
---     - 'time_a' (width 4, first 1) will have a better match than 'a_time'
---       (width 4, first 3).
---
--- - Final matched positions are those which minimize score among all possible
---   matched positions of `word` and `candidate`.
---@tag MiniFuzzy-algorithm

-- Module definition ==========================================================
local MiniFuzzy = {}
local H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniFuzzy.config|.
---
---@usage >lua
---   require('mini.fuzzy').setup() -- use default config
---   -- OR
---   require('mini.fuzzy').setup({}) -- replace {} with your config table
--- <
MiniFuzzy.setup = function(config)
  -- Export module
  _G.MiniFuzzy = MiniFuzzy

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)
end

--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
MiniFuzzy.config = {
  -- Maximum allowed value of match features (width and first match). All
  -- feature values greater than cutoff can be considered "equally bad".
  cutoff = 100,
}
--minidoc_afterlines_end

-- Module functionality =======================================================
--- Compute match data
---
---@param word string Input word (usually user input).
---@param candidate string Target word (usually with which matching is done).
---
---@return table Matching information:
---   - <positions> `(table|nil)` - array with letter indexes inside `candidate`
---     which matched to corresponding letters in `word`. It is empty array if
---     `word` is empty string and `nil` if no match.
---   - <score> `number` - positive number representing how good the match is
---     (lower is better). It is `-1` if no match or word is empty string.
MiniFuzzy.match = function(word, candidate)
  -- Use 'smart case'
  candidate = word == word:lower() and candidate:lower() or candidate
  local positions = H.find_best_positions(H.string_to_letters(word), candidate)
  return { positions = positions, score = H.score_positions(positions) }
end

--- Filter string array
---
--- - Keep only input elements which match `word`.
--- - Sort from best to worst matches (based on score and index in original
---   array, both lower is better).
---
---@param word string String which will be searched.
---@param candidate_array table Lua array of strings inside which word will be
---   searched.
---
---@return ... Arrays of matched candidates and their indexes in original input.
MiniFuzzy.filtersort = function(word, candidate_array)
  -- Use 'smart case'. Create new array to preserve input for later filtering
  local cand_array = word == word:lower() and vim.tbl_map(string.lower, candidate_array) or candidate_array
  local filter_ids = H.make_filter_indexes(word, cand_array)
  table.sort(filter_ids, H.compare_filter_indexes)

  return H.filter_by_indexes(candidate_array, filter_ids)
end

--- Fuzzy matching for `lsp_completion.process_items` of |MiniCompletion.config|
---
---@param items table Array with LSP 'textDocument/completion' response items.
---@param base string Word to complete.
---
---@return table Array of items with text (`filterText` or `label`) fuzzy matching `base`.
MiniFuzzy.process_lsp_items = function(items, base)
  local words = vim.tbl_map(function(x) return x.filterText or x.label end, items)
  local _, match_inds = MiniFuzzy.filtersort(base, words)
  return vim.tbl_map(function(i) return items[i] end, match_inds)
end

--- Custom getter for `telescope.nvim` sorter
---
--- Designed to be used as value for |telescope.defaults.file_sorter|
--- and |telescope.defaults.generic_sorter|.
---
---@param opts table|nil Options (currently not used).
---
---@usage >lua
---   require('telescope').setup({
---     defaults = {
---       generic_sorter = require('mini.fuzzy').get_telescope_sorter
---     }
---   })
--- <
MiniFuzzy.get_telescope_sorter = function(opts)
  opts = opts or {}

  return require('telescope.sorters').Sorter:new({
    start = function(self, prompt)
      -- Cache prompt's letters
      self.letters = H.string_to_letters(prompt)

      -- Use 'smart case': insensitive if `prompt` is lowercase
      self.case_sensitive = prompt ~= prompt:lower()
    end,

    -- @param self
    -- @param prompt (which is the text on the line)
    -- @param line (entry.ordinal)
    -- @param entry (the whole entry)
    scoring_function = function(self, _, line, _)
      if #self.letters == 0 then return 1 end
      line = self.case_sensitive and line or line:lower()
      local positions = H.find_best_positions(self.letters, line)
      return H.score_positions(positions)
    end,

    -- Currently there doesn't seem to be a proper way to cache matched
    -- positions from inside of `scoring_function` (see `highlighter` code of
    -- `get_fzy_sorter`'s output). Besides, it seems that `display` and `line`
    -- arguments might be different. So, extra calls to `match` are made.
    highlighter = function(self, _, display)
      if #self.letters == 0 or #display == 0 then return {} end
      display = self.case_sensitive and display or display:lower()
      return H.find_best_positions(self.letters, display)
    end,
  })
end

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniFuzzy.config)

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  if not (type(config.cutoff) == 'number' and config.cutoff >= 1) then
    H.error('`cutoff` should be number not less than 1, not ' .. type(config.cutoff))
  end

  return config
end

H.apply_config = function(config) MiniFuzzy.config = config end

H.is_disabled = function() return vim.g.minifuzzy_disable == true or vim.b.minifuzzy_disable == true end

H.get_config = function(config)
  return vim.tbl_deep_extend('force', MiniFuzzy.config, vim.b.minifuzzy_config or {}, config or {})
end

-- Fuzzy matching -------------------------------------------------------------
---@param letters table Array of letters from input word
---@param candidate string String of interest
---
---@return table|nil Table with matched positions (in `candidate`) if there is a
---   match, `nil` otherwise.
---@private
H.find_best_positions = function(letters, candidate)
  local n_candidate, n_letters = #candidate, #letters
  if n_letters == 0 then return {} end
  if n_candidate < n_letters then return nil end

  -- Search forward to find matching positions with left-most last letter match
  local pos_last = 0
  for let_i = 1, #letters do
    pos_last = candidate:find(letters[let_i], pos_last + 1)
    if not pos_last then break end
  end

  -- Candidate is matched only if word's last letter is found
  if not pos_last then return nil end

  -- If there is only one letter, it is already the best match (there will not
  -- be better width and it has lowest first match)
  if n_letters == 1 then return { pos_last } end

  -- Compute best match positions by iteratively checking all possible last
  -- letter matches (at and after initial one). At end of each iteration
  -- `best_pos_last` holds best match for last letter among all previously
  -- checked such matches.
  local best_pos_last, best_width = pos_last, math.huge
  local rev_candidate = candidate:reverse()

  local cutoff = H.get_config().cutoff
  while pos_last do
    -- Simulate computing best match positions ending exactly at `pos_last` by
    -- going backwards from current last letter match. This works because it
    -- minimizes width which is the only way to find match with lower score.
    -- Not actually creating table with positions and then directly computing
    -- score increases speed by up to 40% (on small frequent input word with
    -- relatively wide candidate, such as file paths of nested directories).
    local rev_first = n_candidate - pos_last + 1
    for i = #letters - 1, 1, -1 do
      rev_first = rev_candidate:find(letters[i], rev_first + 1)
    end
    local first = n_candidate - rev_first + 1
    local width = math.min(pos_last - first + 1, cutoff)

    -- Using strict sign is crucial because when two last letter matches result
    -- into positions with similar width, the one which was created earlier
    -- (i.e. with smaller last letter match) will have smaller first letter
    -- match (hence better score).
    if width < best_width then
      best_pos_last, best_width = pos_last, width
    end

    -- Advance iteration
    pos_last = candidate:find(letters[n_letters], pos_last + 1)
  end

  -- Actually compute best matched positions from best last letter match
  local best_positions = { best_pos_last }
  local rev_pos = n_candidate - best_pos_last + 1
  for i = #letters - 1, 1, -1 do
    rev_pos = rev_candidate:find(letters[i], rev_pos + 1)
    -- For relatively small number of letters (around 10, which is main use
    -- case) inserting to front seems to have better performance than
    -- inserting at end and then reversing.
    table.insert(best_positions, 1, n_candidate - rev_pos + 1)
  end

  return best_positions
end

-- Compute score of matched positions. Smaller values indicate better match
-- (i.e. like distance). Reasoning behind the score is for it to produce the
-- same ordering as with sequential comparison of match's width and first
-- position. So it shouldn't really be perceived as linear distance (difference
-- between scores don't really matter, only their comparison with each other).
--
-- Reasoning behind comparison logic (based on 'time' input):
-- - '_time' is better than 't_ime' (width is smaller).
-- - 'time_aa' is better than 'aa_time' (same width, first match is smaller).
--
-- Returns -1 if `positions` is `nil` or empty.
H.score_positions = function(positions)
  if positions == nil or #positions == 0 then return -1 end
  local first, last = positions[1], positions[#positions]
  local cutoff = H.get_config().cutoff
  return cutoff * math.min(last - first + 1, cutoff) + math.min(first, cutoff)
end

H.make_filter_indexes = function(word, candidate_array)
  local res, letters = {}, H.string_to_letters(word)
  for i, cand in ipairs(candidate_array) do
    local positions = H.find_best_positions(letters, cand)
    if positions ~= nil then table.insert(res, { index = i, score = H.score_positions(positions) }) end
  end
  return res
end

H.compare_filter_indexes = function(a, b) return a.score < b.score or (a.score == b.score and a.index < b.index) end

H.filter_by_indexes = function(candidate_array, ids)
  local res, res_ids = {}, {}
  for _, id in pairs(ids) do
    table.insert(res, candidate_array[id.index])
    table.insert(res_ids, id.index)
  end
  return res, res_ids
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.fuzzy) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.string_to_letters = function(s) return vim.tbl_map(vim.pesc, vim.split(s, '')) end

return MiniFuzzy
