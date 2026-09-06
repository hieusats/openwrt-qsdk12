#!/bin/bash
# Fixpoint-resolve kernel kconfig NEW symbols, then build the world.
# Each NEW symbol prompt aborts silentoldconfig; append a default answer and retry.
set -e
apt-get update -q >/dev/null
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  build-essential libncurses5-dev libncursesw5-dev zlib1g-dev gawk git gettext \
  libssl-dev xsltproc wget unzip python2 python3 file rsync ca-certificates curl ccache >/dev/null
update-alternatives --install /usr/bin/python python /usr/bin/python2 1 >/dev/null 2>&1 || true
git config --global --add safe.directory /src

cd /src
# xtables-addons 2.14 (pulled only by kmod-ipt-nathelper-rtsp) is incompatible
# with kernel 5.4: VLA/shash_desc/renamed-API failures under -Werror. Disable it.
sed -i 's|^CONFIG_PACKAGE_kmod-ipt-nathelper-rtsp=y|# CONFIG_PACKAGE_kmod-ipt-nathelper-rtsp is not set|' .config
make defconfig >/dev/null 2>&1 || true
CFG=target/linux/ipq53xx/ipq53xx_32/config-default

for i in $(seq 1 80); do
  if out=$(make -j$(nproc) target/linux/compile V=s 2>&1); then
    echo "=== KERNEL COMPILE OK (iteration $i) ==="
    break
  fi
  line=$(echo "$out" | grep '(NEW)' | tail -1 || true)
  if [ -z "$line" ]; then
    echo "=== REAL ERROR (no NEW symbol left) ==="
    echo "$out" | grep -vE 'WARNING: Makefile' | tail -60
    exit 1
  fi
  sym=$(echo "$line" | sed -n 's/.*(\([A-Za-z0-9_]*\)) \[[^]]*\] (NEW).*/\1/p')
  [ -z "$sym" ] && {
    echo "cannot parse symbol from: $line"
    echo "$out" | tail -40
    exit 1
  }
  brk=$(echo "$line" | grep -oE '\[[^]]*\]' | head -1 | tr -d '[]')
  # bracket shows UPPERCASE default + lowercase options: [N/m/y/?], [N/m/?], [Y/n/?]...
  def=$(echo "$brk" | grep -oE '[NMY]' | head -1 | tr 'NMY' 'nmy')
  case "$def" in
  n) entry="# CONFIG_$sym is not set" ;;
  m) entry="CONFIG_$sym=m" ;;
  y) entry="CONFIG_$sym=y" ;;
  '')
    if [ -z "$brk" ]; then entry="CONFIG_$sym=\"\""; else entry="CONFIG_$sym=$brk"; fi
    ;;
  *) entry="CONFIG_$sym=$brk" ;;
  esac
  if [ "$sym" = "$prev_sym" ]; then
    stuck=$((stuck + 1))
    [ "$stuck" -ge 3 ] && {
      echo "STUCK on $sym — parse bug"
      exit 1
    }
  else
    stuck=0
  fi
  prev_sym=$sym
  echo "iter $i: $sym -> $entry"
  echo "$entry" >>"$CFG"
  if [ "$i" = "80" ]; then
    echo "TOO MANY ITERATIONS"
    exit 1
  fi
done

echo '=== full world build ==='
make -j$(nproc) || make -j1 V=s
echo '=== outputs ==='
find bin -type f | head -100
