#!/bin/bash
#
# Push the current fuzzilli image (built from the Docker/ directory) to the GCE docker registry.
#

set -e

source config.sh

sudo docker tag fuzzilli gcr.io/$PROJECT_ID/$CONTAINER_NAME
sudo docker push gcr.io/$PROJECT_ID/$CONTAINER_NAME
