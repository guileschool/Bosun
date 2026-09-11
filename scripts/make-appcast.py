#!/usr/bin/env python3
"""Sign the final release DMG and produce a signed feed for later publication."""
import base64
from datetime import datetime
from email.utils import format_datetime
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import xml.etree.ElementTree as ET
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[1]
NS = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', NS)

def run(*args):
    return subprocess.check_output(args, text=True).strip()

def main():
    if len(sys.argv) != 2:
        raise SystemExit('Usage: make-appcast.py final-notarized.dmg')
    archive = Path(sys.argv[1]).resolve()
    info = plistlib.loads((ROOT / 'Info.plist').read_bytes())
    version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
    if archive.name != f'Bosun-{version}-arm64.dmg':
        raise SystemExit('Expected a final Apple Silicon release DMG matching Info.plist')
    account = os.environ.get('SPARKLE_KEY_ACCOUNT', 'com.jcutplus.bosun.sparkle')
    tools = ROOT / 'build/dependencies/Sparkle-2.9.6/bin'
    key = run(str(tools / 'generate_keys'), '--account', account, '-p')
    if key != info['SUPublicEDKey']:
        raise SystemExit('Keychain signing key does not match the app public key')
    signature = run(str(tools / 'sign_update'), '--account', account, '-p', str(archive))
    if len(base64.b64decode(signature, validate=True)) != 64:
        raise SystemExit('Invalid update signature')
    run(str(tools / 'sign_update'), '--account', account, '--verify', str(archive), signature)
    rss = ET.Element('rss', version='2.0')
    channel = ET.SubElement(rss, 'channel')
    ET.SubElement(channel, 'title').text = 'Bosun Updates'
    ET.SubElement(channel, 'link').text = 'https://github.com/guileschool/Bosun'
    ET.SubElement(channel, 'description').text = 'Bosun for Apple Silicon Mac'
    item = ET.SubElement(channel, 'item')
    ET.SubElement(item, 'title').text = f'Bosun {version}'
    ET.SubElement(item, 'pubDate').text = format_datetime(datetime.now(ZoneInfo('Asia/Seoul')))
    for name, value in [('version', build), ('shortVersionString', version),
                        ('minimumSystemVersion', '14.0.0'), ('hardwareRequirements', 'arm64')]:
        ET.SubElement(item, f'{{{NS}}}{name}').text = value
    ET.SubElement(item, 'description').text = (
        '<html><head><meta name="color-scheme" content="light dark">'
        '<style>body{font:15px -apple-system,BlinkMacSystemFont,sans-serif;'
        'line-height:1.55;padding:12px 18px}h2{font-size:20px;margin:0 0 12px}'
        'li{margin:8px 0}ul{padding-left:22px}</style></head><body>'
        '<h2>Updates, right from Bosun</h2><ul>'
        '<li>Check for new versions from the menu bar.</li>'
        '<li>Get update notifications with optional automatic checks.</li>'
        '<li>Install when you choose. Bosun takes care of the restart.</li>'
        '</ul></body></html>')
    ET.SubElement(item, 'enclosure', {
        'url': f'https://github.com/guileschool/Bosun/releases/download/v{version}/{archive.name}',
        'length': str(archive.stat().st_size), 'type': 'application/octet-stream',
        f'{{{NS}}}edSignature': signature})
    output = archive.parent / 'appcast.xml'
    ET.indent(rss)
    ET.ElementTree(rss).write(output, encoding='utf-8', xml_declaration=True)
    run(str(tools / 'sign_update'), '--account', account, str(output))
    run(str(tools / 'sign_update'), '--account', account, '--verify', str(output))
    print(f'Verified signed update and feed: {output}')
    print('Upload the DMG and checksum first; only then publish this feed as docs/appcast.xml.')

if __name__ == '__main__':
    main()
