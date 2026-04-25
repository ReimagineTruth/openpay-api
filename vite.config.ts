import { defineConfig } from "vite";
import react from "@vitejs/plugin-react-swc";
import path from "path";
import { componentTagger } from "lovable-tagger";

// https://vitejs.dev/config/
export default defineConfig(({ mode }) => ({
  server: {
    host: "::",
    port: 8080,
    hmr: {
      overlay: false,
    },
  },
  plugins: [react(), mode === "development" && componentTagger()].filter(Boolean),
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
      buffer: "buffer",
      crypto: "crypto-browserify",
      stream: "stream-browserify",
      util: "util",
      assert: "assert",
      process: "process/browser",
      url: "url/",
      zlib: "browserify-zlib",
      http: "stream-http",
      https: "https-browserify",
      os: "os-browserify/browser",
    },
  },
  define: {
    global: 'globalThis',
    'process.env': '{}',
    process: 'process/browser',
    Buffer: 'Buffer',
  },
  optimizeDeps: {
    include: [
      'buffer',
      'process',
      'crypto-browserify',
      'stream-browserify',
      'util',
      'assert',
      'url',
      'zlib',
      'http',
      'https',
      'os',
    ],
  },
  build: {
    rollupOptions: {
      external: [],
      output: {
        globals: {
          buffer: 'Buffer',
          process: 'process',
          crypto: 'crypto',
          stream: 'stream',
          util: 'util',
          assert: 'assert',
          url: 'url',
          zlib: 'zlib',
          http: 'http',
          https: 'https',
          os: 'os',
        },
      },
    },
  },
}));
