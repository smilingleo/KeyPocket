#!/bin/bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 /absolute/path/to/KeyPocket.app /absolute/path/to/KeyPocket-iPhone.ipa" >&2
  exit 2
fi
app_path="$1"
ipa_path="$2"
if [[ "$app_path" != /* || "$ipa_path" != /* ]]; then
  echo "Both paths must be absolute." >&2
  exit 2
fi
if [[ ! -d "$app_path" || ! -f "$app_path/embedded.mobileprovision" ]]; then
  echo "A signed iPhone app with an embedded provisioning profile is required." >&2
  exit 1
fi
/usr/bin/codesign --verify --deep --strict "$app_path"
task_temp_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp/}keypocket-package.XXXXXX")"
trap '/bin/rm -rf "$task_temp_dir"' EXIT
/bin/mkdir -p "$task_temp_dir/Payload"
/usr/bin/ditto "$app_path" "$task_temp_dir/Payload/KeyPocket.app"
/usr/bin/ditto -c -k --keepParent "$task_temp_dir/Payload" "$ipa_path"
/usr/bin/unzip -tq "$ipa_path"
echo "Packaged: $ipa_path"
echo "This IPA can be used only on devices covered by its provisioning profile."
