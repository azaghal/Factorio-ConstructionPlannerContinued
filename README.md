Construction Planner Continued
==============================


About
-----

Construction Planner changes the behavior of how ghost entities are built to give the player more control over planning and building their factory.  With the mod, construction bots will no longer be automatically dispatched to build ghosts; instead, the player must use the new Construction Planner selection tool to approve construction of the ghosts; only then will bots be dispatched.

Why use Construction Planner?

- Plan ahead and stamp out your entire factory ahead of time as ghosts, and approve sections only as needed, so your construction bots won't prematurely build power lines, belts, etc.
- Mouse slipped and that blueprint stamp is off by a tile?  No need to rush - the bots haven't been dispatched yet; there's plenty of time to fix it
- Plenty of time to make those blueprint tweaks for the inputs and outputs, too; the bots will wait until you give it the thumbs-up
- Plan out an entire perimeter defense, without worrying about the bots getting ahead of you.  Then, strategically prioritize construction of the defenses in key locations first.
- Stamp out a huge solar field and approve it in chunks, so the bots won't accidentally build solar panels and accumulators where there's no power yet

You can also see the mod in action by checking out Xterminator's excellent [mod spotlight video](https://www.youtube.com/watch?v=UNAXhiTBu9M) on Youtube.


Features
--------

- Ghost entities are no longer built automatically by construction bots; instead, they must first be approved by the player
    - Exception: ghosts created when an entity is destroyed don't require approval and will be rebuilt as usual
- Use the Construction Planner tool (in the shortcut bar) to approve and unapprove ghosts for construction
- Use the auto-approve mod setting to save time when you just want everything to be approved as soon as you stamp it


Contributions
-------------

Should you come upon bugs, or have features and ideas on how to make the mod better, please do not hesitate to voice your feedback either through mod portal discussion page, or through project's issue tracker. Pull requests for implementing new features and fixing encountered issues are always welcome.


Known issues
------------

- The upgrade planner doesn't yet work on unapproved ghosts
- Blueprinting and deconstruction of unapproved ghosts works, but the selection border will look a little strange
- If an approved ghost becomes unapproved, any construction bots already en route won't turn around until they reach the build site (compare this to when a ghost is deconstructed, in which case the bots turn around immediately)


Roadmap
-------

### Unscheduled

- [ ] Support for entity filters when using the approval tool (similar to the deconstruction planner)
- [ ] Toggle switch to allow/disallow building of unapproved ghosts if there are no approved ghosts left to build
- [ ] Option to require approval for tile ghosts as well
- [ ] Support use of the upgrade planner on unapproved ghosts
- [ ] Improved graphics and icons
- [ ] Improve visual appearance when selecting unapproved ghosts using the blueprint and deconstruction tools (if the mod API allows for it)


How it works
------------

- Whenever a ghost entity is built or stamped by a player, the mod immediately reassigns the entity to a special 'unapproved ghost' force that is 'mutual friends' with the player's force.  This allows the player to still see and interact with the ghosts, but prevents construction bots from being dispatched to build the ghost.
- At the same time, an invisible 'placeholder' ghost entity is created in the same exact location on the player force.  This entity is what actually gets selected when an unapproved ghost is blueprinted or deconstructed.
- When a blueprint is created that includes placeholder entities, the mod will edit the blueprint to swap out the placeholder blueprint data with the real ghost entity data.  This is done by using a hidden blueprint to capture the same exact area for the unapproved ghost force, and then using the captured blueprint data to overwrite the placeholders in the player's blueprint
- Likewise, when a placeholder entity is deconstructed or destroyed, the unapproved ghost is deconstructed or destroyed as well


Credits
-------

This is a continuation/fork of the original [Construction Planner mod](https://mods.factorio.com/mod/ConstructionPlanner) mod. Many thanks to the original author for both implementing the original mod, and making it availabe under a Free (as in Freedom) license.


License
-------

All code, documentation, and assets implemented as part of this mod are released under the terms of MIT license (see the accompanying `LICENSE`) file.
