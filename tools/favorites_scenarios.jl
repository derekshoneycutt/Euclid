"""Run bounded fixture SQL outside the application; scenarios never accept SQL."""
function favorites_fixture_sql(database::String, sql::String)
    sqlite = Sys.which("sqlite3")
    sqlite === nothing && error("Favorites acceptance requires the sqlite3 CLI")
    result = capture_process(
        Cmd([sqlite, "-bail", "-json", database]); input=IOBuffer(sql))
    result.exit_code == 0 || error("Favorites fixture SQL failed: $(result.stderr)")
    return isempty(strip(result.stdout)) ? nothing : JSON.parse(result.stdout)
end

"""Inspect committed ordered membership and placement UUIDs independently."""
function favorites_database_rows(database::String)
    sqlite = Sys.which("sqlite3")
    sqlite === nothing && error("Favorites acceptance requires the sqlite3 CLI")
    sql = "SELECT hex(entry_id) AS placement,hex(animation_id) AS animation,custom_name," *
        "sibling_order FROM user_collection_entry " *
        "WHERE collection_id=(SELECT collection_id FROM user_collection " *
        "WHERE system_role='favorites') ORDER BY sibling_order"
    result = capture_process(Cmd([sqlite, "-readonly", "-json", database, sql]))
    result.exit_code == 0 || error("Favorites inspection failed: $(result.stderr)")
    return isempty(strip(result.stdout)) ? [] : JSON.parse(result.stdout)
end

"""Build the genuine v1 schema so launch must migrate without losing preferences."""
function favorites_migration_fixture(database::String)
    schema = read(joinpath(REPOSITORY_ROOT, "src", "userdata", "sql",
        "user_setting.sql"), String)
    favorites_fixture_sql(database, schema *
        "INSERT INTO user_setting VALUES ('drawing','dust_limit','integer',1400,NULL);" *
        "PRAGMA application_id=1163215701; PRAGMA user_version=1;")
end

"""Validate isolated Favorites launches with joined task correlation and shutdown evidence."""
function favorites_launch(binary, root, database, name, source;
    arguments=String[])
    if !any(argument -> startswith(argument, "--diagnostics="), arguments)
        arguments = [arguments; "--diagnostics=$(joinpath(root, "$name.log"))"]
    end
    record = run_scenario_launch(binary, "favorites-$name", source,
        joinpath(root, name), ["--user-db=$database"; arguments])
    scenario_passed(record) || error("Favorites scenario failed: $source " *
        "step=$(record.failed_step) reason=$(record.reason) artifacts=$(record.artifacts)")
    validate_settings_launch(record)
    return record
end

"""Require fresh and migrated membership round trips plus unchanged portrait restore."""
function run_favorites_roundtrip(binary::String, root::String, migrated::Bool)
    directory = joinpath(root, migrated ? "migrated" : "fresh")
    mkpath(directory)
    database = joinpath(directory, "user.sqlite3")
    migrated && favorites_migration_fixture(database)
    source = joinpath("tools", "scenarios", "collections-favorites-acceptance.jsonl")
    first = favorites_launch(binary, directory, database, "acceptance", source)
    rows = favorites_database_rows(database)
    length(rows) == 2 || error("Favorites did not persist exactly B/A membership")
    rows[1]["animation"] != rows[2]["animation"] ||
        error("Favorites contain duplicate animation membership")
    rows[1]["sibling_order"] < rows[2]["sibling_order"] ||
        error("Favorites order was not preserved")
    require_setting_row(settings_database_rows(database), "drawing", "dust_limit", 1400)
    restore = favorites_launch(binary, directory, database, "restore",
        joinpath("tools", "scenarios", "favorites", "restore.jsonl");
        arguments=["--layout=portrait", "--window-size=640x900"])
    favorites_database_rows(database) == rows ||
        error("Favorites restore changed committed placement identities")
    return [first, restore], database
end

"""Remove the external SQLite fault after the scenario proves retained failure state."""
function favorites_recovery_launch(binary::String, root::String, database::String;
    source=joinpath("tools", "scenarios", "favorites", "recovery.jsonl"))
    baseline = favorites_database_rows(database)
    diagnostics = joinpath(root, "recovery.log")
    task = @async favorites_launch(binary, root, database, "recovery",
        source;
        arguments=["--diagnostics=$diagnostics"])
    deadline = time() + 30
    observed = false
    while !istaskdone(task) && time() < deadline
        if isfile(diagnostics) &&
            occursin("favorites_failure_observed", read(diagnostics, String))
            observed = true
            break
        end
        sleep(0.05)
    end
    # The signal is emitted only after the retained-failure assertion succeeds.
    observed || begin
        fetch(task)
        error("Recovery did not publish its failure checkpoint")
    end
    favorites_database_rows(database) == baseline ||
        error("Retained failed edits changed committed Favorites before recovery")
    favorites_fixture_sql(database, "DROP TRIGGER favorites_acceptance_failure")
    return fetch(task)
end

"""Verify rollback, retained edits, real recovery and second-process durable restore."""
function run_favorites_failure_cases(binary::String, root::String, database::String)
    records = NamedTuple[]
    baseline = favorites_database_rows(database)
    favorites_fixture_sql(database,
        "CREATE TRIGGER favorites_acceptance_failure BEFORE INSERT ON user_collection_entry " *
        "BEGIN SELECT RAISE(ABORT,'favorites acceptance fault'); END")
    push!(records, favorites_launch(binary, root, database, "degraded",
        joinpath("tools", "scenarios", "favorites", "degraded.jsonl")))
    favorites_database_rows(database) == baseline ||
        error("Failed transaction partially published collection rows")
    require_setting_row(settings_database_rows(database), "drawing", "dust_limit", 1400)
    push!(records, favorites_recovery_launch(binary, root, database))
    length(favorites_database_rows(database)) == 3 ||
        error("Recovery did not persist the retained Favorites edit")
    require_setting_row(settings_database_rows(database), "drawing", "dust_limit", 1500)
    push!(records, favorites_launch(binary, root, database, "recovered-restore",
        joinpath("tools", "scenarios", "favorites", "recovered-restore.jsonl")))
    return records
end

"""Run reusable Favorites acceptance against fresh and v1-migrated isolated databases."""
function run_favorites_acceptance(binary::String)
    root = fresh_artifact_path("collections-favorites")
    records, database = run_favorites_roundtrip(binary, root, false)
    session_root = joinpath(root, "empty-session")
    mkpath(session_root)
    push!(records, favorites_launch(binary, session_root,
        joinpath(session_root, "user.sqlite3"), "acceptance",
        joinpath("tools", "scenarios", "favorites", "empty-session.jsonl")))
    migrated, _ = run_favorites_roundtrip(binary, root, true)
    append!(records, migrated)
    append!(records, run_favorites_failure_cases(binary, root, database))
    append!(records, run_favorites_capacity(binary, root))
    append!(records, run_favorites_motion(binary, root))
    append!(records, run_favorites_ordering(binary, root))
    return records
end

"""Require a precise durable permutation without recreating any animation placement."""
function require_favorites_reorder(rows, baseline, permutation)
    length(rows) == length(baseline) == length(permutation) ||
        error("Reorder changed Favorites membership count")
    length(unique(row["placement"] for row in baseline)) == length(baseline) ||
        error("Seed contains duplicate placement identities")
    length(unique(row["animation"] for row in baseline)) == length(baseline) ||
        error("Seed contains duplicate animation identities")
    for (index, source) in enumerate(permutation)
        rows[index]["animation"] == baseline[source]["animation"] ||
            error("Durable Favorites order differs at sibling $index")
        rows[index]["placement"] == baseline[source]["placement"] ||
            error("Reorder replaced a Favorites placement UUID")
        index == 1 || rows[index - 1]["sibling_order"] < rows[index]["sibling_order"] ||
            error("Durable Favorites sibling positions are not increasing")
    end
    return nothing
end

"""Prove UI-driven reordering changes durable order and survives a separate process."""
function run_favorites_ordering(binary::String, root::String)
    directory = joinpath(root, "ordering")
    mkpath(directory)
    database = joinpath(directory, "user.sqlite3")
    sources = joinpath("tools", "scenarios", "favorites")
    records = [favorites_launch(binary, directory, database, "seed",
        joinpath(sources, "reorder-seed.jsonl"))]
    baseline = favorites_database_rows(database)
    length(baseline) == 3 || error("Ordering seed did not persist three Favorites")
    push!(records, favorites_launch(binary, directory, database, "reorder",
        joinpath(sources, "reorder-acceptance.jsonl")))
    reordered = favorites_database_rows(database)
    require_favorites_reorder(reordered, baseline, [2, 1, 3])
    push!(records, favorites_launch(binary, directory, database, "restore",
        joinpath(sources, "reorder-restore.jsonl");
        arguments=["--layout=portrait", "--window-size=640x900"]))
    favorites_database_rows(database) == reordered ||
        error("Reorder restore changed committed rows or UUIDs")
    append!(records, run_favorites_reorder_failure(binary, directory, database, baseline))
    return records
end

"""Prove failed moves roll back durably while later retained moves recover in order."""
function run_favorites_reorder_failure(binary::String, root::String,
    database::String, seed)
    sources = joinpath("tools", "scenarios", "favorites")
    baseline = favorites_database_rows(database)
    favorites_fixture_sql(database,
        "CREATE TRIGGER favorites_acceptance_failure BEFORE INSERT ON user_collection_entry " *
        "BEGIN SELECT RAISE(ABORT,'favorites reorder fault'); END")
    records = [favorites_launch(binary, root, database, "reorder-degraded",
        joinpath(sources, "reorder-degraded.jsonl"))]
    favorites_database_rows(database) == baseline ||
        error("Failed reorder partially committed durable rows")
    push!(records, favorites_recovery_launch(binary, root, database;
        source=joinpath(sources, "reorder-recovery.jsonl")))
    recovered = favorites_database_rows(database)
    require_favorites_reorder(recovered, seed, [1, 2, 3])
    push!(records, favorites_launch(binary, root, database, "recovered-restore",
        joinpath(sources, "reorder-recovered-restore.jsonl")))
    favorites_database_rows(database) == recovered ||
        error("Recovered reorder changed on relaunch")
    return records
end

"""Exercise sampled swap rendering and reduced motion against independent user stores."""
function run_favorites_motion(binary::String, root::String)
    records = NamedTuple[]
    for (name, source, arguments) in (
        ("motion-landscape", "reorder-motion.jsonl", String[]),
        ("motion-portrait", "reorder-motion.jsonl",
            ["--layout=portrait", "--window-size=640x900"]),
        ("motion-short", "reorder-motion.jsonl",
            ["--layout=portrait", "--window-size=640x640"]),
        ("motion-reduced", "reorder-motion-reduced.jsonl", String[]))
        directory = joinpath(root, name)
        mkpath(directory)
        push!(records, favorites_launch(binary, directory,
            joinpath(directory, "user.sqlite3"), "acceptance",
            joinpath("tools", "scenarios", "favorites", source); arguments))
    end
    return records
end

"""Seed large durable membership and retained collections without custom collection UI."""
function run_favorites_capacity(binary::String, root::String)
    directory = joinpath(root, "capacity")
    mkpath(directory)
    database = joinpath(directory, "user.sqlite3")
    initialized = favorites_launch(binary, directory, database, "initialize",
        joinpath("tools", "scenarios", "favorites", "initialize.jsonl"))
    seed_favorites_capacity(database)
    before = favorites_database_rows(database)
    collections_before = favorites_collection_rows(database)
    maximum = favorites_launch(binary, directory, database, "maximum",
        joinpath("tools", "scenarios", "favorites", "capacity.jsonl"))
    after = favorites_database_rows(database)
    validate_favorites_capacity_rows(before, after)
    favorites_collection_rows(database) == collections_before ||
        error("Large save lost retained collections")
    restored = favorites_launch(binary, directory, database, "large-restore",
        joinpath("tools", "scenarios", "favorites", "large-restore.jsonl"))
    favorites_database_rows(database) == after ||
        error("Reopen changed durable membership")
    favorites_collection_rows(database) == collections_before ||
        error("Reopen changed retained collections")
    validate_favorites_storage(maximum, length(after))
    validate_favorites_storage(restored, length(after))
    require_setting_row(settings_database_rows(database), "drawing", "dust_limit", 1400)
    return [initialized, maximum, restored]
end

"""Inspect collection identities and metadata without decoding raw UUID blobs as text."""
function favorites_collection_rows(database::String)
    return favorites_fixture_sql(database,
        "SELECT hex(collection_id),system_role,display_name,collection_order,is_read_only " *
        "FROM user_collection ORDER BY collection_order")
end

"""Preserve untouched UUIDs, targets and names while Point is removed and re-added."""
function validate_favorites_capacity_rows(before, after)
    length(after) == length(before) || error("Large Favorites lost placements")
    point = last(after)
    point["custom_name"] == "Large store persisted name" ||
        error("Large store name edit did not persist")
    before_by_id = Dict(row["placement"] => row for row in before)
    haskey(before_by_id, point["placement"]) &&
        error("Re-added Point reused its removed placement UUID")
    previous = only(filter(row -> row["animation"] == point["animation"], before))
    [row["placement"] for row in after[1:end-1]] ==
        [row["placement"] for row in before if
            row["placement"] != previous["placement"]] ||
        error("Large save changed unrelated sibling order")
    for row in after[1:end-1]
        prior = before_by_id[row["placement"]]
        row["animation"] == prior["animation"] &&
            row["custom_name"] == prior["custom_name"] ||
            error("Large save changed an unrelated identity or name")
    end
    return nothing
end

"""Populate every eligible animation plus unavailable labels exceeding former text caps."""
function seed_favorites_capacity(database::String)
    source = joinpath(REPOSITORY_ROOT, ".build", "content", "content-records.jsonl")
    nodes = filter(record -> get(record, "kind", 0) == 7,
        JSON.parse.(readlines(source)))
    eligible = filter(record -> record["node_kind"] == 1, nodes)
    sql = "BEGIN;"
    for (index, record) in enumerate(eligible)
        animation = replace(string(UUID(record["animation_id"])), "-" => "")
        placement = replace(string(uuid4()), "-" => "")
        sql *= "INSERT INTO user_collection_entry VALUES(X'$placement'," *
            "X'4555434C494400008000000000000001',NULL,$(index - 1)," *
            "'animation',X'$animation',NULL);"
    end
    for index in 1:max(512, 1024 - length(eligible))
        animation = replace(string(uuid4()), "-" => "")
        placement = replace(string(uuid4()), "-" => "")
        label = "Unavailable $(lpad(index, 4, '0')) " * repeat("retained label ", 13)
        sql *= "INSERT INTO user_collection_entry VALUES(X'$placement'," *
            "X'4555434C494400008000000000000001',NULL,$(length(eligible) + index - 1)," *
            "'animation',X'$animation','$label');"
    end
    for index in 1:600
        collection = replace(string(uuid4()), "-" => "")
        sql *= "INSERT INTO user_collection VALUES(X'$collection',NULL," *
            "'Stored collection $index',$index,1);"
    end
    favorites_fixture_sql(database, sql * "COMMIT;")
    return nothing
end

"""Require separate display, joined replay and native TLSF diagnostics in the bundle."""
function validate_favorites_storage(record, placements::Int)
    evidence = JSON.parsefile(
        joinpath(REPOSITORY_ROOT, record.artifacts, "allocations.json"))
    sample = evidence["library"]
    sample["placement_count"] == placements && sample["collection_count"] == 601 ||
        error("Library TLSF evidence disagrees with the durable fixture")
    sample["replay_joined"] || error("Replay evidence was sampled before join")
    sample["semantic_text_bytes"] > 65536 ||
        error("Large fixture did not cross the former semantic text cap")
    sample["native_text_bytes"] > 32768 &&
        sample["native_control_count"] >= placements ||
        error("Large fixture did not cross the former native publication caps")
    for domain in ("display", "projection", "replay")
        sample[domain]["initialized"] || error("Missing $domain TLSF evidence")
        sample[domain]["growth_failure_count"] == 0 ||
            error("$domain TLSF admission failed")
    end
    return nothing
end
