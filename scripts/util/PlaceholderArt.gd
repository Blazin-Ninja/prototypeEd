extends RefCounted
class_name PlaceholderArt
## Draws simple colored shapes for creatures / mutations.

static func draw_creature(canvas: CanvasItem, creature: Dictionary, center: Vector2, radius: float) -> void:
	var color := Color.html(str(creature.get("color", "#888888")))
	var shape := str(creature.get("shape", "quad"))
	match shape:
		"fish":
			canvas.draw_circle(center, radius * 0.7, color)
			canvas.draw_colored_polygon(PackedVector2Array([
				center + Vector2(radius * 0.5, 0),
				center + Vector2(radius, -radius * 0.5),
				center + Vector2(radius, radius * 0.5)
			]), color.darkened(0.2))
		"bird":
			canvas.draw_circle(center + Vector2(0, -radius * 0.1), radius * 0.55, color)
			canvas.draw_colored_polygon(PackedVector2Array([
				center + Vector2(-radius, 0),
				center + Vector2(0, -radius * 0.2),
				center + Vector2(-radius * 0.2, radius * 0.3)
			]), color.lightened(0.15))
			canvas.draw_colored_polygon(PackedVector2Array([
				center + Vector2(radius, 0),
				center + Vector2(0, -radius * 0.2),
				center + Vector2(radius * 0.2, radius * 0.3)
			]), color.lightened(0.15))
		"plant":
			canvas.draw_rect(Rect2(center - Vector2(radius * 0.25, 0), Vector2(radius * 0.5, radius)), color.darkened(0.3))
			canvas.draw_circle(center + Vector2(0, -radius * 0.35), radius * 0.55, color)
		"bug":
			canvas.draw_circle(center, radius * 0.45, color)
			canvas.draw_circle(center + Vector2(0, -radius * 0.45), radius * 0.35, color.lightened(0.1))
		"serpent":
			canvas.draw_circle(center + Vector2(-radius * 0.4, 0), radius * 0.35, color)
			canvas.draw_circle(center, radius * 0.4, color)
			canvas.draw_circle(center + Vector2(radius * 0.4, 0), radius * 0.35, color)
		"bulk":
			canvas.draw_rect(Rect2(center - Vector2(radius * 0.8, radius * 0.6), Vector2(radius * 1.6, radius * 1.2)), color)
		_:
			# quad / default
			canvas.draw_circle(center + Vector2(-radius * 0.35, radius * 0.2), radius * 0.35, color.darkened(0.1))
			canvas.draw_circle(center + Vector2(radius * 0.35, radius * 0.2), radius * 0.35, color.darkened(0.1))
			canvas.draw_circle(center + Vector2(0, -radius * 0.15), radius * 0.55, color)

	# Mutation overlays (simple markers).
	for mid in creature.get("mutations", []):
		var m: Dictionary = DataRegistry.get_mutation(str(mid))
		var slot := str(m.get("slot", ""))
		var mc := Color.html(str(m.get("color", "#ffffff"))) if m.get("color", null) != null else Color(1, 1, 1, 0.8)
		match slot:
			"horns":
				canvas.draw_colored_polygon(PackedVector2Array([
					center + Vector2(-radius * 0.35, -radius * 0.5),
					center + Vector2(-radius * 0.2, -radius),
					center + Vector2(-radius * 0.05, -radius * 0.5)
				]), mc)
				canvas.draw_colored_polygon(PackedVector2Array([
					center + Vector2(radius * 0.05, -radius * 0.5),
					center + Vector2(radius * 0.2, -radius),
					center + Vector2(radius * 0.35, -radius * 0.5)
				]), mc)
			"wings":
				canvas.draw_circle(center + Vector2(-radius, 0), radius * 0.3, mc)
				canvas.draw_circle(center + Vector2(radius, 0), radius * 0.3, mc)
			"eyes":
				canvas.draw_circle(center + Vector2(-radius * 0.18, -radius * 0.2), radius * 0.1, mc)
				canvas.draw_circle(center + Vector2(radius * 0.18, -radius * 0.2), radius * 0.1, mc)
			"particles":
				for i in 4:
					var ang := TAU * float(i) / 4.0
					canvas.draw_circle(center + Vector2(cos(ang), sin(ang)) * radius * 0.95, radius * 0.08, mc)
			"tail":
				canvas.draw_circle(center + Vector2(0, radius * 0.75), radius * 0.18, mc)
			"fangs":
				canvas.draw_colored_polygon(PackedVector2Array([
					center + Vector2(-0.1 * radius, 0.1 * radius),
					center + Vector2(-0.05 * radius, 0.35 * radius),
					center + Vector2(0.0, 0.1 * radius)
				]), Color.WHITE)
			"armor":
				canvas.draw_rect(Rect2(center - Vector2(radius * 0.7, radius * 0.2), Vector2(radius * 1.4, radius * 0.25)), mc)
			_:
				pass

	if creature.get("is_alpha", false):
		canvas.draw_arc(center, radius * 1.15, 0, TAU, 32, Color(1, 0.84, 0, 0.9), 3.0)
	if creature.get("is_boss", false):
		canvas.draw_arc(center, radius * 1.25, 0, TAU, 32, Color(0.7, 0.1, 0.2, 0.9), 4.0)

	# Ability / element flourishes so companions read like their powers.
	_draw_power_flourishes(canvas, creature, center, radius)

static func _draw_power_flourishes(canvas: CanvasItem, creature: Dictionary, center: Vector2, radius: float) -> void:
	var els: Array = creature.get("elements", [])
	var tid := str(creature.get("template_id", creature.get("id", "")))
	var primary := str(els[0]) if not els.is_empty() else ""
	match primary:
		"fire":
			for i in 3:
				var o := Vector2((-0.35 + i * 0.35) * radius, -radius * (0.75 + 0.1 * (i % 2)))
				canvas.draw_colored_polygon(PackedVector2Array([
					center + o,
					center + o + Vector2(radius * 0.08, radius * 0.18),
					center + o + Vector2(-radius * 0.08, radius * 0.18)
				]), Color(1.0, 0.55, 0.1, 0.85))
		"water":
			for i in 3:
				var p := center + Vector2((-0.4 + i * 0.4) * radius, radius * 0.7)
				canvas.draw_circle(p, radius * 0.07, Color(0.4, 0.75, 1.0, 0.7))
		"nature":
			for i in 2:
				var side := -1.0 if i == 0 else 1.0
				canvas.draw_colored_polygon(PackedVector2Array([
					center + Vector2(side * radius * 0.15, -radius * 0.1),
					center + Vector2(side * radius * 0.75, -radius * 0.45),
					center + Vector2(side * radius * 0.35, radius * 0.05)
				]), Color(0.35, 0.75, 0.4, 0.75))
		"wind":
			for i in 2:
				var y := -0.1 + i * 0.25
				canvas.draw_line(center + Vector2(-radius * 0.7, y * radius), center + Vector2(radius * 0.7, (y - 0.1) * radius), Color(0.75, 0.95, 1.0, 0.55), 2.0)
		"electric":
			canvas.draw_colored_polygon(PackedVector2Array([
				center + Vector2(0, -radius * 1.05),
				center + Vector2(radius * 0.12, -radius * 0.55),
				center + Vector2(-radius * 0.05, -radius * 0.55),
				center + Vector2(0, -radius * 0.2),
				center + Vector2(-radius * 0.12, -radius * 0.7),
				center + Vector2(radius * 0.05, -radius * 0.7)
			]), Color(1.0, 0.9, 0.2, 0.85))
		"shadow":
			canvas.draw_circle(center + Vector2(0, radius * 0.1), radius * 0.95, Color(0.25, 0.05, 0.35, 0.18))
		_:
			pass
	# Bite / claw starters get fang or claw marks via ability names.
	for aid in creature.get("abilities", []):
		var name := str(DataRegistry.get_ability(str(aid)).get("name", "")).to_lower()
		if "bite" in name or "fang" in name:
			canvas.draw_colored_polygon(PackedVector2Array([
				center + Vector2(-radius * 0.12, radius * 0.05),
				center + Vector2(-radius * 0.05, radius * 0.35),
				center + Vector2(0, radius * 0.05)
			]), Color(1, 1, 1, 0.9))
		if "scratch" in name or "slash" in name or "claw" in name:
			canvas.draw_line(center + Vector2(radius * 0.35, -radius * 0.1), center + Vector2(radius * 0.7, radius * 0.25), Color(0.9, 0.9, 0.95, 0.7), 2.0)
			canvas.draw_line(center + Vector2(radius * 0.25, 0), center + Vector2(radius * 0.65, radius * 0.35), Color(0.9, 0.9, 0.95, 0.55), 2.0)
