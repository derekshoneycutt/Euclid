package view

import ec "../core"
import "core:fmt"
import rl "vendor:raylib"
import "core:math"
import "core:math/linalg"

ViewScaler :: struct {
    BarColor: rl.Color,
    IndicatorColor: rl.Color,

    CurrentValue : f32,

    Position : Vector2,
    Size : f32,
    IndicatorSize: f32,
    BarBrushSize : f32,
    IndicatorBrushSize : f32,

    Horizontal: bool
}

init_view_scaler :: proc(
    init : f32,
    position : Vector2,
    size, indicator : f32,
    brushes : f32 = 1.0,
    barColor : rl.Color = rl.Color{255, 255, 255, 255},
    indicatorColor : rl.Color = rl.Color{255, 255, 255, 255},
    horizontal : bool = true) -> ViewScaler {

    return ViewScaler {
        barColor, indicatorColor, init, position, size, indicator, brushes, brushes, horizontal
    }
}

try_scaler_mouse_adjust :: proc(scaler : ^ViewScaler) -> bool {
    mousePos := rl.GetMousePosition()

    startPos := scaler^.Position
    endPos := startPos
    if scaler^.Horizontal {
        startPos -= { 0, scaler^.IndicatorSize / 2 }
        endPos += { scaler^.Size, scaler^.IndicatorSize / 2 }
    }
    else {
        startPos -= { scaler^.IndicatorSize / 2, 0 }
        endPos += { scaler^.IndicatorSize / 2, scaler^.Size }
    }

    if mousePos.x >= startPos.x && mousePos.x <= endPos.x &&
        mousePos.y >= startPos.y && mousePos.y <= endPos.y {
        if !rl.IsMouseButtonDown(rl.MouseButton.LEFT) {
            return false
        }

        if scaler^.Horizontal {
            x_full := endPos.x - startPos.x
            x_mouse := mousePos.x - startPos.x
            scaler^.CurrentValue = f32(x_mouse) / f32(x_full)
        }
        else {
            y_full := endPos.y - startPos.y
            y_mouse := mousePos.y - startPos.y
            scaler^.CurrentValue = f32(y_mouse) / f32(y_full)
        }

        return true
    }

    return false
}

draw_view_scaler :: proc(scaler : ^ViewScaler) {
    startPos := scaler^.Position
    endPos := startPos
    if scaler^.Horizontal {
        endPos += { scaler^.Size, 0 }
    }
    else {
        endPos += { 0, scaler^.Size }
    }

    vec := linalg.normalize(endPos - startPos)
    indicatorPos := startPos + vec * (scaler^.Size * scaler^.CurrentValue)
    indicatorStart := indicatorPos
    indicatorEnd := indicatorPos
    if scaler^.Horizontal {
        indicatorStart -= { 0, scaler^.IndicatorSize / 2 }
        indicatorEnd += { 0, scaler^.IndicatorSize / 2 }
    }
    else {
        indicatorStart -= { scaler^.IndicatorSize / 2, 0 }
        indicatorEnd += { scaler^.IndicatorSize / 2, 0 }
    }

    rl.DrawLineEx(startPos, endPos, scaler^.BarBrushSize, scaler^.BarColor)
    rl.DrawLineEx(indicatorStart, indicatorEnd, scaler^.IndicatorBrushSize, scaler^.IndicatorColor)
}
