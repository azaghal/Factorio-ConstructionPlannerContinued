--- Fixes the researched technology desync between the base and unapproved ghosts force.
--
local function fix_technology_desync()
  for _, force in pairs(game.forces) do
    if is_base_force(force) then
      local unapproved_ghost_force = get_unapproved_ghost_force(force)
      if unapproved_ghost_force then
        sync_all_technology(force)
        sync_all_recipes(force)
      end
    end
  end
end

-- Run migration code.
fix_technology_desync()
