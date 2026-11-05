@moduledoc """
refused: A program the verifier refuses at a line it can name: it reads the XDP context at an offset the context does not have. kernel/object_suite.b asserts the refusal names this file's line 11.

    blue test --allow host kernel/object_suite.b
"""

use("kaaneru/bpf", [:ctx_int])

def read_far(c)
  near = 1
  far = ctx_int(c, 1000, 4)
  near + far
end
