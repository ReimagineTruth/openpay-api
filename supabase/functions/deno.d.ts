declare global {
  const Deno: {
    env: {
      get(key: string): string | undefined;
    };
  };
}
export {};
