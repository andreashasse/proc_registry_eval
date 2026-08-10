# Distributed process registry evaluation

A three node Erlang cluster in docker. The network between the nodes is cut and healed with iptables while a fixed list of actions is run against each registry, and every answer every node gives is written down.

Registries in this run: global, gproc, syn, horde, group, locker, highlander_pg. Produced by `./run.sh`; nothing in this file is written by hand.

## Environment

| Setting | global | gproc | syn | horde | group | locker | highlander_pg |
| --- | --- | --- | --- | --- | --- | --- | --- |
| run started | 2026-08-10T08:30:35Z | 2026-08-10T08:34:32Z | 2026-08-10T08:38:20Z | 2026-08-10T08:42:05Z | 2026-08-10T08:45:51Z | 2026-08-10T08:50:19Z | 2026-08-10T08:54:30Z |
| OTP release | 27 | 27 | 27 | 27 | 27 | 27 | 27 |
| net_ticktime | 5 | 5 | 5 | 5 | 5 | 5 | 5 |
| kernel prevent_overlapping_partitions | true | true | true | true | true | true | true |
| registry version | kernel 10.2.7.4 | gproc 1.3.0 | syn 3.4.2 | horde 0.10.0 | group 0.2.1 | locker 6 | highlander_pg 1.0.8 |
| settle after network change | 15000 | 15000 | 15000 | 15000 | 15000 | 15000 | 15000 |
| default lease | 60000 | 60000 | 60000 | 60000 | 60000 | 60000 | 60000 |
| action timeout | 20000 | 20000 | 20000 | 20000 | 20000 | 20000 | 20000 |
| wait for a pending claim | 3000 | 3000 | 3000 | 3000 | 3000 | 3000 | 3000 |
| horde keys | - | - | - | unique | - | - | - |
| horde members | - | - | - | auto, the visible nodes | - | - | - |
| group cluster | - | - | - | - | default, the connected nodes | - | - |
| locker write quorum | - | - | - | - | - | 2 of 3 masters | - |
| locker call timeout | - | - | - | - | - | 5000ms | - |
| highlander_pg database | - | - | - | - | - | - | workbench@postgres |
| highlander_pg polling interval | - | - | - | - | - | - | 300ms |

## Summary

Every `lookup on all nodes` step asks all three nodes who owns the name and compares the answers. `agree n/m` counts how many of those checks got the same answer from every node. `owners` is the highest number of different owners seen at the same time, so more than one means the cluster had a split brain. `refused` counts the actions the registry answered `{error, Reason}` to, such as a second claim on a name that is already owned; `timed out` counts the ones it did not answer at all.

| Scenario | global | gproc | syn | horde | group | locker | highlander_pg |
| --- | --- | --- | --- | --- | --- | --- | --- |
| baseline | agree 3/3, 1 owner, 1 refused | agree 3/3, 1 owner, 1 refused | agree 3/3, 1 owner, 1 refused | agree 0/3, 2 owners | agree 1/3, 1 owner, 1 refused | agree 3/3, 1 owner, 1 refused | agree 1/3, 1 owner |
| process death | agree 3/3, 1 owner | agree 3/3, 1 owner | agree 3/3, 1 owner | agree 1/3, 1 owner | agree 1/3, 1 owner | agree 3/3, 1 owner, 1 refused | agree 1/3, 1 owner |
| lease expiry | agree 3/3, 1 owner, 1 refused | agree 3/3, 1 owner, 1 refused | agree 3/3, 1 owner, 1 refused | agree 1/3, 2 owners | agree 2/3, 1 owner, 1 refused | agree 3/3, 1 owner | agree 0/3, 1 owner |
| symmetric split | agree 2/4, 2 owners | agree 2/4, 2 owners | agree 2/4, 2 owners | agree 1/4, 2 owners | agree 1/4, 2 owners | agree 4/4, 1 owner, 1 refused | agree 0/4, 1 owner |
| owner isolated | agree 2/4, 2 owners | agree 2/4, 2 owners | agree 2/4, 2 owners | agree 1/4, 2 owners | agree 1/4, 2 owners | agree 4/4, 1 owner, 1 refused | agree 0/4, 1 owner |
| one sided split | agree 2/4, 2 owners | agree 3/4, 2 owners | agree 2/4, 2 owners | agree 1/4, 2 owners | agree 1/4, 2 owners | agree 4/4, 1 owner, 1 refused | agree 0/4, 1 owner |
| full split | agree 2/4, 3 owners | agree 2/4, 3 owners | agree 2/4, 3 owners | agree 1/4, 3 owners | agree 1/4, 3 owners | agree 4/4, 1 owner, 2 refused | agree 0/4, 1 owner |
| database lost | agree 4/4, 1 owner, 1 refused | agree 0/4, 1 owner, 1 refused | agree 4/4, 1 owner, 1 refused | agree 4/4, 1 owner | agree 4/4, 1 owner, 1 refused | agree 4/4, 1 owner, 1 refused | agree 0/4, 1 owner |

## Observations

| Question | global | gproc | syn | horde | group | locker | highlander_pg |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Are leases supported? | no | no | no | no | no | yes | no |
| Slowest single action | 9ms | 5012ms | 7ms | 9ms | 13ms | 7012ms | 3102ms |
| Claims the registry refused | 3 | 3 | 3 | 0 | 3 | 8 | 0 |
| Actions that timed out or crashed | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| Checks where the nodes disagreed | 8 | 11 | 8 | 19 | 17 | 0 | 27 |
| Highest number of owners at the same time | 3 | 3 | 3 | 3 | 3 | 1 | 1 |

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
| 1 | `start_process` on n1 (baseline/service) | started `node1/2559fd` |  |  |
| 2 | `lookup` on all nodes (baseline/service) - **agree** | `node1/2559fd` | `node1/2559fd` | `node1/2559fd` |
| 3 | _A second node claims the same name._ |  |  |  |
| 4 | `start_process` on n2 (baseline/service) |  | error: `name_taken` |  |
| 5 | `lookup` on all nodes (baseline/service) - **agree** | `node1/2559fd` | `node1/2559fd` | `node1/2559fd` |
| 6 | `renew_lease` on n2 (baseline/service) |  | `not_supported` |  |
| 7 | `stop_process` on n1 (baseline/service) | `stopped` |  |  |
| 8 | `lookup` on all nodes (baseline/service) - **agree** | `not_found` | `not_found` | `not_found` |

#### process death

The registered process is killed without unregistering. Shows whether the registry monitors the process and frees the name by itself, or keeps handing out a dead pid.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (process_death/service) | started `node1/34b0e2` |  |  |
| 2 | `lookup` on all nodes (process_death/service) - **agree** | `node1/34b0e2` | `node1/34b0e2` | `node1/34b0e2` |
| 3 | `kill_process` on n1 (process_death/service) | `killed` |  |  |
| 4 | wait 2000ms |  |  |  |
| 5 | `lookup` on all nodes (process_death/service) - **agree** | `not_found` | `not_found` | `not_found` |
| 6 | _Another node tries to take the name over._ |  |  |  |
| 7 | `start_process` on n2 (process_death/service) |  | started `node2/89c8ef` |  |
| 8 | `lookup` on all nodes (process_death/service) - **agree** | `node2/89c8ef` | `node2/89c8ef` | `node2/89c8ef` |

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
| 9 | `start_process` on n2 (lease_expiry/service) |  | error: `name_taken` |  |
| 10 | `lookup` on all nodes (lease_expiry/service) - **agree** | `node1/b27ae5` | `node1/b27ae5` | `node1/b27ae5` |

#### symmetric split

The cluster splits into a majority (n1, n2) and a minority (n3). The owner is on the majority side. The minority tries to claim the same name, then the split is healed.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (symmetric_split/service) | started `node1/22a9d4` |  |  |
| 2 | `lookup` on all nodes (symmetric_split/service) - **agree** | `node1/22a9d4` | `node1/22a9d4` | `node1/22a9d4` |
| 3 | **isolate n3** |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (symmetric_split/service) - **disagree** | `node1/22a9d4` | `node1/22a9d4` | `not_found` |
| 6 | _The minority side claims the same name._ |  |  |  |
| 7 | `start_process` on n3 (symmetric_split/service) |  |  | started `node3/0f9b53` |
| 8 | `lookup` on all nodes (symmetric_split/service) - **disagree** | `node1/22a9d4` | `node1/22a9d4` | `node3/0f9b53` |
| 9 | `renew_lease` on n1 (symmetric_split/service) | `not_supported` |  |  |
| 10 | **heal the network** |  |  |  |
| 11 | wait 15000ms for the registry to react |  |  |  |
| 12 | _After healing: does the cluster agree again?_ |  |  |  |
| 13 | `lookup` on all nodes (symmetric_split/service) - **agree** | `node1/22a9d4` | `node1/22a9d4` | `node1/22a9d4` |

#### owner isolated

The node owning the name (n3) is cut off from the majority. This is the failover case: can the majority take the name over, and what happens to the old owner when the split heals?

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n3 (owner_isolated/service) |  |  | started `node3/4392fd` |
| 2 | `lookup` on all nodes (owner_isolated/service) - **agree** | `node3/4392fd` | `node3/4392fd` | `node3/4392fd` |
| 3 | **isolate n3** |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (owner_isolated/service) - **disagree** | `not_found` | `not_found` | `node3/4392fd` |
| 6 | _The majority side tries to take the name over._ |  |  |  |
| 7 | `start_process` on n1 (owner_isolated/service) | started `node1/0fdaf5` |  |  |
| 8 | `lookup` on all nodes (owner_isolated/service) - **disagree** | `node1/0fdaf5` | `node1/0fdaf5` | `node3/4392fd` |
| 9 | **heal the network** |  |  |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | _After healing: one owner, or two?_ |  |  |  |
| 12 | `lookup` on all nodes (owner_isolated/service) - **agree** | `node1/0fdaf5` | `node1/0fdaf5` | `node1/0fdaf5` |

#### one sided split

n1 stops hearing from n3, but n3 still hears n1. The two nodes disagree about whether the other one is alive, which is the case that breaks membership algorithms assuming symmetric failures.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (one_sided_split/service) | started `node1/a60239` |  |  |
| 2 | `lookup` on all nodes (one_sided_split/service) - **agree** | `node1/a60239` | `node1/a60239` | `node1/a60239` |
| 3 | **cut n1 <- n3** (one sided: n3 still hears n1) |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (one_sided_split/service) - **disagree** | `node1/a60239` | `not_found` | `not_found` |
| 6 | _n3 claims the same name while it still believes n1 is up._ |  |  |  |
| 7 | `start_process` on n3 (one_sided_split/service) |  |  | started `node3/fee2b1` |
| 8 | `lookup` on all nodes (one_sided_split/service) - **disagree** | `node1/a60239` | `node3/fee2b1` | `node3/fee2b1` |
| 9 | **heal the network** |  |  |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | `lookup` on all nodes (one_sided_split/service) - **agree** | `node1/a60239` | `node1/a60239` | `node1/a60239` |

#### full split

Every node is cut off from every other node, so nobody has a majority. All three then try to own the same name at the same time, and the split is healed with three candidate owners.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (full_split/service) | started `node1/3d52ab` |  |  |
| 2 | `lookup` on all nodes (full_split/service) - **agree** | `node1/3d52ab` | `node1/3d52ab` | `node1/3d52ab` |
| 3 | **cut n1 <-> n2** |  |  |  |
| 4 | **cut n1 <-> n3** |  |  |  |
| 5 | **cut n2 <-> n3** |  |  |  |
| 6 | wait 15000ms for the registry to react |  |  |  |
| 7 | `lookup` on all nodes (full_split/service) - **disagree** | `node1/3d52ab` | `not_found` | `not_found` |
| 8 | _Both other nodes claim the name as well._ |  |  |  |
| 9 | `start_process` on n2 (full_split/service) |  | started `node2/beff98` |  |
| 10 | `start_process` on n3 (full_split/service) |  |  | started `node3/bd53b8` |
| 11 | `lookup` on all nodes (full_split/service) - **disagree** | `node1/3d52ab` | `node2/beff98` | `node3/bd53b8` |
| 12 | **heal the network** |  |  |  |
| 13 | wait 15000ms for the registry to react |  |  |  |
| 14 | _After healing: how many owners survive?_ |  |  |  |
| 15 | `lookup` on all nodes (full_split/service) - **agree** | `node1/3d52ab` | `node1/3d52ab` | `node1/3d52ab` |

#### database lost

The node owning the name loses its connection to Postgres while the BEAM cluster stays intact. Only matters for a registry that keeps its state in the database; for the others nothing happens, which is itself the result.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (database_lost/service) | started `node1/a70f0c` |  |  |
| 2 | wait 15000ms for the registry to react |  |  |  |
| 3 | `lookup` on all nodes (database_lost/service) - **agree** | `node1/a70f0c` | `node1/a70f0c` | `node1/a70f0c` |
| 4 | _n1 can still reach the other nodes, but not the database._ |  |  |  |
| 5 | **cut n1 <- postgres** |  |  |  |
| 6 | wait 15000ms for the registry to react |  |  |  |
| 7 | `lookup` on all nodes (database_lost/service) - **agree** | `node1/a70f0c` | `node1/a70f0c` | `node1/a70f0c` |
| 8 | _Does another node take the name over?_ |  |  |  |
| 9 | `start_process` on n2 (database_lost/service) |  | error: `name_taken` |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | `lookup` on all nodes (database_lost/service) - **agree** | `node1/a70f0c` | `node1/a70f0c` | `node1/a70f0c` |
| 12 | **heal the network** |  |  |  |
| 13 | wait 15000ms for the registry to react |  |  |  |
| 14 | `lookup` on all nodes (database_lost/service) - **agree** | `node1/a70f0c` | `node1/a70f0c` | `node1/a70f0c` |

### gproc

#### baseline

Healthy cluster. Establishes what the registry does when nothing is wrong: a name is visible everywhere, a second claim is refused, and the name is free again after an orderly stop.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (baseline/service) | started `node1/c8b71a` |  |  |
| 2 | `lookup` on all nodes (baseline/service) - **agree** | `node1/c8b71a` | `node1/c8b71a` | `node1/c8b71a` |
| 3 | _A second node claims the same name._ |  |  |  |
| 4 | `start_process` on n2 (baseline/service) |  | error: `badarg` |  |
| 5 | `lookup` on all nodes (baseline/service) - **agree** | `node1/c8b71a` | `node1/c8b71a` | `node1/c8b71a` |
| 6 | `renew_lease` on n2 (baseline/service) |  | `not_supported` |  |
| 7 | `stop_process` on n1 (baseline/service) | `stopped` |  |  |
| 8 | `lookup` on all nodes (baseline/service) - **agree** | `not_found` | `not_found` | `not_found` |

#### process death

The registered process is killed without unregistering. Shows whether the registry monitors the process and frees the name by itself, or keeps handing out a dead pid.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (process_death/service) | started `node1/ae69eb` |  |  |
| 2 | `lookup` on all nodes (process_death/service) - **agree** | `node1/ae69eb` | `node1/ae69eb` | `node1/ae69eb` |
| 3 | `kill_process` on n1 (process_death/service) | `killed` |  |  |
| 4 | wait 2000ms |  |  |  |
| 5 | `lookup` on all nodes (process_death/service) - **agree** | `not_found` | `not_found` | `not_found` |
| 6 | _Another node tries to take the name over._ |  |  |  |
| 7 | `start_process` on n2 (process_death/service) |  | started `node2/81785f` |  |
| 8 | `lookup` on all nodes (process_death/service) - **agree** | `node2/81785f` | `node2/81785f` | `node2/81785f` |

#### lease expiry

The lease is shortened to 3s and then nobody renews it. Registries without leases keep the name forever; a lease based registry drops it and lets another node take over.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | set lease_ms to 3000 |  |  |  |
| 2 | `start_process` on n1 (lease_expiry/service) | started `node1/75e17c` |  |  |
| 3 | `lookup` on all nodes (lease_expiry/service) - **agree** | `node1/75e17c` | `node1/75e17c` | `node1/75e17c` |
| 4 | `renew_lease` on n1 (lease_expiry/service) | `not_supported` |  |  |
| 5 | _Wait past the lease without renewing._ |  |  |  |
| 6 | wait 6000ms |  |  |  |
| 7 | `lookup` on all nodes (lease_expiry/service) - **agree** | `node1/75e17c` | `node1/75e17c` | `node1/75e17c` |
| 8 | _Another node tries to take the name over._ |  |  |  |
| 9 | `start_process` on n2 (lease_expiry/service) |  | error: `badarg` |  |
| 10 | `lookup` on all nodes (lease_expiry/service) - **agree** | `node1/75e17c` | `node1/75e17c` | `node1/75e17c` |

#### symmetric split

The cluster splits into a majority (n1, n2) and a minority (n3). The owner is on the majority side. The minority tries to claim the same name, then the split is healed.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (symmetric_split/service) | started `node1/cb9d65` |  |  |
| 2 | `lookup` on all nodes (symmetric_split/service) - **agree** | `node1/cb9d65` | `node1/cb9d65` | `node1/cb9d65` |
| 3 | **isolate n3** |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (symmetric_split/service) - **disagree** | `node1/cb9d65` | `node1/cb9d65` | `not_found` |
| 6 | _The minority side claims the same name._ |  |  |  |
| 7 | `start_process` on n3 (symmetric_split/service) |  |  | started `node3/01bc77` |
| 8 | `lookup` on all nodes (symmetric_split/service) - **disagree** | `node1/cb9d65` | `node1/cb9d65` | `node3/01bc77` |
| 9 | `renew_lease` on n1 (symmetric_split/service) | `not_supported` |  |  |
| 10 | **heal the network** |  |  |  |
| 11 | wait 15000ms for the registry to react |  |  |  |
| 12 | _After healing: does the cluster agree again?_ |  |  |  |
| 13 | `lookup` on all nodes (symmetric_split/service) - **agree** | `node3/01bc77` | `node3/01bc77` | `node3/01bc77` |

#### owner isolated

The node owning the name (n3) is cut off from the majority. This is the failover case: can the majority take the name over, and what happens to the old owner when the split heals?

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n3 (owner_isolated/service) |  |  | started `node3/82dd51` |
| 2 | `lookup` on all nodes (owner_isolated/service) - **agree** | `node3/82dd51` | `node3/82dd51` | `node3/82dd51` |
| 3 | **isolate n3** |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (owner_isolated/service) - **disagree** | `not_found` | `not_found` | `node3/82dd51` |
| 6 | _The majority side tries to take the name over._ |  |  |  |
| 7 | `start_process` on n1 (owner_isolated/service) | started `node1/fee2b1` |  |  |
| 8 | `lookup` on all nodes (owner_isolated/service) - **disagree** | `node1/fee2b1` | `node1/fee2b1` | `node3/82dd51` |
| 9 | **heal the network** |  |  |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | _After healing: one owner, or two?_ |  |  |  |
| 12 | `lookup` on all nodes (owner_isolated/service) - **agree** | `node3/82dd51` | `node3/82dd51` | `node3/82dd51` |

#### one sided split

n1 stops hearing from n3, but n3 still hears n1. The two nodes disagree about whether the other one is alive, which is the case that breaks membership algorithms assuming symmetric failures.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (one_sided_split/service) | started `node1/2a4164` |  |  |
| 2 | `lookup` on all nodes (one_sided_split/service) - **agree** | `node1/2a4164` | `node1/2a4164` | `node1/2a4164` |
| 3 | **cut n1 <- n3** (one sided: n3 still hears n1) |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (one_sided_split/service) - **agree** | `node1/2a4164` | `node1/2a4164` | `node1/2a4164` |
| 6 | _n3 claims the same name while it still believes n1 is up._ |  |  |  |
| 7 | `start_process` on n3 (one_sided_split/service) |  |  | started `node3/bb8474` _(284ms)_ |
| 8 | `lookup` on all nodes (one_sided_split/service) - **disagree** | `node1/2a4164` | `node1/2a4164` | `node3/bb8474` |
| 9 | **heal the network** |  |  |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | `lookup` on all nodes (one_sided_split/service) - **agree** | `node3/bb8474` | `node3/bb8474` | `node3/bb8474` |

#### full split

Every node is cut off from every other node, so nobody has a majority. All three then try to own the same name at the same time, and the split is healed with three candidate owners.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (full_split/service) | started `node1/3a7f4c` |  |  |
| 2 | `lookup` on all nodes (full_split/service) - **agree** | `node1/3a7f4c` | `node1/3a7f4c` | `node1/3a7f4c` |
| 3 | **cut n1 <-> n2** |  |  |  |
| 4 | **cut n1 <-> n3** |  |  |  |
| 5 | **cut n2 <-> n3** |  |  |  |
| 6 | wait 15000ms for the registry to react |  |  |  |
| 7 | `lookup` on all nodes (full_split/service) - **disagree** | `node1/3a7f4c` | `node1/3a7f4c` | `not_found` |
| 8 | _Both other nodes claim the name as well._ |  |  |  |
| 9 | `start_process` on n2 (full_split/service) |  | started `node2/2373ea` _(4513ms)_ |  |
| 10 | `start_process` on n3 (full_split/service) |  |  | started `node3/1484a1` |
| 11 | `lookup` on all nodes (full_split/service) - **disagree** | `node1/3a7f4c` | `node2/2373ea` | `node3/1484a1` |
| 12 | **heal the network** |  |  |  |
| 13 | wait 15000ms for the registry to react |  |  |  |
| 14 | _After healing: how many owners survive?_ |  |  |  |
| 15 | `lookup` on all nodes (full_split/service) - **agree** | `node3/1484a1` | `node3/1484a1` | `node3/1484a1` |

#### database lost

The node owning the name loses its connection to Postgres while the BEAM cluster stays intact. Only matters for a registry that keeps its state in the database; for the others nothing happens, which is itself the result.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (database_lost/service) | started `node1/4260e9` |  |  |
| 2 | wait 15000ms for the registry to react |  |  |  |
| 3 | `lookup` on all nodes (database_lost/service) - **disagree** | `node1/4260e9` | `not_found` | `not_found` |
| 4 | _n1 can still reach the other nodes, but not the database._ |  |  |  |
| 5 | **cut n1 <- postgres** |  |  |  |
| 6 | wait 15000ms for the registry to react |  |  |  |
| 7 | `lookup` on all nodes (database_lost/service) - **disagree** | `node1/4260e9` | `not_found` | `not_found` |
| 8 | _Does another node take the name over?_ |  |  |  |
| 9 | `start_process` on n2 (database_lost/service) |  | error: `{timeout,{gen_leader,leader_call,
                     [gproc_dist,
                      {reg_other,{n,g,<<"database_lost/service">>},
                                 undefined,<<"<10204.345.0>">>,[],reg}]}}` _(5012ms)_ |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | `lookup` on all nodes (database_lost/service) - **disagree** | `node1/4260e9` | `not_found` | `not_found` |
| 12 | **heal the network** |  |  |  |
| 13 | wait 15000ms for the registry to react |  |  |  |
| 14 | `lookup` on all nodes (database_lost/service) - **disagree** | `node1/4260e9` | `not_found` | `not_found` |

### syn

#### baseline

Healthy cluster. Establishes what the registry does when nothing is wrong: a name is visible everywhere, a second claim is refused, and the name is free again after an orderly stop.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (baseline/service) | started `node1/87ce39` |  |  |
| 2 | `lookup` on all nodes (baseline/service) - **agree** | `node1/87ce39` | `node1/87ce39` | `node1/87ce39` |
| 3 | _A second node claims the same name._ |  |  |  |
| 4 | `start_process` on n2 (baseline/service) |  | error: `taken` |  |
| 5 | `lookup` on all nodes (baseline/service) - **agree** | `node1/87ce39` | `node1/87ce39` | `node1/87ce39` |
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
| 7 | `start_process` on n2 (process_death/service) |  | started `node2/5e7dec` |  |
| 8 | `lookup` on all nodes (process_death/service) - **agree** | `node2/5e7dec` | `node2/5e7dec` | `node2/5e7dec` |

#### lease expiry

The lease is shortened to 3s and then nobody renews it. Registries without leases keep the name forever; a lease based registry drops it and lets another node take over.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | set lease_ms to 3000 |  |  |  |
| 2 | `start_process` on n1 (lease_expiry/service) | started `node1/4a9be7` |  |  |
| 3 | `lookup` on all nodes (lease_expiry/service) - **agree** | `node1/4a9be7` | `node1/4a9be7` | `node1/4a9be7` |
| 4 | `renew_lease` on n1 (lease_expiry/service) | `not_supported` |  |  |
| 5 | _Wait past the lease without renewing._ |  |  |  |
| 6 | wait 6000ms |  |  |  |
| 7 | `lookup` on all nodes (lease_expiry/service) - **agree** | `node1/4a9be7` | `node1/4a9be7` | `node1/4a9be7` |
| 8 | _Another node tries to take the name over._ |  |  |  |
| 9 | `start_process` on n2 (lease_expiry/service) |  | error: `taken` |  |
| 10 | `lookup` on all nodes (lease_expiry/service) - **agree** | `node1/4a9be7` | `node1/4a9be7` | `node1/4a9be7` |

#### symmetric split

The cluster splits into a majority (n1, n2) and a minority (n3). The owner is on the majority side. The minority tries to claim the same name, then the split is healed.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (symmetric_split/service) | started `node1/86ae6f` |  |  |
| 2 | `lookup` on all nodes (symmetric_split/service) - **agree** | `node1/86ae6f` | `node1/86ae6f` | `node1/86ae6f` |
| 3 | **isolate n3** |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (symmetric_split/service) - **disagree** | `node1/86ae6f` | `node1/86ae6f` | `not_found` |
| 6 | _The minority side claims the same name._ |  |  |  |
| 7 | `start_process` on n3 (symmetric_split/service) |  |  | started `node3/b712ba` |
| 8 | `lookup` on all nodes (symmetric_split/service) - **disagree** | `node1/86ae6f` | `node1/86ae6f` | `node3/b712ba` |
| 9 | `renew_lease` on n1 (symmetric_split/service) | `not_supported` |  |  |
| 10 | **heal the network** |  |  |  |
| 11 | wait 15000ms for the registry to react |  |  |  |
| 12 | _After healing: does the cluster agree again?_ |  |  |  |
| 13 | `lookup` on all nodes (symmetric_split/service) - **agree** | `node3/b712ba` | `node3/b712ba` | `node3/b712ba` |

#### owner isolated

The node owning the name (n3) is cut off from the majority. This is the failover case: can the majority take the name over, and what happens to the old owner when the split heals?

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n3 (owner_isolated/service) |  |  | started `node3/27c2cc` |
| 2 | `lookup` on all nodes (owner_isolated/service) - **agree** | `node3/27c2cc` | `node3/27c2cc` | `node3/27c2cc` |
| 3 | **isolate n3** |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (owner_isolated/service) - **disagree** | `not_found` | `not_found` | `node3/27c2cc` |
| 6 | _The majority side tries to take the name over._ |  |  |  |
| 7 | `start_process` on n1 (owner_isolated/service) | started `node1/dd0569` |  |  |
| 8 | `lookup` on all nodes (owner_isolated/service) - **disagree** | `node1/dd0569` | `node1/dd0569` | `node3/27c2cc` |
| 9 | **heal the network** |  |  |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | _After healing: one owner, or two?_ |  |  |  |
| 12 | `lookup` on all nodes (owner_isolated/service) - **agree** | `node1/dd0569` | `node1/dd0569` | `node1/dd0569` |

#### one sided split

n1 stops hearing from n3, but n3 still hears n1. The two nodes disagree about whether the other one is alive, which is the case that breaks membership algorithms assuming symmetric failures.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (one_sided_split/service) | started `node1/3b68e5` |  |  |
| 2 | `lookup` on all nodes (one_sided_split/service) - **agree** | `node1/3b68e5` | `node1/3b68e5` | `node1/3b68e5` |
| 3 | **cut n1 <- n3** (one sided: n3 still hears n1) |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (one_sided_split/service) - **disagree** | `node1/3b68e5` | `node1/3b68e5` | `not_found` |
| 6 | _n3 claims the same name while it still believes n1 is up._ |  |  |  |
| 7 | `start_process` on n3 (one_sided_split/service) |  |  | started `node3/22824a` |
| 8 | `lookup` on all nodes (one_sided_split/service) - **disagree** | `node1/3b68e5` | `node1/3b68e5` | `node3/22824a` |
| 9 | **heal the network** |  |  |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | `lookup` on all nodes (one_sided_split/service) - **agree** | `node3/22824a` | `node3/22824a` | `node3/22824a` |

#### full split

Every node is cut off from every other node, so nobody has a majority. All three then try to own the same name at the same time, and the split is healed with three candidate owners.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (full_split/service) | started `node1/ad7731` |  |  |
| 2 | `lookup` on all nodes (full_split/service) - **agree** | `node1/ad7731` | `node1/ad7731` | `node1/ad7731` |
| 3 | **cut n1 <-> n2** |  |  |  |
| 4 | **cut n1 <-> n3** |  |  |  |
| 5 | **cut n2 <-> n3** |  |  |  |
| 6 | wait 15000ms for the registry to react |  |  |  |
| 7 | `lookup` on all nodes (full_split/service) - **disagree** | `node1/ad7731` | `not_found` | `not_found` |
| 8 | _Both other nodes claim the name as well._ |  |  |  |
| 9 | `start_process` on n2 (full_split/service) |  | started `node2/ef6d07` |  |
| 10 | `start_process` on n3 (full_split/service) |  |  | started `node3/f51525` |
| 11 | `lookup` on all nodes (full_split/service) - **disagree** | `node1/ad7731` | `node2/ef6d07` | `node3/f51525` |
| 12 | **heal the network** |  |  |  |
| 13 | wait 15000ms for the registry to react |  |  |  |
| 14 | _After healing: how many owners survive?_ |  |  |  |
| 15 | `lookup` on all nodes (full_split/service) - **agree** | `node2/ef6d07` | `node2/ef6d07` | `node2/ef6d07` |

#### database lost

The node owning the name loses its connection to Postgres while the BEAM cluster stays intact. Only matters for a registry that keeps its state in the database; for the others nothing happens, which is itself the result.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (database_lost/service) | started `node1/f8349b` |  |  |
| 2 | wait 15000ms for the registry to react |  |  |  |
| 3 | `lookup` on all nodes (database_lost/service) - **agree** | `node1/f8349b` | `node1/f8349b` | `node1/f8349b` |
| 4 | _n1 can still reach the other nodes, but not the database._ |  |  |  |
| 5 | **cut n1 <- postgres** |  |  |  |
| 6 | wait 15000ms for the registry to react |  |  |  |
| 7 | `lookup` on all nodes (database_lost/service) - **agree** | `node1/f8349b` | `node1/f8349b` | `node1/f8349b` |
| 8 | _Does another node take the name over?_ |  |  |  |
| 9 | `start_process` on n2 (database_lost/service) |  | error: `taken` |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | `lookup` on all nodes (database_lost/service) - **agree** | `node1/f8349b` | `node1/f8349b` | `node1/f8349b` |
| 12 | **heal the network** |  |  |  |
| 13 | wait 15000ms for the registry to react |  |  |  |
| 14 | `lookup` on all nodes (database_lost/service) - **agree** | `node1/f8349b` | `node1/f8349b` | `node1/f8349b` |

### horde

#### baseline

Healthy cluster. Establishes what the registry does when nothing is wrong: a name is visible everywhere, a second claim is refused, and the name is free again after an orderly stop.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (baseline/service) | started `node1/d70750` |  |  |
| 2 | `lookup` on all nodes (baseline/service) - **disagree** | `node1/d70750` | `not_found` | `not_found` |
| 3 | _A second node claims the same name._ |  |  |  |
| 4 | `start_process` on n2 (baseline/service) |  | started `node2/d70750` |  |
| 5 | `lookup` on all nodes (baseline/service) - **disagree** | `node1/d70750` | `node2/d70750` | `not_found` |
| 6 | `renew_lease` on n2 (baseline/service) |  | `not_supported` |  |
| 7 | `stop_process` on n1 (baseline/service) | `stopped` |  |  |
| 8 | `lookup` on all nodes (baseline/service) - **disagree** | `not_found` | `node2/d70750` | `not_found` |

#### process death

The registered process is killed without unregistering. Shows whether the registry monitors the process and frees the name by itself, or keeps handing out a dead pid.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (process_death/service) | started `node1/ea654a` |  |  |
| 2 | `lookup` on all nodes (process_death/service) - **disagree** | `node1/ea654a` | `not_found` | `not_found` |
| 3 | `kill_process` on n1 (process_death/service) | `killed` |  |  |
| 4 | wait 2000ms |  |  |  |
| 5 | `lookup` on all nodes (process_death/service) - **agree** | `not_found` | `not_found` | `not_found` |
| 6 | _Another node tries to take the name over._ |  |  |  |
| 7 | `start_process` on n2 (process_death/service) |  | started `node2/0bc2d0` |  |
| 8 | `lookup` on all nodes (process_death/service) - **disagree** | `not_found` | `node2/0bc2d0` | `not_found` |

#### lease expiry

The lease is shortened to 3s and then nobody renews it. Registries without leases keep the name forever; a lease based registry drops it and lets another node take over.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | set lease_ms to 3000 |  |  |  |
| 2 | `start_process` on n1 (lease_expiry/service) | started `node1/b712ba` |  |  |
| 3 | `lookup` on all nodes (lease_expiry/service) - **disagree** | `node1/b712ba` | `not_found` | `not_found` |
| 4 | `renew_lease` on n1 (lease_expiry/service) | `not_supported` |  |  |
| 5 | _Wait past the lease without renewing._ |  |  |  |
| 6 | wait 6000ms |  |  |  |
| 7 | `lookup` on all nodes (lease_expiry/service) - **agree** | `node1/b712ba` | `node1/b712ba` | `node1/b712ba` |
| 8 | _Another node tries to take the name over._ |  |  |  |
| 9 | `start_process` on n2 (lease_expiry/service) |  | started `node2/b712ba` |  |
| 10 | `lookup` on all nodes (lease_expiry/service) - **disagree** | `node1/b712ba` | `node2/b712ba` | `node1/b712ba` |

#### symmetric split

The cluster splits into a majority (n1, n2) and a minority (n3). The owner is on the majority side. The minority tries to claim the same name, then the split is healed.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (symmetric_split/service) | started `node1/0818cc` |  |  |
| 2 | `lookup` on all nodes (symmetric_split/service) - **disagree** | `node1/0818cc` | `not_found` | `not_found` |
| 3 | **isolate n3** |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (symmetric_split/service) - **disagree** | `node1/0818cc` | `node1/0818cc` | `not_found` |
| 6 | _The minority side claims the same name._ |  |  |  |
| 7 | `start_process` on n3 (symmetric_split/service) |  |  | started `node3/6c4c45` |
| 8 | `lookup` on all nodes (symmetric_split/service) - **disagree** | `node1/0818cc` | `node1/0818cc` | `node3/6c4c45` |
| 9 | `renew_lease` on n1 (symmetric_split/service) | `not_supported` |  |  |
| 10 | **heal the network** |  |  |  |
| 11 | wait 15000ms for the registry to react |  |  |  |
| 12 | _After healing: does the cluster agree again?_ |  |  |  |
| 13 | `lookup` on all nodes (symmetric_split/service) - **agree** | `node3/6c4c45` | `node3/6c4c45` | `node3/6c4c45` |

#### owner isolated

The node owning the name (n3) is cut off from the majority. This is the failover case: can the majority take the name over, and what happens to the old owner when the split heals?

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n3 (owner_isolated/service) |  |  | started `node3/2c0ee0` |
| 2 | `lookup` on all nodes (owner_isolated/service) - **disagree** | `not_found` | `not_found` | `node3/2c0ee0` |
| 3 | **isolate n3** |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (owner_isolated/service) - **disagree** | `not_found` | `not_found` | `node3/2c0ee0` |
| 6 | _The majority side tries to take the name over._ |  |  |  |
| 7 | `start_process` on n1 (owner_isolated/service) | started `node1/1448f2` |  |  |
| 8 | `lookup` on all nodes (owner_isolated/service) - **disagree** | `node1/1448f2` | `not_found` | `node3/2c0ee0` |
| 9 | **heal the network** |  |  |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | _After healing: one owner, or two?_ |  |  |  |
| 12 | `lookup` on all nodes (owner_isolated/service) - **agree** | `node1/1448f2` | `node1/1448f2` | `node1/1448f2` |

#### one sided split

n1 stops hearing from n3, but n3 still hears n1. The two nodes disagree about whether the other one is alive, which is the case that breaks membership algorithms assuming symmetric failures.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (one_sided_split/service) | started `node1/2c9ee5` |  |  |
| 2 | `lookup` on all nodes (one_sided_split/service) - **disagree** | `node1/2c9ee5` | `not_found` | `not_found` |
| 3 | **cut n1 <- n3** (one sided: n3 still hears n1) |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (one_sided_split/service) - **disagree** | `node1/2c9ee5` | `not_found` | `not_found` |
| 6 | _n3 claims the same name while it still believes n1 is up._ |  |  |  |
| 7 | `start_process` on n3 (one_sided_split/service) |  |  | started `node3/bd53b8` |
| 8 | `lookup` on all nodes (one_sided_split/service) - **disagree** | `node1/2c9ee5` | `not_found` | `node3/bd53b8` |
| 9 | **heal the network** |  |  |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | `lookup` on all nodes (one_sided_split/service) - **agree** | `not_found` | `not_found` | `not_found` |

#### full split

Every node is cut off from every other node, so nobody has a majority. All three then try to own the same name at the same time, and the split is healed with three candidate owners.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (full_split/service) | started `node1/860759` |  |  |
| 2 | `lookup` on all nodes (full_split/service) - **disagree** | `node1/860759` | `not_found` | `not_found` |
| 3 | **cut n1 <-> n2** |  |  |  |
| 4 | **cut n1 <-> n3** |  |  |  |
| 5 | **cut n2 <-> n3** |  |  |  |
| 6 | wait 15000ms for the registry to react |  |  |  |
| 7 | `lookup` on all nodes (full_split/service) - **disagree** | `node1/860759` | `not_found` | `not_found` |
| 8 | _Both other nodes claim the name as well._ |  |  |  |
| 9 | `start_process` on n2 (full_split/service) |  | started `node2/6c1312` |  |
| 10 | `start_process` on n3 (full_split/service) |  |  | started `node3/29b23e` |
| 11 | `lookup` on all nodes (full_split/service) - **disagree** | `node1/860759` | `node2/6c1312` | `node3/29b23e` |
| 12 | **heal the network** |  |  |  |
| 13 | wait 15000ms for the registry to react |  |  |  |
| 14 | _After healing: how many owners survive?_ |  |  |  |
| 15 | `lookup` on all nodes (full_split/service) - **agree** | `node3/29b23e` | `node3/29b23e` | `node3/29b23e` |

#### database lost

The node owning the name loses its connection to Postgres while the BEAM cluster stays intact. Only matters for a registry that keeps its state in the database; for the others nothing happens, which is itself the result.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (database_lost/service) | started `node1/e7ed4f` |  |  |
| 2 | wait 15000ms for the registry to react |  |  |  |
| 3 | `lookup` on all nodes (database_lost/service) - **agree** | `node1/e7ed4f` | `node1/e7ed4f` | `node1/e7ed4f` |
| 4 | _n1 can still reach the other nodes, but not the database._ |  |  |  |
| 5 | **cut n1 <- postgres** |  |  |  |
| 6 | wait 15000ms for the registry to react |  |  |  |
| 7 | `lookup` on all nodes (database_lost/service) - **agree** | `node1/e7ed4f` | `node1/e7ed4f` | `node1/e7ed4f` |
| 8 | _Does another node take the name over?_ |  |  |  |
| 9 | `start_process` on n2 (database_lost/service) |  | started `node2/804fbf` |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | `lookup` on all nodes (database_lost/service) - **agree** | `node2/804fbf` | `node2/804fbf` | `node2/804fbf` |
| 12 | **heal the network** |  |  |  |
| 13 | wait 15000ms for the registry to react |  |  |  |
| 14 | `lookup` on all nodes (database_lost/service) - **agree** | `node2/804fbf` | `node2/804fbf` | `node2/804fbf` |

### group

#### baseline

Healthy cluster. Establishes what the registry does when nothing is wrong: a name is visible everywhere, a second claim is refused, and the name is free again after an orderly stop.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (baseline/service) | started `node1/b6c8dc` |  |  |
| 2 | `lookup` on all nodes (baseline/service) - **disagree** | `node1/b6c8dc` | `not_found` | `not_found` |
| 3 | _A second node claims the same name._ |  |  |  |
| 4 | `start_process` on n2 (baseline/service) |  | error: `taken` |  |
| 5 | `lookup` on all nodes (baseline/service) - **agree** | `node1/b6c8dc` | `node1/b6c8dc` | `node1/b6c8dc` |
| 6 | `renew_lease` on n2 (baseline/service) |  | `not_supported` |  |
| 7 | `stop_process` on n1 (baseline/service) | `stopped` |  |  |
| 8 | `lookup` on all nodes (baseline/service) - **disagree** | `not_found` | `node1/b6c8dc` | `node1/b6c8dc` |

#### process death

The registered process is killed without unregistering. Shows whether the registry monitors the process and frees the name by itself, or keeps handing out a dead pid.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (process_death/service) | started `node1/5beed3` |  |  |
| 2 | `lookup` on all nodes (process_death/service) - **disagree** | `node1/5beed3` | `not_found` | `not_found` |
| 3 | `kill_process` on n1 (process_death/service) | `killed` |  |  |
| 4 | wait 2000ms |  |  |  |
| 5 | `lookup` on all nodes (process_death/service) - **agree** | `not_found` | `not_found` | `not_found` |
| 6 | _Another node tries to take the name over._ |  |  |  |
| 7 | `start_process` on n2 (process_death/service) |  | started `node2/75e17c` |  |
| 8 | `lookup` on all nodes (process_death/service) - **disagree** | `not_found` | `node2/75e17c` | `not_found` |

#### lease expiry

The lease is shortened to 3s and then nobody renews it. Registries without leases keep the name forever; a lease based registry drops it and lets another node take over.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | set lease_ms to 3000 |  |  |  |
| 2 | `start_process` on n1 (lease_expiry/service) | started `node1/bcf409` |  |  |
| 3 | `lookup` on all nodes (lease_expiry/service) - **disagree** | `node1/bcf409` | `not_found` | `not_found` |
| 4 | `renew_lease` on n1 (lease_expiry/service) | `not_supported` |  |  |
| 5 | _Wait past the lease without renewing._ |  |  |  |
| 6 | wait 6000ms |  |  |  |
| 7 | `lookup` on all nodes (lease_expiry/service) - **agree** | `node1/bcf409` | `node1/bcf409` | `node1/bcf409` |
| 8 | _Another node tries to take the name over._ |  |  |  |
| 9 | `start_process` on n2 (lease_expiry/service) |  | error: `taken` |  |
| 10 | `lookup` on all nodes (lease_expiry/service) - **agree** | `node1/bcf409` | `node1/bcf409` | `node1/bcf409` |

#### symmetric split

The cluster splits into a majority (n1, n2) and a minority (n3). The owner is on the majority side. The minority tries to claim the same name, then the split is healed.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (symmetric_split/service) | started `node1/11d941` |  |  |
| 2 | `lookup` on all nodes (symmetric_split/service) - **disagree** | `node1/11d941` | `not_found` | `not_found` |
| 3 | **isolate n3** |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (symmetric_split/service) - **disagree** | `node1/11d941` | `node1/11d941` | `not_found` |
| 6 | _The minority side claims the same name._ |  |  |  |
| 7 | `start_process` on n3 (symmetric_split/service) |  |  | started `node3/18198e` |
| 8 | `lookup` on all nodes (symmetric_split/service) - **disagree** | `node1/11d941` | `node1/11d941` | `node3/18198e` |
| 9 | `renew_lease` on n1 (symmetric_split/service) | `not_supported` |  |  |
| 10 | **heal the network** |  |  |  |
| 11 | wait 15000ms for the registry to react |  |  |  |
| 12 | _After healing: does the cluster agree again?_ |  |  |  |
| 13 | `lookup` on all nodes (symmetric_split/service) - **agree** | `node3/18198e` | `node3/18198e` | `node3/18198e` |

#### owner isolated

The node owning the name (n3) is cut off from the majority. This is the failover case: can the majority take the name over, and what happens to the old owner when the split heals?

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n3 (owner_isolated/service) |  |  | started `node3/7c8a62` |
| 2 | `lookup` on all nodes (owner_isolated/service) - **disagree** | `not_found` | `not_found` | `node3/7c8a62` |
| 3 | **isolate n3** |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (owner_isolated/service) - **disagree** | `not_found` | `not_found` | `node3/7c8a62` |
| 6 | _The majority side tries to take the name over._ |  |  |  |
| 7 | `start_process` on n1 (owner_isolated/service) | started `node1/a60239` |  |  |
| 8 | `lookup` on all nodes (owner_isolated/service) - **disagree** | `node1/a60239` | `not_found` | `node3/7c8a62` |
| 9 | **heal the network** |  |  |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | _After healing: one owner, or two?_ |  |  |  |
| 12 | `lookup` on all nodes (owner_isolated/service) - **agree** | `node1/a60239` | `node1/a60239` | `node1/a60239` |

#### one sided split

n1 stops hearing from n3, but n3 still hears n1. The two nodes disagree about whether the other one is alive, which is the case that breaks membership algorithms assuming symmetric failures.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (one_sided_split/service) | started `node1/2a4164` |  |  |
| 2 | `lookup` on all nodes (one_sided_split/service) - **disagree** | `node1/2a4164` | `not_found` | `not_found` |
| 3 | **cut n1 <- n3** (one sided: n3 still hears n1) |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (one_sided_split/service) - **disagree** | `node1/2a4164` | `not_found` | `not_found` |
| 6 | _n3 claims the same name while it still believes n1 is up._ |  |  |  |
| 7 | `start_process` on n3 (one_sided_split/service) |  |  | started `node3/25f275` |
| 8 | `lookup` on all nodes (one_sided_split/service) - **disagree** | `node1/2a4164` | `not_found` | `node3/25f275` |
| 9 | **heal the network** |  |  |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | `lookup` on all nodes (one_sided_split/service) - **agree** | `node3/25f275` | `node3/25f275` | `node3/25f275` |

#### full split

Every node is cut off from every other node, so nobody has a majority. All three then try to own the same name at the same time, and the split is healed with three candidate owners.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (full_split/service) | started `node1/68ac56` |  |  |
| 2 | `lookup` on all nodes (full_split/service) - **disagree** | `node1/68ac56` | `not_found` | `not_found` |
| 3 | **cut n1 <-> n2** |  |  |  |
| 4 | **cut n1 <-> n3** |  |  |  |
| 5 | **cut n2 <-> n3** |  |  |  |
| 6 | wait 15000ms for the registry to react |  |  |  |
| 7 | `lookup` on all nodes (full_split/service) - **disagree** | `node1/68ac56` | `not_found` | `not_found` |
| 8 | _Both other nodes claim the name as well._ |  |  |  |
| 9 | `start_process` on n2 (full_split/service) |  | started `node2/4da8b2` |  |
| 10 | `start_process` on n3 (full_split/service) |  |  | started `node3/e44cf1` |
| 11 | `lookup` on all nodes (full_split/service) - **disagree** | `node1/68ac56` | `node2/4da8b2` | `node3/e44cf1` |
| 12 | **heal the network** |  |  |  |
| 13 | wait 15000ms for the registry to react |  |  |  |
| 14 | _After healing: how many owners survive?_ |  |  |  |
| 15 | `lookup` on all nodes (full_split/service) - **agree** | `node2/4da8b2` | `node2/4da8b2` | `node2/4da8b2` |

#### database lost

The node owning the name loses its connection to Postgres while the BEAM cluster stays intact. Only matters for a registry that keeps its state in the database; for the others nothing happens, which is itself the result.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (database_lost/service) | started `node1/84dea6` |  |  |
| 2 | wait 15000ms for the registry to react |  |  |  |
| 3 | `lookup` on all nodes (database_lost/service) - **agree** | `node1/84dea6` | `node1/84dea6` | `node1/84dea6` |
| 4 | _n1 can still reach the other nodes, but not the database._ |  |  |  |
| 5 | **cut n1 <- postgres** |  |  |  |
| 6 | wait 15000ms for the registry to react |  |  |  |
| 7 | `lookup` on all nodes (database_lost/service) - **agree** | `node1/84dea6` | `node1/84dea6` | `node1/84dea6` |
| 8 | _Does another node take the name over?_ |  |  |  |
| 9 | `start_process` on n2 (database_lost/service) |  | error: `taken` |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | `lookup` on all nodes (database_lost/service) - **agree** | `node1/84dea6` | `node1/84dea6` | `node1/84dea6` |
| 12 | **heal the network** |  |  |  |
| 13 | wait 15000ms for the registry to react |  |  |  |
| 14 | `lookup` on all nodes (database_lost/service) - **agree** | `node1/84dea6` | `node1/84dea6` | `node1/84dea6` |

### locker

#### baseline

Healthy cluster. Establishes what the registry does when nothing is wrong: a name is visible everywhere, a second claim is refused, and the name is free again after an orderly stop.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (baseline/service) | started `node1/9a0e78` |  |  |
| 2 | `lookup` on all nodes (baseline/service) - **agree** | `node1/9a0e78` | `node1/9a0e78` | `node1/9a0e78` |
| 3 | _A second node claims the same name._ |  |  |  |
| 4 | `start_process` on n2 (baseline/service) |  | error: `no_quorum` |  |
| 5 | `lookup` on all nodes (baseline/service) - **agree** | `node1/9a0e78` | `node1/9a0e78` | `node1/9a0e78` |
| 6 | `renew_lease` on n2 (baseline/service) |  | `renewed` |  |
| 7 | `stop_process` on n1 (baseline/service) | `stopped` |  |  |
| 8 | `lookup` on all nodes (baseline/service) - **agree** | `not_found` | `not_found` | `not_found` |

#### process death

The registered process is killed without unregistering. Shows whether the registry monitors the process and frees the name by itself, or keeps handing out a dead pid.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (process_death/service) | started `node1/d70750` |  |  |
| 2 | `lookup` on all nodes (process_death/service) - **agree** | `node1/d70750` | `node1/d70750` | `node1/d70750` |
| 3 | `kill_process` on n1 (process_death/service) | `killed` |  |  |
| 4 | wait 2000ms |  |  |  |
| 5 | `lookup` on all nodes (process_death/service) - **agree** | `node1/d70750` | `node1/d70750` | `node1/d70750` |
| 6 | _Another node tries to take the name over._ |  |  |  |
| 7 | `start_process` on n2 (process_death/service) |  | error: `no_quorum` |  |
| 8 | `lookup` on all nodes (process_death/service) - **agree** | `node1/d70750` | `node1/d70750` | `node1/d70750` |

#### lease expiry

The lease is shortened to 3s and then nobody renews it. Registries without leases keep the name forever; a lease based registry drops it and lets another node take over.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | set lease_ms to 3000 |  |  |  |
| 2 | `start_process` on n1 (lease_expiry/service) | started `node1/0bc2d0` |  |  |
| 3 | `lookup` on all nodes (lease_expiry/service) - **agree** | `node1/0bc2d0` | `node1/0bc2d0` | `node1/0bc2d0` |
| 4 | `renew_lease` on n1 (lease_expiry/service) | `renewed` |  |  |
| 5 | _Wait past the lease without renewing._ |  |  |  |
| 6 | wait 6000ms |  |  |  |
| 7 | `lookup` on all nodes (lease_expiry/service) - **agree** | `not_found` | `not_found` | `not_found` |
| 8 | _Another node tries to take the name over._ |  |  |  |
| 9 | `start_process` on n2 (lease_expiry/service) |  | started `node2/1b4dc2` |  |
| 10 | `lookup` on all nodes (lease_expiry/service) - **agree** | `node2/1b4dc2` | `node2/1b4dc2` | `node2/1b4dc2` |

#### symmetric split

The cluster splits into a majority (n1, n2) and a minority (n3). The owner is on the majority side. The minority tries to claim the same name, then the split is healed.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (symmetric_split/service) | started `node1/b712ba` |  |  |
| 2 | `lookup` on all nodes (symmetric_split/service) - **agree** | `node1/b712ba` | `node1/b712ba` | `node1/b712ba` |
| 3 | **isolate n3** |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (symmetric_split/service) - **agree** | `node1/b712ba` | `node1/b712ba` | `node1/b712ba` |
| 6 | _The minority side claims the same name._ |  |  |  |
| 7 | `start_process` on n3 (symmetric_split/service) |  |  | error: `no_quorum` _(7012ms)_ |
| 8 | `lookup` on all nodes (symmetric_split/service) - **agree** | `node1/b712ba` | `node1/b712ba` | `node1/b712ba` |
| 9 | `renew_lease` on n1 (symmetric_split/service) | `renewed` _(7008ms)_ |  |  |
| 10 | **heal the network** |  |  |  |
| 11 | wait 15000ms for the registry to react |  |  |  |
| 12 | _After healing: does the cluster agree again?_ |  |  |  |
| 13 | `lookup` on all nodes (symmetric_split/service) - **agree** | `node1/b712ba` | `node1/b712ba` | `node1/b712ba` |

#### owner isolated

The node owning the name (n3) is cut off from the majority. This is the failover case: can the majority take the name over, and what happens to the old owner when the split heals?

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n3 (owner_isolated/service) |  |  | started `node3/540222` |
| 2 | `lookup` on all nodes (owner_isolated/service) - **agree** | `node3/540222` | `node3/540222` | `node3/540222` |
| 3 | **isolate n3** |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (owner_isolated/service) - **agree** | `node3/540222` | `node3/540222` | `node3/540222` |
| 6 | _The majority side tries to take the name over._ |  |  |  |
| 7 | `start_process` on n1 (owner_isolated/service) | error: `no_quorum` _(7008ms)_ |  |  |
| 8 | `lookup` on all nodes (owner_isolated/service) - **agree** | `node3/540222` | `node3/540222` | `node3/540222` |
| 9 | **heal the network** |  |  |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | _After healing: one owner, or two?_ |  |  |  |
| 12 | `lookup` on all nodes (owner_isolated/service) - **agree** | `node3/540222` | `node3/540222` | `node3/540222` |

#### one sided split

n1 stops hearing from n3, but n3 still hears n1. The two nodes disagree about whether the other one is alive, which is the case that breaks membership algorithms assuming symmetric failures.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (one_sided_split/service) | started `node1/8290bb` |  |  |
| 2 | `lookup` on all nodes (one_sided_split/service) - **agree** | `node1/8290bb` | `node1/8290bb` | `node1/8290bb` |
| 3 | **cut n1 <- n3** (one sided: n3 still hears n1) |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (one_sided_split/service) - **agree** | `node1/8290bb` | `node1/8290bb` | `node1/8290bb` |
| 6 | _n3 claims the same name while it still believes n1 is up._ |  |  |  |
| 7 | `start_process` on n3 (one_sided_split/service) |  |  | error: `no_quorum` _(7006ms)_ |
| 8 | `lookup` on all nodes (one_sided_split/service) - **agree** | `node1/8290bb` | `node1/8290bb` | `node1/8290bb` |
| 9 | **heal the network** |  |  |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | `lookup` on all nodes (one_sided_split/service) - **agree** | `node1/8290bb` | `node1/8290bb` | `node1/8290bb` |

#### full split

Every node is cut off from every other node, so nobody has a majority. All three then try to own the same name at the same time, and the split is healed with three candidate owners.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (full_split/service) | started `node1/bb8474` |  |  |
| 2 | `lookup` on all nodes (full_split/service) - **agree** | `node1/bb8474` | `node1/bb8474` | `node1/bb8474` |
| 3 | **cut n1 <-> n2** |  |  |  |
| 4 | **cut n1 <-> n3** |  |  |  |
| 5 | **cut n2 <-> n3** |  |  |  |
| 6 | wait 15000ms for the registry to react |  |  |  |
| 7 | `lookup` on all nodes (full_split/service) - **agree** | `node1/bb8474` | `node1/bb8474` | `node1/bb8474` |
| 8 | _Both other nodes claim the name as well._ |  |  |  |
| 9 | `start_process` on n2 (full_split/service) |  | error: `no_quorum` _(7008ms)_ |  |
| 10 | `start_process` on n3 (full_split/service) |  |  | error: `no_quorum` _(7008ms)_ |
| 11 | `lookup` on all nodes (full_split/service) - **agree** | `node1/bb8474` | `node1/bb8474` | `node1/bb8474` |
| 12 | **heal the network** |  |  |  |
| 13 | wait 15000ms for the registry to react |  |  |  |
| 14 | _After healing: how many owners survive?_ |  |  |  |
| 15 | `lookup` on all nodes (full_split/service) - **agree** | `node1/bb8474` | `node1/bb8474` | `node1/bb8474` |

#### database lost

The node owning the name loses its connection to Postgres while the BEAM cluster stays intact. Only matters for a registry that keeps its state in the database; for the others nothing happens, which is itself the result.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (database_lost/service) | started `node1/3a7f4c` |  |  |
| 2 | wait 15000ms for the registry to react |  |  |  |
| 3 | `lookup` on all nodes (database_lost/service) - **agree** | `node1/3a7f4c` | `node1/3a7f4c` | `node1/3a7f4c` |
| 4 | _n1 can still reach the other nodes, but not the database._ |  |  |  |
| 5 | **cut n1 <- postgres** |  |  |  |
| 6 | wait 15000ms for the registry to react |  |  |  |
| 7 | `lookup` on all nodes (database_lost/service) - **agree** | `node1/3a7f4c` | `node1/3a7f4c` | `node1/3a7f4c` |
| 8 | _Does another node take the name over?_ |  |  |  |
| 9 | `start_process` on n2 (database_lost/service) |  | error: `no_quorum` |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | `lookup` on all nodes (database_lost/service) - **agree** | `node1/3a7f4c` | `node1/3a7f4c` | `node1/3a7f4c` |
| 12 | **heal the network** |  |  |  |
| 13 | wait 15000ms for the registry to react |  |  |  |
| 14 | `lookup` on all nodes (database_lost/service) - **agree** | `node1/3a7f4c` | `node1/3a7f4c` | `node1/3a7f4c` |

### highlander_pg

#### baseline

Healthy cluster. Establishes what the registry does when nothing is wrong: a name is visible everywhere, a second claim is refused, and the name is free again after an orderly stop.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (baseline/service) | started `node1/6f7d24` _(131ms)_ |  |  |
| 2 | `lookup` on all nodes (baseline/service) - **disagree** | `node1/6f7d24` | `not_found` | `not_found` |
| 3 | _A second node claims the same name._ |  |  |  |
| 4 | `start_process` on n2 (baseline/service) |  | `pending` _(3020ms)_ |  |
| 5 | `lookup` on all nodes (baseline/service) - **disagree** | `node1/6f7d24` | `not_found` | `not_found` |
| 6 | `renew_lease` on n2 (baseline/service) |  | `not_found` |  |
| 7 | `stop_process` on n1 (baseline/service) | `stopped` |  |  |
| 8 | `lookup` on all nodes (baseline/service) - **agree** | `not_found` | `not_found` | `not_found` |

#### process death

The registered process is killed without unregistering. Shows whether the registry monitors the process and frees the name by itself, or keeps handing out a dead pid.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (process_death/service) | started `node1/7839a7` _(107ms)_ |  |  |
| 2 | `lookup` on all nodes (process_death/service) - **disagree** | `node1/7839a7` | `not_found` | `not_found` |
| 3 | `kill_process` on n1 (process_death/service) | `killed` |  |  |
| 4 | wait 2000ms |  |  |  |
| 5 | `lookup` on all nodes (process_death/service) - **agree** | `not_found` | `not_found` | `not_found` |
| 6 | _Another node tries to take the name over._ |  |  |  |
| 7 | `start_process` on n2 (process_death/service) |  | started `node2/d7ae72` _(101ms)_ |  |
| 8 | `lookup` on all nodes (process_death/service) - **disagree** | `not_found` | `node2/d7ae72` | `not_found` |

#### lease expiry

The lease is shortened to 3s and then nobody renews it. Registries without leases keep the name forever; a lease based registry drops it and lets another node take over.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | set lease_ms to 3000 |  |  |  |
| 2 | `start_process` on n1 (lease_expiry/service) | started `node1/f3edf8` _(104ms)_ |  |  |
| 3 | `lookup` on all nodes (lease_expiry/service) - **disagree** | `node1/f3edf8` | `not_found` | `not_found` |
| 4 | `renew_lease` on n1 (lease_expiry/service) | `not_supported` |  |  |
| 5 | _Wait past the lease without renewing._ |  |  |  |
| 6 | wait 6000ms |  |  |  |
| 7 | `lookup` on all nodes (lease_expiry/service) - **disagree** | `node1/f3edf8` | `not_found` | `not_found` |
| 8 | _Another node tries to take the name over._ |  |  |  |
| 9 | `start_process` on n2 (lease_expiry/service) |  | `pending` _(3064ms)_ |  |
| 10 | `lookup` on all nodes (lease_expiry/service) - **disagree** | `node1/f3edf8` | `not_found` | `not_found` |

#### symmetric split

The cluster splits into a majority (n1, n2) and a minority (n3). The owner is on the majority side. The minority tries to claim the same name, then the split is healed.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (symmetric_split/service) | started `node1/6de709` _(107ms)_ |  |  |
| 2 | `lookup` on all nodes (symmetric_split/service) - **disagree** | `node1/6de709` | `not_found` | `not_found` |
| 3 | **isolate n3** |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (symmetric_split/service) - **disagree** | `node1/6de709` | `not_found` | `not_found` |
| 6 | _The minority side claims the same name._ |  |  |  |
| 7 | `start_process` on n3 (symmetric_split/service) |  |  | `pending` _(3015ms)_ |
| 8 | `lookup` on all nodes (symmetric_split/service) - **disagree** | `node1/6de709` | `not_found` | `not_found` |
| 9 | `renew_lease` on n1 (symmetric_split/service) | `not_supported` |  |  |
| 10 | **heal the network** |  |  |  |
| 11 | wait 15000ms for the registry to react |  |  |  |
| 12 | _After healing: does the cluster agree again?_ |  |  |  |
| 13 | `lookup` on all nodes (symmetric_split/service) - **disagree** | `node1/6de709` | `not_found` | `not_found` |

#### owner isolated

The node owning the name (n3) is cut off from the majority. This is the failover case: can the majority take the name over, and what happens to the old owner when the split heals?

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n3 (owner_isolated/service) |  |  | started `node3/bfae24` _(105ms)_ |
| 2 | `lookup` on all nodes (owner_isolated/service) - **disagree** | `not_found` | `not_found` | `node3/bfae24` |
| 3 | **isolate n3** |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (owner_isolated/service) - **disagree** | `not_found` | `not_found` | `node3/bfae24` |
| 6 | _The majority side tries to take the name over._ |  |  |  |
| 7 | `start_process` on n1 (owner_isolated/service) | `pending` _(3089ms)_ |  |  |
| 8 | `lookup` on all nodes (owner_isolated/service) - **disagree** | `not_found` | `not_found` | `node3/bfae24` |
| 9 | **heal the network** |  |  |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | _After healing: one owner, or two?_ |  |  |  |
| 12 | `lookup` on all nodes (owner_isolated/service) - **disagree** | `not_found` | `not_found` | `node3/bfae24` |

#### one sided split

n1 stops hearing from n3, but n3 still hears n1. The two nodes disagree about whether the other one is alive, which is the case that breaks membership algorithms assuming symmetric failures.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (one_sided_split/service) | started `node1/361bc8` _(107ms)_ |  |  |
| 2 | `lookup` on all nodes (one_sided_split/service) - **disagree** | `node1/361bc8` | `not_found` | `not_found` |
| 3 | **cut n1 <- n3** (one sided: n3 still hears n1) |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (one_sided_split/service) - **disagree** | `node1/361bc8` | `not_found` | `not_found` |
| 6 | _n3 claims the same name while it still believes n1 is up._ |  |  |  |
| 7 | `start_process` on n3 (one_sided_split/service) |  |  | `pending` _(3011ms)_ |
| 8 | `lookup` on all nodes (one_sided_split/service) - **disagree** | `node1/361bc8` | `not_found` | `not_found` |
| 9 | **heal the network** |  |  |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | `lookup` on all nodes (one_sided_split/service) - **disagree** | `node1/361bc8` | `not_found` | `not_found` |

#### full split

Every node is cut off from every other node, so nobody has a majority. All three then try to own the same name at the same time, and the split is healed with three candidate owners.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (full_split/service) | started `node1/6ee14d` _(107ms)_ |  |  |
| 2 | `lookup` on all nodes (full_split/service) - **disagree** | `node1/6ee14d` | `not_found` | `not_found` |
| 3 | **cut n1 <-> n2** |  |  |  |
| 4 | **cut n1 <-> n3** |  |  |  |
| 5 | **cut n2 <-> n3** |  |  |  |
| 6 | wait 15000ms for the registry to react |  |  |  |
| 7 | `lookup` on all nodes (full_split/service) - **disagree** | `node1/6ee14d` | `not_found` | `not_found` |
| 8 | _Both other nodes claim the name as well._ |  |  |  |
| 9 | `start_process` on n2 (full_split/service) |  | `pending` _(3008ms)_ |  |
| 10 | `start_process` on n3 (full_split/service) |  |  | `pending` _(3003ms)_ |
| 11 | `lookup` on all nodes (full_split/service) - **disagree** | `node1/6ee14d` | `not_found` | `not_found` |
| 12 | **heal the network** |  |  |  |
| 13 | wait 15000ms for the registry to react |  |  |  |
| 14 | _After healing: how many owners survive?_ |  |  |  |
| 15 | `lookup` on all nodes (full_split/service) - **disagree** | `node1/6ee14d` | `not_found` | `not_found` |

#### database lost

The node owning the name loses its connection to Postgres while the BEAM cluster stays intact. Only matters for a registry that keeps its state in the database; for the others nothing happens, which is itself the result.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (database_lost/service) | started `node1/fe78b0` _(104ms)_ |  |  |
| 2 | wait 15000ms for the registry to react |  |  |  |
| 3 | `lookup` on all nodes (database_lost/service) - **disagree** | `node1/fe78b0` | `not_found` | `not_found` |
| 4 | _n1 can still reach the other nodes, but not the database._ |  |  |  |
| 5 | **cut n1 <- postgres** |  |  |  |
| 6 | wait 15000ms for the registry to react |  |  |  |
| 7 | `lookup` on all nodes (database_lost/service) - **disagree** | `node1/fe78b0` | `not_found` | `not_found` |
| 8 | _Does another node take the name over?_ |  |  |  |
| 9 | `start_process` on n2 (database_lost/service) |  | `pending` _(3102ms)_ |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | `lookup` on all nodes (database_lost/service) - **disagree** | `node1/fe78b0` | `not_found` | `not_found` |
| 12 | **heal the network** |  |  |  |
| 13 | wait 15000ms for the registry to react |  |  |  |
| 14 | `lookup` on all nodes (database_lost/service) - **disagree** | `node1/fe78b0` | `not_found` | `not_found` |

