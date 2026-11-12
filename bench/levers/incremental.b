CHUNKS = 64

WORK = 50000

EDIT = 0

def chunk(seed)
  reduce((acc, i) -> (acc * 31 + seed + i) % 1_000_003, 0, range(WORK))
end

write_stdout(
  unlines(
    [
      reduce(
        fn(a, i)
          last = if i == CHUNKS - 1
            EDIT
          else
            0
          end
          a + chunk(i * 7 + 1 + last)
        end,
        0,
        range(CHUNKS)
      )
    ]
  )
)
