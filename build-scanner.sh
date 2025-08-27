#!/bin/bash

set -e

if [[ "$DEBUG" != "" ]]; then
  set -x
fi

REPO=${REPO:-"devkteam/sonar-scanner-cli"}
PROJECT_DIR=${PROJECT_DIR:-"sonar-scanner-cli-docker"}
BUILDER=${BUILDER:-multi}
BUILD_ARGS=${BUILD_ARGS:-"--push"}
BUILD_PLATFORMS=${BUILD_PLATFORMS:-"linux/arm64,linux/amd64"}

cd /tmp

CHECK_BUILDER=$(docker buildx inspect $BUILDER > /dev/null && echo "Builder exists" || echo "Builder not found" )

if [[ "$CHECK_BUILDER" == "Builder not found" ]]; then
  docker buildx create --name $BUILDER --driver docker-container
else
  echo "Builder $BUILDER found"
fi

rm -rf $PROJECT_DIR
echo "Cloning Sonar Scanner CLI Repo"
git clone -q https://github.com/SonarSource/sonar-scanner-cli-docker.git $PROJECT_DIR
cd $PROJECT_DIR

LATEST_TAG=$(git tag | sort -nr | head -n 1)
CHECK_TAG=$(docker manifest inspect $REPO:$LATEST_TAG > /dev/null && echo "Tag exists" || echo "Tag not found")

if [[ "$CHECK_TAG" == "Tag not found" ]]; then
  git checkout $LATEST_TAG
  docker buildx --builder=$BUILDER build --platform $BUILD_PLATFORMS --tag $REPO:$LATEST_TAG ${BUILD_ARGS} .
  docker buildx --builder=$BUILDER build --platform $BUILD_PLATFORMS --tag $REPO:latest ${BUILD_ARGS} .
else
  echo "Latest Tag $REPO:$LATEST_TAG already exists on Docker Hub"
fi