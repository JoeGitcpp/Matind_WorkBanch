#!/usr/bin/env python3
"""Bundle an explicit, signed Matind browser module and the real execution host.

Run before distribution/notarization. No private platform signing key enters the
app. Release builds require an already-signed module, its pinned public root,
bundled Chromium, and a Developer ID identity. Development artifacts are labelled.
"""
import argparse
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile


def run(args, **kwargs):
    subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def build_host(frontend, public_root, development):
    environment = dict(os.environ)
    if environment.get('CARGO_BUILD_TARGET'):
        raise SystemExit('unset CARGO_BUILD_TARGET before packaging the execution host')
    environment.pop('CARGO_TARGET_DIR', None)
    environment.pop('MATIND_TEST_MODULE_ROOT', None)
    target = frontend / 'apps/desktop/local-server/target'
    command = ['cargo', 'build', '--locked', '--manifest-path', str(frontend / 'apps/desktop/local-server/Cargo.toml'),
               '--target-dir', str(target), '--message-format=json-render-diagnostics']
    if development:
        environment.pop('MATIND_PLATFORM_MODULE_PUBLIC_KEY', None)
        command += ['--features', 'development-test-root']
    else:
        environment['MATIND_PLATFORM_MODULE_PUBLIC_KEY'] = public_root
        command += ['--release']
    result = subprocess.run(command, env=environment, stdout=subprocess.PIPE, text=True, check=False)
    artifacts = set()
    for line in result.stdout.splitlines():
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        if message.get('reason') == 'compiler-message':
            rendered = message.get('message', {}).get('rendered')
            if rendered:
                print(rendered, end='', file=sys.stderr)
        if (message.get('reason') == 'compiler-artifact' and message.get('target', {}).get('name') == 'matind-local-service'
                and 'bin' in message.get('target', {}).get('kind', []) and message.get('executable')):
            artifacts.add(Path(message['executable']).resolve())
    if result.returncode != 0 or len(artifacts) != 1:
        raise SystemExit('cargo did not produce one confirmed execution-host artifact')
    artifact = artifacts.pop()
    if not artifact.is_relative_to(target.resolve()) or not artifact.is_file():
        raise SystemExit('cargo execution-host artifact is outside the explicit target directory')
    return artifact


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--frontend', type=Path, required=True)
    parser.add_argument('--module', type=Path, required=True)
    parser.add_argument('--node', type=Path, required=True)
    parser.add_argument('--public-root', required=True)
    parser.add_argument('--development', action='store_true')
    parser.add_argument('--apple-signing-identity')
    args = parser.parse_args()
    app, frontend, module, node = (p.resolve(strict=True) for p in [args.app, args.frontend, args.module, args.node])
    if app.suffix != '.app' or not (app / 'Contents/Info.plist').is_file():
        parser.error('--app must be an existing built application')
    info_path = app / 'Contents/Info.plist'
    info = plistlib.loads(info_path.read_bytes())
    if info.get('MATIND_DISTRIBUTION') != 'direct':
        parser.error('browser execution requires the explicit direct-distribution Operations configuration')
    if args.development and info.get('MATIND_BUILD_CONFIGURATION') != 'LocalOperations':
        parser.error('development module root is only allowed in LocalOperations')
    if not args.development and info.get('MATIND_BUILD_CONFIGURATION') != 'ReleaseOperations':
        parser.error('release browser execution requires ReleaseOperations')
    if not args.development and (not args.apple_signing_identity or args.apple_signing_identity == '-'):
        parser.error('release packaging requires an explicit Developer ID signing identity')
    if not args.development and not (module / 'browsers').is_dir():
        parser.error('release module must include the pinned Playwright browsers directory')
    # Use a verifier independent of the native runtime. No npm install or network in this stage.
    verification = r'''
      const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
      const [root, publicRoot] = process.argv.slice(1);
      const canonical = x => Array.isArray(x) ? '['+x.map(canonical).join(',')+']' :
        x && typeof x === 'object' ? '{'+Object.keys(x).sort().map(k=>JSON.stringify(k)+':'+canonical(x[k])).join(',')+'}' : JSON.stringify(x);
      const e = JSON.parse(fs.readFileSync(path.join(root, 'manifest.json')));
      const key = crypto.createPublicKey({key:{kty:'OKP',crv:'Ed25519',x:publicRoot},format:'jwk'});
      if (!crypto.verify(null, Buffer.from(canonical(e.payload)), key, Buffer.from(e.signature,'base64url'))) throw Error('module signature invalid');
      if(e.payload.contractVersion!=='matind-module-v1'||e.payload.moduleId!=='matind.browser'||e.payload.version!=='1.0.0'||e.payload.entrypoint!=='driver.mjs') throw Error('module contract invalid');
      const actual = new Map(), canonicalRoot = fs.realpathSync(root);
      const walk = dir => {for(const name of fs.readdirSync(dir)){
        const p=path.join(dir,name), s=fs.lstatSync(p), local=path.relative(root,p).split(path.sep).join('/');
        if(s.isSymbolicLink()) {
          const target=fs.readlinkSync(p), resolved=fs.realpathSync(p), parent=fs.realpathSync(path.dirname(p));
          if(local==='manifest.json'||path.isAbsolute(target)||!resolved.startsWith(canonicalRoot+path.sep)||parent===resolved||parent.startsWith(resolved+path.sep)) throw Error('module symlink boundary');
          actual.set(local,crypto.createHash('sha256').update('symlink\0').update(target).digest('hex'));
        } else if(s.isDirectory())walk(p);
        else if(s.isFile())actual.set(local,crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex'));
        else throw Error('module file invalid');
      }};
      walk(root);actual.delete('manifest.json');
      if(actual.size!==e.payload.files.length)throw Error('module inventory invalid');
      for(const f of e.payload.files){if(actual.get(f.path)!==f.sha256)throw Error('module content invalid');actual.delete(f.path);}
      if(actual.size)throw Error('module duplicate inventory');
    '''
    run([node, '-e', verification, module, args.public_root])
    # Cargo JSON identifies the actual binary even when config selects a target
    # triple. Never copy a stale executable from a guessed cache location.
    host_artifact = build_host(frontend, args.public_root, args.development)
    helpers = app / 'Contents/Helpers'
    helpers.mkdir(exist_ok=True)
    shutil.copy2(host_artifact, helpers / 'matind-local-service')
    shutil.copy2(node, helpers / 'node')
    destination = app / 'Contents/Resources/browser'
    if destination.exists():
        raise SystemExit('browser resources already exist; package a fresh app to avoid stale files')
    shutil.copytree(module, destination, symlinks=True)
    info.pop('MATIND_TEST_MODULE_PUBLIC_KEY', None)
    if args.development:
        info['MATIND_TEST_MODULE_PUBLIC_KEY'] = args.public_root
    info_path.write_bytes(plistlib.dumps(info))
    identity = args.apple_signing_identity or '-'
    with tempfile.TemporaryDirectory(prefix='matind-signing-') as temporary:
        entitlement = Path(temporary) / 'helper.plist'
        for helper in [helpers / 'matind-local-service', helpers / 'node']:
            values = {}
            if helper.name == 'node':
                values['com.apple.security.cs.allow-jit'] = True
            entitlement.write_bytes(plistlib.dumps(values))
            run(['codesign', '--force', '--sign', identity, '--options', 'runtime', '--entitlements', entitlement, helper])
        for framework in sorted((app / 'Contents/Frameworks').glob('*.framework')):
            run(['codesign', '--force', '--sign', identity, '--options', 'runtime', framework])
        # Do not --deep re-sign the module after its platform content digest is frozen.
        main_entitlement = Path(__file__).resolve().parents[1] / 'MatindWorkboard/MatindWorkboardDirect.entitlements'
        run(['codesign', '--force', '--sign', identity, '--options', 'runtime', '--entitlements', main_entitlement, app])
    run(['codesign', '--verify', '--deep', '--strict', app])
    print(json.dumps({'application': str(app), 'developmentOnly': args.development, 'notarized': False}))


if __name__ == '__main__':
    main()
