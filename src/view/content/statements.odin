package content

import sqlite "../../sqlite"

SEARCH_COUNT_SQL :: `SELECT count(*) FROM animation_search
WHERE animation_search MATCH ?1`
SEARCH_ROWS_SQL :: `SELECT documents.source_namespace, documents.animation_id
FROM animation_search
JOIN animation_catalog AS documents ON documents.rowid = animation_search.rowid
WHERE animation_search MATCH ?1
ORDER BY bm25(animation_search, 10.0, 6.0, 8.0, 2.0) ASC,
documents.source_namespace ASC, documents.animation_id ASC
LIMIT ?2 OFFSET ?3`
SEARCH_METADATA_SQL :: `SELECT value FROM search_metadata WHERE key = ?1`
SEARCH_SPELLFIX_SQL :: `SELECT word, distance, rank FROM search_terms
WHERE word MATCH ?1 AND top = ?2
ORDER BY distance ASC, rank ASC, word ASC LIMIT ?3`
RAW_METADATA_ROWS_SQL :: `SELECT key, value FROM content_metadata ORDER BY key`
LOCALE_ROWS_SQL :: `SELECT tag, is_default FROM locale ORDER BY tag`
MESSAGE_ROWS_SQL :: `SELECT message_key, native_message_id, developer_context
FROM ui_message ORDER BY native_message_id`
ARGUMENT_ROWS_SQL :: `SELECT message_key, ordinal, argument_name, argument_type
FROM ui_argument ORDER BY message_key, ordinal`
TRANSLATION_ROWS_SQL :: `SELECT locale_tag, message_key, template
FROM ui_translation ORDER BY locale_tag, message_key`
SUBJECT_ROWS_SQL :: `SELECT source_namespace, animation_id
FROM content_subject ORDER BY source_namespace, animation_id`
CATALOG_ROWS_SQL :: `SELECT source_namespace, animation_id, parent_animation_id,
node_kind, sibling_order, catalog_order, implementation_path
FROM catalog_node ORDER BY catalog_order`
NAME_ROWS_SQL :: `SELECT source_namespace, animation_id, locale_tag, display_name
FROM catalog_name ORDER BY source_namespace, animation_id, locale_tag`
EDITION_ROWS_SQL :: `SELECT edition_id, unique_name, text_language_tag, description
FROM edition ORDER BY edition_id`
AVAILABILITY_ROWS_SQL :: `SELECT source_namespace, animation_id, locale_tag,
edition_id, is_default FROM availability
ORDER BY source_namespace, animation_id, locale_tag, edition_id`
PROJECTION_ROWS_SQL :: `SELECT projection_id, source_namespace, animation_id,
locale_tag, edition_id, display_name, hierarchy_path, semantic_text, aliases
FROM search_projection ORDER BY projection_id`

// Persistent named statement set for schema admission and compatibility search.
Content_Statements :: struct {
    count: sqlite.Statement,
    search_rows: sqlite.Statement,
    search_metadata: sqlite.Statement,
    spellfix: sqlite.Statement,
    raw_metadata_rows: sqlite.Statement,
    locale_rows: sqlite.Statement,
    message_rows: sqlite.Statement,
    argument_rows: sqlite.Statement,
    translation_rows: sqlite.Statement,
    subject_rows: sqlite.Statement,
    catalog_rows: sqlite.Statement,
    name_rows: sqlite.Statement,
    edition_rows: sqlite.Statement,
    availability_rows: sqlite.Statement,
    projection_rows: sqlite.Statement,
}
