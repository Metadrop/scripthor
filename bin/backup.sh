#!/bin/bash
#######################################
#  Perform a full backup of the site
#  on the users home.
#  This script can be called directly
#  or automated by cron, as it do a
#  cleanup for oldest backups.
#
#
#  $1: Folder to backup to. Optional.
#
#  $2: Site name. used top name the
#      backup files. Optional.
#
#
#             WARNING!
#  Execute from the project root
#
#             WARNING!
#  Not compatible with multisite setups
#
#######################################

set -e

BACKUPS_ROOT="${1:-./backups}"
BACKUPS_DIR_SITE=$BACKUPS_ROOT/backups-automated/site
BACKUPS_DIR_DB=$BACKUPS_ROOT/backups-automated/db
N_BACKUPS_KEEP=5
BACKUP_PREFIX=${2:-site}

if [[ ! -d "./web/sites" ]] || [[ ! -f "./web/core/modules/system/system.module" ]]
then
  printf "************************************************************\n"
  printf "* Error: Please run the script from a Drupal project root. *\n"
  printf "************************************************************\n"
  print_help
  exit 1
fi

if [[ ! -d $BACKUPS_ROOT ]]
then
  printf "The destination folder '$BACKUPS_ROOT' is not a directory\n"
  exit -1
fi


#######################################
#  Ensure directory exist
#
#  params:
#    $1: directory absolute path
#######################################
function ensure_directory() {
  if [ ! -d $1 ]
  then
    mkdir -p $1
  fi
}

#######################################
#  Do a cleanup for oldest files
#
#  params:
#    $1: directory absolute path
#    $2: max number of files to keep
#######################################
function cleanup() {
  cd $1
  N_BACKUPS=`ls -1 | wc -l`
  if [ ${N_BACKUPS} -gt $2 ]
  then
    LATEST_BACKUPS=`ls -ct1 | head -n $2 | tr '\n' '|'`
    ls -1 | grep -E -v "^(${LATEST_BACKUPS})$" | xargs rm
  fi
  cd - > /dev/null
}

# Ensure directories exist
ensure_directory ${BACKUPS_DIR_SITE}
ensure_directory ${BACKUPS_DIR_DB}

# Do the backups
STAMP=`date +%Y%m%d-%H%M%S`
printf "\nDumping database to ${BACKUPS_DIR_DB}/${BACKUP_PREFIX}-db-${STAMP}.sql-gz..."
drush sql-dump --gzip > ${BACKUPS_DIR_DB}/${BACKUP_PREFIX}-db-${STAMP}.sql-gz
printf "OK!"

printf "\nBackuping codebase and files..."
tar -czpf ${BACKUPS_DIR_SITE}/${BACKUP_PREFIX}-code-${STAMP}.tar.gz web/
printf "OK!"


# Cleanup for older files
printf "\nCleaning old backups..."
cleanup ${BACKUPS_DIR_SITE} ${N_BACKUPS_KEEP}
cleanup ${BACKUPS_DIR_DB} ${N_BACKUPS_KEEP}
printf "OK!\n"

