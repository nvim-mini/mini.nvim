H = {}

--- Remove (possibly not empty) directory
_G.remove_dir = function(path)
  local fs = vim.uv.fs_scandir(path)
  if not fs then
    vim.notify([[Couldn't open directory ]] .. path)
    return
  end

  local path_sep = package.config:sub(1, 1)
  while true do
    local f_name, _ = vim.uv.fs_scandir_next(fs)
    if f_name == nil then break end
    local p = ('%s%s%s'):format(path, path_sep, f_name)
    vim.uv.fs_unlink(p)
  end

  vim.uv.fs_rmdir(path)
end

_G.validate_doc_structure = function(x)
  H.validate_structure(x, 'doc', nil)

  for _, file in ipairs(x) do
    H.validate_structure(file, 'file', x)

    for _, block in ipairs(file) do
      H.validate_structure(block, 'block', file)

      for _, section in ipairs(block) do
        H.validate_structure(section, 'section', block)

        for _, line in ipairs(section) do
          if type(line) ~= 'string' then error('Section element is not a line.') end
        end
      end
    end
  end
end

-- Helper methods =============================================================
H.validate_structure = function(x, struct_type, parent)
  local type_string = vim.inspect(struct_type)

  if not H.is_structure(x, struct_type) then error(('Element is not %s structure.'):format(type_string)) end

  if parent == nil then return end

  if tostring(x.parent) ~= tostring(parent) then
    error(('%s structure has not correct `info.parent`.'):format(type_string))
  end

  if tostring(parent[x.parent_index]) ~= tostring(x) then
    error(('%s structure has not correct `info.parent_index`.'):format(type_string))
  end
end

H.info_fields = {
  section = { id = 'string', line_begin = 'number', line_end = 'number' },
  block = { afterlines = 'table', line_begin = 'number', line_end = 'number' },
  file = { path = 'string' },
  doc = { input = 'table', output = 'string', config = 'table' },
}

H.is_structure = function(x, struct_type)
  if not H.struct_has_elements(x) then return false end
  if not x.type == struct_type then return false end

  for info_name, info_type in pairs(H.info_fields[struct_type]) do
    if type(x.info[info_name]) ~= info_type then return false end
  end

  return true
end

H.struct_has_elements = function(x)
  -- Fields
  if not (type(x.info) == 'table' and type(x.type) == 'string') then return false end

  if x.parent ~= nil and not (type(x.parent) == 'table' and type(x.parent_index) == 'number') then return false end

  -- Methods
  for _, name in ipairs({ 'insert', 'remove', 'has_descendant', 'has_lines', 'clear_lines' }) do
    if type(x[name]) ~= 'function' then return false end
  end

  return true
end
