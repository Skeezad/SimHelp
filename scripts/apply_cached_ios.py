import json
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1] / "iOS"
cache = json.loads((Path(__file__).with_name("ios_translation_cache.json")).read_text(encoding="utf-8"))
cjk = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]")
lit = re.compile(r'"(?:\\.|[^"\\\r\n])*"')
changed = 0
replacements = {
    "连接安卓手机": "Connect Android phone", "开始配对": "Start pairing", "添加蓝牙设备": "Add Bluetooth device",
    "稍后在设置中配对": "Pair later in Settings", "连接模式": "Connection mode", "选择安卓手机": "Select Android phone",
    "已配对设备": "Paired devices", "暂无配对记录": "No pairing records", "号码未提供": "Number unavailable",
    "通话": "Calls", "短信": "SMS", "通讯录": "Contacts", "最近": "Recents", "在线": "Online", "离线": "Offline",
    "云端": "Cloud", "当前": "Current", "切换": "Switch", "完成": "Done", "刷新": "Refresh", "错误": "Error",
    "返回配置": "Back to setup", "加密配对": "Encrypted pairing", "配对成功": "Pairing successful", "配对失败": "Pairing failed",
    "正在连接与认证…": "Connecting and authenticating…", "正在切换连接策略": "Switching connection policy",
    "通话中不可切换": "Cannot switch during a call", "纯本地模式": "Local-only mode", "已开启": "Enabled", "已关闭": "Disabled",
    "请先结束当前通话": "End the current call first", "请稍候": "Please wait", "安卓": "Android", "电话": "Phone",
    "未读短信": "Unread SMS", "未接来电": "Missed calls", "信号": "Signal", "未知": "Unknown", "无输入": "No input", "无输出": "No output",
}
replacements.update({
    "\u8fde\u63a5\u5b89\u5353\u624b\u673a": "Connect Android phone",
    "\u5f00\u59cb\u914d\u5bf9": "Start pairing",
    "\u6dfb\u52a0\u84dd\u7259\u8bbe\u5907": "Add Bluetooth device",
    "\u7a0d\u540e\u5728\u8bbe\u7f6e\u4e2d\u914d\u5bf9": "Pair later in Settings",
    "\u8fde\u63a5\u6a21\u5f0f": "Connection mode",
    "\u9009\u62e9\u5b89\u5353\u624b\u673a": "Select Android phone",
    "\u5df2\u914d\u5bf9\u8bbe\u5907": "Paired devices",
    "\u6682\u65e0\u914d\u5bf9\u8bb0\u5f55": "No pairing records",
    "\u53f7\u7801\u672a\u63d0\u4f9b": "Number unavailable",
    "\u901a\u8bdd": "Calls", "\u77ed\u4fe1": "SMS", "\u901a\u8baf\u5f55": "Contacts",
    "\u6700\u8fd1": "Recents", "\u5728\u7ebf": "Online", "\u79bb\u7ebf": "Offline", "\u4e91\u7aef": "Cloud",
    "\u5f53\u524d": "Current", "\u5207\u6362": "Switch", "\u5b8c\u6210": "Done", "\u5237\u65b0": "Refresh", "\u9519\u8bef": "Error",
    "\u56de\u5230\u914d\u7f6e": "Back to setup", "\u52a0\u5bc6\u914d\u5bf9": "Encrypted pairing",
    "\u914d\u5bf9\u6210\u529f": "Pairing successful", "\u914d\u5bf9\u5931\u8d25": "Pairing failed",
    "\u5b89\u5353": "Android", "\u7535\u8bdd": "Phone", "\u672a\u8bfb\u77ed\u4fe1": "Unread SMS",
    "\u672a\u63a5\u6765\u7535": "Missed calls", "\u4fe1\u53f7": "Signal", "\u672a\u77e5": "Unknown",
    "\u65e0\u8f93\u5165": "No input", "\u65e0\u8f93\u51fa": "No output",
})
for path in root.rglob("*.swift"):
    text = path.read_text(encoding="utf-8")
    for source, target in replacements.items():
        text = text.replace(source, target)
    lines = []
    for line in text.splitlines(keepends=True):
        if '"""' in line:
            lines.append(line); continue
        lines.append(lit.sub(lambda m: cache.get(m.group(0), m.group(0)) if cjk.search(m.group(0)) and "\\(" not in m.group(0) else m.group(0), line))
    new = "".join(lines)
    if new != text:
        path.write_text(new, encoding="utf-8"); changed += 1
print(changed)
