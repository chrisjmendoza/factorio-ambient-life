-- Sprites are drawn white so they can be tinted per-creature at runtime.

data:extend({
	{
		type = "animation",
		name = "ambientlife-bird",
		filename = "__AmbientLife__/graphics/bird.png",
		width = 16,
		height = 16,
		frame_count = 4,
		animation_speed = 0.4,
		flags = {"no-crop"},
	},
	{
		type = "animation",
		name = "ambientlife-butterfly",
		filename = "__AmbientLife__/graphics/butterfly.png",
		width = 12,
		height = 12,
		frame_count = 4,
		animation_speed = 0.5,
		flags = {"no-crop"},
	},
})
