#!/bin/bash
set -euo pipefail
PIR_APP="${1:?Usage: sign-update-components.sh /path/to/Pir.app identity}"
PIR_IDENTITY="${2:--}"
python3 - "$PIR_APP" "$PIR_IDENTITY" <<'PY'
import pathlib, subprocess, sys
framework = pathlib.Path(sys.argv[1]) / 'Contents/Frameworks/Sparkle.framework'
if not framework.exists():
    raise SystemExit('Embedded Sparkle framework is missing')
identity = sys.argv[2]
version = (framework / 'Versions/Current').resolve(strict=True)
components = [version / 'Autoupdate', version / 'Updater.app',
              version / 'XPCServices/Downloader.xpc', version / 'XPCServices/Installer.xpc']
for component in components + [framework]:
    if not component.exists():
        raise SystemExit(f'Missing Sparkle component: {component.name}')
    command = ['codesign', '--force', '--options', 'runtime', '--preserve-metadata=entitlements',
               '--timestamp=none' if identity == '-' else '--timestamp', '--sign', identity, str(component)]
    subprocess.run(command, check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(framework)], check=True)
PY
