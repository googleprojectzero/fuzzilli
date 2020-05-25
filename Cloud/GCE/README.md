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
                           +--------------+ |    +-----------------------------+
                           |                |                                  |
                     +-----v----+           |     +----------+           +-----v----+
                     |          |           |     |          |           |          |
                     | master 1 |           +-----> master 2 |           | master N |
                     |          |                 |          |    ...    |          |
                     +-+-+----+-+                 +----------+           +----------+
                       | |    |
           +-----------+ |    +---------+
           |             |              |
    +------v---+ +-------v--+     +-----v----+
    | worker 1 | | worker 2 | ... | worker M |        ....        ....        ....
    +----------+ +----------+     +----------+

Here, an edge from A to B indicates that A is a network master instance and B is connected to it as a network worker, meaning that A and B synchronize their corpuses (by sending newly added samples to the other side) while newly found crashes (and fuzzing statistics) are only sent from the worker to the master. With that, the root then manages the global corpus, receiving and sharing newly found samples that increase coverage. It also receives all crashing files and stores them to disk.

If the workload ever becomes too large for a network master instance, further levels can easily be added to the hierarchy.

## Quickstart

1. [Create a GCP project](https://cloud.google.com/resource-manager/docs/creating-managing-projects) and optionally request quota increases (e.g. increase the maximum number of GCE instances)
2. [Enable Private Google Access](https://cloud.google.com/vpc/docs/configure-private-google-access#configuring_access_to_google_services_from_internal_ips) for the default subnet in the [active region](https://cloud.google.com/compute/docs/regions-zones) (see [config.sh](./config.sh)) in the new project. This is necessary so that worker instances without a public IP address can access the project's docker registry
3. Install and configure the [Google Cloud SDK](https://cloud.google.com/sdk)
4. Edit [config.sh](./config.sh): insert the GCP Project ID and Number and potentially modify other configuration options as well
5. Build the fuzzilli docker container. See [Docker/](../Docker)
6. Push it to GCE: `./push.sh`
7. Start fuzzing! `./start.sh all` :)

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
