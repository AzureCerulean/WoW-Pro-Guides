-----------------------------------
--      WoWPro.Recorder.lua      --
-----------------------------------

local L = WoWPro_Locale
local config = LibStub("AceConfig-3.0")
local dialog = LibStub("AceConfigDialog-3.0")

WoWPro.Recorder = WoWPro:NewModule("Recorder")
WoWPro:Embed(WoWPro.Recorder)
WoWPro.Recorder.stepInfo = {}
WoWPro.Recorder.LoadingGuide = false

function WoWPro.Recorder:OnInitialize()
	
	-- Creating the config options --
--	WoWPro.Recorder:CreateConfig()

end

function WoWPro.Recorder:OnEnable()

	--Loading Frames--
	if not WoWPro.Recorder.FramesLoaded then --First time the addon has been enabled since UI Load
		WoWPro.Recorder:CreateRecorderFrame()
		WoWPro.Recorder.SelectedStep = nil
		WoWPro.Recorder.FramesLoaded = true
	end

	-- Creating empty user settings if none exist
	WoWPro_RecorderDB = WoWPro_RecorderDB or {}
	WoWPro.Recorder.CurrentGuide = WoWPro.Recorder.CurrentGuide or {}
	
	WoWPro.Recorder:CustomizeFrames()
	
	WoWPro.Recorder:RegisterEvents()
	WoWPro.Recorder:RegisterSavedGuides()
	WoWPro.Recorder.ProcessScenarioStage(nil)
end

function WoWPro.Recorder:OnDisable()

	-- Unregistering Recorder Module Events --
	local events = {
	}
	for _, event in ipairs(events) do
		WoWPro.GuideFrame:UnregisterEvent(event)
	end
	
end

function WoWPro.Recorder:RegisterSavedGuides()
	local myUFG = UnitFactionGroup("player")
	for GID,guideInfo in pairs(WoWPro_RecorderDB) do
		if factionname and factionname ~= myUFG and factionname ~= "Neutral" then return end
		if type(guideInfo.sequence) == "table" then
		    guideInfo.sequence = table.concat(guideInfo.sequence,"\n")
		end
		WoWPro.Guides[GID] = {
			guidetype = guideInfo.guidetype,
			zone = guideInfo.zone,
			author = guideInfo.author,
			startlevel = tonumber(guideInfo.startlevel),
			endlevel = tonumber(guideInfo.endlevel),
			sequence = function()
return guideInfo.sequence
end,
			nextGID = guideInfo.nextGID,
		}
	end
end

function WoWPro.Recorder:InitGuide(GIDvalue,guidetype,kvp)
	WoWPro.Guides[GIDvalue] = {
	    guidetype = guidetype,
		sequence = function() 
return [[
]] end,
	}
	for key,value in pairs(kvp) do
	    WoWPro.Guides[GIDvalue][key] = value
	end
end

local function checkClassQuest(QID, questTable)
	if UnitClass("player") == questTable[QID].header then 
		return UnitClass("player")
	else
		return nil
	end
end


function WoWPro.Recorder.eventHandler(frame, event, ...)
	local GID = WoWProDB.char.currentguide
	WoWPro.Recorder:dbp(event.." event fired.")
	if WoWPro.Recorder.status == "STOP" or not WoWPro.Guides[GID] then return end
	
	local x, y = GetPlayerMapPosition("player")
	local zonetag
	if GetZoneText() ~= WoWPro.Guides[GID].zone then zonetag = GetZoneText() else zonetag = nil end


	if event == "CHAT_MSG_SYSTEM" then
		WoWPro.Recorder:dbp("CHAT_MSG_SYSTEM detected.")
		local msg = ...
		local _, _, loc = msg:find(L["(.*) is now your home."])
		if loc then
			local stepInfo = {
				action = "h",
				step = loc,
				QID = WoWPro.Recorder.lastStep,
				map = string.format("%.2f,%.2f", x*100,y*100),
				zone = zonetag
			}
			if GetUnitName("target") then stepInfo.note = "At "..GetUnitName("target").."." end
			WoWPro.Recorder:dbp("Adding hearth location "..loc)
			WoWPro.Recorder.AddStep(stepInfo)
		end	
		WoWPro:AutoCompleteSetHearth(...)
		
	elseif event == "PLAYER_LEVEL_UP" then
		WoWPro.Recorder:dbp("PLAYER_LEVEL_UP detected.")
		local newLevel = ...
		local stepInfo = {
			action = "L",
			step = "Level "..newLevel,
			QID = WoWPro.Recorder.lastStep,
			note = "You should be around level "..newLevel.." by this point.",
			level = newLevel
		}
		WoWPro.Recorder:dbp("Adding level up to level "..newLevel)
		WoWPro.Recorder.AddStep(stepInfo)
		WoWPro:AutoCompleteLevel(newLevel)
		
	elseif event == "UI_INFO_MESSAGE" then
		WoWPro.Recorder:dbp("UI_INFO_MESSAGE detected.")
		if ... == ERR_NEWTAXIPATH then
			local stepInfo = {
				action = "f",
				step = GetSubZoneText() or GetZoneText(),
				QID = WoWPro.Recorder.lastStep,
				map = string.format("%.2f,%.2f", x*100,y*100),
				zone = zonetag
			}
			if GetUnitName("target") then stepInfo.note = "At "..GetUnitName("target").."." end
			WoWPro.Recorder:dbp("Adding get FP "..GetSubZoneText() or GetZoneText())
			WoWPro.Recorder.AddStep(stepInfo)
		end
		WoWPro:AutoCompleteGetFP(...)
		
	elseif event == "POST_QUEST_LOG_UPDATE" then
		WoWPro.Recorder:dbp("POST_QUEST_LOG_UPDATE detected.")
		WoWPro.inhibit_oldQuests_update = false
		
		if WoWPro.newQuest then
			local questInfo = WoWPro.QuestLog[WoWPro.newQuest]
			local stepInfo = {
				action = "A",
				step = questInfo.title,
				QID = WoWPro.newQuest,
				map = string.format("%.2f,%.2f", x*100,y*100),
				zone = zonetag,
				class = checkClassQuest(WoWPro.newQuest,WoWPro.QuestLog)
			}
			if GetUnitName("target") then stepInfo.note = "From "..GetUnitName("target").."." end
			WoWPro.Recorder.lastStep = WoWPro.newQuest
			WoWPro.Recorder:dbp("Adding new quest "..WoWPro.newQuest)
			WoWPro.Recorder.AddStep(stepInfo)
			WoWPro:AutoCompleteQuestUpdate()
			
		elseif WoWPro.missingQuest and WoWPro.CompletingQuest then
			local questInfo = WoWPro.oldQuests[WoWPro.missingQuest]
			local stepInfo = {
				action = "T",
				step = questInfo.title,
				QID = WoWPro.missingQuest,
				map = string.format("%.2f,%.2f", x*100,y*100),
				zone = zonetag,
				class = checkClassQuest(WoWPro.missingQuest,WoWPro.oldQuests)
			}
			if GetUnitName("target") then stepInfo.note = "To "..GetUnitName("target").."." end
			WoWPro.Recorder:dbp("Turning in quest "..stepInfo.QID)
			WoWPro.Recorder.AddStep(stepInfo)
			WoWPro:AutoCompleteQuestUpdate()
			
		else
		    WoWPro.Recorder:dbp("Got PQLU and looking for changed quest status")
			for QID, questInfo in pairs(WoWPro.QuestLog) do
                if WoWPro.oldQuests[QID] then
                    if WoWPro.oldQuests[QID].leaderBoard and WoWPro.QuestLog[QID].leaderBoard then
                        for idx,status in pairs(WoWPro.QuestLog[QID].leaderBoard) do
                            WoWPro.Recorder:dbp("Checking status on QO #%d of QID %d aka %s",idx,QID,status)
                            if (not WoWPro.oldQuests[QID].ocompleted[idx]) and WoWPro.QuestLog[QID].ocompleted[idx] then
        						local stepInfo = {
        							action = "C",
        							step = WoWPro.QuestLog[QID].title,
        							QID = QID,
        							map = string.format("%.2f,%.2f", x*100,y*100),
        							zone = zonetag,
        							noncombat = nc,
        							use = WoWPro.QuestLog[QID].use,
        							note = WoWPro.QuestLog[QID].leaderBoard[idx],
        							questtext = tostring(idx),
        							class = checkClassQuest(QID,WoWPro.QuestLog)
        						}
        						WoWPro.Recorder:dbp("Completed QO #%d (%s) for [%s]",idx,stepInfo.note, stepInfo.step)
        						WoWPro.Recorder.AddStep(stepInfo)
        						WoWPro:AutoCompleteQuestUpdate()
        					end
        				end
					end
				end
			end
		end
	end
end

function WoWPro.Recorder.PostQuestLogUpdate()
    if not WoWPro.GuideLoaded then
        WoWPro.Recorder:dbp("Suppressing PostQuestLogUpdate() after LoadGuide()")
        WoWPro:SendMessage("WoWPro_PostQuestLogUpdate")
        return
    end
    WoWPro.Recorder.eventHandler(nil,"POST_QUEST_LOG_UPDATE")
end

function WoWPro.Recorder.PostGuideLoad()
end

function WoWPro.Recorder.PostUpdateGuide()
    if not WoWPro.Recorder.SelectedStep then
        if WoWPro.ActiveStep then
            WoWPro.Recorder.SelectedStep = WoWPro.ActiveStep
            WoWPro.Recorder:dbp("WoWPro.Recorder.PostUpdateGuide(): Selecting step %d as current position at ActiveStep.", WoWPro.ActiveStep)
        else
            WoWPro.Recorder.SelectedStep = WoWPro.stepcount
            WoWPro.Recorder:dbp("WoWPro.Recorder.PostUpdateGuide(): Selecting step %d as current position at EOG.", WoWPro.stepcount)
        end
    else
        WoWPro.Recorder:dbp("WoWPro.Recorder.PostUpdateGuide(): Keeping step %d as current position.", WoWPro.Recorder.SelectedStep)
    end
end

local old_scenario = nil

function WoWPro.Recorder.ProcessScenarioStage(scenario)
    -- Cleanup!
    if not scenario then
        old_scenario = nil
        return
    end
    
    local GID = WoWProDB.char.currentguide
    local zonetag
    if GetZoneText() ~= WoWPro.Guides[GID].zone then
        zonetag = GetZoneText()
    else
        zonetag = nil
    end
    
    if old_scenario then
        -- has anything changed?
        if old_scenario.currentStage > scenario.currentStage then
            -- close old stage and open the new stage
            local stepInfo = {
                action = "C",
                step = old_scenario.stageName,
                zone = zonetag,
                note = old_scenario.stageDescription,
                unsticky = true,
                sobjective = tostring(old_scenario.currentStage),
            }
            WoWPro.Recorder:Print("Closing old stage: %s", stepInfo.step)
            WoWPro.Recorder.AddStep(stepInfo)
            stepInfo = {
                action = "C",
                step = scenario.stageName,
                zone = zonetag,
                note = scenario.stageDescription,
                sticky = true,
                sobjective = tostring(scenario.currentStage),
            }
            WoWPro.Recorder:Print("Entering next stage: %s", stepInfo.step)
            WoWPro.Recorder.AddStep(stepInfo)
        else
            if scenario.completed then
               -- Close Scenario
                local stepInfo = {
                    action = "C",
                    step = scenario.stageName,
                    zone = zonetag,
                    note = scenario.stageDescription,
                    unsticky = true,
                    sobjective = tostring(scenario.currentStage),
                }
                WoWPro.Recorder:Print("Finishing final stage: %s", stepInfo.step)
                WoWPro.Recorder.AddStep(stepInfo)        
            end
        end
    else    
       -- New Scenario
        local stepInfo = {
            action = "C",
            step = scenario.stageName,
            zone = zonetag,
            note = scenario.stageDescription,
            sticky = true,
            sobjective = tostring(scenario.currentStage),
        }
        WoWPro.Recorder:Print("Starting new scenario: %s", scenario.name)
        WoWPro.Recorder:Print("Entering new stage: %s", stepInfo.step)
        WoWPro.Recorder.AddStep(stepInfo)
    end
    WoWPro.Recorder.ProcessScenarioCriteria(scenario)
end

function WoWPro.Recorder.ProcessScenarioCriteria(scenario)
    local GID = WoWProDB.char.currentguide
    local x, y = GetPlayerMapPosition("player")
    local zonetag
    if GetZoneText() ~= WoWPro.Guides[GID].zone then zonetag = GetZoneText() else zonetag = nil end

    if old_scenario then
        if old_scenario.currentStage == scenario.currentStage then
            WoWPro.Recorder:dbp("WoWPro.Recorder.ProcessScenario: Scanning stage: %d for completed criteria", scenario.currentStage )
            for criteriaIndex = 1, scenario.numCriteria do
                if (not old_scenario.Criteria[criteriaIndex].completed) and scenario.Criteria[criteriaIndex].completed then
                    -- Incremental completion!
                    local stepInfo = {
                        action = "C",
                        step = scenario.Criteria[criteriaIndex].criteriaString,
                        map = string.format("%.2f,%.2f", x*100,y*100),
                        zone = zonetag,
                        note = scenario.Criteria[criteriaIndex].criteriaString,
                        sobjective = string.format("%d;%d", scenario.currentStage, criteriaIndex),
                    }
                    WoWPro.Recorder:Print("Completed criteria: %s", stepInfo.step)
                    WoWPro.Recorder.AddStep(stepInfo)
                end
            end
        else
            -- if we switched stages, then anything uncompleted in the old state must have been done!
            WoWPro.Recorder:dbp("WoWPro.Recorder.ProcessScenario: PostScanning stage: %d for completed criteria", old_scenario.currentStage )
            for criteriaIndex = 1, old_scenario.numCriteria do
                if (not old_scenario.Criteria[criteriaIndex].completed) then
                    -- Pretend completed!
                    local stepInfo = {
                           action = "C",
                           step = old_scenario.Criteria[criteriaIndex].criteriaString,
                           map = string.format("%.2f,%.2f", x*100,y*100),
                           zone = zonetag,
                           note = old_scenario.Criteria[criteriaIndex].criteriaString,
                           sobjective = string.format("%d;%d", old_scenario.currentStage, criteriaIndex),
                    }
                    WoWPro.Recorder.AddStep(stepInfo)
                end
            end
        end
    else
        WoWPro.Recorder:dbp("WoWPro.Recorder.ProcessScenario: No old_scenario for reference.")
    end
    -- Update state
    if scenario.completed then
        old_scenario = nil
    else
        old_scenario = scenario
    end
end


function WoWPro.Recorder:RegisterEvents()
	WoWPro.Recorder.events = {"UI_INFO_MESSAGE", "CHAT_MSG_SYSTEM", "PLAYER_LEVEL_UP"}
	
	for _, event in pairs(WoWPro.Recorder.events) do
		WoWPro.RecorderFrame:RegisterEvent(event)
		WoWPro.Recorder:dbp(event.." event registered")
	end
	
	WoWPro.RecorderFrame:SetScript("OnEvent", WoWPro.Recorder.eventHandler);
end

function WoWPro.Recorder:RowUpdate(offset)
	WoWPro.Recorder.SelectedStep = WoWPro.Recorder.SelectedStep or WoWPro.ActiveStep
	WoWPro.Recorder.RowDropdownMenu = {}
	for i,row in pairs(WoWPro.rows) do
		local dropdown = {
			{text = "Move Up", func = function()
				local pos = WoWPro.Recorder.SelectedStep or WoWPro.stepcount
				if pos == 1 then return end
				for tag,_ in pairs(WoWPro.Tags) do 
					if not WoWPro[tag][pos] then WoWPro[tag][pos] = false end
					table.insert(WoWPro[tag], pos-1, WoWPro[tag][pos])
				end
				for tag,_ in pairs(WoWPro.Tags) do 
					table.remove(WoWPro[tag], pos+1)
				end
				WoWPro.Recorder.SelectedStep = pos-1
				WoWPro.Recorder:CheckpointCurrentGuide("MoveUp")
				WoWPro:UpdateGuide("WoWPro.Recorder:RowUpdate(MoveUp)")
			end},
			{text = "Move Down", func = function()
				local pos = WoWPro.Recorder.SelectedStep or WoWPro.stepcount
				if pos == WoWPro.stepcount then return end
				for tag,_ in pairs(WoWPro.Tags) do 
					if not WoWPro[tag][pos] then WoWPro[tag][pos] = false end
					table.insert(WoWPro[tag], pos+2, WoWPro[tag][pos])
				end
				for tag,_ in pairs(WoWPro.Tags) do 
					table.remove(WoWPro[tag], pos)
				end
				WoWPro.Recorder.SelectedStep = pos+1
				WoWPro.Recorder:CheckpointCurrentGuide("MoveDown")
				WoWPro:UpdateGuide("WoWPro.Recorder:RowUpdate(MoveDown)")
			end},
			{text = "Clone Step", func = function()
				local pos = WoWPro.Recorder.SelectedStep or WoWPro.stepcount
				for tag,_ in pairs(WoWPro.Tags) do 
					if not WoWPro[tag][pos] then WoWPro[tag][pos] = false end
					table.insert(WoWPro[tag], pos+1, WoWPro[tag][pos])
				end
				WoWPro.stepcount = WoWPro.stepcount+1
			    WoWPro.Recorder:CheckpointCurrentGuide("Clone")
				WoWPro:UpdateGuide("WoWPro.Recorder:RowUpdate(Clone)")
			end}
		}
		WoWPro.Recorder.RowDropdownMenu[i] = dropdown
		
		if WoWPro.Recorder.SelectedStep == row.index then
			row:SetChecked(true)
		else
			row:SetChecked(false)
		end
		
	end
end

function WoWPro.Recorder:RowLeftClick(i)
	WoWPro.Recorder.SelectedStep = WoWPro.rows[i].index
	WoWPro.Recorder:RowUpdate(true)
end
		
function WoWPro.Recorder.AddStep(stepInfo,position)
    if not WoWPro.GuideLoaded then
        WoWPro.Recorder:Warning("Hey, no guide is loaded!")
        return
    end
    if type(stepInfo.action) ~= "string" then
        stepInfo.action = "?"
    end
    if type(stepInfo.step) ~= "string" then
        stepInfo.step = "?"
    end
        
	local pos = position or WoWPro.Recorder.SelectedStep or WoWPro.stepcount
	if pos > WoWPro.stepcount then
	    pos = WoWPro.stepcount
	end
	WoWPro.Recorder:dbp("Adding new step %d %s [%s]", pos+1, stepInfo.action, stepInfo.step)
	for tag,_ in pairs(WoWPro.Tags) do 
		value = stepInfo[tag]
		if not value then value = false end
		table.insert(WoWPro[tag], pos+1, value)
--		WoWPro.Recorder:dbp("Adding tag "..tag.." at position "..pos+1)
	end
	WoWPro.stepcount = WoWPro.stepcount+1
	if WoWPro.Recorder.SelectedStep then
	    WoWPro.Recorder.SelectedStep = WoWPro.Recorder.SelectedStep + 1
	else
	    WoWPro.Recorder.SelectedStep = WoWPro.stepcount
	end
	WoWPro.Recorder:CheckpointCurrentGuide("AddStep")
	local line = WoWPro.Recorder.EmitStep(pos+1)
	line = line:gsub("|", "¦")
	WoWPro.Recorder:Print(line)
	WoWPro:UpdateGuide("WoWPro.Recorder.AddStep()")
end

function WoWPro.Recorder:RemoveStep(position)
    if not WoWPro.GuideLoaded then
        WoWPro.Recorder:Warning("Hey, no guide is loaded!")
        return
    end
	local pos = position or WoWPro.stepcount
	WoWPro.Recorder:dbp("Deleteing step %d %s [%s]",pos, WoWPro.action[pos], WoWPro.step[pos])
	for tag,_ in pairs(WoWPro.Tags) do 
		table.remove(WoWPro[tag], pos)
--		WoWPro.Recorder:dbp("Removing tag "..tag.." at position "..pos)
	end
	WoWPro.stepcount = WoWPro.stepcount-1
	if WoWPro.Recorder.SelectedStep then
	    WoWPro.Recorder.SelectedStep = WoWPro.Recorder.SelectedStep - 1
	else
	    WoWPro.Recorder.SelectedStep = WoWPro.stepcount
	end

	WoWPro.Recorder:CheckpointCurrentGuide("RemoveStep")
	WoWPro:UpdateGuide()
end

---This is what the header needs to look like
---local guide = WoWPro:RegisterGuide('FlucloPanda', "Leveling", 'TheWanderingIsle', 'Fluclo', 'Neutral')
---WoWPro:GuideLevels(guide,1,12,1.0531)
---WoWPro:GuideNextGuide(guide, 'WkjLoc1220|BitAzs1220')
---WoWPro:GuideSteps(guide, function()
---return [[

local function addTag(line, tag, value)
	line = line..tag.."\|"
	if value then
		line = line..tostring(value).."\|"
	end
	return line
end


function WoWPro.Recorder.EmitStep(i)
    if type(WoWPro.action[i]) ~= "string" or type(WoWPro.step[i]) ~= "string" then
        return ""
    end

    local line = WoWPro.action[i].." "..WoWPro.step[i].."|"
    
    if WoWPro.QID[i] then line = addTag(line, "QID", tostring(WoWPro.QID[i])) end
    if WoWPro.optional[i] then line = addTag(line, "O") end
    if WoWPro.sticky[i] then line = addTag(line, "S") end
    if WoWPro.unsticky[i] then line = addTag(line, "US") end
    if WoWPro.rank[i] then line = addTag(line, "RANK", WoWPro.rank[i]) end
    if WoWPro.noncombat[i] then line = addTag(line, "NC") end
    if WoWPro.level[i] then line = addTag(line, "LVL", WoWPro.level[i]) end
    if WoWPro.prof[i] then line = addTag(line, "P", WoWPro.prof[i]) end
    if WoWPro.waypcomplete[i] == 1 then line = addTag(line, "CC")
    elseif WoWPro.waypcomplete[i] == 2 then line = addTag(line, "CS") end
    if WoWPro.prereq[i] then line = addTag(line, "PRE", WoWPro.prereq[i]) end
    if WoWPro.leadin[i] then line = addTag(line, "LEAD", WoWPro.leadin[i]) end
    if WoWPro.use[i] then line = addTag(line, "U", WoWPro.use[i]) end
    if WoWPro.lootitem[i] then
    	line = line.."L|"..WoWPro.lootitem[i]
    	if WoWPro.lootqty[i] then
    		line = line.." "..WoWPro.lootqty[i].."|"
    	else
    		line = line.."|"
    	end
    end
    if WoWPro.target[i] then line = addTag(line, "T", WoWPro.target[i]) end
    if WoWPro.questtext[i] then line = addTag(line, "QO", WoWPro.questtext[i]) end
    if WoWPro.sobjective[i] then line = addTag(line, "SO", WoWPro.sobjective[i]) end
    if WoWPro.map[i] then line = addTag(line, "M", WoWPro.map[i]) end
    if WoWPro.zone[i] then line = addTag(line, "Z", WoWPro.zone[i]) end
    if WoWPro.note[i] then line = addTag(line, "N", WoWPro.note[i]) end
    return line
end

function WoWPro.Recorder:CheckpointCurrentGuide(why)
	local GID = WoWProDB.char.currentguide

	local header = "local guide = WoWPro:RegisterGuide('"
		..GID.."', '"
		..WoWPro.Guides[GID].guidetype.."', '"
		..WoWPro.Guides[GID].zone.."', '"
		..WoWPro.Guides[GID].author.."', '"
		..UnitFactionGroup("player").."')\n"
		.."WoWPro:GuideLevels(guide,"
		..WoWPro.Guides[GID].startlevel..", "
		..WoWPro.Guides[GID].endlevel..")\n"
		.."WoWPro:GuideNextGuide(guide, '"
		..WoWPro.Guides[GID].nextGID.."')\n"
		.."WoWPro:GuideSteps(guide, function()\nreturn [[\n"
		
	local sequence = {}
		
	
	for i,action in pairs(WoWPro.action) do
	    local line = WoWPro.Recorder.EmitStep(i)
		table.insert(sequence,line)
	end
	
	local guideString = header..table.concat(sequence,"\n").."\n]]\n\nend)"
	
	WoWPro_RecorderDB[GID] = {
		guidetype = WoWPro.Guides[GID].guidetype,
		zone = WoWPro.Guides[GID].zone,
		author = WoWPro.Guides[GID].author,
		startlevel = tonumber(WoWPro.Guides[GID].startlevel),
		endlevel = tonumber(WoWPro.Guides[GID].endlevel),
		sequence = sequence,
		nextGID = WoWPro.Guides[GID].nextGID,
		faction = UnitFactionGroup("player")
	}
	WoWPro.Recorder:RegisterSavedGuides()
	WoWPro.Recorder:dbp("WoWPro.Recorder:CheckpointCurrentGuide(%s)",why)
	return guideString
end

function WoWPro.Recorder:SaveGuide(window)
    if not WoWPro.GuideLoaded then
        WoWPro.Recorder:Warning("Hey, no guide is loaded!")
        return
    end
    local guideString = WoWPro.Recorder:CheckpointCurrentGuide("Save")
	-- Save Guide Dialog --
	config:RegisterOptionsTable("WoWPro Recorder - Save Guide", {
		name = "Save Guide",
		type = "group",
		args = {
			guidetype = {
				order = 0,
				type = "input",
				multiline = 20,
				name = "Copy the following and paste it into a guide file:",
				desc = "",
				width = "full",
				get = function(info)
						return guideString:trim():gsub("|N", "||N"):gsub("|R", "||R")
					end,
			},
		},
	})
	dialog:SetDefaultSize("WoWPro Recorder - Save Guide", 750, 400)
	if window then dialog:Open("WoWPro Recorder - Save Guide", WoWPro.DialogFrame) end

end