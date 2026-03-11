import { PropsWithChildren, useEffect, useState } from "react";

const PageTransition = ({ children }: PropsWithChildren) => {
  const [ready, setReady] = useState(false);
  useEffect(() => {
    const id = window.setTimeout(() => setReady(true), 0);
    return () => window.clearTimeout(id);
  }, []);
  return (
    <div
      className={`transition-opacity duration-500 ease-[cubic-bezier(0.16,1,0.3,1)] ${
        ready ? "opacity-100" : "opacity-0"
      }`}
    >
      {children}
    </div>
  );
};

export default PageTransition;
