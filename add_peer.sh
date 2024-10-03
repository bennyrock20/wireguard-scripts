#!/bin/bash

# Variables (adjust according to your WireGuard setup)
SERVER_PUBLIC_IP="insert public ip here"
SERVER_PORT="51820"  # Change this to your WireGuard server port
SERVER_PUBLIC_KEY="insert ssh key here"
WG_CONFIG="/etc/wireguard/wg0.conf"  # Path to WireGuard server config file
CLIENTS_DIR="/etc/wireguard/clients"  # Directory to store client peers
NETWORK_PREFIX="10.20.20."  # Your subnet prefix for WireGuard clients

# Check for required tools
if ! command -v wg &> /dev/null || ! command -v wg-quick &> /dev/null; then
    echo "Error: WireGuard tools (wg, wg-quick) are not installed."
    exit 1
fi

# Backup server config
cp "$WG_CONFIG" "${WG_CONFIG}.bak"

# Function to find the next available IP
get_next_available_ip() {
  LAST_OCTET=2  # Start from .2 since .1 is likely the server

  while grep -q "${NETWORK_PREFIX}${LAST_OCTET}/32" "$WG_CONFIG"; do
    LAST_OCTET=$((LAST_OCTET + 1))
  done

  echo "${NETWORK_PREFIX}${LAST_OCTET}/32"
}

# Function to check if the IP already exists in the configuration
check_ip_exists() {
  if grep -q "$1" "$WG_CONFIG"; then
    echo "Error: IP address $1 already exists in the WireGuard configuration."
    exit 1  # Exit the script with an error
  fi
}

# Function to generate a new client config
generate_client_config() {
  CLIENT_NAME="$1"
  CLIENT_IP="$2"
  CLIENT_DIR="$CLIENTS_DIR/$CLIENT_NAME"
  
  # Create the client directory if it doesn't exist
  mkdir -p "$CLIENT_DIR"

  # Generate client keys and save them in specified locations
  CLIENT_PRIVATE_KEY=$(wg genkey)
  CLIENT_PUBLIC_KEY=$(echo "$CLIENT_PRIVATE_KEY" | wg pubkey)
  
  echo "$CLIENT_PRIVATE_KEY" > "$CLIENT_DIR/client.key"
  echo "$CLIENT_PUBLIC_KEY" > "$CLIENT_DIR/client.pub"
  
  chmod 600 "$CLIENT_DIR/client.key"

  # Create the client config file
  CLIENT_CONF="$CLIENT_DIR/$CLIENT_NAME.conf"
  cat << EOF > $CLIENT_CONF
[Interface]
PrivateKey = $(cat "$CLIENT_DIR/client.key")
Address = $CLIENT_IP
#DNS = 1.1.1.1

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $SERVER_PUBLIC_IP:$SERVER_PORT
AllowedIPs = 10.20.20.0/24  # Allow traffic within the subnet
PersistentKeepalive = 25
EOF

  chmod 600 "$CLIENT_CONF"

  # Add the client to WireGuard server using 'wg set' without restarting the interface
  wg set wg0 peer $CLIENT_PUBLIC_KEY allowed-ips $CLIENT_IP
  #wg syncconf wg0 <(wg-quick strip wg0)
  
  # Add the client to the server configuration file for persistence, with a newline between peers
  echo -e "\n### Client: $CLIENT_NAME ###" >> $WG_CONFIG
  echo "[Peer]" >> $WG_CONFIG
  echo "PublicKey = $CLIENT_PUBLIC_KEY" >> $WG_CONFIG
  echo "AllowedIPs = $CLIENT_IP" >> $WG_CONFIG
  echo "" >> $WG_CONFIG  # Adds a newline after each peer

  echo "Client $CLIENT_NAME added successfully!"
  echo "Private key saved in: $CLIENT_DIR/client.key"
  echo "Public key saved in: $CLIENT_DIR/client.pub"
  echo "Client config saved in: $CLIENT_CONF"
}

# Validate input for client name
read -p "Enter the peer name: " CLIENT_NAME
if [[ ! "$CLIENT_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "Error: Client name can only contain letters, numbers, underscores, and dashes."
    exit 1
fi

# Suggest next available IP
NEXT_IP=$(get_next_available_ip)
read -p "Enter the IP address (suggested: $NEXT_IP): " CLIENT_IP

# Use suggested IP if no input is provided
CLIENT_IP="${CLIENT_IP:-$NEXT_IP}"

# Check if the IP already exists in the configuration
check_ip_exists "$CLIENT_IP"

# Generate the client configuration
generate_client_config "$CLIENT_NAME" "$CLIENT_IP"
