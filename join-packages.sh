#!/bin/sh
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
cat goldilocks-monitor-linux.tar.gz.001 goldilocks-monitor-linux.tar.gz.002 > goldilocks-monitor-linux.tar.gz
sha256sum -c goldilocks-monitor-linux.tar.gz.sha256
printf '%s\n' 'Verified: goldilocks-monitor-linux.tar.gz'
