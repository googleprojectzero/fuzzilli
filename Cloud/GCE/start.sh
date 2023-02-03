#!/bin/bash
#
# Script to setup distributed fuzzing with the following hierarchy:
#   - 1 root instance. It will manage the global corpus and collect all crashes
#   - X intermedaite nodes, forming a tree such that every parent node has at most $MAX_CHILD_NODES_PER_PARENT nodes directly reporting to it
#   - $NUM_LEAF_NODES instances, running on $NUM_LEAF_NODES / $NUM_INSTANCES_PER_MACHINE machines
#
# The image below shows a simple hierarchy with only a single level of intermediate nodes. It is also possible to have no intermediate nodes
# at all (if the root can already handle all leave nodes) or multiple levels of intermediate nodes (if there are more intermediate nodes than
# the root can handle on its own).
#
#                                        +----------+
#                                        |          |
#                                        |   root   |
#                                        |          |
#                                        +-+-+----+-+
#                                          | |    |
#                           +--------------+ |    +--------------------------+
#                           |                |                               |
#                  +--------v-------+    +---v------------+         +--------v-------+
#                  |                |    |                |         |                |
#                  | intermediate 1 |    | intermediate 2 |         | intermediate N |
#                  |                |    |                |   ...   |                |
#                  +--+--+-----+----+    +----------------+         +----------------+
#                     |  |     |
#         +-----------+  |     +-----+
#         |              |           |
#    +----v---+   +------v-+     +---v----+
#    | leaf 1 |   | leaf 2 | ... | leaf M |      ....        ....        ....
#    +--------+   +--------+     +--------+
#

set -e

source config.sh

if [ $# -eq 0 ]; then
    echo "Usage: $0 [root|intermediates|leaves|all]"
    exit 1
fi

START_ROOT=false
START_INTERMEDIATES=false
START_LEAVES=false

while test $# -gt 0
do
    case "$1" in
        root)
            START_ROOT=true
            ;;
        intermediates)
            START_INTERMEDIATES=true
            ;;
        leaves)
            START_LEAVES=true
            ;;
        all)
            START_ROOT=true
            START_INTERMEDIATES=true
            START_LEAVES=true
            ;;
        *)
            echo "Usage: $0 [root|intermediates|leaves|all]"
            exit 1
            ;;
    esac
    shift
done

if (( $NUM_LEAF_NODES % $NUM_INSTANCES_PER_MACHINE != 0 )); then
    echo "[!] NUM_LEAF_NODES must be divisible by NUM_INSTANCES_PER_MACHINE"
    exit 1
fi

# Number of leaf node machines that we'll need to start, each running $NUM_INSTANCES_PER_MACHINE Fuzzilli instances
num_leave_node_machines=$(($NUM_LEAF_NODES / $NUM_INSTANCES_PER_MACHINE))

if [ "$LEAF_INSTANCE_TYPE" = "permanent" ]; then
  LEAF_INSTANCE_TYPE_FLAGS="--maintenance-policy=MIGRATE"
elif [ "$LEAF_INSTANCE_TYPE" = "preemtible" ]; then
  LEAF_INSTANCE_TYPE_FLAGS="--maintenance-policy=TERMINATE --preemptible"
else
  echo "[!] Invalid leaf instance type: $LEAF_INSTANCE_TYPE"
  exit 1
fi

# The instance hierarchy. Will contains the number of instances on every level.
hierarchy=()

# Compute the hierarchy
remaining_instances=$num_leave_node_machines
while true; do
    # Compute required number of instances on this level, rounding up if necessary
    remaining_instances=$(( ( $remaining_instances + $MAX_CHILD_NODES_PER_PARENT - 1 ) / $MAX_CHILD_NODES_PER_PARENT))

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
        --container-arg="sysctl -w 'kernel.core_pattern=|/bin/false' && ./Fuzzilli --instanceType=root --bindTo=0.0.0.0:1337 --resume --storagePath=/home/fuzzer/fuzz $FUZZILLI_ROOT_ARGS $FUZZILLI_ARGS $BINARY" \
        --container-mount-host-path=mount-path=/home/fuzzer/fuzz,host-path=/home/$USER/fuzz,mode=rw \
        --network-tier=PREMIUM \
        --maintenance-policy=MIGRATE \
        --labels=container-vm=$IMAGE,level=0,role=root,session=$SESSION
fi

if [ "$START_INTERMEDIATES" = true ]; then
    for (( level=1; level<${#hierarchy[@]}; level++ )); do
        # The hierarchy array is stored in reverse order
        idx=$(( ${#hierarchy[@]} - $level - 1 ))
        num_machines=${hierarchy[idx]}
        echo "[*] Starting $num_machines intermediate nodes for level $level"

        prev_level=$(( $level - 1 ))
        parent_ips=$(gcloud compute --project=$PROJECT_ID instances list --filter="labels.level=$prev_level && labels.session=$SESSION" --format="value(networkInterfaces[0].networkIP)")
        if [ -z "$parent_ips" ]; then
            echo "[!] Could not locate level $prev_level instances. Are they running?"
            exit 1
        fi

        running_instances=0
        remaining_instances=$num_machines
        while read -r parent_ip; do
            instances_to_start=$(( $MAX_CHILD_NODES_PER_PARENT < $remaining_instances ? $MAX_CHILD_NODES_PER_PARENT : $remaining_instances ))
            echo "[*] Starting $instances_to_start level $level nodes for level $prev_level node @ $parent_ip"

            instances=$(printf "$SESSION-intermediate-l$level-%i " $(seq $running_instances $(( $running_instances + $instances_to_start - 1 )) ))
            gcloud compute --project=$PROJECT_ID instances create-with-container $instances \
                --zone=$ZONE \
                --machine-type=$INTERMEDIATE_MACHINE_TYPE \
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
                --container-arg="sysctl -w 'kernel.core_pattern=|/bin/false' && ./Fuzzilli --instanceType=intermediate --connectTo=$parent_ip:1337 --bindTo=0.0.0.0:1337 $FUZZILLI_ARGS $FUZZILLI_INTERMEDIATE_ARGS $BINARY" \
                --network-tier=PREMIUM \
                --maintenance-policy=MIGRATE \
                --labels=container-vm=$IMAGE,level=$level,role=intermediate,session=$SESSION

            running_instances=$(( $running_instances + $instances_to_start ))
            remaining_instances=$(( $remaining_instances - $instances_to_start ))
        done <<< "$parent_ips"
    done
fi

if [ "$START_LEAVES" = true ]; then
    last_level=$(( ${#hierarchy[@]} - 1))
    parent_ips=$(gcloud compute --project=$PROJECT_ID instances list --filter="labels.level=$last_level && labels.session=$SESSION" --format="value(networkInterfaces[0].networkIP)")
    if [ -z "$parent_ips" ]; then
        echo "[!] Could not locate intermediate nodes. Are they running?"
        exit 1
    fi

    echo "[*] Starting $num_leave_node_machines ($LEAF_INSTANCE_TYPE) machines for the leaf nodes, each running $NUM_INSTANCES_PER_MACHINE Fuzzilli instances"

    running_instances=0
    remaining_instances=$num_leave_node_machines
    while read -r parent_ip; do
        instances_to_start=$(( $MAX_CHILD_NODES_PER_PARENT < $remaining_instances ? $MAX_CHILD_NODES_PER_PARENT : $remaining_instances ))
        echo "[*] Starting $instances_to_start instances for level $last_level intermediate node @ $parent_ip"

        instances=$(printf "$SESSION-leaf-%i " $(seq $running_instances $(( $running_instances + $instances_to_start - 1 )) ))
        gcloud compute --project=$PROJECT_ID instances create-with-container $instances \
            --zone=$ZONE \
            --machine-type=$LEAF_MACHINE_TYPE \
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
            --container-arg="sysctl -w 'kernel.core_pattern=|/bin/false' && ./Fuzzilli --logLevel=warning --jobs=$NUM_INSTANCES_PER_MACHINE --instanceType=leaf --connectTo=$parent_ip:1337 $FUZZILLI_LEAF_ARGS $FUZZILLI_ARGS $BINARY" \
            --no-address \
            $LEAF_INSTANCE_TYPE_FLAGS \
            --labels=container-vm=$IMAGE,role=leaf,session=$SESSION

            running_instances=$(( $running_instances + $instances_to_start ))
            remaining_instances=$(( $remaining_instances - $instances_to_start ))
    done <<< "$parent_ips"
fi
