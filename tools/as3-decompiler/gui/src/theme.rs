use gpui::{Rgba, rgb, rgba};

#[allow(dead_code)]
pub struct Theme {
    pub bg_app: Rgba,
    pub bg_sidebar: Rgba,
    pub bg_header: Rgba,
    pub bg_editor: Rgba,
    pub bg_hover: Rgba,
    pub bg_selected: Rgba,
    pub bg_button: Rgba,
    pub bg_button_hover: Rgba,
    pub bg_badge: Rgba,
    pub border: Rgba,
    pub text_primary: Rgba,
    pub text_secondary: Rgba,
    pub text_muted: Rgba,
    pub text_accent: Rgba,

    // Syntax colors
    pub syn_keyword: Rgba,
    pub syn_string: Rgba,
    pub syn_number: Rgba,
    pub syn_type: Rgba,
    pub syn_comment: Rgba,
    pub syn_function: Rgba,

    // Trait badges
    pub badge_class: Rgba,
    pub badge_interface: Rgba,
    pub badge_method: Rgba,
    pub badge_prop: Rgba,
    pub badge_accessor: Rgba,
}

impl Default for Theme {
    fn default() -> Self {
        Self {
            bg_app: rgb(0x0e0e11),
            bg_sidebar: rgb(0x131316),
            bg_header: rgb(0x18181c),
            bg_editor: rgb(0x0a0a0c),
            bg_hover: rgba(0xffffff0d),
            bg_selected: rgba(0x3b82f633),
            bg_button: rgb(0x242429),
            bg_button_hover: rgb(0x2f2f36),
            bg_badge: rgb(0x27272e),
            border: rgb(0x26262c),
            text_primary: rgb(0xf4f4f5),
            text_secondary: rgb(0xa1a1aa),
            text_muted: rgb(0x71717a),
            text_accent: rgb(0x38bdf8),

            syn_keyword: rgb(0xc084fc),   // purple
            syn_string: rgb(0x4ade80),    // green
            syn_number: rgb(0xfb923c),    // orange
            syn_type: rgb(0x38bdf8),      // cyan / sky
            syn_comment: rgb(0x6b7280),   // muted grey
            syn_function: rgb(0x60a5fa),  // blue

            badge_class: rgb(0x3b82f6),
            badge_interface: rgb(0xa855f7),
            badge_method: rgb(0x10b981),
            badge_prop: rgb(0xf59e0b),
            badge_accessor: rgb(0x06b6d4),
        }
    }
}
