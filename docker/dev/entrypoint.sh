#!/bin/sh
# Installs gems/JS packages on first boot (cached in volumes) and prepares the DB.
set -e
cd /app

if [ "${WELLO_WAIT_FOR_DEPS:-false}" = "true" ]; then
  # Let the app container do the installs to avoid two installers on one volume
  until bundle check >/dev/null 2>&1 && [ -f node_modules/.yarn-integrity ]; do
    echo "Waiting for app container to install dependencies..."; sleep 5
  done
else
  bundle check >/dev/null 2>&1 || bundle install --jobs 4
  if [ ! -f node_modules/.yarn-integrity ] || [ package.json -nt node_modules/.yarn-integrity ]; then
    yarn install --network-timeout 1000000
  fi
fi

# Fonts, field-detection model, and signature font expected by the app
mkdir -p tmp public/fonts
[ -e tmp/model.onnx ] || ln -sf /opt/model.onnx tmp/model.onnx
[ -e public/fonts/DancingScript-Regular.otf ] || ln -sf /fonts/DancingScript-Regular.otf public/fonts/
ln -sf /usr/lib/libonnxruntime.so.1 "$(ruby -e "print Dir[Gem::Specification.find_by_name('onnxruntime').gem_dir + '/vendor/*.so'].first")" 2>/dev/null || true

if [ "${WELLO_PREPARE_DB:-false}" = "true" ]; then
  until pg_isready -h "${DATABASE_HOST:-db}" -U postgres >/dev/null 2>&1; do
    echo "Waiting for Postgres..."; sleep 2
  done
  bundle exec rails db:prepare
fi

exec "$@"
