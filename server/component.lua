_DRUGS = _DRUGS or {}
local _addictionTemplate = {
	Meth = {
		LastUse = false,
		Factor = 0.0,
	},
	Coke = {
		LastUse = false,
		Factor = 0.0,
	},
	Moonshine = {
		LastUse = false,
		Factor = 0.0,
	},
}

function table.copy(t)
	local u = {}
	for k, v in pairs(t) do
		u[k] = v
	end
	return setmetatable(u, getmetatable(t))
end

CreateThread(function()
	RegisterItemUse()
	RunDegenThread()

	plsr.Middleware:Add("Characters:Spawning", function(source)
		local char = plsr.Fetch:CharacterSource(source)
		if char ~= nil then
			local addictions = char:GetData("Addiction")
			if char:GetData("Addiction") == nil then
				char:SetData("Addiction", _addictionTemplate)
			else
				for k, v in pairs(_addictionTemplate) do
					if addictions[k] == nil then
						addictions[k] = table.copy(v)
					end
				end
				char:SetData("Addiction", addictions)
			end
		end
	end, 1)

	TriggerEvent("Drugs:Server:Startup")
	TriggerEvent("Drugs:Server:StartCookThreads")
end)

AddEventHandler("Proxy:Shared:RegisterReady", function()
	exports["pulsar_core"]:RegisterComponent("Drugs", _DRUGS)
end)
