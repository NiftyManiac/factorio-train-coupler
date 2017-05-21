local item = 
{
	type = "item",
	name = "coupler-rail",
	icon = "__TrainCoupler__/graphics/icons/coupler-rail.png",
	flags = {"goes-to-quickbar"},
	subgroup = "transport",
	order = "a[train-system]-b[rail-storage]",
	place_result = "coupler-rail",
	stack_size = 100
}

local recipe =
{
    type = "recipe",
    name = "coupler-rail",
    enabled = "false",
    ingredients =
    {
      {"rail", 1},
      {"green-circuit", 1},
    },
    result = "coupler-rail"
}

local coupler_rail = copyPrototype("straight-rail", "straight-rail", "coupler-rail")

coupler_rail.pictures.straight_rail_horizontal.ties.filename =
	"__TrainCoupler__/graphics/entities/coupler-rail-horizontal-ties.png"

coupler_rail.pictures.straight_rail_vertical.ties.filename =
	"__TrainCoupler__/graphics/entities/coupler-rail-vertical-ties.png"

coupler_rail.pictures.straight_rail_diagonal.ties.filename =
	"__TrainCoupler__/graphics/entities/coupler-rail-diagonal-ties.png"

data:extend({coupler_rail, item, recipe})
