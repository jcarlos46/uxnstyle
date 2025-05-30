#!/usr/bin/env lua
-- uxnstyle.lua
local lexer = require("uxnlexer")

STASH = {}
TOKENS = {}
LABELS = {}
NAMES = {}
IP = 1

local Stack = {}
Stack.__index = Stack

function Stack:new()
    local stack = {items = {}}
    setmetatable(stack, Stack)
    return stack
end

function Stack:push(value)
    table.insert(self.items, value)
end

function Stack:pop()
    if #self.items == 0 then
        error("Stack underflow")
    end
    return table.remove(self.items)
end

function Stack:peek()
    if #self.items == 0 then
        return nil
    end
    return self.items[#self.items]
end

function Stack:size()
    return #self.items
end

function Stack:clear()
    self.items = {}
end

local format_list
function Stack:tostring()
    local result = "["
    for i, v in ipairs(self.items) do
        if i > 1 then result = result .. " " end
        if type(v) == "string" then
            result = result .. '"' .. v .. '"'
        elseif type(v) == "table" then
            result = result .. format_list(v)
        else
            result = result .. tostring(v)
        end
    end
    return result .. "]"
end

-- Helper function to format lists
function format_list(list)
    local result = "["
    for i, item in ipairs(list) do
        if i > 1 then result = result .. " " end
        if type(item) == "string" then
            result = result .. '"' .. item .. '"'
        elseif type(item) == "table" and item.type == "list" then
            result = result .. format_list(item)
        elseif type(item) == "table" and item.type == "quote" then
            result = result .. "[" .. table.concat(item.value, " ") .. "]"
        else
            result = result .. tostring(item)
        end
    end
    return result .. "]"
end

-- Global stack and dictionary
local stack = Stack:new()

local code = [[
]]

local function _print()
    local a = stack:pop()
    print(a)
end
NAMES["print"] = _print

local function pop() stack:pop() end
NAMES["pop"] = pop

local function dup()
    local a = stack:pop()
    stack:push(a)
    stack:push(a)
end
NAMES["dup"] = dup

local function sum()
    local b = stack:pop()
    local a = stack:pop()
    stack:push(a + b)
end
NAMES["+"] = sum

local function sub()
    local b = stack:pop()
    local a = stack:pop()
    stack:push(a - b)
end
NAMES["sub"] = sub

local function when()
    local cond = stack:pop()
    if cond > 0 then
        IP = TOKENS[IP-1].value
    end
end
NAMES["when"] = when

local function ret() IP = table.remove(STASH) end
NAMES["ret"] = ret

local function halt() IP = #TOKENS + 1 end
NAMES["halt"] = halt

local function ps() print(stack:tostring()) end
NAMES["ps"] = ps

local function import_file(filename)
    local file, err = io.open(filename, "r")
    if not file then
        error("Could not open file: " .. filename .. " (" .. (err or "unknown error") .. ")")
    end

    local content = file:read("*all")
    file:close()

    if not content then
        error("Could not read file: " .. filename)
    end

    return content
end

local function eval(token)
    if token.ignore then
        if token.value == "while" then token.ignore = false end
    elseif token.type == "PAR_OPEN" then
        local _stack = {IP}
        local depth = 1
        IP = IP + 1
        while depth > 0 and IP < #TOKENS do
            if TOKENS[IP].type == "PAR_OPEN" then
                depth = depth + 1
                _stack[#_stack + 1] = IP
            elseif TOKENS[IP].type == "PAR_CLOSE" then
                depth = depth - 1
                local open_par_ip = table.remove(_stack)
                TOKENS[IP].value = open_par_ip
                TOKENS[open_par_ip].value = IP
            end
            IP = IP + 1
        end
        IP = IP - 1
    elseif token.type == "NUMBER" or token.type == "STRING" then
        stack:push(token.value)
    elseif token.type == "LIST" then
        local list = {}
        for _, v in ipairs(token.value) do
            table.insert(list, v.value)
        end
        stack:push(list)
    elseif token.type == "NAME" then
        if LABELS[token.value] then
            table.insert(STASH, IP)
            IP = LABELS[token.value]
        elseif NAMES[token.value] then
            if type(NAMES[token.value]) == "function" then
                NAMES[token.value]()
            else
                stack:push(NAMES[token.value])
            end
        else
            error("NAME not found: " .. token.value)
        end
    end
end

if arg[1] then
    local filename = arg[1]
    code = import_file(filename)
else
    print("Usage: uxnstyle.lua <filename>")
    os.exit(1)
end

TOKENS = lexer.tokenize(code)
-- Process labels
for i, token in ipairs(TOKENS) do
    if token.type == "LABEL" then
        local token_str = token.value:sub(2) -- Remove o '@' do início'
        LABELS[token_str] = i
    end
end

if LABELS["main"] then IP = LABELS["main"] end
while IP <= #TOKENS do
    eval(TOKENS[IP])
    IP = IP + 1
end