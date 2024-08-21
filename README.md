# sms-forwarder 现在成本也不低的短信转发器
ESP32C3 + Air780e 短信转发

## 修改内容
1. 使用 ESP32-C3 SuperMini + Air780E AT 模块
2. 增加了 Bark 推送
3. 增加了获取本机号码，并作为 Bark 分组推送
4. 修复了无法处理带换行符短信的问题
5. 修复了标题无法正常显示 +86 的问题
6. 增加了短信修改 Wi-Fi 和 CmdTag 功能

## 使用步骤
1. 模块接线

|Air780E|ESP32-C3|
|:-----:|:------:|
|  VCC  |  5V    |
|  GND  |  GND   |
|  TX   |  1     |
|  RX   |  0     |

2. 修改 util_notify.lua 添加你自己的推送，必须配置
3. 修改 util_wifi.lua 添加你自己的Wi-Fi，也可以不修改，通过短信发送Wi-Fi配置进行连接
4. 打印外壳
5. all done

## 短信指令

目前支持命令（[cmdTag]表示你的tag，可以理解为密码，默认1234）

```
C[cmdTag]REBOOT：重启

C[cmdTag]SEND[空格][手机号][空格][短信内容]：主动发短信

C[cmdTag]WIFI[空格][SSID][空格][PASSWORD]：修改 WIFI 连接

C[cmdTag]CMDTAG[空格][cmdTag]：修改 cmdTag

C[cmdTag]RESET：恢复出厂设置 (清空整个kv数据库)
```

如修改 Wi-Fi 连接，发送以下短信到插入的sim卡号码

`C1234WIFI ssid password`

## 关于本机号码获取
1. 国内 sim 卡一般可以正常获取本机号码
2. 如不能正常获取，可按以下步骤解决
- 使用 iPhone (Android未测试) 进入`设置-电话-本机号码`，进行手动输入保存后就能自动获取
- 编辑 `mian.lua` 中 `myNumber` 变量手动指定
- 号码格式为 `+8613800138000`
3. 不能正常获取本机号码的原因为：部分厂家并没有将本机号码写到 sim 卡

## 关于 GiffGaff 注册慢
1. 修改了逻辑，当识别到获取的号码非国内号码时，会优先手动注册到中国移动
2. 请确保能正常获取本机号码，或已手动设置本机号码

## 关于网络支持
1. 支持移动联通
2. 电信能注册成功，但无法收发短信

### 来自于以下项目稍作修改，感谢付出

>## 低成本短信转发器

>使用方法见[50元内自制短信转发器（Air780E+ESP32C3）](https://www.chenxublog.com/2022/10/28/19-9-sms-forwarding-air780e-esp32c3.html)

>## air780e-forwarder

>[Air700E / Air780E / Air780EP / Air780EPV 短信转发 来电通知](https://github.com/0wQ/air780e-forwarder)