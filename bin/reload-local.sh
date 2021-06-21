#!/bin/bash
#######################################
#  Reloads local environment for a fresh start.
#
#  It is recomended to run this script when starting a new branch.
#  It should be run outside of docker.
#  It currently perform:
#  - composer install
#  - database sync
#  - database sanitization
#  - drush updatedb
#  _ drush config-import
#  - CSS and JS transpilation
#  - cache rebuild
#  - display a one time user login link
#######################################
set -e

function get_default_value() {
  VARNAME=$1
  DEFAULT_VALUE=$2

  ENV_VALUE=$(egrep ${VARNAME} ${PROJECT_ROOT}/.env | sed s/${VARNAME}=//)
  eval "${VARNAME}=${ENV_VALUE:-$DEFAULT_VALUE}"
}


PROJECT_ROOT="./"

# Default flags values.
get_default_value DEFAULT_DRUSH_ALIAS site.test
get_default_value DOCKER_PROJECT_ROOT /var/www/html
get_default_value NO_ACTION false
get_default_value DATABASE_ONLY false
get_default_value NO_DATABASE false
get_default_value REFRESH_LOCAL_DUMP false
get_default_value SKIP_TRANSLATIONS false
get_default_value NPM_RUN_COMMAND dev

# Set the target remote Environment to download database.
DEFAULT_SITE=$(echo $DEFAULT_DRUSH_ALIAS | cut -d . -f 1)
REMOTE_ENVIRONMENT=$(echo $DEFAULT_DRUSH_ALIAS | cut -d . -f 2)

SITE=$DEFAULT_SITE

# Scripts/executables.compilation
DOCKER_EXEC_PHP="docker-compose exec php"
DOCKER_EXEC_TTY_PHP="docker-compose exec -T php"
DOCKER_EXEC_NPM="docker-compose exec node"
COMPOSER_EXEC="docker-compose exec php composer"
RM_EXEC="rm"

# Having a month based db backup filename ensures the database is refreshed at least every month.
BACKUP_FILE_NAME_TEMPLATE=db-$(date +%Y-%m)

function show_help() {
cat << EOF

Reloads a site's local environment with data from a given remote environment.

Reloads includes:
  - Execute composer install.
  - Download database from remote environment and site (if needed).
  - Imports downloaded database in local environment and site.
  - Drupal update (updb and cim).
  - Frontend assets generation  (./scripts/frontend-build.sh)

Usage: ${0##*/} [-d|--database-only] [-e|--env=(ENVIRONMENT_NAME)] [-s|--site=(SITE_NAME)]
  -h|--help         Show this help and exit.

  -d
  --database-only   Perfom only database sync operation (composer install and site update is not done).

  --no-database     Do not perform database sync operation.

  -e=ENV
  --env=ENV         The environment from which to syncronize the database, as expresed in your drush aliases.

  -s=SITE
  --site=SITE       The site to reload, as expresed in your drush aliases.

  -r
  --refresh         Refresh the local dump file before importing it. This is always done if no local file is found.

  -n
  --no-action       Show actions that would be done but do not execute any command. Useful for debugging purposes.

  --skip-translations  Skip translations check and update.

You can add default values to most of the parameters by editing the .env file.
Here is a relation of the supported variables and their default values

NO_ACTION=false
DATABASE_ONLY=false
NO_DATABASE=false
REFRESH_LOCAL_DUMP=false
SKIP_TRANSLATIONS=false
DEFAULT_DRUSH_ALIAS=site.test
DOCKER_PROJECT_ROOT=/var/www/html
NPM_RUN_COMMAND=dev

EOF
}

#######################################
# Create database if not exist and grant privileges.
# Globals:
#   PROJECT_ROOT
#   SITE
# Arguments:
#   None
# Returns:
#   None
#######################################
function create_database() {
  # Get connection credentials from .env file.
  MYSQL_ROOT_PASS=$(egrep DB_ROOT_PASSWORD[^a-zA-Z_] ${PROJECT_ROOT}/.env | sed s/DB_ROOT_PASSWORD=//)
  MYSQL_HOST=$(egrep DB_HOST[^a-zA-Z_] ${PROJECT_ROOT}/.env | sed s/DB_HOST=//)
  MYSQL_DB_NAME=$(egrep DB_NAME[^a-zA-Z_] ${PROJECT_ROOT}/.env | sed s/DB_NAME=//)
  MYSQL_DB_USER=$(egrep DB_USER[^a-zA-Z_] ${PROJECT_ROOT}/.env | sed s/DB_USER=//)

  if [ $SITE != $DEFAULT_SITE ]
  then
    MYSQL_DB_NAME="${MYSQL_DB_NAME}_${SITE}"
  fi

  # Create DB.
  $DOCKER_EXEC_PHP mysql -u root -p${MYSQL_ROOT_PASS} -h ${MYSQL_HOST} -e "CREATE DATABASE IF NOT EXISTS ${MYSQL_DB_NAME};GRANT ALL PRIVILEGES ON ${MYSQL_DB_NAME}.* TO  '${MYSQL_DB_USER}'@'%';"
}

# Process script options.
#########################
for i in "$@"
do
  case ${i} in
    -h|--help)
        show_help    # Display a usage synopsis.
        exit
        ;;
    -d|--database-only)
        DATABASE_ONLY=true
        ;;
    --no-database)
        NO_DATABASE=true
        ;;
    -e=*|--env=*)       # Takes an option argument; ensure it has been specified.
        REMOTE_ENVIRONMENT="${i#*=}"
        ;;
    -s=*|--site=*)       # Takes an option argument; ensure it has been specified.
        SITE="${i#*=}"
        ;;
    -r|--refresh)
        REFRESH_LOCAL_DUMP=true
        ;;
    -n|--no-action)
        NO_ACTION=true
        ;;
    --skip-translations)
        SKIP_TRANSLATIONS=true
        ;;
    --)              # End of all options.
        shift
        break
        ;;
    -?*|*)
        printf 'ERROR: Unknown option: %s\n' "$1" >&2
        show_help
        exit 1
        ;;
  esac
shift
done


# Perform some sanity checks.
#############################

if [ ${NO_DATABASE} = true ] && [ ${DATABASE_ONLY} = true ]
then
  printf 'ERROR: The options --database-only and --no-database are not compatible.\n' "$1" >&2
  exit 1
fi

# Validate the site and environment.
VALID_ALIASES=$($DOCKER_EXEC_PHP drush sa --format list)
VALID_SITES=$(echo "${VALID_ALIASES[@]//@}" | cut -d . -f 1 | uniq)
VALID_ENVIRONMENTS=$(echo "${VALID_ALIASES[@]//@}" | cut -d . -f 2 | uniq)

IS_VALID_ENVIRONMENT=$(echo "${VALID_ENVIRONMENTS[@]}" | grep -o "${REMOTE_ENVIRONMENT}" | wc -w)
if [ "${IS_VALID_ENVIRONMENT}" = 0 ]
then
  echo "ERROR: Wrong environment: ${REMOTE_ENVIRONMENT}. Valid environments are:"
  echo "${VALID_ENVIRONMENTS[@]}"
  exit 1
fi

IS_VALID_SITE=$(echo "${VALID_SITES[@]}" | grep -o "${SITE}" | wc -w)
if [ "${IS_VALID_SITE}" = 0 ]
then
  echo "ERROR: Wrong site: ${SITE}. Valid sites are:"
  echo "${VALID_SITES[@]}"
  exit 1
fi

echo "Reloading local environment ${SITE} site with database from $REMOTE_ENVIRONMENT remote environment."

# Setup some calculated constants.
if [ $NO_ACTION = true ]
then
    DOCKER_EXEC_PHP="echo $DOCKER_EXEC_PHP"
    DOCKER_EXEC_TTY_PHP="echo $DOCKER_EXEC_TTY_PHP"
    COMPOSER_EXEC="echo $COMPOSER_EXEC"
    RM_EXEC="echo $RM_EXEC"
    DOCKER_EXEC_NPM="echo $DOCKER_EXEC_NPM"
fi

if [ $SITE = $DEFAULT_SITE ]
then
    LOCAL_ALIAS="self"
else
    LOCAL_ALIAS="$SITE.local"
fi

REMOTE_ALIAS="$SITE.$REMOTE_ENVIRONMENT"

BACKUP_FILE_NAME=${BACKUP_FILE_NAME_TEMPLATE}.${SITE}.${REMOTE_ENVIRONMENT}.sql
LOCAL_FILE=${PROJECT_ROOT}tmp/${BACKUP_FILE_NAME}

cd ${PROJECT_ROOT}

if [[ ${DATABASE_ONLY} = false ]]
then
  # Install dependencies.
  $COMPOSER_EXEC install

fi

if [[ ${NO_DATABASE} = false ]]
then

  create_database

  # Drop current database.
  $DOCKER_EXEC_PHP drush @${LOCAL_ALIAS} sql-drop -y

  # Do we need to download a remote dump?
  # Best if we do this before droping current database.
  if [ ${REFRESH_LOCAL_DUMP} = true ] || [ ! -f $LOCAL_FILE ]
  then
    echo "Either no local dump was found or refresh local dump options was passed."
    # Ensure using your personal ssh-key before trying to connect to remote alias for downloading the database.
    ssh-add -k
    $DOCKER_EXEC_PHP drush sql:sync @${REMOTE_ALIAS} @${LOCAL_ALIAS} -y
    $DOCKER_EXEC_PHP drush @${LOCAL_ALIAS} sql:sanitize -y

    if [ $? -ne 0 ]
    then
      echo "There was an error downloading the remote DB dump."
      exit 1
    fi
  else
    echo "Loading database from local file:  ${LOCAL_FILE}"
    cat ${LOCAL_FILE} | $DOCKER_EXEC_TTY_PHP  drush @${LOCAL_ALIAS} sql-cli
  fi

fi

if [[ ${DATABASE_ONLY} = false ]]
then

  # Execute updates and import configuration.
  $DOCKER_EXEC_PHP drush @${LOCAL_ALIAS} updb -y

  if [[ ${SKIP_TRANSLATIONS} = false ]]
  then
    $DOCKER_EXEC_PHP drush @${LOCAL_ALIAS} locale-check

    $DOCKER_EXEC_PHP drush @${LOCAL_ALIAS} locale-update
  fi

  $DOCKER_EXEC_PHP drush @${LOCAL_ALIAS} cim sync -y

  $DOCKER_EXEC_PHP drush @${LOCAL_ALIAS} deploy:hook -y

  $DOCKER_EXEC_NPM sh ${DOCKER_PROJECT_ROOT}/scripts/frontend-build.sh ${NPM_RUN_COMMAND}

  $DOCKER_EXEC_PHP drush @${LOCAL_ALIAS} cr

  # Show one-time login link.
  $DOCKER_EXEC_PHP drush @${LOCAL_ALIAS} uli

fi

if [ ${REFRESH_LOCAL_DUMP} = true ] || [ ! -f $LOCAL_FILE ]
  then
    echo "Updating local dump."
    $DOCKER_EXEC_PHP drush @${LOCAL_ALIAS} sql:dump --result-file=../$LOCAL_FILE
fi

cat << EOF
//////////////////////////////
//  RELOAD LOCAL COMPLETED  //
//////////////////////////////
EOF
