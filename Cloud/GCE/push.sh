#!/bin/bash
#
# Push the current fuzzilli image (built from the Docker/ directory) to the GCE docker registry.
#

set -e

source config.sh

docker tag fuzzilli gcr.io/$PROJECT_ID/$CONTAINER_NAME
docker push gcr.io/$PROJECT_ID/$CONTAINER_NAME
