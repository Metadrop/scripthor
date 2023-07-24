#!/bin/bash

repository="$1"
docroot_folder=${2:-"web"}
custom_folderfiles=${3:-""}

#####
# This scripts generates an artifact of the project and commits it to the of the
# artifact repository.
#
# The scripts generates an artifact from the current branch for the repository
# and commits it to the matching branch of the artifacts repository. For
# example, if the repository is in the master branch the generated artifact is
# pushed to the master branch of the artifacs repository.
#
###########

# Cleans the created containers and volumes.
function finalize() {
  current_folder=$(basename $(pwd))
  if [ "$current_folder" = "$artifact_folder" ]
  then
    cd ..
  fi

  docker-compose $docker_composer_config down --volumes --remove-orphans
}

# Handles an error (display it and exit).
#
# $1: Error string.
# $2: Error code for exit.
function error() {
  log "Error: $1"
  exit ${2:-1}
}


# Checks if previous command returned an error.
#
# $1: String that describes the operation that the previous command was doing.
function check_error() {
  err_code=${?}
  if [[ $err_code -ne 0 ]]
  then
    error "$1 (operation error code: $err_code)"
  fi
}

function log() {
  printf "[-->] $1\n"
}

# Copy a file or folder from source code to artifact repository folder.
#
# $1: File to copy.
function copy_folderfile() {
  log "Copying ${1}..."
  docker cp -a "${PROJECT_NAME}_php:/var/www/html/${1}" "${artifact_folder}/"
  check_error "Copy failed"
  log "Copy successful\n"
}

# Remove files that can reveal the installed version.
# $1 Pattern to locate files.
function clean_file_from_artifact() {
  find . -name "$1" -exec rm {} \;
  log "File(s) $1 removed or not present in artifact"
}

# Ensure there are no local changes (changed or untracked files).
function assure_is_clean() {
  num_changes=$(git status --porcelain | grep -v generate_artifact| grep -v .env |wc -l)
  if [[ $num_changes -ne 0 ]]
  then
    return -1
  fi
}


# Deploy a .gitignore file for an artifact.
#
# $1 path to the .gitignore file.
function deploy_gitignore() {
cat > $1 <<- EOM
# Ignore sensitive information.
/$docroot_folder/sites/*/settings.local.php
# Ignore local drush settings
/$docroot_folder/sites/*/local.drush.yml
# Ignore paths that contain user-generated content.
/$docroot_folder/sites/*/files
/private-files/*
# OS X files.
.DS_STORE
.Ds_Store
.DS_Store
# Linux files.
.directory
# IDE related directories.
/nbproject/private/
.idea
# Database and compressed files.
*.mysql
*.sql
*.gz
*.zip
*.rar
*.7z
# NPM.
node_modules/
.sass-cache
.cache
# Test related Reports.
/reports/behat/errors/*
/reports/behat/junit/*
/reports/codereview/*
/$docroot_folder/sites/default/settings.local.unmanaged.php
# BackstopJS
/tests/backstopjs/backstop_data/html_report
/tests/backstopjs/backstop_data/bitmaps_test
# Temporary files
/tmp/*
# Ignore docker-compose env specific settings.
/docker-compose.override.yml
# Ensure .gitkeep files are commited so folder structure get respected.
!.gitkeep
# Ignore editor config files.
/.editorconfig
/.gitattributes

EOM

}

#
# Constants
###########
readonly artifact_folder="deploy-artifact"

#
# Read the current branch
#########################
branch="${GIT_BRANCH:-$(git branch --show-current)}"

if [[ -z $branch ]]
then
  error "Could not detect the selected branch. Either you didn't set GIT_BRANCH environment variable or you are in deatached mode"
fi


log "Selected $branch branch"

#
# Sanity checks
###############

# Ensure we are in the repository root.
if [[ ! -d ./docroot ]] \
   || [[ ! -d ./config ]] \
   || [[ ! -d ./docs ]] \
   || [[ ! -f ./composer.json ]] \
   || [[ ! -f ./docker-compose.yml ]]
then
  error "It seems this command has not been launched the repository root folder. Please run it from root folder."
fi

assure_is_clean
check_error "There are changes in the repository (changed and/or untracked files), please run this artifact generation script with folder tree clean."

#
# Let's go!
###########

#
# Prepare artifact repository.
#

# Clone artifact repository if it is not already there.
if [[ ! -d ${artifact_folder} ]]
then
  log "Cloning artifact repository"
  log "###########################"
  git clone ${repository} ${artifact_folder}
  check_error "Repository could not be cloned."
else
  log "Detected artifact repository at ${artifact_folder}"
fi


assure_is_clean
check_error "There are changes in the artifact repository (changed and/or untracked files), please run this artifact generation script with folder tree clean."


# Use desired branch.
cd ${artifact_folder}
check_error "Error entering in the artifact folder"

git checkout ${branch}
check_error "Could not checkout to branch ${branch} in the artifacts repository"
log "Repository switched to ${branch}"

#git pull --ff-only
check_error "Could not pull branch ${branch}"
log "Repository updated using pull"

cd -

log "Repository updated and ready"


#
# Generate code from source repo.
#

log "Starting to generate source code"
log "################################"


# Load environment variables (at least to use DOCKER_PROJECT_ROOT variable).
source .env

docker_composer_config="-f docker-compose.yml -f docker-compose.artifact.yml"

# Makes sure that containers and volumes are destroyed on exit.
trap finalize EXIT

log "Running containers"
docker-compose $docker_composer_config up -d php node
check_error "Could not run containers"

log "Copying source code to containers"
docker cp  ./ ${PROJECT_NAME}_php:/var/www/html
check_error "Source code copy failed"


# Change permissions so the user inside the contanier can  handle the files.
# This is due uid are different in host system than in docker containers.
docker-compose $docker_composer_config exec -T -u root php chown wodby: . -R
check_error "Operation change permissions to allow container user to handle them failed"


# Run composer install to get any needed libraries like the frontend generation
# libraries
log "Installing composer dependencies including development dependencies"
docker-compose $docker_composer_config exec -T php composer install --prefer-dist
check_error "Installation of dependencies using composer failed"

# Build front assets.
log "Building frontend"
docker-compose $docker_composer_config exec -T node ${DOCKER_PROJECT_ROOT}/scripts/frontend-build.sh ${NPM_RUN_COMMAND}
check_error "Could not generate frontend assets"

log "Removing development dependencies and optimizing autoloader"
docker-compose $docker_composer_config exec  -T php composer install --prefer-dist --no-dev --optimize-autoloader
check_error "Removing of dependencies failed"

log "Source code generation process finised OK"

#
# Copy source to artifact repository folder
#

log "Cleaning previous artifact"
log "##########################"
rm ${artifact_folder}/* -fr
check_error "Deleting previous artifact code failed"

log "Starting source copy to artifact repository folder"
log "##################################################"

copy_folderfile config
copy_folderfile drush
copy_folderfile vendor "--exclude composer/tmp-\*"
copy_folderfile scripts "--exclude *.sh"
copy_folderfile $docroot_folder "--exclude node_modules --exclude /.gitignore --exclude files"
copy_folderfile patches

IFS=';' read -ra custom_folderfiles_list <<< "$custom_folderfiles"

#Print the split string
for file in "${custom_folderfiles_list[@]}"
do
    echo "copy_folderfile $file"
    copy_folderfile $file
done


# Make sure there is a tmp folder
[[ -d tmp ]] || mkdir tmp
check_error "Creation of 'tmp' folder failed"



# Add hash.txt file with current source repository hash to know what hash is
# deployed in an environment just checking an url.
hash=$(git rev-parse  HEAD)
check_error "Could not generate commit hash to place in the artifact folder"
echo ${hash} > ${artifact_folder}/docroot/hash.txt
log "Added hash file"


# Add .gitignore
deploy_gitignore ${artifact_folder}/.gitignore

log "Operation to copy source to artifact repository folder finised successfully"


#
# Completing artifact using composer
#
log "Adding external libraries using composer"
log "########################################"

cd ${artifact_folder}


# Remove TXT files
clean_file_from_artifact "CHANGELOG.txt"
clean_file_from_artifact "COPYRIGHT.txt"
clean_file_from_artifact "INSTALL.txt"
clean_file_from_artifact "INSTALL.mysql.txt"
clean_file_from_artifact "INSTALL.pgsql.txt"
clean_file_from_artifact "INSTALL.sqlite.txt"
clean_file_from_artifact "LICENSE.txt"
clean_file_from_artifact "README.txt"
clean_file_from_artifact "UPDATE.txt"
clean_file_from_artifact "USAGE.txt"
clean_file_from_artifact "PATCHES.txt"

# Clean .git folders on contrib modules to avoid Acquia detect them as submodules.
find $docroot_folder/modules/contrib -name ".git" -exec rm -fr {} +

#
# Commit changes
#


git add . .gitignore
check_error "Operation to add files to git stagging area failed"

git commit -m "Artifact commit by artifact generation script"
log "Artifact generation finished successfully in the ${artifact_folder} folder"
log "Take into account that the operation removed development packages so you may want to run 'composer install'"
log "Please, complete the process with:\n  - Adding a tag (if needed)\n  - Merging with master (if this is a prod release)\n  - git push\n"
