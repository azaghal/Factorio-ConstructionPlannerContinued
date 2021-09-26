-- Note:  latest plan:
-- 1. Use a friendly force to hold the unapproved entities, as I'm currently doing
--    -  Advantage of this strategy is that it *should* preserve entity config and connections (inventories, filters, wire connections, etc.)
--    -  Preserving config and connections is possible in theory with generated placeholders, but would necessarily be very complex and brittle due to API constraints
--    -  TODO: will undo/redo still work as expected?  (i.e. will both the placeholder entities and unapproved entities be cleared when undoing a stamp?)
--       -  Betting it won't work out-of-the-box, but I expect there should be an event I can listen to so I can fix up things
-- 2. Create 'placeholder' entities - invisible entities that are positioned over the unapproved ghosts and can be selected by selection-tools
--    -  TODO: what to do about placeholder entity right-click?  (i.e. 'mining')?  Since the friendly force is also mineable...
--       -  It might be possible to make the placeholders non-mineable.  Ideally, they should only be interactable via the selection-tools
--    -  Placeholders should be destroyed whenever the unapproved entity is destroyed, and vice-versa
--       -  Events on_pre_ghost_deconstructed + on_player_mined_entity combined should cover the normal circumstancs...are there others though?
-- 3. Blueprint/copy:  do JIT replacement of the placeholder entities in the BP w/ the entities from the unapproved force
--    -  Idea is to generate a BP of the same area from the unapproved force, then swap those entities in for the placeholders in the original BP
--    -  Swap: should be okay to simply remove all placeholder entities from the original BP, then add in all entities from the generated BP
-- 4. Deconstruction:  two potential options
--    -  Option A:  listen to deconstruction events, and replicate the event in the same area on the unapproved force
--       -  TODO: Will the listener trigger though for mod-generated deconstruction events?
--    -  Option B:  listen to on_pre_ghost_deconstructed and replay the deconstruction onto the unapproved force entity
--    -  Even though in theory it's impossible to deconstruct the unapproved ghost entities, should probably sync on it anyways, to be safe (can test from editor)
--       (i.e. listen for unapproved ghost deconstruction events, and remove the linked placeholder entity)
-- 5. Upgrade planner:  likely won't be supported at first; I believe it's theoretically possible but difficult to implement
--    -  Would likely need a full-mirror placeholder tree that properly links upgrade paths to parallel the original upgrade paths
--    -  Might be able to get away with a simplified version, i.e. 'upgradeable-placeholder'
--    -  Also might work to listen to upgrade events and replay the upgrade on the same area for the unapproved force
--    -  Not sure how (if at all) 'customized' upgrade planners could be supported...the custom planner won't have upgrade rules for the placeholders
--       -  Might be possible to do JIT modification of the planner rule-set when the player puts it in their cursor...would be tricky though
-- 6. Modded selection-tools:  not sure if they can be supported; not worrying about for 1.0

-- TODO: implement new plan
--   Done: placeholder prototypes, placeholder creation
--   TBD:  remove placeholder when ghost mined, blueprint JIT replacement, deconstruction linkage, placeholder appearance
-- TODO: test tile ghost behavior
-- TODO: update README.md, changelog, etc. in prep for 1.0 release
-- TODO: flesh out post-1.0 roadmap.  Ideas:
  -- Replace 'draw_text' with 'draw_sprite' and a better icon? (maybe hammer or hammer-and-wrench?)
  -- Improved graphics for the shortcut and/or selection-tool, maybe thumbnail as well
  -- Use "on_entity_changed_force", if Wube decides to add it
  -- Forces library?
  -- More efficient force-based logic?  (regex = slow)
  -- Some sort of toggle switch to temporarily turn off the mod (i.e. move all ghosts to main force, hide badge, etc.) to make it easier to work around BP/upgrade limitations
  -- It might be possible to somehow use faux/placeholder ghost entities, instead of entity force manipulation.  This might be friendlier to BP/upgrading (not guaranteed though)
  -- Mod options, e.g. whether entities should be approved or unapproved when first built (default unapproved)
-- TODO: note limitations
  -- TBD (new plan works around blueprinting/deconstruction, but maybe other limitations?)
-- TODO: release 1.0
-- TODO: make mod API request in forums (not very hopeful but why not try...)
  -- Would like a flag to mark a force as 'ally' or something like that...with the idea being that blueprints, copy/cut/paste, upgrade planner, decon planner, etc. would all work on allied force entities the same as though they were on the player's force
  -- It would follow to share logistics too...but this would mess up my mods!  Not sure yet how to approach that.
    -- Maybe suggest a flag name of 'share_blueprints' or something like that.  Or maybe just suggest 'friend' ought to imply selection-tool functionality (it lets you manually deconstruct already, after all)

-- Note: there is no "on_entity_changed_force" event, so I'll have to just update badges as I change the forces in my
--       mod, and hope that other mods don't mess around with the forces too much.  For /editor force changes during
--       testing, I can use a console command + remote interface to manually force a badge rescan.

local approvalBadges = require("control.approvalBadges")

FORCE_REGEX = "(.+)%.unapproved_ghosts"
function is_unapproved_ghost_force_name(force_name)
  return string.match(force_name, FORCE_REGEX) ~= nil
end

function to_unapproved_ghost_force_name(base_force_name)
  return base_force_name .. ".unapproved_ghosts"
end

function parse_base_force_name(force_name)
  local base_name = string.match(force_name, FORCE_REGEX)
  if base_name then
      return base_name
  else
      return force_name
  end
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

function to_blueprint_entity(entity)
  local bp = get_script_blueprint()
  bp.clear_blueprint()
  bp.create_blueprint {
    surface = entity.surface,
    force = entity.force,
    area = {{entity.position.x, entity.position.y}, {entity.position.x, entity.position.y}},
    always_include_tiles = false
  }
  game.print("construction-planner: BlueprintEntity = " .. serpent.block(bp.get_blueprint_entities()))
  return bp.get_blueprint_entities()
end

function approve_entities(entities)
  local baseForceCache = {}

  for _, entity in pairs(entities) do
    local base_force = baseForceCache[entity.force.name]
    if not base_force then
      local base_force_name = parse_base_force_name(entity.force.name)
      base_force = game.forces[base_force_name]
      baseForceCache[entity.force.name] = base_force
    end
    if (entity.force ~= base_force) then
      entity.force = base_force
      local badgeId = approvalBadges.getOrCreate(entity);
      approvalBadges.showApproved(badgeId)
    end
  end
end

function unapprove_entities(entities)
  local unapprovedForceCache = {}

  for _, entity in pairs(entities) do
    if not is_unapproved_ghost_force_name(entity.force.name) then
      local unapproved_force = unapprovedForceCache[entity.force.name]
      if not unapproved_force then
        unapproved_force = get_or_create_unapproved_ghost_force(entity.force)
        unapprovedForceCache[entity.force.name] = unapproved_force
      end
      if (entity.force ~= unapproved_force) then
        entity.force = unapproved_force

        local badgeId = approvalBadges.getOrCreate(entity);
        approvalBadges.showUnapproved(badgeId)
      end
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
    -- game.print("construction-planner: detected new ghost entity (".. event.created_entity.ghost_name ..")")
    -- to_blueprint_entity(event.created_entity)
    local original_force = event.created_entity.force
    unapprove_entities({event.created_entity})

    function createPlaceholderFor(entity)
      entity.surface.create_entity {
        name = "entity-ghost",
        position = entity.position,
        force = original_force,
        inner_name = "unapproved-ghost-placeholder"
      }
    end
    createPlaceholderFor(event.created_entity)
    
  end,
  {{ filter="type", type="entity-ghost"}}
)

script.on_event(defines.events.on_player_setup_blueprint,
  function(event)
    -- game.print("construction-planner: on_player_setup_blueprint, event=" .. serpent.block(event));

    local adjust_blueprint = function(blueprint)
      -- blueprint.clear_blueprint()
    end
    
    local player = game.players[event.player_index]
    if (player.blueprint_to_setup.valid_for_read) then
      adjust_blueprint(player.blueprint_to_setup)
    end
    if (player.is_cursor_blueprint()) then
      adjust_blueprint(player.cursor_stack)
    end
  end
)

script.on_event(defines.events.on_pre_ghost_deconstructed,
  function(event)
    game.print("construction-planner: on_pre_ghost_deconstructed, event=" .. serpent.block(event));
    -- TODO: if placeholder, deconstruct the actual entity as well
  end
)

-- Note: this includes when the player right-clicks on ghost entities 
script.on_event(defines.events.on_player_mined_entity,
  function(event)
    game.print("construction-planner: on_player_mined_entity, event=" .. serpent.block(event));
    -- TODO: if placeholder, deconstruct the actual entity as well
  end,
  {{ filter="type", type="entity-ghost"}}
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
