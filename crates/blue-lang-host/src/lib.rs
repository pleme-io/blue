pub use blue_lang_host_macros::host;
pub use blue_lang_runtime::hosted::{CallError, FramedError, Hosted};
pub use blue_lang_runtime::uses::{Entry, Loader, NoLoader};
pub use blue_lang_runtime::RunError;
pub use tatara_lisp_eval::vm::Budget;
pub use tatara_lisp_eval::{Arity, EvalError, FromValue, Interpreter, IntoValue, Span, Value};

#[cfg(feature = "packages")]
pub use blue_lang_pkg::embedded::Standard;

pub trait Host: Sized + 'static {
    const SURFACE: &'static [HostFn];

    fn install(interp: &mut Interpreter<Self>);
}

impl Host for () {
    const SURFACE: &'static [HostFn] = &[];

    fn install(_: &mut Interpreter<Self>) {}
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct HostFn {
    pub name: &'static str,
    pub params: &'static [&'static str],
    pub doc: &'static str,
}

#[derive(Debug, thiserror::Error)]
pub enum Error {
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
    #[cfg(feature = "packages")]
    pub fn load(entry: Entry<'_>, host: &mut H) -> Result<Self, Error> {
        Self::load_with(entry, &Standard, host)
    }

    pub fn load_with(entry: Entry<'_>, loader: &dyn Loader, host: &mut H) -> Result<Self, Error> {
        let hosted = blue_lang_runtime::hosted::load_hosted(entry, loader, host, H::install)?;
        Ok(Self { hosted })
    }

    pub fn load_in_frame(
        entry: Entry<'_>,
        loader: &dyn Loader,
        host: &mut H,
        permits: &dyn Fn(&str) -> bool,
        budget: Budget,
    ) -> Result<Self, Error> {
        let hosted = blue_lang_runtime::hosted::load_hosted_in_frame(
            entry,
            loader,
            host,
            H::install,
            permits,
            budget,
        )?;
        Ok(Self { hosted })
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
