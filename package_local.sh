#!/bin/bash
# Package rd15-openwrt.ubi from built FIT + squashfs rootfs.
# Volume names MUST match u-boot strings: kernel + ubi_rootfs
#   bootargs: ubi.mtd=rootfs root=mtd:ubi_rootfs rootfstype=squashfs
#   webfailsafe: raw UBI image (magic UBI#) -> "flash rootfs" writes at partition start
set -e
apt-get update -q >/dev/null
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends mtd-utils file >/dev/null

cd /src
BIN=bin/targets/ipq53xx/ipq53xx_32
FIT=$BIN/openwrt-ipq53xx-ipq53xx_32-ipq5332-xiaomi-rd15-fit-uImage.itb
ROOT=$BIN/openwrt-ipq53xx-ipq53xx_32-squashfs-root.img
[ -f "$FIT" ] || { echo "MISSING: $FIT"; ls $BIN | head; exit 1; }
[ -f "$ROOT" ] || { echo "MISSING: $ROOT"; exit 1; }

# pad kernel FIT to 4KiB multiple (ubinize static volume requirement is fine either way)
P=$(stat -c%s "$FIT"); PAD=$(( (P + 4095) / 4096 * 4096 ))
cp "$FIT" /tmp/kernel-pad.itb
truncate -s "$PAD" /tmp/kernel-pad.itb

cat > /tmp/ubi.cfg <<EOF
[kernel]
mode=static
image=/tmp/kernel-pad.itb
vol_id=0
vol_name=kernel
vol_size=$PAD
[ubi_rootfs]
mode=ubi
image=$ROOT
vol_id=1
vol_name=ubi_rootfs
vol_flags=autoresize
EOF

ubinize -m 2048 -p 128KiB -o /src/rd15-openwrt.ubi /tmp/ubi.cfg
echo '=== result ==='
ls -l /src/rd15-openwrt.ubi
file /src/rd15-openwrt.ubi
xxd /src/rd15-openwrt.ubi | head -3
