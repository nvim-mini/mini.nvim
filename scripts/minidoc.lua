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

local hooks = vim.deepcopy(MiniDoc.default_hooks)

hooks.write_pre = function(lines)
  -- Remove first two lines with `======` and `------` delimiters to comply
  -- with `:h local-additions` template
  table.remove(lines, 1)
  table.remove(lines, 1)
  return lines
end

MiniDoc.generate({ 'lua/mini/init.lua' }, 'doc/mini-nvim.txt', { hooks = hooks })

for _, m in ipairs(modules) do
  MiniDoc.generate({ 'lua/mini/' .. m .. '.lua' }, 'doc/mini-' .. m .. '.txt', { hooks = hooks })
end
