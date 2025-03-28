Construction Approvals
======================


About
-----

*Construction Approvals* changes the behavior of how ghosts are built to give the player more control over factory planning and building. With the mod enabled, construction bots are no longer automatically dispatched to build the ghosts. Instead, the player uses *Construction Planner* tool to explicitly approve construction of selected ghosts, at which point the bots are dispatched to complete the task.

Why use *Construction Approvals*?

-   Create plans using ghosts without having to find isolated spot not covered by the roboport network.
-   Plan ahead and stamp out the entire factory using blueprints and ghosts; approve construction in sections as needed; control which sections get built first.
-   Hand slipped while stamping a bluperint? Used a wrong blueprint? No need for rush - the bots have not been dispatched yet, and there is plenty of time to undo or fix the mistake.
-   Tweak blueprint inputs and outputs without worrying that bots will unleash a flood of resources into the unfinished factory.
-   Plan-out an entire defensive perimeter, without worrying about bots getting ahead and building partial, non-functional defensive segments. Strategically prioritize construction of key defensive locations.
-   Stamp out a huge solar field and approve it in chunks, thus avoiding bots building solar panels and accumulators disconnected from the main grid.


Features
--------

-   Ghost entities are no longer automatically built by construction bots, and require a manual approval first. **NOTE:** Ghosts created in place of destroyed entities do not require approval, and are rebuilt as usual.
-   Ghost construction is approved (by click-dragging) or unapproved (by shift-click-dragging) using the *Construction Planner*_tool.
-   Automatic approval toggle can be used to change behaviour for newly placed ghosts for faster building when necessary.
-   Blueprints can be created and updated using any combination of unapproved and approved ghosts.
-   Approval status is indicated via check mark shown on top of the ghost entity. Green check mark indicates that ghost entity has been approved for construction. Grey check mark indicates that ghost entity has not been approved for construction. Check mark size is configurable via map settings.


Contributions
-------------

Bugs and feature requests can be reported through discussion threads or through project's issue tracker. For general questions, please use discussion threads.

Pull requests for implementing new features and fixing encountered issues are always welcome.


Known issues
------------

-   Upgrade planner has no effect on unapproved ghosts.
-   Unapproved ghosts selected with cut/copy/blueprint/deconstruct tools also show up as "placeholder" ghosts (check-marks) while dragging . However, no placeholders are included in the resulting blueprint.
-   Undoing deletion with combination of approved and unapproved ghosts results in two separate undo steps.
-   Construction bots already en route to approved ghost that has been unapproved in the memantime will not turn around until they reach the build site. However, no unapproved ghosts will be built. Compare this to deconstruction of a ghost, when the bots do turn around immediatelly.
-   Approval and unapproval actions cannot be undone. Approved ghosts built by personal robots cannot be undone. Invoking undo will not mark those newly built entities for deconstruction. Be careful not to accidentally undo some unrelated part of the base in this manner.
-   *Library* blueprints updated using unapproved ghosts will include the placeholder ghosts. Placeholder ghosts can be manually removed from such blueprint without any repercussions.
-   Underground belt rotation can get messed-up when approving/unapproving ghost entities. Due to how game engine handles underground belt orientation (preventing inconsistencies for belts of the same force), it is not possible to fix this via mod.
-   Underground belt rotation might not always rotate the most obvious underground belt.
-   Belts are not rotated correctly during direction change/rotation when drag-placing in unapproved-by-default mode.
-   Underground belts entries are not placed when drag-placing over other entities in unapproved-by-default mode.
-   Approval badges and unapproved ghost placeholders for elevated rails are not correctly placed/shown on top of the rails.
-   Recipes which are manually unlocked by mods (without using technology research) may not be selectable in machine configuration for unapproved ghosts. This is a limiation of the current modding API (lack of events triggered when recipe is enabled/disabled).
-   Reversing ghost belts via super-forced pasting is not undoable. The undo action will trigger, but will not put the belts back into the original orientation. This is both a limitation of the mod itself, and the way the game handles the undo queue.
-   When underground belts get placed while dragging belt in super-forced build mode across unapproved ghost belts, the newly-placed underground belts get approved automatically, and do not have an approval indicator. This is a limitation of the current modding API. Required/expected event is not triggered, so the mod cannot apply the necessary corrections/additions.
-   Building huge (larger than 1000 by 1000 tiles) blueprints using blueprint books from inventory (not library) will probably crash the game. This is current mod limitation/bug that will be fixed in the future.
-   Building using blueprint books may incur additional performance issues due to currently implemented workarounds. This is current mod limitation that will be fixed in the future.


Roadmap
-------

### Unscheduled

-   Entity filters for the "Construction Planner" tool.
-   Approval support for ghost tiles.
-   Upgrade planner support for unapproved ghosts.
-   Improved graphics and icons.
-   In-game tips-and-tricks demonstration and documentation.
-   Show correct selection boxes around unapproved ghosts when using deconstruction tool.
-   Support for force merging (merging unapproved ghosts forces in addition to merging of base forces).
-   Efficient means for force identification (if the regex is too slow).
-   Use on\_entity\_changed_force event handler for approval status badge updates if Wube Software ever implementes it.
-   Undo support for approve/unapprove actions.
-   Preserve approval state when invoking undo.
-   Merge approved and unapproved undo action into one when using deconstruction planner or cut-and-paste tool.
-   Make checkmarks less obnoxious.


How it works
------------

-   Construction bots will only build ghost entities that belong to the same force as a player. Whenever a ghost entity is built or stamped by a player, the mod immediately reassigns the entity to a special "unapproved ghost" force that is "mutual friends" with the player's force. This allows the player to still see and interact with the ghosts, but prevents construction bots from being dispatched to build them.
-   At the same time, an invisible "placeholder" ghost entity is created at the same exact location, with same force as player's. This is the actual entity that gets selected when an unapproved ghost is blueprinted or deconstructed.
-   When a blueprint is created that includes placeholder entities, the mod edits the blueprint to swap out the placeholder blueprint data with the real ghost entity data. This is done by using a hidden blueprint to capture the same exact area for the unapproved ghost force, and then using the captured blueprint data to overwrite the placeholders in the player's blueprint.
-   Likewise, when a placeholder entity is deconstructed or destroyed, the unapproved ghost is deconstructed or destroyed as well.
-   Undo is implemented by relying on multiple events, and using a deconstruction planner to assign the deconstruction action to the player. This happens in addition to what the player has selected by hand, thus resulting in a separate step in the undo queue.


Credits
-------

This is a fork of the original [Construction Planner](https://mods.factorio.com/mod/ConstructionPlanner) mod. Many thanks to the original author for both implementing the original mod, and for releasing it under a Free (as in Freedom) license, thus making it possible to learn from it and make improvements.


License
-------

All code, documentation, and assets implemented as part of this mod are released under the terms of MIT license (see the accompanying `LICENSE`) file, with the following exceptions:

-   [assets/crane.svg](https://game-icons.net/1x1/delapouite/crane.html), by Delapouite, under [CC BY 3.0](http://creativecommons.org/licenses/by/3.0/), used in creation of modpack thumbnail.
-   [build.sh (factorio_development.sh)](https://code.majic.rs/majic-scripts/), by Branko Majic, under [GPLv3](https://www.gnu.org/licenses/gpl-3.0.html).
