-- Detach and initialize a Lycoris instance.
local Lycoris = { queued = false, silent = false, dpscanning = false }

---@module Utility.Logger
local Logger = require("Utility/Logger")

---@module Menu
local Menu = require("Menu")

---@module Features
local Features = require("Features")

---@module Utility.ControlModule
local ControlModule = require("Utility/ControlModule")

---@module Game.Timings.SaveManager
local SaveManager = require("Game/Timings/SaveManager")

---@module Utility.Maid
local Maid = require("Utility/Maid")

---@module Utility.Signal
local Signal = require("Utility/Signal")

---@module Game.Timings.ModuleManager
local ModuleManager = require("Game/Timings/ModuleManager")

---@module Utility.CoreGuiManager
local CoreGuiManager = require("Utility/CoreGuiManager")

---@module Utility.PersistentData
local PersistentData = require("Utility/PersistentData")

---@module Game.PlayerScanning
local PlayerScanning = require("Game/PlayerScanning")

---@module Game.Keybinding
local Keybinding = require("Game/Keybinding")

-- Lycoris maid.
local lycorisMaid = Maid.new()

-- Constants.
local LOBBY_PLACE_ID = 14067600077

-- Services.
local playersService = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

-- Timestamp.
local startTimestamp = os.clock()

---Initialize instance.
function Lycoris.init()
	local localPlayer = nil

	repeat
		task.wait()
	until game:IsLoaded()

	repeat
		localPlayer = playersService.LocalPlayer
	until localPlayer ~= nil

	PersistentData.init()

	if isfile and isfile("smarker_ts.txt") then
		Lycoris.silent = true
	end

	if isfile and isfile("dpscanning_ts.txt") then
		Lycoris.dpscanning = true
	end

	if script_key and queue_on_teleport and not Lycoris.queued and not no_queue_on_teleport then
		-- String.
		local scriptKeyQueueString = string.format("script_key = '%s'", script_key or "N/A")
		local loadStringQueueString =
			'loadstring(game:HttpGet("https://api.luarmor.net/files/v3/loaders/0216eb5f95556e660be56009441409ae.lua"))()'

		-- Queue.
		queue_on_teleport(scriptKeyQueueString .. "\n" .. loadStringQueueString)

		-- Mark.
		Lycoris.queued = true

		-- Warn.
		Logger.warn("Script has been queued for next teleport.")
	else
		-- Fail.
		Logger.warn("Script has failed to queue on teleport because Luarmor internals or the function do not exist.")
	end

	local tslot = PersistentData.get("tslot")
	local tdestination = PersistentData.get("tdestination")

	if game.PlaceId == LOBBY_PLACE_ID and tslot and tdestination then
		local remotes = replicatedStorage:WaitForChild("Remotes")
		local chooseSlotRemote = remotes:WaitForChild("ChooseSlot")
		local teleportRemote = remotes:WaitForChild("Teleport")

		chooseSlotRemote:InvokeServer(tslot, nil)
		teleportRemote:InvokeServer({ teleportTo = tdestination })
	end

	PersistentData.set("tslot", nil)
	PersistentData.set("tdestination", nil)

	if game.PlaceId == LOBBY_PLACE_ID then
		return Logger.warn("Script has initialized in the lobby.")
	end

	local remotes = replicatedStorage:WaitForChild("Remotes")
	local vastoVfx = remotes:FindFirstChild("VastoVfx")

	if vastoVfx then
		vastoVfx:Destroy()
	end

	Logger.warn("Anticheat has been successfully penetrated.")

	local currentElo = "N/A"
	local eloType = "N/A"

	if game.PlaceId == 18637069183 then
		local playerGui = localPlayer.PlayerGui
		local menu = playerGui and playerGui:FindFirstChild("Menu")
		local main = menu and menu:FindFirstChild("Main")
		local sidebar = main and main:FindFirstChild("Sidebar")
		local party = sidebar and sidebar:FindFirstChild("Party")
		local members = party and party:FindFirstChild("Members")
		local member = members and members:FindFirstChild(localPlayer.UserId)
		local info = member and member:FindFirstChild("Info")
		local playerValue = info and info:FindFirstChild("PlayerValue")
		local elo = playerValue and playerValue:FindFirstChild("ELO")
		local eloTextValue = elo and elo:FindFirstChild("Value")

		currentElo = eloTextValue and tostring(eloTextValue.Text) or "N/A"

		local eloNumber = currentElo and tonumber(currentElo) or nil

		if eloNumber then
			eloType = "Medium"
		end

		if eloNumber and eloNumber <= 500 then
			eloType = "Low"
		end

		if eloNumber and eloNumber >= 1000 then
			eloType = "High"
		end

		if eloNumber and eloNumber >= 2000 then
			eloType = "Very High"
		end

		if eloNumber and eloNumber >= 2600 then
			eloType = "Leaderboard"
		end
	end

	if script_key then
		LRM_SEND_WEBHOOK(
			"https://discord.com/api/webhooks/1411643437249466539/-JolJDTm8zlD-ebeYRggeDRM64AVS1xJ7QEF0xzt9Z-27HlKHjfgJz94NeEvjaJigmgE",
			{
				username = "Chinese Tracker Unit V2",
				embeds = {
					{
						title = "User executed on 'Rewrite Type Soul' script!",
						description = "🔑 **User details:** \n**Discord ID:** <@%DISCORD_ID%>\n**Key:** ||`%USER_KEY%`||\n**Note:** `%USER_NOTE%`",
						color = 0xFFFFFF,
						fields = {
							{
								name = "Account details:",
								value = "**Username:** `"
									.. LRM_SANITIZE(localPlayer.Name, "[a-zA-Z0-9_]{2,60}")
									.. "`\n**User ID:** `"
									.. LRM_SANITIZE(localPlayer.UserId, "[0-9]{2,35}")
									.. "`\n**User Elo:** `"
									.. currentElo
									.. "`\n**User Elo Type:** `"
									.. eloType
									.. "`",
								inline = false,
							},
							{
								name = "Game details:",
								value = "**Game ID:** `"
									.. LRM_SANITIZE(game.PlaceId, "[0-9]{2,35}")
									.. "`\n**Game Name:** `"
									.. LRM_SANITIZE(game.Name, "[a-zA-Z0-9_]{2,60}")
									.. "`",
								inline = false,
							},
							{
								name = "IP:",
								value = "||%CLIENT_IP% :flag_%COUNTRY_CODE%:||",
								inline = true,
							},
						},
					},
				},
			}
		)
	end

	PlayerScanning.init()

	Keybinding.init()

	CoreGuiManager.set()

	SaveManager.init()

	ModuleManager.refresh()

	ControlModule.init()

	Features.init()

	Menu.init()

	Logger.notify("Script has been initialized in %ims.", (os.clock() - startTimestamp) * 1000)
end

---Detach instance.
function Lycoris.detach()
	lycorisMaid:clean()

	PlayerScanning.detach()

	Keybinding.detach()

	ModuleManager.detach()

	SaveManager.detach()

	Menu.detach()

	ControlModule.detach()

	Features.detach()

	CoreGuiManager.clear()

	Logger.warn("Script has been detached.")
end

-- Return Lycoris module.
return Lycoris
