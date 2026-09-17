package shader

import "core:testing"

// Verify both production contracts declare every required ABI surface.
@(test)
production_shader_contracts_declare_requirements :: proc(t: ^testing.T) {
    contracts := [2]Shader_Program_Contract{
        STROKE3D_CONTRACT,
        DUST_INSTANCED_CONTRACT,
    }
    for contract in contracts {
        testing.expect(t, contract.revision > 0)
        testing.expect(t, len(contract.vertex_asset) > 0)
        testing.expect(t, len(contract.fragment_asset) > 0)
        testing.expect(t, len(contract.uniforms) > 0)
        testing.expect(t, len(contract.attributes) > 0)
        for requirement in contract.uniforms {
            testing.expect(t, requirement.required)
            testing.expect(t, requirement.name != nil)
        }
        for requirement in contract.attributes {
            testing.expect(t, requirement.required)
            testing.expect(t, len(requirement.name) > 0)
            testing.expect(t, requirement.component_count > 0)
        }
    }
}

// Verify one missing required location reports its exact descriptor entry.
@(test)
missing_shader_requirement_is_reported :: proc(t: ^testing.T) {
    contract := DUST_INSTANCED_CONTRACT
    locations := [DUST_INSTANCED_UNIFORM_COUNT]i32{4, -1}

    result := validate_uniform_locations(&contract, locations[:])

    testing.expect_value(t, result.failure, Validation_Failure.Missing_Uniform)
    testing.expect_value(t, result.requirement_index, 1)
}

// Verify validation count mismatches cannot silently omit contract entries.
@(test)
shader_location_count_must_match_contract :: proc(t: ^testing.T) {
    contract := DUST_INSTANCED_CONTRACT
    locations := [1]i32{4}

    result := validate_uniform_locations(&contract, locations[:])

    testing.expect_value(t, result.failure, Validation_Failure.Location_Count)
}

// Verify each invalid program selects its explicitly declared fallback.
@(test)
invalid_shader_contract_selects_declared_fallback :: proc(t: ^testing.T) {
    stroke := STROKE3D_CONTRACT
    dust := DUST_INSTANCED_CONTRACT
    validation := Validation_Result{failure = .Missing_Uniform}

    stroke_fallback, stroke_selected := fallback_for_validation(&stroke, validation)
    dust_fallback, dust_selected := fallback_for_validation(&dust, validation)

    testing.expect(t, stroke_selected && dust_selected)
    testing.expect_value(t, stroke_fallback, Shader_Fallback_Kind.Tool_Primitives)
    testing.expect_value(t, dust_fallback, Shader_Fallback_Kind.Dust_Immediate_Quads)
}