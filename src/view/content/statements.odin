package content

import sqlite "../../sqlite"

SEARCH_COUNT_SQL :: #load("sql/search_count.sql", string)
SEARCH_ROWS_SQL :: #load("sql/search_rows.sql", string)
SEARCH_METADATA_SQL :: #load("sql/search_metadata.sql", string)
SEARCH_SPELLFIX_SQL :: #load("sql/search_spellfix.sql", string)
RAW_METADATA_ROWS_SQL :: #load("sql/raw_metadata_rows.sql", string)
LOCALE_ROWS_SQL :: #load("sql/locale_rows.sql", string)
MESSAGE_ROWS_SQL :: #load("sql/message_rows.sql", string)
ARGUMENT_ROWS_SQL :: #load("sql/argument_rows.sql", string)
TRANSLATION_ROWS_SQL :: #load("sql/translation_rows.sql", string)
SUBJECT_ROWS_SQL :: #load("sql/subject_rows.sql", string)
CATALOG_ROWS_SQL :: #load("sql/catalog_rows.sql", string)
NAME_ROWS_SQL :: #load("sql/name_rows.sql", string)
EDITION_ROWS_SQL :: #load("sql/edition_rows.sql", string)
AVAILABILITY_ROWS_SQL :: #load("sql/availability_rows.sql", string)
PROJECTION_ROWS_SQL :: #load("sql/projection_rows.sql", string)

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
