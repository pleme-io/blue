use("chuuzou", [:cz_def_image])

def main()
  write_stdout(
    unlines(
      [
        cz_def_image(
          env_required("DEF_SLICE"),
          env_required("DEF_ENTRY"),
          env_required("DEF_SEAM"),
          env_required("DEF_OUT")
        )
      ]
    )
  )
end
