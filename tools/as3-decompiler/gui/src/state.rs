use as3_decompiler_core::{ClassInfo, DecompiledProject, MethodInfo};
use std::collections::HashSet;
use std::path::PathBuf;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ViewMode {
    DecompiledAs3,
    Disassembly,
    Split,
}

#[allow(dead_code)]
pub struct AppState {
    pub current_file_name: Option<String>,
    pub current_file_path: Option<PathBuf>,
    pub project: Option<DecompiledProject>,
    pub selected_class_id: Option<String>,
    pub selected_method_name: Option<String>,
    pub view_mode: ViewMode,
    pub search_query: String,
    pub status_message: String,
    pub expanded_packages: HashSet<String>,
    pub expanded_classes: HashSet<String>,
}

impl Default for AppState {
    fn default() -> Self {
        Self {
            current_file_name: None,
            current_file_path: None,
            project: None,
            selected_class_id: None,
            selected_method_name: None,
            view_mode: ViewMode::DecompiledAs3,
            search_query: String::new(),
            status_message: "Ready. Click 'Open SWF' or drop a file to decompile.".to_string(),
            expanded_packages: HashSet::new(),
            expanded_classes: HashSet::new(),
        }
    }
}

impl AppState {
    pub fn selected_class(&self) -> Option<&ClassInfo> {
        let id = self.selected_class_id.as_ref()?;
        let project = self.project.as_ref()?;
        for pkg in &project.packages {
            for class in &pkg.classes {
                if &class.id == id {
                    return Some(class);
                }
            }
        }
        None
    }

    pub fn selected_method(&self) -> Option<&MethodInfo> {
        let class = self.selected_class()?;
        let method_name = self.selected_method_name.as_ref()?;

        if let Some(ctor) = &class.constructor {
            if &ctor.name == method_name {
                return Some(ctor);
            }
        }

        for t in &class.instance_traits {
            match &t.kind {
                as3_decompiler_core::TraitKindInfo::Method(m)
                | as3_decompiler_core::TraitKindInfo::Getter(m)
                | as3_decompiler_core::TraitKindInfo::Setter(m)
                | as3_decompiler_core::TraitKindInfo::Function(m) => {
                    if &t.name == method_name || &m.name == method_name {
                        return Some(m);
                    }
                }
                _ => {}
            }
        }

        for t in &class.static_traits {
            match &t.kind {
                as3_decompiler_core::TraitKindInfo::Method(m)
                | as3_decompiler_core::TraitKindInfo::Getter(m)
                | as3_decompiler_core::TraitKindInfo::Setter(m)
                | as3_decompiler_core::TraitKindInfo::Function(m) => {
                    if &t.name == method_name || &m.name == method_name {
                        return Some(m);
                    }
                }
                _ => {}
            }
        }

        None
    }
}
