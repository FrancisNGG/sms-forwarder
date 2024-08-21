local util_air780e = {}

local uartid = 1
local result = uart.setup(uartid, -- 串口id
115200, -- 波特率
8, -- 数据位
1 -- 停止位
)

-- 串口读缓冲区
local sendQueue = {}
-- 串口超时，串口准备好后发布的消息
local uartimeout, recvReady = 100, "UART_RECV_ID"
uart.on(uartid, "receive", function(id, len)
    local s = ""
    repeat
        s = uart.read(id, len)
        if #s > 0 then
            table.insert(sendQueue, s)
            sys.timerStart(sys.publish, uartimeout, recvReady)
        end
    until s == ""
end)

-- 发送AT指令
function util_air780e.write(s, notNeedCRLF)
    uart.write(uartid, s)
    log.info("util_air780e", "sent at", s)
    if notNeedCRLF then
        return
    end
    uart.write(uartid, "\r\n")
end

-- 向串口发送收到的字符串
sys.subscribe(recvReady, function()
    collectgarbage("collect") -- 防止内存不足
    -- 拼接所有收到的数据
    local s = table.concat(sendQueue)
    -- 串口的数据读完后清空缓冲区
    sendQueue = {}
    collectgarbage("collect") -- 防止内存不足

    s = s:gsub("\n", "\r")
    s = s:split("\r")
    collectgarbage("collect") -- 防止内存不足

    while #s > 0 do
        local line = table.remove(s, 1)
        log.info("uart", "line", line, line:toHex())
        if line == "AT" or line == "OK" then
            sys.publish("AT_AT")
            return
        end
        if line == "ATE1" then
            sys.publish("AT_ATE1")
            return
        end
        if line == "AT+UPGRADE=\"AUTO\",0" then
            sys.publish("AT_UPGRADE")
            return
        end
        if line == "AT+CMGF=0" then
            sys.publish("AT_CMGF")
            return
        end
        if line == "AT+CSCS=\"UCS2\"" then
            sys.publish("AT_CSCS")
            return
        end
        if line == "AT+CNMI=2,2,0,0,0" then
            sys.publish("AT_CNMI")
            return
        end
        if line == "> " then
            sys.publish("AT_SEND_SMS")
            return
        end
        local urc = line:match("^%+(%w+)")
        if urc then -- urc上报
            if urc == "CGATT" then -- 基站附着状态
                sys.publish("AT_CGATT", line:match("%+CGATT: *(%d)") == "1")
            elseif urc == "CNUM" then -- 获取到了本机号码
                sys.publish("AT_CNUM", line:match(',"+(%+%d+)"'))
            elseif urc == "CMT" then -- 来短信了
                local len = tonumber(line:match("%+CMT: *, *(%d+)"))
                repeat
                    local l = table.remove(s, 1)
                    if #l > 0 then
                        local phone, data, time, long, total, id, sms_id = lib_pdu.decodePDU(l, len)
                        log.info("sms", "recv", phone, time, long, sms_id, total, id, data)
                        sys.publish("AT_CMT", phone, data, time, long, total, id, sms_id)
                        break
                    end
                until #s == 0
            end
        else -- 其他命令解析
            -- log.info("uart", "check other cmd")
            local cmd = line:match("^AT%+(%w+)")
            if cmd then -- 命令回复
                if cmd == "CPIN" then -- 检查卡
                    -- log.info("uart", "CPIN found")
                    repeat
                        local l = table.remove(s, 1)
                        -- log.info("uart", "CPIN line",l)
                        if #l > 0 then
                            -- 错误码10=无卡 手册3.15章节
                            -- 错误码13=卡故障 手册3.15章节
                            if l:find("CME ERROR: 10") or l:find("CME ERROR: 13") then 
                                sys.publish("AT_CPIN", false)
                                return
                            else
                                sys.publish("AT_CPIN", true)
                                return
                            end
                        end
                    until #s == 0
                end
            end
        end
    end
end)

function util_air780e.loopAT(cmd, wait, loopTime, timeout)
    local start_time = os.time()
    while true do -- 检查AT状态
        util_air780e.write(cmd)
        local r, r1, r2, r3 = sys.waitUntil(wait, loopTime or 200)
        if r then
            log.info("util_air780e", "got recv", cmd)
            return r1, r2, r3
        end
        -- 检查是否超时
        if timeout and os.time() - start_time >= timeout then
            log.error("util_air780e", "loopAT timeout, cmd : ", cmd)
            return nil
        end
    end
end

return util_air780e
