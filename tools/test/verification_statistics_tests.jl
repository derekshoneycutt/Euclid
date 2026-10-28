import OdinJuliaAnalysis

@testset "Euclid SQL statistics consumer" begin
    mktempdir() do root
        path = joinpath(root, "query.sql")
        for source in ("SELECT ?1 AS value;", "ALTER TABLE t RENAME TO u; SELECT ?1;")
            write(path, source)
            file = OdinJuliaAnalysis.analyze_file(
                "query.sql", path, source, "sql", false, 0)
            statistics = OdinJuliaAnalysis.calculate_repository_statistics(
                [file], OdinJuliaAnalysis.FunctionAnalysis[])
            encoded = Verification.JSON.json((statistics=statistics,))
            report = Verification.JSON.parse(encoded)
            phase = Verification.PhaseResult(
                "Repository analysis", "SQL scope", UInt64(1), "PASS", "",
                Dict{String, Any}("report" => report))
            output = IOBuffer()
            Verification.write_statistics(output, phase, false)
            text = String(take!(output))
            @test occursin("| SQLite", text)
            @test occursin("Procedural total", text)
            @test !occursin("Shared source:", text)
            @test !occursin("SQLite lexical coverage:", text)
            @test !occursin("Estimate inputs:", text)
            @test occursin("\u2014 (not applicable", text)
            @test occursin(r"\+-+\+\nCOCOMO/LOCOMO:", text)
            @test Verification.code_statistics_row("SQLite",
                report.statistics.code_by_language.sql)[3:4] == ["\u2014", "\u2014"]
            @test !occursin("SQLite inventory:", text)
            @test !occursin("SQLite reason:", text)
        end
    end
end
