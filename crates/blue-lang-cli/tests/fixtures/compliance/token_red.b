use("settei")

def parse_token(path)
  settei::prescribed("token", path)
end

def pure_token(text)
  json_parse(text)
end

test "a parse that reaches no host does not breach", {
  satisfies: [:nist_ac_6],
  target: pure_token
}
  assert_panics pure_token("{}")
end

test "a breach outside assert_panics ends the test", {
  satisfies: [:nist_ac_6],
  target: parse_token
}
  token = parse_token("/etc/hosts") rescue "swallowed"
  assert token == "swallowed"
end
