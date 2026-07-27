_placedStills = {}
_inProgBrews = {}
_placedBarrels = {}
_inProgAges = {}
_stillHeat = {}
_lastAlertTime = {}
_activeDeliveries = {}

local bought = {}

local year = os.date("%Y")
local month = os.date("%m")
local _toolsForSale = {
	{ id = 1, item = "moonshine_still", coin = "MALD", price = 60, qty = 5, vpn = true, limited = {
        id = year + month,
        qty = 5,
    } },
}

local function GetRecipeById(recipeId)
	for k, v in ipairs(_moonshineRecipes) do
		if v.id == recipeId then
			return v
		end
	end
	return nil
end

local function CheckRecipeUnlocked(source, recipeId)
	local rep = plsr.Reputation:GetLevel(source, "Moonshine") or 0
	local requiredRep = _reputationSystem.unlockRecipes[recipeId] or 0
	return rep >= requiredRep
end

local function CalculateQuality(recipe, skillChecks, stillTier, temperature, weather, skillLevel)
	local baseQuality = recipe.baseQuality
	local factors = _qualityFactors

	local skillContribution = math.min(skillLevel / 1000, 1.0) * 30 * factors.skillMultiplier

	local checkSuccessRate = skillChecks.success / skillChecks.total
	local checkContribution = checkSuccessRate * 25 * factors.skillChecks

	local tierContribution = (_stillTiers[stillTier]?.efficiency or 0.75) * 10 * factors.stillTier

	local tempContribution = 0
	if temperature >= _temperatureEffects.optimal.min and temperature <= _temperatureEffects.optimal.max then
		tempContribution = 15 * factors.temperature
	elseif temperature >= _temperatureEffects.good.min and temperature <= _temperatureEffects.good.max then
		tempContribution = 10 * factors.temperature
	elseif temperature >= _temperatureEffects.poor.min and temperature <= _temperatureEffects.poor.max then
		tempContribution = 5 * factors.temperature
	else
		tempContribution = -10 * factors.temperature
	end

	local weatherMod = _weatherEffects[weather] or 1.0

	local quality = baseQuality + skillContribution + checkContribution + tierContribution + tempContribution
	quality = quality * weatherMod
	quality = quality * (_stillTiers[stillTier]?.efficiency or 0.75)

	return math.max(1, math.min(100, math.floor(quality)))
end

-- reads the real, server-authoritative weather/hour instead of trusting anything the client sends
local function GetCurrentConditions()
	local weatherRaw = GlobalState["Sync:Weather"] or "CLEAR"
	local weatherMap = {
		RAIN = "rain",
		THUNDER = "thunder",
		FOGGY = "foggy",
		CLOUDS = "clouds",
		OVERCAST = "clouds",
		CLEARING = "clouds",
		SNOW = "snow",
		SNOWLIGHT = "snow",
		BLIZZARD = "snow",
		XMAS = "snow",
	}
	local weather = weatherMap[weatherRaw] or "clear"

	local hour = (GlobalState["Sync:Time"] and GlobalState["Sync:Time"].hour) or 12
	local temperature = 20
	if hour >= 6 and hour < 12 then
		temperature = 15 + math.random(0, 10)
	elseif hour >= 12 and hour < 18 then
		temperature = 20 + math.random(0, 15)
	elseif hour >= 18 and hour < 22 then
		temperature = 15 + math.random(0, 10)
	else
		temperature = 5 + math.random(0, 10)
	end

	return temperature, weather
end

local function AddHeatToStill(stillId, amount)
	_stillHeat[stillId] = math.min((_stillHeat[stillId] or 0) + amount, _policeDetection.maxHeat)
	return _stillHeat[stillId]
end

-- returns true on a plain alert (police notified, no consequence), "raid" if the still gets destroyed
local function CheckPoliceAlert(coords, stillId)
	local heat = _stillHeat[stillId] or 0

	if heat >= _policeDetection.alertThreshold then
		local lastAlert = _lastAlertTime[stillId] or 0
		if os.time() - lastAlert > _policeDetection.alertCooldown then
			_lastAlertTime[stillId] = os.time()

			for _, playerId in ipairs(GetPlayers()) do
				local source = tonumber(playerId)
				if plsr.State:Player(source).onDuty == "police" then
					TriggerClientEvent("Drugs:Client:Moonshine:PoliceAlert", source, {
						coords = coords,
						heat = heat,
						stillId = stillId,
					})
				end
			end

			return true
		end
	end

	if heat >= _policeDetection.raidThreshold and math.random() < _policeDetection.raidChance then
		return "raid"
	end

	return false
end

_DRUGS = _DRUGS or {}
_DRUGS.Moonshine = {
    Still = {
        Generate = function(self, tier)
            return MySQL.insert.await('INSERT INTO moonshine_stills (created, tier) VALUES(?, ?)', { os.time(), tier })
        end,
        Get = function(self, stillId)
            return MySQL.single.await('SELECT id, tier, created, cooldown, active_cook FROM moonshine_stills WHERE id = ?', { stillId })
        end,
        IsPlaced = function(self, stillId)
            return MySQL.scalar.await('SELECT COUNT(still_id) as Count FROM placed_moonshine_stills WHERE still_id = ?', { stillId }) > 0
        end,
        CreatePlaced = function(self, stillId, owner, tier, coords, heading, created)
            local itemInfo = plsr.Inventory.Items:GetData("moonshine_still")
            local stillData = _DRUGS.Moonshine.Still:Get(stillId)

            MySQL.insert.await("INSERT INTO placed_moonshine_stills (still_id, owner, placed, expires, coords, heading) VALUES(?, ?, ?, ?, ?, ?)", {
                stillId,
                owner,
                os.time(),
                created + itemInfo.durability,
                json.encode(coords),
                heading,
            })

            local cookData = stillData.active_cook ~= nil and json.decode(stillData.active_cook) or {}

            _placedStills[stillId] = {
                id = stillId,
                owner = owner,
                tier = tier,
                placed = os.time(),
                expires = created + itemInfo.durability,
                cooldown = stillData.cooldown,
                activeBrew = stillData.active_cook ~= nil,
                pickupReady = os.time() > (cookData?.end_time or 0),
                coords = coords,
                heading = heading,
            }

            TriggerClientEvent("Drugs:Client:Moonshine:CreateStill", -1, _placedStills[stillId])
        end,
        RemovePlaced = function(self, stillId)
            local s = MySQL.query.await('DELETE FROM placed_moonshine_stills WHERE still_id = ?', { stillId })
            if s.affectedRows > 0 then
                _placedStills[stillId] = nil
                _stillHeat[stillId] = nil
                _lastAlertTime[stillId] = nil
                TriggerClientEvent("Drugs:Client:Moonshine:RemoveStill", -1, stillId)
            end
            return s.affectedRows > 0
        end,
        StartCook = function(self, stillId, cooldown, results)
            MySQL.query.await('UPDATE moonshine_stills SET cooldown = ?, active_cook = ? WHERE id = ?', { cooldown, json.encode(results), stillId })
            _placedStills[stillId].cooldown = cooldown
            _placedStills[stillId].activeBrew = true
            _placedStills[stillId].pickupReady = false
            _inProgBrews[stillId] = results

            TriggerClientEvent("Drugs:Client:Moonshine:UpdateStillData", -1, stillId, _placedStills[stillId])
        end,
        FinishCook = function(self, stillId)
            MySQL.query.await('UPDATE moonshine_stills SET active_cook = NULL WHERE id = ?', { stillId })
            _placedStills[stillId].activeBrew = false
            _placedStills[stillId].pickupReady = false
            _inProgBrews[stillId] = nil
            TriggerClientEvent("Drugs:Client:Moonshine:UpdateStillData", -1, stillId, _placedStills[stillId])
        end,
        Upgrade = function(self, stillId, tier)
            MySQL.query.await('UPDATE moonshine_stills SET tier = ? WHERE id = ?', { tier, stillId })
            _placedStills[stillId].tier = tier
        end,
    },
    Barrel = {
        Generate = function(self)
            return {
                Quality = math.random(1, 100),
                Drinks = math.random(15, 30),
            }
        end,
        IsPlaced = function(self, barrelId)
            return MySQL.scalar.await('SELECT COUNT(*) as Count FROM placed_moonshine_barrels WHERE barrel_id = ?', { barrelId }) > 0
        end,
        CreatePlaced = function(self, owner, coords, heading, created, brewData)
            local itemInfo = plsr.Inventory.Items:GetData("moonshine_barrel")
            local ready = os.time() + (GlobalState.IsProduction and (60 * 60 * 24 * 2) or _devAgingTime)

            local barrelId = MySQL.insert.await("INSERT INTO placed_moonshine_barrels (owner, placed, ready, expires, coords, heading, brew_data) VALUES(?, ?, ?, ?, ?, ?, ?)", {
                owner,
                os.time(),
                ready,
                created + itemInfo.durability,
                json.encode(coords),
                heading,
                json.encode(brewData),
            })

            _placedBarrels[barrelId] = {
                id = barrelId,
                owner = owner,
                placed = os.time(),
                ready = ready,
                expires = created + itemInfo.durability,
                pickupReady = false,
                coords = coords,
                heading = heading,
                brewData = brewData,
            }

            _inProgAges[barrelId] = ready

            TriggerClientEvent("Drugs:Client:Moonshine:CreateBarrel", -1, _placedBarrels[barrelId])
        end,
        RemovePlaced = function(self, barrelId)
            local s = MySQL.query.await('DELETE FROM placed_moonshine_barrels WHERE barrel_id = ?', { barrelId })
            if s.affectedRows > 0 then
                _placedBarrels[barrelId] = nil
                TriggerClientEvent("Drugs:Client:Moonshine:RemoveBarrel", -1, barrelId)
            end
            return s.affectedRows > 0
        end,
    },
}

AddEventHandler("Drugs:Server:Startup", function()
    MySQL.query.await("CREATE TABLE IF NOT EXISTS `moonshine_stills` (`id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY, `created` BIGINT NOT NULL, `tier` INT UNSIGNED NOT NULL DEFAULT 1, `cooldown` BIGINT NULL, `active_cook` JSON NULL)")
    MySQL.query.await("CREATE TABLE IF NOT EXISTS `placed_moonshine_stills` (`still_id` INT UNSIGNED PRIMARY KEY, `owner` VARCHAR(191) NOT NULL, `placed` BIGINT NOT NULL, `expires` BIGINT NOT NULL, `coords` JSON NOT NULL, `heading` FLOAT NOT NULL)")
    MySQL.query.await("CREATE TABLE IF NOT EXISTS `moonshine_barrels` (`id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY, `quality` INT UNSIGNED NOT NULL DEFAULT 1, `drinks` INT UNSIGNED NOT NULL DEFAULT 15)")
    MySQL.query.await("CREATE TABLE IF NOT EXISTS `placed_moonshine_barrels` (`barrel_id` INT UNSIGNED PRIMARY KEY, `owner` VARCHAR(191) NOT NULL, `placed` BIGINT NOT NULL, `ready` BIGINT NOT NULL, `expires` BIGINT NOT NULL, `coords` JSON NOT NULL, `heading` FLOAT NOT NULL, `brew_data` JSON NULL)")

    plsr.Reputation:Create("Moonshine", "Moonshine Brewing", {
        { label = "Novice", value = 100 },
        { label = "Apprentice", value = 500 },
        { label = "Journeyman", value = 1500 },
        { label = "Expert", value = 3000 },
        { label = "Master", value = 5000 },
        { label = "Grandmaster", value = 10000 },
    }, false)

    plsr.Vendor:Create("MoonshineSeller", "ped", "Karen", `S_F_Y_Bartender_01`, {
        coords = vector3(755.504, -1860.620, 48.292),
        heading = 307.963,
        scenario = "WORLD_HUMAN_SMOKING"
    }, _toolsForSale, "jar", "View Offers", false, false, true)

    -- separate ped: sells finished moonshine via the delivery/dealer menu, not the tool shop above
    TriggerClientEvent("Drugs:Client:Moonshine:CreateDealer", -1, {
        id = "MoonshineDealer",
        model = `S_M_Y_Dealer_01`,
        coords = vector3(772.220, -1862.930, 48.089),
        heading = 130.0,
        scenario = "WORLD_HUMAN_SMOKING",
    })

    local stills = MySQL.query.await('SELECT * FROM placed_moonshine_stills WHERE expires > ?', { os.time() })
    for k, v in ipairs(stills) do
        if _placedStills[v.still_id] == nil then
            local stillData = plsr.Drugs.Moonshine.Still:Get(v.still_id)

            if stillData ~= nil then
                local coords = json.decode(v.coords)

                local cookData = stillData.active_cook ~= nil and json.decode(stillData.active_cook) or {}
                _placedStills[v.still_id] = {
                    id = v.still_id,
                    owner = v.owner,
                    tier = stillData.tier,
                    placed = v.placed,
                    expires = v.expires,
                    cooldown = stillData.cooldown,
                    activeBrew = stillData.active_cook ~= nil,
                    pickupReady = os.time() > (cookData?.end_time or 0),
                    coords = coords,
                    heading = v.heading,
                }

                if stillData.active_cook then
                    local f = json.decode(stillData.active_cook)
                    if f.end_time > os.time() then
                        _inProgBrews[v.still_id] = f
                    end
                end
            end
        end
    end

    plsr.Logger:Trace("Drugs:Moonshine", string.format("Restored ^2%s^7 Moonshine Stills", #stills))

    local barrels = MySQL.query.await('SELECT * FROM placed_moonshine_barrels WHERE expires > ?', { os.time() })
    for k, v in ipairs(barrels) do
        if _placedBarrels[v.barrel_id] == nil then
            local coords = json.decode(v.coords)

            _placedBarrels[v.barrel_id] = {
                id = v.barrel_id,
                owner = v.owner,
                placed = v.placed,
                ready = v.ready,
                expires = v.expires,
                pickupReady = os.time() > (v.ready or 0),
                coords = coords,
                heading = v.heading,
                brewData = json.decode(v.brew_data),
            }

            if v.ready > os.time() then
                _inProgAges[v.barrel_id] = v.ready
            end
        end
    end

    plsr.Logger:Trace("Drugs:Moonshine", string.format("Restored ^2%s^7 Moonshine Barrels", #barrels))

    plsr.Middleware:Add("Characters:Spawning", function(source)
        TriggerLatentClientEvent("Drugs:Client:Moonshine:SetupStills", source, 50000, _placedStills)
        TriggerLatentClientEvent("Drugs:Client:Moonshine:SetupBarrels", source, 50000, _placedBarrels)
    end, 1)

    plsr.Callbacks:RegisterServerCallback("Drugs:Moonshine:FinishStillPlacement", function(source, data, cb)
        local char = plsr.Fetch:CharacterSource(source)
        if char ~= nil then
            local still = plsr.Inventory:GetItem(data.data)
            if still.Owner == tostring(char:GetData("SID")) then
                local md = still.MetaData
                local stillData = plsr.Drugs.Moonshine.Still:Get(md.Still)
                if plsr.Inventory.Items:RemoveId(char:GetData("SID"), 1, still) then
                    plsr.Drugs.Moonshine.Still:CreatePlaced(md.Still, char:GetData("SID"), stillData.tier, data.endCoords.coords, data.endCoords.rotation, still.CreateDate)
                    cb(true)
                else
                    cb(false)
                end
            end
        else
            cb(false)
        end
    end)

    plsr.Callbacks:RegisterServerCallback("Drugs:Moonshine:PickupStill", function(source, data, cb)
        local char = plsr.Fetch:CharacterSource(source)
        if char ~= nil then
            if data then
                if plsr.Drugs.Moonshine.Still:IsPlaced(data) then
                    local stillData = plsr.Drugs.Moonshine.Still:Get(data)
                    if plsr.State:Player(source).onDuty == "police" or stillData.owner == char:GetData("SID") then
                        if plsr.Drugs.Moonshine.Still:RemovePlaced(data) then
                            cb(true)
                        else
                            cb(false)
                        end
                    else
                        cb(false)
                    end
                else
                    cb(false)
                end
            else
                cb(false)
            end
        else
            cb(false)
        end
    end)

    plsr.Callbacks:RegisterServerCallback("Drugs:Moonshine:CheckStill", function(source, data, cb)
        local char = plsr.Fetch:CharacterSource(source)
        if char ~= nil then
            if data and _placedStills[data] ~= nil then
                if _placedStills[data].cooldown == nil or os.time() > _placedStills[data].cooldown then
                    cb(true)
                else
                    cb(false)
                end
            else
                cb(false)
            end
        else
            cb(false)
        end
    end)

    -- returns every recipe with its `unlocked` state for this player, used by the recipe-select menu
    plsr.Callbacks:RegisterServerCallback("Drugs:Moonshine:GetRecipes", function(source, data, cb)
        local char = plsr.Fetch:CharacterSource(source)
        if not char then
            cb(false)
            return
        end

        local recipes = {}
        for k, recipe in ipairs(_moonshineRecipes) do
            table.insert(recipes, {
                id = recipe.id,
                label = recipe.label,
                description = recipe.description,
                ingredients = recipe.ingredients,
                baseQuality = recipe.baseQuality,
                difficulty = recipe.difficulty,
                unlocked = CheckRecipeUnlocked(source, recipe.id),
                requiredRep = _reputationSystem.unlockRecipes[recipe.id] or 0,
            })
        end

        cb({ recipes = recipes, reputation = plsr.Reputation:GetLevel(source, "Moonshine") or 0 })
    end)

    plsr.Callbacks:RegisterServerCallback("Drugs:Moonshine:StartCooking", function(source, data, cb)
        local char = plsr.Fetch:CharacterSource(source)
        if char == nil then
            cb(false)
            return
        end

        if not data or not _placedStills[data.stillId] then
            cb(false)
            return
        end

        local still = _placedStills[data.stillId]
        if still.cooldown ~= nil and os.time() <= still.cooldown then
            cb(false)
            return
        end

        local recipe = GetRecipeById(data.recipeId or "classic")
        if not recipe then
            plsr.Execute:Client(source, "Notification", "Error", "Invalid Recipe")
            cb(false)
            return
        end

        if not CheckRecipeUnlocked(source, recipe.id) then
            plsr.Execute:Client(source, "Notification", "Error", string.format("Recipe Locked, Need %s Reputation", _reputationSystem.unlockRecipes[recipe.id] or 0))
            cb(false)
            return
        end

        if not data.results or not data.results.success or not data.results.total then
            cb(false)
            return
        end

        local sid = char:GetData("SID")
        for k, ingredient in ipairs(recipe.ingredients) do
            if not plsr.Inventory.Items:Has(sid, 1, ingredient.item, ingredient.amount) then
                plsr.Execute:Client(source, "Notification", "Error", string.format("Missing %s %s", ingredient.amount, ingredient.item))
                cb(false)
                return
            end
        end

        for k, ingredient in ipairs(recipe.ingredients) do
            plsr.Inventory.Items:Remove(sid, 1, ingredient.item, ingredient.amount, false)
        end

        local stillData = plsr.Drugs.Moonshine.Still:Get(data.stillId)
        local temperature, weather = GetCurrentConditions()
        local skillLevel = plsr.Reputation:GetLevel(source, "Moonshine") or 0
        local quality = CalculateQuality(recipe, data.results, stillData.tier, temperature, weather, skillLevel)

        local heat = AddHeatToStill(data.stillId, _policeDetection.heatPerBrew)
        local alertResult = CheckPoliceAlert(still.coords, data.stillId)
        if alertResult == "raid" then
            plsr.Execute:Client(source, "Notification", "Error", "Police Raid! Your Still Has Been Destroyed!")
            plsr.Reputation.Modify:Remove(source, "Moonshine", _reputationSystem.repLossOnRaid)
            plsr.Drugs.Moonshine.Still:RemovePlaced(data.stillId)
            cb(false)
            return
        end

        local cookTime = _stillTiers[stillData.tier]?.cookTime or 30
        local cookSeconds = GlobalState.IsProduction and (60 * cookTime) or _devCookTime
        plsr.Drugs.Moonshine.Still:StartCook(data.stillId, os.time() + (60 * 60 * 2), {
            start_time = os.time(),
            end_time = os.time() + cookSeconds,
            quality = quality,
            recipe = recipe.id,
            heat = heat,
        })

        plsr.Execute:Client(source, "Notification", "Success", string.format("Brew Started, Quality %s/100, Ready In %s", quality, GlobalState.IsProduction and (cookTime .. " Minutes") or (cookSeconds .. " Seconds")))
        cb(true)
    end)

    plsr.Callbacks:RegisterServerCallback("Drugs:Moonshine:PickupCook", function(source, data, cb)
        local char = plsr.Fetch:CharacterSource(source)
        if char ~= nil then
            if data and _placedStills[data] ~= nil then
                local stillData = plsr.Drugs.Moonshine.Still:Get(data)
                if stillData.active_cook ~= nil then
                    local cookData = json.decode(stillData.active_cook)
                    if os.time() > cookData.end_time then
                        local recipe = GetRecipeById(cookData.recipe or "classic")
                        if plsr.Inventory:AddItem(char:GetData("SID"), "moonshine_barrel", 1, {
                            Brew = {
                                Quality = cookData.quality,
                                Drinks = math.random(15, 30),
                                Recipe = cookData.recipe or "classic",
                            }
                        }, 1, false, false, false, false, false, false, false) then
                            plsr.Drugs.Moonshine.Still:FinishCook(data)
                            plsr.Reputation.Modify:Add(source, "Moonshine", _reputationSystem.repPerBrew)
                            plsr.Execute:Client(source, "Notification", "Success", string.format("Brew Complete! Quality %s/100, Reputation +%s", cookData.quality, _reputationSystem.repPerBrew))
                            cb(true)
                        else
                            cb(false)
                        end
                    else
                        cb(false)
                    end
                else
                    cb(false)
                end
            else
                cb(false)
            end
        else
            cb(false)
        end
    end)

    plsr.Callbacks:RegisterServerCallback("Drugs:Moonshine:GetStillDetails", function(source, data, cb)
        local char = plsr.Fetch:CharacterSource(source)
        if char ~= nil then
            if data and _placedStills[data] ~= nil then
                local stillData = plsr.Drugs.Moonshine.Still:Get(data)

                local menu = {
                    main = {
                        label = "Still Information",
                        items = {}
                    },
                }

                if stillData.cooldown ~= nil then
                    local timeUntil = stillData.cooldown - os.time()
                    if timeUntil > 0 then
                        table.insert(menu.main.items, {
                            label = "On Cooldown",
                            description = string.format("Available %s (in about %s)</li>", os.date("%m/%d/%Y %I:%M %p", stillData.cooldown), GetFormattedTimeFromSeconds(timeUntil)),
                        })
                    else
                        table.insert(menu.main.items, {
                            label = "Cooldown Expired",
                            description = string.format("Expired at %s</li>", os.date("%m/%d/%Y %I:%M %p", stillData.cooldown)),
                        })
                    end
                else
                    table.insert(menu.main.items, {
                        label = "Not On Cooldown",
                        description = string.format("No Cooldown Information Available"),
                    })
                end

                if stillData.active_cook ~= nil then
                    local cook = json.decode(stillData.active_cook)

                    local timeUntil = cook.end_time - os.time()
                    if timeUntil > 0 then
                        table.insert(menu.main.items, {
                            label = "Brew Status",
                            description = string.format("Finishes at %s (in about %s)", os.date("%m/%d/%Y %I:%M %p", cook.end_time), GetFormattedTimeFromSeconds(timeUntil)),
                        })
                    else
                        table.insert(menu.main.items, {
                            label = "Brew Status",
                            description = string.format("Finished at %s", os.date("%m/%d/%Y %I:%M %p", cook.end_time)),
                        })
                    end
                else
                    table.insert(menu.main.items, {
                        label = "Brew Status",
                        description = string.format("No Active Brew"),
                    })
                end

                table.insert(menu.main.items, {
                    label = "Still Tier",
                    description = string.format("%s (%s)", _stillTiers[stillData.tier]?.label or "Unknown", stillData.tier),
                })

                table.insert(menu.main.items, {
                    label = "Police Heat",
                    description = string.format("%s/100", _stillHeat[data] or 0),
                })

                cb(menu)
            else
                cb(false)
            end
        else
            cb(false)
        end
    end)

    plsr.Callbacks:RegisterServerCallback("Drugs:Moonshine:UpgradeStill", function(source, data, cb)
        local char = plsr.Fetch:CharacterSource(source)
        if not char or not data or not _placedStills[data] then
            cb(false)
            return
        end

        local stillData = plsr.Drugs.Moonshine.Still:Get(data)
        local nextTier = stillData.tier + 1
        if not _stillTiers[nextTier] then
            plsr.Execute:Client(source, "Notification", "Error", "Still Is Already At Maximum Tier")
            cb(false)
            return
        end

        local requiredRep = _upgradeSystem.requireRep[nextTier] or 0
        if (plsr.Reputation:GetLevel(source, "Moonshine") or 0) < requiredRep then
            plsr.Execute:Client(source, "Notification", "Error", string.format("Need %s Reputation To Upgrade", requiredRep))
            cb(false)
            return
        end

        local cost = _stillTiers[nextTier].upgradeCost
        if cost > 0 then
            local account = plsr.Banking.Accounts:GetPersonal(char:GetData("SID"))
            if not account or not plsr.Banking.Balance:Has(account.Account, cost) then
                plsr.Execute:Client(source, "Notification", "Error", string.format("Need $%s To Upgrade", cost))
                cb(false)
                return
            end

            plsr.Banking.Balance:Withdraw(account.Account, cost, {
                type = "moonshine_upgrade",
                title = "Moonshine Still Upgrade",
                description = "Moonshine Still Upgrade",
            })
        end

        plsr.Drugs.Moonshine.Still:Upgrade(data, nextTier)
        plsr.Execute:Client(source, "Notification", "Success", string.format("Still Upgraded To %s!", _stillTiers[nextTier].label))
        cb(true)
    end)

    plsr.Callbacks:RegisterServerCallback("Drugs:Moonshine:FinishBarrelPlacement", function(source, data, cb)
        local char = plsr.Fetch:CharacterSource(source)
        if char ~= nil then
            local barrel = plsr.Inventory:GetItem(data.data)
            if barrel.Owner == tostring(char:GetData("SID")) then
                local md = barrel.MetaData
                if plsr.Inventory.Items:RemoveId(char:GetData("SID"), 1, barrel) then
                    plsr.Drugs.Moonshine.Barrel:CreatePlaced(char:GetData("SID"), data.endCoords.coords, data.endCoords.rotation, os.time(), md.Brew)
                    cb(true)
                else
                    cb(false)
                end
            end
        else
            cb(false)
        end
    end)

    plsr.Callbacks:RegisterServerCallback("Drugs:Moonshine:PickupBarrel", function(source, data, cb)
        local char = plsr.Fetch:CharacterSource(source)
        if char ~= nil then
            if data then
                if plsr.Drugs.Moonshine.Barrel:IsPlaced(data) then
                    if plsr.State:Player(source).onDuty == "police" or _placedBarrels[data]?.owner == char:GetData("SID") then
                        if plsr.Drugs.Moonshine.Barrel:RemovePlaced(data) then
                            cb(true)
                        else
                            cb(false)
                        end
                    else
                        cb(false)
                    end
                else
                    cb(false)
                end
            else
                cb(false)
            end
        else
            cb(false)
        end
    end)

    plsr.Callbacks:RegisterServerCallback("Drugs:Moonshine:GetBarrelDetails", function(source, data, cb)
        local char = plsr.Fetch:CharacterSource(source)
        if char ~= nil then
            if data and _placedBarrels[data] ~= nil then
                local menu = {
                    main = {
                        label = "Oak Barrel Information",
                        items = {}
                    },
                }

                if os.time() > _placedBarrels[data]?.ready or 0 then
                    local timeUntil = _placedBarrels[data]?.ready - os.time()
                    table.insert(menu.main.items, {
                        label = "Aging Process Still In Progress",
                        description = string.format("Finishes At %s (in about %s)", os.date("%m/%d/%Y %I:%M %p", _placedBarrels[data]?.ready), GetFormattedTimeFromSeconds(timeUntil)),
                    })
                else
                    local timeUntil = _placedBarrels[data]?.ready - os.time()
                    table.insert(menu.main.items, {
                        label = "Aging Process Finished",
                        description = string.format("Finished At %s", os.date("%m/%d/%Y %I:%M %p", _placedBarrels[data]?.ready)),
                    })
                end

                cb(menu)
            else
                cb(false)
            end
        else
            cb(false)
        end
    end)

    plsr.Callbacks:RegisterServerCallback("Drugs:Moonshine:PickupBrew", function(source, data, cb)
        local char = plsr.Fetch:CharacterSource(source)
        if char ~= nil then
            local sid = char:GetData("SID")
            if data and _placedBarrels[data] ~= nil then
                if _placedBarrels[data].owner == sid then
                    local drinks = _placedBarrels[data].brewData?.Drinks or 15
                    if plsr.Inventory.Items:Has(sid, 1, "moonshine_jar", drinks) then
                        if plsr.Inventory.Items:Remove(sid, 1, "moonshine_jar", drinks, false) then
                            local recipeId = _placedBarrels[data].brewData?.Recipe or "classic"
                            local recipe = GetRecipeById(recipeId)
                            if plsr.Inventory:AddItem(sid, "moonshine", drinks, {
                                Recipe = recipeId,
                                RecipeLabel = recipe and recipe.label or "Classic Moonshine",
                            }, 1, false, false, false, false, false, false, _placedBarrels[data].brewData?.Quality or math.random(1, 100)) then
                                plsr.Drugs.Moonshine.Barrel:RemovePlaced(data)
                                cb(true)
                            else
                                cb(false)
                            end
                        else
                            cb(false)
                        end
                    else
                        plsr.Execute:Client(source, "Notification", "Error", string.format("Missing Masson Jars, You Need %s Empty Jars", drinks))
                        cb(false)
                    end
                else
                    cb(false)
                end
            else
                cb(false)
            end
        else
            cb(false)
        end
    end)

    -- Delivery dealer: lets a player with enough moonshine on hand offload it via a multi-stop
    -- drop-off route, an instant reduced-price bulk sale, or (higher rep) a Cayo Perico route
    plsr.Callbacks:RegisterServerCallback("Drugs:Moonshine:GetDealerOptions", function(source, data, cb)
        local char = plsr.Fetch:CharacterSource(source)
        if not char then
            cb(false)
            return
        end

        local sid = char:GetData("SID")
        if not plsr.Inventory.Items:GetFirst(sid, "moonshine", 1) then
            plsr.Execute:Client(source, "Notification", "Error", "You Don't Have Any Moonshine To Sell")
            cb(false)
            return
        end

        local rep = plsr.Reputation:GetLevel(source, "Moonshine") or 0
        local isDevMode = not GlobalState.IsProduction
        cb({
            dropOff = {
                available = isDevMode or rep >= _deliverySystem.minRep,
                label = "Drop Off",
                description = "Deliver moonshine to customer locations",
            },
            bulkSale = {
                available = isDevMode or rep >= _deliverySystem.bulkSaleRep,
                label = "Bulk Sale",
                description = string.format("Sell all moonshine at %s%% price (lazy way)", math.floor(_deliverySystem.bulkSaleMultiplier * 100)),
            },
            travel = {
                available = isDevMode or rep >= _deliverySystem.travelRep,
                label = "Travel to Cayo Perico",
                description = "Bulk delivery to Cayo Perico island (extra rewards)",
            },
        })
    end)

    local function BuildStops(source, char, numStops, locationsPool)
        local sid = char:GetData("SID")
        local allMoonshine = plsr.Inventory.Items:GetAll(sid, "moonshine", 1)
        if not allMoonshine or #allMoonshine == 0 then
            return nil
        end

        local totalJars = 0
        for k, item in ipairs(allMoonshine) do
            totalJars = totalJars + (item.Count or 1)
        end
        if totalJars == 0 then
            return nil
        end

        local stops = {}
        local usedIndices = {}
        for i = 1, numStops do
            if totalJars <= 0 then
                break
            end

            local locationIndex, attempts = nil, 0
            repeat
                locationIndex = math.random(#locationsPool)
                attempts += 1
            until not usedIndices[locationIndex] or attempts > 50
            usedIndices[locationIndex] = true

            local jarsAtStop = math.min(math.random(_deliverySystem.minJarsPerStop, _deliverySystem.maxJarsPerStop), totalJars)
            totalJars -= jarsAtStop

            table.insert(stops, { coords = locationsPool[locationIndex], jars = jarsAtStop, completed = false })
        end

        return stops, allMoonshine
    end

    plsr.Callbacks:RegisterServerCallback("Drugs:Moonshine:DealerDropOff", function(source, data, cb)
        local char = plsr.Fetch:CharacterSource(source)
        if not char then
            cb(false)
            return
        end

        if GlobalState.IsProduction and (plsr.Reputation:GetLevel(source, "Moonshine") or 0) < _deliverySystem.minRep then
            plsr.Execute:Client(source, "Notification", "Error", string.format("Need %s Reputation For Drop Offs", _deliverySystem.minRep))
            cb(false)
            return
        end

        local numStops = math.random(_deliverySystem.minStops, _deliverySystem.maxStops)
        local stops, moonshineItems = BuildStops(source, char, numStops, _deliveryLocations)
        if not stops then
            plsr.Execute:Client(source, "Notification", "Error", "You Don't Have Any Moonshine")
            cb(false)
            return
        end

        local deliveryId = #_activeDeliveries + 1
        _activeDeliveries[deliveryId] = {
            id = deliveryId,
            source = source,
            sid = char:GetData("SID"),
            stops = stops,
            currentStop = 1,
            totalPayment = 0,
            expires = os.time() + _deliverySystem.deliveryTimeLimit,
            type = "dropoff",
        }

        cb({ id = deliveryId, stops = stops, timeLimit = _deliverySystem.deliveryTimeLimit })
    end)

    plsr.Callbacks:RegisterServerCallback("Drugs:Moonshine:DealerTravel", function(source, data, cb)
        local char = plsr.Fetch:CharacterSource(source)
        if not char then
            cb(false)
            return
        end

        if GlobalState.IsProduction and (plsr.Reputation:GetLevel(source, "Moonshine") or 0) < _deliverySystem.travelRep then
            plsr.Execute:Client(source, "Notification", "Error", string.format("Need %s Reputation For Travel Deliveries", _deliverySystem.travelRep))
            cb(false)
            return
        end

        local numStops = math.random(_deliverySystem.travelMinStops, _deliverySystem.travelMaxStops)
        local stops, moonshineItems = BuildStops(source, char, numStops, _cayoPericoLocations)
        if not stops then
            plsr.Execute:Client(source, "Notification", "Error", "You Don't Have Any Moonshine")
            cb(false)
            return
        end

        local deliveryId = #_activeDeliveries + 1
        _activeDeliveries[deliveryId] = {
            id = deliveryId,
            source = source,
            sid = char:GetData("SID"),
            stops = stops,
            currentStop = 1,
            totalPayment = 0,
            expires = os.time() + _deliverySystem.travelTime,
            type = "travel",
        }

        cb({ id = deliveryId, stops = stops, timeLimit = _deliverySystem.travelTime })
    end)

    plsr.Callbacks:RegisterServerCallback("Drugs:Moonshine:SellToPed", function(source, data, cb)
        local char = plsr.Fetch:CharacterSource(source)
        if not (char and data and data.deliveryId and data.stopIndex) then
            cb(false)
            return
        end

        local delivery = _activeDeliveries[data.deliveryId]
        if not delivery or delivery.source ~= source then
            cb(false)
            return
        end

        if os.time() > delivery.expires then
            plsr.Execute:Client(source, "Notification", "Error", "Delivery Expired!")
            _activeDeliveries[data.deliveryId] = nil
            cb(false)
            return
        end

        local stop = delivery.stops[data.stopIndex]
        if not stop or stop.completed then
            cb(false)
            return
        end

        local sid = char:GetData("SID")
        local allMoonshine = plsr.Inventory.Items:GetAll(sid, "moonshine", 1)
        if not allMoonshine or #allMoonshine == 0 then
            plsr.Execute:Client(source, "Notification", "Error", "You Don't Have Any Moonshine")
            cb(false)
            return
        end

        local jarsToRemove = stop.jars
        local totalPayment, removed = 0, 0
        local basePay = (delivery.type == "travel") and _deliverySystem.travelBasePayPerJar or _deliverySystem.basePayPerJar
        local payPerQuality = (delivery.type == "travel") and _deliverySystem.travelPayPerQualityPerJar or _deliverySystem.payPerQualityPerJar

        for k, item in ipairs(allMoonshine) do
            if removed >= jarsToRemove then
                break
            end

            local itemCount = item.Count or 1
            local toRemove = math.min(itemCount, jarsToRemove - removed)
            local quality = item.Quality or 50
            local itemPayment = (basePay + (quality * payPerQuality)) * toRemove

            if plsr.Inventory.Items:RemoveSlot(sid, item.Name, toRemove, item.Slot, 1) then
                totalPayment += itemPayment
                removed += toRemove
            end
        end

        if removed == 0 then
            cb(false)
            return
        end

        delivery.totalPayment += totalPayment
        stop.completed = true

        local repGain
        if delivery.type == "travel" then
            repGain = math.random(_deliverySystem.travelRepPerStop, _deliverySystem.travelRepPerStopMax)
        else
            repGain = math.random(3, 5)
        end
        plsr.Reputation.Modify:Add(source, "Moonshine", repGain)

        local allDone = true
        for k, s in ipairs(delivery.stops) do
            if not s.completed then
                allDone = false
                break
            end
        end

        if allDone then
            local account = plsr.Banking.Accounts:GetPersonal(sid)
            if account then
                local deliveryType = (delivery.type == "travel") and "Cayo Perico Delivery Route" or "Moonshine Delivery Route"
                plsr.Banking.Balance:Deposit(account.Account, math.floor(delivery.totalPayment), {
                    type = "moonshine_delivery",
                    title = deliveryType,
                    description = deliveryType,
                })
            end

            plsr.Execute:Client(source, "Notification", "Success", string.format("Delivery Route Complete! +$%s", math.floor(delivery.totalPayment)))
            _activeDeliveries[data.deliveryId] = nil
            cb({ completed = true, payment = math.floor(delivery.totalPayment), repGain = repGain })
        else
            delivery.currentStop += 1
            cb({ completed = false, nextStop = delivery.currentStop, repGain = repGain })
        end
    end)

    plsr.Callbacks:RegisterServerCallback("Drugs:Moonshine:DealerBulkSale", function(source, data, cb)
        local char = plsr.Fetch:CharacterSource(source)
        if not char then
            cb(false)
            return
        end

        if GlobalState.IsProduction and (plsr.Reputation:GetLevel(source, "Moonshine") or 0) < _deliverySystem.bulkSaleRep then
            plsr.Execute:Client(source, "Notification", "Error", string.format("Need %s Reputation For Bulk Sales", _deliverySystem.bulkSaleRep))
            cb(false)
            return
        end

        local sid = char:GetData("SID")
        local allMoonshine = plsr.Inventory.Items:GetAll(sid, "moonshine", 1)
        if not allMoonshine or #allMoonshine == 0 then
            plsr.Execute:Client(source, "Notification", "Error", "You Don't Have Any Moonshine")
            cb(false)
            return
        end

        local totalPayment, totalCount = 0, 0
        for k, item in ipairs(allMoonshine) do
            local quality = item.Quality or 50
            local itemCount = item.Count or 1
            local paymentPerJar = _deliverySystem.basePayPerJar + (quality * _deliverySystem.payPerQualityPerJar)
            totalPayment += (paymentPerJar * itemCount) * _deliverySystem.bulkSaleMultiplier
            totalCount += itemCount

            plsr.Inventory.Items:RemoveSlot(sid, item.Name, itemCount, item.Slot, 1)
        end

        local account = plsr.Banking.Accounts:GetPersonal(sid)
        if account then
            plsr.Banking.Balance:Deposit(account.Account, math.floor(totalPayment), {
                type = "moonshine_bulk_sale",
                title = "Moonshine Bulk Sale",
                description = "Moonshine Bulk Sale",
            })
        end

        plsr.Execute:Client(source, "Notification", "Success", string.format("Sold %s Moonshine For $%s (Bulk Sale)", totalCount, math.floor(totalPayment)))
        cb(true)
    end)
end)
