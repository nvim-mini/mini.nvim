; Source: https://github.com/nvim-treesitter/nvim-treesitter-textobjects
[ (function_declaration) (function_definition) ] @function.outer

(function_declaration body: (_) @function.inner)
(function_definition body: (_) @function.inner)

; - Quantified captures (several captured nodes). Result range should cover
;   from left most node start to right most node end.
(parameters
  .
  (_) @parameter.inner @parameter.outer
  .
  ","? @parameter.outer)

(parameters
  "," @parameter.outer
  .
  (_) @parameter.inner @parameter.outer)

; Custom
[ (return_statement) ] @return.outer

(return_statement (expression_list (_) @return.inner))

(string) @string

((string) @string_offset (#offset! @string_offset 0 1 0 -2))

(chunk [(function_declaration) (assignment_statement)]* @chunk.inner) @chunk.outer
