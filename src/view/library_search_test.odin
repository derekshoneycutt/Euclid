package view

import bridgemodel "../bridge/model"
import bridge "../bridge"
import evidence_session "../evidence/session"
import evidence_trace "../evidence/trace"
import "../files"
import viewmodel "model"
import viewcatalog "catalog"

import "core:encoding/uuid"
import "core:os"
import "core:path/filepath"
import "core:testing"
import "core:time"

Library_Search_Quality_Fixture :: struct {
    query:        string,
    expected_id:  string,
    display_name: string,
}

LIBRARY_SEARCH_QUALITY_FIXTURES :: [?]Library_Search_Quality_Fixture{
    {"draw circle", "4d9de8df-9439-523a-957e-99439f5ad927", "Draw a Circle"},
    {"equidistant fixed center", "5eae70a6-d48e-4b85-9fe3-db3b2e82cb3b", "Circle"},
    {"two fixed foci", "9836d89f-5b15-45b6-be0a-92c2e61c541c", "Ellipse"},
    {"tracer inside rolling circle", "0a8ada74-d72a-403d-a065-2269c72dfd4b", "Curtate Cycloid"},
    {"heart shaped one cusp", "bad550b7-54c6-40df-adf1-c19e2e88fe25", "Cardioid"},
    {"eleven cusps two circuits", "d6fcda98-5195-457d-8154-939930ec00c5", "11⁄2-Hypocycloid"},
    {"kidney shaped two cusp", "5cea3464-3e41-444d-a326-2fbd9b20de7e", "Nephroid"},
    {"two element reflection symmetry", "de580f25-1901-50de-84b3-3d7966a8bfd4", "ℤ₂"},
    {"cyclic rotations equal angle steps", "36baf769-897f-5e3d-8e7f-a5f7dd605dd7", "Cₙ"},
    {"commutative order does not matter", "ab55384b-ed8e-5a51-b367-4ea2b4fbd9fb", "Abelian"},
    {"intersection lens both conditions", "8785c9e6-53e9-4433-b1ae-7e18cef22c88", "And"},
    {"bounded negation lune difference", "9f6972f7-949b-4290-bfda-11dcbfcab409", "Not"},
    {"all sides unequal proclus", "fc8d5e5e-3135-53aa-8e4e-4021f78443d4", "Scalene Triangle"},
    {"twenty three definitions points lines angles", "17ec8ed8-e961-51fc-8025-4bb16ad8a10b", "Definitions"},
    {"whole greater than part equality", "ff723537-4f80-528f-a762-39fdc8a5034a", "Common Notions"},
    {"transversal interior angles meet", "4d98d3cf-e73a-5e6e-9e1d-6fa1141934e6", "Non-Parallel Lines"},
    {"breadthless length no width", "168548ed-ed4a-5d8b-8ac6-fb573f5637cd", "Line"},
    {"surface boundaries are lines", "b2f240b3-12c1-5908-a7fb-4a0315929980", "Surface Extremities"},
    {"inclination two lines rectilinear", "18a9886f-a127-549d-8863-6deb86858661", "Plane Angle"},
    {"greater than right angle wide", "142a4b16-0a1f-58f5-8599-823b8d3d2821", "Obtuse Angle"},
    {"contained by several boundaries", "cc73ce96-0e8a-576c-9b2e-daa3b559c9ff", "Figure"},
    {"straight line through center bisects circle", "b2472007-9bab-592b-a891-8b9c97d86539", "Diameter"},
    {"more than four straight lines", "157804cd-7a32-525d-90bd-88d2f76d4f03", "Multilateral Rectilineal Figures"},
    {"two sides alone equal", "a2a8bc49-a232-52db-baa2-cdc0fa377ae8", "Isosceles Triangle"},
    {"three angles acute", "fc2794f8-dbac-52a1-89e6-865e76d23cf4", "Acute-Angled Triangle"},
    {"opposite sides angles equal neither equilateral right angled", "f82efede-34ea-5ffe-8f34-ab6ae17f1860", "Rhomboid"},
    {"same plane indefinitely never meet", "51608ec9-487a-53f9-ba14-72c1f1750756", "Parallel Straight Lines"},
    {"place at given point equal straight line", "81464bfd-ae0f-5763-8617-c3846f692c33", "Proposition II"},
    {"connection order parallels congruence continuity", "df6fe312-a86c-5489-96b5-39729053df0d", "1. The Five Groups of Axioms, §1"},
    {"betweenness sequence points linear", "ccb3afdf-4679-5dc7-9815-a7c3263d01b1", "§3 Group II: Axioms of Order"},
    {"Archimedean continuity completeness", "2e0a8725-94ef-5c51-93df-f35356806483", "§8 Group V: Axiom of Continuity"},
    {"two line three plane four space points", "8c128636-9d9f-508f-9243-4ddbeb93eead", "Axiom I,7"},
    {"point between and beyond endpoint", "9fd5d1e9-dcbb-530b-a99d-8b891f8e0746", "Axiom II,2"},
    {"coplanar line crosses triangle side", "df459efe-fb15-5bde-898c-abf676cfa170", "Axiom II,5"},
    {"exactly one parallel through outside point", "6fe08874-492a-50e6-a69c-b993b39369d0", "Axiom III"},
    {"lay off angle chosen half ray", "de9f30ff-7cd4-5eaa-bfe4-ecd5c1c4de9a", "Axiom IV,4"},
    {"no points lines planes added five groups", "b47188c2-2829-5320-82c1-caf2666314b2", "Axiom of Completeness"},
    {"same or different sides straight line plane", "fdc6cded-a63f-5b19-ad63-8876317366ce", "Definition: Side of Line"},
    {"supplementary vertical right angles", "b3709506-caed-5801-8ebf-29ff50c1f6ef", "Definition: Supplementary Angles"},
    {"finite point set one-to-one segments angles", "71d6cce5-385d-57d5-bbcd-209393b3ca15", "Definition: Figure"},
    {"line outside point exactly one plane", "ce75fdec-5412-5be8-a15e-a638bdab2c41", "Theorem 2"},
    {"unlimited points between straight line", "d119466f-cf6b-569a-8228-f5e21b753b74", "Theorem 3"},
    {"simple polygon interior exterior crosses boundary", "88d5a96a-0b6e-5833-9fb6-25b7f0ff4b7b", "Theorem 6"},
    {"two sides included angle triangle congruent", "0b80bb83-049d-5385-a481-326c27126f49", "Theorem 10"},
    {"supplements of congruent angles congruent", "94255381-8250-5e52-8b42-df5d5fb68af6", "Theorem 12"},
    {"interior half ray matching subangles", "a156d843-ed14-5a5e-b311-7cf82957295c", "Theorem 13"},
    {"three corresponding sides triangle congruent", "ad0416c5-2429-5ae3-8143-2594a6aca758", "Theorem 16"},
    {"four noncoplanar points congruence without parallels", "db80657d-3c76-554e-9bec-b193cc6dcdbf", "Theorem 18"},
    {"triangle angles sum two right angles", "f093e4fb-8651-5385-8837-60c25cccebc3", "Theorem 20"},
}

// search_test_document_key builds one canonical built-in result identity.
search_test_document_key :: proc(text: string) -> viewcatalog.Search_Document_Key {
    result := viewcatalog.Search_Document_Key{source_namespace = .Builtin}
    copy(result.document_id.bytes[:], text)
    return result
}

// library_search_quality_fixture_matches checks one natural query against the packaged corpus.
library_search_quality_fixture_matches :: proc(
    t: ^testing.T, service: ^viewcatalog.Catalog_Service,
    registry: ^bridgemodel.Euclid_Julia_Interface,
    fixture: Library_Search_Quality_Fixture, generation: u64) {
    stable_id, read_error := uuid.read(fixture.expected_id)
    testing.expect(t, read_error == .None)
    state := new(Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    state^.julia_interface = registry
    search := &state^.ui_runtime.library_search
    copy(search^.query[:], fixture.query)
    search^.query_length = len(fixture.query)
    search^.generation = generation
    search^.query_dirty = true
    search^.debounce_remaining_seconds = 0.175

    for _ in 0..<1000 {
        service_library_search(state, service, 0.016)
        if search^.active {
           break
        }
        time.sleep(time.Millisecond)
    }
    testing.expect(t, search^.active)
    testing.expect(t, search^.total_match_count > 0)
    testing.expect(t, search^.visible_id_count > 0)
    matched_node_is_visible := false
    for index in 0..<search^.visible_id_count {
        matched_node_is_visible = matched_node_is_visible ||
            search^.visible_ids[index] == stable_id
    }
    testing.expect(t, matched_node_is_visible)
}

// Verify a current result derives ancestors without mutating stored expansion.
@(test)
library_search_commit_derives_visible_ancestry :: proc(t: ^testing.T) {
    root_id, _ := uuid.read("11111111-1111-4111-8111-111111111111")
    leaf_id, _ := uuid.read("22222222-2222-4222-8222-222222222222")
    nodes: [2]bridgemodel.Euclid_Julia_Animation_Interface
    nodes[0].stable_id = root_id
    nodes[0].first_child = &nodes[1]
    nodes[0].next_in_registry = &nodes[1]
    nodes[1].stable_id = leaf_id
    nodes[1].parent = &nodes[0]
    state := new(Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    state^.julia_interface = &state^.julia_interface_slots[0]
    state^.julia_interface^.animation_head = &nodes[0]
    state^.julia_interface^.animation_count = len(nodes)
    search := &state^.ui_runtime.library_search
    search.query_length = 4
    search.generation = 7
    search.index_generation = 11
    result := viewcatalog.Search_Query_Result{generation = 7,
        index_generation = 11, status = .Ready, total_match_count = 1,
        returned_count = 1}
    result.document_keys[0] = search_test_document_key(
        "22222222-2222-4222-8222-222222222222")

    testing.expect(t, library_search_commit_result(state, &result))
    testing.expect(t, search.active)
    testing.expect_value(t, search.visible_id_count, 2)
    testing.expect(t, !nodes[0].is_expanded)
}

// Verify stale result generations cannot replace accepted display state.
@(test)
library_search_commit_rejects_stale_generation :: proc(t: ^testing.T) {
    state := new(Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    search := &state^.ui_runtime.library_search
    search.generation = 8
    search.index_generation = 12
    search.visible_id_count = 1
    result := viewcatalog.Search_Query_Result{generation = 7,
        index_generation = 12, status = .Ready}
    testing.expect(t, !library_search_commit_result(state, &result))
    testing.expect_value(t, search.visible_id_count, 1)
}

// Verify accepted results publish counts, generations, and suggestion status.
@(test)
library_search_commit_records_typed_evidence :: proc(t: ^testing.T) {
    state := new(Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    state^.evidence_session.enabled = true
    state^.evidence_session.lanes = evidence_session.ALL_LANES
    state^.evidence_session.required_evidence_complete = true
    evidence_trace.ring_init(&state^.evidence_ring, .Display)
    search := &state^.ui_runtime.library_search
    search^.query_length = 4
    search^.generation = 7
    search^.index_generation = 11
    search^.scenario_correlation = 23
    search^.scenario_correlation_generation = 1
    result := viewcatalog.Search_Query_Result{generation = 7,
        index_generation = 11, status = .Ready, total_match_count = 81,
        returned_count = 64, more_available = true, suggestion_length = 3}
    copy(result.suggestion_bytes[:], "ray")

    testing.expect(t, library_search_commit_result(state, &result))

    event := state^.evidence_ring.events[0]
    testing.expect_value(t, event.kind,
        evidence_trace.Kind.Library_Search_Committed)
    testing.expect_value(t, event.correlation_kind,
        evidence_trace.Correlation_Kind.Scenario_Action)
    testing.expect_value(t, event.correlation, u64(23))
    testing.expect_value(t, event.generation, u64(1))
    testing.expect_value(t, event.tick, u64(7))
    testing.expect_value(t, event.revision, u64(11))
    testing.expect_value(t, event.payload.counts.first, u32(64))
    testing.expect_value(t, event.payload.counts.second, u32(81))
    testing.expect(t, .Required in event.flags)
    testing.expect(t, .Truncated in event.flags)
    testing.expect(t, .Suggested in event.flags)
}

// Verify debounce waits for elapsed time while explicit submit is immediate.
@(test)
library_search_debounce_and_submit_timing :: proc(t: ^testing.T) {
    search := viewmodel.Library_Search_State{query_length = 4,
        query_dirty = true, debounce_remaining_seconds = 0.175}
    testing.expect(t, !library_search_debounce_ready(&search, 0.1))
    testing.expect(t, library_search_debounce_ready(&search, 0.075))
    search.debounce_remaining_seconds = 1
    search.submit_requested = true
    testing.expect(t, library_search_debounce_ready(&search, 0))
}

// Verify the packaged index reaches display-owned tree identity through the real worker.
@(test)
library_search_packaged_index_commits_visible_node :: proc(t: ^testing.T) {
    cwd, cwd_err := os.get_working_directory(context.temp_allocator)
    testing.expect(t, cwd_err == nil)
    bin_dir, bin_join_err := filepath.join(
        []string{cwd, "bin"}, context.allocator)
    testing.expect(t, bin_join_err == nil)
    defer delete(bin_dir)
    asset_config := files.make_asset_root_config(bin_dir, context.allocator)
    defer files.destroy_asset_root_config(&asset_config)
    asset, asset_ok := files.packaged_catalog_asset_with_config(
        &asset_config, context.allocator)
    defer delete(asset.database_path, context.allocator)
    defer delete(asset.corpus_fingerprint, context.allocator)
    testing.expect(t, asset_ok)
    service := viewcatalog.catalog_service_create(
        asset.database_path, asset.corpus_fingerprint)
    testing.expect(t, service != nil)
    if service == nil {
       return
    }
    defer viewcatalog.catalog_service_destroy_owned(service)

    registry_state := new(Euclid_General_State, context.allocator)
    defer bridge.destroy_julia_interface_resources(registry_state)
    defer free(registry_state, context.allocator)
    registry := &registry_state^.julia_interface_slots[0]
    registry_state^.julia_interface = registry
    snapshot := viewcatalog.catalog_service_snapshot(service)
    testing.expect(t, snapshot != nil)
    if snapshot == nil {
       return
    }
    testing.expect(t, bridge.catalog_snapshot_materialize(registry, snapshot))

    for fixture, index in LIBRARY_SEARCH_QUALITY_FIXTURES {
        library_search_quality_fixture_matches(
            t, service, registry, fixture, u64(index + 1))
    }
}