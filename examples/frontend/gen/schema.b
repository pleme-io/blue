use("danpen")

sdl = read_file(path_join(getenv("GEN_ROOT", "."), "schema.graphql"))

write_file(
  getenv("GEN_OUT", "schema.table"),
  danpen::render(danpen::parse(sdl), :table)
)

nil
