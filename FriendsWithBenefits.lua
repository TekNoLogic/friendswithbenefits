
----------------------
--      Locals      --
----------------------

local db, currop, currfriend, hasannounced
local initadds, friendlist = true, {}


------------------------------
--      Util Functions      --
------------------------------

local function Print(...) print("|cFF33FF99Friends With Benefits|r:", ...) end

local debugf = tekDebug and tekDebug:GetFrame("FriendsWithBenefits")
local function Debug(...) if debugf then debugf:AddMessage(string.join(", ", tostringall(...))) end end


-----------------------------
--      Event Handler      --
-----------------------------

local f = CreateFrame("frame")
f:SetScript("OnEvent", function(self, event, ...) if self[event] then return self[event](self, event, ...) end end)
f:RegisterEvent("ADDON_LOADED")


function f:ADDON_LOADED(event, addon)
	if addon:lower() ~= "friendswithbenefits" then return end

 	LibStub("tekKonfig-AboutPanel").new(nil, "FriendsWithBenefits")

	Debug("Loading DB")
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

	self:UnregisterEvent("ADDON_LOADED")
	self.ADDON_LOADED = nil

	if IsLoggedIn() then self:PLAYER_LOGIN() else self:RegisterEvent("PLAYER_LOGIN") end
end


function f:PLAYER_LOGIN()
	self:RegisterEvent("CHAT_MSG_SYSTEM")
	self:RegisterEvent("FRIENDLIST_UPDATE")
	ShowFriends()

	self:UnregisterEvent("PLAYER_LOGIN")
	self.PLAYER_LOGIN = nil
end


local orig1 = AddFriend
AddFriend = function(name, ignore, ...)
	Debug("Function AddFriend", name, ignore, ...)
	if not ignore then currop, currfriend = "ADD", string.lower(name) end
	return orig1(name, ignore, ...)
end


local orig2 = RemoveFriend
RemoveFriend = function(i, ignore, ...)
	local name = type(i) == "number" and GetFriendInfo(i) or i
	Debug("Function RemoveFriend", name, i, ignore, ...)
	if not ignore then currop, currfriend = "REM", string.lower(name) end
	return orig2(i, ignore, ...)
end


local orig3 = SetFriendNotes
SetFriendNotes = function(i, note, ...)
	Debug("Function SetFriendNotes", i, note, ...)
	local name = type(i) == "number" and GetFriendInfo(i) or i
	db.notes[string.lower(name)] = note
	return orig3(i, note, ...)
end


-- ERR_FRIEND_ERROR = "Unknown friend response from server."
-- ERR_FRIEND_NOT_FOUND = "Player not found."
-- ERR_FRIEND_WRONG_FACTION = "Friends must be part of your alliance."
local rxadd = string.gsub(ERR_FRIEND_ADDED_S, "%%s", "(.+)")   -- ERR_FRIEND_ADDED_S = "%s added to friends."
local rxrem = string.gsub(ERR_FRIEND_REMOVED_S, "%%s", "(.+)") -- ERR_FRIEND_REMOVED_S = "%s removed from friends list."
function f:CHAT_MSG_SYSTEM(event, text)
	if text == ERR_FRIEND_ERROR then return self:Abort("An error has occured.") end

	local _, _, addname = string.find(text, rxadd)
	local remname = not addname and select(3, string.find(text, rxrem))
	if not addname and not remname and (not self.FRIENDLIST_UPDATE or text ~= ERR_FRIEND_NOT_FOUND and text ~= ERR_FRIEND_WRONG_FACTION) then return end
	if not currfriend then return end
	Debug("Processing chat message", text, addname, remname, currfriend)

	if text == ERR_FRIEND_NOT_FOUND then
		if currop == "REM" then return self:Abort("'Not found' error when removing a friend.") end
		db.removed[currfriend] = true
		db.friends[currfriend] = nil
		if self.FRIENDLIST_UPDATE then Print(string.format("Cannot find player %q on this realm.", currfriend)) end
	elseif text == ERR_FRIEND_WRONG_FACTION then
		if currop == "REM" then return self:Abort("'Wrong faction' error when removing a friend.") end
		db.removed[currfriend] = true
		db.friends[currfriend] = nil
		if self.FRIENDLIST_UPDATE then Print(string.format("Player %q is the wrong faction.", currfriend)) end
	elseif addname then
		if currop == "REM" then return self:Abort("'Friend added' message when removing a friend.") end
		if string.lower(addname) ~= currfriend then return self:Abort("Name mismatch while adding a friend.") end
		Debug("Friend added", currfriend)
		db.friends[currfriend] = true
		db.removed[currfriend] = nil
		friendlist[currfriend] = true
	elseif remname then
		if currop == "ADD" then return self:Abort("'Friend removed' message when adding a friend.") end
		if string.lower(remname) ~= currfriend then return self:Abort("Name mismatch while removing a friend.") end
		Debug("Friend removed", currfriend)
		db.removed[currfriend] = true
		db.friends[currfriend] = nil
		friendlist[currfriend] = nil
		db.notes[currfriend] = nil
	end

	if self.FRIENDLIST_UPDATE then self:FRIENDLIST_UPDATE() end
end


function f:FRIENDLIST_UPDATE(event)
	if event then self:UnregisterEvent("FRIENDLIST_UPDATE") end

	if initadds then
		for i=1,GetNumFriends() do
			if not GetFriendInfo(i) then
				Print("Server returned invalid friend data")
				return
			else
				local name, _, _, _, _, _, note = GetFriendInfo(i)
				name = string.lower(name)
				friendlist[name] = note or ""
				if db.removed[name] then
					if not hasannounced then
						Print("Updating friend list.  Please do not add or remove friends until complete.")
						hasannounced = true
					end
					Debug("RemoveFriend", name)
					return RemoveFriend(name)
				else db.friends[name] = true end
			end
		end
		initadds = nil
	end

	for name in pairs(db.friends) do
		if not friendlist[name] and string.lower(UnitName("player")) ~= name then
			if not hasannounced then
				Print("Updating friend list.  Please do not add or remove friends until complete.")
				hasannounced = true
			end
			if name ~= string.lower(UnitName("player")) then
				Debug("AddFriend", name)
				return AddFriend(name)
			end
		end
	end

	for i=1,GetNumFriends() do
		local name, _, _, _, _, _, note = GetFriendInfo(i)
		if not name then
			Print("Server returned invalid friend data")
			return
		else
			name = string.lower(name)
			if db.notes[name] and db.notes[name] ~= note then SetFriendNotes(name, db.notes[name])
			elseif note ~= "" then db.notes[name] = note end
		end
	end

	if hasannounced then Print("Update completed.") end
	Debug("Cleaning up")
	self:UnregisterEvent("FRIENDLIST_UPDATE")
	self.FRIENDLIST_UPDATE, self.Cleanup = nil
end


function f:Abort(msg)
	self:UnregisterAllEvents()
	self.FRIENDLIST_UPDATE, self.Cleanup, self.CHAT_MSG_SYSTEM, self.Abort = nil
	self:SetScript("OnEvent", nil)
	Print(msg, "Disabling for the rest of this session.")
end
