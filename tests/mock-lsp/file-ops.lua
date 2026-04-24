local server_name = _G.server_name or 'file-methods-lsp'
_G.lsp_requests = _G.lsp_requests or {}
_G.lsp_notifications = _G.lsp_notifications or {}

_G.filter_configs = _G.filter_configs or { filters = { { pattern = { glob = '**' } } } }
local fc = _G.filter_configs
local file_operations_config = _G.file_operations_config
  or { willCreate = fc, willDelete = fc, willRename = fc, didCreate = fc, didDelete = fc, didRename = fc }

local capabilities = { workspace = { fileOperations = file_operations_config } }

local make_will_request = function(method)
  return function(params)
    _G.lsp_requests[server_name] = _G.lsp_requests[server_name] or {}
    table.insert(_G.lsp_requests[server_name], { method, params })
    return _G.workspace_edit_response
  end
end

_G.did_callback = _G.did_callback or function(_, _) end

local make_did_notification = function(method)
  return function(params, dispatchers)
    _G.lsp_notifications[server_name] = _G.lsp_notifications[server_name] or {}
    table.insert(_G.lsp_notifications[server_name], { method, params })
    _G.did_callback(params, dispatchers)
  end
end

local requests = {
  initialize = function(_) return { capabilities = capabilities } end,
  shutdown = function(_) return nil end,

  ['workspace/willCreateFiles'] = make_will_request('workspace/willCreateFiles'),
  ['workspace/willRenameFiles'] = make_will_request('workspace/willRenameFiles'),
  ['workspace/willDeleteFiles'] = make_will_request('workspace/willDeleteFiles'),
}

local notifications = {
  ['workspace/didCreateFiles'] = make_did_notification('workspace/didCreateFiles'),
  ['workspace/didRenameFiles'] = make_did_notification('workspace/didRenameFiles'),
  ['workspace/didDeleteFiles'] = make_did_notification('workspace/didDeleteFiles'),
}

local cmd = function(dispatchers)
  local is_closing, request_id = false, 0

  return {
    request = function(method, params, callback)
      local method_impl = requests[method]
      if method_impl ~= nil then callback(nil, method_impl(params)) end
      request_id = request_id + 1
      return true, request_id
    end,
    notify = function(method, params)
      local method_impl = notifications[method]
      if method_impl ~= nil then method_impl(params, dispatchers) end
      return true
    end,
    is_closing = function() return is_closing end,
    terminate = function() is_closing = true end,
  }
end

-- Start server and attach to current buffer
return vim.lsp.start({ name = server_name, cmd = cmd, root_dir = vim.fn.getcwd() })
