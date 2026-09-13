#!/bin/zsh
# Installs the Finder Quick Action "Transcribe with Hark" and removes the three older
# CLI-based actions ("Transcribe to Text File / to Clipboard / to Subtitles (SRT)").
#
# WHY THIS SHAPE. The old actions ran the `transcribe` CLI directly from Automator's Run Shell
# Script. That child process inherits Automator's sandbox, and inside it AVFoundation's media
# decode fails with a bare _GenericObjCError (both AVAssetExportSession and AVAssetReader;
# proven with an instrumented run on 2026-08-04: the raw file read fine, only the decode died).
# The same binary worked from a Terminal every time, which is how three fixes shipped without
# touching the cause. `open -g -a Hark <file>` asks LaunchServices to launch Hark as a normal
# user app, outside that sandbox. Hark receives the file as a document, transcribes it with
# speaker labels, writes <file>.txt beside it, and posts a notification.
#
#   usage: ./install-quick-action.sh
#   needs: ~/Applications/Hark.app   (cd ~/Code/transcribe-app && ./make-app.sh release --install)
set -e

APP="$HOME/Applications/Hark.app"
SERVICES="$HOME/Library/Services"
NAME="Transcribe with Hark"

if [[ ! -d "$APP" ]]; then
  echo "Hark is not installed at $APP." >&2
  echo "Run: cd ~/Code/transcribe-app && ./make-app.sh release --install" >&2
  exit 1
fi

mkdir -p "$SERVICES"
for old in "Transcribe to Text File" "Transcribe to Clipboard" "Transcribe to Subtitles (SRT)"; do
  rm -rf "$SERVICES/$old.workflow"
done

WF="$SERVICES/$NAME.workflow"
rm -rf "$WF"
mkdir -p "$WF/Contents"

cat > "$WF/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>NSServices</key>
  <array>
    <dict>
      <key>NSMenuItem</key>
      <dict><key>default</key><string>$NAME</string></dict>
      <key>NSMessage</key>
      <string>runWorkflowAsService</string>
      <key>NSSendFileTypes</key>
      <array>
        <string>public.audio</string>
        <string>public.movie</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
PLIST

# The app path is ABSOLUTE and baked in at install time. A runtime $HOME reference broke once
# under a redirected home; never reintroduce it. "$@" stays quoted so it expands when run.
SCRIPT='APP="'"$APP"'"
if [[ ! -d "$APP" ]]; then
  osascript -e "display notification \"Hark is not installed at $APP\" with title \"'"$NAME"'\""
  exit 1
fi
# -g: do not bring Hark to the front. It works in the background and notifies when each
# transcript is written. open returns at once, so this action never blocks or errors.
open -g -a "$APP" "$@"'

/usr/bin/python3 - "$WF/Contents/document.wflow" "$SCRIPT" <<'PY'
import plistlib, sys, uuid

out_path, script = sys.argv[1], sys.argv[2]
uid = lambda: str(uuid.uuid4()).upper()

action = {
    "AMAccepts": {"Container": "List", "Optional": True,
                  "Types": ["com.apple.cocoa.string"]},
    "AMActionVersion": "2.0.3",
    "AMApplication": ["Automator"],
    "AMParameterProperties": {
        "COMMAND_STRING": {}, "CheckedForUserDefaultShell": {},
        "inputMethod": {}, "shell": {}, "source": {},
    },
    "AMProvides": {"Container": "List", "Types": ["com.apple.cocoa.string"]},
    "ActionBundlePath": "/System/Library/Automator/Run Shell Script.action",
    "ActionName": "Run Shell Script",
    "ActionParameters": {
        "COMMAND_STRING": script,
        "CheckedForUserDefaultShell": True,
        "inputMethod": 1,          # 1 = pass input "as arguments"
        "shell": "/bin/zsh",
        "source": "",
    },
    "BundleIdentifier": "com.apple.Automator.RunShellScript",
    "CFBundleVersion": "2.0.3",
    "CanShowSelectedItemsWhenRun": False,
    "CanShowWhenRun": True,
    "Category": ["AMCategoryUtilities"],
    "Class Name": "RunShellScriptAction",
    "InputUUID": uid(),
    "Keywords": ["Shell", "Script", "Command", "Run", "Unix"],
    "OutputUUID": uid(),
    "UUID": uid(),
    "UnlocalizedApplications": ["Automator"],
    "arguments": {},
    "isViewVisible": 1,
    "location": "309.000000:253.000000",
    "nibPath": "/System/Library/Automator/Run Shell Script.action/Contents/Resources/Base.lproj/main.nib",
}

doc = {
    "AMApplicationBuild": "528",
    "AMApplicationVersion": "2.10",
    "AMDocumentVersion": "2",
    "actions": [{"action": action, "isViewVisible": 1}],
    "connectors": {},
    "workflowMetaData": {
        "serviceInputTypeIdentifier": "com.apple.Automator.fileSystemObject",
        "serviceOutputTypeIdentifier": "com.apple.Automator.nothing",
        "serviceProcessesInput": 0,
        "presentationMode": 15,
        "workflowTypeIdentifier": "com.apple.Automator.servicesMenu",
    },
}

with open(out_path, "wb") as f:
    plistlib.dump(doc, f)
PY

/System/Library/CoreServices/pbs -flush 2>/dev/null || true
echo "Installed: $WF"
echo "Right-click any audio or video file in Finder → Quick Actions → $NAME"
