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
    msg = M.LAST_TOKEN_NAME..": line "..M.LAST_TOKEN_LINE.." column "..M.LAST_TOKEN_COLUMN..": "..msg
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
LABELS = {}
stack = Stack:new()
NAMES = {}
CLI = false
DEBUG = false

local function _print()
    local a = M.stack:pop()
    print(a)
end
NAMES["print"] = _print

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
    if (b == a) then
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

local function ps() print(stack:tostring()) end
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

-- String manipulation
local function trim()
    local s = stack:pop()
    s = s:match("^%s*(.-)%s*$")
    stack:push(s)
end
NAMES["trim"] = trim

local function ffi()
    local alias = M.stack:pop()
    if type(alias) ~= "string" then
		print_error_type("STRING", type(alias))
	end
    local lua_func = M.stack:pop()
    if type(lua_func) ~= "string" then
		print_error_type("STRING", type(lua_func))
	end
    local args_count = M.stack:pop()
    if tonumber(args_count) == false then
		print_error_type("NUMBER", type(args_count))
	end
    local return_type = M.stack:pop()
    if type(return_type) ~= "string" then
		print_error_type("STRING", type(return_type))
	end
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
    if type(resolved_func) == "function" then
        print_error(lua_func.. "is not a valid funciton")
    end

    -- Registra a função no ambiente da linguagem
    NAMES[alias] = function()
        local args = {}
        for i = 1, args_count do
            local arg = stack:pop()
             -- Insere em ordem reversa para corresponder ao comportamento da pilha
            table.insert(args, arg)
        end

        local unpack = table.unpack or unpack
        local result = resolved_func(unpack(args))
        if return_type ~= "VOID" then
            stack:push(result)
        end
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
        print_error_type("LIST", type(seconds))
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

return M
