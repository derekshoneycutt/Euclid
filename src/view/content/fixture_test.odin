#+test
package content

import sqlite3 "../../../libs/sqlite3"
import contentdata "../../core/content"

import "core:fmt"
import "core:strings"

CONTENT_TEST_SCHEMA :: `
CREATE TABLE content_metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL);
INSERT INTO content_metadata SELECT CASE key
    WHEN 'catalog_fingerprint' THEN 'content_fingerprint'
    WHEN 'index_generation' THEN 'generation_identity'
    WHEN 'document_count' THEN 'projection_count'
    WHEN 'schema_version' THEN 'catalog_projection_schema_version'
    ELSE key END, value FROM search_metadata;
INSERT INTO content_metadata VALUES ('schema_version','3'),
    ('default_locale','en-US'), ('tool_compatibility','euclid-content-builder-v1'),
    ('record_count','874'),
    ('table_counts','1=6;2=1;3=81;4=10;5=81;6=139;7=138;8=138;9=3;10=139;11=138');
CREATE TABLE locale(tag TEXT PRIMARY KEY, is_default INTEGER NOT NULL);
INSERT INTO locale VALUES ('en-US',1);
CREATE TABLE ui_message(message_key TEXT PRIMARY KEY, native_message_id INTEGER,
    developer_context TEXT);
CREATE TABLE ui_argument(message_key TEXT, ordinal INTEGER,
    argument_name TEXT, argument_type TEXT);
CREATE TABLE ui_translation(locale_tag TEXT, message_key TEXT, template TEXT);
CREATE TABLE content_subject(source_namespace TEXT, animation_id TEXT);
INSERT INTO content_subject SELECT source_namespace, animation_id FROM animation_catalog;
INSERT INTO content_subject VALUES ('builtin','00000000-0000-0000-0000-000000000000');
CREATE TABLE catalog_node AS SELECT source_namespace, animation_id, parent_animation_id,
    node_kind, sibling_order, catalog_order, implementation_path FROM animation_catalog;
CREATE TABLE catalog_name AS SELECT source_namespace, animation_id,
    'en-US' AS locale_tag, display_name FROM animation_catalog;
CREATE TABLE edition(edition_id TEXT, unique_name TEXT, text_language_tag TEXT,
    description TEXT);
INSERT INTO edition VALUES ('original','Original','en-US','Original content'),
    ('heath','Heath','en-US','Edited translation'),
    ('townsend','Townsend','en-US','Edited translation');
CREATE TABLE availability(source_namespace TEXT, animation_id TEXT, locale_tag TEXT,
    edition_id TEXT, is_default INTEGER);
INSERT INTO availability SELECT source_namespace, animation_id,'en-US','original',1
    FROM content_subject;
CREATE TABLE search_projection AS SELECT rowid AS projection_id, source_namespace,
    animation_id,'en-US' AS locale_tag,'original' AS edition_id,display_name,
    hierarchy_path,semantic_text,aliases FROM animation_catalog;
UPDATE search_projection SET semantic_text='',aliases='' WHERE projection_id=138;
UPDATE animation_catalog SET semantic_text='',aliases='' WHERE rowid=138;
CREATE TRIGGER content_fixture_update AFTER UPDATE ON animation_catalog BEGIN
    UPDATE catalog_node SET animation_id=NEW.animation_id,
        parent_animation_id=NEW.parent_animation_id,node_kind=NEW.node_kind,
        sibling_order=NEW.sibling_order,catalog_order=NEW.catalog_order,
        implementation_path=NEW.implementation_path
        WHERE animation_id=OLD.animation_id;
    UPDATE catalog_name SET display_name=NEW.display_name,animation_id=NEW.animation_id
        WHERE animation_id=OLD.animation_id;
    UPDATE search_projection SET display_name=NEW.display_name,
        animation_id=NEW.animation_id WHERE projection_id=OLD.rowid;
END;
CREATE TRIGGER content_fixture_insert AFTER INSERT ON animation_catalog BEGIN
    INSERT INTO catalog_node VALUES (NEW.source_namespace,NEW.animation_id,
        NEW.parent_animation_id,NEW.node_kind,NEW.sibling_order,NEW.catalog_order,
        NEW.implementation_path);
END;
`

// Populate complete synthetic content alongside the existing deterministic search rows.
search_test_populate_content :: proc(database: ^sqlite3.Database) -> bool {
    if !search_test_execute_sql(database, cstring(CONTENT_TEST_SCHEMA)) {
        return false
    }
    messages := CONTENT_REQUIRED_MESSAGES
    for message in messages {
        signature := contentdata.content_message_signature(
            contentdata.Content_Message_Id(message.native_id))
        template := "Fixture message"
        if len(signature.name) > 0 {
            template = strings.concatenate(
                {"Fixture {", signature.name, "}"}, context.temp_allocator)
        }
        sql := fmt.tprintf(
            "INSERT INTO ui_message VALUES ('%s',%d,'Fixture context');"+
            "INSERT INTO ui_translation VALUES ('en-US','%s','%s');",
            message.key, message.native_id, message.key, template)
        if !search_test_execute_sql(
            database, strings.clone_to_cstring(sql, context.temp_allocator)) {
            return false
        }
        if len(signature.name) > 0 &&
           !search_test_populate_argument(database, message.key, signature) {
            return false
        }
    }
    return true
}

// Insert the current named wire signature so synthetic candidates obey native consumers.
search_test_populate_argument :: proc(
    database: ^sqlite3.Database, key: string,
    signature: contentdata.Content_Message_Signature) -> bool {
    kinds := [contentdata.Content_Argument_Kind]string{
        .Text = "text", .Uint32 = "uint32", .Int64 = "int64",
        .Float32_One_Decimal = "float32_1dp"}
    sql := fmt.tprintf("INSERT INTO ui_argument VALUES ('%s',0,'%s','%s');",
        key, signature.name, kinds[signature.kind])
    return search_test_execute_sql(
        database, strings.clone_to_cstring(sql, context.temp_allocator))
}
