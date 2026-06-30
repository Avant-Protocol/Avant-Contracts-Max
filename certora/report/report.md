---
title: "Formal Verification Report"
project: "Avant RequestManagerV2"
subtitle: "Cyfrin Audit External"
author: "Julius Raynaldi"
date: "June 2026"
twitterhandle: https://x.com/JuliusRaynaldi
auditrepo: https://github.com/Cyfrin/audit-2026-06-avant-requestmanagerv2
clientrepo: https://github.com/Avant-Protocol/Avant-Contracts-Max
auditcommit: "0738f33ebc960522187546446e62e7037413abbc"
mitigationcommit: "ec30a6ccba0def3e745b8c5ffb474cef39c45c90"
proverversion: "8.16.1"
---

# Project Summary 

## Project Scope
This document describes the specification and verification of Avant RequestManagerV2 using the Certora Prover.
The work was undertaken from **June 14th 2026** to **June 19th 2026**.

The following contract list is included in our scope:

```solidity
- src/RequestsManagerV2.sol
- src/interfaces/IRequestsManagerV2.sol
- src/PriceStorage.sol
- src/SimpleToken.sol
- src/interfaces/ISimpleToken.sol
- src/interfaces/IPriceStorage.sol
```

The Certora Prover demonstrated that the implementation of the Solidity contracts above is correct with
respect to the formal rules written by **Julius Raynaldi** \href{https://x.com/JuliusRaynaldi}{(@JuliusRaynaldi)}.

### Protocol Overview
The protocol implements a token minting and burning system that bridges external assets into wrapped versions
through a request-based mechanism. At its core, RequestsManager serves as the central orchestrator, accepting
deposits of whitelisted tokens from approved providers who request minting of the wrapped token. These requests
enter a pending state until a designated service role completes them with the final mint amount, which may be
greater but not lesser than the requested amount due to exchange rates.

The system works bidirectionally - users can also burn their wrapped tokens to request redemption of the un-
derlying assets, following the same request-complete pattern. The treasury address receives deposited tokens
from completed mints and provides tokens for burns, maintaining clear fund flow separation from the operational
contracts.

The architecture employs several supporting contracts to ensure operational security and flexibility:

• SimpleToken provides the ERC20 implementation with idempotent mint/burn functions that prevent double-
processing through unique keys

• AddressesWhitelist maintains an optional KYC layer, allowing the protocol to restrict participation to verified
addresses when regulatory compliance is required

• PriceStorage implements a price oracle system with configurable bounds checking, preventing extreme
price movements between updates by enforcing upper and lower percentage limits on consecutive price
changes


## Finding Summary
| Severity          | Discovered | Confirmed | Fixed |
|-------------------|------------|-----------|-------|
| **Critical**      | 0          | 0         | 0     |
| **High**          | 0          | 0         | 0     |
| **Medium**        | 0          | 0         | 0     |
| **Low**           | 1          | 1         | 0     |
| **Informational** | 0          | 0         | 0     |
| **Total**         | **1**     | **1**     | **0** |



\pagebreak

# Detailed Findings

## Low Severity

``` {.include}
findings/low/LOW-1.md
```

\pagebreak

# Formal Verification

## Formal Verification Methodology

Formal verification was used to reason about the `RequestsManagerV2`, `SimpleToken`, and `PriceStorage` contracts against explicitly written correctness properties. Rather than exercising a selected set of examples, as in unit tests or fuzz tests, the Certora Prover analyzes the compiled contracts symbolically and checks whether the specified properties hold for all relevant inputs, callers, contract states, and execution paths within the verification model.

The specifications were written in CVL, the Certora Verification Language. Each CVL rule captures an expected protocol guarantee, such as preserving escrow accounting invariants, enforcing role-based access control, respecting the three-state request lifecycle, or rejecting invalid settlement inputs.

The Solidity contracts, harnesses, and CVL specifications are then submitted to the prover, which translates them into logical constraints and attempts to either prove the property or produce a counterexample showing how it can be violated. This methodology complements testing by covering broad state spaces that are difficult to enumerate manually. Tests are useful for concrete scenarios and integration behavior, while formal verification is used here to check general safety properties across the protocol's critical flows.

### Types of Properties

**Valid State:** invariants and global correctness conditions that should hold across all reachable states.

**Variable Transition:** rules proving that selected state variables change only in expected ways.

**State Transition:** authorization, gating, and lifecycle transition properties.

**High-Level:** end-to-end economic and business-logic properties.

**Unit / Liveness:** reachability and model sanity checks.

**Negative / Anti-Property:** offensive witnesses or expected-failure checks documenting what must not be assumed.

## Verification Notations

\renewcommand{\arraystretch}{1.4}
\begin{table}[h]
\centering
\begin{tabularx}{\textwidth}{|X|X|}
\hline

\rowcolor[HTML]{E6E6E6}
Notation  & Description  \\ \hline
\cellcolor{green!30}{$\checkmark$}  & The rule is verified for every state of the contract(s), under the assumptions of the scope/requirements in the rule.  \\ \hline
\cellcolor{red!30}{$\times$}  & A counter-example exists that violates one of the assertions of the rule. \\ \hline
\end{tabularx}
\end{table}


## General Assumptions and Simplifications

- We used Solidity Compiler version 0.8.28 to verify the protocol, without using the solc optimizer and without via-ir.
- `PRICE_STORAGE.lastPrice()` is summarized by a CVL ghost returning a symbolic `(price, timestamp)` pair. Price is treated as a free symbolic value; oracle staleness and price-update ordering are not checked (F-01 carve-out).
- `EIP-2612 permit` calls are summarized as `NONDET` to allow `requestMintWithPermit`/`requestBurnWithPermit` to reach a success path without modeling `ecrecover` signature verification.
- `SafeERC20.safeTransfer` and `safeTransferFrom` are summarized by CVL dispatch functions that route to the concrete linked token contracts (`SimpleTokenHarness`, `DummyERC20Permit`, `DummyERC20A`), keeping all token storage on real OZ storage and preventing unintended HAVOC 
- Linked token contracts are modeled as standard 18-decimal, non-fee-on-transfer ERC-20s. Fee-on-transfer, rebase, and other non-standard behaviors are not verified.
- `emergencyWithdraw` solvency is not asserted. Only state-inertness is verified.
- Loop iterations are bounded at 2 (`optimistic_loop`, `loop_iter = 2`). Hashing is bounded at 128 bytes (`optimistic_hashing`, `hashing_length_bound = 128`).
- `SimpleToken.initialize(string,string)` is excluded from parametric rules in all SimpleToken specs; initialization correctness is verified separately via `ST-CORE-27`/`ST-CORE-28`.

## Verification Properties


``` {.include}
properties/RMV2_AccessControl.md
properties/RMV2_Idempotency.md
properties/RMV2_Escrow.md
properties/RMV2_StateMachine.md
properties/RMV2_Structural.md
properties/RMV2_Settlement.md
properties/SimpleToken_Core.md
properties/SimpleToken_ERC20.md
properties/PriceStorage.md
```


\pagebreak

\addtocontents{toc}{\protect\setcounter{tocdepth}{1}}

# Setup and Executions

The Certora Prover can be run remotely using Certora's cloud infrastructure or locally from a source build. For this engagement, the report metadata records Certora Prover version **8.16.1**. The commands below assume you are inside the repository root, where `certora/` is a direct child. No source code modification is required — all external calls and complex internals are handled through CVL summaries and ghost-based modeling within the spec files.

## Common Setup

The first four steps are shared by remote and local execution.

**Recommended:** Use a Python virtual environment to isolate Certora dependencies from your system Python.
```bash
python3 -m venv .venv
source .venv/bin/activate
```
All subsequent `pip`/`pipx` installs should be run inside this environment.

### Step 1 - Install Java (JDK 21)

```bash
sudo apt update
sudo apt install -y openjdk-21-jdk
java -version
```

### Step 2 - Install pipx

pipx installs Python CLI tools in isolated environments, which keeps Certora dependencies separate from the repo's Python packages. See the [pipx documentation](https://pipx.pypa.io) for platform-specific notes.

```bash
sudo apt install -y pipx
pipx ensurepath
exec "$SHELL"
```

### Step 3 - Install the Certora CLI

```bash
pipx install certora-cli==8.16.1
certoraRun --version
```

### Step 4 - Install the Solidity Compiler

```bash
pipx install solc-select
solc-select install 0.8.28
solc-select use 0.8.28
solc --version
```

## Remote Execution

A Certora key is required for cloud runs. Certora provides keys through its [Discord](https://discord.gg/certora) and website.

```bash
echo "export CERTORAKEY=<your_certora_api_key>" >> ~/.bashrc
source ~/.bashrc
```

Run a configuration against the cloud backend:

```bash
certoraRun certora/conf/RMV2_Escrow.conf --server production
```

## Local Execution

For a local build matching this engagement, follow the [CertoraProver repository](https://github.com/Certora/CertoraProver). Once installed, the local Prover is used before the cloud backend unless `--server production` is passed.

### Install Local-Prover Prerequisites

```bash
# JDK 21
sudo apt install -y openjdk-21-jdk

# SMT solvers: z3 and cvc5 are required; place their binaries on PATH.
# z3:   https://github.com/Z3Prover/z3/releases
# cvc5: https://github.com/cvc5/cvc5/releases

# LLVM tools
sudo apt install -y llvm

# Rust 1.81.0+
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
cargo install rustfilt

# Optional, for visual reports
sudo apt install -y graphviz
```

### Build CertoraProver v8.16.1

```bash
export CERTORA="$HOME/CertoraProver/target/installed/"
mkdir -p "$CERTORA"
export PATH="$CERTORA:$PATH"

git clone --recurse-submodules https://github.com/Certora/CertoraProver.git
cd CertoraProver
git checkout tags/8.16.1
./gradlew assemble
```

### Verify the Local Installation

```bash
certoraRun.py -h
cd Public/TestEVM/Counter
certoraRun counter.conf
```

## Running Avant RequestManagerV2 Verification

The verification suite is organized based on the contract they verify. All configuration files can be found in `certora/conf`.

### Project Structure

```solidity
certora/
├── conf/                           # Certora configuration files
│   ├── PriceStorage.conf
│   ├── RMV2_AccessControl.conf
│   ├── RMV2_Escrow.conf
│   ├── RMV2_Idempotency.conf
│   ├── RMV2_Settlement.conf
│   ├── RMV2_StateMachine.conf
│   ├── RMV2_Structural.conf
│   ├── SimpleToken_Core.conf
│   └── SimpleToken_ERC20.conf
├── harness/                        # Harness contracts exposing internal state
│   ├── DummyERC20A.sol
│   ├── DummyERC20.sol
│   ├── DummyERC20Permit.sol
│   ├── PriceStorageHarness.sol
│   ├── RequestsManagerV2Harness.sol
│   └── SimpleTokenHarness.sol
└── specs/                          # CVL specification files
    ├── PriceStorage.spec
    ├── RMV2_AccessControl.spec
    ├── RMV2_Escrow.spec
    ├── RMV2_Idempotency.spec
    ├── RMV2_Settlement.spec
    ├── RMV2_StateMachine.spec
    ├── RMV2_Structural.spec
    ├── SimpleToken_Core.spec
    ├── SimpleToken_ERC20.spec
    └── utils/
        └── RMV2_Base.spec          # Shared ghosts, hooks, and helpers
```

Run the commands below from the repository root.

### Run the Full Suite

```bash
chmod +x certora/scripts/certora_run_all.sh
bash certora/scripts/certora_run_all.sh
```

### Run All Configurations

```bash
certoraRun certora/conf/<config>.conf
```

For example:

```bash
# RequestsManagerV2
certoraRun certora/conf/RMV2_AccessControl.conf
certoraRun certora/conf/RMV2_Idempotency.conf
certoraRun certora/conf/RMV2_Escrow.conf
certoraRun certora/conf/RMV2_StateMachine.conf
certoraRun certora/conf/RMV2_Structural.conf
certoraRun certora/conf/RMV2_Settlement.conf

# SimpleToken
certoraRun certora/conf/SimpleToken_Core.conf
certoraRun certora/conf/SimpleToken_ERC20.conf

# PriceStorage
certoraRun certora/conf/PriceStorage.conf
```

### Run One Rule While Debugging

```bash
certoraRun certora/conf/<config>.conf --rule <ruleName>
```

For example:

```bash
certoraRun certora/conf/RMV2_Escrow.conf --rule mintEscrowBacked
certoraRun certora/conf/RMV2_StateMachine.conf --rule mintTerminalAbsorption
certoraRun certora/conf/RMV2_AccessControl.conf --rule onlyAdminCanPause
```

### Compilation-Only Checks

Use compilation-only checks before long runs or after touching imports, summaries, harnesses, or config paths.

```bash
certoraRun certora/conf/<config>.conf --compilation_steps_only
```

For example:

```bash
certoraRun certora/conf/RMV2_Escrow.conf --compilation_steps_only
certoraRun certora/conf/RMV2_AccessControl.conf --compilation_steps_only
certoraRun certora/conf/PriceStorage.conf --compilation_steps_only
```

\addtocontents{toc}{\protect\setcounter{tocdepth}{3}}

# Resources

To learn more about Certora formal verification, the resources below are useful for onboarding, writing stronger CVL properties, and debugging prover behavior.

- [Updraft Assembly & Formal Verification Course](https://updraft.cyfrin.io/courses/formal-verification) - Comprehensive video course covering assembly and formal verification from the ground up.
- [RareSkills Certora Book](https://rareskills.io/post/certora-formal-verification-intro) - Structured tutorial covering CVL syntax, specification patterns, and common pitfalls.
- [Certora Tutorials](https://docs.certora.com/projects/tutorials/en/latest/) - Official Certora tutorials for guided Prover, CVL, config, invariant, and debugging workflows.
- [Certora Prover Documentation](https://docs.certora.com/en/latest/) - Official Prover reference covering installation, CLI options, CVL, approximations, reports, and dashboard usage.

\pagebreak

# Disclaimer 

This report reflects the results of a formal verification effort performed on a specific version of the codebase provided by the client. Formal verification increases confidence in the correctness of smart-contract behavior with respect to the specified rules; however, **it cannot guarantee the complete absence of bugs, vulnerabilities, or unexpected behavior.**

This document does not constitute legal, financial, or investment advice. The authors and reviewers assume no liability for the use of the verified smart contracts in production or for any losses arising from their deployment or interaction.