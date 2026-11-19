# Four hospitals for Kent and Medway, ~500,000 people each

Analysis of 2026-11-18. It is a side study and is not compiled into the
healthKent demo.

**The question:** choose four hospitals, each serving about a quarter of Kent
and Medway's 1,931,684 people (mid-2024), so that the total drive time to
them is as small as possible.
1. Choose four of the seven existing acute hospitals.
2. Choose four ideal locations, anywhere on Kent's road network.

## Method

- **Drive times** use the same road graph, speeds and joining rules as
  `make_drive_data.py`, imported from the folder above. That means 750,654
  nodes, 20 km/h access to the nearest non-trunk node, and the three speed
  scenarios: free-flow car, weekday morning peak and blue light.
- **Weights** are LSOA populations (`LsoaPop`), not admissions.
- **Times** are measured from each of the 1,107 LSOA label points:
  - to all 457,606 candidate sites, the non-trunk nodes on Kent's land, by
    forward Dijkstra;
  - to the seven hospitals, by reverse Dijkstra exactly as the demo does.
- **Allocation is capacitated.** Each LSOA goes, whole, to one site, and each
  site serves between (1 - tol) and (1 + tol) of P/4. The tolerance is 10 %
  (434,628 to 531,213 people) or 2.5 %. The allocation is a binary MILP
  (scipy `milp`, HiGHS) that minimises the sum of population x minutes.
- **Existing hospitals:** all 35 choices of 4 from 7. The unconstrained
  figure (everyone to the nearest of the four) is given beside each.
- **Ideal sites:** location-allocation. The script alternates the MILP
  allocation with each group's 1-median until neither changes. It starts
  from the five best existing sets and from ten random sets, then tries
  swapping each site for up to 300 random candidates within 8 km.

The figures are population-weighted mean minutes.

## Results: existing hospitals

The size band binds. At ±10 % the two northern hospitals take 27.5 % each
and the two eastern ones 22.5 %.

| Combination | Free-flow ±10 % | Peak | Blue light | Free-flow ±2.5 % |
|---|---|---|---|---|
| Darent Valley, Medway, William Harvey, QEQM | **17.68** | **22.26** | 14.61 | 18.24 |
| Darent Valley, Medway, Maidstone, K&C | 17.69 | 22.35 | **14.53** | **18.01** |
| Darent Valley, Medway, William Harvey, K&C | 17.76 | 22.36 | 14.69 | 18.03 |

- Darent Valley and Medway Maritime are in every best set.
- The east Kent pair is a near-tie, within about 0.1 min in every scenario:
  WHH with QEQM, or Maidstone with K&C.
- **No capacity limit:** the best set is Darent Valley, Maidstone, William
  Harvey and QEQM, at 16.67 / 20.96 / 13.61 min. But Maidstone then serves
  802,000 people (41.5 %) and QEQM 304,000 (15.7 %).

The best set at ±10 %, free-flow:

| Hospital | Population | Mean | Max |
|---|---|---|---|
| Darent Valley | 531,146 (27.5 %) | 18.1 | 40.3 |
| Medway Maritime | 531,186 (27.5 %) | 13.3 | 35.1 |
| William Harvey | 434,662 (22.5 %) | 19.6 | 44.5 |
| QEQM | 434,690 (22.5 %) | 20.6 | 42.4 |

## Results: ideal locations (±10 %)

The three scenarios give the same four sites, to within 0.5-3 km. These are
the free-flow run's sites. The times are free-flow / peak / blue light, with
the allocation held fixed.

| Site | Where | Population | Mean minutes |
|---|---|---|---|
| TQ 52621 67656 | Swanley, by the M25/A20; 7 km W of Darent Valley | 531,203 | 16.0 / 19.6 / 13.4 |
| TQ 74994 62617 | Bluebell Hill (A229) above Chatham; 6 km S of Medway Maritime | 531,145 | 11.5 / 14.3 / 9.5 |
| TR 00248 43764 | Ashford; ~4 km from William Harvey | 434,654 | 18.0 / 22.1 / 15.2 |
| TR 31136 65714 | Mid-Thanet near Minster; 6 km from QEQM | 434,682 | 16.5 / 20.4 / 13.2 |
| **All four** | | | **15.31 / 18.88 / 12.71** |

- Against the best existing four, that saves 2.4 min free-flow (13 %),
  3.4 min at peak (15 %) and 1.8-1.9 min on blue light.
- At ±2.5 % the Medway site moves back into Chatham, 1 km from Medway
  Maritime. At ±10 % it sits on Bluebell Hill so that it can reach south
  towards Maidstone. The four then give 15.84 / 19.81 / 13.13, against
  18.01 for the best existing four (Darent Valley, Medway, Maidstone, K&C).
- Three ideal sites sit close to existing hospitals: Chatham, Ashford and
  Thanet. The main difference is in the north-west, where the ideal site is
  at Swanley rather than Dartford.

## Files

- `times.py <scenario>` writes `T<sc>.npy` and `meta<sc>.npz`.
  - `T<sc>.npy` holds LSOA to site minutes: 1107 x 457606 float32, 2 GB.
    Both files are git-ignored.
  - Each scenario runs 1,107 Dijkstras over the full graph.
- `opt.py <scenario> [tol]` runs both optimisations, with tol defaulting to
  0.10.
  - It prints to stdout; that output is saved as `opt<sc>_<tol>.txt`.
  - It writes the ideal sites to `ideal<sc>_<tol>.npz`.
  - The ideal-site search is the slow part.
- `summ.py <ideal...npz>` gives each ideal set's sites, nearest towns and
  times in all three scenarios, with the allocation fixed. Its output for the
  four runs is in `summary.txt`.

Run these from this folder. The road data
(`~/data/healthKent-src/roads/drive_roads.json`) must be present, as for
`make_drive_data.py`.
