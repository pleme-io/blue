# Conformance fixture packages

Tiny bidamas the module rows in `spec/rows/modules.b` load. The conformance
runner puts this directory first on the load path, ahead of `bidamas/`.
Every name carries the `sp_` prefix so no fixture collides with a real
package. These are not part of the public distribution.
