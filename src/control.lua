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


--- Returns unapproved ghost force.
--
-- Can be used against the unapproved ghost force itself as well.
--
-- @param force LuaForce Force for which to return the unapproved ghost force.
--
-- @return LuaForce Unapproved ghost force.
--
function get_unapproved_ghost_force(force)
  return game.forces[get_unapproved_ghost_force_name(force)]
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


--- Syncs research status of technology between the base and unapproved ghost forces.
--
-- @param technology LuaTechnology Technology to sync the researched status for.
--
function sync_technology(technology)
  local base_force = get_base_force(technology.force)
  local unapproved_ghost_force = get_unapproved_ghost_force(base_force)

  -- Unapproved ghost force has not been created yet (no unapproved ghosts were placed by the base force).
  if not unapproved_ghost_force then
    return
  end

  local base_force_technology = base_force.technologies[technology.name]
  local unapproved_ghost_force_technology = unapproved_ghost_force.technologies[technology.name]

  unapproved_ghost_force_technology.researched = base_force_technology.researched
end


--- Synchronises all technology research status between the base and unapproved ghost forces.
--
-- @param force LuaForce Force to sync the technology research status for. Can be either the base force or unapproved ghosts force.
--
function sync_all_technology(force)
  for _, technology in pairs(force.technologies) do
    sync_technology(technology)
  end
end


--- Synchronises recipe status between the base and unapproved ghost forces.
--
-- @param recipe LuaRecipe Recipe to sync the status for.
--
function sync_recipe(recipe)
  local base_force = get_base_force(recipe.force)
  local base_force_recipe = base_force.recipes[recipe.name]

  local unapproved_ghost_force = get_unapproved_ghost_force(base_force)
  local unapproved_ghost_force_recipe = unapproved_ghost_force.recipes[recipe.name]

  unapproved_ghost_force_recipe.enabled = base_force_recipe.enabled
  unapproved_ghost_force_recipe.hidden_from_flow_stats = base_force_recipe.hidden_from_flow_stats
  unapproved_ghost_force_recipe.productivity_bonus = base_force_recipe.productivity_bonus
end


--- Synchronises all recipes between the base and unapproved ghost forces.
--
-- @param force LuaForce Force to sync the recipes for. Can be either the base force or unapproved ghosts force.
--
function sync_all_recipes(force)
  for _, recipe in pairs(force.recipes) do
    sync_recipe(recipe)
  end
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
    sync_all_technology(force)
    sync_all_recipes(force)

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
  if not storage.blueprintInventory then
    local blueprintInventory = game.create_inventory(1)
    blueprintInventory.insert({ name="blueprint"})
    storage.blueprintInventory = blueprintInventory
  end

  return storage.blueprintInventory[1]
end


--- Returns a player-neutral deconstruction planner used for internal mod processing.
--
-- @return LuaItemStack Deconstruction planner.
--
function get_deconstruction_planner()
  if not storage.deconstruction_planner_inventory then
    storage.deconstruction_planner_inventory = game.create_inventory(1)
    storage.deconstruction_planner_inventory.insert({ name = "deconstruction-planner" })

    -- Make sure that the deconstruction planner cannot be used for deconstructing trees and rocks. Deconstruction
    -- planner is used as a helper tool to preserve correct undo history. However, when used with cut-and-paste, we need
    -- to make sure that the trees and rocks are not affected by it - since normal cut-and-paste tool does not touch
    -- those either.
    storage.deconstruction_planner_inventory[1].entity_filter_mode = defines.deconstruction_item.entity_filter_mode.blacklist
    storage.deconstruction_planner_inventory[1].trees_and_rocks_only = true
  end

  return storage.deconstruction_planner_inventory[1]
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

  function is_selectable(entity)
    return entity.type == "entity-ghost" and entity.ghost_prototype.selectable_in_game
  end

  return entity and entity.valid and entity.type == "entity-ghost" and not is_placeholder(entity) and is_selectable(entity)
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

        -- @TODO: request_from_buffers is not preserved during force change
        --   This behaviour is present in Factorio <= 1.1.109. Once fixed, this workaround should be removed (unless
        --   this is vanilla game's intended behaviour).
        local request_from_buffers = (entity.ghost_prototype.logistic_mode == "requester" and entity.request_from_buffers) or nil

        entity.force = base_force

        if request_from_buffers ~= nil then
          entity.request_from_buffers = request_from_buffers
        end

        remove_placeholder_for(entity)
      end

      local badge = approvalBadges.getOrCreate(entity);
      approvalBadges.showApproved(badge)
    end
  end

end


--- Approves all entities for a force in an area.
--
-- @param force LuaForce Force for which to approve the entities.
-- @param surface LuaSurface Surface on which to search for unapproved ghost entities.
-- @param area BoundingBox Area in which to search for unapporoved ghost entities.
--
-- @return {LuaEntity} List of entities that have been approved.
--
function approve_entities_in_area(force, surface, area)
  local entities = surface.find_entities_filtered {
    area = area,
    force = get_or_create_unapproved_ghost_force(force),
    type = "entity-ghost"
  }

  approve_entities(entities)

  return entities
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

        -- @TODO: request_from_buffers is not preserved during force change
        --   This behaviour is present in Factorio <= 1.1.109. Once fixed, this workaround should be removed (unless
        --   this is vanilla game's intended behaviour).
        local request_from_buffers = (entity.ghost_prototype.logistic_mode == "requester" and entity.request_from_buffers) or nil

        -- Try to store some basic information about the entity for logging in case it becomes invalid.
        local warning_entity_info = serpent.line(entity)

        entity.force = unapproved_force

        -- This can happen when an unapproved ghost is still present underneath, and the force change of the newly built
        -- entity causes it to become invalid. This happens mainly during super-forced build, and specifically with
        -- transport belt (undergrounds, splitters) type of entities. Prevent crash and inform player that a bug was
        -- encountered to avoid having silent fails happen. Avoid spamming the console by showing the warning message
        -- only once.
        if not entity.valid then
          if storage.cp_failed_force_paste_tick ~= game.tick then
            storage.cp_failed_force_paste_tick = game.tick
            game.print({"warning.ca-failed-force-paste", warning_entity_info})
          end
          return
        end

        if request_from_buffers ~= nil then
          entity.request_from_buffers = request_from_buffers
        end

        -- Rotate the underground belt if required.
        if rotate_entity then
          entity.rotate()
        end
      end

      create_placeholder_for(entity)
      local badge = approvalBadges.getOrCreate(entity);
      approvalBadges.showUnapproved(badge)
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
  if storage.unapproved_ghosts_correction_queue then
    -- Ghosts that are still valid have obvisouly not been replaced, so they should be switched back to their original
    -- (unapproved) state.
    for unit_number, ghost in pairs(storage.unapproved_ghosts_correction_queue) do
      if ghost.valid then
        unapprove_entities({ghost})
      end
    end

    -- Mark the queue as processed.
    storage.unapproved_ghosts_correction_queue = nil

    -- The queue has been processed, deregister handler to avoid performance issues.
    script.on_event(defines.events.on_tick, nil)
  end
end


--- Deconstructs unapproved ghosts in an area using a deconstruction planner.
--
-- Caveat: This function will deconstruct both unapproved _and_ approved entities. It is primarily meant for use where a
-- player has already made a pass with a deconstruction planner, or when targeting singular entities.
--
-- @param player LuaPlayer Player on whose behalf the deconstruction is taking place.
-- @param deconstruction_planner LuaItemStack Deconstruction planner to use.
-- @param surface LuaSurface Surface on which to perform the deconstruction.
-- @param area BoundingBox Area on passed-in surface to encompass with the deconstruction planner.
--
-- @return bool true, if at least one unapproved ghost has been deconstructed, false otherwise.
--
function deconstruct_unapproved_ghosts(player, deconstruction_planner, surface, area)

  -- In order for deconstruction planner to have an effect on them, all entities must belong to player's base
  -- force. Approve all unapproved ghost entities in the area first (so they can be affected by player's deconstruction
  -- planner).
  local target_entities = approve_entities_in_area(player.force, surface, area)

  -- Nothing to do, bail-out immediatelly (optimisation).
  if table_size(target_entities) == 0 then
    return false
  end

  -- Prepare a list of environment (neutral) entities that have not been already marked for
  -- deconstruction. Deconstruction planner might affect them, so we want to ensure their deconstruction state is
  -- preserved - only the (just-approved) entities should be taken into the account.
  local preserved_environment_entities = surface.find_entities_filtered {
    area = area,
    type = {"cliff", "fish"},
    to_be_deconstructed = false,
  }

  -- Assumes that previously stored item in the undo stack is the one with unapproved ghosts. This might be wrong in
  -- cases where other mods are plugging in into the API that modifies the undo queue as well.
  cleanup_undo_stack_item(player, 1)

  deconstruction_planner.deconstruct_area {
    surface = surface,
    force = player.force,
    area = area,
    skip_fog_of_war = false,
    by_player = player
  }

  -- Restore deconstruction state of preserved environment entities.
  for _, entity in pairs(preserved_environment_entities) do
    entity.cancel_deconstruction(player.force)
  end

  -- Deconstruction planner might have filters that do not affect all of the unapproved ghosts. Make sure to unapprove
  -- any remaining ghost entities.
  unapprove_entities(target_entities)

  -- Check if any entity is now invalid (it has been deconstructed).
  for _, entity in pairs(target_entities) do
    if not entity.valid then
      return true
    end
  end

  return false
end


--- Cleans unapproved ghost placeholders from undo stack item.
--
-- If the action is empty after the cleanup, it is removed from the player's undo stack altogether.
--
-- @param player LuaPlayer Player owning the undo/redo stack.
-- @param item_index uint Undo stack item index.
--
function cleanup_undo_stack_item(player, item_index)
  local stack = player.undo_redo_stack
  local actions = stack.get_undo_item(item_index)

  -- Must iterate in reverse order in order to keep the action indices stable.
  for i = #actions, 1, -1 do
    if actions[i] and actions[i].target and actions[i].target.name == "unapproved-ghost-placeholder" then
      stack.remove_undo_action(item_index, i)
      actions[i] = nil
    end
  end

  if #actions == 0 then
    stack.remove_undo_item(item_index)
  end
end


--- Calculates dimensions (width and height) of a blueprint based on passed-in blueprint entities.
--
-- The width and height are rounded-up in the process, and orientation is taken into account (swapping width/height as
-- necessary).
--
-- @param blueprint LuaItemStack|LuaRecord Blueprint to get the dimensions for.
-- @param blueprint_orientation defines.direction Direction that the blueprint is facing.
--
-- @return {uint, uint} Width and height of a blueprint. Zero if an empty list of blueprints is passed-in.
--
function get_blueprint_dimensions(blueprint, blueprint_orientation)
  local blueprint_entities = blueprint.get_blueprint_entities()

  if table_size(blueprint_entities) == 0 then
    return 0, 0
  end

  -- Use center of the first blueprint entity as a starting point (corners will always expand beyond this).
  local left_top = { x = blueprint_entities[1].position.x, y = blueprint_entities[1].position.y }
  local right_bottom = { x = blueprint_entities[1].position.x, y = blueprint_entities[1].position.y }

  for _, blueprint_entity in pairs(blueprint_entities) do
    local box = get_entity_prototype_bounding_box(prototypes.entity[blueprint_entity.name], blueprint_entity.direction, blueprint_entity.position)
    left_top.x = math.min(box.left_top.x, left_top.x)
    left_top.y = math.min(box.left_top.y, left_top.y)
    right_bottom.x = math.max(box.right_bottom.x, right_bottom.x)
    right_bottom.y = math.max(box.right_bottom.y, right_bottom.y)
  end

  local width = math.ceil(right_bottom.x - left_top.x)
  local height = math.ceil(right_bottom.y - left_top.y)

  -- Swap the height/width if the blueprint has been rotated by 90 degrees.
  if blueprint_orientation == defines.direction.east or blueprint_orientation == defines.direction.west then
    width, height = height, width
  end

  return width, height
end


--- Calculates bounding box for a blueprint placed at the passed-in map position.
--
-- Calculated bounding box is rounded up as necessary to cover full tiles, and the blueprint width and height is taken
-- into the account when determining the blueprint center (odd vs even width and height will have slightly different
-- centers).
--
-- @param blueprint LuaItemStack|LuaRecord Blueprint to get the bounding box for.
-- @param blueprint_orientation defines.direction Direction that the blueprint is facing.
-- @param position MapPosition Position at which the blueprint should be placed. Normally cursor position.
--
-- @return BoundingBox Bounding box that blueprint occupies on the map.
--
function get_blueprint_bounding_box(blueprint, blueprint_orientation, position)
  local width, height = get_blueprint_dimensions(blueprint, blueprint_orientation)

  -- Pick the larger value between blueprint (entity-based) dimensions and snap width and height to be on the safe side.
  if  blueprint.blueprint_snap_to_grid then
    local snap_width, snap_height = blueprint.blueprint_snap_to_grid.x, blueprint.blueprint_snap_to_grid.y

    if blueprint_orientation == defines.direction.east or blueprint_orientation == defines.direction.west then
      snap_width, snap_height = snap_height, snap_width
    end

    -- @TODO: Approve larger area to deal with event.position imprecision when acting upon on_pre_build event
    --   The passed-in position is normally the cursor position, which may not align with blueprint center when dragging
    --   across with tileable (snap-to-grid) blueprints. Therefore assume that the potential bounding box is twice the
    --   size of the blueprint
    width = math.max(width, snap_width * 2)
    height = math.max(height, snap_height * 2)
  end

  -- Determine the center position. Depending on whether the height/width are even or odd, it can be either in the
  -- very center of a tile or between two tiles.
  local center = {}
  if width % 2 == 0 then
    center.x = position.x >= 0 and math.floor(position.x + 0.5) or math.ceil(position.x - 0.5)
  else
    center.x = math.floor(position.x) + 0.5
  end

  if height % 2 == 0 then
    center.y = position.y >= 0 and math.floor(position.y + 0.5) or math.ceil(position.y - 0.5)
  else
    center.y = math.floor(position.y) + 0.5
  end

  -- Offset the corners based on width/height, and make sure to encircle entire tiles (just in case).
  local bounding_box = {left_top = {}, right_bottom = {}}

  bounding_box.left_top.x = math.floor(center.x - width / 2)
  bounding_box.left_top.y = math.floor(center.y - height / 2)
  bounding_box.right_bottom.x = math.ceil(center.x + width / 2)
  bounding_box.right_bottom.y = math.ceil(center.y + height / 2)

  return bounding_box
end


--- Calculates bounding box for an entity placed at  the passed-in map position.
--
-- Calculated bounding box is rounded up as necessary to cover full tiles, and the entity (prototype) width and height
-- are taken into the account when determining the center point of the bounding box (odd vs even width and height will
-- have slightly different centers).
--
-- @param entity_prototype LuaEntityPrototype Prototype of entity to calculate the bounding box for.
-- @param entity_orientation defines.direction Direction that the entity is facing.
-- @param position MapPosition Position at which the entity should be placed. Normally cursor position.
--
-- @return BoundingBox Bounding box that entity ouccupies on the map.
--
function get_entity_prototype_bounding_box(entity_prototype, entity_orientation, position)
  local width = entity_prototype.tile_width
  local height = entity_prototype.tile_height

  -- Swap the height/width if the entity has been rotated by 90 degrees.
  if entity_orientation == defines.direction.east or entity_orientation ==defines.direction.west then
    height, width = width, height
  end

  -- Determine the center position. Depending on whether the height/width are even or odd, it can be either in the
  -- very center of a tile or between two tiles.
  local center = {}
  if width % 2 == 0 then
    center.x = position.x >= 0 and math.floor(position.x + 0.5) or math.ceil(position.x - 0.5)
  else
    center.x = math.floor(position.x) + 0.5
  end

  if height % 2 == 0 then
    center.y = position.y >= 0 and math.floor(position.y + 0.5) or math.ceil(position.y - 0.5)
  else
    center.y = math.floor(position.y) + 0.5
  end

  -- Offset the corners based on width/height, and make sure to encircle entire tiles (just in case).
  local bounding_box = {left_top = {}, right_bottom = {}}

  bounding_box.left_top.x = math.floor(center.x - width / 2)
  bounding_box.left_top.y = math.floor(center.y - height / 2)
  bounding_box.right_bottom.x = math.ceil(center.x + width / 2)
  bounding_box.right_bottom.y = math.ceil(center.y + height / 2)

  return bounding_box
end


--- Retrieves currently selected (non-book) item from the blueprint book.
--
-- @param book LuaItem Blueprint book to grab the item from.
--
-- @return LuaItem|nil Blueprint, deconstructor, upgrade item, or nil if the book is empty.
function get_selected_item_from_blueprint_book(book)
  -- Empty book.
  if not book.active_index then
    return nil
  end

  local inventory = book.get_inventory(defines.inventory.item_main)
  local item = inventory[book.active_index]

  if item.type == "blueprint-book" then
    return get_selected_item_from_blueprint_book(book)
  end

  return item
end


--- Retrieves currently selected (non-book) item from the blueprint book record.
--
-- @param player LuaPlayer Player to get the item for.
-- @param book LuaRecord Blueprint book record to grab the item from.
--
-- @return LuaRecord|nil Blueprint, deconstructor, upgrade item, or nil if the book is empty.
function get_selected_item_from_blueprint_book_record(player, book)
  local record = book.contents[book.get_active_index(player)]

  if not record then
    return nil
  end

  if record.type == "blueprint-book" then
    return get_selected_item_from_blueprint_book_record(player, record)
  end

  return record
end


--- Retrieves blueprint currently held by the player.
--
-- Takes into the account all kinds of variations that the game presents (directly held blueprint, blueprint books,
-- nested blueprint books, as well as their LuaRecord equivalents).
--
-- @param player LuaPlayer Player for which to get the blueprint..
--
-- @return LuaItem|LuaRecord|nil Blueprint currently held by the player or nil if none (might be deconstruction item etc).
function get_held_blueprint(player)
  local cursor_stack = player.cursor_stack
  local cursor_record = player.cursor_record

  local blueprint = nil

  if cursor_stack.is_blueprint then
    blueprint = cursor_stack
  elseif cursor_stack.is_blueprint_book then
    blueprint = get_selected_item_from_blueprint_book(cursor_stack)
  elseif cursor_record and cursor_record.type == "blueprint" then
    blueprint = player.cursor_record
  elseif cursor_record and cursor_record.type == "blueprint-book" then
    blueprint = get_selected_item_from_blueprint_book_record(player, cursor_record)
  end

  -- Make sure the returned item is a blueprint.
  blueprint = blueprint and blueprint.type == "blueprint" and blueprint or nil

  return blueprint
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
      approve_entities_in_area(player.force, event.surface, event.area)
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
        end
    end
  end
)


script.on_event(defines.events.on_built_entity,
  function(event)

    local entity = event.entity
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
    -- NOTE: This event fires for a number of different operations (not just blueprint creation), like copy or cut.

    local player = game.players[event.player_index]
    local blueprint = event.stack

    -- Drop the placeholder entities from the blueprint.
    if blueprint and blueprint.valid then
      local blueprintEntities = blueprint.get_blueprint_entities() or {}
      local filteredBlueprintEntities = filter(
        blueprintEntities,
        function(id, blueprintEntity)
          return not is_bp_placeholder(blueprintEntity)
        end
      )

      if blueprintEntities and table_size(blueprintEntities) ~= table_size(filteredBlueprintEntities) then
          blueprint.set_blueprint_entities(filteredBlueprintEntities)
      end

    end

    -- If action resulted in player holding a blueprint, store additional information to account for use of
    -- cut-and-paste tool:
    --
    --   - age, assuming that related on_pre_ghost_deconstructed will get executed in the same tick.
    --   - area, that can be used for deconstructing all unapproved ghost entities.
    --   - surface, for completeness sake when doing condition checks in on_pre_ghost_deconstructed.
    if (player.is_cursor_blueprint()) then
      storage.player_setup_blueprint = storage.player_setup_blueprint or {}
      storage.player_setup_blueprint[player.index] = storage.player_setup_blueprint[player.index] or {}
      storage.player_setup_blueprint[player.index].age = event.tick
      storage.player_setup_blueprint[player.index].area = event.area
      storage.player_setup_blueprint[player.index].surface = event.surface
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
    -- @TODO: Unfortunately, this bit of code is no longer helping with keeping the placeholders out of the undo
    --        queue. Looks like the undo queue item gets populated prior to this event firing, so we end-up having to
    --        clean up the queue items explicitly. A bunch of the undo queue handling needs to be refactored, but for
    --        now this is kept in place to prevent things breaking.

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
             storage.player_setup_blueprint[player.index].age == event.tick and
             storage.player_setup_blueprint[player.index].surface == entity.surface then

        local deconstruction_planner = get_deconstruction_planner()
        local surface = entity.surface

        deconstruct_unapproved_ghosts(player, deconstruction_planner, surface, storage.player_setup_blueprint[player.index].area)

        -- When invoking the cut-and-paste tool, it looks like the undo queue is not populated straight away, but only
        -- at the very end of the action when the blueprint also gets put into player's hand. This is a minor workaround
        -- that will take care of undo queue clean-up at that point (as a one-off).
        -- @TODO: Check with game devs if this is intended behaviour or accidental.
        script.on_event(defines.events.on_player_cursor_stack_changed,
          function(event)
            cleanup_undo_stack_item(player, 1)
            script.on_event(defines.events.on_player_cursor_stack_changed, nil)
          end
        )

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
        local area = {{position.x, position.y}, {position.x, position.y}}

        deconstruct_unapproved_ghosts(player, deconstruction_planner, surface, area)

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
    -- When player is about to build an entity, approve all overlapping unapproved ghosts before that happens. This way
    -- a number of core game mechanics will kick-in correctly:
    --
    --   - (Now approved) unapproved ghosts will get removed and replaced by entity built on top, or by new enetity
    --     ghosts built using super-forced build.
    --   - The (now approved) unapproved ghosts that are removed by the above will become part of the undo queue.
    --   - Entities built right on top of matching (now approved) unapproved ghosts will inherit the unapproved ghost
    --     configuration (recipes, logic circuit configurations etc).
    --
    -- There are also some peculiar behaviours that need to be taken into account within this event handler:
    --
    --   - When placing new ghosts via dragging, the event will trigger on every single tile the cursor moves over, even
    --     though nothing will get subsequently built on top of that tile (no on_built_entity gets triggered). This
    --     complicates the decison-making process on what unapproved ghosts to apporove.
    --   - Some selection tools (like Tapeline - https://mods.factorio.com/mod/Tapeline) place down new entities as they
    --     are being dragged. These events may also need to be ignored if the placed entity is some kind of temporary
    --     entity, or if it doesn't interact with the underlying entity in any meaningful manner.
    --

    local player = game.players[event.player_index]

    -- Different cursors need to be accessed depending on what the player is holding.
    local cursor_stack = player.cursor_stack   -- regular item (quantity > 0) or inventory blueprint
    local cursor_ghost = player.cursor_ghost   -- ghost item (quantity = 0)
    local cursor_record = player.cursor_record -- library blueprint

    -- Bail-out early if there is nothing that needs to be done - underlying ghosts would not get affected in the
    -- vanilla game mechanics. Sole exception would be building upgraded/downgraded version of ghost entity on top of
    -- existing ghost entity. However, since placeholder ghost entities will conflict with this scenario, we can ignore
    -- even that one.
    if   event.build_mode == defines.build_mode.forced
      or event.build_mode == defines.build_mode.normal and cursor_ghost
      or event.build_mode == defines.build_mode.normal and cursor_stack.is_blueprint
      or event.build_mode == defines.build_mode.normal and cursor_record and cursor_record.type == "blueprint"
    then
      return
    end

    -- Selection tools can be used to build entities as they are being dragged across the screen. If player is building
    -- entities with a selection tool, make sure to validate that the selection tool places entities that are selectable
    -- before approving the underlying unapproved ghosts. Tapeline is an example of a mod that behaves in this manner.
    -- Unfortunately, it does not seem possible to more closely detect what entity would get placed during this event.
    if cursor_stack.is_selection_tool and cursor_stack.prototype.place_result and not cursor_stack.prototype.place_result.selectable_in_game then
      return
    end

    -- Grab the (potential) prototype of individual entity being built.
    local place_result =
         cursor_stack and cursor_stack.valid_for_read and cursor_stack.prototype and cursor_stack.prototype.place_result
      or cursor_ghost and cursor_ghost.name and cursor_ghost.name.place_result
      or cursor_stack.valid_for_read and cursor_stack.prototype and cursor_stack.prototype.place_result
      or nil

    -- Grab the (potential) blueprint being built.
    local blueprint = get_held_blueprint(player)

    -- Calculate area under which the unapproved ghosts should be approved.
    local area = nil
    if place_result then
      area = get_entity_prototype_bounding_box(place_result, event.direction, event.position)
    elseif blueprint then
      local blueprint_entities = blueprint and blueprint.get_blueprint_entities() or {}
      area = get_blueprint_bounding_box(blueprint, event.direction, event.position)
    else
      -- Event was triggered by a script.
      area = {left_top = event.position, right_bottom = event.position}
    end

    -- Approve overlapping unapproved ghosts.
    if area then
      local approved_ghosts = approve_entities_in_area(player.force, player.surface, area)

      -- Set up a correction queue for unapproved ghosts that will be processed in the next tick. This is meant to catch
      -- any unapproved ghosts (that have now been approved) that survive the placement, so that their approval state
      -- can be correctly reset. This also helps deal with building entities by dragging, since those trigger the
      -- on_pre_build event even if nothing gets built at a specific position.
      -- @TODO: Check with devs if it is normal that on_pre_build triggers for every single tile when draggin with an
      --        item, even if nothing will get built.
      if #approved_ghosts > 0 then
        storage.unapproved_ghosts_correction_queue = storage.unapproved_ghosts_correction_queue or {}
        for _, ghost in pairs(approved_ghosts) do
          storage.unapproved_ghosts_correction_queue[ghost.unit_number] = ghost
        end
        script.on_event(defines.events.on_tick, process_unapproved_ghosts_correction_queue)
      end

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

      -- @TODO: request_from_buffers is not preserved during force change
      --   Unfortunately, it is not possible to preserve the original setting here, since the original ghost entity is
      --   already gone at this point.
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

    if player.cursor_stack and player.cursor_stack.valid_for_read and player.cursor_stack.name == "deconstruction-planner" then
      deconstruct_unapproved_ghosts(player, player.cursor_stack, event.surface, event.area)
    elseif player.cursor_record and player.cursor_record.valid and player.cursor_record.type == "deconstruction-planner" then
      -- @TODO: There is a bug in Factorio that seems to prevent player.cursor_record.deconstruct_area from working,
      --        resort to cloning its settings instead. This code could be simplified if the devs address it. Bug report
      --        on forums: https://forums.factorio.com/viewtopic.php?f=7&t=117411
      local deconstruction_planner = get_deconstruction_planner()

      deconstruction_planner.clear_deconstruction_item()
      deconstruction_planner.entity_filters = player.cursor_record.entity_filters
      deconstruction_planner.tile_filters = player.cursor_record.tile_filters
      deconstruction_planner.entity_filter_mode = player.cursor_record.entity_filter_mode
      deconstruction_planner.tile_filter_mode = player.cursor_record.tile_filter_mode
      deconstruction_planner.tile_selection_mode = player.cursor_record.tile_selection_mode
      deconstruction_planner.trees_and_rocks_only = player.cursor_record.trees_and_rocks_only

      deconstruct_unapproved_ghosts(player, deconstruction_planner, event.surface, event.area)

      -- @TODO: Deconstruction planner is primarily used for cut-and-paste tool at this point, and that one expects
      --        specific planner config.
      deconstruction_planner.clear_deconstruction_item()
      deconstruction_planner.entity_filter_mode = defines.deconstruction_item.entity_filter_mode.blacklist
      deconstruction_planner.trees_and_rocks_only = true
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


script.on_event(defines.events.on_player_joined_game,
  function(event)
    local player = game.players[event.player_index]

    -- Make sure that the initial state of the shortcut is correct.
    player.set_shortcut_toggled("toggle-auto-approve", is_auto_approval_enabled(player))
  end
)


-- Will trigger twice, once for base force, once for unapproved ghosts force, but should not enter a loop and will
-- result in consistent state.
script.on_event(defines.events.on_research_finished,
  function(event)
    local technology = event.research
    sync_technology(technology)
  end
)


-- Will trigger twice, once for base force, once for unapproved ghosts force, but should not enter a loop and will
-- result in consistent state.
script.on_event(defines.events.on_research_reversed,
  function(event)
    local technology = event.research
    sync_technology(technology)
  end
)


script.on_event(defines.events.on_force_reset,
  function(event)
    local force = event.force

    if is_unapproved_ghost_force(force) then
      return
    end

    local unapproved_ghost_force = get_unapproved_ghost_force(force)
    if unapproved_ghost_force then
      unapproved_ghost_force.reset()

      force.set_friend(unapproved_ghost_force, true)
      force.set_cease_fire(unapproved_ghost_force, true)

      unapproved_ghost_force.set_friend(force, true)
      unapproved_ghost_force.set_cease_fire(force, true)

      sync_all_diplomacy(force, unapproved_ghost_force)
    end
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

    -- Unapproved ghost placeholders should never exist as an entity - only as a ghost.
    local base_force_built_placeholders = surface.find_entities_filtered {
      force = base_force,
      name = "unapproved-ghost-placeholder",
    }
    for _, placeholder in pairs(base_force_built_placeholders) do
      placeholder.destroy()
    end

    local unapproved_ghost_force_built_placeholders = surface.find_entities_filtered {
      force = unapproved_ghost_force,
      name = "unapproved-ghost-placeholder",
    }
    for _, placeholder in pairs(unapproved_ghost_force_built_placeholders) do
      placeholder.destroy()
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
function command_ca_cleanup(command)
  local player = game.players[command.player_index]
  local unapproved_ghost_force

  storage.commands = storage.commands or {}
  storage.commands.ca_cleanup = storage.commands.ca_cleanup or {}

  if not storage.commands.ca_cleanup.invoked_at or command.tick - storage.commands.ca_cleanup.invoked_at > 600 then
    storage.commands.ca_cleanup.invoked_at = command.tick
    player.print({"warning.ca-cleanup-command-confirm"})
    return
  end

  -- Reset the last invocation time.
  storage.commands.ca_cleanup.invoked_at = nil

  game.print({"warning.ca-cleanup-command-started"})

  for _, force in pairs(game.forces) do
    if not is_unapproved_ghost_force(force) then
      unapproved_ghost_force = get_or_create_unapproved_ghost_force(force)
      cleanup_invalid_entities_and_deconstruction_orders(force, unapproved_ghost_force)
    end
  end

  game.print({"warning.ca-cleanup-command-finished"})

end

commands.add_command(
  "ca_cleanup",
  "Cleans-up and fixes inconsistencies caused by bugs. Please back-up your savegame before running. Must be invoked twice in row to prevent accidents.",
  command_ca_cleanup
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
--       local badge = approvalBadges.getOrCreate(entity);
--       if is_unapproved_ghost_force(entity.force) then
--         approvalBadges.showUnapproved(badge)
--       else
--         approvalBadges.showApproved(badge)
--       end
--     end
--   end
-- })
