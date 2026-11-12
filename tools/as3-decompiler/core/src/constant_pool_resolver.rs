use swf::avm2::types::{
    AbcFile, ConstantPool, DefaultValue, Index, Multiname, Namespace,
};

pub struct ConstantPoolResolver<'a> {
    pub pool: &'a ConstantPool,
}

impl<'a> ConstantPoolResolver<'a> {
    pub fn new(abc: &'a AbcFile) -> Self {
        Self {
            pool: &abc.constant_pool,
        }
    }

    pub fn string(&self, index: Index<String>) -> String {
        let i = index.0 as usize;
        if i == 0 {
            return "*".to_string();
        }
        if let Some(bytes) = self.pool.strings.get(i - 1) {
            String::from_utf8_lossy(bytes).into_owned()
        } else {
            format!("<invalid string index {}>", i)
        }
    }

    pub fn namespace(&self, index: Index<Namespace>) -> (String, String) {
        let i = index.0 as usize;
        if i == 0 {
            return ("public".to_string(), "".to_string());
        }
        let Some(ns) = self.pool.namespaces.get(i - 1) else {
            return ("public".to_string(), "".to_string());
        };

        match ns {
            Namespace::Namespace(idx) => ("public".to_string(), self.string(*idx)),
            Namespace::Package(idx) => ("public".to_string(), self.string(*idx)),
            Namespace::PackageInternal(idx) => ("internal".to_string(), self.string(*idx)),
            Namespace::Protected(idx) => ("protected".to_string(), self.string(*idx)),
            Namespace::Explicit(idx) => ("explicit".to_string(), self.string(*idx)),
            Namespace::StaticProtected(idx) => ("protected".to_string(), self.string(*idx)),
            Namespace::Private(idx) => ("private".to_string(), self.string(*idx)),
        }
    }

    pub fn multiname(&self, index: Index<Multiname>) -> String {
        let i = index.0 as usize;
        if i == 0 {
            return "*".to_string();
        }
        let Some(mn) = self.pool.multinames.get(i - 1) else {
            return format!("<invalid multiname index {}>", i);
        };

        match mn {
            Multiname::QName { namespace, name } | Multiname::QNameA { namespace, name } => {
                let (_, ns_url) = self.namespace(*namespace);
                let n = self.string(*name);
                if ns_url.is_empty() {
                    n
                } else {
                    format!("{}.{}", ns_url, n)
                }
            }
            Multiname::RTQName { name } | Multiname::RTQNameA { name } => {
                let n = self.string(*name);
                format!("[rtq]::{}", n)
            }
            Multiname::RTQNameL | Multiname::RTQNameLA => "[rtql]".to_string(),
            Multiname::Multiname { name, .. } | Multiname::MultinameA { name, .. } => {
                self.string(*name)
            }
            Multiname::MultinameL { .. } | Multiname::MultinameLA { .. } => "[multil]".to_string(),
            Multiname::TypeName { base_type, parameters } => {
                let base = self.multiname(*base_type);
                let param_names: Vec<String> = parameters.iter().map(|p| self.multiname(*p)).collect();
                format!("{}.<{}>", base, param_names.join(", "))
            }
        }
    }

    pub fn property_name(&self, index: Index<Multiname>) -> String {
        let i = index.0 as usize;
        if i == 0 {
            return "*".to_string();
        }
        let Some(mn) = self.pool.multinames.get(i - 1) else {
            return format!("<invalid multiname index {}>", i);
        };

        match mn {
            Multiname::QName { name, .. }
            | Multiname::QNameA { name, .. }
            | Multiname::Multiname { name, .. }
            | Multiname::MultinameA { name, .. } => self.string(*name),
            _ => self.multiname(index),
        }
    }
    pub fn split_qname(&self, index: Index<Multiname>) -> (String, String, String) {
        let i = index.0 as usize;
        if i == 0 {
            return ("".to_string(), "*".to_string(), "public".to_string());
        }
        let Some(mn) = self.pool.multinames.get(i - 1) else {
            return ("".to_string(), "*".to_string(), "public".to_string());
        };

        match mn {
            Multiname::QName { namespace, name } | Multiname::QNameA { namespace, name } => {
                let (access, pkg) = self.namespace(*namespace);
                let class_name = self.string(*name);
                (pkg, class_name, access)
            }
            _ => ("".to_string(), self.multiname(index), "public".to_string()),
        }
    }

    pub fn default_value(&self, val: &DefaultValue) -> String {
        match val {
            DefaultValue::Int(idx) => {
                let i = idx.0 as usize;
                if i > 0 && i <= self.pool.ints.len() {
                    self.pool.ints[i - 1].to_string()
                } else {
                    "0".to_string()
                }
            }
            DefaultValue::Uint(idx) => {
                let i = idx.0 as usize;
                if i > 0 && i <= self.pool.uints.len() {
                    self.pool.uints[i - 1].to_string()
                } else {
                    "0".to_string()
                }
            }
            DefaultValue::Double(idx) => {
                let i = idx.0 as usize;
                if i > 0 && i <= self.pool.doubles.len() {
                    let d = self.pool.doubles[i - 1];
                    if d.fract() == 0.0 {
                        format!("{:.1}", d)
                    } else {
                        d.to_string()
                    }
                } else {
                    "0.0".to_string()
                }
            }
            DefaultValue::String(idx) => format!("\"{}\"", self.string(*idx).escape_debug()),
            DefaultValue::True => "true".to_string(),
            DefaultValue::False => "false".to_string(),
            DefaultValue::Null => "null".to_string(),
            DefaultValue::Undefined => "undefined".to_string(),
            DefaultValue::Namespace(idx)
            | DefaultValue::Package(idx)
            | DefaultValue::PackageInternal(idx)
            | DefaultValue::Protected(idx)
            | DefaultValue::Explicit(idx)
            | DefaultValue::StaticProtected(idx)
            | DefaultValue::Private(idx) => {
                let (_, ns) = self.namespace(*idx);
                ns
            }
        }
    }
}
