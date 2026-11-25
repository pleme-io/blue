use("deeta", %i[read stringify write])

def agrees(text)
  want = json_parse(text) rescue :refused
  got = read(text) rescue :refused
  if want == :refused and got == :refused
    "both refuse"
  elsif to_s([got]) != to_s([want])
    "read differs"
  elsif stringify(want) != json_stringify(want)
    "stringify differs"
  elsif write(want) != json_write(want)
    "write differs"
  else
    "same"
  end
end
