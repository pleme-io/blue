use("chuuzou", [:cz_host_image])

def main()
  write_stdout(unlines([cz_host_image(argv[0], argv[2], argv[1])]))
end
