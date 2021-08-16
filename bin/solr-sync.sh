#!/bin/bash
set -ex
PROJECT_NAME=$1
SOLR_CONTAINER=${2:- 'solr'}
CORES=${3:- 'default'}
for core in ${CORES}
do
  docker cp solr/cores/ $(docker ps --filter name="^${PROJECT_NAME}_solr" --format "{{ .ID }}"):"/tmp/cores"
  docker-compose exec -T ${SOLR_CONTAINER} sh -c "solr delete -c $core" || true
  docker-compose exec -T ${SOLR_CONTAINER} sh -c "solr create_core -c $core -d /tmp/cores/$core"
done
