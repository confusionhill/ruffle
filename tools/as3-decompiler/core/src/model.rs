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

impl DecompiledProject {
    pub fn export_to_zip<W: std::io::Write + std::io::Seek>(&self, writer: W) -> anyhow::Result<usize> {
        use std::io::Write;
        use zip::write::SimpleFileOptions;
        use zip::ZipWriter;

        let mut zip = ZipWriter::new(writer);
        let options = SimpleFileOptions::default()
            .compression_method(zip::CompressionMethod::Deflated);

        let mut count = 0;
        for pkg in &self.packages {
            for class in &pkg.classes {
                let file_path = if pkg.name.is_empty() {
                    format!("{}.as", class.name)
                } else {
                    format!("{}/{}.as", pkg.name.replace('.', "/"), class.name)
                };

                zip.start_file(file_path, options)?;
                zip.write_all(class.as3_source.as_bytes())?;
                count += 1;
            }
        }

        zip.finish()?;
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

