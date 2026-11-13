use anyhow::{Context, Result};
use swf::{FileAttributes, SymbolClassLink, Tag};

/// Injects AS3 (`DoABC` / `DoABC2`), `SymbolClass`, and `FileAttributes(IS_ACTION_SCRIPT_3)`
/// from `code_swf_bytes` into `base_swf_bytes`, preserving all visual/asset tags from `base_swf_bytes`.
pub fn patch_swf_with_code(base_swf_bytes: &[u8], code_swf_bytes: &[u8]) -> Result<Vec<u8>> {
    let base_buf = swf::decompress_swf(base_swf_bytes)
        .context("Failed to decompress base SWF")?;
    let base_swf = swf::parse_swf(&base_buf)
        .context("Failed to parse base SWF tags")?;

    let code_buf = swf::decompress_swf(code_swf_bytes)
        .context("Failed to decompress code SWF")?;
    let code_swf = swf::parse_swf(&code_buf)
        .context("Failed to parse code SWF tags")?;

    let mut header = base_swf.header.swf_header().clone();
    header.version = header.version.max(code_swf.header.version()).max(9);

    let mut code_attrs = FileAttributes::IS_ACTION_SCRIPT_3;
    let mut abc_tags: Vec<Tag<'_>> = Vec::new();
    let mut symbol_links: Vec<SymbolClassLink<'_>> = Vec::new();

    for tag in code_swf.tags {
        match tag {
            Tag::FileAttributes(attrs) => {
                code_attrs |= attrs;
            }
            Tag::DoAbc(_) | Tag::DoAbc2(_) => {
                abc_tags.push(tag);
            }
            Tag::SymbolClass(links) => {
                symbol_links.extend(links);
            }
            _ => {}
        }
    }

    let mut out_tags: Vec<Tag<'_>> = Vec::with_capacity(base_swf.tags.len() + abc_tags.len() + 2);
    let mut saw_file_attrs = false;
    let mut injected_code = false;

    for tag in base_swf.tags {
        match tag {
            Tag::FileAttributes(mut attrs) => {
                saw_file_attrs = true;
                attrs |= code_attrs;
                out_tags.push(Tag::FileAttributes(attrs));
            }
            Tag::DoAbc(_) | Tag::DoAbc2(_) => {
                // Strip old ABC tags from base SWF when patching
            }
            Tag::SymbolClass(base_links) => {
                // Keep base symbol links whose character IDs aren't overridden by code SWF
                for link in base_links {
                    if !symbol_links.iter().any(|c| c.id == link.id) {
                        symbol_links.push(link);
                    }
                }
            }
            Tag::ShowFrame => {
                if !injected_code {
                    out_tags.append(&mut abc_tags);
                    if !symbol_links.is_empty() {
                        out_tags.push(Tag::SymbolClass(std::mem::take(&mut symbol_links)));
                    }
                    injected_code = true;
                }
                out_tags.push(Tag::ShowFrame);
            }
            other => {
                out_tags.push(other);
            }
        }
    }

    if !injected_code {
        out_tags.append(&mut abc_tags);
        if !symbol_links.is_empty() {
            out_tags.push(Tag::SymbolClass(symbol_links));
        }
    }

    if !saw_file_attrs {
        out_tags.insert(0, Tag::FileAttributes(code_attrs));
    }

    let mut output = Vec::new();
    swf::write_swf(&header, &out_tags, &mut output)
        .context("Failed to write patched SWF")?;

    Ok(output)
}
