local resolve_provider = true
if _G.mock_no_resolve then resolve_provider = false end
local capabilities = { completionProvider = { resolveProvider = resolve_provider } }

local requests = {
  initialize = function(_) return { capabilities = capabilities } end,
  shutdown = function(_) return nil end,

  ['textDocument/completion'] = function(_)
    return {
      { label = 'Apple', insertText = 'Fruit Apple', documentation = 'Apple fruit' },
      { label = 'Jackfruit', insertText = 'Fruit Jack' },
    }
  end,

  ['completionItem/resolve'] = function(params)
    _G.n_completionitem_resolve = (_G.n_completionitem_resolve or 0) + 1
    params.documentation = { kind = 'markdown', value = params.label .. ' is a fruit' }
    return params
  end,
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
_G.fruits_lsp_client_id = vim.lsp.start({ name = 'fruits-lsp', cmd = cmd, root_dir = _G.root_dir or vim.fn.getcwd() })
