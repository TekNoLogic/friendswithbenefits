
local myname, ns = ...


local db, currop, currfriend, hasannounced
local friendlist = {}


function ns.OnLoad()
	ns.Debug("Loading DB")
	local factionrealm = UnitFactionGroup("player").. " - "..GetRealmName()

	FriendsWithBenefitsDB = FriendsWithBenefitsDB or {}
	if FriendsWithBenefitsDB.factionrealm then -- Migrate data from dongle-style DB
		for i,v in pairs(FriendsWithBenefitsDB.factionrealm) do FriendsWithBenefitsDB[i] = v end
		FriendsWithBenefitsDB.profileKeys, FriendsWithBenefitsDB.factionrealm = nil
	end
	FriendsWithBenefitsDB[factionrealm] = FriendsWithBenefitsDB[factionrealm] or {}
	db = FriendsWithBenefitsDB[factionrealm]
	db.friends, db.removed, db.notes = db.friends or {}, db.removed or {}, db.notes or {}

	if not db.removed[string.lower(UnitName("player"))] then db.friends[string.lower(UnitName("player"))] = true end
end


function ns.OnLogin()
	ns.RegisterEvent("CHAT_MSG_SYSTEM")
	ns.RegisterEvent("FRIENDLIST_UPDATE")
	ShowFriends()
end


local origAddFriend = AddFriend
AddFriend = function(name, ignore, ...)
	ns.Debug("Function AddFriend", name, ignore, ...)
	if not ignore then currop, currfriend = "ADD", string.lower(name) end
	return origAddFriend(name, ignore, ...)
end


local origRemoveFriend = RemoveFriend
RemoveFriend = function(i, ignore, ...)
	local name = type(i) == "number" and GetFriendInfo(i) or i
	ns.Debug("Function RemoveFriend", name, i, ignore, ...)
	if not ignore then currop, currfriend = "REM", string.lower(name) end
	return origRemoveFriend(i, ignore, ...)
end


local origSetFriendNotes = SetFriendNotes
SetFriendNotes = function(i, note, ...)
	ns.Debug("Function SetFriendNotes", i, note, ...)
	local name = type(i) == "number" and GetFriendInfo(i) or i
	db.notes[string.lower(name)] = note
	return origSetFriendNotes(i, note, ...)
end


-- ERR_FRIEND_ERROR = "Unknown friend response from server."
-- ERR_FRIEND_NOT_FOUND = "Player not found."
-- ERR_FRIEND_WRONG_FACTION = "Friends must be part of your alliance."
local rxadd = string.gsub(ERR_FRIEND_ADDED_S, "%%s", "(.+)")   -- ERR_FRIEND_ADDED_S = "%s added to friends."
local rxrem = string.gsub(ERR_FRIEND_REMOVED_S, "%%s", "(.+)") -- ERR_FRIEND_REMOVED_S = "%s removed from friends list."
function ns.CHAT_MSG_SYSTEM(event, text)
	if text == ERR_FRIEND_ERROR then return ns.Abort("An error has occured.") end

	local _, _, addname = string.find(text, rxadd)
	local remname = not addname and select(3, string.find(text, rxrem))
	if not addname and not remname and (not ns.FRIENDLIST_UPDATE or text ~= ERR_FRIEND_NOT_FOUND and text ~= ERR_FRIEND_WRONG_FACTION) then return end
	if not currfriend then return end
	ns.Debug("Processing chat message", text, addname, remname, currfriend)

	if text == ERR_FRIEND_NOT_FOUND then
		if currop == "REM" then return ns.Abort("'Not found' error when removing a friend.") end
		db.removed[currfriend] = true
		db.friends[currfriend] = nil
		if ns.FRIENDLIST_UPDATE then ns.Printf("Cannot find player %q on this realm.", currfriend) end
	elseif text == ERR_FRIEND_WRONG_FACTION then
		if currop == "REM" then return ns.Abort("'Wrong faction' error when removing a friend.") end
		db.removed[currfriend] = true
		db.friends[currfriend] = nil
		if ns.FRIENDLIST_UPDATE then ns.Printf("Player %q is the wrong faction.", currfriend) end
	elseif addname then
		if currop == "REM" then return ns.Abort("'Friend added' message when removing a friend.") end
		if string.lower(addname) ~= currfriend then return ns.Abort("Name mismatch while adding a friend.") end
		ns.Debug("Friend added", currfriend)
		db.friends[currfriend] = true
		db.removed[currfriend] = nil
		friendlist[currfriend] = true
	elseif remname then
		if currop == "ADD" then return ns.Abort("'Friend removed' message when adding a friend.") end
		if string.lower(remname) ~= currfriend then return ns.Abort("Name mismatch while removing a friend.") end
		ns.Debug("Friend removed", currfriend)
		db.removed[currfriend] = true
		db.friends[currfriend] = nil
		friendlist[currfriend] = nil
		db.notes[currfriend] = nil
	end

	if ns.FRIENDLIST_UPDATE then ns.FRIENDLIST_UPDATE() end
end


function ns.FRIENDLIST_UPDATE(event)
	if event then ns.UnregisterEvent("FRIENDLIST_UPDATE") end

  if ns.LoginSyncRemote then ns.LoginSyncRemote() end
  if ns.LoginSyncLocal then ns.LoginSyncLocal() end

	if hasannounced then ns.Print("Update completed.") end
	ns.Debug("Cleaning up")
	ns.UnregisterEvent("FRIENDLIST_UPDATE")
	ns.FRIENDLIST_UPDATE = nil
end


function ns.LoginSyncRemote()
  for i=1,GetNumFriends() do
    if not GetFriendInfo(i) then
      ns.Print("Server returned invalid friend data")
      return
    else
      local name, _, _, _, _, _, note = GetFriendInfo(i)
      name = string.lower(name)
      friendlist[name] = note or ""
      if db.removed[name] then
        if not hasannounced then
          ns.Print("Updating friend list.  Please do not add or remove friends until complete.")
          hasannounced = true
        end
        ns.Debug("RemoveFriend", name)
        return RemoveFriend(name)
      else db.friends[name] = true end
    end
  end
  ns.LoginSyncRemote = nil
end


function ns.LoginSyncLocal()
  for name in pairs(db.friends) do
    if not friendlist[name] and string.lower(UnitName("player")) ~= name then
      if not hasannounced then
        ns.Print("Updating friend list.  Please do not add or remove friends until complete.")
        hasannounced = true
      end
      if name ~= string.lower(UnitName("player")) then
        ns.Debug("AddFriend", name)
        return AddFriend(name)
      end
    end
  end

  for i=1,GetNumFriends() do
    local name, _, _, _, _, _, note = GetFriendInfo(i)
    if not name then
      ns.Print("Server returned invalid friend data")
      return
    else
      name = string.lower(name)
      if db.notes[name] and db.notes[name] ~= note then SetFriendNotes(name, db.notes[name])
      elseif note ~= "" then db.notes[name] = note end
    end
  end

  ns.LoginSyncLocal = nil
end


function ns.Abort(msg)
	ns.UnregisterAllEvents()
	ns.FRIENDLIST_UPDATE, ns.CHAT_MSG_SYSTEM, ns.Abort = nil
	ns.Print(msg, "Disabling for the rest of this session.")
end
