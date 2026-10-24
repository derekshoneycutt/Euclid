module CompletionTests

using Test
using REPL

using Main.EuclidReplEvaluation: complete_input

const Fixture = Module(:CompletionFixture, true, true)
for name in ("PREFIXÉONE", "PREFIXÊTWO", "UNICODEÉONE", "UNICODEÉTWO")
    Core.eval(Fixture, :(const $(Symbol(name)) = 1))
end

@testset "Useful common prefixes and explicit alternatives" begin
    for explicit in (false, true)
        result = complete_input("func", 4;
            show_candidates=explicit, context_module=Fixture)
        @test result.found
        @test result.insertion == "function"
        @test (result.replacement_start, result.replacement_end) == (0, 4)
    end
    preview = complete_input("function", 8; show_candidates=false, context_module=Fixture)
    @test !preview.found && isempty(preview.insertion)
    alternatives = complete_input("function", 8; context_module=Fixture)
    @test !alternatives.found
    @test Set(split(alternatives.insertion)) == Set(("function", "functionloc"))
    result = complete_input("PREFIX", 6; show_candidates=false, context_module=Fixture)
    @test !result.found && isempty(result.insertion)
    @test REPL.LineEdit.common_prefix(["prefixéone", "prefixêtwo"]) == "prefix"
    source = "UNICODE"
    result = complete_input(source, ncodeunits(source);
        show_candidates=false, context_module=Fixture)
    @test result.found && result.insertion == "UNICODEÉ"
    @test (result.replacement_start, result.replacement_end) == (0, ncodeunits(source))
    source = "UNICODEÉ"
    result = complete_input(source, ncodeunits(source); context_module=Fixture)
    @test !result.found
    @test (result.replacement_start, result.replacement_end) == (0, ncodeunits(source))
end

@testset "Unique replacement and byte-correct regions" begin
    for source in ("α = printl", "begin\n    printl")
        result = complete_input(source, ncodeunits(source); context_module=Fixture)
        @test result.found && result.insertion == "println"
        @test result.replacement_start == ncodeunits(source) - 6
        @test result.replacement_end == ncodeunits(source)
    end
    result = complete_input("x=\\alpha", 8; context_module=Fixture)
    @test result.found && result.insertion == "α"
    @test (result.replacement_start, result.replacement_end) == (2, 8)
    source = "EuclidNonexistentCompletionXyz"
    result = complete_input(source, ncodeunits(source); context_module=Fixture)
    @test !result.found && isempty(result.insertion)
    for cursor in (-1, 0, 1, 4)
        result = complete_input("α", cursor; context_module=Fixture)
        @test !result.found && isempty(result.insertion)
    end
end

@testset "List-only method signatures never become insertions" begin
    for explicit in (false, true)
        result = complete_input("sin(", 4;
            show_candidates=explicit, context_module=Fixture)
        @test !result.found
        @test explicit ? !isempty(result.insertion) : isempty(result.insertion)
    end
end

end
