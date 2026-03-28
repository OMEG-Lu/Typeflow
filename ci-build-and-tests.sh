#!/bin/bash

set -euo pipefail

rm -f Podfile.lock
rm -rf Pods
pod install

echo "===================tests===================="
bash unit-tests.sh

echo "=================build App=================="
bash build.sh
