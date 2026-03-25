#!/bin/bash
# Install Flutter if it doesn't exist
if [ ! -d "flutter" ]; then
  git clone https://github.com/flutter/flutter.git -b stable
fi
export PATH="$PATH:`pwd`/flutter/bin"

# Build the Flutter web app
flutter build web --release
