space("tegata", {status: :ratified})

verb(
  "tegata",
  "acquire",
  {
    kind: :effect,
    shape: "acquire(provider, opts) -> token",
    laterals: %w[cache resource retry],
    fleet: nil,
    today: "absent",
    meaning: "machine token by client credentials, reused until near expiry",
    wave: 2,
    origin: "D"
  }
)

verb(
  "tegata",
  "api_key",
  {
    kind: :effect,
    shape: "api_key(prefix, opts) -> record",
    laterals: %w[capability validate],
    fleet: nil,
    today: "absent",
    meaning: "long-lived key: id, secret shown once, stored hash",
    wave: 2,
    origin: "D"
  }
)

verb(
  "tegata",
  "api_key_valid?",
  {
    kind: :pure,
    shape: "api_key_valid?(secret, record) -> Bool",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "presented key matches the stored hash in equal time",
    wave: 2,
    origin: "D"
  }
)

verb(
  "tegata",
  "assertion",
  {
    kind: :pure,
    shape: "assertion(xml, trust, opts) -> record",
    laterals: %w[error time validate],
    fleet: nil,
    today: "absent",
    meaning: "SAML assertion with signature, conditions and audience checked",
    wave: 4,
    origin: "D"
  }
)

verb(
  "tegata",
  "attenuate",
  {
    kind: :pure,
    shape: "attenuate(token, caveat) -> token",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "add a restriction to a token; it can never widen",
    wave: 3,
    origin: "D"
  }
)

verb(
  "tegata",
  "discover",
  {
    kind: :effect,
    shape: "discover(issuer) -> record",
    laterals: %w[cache deadline resource],
    fleet: nil,
    today: "absent",
    meaning: "an issuer's OpenID configuration document",
    wave: 2,
    origin: "D"
  }
)

verb(
  "tegata",
  "exchange",
  {
    kind: :effect,
    shape: "exchange(token, audience, opts) -> token",
    laterals: %w[resource validate],
    fleet: nil,
    today: "absent",
    meaning: "trade a token for one narrower or for another service",
    wave: 3,
    origin: "D"
  }
)

verb(
  "tegata",
  "expired?",
  {
    kind: :pure,
    shape: "expired?(token, now) -> Bool",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "token is past its expiry, signature unchecked",
    wave: 1,
    origin: "D"
  }
)

verb(
  "tegata",
  "flow_finish",
  {
    kind: :effect,
    shape: "flow_finish(provider, callback, saved) -> tokens",
    laterals: %w[error resource validate],
    fleet: nil,
    today: "absent",
    meaning: "check the callback and trade its code for tokens",
    wave: 2,
    origin: "D"
  }
)

verb(
  "tegata",
  "flow_start",
  {
    kind: :effect,
    shape: "flow_start(provider, opts) -> record",
    laterals: %w[capability time],
    fleet: nil,
    today: "absent",
    meaning: "OAuth2 sign-in URL with state and PKCE verifier",
    wave: 2,
    origin: "D"
  }
)

verb(
  "tegata",
  "introspect",
  {
    kind: :effect,
    shape: "introspect(token, opts) -> record",
    laterals: %w[cache deadline resource],
    fleet: nil,
    today: "absent",
    meaning: "ask the issuer whether a token is still active",
    wave: 3,
    origin: "D"
  }
)

verb(
  "tegata",
  "issue",
  {
    kind: :effect,
    shape: "issue(claims, key, opts) -> token",
    laterals: %w[capability time validate],
    fleet: "pleme-auth-tokens",
    today: "absent",
    meaning: "mint a signed token with expiry and audience",
    wave: 1,
    origin: "D"
  }
)

verb(
  "tegata",
  "keys",
  {
    kind: :effect,
    shape: "keys(issuer, opts) -> [key]",
    laterals: %w[cache deadline resource],
    fleet: nil,
    today: "absent",
    meaning: "issuer's published verification keys, cached (JWKS)",
    wave: 2,
    origin: "D"
  }
)

verb(
  "tegata",
  "pkce",
  {
    kind: :pure,
    shape: "pkce(verifier) -> text",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "code challenge derived from a verifier (S256)",
    wave: 2,
    origin: "D"
  }
)

verb(
  "tegata",
  "read",
  {
    kind: :effect,
    shape: "read(token, opts) -> claims",
    laterals: %w[error time validate],
    fleet: "pleme-auth-tokens",
    today: "absent",
    meaning: "check signature, expiry, issuer, audience; return claims",
    wave: 1,
    origin: "D"
  }
)

verb(
  "tegata",
  "refresh",
  {
    kind: :effect,
    shape: "refresh(refresh_token, opts) -> pair",
    laterals: %w[error idempotent time],
    fleet: "pleme-auth-tokens",
    today: "absent",
    meaning: "swap a refresh token for a new pair, retiring the old",
    wave: 2,
    origin: "D"
  }
)

verb(
  "tegata",
  "revoke",
  {
    kind: :effect,
    shape: "revoke(token, opts) -> nil",
    laterals: %w[idempotent log],
    fleet: nil,
    today: "absent",
    meaning: "make a token unacceptable before its expiry",
    wave: 2,
    origin: "D"
  }
)

verb(
  "tegata",
  "revoked?",
  {
    kind: :effect,
    shape: "revoked?(token) -> Bool",
    laterals: %w[cache resource],
    fleet: nil,
    today: "absent",
    meaning: "token is on the revocation list",
    wave: 2,
    origin: "D"
  }
)

verb(
  "tegata",
  "tie",
  {
    kind: :pure,
    shape: "tie(token, key) -> token",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "bind a token to the holder's key so theft is useless",
    wave: 3,
    origin: "D"
  }
)

verb(
  "tegata",
  "unverified",
  {
    kind: :pure,
    shape: "unverified(token) -> record",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "header and claims with no checks; never decide on these",
    wave: 1,
    origin: "D"
  }
)

edge("tegata::api_key", :composes, "shomei::hash", "store hash, not secret")
edge("tegata::pkce", :composes, "shomei::hash", "SHA-256 of the verifier")

edge(
  "tegata::api_key_valid?",
  :composes,
  "shomei::same?",
  "equal-time comparison"
)

edge(
  "tegata::issue",
  :composes,
  "shomei::sign",
  "signature over header and claims"
)

edge("tegata::read", :composes, "shomei::verify?", "signature check")

edge(
  "tegata::keys",
  :composes,
  "tegata::discover",
  "key set URL from discovery"
)

edge(
  "tegata::acquire",
  :composes,
  "tegata::issue",
  "assertion for client credentials"
)

edge("tegata::exchange", :composes, "tegata::issue", "mint the narrower token")
edge("tegata::refresh", :composes, "tegata::issue", "new pair")
edge("tegata::read", :composes, "tegata::keys", "find the verification key")
edge("tegata::flow_start", :composes, "tegata::pkce", "challenge from verifier")
edge("tegata::exchange", :composes, "tegata::read", "check the incoming token")

edge(
  "tegata::flow_finish",
  :composes,
  "tegata::read",
  "check the returned ID token"
)

edge(
  "tegata::refresh",
  :composes,
  "tegata::revoke",
  "old refresh token retired"
)

edge(
  "tegata::assertion",
  :generalizes,
  "tegata::read",
  "same checks on a SAML document"
)

edge(
  "tegata::introspect",
  :generalizes,
  "tegata::read",
  "asks the issuer instead of verifying locally"
)

edge(
  "tegata::read",
  :guards,
  "ninshou?::caller",
  "token is one source of identity"
)

edge("tegata::revoke", :guards, "tegata::read", "revoked tokens fail reading")
edge("tegata::tie", :guards, "tegata::read", "reader checks the holder proof")

edge(
  "tegata::unverified",
  :guards,
  "tegata::read",
  "peek at key id before verifying"
)

edge(
  "tegata::api_key_valid?",
  :inverse,
  "tegata::api_key",
  "checks a presented key"
)

edge(
  "tegata::api_key",
  :inverse,
  "tegata::api_key_valid?",
  "checks a presented key"
)

edge(
  "tegata::read",
  :inverse,
  "tegata::issue",
  "checks and opens what issue made"
)

edge("tegata::revoke", :inverse, "tegata::issue", "withdraws an issued token")

edge(
  "tegata::issue",
  :inverse,
  "tegata::read",
  "checks and opens what issue made"
)

edge("tegata::issue", :inverse, "tegata::revoke", "withdraws an issued token")
edge("tegata::api_key", :pairs, "tegata::api_key_valid?", "issue and check")

edge(
  "tegata::flow_finish",
  :pairs,
  "tegata::flow_start",
  "redeems what start prepared"
)

edge(
  "tegata::refresh",
  :pairs,
  "tegata::issue",
  "refresh mints a pair like issue"
)

edge("tegata::issue", :pairs, "tegata::read", "every token has a check")
edge("tegata::keys", :pairs, "tegata::read", "read needs the issuer keys")
edge("tegata::revoked?", :pairs, "tegata::revoke", "the list revoke writes")

edge(
  "tegata::introspect",
  :pairs,
  "tegata::revoked?",
  "remote versus local state"
)

edge(
  "tegata::attenuate",
  :pairs,
  "waku::narrow",
  "same law: narrow cannot widen"
)

edge(
  "tegata::attenuate",
  :refines,
  "tegata::issue",
  "adds a caveat, never removes"
)

edge("tegata::expired?", :refines, "tegata::read", "expiry check alone")
edge("tegata::api_key", :requires, "fuuin?::random", "key from entropy")

edge(
  "tegata::flow_start",
  :requires,
  "fuuin?::random",
  "state and verifier from entropy"
)

edge("tegata::tie", :requires, "shomei::keypair", "holder owns a key")

edge(
  "tegata::acquire",
  :requires,
  "tegata::discover",
  "token endpoint from discovery"
)

edge(
  "tegata::flow_finish",
  :requires,
  "tegata::discover",
  "endpoints come from discovery"
)

edge("tegata::discover", :requires, "tegata::keys", "keys come after discovery")

edge(
  "tegata::unverified",
  :requires,
  "tegata::keys",
  "key id picks the verification key"
)
