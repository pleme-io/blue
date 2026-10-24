use("danpen")
use("gamen", [:labels])

card = danpen::fragment(
  :user_card,
  {on: "User", fields: [:name, :tone, {avatar: [:url]}]}
)

page = danpen::fragment(
  :profile,
  {on: "Query", fields: [{user: [:id, "...user_card"]}]}
)

TONES = labels(:Tone, {WARM: "Warm", COOL: "Cool"})

def user_card(user: UserCard)
  "#{user.name} (#{get(TONES.entries, user.tone)}) #{user.avatar.url}"
end

def profile(data: Profile)
  user_card(data.user)
end

test "a profile renders the card from the one response"
  response = json_read("{\"user\": {\"id\": \"1\", \"name\": \"Ana\", \"tone\": \"WARM\", \"avatar\": {\"url\": \"https://img/1\"}}}")
  assert profile(response) == "Ana (Warm) https://img/1"
end

test "the operation is the union of the view's and the card's fragments"
  op = danpen::render(danpen::compose(page, [card]), :compact)
  assert starts_with?(
    op,
    "query Profile { ...profile } fragment profile on Query"
  )
  assert danpen::hash(danpen::compose(page, [card])) ==
    danpen::hash(danpen::parse(op))
end
