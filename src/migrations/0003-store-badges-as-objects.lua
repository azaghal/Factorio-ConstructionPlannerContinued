--- Switch from using numeric IDs to using objects for badges.
--
-- Required update for version 2.0 of the game.
--
local function convert_badge_ids_to_objects()
  if storage.approvalBadges then
    for entity_id, badge_id in pairs(storage.approvalBadges) do
      if (type(badge_id)) == "number" then
        storage.approvalBadges[entity_id] = rendering.get_object_by_id(badge_id)
      end
    end
  end
end

-- Run migration code.
convert_badge_ids_to_objects()
