space("kyoukyuu?", {status: :provisional})

verb(
  "kyoukyuu?",
  "admit",
  {
    kind: :effect,
    shape: "admit(artifact, policy, opts) -> decision",
    laterals: ["error", "log", "switch"],
    fleet: "sekiban",
    today: "absent",
    meaning: "gate on required attestations; audit or enforce mode",
    wave: 2,
    origin: "D"
  }
)

verb(
  "kyoukyuu?",
  "admit?",
  {
    kind: :effect,
    shape: "admit?(subject, policy) -> Bool",
    laterals: ["capability"],
    fleet: "sekiban",
    today: "absent",
    meaning: "whether the cluster gate would let it in",
    wave: 3,
    origin: "E"
  }
)

verb(
  "kyoukyuu?",
  "affects?",
  {
    kind: :pure,
    shape: "affects?(advisory, component) -> Bool",
    laterals: ["validate"],
    fleet: "tameshi",
    today: "absent",
    meaning: "advisory version range covers the component",
    wave: 1,
    origin: "D"
  }
)

verb(
  "kyoukyuu?",
  "attest",
  {
    kind: :effect,
    shape: "attest(subject, predicate, key, opts) -> envelope",
    laterals: ["capability", "log", "serialize"],
    fleet: "tameshi-attest",
    today: "absent",
    meaning: "sign a statement about an artifact (in-toto, DSSE)",
    wave: 1,
    origin: "D"
  }
)

verb(
  "kyoukyuu?",
  "attested?",
  {
    kind: :effect,
    shape: "attested?(subject, envelope, trust) -> Bool",
    laterals: ["time", "validate"],
    fleet: "sekiban",
    today: "absent",
    meaning: "envelope verifies and names the subject digest",
    wave: 1,
    origin: "D"
  }
)

verb(
  "kyoukyuu?",
  "audit_lock",
  {
    kind: :effect,
    shape: "audit_lock(lock, opts) -> [advisory]",
    laterals: ["error", "validate"],
    fleet: nil,
    today: "absent",
    meaning: "locked packages against advisories",
    wave: 2,
    origin: "E"
  }
)

verb(
  "kyoukyuu?",
  "blast",
  {
    kind: :effect,
    shape: "blast(component, graph) -> [artifact]",
    laterals: ["cache", "resource"],
    fleet: "security-contract",
    today: "absent",
    meaning: "every artifact that contains a component",
    wave: 3,
    origin: "D"
  }
)

verb(
  "kyoukyuu?",
  "breaches",
  {
    kind: :pure,
    shape: "breaches(findings, policy) -> [finding]",
    laterals: ["switch", "validate"],
    fleet: "tameshi",
    today: "absent",
    meaning: "findings that break the policy threshold",
    wave: 1,
    origin: "D"
  }
)

verb(
  "kyoukyuu?",
  "diff",
  {
    kind: :pure,
    shape: "diff(a, b) -> [change]",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "components added, removed or moved between two inventories",
    wave: 2,
    origin: "D"
  }
)

verb(
  "kyoukyuu?",
  "explain",
  {
    kind: :pure,
    shape: "explain(finding) -> text",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "how a flaw reaches the subject",
    wave: 3,
    origin: "E"
  }
)

verb(
  "kyoukyuu?",
  "get",
  {
    kind: :effect,
    shape: "get(feed, id) -> advisory or nil",
    laterals: ["cache", "resource"],
    fleet: nil,
    today: "absent",
    meaning: "one advisory by id, nil when unknown",
    wave: 2,
    origin: "D"
  }
)

verb(
  "kyoukyuu?",
  "inventory",
  {
    kind: :effect,
    shape: "inventory(subject, opts) -> sbom",
    laterals: ["cache", "resource"],
    fleet: "tameshi",
    today: "absent",
    meaning: "every component in an artifact or closure (SBOM)",
    wave: 1,
    origin: "D"
  }
)

verb(
  "kyoukyuu?",
  "license",
  {
    kind: :effect,
    shape: "license(subject) -> [license]",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "licenses found in a subject",
    wave: 3,
    origin: "E"
  }
)

verb(
  "kyoukyuu?",
  "licenses",
  {
    kind: :pure,
    shape: "licenses(sbom, policy) -> [violation]",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "components whose license the policy refuses",
    wave: 2,
    origin: "D"
  }
)

verb(
  "kyoukyuu?",
  "list",
  {
    kind: :effect,
    shape: "list(feed, opts) -> [advisory]",
    laterals: ["cache", "deadline", "resource"],
    fleet: nil,
    today: "absent",
    meaning: "advisories of a CVE or OSV feed, all pages",
    wave: 2,
    origin: "D"
  }
)

verb(
  "kyoukyuu?",
  "parse",
  {
    kind: :pure,
    shape: "parse(text, format) -> sbom",
    laterals: ["serialize", "validate"],
    fleet: "tameshi",
    today: "absent",
    meaning: "SPDX or CycloneDX text to an inventory",
    wave: 2,
    origin: "D"
  }
)

verb(
  "kyoukyuu?",
  "pin",
  {
    kind: :effect,
    shape: "pin(dependencies, opts) -> lock",
    laterals: ["idempotent", "resource"],
    fleet: "blue-lang-pkg",
    today: "absent",
    meaning: "record exact versions and hashes of dependencies",
    wave: 1,
    origin: "D"
  }
)

verb(
  "kyoukyuu?",
  "posture",
  {
    kind: :effect,
    shape: "posture(repository) -> record",
    laterals: ["resource"],
    fleet: "security-contract",
    today: "absent",
    meaning: "repository security practices as a score",
    wave: 3,
    origin: "D"
  }
)

verb(
  "kyoukyuu?",
  "provenance",
  {
    kind: :pure,
    shape: "provenance(build, opts) -> statement",
    laterals: ["serialize", "validate"],
    fleet: "tameshi-attest",
    today: "absent",
    meaning: "who built what, from which inputs, how (SLSA)",
    wave: 2,
    origin: "D"
  }
)

verb(
  "kyoukyuu?",
  "rebuild",
  {
    kind: :effect,
    shape: "rebuild(recipe, opts) -> record",
    laterals: ["process", "resource"],
    fleet: "substrate",
    today: "absent",
    meaning: "build again and report whether outputs are bit-identical",
    wave: 3,
    origin: "D"
  }
)

verb(
  "kyoukyuu?",
  "record",
  {
    kind: :effect,
    shape: "record(artifact, evidence) -> receipt",
    laterals: ["idempotent", "log", "resource"],
    fleet: "cartorio",
    today: "absent",
    meaning: "append to the ledger; get an inclusion receipt",
    wave: 3,
    origin: "D"
  }
)

verb(
  "kyoukyuu?",
  "render",
  {
    kind: :pure,
    shape: "render(sbom, format) -> text",
    laterals: ["serialize"],
    fleet: "tameshi",
    today: "absent",
    meaning: "inventory to SPDX or CycloneDX text",
    wave: 2,
    origin: "D"
  }
)

verb(
  "kyoukyuu?",
  "review",
  {
    kind: :effect,
    shape: "review(change, opts) -> [finding]",
    laterals: ["resource", "validate"],
    fleet: nil,
    today: "absent",
    meaning: "risk in a dependency change: new, abandoned, unsigned",
    wave: 3,
    origin: "D"
  }
)

verb(
  "kyoukyuu?",
  "sbom",
  {
    kind: :effect,
    shape: "sbom(subject, opts) -> sbom",
    laterals: ["cache", "serialize"],
    fleet: nil,
    today: "absent",
    meaning: "the bill of materials of an image or closure",
    wave: 2,
    origin: "E"
  }
)

verb(
  "kyoukyuu?",
  "scan",
  {
    kind: :effect,
    shape: "scan(subject, opts) -> [finding]",
    laterals: ["cache", "error", "resource", "time", "validate"],
    fleet: "openclaw-scanner",
    today: "absent",
    meaning: "match components against known vulnerability data",
    wave: 1,
    origin: "D"
  }
)

verb(
  "kyoukyuu?",
  "score",
  {
    kind: :pure,
    shape: "score(finding, opts) -> record",
    laterals: ["validate"],
    fleet: "tameshi",
    today: "absent",
    meaning: "severity and exploit likelihood of a finding",
    wave: 2,
    origin: "D"
  }
)

verb(
  "kyoukyuu?",
  "sign",
  {
    kind: :effect,
    shape: "sign(artifact, opts) -> signature",
    laterals: ["capability", "log"],
    fleet: "tameshi-sigstore",
    today: "absent",
    meaning: "sign an artifact digest as an identity (Sigstore)",
    wave: 2,
    origin: "D"
  }
)

verb(
  "kyoukyuu?",
  "trust",
  {
    kind: :decl,
    shape: "trust(name, keys, scope) -> root",
    laterals: ["config"],
    fleet: "tameshi",
    today: "absent",
    meaning: "which keys and identities count, and for what",
    wave: 1,
    origin: "D"
  }
)

verb(
  "kyoukyuu?",
  "verify",
  {
    kind: :effect,
    shape: "verify(subject, policy) -> verdict",
    laterals: ["capability", "validate"],
    fleet: "sekiban",
    today: "absent",
    meaning: "check signatures and attestations against a policy",
    wave: 2,
    origin: "E"
  }
)

verb(
  "kyoukyuu?",
  "verify?",
  {
    kind: :effect,
    shape: "verify?(artifact, signature, trust) -> Bool",
    laterals: ["resource", "time", "validate"],
    fleet: "tameshi-sigstore",
    today: "absent",
    meaning: "artifact signature checks against the trusted identities",
    wave: 2,
    origin: "D"
  }
)

verb(
  "kyoukyuu?",
  "vex",
  {
    kind: :decl,
    shape: "vex(finding, status, why) -> statement",
    laterals: ["config"],
    fleet: "security-contract",
    today: "absent",
    meaning: "a finding judged exploitable or not, with reason",
    wave: 2,
    origin: "D"
  }
)

edge("kyoukyuu?::sbom", :composes, "hyouka::depends", "closure is the list")
edge("kyoukyuu?::scan", :composes, "kyoukyuu?::affects?", "match one component")

edge(
  "kyoukyuu?::record",
  :composes,
  "kyoukyuu?::attest",
  "ledger holds attestations"
)

edge(
  "kyoukyuu?::admit",
  :composes,
  "kyoukyuu?::attested?",
  "required attestations"
)

edge("kyoukyuu?::admit", :composes, "kyoukyuu?::breaches", "findings policy")
edge("kyoukyuu?::rebuild", :composes, "kyoukyuu?::diff", "show what differs")

edge(
  "kyoukyuu?::review",
  :composes,
  "kyoukyuu?::diff",
  "new dependencies in a change"
)

edge(
  "kyoukyuu?::scan",
  :composes,
  "kyoukyuu?::list",
  "advisories to match against"
)

edge(
  "kyoukyuu?::attest",
  :composes,
  "kyoukyuu?::provenance",
  "a common statement"
)

edge(
  "kyoukyuu?::sign",
  :composes,
  "kyoukyuu?::record",
  "signature logged in the ledger"
)

edge(
  "kyoukyuu?::verify?",
  :composes,
  "kyoukyuu?::record",
  "inclusion checked against the ledger"
)

edge("kyoukyuu?::diff", :composes, "kyoukyuu?::sbom", "compare two inventories")
edge("kyoukyuu?::license", :composes, "kyoukyuu?::sbom", "licenses per entry")
edge("kyoukyuu?::review", :composes, "kyoukyuu?::scan", "vulnerable additions")
edge("kyoukyuu?::admit?", :composes, "kyoukyuu?::verify", "cluster gate logic")

edge(
  "kyoukyuu?::audit_lock",
  :composes,
  "paketto?::read",
  "lock against advisories"
)

edge("kyoukyuu?::admit", :composes, "shisei::gated", "audit-or-enforce ladder")

edge(
  "kyoukyuu?::inventory",
  :composes,
  "shomei::hash",
  "each component carries its digest"
)

edge(
  "kyoukyuu?::pin",
  :composes,
  "shomei::hash",
  "record the hash of each dependency"
)

edge(
  "kyoukyuu?::rebuild",
  :composes,
  "shomei::hash_file",
  "compare output digests"
)

edge("kyoukyuu?::record", :composes, "shomei::root", "ledger is a Merkle tree")
edge("kyoukyuu?::attest", :composes, "shomei::sign", "DSSE envelope signature")
edge("kyoukyuu?::attested?", :composes, "shomei::verify?", "signature check")

edge(
  "kyoukyuu?::get",
  :generalizes,
  "kyoukyuu?::list",
  "one advisory of the feed"
)

edge("kyoukyuu?::breaches", :guards, "kyoukyuu?::admit", "findings that block")
edge("kyoukyuu?::scan", :guards, "kyoukyuu?::admit", "findings feed the gate")

edge(
  "kyoukyuu?::verify",
  :guards,
  "kyoukyuu?::admit?",
  "check precedes admission"
)

edge(
  "kyoukyuu?::vex",
  :guards,
  "kyoukyuu?::breaches",
  "not-exploitable findings are removed"
)

edge(
  "kyoukyuu?::pin",
  :guards,
  "kyoukyuu?::inventory",
  "exact versions make inventory stable"
)

edge(
  "kyoukyuu?::provenance",
  :guards,
  "kyoukyuu?::rebuild",
  "claims to reproduce"
)

edge(
  "kyoukyuu?::licenses",
  :guards,
  "kyoukyuu?::review",
  "license risk in a change"
)

edge("kyoukyuu?::affects?", :guards, "kyoukyuu?::scan", "version range test")

edge(
  "kyoukyuu?::trust",
  :guards,
  "kyoukyuu?::verify?",
  "names the accepted roots"
)

edge("kyoukyuu?::scan", :guards, "tsumini?::push", "no push of flawed images")

edge(
  "kyoukyuu?::attested?",
  :inverse,
  "kyoukyuu?::attest",
  "checks an attestation"
)

edge("kyoukyuu?::verify", :inverse, "kyoukyuu?::attest", "sign versus check")

edge(
  "kyoukyuu?::attest",
  :inverse,
  "kyoukyuu?::attested?",
  "checks an attestation"
)

edge("kyoukyuu?::render", :inverse, "kyoukyuu?::parse", "inventory to text")
edge("kyoukyuu?::parse", :inverse, "kyoukyuu?::render", "inventory to text")
edge("kyoukyuu?::attest", :inverse, "kyoukyuu?::verify", "sign versus check")
edge("kyoukyuu?::provenance", :pairs, "kyoukyuu?::attest", "record then sign")
edge("kyoukyuu?::list", :pairs, "kyoukyuu?::get", "all entries, one entry")

edge(
  "kyoukyuu?::pin",
  :pairs,
  "kyoukyuu?::rebuild",
  "pinned inputs make rebuilds equal"
)

edge(
  "kyoukyuu?::inventory",
  :pairs,
  "kyoukyuu?::scan",
  "scan consumes the inventory"
)

edge(
  "kyoukyuu?::sign",
  :pairs,
  "kyoukyuu?::verify?",
  "every signature has a check"
)

edge(
  "kyoukyuu?::record",
  :pairs,
  "nisshi::witness",
  "ledger receipt for a log head"
)

edge("kyoukyuu?::sbom", :pairs, "tsumini?::layers", "layers hold the packages")
edge("kyoukyuu?::sbom", :refines, "core::render", "inventory of contents")
edge("kyoukyuu?::diff", :refines, "deeta::diff", "specialised to inventories")

edge(
  "kyoukyuu?::posture",
  :refines,
  "junshu?::assess",
  "checks practices of a repository"
)

edge(
  "kyoukyuu?::score",
  :refines,
  "kyoui?::rank",
  "ranking of vulnerability findings"
)

edge(
  "kyoukyuu?::audit_lock",
  :refines,
  "kyoukyuu?::scan",
  "scope is a lockfile"
)

edge(
  "kyoukyuu?::vex",
  :refines,
  "kyoukyuu?::scan",
  "judges a finding the scan made"
)

edge(
  "kyoukyuu?::sign",
  :refines,
  "shomei::sign",
  "adds identity and transparency"
)

edge("kyoukyuu?::verify", :refines, "shomei::verify?", "policy-aware check")

edge(
  "kyoukyuu?::verify?",
  :refines,
  "shomei::verify?",
  "adds identity and trust roots"
)

edge(
  "kyoukyuu?::blast",
  :requires,
  "kyoukyuu?::inventory",
  "inventories form the graph"
)

edge(
  "kyoukyuu?::licenses",
  :requires,
  "kyoukyuu?::inventory",
  "reads inventory licenses"
)

edge(
  "kyoukyuu?::provenance",
  :requires,
  "kyoukyuu?::inventory",
  "names the inputs"
)

edge(
  "kyoukyuu?::attest",
  :requires,
  "kyoukyuu?::provenance",
  "claim is provenance"
)

edge("kyoukyuu?::scan", :requires, "kyoukyuu?::sbom", "scan the inventory")
edge("kyoukyuu?::score", :requires, "kyoukyuu?::scan", "ranks findings")

edge(
  "kyoukyuu?::breaches",
  :requires,
  "kyoukyuu?::score",
  "policy threshold on score"
)

edge(
  "kyoukyuu?::attested?",
  :requires,
  "kyoukyuu?::trust",
  "only trusted keys count"
)

edge(
  "kyoukyuu?::verify?",
  :requires,
  "kyoukyuu?::trust",
  "identities to accept"
)

edge("kyoukyuu?::explain", :requires, "paketto?::why", "chain to the flaw")
edge("kyoukyuu?::sbom", :requires, "tsumini?::info", "image gives packages")
