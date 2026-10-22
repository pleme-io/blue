space("gyouretsu", {status: :ratified})

verb(
  "gyouretsu",
  "add",
  {
    kind: :pure,
    shape: "add(a, b) -> matrix",
    laterals: ["error"],
    fleet: nil,
    today: "exists:gyouretsu",
    meaning: "entrywise sum; shape mismatch raises",
    wave: 0,
    origin: "A"
  }
)

verb(
  "gyouretsu",
  "compile",
  {
    kind: :pure,
    shape: "compile(graph) -> compiled graph",
    laterals: ["validate"],
    fleet: "ml-forge",
    today: "absent",
    meaning: "compile a tensor graph; shapes proved before any run",
    wave: 3,
    origin: "G"
  }
)

verb(
  "gyouretsu",
  "cross",
  {
    kind: :pure,
    shape: "cross(a, b) -> vector",
    laterals: ["error"],
    fleet: nil,
    today: "exists:gyouretsu",
    meaning: "cross product of two 3-vectors",
    wave: 0,
    origin: "A"
  }
)

verb(
  "gyouretsu",
  "decompose",
  {
    kind: :pure,
    shape: "decompose(m, kind) -> record",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "LU, QR, Cholesky or SVD factors",
    wave: 3,
    origin: "A"
  }
)

verb(
  "gyouretsu",
  "determinant",
  {
    kind: :pure,
    shape: "determinant(m) -> number",
    laterals: ["error"],
    fleet: nil,
    today: "exists:gyouretsu",
    meaning: "signed volume factor of a square matrix",
    wave: 0,
    origin: "A"
  }
)

verb(
  "gyouretsu",
  "diagsum",
  {
    kind: :pure,
    shape: "diagsum(m) -> number",
    laterals: ["error"],
    fleet: nil,
    today: "exists:gyouretsu",
    meaning: "sum of the diagonal",
    wave: 0,
    origin: "A"
  }
)

verb(
  "gyouretsu",
  "dot",
  {
    kind: :pure,
    shape: "dot(a, b) -> number",
    laterals: ["error"],
    fleet: nil,
    today: "exists:gyouretsu",
    meaning: "inner product of two vectors",
    wave: 0,
    origin: "A"
  }
)

verb(
  "gyouretsu",
  "eigen",
  {
    kind: :pure,
    shape: "eigen(m) -> record",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "eigenvalues and eigenvectors",
    wave: 4,
    origin: "A"
  }
)

verb(
  "gyouretsu",
  "eye",
  {
    kind: :pure,
    shape: "eye(n) -> matrix",
    laterals: [],
    fleet: nil,
    today: "exists:gyouretsu",
    meaning: "n by n identity matrix",
    wave: 0,
    origin: "A"
  }
)

verb(
  "gyouretsu",
  "inverse",
  {
    kind: :pure,
    shape: "inverse(m) -> matrix",
    laterals: ["error"],
    fleet: nil,
    today: "exists:gyouretsu",
    meaning: "matrix that multiplies to identity; singular raises",
    wave: 0,
    origin: "A"
  }
)

verb(
  "gyouretsu",
  "matrix",
  {
    kind: :pure,
    shape: "matrix(rows) -> matrix",
    laterals: ["error", "validate"],
    fleet: nil,
    today: "partial:gyouretsu",
    meaning: "build a matrix from rows of numbers",
    wave: 0,
    origin: "A"
  }
)

verb(
  "gyouretsu",
  "multiply",
  {
    kind: :pure,
    shape: "multiply(a, b) -> matrix",
    laterals: ["error"],
    fleet: nil,
    today: "exists:gyouretsu",
    meaning: "matrix product",
    wave: 0,
    origin: "A"
  }
)

verb(
  "gyouretsu",
  "norm",
  {
    kind: :pure,
    shape: "norm(v, order) -> number",
    laterals: [],
    fleet: nil,
    today: "exists:gyouretsu",
    meaning: "length of a vector in a chosen norm",
    wave: 0,
    origin: "A"
  }
)

verb(
  "gyouretsu",
  "normalize",
  {
    kind: :pure,
    shape: "normalize(v) -> vector",
    laterals: ["error"],
    fleet: nil,
    today: "exists:gyouretsu",
    meaning: "vector scaled to length one",
    wave: 0,
    origin: "A"
  }
)

verb(
  "gyouretsu",
  "power",
  {
    kind: :pure,
    shape: "power(m, n) -> matrix",
    laterals: ["error"],
    fleet: nil,
    today: "exists:gyouretsu",
    meaning: "matrix times itself n times",
    wave: 0,
    origin: "A"
  }
)

verb(
  "gyouretsu",
  "rank",
  {
    kind: :pure,
    shape: "rank(m, opts) -> int",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "number of independent rows",
    wave: 2,
    origin: "A"
  }
)

verb(
  "gyouretsu",
  "reshape",
  {
    kind: :pure,
    shape: "reshape(m, rows, cols) -> matrix",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "same entries in a new shape",
    wave: 2,
    origin: "A"
  }
)

verb(
  "gyouretsu",
  "run",
  {
    kind: :effect,
    shape: "run(compiled, inputs) -> tensors",
    laterals: ["deadline", "resource"],
    fleet: "ml-forge",
    today: "absent",
    meaning: "run a compiled graph on CPU or GPU",
    wave: 4,
    origin: "G"
  }
)

verb(
  "gyouretsu",
  "scale",
  {
    kind: :pure,
    shape: "scale(m, k) -> matrix",
    laterals: [],
    fleet: nil,
    today: "exists:gyouretsu",
    meaning: "every entry multiplied by a number",
    wave: 0,
    origin: "A"
  }
)

verb(
  "gyouretsu",
  "shape",
  {
    kind: :pure,
    shape: "shape(m) -> record",
    laterals: [],
    fleet: nil,
    today: "exists:gyouretsu",
    meaning: "row and column counts",
    wave: 0,
    origin: "A"
  }
)

verb(
  "gyouretsu",
  "solve",
  {
    kind: :pure,
    shape: "solve(a, b) -> vector",
    laterals: ["error"],
    fleet: nil,
    today: "exists:gyouretsu",
    meaning: "vector x with a times x equal to b",
    wave: 0,
    origin: "A"
  }
)

verb(
  "gyouretsu",
  "stack",
  {
    kind: :pure,
    shape: "stack(matrices, axis) -> matrix",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "matrices joined side by side or one above another",
    wave: 2,
    origin: "A"
  }
)

verb(
  "gyouretsu",
  "tensor",
  {
    kind: :decl,
    shape: "tensor(shape, dtype) -> tensor",
    laterals: ["validate"],
    fleet: "ml-forge",
    today: "absent",
    meaning: "declare an n-dimensional array with symbolic shape",
    wave: 3,
    origin: "G"
  }
)

verb(
  "gyouretsu",
  "transpose",
  {
    kind: :pure,
    shape: "transpose(m) -> matrix",
    laterals: [],
    fleet: nil,
    today: "exists:gyouretsu",
    meaning: "rows and columns swapped",
    wave: 0,
    origin: "A"
  }
)

verb(
  "gyouretsu",
  "zeros",
  {
    kind: :pure,
    shape: "zeros(rows, cols) -> matrix",
    laterals: [],
    fleet: nil,
    today: "exists:gyouretsu",
    meaning: "matrix of zeros",
    wave: 0,
    origin: "A"
  }
)

edge(
  "gyouretsu::eigen",
  :composes,
  "gyouretsu::decompose",
  "iterate on factors"
)

edge(
  "gyouretsu::rank",
  :composes,
  "gyouretsu::decompose",
  "count nonzero pivots"
)

edge(
  "gyouretsu::inverse",
  :composes,
  "gyouretsu::determinant",
  "zero determinant raises"
)

edge("gyouretsu::multiply", :composes, "gyouretsu::dot", "row dot column")
edge("gyouretsu::norm", :composes, "gyouretsu::dot", "root of self dot")

edge(
  "gyouretsu::solve",
  :composes,
  "gyouretsu::inverse",
  "x equals inverse times b"
)

edge("gyouretsu::power", :composes, "gyouretsu::multiply", "repeated product")
edge("gyouretsu::normalize", :composes, "gyouretsu::norm", "divide by length")
edge("gyouretsu::transpose", :composes, "gyouretsu::shape", "swap the shape")
edge("gyouretsu::matrix", :composes, "retsu::chunk", "rows from a flat list")
edge("gyouretsu::stack", :composes, "retsu::concat", "join rows or columns")
edge("gyouretsu::reshape", :composes, "retsu::flatten", "flatten, then chunk")
edge("gyouretsu::transpose", :composes, "retsu::zip", "columns become rows")
edge("gyouretsu::shape", :guards, "gyouretsu::add", "add needs equal shapes")

edge(
  "gyouretsu::matrix",
  :guards,
  "gyouretsu::multiply",
  "multiply needs a matrix"
)

edge("gyouretsu::compile", :guards, "gyouretsu::run", "no run of a bad shape")
edge("gyouretsu::scale", :pairs, "gyouretsu::add", "both are entrywise")

edge(
  "gyouretsu::solve",
  :pairs,
  "gyouretsu::decompose",
  "factor once, solve many"
)

edge(
  "gyouretsu::cross",
  :pairs,
  "gyouretsu::dot",
  "perpendicular versus parallel"
)

edge(
  "gyouretsu::zeros",
  :pairs,
  "gyouretsu::eye",
  "additive and multiplicative units"
)

edge(
  "gyouretsu::eye",
  :pairs,
  "gyouretsu::inverse",
  "a times inverse is identity"
)

edge("gyouretsu::dot", :pairs, "gyouretsu::norm", "length is root of self dot")

edge(
  "gyouretsu::solve",
  :pairs,
  "gyouretsu::rank",
  "a unique solution needs full rank"
)

edge("gyouretsu::solve", :pairs, "kinji::fit", "linear solve inside fitting")
edge("gyouretsu::dot", :refines, "gyouretsu::multiply", "row times column")
edge("gyouretsu::run", :requires, "gyouretsu::compile", "runs a plan")
edge("gyouretsu::tensor", :requires, "gyouretsu::compile", "shape proved")
edge("gyouretsu::solve", :requires, "gyouretsu::decompose", "solve by factors")

edge(
  "gyouretsu::decompose",
  :requires,
  "gyouretsu::determinant",
  "singular matrices limit kinds"
)

edge("gyouretsu::add", :requires, "gyouretsu::shape", "shapes must match")
edge("gyouretsu::determinant", :requires, "gyouretsu::shape", "square only")
edge("gyouretsu::diagsum", :requires, "gyouretsu::shape", "square only")
edge("gyouretsu::multiply", :requires, "gyouretsu::shape", "columns match rows")
edge("gyouretsu::reshape", :requires, "gyouretsu::shape", "same entry count")

edge(
  "gyouretsu::stack",
  :requires,
  "gyouretsu::shape",
  "shared edge must match"
)

edge(
  "gyouretsu::tensor",
  :requires,
  "gyouretsu::solve",
  "dense math kept in Rust"
)

edge(
  "gyouretsu::decompose",
  :requires,
  "gyouretsu::tensor",
  "arrays of numbers"
)
