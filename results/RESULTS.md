# Distributed process registry evaluation

A three node Erlang cluster in docker. The network between the nodes is cut and healed with iptables while a fixed list of actions is run against each registry, and every answer every node gives is written down.

Registries in this run: global, gproc, syn, locker. Produced by `./run.sh`; nothing in this file is written by hand.

## Environment

| Setting | global | gproc | syn | locker |
| --- | --- | --- | --- | --- |
| run started | 2026-08-09T21:23:39Z | 2026-08-09T21:26:25Z | 2026-08-09T21:29:03Z | 2026-08-09T21:36:52Z |
| OTP release | 27 | 27 | 27 | 27 |
| net_ticktime | 5 | 5 | 5 | 5 |
| kernel prevent_overlapping_partitions | true | true | true | true |
| registry version | kernel 10.2.7.4 | gproc 1.3.0 | syn 3.4.2 | locker 6 |
| settle after network change | 15000 | 15000 | 15000 | 15000 |
| default lease | 60000 | 60000 | 60000 | 60000 |
| action timeout | 20000 | 20000 | 20000 | 20000 |

## Summary

Every `lookup on all nodes` step asks all three nodes who owns the name and compares the answers. `agree n/m` counts how many of those checks got the same answer from every node. `owners` is the highest number of different owners seen at the same time, so more than one means the cluster had a split brain.

| Scenario | global | gproc | syn | locker |
| --- | --- | --- | --- | --- |
| baseline | agree 3/3, 1 owner, 1 refused | agree 3/3, 1 owner, 1 refused | agree 3/3, 1 owner, 1 refused | agree 3/3, 1 owner, 1 refused |
| process death | agree 3/3, 1 owner | agree 3/3, 1 owner | agree 3/3, 1 owner | agree 3/3, 1 owner, 1 refused |
| lease expiry | agree 3/3, 1 owner, 1 refused | agree 3/3, 1 owner, 1 refused | agree 3/3, 1 owner, 1 refused | agree 3/3, 1 owner |
| symmetric split | agree 2/4, 2 owners | agree 2/4, 2 owners | agree 2/4, 2 owners | agree 4/4, 1 owner, 1 refused |
| owner isolated | agree 2/4, 2 owners | agree 2/4, 2 owners | agree 2/4, 2 owners | agree 4/4, 1 owner, 1 refused |
| one sided split | agree 2/4, 2 owners | agree 1/4, 2 owners | agree 2/4, 2 owners | agree 4/4, 1 owner, 1 refused |
| full split | agree 2/4, 3 owners | agree 2/4, 3 owners | agree 2/4, 3 owners | agree 4/4, 1 owner, 2 refused |

## Observations

| Question | global | gproc | syn | locker |
| --- | --- | --- | --- | --- |
| Are leases supported? | no | no | no | yes |
| Slowest single action | 8ms | 4469ms | 8ms | 7014ms |
| Claims the registry refused | 2 | 2 | 2 | 7 |
| Actions that timed out or crashed | 0 | 0 | 0 | 0 |
| Checks where the nodes disagreed | 8 | 9 | 8 | 0 |
| Highest number of owners at the same time | 3 | 3 | 3 | 1 |

## Actions

| Action | What it does |
| --- | --- |
| `start_process` | start a process and register it |
| `lookup` | look up which process owns the name |
| `stop_process` | unregister the name and stop the process |
| `kill_process` | kill the process without unregistering |
| `renew_lease` | renew the lease on the name |

## Details

### global

#### baseline

Healthy cluster. Establishes what the registry does when nothing is wrong: a name is visible everywhere, a second claim is refused, and the name is free again after an orderly stop.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (baseline/service) | started `node1/341be1` |  |  |
| 2 | `lookup` on all nodes (baseline/service) - **agree** | `node1/341be1` | `node1/341be1` | `node1/341be1` |
| 3 | _A second node claims the same name._ |  |  |  |
| 4 | `start_process` on n2 (baseline/service) |  | error: `name_taken` |  |
| 5 | `lookup` on all nodes (baseline/service) - **agree** | `node1/341be1` | `node1/341be1` | `node1/341be1` |
| 6 | `renew_lease` on n2 (baseline/service) |  | `not_supported` |  |
| 7 | `stop_process` on n1 (baseline/service) | `stopped` |  |  |
| 8 | `lookup` on all nodes (baseline/service) - **agree** | `not_found` | `not_found` | `not_found` |

#### process death

The registered process is killed without unregistering. Shows whether the registry monitors the process and frees the name by itself, or keeps handing out a dead pid.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (process_death/service) | started `node1/e019d8` |  |  |
| 2 | `lookup` on all nodes (process_death/service) - **agree** | `node1/e019d8` | `node1/e019d8` | `node1/e019d8` |
| 3 | `kill_process` on n1 (process_death/service) | `killed` |  |  |
| 4 | wait 2000ms |  |  |  |
| 5 | `lookup` on all nodes (process_death/service) - **agree** | `not_found` | `not_found` | `not_found` |
| 6 | _Another node tries to take the name over._ |  |  |  |
| 7 | `start_process` on n2 (process_death/service) |  | started `node2/c0a1eb` |  |
| 8 | `lookup` on all nodes (process_death/service) - **agree** | `node2/c0a1eb` | `node2/c0a1eb` | `node2/c0a1eb` |

#### lease expiry

The lease is shortened to 3s and then nobody renews it. Registries without leases keep the name forever; a lease based registry drops it and lets another node take over.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | set lease_ms to 3000 |  |  |  |
| 2 | `start_process` on n1 (lease_expiry/service) | started `node1/431ca0` |  |  |
| 3 | `lookup` on all nodes (lease_expiry/service) - **agree** | `node1/431ca0` | `node1/431ca0` | `node1/431ca0` |
| 4 | `renew_lease` on n1 (lease_expiry/service) | `not_supported` |  |  |
| 5 | _Wait past the lease without renewing._ |  |  |  |
| 6 | wait 6000ms |  |  |  |
| 7 | `lookup` on all nodes (lease_expiry/service) - **agree** | `node1/431ca0` | `node1/431ca0` | `node1/431ca0` |
| 8 | _Another node tries to take the name over._ |  |  |  |
| 9 | `start_process` on n2 (lease_expiry/service) |  | error: `name_taken` |  |
| 10 | `lookup` on all nodes (lease_expiry/service) - **agree** | `node1/431ca0` | `node1/431ca0` | `node1/431ca0` |

#### symmetric split

The cluster splits into a majority (n1, n2) and a minority (n3). The owner is on the majority side. The minority tries to claim the same name, then the split is healed.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (symmetric_split/service) | started `node1/75e17c` |  |  |
| 2 | `lookup` on all nodes (symmetric_split/service) - **agree** | `node1/75e17c` | `node1/75e17c` | `node1/75e17c` |
| 3 | **isolate n3** |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (symmetric_split/service) - **disagree** | `node1/75e17c` | `node1/75e17c` | `not_found` |
| 6 | _The minority side claims the same name._ |  |  |  |
| 7 | `start_process` on n3 (symmetric_split/service) |  |  | started `node3/8948b6` |
| 8 | `lookup` on all nodes (symmetric_split/service) - **disagree** | `node1/75e17c` | `node1/75e17c` | `node3/8948b6` |
| 9 | `renew_lease` on n1 (symmetric_split/service) | `not_supported` |  |  |
| 10 | **heal the network** |  |  |  |
| 11 | wait 15000ms for the registry to react |  |  |  |
| 12 | _After healing: does the cluster agree again?_ |  |  |  |
| 13 | `lookup` on all nodes (symmetric_split/service) - **agree** | `node1/75e17c` | `node1/75e17c` | `node1/75e17c` |

#### owner isolated

The node owning the name (n3) is cut off from the majority. This is the failover case: can the majority take the name over, and what happens to the old owner when the split heals?

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n3 (owner_isolated/service) |  |  | started `node3/57bde7` |
| 2 | `lookup` on all nodes (owner_isolated/service) - **agree** | `node3/57bde7` | `node3/57bde7` | `node3/57bde7` |
| 3 | **isolate n3** |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (owner_isolated/service) - **disagree** | `not_found` | `not_found` | `node3/57bde7` |
| 6 | _The majority side tries to take the name over._ |  |  |  |
| 7 | `start_process` on n1 (owner_isolated/service) | started `node1/18198e` |  |  |
| 8 | `lookup` on all nodes (owner_isolated/service) - **disagree** | `node1/18198e` | `node1/18198e` | `node3/57bde7` |
| 9 | **heal the network** |  |  |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | _After healing: one owner, or two?_ |  |  |  |
| 12 | `lookup` on all nodes (owner_isolated/service) - **agree** | `node1/18198e` | `node1/18198e` | `node1/18198e` |

#### one sided split

n1 stops hearing from n3, but n3 still hears n1. The two nodes disagree about whether the other one is alive, which is the case that breaks membership algorithms assuming symmetric failures.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (one_sided_split/service) | started `node1/344333` |  |  |
| 2 | `lookup` on all nodes (one_sided_split/service) - **agree** | `node1/344333` | `node1/344333` | `node1/344333` |
| 3 | **cut n1 <- n3** (one sided: n3 still hears n1) |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (one_sided_split/service) - **disagree** | `node1/344333` | `not_found` | `not_found` |
| 6 | _n3 claims the same name while it still believes n1 is up._ |  |  |  |
| 7 | `start_process` on n3 (one_sided_split/service) |  |  | started `node3/344333` |
| 8 | `lookup` on all nodes (one_sided_split/service) - **disagree** | `node1/344333` | `node3/344333` | `node3/344333` |
| 9 | **heal the network** |  |  |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | `lookup` on all nodes (one_sided_split/service) - **agree** | `node1/344333` | `node1/344333` | `node1/344333` |

#### full split

Every node is cut off from every other node, so nobody has a majority. All three then try to own the same name at the same time, and the split is healed with three candidate owners.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (full_split/service) | started `node1/8aae17` |  |  |
| 2 | `lookup` on all nodes (full_split/service) - **agree** | `node1/8aae17` | `node1/8aae17` | `node1/8aae17` |
| 3 | **cut n1 <-> n2** |  |  |  |
| 4 | **cut n1 <-> n3** |  |  |  |
| 5 | **cut n2 <-> n3** |  |  |  |
| 6 | wait 15000ms for the registry to react |  |  |  |
| 7 | `lookup` on all nodes (full_split/service) - **disagree** | `node1/8aae17` | `not_found` | `not_found` |
| 8 | _Both other nodes claim the name as well._ |  |  |  |
| 9 | `start_process` on n2 (full_split/service) |  | started `node2/046225` |  |
| 10 | `start_process` on n3 (full_split/service) |  |  | started `node3/523f22` |
| 11 | `lookup` on all nodes (full_split/service) - **disagree** | `node1/8aae17` | `node2/046225` | `node3/523f22` |
| 12 | **heal the network** |  |  |  |
| 13 | wait 15000ms for the registry to react |  |  |  |
| 14 | _After healing: how many owners survive?_ |  |  |  |
| 15 | `lookup` on all nodes (full_split/service) - **agree** | `node1/8aae17` | `node1/8aae17` | `node1/8aae17` |

### gproc

#### baseline

Healthy cluster. Establishes what the registry does when nothing is wrong: a name is visible everywhere, a second claim is refused, and the name is free again after an orderly stop.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (baseline/service) | started `node1/3c9315` |  |  |
| 2 | `lookup` on all nodes (baseline/service) - **agree** | `node1/3c9315` | `node1/3c9315` | `node1/3c9315` |
| 3 | _A second node claims the same name._ |  |  |  |
| 4 | `start_process` on n2 (baseline/service) |  | error: `badarg` |  |
| 5 | `lookup` on all nodes (baseline/service) - **agree** | `node1/3c9315` | `node1/3c9315` | `node1/3c9315` |
| 6 | `renew_lease` on n2 (baseline/service) |  | `not_supported` |  |
| 7 | `stop_process` on n1 (baseline/service) | `stopped` |  |  |
| 8 | `lookup` on all nodes (baseline/service) - **agree** | `not_found` | `not_found` | `not_found` |

#### process death

The registered process is killed without unregistering. Shows whether the registry monitors the process and frees the name by itself, or keeps handing out a dead pid.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (process_death/service) | started `node1/5e75ec` |  |  |
| 2 | `lookup` on all nodes (process_death/service) - **agree** | `node1/5e75ec` | `node1/5e75ec` | `node1/5e75ec` |
| 3 | `kill_process` on n1 (process_death/service) | `killed` |  |  |
| 4 | wait 2000ms |  |  |  |
| 5 | `lookup` on all nodes (process_death/service) - **agree** | `not_found` | `not_found` | `not_found` |
| 6 | _Another node tries to take the name over._ |  |  |  |
| 7 | `start_process` on n2 (process_death/service) |  | started `node2/27d283` |  |
| 8 | `lookup` on all nodes (process_death/service) - **agree** | `node2/27d283` | `node2/27d283` | `node2/27d283` |

#### lease expiry

The lease is shortened to 3s and then nobody renews it. Registries without leases keep the name forever; a lease based registry drops it and lets another node take over.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | set lease_ms to 3000 |  |  |  |
| 2 | `start_process` on n1 (lease_expiry/service) | started `node1/b471f1` |  |  |
| 3 | `lookup` on all nodes (lease_expiry/service) - **agree** | `node1/b471f1` | `node1/b471f1` | `node1/b471f1` |
| 4 | `renew_lease` on n1 (lease_expiry/service) | `not_supported` |  |  |
| 5 | _Wait past the lease without renewing._ |  |  |  |
| 6 | wait 6000ms |  |  |  |
| 7 | `lookup` on all nodes (lease_expiry/service) - **agree** | `node1/b471f1` | `node1/b471f1` | `node1/b471f1` |
| 8 | _Another node tries to take the name over._ |  |  |  |
| 9 | `start_process` on n2 (lease_expiry/service) |  | error: `badarg` |  |
| 10 | `lookup` on all nodes (lease_expiry/service) - **agree** | `node1/b471f1` | `node1/b471f1` | `node1/b471f1` |

#### symmetric split

The cluster splits into a majority (n1, n2) and a minority (n3). The owner is on the majority side. The minority tries to claim the same name, then the split is healed.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (symmetric_split/service) | started `node1/b712ba` |  |  |
| 2 | `lookup` on all nodes (symmetric_split/service) - **agree** | `node1/b712ba` | `node1/b712ba` | `node1/b712ba` |
| 3 | **isolate n3** |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (symmetric_split/service) - **disagree** | `node1/b712ba` | `node1/b712ba` | `not_found` |
| 6 | _The minority side claims the same name._ |  |  |  |
| 7 | `start_process` on n3 (symmetric_split/service) |  |  | started `node3/199bda` |
| 8 | `lookup` on all nodes (symmetric_split/service) - **disagree** | `node1/b712ba` | `node1/b712ba` | `node3/199bda` |
| 9 | `renew_lease` on n1 (symmetric_split/service) | `not_supported` |  |  |
| 10 | **heal the network** |  |  |  |
| 11 | wait 15000ms for the registry to react |  |  |  |
| 12 | _After healing: does the cluster agree again?_ |  |  |  |
| 13 | `lookup` on all nodes (symmetric_split/service) - **agree** | `node3/199bda` | `node3/199bda` | `node3/199bda` |

#### owner isolated

The node owning the name (n3) is cut off from the majority. This is the failover case: can the majority take the name over, and what happens to the old owner when the split heals?

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n3 (owner_isolated/service) |  |  | started `node3/e2db96` |
| 2 | `lookup` on all nodes (owner_isolated/service) - **agree** | `node3/e2db96` | `node3/e2db96` | `node3/e2db96` |
| 3 | **isolate n3** |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (owner_isolated/service) - **disagree** | `not_found` | `not_found` | `node3/e2db96` |
| 6 | _The majority side tries to take the name over._ |  |  |  |
| 7 | `start_process` on n1 (owner_isolated/service) | started `node1/af7c78` |  |  |
| 8 | `lookup` on all nodes (owner_isolated/service) - **disagree** | `node1/af7c78` | `node1/af7c78` | `node3/e2db96` |
| 9 | **heal the network** |  |  |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | _After healing: one owner, or two?_ |  |  |  |
| 12 | `lookup` on all nodes (owner_isolated/service) - **agree** | `node3/e2db96` | `node3/e2db96` | `node3/e2db96` |

#### one sided split

n1 stops hearing from n3, but n3 still hears n1. The two nodes disagree about whether the other one is alive, which is the case that breaks membership algorithms assuming symmetric failures.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (one_sided_split/service) | started `node1/16255b` |  |  |
| 2 | `lookup` on all nodes (one_sided_split/service) - **disagree** | `node1/16255b` | `not_found` | `node1/16255b` |
| 3 | **cut n1 <- n3** (one sided: n3 still hears n1) |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (one_sided_split/service) - **disagree** | `node1/16255b` | `node1/16255b` | `not_found` |
| 6 | _n3 claims the same name while it still believes n1 is up._ |  |  |  |
| 7 | `start_process` on n3 (one_sided_split/service) |  |  | started `node3/942bb9` |
| 8 | `lookup` on all nodes (one_sided_split/service) - **disagree** | `node1/16255b` | `node3/942bb9` | `node3/942bb9` |
| 9 | **heal the network** |  |  |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | `lookup` on all nodes (one_sided_split/service) - **agree** | `node3/942bb9` | `node3/942bb9` | `node3/942bb9` |

#### full split

Every node is cut off from every other node, so nobody has a majority. All three then try to own the same name at the same time, and the split is healed with three candidate owners.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (full_split/service) | started `node1/8bf374` |  |  |
| 2 | `lookup` on all nodes (full_split/service) - **agree** | `node1/8bf374` | `node1/8bf374` | `node1/8bf374` |
| 3 | **cut n1 <-> n2** |  |  |  |
| 4 | **cut n1 <-> n3** |  |  |  |
| 5 | **cut n2 <-> n3** |  |  |  |
| 6 | wait 15000ms for the registry to react |  |  |  |
| 7 | `lookup` on all nodes (full_split/service) - **disagree** | `node1/8bf374` | `node1/8bf374` | `not_found` |
| 8 | _Both other nodes claim the name as well._ |  |  |  |
| 9 | `start_process` on n2 (full_split/service) |  | started `node2/f6ce6e` _(4469ms)_ |  |
| 10 | `start_process` on n3 (full_split/service) |  |  | started `node3/607b2e` |
| 11 | `lookup` on all nodes (full_split/service) - **disagree** | `node1/8bf374` | `node2/f6ce6e` | `node3/607b2e` |
| 12 | **heal the network** |  |  |  |
| 13 | wait 15000ms for the registry to react |  |  |  |
| 14 | _After healing: how many owners survive?_ |  |  |  |
| 15 | `lookup` on all nodes (full_split/service) - **agree** | `node3/607b2e` | `node3/607b2e` | `node3/607b2e` |

### syn

#### baseline

Healthy cluster. Establishes what the registry does when nothing is wrong: a name is visible everywhere, a second claim is refused, and the name is free again after an orderly stop.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (baseline/service) | started `node1/d3c104` |  |  |
| 2 | `lookup` on all nodes (baseline/service) - **agree** | `node1/d3c104` | `node1/d3c104` | `node1/d3c104` |
| 3 | _A second node claims the same name._ |  |  |  |
| 4 | `start_process` on n2 (baseline/service) |  | error: `taken` |  |
| 5 | `lookup` on all nodes (baseline/service) - **agree** | `node1/d3c104` | `node1/d3c104` | `node1/d3c104` |
| 6 | `renew_lease` on n2 (baseline/service) |  | `not_supported` |  |
| 7 | `stop_process` on n1 (baseline/service) | `stopped` |  |  |
| 8 | `lookup` on all nodes (baseline/service) - **agree** | `not_found` | `not_found` | `not_found` |

#### process death

The registered process is killed without unregistering. Shows whether the registry monitors the process and frees the name by itself, or keeps handing out a dead pid.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (process_death/service) | started `node1/7b445e` |  |  |
| 2 | `lookup` on all nodes (process_death/service) - **agree** | `node1/7b445e` | `node1/7b445e` | `node1/7b445e` |
| 3 | `kill_process` on n1 (process_death/service) | `killed` |  |  |
| 4 | wait 2000ms |  |  |  |
| 5 | `lookup` on all nodes (process_death/service) - **agree** | `not_found` | `not_found` | `not_found` |
| 6 | _Another node tries to take the name over._ |  |  |  |
| 7 | `start_process` on n2 (process_death/service) |  | started `node2/6e07f6` |  |
| 8 | `lookup` on all nodes (process_death/service) - **agree** | `node2/6e07f6` | `node2/6e07f6` | `node2/6e07f6` |

#### lease expiry

The lease is shortened to 3s and then nobody renews it. Registries without leases keep the name forever; a lease based registry drops it and lets another node take over.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | set lease_ms to 3000 |  |  |  |
| 2 | `start_process` on n1 (lease_expiry/service) | started `node1/b27ae5` |  |  |
| 3 | `lookup` on all nodes (lease_expiry/service) - **agree** | `node1/b27ae5` | `node1/b27ae5` | `node1/b27ae5` |
| 4 | `renew_lease` on n1 (lease_expiry/service) | `not_supported` |  |  |
| 5 | _Wait past the lease without renewing._ |  |  |  |
| 6 | wait 6000ms |  |  |  |
| 7 | `lookup` on all nodes (lease_expiry/service) - **agree** | `node1/b27ae5` | `node1/b27ae5` | `node1/b27ae5` |
| 8 | _Another node tries to take the name over._ |  |  |  |
| 9 | `start_process` on n2 (lease_expiry/service) |  | error: `taken` |  |
| 10 | `lookup` on all nodes (lease_expiry/service) - **agree** | `node1/b27ae5` | `node1/b27ae5` | `node1/b27ae5` |

#### symmetric split

The cluster splits into a majority (n1, n2) and a minority (n3). The owner is on the majority side. The minority tries to claim the same name, then the split is healed.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (symmetric_split/service) | started `node1/98776b` |  |  |
| 2 | `lookup` on all nodes (symmetric_split/service) - **agree** | `node1/98776b` | `node1/98776b` | `node1/98776b` |
| 3 | **isolate n3** |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (symmetric_split/service) - **disagree** | `node1/98776b` | `node1/98776b` | `not_found` |
| 6 | _The minority side claims the same name._ |  |  |  |
| 7 | `start_process` on n3 (symmetric_split/service) |  |  | started `node3/22a9d4` |
| 8 | `lookup` on all nodes (symmetric_split/service) - **disagree** | `node1/98776b` | `node1/98776b` | `node3/22a9d4` |
| 9 | `renew_lease` on n1 (symmetric_split/service) | `not_supported` |  |  |
| 10 | **heal the network** |  |  |  |
| 11 | wait 15000ms for the registry to react |  |  |  |
| 12 | _After healing: does the cluster agree again?_ |  |  |  |
| 13 | `lookup` on all nodes (symmetric_split/service) - **agree** | `node3/22a9d4` | `node3/22a9d4` | `node3/22a9d4` |

#### owner isolated

The node owning the name (n3) is cut off from the majority. This is the failover case: can the majority take the name over, and what happens to the old owner when the split heals?

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n3 (owner_isolated/service) |  |  | started `node3/0818cc` |
| 2 | `lookup` on all nodes (owner_isolated/service) - **agree** | `node3/0818cc` | `node3/0818cc` | `node3/0818cc` |
| 3 | **isolate n3** |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (owner_isolated/service) - **disagree** | `not_found` | `not_found` | `node3/0818cc` |
| 6 | _The majority side tries to take the name over._ |  |  |  |
| 7 | `start_process` on n1 (owner_isolated/service) | started `node1/74b207` |  |  |
| 8 | `lookup` on all nodes (owner_isolated/service) - **disagree** | `node1/74b207` | `node1/74b207` | `node3/0818cc` |
| 9 | **heal the network** |  |  |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | _After healing: one owner, or two?_ |  |  |  |
| 12 | `lookup` on all nodes (owner_isolated/service) - **agree** | `node1/74b207` | `node1/74b207` | `node1/74b207` |

#### one sided split

n1 stops hearing from n3, but n3 still hears n1. The two nodes disagree about whether the other one is alive, which is the case that breaks membership algorithms assuming symmetric failures.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (one_sided_split/service) | started `node1/695584` |  |  |
| 2 | `lookup` on all nodes (one_sided_split/service) - **agree** | `node1/695584` | `node1/695584` | `node1/695584` |
| 3 | **cut n1 <- n3** (one sided: n3 still hears n1) |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (one_sided_split/service) - **disagree** | `node1/695584` | `node1/695584` | `not_found` |
| 6 | _n3 claims the same name while it still believes n1 is up._ |  |  |  |
| 7 | `start_process` on n3 (one_sided_split/service) |  |  | started `node3/d0dfff` |
| 8 | `lookup` on all nodes (one_sided_split/service) - **disagree** | `node1/695584` | `node1/695584` | `node3/d0dfff` |
| 9 | **heal the network** |  |  |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | `lookup` on all nodes (one_sided_split/service) - **agree** | `node3/d0dfff` | `node3/d0dfff` | `node3/d0dfff` |

#### full split

Every node is cut off from every other node, so nobody has a majority. All three then try to own the same name at the same time, and the split is healed with three candidate owners.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (full_split/service) | started `node1/8aae17` |  |  |
| 2 | `lookup` on all nodes (full_split/service) - **agree** | `node1/8aae17` | `node1/8aae17` | `node1/8aae17` |
| 3 | **cut n1 <-> n2** |  |  |  |
| 4 | **cut n1 <-> n3** |  |  |  |
| 5 | **cut n2 <-> n3** |  |  |  |
| 6 | wait 15000ms for the registry to react |  |  |  |
| 7 | `lookup` on all nodes (full_split/service) - **disagree** | `node1/8aae17` | `not_found` | `not_found` |
| 8 | _Both other nodes claim the name as well._ |  |  |  |
| 9 | `start_process` on n2 (full_split/service) |  | started `node2/8aae17` |  |
| 10 | `start_process` on n3 (full_split/service) |  |  | started `node3/ef6d07` |
| 11 | `lookup` on all nodes (full_split/service) - **disagree** | `node1/8aae17` | `node2/8aae17` | `node3/ef6d07` |
| 12 | **heal the network** |  |  |  |
| 13 | wait 15000ms for the registry to react |  |  |  |
| 14 | _After healing: how many owners survive?_ |  |  |  |
| 15 | `lookup` on all nodes (full_split/service) - **agree** | `node2/8aae17` | `node2/8aae17` | `node2/8aae17` |

### locker

#### baseline

Healthy cluster. Establishes what the registry does when nothing is wrong: a name is visible everywhere, a second claim is refused, and the name is free again after an orderly stop.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (baseline/service) | started `node1/5a14b8` |  |  |
| 2 | `lookup` on all nodes (baseline/service) - **agree** | `node1/5a14b8` | `node1/5a14b8` | `node1/5a14b8` |
| 3 | _A second node claims the same name._ |  |  |  |
| 4 | `start_process` on n2 (baseline/service) |  | error: `no_quorum` |  |
| 5 | `lookup` on all nodes (baseline/service) - **agree** | `node1/5a14b8` | `node1/5a14b8` | `node1/5a14b8` |
| 6 | `renew_lease` on n2 (baseline/service) |  | `renewed` |  |
| 7 | `stop_process` on n1 (baseline/service) | `stopped` |  |  |
| 8 | `lookup` on all nodes (baseline/service) - **agree** | `not_found` | `not_found` | `not_found` |

#### process death

The registered process is killed without unregistering. Shows whether the registry monitors the process and frees the name by itself, or keeps handing out a dead pid.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (process_death/service) | started `node1/e7d158` |  |  |
| 2 | `lookup` on all nodes (process_death/service) - **agree** | `node1/e7d158` | `node1/e7d158` | `node1/e7d158` |
| 3 | `kill_process` on n1 (process_death/service) | `killed` |  |  |
| 4 | wait 2000ms |  |  |  |
| 5 | `lookup` on all nodes (process_death/service) - **agree** | `node1/e7d158` | `node1/e7d158` | `node1/e7d158` |
| 6 | _Another node tries to take the name over._ |  |  |  |
| 7 | `start_process` on n2 (process_death/service) |  | error: `no_quorum` |  |
| 8 | `lookup` on all nodes (process_death/service) - **agree** | `node1/e7d158` | `node1/e7d158` | `node1/e7d158` |

#### lease expiry

The lease is shortened to 3s and then nobody renews it. Registries without leases keep the name forever; a lease based registry drops it and lets another node take over.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | set lease_ms to 3000 |  |  |  |
| 2 | `start_process` on n1 (lease_expiry/service) | started `node1/8c54d1` |  |  |
| 3 | `lookup` on all nodes (lease_expiry/service) - **agree** | `node1/8c54d1` | `node1/8c54d1` | `node1/8c54d1` |
| 4 | `renew_lease` on n1 (lease_expiry/service) | `renewed` |  |  |
| 5 | _Wait past the lease without renewing._ |  |  |  |
| 6 | wait 6000ms |  |  |  |
| 7 | `lookup` on all nodes (lease_expiry/service) - **agree** | `not_found` | `not_found` | `not_found` |
| 8 | _Another node tries to take the name over._ |  |  |  |
| 9 | `start_process` on n2 (lease_expiry/service) |  | started `node2/037466` |  |
| 10 | `lookup` on all nodes (lease_expiry/service) - **agree** | `node2/037466` | `node2/037466` | `node2/037466` |

#### symmetric split

The cluster splits into a majority (n1, n2) and a minority (n3). The owner is on the majority side. The minority tries to claim the same name, then the split is healed.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (symmetric_split/service) | started `node1/27eac7` |  |  |
| 2 | `lookup` on all nodes (symmetric_split/service) - **agree** | `node1/27eac7` | `node1/27eac7` | `node1/27eac7` |
| 3 | **isolate n3** |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (symmetric_split/service) - **agree** | `node1/27eac7` | `node1/27eac7` | `node1/27eac7` |
| 6 | _The minority side claims the same name._ |  |  |  |
| 7 | `start_process` on n3 (symmetric_split/service) |  |  | error: `no_quorum` _(7010ms)_ |
| 8 | `lookup` on all nodes (symmetric_split/service) - **agree** | `node1/27eac7` | `node1/27eac7` | `node1/27eac7` |
| 9 | `renew_lease` on n1 (symmetric_split/service) | `renewed` _(7003ms)_ |  |  |
| 10 | **heal the network** |  |  |  |
| 11 | wait 15000ms for the registry to react |  |  |  |
| 12 | _After healing: does the cluster agree again?_ |  |  |  |
| 13 | `lookup` on all nodes (symmetric_split/service) - **agree** | `node1/27eac7` | `node1/27eac7` | `node1/27eac7` |

#### owner isolated

The node owning the name (n3) is cut off from the majority. This is the failover case: can the majority take the name over, and what happens to the old owner when the split heals?

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n3 (owner_isolated/service) |  |  | started `node3/0818cc` |
| 2 | `lookup` on all nodes (owner_isolated/service) - **agree** | `node3/0818cc` | `node3/0818cc` | `node3/0818cc` |
| 3 | **isolate n3** |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (owner_isolated/service) - **agree** | `node3/0818cc` | `node3/0818cc` | `node3/0818cc` |
| 6 | _The majority side tries to take the name over._ |  |  |  |
| 7 | `start_process` on n1 (owner_isolated/service) | error: `no_quorum` _(7008ms)_ |  |  |
| 8 | `lookup` on all nodes (owner_isolated/service) - **agree** | `node3/0818cc` | `node3/0818cc` | `node3/0818cc` |
| 9 | **heal the network** |  |  |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | _After healing: one owner, or two?_ |  |  |  |
| 12 | `lookup` on all nodes (owner_isolated/service) - **agree** | `node3/0818cc` | `node3/0818cc` | `node3/0818cc` |

#### one sided split

n1 stops hearing from n3, but n3 still hears n1. The two nodes disagree about whether the other one is alive, which is the case that breaks membership algorithms assuming symmetric failures.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (one_sided_split/service) | started `node1/67249b` |  |  |
| 2 | `lookup` on all nodes (one_sided_split/service) - **agree** | `node1/67249b` | `node1/67249b` | `node1/67249b` |
| 3 | **cut n1 <- n3** (one sided: n3 still hears n1) |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (one_sided_split/service) - **agree** | `node1/67249b` | `node1/67249b` | `node1/67249b` |
| 6 | _n3 claims the same name while it still believes n1 is up._ |  |  |  |
| 7 | `start_process` on n3 (one_sided_split/service) |  |  | error: `no_quorum` _(7008ms)_ |
| 8 | `lookup` on all nodes (one_sided_split/service) - **agree** | `node1/67249b` | `node1/67249b` | `node1/67249b` |
| 9 | **heal the network** |  |  |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | `lookup` on all nodes (one_sided_split/service) - **agree** | `node1/67249b` | `node1/67249b` | `node1/67249b` |

#### full split

Every node is cut off from every other node, so nobody has a majority. All three then try to own the same name at the same time, and the split is healed with three candidate owners.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (full_split/service) | started `node1/e0c194` |  |  |
| 2 | `lookup` on all nodes (full_split/service) - **agree** | `node1/e0c194` | `node1/e0c194` | `node1/e0c194` |
| 3 | **cut n1 <-> n2** |  |  |  |
| 4 | **cut n1 <-> n3** |  |  |  |
| 5 | **cut n2 <-> n3** |  |  |  |
| 6 | wait 15000ms for the registry to react |  |  |  |
| 7 | `lookup` on all nodes (full_split/service) - **agree** | `node1/e0c194` | `node1/e0c194` | `node1/e0c194` |
| 8 | _Both other nodes claim the name as well._ |  |  |  |
| 9 | `start_process` on n2 (full_split/service) |  | error: `no_quorum` _(7014ms)_ |  |
| 10 | `start_process` on n3 (full_split/service) |  |  | error: `no_quorum` _(7006ms)_ |
| 11 | `lookup` on all nodes (full_split/service) - **agree** | `node1/e0c194` | `node1/e0c194` | `node1/e0c194` |
| 12 | **heal the network** |  |  |  |
| 13 | wait 15000ms for the registry to react |  |  |  |
| 14 | _After healing: how many owners survive?_ |  |  |  |
| 15 | `lookup` on all nodes (full_split/service) - **agree** | `node1/e0c194` | `node1/e0c194` | `node1/e0c194` |

