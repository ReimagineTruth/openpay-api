import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { ArrowLeft, Code2, Key, Shield, Zap, Globe, BookOpen, Terminal, Copy, ChevronDown, ChevronRight } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { toast } from "sonner";

const BASE_URL = `${window.location.origin}`;

const endpoints = [
  { method: "GET", path: "/health", desc: "Check API status", auth: "API Key", scopes: [] },
  { method: "GET", path: "/balance", desc: "Get user wallet balance", auth: "OAuth", scopes: ["read:balance"] },
  { method: "GET", path: "/profile", desc: "Get user profile & account info", auth: "OAuth", scopes: ["read:profile"] },
  { method: "GET", path: "/transactions", desc: "List user transactions (paginated)", auth: "OAuth", scopes: ["read:transactions"] },
  { method: "POST", path: "/send", desc: "Send OUSD to another user", auth: "OAuth", scopes: ["write:send"] },
  { method: "GET", path: "/invoices", desc: "List user invoices", auth: "OAuth", scopes: ["read:invoices"] },
  { method: "POST", path: "/invoices", desc: "Create a new invoice", auth: "OAuth", scopes: ["write:invoices"] },
  { method: "GET", path: "/ledger", desc: "View public ledger events", auth: "API Key", scopes: [] },
  { method: "GET", path: "/currencies", desc: "List supported currencies & rates", auth: "Public", scopes: [] },
  { method: "POST", path: "/apps/register", desc: "Register a new developer app", auth: "Bearer", scopes: [] },
];

const scopes = [
  { scope: "read:balance", desc: "View wallet balance" },
  { scope: "read:profile", desc: "View user profile and account info" },
  { scope: "read:transactions", desc: "View transaction history" },
  { scope: "write:send", desc: "Send payments on behalf of user" },
  { scope: "read:invoices", desc: "View invoices" },
  { scope: "write:invoices", desc: "Create invoices" },
];

const CodeBlock = ({ code, language = "bash" }: { code: string; language?: string }) => (
  <div className="relative rounded-lg bg-muted/80 border border-border p-4 font-mono text-xs overflow-x-auto">
    <button
      className="absolute top-2 right-2 text-muted-foreground hover:text-foreground"
      onClick={() => { navigator.clipboard.writeText(code); toast.success("Copied!"); }}
    >
      <Copy className="h-3.5 w-3.5" />
    </button>
    <pre className="text-foreground whitespace-pre-wrap">{code}</pre>
  </div>
);

const EndpointRow = ({ ep }: { ep: typeof endpoints[0] }) => {
  const [open, setOpen] = useState(false);
  const methodColor = ep.method === "GET" ? "text-green-600 bg-green-100" : "text-blue-600 bg-blue-100";

  return (
    <div className="border border-border rounded-lg overflow-hidden">
      <button onClick={() => setOpen(!open)} className="w-full flex items-center gap-3 p-3 hover:bg-muted/50 transition-colors text-left">
        {open ? <ChevronDown className="h-4 w-4 text-muted-foreground shrink-0" /> : <ChevronRight className="h-4 w-4 text-muted-foreground shrink-0" />}
        <span className={`px-2 py-0.5 rounded text-[11px] font-bold ${methodColor}`}>{ep.method}</span>
        <code className="text-sm font-semibold text-foreground">{ep.path}</code>
        <span className="text-xs text-muted-foreground ml-auto hidden sm:inline">{ep.desc}</span>
      </button>
      {open && (
        <div className="px-4 pb-4 border-t border-border bg-muted/20 space-y-3">
          <p className="text-sm text-muted-foreground pt-3">{ep.desc}</p>
          <div className="flex flex-wrap gap-2 text-xs">
            <span className="px-2 py-0.5 rounded bg-primary/10 text-primary font-medium">Auth: {ep.auth}</span>
            {ep.scopes.map(s => (
              <span key={s} className="px-2 py-0.5 rounded bg-accent text-accent-foreground font-mono">{s}</span>
            ))}
          </div>
          <CodeBlock code={`curl -X ${ep.method} "${BASE_URL}/functions/v1/smart-contract-api${ep.path}" \\
  -H "x-client-id: YOUR_CLIENT_ID" \\
  -H "x-api-key: YOUR_API_KEY" \\
  -H "Authorization: Bearer USER_ACCESS_TOKEN"`} />
        </div>
      )}
    </div>
  );
};

const SmartContractApiPage = () => {
  const navigate = useNavigate();

  return (
    <div className="min-h-screen bg-background">
      {/* Header */}
      <div className="sticky top-0 z-20 bg-background/95 backdrop-blur border-b border-border px-4 py-3">
        <div className="flex items-center gap-3 max-w-5xl mx-auto">
          <button onClick={() => navigate(-1)}><ArrowLeft className="h-5 w-5 text-foreground" /></button>
          <Code2 className="h-5 w-5 text-primary" />
          <h1 className="text-lg font-bold text-foreground">OpenPay Smart Contract API</h1>
        </div>
      </div>

      <div className="max-w-5xl mx-auto px-4 py-8 space-y-8">
        {/* Hero */}
        <div className="text-center space-y-3">
          <h2 className="text-3xl font-bold text-foreground">Connect Your App to OpenPay</h2>
          <p className="text-muted-foreground max-w-2xl mx-auto">
            The OpenPay Smart Contract API lets third-party apps read balances, send payments, 
            create invoices, and interact with the public ledger — all secured by OAuth 2.0 and API keys.
          </p>
          <div className="flex justify-center gap-3 pt-2">
            <Button onClick={() => navigate("/developer-dashboard")} className="gap-2">
              <Terminal className="h-4 w-4" /> Developer Dashboard
            </Button>
            <Button variant="outline" className="gap-2" onClick={() => document.getElementById("endpoints")?.scrollIntoView({ behavior: "smooth" })}>
              <BookOpen className="h-4 w-4" /> View Endpoints
            </Button>
          </div>
        </div>

        {/* Features */}
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          {[
            { icon: Shield, title: "OAuth 2.0", desc: "User-authorized access with granular scopes" },
            { icon: Key, title: "API Keys", desc: "Client ID + secret for server-to-server calls" },
            { icon: Zap, title: "Real-time", desc: "Webhooks for transaction and payment events" },
            { icon: Globe, title: "Public Ledger", desc: "Read-only access to OpenPay's public ledger" },
          ].map(({ icon: Icon, title, desc }) => (
            <Card key={title} className="border-border">
              <CardContent className="p-4 flex items-start gap-3">
                <div className="rounded-lg bg-primary/10 p-2"><Icon className="h-5 w-5 text-primary" /></div>
                <div>
                  <p className="font-semibold text-foreground text-sm">{title}</p>
                  <p className="text-xs text-muted-foreground">{desc}</p>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>

        {/* Tabs: Docs */}
        <Tabs defaultValue="quickstart" className="space-y-4">
          <TabsList className="w-full justify-start bg-muted/50 rounded-xl p-1">
            <TabsTrigger value="quickstart">Quick Start</TabsTrigger>
            <TabsTrigger value="auth">Authentication</TabsTrigger>
            <TabsTrigger value="scopes">Scopes</TabsTrigger>
            <TabsTrigger value="webhooks">Webhooks</TabsTrigger>
          </TabsList>

          <TabsContent value="quickstart" className="space-y-4">
            <Card>
              <CardHeader><CardTitle className="text-base">1. Register Your App</CardTitle></CardHeader>
              <CardContent className="space-y-3">
                <p className="text-sm text-muted-foreground">Create a developer app to get your client_id and client_secret.</p>
                <CodeBlock code={`curl -X POST "${BASE_URL}/functions/v1/smart-contract-api/apps/register" \\
  -H "Authorization: Bearer YOUR_OPENPAY_TOKEN" \\
  -H "Content-Type: application/json" \\
  -d '{
    "app_name": "My DApp",
    "app_url": "https://mydapp.com",
    "scopes": ["read:balance", "read:profile", "write:send"]
  }'`} />
              </CardContent>
            </Card>
            <Card>
              <CardHeader><CardTitle className="text-base">2. Authenticate & Call Endpoints</CardTitle></CardHeader>
              <CardContent className="space-y-3">
                <p className="text-sm text-muted-foreground">Use your client credentials to make API calls.</p>
                <CodeBlock code={`// Check user balance
const res = await fetch("${BASE_URL}/functions/v1/smart-contract-api/balance", {
  headers: {
    "x-client-id": "opc_abc123...",
    "x-api-key": "ops_def456...",
    "Authorization": "Bearer user_access_token"
  }
});
const { balance, currency } = await res.json();
console.log(\`Balance: \${balance} \${currency}\`);`} language="javascript" />
              </CardContent>
            </Card>
            <Card>
              <CardHeader><CardTitle className="text-base">3. Send a Payment</CardTitle></CardHeader>
              <CardContent>
                <CodeBlock code={`const res = await fetch("${BASE_URL}/functions/v1/smart-contract-api/send", {
  method: "POST",
  headers: {
    "x-client-id": "opc_abc123...",
    "x-api-key": "ops_def456...",
    "Authorization": "Bearer user_access_token",
    "Content-Type": "application/json"
  },
  body: JSON.stringify({
    receiver_id: "recipient-uuid",
    amount: 10.00,
    note: "Payment from MyDApp"
  })
});
const { success, transaction_id } = await res.json();`} language="javascript" />
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="auth" className="space-y-4">
            <Card>
              <CardHeader><CardTitle className="text-base">Authentication Methods</CardTitle></CardHeader>
              <CardContent className="space-y-4 text-sm text-muted-foreground">
                <div>
                  <p className="font-semibold text-foreground mb-1">API Keys (Server-to-Server)</p>
                  <p>Pass <code className="text-xs bg-muted px-1 rounded">x-client-id</code> and <code className="text-xs bg-muted px-1 rounded">x-api-key</code> headers for endpoints that don't require user context (health, ledger, currencies).</p>
                </div>
                <div>
                  <p className="font-semibold text-foreground mb-1">OAuth 2.0 (User-Authorized)</p>
                  <p>For endpoints that operate on user data (balance, send, invoices), include a <code className="text-xs bg-muted px-1 rounded">Authorization: Bearer</code> token obtained via OAuth consent flow. The user grants specific scopes to your app.</p>
                </div>
                <div>
                  <p className="font-semibold text-foreground mb-1">Direct Bearer Token</p>
                  <p>OpenPay users can also call the API directly with their session token for personal integrations.</p>
                </div>
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="scopes" className="space-y-4">
            <Card>
              <CardHeader><CardTitle className="text-base">Available Scopes</CardTitle></CardHeader>
              <CardContent>
                <div className="space-y-2">
                  {scopes.map(s => (
                    <div key={s.scope} className="flex items-center gap-3 p-2 rounded-lg bg-muted/30">
                      <code className="text-xs font-bold text-primary bg-primary/10 px-2 py-0.5 rounded">{s.scope}</code>
                      <span className="text-sm text-muted-foreground">{s.desc}</span>
                    </div>
                  ))}
                </div>
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="webhooks" className="space-y-4">
            <Card>
              <CardHeader><CardTitle className="text-base">Webhook Events</CardTitle></CardHeader>
              <CardContent className="space-y-3 text-sm text-muted-foreground">
                <p>Register a webhook URL to receive real-time notifications when events occur.</p>
                <div className="space-y-1">
                  {["transaction.completed", "transaction.received", "invoice.created", "invoice.paid", "payment.received"].map(e => (
                    <div key={e} className="flex items-center gap-2 p-2 rounded bg-muted/30">
                      <Zap className="h-3 w-3 text-primary" />
                      <code className="text-xs font-mono text-foreground">{e}</code>
                    </div>
                  ))}
                </div>
                <CodeBlock code={`// Webhook payload example
{
  "event": "transaction.completed",
  "data": {
    "transaction_id": "uuid",
    "sender_id": "uuid",
    "receiver_id": "uuid",
    "amount": 25.00,
    "currency": "OUSD",
    "timestamp": "2026-04-01T09:00:00Z"
  },
  "signature": "hmac_sha256_signature"
}`} language="json" />
              </CardContent>
            </Card>
          </TabsContent>
        </Tabs>

        {/* Endpoints */}
        <div id="endpoints" className="space-y-4">
          <h3 className="text-xl font-bold text-foreground">API Endpoints</h3>
          <div className="space-y-2">
            {endpoints.map(ep => <EndpointRow key={ep.method + ep.path} ep={ep} />)}
          </div>
        </div>

        {/* CTA */}
        <div className="text-center py-8 space-y-3">
          <p className="text-muted-foreground">Ready to integrate?</p>
          <Button size="lg" onClick={() => navigate("/developer-dashboard")} className="gap-2">
            <Key className="h-4 w-4" /> Go to Developer Dashboard
          </Button>
        </div>
      </div>
    </div>
  );
};

export default SmartContractApiPage;
