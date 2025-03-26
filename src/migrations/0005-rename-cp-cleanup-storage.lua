--- "Renames" the key used for storing the cleanup command data.
--
local function rename_cp_cleanup_storage()
  if storage.commands and storage.commands.cp_cleanup then
    storage.commands.ca_cleanup = storage.commands.cp_cleanup
    storage.commands.cp_cleanup = nil
  end
end

rename_cp_cleanup_storage()
