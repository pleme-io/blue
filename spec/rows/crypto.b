# Hashing and signatures: pure, C-free, and the same on every evaluator.

row(
  "crypto.blake3",
  "blake3_hex(\"\")",
  value("\"af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262\""),
  covers("builtin:blake3_hex")
)

row(
  "crypto.ed25519",
  "k = ed25519_keypair(\"0101010101010101010101010101010101010101010101010101010101010101\")\nsec = nth(0, k)\npub = nth(1, k)\nsig = ed25519_sign(sec, \"m\")\n[ed25519_verify(pub, \"m\", sig), ed25519_verify(pub, \"n\", sig)]",
  value("[true, false]"),
  covers(
    "builtin:ed25519_keypair",
    "builtin:ed25519_sign",
    "builtin:ed25519_verify"
  )
)
