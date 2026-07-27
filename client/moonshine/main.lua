_stills = {}
_barrels = {}
local _stillModels = {
    `prop_still`
}

local _barrelModels = {
    `prop_wooden_barrel`,
}

local function RunSkillChecks(total)
    local success = 0
    local failed = 0

    for i = 1, total do
        local p = promise.new()
        plsr.Minigame.Play:RoundSkillbar(1.15, 3, {
            onSuccess = function()
                success += 1
                Wait(50)
                p:resolve(true)
            end,
            onFail = function()
                failed += 1
                Wait(50)
                p:resolve(true)
            end,
        }, {
            useWhileDead = false,
            vehicle = false,
            controlDisables = {
                disableMovement = true,
                disableCarMovement = true,
                disableMouse = false,
                disableCombat = true,
            },
            animation = {
                anim = "dj",
            },
        })

        Citizen.Await(p)
    end

    return {
        total = total,
        success = success,
        failed = failed,
    }
end

AddEventHandler("Drugs:Client:Startup", function()
    for k, v in ipairs(_stillModels) do
        plsr.Targeting:AddObject(v, "kitchen-set", {
            {
                text = "Dismantle Still (Destroys Still)",
                icon = "hand",
                event = "Drugs:Client:Moonshine:PickupStill",
                minDist = 3.0,
                isEnabled = function(data, entity)
                    local entState = Entity(entity.entity).state
                    return entState?.isMoonshineStill and (plsr.State.flags.onDuty == "police" or _barrels[entState?.stillId]?.owner == plsr.State.character.SID)
                end,
            },
            {
                text = "Still Info",
                icon = "circle-info",
                event = "Drugs:Client:Moonshine:StillDetails",
                minDist = 3.0,
                isEnabled = function(data, entity)
                    return Entity(entity.entity).state?.isMoonshineStill
                end,
            },
            {
                text = "Upgrade Still",
                icon = "wrench",
                event = "Drugs:Client:Moonshine:UpgradeStill",
                minDist = 3.0,
                isEnabled = function(data, entity)
                    local entState = Entity(entity.entity).state
                    return entState?.isMoonshineStill and (_stills[entState.stillId]?.owner == nil or _stills[entState.stillId]?.owner == plsr.State.character.SID)
                end,
            },
            {
                text = "Start Brewing",
                icon = "timer",
                event = "Drugs:Client:Moonshine:StartCook",
                minDist = 3.0,
                isEnabled = function(data, entity)
                    local entState = Entity(entity.entity).state
                    return entState?.isMoonshineStill and not _stills[entState.stillId]?.activeBrew and (not _stills[entState.stillId]?.cooldown or GetCloudTimeAsInt() > _stills[entState.stillId]?.cooldown) and (_stills[entState.stillId].owner == nil or _stills[entState.stillId].owner == plsr.State.character.SID)
                end,
            },
            {
                text = "Collect Brew",
                icon = "block",
                event = "Drugs:Client:Moonshine:PickupCook",
                minDist = 3.0,
                isEnabled = function(data, entity)
                    local entState = Entity(entity.entity).state
                    return entState?.isMoonshineStill and _stills[entState.stillId]?.activeBrew and _stills[entState.stillId]?.pickupReady and (_stills[entState.stillId]?.owner == nil or _stills[entState.stillId]?.owner == plsr.State.character.SID)
                end,
            },
        }, 3.0)
    end

    for k, v in ipairs(_barrelModels) do
        plsr.Targeting:AddObject(v, "prescription-bottle", {
            {
                text = "Destroy Barrel",
                icon = "hand",
                event = "Drugs:Client:Moonshine:PickupBarrel",
                minDist = 3.0,
                isEnabled = function(data, entity)
                    local entState = Entity(entity.entity).state
                    return entState?.isMoonshineBarrel and (plsr.State.flags.onDuty == "police" or _barrels[entState?.barrelId]?.owner == plsr.State.character.SID)
                end,
            },
            {
                text = "Barrel Info",
                icon = "block",
                event = "Drugs:Client:Moonshine:BarrelDetails",
                minDist = 3.0,
                isEnabled = function(data, entity)
                    return Entity(entity.entity).state?.isMoonshineBarrel
                end,
            },
            {
                text = "Fill Jars",
                textFunc = function(data, entity)
                    local entState = Entity(entity.entity).state
                    return string.format("Fill Jars (Requires %s Empty Jars)", (_barrels[entState.barrelId]?.brewData?.Drinks or 15))
                end,
                icon = "block",
                event = "Drugs:Client:Moonshine:PickupBrew",
                minDist = 3.0,
                isEnabled = function(data, entity)
                    local entState = Entity(entity.entity).state
                    return entState?.isMoonshineBarrel and _barrels[entState.barrelId]?.pickupReady and (_barrels[entState.barrelId]?.owner == nil or _barrels[entState.barrelId]?.owner == plsr.State.character.SID)
                end,
            },
        }, 3.0)
    end

    plsr.Callbacks:RegisterClientCallback("Drugs:Moonshine:PlaceStill", function(data, cb)
        plsr.ObjectPlacer:Start(`prop_still`, "Drugs:Client:Moonshine:FinishPlacement", data, 2)
        cb()
    end)

    plsr.Callbacks:RegisterClientCallback("Drugs:Moonshine:PlaceBarrel", function(data, cb)
        plsr.ObjectPlacer:Start(`prop_wooden_barrel`, "Drugs:Client:Moonshine:FinishPlacementBarrel", data, 2)
        cb()
    end)

    plsr.Callbacks:RegisterClientCallback("Drugs:Moonshine:Use", function(data, cb)
        Wait(400)
        plsr.Minigame.Play:RoundSkillbar(0.8, 8, {
            onSuccess = function()
                cb(true)
            end,
            onFail = function()
                cb(false)
            end,
        }, {
            useWhileDead = false,
            vehicle = false,
            controlDisables = {
                disableMovement = true,
                disableCarMovement = true,
                disableMouse = false,
                disableCombat = true,
            },
            animation = {
                animDict = "amb@world_human_drinking@coffee@male@idle_a",
                anim = "idle_c",
                flags = 48,
            },
            prop = {
            	model = "prop_beer_bottle",
            	bone = 28422,
            	coords = { x = 0.0, y = 0.0, z = -0.15 },
            	rotation = { x = 0.0, y = 0.0, z = 0.0 },
            },
        })
    end)
end)

RegisterNetEvent("Drugs:Client:Moonshine:SetupStills", function(stills)
    CreateThread(function()
        loadModel(`prop_still`)
        for k, v in pairs(stills) do
            _stills[k] = v
            local obj = CreateObject(`prop_still`, v.coords.x, v.coords.y, v.coords.z, false, true, false)
            SetEntityHeading(obj, v.heading)
            while not DoesEntityExist(obj) do
                Wait(1)
            end
            PlaceObjectOnGroundProperly(obj)
            _stills[k].entity = obj
            Entity(obj).state.isMoonshineStill = true
            Entity(obj).state.stillId = v.id
            Wait(1)
        end
    end)
end)

RegisterNetEvent("Drugs:Client:Moonshine:SetupBarrels", function(barrels)
    CreateThread(function()
        loadModel(`prop_wooden_barrel`)
        for k, v in pairs(barrels) do
            _barrels[k] = v
            local obj = CreateObject(`prop_wooden_barrel`, v.coords.x, v.coords.y, v.coords.z, false, true, false)
            SetEntityHeading(obj, v.heading)
            while not DoesEntityExist(obj) do
                Wait(1)
            end
            PlaceObjectOnGroundProperly(obj)
            _barrels[k].entity = obj
            Entity(obj).state.isMoonshineBarrel = true
            Entity(obj).state.barrelId = v.id
            Wait(1)
        end
    end)
end)

RegisterNetEvent("Characters:Client:Logout", function()
    CreateThread(function()
        for k, v in pairs(_stills) do
            if v?.entity ~= nil and DoesEntityExist(v?.entity) then
                DeleteEntity(v?.entity)
                _stills[k] = nil
            end
            Wait(1)
        end
    end)
end)

RegisterNetEvent("Characters:Client:Logout", function()
    CreateThread(function()
        for k, v in pairs(_barrels) do
            if v?.entity ~= nil and DoesEntityExist(v?.entity) then
                DeleteEntity(v?.entity)
                _barrels[k] = nil
            end
            Wait(1)
        end
    end)
end)

RegisterNetEvent("Drugs:Client:Moonshine:CreateStill", function(still)
    CreateThread(function()
        loadModel(`prop_still`)
        _stills[still.id] = still
        local obj = CreateObject(`prop_still`, still.coords.x, still.coords.y, still.coords.z, false, true, false)
        SetEntityHeading(obj, still.heading)
        while not DoesEntityExist(obj) do
            Wait(1)
        end

        _stills[still.id].entity = obj

        Entity(obj).state.isMoonshineStill = true
        Entity(obj).state.stillId = still.id
    end)
end)

RegisterNetEvent("Drugs:Client:Moonshine:RemoveStill", function(stillId)
    CreateThread(function()
        local objs = GetGamePool("CObject")
        for k, v in ipairs(objs) do
            local entState = Entity(v).state
            if entState.isMoonshineStill and entState.stillId == stillId then
                DeleteEntity(v)
            end
        end
        _stills[stillId] = nil
    end)
end)

RegisterNetEvent("Drugs:Client:Moonshine:UpdateStillData", function(stillId, data)
    _stills[stillId] = data
end)

AddEventHandler("Drugs:Client:Moonshine:FinishPlacement", function(data, endCoords)
    TaskTurnPedToFaceCoord(PlayerPedId(), endCoords.coords.x, endCoords.coords.y, endCoords.coords.z, 0.0)
    Wait(1000)
    plsr.Progress:Progress({
        name = "meth_pickup",
        duration = (math.random(5) + 10) * 1000,
        label = "Placing",
        useWhileDead = false,
        canCancel = true,
        ignoreModifier = true,
        controlDisables = {
            disableMovement = true,
            disableCarMovement = true,
            disableMouse = false,
            disableCombat = true,
        },
        animation = {
            task = "CODE_HUMAN_MEDIC_KNEEL",
        },
    }, function(status)
        if not status then
            plsr.Callbacks:ServerCallback("Drugs:Moonshine:FinishStillPlacement", {
                data = data,
                endCoords = endCoords
            }, function(s)

            end)
        end
    end)
end)

AddEventHandler("Drugs:Client:Moonshine:FinishPlacementBarrel", function(data, endCoords)
    TaskTurnPedToFaceCoord(PlayerPedId(), endCoords.coords.x, endCoords.coords.y, endCoords.coords.z, 0.0)
    Wait(1000)
    plsr.Progress:Progress({
        name = "meth_pickup",
        duration = 3 * 1000,
        label = "Placing",
        useWhileDead = false,
        canCancel = true,
        ignoreModifier = true,
        controlDisables = {
            disableMovement = true,
            disableCarMovement = true,
            disableMouse = false,
            disableCombat = true,
        },
        animation = {
            task = "CODE_HUMAN_MEDIC_KNEEL",
        },
    }, function(status)
        if not status then
            plsr.Callbacks:ServerCallback("Drugs:Moonshine:FinishBarrelPlacement", {
                data = data,
                endCoords = endCoords
            }, function(s)

            end)
        end
    end)
end)

AddEventHandler("Drugs:Client:Moonshine:PickupStill", function(entity, data)
    if Entity(entity.entity).state?.isMoonshineStill then
        plsr.Progress:Progress({
            name = "meth_pickup",
            duration = (math.random(5) + 15) * 1000,
            label = "Picking Up Still",
            useWhileDead = false,
            canCancel = true,
            ignoreModifier = true,
            controlDisables = {
                disableMovement = true,
                disableCarMovement = true,
                disableMouse = false,
                disableCombat = true,
            },
            animation = {
                task = "CODE_HUMAN_MEDIC_KNEEL",
            },
        }, function(status)
            if not status then
                plsr.Callbacks:ServerCallback("Drugs:Moonshine:PickupStill", Entity(entity.entity).state.stillId, function(s)
                end)
            end
        end)
    end
end)

-- holds the recipe list + chosen still between StartCook (open menu) and SelectRecipe (fired by the menu)
local _recipeSelectionData = {}

AddEventHandler("Drugs:Client:Moonshine:StartCook", function(entity, data)
    local entState = Entity(entity.entity).state
    if entState.isMoonshineStill and entState.stillId then
        plsr.Callbacks:ServerCallback("Drugs:Moonshine:CheckStill", entState.stillId, function(s)
            if not s then
                plsr.Notification:Error("Still Is Not Ready")
                return
            end

            local stillId = entState.stillId
            local stillTier = _stills[stillId]?.tier or 1

            plsr.Callbacks:ServerCallback("Drugs:Moonshine:GetRecipes", {}, function(recipeData)
                if not recipeData then
                    plsr.Notification:Error("Failed To Load Recipes")
                    return
                end

                _recipeSelectionData.stillId = stillId
                _recipeSelectionData.stillTier = stillTier
                _recipeSelectionData.recipes = recipeData.recipes

                local menuItems = {}
                for k, recipe in ipairs(recipeData.recipes) do
                    local ingredientText = ""
                    for i, ing in ipairs(recipe.ingredients) do
                        ingredientText = ingredientText .. string.format("%d %s", ing.amount, ing.item)
                        if i < #recipe.ingredients then
                            ingredientText = ingredientText .. ", "
                        end
                    end

                    table.insert(menuItems, {
                        label = recipe.unlocked and recipe.label or (recipe.label .. " (Locked)"),
                        description = recipe.unlocked
                            and string.format("%s\nIngredients: %s\nBase Quality: %d", recipe.description, ingredientText, recipe.baseQuality)
                            or string.format("Requires %d Reputation", recipe.requiredRep),
                        event = "Drugs:Client:Moonshine:SelectRecipe",
                        data = { recipeId = recipe.id },
                        disabled = not recipe.unlocked,
                    })
                end

                plsr.ListMenu:Show({
                    main = {
                        label = "Select Recipe",
                        items = menuItems,
                    },
                })
            end)
        end)
    end
end)

AddEventHandler("Drugs:Client:Moonshine:SelectRecipe", function(data)
    if not data or not data.recipeId or not _recipeSelectionData.stillId then
        return
    end

    local selectedRecipe = nil
    for k, recipe in ipairs(_recipeSelectionData.recipes) do
        if recipe.id == data.recipeId then
            selectedRecipe = recipe
            break
        end
    end

    if not selectedRecipe or not selectedRecipe.unlocked then
        plsr.Notification:Error("Recipe Is Locked Or Invalid")
        return
    end

    local checks = _stillTiers[_recipeSelectionData.stillTier]?.checks or 10

    plsr.Progress:Progress({
        name = "moonshine_prepare",
        duration = 5 * 1000,
        label = "Preparing Ingredients",
        useWhileDead = false,
        canCancel = true,
        ignoreModifier = true,
        controlDisables = {
            disableMovement = true,
            disableCarMovement = true,
            disableMouse = false,
            disableCombat = true,
        },
        animation = {
            anim = "dj",
        },
    }, function(status)
        if status then
            _recipeSelectionData = {}
            return
        end

        local results = RunSkillChecks(checks)

        plsr.State.flags.doingAction = false

        plsr.Progress:Progress({
            name = "moonshine_finish",
            duration = 2 * 1000,
            label = "Starting Brew",
            useWhileDead = false,
            canCancel = false,
            ignoreModifier = true,
            controlDisables = {
                disableMovement = true,
                disableCarMovement = true,
                disableMouse = false,
                disableCombat = true,
            },
            animation = {
                anim = "dj",
            },
        }, function(finishStatus)
            if finishStatus then
                _recipeSelectionData = {}
                return
            end

            plsr.Callbacks:ServerCallback("Drugs:Moonshine:StartCooking", {
                stillId = _recipeSelectionData.stillId,
                recipeId = selectedRecipe.id,
                results = results,
            }, function(success)
                if success then
                    plsr.Notification:Success("Brew Started Successfully!")
                else
                    plsr.Notification:Error("Failed To Start Brew, Check Your Ingredients And Still Status")
                end
                _recipeSelectionData = {}
            end)
        end)
    end)
end)

AddEventHandler("Drugs:Client:Moonshine:PickupCook", function(entity, data)
    local entState = Entity(entity.entity).state
    if entState.isMoonshineStill and entState.stillId then
        plsr.Progress:Progress({
            name = "meth_pickup",
            duration = 5 * 1000,
            label = "Emptying Still",
            useWhileDead = false,
            canCancel = true,
            ignoreModifier = true,
            controlDisables = {
                disableMovement = true,
                disableCarMovement = true,
                disableMouse = false,
                disableCombat = true,
            },
            animation = {
                anim = "dj",
            },
        }, function(status)
            if not status then
                plsr.Callbacks:ServerCallback("Drugs:Moonshine:PickupCook", entState.stillId, function(s)
                    if not s then
                        plsr.Notification:Error("Still Is Not Ready")
                    end
                end)
            end
        end)
    end
end)

AddEventHandler("Drugs:Client:Moonshine:UpgradeStill", function(entity, data)
    local entState = Entity(entity.entity).state
    if entState.isMoonshineStill and entState.stillId then
        plsr.Callbacks:ServerCallback("Drugs:Moonshine:UpgradeStill", entState.stillId, function(success)
            if success then
                plsr.Notification:Success("Still Upgraded Successfully!")
            end
        end)
    end
end)

AddEventHandler("Drugs:Client:Moonshine:PickupBrew", function(entity, data)
    local entState = Entity(entity.entity).state
    if plsr.Inventory.Items:Has("moonshine_jar", (_barrels[entState.barrelId]?.brewData?.Drinks or 15), false) then
        if entState.isMoonshineBarrel and entState.barrelId then
            plsr.Progress:Progress({
                name = "meth_pickup",
                duration = 5 * 1000,
                label = "Emptying Barrel",
                useWhileDead = false,
                canCancel = true,
                ignoreModifier = true,
                controlDisables = {
                    disableMovement = true,
                    disableCarMovement = true,
                    disableMouse = false,
                    disableCombat = true,
                },
                animation = {
                    anim = "dj",
                },
            }, function(status)
                if not status then
                    plsr.Callbacks:ServerCallback("Drugs:Moonshine:PickupBrew", entState.barrelId, function(s) end)
                end
            end)
        end
    else
        plsr.Notification:Error(string.format("Missing Empty Jars (Requires %s Empty Jars", (_barrels[entState.barrelId]?.brewData?.Drinks or 15)))
    end
end)

AddEventHandler("Drugs:Client:Moonshine:StillDetails", function(entity, data)
    local entState = Entity(entity.entity).state
    if entState.isMoonshineStill and entState.stillId then
        plsr.Callbacks:ServerCallback("Drugs:Moonshine:GetStillDetails", entState.stillId, function(s)
            if s then
                plsr.ListMenu:Show(s)
            end
        end)
    end
end)

RegisterNetEvent("Drugs:Client:Moonshine:UpdateBarrelData", function(barrelId, data)
    _barrels[barrelId] = data
end)

RegisterNetEvent("Drugs:Client:Moonshine:CreateBarrel", function(barrel)
    CreateThread(function()
        loadModel(`prop_wooden_barrel`)
        _barrels[barrel.id] = barrel
        local obj = CreateObject(`prop_wooden_barrel`, barrel.coords.x, barrel.coords.y, barrel.coords.z, false, true, false)
        SetEntityHeading(obj, barrel.heading)
        PlaceObjectOnGroundProperly(obj)
        while not DoesEntityExist(obj) do
            Wait(1)
        end

        _barrels[barrel.id].entity = obj

        Entity(obj).state.isMoonshineBarrel = true
        Entity(obj).state.barrelId = barrel.id
    end)
end)

RegisterNetEvent("Drugs:Client:Moonshine:RemoveBarrel", function(barrelId)
    CreateThread(function()
        local objs = GetGamePool("CObject")
        for k, v in ipairs(objs) do
            local entState = Entity(v).state
            if entState.isMoonshineBarrel and entState.barrelId == barrelId then
                DeleteEntity(v)
            end
        end
        _barrels[barrelId] = nil
    end)
end)

AddEventHandler("Drugs:Client:Moonshine:PickupBarrel", function(entity, data)
    if Entity(entity.entity).state?.isMoonshineBarrel then
        plsr.Progress:Progress({
            name = "meth_pickup",
            duration = 8 * 1000,
            label = "Destroying",
            useWhileDead = false,
            canCancel = true,
            ignoreModifier = true,
            controlDisables = {
                disableMovement = true,
                disableCarMovement = true,
                disableMouse = false,
                disableCombat = true,
            },
            animation = {
                task = "CODE_HUMAN_MEDIC_KNEEL",
            },
        }, function(status)
            if not status then
                plsr.Callbacks:ServerCallback("Drugs:Moonshine:PickupBarrel", Entity(entity.entity).state.barrelId, function(s)
                end)
            end
        end)
    end
end)

AddEventHandler("Drugs:Client:Moonshine:BarrelDetails", function(entity, data)
    local entState = Entity(entity.entity).state
    if entState.isMoonshineBarrel and entState.barrelId then
        plsr.Callbacks:ServerCallback("Drugs:Moonshine:GetBarrelDetails", entState.barrelId, function(s)
            if s then
                plsr.ListMenu:Show(s)
            end
        end)
    end
end)

-- Police heat alert: draws a temporary blip for on-duty police within range of a hot still
RegisterNetEvent("Drugs:Client:Moonshine:PoliceAlert", function(alertData)
    if plsr.State.flags.onDuty ~= "police" then
        return
    end

    local playerCoords = GetEntityCoords(PlayerPedId())
    local distance = #(vector3(alertData.coords.x, alertData.coords.y, alertData.coords.z) - playerCoords)
    if distance > _policeDetection.detectionRadius then
        return
    end

    local blip = AddBlipForCoord(alertData.coords.x, alertData.coords.y, alertData.coords.z)
    SetBlipSprite(blip, 432)
    SetBlipColour(blip, 1)
    SetBlipScale(blip, 1.0)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Suspicious Moonshine Activity")
    EndTextCommandSetBlipName(blip)

    SetTimeout(300000, function()
        RemoveBlip(blip)
    end)

    plsr.Notification:Info(string.format("Moonshine Activity Detected! Heat: %d/100", alertData.heat))
end)

-- Dealer ped: sells finished moonshine (drop-off route / bulk sale / Cayo Perico), separate from
-- the tool-shop vendor that sells stills/barrels
RegisterNetEvent("Drugs:Client:Moonshine:CreateDealer", function(data)
    plsr.PedInteraction:Add(data.id, data.model, data.coords, data.heading, 50.0, {
        {
            icon = "handshake",
            text = "Talk To Dealer",
            minDist = 2.0,
            event = "Drugs:Client:Moonshine:OpenDealerMenu",
        },
    }, "handshake", data.scenario or false)
end)

RegisterNetEvent("Drugs:Client:Moonshine:OpenDealerMenu", function()
    plsr.Callbacks:ServerCallback("Drugs:Moonshine:GetDealerOptions", {}, function(options)
        if not options then
            return
        end

        local menuItems = {}

        if options.dropOff.available then
            table.insert(menuItems, {
                label = options.dropOff.label,
                description = options.dropOff.description,
                event = "Drugs:Client:Moonshine:DealerDropOff",
            })
        else
            table.insert(menuItems, {
                label = options.dropOff.label .. " (Locked)",
                description = "Reputation too low",
                disabled = true,
            })
        end

        if options.bulkSale.available then
            table.insert(menuItems, {
                label = options.bulkSale.label,
                description = options.bulkSale.description,
                event = "Drugs:Client:Moonshine:DealerBulkSale",
            })
        else
            table.insert(menuItems, {
                label = options.bulkSale.label .. " (Locked)",
                description = "Reputation too low",
                disabled = true,
            })
        end

        if options.travel.available then
            table.insert(menuItems, {
                label = options.travel.label,
                description = options.travel.description,
                event = "Drugs:Client:Moonshine:DealerTravel",
            })
        else
            table.insert(menuItems, {
                label = options.travel.label .. " (Locked)",
                description = "Reputation too low",
                disabled = true,
            })
        end

        plsr.ListMenu:Show({
            main = {
                label = "Moonshine Dealer",
                items = menuItems,
            },
        })
    end)
end)

local _activeDeliveryPeds = {}
local _currentDelivery = nil

local function StartDeliveryRoute(result, isTravel)
    _currentDelivery = {
        id = result.id,
        stops = result.stops,
        currentStop = 1,
        timeLimit = result.timeLimit,
        type = isTravel and "travel" or "dropoff",
    }

    TriggerEvent("Drugs:Client:Moonshine:GoToStop", 1)

    plsr.Notification:Success(string.format("%s Started! %d Stops | Time Limit: %d Minutes",
        isTravel and "Cayo Perico Delivery Route" or "Delivery Route", #result.stops, math.floor(result.timeLimit / 60)))
end

RegisterNetEvent("Drugs:Client:Moonshine:DealerDropOff", function()
    plsr.Callbacks:ServerCallback("Drugs:Moonshine:DealerDropOff", {}, function(result)
        if result and result.stops and #result.stops > 0 then
            StartDeliveryRoute(result, false)
        else
            plsr.Notification:Error("Failed To Start Drop Off")
        end
    end)
end)

RegisterNetEvent("Drugs:Client:Moonshine:DealerTravel", function()
    plsr.Callbacks:ServerCallback("Drugs:Moonshine:DealerTravel", {}, function(result)
        if result and result.stops and #result.stops > 0 then
            StartDeliveryRoute(result, true)
        else
            plsr.Notification:Error("Failed To Start Travel Delivery")
        end
    end)
end)

RegisterNetEvent("Drugs:Client:Moonshine:DealerBulkSale", function()
    plsr.Callbacks:ServerCallback("Drugs:Moonshine:DealerBulkSale", {}, function(success)
        if not success then
            plsr.Notification:Error("Failed To Complete Bulk Sale")
        end
    end)
end)

RegisterNetEvent("Drugs:Client:Moonshine:GoToStop", function(stopIndex)
    if not _currentDelivery or not _currentDelivery.stops[stopIndex] then
        return
    end

    local stop = _currentDelivery.stops[stopIndex]
    local isTravel = _currentDelivery.type == "travel"

    SetNewWaypoint(stop.coords.x, stop.coords.y)
    local blip = AddBlipForCoord(stop.coords.x, stop.coords.y, stop.coords.z)
    SetBlipSprite(blip, 1)
    local blipColor = isTravel and 46 or 5
    SetBlipColour(blip, blipColor)
    SetBlipRoute(blip, true)
    SetBlipRouteColour(blip, blipColor)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(string.format("%s (Stop %d/%d)", isTravel and "Cayo Perico Delivery" or "Moonshine Delivery", stopIndex, #_currentDelivery.stops))
    EndTextCommandSetBlipName(blip)

    local pedModels = { `a_m_m_hillbilly_01`, `a_m_m_hillbilly_02`, `a_m_y_hippy_01`, `a_m_y_hipster_02`, `a_m_m_tramp_01` }
    local pedModel = pedModels[math.random(#pedModels)]

    RequestModel(pedModel)
    local timeout = 0
    while not HasModelLoaded(pedModel) and timeout < 50 do
        Wait(100)
        timeout += 1
    end

    if not HasModelLoaded(pedModel) then
        plsr.Notification:Error("Failed To Load Ped Model")
        return
    end

    local ped = CreatePed(4, pedModel, stop.coords.x, stop.coords.y, stop.coords.z, 0.0, false, true)
    SetEntityAsMissionEntity(ped, true, true)
    FreezeEntityPosition(ped, true)
    SetPedCanRagdoll(ped, false)
    TaskSetBlockingOfNonTemporaryEvents(ped, 1)
    SetBlockingOfNonTemporaryEvents(ped, 1)
    SetPedFleeAttributes(ped, 0, 0)
    SetPedCombatAttributes(ped, 17, 1)
    SetEntityInvincible(ped, true)
    SetPedDefaultComponentVariation(ped)
    SetModelAsNoLongerNeeded(pedModel)

    plsr.Targeting:AddEntity(ped, "handshake", {
        {
            text = "Sell Moonshine",
            icon = "handshake",
            event = "Drugs:Client:Moonshine:SellToPed",
            data = { stopIndex = stopIndex },
            minDist = 2.0,
        },
    }, 2.0)

    _activeDeliveryPeds[stopIndex] = { ped = ped, blip = blip }
end)

AddEventHandler("Drugs:Client:Moonshine:SellToPed", function(entity, data)
    if not _currentDelivery then
        return
    end

    local stopIndex = data.stopIndex

    plsr.Callbacks:ServerCallback("Drugs:Moonshine:SellToPed", {
        deliveryId = _currentDelivery.id,
        stopIndex = stopIndex,
    }, function(result)
        if not result then
            plsr.Notification:Error("Failed To Sell Moonshine")
            return
        end

        local pedData = _activeDeliveryPeds[stopIndex]
        if pedData and pedData.ped and DoesEntityExist(pedData.ped) then
            FreezeEntityPosition(pedData.ped, false)
            SetEntityInvincible(pedData.ped, false)
            SetPedCanRagdoll(pedData.ped, true)
            SetBlockingOfNonTemporaryEvents(pedData.ped, false)
            TaskSetBlockingOfNonTemporaryEvents(pedData.ped, 0)
            TaskWanderStandard(pedData.ped, 10.0, 10)
            plsr.Targeting:RemoveEntity(pedData.ped)
        end

        if pedData and pedData.blip then
            RemoveBlip(pedData.blip)
        end

        _activeDeliveryPeds[stopIndex] = nil

        if result.completed then
            local deliveryType = _currentDelivery and _currentDelivery.type == "travel" and "Cayo Perico delivery" or "Delivery route"
            plsr.Notification:Success(string.format("%s Complete! Total Payment: $%s", deliveryType, result.payment))
            _currentDelivery = nil
        else
            local repMsg = result.repGain and string.format(" | Rep +%d", result.repGain) or ""
            plsr.Notification:Info(string.format("Stop %d Complete! Moving To Next Stop...%s", stopIndex, repMsg))
            Wait(2000)
            TriggerEvent("Drugs:Client:Moonshine:GoToStop", result.nextStop)
        end
    end)
end)
