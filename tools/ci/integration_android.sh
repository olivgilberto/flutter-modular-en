#!/usr/bin/env bash
# The integration tests on the CI emulator (chapter 40), with the same
# rules as chapter 39's verify_integration.sh: both dev_backend ports
# connected through adb reverse and each file on an app installed from
# scratch. A failing file does not stop the others; the script exits with
# 1 at the end if any failed.
set -u
cd "$(dirname "$0")/../../mobile_tasks_app"
adb reverse tcp:8080 tcp:8080
adb reverse tcp:8081 tcp:8081
status=0
for f in integration_test/*_test.dart; do
  adb uninstall com.zayitbrazil.mobiletasks.dev > /dev/null 2>&1 || true
  echo "::group::$f"
  flutter test "$f" -d emulator-5554 --flavor dev \
    --dart-define-from-file=config/dev_local.json || status=1
  echo "::endgroup::"
done
exit $status
