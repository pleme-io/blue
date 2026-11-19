use("deeta", [:read])

def agrees(text)
  want = json_parse(text) rescue :refused
  if want == :refused
    "skipped"
  elsif (read(text) rescue :refused) == want
    "same"
  else
    "differs"
  end
end
