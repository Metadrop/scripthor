#!/bin/bash
set -e

# This command is executed on the theme directory.

TASK=${1:-""}

if [ -z "$1" ]
then
  echo "Parametter TASK is required. Usage: make frontend dev"
  exit 1
fi

echo "Running ./scripts/frontend-build.sh dev"
npm install
npm run $TASK
