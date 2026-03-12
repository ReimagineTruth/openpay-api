import { cn } from "@/lib/utils";

interface AuthMarkProps {
  className?: string;
}

const AuthMark = ({ className }: AuthMarkProps) => (
  <img
    src="/openpay-auth-logo.png"
    alt="OpenPay"
    className={cn("h-24 w-24 object-contain", className)}
  />
);

export default AuthMark;
