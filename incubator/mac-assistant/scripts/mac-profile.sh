#!/usr/bin/env bash
# Print the supported-Mac profile (roadmap backlog item 2). Run on the Mac; paste the output into
# PROJECT-CONTEXT.md. Read-only; prints nothing personal (no serial, user, host, or network names).
set -euo pipefail

[[ "$(uname)" == "Darwin" ]] || { echo "Run this on the Mac." >&2; exit 1; }

sysctl_value() { /usr/sbin/sysctl -n "$1" 2>/dev/null || echo "unknown"; }

chip="$(sysctl_value machdep.cpu.brand_string)"
model="$(sysctl_value hw.model)"
cores="$(sysctl_value hw.ncpu) logical ($(sysctl_value hw.perflevel0.physicalcpu) performance + $(sysctl_value hw.perflevel1.physicalcpu) efficiency)"
memory_gb=$(( $(sysctl_value hw.memsize) / 1073741824 ))
os="$(/usr/bin/sw_vers -productVersion) ($(/usr/bin/sw_vers -buildVersion))"
arch="$(/usr/bin/uname -m)"
xcode="$(/usr/bin/xcode-select -p 2>/dev/null || echo none)"
xcodebuild_version="$(/usr/bin/xcrun xcodebuild -version 2>/dev/null | /usr/bin/head -1 || echo none)"
swift_version="$(/usr/bin/xcrun swift --version 2>/dev/null | /usr/bin/head -1 || echo none)"
data_free="$(/bin/df -h /System/Volumes/Data | /usr/bin/awk 'NR==2 {print $4 " free of " $2}')"

# Foundation Models needs macOS 26, Apple silicon, and Apple Intelligence turned on.
os_major="$(/usr/bin/sw_vers -productVersion | /usr/bin/cut -d. -f1)"
if [[ "$arch" != "arm64" ]]; then
    fm="no (Intel Mac)"
elif (( os_major < 26 )); then
    fm="no (macOS $os_major; needs 26)"
else
    fm="maybe: check System Settings > Apple Intelligence & Siri is on"
fi

cat <<REPORT
## Supported Mac profile ($(/bin/date +%Y-%m-%d))
- Model: $model ($arch)
- Chip: $chip; $cores
- Memory: ${memory_gb} GB
- macOS: $os
- Data volume: $data_free
- Developer tools: $xcode; $xcodebuild_version; $swift_version
- Apple Foundation Models (local model): $fm
REPORT
