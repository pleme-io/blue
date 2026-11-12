use("mokuroku", %i[catalog_of quality_drift quality_section registered_only])
use("retsu", %i[concat_lists first is_empty rest size])

def bidamas_root()
  path_join(getenv("GEN_ROOT", "."), "bidamas")
end

def records_at(root)
  registered_only(read_file(path_join(root, "NAMES.md")), catalog_of([root]))
end

def drift_text(drift)
  unlines(
    map((d) -> "#{d[0]} #{d[1]}: CATALOG says #{d[2]}, computed #{d[3]}", drift)
  )
end

test "every quality signal in CATALOG.md is the one Bluefile.lock and the sources compute"
  root = bidamas_root
  records = records_at(root)
  drift = quality_drift(read_file(path_join(root, "CATALOG.md")), records)
  if not is_empty(drift)
    raise(:quality_drift, drift_text(drift))
  end
  assert size(records) > 50
end

test "a hand-edited signal, a lost row and a row the packages do not have are each named"
  records = records_at(bidamas_root)
  text = unlines(quality_section(records))
  assert quality_drift(text, records) == []
  r = first(records)
  name = r[0]
  edited = replace(
    text,
    "| [`#{name}`](##{name}) | ",
    "| [`#{name}`](##{name}) | 9999/9999 | "
  )
  hit = quality_drift(edited, records)
  assert size(hit) > 0
  assert first(hit)[0] == name
  assert first(hit)[1] == "docs"
  assert first(hit)[2] == "9999/9999"
  lost = quality_drift(
    text,
    concat_lists(records, [["zz-extra", "1", [], "", [], 0]])
  )
  assert lost == [%w[zz-extra row absent present]]
  stray = quality_drift(text, rest(records))
  assert stray == [[name, "row", "present", "absent"]]
end
