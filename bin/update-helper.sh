#!/bin/bash
set -e

# Vars:
environments='@self'
updated_packages=""

function header1() {
  printf '\n// %s //\n\n' "$1"
}

function header2() {
  printf '/// %s ///\n\n' "$1"
}


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
      echo -e "\n"
      header2 "Updating: $c"

      package_version_from=$(composer show $c | grep versions | awk '{print $4}')

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

      package_version_to=$(composer show $c | grep versions | awk '{print $4}')

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

      if [ "$package_version_from" != "$package_version_to" ]
      then
        updated_packages="$c from $package_version_from to $package_version_to\n$updated_packages"
      fi

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

header1 "SETUP"

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

header1 "SUMMARY"
echo "   1. Checking outdated packages"
echo "   2. Consolidating configuration"
echo "   3. Updating packages"
echo "   4. Report"

header1 "1. CHECKING OUTDATED PACKAGES"

# Get the packages to be updated (direct dependencies): outdated, minor version only
packages_to_update=$($updates)
drupal_version="$(drush status --format=list 'Drupal version' | cut -d. -f1 -)"

echo "$packages_to_update"
printf '\n'

# Revert any overriden config to only export new configurations provided by module updates.
if [[ $drupal_version -gt 8 ]]; then
  run_drush $environments cr
  run_drush $environments cim -y

  header1 "2. CONSOLIDATING CONFIGURATION"
  # Estabilize current config (do not commit not exported config associated to a module):
  run_drush $environments cex -y
  git add config && git commit -m "CONFIG - Consolidate current configuration" "$author_commit" -n  || echo "No changes to commit"

  run_drush $environments cr

  run_drush $environments cim -y
fi

header1 "3. UPDATING PACKAGES"
composer_update_outdated $drupal_version $environments

header1 "4. REPORT"

if [ "$updated_packages" != "" ]
then
  echo -e "\n"
  header2 "Updated Packages"
  echo -e "$updated_packages\n"
fi

header2 "Not Updated Packages"
composer show -oD
