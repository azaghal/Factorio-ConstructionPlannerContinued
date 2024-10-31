--- Fixes the researched technology desync between the base and unapproved ghosts force.
--
local function fix_technology_desync()
  for _, force in pairs(game.forces) do
    if is_base_force(force) then
      -- Do not use get_unapproved_ghost_force function - otherwise we could end-up creating unapproved ghost force even
      -- for non-player factions.
      local unapproved_ghost_force_name = get_unapproved_ghost_force_name(force.name)
      local unapproved_ghost_force = game.forces[unapproved_ghost_force_name]
      if unapproved_ghost_force then
        sync_all_technology(force)
      end
    end
  end
end

-- Run migration code.
fix_technology_desync()
