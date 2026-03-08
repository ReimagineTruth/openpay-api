import { useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { generateOpenPayAccountNumber } from "@/lib/openpayIdentity";

const SetupProfilePage = () => {
  const navigate = useNavigate();
  const [userId, setUserId] = useState<string | null>(null);
  const [fullName, setFullName] = useState("");
  const [username, setUsername] = useState("");
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    const load = async () => {
      const {
        data: { user },
      } = await supabase.auth.getUser();

      if (!user) {
        navigate("/auth", { replace: true });
        return;
      }

      setUserId(user.id);

      const { data: profile } = await supabase
        .from("profiles")
        .select("full_name, username")
        .eq("id", user.id)
        .single();

      const loadedName = (profile?.full_name || "").trim();
      const loadedUsername = (profile?.username || "").trim();

      setFullName(loadedName);
      setUsername(loadedUsername.startsWith("pi_") ? "" : loadedUsername);
    };

    load();
  }, [navigate]);

  const normalizedUsername = useMemo(() => {
    return username.trim().toLowerCase().replace(/[^a-z0-9_]/g, "");
  }, [username]);

  const handleSave = async () => {
    if (!userId) return;

    if (!fullName.trim()) {
      toast.error("Full name is required");
      return;
    }

    if (!/^[a-z0-9_]{3,20}$/i.test(normalizedUsername)) {
      toast.error("Username must be 3-20 characters and use letters, numbers, or underscore");
      return;
    }

    setSaving(true);

    const trimmedName = fullName.trim();
    const trimmedUsername = normalizedUsername;

    try {
      const { data: updatedRows, error: profileError } = await supabase
        .from("profiles")
        .update({
          full_name: trimmedName,
          username: trimmedUsername,
        })
        .eq("id", userId)
        .select("id");

      if (profileError) {
        throw new Error(profileError.message || "Failed to save profile");
      }

      if (!updatedRows || updatedRows.length === 0) {
        const referralBase = trimmedUsername || `user_${userId.replace(/-/g, "").slice(0, 8)}`;
        let created = false;
        for (let attempt = 0; attempt < 6; attempt++) {
          const referral_code = attempt === 0 ? referralBase : `${referralBase}${attempt}`;
          const insertPayload = {
            id: userId,
            full_name: trimmedName,
            username: trimmedUsername,
            referral_code,
          } as any;

          const { error: insertError } = await supabase.from("profiles").insert(insertPayload);
          if (!insertError) {
            created = true;
            break;
          }

          const msg = String(insertError.message || "");
          if (msg.toLowerCase().includes("column") && msg.toLowerCase().includes("referral_code")) {
            const { error: retryError } = await supabase.from("profiles").insert({
              id: userId,
              full_name: trimmedName,
              username: trimmedUsername,
            } as any);
            if (!retryError) {
              created = true;
              break;
            }
          }
        }

        if (!created) {
          throw new Error(
            "Profile record was missing and could not be created. Apply the latest Supabase migrations then try again.",
          );
        }
      }

      const accountNumber = generateOpenPayAccountNumber(userId);
      const { error: accountError } = await supabase.from("user_accounts").upsert(
        {
          user_id: userId,
          account_number: accountNumber,
          account_name: trimmedName,
          account_username: trimmedUsername,
        },
        { onConflict: "user_id" },
      );

      if (accountError) {
        try {
          await (supabase as any).rpc("upsert_my_user_account");
        } catch {
          // ignore
        }
      }
    } catch (err) {
      setSaving(false);
      toast.error(err instanceof Error ? err.message : "Failed to save profile");
      return;
    }

    setSaving(false);

    toast.success("Profile setup complete");
    navigate("/dashboard", { replace: true });
  };

  return (
    <div className="min-h-screen bg-background px-4 pt-8 pb-10">
      <div className="mx-auto max-w-md">
        <h1 className="paypal-heading">Set up your profile</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Complete your name and username to start using OpenPay.
        </p>

        <div className="paypal-surface mt-5 rounded-3xl p-5">
          <div className="space-y-3">
            <div>
              <p className="mb-1 text-sm text-muted-foreground">Full Name</p>
              <Input
                value={fullName}
                onChange={(e) => setFullName(e.target.value)}
                placeholder="Your full name"
                className="h-12 rounded-2xl bg-white"
              />
            </div>
            <div>
              <p className="mb-1 text-sm text-muted-foreground">Username</p>
              <Input
                value={username}
                onChange={(e) => setUsername(e.target.value)}
                placeholder="your_username"
                className="h-12 rounded-2xl bg-white"
              />
              <p className="mt-1 text-xs text-muted-foreground">
                Use 3-20 letters, numbers, or underscore.
              </p>
            </div>
          </div>

          <Button
            onClick={handleSave}
            disabled={saving}
            className="mt-5 h-12 w-full rounded-2xl bg-paypal-blue text-white hover:bg-[#004dc5]"
          >
            {saving ? "Saving..." : "Continue"}
          </Button>
        </div>
      </div>
    </div>
  );
};

export default SetupProfilePage;
