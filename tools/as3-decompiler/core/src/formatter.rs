use crate::ast::{Expr, Statement};
use crate::model::{ClassInfo, MethodInfo, ParamInfo, TraitInfo, TraitKindInfo};

pub struct Formatter;

impl Formatter {
    pub fn format_class(class: &ClassInfo) -> String {
        let mut out = String::new();

        // Package header
        if class.package_name.is_empty() {
            out.push_str("package\n{\n");
        } else {
            out.push_str(&format!("package {}\n{{\n", class.package_name));
        }

        // Class declaration
        let mut class_line = String::from("    ");
        if class.is_final {
            class_line.push_str("final ");
        }
        if !class.is_sealed && !class.is_interface {
            class_line.push_str("dynamic ");
        }
        if class.is_interface {
            class_line.push_str(&format!("public interface {}", class.name));
        } else {
            class_line.push_str(&format!("public class {}", class.name));
        }

        if let Some(super_name) = &class.super_name {
            if super_name != "Object" && !super_name.is_empty() {
                class_line.push_str(&format!(" extends {}", super_name));
            }
        }

        if !class.interfaces.is_empty() {
            let kw = if class.is_interface { "extends" } else { "implements" };
            class_line.push_str(&format!(" {} {}", kw, class.interfaces.join(", ")));
        }

        out.push_str(&class_line);
        out.push_str("\n    {\n");

        // Static Constants and Variables
        for trait_info in &class.static_traits {
            Self::format_trait(&mut out, trait_info, true);
        }

        // Instance Variables / Constants
        for trait_info in &class.instance_traits {
            if matches!(trait_info.kind, TraitKindInfo::Slot { .. } | TraitKindInfo::Const { .. }) {
                Self::format_trait(&mut out, trait_info, false);
            }
        }

        if !class.static_traits.is_empty() || !class.instance_traits.is_empty() {
            out.push('\n');
        }

        // Constructor
        if let Some(constructor) = &class.constructor {
            Self::format_method(&mut out, constructor, "public", false, false, false, "        ");
            out.push('\n');
        }

        // Instance Methods, Getters, Setters
        for trait_info in &class.instance_traits {
            if !matches!(trait_info.kind, TraitKindInfo::Slot { .. } | TraitKindInfo::Const { .. }) {
                Self::format_trait(&mut out, trait_info, false);
                out.push('\n');
            }
        }

        // Static Methods
        for trait_info in &class.static_traits {
            if !matches!(trait_info.kind, TraitKindInfo::Slot { .. } | TraitKindInfo::Const { .. }) {
                Self::format_trait(&mut out, trait_info, true);
                out.push('\n');
            }
        }

        out.push_str("    }\n}\n");
        out
    }

    fn format_trait(out: &mut String, trait_info: &TraitInfo, is_static: bool) {
        let static_prefix = if is_static { "static " } else { "" };
        let _override_prefix = if trait_info.is_override { "override " } else { "" };
        let final_prefix = if trait_info.is_final { "final " } else { "" };
        let access = &trait_info.access;

        match &trait_info.kind {
            TraitKindInfo::Slot { type_name, default_val } => {
                let init = default_val.as_ref().map(|v| format!(" = {}", v)).unwrap_or_default();
                out.push_str(&format!(
                    "        {} {}{}var {}: {}{};\n",
                    access, static_prefix, final_prefix, trait_info.name, type_name, init
                ));
            }
            TraitKindInfo::Const { type_name, default_val } => {
                let init = default_val.as_ref().map(|v| format!(" = {}", v)).unwrap_or_default();
                out.push_str(&format!(
                    "        {} {}{}const {}: {}{};\n",
                    access, static_prefix, final_prefix, trait_info.name, type_name, init
                ));
            }
            TraitKindInfo::Method(m) => {
                Self::format_method(out, m, access, is_static, trait_info.is_override, trait_info.is_final, "        ");
            }
            TraitKindInfo::Getter(m) => {
                Self::format_accessor(out, m, access, is_static, trait_info.is_override, "get", "        ");
            }
            TraitKindInfo::Setter(m) => {
                Self::format_accessor(out, m, access, is_static, trait_info.is_override, "set", "        ");
            }
            TraitKindInfo::Function(m) => {
                Self::format_method(out, m, access, is_static, trait_info.is_override, trait_info.is_final, "        ");
            }
        }
    }

    fn format_method(
        out: &mut String,
        m: &MethodInfo,
        access: &str,
        is_static: bool,
        is_override: bool,
        is_final: bool,
        indent: &str,
    ) {
        let static_prefix = if is_static { "static " } else { "" };
        let override_prefix = if is_override { "override " } else { "" };
        let _final_prefix = if is_final { "final " } else { "" };

        let params: Vec<String> = m.params.iter().map(Self::format_param).collect();
        let ret = if m.return_type.is_empty() {
            "".to_string()
        } else {
            format!(": {}", m.return_type)
        };

        out.push_str(&format!(
            "{}{}{}{}{}function {}({}){}\n{}{{\n",
            indent, access, if !access.is_empty() { " " } else { "" }, override_prefix, static_prefix, m.name, params.join(", "), ret, indent
        ));

        if !m.as3_source.is_empty() {
            for line in m.as3_source.lines() {
                out.push_str(&format!("{}    {}\n", indent, line));
            }
        }

        out.push_str(&format!("{}}}\n", indent));
    }

    fn format_accessor(
        out: &mut String,
        m: &MethodInfo,
        access: &str,
        is_static: bool,
        is_override: bool,
        accessor_kind: &str,
        indent: &str,
    ) {
        let static_prefix = if is_static { "static " } else { "" };
        let override_prefix = if is_override { "override " } else { "" };

        let params: Vec<String> = m.params.iter().map(Self::format_param).collect();
        let ret = if m.return_type.is_empty() {
            "".to_string()
        } else {
            format!(": {}", m.return_type)
        };

        out.push_str(&format!(
            "{}{}{}{}{}function {} {}({}){}\n{}{{\n",
            indent, access, if !access.is_empty() { " " } else { "" }, override_prefix, static_prefix, accessor_kind, m.name, params.join(", "), ret, indent
        ));

        if !m.as3_source.is_empty() {
            for line in m.as3_source.lines() {
                out.push_str(&format!("{}    {}\n", indent, line));
            }
        }

        out.push_str(&format!("{}}}\n", indent));
    }

    fn format_param(p: &ParamInfo) -> String {
        let mut s = format!("{}: {}", p.name, p.type_name);
        if let Some(def) = &p.default_value {
            s.push_str(&format!(" = {}", def));
        }
        s
    }

    pub fn format_statements(statements: &[Statement], indent_level: usize) -> String {
        let mut out = String::new();
        let indent = "    ".repeat(indent_level);

        for stmt in statements {
            match stmt {
                Statement::Expr(expr) => {
                    out.push_str(&format!("{}{};\n", indent, Self::format_expr(expr)));
                }
                Statement::VarDecl { name, type_name, init } => {
                    let ty = type_name.as_ref().map(|t| format!(": {}", t)).unwrap_or_default();
                    let init_str = init.as_ref().map(|e| format!(" = {}", Self::format_expr(e))).unwrap_or_default();
                    out.push_str(&format!("{}var {}{}{};\n", indent, name, ty, init_str));
                }
                Statement::If { cond, then_body, else_body } => {
                    out.push_str(&format!("{}if ({})\n{}{{\n", indent, Self::format_expr(cond), indent));
                    out.push_str(&Self::format_statements(then_body, indent_level + 1));
                    out.push_str(&format!("{}}}\n", indent));
                    if let Some(else_stmts) = else_body {
                        out.push_str(&format!("{}else\n{}{{\n", indent, indent));
                        out.push_str(&Self::format_statements(else_stmts, indent_level + 1));
                        out.push_str(&format!("{}}}\n", indent));
                    }
                }
                Statement::While { cond, body } => {
                    out.push_str(&format!("{}while ({})\n{}{{\n", indent, Self::format_expr(cond), indent));
                    out.push_str(&Self::format_statements(body, indent_level + 1));
                    out.push_str(&format!("{}}}\n", indent));
                }
                Statement::Return(opt_expr) => {
                    if let Some(expr) = opt_expr {
                        out.push_str(&format!("{}return {};\n", indent, Self::format_expr(expr)));
                    } else {
                        out.push_str(&format!("{}return;\n", indent));
                    }
                }
                Statement::Throw(expr) => {
                    out.push_str(&format!("{}throw {};\n", indent, Self::format_expr(expr)));
                }
                Statement::Break => {
                    out.push_str(&format!("{}break;\n", indent));
                }
                Statement::Continue => {
                    out.push_str(&format!("{}continue;\n", indent));
                }
                Statement::Comment(c) => {
                    out.push_str(&format!("{}// {}\n", indent, c));
                }
                Statement::Raw(r) => {
                    out.push_str(&format!("{}{}\n", indent, r));
                }
            }
        }

        out
    }

    pub fn format_expr(expr: &Expr) -> String {
        match expr {
            Expr::Null => "null".to_string(),
            Expr::Undefined => "undefined".to_string(),
            Expr::This => "this".to_string(),
            Expr::Super => "super".to_string(),
            Expr::Bool(b) => b.to_string(),
            Expr::Int(i) => i.to_string(),
            Expr::Uint(u) => u.to_string(),
            Expr::Number(n) => {
                if n.is_nan() {
                    "NaN".to_string()
                } else if n.is_infinite() {
                    if *n > 0.0 { "Infinity".to_string() } else { "-Infinity".to_string() }
                } else if n.fract() == 0.0 {
                    format!("{:.1}", n)
                } else {
                    n.to_string()
                }
            }
            Expr::String(s) => format!("\"{}\"", s.escape_debug()),
            Expr::Ident(name) => name.clone(),
            Expr::Unary { op, expr } => format!("{}{}", op, Self::format_expr(expr)),
            Expr::Binary { op, lhs, rhs } => {
                format!("{} {} {}", Self::format_expr(lhs), op, Self::format_expr(rhs))
            }
            Expr::Assign { lhs, rhs } => {
                format!("{} = {}", Self::format_expr(lhs), Self::format_expr(rhs))
            }
            Expr::Member { target, member } => {
                format!("{}.{}", Self::format_expr(target), member)
            }
            Expr::Index { target, index } => {
                format!("{}[{}]", Self::format_expr(target), Self::format_expr(index))
            }
            Expr::Call { callee, args } => {
                let formatted_args: Vec<String> = args.iter().map(Self::format_expr).collect();
                format!("{}({})", Self::format_expr(callee), formatted_args.join(", "))
            }
            Expr::Construct { callee, args } => {
                let formatted_args: Vec<String> = args.iter().map(Self::format_expr).collect();
                format!("new {}({})", Self::format_expr(callee), formatted_args.join(", "))
            }
            Expr::ArrayLiteral(items) => {
                let formatted: Vec<String> = items.iter().map(Self::format_expr).collect();
                format!("[{}]", formatted.join(", "))
            }
            Expr::ObjectLiteral(props) => {
                let formatted: Vec<String> = props
                    .iter()
                    .map(|(k, v)| format!("\"{}\": {}", k.escape_debug(), Self::format_expr(v)))
                    .collect();
                format!("{{{}}}", formatted.join(", "))
            }
            Expr::AsType { expr, type_name } => {
                format!("{} as {}", Self::format_expr(expr), type_name)
            }
            Expr::IsType { expr, type_name } => {
                format!("{} is {}", Self::format_expr(expr), type_name)
            }
        }
    }
}
