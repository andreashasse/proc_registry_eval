# Distributed process registry evaluation

A three node Erlang cluster in docker. The network between the nodes is cut and healed with iptables while a fixed list of actions is run against each registry, and every answer every node gives is written down.

Registries in this run: global, gproc, syn, horde, locker, highlander_pg. Produced by `./run.sh`; nothing in this file is written by hand.

## Environment

| Setting | global | gproc | syn | horde | locker | highlander_pg |
| --- | --- | --- | --- | --- | --- | --- |
| run started | 2026-08-10T07:08:25Z | 2026-08-10T07:31:55Z | 2026-08-10T07:16:08Z | 2026-08-10T08:01:13Z | 2026-08-10T07:39:42Z | 2026-08-10T07:25:21Z |
| OTP release | 27 | 27 | 27 | 27 | 27 | 27 |
| net_ticktime | 5 | 5 | 5 | 5 | 5 | 5 |
| kernel prevent_overlapping_partitions | true | true | true | true | true | true |
| registry version | kernel 10.2.7.4 | gproc 1.3.0 | syn 3.4.2 | horde 0.10.0 | locker 6 | highlander_pg 1.0.8 |
| settle after network change | 15000 | 15000 | 15000 | 15000 | 15000 | 15000 |
| default lease | 60000 | 60000 | 60000 | 60000 | 60000 | 60000 |
| action timeout | 20000 | 20000 | 20000 | 20000 | 20000 | 20000 |
| wait for a pending claim | 3000 | 3000 | 3000 | 3000 | 3000 | 3000 |
| horde keys | - | - | - | unique | - | - |
| horde members | - | - | - | auto, the visible nodes | - | - |
| locker write quorum | - | - | - | - | 2 of 3 masters | - |
| locker call timeout | - | - | - | - | 5000ms | - |
| highlander_pg database | - | - | - | - | - | workbench@postgres |
| highlander_pg polling interval | - | - | - | - | - | 300ms |

## Summary

Every `lookup on all nodes` step asks all three nodes who owns the name and compares the answers. `agree n/m` counts how many of those checks got the same answer from every node. `owners` is the highest number of different owners seen at the same time, so more than one means the cluster had a split brain. `refused` counts the actions the registry answered `{error, Reason}` to, such as a second claim on a name that is already owned; `timed out` counts the ones it did not answer at all.

| Scenario | global | gproc | syn | horde | locker | highlander_pg |
| --- | --- | --- | --- | --- | --- | --- |
| baseline | agree 3/3, 1 owner, 1 refused | agree 3/3, 1 owner, 1 refused | agree 3/3, 1 owner, 1 refused | agree 0/3, 2 owners | agree 3/3, 1 owner, 1 refused | agree 1/3, 1 owner |
| process death | agree 3/3, 1 owner | agree 3/3, 1 owner | agree 3/3, 1 owner | agree 1/3, 1 owner | agree 3/3, 1 owner, 1 refused | agree 1/3, 1 owner |
| lease expiry | agree 3/3, 1 owner, 1 refused | agree 3/3, 1 owner, 1 refused | agree 3/3, 1 owner, 1 refused | agree 1/3, 2 owners | agree 3/3, 1 owner | agree 0/3, 1 owner |
| symmetric split | agree 2/4, 2 owners | agree 2/4, 2 owners | agree 2/4, 2 owners | agree 1/4, 2 owners | agree 4/4, 1 owner, 1 refused | agree 0/4, 1 owner |
| owner isolated | agree 2/4, 2 owners | agree 2/4, 2 owners | agree 2/4, 2 owners | agree 1/4, 2 owners | agree 4/4, 1 owner, 1 refused | agree 0/4, 1 owner |
| one sided split | agree 2/4, 2 owners | agree 3/4, 2 owners | agree 2/4, 2 owners | agree 1/4, 2 owners | agree 4/4, 1 owner, 1 refused | agree 0/4, 1 owner |
| full split | agree 2/4, 3 owners | agree 2/4, 3 owners | agree 2/4, 3 owners | agree 1/4, 3 owners | agree 4/4, 1 owner, 2 refused | agree 0/4, 1 owner |
| database lost | agree 4/4, 1 owner, 1 refused | agree 0/4, 1 owner, 1 refused | agree 4/4, 1 owner, 1 refused | agree 4/4, 1 owner | agree 4/4, 1 owner, 1 refused | agree 0/4, 1 owner |

## Observations

| Question | global | gproc | syn | horde | locker | highlander_pg |
| --- | --- | --- | --- | --- | --- | --- |
| Are leases supported? | no | no | no | no | yes | no |
| Slowest single action | 6ms | 5001ms | 7ms | 9ms | 7015ms | 3098ms |
| Claims the registry refused | 3 | 3 | 3 | 0 | 8 | 0 |
| Actions that timed out or crashed | 0 | 0 | 0 | 0 | 0 | 0 |
| Checks where the nodes disagreed | 8 | 11 | 8 | 19 | 0 | 27 |
| Highest number of owners at the same time | 3 | 3 | 3 | 3 | 1 | 1 |

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
| 7 | `start_process` on n2 (process_death/service) |  | started `node2/e7d158` |  |
| 8 | `lookup` on all nodes (process_death/service) - **agree** | `node2/e7d158` | `node2/e7d158` | `node2/e7d158` |

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
| 7 | `start_process` on n3 (symmetric_split/service) |  |  | started `node3/597101` |
| 8 | `lookup` on all nodes (symmetric_split/service) - **disagree** | `node1/22a9d4` | `node1/22a9d4` | `node3/597101` |
| 9 | `renew_lease` on n1 (symmetric_split/service) | `not_supported` |  |  |
| 10 | **heal the network** |  |  |  |
| 11 | wait 15000ms for the registry to react |  |  |  |
| 12 | _After healing: does the cluster agree again?_ |  |  |  |
| 13 | `lookup` on all nodes (symmetric_split/service) - **agree** | `node1/22a9d4` | `node1/22a9d4` | `node1/22a9d4` |

#### owner isolated

The node owning the name (n3) is cut off from the majority. This is the failover case: can the majority take the name over, and what happens to the old owner when the split heals?

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n3 (owner_isolated/service) |  |  | started `node3/18198e` |
| 2 | `lookup` on all nodes (owner_isolated/service) - **agree** | `node3/18198e` | `node3/18198e` | `node3/18198e` |
| 3 | **isolate n3** |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (owner_isolated/service) - **disagree** | `not_found` | `not_found` | `node3/18198e` |
| 6 | _The majority side tries to take the name over._ |  |  |  |
| 7 | `start_process` on n1 (owner_isolated/service) | started `node1/954d37` |  |  |
| 8 | `lookup` on all nodes (owner_isolated/service) - **disagree** | `node1/954d37` | `node1/954d37` | `node3/18198e` |
| 9 | **heal the network** |  |  |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | _After healing: one owner, or two?_ |  |  |  |
| 12 | `lookup` on all nodes (owner_isolated/service) - **agree** | `node1/954d37` | `node1/954d37` | `node1/954d37` |

#### one sided split

n1 stops hearing from n3, but n3 still hears n1. The two nodes disagree about whether the other one is alive, which is the case that breaks membership algorithms assuming symmetric failures.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (one_sided_split/service) | started `node1/6de709` |  |  |
| 2 | `lookup` on all nodes (one_sided_split/service) - **agree** | `node1/6de709` | `node1/6de709` | `node1/6de709` |
| 3 | **cut n1 <- n3** (one sided: n3 still hears n1) |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (one_sided_split/service) - **disagree** | `node1/6de709` | `not_found` | `not_found` |
| 6 | _n3 claims the same name while it still believes n1 is up._ |  |  |  |
| 7 | `start_process` on n3 (one_sided_split/service) |  |  | started `node3/d0dfff` |
| 8 | `lookup` on all nodes (one_sided_split/service) - **disagree** | `node1/6de709` | `not_found` | `node3/d0dfff` |
| 9 | **heal the network** |  |  |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | `lookup` on all nodes (one_sided_split/service) - **agree** | `node1/6de709` | `node1/6de709` | `node1/6de709` |

#### full split

Every node is cut off from every other node, so nobody has a majority. All three then try to own the same name at the same time, and the split is healed with three candidate owners.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (full_split/service) | started `node1/28737d` |  |  |
| 2 | `lookup` on all nodes (full_split/service) - **agree** | `node1/28737d` | `node1/28737d` | `node1/28737d` |
| 3 | **cut n1 <-> n2** |  |  |  |
| 4 | **cut n1 <-> n3** |  |  |  |
| 5 | **cut n2 <-> n3** |  |  |  |
| 6 | wait 15000ms for the registry to react |  |  |  |
| 7 | `lookup` on all nodes (full_split/service) - **disagree** | `node1/28737d` | `not_found` | `not_found` |
| 8 | _Both other nodes claim the name as well._ |  |  |  |
| 9 | `start_process` on n2 (full_split/service) |  | started `node2/261354` |  |
| 10 | `start_process` on n3 (full_split/service) |  |  | started `node3/3d52ab` |
| 11 | `lookup` on all nodes (full_split/service) - **disagree** | `node1/28737d` | `node2/261354` | `node3/3d52ab` |
| 12 | **heal the network** |  |  |  |
| 13 | wait 15000ms for the registry to react |  |  |  |
| 14 | _After healing: how many owners survive?_ |  |  |  |
| 15 | `lookup` on all nodes (full_split/service) - **agree** | `node1/28737d` | `node1/28737d` | `node1/28737d` |

#### database lost

The node owning the name loses its connection to Postgres while the BEAM cluster stays intact. Only matters for a registry that keeps its state in the database; for the others nothing happens, which is itself the result.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (database_lost/service) | started `node1/f69392` |  |  |
| 2 | wait 15000ms for the registry to react |  |  |  |
| 3 | `lookup` on all nodes (database_lost/service) - **agree** | `node1/f69392` | `node1/f69392` | `node1/f69392` |
| 4 | _n1 can still reach the other nodes, but not the database._ |  |  |  |
| 5 | **cut n1 <- postgres** |  |  |  |
| 6 | wait 15000ms for the registry to react |  |  |  |
| 7 | `lookup` on all nodes (database_lost/service) - **agree** | `node1/f69392` | `node1/f69392` | `node1/f69392` |
| 8 | _Does another node take the name over?_ |  |  |  |
| 9 | `start_process` on n2 (database_lost/service) |  | error: `name_taken` |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | `lookup` on all nodes (database_lost/service) - **agree** | `node1/f69392` | `node1/f69392` | `node1/f69392` |
| 12 | **heal the network** |  |  |  |
| 13 | wait 15000ms for the registry to react |  |  |  |
| 14 | `lookup` on all nodes (database_lost/service) - **agree** | `node1/f69392` | `node1/f69392` | `node1/f69392` |

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
| 7 | `start_process` on n2 (process_death/service) |  | started `node2/ae69eb` |  |
| 8 | `lookup` on all nodes (process_death/service) - **agree** | `node2/ae69eb` | `node2/ae69eb` | `node2/ae69eb` |

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
| 7 | `start_process` on n3 (symmetric_split/service) |  |  | started `node3/8451d8` |
| 8 | `lookup` on all nodes (symmetric_split/service) - **disagree** | `node1/cb9d65` | `node1/cb9d65` | `node3/8451d8` |
| 9 | `renew_lease` on n1 (symmetric_split/service) | `not_supported` |  |  |
| 10 | **heal the network** |  |  |  |
| 11 | wait 15000ms for the registry to react |  |  |  |
| 12 | _After healing: does the cluster agree again?_ |  |  |  |
| 13 | `lookup` on all nodes (symmetric_split/service) - **agree** | `node3/8451d8` | `node3/8451d8` | `node3/8451d8` |

#### owner isolated

The node owning the name (n3) is cut off from the majority. This is the failover case: can the majority take the name over, and what happens to the old owner when the split heals?

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n3 (owner_isolated/service) |  |  | started `node3/1517fb` |
| 2 | `lookup` on all nodes (owner_isolated/service) - **agree** | `node3/1517fb` | `node3/1517fb` | `node3/1517fb` |
| 3 | **isolate n3** |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (owner_isolated/service) - **disagree** | `not_found` | `not_found` | `node3/1517fb` |
| 6 | _The majority side tries to take the name over._ |  |  |  |
| 7 | `start_process` on n1 (owner_isolated/service) | started `node1/fee2b1` |  |  |
| 8 | `lookup` on all nodes (owner_isolated/service) - **disagree** | `node1/fee2b1` | `node1/fee2b1` | `node3/1517fb` |
| 9 | **heal the network** |  |  |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | _After healing: one owner, or two?_ |  |  |  |
| 12 | `lookup` on all nodes (owner_isolated/service) - **agree** | `node3/1517fb` | `node3/1517fb` | `node3/1517fb` |

#### one sided split

n1 stops hearing from n3, but n3 still hears n1. The two nodes disagree about whether the other one is alive, which is the case that breaks membership algorithms assuming symmetric failures.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (one_sided_split/service) | started `node1/8696b4` |  |  |
| 2 | `lookup` on all nodes (one_sided_split/service) - **agree** | `node1/8696b4` | `node1/8696b4` | `node1/8696b4` |
| 3 | **cut n1 <- n3** (one sided: n3 still hears n1) |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (one_sided_split/service) - **agree** | `node1/8696b4` | `node1/8696b4` | `node1/8696b4` |
| 6 | _n3 claims the same name while it still believes n1 is up._ |  |  |  |
| 7 | `start_process` on n3 (one_sided_split/service) |  |  | started `node3/bb8474` _(417ms)_ |
| 8 | `lookup` on all nodes (one_sided_split/service) - **disagree** | `node1/8696b4` | `node1/8696b4` | `node3/bb8474` |
| 9 | **heal the network** |  |  |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | `lookup` on all nodes (one_sided_split/service) - **agree** | `node3/bb8474` | `node3/bb8474` | `node3/bb8474` |

#### full split

Every node is cut off from every other node, so nobody has a majority. All three then try to own the same name at the same time, and the split is healed with three candidate owners.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (full_split/service) | started `node1/dd8810` |  |  |
| 2 | `lookup` on all nodes (full_split/service) - **agree** | `node1/dd8810` | `node1/dd8810` | `node1/dd8810` |
| 3 | **cut n1 <-> n2** |  |  |  |
| 4 | **cut n1 <-> n3** |  |  |  |
| 5 | **cut n2 <-> n3** |  |  |  |
| 6 | wait 15000ms for the registry to react |  |  |  |
| 7 | `lookup` on all nodes (full_split/service) - **disagree** | `node1/dd8810` | `node1/dd8810` | `not_found` |
| 8 | _Both other nodes claim the name as well._ |  |  |  |
| 9 | `start_process` on n2 (full_split/service) |  | started `node2/a0ee4f` _(4477ms)_ |  |
| 10 | `start_process` on n3 (full_split/service) |  |  | started `node3/1484a1` |
| 11 | `lookup` on all nodes (full_split/service) - **disagree** | `node1/dd8810` | `node2/a0ee4f` | `node3/1484a1` |
| 12 | **heal the network** |  |  |  |
| 13 | wait 15000ms for the registry to react |  |  |  |
| 14 | _After healing: how many owners survive?_ |  |  |  |
| 15 | `lookup` on all nodes (full_split/service) - **agree** | `node2/a0ee4f` | `node2/a0ee4f` | `node2/a0ee4f` |

#### database lost

The node owning the name loses its connection to Postgres while the BEAM cluster stays intact. Only matters for a registry that keeps its state in the database; for the others nothing happens, which is itself the result.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (database_lost/service) | started `node1/9c987a` |  |  |
| 2 | wait 15000ms for the registry to react |  |  |  |
| 3 | `lookup` on all nodes (database_lost/service) - **disagree** | `node1/9c987a` | `not_found` | `not_found` |
| 4 | _n1 can still reach the other nodes, but not the database._ |  |  |  |
| 5 | **cut n1 <- postgres** |  |  |  |
| 6 | wait 15000ms for the registry to react |  |  |  |
| 7 | `lookup` on all nodes (database_lost/service) - **disagree** | `node1/9c987a` | `not_found` | `not_found` |
| 8 | _Does another node take the name over?_ |  |  |  |
| 9 | `start_process` on n2 (database_lost/service) |  | error: `{timeout,{gen_leader,leader_call,
                     [gproc_dist,
                      {reg_other,{n,g,<<"database_lost/service">>},
                                 undefined,<<"<10201.340.0>">>,[],reg}]}}` _(5001ms)_ |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | `lookup` on all nodes (database_lost/service) - **disagree** | `node1/9c987a` | `not_found` | `not_found` |
| 12 | **heal the network** |  |  |  |
| 13 | wait 15000ms for the registry to react |  |  |  |
| 14 | `lookup` on all nodes (database_lost/service) - **disagree** | `node1/9c987a` | `not_found` | `not_found` |

### syn

#### baseline

Healthy cluster. Establishes what the registry does when nothing is wrong: a name is visible everywhere, a second claim is refused, and the name is free again after an orderly stop.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (baseline/service) | started `node1/9a0e78` |  |  |
| 2 | `lookup` on all nodes (baseline/service) - **agree** | `node1/9a0e78` | `node1/9a0e78` | `node1/9a0e78` |
| 3 | _A second node claims the same name._ |  |  |  |
| 4 | `start_process` on n2 (baseline/service) |  | error: `taken` |  |
| 5 | `lookup` on all nodes (baseline/service) - **agree** | `node1/9a0e78` | `node1/9a0e78` | `node1/9a0e78` |
| 6 | `renew_lease` on n2 (baseline/service) |  | `not_supported` |  |
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
| 5 | `lookup` on all nodes (process_death/service) - **agree** | `not_found` | `not_found` | `not_found` |
| 6 | _Another node tries to take the name over._ |  |  |  |
| 7 | `start_process` on n2 (process_death/service) |  | started `node2/81785f` |  |
| 8 | `lookup` on all nodes (process_death/service) - **agree** | `node2/81785f` | `node2/81785f` | `node2/81785f` |

#### lease expiry

The lease is shortened to 3s and then nobody renews it. Registries without leases keep the name forever; a lease based registry drops it and lets another node take over.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | set lease_ms to 3000 |  |  |  |
| 2 | `start_process` on n1 (lease_expiry/service) | started `node1/0bc2d0` |  |  |
| 3 | `lookup` on all nodes (lease_expiry/service) - **agree** | `node1/0bc2d0` | `node1/0bc2d0` | `node1/0bc2d0` |
| 4 | `renew_lease` on n1 (lease_expiry/service) | `not_supported` |  |  |
| 5 | _Wait past the lease without renewing._ |  |  |  |
| 6 | wait 6000ms |  |  |  |
| 7 | `lookup` on all nodes (lease_expiry/service) - **agree** | `node1/0bc2d0` | `node1/0bc2d0` | `node1/0bc2d0` |
| 8 | _Another node tries to take the name over._ |  |  |  |
| 9 | `start_process` on n2 (lease_expiry/service) |  | error: `taken` |  |
| 10 | `lookup` on all nodes (lease_expiry/service) - **agree** | `node1/0bc2d0` | `node1/0bc2d0` | `node1/0bc2d0` |

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
| 7 | `start_process` on n3 (symmetric_split/service) |  |  | started `node3/bcf409` |
| 8 | `lookup` on all nodes (symmetric_split/service) - **disagree** | `node1/b712ba` | `node1/b712ba` | `node3/bcf409` |
| 9 | `renew_lease` on n1 (symmetric_split/service) | `not_supported` |  |  |
| 10 | **heal the network** |  |  |  |
| 11 | wait 15000ms for the registry to react |  |  |  |
| 12 | _After healing: does the cluster agree again?_ |  |  |  |
| 13 | `lookup` on all nodes (symmetric_split/service) - **agree** | `node3/bcf409` | `node3/bcf409` | `node3/bcf409` |

#### owner isolated

The node owning the name (n3) is cut off from the majority. This is the failover case: can the majority take the name over, and what happens to the old owner when the split heals?

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n3 (owner_isolated/service) |  |  | started `node3/540222` |
| 2 | `lookup` on all nodes (owner_isolated/service) - **agree** | `node3/540222` | `node3/540222` | `node3/540222` |
| 3 | **isolate n3** |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (owner_isolated/service) - **disagree** | `not_found` | `not_found` | `node3/540222` |
| 6 | _The majority side tries to take the name over._ |  |  |  |
| 7 | `start_process` on n1 (owner_isolated/service) | started `node1/f3edf8` |  |  |
| 8 | `lookup` on all nodes (owner_isolated/service) - **disagree** | `node1/f3edf8` | `node1/f3edf8` | `node3/540222` |
| 9 | **heal the network** |  |  |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | _After healing: one owner, or two?_ |  |  |  |
| 12 | `lookup` on all nodes (owner_isolated/service) - **agree** | `node1/f3edf8` | `node1/f3edf8` | `node1/f3edf8` |

#### one sided split

n1 stops hearing from n3, but n3 still hears n1. The two nodes disagree about whether the other one is alive, which is the case that breaks membership algorithms assuming symmetric failures.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (one_sided_split/service) | started `node1/370ec9` |  |  |
| 2 | `lookup` on all nodes (one_sided_split/service) - **agree** | `node1/370ec9` | `node1/370ec9` | `node1/370ec9` |
| 3 | **cut n1 <- n3** (one sided: n3 still hears n1) |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (one_sided_split/service) - **disagree** | `node1/370ec9` | `node1/370ec9` | `not_found` |
| 6 | _n3 claims the same name while it still believes n1 is up._ |  |  |  |
| 7 | `start_process` on n3 (one_sided_split/service) |  |  | started `node3/6cd161` |
| 8 | `lookup` on all nodes (one_sided_split/service) - **disagree** | `node1/370ec9` | `node1/370ec9` | `node3/6cd161` |
| 9 | **heal the network** |  |  |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | `lookup` on all nodes (one_sided_split/service) - **agree** | `node3/6cd161` | `node3/6cd161` | `node3/6cd161` |

#### full split

Every node is cut off from every other node, so nobody has a majority. All three then try to own the same name at the same time, and the split is healed with three candidate owners.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (full_split/service) | started `node1/2cf4e2` |  |  |
| 2 | `lookup` on all nodes (full_split/service) - **agree** | `node1/2cf4e2` | `node1/2cf4e2` | `node1/2cf4e2` |
| 3 | **cut n1 <-> n2** |  |  |  |
| 4 | **cut n1 <-> n3** |  |  |  |
| 5 | **cut n2 <-> n3** |  |  |  |
| 6 | wait 15000ms for the registry to react |  |  |  |
| 7 | `lookup` on all nodes (full_split/service) - **disagree** | `node1/2cf4e2` | `not_found` | `not_found` |
| 8 | _Both other nodes claim the name as well._ |  |  |  |
| 9 | `start_process` on n2 (full_split/service) |  | started `node2/f6ce6e` |  |
| 10 | `start_process` on n3 (full_split/service) |  |  | started `node3/b636a4` |
| 11 | `lookup` on all nodes (full_split/service) - **disagree** | `node1/2cf4e2` | `node2/f6ce6e` | `node3/b636a4` |
| 12 | **heal the network** |  |  |  |
| 13 | wait 15000ms for the registry to react |  |  |  |
| 14 | _After healing: how many owners survive?_ |  |  |  |
| 15 | `lookup` on all nodes (full_split/service) - **agree** | `node2/f6ce6e` | `node2/f6ce6e` | `node2/f6ce6e` |

#### database lost

The node owning the name loses its connection to Postgres while the BEAM cluster stays intact. Only matters for a registry that keeps its state in the database; for the others nothing happens, which is itself the result.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (database_lost/service) | started `node1/d5ad0f` |  |  |
| 2 | wait 15000ms for the registry to react |  |  |  |
| 3 | `lookup` on all nodes (database_lost/service) - **agree** | `node1/d5ad0f` | `node1/d5ad0f` | `node1/d5ad0f` |
| 4 | _n1 can still reach the other nodes, but not the database._ |  |  |  |
| 5 | **cut n1 <- postgres** |  |  |  |
| 6 | wait 15000ms for the registry to react |  |  |  |
| 7 | `lookup` on all nodes (database_lost/service) - **agree** | `node1/d5ad0f` | `node1/d5ad0f` | `node1/d5ad0f` |
| 8 | _Does another node take the name over?_ |  |  |  |
| 9 | `start_process` on n2 (database_lost/service) |  | error: `taken` |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | `lookup` on all nodes (database_lost/service) - **agree** | `node1/d5ad0f` | `node1/d5ad0f` | `node1/d5ad0f` |
| 12 | **heal the network** |  |  |  |
| 13 | wait 15000ms for the registry to react |  |  |  |
| 14 | `lookup` on all nodes (database_lost/service) - **agree** | `node1/d5ad0f` | `node1/d5ad0f` | `node1/d5ad0f` |

### horde

#### baseline

Healthy cluster. Establishes what the registry does when nothing is wrong: a name is visible everywhere, a second claim is refused, and the name is free again after an orderly stop.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (baseline/service) | started `node1/cd48d4` |  |  |
| 2 | `lookup` on all nodes (baseline/service) - **disagree** | `node1/cd48d4` | `not_found` | `not_found` |
| 3 | _A second node claims the same name._ |  |  |  |
| 4 | `start_process` on n2 (baseline/service) |  | started `node2/049f95` |  |
| 5 | `lookup` on all nodes (baseline/service) - **disagree** | `node1/cd48d4` | `node2/049f95` | `not_found` |
| 6 | `renew_lease` on n2 (baseline/service) |  | `not_supported` |  |
| 7 | `stop_process` on n1 (baseline/service) | `stopped` |  |  |
| 8 | `lookup` on all nodes (baseline/service) - **disagree** | `not_found` | `node2/049f95` | `not_found` |

#### process death

The registered process is killed without unregistering. Shows whether the registry monitors the process and frees the name by itself, or keeps handing out a dead pid.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (process_death/service) | started `node1/0bc2d0` |  |  |
| 2 | `lookup` on all nodes (process_death/service) - **disagree** | `node1/0bc2d0` | `not_found` | `not_found` |
| 3 | `kill_process` on n1 (process_death/service) | `killed` |  |  |
| 4 | wait 2000ms |  |  |  |
| 5 | `lookup` on all nodes (process_death/service) - **agree** | `not_found` | `not_found` | `not_found` |
| 6 | _Another node tries to take the name over._ |  |  |  |
| 7 | `start_process` on n2 (process_death/service) |  | started `node2/ea654a` |  |
| 8 | `lookup` on all nodes (process_death/service) - **disagree** | `not_found` | `node2/ea654a` | `not_found` |

#### lease expiry

The lease is shortened to 3s and then nobody renews it. Registries without leases keep the name forever; a lease based registry drops it and lets another node take over.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | set lease_ms to 3000 |  |  |  |
| 2 | `start_process` on n1 (lease_expiry/service) | started `node1/aaf1a3` |  |  |
| 3 | `lookup` on all nodes (lease_expiry/service) - **disagree** | `node1/aaf1a3` | `not_found` | `not_found` |
| 4 | `renew_lease` on n1 (lease_expiry/service) | `not_supported` |  |  |
| 5 | _Wait past the lease without renewing._ |  |  |  |
| 6 | wait 6000ms |  |  |  |
| 7 | `lookup` on all nodes (lease_expiry/service) - **agree** | `node1/aaf1a3` | `node1/aaf1a3` | `node1/aaf1a3` |
| 8 | _Another node tries to take the name over._ |  |  |  |
| 9 | `start_process` on n2 (lease_expiry/service) |  | started `node2/afedf4` |  |
| 10 | `lookup` on all nodes (lease_expiry/service) - **disagree** | `node1/aaf1a3` | `node2/afedf4` | `node1/aaf1a3` |

#### symmetric split

The cluster splits into a majority (n1, n2) and a minority (n3). The owner is on the majority side. The minority tries to claim the same name, then the split is healed.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (symmetric_split/service) | started `node1/0224f6` |  |  |
| 2 | `lookup` on all nodes (symmetric_split/service) - **disagree** | `node1/0224f6` | `not_found` | `not_found` |
| 3 | **isolate n3** |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (symmetric_split/service) - **disagree** | `node1/0224f6` | `node1/0224f6` | `not_found` |
| 6 | _The minority side claims the same name._ |  |  |  |
| 7 | `start_process` on n3 (symmetric_split/service) |  |  | started `node3/ceb9b1` |
| 8 | `lookup` on all nodes (symmetric_split/service) - **disagree** | `node1/0224f6` | `node1/0224f6` | `node3/ceb9b1` |
| 9 | `renew_lease` on n1 (symmetric_split/service) | `not_supported` |  |  |
| 10 | **heal the network** |  |  |  |
| 11 | wait 15000ms for the registry to react |  |  |  |
| 12 | _After healing: does the cluster agree again?_ |  |  |  |
| 13 | `lookup` on all nodes (symmetric_split/service) - **agree** | `node3/ceb9b1` | `node3/ceb9b1` | `node3/ceb9b1` |

#### owner isolated

The node owning the name (n3) is cut off from the majority. This is the failover case: can the majority take the name over, and what happens to the old owner when the split heals?

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n3 (owner_isolated/service) |  |  | started `node3/344333` |
| 2 | `lookup` on all nodes (owner_isolated/service) - **disagree** | `not_found` | `not_found` | `node3/344333` |
| 3 | **isolate n3** |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (owner_isolated/service) - **disagree** | `not_found` | `not_found` | `node3/344333` |
| 6 | _The majority side tries to take the name over._ |  |  |  |
| 7 | `start_process` on n1 (owner_isolated/service) | started `node1/3f210a` |  |  |
| 8 | `lookup` on all nodes (owner_isolated/service) - **disagree** | `node1/3f210a` | `not_found` | `node3/344333` |
| 9 | **heal the network** |  |  |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | _After healing: one owner, or two?_ |  |  |  |
| 12 | `lookup` on all nodes (owner_isolated/service) - **agree** | `node1/3f210a` | `node1/3f210a` | `node1/3f210a` |

#### one sided split

n1 stops hearing from n3, but n3 still hears n1. The two nodes disagree about whether the other one is alive, which is the case that breaks membership algorithms assuming symmetric failures.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (one_sided_split/service) | started `node1/3d52ab` |  |  |
| 2 | `lookup` on all nodes (one_sided_split/service) - **disagree** | `node1/3d52ab` | `not_found` | `not_found` |
| 3 | **cut n1 <- n3** (one sided: n3 still hears n1) |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (one_sided_split/service) - **disagree** | `node1/3d52ab` | `not_found` | `not_found` |
| 6 | _n3 claims the same name while it still believes n1 is up._ |  |  |  |
| 7 | `start_process` on n3 (one_sided_split/service) |  |  | started `node3/2a4164` |
| 8 | `lookup` on all nodes (one_sided_split/service) - **disagree** | `node1/3d52ab` | `not_found` | `node3/2a4164` |
| 9 | **heal the network** |  |  |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | `lookup` on all nodes (one_sided_split/service) - **agree** | `not_found` | `not_found` | `not_found` |

#### full split

Every node is cut off from every other node, so nobody has a majority. All three then try to own the same name at the same time, and the split is healed with three candidate owners.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (full_split/service) | started `node1/7f314b` |  |  |
| 2 | `lookup` on all nodes (full_split/service) - **disagree** | `node1/7f314b` | `not_found` | `not_found` |
| 3 | **cut n1 <-> n2** |  |  |  |
| 4 | **cut n1 <-> n3** |  |  |  |
| 5 | **cut n2 <-> n3** |  |  |  |
| 6 | wait 15000ms for the registry to react |  |  |  |
| 7 | `lookup` on all nodes (full_split/service) - **disagree** | `node1/7f314b` | `not_found` | `not_found` |
| 8 | _Both other nodes claim the name as well._ |  |  |  |
| 9 | `start_process` on n2 (full_split/service) |  | started `node2/6c1312` |  |
| 10 | `start_process` on n3 (full_split/service) |  |  | started `node3/d42bc3` |
| 11 | `lookup` on all nodes (full_split/service) - **disagree** | `node1/7f314b` | `node2/6c1312` | `node3/d42bc3` |
| 12 | **heal the network** |  |  |  |
| 13 | wait 15000ms for the registry to react |  |  |  |
| 14 | _After healing: how many owners survive?_ |  |  |  |
| 15 | `lookup` on all nodes (full_split/service) - **agree** | `node3/d42bc3` | `node3/d42bc3` | `node3/d42bc3` |

#### database lost

The node owning the name loses its connection to Postgres while the BEAM cluster stays intact. Only matters for a registry that keeps its state in the database; for the others nothing happens, which is itself the result.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (database_lost/service) | started `node1/4661db` |  |  |
| 2 | wait 15000ms for the registry to react |  |  |  |
| 3 | `lookup` on all nodes (database_lost/service) - **agree** | `node1/4661db` | `node1/4661db` | `node1/4661db` |
| 4 | _n1 can still reach the other nodes, but not the database._ |  |  |  |
| 5 | **cut n1 <- postgres** |  |  |  |
| 6 | wait 15000ms for the registry to react |  |  |  |
| 7 | `lookup` on all nodes (database_lost/service) - **agree** | `node1/4661db` | `node1/4661db` | `node1/4661db` |
| 8 | _Does another node take the name over?_ |  |  |  |
| 9 | `start_process` on n2 (database_lost/service) |  | started `node2/3a7f4c` |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | `lookup` on all nodes (database_lost/service) - **agree** | `node2/3a7f4c` | `node2/3a7f4c` | `node2/3a7f4c` |
| 12 | **heal the network** |  |  |  |
| 13 | wait 15000ms for the registry to react |  |  |  |
| 14 | `lookup` on all nodes (database_lost/service) - **agree** | `node2/3a7f4c` | `node2/3a7f4c` | `node2/3a7f4c` |

### locker

#### baseline

Healthy cluster. Establishes what the registry does when nothing is wrong: a name is visible everywhere, a second claim is refused, and the name is free again after an orderly stop.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (baseline/service) | started `node1/d9fc59` |  |  |
| 2 | `lookup` on all nodes (baseline/service) - **agree** | `node1/d9fc59` | `node1/d9fc59` | `node1/d9fc59` |
| 3 | _A second node claims the same name._ |  |  |  |
| 4 | `start_process` on n2 (baseline/service) |  | error: `no_quorum` |  |
| 5 | `lookup` on all nodes (baseline/service) - **agree** | `node1/d9fc59` | `node1/d9fc59` | `node1/d9fc59` |
| 6 | `renew_lease` on n2 (baseline/service) |  | `renewed` |  |
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
| 5 | `lookup` on all nodes (process_death/service) - **agree** | `node1/7b445e` | `node1/7b445e` | `node1/7b445e` |
| 6 | _Another node tries to take the name over._ |  |  |  |
| 7 | `start_process` on n2 (process_death/service) |  | error: `no_quorum` |  |
| 8 | `lookup` on all nodes (process_death/service) - **agree** | `node1/7b445e` | `node1/7b445e` | `node1/7b445e` |

#### lease expiry

The lease is shortened to 3s and then nobody renews it. Registries without leases keep the name forever; a lease based registry drops it and lets another node take over.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | set lease_ms to 3000 |  |  |  |
| 2 | `start_process` on n1 (lease_expiry/service) | started `node1/1b4dc2` |  |  |
| 3 | `lookup` on all nodes (lease_expiry/service) - **agree** | `node1/1b4dc2` | `node1/1b4dc2` | `node1/1b4dc2` |
| 4 | `renew_lease` on n1 (lease_expiry/service) | `renewed` |  |  |
| 5 | _Wait past the lease without renewing._ |  |  |  |
| 6 | wait 6000ms |  |  |  |
| 7 | `lookup` on all nodes (lease_expiry/service) - **agree** | `not_found` | `not_found` | `not_found` |
| 8 | _Another node tries to take the name over._ |  |  |  |
| 9 | `start_process` on n2 (lease_expiry/service) |  | started `node2/4a9be7` |  |
| 10 | `lookup` on all nodes (lease_expiry/service) - **agree** | `node2/4a9be7` | `node2/4a9be7` | `node2/4a9be7` |

#### symmetric split

The cluster splits into a majority (n1, n2) and a minority (n3). The owner is on the majority side. The minority tries to claim the same name, then the split is healed.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (symmetric_split/service) | started `node1/c5b0b2` |  |  |
| 2 | `lookup` on all nodes (symmetric_split/service) - **agree** | `node1/c5b0b2` | `node1/c5b0b2` | `node1/c5b0b2` |
| 3 | **isolate n3** |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (symmetric_split/service) - **agree** | `node1/c5b0b2` | `node1/c5b0b2` | `node1/c5b0b2` |
| 6 | _The minority side claims the same name._ |  |  |  |
| 7 | `start_process` on n3 (symmetric_split/service) |  |  | error: `no_quorum` _(7015ms)_ |
| 8 | `lookup` on all nodes (symmetric_split/service) - **agree** | `node1/c5b0b2` | `node1/c5b0b2` | `node1/c5b0b2` |
| 9 | `renew_lease` on n1 (symmetric_split/service) | `renewed` _(7013ms)_ |  |  |
| 10 | **heal the network** |  |  |  |
| 11 | wait 15000ms for the registry to react |  |  |  |
| 12 | _After healing: does the cluster agree again?_ |  |  |  |
| 13 | `lookup` on all nodes (symmetric_split/service) - **agree** | `node1/c5b0b2` | `node1/c5b0b2` | `node1/c5b0b2` |

#### owner isolated

The node owning the name (n3) is cut off from the majority. This is the failover case: can the majority take the name over, and what happens to the old owner when the split heals?

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n3 (owner_isolated/service) |  |  | started `node3/343ba1` |
| 2 | `lookup` on all nodes (owner_isolated/service) - **agree** | `node3/343ba1` | `node3/343ba1` | `node3/343ba1` |
| 3 | **isolate n3** |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (owner_isolated/service) - **agree** | `node3/343ba1` | `node3/343ba1` | `node3/343ba1` |
| 6 | _The majority side tries to take the name over._ |  |  |  |
| 7 | `start_process` on n1 (owner_isolated/service) | error: `no_quorum` _(7004ms)_ |  |  |
| 8 | `lookup` on all nodes (owner_isolated/service) - **agree** | `node3/343ba1` | `node3/343ba1` | `node3/343ba1` |
| 9 | **heal the network** |  |  |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | _After healing: one owner, or two?_ |  |  |  |
| 12 | `lookup` on all nodes (owner_isolated/service) - **agree** | `node3/343ba1` | `node3/343ba1` | `node3/343ba1` |

#### one sided split

n1 stops hearing from n3, but n3 still hears n1. The two nodes disagree about whether the other one is alive, which is the case that breaks membership algorithms assuming symmetric failures.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (one_sided_split/service) | started `node1/22824a` |  |  |
| 2 | `lookup` on all nodes (one_sided_split/service) - **agree** | `node1/22824a` | `node1/22824a` | `node1/22824a` |
| 3 | **cut n1 <- n3** (one sided: n3 still hears n1) |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (one_sided_split/service) - **agree** | `node1/22824a` | `node1/22824a` | `node1/22824a` |
| 6 | _n3 claims the same name while it still believes n1 is up._ |  |  |  |
| 7 | `start_process` on n3 (one_sided_split/service) |  |  | error: `no_quorum` _(7002ms)_ |
| 8 | `lookup` on all nodes (one_sided_split/service) - **agree** | `node1/22824a` | `node1/22824a` | `node1/22824a` |
| 9 | **heal the network** |  |  |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | `lookup` on all nodes (one_sided_split/service) - **agree** | `node1/22824a` | `node1/22824a` | `node1/22824a` |

#### full split

Every node is cut off from every other node, so nobody has a majority. All three then try to own the same name at the same time, and the split is healed with three candidate owners.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (full_split/service) | started `node1/ff8b1f` |  |  |
| 2 | `lookup` on all nodes (full_split/service) - **agree** | `node1/ff8b1f` | `node1/ff8b1f` | `node1/ff8b1f` |
| 3 | **cut n1 <-> n2** |  |  |  |
| 4 | **cut n1 <-> n3** |  |  |  |
| 5 | **cut n2 <-> n3** |  |  |  |
| 6 | wait 15000ms for the registry to react |  |  |  |
| 7 | `lookup` on all nodes (full_split/service) - **agree** | `node1/ff8b1f` | `node1/ff8b1f` | `node1/ff8b1f` |
| 8 | _Both other nodes claim the name as well._ |  |  |  |
| 9 | `start_process` on n2 (full_split/service) |  | error: `no_quorum` _(7008ms)_ |  |
| 10 | `start_process` on n3 (full_split/service) |  |  | error: `no_quorum` _(7012ms)_ |
| 11 | `lookup` on all nodes (full_split/service) - **agree** | `node1/ff8b1f` | `node1/ff8b1f` | `node1/ff8b1f` |
| 12 | **heal the network** |  |  |  |
| 13 | wait 15000ms for the registry to react |  |  |  |
| 14 | _After healing: how many owners survive?_ |  |  |  |
| 15 | `lookup` on all nodes (full_split/service) - **agree** | `node1/ff8b1f` | `node1/ff8b1f` | `node1/ff8b1f` |

#### database lost

The node owning the name loses its connection to Postgres while the BEAM cluster stays intact. Only matters for a registry that keeps its state in the database; for the others nothing happens, which is itself the result.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (database_lost/service) | started `node1/fc412e` |  |  |
| 2 | wait 15000ms for the registry to react |  |  |  |
| 3 | `lookup` on all nodes (database_lost/service) - **agree** | `node1/fc412e` | `node1/fc412e` | `node1/fc412e` |
| 4 | _n1 can still reach the other nodes, but not the database._ |  |  |  |
| 5 | **cut n1 <- postgres** |  |  |  |
| 6 | wait 15000ms for the registry to react |  |  |  |
| 7 | `lookup` on all nodes (database_lost/service) - **agree** | `node1/fc412e` | `node1/fc412e` | `node1/fc412e` |
| 8 | _Does another node take the name over?_ |  |  |  |
| 9 | `start_process` on n2 (database_lost/service) |  | error: `no_quorum` |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | `lookup` on all nodes (database_lost/service) - **agree** | `node1/fc412e` | `node1/fc412e` | `node1/fc412e` |
| 12 | **heal the network** |  |  |  |
| 13 | wait 15000ms for the registry to react |  |  |  |
| 14 | `lookup` on all nodes (database_lost/service) - **agree** | `node1/fc412e` | `node1/fc412e` | `node1/fc412e` |

### highlander_pg

#### baseline

Healthy cluster. Establishes what the registry does when nothing is wrong: a name is visible everywhere, a second claim is refused, and the name is free again after an orderly stop.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (baseline/service) | started `node1/6f7d24` _(139ms)_ |  |  |
| 2 | `lookup` on all nodes (baseline/service) - **disagree** | `node1/6f7d24` | `not_found` | `not_found` |
| 3 | _A second node claims the same name._ |  |  |  |
| 4 | `start_process` on n2 (baseline/service) |  | `pending` _(3053ms)_ |  |
| 5 | `lookup` on all nodes (baseline/service) - **disagree** | `node1/6f7d24` | `not_found` | `not_found` |
| 6 | `renew_lease` on n2 (baseline/service) |  | `not_found` |  |
| 7 | `stop_process` on n1 (baseline/service) | `stopped` |  |  |
| 8 | `lookup` on all nodes (baseline/service) - **agree** | `not_found` | `not_found` | `not_found` |

#### process death

The registered process is killed without unregistering. Shows whether the registry monitors the process and frees the name by itself, or keeps handing out a dead pid.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (process_death/service) | started `node1/7839a7` _(112ms)_ |  |  |
| 2 | `lookup` on all nodes (process_death/service) - **disagree** | `node1/7839a7` | `not_found` | `not_found` |
| 3 | `kill_process` on n1 (process_death/service) | `killed` |  |  |
| 4 | wait 2000ms |  |  |  |
| 5 | `lookup` on all nodes (process_death/service) - **agree** | `not_found` | `not_found` | `not_found` |
| 6 | _Another node tries to take the name over._ |  |  |  |
| 7 | `start_process` on n2 (process_death/service) |  | started `node2/8451d8` _(110ms)_ |  |
| 8 | `lookup` on all nodes (process_death/service) - **disagree** | `not_found` | `node2/8451d8` | `not_found` |

#### lease expiry

The lease is shortened to 3s and then nobody renews it. Registries without leases keep the name forever; a lease based registry drops it and lets another node take over.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | set lease_ms to 3000 |  |  |  |
| 2 | `start_process` on n1 (lease_expiry/service) | started `node1/f3edf8` _(108ms)_ |  |  |
| 3 | `lookup` on all nodes (lease_expiry/service) - **disagree** | `node1/f3edf8` | `not_found` | `not_found` |
| 4 | `renew_lease` on n1 (lease_expiry/service) | `not_supported` |  |  |
| 5 | _Wait past the lease without renewing._ |  |  |  |
| 6 | wait 6000ms |  |  |  |
| 7 | `lookup` on all nodes (lease_expiry/service) - **disagree** | `node1/f3edf8` | `not_found` | `not_found` |
| 8 | _Another node tries to take the name over._ |  |  |  |
| 9 | `start_process` on n2 (lease_expiry/service) |  | `pending` _(3075ms)_ |  |
| 10 | `lookup` on all nodes (lease_expiry/service) - **disagree** | `node1/f3edf8` | `not_found` | `not_found` |

#### symmetric split

The cluster splits into a majority (n1, n2) and a minority (n3). The owner is on the majority side. The minority tries to claim the same name, then the split is healed.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (symmetric_split/service) | started `node1/6de709` _(104ms)_ |  |  |
| 2 | `lookup` on all nodes (symmetric_split/service) - **disagree** | `node1/6de709` | `not_found` | `not_found` |
| 3 | **isolate n3** |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (symmetric_split/service) - **disagree** | `node1/6de709` | `not_found` | `not_found` |
| 6 | _The minority side claims the same name._ |  |  |  |
| 7 | `start_process` on n3 (symmetric_split/service) |  |  | `pending` _(3046ms)_ |
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
| 1 | `start_process` on n3 (owner_isolated/service) |  |  | started `node3/b44c27` _(103ms)_ |
| 2 | `lookup` on all nodes (owner_isolated/service) - **disagree** | `not_found` | `not_found` | `node3/b44c27` |
| 3 | **isolate n3** |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (owner_isolated/service) - **disagree** | `not_found` | `not_found` | `node3/b44c27` |
| 6 | _The majority side tries to take the name over._ |  |  |  |
| 7 | `start_process` on n1 (owner_isolated/service) | `pending` _(3073ms)_ |  |  |
| 8 | `lookup` on all nodes (owner_isolated/service) - **disagree** | `not_found` | `not_found` | `node3/b44c27` |
| 9 | **heal the network** |  |  |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | _After healing: one owner, or two?_ |  |  |  |
| 12 | `lookup` on all nodes (owner_isolated/service) - **disagree** | `not_found` | `not_found` | `node3/b44c27` |

#### one sided split

n1 stops hearing from n3, but n3 still hears n1. The two nodes disagree about whether the other one is alive, which is the case that breaks membership algorithms assuming symmetric failures.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (one_sided_split/service) | started `node1/361bc8` _(112ms)_ |  |  |
| 2 | `lookup` on all nodes (one_sided_split/service) - **disagree** | `node1/361bc8` | `not_found` | `not_found` |
| 3 | **cut n1 <- n3** (one sided: n3 still hears n1) |  |  |  |
| 4 | wait 15000ms for the registry to react |  |  |  |
| 5 | `lookup` on all nodes (one_sided_split/service) - **disagree** | `node1/361bc8` | `not_found` | `not_found` |
| 6 | _n3 claims the same name while it still believes n1 is up._ |  |  |  |
| 7 | `start_process` on n3 (one_sided_split/service) |  |  | `pending` _(3005ms)_ |
| 8 | `lookup` on all nodes (one_sided_split/service) - **disagree** | `node1/361bc8` | `not_found` | `not_found` |
| 9 | **heal the network** |  |  |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | `lookup` on all nodes (one_sided_split/service) - **disagree** | `node1/361bc8` | `not_found` | `not_found` |

#### full split

Every node is cut off from every other node, so nobody has a majority. All three then try to own the same name at the same time, and the split is healed with three candidate owners.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (full_split/service) | started `node1/dbc390` _(104ms)_ |  |  |
| 2 | `lookup` on all nodes (full_split/service) - **disagree** | `node1/dbc390` | `not_found` | `not_found` |
| 3 | **cut n1 <-> n2** |  |  |  |
| 4 | **cut n1 <-> n3** |  |  |  |
| 5 | **cut n2 <-> n3** |  |  |  |
| 6 | wait 15000ms for the registry to react |  |  |  |
| 7 | `lookup` on all nodes (full_split/service) - **disagree** | `node1/dbc390` | `not_found` | `not_found` |
| 8 | _Both other nodes claim the name as well._ |  |  |  |
| 9 | `start_process` on n2 (full_split/service) |  | `pending` _(3096ms)_ |  |
| 10 | `start_process` on n3 (full_split/service) |  |  | `pending` _(3085ms)_ |
| 11 | `lookup` on all nodes (full_split/service) - **disagree** | `node1/dbc390` | `not_found` | `not_found` |
| 12 | **heal the network** |  |  |  |
| 13 | wait 15000ms for the registry to react |  |  |  |
| 14 | _After healing: how many owners survive?_ |  |  |  |
| 15 | `lookup` on all nodes (full_split/service) - **disagree** | `node1/dbc390` | `not_found` | `not_found` |

#### database lost

The node owning the name loses its connection to Postgres while the BEAM cluster stays intact. Only matters for a registry that keeps its state in the database; for the others nothing happens, which is itself the result.

| # | Step | n1 | n2 | n3 |
| --- | --- | --- | --- | --- |
| 1 | `start_process` on n1 (database_lost/service) | started `node1/b272de` _(104ms)_ |  |  |
| 2 | wait 15000ms for the registry to react |  |  |  |
| 3 | `lookup` on all nodes (database_lost/service) - **disagree** | `node1/b272de` | `not_found` | `not_found` |
| 4 | _n1 can still reach the other nodes, but not the database._ |  |  |  |
| 5 | **cut n1 <- postgres** |  |  |  |
| 6 | wait 15000ms for the registry to react |  |  |  |
| 7 | `lookup` on all nodes (database_lost/service) - **disagree** | `node1/b272de` | `not_found` | `not_found` |
| 8 | _Does another node take the name over?_ |  |  |  |
| 9 | `start_process` on n2 (database_lost/service) |  | `pending` _(3098ms)_ |  |
| 10 | wait 15000ms for the registry to react |  |  |  |
| 11 | `lookup` on all nodes (database_lost/service) - **disagree** | `node1/b272de` | `not_found` | `not_found` |
| 12 | **heal the network** |  |  |  |
| 13 | wait 15000ms for the registry to react |  |  |  |
| 14 | `lookup` on all nodes (database_lost/service) - **disagree** | `node1/b272de` | `not_found` | `not_found` |

