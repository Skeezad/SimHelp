from pathlib import Path
import json, re
root = Path(__file__).resolve().parents[1] / "iOS"
mcache = json.loads((Path(__file__).with_name("ios_translation_cache.json")).read_text(encoding="utf-8"))
lit = re.compile(r'"(?:\\.|[^"\\])*"')
m = {
  "\u8fde\u63a5\u5b89\u5353\u624b\u673a":"Connect Android phone",
  "\u901a\u8baf\u5f55":"Contacts", "\u6700\u8fd1":"Recents", "\u6765\u7535":"Incoming call",
  "\u901a\u8bdd":"Calls", "\u77ed\u4fe1":"SMS", "\u5728\u7ebf":"Online", "\u79bb\u7ebf":"Offline",
  "\u4e91\u7aef":"Cloud", "\u5f53\u524d":"Current", "\u5207\u6362":"Switch", "\u5b8c\u6210":"Done",
  "\u5237\u65b0":"Refresh", "\u9519\u8bef":"Error", "\u5b89\u5353":"Android", "\u5df2\u914d\u5bf9\u8bbe\u5907":"Paired devices",
  "\u5f00\u59cb\u914d\u5bf9":"Start pairing", "\u6dfb\u52a0\u84dd\u7259\u8bbe\u5907":"Add Bluetooth device",
  "\u9009\u62e9\u5b89\u5353\u624b\u673a":"Select Android phone", "\u6682\u65e0\u914d\u5bf9\u8bb0\u5f55":"No pairing records",
  "\u53f7\u7801\u672a\u63d0\u4f9b":"Number unavailable", "\u672a\u8bfb\u77ed\u4fe1":"Unread SMS",
  "\u672a\u63a5\u6765\u7535":"Missed calls", "\u4fe1\u53f7":"Signal", "\u672a\u77e5":"Unknown",
  "\u6df1\u8272":"Dark", "\u6d45\u8272":"Light", "\u5176\u4ed6\u8bbe\u5907":"Other devices",
  "\u5f53\u524d\u8bbe\u5907":"Current device", "\u9009\u62e9\u901a\u8bdd\u5361":"Select call card",
  "\u56de\u62e8":"Call back", "\u65b0\u4fe1\u606f":"New message", "\u6682\u65e0\u77ed\u4fe1":"No messages",
  "\u590d\u5236\u9a8c\u8bc1\u7801":"Copy verification code", "\u53d1\u9001\u7ebf\u8def":"Sending line",
  "\u5b89\u5353\u9ed8\u8ba4\u77ed\u4fe1\u5361":"Android default SMS card", "\u56de\u5230\u914d\u7f6e":"Back to setup",
  "\u53d1\u9001\u77ed\u4fe1":"Send message", "\u77ed\u4fe1\u64cd\u4f5c":"Message actions", "\u8bbe\u7f6e":"Settings",
  "\u7cfb\u7edf\u6743\u9650":"System permissions", "\u8be6\u7ec6\u65e5\u5fd7\u4e0e\u6280\u672f\u4fe1\u606f":"Detailed logs and technical information",
  "\u4f7f\u7528\u6307\u5357":"User guide", "\u684c\u9762\u5c0f\u7ec4\u4ef6":"Home screen widget", "\u914d\u5bf9\u8bbe\u5907\u540e\u53ef\u4ee5\u8c03\u6574\u663e\u793a\u987a\u5e8f\u3002":"You can adjust the display order after pairing devices.",
  "\u4e34\u65f6\u5141\u8bb8":"Temporarily allowed", "\u672a\u5141\u8bb8":"Not allowed", "\u5c1a\u672a\u8bf7\u6c42":"Not requested",
  "\u672c\u673a\u914d\u5bf9\u8bb0\u5f55":"Local pairing record", "\u4e2a\u5730\u5740":"addresses", "\u63a7\u5236":"Control", "\u97f3\u9891":"Audio",
  "\u79c1\u7f51\u76f4\u8fde":"Private network direct connection", "\u5b9e\u9a8c\u6027":"Experimental", "\u57df\u540d":"Domain",
  "\u5b9a\u4f4d":"Location", "\u6743\u9650":"Permission", "\u901a\u77e5\u6743\u9650":"Notification permission",
  "\u672c\u5730\u94fe\u8def":"Local link", "\u914d\u5bf9":"Pairing", "\u7f51\u7edc":"Network", "\u72b6\u6001":"Status",
  "\u8fd8\u6ca1\u6709":"Not yet", "\u6ca1\u6709":"No", "\u5df2\u8bfb":"Read", "\u672a\u8bfb":"Unread",
  "\u914d\u7f6e\u5df2\u53d6\u6d88\uff0c\u8bf7\u91cd\u65b0\u9a8c\u8bc1\u3002":"Configuration canceled. Please verify again.",
  "\u8bf7\u8f93\u5165\u5b8c\u6574\u7684 http:// \u6216 https:// \u5730\u5740\uff0c\u4e0d\u5305\u542b\u8d26\u53f7\u3001\u5bc6\u7801\u3001\u67e5\u8be2\u53c2\u6570\u6216\u7247\u6bb5\u3002":"Enter a complete http:// or https:// address without credentials, query parameters, or fragments.",
  "\u5c0f\u7ec4\u4ef6\u652f\u6301\u540e\u53f0Switch\uff0c\u663e\u793a\u8bbe\u5907\u4e0a\u62a5\u7684\u7535\u91cf\uff1bRefresh\u7531\u7cfb\u7edf\u8c03\u5ea6\uff0c\u65e0\u6709\u6548\u91c7\u6837\u65f6\u663e\u793aUnknown\u3002":"The widget shows reported battery status; refresh is scheduled by iOS and shows Unknown when no sample is available.",
  "\u81ea\u7b7e\uff0f\u4fa7\u8f7d\u6216\u5176\u4ed6\u5b89\u88c5\u6e20\u9053":"Sideload or another installation method",
  "\u516c\u5f00\u7248\u672c":"Public version", "\u5e94\u7528\u66f4\u65b0":"App update", "\u77e5\u9053\u4e86":"Got it",
  "\u684c\u9762\u4e0e\u9501\u5c4f\u5c0f\u7ec4\u4ef6":"Home screen and Lock Screen widgets", "\u7248\u672c":"Version",
  "\u586b\u5199Domain\uff0c\u4e0d\u542b https:// \u6216\u8def\u5f84\u3002\u4e09\u4e2a\u7aef\u53e3\u90fd\u662f NAS \u5bf9\u5916\u63d0\u4f9b\u7684 TLS \u7aef\u53e3\uff1bPairing\u7aef\u53e3\u8f6c\u53d1\u5230Android\u672c\u6b21Pairing\u7a97\u53e3\uff0cControl\u4e0eAudio\u5404\u81ea\u8f6c\u53d1\u3002\u8bc1\u4e66\u5fc5\u987b\u53ef\u4fe1\u4e14\u5339\u914dDomain\uff0c\u4e0d\u652f\u6301\u660e\u6587\u516c\u7f51\u8fde\u63a5\u6216\u8df3\u8fc7\u8bc1\u4e66\u6821\u9a8c\u3002\u65e0\u9700\u5f00\u542f SimHelp Cloud\u6a21\u5f0f\u3002":"Enter the domain without https:// or a path. The three ports are TLS ports exposed by the NAS; forward pairing, control, and audio separately. The certificate must be trusted and match the domain. Plain public connections and skipped certificate checks are unsupported. SimHelp Cloud mode is not required.",
  "\u4e0d\u5e26 https://\u3001\u8def\u5f84\u6216\u7aef\u53e3\u3002\u53ea\u6709\u8bc1\u4e66\u548c\u8be5Android\u8bbe\u5907\u7684\u8eab\u4efd\u9a8c\u8bc1\u901a\u8fc7\uff0cDomain\u8def\u7531\u624d\u4f1a\u4fdd\u5b58\u3002":"Do not include https://, a path, or a port. The domain route is saved only after the certificate and Android device identity are verified.",
  "\u8bf7\u586b\u5199\u6709\u6548Domain\uff08\u4e0d\u542b https:// \u6216\u8def\u5f84\uff09\u53ca 1\u201365535 \u7684Control\u3001Audio\u7aef\u53e3":"Enter a valid domain without https:// or a path, plus Control and Audio ports from 1 to 65535.",
  "\u901a\u77e5Token=":"Notification token=",
  "\u6fc0\u6d3bDone\uff1bstate=":"Activation completed; state=",
  "\u8fd0\u8425\u5546\u65e9\u671f\u5a92\u4f53\u4ec5\u5728\u4e34\u65f6\u5019\u9009\u4e2dDone\u5355\u6b21\u8bd5\u542c\uff0c\u5c1a\u672a\u6b63\u5f0f\u5f00\u653e\u3002":"Early carrier media is available only for a one-time test and is not officially enabled.",
  "\u5c0f\u7ec4\u4ef6Refresh\u7531\u7cfb\u7edf\u8c03\u5ea6\uff0c\u6a21\u5f0fSwitch\u4e0d\u4ee3\u8868\u5df2\u8fde\u63a5\u3002":"Widget refresh is scheduled by iOS; switching modes does not mean connected.",
  "\u4e0d\u7528\u6253\u5f00 App\uff0c\\n\u5e38\u7528\u4fe1\u606f\u4e00\u773c\u53ef\u89c1":"No need to open the app; common information is visible at a glance.",
  "\u8fde\u63a5\u6a21\u5f0f":"Connection mode", "\u81ea\u52a8":"Automatic", "\u793a\u610f\u6570\u636e":"Sample data",
  "\u672a\u63a5Incoming call":"Missed calls", "U30Air \u652f\u6301":"U30Air support",
  "\u652f\u6301\u8fde\u63a5\u8fd0\u884c\u517c\u5bb9 SimHelp \u8bbe\u5907\u7aef\u7684 U30Air\uff0c\u5728 iPhone \u4e0a\u4f7f\u7528\u901a\u8bdd\u4e0e\u77ed\u4fe1\u529f\u80fd\u3002":"Supports U30Air with a compatible SimHelp device for calls and messages on iPhone.",
  "\u684c\u9762\u4e0e\u9501\u5c4f\u5c0f\u7ec4\u4ef6\u5c55\u793a\u8bbe\u5907\u72b6\u6001\uff1b\u652f\u6301\u7684\u684c\u9762\u5c3a\u5bf8\u63d0\u4f9b\u8bbe\u5907\u4e0e\u8fde\u63a5\u6a21\u5f0f\u5207\u6362\u3001\u6700\u8fd1\u901a\u8bdd\u548c\u77ed\u4fe1\u5185\u5bb9\u6458\u8981\u3002":"Home and Lock Screen widgets show device status, device switching, recent calls, and message summaries.",
  "\u6700\u8fd1\u901a\u8bdd\u4e0e\u77ed\u4fe1\u7684\u5e95\u90e8\u6807\u7b7e\u3001\u5c0f\u7ec4\u4ef6\u6807\u9898\u663e\u793a\u672a\u63a5\uff0f\u672a\u8bfb\u6570\u91cf\uff0c\u5bf9\u5e94\u8bb0\u5f55\u4e5f\u6709\u9192\u76ee\u6807\u8bb0\u3002":"Bottom tabs and widget titles show missed and unread counts with clear record markers.",
  "U30Air \u9700\u8fd0\u884c\u517c\u5bb9\u8bbe\u5907\u7aef\u3002\u8fd0\u8425\u5546\u65e9\u671f\u5a92\u4f53\u4ec5\u5728\u4e34\u65f6\u5019\u9009\u4e2d\u5b8c\u6210\u5355\u6b21\u8bd5\u542c\uff0c\u5c1a\u672a\u6b63\u5f0f\u5f00\u653e\u3002TLS \u516c\u7f51\u529f\u80fd\u4e3a\u8bd5\u9a8c\u6027\uff0c\u9700\u8981\u53ef\u5165\u7ad9\u7684\u81ea\u5efa\u7f51\u5173\u3001\u6709\u6548\u8bc1\u4e66\u53ca\u72ec\u7acb\u97f3\u9891\u8f6c\u53d1\uff1b\u4e0d\u81ea\u52a8\u7a7f\u900f NAT\uff0c\u4e5f\u4e0d\u65b0\u589e\u540e\u53f0\u63a8\u9001\u3002\u5c0f\u7ec4\u4ef6\u5237\u65b0\u7531\u7cfb\u7edf\u8c03\u5ea6\uff0c\u6a21\u5f0f\u5207\u6362\u4e0d\u4ee3\u8868\u5df2\u8fde\u63a5\u3002GitHub \u53d1\u5e03\u4e0d\u4ee3\u8868 TestFlight \u5df2\u53ef\u66f4\u65b0\u3002":"U30Air requires a compatible device app. Carrier media is experimental, and public TLS access requires a reachable gateway, valid certificates, and separate audio forwarding. Widgets are refreshed by iOS; switching modes does not guarantee a connection. A GitHub release does not mean a TestFlight update is available.",
  "\u81ea\u7b7e\uff0f\u4fa7\u8f7d\u6216\u5176\u4ed6\u5b89\u88c5\u6e20\u9053":"Sideload or another installation method",
  "\u516c\u5f00\u7248\u672c \\(candidate.version)\uff08\\(candidate.build)\uff09":"Public version \\(candidate.version) (\\(candidate.build))",
  "\u8fde\u63a5 U30Air\uff0c\\n\u7535\u8bdd\u77ed\u4fe1\u968f\u8eab\u7528":"Connect U30Air, use calls and messages anywhere",
  "\u8fde\u63a5\u8fd0\u884c\u517c\u5bb9 SimHelp \u8bbe\u5907\u7aef\u7684 U30Air\uff0c\u5728 iPhone \u4e0a\u62e8\u6253\u3001\u63a5\u542c\u7535\u8bdd\u548c\u6536\u53d1\u77ed\u4fe1\u3002\u8bf7\u5148\u66f4\u65b0\u8bbe\u5907\u7aef\u5e76\u5b8c\u6210\u914d\u5bf9\u3002":"Connect a compatible U30Air device, then make calls and send messages on iPhone. Update the device app and pair it first.",
  "\u5e95\u90e8\u6807\u7b7e\u4e0e\u5c0f\u7ec4\u4ef6\u663e\u793a\u672a\u8bfb\uff0f\u672a\u63a5\u6570\u5b57\uff0c\u5bf9\u5e94\u77ed\u4fe1\u548c\u901a\u8bdd\u8bb0\u5f55\u4e5f\u6709\u6807\u8bb0\u3002\u6253\u5f00\u8bb0\u5f55\uff0c\u5c31\u80fd\u627e\u5230\u5c1a\u672a\u67e5\u770b\u7684\u6d88\u606f\u4e0e\u6765\u7535\u3002":"Tabs and widgets show unread and missed counts with markers on the related records. Open a record to find unseen messages and calls.",
  "\u8fde\u63a5\u6a21\u5f0f":"Connection mode", "\u793a\u610f\u6570\u636e \xb7 \u5237\u65b0\u7531\u7cfb\u7edf\u8c03\u5ea6":"Sample data · refreshed by iOS", "\u672a\u63a5\u6765\u7535":"Missed calls",
}
m.update({
  "\u8bd5\u9a8c\u6027":"Experimental", "\u516c\u7f51":"public network", "\u57df\u540d\u914d\u5bf9\u4e0e\u76f4\u8fde":"domain pairing and direct connection", "\u81ea\u5efa":"self-hosted", "\u5165\u53e3":"entry", "\u9996\u6b21":"first",
  "\u4e0e":" and ", "\u76f4\u8fde":" direct connection", "\u901a\u8fc7":" via ", "\u6216\u4e3a":" or for ", "\u6dfb\u52a0":" add ", "\u8fdb\u884c":" perform ", "\u8bbe\u5907":"device", "\u7cfb\u7edf":"system", "\u4e0d":"not ", "\u8fde\u63a5":"connect", "\u4e3a":" for ", "\u548c":" and ", "\u4e0e":" and ", "\u8bf7":"Please ", "\u53ef":"can ", "\u4ee3\u8868":"mean", "\u5df2":"already ", "\u8fd8":"still ", "\u65b0":"new ", "\u4f7f\u7528":"use ",
  "\u6309":" by ", "\u8eab\u4efd":" state ", "\u6216":" or ", "\u4e5f":" also ", "\u8005":" or ", "\u67e5\u770b":"check ", "\u8c03\u5ea6":"schedule", "\u4ee5":" as ", "\u6709\u6548":"valid ", "\u4e0a\u62a5":"report ", "\u51c6":"basis", "\u9700":"requires ", "\u5165\u7ad9":"inbound", "\u72ec\u7acb":"separate", "\u8f6c\u53d1":"forwarding", "\u914d\u7f6e\u9875\u5185\u9644":"setup page includes", "\u6559\u7a0b":"guide", "\u8bb0\u5f55":"record", "\u6d88\u606f":"message", "\u6765\u7535":"call",
  "\u8bbe\u5907\u72b6\u6001":"device status", "\u7531":"by", "\u6570\u91cf":"count", "\u4e3a\u51c6":"as the basis", "\u53f7":"number", "\u6761":" items", "\u3001":", ", "\uff1b":"; ", "\u3002":". ", "\uff0c":", ", "\uff1a":": ", "\u300c":"'", "\u300d":"'",
  "\u547c\u51fa\u7ed3\u675f\u65f6":"When an outgoing call ends", "\u505c\u6b62\u7b49\u5f85\u97f3\u4e0e\u8ba1\u65f6":"stop waiting audio and timer", "\u6ce2\u52a8":"network changes", "\u91cd\u590d\u62e8\u53f7":"redial", "\u8bf7\u6253\u5f00":"Open", "\u67e5\u770b\u6b64":"check this", "\u662f\u5426\u5df2\u6709\u53ef\u7528\u6784\u5efa":"whether a build is available", "\u53d1\u5e03\u4e0d\u4ee3\u8868":"release does not mean", "\u5df2\u5904\u7406":"processed", "\u6d4b\u8bd5\u8005\u53ef\u66f4\u65b0":"testers can update", "\u4e0d\u4f1a":"Does not", "\u4e0b\u8f7d\u5b89\u88c5":"download or install", "\u66f4\u6539":"change", "\u8bbe\u5907\u72b6\u6001":"device status", "\u7535\u91cf":"battery", "\u5185\u5bb9":"content", "\u652f\u6301\u7684\u684c\u9762\u5c3a\u5bf8":"supported widget sizes", "\u53ef\u76f4\u63a5":"directly", "\u7528\u81ea\u5df1\u7684":"Use your own", "\u5728\u5916\u4e5f\u80fd":"connect remotely", "\u7f51\u5173":"gateway", "\u9700\u8981":"requires", "\u6709\u6548\u8bc1\u4e66":"valid certificate", "\u72ec\u7acb\u97f3\u9891\u8f6c\u53d1":"separate audio forwarding", "\u5df2\u6709\u8bbe\u5907":"existing device", "\u6dfb\u52a0":"add",
})
changed=0
for p in root.rglob("*.swift"):
    s=p.read_text(encoding="utf-8")
    n=s
    for a,b in m.items(): n=n.replace(a,b)
    n=re.sub(r'case \.zh: return "[^"\n]*"', 'case .zh: return "English"', n)
    n=re.sub(r'case \.dark: return L10n\.t\("[^"\n]*"\)', 'case .dark: return "Dark"', n)
    n=lit.sub(lambda x: mcache.get(x.group(0), x.group(0)) if "\\(" not in x.group(0) and any("\u3400" <= ch <= "\u9fff" for ch in x.group(0)) and mcache.get(x.group(0), x.group(0)) != x.group(0) else x.group(0), n)
    if n!=s: p.write_text(n,encoding="utf-8"); changed+=1
print(changed)
