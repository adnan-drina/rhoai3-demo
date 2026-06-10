# ODF Component Skill Roadmap

Use this roadmap with `.agents/references/red-hat-doc-map.yaml`. The YAML map
routes Red Hat documentation books to flat skills; this file is the readable
status view for ODF skill coverage.

## Active Baseline

- Product: Red Hat OpenShift Data Foundation
- Baseline source: `docs/PLATFORM_BASELINE.md`
- Active version while authored: 4.20
- OpenShift baseline while authored: 4.20

## Active Skills

| Skill | Primary coverage |
|-------|------------------|
| `odf-storagecluster` | Planning, architecture, AWS deployment posture, StorageCluster, StorageSystem, standalone MCG selection, update alignment, monitoring, troubleshooting, and must-gather |
| `odf-multicloud-gateway` | Multicloud Object Gateway, NooBaa, standalone object storage, S3 endpoint, backing stores, bucket classes, object dashboards, NooBaa backup handoff |
| `odf-object-bucket-claims` | Project-scoped ObjectBucketClaims, generated ConfigMaps and Secrets, app bucket consumption, RHOAI object-store handoff |
| `odf-storage-classes` | ODF block, file, and object storage classes; Ceph RBD, CephFS, NooBaa object class review; reclaim and binding behavior |

## Demo Priority

1. Use standalone MCG and ObjectBucketClaims for the first RHOAI object-store
   implementation.
2. Add full StorageCluster/Ceph manifests only if the demo needs ODF-provided
   RWO or RWX PVCs beyond existing OpenShift storage classes.
3. Keep ODF updates and troubleshooting version-aligned with the pinned OCP and
   ODF baseline.

## Future Candidates

Add only when an official source and demo need are clear:

- `odf-disaster-recovery` for ODF backup, restore, and DR workflows.
- `odf-security-and-encryption` for encryption, KMS, and access-control
  posture if the demo begins showcasing storage security.
- `odf-performance-and-scaling` for MCG endpoint scaling, Ceph performance, and
  capacity-management guidance if load testing becomes part of the demo.
