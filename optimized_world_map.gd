extends "res://world_map.gd"

func _safe_anchor(poly:PackedVector2Array)->Vector2:
    if poly.size()<3:return Vector2.ZERO
    var bb:Rect2=_bounds(poly);var center:Vector2=bb.get_center()
    if Geometry2D.is_point_in_polygon(center,poly):return center
    var best:Vector2=poly[0];var best_distance:float=INF
    for gy in range(1,8):
        for gx in range(1,8):
            var p:Vector2=bb.position+Vector2(bb.size.x*float(gx)/8.0,bb.size.y*float(gy)/8.0)
            if not Geometry2D.is_point_in_polygon(p,poly):continue
            var distance:float=p.distance_squared_to(center)
            if distance<best_distance:best_distance=distance;best=p
    return best
