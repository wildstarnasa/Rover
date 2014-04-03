local sAddonVersion = "fork-22"

-- https://forums.wildstar-online.com/forums/index.php?/topic/15859-addon-introducing-rover/?p=161111
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
		table.sort(keys)
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
-- Client Lua Script for Rover
-- Copyright (c) NCsoft. All rights reserved
-----------------------------------------------------------------------------------------------
 
require "Window"
 
-----------------------------------------------------------------------------------------------
-- Rover Module Definition
-----------------------------------------------------------------------------------------------
local Rover = {}

Rover.ADD_ALL = 0
Rover.ADD_ONCE = 1
Rover.ADD_DEFAULT = 2
 
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
local kStrOriginalIndex = "original__index"
local kStrNodeIndex = "tree__node"
local kStrDetailed = "detailed__data"

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
-- Rover OnLoad
-----------------------------------------------------------------------------------------------
function Rover:OnLoad()
    -- load our form file
	self.xmlDoc = XmlDoc.CreateFromFile("Rover.xml")
	-- Register the callback for when the xml is finished loading
	self.xmlDoc:RegisterCallback("OnDocumentLoaded", self)
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
	self.xmlDoc = nil
		
	-- save some windows for later
	self.wndTree = self.wndMain:FindChild("Variables")
	self.wndRemoveBtn = self.wndMain:FindChild("s_Column1"):FindChild("RemoveVar")
	self.wndEvtTree = self.wndMain:FindChild("EventsList")
	self.wndTranscriptTree = self.wndMain:FindChild("TranscriptsList")
	self.wndParametersDialog = self.wndMain:FindChild("ParametersDialog")
	self.wndWatchDialog = self.wndMain:FindChild("WatchDialog")

	-- more initialization here
	-- Register handlers for events, slash commands and timer, etc.
	-- e.g. Apollo.RegisterEventHandler("KeyDown", "OnKeyDown", self)
	Apollo.RegisterSlashCommand("rover", "OnRoverOn", self)

	self.wndTree:SetColumnWidth(eRoverColumns.VarName, 200)
	self.wndTree:SetColumnWidth(eRoverColumns.Type, 150)
	self.wndTree:SetColumnWidth(eRoverColumns.Value, 300)
	self.wndTree:SetColumnWidth(eRoverColumns.LastUpdate, 100)

	self.tMonitoredEvents = {}
	self.tTranscripted = {}

	-- Event Handlers
	Apollo.RegisterEventHandler("SendVarToRover", "AddWatch", self)
	Apollo.RegisterEventHandler("RemoveVarFromRover", "RemoveWatch", self)

	-- Timers
	Apollo.RegisterTimerHandler("Rover_ModifierAddCheck", "OnModifierAddCheck", self)
		
	for sVarName, varData in pairs(self.tPreInitData) do
		if varData == self.sSuperSecretNilReplacement then
			self:AddWatch(sVarName, nil)
		else
			self:AddWatch(sVarName, varData)
		end
		self.tPreInitData[sVarName] = nil
	end
		
	self.bIsInitialized = true
end

-----------------------------------------------------------------------------------------------
-- Rover Functions
-----------------------------------------------------------------------------------------------
-- Define general functions here

-- on SlashCommand "/rover"
function Rover:OnRoverOn()
	self.wndMain:Show(true) -- show the window
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
	local strTime = string.format("%d:%02d:%02d %s", nHour, tTime.nMinute, tTime.nSecond, strAMPM)
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
		local strLabel = string.format("s_Column%d", nLabelNumber)
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
	
	self.wndTree:SetNodeText(hNewNode, eRoverColumns.Value, tostring(var))
	self:UpdateTimeStamp(hNewNode)
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
	if type(var) ~= "function" then
		return
	end
	
	local hParent = self.wndTree:GetParentNode(hNode)

	if Apollo.IsShiftKeyDown() then
		self.wndParametersDialog:SetData(hNode)
		self.wndParametersDialog:Show(true)
		self.wndParametersDialog:FindChild("IncludeSelfBtn"):SetCheck(self.wndTree:GetNodeText(hParent) == 'metatable')
		self.wndParametersDialog:FindChild("ParameterInput"):SetFocus()
		return
	end

	self.wndTree:DeleteChildren(hNode)
	
	self:AddCallResult(hNode, pcall(function()
		if self.wndTree:GetNodeText(hParent) == 'metatable' then
			return var(self.wndTree:GetNodeData(self.wndTree:GetParentNode(hParent)))
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
		self.tManagedVars[self.wndTree:GetNodeText(hNode, eRoverColumns.VarName)] = nil
		self.wndTree:DeleteNode(hNode)
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
	Apollo.CreateTimer("Rover_ModifierAddCheck", 0.1, true)
end

function Rover:DisableModifierTimer()
	Apollo.CreateTimer("Rover_ModifierAddCheck", 1, false)
	Apollo.StopTimer("Rover_ModifierAddCheck")
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

function Rover:BuildMonitorFunc(eventName)
	-- Build a string to return the needed function, the function has a local variable with the event name.
	--	This local variable is then added to the variable list along with all arguments to the event.  A RoverID (RID) is generated and passed as well.
	--	This is needed because loadstring generates a function that accepts no arguments, which is not what we need, we need a function that accepts
	--	arguments.  So we make a function that accepts no arguments that will return the function we actually want.  Sorry this isn't as clear as
	--	I'd like but not sure of a better way to phrase this.  This whole rigamarole is needed because there is no way to determine the name
	--	of a fired event.  Bitwise is contemplating adding an API call to get the event name, if this happens then the need for this goes away
	--	and the event handler can be the same for all monitored events.
	local funcStr = "return (function (self, ...) local eName = 'Event: " .. eventName .. "' self:AddWatch(eName, arg, 0) end)"

	-- Convert this string into a function
	local loadedFunc = loadstring(funcStr)
	-- Since this function actually returns the function we want, we return the function that the function we made made ... clear no?
	return loadedFunc()
end

-- Adds Event Monitoring for specified event
function Rover:OnAddEventMonitor(eventName)
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
	Rover[handlerName] = self:BuildMonitorFunc(eventName)
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
			self:AddWatch(string.format("%s%s%s (#%d)", strAddonName, strObjType, key, nCount), retVal, Rover.ADD_ONCE)
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
			self:AddWatch(string.format("%s%s%s", strAddonName, strObjType, key), 'Calls: ' .. tRover.tTranscripted[strAddonName][key], Rover.ADD_DEFAULT)
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
	
	-- TODO: Switch back to Icons once the crash bug is fixed =)
	if self.tTranscripted[strAddonName][kStrDetailed] then
		wndControl:SetNodeImage(hSelected, "CRB_Basekit:kitIcon_Holo_HazardObserver")
	else
		wndControl:SetNodeImage(hSelected, "")
	end
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