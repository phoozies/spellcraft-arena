--!strict
-- Wordcraft Arena client entry point. Same two-phase bootstrap as the
-- server: init() every controller, then start() every controller.

local ORDER = {
	"ClientState",
	"HudController",
	"MenuController",
	"CrateController",
	"DraftController",
	"PlacementController",
	"ReticleController",
	"DrawController",
	"InputController",
	"EffectsController",
	"FxController",
	"HealthController",
	"SettingsController",
	"PresentationController",
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
