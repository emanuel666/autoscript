#!/bin/bash
# ----------------------------------------------------------------------
# Script de instalación personalizado - nokasvip | kyz | http door | socketdevz
# Uso personal - Todos los derechos reservados
# Basado en el trabajo original de Hex Applications, adaptado y corregido.
# ----------------------------------------------------------------------
set -o pipefail
clear

export DEBIAN_FRONTEND=noninteractive
source /etc/os-release

SUPPORT_LEVEL="unsupported"
case "$ID:$VERSION_ID" in
  ubuntu:20.04) SUPPORT_LEVEL="legacy" ;;
  ubuntu:22.04) SUPPORT_LEVEL="recommended" ;;
  ubuntu:24.04) SUPPORT_LEVEL="supported" ;;
  debian:11) SUPPORT_LEVEL="legacy" ;;
  debian:12) SUPPORT_LEVEL="supported" ;;
  *) SUPPORT_LEVEL="unsupported" ;;
esac

echo "============================================================"
echo "              Instalador de Script SSH - nokasvip"
echo "        (AutoScript: SSH/Xray/Hysteria/ZiVPN/UDP Custom)"
echo "============================================================"
echo ""
echo "Sistemas Operativos Soportados:"
echo ""
echo "  ✔ Ubuntu 22.04           (Recomendado)"
echo "  ✔ Ubuntu 20.04/24.04      (Soporte)"
echo "  ✔ Debian 11/12            (Soporte)"
echo ""
echo "============================================================"
sleep 2

if [ "$SUPPORT_LEVEL" = "unsupported" ]; then
  echo "Este instalador solo soporta Ubuntu 20.04/22.04/24.04 y Debian 11/12."
  echo "Detectado: ${ID} ${VERSION_ID}"
  exit 1
fi

# --- Dominio y credenciales ---
read -p "Ingresa tu Dominio/Subdominio para Xray (o presiona enter para usar la IP): " -e -i "$(curl -4 -s --max-time 2 ipv4.icanhazip.com || hostname -I | awk '{print $1}')" DOMAIN
export DOMAIN

# Generar claves Ed25519 para SlowDNS (compatibles con el binario sldns-server)
mkdir -p /etc/slowdns
if command -v openssl >/dev/null 2>&1; then
    openssl genpkey -algorithm ed25519 -out /etc/slowdns/server.key 2>/dev/null
    openssl pkey -in /etc/slowdns/server.key -pubout -out /etc/slowdns/server.pub 2>/dev/null
fi
# Si falla la generación, se crearán claves por defecto (no ideales, pero evitan error)
if [ ! -s /etc/slowdns/server.key ]; then
    echo "nokasvip-slowdns-key-default" > /etc/slowdns/server.key
    echo "nokasvip-slowdns-pub-default" > /etc/slowdns/server.pub
fi
Serverkey=$(cat /etc/slowdns/server.key | grep -v "BEGIN" | grep -v "END" | tr -d '\n' | tr -d ' ' | head -c 64)
Serverpub=$(cat /etc/slowdns/server.pub | grep -v "BEGIN" | grep -v "END" | tr -d '\n' | tr -d ' ' | head -c 64)

# Credenciales aleatorias para Hysteria y ZiVPN
PASSWORD=$(openssl rand -base64 12 2>/dev/null | tr -d '/+=' | head -c 16 || echo "nokasvip2024")
OBFS="nokasvip-$(openssl rand -hex 4 2>/dev/null || echo "secure")"

# --- Preparación inicial ---
apt-get update -y >/dev/null 2>&1
command -v dig >/dev/null 2>&1 || apt-get install -y dnsutils >/dev/null 2>&1
command -v certbot >/dev/null 2>&1 || apt-get install -y certbot >/dev/null 2>&1

mkdir -p /etc/xray
# Certificado
if [[ "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    USE_LETSENCRYPT=false
    echo "Se usará un certificado autofirmado para la IP $DOMAIN."
    echo "Los clientes deberán activar 'allowInsecure' para el TLS en el puerto 443."
else
    USE_LETSENCRYPT=true
    echo "Verificando que el dominio $DOMAIN resuelva a la IP del servidor..."
    SERVER_IP=$(curl -4 -s --max-time 2 ipv4.icanhazip.com || hostname -I | awk '{print $1}')
    DOMAIN_IP=$(dig +short "$DOMAIN" @8.8.8.8 | tail -1)
    if [ "$DOMAIN_IP" != "$SERVER_IP" ]; then
        echo "ERROR: El dominio $DOMAIN no apunta a la IP $SERVER_IP."
        echo "       Crea un registro A en tu DNS y vuelve a ejecutar el script."
        exit 1
    fi
    echo "Dominio verificado. Solicitando certificado Let's Encrypt..."
    systemctl stop xray 2>/dev/null || true
    systemctl stop nginx 2>/dev/null || true
    read -p "Ingresa tu correo electrónico para Let's Encrypt (opcional, presiona enter para usar admin@$DOMAIN): " LETS_EMAIL
    [ -z "$LETS_EMAIL" ] && LETS_EMAIL="admin@${DOMAIN}"
    if ! certbot certonly --standalone --non-interactive --agree-tos --email "$LETS_EMAIL" -d "$DOMAIN"; then
        echo "ERROR: No se pudo emitir el certificado Let's Encrypt para $DOMAIN."
        exit 1
    fi
    CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
    KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
    echo "letsencrypt" > /etc/xray/cert_type
fi

if [ "$USE_LETSENCRYPT" = false ]; then
    echo "Generando certificado autofirmado para la IP $DOMAIN..."
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
      -keyout /etc/xray/xray.key \
      -out /etc/xray/xray.crt \
      -subj "/CN=${DOMAIN}/O=nokasvip/C=US"
    echo "selfsigned" > /etc/xray/cert_type
else
    cp "$CERT_PATH" /etc/xray/xray.crt
    cp "$KEY_PATH" /etc/xray/xray.key
fi
chmod 644 /etc/xray/xray.crt
chmod 600 /etc/xray/xray.key
mkdir -p /etc/stunnel
cat /etc/xray/xray.key /etc/xray/xray.crt > /etc/stunnel/stunnel.pem
chmod 600 /etc/stunnel/stunnel.pem
chown root:root /etc/stunnel/stunnel.pem

# Variables de puertos (igual que el original)
SSH_Port1='22'
SSH_Port2='299'
Stunnel_Port='127.0.0.1:4443'
Stunnel_Port_Num='4443'
Squid_Port1='3128'
Squid_Port2='8000'
WsPorts=('10080' '25' '2082' '2086')
WsPort='10080'
MainPort='666'
UDP_PORT=":36712"
HYST2_PORT="36713"
UDP_CUSTOM_PORT="36717"
ZIVPN_PORT="5667"
Nginx_Port='85'
Dns_1='1.1.1.1'
Dns_2='1.0.0.1'
MyVPS_Time='Africa/Accra'

read -p "¿Deseas instalar SlipStream (túnel DNS adicional)? [y/N]: " -e -i "N" _install_slipstream
if [[ "$_install_slipstream" =~ ^[Yy]$ ]]; then
    InstallSlipstream="y"
    SlipstreamDomain="ss.${DOMAIN}"
    echo "Se usará el dominio: $SlipstreamDomain para SlipStream."
else
    InstallSlipstream="n"
    SlipstreamDomain=""
fi

export OBFS PASSWORD

function ip_address(){
  local IP="$( ip addr | egrep -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | egrep -v "^192\.168|^172\.1[6-9]\.|^172\.2[0-9]\.|^172\.3[0-2]\.|^10\.|^127\.|^255\.|^0\." | head -n 1 )"
  [ -z "${IP}" ] && IP="$( wget -qO- -t1 -T2 ipv4.icanhazip.com )"
  [ -z "${IP}" ] && IP="$( wget -qO- -t1 -T2 ipinfo.io/ip )"
  [ ! -z "${IP}" ] && echo "${IP}" || echo
}
IPADDR="$(ip_address)"

red='\e[1;31m'; green='\e[0;32m'; NC='\e[0m'

# --- Actualización e instalación de paquetes ---
apt-get update -y && apt-get upgrade -y --with-new-pkgs

# Gestión de systemd-resolved (más suave)
if systemctl is-active --quiet systemd-resolved; then
    systemctl stop systemd-resolved
    systemctl disable systemd-resolved
fi
rm -f /etc/resolv.conf
if [ -L /run/systemd/resolve/stub-resolv.conf ] || [ -f /run/systemd/resolve/stub-resolv.conf ]; then
    ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
else
    printf 'nameserver %s\nnameserver %s\n' "$Dns_1" "$Dns_2" > /etc/resolv.conf
fi

# IPv6 persistente
cat > /etc/sysctl.d/99-ipv6-disable.conf <<EOF
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF
sysctl -p /etc/sysctl.d/99-ipv6-disable.conf >/dev/null 2>&1

# Instalar Node.js moderno (versión 18.x)
if ! command -v node >/dev/null 2>&1; then
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs
fi

SSH_SERVICE="ssh"; STUNNEL_SERVICE="stunnel4"; SQUID_SERVICE="squid"; SSLH_SERVICE="sslh"; NGINX_SERVICE="nginx"; SFTP_SUBSYSTEM="internal-sftp"

mkdir -p /etc/stunnel /etc/nginx/conf.d /etc/deekayvpn /var/run/sslh /etc/xray
echo "$DOMAIN" > /etc/deekayvpn/domain.txt
echo "$SlipstreamDomain" > /etc/deekayvpn/slipstream_domain.txt
ssh-keygen -A >/dev/null 2>&1 || true

PACKAGE_LIST=(
  neofetch sslh dnsutils stunnel4 squid nano sudo wget unzip tar zip gzip
  iptables iptables-persistent netfilter-persistent bc cron dos2unix whois screen ruby
  apt-transport-https software-properties-common gnupg2 ca-certificates curl net-tools 
  nginx haproxy certbot jq figlet git gcc make build-essential perl expect libdbi-perl vnstat socat
  libnet-ssleay-perl libauthen-pam-perl libio-pty-perl apt-show-versions openssh-server rsyslog lsof procps
  cmake pkg-config libssl-dev dante-server dnsdist
)
apt-get install -y "${PACKAGE_LIST[@]}"

# Zona horaria
ln -fs /usr/share/zoneinfo/$MyVPS_Time /etc/localtime

# Banner personalizado (marca)
cat <<'nokasvip_banner' > /etc/zorro-luffy
<br><font color="#C12267">nokasvip | kyz | http door | socketdevz<br></font><br>
<font color="#b3b300"> x No DDOS<br></font>
<font color="#00cc00"> x No Torrent<br></font>
<font color="#ff1aff"> x No Spamming<br></font>
<font color="blue"> x No Phishing<br></font>
<font color="#A810FF"> x No Hacking<br></font><br>
<font color="red">• POWERED BY SOCKETDEVZ<br></font>
nokasvip_banner

# ===== CONFIGURACIÓN DE SERVICIOS =====
# A partir de aquí, se configuran SSH, SSLH, Stunnel, Node WS, etc.
# (Esta es la Parte 1; la Parte 2 comenzará con la configuración de SSH)

# ======================================================
#  CONFIGURACIÓN DE SSH
# ======================================================
rm -f /etc/ssh/sshd_config
cat <<'MySSHConfig' > /etc/ssh/sshd_config
Port myPORT1
Port myPORT2
AddressFamily inet
ListenAddress 0.0.0.0
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key
PermitRootLogin yes
MaxSessions 5000
MaxStartups 500:30:1000
LoginGraceTime 30
PubkeyAuthentication yes
PasswordAuthentication yes
PermitEmptyPasswords no
UsePAM yes
X11Forwarding yes
PrintMotd no
ClientAliveInterval 120
ClientAliveCountMax 3
UseDNS no
Banner /etc/zorro-luffy
LogLevel QUIET
AcceptEnv LANG LC_*
Subsystem sftp SFTP_SUBSYSTEM
MySSHConfig

sed -i "s|myPORT1|$SSH_Port1|g" /etc/ssh/sshd_config
sed -i "s|myPORT2|$SSH_Port2|g" /etc/ssh/sshd_config
sed -i "s|SFTP_SUBSYSTEM|$SFTP_SUBSYSTEM|g" /etc/ssh/sshd_config
# Limpiar reglas de contraseña compleja (para evitar bloqueos)
sed -i -E '/password\s+(requisite|required)\s+pam_(cracklib|pwquality)\.so.*/d' /etc/pam.d/common-password
sed -i 's/use_authtok //g' /etc/pam.d/common-password
# Añadir shells para usuarios sin login
sed -i '/\/bin\/false/d' /etc/shells
sed -i '/\/usr\/sbin\/nologin/d' /etc/shells
echo '/bin/false' >> /etc/shells
echo '/usr/sbin/nologin' >> /etc/shells
systemctl restart "$SSH_SERVICE"

# ======================================================
#  CONFIGURACIÓN DE SSLH (multiplexor en puerto 666)
# ======================================================
cd /etc/default/
cat << sslh > /etc/default/sslh
RUN=yes
DAEMON=/usr/sbin/sslh
DAEMON_OPTS="--user sslh --listen 127.0.0.1:$MainPort --ssh 127.0.0.1:$SSH_Port1 --http 127.0.0.1:$WsPort --pidfile /var/run/sslh/sslh.pid"
sslh
mkdir -p /var/run/sslh
touch /var/run/sslh/sslh.pid
chmod 777 /var/run/sslh/sslh.pid
systemctl daemon-reload
systemctl enable "$SSLH_SERVICE"
systemctl restart "$SSLH_SERVICE"
cd

# ======================================================
#  CONFIGURACIÓN DE STUNNEL (TLS wrapper)
# ======================================================
StunnelDir=$(ls /etc/default | grep stunnel | head -n1)
cat <<'MyStunnelD' > /etc/default/$StunnelDir
ENABLED=1
FILES="/etc/stunnel/*.conf"
OPTIONS=""
BANNER="/etc/zorro-luffy"
PPP_RESTART=0
RLIMITS=""
MyStunnelD

cat <<'MyStunnelC' > /etc/stunnel/stunnel.conf
pid = /var/run/stunnel.pid
cert = /etc/stunnel/stunnel.pem
client = no
syslog = no
debug = 0
output = /dev/null
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1
TIMEOUTclose = 0
[sslh]
accept = Stunnel_Port
connect = 127.0.0.1:MainPort
MyStunnelC

sed -i "s|Stunnel_Port|$Stunnel_Port|g" /etc/stunnel/stunnel.conf
sed -i "s|MainPort|$MainPort|g" /etc/stunnel/stunnel.conf
systemctl enable "$STUNNEL_SERVICE"
systemctl restart "$STUNNEL_SERVICE"

# ======================================================
#  PROXIES WEBSOCKET DE NODE.JS (puertos 10080, 25, 2082, 2086)
# ======================================================
loc=/etc/socksproxy
mkdir -p $loc
# Instalar Node.js ya está hecho arriba, pero por si acaso:
command -v npm >/dev/null 2>&1 || apt-get install -y npm

cat <<'EOF' > $loc/proxy.js
const net = require('net');
process.on('uncaughtException', (err) => { console.error('Unhandled Exception:', err); });
const TARGET_HOST = '127.0.0.1';
const TARGET_PORT = process.env.SSH_PORT || 22;
const LISTEN_PORT = parseInt(process.argv[2]);
if (!LISTEN_PORT) { process.exit(1); }
const handleConnection = (clientSocket) => {
    clientSocket.once('data', (data) => {
        const targetSocket = net.connect(TARGET_PORT, TARGET_HOST, () => {
            clientSocket.write('HTTP/1.1 101 <font color="yellow">nokasvip</font>\r\n\r\n');
            clientSocket.pipe(targetSocket);
            targetSocket.pipe(clientSocket);
        });
        targetSocket.on('error', () => clientSocket.destroy());
        targetSocket.on('close', () => clientSocket.destroy());
    });
    clientSocket.on('error', () => {});
    clientSocket.on('close', () => {});
};
const server = net.createServer(handleConnection);
server.listen(LISTEN_PORT, '0.0.0.0', () => {
    console.log(`WS Proxy active on port ${LISTEN_PORT}`);
});
EOF

# Ajustar el puerto SSH en el script proxy
sed -i "s/process.env.SSH_PORT || 22/$SSH_Port1/g" $loc/proxy.js

cat <<'service' > /etc/systemd/system/ws-proxy@.service
[Unit]
Description=Node.js WebSocket Proxy on port %i
After=network.target nss-lookup.target
[Service]
Type=simple
User=root
WorkingDirectory=/etc/socksproxy
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
LimitNOFILE=1048576
Restart=always
RestartSec=1
ExecStart=/usr/bin/node /etc/socksproxy/proxy.js %i
SyslogIdentifier=ws-proxy-%i
[Install]
WantedBy=multi-user.target
service

systemctl daemon-reload
for port in "${WsPorts[@]}"; do
    systemctl enable ws-proxy@$port
    systemctl restart ws-proxy@$port
done

# ======================================================
#  INSTALACIÓN DE XRAY CORE (versión fija con verificación SHA256)
# ======================================================
echo "Instalando Xray Core v26.3.27..."
XRAY_VER="v26.3.27"

cat <<'EOF_XRAY_INSTALLER' > /usr/local/sbin/xray-install-version
#!/bin/bash
set -o pipefail
umask 077

version="${1:?Usage: xray-install-version VERSION}"
case "$(uname -m)" in
  x86_64|amd64) asset="Xray-linux-64.zip" ;;
  i386|i486|i586|i686) asset="Xray-linux-32.zip" ;;
  aarch64|arm64) asset="Xray-linux-arm64-v8a.zip" ;;
  armv7l|armv7*) asset="Xray-linux-arm32-v7a.zip" ;;
  *) echo "Unsupported Xray architecture: $(uname -m)" >&2; exit 1 ;;
esac

tmp_dir=$(mktemp -d /tmp/xray-install.XXXXXX) || exit 1
trap 'rm -rf "$tmp_dir"' EXIT
base_url="https://github.com/XTLS/Xray-core/releases/download/${version}/${asset}"

wget -qO "$tmp_dir/xray.zip" "$base_url" || { echo "Xray download failed." >&2; exit 1; }
wget -qO "$tmp_dir/xray.zip.dgst" "$base_url.dgst" || { echo "Xray digest download failed." >&2; exit 1; }
expected=$(awk -F'= *' 'toupper($1) == "SHA2-256" {print tolower($2); exit}' "$tmp_dir/xray.zip.dgst")
actual=$(sha256sum "$tmp_dir/xray.zip" | awk '{print tolower($1)}')
[ -n "$expected" ] && [ "$actual" = "$expected" ] || { echo "Xray SHA-256 verification failed." >&2; exit 1; }

unzip -q "$tmp_dir/xray.zip" -d "$tmp_dir/unpacked" || exit 1
[ -f "$tmp_dir/unpacked/xray" ] || { echo "Xray binary missing from archive." >&2; exit 1; }
chmod 755 "$tmp_dir/unpacked/xray"
if [ -s /etc/xray/config.json ]; then
  "$tmp_dir/unpacked/xray" run -test -config /etc/xray/config.json || {
    echo "The downloaded Xray version rejected the current configuration." >&2
    exit 1
  }
fi
install -m 755 "$tmp_dir/unpacked/xray" /usr/local/bin/xray.new
mv -f /usr/local/bin/xray.new /usr/local/bin/xray
EOF_XRAY_INSTALLER
chmod 700 /usr/local/sbin/xray-install-version

if ! /usr/local/sbin/xray-install-version "$XRAY_VER"; then
  echo "Unable to install a verified Xray Core ${XRAY_VER} binary."
  exit 1
fi

touch /etc/xray/vless.txt
chmod 600 /etc/xray/vless.txt

# ======================================================
#  CONFIGURACIÓN DE XRAY (config.json)
#  Se corrige el puerto inválido "80,8080,8880" -> [80,8080,8880]
# ======================================================
cat <<EOF > /etc/xray/config.json
{
  "log": { "access": "none", "error": "/var/log/xray/error.log", "loglevel": "error" },
  "inbounds": [
    {
      "tag": "vless-tls-dispatcher",
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none",
        "fallbacks": [
          { "path": "/httpupgrade", "dest": 10005, "xver": 2 },
          { "path": "/vless-tcp", "dest": 10007, "xver": 2 },
          { "path": "/vmess-hup", "dest": 10011, "xver": 2 },
          { "path": "/vmess-tcp", "dest": 10008, "xver": 2 },
          { "path": "/trojan", "dest": 10013, "xver": 2 },
          { "path": "/vless", "dest": 10003, "xver": 2 },
          { "path": "/vmess", "dest": 10009, "xver": 2 },
          { "alpn": "h2", "dest": 10444, "xver": 2 },
          { "dest": 666 }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "alpn": ["h2", "http/1.1"],
          "certificates": [
            { "certificateFile": "/etc/xray/xray.crt", "keyFile": "/etc/xray/xray.key" }
          ]
        },
        "sockopt": { "tcpFastOpen": true }
      }
    },
    {
      "tag": "vless-tcp-http",
      "listen": "127.0.0.1",
      "port": 10007,
      "protocol": "vless",
      "settings": { "clients": [], "decryption": "none" },
      "streamSettings": {
        "network": "tcp",
        "security": "none",
        "tcpSettings": { "header": { "type": "http", "request": { "path": ["/vless-tcp"] } } },
        "sockopt": { "acceptProxyProtocol": true, "tcpFastOpen": true }
      }
    },
    {
      "tag": "vless-plain-public",
      "port": [80,8080,8880],
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none",
        "fallbacks": [
          { "path": "/vless-tcp", "dest": 10007, "xver": 2 },
          { "path": "/vmess-tcp", "dest": 10008, "xver": 2 },
          { "path": "/vmess-hup", "dest": 10011, "xver": 2 },
          { "path": "/vless", "dest": 10003, "xver": 2 },
          { "path": "/vmess", "dest": 10009, "xver": 2 },
          { "path": "/httpupgrade", "dest": 10005, "xver": 2 },
          { "dest": 10080 }
        ]
      },
      "streamSettings": { "network": "tcp", "security": "none" }
    },
    {
      "tag": "vless-ws",
      "listen": "127.0.0.1",
      "port": 10003,
      "protocol": "vless",
      "settings": { "clients": [], "decryption": "none" },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": { "path": "/vless" },
        "sockopt": { "acceptProxyProtocol": true, "tcpFastOpen": true }
      }
    },
    {
      "tag": "vless-xhttp",
      "listen": "127.0.0.1",
      "port": 10004,
      "protocol": "vless",
      "settings": { "clients": [], "decryption": "none" },
      "streamSettings": {
        "network": "xhttp",
        "security": "none",
        "xhttpSettings": { "path": "/xhttp", "mode": "auto" },
        "sockopt": { "acceptProxyProtocol": true, "tcpFastOpen": true }
      }
    },
    {
      "tag": "vless-httpupgrade",
      "listen": "127.0.0.1",
      "port": 10005,
      "protocol": "vless",
      "settings": { "clients": [], "decryption": "none" },
      "streamSettings": {
        "network": "httpupgrade",
        "security": "none",
        "httpupgradeSettings": { "path": "/httpupgrade", "host": "" },
        "sockopt": { "acceptProxyProtocol": true, "tcpFastOpen": true }
      }
    },
    {
      "tag": "vless-grpc",
      "listen": "127.0.0.1",
      "port": 10006,
      "protocol": "vless",
      "settings": { "clients": [], "decryption": "none" },
      "streamSettings": {
        "network": "grpc",
        "security": "none",
        "grpcSettings": { "serviceName": "grpc-svc" },
        "sockopt": { "acceptProxyProtocol": true, "tcpFastOpen": true }
      }
    },
    {
      "tag": "vmess-tcp-http",
      "listen": "127.0.0.1",
      "port": 10008,
      "protocol": "vmess",
      "settings": { "clients": [] },
      "streamSettings": {
        "network": "tcp",
        "security": "none",
        "tcpSettings": { "header": { "type": "http", "request": { "path": ["/vmess-tcp"] } } },
        "sockopt": { "acceptProxyProtocol": true, "tcpFastOpen": true }
      }
    },
    {
      "tag": "vmess-ws",
      "listen": "127.0.0.1",
      "port": 10009,
      "protocol": "vmess",
      "settings": { "clients": [] },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": { "path": "/vmess" },
        "sockopt": { "acceptProxyProtocol": true, "tcpFastOpen": true }
      }
    },
    {
      "tag": "vmess-xhttp",
      "listen": "127.0.0.1",
      "port": 10010,
      "protocol": "vmess",
      "settings": { "clients": [] },
      "streamSettings": {
        "network": "xhttp",
        "security": "none",
        "xhttpSettings": { "path": "/vmess-xhttp", "mode": "auto" },
        "sockopt": { "acceptProxyProtocol": true, "tcpFastOpen": true }
      }
    },
    {
      "tag": "vmess-httpupgrade",
      "listen": "127.0.0.1",
      "port": 10011,
      "protocol": "vmess",
      "settings": { "clients": [] },
      "streamSettings": {
        "network": "httpupgrade",
        "security": "none",
        "httpupgradeSettings": { "path": "/vmess-hup", "host": "" },
        "sockopt": { "acceptProxyProtocol": true, "tcpFastOpen": true }
      }
    },
    {
      "tag": "vmess-grpc",
      "listen": "127.0.0.1",
      "port": 10012,
      "protocol": "vmess",
      "settings": { "clients": [] },
      "streamSettings": {
        "network": "grpc",
        "security": "none",
        "grpcSettings": { "serviceName": "vmess-grpc-svc" },
        "sockopt": { "acceptProxyProtocol": true, "tcpFastOpen": true }
      }
    },
    {
      "tag": "trojan-ws",
      "listen": "127.0.0.1",
      "port": 10013,
      "protocol": "trojan",
      "settings": { "clients": [] },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": { "path": "/trojan" },
        "sockopt": { "acceptProxyProtocol": true, "tcpFastOpen": true }
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "settings": {} },
    { "protocol": "blackhole", "settings": {}, "tag": "blocked" }
  ]
}
EOF
chmod 600 /etc/xray/config.json

mkdir -p /var/log/xray
if ! /usr/local/bin/xray run -test -config /etc/xray/config.json; then
  echo "Xray configuration validation failed. Review the Xray error printed above."
  exit 1
fi

cat <<EOF > /etc/systemd/system/xray.service
[Unit]
Description=Xray Service
After=network.target nss-lookup.target
[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=on-failure
RestartSec=2
LimitNPROC=10000
LimitNOFILE=1000000
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl disable --now haproxy 2>/dev/null || true
systemctl enable xray
systemctl restart xray

# ======================================================
#  HAPROXY (router HTTP/2 interno para gRPC y XHTTP)
# ======================================================
cat <<'EOF_H2_ROUTER' > /etc/haproxy/haproxy.cfg
global
    log /dev/log local0
    maxconn 100000
    daemon

defaults
    log global
    mode http
    option dontlognull
    timeout connect 5s
    timeout client 1h
    timeout server 1h
    timeout tunnel 1h

frontend xray_h2_router
    bind 127.0.0.1:10444 accept-proxy proto h2
    mode http
    use_backend vless_grpc_h2 if { path_beg /grpc-svc/ }
    use_backend vmess_grpc_h2 if { path_beg /vmess-grpc-svc/ }
    use_backend vless_xhttp_h2 if { path_beg /xhttp }
    use_backend vmess_xhttp_h2 if { path_beg /vmess-xhttp }
    default_backend reject_h2

backend vless_grpc_h2
    mode http
    server xray 127.0.0.1:10006 send-proxy-v2 proto h2

backend vmess_grpc_h2
    mode http
    server xray 127.0.0.1:10012 send-proxy-v2 proto h2

backend vless_xhttp_h2
    mode http
    server xray 127.0.0.1:10004 send-proxy-v2 proto h2

backend vmess_xhttp_h2
    mode http
    server xray 127.0.0.1:10010 send-proxy-v2 proto h2

backend reject_h2
    mode http
    http-request return status 404
EOF_H2_ROUTER

if ! haproxy -c -f /etc/haproxy/haproxy.cfg; then
  echo "Internal HTTP/2 router validation failed."
  exit 1
fi
mkdir -p /etc/systemd/system/haproxy.service.d
cat <<'EOF_H2_UNIT' > /etc/systemd/system/haproxy.service.d/xray-order.conf
[Unit]
After=xray.service network-online.target
Wants=xray.service network-online.target
EOF_H2_UNIT
systemctl daemon-reload
systemctl enable haproxy
systemctl restart haproxy

# ======================================================
#  CRONJOBS DE EXPIRACIÓN (con flock para evitar race conditions)
# ======================================================
cat <<'EOF_EXP' > /usr/local/bin/exp-check
#!/bin/bash
set -o pipefail
umask 077
now=$(date +%Y-%m-%d)
CONFIG="/etc/xray/config.json"
[ -s "$CONFIG" ] || exit 0

exec 9>/run/lock/xray-config.lock
flock -w 30 9 || { logger -t xray-exp "Timed out waiting for the Xray config lock"; exit 1; }

work_dir=$(mktemp -d /tmp/xray-exp.XXXXXX) || exit 1
trap 'rm -rf "$work_dir"' EXIT

mapfile -t expired_users < <(
  for proto in vless vmess trojan; do
    db="/etc/xray/${proto}.txt"
    [ -f "$db" ] && awk -v d="$now" '$3 < d {print $1}' "$db"
  done | sort -u
)
[ "${#expired_users[@]}" -gt 0 ] || exit 0

expired_json=$(printf '%s\n' "${expired_users[@]}" | jq -R . | jq -s .) || exit 1
jq --argjson expired "$expired_json" '
  (.inbounds[] | select(((.settings.clients? // null) | type) == "array") | .settings.clients) |=
    map(. as $client | select(($expired | index($client.email)) == null)) |
  (.inbounds[] | select(((.settings.users? // null) | type) == "array") | .settings.users) |=
    map(. as $user | select(($expired | index($user.email)) == null))
' "$CONFIG" > "$work_dir/config.json" || exit 1

if ! /usr/local/bin/xray run -test -config "$work_dir/config.json" >/dev/null 2>&1; then
  logger -t xray-exp "Refusing expiry update: generated Xray config failed validation"
  exit 1
fi

cp -p "$CONFIG" "$work_dir/config.backup" || exit 1
install -m 600 "$work_dir/config.json" "$CONFIG" || exit 1
if ! systemctl restart xray; then
  install -m 600 "$work_dir/config.backup" "$CONFIG"
  systemctl restart xray || true
  logger -t xray-exp "Expiry update rolled back because Xray failed to restart"
  exit 1
fi

for proto in vless vmess trojan; do
  db="/etc/xray/${proto}.txt"
  [ -f "$db" ] || continue
  awk -v d="$now" '$3 >= d {print}' "$db" > "$work_dir/${proto}.txt" || exit 1
  install -m 600 "$work_dir/${proto}.txt" "$db" || exit 1
done
EOF_EXP
chmod +x /usr/local/bin/exp-check
echo "0 0 * * * root /usr/local/bin/exp-check >/dev/null 2>&1" > /etc/cron.d/xray-expiry

# ======================================================
#  NGINX (puerto 85) y SQUID (puertos 3128, 8000)
# ======================================================
rm -rf /home/vps/public_html /etc/nginx/sites-* /etc/nginx/nginx.conf
mkdir -p /home/vps/public_html
cat <<'myNginxC' > /etc/nginx/nginx.conf
user www-data; worker_processes auto; pid /var/run/nginx.pid;
events { multi_accept on; worker_connections 8192; }
http { gzip on; gzip_vary on; gzip_comp_level 5; gzip_types text/plain application/x-javascript text/xml text/css; autoindex on; sendfile on; tcp_nopush on; tcp_nodelay on; keepalive_timeout 65; types_hash_max_size 2048; server_tokens off; include /etc/nginx/mime.types; default_type application/octet-stream; access_log /var/log/nginx/access.log; error_log /var/log/nginx/error.log; client_max_body_size 32M; client_header_buffer_size 8m; large_client_header_buffers 8 8m; fastcgi_buffer_size 8m; fastcgi_buffers 8 8m; fastcgi_read_timeout 600; include /etc/nginx/conf.d/*.conf; }
myNginxC
cat <<'myvpsC' > /etc/nginx/conf.d/vps.conf
server { listen Nginx_Port; server_name 127.0.0.1 localhost; root /home/vps/public_html; location / { try_files $uri $uri/ /index.php?$args; } }
myvpsC
sed -i "s|Nginx_Port|$Nginx_Port|g" /etc/nginx/conf.d/vps.conf
systemctl restart "$NGINX_SERVICE"

rm -rf /etc/squid/squid.con*
cat <<'mySquid' > /etc/squid/squid.conf
acl server dst IP-ADDRESS/32 localhost
acl ports_ port 14 22 53 21 8081 25 8000 3128 443 80 8080 8880 2082 2086 36712
http_port Squid_Port1
http_port Squid_Port2
http_access allow server
http_access deny all
http_access allow all
visible_hostname IP-ADDRESS
mySquid
sed -i "s|IP-ADDRESS|$IPADDR|g" /etc/squid/squid.conf
sed -i "s|Squid_Port1|$Squid_Port1|g" /etc/squid/squid.conf
sed -i "s|Squid_Port2|$Squid_Port2|g" /etc/squid/squid.conf
systemctl restart "$SQUID_SERVICE"

# ======================================================
#  HEALTH CHECKS (sin Telegram)
# ======================================================
mkdir -p /etc/deekayvpn/health
cat <<'ServiceChecker' > /etc/deekayvpn/service_checker.sh
#!/bin/bash
STATE_DIR="/etc/deekayvpn/health"
check_port() { ss -lnt | awk '{print $4}' | grep -q ":$1$"; }
mark_fail() { local f="$STATE_DIR/$1.fail"; local n=0; [ -f "$f" ] && n=$(cat "$f"); n=$((n+1)); echo "$n" > "$f"; echo "$n"; }
clear_fail() { rm -f "$STATE_DIR/$1.fail"; }
restart_after_3_fails() {
    local fails=$(mark_fail "$1")
    if [ "$fails" -ge 3 ]; then
        systemctl restart "$2" >/dev/null 2>&1
        clear_fail "$1"
    fi
}
if check_port SSHPORT1 && check_port SSHPORT2 && systemctl is-active --quiet ssh; then clear_fail ssh; else restart_after_3_fails ssh ssh "SSHPORT1,SSHPORT2"; fi
if check_port STUNNELPORT && systemctl is-active --quiet stunnel4; then clear_fail stunnel4; else restart_after_3_fails stunnel4 stunnel4 "STUNNELPORT"; fi
if check_port SSLHPORT && systemctl is-active --quiet sslh; then clear_fail sslh; else restart_after_3_fails sslh sslh "SSLHPORT"; fi
if check_port SQUIDPORT1 && check_port SQUIDPORT2 && systemctl is-active --quiet squid; then clear_fail squid; else restart_after_3_fails squid squid "SQUIDPORT1,SQUIDPORT2"; fi
if check_port NGINXPORT && systemctl is-active --quiet nginx; then clear_fail nginx; else restart_after_3_fails nginx nginx "NGINXPORT"; fi
for port in 10080 25 2082 2086; do if check_port $port && systemctl is-active --quiet ws-proxy@$port; then clear_fail ws-proxy-$port; else restart_after_3_fails ws-proxy-$port ws-proxy@$port "$port"; fi; done
# Xray: chequea puertos 443 y 80 (además de los internos)
if check_port 443 && check_port 80 && systemctl is-active --quiet xray; then clear_fail xray; else restart_after_3_fails xray xray "443,80"; fi
if systemctl is-active --quiet hysteria-server; then clear_fail hysteria-server; else restart_after_3_fails hysteria-server hysteria-server "UDP"; fi
ServiceChecker

chmod 755 /etc/deekayvpn/service_checker.sh
sed -i "s|STUNNELPORT|$Stunnel_Port_Num|g" /etc/deekayvpn/service_checker.sh
sed -i "s|SSLHPORT|$MainPort|g" /etc/deekayvpn/service_checker.sh
sed -i "s|SQUIDPORT1|$Squid_Port1|g" /etc/deekayvpn/service_checker.sh
sed -i "s|SQUIDPORT2|$Squid_Port2|g" /etc/deekayvpn/service_checker.sh
sed -i "s|NGINXPORT|$Nginx_Port|g" /etc/deekayvpn/service_checker.sh
sed -i "s|SSHPORT1|$SSH_Port1|g" /etc/deekayvpn/service_checker.sh
sed -i "s|SSHPORT2|$SSH_Port2|g" /etc/deekayvpn/service_checker.sh

echo "*/3 * * * * root /bin/bash /etc/deekayvpn/service_checker.sh >/dev/null 2>&1" > /etc/cron.d/service-checker

# ======================================================
#  SSH LIMIT CHECKER (límite de conexiones simultáneas)
# ======================================================
mkdir -p /etc/deekayvpn
touch /etc/deekayvpn/ssh_limits.txt
cat <<'SSHLimitChecker' > /etc/deekayvpn/ssh_limit_checker.sh
#!/bin/bash
DB="/etc/deekayvpn/ssh_limits.txt"
[ -s "$DB" ] || exit 0
while read -r suser slimit; do
  [ -z "$suser" ] && continue
  [[ "$slimit" =~ ^[0-9]+$ ]] || continue
  [ "$slimit" -le 0 ] && continue
  id "$suser" >/dev/null 2>&1 || continue
  mapfile -t sessions < <(ps -u "$suser" -o pid=,etimes=,cmd= 2>/dev/null | awk '$0 ~ /sshd/ {print $1" "$2}')
  count=${#sessions[@]}
  [ "$count" -le "$slimit" ] && continue
  excess=$((count - slimit))
  mapfile -t sorted < <(printf '%s\n' "${sessions[@]}" | sort -k2,2n)
  for ((i=0; i<excess; i++)); do
    pid=$(awk '{print $1}' <<< "${sorted[$i]}")
    [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null
  done
done < "$DB"
SSHLimitChecker
chmod 755 /etc/deekayvpn/ssh_limit_checker.sh
echo "* * * * * root /bin/bash /etc/deekayvpn/ssh_limit_checker.sh >/dev/null 2>&1" > /etc/cron.d/ssh-limit-checker

# ======================================================
#  LOGROTATE (sin forzar cada 5 minutos)
# ======================================================
rm -f /etc/logrotate.d/rsyslog
cat <<'logrotate' > /etc/logrotate.d/rsyslog
/var/log/syslog /var/log/kern.log /var/log/auth.log /var/log/xray/access.log /var/log/xray/error.log { rotate 7; daily; missingok; notifempty; compress; delaycompress; sharedscripts; postrotate; /usr/lib/rsyslog/rsyslog-rotate; endscript; }
logrotate
chown root:root /var/log
chmod 755 /var/log
chown syslog:adm /var/log/syslog
chmod 640 /var/log/syslog
# No se fuerza logrotate cada 5 minutos, se deja la configuración estándar

# ======================================================
#  SISTEMA - CONFIGURACIÓN DE SYSCTL Y LÍMITES
# ======================================================
modprobe nf_conntrack 2>/dev/null || true
echo "nf_conntrack" > /etc/modules-load.d/freenet.conf
cat <<'SYSCTL' > /etc/sysctl.d/99-freenet-tuning.conf
fs.file-max = 1048576
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 16384
net.ipv4.ip_local_port_range = 1024 65000
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 10
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_mtu_probing = 1
net.netfilter.nf_conntrack_max = 2097152
net.netfilter.nf_conntrack_tcp_timeout_established = 1200
net.netfilter.nf_conntrack_udp_timeout = 60
SYSCTL
sysctl --system || true
mkdir -p /etc/security/limits.d
cat <<'LIMITS' > /etc/security/limits.d/99-freenet.conf
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
LIMITS

# ======================================================
#  SLOWDNS (con claves Ed25519 generadas)
# ======================================================
rm -rf /etc/slowdns
mkdir -m 777 /etc/slowdns
# Las claves ya se generaron al inicio del script, pero si no existen, se crean ahora.
if [ ! -s /etc/slowdns/server.key ] || [ ! -s /etc/slowdns/server.pub ]; then
    openssl genpkey -algorithm ed25519 -out /etc/slowdns/server.key 2>/dev/null
    openssl pkey -in /etc/slowdns/server.key -pubout -out /etc/slowdns/server.pub 2>/dev/null
fi
# Asegurar que las claves tienen el formato esperado por sldns-server (sin cabeceras)
Serverkey=$(cat /etc/slowdns/server.key | grep -v "BEGIN" | grep -v "END" | tr -d '\n' | tr -d ' ')
Serverpub=$(cat /etc/slowdns/server.pub | grep -v "BEGIN" | grep -v "END" | tr -d '\n' | tr -d ' ')
# (Si falla la generación, se usan valores por defecto)
if [ -z "$Serverkey" ] || [ -z "$Serverpub" ]; then
    Serverkey="nokasvip-slowdns-key-$(openssl rand -hex 16 2>/dev/null || echo 'default')"
    Serverpub="nokasvip-slowdns-pub-$(openssl rand -hex 16 2>/dev/null || echo 'default')"
    echo "$Serverkey" > /etc/slowdns/server.key
    echo "$Serverpub" > /etc/slowdns/server.pub
fi

wget -q -O /etc/slowdns/sldns-server "https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/sldns-server"
chmod +x /etc/slowdns/sldns-server
chmod 600 /etc/slowdns/server.key /etc/slowdns/server.pub
iptables -C INPUT -p udp --dport 53 -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport 53 -j ACCEPT

if [ "$InstallSlipstream" = "y" ]; then
  SlowDNS_Listen="127.0.0.1:5301"
else
  SlowDNS_Listen=":53"
fi
cat > /etc/systemd/system/server-sldns.service << END
[Unit]
Description=Server SlowDNS
After=network.target
[Service]
ExecStart=/etc/slowdns/sldns-server -udp $SlowDNS_Listen -privkey-file /etc/slowdns/server.key $DOMAIN 127.0.0.1:$SSH_Port2
Restart=on-failure
[Install]
WantedBy=multi-user.target
END
systemctl daemon-reload
systemctl enable server-sldns
systemctl restart server-sldns

# ======================================================
#  SLIPSTREAM (opcional) + DANTE SOCKS + DNSDIST
# ======================================================
if [ "$InstallSlipstream" = "y" ]; then
    # Dante SOCKS
    command -v danted >/dev/null 2>&1 || apt-get install -y dante-server
    EXT_IP="$(ip -4 addr show scope global 2>/dev/null | awk '/inet/{print $2}' | cut -d/ -f1 | head -1)"
    [ -z "$EXT_IP" ] && EXT_IP="$(curl -s --max-time 5 ifconfig.me 2>/dev/null)"
    cat > /etc/danted.conf <<DANTE_EOF
logoutput: syslog
internal: 127.0.0.1 port = 1080
external: ${EXT_IP}
socksmethod: none
clientmethod: none
client pass {
    from: 127.0.0.1/32 to: 0.0.0.0/0
    log: connect disconnect error
}
socks pass {
    from: 127.0.0.1/32 to: 0.0.0.0/0
    protocol: tcp udp
    log: connect disconnect error
}
DANTE_EOF
    systemctl restart danted
    systemctl enable danted >/dev/null 2>&1

    # Rust (si no está instalado)
    if ! command -v cargo >/dev/null 2>&1; then
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y >/dev/null 2>&1
        source "$HOME/.cargo/env"
    else
        source "$HOME/.cargo/env" 2>/dev/null || true
    fi

    # Clonar y compilar SlipStream
    if [ -d "/opt/slipstream-rust/.git" ]; then
        cd /opt/slipstream-rust
    else
        rm -rf /opt/slipstream-rust
        git clone --quiet https://github.com/Mygod/slipstream-rust.git /opt/slipstream-rust
        cd /opt/slipstream-rust
    fi
    git fetch --quiet origin
    git checkout --quiet bc772dd07d9a136dbd7553b0da575526de207847
    git submodule update --init --recursive --quiet
    cargo build --release -p slipstream-server --quiet 2>&1
    cd /root

    cat > /etc/systemd/system/slipstream.service <<SLIPSTREAM_EOF
[Unit]
Description=Slipstream DNS Tunnel Server
After=network.target danted.service
[Service]
Type=simple
ExecStart=/opt/slipstream-rust/target/release/slipstream-server \\
    --dns-listen-port 5300 \\
    --target-address 127.0.0.1:1080 \\
    --domain ${SlipstreamDomain} \\
    --cert /opt/slipstream-rust/cert.pem \\
    --key /opt/slipstream-rust/key.pem \\
    --reset-seed /opt/slipstream-rust/reset-seed
WorkingDirectory=/opt/slipstream-rust
Restart=always
RestartSec=5
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
SLIPSTREAM_EOF
    systemctl daemon-reload
    systemctl enable slipstream >/dev/null 2>&1
    systemctl restart slipstream

    # DNSDIST
    command -v dnsdist >/dev/null 2>&1 || apt-get install -y dnsdist
    mkdir -p /etc/dnsdist
    cat > /etc/dnsdist/dnsdist.conf <<DNSDIST_EOF
setLocal("0.0.0.0:53")
newServer({address="127.0.0.1:5301", name="slowdns"})
newServer({address="127.0.0.1:5300", name="slipstream"})
addAction(SuffixMatchNodeRule("${DOMAIN}."), PoolAction("slowdns_pool"))
setPoolServers("slowdns_pool", {getServer(0)})
addAction(SuffixMatchNodeRule("${SlipstreamDomain}."), PoolAction("slipstream_pool"))
setPoolServers("slipstream_pool", {getServer(1)})
addAction(AllRule(), DropAction())
DNSDIST_EOF
    systemctl daemon-reload
    systemctl enable dnsdist >/dev/null 2>&1
    systemctl restart dnsdist
fi


# ======================================================
#  NGINX (servidor web en puerto 85)
# ======================================================
rm -rf /home/vps/public_html /etc/nginx/sites-* /etc/nginx/nginx.conf
mkdir -p /home/vps/public_html
cat <<'myNginxC' > /etc/nginx/nginx.conf
user www-data;
worker_processes auto;
pid /var/run/nginx.pid;
events {
    multi_accept on;
    worker_connections 8192;
}
http {
    gzip on;
    gzip_vary on;
    gzip_comp_level 5;
    gzip_types text/plain application/x-javascript text/xml text/css;
    autoindex on;
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;
    client_max_body_size 32M;
    client_header_buffer_size 8m;
    large_client_header_buffers 8 8m;
    fastcgi_buffer_size 8m;
    fastcgi_buffers 8 8m;
    fastcgi_read_timeout 600;
    include /etc/nginx/conf.d/*.conf;
}
myNginxC

cat <<'myvpsC' > /etc/nginx/conf.d/vps.conf
server {
    listen Nginx_Port;
    server_name 127.0.0.1 localhost;
    root /home/vps/public_html;
    location / {
        try_files $uri $uri/ /index.php?$args;
    }
}
myvpsC
sed -i "s|Nginx_Port|$Nginx_Port|g" /etc/nginx/conf.d/vps.conf
systemctl restart "$NGINX_SERVICE"

# ======================================================
#  SQUID (proxy HTTP en puertos 3128 y 8000)
# ======================================================
rm -rf /etc/squid/squid.con*
cat <<'mySquid' > /etc/squid/squid.conf
acl server dst IP-ADDRESS/32 localhost
acl ports_ port 14 22 53 21 8081 25 8000 3128 443 80 8080 8880 2082 2086 36712
http_port Squid_Port1
http_port Squid_Port2
http_access allow server
http_access allow all
visible_hostname IP-ADDRESS
mySquid
sed -i "s|IP-ADDRESS|$IPADDR|g" /etc/squid/squid.conf
sed -i "s|Squid_Port1|$Squid_Port1|g" /etc/squid/squid.conf
sed -i "s|Squid_Port2|$Squid_Port2|g" /etc/squid/squid.conf
systemctl restart "$SQUID_SERVICE"

# ======================================================
#  HEALTH CHECK (sin Telegram, solo reinicio automático)
# ======================================================
mkdir -p /etc/deekayvpn/health
cat <<'ServiceChecker' > /etc/deekayvpn/service_checker.sh
#!/bin/bash
STATE_DIR="/etc/deekayvpn/health"
check_port() {
    ss -lnt | awk '{print $4}' | grep -q ":$1$"
}
mark_fail() {
    local f="$STATE_DIR/$1.fail"
    local n=0
    [ -f "$f" ] && n=$(cat "$f")
    n=$((n+1))
    echo "$n" > "$f"
    echo "$n"
}
clear_fail() {
    rm -f "$STATE_DIR/$1.fail"
}
restart_after_3_fails() {
    local fails=$(mark_fail "$1")
    if [ "$fails" -ge 3 ]; then
        systemctl restart "$2" >/dev/null 2>&1
        clear_fail "$1"
    fi
}
if check_port SSHPORT1 && check_port SSHPORT2 && systemctl is-active --quiet ssh; then
    clear_fail ssh
else
    restart_after_3_fails ssh ssh
fi
if check_port STUNNELPORT && systemctl is-active --quiet stunnel4; then
    clear_fail stunnel4
else
    restart_after_3_fails stunnel4 stunnel4
fi
if check_port SSLHPORT && systemctl is-active --quiet sslh; then
    clear_fail sslh
else
    restart_after_3_fails sslh sslh
fi
if check_port SQUIDPORT1 && check_port SQUIDPORT2 && systemctl is-active --quiet squid; then
    clear_fail squid
else
    restart_after_3_fails squid squid
fi
if check_port NGINXPORT && systemctl is-active --quiet nginx; then
    clear_fail nginx
else
    restart_after_3_fails nginx nginx
fi
for port in 10080 25 2082 2086; do
    if check_port $port && systemctl is-active --quiet ws-proxy@$port; then
        clear_fail ws-proxy-$port
    else
        restart_after_3_fails ws-proxy-$port ws-proxy@$port
    fi
done
if check_port 443 && systemctl is-active --quiet xray; then
    clear_fail xray
else
    restart_after_3_fails xray xray
fi
if systemctl is-active --quiet hysteria-server; then
    clear_fail hysteria-server
else
    restart_after_3_fails hysteria-server hysteria-server
fi
ServiceChecker

chmod 755 /etc/deekayvpn/service_checker.sh
sed -i "s|STUNNELPORT|$Stunnel_Port_Num|g" /etc/deekayvpn/service_checker.sh
sed -i "s|SSLHPORT|$MainPort|g" /etc/deekayvpn/service_checker.sh
sed -i "s|SQUIDPORT1|$Squid_Port1|g" /etc/deekayvpn/service_checker.sh
sed -i "s|SQUIDPORT2|$Squid_Port2|g" /etc/deekayvpn/service_checker.sh
sed -i "s|NGINXPORT|$Nginx_Port|g" /etc/deekayvpn/service_checker.sh
sed -i "s|SSHPORT1|$SSH_Port1|g" /etc/deekayvpn/service_checker.sh
sed -i "s|SSHPORT2|$SSH_Port2|g" /etc/deekayvpn/service_checker.sh

echo "*/3 * * * * root /bin/bash /etc/deekayvpn/service_checker.sh >/dev/null 2>&1" > /etc/cron.d/service-checker

# ======================================================
#  SSH LIMIT CHECKER (límite de conexiones por usuario)
# ======================================================
mkdir -p /etc/deekayvpn
touch /etc/deekayvpn/ssh_limits.txt
cat <<'SSHLimitChecker' > /etc/deekayvpn/ssh_limit_checker.sh
#!/bin/bash
DB="/etc/deekayvpn/ssh_limits.txt"
[ -s "$DB" ] || exit 0
while read -r suser slimit; do
    [ -z "$suser" ] && continue
    [[ "$slimit" =~ ^[0-9]+$ ]] || continue
    [ "$slimit" -le 0 ] && continue
    id "$suser" >/dev/null 2>&1 || continue
    mapfile -t sessions < <(ps -u "$suser" -o pid=,etimes=,cmd= 2>/dev/null | awk '$0 ~ /sshd/ {print $1" "$2}')
    count=${#sessions[@]}
    [ "$count" -le "$slimit" ] && continue
    excess=$((count - slimit))
    mapfile -t sorted < <(printf '%s\n' "${sessions[@]}" | sort -k2,2n)
    for ((i=0; i<excess; i++)); do
        pid=$(awk '{print $1}' <<< "${sorted[$i]}")
        [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null
    done
done < "$DB"
SSHLimitChecker
chmod 755 /etc/deekayvpn/ssh_limit_checker.sh
echo "* * * * * root /bin/bash /etc/deekayvpn/ssh_limit_checker.sh >/dev/null 2>&1" > /etc/cron.d/ssh-limit-checker

# ======================================================
#  LOGROTATE (configuración estándar, sin forzar cada 5 min)
# ======================================================
rm -f /etc/logrotate.d/rsyslog
cat <<'logrotate' > /etc/logrotate.d/rsyslog
/var/log/syslog /var/log/kern.log /var/log/auth.log /var/log/xray/access.log /var/log/xray/error.log {
    rotate 7
    daily
    missingok
    notifempty
    compress
    delaycompress
    sharedscripts
    postrotate
        /usr/lib/rsyslog/rsyslog-rotate
    endscript
}
logrotate
chown root:root /var/log
chmod 755 /var/log
chown syslog:adm /var/log/syslog
chmod 640 /var/log/syslog

# ======================================================
#  AJUSTES DEL SISTEMA (sysctl, límites de archivos, etc.)
# ======================================================
modprobe nf_conntrack 2>/dev/null || true
echo "nf_conntrack" > /etc/modules-load.d/freenet.conf

cat <<'SYSCTL' > /etc/sysctl.d/99-freenet-tuning.conf
fs.file-max = 1048576
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 16384
net.ipv4.ip_local_port_range = 1024 65000
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 10
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_mtu_probing = 1
net.netfilter.nf_conntrack_max = 2097152
net.netfilter.nf_conntrack_tcp_timeout_established = 1200
net.netfilter.nf_conntrack_udp_timeout = 60
SYSCTL
sysctl --system || true

mkdir -p /etc/security/limits.d
cat <<'LIMITS' > /etc/security/limits.d/99-freenet.conf
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
LIMITS

# ======================================================
#  SLOWDNS (con claves Ed25519 generadas)
# ======================================================
rm -rf /etc/slowdns
mkdir -m 777 /etc/slowdns
# Las claves ya están generadas en la Parte 1, pero las reescribimos por si acaso
cat > /etc/slowdns/server.key << END
$Serverkey
END
cat > /etc/slowdns/server.pub << END
$Serverpub
END

# Descargar binario de SlowDNS (verificación opcional, pero mantenemos el original)
wget -q -O /etc/slowdns/sldns-server "https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/sldns-server"
chmod +x /etc/slowdns/sldns-server /etc/slowdns/server.key /etc/slowdns/server.pub

# Abrir puerto 53 en firewall
iptables -C INPUT -p udp --dport 53 -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport 53 -j ACCEPT

# Si SlipStream se instala, SlowDNS escuchará en 127.0.0.1:5301, sino en :53
if [ "$InstallSlipstream" = "y" ]; then
    SlowDNS_Listen="127.0.0.1:5301"
else
    SlowDNS_Listen=":53"
fi

cat > /etc/systemd/system/server-sldns.service << END
[Unit]
Description=Server SlowDNS
After=network.target
[Service]
ExecStart=/etc/slowdns/sldns-server -udp $SlowDNS_Listen -privkey-file /etc/slowdns/server.key $DOMAIN 127.0.0.1:$SSH_Port2
Restart=on-failure
[Install]
WantedBy=multi-user.target
END
systemctl daemon-reload
systemctl enable server-sldns
systemctl restart server-sldns

# ======================================================
#  SLIPSTREAM (opcional) + DANTE SOCKS + DNSDIST
# ======================================================
if [ "$InstallSlipstream" = "y" ]; then
    # --- Dante SOCKS (backend para SlipStream) ---
    command -v danted >/dev/null 2>&1 || apt-get install -y dante-server
    EXT_IP="$(ip -4 addr show scope global 2>/dev/null | awk '/inet/{print $2}' | cut -d/ -f1 | head -1)"
    [ -z "$EXT_IP" ] && EXT_IP="$(curl -s --max-time 5 ifconfig.me 2>/dev/null)"
    cat > /etc/danted.conf <<DANTE_EOF
logoutput: syslog
internal: 127.0.0.1 port = 1080
external: ${EXT_IP}
socksmethod: none
clientmethod: none
client pass {
    from: 127.0.0.1/32 to: 0.0.0.0/0
    log: connect disconnect error
}
socks pass {
    from: 127.0.0.1/32 to: 0.0.0.0/0
    protocol: tcp udp
    log: connect disconnect error
}
DANTE_EOF
    systemctl restart danted
    systemctl enable danted >/dev/null 2>&1

    # --- Rust (para compilar SlipStream) ---
    if ! command -v cargo &>/dev/null; then
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y >/dev/null 2>&1
        source "$HOME/.cargo/env"
    else
        source "$HOME/.cargo/env" 2>/dev/null || true
    fi

    # --- Clonar y compilar SlipStream (commit fijado) ---
    if [ -d "/opt/slipstream-rust/.git" ]; then
        cd /opt/slipstream-rust
    else
        rm -rf /opt/slipstream-rust
        git clone --quiet https://github.com/Mygod/slipstream-rust.git /opt/slipstream-rust
        cd /opt/slipstream-rust
    fi
    git fetch --quiet origin
    git checkout --quiet bc772dd07d9a136dbd7553b0da575526de207847
    git submodule update --init --recursive --quiet
    cargo build --release -p slipstream-server --quiet 2>&1
    cd /root

    # --- Servicio systemd para SlipStream ---
    cat > /etc/systemd/system/slipstream.service <<SLIPSTREAM_EOF
[Unit]
Description=Slipstream DNS Tunnel Server
After=network.target danted.service
[Service]
Type=simple
ExecStart=/opt/slipstream-rust/target/release/slipstream-server \\
    --dns-listen-port 5300 \\
    --target-address 127.0.0.1:1080 \\
    --domain ${SlipstreamDomain} \\
    --cert /opt/slipstream-rust/cert.pem \\
    --key /opt/slipstream-rust/key.pem \\
    --reset-seed /opt/slipstream-rust/reset-seed
WorkingDirectory=/opt/slipstream-rust
Restart=always
RestartSec=5
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
SLIPSTREAM_EOF
    systemctl daemon-reload
    systemctl enable slipstream >/dev/null 2>&1
    systemctl restart slipstream

    # --- dnsdist (multiplexor DNS en puerto 53) ---
    command -v dnsdist >/dev/null 2>&1 || apt-get install -y dnsdist
    mkdir -p /etc/dnsdist
    cat > /etc/dnsdist/dnsdist.conf <<DNSDIST_EOF
setLocal("0.0.0.0:53")
newServer({address="127.0.0.1:5301", name="slowdns"})
newServer({address="127.0.0.1:5300", name="slipstream"})
addAction(SuffixMatchNodeRule("${DOMAIN}."), PoolAction("slowdns_pool"))
setPoolServers("slowdns_pool", {getServer(0)})
addAction(SuffixMatchNodeRule("${SlipstreamDomain}."), PoolAction("slipstream_pool"))
setPoolServers("slipstream_pool", {getServer(1)})
addAction(AllRule(), DropAction())
DNSDIST_EOF
    systemctl daemon-reload
    systemctl enable dnsdist >/dev/null 2>&1
    systemctl restart dnsdist
fi

# ======================================================
#  HYSTERIA v1 (Sing-box v1.12.22) con Cloudflare WARP
# ======================================================
# Instalar Cloudflare WARP
curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-client.list
apt-get update && apt-get install -y cloudflare-warp

# Configurar WARP en modo proxy
warp-cli --accept-tos disconnect 2>/dev/null || true
warp-cli --accept-tos registration delete 2>/dev/null || true
warp-cli --accept-tos registration new 2>/dev/null || warp-cli --accept-tos register
warp-cli --accept-tos mode proxy
warp-cli --accept-tos proxy port 40000
warp-cli --accept-tos connect
sleep 2

# Instalar Sing-box (Hysteria v1)
wget -qO /tmp/sing-box.deb "https://github.com/SagerNet/sing-box/releases/download/v1.12.22/sing-box_1.12.22_linux_amd64.deb"
dpkg -i /tmp/sing-box.deb
apt-mark hold sing-box
rm -f /tmp/sing-box.deb

mkdir -p /etc/hysteria
HYST_PORT="${UDP_PORT##*:}"

# Usar el mismo certificado de Xray para Hysteria
cp /etc/xray/xray.crt /etc/hysteria/hysteria.crt
cp /etc/xray/xray.key /etc/hysteria/hysteria.key

cat > /etc/hysteria/config.json <<EOF
{
  "log": { "level": "fatal" },
  "inbounds": [
    {
      "type": "hysteria",
      "tag": "hy1-inbound",
      "listen": "::",
      "listen_port": $HYST_PORT,
      "up_mbps": 100,
      "down_mbps": 100,
      "obfs": "$OBFS",
      "users": [ { "auth_str": "$PASSWORD" } ],
      "tls": {
        "enabled": true,
        "certificate_path": "/etc/hysteria/hysteria.crt",
        "key_path": "/etc/hysteria/hysteria.key"
      }
    }
  ],
  "outbounds": [
    { "type": "socks", "tag": "warp-proxy", "server": "127.0.0.1", "server_port": 40000 },
    { "type": "direct", "tag": "direct" },
    { "type": "block", "tag": "block" }
  ],
  "route": {
    "rules": [
      {
        "inbound": "hy1-inbound",
        "network": "udp",
        "domain_suffix": [
          "doubleclick.net", "googlesyndication.com", "googleadservices.com",
          "admob.com", "google-analytics.com", "app-measurement.com",
          "adservice.google.com", "g.doubleclick.net", "google.com",
          "pagead2.googlesyndication.com", "tpc.googlesyndication.com",
          "googlevideo.com", "gvt1.com", "gvt2.com", "gvt3.com",
          "ytimg.com", "youtube.com", "gstatic.com", "googleusercontent.com",
          "ggpht.com", "play.google.com", "firebaseio.com", "firebase.googleapis.com",
          "crashlytics.com", "fundingchoicesmessages.google.com",
          "imasdk.googleapis.com", "googleanalytics.com", "analytics.google.com",
          "fcm.googleapis.com", "mtalk.google.com",
          "firebaseinstallations.googleapis.com", "firebaselogging.googleapis.com",
          "firebaselogging-pa.googleapis.com", "firebaseremoteconfig.googleapis.com",
          "googleadapis.com", "accounts.google.com", "play.googleapis.com",
          "android.apis.google.com", "adsense.com", "1e100.net"
        ],
        "outbound": "block"
      },
      {
        "inbound": "hy1-inbound",
        "domain_suffix": [
          "doubleclick.net", "googlesyndication.com", "googleadservices.com",
          "admob.com", "google-analytics.com", "app-measurement.com",
          "adservice.google.com", "g.doubleclick.net", "google.com",
          "pagead2.googlesyndication.com", "tpc.googlesyndication.com",
          "googlevideo.com", "gvt1.com", "gvt2.com", "gvt3.com",
          "ytimg.com", "youtube.com", "gstatic.com", "googleusercontent.com",
          "ggpht.com", "play.google.com", "firebaseio.com", "firebase.googleapis.com",
          "crashlytics.com", "fundingchoicesmessages.google.com",
          "imasdk.googleapis.com", "googleanalytics.com", "analytics.google.com",
          "fcm.googleapis.com", "mtalk.google.com",
          "firebaseinstallations.googleapis.com", "firebaselogging.googleapis.com",
          "firebaselogging-pa.googleapis.com", "firebaseremoteconfig.googleapis.com",
          "googleadapis.com", "accounts.google.com", "play.googleapis.com",
          "android.apis.google.com", "adsense.com", "1e100.net"
        ],
        "outbound": "warp-proxy"
      },
      { "inbound": "hy1-inbound", "outbound": "direct" }
    ],
    "auto_detect_interface": true
  }
}
EOF

chmod 600 /etc/hysteria/config.json
chmod 644 /etc/hysteria/hysteria.crt
chmod 600 /etc/hysteria/hysteria.key
echo "$PASSWORD $(date -d "+365 days" +"%Y-%m-%d")" > /etc/hysteria/users.txt
chmod 600 /etc/hysteria/users.txt

cat > /etc/systemd/system/hysteria-server.service <<EOF
[Unit]
Description=Sing-Box Hysteria v1 Core
After=network.target
[Service]
User=root
ExecStart=/usr/bin/sing-box run -c /etc/hysteria/config.json
Restart=on-failure
RestartSec=5
LimitNOFILE=1048576
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable hysteria-server.service
systemctl start hysteria-server.service

# Reglas NAT para Hysteria (redirigir puertos 20000-50000 al puerto 36712)
IFACE="$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)"
cat > /etc/systemd/system/hysteria-nat.service <<EOF
[Unit]
Description=Restore Hysteria UDP NAT rules
After=network-online.target
Wants=network-online.target
Before=hysteria-server.service
[Service]
Type=oneshot
ExecStart=/bin/bash -c 'IFACE=\$(ip -4 route ls|grep default|grep -Po "(?<=dev )(\\\\S+)"|head -1); [ -n "\$IFACE" ] && (iptables -t nat -C PREROUTING -i "\$IFACE" -p udp --dport 20000:50000 -j DNAT --to-destination :$HYST_PORT 2>/dev/null || iptables -t nat -A PREROUTING -i "\$IFACE" -p udp --dport 20000:50000 -j DNAT --to-destination :$HYST_PORT)'
ExecStart=/bin/bash -c 'iptables -C INPUT -p udp --dport $HYST_PORT -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport $HYST_PORT -j ACCEPT'
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable hysteria-nat.service
systemctl start hysteria-nat.service

# ======================================================
#  HYSTERIA 2 (oficial, con verificación SHA256)
# ======================================================
HYSTERIA2_VER="app/v2.9.3"
case "$(uname -m)" in
  x86_64|amd64) HYSTERIA2_ASSET="hysteria-linux-amd64" ;;
  i386|i486|i586|i686) HYSTERIA2_ASSET="hysteria-linux-386" ;;
  aarch64|arm64) HYSTERIA2_ASSET="hysteria-linux-arm64" ;;
  armv7l|armv7*) HYSTERIA2_ASSET="hysteria-linux-arm" ;;
  *) echo "Unsupported Hysteria 2 architecture: $(uname -m)"; exit 1 ;;
esac

HYSTERIA2_RELEASE_URL="https://github.com/apernet/hysteria/releases/download/${HYSTERIA2_VER}"
hyst2_tmp=$(mktemp -d /tmp/hysteria2-install.XXXXXX) || exit 1
if ! curl -fL --retry 3 -o "$hyst2_tmp/$HYSTERIA2_ASSET" "$HYSTERIA2_RELEASE_URL/$HYSTERIA2_ASSET" ||
   ! curl -fL --retry 3 -o "$hyst2_tmp/hashes.txt" "$HYSTERIA2_RELEASE_URL/hashes.txt"; then
  rm -rf "$hyst2_tmp"
  echo "Hysteria 2 download failed."
  exit 1
fi

hyst2_expected=$(awk -v asset="$HYSTERIA2_ASSET" '$2 == asset || $2 == "build/" asset || $2 == "*" asset {print tolower($1); exit}' "$hyst2_tmp/hashes.txt")
hyst2_actual=$(sha256sum "$hyst2_tmp/$HYSTERIA2_ASSET" | awk '{print tolower($1)}')
if [ -z "$hyst2_expected" ] || [ "$hyst2_actual" != "$hyst2_expected" ]; then
  rm -rf "$hyst2_tmp"
  echo "Hysteria 2 SHA-256 verification failed."
  exit 1
fi
install -m 755 "$hyst2_tmp/$HYSTERIA2_ASSET" /usr/local/bin/hysteria2
rm -rf "$hyst2_tmp"

mkdir -p /etc/hysteria2
mkdir -p /usr/local/libexec

# Script de autenticación para Hysteria 2
cat <<'EOF_HYST2_AUTH' > /usr/local/libexec/hysteria2-auth
#!/bin/bash
user_db="/etc/hysteria2/users.txt"
auth="$2"
[ -n "$auth" ] && [ -r "$user_db" ] || exit 1
awk -v token="$auth" '$2 == token {print $1; found=1; exit} END {exit !found}' "$user_db"
EOF_HYST2_AUTH
chmod 700 /usr/local/libexec/hysteria2-auth

HYST2_INITIAL_TOKEN=$(cat /proc/sys/kernel/random/uuid)
jq -n \
  --arg listen ":$HYST2_PORT" \
  --arg cert "/etc/xray/xray.crt" \
  --arg key "/etc/xray/xray.key" \
  --arg obfs "$OBFS" '
{
  listen: $listen,
  tls: {cert: $cert, key: $key},
  auth: {type: "command", command: "/usr/local/libexec/hysteria2-auth"},
  obfs: {type: "salamander", salamander: {password: $obfs}},
  masquerade: {
    type: "proxy",
    proxy: {url: "https://www.microsoft.com/", rewriteHost: true}
  }
}
' > /etc/hysteria2/config.json
chmod 600 /etc/hysteria2/config.json
printf 'default %s %s\n' "$HYST2_INITIAL_TOKEN" "$(date -d '+365 days' +%Y-%m-%d)" > /etc/hysteria2/users.txt
chmod 600 /etc/hysteria2/users.txt

cat <<'EOF_HYST2_SERVICE' > /etc/systemd/system/hysteria2-server.service
[Unit]
Description=Official Hysteria 2 Server
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/hysteria2 server --config /etc/hysteria2/config.json
Restart=on-failure
RestartSec=2s
LimitNOFILE=1048576
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=full
ReadOnlyPaths=/etc/xray/xray.crt /etc/xray/xray.key
ReadWritePaths=/etc/hysteria2
[Install]
WantedBy=multi-user.target
EOF_HYST2_SERVICE

iptables -C INPUT -p udp --dport "$HYST2_PORT" -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport "$HYST2_PORT" -j ACCEPT
netfilter-persistent save >/dev/null 2>&1 || true
systemctl daemon-reload
systemctl enable hysteria2-server.service
systemctl restart hysteria2-server.service

# ======================================================
#  BADVPN (UDP Gateway en 127.0.0.1:7300)
# ======================================================
if [ "$(getconf LONG_BIT)" == "64" ]; then
    wget -q -O /usr/bin/badvpn-udpgw "https://www.dropbox.com/s/jo6qznzwbsf1xhi/badvpn-udpgw64"
else
    wget -q -O /usr/bin/badvpn-udpgw "https://www.dropbox.com/s/8gemt9c6k1fph26/badvpn-udpgw"
fi
chmod +x /usr/bin/badvpn-udpgw

cat <<'deekayb' > /etc/systemd/system/badvpn.service
[Unit]
Description=badvpn tun2socks service
After=network.target
[Service]
Type=simple
ExecStart=/usr/bin/badvpn-udpgw --loglevel none --listen-addr 127.0.0.1:7300 --max-clients 1000 --max-connections-for-client 10
[Install]
WantedBy=multi-user.target
deekayb
systemctl enable badvpn
systemctl start badvpn

# ======================================================
#  UDP CUSTOM (puerto 36717)
# ======================================================
echo "Instalando UDP Custom..."
mkdir -p /root/udp
wget -q -O /root/udp/udp-custom "https://raw.githubusercontent.com/mahpud896/UDP-Custom/main/bin/udp-custom-linux-amd64" || true
chmod +x /root/udp/udp-custom 2>/dev/null || true
wget -q -O /root/udp/config.json "https://raw.githubusercontent.com/mahpud896/UDP-Custom/main/config/config.json" || true
sed -i "s/\":36712\"/\":36717\"/g" /root/udp/config.json 2>/dev/null || true
chmod 644 /root/udp/config.json 2>/dev/null || true

cat > /etc/systemd/system/udp-custom.service <<EOF
[Unit]
Description=UDP Custom Proxy
After=network.target
[Service]
Type=simple
User=root
WorkingDirectory=/root/udp
ExecStart=/root/udp/udp-custom server -c /root/udp/config.json
Restart=always
RestartSec=2s
LimitNOFILE=1048576
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable udp-custom
systemctl start udp-custom 2>/dev/null || true

# ======================================================
#  ZIVPN (puerto 5667)
# ======================================================
echo "Instalando ZiVPN..."
mkdir -p /etc/zivpn
wget -q -O /usr/local/bin/zivpn "https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64" || true
chmod +x /usr/local/bin/zivpn 2>/dev/null || true
cp /etc/xray/xray.crt /etc/zivpn/zivpn.crt 2>/dev/null || true
cp /etc/xray/xray.key /etc/zivpn/zivpn.key 2>/dev/null || true
chmod 644 /etc/zivpn/zivpn.crt /etc/zivpn/zivpn.key 2>/dev/null || true

cat > /etc/zivpn/config.json <<EOF
{
  "listen": ":5667",
  "cert": "/etc/zivpn/zivpn.crt",
  "key": "/etc/zivpn/zivpn.key",
  "obfs": "$OBFS",
  "auth": {
    "mode": "passwords",
    "config": ["$PASSWORD"]
  }
}
EOF
chmod 600 /etc/zivpn/config.json
echo "$PASSWORD $(date -d "+365 days" +"%Y-%m-%d")" > /etc/zivpn/users.txt
chmod 600 /etc/zivpn/users.txt

cat > /etc/systemd/system/zivpn.service <<EOF
[Unit]
Description=zivpn VPN Server
After=network.target
[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/local/bin/zivpn server -c /etc/zivpn/config.json
Restart=always
RestartSec=3
Environment=ZIVPN_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true
LimitNOFILE=1048576
[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/zivpn-nat.service <<EOF
[Unit]
Description=Restore ZiVPN UDP NAT rules
After=network-online.target
Wants=network-online.target
Before=zivpn.service
[Service]
Type=oneshot
ExecStart=/bin/bash -c 'IFACE=\$(ip -4 route ls|grep default|grep -Po "(?<=dev )(\\\\S+)"|head -1); [ -n "\$IFACE" ] && (iptables -t nat -C PREROUTING -i "\$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null || iptables -t nat -A PREROUTING -i "\$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667)'
ExecStart=/bin/bash -c 'iptables -C INPUT -p udp --dport 5667 -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport 5667 -j ACCEPT'
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable zivpn.service
systemctl start zivpn.service 2>/dev/null || true
systemctl enable zivpn-nat.service
systemctl start zivpn-nat.service 2>/dev/null || true

# ======================================================
#  VNSTAT (monitor de tráfico)
# ======================================================
IFACE="$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)"
vnstat -u -i "$IFACE" 2>/dev/null || true
systemctl enable vnstat
systemctl restart vnstat

# ======================================================
#  STARTUP SCRIPT (se ejecuta al arrancar el sistema)
# ======================================================
cat <<'deekayz' > /etc/deekaystartup
#!/bin/sh
ln -fs /usr/share/zoneinfo/MyTimeZone /etc/localtime
export DEBIAN_FRONTEND=noninteractive
echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6
echo "nameserver DNS1" > /etc/resolv.conf
echo "nameserver DNS2" >> /etc/resolv.conf
mkdir -p /var/run/sslh
touch /var/run/sslh/sslh.pid
chmod 777 /var/run/sslh/sslh.pid
iptables -C INPUT -p udp --dport 53 -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport 53 -j ACCEPT
iptables -t nat -C PREROUTING -p udp --dport 36713 -j ACCEPT 2>/dev/null || iptables -t nat -I PREROUTING 1 -p udp --dport 36713 -j ACCEPT
iptables -C INPUT -p udp --dport 36713 -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport 36713 -j ACCEPT
IFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
iptables -t nat -C PREROUTING -i "$IFACE" -p udp --dport 20000:50000 -j DNAT --to-destination :36712 2>/dev/null || iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 20000:50000 -j DNAT --to-destination :36712
deekayz

sed -i "s|MyTimeZone|$MyVPS_Time|g" /etc/deekaystartup
sed -i "s|DNS1|$Dns_1|g" /etc/deekaystartup
sed -i "s|DNS2|$Dns_2|g" /etc/deekaystartup

cat <<'deekayx' > /etc/systemd/system/deekaystartup.service
[Unit]
Description=Custom startup script
ConditionPathExists=/etc/deekaystartup
[Service]
Type=oneshot
ExecStart=/etc/deekaystartup
RemainAfterExit=true
[Install]
WantedBy=multi-user.target
deekayx
chmod +x /etc/deekaystartup
systemctl enable deekaystartup

# ======================================================
#  MENÚ PRINCIPAL (CLI) - COMPLETO Y FUNCIONAL
#  (Adaptado del original, con marca nokasvip y sin Telegram)
# ======================================================

cat > /usr/local/bin/menu <<'EOF_MENU'
#!/bin/bash

# ======================================================
#  MENÚ PRINCIPAL - nokasvip | kyz | http door | socketdevz
#  Basado en el original de Hex Applications, adaptado y corregido
# ======================================================

# --- Detectar si el certificado es real o autofirmado ---
if [ -f /etc/xray/cert_type ] && grep -q "letsencrypt" /etc/xray/cert_type; then
    XRAY_INSECURE="0"
else
    XRAY_INSECURE="1"
fi
if [ "$XRAY_INSECURE" = "1" ]; then
    INSECURE_PARAM="&allowInsecure=1"
else
    INSECURE_PARAM=""
fi

# --- Colores y estilos ---
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
MAGENTA='\033[1;35m'
WHITE='\033[1;37m'
NC='\033[0m'
BOLD='\033[1m'

DOMAIN=$(cat /etc/deekayvpn/domain.txt 2>/dev/null || curl -4 -s --max-time 2 ipv4.icanhazip.com)
SLIPSTREAM_DOMAIN=$(cat /etc/deekayvpn/slipstream_domain.txt 2>/dev/null || echo "No configurado")

# Rutas de bases de datos
HYST_CONFIG="/etc/hysteria/config.json"
HYST_USER_DB="/etc/hysteria/users.txt"
HYST2_CONFIG="/etc/hysteria2/config.json"
HYST2_USER_DB="/etc/hysteria2/users.txt"
HYST2_PORT="${HYST2_PORT:-36713}"
ZIVPN_CONFIG="/etc/zivpn/config.json"
ZIVPN_USER_DB="/etc/zivpn/users.txt"
SSH_LIMIT_DB="/etc/deekayvpn/ssh_limits.txt"
mkdir -p /etc/deekayvpn 2>/dev/null || true
touch "$SSH_LIMIT_DB" 2>/dev/null || true

# --- Funciones auxiliares ---
server_ip() {
    curl -4 -s --max-time 2 ipv4.icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}'
}
cpu_count() {
    nproc 2>/dev/null || echo "1"
}
ram_percent() {
    free 2>/dev/null | awk '/Mem:/ { if ($2>0) printf "%.1f%%", ($3/$2)*100; else print "0.0%" }'
}
cpu_percent() {
    top -bn1 2>/dev/null | awk -F',' '/Cpu\(s\)/ { gsub("%us","",$1); gsub(" ","",$1); split($1,a,":"); if (a[2] == "") print "0.0%"; else printf "%.1f%%", a[2]+0 }'
}
buffer_mem() {
    free -m 2>/dev/null | awk '/Mem:/ {print $6 "M"}'
}

server_status() {
    local ok=0
    for s in ssh stunnel4 squid nginx server-sldns hysteria-server hysteria2-server ws-proxy@10080 xray slipstream danted dnsdist; do
        systemctl is-active --quiet "$s" 2>/dev/null && ok=$((ok+1))
    done
    [ "$ok" -ge 4 ] && echo -e "${GREEN}EN LÍNEA${NC}" || echo -e "${RED}PROBLEMAS DETECTADOS${NC}"
}

pause_return() {
    echo
    read -rp "Presiona ENTER para volver... " _
}

# ======================================================
#  FUNCIONES DE GESTIÓN DE USUARIOS SSH (Legado)
# ======================================================
list_real_users() {
    awk -F: '$3 >= 1000 && $1 != "nobody" && $1 != "systemd-network" && $1 != "messagebus" {print $1}' /etc/passwd 2>/dev/null
}

select_user() {
    local purpose="$1"
    mapfile -t USERS < <(list_real_users)
    if [ "${#USERS[@]}" -eq 0 ]; then
        echo -e "${RED}No se encontraron cuentas de usuario activas.${NC}"
        return 1
    fi
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    printf " %-56s \n" "${BOLD}$purpose${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    for i in "${!USERS[@]}"; do
        printf "  [${YELLOW}%02d${NC}] %s\n" $((i+1)) "${USERS[$i]}"
    done
    echo -e "\n  [${YELLOW}00${NC}] Atrás\n"
    read -rp "  Selecciona un número de cuenta: " idx
    [[ "$idx" == "00" || "$idx" == "0" ]] && return 1
    if ! [[ "$idx" =~ ^[0-9]+$ ]] || [ "$idx" -lt 1 ] || [ "$idx" -gt "${#USERS[@]}" ]; then
        echo -e "${RED}  Selección inválida.${NC}"
        return 1
    fi
    SELECTED_USER="${USERS[$((idx-1))]}"
    return 0
}

create_user() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                   ${BOLD}CREAR NUEVO USUARIO SSH${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "  ${YELLOW}(Escribe 00 en cualquier campo para cancelar y volver)${NC}\n"

    while true; do
        read -rp "  Nombre de usuario: " user
        user="$(echo -n "$user" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        [ "$user" = "00" ] && return
        if [ -z "$user" ]; then
            echo -e "${RED}  Error: El usuario no puede estar vacío.${NC}\n"
            continue
        fi
        if ! [[ "$user" =~ ^[a-zA-Z_][a-zA-Z0-9_-]{0,31}$ ]]; then
            echo -e "${RED}  Error: Nombre inválido (letras/números/guiones, sin espacios).${NC}\n"
            continue
        fi
        if id "$user" >/dev/null 2>&1; then
            echo -e "${RED}  Error: El usuario '$user' ya existe.${NC}\n"
            continue
        fi
        break
    done

    while true; do
        read -rp "  Contraseña: " pass
        pass="$(echo -n "$pass" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        [ "$pass" = "00" ] && return
        if [ -z "$pass" ]; then
            echo -e "${RED}  Error: La contraseña no puede estar vacía.${NC}\n"
            continue
        fi
        if [[ "$pass" =~ [[:space:]] ]]; then
            echo -e "${RED}  Error: La contraseña no puede contener espacios.${NC}\n"
            continue
        fi
        break
    done

    while true; do
        read -rp "  Válido por (días): " days
        days="$(echo -n "$days" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        [ "$days" = "00" ] && return
        if ! [[ "$days" =~ ^[0-9]+$ ]] || [ "$days" -eq 0 ]; then
            echo -e "${RED}  Error: Debe ser un número de días mayor a 0.${NC}\n"
            continue
        fi
        break
    done

    while true; do
        read -rp "  Límite de conexiones simultáneas (0 = sin límite): " conn_limit
        conn_limit="$(echo -n "$conn_limit" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        [ "$conn_limit" = "00" ] && return
        [ -z "$conn_limit" ] && conn_limit=0
        if ! [[ "$conn_limit" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}  Error: Debe ser un número.${NC}\n"
            continue
        fi
        break
    done

    useradd --badname -e "$(date -d "+$days days" +%Y-%m-%d)" -s /bin/false -M "$user" 2>/dev/null
    if [ $? -ne 0 ]; then
        echo -e "\n${RED}  Error: No se pudo crear el usuario '$user'.${NC}"
        pause_return
        return
    fi
    echo "$user:$pass" | chpasswd 2>/dev/null
    if [ $? -ne 0 ]; then
        echo -e "\n${RED}  Error: No se pudo establecer la contraseña. Eliminando cuenta...${NC}"
        userdel -f "$user" 2>/dev/null
        pause_return
        return
    fi

    sed -i "/^$user /d" "$SSH_LIMIT_DB" 2>/dev/null
    if [ "$conn_limit" -gt 0 ]; then
        echo "$user $conn_limit" >> "$SSH_LIMIT_DB"
    fi

    IP=$(curl -s ipv4.icanhazip.com)
    CURRENT_NS=$(grep 'ExecStart=' /etc/systemd/system/server-sldns.service 2>/dev/null | sed 's/.*server\.key \([^ ]*\) .*/\1/')

    clear
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                   ${BOLD}CUENTA CREADA EXITOSAMENTE${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "  ${BOLD}Dominio/Host${NC}: ${YELLOW}$DOMAIN${NC}"
    echo -e "  ${BOLD}Dirección IP${NC} : ${YELLOW}$IP${NC}"
    echo -e "  ${BOLD}Usuario${NC}   : ${YELLOW}$user${NC}"
    echo -e "  ${BOLD}Contraseña${NC}   : ${YELLOW}$pass${NC}"
    echo -e "  ${BOLD}Expiración${NC}     : ${YELLOW}$(date -d "+$days days" +%Y-%m-%d)${NC}"
    echo -e "  ${BOLD}Límite Conexiones${NC}: ${YELLOW}$([ "$conn_limit" -gt 0 ] && echo "$conn_limit" || echo "Sin límite")${NC}"
    echo -e "${CYAN}--------------------------------------------------------------${NC}"
    echo -e "  SSH Port   : 22, 299"
    echo -e "  SSL/TLS    : 443"
    echo -e "  SSL/WS     : 443"
    echo -e "  WebSocket  : 80, 8080, 8880, 2082, 2086, 25"
    echo -e "  SlowDNS/SlipStream (dnsdist): 53"
    echo -e "  BadVPN     : 7300"
    echo -e "  UDP Custom : 1-65535"
    echo -e "${CYAN}--------------------------------------------------------------${NC}"
    echo -e "  ${BOLD}Payload HTTP     :${NC}"
    echo -e "  ${YELLOW}GET / HTTP/1.1[crlf]Host: ${DOMAIN}[crlf]Connection: upgrade[crlf]Upgrade: websocket[crlf][crlf]${NC}"
    echo -e ""
    echo -e "  ${BOLD}Payload Mejorado :${NC}"
    echo -e "  ${YELLOW}GET / HTTP/1.1[crlf]Host: bug.com[crlf][crlf]PATCH / HTTP/1.1[crlf]Host: ${DOMAIN}[crlf]Connection: upgrade[crlf]Upgrade: websocket[crlf][crlf]${NC}"
    echo -e "${CYAN}--------------------------------------------------------------${NC}"
    echo -e "  ${BOLD}SlowDNS NS ${NC}: ${YELLOW}${CURRENT_NS:-No configurado}${NC}"
    echo -e "  ${BOLD}SlipStream ${NC}: ${YELLOW}${SLIPSTREAM_DOMAIN}${NC}"
    echo -e "  ${BOLD}DNS PUB KEY${NC}: $(cat /etc/slowdns/server.pub 2>/dev/null | grep -v "BEGIN" | grep -v "END" | tr -d '\n' | head -c 64)"
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
    pause_return
}

delete_user() {
    if ! select_user "DELETE SSH USER"; then
        pause_return
        return
    fi
    clear
    echo -e "${RED}Advertencia: Estás a punto de eliminar al usuario: ${YELLOW}$SELECTED_USER${NC}"
    read -rp "¿Estás seguro? [y/N]: " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        pkill -u "$SELECTED_USER" 2>/dev/null
        if userdel -r -f "$SELECTED_USER" 2>/dev/null || userdel -f "$SELECTED_USER" 2>/dev/null; then
            sed -i "/^$SELECTED_USER /d" "$SSH_LIMIT_DB" 2>/dev/null
            echo -e "${GREEN}El usuario $SELECTED_USER ha sido eliminado.${NC}"
        else
            echo -e "${RED}Fallo al eliminar $SELECTED_USER.${NC}"
        fi
    fi
    pause_return
}

extend_user() {
    if ! select_user "EXTEND USER EXPIRY"; then
        pause_return
        return
    fi
    clear
    echo -e "Extendiendo cuenta de: ${YELLOW}$SELECTED_USER${NC}"
    read -rp "Ingresa número de días a agregar: " days
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Formato de número inválido.${NC}"
        pause_return
        return
    fi
    current=$(chage -l "$SELECTED_USER" 2>/dev/null | awk -F": " '/Account expires/ {print $2}')
    if [ "$current" = "never" ] || [ -z "$current" ]; then
        new_exp=$(date -d "+$days days" +%Y-%m-%d)
    else
        new_exp=$(date -d "$current +$days days" +%Y-%m-%d)
    fi
    chage -E "$new_exp" "$SELECTED_USER"
    echo -e "${GREEN}¡Éxito!${NC} Cuenta extendida.\nNueva Fecha de Expiración: ${YELLOW}$new_exp${NC}"
    pause_return
}

# ======================================================
#  FUNCIONES DE GESTIÓN DE XRAY (VLESS, VMESS, TROJAN)
# ======================================================
add_xray() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                   ${BOLD}CREAR CUENTA XRAY${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e " [1] VLESS (TCP, WS, XHTTP, HTTPUpgrade Y gRPC)"
    echo -e " [2] VMESS (TCP, WS, XHTTP, HTTPUpgrade Y gRPC)"
    echo -e " [3] TROJAN (TLS)"
    echo -e " [4] TODO-EN-UNO (VLESS + VMESS + TROJAN)"
    read -rp " Selecciona Protocolo: " prot
    read -rp " Nombre de usuario: " user

    if grep -qw "^$user" /etc/xray/vless.txt /etc/xray/vmess.txt /etc/xray/trojan.txt 2>/dev/null; then
        echo -e "${RED}¡El nombre de usuario ya existe!${NC}"
        pause_return
        return
    fi

    read -rp " Validez (Días): " masa
    exp=$(date -d "+${masa} days" +"%Y-%m-%d")

    read -rp " ¿Quieres usar un UUID personalizado? (y/N): " custom_uuid_prompt
    if [[ "$custom_uuid_prompt" =~ ^[Yy]$ ]]; then
        read -rp " Ingresa el UUID personalizado: " uuid
    else
        uuid=$(cat /proc/sys/kernel/random/uuid)
    fi

    pass="nokasvip${uuid:0:6}"

    VLESS_TAGS='["vless-tls-dispatcher","vless-tcp-http","vless-plain-public","vless-ws","vless-xhttp","vless-httpupgrade","vless-grpc"]'
    VMESS_TAGS='["vmess-tcp-http","vmess-ws","vmess-xhttp","vmess-httpupgrade","vmess-grpc"]'
    TROJAN_TAGS='["trojan-ws"]'

    if [ "$prot" == "1" ]; then
        jq --arg uuid "$uuid" --arg user "$user" --argjson tags "$VLESS_TAGS" \
            '(.inbounds[] | select(.tag as $t | $tags | index($t)) | .settings.clients) += [{"id": $uuid, "email": $user}]' \
            /etc/xray/config.json > /tmp/x.json && mv /tmp/x.json /etc/xray/config.json
        echo "$user $uuid $exp" >> /etc/xray/vless.txt

        clear
        echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
        echo -e "                   ${BOLD}CUENTA VLESS CREADA${NC}"
        echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
        echo -e "Usuario  : $user\nExpira   : $exp"
        echo -e "\n${YELLOW}[ VLESS TLS / SHARED PORT 443 ]${NC}\n"
        echo -e "TCP HTTP:  vless://${uuid}@${DOMAIN}:443?type=tcp&headerType=http&security=tls&encryption=none&host=${DOMAIN}&path=%2Fvless-tcp&sni=${DOMAIN}${INSECURE_PARAM}#${user}-VLESS-TCP\n"
        echo -e "WS:        vless://${uuid}@${DOMAIN}:443?type=ws&security=tls&encryption=none&path=%2Fvless&host=${DOMAIN}&sni=${DOMAIN}${INSECURE_PARAM}#${user}-VLESS-WS\n"
        echo -e "XHTTP:     vless://${uuid}@${DOMAIN}:443?type=xhttp&security=tls&encryption=none&path=%2Fxhttp&host=${DOMAIN}&sni=${DOMAIN}${INSECURE_PARAM}&mode=auto&alpn=h2%2Chttp%2F1.1#${user}-VLESS-XHTTP\n"
        echo -e "HTTPUp:    vless://${uuid}@${DOMAIN}:443?type=httpupgrade&security=tls&encryption=none&path=%2Fhttpupgrade&host=${DOMAIN}&sni=${DOMAIN}${INSECURE_PARAM}#${user}-VLESS-HTTPUp\n"
        echo -e "gRPC:      vless://${uuid}@${DOMAIN}:443?type=grpc&security=tls&encryption=none&serviceName=grpc-svc&sni=${DOMAIN}${INSECURE_PARAM}&alpn=h2#${user}-VLESS-gRPC\n"
        echo -e "${YELLOW}[ VLESS NTLS (80/8080/8880) ]${NC}\n"
        echo -e "TCP: vless://${uuid}@${DOMAIN}:80?type=tcp&headerType=http&security=none&encryption=none&path=%2Fvless-tcp&host=${DOMAIN}#${user}-VLESS-NTLS-TCP\n"
        echo -e "WS:  vless://${uuid}@${DOMAIN}:80?type=ws&security=none&encryption=none&path=%2Fvless&host=${DOMAIN}#${user}-VLESS-NTLS-WS\n"
        echo -e "HUP: vless://${uuid}@${DOMAIN}:80?type=httpupgrade&security=none&encryption=none&path=%2Fhttpupgrade&host=${DOMAIN}#${user}-VLESS-NTLS-HTTPUp\n"
        echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"

    elif [ "$prot" == "2" ]; then
        jq --arg uuid "$uuid" --arg user "$user" --argjson tags "$VMESS_TAGS" \
            '(.inbounds[] | select(.tag as $t | $tags | index($t)) | .settings.clients) += [{"id": $uuid, "alterId": 0, "email": $user}]' \
            /etc/xray/config.json > /tmp/x.json && mv /tmp/x.json /etc/xray/config.json
        echo "$user $uuid $exp" >> /etc/xray/vmess.txt

        clear
        echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
        echo -e "                   ${BOLD}CUENTA VMESS CREADA${NC}"
        echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
        echo -e "Usuario: $user\nExpira: $exp"
        echo -e "\n${YELLOW}[ VMESS TLS / PORT 443 ]${NC}"
        VMESS_TCP_JSON="{\"v\":\"2\",\"ps\":\"${user}-TLS-TCP\",\"add\":\"${DOMAIN}\",\"port\":\"443\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"tcp\",\"type\":\"http\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess-tcp\",\"tls\":\"tls\",\"sni\":\"${DOMAIN}\"}"
        echo -e "TCP:        vmess://$(echo -n "$VMESS_TCP_JSON" | base64 -w 0)"
        VMESS_WS_JSON="{\"v\":\"2\",\"ps\":\"${user}-TLS-WS\",\"add\":\"${DOMAIN}\",\"port\":\"443\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess\",\"tls\":\"tls\",\"sni\":\"${DOMAIN}\"}"
        echo -e "WS:         vmess://$(echo -n "$VMESS_WS_JSON" | base64 -w 0)"
        VMESS_XHTTP_JSON="{\"v\":\"2\",\"ps\":\"${user}-TLS-XHTTP\",\"add\":\"${DOMAIN}\",\"port\":\"443\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"xhttp\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess-xhttp\",\"tls\":\"tls\",\"sni\":\"${DOMAIN}\"}"
        echo -e "XHTTP:      vmess://$(echo -n "$VMESS_XHTTP_JSON" | base64 -w 0)"
        VMESS_HUP_JSON="{\"v\":\"2\",\"ps\":\"${user}-TLS-HUP\",\"add\":\"${DOMAIN}\",\"port\":\"443\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"httpupgrade\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess-hup\",\"tls\":\"tls\",\"sni\":\"${DOMAIN}\"}"
        echo -e "HTTPUp:     vmess://$(echo -n "$VMESS_HUP_JSON" | base64 -w 0)"
        VMESS_GRPC_JSON="{\"v\":\"2\",\"ps\":\"${user}-TLS-gRPC\",\"add\":\"${DOMAIN}\",\"port\":\"443\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"grpc\",\"type\":\"none\",\"host\":\"\",\"path\":\"\",\"serviceName\":\"vmess-grpc-svc\",\"tls\":\"tls\",\"sni\":\"${DOMAIN}\"}"
        echo -e "gRPC:       vmess://$(echo -n "$VMESS_GRPC_JSON" | base64 -w 0)"
        echo -e "\n${YELLOW}[ VMESS NTLS / PORT 80 ]${NC}"
        VMESS_NTCP_JSON="{\"v\":\"2\",\"ps\":\"${user}-NTLS-TCP\",\"add\":\"${DOMAIN}\",\"port\":\"80\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"tcp\",\"type\":\"http\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess-tcp\",\"tls\":\"\"}"
        echo -e "TCP:        vmess://$(echo -n "$VMESS_NTCP_JSON" | base64 -w 0)"
        VMESS_NWS_JSON="{\"v\":\"2\",\"ps\":\"${user}-NTLS-WS\",\"add\":\"${DOMAIN}\",\"port\":\"80\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess\",\"tls\":\"\"}"
        echo -e "WS:         vmess://$(echo -n "$VMESS_NWS_JSON" | base64 -w 0)"
        VMESS_NHUP_JSON="{\"v\":\"2\",\"ps\":\"${user}-NTLS-HUP\",\"add\":\"${DOMAIN}\",\"port\":\"80\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"httpupgrade\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess-hup\",\"tls\":\"\"}"
        echo -e "HTTPUp:     vmess://$(echo -n "$VMESS_NHUP_JSON" | base64 -w 0)"
        echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"

    elif [ "$prot" == "3" ]; then
        jq --arg pass "$pass" --arg user "$user" --argjson tags "$TROJAN_TAGS" \
            '(.inbounds[] | select(.tag as $t | $tags | index($t)) | .settings.clients) += [{"password": $pass, "email": $user}]' \
            /etc/xray/config.json > /tmp/x.json && mv /tmp/x.json /etc/xray/config.json
        echo "$user $pass $exp" >> /etc/xray/trojan.txt

        clear
        echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
        echo -e "                   ${BOLD}CUENTA TROJAN CREADA${NC}"
        echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
        echo -e "Usuario: $user\nContraseña: $pass\nExpira: $exp"
        echo -e "\n${YELLOW}TLS (443):${NC}\ntrojan://${pass}@${DOMAIN}:443?type=ws&security=tls&path=%2Ftrojan&host=${DOMAIN}&sni=${DOMAIN}${INSECURE_PARAM}#${user}"
        echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"

    elif [ "$prot" == "4" ]; then
        jq --arg uuid "$uuid" --arg pass "$pass" --arg user "$user" \
            --argjson vtags "$VLESS_TAGS" --argjson mtags "$VMESS_TAGS" --argjson ttags "$TROJAN_TAGS" \
            '(.inbounds[] | select(.tag as $t | $vtags | index($t)) | .settings.clients) += [{"id": $uuid, "email": $user}]
             | (.inbounds[] | select(.tag as $t | $mtags | index($t)) | .settings.clients) += [{"id": $uuid, "alterId": 0, "email": $user}]
             | (.inbounds[] | select(.tag as $t | $ttags | index($t)) | .settings.clients) += [{"password": $pass, "email": $user}]' \
            /etc/xray/config.json > /tmp/x.json && mv /tmp/x.json /etc/xray/config.json

        echo "$user $uuid $exp" >> /etc/xray/vless.txt
        echo "$user $uuid $exp" >> /etc/xray/vmess.txt
        echo "$user $pass $exp" >> /etc/xray/trojan.txt

        clear
        echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
        echo -e "               ${BOLD}CUENTA TODO-EN-UNO CREADA${NC}"
        echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
        echo -e "Usuario: $user\nExpira:   $exp"
        echo -e "${CYAN}--------------------------------------------------------------${NC}"
        echo -e "\n${YELLOW}[ VLESS TLS / SHARED PORT 443 ]${NC}\n"
        echo -e "TCP HTTP:  vless://${uuid}@${DOMAIN}:443?type=tcp&headerType=http&security=tls&encryption=none&host=${DOMAIN}&path=%2Fvless-tcp&sni=${DOMAIN}${INSECURE_PARAM}#${user}-VLESS-TCP\n"
        echo -e "WS:        vless://${uuid}@${DOMAIN}:443?type=ws&security=tls&encryption=none&path=%2Fvless&host=${DOMAIN}&sni=${DOMAIN}${INSECURE_PARAM}#${user}-VLESS-WS\n"
        echo -e "XHTTP:     vless://${uuid}@${DOMAIN}:443?type=xhttp&security=tls&encryption=none&path=%2Fxhttp&host=${DOMAIN}&sni=${DOMAIN}${INSECURE_PARAM}&mode=auto&alpn=h2%2Chttp%2F1.1#${user}-VLESS-XHTTP\n"
        echo -e "HTTPUp:    vless://${uuid}@${DOMAIN}:443?type=httpupgrade&security=tls&encryption=none&path=%2Fhttpupgrade&host=${DOMAIN}&sni=${DOMAIN}${INSECURE_PARAM}#${user}-VLESS-HTTPUp\n"
        echo -e "gRPC:      vless://${uuid}@${DOMAIN}:443?type=grpc&security=tls&encryption=none&serviceName=grpc-svc&sni=${DOMAIN}${INSECURE_PARAM}&alpn=h2#${user}-VLESS-gRPC\n"
        echo -e "${YELLOW}[ VLESS NTLS (80/8080/8880) ]${NC}\n"
        echo -e "TCP: vless://${uuid}@${DOMAIN}:80?type=tcp&headerType=http&security=none&encryption=none&path=%2Fvless-tcp&host=${DOMAIN}#${user}-VLESS-NTLS-TCP\n"
        echo -e "WS:  vless://${uuid}@${DOMAIN}:80?type=ws&security=none&encryption=none&path=%2Fvless&host=${DOMAIN}#${user}-VLESS-NTLS-WS\n"
        echo -e "HUP: vless://${uuid}@${DOMAIN}:80?type=httpupgrade&security=none&encryption=none&path=%2Fhttpupgrade&host=${DOMAIN}#${user}-VLESS-NTLS-HTTPUp\n"
        echo -e "\n${YELLOW}[ VMESS TLS / PORT 443 ]${NC}"
        VMESS_TCP_JSON="{\"v\":\"2\",\"ps\":\"${user}-TLS-TCP\",\"add\":\"${DOMAIN}\",\"port\":\"443\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"tcp\",\"type\":\"http\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess-tcp\",\"tls\":\"tls\",\"sni\":\"${DOMAIN}\"}"
        echo -e "TCP:        vmess://$(echo -n "$VMESS_TCP_JSON" | base64 -w 0)"
        VMESS_WS_JSON="{\"v\":\"2\",\"ps\":\"${user}-TLS-WS\",\"add\":\"${DOMAIN}\",\"port\":\"443\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess\",\"tls\":\"tls\",\"sni\":\"${DOMAIN}\"}"
        echo -e "WS:         vmess://$(echo -n "$VMESS_WS_JSON" | base64 -w 0)"
        VMESS_XHTTP_JSON="{\"v\":\"2\",\"ps\":\"${user}-TLS-XHTTP\",\"add\":\"${DOMAIN}\",\"port\":\"443\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"xhttp\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess-xhttp\",\"tls\":\"tls\",\"sni\":\"${DOMAIN}\"}"
        echo -e "XHTTP:      vmess://$(echo -n "$VMESS_XHTTP_JSON" | base64 -w 0)"
        VMESS_HUP_JSON="{\"v\":\"2\",\"ps\":\"${user}-TLS-HUP\",\"add\":\"${DOMAIN}\",\"port\":\"443\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"httpupgrade\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess-hup\",\"tls\":\"tls\",\"sni\":\"${DOMAIN}\"}"
        echo -e "HTTPUp:     vmess://$(echo -n "$VMESS_HUP_JSON" | base64 -w 0)"
        VMESS_GRPC_JSON="{\"v\":\"2\",\"ps\":\"${user}-TLS-gRPC\",\"add\":\"${DOMAIN}\",\"port\":\"443\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"grpc\",\"type\":\"none\",\"host\":\"\",\"path\":\"\",\"serviceName\":\"vmess-grpc-svc\",\"tls\":\"tls\",\"sni\":\"${DOMAIN}\"}"
        echo -e "gRPC:       vmess://$(echo -n "$VMESS_GRPC_JSON" | base64 -w 0)"
        echo -e "\n${YELLOW}[ VMESS NTLS / PORT 80 ]${NC}"
        VMESS_NTCP_JSON="{\"v\":\"2\",\"ps\":\"${user}-NTLS-TCP\",\"add\":\"${DOMAIN}\",\"port\":\"80\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"tcp\",\"type\":\"http\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess-tcp\",\"tls\":\"\"}"
        echo -e "TCP:        vmess://$(echo -n "$VMESS_NTCP_JSON" | base64 -w 0)"
        VMESS_NWS_JSON="{\"v\":\"2\",\"ps\":\"${user}-NTLS-WS\",\"add\":\"${DOMAIN}\",\"port\":\"80\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess\",\"tls\":\"\"}"
        echo -e "WS:         vmess://$(echo -n "$VMESS_NWS_JSON" | base64 -w 0)"
        VMESS_NHUP_JSON="{\"v\":\"2\",\"ps\":\"${user}-NTLS-HUP\",\"add\":\"${DOMAIN}\",\"port\":\"80\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"httpupgrade\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess-hup\",\"tls\":\"\"}"
        echo -e "HTTPUp:     vmess://$(echo -n "$VMESS_NHUP_JSON" | base64 -w 0)"
        echo -e "\n${YELLOW}[ TROJAN TLS (443) ]${NC}\ntrojan://${pass}@${DOMAIN}:443?type=ws&security=tls&path=%2Ftrojan&host=${DOMAIN}&sni=${DOMAIN}${INSECURE_PARAM}#${user}"
        echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
    fi
    systemctl restart xray
    pause_return
}

del_xray() {
    clear
    echo -e "${RED}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                   ${BOLD}ELIMINAR CUENTA XRAY${NC}"
    echo -e "${RED}══════════════════════════════════════════════════════════════${NC}"

    mapfile -t users < <(cat /etc/xray/*.txt 2>/dev/null | awk '{print $1}' | sort -u)

    if [ ${#users[@]} -eq 0 ]; then
        echo -e "${YELLOW}No se encontraron usuarios de Xray.${NC}"
        pause_return
        return
    fi
    for i in "${!users[@]}"; do
        printf "  [${YELLOW}%02d${NC}] %s\n" $((i+1)) "${users[$i]}"
    done
    echo -e "\n  [${YELLOW}00${NC}] Cancelar\n"

    read -rp "  Selecciona usuario a eliminar: " idx
    if [[ "$idx" == "00" || "$idx" == "0" ]]; then
        return
    fi
    if ! [[ "$idx" =~ ^[0-9]+$ ]] || [ "$idx" -le 0 ] || [ "$idx" -gt "${#users[@]}" ]; then
        echo -e "${RED}Selección inválida.${NC}"
        pause_return
        return
    fi

    user="${users[$((idx-1))]}"
    jq "(.inbounds[].settings.clients) |= map(select(.email != \"$user\"))" /etc/xray/config.json > /tmp/x.json && mv /tmp/x.json /etc/xray/config.json
    sed -i "/^$user /d" /etc/xray/vless.txt /etc/xray/vmess.txt /etc/xray/trojan.txt 2>/dev/null
    systemctl restart xray
    echo -e "\n${GREEN}✔ Usuario $user eliminado exitosamente.${NC}"
    pause_return
}

renew_xray() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                   ${BOLD}RENOVAR CUENTA XRAY${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    read -rp " Usuario a renovar: " user

    if ! grep -qw "^$user" /etc/xray/vless.txt /etc/xray/vmess.txt /etc/xray/trojan.txt 2>/dev/null; then
        echo -e "${RED}Usuario no encontrado.${NC}"
        pause_return
        return
    fi
    read -rp " Días a Agregar: " days
    for proto in vless vmess trojan; do
        if grep -qw "^$user" "/etc/xray/${proto}.txt"; then
            current_exp=$(grep -w "^$user" "/etc/xray/${proto}.txt" | awk '{print $3}')
            new_exp=$(date -d "$current_exp + $days days" +"%Y-%m-%d")
            sed -i "s/^$user .* $current_exp/$(grep -w "^$user" "/etc/xray/${proto}.txt" | awk '{print $1 " " $2}') $new_exp/" "/etc/xray/${proto}.txt"
        fi
    done
    echo -e "\n${GREEN}✔ Usuario '$user' renovado exitosamente.${NC}\nNueva Expiración: $new_exp"
    pause_return
}

show_xray() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                   ${BOLD}MOSTRAR ENLACES DE CONFIG XRAY${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    read -rp " Usuario a ver: " user
    local found=0
    if grep -qw "^$user" /etc/xray/vless.txt; then
        uuid=$(grep -w "^$user" /etc/xray/vless.txt | awk '{print $2}')
        echo -e "${YELLOW}VLESS TLS (443):${NC}\nvless://${uuid}@${DOMAIN}:443?type=ws&security=tls&encryption=none&path=%2Fvless&host=${DOMAIN}&sni=${DOMAIN}${INSECURE_PARAM}#${user}"
        echo -e "\n${YELLOW}VLESS NTLS (80):${NC}\nvless://${uuid}@${DOMAIN}:80?type=ws&security=none&encryption=none&path=%2Fvless&host=${DOMAIN}#${user}\n"
        found=1
    fi
    if grep -qw "^$user" /etc/xray/vmess.txt; then
        uuid=$(grep -w "^$user" /etc/xray/vmess.txt | awk '{print $2}')
        VMESS_TLS_JSON="{\"v\":\"2\",\"ps\":\"${user}-TLS\",\"add\":\"${DOMAIN}\",\"port\":\"443\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess\",\"tls\":\"tls\",\"sni\":\"${DOMAIN}\"}"
        echo -e "${YELLOW}VMESS TLS (443):${NC}\nvmess://$(echo -n "$VMESS_TLS_JSON" | base64 -w 0)"
        VMESS_NTLS_JSON="{\"v\":\"2\",\"ps\":\"${user}-NTLS\",\"add\":\"${DOMAIN}\",\"port\":\"80\",\"id\":\"${uuid}\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"/vmess\",\"tls\":\"\"}"
        echo -e "\n${YELLOW}VMESS NTLS (80):${NC}\nvmess://$(echo -n "$VMESS_NTLS_JSON" | base64 -w 0)\n"
        found=1
    fi
    if grep -qw "^$user" /etc/xray/trojan.txt; then
        pass=$(grep -w "^$user" /etc/xray/trojan.txt | awk '{print $2}')
        echo -e "${YELLOW}TROJAN TLS (443):${NC}\ntrojan://${pass}@${DOMAIN}:443?type=ws&security=tls&path=%2Ftrojan&host=${DOMAIN}&sni=${DOMAIN}${INSECURE_PARAM}#${user}\n"
        found=1
    fi
    if [ "$found" -eq 0 ]; then
        echo -e "${RED}Usuario no encontrado en ningún protocolo.${NC}"
    fi
    pause_return
}

# ======================================================
#  FUNCIONES DE GESTIÓN DE HYSTERIA v1
# ======================================================
add_hysteria() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}CREAR USUARIO HYSTERIA${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    read -rp " Ingresa Contraseña/Cadena de Auth: " new_pass

    if grep -qw "^$new_pass" "$HYST_USER_DB" 2>/dev/null || jq -e ".inbounds[0].users[] | select(.auth_str == \"$new_pass\")" "$HYST_CONFIG" >/dev/null; then
        echo -e "\n${RED}Error: ¡El usuario/contraseña ya existe!${NC}"
        pause_return
        return
    fi
    read -rp " Validez (Días): " days
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Número inválido.${NC}"
        pause_return
        return
    fi
    exp_date=$(date -d "+${days} days" +"%Y-%m-%d")

    jq ".inbounds[0].users += [{\"auth_str\": \"$new_pass\"}]" "$HYST_CONFIG" > /tmp/h.json && mv /tmp/h.json "$HYST_CONFIG"
    echo "$new_pass $exp_date" >> "$HYST_USER_DB"
    systemctl restart hysteria-server

    OBFS_VAL=$(jq -r '.inbounds[0].obfs' "$HYST_CONFIG" 2>/dev/null || echo "nokasvip")

    echo -e "\n${GREEN}✔ ¡Usuario creado exitosamente!${NC}"
    echo -e "${CYAN}--------------------------------------------------------------${NC}"
    echo -e " ${BOLD}IP:${NC}          ${YELLOW}$(server_ip)${NC}"
    echo -e " ${BOLD}Dominio:${NC}      ${YELLOW}${DOMAIN:-$(server_ip)}${NC}"
    echo -e " ${BOLD}Rango de Puertos:${NC}  ${YELLOW}20000-50000 (-> 36712)${NC}"
    echo -e " ${BOLD}Usuario (Contraseña):${NC} ${YELLOW}${new_pass}${NC}"
    echo -e " ${BOLD}Obfs:${NC}        ${YELLOW}${OBFS_VAL}${NC}"
    echo -e " ${BOLD}Fecha de Expiración:${NC} ${YELLOW}${exp_date}${NC}"
    echo -e "${CYAN}--------------------------------------------------------------${NC}"
    pause_return
}

del_hysteria() {
    clear
    echo -e "${RED}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}ELIMINAR USUARIO HYSTERIA${NC}"
    echo -e "${RED}══════════════════════════════════════════════════════════════${NC}"
    if [ ! -s "$HYST_USER_DB" ]; then
        echo -e "No se encontraron usuarios."
        pause_return
        return
    fi
    cat -n "$HYST_USER_DB" | awk '{print " ["$1"] User: "$2" | Exp: "$3}'
    echo ""
    read -rp " Ingresa el número de ID del usuario a eliminar: " del_id
    if ! [[ "$del_id" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}ID inválido.${NC}"
        pause_return
        return
    fi

    del_pass=$(sed -n "${del_id}p" "$HYST_USER_DB" | awk '{print $1}')
    if [ -z "$del_pass" ]; then
        echo -e "${RED}ID no encontrado.${NC}"
        pause_return
        return
    fi

    jq ".inbounds[0].users |= map(select(.auth_str != \"$del_pass\"))" "$HYST_CONFIG" > /tmp/h.json && mv /tmp/h.json "$HYST_CONFIG"
    sed -i "${del_id}d" "$HYST_USER_DB"
    systemctl restart hysteria-server
    echo -e "\n${GREEN}✔ ¡Usuario '$del_pass' eliminado exitosamente!${NC}"
    pause_return
}

extend_hysteria() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}EXTENDER USUARIO HYSTERIA${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    if [ ! -s "$HYST_USER_DB" ]; then
        echo -e "No se encontraron usuarios."
        pause_return
        return
    fi

    cat -n "$HYST_USER_DB" | awk '{print " ["$1"] User: "$2" | Exp: "$3}'
    echo ""
    read -rp " Ingresa el número de ID del usuario a extender: " ext_id
    if ! [[ "$ext_id" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}ID inválido.${NC}"
        pause_return
        return
    fi

    ext_pass=$(sed -n "${ext_id}p" "$HYST_USER_DB" | awk '{print $1}')
    current_exp=$(sed -n "${ext_id}p" "$HYST_USER_DB" | awk '{print $2}')
    if [ -z "$ext_pass" ]; then
        echo -e "${RED}ID no encontrado.${NC}"
        pause_return
        return
    fi

    read -rp " Días a Agregar: " days
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Número inválido.${NC}"
        pause_return
        return
    fi

    new_exp=$(date -d "$current_exp + $days days" +"%Y-%m-%d")
    sed -i "${ext_id}s/.*/$ext_pass $new_exp/" "$HYST_USER_DB"

    echo -e "\n${GREEN}✔ ¡Usuario '$ext_pass' extendido exitosamente!${NC}\n Nueva Expiración: ${YELLOW}$new_exp${NC}"
    pause_return
}

list_hysteria() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                   ${BOLD}LISTA DE USUARIOS HYSTERIA${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    if [ ! -s "$HYST_USER_DB" ]; then
        echo -e "\n No se encontraron usuarios activos.\n"
    else
        printf " %-5s | %-25s | %-15s\n" "ID" "PASSWORD (AUTH STRING)" "EXPIRY DATE"
        echo -e "${CYAN}--------------------------------------------------------------${NC}"
        cat -n "$HYST_USER_DB" | while read -r num user exp; do
            printf " [%-3s] | %-25s | %-15s\n" "$num" "$user" "$exp"
        done
        echo -e "${CYAN}--------------------------------------------------------------${NC}"
        echo -e " Total de Usuarios Activos: ${YELLOW}$(wc -l < "$HYST_USER_DB")${NC}"
    fi
    pause_return
}

speed_hysteria() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}EDITAR VELOCIDADES SUBIDA/BAJADA${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    current_up=$(jq -r '.inbounds[0].up_mbps' "$HYST_CONFIG" 2>/dev/null || echo "100")
    current_down=$(jq -r '.inbounds[0].down_mbps' "$HYST_CONFIG" 2>/dev/null || echo "100")
    echo -e " Subida Actual:    ${YELLOW}${current_up} Mbps${NC}"
    echo -e " Bajada Actual:    ${YELLOW}${current_down} Mbps${NC}\n"
    read -rp " Ingresa Nueva Velocidad de Subida (Mbps): " new_up
    read -rp " Ingresa Nueva Velocidad de Bajada (Mbps): " new_down
    if [[ "$new_up" =~ ^[0-9]+$ ]] && [[ "$new_down" =~ ^[0-9]+$ ]]; then
        jq ".inbounds[0].up_mbps = $new_up | .inbounds[0].down_mbps = $new_down" "$HYST_CONFIG" > /tmp/h.json && mv /tmp/h.json "$HYST_CONFIG"
        systemctl restart hysteria-server
        echo -e "\n${GREEN}✔ ¡Velocidades actualizadas exitosamente!${NC}"
    else
        echo -e "\n${RED}Entrada inválida. Solo números.${NC}"
    fi
    pause_return
}

change_obfs_hysteria() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}CAMBIAR OBFS DE HYSTERIA${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    current_obfs=$(jq -r '.inbounds[0].obfs' "$HYST_CONFIG" 2>/dev/null || echo "nokasvip")
    echo -e " Obfs Actual: ${YELLOW}${current_obfs}${NC}\n"
    read -rp " Ingresa Nuevo Obfs: " new_obfs
    if [ -n "$new_obfs" ]; then
        jq ".inbounds[0].obfs = \"$new_obfs\"" "$HYST_CONFIG" > /tmp/h.json && mv /tmp/h.json "$HYST_CONFIG"
        systemctl restart hysteria-server
        echo -e "\n${GREEN}✔ ¡Obfs actualizado exitosamente a: $new_obfs!${NC}"
    else
        echo -e "\n${RED}Acción cancelada.${NC}"
    fi
    pause_return
}

# ======================================================
#  FUNCIONES DE GESTIÓN DE HYSTERIA 2
# ======================================================
print_hysteria2_link() {
    local user="$1" token="$2"
    encoded_token=$(jq -nr --arg v "$token" '$v|@uri')
    encoded_obfs=$(jq -nr --arg v "$(jq -r '.obfs.salamander.password' "$HYST2_CONFIG")" '$v|@uri')
    echo "hysteria2://${encoded_token}@${DOMAIN}:${HYST2_PORT}?insecure=1&sni=${DOMAIN}&obfs=salamander&obfs-password=${encoded_obfs}#${user}-HY2"
}

add_hysteria2() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}CREAR CUENTA HYSTERIA 2${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    read -rp " Usuario: " user
    [[ "$user" =~ ^[A-Za-z0-9._-]+$ ]] || { echo -e "\n${RED}Usuario inválido.${NC}"; pause_return; return; }
    if awk -v u="$user" '$1 == u {found=1} END {exit !found}' "$HYST2_USER_DB" 2>/dev/null; then
        echo -e "\n${RED}El usuario ya existe.${NC}"
        pause_return
        return
    fi
    read -rp " Validez (Días): " days
    [[ "$days" =~ ^[0-9]+$ ]] && [ "$days" -gt 0 ] || { echo -e "\n${RED}Validez inválida.${NC}"; pause_return; return; }

    read -rp " ¿Usar un token/UUID personalizado? (y/N): " custom_token_prompt
    if [[ "$custom_token_prompt" =~ ^[Yy]$ ]]; then
        read -rp " Ingresa el token/UUID personalizado: " token
        if [[ -z "$token" ]] || [[ "$token" =~ [[:space:]] ]]; then
            echo -e "\n${RED}Token inválido: no puede estar vacío ni contener espacios.${NC}"
            pause_return
            return
        fi
        if awk -v t="$token" '$2 == t {found=1} END {exit !found}' "$HYST2_USER_DB" 2>/dev/null; then
            echo -e "\n${RED}Ese token ya está en uso por otro usuario de Hysteria 2.${NC}"
            pause_return
            return
        fi
    else
        token=$(cat /proc/sys/kernel/random/uuid)
    fi

    exp=$(date -d "+${days} days" +%Y-%m-%d)
    printf '%s %s %s\n' "$user" "$token" "$exp" >> "$HYST2_USER_DB"
    chmod 600 "$HYST2_USER_DB"
    echo -e "\n${GREEN}✔ Cuenta Hysteria 2 creada.${NC}\nUsuario: $user\nToken: $token\nExpira: $exp\n"
    print_hysteria2_link "$user" "$token"
    pause_return
}

del_hysteria2() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}ELIMINAR USUARIO HYSTERIA 2${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    [ -s "$HYST2_USER_DB" ] || { echo "No se encontraron usuarios Hysteria 2."; pause_return; return; }
    nl -w2 -s'. ' "$HYST2_USER_DB"
    read -rp " ID de usuario a eliminar: " id
    [[ "$id" =~ ^[0-9]+$ ]] || { echo -e "\n${RED}ID inválido.${NC}"; pause_return; return; }
    user=$(sed -n "${id}p" "$HYST2_USER_DB" | awk '{print $1}')
    [ -n "$user" ] || { echo -e "\n${RED}ID no encontrado.${NC}"; pause_return; return; }
    sed -i "${id}d" "$HYST2_USER_DB"
    echo -e "\n${GREEN}✔ Usuario Hysteria 2 '$user' eliminado.${NC}"
    pause_return
}

extend_hysteria2() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}EXTENDER USUARIO HYSTERIA 2${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    [ -s "$HYST2_USER_DB" ] || { echo "No se encontraron usuarios Hysteria 2."; pause_return; return; }
    nl -w2 -s'. ' "$HYST2_USER_DB"
    read -rp " ID de usuario a renovar: " id
    [[ "$id" =~ ^[0-9]+$ ]] || { echo -e "\n${RED}ID inválido.${NC}"; pause_return; return; }
    line=$(sed -n "${id}p" "$HYST2_USER_DB")
    user=$(awk '{print $1}' <<< "$line")
    token=$(awk '{print $2}' <<< "$line")
    old_exp=$(awk '{print $3}' <<< "$line")
    [ -n "$user" ] || { echo -e "\n${RED}ID no encontrado.${NC}"; pause_return; return; }
    read -rp " Días a agregar: " days
    [[ "$days" =~ ^[0-9]+$ ]] && [ "$days" -gt 0 ] || { echo -e "\n${RED}Validez inválida.${NC}"; pause_return; return; }
    base="$old_exp"
    [ "$old_exp" \< "$(date +%Y-%m-%d)" ] && base="$(date +%Y-%m-%d)"
    new_exp=$(date -d "$base +${days} days" +%Y-%m-%d)
    sed -i "${id}s/.*/$user $token $new_exp/" "$HYST2_USER_DB"
    echo -e "\n${GREEN}✔ Usuario Hysteria 2 renovado hasta $new_exp.${NC}"
    pause_return
}

list_hysteria2() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}LISTA DE USUARIOS HYSTERIA 2${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    if [ -s "$HYST2_USER_DB" ]; then
        nl -w2 -s'. ' "$HYST2_USER_DB"
    else
        echo "No se encontraron usuarios."
    fi
    pause_return
}

show_hysteria2() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}ENLACE HYSTERIA 2${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    [ -s "$HYST2_USER_DB" ] || { echo "No se encontraron usuarios Hysteria 2."; pause_return; return; }
    nl -w2 -s'. ' "$HYST2_USER_DB"
    read -rp " ID de usuario: " id
    line=$(sed -n "${id}p" "$HYST2_USER_DB")
    user=$(awk '{print $1}' <<< "$line")
    token=$(awk '{print $2}' <<< "$line")
    [ -n "$user" ] || { echo -e "\n${RED}ID no encontrado.${NC}"; pause_return; return; }
    echo
    print_hysteria2_link "$user" "$token"
    pause_return
}

# ======================================================
#  FUNCIONES DE GESTIÓN DE ZIVPN
# ======================================================
add_zivpn() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}CREAR USUARIO ZIVPN${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    read -rp " Ingresa Contraseña: " new_pass

    if grep -qw "^$new_pass" "$ZIVPN_USER_DB" 2>/dev/null; then
        echo -e "\n${RED}Error: Contraseña ya existe!${NC}"
        pause_return
        return
    fi
    read -rp " Validez (Dias): " days
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Numero Invalido.${NC}"
        pause_return
        return
    fi
    exp_date=$(date -d "+${days} days" +"%Y-%m-%d")

    jq ".auth.config += [\"$new_pass\"]" "$ZIVPN_CONFIG" > /tmp/z.json && mv /tmp/z.json "$ZIVPN_CONFIG"
    echo "$new_pass $exp_date" >> "$ZIVPN_USER_DB"
    systemctl restart zivpn.service

    OBFS_VAL=$(jq -r '.obfs' "$ZIVPN_CONFIG" 2>/dev/null || echo "nokasvip")

    echo -e "\n${GREEN}✔ Usuario creado exitosamente!${NC}"
    echo -e "${CYAN}--------------------------------------------------------------${NC}"
    echo -e " ${BOLD}IP:${NC}          ${YELLOW}$(server_ip)${NC}"
    echo -e " ${BOLD}Dominio:${NC}      ${YELLOW}${DOMAIN:-$(server_ip)}${NC}"
    echo -e " ${BOLD}Puerto De Rango:${NC}  ${YELLOW}6000-19999${NC}"
    echo -e " ${BOLD}Usuario (Contraseña):${NC} ${YELLOW}${new_pass}${NC}"
    echo -e " ${BOLD}Fecha de Expiración:${NC} ${YELLOW}${exp_date}${NC}"
    echo -e "${CYAN}--------------------------------------------------------------${NC}"
    pause_return
}

del_zivpn() {
    clear
    echo -e "${RED}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}ELIMINAR USUARIO ZIVPN${NC}"
    echo -e "${RED}══════════════════════════════════════════════════════════════${NC}"
    if [ ! -s "$ZIVPN_USER_DB" ]; then
        echo -e "No Hay Usuarios."
        pause_return
        return
    fi
    cat -n "$ZIVPN_USER_DB" | awk '{print " ["$1"] User: "$2" | Exp: "$3}'
    echo ""
    read -rp " Ingrese el número de ID del usuario a eliminar: " del_id
    if ! [[ "$del_id" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}ID inválido.${NC}"
        pause_return
        return
    fi

    del_pass=$(sed -n "${del_id}p" "$ZIVPN_USER_DB" | awk '{print $1}')
    if [ -z "$del_pass" ]; then
        echo -e "${RED}ID no encontrado.${NC}"
        pause_return
        return
    fi
    jq ".auth.config |= map(select(. != \"$del_pass\"))" "$ZIVPN_CONFIG" > /tmp/z.json && mv /tmp/z.json "$ZIVPN_CONFIG"
    sed -i "${del_id}d" "$ZIVPN_USER_DB"
    systemctl restart zivpn.service
    echo -e "\n${GREEN}✔ Usuario '$del_pass' eliminado exitosamente!${NC}"
    pause_return
}

extend_zivpn() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}EXTENDER USUARIO ZIVPN${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    if [ ! -s "$ZIVPN_USER_DB" ]; then
        echo -e "Usuarios No Encontrados."
        pause_return
        return
    fi

    cat -n "$ZIVPN_USER_DB" | awk '{print " ["$1"] User: "$2" | Exp: "$3}'
    echo ""
    read -rp " Ingrese el número de ID del usuario a extender: " ext_id
    if ! [[ "$ext_id" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Número de ID inválido.${NC}"
        pause_return
        return
    fi

    ext_pass=$(sed -n "${ext_id}p" "$ZIVPN_USER_DB" | awk '{print $1}')
    current_exp=$(sed -n "${ext_id}p" "$ZIVPN_USER_DB" | awk '{print $2}')
    if [ -z "$ext_pass" ]; then
        echo -e "${RED}ID No Encontrado.${NC}"
        pause_return
        return
    fi

    read -rp " Agregar Validez (Dias): " days
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Numero Invalido.${NC}"
        pause_return
        return
    fi

    new_exp=$(date -d "$current_exp + $days days" +"%Y-%m-%d")
    sed -i "${ext_id}s/.*/$ext_pass $new_exp/" "$ZIVPN_USER_DB"

    echo -e "\n${GREEN}✔ Usuario '$ext_pass' Extendido Exitosamente!${NC}\n New Expiry: ${YELLOW}$new_exp${NC}"
    pause_return
}

list_zivpn() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                   ${BOLD}LISTA DE USUARIOS ZIVPN${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    if [ ! -s "$ZIVPN_USER_DB" ]; then
        echo -e "\n No Hay Usuarios En Linea.\n"
    else
        printf " %-5s | %-25s | %-15s\n" "ID" "PASSWORD" "EXPIRY DATE"
        echo -e "${CYAN}--------------------------------------------------------------${NC}"
        cat -n "$ZIVPN_USER_DB" | while read -r num user exp; do
            printf " [%-3s] | %-25s | %-15s\n" "$num" "$user" "$exp"
        done
        echo -e "${CYAN}--------------------------------------------------------------${NC}"
        echo -e " Total Usuarios Activos: ${YELLOW}$(wc -l < "$ZIVPN_USER_DB")${NC}"
    fi
    pause_return
}

# ======================================================
#  MONITOR DE CONEXIONES ACTIVAS
# ======================================================
online_users() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "               ${BOLD}MONITOR DE SESIONES ACTIVAS${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"

    echo -e "${YELLOW}--- SSH LEGADO ---${NC}"
    declare -A active_ssh
    mapfile -t USERS < <(awk -F: '$3 >= 1000 && $1 != "nobody" && $1 != "systemd-network" && $1 != "messagebus" {print $1}' /etc/passwd 2>/dev/null)

    for user in "${USERS[@]}"; do
        ssh_count=$(ps -u "$user" 2>/dev/null | grep -c "sshd")
        total=$ssh_count
        if [ "$total" -gt 0 ]; then
            active_ssh["$user"]=$total
        fi
    done

    if [ "${#active_ssh[@]}" -eq 0 ]; then
        echo -e "  No hay usuarios de SSH legado autenticados en línea actualmente.\n"
    else
        printf "  %-25s %-15s\n" "USERNAME" "ACTIVE SESSIONS"
        echo -e "${CYAN}  ----------------------------------------------------------${NC}"
        for user in "${!active_ssh[@]}"; do
            if [ "${active_ssh[$user]}" -gt 1 ]; then
                printf "  %-25s ${RED}%-15s (Multi-Login)${NC}\n" "$user" "${active_ssh[$user]}"
            else
                printf "  %-25s ${GREEN}%-15s${NC}\n" "$user" "${active_ssh[$user]}"
            fi
        done | sort
        echo
    fi

    echo -e "${YELLOW}--- INICIOS DE SESIÓN ACTIVOS XRAY CORE (IPs Únicas Recientes) ---${NC}"
    if grep -q '"loglevel": "warning"' /etc/xray/config.json 2>/dev/null; then
        sed -i 's/"loglevel": "warning"/"loglevel": "info"/g' /etc/xray/config.json
        systemctl restart xray 2>/dev/null
        echo -e "  [Nota del Sistema] Registro de Xray habilitado. Reconecta a los usuarios para ver los logs.\n"
    elif [ -f /var/log/xray/access.log ]; then
        active_xray=$(tail -n 10000 /var/log/xray/access.log 2>/dev/null | grep "accepted" | awk '{ user=""; for(i=1;i<=NF;i++) if($i=="email:") user=$(i+1); if(user!="") { split($3, a, ":"); print user " " a[1] } }' | sort -u | awk '{print $1}' | uniq -c | sort -nr)
        if [ -z "$active_xray" ]; then
            echo -e "  No se encontraron usuarios activos de Xray en los logs recientes.\n"
        else
            printf "  %-15s %-25s\n" "UNIQUE IPs" "USERNAME"
            echo -e "${CYAN}  ----------------------------------------------------------${NC}"
            while read -r count username; do
                if [ -n "$username" ]; then
                    if [ "$count" -gt 1 ]; then
                        printf "  ${RED}%-15s${NC} %-25s ${RED}(Multi-IP)${NC}\n" "$count" "$username"
                    else
                        printf "  %-15s %-25s\n" "$count" "$username"
                    fi
                fi
            done <<< "$active_xray"
        fi
    else
        echo -e "  Log de acceso de Xray no encontrado.\n"
    fi

    pause_return
}

# ======================================================
#  CONTROL DE SERVICIOS (REINICIOS)
# ======================================================
restart_service() {
    local service_name="$1"
    local display_name="$2"
    echo -e "Reiniciando ${display_name}..."
    systemctl restart $service_name 2>/dev/null || true
    echo -e "${GREEN}✔ ${display_name} reiniciado.${NC}"
}

service_control_menu() {
    while true; do
        clear
        echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
        echo -e "                   ${BOLD}CONTROL DE SERVICIOS${NC}"
        echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
        echo -e "  [${YELLOW}01${NC}] Reiniciar Todos Los Servicios"
        echo -e "  [${YELLOW}02${NC}] Reiniciar SSH"
        echo -e "  [${YELLOW}03${NC}] Reiniciar Proxies WebSocket de Node"
        echo -e "  [${YELLOW}04${NC}] Reiniciar Stunnel y Xray Core"
        echo -e "  [${YELLOW}05${NC}] Reiniciar Squid Proxy y Nginx"
        echo -e "  [${YELLOW}06${NC}] Reiniciar Núcleo UDP (SlowDNS / Hysteria / BadVPN)"
        echo -e "  [${YELLOW}07${NC}] Reiniciar Multiplexor (dnsdist / Slipstream / Dante)"
        echo -e "  [${YELLOW}00${NC}] Atrás\n"
        read -rp "  Selecciona una opción: " opt
        case "$opt" in
            1|01) restart_service "ssh stunnel4 sslh squid nginx server-sldns hysteria-server hysteria2-server badvpn ws-proxy@10080 ws-proxy@25 ws-proxy@2082 ws-proxy@2086 xray slipstream danted dnsdist" "All Services"
                  pause_return ;;
            2|02) restart_service "ssh" "SSH"; pause_return ;;
            3|03) restart_service "ws-proxy@10080 ws-proxy@25 ws-proxy@2082 ws-proxy@2086" "Node WebSocket Proxies"; pause_return ;;
            4|04) restart_service "stunnel4 xray" "Stunnel & Xray Core"; pause_return ;;
            5|05) restart_service "squid nginx" "Squid Proxy & Nginx"; pause_return ;;
            6|06) restart_service "server-sldns hysteria-server hysteria2-server badvpn" "UDP Core Services"; pause_return ;;
            7|07) restart_service "dnsdist slipstream danted" "Multiplexor (dnsdist/Slipstream/Dante)"; pause_return ;;
            0|00) break ;;
            *) echo -e "${RED}Opción inválida.${NC}"; sleep 1 ;;
        esac
    done
}

# ======================================================
#  RESPALDO Y RESTAURACIÓN
# ======================================================
backup_snapshot() {
    clear
    local out="/root/nokasvip_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
    echo -e "Empaquetando configuraciones del servidor..."
    tar -czf "$out" /etc/ssh /etc/stunnel /etc/squid /etc/hysteria /etc/hysteria2 /etc/deekayvpn /etc/systemd/system/ws-proxy@.service /etc/xray 2>/dev/null
    echo -e "\n${GREEN}✔ ¡Respaldo creado exitosamente!${NC}\nUbicación: ${YELLOW}$out${NC}"
    pause_return
}

restore_snapshot() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                   ${BOLD}RESTAURAR CONFIGURACIÓN${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    shopt -s nullglob
    backups=(/root/nokasvip_backup_*.tar.gz)
    if [ ${#backups[@]} -eq 0 ]; then
        echo -e "${RED}  No se encontraron archivos de respaldo en /root/.${NC}"
        pause_return
        return
    fi
    echo -e "  Respaldos Disponibles:\n"
    for i in "${!backups[@]}"; do
        printf "  [${YELLOW}%02d${NC}] %s\n" $((i+1)) "$(basename "${backups[$i]}")"
    done
    echo -e "\n  [${YELLOW}00${NC}] Cancelar\n"
    read -rp "  Selecciona respaldo a restaurar: " sel
    if [[ "$sel" == "00" || "$sel" == "0" ]]; then
        return
    fi
    idx=$((sel-1))
    if [ -n "${backups[$idx]}" ]; then
        echo -e "\nRestaurando ${YELLOW}$(basename "${backups[$idx]}")${NC}..."
        tar -xzf "${backups[$idx]}" -C /
        systemctl daemon-reload
        systemctl restart ssh stunnel4 sslh squid nginx server-sldns hysteria-server badvpn ws-proxy@10080 ws-proxy@25 ws-proxy@2082 ws-proxy@2086 xray slipstream danted dnsdist 2>/dev/null || true
        echo -e "${GREEN}✔ ¡Restauración completa!${NC}"
    else
        echo -e "${RED}Selección inválida.${NC}"
    fi
    pause_return
}

# ======================================================
#  UTILIDADES DEL SISTEMA
# ======================================================
utilities_menu() {
    while true; do
        clear
        echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
        echo -e "                   ${BOLD}UTILIDADES DEL SISTEMA${NC}"
        echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
        echo -e "  [${YELLOW}1${NC}] Activar BBR Nativo del Kernel"
        echo -e "  [${YELLOW}2${NC}] Verificar Desbloqueos de Netflix y Streaming (Inglés)"
        echo -e "  [${YELLOW}0${NC}] Atrás\n"
        read -rp "  Selecciona una opción: " subopt
        case "$subopt" in
            1)
                echo -e "\nActivando BBR Nativo del Kernel..."
                # Evitar duplicados
                sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
                sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
                echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
                echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
                sysctl -p >/dev/null 2>&1
                if [[ "$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null)" == *"bbr"* ]]; then
                    echo -e "${GREEN}✔ ¡BBR Activado Exitosamente!${NC}"
                else
                    echo -e "${RED}✖ Fallo al activar BBR (puede que el kernel no lo soporte).${NC}"
                fi
                pause_return
                ;;
            2)
                clear
                echo -e "${YELLOW}Ejecutando Verificación de Restricción Regional (Inglés)...${NC}\n"
                bash <(curl -sL https://raw.githubusercontent.com/lmc999/RegionRestrictionCheck/main/check.sh) -E en
                echo ""
                pause_return
                ;;
            0) break ;;
            *) echo -e "${RED}Opción inválida.${NC}"; sleep 1 ;;
        esac
    done
}

# ======================================================
#  CONFIGURACIÓN AVANZADA (DOMINIO, NS, SLIPSTREAM, ETC.)
# ======================================================
change_domain() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                 ${BOLD}CAMBIAR DOMINIO DEL SERVIDOR${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    current_dom=$(cat /etc/deekayvpn/domain.txt 2>/dev/null || echo "No configurado")
    current_cert=$(cat /etc/xray/cert_type 2>/dev/null || echo "desconocido")
    echo -e " Dominio/IP Actual: ${YELLOW}$current_dom${NC}  (certificado: ${YELLOW}$current_cert${NC})\n"
    read -rp " Ingresa Nuevo Dominio o IP: " new_dom

    if [ -z "$new_dom" ]; then
        echo -e "\n${RED}Acción cancelada.${NC}"
        pause_return
        return
    fi
    if [ "$new_dom" = "$current_dom" ]; then
        echo -e "\n${RED}Es el mismo dominio/IP, sin cambios.${NC}"
        pause_return
        return
    fi

    SERVER_IP=$(curl -4 -s --max-time 2 ipv4.icanhazip.com || hostname -I | awk '{print $1}')

    if [[ "$new_dom" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "\n${YELLOW}Generando certificado autofirmado para la IP $new_dom...${NC}"
        systemctl stop xray 2>/dev/null || true
        openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
            -keyout /etc/xray/xray.key \
            -out /etc/xray/xray.crt \
            -subj "/CN=${new_dom}/O=nokasvip/C=US"
        echo "selfsigned" > /etc/xray/cert_type
        rm -f /etc/cron.d/certbot-renew
        NEW_CERT_TYPE="selfsigned"
    else
        echo -e "\n${YELLOW}Verificando que $new_dom resuelva a $SERVER_IP...${NC}"
        command -v dig >/dev/null 2>&1 || apt-get install -y dnsutils >/dev/null 2>&1
        DOMAIN_IP=$(dig +short "$new_dom" @8.8.8.8 | tail -1)
        if [ "$DOMAIN_IP" != "$SERVER_IP" ]; then
            echo -e "\n${RED}✘ ERROR: $new_dom no apunta a $SERVER_IP todavía.${NC}"
            echo -e "  Crea/corrige el registro A en tu DNS y vuelve a intentar. No se cambió nada."
            pause_return
            return
        fi
        echo -e "${GREEN}Dominio verificado. Solicitando certificado Let's Encrypt...${NC}"
        command -v certbot >/dev/null 2>&1 || apt-get install -y certbot >/dev/null 2>&1
        systemctl stop xray 2>/dev/null || true
        systemctl stop nginx 2>/dev/null || true
        read -p "Ingresa tu correo electrónico (opcional, presiona enter para usar admin@$new_dom): " LETS_EMAIL
        [ -z "$LETS_EMAIL" ] && LETS_EMAIL="admin@${new_dom}"
        if ! certbot certonly --standalone --non-interactive --agree-tos --email "$LETS_EMAIL" -d "${new_dom}"; then
            echo -e "\n${RED}✘ Falló la emisión del certificado Let's Encrypt. No se cambió el dominio.${NC}"
            systemctl start xray 2>/dev/null || true
            pause_return
            return
        fi
        cp "/etc/letsencrypt/live/${new_dom}/fullchain.pem" /etc/xray/xray.crt
        cp "/etc/letsencrypt/live/${new_dom}/privkey.pem" /etc/xray/xray.key
        echo "letsencrypt" > /etc/xray/cert_type
        NEW_CERT_TYPE="letsencrypt"

        mkdir -p /etc/letsencrypt/renewal-hooks/deploy
        cat <<'EOF_RENEW' > /etc/letsencrypt/renewal-hooks/deploy/nokasvip-hook.sh
#!/bin/bash
set -e
for domain in $RENEWED_DOMAINS; do
    cp /etc/letsencrypt/live/$domain/fullchain.pem /etc/xray/xray.crt
    cp /etc/letsencrypt/live/$domain/privkey.pem /etc/xray/xray.key
    cat /etc/letsencrypt/live/$domain/privkey.pem /etc/letsencrypt/live/$domain/fullchain.pem > /etc/stunnel/stunnel.pem
    chmod 600 /etc/stunnel/stunnel.pem /etc/xray/xray.key
    chmod 644 /etc/xray/xray.crt
    systemctl restart xray stunnel4
    break
done
EOF_RENEW
        chmod +x /etc/letsencrypt/renewal-hooks/deploy/nokasvip-hook.sh
        echo "0 3 * * * root certbot renew --quiet --deploy-hook /etc/letsencrypt/renewal-hooks/deploy/nokasvip-hook.sh" > /etc/cron.d/certbot-renew
    fi

    chmod 644 /etc/xray/xray.crt
    chmod 600 /etc/xray/xray.key
    cat /etc/xray/xray.key /etc/xray/xray.crt > /etc/stunnel/stunnel.pem
    chmod 600 /etc/stunnel/stunnel.pem
    chown root:root /etc/stunnel/stunnel.pem

    echo "$new_dom" > /etc/deekayvpn/domain.txt
    DOMAIN="$new_dom"

    systemctl start xray 2>/dev/null || true
    if ! /usr/local/bin/xray run -test -config /etc/xray/config.json >/dev/null 2>&1; then
        echo -e "\n${RED}✘ Advertencia: el nuevo certificado no pasó la validación de Xray.${NC}"
    fi
    systemctl restart xray stunnel4 2>/dev/null || true
    systemctl restart nginx 2>/dev/null || true

    echo -e "\n${GREEN}✔ Dominio actualizado a: $new_dom${NC}"
    echo -e "${GREEN}✔ Certificado regenerado (${NEW_CERT_TYPE}) y Xray/Stunnel reiniciados.${NC}"
    echo -e "${YELLOW}Nota: los enlaces vless/vmess/trojan que ya diste a usuarios usaban el dominio/cert${NC}"
    echo -e "${YELLOW}anterior. Genera enlaces nuevos desde el menú de Xray (opción Mostrar Enlaces).${NC}"
    pause_return
}

change_slowdns() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "               ${BOLD}CAMBIAR NAMESERVER DE SLOWDNS${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    svc_file="/etc/systemd/system/server-sldns.service"
    if [ ! -f "$svc_file" ]; then
        echo -e "${RED}Archivo de servicio SlowDNS no encontrado.${NC}"
        pause_return
        return
    fi
    current_ns=$(grep 'ExecStart=' "$svc_file" | sed 's/.*server\.key \([^ ]*\) .*/\1/')
    echo -e " Nameserver Actual: ${YELLOW}$current_ns${NC}\n"
    read -rp " Ingresa Nuevo Nameserver (ej. ns1.dominio.com): " new_ns
    ss_dom=$(cat /etc/deekayvpn/slipstream_domain.txt 2>/dev/null || echo "")
    if [ -n "$new_ns" ] && [ "$new_ns" = "$ss_dom" ]; then
        echo -e "\n${RED}✘ Ese dominio ya lo usa Slipstream. dnsdist enruta por dominio, no pueden ser iguales.${NC}"
        pause_return
        return
    fi
    if [ -n "$new_ns" ] && [ "$new_ns" != "$current_ns" ]; then
        sed -i "s/$current_ns/$new_ns/g" "$svc_file"
        systemctl daemon-reload
        systemctl restart server-sldns
        echo -e "\n${GREEN}✔ Nameserver de SlowDNS actualizado a: $new_ns${NC}"
    else
        echo -e "\n${RED}Acción cancelada o se ingresó el mismo NS.${NC}"
    fi
    pause_return
}

change_slipstream() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "                     ${BOLD}SLIPSTREAM${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    svc_file="/etc/systemd/system/slipstream.service"
    dnsdist_conf="/etc/dnsdist/dnsdist.conf"
    sldns_svc="/etc/systemd/system/server-sldns.service"

    if [ ! -f "$svc_file" ]; then
        echo -e " SlipStream no está instalado en este servidor."
        read -rp " ¿Deseas instalarlo ahora? [y/N]: " ans
        if ! [[ "$ans" =~ ^[Yy]$ ]]; then
            echo -e "\n${RED}Cancelado.${NC}"
            pause_return
            return
        fi
        # Instalación rápida de SlipStream (similar a la lógica de la Parte 3, pero en el menú)
        echo "Instalando SlipStream..."
        command -v danted >/dev/null 2>&1 || apt-get install -y dante-server
        EXT_IP="$(ip -4 addr show scope global 2>/dev/null | awk '/inet/{print $2}' | cut -d/ -f1 | head -1)"
        [ -z "$EXT_IP" ] && EXT_IP="$(curl -s --max-time 5 ifconfig.me 2>/dev/null)"
        cat > /etc/danted.conf <<DANTE_EOF
logoutput: syslog
internal: 127.0.0.1 port = 1080
external: ${EXT_IP}
socksmethod: none
clientmethod: none
client pass {
    from: 127.0.0.1/32 to: 0.0.0.0/0
    log: connect disconnect error
}
socks pass {
    from: 127.0.0.1/32 to: 0.0.0.0/0
    protocol: tcp udp
    log: connect disconnect error
}
DANTE_EOF
        systemctl restart danted
        systemctl enable danted >/dev/null 2>&1

        if ! command -v cargo &>/dev/null; then
            curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y >/dev/null 2>&1
            source "$HOME/.cargo/env"
        else
            source "$HOME/.cargo/env" 2>/dev/null || true
        fi

        if [ -d "/opt/slipstream-rust/.git" ]; then
            cd /opt/slipstream-rust
        else
            rm -rf /opt/slipstream-rust
            git clone --quiet https://github.com/Mygod/slipstream-rust.git /opt/slipstream-rust
            cd /opt/slipstream-rust
        fi
        git fetch --quiet origin
        git checkout --quiet bc772dd07d9a136dbd7553b0da575526de207847
        git submodule update --init --recursive --quiet
        cargo build --release -p slipstream-server --quiet 2>&1
        cd /root

        read -rp "Ingresa el dominio para SlipStream (ej. ss.${DOMAIN}): " SlipstreamDomain
        [ -z "$SlipstreamDomain" ] && SlipstreamDomain="ss.${DOMAIN}"
        cat > /etc/systemd/system/slipstream.service <<SLIPSTREAM_EOF
[Unit]
Description=Slipstream DNS Tunnel Server
After=network.target danted.service
[Service]
Type=simple
ExecStart=/opt/slipstream-rust/target/release/slipstream-server \\
    --dns-listen-port 5300 \\
    --target-address 127.0.0.1:1080 \\
    --domain ${SlipstreamDomain} \\
    --cert /opt/slipstream-rust/cert.pem \\
    --key /opt/slipstream-rust/key.pem \\
    --reset-seed /opt/slipstream-rust/reset-seed
WorkingDirectory=/opt/slipstream-rust
Restart=always
RestartSec=5
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
SLIPSTREAM_EOF
        systemctl daemon-reload
        systemctl enable slipstream >/dev/null 2>&1
        systemctl restart slipstream
        echo "$SlipstreamDomain" > /etc/deekayvpn/slipstream_domain.txt

        # Mover SlowDNS a 5301 y configurar dnsdist
        sed -i 's|-udp :53 -privkey-file|-udp 127.0.0.1:5301 -privkey-file|' "$sldns_svc"
        systemctl daemon-reload
        systemctl restart server-sldns

        command -v dnsdist >/dev/null 2>&1 || apt-get install -y dnsdist
        mkdir -p /etc/dnsdist
        current_ns=$(grep 'ExecStart=' "$sldns_svc" | sed 's/.*server\.key \([^ ]*\) .*/\1/')
        cat > /etc/dnsdist/dnsdist.conf <<DNSDIST_EOF
setLocal("0.0.0.0:53")
newServer({address="127.0.0.1:5301", name="slowdns"})
newServer({address="127.0.0.1:5300", name="slipstream"})
addAction(SuffixMatchNodeRule("${current_ns}."), PoolAction("slowdns_pool"))
setPoolServers("slowdns_pool", {getServer(0)})
addAction(SuffixMatchNodeRule("${SlipstreamDomain}."), PoolAction("slipstream_pool"))
setPoolServers("slipstream_pool", {getServer(1)})
addAction(AllRule(), DropAction())
DNSDIST_EOF
        systemctl daemon-reload
        systemctl enable dnsdist >/dev/null 2>&1
        systemctl restart dnsdist
        echo -e "${GREEN}SlipStream instalado correctamente.${NC}"
        pause_return
        return
    fi

    # Si ya está instalado, permitir cambiar el dominio
    current_dom=$(cat /etc/deekayvpn/slipstream_domain.txt 2>/dev/null || echo "No configurado")
    echo -e " Dominio Actual: ${YELLOW}$current_dom${NC}\n"
    read -rp " Ingresa Nuevo Dominio (enter para dejarlo igual): " new_dom
    [ -z "$new_dom" ] && { echo -e "\n${RED}Sin cambios.${NC}"; pause_return; return; }
    current_ns=$(grep 'ExecStart=' "$sldns_svc" 2>/dev/null | sed 's/.*server\.key \([^ ]*\) .*/\1/')
    if [ "$new_dom" = "$current_ns" ]; then
        echo -e "\n${RED}✘ Ese dominio ya lo usa SlowDNS. dnsdist enruta por dominio, no pueden ser iguales.${NC}"
        pause_return
        return
    fi
    if [ "$new_dom" != "$current_dom" ]; then
        sed -i "s/--domain ${current_dom} /--domain ${new_dom} /" "$svc_file"
        [ -f "$dnsdist_conf" ] && sed -i "s/${current_dom}\./${new_dom}./g" "$dnsdist_conf"
        echo "$new_dom" > /etc/deekayvpn/slipstream_domain.txt
        systemctl daemon-reload
        systemctl restart slipstream dnsdist
        echo -e "\n${GREEN}✔ Dominio de Slipstream actualizado a: $new_dom${NC}"
    else
        echo -e "\n${RED}Se ingresó el mismo dominio, sin cambios.${NC}"
    fi
    pause_return
}

# ======================================================
#  PANEL PRINCIPAL (DASHBOARD)
# ======================================================
draw_header() {
    local os_name=$(. /etc/os-release 2>/dev/null; echo "${ID:-UNKNOWN}" | tr '[:lower:]' '[:upper:]')
    local os_ver=$(. /etc/os-release 2>/dev/null; echo "${VERSION_ID:-}")
    local os="${os_name} ${os_ver}"
    local arch=$(uname -m)
    local cores=$(nproc 2>/dev/null || echo "1")
    local ip=$(server_ip)
    local time=$(date '+%H:%M %Z')
    local status=$(server_status)
    local ram=$(ram_percent)
    local cpu=$(cpu_percent)
    local buf=$(buffer_mem)

    echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}       >>>>>  🐉  ${YELLOW}${BOLD}nokasvip | kyz | http door | socketdevz${NC}${BLUE}  🐉  <<<<<${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
    printf "  ${WHITE}%-5s${NC} ${YELLOW}%-17s${NC} ${WHITE}%-6s${NC} ${YELLOW}%-14s${NC} ${WHITE}%-7s${NC} ${YELLOW}%s${NC}\n" "OS:" "$os" "Arch:" "$arch" "Cores:" "$cores"
    printf "  ${WHITE}%-5s${NC} ${YELLOW}%-17s${NC} ${WHITE}%-6s${NC} ${YELLOW}%-14s${NC} ${WHITE}%-7s${NC} %s\n" "IP:" "$ip" "Time:" "$time" "Status:" "$status"
    echo -e "${CYAN}------------------------ ${BOLD}Puertos Abiertos${NC} ${CYAN}------------------------${NC}"
    printf "  ${WHITE}• %-12s${NC} ${GREEN}%-22s${NC} ${WHITE}• %-13s${NC} ${GREEN}%s${NC}\n" "SSH:" "22, 299" "System-DNS:" "53"
    printf "  ${WHITE}• %-12s${NC} ${GREEN}%-22s${NC} ${WHITE}• %-13s${NC} ${GREEN}%s${NC}\n" "WEB-Nginx:" "85" "SSL:" "443"
    printf "  ${WHITE}• %-12s${NC} ${GREEN}%-22s${NC} ${WHITE}• %-13s${NC} ${GREEN}%s${NC}\n" "SSL/PYTHON:" "443" "Squid:" "3128, 8000"
    printf "  ${WHITE}• %-12s${NC} ${GREEN}%-22s${NC} ${WHITE}• %-13s${NC} ${GREEN}%s${NC}\n" "WS/PYTHON:" "80, 8080, 8880" "BadVPN:" "7300"
    printf "  ${WHITE}• %-12s${NC} ${GREEN}%-22s${NC} ${WHITE}• %-13s${NC} ${GREEN}%s${NC}\n" "WS/PYTHON:" "2082, 2086, 25" "XRAY NTLS:" "80, 8080, 8880"
    printf "  ${WHITE}• %-12s${NC} ${GREEN}%-22s${NC} ${WHITE}• %-13s${NC} ${GREEN}%s${NC}\n" "XRAY TLS:" "443" "SlowDNS/SS:" "53 (dnsdist)"
    printf "  ${WHITE}• %-12s${NC} ${GREEN}%-22s${NC} ${WHITE}• %-13s${NC} ${GREEN}%s${NC}\n" "SOCKS:" "127.0.0.1:1080" "Hysteria 1:" "20000-50000"
    printf "  ${WHITE}• %-12s${NC} ${GREEN}%-22s${NC} ${WHITE}• %-13s${NC} ${GREEN}%s${NC}\n" "Hysteria 2:" "36713/UDP" "UDPCustom:" "1-65535"
    printf "  ${WHITE}• %-12s${NC} ${GREEN}%-22s${NC} ${WHITE}• %-13s${NC} ${GREEN}%s${NC}\n" "ZiVPN:" "6000-19999"
    echo -e "${CYAN}----------------------- ${BOLD}Recursos Del Sistema${NC} ${CYAN}-----------------------${NC}"
    printf "  ${WHITE}%-10s${NC} ${YELLOW}%-14s${NC} ${WHITE}%-10s${NC} ${YELLOW}%-10s${NC} ${WHITE}%-8s${NC} ${YELLOW}%s${NC}\n" "RAM Usada:" "$ram" "CPU Usada:" "$cpu" "Buffer:" "$buf"
    echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
}

# ======================================================
#  BUCLE PRINCIPAL DEL MENÚ
# ======================================================
while true; do
    clear
    draw_header
    echo
    echo -e "  [${YELLOW}01${NC}] Gestión de Cuentas SSH (Legado)"
    echo -e "  [${YELLOW}02${NC}] Gestión de Cuentas Xray (V2ray)"
    echo -e "  [${YELLOW}03${NC}] Gestión de Cuentas Hysteria (UDP)"
    echo -e "  [${YELLOW}04${NC}] Gestión de Cuentas Hysteria 2 (UDP)"
    echo -e "  [${YELLOW}05${NC}] ZiVPN Account Management (UDP)"
    echo -e "  [${YELLOW}06${NC}] Monitorear Conexiones Activas"
    echo -e "  [${YELLOW}07${NC}] Control de Servicios (Reiniciar Protocolos)"
    echo -e "  [${YELLOW}08${NC}] Respaldar y Restaurar Datos"
    echo -e "  [${YELLOW}09${NC}] Utilidades del Sistema (BBR y Netflix)"
    echo -e "  [${YELLOW}10${NC}] Configuración Avanzada (Dominio / Nameserver)"
    echo -e "  [${YELLOW}11${NC}] Reiniciar Servidor"
    echo -e "  [${RED}00${NC}] Salir\n"
    read -rp "  ► Selecciona una opción: " opt

    case "$opt" in
        1|01)
            while true; do
                clear
                echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
                echo -e "                   ${BOLD}GESTIÓN DE CUENTAS SSH${NC}"
                echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
                echo -e "  [${YELLOW}1${NC}] Crear Usuario SSH"
                echo -e "  [${YELLOW}2${NC}] Extender Expiración"
                echo -e "  [${YELLOW}3${NC}] Eliminar Usuario SSH"
                echo -e "  [${YELLOW}4${NC}] Listar Todas Las Cuentas"
                echo -e "  [${YELLOW}0${NC}] Atrás\n"
                read -rp "  ► Opción: " sub
                case "$sub" in
                    1) create_user ;;
                    2) extend_user ;;
                    3) delete_user ;;
                    4) list_real_users | nl -w2 -s'. '
                       pause_return ;;
                    0) break ;;
                esac
            done
            ;;
        2|02)
            while true; do
                clear
                echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
                echo -e "                   ${BOLD}GESTIÓN DE CUENTAS XRAY${NC}"
                echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
                echo -e "  [${YELLOW}1${NC}] Agregar Cuenta Xray"
                echo -e "  [${YELLOW}2${NC}] Renovar Cuenta Xray"
                echo -e "  [${YELLOW}3${NC}] Eliminar Cuenta Xray"
                echo -e "  [${YELLOW}4${NC}] Mostrar Enlaces de Config"
                echo -e "  [${YELLOW}5${NC}] Forzar Eliminación de Usuarios Xray Expirados"
                echo -e "  [${YELLOW}6${NC}] Actualizar Versión de Xray Core"
                echo -e "  [${YELLOW}0${NC}] Atrás\n"
                read -rp "  ► Opción: " sub
                case "$sub" in
                    1) add_xray ;;
                    2) renew_xray ;;
                    3) del_xray ;;
                    4) show_xray ;;
                    5) /usr/local/bin/exp-check
                       echo "Usuarios Xray expirados eliminados."
                       pause_return ;;
                    6) systemctl stop xray
                       XRAY_VER="v26.5.9"
                       echo "Reinstalando Xray Core ${XRAY_VER}..."
                       wget -qO /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VER}/Xray-linux-64.zip"
                       unzip -q -o /tmp/xray.zip -d /tmp/xray/ && mv -f /tmp/xray/xray /usr/local/bin/xray
                       systemctl start xray
                       echo -e "${GREEN}✔ ¡Xray Restaurado a ${XRAY_VER}!${NC}"
                       pause_return ;;
                    0) break ;;
                esac
            done
            ;;
        3|03)
            while true; do
                clear
                echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
                echo -e "                   ${BOLD}GESTIÓN DE CUENTAS HYSTERIA${NC}"
                echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
                echo -e "  [${YELLOW}1${NC}] Agregar Cuenta Hysteria"
                echo -e "  [${YELLOW}2${NC}] Renovar Cuenta Hysteria"
                echo -e "  [${YELLOW}3${NC}] Eliminar Cuenta Hysteria"
                echo -e "  [${YELLOW}4${NC}] Listar Todas Las Cuentas"
                echo -e "  [${YELLOW}5${NC}] Editar Velocidades Subida/Bajada"
                echo -e "  [${YELLOW}6${NC}] Cambiar Obfs"
                echo -e "  [${YELLOW}0${NC}] Atrás\n"
                read -rp "  ► Opción: " sub
                case "$sub" in
                    1) add_hysteria ;;
                    2) extend_hysteria ;;
                    3) del_hysteria ;;
                    4) list_hysteria ;;
                    5) speed_hysteria ;;
                    6) change_obfs_hysteria ;;
                    0) break ;;
                esac
            done
            ;;
        4|04)
            while true; do
                clear
                echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
                echo -e "                   ${BOLD}GESTIÓN DE CUENTAS HYSTERIA 2${NC}"
                echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
                echo -e "  [${YELLOW}1${NC}] Agregar Cuenta Hysteria 2"
                echo -e "  [${YELLOW}2${NC}] Renovar Cuenta Hysteria 2"
                echo -e "  [${YELLOW}3${NC}] Eliminar Cuenta Hysteria 2"
                echo -e "  [${YELLOW}4${NC}] Listar Todas Las Cuentas"
                echo -e "  [${YELLOW}5${NC}] Mostrar Enlace de Cuenta"
                echo -e "  [${YELLOW}0${NC}] Atrás\n"
                read -rp "  ► Opción: " sub
                case "$sub" in
                    1) add_hysteria2 ;;
                    2) extend_hysteria2 ;;
                    3) del_hysteria2 ;;
                    4) list_hysteria2 ;;
                    5) show_hysteria2 ;;
                    0) break ;;
                esac
            done
            ;;
        5|05)
            while true; do
                clear
                echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
                echo -e "                   ${BOLD}GESTION DE CUENTAS ZIVPN${NC}"
                echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
                echo -e "  [${YELLOW}1${NC}] Agregar Cuenta ZiVPN"
                echo -e "  [${YELLOW}2${NC}] Renovar Cuenta ZiVPN"
                echo -e "  [${YELLOW}3${NC}] Eliminar Cuenta ZiVPN"
                echo -e "  [${YELLOW}4${NC}] Listar Todas Las Cuentas"
                echo -e "  [${YELLOW}0${NC}] Atrás\n"
                read -rp "  ► Opción: " sub
                case "$sub" in
                    1) add_zivpn ;;
                    2) extend_zivpn ;;
                    3) del_zivpn ;;
                    4) list_zivpn ;;
                    0) break ;;
                esac
            done
            ;;
        6|06) online_users ;;
        7|07) service_control_menu ;;
        8|08)
            clear
            echo -e "  [1] Respaldar Configuraciones del Sistema"
            echo -e "  [2] Restaurar Desde Respaldo"
            echo -e "  [0] Atrás"
            read -rp " Selecciona: " subopt
            case "$subopt" in
                1) backup_snapshot ;;
                2) restore_snapshot ;;
            esac
            ;;
        9|09) utilities_menu ;;
        10) advanced_menu ;;
        11)
            clear
            read -rp "¿Reiniciar el servidor ahora? [y/N]: " ans
            [[ "$ans" =~ ^[Yy]$ ]] && reboot
            ;;
        0|00)
            clear
            exit 0
            ;;
    esac
done
EOF_MENU

# ======================================================
#  FINALIZACIÓN DEL SCRIPT
# ======================================================
chmod +x /usr/local/bin/menu
ln -sf /usr/local/bin/menu /usr/bin/menu

# Limpieza y mensaje final
clear
figlet -c "nokasvip" | lolcat 2>/dev/null || figlet -c "nokasvip"
echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}       ¡Instalación completada con éxito!${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
echo -e "  Tu VPS ahora tiene todos los servicios configurados."
echo -e "  ${BOLD}Marca:${NC} nokasvip | kyz | http door | socketdevz"
echo -e "  ${BOLD}Dominio:${NC} $DOMAIN"
echo -e "  ${BOLD}Credenciales generadas automáticamente:${NC}"
echo -e "    - Hysteria/ZiVPN obfs: ${YELLOW}$OBFS${NC}"
echo -e "    - Hysteria/ZiVPN password: ${YELLOW}$PASSWORD${NC}"
echo -e "    - SlowDNS keys: guardadas en /etc/slowdns/"
echo ""
echo -e "  ${BOLD}Para acceder al panel de control, después del reinicio ejecuta:${NC}"
echo -e "  ${YELLOW}menu${NC}"
echo ""
echo -e "${RED}El sistema se reiniciará en 10 segundos para aplicar todos los cambios.${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
sleep 10
reboot