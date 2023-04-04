Coordinate = {
    X = 1,
    Y = 1
}
function Coordinate:Constructor(values)
    local result = values or {}
    setmetatable(result, self)
    self.__index = self
    return result
end
function Coordinate:Bound(minX, maxX, minY, maxY)
    return Coordinate:Constructor{
        X = math.max(math.min(self.X, maxX), minX),
        Y = math.max(math.min(self.Y, maxY), minY)
    }
end
KeyPressEvent = {
    ShiftDown = nil,
    ControlDown = nil,
    AltDown = nil,
    MetaDown = nil,
    Key = nil,
    OSKeyType = nil,

    statics = {
        controlKeyModifiers = {
            none = 0,
            shift = 1 << 0,
            control = 1 << 1,
            alt = 1 << 2,
            meta = 1 << 3
        }
    }
}
function KeyPressEvent:Constructor(values)
    local result = values or {}
    setmetatable(result, self)
    self.__index = self

    result.ShiftDown = result.ShiftDown or false
    result.ControlDown = result.ControlDown or false
    result.AltDown = result.AltDown or false
    result.MetaDown = result.MetaDown or false

    if result.Key ~= nil then
        result.OSKeyType = ConvertOsKeyType(result.Key)
    elseif result.OSKeyType ~= nil then
        result.Key = GetHandleId(result.OSKeyType)
    end

    return result
end
function KeyPressEvent:ToString()
    return string.char(self.Key) .. (self.ShiftDown and '1' or '0') .. (self.ControlDown and '1' or '0') .. (self.AltDown and '1' or '0') .. (self.MetaDown and '1' or '0')
end
function KeyPressEvent:FromString(text)
    local result = KeyPressEvent:Constructor{
        Key = string.byte(text, 1),
        ShiftDown = string.sub(text, 2, 2) == '1',
        ControlDown = string.sub(text, 3, 3) == '1',
        AltDown = string.sub(text, 4, 4) == '1',
        MetaDown = string.sub(text, 5, 5) == '1'
    }
    return result
end
function KeyPressEvent:SetModifiersFromBitFlags(bitFlags)
    self.ShiftDown = (bitFlags & self.statics.controlKeyModifiers.shift) ~= 0
    self.ControlDown = (bitFlags & self.statics.controlKeyModifiers.control) ~= 0
    self.AltDown = (bitFlags & self.statics.controlKeyModifiers.alt) ~= 0
    self.MetaDown = (bitFlags & self.statics.controlKeyModifiers.meta) ~= 0
end
function KeyPressEvent:GetModifiersAsBitFlags()
    local result = self.statics.controlKeyModifiers.none
    if self.ShiftDown then
        result = result | self.statics.controlKeyModifiers.shift
    end
    if self.ControlDown then
        result = result | self.statics.controlKeyModifiers.control
    end
    if self.AltDown then
        result = result | self.statics.controlKeyModifiers.alt
    end
    if self.MetaDown then
        result = result | self.statics.controlKeyModifiers.meta
    end
    return result
end
function KeyPressEvent:ToUserReadableString()
    local result = ''

    if self.ShiftDown then
        result = result .. 'shift+'
    end
    if self.ControlDown then
        result = result .. 'ctrl+'
    end
    if self.AltDown then
        result = result .. 'alt+'
    end
    if self.MetaDown then
        result = result .. 'meta+'
    end

    result = result .. string.format('<0x%02X>', self.Key)
    result = result .. ' [' .. self.Key .. ']'
    return result
end

TextEditor = {
    TextArea = nil,
    Buffer = {},
    CursorIndex = Coordinate:Constructor(),
    CursorChar = utf8.char(166),
    KeyboardEventTrigger = nil,
    TabWidth = 4,
    TextChangedTrigger = nil,
    QueueTextChangedTrigger = nil,
    PeriodicCursorRender = nil,
    PeriodicResetCameraZoomTrigger = nil,
    UndoHistoryIndex = 1,
    UndoHistory = {},
    SettingsBackup = {
        Camera = nil,
        UnitSelectionBackup = nil,
        IsSelectionEnabledBackup = nil,
        IsSelectionCircleEnabledBackup = nil
    },
    statics = {
        ClipBoard = nil,
        KeyPressEventHandlers = nil
    }
}
function TextEditor:Undo()
    local history = self.UndoHistory[self.UndoHistoryIndex - 1] or {}
    if history.text ~= nil then
        self.UndoHistoryIndex = self.UndoHistoryIndex - 1
        self:SetText(history.text)
        self.CursorIndex = self:FixIndexBounds(history.cursorIndex)
        self:Render()
    end
end
function TextEditor:Redo()
    local history = self.UndoHistory[self.UndoHistoryIndex + 1] or {}
    if history.text ~= nil then
        self.UndoHistoryIndex = self.UndoHistoryIndex + 1
        self:SetText(history.text)
        self.CursorIndex = self:FixIndexBounds(history.cursorIndex)
        self:Render()
    end
end
function TextEditor:MoveCoordinate(coordinate, delta, stopPredicate)
    local result = Coordinate:Constructor({
        X = coordinate.X,
        Y = coordinate.Y
    })
    if delta > 0 then
        for count = 1, delta do
            result = self:MoveCoordinateRight(result)
            if (stopPredicate ~= nil and stopPredicate(result)) then
                break
            end
        end
    elseif delta < 0 then
        for count = delta, -1 do
            result = self:MoveCoordinateLeft(result)
            if (stopPredicate ~= nil and stopPredicate(result)) then
                break
            end
        end
    end

    return result
end
function TextEditor:MoveCoordinateLeft(coordinate)
    local result = Coordinate:Constructor({
        X = coordinate.X,
        Y = coordinate.Y
    })
    if result.X == 1 then
        if result.Y > 1 then
            result.Y = result.Y - 1
            result.X = math.maxinteger
            result = self:FixIndexBounds(result)
        end
    else
        result.X = result.X - 1
    end
    return result
end
function TextEditor:MoveCoordinateRight(coordinate)
    local result = Coordinate:Constructor({
        X = coordinate.X,
        Y = coordinate.Y
    })
    if result.X > string.len(self.Buffer[result.Y]) then
        if result.Y < #self.Buffer then
            result.Y = result.Y + 1
            result.X = 1
        end
    else
        result.X = result.X + 1
    end

    return result
end
function TextEditor:BackupSettings()
    self.SettingsBackup = {
        Camera = GetCurrentCameraSetup(),
        UnitSelectionBackup = {},
        IsSelectionEnabledBackup = BlzIsSelectionEnabled(),
        IsSelectionCircleEnabledBackup = BlzIsSelectionCircleEnabled()
    }

    local group = CreateGroup()
    GroupEnumUnitsSelected(group, GetLocalPlayer(), nil)
    ForGroup(group, function()
        self.SettingsBackup.UnitSelectionBackup[#self.SettingsBackup.UnitSelectionBackup + 1] = GetEnumUnit()
    end)
    DestroyGroup(group)
end
function TextEditor:ResetCamera()
    if self.SettingsBackup.Camera ~= nil then
        CameraSetupApply(self.SettingsBackup.Camera, false, false)
    end
end
function TextEditor:IsVisible()
    return BlzFrameIsVisible(self.TextArea)
end
function TextEditor:SetVisible(visible)
    BlzFrameSetVisible(self.TextArea, visible)
    if visible then
        SetCameraRotateMode(0, 0, 0, 0) -- don't allow arrow keys or DEL key to move camera
        self:BackupSettings()
        ClearSelectionForPlayer(GetLocalPlayer())
        BlzEnableSelections(false, false)
        EnableTrigger(self.PeriodicCursorRender)
        EnableTrigger(self.PeriodicResetCameraZoomTrigger)
        EnableTrigger(self.KeyboardEventTrigger)
        self:Render()
    else
        StopCamera()
        ResetToGameCamera(0)
        CameraSetupApply(self.SettingsBackup.Camera, false, false)
        if self.SettingsBackup.UnitSelectionBackup ~= nil then
            ClearSelectionForPlayer(GetLocalPlayer())
            for key, unit in pairs(self.SettingsBackup.UnitSelectionBackup) do
                SelectUnit(unit, true)
            end
        end
        BlzEnableSelections(self.SettingsBackup.IsSelectionEnabledBackup, self.SettingsBackup.IsSelectionCircleEnabledBackup)
        DisableTrigger(self.PeriodicCursorRender)
        DisableTrigger(self.PeriodicResetCameraZoomTrigger)
        DisableTrigger(self.KeyboardEventTrigger)
    end
end
function TextEditor:GetTextAtCoordinate(coordinate)
    local line = self.Buffer[coordinate.Y] or ""
    return string.sub(line, coordinate.X, coordinate.X)
end
function TextEditor:GetText()
    return self:GetTextWithCursor("")
end
function TextEditor:GetTextWithCursor(cursorChar)
    -- Using table.concat to combine lines into 1 string
    -- For memory/speed we want to avoid cloning data
    -- Since LUA strings are read-only, we want cursor injected during concatenation
    -- Since LUA tables are copy-by-reference, we can't inject cursor without modifying the real self.Buffer so we inject it into real Buffer and revert it afterwards

    local withoutCursor = self.Buffer[self.CursorIndex.Y] or ""
    self.Buffer[self.CursorIndex.Y] = self:SpliceString(withoutCursor, self.CursorIndex.X, 0, cursorChar)
    local result = table.concat(self.Buffer, "\r")
    self.Buffer[self.CursorIndex.Y] = withoutCursor
    return result
end
function TextEditor:SetText(text)
    self.Buffer = {}

    local currentLine = {}
    local lastCharWasCarriageReturn = false
    for charIndex = 1, string.len(text) do
        local char = string.sub(text, charIndex, charIndex)

        if char == "\t" then
            currentLine[#currentLine + 1] = string.rep(" ", self.TabWidth)
        elseif char == "\r" then
            self.Buffer[#self.Buffer + 1] = table.concat(currentLine)
            currentLine = {}
        elseif char == "\n" then
            if lastCharWasCarriageReturn ~= true then -- count \r\n as 1 break, not 2
                self.Buffer[#self.Buffer + 1] = table.concat(currentLine)
                currentLine = {}
            end
        else
            currentLine[#currentLine + 1] = char
        end

        lastCharWasCarriageReturn = char == "\r"
    end
    self.Buffer[#self.Buffer + 1] = table.concat(currentLine)

    self.CursorIndex = self:FixIndexBounds(Coordinate:Constructor{
        X = math.maxinteger,
        Y = math.maxinteger
    })

    self:Render()
    TriggerExecute(self.QueueTextChangedTrigger)
end
function TextEditor:ResetFocusedControlHack()
    BlzFrameClick(BlzGetFrameByName("UpperButtonBarMenuButton", 0))
    ForceUICancel()
end
function TextEditor:FixIndexBounds(coordinate)
    if #self.Buffer == 0 then
        self.Buffer[1] = ""
    end
    local yBounded = coordinate:Bound(1, math.maxinteger, 1, #self.Buffer)
    return yBounded:Bound(1, string.len(self.Buffer[yBounded.Y]) + 1, 1, math.maxinteger)
end
function TextEditor:SpliceString(originalText, index, deleteCount, appendText)
    if deleteCount < 0 then
        deleteCount = 0
    end
    appendText = appendText or ""
    local prefix = ""
    if index > 1 then
        prefix = string.sub(originalText, 1, index - 1)
    end
    return prefix .. appendText .. string.sub(originalText, index + deleteCount)
end
function TextEditor:DeleteCharactersFromBuffer(index, count)
    index = self:FixIndexBounds(index)
    if index.X + count > string.len(self.Buffer[index.Y]) + 1 then
        count = string.len(self.Buffer[index.Y]) + 1 - index.X
    end

    self.Buffer[index.Y] = self:SpliceString(self.Buffer[index.Y], index.X, count)
    self.CursorIndex = self:FixIndexBounds(index)
    self:Render()
    TriggerExecute(self.QueueTextChangedTrigger)
end
function TextEditor:AddTextToBuffer(text)
    self.CursorIndex = self:FixIndexBounds(self.CursorIndex)
    self:AddTextToBufferAtIndex(text, self.CursorIndex)
    self.CursorIndex.X = self.CursorIndex.X + string.len(text)
    self.CursorIndex = self:FixIndexBounds(self.CursorIndex)
    self:Render()
    TriggerExecute(self.QueueTextChangedTrigger)
end
function TextEditor:AddTextToBufferAtIndex(text, index)
    index = self:FixIndexBounds(index)
    self.Buffer[index.Y] = self:SpliceString(self.Buffer[index.Y], index.X, 0, text)
    self:Render()
    TriggerExecute(self.QueueTextChangedTrigger)
end
function TextEditor:DeleteNewlineAtCursor()
    self.Buffer[self.CursorIndex.Y] = self.Buffer[self.CursorIndex.Y] .. (self.Buffer[self.CursorIndex.Y + 1] or "")

    local lineCount = #self.Buffer
    for y = self.CursorIndex.Y + 1, lineCount - 1 do
        self.Buffer[y] = self.Buffer[y + 1]
    end
    table.remove(self.Buffer, lineCount)
    self:Render()
    TriggerExecute(self.QueueTextChangedTrigger)
end
function TextEditor:RegisterKeyPressEventHandlers()
    self.statics.KeyPressEventHandlers = {}
    function addKeyStroke(keyPressEvent, char)
        self.statics.KeyPressEventHandlers[keyPressEvent:ToString()] = (function(self)
            self:AddTextToBuffer(char)
            TriggerExecute(self.QueueTextChangedTrigger)
        end)
    end

    self.statics.KeyPressEventHandlers[KeyPressEvent:Constructor{
        ControlDown = true,
        OSKeyType = OSKEY_C
    }:ToString()] = (function(self)
        self.statics.ClipBoard = self.Buffer[self.CursorIndex.Y]
    end)
    self.statics.KeyPressEventHandlers[KeyPressEvent:Constructor{
        ControlDown = true,
        OSKeyType = OSKEY_X
    }:ToString()] = (function(self)
        self.statics.ClipBoard = self.Buffer[self.CursorIndex.Y]
        self.Buffer[self.CursorIndex.Y] = ""
        self:Render()
    end)
    self.statics.KeyPressEventHandlers[KeyPressEvent:Constructor{
        ControlDown = true,
        OSKeyType = OSKEY_V
    }:ToString()] = (function(self)
        self:AddTextToBuffer(self.statics.ClipBoard or "")
    end)

    self.statics.KeyPressEventHandlers[KeyPressEvent:Constructor{
        AltDown = true,
        OSKeyType = OSKEY_UP
    }:ToString()] = (function(self)
        if (self.CursorIndex.Y <= 1) then
            return
        end

        local previousLine = self.Buffer[self.CursorIndex.Y - 1] or ""
        self.Buffer[self.CursorIndex.Y - 1] = self.Buffer[self.CursorIndex.Y]
        self.Buffer[self.CursorIndex.Y] = previousLine
        self.CursorIndex.Y = self.CursorIndex.Y - 1
        self.CursorIndex = self:FixIndexBounds(self.CursorIndex)
        self:Render()
    end)
    self.statics.KeyPressEventHandlers[KeyPressEvent:Constructor{
        AltDown = true,
        OSKeyType = OSKEY_DOWN
    }:ToString()] = (function(self)
        if self.CursorIndex.Y >= #self.Buffer then
            return
        end

        local currentLine = self.Buffer[self.CursorIndex.Y]
        self.Buffer[self.CursorIndex.Y] = self.Buffer[self.CursorIndex.Y + 1] or ""
        self.Buffer[self.CursorIndex.Y + 1] = currentLine
        self.CursorIndex.Y = self.CursorIndex.Y + 1
        self.CursorIndex = self:FixIndexBounds(self.CursorIndex)
        self:Render()
    end)

    self.statics.KeyPressEventHandlers[KeyPressEvent:Constructor{
        ControlDown = true,
        OSKeyType = OSKEY_Z
    }:ToString()] = (function(self)
        self:Undo()
    end)
    self.statics.KeyPressEventHandlers[KeyPressEvent:Constructor{
        ControlDown = true,
        OSKeyType = OSKEY_Y
    }:ToString()] = (function(self)
        self:Redo()
    end)

    self.statics.KeyPressEventHandlers[KeyPressEvent:Constructor{
        ControlDown = true,
        OSKeyType = OSKEY_HOME
    }:ToString()] = (function(self)
        self.CursorIndex.X = 1
        self.CursorIndex.Y = 1
        self.CursorIndex = self:FixIndexBounds(self.CursorIndex)
        self:Render()
    end)
    self.statics.KeyPressEventHandlers[KeyPressEvent:Constructor{
        ControlDown = true,
        OSKeyType = OSKEY_END
    }:ToString()] = (function(self)
        self.CursorIndex.X = math.maxinteger
        self.CursorIndex.Y = math.maxinteger
        self.CursorIndex = self:FixIndexBounds(self.CursorIndex)
        self:Render()
    end)

    self.statics.KeyPressEventHandlers[KeyPressEvent:Constructor{
        OSKeyType = OSKEY_HOME
    }:ToString()] = (function(self)
        self.CursorIndex.X = 1
        self.CursorIndex = self:FixIndexBounds(self.CursorIndex)
        self:Render()
    end)
    self.statics.KeyPressEventHandlers[KeyPressEvent:Constructor{
        OSKeyType = OSKEY_END
    }:ToString()] = (function(self)
        self.CursorIndex.X = math.maxinteger
        self.CursorIndex = self:FixIndexBounds(self.CursorIndex)
        self:Render()
    end)
    self.statics.KeyPressEventHandlers[KeyPressEvent:Constructor{
        OSKeyType = OSKEY_UP
    }:ToString()] = (function(self)
        self.CursorIndex.Y = self.CursorIndex.Y - 1
        self.CursorIndex = self:FixIndexBounds(self.CursorIndex)
        self:Render()
    end)
    self.statics.KeyPressEventHandlers[KeyPressEvent:Constructor{
        OSKeyType = OSKEY_DOWN
    }:ToString()] = (function(self)
        self.CursorIndex.Y = self.CursorIndex.Y + 1
        self.CursorIndex = self:FixIndexBounds(self.CursorIndex)
        self:Render()
    end)
    self.statics.KeyPressEventHandlers[KeyPressEvent:Constructor{
        OSKeyType = OSKEY_LEFT
    }:ToString()] = (function(self)
        self.CursorIndex = self:MoveCoordinate(self.CursorIndex, -1)
        self:Render()
    end)
    self.statics.KeyPressEventHandlers[KeyPressEvent:Constructor{
        OSKeyType = OSKEY_RIGHT
    }:ToString()] = (function(self)
        self.CursorIndex = self:MoveCoordinate(self.CursorIndex, 1)
        self:Render()
    end)

    local function ControlArrowStopPredicate(self, coordinate, movingBackwards, stopOnSpace)
        if coordinate.X <= 1 or coordinate.X > string.len(self.Buffer[coordinate.Y]) then
            return true
        end
        local nextCoordinate = movingBackwards and TextEditor:MoveCoordinateLeft(coordinate) or coordinate
        local nextChar = self:GetTextAtCoordinate(nextCoordinate)
        return (stopOnSpace and nextChar == " ") or (not stopOnSpace and nextChar ~= " ")
    end
    self.statics.KeyPressEventHandlers[KeyPressEvent:Constructor{
        ControlDown = true,
        OSKeyType = OSKEY_LEFT
    }:ToString()] = (function(self)
        local nextChar = self:GetTextAtCoordinate(self:MoveCoordinateLeft(self.CursorIndex))
        self.CursorIndex = self:MoveCoordinate(self.CursorIndex, -math.maxinteger, function(coordinate)
            return ControlArrowStopPredicate(self, coordinate, true, nextChar ~= " ")
        end)
        self:Render()
    end)
    self.statics.KeyPressEventHandlers[KeyPressEvent:Constructor{
        ControlDown = true,
        OSKeyType = OSKEY_RIGHT
    }:ToString()] = (function(self)
        local nextChar = self:GetTextAtCoordinate(self.CursorIndex)
        self.CursorIndex = self:MoveCoordinate(self.CursorIndex, math.maxinteger, function(coordinate)
            return ControlArrowStopPredicate(self, coordinate, false, nextChar ~= " ")
        end)
        self:Render()
    end)
    self.statics.KeyPressEventHandlers[KeyPressEvent:Constructor{
        ControlDown = true,
        OSKeyType = OSKEY_BACKSPACE
    }:ToString()] = (function(self)
        local nextChar = self:GetTextAtCoordinate(self:MoveCoordinateLeft(self.CursorIndex))
        local deleteFrom = self:MoveCoordinate(self.CursorIndex, -math.maxinteger, function(coordinate)
            return ControlArrowStopPredicate(self, coordinate, true, nextChar ~= " ")
        end)
        if self.CursorIndex.Y ~= deleteFrom.Y then
            self.statics.KeyPressEventHandlers[KeyPressEvent:Constructor{
                OSKeyType = OSKEY_BACKSPACE
            }:ToString()](self)
        else
            local deleteCount = self.CursorIndex.X - deleteFrom.X
            self.CursorIndex = deleteFrom
            self:DeleteCharactersFromBuffer(deleteFrom, deleteCount)
        end
    end)
    self.statics.KeyPressEventHandlers[KeyPressEvent:Constructor{
        ControlDown = true,
        OSKeyType = OSKEY_DELETE
    }:ToString()] = (function(self)
        local nextChar = self:GetTextAtCoordinate(self.CursorIndex)
        local deleteTo = self:MoveCoordinate(self.CursorIndex, math.maxinteger, function(coordinate)
            return ControlArrowStopPredicate(self, coordinate, false, nextChar ~= " ")
        end)
        if self.CursorIndex.Y ~= deleteTo.Y then
            self.statics.KeyPressEventHandlers[KeyPressEvent:Constructor{
                OSKeyType = OSKEY_DELETE
            }:ToString()](self)
        else
            self:DeleteCharactersFromBuffer(self.CursorIndex, deleteTo.X - self.CursorIndex.X)
        end
    end)

    self.statics.KeyPressEventHandlers[KeyPressEvent:Constructor{
        OSKeyType = OSKEY_BACKSPACE
    }:ToString()] = (function(self)
        if self.CursorIndex.X <= 1 then
            if self.CursorIndex.Y > 1 then
                self.CursorIndex.Y = self.CursorIndex.Y - 1
                self.CursorIndex.X = math.maxinteger
                self.CursorIndex = self:FixIndexBounds(self.CursorIndex)
                self:DeleteNewlineAtCursor()
            end
        else
            local coordinate = Coordinate:Constructor{
                X = self.CursorIndex.X - 1,
                Y = self.CursorIndex.Y
            }
            local char = self:GetTextAtCoordinate(coordinate)
            if char == " " and string.sub(self.Buffer[coordinate.Y], coordinate.X - self.TabWidth + 1, coordinate.X) == string.rep(" ", self.TabWidth) then
                coordinate.X = coordinate.X - self.TabWidth + 1
                self:DeleteCharactersFromBuffer(coordinate, self.TabWidth)
            else
                self:DeleteCharactersFromBuffer(coordinate, 1)
            end
        end
    end)

    self.statics.KeyPressEventHandlers[KeyPressEvent:Constructor{
        OSKeyType = OSKEY_DELETE
    }:ToString()] = (function(self)
        if self.CursorIndex.X > string.len(self.Buffer[self.CursorIndex.Y]) then
            if self.CursorIndex.Y < #self.Buffer then
                self:DeleteNewlineAtCursor()
            end
        else
            local coordinate = Coordinate:Constructor{
                X = self.CursorIndex.X,
                Y = self.CursorIndex.Y
            }
            local char = self:GetTextAtCoordinate(coordinate)
            if char == " " and string.sub(self.Buffer[coordinate.Y], coordinate.X, coordinate.X + self.TabWidth - 1) == string.rep(" ", self.TabWidth) then
                self:DeleteCharactersFromBuffer(coordinate, self.TabWidth)
            else
                self:DeleteCharactersFromBuffer(coordinate, 1)
            end
        end
    end)

    self.statics.KeyPressEventHandlers[KeyPressEvent:Constructor{
        OSKeyType = OSKEY_RETURN
    }:ToString()] = (function(self)
        local lineCount = #self.Buffer
        for y = 1, lineCount - self.CursorIndex.Y do
            self.Buffer[lineCount + 2 - y] = self.Buffer[lineCount + 1 - y]
        end
        local currentLine = self.Buffer[self.CursorIndex.Y]
        self.Buffer[self.CursorIndex.Y] = string.sub(currentLine, 1, self.CursorIndex.X - 1)
        self.Buffer[self.CursorIndex.Y + 1] = string.sub(currentLine, self.CursorIndex.X)
        self.CursorIndex.X = 1
        self.CursorIndex.Y = self.CursorIndex.Y + 1
        self.CursorIndex = self:FixIndexBounds(self.CursorIndex)
        self:Render()
        -- hide chat menu (still shows for a split second)
        self:ResetFocusedControlHack()
    end)

    local shiftedKeys = {}
    shiftedKeys["0"] = ")"
    shiftedKeys["1"] = "!"
    shiftedKeys["2"] = "@"
    shiftedKeys["3"] = "#"
    shiftedKeys["4"] = "$"
    shiftedKeys["5"] = "%"
    shiftedKeys["6"] = "^"
    shiftedKeys["7"] = "&"
    shiftedKeys["8"] = "*"
    shiftedKeys["9"] = "("
    shiftedKeys[";"] = ":"
    shiftedKeys["="] = "+"
    shiftedKeys[","] = "<"
    shiftedKeys["-"] = "_"
    shiftedKeys["."] = ">"
    shiftedKeys["/"] = "?"
    shiftedKeys["`"] = "~"
    shiftedKeys["["] = "{"
    shiftedKeys["\\"] = "|"
    shiftedKeys["]"] = "}"
    shiftedKeys["'"] = "\""

    local osKeyTranslations = {}
    osKeyTranslations[OSKEY_OEM_1] = ";"
    osKeyTranslations[OSKEY_OEM_PLUS] = "=" -- + is the shifted version
    osKeyTranslations[OSKEY_OEM_COMMA] = ","
    osKeyTranslations[OSKEY_OEM_MINUS] = "-"
    osKeyTranslations[OSKEY_OEM_PERIOD] = "."
    osKeyTranslations[OSKEY_OEM_2] = "/"
    osKeyTranslations[OSKEY_OEM_3] = "`"
    osKeyTranslations[OSKEY_OEM_4] = "["
    osKeyTranslations[OSKEY_OEM_5] = "\\"
    osKeyTranslations[OSKEY_OEM_6] = "]"
    osKeyTranslations[OSKEY_OEM_7] = "'"

    osKeyTranslations[OSKEY_ADD] = "+"
    osKeyTranslations[OSKEY_SUBTRACT] = "-"
    osKeyTranslations[OSKEY_MULTIPLY] = "*"
    osKeyTranslations[OSKEY_DIVIDE] = "/"
    osKeyTranslations[OSKEY_DECIMAL] = "."
    osKeyTranslations[OSKEY_SPACE] = " "
    osKeyTranslations[OSKEY_TAB] = string.rep(" ", self.TabWidth)

    for asciiCodeLower = string.byte('a', 1), string.byte('z', 1) do
        local lower = string.char(asciiCodeLower)
        local upper = string.upper(lower)
        local osKeyType = load("return OSKEY_" .. upper)()
        osKeyTranslations[osKeyType] = lower
        shiftedKeys[lower] = upper
    end

    for number = 0, 9 do
        local char = tostring(number)
        osKeyTranslations[load("return OSKEY_NUMPAD" .. number)()] = char
        osKeyTranslations[load("return OSKEY_" .. number)()] = char
    end

    for osKeyType, char in pairs(osKeyTranslations) do
        local event = KeyPressEvent:Constructor{
            OSKeyType = osKeyType
        }
        addKeyStroke(event, char)
        local shiftedChar = shiftedKeys[char]
        if shiftedChar ~= nil then
            event.ShiftDown = true
            addKeyStroke(event, shiftedChar)
        end
    end
end
function TextEditor:ProcessKeyPressEvent(keyPressEvent)
    self.statics.KeyPressEventHandlers[keyPressEvent:ToString()](self)
end
function TextEditor:SetPositionAndSize(x, y, width, height)
    BlzFrameSetAbsPoint(self.TextArea, FRAMEPOINT_TOPLEFT, x, y)
    BlzFrameSetSize(self.TextArea, width, height)
end
function TextEditor:Constructor()
    local result = {}
    setmetatable(result, self)
    self.__index = self

    if self.statics.KeyPressEventHandlers == nil then
        BlzLoadTOCFile("war3mapImported\\TextEditor.toc")
        TextEditor:RegisterKeyPressEventHandlers()
    end

    result.PeriodicResetCameraZoomTrigger = CreateTrigger()
    TriggerAddAction(result.PeriodicResetCameraZoomTrigger, function()
        -- PageUp/Down zoom in & out the camera, but haven't found a way to disable zoom
        result:ResetCamera()
    end)
    TriggerRegisterTimerEvent(result.PeriodicResetCameraZoomTrigger, .1, true)

    local showCursor = true
    result.PeriodicCursorRender = CreateTrigger()
    TriggerAddAction(result.PeriodicCursorRender, function()
        result:Render(showCursor and result.CursorChar or "  ")
        showCursor = not showCursor
    end)
    TriggerRegisterTimerEvent(result.PeriodicCursorRender, .5, true)

    -- To avoid notifying 2x for same edit, we use flag to determine if already queued and execute Queue trigger immediately but use delay on actual notification trigger
    result.TextChangedTrigger = CreateTrigger()
    local textChangeQueued = false
    result.QueueTextChangedTrigger = CreateTrigger()
    TriggerAddAction(result.QueueTextChangedTrigger, function()
        if not textChangeQueued then
            PostTriggerExecuteBJ(result.TextChangedTrigger, false)
        end
        textChangeQueued = true
    end)
    result.TextChangedTrigger = CreateTrigger()
    TriggerAddAction(result.TextChangedTrigger, function()
        textChangeQueued = false
    end)

    result:CreateTextArea()
    result:SetPositionAndSize(0.00, 1.00, 1.00, 1.00)
    result:RegisterKeyboardTriggers()
    result:Render()
    result:BackupSettings()
    result:SetVisible(false)

    return result
end
function TextEditor:Dispose()
    DestroyTrigger(self.PeriodicCursorRender)
    DestroyTrigger(self.PeriodicResetCameraZoomTrigger)
    DestroyTrigger(self.QueueTextChangedTrigger)
    DestroyTrigger(self.TextChangedTrigger)
    DestroyTrigger(self.KeyboardEventTrigger)
    BlzDestroyFrame(self.TextArea)
end
function TextEditor:CreateTextArea()
    self.TextArea = BlzCreateFrame("EscMenuTextAreaTemplate", BlzGetOriginFrame(ORIGIN_FRAME_GAME_UI, 0), 0, 0)
    BlzFrameSetEnable(self.TextArea, false) -- Prevent mouse clicks on frame because keyboard events don't occur while frame is focused
end
function TextEditor:Render(cursorChar)
    local withoutCursor = self:GetText()
    if (self.UndoHistory[self.UndoHistoryIndex] or {}).text ~= withoutCursor then
        self.UndoHistoryIndex = self.UndoHistoryIndex + 1
        self.UndoHistory[self.UndoHistoryIndex] = {
            text = withoutCursor,
            cursorIndex = self.CursorIndex
        }
    end

    cursorChar = cursorChar or self.CursorChar
    local renderText = self:GetTextWithCursor(cursorChar)
    if renderText == "" then
        renderText = " " -- fix bug where "" is ignored so replacing "A" then "" leaves "A" rendered
    end
    local textWithCursor = BlzFrameSetText(self.TextArea, renderText)
end
function TextEditor:RegisterKeyboardTriggers()
    self.KeyboardEventTrigger = CreateTrigger()
    TriggerAddAction(self.KeyboardEventTrigger, function()
        local modifierBitFlags = BlzGetTriggerPlayerMetaKey()

        local event = KeyPressEvent:Constructor{
            OSKeyType = BlzGetTriggerPlayerKey()
        }
        event:SetModifiersFromBitFlags(modifierBitFlags)

        self:ProcessKeyPressEvent(event)
    end)

    local player = GetLocalPlayer()

    for keyPress, handler in pairs(self.statics.KeyPressEventHandlers) do
        local event = KeyPressEvent:FromString(keyPress)
        BlzTriggerRegisterPlayerKeyEvent(self.KeyboardEventTrigger, player, event.OSKeyType, event:GetModifiersAsBitFlags(), true)
    end
end
