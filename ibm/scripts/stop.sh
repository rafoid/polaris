#!/usr/bin/bash

cd /work/repos/polaris_1.2
python3.11 -m podman_compose -f getting-started/minio/docker-compose.yml down
