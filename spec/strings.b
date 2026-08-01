# blue's string core.
#
# tatara-lisp has no string operations at all; these are blue's, with Ruby's
# semantics — `length` counts CHARACTERS, not bytes.

test "length counts characters, not bytes"
  assert length("hello") == 5
  assert length("héllo") == 5
  assert length("😀") == 1
end
test "case and trim"
  assert upcase(
    "abc"
  ) == "ABC"
  assert downcase("ABC") == "abc"
  assert trim("  hi  ") == "hi"
end
test "concat, not plus"
  assert concat("a", "b") == "ab"
  assert "n=#{42}" == "n=42"
end
test "split and join round-trip"
  assert join(split("a,b,c", ","), "-") == "a-b-c"
end
test "predicates"
  assert contains?(
    "hello",
    "ell"
  )
  assert starts_with?("hello", "he")
  assert ends_with?("hello", "lo")
end
test "reverse is character-wise"
  assert reverse("héllo") == "olléh"
end
test "to_int is nil on garbage, not zero"
  assert to_int("42") == 42
  assert to_int("banana") == nil
end
