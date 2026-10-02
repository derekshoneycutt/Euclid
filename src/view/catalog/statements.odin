package catalog

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
CATALOG_ROWS_SQL :: `SELECT source_namespace, animation_id,
parent_animation_id, node_kind, display_name, sibling_order,
catalog_order, implementation_path
FROM animation_catalog ORDER BY catalog_order ASC`

// Persistent statements required for one admitted catalogue database.
Catalog_Statements :: struct {
    count: sqlite.Statement,
    search_rows: sqlite.Statement,
    catalog_rows: sqlite.Statement,
    metadata: sqlite.Statement,
    spellfix: sqlite.Statement,
}