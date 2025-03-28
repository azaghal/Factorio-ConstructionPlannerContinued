local approvalBadges = {}

local availableBadgeScales = {
  tiny = 0.5,
  small = 0.75,
  normal = 1,
  large = 1.5,
  huge = 2,
}

-- TODO: consider replacing 'draw_text' with 'draw_sprite' and a better icon? (maybe Unicode hammer or hammer-and-wrench?)
-- Unicode marks, for convenience:
--   Useable:  ✘ ✔
--   Not useable:  🛠

-----------------------------------------------------------
--  Public functions
-----------------------------------------------------------

function approvalBadges.getOrCreate(entity)
  if not storage.approvalBadges then
    storage.approvalBadges = {}
  end
  if not storage.approvalBadges[entity.unit_number] then
    local badge_scale = availableBadgeScales[settings.global["construction-approvals-indicator-size"].value]

    storage.approvalBadges[entity.unit_number] = rendering.draw_text {
      text = "",
      -- text = "██",  -- Can be used for checking text bounding box / alignment
      surface = entity.surface,
      target = entity,
      color = {0.5, 0.5, 0.5},
      -- players = {playerIndex},
      alignment = "center",
      vertical_alignment = "middle",
      scale = badge_scale,
    }
  end
  return storage.approvalBadges[entity.unit_number]
end

function approvalBadges.showApproved(badge)
  if badge and badge.valid then
    badge.text = "✔"
    badge.color = {0.0, 0.8, 0.0, 0.6}
    badge.visible = true
  end
end

function approvalBadges.showUnapproved(badge)
  if badge and badge.valid then
    badge.text = "✔"
    badge.color = {0.5, 0.5, 0.5, 0.4}
    badge.visible = true
  end
end

function approvalBadges.hide(badge)
  if badge and badge.valid then
    badge.text = ""
    badge.visible = false
  end
end


--- Updates size of all approval badges.
--
function approvalBadges.update_badge_sizes()
  local configured_badge_scale = availableBadgeScales[settings.global["construction-approvals-indicator-size"].value]

  for _, badge in pairs(rendering.get_all_objects("ConstructionPlannerContinued")) do
    badge.scale = configured_badge_scale
  end
end


-----------------------------------------------------------
--  Private functions
-----------------------------------------------------------



-----------------------------------------------------------

return approvalBadges
