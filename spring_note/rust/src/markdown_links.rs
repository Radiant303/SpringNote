use percent_encoding::percent_decode_str;
use pulldown_cmark::{Event, Options, Parser, Tag};
use std::path::{Component, Path};

pub(crate) fn markdown_link_targets(markdown: &str) -> Vec<String> {
    Parser::new_ext(markdown, Options::all())
        .filter_map(|event| match event {
            Event::Start(Tag::Link { dest_url, .. })
            | Event::Start(Tag::Image { dest_url, .. }) => Some(dest_url.to_string()),
            _ => None,
        })
        .collect()
}

pub(crate) fn shared_image_name_from_markdown_target(target: &str) -> Option<String> {
    let target = normalized_local_target(target)?;
    let segments = target.split('/').collect::<Vec<_>>();
    if segments.len() < 3
        || segments[0] != ".."
        || !directory_name_matches(segments[1], "images")
        || segments[2..]
            .iter()
            .any(|segment| segment.is_empty() || *segment == "." || *segment == "..")
    {
        return None;
    }
    Some(segments[2..].join("/"))
}

pub(crate) fn shared_image_name_from_note_target(
    notes_root: &Path,
    note_path: &Path,
    target: &str,
) -> Option<String> {
    let target = normalized_local_target(target)?;
    let note_parent = note_path.parent()?.strip_prefix(notes_root).ok()?;
    let mut segments = note_parent
        .components()
        .map(|component| match component {
            Component::Normal(value) => value.to_str().map(str::to_owned),
            _ => None,
        })
        .collect::<Option<Vec<_>>>()?;

    for segment in target.split('/') {
        match segment {
            "" => return None,
            "." => {}
            ".." => {
                segments.pop()?;
            }
            value => segments.push(value.to_string()),
        }
    }

    if segments.len() < 2 || !directory_name_matches(&segments[0], "images") {
        return None;
    }
    Some(segments[1..].join("/"))
}

fn normalized_local_target(target: &str) -> Option<String> {
    let target = markdown_target_path_part(target)?;
    let target = strip_query_and_fragment(target);
    let lower = target.to_lowercase();
    if target.is_empty()
        || target.starts_with('/')
        || target.starts_with('\\')
        || lower.starts_with("file:")
        || target.contains("://")
        || target.contains(':')
    {
        return None;
    }

    let decoded = percent_decode_str(target)
        .decode_utf8()
        .ok()?
        .replace('\\', "/");
    (!decoded.is_empty() && !decoded.starts_with('/') && !decoded.contains('\0')).then_some(decoded)
}

fn markdown_target_path_part(target: &str) -> Option<&str> {
    let value = target.trim();
    if value.is_empty() {
        return None;
    }
    if let Some(rest) = value.strip_prefix('<') {
        return rest.find('>').map(|end| &rest[..end]);
    }
    if let Some(index) = value.find(char::is_whitespace) {
        let rest = value[index..].trim_start();
        if rest.starts_with('"') || rest.starts_with('\'') || rest.starts_with('(') {
            return Some(&value[..index]);
        }
    }
    Some(value)
}

fn strip_query_and_fragment(value: &str) -> &str {
    let query = value.find('?');
    let fragment = value.find('#');
    let cutoff = match (query, fragment) {
        (Some(left), Some(right)) => left.min(right),
        (Some(value), None) | (None, Some(value)) => value,
        (None, None) => value.len(),
    };
    &value[..cutoff]
}

fn directory_name_matches(left: &str, right: &str) -> bool {
    #[cfg(windows)]
    {
        left.eq_ignore_ascii_case(right)
    }
    #[cfg(not(windows))]
    {
        left == right
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_standard_links_but_ignores_code() {
        let markdown = concat!(
            "![inline](../images/inline.png)\n\n",
            "[chart]: ../images/reference.png\n\n",
            "![reference][chart]\n\n",
            "`![code](../images/code.png)`\n",
        );

        assert_eq!(
            markdown_link_targets(markdown),
            vec!["../images/inline.png", "../images/reference.png"]
        );
    }

    #[test]
    fn resolves_an_image_relative_to_the_note_directory() {
        let notes_root = Path::new("/data/notes");
        let note_path = notes_root.join("daily/nested/2026-07-10.md");

        assert_eq!(
            shared_image_name_from_note_target(
                notes_root,
                &note_path,
                "../../images/charts/summary%20%231.png",
            ),
            Some("charts/summary #1.png".to_string())
        );
        assert_eq!(
            shared_image_name_from_note_target(notes_root, &note_path, "../../../outside.png"),
            None
        );
    }
}
