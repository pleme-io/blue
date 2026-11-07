; Generated from bidamas/kiwari by gen/kiwari/. Edit the spec and run `nix run .#regen`.
; The general first: neovim lets the last matching pattern win.
(comment) @comment
(expectation) @punctuation.special.doctest
(record_head) @keyword
(identifier) @variable
(label) @property
(integer) @number
(float) @number.float
(symbol) @string.special.symbol
(word_list) @string
(true) @boolean
(false) @boolean
(nil) @constant.builtin
(string) @string
(escape_sequence) @string.escape
(interpolation) @none
(doc_open) @punctuation.delimiter.documentation
(doc_close) @punctuation.delimiter.documentation
(doc_line) @comment.documentation
(doc_block) @markup.raw.block
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
(type name: (qualified_name) @type)
(defmacro name: (identifier) @function.macro)
["(" ")" "[" "]" "{" "}"] @punctuation.bracket
["," "." "::"] @punctuation.delimiter
["=" "||" "∨" "&&" "∧" "==" "≡" "!=" "≠" "<" "<=" "≤" ">" ">=" "≥" "+" "-" "−" "*" "×" "/" "÷" "%" "|>" "!" "¬" "**" "=>" "->"] @operator
["rescue" "begin" "as" "ensure"] @keyword.exception
["or" "and" "not"] @keyword.operator
["end" "test" "assert" "assert_panics" "quote" "unquote" "unquote_splice"] @keyword
["#{"] @punctuation.special
["if" "unless" "elsif" "else" "case" "when"] @keyword.conditional
["def" "defmacro" "fn"] @keyword.function
["return"] @keyword.return
["@moduledoc" "@doc"] @attribute.documentation
