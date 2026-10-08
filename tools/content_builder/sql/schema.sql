PRAGMA page_size=4096;
PRAGMA journal_mode=OFF;
PRAGMA synchronous=OFF;
PRAGMA temp_store=MEMORY;
PRAGMA foreign_keys=ON;
CREATE TABLE content_metadata (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
) WITHOUT ROWID;
CREATE TABLE locale (
    tag TEXT PRIMARY KEY,
    is_default INTEGER NOT NULL CHECK (is_default IN (0, 1))
) WITHOUT ROWID;
CREATE TABLE ui_message (
    message_key TEXT PRIMARY KEY,
    native_message_id INTEGER NOT NULL UNIQUE CHECK (
        native_message_id BETWEEN 1 AND 65535),
    developer_context TEXT NOT NULL
) WITHOUT ROWID;
CREATE TABLE ui_argument (
    message_key TEXT NOT NULL REFERENCES ui_message(message_key),
    ordinal INTEGER NOT NULL CHECK (ordinal BETWEEN 0 AND 1),
    argument_name TEXT NOT NULL,
    argument_type TEXT NOT NULL CHECK (
        argument_type IN ('text', 'uint32', 'int64', 'float32_1dp')),
    PRIMARY KEY (message_key, ordinal),
    UNIQUE (message_key, argument_name)
) WITHOUT ROWID;
CREATE TABLE ui_translation (
    locale_tag TEXT NOT NULL REFERENCES locale(tag),
    message_key TEXT NOT NULL REFERENCES ui_message(message_key),
    template TEXT NOT NULL,
    PRIMARY KEY (locale_tag, message_key)
) WITHOUT ROWID;
CREATE TABLE content_subject (
    source_namespace TEXT NOT NULL,
    animation_id TEXT NOT NULL,
    PRIMARY KEY (source_namespace, animation_id)
) WITHOUT ROWID;
CREATE TABLE catalog_node (
    source_namespace TEXT NOT NULL,
    animation_id TEXT NOT NULL,
    parent_animation_id TEXT,
    node_kind INTEGER NOT NULL CHECK (node_kind IN (1, 2)),
    sibling_order INTEGER NOT NULL CHECK (sibling_order >= 0),
    catalog_order INTEGER NOT NULL CHECK (catalog_order >= 0),
    implementation_path TEXT,
    PRIMARY KEY (source_namespace, animation_id),
    FOREIGN KEY (source_namespace, animation_id)
        REFERENCES content_subject(source_namespace, animation_id),
    FOREIGN KEY (source_namespace, parent_animation_id)
        REFERENCES catalog_node(source_namespace, animation_id)
        DEFERRABLE INITIALLY DEFERRED,
    UNIQUE (source_namespace, catalog_order),
    CHECK (
        (node_kind = 2 AND implementation_path IS NULL) OR
        (node_kind = 1 AND implementation_path IS NOT NULL AND
            length(implementation_path) > 0)
    )
) WITHOUT ROWID;
CREATE UNIQUE INDEX catalog_node_root_sibling_order
ON catalog_node(source_namespace, sibling_order)
WHERE parent_animation_id IS NULL;
CREATE UNIQUE INDEX catalog_node_child_sibling_order
ON catalog_node(source_namespace, parent_animation_id, sibling_order)
WHERE parent_animation_id IS NOT NULL;
CREATE TABLE catalog_name (
    source_namespace TEXT NOT NULL,
    animation_id TEXT NOT NULL,
    locale_tag TEXT NOT NULL REFERENCES locale(tag),
    display_name TEXT NOT NULL CHECK (length(display_name) > 0),
    PRIMARY KEY (source_namespace, animation_id, locale_tag),
    FOREIGN KEY (source_namespace, animation_id)
        REFERENCES catalog_node(source_namespace, animation_id)
) WITHOUT ROWID;
CREATE TABLE edition (
    edition_id TEXT PRIMARY KEY,
    unique_name TEXT NOT NULL UNIQUE,
    text_language_tag TEXT NOT NULL,
    description TEXT NOT NULL
) WITHOUT ROWID;
CREATE TABLE availability (
    source_namespace TEXT NOT NULL,
    animation_id TEXT NOT NULL,
    locale_tag TEXT NOT NULL REFERENCES locale(tag),
    edition_id TEXT NOT NULL REFERENCES edition(edition_id),
    is_default INTEGER NOT NULL CHECK (is_default IN (0, 1)),
    PRIMARY KEY (source_namespace, animation_id, locale_tag, edition_id),
    FOREIGN KEY (source_namespace, animation_id)
        REFERENCES content_subject(source_namespace, animation_id)
) WITHOUT ROWID;
CREATE TABLE search_projection (
    projection_id INTEGER PRIMARY KEY,
    source_namespace TEXT NOT NULL,
    animation_id TEXT NOT NULL,
    locale_tag TEXT NOT NULL,
    edition_id TEXT NOT NULL,
    display_name TEXT NOT NULL CHECK (length(display_name) > 0),
    hierarchy_path TEXT NOT NULL CHECK (length(hierarchy_path) > 0),
    semantic_text TEXT NOT NULL,
    aliases TEXT NOT NULL,
    UNIQUE (source_namespace, animation_id, locale_tag, edition_id),
    FOREIGN KEY (source_namespace, animation_id)
        REFERENCES catalog_node(source_namespace, animation_id),
    FOREIGN KEY (source_namespace, animation_id, locale_tag, edition_id)
        REFERENCES availability(
            source_namespace, animation_id, locale_tag, edition_id)
);
CREATE VIRTUAL TABLE animation_search USING fts5(
    display_name,
    hierarchy_path,
    aliases,
    semantic_text,
    content='search_projection',
    content_rowid='projection_id',
    tokenize='porter unicode61 remove_diacritics 2',
    detail=full
);
CREATE VIRTUAL TABLE search_terms USING spellfix1;
CREATE VIRTUAL TABLE plain_search USING fts5(
    content,
    tokenize='unicode61 remove_diacritics 2'
);
CREATE VIRTUAL TABLE plain_search_vocabulary USING fts5vocab(plain_search, 'row');
CREATE VIEW animation_catalog AS
SELECT p.projection_id AS rowid, p.source_namespace, p.animation_id,
    n.parent_animation_id, n.node_kind, p.display_name, n.sibling_order,
    n.catalog_order, n.implementation_path, p.hierarchy_path, p.aliases,
    p.semantic_text
FROM search_projection AS p
JOIN catalog_node AS n
  ON n.source_namespace = p.source_namespace AND n.animation_id = p.animation_id;
CREATE VIEW search_metadata AS
SELECT CASE key
    WHEN 'catalog_projection_schema_version' THEN 'schema_version'
    WHEN 'content_fingerprint' THEN 'catalog_fingerprint'
    WHEN 'projection_count' THEN 'document_count'
    WHEN 'generation_identity' THEN 'index_generation'
    ELSE key END AS key,
    CASE key
    WHEN 'catalog_projection_schema_version' THEN value
    WHEN 'content_fingerprint' THEN value
    WHEN 'projection_count' THEN value
    WHEN 'generation_identity' THEN value
    ELSE value END AS value
FROM content_metadata
WHERE key IN (
    'catalog_projection_schema_version', 'content_fingerprint',
    'projection_count', 'generation_identity', 'sqlite_version',
    'tokenizer_version', 'query_contract_version');
