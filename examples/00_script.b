#!/usr/bin/env blue
# A script
#
# A file is a program. `blue examples/00_script.b one two` runs this one, and
# so does `./examples/00_script.b one two`, because its first line names blue
# and the file is executable. No Bluefile and no BLUE_PATH are needed: the
# standard bidamas are compiled into blue, and a script inside a project also
# reaches the project's own packages. argv() is what follows the file. A
# script prints only what it writes, where `blue run` also prints the last
# value, and `blue test` runs its tests. When a script outgrows one file,
# `blue new NAME` starts a project around it.
use("retsu", [:is_empty])

# The arguments as one shouted line, or how to call the script.
def shout(args)
  if is_empty(args)
    "usage: 00_script.b WORD..."
  else
    upcase(join(args, " "))
  end
end

test "it shouts every argument"
  assert shout(["one", "two"]) == "ONE TWO"
end

test "with no arguments it says how to call it"
  assert shout([]) == "usage: 00_script.b WORD..."
end

write_stdout("#{shout(argv())}\n")
