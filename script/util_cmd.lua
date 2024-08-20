local util_cmd = {}

util_wifi = require "util_wifi"

-- 短信接收指令的标记（密码）
--[[
目前支持命令（[cmdTag]表示你的tag）
C[cmdTag]REBOOT：重启
C[cmdTag]SEND[空格][手机号][空格][短信内容]：主动发短信
C[cmdTag]WIFI[空格][SSID][空格][PASSWORD]：修改 WIFI 连接
C[cmdTag]CMDTAG[空格][cmdTag]：修改 cmdTag
C[cmdTag]RESET：恢复出厂设置 (清空整个kv数据库)
]]

-- 默认 cmdTag 为 1234, 可发送短信修改
local cmdTag = "1234"

-- 检测是否属于指令data
function cmdHandle(data)
    log.info("cmd", "mathing cmd code", cmdTag, data)
    -- 匹配上了指令
    if data:find("C" .. cmdTag) == 1 then
        log.info("cmd", "matched cmd")
        if data:find("C" .. cmdTag .. "REBOOT") == 1 then -- 重启指令
            sys.timerStart(rtos.reboot, 10000) -- 10s后才执行
            data = "reboot command done"
        elseif data:find("C" .. cmdTag .. "SEND") == 1 then -- 发送短信指令
            local _, _, phone, text = data:find("C" .. cmdTag .. "SEND (%d+) +(.+)")
            if phone and text then
                log.info("cmd", "cmd send sms", phone, text)
                local d, len = pdu.encodePDU(phone, text)
                if d and len then
                    air780.write("AT+CMGS=" .. len .. "\r\n")
                    local r = sys.waitUntil("AT_SEND_SMS", 5000)
                    if r then
                        air780.write(d, true)
                        sys.wait(500)
                        air780.write(string.char(0x1A), true)
                        data = "send sms at command done"
                    else
                        data = "send sms at command error!"
                    end
                end
            end
        elseif data:find("C" .. cmdTag .. "WIFI") == 1 then -- 修改 WiFi 指令
            local _, _, wifi_ssid, wifi_pw = data:find("C" .. cmdTag .. "WIFI (%S+) (%S+)")
            if wifi_ssid and wifi_pw then
                log.info("cmd", "cmd connect to wifi...  ssid : " .. wifi_ssid .. " password : " .. wifi_pw)
                if wifiConnect(wifi_ssid, wifi_pw) == "success" then
                    data = "change wifi done"
                    -- 保存 ssid password 到不掉电数据库，方便下次连接
                    log.info("fskv", "save wifi ssid to fskv", fskv.sett("config", "ssid", wifi_ssid),
                        fskv.get("config", "ssid"))
                    log.info("fskv", "save wifi password to fskv", fskv.sett("config", "password", wifi_pw),
                        fskv.get("config", "password"))
                    sys.wait(1000)
                else
                    data = "change wifi fail"
                end
            else
                log.info("cmd", "wrong wifi")
                data = "get wifi info fail"
            end
        elseif data:find("C" .. cmdTag .. "CMDTAG") == 1 then -- 修改 cmdTag 指令
            local _, _, tag = data:find("C" .. cmdTag .. "CMDTAG (%S+)")
            if tag then
                log.info("cmd", "received new cmd tag : " .. tag)
                local saveStatus = fskv.sett("config", "cmdTag", tag)
                -- 保存到不掉电数据库
                log.info("fskv", "save cmd tag to fskv", saveStatus, fskv.get("config", "cmdTag"))
                if saveStatus then
                    data = "change cmd tag done"
                else
                    data = "change cmd tag fail"
                end
            else
                log.info("cmd", "wrong cmd tag")
                data = "get cmd tag info fail"
            end
        elseif data:find("C" .. cmdTag .. "RESET") == 1 then -- 恢复出厂 (清空整个kv数据库)       
            local saveStatus = fskv.clear()
            log.info("fskv", "erase all content and settings", saveStatus)
            -- 保存到不掉电数据库
            if saveStatus then
                data = "reset done"
            else
                data = "reset fail"
            end
        end
    else
        log.info("cmd", "no math cmd code")
    end
    return data
end

sys.taskInit(function()
    local fskvCmdTag = fskv.get("config", "cmdTag")
    if fskvCmdTag then
        cmdTag = fskvCmdTag
        log.info("fskv", "get cmdTag for fskv", cmdTag)
    else
        log.info("fskv", "default cmdTag", cmdTag)
    end
end)

return util_cmd
