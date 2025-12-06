local minidoc = require('mini.doc')

if _G.MiniDoc == nil then minidoc.setup() end

local modules = {
  'ai',
  'align',
  'animate',
  'base16',
  'basics',
  'bracketed',
  'bufremove',
  'clue',
  'cmdline',
  'colors',
  'comment',
  'completion',
  'cursorword',
  'deps',
  'diff',
  'doc',
  'extra',
  'files',
  'fuzzy',
  'git',
  'hipatterns',
  'hues',
  'icons',
  'indentscope',
  'jump',
  'jump2d',
  'keymap',
  'map',
  'misc',
  'move',
  'notify',
  'operators',
  'pairs',
  'pick',
  'sessions',
  'snippets',
  'splitjoin',
  'starter',
  'statusline',
  'surround',
  'tabline',
  'test',
  'trailspace',
  'visits',
}

MiniDoc.generate({ 'lua/mini/init.lua' }, 'doc/mini-nvim.txt')

for _, m in ipairs(modules) do
  MiniDoc.generate({ 'lua/mini/' .. m .. '.lua' }, 'doc/mini-' .. m .. '.txt')
end
