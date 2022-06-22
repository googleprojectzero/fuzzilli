#!/bin/bash
#
# Push the current fuzzilli image (built from the Docker/ directory) to the GCE docker registry.
#

set -e

source config.sh

docker tag $CONTAINER_NAME:latest $REGION-docker.pkg.dev/$PROJECT_ID/fuzzilli-docker-repo/$CONTAINER_NAME
docker push $REGION-docker.pkg.dev/$PROJECT_ID/fuzzilli-docker-repo/$CONTAINER_NAME
