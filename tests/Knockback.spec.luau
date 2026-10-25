--!strict
-- Knockback (wind, Whirlwind, Tornado) pushes Battleground NPCs as well as
-- players: they go limp for a moment and are given the push velocity.

local CollectionService = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")

return function(t: any)
	t.describe("Knockback", function()
		local DestructibleService =
			require(ServerScriptService.Server.Services.DestructibleService) :: any

		local function fakeNpc(): (Model, BasePart, Humanoid)
			local model = Instance.new("Model")
			local root = Instance.new("Part")
			root.Name = "HumanoidRootPart"
			root.Anchored = false
			root.Parent = workspace
			root.Parent = model
			local humanoid = Instance.new("Humanoid")
			humanoid.Parent = model
			model:SetAttribute("Hostile", true)
			model:SetAttribute("NpcType", "Test")
			CollectionService:AddTag(model, "Destructible")
			model.PrimaryPart = root
			model.Parent = workspace
			root.Anchored = true
			root.CFrame = CFrame.new(0, 5000, 0)
			root.Anchored = false
			root.CanCollide = false
			return model, root, humanoid
		end

		t.it("pushes a Battleground NPC and staggers it, then lets it walk again", function()
			local model, root, humanoid = fakeNpc()
			root.AssemblyLinearVelocity = Vector3.zero
			DestructibleService.push(model, Vector3.new(0, 0, -40))
			t.expect(root.AssemblyLinearVelocity.Z < -30).toBeTruthy()
			t.expect(humanoid.PlatformStand).toBe(true)
			task.wait(1)
			t.expect(humanoid.PlatformStand).toBe(false)
			model:Destroy()
		end)

		t.it("does not push anchored things, plain props, or training dummies", function()
			local dummy = Instance.new("Model")
			dummy:SetAttribute("Dummy", true)
			CollectionService:AddTag(dummy, "Destructible")
			local post = Instance.new("Part")
			post.Name = "HumanoidRootPart"
			post.Anchored = true
			post.Parent = dummy
			dummy.Parent = workspace
			DestructibleService.push(dummy, Vector3.new(0, 0, -40))
			t.expect(post.AssemblyLinearVelocity.Magnitude).toBeNear(0, 0.001)
			dummy:Destroy()
		end)
	end)
end
