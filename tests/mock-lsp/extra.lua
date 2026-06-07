_G.lsp_requests = {}

local capabilities = {
  declarationProvider = true,
  definitionProvider = true,
  documentSymbolProvider = true,
  implementationProvider = true,
  referencesProvider = true,
  typeDefinitionProvider = true,
  workspaceSymbolProvider = true,
}

local new_location = function(uri, from_line, from_col, to_line, to_col)
  return {
    uri = uri,
    range = { start = { line = from_line, character = from_col }, ['end'] = { line = to_line, character = to_col } },
  }
end

local make_location_request = function(method)
  return function(params)
    table.insert(_G.lsp_requests, method)
    return { new_location(params.textDocument.uri, 2, 15, 2, 16) }
  end
end

local make_symbol_request = function(method)
  return function(params)
    table.insert(_G.lsp_requests, method)
    _G.params = params
    local symbol_kind = vim.lsp.protocol.SymbolKind
    return {
      {
        name = 'a',
        kind = symbol_kind.Number,
        range = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 11 } },
        selectionRange = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 7 } },
      },
      {
        name = 't',
        kind = symbol_kind.Object,
        range = { start = { line = 1, character = 6 }, ['end'] = { line = 4, character = 1 } },
        selectionRange = { start = { line = 1, character = 6 }, ['end'] = { line = 1, character = 7 } },
        children = {
          -- NOTE: Deliberately use not a natural order to test picker's sort
          {
            name = 'y',
            kind = symbol_kind.Variable,
            range = { start = { line = 3, character = 2 }, ['end'] = { line = 3, character = 20 } },
            selectionRange = { start = { line = 3, character = 2 }, ['end'] = { line = 3, character = 3 } },
          },
          {
            name = 'x',
            kind = symbol_kind.Variable,
            range = { start = { line = 2, character = 2 }, ['end'] = { line = 2, character = 20 } },
            selectionRange = { start = { line = 2, character = 2 }, ['end'] = { line = 2, character = 3 } },
          },
        },
      },
    }
  end
end

local requests = {
  initialize = function(_) return { capabilities = capabilities } end,
  shutdown = function(_) return nil end,

  -- Location methods
  ['textDocument/declaration'] = make_location_request('textDocument/declaration'),
  ['textDocument/definition'] = make_location_request('textDocument/definition'),
  ['textDocument/implementation'] = make_location_request('textDocument/implementation'),
  ['textDocument/typeDefinition'] = make_location_request('textDocument/typeDefinition'),
  ['textDocument/references'] = function(params)
    table.insert(_G.lsp_requests, 'textDocument/references')
    return {
      new_location(params.textDocument.uri, 0, 6, 0, 7),
      new_location(params.textDocument.uri, 2, 15, 2, 16),
      new_location(params.textDocument.uri, 3, 15, 3, 16),
    }
  end,

  -- Symbols methods
  ['textDocument/documentSymbol'] = make_symbol_request('textDocument/documentSymbol'),
  ['workspace/symbol'] = make_symbol_request('workspace/symbol'),
}

local cmd = function(dispatchers)
  -- Adaptation of `MiniSnippets.start_lsp_server()` implementation
  local is_closing, request_id = false, 0

  return {
    request = function(method, params, callback)
      local method_impl = requests[method]
      if method_impl ~= nil then callback(nil, method_impl(params)) end
      request_id = request_id + 1
      return true, request_id
    end,
    notify = function(method, params) return false end,
    is_closing = function() return is_closing end,
    terminate = function() is_closing = true end,
  }
end

-- Start server and attach to current buffer
return vim.lsp.start({ name = 'extra-lsp', cmd = cmd, root_dir = vim.fn.getcwd() })
