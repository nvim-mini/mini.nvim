_G.custom_script_result = 'This actually ran'

-- Buffer local and global configs should be later restored
MiniTest.config.aaa = true
vim.b.minitest_config = { aaa = true }
