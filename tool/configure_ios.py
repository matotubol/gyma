"""Configure the generated iOS app for device-local Keychain storage."""
from pathlib import Path
import plistlib

runner = Path('ios/Runner')
with (runner / 'Runner.entitlements').open('wb') as output:
    plistlib.dump({'keychain-access-groups': []}, output)
project = Path('ios/Runner.xcodeproj/project.pbxproj')
text = project.read_text()
if 'CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;' not in text:
    needle = 'INFOPLIST_FILE = Runner/Info.plist;'
    if needle not in text:
        raise RuntimeError('Could not locate Runner signing configuration')
    text = text.replace(needle, 'CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;\n\t\t\t\t' + needle)
    project.write_text(text)
