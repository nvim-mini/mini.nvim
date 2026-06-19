local is_codeblock_start = function(line)
  return (line or ''):find(' >%w*%s*$') ~= nil or (line or ''):find('^>%w*%s*$') ~= nil
end

local is_codeblock_end = function(line) return (line or ''):find('^%S') ~= nil end

local iter_noncode_lines = function(lines)
  local n = #lines
  local f = function(_, i)
    if i >= n then return nil end
    i = i + 1
    if not is_codeblock_start(lines[i - 1]) then return i, lines[i] end
    for j = i, n do
      if is_codeblock_end(lines[j]) and j < n then return j + 1, lines[j + 1] end
    end
    return nil
  end
  return f, {}, 0
end

local append_problem = function(arr, file_path, lnum, msg) table.insert(arr, file_path .. '#' .. lnum .. ': ' .. msg) end

local get_help_tag_map = function()
  -- Ensure freshly generated helptags
  pcall(vim.fs.rm, 'doc')
  vim.cmd('helptags doc')

  -- Get all available tags
  local help_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[help_buf].buftype = 'help'
  local tags = vim.api.nvim_buf_call(help_buf, function() return vim.fn.taglist('.*') end)
  vim.api.nvim_buf_delete(help_buf, { force = true })

  local res = {}
  for _, tag_data in ipairs(tags) do
    res[tag_data.name] = true
  end

  -- Intentionally used, cherry picked tags from future and past versions
  --stylua: ignore
  local custom_tags = {
    -- Neovim>=0.13
    'al', 'il', 'vim.hl.hl_op()',
    -- Neovim<0.11
    'vim.highlight.on_yank()',
  }
  for _, tag in ipairs(custom_tags) do
    res[tag] = true
  end

  return res
end

local lint_unclosed_codeblocks = function(file_path, lines)
  local problems, is_in_codeblock = {}, false
  for i, l in ipairs(lines) do
    if not is_in_codeblock and is_codeblock_start(l) then
      is_in_codeblock = true
    elseif is_in_codeblock and is_codeblock_end(l) then
      is_in_codeblock = false
      if l:sub(1, 1) ~= '<' then append_problem(problems, file_path, i, 'code block is closed not with <') end
    end
  end
  return problems
end

local lint_inline_codeblocks = function(file_path, lines)
  local problems = {}
  for i, l in iter_noncode_lines(lines) do
    -- Use last line part after all valid inline codebloack
    local col = l:match('`.-`()') or 1
    while col ~= nil do
      l = l:sub(col)
      col = l:match('`.-`()')
    end

    -- Detect hanging backtick that is not a part of a tag link
    for s in vim.gsplit(l, '|.-|') do
      if s:find('`') ~= nil then append_problem(problems, file_path, i, 'Not proper inline code block') end
    end
  end
  return problems
end

local lint_single_quotes = function(file_path, lines)
  local gsub_nonlinks = function(line, pattern, f)
    for l in vim.gsplit(line, '`.-`') do
      for s in vim.gsplit(l, '|.-|') do
        s:gsub(pattern, f)
      end
    end
  end

  local problems, appended = {}, {}
  local append = function(lnum)
    if appended[lnum] then return end
    append_problem(problems, file_path, lnum, 'Bad single quote')
    appended[lnum] = true
  end
  for i, l in iter_noncode_lines(lines) do
    local f = function() append(i) end
    gsub_nonlinks(l, "%W'%w", f)
    gsub_nonlinks(l, "%w'%W", f)
    gsub_nonlinks(l, "%W'%W", f)
    gsub_nonlinks(l, "^'", f)
    gsub_nonlinks(l, "'$", f)
  end
  return problems
end

local is_good_tag = function(text)
  -- Have strict rules about allowed tags
  local is_good_name = text:find('^%*[Mm]ini') ~= nil or text:find('^%*:') ~= nil or text == '*randomhue*'
  local has_good_chars = text:find('[^%w%p]') == nil
  return is_good_name and has_good_chars
end

local lint_asterisks = function(file_path, lines)
  local problems = {}
  local append = function(lnum, text)
    if is_good_tag(text) then return end
    append_problem(problems, file_path, lnum, text .. ' is a bad tag')
  end
  for i, l in iter_noncode_lines(lines) do
    local f = function(tag) append(i, tag) end
    for s in vim.gsplit(l, '`.-`') do
      s:gsub('%*.-%*', f)
    end
  end
  return problems
end

local lint_bad_links = function(file_path, lines, tag_map)
  local nvim_version = vim.version().build
  local problems = {}
  local append = function(lnum, tag)
    if tag_map[tag] then return end
    local msg = 'link |' .. tag .. '| has not existing tag (in Neovim ' .. nvim_version .. ' or mini.nvim)'
    append_problem(problems, file_path, lnum, msg)
  end
  for i, l in iter_noncode_lines(lines) do
    local f = function(tag) append(i, tag) end
    for s in vim.gsplit(l, '`.-`') do
      s:gsub('|([%w%p]+)|', f)
    end
  end
  return problems
end

local lint_titles = function(file_path, lines)
  local problems = {}
  for i, l in iter_noncode_lines(lines) do
    if vim.startswith(l, '#') and not vim.endswith(l, '~') then
      append_problem(problems, file_path, i, 'Titles should end with ~')
    end
  end
  return problems
end

local lint_help = function()
  local help_tag_map = get_help_tag_map()
  local help_path = 'doc'

  local problems = {}
  for file, _ in vim.fs.dir(help_path) do
    local basename = file:match('^(.+)%.txt$')
    if basename ~= nil then
      local file_path = vim.fs.joinpath(help_path, file)
      local lines = vim.fn.readfile(file_path)

      vim.list_extend(problems, lint_unclosed_codeblocks(file_path, lines))
      vim.list_extend(problems, lint_inline_codeblocks(file_path, lines))
      vim.list_extend(problems, lint_single_quotes(file_path, lines))
      vim.list_extend(problems, lint_asterisks(file_path, lines))
      vim.list_extend(problems, lint_bad_links(file_path, lines, help_tag_map))
      vim.list_extend(problems, lint_titles(file_path, lines))
    end
  end

  -- if #problems == 0 then return end
  -- error(table.concat(problems, '\n'))
  return problems
end

-- Actual validation
local problems = lint_help()
local exit_code = #problems == 0 and 0 or 1
io.write('Generated documentation:\n')
local exit_status = exit_code == 0 and 'OK' or table.concat(problems, '\n')
io.write(exit_status .. '\n\n')

os.exit(exit_code)
