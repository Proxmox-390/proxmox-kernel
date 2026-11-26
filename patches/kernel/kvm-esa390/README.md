# kvm-esa390

Yvan Janssens' KVM series for running guests that IPL in ESA/390 on s390x KVM, carried here
before upstream review. Not yet merged upstream; the patch files are `git format-patch` output of
the series on Linux v7.3.6 and keep their RFC subject prefix and author header.

| Patches | Series | Source commit (on v7.3.6) |
|---|---|---|
| 0001-0007 | ESA/390-compatibility mode, v2 | `18355f97568a` |
| 0008-0011 | ESA/390 DAT shadowing, v1 | `4e51c436fb0e` (on top of the above) |

Change against the source commits: the `Makefile.kvm` hunks of 0007 and 0011 carry the line of
`kvm-vsie`'s selftest as context, because `kvm-vsie` is applied first here. The code is unchanged.

The features are opt-in per VM (`KVM_CAP_S390_ESA390_CM`, flag `KVM_S390_ESA390_CM_DAT`); other
guests are not affected.
