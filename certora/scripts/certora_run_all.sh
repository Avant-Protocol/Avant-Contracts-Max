#!/usr/bin/env bash
# Run all RequestsManagerV2 FV specs against the Certora cloud prover.
# Requires: certora-cli==8.13.1, solc 0.8.28 active (solc-select use 0.8.28), CERTORAKEY set.
set -euo pipefail
cd "$(dirname "$0")/../.."   # repo root
for conf in \
  certora/conf/PriceStorage.conf \
  certora/conf/SimpleToken_ERC20.conf \
  certora/conf/SimpleToken_Core.conf \
  certora/conf/RMV2_Settlement.conf \
  certora/conf/RMV2_StateMachine.conf \
  certora/conf/RMV2_Structural.conf \
  certora/conf/RMV2_AccessControl.conf \
  certora/conf/RMV2_Escrow.conf \
  certora/conf/RMV2_Idempotency.conf ; do
  echo "=== submitting $conf ==="
  certoraRun "$conf" --wait_for_results all
done
