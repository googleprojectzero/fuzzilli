# Fuzzilli on Google Compute Engine

Scripts to run Fuzzilli on Google Compute Engine (GCE).

## Overview

The general instance hierarchy created by these scripts is:

                                        +----------+
                                        |          |
                                        |   root   |
                                        |          |
                                        +-+-+----+-+
                                          | |    |
                           +--------------+ |    +--------------------------+
                           |                |                               |
                  +--------v-------+    +---v------------+         +--------v-------+
                  |                |    |                |         |                |
                  | intermediate 1 |    | intermediate 2 |         | intermediate N |
                  |                |    |                |   ...   |                |
                  +--+--+-----+----+    +----------------+         +----------------+
                     |  |     |
         +-----------+  |     +-----+
         |              |           |
    +----v---+   +------v-+     +---v----+
    | leaf 1 |   | leaf 2 | ... | leaf M |      ....        ....        ....
    +--------+   +--------+     +--------+

Here, an edge from A to B indicates that A is a network parent node and B is connected to it as a child node, meaning that A and B synchronize their corpuses (by sending newly added samples to the other side) while newly found crashes (and fuzzing statistics) are only sent from the child to the parent. With that, the root then manages the global corpus, receiving and sharing newly found samples that increase coverage. It also receives all crashing files and stores them to disk.

The [start.sh](./start.sh) script automatically computes the necessary number of levels such that a parent node never has more than a certain number of child nodes.

## Quickstart

1. [Create a GCP project](https://cloud.google.com/resource-manager/docs/creating-managing-projects)
2. [Install](https://cloud.google.com/sdk/install) and [configure](https://cloud.google.com/sdk/docs/initializing) the [Google Cloud SDK](https://cloud.google.com/sdk)
3. Create config based on [config-template.sh](./config-template.sh): `cp config-template.sh config.sh` and insert the GCP Project ID and Number and potentially modify other configuration options, such as the [GCE region](https://cloud.google.com/compute/docs/regions-zones), as well
4. [Enable Private Google Access](https://cloud.google.com/vpc/docs/configure-private-google-access#enabling-pga) for the default subnet in the selected region. This is necessary so that leaf nodes without a public IP address can access the project's docker registry
5. [Enable the Container Registry API](https://cloud.google.com/container-registry/docs/quickstart) and [configure docker for access to the GCE docker registry](https://cloud.google.com/container-registry/docs/quickstart#add_the_image_to)
6. Optionally [request a quota increase](https://cloud.google.com/compute/quotas) for the number of CPUS in the selected region. The default is 72
7. Build the fuzzilli docker container. See [Docker/](../Docker)
8. Push it to GCE: `./push.sh`
9. Start fuzzing! `./start.sh all` :)

To stop fuzzing, simply run `./stop.sh all`, but be sure to fetch all crashes first!

## Collecting Crashes

The root instance collects crashes from all instances in a session and stores them to disk. As such, the crash files can for example be downloaded with these commands:

    NAME=$SESSION-root
    gcloud compute ssh $NAME --command "cd ~/fuzz/ && sudo tar czf ~/crashes.tgz crashes"
    gcloud compute scp $NAME:/home/$USER/crashes.tgz .
    tar xzf ./crashes.tgz && rm crashes.tgz

Also see the [Triage/](../Triage) directory for what to do next :)

## Attaching to the Cloud Instances

It's possible to attach to a running Fuzzilli session (to for example see fuzzing statistics) as follows:

    gcloud compute ssh $SESSION-root

    # Now on the GCE instance
    docker ps       # Copy the container name

    # Disable the sig proxy so ctrl-c detaches and doesn't stop Fuzzilli
    docker attach --sig-proxy=false $CONTAINER
