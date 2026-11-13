use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SwfMetadata {
    pub swf_version: u8,
    pub compression: String,
    pub width: f32,
    pub height: f32,
    pub frame_rate: f32,
    pub num_frames: u16,
    pub total_abc_blocks: usize,
    pub total_classes: usize,
    pub total_scripts: usize,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct DecompiledProject {
    pub metadata: SwfMetadata,
    pub packages: Vec<PackageInfo>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ExportMode {
    As3,
    Bytecode,
    Both,
}

fn class_rel_path(pkg_name: &str, class_name: &str, ext: &str) -> String {
    if pkg_name.is_empty() {
        format!("{class_name}.{ext}")
    } else {
        format!("{}/{class_name}.{ext}", pkg_name.replace('.', "/"))
    }
}

impl DecompiledProject {
    pub fn export_to_zip<W: std::io::Write + std::io::Seek>(&self, writer: W) -> anyhow::Result<usize> {
        self.export_to_zip_with_mode(writer, ExportMode::As3)
    }

    pub fn export_to_zip_with_mode<W: std::io::Write + std::io::Seek>(
        &self,
        writer: W,
        mode: ExportMode,
    ) -> anyhow::Result<usize> {
        use std::io::Write;
        use zip::write::SimpleFileOptions;
        use zip::ZipWriter;

        let mut zip = ZipWriter::new(writer);
        let options = SimpleFileOptions::default()
            .compression_method(zip::CompressionMethod::Deflated);

        let mut count = 0;
        for pkg in &self.packages {
            for class in &pkg.classes {
                if matches!(mode, ExportMode::As3 | ExportMode::Both) {
                    let file_path = class_rel_path(&pkg.name, &class.name, "as");
                    zip.start_file(file_path, options)?;
                    zip.write_all(class.as3_source.as_bytes())?;
                    count += 1;
                }
                if matches!(mode, ExportMode::Bytecode | ExportMode::Both) {
                    let file_path = class_rel_path(&pkg.name, &class.name, "asm");
                    zip.start_file(file_path, options)?;
                    zip.write_all(class.bytecode_text.as_bytes())?;
                    count += 1;
                }
            }
        }

        zip.finish()?;
        Ok(count)
    }

    pub fn export_to_dir(
        &self,
        out_dir: &std::path::Path,
        mode: ExportMode,
    ) -> anyhow::Result<usize> {
        let mut count = 0;
        for pkg in &self.packages {
            for class in &pkg.classes {
                if matches!(mode, ExportMode::As3 | ExportMode::Both) {
                    let dest = out_dir.join(class_rel_path(&pkg.name, &class.name, "as"));
                    if let Some(parent) = dest.parent() {
                        std::fs::create_dir_all(parent)?;
                    }
                    std::fs::write(&dest, class.as3_source.as_bytes())?;
                    count += 1;
                }
                if matches!(mode, ExportMode::Bytecode | ExportMode::Both) {
                    let dest = out_dir.join(class_rel_path(&pkg.name, &class.name, "asm"));
                    if let Some(parent) = dest.parent() {
                        std::fs::create_dir_all(parent)?;
                    }
                    std::fs::write(&dest, class.bytecode_text.as_bytes())?;
                    count += 1;
                }
            }
        }
        Ok(count)
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct PackageInfo {

    pub name: String,
    pub classes: Vec<ClassInfo>,
    pub scripts: Vec<ScriptInfo>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ClassInfo {
    pub id: String,
    pub package_name: String,
    pub name: String,
    pub super_name: Option<String>,
    pub interfaces: Vec<String>,
    pub is_interface: bool,
    pub is_final: bool,
    pub is_sealed: bool,
    pub constructor: Option<MethodInfo>,
    pub instance_traits: Vec<TraitInfo>,
    pub static_traits: Vec<TraitInfo>,
    pub as3_source: String,
    pub bytecode_text: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ScriptInfo {
    pub name: String,
    pub traits: Vec<TraitInfo>,
    pub as3_source: String,
    pub bytecode_text: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct TraitInfo {
    pub name: String,
    pub access: String,
    pub is_override: bool,
    pub is_final: bool,
    pub kind: TraitKindInfo,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub enum TraitKindInfo {
    Slot {
        type_name: String,
        default_val: Option<String>,
    },
    Const {
        type_name: String,
        default_val: Option<String>,
    },
    Method(MethodInfo),
    Getter(MethodInfo),
    Setter(MethodInfo),
    Function(MethodInfo),
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct MethodInfo {
    pub name: String,
    pub params: Vec<ParamInfo>,
    pub return_type: String,
    pub as3_source: String,
    pub disassembly: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ParamInfo {
    pub name: String,
    pub type_name: String,
    pub default_value: Option<String>,
}

