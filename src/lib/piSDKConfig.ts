/**
 * Pi Network SDK Configuration and Error Handling
 * Handles Pi SDK environment issues and provides proper setup
 */

// Global polyfill for stellar-sdk/pi-backend compatibility
if (typeof global === 'undefined') {
  (window as any).global = window;
}

// Pi SDK configuration
export const PiSDKConfig = {
  // Development environment handling
  isDevelopment: import.meta.env.DEV,
  
  // Suppress specific warnings in development
  suppressWarnings: [
    'target origin provided',
    'postMessage',
    'SES Removing unpermitted intrinsics',
    'SDKMessaging instantiated'
  ],
  
  // Pi Network API configuration
  api: {
    key: import.meta.env.VITE_PI_API_KEY || "fudrvmlzm7ucqu94smlgeudrryccqxpymkr1vqk6nw0yoli8ikirbzrn9siv4hi9",
    sandbox: import.meta.env.VITE_PI_SANDBOX === "true"
  },
  
  // Wallet configuration
  wallet: {
    privateSeed: import.meta.env.VITE_PI_WALLET_PRIVATE_SEED || "SDZWK2Z4JA3KTQIGAEUSKWFLZBDILJAWLUNAUFHURFIF5BWNNH3PB5Y3"
  }
};

/**
 * Initialize Pi SDK warning suppression
 */
export const initializePiSDKWarnings = () => {
  if (!PiSDKConfig.isDevelopment) {
    return () => {}; // No-op in production
  }
  
  const originalWarn = console.warn;
  const originalError = console.error;
  
  // Suppress specific Pi SDK warnings in development
  console.warn = (...args) => {
    const message = args.join(' ');
    const shouldSuppress = PiSDKConfig.suppressWarnings.some(warning => 
      message.includes(warning)
    );
    
    if (!shouldSuppress) {
      originalWarn.apply(console, args);
    }
  };
  
  // Handle specific stellar-sdk errors
  console.error = (...args) => {
    const message = args.join(' ');
    
    // Suppress global undefined errors from stellar-sdk
    if (message.includes('global is not defined') && 
        message.includes('stellar-sdk')) {
      return; // Suppress this specific error
    }
    
    originalError.apply(console, args);
  };
  
  return () => {
    console.warn = originalWarn;
    console.error = originalError;
  };
};

/**
 * Check if Pi SDK is available
 */
export const isPiSDKAvailable = (): boolean => {
  return typeof window !== 'undefined' && 
         typeof (window as any).Pi !== 'undefined';
};

/**
 * Wait for Pi SDK to be available
 */
export const waitForPiSDK = (timeout = 10000): Promise<void> => {
  return new Promise((resolve, reject) => {
    if (isPiSDKAvailable()) {
      resolve();
      return;
    }
    
    const checkInterval = setInterval(() => {
      if (isPiSDKAvailable()) {
        clearInterval(checkInterval);
        resolve();
      }
    }, 100);
    
    setTimeout(() => {
      clearInterval(checkInterval);
      reject(new Error('Pi SDK not available within timeout'));
    }, timeout);
  });
};

/**
 * Get Pi Network environment info
 */
export const getPiEnvironment = () => {
  return {
    isPiBrowser: /PiBrowser/i.test(navigator.userAgent),
    isDevelopment: PiSDKConfig.isDevelopment,
    sdkAvailable: isPiSDKAvailable(),
    origin: window.location.origin,
    config: PiSDKConfig
  };
};
