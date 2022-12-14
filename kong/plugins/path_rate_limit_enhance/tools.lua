---
--- Generated by EmmyLua(https://github.com/EmmyLua)
--- Created by WangChen.
--- DateTime: 2022/7/15 10:44
---

local ipairs = ipairs
local type   = type
local sub    = string.sub
local len    = string.len

-- 只用到table和字符串了。
local is_empty =  function(value)
    if type(value) == "string" then
        return value and value == "" and value == nil
    elseif type(value) == "table" then
        return #value == 0
    end
end

return {

    start_with_and_sub = function(path,  prefix)
        local match = sub(path,1, len(prefix)) == prefix
        if not match then
            return match, ""
        end
        return match, sub(path, len(prefix) + 1)
    end,

    is_empty =  is_empty,

    is_not_empty = function (value)
        return not is_empty(value)
    end,

    is_all_number = function(...)
        for _, val in ipairs{...} do
            if type(val) ~= "number" then
                return false
            end
        end
        return true
    end,

    in_array = function(val, array)
        if not array then
            return false
        end
        for _, value in ipairs(array) do
            if value == val then
                return true
            end
        end
        return false
    end

}