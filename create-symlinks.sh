#!/bin/bash
set -e

# Create symlinks if they don't exist, allowing project specific customizations.
FILES=(
  "frontend-build.sh"
  "copy-content-config-entity-to-module.sh"
  "reload-local.sh"
)
DIR="./scripts"

if [ ! -d $DIR ]
  mkdir "$DIR"
fi

for FILE in "${FILES[@]}"
do
  if [ ! -L "$DIR/$FILE" ] && [ ! -f "$DIR/$FILE" ]; then
      ln -s ../vendor/metadrop/scripthor/$FILE ./scripts/$FILE
  fi
done
