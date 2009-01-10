
FriendsWithBenefits = DongleStub("Dongle-1.0"):New("FriendsWithBenefits")


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


function FriendsWithBenefits:Initialize()
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
end

function FriendsWithBenefits:Enable()
	self:RegisterEvent("CHAT_MSG_SYSTEM")
	self:RegisterEvent("FRIENDLIST_UPDATE", "ProcessNext")
	ShowFriends()
end


local orig1 = AddFriend
AddFriend = function(name, ...)
	Debug("Function AddFriend", name, ...)
	currop, currfriend = "ADD", string.lower(name)
	return orig1(name, ...)
end


local orig2 = RemoveFriend
RemoveFriend = function(i, ...)
	Debug("Function RemoveFriend", i, ...)
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
	if text == ERR_FRIEND_ERROR then return self:Abort("An error has occured.") end

	local _, _, addname = string.find(text, rxadd)
	local remname = not addname and select(3, string.find(text, rxrem))
	if not addname and not remname and (not self.ProcessNext or text ~= ERR_FRIEND_NOT_FOUND and text ~= ERR_FRIEND_WRONG_FACTION) then return end
	if not currfriend then return end
	Debug("Processing chat message", text, addname, remname, currfriend)

	if text == ERR_FRIEND_NOT_FOUND then
		if currop == "REM" then return self:Abort("'Not found' error when removing a friend.") end
		db.removed[currfriend] = true
		db.friends[currfriend] = nil
		if self.ProcessNext then Print(string.format("Cannot find player %q on this realm.", currfriend)) end
	elseif text == ERR_FRIEND_WRONG_FACTION then
		if currop == "REM" then return self:Abort("'Wrong faction' error when removing a friend.") end
		db.removed[currfriend] = true
		db.friends[currfriend] = nil
		if self.ProcessNext then Print(string.format("Player %q is the wrong faction.", currfriend)) end
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
	end

	if self.ProcessNext then self:ProcessNext() end
end


function FriendsWithBenefits:ProcessNext(event)
	if event then self:UnregisterEvent("FRIENDLIST_UPDATE") end

	if initadds then
		for i=1,GetNumFriends() do
			if not GetFriendInfo(i) then Print("Server returned invalid friend data")
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

	if hasannounced then Print("Update completed.") end
	self.ProcessNext = nil
end


function FriendsWithBenefits:Abort(msg)
	self:UnregisterAllEvents()
	Print(msg, "Disabling for the rest of this session.")
end
