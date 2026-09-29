# Calling a Rust primitive through a bidama
#
# BLAKE3 and Ed25519 are Rust, bound into the runtime as blake3_hex and the
# ed25519_* names. A program reaches them through shomei, the bidama that
# wraps them with names that say what they are for and checks their inputs.
# There is no entropy source: a keypair comes from a seed the caller supplies.
use("retsu")
use("moji")
use("shomei")

seed = repeated("07", 32)

test "a hash is 64 lowercase hex characters, and stable"
  h = hash_message("blue")
  assert is_hash_hex(h)
  assert h == hash_message("blue")
  assert h != hash_message("Blue")
end

test "the bidama word and the runtime primitive agree"
  assert hash_message("blue") == blake3_hex("blue")
end

test "sign with the secret half, verify with the public half"
  kp = signing_keypair(seed)
  sig = sign_message(keypair_secret(kp), "ship it")
  assert verify_message(keypair_public(kp), "ship it", sig)
  assert !verify_message(keypair_public(kp), "ship it later", sig)
end

test "a hash chain detects an edited entry"
  g = chain_genesis("orders")
  head = chain_head(g, ["a", "b", "c"])
  assert chain_verify(g, ["a", "b", "c"], head)
  assert !chain_verify(g, ["a", "B", "c"], head)
end
