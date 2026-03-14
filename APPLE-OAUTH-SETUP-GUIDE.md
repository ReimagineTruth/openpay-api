# Apple OAuth Setup Guide for OpenPay

## Overview
This guide helps you set up Apple Sign In for your OpenPay application using Supabase authentication.

## Prerequisites
- Apple Developer Account ($99/year)
- Xcode (for generating certificates)
- Supabase project access

## Step 1: Configure Apple Developer Account

### 1.1 Create App ID
1. Go to [Apple Developer Portal](https://developer.apple.com/)
2. Navigate to **Certificates, Identifiers & Profiles**
3. Click **Identifiers** → **+**
4. Select **App IDs** and click **Continue**
5. Enter **Description**: "OpenPay App"
6. Enter **Bundle ID**: `com.openpay.app` (unique)
7. Enable **Sign In with Apple**
8. Click **Continue** → **Register**

### 1.2 Create Service ID
1. Go to **Identifiers** → **+**
2. Select **Services IDs** and click **Continue**
3. Enter **Description**: "OpenPay Web Service"
4. Enter **Identifier**: `com.openpay.web`
5. Click **Continue** → **Register**

### 1.3 Configure Service ID
1. Click on your newly created Service ID
2. Check **Sign In with Apple**
3. Click **Configure**
4. Add your redirect URIs:
   - Development: `http://localhost:8081/auth/callback`
   - Production: `https://yourdomain.com/auth/callback`
5. Click **Done** → **Save**

### 1.4 Create Private Key
1. Go to **Keys** → **+**
2. Enter **Key Name**: "OpenPay Auth Key"
3. Check **Sign In with Apple**
4. Click **Continue**
5. Select your primary App ID
6. Click **Register**
7. **Download the key** (.p8 file) - you can only download it once!
8. Note the **Key ID** (shown in the portal)

## Step 2: Generate Client Secret

### Option A: Using Supabase Dashboard (Recommended)
1. Go to your Supabase project
2. Navigate to **Authentication** → **Providers**
3. Find **Apple** and click **Setup**
4. Enter:
   - **Client ID**: Your Service ID (`com.openpay.web`)
   - **Client Secret**: Generate using your private key
   - **Team ID**: Your Apple Developer Team ID

### Option B: Manual JWT Generation
Create a JWT using your private key:

```bash
# Install required packages
npm install -g jsonwebtoken

# Generate JWT (replace values)
node -e "
const jwt = require('jsonwebtoken');
const fs = require('fs');

const privateKey = fs.readFileSync('path/to/your/AuthKey.p8', 'utf8');
const teamId = 'YOUR_TEAM_ID';
const keyId = 'YOUR_KEY_ID';
const clientId = 'com.openpay.web';

const token = jwt.sign(
  {
    iss: teamId,
    iat: Math.floor(Date.now() / 1000),
    exp: Math.floor(Date.now() / 1000) + (180 * 24), // 6 months
    aud: 'https://appleid.apple.com',
    sub: clientId
  },
  privateKey,
  { algorithm: 'ES256', keyid: keyId }
);

console.log(token);
"
```

## Step 3: Configure Supabase

### 3.1 Using SQL
Run the SQL file in your Supabase SQL Editor:

```sql
-- Update with your actual credentials
UPDATE auth.providers 
SET config = '{
  "client_id": "com.openpay.web",
  "client_secret": "YOUR_GENERATED_JWT_TOKEN", 
  "redirect_uri": "http://localhost:8081/auth/callback",
  "scope": "name email"
}'
WHERE name = 'apple';
```

### 3.2 Using Dashboard
1. Go to **Authentication** → **Providers**
2. Enable **Apple**
3. Fill in:
   - **Apple Client ID**: `com.openpay.web`
   - **Apple Client Secret**: Your JWT token
   - **Apple Team ID**: Your Team ID
   - **Redirect URL**: `http://localhost:8081/auth/callback`

## Step 4: Test Configuration

### 4.1 Check Provider Status
```sql
SELECT * FROM auth.providers WHERE name = 'apple';
```

### 4.2 Test Sign In Flow
1. Go to `http://localhost:8081/sign-in`
2. Click "Sign in with Apple"
3. Should redirect to Apple authentication
4. After successful auth, redirect to dashboard

## Step 5: Production Setup

### 5.1 Update Redirect URI
```sql
UPDATE auth.providers 
SET config = '{
  "client_id": "com.openpay.web",
  "client_secret": "YOUR_JWT_TOKEN", 
  "redirect_uri": "https://yourdomain.com/auth/callback",
  "scope": "name email"
}'
WHERE name = 'apple';
```

### 5.2 Add Production Domain to Apple
1. Go back to Apple Developer Portal
2. Edit your Service ID
3. Add production redirect URI: `https://yourdomain.com/auth/callback`

## Troubleshooting

### Common Issues

1. **"invalid_client" Error**
   - Check Client ID matches Service ID
   - Verify JWT token is valid and not expired
   - Ensure private key is correct

2. **"redirect_uri_mismatch" Error**
   - Verify redirect URI matches exactly
   - Check both Supabase and Apple configurations

3. **404 After Authentication**
   - Ensure `/auth/callback` route exists in your app
   - Check auth state listener is implemented

### Debug Queries
```sql
-- Check OAuth logs
SELECT * FROM auth.oauth_logs WHERE provider = 'apple' ORDER BY created_at DESC;

-- Check Apple users
SELECT * FROM apple_users ORDER BY created_at DESC;

-- Check provider config
SELECT * FROM auth.providers WHERE name = 'apple';
```

## Security Notes

1. **JWT Token**: Valid for 6 months, set reminder to renew
2. **Private Key**: Store securely, never commit to git
3. **Redirect URIs**: Use HTTPS in production
4. **Scope**: Only request necessary permissions

## Support

- Apple Developer Documentation: https://developer.apple.com/documentation/signinwithapple
- Supabase Auth Guide: https://supabase.com/docs/guides/auth/social-login/auth-apple
- OpenPay Support: Check your project documentation
