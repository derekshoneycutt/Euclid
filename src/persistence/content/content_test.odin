#+test
package contentstore

import contentfixture "testsupport"

import contentdata "../../core/content"
import sqlite3 "../../../libs/sqlite3"
import sqlite "../../sqlite"
import files "../../files"

import "core:os"
import "core:testing"

// The packaged authored dataset, not just a synthetic fixture, preserves every baseline byte.
@(test)
content_packaged_messages_match_native_output_baselines :: proc(t: ^testing.T) {
    config: files.Asset_Root_Config = {
        asset_root_override = "bin",
    }
    asset, resolved := files.packaged_content_asset_with_config(
        &config, context.allocator)
    testing.expect(t, resolved)
    if !resolved {
        return
    }
    defer delete(asset.database_path, context.allocator)
    defer delete(asset.corpus_fingerprint, context.allocator)
    generation := new(contentdata.Content_Generation, context.allocator)
    defer free(generation, context.allocator)
    testing.expect_value(t, contentdata.content_generation_init(generation),
        contentdata.Content_Generation_Status.Ok)
    defer contentdata.content_generation_destroy(generation)
    database: Content_Database
    testing.expect(t, !content_database_ready(&database))
    opened := content_database_open(
        &database, asset.database_path, asset.corpus_fingerprint, generation)
    testing.expect(t, opened)
    if !opened {
        return
    }
    testing.expect(t, content_database_ready(&database))
    defer _ = content_database_close(&database)
    templates := contentdata.CONTENT_MESSAGE_TEST_TEMPLATES
    for id in contentdata.Content_Message_Id {
        if id == .Invalid {
            continue
        }
        view, status := contentdata.content_message_lookup(generation, id)
        testing.expect_value(t, status, contentdata.Content_Message_Status.Ok)
        testing.expect_value(t, view.template, templates[view.ordinal])
        contentdata.content_message_test_output(
            t, generation, id, templates[view.ordinal])
    }
}

// Synthetic candidates carry the same named signatures as the production consumers.
@(test)
content_fixture_materializes_native_message_signatures :: proc(t: ^testing.T) {
    fixture := contentfixture.search_test_database_create("content-signature-fixture")
    defer delete(fixture.directory, context.allocator)
    defer delete(fixture.path, context.allocator)
    defer _ = os.remove_all(fixture.directory)
    testing.expect(t, fixture.ok)
    database: Content_Database
    failure := sqlite.connection_open(
        &database.connection, fixture.path, .Immutable_Readonly, context.temp_allocator)
    testing.expect_value(t, failure.result, sqlite3.Result.Ok)
    defer _ = content_database_close(&database)
    registered := sqlite.connection_register_spellfix(&database.connection)
    testing.expect_value(t, registered.result, sqlite3.Result.Ok)
    testing.expect(t, content_database_prepare_statements(&database))
    testing.expect(t,
        content_database_validate_metadata(
            &database, contentfixture.SEARCH_TEST_FINGERPRINT))
    generation := new(contentdata.Content_Generation, context.allocator)
    defer free(generation, context.allocator)
    testing.expect_value(t, contentdata.content_generation_init(generation),
        contentdata.Content_Generation_Status.Ok)
    defer contentdata.content_generation_destroy(generation)
    testing.expect_value(t, contentdata.content_generation_begin(
        generation, database.index_generation), contentdata.Content_Generation_Status.Ok)
    testing.expect(t, content_admission_read_locales(&database, generation))
    testing.expect(t, content_admission_read_messages(&database, generation))
    testing.expect(t, content_admission_read_arguments(&database, generation))
    testing.expect(t, content_admission_read_translations(&database, generation))
    testing.expect_value(t, generation.data.argument_count, u16(17))
    testing.expect(t, content_admission_validate_messages(generation))
    testing.expect(t, content_admission_validate_translations(generation))
}
