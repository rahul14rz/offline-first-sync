import { sql } from "drizzle-orm";
import type { Db } from "./db.js";
import { products } from "./schema.js";
import { writeSynced } from "./sync/changeLog.js";
import type { ProductData } from "./sync/protocol.js";

/** Creates the product with this SKU, or updates it. Returns its id. */
export async function upsertProduct(db: Db, product: ProductData): Promise<string> {
  return writeSynced(db, async (tx, append) => {
    const [row] = await tx
      .insert(products)
      .values({ ...product, version: 1 })
      .onConflictDoUpdate({
        target: products.sku,
        set: {
          name: product.name,
          priceCents: product.priceCents,
          version: sql`${products.version} + 1`,
          updatedAt: sql`now()`,
        },
      })
      .returning({ id: products.id, version: products.version });
    if (!row) throw new Error(`upsert of product ${product.sku} returned no row`);

    await append({
      entity: "product",
      entityId: row.id,
      op: "upsert",
      version: row.version,
      data: product,
    });
    return row.id;
  });
}
