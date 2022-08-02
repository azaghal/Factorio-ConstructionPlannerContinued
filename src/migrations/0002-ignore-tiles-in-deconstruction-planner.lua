--- Disables deconstruction of tiles in helper deconstruction planner.
--
local function disable_tiles_in_deconstruction_planner()
  local deconstruction_planner =
    global.deconstruction_planner_inventory and
    global.deconstruction_planner_inventory[1] or
    nil

  if deconstruction_planner then
    deconstruction_planner.tile_selection_mode = defines.deconstruction_item.tile_selection_mode.never
  end
end

-- Run migration code.
disable_tiles_in_deconstruction_planner()
