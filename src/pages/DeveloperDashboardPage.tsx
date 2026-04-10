import { useState, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { ArrowLeft, Plus, Key, Trash2, Copy, Eye, EyeOff, Globe, BarChart3, Webhook, Terminal, Play, Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";

interface DeveloperApp {
  id: string;
  app_name: string;
  app_description: string;
  app_url: string;
  client_id: string;
  client_secret_last4: string;
  is_active: boolean;
  scopes: string[];
  rate_limit_per_minute: number;
  created_at: string;
}

interface ApiLog {
  id: string;
  endpoint: string;
  method: string;
  status_code: number;
  created_at: string;
}

const DeveloperDashboardPage = () => {
  const navigate = useNavigate();
  const [apps, setApps] = useState<DeveloperApp[]>([]);
  const [logs, setLogs] = useState<ApiLog[]>([]);
  const [loading, setLoading] = useState(true);
  const [showCreate, setShowCreate] = useState(false);
  const [newApp, setNewApp] = useState({ app_name: "", app_description: "", app_url: "", redirect_uris: "" });
  const [creating, setCreating] = useState(false);
  const [newSecret, setNewSecret] = useState("");
  const [showSecrets, setShowSecrets] = useState<Record<string, boolean>>({});
  const [rpcNetwork, setRpcNetwork] = useState<"testnet" | "mainnet">("testnet");
  const [rpcMethod, setRpcMethod] = useState("getHealth");
  const [rpcParams, setRpcParams] = useState("");
  const [rpcResult, setRpcResult] = useState("");
  const [rpcLoading, setRpcLoading] = useState(false);

  const loadApps = async () => {
    const { data } = await supabase.from("developer_apps").select("*").order("created_at", { ascending: false });
    setApps((data as any[]) || []);
  };

  const loadLogs = async () => {
    const { data } = await supabase.from("api_access_logs").select("*").order("created_at", { ascending: false }).limit(50);
    setLogs((data as any[]) || []);
  };

  useEffect(() => {
    Promise.all([loadApps(), loadLogs()]).finally(() => setLoading(false));
  }, []);

  const createApp = async () => {
    setCreating(true);
    try {
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) { toast.error("Please sign in"); return; }

      const requestBody = {
        app_name: newApp.app_name,
        app_description: newApp.app_description,
        app_url: newApp.app_url,
        redirect_uris: newApp.redirect_uris.split(",").map(u => u.trim()).filter(Boolean),
        scopes: ["read:balance", "read:profile", "read:transactions", "write:send", "read:invoices", "write:invoices"],
      };

      const { data: result, error: fnError } = await supabase.functions.invoke("smart-contract-api", {
        body: requestBody,
        headers: { "x-target-path": "apps/register" },
      });

      if (fnError) throw new Error(fnError.message || "Failed to create app");
      if (result?.error) throw new Error(result.error);

      if (result?.app?.client_secret) {
        setNewSecret(result.app.client_secret);
      }
      toast.success("App created!");
      setShowCreate(false);
      setNewApp({ app_name: "", app_description: "", app_url: "", redirect_uris: "" });
      await loadApps();
    } catch (err: any) {
      toast.error(err.message || "Failed to create app");
    } finally {
      setCreating(false);
    }
  };

  const deleteApp = async (appId: string) => {
    const { error } = await supabase.from("developer_apps").delete().eq("id", appId);
    if (error) { toast.error("Failed to delete"); return; }
    toast.success("App deleted");
    await loadApps();
  };

  const copyToClipboard = (text: string, label: string) => {
    navigator.clipboard.writeText(text);
    toast.success(`${label} copied`);
  };

  const callPiRpc = async () => {
    setRpcLoading(true);
    setRpcResult("");
    try {
      const endpoint = rpcNetwork === "mainnet" ? "pi-rpc/mainnet" : "pi-rpc";
      let parsedParams: unknown[] = [];
      if (rpcParams.trim()) {
        try { parsedParams = JSON.parse(rpcParams); } catch { parsedParams = [rpcParams.trim()]; }
      }
      const rpcBody: Record<string, unknown> = { jsonrpc: "2.0", id: 1, method: rpcMethod };
      if (parsedParams.length > 0) rpcBody.params = parsedParams;

      const { data, error } = await supabase.functions.invoke("smart-contract-api", {
        body: rpcBody,
        headers: { "x-target-path": endpoint },
      });
      if (error) throw error;
      setRpcResult(JSON.stringify(data, null, 2));
    } catch (err: any) {
      setRpcResult(JSON.stringify({ error: err.message || "RPC call failed" }, null, 2));
    } finally {
      setRpcLoading(false);
    }
  };
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-background flex items-center justify-center">
        <p className="text-muted-foreground">Loading...</p>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-background">
      <div className="sticky top-0 z-20 bg-background/95 backdrop-blur border-b border-border px-4 py-3">
        <div className="flex items-center gap-3 max-w-5xl mx-auto">
          <button onClick={() => navigate(-1)}><ArrowLeft className="h-5 w-5 text-foreground" /></button>
          <Key className="h-5 w-5 text-primary" />
          <h1 className="text-lg font-bold text-foreground">Developer Dashboard</h1>
          <Button size="sm" className="ml-auto gap-1" onClick={() => setShowCreate(true)}>
            <Plus className="h-4 w-4" /> New App
          </Button>
        </div>
      </div>

      <div className="max-w-5xl mx-auto px-4 py-6 space-y-6">
        {/* Secret reveal banner */}
        {newSecret && (
          <Card className="border-yellow-500 bg-yellow-50 dark:bg-yellow-900/20">
            <CardContent className="p-4 space-y-2">
              <p className="text-sm font-bold text-yellow-800 dark:text-yellow-200">⚠️ Save Your Client Secret Now</p>
              <p className="text-xs text-yellow-700 dark:text-yellow-300">This will not be shown again.</p>
              <div className="flex items-center gap-2">
                <code className="text-xs bg-white dark:bg-black/30 p-2 rounded flex-1 break-all">{newSecret}</code>
                <Button size="sm" variant="outline" onClick={() => copyToClipboard(newSecret, "Secret")}>
                  <Copy className="h-3 w-3" />
                </Button>
              </div>
              <Button size="sm" variant="ghost" onClick={() => setNewSecret("")}>Dismiss</Button>
            </CardContent>
          </Card>
        )}

        <Tabs defaultValue="apps">
          <TabsList className="w-full justify-start bg-muted/50 rounded-xl p-1">
            <TabsTrigger value="apps" className="gap-1"><Globe className="h-3.5 w-3.5" /> Apps ({apps.length})</TabsTrigger>
            <TabsTrigger value="logs" className="gap-1"><BarChart3 className="h-3.5 w-3.5" /> API Logs</TabsTrigger>
          </TabsList>

          <TabsContent value="apps" className="space-y-4 mt-4">
            {apps.length === 0 ? (
              <Card>
                <CardContent className="p-8 text-center space-y-3">
                  <Globe className="h-10 w-10 text-muted-foreground mx-auto" />
                  <p className="text-muted-foreground">No apps yet. Create one to get started.</p>
                  <Button onClick={() => setShowCreate(true)} className="gap-1"><Plus className="h-4 w-4" /> Create App</Button>
                </CardContent>
              </Card>
            ) : (
              apps.map(app => (
                <Card key={app.id}>
                  <CardHeader className="pb-2">
                    <div className="flex items-center justify-between">
                      <CardTitle className="text-base">{app.app_name}</CardTitle>
                      <div className="flex items-center gap-2">
                        <span className={`text-[10px] px-2 py-0.5 rounded-full font-medium ${app.is_active ? "bg-green-100 text-green-700" : "bg-red-100 text-red-700"}`}>
                          {app.is_active ? "Active" : "Inactive"}
                        </span>
                        <Button variant="ghost" size="icon" className="h-7 w-7 text-destructive" onClick={() => deleteApp(app.id)}>
                          <Trash2 className="h-3.5 w-3.5" />
                        </Button>
                      </div>
                    </div>
                  </CardHeader>
                  <CardContent className="space-y-3">
                    {app.app_description && <p className="text-xs text-muted-foreground">{app.app_description}</p>}

                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                      <div>
                        <p className="text-[10px] uppercase text-muted-foreground font-medium">Client ID</p>
                        <div className="flex items-center gap-1 mt-0.5">
                          <code className="text-xs text-foreground">{app.client_id}</code>
                          <button onClick={() => copyToClipboard(app.client_id, "Client ID")}>
                            <Copy className="h-3 w-3 text-muted-foreground" />
                          </button>
                        </div>
                      </div>
                      <div>
                        <p className="text-[10px] uppercase text-muted-foreground font-medium">Client Secret</p>
                        <div className="flex items-center gap-1 mt-0.5">
                          <code className="text-xs text-foreground">
                            {showSecrets[app.id] ? `ops_...${app.client_secret_last4}` : "••••••••"}
                          </code>
                          <button onClick={() => setShowSecrets(p => ({ ...p, [app.id]: !p[app.id] }))}>
                            {showSecrets[app.id] ? <EyeOff className="h-3 w-3 text-muted-foreground" /> : <Eye className="h-3 w-3 text-muted-foreground" />}
                          </button>
                        </div>
                      </div>
                    </div>

                    <div>
                      <p className="text-[10px] uppercase text-muted-foreground font-medium mb-1">Scopes</p>
                      <div className="flex flex-wrap gap-1">
                        {app.scopes.map(s => (
                          <span key={s} className="text-[10px] px-1.5 py-0.5 rounded bg-primary/10 text-primary font-mono">{s}</span>
                        ))}
                      </div>
                    </div>

                    <div className="flex items-center justify-between text-[10px] text-muted-foreground">
                      <span>Rate limit: {app.rate_limit_per_minute}/min</span>
                      <span>Created: {new Date(app.created_at).toLocaleDateString()}</span>
                    </div>
                  </CardContent>
                </Card>
              ))
            )}
          </TabsContent>

          <TabsContent value="logs" className="space-y-4 mt-4">
            {logs.length === 0 ? (
              <Card>
                <CardContent className="p-8 text-center">
                  <BarChart3 className="h-10 w-10 text-muted-foreground mx-auto mb-2" />
                  <p className="text-muted-foreground">No API calls recorded yet.</p>
                </CardContent>
              </Card>
            ) : (
              <Card>
                <CardContent className="p-0">
                  <div className="overflow-x-auto">
                    <table className="w-full text-xs">
                      <thead className="bg-muted/50">
                        <tr>
                          <th className="text-left p-2 font-medium text-muted-foreground">Time</th>
                          <th className="text-left p-2 font-medium text-muted-foreground">Method</th>
                          <th className="text-left p-2 font-medium text-muted-foreground">Endpoint</th>
                          <th className="text-left p-2 font-medium text-muted-foreground">Status</th>
                        </tr>
                      </thead>
                      <tbody>
                        {logs.map(log => (
                          <tr key={log.id} className="border-t border-border">
                            <td className="p-2 text-muted-foreground">{new Date(log.created_at).toLocaleString()}</td>
                            <td className="p-2"><span className={`px-1.5 py-0.5 rounded text-[10px] font-bold ${log.method === "GET" ? "bg-green-100 text-green-700" : "bg-blue-100 text-blue-700"}`}>{log.method}</span></td>
                            <td className="p-2 font-mono">{log.endpoint}</td>
                            <td className="p-2"><span className={`${log.status_code < 300 ? "text-green-600" : "text-red-600"}`}>{log.status_code}</span></td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                </CardContent>
              </Card>
            )}
          </TabsContent>
        </Tabs>
      </div>

      {/* Create App Dialog */}
      <Dialog open={showCreate} onOpenChange={setShowCreate}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Register New App</DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div>
              <Label>App Name *</Label>
              <Input value={newApp.app_name} onChange={e => setNewApp(p => ({ ...p, app_name: e.target.value }))} placeholder="My DApp" />
            </div>
            <div>
              <Label>Description</Label>
              <Input value={newApp.app_description} onChange={e => setNewApp(p => ({ ...p, app_description: e.target.value }))} placeholder="A decentralized payment app" />
            </div>
            <div>
              <Label>App URL</Label>
              <Input value={newApp.app_url} onChange={e => setNewApp(p => ({ ...p, app_url: e.target.value }))} placeholder="https://mydapp.com" />
            </div>
            <div>
              <Label>Redirect URIs (comma-separated)</Label>
              <Input value={newApp.redirect_uris} onChange={e => setNewApp(p => ({ ...p, redirect_uris: e.target.value }))} placeholder="https://mydapp.com/callback" />
            </div>
            <Button className="w-full" onClick={createApp} disabled={creating || !newApp.app_name}>
              {creating ? "Creating..." : "Create App & Generate Keys"}
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
};

export default DeveloperDashboardPage;
