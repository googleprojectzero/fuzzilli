#!/bin/bash
#
# GCE configuration.
#
# Generally, only the PROJECT_ID and PROJECT_NUMBER as well as the Fuzzilli options and NUM_LEAF_NODES need to be changed.
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
# Arguments for the intermediate instances. See ./Fuzzilli --help
FUZZILLI_INTERMEDIATE_ARGS=""
# Arguments for the leaf instances. See ./Fuzzilli --help
FUZZILLI_LEAF_ARGS=""

# Region and zone where compute instances are created. See https://cloud.google.com/compute/docs/regions-zones
REGION=us-east1
ZONE=$REGION-b

# By default, the default service account: https://cloud.google.com/iam/docs/service-accounts#default
SERVICE_ACCOUNT=$PROJECT_NUMBER-compute@developer.gserviceaccount.com

# The docker container and OS image to use.
CONTAINER_NAME=fuzzilli
CONTAINER_IMAGE=gcr.io/$PROJECT_ID/$CONTAINER_NAME:latest
# By default, use the latest stable OS image
OS_IMAGE=$(gcloud compute --project=$PROJECT_ID images list --filter="family=cos-stable" --format="value(NAME)")

# Total number of leaf nodes. Adjust this as desired.
NUM_LEAF_NODES=128

# How many Fuzzilli instances to run per machine, using --jobs=N.
# NUM_LEAF_NODES / NUM_INSTANCES_PER_MACHINE machines will be started.
# This number should roughly equal the number of cores on the leaf machines.
NUM_INSTANCES_PER_MACHINE=8

# How many child nodes a single parent node can handle at most.
# This will determine the depth of the instace hierarchy.
MAX_CHILD_NODES_PER_PARENT=32

# 2 cores, 8 GB
ROOT_MACHINE_TYPE=e2-standard-2
# 2 cores, 4GB
INTERMEDIATE_MACHINE_TYPE=e2-medium
# 8 cores, 8 GB
LEAF_MACHINE_TYPE=e2-highcpu-8

# The amount of disk space for the image. This should be enough for the target
# binary and potential crashes and samples.
DISK_SIZE=20GB

# GCE instance type of the leaf nodes, can be "permanent" or "preemtible". Preemptible instances are (much) cheaper but
# live at most 24 hours and may be shut down at any time. Typically it only makes sense to use preemtible instances when
# the corpus is synchronized as 24h is otherwise not long enough for a decent fuzzing run.
LEAF_INSTANCE_TYPE=preemtible
