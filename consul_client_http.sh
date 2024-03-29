#!/bin/bash

set -x
export TERM=xterm-256color
export DEBIAN_FRONTEND=noninteractive
LOCAL_IPV4=$(curl "http://169.254.169.254/latest/meta-data/local-ipv4")
CONSUL_NODE_NAME=consul-kubernetes-node
SERVICE_PORT_NUMBER=30036
CONSUL_SERVICE_NAME=http

# Downloading and installing Prerequisites
sudo apt-get update -y
sudo apt-get install -y \
   apt-transport-https \
   ca-certificates \
   curl \
   software-properties-common \
   jq \
   unzip \
   dnsmasq \
   

echo "Enabling *.service.consul resolution system wide"
cat << EODMCF >/etc/dnsmasq.d/10-consul
# Enable forward lookup of the 'consul' domain:
server=/consul/127.0.0.1#8600
EODMCF

sudo chown ubuntu /etc/dnsmasq.d

sudo systemctl restart dnsmasq
CHECKPOINT_URL="https://checkpoint-api.hashicorp.com/v1/check"
CONSUL_VERSION=$(curl -s "${CHECKPOINT_URL}"/consul | jq .current_version | tr -d '"')

cd /tmp/

echo "Fetching Consul version ${CONSUL_VERSION} ..."
curl -s https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_amd64.zip -o consul.zip
echo "Installing Consul version ${CONSUL_VERSION} ..."
unzip consul.zip
chmod +x consul
mv consul /usr/local/bin/consul

echo "Configuring Consul"
mkdir -p /var/lib/consul /etc/consul.d

cat << EOCCF >/etc/consul.d/agent.hcl
node_name = "$CONSUL_NODE_NAME"
client_addr =  "0.0.0.0"
recursors =  ["127.0.0.1"]
bootstrap =  false
datacenter = "dc1"
data_dir = "/var/lib/consul"
enable_syslog = true
log_level = "DEBUG"
retry_join = ["provider=aws tag_key=Name tag_value=basti"]
advertise_addr = "${LOCAL_IPV4}"
EOCCF

cat << EOCSU >/etc/systemd/system/consul.service
[Unit]
Description=consul agent
Requires=network-online.target
After=network-online.target
[Service]
LimitNOFILE=65536
Restart=on-failure
ExecStart=/usr/local/bin/consul agent -config-dir /etc/consul.d
ExecReload=/bin/kill -HUP $MAINPID
KillSignal=SIGINT
Type=notify
[Install]
WantedBy=multi-user.target
EOCSU

sudo systemctl daemon-reload
sudo systemctl start consul &

cat << EOCSU >/etc/consul.d/$CONSUL_SERVICE_NAME.json
{
 "service": {
   "name": "$CONSUL_SERVICE_NAME",
   "tags": ["$CONSUL_SERVICE_NAME"],
   "port": $SERVICE_PORT_NUMBER,
   "check": {
        "id": "$CONSUL_SERVICE_NAME-health",
       "name": "$CONSUL_SERVICE_NAME TCP health",
       "tcp": "${LOCAL_IPV4}:$SERVICE_PORT_NUMBER",
       "interval": "5s",
        "timeout": "1s"
       }
   }
}
EOCSU
consul reload
