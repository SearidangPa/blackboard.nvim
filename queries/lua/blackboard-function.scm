; Standard function declarations
(function_declaration
  name: (identifier) @name) @function

; Local function definitions
(function_definition
  name: (identifier) @name) @function

; M.func = function() pattern (assigned functions)
(assignment_statement
  (variable_list
    (dot_index_expression
      field: (identifier) @name))
  (expression_list
    (function_definition))) @function

; local func = function() pattern
(assignment_statement
  (variable_list
    (identifier) @name)
  (expression_list
    (function_definition))) @function
