#!/bin/bash
# Resolve all NEW kernel kconfig symbols in one pass:
# 1) yes '' | make kernel_oldconfig  -> accepts defaults for every NEW symbol
# 2) diff resolved .config vs (config-5.4 + config-default) -> append only missing symbols
set -e
apt-get update -q >/dev/null
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  build-essential libncurses5-dev libncursesw5-dev zlib1g-dev gawk git gettext \
  libssl-dev xsltproc wget unzip python2 python3 file rsync ca-certificates curl ccache >/dev/null
update-alternatives --install /usr/bin/python python /usr/bin/python2 1 >/dev/null 2>&1 || true

cd /src
echo '=== kernel_oldconfig (accept all defaults) ==='
yes '' | make kernel_oldconfig || { echo OLDCONFIG-FAILED; exit 1; }

echo '=== merging missing symbols into config-default ==='
python3 - <<'EOF'
import re, glob

def syms_from(path):
    out = {}
    for line in open(path, errors='replace'):
        line = line.strip()
        m = re.match(r'# (CONFIG_[A-Za-z0-9_]+) is not set', line)
        if m:
            out[m.group(1)] = line
            continue
        m = re.match(r'(CONFIG_[A-Za-z0-9_]+)=.*', line)
        if m:
            out[m.group(1)] = line
    return out

existing = {}
for f in ['target/linux/ipq53xx/config-5.4',
          'target/linux/ipq53xx/ipq53xx_32/config-default']:
    existing.update(syms_from(f))

bd = glob.glob('build_dir/target-*/linux-ipq53xx_ipq53xx_32/linux-*/.config')
assert bd, 'no resolved kernel .config found'
resolved = syms_from(bd[0])

missing = {k: v for k, v in resolved.items() if k not in existing}
with open('target/linux/ipq53xx/ipq53xx_32/config-default', 'a') as f:
    f.write('\n# auto-resolved NEW symbols (defaults accepted via kernel_oldconfig)\n')
    for k in sorted(missing):
        f.write(missing[k] + '\n')
print(f'appended {len(missing)} symbols, e.g.:')
for k in sorted(missing)[:10]:
    print(' ', missing[k])
EOF
echo '=== verify: prepare passes now ==='
make target/linux/prepare && echo PREPARE-OK
