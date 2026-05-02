import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  async rewrites() {
    return [
      {
        source: "/solvers/:method",
        destination: "/solve?method=:method",
      },
    ];
  },
};

export default nextConfig;
