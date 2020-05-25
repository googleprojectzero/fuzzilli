#!/bin/bash
#
# Script to setup distributed fuzzing with the following hierarchy:
#   - 1 root instance. It will manage the global corpus and collect all crashes
#   - N masters, communicating with the root, receiving and forwarding new samples and crashes
#   - M workers per master, for a total of N*M workers

set -e

source config.sh

if [ $# -eq 0 ]; then
    echo "Usage: $0 [root|masters|workers|all]"
    exit 1
fi

START_ROOT=false
START_MASTERS=false
START_WORKERS=false

while test $# -gt 0
do
    case "$1" in
        root)
            START_ROOT=true
            ;;
        masters)
            START_MASTERS=true
            ;;
        workers)
            START_WORKERS=true
            ;;
        all)
            START_ROOT=true
            START_MASTERS=true
            START_WORKERS=true
            ;;
        *)
            echo "Usage: $0 [root|masters|workers|all]"
            exit 1
            ;;
    esac
    shift
done

#
# Start root instance
#

if [ "$START_ROOT" = true ]; then
    echo "[*] Starting root instance"
    NAME=$SESSION-root

    # This command assumes that the local $USER is the same as on the GCE instance
    gcloud compute --project=$PROJECT_ID instances create-with-container $NAME \
        --zone=$ZONE \
        --machine-type=$ROOT_MACHINE_TYPE \
        --subnet=default \
        --network-tier=PREMIUM \
        --maintenance-policy=MIGRATE \
        --service-account=$SERVICE_ACCOUNT \
        --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/trace.append \
        --image=$IMAGE \
        --image-project=cos-cloud \
        --boot-disk-size=10GB \
        --boot-disk-type=pd-ssd \
        --container-image=$CONTAINER_IMAGE \
        --container-restart-policy=always \
        --container-privileged \
        --container-command=/bin/bash \
        --container-arg="-c" \
        --container-arg="sysctl -w 'kernel.core_pattern=|/bin/false' && ./Fuzzilli --networkMaster=0.0.0.0:1337 --storagePath=/home/fuzzer/fuzz $IMPORT_CORPUS $FUZZILLI_ARGS $BINARY" \
        --container-mount-host-path=mount-path=/home/fuzzer/fuzz,host-path=/home/$USER/fuzz,mode=rw \
        --container-tty \
        --labels=container-vm=$IMAGE,role=root,session=$SESSION
fi


#
# Start N master instances
#


if [ "$START_MASTERS" = true ]; then
    ROOT_IP=$(gcloud compute instances list --filter="labels.role=root && labels.session=$SESSION" --format="value(networkInterfaces[0].networkIP)")
    if [ -z "$ROOT_IP" ]; then
        echo "[!] Could not locate root instance. Is it running?"
        exit 1
    fi

    echo "[*] Starting $NUM_MASTERS master instances for root instance @ $ROOT_IP"

    MASTERS=$(printf "$SESSION-master-%i " $(seq $NUM_MASTERS))
    gcloud compute --project=$PROJECT_ID instances create-with-container $MASTERS \
        --zone=$ZONE \
        --machine-type=$MASTER_MACHINE_TYPE \
        --subnet=default \
        --network-tier=PREMIUM \
        --maintenance-policy=MIGRATE \
        --service-account=$SERVICE_ACCOUNT \
        --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/trace.append \
        --image=$IMAGE \
        --image-project=cos-cloud \
        --boot-disk-size=10GB \
        --boot-disk-type=pd-ssd \
        --container-image=$CONTAINER_IMAGE \
        --container-restart-policy=always \
        --container-privileged \
        --container-command=/bin/bash \
        --container-arg="-c" \
        --container-arg="sysctl -w 'kernel.core_pattern=|/bin/false' && ./Fuzzilli --networkWorker=$ROOT_IP:1337 --networkMaster=0.0.0.0:1337 $FUZZILLI_ARGS $BINARY" \
        --container-tty \
        --labels=container-vm=$IMAGE,role=master,session=$SESSION
fi

#
# Start M worker instances per master, for a total of N*M workers
#

if [ "$START_WORKERS" = true ]; then
    MASTER_IPS=$(gcloud compute instances list --filter="labels.role=master && labels.session=$SESSION" --format="value(networkInterfaces[0].networkIP)")
    if [ -z "$MASTER_IPS" ]; then
        echo "[!] Could not locate master instances. Are they running?"
        exit 1
    fi

    if (( $NUM_WORKERS_PER_MASTER % $WORKER_INSTANCES_PER_MACHINE != 0 )); then
        echo "[!] M is not divisible by the number of fuzzer instances per machine"
        exit 1
    fi
    NUM_WORKER_MACHINES_PER_MASTER=$(($NUM_WORKERS_PER_MASTER / $WORKER_INSTANCES_PER_MACHINE))

    echo "[*] Starting $NUM_WORKER_MACHINES_PER_MASTER (preemptible) worker machines per master, each running $WORKER_INSTANCES_PER_MACHINE Fuzzilli instances"

    MASTER_ID=1
    while read -r MASTER_IP; do
        echo "[*] Starting workers for master instance $MASTER_ID @ $MASTER_IP"

        WORKERS=$(printf "$SESSION-worker-$MASTER_ID-%i " $(seq $NUM_WORKER_MACHINES_PER_MASTER))
        MASTER_ID=$((MASTER_ID + 1))
        gcloud compute --project=$PROJECT_ID instances create-with-container $WORKERS \
            --zone=$ZONE \
            --machine-type=$WORKER_MACHINE_TYPE \
            --subnet=default \
            --no-address \
            --maintenance-policy=TERMINATE \
            --preemptible \
            --service-account=$SERVICE_ACCOUNT \
            --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/trace.append \
            --image=$IMAGE \
            --image-project=cos-cloud \
            --boot-disk-size=10GB \
            --boot-disk-type=pd-ssd \
            --container-image=$CONTAINER_IMAGE \
            --container-restart-policy=always \
            --container-privileged \
            --container-command=/bin/bash \
            --container-arg="-c" \
            --container-arg="sysctl -w 'kernel.core_pattern=|/bin/false' && for i in {1..$WORKER_INSTANCES_PER_MACHINE}; do ./Fuzzilli --minMutationsPerSample=8 --logLevel=warning --networkWorker=$MASTER_IP:1337 $FUZZILLI_ARGS $BINARY & done; wait" \
            --container-tty \
            --labels=container-vm=$IMAGE,role=worker,session=$SESSION
    done <<< "$MASTER_IPS"
fi
