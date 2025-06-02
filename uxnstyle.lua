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

local function halt() IP = #dict.TOKENS + 1 end
dict.NAMES["halt"] = halt

local function debug() dict.DEBUG = true end
dict.NAMES["debug"] = debug

local function jz()
    local label = stack:pop()
    assert(LABELS[label] ~= nil, "JMP: label "..label.." not found")
    local cond  = stack:pop()
    if cond == 0 then 
        IP = LABELS[label]
    end 
end
dict.NAMES["jz"] = jz

local function jnz()
    local label = stack:pop()
    assert(LABELS[label] ~= nil, "JMP: label "..label.." not found")
    local cond  = stack:pop()
    if cond ~= 0 then 
        IP = LABELS[label]
    end
end
dict.NAMES["jnz"] = jnz

local function jmp()
    local label = stack:pop()
    assert(LABELS[label] ~= nil, "JMP: label "..label.." not found")
    IP = LABELS[label]
end
dict.NAMES["jmp"] = jmp

local function apply()
    local code = dict.stack:pop()
    local last_IP = #dict.TOKENS
    INCALL = true
    local tokens = lexer.tokenize(code)
    for _, t in ipairs(tokens) do
        table.insert(dict.TOKENS, t)
    end
    table.insert(STASH, IP+1)
    IP = last_IP
end
dict.NAMES["apply"] = apply

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
        dict.stack:push(token.value)
    elseif token.type == "LIST" then
        local list = {}
        for _, v in ipairs(token.value) do
            table.insert(list, v.value)
        end
        dict.stack:push(list)
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
        local token_str = token.value:sub(2) -- Remove o '@' do início'
        dict.LABELS[token_str] = i
    end
end


if dict.LABELS["main"] then IP = dict.LABELS["main"] end
while IP <= #dict.TOKENS do
    local token = dict.TOKENS[IP]
    if dict.DEBUG then
        print(IP .. ":"..token.value.." line: "..token.line.." column: ".. token.column)
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
