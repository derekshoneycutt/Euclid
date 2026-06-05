package surface

import ec "../core"
import rl "vendor:raylib"

DefaultEdgeSize :: 0.05
DefaultTileSize :: 1.0
DefaultSurfaceColor :: rl.Color{25, 25, 25, 255}
DefaultEdgeColor :: rl.Color{96, 65, 76, 255}

EuclidDrawingSurface :: ec.EuclidDrawingSurface

init_drawing_surface :: proc(
    tileSize : f32 = DefaultTileSize,
    edgeSize : f32 = DefaultEdgeSize,
    surfaceColor : rl.Color = DefaultSurfaceColor,
    edgeColor : rl.Color = DefaultEdgeColor) -> EuclidDrawingSurface {

    Zeros := ec.Vector3{0 - edgeSize, 0 - edgeSize, 0}
    RightUp := ec.Vector3{1 + edgeSize, 0 - edgeSize, 0}
    LeftDown := ec.Vector3{0 - edgeSize, 1 + edgeSize, 0}
    RightDown := ec.Vector3{1 + edgeSize, 1 + edgeSize, 0}

    return EuclidDrawingSurface{
        Zeros,
        RightUp,
        LeftDown,
        RightDown,
        surfaceColor,
        edgeColor,
        DefaultEdgeSize
    }
}
