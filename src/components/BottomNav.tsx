import { useNavigate } from "react-router-dom";
import { Home, QrCode, Menu } from "lucide-react";

interface BottomNavProps {
  active: "home" | "contacts" | "scan" | "menu";
}

const BottomNav = ({ active }: BottomNavProps) => {
  const navigate = useNavigate();

  const items = [
    { key: "home" as const, label: "Home", icon: Home, path: "/dashboard" },
    { key: "scan" as const, label: "Scan QR", icon: QrCode, path: "/scan-qr?returnTo=/send" },
    { key: "menu" as const, label: "Menu", icon: Menu, path: "/menu" },
  ];

  return (
    <div className="fixed bottom-6 left-0 right-0 z-30 px-4">
      <div className="mx-auto max-w-md bg-white/95 backdrop-blur-md rounded-[2rem] shadow-2xl border border-white/60 overflow-hidden">
        <div className="flex items-center justify-around px-2 py-3.5">
        {items.map(({ key, label, icon: Icon, path }) => (
          <button
            key={key}
            onClick={() => navigate(path)}
            className={`flex min-w-[85px] flex-col items-center gap-1.5 rounded-2xl py-2.5 transition-all duration-300 active:scale-95 ${
              active === key 
                ? "bg-secondary/80 text-paypal-blue shadow-inner" 
                : "text-muted-foreground hover:bg-secondary/40"
            }`}
          >
            <Icon className={`w-6 h-6 transition-transform ${active === key ? "scale-110" : ""}`} />
            <span className={`text-[11px] tracking-tight ${active === key ? "font-extrabold" : "font-semibold"}`}>{label}</span>
          </button>
        ))}
        </div>
      </div>
    </div>
  );
};

export default BottomNav;
