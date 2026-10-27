---
kind: explanation
summary: verb graph region D: security and trust
---

# Region D: security and trust (2026-10-22)

343 verbs, 548 edges (1.6 per verb), 20 spaces. Waves 0/1/2/3/4 = 74/77/128/55/9. 71 rows (21%) already exist in blue.
Drew from: Go `crypto/*` and `x/crypto`, RustCrypto and rustls/webpki, libsodium (`seal`/`open`), Python `hashlib`/`hmac`/`secrets`, JOSE/OAuth2/OIDC RFCs (6749, 7636, 7662, 8693), WebAuthn, NIST 800-63B, OWASP cheat sheets, Zanzibar/Cedar/Rego, Vault/SOPS, in-toto/SLSA/Sigstore/OSV/CycloneDX/OpenVEX, OSCAL, STRIDE, Sigma-style rules, GDPR.
Fleet owners cited from Cargo descriptions and file lists I read; I did not audit their APIs (a name in `fleet` means "owns the concern today").

## Spaces
Existing, extended (`blue_today` marks which rows exist): `shomei` (digests, MACs, signatures, chains, Merkle), `angou` (stays the teaching space: number theory and classical ciphers, nothing here is secure), `nisshi` (event log, now audit trail), `bougyo` (request postures), `shisei` (posture ladder), `tokumei` (anonymity, widened to privacy: PII classify/redact/retain/erase), `kyohi` (ledger of kinds, security kinds are rows: denied, expired, tampered, untrusted, revoked, escapes_root), `ukai` (route detour), `waku` (capability frames; 5 rows), `himitsu` (STDLIB 4.21 design, extended to 22).
Provisional (`?`, need the `naming` sweep): `kagi?` 鍵 keys, randomness, sealing (encrypt/decrypt, envelope, wrap, share); `ninshou?` 認証 authentication: passwords, one-time codes, passkeys, sessions, lockout; `tegata?` 手形 credentials in transit: tokens, OAuth2/OIDC, SAML, API keys; `shoumeisho?` 証明書 X.509 and TLS identity; `kengen?` 権限 authorization: allow/permit/grant, roles, relations, policies; `kyoukyuu?` 供給 supply chain: SBOM, scan, attest, admit, reproduce; `junshu?` 遵守 compliance: controls, packs, evidence, OSCAL; `kakuri?` 隔離 isolation and least privilege; `jouka?` 浄化 sanitising and injection defence; `kyoui?` 脅威 threat models and detection.

## The 5 highest-leverage gaps
1. `kagi?` (random, generate, derive, seal/open). blue has hash and Ed25519 and nothing else: no entropy, no encryption, no key derivation. Every other space here (sessions, tokens, vault, passwords) stands on `kagi::random` and `kagi::seal`. Needs one new `Capability::Entropy` (E0004 at four sites, by design) and RustCrypto AEAD/HKDF/X25519 behind the pure `crypto` layer, no C.
2. `jouka?` (escape, bind, contain, fits?, vet, hostile). All pure, all wave 1, and it turns the injection classes (SQL, shell, path traversal, SSRF, log forging) into one vocabulary a check-stage rule can enforce (`taint`/`clear` is the wave-4 destination).
3. `himitsu` as a type that cannot print. STDLIB makes it a record rendering `<secret>`; here `secret`/`reveal` plus `tokumei::mark` give secrets and PII the same one-door rule, and `leaks` closes the other direction.
4. `ninshou?`+`tegata?`+`kengen?`. The fleet has these only as Rust service libs (pleme-auth-*, pleme-rbac); blue programs and bougyo postures (`authenticate`, `authorize`) have nothing to call. `kengen::permit` and `waku::narrow` share one law: narrowing never widens.
5. `kyoukyuu?` (inventory, scan, vex, attest, admit). The fleet has the pieces in separate Rust repos (tameshi, sekiban, cartorio, security-contract); the verb loop `inventory > scan > attest > admit > record` is the missing composition, with `shisei::gated` supplying audit-or-enforce.

## Stays OUT of blue (and why)
- Primitive implementations in C or assembly, `-sys` crates, OpenSSL: blue's crypto layer is pure Rust (CONTAIN THE C). Algorithms are RustCrypto crates behind verbs.
- FIPS 140 validated modules and live 3PAO passes: external gates, named never claimed (SECURITY-LAYER.md section 0). `quantum_safe?` and `strength` report algorithm facts only.
- HSM, TPM, Secure Enclave, GrapheneOS hardware attestation (gos-attest, Auditor): device seams stay Rust.
- Kernel enforcement (seccomp, Landlock, eBPF programs): blue declares `kakuri::filter` and profiles; a Rust seam applies them. WASM confinement via `kakuri::embed` is the pure-blue route.
- The TLS record protocol and SAML XML canonicalization engines: `net` has no TLS today; `tegata::assertion` is wave 4 because XML signature wrapping is a parser attack surface, OIDC is preferred.
- Browser and GUI passkey UX, pentest toolkits (blackmatter-security is Nix packaging), ML anomaly models (`chokkan` territory): not stdlib.

## Wave order and why
- Wave 0 (74): rename what exists to the master verbs (`hash`, `sign`, `verify?`, `intact?`, kyohi ledger rows, bougyo/shisei/tokumei names), plus `same?` (constant-time compare is tiny and unlocks every secret check).
- Wave 1 (77): `kagi` entropy/seal/derive, `jouka` escape/bind/contain, `himitsu` read/reveal, `ninshou` password+TOTP, `tegata` issue/read, `kengen` allow?/permit, `kyoukyuu` inventory/scan/attest, `nisshi::audit/checkpoint`. Order inside: kagi first (dependency of the rest).
- Wave 2 (128): sessions, OAuth flows, certificates, policies, vault rotation, compliance render, isolation profiles, bougyo postures. These consume wave 1 and need I/O (network, clock).
- Wave 3 (55): passkeys, PKI issuance, leases, reproduce-and-compare, threat correlation, erase/gather. Large surface, few consumers yet.
- Wave 4 (9): hybrid post-quantum, SAML, seccomp filter, taint tracking, playbooks, honeytokens. Each waits on a capability or a type-system change.

## Overlaps with other regions (resolve once)
- Hash of files, safe paths: `shomei::hash_file`, `jouka::contain` against fairu (`fairu::write` takes a contained path). Canonical JSON and `diff`: deeta (nisshi has its own `canon`; extract to deeta).
- `kakuri::confine` vs shisutemu's `sandbox:` option: same meaning, keep one (confine) and let `run` accept a profile.
- Rate limit and retry: `bougyo::rate`, `ninshou::strike` vs heikou's `ratelimit` lateral; one policy record.
- Sinks: `tokumei::redact` is the rogu scrubber; `kyoui::alert` vs observability region; `nisshi::query` vs kueri.
- Secrets backends: himitsu vs `kinko` (1Password, declarative) and cofre; `junshu::waive` vs `hadome` (ratchet) and the `skip-<name>:` grammar.
- `kagi::random` vs `ran` (deterministic PRNG): never merge; `ran` stays for simulations and tests.
- `kyoukyuu::pin/rebuild` vs hyouka/kirikae (nix) and gitto (signed commits, secret scanning).
- Cross-region edge targets: shisutemu::run, fairu::write, tsuushin::request, rogu::info, deeta::diff, moji::pattern, ran::stream_seed.

## Risks
- Names are unswept. `shoumeisho?` is a near-homophone of `shomei`; alternative `inkan?`. `tokumei` widening past "anonymity" needs a NAMES gloss change or a split into `kojin?`.
- Memory hygiene: blue strings are not zeroized (crypto.rs says it is not a key vault), so `kagi::zeroize` is aspirational until a secret value type exists in the runtime.
- Timing safety (`same?`, `matches?`) needs a runtime primitive; a blue loop cannot promise constant time.
- tameshi's `encrypted_chain` uses a BLAKE3 counter mode and a mock; do not cite it as AEAD precedent.
- `begin`/`end` avoided as verbs (Ruby-shaped keywords); sessions use `start`/`stop`.
- Overlay-VPN `ukai` is network, not trust; kept here only because the operator listed it.
