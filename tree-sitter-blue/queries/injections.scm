; Generated from bidamas/kiwari by gen/kiwari/. Edit the spec and run `nix run .#regen`.
; Text that is another language's source: a doc's prose is Markdown, its examples blue.
([(doc_line) (doc_blank) (doc_block)] @injection.content (#set! injection.language "markdown") (#set! injection.combined))
((doc_example [(doc_code) (doc_check)] @injection.content) (#set! injection.language "blue"))
((expectation) @injection.content (#offset! @injection.content 0 3 0 0) (#set! injection.language "blue"))
