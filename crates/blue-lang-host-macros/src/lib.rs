use proc_macro::TokenStream;
use quote::{format_ident, quote};
use syn::parse::Parser;
use syn::punctuated::Punctuated;
use syn::{
    Attribute, Expr, ExprLit, FnArg, ImplItem, ImplItemFn, ItemImpl, Lit, Meta, Pat, ReturnType,
    Token, Type,
};

#[proc_macro_attribute]
pub fn host(attr: TokenStream, item: TokenStream) -> TokenStream {
    match expand(attr.into(), item.into()) {
        Ok(ts) => ts.into(),
        Err(e) => e.to_compile_error().into(),
    }
}

struct HostArgs {
    prefix: String,
}

fn parse_host_args(attr: proc_macro2::TokenStream) -> syn::Result<HostArgs> {
    let mut prefix = String::new();
    let metas = Punctuated::<Meta, Token![,]>::parse_terminated.parse2(attr)?;
    for meta in metas {
        match &meta {
            Meta::NameValue(nv) if nv.path.is_ident("prefix") => prefix = string_value(&nv.value)?,
            other => {
                return Err(syn::Error::new_spanned(
                    other,
                    "#[host] takes only `prefix = \"...\"`",
                ))
            }
        }
    }
    Ok(HostArgs { prefix })
}

fn string_value(e: &Expr) -> syn::Result<String> {
    match e {
        Expr::Lit(ExprLit {
            lit: Lit::Str(s), ..
        }) => Ok(s.value()),
        other => Err(syn::Error::new_spanned(other, "expected a string literal")),
    }
}

enum Blue {
    Expose { name: Option<String> },
    Skip,
}

fn blue_attr(attrs: &mut Vec<Attribute>) -> syn::Result<Blue> {
    let mut out = Blue::Expose { name: None };
    let mut kept = Vec::with_capacity(attrs.len());
    for attr in attrs.drain(..) {
        if !attr.path().is_ident("blue") {
            kept.push(attr);
            continue;
        }
        attr.parse_nested_meta(|m| {
            if m.path.is_ident("skip") {
                out = Blue::Skip;
                Ok(())
            } else if m.path.is_ident("name") {
                let s: syn::LitStr = m.value()?.parse()?;
                out = Blue::Expose {
                    name: Some(s.value()),
                };
                Ok(())
            } else {
                Err(m.error("#[blue] takes `skip` or `name = \"...\"`"))
            }
        })?;
    }
    *attrs = kept;
    Ok(out)
}

fn doc_of(attrs: &[Attribute]) -> String {
    attrs
        .iter()
        .filter(|a| a.path().is_ident("doc"))
        .filter_map(|a| match &a.meta {
            Meta::NameValue(nv) => string_value(&nv.value).ok(),
            _ => None,
        })
        .map(|line| line.trim().to_owned())
        .collect::<Vec<_>>()
        .join("\n")
        .trim()
        .to_owned()
}

fn is_option(ty: &Type) -> bool {
    match ty {
        Type::Path(p) => p.path.segments.last().is_some_and(|s| s.ident == "Option"),
        _ => false,
    }
}

fn returns_result(ret: &ReturnType) -> bool {
    match ret {
        ReturnType::Default => false,
        ReturnType::Type(_, ty) => match ty.as_ref() {
            Type::Path(p) => p.path.segments.last().is_some_and(|s| s.ident == "Result"),
            _ => false,
        },
    }
}

struct Method {
    ident: syn::Ident,
    blue_name: String,
    params: Vec<(String, Type)>,
    required: usize,
    receiver: bool,
    fallible: bool,
    doc: String,
}

fn method(f: &mut ImplItemFn, prefix: &str) -> syn::Result<Option<Method>> {
    let name = match blue_attr(&mut f.attrs)? {
        Blue::Skip => return Ok(None),
        Blue::Expose { name } => name,
    };
    let sig = &f.sig;
    if sig.asyncness.is_some() || !sig.generics.params.is_empty() {
        return Err(syn::Error::new_spanned(
            sig,
            "a host function is a plain synchronous method; mark this one #[blue(skip)]",
        ));
    }
    let mut receiver = false;
    let mut params = Vec::new();
    for input in &sig.inputs {
        match input {
            FnArg::Receiver(r) => {
                if r.reference.is_none() {
                    return Err(syn::Error::new_spanned(
                        r,
                        "a host function borrows the host: take `&self` or `&mut self`",
                    ));
                }
                receiver = true;
            }
            FnArg::Typed(pt) => {
                let label = match pt.pat.as_ref() {
                    Pat::Ident(i) => i.ident.to_string(),
                    _ => format!("argument {}", params.len() + 1),
                };
                params.push((label, (*pt.ty).clone()));
            }
        }
    }
    let required = params.len()
        - params
            .iter()
            .rev()
            .take_while(|(_, ty)| is_option(ty))
            .count();
    Ok(Some(Method {
        required,
        ident: sig.ident.clone(),
        blue_name: name.unwrap_or_else(|| format!("{prefix}{}", sig.ident)),
        params,
        receiver,
        fallible: returns_result(&sig.output),
        doc: doc_of(&f.attrs),
    }))
}

fn expand(
    attr: proc_macro2::TokenStream,
    item: proc_macro2::TokenStream,
) -> syn::Result<proc_macro2::TokenStream> {
    let args = parse_host_args(attr)?;
    let mut block: ItemImpl = syn::parse2(item)?;
    if block.trait_.is_some() {
        return Err(syn::Error::new_spanned(
            &block.self_ty,
            "#[host] goes on an inherent impl block, not a trait impl",
        ));
    }
    let mut methods = Vec::new();
    for it in &mut block.items {
        if let ImplItem::Fn(f) = it {
            if let Some(m) = method(f, &args.prefix)? {
                methods.push(m);
            }
        }
    }
    let self_ty = &block.self_ty;
    let (impl_generics, _, where_clause) = block.generics.split_for_impl();
    let krate = quote!(::blue_lang_host);

    let surface = methods.iter().map(|m| {
        let name = &m.blue_name;
        let doc = &m.doc;
        let labels = m.params.iter().map(|(l, _)| l);
        let required = m.required;
        quote! {
            #krate::HostFn { name: #name, params: &[#(#labels),*], required: #required, doc: #doc }
        }
    });

    let registrations = methods.iter().map(|m| {
        let name = &m.blue_name;
        let ident = &m.ident;
        let arity = m.params.len();
        let binds = (0..arity).map(|i| format_ident!("a{i}"));
        let required = m.required;
        let converts = m.params.iter().enumerate().map(|(i, (label, ty))| {
            let var = format_ident!("a{i}");
            let position = i + 1;
            if i < required {
                quote! {
                    let #var = <#ty as #krate::FromValue>::from_value(&args[#i], span)
                        .map_err(|e| #krate::__private::argument(#name, #position, #label, &e, span))?;
                }
            } else {
                quote! {
                    let #var = match args.get(#i) {
                        ::core::option::Option::Some(v) => <#ty as #krate::FromValue>::from_value(v, span)
                            .map_err(|e| #krate::__private::argument(#name, #position, #label, &e, span))?,
                        ::core::option::Option::None => ::core::option::Option::None,
                    };
                }
            }
        });
        let arity_expr = if required == arity {
            quote!(#krate::Arity::Exact(#arity))
        } else {
            quote!(#krate::Arity::Range(#required, #arity))
        };
        let call = if m.receiver {
            quote!(host.#ident(#(#binds),*))
        } else {
            quote!(<#self_ty>::#ident(#(#binds),*))
        };
        let finish = if m.fallible {
            quote!(#krate::__private::fallible(#name, #call, span))
        } else {
            quote!(::core::result::Result::Ok(#krate::IntoValue::into_value(#call)))
        };
        quote! {
            interp.register_fn(
                #name,
                #arity_expr,
                |args: &[#krate::Value], host: &mut Self, span: #krate::Span| {
                    #(#converts)*
                    #finish
                },
            );
        }
    });

    Ok(quote! {
        #block

        impl #impl_generics #krate::Host for #self_ty #where_clause {
            const SURFACE: &'static [#krate::HostFn] = &[#(#surface),*];

            fn install(interp: &mut #krate::Interpreter<Self>) {
                #(#registrations)*
            }
        }
    })
}
