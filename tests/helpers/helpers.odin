package test_helpers

import "core:math"
import "core:testing"

import app_kine "../../src/kine"

EPS :: f32(1e-5)

expect_vec3_close :: proc(t: ^testing.T, actual, expected: app_kine.Vector3, msg: string) {
    testing.expectf(t,
        math.abs(actual.x - expected.x) <= EPS &&
        math.abs(actual.y - expected.y) <= EPS &&
        math.abs(actual.z - expected.z) <= EPS,
        "%s | expected=(%v, %v, %v) got=(%v, %v, %v)",
        msg,
        expected.x,
        expected.y,
        expected.z,
        actual.x,
        actual.y,
        actual.z)
}

expect_close :: proc(t: ^testing.T, actual, expected: f32, msg: string) {
    testing.expectf(t, math.abs(actual - expected) <= EPS,
        "%s | expected=%v got=%v", msg, expected, actual)
}
