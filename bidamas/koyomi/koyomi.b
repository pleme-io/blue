use("retsu")
# koyomi (暦) — the proleptic Gregorian calendar, as arithmetic.
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
