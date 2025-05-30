-- uxnlexer.lua
local M = {}

local function is_number(s)
    return tonumber(s) ~= nil
end

local function is_name(s)
    return not tonumber(s) and not s:find("%s")
end

local function is_label(s)
    return s:match("^@") ~= nil
end

local function trim(s)
    return s:match("^%s*(.-)%s*$")
end

local function return_token(_type, expr)
    return { type=_type, value=expr }
end

function M.tokenize(input)
    local result = {}
    input = tostring(input)
    for line in input:gmatch("[^\n]+") do
        -- Ignora comentários e espaços em branco
        local _line = trim(line)
        local result_line = {nil}
        if line:sub(1, 2) ~= "--" then
            result_line = {}
            for part in string.gmatch(_line, "([^%-%-]+)") do
                table.insert(result_line, trim(part))
            end
        end
        line = result_line[1] or ""

        local i = 1
        while i <= #line do
            local c = line:sub(i, i)

            if c == "(" then
                table.insert(result, return_token("PAR_OPEN", nil))
                i = i + 1
            elseif c == ")" then
                table.insert(result, return_token("PAR_CLOSE", nil))
                i = i + 1
            elseif c == "(" and false then
                -- Expressão entre parênteses
                local expr = ""
                local depth = 1
                i = i + 1
                while i <= #line and depth > 0 do
                    local ch = line:sub(i, i)
                    if ch == "(" then
                        depth = depth + 1
                    elseif ch == ")" then
                        depth = depth - 1
                        if depth == 0 then
                            i = i + 1
                            break
                        end
                    end
                    expr = expr .. ch
                    i = i + 1
                end
                table.insert(result, return_token("EXPR", expr))

            elseif c == "[" then
                -- Lista entre colchetes
                local list = ""
                local depth = 1
                i = i + 1
                while i <= #line and depth > 0 do
                    local ch = line:sub(i, i)
                    if ch == "[" then
                        depth = depth + 1
                    elseif ch == "]" then
                        depth = depth - 1
                        if depth == 0 then
                            i = i + 1
                            break
                        end
                    end
                    list = list .. ch
                    i = i + 1
                end
                table.insert(result, M.parse_list(return_token("LIST", list)))

            elseif c == "\"" then
                -- String entre aspas
                local str = ""
                i = i + 1
                while i <= #line do
                    local ch = line:sub(i, i)
                    if ch == "\"" then
                        i = i + 1
                        break
                    elseif ch == "\\" and i < #line then
                        local next_ch = line:sub(i + 1, i + 1)
                        if next_ch == "\"" or next_ch == "\\" then
                            str = str .. next_ch
                            i = i + 2
                        else
                            str = str .. ch
                            i = i + 1
                        end
                    else
                        str = str .. ch
                        i = i + 1
                    end
                end
                table.insert(result, return_token("STRING", tostring(str)))

            elseif c:match("%s") then
                i = i + 1 -- Ignorar espaços

            else
                -- Token padrão (número ou nome)
                local token = ""
                while i <= #line and not line:sub(i, i):match("[%s%(%)%[%]\"]") do
                    token = token .. line:sub(i, i)
                    i = i + 1
                end
                if is_number(token) then
                    table.insert(result, return_token("NUMBER", tonumber(token)))
                elseif is_label(token) then
                    table.insert(result, return_token("LABEL", token))
                elseif is_name(token) then
                    table.insert(result, return_token("NAME", tostring(token)))
                else
                    table.insert(result, return_token("UNKNOWN", token))
                end
            end
        end
    end

    return result
end

function M.parse_list(token)
    assert(token.type == "LIST", "Token precisa ser do tipo LIST")

    local content = token.value
    local result = {}

    local i = 1
    while i <= #content do
        local c = content:sub(i, i)

        if c:match("%s") then
            i = i + 1 -- Ignora espaços

        elseif c == "\"" then
            -- String
            local str = ""
            i = i + 1
            while i <= #content do
                local ch = content:sub(i, i)
                if ch == "\"" then
                    i = i + 1
                    break
                elseif ch == "\\" and i < #content then
                    local next_ch = content:sub(i + 1, i + 1)
                    if next_ch == "\"" or next_ch == "\\" then
                        str = str .. next_ch
                        i = i + 2
                    else
                        str = str .. ch
                        i = i + 1
                    end
                else
                    str = str .. ch
                    i = i + 1
                end
            end
            table.insert(result, return_token("STRING", str))

        else
            -- Nome ou número
            local token_str = ""
            while i <= #content and not content:sub(i, i):match("[%s\"]") do
                token_str = token_str .. content:sub(i, i)
                i = i + 1
            end
            if is_number(token_str) then
                table.insert(result, return_token("NUMBER", tonumber(token_str)))
            elseif is_label(token_str) then
                token_str = token_str:sub(2) -- Remove o '@' do início'
                table.insert(result, return_token("LABEL", token_str))
            elseif is_name(token_str) then
                table.insert(result, return_token("NAME", token_str))
            else
                table.insert(result, return_token("UNKNOWN", token_str))
            end
        end
    end

    return { type = "LIST", value = result }
end


function M.dump(o)
   if type(o) == 'table' then
      local s = '\n{\n'
      for k,v in pairs(o) do
         if type(k) ~= 'number' then
		 k = '"'..k..'"'
	 end
	 if v ~= nil and k ~= nil then
             s = s .. '['..k..'] = ' .. M.dump(v) .. ','
         end
      end
      return s .. '\n}\n'
   else
      return tostring(o)
   end
end

return M
