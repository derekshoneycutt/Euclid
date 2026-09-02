package dynview

import "../core"

Math_Stretch_Construction :: core.Font_Math_Stretch_Construction

Stretch_Recipe :: struct {
    count: int,
    parts: [core.FONT_MATH_GLYPH_PART_CAPACITY]core.Font_Math_Glyph_Part,
}

//   Return the smallest ready-made variant meeting the requested raw advance.
math_stretch_ready_variant :: proc(
    variants: core.Font_Math_Glyph_Variants,
    target_advance: i32) -> (core.Font_Math_Glyph_Variant, bool) {

    if !variants.valid || variants.count <= 0 ||
        variants.count > len(variants.values) || target_advance <= 0 {
        return {}, false
    }
    for index in 0..<variants.count {
        variant := variants.values[index]
        if variant.glyph_id == 0 || variant.advance <= 0 {
            return {}, false
        }
        if variant.advance >= target_advance {
            return variant, true
        }
    }
    return {}, false
}

//   Expand one recipe with the same repetition count for every extender.
math_stretch_expand_recipe :: proc(
    assembly: core.Font_Math_Glyph_Assembly,
    repetitions: int) -> (Stretch_Recipe, bool) {

    recipe: Stretch_Recipe
    if !assembly.valid || assembly.count <= 0 ||
        assembly.count > len(assembly.values) || repetitions < 0 {
        return {}, false
    }
    for index in 0..<assembly.count {
        part := assembly.values[index]
        copies := 1
        if part.extender {
            copies = repetitions
        }
        if copies > len(recipe.parts)-recipe.count {
            return {}, false
        }
        for _ in 0..<copies {
            recipe.parts[recipe.count] = part
            recipe.count += 1
        }
    }
    return recipe, recipe.count > 0
}

//   Return maximum connector overlaps and the recipe's smallest advance.
math_stretch_max_overlaps :: proc(
    recipe: Stretch_Recipe,
    overlaps: []f32) -> (f32, bool) {

    if recipe.count <= 0 || len(overlaps) < recipe.count-1 {
        return 0, false
    }
    advance := f32(recipe.parts[0].full_advance)
    for index in 1..<recipe.count {
        previous := recipe.parts[index-1]
        current := recipe.parts[index]
        overlap := f32(min(
            previous.end_connector_length, current.start_connector_length))
        if overlap < 0 {
            return 0, false
        }
        overlaps[index-1] = overlap
        advance += f32(current.full_advance) - overlap
    }
    return advance, advance > 0
}

//   Relax all connector overlaps equally without crossing the font minimum.
math_stretch_relax_overlaps :: proc(
    overlaps: []f32,
    min_overlap: f32,
    extra: f32) -> f32 {

    remaining := max(0, extra)
    for len(overlaps) > 0 && remaining > 0 {
        active_count := 0
        share := remaining / f32(len(overlaps))
        consumed: f32
        for &overlap in overlaps {
            reduction := min(max(0, overlap-min_overlap), share)
            overlap -= reduction
            consumed += reduction
            if overlap > min_overlap {
                active_count += 1
            }
        }
        remaining -= consumed
        if consumed <= 0 || active_count == 0 {
            break
        }
    }
    return extra - remaining
}

//   Build one positioned bottom-up construction from a validated recipe.
math_stretch_position_recipe :: proc(
    recipe: Stretch_Recipe,
    overlaps: []f32,
    assembly: core.Font_Math_Glyph_Assembly) -> Math_Stretch_Construction {

    result := Math_Stretch_Construction{
        valid = true, assembled = true,
        generation = assembly.generation,
        base_glyph_id = assembly.base_glyph_id,
        italic_correction = f32(assembly.italic_correction),
        count = recipe.count,
    }
    for index in 0..<recipe.count {
        part := recipe.parts[index]
        result.parts[index] = {
            glyph_id = part.glyph_id,
            advance_offset = result.advance,
            extents = part.extents,
        }
        result.advance += f32(part.full_advance)
        if index < recipe.count-1 {
            result.advance -= overlaps[index]
        }
    }
    return result
}

//   Select a ready-made variant or construct the smallest symmetric assembly.
math_stretch_select :: proc(
    variants: core.Font_Math_Glyph_Variants,
    assembly: core.Font_Math_Glyph_Assembly,
    generation: u64,
    target_advance: i32) -> Math_Stretch_Construction {

    if generation == 0 || target_advance <= 0 {
        return {}
    }
    variant, ready := math_stretch_ready_variant(variants, target_advance)
    if variants.generation == generation && ready {
        result := Math_Stretch_Construction{
            valid = true, generation = generation,
            base_glyph_id = variants.base_glyph_id,
            advance = f32(variant.advance), count = 1,
            top_accent_attachment = f32(variant.top_accent_attachment),
        }
        result.parts[0] = {glyph_id = variant.glyph_id, extents = variant.extents}
        return result
    }
    if assembly.generation != generation {
        return {}
    }
    overlaps: [core.FONT_MATH_GLYPH_PART_CAPACITY-1]f32
    for repetitions in 0..=core.FONT_MATH_GLYPH_PART_CAPACITY {
        recipe, expanded := math_stretch_expand_recipe(assembly, repetitions)
        if !expanded {
            continue
        }
        minimum, measured := math_stretch_max_overlaps(
            recipe, overlaps[:recipe.count-1])
        if !measured {
            return {}
        }
        capacity: f32
        for overlap in overlaps[:recipe.count-1] {
            capacity += max(0, overlap-f32(assembly.min_connector_overlap))
        }
        if f32(target_advance) <= minimum+capacity {
            _ = math_stretch_relax_overlaps(overlaps[:recipe.count-1],
                f32(assembly.min_connector_overlap), f32(target_advance)-minimum)
            return math_stretch_position_recipe(
                recipe, overlaps[:recipe.count-1], assembly)
        }
    }
    return {}
}