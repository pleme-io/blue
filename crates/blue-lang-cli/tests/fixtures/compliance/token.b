use("settei")

def parse_token(path)
  settei::prescribed("token", path)
end

test "a token is parsed in isolation from the filesystem", {
  satisfies: [:nist_ac_6],
  target: parse_token
}
  assert_panics parse_token("/etc/hosts")
end
