//! The solver seam for laws (HORIZON H6): satisfiability of quantifier-free
//! linear integer arithmetic with divisibility, the decidable fragment a law
//! is proved in.
//!
//! A [`Formula`] is in negation normal form over three atoms: `t > 0`,
//! `d | t` and `d ∤ t`, each `t` a [`Lin`] with integer coefficients. A
//! [`Backend`] answers whether a formula has a model: [`Verdict::Unsat`], a
//! [`Verdict::Sat`] model checked against the formula before it is returned,
//! or [`Verdict::Unknown`] with the reason (a step budget spent, a number past
//! the bound), never a guess.
//!
//! [`Backend::Cooper`] is pure Rust: Cooper's quantifier elimination, run as a
//! search that keeps the witness of each eliminated variable, so a satisfiable
//! formula comes back with its model. No C is linked. [`Backend::Absent`] is
//! the typed absence of a solver: it answers `Unknown`, and every law falls
//! back to being tested.

use std::collections::BTreeMap;

/// A variable, by index.
pub type Var = usize;

/// A value for each variable a model names; a variable it does not name is 0.
pub type Model = BTreeMap<Var, i128>;

/// The bound every coefficient and constant stays under, so no step of the
/// search overflows `i128`.
pub const BOUND: i128 = 1 << 62;

/// Search steps one check may take before it answers `Unknown`.
pub const STEPS: usize = 200_000;

/// `Σ coeffs[v]·v + k`.
#[derive(Clone, Debug, Default, PartialEq, Eq, PartialOrd, Ord)]
pub struct Lin {
    pub coeffs: BTreeMap<Var, i128>,
    pub k: i128,
}

/// Why a check stopped without an answer.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Stop {
    Bound,
    Steps,
}

impl std::fmt::Display for Stop {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Bound => write!(f, "a number grew past 2^62"),
            Self::Steps => write!(f, "the search took more than {STEPS} steps"),
        }
    }
}

fn fit(v: i128) -> Result<i128, Stop> {
    if v.abs() < BOUND {
        Ok(v)
    } else {
        Err(Stop::Bound)
    }
}

fn mul(a: i128, b: i128) -> Result<i128, Stop> {
    a.checked_mul(b).ok_or(Stop::Bound).and_then(fit)
}

fn add(a: i128, b: i128) -> Result<i128, Stop> {
    a.checked_add(b).ok_or(Stop::Bound).and_then(fit)
}

fn gcd(a: i128, b: i128) -> i128 {
    let (mut a, mut b) = (a.abs(), b.abs());
    while b != 0 {
        (a, b) = (b, a % b);
    }
    a
}

fn lcm(a: i128, b: i128) -> Result<i128, Stop> {
    if a == 0 || b == 0 {
        return Ok(a.max(b));
    }
    mul(a / gcd(a, b), b).map(i128::abs)
}

impl Lin {
    #[must_use]
    pub fn constant(k: i128) -> Self {
        Self {
            coeffs: BTreeMap::new(),
            k,
        }
    }

    #[must_use]
    pub fn var(v: Var) -> Self {
        Self {
            coeffs: BTreeMap::from([(v, 1)]),
            k: 0,
        }
    }

    #[must_use]
    pub fn is_ground(&self) -> bool {
        self.coeffs.is_empty()
    }

    #[must_use]
    pub fn coeff(&self, v: Var) -> i128 {
        self.coeffs.get(&v).copied().unwrap_or(0)
    }

    /// `self + other`.
    ///
    /// # Errors
    ///
    /// [`Stop::Bound`] when a coefficient leaves the bound.
    pub fn plus(&self, other: &Self) -> Result<Self, Stop> {
        let mut out = self.clone();
        for (v, c) in &other.coeffs {
            let sum = add(out.coeff(*v), *c)?;
            if sum == 0 {
                out.coeffs.remove(v);
            } else {
                out.coeffs.insert(*v, sum);
            }
        }
        out.k = add(out.k, other.k)?;
        Ok(out)
    }

    /// `m · self`.
    ///
    /// # Errors
    ///
    /// [`Stop::Bound`] when a coefficient leaves the bound.
    pub fn scale(&self, m: i128) -> Result<Self, Stop> {
        if m == 0 {
            return Ok(Self::constant(0));
        }
        let mut coeffs = BTreeMap::new();
        for (v, c) in &self.coeffs {
            coeffs.insert(*v, mul(*c, m)?);
        }
        Ok(Self {
            coeffs,
            k: mul(self.k, m)?,
        })
    }

    /// `self` with `v` replaced by `by`.
    ///
    /// # Errors
    ///
    /// [`Stop::Bound`] when a coefficient leaves the bound.
    pub fn subst(&self, v: Var, by: &Self) -> Result<Self, Stop> {
        let c = self.coeff(v);
        if c == 0 {
            return Ok(self.clone());
        }
        let mut rest = self.clone();
        rest.coeffs.remove(&v);
        rest.plus(&by.scale(c)?)
    }

    /// The value under `model`.
    ///
    /// # Errors
    ///
    /// [`Stop::Bound`] when the value leaves the bound.
    pub fn eval(&self, model: &Model) -> Result<i128, Stop> {
        let mut sum = self.k;
        for (v, c) in &self.coeffs {
            sum = add(sum, mul(*c, model.get(v).copied().unwrap_or(0))?)?;
        }
        Ok(sum)
    }
}

/// A formula in negation normal form.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Formula {
    True,
    False,
    /// `t > 0`.
    Pos(Lin),
    /// `d | t`, `d > 0`.
    Dvd(i128, Lin),
    /// `d ∤ t`, `d > 0`.
    NDvd(i128, Lin),
    And(Vec<Formula>),
    Or(Vec<Formula>),
}

impl Formula {
    /// `t > 0`, decided when `t` is ground, and divided through by the gcd
    /// of its coefficients: `g·u + k > 0` is `u + ⌊(k - 1) / g⌋ + 1 > 0`.
    #[must_use]
    pub fn pos(t: Lin) -> Self {
        if t.is_ground() {
            return Self::truth(t.k > 0);
        }
        let g = t.coeffs.values().fold(0, |g, c| gcd(g, *c));
        if g <= 1 {
            return Self::Pos(t);
        }
        Self::Pos(Lin {
            coeffs: t.coeffs.iter().map(|(v, c)| (*v, c / g)).collect(),
            k: (t.k - 1).div_euclid(g) + 1,
        })
    }

    /// `d | t` (`holds`) or `d ∤ t`, decided when `t` is ground or `d` is 1.
    #[must_use]
    pub fn divides(d: i128, t: Lin, holds: bool) -> Self {
        let d = d.abs();
        if d == 1 {
            Self::truth(holds)
        } else if t.is_ground() {
            Self::truth((t.k.rem_euclid(d) == 0) == holds)
        } else if holds {
            Self::Dvd(d, t)
        } else {
            Self::NDvd(d, t)
        }
    }

    #[must_use]
    pub fn truth(b: bool) -> Self {
        if b {
            Self::True
        } else {
            Self::False
        }
    }

    /// The conjunction, flattened and decided where a part is.
    #[must_use]
    pub fn and(parts: Vec<Self>) -> Self {
        let mut out = Vec::new();
        for p in parts {
            match p {
                Self::True => {}
                Self::False => return Self::False,
                Self::And(inner) => out.extend(inner),
                other => out.push(other),
            }
        }
        match out.len() {
            0 => Self::True,
            1 => out.pop().unwrap_or(Self::True),
            _ => Self::And(out),
        }
    }

    /// The disjunction, flattened and decided where a part is.
    #[must_use]
    pub fn or(parts: Vec<Self>) -> Self {
        let mut out = Vec::new();
        for p in parts {
            match p {
                Self::False => {}
                Self::True => return Self::True,
                Self::Or(inner) => out.extend(inner),
                other => out.push(other),
            }
        }
        match out.len() {
            0 => Self::False,
            1 => out.pop().unwrap_or(Self::False),
            _ => Self::Or(out),
        }
    }

    /// The negation, kept in negation normal form: `¬(t > 0)` is `1 - t > 0`.
    ///
    /// # Errors
    ///
    /// [`Stop::Bound`] when a coefficient leaves the bound.
    pub fn not(&self) -> Result<Self, Stop> {
        Ok(match self {
            Self::True => Self::False,
            Self::False => Self::True,
            Self::Pos(t) => Self::pos(t.scale(-1)?.plus(&Lin::constant(1))?),
            Self::Dvd(d, t) => Self::divides(*d, t.clone(), false),
            Self::NDvd(d, t) => Self::divides(*d, t.clone(), true),
            Self::And(ps) => Self::or(ps.iter().map(Self::not).collect::<Result<_, _>>()?),
            Self::Or(ps) => Self::and(ps.iter().map(Self::not).collect::<Result<_, _>>()?),
        })
    }

    /// Whether the formula holds under `model`.
    ///
    /// # Errors
    ///
    /// [`Stop::Bound`] when a value leaves the bound.
    pub fn eval(&self, model: &Model) -> Result<bool, Stop> {
        Ok(match self {
            Self::True => true,
            Self::False => false,
            Self::Pos(t) => t.eval(model)? > 0,
            Self::Dvd(d, t) => t.eval(model)?.rem_euclid(*d) == 0,
            Self::NDvd(d, t) => t.eval(model)?.rem_euclid(*d) != 0,
            Self::And(ps) => {
                for p in ps {
                    if !p.eval(model)? {
                        return Ok(false);
                    }
                }
                true
            }
            Self::Or(ps) => {
                for p in ps {
                    if p.eval(model)? {
                        return Ok(true);
                    }
                }
                false
            }
        })
    }

    fn map_atoms(&self, f: &mut impl FnMut(&Self) -> Result<Self, Stop>) -> Result<Self, Stop> {
        Ok(match self {
            Self::And(ps) => Self::and(
                ps.iter()
                    .map(|p| p.map_atoms(f))
                    .collect::<Result<_, _>>()?,
            ),
            Self::Or(ps) => Self::or(
                ps.iter()
                    .map(|p| p.map_atoms(f))
                    .collect::<Result<_, _>>()?,
            ),
            atom => f(atom)?,
        })
    }

    fn atoms<'a>(&'a self, out: &mut Vec<&'a Self>) {
        match self {
            Self::And(ps) | Self::Or(ps) => ps.iter().for_each(|p| p.atoms(out)),
            Self::True | Self::False => {}
            atom => out.push(atom),
        }
    }

    /// `self` with `v` replaced by `by`, ground atoms decided.
    ///
    /// # Errors
    ///
    /// [`Stop::Bound`] when a coefficient leaves the bound.
    pub fn subst(&self, v: Var, by: &Lin) -> Result<Self, Stop> {
        self.map_atoms(&mut |atom| {
            Ok(match atom {
                Self::Pos(t) => Self::pos(t.subst(v, by)?),
                Self::Dvd(d, t) => Self::divides(*d, t.subst(v, by)?, true),
                Self::NDvd(d, t) => Self::divides(*d, t.subst(v, by)?, false),
                other => other.clone(),
            })
        })
    }

    /// Every variable the formula names, in order.
    #[must_use]
    pub fn vars(&self) -> Vec<Var> {
        let mut atoms = Vec::new();
        self.atoms(&mut atoms);
        let mut vs: Vec<Var> = atoms
            .iter()
            .flat_map(|a| match a {
                Self::Pos(t) | Self::Dvd(_, t) | Self::NDvd(_, t) => {
                    t.coeffs.keys().copied().collect::<Vec<_>>()
                }
                _ => Vec::new(),
            })
            .collect();
        vs.sort_unstable();
        vs.dedup();
        vs
    }
}

/// What a backend answers.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Verdict {
    Unsat,
    Sat(Model),
    Unknown(String),
}

/// The solver behind the seam. A backend that is not here is a state of this
/// type, never a missing branch.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Backend {
    Absent,
    Cooper,
}

impl Backend {
    /// The name a law's result is labelled with.
    #[must_use]
    pub fn name(self) -> &'static str {
        match self {
            Self::Absent => "absent",
            Self::Cooper => "cooper",
        }
    }

    /// Whether `f` has a model.
    #[must_use]
    pub fn check(self, f: &Formula) -> Verdict {
        match self {
            Self::Absent => Verdict::Unknown("no solver is configured".into()),
            Self::Cooper => {
                let mut steps = 0;
                match sat(f, &f.vars(), &mut steps) {
                    Ok(None) => Verdict::Unsat,
                    Ok(Some(model)) => match f.eval(&model) {
                        Ok(true) => Verdict::Sat(model),
                        Ok(false) => {
                            Verdict::Unknown("the model found does not satisfy the formula".into())
                        }
                        Err(e) => Verdict::Unknown(e.to_string()),
                    },
                    Err(e) => Verdict::Unknown(e.to_string()),
                }
            }
        }
    }
}

enum Candidate {
    Far(i128),
    At(Lin, i128),
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Side {
    Low,
    High,
}

struct Plan {
    x: Var,
    l: i128,
    delta: i128,
    side: Side,
    scaled: Formula,
    far: Formula,
    bounds: Vec<Lin>,
}

impl Plan {
    fn cost(&self) -> i128 {
        let bounds = i128::try_from(self.bounds.len()).unwrap_or(i128::MAX);
        self.delta.saturating_mul(bounds.saturating_add(1))
    }

    fn point(&self, cand: &Candidate) -> Result<Lin, Stop> {
        let sign = if self.side == Side::Low { 1 } else { -1 };
        match cand {
            Candidate::Far(j) => Ok(Lin::constant(sign * j)),
            Candidate::At(b, j) => b.plus(&Lin::constant(sign * j)),
        }
    }
}

fn sat(f: &Formula, vars: &[Var], steps: &mut usize) -> Result<Option<Model>, Stop> {
    *steps += 1;
    if *steps > STEPS {
        return Err(Stop::Steps);
    }
    match f {
        Formula::True => return Ok(Some(Model::new())),
        Formula::False => return Ok(None),
        _ => {}
    }
    if vars.is_empty() {
        return Ok(f.eval(&Model::new())?.then(Model::new));
    }
    let mut best: Option<Plan> = None;
    for &x in vars {
        let p = plan(f, x)?;
        if best.as_ref().is_none_or(|b| p.cost() < b.cost()) {
            best = Some(p);
        }
    }
    let Some(p) = best else {
        return Ok(None);
    };
    let rest: Vec<Var> = vars.iter().copied().filter(|v| *v != p.x).collect();
    let far = (1..=p.delta).map(Candidate::Far);
    let at = p
        .bounds
        .iter()
        .flat_map(|b| (1..=p.delta).map(move |j| Candidate::At(b.clone(), j)));
    for cand in far.chain(at) {
        *steps += 1;
        if *steps > STEPS {
            return Err(Stop::Steps);
        }
        let at = p.point(&cand)?;
        let psi = match &cand {
            Candidate::Far(_) => p.far.subst(p.x, &at)?,
            Candidate::At(..) => p.scaled.subst(p.x, &at)?,
        };
        if psi == Formula::False {
            continue;
        }
        if let Some(mut model) = sat(&psi, &rest, steps)? {
            let xv = match &cand {
                Candidate::At(..) => at.eval(&model)?,
                Candidate::Far(_) => far_witness(&p, at.k, &model)?,
            };
            model.insert(p.x, xv / p.l);
            return Ok(Some(model));
        }
    }
    Ok(None)
}

fn plan(f: &Formula, x: Var) -> Result<Plan, Stop> {
    let mut atoms = Vec::new();
    f.atoms(&mut atoms);
    let mut l = 1;
    for a in &atoms {
        if let Formula::Pos(t) | Formula::Dvd(_, t) | Formula::NDvd(_, t) = a {
            let c = t.coeff(x);
            if c != 0 {
                l = lcm(l, c)?;
            }
        }
    }
    let unit = |t: &Lin, c: i128| -> Result<Lin, Stop> {
        let mut s = t.scale(l / c.abs())?;
        s.coeffs.insert(x, c.signum());
        Ok(s)
    };
    let scaled = f.map_atoms(&mut |atom| {
        Ok(match atom {
            Formula::Pos(t) if t.coeff(x) != 0 => Formula::Pos(unit(t, t.coeff(x))?),
            Formula::Dvd(d, t) if t.coeff(x) != 0 => {
                Formula::divides(mul(*d, l / t.coeff(x).abs())?, unit(t, t.coeff(x))?, true)
            }
            Formula::NDvd(d, t) if t.coeff(x) != 0 => {
                Formula::divides(mul(*d, l / t.coeff(x).abs())?, unit(t, t.coeff(x))?, false)
            }
            other => other.clone(),
        })
    })?;
    let scaled = Formula::and(vec![scaled, Formula::divides(l, Lin::var(x), true)]);
    let mut atoms = Vec::new();
    scaled.atoms(&mut atoms);
    let mut delta = 1;
    let (mut lows, mut highs) = (Vec::new(), Vec::new());
    for a in &atoms {
        match a {
            Formula::Dvd(d, t) | Formula::NDvd(d, t) if t.coeff(x) != 0 => {
                delta = lcm(delta, *d)?;
            }
            Formula::Pos(t) if t.coeff(x) != 0 => {
                let mut b = t.clone();
                b.coeffs.remove(&x);
                if t.coeff(x) == 1 {
                    lows.push(b.scale(-1)?);
                } else {
                    highs.push(b);
                }
            }
            _ => {}
        }
    }
    let (side, mut bounds) = if highs.len() < lows.len() {
        (Side::High, highs)
    } else {
        (Side::Low, lows)
    };
    bounds.sort();
    bounds.dedup();
    let far = scaled.map_atoms(&mut |atom| {
        Ok(match atom {
            Formula::Pos(t) if t.coeff(x) != 0 => {
                Formula::truth((t.coeff(x) == 1) == (side == Side::High))
            }
            other => other.clone(),
        })
    })?;
    Ok(Plan {
        x,
        l,
        delta,
        side,
        scaled,
        far,
        bounds,
    })
}

fn far_witness(p: &Plan, start: i128, model: &Model) -> Result<i128, Stop> {
    let mut atoms = Vec::new();
    p.scaled.atoms(&mut atoms);
    let mut edge = start;
    for a in atoms {
        if let Formula::Pos(t) = a {
            let mut rest = t.clone();
            rest.coeffs.remove(&p.x);
            let r = rest.eval(model)?;
            match (p.side, t.coeff(p.x)) {
                (Side::Low, 1) => edge = edge.min(-r),
                (Side::Low, -1) => edge = edge.min(add(r, -1)?),
                (Side::High, 1) => edge = edge.max(add(1, -r)?),
                (Side::High, -1) => edge = edge.max(r),
                _ => {}
            }
        }
    }
    let gap = (edge - start).abs();
    let k = (gap + p.delta - 1) / p.delta;
    let step = mul(p.delta, k)?;
    add(start, if p.side == Side::Low { -step } else { step })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn lin(pairs: &[(Var, i128)], k: i128) -> Lin {
        Lin {
            coeffs: pairs.iter().copied().collect(),
            k,
        }
    }

    #[test]
    fn a_contradiction_has_no_model() {
        let f = Formula::and(vec![
            Formula::pos(lin(&[(0, 1)], 0)),
            Formula::pos(lin(&[(0, -1)], 0)),
        ]);
        assert_eq!(Backend::Cooper.check(&f), Verdict::Unsat);
    }

    #[test]
    fn a_satisfiable_formula_comes_back_with_a_model_that_satisfies_it() {
        let f = Formula::and(vec![
            Formula::pos(lin(&[(0, 2), (1, -3)], -1)),
            Formula::divides(5, lin(&[(0, 1)], 0), true),
            Formula::pos(lin(&[(1, 1)], 2)),
        ]);
        match Backend::Cooper.check(&f) {
            Verdict::Sat(m) => assert!(f.eval(&m).unwrap(), "{m:?}"),
            other => panic!("{other:?}"),
        }
    }

    #[test]
    fn an_even_number_is_never_odd() {
        let f = Formula::and(vec![
            Formula::divides(2, lin(&[(0, 1)], 0), true),
            Formula::divides(2, lin(&[(0, 1)], 1), true),
        ]);
        assert_eq!(Backend::Cooper.check(&f), Verdict::Unsat);
    }

    #[test]
    fn integers_have_no_point_strictly_between_neighbours() {
        let f = Formula::and(vec![
            Formula::pos(lin(&[(0, 2)], 0)),
            Formula::pos(lin(&[(0, -2)], 2)),
        ]);
        assert_eq!(Backend::Cooper.check(&f), Verdict::Unsat);
    }

    #[test]
    fn a_formula_unbounded_below_gets_a_witness_below_every_bound() {
        let f = Formula::and(vec![
            Formula::pos(lin(&[(0, -1), (1, 1)], -100)),
            Formula::divides(7, lin(&[(0, 1)], 3), true),
            Formula::pos(lin(&[(1, 1)], 0)),
        ]);
        match Backend::Cooper.check(&f) {
            Verdict::Sat(m) => assert!(f.eval(&m).unwrap(), "{m:?}"),
            other => panic!("{other:?}"),
        }
    }

    #[test]
    fn the_absent_backend_answers_unknown_and_never_unsat() {
        assert!(matches!(
            Backend::Absent.check(&Formula::False),
            Verdict::Unknown(_)
        ));
    }

    struct Draws(u64);

    impl Draws {
        fn below(&mut self, n: u64) -> i128 {
            self.0 = self
                .0
                .wrapping_mul(6_364_136_223_846_793_005)
                .wrapping_add(1_442_695_040_888_963_407);
            i128::from((self.0 >> 33) % n)
        }

        fn lin(&mut self) -> Lin {
            let mut coeffs = BTreeMap::new();
            for v in 0..3 {
                let c = self.below(7) - 3;
                if c != 0 {
                    coeffs.insert(v, c);
                }
            }
            Lin {
                coeffs,
                k: self.below(13) - 6,
            }
        }

        fn atom(&mut self) -> Formula {
            if self.below(3) > 0 {
                return Formula::pos(self.lin());
            }
            let d = self.below(2) + 2;
            let t = self.lin();
            Formula::divides(d, t, self.below(2) == 0)
        }

        fn formula(&mut self, depth: u32) -> Formula {
            if depth == 0 {
                return self.atom();
            }
            match self.below(4) {
                0 => self.atom(),
                1 | 2 => Formula::and((0..4).map(|_| self.formula(depth - 1)).collect()),
                _ => Formula::or((0..2).map(|_| self.formula(depth - 1)).collect()),
            }
        }
    }

    fn model_in_box(f: &Formula) -> Option<Model> {
        let r = -9..=9;
        for a in r.clone() {
            for b in r.clone() {
                for c in r.clone() {
                    let m = Model::from([(0, a), (1, b), (2, c)]);
                    if f.eval(&m).unwrap() {
                        return Some(m);
                    }
                }
            }
        }
        None
    }

    #[test]
    fn cooper_agrees_with_a_search_of_the_box_on_drawn_formulas() {
        let mut draws = Draws(7);
        let (mut unsat, mut sat, mut unknown) = (0, 0, 0);
        let mut drawn = Vec::new();
        for _ in 0..200 {
            let f = draws.formula(1);
            drawn.push(Formula::and(vec![f.clone(), draws.formula(1)]));
            drawn.push(f);
        }
        for f in drawn {
            match Backend::Cooper.check(&f) {
                Verdict::Unsat => {
                    assert_eq!(model_in_box(&f), None, "{f:?}");
                    unsat += 1;
                }
                Verdict::Sat(m) => {
                    assert!(f.eval(&m).unwrap(), "{f:?} {m:?}");
                    sat += 1;
                }
                Verdict::Unknown(_) => unknown += 1,
            }
        }
        assert!(
            unsat > 20 && sat > 20 && unknown < 60,
            "unsat {unsat}, sat {sat}, unknown {unknown}"
        );
    }

    #[test]
    fn negation_stays_exact_over_the_integers() {
        let t = lin(&[(0, 1)], -3);
        let f = Formula::pos(t);
        for v in -10..10 {
            let m = Model::from([(0, v)]);
            assert_ne!(f.eval(&m).unwrap(), f.not().unwrap().eval(&m).unwrap());
        }
    }
}
