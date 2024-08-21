local util_notify = {}
util_cmd = require "util_cmd"

-- 推荐使用LuatOS社区提供的推送服务，无使用限制
-- 官网：https://push.luatos.org/ 点击GitHub图标登陆即可
-- 支持邮件/企业微信/钉钉/飞书/电报/IOS Bark

-- 使用哪个推送服务，默认 bark
-- 可选：luatos/serverChan/pushover/bark
local useServer = "bark"

-- LuatOS社区提供的推送服务 https://push.luatos.org/ ，用不到可留空
-- 这里填.send前的字符串就好了
-- 如：https://push.luatos.org/ABCDEF1234567890ABCD.send/{title}/{data} 填入 ABCDEF1234567890ABCD
local luatosPush = "ABCDEF1234567890ABCD"
-- 默认的接口网址，推荐优先使用（由于服务器在国外某些地方可能连不上，如果连不上就换另一个）
local luatosPushApi = "https://push.luatos.org/"
-- 备用的接口网址，从国内中转（有严格的QPS限制，请求频率过高会被屏蔽）
-- local luatosPushApi = "http://push.papapoi.com/"

-- server酱的配置，用不到可留空，免费用户每天仅可发送五条推送消息
-- server酱的SendKey，如果你用的是这个就需要填一个
-- https://sct.ftqq.com/sendkey 申请一个
local serverKey = ""

-- pushover配置，用不到可留空
local pushoverApiToken = ""
local pushoverUserKey = ""

-- bark配置，用不到可留空
local barkApi = "https://api.day.app/"
local barkKey = ""

-- 缓存消息
local buff = {}

-- 手动回收垃圾
function garbagecollect()
    local nowMem = "before : " .. collectgarbage("count") .. " KB"
    local cleanState = collectgarbage("collect")
    local afterMem = "after : " .. collectgarbage("count") .. " KB"
    if cleanState == 0 then
        log.info("user", "collect garbage done  ", nowMem, afterMem)
    else
        log.info("user", "collect garbage fail  ", nowMem, afterMem)
    end
end

-- 来新消息了
function util_notify.add(phone, data)
    data = lib_pdu.ucs2_utf8(data) -- 转码
    log.info("notify", "got sms", phone, data)

    -- 检测是否属于指令data
    data = cmdHandle(data)
    table.insert(buff, {phone, data})
    sys.publish("SMS_ADD") -- 推个事件
end

sys.taskInit(function()
    print("gc1", collectgarbage("count"))
    log.info("notify", "notify is ready !!")
    while true do
        print("gc2", collectgarbage("count"))
        while #buff > 0 do -- 把消息读完
            collectgarbage("collect") -- 防止内存不足
            local sms = table.remove(buff, 1)
            local code, h, body
            local data = sms[2]
            if useServer == "serverChan" then -- server酱
                log.info("notify", "send to serverChan", data)
                code, h, body = http.request("POST", "https://sctapi.ftqq.com/" .. serverKey .. ".send", {
                    ["Content-Type"] = "application/x-www-form-urlencoded"
                }, "title=" .. string.urlEncode("sms" .. sms[1]) .. "&desp=" .. string.urlEncode(data)).wait()
                log.info("notify", "pushed sms notify", code, h, body, sms[1])
            elseif useServer == "pushover" then -- Pushover
                log.info("notify", "send to Pushover", data)
                local body = {
                    token = pushoverApiToken,
                    user = pushoverUserKey,
                    title = "SMS: " .. sms[1],
                    message = data
                }
                local json_body = string.gsub(json.encode(body), "\\b", "\\n") -- luatos bug
                -- 多试几次好了
                for i = 1, 10 do
                    code, h, body = http.request("POST", "https://api.pushover.net/1/messages.json", {
                        ["Content-Type"] = "application/json; charset=utf-8"
                    }, json_body).wait()
                    log.info("notify", "pushed sms notify", code, h, body, sms[1])
                    if code == 200 then
                        break
                    end
                    sys.wait(5000)
                end
            elseif useServer == "bark" then -- bark
                local text = data:gsub("%%", "%%25"):gsub("+", "%%2B"):gsub("/", "%%2F"):gsub("?", "%%3F"):gsub("#",
                    "%%23"):gsub("&", "%%26"):gsub(" ", "%%20"):gsub("\n", "%%0A")
                local numberFrom = sms[1]:gsub("%%", "%%25"):gsub("+", "%%2B"):gsub("/", "%%2F"):gsub("?", "%%3F")
                    :gsub("#", "%%23"):gsub("&", "%%26"):gsub(" ", "%%20"):gsub("\n", "%%0A")
                local myNumber = myNumber:gsub("%%", "%%25"):gsub("+", "%%2B"):gsub("/", "%%2F"):gsub("?", "%%3F"):gsub(
                    "#", "%%23"):gsub("&", "%%26"):gsub(" ", "%%20"):gsub("\n", "%%0A")

                local url = barkApi .. barkKey .. "/" .. numberFrom .. "/" .. text .. "?group=" .. myNumber
                log.info("notify", "send to bark push server", url)

                garbagecollect() -- 手动回收内存

                -- 多试几次好了
                for i = 1, 10 do
                    code, h, body = http.request("GET", url).wait()
                    log.info("notify", "pushed sms notify", code, h, body, sms[1])
                    if code == 200 then
                        break
                    end
                    sys.wait(5000)
                end
            else -- luatos推送服务
                data = data:gsub("%%", "%%25"):gsub("+", "%%2B"):gsub("/", "%%2F"):gsub("?", "%%3F"):gsub("#", "%%23")
                    :gsub("&", "%%26"):gsub(" ", "%%20"):gsub("\n", "%%0A")
                local url = luatosPushApi .. luatosPush .. ".send/sms" .. sms[1] .. "/" .. data
                log.info("notify", "send to luatos push server", data, url)
                -- 多试几次好了
                for i = 1, 10 do
                    code, h, body = http.request("GET", url).wait()
                    log.info("notify", "pushed sms notify", code, h, body, sms[1])
                    if code == 200 then
                        break
                    end
                    sys.wait(5000)
                end
            end
        end
        log.info("notify", "wait for a new sms~")
        garbagecollect() -- 手动回收内存
        sys.waitUntil("SMS_ADD")
    end
end)

return util_notify
