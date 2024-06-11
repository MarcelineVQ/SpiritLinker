-- stop loading addon if no superwow
if not SetAutoloot then
  DEFAULT_CHAT_FRAME:AddMessage("[|cff36c948Spirit Linker requires |cffffd200SuperWoW|r to operate.")
  return
end

-- NB: This doens't work, this info isn't available at addon load time, and by the time it is available the addon all exists in memory anyway
-- -- There's no need for a non spirit linker to use this currently
--[[
if true then
  local _,race = UnitRace("player")
  local _,class = UnitClass("player")
  if not (race == "Tauren" and class == "SHAMAN") then
    return
  end
end
--]]

local DEBUG_MODE = false

local color = {
  blue = format("|c%02X%02X%02X%02X", 1, 41,146,255),
  red = format("|c%02X%02X%02X%02X",1, 255, 0, 0),
  green = format("|c%02X%02X%02X%02X",1, 22, 255, 22),
  yellow = format("|c%02X%02X%02X%02X",1, 255, 255, 0),
  orange = format("|c%02X%02X%02X%02X",1, 255, 146, 24),
  red = format("|c%02X%02X%02X%02X",1, 255, 0, 0),
  gray = format("|c%02X%02X%02X%02X",1, 187, 187, 187),
  gold = format("|c%02X%02X%02X%02X",1, 255, 255, 154),
  blizzard = format("|c%02X%02X%02X%02X",1, 180,244,1),
}

local function colorize(msg,color)
  local c = color or ""
  return c..msg..FONT_COLOR_CODE_CLOSE
end

local function showOnOff(setting)
  local b = "d"
  return setting and colorize("On",color.blue) or colorize("Off",color.red)
end

local function sl_print(msg)
  DEFAULT_CHAT_FRAME:AddMessage(msg)
end

local function debug_print(text)
    if DEBUG_MODE == true then DEFAULT_CHAT_FRAME:AddMessage(text) end
end

-------------------------------------------------
-- Table funcs
-------------------------------------------------

local function isempty(t)
  for _ in pairs(t) do
    return false
  end
  return true
end

local function iskey(table,item)
  for k,v in pairs(table) do
    if item == k then
      return true
    end
  end
  return false
end

local function iselem(table,item)
  for k,v in pairs(table) do
    if item == k then
      return true
    end
  end
  return false
end

local function wipe(table)
  for k,_ in pairs(table) do
    table[k] = nil
  end
end

-------------------------------------------------

-- spirt link claims 15y range but it's not, it's about 11.2y, which is basically CheckInteractDistance index 2
local librange = {}

-- Function to calculate distance between two points in 3D space
function librange:distance(x1,y1,z1,x2,y2,z2)
  local dx = x2 - x1
  local dy = y2 - y1
  local dz = z2 - z1
  return math.sqrt(dx^2 + dy^2 + dz^2)
end

function librange:InRange(unit, range, unit2)
  -- Determine the source based on the unit2 parameter
  local source = unit2 or "player"

  -- Early exit if the unit does not exist
  if not UnitExists(unit) then return nil end
  if not UnitCanAssist(unit, source) then return nil end
  if UnitIsCharmed(unit) or UnitIsCharmed(unit2) then return nil end

  local x1, y1, z1 = UnitPosition(source)
  local x2, y2, z2 = UnitPosition(unit)

  -- Check for Tauren race to adjust range
  local raceAdjustment = (UnitRace(source) == "Tauren" or UnitRace(unit) == "Tauren") and 5 or 3

  -- Calculate distance and adjust based on race
  local distance = self:distance(x1, y1, z1, x2, y2, z2)
  local adjustedDistance = distance - raceAdjustment

  -- Return based on the adjusted distance compared to the given range
  return adjustedDistance < range and 1 or nil
end

local linked = {
  target_name = "",
  target_guid = "",
  start = 0,
  nearby = 0,
  healing_way = {stacks = 0, start = 0},
  armor_buff = { ancestral_fortitude = false, inspiration = false }
}

local link_range = 11.2

local frameWidth = 180
local frameHeight = 20
local barWidth = frameWidth --  - 20

local function HexToColors(hex,alpha_first)
  if alpha_first == nil then alpha_first = false end
  
  local len = string.len(hex)

  local ix = len == 6 and 1 or 3

  local red = tonumber(string.sub(hex,ix,ix+1),16) / 255
  local green = tonumber(string.sub(hex,ix+2,ix+3),16) / 255
  local blue = tonumber(string.sub(hex,ix+4,ix+5),16) / 255

  if len == 6 then
    return red,green,blue
  elseif len == 8 then
    local alpha
    if alpha_first then
      alpha = tonumber(string.sub(hex,1,2),16) / 255
      return alpha,red,green,blue
    else
      alpha = tonumber(string.sub(hex,7,8),16) / 255
      return red,green,blue,alpha
    end
  end
end

local durationColor = HexToColors("36c948")

local function ResetBar(self)
  self:SetWidth(barWidth)
  self.timeElapsed = 0
  self:Hide()
end

local function Update(self, elapsed, duration)
  self.timeElapsed = (self.timeElapsed or 0) + elapsed
  if self.timeElapsed >= duration then
      ResetBar(self)
  else
      local newWidth = barWidth * (1 - self.timeElapsed / duration)
      self:SetWidth(newWidth)
  end
end

-- Create the main frame
local linkFrame = CreateFrame("Button", "SpiritLinkFrame", UIParent)
linkFrame:SetWidth(frameWidth)
linkFrame:SetHeight(frameHeight)
linkFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)  -- position it at the center of the parent frame (UIParent)
linkFrame:SetMovable(true)
linkFrame:EnableMouse(true)
linkFrame:RegisterForDrag("LeftButton")
linkFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
linkFrame:SetBackdropColor(0, 0, 0, 0.8)
linkFrame:SetScript("OnDragStart", function () linkFrame:StartMoving() end)
linkFrame:SetScript("OnDragStop", function () linkFrame:StopMovingOrSizing() end)
linkFrame:SetScript("OnClick", function () if linked.target_guid ~= "" then CastSpellByName("Spirit Link",linked.target_guid) end end)
-- linkFrame:SetScript("OnUpdate", function ()
--   local now = GetTime()
--   if now - linked.healing_way.start > 15 then
--     linked.healing_way.stacks = 0
--   end
-- end)

-- Text ----------------------

local linkText = CreateFrame("Frame", nil, linkFrame)
linkText:SetFrameLevel(4)

local targetText = linkText:CreateFontString(nil, "OVERLAY", "GameFontNormal")
targetText:SetPoint("LEFT", linkFrame, "LEFT", 2, 0)
targetText:SetText("Spirit Linker")
targetText:SetFont(targetText:GetFont(), 16)

local nearbyText = linkText:CreateFontString(nil, "OVERLAY", "GameFontNormal")
nearbyText:SetPoint("CENTER", linkFrame, "RIGHT", -10, 0)
nearbyText:SetFont(nearbyText:GetFont(), 16)

--- Bars ---------------------

local armorBar = CreateFrame("Frame", nil, linkFrame)
armorBar:SetWidth(frameHeight*0.8)
armorBar:SetHeight(frameHeight*0.8)
armorBar:SetPoint("RIGHT", nearbyText, "LEFT",-5,0)
armorBar:SetBackdrop({ bgFile = "Interface\\Addons\\SpiritLinker\\tank2" })
armorBar:SetBackdropColor(1,1,1,0.8)
armorBar:SetFrameLevel(3)
armorBar:SetScript("OnUpdate", function ()
  if linked.armor_buff.ancestral_fortitude or linked.armor_buff.inspiration then
    this:Show()
  else
    this:Hide()
  end
end)

local durationBar = CreateFrame("Frame", nil, linkFrame)
durationBar:SetWidth(barWidth)
durationBar:SetHeight(frameHeight)
durationBar:SetPoint("TOPLEFT", linkFrame, "TOPLEFT")
durationBar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
durationBar:SetBackdropColor(durationColor,0.7)
durationBar:SetFrameLevel(2)
durationBar:Hide()
durationBar:SetScript("OnUpdate", function () Update(durationBar,arg1,30) end)

local cooldownBar = CreateFrame("Frame", nil, durationBar)
cooldownBar:SetWidth(barWidth)
cooldownBar:SetHeight(frameHeight*0.15)
cooldownBar:SetPoint("BOTTOMLEFT", linkFrame, "BOTTOMLEFT")
cooldownBar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
cooldownBar:SetBackdropColor(1,0,0,0.6)
cooldownBar:SetFrameLevel(3)
cooldownBar:Hide()
cooldownBar:SetScript("OnUpdate", function () Update(cooldownBar,arg1,20) end)

local hw1Bar = CreateFrame("Frame", nil, linkFrame)
hw1Bar:SetWidth(barWidth/3)
hw1Bar:SetHeight(frameHeight*0.15)
hw1Bar:SetPoint("BOTTOMLEFT", linkFrame, "TOPLEFT")
hw1Bar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
hw1Bar:SetBackdropColor(HexToColors("aaaa00"),0.6)
hw1Bar:SetFrameLevel(3)
hw1Bar:SetScript("OnUpdate", function () if linked.healing_way.stacks > 0 then this:Show() else this:Hide() end end)

local hw2Bar = CreateFrame("Frame", nil, linkFrame)
hw2Bar:SetWidth(barWidth/3)
hw2Bar:SetHeight(frameHeight*0.15)
hw2Bar:SetPoint("LEFT", hw1Bar, "RIGHT")
hw2Bar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
hw2Bar:SetBackdropColor(HexToColors("cccc00"),0.6)
hw2Bar:SetFrameLevel(3)
hw2Bar:SetScript("OnUpdate", function () if linked.healing_way.stacks > 1 then this:Show() else this:Hide() end end)

local hw3Bar = CreateFrame("Frame", nil, linkFrame)
hw3Bar:SetWidth(barWidth/3)
hw3Bar:SetHeight(frameHeight*0.15)
hw3Bar:SetPoint("LEFT", hw2Bar, "RIGHT")
hw3Bar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
hw3Bar:SetBackdropColor(HexToColors("ffff00"),0.6)
hw3Bar:SetFrameLevel(3)
hw3Bar:SetScript("OnUpdate", function () if linked.healing_way.stacks > 2 then this:Show() else this:Hide() end end)


-- cooldownBar:SetScript("OnUpdate", function () Update(cooldownBar,arg1,20) end)

------------------------------

linkFrame:SetScript("OnUpdate", function ()
  linkFrame.timeElapsed = (linkFrame.timeElapsed or 0) + arg1
  if linkFrame.timeElapsed >= 0.5 and linked.target_name ~= "" then
    linkFrame.timeElapsed = 0
    local group_size = max(GetNumRaidMembers(),GetNumPartyMembers())
    local unit_type = GetNumRaidMembers() > 0 and "raid" or "party"
    local count = 0
    -- is the player close
    count = count + (librange:InRange(linked.target_guid,link_range) and 1 or 0)
    -- who else is close
    for i=1,group_size do
      local unit_id = unit_type .. i
      -- ignore self and player, we tested player above
      if UnitName(unit_id) ~= linked.target_name and UnitName(unit_id) ~= UnitName("player") then
        count = count + (librange:InRange(unit_type .. i,link_range,linked.target_guid) and 1 or 0)
      end
    end
    if count == 0 then
      durationBar:SetBackdropColor(1,0,0,0.7)
    else
      durationBar:SetBackdropColor(durationColor,0.7)
    end
    nearbyText:SetText(count)
  end
end)

-- cancaston
local function CanCastOn(unit)
  local _,guid = UnitExists(unit)
  if guid and not UnitIsDead(guid) and LibRange:InRange(guid,40) and UnitCanAssist("player",guid) then
    return true
  end
  return false
end

local LOCAL_RAID_CLASS_COLORS = {
  ["HUNTER"] = { r = 0.67, g = 0.83, b = 0.45, colorStr = "ffabd473" },
  ["WARLOCK"] = { r = 0.58, g = 0.51, b = 0.79, colorStr = "ff9482c9" },
  ["PRIEST"] = { r = 1.0, g = 1.0, b = 1.0, colorStr = "ffffffff" },
  ["PALADIN"] = { r = 0.96, g = 0.55, b = 0.73, colorStr = "fff58cba" },
  ["MAGE"] = { r = 0.41, g = 0.8, b = 0.94, colorStr = "ff69ccf0" },
  ["ROGUE"] = { r = 1.0, g = 0.96, b = 0.41, colorStr = "fffff569" },
  ["DRUID"] = { r = 1.0, g = 0.49, b = 0.04, colorStr = "ffff7d0a" },
  ["SHAMAN"] = { r = 0.0, g = 0.44, b = 0.87, colorStr = "ff0070de" },
  ["WARRIOR"] = { r = 0.78, g = 0.61, b = 0.43, colorStr = "ffc79c6e" },
  ["DEATHKNIGHT"] = { r = 0.77, g = 0.12 , b = 0.23, colorStr = "ffc41f3b" },
  ["MONK"] = { r = 0.0, g = 1.00 , b = 0.59, colorStr = "ff00ff96" },
}

local function Colorize(text,hex)
  return "|c"..hex..text.."|r"
end

local function ColorizeName(unit)
  local _,c = UnitClass(unit)
  -- erroring on someone, someone offline maybe
  local cc = (LOCAL_RAID_CLASS_COLORS[c] and LOCAL_RAID_CLASS_COLORS[c].colorStr) or "ffc0c0c0"
  -- if not cc then cc = ffc0c0c0 end
  return Colorize(UnitName(unit),cc)
end

local function OnEvent()
  if event == "UNIT_CASTEVENT" and arg3 == "CAST" and arg4 == 45500 then
    local _,guid = UnitExists("player")

    -- did someone else cast on our linkee
    -- TODO: this needs testing, I only have one shaman
    if arg1 ~= guid and ((linked.target_name ~= "") and (arg2 == linked.target_name)) then
      linked.start = GetTime()
      linked.expired = false

      ResetBar(durationBar)
      durationBar:Show()
    end

    -- did we cast
    if arg1 == guid then
      linked.target_name = UnitName(arg2)
      linked.target_guid = arg2
      linked.start = GetTime()
      linked.expired = false
      targetText:SetText(linked.target_name)

      ResetBar(durationBar)
      durationBar:Show()
      ResetBar(cooldownBar)
      cooldownBar:Show()
    end
  elseif event == "CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS" or event == "CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFFS" then
    local _, _, name, buff = string.find(arg1, "^(%S+) gains ([%a%s-']+)")
    if name ~= linked.target_name then return end

    buff = string.gsub(buff,"^%s*(.-)%s$","%1")
    debug_print("gain "..name.." "..buff)
    if buff == "Ancestral Fortitude" then
      linked.armor_buff.ancestral_fortitude = true
      armorBar:Show()
    elseif buff == "Inspiration" then
      linked.armor_buff.inspiration = true
      armorBar:Show()
    elseif buff == "Healing Way" then
      linked.healing_way.stacks = (linked.healing_way.stacks > 2) and 3 or linked.healing_way.stacks + 1
      hw1Bar:Show()
      hw2Bar:Show()
      hw3Bar:Show()
    end
  elseif event == "CHAT_MSG_SPELL_AURA_GONE_PARTY" or event == "CHAT_MSG_SPELL_AURA_GONE_OTHER" then
    local _, _, buff, name = string.find(arg1, "^([%a%s-']+) fades from (%a+)")
    if name ~= linked.target_name then return end
    buff = string.gsub(buff,"^%s*(.-)%s$","%1")
    debug_print("lose "..name.." "..buff)
    if buff == "Ancestral Fortitude" then
      linked.armor_buff.ancestral_fortitude = false
    elseif buff == "Inspiration" then
      linked.armor_buff.inspiration = false
    elseif buff == "Healing Way" then
      linked.healing_way.stacks = 0
    end
  elseif event == "PLAYER_ENTERING_WORLD" then
    local _,engClass = UnitClass("player")
    if engClass ~= "SHAMAN" then
      DEFAULT_CHAT_FRAME:AddMessage("|cff36c948Spirit Linker|cffffffff is only useful to the Shaman class, the addon is now set to not load again.|r")
      DisableAddOn("SpiritLinker")
      linkFrame:EnableMouse(false)
      linkFrame:SetScript("OnUpdate", nil)
      linkFrame:SetScript("OnEvent", nil)
      linkFrame:Hide()
    end
  end
end

linkFrame:RegisterEvent("UNIT_CASTEVENT")
linkFrame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS")
linkFrame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFFS")
linkFrame:RegisterEvent("CHAT_MSG_SPELL_AURA_GONE_PARTY")
linkFrame:RegisterEvent("CHAT_MSG_SPELL_AURA_GONE_OTHER")
linkFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
linkFrame:SetScript("OnEvent", OnEvent)
