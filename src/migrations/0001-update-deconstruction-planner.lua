--- Enables black-listing of trees and rocks in helper deconstruction planner.
--
local function blacklist_trees_and_rocks_in_deconstruction_planner()
  local deconstruction_planner =
    global.deconstruction_planner_inventory and
    global.deconstruction_planner_inventory[1] or
    nil

  if deconstruction_planner then
    deconstruction_planner.entity_filter_mode = defines.deconstruction_item.entity_filter_mode.blacklist
    deconstruction_planner.trees_and_rocks_only = true
  end
end

-- Run migration code.
blacklist_trees_and_rocks_in_deconstruction_planner()
