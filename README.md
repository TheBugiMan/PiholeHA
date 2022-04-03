Using script example found at https://discourse.pi-hole.net/t/good-solution-to-automatically-revert-to-normal-if-pi-hole-dies/10059/4 (authored by RAMSET) as a base, look to improve by using reusable functions and to not just create configuration but utilise backups pulled from primary PI server for DHCP configuration and leases.

TO be used in conjuction with Gravity-Sync https://github.com/vmstan/gravity-sync which will be responsible for CNAME, client/group, and white/blocklist duplication

Other resource - https://discourse.pi-hole.net/t/high-availability-ha-for-pi-hole-running-two-pi-holes/3138/80