def with_role(user, role)
  assoc(user, :role, role)
end

test "with_role sets the role"
  assert with_role({name: "ana"}, :admin)[:role] == :admin
  assert with_role({name: "ana", role: :guest}, :admin)[:name] == "ana"
end
