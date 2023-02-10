#!/bin/bash
set -e

# Vars:
environments='@self'
updated_packages=""

function header1() {
  printf '// %s //\n\n' "$1"
}

function header2() {
  printf '/// %s ///\n\n' "$1"
}


function show_help() {
cat << EOF

Update composer packages.

Update includes:
  - Commit current configuration not exported (Drupal +8).
  - Identify updatable composer packages (outdated)
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
  packages_to_update=$3

  # Outdated, minor version, just name, direct dependencies:
  for package in $packages_to_update
    do
      echo -e "\n"
      header2 "Updating: $package"

      package_version_from=$(composer show --locked $package | grep versions | awk '{print $4}')

      set +e
      composer update $package --with-dependencies
      if [[ $? -ne 0 ]]; then
        printf '\n!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
        printf 'Updating package FAILED: recovering previous state.'
        printf '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n'
        git checkout composer.json composer.lock
        continue
      fi
      set -e

      package_version_to=$(composer show --locked $package | grep versions | awk '{print $4}')

      # Composer files:
      git add composer.json composer.lock

      package_type=$(composer show $package | grep ^type | awk '{print $3}')
      printf "Package type: $package_type \n"

      # Drupal specific actions:
      if [[ "$package_type" =~ .*"drupal".* ]]; then

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

      fi

      git commit -m "UPDATE - $package" "$author_commit" -n || printf "No changes to commit\n"

      if [ "$package_version_from" != "$package_version_to" ]
      then
        updated_packages="$package from $package_version_from to $package_version_to\n$updated_packages"
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

function consolidate_configuration() {
  environments=$1
  author_commit=$2
  IFS=',' read -a environment_list <<< $environments
  for environment in "${environment_list[@]}"
  do
    printf 'Consolidating configuration on the "%s" environment:\n' "$commands" "$environment"
    drush $environment cex -y
    git add config && git commit -m "CONFIG - Consolidate current configuration on $environment" "$author_commit" -n  || echo "No changes to commit"
    printf '\n'
  done
}

## Defaults:
author_commit=""
drush="vendor/bin/drush"
update_mode="all"
update_no_dev=""

echo -e "\n"
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
        update_no_dev="--no-dev"
        ;;
    --security)
        printf "Security packages (with dependencies).\n"
        update_mode="security"
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

echo -e "\n"
header1 "SUMMARY"
echo "   1. Consolidating configuration"
echo "   2. Checking packages"
echo "   3. Updating packages"
echo "   4. Report"

# Revert any overriden config to only export new configurations provided by module updates.
echo -e "\n"
header1 "1. CONSOLIDATING CONFIGURATION"
drupal_version="$(drush status --format=list 'Drupal version' | cut -d. -f1 -)"
if [[ $drupal_version -gt 8 ]]; then
  run_drush $environments cr
  run_drush $environments cim -y

  # Estabilize current config (do not commit not exported config associated to a module):
  consolidate_configuration "$environments" "$author_commit"

  run_drush $environments cr

  run_drush $environments cim -y
fi

echo -e "\n"
header1 "2. CHECKING OUTDATED PACKAGES"

# Get the packages to be updated:
if [ "$update_mode" = "security" ] ; then
  packages_to_update=$(composer audit --locked $update_no_dev --format plain 2>&1 | grep ^Package | cut -f2 -d: | sort -u)

  set +e
  drupal_security_packages=$(./vendor/bin/drush pm:security --fields=name --format=list 2>/dev/null)
  set -e

  packages_to_update="$packages_to_update
$drupal_security_packages"

else
  packages_to_update=$(composer show --locked --direct --name-only $update_no_dev 2>/dev/null)
fi

packages_to_update=${packages_to_update// /}

# Silent errors because when there aren't packages grep returns exit code 1.
set +e
packages_to_update=$(echo "$packages_to_update" | grep -E -i "^([A-Z0-9_-]*\/[A-Z0-9_-]*)")
set -e

echo "$packages_to_update"
printf '\n'

echo -e "\n"
header1 "3. UPDATING PACKAGES"
composer_update_outdated "$drupal_version" "$environments" "$packages_to_update"

header1 "4. REPORT"

if [ "$updated_packages" != "" ]
then
  header2 "Updated Packages"
  echo -e "$updated_packages\n"
fi

header2 "Not Updated Packages (Direct)"
composer show --locked --outdated --direct

header2 "Not Updated Packages (ALL)"
composer show --locked --outdated
