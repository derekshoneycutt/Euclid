#+test
package contenttest

import sqlite3 "../../../../libs/sqlite3"

import "core:c"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

SEARCH_TEST_FINGERPRINT ::
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
SEARCH_TEST_CANDIDATE_FINGERPRINT ::
    "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

SEARCH_TEST_SCHEMA :: `
CREATE TABLE search_metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID;
PRAGMA foreign_keys=ON;
CREATE TABLE animation_catalog(
    rowid INTEGER PRIMARY KEY,
    source_namespace TEXT NOT NULL,
    animation_id TEXT NOT NULL,
    parent_animation_id TEXT,
    node_kind INTEGER NOT NULL,
    display_name TEXT NOT NULL,
    sibling_order INTEGER NOT NULL,
    catalog_order INTEGER NOT NULL,
    implementation_path TEXT,
    hierarchy_path TEXT NOT NULL,
    aliases TEXT NOT NULL,
    semantic_text TEXT NOT NULL,
    UNIQUE(source_namespace, animation_id),
    UNIQUE(source_namespace, catalog_order),
    FOREIGN KEY(source_namespace, parent_animation_id)
        REFERENCES animation_catalog(source_namespace, animation_id)
        DEFERRABLE INITIALLY DEFERRED);
CREATE UNIQUE INDEX animation_catalog_root_order
ON animation_catalog(source_namespace, sibling_order)
WHERE parent_animation_id IS NULL;
CREATE UNIQUE INDEX animation_catalog_child_order
ON animation_catalog(source_namespace, parent_animation_id, sibling_order)
WHERE parent_animation_id IS NOT NULL;
CREATE VIRTUAL TABLE animation_search USING fts5(
    display_name, hierarchy_path, aliases, semantic_text,
    content='animation_catalog', content_rowid='rowid',
    tokenize='porter unicode61 remove_diacritics 2', detail=full);
CREATE VIRTUAL TABLE search_terms USING spellfix1;
INSERT INTO animation_catalog VALUES
    (1, 'builtin', '00000000-0000-0000-0000-000000000001', NULL, 1,
     'Perpendicular', 0, 0, 'synthetic/1.jl',
        'Elements Book I Perpendicular', 'normal line right angle',
     'A line forming equal adjacent right angles is perpendicular.'),
    (2, 'builtin', '00000000-0000-0000-0000-000000000002', NULL, 1,
     'Circle', 1, 1, 'synthetic/2.jl',
        'Elements Circle', 'round circumference',
     'A circle has points equally distant from its center.'),
    (3, 'builtin', '00000000-0000-0000-0000-000000000003', NULL, 1,
     'Line Construction', 2, 2, 'synthetic/3.jl',
        'Elements Book I Line Construction', 'straight line',
     'Construct a straight line through two points.');
WITH RECURSIVE sequence(value) AS (
    VALUES(4) UNION ALL SELECT value + 1 FROM sequence WHERE value < 138)
INSERT INTO animation_catalog
SELECT value, 'builtin', printf('00000000-0000-0000-0000-%012d', value), NULL, 1,
       printf('Synthetic %03d', value), value - 1, value - 1,
       printf('synthetic/%d.jl', value),
    'Synthetic Scale', 'generated fixture',
       'Synthetic searchable geometry document'
FROM sequence;
UPDATE animation_catalog SET node_kind=2, display_name='Terminal',
    implementation_path=NULL WHERE rowid=138;
INSERT INTO animation_search(animation_search) VALUES('rebuild');
INSERT INTO search_terms(word, rank) VALUES
    ('perpendicular', 1), ('circle', 2), ('construction', 3), ('line', 4);
INSERT INTO search_metadata VALUES
    ('schema_version', '2'),
    ('sqlite_version', '3.53.4'),
    ('catalog_fingerprint', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
    ('document_count', '138'),
    ('tokenizer_version', 'porter-unicode61-v1'),
    ('query_contract_version', '1'),
    ('index_generation', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
`

// Owned paths and creation outcome for one temporary search database.
Search_Test_Database :: struct {
    directory: string,
    path: string,
    ok: bool,
}

// Execute one fixed fixture SQL program and release any SQLite diagnostic.
search_test_execute_sql :: proc(database: ^sqlite3.Database, sql: cstring) -> bool {
    message: cstring
    status := sqlite3.sqlite3_exec(database, sql, nil, nil, &message)
    if message != nil {
       sqlite3.sqlite3_free(rawptr(message))
    }
    return status == .Ok
}

// Create one isolated immutable-search database fixture under the OS temp directory.
search_test_database_create :: proc(
    suffix: string) -> Search_Test_Database {
    result: Search_Test_Database
    temp, temp_error := os.temp_directory(context.temp_allocator)
    if temp_error != nil {
       return result
    }
    directory_name := fmt.tprintf("euclid-search-worker-%s", suffix)
    result.directory, _ = filepath.join(
        []string{temp, directory_name}, context.allocator)
    if len(result.directory) == 0 {
       return result
    }
    _ = os.remove_all(result.directory)
    if os.make_directory_all(result.directory) != nil {
       return result
    }
    result.path, _ = filepath.join(
        []string{result.directory, "search.sqlite3"}, context.allocator)
    if len(result.path) == 0 {
       return result
    }
    database: ^sqlite3.Database
    flags := c.int(sqlite3.Open_Flag.Readwrite) | c.int(sqlite3.Open_Flag.Create)
    encoded_path := strings.clone_to_cstring(result.path, context.temp_allocator)
    if sqlite3.sqlite3_open_v2(encoded_path, &database, flags, nil) != .Ok {
        return result
    }
    registered := sqlite3.euclid_sqlite_register_spellfix(database) == .Ok
    populated := registered && search_test_execute_sql(database, SEARCH_TEST_SCHEMA) &&
        search_test_populate_content(database)
    closed := sqlite3.sqlite3_close(database) == .Ok
    result.ok = populated && closed
    return result
}

// Give one fixture a distinct admitted generation and visible catalogue value.
search_test_make_candidate :: proc(
    t: ^testing.T, fixture: ^Search_Test_Database) {
    database: ^sqlite3.Database
    encoded_path := strings.clone_to_cstring(fixture.path, context.temp_allocator)
    opened := sqlite3.sqlite3_open_v2(encoded_path, &database,
        c.int(sqlite3.Open_Flag.Readwrite), nil)
    testing.expect_value(t, opened, sqlite3.Result.Ok)
    if opened != .Ok {
        return
    }
    mutation := "UPDATE search_metadata SET value='" +
        SEARCH_TEST_CANDIDATE_FINGERPRINT + "' WHERE key IN " +
        "('catalog_fingerprint', 'index_generation');" +
        "UPDATE content_metadata SET value='" +
        SEARCH_TEST_CANDIDATE_FINGERPRINT + "' WHERE key IN " +
        "('content_fingerprint', 'generation_identity');" +
        "UPDATE ui_translation SET template='Candidate message' "+
        "WHERE message_key NOT IN (SELECT message_key FROM ui_argument);"+
        "UPDATE edition SET unique_name='Candidate Original' WHERE edition_id='original';"+
        "UPDATE animation_catalog SET display_name='Candidate Perpendicular' " +
        "WHERE rowid=1;"
    encoded := strings.clone_to_cstring(mutation, context.temp_allocator)
    testing.expect(t, search_test_execute_sql(database, encoded))
    testing.expect_value(t, sqlite3.sqlite3_close(database), sqlite3.Result.Ok)
}

// Apply one mutation to a closed fixture before immutable admission.
content_test_mutate :: proc(fixture: ^Search_Test_Database, sql: string) -> bool {
    database: ^sqlite3.Database
    path := strings.clone_to_cstring(fixture.path, context.temp_allocator)
    if sqlite3.sqlite3_open_v2(
        path, &database, c.int(sqlite3.Open_Flag.Readwrite), nil) != .Ok {
        return false
    }
    changed := search_test_execute_sql(
        database, strings.clone_to_cstring(sql, context.temp_allocator))
    counted := changed && content_test_refresh_counts(database)
    return sqlite3.sqlite3_close(database) == .Ok && counted
}

// Keep fixture metadata honest so invalid data, rather than stale counts, rejects admission.
content_test_refresh_counts :: proc(database: ^sqlite3.Database) -> bool {
    sql := `UPDATE content_metadata SET value='1=6;2='||(SELECT count(*) FROM locale)||
        ';3='||(SELECT count(*) FROM ui_message)||';4='||(SELECT count(*) FROM ui_argument)||
        ';5='||(SELECT count(*) FROM ui_translation)||';6='||(SELECT count(*) FROM content_subject)||
        ';7='||(SELECT count(*) FROM catalog_node)||';8='||(SELECT count(*) FROM catalog_name)||
        ';9='||(SELECT count(*) FROM edition)||';10='||(SELECT count(*) FROM availability)||
        ';11='||(SELECT count(*) FROM search_projection) WHERE key='table_counts';
        UPDATE content_metadata SET value=CAST(6+(SELECT count(*) FROM locale)+
        (SELECT count(*) FROM ui_message)+(SELECT count(*) FROM ui_argument)+
        (SELECT count(*) FROM ui_translation)+(SELECT count(*) FROM content_subject)+
        (SELECT count(*) FROM catalog_node)+(SELECT count(*) FROM catalog_name)+
        (SELECT count(*) FROM edition)+(SELECT count(*) FROM availability)+
        (SELECT count(*) FROM search_projection) AS TEXT) WHERE key='record_count';`
    return search_test_execute_sql(
        database, strings.clone_to_cstring(sql, context.temp_allocator))
}

