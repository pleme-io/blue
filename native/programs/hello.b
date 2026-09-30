# N0's program (theory/BLUE-NATIVE.md §7): write "hi" and a newline to the
# board's UART. It uses def, if, Int arithmetic, a tail call and mmio_write, and
# nothing else. Under `blue run` kiban's model of the board prints the same
# three bytes the image prints on QEMU; the check compares the two.
use("kiban", [:mmio_write])

UART0 = 268435456

# Send one byte to the UART and answer it.
def put(c: Int) -> Int
  mmio_write(UART0, 8, c)
  c
end

# Send `n` consecutive bytes starting at `c`: "h" then "i" from 104. A tail
# call, so the image runs it as a loop.
def send(c: Int, n: Int) -> Int
  if n == 0
    c
  else
    put(c)
    send(c + 1, n - 1)
  end
end

send(104, 2)
put(10)
