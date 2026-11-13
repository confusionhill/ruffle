use std::io::{self, Read};
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use as3_decompiler_core::{
    ClassInfo, DecompiledProject, ExportMode, ProjectBuilder, SwfMetadata, TraitKindInfo,
};
use clap::{Parser, Subcommand, ValueEnum};
use serde::Serialize;

#[derive(Parser, Debug)]
#[command(
    name = "as3-decompiler",
    version,
    about = "Headless ActionScript 3 (AS3) SWF decompiler and disassembler"
)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand, Debug)]
enum Commands {
    /// Inspect SWF metadata and list packages, classes, and members.
    Info {
        /// Path to the SWF file, or '-' to read from stdin.
        input: String,
        /// Include constructors, methods, getters/setters, and properties under each class.
        #[arg(short, long)]
        methods: bool,
    },
    /// Decompile and print AS3 source or AVM2 bytecode disassembly to stdout.
    Dump {
        /// Path to the SWF file, or '-' to read from stdin.
        input: String,
        /// Output format mode.
        #[arg(short, long, value_enum, default_value_t = OutputMode::As3)]
        mode: OutputMode,
        /// Filter by class name or fully qualified name (substring match, repeatable).
        #[arg(short, long)]
        class: Vec<String>,
        /// Filter by package name (substring match, repeatable).
        #[arg(short, long)]
        package: Vec<String>,
    },
    /// Export all decompiled classes to a directory tree or a ZIP archive.
    Export {
        /// Path to the SWF file, or '-' to read from stdin.
        input: String,
        /// Output directory path or .zip archive path.
        #[arg(short, long)]
        output: PathBuf,
        /// Output format mode.
        #[arg(short, long, value_enum, default_value_t = OutputMode::As3)]
        mode: OutputMode,
        /// Force writing a ZIP archive even if the output path does not end with .zip.
        #[arg(long)]
        zip: bool,
    },
    /// Emit the decompiled project as structured JSON.
    Json {
        /// Path to the SWF file, or '-' to read from stdin.
        input: String,
        /// Pretty-print JSON output.
        #[arg(long)]
        pretty: bool,
        /// Emit only metadata and package/class summaries without source/bytecode bodies.
        #[arg(long)]
        summary: bool,
        /// Write JSON output to a file instead of stdout.
        #[arg(short, long)]
        output: Option<PathBuf>,
    },
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, ValueEnum)]
enum OutputMode {
    As3,
    Bytecode,
    Both,
}

impl From<OutputMode> for ExportMode {
    fn from(value: OutputMode) -> Self {
        match value {
            OutputMode::As3 => ExportMode::As3,
            OutputMode::Bytecode => ExportMode::Bytecode,
            OutputMode::Both => ExportMode::Both,
        }
    }
}

#[derive(Serialize)]
struct ProjectSummary<'a> {
    metadata: &'a SwfMetadata,
    packages: Vec<PackageSummary<'a>>,
}

#[derive(Serialize)]
struct PackageSummary<'a> {
    name: &'a str,
    classes: Vec<ClassSummary<'a>>,
}

#[derive(Serialize)]
struct ClassSummary<'a> {
    id: &'a str,
    name: &'a str,
    super_name: Option<&'a str>,
    interfaces: &'a [String],
    is_interface: bool,
    is_final: bool,
    is_sealed: bool,
    member_count: usize,
}

fn load_project(input: &str) -> Result<DecompiledProject> {
    let bytes = if input == "-" {
        let mut buf = Vec::new();
        io::stdin()
            .read_to_end(&mut buf)
            .context("Failed to read SWF bytes from stdin")?;
        buf
    } else {
        std::fs::read(input).with_context(|| format!("Failed to read SWF file '{}'", input))?
    };

    ProjectBuilder::from_swf_bytes(&bytes)
        .with_context(|| format!("Failed to decompile SWF from '{}'", input))
}

fn pkg_display_name(name: &str) -> &str {
    if name.is_empty() {
        "(default package)"
    } else {
        name
    }
}

fn matches_filters(value: &str, filters: &[String]) -> bool {
    filters.is_empty()
        || filters
            .iter()
            .any(|f| value.to_lowercase().contains(&f.to_lowercase()))
}

fn class_matches(class: &ClassInfo, pkg_filters: &[String], class_filters: &[String]) -> bool {
    let pkg_ok = matches_filters(&class.package_name, pkg_filters);
    let fqn = if class.package_name.is_empty() {
        class.name.clone()
    } else {
        format!("{}.{}", class.package_name, class.name)
    };
    let class_ok =
        matches_filters(&class.name, class_filters) || matches_filters(&fqn, class_filters);
    pkg_ok && class_ok
}

fn run_info(project: &DecompiledProject, show_methods: bool) {
    let m = &project.metadata;
    println!(
        "Flash v{} | Compression: {} | {}x{} @ {}fps | {} frames",
        m.swf_version, m.compression, m.width as i32, m.height as i32, m.frame_rate as i32, m.num_frames
    );
    println!(
        "ABC blocks: {} | Classes: {} | Scripts: {}",
        m.total_abc_blocks, m.total_classes, m.total_scripts
    );
    println!();

    for pkg in &project.packages {
        println!("{} ({} classes)", pkg_display_name(&pkg.name), pkg.classes.len());
        for class in &pkg.classes {
            let kind = if class.is_interface { "interface" } else { "class" };
            let ext = class
                .super_name
                .as_deref()
                .map(|s| format!(" extends {}", s))
                .unwrap_or_default();
            println!("  [{}] {}{}", kind, class.name, ext);

            if show_methods {
                if let Some(ctor) = &class.constructor {
                    println!("    ctor {}()", ctor.name);
                }
                for t in &class.instance_traits {
                    println!("    {} {}: {}", trait_kind_label(&t.kind), t.access, t.name);
                }
                for t in &class.static_traits {
                    println!("    static {} {}: {}", trait_kind_label(&t.kind), t.access, t.name);
                }
            }
        }
    }
}

fn trait_kind_label(kind: &TraitKindInfo) -> &'static str {
    match kind {
        TraitKindInfo::Slot { .. } => "var",
        TraitKindInfo::Const { .. } => "const",
        TraitKindInfo::Method(_) => "method",
        TraitKindInfo::Getter(_) => "get",
        TraitKindInfo::Setter(_) => "set",
        TraitKindInfo::Function(_) => "fn",
    }
}

fn run_dump(
    project: &DecompiledProject,
    mode: OutputMode,
    class_filters: &[String],
    pkg_filters: &[String],
) {
    let mut matched = 0usize;
    for pkg in &project.packages {
        for class in &pkg.classes {
            if !class_matches(class, pkg_filters, class_filters) {
                continue;
            }
            matched += 1;
            println!("// ==========================================");
            println!(
                "// Class: {} (package: {})",
                class.name,
                pkg_display_name(&pkg.name)
            );
            println!("// ==========================================\n");

            if matches!(mode, OutputMode::As3 | OutputMode::Both) {
                println!("{}", class.as3_source);
            }
            if matches!(mode, OutputMode::Bytecode | OutputMode::Both) {
                if mode == OutputMode::Both {
                    println!("// --- AVM2 Bytecode Disassembly ---\n");
                }
                println!("{}", class.bytecode_text);
            }
        }
    }

    if matched == 0 {
        eprintln!("No classes matched the given filters.");
    }
}

fn run_export(
    project: &DecompiledProject,
    output: &Path,
    mode: OutputMode,
    force_zip: bool,
) -> Result<()> {
    let is_zip = force_zip
        || output
            .extension()
            .and_then(|e| e.to_str())
            .is_some_and(|e| e.eq_ignore_ascii_case("zip"));

    if is_zip {
        if let Some(parent) = output.parent().filter(|p| !p.as_os_str().is_empty()) {
            std::fs::create_dir_all(parent)?;
        }
        let file = std::fs::File::create(output)
            .with_context(|| format!("Failed to create ZIP file '{}'", output.display()))?;
        let count = project.export_to_zip_with_mode(file, mode.into())?;
        println!("Exported {} file(s) to ZIP: {}", count, output.display());
    } else {
        let count = project.export_to_dir(output, mode.into())?;
        println!("Exported {} file(s) to directory: {}", count, output.display());
    }

    Ok(())
}

fn build_summary(project: &DecompiledProject) -> ProjectSummary<'_> {
    ProjectSummary {
        metadata: &project.metadata,
        packages: project
            .packages
            .iter()
            .map(|pkg| PackageSummary {
                name: &pkg.name,
                classes: pkg
                    .classes
                    .iter()
                    .map(|c| ClassSummary {
                        id: &c.id,
                        name: &c.name,
                        super_name: c.super_name.as_deref(),
                        interfaces: &c.interfaces,
                        is_interface: c.is_interface,
                        is_final: c.is_final,
                        is_sealed: c.is_sealed,
                        member_count: c.instance_traits.len() + c.static_traits.len(),
                    })
                    .collect(),
            })
            .collect(),
    }
}

fn run_json(
    project: &DecompiledProject,
    pretty: bool,
    summary: bool,
    output: Option<&Path>,
) -> Result<()> {
    let json = if summary {
        let s = build_summary(project);
        if pretty {
            serde_json::to_string_pretty(&s)?
        } else {
            serde_json::to_string(&s)?
        }
    } else if pretty {
        serde_json::to_string_pretty(project)?
    } else {
        serde_json::to_string(project)?
    };

    if let Some(path) = output {
        if let Some(parent) = path.parent().filter(|p| !p.as_os_str().is_empty()) {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(path, json.as_bytes())
            .with_context(|| format!("Failed to write JSON to '{}'", path.display()))?;
    } else {
        println!("{}", json);
    }

    Ok(())
}

fn main() -> Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Commands::Info { input, methods } => {
            let project = load_project(&input)?;
            run_info(&project, methods);
        }
        Commands::Dump {
            input,
            mode,
            class,
            package,
        } => {
            let project = load_project(&input)?;
            run_dump(&project, mode, &class, &package);
        }
        Commands::Export {
            input,
            output,
            mode,
            zip,
        } => {
            let project = load_project(&input)?;
            run_export(&project, &output, mode, zip)?;
        }
        Commands::Json {
            input,
            pretty,
            summary,
            output,
        } => {
            let project = load_project(&input)?;
            run_json(&project, pretty, summary, output.as_deref())?;
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use clap::CommandFactory;

    #[test]
    fn verify_cli_schema() {
        Cli::command().debug_assert();
    }

    #[test]
    fn test_cli_parse_export_zip() {
        let cli = Cli::try_parse_from([
            "as3-decompiler",
            "export",
            "game.swf",
            "-o",
            "out.zip",
            "--mode",
            "both",
        ])
        .unwrap();

        match cli.command {
            Commands::Export {
                input,
                output,
                mode,
                zip,
            } => {
                assert_eq!(input, "game.swf");
                assert_eq!(output, PathBuf::from("out.zip"));
                assert_eq!(mode, OutputMode::Both);
                assert!(!zip);
            }
            _ => panic!("expected Export command"),
        }
    }
}
