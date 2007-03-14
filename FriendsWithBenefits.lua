
FriendsWithBenefits = DongleStub("Dongle-Beta1"):New("FriendsWithBenefits")
local debuggers = {Tekkub = true, Beardyhead = true, Cubbyhole = true, Mishutka = true}
if GetRealmName() == "Area 52" and debuggers[UnitName("player")] then FriendsWithBenefits:EnableDebug(1, ChatFrame5) end

local db, currop, currfriend, hasannounced
local initadds, friendlist = true, {}


function FriendsWithBenefits:Initialize()
	local factionrealm = string.format("%s - %s", UnitFactionGroup("player"), GetRealmName())
	db = self:InitializeDB("FriendsWithBenefitsDB", {profile = {friends = {}, removed = {}}}, factionrealm)
	db.profile.friends[string.lower(UnitName("player"))] = true
	db.profile.removed[string.lower(UnitName("player"))] = nil
end

-- FriendsWithBenefitsDB.profiles["Alliance - Area 52"].friends.adbvairhf = true
function FriendsWithBenefits:Enable()
	self:RegisterEvent("CHAT_MSG_SYSTEM")
	self:RegisterEvent("FRIENDLIST_UPDATE", "ProcessNext")
	ShowFriends()
end


local orig1 = AddFriend
AddFriend = function(name, ...)
	FriendsWithBenefits:Debug(1, "Function AddFriend", name, ...)
	currop, currfriend = "ADD", string.lower(name)
	return orig1(name, ...)
end

local orig2 = RemoveFriend
RemoveFriend = function(i, ...)
	FriendsWithBenefits:Debug(1, "Function RemoveFriend", i, ...)
	local name = type(i) == "number" and GetFriendInfo(i) or i
	currop, currfriend = "REM", string.lower(name)
	return orig2(i, ...)
end


-- ERR_FRIEND_ERROR = "Unknown friend response from server."
-- ERR_FRIEND_NOT_FOUND = "Player not found."
-- ERR_FRIEND_WRONG_FACTION = "Friends must be part of your alliance."
local rxadd = string.gsub(ERR_FRIEND_ADDED_S, "%%s", "(.+)")   -- ERR_FRIEND_ADDED_S = "%s added to friends."
local rxrem = string.gsub(ERR_FRIEND_REMOVED_S, "%%s", "(.+)") -- ERR_FRIEND_REMOVED_S = "%s removed from friends list."
function FriendsWithBenefits:CHAT_MSG_SYSTEM(event, text)
	if text == ERR_FRIEND_ERROR then return self:Abort("An error has occured") end

	local _, _, addname = string.find(text, rxadd)
	local remname = not addname and select(3, string.find(text, rxrem))
	if not addname and not remname and (not self.ProcessNext or text ~= ERR_FRIEND_NOT_FOUND and text ~= ERR_FRIEND_WRONG_FACTION) then return end

	if text == ERR_FRIEND_NOT_FOUND then
		if currop == "REM" then return self:Abort("'Not found' error when removing a friend") end
		db.profile.removed[currfriend] = true
		db.profile.friends[currfriend] = nil
		if self.ProcessNext then self:PrintF("Cannot find player '%s' on this realm.", currfriend) end
	elseif text == ERR_FRIEND_WRONG_FACTION then
		if currop == "REM" then return self:Abort("'Wrong faction' error when removing a friend") end
		db.profile.removed[currfriend] = true
		db.profile.friends[currfriend] = nil
		if self.ProcessNext then self:PrintF("Player '%s' is the wrong faction.", currfriend) end
	elseif addname then
		if currop == "REM" then return self:Abort("'Friend added' message when removing a friend") end
		if string.lower(addname) ~= currfriend then return self:Abort("Name mismatch while adding a friend") end
		db.profile.friends[currfriend] = true
		db.profile.removed[currfriend] = nil
		friendlist[currfriend] = true
	elseif remname then
		if currop == "ADD" then return self:Abort("'Friend removed' message when adding a friend") end
		if string.lower(remname) ~= currfriend then return self:Abort("Name mismatch while removing a friend") end
		db.profile.removed[currfriend] = true
		db.profile.friends[currfriend] = nil
		friendlist[currfriend] = nil
	end

	if self.ProcessNext then self:ProcessNext() end
end


function FriendsWithBenefits:ProcessNext(event)
	if event then self:UnregisterEvent("FRIENDLIST_UPDATE") end

	if initadds then
		for i=1,GetNumFriends() do
			local name = string.lower(GetFriendInfo(i))
			friendlist[name] = true
			if db.profile.removed[name] then
				if not hasannounced then
					self:Print("Updating friend list.  Please do not add or remove friends until complete.")
					hasannounced = true
				end
				self:Debug(1, "RemoveFriend", name)
				return RemoveFriend(name)
			else db.profile.friends[name] = true end
		end
		initadds = nil
	end

	for name in pairs(db.profile.friends) do
		if not friendlist[name] and string.lower(UnitName("player")) ~= name then
			if not hasannounced then
				self:Print("Updating friend list.  Please do not add or remove friends until complete.")
				hasannounced = true
			end
			if name ~= string.lower(UnitName("player")) then
				self:Debug(1, "AddFriend", name)
				return AddFriend(name)
			end
		end
	end

	if hasannounced then self:Print("Update completed.") end
	self.ProcessNext = nil
end


function FriendsWithBenefits:Abort(msg)
	self:UnregisterAllEvents()
	self:Print(msg..".  Disabling for the rest of this session.")
end
