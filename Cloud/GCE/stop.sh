#!/bin/bash
#
# Terminates all worker instances.
#

set -e

source config.sh

if [ $# -eq 0 ]; then
    echo "Usage: $0 [root|masters|workers|all]"
    exit 1
fi

STOP_ROOT=false
STOP_MASTERS=false
STOP_WORKERS=false

while test $# -gt 0
do
    case "$1" in
        root)
            STOP_ROOT=true
            ;;
        masters)
            STOP_MASTERS=true
            ;;
        workers)
            STOP_WORKERS=true
            ;;
        all)
            STOP_ROOT=true
            STOP_MASTERS=true
            STOP_WORKERS=true
            ;;
        *)
            echo "Usage: $0 [root|masters|workers|all]"
            exit 1
            ;;
    esac
    shift
done

if [ "$STOP_WORKERS" = true ]; then
    echo "[*] Deleting worker instances"
    WORKERS=$(gcloud compute --project=$PROJECT_ID instances list --filter="labels.role=worker && labels.session=$SESSION" --format="value(name)")

    if [ ! -z "$WORKERS" ]; then
        while read -r instance; do
            gcloud compute --project=$PROJECT_ID instances delete $instance --quiet --zone $ZONE &
        done <<< "$WORKERS"
    else
        echo "Nothing to delete"
    fi

    wait
fi

if [ "$STOP_MASTERS" = true ]; then
    echo "[*] Deleting master instances"
    MASTERS=$(gcloud compute --project=$PROJECT_ID instances list --filter="labels.role=master && labels.session=$SESSION" --format="value(name)")

    if [ ! -z "$MASTERS" ]; then
        while read -r instance; do
            gcloud compute --project=$PROJECT_ID instances delete $instance --quiet --zone $ZONE &
        done <<< "$MASTERS"
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
