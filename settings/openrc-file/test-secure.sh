#!/usr/bin/env bash
# test-secure.sh — Dummy openrc for testing (no real credentials, no insecure flag)
export OS_AUTH_URL="http://127.0.0.1:5000/v3"
export OS_USERNAME="test-user"
export OS_PASSWORD="test-password"
export OS_PROJECT_NAME="test-project"
export OS_USER_DOMAIN_NAME="Default"
export OS_PROJECT_DOMAIN_NAME="Default"
export OS_IDENTITY_API_VERSION="3"
# Secure endpoint — no insecure flag needed
