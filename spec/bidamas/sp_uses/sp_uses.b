# A package that uses another; its importer does not see sp_mod.
use("sp_mod", [:sp_twice])

def sp_quad(x)
  sp_twice(sp_twice(x))
end
