# kvm-esa390-native

Yvan Janssens' patch for hosts without facility 138 (z196, z114, zEC12, zBC12): there the
ESA/390-compatibility mode accepts DAT-on PSWs (the machine translates) and
KVM_S390_ESA390_CM_DAT is refused. No change on hosts with facility 138. `git format-patch`
output of commit `e6e4548c0616`; the `kvm_host_s390.h` hunk carries a line of `kvm-ext-irq` as
context, because that topic is applied first. The code is unchanged.
