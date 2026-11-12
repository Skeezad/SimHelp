from pathlib import Path
root = Path(__file__).resolve().parents[1] / "iOS"
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
}
changed=0
for p in root.rglob("*.swift"):
    s=p.read_text(encoding="utf-8")
    n=s
    for a,b in m.items(): n=n.replace(a,b)
    if n!=s: p.write_text(n,encoding="utf-8"); changed+=1
print(changed)
