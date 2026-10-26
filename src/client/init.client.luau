--!strict
-- Spellcraft Arena client entry point. Same two-phase bootstrap as the
-- server: init() every controller, then start() every controller.

local ORDER = {
	"ClientState",
	"LightingController",
	"AudioController",
	"HudController",
	"PartyController",
	"MapVoteController",
	"MenuController",
	"CrateController",
	"DraftController",
	"PlacementController",
	"ReticleController",
	"CursorController",
	"DrawController",
	"InputController",
	"EffectsController",
	"JuiceController",
	"FxController",
	"HealthController",
	"SettingsController",
	"AdminController",
	"SupportController",
	"SpectateController",
	"DashController",
	"MobileController",
	"PresentationController",
	"TutorialController",
}

local Controllers = script:WaitForChild("Controllers")
local loaded: { any } = {}
for _, name in ORDER do
	local module = Controllers:WaitForChild(name)
	table.insert(loaded, require(module) :: any)
end

for _, controller in loaded do
	if typeof(controller.init) == "function" then
		controller.init()
	end
end

for _, controller in loaded do
	if typeof(controller.start) == "function" then
		task.spawn(controller.start)
	end
end
