space("ninshou?", {status: :provisional})

verb(
  "ninshou?",
  "alive?",
  {
    kind: :pure,
    shape: "alive?(session, now) -> Bool",
    laterals: ["time"],
    fleet: "pleme-auth-sessions",
    today: "absent",
    meaning: "session is inside both lifetimes",
    wave: 2,
    origin: "D"
  }
)

verb(
  "ninshou?",
  "answer?",
  {
    kind: :effect,
    shape: "answer?(challenge, response, key) -> Bool",
    laterals: ["idempotent", "time", "validate"],
    fleet: nil,
    today: "absent",
    meaning: "response is right, and the challenge is now spent",
    wave: 2,
    origin: "D"
  }
)

verb(
  "ninshou?",
  "backup_codes",
  {
    kind: :effect,
    shape: "backup_codes(count) -> [text]",
    laterals: ["capability"],
    fleet: "pleme-auth-mfa",
    today: "absent",
    meaning: "single-use recovery codes, shown once",
    wave: 1,
    origin: "D"
  }
)

verb(
  "ninshou?",
  "caller",
  {
    kind: :pure,
    shape: "caller(request, opts) -> identity or nil",
    laterals: ["validate"],
    fleet: "pleme-auth-sdk",
    today: "absent",
    meaning: "the identity a request proves, from session, token or cert",
    wave: 2,
    origin: "D"
  }
)

verb(
  "ninshou?",
  "challenge",
  {
    kind: :effect,
    shape: "challenge(identity, opts) -> challenge",
    laterals: ["capability", "time"],
    fleet: nil,
    today: "absent",
    meaning: "fresh one-use nonce a client must answer",
    wave: 2,
    origin: "D"
  }
)

verb(
  "ninshou?",
  "code",
  {
    kind: :pure,
    shape: "code(secret, moment, opts) -> text",
    laterals: ["time"],
    fleet: "pleme-auth-mfa",
    today: "absent",
    meaning: "one-time code (TOTP or HOTP) for a moment",
    wave: 1,
    origin: "D"
  }
)

verb(
  "ninshou?",
  "code_valid?",
  {
    kind: :pure,
    shape: "code_valid?(secret, text, opts) -> Bool",
    laterals: ["time", "validate"],
    fleet: "pleme-auth-mfa",
    today: "absent",
    meaning: "code is right within the allowed time window",
    wave: 1,
    origin: "D"
  }
)

verb(
  "ninshou?",
  "flaws",
  {
    kind: :pure,
    shape: "flaws(password, policy) -> [reason]",
    laterals: ["validate"],
    fleet: "pleme-auth-validators",
    today: "absent",
    meaning: "reasons a password fails length, breach or reuse rules",
    wave: 1,
    origin: "D"
  }
)

verb(
  "ninshou?",
  "forgive",
  {
    kind: :effect,
    shape: "forgive(identity) -> nil",
    laterals: ["idempotent", "log"],
    fleet: nil,
    today: "absent",
    meaning: "clear the failure count after success",
    wave: 2,
    origin: "D"
  }
)

verb(
  "ninshou?",
  "fresh?",
  {
    kind: :pure,
    shape: "fresh?(session, within, now) -> Bool",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "identity proved itself recently enough for a risky act",
    wave: 3,
    origin: "D",
    contract: "fresh?(session, within) -> Bool"
  }
)

verb(
  "ninshou?",
  "locked?",
  {
    kind: :pure,
    shape: "locked?(identity, now) -> Bool",
    laterals: ["ratelimit", "time"],
    fleet: nil,
    today: "absent",
    meaning: "too many failures; further attempts are refused",
    wave: 2,
    origin: "D"
  }
)

verb(
  "ninshou?",
  "matches?",
  {
    kind: :pure,
    shape: "matches?(password, verifier) -> Bool",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "password fits the stored verifier in equal time",
    wave: 1,
    origin: "D"
  }
)

verb(
  "ninshou?",
  "passkey_accept",
  {
    kind: :pure,
    shape: "passkey_accept(request, response) -> credential",
    laterals: ["error", "validate"],
    fleet: "namimado",
    today: "absent",
    meaning: "check an enrolment response and keep the new credential",
    wave: 3,
    origin: "D"
  }
)

verb(
  "ninshou?",
  "passkey_ask",
  {
    kind: :effect,
    shape: "passkey_ask(kind, opts) -> request",
    laterals: ["capability", "time"],
    fleet: "namimado",
    today: "absent",
    meaning: "WebAuthn creation or assertion request with a fresh challenge",
    wave: 3,
    origin: "D"
  }
)

verb(
  "ninshou?",
  "passkey_verify",
  {
    kind: :pure,
    shape: "passkey_verify(request, response, credential) -> credential",
    laterals: ["error", "validate"],
    fleet: "namimado",
    today: "absent",
    meaning: "check a sign-in; raises :cloned when the counter goes back",
    wave: 3,
    origin: "D"
  }
)

verb(
  "ninshou?",
  "protect",
  {
    kind: :effect,
    shape: "protect(password, opts) -> verifier",
    laterals: ["capability", "resource"],
    fleet: "pleme-auth-validators",
    today: "absent",
    meaning: "salted slow hash of a password, safe to store",
    wave: 1,
    origin: "D",
    contract: "protect(password, f, opts) -> verifier"
  }
)

verb(
  "ninshou?",
  "renew",
  {
    kind: :effect,
    shape: "renew(session) -> session",
    laterals: ["log", "time"],
    fleet: "pleme-auth-sessions",
    today: "absent",
    meaning: "new session id after a privilege change, old one dead",
    wave: 2,
    origin: "D"
  }
)

verb(
  "ninshou?",
  "sign_in",
  {
    kind: :effect,
    shape: "sign_in(identity, proofs, opts) -> session",
    laterals: ["error", "log", "ratelimit", "time"],
    fleet: "pleme-auth-sdk",
    today: "absent",
    meaning: "check every required factor, then start a session",
    wave: 2,
    origin: "D"
  }
)

verb(
  "ninshou?",
  "spend",
  {
    kind: :pure,
    shape: "spend(codes, code) -> [text]",
    laterals: ["validate"],
    fleet: "pleme-auth-mfa",
    today: "absent",
    meaning: "the recovery codes left after one is used",
    wave: 1,
    origin: "D"
  }
)

verb(
  "ninshou?",
  "stale?",
  {
    kind: :pure,
    shape: "stale?(verifier, policy) -> Bool",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "verifier is weaker than policy; rehash at next login",
    wave: 1,
    origin: "D"
  }
)

verb(
  "ninshou?",
  "start",
  {
    kind: :effect,
    shape: "start(identity, opts) -> session",
    laterals: ["capability", "log", "time"],
    fleet: "pleme-auth-sessions",
    today: "absent",
    meaning: "start a session with idle and absolute lifetimes",
    wave: 2,
    origin: "D"
  }
)

verb(
  "ninshou?",
  "stop",
  {
    kind: :effect,
    shape: "stop(session, opts) -> nil",
    laterals: ["idempotent", "log"],
    fleet: "pleme-auth-sessions",
    today: "absent",
    meaning: "end one session or every session of an identity",
    wave: 2,
    origin: "D"
  }
)

verb(
  "ninshou?",
  "strike",
  {
    kind: :effect,
    shape: "strike(identity, opts) -> record",
    laterals: ["log", "ratelimit", "time"],
    fleet: nil,
    today: "absent",
    meaning: "count a failed attempt toward a lockout",
    wave: 2,
    origin: "D"
  }
)

verb(
  "ninshou?",
  "touch",
  {
    kind: :effect,
    shape: "touch(session) -> session",
    laterals: ["error", "time"],
    fleet: "pleme-auth-sessions",
    today: "absent",
    meaning: "record activity; raises :expired past either lifetime",
    wave: 2,
    origin: "D"
  }
)

edge(
  "ninshou?::protect",
  :composes,
  "fuuin?::stretch",
  "slow salted derivation"
)

edge(
  "ninshou?::code_valid?",
  :composes,
  "ninshou?::code",
  "compare within the window"
)

edge("ninshou?::sign_in", :composes, "ninshou?::code_valid?", "second factor")
edge("ninshou?::sign_in", :composes, "ninshou?::matches?", "first factor")
edge("ninshou?::sign_in", :composes, "ninshou?::start", "session after proofs")
edge("ninshou?::renew", :composes, "ninshou?::stop", "old id is stopped")
edge("ninshou?::sign_in", :composes, "ninshou?::strike", "failures are counted")
edge("ninshou?::code", :composes, "shomei::mac", "HMAC of the time step")

edge(
  "ninshou?::code_valid?",
  :composes,
  "shomei::same?",
  "equal-time comparison"
)

edge("ninshou?::matches?", :composes, "shomei::same?", "equal-time comparison")

edge(
  "ninshou?::answer?",
  :composes,
  "shomei::verify?",
  "response is a signature"
)

edge(
  "ninshou?::passkey_accept",
  :composes,
  "shomei::verify?",
  "attestation signature check"
)

edge(
  "ninshou?::passkey_verify",
  :composes,
  "shomei::verify?",
  "assertion signature check"
)

edge("ninshou?::caller", :composes, "tegata::read", "identity from a token")

edge(
  "ninshou?::caller",
  :guards,
  "kengen?::permit",
  "identity comes before permission"
)

edge(
  "ninshou?::touch",
  :guards,
  "ninshou?::alive?",
  "raises when either lifetime ended"
)

edge(
  "ninshou?::strike",
  :guards,
  "ninshou?::matches?",
  "count each failed match"
)

edge(
  "ninshou?::challenge",
  :guards,
  "ninshou?::passkey_ask",
  "same fresh nonce rule"
)

edge(
  "ninshou?::flaws",
  :guards,
  "ninshou?::protect",
  "refuse weak passwords before storing"
)

edge("ninshou?::stale?", :guards, "ninshou?::protect", "decides when to rehash")

edge(
  "ninshou?::fresh?",
  :guards,
  "ninshou?::sign_in",
  "step-up before a risky act"
)

edge("ninshou?::locked?", :guards, "ninshou?::sign_in", "refuse while locked")
edge("ninshou?::alive?", :guards, "ninshou?::touch", "touch only when alive")
edge("ninshou?::strike", :inverse, "ninshou?::forgive", "clears the count")

edge(
  "ninshou?::protect",
  :inverse,
  "ninshou?::matches?",
  "checks a password against its verifier"
)

edge(
  "ninshou?::matches?",
  :inverse,
  "ninshou?::protect",
  "checks a password against its verifier"
)

edge("ninshou?::stop", :inverse, "ninshou?::start", "ends what start began")
edge("ninshou?::start", :inverse, "ninshou?::stop", "ends what start began")
edge("ninshou?::forgive", :inverse, "ninshou?::strike", "clears the count")
edge("ninshou?::spend", :pairs, "ninshou?::backup_codes", "a code works once")

edge(
  "ninshou?::answer?",
  :pairs,
  "ninshou?::challenge",
  "each challenge answered once"
)

edge("ninshou?::code", :pairs, "ninshou?::code_valid?", "generate and check")

edge(
  "ninshou?::strike",
  :pairs,
  "ninshou?::locked?",
  "failures feed the lockout"
)

edge("ninshou?::protect", :pairs, "ninshou?::matches?", "store and check")

edge(
  "ninshou?::passkey_accept",
  :pairs,
  "ninshou?::passkey_ask",
  "answers an enrolment request"
)

edge(
  "ninshou?::passkey_verify",
  :pairs,
  "ninshou?::passkey_ask",
  "answers a sign-in request"
)

edge("ninshou?::start", :pairs, "ninshou?::stop", "every session ends")

edge(
  "ninshou?::backup_codes",
  :requires,
  "fuuin?::random",
  "codes need entropy"
)

edge(
  "ninshou?::challenge",
  :requires,
  "fuuin?::random",
  "nonce must be unpredictable"
)

edge(
  "ninshou?::passkey_ask",
  :requires,
  "fuuin?::random",
  "challenge must be fresh"
)

edge(
  "ninshou?::protect",
  :requires,
  "fuuin?::random",
  "salt from secure entropy"
)

edge("ninshou?::start", :requires, "fuuin?::random", "session id from entropy")

edge(
  "ninshou?::caller",
  :requires,
  "ninshou?::alive?",
  "identity from a live session"
)

edge("ninshou?::fresh?", :requires, "ninshou?::alive?", "fresh implies alive")

edge(
  "ninshou?::passkey_verify",
  :requires,
  "ninshou?::passkey_accept",
  "needs the enrolled credential"
)

edge(
  "ninshou?::flaws",
  :requires,
  "ninshou?::protect",
  "checked before the hash is stored"
)

edge(
  "ninshou?::alive?",
  :requires,
  "ninshou?::start",
  "only sessions that started"
)

edge(
  "ninshou?::renew",
  :requires,
  "ninshou?::start",
  "replaces a live session id"
)

edge("ninshou?::touch", :requires, "ninshou?::start", "only a live session")
