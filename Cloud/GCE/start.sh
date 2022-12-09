#!/bin/bash
#
# Script to setup distributed fuzzing with the following hierarchy:
#   - 1 root instance. It will manage the global corpus and collect all crashes
#   - X master instances, forming a pyramid such that every master has at most $MAX_WORKERS_PER_MASTER workers directly reporting to it
#   - $NUM_WORKERS worker instances, running on $NUM_WORKER / $NUM_WORKERS_PER_MACHINE machines
#
# The image below shows a simple hierarchy with only a single level of master instances. It is also possible to have no master instances
# at all (if the root can already handle all workers) or multiple levels of master instances (if there are more master instances than
# the root can handle on its own).
#
#                                        +----------+
#                                        |          |
#                                        |   root   |
#                                        |          |
#                                        +-+-+----+-+
#                                          | |    |
#                           +--------------+ |    +-----------------------------+
#                           |                |                                  |
#                     +-----v----+           |     +----------+           +-----v----+
#                     |          |           |     |          |           |          |
#                     | master 1 |           +-----> master 2 |           | master N |
#                     |          |                 |          |    ...    |          |
#                     +-+-+----+-+                 +----------+           +----------+
#                       | |    |
#           +-----------+ |    +---------+
#           |             |              |
#    +------v---+ +-------v--+     +-----v----+
#    | worker 1 | | worker 2 | ... | worker M |        ....        ....        ....
#    +----------+ +----------+     +----------+
#
# TODO factor out commong code into functions
#

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

if (( $NUM_WORKERS % $NUM_WORKERS_PER_MACHINE != 0 )); then
    echo "[!] NUM_WORKERS must be divisible by NUM_WORKERS_PER_MACHINE"
    exit 1
fi

# Number of worker machines that we'll need to start, each running $NUM_WORKERS_PER_MACHINE Fuzzilli instances
num_worker_machines=$(($NUM_WORKERS / $NUM_WORKERS_PER_MACHINE))

if [ "$WORKER_INSTANCE_TYPE" = "permanent" ]; then
  WORKER_INSTANCE_TYPE_FLAGS="--maintenance-policy=MIGRATE"
elif [ "$WORKER_INSTANCE_TYPE" = "preemtible" ]; then
  WORKER_INSTANCE_TYPE_FLAGS="--maintenance-policy=TERMINATE --preemptible"
else
  echo "[!] Invalid worker instance type: $WORKER_INSTANCE_TYPE"
  exit 1
fi

# The instance hierarchy. Will contains the number of master instances on every level.
hierarchy=()

# Compute the hierarchy
remaining_instances=$num_worker_machines
while true; do
    # Compute required number of instances on this level, rounding up if necessary
    remaining_instances=$(( ( $remaining_instances + $MAX_WORKERS_PER_MASTER - 1 ) / $MAX_WORKERS_PER_MASTER))

    hierarchy+=( $remaining_instances )

    if (( $remaining_instances == 1 )); then
        # We've reached the root
        break
    fi
done

if [ "$START_ROOT" = true ]; then
    echo "[*] Starting root instance"
    name=$SESSION-root
    gcloud compute --project=$PROJECT_ID instances create-with-container $name \
        --zone=$ZONE \
        --machine-type=$ROOT_MACHINE_TYPE \
        --subnet=default \
        --service-account=$SERVICE_ACCOUNT \
        --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/trace.append \
        --image=$OS_IMAGE \
        --image-project=cos-cloud \
        --boot-disk-size=$DISK_SIZE \
        --boot-disk-type=pd-ssd \
        --container-image=$CONTAINER_IMAGE \
        --container-restart-policy=always \
        --container-privileged \
        --container-tty \
        --container-command=/bin/bash \
        --container-arg="-c" \
        --container-arg="sysctl -w 'kernel.core_pattern=|/bin/false' && ./Fuzzilli --instanceType=master --bindTo=0.0.0.0:1337 --resume --storagePath=/home/fuzzer/fuzz $FUZZILLI_ROOT_ARGS $FUZZILLI_ARGS $BINARY" \
        --container-mount-host-path=mount-path=/home/fuzzer/fuzz,host-path=/home/$USER/fuzz,mode=rw \
        --network-tier=PREMIUM \
        --maintenance-policy=MIGRATE \
        --labels=container-vm=$IMAGE,level=0,role=root,session=$SESSION
fi

if [ "$START_MASTERS" = true ]; then
    for (( level=1; level<${#hierarchy[@]}; level++ )); do
        # The hierarchy array is stored in reverse order
        idx=$(( ${#hierarchy[@]} - $level - 1 ))
        num_machines=${hierarchy[idx]}
        echo "[*] Starting $num_machines masters for level $level"

        prev_level=$(( $level - 1 ))
        master_ips=$(gcloud compute --project=$PROJECT_ID instances list --filter="labels.level=$prev_level && labels.session=$SESSION" --format="value(networkInterfaces[0].networkIP)")
        if [ -z "$master_ips" ]; then
            echo "[!] Could not locate level $prev_level instances. Are they running?"
            exit 1
        fi

        running_instances=0
        remaining_instances=$num_machines
        while read -r master_ip; do
            instances_to_start=$(( $MAX_WORKERS_PER_MASTER < $remaining_instances ? $MAX_WORKERS_PER_MASTER : $remaining_instances ))
            echo "[*] Starting $instances_to_start level $level masters for level $prev_level master instance @ $master_ip"

            instances=$(printf "$SESSION-master-l$level-%i " $(seq $running_instances $(( $running_instances + $instances_to_start - 1 )) ))
            gcloud compute --project=$PROJECT_ID instances create-with-container $instances \
                --zone=$ZONE \
                --machine-type=$MASTER_MACHINE_TYPE \
                --subnet=default \
                --service-account=$SERVICE_ACCOUNT \
                --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/trace.append \
                --image=$OS_IMAGE \
                --image-project=cos-cloud \
                --boot-disk-size=$DISK_SIZE \
                --boot-disk-type=pd-ssd \
                --container-image=$CONTAINER_IMAGE \
                --container-restart-policy=always \
                --container-privileged \
                --container-tty \
                --container-command=/bin/bash \
                --container-arg="-c" \
                --container-arg="sysctl -w 'kernel.core_pattern=|/bin/false' && ./Fuzzilli --instanceType=intermediate --connectTo=$master_ip:1337 --bindTo=0.0.0.0:1337 $FUZZILLI_ARGS $BINARY" \
                --network-tier=PREMIUM \
                --maintenance-policy=MIGRATE \
                --labels=container-vm=$IMAGE,level=$level,role=master,session=$SESSION

            running_instances=$(( $running_instances + $instances_to_start ))
            remaining_instances=$(( $remaining_instances - $instances_to_start ))
        done <<< "$master_ips"
    done
fi

if [ "$START_WORKERS" = true ]; then
    last_level=$(( ${#hierarchy[@]} - 1))
    master_ips=$(gcloud compute --project=$PROJECT_ID instances list --filter="labels.level=$last_level && labels.session=$SESSION" --format="value(networkInterfaces[0].networkIP)")
    if [ -z "$master_ips" ]; then
        echo "[!] Could not locate master instances. Are they running?"
        exit 1
    fi

    echo "[*] Starting $num_worker_machines ($WORKER_INSTANCE_TYPE) worker machines, each running $NUM_WORKERS_PER_MACHINE Fuzzilli instances"

    running_instances=0
    remaining_instances=$num_worker_machines
    while read -r master_ip; do
        instances_to_start=$(( $MAX_WORKERS_PER_MASTER < $remaining_instances ? $MAX_WORKERS_PER_MASTER : $remaining_instances ))
        echo "[*] Starting $instances_to_start workers for level $last_level master instance @ $master_ip"

        instances=$(printf "$SESSION-worker-%i " $(seq $running_instances $(( $running_instances + $instances_to_start - 1 )) ))
        gcloud compute --project=$PROJECT_ID instances create-with-container $instances \
            --zone=$ZONE \
            --machine-type=$WORKER_MACHINE_TYPE \
            --subnet=default \
            --service-account=$SERVICE_ACCOUNT \
            --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/trace.append \
            --image=$OS_IMAGE \
            --image-project=cos-cloud \
            --boot-disk-size=$DISK_SIZE \
            --boot-disk-type=pd-ssd \
            --container-image=$CONTAINER_IMAGE \
            --container-restart-policy=always \
            --container-privileged \
            --container-tty \
            --container-command=/bin/bash \
            --container-arg="-c" \
            --container-arg="sysctl -w 'kernel.core_pattern=|/bin/false' && ./Fuzzilli --logLevel=warning --jobs=$NUM_WORKERS_PER_MACHINE --instanceType=worker --connectTo=$master_ip:1337 $FUZZILLI_WORKER_ARGS $FUZZILLI_ARGS $BINARY" \
            --no-address \
            $WORKER_INSTANCE_TYPE_FLAGS \
            --labels=container-vm=$IMAGE,role=worker,session=$SESSION

            running_instances=$(( $running_instances + $instances_to_start ))
            remaining_instances=$(( $remaining_instances - $instances_to_start ))
    done <<< "$master_ips"
fi
