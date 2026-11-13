from pathlib import Path
p=Path(__file__).resolve().parents[1]/'apps/ios/AirSIM/AppUpdateView.swift'
s=p.read_text(encoding='utf8')
m={
'支持连接运行兼容 SimHelp 设备端的 U30Air，在 iPhone 上使用通话与短信功能。':'Supports U30Air with a compatible SimHelp device for calls and messages on iPhone.',
'桌面与锁屏小组件展示设备状态；支持的桌面尺寸提供设备与连接模式切换、最近通话和短信内容摘要。':'Home and Lock Screen widgets show device status, device switching, recent calls, and message summaries.',
'小组件支持后台切换，显示设备上报的电量；刷新由系统调度，无有效采样时显示未知。':'Widgets support background switching and show reported battery level; iOS schedules refresh and shows Unknown without a valid sample.',
'最近通话与短信的底部标签、小组件标题显示未接／未读数量，对应记录也有醒目标记。':'Bottom tabs and widget titles show missed and unread counts with clear record markers.',
'U30Air 需运行兼容设备端。运营商早期媒体仅在临时候选中完成单次试听，尚未正式开放。TLS 公网功能为试验性，需要可入站的自建网关、有效证书及独立音频转发；不自动穿透 NAT，也不新增后台推送。小组件刷新由系统调度，模式切换不代表已连接。GitHub 发布不代表 TestFlight 已可更新。':'U30Air requires a compatible device app. Carrier media is experimental, and public TLS access requires a reachable gateway, valid certificates, and separate audio forwarding. Widgets are refreshed by iOS; switching modes does not guarantee a connection. A GitHub release does not mean a TestFlight update is available.',
'自签／侧载或其他安装渠道':'Sideload or another installation method','公开版本':'Public version','应用更新':'App update','知道了':'Got it','U30Air 支持':'U30Air support',
'不用打开 App，\\n常用信息一眼可见':'No need to open the app; common information is visible at a glance.',
'连接 U30Air，\\n电话短信随身用':'Connect U30Air, use calls and messages anywhere',
'连接运行兼容 SimHelp 设备端的 U30Air，在 iPhone 上拨打、接听电话和收发短信。请先更新设备端并完成配对。':'Connect a compatible U30Air device, then make calls and send messages on iPhone. Update the device app and pair it first.',
'桌面与锁屏小组件':'Home and Lock Screen widgets','未读短信 · 未接来电':'Unread messages · Missed calls',
'底部标签与小组件显示未读／未接数字，对应短信和通话记录也有标记。打开记录，就能找到尚未查看的消息与来电。':'Tabs and widgets show unread and missed counts with markers on the related records. Open a record to find unseen messages and calls.',
'连接模式':'Connection mode','示意数据 · 刷新由系统调度':'Sample data · refreshed by iOS','示意数据 · 数字角标与记录标记':'Sample data · badge counts and record markers','未接来电':'Missed calls',
}
for a,b in m.items(): s=s.replace(a,b)
p.write_text(s,encoding='utf8')
