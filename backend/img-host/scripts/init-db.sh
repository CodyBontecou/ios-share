#!/bin/bash

# Database initialization script for ImageHost
# This script helps set up the D1 database for local development or production

set -e

echo "ImageHost Database Initialization"
echo "=================================="
echo ""

# Check if wrangler is installed
if ! command -v wrangler &> /dev/null; then
    echo "Error: wrangler CLI is not installed"
    echo "Install it with: npm install -g wrangler"
    exit 1
fi

# Ask for environment
read -p "Initialize for [local/production]? (default: local): " ENV
ENV=${ENV:-local}

DATABASE_NAME="imagehost"

if [ "$ENV" = "production" ]; then
    echo ""
    echo "Production Setup"
    echo "================"
    echo ""

    # Check if database exists
    echo "Checking if database exists..."
    if wrangler d1 list | grep -q "$DATABASE_NAME"; then
        echo "Database '$DATABASE_NAME' already exists"
        read -p "Do you want to continue and run migrations? (yes/no): " CONTINUE
        if [ "$CONTINUE" != "yes" ]; then
            echo "Aborted."
            exit 0
        fi
    else
        echo "Creating database '$DATABASE_NAME'..."
        wrangler d1 create "$DATABASE_NAME"
        echo ""
        echo "IMPORTANT: Update wrangler.toml with the database_id from above!"
        echo ""
        read -p "Have you updated wrangler.toml? (yes/no): " UPDATED
        if [ "$UPDATED" != "yes" ]; then
            echo "Please update wrangler.toml and run this script again"
            exit 0
        fi
    fi

    echo ""
    echo "Running migrations..."
    wrangler d1 execute "$DATABASE_NAME" --file=./migrations/0001_initial_schema.sql

    echo ""
    echo "Verifying tables..."
    wrangler d1 execute "$DATABASE_NAME" --command="SELECT name FROM sqlite_master WHERE type='table';"

elif [ "$ENV" = "local" ]; then
    echo ""
    echo "Local Development Setup"
    echo "======================="
    echo ""

    echo "Running migrations locally..."
    wrangler d1 execute "$DATABASE_NAME" --local --file=./migrations/0001_initial_schema.sql

    echo ""
    echo "Verifying tables..."
    wrangler d1 execute "$DATABASE_NAME" --local --command="SELECT name FROM sqlite_master WHERE type='table';"

    echo ""
    read -p "Create a test user? (yes/no): " CREATE_TEST
    if [ "$CREATE_TEST" = "yes" ]; then
        TEST_EMAIL="test@example.com"
        TEST_PASSWORD="test123"
        # Simple hash for testing only (not production-ready)
        TEST_PASSWORD_HASH=$(echo -n "$TEST_PASSWORD" | shasum -a 256 | cut -d' ' -f1)
        TEST_TOKEN=$(uuidgen | tr '[:upper:]' '[:lower:]')
        TEST_USER_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
        TIMESTAMP=$(date +%s)000

        echo "Creating test user..."
        wrangler d1 execute "$DATABASE_NAME" --local --command="
        INSERT INTO users (id, email, password_hash, created_at, subscription_tier, api_token, storage_limit_bytes)
        VALUES ('$TEST_USER_ID', '$TEST_EMAIL', '$TEST_PASSWORD_HASH', $TIMESTAMP, 'free', '$TEST_TOKEN', 104857600);
        "

        echo "Creating test subscription..."
        TEST_SUB_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
        wrangler d1 execute "$DATABASE_NAME" --local --command="
        INSERT INTO subscriptions (id, user_id, tier, status, cancel_at_period_end, created_at, updated_at)
        VALUES ('$TEST_SUB_ID', '$TEST_USER_ID', 'free', 'active', 0, $TIMESTAMP, $TIMESTAMP);
        "

        echo ""
        echo "Test User Created!"
        echo "=================="
        echo "Email: $TEST_EMAIL"
        echo "Password: $TEST_PASSWORD"
        echo "API Token: $TEST_TOKEN"
        echo ""
        echo "You can use this to test the API endpoints:"
        echo "curl -H 'Authorization: Bearer $TEST_TOKEN' http://localhost:8787/user"
    fi
else
    echo "Invalid environment. Choose 'local' or 'production'"
    exit 1
fi

echo ""
echo "Database initialization complete!"
echo ""
echo "Next steps:"
echo "  - For local dev: npm run dev"
echo "  - For production: wrangler deploy"
