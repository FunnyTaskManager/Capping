local Capping = Capping
local L = Capping.locale
local format, floor, min, max = string.format, math.floor, math.min, math.max
local profiles = {
    { key = "av", id = 1, area = 401, map = "AlteracValley", name = "Alterac Valley", legacy = "StartAV", capture = 240 },
    { key = "wsg", id = 2, area = 443, map = "WarsongGulch", name = "Warsong Gulch", flags = true, flagRespawn = 23, limit = 900, flagSpells = {23335, 23333}, stackSpell = 318062 },
    { key = "ab", id = 3, area = 461, map = "ArathiBasin", name = "Arathi Basin", capture = 60, rates = {10/11, 10/8, 2, 5, 30} },
    { key = "eots", id = 7, area = 482, map = "NetherstormArena", name = "Eye of the Storm", legacy = "StartEotS", rates = {0.5, 1, 2.5, 5}, flagRespawn = 8 },
    { key = "sa", id = 9, area = 512, map = "StrandoftheAncients", name = "Strand of the Ancients", round = true },
    { key = "ioc", id = 30, area = 540, map = "IsleofConquest", name = "Isle of Conquest", legacy = "StartIoC", capture = 60 },
    { key = "tp", id = 57, area = 932, map = "TwinPeaks", name = "Twin Peaks", flags = true, flagRespawn = 15, limit = 900, flagSpells = {313669, 313670}, pressure = {300, 600} },
    { key = "bfg", id = 18, area = 915, map = "gilneasbattleground2", name = "The Battle for Gilneas", capture = 60, rates = {10/9, 10/3, 30} },
    { key = "sv", id = 31, area = 610, map = "Battleground01", name = "Slavery Valley", capture = 60, boss = true },
    { key = "sm", id = 12, area = 860, map = "STVDiamondMineBG", name = "Silvershard Mines", carts = true, empirical = true },
    { key = "kt", id = 19, area = 916, map = "templeofkotmogu", name = "Temple of Kotmogu", orbs = true, empirical = true },
    { key = "ca", id = 20, area = 917, map = "TempleCity", name = "Temple City of Ala'washte", flags = true, flagRespawn = 10, flagSpells = {311055, 311056}, pressure = {600, 900}, empirical = true, sandstorm = true },
    { key = "avb", id = 58, area = 962, map = "alteracblitz", name = "Alterac Valley Blitz", capture = 90 },
    { key = "abw", id = 59, area = 957, map = "arathibasinwinter", name = "Winter Arathi Basin", capture = 60, rates = {10/12, 10/9, 10/6, 10/3, 30}, blizzard = true, brawl = true },
    { key = "tmf", id = 61, area = 959, name = "The Magnificent Five", flags = true, flagRespawn = 23, limit = 900, flagSpells = {23335, 23333}, stackSpell = 318062, brawl = true },
    { key = "gl", id = 62, area = 960, name = "Gravity Lapse", legacy = "StartEotS", rates = {0.5, 1, 2.5, 5}, flagRespawn = 8, gravity = true, brawl = true },
}
Capping.battlegroundProfiles = profiles
Capping.battlegroundOptions = {}
local byArea, byID, byMap = {}, {}, {}
for _, profile in ipairs(profiles) do
    byArea[profile.area], byID[profile.id] = profile, profile
    if profile.map then byMap[profile.map] = profile end
    if profile.id ~= 1 and profile.id ~= 2 and profile.id ~= 3 and profile.id ~= 7 and profile.id ~= 30 then
        table.insert(Capping.battlegroundOptions, profile)
    end
end

local state, panel, eventFrame, BattleStarted
local buttons = {}
local icon = "Interface\\Icons\\INV_Misc_PocketWatch_01"
local flagIcon = "Interface\\Icons\\INV_BannerPVP_01"
local orbSpells = {309221, 309219, 309220, 309222}
local orbNames = {"Purple orb", "Orange orb", "Green orb", "Blue orb"}
local cartNames = {"Water cart", "Middle cart", "Lava cart"}
local factionNames = { _G.FACTION_ALLIANCE or "Alliance", _G.FACTION_HORDE or "Horde" }
local colors = { "alliance", "horde" }

local function Clean(text)
    text = (text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return (text:gsub("|H.-|h(.-)|h", "%1"))
end

local function Numbers(text)
    local numbers = {}
    for value in Clean(text):gmatch("%d+") do numbers[#numbers + 1] = tonumber(value) end
    return numbers
end

local function Faction(unit)
    if C_Unit and C_Unit.GetFactionByDebuff then
        local faction = C_Unit.GetFactionByDebuff(unit)
        if faction == 1 or faction == 0 then return faction == 1 and 1 or 2 end
    end
    return UnitFactionGroup(unit) == "Alliance" and 1 or 2
end

local function NewState(profile)
    return { profile = profile, nodes = {}, holders = {}, scores = {}, samples = {{}, {}}, carts = {}, orbs = {}, bars = {}, ticks = {}, knownFlags = {} }
end

function Capping:InitBattlegroundDefaults()
    for _, profile in ipairs(profiles) do
        if self.db[profile.key] == nil then self.db[profile.key] = true end
    end
    if self.db.arena == nil then self.db.arena = true end
end

function Capping:GetBattlegroundProfile()
    local area = GetCurrentMapAreaID and GetCurrentMapAreaID()
    if byArea[area] then return byArea[area] end
    if C_BattlefieldQueue and C_BattlefieldQueue.GetActiveBattlegroundTypeID then
        local profile = byID[C_BattlefieldQueue.GetActiveBattlegroundTypeID()]
        if profile then return profile end
    end
    return byMap[GetMapInfo()]
end

local function Start(label, duration, remaining, color, texture)
    if not state or not remaining or remaining <= 0 or duration <= 0 then return end
    state.bars[label] = true
    Capping:StartBar(label, duration, remaining, texture or icon, color or "info2")
end

local function Stop(label)
    Capping:StopBar(label)
    if state then state.bars[label] = nil end
end

local function Sync(label, duration, remaining, color)
    if not remaining or remaining <= 0 then Stop(label) return end
    local bar = Capping:GetBar(label)
    if not bar or not bar:IsShown() or math.abs(bar.endtime - GetTime() - remaining) > 1.5 then
        Start(label, duration, remaining, color)
    end
end

local function SetInfo(lines)
    if panel then
        panel.text:SetText(table.concat(lines, "\n"))
        panel:SetHeight(max(16, #lines * 15))
    end
end

local function ApplyTargets()
    for _, button in ipairs(buttons) do
        local holder = state and state.holders[button.index]
        button:SetAttribute("macrotext", holder and holder.name and "/targetexact "..holder.name or "")
        button:SetAlpha(1)
        if holder and holder.name then button:Show() else button:Hide() end
    end
end

local function CreatePanel()
    if panel then return end
    panel = CreateFrame("Frame", nil, UIParent)
    panel:SetWidth(270)
    panel:SetHeight(16)
    panel:SetPoint("TOPLEFT", Capping, "TOPRIGHT", 12, 0)
    panel.text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.text:SetPoint("TOPLEFT")
    panel.text:SetJustifyH("LEFT")
    for i = 1, 4 do
        local button = Capping:CreateCarrierButton("CappingCarrier"..i, 270, 18, function(this)
            if not state or not IsControlKeyDown() then return end
            local holder = state.holders[this.index]
            if holder and holder.name then
                SendChatMessage(format(L["Flag carrier: %s"], holder.name), "BATTLEGROUND")
            end
        end)
        button.index = i
        button:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 0, -(i - 1) * 18 - 4)
        button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        button.text:SetAllPoints()
        button.text:SetJustifyH("LEFT")
        button:Hide()
        buttons[i] = button
    end
end

local function Holder(index, name, faction)
    if not state then return end
    name = name and Clean(name)
    local previous = state.holders[index]
    if previous and previous.name == name and previous.faction == faction then return end
    state.holders[index] = name and {name = name, faction = faction, observed = GetTime()} or nil
    if buttons[index] then
        buttons[index].car = name
        buttons[index].faction = faction == 1 and "Alliance" or "Horde"
        buttons[index]:SetAlpha(InCombatLockdown() and 0.6 or 1)
        buttons[index].text:SetText(name or "")
    end
    Capping:CheckCombat(ApplyTargets)
end

local nodeTextures = {
    [4] = {"alliance", true}, [14] = {"horde", true}, [15] = {"alliance"}, [13] = {"horde"},
    [9] = {"alliance", true}, [12] = {"horde", true}, [11] = {"alliance"}, [10] = {"horde"},
    [17] = {"alliance", true}, [19] = {"horde", true}, [18] = {"alliance"}, [20] = {"horde"},
    [22] = {"alliance", true}, [24] = {"horde", true}, [23] = {"alliance"}, [25] = {"horde"},
    [27] = {"alliance", true}, [29] = {"horde", true}, [28] = {"alliance"}, [30] = {"horde"},
    [32] = {"alliance", true}, [34] = {"horde", true}, [33] = {"alliance"}, [35] = {"horde"},
    [37] = {"alliance", true}, [39] = {"horde", true}, [38] = {"alliance"}, [40] = {"horde"},
    [137] = {"alliance", true}, [139] = {"horde", true}, [136] = {"alliance"}, [138] = {"horde"},
    [142] = {"alliance", true}, [144] = {"horde", true}, [141] = {"alliance"}, [143] = {"horde"},
    [147] = {"alliance", true}, [149] = {"horde", true}, [146] = {"alliance"}, [148] = {"horde"},
    [152] = {"alliance", true}, [154] = {"horde", true}, [151] = {"alliance"}, [153] = {"horde"},
}
local gateTextures = {}
for _, intact in ipairs({77, 80, 102, 105, 108}) do
    gateTextures[intact], gateTextures[intact + 1], gateTextures[intact + 2] = "Intact", "Damaged", "Destroyed"
end

local function ScanNodes(lines)
    if not state then return end
    local profile = state.profile
    for i = 1, GetNumMapLandmarks() do
        local name, _, texture = GetMapLandmarkInfo(i)
        if name then
            if profile.capture then
                local old = state.nodes[name]
                local current = nodeTextures[texture]
                -- A contested POI has no remaining-time field; only an observed transition can start a capture timer.
                if old and old ~= texture then
                    if current and current[2] then Start(name, profile.capture, profile.capture, current[1])
                    else Stop(name) end
                end
                state.nodes[name] = texture
            elseif profile.round and gateTextures[texture] then
                lines[#lines + 1] = name..": "..L[gateTextures[texture]]
            end
        end
    end
end

local function ReadScores(lines)
    if not state then return end
    local profile, scores = state.profile, {}
    local timerFound, bossFound = false, false
    for i = 1, GetNumWorldStateUI() do
        local uiType, _, text, texture, _, _, dynamicTooltip, extended = GetWorldStateUIInfo(i)
        if uiType == 0 and extended ~= "CAPTUREPOINT" and text and text ~= "" then
            local values = Numbers(text)
            local faction = texture and (texture:find("Alliance") and 1 or texture:find("Horde") and 2)
            if faction and #values > 0 then
                if profile.boss and #values == 2 then scores[faction] = {value = values[1], bases = values[2]}
                elseif #values >= 3 then scores[faction] = {bases = values[1], value = values[2], maximum = values[3]}
                elseif #values == 2 then scores[faction] = {value = values[1], maximum = values[2]}
                else scores[faction] = {value = values[1]} end
                if profile.flags and dynamicTooltip and dynamicTooltip ~= "" then
                    local name = Clean(dynamicTooltip):match("^([^%s:]+)$")
                    if name then Holder(faction == 1 and 2 or 1, name, faction == 1 and 2 or 1) end
                end
            elseif (not texture or texture == "") and #values > 0 and (profile.round or profile.limit) then
                local remaining = values[1] * 60 + (values[2] or 0)
                local label = L[profile.round and "Round ends" or "Battle ends"]
                -- WSG exposes whole minutes; retain its last boundary instead of restarting the bar on every event.
                if (not state.started or profile.round) and (#values > 1 or profile.round or state.ticks[label] ~= remaining) then
                    Sync(label, profile.limit or 600, remaining)
                    state.ticks[label] = remaining
                    local bar = Capping:GetBar(label)
                    if #values == 1 and bar then bar.displaytext:SetText("~ "..label) end
                end
                timerFound = true
            elseif profile.boss and #values == 2 and texture and texture:find("SkullBones") then
                Sync(L["Warden Gedelborn"], 300, values[1] * 60 + values[2])
                bossFound = true
            end
        end
    end
    if profile.boss and not bossFound then Stop(L["Warden Gedelborn"]) end
    if profile.round and not timerFound then Stop(L["Round ends"]) end
    if not scores[1] or not scores[2] then return end
    state.scores = scores
    lines[#lines + 1] = format(L["Score: %d - %d"], scores[1].value, scores[2].value)
    if scores[1].bases and scores[2].bases then
        lines[#lines + 1] = format(L["Bases: %d - %d"], scores[1].bases, scores[2].bases)
    end
    if not profile.rates and not profile.empirical then return end
    local rates, now = {}, GetTime()
    for faction = 1, 2 do
        local score = scores[faction]
        local samples = state.samples[faction]
        if profile.rates then
            rates[faction] = profile.rates[score.bases or 0] or 0
        else
            if #samples == 0 or now - samples[#samples].time >= 5 then samples[#samples + 1] = {time = now, value = score.value} end
            while #samples > 1 and now - samples[1].time > 30 do table.remove(samples, 1) end
            local first = samples[1]
            rates[faction] = now - first.time >= 10 and max(0, score.value - first.value) / (now - first.time) or 0
        end
    end
    local finish = {}
    for faction = 1, 2 do
        finish[faction] = rates[faction] > 0 and scores[faction].maximum and (scores[faction].maximum - scores[faction].value) / rates[faction] or math.huge
    end
    local winner = finish[1] <= finish[2] and 1 or 2
    local remain = finish[winner]
    if remain == math.huge or remain <= 0 then Stop("EstFinal") return end
    local loser = winner == 1 and 2 or 1
    local result = {}
    result[winner] = scores[winner].maximum
    result[loser] = min(scores[loser].maximum or result[winner], floor(scores[loser].value + rates[loser] * remain))
    local label = format(L["Estimated finish: %d - %d"], result[1], result[2])
    state.bars.EstFinal = true
    local bar = Capping:GetBar("EstFinal")
    if not bar or not bar:IsShown() or math.abs(bar.endtime - now - remain) > 1.5 or bar.color ~= colors[winner] then
        Capping:StartBar("EstFinal", remain, remain, icon, colors[winner], nil, nil, label)
    else bar.displaytext:SetText(label) end
end

local function ScanHolders()
    if not state or not (state.profile.flags or state.profile.orbs) then return end
    local spells = state.profile.orbs and orbSpells or state.profile.flagSpells
    local units = {"player", "target", "focus", "mouseover"}
    local confirmed, missing = {}, {}
    for i = 1, GetNumRaidMembers() do
        units[#units + 1], units[#units + 2] = "raid"..i, "raid"..i.."target"
    end
    for _, unit in ipairs(units) do
        if UnitExists(unit) then
            local visible = UnitIsVisible(unit) and UnitIsConnected(unit)
            local carried, complete = {}, false
            for aura = 1, 40 do
                local name, _, _, _, _, _, _, _, _, _, spellID = UnitBuff(unit, aura)
                if not name then complete = true break end
                for index, spell in ipairs(spells) do
                    if spellID == spell then
                        local faction = Faction(unit)
                        local holderIndex = state.profile.orbs and index or (index == 1 and 2 or 1)
                        Holder(holderIndex, UnitName(unit), faction)
                        carried[holderIndex], confirmed[holderIndex] = true, true
                        if state.profile.orbs then state.orbs[index] = faction end
                    end
                end
            end
            for index, holder in pairs(state.holders) do
                if visible and UnitName(unit) == holder.name and UnitHealthMax(unit) > 0 then
                    -- Allow pickup messages to arrive before the carrier aura reaches the client.
                    if complete and not carried[index] and GetTime() - holder.observed >= 2 then missing[index] = true end
                    holder.health, holder.seen = floor(100 * UnitHealth(unit) / UnitHealthMax(unit)), GetTime()
                    if state.profile.stackSpell then
                        holder.stacks = nil
                        for aura = 1, 40 do
                            local name, _, _, count, _, _, _, _, _, _, spellID = UnitDebuff(unit, aura)
                            if not name then break end
                            if spellID == state.profile.stackSpell then holder.stacks = count break end
                        end
                    end
                end
            end
        end
    end
    for index in pairs(missing) do
        if not confirmed[index] then
            Holder(index)
            if state.profile.orbs then state.orbs[index] = nil end
        end
    end
    for i, button in ipairs(buttons) do
        local holder = state.holders[i]
        if holder then
            local title = state.profile.orbs and L[orbNames[i]] or factionNames[holder.faction or i]
            local hp = holder.seen and GetTime() - holder.seen <= 6 and format("%d%%", holder.health) or "??%"
            button.text:SetText(title..": "..holder.name.."  "..hp..(holder.stacks and "  x"..holder.stacks or ""))
        end
    end
end

local function Update()
    if not state then return end
    if GetBattlefieldWinner() ~= nil then Capping:ResetAll() return end
    local lines = {L[state.profile.name] or state.profile.name}
    ReadScores(lines)
    ScanNodes(lines)
    ScanHolders()
    if state.profile.carts then
        for i = 1, 3 do lines[#lines + 1] = L[cartNames[i]]..": "..(state.carts[i] and factionNames[state.carts[i]] or L["Neutral"]) end
        if state.tracks then lines[#lines + 1] = state.tracks end
    elseif state.profile.orbs then
        if GetBattlefieldVehicleInfo then
            for i = 1, 4 do
                local _, _, name, _, vehicleType, _, _, _, faction = GetBattlefieldVehicleInfo(i)
                local index = vehicleType and (vehicleType:find("Purple") and 1 or vehicleType:find("Orange") and 2 or vehicleType:find("Green") and 3 or vehicleType:find("Blue") and 4)
                if index and name and faction ~= nil then
                    local team = faction == 1 and 1 or 2
                    Holder(index, name, team)
                    state.orbs[index] = team
                end
            end
        end
        for i = 1, 4 do
            lines[#lines + 1] = L[orbNames[i]]..": "..(state.orbs[i] and factionNames[state.orbs[i]] or L["Available"])
        end
    end
    SetInfo(lines)
end

local function Cycle(label, period, now)
    local remaining = period - now % period
    Sync(L[label], period, remaining)
end

local function UpdateCycles()
    if not state then return end
    if state.countdownEnd and GetTime() >= state.countdownEnd then BattleStarted() end
    if not state or not state.started then return end
    local elapsed, profile = GetTime() - state.started, state.profile
    if profile.limit then
        Sync(L["Battle ends"], profile.limit, profile.limit - elapsed)
        local bar = Capping:GetBar(L["Battle ends"])
        if bar then bar.displaytext:SetText(L["Battle ends"]) end
    end
    if profile.gravity then Cycle("Next gravity lapse", 60, elapsed - (state.gravityOffset or 0)) end
    if profile.blizzard then
        local cycle = elapsed % 450
        Sync(L[cycle < 300 and "Blizzard begins" or "Blizzard ends"], cycle < 300 and 300 or 150, (cycle < 300 and 300 or 450) - cycle)
        Stop(L[cycle < 300 and "Blizzard ends" or "Blizzard begins"])
    end
    if profile.sandstorm and not state.stormObserved then
        local cycle = elapsed % 600
        local label, remaining, duration
        if cycle < 420 then label, remaining, duration = "Sandstorm begins", 420 - cycle, 420
        elseif cycle < 480 then label, remaining, duration = "Sandstorm strengthens", 480 - cycle, 60
        elseif cycle < 540 then label, remaining, duration = "Sandstorm peaks", 540 - cycle, 60
        else label, remaining, duration = "Sandstorm ends", 600 - cycle, 60 end
        for _, other in ipairs({"Sandstorm begins", "Sandstorm strengthens", "Sandstorm peaks", "Sandstorm ends"}) do
            if other ~= label then Stop(L[other]) end
        end
        Sync(L[label], duration, remaining)
    end
end

BattleStarted = function()
    if not state or state.started then return end
    state.started = state.countdownEnd and min(state.countdownEnd, GetTime()) or GetTime()
    state.countdownEnd = nil
    Stop(L["Battle Begins"])
    if state.profile.boss then Start(L["Bosses advance"], 300, 300) end
    if state.profile.arena then
        local spell, _, texture = GetSpellInfo(34709)
        if spell then Start(spell, 90, max(0, 90 - (GetTime() - state.started)), "info2", texture) end
    end
    UpdateCycles()
end

local function StartCountdown(timerType, remaining, duration)
    if not state or (timerType ~= 0 and timerType ~= 1 and timerType ~= 4) or not remaining or remaining <= 0 then return end
    state.started = nil
    state.countdownEnd = GetTime() + remaining
    state.bars[L["Battle Begins"]] = true
    Capping:StartBar(L["Battle Begins"], duration or remaining, remaining, icon, "info2", nil, nil, nil, BattleStarted)
end

local function FlagMessage(text)
    if not state or not state.profile.flags then return end
    local owner = (text:find("Альянса", 1, true) or text:find("Alliance", 1, true)) and 1 or (text:find("Орды", 1, true) or text:find("Horde", 1, true)) and 2
    if not owner then
        if text:find("Флаги возвращены", 1, true) or text:find("flags are now placed", 1, true) then
            Holder(1) Holder(2)
            state.knownFlags, state.pressureStarted = {}, nil
            Stop(L["Focused Assault"]) Stop(L["Brutal Assault"])
            for owner = 1, 2 do
                Stop(format(L["Flag returns: %s"], factionNames[owner]))
                Stop(format(L["Flag respawns: %s"], factionNames[owner]))
            end
        end
        return
    end
    local faction = owner == 1 and 2 or 1
    local name = text:match("^(.+) несет флаг") or text:match("^Флаг Альянса у (.+)!") or text:match("was picked up by (.+)!")
    if state.profile.sandstorm then name = name or text:match("^(.+) захватывает флаг") or text:match("^(.+) has taken the .+ flag!") end
    local returning = format(L["Flag returns: %s"], factionNames[owner])
    local respawning = format(L["Flag respawns: %s"], factionNames[owner])
    if name then
        name = name:gsub("^|3%-1%((.-)%)$", "%1")
        Holder(faction, name, faction)
        Stop(returning) Stop(respawning)
        state.knownFlags[owner] = true
    elseif text:find("роняет", 1, true) or text:find("потерян", 1, true) or text:find("dropped", 1, true) then
        Holder(faction)
        Start(returning, 10, 10, colors[owner], flagIcon)
    elseif text:find("захватывает", 1, true) or text:find("захватил", 1, true) or text:find("захватила", 1, true) or text:find("captured", 1, true) then
        Holder(faction)
        state.knownFlags[owner] = false
        Stop(returning)
        Start(respawning, state.profile.flagRespawn, state.profile.flagRespawn, colors[owner], flagIcon)
    elseif text:find("возвращ", 1, true) or text:find("вернул", 1, true) or text:find("вернула", 1, true) or text:find("returned", 1, true) or text:find("reset", 1, true) then
        Holder(faction)
        state.knownFlags[owner] = false
        Stop(returning) Stop(respawning)
    end
    if state.profile.pressure then
        if state.knownFlags[1] and state.knownFlags[2] then
            if not state.pressureStarted then
                state.pressureStarted = true
                Start(L["Focused Assault"], state.profile.pressure[1], state.profile.pressure[1])
                Start(L["Brutal Assault"], state.profile.pressure[2], state.profile.pressure[2])
            end
        else
            state.pressureStarted = nil
            Stop(L["Focused Assault"]) Stop(L["Brutal Assault"])
        end
    end
end

local function OrbMessage(text, faction)
    if not state or not state.profile.orbs then return end
    local patterns = {{"фиолет", "Purple"}, {"оранж", "Orange"}, {"зелен", "Green"}, {"син", "Blue"}}
    local lower = text:gsub("ё", "е"):gsub("Ё", "Е"):gsub("Фиолет", "фиолет"):gsub("Оранж", "оранж"):gsub("Зелен", "зелен"):gsub("Син", "син")
    for i, words in ipairs(patterns) do
        if lower:find(words[1], 1, true) or text:find(words[2], 1, true) then
            local name = text:match("^(.+) захватывает") or text:match("^(.+) has taken")
            Holder(i, name, faction)
            state.orbs[i] = name and faction or nil
        end
    end
end

local function Message(event, message)
    if not state then return end
    local text = Clean(message)
    FlagMessage(text)
    OrbMessage(text, event == "CHAT_MSG_BG_SYSTEM_ALLIANCE" and 1 or 2)
    if event == "CHAT_MSG_BG_SYSTEM_NEUTRAL" then
        if text:find("Да начнется битва", 1, true) or text:find("Let the battle begin", 1, true) or text:find("has begun", 1, true) or text:find("началось", 1, true) or text:find("началась", 1, true) then BattleStarted() end
        if state.profile.boss and (text:find("появится через 1 минуту", 1, true) or text:find("appear in 1 minute", 1, true)) then Sync(L["Warden Gedelborn"], 300, 60) end
        if state.profile.sandstorm then
            if text:find("буря начинается", 1, true) or text:find("sandstorm has begun", 1, true) then
                state.stormObserved = true
                Stop(L["Sandstorm begins"])
                Start(L["Sandstorm strengthens"], 60, 60)
                Start(L["Sandstorm peaks"], 120, 120)
                Start(L["Sandstorm ends"], 180, 180)
            elseif text:find("достигла своего пика", 1, true) or text:find("reaches it's peak", 1, true) then
                Stop(L["Sandstorm strengthens"]) Stop(L["Sandstorm peaks"])
                Sync(L["Sandstorm ends"], 60, 60)
            elseif text:find("буря окончена", 1, true) or text:find("sandstorm has now ended", 1, true) then
                Stop(L["Sandstorm ends"])
                Start(L["Sandstorm begins"], 420, 420)
            end
        end
    end
end

local function ServerMessage(prefix, message, channel, sender)
    if not state or channel ~= "UNKNOWN" or sender ~= UnitName("player") then return end
    if prefix == "ASMSG_EVENT_START_TIMER" then
        local remaining, duration = message:match("^(%d+):(%d+)")
        if remaining then StartCountdown(0, tonumber(remaining) / 1000, tonumber(duration) / 1000) end
    elseif prefix == "ASMSG_BG_SM_CART_STATES" and state.profile.carts then
        for entry, visual in message:gmatch("(%d+):(%d+)") do
            local index = tonumber(entry) - 900199
            if index >= 1 and index <= 3 then state.carts[index] = visual == "7" and 1 or visual == "6" and 2 or nil end
        end
    elseif prefix == "ASMSG_BG_SM_TRACK_STATES" and state.profile.carts then
        local east, north = message:match("^([01]):([01])$")
        if east then state.tracks = format(L["Eastern track: %s; Northern track: %s"], L[east == "1" and "Right" or "Left"], L[north == "1" and "Right" or "Left"]) end
    elseif prefix == "ASMSG_BG_KT_ORB_STATE" and state.profile.orbs then
        local index, faction = message:match("^(%d+),(%-?%d+)$")
        index, faction = tonumber(index), tonumber(faction)
        if index and index >= 1 and index <= 4 then
            state.orbs[index] = faction == 0 and 1 or faction == 1 and 2 or nil
            if faction == -1 then Holder(index) end
        end
    end
end

local function CombatLog(...)
    if not state then return end
    local args = {...}
    if #args == 0 and CombatLogGetCurrentEventInfo then args = {CombatLogGetCurrentEventInfo()} end
    local modern = type(args[3]) == "boolean"
    local event, destGUID = args[2], args[modern and 8 or 6]
    local spell = args[modern and 12 or 9]
    if state.profile.carts and event == "UNIT_DIED" and destGUID then
        local entry = tonumber(destGUID:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")) or tonumber(destGUID:sub(7, 12), 16)
        local index = entry and entry - 900199
        if index and index >= 1 and index <= 3 then Start(format(L["Cart respawns: %s"], L[cartNames[index]]), 10, 10) end
    elseif state.profile.gravity and (event == "SPELL_AURA_APPLIED" or event == "SPELL_CAST_SUCCESS") and (spell == 319091 or spell == 319092) then
        if not state.lastGravity or GetTime() - state.lastGravity > 5 then
            state.lastGravity = GetTime()
            if not state.started then state.started = GetTime() end
            state.gravityOffset = GetTime() - state.started
            Sync(L["Next gravity lapse"], 60, 60)
        end
    end
end

local function EnableEvents()
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", function(_, event, ...)
            if event == "CHAT_MSG_ADDON" then ServerMessage(...)
            elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then CombatLog(...)
            elseif event == "START_TIMER" then StartCountdown(...)
            elseif event == "WORLD_MAP_UPDATE" or event == "UPDATE_WORLD_STATES" or event == "UPDATE_BATTLEFIELD_SCORE" then Update()
            elseif event == "STOP_TIMER_OF_TYPE" then
                local timerType = ...
                if timerType == 0 or timerType == 1 or timerType == 4 then
                    if state and state.countdownEnd and state.countdownEnd <= GetTime() + 1 then BattleStarted()
                    elseif state then state.countdownEnd = nil end
                    Stop(L["Battle Begins"])
                end
            elseif event:find("CHAT_MSG_", 1, true) then Message(event, ...)
            end
        end)
        eventFrame:SetScript("OnUpdate", function(this, elapsed)
            this.elapsed = (this.elapsed or 0) + elapsed
            if this.elapsed < 1 then return end
            this.elapsed = 0
            Update()
            UpdateCycles()
        end)
    end
    for _, event in ipairs({"CHAT_MSG_BG_SYSTEM_NEUTRAL", "CHAT_MSG_BG_SYSTEM_ALLIANCE", "CHAT_MSG_BG_SYSTEM_HORDE", "CHAT_MSG_ADDON", "COMBAT_LOG_EVENT_UNFILTERED", "UPDATE_WORLD_STATES", "WORLD_MAP_UPDATE", "UPDATE_BATTLEFIELD_SCORE"}) do eventFrame:RegisterEvent(event) end
    if eventFrame.RegisterCustomEvent then
        eventFrame:RegisterCustomEvent("START_TIMER")
        eventFrame:RegisterCustomEvent("STOP_TIMER_OF_TYPE")
    end
    eventFrame:Show()
    Capping:CheckCombat(function()
        if not state then return end
        CreatePanel()
        panel:Show()
        ApplyTargets()
        Update()
    end)
    if C_GlobalStorage and C_GlobalStorage.GetVar then
        local timers = C_GlobalStorage.GetVar("WORLD_STATE_TIMERS")
        if timers then
            for _, timerType in ipairs({0, 1, 4}) do
                local timer = timers[timerType]
                if timer and (not timer.guidDependent or timer.guid == UnitGUID("player")) then
                    local instanceID, instanceType = GetInstanceID()
                    if not timer.mapDependent or (timer.instanceID == instanceID and timer.instanceType == instanceType) then
                        StartCountdown(timerType, timer.timestamp + timer.timeRemaining - GetTime(), timer.totalTime)
                    end
                end
            end
        end
    end
    Update()
end

function Capping:ResetBattlegroundProfile()
    local old = state
    state, self.bgprofile = nil, nil
    if eventFrame then
        eventFrame:UnregisterAllEvents()
        if eventFrame.UnregisterCustomEvent then
            eventFrame:UnregisterCustomEvent("START_TIMER")
            eventFrame:UnregisterCustomEvent("STOP_TIMER_OF_TYPE")
        end
        eventFrame:Hide()
    end
    if old then for label in pairs(old.bars) do self:StopBar(label) end end
    if panel then panel:Hide() end
    self:CheckCombat(ApplyTargets)
end

function Capping:StartBattlegroundProfile()
    local profile = self:GetBattlegroundProfile()
    self.bgprofile = profile
    if not profile or not self.db[profile.key] then return end
    state = NewState(profile)
    if profile.legacy then
        local current = state
        self:CheckCombat(function()
            if state == current then self[profile.legacy](self) end
        end)
    end
    EnableEvents()
end

function Capping:StartArenaProfile()
    if not self.db.arena then return end
    state = NewState({name = GetRealZoneText() or "Arena", arena = true})
    EnableEvents()
end
