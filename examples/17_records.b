# Records
#
# record names a structure in one line: a constructor taking the fields in
# order or a map of them, a predicate ending in ?, the fields read with a dot,
# and an updated copy written with **. A call that misses a field or names one
# there is not stops at the check stage; a value only known when the program
# runs raises :record, naming the same field. A record is a map carrying its
# name and fields, so == includes the name, it prints as the call that builds
# it, and it crosses JSON and spawn as data under the key "$record". A map whose
# keys stop matching that, after assoc adds one, is a plain map. A record in a
# bidama is reached like any definition, as chizu::point or with a listed name.
use("chizu", %i[leg point])

record trip(name: Str, legs: List(leg))

record stop(name: Str, at: point)

def length_of(t)
  reduce((n, l) -> n + chizu::span(l), 0, t.legs)
end

def outing()
  home = point(0, 0)
  shop = point({x: 3, y: 4})
  trip("errand", [leg(home, shop), leg(shop, home)])
end

def label(x)
  case x
  when stop?
    "stop #{x.name}"
  when trip?
    "trip #{x.name}"
  else
    "other"
  end
end

def mover(parent)
  send(parent, stop(**receive(), name: "there"))
end

test "fields read with a dot, through every level"
  assert outing.legs[0].stop.y == 4
  assert length_of(outing) == 14
end

test "the predicate tells two same-shaped values apart"
  here = stop("here", point(1, 1))
  assert stop?(here)
  assert not trip?(here)
  assert not stop?({name: "here", at: point(1, 1)})
  assert label(here) == "stop here"
  assert label(outing) == "trip errand"
  assert label(1) == "other"
end

test "an update is a copy"
  old = stop("here", point(1, 1))
  moved = stop(**old, at: point(2, 2))
  assert moved.at == point(2, 2)
  assert old.at == point(1, 1)
  assert moved.name == "here"
end

test "equality includes the name"
  assert point(1, 2) == point({y: 2, x: 1})
  assert point(1, 2) != {x: 1, y: 2}
end

test "a record prints as the call that builds it"
  assert to_s(stop("a", point(1, 2))) ==
    "stop({at: chizu::point({x: 1, y: 2}), name: \"a\"})"
end

test "a record crosses JSON with its name, and comes back equal"
  text = json_stringify(outing)
  assert json_read(text) == outing
  assert json_read(json_stringify(point(1, 2))) == point(1, 2)
  assert json_get(json_parse(json_stringify(point(1, 2))), "$record") ==
    "chizu::point(x,y)"
end

test "a map that stops matching its name is a plain map"
  grown = assoc(point(1, 2), :z, 3)
  assert record_name(grown).nil?
  assert not chizu::point?(grown)
end

test "a record crosses a process as data"
  w = spawn(mover, [self])
  send(w, stop("here", point(1, 1)))
  assert receive() == stop("there", point(1, 1))
end

test "a value known only at run time is refused by name"
  make = stop
  e = begin
    make({name: "x", place: point(0, 0)})
  rescue :record as err
    err
  end
  assert e.data.unknown == [:place]
  assert e.data.missing == [:at]
  assert (make(1, point(0, 0)) rescue :refused) == :refused
end
