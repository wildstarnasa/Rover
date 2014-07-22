-----------------------------------------------------------------------------------------------
-- Client Lua Script for Rover
-----------------------------------------------------------------------------------------------

require "Window"

-----------------------------------------------------------------------------------------------
-- Upvalues
-----------------------------------------------------------------------------------------------
local ipairs, pairs, next, tonumber, tostring, type = ipairs, pairs, next, tonumber, tostring, type
local tsort, tinsert, unpack = table.sort, table.insert, unpack
local strformat = string.format
local pcall, loadstring, getmetatable, setmetatable = pcall, loadstring, getmetatable, setmetatable
local _G = _G

-- Wildstar APIs
local Apollo, ApolloTimer, GameLib, XmlDoc = Apollo, ApolloTimer, GameLib, XmlDoc
local ICCommLib = ICCommLib
local Event_FireGenericEvent = Event_FireGenericEvent

--GLOBALS: SendVarToRover, RemoveVarFromRover

-----------------------------------------------------------------------------------------------
-- Rover Module Definitions
-----------------------------------------------------------------------------------------------
local Rover = {}

Rover.ADD_ALL = 0
Rover.ADD_ONCE = 1
Rover.ADD_DEFAULT = 2

local tModifierTimer
local tBottomTimer
local tXMLRefs = {}
local tEvents = {}
local tBlacklistedEvents = {
	["NextFrame"] = true,
	["VarChange_FrameCount"] = true,
	["ActionBarDescriptionSpell"] = true,
}

-----------------------------------------------------------------------------------------------
-- Constants
-----------------------------------------------------------------------------------------------
-- e.g. local kiExampleVariableMax = 999
local eRoverColumns = {
	VarName = 1,
	Type = 2,
	Value = 3,
	LastUpdate = 4,
}
-- Prefix for all handler functions, change to something more unique if needed.
local handlerPrefix = "evtMon_"
local channelPrefix = "chnMon_"
local kStrOriginalIndex = "original__index"
local kStrNodeIndex = "tree__node"
local kStrDetailed = "detailed__data"

-----------------------------------------------------------------------------------------------
-- Custom Userdata Displays - SinusPi's Idea
-----------------------------------------------------------------------------------------------

Rover.userdataDisplay = {
	[ApolloColor] = function(u) return ("<APOLLOCOLOR %s>"):format(tostring(u)) end,
	[ApolloTimer] = function(u) return ("<APOLLOTIMER %s>"):format(tostring(u)) end,
	[CColor] = function(u) return ("<CCOLOR %s>"):format(tostring(u)) end,
	[Episode] = function(u) return ("<EPISODE #%d \"%s\">"):format(u:GetId(),u:GetTitle()) end,
	[Item] = function(u) return ("<ITEM #%d \"%s\">"):format(u:GetItemId(), u:GetName()) end,
	[PathEpisode] = function(u) return ("<PATHEPISODE \"%s\" (%s)>"):format(u:GetName(),u:GetWorldZone()) end,
	[PathMission] = function(u) return ("<PATHMISSION #%d \"%s\" (%d/%d)>"):format(u:GetId(),u:GetName(),u:GetNumCompleted(),u:GetNumNeeded()) end,
	[Quest] = function(u) return ("<QUEST #%d \"%s\">"):format(u:GetId(),u:GetTitle()) end,
	[Unit] = function(u) return ("<UNIT %s (#%d)>"):format(u:GetName(), (u:GetId() or -1)) end,
	[Vector3] = function(u)
			local s = tostring(u)
			local x,y,z = s:match("Vector3%((.*), (.*), (.*)%)")
			if z then return ("Vector3 (%.2f, %.2f, %.2f)"):format(tonumber(x),tonumber(y),tonumber(z)) end
		end,
	[Window] = function(u) return ("<WINDOW \"%s\">"):format(u:GetName()) end,
}

-----------------------------------------------------------------------------------------------
-- Helper functions
-----------------------------------------------------------------------------------------------
local function spairs(t)
	-- Collect keys
	local keys = {}
	local sort = true

	for k in pairs(t) do
		keys[#keys + 1] = k
		if type(k) ~= "string" then
			sort = false
		end
	end

	if sort then
		tsort(keys)
	end

	-- Return the iterator function
	local i = 0
	return function()
		i = i + 1
		if keys[i] then
			return keys[i], t[keys[i]]
		end
	end
end

-----------------------------------------------------------------------------------------------
-- Initialization
-----------------------------------------------------------------------------------------------
function Rover:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self

	self.bIsInitialized = false
	self.bModifierAddAsTop = false

	self.tPreInitData = {}
	self.tManagedVars = {}
	self.RoverIDNum = 1
	self.sSuperSecretNilReplacement = "yyeuriofhdsagjkgadsfbjgcratejasfdghljkdsglasgisjadskhfglasfdghreuigalivejsdhflds"

  -- initialize variables here

  return o
end

function Rover:Init()
    Apollo.RegisterAddon(self)
end

-----------------------------------------------------------------------------------------------
-- Rover OnLoad/Save/Restore
-----------------------------------------------------------------------------------------------
function Rover:OnLoad()
	--Time to get crazy... lets load our own toc
	local tTOCXml = XmlDoc.CreateFromFile("toc.xml"):ToTable()
	self.tXML = {}
	local nIndex = 1
	for k,v in pairs(tTOCXml) do
		if v.__XmlNode == "DocData" then
			local pDir = Apollo.GetAssetFolder() .. "\\" .. v.Name
			tinsert(tXMLRefs, Apollo.GetAssetFolder() .. "\\" .. v.Name)
			self.tXML[nIndex] = XmlDoc.CreateFromFile(Apollo.GetAssetFolder() .. "\\" .. v.Name):ToTable()
			nIndex = nIndex + 1
		end
	end

    -- load our form file
	self.xmlDoc = XmlDoc.CreateFromFile("Rover.xml")
	Apollo.LoadSprites("RoverSprites.xml", "RoverSprites")
	-- Register the callback for when the xml is finished loading
	self.xmlDoc:RegisterCallback("OnDocumentLoaded", self)
end

function Rover:OnSave(eLevel)
	if eLevel ~= GameLib.CodeEnumAddonSaveLevel.Character then
		return
	end

	local tSave = {
		tBookmarks = {},
	}
	for k,v in pairs(self.tBookmarks) do
		tinsert(tSave.tBookmarks, k)
	end

	return tSave
end

function Rover:OnRestore(eLevel, tSavedData)
	if eLevel ~= GameLib.CodeEnumAddonSaveLevel.Character then
		return
	end
	self.tPendingMarks = tSavedData.tBookmarks
end

-----------------------------------------------------------------------------------------------
-- Rover XML Document load
-----------------------------------------------------------------------------------------------
function Rover:OnDocumentLoaded()
	self.wndMain = Apollo.LoadForm(self.xmlDoc, "RoverForm", nil, self)
	if self.wndMain == nil then
		Apollo.AddAddonErrorText(self, "Could not load the main window for some reason.")
		return "Could not load the main window for some reason."
	end

	self.wndMain:Show(false, true)

	-- if the xmlDoc is no longer needed, you should set it to nil
	-- self.xmlDoc = nil

	-- save some windows for later
	self.wndTree = self.wndMain:FindChild("Variables")
	self.wndRemoveBtn = self.wndMain:FindChild("s_Column1"):FindChild("RemoveVar")
	self.wndEvtTree = self.wndMain:FindChild("EventsList")
	self.wndTranscriptTree = self.wndMain:FindChild("TranscriptsList")
	self.wndChnTree = self.wndMain:FindChild("ChannelsList")
	self.wndParametersDialog = self.wndMain:FindChild("ParametersDialog")
	self.wndWatchDialog = self.wndMain:FindChild("WatchDialog")
	self.wndMarkTree = self.wndMain:FindChild("BookmarksList")

	-- more initialization here
	-- Register handlers for events, slash commands and timer, etc.
	-- e.g. Apollo.RegisterEventHandler("KeyDown", "OnKeyDown", self)
	Apollo.RegisterSlashCommand("rover", "OnRoverOn", self)

	self.wndMain:FindChild("AutoScrollButton"):SetCheck(true)

	self.wndTree:SetColumnWidth(eRoverColumns.VarName, 200)
	self.wndTree:SetColumnWidth(eRoverColumns.Type, 150)
	self.wndTree:SetColumnWidth(eRoverColumns.Value, 300)
	self.wndTree:SetColumnWidth(eRoverColumns.LastUpdate, 100)

	self.tMonitoredEvents = {}
	self.tTranscripted = {}
	self.tChannels = {}
	self.tBookmarks = {}

	-- Event Handlers
	Apollo.RegisterEventHandler("SendVarToRover", "AddWatch", self)
	Apollo.RegisterEventHandler("RemoveVarFromRover", "RemoveWatch", self)
	Apollo.RegisterEventHandler("WindowManagementReady", "OnWindowManagementReady", self)
	Apollo.RegisterEventHandler("InterfaceMenuListHasLoaded", "OnInterfaceMenuListHasLoaded", self)
	Apollo.RegisterEventHandler("ToggleRoverWindow", "OnRoverOn", self)

	self.bIsInitialized = true
	for sVarName, varData in pairs(self.tPreInitData) do
		if varData == self.sSuperSecretNilReplacement then
			self:AddWatch(sVarName, nil)
		else
			self:AddWatch(sVarName, varData)
		end
		self.tPreInitData[sVarName] = nil
	end
end

function Rover:OnWindowManagementReady()
	Event_FireGenericEvent("WindowManagementAdd", {wnd = self.wndMain, strName = "Rover"})

	-- If we have pending bookmarks we need to process them then display the form if needed.
	if self.tPendingMarks then
		local bFound
		for k,v in ipairs(self.tPendingMarks) do
			self:AddBookmark(v)
			local bSuccess, vWatch = pcall(loadstring("return " .. v))
			if bSuccess then
				bFound = true
				self:AddWatch(v,vWatch)
			end
		end
		-- Remove Pending Bookmarks
		self.tPendingMarks = nil
		if bFound then
			self:OnRoverOn()
		end
	end
end

function Rover:OnInterfaceMenuListHasLoaded()
	Event_FireGenericEvent("InterfaceMenuList_NewAddOn","Rover", {"ToggleRoverWindow", "", "RoverSprites:RoverIcon"})
end

function Rover:JumpToBottom()
	self.wndTree:SetVScrollPos(self.wndTree:GetVScrollRange())
end

-----------------------------------------------------------------------------------------------
-- Rover Functions
-----------------------------------------------------------------------------------------------
-- Define general functions here

-- on SlashCommand "/rover"
function Rover:OnRoverOn(strCommand, strParam)
	self.wndMain:Show(not self.wndMain:IsVisible() or (strParam and strParam ~= "")) -- toggle the window
	if strParam and strParam ~= "" then
		local bSuccess, vWatch = pcall(loadstring("return " .. strParam))
		if not bSuccess then
			self:AddWatch(strParam, self:ParseErrorString(vWatch))
			return
		end
		self:AddWatch(strParam, vWatch)
	end
end

-- Refactored so can be used for timestamping Events
function Rover:UpdateTimeStamp(hNode)
	local tTime = GameLib.GetLocalTime()
	local strAMPM = "AM"
	local nHour = tTime.nHour
	if tTime.nHour == 0 then
		nHour = 12
	elseif tTime.nHour == 12 then
		strAMPM = "PM"
	elseif tTime.nHour > 12 then
		nHour = nHour - 12
		strAMPM = "PM"
	end
	local strTime = strformat("%d:%02d:%02d %s", nHour, tTime.nMinute, tTime.nSecond, strAMPM)
	self.wndTree:SetNodeText(hNode, eRoverColumns.LastUpdate, strTime)
end

-- Provide a level of uniqueness
function Rover:GetRoverID()
	-- Increment RID
	self.RoverIDNum = self.RoverIDNum + 1
	-- Return new RID to be used.
	return self.RoverIDNum
end

-----------------------------------------------------------------------------------------------
-- RoverForm Functions
-----------------------------------------------------------------------------------------------
-- when the Close button is clicked
function Rover:OnCloseRover()
	self.wndMain:Show(false) -- hide the window
end

function Rover:OnSizeChanged( wndHandler, wndControl )
	if wndHandler ~= wndControl then
		return
	end
	local nBorderSize = 7
	-- DOUBLE DOG DERP!! TreeControl doesn't have a header row (YET) so we have to
	-- explicitly adjust column widths as the parent's size changes
	for nLabelNumber = 1,4 do
		local strLabel = strformat("s_Column%d", nLabelNumber)
		local wndLabel = self.wndMain:FindChild(strLabel)
		local nWidth = wndLabel:GetWidth()
		if nLabelNumber == 1 or nLabelNumber == 4 then
			-- Adjust column width to account for TreeControl's left and right borders
			nWidth = nWidth - nBorderSize
		end

		self.wndTree:SetColumnWidth(nLabelNumber, nWidth)
	end
end

function Rover:OnParametersClose( wndHandler, wndControl, eMouseButton )
	self.wndParametersDialog:FindChild("ParameterInput"):SetText("")
	self.wndParametersDialog:Show(false)
end

function Rover:OnWatchClose( wndHandler, wndControl, eMouseButton )
	self.wndWatchDialog:FindChild("WatchInput"):SetText("")
	self.wndWatchDialog:Show(false)
end

-----------------------------------------------------------------------------------------------
-- Rover Variable Tracking Functions
-----------------------------------------------------------------------------------------------
function Rover:AnalyzeUserData(userdata, hNode)
	for base, fnDisplay in pairs(Rover.userdataDisplay) do
		if base.is and base.is(userdata) then return fnDisplay(userdata, hNode) end
		if base.Is and base.Is(userdata) then return fnDisplay(userdata, hNode) end
		if base.isInstance and base.isInstance(userdata) then return fnDisplay(userdata, hNode) end
	end
	return tostring(userdata)
end

function Rover:SelectIcon(var, strType, hParent)
	local retVal
	if strType == "function" then
		retVal = "CRB_Basekit:kitIcon_Holo_LFG"
	elseif strType == "number" and self.wndTree:GetNodeData(hParent) == _G.Sound then
		retVal = "RoverSprites:SoundIcon"
	end

	return retVal
end

function Rover:AddVariable(strName, var, hParent)
	if hParent == 0 then
		if self.tManagedVars[strName] ~= nil then
			self:RemoveWatch(strName)
		end
	end

	-- Regardles of the index for saving, we call it what we are expecting to
	local hNewNode = self.wndTree:AddNode(hParent, strName, "", var)
	if hParent == 0 then
		self.tManagedVars[strName] = hNewNode
	end

	local strType = type(var)
	self.wndTree:SetNodeText(hNewNode, eRoverColumns.Type, strType, var)

	if strType == "nil" then
		return
	end

	if strType == "table" or strType == "userdata" then
		local hPlace = self.wndTree:AddNode(hNewNode, "PLACEHOLDER", "")
		self.wndTree:CollapseNode(hNewNode)
	end

	local str = strType == "userdata" and self:AnalyzeUserData(var, hNewNode) or tostring(var)

	local nodeIcon = self:SelectIcon(var, strType, hParent)
	if nodeIcon then
		self.wndTree:SetNodeImage(hNewNode, nodeIcon)
	end

	-- Per SinusPi strings over 100 cause a crash.. double click to view instead!
	if #str > 100 then
		str = str:sub(1,100) .. " ..."
	end

	self.wndTree:SetNodeText(hNewNode, eRoverColumns.Value, str)
	self:UpdateTimeStamp(hNewNode)

	if not self.wndMain:FindChild("AutoScrollButton"):IsChecked() then -- Lock icon has reverse logic apparently
		if tBottomTimer then
			tBottomTimer:Start()
		else
			tBottomTimer = ApolloTimer.Create(0.1, false, "JumpToBottom", self)
		end
	end
end

function Rover:OnExpandNode( wndHandler, wndControl, hNode )
	local var = self.wndTree:GetNodeData(hNode)
	if type(var) ~= "table" and type(var) ~= "userdata" then
		return
	end
	self.wndTree:DeleteChildren(hNode)

	-- All tables/userdata can have metatables let's check for one.
	local mt = getmetatable(var)
	-- If we found a metatable then add that to Rover
	if mt ~= nil then
		self:AddVariable("metatable", mt, hNode)
	end
	-- If this is a table and not userdata, then we need to add all the keys
	if type(var) == "table" then
		-- sorted by keys
		for k,v in spairs(var) do
			self:AddVariable(tostring(k), v, hNode)
		end
	end
	self:UpdateTimeStamp(hNode)
end

function Rover:OnTwoClicks( wndHandler, wndControl, hNode )
	local var = self.wndTree:GetNodeData(hNode)
	local hParent = self.wndTree:GetParentNode(hNode)

	-- Play sounds, courtesy of SinusPi
	if type(var) == "number" and self.wndTree:GetNodeData(hParent) == _G.Sound then
		_G.Sound.Play(var)
		return
	elseif type(var) == "string" then
		self:GenerateTextBox(self.wndTree:GetNodeText(hNode, eRoverColumns.VarName), var)
		return
	elseif type(var) ~= "function" then
		return
	end

	if Apollo.IsShiftKeyDown() then
		self.wndParametersDialog:SetData(hNode)
		self.wndParametersDialog:Show(true)
		self.wndParametersDialog:FindChild("IncludeSelfBtn"):SetCheck(self.wndTree:GetNodeText(hParent) == 'metatable')
		self.wndParametersDialog:FindChild("ParameterInput"):SetFocus()
		return
	end

	self.wndTree:DeleteChildren(hNode)

	local hGrandParent = self.wndTree:GetParentNode(hParent)

	self:AddCallResult(hNode, pcall(function()
		if self.wndTree:GetNodeText(hParent) == 'metatable' then
			return var(self.wndTree:GetNodeData(self.wndTree:GetParentNode(hParent)))
		elseif hGrandParent and self.wndTree:GetNodeText(hGrandParent) == 'metatable' then
			return var(self.wndTree:GetNodeData(self.wndTree:GetParentNode(hGrandParent)))
		else
			return var()
		end
	end))
end

function Rover:OnParameterInputEnter( wndHandler, wndControl, strText )
	local varStr = "return {" .. strText .. "}"

	local bSuccess, tParameters = pcall(loadstring(varStr))
	if not bSuccess then
		self:AddWatch("Invalid Parameters:", strText)
		return
	end

	local hNode = self.wndParametersDialog:GetData()
	local var = self.wndTree:GetNodeData(hNode)
	self.wndTree:DeleteChildren(hNode)

	local hParent = self.wndTree:GetParentNode(hNode)
	local bIncludeSelf = self.wndParametersDialog:FindChild("IncludeSelfBtn"):IsChecked()

	wndControl:SetText("")
	self.wndParametersDialog:Show(false)

	self:AddCallResult(hNode, pcall(function()
		if bIncludeSelf then
			if self.wndTree:GetNodeText(hParent) == 'metatable' then
				return var(self.wndTree:GetNodeData(self.wndTree:GetParentNode(hParent)), unpack(tParameters))
			else
				return var(self.wndTree:GetNodeData(hParent), unpack(tParameters))
			end
		else
			return var(unpack(tParameters))
		end
	end))
end

function Rover:AddCallResult(hNode, bExecutedCorrectly, ...)
	if not bExecutedCorrectly then
		self:AddVariable("execution error", self:ParseErrorString(arg[1]), hNode)
		return
	end

	if arg.n == 0 then
		self:AddVariable("no return value", nil, hNode)
		return
	end

	if arg.n == 1 then
		self:AddVariable("result", arg[1], hNode)
		return
	end

	for i, result in pairs(arg) do
		if i ~= 'n' then
			self:AddVariable("result " .. i, result, hNode)
		end
	end
end

function Rover:ParseErrorString(sError)
	local startIndex = sError:find("bad argument")

	if startIndex == nil then
		return sError
	end

	return sError:sub(startIndex)
end

function Rover:AddWatch(strName, var, iOptions)
	if self.bIsInitialized == false then
		if iOptions == self.ADD_ONCE and self.tPreInitData[strName] ~= nil then
			return
		elseif iOptions == self.ADD_ALL and self.tPreInitData[strName] ~= nil then
			strName = strName .. "  (+" .. self:GetRoverID() .. ")"
		end

		if var == nil then
			var = self.sSuperSecretNilReplacement
		end
		self.tPreInitData[strName] = var
	else
		if iOptions == self.ADD_ONCE and self.tManagedVars[strName] ~= nil then
			return
		elseif iOptions == self.ADD_ALL and self.tManagedVars[strName] ~= nil then
			strName = strName .. "  (+" .. self:GetRoverID() .. ")"
		end

		self:AddVariable(strName, var, 0)
	end
end

function Rover:RemoveWatch(strName)
	if self.bIsInitialized == false then
		self.tPreInitData[strName] = nil
	elseif self.tManagedVars[strName] ~= nil then
		self.wndTree:DeleteNode(self.tManagedVars[strName])
		self.tManagedVars[strName] = nil
	end
end

function Rover:OnRemoveVarClicked(wndHandler, wndControl)
	local hNode = self.wndTree:GetSelectedNode()
	if hNode > 0 and self.wndTree:GetParentNode(hNode) == 0 then
		local strText = self.wndTree:GetNodeText(hNode, eRoverColumns.VarName)
		self.tManagedVars[strText] = nil
		self.wndTree:DeleteNode(hNode)

		if not Apollo.IsShiftKeyDown() then return end

		local strMonitorName, strItemName = strText:match("(%w-): ([^%s]+)")

		if strMonitorName == "Event" then
			self:OnRemoveEventMonitor(strItemName)
		elseif strMonitorName == "Channel" then
			self:OnRemoveChannelListening(strItemName)
		else
			return  -- Nothing special
		end

		local strMatch = strMonitorName .. ": " .. strItemName
		for k,v in pairs(self.tManagedVars) do
			local strNodeText = self.wndTree:GetNodeText(v, eRoverColumns.VarName)
			if strNodeText and strNodeText:match(strMatch) then
				self.wndTree:DeleteNode(v)
				self.tManagedVars[k] = nil
			end
		end
	end
end

function Rover:OnNodeChanged( wndHandler, wndControl, hSelected, hPrevSelected )
	self.wndRemoveBtn:Show(hSelected > 0 and self.wndTree:GetParentNode(hSelected) == 0)
end

-- Button to Remove all Variables
function Rover:OnRemoveAllVars( wndHandler, wndControl, eMouseButton )
	for k,v in pairs(self.tManagedVars) do
		self:RemoveWatch(k)
	end
end

function Rover:GenerateTextBox(strName, strText)
	local wndTextBox = Apollo.LoadForm(self.xmlDoc, "TextBox", nil, self)
	wndTextBox:FindChild("Title"):SetText(strName)
	wndTextBox:FindChild("Text"):SetText(strText)
end

function Rover:OnTextBoxClose( wndHandler, wndControl, eMouseButton )
	wndControl:GetParent():GetParent():Destroy()
end

function Rover:PrepareCopy(wndHandler, wndControl)
	wndControl:SetActionData(GameLib.CodeEnumConfirmButtonType.CopyToClipboard, wndControl:GetParent():GetParent():FindChild("Text"):GetText())
end

-----------------------------------------------------------------------------------------------
-- Rover Add buttons
-----------------------------------------------------------------------------------------------

function Rover:OnAddGlobalsVar()
	self:AddVariable("_G", _G, 0)
end

function Rover:OnAddMyselfVar()
	local uUnit = GameLib.GetPlayerUnit()

	if uUnit ~= nil then
		self:AddVariable("myself (" .. uUnit:GetName() .. ")", uUnit, 0)
	end
end

function Rover:OnAddVar()
	self.wndWatchDialog:Show(true)
	self.wndWatchDialog:FindChild("WatchInput"):SetFocus()
end

function Rover:OnWatchInputEnter( wndHandler, wndControl, strText )
	local varStr = "return " .. strText

	local bSuccess, vWatch = pcall(loadstring(varStr))
	if not bSuccess then
		return
	end

	wndControl:SetText("")
	self.wndWatchDialog:Show(false)

	self:AddWatch(strText, vWatch, not self.wndWatchDialog:FindChild("UniqueBtn"):IsChecked() and self.ADD_DEFAULT or self.ADD_ALL)
end

function Rover:OnAddTargetVar()
	local uUnit = GameLib.GetTargetUnit()

	if uUnit ~= nil then
		self:AddVariable("target (" .. uUnit:GetName() .. ")", uUnit, 0)
	end
end

function Rover:EnableModifierAdd()
	self.bModifierAddAsTop = false

	local btnMdTop = self.wndMain:FindChild("ButtonAddByModifierTop")
	if btnMdTop:IsChecked() then
		btnMdTop:SetCheck(false)
		return
	end

	self:EnableModifierTimer()
end

function Rover:EnableModifierAddTop()
	self.bModifierAddAsTop = true

	local btnMd = self.wndMain:FindChild("ButtonAddByModifier")
	if btnMd:IsChecked() then
		btnMd:SetCheck(false)
		return
	end

	self:EnableModifierTimer()
end

function Rover:EnableModifierTimer()
	if tModifierTimer then
		tModifierTimer:Start()
	else
		tModifierTimer = ApolloTimer.Create(0.1, true, "OnModifierAddCheck", self)
	end
end

function Rover:DisableModifierTimer()
	tModifierTimer:Stop()
end

function Rover:OnModifierAddCheck()
	if not Apollo.IsControlKeyDown() then
		return
	end

	local wndFound = Apollo.GetMouseTargetWindow()

	if wndFound == nil then
		return
	end

	if self.bModifierAddAsTop then
		local wndParent = wndFound
		while wndParent ~= nil do
			wndFound = wndParent
			wndParent = wndFound:GetParent()
		end
	end

	self:AddWatch("Window: " .. wndFound:GetName(), wndFound, self.ADD_ALL)

	self.wndMain:FindChild("ButtonAddByModifier"):SetCheck(false)
	self.wndMain:FindChild("ButtonAddByModifierTop"):SetCheck(false)
	self:DisableModifierTimer()
end

-----------------------------------------------------------------------------------------------
-- Rover Event Monitoring
-----------------------------------------------------------------------------------------------

local function ParseEventXML(tXML)
	for _,v in ipairs(tXML) do
		if v.__XmlNode == "Event" then
			tEvents[v.Name] = v.Desc or ""
		end
		if v[1] then
			ParseEventXML(v)
		end
	end
end

function Rover:OnAddAllEvents()
	if tXMLRefs then
		for _,file in ipairs(tXMLRefs) do
			local tXML = XmlDoc.CreateFromFile(file):ToTable()
			ParseEventXML(tXML)
		end
		tXMLRefs = nil
	end
	for k,v in spairs(tEvents) do
		if not tBlacklistedEvents[k] then
			self:OnAddEventMonitor(k, v)
		end
	end
end

function Rover:BuildMonitorFunc(eventName, strDesc)
	-- Use a closure instead, much cleaner than previous method
	local eName = "Event: " .. eventName
	local strDescription = strDesc and strDesc ~= "" and strDesc or nil
	return  function(self,...)
				arg.strDesc = strDescription
				self:AddWatch(eName, arg, 0)
			end
end

-- Adds Event Monitoring for specified event
function Rover:OnAddEventMonitor(eventName, strDesc)
	-- If we are already monitoring this then just stop now!
	if self.tMonitoredEvents[eventName] ~= nil then
		return
	end

	-- Can't add monitoring of Rover events... lets not break Rover please.
	if eventName == "SendVarToRover" or eventName == "RemoveVarFromRover" then
		return
	end

	-- Add new entry to tree for viewing
	local hNewNode = self.wndEvtTree:AddNode(0, eventName, "", eventName)
	-- Store reference to node
	self.tMonitoredEvents[eventName] = hNewNode

	-- Build handler name, use the prefix + eventName
	local handlerName = handlerPrefix..eventName
	-- Create handler and assign it to rover
	Rover[handlerName] = self:BuildMonitorFunc(eventName, strDesc)
	-- Register handler with Apollo
	Apollo.RegisterEventHandler(eventName, handlerName, self)
end

-- Remove event monitoring for specified event
function Rover:OnRemoveEventMonitor(eventName)
	-- If we aren't monitoring this event, stop now!
	if self.tMonitoredEvents[eventName] ~= nil then
		-- Remove display node for event
		self.wndEvtTree:DeleteNode(self.tMonitoredEvents[eventName])

		-- Build handler name, use the prefix + eventName
		local handlerName = handlerPrefix..eventName
		-- Clear out monitored event reference
		self.tMonitoredEvents[eventName] = nil
		-- Remove eventhandler function
		Rover[handlerName] = nil
		-- Tell Apollo we don't want to listen for this event anymore.
		Apollo.RemoveEventHandler(eventName, self)
	end
end

-- Close button on event form, toggle the event button then close via toggle func
function Rover:OnEventsCloseClick( wndHandler, wndControl, eMouseButton )
	self.wndMain:FindChild("EventsBtn"):SetCheck(false)
	self:OnEventsMonitorToggle()
end

-- Double clicking events deletes them, so lets get the event name then use OnRemoveEventMonitor
function Rover:OnEventDoubleClick( wndHandler, wndControl, hNode )
	local strEventName = wndControl:GetNodeData(hNode)
	self:OnRemoveEventMonitor(strEventName)
end

-- Remove all Monitored Events
function Rover:OnRemoveAllEventMonitors( wndHandler, wndControl, eMouseButton )
	for _, EventNode in pairs(self.tMonitoredEvents) do
		local eventName = self.wndEvtTree:GetNodeData(EventNode)
		self:OnRemoveEventMonitor(eventName)
	end
end

-- Toggle if the Event Form is displayed or not
function Rover:OnEventsMonitorToggle( wndHandler, wndControl, eMouseButton )
	-- Determine if we are going to be showing this window or not
	local bShowWnd = self.wndMain:FindChild("EventsBtn"):IsChecked()
	if bShowWnd then
		-- If we were previously showing one of the windows hide it
		if self.wndPrevious then
			self.wndPrevious:Show(false)
		end
		-- Record that this window is now showing
		self.wndPrevious = self.wndMain:FindChild("EventsWindow")
	else
		-- We closed the window, so no window is showing now
		self.wndPrevious = nil
	end
	-- Set proper shown state
	self.wndMain:FindChild("EventsWindow"):Show(bShowWnd)
end

-- Handles someone pressing enter after typing the name of the event to monitor
--	Also hides entry section once entered.
function Rover:OnEventInputReturn( wndHandler, wndControl, strText )
	self:OnAddEventMonitor(strText)
	wndControl:SetText("")
	self.wndMain:FindChild("AddEventBtn"):SetCheck(false)
	self:OnAddEventToggle()
end

-- Add Event button, toggles input section for entry of event name
function Rover:OnAddEventToggle( wndHandler, wndControl, eMouseButton )
	local showWnd = self.wndMain:FindChild("AddEventBtn"):IsChecked()
	self.wndMain:FindChild("EventInputContainer"):Show(showWnd)
	if showWnd then
		self.wndMain:FindChild("EventInput"):SetFocus()
	end
end

-----------------------------------------------------------------------------------------------
-- Rover Transcription
-----------------------------------------------------------------------------------------------

-- This takes advantage of closures, each call of this function will return a function that has its own
--	unique nCount that will count up as used.  This function will become the new metatable index
--	function for some addon.  All addons currently by default are instances that are children of the
--	base addon.  Because of this all data is stored on the metatable (self, the addon itself) and not
--	the instance of the class, unless done so after the fact or explicitly.  As the __index metamethod
--	is called when we would normally get a nil result (pretty much everything since almost everything
--	is in the metatable) we can use it as a quasi-logger.  We save the name of the item accessed and
--	the order it was accessed to a table (to avoid repeats or changing call order) then send that to
--	the variable display panel.  We then return whatever the original metamethod would have, this way
--	if something did have a custom metamethod for __index we preserve whatever was intended.
--
-- NOTE: This will record _all_ attempts to access things undefined on the instance of the addon.
--	this includes functions that do not exist but have attempts to them call anyway. For example:
--	OnAsyncLoadStatus during load.
function Rover:BuildTranscriptor(strAddon)
	-- Store a reference to self so we can use it without confusing everyone!
	--	Also store a reference to the addonname and initialize nCount
	local strAddonName, tRover, nCount = strAddon, self, 1
	local strOriginalIndex, strDetailed = kStrOriginalIndex, kStrDetailed
	-- Metamethod takes 2 arguments, the table we are looking in and the key we are looking for
	return function(table, key)
		local strObjType, retVal = ".", nil

		-- Retrieve reference to original metamethod for __index
		local OriginalIndex = tRover.tTranscripted[strAddonName][strOriginalIndex]
		-- If the original metamethod was a table return it indexed by the key
		if type(OriginalIndex) == "table" then
			retVal = OriginalIndex[key]
		-- If the original metamethod was a function we need to return its return value
		elseif type(OriginalIndex) == "function" then
			retVal = OriginalIndex(table, key)
		end

		-- If the return value is a function we use the : operator to indicate it, otherwise it uses .
		if type(retVal) == "function" then
			strObjType = ":"
		end

		-- Check to see if we have this addon set for detailed recording
		if tRover.tTranscripted[strAddonName][strDetailed] then
			-- Detailed means every instance that occurs ... probably extremely spammy!, also since its detailed, lets send rover whatever it was trying to retrieve
			self:AddWatch(strformat("%s%s%s (#%d)", strAddonName, strObjType, key, nCount), retVal, Rover.ADD_ONCE)
			-- Increment the counter
			nCount = nCount + 1
		else -- Normal function calls as they occur logging
			-- No record of this key before, set its call number to 1
			if tRover.tTranscripted[strAddonName][key] == nil then
				tRover.tTranscripted[strAddonName][key] = 1
			else
				-- Otherwise increment the number of calls
				tRover.tTranscripted[strAddonName][key] = tRover.tTranscripted[strAddonName][key] + 1
			end
			-- Send to Rover and replace the existing value, causes it to pop down to the bottom.
			self:AddWatch(strformat("%s%s%s", strAddonName, strObjType, key), 'Calls: ' .. tRover.tTranscripted[strAddonName][key], Rover.ADD_DEFAULT)
		end

		return retVal
	end
end

local function deepcopy(orig)
	local orig_type = type(orig)
	local copy
	if orig_type == 'table' then
		copy = {}
		for orig_key, orig_value in next, orig, nil do
			-- Inifinite loops are bad okay, lets just put indexes to the same state
			if orig_key == "__index" or orig_key == "__newindex" then
				copy[orig_key] = orig_value
			else
				copy[deepcopy(orig_key)] = deepcopy(orig_value)
			end
		end
		setmetatable(copy, deepcopy(getmetatable(orig)))
	else -- number, string, boolean, etc
		copy = orig
	end
	return copy
end

-- Adds a metatable with the addons previous contents to an addon.
function Rover:AddMetatable(aAddon)
	-- If this addon directly has a __index metamethod we nil it out (This fixes infinite recursion problems)
	--	TargetFrame for example has a __index which points back to itself so Table Copy will not work.
	--	metamethods should be defined on metatables anyway not the table in use.  This problem occurs because
	--	New was called on the base addon to generate an instance which assigned a __index to it pointing back
	--	to itself, however the base addon is then passed to Apollo instead of the instance.  Typically the
	--	instance should be passed where this __index is a metamethod on the metatable rather than the addon
	--	itself.
	aAddon.__index = nil
	-- Our new metatable is actually the old addon table, all functions/variables/etc so we duplicate it
	local newMt = deepcopy(aAddon)
	-- The metatable's metamethod will point back to the metatable for non-found items in the parent
	newMt.__index = newMt
	-- New entries should be made on the previous addon, this means we can keep tracking changes.
	newMt.__newindex = newMt
	-- Boolean to indicate we put a new metatable around this already
	newMt.___bWrapped = true

	-- Set the metatable on this 'new' soon to be blank Addon table to our new metatable containing all the old data
	setmetatable(aAddon, newMt)
	-- Time to wipe out all contents of the addon, we have to do it this way as you cannot assign to
	--	Apollo.GetAddon("AddonName").  So instead we just nil out all entries which is effectively the same
	--	as assigning a blank table.  pairs doesn't iterate over metatables so we are fine.  We set the
	--	metatable first so there is no interruption in service, it is theoretically possible that some variable
	--	state might get changed between the copy and the assignment/wipe and this _could_ cause some issue
	--	but hey this is for addon devs, take this into account please when looking at stuff.
	for k,v in pairs(aAddon) do
		aAddon[k] = nil
	end

	-- Return a reference to the new metatable
	return newMt
end

-- Use PCall to turn the string into a real reference
function Rover:FindTable(strTable)
	local varStr = "return " .. strTable
	local bSuccess, tTable = pcall(loadstring(varStr))
	if not bSuccess or type(tTable) ~= "table" then
		return nil
	end
	return tTable
end

-- Function to initiate transcription of an Addon
function Rover:StartTranscript(strTable, bForceAddMeta)
	-- Can't start a transcript of something we are already transcribing or Rover
	if self.tTranscripted[strTable] ~= nil or strTable == "Rover" then
		return
	end
	-- Attempt to retrieve a reference to the Addon/Package in question
	local tTable = Apollo.GetAddon(strTable) or Apollo.GetPackage(strTable) or self:FindTable(strTable)
	-- If no reference found we can stop now
	if not tTable then return end
	-- Get a reference to the metatable for the Addon/Package or alternatively add a metatable with the addon contents
	local mt = getmetatable(tTable)
	-- If we're forcing a new metatable on this we need to check and see we haven't done that already (bad mojo!)
	if not mt or bForceAddMeta and not mt.___bWrapped then
		self.wndMain:FindChild("ForceAddMetaBtn"):SetCheck(false)
		self:AddWatch("NOTICE", "Adding metatable to Addon/Package/Table " .. strTable .. ".", 0)
		mt = self:AddMetatable(tTable)
	end
	-- If for some bizarre reason we _still_ don't have a metatable we have a problem
	if mt == nil then
		-- Warn people there is no metatable, can't log it.
		self:AddWatch("WARNING!", "Addon/Package/Table " .. strTable .. " has no metatable!", 0)
		return
	end

	-- Add a node to the transcript list
	local hNewNode = self.wndTranscriptTree:AddNode(0, strTable, "", strTable)

	-- Create table to store the list of accessed variables .. and the original __
	self.tTranscripted[strTable] = {}
	-- Store a copy of the original __index so we can revert and also still use it
	self.tTranscripted[strTable][kStrOriginalIndex] = mt.__index
	-- Store a reference to the node that we generated in the tree
	self.tTranscripted[strTable][kStrNodeIndex] = hNewNode
	-- Assign the __index metamethod to our custom metamethod
	mt.__index = self:BuildTranscriptor(strTable)
end

-- Function to cease transcripting an addon
function Rover:StopTranscript(strTable)
	-- If we haven't started a Transcript of this addon we can't stop one either.
	if self.tTranscripted[strTable] == nil then
		return
	end
	-- Delete the node this addon has.
	self.wndTranscriptTree:DeleteNode(self.tTranscripted[strTable][kStrNodeIndex])

	-- Attempt to retrieve a reference to the Addon/Package/Table in question
	local tAddon = Apollo.GetAddon(strTable) or Apollo.GetPackage(strTable) or self:FindTable(strTable)
	-- If no reference found, then we can stop now
	if not tAddon then return end
	-- Get a reference to the metatable for the Addon
	local mt = getmetatable(tAddon)
	-- Set the __index metamethod back to what we saved originally
	mt.__index = self.tTranscripted[strTable][kStrOriginalIndex]
	-- delete the transcripted records for this Addon
	self.tTranscripted[strTable] = nil
end

-- Close button on event form, toggle the Logs button then close via toggle func
function Rover:OnTranscriptsCloseClick( wndHandler, wndControl, eMouseButton )
	self.wndMain:FindChild("TranscriptBtn"):SetCheck(false)
	self:OnTranscriptsMonitorToggle()
end

-- Double clicking Transcriptors deletes them, so lets get the event name then use StopTranscript
function Rover:OnTranscriptDoubleClick( wndHandler, wndControl, hNode )
	local strAddonName = wndControl:GetNodeData(hNode)
	self:StopTranscript(strAddonName)
end

-- Remove all Transcriptors
function Rover:OnRemoveAllTranscripts( wndHandler, wndControl, eMouseButton )
	for _, TranscriptNode in pairs(self.tTranscripted) do
		local strAddonName = self.wndTranscriptTree:GetNodeData(TranscriptNode[kStrNodeIndex])
		self:StopTranscript(strAddonName)
	end
end

-- Toggle if the Transcripts Form is displayed or not
function Rover:OnTranscriptsMonitorToggle( wndHandler, wndControl, eMouseButton )
	-- Determine if we are going to be showing this window or not
	local bShowWnd = self.wndMain:FindChild("TranscriptBtn"):IsChecked()
	if bShowWnd then
		-- If we were previously showing one of the windows hide it
		if self.wndPrevious then
			self.wndPrevious:Show(false)
		end
		-- Record that this window is now showing
		self.wndPrevious = self.wndMain:FindChild("TranscriptsWindow")
	else
		-- We closed the window, so no window is showing now
		self.wndPrevious = nil
	end
	-- Set proper shown state
	self.wndMain:FindChild("TranscriptsWindow"):Show(bShowWnd)
end

-- Handles someone pressing enter after typing the name of the Addon to monitor
--	Also hides entry section once entered.
function Rover:OnTranscriptInputReturn( wndHandler, wndControl, strText )
	self:StartTranscript(strText, self.wndMain:FindChild("ForceAddMetaBtn"):IsChecked())
	wndControl:SetText("")
	self.wndMain:FindChild("AddTranscriptBtn"):SetCheck(false)
	self:OnAddTranscriptToggle()
end

-- Add Transcript button, toggles input section for entry of event name
function Rover:OnAddTranscriptToggle( wndHandler, wndControl, eMouseButton )
	local showWnd = self.wndMain:FindChild("AddTranscriptBtn"):IsChecked()
	self.wndMain:FindChild("TranscriptInputContainer"):Show(showWnd)
	if showWnd then
		self.wndMain:FindChild("TranscriptInput"):SetFocus()
	end
end

function Rover:OnTranscriptTreeSelection( wndHandler, wndControl, hSelected, hPrevSelected )
	-- Get a reference from the node
	local strAddonName = wndControl:GetNodeData(hSelected)
	-- We double clicked and deleted the node, apparently that happens before single clicks.
	if not strAddonName then return end

	-- Toggle detailed information setting
	self.tTranscripted[strAddonName][kStrDetailed] = not self.tTranscripted[strAddonName][kStrDetailed]

	if self.tTranscripted[strAddonName][kStrDetailed] then
		wndControl:SetNodeImage(hSelected, "CRB_Basekit:kitIcon_Holo_HazardObserver")
	else
		wndControl:SetNodeImage(hSelected, "")
	end
end

-----------------------------------------------------------------------------------------------
-- Rover ICComm Tracking Functions
-----------------------------------------------------------------------------------------------

function Rover:BuildChannelListener(strChannelName)
	-- Closure for channel monitoring
	local cName = "Channel: " .. strChannelName
	return  function(self, channel, tMsg, strSender)
				self:AddWatch(cName, { channel = channel, tMsg = tMsg, strSender = strSender }, 0)
			end
end

-- Adds listening to specified channel
function Rover:ListenChannel(strChannelName)
	if self.tChannels[strChannelName] ~= nil then
		return
	end

	-- Add new entry to tree for viewing
	local hNewNode = self.wndChnTree:AddNode(0, strChannelName, "", strChannelName)
	-- Store reference to node
	self.tChannels[strChannelName] = { hNode = hNewNode }

	-- Build handler name, use the prefix + eventName
	local handlerName = channelPrefix..strChannelName
	-- Create handler and assign it to rover
	self[handlerName] = self:BuildChannelListener(strChannelName)
	-- Register handler with Apollo
	self.tChannels[strChannelName].channel = ICCommLib.JoinChannel(strChannelName, handlerName, self)
end

-- Remove listening for the specified channel
-- No current way to do this so we just return
function Rover:OnRemoveChannelListening(strChannelName)
	-- If we aren't monitoring this event, stop now!
	if self.tChannels[strChannelName] ~= nil then
		-- Remove display node for event
		self.wndChnTree:DeleteNode(self.tChannels[strChannelName].hNode)

		-- Build handler name, use the prefix + eventName
		local handlerName = channelPrefix..strChannelName
		-- Clear out monitored event reference, this removes the channel object, hopefully this stops us listening
		self.tChannels[strChannelName] = nil
		-- Remove eventhandler function
		self[handlerName] = nil
	end
end

-- Remove all Monitored Channels
function Rover:OnRemoveAllChannels( wndHandler, wndControl, eMouseButton )
	for _, ChannelNode in pairs(self.tChannels) do
		local strChannelName = self.wndChnTree:GetNodeData(ChannelNode.hNode)
		self:OnRemoveChannelListening(strChannelName)
	end
end

-- Add Channel button, toggles input section for entry of ICCommLib Channel
function Rover:OnAddChannelToggle( wndHandler, wndControl, eMouseButton )
	local showWnd = self.wndMain:FindChild("AddChannelBtn"):IsChecked()
	self.wndMain:FindChild("ChannelInputContainer"):Show(showWnd)
	if showWnd then
		self.wndMain:FindChild("ChannelInput"):SetFocus()
	end
end

-- Close button on Channel form, toggle the channels button then close via toggle func
function Rover:OnChannelsCloseClick( wndHandler, wndControl, eMouseButton )
	self.wndMain:FindChild("ChannelBtn"):SetCheck(false)
	self:OnChannelsMonitorToggle()
end

-- Double clicking Channels deletes them
function Rover:OnChannelDoubleClick( wndHandler, wndControl, hNode )
	local strChannelName = wndControl:GetNodeData(hNode)
	self:OnRemoveChannelListening(strChannelName)
end

-- Handles someone pressing enter after typing the name of the channel to listen to
--	Also hides entry section once entered.
function Rover:OnChannelInputReturn( wndHandler, wndControl, strText )
	self:ListenChannel(strText)
	wndControl:SetText("")
	self.wndMain:FindChild("AddChannelBtn"):SetCheck(false)
	self:OnAddChannelToggle()
end

-- Toggle if the Channel Form is displayed or not
function Rover:OnChannelsMonitorToggle( wndHandler, wndControl, eMouseButton )
	-- Determine if we are going to be showing this window or not
	local bShowWnd = self.wndMain:FindChild("ChannelBtn"):IsChecked()
	if bShowWnd then
		-- If we were previously showing one of the windows hide it
		if self.wndPrevious then
			self.wndPrevious:Show(false)
		end
		-- Record that this window is now showing
		self.wndPrevious = self.wndMain:FindChild("ChannelsWindow")
	else
		-- We closed the window, so no window is showing now
		self.wndPrevious = nil
	end
	-- Set proper shown state
	self.wndMain:FindChild("ChannelsWindow"):Show(bShowWnd)
end

-----------------------------------------------------------------------------------------------
-- Rover Bookmarks
-----------------------------------------------------------------------------------------------

function Rover:AddBookmark(strBookmarkName)
	if self.tBookmarks[strBookmarkName] ~= nil then
		return
	end

	-- Add new entry to tree for viewing
	local hNode = self.wndMarkTree:AddNode(0, strBookmarkName, "", strBookmarkName)
	-- Store reference to node
	self.tBookmarks[strBookmarkName] = hNode
end

-- Remove all Bookmarks
function Rover:OnRemoveAllBookmarks( wndHandler, wndControl, eMouseButton )
	for strBookmarkName, BookmarkNode in pairs(self.tBookmarks) do
		self.wndMarkTree:DeleteNode(BookmarkNode)
		self.tBookmarks[strBookmarkName] = nil
	end
end

-- Close button on Bookmark form, toggle the bookmark button then close via toggle func
function Rover:OnBookmarksCloseClick( wndHandler, wndControl, eMouseButton )
	self.wndMain:FindChild("BookmarkBtn"):SetCheck(false)
	self:OnBookmarksToggle()
end

-- Add bookmark button, toggles input section for entry of bookmark
function Rover:OnAddBookmarkToggle( wndHandler, wndControl, eMouseButton )
	local showWnd = self.wndMain:FindChild("AddBookmarkBtn"):IsChecked()
	self.wndMain:FindChild("BookmarkInputContainer"):Show(showWnd)
	if showWnd then
		self.wndMain:FindChild("BookmarkInput"):SetFocus()
	end
end

-- Double clicking Bookmarks deletes them
function Rover:OnBookmarkDoubleClick( wndHandler, wndControl, hNode )
	local strBookmarkName = wndControl:GetNodeData(hNode)
	self.wndMarkTree:DeleteNode(hNode)
	self.tBookmarks[strBookmarkName] = nil
end

-- Single click a bookmark to make it show up in rover
function Rover:OnBookmarkSelection( wndHandler, wndControl, hSelected, hPrevSelected )
	-- Get a reference from the node
	local strBookmarkName = wndControl:GetNodeData(hSelected)
	-- We double clicked and deleted the node, apparently that happens before single clicks.
	if not strBookmarkName then return end
	local bSuccess, vWatch = pcall(loadstring("return " .. strBookmarkName))
	if not bSuccess then
		self:AddWatch(strBookmarkName, self:ParseErrorString(vWatch))
		return
	end
	self:AddWatch(strBookmarkName, vWatch)
end

-- Handles someone pressing enter after typing the name of the bookmark to add
--	Also hides entry section once entered.
function Rover:OnBookmarkInputReturn( wndHandler, wndControl, strText )
	self:AddBookmark(strText)
	wndControl:SetText("")
	self.wndMain:FindChild("AddBookmarkBtn"):SetCheck(false)
	self:OnAddBookmarkToggle()
end

-- Toggle if the Bookmark Form is displayed or not
function Rover:OnBookmarksToggle( wndHandler, wndControl, eMouseButton )
	-- Determine if we are going to be showing this window or not
	local bShowWnd = self.wndMain:FindChild("BookmarkBtn"):IsChecked()
	if bShowWnd then
		-- If we were previously showing one of the windows hide it
		if self.wndPrevious then
			self.wndPrevious:Show(false)
		end
		-- Record that this window is now showing
		self.wndPrevious = self.wndMain:FindChild("BookmarksWindow")
	else
		-- We closed the window, so no window is showing now
		self.wndPrevious = nil
	end
	-- Set proper shown state
	self.wndMain:FindChild("BookmarksWindow"):Show(bShowWnd)
end

-----------------------------------------------------------------------------------------------
-- Rover Instance
-----------------------------------------------------------------------------------------------
local RoverInst = Rover:new()
RoverInst:Init()


-- These functions can be invoked right from the chat window with /eval
-- EG: /eval SendVarToRover("_G", _G) will show you al the variables in the global namespace

-- iOptions - optional integer or constant:
--   (0) Rover.ADD_ALL - always add the variable, even if strName is repeated
--   (1) Rover.ADD_ONCE - add the variable only once, don't overwrite if strName already exists
--   the default is Rover.ADD_DEFAULT - which adds the variable if the strName is not repeated
function SendVarToRover(strName, var, iOptions)
	RoverInst:AddWatch(strName, var, iOptions)
end

function RemoveVarFromRover(strName)
	RoverInst:RemoveWatch(strName)
end
