"""Exercise the patched bootstrap with the actual pinned SwiftSignalKit implementation."""
import pathlib
import subprocess
import sys
import tempfile

root = pathlib.Path(sys.argv[1]).resolve()
cloud = (root / 'submodules/CloudData/Sources/CloudData.swift').read_text()
cloud = cloud[:cloud.index('public protocol CloudDataContext')]
for imported in ('CloudKit', 'MtProtoKit', 'SwiftSignalKit', 'EncryptionProvider'):
    cloud = cloud.replace('import ' + imported + '\n', '')
assert 'CKContainer.default()' not in cloud
assert 'return .never()' in cloud
sources = sorted((root / 'submodules/SSignalKit/SwiftSignalKit/Source').glob('*.swift'))
exercise = '''
var events = 0
for _ in 0..<1000 {
    let context = CloudDataPrefixContext(prefix: "")
    let subscription = context.get().start(next: { _ in events += 1 }, completed: { events += 1 })
    subscription.dispose()
}
precondition(events == 0)
print("PASS: 1000 optional CloudData subscriptions, no terminal events or recursive restart")
'''
with tempfile.TemporaryDirectory() as temporary:
    path = pathlib.Path(temporary)
    main = path / 'main.swift'
    main.write_text(cloud + exercise)
    executable = path / 'cloud-bootstrap-check'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-O', *map(str, sources), str(main), '-o', str(executable)], check=True, timeout=120)
    subprocess.run([str(executable)], check=True, timeout=15)
    # The previous shipped fix must fail this same exercise. Reproduce its exact
    # immediate generic error, which catch/restart turns into unbounded recursion.
    old = cloud.replace('return .never()', 'return Signal { subscriber in subscriber.putError(.generic); return EmptyDisposable }')
    main.write_text(old + exercise)
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-O', *map(str, sources), str(main), '-o', str(executable)], check=True, timeout=120)
    try:
        result = subprocess.run([str(executable)], timeout=15, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        assert result.returncode != 0, 'Old recursive implementation unexpectedly passed'
    except subprocess.TimeoutExpired:
        pass
    print('PASS: previous immediate-error implementation reproduces failure')
