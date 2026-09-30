# Link an emitted program into an image for its board and measure it: the ELF
# and size.tsv (one row of BLUE-NATIVE.md's size ledger) into $IMAGE_OUT.
#
#   IMAGE_RS     the emitted Rust (packages.generated-<name>)
#   IMAGE_BOARD  the board's name in kiban
#   IMAGE_SEAM   the seam sources (native/seam)
#   IMAGE_NAME   the image's name
use("chuuzou", [:cz_link, :cz_measure, :cz_size_tsv])

out = env_required("IMAGE_OUT")
board = env_required("IMAGE_BOARD")
name = env_required("IMAGE_NAME")

elf = cz_link(
  env_required("IMAGE_RS"),
  board,
  env_required("IMAGE_SEAM"),
  out,
  name
)

write_file(
  path_join(out, "size.tsv"),
  cz_size_tsv(name, board, cz_measure(elf))
)
