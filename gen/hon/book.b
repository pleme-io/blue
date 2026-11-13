# waive B0085: rendering debt recorded 2026-11-13: no test of this generator declared kind: :rendering feeds its output to the output's reader yet
use("hon", [:write_rendering])

write_rendering(:book, "docs/BOOK.md")
