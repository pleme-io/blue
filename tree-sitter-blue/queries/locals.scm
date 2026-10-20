; Generated from bidamas/kiwari by gen/kiwari/. Edit the spec and run `nix run .#regen`.
; Scopes, the names they define, and the names that refer.
(def) @local.scope
(defmacro) @local.scope
(lambda) @local.scope
(arrow_lambda) @local.scope
(binding name: (identifier) @local.definition.var)
(def name: (identifier) @local.definition.function)
(parameters parameter: (identifier) @local.definition.parameter)
(defmacro name: (identifier) @local.definition.macro)
(identifier) @local.reference
