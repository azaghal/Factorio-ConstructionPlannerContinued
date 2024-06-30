Construction Planner Continued
==============================


About
-----

*Construction Planner* changes the behavior of how ghost entities are built to give the player more control over planning and building their factory. With the mod, construction bots will no longer be automatically dispatched to build ghosts; instead, the player can use the new *Construction Planner* selection tool to approve construction of the ghosts; only then will the bots be dispatched.

Why to use the *Construction Planner*?

-   Plan ahead and stamp out entire factory ahead of time as ghosts, and approve sections as needed; control what sections get built first.
-   Mouse slipped and that blueprint stamp is off by a tile? No need to rush - the bots have not been dispatched yet, and there is plenty of time to fix it.
-   Tweak blueprint inputs and outputs without worrying that bots will unleash a flood of resources into the unfinished factory.
-   Plan out an entire perimeter defense, without worrying about the bots getting ahead and building partial, non-functional defensive segments. Strategically prioritize construction of key defensive locations.
-   Stamp out a huge solar field and approve it in chunks, thus avoiding bots building solar panels and accumulators disconnected from the main grid.

The mod can be see in action by checking out Xterminator's excellent [mod spotlight video](https://www.youtube.com/watch?v=UNAXhiTBu9M). **NOTE:** The video reviews a fairly outdated version of mod, but provides excellent overview of its capabilities.


Features
--------

-   Ghost entities are no longer built automatically by construction bots, and must be approved by a player first. **NOTE:** Ghosts created in place of destroyed entities do not require approval, and are rebuilt as usual.
-   *Construction Planner* selection tool can be used to approve (by dragging) and unapprove (by shift-dragging) ghosts for construction.
-   Auto-approval toggle can be used to change behaviour for newly placed ghosts for faster building when necessary.
-   Unapproved ghosts can be used for creating and updating blueprints as usual.


Contributions
-------------

Should you come upon bugs, or have features and ideas on how to make the mod better, please do not hesitate to voice your feedback either through mod portal discussion page, or through project's issue tracker. Pull requests for implementing new features and fixing encountered issues are always welcome.


Known issues
------------

-   Upgrade planner cannot be used against unapproved ghosts.
-   Unapproved ghosts selected with any cut/copy/blueprint/deconstruct tool also show up as "placeholder" ghosts (check-marks).
-   Undoing deletion with combination of approved and unapproved ghosts results in two separate undo steps.
-   Construction bots already en route to approved ghosts will not turn around until they reach the build site. However, no unapproved entities will be built. Compare this to deconstruction of a ghost, when the bots do turn around immediatelly.
-   Approving/unapproving itself cannot be undone. When ghost entities get approved, and personal robots construct them, undoing will _not_ cause those newly built entities to be marked for deconstruction. Approve/unapprove actions themselves are not put into the undo queue. Be careful not to accidentally undo some unrelated part of the base in this manner.
-   Updating blueprints using unapproved ghosts will also include the placeholder ghosts in the blueprint. They can be manually removed from the blueprint without any repercussions.
-   Deconstruction planners from blueprint library have no effect on unapproved ghost entities. This is limtiation on the game's modding API.
-   Underground belt rotation can get messed-up when approving/unapproving ghost entities. Due to how game engine handles underground belt orientation (preventing inconsistencies for belts of the same force), it is not possible to fix this via mod.
-   Underground belt rotation might not always rotate the most obvious underground belt.
-   Belts are not rotated correctly when drag-placing in unapproved-by-default mode.
-   Underground belts are not placed when drag-placing in unapproved-by-default mode.
-   Requester chest option *Request from buffer chests* is not set correctly when unapproved ghosts get revived by mods (such as *Creative Mod*).


Roadmap
-------

### Unscheduled

-   Use of entity filters with the approval tool (similar to deconstruction planner).
-   Approval support for ghost tiles.
-   Upgrade planner support for unapproved ghosts.
-   Improved graphics and icons.
-   In-game tips-and-tricks demonstration and documentation.
-   Show correct selection boxes around unapproved ghosts when using deconstruction tools.
-   Support for force merging (merging unapproved ghosts forces in addition to merging of base forces).
-   Efficient means for force identification (if the regex is too slow).
-   Use on\_entity\_changed_force event handler for approval status badge updates if Wube Software ever implementes it.
-   Undo support for approve/unapprove actions.


How it works
------------

-   Construction bots will only build ghost entities that belong to the same force as a player. Whenever a ghost entity is built or stamped by a player, the mod immediately reassigns the entity to a special "unapproved ghost" force that is "mutual friends" with the player's force. This allows the player to still see and interact with the ghosts, but prevents construction bots from being dispatched to build them.
-   At the same time, an invisible "placeholder" ghost entity is created at the same exact location, with same force as player's.  This is the actual entity that gets selected when an unapproved ghost is blueprinted or deconstructed.
-   When a blueprint is created that includes placeholder entities, the mod edits the blueprint to swap out the placeholder blueprint data with the real ghost entity data. This is done by using a hidden blueprint to capture the same exact area for the unapproved ghost force, and then using the captured blueprint data to overwrite the placeholders in the player's blueprint.
-   Likewise, when a placeholder entity is deconstructed or destroyed, the unapproved ghost is deconstructed or destroyed as well.
-   Undo is implemented by relying on multiple events, and using a deconstruction planner to assign the deconstruction action to the player. This happens in addition to what the player has selected by hand, thus resulting in a separate step in the undo queue.


Credits
-------

This is a continuation/fork of the original [Construction Planner mod](https://mods.factorio.com/mod/ConstructionPlanner) mod. Many thanks to the original author for both implementing the original mod, and for releasing it under a Free (as in Freedom) license, thus making it possible to learn from it and make improvements.


License
-------

All code, documentation, and assets implemented as part of this mod are released under the terms of MIT license (see the accompanying `LICENSE`) file.
