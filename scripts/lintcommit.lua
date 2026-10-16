-- Validate commit message. Designed to be run as pre-commit hook and in CI.
--
-- Each Neovim's argument for when it is opened is assumed to be a path to
-- a file containing commit message to validate
-- Example usage:
-- ```
-- nvim --headless --noplugin -u scripts/lintcommit.lua -- .git/COMMIT_EDITMSG
-- ```

-- Validator functions
local allowed_commit_types = { 'ci', 'docs', 'feat', 'fix', 'refactor', 'style', 'test' }

local allowed_scopes = { 'ALL' }
for _, module in ipairs(vim.fn.readdir('lua/mini')) do
  if module ~= 'init.lua' then table.insert(allowed_scopes, module:match('^(.+)%.lua$')) end
end

local validate_subject = function(line)
  -- Possibly allow starting with 'fixup' to disable commit linting
  if vim.startswith(line, 'fixup') then
    local is_strict = vim.uv.os_getenv('LINTCOMMIT_STRICT') ~= nil
    local msg = is_strict and 'No "fixup" commits are allowed.' or ''
    return not is_strict, msg
  end

  -- Should match overall conventional commit spec
  local commit_type, scope, desc = string.match(line, '^([^(]+)(%b())!?: (.+)$')
  if commit_type == nil then
    commit_type, desc = string.match(line, '^([^!:]+)!?: (.+)$')
  end
  if commit_type == nil or desc == nil then
    return false,
      'First line does not match conventional commit specification of `<type>[optional scope][!]: <description>`: '
        .. vim.inspect(line)
  end

  -- Commit type should be present and be from one of allowed
  if not vim.tbl_contains(allowed_commit_types, commit_type) then
    local one_of = table.concat(vim.tbl_map(vim.inspect, allowed_commit_types), ', ')
    return false, 'Commit type ' .. vim.inspect(commit_type) .. ' is not allowed. Use one of ' .. one_of .. '.'
  end

  -- Scope, if present, should be from one of allowed
  if scope ~= nil then
    scope = scope:sub(2, -2)
    if not vim.tbl_contains(allowed_scopes, scope) then
      local one_of = table.concat(vim.tbl_map(vim.inspect, allowed_scopes), ', ')
      return false, 'Scope ' .. vim.inspect(scope) .. ' is not allowed. Use one of ' .. one_of .. '.'
    end
  end

  -- Description should be present and properly formatted
  if string.find(desc, '^%w') == nil then
    return false, 'Description should start with alphanumeric character: ' .. vim.inspect(desc)
  end

  if string.find(desc, '^%u%l') ~= nil then
    return false, 'Description should not start with capitalized word: ' .. vim.inspect(desc)
  end

  if string.find(desc, '[.,?!;]$') ~= nil then
    return false, 'Description should not end with any of `.,?!;`: ' .. vim.inspect(desc)
  end

  -- Subject should not be too long
  if vim.fn.strdisplaywidth(line) > 72 then
    return false, 'First line is longer than 72 characters: ' .. vim.inspect(desc)
  end

  return true, nil
end

local is_details = function(line, line_next) return line == 'Details:' and vim.startswith(line_next or '', '- ') end

local is_forge_directive = function(line)
  return line:find('^Resolve [%a%p]*#%d+$') ~= nil or line:find('^Related to [%a%p]*#%d+$') ~= nil
end

local is_git_footer = function(line) return vim.startswith(line, 'Co-authored-by: ') end

local validate_body = function(parts)
  if #parts == 1 then return true, nil end

  if parts[2] ~= '' then return false, 'Second line should be empty' end
  if parts[3] == nil then return false, 'If first line is not enough, body should be present' end
  if string.find(parts[3], '^%S') == nil then return false, 'First body line should not start with whitespace.' end

  local is_good_body_start = is_details(parts[3], parts[4]) or is_forge_directive(parts[3]) or is_git_footer(parts[3])
  if not is_good_body_start then
    local msg = table.concat({
      'First body line should be one of:',
      '- Details: start with "Details:" and follow with a "- ..." to list extra info about the change.',
      '- Forge directive: "Resolve #XXXX" / "Related to #XXXX" to show which issue/PR/discussion is resolved/related.',
      '- Git footer: "Co-authored-by: " to show commit co-authors.',
    }, '\n')
    return false, msg
  end

  local details_lnum, forge_lnum, git_lnum
  for i = 3, #parts do
    if vim.fn.strdisplaywidth(parts[i]) > 80 and not vim.startswith(parts[i], 'Co-authored-by:') then
      return false, 'Body line is longer than 80 characters: ' .. vim.inspect(parts[i])
    end
    details_lnum = is_details(parts[i], parts[i + 1]) and i or details_lnum
    forge_lnum = is_forge_directive(parts[i]) and i or forge_lnum
    git_lnum = is_git_footer(parts[i]) and i or git_lnum
  end

  --stylua: ignore start
  if forge_lnum and details_lnum and forge_lnum < details_lnum then return false, 'Forge directives should go after "Details:"' end
  if git_lnum and details_lnum and git_lnum < details_lnum then return false, 'Git footer should go after "Details:"' end
  if git_lnum and forge_lnum and git_lnum < forge_lnum then return false, 'Git footer should go after forge directives' end
  --stylua: ignore end

  if string.find(parts[#parts], '^%s*$') ~= nil then return false, 'Body should not end with blank line.' end

  return true, nil
end

local validate_bad_wording = function(msg)
  local has_fix = msg:find('[Ff]ix [%a%p]*#') or msg:find('[Ff]ixes [%a%p]*#') or msg:find('[Ff]ixed [%a%p]*#')
  local has_bad_close = msg:find('[Cc]lose[sd]? #') ~= nil
  local has_bad_resolve = msg:find('[Rr]esolve[sd] #') ~= nil
  if has_fix or has_bad_close or has_bad_resolve then
    return false,
      'Use "Resolve #" Git forge directive to resolve issue/PR '
        .. '(not "Fix(/es/ed)", not "Close(/s/d)", not "Resolve(s/d)").'
  end
  return true, nil
end

local remove_cleanup_lines = function(lines)
  -- Remove lines which are assumed to be later cleaned up by Git itself
  -- See `git help commit` for option `--cleanup` (assumes default value)
  local res = {}
  for _, l in ipairs(lines) do
    -- Ignore anything past and including scissors line
    if l == '# ------------------------ >8 ------------------------' then break end
    -- Ignore comments
    if l:find('^%s*#') == nil then table.insert(res, l) end
  end

  -- Ignore trailing blank lines
  for i = #res, 1, -1 do
    if res[i]:find('%S') ~= nil then break end
    res[i] = nil
  end

  return res
end

local validate_commit_msg = function(lines)
  local is_valid, err_msg

  -- If not in strict context, ignore lines which will be later cleaned up
  local is_strict = vim.uv.os_getenv('LINTCOMMIT_STRICT') ~= nil
  if not is_strict then lines = remove_cleanup_lines(lines) end

  -- Allow all lines to be empty to abort committing
  local all_empty = true
  for _, l in ipairs(lines) do
    if l ~= '' then all_empty = false end
  end
  if all_empty then return true, nil end

  -- Validate subject (first line)
  is_valid, err_msg = validate_subject(lines[1])
  if not is_valid then return is_valid, err_msg end

  -- Validate body
  is_valid, err_msg = validate_body(lines)
  if not is_valid then return is_valid, err_msg end

  -- No validation for footer

  -- Should not contain bad wording
  for _, l in ipairs(lines) do
    is_valid, err_msg = validate_bad_wording(l)
    if not is_valid then return is_valid, err_msg end
  end

  return true, nil
end

local validate_commit_msg_from_file = function(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then return false, 'Could not read file ' .. path end
  return validate_commit_msg(lines)
end

-- Actual validation
local exit_code = 0
for i = 0, vim.fn.argc(-1) - 1 do
  local path = vim.fn.argv(i, -1)
  io.write('Commit message of ' .. vim.fn.fnamemodify(path, ':t') .. ':\n')
  local is_valid, err_msg = validate_commit_msg_from_file(path)
  io.write((is_valid and 'OK' or err_msg) .. '\n\n')
  if not is_valid then exit_code = 1 end
end

os.exit(exit_code)

-- Tests to be run interactively: `_G.test_cases_failed` should be empty.
-- NOTE: Comment out previous `os.exit()` call
local test_cases = {
  -- Subject
  ['fixup'] = true,
  ['fixup: commit message'] = true,
  ['fixup! commit message'] = true,

  ['ci: normal message'] = true,
  ['docs: normal message'] = true,
  ['feat: normal message'] = true,
  ['fix: normal message'] = true,
  ['refactor: normal message'] = true,
  ['style: normal message'] = true,
  ['test: normal message'] = true,

  ['feat(ai): message with scope'] = true,
  ['feat!: message with breaking change'] = true,
  ['feat(ai)!: message with scope and breaking change'] = true,
  ['style(ALL): style all modules'] = true,

  ['unknown: unknown type'] = false,
  ['feat(unknown): unknown scope'] = false,
  ['refactor(): empty scope'] = false,
  ['ci( ): whitespace as scope'] = false,

  ['ci no colon after type'] = false,
  [': no type before colon 1'] = false,
  [' : no type before colon 2'] = false,
  ['  : no type before colon 3'] = false,
  ['ci:'] = false,
  ['ci: '] = false,
  ['ci:  '] = false,

  ['feat: message with : in it'] = true,
  ['feat(ai): message with : in it'] = true,

  ['test:  extra space after colon'] = false,
  ['ci:	tab after colon'] = false,
  ['ci:no space after colon'] = false,
  ['ci : extra space before colon'] = false,

  ['ci: bad punctuation at end of sentence.'] = false,
  ['ci: bad punctuation at end of sentence,'] = false,
  ['ci: bad punctuation at end of sentence?'] = false,
  ['ci: bad punctuation at end of sentence!'] = false,
  ['ci: bad punctuation at end of sentence;'] = false,
  ['ci: good punctuation at end of sentence:'] = true,
  ['ci: good punctuation at end of sentence"'] = true,
  ["ci: good punctuation at end of sentence'"] = true,
  ['ci: good punctuation at end of sentence)'] = true,
  ['ci: good punctuation at end of sentence]'] = true,

  ['ci: Capitalized first word'] = false,
  ['ci: UPPER_CASE First Word'] = true,
  ['ci: very very very very very very very very very very very looong subject'] = false,

  -- Body
  ['ci: desc\n\nDetails:\n- Body'] = true,
  ['ci: desc\n\nDetails:\n- Body\n\nwith\n   \nempty and blank lines'] = true,

  ['ci: desc\nSecond line is not empty'] = false,
  ['ci: desc\n\n First body line starts with whitespace'] = false,

  -- Line width should be checked only in not cleaned up lines
  ['ci: desc\n\nDetails:\n- Body\nwith\nVery very very very very very very very very very very very very looong body line'] = false,
  ['ci: desc\n\nDetails:\n- Body\nwith\n# Comment with very very very very very very very very very very looong body line'] = true,
  ['ci: desc\n\nDetails:\n- Body\nwith\n# ------------------------ >8 ------------------------\nVery very very very very very very very very very very very very looong body line'] = true,

  -- Trailing blank lines are allowed in not strict context
  ['ci: only two lines\n\n'] = true,
  ['ci: desc\n\nDetails:\n- Last line is empty\n\n'] = true,
  ['ci: desc\n\nDetails:\n- Last line is blank\n  '] = true,

  -- Forge directives should follow specific template
  ['ci: desc\n\nResolve #1'] = true,
  ['ci: desc\n\nResolve nvim-mini/MiniMax#1'] = true,
  ['ci: desc\n\nRelated to #1'] = true,
  ['ci: desc\n\nRelated to nvim-mini/MiniMax#1'] = true,

  -- Git footer
  ['ci: desc\n\nCo-authored-by: Neo McVim <neo.mcvim@gmail.com>'] = true,

  -- Special body lines should go in specific order
  ['ci: desc\n\nDetails:\n- Body\n\nResolve #1'] = true,
  ['ci: desc\n\nResolve #1\n\nDetails:\n- Body'] = false,
  ['ci: desc\n\nDetails:\n- Body\n\nCo-authored-by: Neo McVim <neo.mcvim@gmail.com>'] = true,
  ['ci: desc\n\nCo-authored-by: Neo McVim <neo.mcvim@gmail.com>\n\nDetails:\n- Body'] = false,
  ['ci: desc\n\nResolve #1\n\nCo-authored-by: Neo McVim <neo.mcvim@gmail.com>'] = true,
  ['ci: desc\n\nCo-authored-by: Neo McVim <neo.mcvim@gmail.com>\n\nResolve #1'] = false,

  ['ci: desc\n\nDetails:\n- Body\n\nResolve #1\n\nCo-authored-by: Neo McVim <neo.mcvim@gmail.com>'] = true,
  ['ci: desc\n\nResolve #1\n\nDetails:\n- Body\n\nCo-authored-by: Neo McVim <neo.mcvim@gmail.com>'] = false,
  ['ci: desc\n\nResolve #1\n\nCo-authored-by: Neo McVim <neo.mcvim@gmail.com>\n\nDetails:\n- Body'] = false,
  ['ci: desc\n\nCo-authored-by: Neo McVim <neo.mcvim@gmail.com>\n\nResolve #1\n\nDetails:\n- Body'] = false,
  ['ci: desc\n\nDetails:\n- Body\n\nCo-authored-by: Neo McVim <neo.mcvim@gmail.com>\n\nResolve #1'] = false,
  ['ci: desc\n\nCo-authored-by: Neo McVim <neo.mcvim@gmail.com>\n\nDetails:\n- Body\n\nResolve #1'] = false,

  -- Bad wordings
  ['ci: this has Fixed #1'] = false,
  ['ci: this has fixed #1'] = false,
  ['ci: this Fixes #1'] = false,
  ['ci: this fixes #1'] = false,
  ['ci: this will Fix #1'] = false,
  ['ci: this will fix #1'] = false,
  ['ci: this has Closed #1'] = false,
  ['ci: this has closed #1'] = false,
  ['ci: this Closes #1'] = false,
  ['ci: this closes #1'] = false,
  ['ci: this will Close #1'] = false,
  ['ci: this will close #1'] = false,
  ['ci: this has Resolved #1'] = false,
  ['ci: this has resolved #1'] = false,
  ['ci: this Resolves #1'] = false,
  ['ci: this resolves #1'] = false,

  ['ci: desc\n\nthis has Fixed #1'] = false,
  ['ci: desc\n\nthis has fixed #1'] = false,
  ['ci: desc\n\nthis Fixes #1'] = false,
  ['ci: desc\n\nthis fixes #1'] = false,
  ['ci: desc\n\nthis will Fix #1'] = false,
  ['ci: desc\n\nthis will fix #1'] = false,
  ['ci: desc\n\nthis has Closed #1'] = false,
  ['ci: desc\n\nthis has closed #1'] = false,
  ['ci: desc\n\nthis Closes #1'] = false,
  ['ci: desc\n\nthis closes #1'] = false,
  ['ci: desc\n\nthis will Close #1'] = false,
  ['ci: desc\n\nthis will close #1'] = false,
  ['ci: desc\n\nthis has Resolved #1'] = false,
  ['ci: desc\n\nthis has resolved #1'] = false,
  ['ci: desc\n\nthis Resolves #1'] = false,
  ['ci: desc\n\nthis resolves #1'] = false,

  -- Comments are allowed in not strict context
  ['# Comment\nci: desc'] = true,
  [' # Comment\nci: desc'] = true,
  ['ci: desc\n# Comment\n\nDetails:\n- Body'] = true,

  -- Allow all empty lines
  [''] = true,
  ['\n'] = true,
  ['\n# Comment'] = true,
}

_G.test_cases_failed = {}

vim.uv.os_unsetenv('LINTCOMMIT_STRICT')
for message, expected in pairs(test_cases) do
  local lines = vim.split(message, '\n')
  local is_valid, reason = validate_commit_msg(lines)
  if is_valid ~= expected then
    table.insert(_G.test_cases_failed, { msg = message, expected = expected, actual = is_valid, reason = reason })
  end
end

vim.uv.os_setenv('LINTCOMMIT_STRICT', 'true')
local strict_test_cases = {
  -- Fixup commit type is not allowed
  ['fixup'] = false,
  ['fixup: should fail'] = false,
  ['fixup! should fail'] = false,

  -- - Should only matter in subject
  ['ci: desc\n\nDetails:\n- fixup'] = true,

  -- Do not allow comments outside of commit body
  ['# Comment\nci: desc'] = false,
  [' # Comment\nci: desc'] = false,
  ['ci: desc\n# Comment\n\nBody'] = false,

  ['ci: desc\n\nDetails:\n- Body\n# Comment in body'] = true,

  -- Check line width even in previously ignored contexts
  ['ci: desc\n\nBody\nwith\n# Comment with very very very very very very very very very very looong body line'] = false,
  ['ci: desc\n\nBody\nwith\n# ------------------------ >8 ------------------------\nVery very very very very very very very very very very very very looong body line'] = false,

  -- Trailing blank lines are not allowed in strict context
  ['ci: only two lines\n\n'] = false,
  ['ci: desc\n\nLast line is empty\n\n'] = false,
  ['ci: desc\n\nLast line is blank\n  '] = false,
}
for message, expected in pairs(strict_test_cases) do
  local lines = vim.split(message, '\n')
  local is_valid = validate_commit_msg(lines)
  if is_valid ~= expected then
    table.insert(_G.test_cases_failed, { msg = message, expected = expected, actual = is_valid })
  end
end

-- Cleanup
vim.uv.os_unsetenv('LINTCOMMIT_STRICT')
