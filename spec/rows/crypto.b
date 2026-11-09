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

row(
  "crypto.x25519",
  join_lines(
    [
      "a = x25519_keypair(\"77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a\")",
      "b = x25519_keypair(\"5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb\")",
      "k = x25519_shared(a[0], b[1])",
      "[a[1], k == x25519_shared(b[0], a[1]), k]"
    ]
  ),
  value("[\"8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a\", true, \"4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742\"]"),
  covers("builtin:x25519_keypair", "builtin:x25519_shared")
)

row(
  "crypto.x25519.low_order",
  join_lines(
    [
      "begin",
      "  x25519_shared(\"77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a\", \"0000000000000000000000000000000000000000000000000000000000000000\")",
      "rescue :refused as e",
      "  [e.kind, contains?(e.message, \"low order\")]",
      "end"
    ]
  ),
  value("[:refused, true]"),
  covers("builtin:x25519_shared")
)

row(
  "crypto.chacha20poly1305",
  join_lines(
    [
      "key = \"808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f\"",
      "nonce = \"070000004041424344454647\"",
      "aad = [80, 81, 82, 83, 192, 193, 194, 195, 196, 197, 198, 199]",
      "sealed = chacha20poly1305_seal(key, nonce, aad, \"Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.\")",
      "[sealed, bytes_text(chacha20poly1305_open(key, nonce, aad, sealed))]"
    ]
  ),
  value("[\"d31a8d34648e60db7b86afbc53ef7ec2a4aded51296e08fea9e2b5a736ee62d63dbea45e8ca9671282fafb69da92728b1a71de0a9e060b2905d6a5b67ecd3b3692ddbd7f2d778b8c9803aee328091b58fab324e4fad675945585808b4831d7bc3ff4def08e4b7a9de576d26586cec64b61161ae10b594f09e26a7e902ecbd0600691\", \"Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.\"]"),
  covers("builtin:chacha20poly1305_seal", "builtin:chacha20poly1305_open")
)

row(
  "crypto.chacha20poly1305.tampered_tag",
  join_lines(
    [
      "key = \"808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f\"",
      "nonce = \"070000004041424344454647\"",
      "sealed = chacha20poly1305_seal(key, nonce, \"aad\", \"m\")",
      "c = chars(sealed)",
      "last = if c[length(c) - 1] == \"0\"",
      "  \"1\"",
      "else",
      "  \"0\"",
      "end",
      "forged = concat(join(take(length(c) - 1, c), \"\"), last)",
      "begin",
      "  chacha20poly1305_open(key, nonce, \"aad\", forged)",
      "rescue :tampered as e",
      "  [e.kind, contains?(e.message, \"sealed message does not verify\")]",
      "end"
    ]
  ),
  value("[:tampered, true]"),
  covers("builtin:chacha20poly1305_open")
)

row(
  "crypto.chacha20poly1305.wrong_aad",
  join_lines(
    [
      "key = \"808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f\"",
      "nonce = \"070000004041424344454647\"",
      "chacha20poly1305_open(key, nonce, \"other\", chacha20poly1305_seal(key, nonce, \"aad\", \"m\"))"
    ]
  ),
  fails(:eval, "sealed message does not verify"),
  covers("builtin:chacha20poly1305_open")
)

row(
  "crypto.bao",
  join_lines(
    [
      "d = map((i) -> i % 251, range(2049))",
      "t = bao_outboard(d)",
      "r = bao_verify_slice(t.root, bao_slice(d, t.outboard, 1024, 1024), 1024, 1024)",
      "[t.root == blake3_hex(d), length(t.outboard) / 2, r == take(1024, drop(1024, d))]"
    ]
  ),
  value("[true, 136, true]"),
  covers(
    "builtin:bao_outboard",
    "builtin:bao_slice",
    "builtin:bao_verify_slice"
  )
)

row(
  "crypto.bao.tampered_range",
  join_lines(
    [
      "d = map((i) -> i % 251, range(2049))",
      "forged = map((i) -> (i + 1) % 251, range(2049))",
      "t = bao_outboard(d)",
      "begin",
      "  bao_verify_slice(t.root, bao_slice(forged, t.outboard, 1024, 1024), 1024, 1024)",
      "rescue :tampered as e",
      "  [e.kind, contains?(e.message, \"slice does not verify\")]",
      "end"
    ]
  ),
  value("[:tampered, true]"),
  covers("builtin:bao_verify_slice")
)

row(
  "crypto.p2p_seam.placement",
  join_lines(
    [
      "a = x25519_keypair(\"77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a\")",
      "b = x25519_keypair(\"5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb\")",
      "k = x25519_shared(a[0], b[1])",
      "nonce = \"000000000000000000000001\"",
      "sealed = chacha20poly1305_seal(k, nonce, \"head\", \"a step\")",
      "d = map((i) -> i % 251, range(2049))",
      "t = bao_outboard(d)",
      "r = bao_verify_slice(t.root, bao_slice(d, t.outboard, 1024, 1024), 1024, 1024)",
      "write_stdout(unlines([k, sealed, bytes_text(chacha20poly1305_open(k, nonce, \"head\", sealed)), t.root, blake3_hex(r)]))"
    ]
  ),
  prints(
    unlines(
      [
        "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742",
        "40e4b4c7a54d5ca9a5073aebde502ec59489642920f2",
        "a step",
        "5f4d72f40d7a5f82b15ca2b2e44b1de3c2ef86c426c95c1af0b6879522563030",
        "f82d9b29da6db93924de1475c47b8e14c74132389534f5ef3c1ee20185edc245"
      ]
    )
  )
)
