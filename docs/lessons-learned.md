# Lessons learned

- **SSH tries every identity.** With several keys loaded, the wrong one is offered first and can hit the server's attempt limit or the wrong forced command. `IdentitiesOnly=yes` plus an explicit `-i` fixes it.
- **A rigid `command="rsync ..."` restriction doesn't scale.** It broke as soon as the pull needed more than one operation (marker check, cleanup, restore upload). Replacing it with a wrapper script (`borg_receive.sh`) that switches on `SSH_ORIGINAL_COMMAND` fixed it. Known gap: the rsync branch still doesn't confine paths (use `rrsync`).
- **Port collision on 9095.** Loki's default gRPC port clashed with Promtail and the webhook listener. Fix: explicit gRPC ports (Loki 9096, Promtail 9097), webhook on 9095.
- **Permission denied on `/var/lib/prometheus`.** The service ran as a different user than the directory owner. The unit's `User=` and the data directory ownership must match.
- **Unit name collision when simulating two hosts on one VM.** Both VPS needed a `backup.service`, so the lab used `backup-vps1/2`. In production there is one `backup.service`, and the repo ships that form.
- **DNS caching made a successful flip look delayed.** `dig` against the local resolver kept returning the old IP; `dig +trace` against the authoritative servers proved the record had already changed. Always verify at the authority first.
