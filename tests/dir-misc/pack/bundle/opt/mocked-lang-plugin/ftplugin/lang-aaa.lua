_G.lang_plugin_ftplugin = _G.lang_plugin_ftplugin or {}
_G.lang_plugin_ftplugin[tostring(vim.api.nvim_get_current_buf())] = true
_G.lang_plugin_ftplugin['ftplugin/lang-aaa.lua'] = (_G.lang_plugin_ftplugin['ftplugin/lang-aaa.lua'] or 0) + 1
