dofile("scripts/forts.lua")
RequiresMoonshot = false
RequiresHighSeas = false
Sandbox = true
Skirmish = false --[[Currently no AI supported.]]--
Multiplayer = true

Symmetrical = false
Mods = {}
Author = L"Papa Sasquatch"
DescLine1 = L"Vanilla (2v2)"

--[[
Map Created by Papa Sasquatch
Music by DSTechnician
Crystal Enviroment by lies 
https://steamcommunity.com/sharedfiles/filedetails/?id=2908915590&searchtext=crystal]]--

--[[ --------------MUSIC STUFF--------------- ]]--

Idle = "/music/dominion.mp3"
Intense = "/music/calculated-drift.mp3"
ReactorLow = "/music/chernobyl_prize(remix).mp3"
Win = "/music/fat_base(mars_mojito_mix).mp3"
Lose = "/music/dear_john(mars_remix).mp3"

LogIntensity = false
LogChanges = false

-- if this is false then only the friendly team's reactor
-- will be considered for going into the ReactorLow state
EnemyReactorsTriggerState = true

-- turn this off to make return to idle more responsive
IntenseTracksMustComplete = false

FadePeriod = 4
FadePeriodQuick = 2
DefaultMinPeriod = 0

-- a random period between between these two values will be selected
-- they can be equal to use a fixed value
SilencePeriodMin = 30
SilencePeriodMax = 30

-- Thresholds for state change
IntenseStartThreshold = 50
IntenseEndThreshold = 30
LowReactorThreshold = 0.5

-- Upper limit of intensity and decay rate
IntensityMax = 100
IntensityDecay = 1.25

-- Events that affect intensity
IntensityLinkDestroyed = 2.5
IntensityProjectileDamageScale = 40/700
IntensityBeamFired = 15
IntensityProjectileCollision = 2
IntensityDeviceDestroyed = 15

-- Victory/defeat music options
ResultMusicDelay = true
ResultLoop = true
ResultDisabled = false


AudioLabels = {}

function Load()
   SendScriptEvent("StopAllStreams","nil","scripts/music.lua",false)
   SendScriptEvent("Disable","nil","scripts/music.lua",false)
   MusicState =
   {
      ["Intro"] =
      {
         Series = "Music.Intro",
      },
      ["Idle"] =
      {
         Series = path .. Idle,
         MinPeriod = 5,
      },
      ["Intense"] =
      {
         Series = path .. Intense,
         MinPeriod = 10,
      },
      ["ReactorLow"] =
      {
         Series = path .. ReactorLow,
      },
      ["Win"] =
      {
         Series = path .. Win,
      },
      ["Lose"] =
      {
         Series = path ..Lose,
      },
   }
   Log(MusicState.Idle.Series.."")
   teamId = GetLocalTeamId()
	if InReplay() then
		teamId = 1
	end

	if teamId%MAX_SIDES == 1 then
		data.enemyTeamId = 2
	else
		data.enemyTeamId = 1
	end

	--Log("Load music.lua, teamId " .. teamId)

	data.updateRate = 1
	data.allowChangeDown = true

	OnRestart()
end

function OnRestart()
	data.gameOver = nil
	data.gameFrame = 0
	data.gameIntensity = 0
	data.currentState = nil
	data.currentMusic = nil
	data.lastMusicChangeTime = 0
	reactorLowLastHealth = nil
	lowestReactorId = nil
	lowestReactorHealth = nil
	maxLowestReatorHealthUntilTrackEnd = nil
	CancelScheduledCalls()

	if LogIntensity then AddTextControl("", "intensity", "Intensity: 0", ANCHOR_TOP_LEFT, Vec3(600, 80), false, "Normal") end
	if LogIntensity then AddTextControl("", "reactor-low", "Lowest Reactor: 1", ANCHOR_TOP_LEFT, Vec3(600, 96), false, "Normal") end
	if LogChanges then AddTextControl("", "state", "State: intro", ANCHOR_TOP_LEFT, Vec3(600, 112), false, "Normal") end

	FadeCurrent(0)

	if reactorLow then
		StopStream(reactorLow)
		reactorLow = nil
	end

	-- delay this slightly to give mission scripts a chance to change or clear the music script
	-- before the intro is started
	ScheduleCall(0.1, StartIntro)
end

function CleanupStreams()
	StopAllStreams()
	if reactorLow then
		StopStream(reactorLow)
		reactorLow = nil
	end
end

function OnPreSeek()
	CleanupStreams()
end

function OnSeek()
--	Log("OnSeek")
	CancelScheduledCalls()
	StopAllStreams()
	data.introTrack = nil
	data.gameOver = nil
	data.gameFrame = 0
	data.currentState = nil
	data.currentMusic = nil
	data.allowChangeDown = true
	data.lastMusicChangeTime = -100
	data.gameIntensity = 0.4*data.gameIntensity -- to rapidly return to Idle state
	musicPaused = nil

	if data.gameIntensity >= IntenseStartThreshold then
		ChangeMusic("Intense")
	else
		ChangeMusic("Idle")
	end

	ScheduleCall(data.updateRate, Monitor)
end

function StartIntro()
	ChangeMusic("Intro", false, false)
	if currentChannel then
		PauseStreamOnAdvance(currentChannel, false)
		data.introTrack = currentChannel
	end
	
	-- for when music is paused during call to Load
	if musicPaused then
		PauseMusic()
	end
end

function OnExit()
end

function OnGameResult(winningTeamId, customCondition)
	--Log(data.gameFrame .. " Music OnGameResult " .. winningTeamId .. ", script team " .. teamId)

	if ResultDisabled then
		return
	end

	TriggerResultMusic(winningTeamId, customCondition, nil)
end

function TriggerResultMusic(winningTeamId, customCondition, delayOverride)
	--Log(data.gameFrame .. " Music TriggerResultMusic " .. winningTeamId .. ", script team " .. teamId)
	if InReplay() or data.gameOver then
		return
	end
	
	data.gameOver = true

	CancelScheduledCalls()
	FadeCurrent(FadePeriod)

	local musicToPlay = "Lose"
	if teamId == TEAM_OBS or winningTeamId == teamId%MAX_SIDES then
		musicToPlay = "Win"
	end

	if reactorLow then
		FadeStream(reactorLow, FadePeriodQuick)
		reactorLow = nil
		lowestReactorId = nil
		maxLowestReatorHealthUntilTrackEnd = nil
	end

	if ResultMusicDelay and not customCondition then
		-- play the end game music after a delay
		local ruleTeamId = teamId%MAX_SIDES
		if teamId == TEAM_OBS then
			ruleTeamId = winningTeamId%MAX_SIDES
		end

		local delay = delayOverride or GetRule(ruleTeamId, "EndGameDelay")

		currentChannel = nil
		ScheduleCall(delay, PlayResultMusic, musicToPlay)
	else
		PlayResultMusic(musicToPlay)
	end
end

function PlayResultMusic(playlist)
	ChangeMusic(playlist, ResultLoop)
	if currentChannel then
		ContinueStreamOnPauseMenu(currentChannel)
		PauseStreamOnAdvance(currentChannel, false)
	end
end

function Cleanup()
	if LogIntensity then DeleteControl("", "intensity") end
	if LogIntensity then DeleteControl("", "reactor-low") end
	if LogChanges then DeleteControl("", "state") end
	CleanupStreams()
end

function Disable()
	data.Disabled = true
	CancelScheduledCalls()
end

function OnStreamComplete(channel, fromReplay)
	-- ignore complete events from the replay file, music adapts to the actual playback
	-- as it doesn't matter if it's not true to the original
	if fromReplay and InReplay() then return end

	if LogChanges then
		Log("OnStreamComplete " .. channel .. " current state " .. tostring(data.currentState) .. ", currentChannel " .. tostring(currentChannel))
	end
	if not fromReplay and channel == data.introTrack then
--		Log("Intro finished")
		data.introTrack = nil
		data.currentState = nil
		data.currentMusic = nil
		data.lastMusicChangeTime = -1000000 -- force change of music
		Monitor()
	elseif channel == reactorLow then
--		Log("Reactor low complete, resuming channel " .. tostring(currentChannel))
		if currentChannel then
			PauseStream(currentChannel, false, FadePeriodQuick)
		end
		reactorLow = nil
		maxLowestReatorHealthUntilTrackEnd = nil
	elseif not musicPaused and channel ~= data.introTrack then
		data.allowChangeDown = false
		local delay = GetRandomFloatLocal(SilencePeriodMin, SilencePeriodMax)
		--Log("Silence period " .. delay)
		ScheduleCall(delay, ResumeSeries, channel)
	end
end

function ResumeSeries(id)
--	Log("Resume series " .. id)
	
	-- Works for series of tracks in constants
	--PauseStream(id, false, 0)

	-- Works to loop studio events
	data.currentState = nil
	ChangeMusic(data.currentState)

	data.lastMusicChangeTime = -1000000 -- encourage the music to change at the end of a track
	data.allowChangeDown = not IntenseTracksMustComplete or (data.currentState == "Intense") -- forces all intense tracks to complete with some silence before going into idle state
	
	-- stop the next track of the old series instantly in the case of a change in music
	local savedFadePeriod = FadePeriod
	FadePeriod = 0
	
	-- give the music a change to change to something else instead of playing any of the next track
	CancelScheduledCalls()
	Monitor()
	
	FadePeriod = savedFadePeriod
	
	data.allowChangeDown = not IntenseTracksMustComplete
end

function FadeCurrent(duration)
	if currentChannel ~= nil then
		FadeStream(currentChannel, duration or 0)
		currentChannel = nil
	end
end

function ChangeMusic(state, loop, randomise)
	if data.currentState ~= state then
		if LogChanges then
			Log("ChangeMusic to " .. state .. " loop = " .. tostring(loop))
		end

		data.currentState = state
		data.currentMusic = MusicState[state].Series
		data.lastMusicChangeTime = data.gameTime or 0
		FadeCurrent(FadePeriod)
		currentChannel = StartMusic(data.currentMusic, loop == true or loop == nil, randomise == true or randomise == nil)
		PauseStreamOnAdvance(currentChannel, true)
		if LogChanges then
			SetControlText("", "state", "State: " .. tostring(state))
		end
	end
end

function MinPeriod()
	if not data.currentState or MusicState[data.currentState].MinPeriod == nil then
		return DefaultMinPeriod
	else
		local min = MusicState[data.currentState].MinPeriod
		return min
	end
end

function LowestReactorHealth(team, lowestReactorId, currentLow)
	local deviceCount = GetDeviceCountSide(team)
	for index = 0,deviceCount - 1 do
		local id = GetDeviceIdSide(team, index)
		local saveName = GetDeviceType(id)
		if saveName == "reactor" then
			local health = GetDeviceHealth(id)
			if health < currentLow then
				currentLow = health
				lowestReactorId = id
			end
		end
	end
	return lowestReactorId, currentLow
end

function ReactorIsLow()
	local lowestReactorId, lowestReactorHealth = LowestReactorHealth(teamId, 0, 1)
	if EnemyReactorsTriggerState then
		lowestReactorId, lowestReactorHealth = LowestReactorHealth(data.enemyTeamId, lowestReactorId, lowestReactorHealth)
	end
	if (maxLowestReatorHealthUntilTrackEnd ~= nil) then
		if (lowestReactorHealth > maxLowestReatorHealthUntilTrackEnd and reactorLow) then
			lowestReactorHealth = maxLowestReatorHealthUntilTrackEnd
		else
			maxLowestReatorHealthUntilTrackEnd = nil
		end
	end
	return lowestReactorId, lowestReactorHealth
end

function Monitor()
	--Log("Music Monitor " .. tostring(data.Disabled) .. ", " .. tostring(data.gameOver) .. ", " .. tostring(data.musicPaused))

	if data.Disabled or data.gameOver then
--		Log("  Disabled or game over")
		return
	end

	if not musicPaused then
		if data.gameIntensity > IntensityMax then
			data.gameIntensity = IntensityMax
		end
	
		local lowestReactorHealth = 1
		lowestReactorId, lowestReactorHealth = ReactorIsLow()
		local reactorIsLowEvent = lowestReactorHealth < LowReactorThreshold and lowestReactorHealth < (reactorLowLastHealth or 1) and not reactorLow
		
		-- update reactor health global parameter
		if (reactorLow or reactorIsLowEvent) and (lowestReactorHealth < (reactorLowLastHealth or 1)) then
			SetGlobalAudioParameter("lowestReactorHealth", lowestReactorHealth)
		end

--		Log("lowestReactor " .. tostring(lowestReactorId) .. " has health " .. lowestReactorHealth .. ", low event " .. tostring(reactorIsLowEvent))

		if LogIntensity then
			local roundedIntensity = Round(data.gameIntensity, 3)
			local text = tostring(roundedIntensity)
			text = "Intensity " .. text.sub(text, 1, 5)
			if reactorIsLowEvent then
				text = text .. ", Reactor Low"
			end
			SetControlText("", "intensity", text)
			text = tostring(Round(lowestReactorHealth, 3))
			text = "Lowest Reactor " .. text.sub(text, 1, 5)
			SetControlText("", "reactor-low", text)
		end
	
		-- Don't cut the intro and limit how frequently music can change
		if not data.introTrack and (reactorIsLowEvent or (data.gameTime - data.lastMusicChangeTime > MinPeriod())) then
			-- above a threshold of activity the music goes into 'intense' mode
			if reactorIsLowEvent then
				--Log("pausing current stream, playing sting")
				if currentChannel then
					PauseStream(currentChannel, true, FadePeriod)
				end
				reactorLow = StartStream(MusicState["ReactorLow"].Series, 1.0)
				--Log("reactorLow " .. reactorLow)
			elseif not reactorLow and data.gameIntensity >= IntenseStartThreshold then
				ChangeMusic("Intense")
			elseif not reactorLow and data.allowChangeDown and data.gameIntensity <= IntenseEndThreshold then
				ChangeMusic("Idle")
			end
	--	elseif data.introTrack then
	--		Log("  Intro track playing")
	--	else
	--		Log("  Waiting for minimum play time")
		end

		reactorLowLastHealth = lowestReactorHealth

		-- decay the intensity so a return to calm is reflected in the music
		data.gameIntensity = data.gameIntensity - IntensityDecay*data.updateRate
		if data.gameIntensity < 0 then
			data.gameIntensity = 0
		end
	end

	ScheduleCall(data.updateRate, Monitor)
end

function OnLinkDestroyed(linkTeamId, saveName, nodeA, nodeB, breakType)
	if breakType ~= LINKBREAK_DELETE then
		data.gameIntensity = data.gameIntensity + IntensityLinkDestroyed
	end
end

function OnWeaponFired(weaponTeamId, saveName, weaponId, projectileNodeId, projectileNodeIdFrom)
	if projectileNodeId > 0 then
		-- projectile weapon fired
		-- scale the contributed intensity by the potential damage
		-- The cannon projectile has a damage of 700 so it has enough, with some damage to trigger intense music by itself
		data.gameIntensity = data.gameIntensity + GetNodeProjectileDamage(projectileNodeId)*IntensityProjectileDamageScale
	else
		-- beam weapon fired
		data.gameIntensity = data.gameIntensity + IntensityBeamFired
	end
end

function OnProjectileCollision(teamIdA, nodeIdA, saveNameA, teamIdB, nodeIdB, saveNameB)
	data.gameIntensity = data.gameIntensity + IntensityProjectileCollision
end

function OnDeviceDestroyed(deviceTeamId, deviceId, saveName, nodeA, nodeB, t)
	data.gameIntensity = data.gameIntensity + IntensityDeviceDestroyed
	--Log("OnDeviceDestroyed " .. deviceId .. ", " .. saveName .. " team " .. deviceTeamId .. " saveName " .. saveName .. " lowestReactorId " .. tostring(lowestReactorId) .. " reactorLow " .. tostring(reactorLow))
	if deviceId == lowestReactorId and reactorLow then
		maxLowestReatorHealthUntilTrackEnd = 0
	end
end

function OverrideMusic(state, newSeries)
	if MusicState[state] then
		MusicState[state].Series = newSeries
	end
end

function PauseMusic(fadePeriod)
	musicPaused = true

	if reactorLow then
		PauseStream(reactorLow, true, fadePeriod or 0)
	end

	if currentChannel then
		PauseStream(currentChannel, true, fadePeriod or 0)
	end
end

function StopReactorLow(fadePeriod)
	if reactorLow then
		FadeStream(reactorLow, fadePeriod or 0)
	end
end

function AdjustMusicVolume(volume, period)
	if currentChannel then
		AdjustStreamVolume(currentChannel, period, volume)
	end
end

function ResumeMusic(fadePeriod)
	musicPaused = nil
	if currentChannel then
		PauseStream(currentChannel, false, fadePeriod or 0)
	end
end

function SetMusicAudioParameter(name, value)
	--Log("SetMusicAudioParameter " .. tostring(name) .. " " .. tostring(value))
	if AudioLabels[name] == nil then
		Log("Error: Cannot find AudioLabel " .. tostring(name))
		return
	end
	if AudioLabels[name][value] == nil then
		Log("Error: Cannot find AudioLabel value lookup " .. tostring(value))
		return
	end
	local rawValue = AudioLabels[name][value]
	SetGlobalAudioParameter(name, rawValue)
end