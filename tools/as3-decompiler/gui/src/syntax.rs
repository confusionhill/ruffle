use crate::theme::Theme;
use gpui::{Rgba, SharedString};

#[derive(Clone, Debug)]
pub struct HighlightedSpan {
    pub text: SharedString,
    pub color: Rgba,
}

#[derive(Clone, Debug)]
pub struct HighlightedLine {
    pub line_number: usize,
    pub spans: Vec<HighlightedSpan>,
}

pub struct SyntaxHighlighter;

impl SyntaxHighlighter {
    pub fn highlight_as3(source: &str, theme: &Theme) -> Vec<HighlightedLine> {
        let mut lines = Vec::new();

        for (idx, raw_line) in source.lines().enumerate() {
            let spans = Self::highlight_as3_line(raw_line, theme);
            lines.push(HighlightedLine {
                line_number: idx + 1,
                spans,
            });
        }

        if lines.is_empty() {
            lines.push(HighlightedLine {
                line_number: 1,
                spans: vec![HighlightedSpan {
                    text: "".into(),
                    color: theme.text_primary,
                }],
            });
        }

        lines
    }

    fn highlight_as3_line(line: &str, theme: &Theme) -> Vec<HighlightedSpan> {
        let mut spans = Vec::new();
        let trimmed = line.trim_start();
        let indent_len = line.len() - trimmed.len();

        if indent_len > 0 {
            spans.push(HighlightedSpan {
                text: line[..indent_len].to_string().into(),
                color: theme.text_primary,
            });
        }

        if trimmed.starts_with("//") {
            spans.push(HighlightedSpan {
                text: trimmed.to_string().into(),
                color: theme.syn_comment,
            });
            return spans;
        }

        let mut current_token = String::new();
        let mut in_string = false;
        let mut string_char = '"';

        for ch in trimmed.chars() {
            if in_string {
                current_token.push(ch);
                if ch == string_char {
                    spans.push(HighlightedSpan {
                        text: current_token.clone().into(),
                        color: theme.syn_string,
                    });
                    current_token.clear();
                    in_string = false;
                }
                continue;
            }

            if ch == '"' || ch == '\'' {
                if !current_token.is_empty() {
                    Self::push_word(&mut spans, &current_token, theme);
                    current_token.clear();
                }
                in_string = true;
                string_char = ch;
                current_token.push(ch);
                continue;
            }

            if ch.is_alphanumeric() || ch == '_' || ch == '$' {
                current_token.push(ch);
            } else {
                if !current_token.is_empty() {
                    Self::push_word(&mut spans, &current_token, theme);
                    current_token.clear();
                }
                spans.push(HighlightedSpan {
                    text: ch.to_string().into(),
                    color: theme.text_secondary,
                });
            }
        }

        if !current_token.is_empty() {
            if in_string {
                spans.push(HighlightedSpan {
                    text: current_token.into(),
                    color: theme.syn_string,
                });
            } else {
                Self::push_word(&mut spans, &current_token, theme);
            }
        }

        spans
    }

    fn push_word(spans: &mut Vec<HighlightedSpan>, word: &str, theme: &Theme) {
        let color = if Self::is_keyword(word) {
            theme.syn_keyword
        } else if Self::is_type(word) {
            theme.syn_type
        } else if word.chars().all(|c| c.is_ascii_digit()) {
            theme.syn_number
        } else {
            theme.text_primary
        };

        spans.push(HighlightedSpan {
            text: word.to_string().into(),
            color,
        });
    }

    fn is_keyword(w: &str) -> bool {
        matches!(
            w,
            "package"
                | "import"
                | "public"
                | "private"
                | "protected"
                | "internal"
                | "class"
                | "interface"
                | "extends"
                | "implements"
                | "function"
                | "var"
                | "const"
                | "static"
                | "override"
                | "final"
                | "dynamic"
                | "return"
                | "if"
                | "else"
                | "while"
                | "do"
                | "for"
                | "each"
                | "in"
                | "switch"
                | "case"
                | "default"
                | "break"
                | "continue"
                | "try"
                | "catch"
                | "finally"
                | "throw"
                | "new"
                | "this"
                | "super"
                | "is"
                | "as"
                | "typeof"
                | "delete"
                | "get"
                | "set"
                | "null"
                | "undefined"
                | "true"
                | "false"
        )
    }

    fn is_type(w: &str) -> bool {
        matches!(
            w,
            "int"
                | "uint"
                | "Number"
                | "String"
                | "Boolean"
                | "Array"
                | "Object"
                | "Vector"
                | "Class"
                | "Function"
                | "XML"
                | "XMLList"
                | "void"
        )
    }

    pub fn highlight_disassembly(source: &str, theme: &Theme) -> Vec<HighlightedLine> {
        let mut lines = Vec::new();

        for (idx, raw_line) in source.lines().enumerate() {
            let mut spans = Vec::new();
            let trimmed = raw_line.trim_start();
            let indent = raw_line.len() - trimmed.len();

            if indent > 0 {
                spans.push(HighlightedSpan {
                    text: raw_line[..indent].to_string().into(),
                    color: theme.text_primary,
                });
            }

            if trimmed.starts_with("//") {
                spans.push(HighlightedSpan {
                    text: trimmed.to_string().into(),
                    color: theme.syn_comment,
                });
            } else if trimmed.starts_with("0x") {
                // Offset
                if let Some(space_idx) = trimmed.find(' ') {
                    spans.push(HighlightedSpan {
                        text: trimmed[..space_idx].to_string().into(),
                        color: theme.syn_number,
                    });
                    let rest = &trimmed[space_idx..];
                    let rest_trimmed = rest.trim_start();
                    let spaces = rest.len() - rest_trimmed.len();
                    if spaces > 0 {
                        spans.push(HighlightedSpan {
                            text: rest[..spaces].to_string().into(),
                            color: theme.text_primary,
                        });
                    }
                    if let Some(next_space) = rest_trimmed.find(' ') {
                        // Opcode
                        spans.push(HighlightedSpan {
                            text: rest_trimmed[..next_space].to_string().into(),
                            color: theme.syn_keyword,
                        });
                        // Operands
                        spans.push(HighlightedSpan {
                            text: rest_trimmed[next_space..].to_string().into(),
                            color: theme.syn_type,
                        });
                    } else {
                        spans.push(HighlightedSpan {
                            text: rest_trimmed.to_string().into(),
                            color: theme.syn_keyword,
                        });
                    }
                } else {
                    spans.push(HighlightedSpan {
                        text: trimmed.to_string().into(),
                        color: theme.syn_number,
                    });
                }
            } else {
                spans.push(HighlightedSpan {
                    text: trimmed.to_string().into(),
                    color: theme.text_secondary,
                });
            }

            lines.push(HighlightedLine {
                line_number: idx + 1,
                spans,
            });
        }

        if lines.is_empty() {
            lines.push(HighlightedLine {
                line_number: 1,
                spans: vec![HighlightedSpan {
                    text: "".into(),
                    color: theme.text_primary,
                }],
            });
        }

        lines
    }
}

