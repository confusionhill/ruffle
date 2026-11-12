use crate::state::{AppState, ViewMode};
use crate::theme::Theme;
use as3_decompiler_core::ProjectBuilder;
use gpui::*;
use std::path::PathBuf;

pub struct DecompilerApp {
    pub state: AppState,
    pub theme: Theme,
}

impl DecompilerApp {
    pub fn new() -> Self {
        let mut app = Self {
            state: AppState::default(),
            theme: Theme::default(),
        };
        app.state.update_cache(&app.theme);
        app
    }

    pub fn load_swf_file(&mut self, path: PathBuf, cx: &mut Context<Self>) {
        self.state.status_message = format!("Decompiling {:?}...", path.file_name().unwrap_or_default());
        cx.notify();

        match std::fs::read(&path) {
            Ok(bytes) => {
                let start = std::time::Instant::now();
                match ProjectBuilder::from_swf_bytes(&bytes) {
                    Ok(project) => {
                        let duration = start.elapsed();
                        let file_name = path
                            .file_name()
                            .map(|n| n.to_string_lossy().to_string())
                            .unwrap_or_else(|| "unknown.swf".to_string());

                        // Automatically select the first class
                        let first_class_id = project
                            .packages
                            .first()
                            .and_then(|p| p.classes.first())
                            .map(|c| c.id.clone());

                        // Automatically expand all packages initially
                        for pkg in &project.packages {
                            self.state.expanded_packages.insert(pkg.name.clone());
                        }

                        let total_classes = project.metadata.total_classes;
                        self.state.current_file_name = Some(file_name);
                        self.state.current_file_path = Some(path);
                        self.state.selected_class_id = first_class_id;
                        self.state.selected_method_name = None;
                        self.state.status_message = format!(
                            "Decompiled {} classes in {:.2}ms",
                            total_classes,
                            duration.as_secs_f64() * 1000.0
                        );
                        self.state.project = Some(project);
                        self.state.update_cache(&self.theme);
                    }
                    Err(e) => {
                        self.state.status_message = format!("Error decompiling SWF: {}", e);
                    }
                }
            }
            Err(e) => {
                self.state.status_message = format!("Failed to read file: {}", e);
            }
        }
        cx.notify();
    }

    fn copy_current_code(&mut self, cx: &mut Context<Self>) {
        let code = match self.state.view_mode {
            ViewMode::DecompiledAs3 => self
                .state
                .selected_class()
                .map(|c| c.as3_source.clone())
                .unwrap_or_default(),
            ViewMode::Disassembly => self
                .state
                .selected_class()
                .map(|c| c.bytecode_text.clone())
                .unwrap_or_default(),
            ViewMode::Split => self
                .state
                .selected_class()
                .map(|c| c.as3_source.clone())
                .unwrap_or_default(),
        };

        if !code.is_empty() {
            cx.write_to_clipboard(ClipboardItem::new_string(code));
            self.state.status_message = "Copied code to clipboard!".to_string();
            cx.notify();
        }
    }

    fn export_current_class(&mut self, cx: &mut Context<Self>) {
        let Some(class) = self.state.selected_class() else {
            return;
        };

        let default_name = format!("{}.as", class.name);
        if let Some(dest) = rfd::FileDialog::new()
            .set_file_name(&default_name)
            .add_filter("ActionScript File", &["as"])
            .save_file()
        {
            if let Err(e) = std::fs::write(&dest, &class.as3_source) {
                self.state.status_message = format!("Failed to save: {}", e);
            } else {
                self.state.status_message = format!("Saved to {:?}", dest.file_name().unwrap_or_default());
            }
            cx.notify();
        }
    }

    fn export_all_as_zip(&mut self, cx: &mut Context<Self>) {
        let Some(project) = &self.state.project else {
            self.state.status_message = "No SWF loaded to export.".to_string();
            cx.notify();
            return;
        };

        let default_zip = if let Some(name) = &self.state.current_file_name {
            if let Some(base) = name.strip_suffix(".swf") {
                format!("{}_src.zip", base)
            } else {
                format!("{}.zip", name)
            }
        } else {
            "decompiled_src.zip".to_string()
        };

        if let Some(dest) = rfd::FileDialog::new()
            .set_file_name(&default_zip)
            .add_filter("ZIP Archive", &["zip"])
            .save_file()
        {
            match std::fs::File::create(&dest) {
                Ok(file) => match project.export_to_zip(file) {
                    Ok(count) => {
                        self.state.status_message = format!(
                            "Exported all {} classes to {:?}",
                            count,
                            dest.file_name().unwrap_or_default()
                        );
                    }
                    Err(e) => {
                        self.state.status_message = format!("Export error: {}", e);
                    }
                },
                Err(e) => {
                    self.state.status_message = format!("Failed to create file: {}", e);
                }
            }
            cx.notify();
        }
    }

    fn render_toolbar(&self, cx: &mut Context<Self>) -> impl IntoElement {
        let file_name = self.state.current_file_name.as_deref().unwrap_or("No SWF loaded");
        let meta_info = if let Some(p) = &self.state.project {
            format!(
                "Flash v{} • {}x{} @ {}fps • {} classes",
                p.metadata.swf_version,
                p.metadata.width as i32,
                p.metadata.height as i32,
                p.metadata.frame_rate as i32,
                p.metadata.total_classes
            )
        } else {
            "Select an ActionScript 3 SWF to decompile".to_string()
        };

        div()
            .h(px(52.0))
            .w_full()
            .flex()
            .flex_row()
            .items_center()
            .justify_between()
            // Placed 84px left padding so macOS traffic lights (at x=12) never collide with content!
            .pl(px(84.0))
            .pr_4()
            .bg(self.theme.bg_header)
            .border_b_1()
            .border_color(self.theme.border)
            // Left: Logo, Open Button, File Info
            .child(
                div()
                    .flex()
                    .flex_row()
                    .items_center()
                    .gap_3()
                    .child(
                        div()
                            .text_sm()
                            .font_weight(FontWeight::BOLD)
                            .text_color(self.theme.text_accent)
                            .child("⚡ AS3 WIZARD")
                    )
                    .child(
                        div()
                            .px_3()
                            .py_1()
                            .bg(self.theme.bg_button)
                            .hover(|s| s.bg(self.theme.bg_button_hover).cursor_pointer())
                            .rounded_md()
                            .border_1()
                            .border_color(self.theme.border)
                            .text_xs()
                            .font_weight(FontWeight::SEMIBOLD)
                            .text_color(self.theme.text_primary)
                            .child("📂 Open SWF")
                            .on_mouse_down(MouseButton::Left, cx.listener(|this, _event, _window, cx| {
                                if let Some(path) = rfd::FileDialog::new()
                                    .add_filter("Flash SWF", &["swf"])
                                    .set_title("Open SWF file")
                                    .pick_file()
                                {
                                    this.load_swf_file(path, cx);
                                }
                            }))
                    )
                    .child(
                        div()
                            .flex()
                            .flex_col()
                            .child(
                                div()
                                    .text_xs()
                                    .font_weight(FontWeight::SEMIBOLD)
                                    .text_color(self.theme.text_primary)
                                    .child(file_name.to_string())
                            )
                            .child(
                                div()
                                    .text_xs()
                                    .text_color(self.theme.text_muted)
                                    .child(meta_info)
                            )
                    )
            )
            // Right: View Mode Toggle & Actions (including Export All ZIP)
            .child(
                div()
                    .flex()
                    .flex_row()
                    .items_center()
                    .gap_2()
                    // View Mode Buttons
                    .child(
                        div()
                            .flex()
                            .flex_row()
                            .bg(self.theme.bg_editor)
                            .border_1()
                            .border_color(self.theme.border)
                            .rounded_md()
                            .p_0p5()
                            .child(self.render_mode_tab("Decompiled AS3", ViewMode::DecompiledAs3, cx))
                            .child(self.render_mode_tab("Bytecode (Disassembly)", ViewMode::Disassembly, cx))
                            .child(self.render_mode_tab("Split View", ViewMode::Split, cx))
                    )
                    // Copy button
                    .child(
                        div()
                            .px_3()
                            .py_1()
                            .bg(self.theme.bg_button)
                            .hover(|s| s.bg(self.theme.bg_button_hover).cursor_pointer())
                            .rounded_md()
                            .border_1()
                            .border_color(self.theme.border)
                            .text_xs()
                            .text_color(self.theme.text_primary)
                            .child("📋 Copy")
                            .on_mouse_down(MouseButton::Left, cx.listener(|this, _event, _window, cx| {
                                this.copy_current_code(cx);
                            }))
                    )
                    // Export .as button
                    .child(
                        div()
                            .px_3()
                            .py_1()
                            .bg(self.theme.bg_button)
                            .hover(|s| s.bg(self.theme.bg_button_hover).cursor_pointer())
                            .rounded_md()
                            .border_1()
                            .border_color(self.theme.border)
                            .text_xs()
                            .text_color(self.theme.text_primary)
                            .child("💾 Export .as")
                            .on_mouse_down(MouseButton::Left, cx.listener(|this, _event, _window, cx| {
                                this.export_current_class(cx);
                            }))
                    )
                    // Export All as ZIP button
                    .child(
                        div()
                            .px_3()
                            .py_1()
                            .bg(self.theme.bg_selected)
                            .hover(|s| s.bg(self.theme.bg_button_hover).cursor_pointer())
                            .rounded_md()
                            .border_1()
                            .border_color(self.theme.text_accent)
                            .text_xs()
                            .font_weight(FontWeight::SEMIBOLD)
                            .text_color(self.theme.text_accent)
                            .child("📦 Export All (ZIP)")
                            .on_mouse_down(MouseButton::Left, cx.listener(|this, _event, _window, cx| {
                                this.export_all_as_zip(cx);
                            }))
                    )
            )
    }

    fn render_mode_tab(&self, label: &'static str, mode: ViewMode, cx: &mut Context<Self>) -> impl IntoElement {
        let is_active = self.state.view_mode == mode;
        let bg_color = if is_active { self.theme.bg_selected } else { rgba(0x00000000) };
        let text_color = if is_active { self.theme.text_accent } else { self.theme.text_secondary };

        div()
            .px_2p5()
            .py_0p5()
            .rounded_sm()
            .bg(bg_color)
            .hover(|s| s.bg(self.theme.bg_hover).cursor_pointer())
            .text_xs()
            .font_weight(FontWeight::SEMIBOLD)
            .text_color(text_color)
            .child(label)
            .on_mouse_down(MouseButton::Left, cx.listener(move |this, _event, _window, cx| {
                this.state.view_mode = mode;
                cx.notify();
            }))
    }

    fn render_sidebar(&self, cx: &mut Context<Self>) -> impl IntoElement {
        let mut package_views = Vec::new();

        if let Some(project) = &self.state.project {
            for pkg in &project.packages {
                let pkg_name = if pkg.name.is_empty() {
                    "(default package)"
                } else {
                    &pkg.name
                };

                let is_pkg_expanded = self.state.expanded_packages.contains(&pkg.name);
                let pkg_key = pkg.name.clone();

                let mut class_items = Vec::new();
                if is_pkg_expanded {
                    for class in &pkg.classes {
                        let is_class_selected = self.state.selected_class_id.as_deref() == Some(&class.id)
                            && self.state.selected_method_name.is_none();
                        let is_class_expanded = self.state.expanded_classes.contains(&class.id);
                        let class_id_for_expand = class.id.clone();
                        let class_id_for_select = class.id.clone();
                        let badge_letter = if class.is_interface { "I" } else { "C" };
                        let badge_color = if class.is_interface {
                            self.theme.badge_interface
                        } else {
                            self.theme.badge_class
                        };

                        let item_bg = if is_class_selected {
                            self.theme.bg_selected
                        } else {
                            rgba(0x00000000)
                        };

                        // Render member items if class is expanded
                        let mut member_items = Vec::new();
                        if is_class_expanded {
                            if let Some(ctor) = &class.constructor {
                                let is_m_sel = self.state.selected_class_id.as_deref() == Some(&class.id)
                                    && self.state.selected_method_name.as_deref() == Some(&ctor.name);
                                let ctor_name = ctor.name.clone();
                                let cid = class.id.clone();
                                member_items.push(
                                    div()
                                        .flex()
                                        .flex_row()
                                        .items_center()
                                        .pl_6()
                                        .pr_2()
                                        .py_0p5()
                                        .rounded_sm()
                                        .bg(if is_m_sel { self.theme.bg_selected } else { rgba(0x00000000) })
                                        .hover(|s| s.bg(self.theme.bg_hover).cursor_pointer())
                                        .gap_1p5()
                                        .child(
                                            div()
                                                .w(px(13.0))
                                                .h(px(13.0))
                                                .flex()
                                                .items_center()
                                                .justify_center()
                                                .rounded_xs()
                                                .bg(self.theme.badge_class)
                                                .text_xs()
                                                .font_weight(FontWeight::BOLD)
                                                .text_color(rgb(0xffffff))
                                                .child("c")
                                        )
                                        .child(
                                            div()
                                                .text_xs()
                                                .text_color(if is_m_sel { self.theme.text_accent } else { self.theme.text_secondary })
                                                .child(format!("{}()", ctor.name))
                                        )
                                        .on_mouse_down(MouseButton::Left, cx.listener(move |this, _event, _window, cx| {
                                            this.state.selected_class_id = Some(cid.clone());
                                            this.state.selected_method_name = Some(ctor_name.clone());
                                            this.state.update_cache(&this.theme);
                                            cx.notify();
                                        }))
                                );
                            }

                            for trait_info in &class.instance_traits {
                                let (badge_l, badge_c) = match &trait_info.kind {
                                    as3_decompiler_core::TraitKindInfo::Method(_) => ("m", self.theme.badge_method),
                                    as3_decompiler_core::TraitKindInfo::Getter(_) => ("g", self.theme.badge_accessor),
                                    as3_decompiler_core::TraitKindInfo::Setter(_) => ("s", self.theme.badge_accessor),
                                    as3_decompiler_core::TraitKindInfo::Slot { .. } => ("v", self.theme.badge_prop),
                                    as3_decompiler_core::TraitKindInfo::Const { .. } => ("k", self.theme.badge_prop),
                                    as3_decompiler_core::TraitKindInfo::Function(_) => ("f", self.theme.badge_method),
                                };

                                let tname = trait_info.name.clone();
                                let cid = class.id.clone();
                                let is_m_sel = self.state.selected_class_id.as_deref() == Some(&class.id)
                                    && self.state.selected_method_name.as_deref() == Some(&trait_info.name);

                                member_items.push(
                                    div()
                                        .flex()
                                        .flex_row()
                                        .items_center()
                                        .pl_6()
                                        .pr_2()
                                        .py_0p5()
                                        .rounded_sm()
                                        .bg(if is_m_sel { self.theme.bg_selected } else { rgba(0x00000000) })
                                        .hover(|s| s.bg(self.theme.bg_hover).cursor_pointer())
                                        .gap_1p5()
                                        .child(
                                            div()
                                                .w(px(13.0))
                                                .h(px(13.0))
                                                .flex()
                                                .items_center()
                                                .justify_center()
                                                .rounded_xs()
                                                .bg(badge_c)
                                                .text_xs()
                                                .font_weight(FontWeight::BOLD)
                                                .text_color(rgb(0xffffff))
                                                .child(badge_l)
                                        )
                                        .child(
                                            div()
                                                .text_xs()
                                                .text_color(if is_m_sel { self.theme.text_accent } else { self.theme.text_secondary })
                                                .child(trait_info.name.clone())
                                        )
                                        .on_mouse_down(MouseButton::Left, cx.listener(move |this, _event, _window, cx| {
                                            this.state.selected_class_id = Some(cid.clone());
                                            this.state.selected_method_name = Some(tname.clone());
                                            this.state.update_cache(&this.theme);
                                            cx.notify();
                                        }))
                                );
                            }
                        }

                        class_items.push(
                            div()
                                .flex()
                                .flex_col()
                                .child(
                                    div()
                                        .flex()
                                        .flex_row()
                                        .items_center()
                                        .justify_between()
                                        .px_2()
                                        .py_1()
                                        .rounded_sm()
                                        .bg(item_bg)
                                        .hover(|s| s.bg(self.theme.bg_hover).cursor_pointer())
                                        .child(
                                            div()
                                                .flex()
                                                .flex_row()
                                                .items_center()
                                                .gap_1p5()
                                                .child(
                                                    div()
                                                        .text_xs()
                                                        .text_color(self.theme.text_muted)
                                                        .child(if is_class_expanded { "▼" } else { "▶" })
                                                        .on_mouse_down(MouseButton::Left, cx.listener(move |this, _e, _w, cx| {
                                                            if this.state.expanded_classes.contains(&class_id_for_expand) {
                                                                this.state.expanded_classes.remove(&class_id_for_expand);
                                                            } else {
                                                                this.state.expanded_classes.insert(class_id_for_expand.clone());
                                                            }
                                                            cx.notify();
                                                        }))
                                                )
                                                .child(
                                                    div()
                                                        .w(px(16.0))
                                                        .h(px(16.0))
                                                        .flex()
                                                        .items_center()
                                                        .justify_center()
                                                        .rounded_xs()
                                                        .bg(badge_color)
                                                        .text_xs()
                                                        .font_weight(FontWeight::BOLD)
                                                        .text_color(rgb(0xffffff))
                                                        .child(badge_letter)
                                                )
                                                .child(
                                                    div()
                                                        .text_xs()
                                                        .text_color(if is_class_selected {
                                                            self.theme.text_primary
                                                        } else {
                                                            self.theme.text_secondary
                                                        })
                                                        .child(class.name.clone())
                                                )
                                        )
                                        .child(
                                            div()
                                                .text_xs()
                                                .text_color(self.theme.text_muted)
                                                .child(format!("{}", class.instance_traits.len() + class.static_traits.len()))
                                        )
                                        .on_mouse_down(MouseButton::Left, cx.listener(move |this, _event, _window, cx| {
                                            this.state.selected_class_id = Some(class_id_for_select.clone());
                                            this.state.selected_method_name = None;
                                            this.state.update_cache(&this.theme);
                                            cx.notify();
                                        }))
                                )
                                .children(member_items)
                        );
                    }
                }

                package_views.push(
                    div()
                        .flex()
                        .flex_col()
                        .child(
                            div()
                                .flex()
                                .flex_row()
                                .items_center()
                                .gap_1p5()
                                .px_2()
                                .py_1()
                                .hover(|s| s.bg(self.theme.bg_hover).cursor_pointer())
                                .child(
                                    div()
                                        .text_xs()
                                        .text_color(self.theme.text_muted)
                                        .child(if is_pkg_expanded { "▼" } else { "▶" })
                                )
                                .child(
                                    div()
                                        .text_xs()
                                        .font_weight(FontWeight::SEMIBOLD)
                                        .text_color(self.theme.text_secondary)
                                        .child(pkg_name.to_string())
                                )
                                .on_mouse_down(MouseButton::Left, cx.listener(move |this, _event, _window, cx| {
                                    if this.state.expanded_packages.contains(&pkg_key) {
                                        this.state.expanded_packages.remove(&pkg_key);
                                    } else {
                                        this.state.expanded_packages.insert(pkg_key.clone());
                                    }
                                    cx.notify();
                                }))
                        )
                        .children(class_items)
                );
            }
        }

        div()
            .w(px(280.0))
            .h_full()
            .flex()
            .flex_col()
            .bg(self.theme.bg_sidebar)
            .border_r_1()
            .border_color(self.theme.border)
            .child(
                div()
                    .px_3()
                    .py_2()
                    .border_b_1()
                    .border_color(self.theme.border)
                    .child(
                        div()
                            .text_xs()
                            .font_weight(FontWeight::BOLD)
                            .text_color(self.theme.text_muted)
                            .child("PACKAGES & CLASSES")
                    )
            )
            .child(
                div()
                    .id("sidebar_scroll")
                    .flex_1()
                    .overflow_scroll()
                    .p_1()
                    .children(package_views)
            )
    }

    fn render_code_panel(&self, title: &str, is_bytecode: bool, cx: &mut Context<Self>) -> impl IntoElement {
        let line_count = if is_bytecode {
            self.state.cached_disasm_lines.len()
        } else {
            self.state.cached_as3_lines.len()
        };

        div()
            .flex_1()
            .h_full()
            .flex()
            .flex_col()
            .bg(self.theme.bg_editor)
            // Code header
            .child(
                div()
                    .h(px(32.0))
                    .px_4()
                    .flex()
                    .items_center()
                    .bg(self.theme.bg_app)
                    .border_b_1()
                    .border_color(self.theme.border)
                    .child(
                        div()
                            .text_xs()
                            .font_weight(FontWeight::SEMIBOLD)
                            .text_color(self.theme.text_secondary)
                            .child(title.to_string())
                    )
            )
            // High-performance virtualized list: renders only the visible lines on screen!
            .child(
                div()
                    .flex_1()
                    .h_full()
                    .p_2()
                    .font_family("Courier New")
                    .child(
                        uniform_list(
                            if is_bytecode { "code_list_bc" } else { "code_list_as3" },
                            line_count,
                            cx.processor(move |this, range: std::ops::Range<usize>, _window, _cx| {
                                let lines = if is_bytecode {
                                    &this.state.cached_disasm_lines
                                } else {
                                    &this.state.cached_as3_lines
                                };

                                let mut items = Vec::with_capacity(range.len());
                                for ix in range {
                                    if let Some(line) = lines.get(ix) {
                                        items.push(
                                            div()
                                                .id(ix)
                                                .flex()
                                                .flex_row()
                                                .items_center()
                                                .h(px(20.0))
                                                .child(
                                                    div()
                                                        .w(px(45.0))
                                                        .text_right()
                                                        .pr_3()
                                                        .text_xs()
                                                        .text_color(this.theme.text_muted)
                                                        .child(format!("{}", line.line_number))
                                                )
                                                .child(
                                                    div()
                                                        .flex()
                                                        .flex_row()
                                                        .items_center()
                                                        .text_xs()
                                                        .children(line.spans.iter().map(|span| {
                                                            div()
                                                                .text_color(span.color)
                                                                .child(span.text.clone())
                                                        }))
                                                )
                                        );
                                    }
                                }
                                items
                            }),
                        )
                        .h_full()
                    )
            )
    }

    fn render_content_area(&self, cx: &mut Context<Self>) -> impl IntoElement {
        let class = self.state.selected_class();
        let method = self.state.selected_method();

        let (_class_name, as3_title, bc_title) = if let Some(m) = method {
            let cname = class.map(|c| c.name.as_str()).unwrap_or("");
            let mtitle_as3 = format!("{} > {}() (ActionScript 3)", cname, m.name);
            let mtitle_bc = format!("{} > {}() (AVM2 Bytecode Disassembly)", cname, m.name);
            (cname, mtitle_as3, mtitle_bc)
        } else if let Some(c) = class {
            let ctitle_as3 = format!("{}.as (ActionScript 3)", c.name);
            let ctitle_bc = format!("{}.as (AVM2 Bytecode Disassembly)", c.name);
            (c.name.as_str(), ctitle_as3, ctitle_bc)
        } else {
            (
                "No selection",
                "No class selected".to_string(),
                "No class selected".to_string(),
            )
        };

        match self.state.view_mode {
            ViewMode::DecompiledAs3 => div()
                .flex_1()
                .h_full()
                .child(self.render_code_panel(&as3_title, false, cx)),
            ViewMode::Disassembly => div()
                .flex_1()
                .h_full()
                .child(self.render_code_panel(&bc_title, true, cx)),
            ViewMode::Split => div()
                .flex_1()
                .h_full()
                .flex()
                .flex_row()
                .child(self.render_code_panel(&as3_title, false, cx))
                .child(
                    div()
                        .w(px(1.0))
                        .h_full()
                        .bg(self.theme.border)
                )
                .child(self.render_code_panel(&bc_title, true, cx)),
        }
    }

    fn render_status_bar(&self) -> impl IntoElement {
        div()
            .h(px(24.0))
            .w_full()
            .flex()
            .flex_row()
            .items_center()
            .justify_between()
            .px_3()
            .bg(self.theme.bg_header)
            .border_t_1()
            .border_color(self.theme.border)
            .child(
                div()
                    .text_xs()
                    .text_color(self.theme.text_secondary)
                    .child(self.state.status_message.clone())
            )
            .child(
                div()
                    .flex()
                    .gap_3()
                    .child(
                        div()
                            .text_xs()
                            .text_color(self.theme.text_muted)
                            .child("Powered by Ruffle AVM2 & GPUI")
                    )
            )
    }
}

impl Render for DecompilerApp {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        div()
            .size_full()
            .flex()
            .flex_col()
            .bg(self.theme.bg_app)
            .text_color(self.theme.text_primary)
            // Top Toolbar
            .child(self.render_toolbar(cx))
            // Middle: Workspace (Sidebar + Code Panel)
            .child(
                div()
                    .flex_1()
                    .flex()
                    .flex_row()
                    .overflow_hidden()
                    .child(self.render_sidebar(cx))
                    .child(self.render_content_area(cx))
            )
            // Bottom Status Bar
            .child(self.render_status_bar())
    }
}
