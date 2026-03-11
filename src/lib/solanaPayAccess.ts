export const isSolanaPayEnabled = () =>
  String(import.meta.env.VITE_ENABLE_SOLANA_PAY_UI || "").toLowerCase() === "true";
