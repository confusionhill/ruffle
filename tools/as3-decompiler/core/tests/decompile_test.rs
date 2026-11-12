use as3_decompiler_core::ProjectBuilder;
use std::path::PathBuf;

#[test]
fn test_decompile_real_swf() {
    let swf_path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../../tests/tests/swfs/from_shumway/as3-interfaces/test.swf");

    assert!(swf_path.exists(), "Test SWF not found at {:?}", swf_path);

    let bytes = std::fs::read(&swf_path).expect("Failed to read SWF file");
    let project = ProjectBuilder::from_swf_bytes(&bytes).expect("Failed to parse and decompile SWF");

    println!("Metadata: {:?}", project.metadata);
    println!("Packages count: {}", project.packages.len());

    assert!(project.metadata.total_abc_blocks > 0);
    assert!(project.metadata.total_classes > 0);

    for pkg in &project.packages {
        println!("Package: '{}'", pkg.name);
        for class in &pkg.classes {
            println!("  Class: {}", class.name);
            println!("  --- AS3 Decompiled ---\n{}\n", class.as3_source);
            println!("  --- Bytecode Disassembly ---\n{}\n", class.bytecode_text);
            assert!(!class.as3_source.is_empty());
            assert!(!class.bytecode_text.is_empty());
        }
    }
}

