# A bidama is a tree
#
# A bidama holds levels, as deep as it needs: a directory `sub/sub.b`, or a
# file that opens with `namespace()`. `casa::quarto::gaveta::meias` is the full
# path of a definition three levels down, and it always works. Importing a
# level brings everything below it into reach by its relative path, so after
# `use("casa/quarto")` the same name is `quarto::gaveta::meias` and
# `gaveta::meias`. Two imports that fit one shortcut are an error naming both,
# never load order. Every level is public, and a level never imports its
# ancestor.
#
# `use` spells one path many ways, and all of them load the same thing:
# `"a/b"`, `"a::b"`, `%i[a b]`, `%w[a b]`, `*%i[a b]` and `**%i[a b]`. After the
# path, `%i[x y]` lists names for bare use, `%w[b c]` imports several children,
# and `{b: %i[x], c: []}` imports them with their lists. `use({s: "a/b"})` gives
# a level a second name. A path is always a literal: the loader reads it before
# the program runs.
use("casa")
use("casa::cozinha")
use("casa/cozinha/pia", [:torneira])
use(%i[casa porta])
use(**%i[casa quarto])
use({g: "casa/quarto/gaveta"})
use(%w[casa quarto gaveta fundo])
use(*%i[casa sala])
use("casa/sala", ["luz"])
use("casa/sala", {mesa: [:pratos], tapete: []})

test "the full path works at every depth"
  assert casa::endereco == "rua 1"
  assert casa::cozinha::fogao == "fogao"
  assert casa::cozinha::pia::torneira == "torneira"
  assert casa::quarto::gaveta::meias.cor == "azul"
  assert casa::quarto::gaveta::fundo::carta == "carta"
end

test "a path relative to an import reaches the same definition"
  assert cozinha::fogao == "fogao"
  assert quarto::gaveta::meias == casa::quarto::gaveta::meias
  assert gaveta::meias.cor == "azul"
  assert gaveta::fundo::carta == "carta"
  assert fundo::carta == casa::quarto::gaveta::fundo::carta
end

test "a level may be one file"
  assert porta::chave == "chave"
  assert casa::porta::chave == "chave"
end

test "a listed name is bare, from any depth"
  assert torneira == "torneira"
  assert pratos == "pratos"
end

test "a second name reaches the level and everything below it"
  assert g::meias.cor == "azul"
  assert g::fundo::carta == "carta"
end

test "several children come from one form"
  assert mesa::pratos == pratos
  assert tapete::padrao == "listras"
  assert luz::lampada == "lampada"
  assert sala::sofa == "sofa"
end
