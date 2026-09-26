#!/usr/bin/env python3
"""Temporarily run the development app's host test as its actual execution main.

Requires a disposable development .app. Always restore its real executable and
re-sign; never point this script at an installed/released app.
"""
import argparse
from pathlib import Path
import plistlib
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', required=True, type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
app = args.app.resolve(strict=True)
info_path = app / 'Contents/Info.plist'
original = info_path.read_bytes()
info = plistlib.loads(original)
if not info.get('MATIND_TEST_MODULE_PUBLIC_KEY') or not info.get('CFBundleIdentifier', '').endswith('.operations-preview'):
    raise SystemExit('only the disposable operations-preview development application is allowed')
executable = app / 'Contents/MacOS/ExecutionHostSmoke'
entitlements = root / ('MatindWorkboard/MatindWorkboardDirect.entitlements' if info.get('MATIND_DISTRIBUTION') == 'direct' else 'MatindWorkboard/MatindWorkboard.entitlements')
try:
    subprocess.run(['swiftc', '-parse-as-library', str(root / 'MatindCore/Sources/MatindCore/LocalServiceHost.swift'), str(root / 'MatindCore/Sources/MatindCore/BrowserExecutionPolicy.swift'), str(root / 'MatindCore/Sources/MatindCore/LocalProfileCommand.swift'), str(root / 'scripts/execution-host-smoke.swift'), '-o', str(executable)], check=True)
    info['CFBundleExecutable'] = 'ExecutionHostSmoke'
    info_path.write_bytes(plistlib.dumps(info))
    subprocess.run(['codesign', '--force', '--sign', '-', '--entitlements', str(entitlements), str(app)], check=True)
    subprocess.run([str(executable), str(app)], timeout=110, check=True)
finally:
    info_path.write_bytes(original)
    executable.unlink(missing_ok=True)
    subprocess.run(['codesign', '--force', '--sign', '-', '--options', 'runtime', '--entitlements', str(entitlements), str(app)], check=True)
