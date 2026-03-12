import { useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { ArrowLeft, Clock, Lock, ShieldCheck, Wallet, History, ArrowDownToLine, ArrowUpToLine } from "lucide-react";
import { format } from "date-fns";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import RegulatoryStatusModal from "@/components/RegulatoryStatusModal";
import { useCurrency } from "@/contexts/CurrencyContext";

type StakeRow = {
  id: string;
  amount: number;
  lock_days: number;
  reward_rate: number;
  reward_amount: number;
  status: string;
  ends_at: string;
  created_at: string;
};

type StakingHistoryRow = {
  id: string;
  amount: number;
  note: string | null;
  status: string | null;
  created_at: string;
};

const parseStakeRewardFromNote = (note: string | null): number | null => {
  if (!note) return null;
  const match = note.match(/reward\s+([0-9]+(?:\.[0-9]+)?)/i);
  if (!match?.[1]) return null;
  const value = Number(match[1]);
  return Number.isFinite(value) ? value : null;
};

const STAKE_OPTIONS = [
  { days: 7, rate: 0.02 },
  { days: 30, rate: 0.05 },
  { days: 90, rate: 0.1 },
  { days: 365, rate: 0.2 },
];

const StakingPage = () => {
  const navigate = useNavigate();
  const { format: formatCurrency } = useCurrency();
  const [loading, setLoading] = useState(true);
  const [balance, setBalance] = useState(0);
  const [amount, setAmount] = useState("");
  const [lockDays, setLockDays] = useState<number>(30);
  const [staking, setStaking] = useState(false);
  const [positions, setPositions] = useState<StakeRow[]>([]);
  const [historyRows, setHistoryRows] = useState<StakingHistoryRow[]>([]);
  const [showRegulatoryModal, setShowRegulatoryModal] = useState(false);

  const parsedAmount = Number(amount);
  const safeAmount = Number.isFinite(parsedAmount) && parsedAmount > 0 ? parsedAmount : 0;
  const selectedRate = useMemo(() => {
    return STAKE_OPTIONS.find((opt) => opt.days === lockDays)?.rate ?? 0;
  }, [lockDays]);
  const rewardPreview = safeAmount > 0 ? Math.round(safeAmount * selectedRate * 100) / 100 : 0;

  const loadData = async () => {
    setLoading(true);
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) {
        navigate("/signin");
        return;
      }

      const [{ data: wallet }, { data: stakeRows }, { data: stakingHistory }] = await Promise.all([
        supabase.from("wallets").select("balance").eq("user_id", user.id).single(),
        (supabase as any)
          .from("staking_positions")
          .select("*")
          .eq("user_id", user.id)
          .order("created_at", { ascending: false }),
        (supabase as any)
          .from("transactions")
          .select("id, amount, note, status, created_at")
          .eq("sender_id", user.id)
          .eq("receiver_id", user.id)
          .ilike("note", "Stake %")
          .order("created_at", { ascending: false })
          .limit(50),
      ]);

      setBalance(Number(wallet?.balance || 0));
      setPositions((stakeRows as StakeRow[] | null) || []);
      setHistoryRows((stakingHistory as StakingHistoryRow[] | null) || []);
    } catch (error) {
      toast.error(error instanceof Error ? error.message : "Failed to load staking data");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void loadData();
  }, []);

  const handleStake = async () => {
    if (safeAmount <= 0) {
      toast.error("Enter a valid stake amount");
      return;
    }
    if (safeAmount > balance) {
      toast.error("Insufficient balance");
      return;
    }
    setStaking(true);
    try {
      const { data, error } = await supabase.rpc("create_stake", {
        p_amount: Number(safeAmount.toFixed(2)),
        p_lock_days: lockDays,
      } as any);
      if (error) throw new Error(error.message || "Stake failed");
      const rewardAmount = Number((data as any)?.reward_amount || 0);
      toast.success(`Stake created. Reward: ${rewardAmount.toFixed(2)} OPEN USD`);
      setAmount("");
      await loadData();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : "Stake failed");
    } finally {
      setStaking(false);
    }
  };

  const handleClaim = async (id: string) => {
    try {
      const { data, error } = await supabase.rpc("claim_stake", { p_position_id: id } as any);
      if (error) throw new Error(error.message || "Claim failed");
      const total = Number((data as any)?.total || 0);
      toast.success(`Claimed ${total.toFixed(2)} OPEN USD`);
      await loadData();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : "Claim failed");
    }
  };

  const totalRewardsEarned = useMemo(() => {
    return (historyRows || [])
      .filter((row) => String(row.note || "").toLowerCase().includes("stake claim"))
      .reduce((sum, row) => sum + (parseStakeRewardFromNote(row.note) ?? 0), 0);
  }, [historyRows]);

  return (
    <div className="min-h-screen bg-background px-4 pt-4 pb-24">
      <div className="flex items-center gap-3">
        <button onClick={() => navigate("/menu")}>
          <ArrowLeft className="h-6 w-6 text-foreground" />
        </button>
        <h1 className="text-lg font-semibold text-paypal-dark">Staking</h1>
      </div>

      <div className="paypal-surface mt-6 rounded-3xl p-6">
        <div className="flex items-center gap-2 text-sm text-muted-foreground">
          <Wallet className="h-4 w-4 text-paypal-blue" />
          Available balance
        </div>
        <p className="mt-1 text-2xl font-bold text-foreground">{formatCurrency(balance)}</p>

        <div className="mt-4 rounded-2xl border border-border bg-white p-4">
          <p className="text-xs font-semibold text-muted-foreground">Stake amount (OPEN USD)</p>
          <input
            value={amount}
            onChange={(event) => setAmount(event.target.value)}
            type="number"
            min="1"
            step="0.01"
            placeholder="0.00"
            className="mt-2 h-11 w-full rounded-xl border border-border px-3 text-sm text-foreground"
          />

          <p className="mt-4 text-xs font-semibold text-muted-foreground">Lock duration</p>
          <div className="mt-2 grid grid-cols-3 gap-2">
            {STAKE_OPTIONS.map((opt) => (
              <button
                key={opt.days}
                type="button"
                onClick={() => setLockDays(opt.days)}
                className={`rounded-xl border px-3 py-2 text-xs font-semibold ${
                  lockDays === opt.days
                    ? "border-paypal-blue bg-paypal-blue text-white"
                    : "border-border bg-white text-foreground"
                }`}
              >
                {opt.days} days
              </button>
            ))}
          </div>

          <div className="mt-4 rounded-xl border border-border bg-secondary/20 p-3 text-sm text-foreground">
            <div className="flex items-center justify-between">
              <span>Reward rate</span>
              <span className="font-semibold">{(selectedRate * 100).toFixed(0)}%</span>
            </div>
            <div className="mt-1 flex items-center justify-between">
              <span>Estimated reward</span>
              <span className="font-semibold">{rewardPreview.toFixed(2)} OPEN USD</span>
            </div>
            <div className="mt-1 flex items-center justify-between">
              <span>Total at unlock</span>
              <span className="font-semibold">{(safeAmount + rewardPreview).toFixed(2)} OPEN USD</span>
            </div>
          </div>

          <Button
            className="mt-4 h-11 w-full rounded-2xl bg-paypal-blue text-white hover:bg-[#004dc5]"
            disabled={staking || safeAmount <= 0}
            onClick={handleStake}
          >
            {staking ? "Staking..." : "Stake now"}
          </Button>
        </div>
      </div>

      <div className="mt-6">
        <div className="mb-3 flex items-center justify-between">
          <h2 className="text-lg font-semibold text-foreground">Your stakes</h2>
          <div className="text-xs text-muted-foreground">{positions.length} total</div>
        </div>

        {loading ? (
          <div className="rounded-2xl border border-border bg-white p-4 text-sm text-muted-foreground">Loading...</div>
        ) : positions.length === 0 ? (
          <div className="rounded-2xl border border-dashed border-border bg-white p-6 text-center text-sm text-muted-foreground">
            No staking positions yet.
          </div>
        ) : (
          <div className="space-y-3">
            {positions.map((row) => {
              const canClaim = row.status === "active" && new Date(row.ends_at).getTime() <= Date.now();
              return (
                <div key={row.id} className="rounded-2xl border border-border bg-white p-4">
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="text-sm font-semibold text-foreground">
                        {Number(row.amount || 0).toFixed(2)} OPEN USD
                      </p>
                      <p className="text-xs text-muted-foreground">
                        {row.lock_days} days · Reward {Number(row.reward_amount || 0).toFixed(2)}
                      </p>
                    </div>
                    <span className="rounded-full border border-border px-2 py-0.5 text-xs font-semibold text-muted-foreground">
                      {row.status}
                    </span>
                  </div>
                  <div className="mt-3 flex items-center gap-2 text-xs text-muted-foreground">
                    <Clock className="h-4 w-4 text-paypal-blue" />
                    Unlocks {row.ends_at ? format(new Date(row.ends_at), "MMM d, yyyy HH:mm") : "N/A"}
                  </div>
                  <div className="mt-3 flex items-center gap-2 text-xs text-muted-foreground">
                    <Lock className="h-4 w-4 text-paypal-blue" />
                    Funds locked until unlock date
                  </div>
                  <Button
                    variant="outline"
                    className="mt-3 h-10 w-full rounded-xl"
                    disabled={!canClaim}
                    onClick={() => handleClaim(row.id)}
                  >
                    {canClaim ? "Claim reward" : "Locked"}
                  </Button>
                </div>
              );
            })}
          </div>
        )}
      </div>

      <div className="mt-8">
        <div className="mb-3 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <History className="h-4 w-4 text-paypal-blue" />
            <h2 className="text-lg font-semibold text-foreground">Staking history</h2>
          </div>
          <div className="text-xs text-muted-foreground">
            Rewards earned: {totalRewardsEarned.toFixed(2)} OPEN USD
          </div>
        </div>

        {loading ? (
          <div className="rounded-2xl border border-border bg-white p-4 text-sm text-muted-foreground">Loading...</div>
        ) : historyRows.length === 0 ? (
          <div className="rounded-2xl border border-dashed border-border bg-white p-6 text-center text-sm text-muted-foreground">
            No staking history yet.
          </div>
        ) : (
          <div className="space-y-3">
            {historyRows.map((row) => {
              const note = String(row.note || "");
              const lower = note.toLowerCase();
              const isLockEvent = lower.includes("stake lock");
              const isClaimEvent = lower.includes("stake claim");
              const reward = parseStakeRewardFromNote(row.note);
              const label = isLockEvent ? "Stake locked" : isClaimEvent ? "Stake claimed" : "Staking activity";
              const Icon = isLockEvent ? ArrowDownToLine : isClaimEvent ? ArrowUpToLine : History;
              return (
                <div key={row.id} className="rounded-2xl border border-border bg-white p-4">
                  <div className="flex items-start justify-between gap-3">
                    <div className="flex min-w-0 items-start gap-3">
                      <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-paypal-blue/10 text-paypal-blue">
                        <Icon className="h-5 w-5" />
                      </div>
                      <div className="min-w-0">
                        <p className="text-sm font-semibold text-foreground">{label}</p>
                        <p className="mt-0.5 text-xs text-muted-foreground line-clamp-2">{note}</p>
                        <p className="mt-1 text-[10px] font-semibold text-muted-foreground">
                          {row.created_at ? format(new Date(row.created_at), "MMM d, yyyy HH:mm") : "N/A"}{" "}
                          {row.status ? `· ${row.status}` : ""}
                        </p>
                      </div>
                    </div>
                    <div className="text-right">
                      <p className="text-sm font-bold text-foreground">{Number(row.amount || 0).toFixed(2)} OPEN USD</p>
                      {reward !== null && reward > 0 && (
                        <p className="text-[10px] font-bold text-paypal-blue">Reward {reward.toFixed(2)}</p>
                      )}
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>

      <div className="mt-6 rounded-2xl border border-border bg-white p-4 text-sm text-muted-foreground">
        <div className="flex items-start gap-2">
          <ShieldCheck className="mt-0.5 h-4 w-4 text-paypal-blue" />
          <div>
            <p className="font-semibold text-foreground">Staking rules</p>
            <p className="mt-1">Staked funds are locked for the selected duration.</p>
            <p className="mt-1">You can claim rewards only after the lock ends.</p>
          </div>
        </div>
      </div>

      <Button
        type="button"
        variant="outline"
        className="mt-4 h-11 w-full rounded-2xl"
        onClick={() => setShowRegulatoryModal(true)}
      >
        Regulatory Status
      </Button>

      <RegulatoryStatusModal open={showRegulatoryModal} onOpenChange={setShowRegulatoryModal} />
    </div>
  );
};

export default StakingPage;
