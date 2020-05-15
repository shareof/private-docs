#!/bin/bash

set -eux

readonly DOCKER_MOUNT_DIR="docker_registry"

function build_private_registry() {
  docker run \
    -d \
    -p 5000:5000 \
    -v ${DOCKER_HOME}/${DOCKER_MOUNT_DIR}:/var/lib/registry \
    -h docker_registry \
    registry:latest
}

function build_docker_frontend(){
  local local_ip=$1
  docker run \
    -d \
    -e ENV_DOCKER_REGISTRY_HOST=${local_ip} \
    -e ENV_DOCKER_REGISTRY_PORT=5000 \
    -p 8080:80 \
    -h registry_browser \
    konradkleine/docker-registry-frontend:v2
}

DOCKER_HOME=$PWD
local_ip=$(ifconfig en0 | awk '/inet / {print $2}')

if [[ ! -d ${DOCKER_HOME}/${DOCKER_MOUNT_DIR} ]]; then
  mkdir ${DOCKER_MOUNT_DIR}
fi

# exec function
build_private_registry
build_docker_frontend ${local_ip}

