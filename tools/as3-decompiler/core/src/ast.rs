use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub enum Expr {
    Null,
    Undefined,
    This,
    Super,
    Bool(bool),
    Int(i32),
    Uint(u32),
    Number(f64),
    String(String),
    Ident(String),
    Unary {
        op: String,
        expr: Box<Expr>,
    },
    Binary {
        op: String,
        lhs: Box<Expr>,
        rhs: Box<Expr>,
    },
    Assign {
        lhs: Box<Expr>,
        rhs: Box<Expr>,
    },
    Member {
        target: Box<Expr>,
        member: String,
    },
    Index {
        target: Box<Expr>,
        index: Box<Expr>,
    },
    Call {
        callee: Box<Expr>,
        args: Vec<Expr>,
    },
    Construct {
        callee: Box<Expr>,
        args: Vec<Expr>,
    },
    ArrayLiteral(Vec<Expr>),
    ObjectLiteral(Vec<(String, Expr)>),
    AsType {
        expr: Box<Expr>,
        type_name: String,
    },
    IsType {
        expr: Box<Expr>,
        type_name: String,
    },
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub enum Statement {
    Expr(Expr),
    VarDecl {
        name: String,
        type_name: Option<String>,
        init: Option<Expr>,
    },
    If {
        cond: Expr,
        then_body: Vec<Statement>,
        else_body: Option<Vec<Statement>>,
    },
    While {
        cond: Expr,
        body: Vec<Statement>,
    },
    Return(Option<Expr>),
    Throw(Expr),
    Break,
    Continue,
    Comment(String),
    Raw(String),
}
