import path from "node:path";
import { fileURLToPath } from "node:url";
import { defineConfig } from "vite";

const dir = path.dirname(fileURLToPath(import.meta.url));

export default defineConfig({
  root: dir,
  build: {
    outDir: path.join(dir, "../public/store"),
    emptyOutDir: false,
    rollupOptions: {
      input: path.join(dir, "main.ts"),
      output: {
        entryFileNames: "assets/[name].js",
        assetFileNames: "assets/[name][extname]"
      }
    }
  }
});
