#!/bin/bash

# Star traefik to generate random port.
docker-compose up -d traefik
# Setup the port on .env file.
sed -i "s/CONTAINER_PORT.*/CONTAINER_PORT\=$(docker-compose port traefik 80 | cut -d: -f2)/g" .env
echo "Project URL: http://$(grep -oP '(?<=PROJECT_BASE_URL=).*' .env):$(docker-compose port traefik 80 | cut -d: -f2)"
