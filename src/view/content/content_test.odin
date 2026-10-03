#+test
package content

import contentdata "../../core/content"
import storage "../../core/storage"
import sqlite3 "../../../libs/sqlite3"
import sqlite "../../sqlite"
import files "../../files"

import "core:c"
import "core:os"
import "core:strings"
import "core:testing"

// The packaged authored dataset, not just a synthetic fixture, preserves every baseline byte.
@(test)
content_packaged_messages_match_native_output_baselines :: proc(t: ^testing.T) {
    config := files.Asset_Root_Config{asset_root_override = "bin"}
    asset, resolved := files.packaged_content_asset_with_config(
        &config, context.allocator)
    testing.expect(t, resolved)
    if !resolved { return }
    defer delete(asset.database_path, context.allocator)
    defer delete(asset.corpus_fingerprint, context.allocator)
    generation := new(Content_Generation, context.allocator)
    defer free(generation, context.allocator)
    testing.expect_value(t, contentdata.content_generation_init(generation),
        contentdata.Content_Generation_Status.Ok)
    defer contentdata.content_generation_destroy(generation)
    database: Content_Database
    opened := content_database_open(
        &database, asset.database_path, asset.corpus_fingerprint, generation)
    testing.expect(t, opened)
    if !opened { return }
    defer _ = content_database_close(&database)
    templates := contentdata.CONTENT_MESSAGE_TEST_TEMPLATES
    for id in contentdata.Content_Message_Id {
        if id == .Invalid { continue }
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
    fixture := search_test_database_create("content-signature-fixture")
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
        content_database_validate_metadata(&database, SEARCH_TEST_FINGERPRINT))
    generation := new(Content_Generation, context.allocator)
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
    testing.expect_value(t, generation.data.argument_count, u16(10))
    testing.expect(t, content_admission_validate_messages(generation))
    testing.expect(t, content_admission_validate_translations(generation))
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

// Require a malformed candidate to retain every active projection and query identity.
content_test_reject_candidate :: proc(
    t: ^testing.T, service: ^Content_Service, suffix, mutation: string) {
    fixture := search_test_database_create(suffix)
    defer delete(fixture.directory, context.allocator)
    defer delete(fixture.path, context.allocator)
    defer _ = os.remove_all(fixture.directory)
    testing.expect(t, fixture.ok)
    testing.expect(t, content_test_mutate(&fixture, mutation))
    active := content_service_generation(service)
    baseline := active^.data
    records := active^.records
    text := strings.clone(string(active^.text_bytes), context.allocator)
    defer delete(text, context.allocator)
    testing.expect(t, !content_service_stage(
        service, fixture.path, SEARCH_TEST_FINGERPRINT))
    testing.expect_value(t, content_service_generation(service), active)
    testing.expect_value(t, active^.data, baseline)
    testing.expect_value(t, active^.records, records)
    testing.expect_value(t, string(active^.text_bytes), text)
    testing.expect_value(t, service.candidate_state, Content_Candidate_State.None)
    testing.expect(t, !service.staged_generation^.data.complete)
    testing.expect_value(t, service.staged_generation^.text_builder.count, 0)
    result := search_test_query(t, service, 91, "perpendicular")
    testing.expect_value(t, result.index_generation, active^.generation)
}

// Validate complete rollback rather than only preservation of the search connection.
@(test)
content_worker_rejects_malformed_ui_without_partial_publication :: proc(t: ^testing.T) {
    fixture := search_test_database_create("content-ui-active")
    defer delete(fixture.directory, context.allocator)
    defer delete(fixture.path, context.allocator)
    defer _ = os.remove_all(fixture.directory)
    service: Content_Service
    testing.expect(t, fixture.ok && content_service_init(
        &service, fixture.path, SEARCH_TEST_FINGERPRINT))
    defer content_service_destroy(&service)
    content_test_reject_candidate(t, &service, "content-missing-message",
        "DELETE FROM ui_translation WHERE message_key='ui.navigation.library'")
    content_test_reject_candidate(t, &service, "content-id-mismatch",
        "UPDATE ui_message SET native_message_id=999 WHERE message_key='ui.navigation.library'")
    content_test_reject_candidate(t, &service, "content-template",
        "UPDATE ui_translation SET template='Bad {missing}' WHERE message_key='ui.navigation.library'")
    content_test_reject_candidate(t, &service, "content-template-utf8",
        "UPDATE ui_translation SET template=CAST(x'80' AS TEXT) WHERE message_key='ui.navigation.library'")
    content_test_reject_candidate(t, &service, "content-template-capacity",
        "UPDATE ui_translation SET template=printf('%0130d',0) WHERE message_key='ui.navigation.library'")
}

// Edition/default and localized-name failures cannot replace any active content.
@(test)
content_worker_rejects_malformed_editions_and_names :: proc(t: ^testing.T) {
    fixture := search_test_database_create("content-edition-active")
    defer delete(fixture.directory, context.allocator)
    defer delete(fixture.path, context.allocator)
    defer _ = os.remove_all(fixture.directory)
    service: Content_Service
    testing.expect(t, fixture.ok && content_service_init(
        &service, fixture.path, SEARCH_TEST_FINGERPRINT))
    defer content_service_destroy(&service)
    content_test_reject_candidate(t, &service, "content-missing-default",
        "UPDATE availability SET is_default=0 WHERE animation_id='00000000-0000-0000-0000-000000000000'")
    content_test_reject_candidate(t, &service, "content-unknown-edition",
        "UPDATE availability SET edition_id='undeclared' WHERE animation_id='00000000-0000-0000-0000-000000000001'")
    content_test_reject_candidate(t, &service, "content-duplicate-default",
        "INSERT INTO availability SELECT source_namespace,animation_id,locale_tag,'heath',1 FROM availability")
    content_test_reject_candidate(t, &service, "content-name-projection",
        "UPDATE catalog_name SET display_name='Different' WHERE animation_id='00000000-0000-0000-0000-000000000001'")
    content_test_reject_candidate(t, &service, "content-duplicate-name",
        "UPDATE catalog_name SET display_name='Circle' WHERE animation_id='00000000-0000-0000-0000-000000000001'")
    content_test_reject_candidate(t, &service, "content-edition-overflow",
        "WITH RECURSIVE sequence(value) AS (VALUES(1) UNION ALL "+
        "SELECT value+1 FROM sequence WHERE value<6) "+
        "INSERT INTO edition SELECT 'extra-'||value,'Extra '||value,'en-US','Extra' FROM sequence")
}

// Typed ordinal signatures are bounded and templates must match their declared names.
@(test)
content_worker_admits_and_rejects_typed_signatures :: proc(t: ^testing.T) {
    fixture := search_test_database_create("content-signature-active")
    defer delete(fixture.directory, context.allocator)
    defer delete(fixture.path, context.allocator)
    defer _ = os.remove_all(fixture.directory)
    testing.expect(t, fixture.ok && content_test_mutate(&fixture,
        "UPDATE ui_translation SET template='{count}, again {count}' "+
        "WHERE message_key='ui.library.status.match_count';"))
    service: Content_Service
    testing.expect(t, content_service_init(
        &service, fixture.path, SEARCH_TEST_FINGERPRINT))
    defer content_service_destroy(&service)
    generation := content_service_generation(&service)
    testing.expect_value(t, generation^.data.argument_count, u16(10))
    content_test_reject_candidate(t, &service, "content-native-signature",
        "INSERT INTO ui_argument VALUES ('ui.navigation.library',0,'count','uint32');"+
        "UPDATE ui_translation SET template='{count}' WHERE message_key='ui.navigation.library';")
    content_test_reject_candidate(t, &service, "content-native-kind",
        "UPDATE ui_argument SET argument_type='int64' "+
        "WHERE message_key='ui.library.status.match_count';")
    content_test_reject_candidate(t, &service, "content-native-name",
        "UPDATE ui_argument SET argument_name='number' "+
        "WHERE message_key='ui.library.status.match_count';"+
        "UPDATE ui_translation SET template='{number}' "+
        "WHERE message_key='ui.library.status.match_count';")
    content_test_reject_candidate(t, &service, "content-signature-type",
        "INSERT INTO ui_argument VALUES ('ui.navigation.library',0,'count','unknown');"+
        "UPDATE ui_translation SET template='{count}' WHERE message_key='ui.navigation.library';")
    content_test_reject_candidate(t, &service, "content-signature-ordinal",
        "INSERT INTO ui_argument VALUES ('ui.navigation.library',1,'count','uint32');"+
        "UPDATE ui_translation SET template='{count}' WHERE message_key='ui.navigation.library';")
    content_test_reject_candidate(t, &service, "content-signature-capacity",
        "INSERT INTO ui_argument SELECT message_key,0,'count','uint32' "+
        "FROM ui_message ORDER BY message_key LIMIT 33;"+
        "UPDATE ui_translation SET template='{count}' "+
        "WHERE message_key IN (SELECT message_key FROM ui_argument);")
}

// A search-compatible database without schema-3 content must fail closed at startup.
@(test)
content_worker_rejects_search_only_database :: proc(t: ^testing.T) {
    search_test_rejects_catalog_mutation(t, "content-search-only",
        "DROP TABLE content_metadata")
}

// Newline serialization includes delimiters beyond the sixteen individual alias bounds.
@(test)
content_worker_preserves_exact_search_alias_bounds :: proc(t: ^testing.T) {
    fixture := search_test_database_create("content-alias-bound")
    defer delete(fixture.directory, context.allocator)
    defer delete(fixture.path, context.allocator)
    defer _ = os.remove_all(fixture.directory)
    testing.expect(t, fixture.ok && content_test_mutate(&fixture,
        "WITH RECURSIVE sequence(value) AS (VALUES(0) UNION ALL "+
        "SELECT value+1 FROM sequence WHERE value<15) "+
        "UPDATE search_projection SET aliases=(SELECT group_concat(alias,char(10)) "+
        "FROM (SELECT printf('%0128d',value) AS alias FROM sequence ORDER BY value)) "+
        "WHERE projection_id=1;"))
    service: Content_Service
    testing.expect(t, content_service_init(
        &service, fixture.path, SEARCH_TEST_FINGERPRINT))
    defer content_service_destroy(&service)
    generation := content_service_generation(&service)
    aliases, status := contentdata.content_generation_text(
        generation, generation^.data.projections[0].aliases)
    testing.expect_value(t, status, contentdata.Content_Generation_Status.Ok)
    testing.expect_value(t, len(aliases), 16 * 128 + 15)
    content_test_reject_candidate(t, &service, "content-alias-overflow",
        "UPDATE search_projection SET aliases=printf('%0129d',0) WHERE projection_id=1")
    content_test_reject_candidate(t, &service, "content-alias-duplicate",
        "UPDATE search_projection SET aliases='repeat'||char(10)||'repeat' "+
        "WHERE projection_id=1")
}

// Edition language is independent of the application locale and has ordinary bindings.
@(test)
content_worker_accepts_greek_edition_under_english_ui :: proc(t: ^testing.T) {
    fixture := search_test_database_create("content-greek-edition")
    defer delete(fixture.directory, context.allocator)
    defer delete(fixture.path, context.allocator)
    defer _ = os.remove_all(fixture.directory)
    testing.expect(t, fixture.ok && content_test_mutate(&fixture,
        "INSERT INTO edition VALUES ('greek','Ancient Greek','grc','Greek source');"+
        "INSERT INTO availability SELECT source_namespace,animation_id,'en-US','greek',0 FROM content_subject;"+
        "UPDATE content_metadata SET value='990' WHERE key='record_count';"+
        "UPDATE content_metadata SET value='1=6;2=1;3=69;4=10;5=69;6=139;7=138;8=138;9=4;10=278;11=138' "+
        "WHERE key='table_counts';"))
    service: Content_Service
    testing.expect(t, content_service_init(
        &service, fixture.path, SEARCH_TEST_FINGERPRINT))
    defer content_service_destroy(&service)
    generation := content_service_generation(&service)
    testing.expect(t, generation != nil && generation^.data.complete)
    testing.expect_value(t, generation^.data.edition_count, u16(4))
    testing.expect_value(t, generation^.data.availability_count, u16(278))
}

// Both stable slots retire all content and packed storage after repeated transactions.
@(test)
content_service_retires_complete_candidate_storage :: proc(t: ^testing.T) {
    active := search_test_database_create("content-retire-active")
    candidate := search_test_database_create("content-retire-candidate")
    defer delete(active.directory, context.allocator)
    defer delete(active.path, context.allocator)
    defer delete(candidate.directory, context.allocator)
    defer delete(candidate.path, context.allocator)
    defer _ = os.remove_all(active.directory)
    defer _ = os.remove_all(candidate.directory)
    service: Content_Service
    testing.expect(t, active.ok && candidate.ok && content_service_init(
        &service, active.path, SEARCH_TEST_FINGERPRINT))
    defer content_service_destroy(&service)
    search_test_make_candidate(t, &candidate)
    content_test_complete_transaction(t, &service, &candidate)
    content_test_stable_slot_pressure(t, &service, &candidate)
}

// Repeating bounded reloads reuses the same owners without increasing arena high waters.
content_test_stable_slot_pressure :: proc(
    t: ^testing.T, service: ^Content_Service, candidate: ^Search_Test_Database) {
    content_test_complete_transaction(t, service, candidate)
    first := service.active_generation
    second := service.staged_generation
    first_sample := storage.arena_owner_diagnostics(&first^.arena_owner)
    second_sample := storage.arena_owner_diagnostics(&second^.arena_owner)
    for _ in 0..<2 {
        content_test_complete_transaction(t, service, candidate)
    }
    first_after := storage.arena_owner_diagnostics(&first^.arena_owner)
    second_after := storage.arena_owner_diagnostics(&second^.arena_owner)
    testing.expect_value(t, first_after.peak_used, first_sample.peak_used)
    testing.expect_value(t, first_after.peak_reserved, first_sample.peak_reserved)
    testing.expect_value(t, second_after.peak_used, second_sample.peak_used)
    testing.expect_value(t, second_after.peak_reserved, second_sample.peak_reserved)
    testing.expect(t, service.active_generation == first)
    testing.expect(t, service.staged_generation == second)
}

// Compare the complete provisional publication and rollback before final retirement.
content_test_complete_transaction :: proc(
    t: ^testing.T, service: ^Content_Service, candidate: ^Search_Test_Database) {
    active := content_service_generation(service)
    baseline := active^.data
    testing.expect(t, content_service_stage(
        service, candidate.path, SEARCH_TEST_CANDIDATE_FINGERPRINT))
    staged := content_service_staged_generation(service)
    testing.expect(t, staged != nil && staged^.data.complete && staged != active)
    testing.expect(t, content_service_commit(service))
    testing.expect_value(t, content_service_generation(service), staged)
    content_test_candidate_values(t, staged)
    testing.expect(t, content_service_discard(service))
    testing.expect_value(t, content_service_generation(service), active)
    testing.expect_value(t, active^.data, baseline)
    testing.expect_value(t, staged^.data, contentdata.Content_Records{})
    testing.expect_value(t, staged^.text_builder.count, 0)
    testing.expect(t, content_service_stage(
        service, candidate.path, SEARCH_TEST_CANDIDATE_FINGERPRINT))
    testing.expect(t, content_service_commit(service) &&
        content_service_finalize(service))
    retired := service.staged_generation
    testing.expect_value(t, retired^.data, contentdata.Content_Records{})
    testing.expect_value(t, retired^.generation, u64(0))
    diagnostics := storage.arena_owner_diagnostics(&retired^.arena_owner)
    testing.expect(t, diagnostics.initialized && diagnostics.reset_count > 0)
}

// Names, templates, and edition provenance become visible from the same published slot.
content_test_candidate_values :: proc(t: ^testing.T, generation: ^Content_Generation) {
    name, name_status := contentdata.content_generation_text(
        generation, generation^.records[0].display_name)
    template, template_status := contentdata.content_generation_text(
        generation, generation^.data.translations[0].template)
    testing.expect_value(t, name_status, contentdata.Content_Generation_Status.Ok)
    testing.expect_value(t, template_status, contentdata.Content_Generation_Status.Ok)
    testing.expect_value(t, name, "Candidate Perpendicular")
    testing.expect_value(t, template, "Candidate message")
    found := false
    for edition in generation^.data.editions[:generation^.data.edition_count] {
        id, _ := contentdata.content_generation_text(generation, edition.id)
        if id == "original" {
            edition_name, status := contentdata.content_generation_text(
                generation, edition.name)
            testing.expect_value(t, status, contentdata.Content_Generation_Status.Ok)
            testing.expect_value(t, edition_name, "Candidate Original")
            found = true
        }
    }
    testing.expect(t, found)
}
