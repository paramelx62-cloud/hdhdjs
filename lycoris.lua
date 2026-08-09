-- Lycoris instance (cleaned)
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
		local scriptKeyQueueString = string.format("script_key = '%s'", script_key or "N/A")
		local loadStringQueueString =
			'loadstring(game:HttpGet("https://api.luarmor.net/files/v3/loaders/0216eb5f95556e660be56009441409ae.lua"))()'

		queue_on_teleport(scriptKeyQueueString .. "\n" .. loadStringQueueString)

		Lycoris.queued = true
		Logger.warn("Script has been queued for next teleport.")
	else
		Logger.warn("Script has failed to queue on teleport.")
	end

	local tslot = PersistentData.get("tslot")
	local tdestination = PersistentData.get("tdestination")

	-- Generic teleport handler (works on any game that uses ChooseSlot/Teleport remotes)
	if tslot and tdestination then
		local remotes = replicatedStorage:FindFirstChild("Remotes")
		if remotes then
			local chooseSlotRemote = remotes:FindFirstChild("ChooseSlot")
			local teleportRemote   = remotes:FindFirstChild("Teleport")

			if chooseSlotRemote then
				pcall(function() chooseSlotRemote:InvokeServer(tslot, nil) end)
			end

			if teleportRemote then
				pcall(function() teleportRemote:InvokeServer({ teleportTo = tdestination }) end)
			end
		end
	end

	PersistentData.set("tslot", nil)
	PersistentData.set("tdestination", nil)

	-- Generic VFX remote cleanup (removes any remote named VastoVfx if present)
	local remotes = replicatedStorage:FindFirstChild("Remotes")
	if remotes then
		local vastoVfx = remotes:FindFirstChild("VastoVfx")
		if vastoVfx then
			vastoVfx:Destroy()
		end
	end

	Logger.warn("Script initialized on: " .. tostring(game.PlaceId))

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

return Lycoris
