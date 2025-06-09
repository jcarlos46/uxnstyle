#!/usr/bin/env lua
-- uxnstyle.lua
local lexer = require("uxnlexer")
local dict = require("uxndict")

STASH = {}
TOKENS = {}
IP = 1
INCALL = false

local function ret()
    IP = table.remove(STASH)
end
dict.NAMES["ret"] = ret

local function stash_in()
    local a = stack:pop()
    table.insert(STASH, a)
end
dict.NAMES['stash-in'] = stash_in

local function stash_out()
    local a = table.remove(STASH)
    stack:push(a)
end
dict.NAMES['stash-out'] = stash_out

local function halt() IP = #dict.TOKENS + 1 end
dict.NAMES["halt"] = halt

local function debug() dict.DEBUG = true end
dict.NAMES["debug"] = debug

local function jz()
    local label = stack:pop()
    local cond  = stack:pop()
    if cond == 0 then IP = label end 
end
dict.NAMES["jz"] = jz

local function jnz()
    local label = stack:pop()
    local cond  = stack:pop()
    if cond ~= 0 then IP = label end
end
dict.NAMES["jnz"] = jnz

local function jmp()
    local label = stack:pop()
    IP = label
end
dict.NAMES["jmp"] = jmp

local function call()
    local new_ip = stack:pop()
    table.insert(STASH, IP)
    IP = new_ip
end
dict.NAMES["call"] = call

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
    elseif token.type == "NUMBER" then
        dict.stack:push(token.value)
    elseif token.type == "STRING" then
        local i = 1
        local list = {}
        while i <= #token.value do
            local c = token.value:sub(i, i)
            c = dict.utf8decode(c)
            table.insert(list, c)
            i = i + 1
        end
        dict.stack:push(list)
    elseif token.type == "LIST" then
        local list = {}
        for _, v in ipairs(token.value) do
            table.insert(list, v.value)
        end
        dict.stack:push(list)
    elseif token.type == "POINTER" then
        local token_ip = dict.LABELS[token.value]
        if token_ip == nil then
            dict.print_error("LABEL not found: " .. token.value)
        end
        dict.stack:push(token_ip)
    elseif token.type == "NAME" then
        if dict.LABELS[token.value] then
            table.insert(STASH, IP)
            IP = dict.LABELS[token.value]
        elseif dict.NAMES[token.value] then
            if type(NAMES[token.value]) == "function" then
                dict.NAMES[token.value]()
            else
                dict.NAMES[token.value]()
                dict.stack:push(dict.NAMES[token.value])
            end
        else
            dict.print_error("NAME not found: " .. token.value)
        end
    elseif token.type == "BLOCK" then
        local block_ip = #dict.TOKENS
        local tokens = lexer.tokenize(token.value)
        for _, t in ipairs(tokens) do
            local index = #dict.TOKENS + 1 
            dict.TOKENS[index] = t
        end
        token.type = "NUMBER"
        token.value = block_ip
        dict.TOKENS[#dict.TOKENS + 1] = {type="NAME", value="ret"}
        stack:push(block_ip)
    end
end

local code
if arg[1] then
    local filename = arg[1]
    code = import_file(filename)
else
    print("Usage: lua uxnstyle.lua <filename>")
    os.exit(1)
end

dict.TOKENS = lexer.tokenize(code)
-- Process labels
for i, token in ipairs(dict.TOKENS) do
    if token.type == "LABEL" then
        dict.LABELS[token.value] = i
    end
end


if dict.LABELS["main"] then IP = dict.LABELS["main"] end
while IP <= #dict.TOKENS do
    local token = dict.TOKENS[IP]
    if dict.DEBUG then
        io.write("WS: ") dict.NAMES['ps']()
        local value = token.value
        if (token.type == "LIST") then value = "list" end
        print(IP .. ":"..value.." line: "..token.line.." column: ".. token.column)
    end
    dict.LAST_TOKEN_NAME = token.value
    dict.LAST_TOKEN_LINE = token.line
    dict.LAST_TOKEN_COLUMN = token.column
    eval(token)
    IP = IP + 1
    if IP > #dict.TOKENS and INCALL then
        IP = table.remove(STASH)
    end
end
