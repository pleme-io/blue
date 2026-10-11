; Generated from bidamas/kiwari by gen/kiwari/. Edit the spec and run `nix run .#regen`.
; The general first: neovim lets the last matching pattern win.
(comment) @comment
(identifier) @variable
(label) @property
(integer) @number
(float) @number.float
(symbol) @string.special.symbol
(true) @boolean
(false) @boolean
(nil) @constant.builtin
(string) @string
(escape_sequence) @string.escape
(interpolation) @none
(binding name: (identifier) @variable)
(call function: (identifier) @function.call)
(call function: (qualified_name) @function.call)
(send method: (identifier) @function.method.call)
(qualified_name package: (identifier) @module)
(qualified_name package: (package) @module)
(def name: (identifier) @function)
(parameters parameter: (identifier) @variable.parameter)
(typed_parameter name: (label) @variable.parameter)
(type name: (identifier) @type)
(defmacro name: (identifier) @function.macro)
["=" "||" "∨" "&&" "∧" "==" "≡" "!=" "≠" "<" "<=" "≤" ">" ">=" "≥" "+" "-" "−" "*" "×" "/" "÷" "%" "|>" "!" "¬" "=>" "->"] @operator
["." "," "::"] @punctuation.delimiter
["(" ")" "[" "]" "{" "}"] @punctuation.bracket
["#{"] @punctuation.special
["if" "unless" "elsif" "else" "case" "when"] @keyword.conditional
["end" "test" "assert" "quote" "unquote" "unquote_splice"] @keyword
["def" "defmacro" "fn"] @keyword.function
