#!/usr/bin/env lua
-- uxnstyle.lua
local lexer = require("uxnlexer")

STASH = {}
TOKENS = {}
LABELS = {}
NAMES = {}
IP = 1
JUMP = 0
INCALL = false
DEBUG = false
CLI = false

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

local function _print()
    local a = stack:pop()
    print(a)
end
NAMES["print"] = _print

local function pop() 
    table.remove(stack.items)
end
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

local function gt()
    local a = stack:pop()
    local b = stack:pop()
    if (b > a) then
        stack:push(1)
    else
        stack:push(0)
    end
end
NAMES[">"] = gt

local function lt()
    local a = stack:pop()
    local b = stack:pop()
    if (b < a) then
        stack:push(1)
    else
        stack:push(0)
    end
end
NAMES["<"] = lt

local function eq()
    local a = stack:pop()
    local b = stack:pop()
    if (b == a) then
        stack:push(1)
    else
        stack:push(0)
    end
end
NAMES["="] = eq

local function sub()
    local b = stack:pop()
    local a = stack:pop()
    stack:push(a - b)
end
NAMES["sub"] = sub

local function sum()
    local b = stack:pop()
    local a = stack:pop()
    stack:push(a * b)
end
NAMES["*"] = sum

local function mod()
    local b = stack:pop()
    local a = stack:pop()
    stack:push(a % b)
end
NAMES["mod"] = mod

local function div()
    local b = stack:pop()
    local a = stack:pop()
    stack:push(math.floor(a / b))
end
NAMES["/"] = div

local function ret()
    IP = table.remove(STASH)
end
NAMES["ret"] = ret

local function halt() IP = #TOKENS + 1 end
NAMES["halt"] = halt

local function sth()
    local a = stack:pop()
    table.insert(STASH, a)
end
NAMES["sth"] = sth

local function sthr()
    local a = table.remove(STASH)
    if a == nil then
        error("STHR: Stack underflow")
    end
    stack:push(a)
end
NAMES["sthr"] = sthr

local function jz()
    local label = stack:pop()
    assert(LABELS[label] ~= nil, "JMP: label "..label.." not found")
    local cond  = stack:pop()
    if cond == 0 then 
        IP = LABELS[label]
    end 
end
NAMES["jz"] = jz

local function jnz()
    local label = stack:pop()
    assert(LABELS[label] ~= nil, "JMP: label "..label.." not found")
    local cond  = stack:pop()
    if cond ~= 0 then 
        IP = LABELS[label]
    end
end
NAMES["jnz"] = jnz

local function jmp()
    local label = stack:pop()
    assert(LABELS[label] ~= nil, "JMP: label "..label.." not found")
    IP = LABELS[label]
end
NAMES["jmp"] = jmp

local function ps() print(stack:tostring()) end
NAMES["ps"] = ps

local function debug() DEBUG=true end
NAMES["debug"] = debug

local function cli() CLI=true end
NAMES["cli"] = cli

-- Stack manipulation
NAMES["dup"] = function()
    local a = stack:peek()
    if a == nil then
        error("Stack empty")
    end
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

local function apply()
    local code = stack:pop()
    local last_IP = #TOKENS
    INCALL = true
    local tokens = lexer.tokenize(code)
    for _, t in ipairs(tokens) do
        table.insert(TOKENS, t)
    end
    table.insert(STASH, IP+1)
    IP = last_IP
end
NAMES["apply"] = apply

local function ffi()
    local alias = stack:pop()
    if type(alias) ~= "string" then
        error("FFI: Expected STRING for alias, but got " .. type(alias))
	end
    local lua_func = stack:pop()
    if type(lua_func) ~= "string" then
        error("FFI: Expected STRING for function name, but got " .. type(alias))
	end
    local args_count = stack:pop()
    if tonumber(args_count) == false then
		error("FFI: Expexted NUMBER for argument count, but got " .. type(args_count))
	end
    local return_type = stack:pop()
    if type(return_type) ~= "string" then
		error("FFI: Expexted STRIN for return, but got " .. type(return_type))
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
    assert(type(resolved_func) == "function", "FFI: " .. lua_func .. " is not a valid function")

    -- Registra a função no ambiente da linguagem
    NAMES[alias] = function()
        local args = {}
        for i = 1, args_count do
            local arg = stack:pop()
            table.insert(args, arg) -- Insere em ordem reversa para corresponder ao comportamento da pilha
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
        error("cons requires a list")
    end
    table.insert(list, 1, element) 
    stack:push(list)
end

NAMES["uncons"] = function() -- remove first element from list
    local list = stack:pop()
    if type(list) ~= "table" then
        error("uncons requires a list")
    end
    if #list == 0 then
        error("uncons on empty list")
    end
    local first = list[1]
    local rest = {}
    for i = 2, #list do
        table.insert(rest, list[i])
    end
    stack:push(rest)
    stack:push(first)
end

NAMES["join"] = function()
    local sep = stack:pop()
    local list = stack:pop()
    if type(sep) ~= "string" or type(list) ~= "table" then
        error("join requires a list and a separator string")
    end
    local str_items = {}
    for _, v in ipairs(list) do
        table.insert(str_items, tostring(v))
    end
    stack:push(table.concat(str_items, sep))
end

local function sleep()
    local seconds = stack:pop()
    if type(seconds) ~= "number" then
        error("sleep espera um número de segundos")
    end
    local t0 = os.clock()
    while os.clock() - t0 < seconds do end
end
NAMES["sleep"] = sleep

local function print_error(msg)
    if CLI then
        print(msg)
    else
        error(msg)
    end
end

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
    elseif token.type == "NUMBER" or token.type == "STRING" or token.type == "QUOTE" then
        stack:push(token.value)
    elseif token.type == "LIST" then
        local list = {}
        for _, v in ipairs(token.value) do
            table.insert(list, v.value)
        end
        stack:push(list)
    elseif token.type == "NAME" then
        if LABELS[token.value] then
            if JUMP == 0 then table.insert(STASH, IP) end
            JUMP = 0
            IP = LABELS[token.value]
        elseif NAMES[token.value] then
            if type(NAMES[token.value]) == "function" then
                NAMES[token.value]()
            else
                NAMES[token.value]()
                stack:push(NAMES[token.value])
            end
        else
            print_error("NAME not found: " .. token.value)
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
    local token = TOKENS[IP]
    if DEBUG then print("TOKEN: "..token.value) end
    eval(token)
    IP = IP + 1
    if IP > #TOKENS and INCALL then
        IP = table.remove(STASH)
    end
end