#!/usr/bin/env python3
"""Build a universal macOS app plus an Intel-only copy using Apple's tools."""
from pathlib import Path
import subprocess
import shutil
import struct
import hashlib

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
APP = ROOT / 'dist/BREaK!BRaKE!BREaK!.app'


def run(args):
    subprocess.run([str(arg) for arg in args], check=True, cwd=ROOT)


BUILD.mkdir(exist_ok=True)
(ROOT / 'dist').mkdir(exist_ok=True)
run(['python3', ROOT / 'scripts/generate_web.py'])
contents = APP / 'Contents'
for directory in [contents / 'MacOS', contents / 'Resources']:
    directory.mkdir(parents=True, exist_ok=True)
shutil.copyfile(ROOT / 'macos/Info.plist', contents / 'Info.plist')
resources = contents / 'Resources'
if (resources / 'Web').exists():
    shutil.rmtree(resources / 'Web')
shutil.copytree(ROOT / 'web', resources / 'Web')
for name in ['LICENSE', 'LICENSING.md', 'THIRD_PARTY_NOTICES.md']:
    shutil.copyfile(ROOT / name, resources / name)
executables = []
for arch in ['arm64', 'x86_64']:
    binary = BUILD / f'BreakBrake-{arch}'
    run(['xcrun', 'swiftc', '-O', '-whole-module-optimization', '-swift-version', '5',
         '-target', f'{arch}-apple-macosx13.0', '-module-cache-path', BUILD / 'module-cache',
         '-framework', 'AppKit', '-framework', 'WebKit',
         *sorted((ROOT / 'macos').glob('*.swift')), '-o', binary])
    executables.append(binary)
run(['xcrun', 'lipo', '-create', *executables, '-output', contents / 'MacOS/BreakBrake'])
iconset = BUILD / 'AppIcon.iconset'
if iconset.exists():
    shutil.rmtree(iconset)
run(['xcrun', 'swift', '-module-cache-path', BUILD / 'module-cache', ROOT / 'scripts/make_icon.swift', iconset])
# ICNS supports PNG payloads directly; no system conversion service is needed.
icon_types = {'icp4': 'icon_16x16.png', 'icp5': 'icon_32x32.png',
              'icp6': 'icon_32x32@2x.png', 'ic07': 'icon_128x128.png',
              'ic08': 'icon_256x256.png', 'ic09': 'icon_512x512.png',
              'ic10': 'icon_512x512@2x.png', 'ic11': 'icon_16x16@2x.png',
              'ic12': 'icon_32x32@2x.png', 'ic13': 'icon_128x128@2x.png',
              'ic14': 'icon_256x256@2x.png'}
chunks = []
for kind, filename in icon_types.items():
    data = (iconset / filename).read_bytes()
    chunks.append(kind.encode('ascii') + struct.pack('>I', len(data) + 8) + data)
payload = b''.join(chunks)
(resources / 'AppIcon.icns').write_bytes(b'icns' + struct.pack('>I', len(payload) + 8) + payload)
run(['codesign', '--force', '--sign', '-', '--entitlements', ROOT / 'macos/Entitlements.plist', APP])
run(['codesign', '--verify', '--deep', '--strict', APP])
intel_app = ROOT / 'dist/BREaK!BRaKE!BREaK!-Intel.app'
if intel_app.exists():
    shutil.rmtree(intel_app)
shutil.copytree(APP, intel_app)
shutil.copyfile(BUILD / 'BreakBrake-x86_64', intel_app / 'Contents/MacOS/BreakBrake')
run(['codesign', '--force', '--sign', '-', '--entitlements', ROOT / 'macos/Entitlements.plist', intel_app])
run(['codesign', '--verify', '--deep', '--strict', intel_app])
print(f'Built universal (arm64 + x86_64) app: {APP}')
print(f'Built Intel x86_64 app: {intel_app}')
for app, filename in [(APP, 'BREaK!BRaKE!BREaK!-Universal.zip'),
                      (intel_app, 'BREaK!BRaKE!BREaK!-Intel.zip')]:
    run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', app, ROOT / 'dist' / filename])
# Refresh the previous arm64 download too, preserving its original bundle name.
arm_app = BUILD / 'package-arm64' / APP.name
if arm_app.parent.exists():
    shutil.rmtree(arm_app.parent)
shutil.copytree(APP, arm_app)
shutil.copyfile(BUILD / 'BreakBrake-arm64', arm_app / 'Contents/MacOS/BreakBrake')
run(['codesign', '--force', '--sign', '-', '--entitlements', ROOT / 'macos/Entitlements.plist', arm_app])
run(['codesign', '--verify', '--deep', '--strict', arm_app])
run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', arm_app,
     ROOT / 'dist/BREaK!BRaKE!BREaK!-arm64.zip'])
packages = [ROOT / 'dist' / f'BREaK!BRaKE!BREaK!-{arch}.zip'
            for arch in ['Universal', 'Intel', 'arm64']]
(ROOT / 'dist/SHA256SUMS.txt').write_text(''.join(
    f'{hashlib.sha256(package.read_bytes()).hexdigest()}  {package.name}\n'
    for package in packages))
print('Packaged Universal, Intel, and arm64 downloads with SHA-256 checksums.')
