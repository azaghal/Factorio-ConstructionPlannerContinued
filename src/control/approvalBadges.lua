local approvalBadges = {}

local badgeScale = 2

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
    storage.approvalBadges[entity.unit_number] = rendering.draw_text {
      text = "",
      -- text = "██",  -- Can be used for checking text bounding box / alignment
      surface = entity.surface,
      target = entity,
      -- 5/16 ratio is techically closer to center, but it kinda looks better at 1/4
      --target_offset = {0, -badgeScale*5/16},
      -- @TODO: Target offset seems to be completely ignored.
      target_offset = {0, -badgeScale/4},
      color = {0.5, 0.5, 0.5},
      -- players = {playerIndex},
      alignment = "center",
      vertical_alignment = "middle",
      scale = badgeScale,
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

-----------------------------------------------------------
--  Private functions
-----------------------------------------------------------



-----------------------------------------------------------

return approvalBadges
