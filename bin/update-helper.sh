#!/bin/bash
set -e

# Vars:
environments='@self'
updated_packages=""

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

  --envs      Force drush to work with an especific environments alias
EOF
}

function composer_update_outdated() {
  drupal_version=$1
  environments=$2

  # Outdated, minor version, just name, direct dependencies:
  for c in $($updates)
    do
      printf '\n/// UPDATING: " %s "///////////////////////////////\n' "$c"

      set +e
      composer update $c --with-dependencies
      if [[ $? -ne 0 ]]; then
        printf '\n!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
        printf 'Updating package FAILED: recovering previous state.'
        printf '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n'
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
        run_drush "$environments" cc all
      fi
      if [[ $drupal_version -gt 8 ]]; then
        run_drush "$environments" cr
      fi

      run_drush "$environments" updb -y

      if [[ $drupal_version -gt 8 ]]; then
        printf 'Exporting any new configuration: \n'
        run_drush "$environments" cex -y
        git add config
      fi

      git commit -m "UPDATE - $c" "$author_commit" -n || printf "No changes to commit\n"
      updated_packages="$c\n$updated_packages"
      printf '\n/// FINISHED UPDATING: " %s "///////////////////////////////\n' "$c"
    done
}

function run_drush() {
  environments=$1
  commands="${@:2}"
  IFS=',' read -a environment_list <<< $environments
  for environment in "${environment_list[@]}"
  do
    printf 'Running drush %s on the "%s" environment:\n' "$commands" "$environment"
    drush $environment $commands
    printf '\n'
  done
}

## Defaults:
author_commit=""
drush="vendor/bin/drush"
updates="composer show -oND"

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
        printf "GIT author will be overriden with: %s\n" "$author"
        author_commit="--author=\"$author\""
        ;;
    --no-dev)
        printf "Updates without require-dev packages.\n"
        updates+=" --no-dev"
        ;;
    --envs=*)
        environments="${i#*=}"
        printf "Environments used will be %s\n" "$environments"
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
drupal_version="$(drush status --format=list 'Drupal version' | cut -d. -f1 -)"

printf '\n/// PACKAGES TO UPDATE ///\n'
echo "$packages_to_update"
printf '\n'

# Revert any overriden config to only export new configurations provided by module updates.
if [[ $drupal_version -gt 8 ]]; then
  printf '\n Reverting any overriden configuration (drush cim). \n'
  run_drush $environments cr
  run_drush $environments cim -y

  printf '\n Consolidating configuration (drush cex + git add):. \n'
  # estabilize current config (do not commit not exported config assiciated to a module):
  run_drush $environments cex -y
  git add config && git commit -m "CONFIG - Consolidate current config stored in database" "$author_commit" -n  || echo "No changes to commit"

  printf '\n Clearing cache. \n'
  run_drush $environments cr

  printf '\n Re-importing configuration. \n'
  run_drush $environments cim -y
fi

printf '\n/// UPDATING PACKAGES ///\n'
composer_update_outdated $drupal_version $environments

printf '\n/// PACKAGES UPDATED:///\n'
echo -e "$updated_packages\n"

printf '\n/// PACKAGES NOT UPDATED:///\n'
composer show -oD
