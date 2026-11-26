# kvm-ext-irq

Yvan Janssens' KVM patches that let user space inject the external interruptions it emulates and
get an exit when such an interruption can be presented (capability 254), with a selftest. Carried
here before upstream review; `git format-patch` output, author header kept.

Applied after `kvm-esa390`; the `Makefile.kvm` hunk of 0003 carries the selftest lines of the
earlier topics as context. The code is unchanged.
