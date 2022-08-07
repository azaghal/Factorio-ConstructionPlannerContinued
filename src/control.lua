-- Note: there is no "on_entity_changed_force" event, so I'll have to just update badges as I change the forces in my
--       mod, and hope that other mods don't mess around with the forces too much.  For /editor force changes during
--       testing, I can use a console command + remote interface to manually force a badge rescan.

local core_util = require("util")

local approvalBadges = require("control.approvalBadges")

local UINT32_MAX = 4294967295
local FORCE_REGEX = "(.+)%.unapproved_ghosts"
local SETTING_AUTO_APPROVE = "constructionPlanner-auto-approve"


-- Global values used to prevent processing of certain events while diplomacy sync is in progress or while a force is
-- being created.
DIPLOMACY_SYNC_IN_PROGRESS = false
FORCE_CREATION_IN_PROGRESS = false


--- Checks if the specified force is an unapproved ghost force.
--
-- @param force LuaForce|string Force or force name to check.
--
-- @return bool true, if passed-in force is an unapproved ghost force, false otherwise.
--
function is_unapproved_ghost_force(force)
  local name = force.name or force

  return string.match(name, FORCE_REGEX) ~= nil
end


--- Checks if the specified force is a base force.
--
-- @param force LuaForce|string Force or force name to check.
--
-- @return bool true, if passed-in force is a base force, false otherwise.
--
function is_base_force(force)
  return not is_unapproved_ghost_force(force)
end


--- Returns unapproved ghost force name for specified force.
--
-- If passed-in name already belongs to an unapproved ghost force, returns the same name.
--
-- @param force LuaForce|string Force or force name for which to calculate the unapproved ghost force name.
--
-- @return string Name of unapproved ghost force.
--
function get_unapproved_ghost_force_name(force)
  local name = force.name or force

  if is_unapproved_ghost_force(name) then

    return name
  end

  return name .. ".unapproved_ghosts"
end


--- Returns base force name for specified force.
--
-- If passed-in name already belongs to a base force, returns the same name.
--
-- @param force LuaForce|string Force or force name for which to calculate the base force name.
--
-- @return string Name of base force.
--
function get_base_force_name(force)
  local name = force.name or force

  return string.match(name, FORCE_REGEX) or name
end


--- Helper function for showing entity debug information.
--
-- @param entity LuaEntity entity for which to produce debug information.
--
-- @return string Debug information about the entity. Includes type, force name, and position.
--
function entity_debug_string(entity)
  return entity.type .. " of " .. entity.force.name .. " @ " .. serpent.line(entity.position)
end


--- Returns first table element or nil.
--
-- @param table table Table to fetch the first element from.
--
-- @return First element of a table or nil.
--
function first_match_or_nil(table)
  if table_size(table) == 0 then
    return nil
  else 
    return table[1]
  end
end


--- Helper function for showing position debug information.
--
-- @param position MapPosition Position on the surface.
--
-- @return string Debug information about the position (x/y coordinates).
function position_string(position)
  return tostring(position.x) .. ":" .. tostring(position.y)
end


--- Remaps associative array by applying the passed in function to key/value pairs of input array.
--
-- Passed in function should accept key and value as positional argument, and output new key and new
-- value. I.e. fn(old_key, old_value) -> (new_key, new_value).
--
-- If new key is nil, the value is ignored.
--
-- @param array Array to run the remap function against.
-- @param fn Function to apply against each (key, value) pair of the array.
--
-- @return Remapped array.
--
function remap(array, fn)
  local result = {}

  for key, value in pairs(array or {}) do
    local new_key, new_value = fn(key, value)
    if new_key ~= nil then
      result[new_key] = new_value
    end
  end

  return result
end


--- Filters elements in an associative array using a predicate function against (key, value) pairs.
--
-- If predicate function return true, then the (key, value) pair is included in the resulting array.
--
-- @param array array Array to filter.
-- @param fn function Function to apply against each (key, value) pair. Must return true or false.
--
-- @return array Array with elements that pass the predicate function check.
--
function filter(array, fn)

  return remap(
    array,
    function(key, value)
      if fn(key, value) then
        return key, value
      end
      return nil, nil
    end
  )
end


--- Synchronises diplomacy settings from source force to destination force.
--
-- Updates friend, foe, and cease fire status for destination force to match the ones of the source force. Normally
-- required to making sure the unapproved ghost force has same relationship to other forces like the base force.
--
-- @param source_force LuaForce Source force from which to take the diplomacy settings.
-- @param destination_force LuaForce Destination force to which to sync the source force diplomacy settings.
--
function sync_all_diplomacy(source_force, destination_force)
  DIPLOMACY_SYNC_IN_PROGRESS = true

  for _, force in pairs(game.forces) do
    if (force ~= source_force and force ~= destination_force) then
      destination_force.set_friend(force, source_force.get_friend(force))
      destination_force.set_cease_fire(force, source_force.get_cease_fire(force))
    end
  end

  DIPLOMACY_SYNC_IN_PROGRESS = false
end


--- Retrieves unapproved ghost force for specified force, creating one if it does not exist.
--
-- @param force LuaForce Force for which to get unapproved ghost force.
--
-- @return LuaForce Unapproved ghost force.
--
function get_or_create_unapproved_ghost_force(force)
  local unapproved_ghost_force_name = get_unapproved_ghost_force_name(force)

  if not game.forces[unapproved_ghost_force_name] then
    FORCE_CREATION_IN_PROGRESS = true
    local unapproved_ghost_force = game.create_force(unapproved_ghost_force_name)

    unapproved_ghost_force.set_friend(force, true)
    unapproved_ghost_force.set_cease_fire(force, true)

    force.set_friend(unapproved_ghost_force, true)
    force.set_cease_fire(unapproved_ghost_force, true)

    sync_all_diplomacy(force, unapproved_ghost_force)

    FORCE_CREATION_IN_PROGRESS = false
  end

  return game.forces[unapproved_ghost_force_name]
end


--- Returns base force.
--
-- Can be used against the base force itself as well.
--
-- @param force LuaForce Force for which to return the base force.
--
-- @return LuaForce Base force.
--
function get_base_force(force)
  return game.forces[get_base_force_name(force)]
end


--- Returns complement force to passed-in force.
--
-- Complement force for base force is unapproved ghost force and vice-versa.
--
-- @param force LuaForce Force for which to return complement force.
--
-- @return LuaForce Complement force to passed-in force.
--
function get_complement_force(force)
  if is_unapproved_ghost_force(force) then
    return get_base_force(force)
  end

  return get_or_create_unapproved_ghost_force(force)
end


--- Returns a player-neutral mod-specific blueprint used for internal mod processing.
--
-- Function take care of initialisation as well.
--
-- @return LuaItemStack Blueprint.
--
function get_script_blueprint()
  if not global.blueprintInventory then
    local blueprintInventory = game.create_inventory(1)
    blueprintInventory.insert({ name="blueprint"})
    global.blueprintInventory = blueprintInventory
  end

  return global.blueprintInventory[1]
end


--- Returns a player-neutral deconstruction planner used for internal mod processing.
--
-- @return LuaItemStack Deconstruction planner.
--
function get_deconstruction_planner()
  if not global.deconstruction_planner_inventory then
    global.deconstruction_planner_inventory = game.create_inventory(1)
    global.deconstruction_planner_inventory.insert({ name = "deconstruction-planner" })

    -- Make sure that the deconstruction planner cannot be used for deconstructing trees and rocks. Deconstruction
    -- planner is used as a helper tool to preserve correct undo history. However, when used with cut-and-paste, we need
    -- to make sure that the trees and rocks are not affected by it - since normal cut-and-paste tool does not touch
    -- those either.
    global.deconstruction_planner_inventory[1].entity_filter_mode = defines.deconstruction_item.entity_filter_mode.blacklist
    global.deconstruction_planner_inventory[1].trees_and_rocks_only = true
  end

  return global.deconstruction_planner_inventory[1]
end


--- Checks if passed-in entity is a placeholder.
--
-- @param entity LuaEntity Entity to check.
--
-- @return bool true, if entity is a placeholder, false otherwise.
--
function is_placeholder(entity)
  return entity.type == "entity-ghost" and entity.ghost_name == "unapproved-ghost-placeholder"
end


--- Checks if the passed-in entity is a placeholder in a blueprint.
--
-- @param entity LuaEntity Entity to check.
--
-- @return bool true, if entity is a placeholder in a blueprint, false otherwise.
--
function is_bp_placeholder(entity)
  return entity.name == "unapproved-ghost-placeholder"
end


--- Creates placeholder for unapproved entity.
--
-- @param unapproved_entity LuaEntity Unapproved entity. It should belong to unapproved ghost force.
--
-- @return LuaEntity Placeholder entity.
--
function create_placeholder_for(unapproved_entity)
  -- The placeholder has to be a ghost, otherwise it will overwrite the unapproved entity, and mess up the
  -- deconstruction planner interaction
  local placeholder = unapproved_entity.surface.create_entity {
    name = "entity-ghost",
    position = unapproved_entity.position,
    force = get_base_force(unapproved_entity.force),
    inner_name = "unapproved-ghost-placeholder"
  }

  return placeholder
end


--- Removes placeholder for an unapproved entity.
--
-- @param unapproved_entity LuaEntity Unapproved entity. It should belong to unapproved ghost force.
--
function remove_placeholder_for(unapproved_entity)
  -- This search works only because the placeholder will be at the *same exact position* as the unapproved entity.
  local placeholders = unapproved_entity.surface.find_entities_filtered {
    position = unapproved_entity.position,
    force = get_base_force(unapproved_entity.force),
    ghost_name = "unapproved-ghost-placeholder"
  }

  -- Only one placeholder is expected, but if multiple are discovered for whatever reason, just remove them all
  for _, placeholder in pairs(placeholders) do
    placeholder.destroy()
  end
end


--- Removes invalid placeholders in vicinity of specified position (50x50 box centered on position).
--
-- Placeholder is invalid if:
--
--   - No matching unapproved ghost entity exists at its position.
--
-- @param surface LuaSurface Surface to search the placeholders for.
-- @param position MapPosition Position on surface around which to search.
--
function remove_invalid_nearby_placeholders(surface, position)
  local placeholders = surface.find_entities_filtered {
    area = {
      { position.x - 25, position.y - 25 },
      { position.x + 25, position.y + 25 },
    },
    ghost_name = "unapproved-ghost-placeholder"
  }

  for _, placeholder in pairs (placeholders) do
    if table_size(get_unapproved_ghost_for(placeholder)) == 0 then
      placeholder.destroy()
    end
  end

end


--- Searches for entities in specified area that belong to passed-in force, and returns them as blueprint entities.
--
-- @param surface LuaSurface Surface to search for entities.
-- @param force LuaForce Force to which the entities belong to.
-- @param area BoundingBox Bounding box on the surface to search for entities.
--
-- @return {LuaEntity} List of entities in format compatible for blueprint use.
--
function get_entities_as_blueprint_entities(surface, force, area)
  local bp = get_script_blueprint()
  bp.clear_blueprint()
  bp.create_blueprint {
    surface = surface,
    force = force,
    area = area,
    always_include_tiles = false
  }
  return bp.get_blueprint_entities()
end


--- Retrieves list of unapproved ghosts matching a placeholder.
--
-- Normally only one unapproved ghost should match a placeholder.
--
-- @param placeholder LuaEntity Placeholder for which to find unapproved ghost entities.
--
-- @return {LuaEntity} List of unapproved ghosts.
--
function get_unapproved_ghost_for(placeholder)
  local unapproved_ghosts = placeholder.surface.find_entities_filtered {
    position = placeholder.position,
    force = get_or_create_unapproved_ghost_force(placeholder.force),
    name = "entity-ghost"
  }

  return unapproved_ghosts
end


--- Retrieves list of placeholders corresponding to unapproved ghost.
--
-- Normally only a single placeholder should be returned.
--
-- @param unapproved_ghost LuaEntity Unapproved ghost entity.
--
-- @return {LuaEntity} List of placeholder entities corresponding to the specified unapproved ghost entity.
--
function get_placeholder_for(unapproved_ghost)
  local placeholders = unapproved_ghost.surface.find_entities_filtered {
    position = unapproved_ghost.position,
    force = get_base_force(unapproved_ghost.force),
    ghost_name = "unapproved-ghost-placeholder"
  }

  return placeholders
end


--- Removes unapproved ghosts for passed-in placeholder.
--
-- @param placeholder LuaEntity Placeholder for which to remove unapproved ghost entities. 
--
function remove_unapproved_ghost_for(placeholder)
  local unapproved_ghosts = get_unapproved_ghost_for(placeholder)

  -- Only one placeholder is expected, but if multiple are discovered for whatever reason, just remove them all
  for _, unapproved_ghost in pairs(unapproved_ghosts) do
    unapproved_ghost.destroy()
  end
end


--- Checks if player has enabled auto-approval.
--
-- @param player LuaPlayer
--
-- @return bool true if player has enabled auto-approval, false otherwise.
--
function is_auto_approval_enabled(player)
  return settings.get_player_settings(player)[SETTING_AUTO_APPROVE].value
end


--- Toggles auto-approval on and off for a player.
--
-- @TODO: This is really a wrong way to do it - this should not be toggled via per-player settings, it should be toggled
-- per-savegame.
--
-- @param player LuaPlayer Player for which to toggle auto-approval.
--
function toggle_auto_approval(player)
  local mod_setting = settings.get_player_settings(player)[SETTING_AUTO_APPROVE]

  mod_setting.value = not mod_setting.value

  settings.get_player_settings(player)[SETTING_AUTO_APPROVE] = mod_setting
end


--- Checks if entity is an approvable ghost entity.
--
-- @param entity LuaEntity Entity to check.
--
-- @return bool true if entity is an approvable ghost entity, false otherwise.
--
function is_approvable_ghost(entity)

  function is_perishable(entity)
    -- In theory, entity.time_to_live <= entity.force.ghost_time_to_live would also work..but this seems safer
    return entity.time_to_live < UINT32_MAX
  end

  function is_selectable(entity)
    return entity.type == "entity-ghost" and entity.ghost_prototype.selectable_in_game
  end

  return entity and entity.type == "entity-ghost" and not is_placeholder(entity) and not is_perishable(entity) and is_selectable(entity)
end


--- Approves passed-in list of entities.
--
-- Each entity is checked to validate that it can be approved.
--
-- @param entities LuaEntity[] List of entities to approve.
--
function approve_entities(entities)

  for _, entity in pairs(entities) do
    if is_approvable_ghost(entity) then
      local base_force = get_base_force(entity.force)

      if entity.force ~= base_force then
        entity.force = base_force
        remove_placeholder_for(entity)
      end

      local badgeId = approvalBadges.getOrCreate(entity);
      approvalBadges.showApproved(badgeId)
    end
  end

end


--- Returns closest matching underground belt that belongs to specified force.
--
-- The function is primarily useful for trying to pair-up underground belts of complement forces (base force and
-- unapproved ghost force). Base game takes good care of pairing-up underground belts from the same force, but in case
-- of unapproved ghost force, this has to be done by hand (and is somewhat error-prone).
--
-- Keep in mind that when complement force is passed-in that the underground belt still might be paired-up with an
-- underground belt of its own force - in which case it is better to let vanilla game handle rotation on its own.
--
-- @param underground_belt LuaEntity (Ghost) underground belt for which to find closest matching underground belt.
-- @param force LuaForce Force to which the matching underground belt should belong.
--
-- @return LuaEntity|nil Closest matching underground belt that belongs to specified force.
--
function get_matching_underground_belt(underground_belt, force)
  local prototype =
    underground_belt.name == "entity-ghost" and underground_belt.ghost_prototype or
    underground_belt.prototype

  -- Determine direction for finding the matching underground belt. It depends on both the direction the passed-in
  -- entity is facing, and whether this is the input or output side of the underground belt (code might look a bit
  -- convoluted, but is quite optimal).
  local search_direction =
    underground_belt.belt_to_ground_type == "output" and core_util.oppositedirection(underground_belt.direction) or
    underground_belt.direction

  -- Calculate bounding box for finding the matching ghost underground belt. Take into consideration the entity
  -- position, the direction in which we need to search for matching ghost underground belt, and finally maximum
  -- distance this type of underground belt can span.
  local bounding_box = {

    -- Exclude the passed-in belt itself from the search.
    core_util.moveposition(
      { underground_belt.position.x, underground_belt.position.y },
      search_direction,
      1
    ),

    core_util.moveposition(
      { underground_belt.position.x, underground_belt.position.y },
      search_direction,
      prototype.max_underground_distance
    )

  }

  -- Ensure that first point of bounding box is upper-left, and second bottom-right - otherwise
  -- find_entities_filtered function does not return correct results.
  if search_direction == defines.direction.north or search_direction == defines.direction.west then
    bounding_box = {bounding_box[2], bounding_box[1]}
  end

  -- Find the matching underground belts (both non-ghost and ghost ones).
  local matching_underground_belts = {}
  for _, entity in pairs(underground_belt.surface.find_entities_filtered{
                           type = prototype.type,
                           name = prototype.name,
                           force = force,
                           area = bounding_box}) do
    table.insert(matching_underground_belts, entity)
  end
  for _, entity in pairs(underground_belt.surface.find_entities_filtered{
                           ghost_type = prototype.type,
                           ghost_name = prototype.name,
                           force = force,
                           area = bounding_box}) do
    table.insert(matching_underground_belts, entity)
  end

  -- Filter-out candidates that:
  --
  --   - Face the same way (first two conditions).
  --   - Are orthogonal to each-other (third condition).
  for index, candidate in pairs(matching_underground_belts) do
    if candidate.direction == underground_belt.direction and candidate.belt_to_ground_type == underground_belt.belt_to_ground_type or
       core_util.oppositedirection(candidate.direction) == underground_belt.direction and candidate.belt_to_ground_type ~= underground_belt.belt_to_ground_type or
       candidate.direction ~= underground_belt.direction and core_util.oppositedirection(candidate.direction) ~= underground_belt.direction then
      matching_underground_belts[index] = nil
    end
  end

  return underground_belt.surface.get_closest(underground_belt.position, matching_underground_belts)
end


--- Unapproves passed-in list of (ghost) entities.
--
-- Each entity is checked to validate that it can be unapproved.
--
-- @param entities {LuaEntity} List of entities to unapproved.
--
function unapprove_entities(entities)
  local unapproved_force_cache = {}

  local unapproved_force_cache = {}

  for _, entity in pairs(entities) do
    if is_approvable_ghost(entity) then

      -- Determine the unapproved ghost entities force. The entity will already have its force set as one when player invokes undo after removing unapproved
      -- ghost entity (via right-click).
      local unapproved_force
      if not is_unapproved_ghost_force(entity.force) then
        unapproved_force_cache[entity.force.name] = unapproved_force_cache[entity.force.name] or get_or_create_unapproved_ghost_force(entity.force)
        unapproved_force = unapproved_force_cache[entity.force.name]
      else
        unapproved_force = entity.force
      end

      if (entity.force ~= unapproved_force) then

        -- In case of underground belts, we need to figure out if their rotation needs to be corrected. This has to be
        -- done prior to changing the force. Once the force changes, game engine will most likely incorrectly rotate the
        -- paired underground belts.
        local rotate_entity = false

        if entity.ghost_prototype.type == "underground-belt" then
          local matching_underground_belt = get_matching_underground_belt(entity, get_complement_force(entity.force))

          -- Make sure the matched underground belt from complement force has no counterpart of its own already.
          if matching_underground_belt and not get_matching_underground_belt(matching_underground_belt, matching_underground_belt.force) then
            rotate_entity = matching_underground_belt and entity.belt_to_ground_type == matching_underground_belt.belt_to_ground_type or false
          end
        end

        entity.force = unapproved_force

        -- Rotate the underground belt if required.
        if rotate_entity then
          entity.rotate()
        end
      end

      create_placeholder_for(entity)
      local badgeId = approvalBadges.getOrCreate(entity);
      approvalBadges.showUnapproved(badgeId)
    end
  end
end


--- Processes correction queue for recently approved ghost entities.
--
-- Unapproves all valid ghost entities, empties the queue, and deregisters handler from the on_tick event.
--
-- Correction queue is used for storing ghost entities that get approved during the on_pre_build event by draggable
-- entities that leave gaps (underground belts, electric poles, underground pipes). Such draggable entities will trigger
-- the event on every tile dragged without necessarily resulting in entity placement.
--
-- Since we cannot detect at that point if placement will happen or not, we preventively approve the intersecting
-- unapproved ghosts in order to ensure that if placement does happen, the unapproved ghost will end-up in player's undo
-- queue (alongside with preserving the recipe settings etc). Additional bonus is that we avoid having leftover
-- placeholders when the placed draggable entity does not overlap them.
--
-- This function needs to be registered for invocation during the next game tick to ensure the ghosts remain unapproved
-- (if they did not get replaced by an actual draggable entity).
--
function process_unapproved_ghosts_correction_queue()
  if global.unapproved_ghosts_correction_queue then
    -- Ghosts that are still valid have obvisouly not been replaced, so they should be switched back to their original
    -- (unapproved) state.
    for unit_number, ghost in pairs(global.unapproved_ghosts_correction_queue) do
      if ghost.valid then
        unapprove_entities({ghost})
      end
    end

    -- Mark the queue as processed.
    global.unapproved_ghosts_correction_queue = nil

    -- The queue has been processed, deregister handler to avoid performance issues.
    script.on_event(defines.events.on_tick, nil)
  end
end


-------------------------------------------------------------------------------
--       EVENTS
-------------------------------------------------------------------------------

script.on_event(defines.events.on_force_friends_changed,
  function(event)
    if not DIPLOMACY_SYNC_IN_PROGRESS and not FORCE_CREATION_IN_PROGRESS then 
      local unapproved_ghost_force = get_or_create_unapproved_ghost_force(event.force)
      if unapproved_ghost_force then
        -- game.print("Syncing friends update from " .. event.force.name .. " to " .. unapproved_ghost_force.name)
        -- game.print("  (other force = " .. event.other_force.name .. ", added = " .. tostring(event.added) .. ")")
        unapproved_ghost_force.set_friend(event.other_force, event.added)
      end
    end
  end
)


script.on_event(defines.events.on_force_cease_fire_changed,
  function(event)
    if not DIPLOMACY_SYNC_IN_PROGRESS and not FORCE_CREATION_IN_PROGRESS then 
      local unapproved_ghost_force = get_or_create_unapproved_ghost_force(event.force)
      if unapproved_ghost_force ~= nil then
        -- game.print("Syncing cease-fire update from " .. event.force.name .. " to " .. unapproved_ghost_force.name)
        -- game.print("  (other force = " .. event.other_force.name .. ", added = " .. tostring(event.added) .. ")")
        unapproved_ghost_force.set_cease_fire(event.other_force, event.added)
      end
    end
  end
)


script.on_event(defines.events.on_player_selected_area,
  function(event)
    if event.item == 'construction-planner' then
      local player = game.get_player(event.player_index)

      -- Filter should only match 'unapproved' ghosts (ghost entities on the selecting player's unapproved ghost force)
      local entities = event.surface.find_entities_filtered {
        area = event.area,
        force = get_or_create_unapproved_ghost_force(player.force),
        type = "entity-ghost"
      }

      if #entities > 0 then
        -- game.print("construction-planner: approving "..tostring(#entities).." entities")

        approve_entities(entities)

        -- Note:  if the devs ever add support, I can also use "utility/upgrade_selection_started" at selection start
        player.play_sound { path = "utility/upgrade_selection_ended" }
      end
    end
  end
)


script.on_event(defines.events.on_player_alt_selected_area,
  function(event)
    if event.item == 'construction-planner' then
        local player = game.get_player(event.player_index)

        -- Filter should only match 'approved' ghosts (ghost entities on the selecting player's base force)
        local entities = event.surface.find_entities_filtered {
          area = event.area,
          force = player.force,
          type = "entity-ghost"
        }

        if #entities > 0 then
          -- game.print("construction-planner: unapproving "..tostring(#entities).." entities")

          unapprove_entities(entities)

          -- Note:  if the devs ever add support, I can also use "utility/upgrade_selection_started" at selection start
          player.play_sound { path = "utility/upgrade_selection_ended" }
        end
    end
  end
)


script.on_event(defines.events.on_built_entity,
  function(event)

    local entity = event.created_entity
    local player = game.players[event.player_index]

    if entity.type == "entity-ghost" then

      if entity.ghost_name == "unapproved-ghost-placeholder" then
        -- Player should not be able to place unapproved ghost placeholders. This can happen when invoking the undo
        -- action. Get rid of the placeholder at this point. As an interesting side-effect, this also makes the undo
        -- action behave correctly when undoing "cancel deconstruction" action (most likely thanks to order in which
        -- undo tries to revive ghosts - not 100% sure if this is deterministic, though).
        entity.destroy()
      elseif not is_auto_approval_enabled(player) then
        unapprove_entities({entity})
      else
        approve_entities({entity})
      end

    elseif entity.type == "underground-belt" and not entity.neighbours then

      -- If underground belt has no matching underground belt in its own force, try to orient it in same direction as a
      -- matching underground belt in complement force (if any) - but only if the matching underground belt from
      -- complement force is not already paired up with another undeground belt from its own force.
      local matching_underground_belt = get_matching_underground_belt(entity, get_complement_force(entity.force))

      if matching_underground_belt and not get_matching_underground_belt(matching_underground_belt, matching_underground_belt.force)
         and entity.belt_to_ground_type == matching_underground_belt.belt_to_ground_type then
        entity.rotate()
      end

    elseif entity.type == "straight-rail" or entity.type == "curved-rail" then
      -- Ideally, this should get handled via on_pre_build event. Unfortunately, when player is quick-building the rails
      -- (as opposed to placing one by one or by dragging), that event never gets triggered. Therefore we are forced to
      -- clean-up since at this point the unapproved ghost is already gone, and we might have bogus placeholders left
      -- behind if the placeholder did not overlap selection box of a rail.
      remove_invalid_nearby_placeholders(entity.surface, entity.position)
    end

  end,
  {{ filter="type", type="entity-ghost"}, {filter="type", type="underground-belt"}, {filter="type", type="straight-rail"}, {filter="type", type="curved-rail"}}
)


script.on_event(defines.events.on_player_setup_blueprint,
  function(event)
    -- Note: this event fires not just for blueprints, but for copy operations as well
    -- game.print("construction-planner: on_player_setup_blueprint, event=" .. serpent.block(event));

    local player = game.players[event.player_index]

    local adjust_blueprint = function(blueprint)
      local blueprintEntities = blueprint.get_blueprint_entities()
      if blueprintEntities and #blueprintEntities > 0 then
        local placeholderEntities = filter(blueprintEntities, function(id, blueprintEntity)
          return is_bp_placeholder(blueprintEntity)
        end)
        
        if placeholderEntities and table_size(placeholderEntities) > 0 then
          local force = get_or_create_unapproved_ghost_force(player.force)
          local unapprovedEntities = get_entities_as_blueprint_entities(event.surface, force, event.area)

          local unapprovedEntitiesByPosition = remap(unapprovedEntities, function(id, blueprintEntity)
            return position_string(blueprintEntity.position), blueprintEntity
          end)

          local replacementEntities = remap(placeholderEntities, function(id, placeholderEntity)
            local replacementEntity = unapprovedEntitiesByPosition[position_string(placeholderEntity.position)]
            if replacementEntity then
              replacementEntity.entity_number = placeholderEntity.entity_number
              return id, replacementEntity
            else
              return id, nil
            end
          end)

          -- Fix up the circuit connections
          -- game.print("Fixing up circuit connections on " .. tostring(#replacementEntities) .. " replacement entities")
          for id, replacementEntity in pairs(replacementEntities) do
            if replacementEntity.connections then
              for _, connection in pairs(replacementEntity.connections) do
                for color, connectedEntityRefs in pairs(connection) do
                  for _, connectedEntityRef in pairs(connectedEntityRefs) do
                    local replacement_id = unapprovedEntities[connectedEntityRef.entity_id].entity_number
                    connectedEntityRef.entity_id = replacement_id
                  end
                end
              end
            end
          end

          -- Apply the replacement entities
          for id, replacementEntity in pairs(replacementEntities) do
            blueprintEntities[id] = replacementEntity
          end

          -- Uncomment for debugging only
          -- game.print("Blueprint updated to replace placeholders")
          -- for id, blueprintEntity in pairs(blueprintEntities) do
          --   game.print("blueprintEntities[" .. id .. "] = " .. serpent.line(blueprintEntity))
          -- end

          blueprint.clear_blueprint()
          blueprint.set_blueprint_entities(blueprintEntities)
        end
      end
    end

    -- Cover both creation of blueprint (first condition), and use of cut/copy/paste tools (cursor check).
    if (player.blueprint_to_setup.valid_for_read) then
      adjust_blueprint(player.blueprint_to_setup)
    elseif (player.is_cursor_blueprint()) then
      adjust_blueprint(player.cursor_stack)

      -- Player may have set-up the blueprint by invoking the cut-paste-tool. Store:
      --
      --   - age, assuming that related on_pre_ghost_deconstructed will get executed in the same tick.
      --   - area, that can be used for deconstructing all unapproved ghost entities.
      --   - surface, for completeness sake when doing condition checks in on_pre_ghost_deconstructed.
      global.player_setup_blueprint = global.player_setup_blueprint or {}
      global.player_setup_blueprint[player.index] = global.player_setup_blueprint[player.index] or {}
      global.player_setup_blueprint[player.index].age = event.tick
      global.player_setup_blueprint[player.index].area = event.area
      global.player_setup_blueprint[player.index].surface = event.surface
    end
  end
)


script.on_event(defines.events.on_pre_ghost_deconstructed,
  function(event)
    -- Assume that the player had invoked ghost deconstruction using deconstruction planner, and simply destroy the
    -- placeholder ghost entity. This prevents it from ending-up in the undo queue.
    --
    -- Unapproved ghost entities are then destroyed as part of on_player_deconstructed_area event. This is done in order
    -- to have the unapproved ghost entities become part of the undo queue (see the mentioned handler for more details).
    --
    -- @TODO: The on_player_deconstructed_area event will not trigger if scripts invoke
    --        LuaEntity::order_deconstruction() or LuaSurface::deconstruct_area() functions. This needs to be handled in
    --        some way, although it may degrade user experience in terms of undo queue.

    local player = event.player_index and game.players[event.player_index] or nil
    local entity = event.ghost

    -- Drop the placholder entity.
    if is_placeholder(entity) then

      -- If script triggered this (using LuaEntity::order_deconstruction() or LuaSurface::deconstruct_area()) without
      -- assignment to player, remove the unapproved ghost entity, and also proceed to destroy the ghost.
      if not player then
        remove_unapproved_ghost_for(entity)
        entity.destroy()

      -- If player triggered this using a deconstruction planner, only destroy the placeholder ghost entity
      -- itself. Removal of unapproved ghost entities will be taken care of by the on_player_deconstructed_area event
      -- handler, preserving the undo queue in the process. The second condition is used in cases where play might be
      -- holding deconstruction planner from the library (but there is no explicit check for it).
      elseif player and player.cursor_stack and player.cursor_stack.valid_for_read and player.cursor_stack.name == "deconstruction-planner" or
             player and player.cursor_stack and not player.cursor_stack.valid_for_read and not player.is_cursor_empty() and not player.is_cursor_blueprint() then
        entity.destroy()

      -- If player triggered this using the cut-and-paste tool, check if a blueprint had been set-up in the same tick as
      -- this event, and deconstruct an entire affected area. This should store all unapproved ghost entities from that
      -- entire area within the same item in the undo queue, instead of having one per unapproved ghost entity in the
      -- cut-and-pasted area.
      --
      -- Caveats/notes:
      --
      -- 1. If there is a mix of approved and unapproved ghost entities, they will be stored as two distinct items in
      --    the undo queue.
      --
      -- 2. Deconstruction planner has been set-up to blacklist trees and rocks, so those will not get
      --    included. However, cliffs are not covered by this black-listing - therefore we invoke canceling of area
      --    deconstruction at the very end to ensure that cliffs are not marked for deconstruction by the unapproved
      --    ghost force. We have to do this (alongside black-listing of trees/rocks) because player will not be able to
      --    cancel deconstruction orders for the unapproved ghost force (and they should not be deconstructed in the
      --    first place by the cut-paste-tool anyway).
      --
      elseif player and player.cursor_stack and player.cursor_stack.valid_for_read and player.cursor_stack.name == "cut-paste-tool" and
             global.player_setup_blueprint[player.index].age == event.tick and
             global.player_setup_blueprint[player.index].surface == entity.surface then

        local deconstruction_planner = get_deconstruction_planner()
        local surface = entity.surface

        deconstruction_planner.deconstruct_area {
          surface = surface,
          force = get_or_create_unapproved_ghost_force(player.force),
          area = global.player_setup_blueprint[player.index].area,
          skip_fog_of_war = false,
          by_player = player
        }

        -- Ensure that unapproved ghost force does not have any deconstruct orders left-over in the area. Primarily we
        -- want to prevent deconstruction of cliffs.
        deconstruction_planner.cancel_deconstruct_area {
          surface = surface,
          force = get_or_create_unapproved_ghost_force(player.force),
          area = global.player_setup_blueprint[player.index].area,
          skip_fog_of_war = false,
        }

      -- Script triggered the removal, and assigned it to player. Destroy placeholder entity directly (to prevent it
      -- from reaching player's undo queue), and destroy the unapproved ghost entity through deconstruction planner (to
      -- place it in the undo queue).
      --
      -- Caveats/notes:
      --
      -- 1. When using the LuaEntity::order_deconstruction() invocation, even when player is assigned, it will not place
      --    anything in player's undo queue. But... We simply cannot distinguish between this function all and the
      --    LuaSurface::deconstruct_area() one. Which means we would pollute plater's undo queue this way. Not sure how
      --    to solve it, truth be told.
      --
      -- 2. We cannot have a single step in undo queue for LuaSurface::deconstruct_area(), since area information is not
      --    available at this stage, and it triggers the "on_marked_for_deconstruction" event only if at least one
      --    non-ghost entity was in the selection. So we will end-up messing with player's undo queue quite a bit here.
      --
      -- 3. It might be better to simplify the code instead, and just drop this entire else block. What would be lost
      --    then is eventual correctness of interaction with other mods that might be using the above Lua functions for
      --    something with expectation that the player's undo queue is preserved.
      else

        local deconstruction_planner = get_deconstruction_planner()
        local surface = entity.surface
        local force = entity.force
        local position = entity.position

        get_deconstruction_planner().deconstruct_area{
          surface = surface,
          force = get_or_create_unapproved_ghost_force(force),
          area = {{position.x, position.y}, {position.x, position.y}},
          skip_fog_of_war = false,
          by_player = player}

        -- Ensure that unapproved ghost force does not have any deconstruct orders left-over in the area. Primarily we
        -- want to prevent deconstruction of cliffs (see explanation for similar code in cut-and-paste handler above).
        deconstruction_planner.cancel_deconstruct_area {
          surface = surface,
          force = get_or_create_unapproved_ghost_force(force),
          area = {{position.x, position.y}, {position.x, position.y}},
          skip_fog_of_war = false,
        }

        entity.destroy()
      end

    -- If an unapproved ghost entity is somehow getting removed, make sure the placeholders are gone as
    -- well.
    elseif (is_unapproved_ghost_force(entity.force)) then
      remove_placeholder_for(entity)
      return
    end

  end
)


-- Note: this includes when the player right-clicks on ghost entities 
script.on_event(defines.events.on_player_mined_entity,
  function(event)
    -- game.print("construction-planner: on_player_mined_entity, event=" .. serpent.block(event));
    local entity = event.entity
    
    -- If an unapproved entity was mined, find and remove the placeholder as well
    if (is_unapproved_ghost_force(entity.force)) then
      -- game.print("Unapproved ghost mined: " .. entity_debug_string(entity))
      remove_placeholder_for(entity)
    end
  end,
  {{filter="type", type="entity-ghost"}}
)


script.on_event(defines.events.on_pre_build,
  function(event)
    -- If the player is about to build an entity in the same exact position as an unapproved ghost, approve the ghost
    -- before the build happens.  This restores the ghost to the main force so that any special logic like recipe
    -- preservation will be handled properly when the entity gets built.

    local player = game.players[event.player_index]
    local cursor_stack = player.cursor_stack

    -- Do not approve the ghost if player is in process of placing ghosts. This will also deal with "fake" approvals
    -- when player is quickly dragging with a ghost entity (basically the on_pre_build will get triggered while still on
    -- top of the ghost placed in previous step, and approve it by mistake).
    if event.shift_build or cursor_stack and (cursor_stack.is_blueprint or not cursor_stack.valid_for_read) then
      return
    end

    -- Selection tools can be used to build entities as they are being dragged across the screen. If player is building
    -- entities with a selection tool, make sure to validate that the selection tool places entities that are selectable
    -- before approving the underlying unapproved ghosts. Tapeline is an example of a mod that behaves in this manner.
    -- Unfortunately, it does not seem possible to more closely detect what entity would get placed during this event.
    if cursor_stack and cursor_stack.is_selection_tool and
      cursor_stack.prototype.place_result and not cursor_stack.prototype.place_result.selectable_in_game then
      return
    end

    -- When dragging with "gappable" item stacks, they produce the on_pre_build event on every tile passed-over without
    -- actually building any entity. Detect use of such items and prevent ghost approval for them.
    -- @TODO: Check on modding forum if this is an actual bug in modding API or not.
    if cursor_stack and cursor_stack.valid_for_read and cursor_stack.prototype then
      local place_type = cursor_stack.prototype.place_result and cursor_stack.prototype.place_result.type

      -- Use selection box of the item that the user is currently holding to find overlap with unapproved ghost entities.
      local box = cursor_stack.prototype.place_result.selection_box
      local area = {
          { event.position.x + box.left_top.x, event.position.y + box.left_top.y },
          { event.position.x + box.right_bottom.x, event.position.y + box.right_bottom.y },
        }
      local unapproved_ghosts = player.surface.find_entities_filtered {
        area = area,
        force = get_or_create_unapproved_ghost_force(player.force),
        name = "entity-ghost"
      }

      if #unapproved_ghosts > 0 then

        -- Draggable entities that create gaps produce on_pre_build event every tile they are dragged, even if no entity
        -- gets built. Some special processing needs to happen to have the undo queue behave correctly and to avoid
        -- ending-up with bogus placeholders. See documentation for process_unapproved_ghosts_correction_queue function
        -- for more details.
        if event.created_by_moving and place_type == "underground-belt" or place_type == "electric-pole" or place_type == "pipe-to-ground" then
          global.unapproved_ghosts_correction_queue = global.unapproved_ghosts_correction_queue or {}
          for _, ghost in pairs(unapproved_ghosts) do
            global.unapproved_ghosts_correction_queue[ghost.unit_number] = ghost
          end

          -- Ensure that the correction queue gets processed during next game tick.
          script.on_event(defines.events.on_tick, process_unapproved_ghosts_correction_queue)
        end

        approve_entities(unapproved_ghosts)
      end
    end

    local unapproved_ghosts = player.surface.find_entities_filtered {
      position = event.position,
      force = get_or_create_unapproved_ghost_force(player.force),
      name = "entity-ghost"
    }

    if #unapproved_ghosts > 0 then
      -- game.print("Approving " .. #unapproved_ghosts .. " ghosts on pre-build")
      approve_entities(unapproved_ghosts)
    end

  end
)


script.on_event(defines.events.script_raised_revive,
  function(event)
    -- game.print("construction-planner: " .. event.name .. " for " .. entity_debug_string(event.entity))
    -- Note: this bit of code is to check whenever a script raises a revive event, if the revived entity somehow got
    --       placed on the unapproved ghost force by accident, and if so, resolve the issue by reassigning the entity to
    --       the main player force.  This is to resolve a compatibility issue between this mod and the Creative Mod mod,
    --       as well as potentially other mods too (the mod does have to use the raise_* flag however)
    local entity = event.entity
    local base_force = get_base_force(entity.force)
    if (entity.force ~= base_force) then
      remove_placeholder_for(entity)
      entity.force = base_force
    end
  end
)


script.on_event("toggle-auto-approve",
  function(event)
    -- game.print("construction-planner: " .. event.input_name .. " (customInput)")
    toggle_auto_approval(event.player_index)
  end
)


script.on_event(defines.events.on_lua_shortcut,
  function(event)
    if (event.prototype_name == "toggle-auto-approve") then
      -- game.print("construction-planner: " .. event.prototype_name .. " (shortcut)")
      toggle_auto_approval(event.player_index)
    end
  end
)


script.on_event(defines.events.on_runtime_mod_setting_changed,
  function(event)
    -- game.print("construction-planner: " .. event.name .. " for " .. event.setting)
    if (event.setting == SETTING_AUTO_APPROVE) then
      local player = game.get_player(event.player_index)
      player.set_shortcut_toggled("toggle-auto-approve", is_auto_approval_enabled(player))
    end
  end
)


script.on_configuration_changed(
  function(data)
    -- Migrate data from the old Construction Planner. This requires iterating over all forces and surfaces and updating data as necessary.
    -- Approval badges need to be recreated for each ghost entity.
    if data.mod_changes['ConstructionPlanner'] and data.mod_changes['ConstructionPlanner'].new_version == nil then
      for _, force in pairs(game.forces) do
        for _, surface in pairs(game.surfaces) do

          -- Depending on force type we need to show badges with different indicators.
          local show_badge_function

          if is_unapproved_ghost_force(force) then
            show_badge_function = approvalBadges.showUnapproved
          else
            show_badge_function = approvalBadges.showApproved
          end

          local ghost_entities = surface.find_entities_filtered {
            force = force,
            name = "entity-ghost"
          }

          for _, entity in pairs(ghost_entities) do
            if not is_placeholder(entity) then
              local badge_id = approvalBadges.getOrCreate(entity)
              show_badge_function(badge_id)
            end
          end

        end
      end
    end
  end
)


script.on_event(defines.events.on_player_deconstructed_area,
  function(event)
    -- At this point, the placeholder ghost entities should already be gone. This handler takes care of removing the
    -- unapproved ghost entities in such a manner that they end-up on player's undo queue.

    local player = game.players[event.player_index]

    -- Bail-out if player is canceling deconstruction.
    if event.alt then
      return
    end

    -- If player is using deconstruction planner from inventory, we can simply reuse it against the area, just against
    -- the unapproved ghost force. However, if it comes from the library, we simply cannot get _any_ information about
    -- it whatsoever, and resort to removing all unapproved ghosts instead.
    if player.cursor_stack and player.cursor_stack.valid_for_read and player.cursor_stack.name == "deconstruction-planner" then

      -- Make sure we do not touch the tiles (we can even crash the game this way apparently).
      local saved_tile_selection_mode = player.cursor_stack.tile_selection_mode
      player.cursor_stack.tile_selection_mode = defines.deconstruction_item.tile_selection_mode.never

      player.cursor_stack.deconstruct_area{
        surface = event.surface,
        force = get_or_create_unapproved_ghost_force(player.force),
        area = event.area,
        skip_fog_of_war = false,
        by_player = player
      }

      -- Restore player's destruction planner to original state.
      player.cursor_stack.tile_selection_mode = saved_tile_selection_mode

      local unapproved_ghosts = event.surface.find_entities_filtered {
        area = event.area,
        force = get_or_create_unapproved_ghost_force(player.force),
        type = "entity-ghost",
      }

      if player.cursor_stack.entity_filter_mode == defines.deconstruction_item.entity_filter_mode.blacklist then
        for _, unapproved_ghost in pairs(unapproved_ghosts) do
          remove_placeholder_for(unapproved_ghost)
          create_placeholder_for(unapproved_ghost)
        end
      end
    else
      local deconstruction_planner = get_deconstruction_planner()

      local unapproved_ghost_entities = event.surface.find_entities_filtered {
        area = event.area,
        force = get_or_create_unapproved_ghost_force(player.force),
        name = "entity-ghost"
      }

      -- Bail out if there is nothing for us to do here.
      if table_size(unapproved_ghost_entities) == 0 then
        return
      end

      -- Alter deconstruction planner to only remove ghost entities.
      -- @TODO: Refactor this whole mess with deconstruction planners to have multiples for different purposes instead.
      deconstruction_planner.entity_filter_mode = defines.deconstruction_item.entity_filter_mode.whitelist
      deconstruction_planner.trees_and_rocks_only = false
      deconstruction_planner.set_entity_filter(1, "entity-ghost")

      player.create_local_flying_text {
        text = {"warning.cp-library-deconstruction-planners-support"},
        create_at_cursor = true,
      }

      deconstruction_planner.deconstruct_area{
        surface = event.surface,
        force = get_or_create_unapproved_ghost_force(player.force),
        area = event.area,
        skip_fog_of_war = false,
        by_player = player
      }

      -- Reset the deconstruction planner.
      -- @TODO: Refactor this whole mess as per-above.
      deconstruction_planner.entity_filter_mode = defines.deconstruction_item.entity_filter_mode.blacklist
      deconstruction_planner.trees_and_rocks_only = true
      deconstruction_planner.set_entity_filter(1, nil)
    end

  end
)


script.on_event(defines.events.on_player_rotated_entity,
  function(event)
    local entity = event.entity

    -- Try to rotate the base force and unapproved ghost force underground belts when they match each-other.
    if entity.name == "entity-ghost" and entity.ghost_type == "underground-belt" or
       entity.type == "underground-belt" then

      -- Grab both same-force and complement force matching underground belts.
      local force_underground = get_matching_underground_belt(entity, entity.force)
      local complement_force_underground = get_matching_underground_belt(entity, get_complement_force(entity.force))

      -- Let the game engine handle undergrounds belonging to same force, and for underground belts from complemental
      -- forces rotate them only if they match each-other.
      if not force_underground and complement_force_underground and
         not get_matching_underground_belt(complement_force_underground, complement_force_underground.force) and
         get_matching_underground_belt(complement_force_underground, entity.force) == entity and
         entity.belt_to_ground_type == complement_force_underground.belt_to_ground_type then
        complement_force_underground.rotate()
      end
    end
  end
)


script.on_event(defines.events.on_cancelled_deconstruction,
  function(event)
    -- When canceling deconstruction, it can happen that bogus placeholders are left-over because they do overlap with
    -- the selection box of target entity.
    --
    -- One option would be to keep state of all placeholders and/or unapproved ghosts, and register for their
    -- destruction event. This might be the most correct way to do it, but would require more state handling.
    --
    -- The below approach is instead to assume that maximum entity size is 50x50, and try to increase the search area
    -- for leftover placholders, dropping them in the process if they do not have a corresponding unapproved ghost. This
    -- is a bit hacky, and it also might have an impact of performance, though.
    remove_invalid_nearby_placeholders(event.entity.surface, event.entity.position)
  end
)


-------------------------------------------------------------------------------
--       COMMANDS
-------------------------------------------------------------------------------


--- Cleans-up invalid entities and deconstruction orders that may have happened due to bugs etc.
--
-- Takes care of the following:
--
--   - Drops deconstruction orders for unapproved ghost force.
--   - Removes placeholders with no matching entities beneath them.
--   - Creates placeholders for unapproved ghost entities that do not have any.
--
-- @param base_force LuaForce Base force (to which the players belong).
-- @param unapproved_ghost_force LuaForce Unapproved ghost force (which owns the unapproved ghost entities).
--
function cleanup_invalid_entities_and_deconstruction_orders(base_force, unapproved_ghost_force)
  for _, surface in pairs(game.surfaces) do

    -- There was a number of bugs related to handling of cut-and-paste and deconstruction planners that would result in
    -- the unapproved ghost force ordering deconstruction of things like cliffs, trees, rocks etc, which the base force
    -- then cannot clear. Make sure such orders are not present for the unapproved ghost force (this force should not
    -- have any deconstruction orders in the first place).
    local entities_for_deconstruction = surface.find_entities_filtered {
      to_be_deconstructed = true
    }

    for _, entity in pairs(entities_for_deconstruction) do
      if entity.is_registered_for_deconstruction(unapproved_ghost_force) then
        entity.cancel_deconstruction(unapproved_ghost_force)
      end
    end

    -- Placeholders should not exist on their own. Find any that do, and get rid of them.
    local placeholders = surface.find_entities_filtered {
      force = base_force,
      ghost_name = "unapproved-ghost-placeholder",
    }

    for _, placeholder in pairs(placeholders) do
      if table_size(get_unapproved_ghost_for(placeholder)) == 0 then
        placeholder.destroy()
      end
    end

    -- Unapproved ghost entities should exist with one and only one placeholder. Drop excess placeholders, or create the
    -- missing ones.
    local unapproved_ghosts = surface.find_entities_filtered {
      force = unapproved_ghost_force,
      name = "entity-ghost",
    }

    for _, ghost in pairs(unapproved_ghosts) do
      local placeholders = get_placeholder_for(ghost)

      if table_size(placeholders) > 1 then
        table.remove(placeholders)
        for _, placeholder in pairs(placeholders) do
          placeholder.destroy()
        end

      elseif table_size(placeholders) == 0 then
        create_placeholder_for(ghost)
      end

    end

    -- Update approval badges for base force (approved) ghost entities.
    local ghost_entities = surface.find_entities_filtered {
      force = base_force,
      name = "entity-ghost",
    }

    for _, entity in pairs(ghost_entities) do
      if not is_placeholder(entity) then
        local badge_id = approvalBadges.getOrCreate(entity)
        approvalBadges.showApproved(badge_id)
      end
    end

    -- Update approval badges for unapproved ghost force entities.
    local ghost_entities = surface.find_entities_filtered {
      force = unapproved_ghost_force,
      name = "entity-ghost",
    }

    for _, entity in pairs(ghost_entities) do
      if not is_placeholder(entity) then
        local badge_id = approvalBadges.getOrCreate(entity)
        approvalBadges.showUnapproved(badge_id)
      end
    end

  end
end


--- Command for cleaning-up incosistent state created by previous bugs in the mod.
--
-- @param command CustomCommandData Command data as passed-in by the game engine.
--
function command_cp_cleanup(command)
  local player = game.players[command.player_index]
  local unapproved_ghost_force

  global.commands = global.commands or {}
  global.commands.cp_cleanup = global.commands.cp_cleanup or {}

  if not global.commands.cp_cleanup.invoked_at or command.tick - global.commands.cp_cleanup.invoked_at > 600 then
    global.commands.cp_cleanup.invoked_at = command.tick
    player.print({"warning.cp-cleanup-command-confirm"})
    return
  end

  -- Reset the last invocation time.
  global.commands.cp_cleanup.invoked_at = nil

  game.print({"warning.cp-cleanup-command-started"})

  for _, force in pairs(game.forces) do
    if not is_unapproved_ghost_force(force) then
      unapproved_ghost_force = get_or_create_unapproved_ghost_force(force)
      cleanup_invalid_entities_and_deconstruction_orders(force, unapproved_ghost_force)
    end
  end

  game.print({"warning.cp-cleanup-command-finished"})

end

commands.add_command(
  "cp_cleanup",
  "Cleans-up and fixes inconsistencies cause by bugs. Please back-up your savegame before running. Must be invoked twice in row to prevent accidents.",
  command_cp_cleanup
)


-------------------------------------------------------------------------------
--       REMOTE INTERFACES (comment out when not debugging)
-------------------------------------------------------------------------------

-- -- /c remote.call("constructionplanner","badgeScan")
-- remote.add_interface("constructionplanner", {
--   badgeScan = function()
--     ghostEntities = game.player.surface.find_entities_filtered {
--       type = "entity-ghost"
--     }
--     game.print("construction-planner: scanning badges for  "..tostring(#ghostEntities).." ghost entities")
--     for _, entity in pairs(ghostEntities) do
--       local badgeId = approvalBadges.getOrCreate(entity);
--       if is_unapproved_ghost_force(entity.force) then
--         approvalBadges.showUnapproved(badgeId)
--       else
--         approvalBadges.showApproved(badgeId)
--       end
--     end
--   end
-- })
