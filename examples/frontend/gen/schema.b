use("toriyose/danpen")

sdl = read_file(path_join(getenv("GEN_ROOT", "."), "schema.graphql"))

write_file(
  getenv("GEN_OUT", "schema.table"),
  toriyose::danpen::render(toriyose::danpen::parse(sdl), :table)
)

nil
