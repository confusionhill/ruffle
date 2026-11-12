use crate::constant_pool_resolver::ConstantPoolResolver;
use crate::decompiler::MethodDecompiler;
use crate::disassembler::Disassembler;
use crate::formatter::Formatter;
use crate::model::*;
use anyhow::{Context, Result};
use std::collections::BTreeMap;
use swf::avm2::types::{AbcFile, MethodBody, Trait, TraitKind};
use swf::{decompress_swf, Tag};

pub struct ProjectBuilder;

impl ProjectBuilder {
    pub fn from_swf_bytes(data: &[u8]) -> Result<DecompiledProject> {
        let swf_buf = decompress_swf(data).context("Failed to decompress SWF")?;

        let swf_meta = SwfMetadata {
            swf_version: swf_buf.header.version(),
            compression: format!("{:?}", swf_buf.header.compression()),
            width: (swf_buf.header.stage_size().x_max - swf_buf.header.stage_size().x_min).to_pixels() as f32,
            height: (swf_buf.header.stage_size().y_max - swf_buf.header.stage_size().y_min).to_pixels() as f32,
            frame_rate: swf_buf.header.frame_rate().into(),
            num_frames: swf_buf.header.num_frames(),
            total_abc_blocks: 0,
            total_classes: 0,
            total_scripts: 0,
        };

        let mut abc_files = Vec::new();
        let mut reader = swf::read::Reader::new(&swf_buf.data[..], swf_buf.header.version());

        while let Ok(tag) = reader.read_tag() {
            match tag {
                Tag::End => break,
                Tag::DoAbc(data) => {
                    let mut abc_reader = swf::avm2::read::Reader::new(data);
                    if let Ok(abc) = abc_reader.read() {
                        abc_files.push(abc);
                    }
                }
                Tag::DoAbc2(do_abc2) => {
                    let mut abc_reader = swf::avm2::read::Reader::new(do_abc2.data);
                    if let Ok(abc) = abc_reader.read() {
                        abc_files.push(abc);
                    }
                }
                _ => {}
            }
        }

        Self::build_project_from_abcs(swf_meta, abc_files)
    }

    pub fn build_project_from_abcs(
        mut meta: SwfMetadata,
        abc_files: Vec<AbcFile>,
    ) -> Result<DecompiledProject> {
        meta.total_abc_blocks = abc_files.len();

        let mut packages_map: BTreeMap<String, (Vec<ClassInfo>, Vec<ScriptInfo>)> = BTreeMap::new();
        let mut total_classes = 0;
        let mut total_scripts = 0;

        for abc in &abc_files {
            let resolver = ConstantPoolResolver::new(abc);
            let disassembler = Disassembler::new(abc);

            // Extract classes from instances and classes
            for (idx, instance) in abc.instances.iter().enumerate() {
                total_classes += 1;
                let class = abc.classes.get(idx);

                let (pkg, class_name, _access) = resolver.split_qname(instance.name);
                let super_name = if instance.super_name.0 != 0 {
                    let (_, name, _) = resolver.split_qname(instance.super_name);
                    Some(name)
                } else {
                    None
                };

                let interfaces = instance
                    .interfaces
                    .iter()
                    .map(|iface| resolver.multiname(*iface))
                    .collect();

                // Constructor
                let constructor = Self::extract_method(
                    abc,
                    &resolver,
                    &disassembler,
                    instance.init_method.0,
                    &class_name,
                    true,
                );

                // Instance traits
                let mut instance_traits = Vec::new();
                for t in &instance.traits {
                    if let Some(trait_info) = Self::extract_trait(abc, &resolver, &disassembler, t, true) {
                        instance_traits.push(trait_info);
                    }
                }

                // Static traits
                let mut static_traits = Vec::new();
                if let Some(c) = class {
                    for t in &c.traits {
                        if let Some(trait_info) = Self::extract_trait(abc, &resolver, &disassembler, t, false) {
                            static_traits.push(trait_info);
                        }
                    }
                }

                // Build combined bytecode disassembly for the class
                let mut bytecode_text = String::new();
                bytecode_text.push_str(&format!("// Class: {}.{}\n\n", pkg, class_name));
                if let Some(ctor) = &constructor {
                    bytecode_text.push_str(&format!("// Method: constructor {}\n", ctor.name));
                    bytecode_text.push_str(&ctor.disassembly);
                    bytecode_text.push('\n');
                }
                for t in &instance_traits {
                    Self::append_trait_bytecode(&mut bytecode_text, t);
                }
                for t in &static_traits {
                    Self::append_trait_bytecode(&mut bytecode_text, t);
                }

                let mut class_info = ClassInfo {
                    id: if pkg.is_empty() {
                        class_name.clone()
                    } else {
                        format!("{}::{}", pkg, class_name)
                    },
                    package_name: pkg.clone(),
                    name: class_name,
                    super_name,
                    interfaces,
                    is_interface: instance.is_interface,
                    is_final: instance.is_final,
                    is_sealed: instance.is_sealed,
                    constructor,
                    instance_traits,
                    static_traits,
                    as3_source: String::new(),
                    bytecode_text,
                };

                // Format high-level AS3 code
                class_info.as3_source = Formatter::format_class(&class_info);

                let entry = packages_map.entry(pkg).or_insert_with(|| (Vec::new(), Vec::new()));
                entry.0.push(class_info);
            }

            // Extract standalone scripts
            for (idx, script) in abc.scripts.iter().enumerate() {
                total_scripts += 1;
                let script_name = format!("script_{}", idx);
                let mut script_traits = Vec::new();
                for t in &script.traits {
                    if let Some(trait_info) = Self::extract_trait(abc, &resolver, &disassembler, t, false) {
                        script_traits.push(trait_info);
                    }
                }

                let entry = packages_map.entry("".to_string()).or_insert_with(|| (Vec::new(), Vec::new()));
                entry.1.push(ScriptInfo {
                    name: script_name,
                    traits: script_traits,
                    as3_source: "// Standalone script\n".to_string(),
                    bytecode_text: "// Script bytecode\n".to_string(),
                });
            }
        }

        meta.total_classes = total_classes;
        meta.total_scripts = total_scripts;

        let packages = packages_map
            .into_iter()
            .map(|(name, (classes, scripts))| PackageInfo {
                name,
                classes,
                scripts,
            })
            .collect();

        Ok(DecompiledProject {
            metadata: meta,
            packages,
        })
    }

    fn extract_trait(
        abc: &AbcFile,
        resolver: &ConstantPoolResolver,
        disassembler: &Disassembler,
        t: &Trait,
        is_instance: bool,
    ) -> Option<TraitInfo> {
        let (_pkg, name, access) = resolver.split_qname(t.name);
        let is_override = t.is_override;
        let is_final = t.is_final;

        let kind = match &t.kind {
            TraitKind::Slot { slot_id: _, type_name, value } => {
                let ty = resolver.multiname(*type_name);
                let val_str = value.as_ref().map(|v| resolver.default_value(v));
                TraitKindInfo::Slot {
                    type_name: ty,
                    default_val: val_str,
                }
            }
            TraitKind::Const { slot_id: _, type_name, value } => {
                let ty = resolver.multiname(*type_name);
                let val_str = value.as_ref().map(|v| resolver.default_value(v));
                TraitKindInfo::Const {
                    type_name: ty,
                    default_val: val_str,
                }
            }
            TraitKind::Method { disp_id: _, method } => {
                let m = Self::extract_method(abc, resolver, disassembler, method.0, &name, is_instance)?;
                TraitKindInfo::Method(m)
            }
            TraitKind::Getter { disp_id: _, method } => {
                let m = Self::extract_method(abc, resolver, disassembler, method.0, &name, is_instance)?;
                TraitKindInfo::Getter(m)
            }
            TraitKind::Setter { disp_id: _, method } => {
                let m = Self::extract_method(abc, resolver, disassembler, method.0, &name, is_instance)?;
                TraitKindInfo::Setter(m)
            }
            TraitKind::Function { slot_id: _, function } => {
                let m = Self::extract_method(abc, resolver, disassembler, function.0, &name, is_instance)?;
                TraitKindInfo::Function(m)
            }
            TraitKind::Class { .. } => return None,
        };

        Some(TraitInfo {
            name,
            access,
            is_override,
            is_final,
            kind,
        })
    }

    fn extract_method(
        abc: &AbcFile,
        resolver: &ConstantPoolResolver,
        disassembler: &Disassembler,
        method_idx: u32,
        name: &str,
        is_instance: bool,
    ) -> Option<MethodInfo> {
        let method = abc.methods.get(method_idx as usize)?;

        let mut params = Vec::new();
        for (i, p) in method.params.iter().enumerate() {
            let param_name = if let Some(n_idx) = p.name {
                let n = resolver.string(n_idx);
                if !n.is_empty() && n != "*" {
                    n
                } else {
                    format!("param{}", i + 1)
                }
            } else {
                format!("param{}", i + 1)
            };
            let type_name = resolver.multiname(p.kind);
            let default_val = p.default_value.as_ref().map(|v| resolver.default_value(v));
            params.push(ParamInfo {
                name: param_name,
                type_name,
                default_value: default_val,
            });
        }

        let return_type = resolver.multiname(method.return_type);

        let (disassembly, as3_source) = if let Some(body) = Self::find_method_body(abc, method_idx) {
            let disasm = disassembler.disassemble_method_body(body);
            let decompiler = MethodDecompiler::new(abc, method, is_instance);
            let statements = decompiler.decompile_body(body);
            let as3 = Formatter::format_statements(&statements, 0);
            (disasm, as3)
        } else {
            ("// Native or abstract method\n".to_string(), String::new())
        };

        Some(MethodInfo {
            name: name.to_string(),
            params,
            return_type,
            as3_source,
            disassembly,
        })
    }

    fn find_method_body<'a>(abc: &'a AbcFile, method_idx: u32) -> Option<&'a MethodBody> {
        abc.method_bodies.iter().find(|b| b.method.0 == method_idx)
    }

    fn append_trait_bytecode(out: &mut String, t: &TraitInfo) {
        match &t.kind {
            TraitKindInfo::Method(m)
            | TraitKindInfo::Getter(m)
            | TraitKindInfo::Setter(m)
            | TraitKindInfo::Function(m) => {
                out.push_str(&format!("// Method: {} {}\n", t.name, m.name));
                out.push_str(&m.disassembly);
                out.push('\n');
            }
            _ => {}
        }
    }
}

