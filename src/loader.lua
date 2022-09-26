----------------------------------------------------------------------------------------------------
-- Loader
----------------------------------------------------------------------------------------------------
-- Purpose: Loader SourceCode for Extended Cruise Control insertion into vehicles
--
-- @author John Deere 6930 @VertexDezign
----------------------------------------------------------------------------------------------------

local modDirectory = g_currentModDirectory
local modName = g_currentModName

---Checks if mods are loaded in current game which causes conflicts with this mod
---@param modNames table<string> names of conflicting mods
---@return boolean valid returns true if no conflicting mod found, false otherwise
local function ceckRestrictedModInstalled(modNames)
    for _, name in ipairs(modNames) do
        if g_modIsLoaded[name] ~= nil and g_modIsLoaded[name] then
            Logging.warning(("'%s' not installed, conflicting mod found: '%s'!"):format(modName, name))
            return false
        end
    end

    return true
end

---Installs ExtendedCruiseControl spec in all vehicles using Drivable specialization
local function installSpecializations(vehicleTypeManager, specializationManager, _modDirectory, _modName)
    specializationManager:addSpecialization("extendedCruiseControl", "ExtendedCruiseControl", Utils.getFilename("src/vehicles/specializations/ExtendedCruiseControl.lua", _modDirectory), nil)

    for typeName, typeEntry in pairs(vehicleTypeManager:getTypes()) do
        if SpecializationUtil.hasSpecialization(Drivable, typeEntry.specializations) then
            vehicleTypeManager:addSpecialization(typeName, _modName .. ".extendedCruiseControl")
        end
    end
end

---Injects extendedCruiseControl installation
---@param typeManager table typeManager table
local function validateTypes(typeManager)
    if typeManager.typeName == "vehicle" then
        if not ceckRestrictedModInstalled({ "FS22_SpeedControl" }) then
            return
        end

        installSpecializations(g_vehicleTypeManager, g_specializationManager, modDirectory, modName)
    end
end

---Injects extendedCruiseControl drawings
---@param speedMeterDisplay table typeManager table
local function drawCruiseControlText(speedMeterDisplay)
    if speedMeterDisplay.cruiseControlElement:getVisible() then
        if speedMeterDisplay.vehicle == nil or speedMeterDisplay.vehicle.spec_extendedCruiseControl == nil then
            return
        end

        -- render active speed group text
        local activeSpeedGroup = speedMeterDisplay.vehicle.spec_extendedCruiseControl.activeSpeedGroup
        if activeSpeedGroup ~= nil then
            setTextAlignment(RenderText.ALIGN_LEFT)
            setTextColor(unpack(speedMeterDisplay.cruiseControlColor))
            setTextBold(true)

            local groupText = ("%d"):format(activeSpeedGroup)
            local baseX, baseY = speedMeterDisplay.cruiseControlElement:getPosition()
            local posX = baseX + speedMeterDisplay.cruiseControlElement:getWidth() - 4.5 * speedMeterDisplay.cruiseControlTextOffsetX
            local posY = baseY + 3.5 * speedMeterDisplay.cruiseControlTextOffsetY

            renderText(posX, posY, speedMeterDisplay.cruiseControlTextSize * 0.7, groupText)
        end

        -- render permanent cruise control character
        local permanentActive = speedMeterDisplay.vehicle.spec_extendedCruiseControl.permanentActive
        if permanentActive ~= nil and permanentActive then
            setTextAlignment(RenderText.ALIGN_LEFT)
            setTextColor(unpack(SpeedMeterDisplay.COLOR.CRUISE_CONTROL_ON))
            setTextBold(true)

            local baseX, baseY = speedMeterDisplay.cruiseControlElement:getPosition()
            local posX = baseX + speedMeterDisplay.cruiseControlElement:getWidth() - 4.5 * speedMeterDisplay.cruiseControlTextOffsetX
            local posY = baseY - speedMeterDisplay.cruiseControlTextOffsetY

            renderText(posX, posY, speedMeterDisplay.cruiseControlTextSize * 0.7, "P")
        end
    end
end

---Initialize the mod
local function init()
    TypeManager.validateTypes = Utils.prependedFunction(TypeManager.validateTypes, validateTypes)
    SpeedMeterDisplay.drawCruiseControlText = Utils.appendedFunction(SpeedMeterDisplay.drawCruiseControlText, drawCruiseControlText)
end

init()
