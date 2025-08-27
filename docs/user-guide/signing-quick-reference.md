# Signing Configuration Quick Reference

This is a quick reference for setting up collection and container signing in Galaxy. For detailed instructions, see [signing-configuration.md](signing-configuration.md).

## Prerequisites Checklist

- [ ] Kubernetes cluster with Galaxy Operator installed
- [ ] `kubectl` access to your cluster
- [ ] GPG tools installed locally
- [ ] Generated GPG key pair

## Quick Setup Steps

### 1. Generate GPG Key
```bash
# Generate key
gpg --full-generate-key

# Export private key
gpg --armor --export-secret-keys YOUR_KEY_ID > signing_service.gpg

# Get fingerprint (save this for verification)
gpg --fingerprint YOUR_KEY_ID
```

### 2. Create Resources
```bash
# Create signing secret
kubectl create secret generic signing-galaxy \
  --from-file=signing_service.gpg=./signing_service.gpg \
  --namespace=your-namespace

# Apply signing scripts configmap
kubectl apply -f signing-scripts-configmap.yaml

# Apply Galaxy CR with signing config
kubectl apply -f galaxy-cr.yaml
```

### 3. Verify Setup
```bash
# Check signing services
ADMIN_PASSWORD=$(kubectl get secret/galaxy-admin-password -o jsonpath='{.data.password}' | base64 -d)
kubectl exec deployment/galaxy-api -- curl -u admin:$ADMIN_PASSWORD \
  -sL localhost:24817/galaxy/api/v3/signing-services/

# Verify GPG keys
kubectl exec deployment/galaxy-api -- gpg --list-keys
kubectl exec deployment/galaxy-worker -- gpg --list-keys
```

## Required Galaxy CR Fields

```yaml
spec:
  signing_secret: "signing-galaxy"                    # Name of secret with GPG key
  signing_scripts_configmap: "signing-scripts"       # Name of configmap with scripts
```

## Required Secret Structure

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: signing-galaxy
stringData:
  signing_service.gpg: |    # Must be exactly this key name
    -----BEGIN PGP PRIVATE KEY BLOCK-----
    [Your GPG private key content]
    -----END PGP PRIVATE KEY BLOCK-----
```

## Required ConfigMap Structure

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: signing-scripts
data:
  collection_sign.sh: |     # Must be exactly this key name
    #!/usr/bin/env bash
    [Collection signing script]
  container_sign.sh: |      # Must be exactly this key name
    #!/usr/bin/env bash
    [Container signing script]
```

## Environment Variables (Auto-configured)

The Galaxy operator automatically sets these variables:

- `PULP_SIGNING_KEY_FINGERPRINT` - Your GPG key fingerprint
- `COLLECTION_SIGNING_SERVICE` - Collection signing service name
- `CONTAINER_SIGNING_SERVICE` - Container signing service name
- `REFERENCE` - Container image reference (container signing)
- `SIG_PATH` - Signature output path (container signing)

## Common Issues & Quick Fixes

| Issue | Quick Fix |
|-------|-----------|
| GPG key not found | Verify secret name matches `signing_secret` in CR |
| Scripts not executable | Check ConfigMap key names: `collection_sign.sh`, `container_sign.sh` |
| Passphrase errors | Set correct passphrase in script or use passwordless key |
| Permission denied | Check pod logs and verify secret/configmap mounts |
| No signing services | Wait for pods to restart after applying CR changes |

## Verification Commands

```bash
# Check pod status
kubectl get pods -l app.kubernetes.io/name=galaxy

# Check signing services count (should be 2)
kubectl exec deployment/galaxy-api -- curl -u admin:$ADMIN_PASSWORD \
  -sL localhost:24817/galaxy/api/v3/signing-services/ | jq .count

# Check GPG key in keyring
kubectl exec deployment/galaxy-api -- gpg -k YOUR_EMAIL

# View pod logs
kubectl logs deployment/galaxy-api
kubectl logs deployment/galaxy-worker
```

## File Locations in Pods

| Resource | Mount Path |
|----------|------------|
| GPG private key | `/etc/pulp/keys/signing_service.gpg` |
| Collection signing script | `/var/lib/pulp/scripts/collection_sign.sh` |
| Container signing script | `/var/lib/pulp/scripts/container_sign.sh` |
| GPG home directory | `/var/lib/pulp/.gnupg` |

## Security Reminders

- [ ] Use strong GPG key (4096 bits recommended)
- [ ] Secure your GPG private key
- [ ] Limit access to signing secret with RBAC
- [ ] Monitor signing operations
- [ ] Plan for key rotation
- [ ] Backup your signing keys securely

## Example Files

See complete examples in:
- [signing-setup-example.yaml](examples/signing-setup-example.yaml)
- [signing-configuration.md](signing-configuration.md)

## Need Help?

1. Check the [troubleshooting section](signing-configuration.md#troubleshooting) in the full documentation
2. Review pod logs for specific error messages
3. Verify all resource names match between CR and actual resources
4. Ensure GPG key format is correct (armored/ASCII format)
5. Test GPG operations manually in the pods
