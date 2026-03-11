import { Button } from "@/components/ui/button";
import type { ReactNode } from "react";

type ActionItem = {
  label: string;
  onClick: () => void;
  icon: ReactNode;
  disabled?: boolean;
};

type TopUpActionGridProps = {
  actions: ActionItem[];
};

const TopUpActionGrid = ({ actions }: TopUpActionGridProps) => {
  return (
    <div className="mt-4 grid grid-cols-2 gap-2 sm:grid-cols-3">
      {actions.map((a) => (
        <Button
          key={a.label}
          type="button"
          variant="default"
          className="h-12 w-full rounded-2xl bg-paypal-blue text-white hover:bg-[#004dc5] disabled:opacity-60 disabled:cursor-not-allowed"
          onClick={a.onClick}
          disabled={a.disabled}
        >
          <span className="inline-flex items-center gap-2">
            {a.icon}
            <span className="text-sm font-semibold">{a.label}</span>
          </span>
        </Button>
      ))}
    </div>
  );
};

export default TopUpActionGrid;
