pub use blue_lang_host_macros::host;
pub use blue_lang_runtime::domain::DomainError;
pub use blue_lang_runtime::hosted::{CallError, FramedError, Hosted};
pub use blue_lang_runtime::uses::{Entry, Loader, NoLoader};
pub use blue_lang_runtime::RunError;
pub use blue_lang_waku::Capability;
pub use tatara_lisp::TataraDomain;
pub use tatara_lisp_eval::vm::Budget;
pub use tatara_lisp_eval::{
    Arity, EvalError, FromValue, Interpreter, IntoValue, MapKey, Span, Value,
};

#[cfg(feature = "packages")]
pub use blue_lang_pkg::embedded::Standard;

pub trait Host: Sized + 'static {
    const SURFACE: &'static [HostFn];

    fn install_into<O: 'static>(interp: &mut Interpreter<O>, part: fn(&mut O) -> &mut Self);

    fn install(interp: &mut Interpreter<Self>) {
        Self::install_into(interp, |h| h);
    }
}

impl Host for () {
    const SURFACE: &'static [HostFn] = &[];

    fn install_into<O: 'static>(_: &mut Interpreter<O>, _: fn(&mut O) -> &mut Self) {}
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct HostFn {
    pub name: &'static str,
    pub params: &'static [&'static str],
    pub required: usize,
    pub doc: &'static str,
}

#[must_use]
pub fn host_effect_names() -> Vec<&'static str> {
    Capability::host_effects()
        .into_iter()
        .flat_map(Capability::names)
        .collect()
}

#[derive(Debug, Clone, PartialEq)]
pub struct Domain<T>(pub T);

impl<T: TataraDomain> FromValue for Domain<T> {
    fn from_value(v: &Value, at: Span) -> Result<Self, EvalError> {
        blue_lang_runtime::domain::compile_value(v)
            .map(Domain)
            .map_err(|e| EvalError::native_fn(T::KEYWORD, e.to_string(), at))
    }
}

type Extension<'a, H> = Box<dyn FnOnce(&mut Interpreter<H>) + 'a>;

pub struct Load<'a, H: Host> {
    entry: Entry<'a>,
    loader: &'a dyn Loader,
    extensions: Vec<Extension<'a, H>>,
    frame: Option<(&'a dyn Fn(&str) -> bool, Budget)>,
    canonical: Canonical,
}

impl<'a, H: Host> Load<'a, H> {
    #[must_use]
    pub fn loader(mut self, loader: &'a dyn Loader) -> Self {
        self.loader = loader;
        self
    }

    #[must_use]
    pub fn extend(mut self, install: impl FnOnce(&mut Interpreter<H>) + 'a) -> Self {
        self.extensions.push(Box::new(install));
        self
    }

    #[must_use]
    pub fn part<P: Host>(self, project: fn(&mut H) -> &mut P) -> Self {
        self.extend(move |interp| P::install_into(interp, project))
    }

    #[must_use]
    pub fn canonical(mut self, canonical: Canonical) -> Self {
        self.canonical = canonical;
        self
    }

    #[must_use]
    pub fn frame(mut self, permits: &'a dyn Fn(&str) -> bool, budget: Budget) -> Self {
        self.frame = Some((permits, budget));
        self
    }

    pub fn load(self, host: &mut H) -> Result<Program<H>, Error> {
        if self.canonical == Canonical::Required {
            let label = self.entry.path.map_or_else(
                || "the host's entry program".to_owned(),
                |p| p.display().to_string(),
            );
            blue_lang_pkg::canonical::require(&label, self.entry.text)?;
        }
        let extensions = self.extensions;
        let install = move |interp: &mut Interpreter<H>| {
            H::install(interp);
            for extension in extensions {
                extension(interp);
            }
        };
        let hosted = match self.frame {
            Some((permits, budget)) => blue_lang_runtime::hosted::load_hosted_in_frame(
                self.entry,
                self.loader,
                host,
                install,
                permits,
                budget,
            )?,
            None => blue_lang_runtime::hosted::load_hosted(self.entry, self.loader, host, install)?,
        };
        Ok(Program { hosted })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Canonical {
    #[default]
    Required,
    AsWritten,
}

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(transparent)]
    NotCanonical(#[from] blue_lang_pkg::canonical::Refusal),
    #[error(transparent)]
    Load(#[from] RunError),
    #[error(transparent)]
    Framed(#[from] FramedError),
    #[error(transparent)]
    Call(#[from] CallError),
    #[error("{name} returned a value the host cannot read: {message}")]
    Returned { name: String, message: String },
}

pub trait Args {
    fn into_args(self) -> Vec<Value>;
}

impl Args for Vec<Value> {
    fn into_args(self) -> Vec<Value> {
        self
    }
}

macro_rules! args_tuple {
    ($($t:ident),*) => {
        impl<$($t: IntoValue),*> Args for ($($t,)*) {
            #[allow(non_snake_case)]
            fn into_args(self) -> Vec<Value> {
                let ($($t,)*) = self;
                vec![$($t.into_value()),*]
            }
        }
    };
}

args_tuple!();
args_tuple!(A);
args_tuple!(A, B);
args_tuple!(A, B, C);
args_tuple!(A, B, C, D);
args_tuple!(A, B, C, D, E);
args_tuple!(A, B, C, D, E, F);
args_tuple!(A, B, C, D, E, F, G);
args_tuple!(A, B, C, D, E, F, G, I);

pub struct Program<H: Host> {
    hosted: Hosted<H>,
}

impl<H: Host> Program<H> {
    #[must_use]
    pub fn builder(entry: Entry<'_>) -> Load<'_, H> {
        #[cfg(feature = "packages")]
        let loader: &dyn Loader = &Standard;
        #[cfg(not(feature = "packages"))]
        let loader: &dyn Loader = &NoLoader;
        Load {
            entry,
            loader,
            extensions: Vec::new(),
            frame: None,
            canonical: Canonical::Required,
        }
    }

    #[cfg(feature = "packages")]
    pub fn load(entry: Entry<'_>, host: &mut H) -> Result<Self, Error> {
        Self::load_with(entry, &Standard, host)
    }

    pub fn load_with(entry: Entry<'_>, loader: &dyn Loader, host: &mut H) -> Result<Self, Error> {
        Self::builder(entry).loader(loader).load(host)
    }

    pub fn load_in_frame(
        entry: Entry<'_>,
        loader: &dyn Loader,
        host: &mut H,
        permits: &dyn Fn(&str) -> bool,
        budget: Budget,
    ) -> Result<Self, Error> {
        Self::builder(entry)
            .loader(loader)
            .frame(permits, budget)
            .load(host)
    }

    #[must_use]
    pub fn defines(&self, name: &str) -> bool {
        self.hosted.defines(name)
    }

    pub fn call<R: FromValue>(
        &mut self,
        name: &str,
        args: impl Args,
        host: &mut H,
    ) -> Result<R, Error> {
        let value = self.hosted.try_call(name, args.into_args(), host)?;
        read(name, &value)
    }

    pub fn call_budgeted<R: FromValue>(
        &mut self,
        name: &str,
        args: impl Args,
        host: &mut H,
        budget: Budget,
    ) -> Result<R, Error> {
        let value = self
            .hosted
            .call_budgeted(name, args.into_args(), host, budget)?;
        read(name, &value)
    }

    #[must_use]
    pub fn hosted(&self) -> &Hosted<H> {
        &self.hosted
    }

    #[must_use]
    pub fn into_hosted(self) -> Hosted<H> {
        self.hosted
    }
}

fn read<R: FromValue>(name: &str, value: &Value) -> Result<R, Error> {
    R::from_value(value, Span::synthetic()).map_err(|e| Error::Returned {
        name: name.to_owned(),
        message: e.short_message(),
    })
}

#[doc(hidden)]
pub mod __private {
    use super::{EvalError, IntoValue, Span, Value};

    #[must_use]
    pub fn argument(
        name: &str,
        position: usize,
        label: &str,
        e: &EvalError,
        span: Span,
    ) -> EvalError {
        EvalError::native_fn(
            name.to_owned(),
            format!("argument {position} ({label}): {}", e.short_message()),
            span,
        )
    }

    pub fn fallible<T: IntoValue, E: std::fmt::Display>(
        name: &str,
        result: Result<T, E>,
        span: Span,
    ) -> Result<Value, EvalError> {
        result
            .map(IntoValue::into_value)
            .map_err(|e| EvalError::native_fn(name.to_owned(), e.to_string(), span))
    }
}
