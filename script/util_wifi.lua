local util_wifi = {}

-- 可在此定义默认的 Wi-Fi ，也可以留空发送短信进行连接
local defaultSsid = ""
local defaultPassword = ""

function wifiConnect(ssid, password)
    wlan.disconnect()
    sys.wait(1000)
    wlan.init() -- 初始化wifi

    if password == "" then -- 考虑到没有密码的 Wi-Fi
        wlan.connect(ssid)
        log.info("wlan", "wait for IP_READY")
        sys.waitUntil("IP_READY", 30 * 1000)
        if wlan.ready() then
            log.info("wlan", "wifi was connected, ip address : " .. wlan.getIP())
            log.info("wlan", "wifi info ", json.encode(wlan.getInfo()))
            return "success"
        end
        log.info("wlan", "wifi was connected fail, waiting to reconfigure for sms! ")
        wlan.disconnect()
        return "fail"
    end

    if ssid and password then
        wlan.connect(ssid, password)
        log.info("wlan", "wait for IP_READY")
        sys.waitUntil("IP_READY", 30 * 1000)
        if wlan.ready() then
            log.info("wlan", "wifi was connected, ip address : " .. wlan.getIP())
            log.info("wlan", "wifi info ", json.encode(wlan.getInfo()))
            return "success"
        end
        log.info("wlan", "wifi was connected fail, waiting to reconfigure for sms! ")
        wlan.disconnect()
        return "fail"
    else
        log.info("wlan", "wifi ssid is null! ")
        wlan.disconnect()
        return nil
    end

end

sys.taskInit(function()
    local fskv_ssid = fskv.get("config", "ssid")
    local fskv_password = fskv.get("config", "password")
    log.info("fskv", "get wifi_ssid for fskv", fskv_ssid)
    log.info("fskv", "get wifi_password for fskv", fskv_password)

    while not wlan.ready() do
        if fskv_ssid then
            wifiConnect(fskv_ssid, fskv_password)
        else
            if defaultSsid then
                log.info("wlan", "using default wifi config to connect!")
                wifiConnect(defaultSsid, defaultPassword)
            else
                log.info("wlan", "wifi configure was not in fskv or not default value, waiting to reconfigure for sms!")
                sys.wait(5000)
            end
        end
    end
end)

return util_wifi
