export function generateOpenPayAccountNumber(userId: string) {
  return `OP${userId.replace(/-/g, "").toUpperCase()}`;
}

export function isPlaceholderOpenPayAccount(accountName?: string | null, accountUsername?: string | null) {
  const normalizedName = String(accountName || "").trim().toLowerCase();
  const normalizedUsername = String(accountUsername || "").trim().toLowerCase();
  return normalizedName === "openpay user" && normalizedUsername === "openpay";
}

