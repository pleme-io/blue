@moduledoc """
toriyose (取り寄せ, fetching on order) — what a frontend asks for and keeps.

Three levels: `toriyose/danpen` (GraphQL documents: one grammar, parsed,
checked and rendered), `toriyose/outou` (a request answered over danpen's
documents) and `toriyose/kyasshu` (the normalized entity store of the
frontend data runtime). The root defines nothing; a `use("toriyose")` brings
all three.

    toriyose::kyasshu::key(["User", 7]) #=> "User:7"
"""

test "the root reaches each of its levels by its full path"
  assert toriyose::kyasshu::key(["User", 7]) == "User:7"
  assert toriyose::danpen::render(toriyose::danpen::parse("{a}")) ==
    unlines(["{", "  a", "}"])
  assert toriyose::outou::request(
    toriyose::outou::fixture,
    "{ hero { id } }"
  ) == {data: {"hero" => {"id" => "2001"}}}
end
