#!/bin/bash
set -euo pipefail
docker ps >/dev/null && echo "Docker OK"
