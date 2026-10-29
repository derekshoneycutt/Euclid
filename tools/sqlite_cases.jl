"""Return a contiguous, explicitly typed SQLite binding list."""
function euclid_sqlite_bindings(values::SQLiteValue...)
    return SQLiteBind[SQLiteBind(slot, value) for (slot, value) in enumerate(values)]
end

"""Create a file-backed step whose identity is stable within its case."""
function euclid_sqlite_file_step(path; role::Symbol=:operation, bindings=SQLiteBind[])
    name = splitext(basename(path))[1]
    return SQLiteFileStep(replace(name, "_" => "-"), path; role, bindings)
end

"""Install ephemeral and durable history schemas before exercising their statements."""
function euclid_history_schema_steps()
    return SQLiteValidationStep[
        euclid_sqlite_file_step("src/terminal/history/store/sql/schema.sql"; role=:setup),
        euclid_sqlite_file_step("src/terminal/history/store/sql/index.sql"; role=:setup),
        euclid_sqlite_file_step(
            "src/userdata/sql/user_terminal_history.sql"; role=:setup),
    ]
end

"""Insert and update session/durable rows with the native caller's slot types."""
function euclid_history_mutation_steps()
    return SQLiteValidationStep[
        euclid_sqlite_file_step("src/terminal/history/store/sql/insert_persistent.sql";
            bindings=euclid_sqlite_bindings(
                SQLiteText("persisted source"), SQLiteInteger(1), SQLiteInteger(100),
                SQLiteInteger(1), SQLiteInteger(1))),
        euclid_sqlite_file_step(
            "src/terminal/history/store/sql/insert_linked_session.sql";
            bindings=euclid_sqlite_bindings(
                SQLiteInteger(2), SQLiteInteger(1), SQLiteText("linked source"),
                SQLiteInteger(1), SQLiteInteger(101),
                SQLiteInteger(1), SQLiteInteger(1))),
        euclid_sqlite_file_step("src/terminal/history/store/sql/insert.sql";
            bindings=euclid_sqlite_bindings(
                SQLiteInteger(3), SQLiteText("session source"), SQLiteInteger(0),
                SQLiteInteger(102), SQLiteInteger(1), SQLiteInteger(1))),
        euclid_sqlite_file_step("src/terminal/history/store/sql/update_persistent.sql";
            bindings=euclid_sqlite_bindings(
                SQLiteText("updated persistent"), SQLiteInteger(1), SQLiteInteger(2),
                SQLiteInteger(1), SQLiteInteger(1))),
        euclid_sqlite_file_step("src/terminal/history/store/sql/update.sql";
            bindings=euclid_sqlite_bindings(
                SQLiteText("updated session"), SQLiteInteger(0), SQLiteInteger(2),
                SQLiteInteger(3), SQLiteInteger(1))),
    ]
end

"""Exercise history lookups, navigation boundaries, and cleanup operations."""
function euclid_history_query_steps()
    return SQLiteValidationStep[
        euclid_sqlite_file_step("src/terminal/history/store/sql/get_by_id.sql";
            bindings=euclid_sqlite_bindings(SQLiteInteger(3))),
        euclid_sqlite_file_step("src/terminal/history/store/sql/get_persistent_by_id.sql";
            bindings=euclid_sqlite_bindings(SQLiteInteger(1))),
        euclid_sqlite_file_step("src/terminal/history/store/sql/older.sql";
            bindings=euclid_sqlite_bindings(SQLiteInteger(3))),
        euclid_sqlite_file_step("src/terminal/history/store/sql/newer.sql";
            bindings=euclid_sqlite_bindings(SQLiteInteger(2))),
        euclid_sqlite_file_step("src/terminal/history/store/sql/combined_older.sql";
            bindings=euclid_sqlite_bindings(
                SQLiteInteger(101), SQLiteInteger(0), SQLiteInteger(2))),
        euclid_sqlite_file_step("src/terminal/history/store/sql/combined_newer.sql";
            bindings=euclid_sqlite_bindings(
                SQLiteInteger(101), SQLiteInteger(0), SQLiteInteger(2))),
        euclid_sqlite_file_step("src/terminal/history/store/sql/combined_latest.sql"),
        euclid_sqlite_file_step(
            "src/terminal/history/store/sql/durable_table_exists.sql"),
        euclid_sqlite_file_step("src/terminal/history/store/sql/delete_persistent.sql"),
        euclid_sqlite_file_step("src/terminal/history/store/sql/delete_session.sql"),
    ]
end

"""Validate matching-page SQL using the runner's declared source-query fixture."""
function euclid_history_search_steps()
    steps = SQLiteValidationStep[]
    for name in ("search_older", "search_newer",
            "search_combined_older", "search_combined_newer")
        combined = startswith(name, "search_combined")
        for cursor_valid in (0, 1)
            bindings = SQLiteBind[
                SQLiteBind(1, SQLiteInteger(cursor_valid)),
                SQLiteBind(4, SQLiteInteger(2)),
                SQLiteBind(5, SQLiteInteger(2)),
                SQLiteBind(6, SQLiteInteger(1)),
                SQLiteBind(7, SQLiteInteger(260)),
                SQLiteBind(8, SQLiteInteger(1)),
            ]
            if combined
                push!(bindings, SQLiteBind(2, SQLiteInteger(101)),
                    SQLiteBind(3, SQLiteInteger(0)))
            end
            push!(steps, SQLiteFileStep(
                "$name-$cursor_valid",
                "src/terminal/history/store/sql/$name.sql"; bindings))
        end
    end
    return steps
end

"""Exercise history schemas and operations with the native caller's slot types."""
function euclid_sqlite_history_case()
    steps = vcat(
        euclid_history_schema_steps(),
        euclid_history_mutation_steps(),
        euclid_history_search_steps(),
        euclid_history_query_steps())
    return SQLiteValidationCase("terminal-history";
        requirements=["history_matches"], steps)
end

"""Exercise preference and collection persistence with storage-class-accurate bindings."""
function euclid_sqlite_userdata_case()
    collection_id = SQLiteBlob(fill(UInt8(0x11), 16))
    entry_id = SQLiteBlob(fill(UInt8(0x22), 16))
    animation_id = SQLiteBlob(fill(UInt8(0x33), 16))
    steps = SQLiteValidationStep[
        euclid_sqlite_file_step("src/userdata/sql/user_setting.sql"; role=:setup),
        euclid_sqlite_file_step(
            "src/userdata/sql/user_collection_schema.sql"; role=:setup),
        euclid_sqlite_file_step("src/userdata/sql/upsert_setting.sql";
            bindings=euclid_sqlite_bindings(
                SQLiteText("phase5"), SQLiteText("manifest"), SQLiteText("text"),
                SQLiteNull(), SQLiteText("typed validation"))),
        euclid_sqlite_file_step("src/userdata/sql/read_setting.sql";
            bindings=euclid_sqlite_bindings(
                SQLiteText("phase5"), SQLiteText("manifest"))),
        euclid_sqlite_file_step("src/userdata/sql/insert_collection.sql";
            bindings=euclid_sqlite_bindings(
                collection_id, SQLiteNull(), SQLiteText("Validation collection"),
                SQLiteInteger(1), SQLiteInteger(0))),
        euclid_sqlite_file_step("src/userdata/sql/insert_collection_entry.sql";
            bindings=euclid_sqlite_bindings(
                entry_id, collection_id, SQLiteNull(), SQLiteInteger(0),
                SQLiteText("animation"), animation_id, SQLiteNull())),
        euclid_sqlite_file_step("src/userdata/sql/read_collections.sql"),
        euclid_sqlite_file_step("src/userdata/sql/read_collection_entries.sql"),
        euclid_sqlite_file_step("src/userdata/sql/delete_setting.sql";
            bindings=euclid_sqlite_bindings(
                SQLiteText("phase5"), SQLiteText("manifest"))),
        euclid_sqlite_file_step("src/userdata/sql/delete_collection_entries.sql"),
        euclid_sqlite_file_step("src/userdata/sql/delete_collections.sql"),
    ]
    return SQLiteValidationCase("user-settings-and-collections"; steps)
end

"""Seed the locale, message arguments, and translations used by content reads."""
function euclid_content_localization_write_steps(locale, message)
    return SQLiteValidationStep[
        euclid_sqlite_file_step("tools/content_builder/sql/locale_insert.sql";
            bindings=euclid_sqlite_bindings(locale, SQLiteInteger(1))),
        euclid_sqlite_file_step("tools/content_builder/sql/message_insert.sql";
            bindings=euclid_sqlite_bindings(
                message, SQLiteInteger(1), SQLiteText("validation fixture"))),
        euclid_sqlite_file_step("tools/content_builder/sql/argument_insert.sql";
            bindings=euclid_sqlite_bindings(
                message, SQLiteInteger(0), SQLiteText("label"), SQLiteText("text"))),
        euclid_sqlite_file_step("tools/content_builder/sql/translation_insert.sql";
            bindings=euclid_sqlite_bindings(
                locale, message, SQLiteText("Validation {label}"))),
    ]
end

"""Insert typed metadata, localization, and catalog data into the authored schema."""
function euclid_content_builder_write_steps(
    namespace, animation, locale, edition, message)
    return SQLiteValidationStep[
        euclid_sqlite_file_step("tools/content_builder/sql/schema.sql"; role=:setup),
        euclid_sqlite_file_step("tools/content_builder/sql/metadata_insert.sql";
            bindings=euclid_sqlite_bindings(
                SQLiteText("catalog_projection_schema_version"), SQLiteText("2"))),
        euclid_content_localization_write_steps(locale, message)...,
        euclid_sqlite_file_step("tools/content_builder/sql/subject_insert.sql";
            bindings=euclid_sqlite_bindings(namespace, animation)),
        euclid_sqlite_file_step("tools/content_builder/sql/node_insert.sql";
            bindings=euclid_sqlite_bindings(
                namespace, animation, SQLiteNull(), SQLiteInteger(1), SQLiteInteger(0),
                SQLiteInteger(0), SQLiteText("validation/case.jl"))),
        euclid_sqlite_file_step("tools/content_builder/sql/name_insert.sql";
            bindings=euclid_sqlite_bindings(
                namespace, animation, locale, SQLiteText("Case study"))),
        euclid_sqlite_file_step("tools/content_builder/sql/edition_insert.sql";
            bindings=euclid_sqlite_bindings(
                edition, SQLiteText("case"), locale, SQLiteText("Validation edition"))),
        euclid_sqlite_file_step("tools/content_builder/sql/availability_insert.sql";
            bindings=euclid_sqlite_bindings(
                namespace, animation, locale, edition, SQLiteInteger(1))),
        euclid_sqlite_file_step("tools/content_builder/sql/projection_insert.sql";
            bindings=euclid_sqlite_bindings(
                SQLiteInteger(1), namespace, animation, locale, edition,
                SQLiteText("Case study"), SQLiteText("Root/Case study"),
                SQLiteText("Euclid validation case"), SQLiteText("case study"))),
        euclid_sqlite_file_step("tools/content_builder/sql/plain_insert.sql";
            bindings=euclid_sqlite_bindings(SQLiteText("plain validation content"))),
    ]
end

"""Read authored content interfaces and query both compiled-in search modules."""
function euclid_content_search_read_steps()
    return SQLiteValidationStep[
        euclid_sqlite_file_step("src/view/content/sql/argument_rows.sql"),
        euclid_sqlite_file_step("src/view/content/sql/availability_rows.sql"),
        euclid_sqlite_file_step("src/view/content/sql/catalog_rows.sql"),
        euclid_sqlite_file_step("src/view/content/sql/edition_rows.sql"),
        euclid_sqlite_file_step("src/view/content/sql/locale_rows.sql"),
        euclid_sqlite_file_step("src/view/content/sql/message_rows.sql"),
        euclid_sqlite_file_step("src/view/content/sql/name_rows.sql"),
        euclid_sqlite_file_step("src/view/content/sql/projection_rows.sql"),
        euclid_sqlite_file_step("src/view/content/sql/raw_metadata_rows.sql"),
        euclid_sqlite_file_step("src/view/content/sql/search_metadata.sql";
            bindings=euclid_sqlite_bindings(SQLiteText("schema_version"))),
        euclid_sqlite_file_step("src/view/content/sql/search_count.sql";
            bindings=euclid_sqlite_bindings(SQLiteText("case"))),
        euclid_sqlite_file_step("src/view/content/sql/search_rows.sql";
            bindings=euclid_sqlite_bindings(
                SQLiteText("case"), SQLiteInteger(10), SQLiteInteger(0))),
        euclid_sqlite_file_step("src/view/content/sql/search_spellfix.sql";
            bindings=euclid_sqlite_bindings(
                SQLiteText("case"), SQLiteInteger(10), SQLiteInteger(10))),
        euclid_sqlite_file_step("src/view/content/sql/subject_rows.sql"),
        euclid_sqlite_file_step("src/view/content/sql/translation_rows.sql"),
    ]
end

"""Build ordered builder/search rows with the exact source schema and required modules."""
function euclid_sqlite_content_case()
    namespace = SQLiteText("phase5")
    animation = SQLiteText("case-study")
    locale = SQLiteText("en-US")
    edition = SQLiteText("case-edition")
    message = SQLiteText("case.message")
    steps = vcat(
        euclid_content_builder_write_steps(
            namespace, animation, locale, edition, message),
        euclid_content_search_read_steps())
    return SQLiteValidationCase(
        "content-builder-and-search"; requirements=["fts5", "spellfix1"], steps)
end

"""Return native validation cases covering every authored first-party SQL file."""
function euclid_sqlite_validation_cases()
    return SQLiteValidationCase[
        euclid_sqlite_history_case(),
        euclid_sqlite_userdata_case(),
        euclid_sqlite_content_case(),
    ]
end
