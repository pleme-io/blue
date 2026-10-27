# Hashing and signatures: pure, C-free, and the same on every evaluator.

row(
  "crypto.blake3",
  "blake3_hex(\"\")",
  value("\"af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262\""),
  covers("builtin:blake3_hex")
)

row(
  "crypto.ed25519",
  join_lines(
    [
      "k = ed25519_keypair(\"0101010101010101010101010101010101010101010101010101010101010101\")",
      "sec = nth(0, k)",
      "pub = nth(1, k)",
      "sig = ed25519_sign(sec, \"m\")",
      "[ed25519_verify(pub, \"m\", sig), ed25519_verify(pub, \"n\", sig)]"
    ]
  ),
  value("[true, false]"),
  covers(
    "builtin:ed25519_keypair",
    "builtin:ed25519_sign",
    "builtin:ed25519_verify"
  )
)

row(
  "crypto.digest",
  "[digest_hex(\"sha1\", \"abc\"), digest_hex(:sha256, \"abc\"), digest_hex(\"sha512\", [97, 98, 99]), digest_hex(\"blake3\", \"\") == blake3_hex(\"\")]",
  value("[\"a9993e364706816aba3e25717850c26c9cd0d89d\", \"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\", \"ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f\", true]"),
  covers("builtin:digest_hex")
)

row(
  "crypto.digest.unknown",
  "digest_hex(\"md5\", \"x\")",
  fails(:eval, "unknown algorithm `md5`"),
  covers("builtin:digest_hex")
)

row(
  "crypto.hmac",
  "[hmac_hex(\"sha256\", \"Jefe\", \"what do ya want for nothing?\"), hmac_hex(:sha1, \"Jefe\", \"what do ya want for nothing?\")]",
  value("[\"5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843\", \"effcdf6ae5eb2fa2d27416d5f184df9c259a7c79\"]"),
  covers("builtin:hmac_hex")
)

row(
  "crypto.hmac.blake3",
  "hmac_hex(\"blake3\", \"k\", \"m\")",
  fails(:eval, "no keyed form"),
  covers("builtin:hmac_hex")
)

row(
  "crypto.bytes_equal",
  "[bytes_equal?(\"abc\", [97, 98, 99]), bytes_equal?(\"abc\", \"abd\"), bytes_equal?(\"abc\", \"ab\"), bytes_equal?(\"\", [])]",
  value("[true, false, false, true]"),
  covers("builtin:bytes_equal?")
)

row(
  "crypto.bytes_equal.not_a_message",
  "bytes_equal?(nil, \"a\")",
  fails(:eval, "string or a list of bytes"),
  covers("builtin:bytes_equal?")
)
