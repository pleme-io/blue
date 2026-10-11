; Generated from bidamas/kiwari by gen/kiwari/. Edit the spec and run `nix run .#regen`.
; A closed form indents its inside; its closer and its arms dedent.
[(arguments) (parenthesized_expression) (list) (map) (if) (unless) (def) (parameters) (defmacro) (case) (lambda) (test) (quote) (unquote) (unquote_splice)] @indent.begin
["end" ")" "]" "}"] @indent.end
["end" ")" "]" "}" "elsif" "else" "when"] @indent.branch
(comment) @indent.auto
