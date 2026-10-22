space("mimoto?", {status: :provisional})

verb(
  "mimoto?",
  "chain_of",
  {
    kind: :effect,
    shape: "chain_of(chain, roots, opts) -> [cert]",
    laterals: ["error", "time", "validate"],
    fleet: "webpki",
    today: "absent",
    meaning: "valid chain from leaf to a trusted root, or :untrusted",
    wave: 2,
    origin: "D"
  }
)

verb(
  "mimoto?",
  "expires",
  {
    kind: :pure,
    shape: "expires(cert) -> instant",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "the end of a certificate's validity",
    wave: 2,
    origin: "D"
  }
)

verb(
  "mimoto?",
  "expiring?",
  {
    kind: :pure,
    shape: "expiring?(cert, within, now) -> Bool",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "certificate ends inside the given duration",
    wave: 2,
    origin: "D"
  }
)

verb(
  "mimoto?",
  "fingerprint",
  {
    kind: :pure,
    shape: "fingerprint(cert) -> hex",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "hash of the public key, for pinning",
    wave: 2,
    origin: "D"
  }
)

verb(
  "mimoto?",
  "info",
  {
    kind: :pure,
    shape: "info(cert) -> record",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "subject, issuer, names, validity, key usage",
    wave: 2,
    origin: "D"
  }
)

verb(
  "mimoto?",
  "issue",
  {
    kind: :effect,
    shape: "issue(csr, authority, opts) -> cert",
    laterals: ["capability", "log", "time"],
    fleet: "openclaw-publisher-pki",
    today: "absent",
    meaning: "sign a request as a CA with a lifetime",
    wave: 3,
    origin: "D"
  }
)

verb(
  "mimoto?",
  "matches?",
  {
    kind: :pure,
    shape: "matches?(cert, name) -> Bool",
    laterals: ["validate"],
    fleet: "webpki",
    today: "absent",
    meaning: "certificate covers a host name or address",
    wave: 2,
    origin: "D"
  }
)

verb(
  "mimoto?",
  "parse",
  {
    kind: :pure,
    shape: "parse(text, format) -> cert",
    laterals: ["serialize", "validate"],
    fleet: "webpki",
    today: "absent",
    meaning: "PEM or DER to a certificate record",
    wave: 2,
    origin: "D"
  }
)

verb(
  "mimoto?",
  "principal",
  {
    kind: :pure,
    shape: "principal(cert) -> text",
    laterals: ["validate"],
    fleet: "kakuin-workload-api",
    today: "absent",
    meaning: "workload identity (SPIFFE id) a certificate names",
    wave: 3,
    origin: "D"
  }
)

verb(
  "mimoto?",
  "probe",
  {
    kind: :effect,
    shape: "probe(host, opts) -> record",
    laterals: ["deadline", "resource"],
    fleet: nil,
    today: "absent",
    meaning: "connect and report version, chain and expiry",
    wave: 2,
    origin: "D"
  }
)

verb(
  "mimoto?",
  "profile",
  {
    kind: :decl,
    shape: "profile(level) -> record",
    laterals: ["config"],
    fleet: "kakuin-rustls",
    today: "absent",
    meaning: "TLS settings by level: versions, suites, client auth",
    wave: 2,
    origin: "D"
  }
)

verb(
  "mimoto?",
  "render",
  {
    kind: :pure,
    shape: "render(cert, format) -> text",
    laterals: ["serialize"],
    fleet: nil,
    today: "absent",
    meaning: "certificate to PEM or DER text",
    wave: 2,
    origin: "D"
  }
)

verb(
  "mimoto?",
  "renew",
  {
    kind: :effect,
    shape: "renew(cert, opts) -> cert",
    laterals: ["idempotent", "retry", "time"],
    fleet: "x-crypto",
    today: "absent",
    meaning: "new certificate for the same identity before expiry (ACME)",
    wave: 3,
    origin: "D"
  }
)

verb(
  "mimoto?",
  "request",
  {
    kind: :pure,
    shape: "request(subject, key, opts) -> csr",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "certificate signing request for a key",
    wave: 2,
    origin: "D"
  }
)

verb(
  "mimoto?",
  "revoke",
  {
    kind: :effect,
    shape: "revoke(cert, reason) -> nil",
    laterals: ["idempotent", "log"],
    fleet: "openclaw-publisher-pki",
    today: "absent",
    meaning: "add a certificate to the signed revocation list",
    wave: 3,
    origin: "D"
  }
)

verb(
  "mimoto?",
  "revoked?",
  {
    kind: :effect,
    shape: "revoked?(cert, opts) -> Bool",
    laterals: ["cache", "deadline", "resource"],
    fleet: "openclaw-publisher-pki",
    today: "absent",
    meaning: "listed as revoked by CRL or OCSP",
    wave: 3,
    origin: "D"
  }
)

verb(
  "mimoto?",
  "roots",
  {
    kind: :effect,
    shape: "roots(opts) -> [cert]",
    laterals: ["cache", "resource"],
    fleet: "webpki",
    today: "absent",
    meaning: "trusted root certificates in force",
    wave: 2,
    origin: "D"
  }
)

verb(
  "mimoto?",
  "self_sign",
  {
    kind: :effect,
    shape: "self_sign(subject, key, opts) -> cert",
    laterals: ["capability", "time"],
    fleet: nil,
    today: "absent",
    meaning: "certificate signed by its own key, for tests and roots",
    wave: 2,
    origin: "D"
  }
)

verb(
  "mimoto?",
  "watch",
  {
    kind: :stream,
    shape: "watch(source, f, opts) -> nil",
    laterals: ["cancel", "resource"],
    fleet: "kakuin-workload-api",
    today: "absent",
    meaning: "call f on each rotated workload certificate",
    wave: 3,
    origin: "D"
  }
)

edge(
  "mimoto?::probe",
  :composes,
  "mimoto?::chain_of",
  "connect then verify chain"
)

edge(
  "mimoto?::expiring?",
  :composes,
  "mimoto?::expires",
  "compare to now plus window"
)

edge(
  "mimoto?::probe",
  :composes,
  "mimoto?::expires",
  "report remaining validity"
)

edge("mimoto?::probe", :composes, "mimoto?::info", "report the chain's fields")

edge(
  "mimoto?::renew",
  :composes,
  "mimoto?::issue",
  "new certificate for same key"
)

edge(
  "mimoto?::fingerprint",
  :composes,
  "shomei::hash",
  "hash of the public key"
)

edge("mimoto?::issue", :composes, "shomei::sign", "CA signature")
edge("mimoto?::chain_of", :composes, "shomei::verify?", "each link signature")

edge(
  "mimoto?::profile",
  :guards,
  "fuuin?::quantum_safe?",
  "level names allowed algorithms"
)

edge(
  "mimoto?::matches?",
  :guards,
  "mimoto?::chain_of",
  "name check follows chain check"
)

edge(
  "mimoto?::roots",
  :guards,
  "mimoto?::chain_of",
  "supplies the trust anchors"
)

edge(
  "mimoto?::chain_of",
  :guards,
  "mimoto?::matches?",
  "chain valid before name checked"
)

edge(
  "mimoto?::profile",
  :guards,
  "mimoto?::probe",
  "probe judges against a level"
)

edge("mimoto?::expiring?", :guards, "mimoto?::renew", "renew when near expiry")

edge(
  "mimoto?::chain_of",
  :guards,
  "mimoto?::revoked?",
  "revocation checked on the path"
)

edge(
  "mimoto?::revoke",
  :inverse,
  "mimoto?::issue",
  "withdraws an issued certificate"
)

edge("mimoto?::render", :inverse, "mimoto?::parse", "certificate to text")
edge("mimoto?::parse", :inverse, "mimoto?::render", "certificate to text")

edge(
  "mimoto?::issue",
  :inverse,
  "mimoto?::revoke",
  "withdraws an issued certificate"
)

edge(
  "mimoto?::watch",
  :lifts,
  "mimoto?::principal",
  "stream of rotated identities"
)

edge("mimoto?::request", :pairs, "mimoto?::issue", "request then issue")

edge(
  "mimoto?::info",
  :pairs,
  "mimoto?::render",
  "read fields of what is rendered"
)

edge("mimoto?::revoked?", :pairs, "mimoto?::revoke", "the list revoke writes")
edge("mimoto?::self_sign", :refines, "mimoto?::issue", "issuer is the subject")

edge(
  "mimoto?::fingerprint",
  :refines,
  "shomei::fingerprint",
  "a fingerprint used for pinning"
)

edge("mimoto?::principal", :requires, "mimoto?::info", "reads the URI name")
edge("mimoto?::expires", :requires, "mimoto?::parse", "reads the validity end")
edge("mimoto?::info", :requires, "mimoto?::parse", "reads a parsed certificate")
edge("mimoto?::issue", :requires, "mimoto?::request", "signs a request")
edge("mimoto?::chain_of", :requires, "mimoto?::roots", "chain ends at a root")

edge(
  "mimoto?::request",
  :requires,
  "shomei::keypair",
  "request signed by the key"
)
