_G.Months = {}

--stylua: ignore
Months.items = {
  { name = 'January',   kind = 1 },
  { name = 'February',  kind = 1 },
  { name = 'March',     kind = 2 },
  { name = 'April',     kind = 2 },
  { name = 'May',       kind = 2 },
  { name = 'June',      kind = 3 },
  { name = 'July',      kind = 3 },
  { name = 'August',    kind = 3 },
  { name = 'September', kind = 4 },
  { name = 'October',   kind = 4 },
  { name = 'November',  kind = 4 },
  { name = 'December',  kind = 1 },
}

--stylua: ignore
local markdown_info = {
  -- Should remove all blank lines from the top
  '',
  '  ',
  '# Month #07',
  -- Should collapse multiple blank lines into one
  '',
  ' ',
  '\t',
  -- Should replace section separator with continuous one spanning window width
  '---',
  '',
  -- Should conceal special characters and highlight
  'This *is* __markdown__ text',
  '',
  ' ',
  -- Should conceal code block characters *and* remove all blank lines before
  -- and after code block (as those will be displayed as empty themselves)
  '```lua',
  'local a = 1',
  '```',
  -- Should remove all blank lines from the bottom
  ' ',
  '',
  '\t',
  ' ',
  '',
}

--stylua: ignore
Months.data = {
  January   = { documentation = 'Month #01' },
  February  = { documentation = 'a\nb\nc\nd\ne\nf\ng\nh' },
  March     = { documentation = 'Month #03' },
  April     = { documentation = 'Month #04', detail = '\n  local a = "New info"  \n  \n' },
  May       = { documentation = nil },
  June      = { documentation = 'Month #06' },
  July      = { documentation = table.concat(markdown_info, '\n') },
  August    = { documentation = 'Month #08', detail = 'Month' },
  September = { documentation = nil,         detail = 'Sep' },
  October   = { documentation = 'Month #10' },
  November  = { documentation = 'Month #11' },
  December  = { documentation = string.rep('a ', 1000) },
}

Months.client = {
  name = 'months-lsp',
  offset_encoding = 'utf-16',
  server_capabilities = {
    completionProvider = { resolveProvider = true, triggerCharacters = { '.' } },
    signatureHelpProvider = { triggerCharacters = { '(', ',' } },
    executeCommandProvider = { commands = { 'add_import' } },
  },
}

local construct_additionTextEdits = function(id, name)
  return {
    {
      newText = ('from months.%s import %s\n'):format(id, name),
      range = {
        start = { line = 0, character = 0 },
        ['end'] = { line = 0, character = 0 },
      },
    },
  }
end

local construct_textEdit = function(name, kind)
  if _G.mock_textEdit == nil then return end
  local new_text, pos = _G.mock_textEdit.new_text, _G.mock_textEdit.pos
  local is_insertreplaceedit = kind == 'InsertReplaceEdit'
  local range = {
    start = { line = pos[1] - 1, character = pos[2] - 1 },
    ['end'] = { line = pos[1] - 1, character = pos[2] },
  }
  return {
    newText = new_text(name),
    [is_insertreplaceedit and 'insert' or 'range'] = range,
    replace = is_insertreplaceedit and range or nil,
  }
end

local construct_filterText = function(name)
  if _G.mock_filterText == nil then return end
  return _G.mock_filterText(name)
end

-- Log actual table params for testing proper requests
_G.params_log = {}

local requests = {
  initialize = function(_) return { capabilities = Months.client.server_capabilities } end,
  shutdown = function(_) return nil end,

  ['textDocument/completion'] = function(params)
    -- Count actual requests for easier "force completion" tests
    _G.n_textdocument_completion = (_G.n_textdocument_completion or 0) + 1

    params = type(params) == 'function' and params(Months.client, vim.api.nvim_get_current_buf()) or params
    table.insert(_G.params_log, { method = 'textDocument/completion', params = vim.deepcopy(params) })

    -- Imitate returning nothing in comments
    local line = vim.fn.getline(params.position.line + 1)
    if line:find('^%s*#') ~= nil then return { items = {} } end

    local items = {}
    for i, item in ipairs(Months.items) do
      local res = { label = item.name, kind = item.kind, sortText = ('%03d'):format(i) }
      -- Mock `additionalTextEdits` as in `pyright`
      if item.name == 'September' or item.name == 'November' then
        res.additionalTextEdits = construct_additionTextEdits('completion', item.name)
      end

      if item.name == 'April' then
        res.textEdit = construct_textEdit(item.name, 'InsertReplaceEdit')
        res.textEditText = _G.mock_itemdefaults ~= nil and 'New April' or nil
        res.filterText = construct_filterText(item.name)
      end
      if item.name == 'August' then
        res.textEdit = construct_textEdit(item.name, 'textEdit')
        res.textEditText = _G.mock_itemdefaults ~= nil and 'New August' or nil
        res.filterText = construct_filterText(item.name)
      end

      table.insert(items, res)
    end

    -- Mock incomplete computation
    if _G.mock_isincomplete then items = vim.list_slice(items, 1, 6) end

    return { items = items, isIncomplete = _G.mock_isincomplete, itemDefaults = _G.mock_itemdefaults }
  end,

  ['completionItem/resolve'] = function(params)
    table.insert(_G.params_log, { method = 'completionItem/resolve', params = vim.deepcopy(params) })

    -- Count actual requests for easier tests
    _G.n_completionitem_resolve = (_G.n_completionitem_resolve or 0) + 1

    local data = Months.data[params.label]
    if data == nil then return params end

    local doc = data.documentation
    if doc ~= nil then params.documentation = { kind = 'markdown', value = doc } end
    params.detail = data.detail

    -- Mock additionalTextEdits as in `typescript-language-server`
    if params.label == 'October' or params.label == 'November' then
      params.additionalTextEdits = construct_additionTextEdits('resolve', params.label)
    end

    -- Mock resolving text to be inserted (which should usually not happen, but
    -- it still might)
    if params.label == 'May' then params.insertText = 'Resolved $1 May' end

    return params
  end,

  ['textDocument/signatureHelp'] = function(params)
    params = type(params) == 'function' and params(Months.client, vim.api.nvim_get_current_buf()) or params
    table.insert(_G.params_log, { method = 'textDocument/completion', params = vim.deepcopy(params) })

    local n_line, n_col = params.position.line, params.position.character
    local line = vim.api.nvim_buf_get_lines(0, n_line, n_line + 1, false)[1]
    line = line:sub(1, n_col)

    local after_open_paren = line:match('%(.*$') or line
    local after_close_paren = line:match('%).*$') or line

    -- Stop showing signature help after closing bracket
    if after_close_paren:len() < after_open_paren:len() then return { signatures = {} } end

    -- Compute active parameter id by counting number of ',' from latest '('
    local _, active_param_id = after_open_paren:gsub('%,', '%,')

    -- Compute what is displayed in signature help: text and parameter info
    -- (for highlighting) based on latest function call
    local word = line:match('(%S+%()[^%(]*$')
    local label, parameters
    if word == 'long(' then
      label = string.rep('a ', 1000)
    elseif word == 'string.format(' then
      label = 'function string.format(s:string|number, ...any)'
    elseif word == 'multiline(' then
      label = 'multiline(\narg1,\narg2)'
      parameters = { { label = 'arg1' }, { label = 'arg2' } }
    elseif word == 'bad_signature(' then
      label = 'bad_signature(param1)'
      parameters = { { label = 'not-substring' } }
    elseif word == 'scroll(' then
      label = 'aaa bbb ccc ddd eee fff ggg hhh'
    elseif word == 'short(' then
      label = line:match('^short%(aa,') and 'bbbbbbbbbbb' or 'aa'
    else
      label = 'abc(param1, param2)'
      parameters = { { label = { 4, 10 } }, { label = { 12, 18 } } }
    end

    -- Construct output
    local signature = { activeParameter = active_param_id, label = label, parameters = parameters }
    return { signatures = { signature } }
  end,

  ['workspace/executeCommand'] = function(params)
    table.insert(_G.params_log, { method = 'workspace/executeCommand', params = vim.deepcopy(params) })
  end,
}

-- Start an actual LSP server -------------------------------------------------
_G.lines_at_request = {}

local cmd = function(dispatchers)
  -- Adaptation of `MiniSnippets.start_lsp_server()` implementation
  local is_closing, request_id = false, 0

  return {
    request = function(method, params, callback)
      table.insert(_G.lines_at_request, vim.api.nvim_get_current_line())

      -- Mock relevant methods with possible error
      local err = (_G.mock_error or {})[method]
      local method_impl = err ~= nil and function() return nil end or requests[method]
      if method_impl and _G.mock_request_delay == nil then callback(err, method_impl(params)) end
      if method_impl and _G.mock_request_delay ~= nil then
        vim.defer_fn(function() callback(err, method_impl(params)) end, _G.mock_request_delay)
      end

      request_id = request_id + 1
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

-- NOTE: set `root_dir` for a working `reuse_client` on Neovim<0.11
_G.months_lsp_client_id = vim.lsp.start({ name = Months.client.name, cmd = cmd, root_dir = vim.fn.getcwd() })

local gr = vim.api.nvim_create_augroup('months-lsp-auto-attach', { clear = true })
local auto_attach = function(ev)
  if not vim.api.nvim_buf_is_valid(ev.buf) then return end
  vim.lsp.buf_attach_client(ev.buf, _G.months_lsp_client_id)
end
vim.api.nvim_create_autocmd('BufEnter', { group = gr, callback = auto_attach })
