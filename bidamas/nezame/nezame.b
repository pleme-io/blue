@moduledoc """
nezame (寝覚め) — waking up: how a machine came back, read after the fact. It reads the firmware's wake-up type, whether the hardware watchdog reset the board, how long the machine was dark between its last boot's final log line and this boot's first, and what the kernel left in persistent storage, and names the way the outage ended: a clean reboot, a watchdog reset, power restored, or a person at the power button. It also keeps what it writes bounded: a ledger cut to its newest rows and an archive pruned to its newest entries.

    outage(wake_record("Power Switch", 0, 8478, 0), 300) #=> :person
"""

use("deeta", [:get_int])
use("junjo", [:sort_by])
use("mitoshi/keisoku", [:sample_line])
use("moji", %i[lines trim])
use("retsu", %i[last size take_last_n take_n])

@doc """
wake_type: the firmware's wake-up type from `dmidecode -t 1` output, or "unread" when the line is absent.

    wake_type("System Information\n\tWake-up Type: Power Switch") #=> "Power Switch"
"""
def wake_type(dmi)
  line = find(lines(dmi), (l) -> contains?(l, "Wake-up Type:"))
  if line.nil?
    "unread"
  else
    trim(replace(trim(line), "Wake-up Type:", ""))
  end
end

@doc """
wake_name: the SMBIOS System Information wake-up type for its code (byte 0x18 of the type 1 structure), in the words dmidecode prints, or "unread" for a code outside the table.

    wake_name(6) #=> "Power Switch"
    wake_name(8) #=> "AC Power Restored"
"""
def wake_name(code)
  names = [
    "Reserved",
    "Other",
    "Unknown",
    "APM Timer",
    "Modem Ring",
    "LAN Remote",
    "Power Switch",
    "PCI PME#",
    "AC Power Restored"
  ]
  if code.nil? or code < 0 or code >= size(names)
    "unread"
  else
    names[code]
  end
end

@doc """
watchdog_reset?: whether a watchdog's `bootstatus` says the last reset was the card's own (WDIOF_CARDRESET, 0x20).

    watchdog_reset?("32") #=> true
    watchdog_reset?("0") #=> false
"""
def watchdog_reset?(bootstatus)
  n = to_int(trim(bootstatus or "")) or 0
  bit_and(n, 32) != 0
end

@doc """
boots: the boots `journalctl --list-boots -o json` names, oldest first, each as {index, first_s, last_s}.

    size(boots("[]")) #=> 0
"""
def boots(list_boots_json)
  rows = json_parse(list_boots_json) rescue []
  read = map(
    fn(r)
      {
        index: get_int(r, "index", 0),
        first_s: get_int(r, "first_entry", 0) / 1_000_000,
        last_s: get_int(r, "last_entry", 0) / 1_000_000
      }
    end,
    rows or []
  )
  sort_by((b) -> b[:index], read)
end

@doc """
dark_seconds: how long the machine logged nothing between the previous boot's last line and this boot's first, or nil with fewer than two boots.

    dark_seconds([{index: -1, first_s: 0, last_s: 100}, {index: 0, first_s: 400, last_s: 900}]) #=> 300
"""
def dark_seconds(bs)
  if size(bs) < 2
    nil
  else
    this = last(bs)
    previous = bs[size(bs) - 2]
    this[:first_s] - previous[:last_s]
  end
end

@doc """
wake_record: one boot's evidence as a map.

    wake_record("Power Switch", 0, 60, 1)[:pstore] #=> 1
"""
def wake_record(wake, watchdog, dark, pstore)
  {wake:, watchdog:, dark:, pstore:}
end

@doc """
outage: how the outage before this boot ended: `:watchdog` when the card reset the board, `:power_restored` on AC restored, `:person` when the power button woke a machine dark longer than `grace` seconds, `:reboot` when it came back within `grace`, else `:unknown`.

    outage(wake_record("Power Switch", 0, 30, 0), 300) #=> :reboot
    outage(wake_record("Power Switch", 32, 900, 0), 300) #=> :watchdog
    outage(wake_record("AC Power Restored", 0, 900, 0), 300) #=> :power_restored
"""
def outage(r, grace)
  dark = r[:dark]
  if watchdog_reset?(to_s(r[:watchdog]))
    :watchdog
  elsif r[:wake] == "AC Power Restored"
    :power_restored
  elsif dark.nil?
    :unknown
  elsif dark <= grace
    :reboot
  elsif r[:wake] == "Power Switch"
    :person
  else
    :unknown
  end
end

@doc """
ledger_row: one boot as a ledger row: when it was read, the evidence, and the outage it names.

    ledger_row(10, wake_record("Power Switch", 0, 30, 0), 300)[:outage] #=> "reboot"
"""
def ledger_row(now_s, r, grace)
  {
    at: now_s,
    wake: r[:wake],
    watchdog: r[:watchdog],
    dark_seconds: r[:dark],
    pstore_entries: r[:pstore],
    outage: to_s(outage(r, grace))
  }
end

@doc """
bounded: the newest `keep` lines of a ledger text, with `row` appended, as the text to write back; the ledger never grows past `keep` rows.

    size(lines(bounded("", "d", 2))) #=> 1
"""
def bounded(text, row, keep)
  kept = take_last_n(
    append(filter((l) -> trim(l) != "", lines(text or "")), [row]),
    keep
  )
  unlines([join(kept, line_break)])
end

@doc """
expired: the entries of an archive, oldest first, that fall outside its newest `keep`.

    expired(["a", "b", "c"], 2) #=> ["a"]
    expired(["a"], 2) #=> []
"""
def expired(entries, keep)
  take_n(entries, size(entries) - keep)
end

@doc """
metric_lines: a ledger row as Prometheus samples: the dark seconds, the watchdog flag, the pstore count, and a 1 on the series naming the outage.

    size(metric_lines(ledger_row(10, wake_record("Power Switch", 0, 30, 0), 300))) #=> 4
"""
def metric_lines(row)
  wake = {wake: row[:wake], outage: row[:outage]}
  reset = if watchdog_reset?(to_s(row[:watchdog]))
    1
  else
    0
  end
  map(
    sample_line,
    [
      {
        name: "nezame_dark_seconds",
        labels: wake,
        value: row[:dark_seconds] or 0
      },
      {name: "nezame_watchdog_reset", labels: {}, value: reset},
      {name: "nezame_pstore_entries", labels: {}, value: row[:pstore_entries]},
      {name: "nezame_boot_read_seconds", labels: wake, value: row[:at]}
    ]
  )
end

test "the watchdog flag is the card-reset bit alone, and an unread status is no reset"
  assert watchdog_reset?("32")
  assert watchdog_reset?("48")
  assert not watchdog_reset?("16")
  assert not watchdog_reset?("0")
  assert not watchdog_reset?("")
  assert not watchdog_reset?(nil)
end

test "the empty cases: no boots, no wake line, an empty ledger"
  assert dark_seconds([]).nil?
  assert dark_seconds(boots("not json")).nil?
  assert wake_type("") == "unread"
  assert bounded("", "x", 3) == unlines(["x"])
  assert expired([], 3) == []
end

test "identity: the ledger keeps every row while it is under its bound"
  assert bounded(join_lines(%w[a b]), "c", 5) == unlines(%w[a b c])
  assert expired(%w[a b], 5) == []
end

test "an independently checkable value: today's rio outage reads as a person at the button"
  bs = boots("[{\"index\":-1,\"first_entry\":1794816125000000,\"last_entry\":1794826517000000},{\"index\":0,\"first_entry\":1794834995000000,\"last_entry\":1794852000000000}]")
  dark = dark_seconds(bs)
  assert dark == 8478
  assert outage(
    wake_record(wake_type("\tWake-up Type: Power Switch"), "0", dark, 0),
    300
  ) == :person
end

test "control: a quick warm reboot is a reboot, and a watchdog reset wins over the button"
  assert outage(wake_record("Power Switch", 0, 26, 0), 300) == :reboot
  assert outage(wake_record("Power Switch", 32, 8478, 0), 300) == :watchdog
  assert outage(wake_record("Other", 0, nil, 0), 300) == :unknown
end

test "the SMBIOS wake codes read as dmidecode prints them, and an out-of-table code is unread"
  assert wake_name(0) == "Reserved"
  assert wake_name(6) == "Power Switch"
  assert wake_name(8) == "AC Power Restored"
  assert wake_name(9) == "unread"
  assert wake_name(nil) == "unread"
end

test "the ledger and the archive stay bounded however many boots go by"
  text = reduce((acc, i) -> bounded(acc, to_s(i), 50), "", range(0, 500))
  assert size(filter((l) -> l != "", lines(text))) == 50
  assert last(filter((l) -> l != "", lines(text))) == "499"
  assert size(expired(map(to_s, range(0, 30)), 20)) == 10
end

test "metrics: one sample per fact, the outage named in a label"
  m = metric_lines(ledger_row(7, wake_record("Power Switch", 0, 8478, 2), 300))
  assert size(m) == 4
  assert contains?(m[0], "outage=\"person\"")
  assert contains?(m[0], " 8478")
  assert m[2] == "nezame_pstore_entries 2"
end

test "AC restored names the power, and a watchdog reset is a 1 on its own sample"
  assert outage(wake_record("AC Power Restored", 0, 900, 0), 300) ==
    :power_restored
  assert outage(wake_record("Other", 0, 900, 0), 300) == :unknown
  m = metric_lines(
    ledger_row(7, wake_record("Power Switch", "32", 900, 0), 300)
  )
  assert m[1] == "nezame_watchdog_reset 1"
  assert contains?(m[0], "outage=\"watchdog\"")
end
