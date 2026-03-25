#!/bin/bash
# Create .env file from environment variables if not already present
if [ ! -f ".env" ]; then
  echo "Creating .env file from environment variables..."
  echo "SUPABASE_URL=$SUPABASE_URL" > .env
  echo "SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY" >> .env
fi

# Install Flutter if it doesn't exist
if [ ! -d "flutter" ]; then
  git clone https://github.com/flutter/flutter.git -b stable
fi
export PATH="$PATH:`pwd`/flutter/bin"

# Build the Flutter web app
flutter build web --release
