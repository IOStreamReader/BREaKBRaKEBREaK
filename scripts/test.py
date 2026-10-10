#!/usr/bin/env python3
"""Run behavioral and native persistence tests without changing player data."""
from pathlib import Path
import argparse
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--node', default='node', help='Node.js executable (18+)')
args = parser.parse_args()
node = shutil.which(args.node)
if node is None:
    parser.error('Node.js is required; install it or pass --node /path/to/node')


def run(command):
    subprocess.run([str(part) for part in command], cwd=ROOT, check=True)


run(['python3', ROOT / 'scripts/generate_web.py'])
for name in ['game.test.cjs', 'input.test.cjs', 'startup.test.cjs']:
    run([node, ROOT / 'tests' / name])
with tempfile.TemporaryDirectory(prefix='breakbrake-tests-') as temp:
    directory = Path(temp)
    binary = directory / 'StoreTests'
    run(['xcrun', 'swiftc', '-swift-version', '5', '-module-cache-path', directory / 'module-cache',
         ROOT / 'macos/LocalStore.swift', ROOT / 'tests/store.swift', '-o', binary])
    run([binary, directory / 'data'])
print('All behavioral and storage tests passed.')
