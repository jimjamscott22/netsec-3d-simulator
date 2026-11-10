class_name CableMesh
extends RefCounted

const RADIUS: float = 0.006
const SIDES: int = 6
const SEGMENTS: int = 24


## Both socket transforms are in the mesh parent's space. +Z points out of the jack.
static func between(from: Transform3D, to: Transform3D) -> ArrayMesh:
	var distance: float = from.origin.distance_to(to.origin)
	var reach: float = clampf(distance * 0.35, 0.10, 0.60)
	var sag: float = minf(distance * 0.15, 0.60)
	var points := PackedVector3Array()
	for ring: int in range(SEGMENTS + 1):
		var t: float = float(ring) / SEGMENTS
		var point: Vector3 = from.origin.bezier_interpolate(
			from.origin + from.basis.z.normalized() * reach,
			to.origin + to.basis.z.normalized() * reach,
			to.origin,
			t
		)
		point.y = maxf(RADIUS, point.y - sag * 4.0 * t * (1.0 - t))
		points.append(point)

	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var radial: Vector3 = from.basis.x.normalized()
	for ring: int in points.size():
		var tangent: Vector3 = (points[mini(ring + 1, SEGMENTS)] - points[maxi(ring - 1, 0)]).normalized()
		# Keep each ring aligned with the previous one as the cable bends.
		radial = radial.slide(tangent)
		if radial.length_squared() < 0.000001:
			radial = tangent.cross(Vector3.UP)
		radial = radial.normalized()
		for side: int in SIDES:
			var normal: Vector3 = radial.rotated(tangent, TAU * side / SIDES)
			surface.set_normal(normal)
			surface.add_vertex(points[ring] + normal * RADIUS)

	for ring: int in SEGMENTS:
		for side: int in SIDES:
			var a: int = ring * SIDES + side
			var b: int = ring * SIDES + (side + 1) % SIDES
			for index: int in [a, a + SIDES, b, b, a + SIDES, b + SIDES]:
				surface.add_index(index)
	return surface.commit()
