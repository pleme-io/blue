# The emitted Rust for programs/hello.b on the QEMU virt32 board, written to
# $GEN_OUT: the generator behind generate("hello-virt32", …) in ../Bluefile.
# The program is read from $GEN_ROOT, where the engine puts exactly the inputs
# the Bluefile names.
use("chuuzou", [:cz_emit])

write_file(
  env_required("GEN_OUT"),
  cz_emit(
    path_join(env_required("GEN_ROOT"), "programs/hello.b"),
    "qemu-virt32"
  )
)
