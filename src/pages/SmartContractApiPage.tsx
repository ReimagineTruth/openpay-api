import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { ArrowLeft, Code2, Key, Shield, Zap, Globe, BookOpen, Terminal, Copy, ChevronDown, ChevronRight, CheckCircle2, ArrowRight } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { toast } from "sonner";

const API_BASE = `https://${import.meta.env.VITE_SUPABASE_PROJECT_ID}.supabase.co/functions/v1/smart-contract-api`;

const endpoints = [
  { method: "GET", path: "/health", desc: "Check API status", auth: "Public", scopes: [], example: '// No auth required\nconst res = await fetch(`${API_BASE}/health`);\nconst data = await res.json();\n// { status: "ok", version: "1.0.0", timestamp: "..." }' },
  { method: "GET", path: "/balance", desc: "Get user wallet balance", auth: "OAuth / Bearer", scopes: ["read:balance"], example: 'const res = await fetch(`${API_BASE}/balance`, {\n  headers: {\n    "x-client-id": CLIENT_ID,\n    "x-api-key": API_KEY,\n    "Authorization": `Bearer ${userToken}`\n  }\n});\nconst { balance, currency } = await res.json();' },
  { method: "GET", path: "/profile", desc: "Get user profile & account info", auth: "OAuth / Bearer", scopes: ["read:profile"], example: 'const res = await fetch(`${API_BASE}/profile`, {\n  headers: { "Authorization": `Bearer ${token}` }\n});\nconst { profile, account } = await res.json();' },
  { method: "GET", path: "/transactions", desc: "List user transactions (paginated)", auth: "OAuth / Bearer", scopes: ["read:transactions"], example: 'const res = await fetch(`${API_BASE}/transactions?limit=20&offset=0`, {\n  headers: { "Authorization": `Bearer ${token}` }\n});\nconst { transactions, pagination } = await res.json();' },
  { method: "POST", path: "/send", desc: "Send OUSD to another user", auth: "OAuth / Bearer", scopes: ["write:send"], example: 'const res = await fetch(`${API_BASE}/send`, {\n  method: "POST",\n  headers: {\n    "Authorization": `Bearer ${token}`,\n    "Content-Type": "application/json"\n  },\n  body: JSON.stringify({\n    receiver_id: "user-uuid",\n    amount: 10.00,\n    note: "Payment via MyApp"\n  })\n});\nconst { success, transaction_id } = await res.json();' },
  { method: "GET", path: "/invoices", desc: "List user invoices", auth: "OAuth / Bearer", scopes: ["read:invoices"], example: 'const res = await fetch(`${API_BASE}/invoices`, {\n  headers: { "Authorization": `Bearer ${token}` }\n});\nconst { invoices } = await res.json();' },
  { method: "POST", path: "/invoices", desc: "Create a new invoice", auth: "OAuth / Bearer", scopes: ["write:invoices"], example: 'const res = await fetch(`${API_BASE}/invoices`, {\n  method: "POST",\n  headers: {\n    "Authorization": `Bearer ${token}`,\n    "Content-Type": "application/json"\n  },\n  body: JSON.stringify({\n    recipient_id: "user-uuid",\n    amount: 50.00,\n    description: "Consulting fee",\n    due_date: "2026-05-01"\n  })\n});' },
  { method: "GET", path: "/ledger", desc: "View public ledger events", auth: "API Key / Bearer", scopes: [], example: 'const res = await fetch(`${API_BASE}/ledger?limit=50`, {\n  headers: { "Authorization": `Bearer ${token}` }\n});\nconst { events } = await res.json();' },
  { method: "GET", path: "/currencies", desc: "List supported currencies & rates", auth: "Public", scopes: [], example: '// No auth required\nconst res = await fetch(`${API_BASE}/currencies`);\nconst { currencies } = await res.json();' },
  { method: "POST", path: "/lookup", desc: "Look up user by username or account number", auth: "API Key / Bearer", scopes: [], example: 'const res = await fetch(`${API_BASE}/lookup`, {\n  method: "POST",\n  headers: {\n    "Authorization": `Bearer ${token}`,\n    "Content-Type": "application/json"\n  },\n  body: JSON.stringify({ username: "john_doe" })\n});\nconst { user } = await res.json();' },
  { method: "POST", path: "/apps/register", desc: "Register a new developer app", auth: "Bearer", scopes: [], example: 'const res = await fetch(`${API_BASE}/apps/register`, {\n  method: "POST",\n  headers: {\n    "Authorization": `Bearer ${token}`,\n    "Content-Type": "application/json"\n  },\n  body: JSON.stringify({\n    app_name: "My DApp",\n    app_url: "https://mydapp.com",\n    scopes: ["read:balance", "write:send"]\n  })\n});\nconst { app } = await res.json();\n// Save app.client_secret immediately!' },
  { method: "POST", path: "/pi-rpc", desc: "Pi Testnet RPC proxy (JSON-RPC)", auth: "Public", scopes: [], example: `// Pi Testnet RPC — no auth required\nconst res = await fetch(\`\${API_BASE}/pi-rpc\`, {\n  method: "POST",\n  headers: { "Content-Type": "application/json" },\n  body: JSON.stringify({\n    jsonrpc: "2.0",\n    id: 1,\n    method: "getHealth"\n  })\n});\nconst data = await res.json();\n// { jsonrpc: "2.0", id: 1, result: "healthy" }` },
  { method: "POST", path: "/pi-rpc/mainnet", desc: "Pi Mainnet RPC proxy (JSON-RPC)", auth: "Public", scopes: [], example: `// Pi Mainnet RPC\nconst res = await fetch(\`\${API_BASE}/pi-rpc/mainnet\`, {\n  method: "POST",\n  headers: { "Content-Type": "application/json" },\n  body: JSON.stringify({\n    jsonrpc: "2.0",\n    id: 1,\n    method: "getHealth"\n  })\n});\nconst data = await res.json();` },
];

const scopeList = [
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
  const methodColor = ep.method === "GET" ? "text-green-600 bg-green-100 dark:bg-green-900/30 dark:text-green-400" : "text-blue-600 bg-blue-100 dark:bg-blue-900/30 dark:text-blue-400";

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
          <CodeBlock code={ep.example} language="javascript" />
        </div>
      )}
    </div>
  );
};

const SmartContractApiPage = () => {
  const navigate = useNavigate();

  const tutorialSteps = [
    {
      title: "Create an OpenPay Account",
      desc: "Sign up at OpenPay and verify your email. You'll need a fully verified account to register developer apps.",
    },
    {
      title: "Go to Developer Dashboard",
      desc: 'Navigate to the Developer Dashboard from Menu → Developer Dashboard, or visit /developer-dashboard directly.',
    },
    {
      title: "Register Your App",
      desc: 'Click "+ New App" and fill in your app name, description, URL, and redirect URIs. Select the scopes your app needs.',
    },
    {
      title: "Save Your Credentials",
      desc: "After creating your app, you'll receive a client_id and client_secret. Save the secret immediately — it won't be shown again.",
    },
    {
      title: "Authenticate Users (OAuth Flow)",
      desc: "Redirect users to OpenPay's auth page. After consent, you'll receive an access token scoped to the permissions the user granted.",
    },
    {
      title: "Make API Calls",
      desc: "Use your client_id + api_key for server calls, or include the user's Bearer token for user-scoped endpoints like balance and send.",
    },
    {
      title: "Handle Webhooks (Optional)",
      desc: "Register a webhook URL in your app settings to receive real-time events like transaction.completed and invoice.paid.",
    },
    {
      title: "Go Live",
      desc: "Test in sandbox mode first. When ready, your app is automatically live. Monitor usage via the API Logs tab in Developer Dashboard.",
    },
  ];

  return (
    <div className="min-h-screen bg-background">
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
          <div className="flex justify-center gap-3 pt-2 flex-wrap">
            <Button onClick={() => navigate("/developer-dashboard")} className="gap-2">
              <Terminal className="h-4 w-4" /> Developer Dashboard
            </Button>
            <Button variant="outline" className="gap-2" onClick={() => document.getElementById("tutorial")?.scrollIntoView({ behavior: "smooth" })}>
              <BookOpen className="h-4 w-4" /> Setup Guide
            </Button>
            <Button variant="outline" className="gap-2" onClick={() => document.getElementById("endpoints")?.scrollIntoView({ behavior: "smooth" })}>
              <Code2 className="h-4 w-4" /> API Reference
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

        {/* Step-by-Step Tutorial */}
        <div id="tutorial" className="space-y-4">
          <h3 className="text-xl font-bold text-foreground flex items-center gap-2">
            <BookOpen className="h-5 w-5 text-primary" /> Step-by-Step Setup Guide
          </h3>
          <p className="text-sm text-muted-foreground">Follow these steps to connect your app to OpenPay and start accepting payments.</p>
          <div className="space-y-3">
            {tutorialSteps.map((step, i) => (
              <Card key={i} className="border-border">
                <CardContent className="p-4 flex items-start gap-4">
                  <div className="flex-shrink-0 w-8 h-8 rounded-full bg-primary text-primary-foreground flex items-center justify-center text-sm font-bold">
                    {i + 1}
                  </div>
                  <div>
                    <p className="font-semibold text-foreground text-sm">{step.title}</p>
                    <p className="text-xs text-muted-foreground mt-1">{step.desc}</p>
                  </div>
                </CardContent>
              </Card>
            ))}
          </div>
        </div>

        {/* Integration Example */}
        <div className="space-y-4">
          <h3 className="text-xl font-bold text-foreground">Full Integration Example</h3>
          <Card>
            <CardHeader><CardTitle className="text-base">Node.js / JavaScript SDK Example</CardTitle></CardHeader>
            <CardContent className="space-y-3">
              <CodeBlock code={`// openpay-sdk.js — Minimal OpenPay API wrapper
const API_BASE = "https://${import.meta.env.VITE_SUPABASE_PROJECT_ID}.supabase.co/functions/v1/smart-contract-api";

class OpenPayClient {
  constructor(clientId, apiKey) {
    this.clientId = clientId;
    this.apiKey = apiKey;
    this.userToken = null;
  }

  setUserToken(token) {
    this.userToken = token;
  }

  async _request(path, options = {}) {
    const headers = {
      "Content-Type": "application/json",
      "x-client-id": this.clientId,
      "x-api-key": this.apiKey,
    };
    if (this.userToken) {
      headers["Authorization"] = \`Bearer \${this.userToken}\`;
    }
    const res = await fetch(\`\${API_BASE}/\${path}\`, {
      ...options,
      headers: { ...headers, ...options.headers },
    });
    return res.json();
  }

  // Public endpoints
  health() { return this._request("health"); }
  currencies() { return this._request("currencies"); }

  // User-scoped endpoints (requires userToken)
  getBalance() { return this._request("balance"); }
  getProfile() { return this._request("profile"); }
  getTransactions(limit = 50, offset = 0) {
    return this._request(\`transactions?limit=\${limit}&offset=\${offset}\`);
  }
  getInvoices() { return this._request("invoices"); }

  // Write operations
  send(receiverId, amount, note = "") {
    return this._request("send", {
      method: "POST",
      body: JSON.stringify({ receiver_id: receiverId, amount, note }),
    });
  }
  createInvoice(recipientId, amount, description = "", dueDate = null) {
    return this._request("invoices", {
      method: "POST",
      body: JSON.stringify({
        recipient_id: recipientId,
        amount,
        description,
        due_date: dueDate,
      }),
    });
  }
  lookupUser(username) {
    return this._request("lookup", {
      method: "POST",
      body: JSON.stringify({ username }),
    });
  }
}

// Usage:
const openpay = new OpenPayClient("opc_your_client_id", "ops_your_api_key");
openpay.setUserToken("user_access_token");

const balance = await openpay.getBalance();
console.log("Balance:", balance);

const result = await openpay.send("recipient-uuid", 25.00, "Coffee payment");
console.log("Sent:", result);`} language="javascript" />
            </CardContent>
          </Card>
        </div>

        {/* Tabs: Auth, Scopes, Webhooks */}
        <Tabs defaultValue="auth" className="space-y-4">
          <TabsList className="w-full justify-start bg-muted/50 rounded-xl p-1 flex-wrap">
            <TabsTrigger value="auth">Authentication</TabsTrigger>
            <TabsTrigger value="scopes">Scopes</TabsTrigger>
            <TabsTrigger value="webhooks">Webhooks</TabsTrigger>
            <TabsTrigger value="errors">Error Handling</TabsTrigger>
          </TabsList>

          <TabsContent value="auth" className="space-y-4">
            <Card>
              <CardHeader><CardTitle className="text-base">Authentication Methods</CardTitle></CardHeader>
              <CardContent className="space-y-4 text-sm text-muted-foreground">
                <div className="space-y-2">
                  <p className="font-semibold text-foreground">1. API Keys (Server-to-Server)</p>
                  <p>Pass <code className="text-xs bg-muted px-1 rounded">x-client-id</code> and <code className="text-xs bg-muted px-1 rounded">x-api-key</code> headers. Used for endpoints that don't need user context (health, ledger, currencies).</p>
                  <CodeBlock code={`curl -X GET "${API_BASE}/ledger" \\
  -H "x-client-id: opc_your_client_id" \\
  -H "x-api-key: ops_your_api_key"`} />
                </div>
                <div className="space-y-2">
                  <p className="font-semibold text-foreground">2. OAuth 2.0 (User-Authorized)</p>
                  <p>For user-scoped data (balance, send, invoices), include a <code className="text-xs bg-muted px-1 rounded">Authorization: Bearer</code> token along with your app credentials. The user grants specific scopes.</p>
                  <CodeBlock code={`curl -X GET "${API_BASE}/balance" \\
  -H "x-client-id: opc_your_client_id" \\
  -H "x-api-key: ops_your_api_key" \\
  -H "Authorization: Bearer user_access_token"`} />
                </div>
                <div className="space-y-2">
                  <p className="font-semibold text-foreground">3. Direct Bearer Token</p>
                  <p>OpenPay users can call the API directly with their session token for personal integrations (no API key needed).</p>
                  <CodeBlock code={`curl -X GET "${API_BASE}/profile" \\
  -H "Authorization: Bearer your_session_token"`} />
                </div>
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="scopes" className="space-y-4">
            <Card>
              <CardHeader><CardTitle className="text-base">Available Scopes</CardTitle></CardHeader>
              <CardContent>
                <div className="space-y-2">
                  {scopeList.map(s => (
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
                <p>Register a webhook URL in your Developer Dashboard to receive real-time notifications.</p>
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

          <TabsContent value="errors" className="space-y-4">
            <Card>
              <CardHeader><CardTitle className="text-base">Error Codes</CardTitle></CardHeader>
              <CardContent>
                <div className="space-y-2 text-sm">
                  {[
                    { code: 400, msg: "Bad Request", desc: "Missing or invalid parameters" },
                    { code: 401, msg: "Unauthorized", desc: "Missing or invalid auth credentials" },
                    { code: 403, msg: "Forbidden", desc: "User authorization required for this endpoint" },
                    { code: 404, msg: "Not Found", desc: "Unknown endpoint or resource" },
                    { code: 405, msg: "Method Not Allowed", desc: "Wrong HTTP method for this endpoint" },
                    { code: 500, msg: "Server Error", desc: "Internal error, retry or contact support" },
                  ].map(e => (
                    <div key={e.code} className="flex items-center gap-3 p-2 rounded bg-muted/30">
                      <span className={`font-bold text-xs px-2 py-0.5 rounded ${e.code < 400 ? "bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400" : e.code < 500 ? "bg-yellow-100 text-yellow-700 dark:bg-yellow-900/30 dark:text-yellow-400" : "bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400"}`}>{e.code}</span>
                      <span className="font-medium text-foreground">{e.msg}</span>
                      <span className="text-muted-foreground ml-auto text-xs">{e.desc}</span>
                    </div>
                  ))}
                </div>
                <div className="mt-4">
                  <CodeBlock code={`// All error responses follow this format:
{
  "error": "Descriptive error message"
}`} language="json" />
                </div>
              </CardContent>
            </Card>
          </TabsContent>
        </Tabs>

        {/* API Endpoints Reference */}
        <div id="endpoints" className="space-y-4">
          <h3 className="text-xl font-bold text-foreground">API Endpoints</h3>
          <p className="text-sm text-muted-foreground">
            Base URL: <code className="bg-muted px-2 py-0.5 rounded text-xs text-foreground">{API_BASE}</code>
          </p>
          <div className="space-y-2">
            {endpoints.map(ep => <EndpointRow key={ep.method + ep.path} ep={ep} />)}
          </div>
        </div>

        {/* CTA */}
        <div className="text-center py-8 space-y-3 border-t border-border">
          <p className="text-lg font-semibold text-foreground">Ready to integrate?</p>
          <p className="text-sm text-muted-foreground">Create your developer app and start building with OpenPay today.</p>
          <div className="flex justify-center gap-3 flex-wrap">
            <Button size="lg" onClick={() => navigate("/developer-dashboard")} className="gap-2">
              <Key className="h-4 w-4" /> Go to Developer Dashboard
            </Button>
          </div>
        </div>
      </div>
    </div>
  );
};

export default SmartContractApiPage;
