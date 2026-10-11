struct StrokeFragmentInput {
    float4 position : SV_Position;
    float2 auxiliary : TEXCOORD0;
    float4 color : TEXCOORD1;
};

cbuffer StrokeFragmentUniforms : register(b0, space3) {
    float3 light_direction_view;
    float ambient;
    float diffuse;
    float material_roughness;
    float material_fresnel_0;
    float material_specular_tint;
    float material_shadow_limit;
    float radius;
    float stroke_mode;
    float strip_alpha;
    float2 segment_p0;
    float2 segment_p1;
    float3 strip_color;
    float strip_side_extent;
    float arc_intersections_enabled;
    float intersection_depth_width;
    float attachment_extent;
    uint occluder_count;
    float4 occluder_p0_p1[2];
    float4 occluder_radius_depths[2];
    float4 occluder_tangent[2];
};

float segment_distance(
    float2 sample_position, float2 segment_start, float2 segment_finish) {
    float2 segment = segment_finish - segment_start;
    float segment_squared = max(dot(segment, segment), 0.0001);
    float h = clamp(
        dot(sample_position - segment_start, segment) /
            segment_squared,
        0.0,
        1.0);
    return length(sample_position - segment_start - segment * h);
}

float3 srgb_to_linear(float3 value) {
    float3 low = value / 12.92;
    float3 high = pow((value + 0.055) / 1.055, 2.4);
    return lerp(low, high, value > 0.04045);
}

float3 linear_to_srgb(float3 value) {
    float3 low = value * 12.92;
    float3 high = 1.055 * pow(value, 1.0 / 2.4) - 0.055;
    return lerp(low, high, value > 0.0031308);
}

float stable_specular_lobe(float half_dot, float power) {
    float raw_lobe = pow(half_dot, power);
    return raw_lobe / (1.0 + fwidth(raw_lobe));
}

float4 main(StrokeFragmentInput input) : SV_Target0 {
    float2 fragment = input.position.xy;
    float coverage;
    float silhouette_distance;
    float source_alpha;
    float3 source_color;
    float3 normal;
    float3 view_direction = float3(0.0, 0.0, 1.0);
    float intersection_contact = 0.0;
    float intersection_visibility = 1.0;
    float weld_suppression = 0.0;

    if (stroke_mode > 0.5) {
        float3 tangent = normalize(input.color.rgb * 2.0 - 1.0);
        float3 side = cross(tangent, view_direction);
        side /= max(length(side), 0.0001);
        float3 front = normalize(cross(side, tangent));
        float x = (input.color.a * 2.0 - 1.0) * strip_side_extent;
        float strip_distance = abs(x) - 1.0;
        float coverage_width = max(fwidth(strip_distance), 0.0001);
        coverage = clamp(0.5 - strip_distance / coverage_width, 0.0, 1.0);
        x = clamp(x, -1.0, 1.0);
        float yz = max(1.0 - x * x, 0.0);
        normal = normalize(side * x + front * sqrt(yz));
        silhouette_distance = abs(x);
        source_alpha = strip_alpha;
        source_color = strip_color;
    } else {
        float2 direction_vector = segment_p1 - segment_p0;
        float direction_length = max(length(direction_vector), 0.0001);
        float2 direction = direction_vector / direction_length;
        float2 perpendicular = float2(-direction.y, direction.x);
        float2 relative = fragment - segment_p0;
        float axis_coordinate = dot(relative, direction);
        float parameter = clamp(axis_coordinate, 0.0, direction_length);
        float2 closest = segment_p0 + direction * parameter;
        float safe_radius = max(radius, 0.0001);
        float2 radial = (fragment - closest) / safe_radius;
        float radial_squared = dot(radial, radial);
        float capsule_distance = sqrt(radial_squared) - 1.0;
        float coverage_width = max(fwidth(capsule_distance), 0.0001);
        coverage = clamp(0.5 - capsule_distance / coverage_width, 0.0, 1.0);

        float signed_distance = dot(fragment - closest, perpendicular);
        float x = clamp(signed_distance / safe_radius, -1.0, 1.0);
        float yz = max(1.0 - x * x, 0.0);
        silhouette_distance = abs(x);
        if (axis_coordinate < 0.0 || axis_coordinate > direction_length) {
            normal = normalize(float3(
                radial, sqrt(max(1.0 - radial_squared, 0.0))));
            silhouette_distance = sqrt(radial_squared);
        } else {
            normal = normalize(float3(perpendicular * x, sqrt(yz)));
        }
        source_alpha = input.color.a;
        source_color = input.color.rgb;
    }

    if (coverage <= 0.0) {
        discard;
    }

    if (arc_intersections_enabled > 0.5) {
        float depth_radius = max(intersection_depth_width * 0.5, 0.0001);
        float arc_depth = input.auxiliary.x + normal.z * depth_radius;
        float arc_parameter = clamp(input.auxiliary.y, 0.0, 1.0);
        for (uint index = 0; index < min(occluder_count, 2u); index += 1) {
            float2 leg_p0 = occluder_p0_p1[index].xy;
            float2 leg_p1 = occluder_p0_p1[index].zw;
            float2 leg_segment = leg_p1 - leg_p0;
            float leg_length_squared = max(
                dot(leg_segment, leg_segment), 0.0001);
            float leg_parameter = clamp(
                dot(fragment - leg_p0, leg_segment) /
                    leg_length_squared,
                0.0,
                1.0);
            float2 leg_closest = leg_p0 + leg_segment * leg_parameter;
            float leg_radius = max(occluder_radius_depths[index].x, 0.0001);
            float leg_distance = length(fragment - leg_closest) - leg_radius;
            float overlap_width = max(fwidth(leg_distance), 0.75);
            float overlap = 1.0 - smoothstep(
                -overlap_width, overlap_width, leg_distance);

            float3 leg_tangent = normalize(occluder_tangent[index].xyz);
            float3 leg_side = normalize(cross(leg_tangent, view_direction));
            float3 leg_front = normalize(cross(leg_side, leg_tangent));
            float2 leg_direction = leg_segment / sqrt(leg_length_squared);
            float2 leg_perpendicular = float2(
                -leg_direction.y, leg_direction.x);
            float leg_x = clamp(
                dot(fragment - leg_closest, leg_perpendicular) /
                    leg_radius,
                -1.0,
                1.0);
            float3 leg_normal = normalize(
                leg_side * leg_x +
                leg_front * sqrt(max(1.0 - leg_x * leg_x, 0.0)));

            float leg_center_depth = lerp(
                occluder_radius_depths[index].y,
                occluder_radius_depths[index].z,
                leg_parameter);
            float leg_depth = leg_center_depth + leg_normal.z * depth_radius;
            float depth_delta = arc_depth - leg_depth;
            float depth_width = max(intersection_depth_width, 0.0001);
            float arc_in_front = smoothstep(
                -depth_width, depth_width, depth_delta);
            float depth_proximity = 1.0 - smoothstep(
                depth_width, depth_width * 2.0, abs(depth_delta));

            float attachment_distance = index == 0 ?
                arc_parameter : 1.0 - arc_parameter;
            float attachment = 1.0 - smoothstep(
                attachment_extent,
                attachment_extent * 1.5,
                attachment_distance);
            float weld = attachment * overlap;
            float visible_at_leg = lerp(arc_in_front, 1.0, weld);
            intersection_visibility *= lerp(1.0, visible_at_leg, overlap);

            float soft_union = overlap * depth_proximity *
                (1.0 - weld) * 0.24;
            float3 union_normal = normalize(normal + leg_normal);
            normal = normalize(lerp(
                normal, union_normal, max(soft_union, weld * 0.72)));
            intersection_contact += 0.06 * overlap * depth_proximity *
                (1.0 - weld);
            weld_suppression = max(weld_suppression, weld);
        }
        source_alpha *= intersection_visibility;
    }

    float3 light_direction = normalize(light_direction_view);
    float3 half_direction = normalize(light_direction + view_direction);
    float lambert = max(dot(normal, light_direction), 0.0);
    float half_dot = max(dot(normal, half_direction), 0.0);
    float view_dot = max(dot(normal, view_direction), 0.0);
    float roughness = clamp(material_roughness, 0.0, 1.0);
    float narrow_power = lerp(120.0, 24.0, roughness);
    float broad_power = max(narrow_power * 0.16, 6.0);
    float narrow_specular = stable_specular_lobe(half_dot, narrow_power);
    float broad_specular = stable_specular_lobe(half_dot, broad_power);

    float edge_dark = smoothstep(0.35, 1.0, silhouette_distance);
    float center_boost = pow(max(
        1.0 - silhouette_distance * silhouette_distance, 0.0), 0.28);
    float3 base = srgb_to_linear(source_color);
    float diffuse_band = ambient + diffuse * lambert;
    float tube_shape = (1.0 + 0.22 * center_boost) *
        (1.0 - 0.25 * edge_dark);
    float3 lit = base * diffuse_band * tube_shape;

    float contextual_darkening = intersection_contact;
    for (uint index = 0; index < min(occluder_count, 2u); index += 1) {
        float2 occluder_p0 = occluder_p0_p1[index].xy;
        float2 occluder_p1 = occluder_p0_p1[index].zw;
        float occluder_radius = occluder_radius_depths[index].x;
        float projected_light_length = max(length(light_direction.xy), 0.0001);
        float2 projected_light = light_direction.xy / projected_light_length;
        float2 shadow_offset = -projected_light * occluder_radius * 1.25;

        float shadow_distance = segment_distance(
            fragment,
            occluder_p0 + shadow_offset,
            occluder_p1 + shadow_offset) - occluder_radius;
        float shadow_width = max(fwidth(shadow_distance), 0.75);
        float shadow_mask = 1.0 - smoothstep(
            -shadow_width, shadow_width, shadow_distance);

        float contact_distance = max(segment_distance(
            fragment, occluder_p0, occluder_p1) - occluder_radius, 0.0);
        float contact_scale = max(occluder_radius * 1.5, 1.0);
        float contact_ratio = contact_distance / contact_scale;
        float contact_mask = exp(-0.5 * contact_ratio * contact_ratio);
        contextual_darkening +=
            (0.24 * shadow_mask + 0.10 * contact_mask) *
            (1.0 - weld_suppression);
    }
    lit *= 1.0 - min(contextual_darkening, material_shadow_limit);

    float3 material_fresnel = lerp(
        material_fresnel_0.xxx, base, material_specular_tint);
    float3 fresnel = material_fresnel + (1.0 - material_fresnel) *
        pow(1.0 - view_dot, 5.0);
    lit += fresnel *
        (0.42 * narrow_specular + 0.10 * broad_specular);

    lit = max(lit, base * 0.20);
    lit = clamp(lit, 0.0, 1.0);
    lit = linear_to_srgb(lit);
    return float4(lit, source_alpha * coverage);
}