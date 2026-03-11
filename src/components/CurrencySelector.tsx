import { useState } from "react";
import { PI_TO_USD, useCurrency } from "@/contexts/CurrencyContext";
import { ChevronDown, Search } from "lucide-react";
import BrandLogo from "./BrandLogo";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { ScrollArea } from "@/components/ui/scroll-area";

const emojiFlagStyle = {
  fontFamily: "\"Segoe UI Emoji\", \"Apple Color Emoji\", \"Noto Color Emoji\", sans-serif",
};
const PURE_PI_ICON_URL = "https://i.ibb.co/BV8PHjB4/Pi-200x200.png";
const TOP_PRIORITY_CODES = ["OUSD", "PI", "USD", "EUR"];

const CurrencySelector = () => {
  const { currencies, currency, setCurrency } = useCurrency();
  const [open, setOpen] = useState(false);
  const [search, setSearch] = useState("");
  const getPiCodeLabel = (code: string) => {
    if (code === "PI") return "PI";
    if (code === "OUSD") return "OPEN USD";
    return `PI ${code}`;
  };
  const getPiNameLabel = (code: string, name: string) => {
    if (code === "PI") return "Pure Pi";
    if (code === "OUSD") return `OpenPay USD Stablecoin (1 PI = ${PI_TO_USD.toFixed(2)} OUSD)`;
    return `PI ${name}`;
  };
  const getDisplaySymbol = (code: string, symbol: string) => (code === "PI" ? "π" : symbol);
  const searchTerm = search.trim().toLowerCase();

  const filtered = currencies.filter(
    (c) =>
      c.code.toLowerCase().includes(searchTerm) ||
      c.name.toLowerCase().includes(searchTerm) ||
      `pi ${c.code}`.toLowerCase().includes(searchTerm) ||
      `pi ${c.name}`.toLowerCase().includes(searchTerm) ||
      (c.code === "OUSD" && "openusd open usd openpay usd 1 usd".includes(searchTerm))
  );
  const prioritized = [...filtered].sort((a, b) => {
    const aPriority = TOP_PRIORITY_CODES.indexOf(a.code);
    const bPriority = TOP_PRIORITY_CODES.indexOf(b.code);
    const aRank = aPriority === -1 ? Number.MAX_SAFE_INTEGER : aPriority;
    const bRank = bPriority === -1 ? Number.MAX_SAFE_INTEGER : bPriority;
    if (aRank !== bRank) return aRank - bRank;
    return a.code.localeCompare(b.code);
  });
  const openUsdCurrency = currencies.find((c) => c.code === "OUSD");
  const piCurrency = prioritized.find((c) => c.code === "PI");
  const piUsdCurrency = prioritized.find((c) => c.code === "USD");
  const piEurCurrency = prioritized.find((c) => c.code === "EUR");
  const remainingCurrencies = prioritized.filter((c) => !["OUSD", "PI", "USD", "EUR"].includes(c.code));
  const showOpenUsd =
    !!openUsdCurrency &&
    (!searchTerm ||
      "openusd open usd openpay usd 1 usd pi usd usd".includes(searchTerm) ||
      searchTerm.includes("openusd") ||
      searchTerm.includes("open usd") ||
      searchTerm.includes("openpay"));

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <button className="flex items-center gap-1.5 px-3 py-1.5 rounded-full bg-secondary text-secondary-foreground text-sm font-medium border border-border hover:bg-accent transition-colors">
          {currency.code === "PI" ? (
            <img
              src={PURE_PI_ICON_URL}
              alt="Pure Pi"
              className="h-[18px] w-[18px] rounded-full object-cover"
            />
          ) : currency.code === "OUSD" ? (
            <BrandLogo className="h-[18px] w-[18px] text-paypal-blue" />
          ) : (
            <span className="text-lg leading-none" style={emojiFlagStyle}>{currency.flag}</span>
          )}
          <span>{getPiCodeLabel(currency.code)}</span>
          <ChevronDown className="w-3.5 h-3.5 opacity-60" />
        </button>
      </DialogTrigger>
      <DialogContent className="max-w-sm p-0 gap-0">
        <DialogHeader className="px-4 pt-4 pb-2">
          <DialogTitle className="text-lg font-bold text-foreground">Select Currency</DialogTitle>
          <DialogDescription className="sr-only">Choose your preferred currency.</DialogDescription>
        </DialogHeader>
        <div className="px-4 pb-2">
          <div className="relative">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
            <Input
              placeholder="Search currency..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="pl-9 h-10 rounded-xl"
            />
          </div>
        </div>
        <ScrollArea className="h-[360px]">
          <div className="px-2 pb-2">
            {showOpenUsd && openUsdCurrency && (
              <button
                onClick={() => {
                  setCurrency(openUsdCurrency);
                  setOpen(false);
                  setSearch("");
                }}
                className={`mb-1 w-full flex items-center gap-3 px-3 py-2.5 rounded-lg text-left transition-colors ${
                  currency.code === "OUSD"
                    ? "bg-primary/10 text-primary"
                    : "hover:bg-muted text-foreground"
                }`}
              >
                <div className="flex h-7 w-7 items-center justify-center rounded-full bg-paypal-blue/10">
                  <BrandLogo className="h-5 w-5 text-paypal-blue" />
                </div>
                <div className="flex-1 min-w-0">
                  <p className="font-semibold text-sm">OPEN USD</p>
                  <p className="text-xs text-muted-foreground truncate">OpenPay USD Stablecoin (1 USD value)</p>
                </div>
                <span className="text-xs text-muted-foreground font-medium">$</span>
              </button>
            )}
            {piCurrency && (
              <button
                key={piCurrency.code}
                onClick={() => {
                  setCurrency(piCurrency);
                  setOpen(false);
                  setSearch("");
                }}
                className={`w-full flex items-center gap-3 px-3 py-2.5 rounded-lg text-left transition-colors ${
                  piCurrency.code === currency.code
                    ? "bg-primary/10 text-primary"
                    : "hover:bg-muted text-foreground"
                }`}
              >
                <img
                  src={PURE_PI_ICON_URL}
                  alt="Pure Pi"
                  className="h-7 w-7 rounded-full object-cover"
                />
                <div className="flex-1 min-w-0">
                  <p className="font-semibold text-sm">{getPiCodeLabel(piCurrency.code)}</p>
                  <p className="text-xs text-muted-foreground truncate">{getPiNameLabel(piCurrency.code, piCurrency.name)}</p>
                </div>
                <span className="text-xs text-muted-foreground font-medium">{getDisplaySymbol(piCurrency.code, piCurrency.symbol)}</span>
              </button>
            )}
            {piUsdCurrency && (
              <button
                key={piUsdCurrency.code}
                onClick={() => {
                  setCurrency(piUsdCurrency);
                  setOpen(false);
                  setSearch("");
                }}
                className={`w-full flex items-center gap-3 px-3 py-2.5 rounded-lg text-left transition-colors ${
                  piUsdCurrency.code === currency.code
                    ? "bg-primary/10 text-primary"
                    : "hover:bg-muted text-foreground"
                }`}
              >
                <span className="text-2xl leading-none" style={emojiFlagStyle}>{piUsdCurrency.flag}</span>
                <div className="flex-1 min-w-0">
                  <p className="font-semibold text-sm">{getPiCodeLabel(piUsdCurrency.code)}</p>
                  <p className="text-xs text-muted-foreground truncate">{getPiNameLabel(piUsdCurrency.code, piUsdCurrency.name)}</p>
                </div>
                <span className="text-xs text-muted-foreground font-medium">{getDisplaySymbol(piUsdCurrency.code, piUsdCurrency.symbol)}</span>
              </button>
            )}
            {piEurCurrency && (
              <button
                key={piEurCurrency.code}
                onClick={() => {
                  setCurrency(piEurCurrency);
                  setOpen(false);
                  setSearch("");
                }}
                className={`w-full flex items-center gap-3 px-3 py-2.5 rounded-lg text-left transition-colors ${
                  piEurCurrency.code === currency.code
                    ? "bg-primary/10 text-primary"
                    : "hover:bg-muted text-foreground"
                }`}
              >
                <span className="text-2xl leading-none" style={emojiFlagStyle}>{piEurCurrency.flag}</span>
                <div className="flex-1 min-w-0">
                  <p className="font-semibold text-sm">{getPiCodeLabel(piEurCurrency.code)}</p>
                  <p className="text-xs text-muted-foreground truncate">{getPiNameLabel(piEurCurrency.code, piEurCurrency.name)}</p>
                </div>
                <span className="text-xs text-muted-foreground font-medium">{getDisplaySymbol(piEurCurrency.code, piEurCurrency.symbol)}</span>
              </button>
            )}
            {remainingCurrencies.map((c) => (
              <button
                key={c.code}
                onClick={() => {
                  setCurrency(c);
                  setOpen(false);
                  setSearch("");
                }}
                className={`w-full flex items-center gap-3 px-3 py-2.5 rounded-lg text-left transition-colors ${
                  c.code === currency.code
                    ? "bg-primary/10 text-primary"
                    : "hover:bg-muted text-foreground"
                }`}
              >
                {c.code === "PI" ? (
                  <img
                    src={PURE_PI_ICON_URL}
                    alt="Pure Pi"
                    className="h-7 w-7 rounded-full object-cover"
                  />
                ) : (
                  <span className="text-2xl leading-none" style={emojiFlagStyle}>{c.flag}</span>
                )}
                <div className="flex-1 min-w-0">
                  <p className="font-semibold text-sm">{getPiCodeLabel(c.code)}</p>
                  <p className="text-xs text-muted-foreground truncate">{getPiNameLabel(c.code, c.name)}</p>
                </div>
                <span className="text-xs text-muted-foreground font-medium">{getDisplaySymbol(c.code, c.symbol)}</span>
              </button>
            ))}
            {filtered.length === 0 && (
              <p className="text-center text-muted-foreground py-8 text-sm">No currencies found</p>
            )}
          </div>
        </ScrollArea>
      </DialogContent>
    </Dialog>
  );
};

export default CurrencySelector;


