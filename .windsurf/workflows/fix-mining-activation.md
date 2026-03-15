---
description: How to fix mining activation after watching ads
---

# Fix Mining Activation After Watching Ads

## Issue Description
Mining is not activating after watching ads in Pi Browser. Users complete the ad verification but mining doesn't start automatically.

## Root Causes Identified

### 1. Pi Browser Detection Issues
- **Problem**: `isPiBrowserUserAgent()` function not detecting all Pi Browser variants
- **Impact**: Database function rejects mining session start due to `p_pi_browser_used` requirement

### 2. Ad Verification Timing Issues
- **Problem**: localStorage cleanup happening too quickly (2 minutes)
- **Impact**: Mining activation window expires before session can start

### 3. Missing Ad ID Persistence
- **Problem**: Only storing timestamp, not ad ID
- **Impact**: Debugging difficulties and potential verification issues

## Applied Fixes

### ✅ 1. Enhanced Pi Browser Detection
**File**: `src/lib/appSecurity.ts`
- Added comprehensive Pi Browser detection patterns
- Includes Kina browser, Android/iOS Pi variants
- Fallback to `window.Pi` detection

### ✅ 2. Improved Ad Reward Detection
**File**: `src/pages/MiningPage.tsx`
- Extended time window from 2 to 5 minutes
- Added ad ID tracking for better debugging
- Delayed localStorage cleanup (10 seconds)
- Enhanced logging for troubleshooting

### ✅ 3. Enhanced Pi Environment Detection
**File**: `src/pages/MiningPage.tsx`
- More lenient Pi environment detection
- Multiple fallback checks for Pi SDK
- Better debugging output

### ✅ 4. Improved Ad Storage
**File**: `src/pages/PiAdsPage.tsx`
- Store both timestamp and ad ID
- Added debugging logs
- Better navigation handling

## Database Requirements
The `start_mining_session` function requires:
- `p_pi_browser_used = true`
- `p_ad_verified = true`

## Testing Checklist
- [ ] Test in Pi Browser with different user agents
- [ ] Test ad flow completion and mining activation
- [ ] Check browser console for debugging logs
- [ ] Verify localStorage persistence
- [ ] Test mining session start after ad completion

## Debugging Commands
```javascript
// Check Pi Browser detection
console.log('Pi Browser detected:', isPiBrowserUserAgent());
console.log('Pi SDK available:', Boolean(window.Pi));

// Check ad reward storage
console.log('Ad reward timestamp:', localStorage.getItem('pi_ad_rewarded_at'));
console.log('Ad reward ID:', localStorage.getItem('pi_ad_rewarded_id'));
```

## Common Issues & Solutions

### Issue: "Pi Browser is required to start mining"
**Solution**: Enhanced detection patterns should resolve this

### Issue: "Rewarded ad verification is required to start mining"
**Solution**: Extended time window and better persistence

### Issue: Mining doesn't auto-start after ad
**Solution**: Delayed cleanup and improved detection logic
