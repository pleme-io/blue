import json, sys

with open(sys.argv[1]) as f:
    records = json.load(f)
print(sum(r["value"] for r in records))
