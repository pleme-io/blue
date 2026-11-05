# A bidama is a tree, and every name in it has one spelling
#
# A bidama holds levels, as deep as it needs: a directory `sub/sub.b`, or a
# file that opens with `namespace()`. Every level is public, and a level never
# imports its ancestor.
#
# One way to import: `use("a/b")`, or `use("a/b", [:x])` to list names for
# bare use. A `use` of a level brings every level below it, so a file imports a
# tree once (B0078), and a path is a slash string, one level per `use` (B0077).
#
# One way to name: a qualified name is the full path of the level that defines
# it, `casa::quarto::gaveta::meias`, whatever the file imported (B0076). A name
# is bare only where the file lists it or its own level defines it (B0018). So
# `rg 'casa::quarto::gaveta::meias'` finds every caller that does not list it.
use("casa")

use("casa/cozinha/pia", [:torneira])

use("casa/sala/mesa", [:pratos])

test "a qualified name is the full path, at every depth"
  assert casa::endereco == "rua 1"
  assert casa::cozinha::fogao == "fogao"
  assert casa::quarto::gaveta::meias.cor == "azul"
  assert casa::quarto::gaveta::fundo::carta == "carta"
end

test "one use of the root reaches every level below it"
  assert casa::sala::sofa == "sofa"
  assert casa::sala::luz::lampada == "lampada"
  assert casa::sala::tapete::padrao == "listras"
end

test "a level may be one file"
  assert casa::porta::chave == "chave"
end

test "a listed name is bare, from any depth"
  assert torneira == "torneira"
  assert pratos == "pratos"
end
