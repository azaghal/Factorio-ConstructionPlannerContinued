-- Note: there is no "on_entity_changed_force" event, so I'll have to just update badges as I change the forces in my
--       mod, and hope that other mods don't mess around with the forces too much.  For /editor force changes during
--       testing, I can use a console command + remote interface to manually force a badge rescan.

local core_util = require("util")

local approvalBadges = require("control.approvalBadges")

local UINT32_MAX = 4294967295
local FORCE_REGEX = "(.+)%.unapproved_ghosts"
local SETTING_AUTO_APPROVE = "constructionPlanner-auto-approve"

function is_unapproved_ghost_force_name(force_name)
  return string.match(force_name, FORCE_REGEX) ~= nil
end

function to_unapproved_ghost_force_name(base_force_name)
  return base_force_name .. ".unapproved_ghosts"
end


--- Returns base force name for specified force name.
--
-- Passed-in force name is checked to see if it belongs to approval ghost force, and base force name is caluclated in
-- that case. If passed-in name does not belong to approval ghost force, force name is returned unchanged - force is a
-- base force for itself.
--
-- @param force_name Name of the force.
--
-- @return string Name of the base force.
--
function get_base_force_name(force_name)
  -- Initialise the cache variable.
  global.base_force_mapping_cache = global.base_force_cache or {}

  -- Reuse the cached entry, extract base name from a ghost force name, or otherwise map the force name to itself.
  if not global.base_force_mapping_cache[force_name] then
    global.base_force_mapping_cache[force_name] = string.match(force_name, FORCE_REGEX) or force_name
  end

  return global.base_force_mapping_cache[force_name]
end


function entity_debug_string(entity)
  return entity.type .. " of " .. entity.force.name .. " @ " .. serpent.line(entity.position)
end

function first_match_or_nil(table)
  if table_size(table) == 0 then
    return nil
  else 
    return table[1]
  end
end

function position_string(position)
  local result = tostring(position.x) .. ":" .. tostring(position.y)
  -- game.print("Position string: " .. serpent.line(position) .. " --> " .. result)
  return result
end

-- Remap an associative array using a mapping function of form: (oldKey, oldVal) => (newKey, newVal)
function remap(array, fnMap)
  local result = {}
  for oldKey, oldVal in pairs(array or {}) do
    local newKey, newVal = fnMap(oldKey, oldVal)
    if newKey ~= nil then
      result[newKey] = newVal
    end
  end
  return result
end

-- Filter an associative array using a predicate function of form: (oldKey, oldVal) => isInclude
function filter(array, fnPredicate)
  return remap(array, function(oldKey, oldVal)
    if fnPredicate(oldKey, oldVal) then
      return oldKey, oldVal
    end
    return nil, nil
  end)
end

DIPLOMACY_SYNC_IN_PROGRESS = false
function syncAllDiplomacy(srcForce, destForce)
  -- game.print("Starting diplomacy sync from " .. srcForce.name .. " to " .. destForce.name .. "...")
  DIPLOMACY_SYNC_IN_PROGRESS = true
  for _, force in pairs(game.forces) do
    if (force ~= srcForce and force ~= destForce) then
      destForce.set_friend(force, srcForce.get_friend(force))
      destForce.set_cease_fire(force, srcForce.get_cease_fire(force))
    end
  end
  DIPLOMACY_SYNC_IN_PROGRESS = false
  -- game.print("Diplomacy sync complete")
end

FORCE_CREATION_IN_PROGRESS = false
function get_or_create_unapproved_ghost_force(base_force)
  local unapproved_ghost_force_name = to_unapproved_ghost_force_name(base_force.name)
  if not game.forces[unapproved_ghost_force_name] then
    FORCE_CREATION_IN_PROGRESS = true
    local unapproved_ghost_force = game.create_force(unapproved_ghost_force_name)
    unapproved_ghost_force.set_friend(base_force, true)
    unapproved_ghost_force.set_cease_fire(base_force, true)
    base_force.set_friend(unapproved_ghost_force, true)
    base_force.set_cease_fire(unapproved_ghost_force, true)
    syncAllDiplomacy(base_force, unapproved_ghost_force)
    FORCE_CREATION_IN_PROGRESS = false
  end
  return game.forces[unapproved_ghost_force_name]
end

function get_script_blueprint()
  if not global.blueprintInventory then
    local blueprintInventory = game.create_inventory(1)
    blueprintInventory.insert({ name="blueprint"})
    global.blueprintInventory = blueprintInventory
  end
  return global.blueprintInventory[1]
end


--- Returns a player-neutral deconstruction planner.
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


function to_blueprint_entity(entity)
  local bp = get_script_blueprint()
  bp.clear_blueprint()
  bp.create_blueprint {
    surface = entity.surface,
    force = entity.force,
    area = {{entity.position.x, entity.position.y}, {entity.position.x, entity.position.y}},
    always_include_tiles = false
  }
  -- game.print("to_blueprint_entity: BlueprintEntity = " .. serpent.line(bp.get_blueprint_entities()))
  return first_match_or_nil(bp.get_blueprint_entities())
end

function is_placeholder(entity)
  return entity.type == "entity-ghost" and entity.ghost_name == "unapproved-ghost-placeholder"
end

function is_bp_placeholder(entity)
  return entity.name == "unapproved-ghost-placeholder"
end

function create_placeholder_for(unapproved_entity)
  -- Note: the placeholder has to be a ghost, otherwise it will overwrite the unapproved entity, and mess up the deconstruction planner interaction
  local placeholder = unapproved_entity.surface.create_entity {
    name = "entity-ghost",
    position = unapproved_entity.position,
    force = get_base_force_name(unapproved_entity.force.name),
    inner_name = "unapproved-ghost-placeholder"
  }
  -- game.print("Unapproved entity: " .. entity_debug_string(event.created_entity))
  -- game.print("Placeholder: " .. entity_debug_string(placeholder))
  return placeholder
end

function remove_placeholder_for(unapproved_entity)
  -- Note: this search works only because the placeholder will be at the *same exact position* as the unapproved entity
  local placeholders = unapproved_entity.surface.find_entities_filtered {
    position = unapproved_entity.position,
    force = get_base_force_name(unapproved_entity.force.name),
    ghost_name = "unapproved-ghost-placeholder"
  }

  -- Only one placeholder is expected, but if multiple are discovered for whatever reason, just remove them all
  for _, placeholder in pairs(placeholders) do
    placeholder.destroy()
  end
end

function get_unapproved_ghost_bp_entities(surface, force, area)
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

function remove_unapproved_ghost_for(placeholder)
  local unapproved_ghosts = placeholder.surface.find_entities_filtered {
    position = placeholder.position,
    force = get_or_create_unapproved_ghost_force(placeholder.force),
    name = "entity-ghost"
  }

  -- Only one placeholder is expected, but if multiple are discovered for whatever reason, just remove them all
  for _, unapproved_ghost in pairs(unapproved_ghosts) do
    unapproved_ghost.destroy()
  end
end

function is_auto_approve(player)
  return settings.get_player_settings(player)[SETTING_AUTO_APPROVE].value
end

function toggle_auto_approve(player)
  local modSetting = settings.get_player_settings(player)[SETTING_AUTO_APPROVE]
  modSetting.value = not modSetting.value
  settings.get_player_settings(player)[SETTING_AUTO_APPROVE] = modSetting
end

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
      local base_force_name = get_base_force_name(entity.force.name)

      if entity.force.name ~= base_force_name then
        entity.force = base_force_name
        remove_placeholder_for(entity)
      end

      local badgeId = approvalBadges.getOrCreate(entity);
      approvalBadges.showApproved(badgeId)
    end
  end

end


--- Synchronises (ghost) underground belt rotation with matching ghost underground belt of different force. 
--
-- Matching ghost underground belt is the one that would normally connect to passed-in underground belt if they
-- both belonged to the same force. No changes are made if no matching ghost underground belt can be found.
--
-- The passed-in underground belt is usually the one that has just been placed by the player.
--
-- This allows us to make sure the underground belt pairs have the same rotation prior to setting them to the same
-- force. This has to be done in order to ensure that placed underground belt will correctly match the rotation of the
-- existing, matching ghost underground belt.
--
-- @param underground_belt LuaEntity Regular or ghost underground belt that should be synced to an existing ghost underground belt.
-- @param matching_force LuaForce Force to which the matching ghost underground belt should belong to.
--
function sync_underground_belt_rotation(underground_belt, matching_force)

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

  -- Find the matching ghost underground belt.
  local possible_matching_underground_belts = underground_belt.surface.find_entities_filtered {
    ghost_type = prototype.type,
    ghost_name = prototype.name,
    force = force,
    area = bounding_box
  }

  local matching_underground_belt = underground_belt.surface.get_closest(underground_belt.position, possible_matching_underground_belts)

  -- When underground belts are rotated, we actually change their input/output status (direction in which the items flow
  -- across connected ground belts).
  if matching_underground_belt then

    -- One belt has to be input, while the other has to be output.
    if underground_belt.belt_to_ground_type == matching_underground_belt.belt_to_ground_type then
      underground_belt.rotate()
    end

  end

end


function unapprove_entities(entities)
  local unapprovedForceCache = {}

  for _, entity in pairs(entities) do
    if is_approvable_ghost(entity) then

      -- Determine the unapproved ghost entities force. The entity will already have its force set as one when player invokes undo after removing unapproved
      -- ghost entity (via right-click).
      local unapproved_force
      if not is_unapproved_ghost_force_name(entity.force.name) then
        unapprovedForceCache[entity.force.name] = unapprovedForceCache[entity.force.name] or get_or_create_unapproved_ghost_force(entity.force)
        unapproved_force = unapprovedForceCache[entity.force.name]
      else
        unapproved_force = entity.force
      end

      if (entity.force ~= unapproved_force) then

        -- Try to synchronise the underground belt rotation/direction with existing underground belt belonging to
        -- regular/unapproved ghost force. If we do not do this bit of code, the belts always end-up facing opposite of
        -- what the user would expect (older underground belt direction should take precedence).
        if entity.ghost_prototype.type == "underground-belt" then
          sync_underground_belt_rotation(entity, unapproved_force)
        end

        entity.force = unapproved_force
      end

      create_placeholder_for(entity)
      local badgeId = approvalBadges.getOrCreate(entity);
      approvalBadges.showUnapproved(badgeId)
    end
  end
end


-------------------------------------------------------------------------------
--       EVENTS
-------------------------------------------------------------------------------

script.on_event(defines.events.on_force_friends_changed,
  function(event)
    if not DIPLOMACY_SYNC_IN_PROGRESS and not FORCE_CREATION_IN_PROGRESS then 
      local unapproved_ghost_force = game.forces[to_unapproved_ghost_force_name(event.force.name)]
      if unapproved_ghost_force ~= nil then
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
      local unapproved_ghost_force = game.forces[to_unapproved_ghost_force_name(event.force.name)]
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

      if not is_auto_approve(player) then
        unapprove_entities({entity})
      else
        approve_entities({entity})
      end

    elseif entity.type == "underground-belt" then

      sync_underground_belt_rotation(entity, get_or_create_unapproved_ghost_force(entity.force))

    end

  end,
  {{ filter="type", type="entity-ghost"}, {filter="type", type="underground-belt"}}
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
        
        if placeholderEntities and #placeholderEntities > 0 then
          local force_name = get_or_create_unapproved_ghost_force(player.force).name
          local unapprovedEntities = get_unapproved_ghost_bp_entities(event.surface, force_name, event.area)

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
    
    if (player.blueprint_to_setup.valid_for_read) then
      adjust_blueprint(player.blueprint_to_setup)
    end
    if (player.is_cursor_blueprint()) then
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
      -- holding destruction planner from the library (but there is no explicit check for it).
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
    elseif (is_unapproved_ghost_force_name(entity.force.name)) then
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
    if (is_unapproved_ghost_force_name(entity.force.name)) then
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

    local unapproved_ghost_force_name = to_unapproved_ghost_force_name(player.force.name)
    if game.forces[unapproved_ghost_force_name] then
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
    local base_force_name = get_base_force_name(entity.force.name)
    if (entity.force.name ~= base_force_name) then
      remove_placeholder_for(entity)
      entity.force = base_force_name
    end
  end
)

script.on_event("toggle-auto-approve",
  function(event)
    -- game.print("construction-planner: " .. event.input_name .. " (customInput)")
    toggle_auto_approve(event.player_index)
  end
)
script.on_event(defines.events.on_lua_shortcut,
  function(event)
    if (event.prototype_name == "toggle-auto-approve") then
      -- game.print("construction-planner: " .. event.prototype_name .. " (shortcut)")
      toggle_auto_approve(event.player_index)
    end
  end
)
script.on_event(defines.events.on_runtime_mod_setting_changed,
  function(event)
    -- game.print("construction-planner: " .. event.name .. " for " .. event.setting)
    if (event.setting == SETTING_AUTO_APPROVE) then
      local player = game.get_player(event.player_index)
      player.set_shortcut_toggled("toggle-auto-approve", is_auto_approve(player))
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

          if is_unapproved_ghost_force_name(force.name) then
            show_badge_function = approvalBadges.showUnapproved
          else
            show_badge_function = approvalBadges.showApproved
          end

          local ghost_entities = surface.find_entities_filtered {
            force = force.name,
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
      player.cursor_stack.deconstruct_area{
        surface = event.surface,
        force = get_or_create_unapproved_ghost_force(player.force),
        area = event.area,
        skip_fog_of_war = false,
        by_player = player
      }

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
--       if is_unapproved_ghost_force_name(entity.force.name) then
--         approvalBadges.showUnapproved(badgeId)
--       else
--         approvalBadges.showApproved(badgeId)
--       end
--     end
--   end
-- })
