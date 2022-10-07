----------------------------------------------------------------------------------------------------
-- ExtendedCruiseControl
----------------------------------------------------------------------------------------------------
-- Purpose: Specialization for extended cruise control on drivable vehicle
--          - Adds permanent active cruise control
--          - Adds three cruise control stages
--
-- @author John Deere 6930 @VertexDezign
----------------------------------------------------------------------------------------------------

---@class ExtendedCruiseControl

ExtendedCruiseControl = {}
ExtendedCruiseControl.MOD_NAME = g_currentModName
ExtendedCruiseControl.SAFE_RESET_TIME_OFFSET = 200

function ExtendedCruiseControl.initSpecialization()
    local schemaSavegame = Vehicle.xmlSchemaSavegame

    schemaSavegame:register(XMLValueType.INT, "vehicles.vehicle(?).FS22_extendedCruiseControl.extendedCruiseControl#activeSpeedGroup", "Currently used speed group")
    schemaSavegame:register(XMLValueType.INT, "vehicles.vehicle(?).FS22_extendedCruiseControl.extendedCruiseControl.speedGroup(?)#forward", "Forward speed of speed group")
    schemaSavegame:register(XMLValueType.INT, "vehicles.vehicle(?).FS22_extendedCruiseControl.extendedCruiseControl.speedGroup(?)#reverse", "Reverse speed of speed group")
end

function ExtendedCruiseControl.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(Drivable, specializations)
end

function ExtendedCruiseControl.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "updateSpeeds", ExtendedCruiseControl.updateSpeeds)
end

function ExtendedCruiseControl.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onPreLoad", ExtendedCruiseControl)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", ExtendedCruiseControl)
    SpecializationUtil.registerEventListener(vehicleType, "onReadStream", ExtendedCruiseControl)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteStream", ExtendedCruiseControl)
    SpecializationUtil.registerEventListener(vehicleType, "onReadUpdateStream", ExtendedCruiseControl)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteUpdateStream", ExtendedCruiseControl)
    SpecializationUtil.registerEventListener(vehicleType, "onPreUpdate", ExtendedCruiseControl)
    SpecializationUtil.registerEventListener(vehicleType, "onPostUpdate", ExtendedCruiseControl)
    SpecializationUtil.registerEventListener(vehicleType, "onLeaveVehicle", ExtendedCruiseControl)
    SpecializationUtil.registerEventListener(vehicleType, "onAIFieldWorkerStart", ExtendedCruiseControl)
    SpecializationUtil.registerEventListener(vehicleType, "onRegisterActionEvents", ExtendedCruiseControl)
end

function ExtendedCruiseControl.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "setCruiseControlState", ExtendedCruiseControl.setCruiseControlState)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "setCruiseControlMaxSpeed", ExtendedCruiseControl.setCruiseControlMaxSpeed)
end

---Called before load
function ExtendedCruiseControl:onPreLoad(savegame)
    local name = "spec_extendedCruiseControl"

    if self[name] ~= nil then
        Logging.xmlError(self.xmlFile, "The vehicle specialization '%s' could not be added because variable '%s' already exists!", ExtendedCruiseControl.MOD_NAME, name)
        self:setLoadingState(VehicleLoadingUtil.VEHICLE_LOAD_ERROR)
    end

    local env = {}
    setmetatable(env, {
        __index = self
    })

    env.actionEvents = {}
    self[name] = env

    self.spec_extendedCruiseControl = self[name]
end

---Called on load
function ExtendedCruiseControl:onLoad(savegame)
    local spec = self.spec_extendedCruiseControl

    spec.raisedPermanentControl = false
    spec.permanentActive = false
    spec.resetIsDirty = false
    spec.doReset = false

    spec.resetTimer = 0

    local cruiseControl = self.spec_drivable.cruiseControl
    local maxSpeed = cruiseControl.maxSpeed or 30
    local maxSpeedReverse = cruiseControl.maxSpeedReverse or 20
    spec.cruiseSpeedGroups = {
        [1] = { forward = 10, reverse = 10 },
        [2] = { forward = 20, reverse = 15 },
        [3] = { forward = maxSpeed, reverse = maxSpeedReverse }
    }

    spec.activeSpeedGroup = #spec.cruiseSpeedGroups
    spec.activeSpeedGroupSent = spec.activeSpeedGroup

    spec.dirtyFlag = self:getNextDirtyFlag()
    spec.lastFrameDirty = false

    if savegame ~= nil then
        spec.activeSpeedGroup = Utils.getNoNil(savegame.xmlFile:getValue(savegame.key .. ".FS22_extendedCruiseControl.extendedCruiseControl#activeSpeedGroup"), 3)

        for index, speedGroup in ipairs(spec.cruiseSpeedGroups) do
            local groupKey = ("%s.FS22_extendedCruiseControl.extendedCruiseControl.speedGroup(%d)"):format(savegame.key, index - 1)

            local forward = Utils.getNoNil(savegame.xmlFile:getValue(groupKey .. "#forward"), speedGroup.forward)
            local reverse = Utils.getNoNil(savegame.xmlFile:getValue(groupKey .. "#reverse"), speedGroup.reverse)
            speedGroup.forward = forward
            speedGroup.reverse = reverse
        end

        self:updateSpeeds()
    end
end

---Save parameter to savegame xml file
---@param xmlFile table xml file handler
---@param key string key to save destination
---@param usedModNames string used mod names
function ExtendedCruiseControl:saveToXMLFile(xmlFile, key, usedModNames)
    local spec = self.spec_extendedCruiseControl
    xmlFile:setValue(key .. "#activeSpeedGroup", spec.activeSpeedGroup)

    for index, speedGroup in ipairs(spec.cruiseSpeedGroups) do
        local groupKey = ("%s.speedGroup(%d)"):format(key, index - 1)

        xmlFile:setValue(groupKey .. "#forward", speedGroup.forward)
        xmlFile:setValue(groupKey .. "#reverse", speedGroup.reverse)
    end
end

---Called on read stream
function ExtendedCruiseControl:onReadStream(streamId, connection)
    local spec = self.spec_extendedCruiseControl
    spec.activeSpeedGroup = streamReadInt8(streamId)

    for i = 1, 3, 1 do
        local speedGroup = spec.cruiseSpeedGroups[streamReadInt8(streamId)]

        if speedGroup ~= nil then
            local forward = streamReadFloat32(streamId)
            local reverse = streamReadFloat32(streamId)

            speedGroup.forward = forward
            speedGroup.reverse = reverse
        end
    end

    self:updateSpeeds()
end

---Called on write stream
function ExtendedCruiseControl:onWriteStream(streamId, connection)
    local spec = self.spec_extendedCruiseControl
    streamWriteInt8(streamId, spec.activeSpeedGroup)

    for i = 1, 3, 1 do
        local speedGroup = spec.cruiseSpeedGroups[i]

        streamWriteInt8(streamId, i)
        streamWriteFloat32(streamId, speedGroup.forward)
        streamWriteFloat32(streamId, speedGroup.reverse)
    end
end

---Called on read update stream
function ExtendedCruiseControl:onReadUpdateStream(streamId, timestamp, connection)
    local spec = self.spec_extendedCruiseControl

    if streamReadBool(streamId) then
        spec.activeSpeedGroup = streamReadInt8(streamId)

        for i = 1, 3, 1 do
            local speedGroup = spec.cruiseSpeedGroups[streamReadInt8(streamId)]

            speedGroup.forward = streamReadFloat32(streamId)
            speedGroup.reverse = streamReadFloat32(streamId)
        end

        self:updateSpeeds()
    end
end

---Called on write update stream
function ExtendedCruiseControl:onWriteUpdateStream(streamId, connection, dirtyMask)
    local spec = self.spec_extendedCruiseControl
    local spec_drivable = self.spec_drivable

    local bitDirty = bitAND(dirtyMask, spec.dirtyFlag) ~= 0 or bitAND(dirtyMask, spec_drivable.dirtyFlag) ~= 0
    if streamWriteBool(streamId, bitDirty) then
        streamWriteInt8(streamId, spec.activeSpeedGroup)

        for i = 1, 3, 1 do
            local speedGroup = spec.cruiseSpeedGroups[i]

            streamWriteInt8(streamId, i)
            streamWriteFloat32(streamId, speedGroup.forward)
            streamWriteFloat32(streamId, speedGroup.reverse)
        end
    end
end

---Called before update
function ExtendedCruiseControl:onPreUpdate(dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    local spec = self.spec_extendedCruiseControl

    if spec.permanentActive then
        if spec.resetIsDirty then
            spec.doReset = self.spec_drivable.lastInputValues.axisBrake == 0 or self.spec_drivable.lastInputValues.axisAccelerate == 0
            spec.resetIsDirty = not spec.doReset
            spec.resetTimer = g_currentMission.time + ExtendedCruiseControl.SAFE_RESET_TIME_OFFSET

            return
        end

        if spec.doReset then
            self.spec_drivable.lastInputValues.cruiseControlState = Drivable.CRUISECONTROL_STATE_ACTIVE

            if spec.resetTimer < g_currentMission.time then
                spec.doReset = false
            end
        end
    else
        spec.doReset = false
    end

    if spec.lastFrameDirty then
        ExtendedCruiseControl.updateActionEventTexts(self)
        spec.lastFrameDirty = false
    end
end

---Called after update
function ExtendedCruiseControl:onPostUpdate(dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    local spec = self.spec_extendedCruiseControl
    local lastControlState = spec.raisedPermanentControl
    spec.raisedPermanentControl = false

    if lastControlState ~= spec.raisedPermanentControl then
        spec.lastFrameDirty = true
    end
end

---Called on leaving vehicle
function ExtendedCruiseControl:onLeaveVehicle(wasEntered)
    local spec = self.spec_extendedCruiseControl
    spec.permanentActive = false
    spec.raisedPermanentControl = false
    spec.resetIsDirty = false
    spec.doReset = false
end

---Called on starting ai helper
function ExtendedCruiseControl:onAIFieldWorkerStart()
    local spec = self.spec_extendedCruiseControl
    spec.permanentActive = false
    spec.raisedPermanentControl = false
    spec.resetIsDirty = false
    spec.doReset = false
end

---Updates speeds by active speed group
function ExtendedCruiseControl:updateSpeeds()
    local spec = self.spec_extendedCruiseControl
    local speedGroup = spec.cruiseSpeedGroups[spec.activeSpeedGroup]
    if speedGroup ~= nil then
        self:setCruiseControlMaxSpeed(speedGroup.forward, speedGroup.reverse)
    end

    ExtendedCruiseControl.updateActionEventTexts(self)
end

-------------------
---Action Events---
-------------------

---Called on register action events
---@param isActiveForInput boolean
---@param isActiveForInputIgnoreSelection boolean
function ExtendedCruiseControl:onRegisterActionEvents(isActiveForInput, isActiveForInputIgnoreSelection)
    if self.isClient then
        local spec = self.spec_extendedCruiseControl

        self:clearActionEventsTable(spec.actionEvents)
        spec.cruiseControlActionEventId = {}

        -- remove unused cruiseControl actionEvents
        local actionEvents = self.spec_drivable.actionEvents
        for _, actionName in pairs({ InputAction.AXIS_CRUISE_CONTROL, InputAction.TOGGLE_CRUISE_CONTROL }) do
            local actionEvent = actionEvents[actionName]

            if actionEvent ~= nil then
                g_inputBinding:setActionEventActive(actionEvent.actionEventId, false)
            end
        end

        if isActiveForInputIgnoreSelection then
            -- Todo: maybe add powered action events
            local _, actionEventId = self:addActionEvent(spec.actionEvents, InputAction.ECC_RAISE_PERMANENT, self, ExtendedCruiseControl.actionEventRaisePermanent, false, true, true, true, nil)
            g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_NORMAL)
            g_inputBinding:setActionEventActive(actionEventId, not spec.permanentActive)
            g_inputBinding:setActionEventText(actionEventId, g_i18n:getText("action_permanentCruiseControl", self.customEnvironment))
            spec.permanentCruiseControlActionEventId = actionEventId

            for i = 1, 3, 1 do
                _, actionEventId = self:addActionEvent(spec.actionEvents, InputAction["ECC_TOGGLE_CRUISECONTROL_" .. i], self, ExtendedCruiseControl.actionEventCruiseControlGroup, false, true, false, true, nil)
                g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_LOW)
                spec.cruiseControlActionEventId[i] = actionEventId
            end

            _, actionEventId = self:addActionEvent(spec.actionEvents, InputAction.ECC_TOGGLE_CRUISECONTROL_LAST, self, ExtendedCruiseControl.actionEventCruiseControlGroup, false, true, false, true, nil)
            g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_LOW)
            spec.lastCruiseControlActionEventId = actionEventId

            ExtendedCruiseControl.updateActionEventTexts(self)

            _, actionEventId = self:addActionEvent(spec.actionEvents, InputAction.ECC_AXIS_CRUISECONTROL, self, Drivable.actionEventCruiseControlValue, false, true, true, true, nil)

            g_inputBinding:setActionEventText(actionEventId, g_i18n:getText("action_changeCruiseControlLevel"))
            g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_LOW)
        end
    end
end

---Action Event Callback: Raise permanent cruise control
function ExtendedCruiseControl:actionEventRaisePermanent(actionName, inputValue, callbackState, isAnalog)
    local spec = self.spec_extendedCruiseControl
    if not spec.permanentActive then
        spec.raisedPermanentControl = true
    end
end

---Action Event Callback: Toggle cruise control state by actionName
function ExtendedCruiseControl:actionEventCruiseControlGroup(actionName, inputValue, callbackState, isAnalog)
    local spec = self.spec_extendedCruiseControl
    local spec_drivable = self.spec_drivable

    local groupIndex = 3
    if actionName == InputAction.ECC_TOGGLE_CRUISECONTROL_1 then
        groupIndex = 1

    elseif actionName == InputAction.ECC_TOGGLE_CRUISECONTROL_2 then
        groupIndex = 2
        
    elseif actionName == InputAction.ECC_TOGGLE_CRUISECONTROL_LAST then
        groupIndex = spec.activeSpeedGroup
    end

    if not spec.resetIsDirty and groupIndex == spec.activeSpeedGroup then
        spec.permanentActive = false
    end

    if groupIndex == spec.activeSpeedGroup or self:getCruiseControlState() == Drivable.CRUISECONTROL_STATE_OFF then
        spec_drivable.lastInputValues.cruiseControlState = 1
    end

    spec.activeSpeedGroup = groupIndex
    self:updateSpeeds()

    if spec.activeSpeedGroup ~= spec.activeSpeedGroupSent then
        spec.activeSpeedGroupSent = spec.activeSpeedGroup

        self:raiseDirtyFlags(spec.dirtyFlag)
    end
end

---Updates actionEvent texts
function ExtendedCruiseControl:updateActionEventTexts()
    local spec = self.spec_extendedCruiseControl

    if spec.resetIsDirty or spec.doReset or spec.cruiseControlActionEventId == nil then
        return
    end

    local permanentTextActive = not spec.permanentActive and not spec.raisedPermanentControl
    g_inputBinding:setActionEventTextVisibility(spec.permanentCruiseControlActionEventId, permanentTextActive)

    local cruiseControlOff = self:getCruiseControlState() == Drivable.CRUISECONTROL_STATE_OFF
    for index, actionEventId in ipairs(spec.cruiseControlActionEventId) do
        local isActiveGroup = spec.activeSpeedGroup == index
        local text = g_i18n:getText("action_activateCruiseControlN", self.customEnvironment):format(index)
        if spec.raisedPermanentControl then
            text = g_i18n:getText("action_activatePermanentCruiseControlN", self.customEnvironment):format(index)
        end

        if isActiveGroup and not cruiseControlOff then
            if spec.permanentActive then
                text = g_i18n:getText("action_deactivatePermanentCruiseControlN", self.customEnvironment):format(index)
            else
                text = g_i18n:getText("action_deactivateCruiseControlN", self.customEnvironment):format(index)
            end
        end

        g_inputBinding:setActionEventTextVisibility(actionEventId, cruiseControlOff or isActiveGroup)
        g_inputBinding:setActionEventText(actionEventId, text)
    end

    if spec.lastCruiseControlActionEventId ~= nil then
        local text = g_i18n:getText("action_activateCruiseControlLast", self.customEnvironment)
        if spec.raisedPermanentControl then
            text = g_i18n:getText("action_activatePermanentCruiseControlLast", self.customEnvironment)
        end

        g_inputBinding:setActionEventTextVisibility(actionEventId, cruiseControlOff)
        g_inputBinding:setActionEventText(actionEventId, text)
    end
end

----------------
---Overwrites---
----------------

---Overwritten function: setCruiseControlState
---Injects resetting catching if was active
---@param superFunc function super function
---@param state integer cruise control state
---@param noEventSend boolean send event
function ExtendedCruiseControl:setCruiseControlState(superFunc, state, noEventSend)
    local spec = self.spec_extendedCruiseControl

    if spec.raisedPermanentControl and state ~= Drivable.CRUISECONTROL_STATE_OFF then
        spec.permanentActive = true
    end

    if not spec.resetIsDirty and state == Drivable.CRUISECONTROL_STATE_OFF and self:getCruiseControlState() ~= Drivable.CRUISECONTROL_STATE_OFF then
        spec.resetIsDirty = spec.permanentActive
    end

    self:updateSpeeds()
    superFunc(self, state, noEventSend)

    ExtendedCruiseControl.updateActionEventTexts(self)
end

---Overwritten function: setCruiseControlMaxSpeed
---Injects resetting catching if was active
---@param superFunc function super function
---@param speed number speed value
---@param speedReverse number reverse speed value
function ExtendedCruiseControl:setCruiseControlMaxSpeed(superFunc, speed, speedReverse)
    superFunc(self, speed, speedReverse)

    local spec = self.spec_extendedCruiseControl
    if spec.cruiseSpeedGroups ~= nil then
        local speedGroup = spec.cruiseSpeedGroups[spec.activeSpeedGroup]

        speedGroup.forward = speed

        if speedReverse ~= nil then
            speedGroup.reverse = speedReverse
        end
    end
end
