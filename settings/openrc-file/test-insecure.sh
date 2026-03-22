#!/usr/bin/env bash
# test-insecure.sh — Dummy openrc for testing (no real credentials, has OS_INSECURE)
export OS_AUTH_URL="https://openstack.internal:5000/v3"
export OS_USERNAME="test-user"
export OS_PASSWORD="test-password"
export OS_PROJECT_NAME="test-project"
export OS_USER_DOMAIN_NAME="Default"
export OS_PROJECT_DOMAIN_NAME="Default"
export OS_IDENTITY_API_VERSION="3"
export OS_INSECURE="true"   # Method A: env var — required for self-signed certs
# Note: openstack --insecure is required for self-signed certs
