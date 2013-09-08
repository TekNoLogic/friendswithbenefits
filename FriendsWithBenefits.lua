
local myname, ns = ...


local db, currop, currfriend
local friendlist = {}


function ns.OnLoad()
	ns.Debug("Loading DB")
	local factionrealm = UnitFactionGroup("player").. " - "..GetRealmName()

	FriendsWithBenefitsDB = FriendsWithBenefitsDB or {}
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
AddFriend = function(name, ...)
	ns.Debug("Function AddFriend", name, ...)
	currop, currfriend = "ADD", string.lower(name)
	return origAddFriend(name, ...)
end


local origRemoveFriend = RemoveFriend
RemoveFriend = function(i, ...)
	local name = type(i) == "number" and GetFriendInfo(i) or i
	ns.Debug("Function RemoveFriend", name, i, ...)
	currop, currfriend = "REM", string.lower(name)
	return origRemoveFriend(i, ...)
end


local origSetFriendNotes = SetFriendNotes
SetFriendNotes = function(i, note, ...)
	ns.Debug("Function SetFriendNotes", i, note, ...)
	local name = type(i) == "number" and GetFriendInfo(i) or i
	db.notes[string.lower(name)] = note
	return origSetFriendNotes(i, note, ...)
end


local function FinalizeAdd()
	if not GetFriendInfo(currfriend) then return end

	ns.Debug("Friend added", currfriend)
	db.friends[currfriend] = true
	db.removed[currfriend] = nil
	friendlist[currfriend] = true
	currop, currfriend = nil

	if ns.LoginSync then ns.LoginSync() end
end


local function FinalizeRemove()
	if GetFriendInfo(currfriend) then return end

	ns.Debug("Friend removed", currfriend)
	db.removed[currfriend] = true
	db.friends[currfriend] = nil
	friendlist[currfriend] = nil
	db.notes[currfriend] = nil
	currop, currfriend = nil

	if ns.LoginSync then ns.LoginSync() end
end


local chat_errors = {
	[ERR_FRIEND_NOT_FOUND] = true, -- "Player not found."
	[ERR_FRIEND_WRONG_FACTION] = true, -- "Friends must be part of your alliance."
}
function ns.CHAT_MSG_SYSTEM(event, text)
	if not chat_errors[text] then return end

	ns.Debug("Processing chat error", text, currop, currfriend)

	if text == ERR_FRIEND_ERROR then return ns.Abort("An error has occured.") end
	if currop == 'REM' then return ns.Abort("Unexpected server response.") end

	if text == ERR_FRIEND_NOT_FOUND then
		db.removed[currfriend] = true
		db.friends[currfriend] = nil
		ns.Printf("Cannot find player %q on this realm.", currfriend)
		currfriend, currop = nil

	elseif text == ERR_FRIEND_WRONG_FACTION then
		db.removed[currfriend] = true
		db.friends[currfriend] = nil
		ns.Printf("Player %q is the wrong faction.", currfriend)
		currfriend, currop = nil
	end
end


function ns.FRIENDLIST_UPDATE(event)
	if currop == "ADD" then return FinalizeAdd()
	elseif currop == "REM" then return FinalizeRemove() end

	if ns.LoginSync then ns.LoginSync() end
end


local hasannounced
local function AnnounceOnce()
	ns.Print("Updating friend list.  Please do not add or remove friends until complete.")
	hasannounced = true
	AnnounceOnce = function() end
end


function ns.LoginSync()
	if not hasannounced then ns.Debug("First sync FRIENDLIST_UPDATE") end

	if ns.LoginSyncRemote then
		local name = ns.LoginSyncRemote()
		if name then
			AnnounceOnce()
			ns.Debug("Removing friend due to sync", name)
			return RemoveFriend(name)
		end
	end

	if ns.LoginSyncLocal then
		local name = ns.LoginSyncLocal()
		if name then
			AnnounceOnce()
			ns.Debug("Adding friend due to sync", name)
			return AddFriend(name)
		end
	end

	if hasannounced then ns.Print("Update completed.") end
	ns.Debug("Login sync complete")

	ns.LoginSync = nil
end


function ns.LoginSyncRemote()
	for i=1,GetNumFriends() do
		local name, _, _, _, _, _, note = GetFriendInfo(i)
		if not name then
			return ns.Abort("Server returned invalid friend data")
		else
			name = string.lower(name)
			friendlist[name] = note or ""
			if db.removed[name] then
				return name
			else db.friends[name] = true end
		end
	end
	ns.LoginSyncRemote = nil
end


function ns.LoginSyncLocal()
	for name in pairs(db.friends) do
		if not friendlist[name] and string.lower(UnitName("player")) ~= name then
			return name
		end
	end

	for i=1,GetNumFriends() do
		local name, _, _, _, _, _, note = GetFriendInfo(i)
		if not name then
			return ns.Abort("Server returned invalid friend data")
		else
			name = string.lower(name)
			if db.notes[name] and db.notes[name] ~= note then
				SetFriendNotes(name, db.notes[name])
			elseif note ~= "" then
				db.notes[name] = note
			end
		end
	end

	ns.LoginSyncLocal = nil
end


function ns.Abort(msg)
	ns.UnregisterAllEvents()
	ns.LoginSync, ns.LoginSyncRemote, ns.LoginSyncLocal = nil
	ns.FRIENDLIST_UPDATE, ns.CHAT_MSG_SYSTEM, ns.Abort = nil
	ns.Print(msg, "Disabling for the rest of this session.")
end
