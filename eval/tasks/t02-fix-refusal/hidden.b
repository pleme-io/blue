test "eval t02: with_role sets the role and keeps every other field"
  assert with_role({name: "ada"}, "admin") == {name: "ada", role: "admin"}
  assert with_role({name: "bo", role: "guest"}, "owner")[:role] == "owner"
  assert with_role({}, "x") == {role: "x"}
end
