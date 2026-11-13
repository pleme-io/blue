# waive B0085: rendering debt recorded 2026-11-13: no test of this generator declared kind: :rendering feeds its output to the output's reader yet
use("toriyose/danpen")

sdl = read_file(path_join(getenv("GEN_ROOT", "."), "schema.graphql"))

write_file(
  getenv("GEN_OUT", "schema.table"),
  toriyose::danpen::render(toriyose::danpen::parse(sdl), :table)
)

nil
