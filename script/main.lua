-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "sms_forwarder"
VERSION = "1.0.3"

log.info("main", PROJECT, VERSION)

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")
require("sysplus")

if wdt then
    -- 添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000) -- 初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000) -- 3s喂一次狗
end

-- 检查一下固件版本，防止用户乱刷
do
    local fw = rtos.firmware():lower() -- 全转成小写
    local ver, bsp = fw:match("luatos%-soc_v(%d-)_(.+)")
    ver = ver and tonumber(ver) or nil
    local r
    if ver and bsp then
        if ver >= 1004 and bsp == "esp32c3" then
            r = true
        end
    end
    if not r then
        sys.timerLoopStart(function()
            wdt.feed()
            log.info("警告",
                "固件类型或版本不满足要求，请使用esp32c3 v1004及以上版本固件。当前：" ..
                    rtos.firmware())
        end, 500)
    end
end

-- 本机号码 (一些国外卡获取不到号码，可以在此手动指定)
myNumber = "+8613800138000"

-- 运营商给的dns经常抽风，手动指定
socket.setDNS(nil, 1, "114.114.114.114")
socket.setDNS(nil, 2, "223.5.5.5")

-- 定时GC一下, 清理内存
sys.timerLoopStart(function()
    collectgarbage("collect")
end, 1000)

-- 初始化 fskv
log.info("main", "fskv.init", fskv.init())

-- 加载模块
lib_pdu = require("lib_pdu")
util_led = require("util_led")
util_air780e = require("util_air780e")
util_notify = require("util_notify")

local function clear_table(table)
    for i = 0, #table do
        table[i] = nil
    end
end

local function fix_time(time)
    return string.format("20%s-%s-%s %s:%s:%s %s", time:sub(1, 2), time:sub(4, 5), time:sub(7, 8), time:sub(10, 11),
        time:sub(13, 14), time:sub(16, 17), time:sub(18, 20))
end

local long_sms_buffer = {}

local function concat_and_send_long_sms(phone, time, sms)
    -- 拼接长短信
    local full_content = ""

    table.sort(sms, function(a, b)
        return a.id < b.id
    end)

    for _, v in ipairs(sms) do
        log.debug("long_sms", "message id: " .. v.id .. ", content: " .. v.data .. ", time: " .. v.time)
        full_content = full_content .. v.data
    end

    util_notify.add(phone, full_content)

    -- 清空缓冲区
    clear_table(sms)
end

local function clean_sms_buffer(phone, time, sms_id)
    if not long_sms_buffer[phone] then
        return
    end

    if not long_sms_buffer[phone][sms_id] then
        return
    end

    log.warn("sms", "long sms receive timeout from ", phone, time, sms_id)
    if #long_sms_buffer[phone][sms_id] > 0 then
        concat_and_send_long_sms(phone, time, long_sms_buffer[phone][sms_id])
        long_sms_buffer[phone][sms_id] = nil
    end
end

sys.taskInit(function()
    util_led.status = 1
    log.info("util_air780e", "sync at")
    -- 同步AT命令看通不通
    util_air780e.loopAT("AT", "AT_AT")

    -- 重启
    util_air780e.write("AT+RESET")
    -- 同步AT命令看通不通（确保重启完）
    util_air780e.loopAT("AT", "AT_AT")
    util_air780e.loopAT("ATE1", "AT_ATE1")

    -- 查询 Air780E 模块版本
    util_air780e.loopAT("AT+CGMR", "AT_AT")

    -- 关闭自动升级
    util_air780e.loopAT("AT+UPGRADE=\"AUTO\",0", "AT_UPGRADE")

    util_led.status = 3
    log.info("util_air780e", "check sim card")
    -- 检查下有没有卡
    local r = util_air780e.loopAT("AT+CPIN?", "AT_CPIN")
    if not r then
        log.error("util_air780e", "sim card is not inserted or failured! system will reboot after 2s!")
        util_led.status = 2
        sys.wait(2000)
        rtos.reboot()
        return
    end

    -- 配置一下参数
    log.info("util_air780e", "configrate")
    -- PDU模式
    util_air780e.loopAT("AT+CMGF=0", "AT_CMGF")
    -- 编码
    util_air780e.loopAT("AT+CSCS=\"UCS2\"", "AT_CSCS")
    -- 短信内容直接上报不缓存
    util_air780e.loopAT("AT+CNMI=2,2,0,0,0", "AT_CNMI")

    -- 获取本机号码
    log.info("util_air780e", "waiting for get the local phone number...")
    local num = util_air780e.loopAT("AT+CNUM", "AT_CNUM", 200, 5)
    if num then
        myNumber = num
        log.info("main", "gotta have number : ", myNumber)
    else
        log.info("main", "the phone number is not exist in sim card, use default number : ", myNumber)
    end

    -- 当获取的号码不是国内号码时，优先手动注册到中国移动 (主要针对 GiffGaff 在国内注册慢的问题)
    if string.sub(myNumber, 1, 3) ~= "+86" then
        log.info("main", "this number is not China mobile number, regedit to ChinaMobile first!")
        -- 参数 4 代表手自一体，当手动选择不成功时，会自动搜网
        util_air780e.write("AT+COPS=4,2,\"46000\"")
        sys.wait(10000)
    end

    -- 检查附着
    log.info("util_air780e", "wait for connection")
    while true do
        local r = util_air780e.loopAT("AT+CGATT?", "AT_CGATT", 1000)
        log.info("util_air780e", "connection status", r)
        if r then
            sys.publish("SIM_READY", r)
            break
        end
    end

    -- 查看所注册的运营商
    util_air780e.write("AT+COPS?")

    -- 初始化完成，发送通知
    util_notify.add("System",
        lib_pdu.utf8_ucs2("system is ready now! \nnumber:" .. myNumber .. "\nwaiting for new sms!"))

    util_led.status = 4
    log.info("util_air780e", "connected! wait sms")

    while true do
        collectgarbage("collect") -- 防止内存不足
        local _, phone, data, time, long, total, id, sms_id = sys.waitUntil("AT_CMT")
        time = fix_time(time)

        if long then -- 是长短信！
            log.info("util_air780e", "receive a long sms", phone, sms_id, id .. " / " .. total, time)
            -- 缓存，长短信存放处
            if not long_sms_buffer[phone] then
                long_sms_buffer[phone] = {}
            end
            if not long_sms_buffer[phone][sms_id] then
                long_sms_buffer[phone][sms_id] = {}
                sys.timerStart(clean_sms_buffer, 30 * 1000, phone, time, sms_id)
            end

            table.insert(long_sms_buffer[phone][sms_id], {
                id = id,
                data = data,
                time = time
            })

            if long_sms_buffer[phone][sms_id] and #long_sms_buffer[phone][sms_id] == total then
                concat_and_send_long_sms(phone, time, long_sms_buffer[phone][sms_id])
                long_sms_buffer[phone][sms_id] = nil
            end
        else
            log.info("util_air780e", "receive a sms", phone, time)
            util_notify.add(phone, data) -- 这次的短信
        end
    end
end)

-- 定时检查附着
sys.taskInit(function()
    sys.waitUntil("SIM_READY", 60 * 1000) -- 60s内等待附着，超时进入循环内执行重启
    while true do
        local r = util_air780e.loopAT("AT+CGATT?", "AT_CGATT", 1000)
        if r == false then
            log.info("util_air780e", "connected fail, system reboot after 2s")
            sys.wait(2000)
            rtos.reboot()
        else
            log.info("util_air780e", "connection status", r, "waiting for new sms!")
        end
        sys.wait(30 * 1000) -- 每 30s 检查附着
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
