#!/bin/bash
set -e

# Trim whitespace/newlines from env vars
SUPABASE_URL=$(echo "$SUPABASE_URL" | tr -d '[:space:]')
SUPABASE_ANON_KEY=$(echo "$SUPABASE_ANON_KEY" | tr -d '[:space:]')

echo "Creating .env file from environment variables..."
printf "SUPABASE_URL=%s\n" "$SUPABASE_URL" > .env
printf "SUPABASE_ANON_KEY=%s\n" "$SUPABASE_ANON_KEY" >> .env

echo "SUPABASE_URL length: ${#SUPABASE_URL}"
echo "SUPABASE_ANON_KEY length: ${#SUPABASE_ANON_KEY}"

# Install Flutter if it doesn't exist
if [ ! -d "flutter" ]; then
  git clone https://github.com/flutter/flutter.git -b stable
fi
export PATH="$PATH:$(pwd)/flutter/bin"

# Build the Flutter web app with environment variables passed via --dart-define
flutter build web --release \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
