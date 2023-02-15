#!/bin/bash
#
# Stops fuzzing jobs.
#

set -e

source config.sh

if [ $# -eq 0 ]; then
    echo "Usage: $0 [root|intermediates|leaves|all]"
    exit 1
fi

STOP_ROOT=false
STOP_INTERMEDIATES=false
STOP_LEAVES=false

while test $# -gt 0
do
    case "$1" in
        root)
            STOP_ROOT=true
            ;;
        intermediates)
            STOP_INTERMEDIATES=true
            ;;
        leaves)
            STOP_LEAVES=true
            ;;
        all)
            STOP_ROOT=true
            STOP_INTERMEDIATES=true
            STOP_LEAVES=true
            ;;
        *)
            echo "Usage: $0 [root|intermediates|leaves|all]"
            exit 1
            ;;
    esac
    shift
done

if [ "$STOP_LEAVES" = true ]; then
    echo "[*] Deleting leaf nodes"
    NODES=$(gcloud compute --project=$PROJECT_ID instances list --filter="labels.role=leaf && labels.session=$SESSION" --format="value(name)")

    if [ ! -z "$NODES" ]; then
        while read -r instance; do
            gcloud compute --project=$PROJECT_ID instances delete $instance --quiet --zone $ZONE &
        done <<< "$NODES"
    else
        echo "Nothing to delete"
    fi

    wait
fi

if [ "$STOP_INTERMEDIATES" = true ]; then
    echo "[*] Deleting intermediate nodes"
    NODES=$(gcloud compute --project=$PROJECT_ID instances list --filter="labels.role=intermediate && labels.session=$SESSION" --format="value(name)")

    if [ ! -z "$NODES" ]; then
        while read -r instance; do
            gcloud compute --project=$PROJECT_ID instances delete $instance --quiet --zone $ZONE &
        done <<< "$NODES"
    else
        echo "Nothing to delete"
    fi

    wait
fi

if [ "$STOP_ROOT" = true ]; then
    echo "[*] Deleting root instance"
    ROOT=$(gcloud compute --project=$PROJECT_ID instances list --filter="labels.role=root && labels.session=$SESSION" --format="value(name)")
    if [ ! -z "$ROOT" ]; then
        gcloud compute --project=$PROJECT_ID instances delete $ROOT --quiet --zone $ZONE
    else
        echo "Nothing to delete"
    fi
fi
