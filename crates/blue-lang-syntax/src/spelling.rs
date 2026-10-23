use crate::lex::Span;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum Spelling {
    LogicalSymbol,
    Unless,
    ElseIf,
    CallForm,
    KeywordRocket,
    ParameterList,
    OperatorSpelling,
    TrailingComma,
    NegatedComparison,
    ElseNil,
    TryCatch,
    Apply,
    MapPun,
    NilTest,
}

impl Spelling {
    pub const ALL: &'static [Spelling] = &[
        Spelling::LogicalSymbol,
        Spelling::Unless,
        Spelling::ElseIf,
        Spelling::CallForm,
        Spelling::KeywordRocket,
        Spelling::ParameterList,
        Spelling::OperatorSpelling,
        Spelling::TrailingComma,
        Spelling::NegatedComparison,
        Spelling::ElseNil,
        Spelling::TryCatch,
        Spelling::Apply,
        Spelling::MapPun,
        Spelling::NilTest,
    ];
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Note {
    pub spelling: Spelling,
    pub span: Span,
    pub written: String,
    pub canonical: String,
}
