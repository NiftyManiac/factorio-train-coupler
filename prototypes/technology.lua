data:extend({
  {
      type = "technology",
      name = "coupler-rail",
      icon = "__TrainCoupler__/graphics/technology/rail-coupler.png", 
      icon_size = 128,
      prerequisites = {"automated-rail-transportation"},
      effects =
      {
        {
            type = "unlock-recipe",
            recipe = "coupler-rail"
        }
      },
      unit =
      {
        count = 50,
        ingredients =
        {
          {"science-pack-1", 1},
          {"science-pack-2", 1},
        },
        time = 20
      }
  }
})
