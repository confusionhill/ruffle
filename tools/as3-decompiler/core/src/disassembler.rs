use crate::constant_pool_resolver::ConstantPoolResolver;
use swf::avm2::read::Reader;
use swf::avm2::types::{AbcFile, MethodBody, Op};
use swf::extensions::ReadSwfExt;

pub struct Disassembler<'a> {
    resolver: ConstantPoolResolver<'a>,
}

impl<'a> Disassembler<'a> {
    pub fn new(abc: &'a AbcFile) -> Self {
        Self {
            resolver: ConstantPoolResolver::new(abc),
        }
    }

    pub fn disassemble_method_body(&self, body: &MethodBody) -> String {
        let mut out = String::new();
        out.push_str(&format!(
            "// Max Stack: {}, Locals: {}, Scope: {}..{}\n",
            body.max_stack, body.num_locals, body.init_scope_depth, body.max_scope_depth
        ));

        if !body.exceptions.is_empty() {
            out.push_str("// Exception Handlers:\n");
            for (idx, ex) in body.exceptions.iter().enumerate() {
                let var = self.resolver.multiname(ex.variable_name);
                let ty = self.resolver.multiname(ex.type_name);
                out.push_str(&format!(
                    "//   [{}] 0x{:04x}..0x{:04x} -> catch 0x{:04x} (var: {}, type: {})\n",
                    idx, ex.from_offset, ex.to_offset, ex.target_offset, var, ty
                ));
            }
            out.push('\n');
        }

        let mut reader = Reader::new(&body.code);
        let code_len = body.code.len();

        while (reader.as_slice().as_ptr() as usize) < (body.code.as_ptr() as usize + code_len) {
            let current_pos = body.code.len() - reader.as_slice().len();
            match reader.read_op() {
                Ok(op) => {
                    let next_pos = body.code.len() - reader.as_slice().len();
                    let formatted = self.format_op(&op, current_pos as i32, next_pos as i32);
                    out.push_str(&format!("  0x{:04x}  {}\n", current_pos, formatted));
                }
                Err(e) => {
                    out.push_str(&format!("  0x{:04x}  <error reading op: {:?}>\n", current_pos, e));
                    break;
                }
            }
        }

        out
    }

    fn format_op(&self, op: &Op, _start_pos: i32, next_pos: i32) -> String {
        match op {
            Op::Add => "add".to_string(),
            Op::AddI => "addi".to_string(),
            Op::ApplyType { num_types } => format!("applytype {}", num_types),
            Op::AsType { type_name } => format!("astype {}", self.resolver.multiname(*type_name)),
            Op::AsTypeLate => "astypelate".to_string(),
            Op::BitAnd => "bitand".to_string(),
            Op::BitNot => "bitnot".to_string(),
            Op::BitOr => "bitor".to_string(),
            Op::BitXor => "bitxor".to_string(),
            Op::Bkpt => "bkpt".to_string(),
            Op::BkptLine { line_num } => format!("bkptline {}", line_num),
            Op::Call { num_args } => format!("call {}", num_args),
            Op::CallMethod { index, num_args } => format!("callmethod {}, args: {}", index, num_args),
            Op::CallProperty { index, num_args } => {
                format!("callproperty {}, args: {}", self.resolver.multiname(*index), num_args)
            }
            Op::CallPropLex { index, num_args } => {
                format!("callproplex {}, args: {}", self.resolver.multiname(*index), num_args)
            }
            Op::CallPropVoid { index, num_args } => {
                format!("callpropvoid {}, args: {}", self.resolver.multiname(*index), num_args)
            }
            Op::CallStatic { index, num_args } => {
                format!("callstatic method_{}, args: {}", index.0, num_args)
            }
            Op::CallSuper { index, num_args } => {
                format!("callsuper {}, args: {}", self.resolver.multiname(*index), num_args)
            }
            Op::CallSuperVoid { index, num_args } => {
                format!("callsupervoid {}, args: {}", self.resolver.multiname(*index), num_args)
            }
            Op::CheckFilter => "checkfilter".to_string(),
            Op::Coerce { index } => format!("coerce {}", self.resolver.multiname(*index)),
            Op::CoerceA => "coerce_a".to_string(),
            Op::CoerceB => "coerce_b".to_string(),
            Op::CoerceD => "coerce_d".to_string(),
            Op::CoerceI => "coerce_i".to_string(),
            Op::CoerceO => "coerce_o".to_string(),
            Op::CoerceS => "coerce_s".to_string(),
            Op::CoerceU => "coerce_u".to_string(),
            Op::Construct { num_args } => format!("construct args: {}", num_args),
            Op::ConstructProp { index, num_args } => {
                format!("constructprop {}, args: {}", self.resolver.multiname(*index), num_args)
            }
            Op::ConstructSuper { num_args } => format!("constructsuper args: {}", num_args),
            Op::ConvertB => "convert_b".to_string(),
            Op::ConvertD => "convert_d".to_string(),
            Op::ConvertI => "convert_i".to_string(),
            Op::ConvertO => "convert_o".to_string(),
            Op::ConvertS => "convert_s".to_string(),
            Op::ConvertU => "convert_u".to_string(),
            Op::Debug { is_local_register, register_name, register } => {
                format!("debug reg: {}, is_local: {}, name: {}", register, is_local_register, self.resolver.string(*register_name))
            }
            Op::DebugFile { file_name } => format!("debugfile \"{}\"", self.resolver.string(*file_name)),
            Op::DebugLine { line_num } => format!("debugline {}", line_num),
            Op::DecLocal { index } => format!("declocal r{}", index),
            Op::DecLocalI { index } => format!("declocal_i r{}", index),
            Op::Decrement => "decrement".to_string(),
            Op::DecrementI => "decrement_i".to_string(),
            Op::DeleteProperty { index } => format!("deleteproperty {}", self.resolver.multiname(*index)),
            Op::Divide => "divide".to_string(),
            Op::Dup => "dup".to_string(),
            Op::Dxns { index } => format!("dxns \"{}\"", self.resolver.string(*index)),
            Op::DxnsLate => "dxnslate".to_string(),
            Op::Equals => "equals".to_string(),
            Op::EscXAttr => "esc_xattr".to_string(),
            Op::EscXElem => "esc_xelem".to_string(),
            Op::FindDef { index } => format!("finddef {}", self.resolver.multiname(*index)),
            Op::FindProperty { index } => format!("findproperty {}", self.resolver.multiname(*index)),
            Op::FindPropStrict { index } => format!("findpropstrict {}", self.resolver.multiname(*index)),
            Op::GetDescendants { index } => format!("getdescendants {}", self.resolver.multiname(*index)),
            Op::GetGlobalScope => "getglobalscope".to_string(),
            Op::GetGlobalSlot { index } => format!("getglobalslot {}", index),
            Op::GetLex { index } => format!("getlex {}", self.resolver.multiname(*index)),
            Op::GetLocal { index } => format!("getlocal r{}", index),
            Op::GetOuterScope { index } => format!("getouterscope {}", index),
            Op::GetProperty { index } => format!("getproperty {}", self.resolver.multiname(*index)),
            Op::GetScopeObject { index } => format!("getscopeobject {}", index),
            Op::GetSlot { index } => format!("getslot {}", index),
            Op::GetSuper { index } => format!("getsuper {}", self.resolver.multiname(*index)),
            Op::GreaterEquals => "greaterequals".to_string(),
            Op::GreaterThan => "greaterthan".to_string(),
            Op::HasNext => "hasnext".to_string(),
            Op::HasNext2 { object_register, index_register } => {
                format!("hasnext2 obj: r{}, idx: r{}", object_register, index_register)
            }
            Op::IfEq { offset } => format!("ifeq 0x{:04x}", next_pos + offset),
            Op::IfFalse { offset } => format!("iffalse 0x{:04x}", next_pos + offset),
            Op::IfGe { offset } => format!("ifge 0x{:04x}", next_pos + offset),
            Op::IfGt { offset } => format!("ifgt 0x{:04x}", next_pos + offset),
            Op::IfLe { offset } => format!("ifle 0x{:04x}", next_pos + offset),
            Op::IfLt { offset } => format!("iflt 0x{:04x}", next_pos + offset),
            Op::IfNe { offset } => format!("ifne 0x{:04x}", next_pos + offset),
            Op::IfNge { offset } => format!("ifnge 0x{:04x}", next_pos + offset),
            Op::IfNgt { offset } => format!("ifngt 0x{:04x}", next_pos + offset),
            Op::IfNle { offset } => format!("ifnle 0x{:04x}", next_pos + offset),
            Op::IfNlt { offset } => format!("ifnlt 0x{:04x}", next_pos + offset),
            Op::IfStrictEq { offset } => format!("ifstricteq 0x{:04x}", next_pos + offset),
            Op::IfStrictNe { offset } => format!("ifstrictne 0x{:04x}", next_pos + offset),
            Op::IfTrue { offset } => format!("iftrue 0x{:04x}", next_pos + offset),
            Op::In => "in".to_string(),
            Op::IncLocal { index } => format!("inclocal r{}", index),
            Op::IncLocalI { index } => format!("inclocal_i r{}", index),
            Op::Increment => "increment".to_string(),
            Op::IncrementI => "increment_i".to_string(),
            Op::InitProperty { index } => format!("initproperty {}", self.resolver.multiname(*index)),
            Op::InstanceOf => "instanceof".to_string(),
            Op::IsType { index } => format!("istype {}", self.resolver.multiname(*index)),
            Op::IsTypeLate => "istypelate".to_string(),
            Op::Jump { offset } => format!("jump 0x{:04x}", next_pos + offset),
            Op::Kill { index } => format!("kill r{}", index),
            Op::Label => "label".to_string(),
            Op::LessEquals => "lessequals".to_string(),
            Op::LessThan => "lessthan".to_string(),
            Op::Lf32 => "lf32".to_string(),
            Op::Lf64 => "lf64".to_string(),
            Op::Li16 => "li16".to_string(),
            Op::Li32 => "li32".to_string(),
            Op::Li8 => "li8".to_string(),
            Op::LookupSwitch(switch) => {
                let targets: Vec<String> = switch
                    .case_offsets
                    .iter()
                    .map(|o| format!("0x{:04x}", next_pos + o))
                    .collect();
                format!("lookupswitch default: 0x{:04x}, cases: [{}]", next_pos + switch.default_offset, targets.join(", "))
            }
            Op::LShift => "lshift".to_string(),
            Op::Modulo => "modulo".to_string(),
            Op::Multiply => "multiply".to_string(),
            Op::MultiplyI => "multiply_i".to_string(),
            Op::Negate => "negate".to_string(),
            Op::NegateI => "negate_i".to_string(),
            Op::NewActivation => "newactivation".to_string(),
            Op::NewArray { num_args } => format!("newarray len: {}", num_args),
            Op::NewCatch { index } => format!("newcatch exception_{}", index.0),
            Op::NewClass { index } => format!("newclass class_{}", index.0),
            Op::NewFunction { index } => format!("newfunction method_{}", index.0),
            Op::NewObject { num_args } => format!("newobject props: {}", num_args),
            Op::NextName => "nextname".to_string(),
            Op::NextValue => "nextvalue".to_string(),
            Op::Nop => "nop".to_string(),
            Op::Not => "not".to_string(),
            Op::Pop => "pop".to_string(),
            Op::PopScope => "popscope".to_string(),
            Op::PushByte { value } => format!("pushbyte {}", value),
            Op::PushDouble { value } => {
                let idx = value.0 as usize;
                let val = if idx > 0 && idx <= self.resolver.pool.doubles.len() {
                    self.resolver.pool.doubles[idx - 1]
                } else {
                    0.0
                };
                format!("pushdouble {}", val)
            }
            Op::PushFalse => "pushfalse".to_string(),
            Op::PushInt { value } => {
                let idx = value.0 as usize;
                let val = if idx > 0 && idx <= self.resolver.pool.ints.len() {
                    self.resolver.pool.ints[idx - 1]
                } else {
                    0
                };
                format!("pushint {}", val)
            }
            Op::PushNamespace { value } => {
                let (_, ns) = self.resolver.namespace(*value);
                format!("pushnamespace \"{}\"", ns)
            }
            Op::PushNaN => "pushnan".to_string(),
            Op::PushNull => "pushnull".to_string(),
            Op::PushScope => "pushscope".to_string(),
            Op::PushShort { value } => format!("pushshort {}", value),
            Op::PushString { value } => format!("pushstring \"{}\"", self.resolver.string(*value).escape_debug()),
            Op::PushTrue => "pushtrue".to_string(),
            Op::PushUint { value } => {
                let idx = value.0 as usize;
                let val = if idx > 0 && idx <= self.resolver.pool.uints.len() {
                    self.resolver.pool.uints[idx - 1]
                } else {
                    0
                };
                format!("pushuint {}", val)
            }
            Op::PushUndefined => "pushundefined".to_string(),
            Op::PushWith => "pushwith".to_string(),
            Op::ReturnValue => "returnvalue".to_string(),
            Op::ReturnVoid => "returnvoid".to_string(),
            Op::RShift => "rshift".to_string(),
            Op::SetGlobalSlot { index } => format!("setglobalslot {}", index),
            Op::SetLocal { index } => format!("setlocal r{}", index),
            Op::SetProperty { index } => format!("setproperty {}", self.resolver.multiname(*index)),
            Op::SetSlot { index } => format!("setslot {}", index),
            Op::SetSuper { index } => format!("setsuper {}", self.resolver.multiname(*index)),
            Op::Sf32 => "sf32".to_string(),
            Op::Sf64 => "sf64".to_string(),
            Op::Si16 => "si16".to_string(),
            Op::Si32 => "si32".to_string(),
            Op::Si8 => "si8".to_string(),
            Op::StrictEquals => "strictequals".to_string(),
            Op::Subtract => "subtract".to_string(),
            Op::SubtractI => "subtract_i".to_string(),
            Op::Swap => "swap".to_string(),
            Op::Sxi1 => "sxi1".to_string(),
            Op::Sxi16 => "sxi16".to_string(),
            Op::Sxi8 => "sxi8".to_string(),
            Op::Throw => "throw".to_string(),
            Op::TypeOf => "typeof".to_string(),
            Op::Timestamp => "timestamp".to_string(),
            Op::URShift => "urshift".to_string(),
        }
    }
}
