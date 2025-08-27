#!/bin/bash

# Galaxy Operator - GPG Key Generation Script
# This script helps generate GPG keys for Galaxy collection and container signing

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DEFAULT_KEY_TYPE="RSA"
DEFAULT_KEY_LENGTH="4096"
DEFAULT_EXPIRE="0"  # Never expire
DEFAULT_NAME="Galaxy Signing Service"
DEFAULT_EMAIL="galaxy-signing@example.com"

echo -e "${BLUE}Galaxy Operator - GPG Key Generation Script${NC}"
echo "=============================================="
echo ""

# Check if GPG is installed
if ! command -v gpg &> /dev/null; then
    echo -e "${RED}Error: GPG is not installed. Please install GPG first.${NC}"
    echo "On Ubuntu/Debian: sudo apt-get install gnupg"
    echo "On RHEL/CentOS: sudo yum install gnupg2"
    echo "On macOS: brew install gnupg"
    exit 1
fi

echo -e "${GREEN}GPG is installed: $(gpg --version | head -n1)${NC}"
echo ""

# Function to prompt for input with default
prompt_with_default() {
    local prompt="$1"
    local default="$2"
    local result

    read -p "$prompt [$default]: " result
    echo "${result:-$default}"
}

# Function to prompt for yes/no
prompt_yes_no() {
    local prompt="$1"
    local default="$2"
    local result

    while true; do
        read -p "$prompt [y/N]: " result
        result=${result:-$default}
        case $result in
            [Yy]* ) echo "yes"; break;;
            [Nn]* ) echo "no"; break;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

echo -e "${YELLOW}This script will generate a GPG key pair for Galaxy signing.${NC}"
echo "You will be prompted for key details."
echo ""

# Collect key information
KEY_TYPE=$(prompt_with_default "Key type" "$DEFAULT_KEY_TYPE")
KEY_LENGTH=$(prompt_with_default "Key length (bits)" "$DEFAULT_KEY_LENGTH")
EXPIRE=$(prompt_with_default "Key expiration (0 = never expire)" "$DEFAULT_EXPIRE")
REAL_NAME=$(prompt_with_default "Real name" "$DEFAULT_NAME")
EMAIL=$(prompt_with_default "Email address" "$DEFAULT_EMAIL")

echo ""
echo -e "${YELLOW}Do you want to set a passphrase for this key?${NC}"
echo "Note: For automated signing, you may want to use no passphrase."
echo "However, this reduces security. Choose based on your security requirements."
USE_PASSPHRASE=$(prompt_yes_no "Use passphrase" "no")

echo ""
echo -e "${BLUE}Key Configuration Summary:${NC}"
echo "========================="
echo "Key Type: $KEY_TYPE"
echo "Key Length: $KEY_LENGTH bits"
echo "Expiration: $([ "$EXPIRE" = "0" ] && echo "Never" || echo "$EXPIRE")"
echo "Name: $REAL_NAME"
echo "Email: $EMAIL"
echo "Passphrase: $([ "$USE_PASSPHRASE" = "yes" ] && echo "Yes" || echo "No")"
echo ""

CONFIRM=$(prompt_yes_no "Generate key with these settings" "yes")
if [ "$CONFIRM" = "no" ]; then
    echo "Key generation cancelled."
    exit 0
fi

# Create GPG batch file
BATCH_FILE=$(mktemp)
cat > "$BATCH_FILE" << EOF
%echo Generating Galaxy signing key
Key-Type: $KEY_TYPE
Key-Length: $KEY_LENGTH
Subkey-Type: $KEY_TYPE
Subkey-Length: $KEY_LENGTH
Name-Real: $REAL_NAME
Name-Email: $EMAIL
Expire-Date: $EXPIRE
EOF

if [ "$USE_PASSPHRASE" = "no" ]; then
    echo "%no-protection" >> "$BATCH_FILE"
fi

echo "%commit" >> "$BATCH_FILE"
echo "%echo done" >> "$BATCH_FILE"

echo ""
echo -e "${YELLOW}Generating GPG key... This may take a few minutes.${NC}"
echo "Move your mouse or type on the keyboard to generate entropy."
echo ""

# Generate the key
if gpg --batch --generate-key "$BATCH_FILE"; then
    echo ""
    echo -e "${GREEN}✓ GPG key generated successfully!${NC}"
else
    echo -e "${RED}✗ Failed to generate GPG key.${NC}"
    rm -f "$BATCH_FILE"
    exit 1
fi

# Clean up batch file
rm -f "$BATCH_FILE"

# Get the key ID
KEY_ID=$(gpg --list-secret-keys --with-colons "$EMAIL" | awk -F: '/^sec:/ {print $5}' | head -n1)

if [ -z "$KEY_ID" ]; then
    echo -e "${RED}Error: Could not find the generated key.${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}Key Information:${NC}"
echo "================"
echo "Key ID: $KEY_ID"

# Get fingerprint
FINGERPRINT=$(gpg --fingerprint "$KEY_ID" | grep -A1 "pub" | tail -n1 | tr -d ' ')
echo "Fingerprint: $FINGERPRINT"

echo ""
echo -e "${YELLOW}Exporting private key...${NC}"

# Export private key
PRIVATE_KEY_FILE="signing_service.gpg"
if gpg --armor --export-secret-keys "$KEY_ID" > "$PRIVATE_KEY_FILE"; then
    echo -e "${GREEN}✓ Private key exported to: $PRIVATE_KEY_FILE${NC}"
else
    echo -e "${RED}✗ Failed to export private key.${NC}"
    exit 1
fi

# Export public key
PUBLIC_KEY_FILE="signing_service_public.gpg"
if gpg --armor --export "$KEY_ID" > "$PUBLIC_KEY_FILE"; then
    echo -e "${GREEN}✓ Public key exported to: $PUBLIC_KEY_FILE${NC}"
else
    echo -e "${RED}✗ Failed to export public key.${NC}"
fi

echo ""
echo -e "${GREEN}=== Key Generation Complete! ===${NC}"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo "1. Create a Kubernetes secret with the private key:"
echo "   kubectl create secret generic signing-galaxy \\"
echo "     --from-file=signing_service.gpg=./$PRIVATE_KEY_FILE \\"
echo "     --namespace=your-namespace"
echo ""
echo "2. Create the signing scripts ConfigMap (see documentation)"
echo ""
echo "3. Configure your Galaxy CR with:"
echo "   signing_secret: \"signing-galaxy\""
echo "   signing_scripts_configmap: \"signing-scripts\""
echo ""
echo -e "${YELLOW}Security Notes:${NC}"
echo "• Store the private key file ($PRIVATE_KEY_FILE) securely"
echo "• Consider encrypting the private key file when not in use"
echo "• Back up your keys in a secure location"
echo "• Share the public key file ($PUBLIC_KEY_FILE) with users who need to verify signatures"
echo ""
echo -e "${BLUE}Key Details for Reference:${NC}"
echo "Key ID: $KEY_ID"
echo "Fingerprint: $FINGERPRINT"
echo "Email: $EMAIL"
echo ""
echo "For more information, see the Galaxy Operator signing documentation."
