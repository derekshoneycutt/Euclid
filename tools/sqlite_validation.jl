module EuclidSQLiteValidation

using SHA
using TOML
using Test
using UUIDs

const ROOT = abspath(joinpath(@__DIR__, ".."))
const CACHE = joinpath(ROOT, ".build", "sqlite-validator")
const STRICT_FLAGS = [
    "-vet", "-strict-style", "-disallow-do", "-warnings-as-errors",
]

"""Load JSON only for runner tests, keeping provider builds independent of test packages."""
function load_test_dependencies()
    @eval import JSON
    return nothing
end

"""Return the stable consumer-owned executable named by Euclid analysis settings."""
published_runner_path() = joinpath(
    CACHE, Sys.iswindows() ? "sqlite-validator.exe" : "sqlite-validator")

"""Publish a verified cached runner before the analyzer is asked to execute cases."""
function prepare_runner(artifact, linker_flags::String)
    cached = build_runner(artifact, linker_flags)
    published = published_runner_path()
    isfile(published) && open(sha256, published) == open(sha256, cached) &&
        return published
    candidate = published * ".candidate-" * string(uuid4())
    try
        cp(cached, candidate; force=true)
        mv(candidate, published; force=true)
    finally
        isfile(candidate) && rm(candidate; force=true)
    end
    return published
end

"""Identify all runner, substrate, binding, compiler, and exact-provider build inputs."""
function runner_fingerprint(artifact, linker_flags::String)
    inputs = String["euclid-sqlite-validator-v1", string(Sys.KERNEL), string(Sys.ARCH),
        artifact.fingerprint, bytes2hex(open(sha256, artifact.archive_path)),
        linker_flags, read(`odin version`, String), STRICT_FLAGS...]
    for root in ("tools/sqlite_validator", "src/sqlite", "libs/sqlite3")
        paths = sort(filter(path -> endswith(path, ".odin"),
            [joinpath(directory, name)
                for (directory, _, names) in walkdir(joinpath(ROOT, root))
                for name in names]))
        for path in paths
            push!(inputs, relpath(path, ROOT), bytes2hex(open(sha256, path)))
        end
    end
    push!(inputs, bytes2hex(open(sha256, @__FILE__)))
    return bytes2hex(sha256(join(inputs, '\0')))
end

"""Reuse only a digest-verified strict binary built against Euclid's own SQLite archive."""
function build_runner(artifact, linker_flags::String; cache_root::String=CACHE)
    fingerprint = runner_fingerprint(artifact, linker_flags)
    directory = joinpath(cache_root, fingerprint)
    executable = joinpath(directory, Sys.iswindows() ? "sqlite-validator.exe" : "sqlite-validator")
    manifest = joinpath(directory, "identity.toml")
    if isfile(executable) && isfile(manifest)
        identity = try
            TOML.parsefile(manifest)
        catch error
            error isa TOML.ParserError || rethrow()
            Dict{String,Any}()
        end
        get(identity, "fingerprint", "") == fingerprint &&
            get(identity, "sha256", "") == bytes2hex(open(sha256, executable)) &&
            return executable
    end
    mkpath(directory)
    candidate = executable * ".candidate-" * string(uuid4()) *
        (Sys.iswindows() ? ".exe" : "")
    command = Cmd(["odin", "build", joinpath(ROOT, "tools", "sqlite_validator"),
        "-out:$candidate", STRICT_FLAGS..., "-extra-linker-flags:$linker_flags"])
    try
        run(pipeline(addenv(Cmd(command; dir=ROOT),
            "TMPDIR" => directory, "TEMP" => directory, "TMP" => directory), stdout=stderr))
        mv(candidate, executable; force=true)
        open(manifest, "w") do io
            TOML.print(io, Dict("fingerprint" => fingerprint,
                "provider_fingerprint" => artifact.fingerprint,
                "sha256" => bytes2hex(open(sha256, executable))))
        end
    finally
        isfile(candidate) && rm(candidate; force=true)
    end
    return executable
end

"""Create a digest-bound fixture with explicit lexical bind evidence."""
function fixture(sql::String; id="operation", mode="execute", role="operation",
    binds=Any[], tokens=Any[])
    return Dict("id" => id, "role" => role, "mode" => mode,
        "source_id" => "fixture:runner:$id", "source" => sql,
        "digest" => bytes2hex(sha256(sql)), "binds" => binds, "bind_tokens" => tokens)
end

"""Create a protocol-v1 case that remains independent of analyzer implementation."""
function request(steps; requirements=String[], id="runner")
    return Dict("protocol_version" => 1, "case_id" => id,
        "requirements" => requirements, "steps" => steps)
end

"""Return a lossless typed wire binding."""
binding(slot, type, value) = Dict("slot" => slot, "type" => type, "value" => value)

"""Locate fixture-only parameter spellings using one-based half-open UTF-8 bytes."""
function token(sql::String, text::String; occurrence=1)
    matches = collect(findall(text, sql))
    span = matches[occurrence]
    return Dict("first_byte" => first(span),
        "after_last_byte" => last(span) + ncodeunits(last(text)), "text" => text)
end

"""Run one owned case with bounded timeout and concurrent stdout/stderr draining."""
function invoke_runner(executable::String, payload; timeout=10.0, raw=false)
    encoded = raw ? payload : JSON.json(payload)
    output = Pipe()
    errors = Pipe()
    input = Pipe()
    process = run(pipeline(ignorestatus(Cmd(Cmd([executable]); dir=ROOT)),
        stdin=input, stdout=output, stderr=errors); wait=false)
    close(input.out)
    close(output.in)
    close(errors.in)
    stdout_task = @async read(output, String)
    stderr_task = @async read(errors, String)
    writer = @async begin
        try
            write(input, encoded)
        catch error
            error isa Base.IOError || rethrow()
        finally
            close(input.in)
        end
    end
    timed_out = timedwait(
        () -> process_exited(process), timeout; pollint=0.01) == :timed_out
    timed_out && kill(process)
    wait(process)
    wait(writer)
    stdout = fetch(stdout_task)
    stderr_text = fetch(stderr_task)
    close(output)
    close(errors)
    close(input)
    return (; exit_code=success(process) ? 0 : max(1, process.exitcode),
        stdout, stderr=stderr_text, timed_out)
end

"""Require complete cleanup and identity echo, independently parsing the native response."""
function checked_case(executable::String, payload; passed=true)
    response = invoke_runner(executable, payload)
    @test !response.timed_out
    @test response.exit_code == 0
    @test isempty(response.stderr)
    result = JSON.parse(response.stdout)
    @test result["protocol_version"] == 1
    @test result["case_id"] == payload["case_id"]
    @test result["completed"]
    @test result["cleanup"]["closed"]
    @test result["status"] == (passed ? "passed" : "failed")
    @test !isempty(result["provider"]["identity"])
    @test occursin(r"^\d+\.\d+\.\d+", result["provider"]["version"])
    @test Set(result["provider"]["capabilities"]) == Set(["fts5", "spellfix1"])
    for (step, declared) in zip(result["steps"], payload["steps"])
        @test all(step[key] == declared[key] for key in ("id", "source_id", "digest", "mode"))
        if step["status"] == "passed"
            @test step["prepared"]
            @test step["executed"] == (step["mode"] == "execute")
            @test step["processed_bytes"] == ncodeunits(declared["source"])
        end
    end
    if passed
        @test result["failure"] === nothing
        @test result["transaction_complete"]
        @test result["cleanup"]["finalized"]
        @test all(step["status"] == "passed" for step in result["steps"])
    else
        @test result["failure"] !== nothing
    end
    return result
end

"""Exercise complete native tails, typed values, modes, guards, provider, and failure cleanup."""
function test_runner(executable::String)
    @testset "Euclid exact-provider SQLite validation runner" begin
        test_scripts(executable)
        test_bindings(executable)
        test_failures(executable)
        test_protocol(executable)
    end
    return 0
end

"""Prove cache reuse, digest-based repair, and compiler/provider/linker identity partitioning."""
function test_cache(artifact, linker_flags::String)
    root = joinpath(CACHE, "cache-tests")
    try
        @testset "SQLite runner cache provenance" begin
            executable = build_runner(artifact, linker_flags; cache_root=root)
            identity = TOML.parsefile(joinpath(dirname(executable), "identity.toml"))
            stamp = stat(executable).mtime
            @test build_runner(artifact, linker_flags; cache_root=root) == executable
            @test stat(executable).mtime == stamp
            open(executable, "a") do io
                write(io, "invalid-cache-bytes")
            end
            corrupted = bytes2hex(open(sha256, executable))
            @test build_runner(artifact, linker_flags; cache_root=root) == executable
            repaired = TOML.parsefile(joinpath(dirname(executable), "identity.toml"))
            @test bytes2hex(open(sha256, executable)) != corrupted
            @test repaired["sha256"] == bytes2hex(open(sha256, executable))
            @test repaired["fingerprint"] == identity["fingerprint"]
            @test repaired["provider_fingerprint"] == identity["provider_fingerprint"]
            @test invoke_runner(executable, request([fixture("SELECT 1;")])).exit_code == 0
            provider = (; fingerprint=artifact.fingerprint * "-different-provider",
                archive_path=artifact.archive_path)
            @test runner_fingerprint(provider, linker_flags) !=
                runner_fingerprint(artifact, linker_flags)
            @test runner_fingerprint(artifact, linker_flags * " ") !=
                runner_fingerprint(artifact, linker_flags)
        end
    finally
        isdir(root) && rm(root; recursive=true)
    end
    return nothing
end

"""Prove native scripts retain TEMP state, triggers, comments, and prepare-only distinction."""
function test_scripts(executable::String)
    @testset "scripts and modes" begin
        setup = fixture("CREATE TEMP TABLE t(x INTEGER); CREATE TABLE log(x); " *
            "CREATE TRIGGER tr AFTER INSERT ON t BEGIN INSERT INTO log VALUES(new.x); " *
            "INSERT INTO log VALUES(new.x+1); END; INSERT INTO t VALUES(1); -- tail\n";
            id="setup", role="setup")
        # TEMP triggers must target tables in a compatible schema.
        setup["source"] = replace(setup["source"], "CREATE TRIGGER" => "CREATE TEMP TRIGGER")
        setup["digest"] = bytes2hex(sha256(setup["source"]))
        operation = fixture("SELECT * FROM log; SELECT * FROM t; /* trailing */";
            mode="prepare")
        result = checked_case(executable, request([setup, operation]))
        @test result["steps"][1]["statement_count"] == 4
        @test result["steps"][2]["statement_count"] == 2
        checked_case(executable, request([fixture("-- empty\n /* comment */")]))
        checked_case(executable, request([fixture("BEGIN; CREATE TABLE t(x); COMMIT;")]))
        for (requirement, sql) in [
            ("fts5", "CREATE VIRTUAL TABLE t USING fts5(x); INSERT INTO t VALUES('hello'); SELECT * FROM t;"),
            ("spellfix1", "CREATE VIRTUAL TABLE t USING spellfix1; INSERT INTO t(word) VALUES('hello'); SELECT * FROM t;"),
        ]
            checked_case(executable, request([fixture(sql)]; requirements=[requirement]))
        end
        sql = "CREATE VIRTUAL TABLE t USING fts5(x, tokenize='unicode61 :ignored');"
        result = checked_case(executable, request([fixture(sql;
            tokens=[token(sql, ":ignored")])]; requirements=["fts5"]); passed=false)
        @test result["failure"]["phase"] != "bind"
        sql = "CREATE VIRTUAL TABLE t USING fts5(x :ignored);"
        checked_case(executable, request([fixture(sql; mode="prepare",
            tokens=[token(sql, ":ignored")])];
            requirements=["fts5"]))
    end
end

"""Execute constraint-backed assertions that verify every transported value and storage class."""
function test_typed_values(executable::String)
    @testset "typed values" begin
        cases = [
            ("integer", string(typemin(Int64)), "typeof(?1)='integer' AND ?1=-9223372036854775808"),
            ("integer", string(typemax(Int64)), "typeof(?1)='integer' AND ?1=9223372036854775807"),
            ("real", 1.25, "typeof(?1)='real' AND ?1=1.25"),
            ("real", 2, "typeof(?1)='real' AND ?1=2.0"),
            ("null", nothing, "?1 IS NULL"),
            ("text", "", "typeof(?1)='text' AND length(?1)=0"),
            ("text", "é\0x", "typeof(?1)='text' AND hex(?1)='C3A90078'"),
            ("blob", "", "typeof(?1)='blob' AND length(?1)=0"),
            ("blob", "00ff12", "typeof(?1)='blob' AND hex(?1)='00FF12'"),
        ]
        for (type, value, predicate) in cases
            sql = "CREATE TABLE t(x CHECK(x)); INSERT INTO t VALUES(($predicate));"
            spans = [Dict("first_byte" => first(span), "after_last_byte" => last(span)+1,
                "text" => "?1") for span in findall("?1", sql)]
            checked_case(executable, request([fixture(sql;
                binds=[binding(1, type, value)], tokens=spans)]))
        end
    end
end

"""Check sparse, repeated, anonymous, and named native slot assignment."""
function test_bindings(executable::String)
    test_typed_values(executable)
    @testset "native binding slots" begin
        for sql in [
            "SELECT ?5;",
            "SELECT ?5, ?5;",
            "SELECT :a, :a, ?, ?2;",
            "SELECT ?, ?, ?;",
            "SELECT :α, @β, \$γ;",
            "SELECT ?01, ?1;",
            "SELECT 1; SELECT :a; SELECT ?1;",
        ]
            spans = [Dict("first_byte" => match.offset,
                "after_last_byte" => match.offset+ncodeunits(match.match), "text" => match.match)
                for match in eachmatch(r"\?[0-9]*|[:@\$][\p{L}]+", sql)]
            slots = occursin("?5", sql) ? [5] :
                occursin("?, ?, ?", sql) || occursin(":α", sql) ? [1, 2, 3] :
                occursin(":a, :a", sql) ? [1, 2] : [1]
            checked_case(executable, request([fixture(sql; tokens=spans,
                binds=[binding(slot, "integer", "4") for slot in slots])]))
        end
        sql = "SELECT ?5;"
        for binds in [Any[], [binding(5, "null", nothing), binding(1, "null", nothing)]]
            result = checked_case(executable, request([fixture(sql;
                binds, tokens=[token(sql, "?5")])]); passed=false)
            @test result["failure"]["phase"] == "bind"
        end
        result = checked_case(executable, request([fixture("SELECT ?;")]); passed=false)
        @test result["failure"]["phase"] == "bind"
    end
end

"""Verify late SQL failures, setup dependency skips, real cleanup, and denied file access."""
function test_failure_phases(executable::String)
    @testset "native failure phases and authorization" begin
        for (sql, phase) in [
            ("SELECT 1; SELECT * FROM missing;", "prepare"),
            ("SELECT 1; SELECT abs(-9223372036854775808);", "step"),
            ("SELECT CASE column1 WHEN 2 THEN abs(-9223372036854775808) " *
                "ELSE 1 END FROM (VALUES(1),(2));", "step"),
            ("ATTACH '.build/sqlite-validator/forbidden.db' AS other;", "prepare"),
            ("VACUUM INTO '.build/sqlite-validator/forbidden.db';", "step"),
            ("SELECT load_extension('forbidden');", "prepare"),
            ("PRAGMA temp_store_directory='.';", "prepare"),
            ("PRAGMA data_store_directory='.';", "prepare"),
            ("PRAGMA temp_store_directory;", "prepare"),
            ("PRAGMA data_store_directory;", "prepare"),
            ("PRAGMA temp_store=FILE;", "prepare"),
            ("SELECT readfile('.build/sqlite-validator/forbidden.db');", "prepare"),
            ("SELECT writefile('.build/sqlite-validator/forbidden.db','x');", "prepare"),
            ("CREATE VIRTUAL TABLE t USING fts5(x);", "prepare"),
            ("CREATE VIRTUAL TABLE t USING fts5vocab(absent, 'row');", "prepare"),
            ("CREATE VIRTUAL TABLE t USING spellfix1;", "prepare"),
            ("CREATE VIRTUAL TABLE t USING unknown_module(x);", "prepare"),
            ("BEGIN;", "transaction"),
        ]
            result = checked_case(executable, request([fixture(sql)]); passed=false)
            @test (phase == "transaction" ? result["failure"] :
                result["steps"][1]["failure"])["phase"] == phase
            @test result["failure"]["primary_code"] != 0
            @test result["failure"]["extended_code"] != 0
            @test !isempty(result["failure"]["message"])
            @test phase != "transaction" || !result["transaction_complete"]
            @test result["cleanup"]["finalized"] || result["failure"]["phase"] == "finalize"
        end
    end
end

"""Verify rollback evidence, dependent-step skips, complete tails, and timeout isolation."""
function test_failures(executable::String)
    test_failure_phases(executable)
    @testset "failure cleanup and isolation" begin
        result = checked_case(executable, request([
            fixture("BEGIN; CREATE TABLE t(x UNIQUE); INSERT INTO t VALUES(1),(1);";
                id="setup", role="setup"), fixture("SELECT 1;")]); passed=false)
        @test !result["transaction_complete"]
        @test result["steps"][2]["status"] == "skipped"
        @test !result["steps"][2]["attempted"]
        result = checked_case(executable, request([fixture("SELECT 1;")];
            requirements=["unavailable"]); passed=false)
        @test result["failure"]["phase"] == "capability"
        @test result["steps"][1]["status"] == "skipped"
        checked_case(executable, request([fixture("SELECT 1;")]))
        @test !isfile(joinpath(CACHE, "forbidden.db"))
        result = checked_case(executable, request([fixture("SELECT 1; SELECT FROM;")]);
            passed=false)
        @test result["steps"][1]["statement_count"] == 1
        @test 0 < result["steps"][1]["processed_bytes"] < ncodeunits("SELECT 1; SELECT FROM;")
        @test result["steps"][1]["failure"]["offset"] > ncodeunits("SELECT 1;")
        checked_case(executable, request([fixture(
            "PRAGMA page_size=4096; PRAGMA journal_mode=OFF; PRAGMA synchronous=OFF; " *
            "PRAGMA locking_mode=EXCLUSIVE; PRAGMA temp_store=MEMORY;")]))
        sql = "WITH RECURSIVE n(x) AS (VALUES(0) UNION ALL SELECT x+1 FROM n) SELECT sum(x) FROM n;"
        response = invoke_runner(executable, request([fixture(sql)]); timeout=0.2)
        @test response.timed_out
        checked_case(executable, request([fixture("SELECT 1;")]))
    end
end

"""Reject malformed wire requests rather than returning misleading SQL validation evidence."""
function test_protocol(executable::String)
    @testset "protocol rejection" begin
        for payload in ["{", "{}", "[]", "{\"protocol_version\":2}", "null",
            JSON.json(request([merge(fixture("SELECT 1;"), Dict("digest" => "0"^64))])),
            JSON.json(merge(request([fixture("SELECT 1;")]), Dict("protocol_version" => 2))),
            JSON.json(request([fixture("SELECT ?1;"; binds=[binding(1, "integer", 1)])])),
            JSON.json(request([fixture("SELECT 1;"; binds=[Dict("slot" => 1, "type" => "null")])])),
            JSON.json(request([fixture("SELECT 1;"; binds=[binding(1, "blob", "FF")])])),
            JSON.json(request([fixture("SELECT 1;"; binds=[binding(1, "integer", "9223372036854775808")])])),
            JSON.json(request([fixture("SELECT 1;"; binds=[binding(1, "integer", "-9223372036854775809")])])),
            JSON.json(request([fixture("SELECT 1;"; binds=[
                binding(1, "null", nothing), binding(1, "null", nothing)])])),
            JSON.json(request([fixture("SELECT 1;"; id="same"), fixture("SELECT 2;"; id="same")])),
            JSON.json(request([fixture("SELECT 1;"; mode="unknown")])),
            JSON.json(request([merge(fixture("SELECT 1;"), Dict("binds" => nothing))])),
            JSON.json(request([merge(fixture("SELECT 1;"), Dict("source_id" => "../query.sql"))])),
            JSON.json(request([fixture(" "^((1024*1024)+1))])),
            JSON.json(request([fixture(""; id="step$index") for index in 1:257])),
            " "^(8*1024*1024+1),
            JSON.json(request([fixture("SELECT 1;"; tokens=[Dict(
                "first_byte" => 1, "after_last_byte" => 3, "text" => ":x")])])),
        ]
            result = invoke_runner(executable, payload; raw=true)
            @test result.exit_code != 0
            @test isempty(result.stdout)
            @test !isempty(result.stderr)
            @test ncodeunits(result.stderr) < 4096
        end
    end
end

"""Validate real subprocess results through the analyzer-owned request and result contract."""
function test_analyzer(executable::String)
    engine = OdinJuliaAnalysis
    @testset "Analyzer/native SQLite protocol integration" begin
        setup = engine.SQLiteFixtureStep("setup",
            "CREATE TEMP TABLE t(x); INSERT INTO t VALUES(1);")
        query = "SELECT ?5, :named, ?, ?5 FROM t; -- full tail\n"
        operation = engine.SQLiteFileStep("native", "query.sql"; bindings=[
            engine.SQLiteBind(5, engine.SQLiteInteger(typemin(Int64))),
            engine.SQLiteBind(6, engine.SQLiteText("a\0β")),
            engine.SQLiteBind(7, engine.SQLiteBlob(UInt8[]))])
        case = engine.SQLiteValidationCase("native"; steps=[setup, operation])
        sources = Dict("query.sql" => engine.SQLEngine.analyze(query))
        payload = engine.sqlite_case_request(case, sources)
        process = invoke_runner(executable, payload)
        @test process.exit_code == 0
        result = engine.sqlite_case_result(
            JSON.parse(process.stdout), payload, process.stderr)
        @test result.status == "passed"
        @test result.steps[2].executed
        runner = engine.SQLiteRunnerSettings([executable])
        @test engine.run_sqlite_case(ROOT, case, runner, sources).status == "passed"
        test_analyzer_failures(runner)
        @test engine.run_sqlite_case(ROOT, case, runner, sources).status == "passed"
        @test engine.SQLITE_REQUEST_LIMIT == 8*1024*1024
        @test engine.SQLITE_SOURCE_LIMIT == 1024*1024
        @test engine.SQLITE_STDOUT_LIMIT == 2*1024*1024
        @test engine.SQLITE_STEP_LIMIT == 256
    end
    return 0
end

"""Check analyzer reconciliation of native failure phases, module admission, and timeout isolation."""
function test_analyzer_failures(runner)
    engine = OdinJuliaAnalysis
    @testset "Analyzer/native failure evidence" begin
        for sql in [
            "SELECT 1; SELECT * FROM absent;",
            "SELECT abs(-9223372036854775808);",
            "BEGIN; SELECT abs(-9223372036854775808);",
            "BEGIN;",
            "ATTACH '.build/sqlite-validator/forbidden.db' AS other;",
        ]
            failed = engine.SQLiteValidationCase("failure"; steps=[
                engine.SQLiteFixtureStep("failure", sql),
                engine.SQLiteFixtureStep("skip", "SELECT 1;")])
            result = engine.run_sqlite_case(ROOT, failed, runner, Dict())
            @test result.status == "failed"
            @test result.message === nothing
        end
        unavailable = engine.SQLiteValidationCase(
            "capability"; requirements=["unavailable"],
            steps=[engine.SQLiteFixtureStep("skip", "SELECT 1;")])
        result = engine.run_sqlite_case(ROOT, unavailable, runner, Dict())
        @test result.status == "incomplete"
        @test result.failure.phase == "capability"
        @test result.provider !== nothing
        test_analyzer_modules(runner)
        forever = engine.SQLiteValidationCase("timeout"; timeout_seconds=0.2, steps=[
            engine.SQLiteFixtureStep("loop",
                "WITH RECURSIVE n(x) AS (VALUES(0) UNION ALL SELECT x+1 FROM n) " *
                "SELECT sum(x) FROM n;")])
        result = engine.run_sqlite_case(ROOT, forever, runner, Dict())
        @test result.status == "incomplete"
    end
    return 0
end

"""Check analyzer capability reconciliation for each supported native module."""
function test_analyzer_modules(runner)
    engine = OdinJuliaAnalysis
    for requirement in ("fts5", "spellfix1")
        sql = requirement == "fts5" ?
            "CREATE VIRTUAL TABLE t USING fts5(x); " *
                "INSERT INTO t VALUES('hello'); " *
                "CREATE VIRTUAL TABLE vocabulary USING fts5vocab(t, 'row'); " *
                "SELECT * FROM vocabulary;" :
            "CREATE VIRTUAL TABLE t USING spellfix1;"
        available = engine.SQLiteValidationCase(
            requirement; requirements=[requirement],
            steps=[engine.SQLiteFixtureStep("module", sql)])
        result = engine.run_sqlite_case(ROOT, available, runner, Dict())
        @test result.status == "passed"
    end
end

end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) == 2 && ARGS[1] == "analyzer-test" ||
        error("Use julia tools/make.jl sqlite-runner-test.")
    @eval EuclidSQLiteValidation begin
        import JSON
        import OdinJuliaAnalysis
    end
    exit(Base.invokelatest(EuclidSQLiteValidation.test_analyzer, ARGS[2]))
end
