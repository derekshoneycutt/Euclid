package world

import native "../native"
import shapemodel "../../shapes/model"
import color "../../core/color"
import geometry "../../core/geometry"
import view_font "../font"
import shapes "../../shapes"
import projection "projection"
import viewtext "../ui/text"
import core "../../core"
import particlemodel "../../particles/model"
import particles "../../particles"

// Bound one label's copied glyph coverage; 64 glyphs of 16 centroids each.
FORMATION_LABEL_INK_CAPACITY :: 1024

// Own one display frame's current label anchors for every active label reveal.
Formation_Label_Preparation :: struct {
    anchors: [particlemodel.MAX_FORMATION_REVEALS]geometry.Vector3,
    ready: [particlemodel.MAX_FORMATION_REVEALS]bool,
}

// Prepare label ink targets from the owner-matched label draws and reattach anchors.
// Missing draws or pending glyphs leave targets untouched; authored time never waits.
prepare_formation_labels :: proc(
    ps: ^particlemodel.Particle_System, state: ^core.Euclid_General_State,
    encoder: ^native.Draw_Encoder) -> int {
    if ps == nil || state == nil {
        return 0
    }
    prepared: Formation_Label_Preparation
    for reveal_index in 0..<particlemodel.MAX_FORMATION_REVEALS {
        reveal := ps^.formation.reveals[reveal_index]
        if !reveal.active || reveal.kind != .Label {
            continue
        }
        draw, found := formation_cached_label_draw(
            &state^.shape_world, reveal.owner_entity)
        if !found {
            continue
        }
        prepared.anchors[reveal_index] = draw.point1
        prepared.ready[reveal_index] = true
        prepare_one_formation_label(ps, state, encoder, reveal_index, draw)
    }
    return particles.formation_refresh_label_targets(
        ps, prepared.anchors[:], prepared.ready[:])
}

// Recollect one label's ink only when its source, revision, or font size changed.
prepare_one_formation_label :: proc(
    ps: ^particlemodel.Particle_System, state: ^core.Euclid_General_State,
    encoder: ^native.Draw_Encoder, reveal_index: int,
    draw: shapemodel.Shapes_Label_Draw) {
    source, has_source := shapes.shape_world_draw_label_source(
        &state^.shape_world, draw)
    if !has_source {
        return
    }
    font_size := projection.effective_ink_size(
        draw.brush_size, state^.iso_scale,
        state^.ui_runtime.preferences.values.animation.scale_percent)
    signature := formation_label_signature(
        source, font_size, draw.source_revision)
    if ps^.formation.reveals[reveal_index].topology_signature == signature {
        return
    }
    ink: [FORMATION_LABEL_INK_CAPACITY]particlemodel.Formation_Label_Ink_Sample
    count, status := collect_formation_label_ink(
        state, encoder, source, draw, ink[:])
    if status == .Pending_Glyph {
        return
    }
    _ = particles.formation_store_label_targets(ps, reveal_index, {
        anchor = draw.point1,
        color = color.Color_RGBA8(draw.color),
        font_size = font_size,
        signature = signature,
    }, ink[:count])
}

// Copy shaped coverage through the crisp label's resolver relative to its anchor.
collect_formation_label_ink :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    source: string, draw: shapemodel.Shapes_Label_Draw,
    output: []particlemodel.Formation_Label_Ink_Sample) -> (
        int, viewtext.Ui_Text_Ink_Sample_Status) {
    screen := projection.iso_to_cartesian(draw.point1, state^.iso_scale)
    font_size := projection.effective_ink_size(
        draw.brush_size, state^.iso_scale,
        state^.ui_runtime.preferences.values.animation.scale_percent)
    ink: [FORMATION_LABEL_INK_CAPACITY]viewtext.Ui_Text_Ink_Sample
    count, status := viewtext.ui_text_collect_shaped_ink_samples({
        encoder = encoder,
        resolver = view_font.cache_terminal_resolver(&state^.font_cache),
        key = .Regular,
        text = source,
        position = geometry.Vector2{screen.x, screen.y},
        color = color.WHITE,
        font = {view_font.cache_borrow(&state^.font_cache, .Regular),
            font_size},
    }, ink[:])
    if status != .Ready {
        return 0, status
    }
    count = min(count, len(output))
    for index in 0..<count {
        output[index] = {
            offset = {ink[index].position.x - screen.x,
                ink[index].position.y - screen.y},
            coverage = ink[index].coverage,
        }
    }
    return count, .Ready
}

// Hash the label inputs that change glyph placement; anchors and zoom do not.
formation_label_signature :: proc(
    source: string, font_size: f32, revision: u32) -> u64 {
    signature := u64(1469598103934665603)
    for byte_value in transmute([]u8)source {
        signature = (signature ~ u64(byte_value)) * u64(1099511628211)
    }
    signature = (signature ~ u64(transmute(u32)font_size)) * u64(1099511628211)
    signature = (signature ~ u64(revision)) * u64(1099511628211)
    return max(signature, 1)
}

// Find the generation-matched cached label draw for one packed owner.
formation_cached_label_draw :: proc(
    world: ^shapemodel.Shape_World,
    owner_entity: u64) -> (shapemodel.Shapes_Label_Draw, bool) {
    entity := shapemodel.shape_entity_unpack(owner_entity)
    cache := &world^.draw_cache
    for item in cache^.items[:cache^.item_count] {
        label, is_label := item.(shapemodel.Shapes_Label_Draw)
        if is_label && label.source_index == int(entity.slot) - 1 &&
            label.source_generation == entity.generation {
            return label, true
        }
    }
    return {}, false
}

// Return one cached label draw's crisp ink opacity under its active formation.
formation_label_draw_opacity :: proc(
    state: ^core.Euclid_General_State,
    item: ^shapemodel.Shapes_Label_Draw) -> f32 {
    owner: shapemodel.Shape_Entity = {
        slot = u32(item^.source_index + 1),
        generation = item^.source_generation,
    }
    return particles.formation_label_opacity(
        &state^.particle_system, shapemodel.shape_entity_pack(owner))
}
