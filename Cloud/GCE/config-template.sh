#!/bin/bash
#
# GCE configuration.
#
# Generally, only the PROJECT_ID and PROJECT_NUMBER as well as the Fuzzilli options need to be changed.
#

# The GCP project to use. See https://cloud.google.com/resource-manager/docs/creating-managing-projects#identifying_projects
PROJECT_ID=YOUR_PROJECT_ID
PROJECT_NUMBER=YOUR_PROJECT_NUMBER

# The name of the session, can be an arbitrary string.
# This also serves as the prefix for instance names. For example, the root instance will be named $SESSION-root.
SESSION="fuzzilli"

# The path to the JavaScript engine binary in the container
BINARY=./v8/d8
# Common arguments to pass to every Fuzzilli instance. See ./Fuzzilli --help
FUZZILLI_ARGS="--profile=v8"
# Arguments for the root instance. See ./Fuzzilli --help
FUZZILLI_ROOT_ARGS="--exportStatistics"

# Region and zone where compute instances are created. See https://cloud.google.com/compute/docs/regions-zones
REGION=us-east1
ZONE=$REGION-b

# By default, the default service account: https://cloud.google.com/iam/docs/service-accounts#default
SERVICE_ACCOUNT=$PROJECT_NUMBER-compute@developer.gserviceaccount.com

# The docker container and OS image to use.
CONTAINER_NAME=fuzzilli
CONTAINER_IMAGE=gcr.io/$PROJECT_ID/$CONTAINER_NAME:latest
# By default, use the latest stable OS image
OS_IMAGE=$(gcloud compute images list --filter="family=cos-stable" --format="value(NAME)")

# Number of master instances (N)
NUM_MASTERS=8
# Number of worker instances per master (M)
NUM_WORKERS_PER_MASTER=16

# 2 cores, 8 GB
ROOT_MACHINE_TYPE=e2-standard-2
# 2 cores, 8 GB
MASTER_MACHINE_TYPE=e2-standard-2
# 4 cores, 16GB
WORKER_MACHINE_TYPE=e2-standard-4

# The workers use multiple fuzzilli instances per machine so that for example memory pages
# for the JS engine and the Fuzzilli binary can be shared between them.
WORKER_INSTANCES_PER_MACHINE=4
