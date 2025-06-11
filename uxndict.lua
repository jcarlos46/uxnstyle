-- uxndict.lua
local lexer = require("uxnlexer")
local M = {}

local Stack = {}
Stack.__index = Stack

M.LAST_TOKEN_NAME = ""
M.LAST_TOKEN_LINE = 0
M.LAST_TOKEN_COLUMN = 0

-- Print error
function print_error(msg)
    msg = arg[1]..":"..M.LAST_TOKEN_LINE..":"..M.LAST_TOKEN_COLUMN.." "..M.LAST_TOKEN_NAME..": "..msg
    if CLI then print(msg)
    else error(msg) end
end

function print_error_type(expected, got)
    print_error(expected.." was expected, but got "..got)
end

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
		print_error("stack underflow")
    end
    return table.remove(self.items)
end

function Stack:peek()
    if #self.items == 0 then
		print_error("stack is empty")
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
            result = result .. v
        elseif type(v) == "table" then
            result = result .. format_list(v)
        else
            result = result .. v
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
LABELS = {}
stack = Stack:new()
NAMES = {}
CLI = false
DEBUG = false

local function pop() 
    table.remove(stack.items)
end
NAMES["pop"] = pop

local function dup()
    local a = M.stack:pop()
    M.stack:push(a)
    M.stack:push(a)
end
NAMES["dup"] = dup

local function sum()
    local b = M.stack:pop()
    local a = M.stack:pop()
    M.stack:push(a + b)
end
NAMES["+"] = sum

local function gt()
    local a = M.stack:pop()
    local b = M.stack:pop()
    if (b > a) then
        M.stack:push(1)
    else
        M.stack:push(0)
    end
end
NAMES[">"] = gt

local function lt()
    local a = M.stack:pop()
    local b = M.stack:pop()
    if (b < a) then
        M.stack:push(1)
    else
        M.stack:push(0)
    end
end
NAMES["<"] = lt

local function eq()
    local a = stack:pop()
    local b = stack:pop()
    
    local function compare_lists(list1, list2)
        if #list1 ~= #list2 then return false end
        for i = 1, #list1 do
            if list1[i] ~= list2[i] then return false end
        end
        return true
    end
    
    local result = false
    if type(a) == "table" and type(b) == "table" then
        result = compare_lists(a, b)
    else
        result = (b == a)
    end
    
    if result then
        M.stack:push(1)
    else
        M.stack:push(0)
    end
end
NAMES["="] = eq

local function sub()
    local b = M.stack:pop()
    local a = M.stack:pop()
    M.stack:push(a - b)
end
NAMES["sub"] = sub

local function sum()
    local b = M.stack:pop()
    local a = M.stack:pop()
    M.stack:push(a * b)
end
NAMES["*"] = sum

local function mod()
    local b = M.stack:pop()
    local a = M.stack:pop()
    M.stack:push(a % b)
end
NAMES["mod"] = mod

local function div()
    local b = M.stack:pop()
    local a = M.stack:pop()
    M.stack:push(math.floor(a / b))
end
NAMES["/"] = div
NAMES["div"] = div

local function ps() 
    print(stack:tostring())
end
NAMES["ps"] = ps

local function debug() DEBUG=true end
NAMES["debug"] = debug

local function cli() CLI=true end
NAMES["cli"] = cli

-- Stack manipulation
NAMES["dup"] = function()
    local a = stack:peek()
    stack:push(a)
end

NAMES["drop"] = function()
    stack:pop()
end

NAMES["swap"] = function()
    local b = stack:pop()
    local a = stack:pop()
    stack:push(b)
    stack:push(a)
end

NAMES["rot"] = function()
    local c = stack:pop()
    local b = stack:pop()
    local a = stack:pop()
    stack:push(b)
    stack:push(c)
    stack:push(a)
end

local function over()
    local b = stack:pop()
    local a = stack:pop()
    stack:push(a)
    stack:push(b)
    stack:push(a)
end
NAMES["over"] = over

local function utf8decode(s)
    local b = string.byte
    local c1 = b(s, 1)
    if c1 < 0x80 then
        return c1
    elseif c1 < 0xE0 then
        local c2 = b(s, 2)
        return ((c1 - 0xC0) * 0x40) + (c2 - 0x80)
    elseif c1 < 0xF0 then
        local c2, c3 = b(s, 2), b(s, 3)
        return ((c1 - 0xE0) * 0x1000) + ((c2 - 0x80) * 0x40) + (c3 - 0x80)
    elseif c1 < 0xF8 then
        local c2, c3, c4 = b(s, 2), b(s, 3), b(s, 4)
        return ((c1 - 0xF0) * 0x40000) + ((c2 - 0x80) * 0x1000) +
               ((c3 - 0x80) * 0x40) + (c4 - 0x80)
    end
end

local function utf8encode(codepoint)
    if codepoint <= 0x7F then
        return string.char(codepoint)
    elseif codepoint <= 0x7FF then
        return string.char(
            0xC0 + math.floor(codepoint / 0x40),
            0x80 + (codepoint % 0x40)
        )
    elseif codepoint <= 0xFFFF then
        return string.char(
            0xE0 + math.floor(codepoint / 0x1000),
            0x80 + (math.floor(codepoint / 0x40) % 0x40),
            0x80 + (codepoint % 0x40)
        )
    elseif codepoint <= 0x10FFFF then
        return string.char(
            0xF0 + math.floor(codepoint / 0x40000),
            0x80 + (math.floor(codepoint / 0x1000) % 0x40),
            0x80 + (math.floor(codepoint / 0x40) % 0x40),
            0x80 + (codepoint % 0x40)
        )
    else
        error("Código Unicode inválido: " .. tostring(codepoint))
    end
end

-- FFI
local function utf8fromlist(list)
    local result = {}
    for _, codepoint in ipairs(list) do
        table.insert(result, utf8encode(codepoint))
    end
    return table.concat(result)
end

local function ffi()
    local return_type = M.stack:pop()
    return_type = M.utf8fromlist(return_type)
    
    local args_count = M.stack:pop()
    args_count = args_count

    local lua_func = M.stack:pop()
    lua_func = M.utf8fromlist(lua_func)

    -- Resolve a função Lua, incluindo namespaces
    local function resolve_function(path)
        local parts = {}
        for part in string.gmatch(path, "[^%.]+") do
            table.insert(parts, part)
        end

        local func = _G
        for _, part in ipairs(parts) do
            func = func[part]
            if not func then break end
        end
        return func
    end

    local resolved_func = resolve_function(lua_func)
    if type(resolved_func) ~= "function" then
        print_error(lua_func.. " is not a valid function")
    end

    local args = {}
    for i = 1, args_count do
        local arg = stack:pop()
        if type(arg) == "table" then
            arg = M.utf8fromlist(arg)
        end
        table.insert(args, arg)
    end

    local unpack = table.unpack or unpack
    local result = resolved_func(unpack(args))
    if return_type ~= "VOID" then
        stack:push(result)
    end
end
NAMES["ffi"] = ffi

local function read()
    local a = io.read()
    stack:push(a)
end
NAMES["read"] = read

NAMES["cons"] = function() -- add element to front of list
    local list = stack:pop()
    local element = stack:pop()
    if type(list) ~= "table" then
        print_error_type("LIST", type(list))
    end
    table.insert(list, 1, element) 
    stack:push(list)
end

NAMES["uncons"] = function() -- remove first element from list
    local list = stack:pop()
    if type(list) ~= "table" then
        print_error_type("LIST", type(list))
    end
    if #list == 0 then
        print_error("got empty LIST")
    end
    local first = list[1]
    local rest = {}
    for i = 2, #list do
        table.insert(rest, list[i])
    end
    stack:push(rest)
    stack:push(first)
end

NAMES["concat"] = function()
    local list_b = stack:pop()
     if type(list_b) ~= "table" then
        print_error_type("LIST", type(list_b))
    end
    local list_a = stack:pop()
     if type(list_a) ~= "table" then
        print_error_type("LIST", type(list_a))
    end
    for i = 1, #list_b do
        table.insert(list_a, list_b[i])
    end

    stack:push(list_a)
end

NAMES["empty?"] = function()
    local list = stack:peek()
    if type(list) ~= "table" then
        print_error_type("LIST", type(list))
    end
    if #list == 0 then 
        stack:push(1)
    else 
        stack:push(0)
    end
end

NAMES["store"] = function()
    local index = stack:pop()
    if type(index) ~= "number" then print_error_type("NUMBER", type(index)) end
    local value = stack:pop()
    NAMES[index] = value
end

NAMES["load"] = function()
    local index = stack:pop()
    if type(index) ~= "number" then print_error_type("NUMBER", type(index)) end
    if NAMES[index] == nil then print_error("Index "..index.." does not exist") return end
    stack:push(NAMES[index])
end

local function pick()
    local index = stack:pop()
    if type(index) ~= "number" then print_error_type("NUMBER", type(index)) end
    local list = stack:pop()
    if type(list) ~= "table" then print_error_type("LIST", type(index)) end
    if list[index] ~= nil then print_error("index "..index.." was not found.") end
    stack:push(list[index+1])
    stack:push(list)
end
NAMES['pick'] = pick

local function sleep()
    local seconds = stack:pop()
    if type(seconds) ~= "number" then
        print_error_type("NUMBER", type(seconds))
    end
    local t0 = os.clock()
    while os.clock() - t0 < seconds do end
end
NAMES["sleep"] = sleep

M.CLI = CLI
M.DEBUG = DEBUG
M.LABELS = LABELS
M.NAMES = NAMES
M.stack = stack
M.TOKENS = TOKENS
M.utf8decode = utf8decode
M.utf8fromlist = utf8fromlist
M.print_error = print_error

return M
