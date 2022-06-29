#!/bin/bash
set -ex
PROJECT_NAME=$1
SOLR_CONTAINER=${2:-'solr'}
CORES=${3:-'default'}
docker cp solr/cores/ "${PROJECT_NAME}_${SOLR_CONTAINER}:/tmp/cores"
for core in ${CORES}
do
  docker-compose exec -T ${SOLR_CONTAINER} sh -c "solr delete -c $core" || true
  docker-compose exec -T ${SOLR_CONTAINER} sh -c "solr create_core -c $core -d /tmp/cores/$core"
done
