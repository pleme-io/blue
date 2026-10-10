# A rule that reaches for the filesystem.

def peek(form)
  read_file("/etc/hosts")
  []
end
