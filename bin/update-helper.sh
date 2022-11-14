#!/bin/bash
set -e

# Vars:
environment=''

function show_help() {
cat << EOF

Update composer packages.

Update includes:
  - Commit current configuration not exported (Drupal +8).
  - Identify updatable composer packages (outdated + minor versions)
  - For each package try to update and commit it (recovers previous state if fails)

Usage: ${0##*/} [--author=Name <user@example.com>]
  -h|--help  Show this help and exit.

  --author   Overrides default Git author name. Example Name <user@example.com>

  --no-dev   Disables search in require-dev packages.

  --env      Force drush to work with an especific environment alias
EOF
}

function composer_update_outdated() {
  drupal_version=$1
  environment=$2

  # Outdated, minor version, just name, direct dependencies:
  for c in $($updates)
    do
      echo -e "\n/// UPDATING: " $c "///////////////////////////////"

      set +e
      composer update $c --with-dependencies
      if [[ $? -ne 0 ]]; then
        echo -e "\n!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo "Updating package FAILED: recovering previous state."
        echo -e "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n"
        git checkout composer.json composer.lock
        continue
      fi
      set -e

      # Composer files:
      git add composer.json composer.lock

      # Drupal scaffold files:
      git add web

      # Clear caches to prevent problems with updated code.
      if [[ $drupal_version -eq 7 ]]; then
        drush $environment cc all
      fi
      if [[ $drupal_version -gt 8 ]]; then
        drush $environment cr
      fi

      drush $environment updb -y

      if [[ $drupal_version -gt 8 ]]; then
        echo "Exporting any new configuration:"
        drush $environment cex -y
        git add config
      fi

      git commit -m "UPDATE - $c" "$author_commit" -n || echo "No changes to commit"
      echo -e "\n\n"
    done
}

## Defaults:
author_commit=""
drush="vendor/bin/drush"
updates="composer show -omND"

# Process script options.
#########################
for i in "$@"
do
  case "${i}" in
    -h|--help)
        show_help    # Display a usage synopsis.
        exit
        ;;
    --author=*)
        author="${i#*=}"
        echo "GIT author will be overriden with: $author"
        author_commit="--author=\"$author\""
        ;;
    --no-dev)
        echo "Updates without require-dev packages."
        updates+=" --no-dev"
        ;;
    --env=*)
        environment="${i#*=}"
        echo "Environment used will be $environment"
        ;;
    -?*|*)
        printf 'ERROR: Unknown option: %s\n' "$1" >&2
        show_help
        exit 1
        ;;
  esac
shift
done

# Get the packages to be updated (direct dependencies): outdated, minor version only
packages_to_update=$($updates)
drupal_version="$(${drush} $environment status --format=list 'Drupal version' | cut -d. -f1 -)"

echo -e "\nPackages to update:"
echo "$packages_to_update"

# Revert any overriden config to only export new configurations provided by module updates.
if [[ $drupal_version -gt 8 ]]; then
  echo "Reverting any overriden configuration (drush cim)."
  drush $environment cr
  drush $environment cim -y

  echo "Consolidating configuration (drush cex + git add):"
  # estabilize current config (do not commit not exported config assiciated to a module):
  drush $environment cex -y
  git add config && git commit -m "CONFIG - Consolidate current config stored in database" "$author_commit" -n  || echo "No changes to commit"

  echo "Clearing cache"
  drush $environment cr

  echo "Re-importing configuration"
  drush $environment cim -y
fi

echo -e "\nUpdating packages:"
composer_update_outdated $drupal_version $environment

echo -e "\nPackages that were not updated:"
composer show -omD
