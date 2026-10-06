#!/bin/bash
# The test initrd: Alpine packages (pinned by Bazel, see BUILD.bazel) unpacked
# into a root, the init script, the test SSH key, packed as a gzip cpio.
# usage: make-initrd.sh <out.cpio.gz> <init> <authorized_keys> <pkg.apk>...
set -euo pipefail
OUT=$1; INIT=$2; KEYS=$3; shift 3
R=$(mktemp -d); trap 'rm -rf "$R"' EXIT
for f in "$@"; do tar -xzf "$f" -C "$R" --exclude='.PKGINFO' --exclude='.SIGN.*' --exclude='.post-*' --exclude='.pre-*' --exclude='.trigger' 2>/dev/null || true; done
mkdir -p "$R/bin" "$R/sbin" "$R/proc" "$R/sys" "$R/dev" "$R/root/.ssh" "$R/etc/dropbear" "$R/var/run" "$R/lib" "$R/usr/lib"
"$R/bin/busybox.static" --install -s "$R/bin" 2>/dev/null || true
cp "$R/bin/busybox.static" "$R/bin/busybox"
for a in sh ip mount umount mkdir echo uname setsid sleep cat ls; do ln -sf busybox "$R/bin/$a"; done
# musl's loader searches /lib and /usr/lib: the packages' libraries go to both
for so in "$R"/usr/lib/*.so* "$R"/lib/*.so*; do [ -e "$so" ] || continue; b=$(basename "$so"); [ -e "$R/lib/$b" ] || cp -a "$so" "$R/lib/$b"; [ -e "$R/usr/lib/$b" ] || cp -a "$so" "$R/usr/lib/$b"; done
printf 'root:x:0:0:root:/root:/bin/sh\n' > "$R/etc/passwd"
printf 'root:*::0:::::\n' > "$R/etc/shadow"
printf 'root:x:0:\n' > "$R/etc/group"
install -m 600 "$KEYS" "$R/root/.ssh/authorized_keys"
install -m 755 "$INIT" "$R/init"
(cd "$R" && find . | LC_ALL=C sort | cpio -o -H newc --quiet -R +0:+0 --reproducible 2>/dev/null || (cd "$R" && find . | LC_ALL=C sort | cpio -o -H newc --quiet -R +0:+0)) | gzip -9 -n > "$OUT"
