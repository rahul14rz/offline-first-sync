// Adds demo products. Safe to run more than once: unchanged products are not written again.
import { loadConfig } from "./config.js";
import { createDb, createPool, runMigrations } from "./db.js";
import { upsertProduct } from "./products.js";

const demoProducts = [
  { sku: "APL-1L", name: "Apple juice 1L", priceCents: 250 },
  { sku: "BRD-WHT", name: "White bread loaf", priceCents: 180 },
  { sku: "RCE-5KG", name: "Basmati rice 5kg", priceCents: 1299 },
];

const config = loadConfig(process.env);
const pool = createPool(config.databaseUrl);
try {
  await runMigrations(pool);
  const db = createDb(pool);
  for (const product of demoProducts) {
    const id = await upsertProduct(db, product);
    console.log(`${product.sku} ${id}`);
  }
} finally {
  await pool.end();
}
