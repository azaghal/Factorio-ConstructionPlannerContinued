--- Switch from using numeric IDs to using objects for badges.
--
-- Required update for version 2.0 of the game.
--
local function convert_badge_ids_to_objects()
  for entity_id, badge_id in pairs(storage.approvalBadges) do
    storage.approvalBadges[entity_id] = rendering.get_object_by_id(badge_id)
  end
end

-- Run migration code.
convert_badge_ids_to_objects()
