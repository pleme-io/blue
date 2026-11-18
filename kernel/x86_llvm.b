use("kikaigo", %i[corpus encode text])
use("moji", %i[after_first before_first includes])
use("retsu", %i[is_empty size])
use("shisutemu", %i[status_of stdout_of])

@doc """
hex_digit: the value of one lower-case hex digit.

    hex_digit("f") #=> 15
"""
def hex_digit(c)
  retsu::index_of(chars("0123456789abcdef"), c)
end

@doc """
hex_byte: the value of a byte written 0xNN.

    hex_byte("0x4d") #=> 77
"""
def hex_byte(t)
  d = chars(replace(trim(t), "0x", ""))
  hex_digit(d[0]) * 16 + hex_digit(d[1])
end

@doc """
encoding_of: the bytes an llvm-mc --show-encoding line reports, or nil for a line with none.

    encoding_of("retq # encoding: [0xc3]") #=> [195]
"""
def encoding_of(line)
  if includes(line, "encoding: [")
    inner = before_first(after_first(line, "encoding: ["), "]")
    map(hex_byte, split(inner, ","))
  end
end

def main()
  insns = corpus
  path = path_join(temp_dir("x86-llvm"), "corpus.s")
  write_file(path, unlines(map(text, insns)))
  r = exec_capture("llvm-mc", "--triple=x86_64", "--show-encoding", path)
  if status_of(r) != 0
    write_stderr(unlines(["llvm-mc failed"]))
    exit_with(2)
  end
  theirs = filter((e) -> e != nil, map(encoding_of, moji::lines(stdout_of(r))))
  if size(theirs) != size(insns)
    write_stderr(
      unlines(
        [
          "llvm-mc reported #{to_s(size(theirs))} encodings for #{to_s(size(insns))} instructions"
        ]
      )
    )
    exit_with(1)
  end
  bad = filter((i) -> encode(insns[i]) != theirs[i], range(0, size(insns)))
  if is_empty(bad)
    write_stdout(
      unlines(
        [
          "x86-64: #{to_s(size(insns))} of #{to_s(size(insns))} byte-identical to llvm-mc"
        ]
      )
    )
  else
    map(
      fn(i)
        write_stderr(
          unlines(
            [
              "#{text(insns[i])}: blue #{to_s(encode(insns[i]))}, llvm #{to_s(theirs[i])}"
            ]
          )
        )
      end,
      bad
    )
    write_stderr(
      unlines(["x86-64: #{to_s(size(bad))} of #{to_s(size(insns))} differ"])
    )
    exit_with(1)
  end
end

test "every corpus instruction is byte-identical to llvm-mc"
  insns = corpus
  path = path_join(temp_dir("x86-llvm"), "corpus.s")
  write_file(path, unlines(map(text, insns)))
  r = exec_capture("llvm-mc", "--triple=x86_64", "--show-encoding", path)
  assert status_of(r) == 0
  theirs = filter((e) -> e != nil, map(encoding_of, moji::lines(stdout_of(r))))
  assert size(theirs) == size(insns)
  bad = filter((i) -> encode(insns[i]) != theirs[i], range(0, size(insns)))
  assert is_empty(bad)
end

test "the parsing helpers read llvm-mc's encoding lines"
  assert hex_byte("0x4d") == 77
  assert hex_digit("f") == 15
  assert encoding_of("retq # encoding: [0xc3]") == [195]
  assert encoding_of("no bytes here").nil?
end
