# Naming sweep: what is applied and what needs a ruling

Source: `N1.tsv` and `N2.tsv` (94 provisional spaces swept 2026-10-22: 28 KEEP, 39 KEEP_WITH_NOTE, 27 REJECT). Method: the `naming` skill over the whole fleet with a file-count control, plus crates.io with a User-Agent and positive and negative controls.

## Applied
The 23 REJECT names whose swept alternative is unambiguous are renamed in `merged/` through `merged/space-renames.tsv`, the last stage of `queries/repair.sql`. Delete a row there to keep the old name and rerun the script.

## Held for a ruling (4 rejected names)
| Name | Why held |
|---|---|
| `assaku` | its alternative `asshuku` is already a space in region B: a merge, not a rename |
| `shigoto`, `tsuuchi` | live fleet repos cover the same subject; the house rule that a word on two rungs stays on both would keep them as the blue face of those repos |
| `haichi` | the alternative `uwagaki` is weak on meaning |

## Pairs that cover the same job (merge or split)
- `rirezu` (E) and `hakkou` (F): release.
- `chizu` (G) and `chiri` (A): coordinates and projection.
- `rokku` (B) and `goui` (C): acquire, elect, fence, lock, release, renew.
- `kyuu`/`junban` (A), `taiki` (B), `messeeji` (C): three queue spaces without a stated split.
- `yuugou` (B) against the shipped `shuugou`: alternative `tougou`.
- `keikaku` against `keiyaku`: one consonant apart; alternative `puran`.

## Other
- `tegata` is claimed by the unratified `theory/TEGATA.md`: ratify the doc and the space as one name.
- `genbo` is the `daicho` crate's object database: name the space only if they share one vocabulary.
- `kumo`, `moderu` and `sekai` are taken crate names with different subjects; kept with notes. Reject exact crate collisions if you prefer.
- The `ky-` head is dense: `kyohi`, `kyuuji`, `kyasshu`, `kyoui`, `kyoujin`.
- `chuukai` is glossed as 中継 but reads `chuukei`, which is reserved; kept with the word taken as 仲介.
