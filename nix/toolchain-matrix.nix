{
  lib,
  entries,
  rows,
}:
let
  buildable = lib.attrNames (lib.filterAttrs (_: e: (e.rung or null) == null) entries);
in
{
  inherit buildable;
  missing = lib.subtractLists (lib.attrNames rows) buildable;
}
