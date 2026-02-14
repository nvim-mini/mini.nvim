_G.lang_plugin_ftdetect = _G.lang_plugin_ftdetect or {}
table.insert(_G.lang_plugin_ftdetect, 'ftdetect/aaa.lua')

-- Set filetype 'aaa.lang' for file named 'lang.aaa'
vim.filetype.add({ filename = { ['lang.aaa'] = 'lang-aaa' } })
