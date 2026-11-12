use crate::ast::{Expr, Statement};
use crate::constant_pool_resolver::ConstantPoolResolver;
use swf::avm2::read::Reader;
use swf::avm2::types::{AbcFile, Method, MethodBody, Op};
use swf::extensions::ReadSwfExt;

pub struct MethodDecompiler<'a> {
    abc: &'a AbcFile,
    resolver: ConstantPoolResolver<'a>,
    is_instance_method: bool,
    param_names: Vec<String>,
}

#[derive(Clone, Debug)]
struct DecodedInstruction {
    offset: usize,
    next_offset: usize,
    op: Op,
}

impl<'a> MethodDecompiler<'a> {
    pub fn new(abc: &'a AbcFile, method: &Method, is_instance_method: bool) -> Self {
        let resolver = ConstantPoolResolver::new(abc);
        let mut param_names = Vec::new();
        for (i, p) in method.params.iter().enumerate() {
            if let Some(idx) = p.name {
                let name = resolver.string(idx);
                if !name.is_empty() && name != "*" {
                    param_names.push(name);
                    continue;
                }
            }
            param_names.push(format!("param{}", i + 1));
        }

        Self {
            abc,
            resolver,
            is_instance_method,
            param_names,
        }
    }

    pub fn decompile_body(&self, body: &MethodBody) -> Vec<Statement> {
        let instructions = self.decode_instructions(&body.code);
        if instructions.is_empty() {
            return Vec::new();
        }

        self.decompile_range(&instructions, 0, instructions.len(), body.num_locals)
    }

    fn decode_instructions(&self, code: &[u8]) -> Vec<DecodedInstruction> {
        let mut instructions = Vec::new();
        let mut reader = Reader::new(code);
        let code_len = code.len();

        while (reader.as_slice().as_ptr() as usize) < (code.as_ptr() as usize + code_len) {
            let offset = code.len() - reader.as_slice().len();
            match reader.read_op() {
                Ok(op) => {
                    let next_offset = code.len() - reader.as_slice().len();
                    instructions.push(DecodedInstruction {
                        offset,
                        next_offset,
                        op,
                    });
                }
                Err(_) => break,
            }
        }

        instructions
    }

    fn local_name(&self, index: u32, _num_locals: u32) -> String {
        if index == 0 && self.is_instance_method {
            return "this".to_string();
        }
        let param_idx = if self.is_instance_method { index - 1 } else { index } as usize;
        if param_idx < self.param_names.len() {
            return self.param_names[param_idx].clone();
        }
        format!("_loc{}_", index)
    }

    fn decompile_range(
        &self,
        instructions: &[DecodedInstruction],
        start: usize,
        end: usize,
        num_locals: u32,
    ) -> Vec<Statement> {
        let mut statements = Vec::new();
        let mut stack: Vec<Expr> = Vec::new();
        let mut declared_locals: std::collections::HashSet<u32> = std::collections::HashSet::new();

        // Mark parameters and 'this' as declared
        let param_count = if self.is_instance_method {
            self.param_names.len() as u32 + 1
        } else {
            self.param_names.len() as u32
        };
        for i in 0..param_count {
            declared_locals.insert(i);
        }

        let mut i = start;
        while i < end {
            let inst = &instructions[i];

            match &inst.op {
                // Literals
                Op::PushNull => stack.push(Expr::Null),
                Op::PushUndefined => stack.push(Expr::Undefined),
                Op::PushTrue => stack.push(Expr::Bool(true)),
                Op::PushFalse => stack.push(Expr::Bool(false)),
                Op::PushNaN => stack.push(Expr::Number(f64::NAN)),
                Op::PushByte { value } => stack.push(Expr::Int(*value as i32)),
                Op::PushShort { value } => stack.push(Expr::Int(*value as i32)),
                Op::PushInt { value } => {
                    let idx = value.0 as usize;
                    let val = if idx > 0 && idx <= self.abc.constant_pool.ints.len() {
                        self.abc.constant_pool.ints[idx - 1]
                    } else {
                        0
                    };
                    stack.push(Expr::Int(val));
                }
                Op::PushUint { value } => {
                    let idx = value.0 as usize;
                    let val = if idx > 0 && idx <= self.abc.constant_pool.uints.len() {
                        self.abc.constant_pool.uints[idx - 1]
                    } else {
                        0
                    };
                    stack.push(Expr::Uint(val));
                }
                Op::PushDouble { value } => {
                    let idx = value.0 as usize;
                    let val = if idx > 0 && idx <= self.abc.constant_pool.doubles.len() {
                        self.abc.constant_pool.doubles[idx - 1]
                    } else {
                        0.0
                    };
                    stack.push(Expr::Number(val));
                }
                Op::PushString { value } => {
                    let s = self.resolver.string(*value);
                    stack.push(Expr::String(s));
                }

                // Locals & Scope
                Op::GetLocal { index } => {
                    if *index == 0 && self.is_instance_method {
                        stack.push(Expr::This);
                    } else {
                        stack.push(Expr::Ident(self.local_name(*index, num_locals)));
                    }
                }
                Op::SetLocal { index } => {
                    let val = stack.pop().unwrap_or(Expr::Undefined);
                    let name = self.local_name(*index, num_locals);
                    if !declared_locals.contains(index) {
                        declared_locals.insert(*index);
                        statements.push(Statement::VarDecl {
                            name,
                            type_name: None,
                            init: Some(val),
                        });
                    } else {
                        statements.push(Statement::Expr(Expr::Assign {
                            lhs: Box::new(Expr::Ident(name)),
                            rhs: Box::new(val),
                        }));
                    }
                }
                Op::IncLocal { index } | Op::IncLocalI { index } => {
                    let name = self.local_name(*index, num_locals);
                    statements.push(Statement::Expr(Expr::Unary {
                        op: "++".to_string(),
                        expr: Box::new(Expr::Ident(name)),
                    }));
                }
                Op::DecLocal { index } | Op::DecLocalI { index } => {
                    let name = self.local_name(*index, num_locals);
                    statements.push(Statement::Expr(Expr::Unary {
                        op: "--".to_string(),
                        expr: Box::new(Expr::Ident(name)),
                    }));
                }

                // Properties & Identifiers
                Op::GetLex { index } => {
                    let name = self.resolver.multiname(*index);
                    stack.push(Expr::Ident(name));
                }
                Op::FindPropStrict { index } | Op::FindProperty { index } => {
                    let name = self.resolver.property_name(*index);
                    stack.push(Expr::Ident(name));
                }
                Op::GetProperty { index } => {
                    let prop = self.resolver.property_name(*index);
                    let obj = stack.pop().unwrap_or(Expr::This);
                    if matches!(obj, Expr::This) {
                        stack.push(Expr::Member {
                            target: Box::new(Expr::This),
                            member: prop,
                        });
                    } else {
                        stack.push(Expr::Member {
                            target: Box::new(obj),
                            member: prop,
                        });
                    }
                }
                Op::SetProperty { index } | Op::InitProperty { index } => {
                    let val = stack.pop().unwrap_or(Expr::Undefined);
                    let obj = stack.pop().unwrap_or(Expr::This);
                    let prop = self.resolver.property_name(*index);
                    statements.push(Statement::Expr(Expr::Assign {
                        lhs: Box::new(Expr::Member {
                            target: Box::new(obj),
                            member: prop,
                        }),
                        rhs: Box::new(val),
                    }));
                }

                // Method Calls
                Op::CallProperty { index, num_args } => {
                    let mut args = Vec::new();
                    for _ in 0..*num_args {
                        args.push(stack.pop().unwrap_or(Expr::Undefined));
                    }
                    args.reverse();
                    let obj = stack.pop().unwrap_or(Expr::This);
                    let method_name = self.resolver.property_name(*index);
                    let callee = match &obj {
                        Expr::Ident(name) if name == &method_name => Expr::Ident(method_name),
                        _ => Expr::Member {
                            target: Box::new(obj),
                            member: method_name,
                        },
                    };
                    stack.push(Expr::Call {
                        callee: Box::new(callee),
                        args,
                    });
                }
                Op::CallPropVoid { index, num_args } => {
                    let mut args = Vec::new();
                    for _ in 0..*num_args {
                        args.push(stack.pop().unwrap_or(Expr::Undefined));
                    }
                    args.reverse();
                    let obj = stack.pop().unwrap_or(Expr::This);
                    let method_name = self.resolver.property_name(*index);
                    let callee = match &obj {
                        Expr::Ident(name) if name == &method_name => Expr::Ident(method_name),
                        _ => Expr::Member {
                            target: Box::new(obj),
                            member: method_name,
                        },
                    };
                    statements.push(Statement::Expr(Expr::Call {
                        callee: Box::new(callee),
                        args,
                    }));
                }
                Op::ConstructSuper { num_args } => {
                    let mut args = Vec::new();
                    for _ in 0..*num_args {
                        args.push(stack.pop().unwrap_or(Expr::Undefined));
                    }
                    args.reverse();
                    let _this = stack.pop(); // pop this receiver
                    statements.push(Statement::Expr(Expr::Call {
                        callee: Box::new(Expr::Super),
                        args,
                    }));
                }
                Op::ConstructProp { index, num_args } => {
                    let mut args = Vec::new();
                    for _ in 0..*num_args {
                        args.push(stack.pop().unwrap_or(Expr::Undefined));
                    }
                    args.reverse();
                    let _scope = stack.pop();
                    let class_name = self.resolver.multiname(*index);
                    stack.push(Expr::Construct {
                        callee: Box::new(Expr::Ident(class_name)),
                        args,
                    });
                }
                Op::CallSuper { index, num_args } => {
                    let mut args = Vec::new();
                    for _ in 0..*num_args {
                        args.push(stack.pop().unwrap_or(Expr::Undefined));
                    }
                    args.reverse();
                    let _receiver = stack.pop();
                    let method_name = self.resolver.multiname(*index);
                    let callee = Expr::Member {
                        target: Box::new(Expr::Super),
                        member: method_name,
                    };
                    stack.push(Expr::Call {
                        callee: Box::new(callee),
                        args,
                    });
                }
                Op::CallSuperVoid { index, num_args } => {
                    let mut args = Vec::new();
                    for _ in 0..*num_args {
                        args.push(stack.pop().unwrap_or(Expr::Undefined));
                    }
                    args.reverse();
                    let _receiver = stack.pop();
                    let method_name = self.resolver.multiname(*index);
                    let callee = Expr::Member {
                        target: Box::new(Expr::Super),
                        member: method_name,
                    };
                    statements.push(Statement::Expr(Expr::Call {
                        callee: Box::new(callee),
                        args,
                    }));
                }

                // Arithmetic & Binary Operations
                Op::Add | Op::AddI => {
                    let rhs = stack.pop().unwrap_or(Expr::Int(0));
                    let lhs = stack.pop().unwrap_or(Expr::Int(0));
                    stack.push(Expr::Binary {
                        op: "+".to_string(),
                        lhs: Box::new(lhs),
                        rhs: Box::new(rhs),
                    });
                }
                Op::Subtract | Op::SubtractI => {
                    let rhs = stack.pop().unwrap_or(Expr::Int(0));
                    let lhs = stack.pop().unwrap_or(Expr::Int(0));
                    stack.push(Expr::Binary {
                        op: "-".to_string(),
                        lhs: Box::new(lhs),
                        rhs: Box::new(rhs),
                    });
                }
                Op::Multiply | Op::MultiplyI => {
                    let rhs = stack.pop().unwrap_or(Expr::Int(1));
                    let lhs = stack.pop().unwrap_or(Expr::Int(1));
                    stack.push(Expr::Binary {
                        op: "*".to_string(),
                        lhs: Box::new(lhs),
                        rhs: Box::new(rhs),
                    });
                }
                Op::Divide => {
                    let rhs = stack.pop().unwrap_or(Expr::Int(1));
                    let lhs = stack.pop().unwrap_or(Expr::Int(1));
                    stack.push(Expr::Binary {
                        op: "/".to_string(),
                        lhs: Box::new(lhs),
                        rhs: Box::new(rhs),
                    });
                }
                Op::Modulo => {
                    let rhs = stack.pop().unwrap_or(Expr::Int(1));
                    let lhs = stack.pop().unwrap_or(Expr::Int(1));
                    stack.push(Expr::Binary {
                        op: "%".to_string(),
                        lhs: Box::new(lhs),
                        rhs: Box::new(rhs),
                    });
                }
                Op::BitAnd => {
                    let rhs = stack.pop().unwrap_or(Expr::Int(0));
                    let lhs = stack.pop().unwrap_or(Expr::Int(0));
                    stack.push(Expr::Binary {
                        op: "&".to_string(),
                        lhs: Box::new(lhs),
                        rhs: Box::new(rhs),
                    });
                }
                Op::BitOr => {
                    let rhs = stack.pop().unwrap_or(Expr::Int(0));
                    let lhs = stack.pop().unwrap_or(Expr::Int(0));
                    stack.push(Expr::Binary {
                        op: "|".to_string(),
                        lhs: Box::new(lhs),
                        rhs: Box::new(rhs),
                    });
                }
                Op::BitXor => {
                    let rhs = stack.pop().unwrap_or(Expr::Int(0));
                    let lhs = stack.pop().unwrap_or(Expr::Int(0));
                    stack.push(Expr::Binary {
                        op: "^".to_string(),
                        lhs: Box::new(lhs),
                        rhs: Box::new(rhs),
                    });
                }
                Op::LShift => {
                    let rhs = stack.pop().unwrap_or(Expr::Int(0));
                    let lhs = stack.pop().unwrap_or(Expr::Int(0));
                    stack.push(Expr::Binary {
                        op: "<<".to_string(),
                        lhs: Box::new(lhs),
                        rhs: Box::new(rhs),
                    });
                }
                Op::RShift => {
                    let rhs = stack.pop().unwrap_or(Expr::Int(0));
                    let lhs = stack.pop().unwrap_or(Expr::Int(0));
                    stack.push(Expr::Binary {
                        op: ">>".to_string(),
                        lhs: Box::new(lhs),
                        rhs: Box::new(rhs),
                    });
                }
                Op::URShift => {
                    let rhs = stack.pop().unwrap_or(Expr::Int(0));
                    let lhs = stack.pop().unwrap_or(Expr::Int(0));
                    stack.push(Expr::Binary {
                        op: ">>>".to_string(),
                        lhs: Box::new(lhs),
                        rhs: Box::new(rhs),
                    });
                }

                // Comparison & Logic
                Op::Equals => {
                    let rhs = stack.pop().unwrap_or(Expr::Null);
                    let lhs = stack.pop().unwrap_or(Expr::Null);
                    stack.push(Expr::Binary {
                        op: "==".to_string(),
                        lhs: Box::new(lhs),
                        rhs: Box::new(rhs),
                    });
                }
                Op::StrictEquals => {
                    let rhs = stack.pop().unwrap_or(Expr::Null);
                    let lhs = stack.pop().unwrap_or(Expr::Null);
                    stack.push(Expr::Binary {
                        op: "===".to_string(),
                        lhs: Box::new(lhs),
                        rhs: Box::new(rhs),
                    });
                }
                Op::LessThan => {
                    let rhs = stack.pop().unwrap_or(Expr::Int(0));
                    let lhs = stack.pop().unwrap_or(Expr::Int(0));
                    stack.push(Expr::Binary {
                        op: "<".to_string(),
                        lhs: Box::new(lhs),
                        rhs: Box::new(rhs),
                    });
                }
                Op::LessEquals => {
                    let rhs = stack.pop().unwrap_or(Expr::Int(0));
                    let lhs = stack.pop().unwrap_or(Expr::Int(0));
                    stack.push(Expr::Binary {
                        op: "<=".to_string(),
                        lhs: Box::new(lhs),
                        rhs: Box::new(rhs),
                    });
                }
                Op::GreaterThan => {
                    let rhs = stack.pop().unwrap_or(Expr::Int(0));
                    let lhs = stack.pop().unwrap_or(Expr::Int(0));
                    stack.push(Expr::Binary {
                        op: ">".to_string(),
                        lhs: Box::new(lhs),
                        rhs: Box::new(rhs),
                    });
                }
                Op::GreaterEquals => {
                    let rhs = stack.pop().unwrap_or(Expr::Int(0));
                    let lhs = stack.pop().unwrap_or(Expr::Int(0));
                    stack.push(Expr::Binary {
                        op: ">=".to_string(),
                        lhs: Box::new(lhs),
                        rhs: Box::new(rhs),
                    });
                }
                Op::Not => {
                    let expr = stack.pop().unwrap_or(Expr::Bool(false));
                    stack.push(Expr::Unary {
                        op: "!".to_string(),
                        expr: Box::new(expr),
                    });
                }
                Op::Negate | Op::NegateI => {
                    let expr = stack.pop().unwrap_or(Expr::Int(0));
                    stack.push(Expr::Unary {
                        op: "-".to_string(),
                        expr: Box::new(expr),
                    });
                }
                Op::BitNot => {
                    let expr = stack.pop().unwrap_or(Expr::Int(0));
                    stack.push(Expr::Unary {
                        op: "~".to_string(),
                        expr: Box::new(expr),
                    });
                }

                // Types
                Op::AsType { type_name } => {
                    let expr = stack.pop().unwrap_or(Expr::Null);
                    let ty = self.resolver.multiname(*type_name);
                    stack.push(Expr::AsType {
                        expr: Box::new(expr),
                        type_name: ty,
                    });
                }
                Op::IsType { index } => {
                    let expr = stack.pop().unwrap_or(Expr::Null);
                    let ty = self.resolver.multiname(*index);
                    stack.push(Expr::IsType {
                        expr: Box::new(expr),
                        type_name: ty,
                    });
                }
                Op::TypeOf => {
                    let expr = stack.pop().unwrap_or(Expr::Null);
                    stack.push(Expr::Unary {
                        op: "typeof ".to_string(),
                        expr: Box::new(expr),
                    });
                }

                // Arrays & Objects
                Op::NewArray { num_args } => {
                    let mut items = Vec::new();
                    for _ in 0..*num_args {
                        items.push(stack.pop().unwrap_or(Expr::Null));
                    }
                    items.reverse();
                    stack.push(Expr::ArrayLiteral(items));
                }
                Op::NewObject { num_args } => {
                    let mut props = Vec::new();
                    for _ in 0..*num_args {
                        let val = stack.pop().unwrap_or(Expr::Null);
                        let key_expr = stack.pop().unwrap_or(Expr::String("".into()));
                        let key_str = match key_expr {
                            Expr::String(s) => s,
                            _ => format!("{:?}", key_expr),
                        };
                        props.push((key_str, val));
                    }
                    props.reverse();
                    stack.push(Expr::ObjectLiteral(props));
                }

                // Returns & Flow
                Op::ReturnValue => {
                    let val = stack.pop().unwrap_or(Expr::Undefined);
                    statements.push(Statement::Return(Some(val)));
                }
                Op::ReturnVoid => {
                    statements.push(Statement::Return(None));
                }
                Op::Throw => {
                    let val = stack.pop().unwrap_or(Expr::Null);
                    statements.push(Statement::Throw(val));
                }

                // Branching / Jumps
                Op::IfFalse { offset } => {
                    let cond = stack.pop().unwrap_or(Expr::Bool(true));
                    let target_offset = (inst.next_offset as i32 + offset) as usize;
                    if *offset > 0 {
                        // Forward if statement
                        let target_idx = instructions
                            .iter()
                            .position(|instr| instr.offset >= target_offset)
                            .unwrap_or(end);
                        let then_stmts = self.decompile_range(instructions, i + 1, target_idx, num_locals);
                        statements.push(Statement::If {
                            cond,
                            then_body: then_stmts,
                            else_body: None,
                        });
                        i = target_idx.saturating_sub(1);
                    } else {
                        statements.push(Statement::Raw(format!("if (!({:?})) goto 0x{:04x};", cond, target_offset)));
                    }
                }
                Op::IfTrue { offset } => {
                    let cond = stack.pop().unwrap_or(Expr::Bool(false));
                    let target_offset = (inst.next_offset as i32 + offset) as usize;
                    if *offset > 0 {
                        let target_idx = instructions
                            .iter()
                            .position(|instr| instr.offset >= target_offset)
                            .unwrap_or(end);
                        let then_stmts = self.decompile_range(instructions, i + 1, target_idx, num_locals);
                        statements.push(Statement::If {
                            cond: Expr::Unary {
                                op: "!".to_string(),
                                expr: Box::new(cond),
                            },
                            then_body: then_stmts,
                            else_body: None,
                        });
                        i = target_idx.saturating_sub(1);
                    } else {
                        statements.push(Statement::Raw(format!("if ({:?}) goto 0x{:04x};", cond, target_offset)));
                    }
                }
                Op::Jump { offset } => {
                    let _target_offset = (inst.next_offset as i32 + offset) as usize;
                    if *offset < 0 {
                        statements.push(Statement::Continue);
                    } else {
                        statements.push(Statement::Break);
                    }
                }

                // Pop / Coerce
                Op::Pop => {
                    if let Some(expr) = stack.pop() {
                        if !matches!(expr, Expr::This | Expr::Null | Expr::Undefined) {
                            statements.push(Statement::Expr(expr));
                        }
                    }
                }
                Op::Coerce { .. } | Op::CoerceA | Op::CoerceS | Op::CoerceI | Op::CoerceU | Op::CoerceD => {
                    // Coercions are mostly implicit in AS3
                }
                Op::Dup => {
                    if let Some(top) = stack.last().cloned() {
                        stack.push(top);
                    }
                }

                // Ignore metadata/debug ops
                Op::Debug { .. } | Op::DebugFile { .. } | Op::DebugLine { .. } | Op::Label | Op::Nop => {}

                _ => {}
            }

            i += 1;
        }

        // Flush any remaining expression left on the stack as expression statements
        while let Some(expr) = stack.pop() {
            if !matches!(expr, Expr::This | Expr::Null | Expr::Undefined) {
                statements.push(Statement::Expr(expr));
            }
        }

        statements
    }
}
