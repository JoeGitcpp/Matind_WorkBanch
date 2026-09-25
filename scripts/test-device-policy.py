#!/usr/bin/env python3
"""Run the production device/authorization owners without a logged-in GUI session.

Symlink the actual source and existing test files into a disposable SwiftPM test
target. This tests policy and lifecycle state, not native UI or OS sandbox behavior.
"""
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
sources = [
    'Core/Config/AppConfig.swift', 'Core/Storage/LocalStorage.swift',
    'Core/Auth/KeychainPasswordStore.swift', 'Core/Network/APIClient.swift',
    'Core/Network/ControlPlaneTransport.swift',
    'Features/LocalServer/Domain/LocalServerContract.swift',
    'Features/LocalServer/Domain/AuthorizationLedger.swift',
    'Features/LocalServer/Data/DeviceIdentityStore.swift',
    'Features/LocalServer/Data/LoopbackServer.swift',
    'Features/LocalServer/Data/LocalDeviceControlClient.swift',
    'Features/LocalServer/Data/LocalServiceInstallation.swift',
    'Features/LocalServer/Presentation/LocalServerState.swift',
]
tests = ['PrivateServerPolicyTests.swift', 'RemoteDeviceAuthorizationTests.swift']
with tempfile.TemporaryDirectory(prefix='matind-device-policy-') as temporary:
    package = Path(temporary)
    (package / 'Sources').mkdir()
    (package / 'Tests').mkdir()
    for source in sources:
        (package / 'Sources' / Path(source).name).symlink_to(root / 'MatindWorkboard' / source)
    for test in tests:
        (package / 'Tests' / test).symlink_to(root / 'MatindWorkboardTests' / test)
    manifest = '''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "DevicePolicyTests", platforms: [.macOS(.v14)],
    dependencies: [.package(path: CORE_PATH)], targets: [
        .target(name: "MatindWorkboard", dependencies: ["MatindCore"], path: "Sources"),
        .testTarget(name: "DevicePolicyTests", dependencies: ["MatindWorkboard", "MatindCore"], path: "Tests")
    ])
'''.replace('CORE_PATH', json.dumps(str(root / 'MatindCore')))
    (package / 'Package.swift').write_text(manifest)
    subprocess.run(['swift', 'test', '--package-path', str(package)], check=True)
