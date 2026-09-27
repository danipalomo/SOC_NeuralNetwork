#!/bin/bash
set -eu
touch /var/log/soc_neuralnetwork-lab.json
python3 - <<'PY'
from pathlib import Path
import subprocess
password = Path('/run/secrets/lab_password').read_text().strip()
subprocess.run(['chpasswd'], input='lab-user:' + password + '\n', text=True, check=True)
PY
cat > /etc/ssh/sshd_config.d/soc_neuralnetwork-lab.conf <<'EOF'
Port 12222
ListenAddress 127.0.0.1
PasswordAuthentication yes
PermitRootLogin no
AllowUsers lab-user
UsePAM no
EOF
mkdir -p /run/soc_neuralnetwork
if [ ! -f /run/soc_neuralnetwork/blocked-ips.json ]; then
  echo '[]' > /run/soc_neuralnetwork/blocked-ips.json
fi
chmod 600 /run/soc_neuralnetwork/blocked-ips.json
