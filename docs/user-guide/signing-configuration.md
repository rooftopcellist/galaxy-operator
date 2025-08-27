# Signing Configuration

Galaxy supports signing of both Ansible Collections and Container Images to ensure content authenticity and integrity. This guide explains how to configure collection and container signing on the Galaxy Custom Resource (CR).

## Overview

Galaxy uses GPG (GNU Privacy Guard) for collection signing and container signing tools like `skopeo` for container image signing. The signing process requires:

1. **Signing Secret** - Contains the GPG private key used for signing
2. **Signing Scripts ConfigMap** - Contains the shell scripts that perform the actual signing operations
3. **Galaxy CR Configuration** - References to the secret and configmap in your Galaxy deployment

## Prerequisites

Before configuring signing, ensure you have:

- A Kubernetes cluster with the Galaxy Operator installed
- `kubectl` access to your cluster
- GPG tools installed locally for key generation
- Understanding of GPG key management and security practices

## Step 1: Generate GPG Keys

First, generate a GPG key pair that will be used for signing:

```bash
# Generate a new GPG key (follow the interactive prompts)
gpg --full-generate-key

# Choose:
# - Key type: RSA and RSA (default)
# - Key size: 4096 bits (recommended)
# - Expiration: Set according to your security policy
# - Real name: Your organization/service name
# - Email: Contact email for the signing key
# - Passphrase: Choose a strong passphrase (or leave empty for automation)
```

After generation, export the private key:

```bash
# List your keys to get the key ID
gpg --list-secret-keys --keyid-format LONG

# Export the private key (replace KEY_ID with your actual key ID)
gpg --armor --export-secret-keys KEY_ID > signing_service.gpg

# Get the key fingerprint (needed for configuration)
gpg --fingerprint KEY_ID
```

**Security Note**: Store your GPG private key securely and follow your organization's key management policies.

## Step 2: Create the Signing Secret

Create a Kubernetes secret containing your GPG private key:

```yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: signing-galaxy
  namespace: <your-namespace>
stringData:
  signing_service.gpg: |
    -----BEGIN PGP PRIVATE KEY BLOCK-----
    
    [Your GPG private key content here]
    
    -----END PGP PRIVATE KEY BLOCK-----
```

Apply the secret:

```bash
kubectl apply -f signing-secret.yaml
```

Alternatively, create the secret directly from your exported key file:

```bash
kubectl create secret generic signing-galaxy \
  --from-file=signing_service.gpg=./signing_service.gpg \
  --namespace=<your-namespace>
```

## Step 3: Create the Signing Scripts ConfigMap

Create a ConfigMap with the signing scripts. The Galaxy operator expects two scripts:

- `collection_sign.sh` - For signing Ansible Collections
- `container_sign.sh` - For signing Container Images

```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: signing-scripts
  namespace: <your-namespace>
data:
  collection_sign.sh: |
    #!/usr/bin/env bash
    
    FILE_PATH=$1
    SIGNATURE_PATH=$1.asc
    
    ADMIN_ID="$PULP_SIGNING_KEY_FINGERPRINT"
    PASSWORD="password"  # Set to your GPG key passphrase or empty string
    
    # Create a detached signature
    gpg --quiet --batch --pinentry-mode loopback --yes --passphrase \
      $PASSWORD --homedir /var/lib/pulp/.gnupg --detach-sign --default-key $ADMIN_ID \
      --armor --output $SIGNATURE_PATH $FILE_PATH
    
    # Check the exit status
    STATUS=$?
    if [ $STATUS -eq 0 ]; then
      echo {\"file\": \"$FILE_PATH\", \"signature\": \"$SIGNATURE_PATH\"}
    else
      exit $STATUS
    fi
    
  container_sign.sh: |
    #!/usr/bin/env bash
    
    # galaxy_container SigningService will pass the next 4 variables to the script
    MANIFEST_PATH=$1
    FINGERPRINT="$PULP_SIGNING_KEY_FINGERPRINT"
    IMAGE_REFERENCE="$REFERENCE"
    SIGNATURE_PATH="$SIG_PATH"
    
    # Create container signature using skopeo
    skopeo standalone-sign \
      $MANIFEST_PATH \
      $IMAGE_REFERENCE \
      $FINGERPRINT \
      --output $SIGNATURE_PATH
    
    # Optionally pass the passphrase to the key if password protected
    # --passphrase-file /path/to/key_password.txt
    
    # Check the exit status
    STATUS=$?
    if [ $STATUS -eq 0 ]; then
      echo {\"signature_path\": \"$SIGNATURE_PATH\"}
    else
      exit $STATUS
    fi
```

Apply the ConfigMap:

```bash
kubectl apply -f signing-scripts-configmap.yaml
```

**Important Notes**:
- Replace `"password"` in the collection signing script with your actual GPG key passphrase, or use an empty string `""` if your key has no passphrase
- The scripts assume standard paths and environment variables that the Galaxy operator provides
- Both scripts must be executable and return proper JSON output on success

## Step 4: Configure the Galaxy CR

Add the signing configuration to your Galaxy Custom Resource:

```yaml
apiVersion: galaxy.ansible.com/v1beta1
kind: Galaxy
metadata:
  name: example-galaxy
  namespace: <your-namespace>
spec:
  # ... other configuration options ...

  # Signing configuration
  signing_secret: "signing-galaxy"
  signing_scripts_configmap: "signing-scripts"

  # ... rest of your configuration ...
```

The Galaxy operator will automatically:
- Mount the GPG private key from the secret
- Mount the signing scripts from the configmap
- Configure the signing services in Galaxy
- Set up the necessary environment variables

## Step 5: Apply the Configuration

Apply your updated Galaxy CR:

```bash
kubectl apply -f galaxy-cr.yaml
```

The Galaxy operator will restart the necessary pods to apply the signing configuration.

## Environment Variables

The Galaxy operator automatically sets these environment variables for the signing scripts:

- `PULP_SIGNING_KEY_FINGERPRINT` - The fingerprint of your GPG key
- `COLLECTION_SIGNING_SERVICE` - Name of the collection signing service
- `CONTAINER_SIGNING_SERVICE` - Name of the container signing service
- `REFERENCE` - Container image reference (for container signing)
- `SIG_PATH` - Path where the signature should be written (for container signing)

## Verification

After deploying your Galaxy instance with signing configured, verify that signing is working:

### 1. Check Signing Services

```bash
# Get the Galaxy admin password
GALAXY_ADMIN_PASSWORD=$(kubectl get secret/<galaxy-name>-admin-password -o jsonpath='{.data.password}' | base64 -d)

# Check signing services via API
kubectl exec deployment/<galaxy-name>-api -- curl -u admin:$GALAXY_ADMIN_PASSWORD \
  -sL localhost:24817/galaxy/api/v3/signing-services/
```

You should see two signing services: one for collections and one for containers.

### 2. Verify GPG Key Import

```bash
# Check if GPG key is available in the API pod
kubectl exec deployment/<galaxy-name>-api -- gpg --list-keys

# Check if GPG key is available in the worker pod
kubectl exec deployment/<galaxy-name>-worker -- gpg --list-keys
```

### 3. Test Collection Signing

Upload a collection to Galaxy and verify it gets signed automatically, or manually trigger signing through the Galaxy API.

## Troubleshooting

### Common Issues

**1. GPG Key Not Found**
- Verify the secret contains the correct GPG private key
- Check that the key fingerprint matches the `PULP_SIGNING_KEY_FINGERPRINT` environment variable
- Ensure the GPG key is properly formatted in the secret

**2. Signing Scripts Not Executable**
- The ConfigMap scripts are automatically made executable by the operator
- Check pod logs for script execution errors

**3. Permission Issues**
- Ensure the Galaxy pods have proper permissions to access the mounted secrets and configmaps
- Check that the GPG home directory has correct permissions

**4. Passphrase Issues**
- If using a passphrase-protected GPG key, ensure the passphrase is correctly set in the signing script
- Consider using a key without a passphrase for automated signing

### Debugging Steps

1. **Check Pod Logs**:
   ```bash
   kubectl logs deployment/<galaxy-name>-api
   kubectl logs deployment/<galaxy-name>-worker
   ```

2. **Verify Mounts**:
   ```bash
   kubectl exec deployment/<galaxy-name>-api -- ls -la /etc/pulp/keys/
   kubectl exec deployment/<galaxy-name>-api -- ls -la /var/lib/pulp/scripts/
   ```

3. **Test GPG Operations**:
   ```bash
   kubectl exec deployment/<galaxy-name>-api -- gpg --list-secret-keys
   ```

4. **Check Signing Service Configuration**:
   ```bash
   kubectl exec deployment/<galaxy-name>-api -- cat /etc/pulp/settings.py | grep -i sign
   ```

## Security Considerations

- **Key Management**: Store GPG private keys securely and rotate them according to your security policy
- **Access Control**: Limit access to the signing secret using Kubernetes RBAC
- **Monitoring**: Monitor signing operations and set up alerts for signing failures
- **Backup**: Ensure you have secure backups of your signing keys
- **Passphrase**: Consider the trade-offs between security (using passphrases) and automation (passwordless keys)

## Advanced Configuration

### Custom Signing Scripts

You can customize the signing scripts in the ConfigMap to meet your specific requirements:

- Add additional validation steps
- Integrate with external signing services
- Implement custom logging or monitoring
- Add support for different signature formats

### Multiple Signing Keys

For organizations requiring multiple signing keys (e.g., different keys for different content types), you can:

- Create multiple secrets with different GPG keys
- Modify the signing scripts to select the appropriate key based on content metadata
- Use different Galaxy instances with different signing configurations

### Integration with External Key Management

For enterprise environments, consider integrating with external key management systems:

- Hardware Security Modules (HSMs)
- Cloud-based key management services
- Enterprise PKI systems

This may require custom signing scripts that interface with your key management infrastructure.

## Related Documentation

- [Database Configuration](database-configuration.md)
- [Galaxy API Documentation](../roles/galaxy-api.md)
- [Galaxy Worker Documentation](../roles/galaxy-worker.md)
