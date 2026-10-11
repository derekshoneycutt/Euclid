SELECT source_namespace, animation_id, locale_tag,
edition_id, is_default FROM availability
ORDER BY source_namespace, animation_id, locale_tag, edition_id
