// Pi Ad Network verification utilities
// These functions should be implemented in your backend for production use

export interface PiAdVerificationRequest {
  adId: string;
  userId: string;
  paymentId?: string;
}

export interface PiAdVerificationResponse {
  granted: boolean;
  mediator_ack_status: "granted" | "denied";
  error?: string;
}

/**
 * Verify a rewarded ad with Pi Platform API
 * This should be called from your backend server, not from the client
 * 
 * @param adId The ad ID returned from Pi.Ads.showAd()
 * @param userId The user ID who watched the ad
 * @returns Verification result from Pi Platform API
 */
export async function verifyRewardedAd(
  adId: string, 
  userId: string
): Promise<PiAdVerificationResponse> {
  try {
    // This should be called from your backend, not client-side
    // Example backend implementation:
    
    /*
    // Backend code (Node.js example):
    const response = await fetch('https://api.minepi.com/v2/payments/verify', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Key ${process.env.PI_API_KEY}`
      },
      body: JSON.stringify({
        ad_id: adId,
        user_id: userId
      })
    });
    
    const data = await response.json();
    
    return {
      granted: data.mediator_ack_status === "granted",
      mediator_ack_status: data.mediator_ack_status
    };
    */
    
    // For development/demo purposes, we'll simulate verification
    // In production, this MUST be done on your backend
    console.warn('Ad verification should be done on backend, not client-side!');
    
    // Simulate API call delay
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    // Simulate successful verification (90% success rate for demo)
    const isGranted = Math.random() > 0.1;
    
    return {
      granted: isGranted,
      mediator_ack_status: isGranted ? "granted" : "denied",
      error: isGranted ? undefined : "Ad verification failed"
    };
    
  } catch (error) {
    console.error('Ad verification error:', error);
    return {
      granted: false,
      mediator_ack_status: "denied",
      error: "Verification service unavailable"
    };
  }
}

/**
 * Check if user is in Pi Browser
 */
export function isPiBrowser(): boolean {
  return typeof window !== 'undefined' && 
         /PiBrowser/i.test(navigator.userAgent);
}

/**
 * Check if Pi Ad Network is available
 */
export async function isPiAdNetworkAvailable(): Promise<boolean> {
  if (!isPiBrowser() || !window.Pi?.Ads) {
    return false;
  }
  
  try {
    const features = await window.Pi.nativeFeaturesList();
    return features.includes("ad_network");
  } catch {
    return false;
  }
}

/**
 * Get Pi Browser version info
 */
export function getPiBrowserInfo(): { version?: string; isPiBrowser: boolean } {
  if (!isPiBrowser()) {
    return { isPiBrowser: false };
  }
  
  const userAgent = navigator.userAgent;
  const match = userAgent.match(/PiBrowser\/(\d+\.\d+\.\d+)/);
  
  return {
    isPiBrowser: true,
    version: match ? match[1] : undefined
  };
}
