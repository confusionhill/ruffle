mod app;
mod state;
mod syntax;
mod theme;

use app::DecompilerApp;
use gpui::*;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.iter().any(|a| a == "--dump" || a == "-d") {
        if let Some(path_str) = args.iter().skip(1).find(|a| !a.starts_with('-')) {
            let path = std::path::PathBuf::from(path_str);
            match std::fs::read(&path) {
                Ok(bytes) => match as3_decompiler_core::ProjectBuilder::from_swf_bytes(&bytes) {
                    Ok(project) => {
                        println!("=== Decompiled SWF: {:?} ===", path.file_name().unwrap_or_default());
                        println!(
                            "Flash v{} • {}x{} @ {}fps • Total Classes: {}\n",
                            project.metadata.swf_version,
                            project.metadata.width as i32,
                            project.metadata.height as i32,
                            project.metadata.frame_rate as i32,
                            project.metadata.total_classes
                        );
                        for pkg in &project.packages {
                            let pkg_label = if pkg.name.is_empty() { "(default package)" } else { &pkg.name };
                            println!("Package: {}", pkg_label);
                            for class in &pkg.classes {
                                println!("\n// ==========================================");
                                println!("// Class: {}", class.name);
                                println!("// ==========================================\n");
                                println!("{}", class.as3_source);
                            }
                        }
                        return;
                    }
                    Err(e) => {
                        eprintln!("Decompilation error: {}", e);
                        std::process::exit(1);
                    }
                },
                Err(e) => {
                    eprintln!("File read error: {}", e);
                    std::process::exit(1);
                }
            }
        } else {
            eprintln!("Usage: as3-decompiler-gui --dump <file.swf>");
            std::process::exit(1);
        }
    }

    Application::new().run(|cx: &mut App| {
        let bounds = Bounds::centered(None, size(px(1280.0), px(820.0)), cx);
        let window_options = WindowOptions {
            window_bounds: Some(WindowBounds::Windowed(bounds)),
            titlebar: Some(TitlebarOptions {
                title: Some("AS3 Wizard - ActionScript 3 Decompiler".into()),
                appears_transparent: true,
                traffic_light_position: Some(point(px(12.0), px(12.0))),
            }),
            ..Default::default()
        };

        cx.open_window(window_options, |_, cx| {
            let app_view = cx.new(|_| DecompilerApp::new());

            // If a file argument was passed on command line, auto-load it!
            if let Some(arg) = std::env::args().nth(1) {
                let path = std::path::PathBuf::from(arg);
                if path.exists() {
                    app_view.update(cx, |this, cx| {
                        this.load_swf_file(path, cx);
                    });
                }
            }

            app_view
        })
        .unwrap();

        cx.activate(true);
    });
}
