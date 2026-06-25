-- NOTE: These are basic tests which cover basic functionliaty. A lot of
-- nuances are not tested to meet "complexity-necessity" trade-off.
local helpers = dofile('tests/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
local load_module = function(config) child.mini_load('doc', config) end
local unload_module = function() child.mini_unload('doc') end
local cd = function(path) child.cmd('cd ' .. path) end
local source_helpers = function() child.cmd('luafile tests/dir-doc/helpers.lua') end
local remove_dir = function(path) child.lua('_G.remove_dir(...)', { path }) end

-- Make helpers
local expect_equal_file_contents = function(file1, file2) eq(child.fn.readfile(file1), child.fn.readfile(file2)) end

-- Data =======================================================================
--stylua: ignore
local default_section_names = {
  '@alias',  '@class',    '@diagnostic', '@eval',
  '@field',  '@overload', '@param',      '@private',
  '@return', '@seealso',  '@signature',  '@tag',
  '@text',   '@toc',      '@toc_entry',  '@type',
  '@usage',
}

-- Output test set ============================================================
local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      load_module()
    end,
    post_once = child.stop,
  },
  n_retry = helpers.get_n_retry(1),
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  -- Global variable
  eq(child.lua_get('type(_G.MiniDoc)'), 'table')
end

T['setup()']['creates `config` field'] = function()
  eq(child.lua_get('type(_G.MiniDoc.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniDoc.config.' .. field), value) end
  local expect_config_function = function(field)
    local command = ('type(MiniDoc.config.%s)'):format(field)
    eq(child.lua_get(command), 'function')
  end
  local expect_sections = function(section_names)
    local t = child.lua_get('vim.tbl_keys(MiniDoc.config.hooks.sections)')
    table.sort(t)
    eq(t, section_names)

    for _, key in ipairs(t) do
      local command = string.format('type(MiniDoc.config.hooks.sections[%s])', vim.inspect(key))
      eq(child.lua_get(command), 'function')
    end
  end

  -- Check default values
  expect_config_function('annotation_extractor')
  expect_config('default_section_id', '@text')
  expect_config_function('hooks.block_pre')
  expect_config_function('hooks.section_pre')
  expect_sections(default_section_names)
  expect_config_function('hooks.section_post')
  expect_config_function('hooks.block_post')
  expect_config_function('hooks.file')
  expect_config_function('hooks.doc')
  expect_config_function('hooks.write_pre')
  expect_config_function('hooks.write_post')
  expect_config('script_path', 'scripts/minidoc.lua')
  expect_config('silent', false)
end

T['setup()']['respects `config` argument'] = function()
  unload_module()
  load_module({ default_section_id = 'aaa' })
  eq(child.lua_get('MiniDoc.config.default_section_id'), 'aaa')
end

T['setup()']['validates `config` argument'] = function()
  unload_module()

  local expect_config_error = function(config, name, target_type)
    expect.error(function() load_module(config) end, vim.pesc(name) .. '.*' .. vim.pesc(target_type))
  end

  local expect_sections_validation = function(section_names)
    expect_config_error({ hooks = { sections = 1 } }, 'hooks.sections', 'table')
    for _, s_name in ipairs(section_names) do
      expect_config_error({ hooks = { sections = { [s_name] = 1 } } }, 'hooks.sections.' .. s_name, 'function')
    end
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ annotation_extractor = 'a' }, 'annotation_extractor', 'function')
  expect_config_error({ default_section_id = 1 }, 'default_section_id', 'string')
  expect_config_error({ hooks = 1 }, 'hooks', 'table')
  expect_config_error({ hooks = { block_pre = 1 } }, 'hooks.block_pre', 'function')
  expect_config_error({ hooks = { section_pre = 1 } }, 'hooks.section_pre', 'function')
  expect_sections_validation(default_section_names)
  expect_config_error({ hooks = { section_post = 1 } }, 'hooks.section_post', 'function')
  expect_config_error({ hooks = { block_post = 1 } }, 'hooks.block_post', 'function')
  expect_config_error({ hooks = { file = 1 } }, 'hooks.file', 'function')
  expect_config_error({ hooks = { doc = 1 } }, 'hooks.doc', 'function')
  expect_config_error({ hooks = { write_pre = 1 } }, 'hooks.write_pre', 'function')
  expect_config_error({ hooks = { write_post = 1 } }, 'hooks.write_post', 'function')
  expect_config_error({ script_path = 1 }, 'script_path', 'string')
  expect_config_error({ silent = 1 }, 'silent', 'boolean')
end

T['default_hooks'] = new_set()

T['default_hooks']['is same as default `MiniDoc.config.hooks`'] = function()
  -- `vim.deep_equal()` tests equality of functions by their address, so this
  -- indeed tests what it should
  eq(child.lua_get('vim.deep_equal(MiniDoc.default_hooks, MiniDoc.config.hooks)'), true)
end

-- General overview of testing workflow:
-- - Tests are organized per test scope: collection of source code file with
--   annotations demonstrating similar functionality. Every test scope organized
--   in separate subdirectory of 'tests/dir-doc'.
-- - Testing is performed by evaluating `MiniDoc.generate()` (with possibly
--   non-default arguments) with current directory being equal to directory of
--   tested scope (for example, 'default-collation'). It will produce some
--   output help file ('doc/default-collation.txt' by default). Test is
--   performed by comparing its contents line by line with manually computed
--   reference file ('default-collation_reference.txt' by default).
-- - To add/update tests either:
--     - Update files in existing test scope and regenerate reference file (run
--       corresponding `MiniDoc.generate()` manually and save it to correct
--       '***_reference.txt' file).
--     - Add new test scope: create directory, add files, generate reference
--       help file, add separate test case.
T['generate()'] = new_set({
  hooks = {
    pre_case = function()
      -- Add inside child process some useful codebase
      source_helpers()

      -- Set current directory to one containing all input data for tests
      cd('tests/dir-doc')
    end,
  },
})

local validate_test_scope = function(test_scope_name)
  cd(test_scope_name)
  child.lua('MiniDoc.generate()')
  local output_path = ('doc/%s.txt'):format(test_scope_name)
  local reference_path = ('%s_reference.txt'):format(test_scope_name)
  expect_equal_file_contents(output_path, reference_path)

  -- Cleanup 'doc' subdirectory from current directory
  remove_dir('doc')
end

T['generate()']['uses correct default collation order'] = function() validate_test_scope('default-collation') end

T['generate()']['makes correct afterlines inference'] = function() validate_test_scope('inference') end

T['generate()']['handles sections correctly'] = function() validate_test_scope('sections') end

T['generate()']['respects arguments'] = function()
  unload_module()

  -- Add project root to runtimepath to be able to `require('mini.doc')`
  child.cmd('set rtp+=../..')
  child.lua([[
      require('mini.doc').setup({
        hooks = {
          section_post = function(s)
            s:insert('This line should be added in `section_post` hook.')
          end,
        },
      })
    ]])

  cd('arguments')
  child.lua([[
      MiniDoc.generate({ 'file.lua' }, 'output.txt', {
        annotation_extractor = function(l)
          return string.find(l, '^%-%-(%S*) ?')
        end,
      })
    ]])

  expect_equal_file_contents('output.txt', 'output_reference.txt')

  -- Cleanup
  child.loop.fs_unlink('output.txt')
end

T['generate()']['respects `vim.b.minidoc_config`'] = function()
  child.b.minidoc_config = { script_path = 'buffer-local_script.lua' }
  child.lua('MiniDoc.generate()')
  eq(child.lua_get('_G.is_inside_buffer_local_script'), true)
  eq(child.b.minidoc_config, { script_path = 'buffer-local_script.lua' })
end

T['generate()']['returns correct data structure'] = function()
  child.cmd('luafile helpers.lua')
  cd('structure')

  expect.no_error(function() child.lua('_G.validate_doc_structure(MiniDoc.generate())') end)

  remove_dir('doc')
end

T['generate()']['uses custom script'] = function()
  -- Add project root to runtimepath to be able to `require('mini.doc')`
  child.cmd('set rtp+=../..')
  cd('custom-script')
  child.lua([[MiniDoc.config.script_path = 'gendoc/gendoc-script.lua']])

  -- This should execute 'gendoc/gendoc-script.lua' and return what it returns
  expect.no_error(function() child.lua('_G.validate_doc_structure(MiniDoc.generate())') end)
  expect_equal_file_contents('output.txt', 'output_reference.txt')

  -- Script is executed only if all arguments are `nil` (default).
  child.lua([[MiniDoc.generate({ 'init.lua' })]])
  expect_equal_file_contents('doc/custom-script.txt', 'output_reference.txt')
  eq(child.lua_get('type(MiniDoc.config.aaa)'), 'nil')

  -- Cleanup
  child.loop.fs_unlink('output.txt')
  remove_dir('doc')
end

return T
