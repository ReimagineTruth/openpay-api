import { useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { hashSecret, loadAppSecuritySettings, markPinSetupCompleted, saveAppSecuritySettings } from "@/lib/appSecurity";
import { upsertUserPreferences } from "@/lib/userPreferences";

const OnboardingPage = () => {
  const navigate = useNavigate();
  const [userId, setUserId] = useState<string | null>(null);
  const [fullName, setFullName] = useState("");
  const [username, setUsername] = useState("");
  const [avatarUrl, setAvatarUrl] = useState("");
  const [pin, setPin] = useState("");
  const [pinConfirm, setPinConfirm] = useState("");
  const [saving, setSaving] = useState(false);
  const [pinAlreadySet, setPinAlreadySet] = useState(false);
  const [uploadingAvatar, setUploadingAvatar] = useState(false);

  useEffect(() => {
    const load = async () => {
      const {
        data: { user },
      } = await supabase.auth.getUser();

      if (!user) {
        navigate("/signin", { replace: true });
        return;
      }

      setUserId(user.id);

      const { data: profile } = await supabase
        .from("profiles")
        .select("full_name, username, avatar_url")
        .eq("id", user.id)
        .single();

      const loadedName = (profile?.full_name || "").trim();
      const loadedUsername = (profile?.username || "").trim();
      setAvatarUrl((profile as any)?.profile_image_url || (profile?.avatar_url || ""));
      setFullName(loadedName);
      setUsername(loadedUsername.startsWith("pi_") ? "" : loadedUsername);

      const settings = loadAppSecuritySettings(user.id);
      setPinAlreadySet(Boolean(settings?.pinHash));
    };

    void load();
  }, [navigate]);

  const normalizedUsername = useMemo(() => {
    return username.trim().toLowerCase().replace(/[^a-z0-9_]/g, "");
  }, [username]);

  const initials = fullName
    ? fullName
      .split(" ")
      .filter(Boolean)
      .map((n) => n[0])
      .join("")
      .slice(0, 2)
      .toUpperCase()
    : "OP";

  const handleAvatarUpload = async (event: React.ChangeEvent<HTMLInputElement>) => {
    if (!userId) return;
    const file = event.target.files?.[0];
    if (!file) return;
    if (!file.type.startsWith("image/")) {
      toast.error("Please select an image file");
      return;
    }

    const ext = file.name.split(".").pop()?.toLowerCase() || "jpg";
    const path = `${userId}/${Date.now()}.${ext}`;

    setUploadingAvatar(true);
    const { error: uploadError } = await supabase.storage
      .from("avatars")
      .upload(path, file, { upsert: true });

    if (uploadError) {
      setUploadingAvatar(false);
      toast.error(uploadError.message);
      return;
    }

    const {
      data: { publicUrl },
    } = supabase.storage.from("avatars").getPublicUrl(path);

    const { error: profileError } = await (supabase as any).rpc("upload_profile_image", {
      p_image_url: publicUrl,
    });

    setUploadingAvatar(false);
    if (profileError) {
      toast.error(profileError.message);
      return;
    }

    setAvatarUrl(publicUrl);
    toast.success("Profile image updated");
  };

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

    if (!pinAlreadySet) {
      if (!/^\d{4,8}$/.test(pin.trim())) {
        toast.error("PIN must be 4-8 digits");
        return;
      }
      if (pin.trim() !== pinConfirm.trim()) {
        toast.error("PIN confirmation does not match");
        return;
      }
    }

    setSaving(true);
    try {
      const { data, error } = await (supabase as any).rpc("complete_account_onboarding", {
        p_full_name: fullName.trim(),
        p_username: normalizedUsername,
        p_profile_image_url: avatarUrl.trim() || null,
        p_security_pin: pinAlreadySet ? null : pin.trim(),
      });
      if (error) {
        throw new Error(error.message || "Failed to complete onboarding");
      }
      if (data && !data[0]?.success) {
        throw new Error(data[0]?.message || "Failed to complete onboarding");
      }

      if (!pinAlreadySet) {
        const pinHash = await hashSecret(pin);
        const current = loadAppSecuritySettings(userId);
        saveAppSecuritySettings(userId, { ...current, pinHash });
      }
      markPinSetupCompleted(userId);

      upsertUserPreferences(userId, {
        profile_full_name: fullName.trim(),
        profile_username: normalizedUsername,
      }).catch(() => undefined);

      toast.success("Account setup complete");
      navigate("/dashboard", { replace: true });
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed to complete onboarding");
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="min-h-screen bg-background px-4 pt-8 pb-10">
      <div className="mx-auto max-w-md">
        <h1 className="paypal-heading">Complete your account</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Set your name, username, and security PIN to start using OpenPay.
        </p>

        <div className="paypal-surface mt-5 rounded-3xl p-5">
          <div className="mb-4 flex items-center gap-4">
            {avatarUrl ? (
              <img src={avatarUrl} alt="Profile avatar" className="h-16 w-16 rounded-full border border-border object-cover" />
            ) : (
              <div className="flex h-16 w-16 items-center justify-center rounded-full bg-paypal-blue text-lg font-bold text-white">
                {initials}
              </div>
            )}
            <div className="flex-1">
              <p className="text-sm font-semibold text-foreground">Profile image</p>
              <Input
                type="file"
                accept="image/*"
                onChange={handleAvatarUpload}
                className="mt-2 h-11 rounded-2xl bg-white"
              />
              {uploadingAvatar && <p className="mt-1 text-xs text-muted-foreground">Uploading image...</p>}
            </div>
          </div>
          <div className="space-y-4">
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

          <div className="mt-5 rounded-2xl border border-border bg-white p-4">
            <p className="text-sm font-semibold text-foreground">Security PIN</p>
            {pinAlreadySet ? (
              <p className="mt-2 text-xs text-muted-foreground">
                Your PIN is already set. You can update it later in Settings.
              </p>
            ) : (
              <div className="mt-3 space-y-3">
                <div>
                  <p className="mb-1 text-xs text-muted-foreground">Create PIN</p>
                  <Input
                    value={pin}
                    onChange={(e) => setPin(e.target.value)}
                    type="password"
                    inputMode="numeric"
                    placeholder="4-8 digits"
                    className="h-11 rounded-2xl bg-white"
                  />
                </div>
                <div>
                  <p className="mb-1 text-xs text-muted-foreground">Confirm PIN</p>
                  <Input
                    value={pinConfirm}
                    onChange={(e) => setPinConfirm(e.target.value)}
                    type="password"
                    inputMode="numeric"
                    placeholder="Re-enter PIN"
                    className="h-11 rounded-2xl bg-white"
                  />
                </div>
                <p className="text-[11px] text-muted-foreground">PIN protects payments and wallet actions.</p>
              </div>
            )}
          </div>

          <Button
            onClick={handleSave}
            disabled={saving}
            className="mt-6 h-12 w-full rounded-2xl bg-paypal-blue text-white hover:bg-[#004dc5]"
          >
            {saving ? "Saving..." : "Finish setup"}
          </Button>
        </div>
      </div>
    </div>
  );
};

export default OnboardingPage;
