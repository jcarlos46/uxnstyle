-- uxnlexer.lua
local M = {}

-- Funções auxiliares locais
local function is_number(s)
    return tonumber(s) ~= nil
end

local function is_name(s)
    return not tonumber(s) and not s:find("%s")
end

local function is_label(s)
    return type(s) == "string" and s:sub(-1) == ":"
end

local function is_pointer(s)
    return type(s) == "string" and s:sub(1, 1) == "*" and #s > 1
end

local function trim(s)
    return s:match("^%s*(.-)%s*$")
end

local function return_token(_type, val, line_c, col_c)
    return { type=_type, value=val, line=line_c, column=col_c}
end

-- Função split simples para comentários "--"
local function split_by_comment(str)
    local result = {}
    local current = ""
    local i = 1
    
    while i <= #str do
        if i <= #str - 1 and str:sub(i, i+1) == "--" then
            -- Encontrou "--", adiciona a parte atual
            table.insert(result, current)
            break -- Para no primeiro "--" (resto é comentário)
        else
            current = current .. str:sub(i, i)
            i = i + 1
        end
    end
    
    -- Se não encontrou "--", adiciona a string toda
    if i > #str then
        table.insert(result, current)
    end
    
    return result
end

-- Função para processar listas (CORRIGIDA - APENAS NÚMEROS)
function M.parse_list(token)
    assert(token.type == "LIST", "Token precisa ser do tipo LIST")

    local line = token.line
    local column = token.column
    local content = token.value
    local result = {}

    local i = 1
    while i <= #content do
        local c = content:sub(i, i)

        if c:match("%s") then
            i = i + 1 -- Ignora espaços
        else
            -- Processa apenas números
            local token_str = ""
            -- CORREÇÃO: Incluir mais caracteres de parada para evitar loops infinitos
            while i <= #content and not content:sub(i, i):match("[%s\"%[%]%(%)%*]") do
                token_str = token_str .. content:sub(i, i)
                i = i + 1
            end
            
            -- Apenas aceita números - outros tokens são ignorados
            if token_str ~= "" and is_number(token_str) then
                table.insert(result, return_token("NUMBER", tonumber(token_str), line, column))
            end
        end
    end

    return return_token("LIST", result, line, column)
end

-- Função principal de tokenização
function M.tokenize(input)
    local result = {}
    local line_count = 0
    local column_count = 0
    
    -- CORREÇÃO: Validação de entrada
    if not input then
        return result
    end
    
    input = tostring(input)

    for line in input:gmatch("([^\n]*)\n?") do
        -- Processa comentários
        local _line = trim(line)
        local result_line = {}
        line_count = line_count + 1
        column_count = 0

        if line:sub(1, 2) ~= "--" then
            -- Se não é um comentário completo, separa por "--"
            result_line = split_by_comment(_line)
        end

        -- Usa apenas a primeira parte (antes do comentário)
        line = result_line[1] or ""

        local i = 1
        while i <= #line do
            local c = line:sub(i, i)

            if c == "(" then
                -- Suporte a BLOCKs aninhados: conta parênteses
                local block_content = ""
                local depth = 1
                i = i + 1
                while i <= #line and depth > 0 do
                    local ch = line:sub(i, i)
                    if ch == "(" then
                        depth = depth + 1
                        block_content = block_content .. ch
                        i = i + 1
                    elseif ch == ")" then
                        depth = depth - 1
                        if depth == 0 then
                            i = i + 1
                            break
                        else
                            block_content = block_content .. ch
                            i = i + 1
                        end
                    else
                        block_content = block_content .. ch
                        i = i + 1
                    end
                end
                column_count = column_count + 1
                table.insert(result, return_token("BLOCK", block_content, line_count, column_count))
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
                column_count = column_count + 1
                table.insert(result, M.parse_list(return_token("LIST", list, line_count, column_count)))

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
                column_count = column_count + 1
                table.insert(result, return_token("STRING", tostring(str), line_count, column_count))

            elseif c:match("%s") then
                i = i + 1 -- Ignorar espaços

            else
                -- Token padrão (número, nome, label ou pointer)
                local token = ""
                while i <= #line and not line:sub(i, i):match("[%s%(%)%[%]\"]") do
                    token = token .. line:sub(i, i)
                    i = i + 1
                end
                if token ~= "" then
                    if is_number(token) then
                        column_count = column_count + 1
                        table.insert(result, return_token("NUMBER", tonumber(token), line_count, column_count))
                    elseif is_pointer(token) then
                        -- NOVO: Suporte a POINTER
                        column_count = column_count + 1
                        local pointer_name = token:sub(2) -- Remove o '*' do início
                        table.insert(result, return_token("POINTER", pointer_name, line_count, column_count))
                    elseif is_label(token) then
                        column_count = column_count + 1
                        token = tostring(token)
                        local token_str = token:gsub(":$", "") -- Remove o ':' do final
                        table.insert(result, return_token("LABEL", token_str, line_count, column_count))
                    elseif is_name(token) then
                        column_count = column_count + 1
                        table.insert(result, return_token("NAME", tostring(token), line_count, column_count))
                    else
                        column_count = column_count + 1
                        table.insert(result, return_token("UNKNOWN", token, line_count, column_count))
                    end
                end
            end
        end
    end

    return result
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