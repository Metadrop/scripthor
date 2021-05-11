#!/bin/bash
# Vars:
set -e

function composer_update_outdated() {
  DRUPAL_VERSION=$1

  # Outdated, minor version, just name, direct dependencies:
  for c in $(composer show -omND)
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
      if [[ $DRUPAL_VERSION -eq 7 ]]; then
        drush cc all
      fi
      if [[ $DRUPAL_VERSION -gt 8 ]]; then
        drush cr
      fi

      drush updb -y

      if [[ $DRUPAL_VERSION -gt 8 ]]; then
        echo "Exporting any new configuration:"
        drush cex -y
        git add config
      fi

      git commit -m "UPDATE - $c" --author="$author" -n || echo "No changes to commit"
      echo -e "\n\n"
    done
}

author=${1:-"SCRIPTHOR <user@example.com>"}
drush=${drush:-vendor/bin/drush}

# Get the packages to be updated (direct dependencies): outdated, minor version only
packages_to_update=$(composer show -omND)
DRUPAL_VERSION="$(${drush} status --format=list 'Drupal version' | cut -d. -f1 -)"

echo -e "\nPackages to update:"
echo "$packages_to_update"

# Revert any overriden config to only export new configurations provided by module updates.
if [[ $DRUPAL_VERSION -gt 8 ]]; then
  echo "Reverting any overriden configuration (drush cim)."
  drush cr
  drush cim -y

  echo "Consolidating configuration (drush cex + git add):"
  # estabilize current config (do not commit not exported config assiciated to a module):
  drush cex -y
  git add config && git commit -m "CONFIG - Consolidate current config stored in database" --author="$author" -n  || echo "No changes to commit"

  echo "Clearing cache"
  drush cr

  echo "Re-importing configuration"
  drush cim -y
fi

echo -e "\nUpdating packages:"
composer_update_outdated $DRUPAL_VERSION

echo -e "\nPackages that were not updated:"
composer show -omD
