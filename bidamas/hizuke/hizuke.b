use("retsu")
# hizuke (日付) — the proleptic Gregorian calendar, as arithmetic.
#
# No clock. Every function here is a pure function of numbers, which is what
# makes a calendar testable: "what day was 2000-01-01" has one answer forever,
# whereas anything reading a system clock has a different answer every run and
# can only be tested against itself.

def is_leap(y)
  if y % 400 == 0
    true
  else
    if y % 100 == 0
      false
    else
      y % 4 == 0
    end
  end
end

def days_in_month(y, m)
  if m == 2
    if is_leap(y)
      29
    else
      28
    end
  else
    if m == 4 || m == 6 || m == 9 || m == 11
      30
    else
      31
    end
  end
end

def days_in_year(y)
  if is_leap(y)
    366
  else
    365
  end
end

# Day of the year, 1-based.
def ordinal_day(y, m, d)
  d + reduce(fn(acc, mm) acc + days_in_month(y, mm) end, 0, range(1, m))
end

# Day of week by Zeller's congruence: 0 = Sunday.
#
# Zeller counts January and February as months 13 and 14 of the PREVIOUS year,
# which is the step every from-scratch implementation forgets and which makes
# every January date wrong by a fixed offset — a bug that looks like a
# timezone problem and is not.
def day_of_week(y, m, d)
  mm = if m < 3
    m + 12
  else
    m
  end
  yy = if m < 3
    y - 1
  else
    y
  end
  k = yy % 100
  j = floor(yy / 100)
  h = (d + floor((13 * (mm + 1)) / 5) + k + floor(k / 4) + floor(j / 4) + (5 * j)) % 7
  # Zeller yields 0 = Saturday; shift so 0 = Sunday, which is what callers
  # expect from a `day_of_week`.
  (h + 6) % 7
end

def is_weekend(y, m, d)
  w = day_of_week(y, m, d)
  w == 0 || w == 6
end

def day_name(w)
  nth(w, ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"])
end

# A serial day number: 0001-01-01 is day 1, counting proleptic Gregorian days
# with no gaps. This is THE missing primitive — the gap between two dates, the
# date n days later, and "did the month roll over" are all subtraction once a
# date is a single number, and none of them need a calendar table.
#
# Howard Hinnant's civil-from-days algebra. It shifts the year to begin in
# March so the 31/30 month pattern is regular and February's variable length
# falls off the END of the year, where a leap day cannot disturb any month
# after it — the trick that makes the whole thing branch-free.
def to_day_number(y, m, d)
  ys = if m < 3
    y - 1
  else
    y
  end
  era = floor(ys / 400)
  yoe = ys - era * 400
  mp = if m > 2
    m - 3
  else
    m + 9
  end
  doy = floor((153 * mp + 2) / 5) + d - 1
  doe = yoe * 365 + floor(yoe / 4) - floor(yoe / 100) + doy
  # 305 = the March-shift offset that puts 0001-01-01 at 1.
  era * 146097 + doe - 305
end

# The exact inverse of to_day_number, as [year, month, day].
#
# Returning a three-element list rather than three values is what lets
# add_days/next_day/easter compose: their result is itself a date.
def from_day_number(n)
  z = n + 305
  era = floor(z / 146097)
  doe = z - era * 146097
  yoe = floor((doe - floor(doe / 1460) + floor(doe / 36524) - floor(doe / 146096)) / 365)
  ys = yoe + era * 400
  doy = doe - (365 * yoe + floor(yoe / 4) - floor(yoe / 100))
  mp = floor((5 * doy + 2) / 153)
  d = doy - floor((153 * mp + 2) / 5) + 1
  m = if mp < 10
    mp + 3
  else
    mp - 9
  end
  y = if m < 3
    ys + 1
  else
    ys
  end
  [y, m, d]
end

# Named accessors, so a caller never has to remember that month is index 1.
def year_of(dt)
  nth(0, dt)
end

def month_of(dt)
  nth(1, dt)
end

def day_of(dt)
  nth(2, dt)
end

# Positive when the SECOND date is the later one, matching how "days between
# now and the deadline" is asked in prose.
def days_between(y1, m1, d1, y2, m2, d2)
  to_day_number(y2, m2, d2) - to_day_number(y1, m1, d1)
end

def add_days(y, m, d, n)
  from_day_number(to_day_number(y, m, d) + n)
end

def next_day(y, m, d)
  add_days(y, m, d, 1)
end

def prev_day(y, m, d)
  add_days(y, m, d, 0 - 1)
end

# add_days for a date that is already a list — the form that chains, because
# every date-returning function here hands back exactly what this takes.
def shift_days(dt, n)
  add_days(year_of(dt), month_of(dt), day_of(dt), n)
end

# Months are 1-based, matching every other function in this file, so the list
# index is m - 1. Defined for 1..12.
def month_name(m)
  nth(m - 1, ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"])
end

def day_of_week_name(y, m, d)
  day_name(day_of_week(y, m, d))
end

def quarter(m)
  floor((m - 1) / 3) + 1
end

# The guard that stops 2023-02-29 and 2024-13-01 from silently becoming a real
# day number: to_day_number happily normalises nonsense, so anything parsing
# user input must ask this FIRST.
def is_valid_date(y, m, d)
  m >= 1 && m <= 12 && d >= 1 && d <= days_in_month(y, m)
end

def is_month_end(y, m, d)
  d == days_in_month(y, m)
end

# Returns a DATE, not a count — days_in_month already answers the count, and a
# date is what add_days/day_of_week/is_weekend can be handed next.
def last_day_of_month(y, m)
  [y, m, days_in_month(y, m)]
end

def first_day_of_month(y, m)
  [y, m, 1]
end

def is_business_day(y, m, d)
  !is_weekend(y, m, d)
end

# 0001-01-01 was a Monday and day numbers have no gaps, so the day number mod 7
# IS the weekday on the same 0=Sunday scale day_of_week uses — no offset table.
# That coincidence is what makes counting weekdays over a span cheap.
def weekday_of_day_number(n)
  n % 7
end

# The plain "which week of this year" count: weeks start on Sunday and week 1
# is whatever week contains 1 January, so week 1 is usually a partial week and
# a long year can reach week 53. This is deliberately NOT iso_week — the two
# disagree at both ends of the year, and picking the wrong one silently shifts
# every report by a week.
def week_of_year(y, m, d)
  floor((ordinal_day(y, m, d) + day_of_week(y, 1, 1) - 1) / 7) + 1
end

# ISO 8601 numbers weekdays 1..7 starting MONDAY, unlike day_of_week's 0=Sunday.
# That is not gratuitous: an ISO week belongs to the year containing its
# Thursday, which is only the midpoint if the week starts on Monday.
def iso_weekday(y, m, d)
  w = day_of_week(y, m, d)
  if w == 0
    7
  else
    w
  end
end

# A 53-week ISO year is exactly one starting on Thursday, or a leap year
# starting on Wednesday — in both cases 1 January's week has its Thursday in
# this year AND 31 December's does too.
def iso_weeks_in_year(y)
  j = iso_weekday(y, 1, 1)
  if j == 4 || (is_leap(y) && j == 3)
    53
  else
    52
  end
end

# The raw ISO week index, which may fall OFF either end of its own year: 0 or
# less means the date belongs to the last week of the previous year, and more
# than iso_weeks_in_year means it belongs to week 1 of the next. iso_week and
# iso_week_year resolve the same overflow in the two different directions, so
# they are computed from this one shared expression.
def iso_week_raw(y, m, d)
  floor((ordinal_day(y, m, d) - iso_weekday(y, m, d) + 10) / 7)
end

def iso_week(y, m, d)
  w = iso_week_raw(y, m, d)
  if w < 1
    iso_weeks_in_year(y - 1)
  else
    if w > iso_weeks_in_year(y)
      1
    else
      w
    end
  end
end

# The year an ISO week belongs to, which is NOT always the calendar year — the
# reason an ISO week number is meaningless without it.
def iso_week_year(y, m, d)
  w = iso_week_raw(y, m, d)
  if w < 1
    y - 1
  else
    if w > iso_weeks_in_year(y)
      y + 1
    else
      y
    end
  end
end

# Completed years between a birth date and a given date. "Today" is an argument
# because hizuke has no clock — which is also what makes the answer testable.
# A birthday that has not yet arrived this year does not count, so someone born
# on 29 February is 0 years older on 28 February of a non-leap year.
def age_in_years(by, bm, bd, y, m, d)
  n = y - by
  if m < bm || (m == bm && d < bd)
    n - 1
  else
    n
  end
end

# Adding a month is not adding 30 days, and the trap is the SHORT target month:
# 31 January plus one month has no 31 February to land on, so the day clamps to
# the month end. Clamping is what every calendar UI does, and it makes this
# lossy — add one month then subtract one and 31 January comes back as 28/29
# February, not 31 January.
def add_months(y, m, d, n)
  t = y * 12 + (m - 1) + n
  ny = floor(t / 12)
  nm = (t % 12) + 1
  [ny, nm, min(d, days_in_month(ny, nm))]
end

# The same clamp one dimension up: 29 February plus a year is 28 February.
def add_years(y, m, d, n)
  add_months(y, m, d, n * 12)
end

# -1 / 0 / 1, so it can drive a sort. Comparing day numbers instead of
# year-then-month-then-day leaves only one thing that can be wrong.
def compare_dates(y1, m1, d1, y2, m2, d2)
  n = days_between(y1, m1, d1, y2, m2, d2)
  if n > 0
    0 - 1
  else
    if n < 0
      1
    else
      0
    end
  end
end

# Counts at the DAY-NUMBER level and tests the weekday with a single mod,
# rather than converting each day back into a calendar date — over a year that
# is one subtraction per day instead of 365 full from_day_number inversions.
def business_days_in_span(a, b)
  size(filter(fn(n) weekday_of_day_number(n) > 0 && weekday_of_day_number(n) < 6 end, range(a, b)))
end

# Business days in the HALF-OPEN span [start, end) — start counted, end
# excluded — so adjacent spans add up and a zero-length span is 0. Negative
# when the end precedes the start, matching days_between's sign convention.
#
# Holidays are deliberately absent: which days a jurisdiction observes is data
# about a place, not arithmetic about the calendar, and baking one country's
# list in here would make the function wrong everywhere else.
def business_days_between(y1, m1, d1, y2, m2, d2)
  a = to_day_number(y1, m1, d1)
  b = to_day_number(y2, m2, d2)
  if b < a
    0 - business_days_in_span(b, a)
  else
    business_days_in_span(a, b)
  end
end

# Easter Sunday, by the anonymous Gregorian algorithm (Meeus/Jones/Butcher).
#
# There is no closed form: Easter is the first Sunday after the ecclesiastical
# full moon falling on or after 21 March, so this is a table of corrections to
# a lunar cycle rather than a derivation, and the constants cannot be sanity-
# checked by reading them. The only honest verification is published dates plus
# the two invariants — it is always a Sunday, and it always falls between
# 22 March and 25 April.
def easter(y)
  a = y % 19
  b = floor(y / 100)
  c = y % 100
  q = floor(b / 4)
  e = b % 4
  f = floor((b + 8) / 25)
  g = floor((b - f + 1) / 3)
  h = (19 * a + b - q - g + 15) % 30
  i = floor(c / 4)
  k = c % 4
  l = (32 + 2 * e + 2 * i - h - k) % 7
  p = floor((a + 11 * h + 22 * l) / 451)
  n = h + l - 7 * p + 114
  [y, floor(n / 31), (n % 31) + 1]
end

# The inverse of ordinal_day. Day 60 is 29 February in 2024 and 1 March in
# 2023, which is the pair showing an ordinal means nothing without its year.
def date_from_ordinal(y, n)
  from_day_number(to_day_number(y, 1, 1) + n - 1)
end

# "The fourth Thursday of November" — how holiday and meeting rules are
# actually written. w is on day_of_week's 0=Sunday scale; n is 1-based.
#
# The trap is the gap to the first matching weekday: subtracting goes negative
# half the time, so it has to be taken modulo 7. Nothing here bounds n, so a
# fifth weekday a month does not have yields a day past the month end — ask
# is_valid_date before using the result for anything.
def nth_weekday_of_month(y, m, w, n)
  offset = (w - day_of_week(y, m, 1)) % 7
  [y, m, 1 + offset + 7 * (n - 1)]
end

# "The last Monday in May" — the other half of the holiday vocabulary, and the
# half that cannot be rewritten as an nth: some Mays have five Mondays and some
# four, so counting from the END is the only rule that is stable year to year.
def last_weekday_of_month(y, m, w)
  ld = days_in_month(y, m)
  [y, m, ld - ((day_of_week(y, m, ld) - w) % 7)]
end

# Left-pads with zeros to a fixed width, returning the number unchanged if it
# is already wider.
def zero_pad(n, width)
  pad_to(to_s(n), width)
end

# The recursive worker: one zero per pass, so the width is a stop condition
# rather than a computed count that could go negative.
def pad_to(s, width)
  if size(chars(s)) >= width
    s
  else
    pad_to(concat("0", s), width)
  end
end

# ISO 8601 is FIXED WIDTH: "2024-02-09", never "2024-2-9". The padding is the
# only reason this is not a bare join — an unpadded date string sorts wrong,
# and sorting correctly as text is the entire point of writing dates this way.
# Defined for years 0..9999, the range the basic format covers.
def format_iso(y, m, d)
  join([zero_pad(y, 4), zero_pad(m, 2), zero_pad(d, 2)], "-")
end

# The same, for a date that is already a list — so easter, add_days and the
# weekday-of-month rules can be printed without being taken apart first.
def format_iso_date(dt)
  format_iso(year_of(dt), month_of(dt), day_of(dt))
end

test "leap years, including the century rules"
  # 1900 is NOT a leap year and 2000 IS — the pair that separates a correct
  # implementation from `y % 4 == 0`.
  assert is_leap(2000) == true
  assert is_leap(1900) == false
  assert is_leap(2024) == true
  assert is_leap(2023) == false
end

test "days in month and year"
  assert days_in_month(2024, 2) == 29
  assert days_in_month(2023, 2) == 28
  assert days_in_month(2023, 4) == 30
  assert days_in_month(2023, 12) == 31
  assert days_in_year(2024) == 366
end

test "ordinal day"
  assert ordinal_day(2023, 1, 1) == 1
  assert ordinal_day(2023, 12, 31) == 365
  assert ordinal_day(2024, 12, 31) == 366
  assert ordinal_day(2024, 3, 1) == 61
end

test "day of week against dates everyone can check"
  # 2000-01-01 was a Saturday; a January date, so this also pins the
  # month-13 correction Zeller needs.
  assert day_of_week(2000, 1, 1) == 6
  assert day_name(day_of_week(2000, 1, 1)) == "Saturday"
  # 2024-02-29 was a Thursday — a leap day, in a shifted month.
  assert day_of_week(2024, 2, 29) == 4
  # 1969-07-20, the Apollo 11 landing, was a Sunday.
  assert day_of_week(1969, 7, 20) == 0
  assert is_weekend(2000, 1, 1) == true
end

test "the serial day number is anchored where it claims to be"
  # The definition of the epoch, and the day before it — which only exists if
  # the calendar really is proleptic rather than clamped at year 1.
  assert to_day_number(1, 1, 1) == 1
  assert from_day_number(0) == [0, 12, 31]
  # 1970-01-01 is Rata Die 719163; an independently published constant.
  assert to_day_number(1970, 1, 1) == 719163
end

test "to_day_number and from_day_number are exact inverses"
  # Round-tripping is the only cheap proof that the two direction-specific
  # magic constants agree; every one of these is a boundary the March-shifted
  # algebra has to cross.
  assert from_day_number(to_day_number(2024, 2, 29)) == [2024, 2, 29]
  assert from_day_number(to_day_number(2023, 12, 31)) == [2023, 12, 31]
  assert from_day_number(to_day_number(2024, 3, 1)) == [2024, 3, 1]
  assert from_day_number(to_day_number(1900, 3, 1)) == [1900, 3, 1]
  assert from_day_number(to_day_number(1, 1, 1)) == [1, 1, 1]
  assert from_day_number(to_day_number(2000, 12, 31)) == [2000, 12, 31]
end

test "the serial number agrees with Zeller's congruence"
  # day_of_week and to_day_number are two INDEPENDENT implementations of the
  # same fact. 0001-01-01 was a Monday, so day-number mod 7 lands on the same
  # 0=Sunday scale — if either one drifts, this disagrees.
  assert to_day_number(2000, 1, 1) % 7 == day_of_week(2000, 1, 1)
  assert to_day_number(1969, 7, 20) % 7 == day_of_week(1969, 7, 20)
  assert to_day_number(2024, 2, 29) % 7 == day_of_week(2024, 2, 29)
  assert to_day_number(1, 1, 1) % 7 == day_of_week(1, 1, 1)
end

test "days between two dates"
  # 10957 days from the Unix epoch to 2000-01-01 — a number anyone can check.
  assert days_between(1970, 1, 1, 2000, 1, 1) == 10957
  assert days_between(2024, 1, 1, 2024, 1, 1) == 0
  # The pair a leap-blind implementation gets wrong in exactly one of the two.
  assert days_between(2024, 2, 28, 2024, 3, 1) == 2
  assert days_between(2023, 2, 28, 2023, 3, 1) == 1
  # Reversing the arguments negates the answer.
  assert days_between(2000, 1, 1, 1970, 1, 1) == 0 - 10957
  assert days_between(2023, 12, 31, 2024, 1, 1) == 1
end

test "add_days, and its inverse"
  assert add_days(2023, 12, 31, 1) == [2024, 1, 1]
  # 2000 was a leap year, so a full year is 366 days.
  assert add_days(2000, 1, 1, 366) == [2001, 1, 1]
  assert add_days(1900, 1, 1, 365) == [1901, 1, 1]
  # Going forward then back is the identity, including across a leap day.
  assert shift_days(shift_days([2024, 2, 27], 40), 0 - 40) == [2024, 2, 27]
  assert shift_days([2024, 2, 27], 40) == [2024, 4, 7]
  assert add_days(2024, 3, 1, 0 - 1) == [2024, 2, 29]
end

test "next_day and prev_day step over the month and year seams"
  assert next_day(2024, 2, 28) == [2024, 2, 29]
  assert next_day(2023, 2, 28) == [2023, 3, 1]
  assert next_day(2023, 12, 31) == [2024, 1, 1]
  assert prev_day(2024, 1, 1) == [2023, 12, 31]
  assert prev_day(2024, 3, 1) == [2024, 2, 29]
  assert prev_day(1900, 3, 1) == [1900, 2, 28]
end

test "date accessors name the three slots"
  assert year_of([2024, 2, 29]) == 2024
  assert month_of([2024, 2, 29]) == 2
  assert day_of([2024, 2, 29]) == 29
end

test "month names are 1-based"
  # The last one is the assertion that catches an off-by-one; the first passes
  # under either indexing convention.
  assert month_name(1) == "January"
  assert month_name(12) == "December"
  assert month_name(2) == "February"
  assert day_of_week_name(2000, 1, 1) == "Saturday"
  assert day_of_week_name(1969, 7, 20) == "Sunday"
end

test "quarters"
  # 3 and 4 are the pair: floor(m / 3) + 1 puts March in Q2 and still gets
  # January, June and December right.
  assert quarter(1) == 1
  assert quarter(3) == 1
  assert quarter(4) == 2
  assert quarter(6) == 2
  assert quarter(9) == 3
  assert quarter(12) == 4
end

test "is_valid_date rejects what to_day_number would silently normalise"
  assert is_valid_date(2024, 2, 29) == true
  assert is_valid_date(2023, 2, 29) == false
  assert is_valid_date(2024, 4, 31) == false
  assert is_valid_date(2024, 13, 1) == false
  assert is_valid_date(2024, 0, 1) == false
  assert is_valid_date(2024, 1, 0) == false
  assert is_valid_date(2024, 12, 31) == true
end

test "month ends"
  assert is_month_end(2024, 2, 29) == true
  assert is_month_end(2024, 2, 28) == false
  assert is_month_end(2023, 2, 28) == true
  assert last_day_of_month(2024, 2) == [2024, 2, 29]
  assert last_day_of_month(2023, 2) == [2023, 2, 28]
  assert first_day_of_month(2024, 7) == [2024, 7, 1]
  # The day after the last day of a month is always the 1st of the next one —
  # the property that ties last_day_of_month to the day-number arithmetic.
  assert shift_days(last_day_of_month(2024, 2), 1) == [2024, 3, 1]
  assert shift_days(last_day_of_month(2023, 12), 1) == [2024, 1, 1]
end

test "business days are the complement of the weekend"
  # 2000-01-01 was a Saturday, 2000-01-03 the following Monday.
  assert is_business_day(2000, 1, 1) == false
  assert is_business_day(2000, 1, 2) == false
  assert is_business_day(2000, 1, 3) == true
end

test "weekday straight off a day number"
  # The same answer as Zeller, with no month correction at all — which only
  # holds because day 1 was a Monday.
  assert weekday_of_day_number(to_day_number(2000, 1, 1)) == 6
  assert weekday_of_day_number(1) == 1
  assert weekday_of_day_number(7) == 0
end

test "the simple Sunday-start week number"
  # 2000-01-01 was a Saturday, so it sits alone in a one-day week 1 and the
  # Sunday immediately after starts week 2.
  assert week_of_year(2000, 1, 1) == 1
  assert week_of_year(2000, 1, 2) == 2
  # 2024-01-01 was a Monday, so week 1 runs Mon..Sat and week 2 opens Jan 7.
  assert week_of_year(2024, 1, 1) == 1
  assert week_of_year(2024, 1, 6) == 1
  assert week_of_year(2024, 1, 7) == 2
end

test "ISO weekdays start on Monday"
  # 2000-01-01 was a Saturday: 6 on both scales. The Sunday after is 0 on the
  # calendar scale and 7 on the ISO one — the only day the two disagree, and
  # the whole reason iso_weekday exists.
  assert iso_weekday(2000, 1, 1) == 6
  assert day_of_week(2000, 1, 2) == 0
  assert iso_weekday(2000, 1, 2) == 7
  assert iso_weekday(2024, 1, 1) == 1
end

test "long ISO years"
  # 2020 started on a Wednesday and was a leap year; 2015 started on a
  # Thursday. Both have 53 weeks, for the two different reasons.
  assert iso_weeks_in_year(2020) == 53
  assert iso_weeks_in_year(2015) == 53
  assert iso_weeks_in_year(2024) == 52
  assert iso_weeks_in_year(2000) == 52
end

test "ISO weeks that belong to the neighbouring year"
  # 2024-12-30 is a Monday and is 2025-W01: the week number and the calendar
  # year point at different years, which is the case that makes a bare week
  # number useless.
  assert iso_week(2024, 12, 30) == 1
  assert iso_week_year(2024, 12, 30) == 2025
  # 2021-01-01 was a Friday, and belongs to 2020-W53.
  assert iso_week(2021, 1, 1) == 53
  assert iso_week_year(2021, 1, 1) == 2020
  # 2020-12-31 was a Thursday, so it stays in its own year's 53rd week.
  assert iso_week(2020, 12, 31) == 53
  assert iso_week_year(2020, 12, 31) == 2020
  # 2000-01-01 is 1999-W52 — and the plain week_of_year calls the same day
  # week 1 of 2000. The two conventions disagreeing here is the point.
  assert iso_week(2000, 1, 1) == 52
  assert iso_week_year(2000, 1, 1) == 1999
  assert week_of_year(2000, 1, 1) == 1
  # A mid-year date, where every convention agrees and nothing is clever.
  assert iso_week(2024, 6, 12) == 24
  assert iso_week_year(2024, 6, 12) == 2024
end

test "every ISO week number is in range, all year"
  # 366 days of 2024, none of which may produce a week 0 or a week 54.
  assert size(filter(fn(n) iso_week(year_of(from_day_number(n)), month_of(from_day_number(n)), day_of(from_day_number(n))) > 0 end, range(to_day_number(2024, 1, 1), to_day_number(2025, 1, 1)))) == 366
  assert size(filter(fn(n) iso_week(year_of(from_day_number(n)), month_of(from_day_number(n)), day_of(from_day_number(n))) < 54 end, range(to_day_number(2024, 1, 1), to_day_number(2025, 1, 1)))) == 366
end

test "age counts completed years only"
  assert age_in_years(2000, 6, 15, 2024, 6, 15) == 24
  # The day before the birthday is still the previous age.
  assert age_in_years(2000, 6, 15, 2024, 6, 14) == 23
  assert age_in_years(2000, 6, 15, 2024, 12, 31) == 24
  assert age_in_years(2000, 6, 15, 2024, 1, 1) == 23
  # Born on a leap day: no 29 February in 2025, so on 28 February the birthday
  # has not arrived and on 1 March it has.
  assert age_in_years(2024, 2, 29, 2025, 2, 28) == 0
  assert age_in_years(2024, 2, 29, 2025, 3, 1) == 1
  assert age_in_years(2024, 2, 29, 2028, 2, 29) == 4
end

test "add_months clamps into short months"
  assert add_months(2024, 1, 31, 1) == [2024, 2, 29]
  assert add_months(2023, 1, 31, 1) == [2023, 2, 28]
  assert add_months(2024, 3, 31, 0 - 1) == [2024, 2, 29]
  # Rolling over the year boundary in both directions.
  assert add_months(2024, 12, 31, 1) == [2025, 1, 31]
  assert add_months(2024, 1, 15, 0 - 1) == [2023, 12, 15]
  assert add_months(2024, 5, 15, 0) == [2024, 5, 15]
  # 12 months is a year, and a day that exists in both months survives it.
  assert add_months(2024, 5, 15, 12) == [2025, 5, 15]
  # The clamp is LOSSY: out and back does not return 31 January.
  assert add_months(2024, 2, 29, 0 - 1) == [2024, 1, 29]
end

test "add_years clamps the leap day"
  assert add_years(2024, 2, 29, 1) == [2025, 2, 28]
  assert add_years(2024, 2, 29, 4) == [2028, 2, 29]
  assert add_years(2024, 6, 15, 0 - 10) == [2014, 6, 15]
  # 1900 is not a leap year, so the century rule reaches this too.
  assert add_years(1896, 2, 29, 4) == [1900, 2, 28]
end

test "comparing dates"
  assert compare_dates(2024, 1, 1, 2024, 1, 2) == 0 - 1
  assert compare_dates(2024, 1, 2, 2024, 1, 1) == 1
  assert compare_dates(2024, 1, 1, 2024, 1, 1) == 0
  # Same day number, different sides of a year boundary.
  assert compare_dates(2023, 12, 31, 2024, 1, 1) == 0 - 1
  # A day-only difference a year-then-month comparison could drop.
  assert compare_dates(2024, 3, 9, 2024, 3, 10) == 0 - 1
end

test "counting business days"
  # 2024-01-01 was a Monday: the half-open week to the following Monday holds
  # exactly the five weekdays.
  assert business_days_between(2024, 1, 1, 2024, 1, 8) == 5
  # Half-open means a zero-length span is zero, and adjacent spans add up.
  assert business_days_between(2024, 1, 1, 2024, 1, 1) == 0
  assert business_days_between(2024, 1, 1, 2024, 1, 4) + business_days_between(2024, 1, 4, 2024, 1, 8) == 5
  # Saturday to Sunday contains one day, and it is not a business day.
  assert business_days_between(2024, 1, 6, 2024, 1, 7) == 0
  # 2024 had 262 weekdays: 52 whole weeks plus the Monday and Tuesday that
  # 366 days leaves over.
  assert business_days_between(2024, 1, 1, 2025, 1, 1) == 262
  # Reversing the span negates the count.
  assert business_days_between(2024, 1, 8, 2024, 1, 1) == 0 - 5
end

test "Easter against published dates"
  # Five dates anyone can look up, including the two extremes of the whole
  # 22 March .. 25 April window.
  assert easter(2024) == [2024, 3, 31]
  assert easter(2025) == [2025, 4, 20]
  assert easter(2000) == [2000, 4, 23]
  assert easter(2016) == [2016, 3, 27]
  assert easter(1818) == [1818, 3, 22]
  assert easter(2038) == [2038, 4, 25]
end

test "Easter obeys its own invariants for two centuries"
  # 200 consecutive years, each cross-checked against Zeller: if the lunar
  # correction table were wrong anywhere, some year would land off a Sunday.
  assert size(filter(fn(yy) day_of_week(yy, month_of(easter(yy)), day_of(easter(yy))) == 0 end, range(1900, 2100))) == 200
  # And every one of them falls inside the 22 March .. 25 April window.
  assert size(filter(fn(yy) compare_dates(yy, 3, 22, yy, month_of(easter(yy)), day_of(easter(yy))) < 1 && compare_dates(yy, month_of(easter(yy)), day_of(easter(yy)), yy, 4, 25) < 1 end, range(1900, 2100))) == 200
end

test "ordinal day round-trips through its own year"
  # Day 60 is the pair that separates the two years.
  assert date_from_ordinal(2024, 60) == [2024, 2, 29]
  assert date_from_ordinal(2023, 60) == [2023, 3, 1]
  assert date_from_ordinal(2024, 1) == [2024, 1, 1]
  assert date_from_ordinal(2024, 366) == [2024, 12, 31]
  assert date_from_ordinal(2023, 365) == [2023, 12, 31]
  # And it really is ordinal_day's inverse, not merely close to it.
  assert ordinal_day(2024, month_of(date_from_ordinal(2024, 200)), day_of(date_from_ordinal(2024, 200))) == 200
end

test "the nth weekday of a month"
  # US Thanksgiving is the fourth Thursday of November: 28 Nov 2024 and
  # 23 Nov 2023 — two years whose 1 November falls on different weekdays, so
  # this fails if the offset is subtracted instead of taken modulo 7.
  assert nth_weekday_of_month(2024, 11, 4, 4) == [2024, 11, 28]
  assert nth_weekday_of_month(2023, 11, 4, 4) == [2023, 11, 23]
  # US Labor Day, the first Monday of September 2024.
  assert nth_weekday_of_month(2024, 9, 1, 1) == [2024, 9, 2]
  # Whatever comes back really is that weekday.
  assert day_of_week(2024, 11, day_of(nth_weekday_of_month(2024, 11, 4, 4))) == 4
  # A fifth Thursday November 2024 does not have: the result overflows the
  # month, and is_valid_date is what catches it.
  assert is_valid_date(2024, 11, day_of(nth_weekday_of_month(2024, 11, 4, 5))) == false
  assert is_valid_date(2024, 8, day_of(nth_weekday_of_month(2024, 8, 4, 5))) == true
end

test "the last weekday of a month"
  # US Memorial Day is the last Monday in May: 27 May 2024, 29 May 2023.
  assert last_weekday_of_month(2024, 5, 1) == [2024, 5, 27]
  assert last_weekday_of_month(2023, 5, 1) == [2023, 5, 29]
  # When the month ends exactly on the wanted weekday the answer is the last
  # day itself, not a week earlier — the off-by-seven this rule invites.
  assert last_weekday_of_month(2024, 5, 5) == [2024, 5, 31]
  assert day_of_week(2024, 5, 31) == 5
  # February in a leap year, where the month end itself moves.
  assert last_weekday_of_month(2024, 2, 4) == [2024, 2, 29]
end

test "ISO formatting is fixed width"
  # The single-digit month and day are the whole point; "2024-2-9" would sort
  # after "2024-11-01", which is the bug padding exists to prevent.
  assert format_iso(2024, 2, 9) == "2024-02-09"
  assert format_iso(2024, 12, 31) == "2024-12-31"
  assert format_iso(1, 1, 1) == "0001-01-01"
  assert format_iso(999, 10, 5) == "0999-10-05"
  assert zero_pad(7, 2) == "07"
  # Already wide enough: padding must not truncate.
  assert zero_pad(2024, 2) == "2024"
  assert format_iso_date(easter(2024)) == "2024-03-31"
  assert format_iso_date(add_days(2023, 12, 31, 1)) == "2024-01-01"
end
