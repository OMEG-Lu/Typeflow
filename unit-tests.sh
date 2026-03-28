#!/bin/bash

set -euo pipefail

xcodebuild build-for-testing \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  -workspace hallelujah.xcworkspace/ \
  -scheme Tests \
  -destination "platform=macOS"
