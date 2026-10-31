import { eq, sql } from "drizzle-orm";
import type { Db } from "./db.js";
import { products } from "./schema.js";
import { writeSynced } from "./sync/changeLog.js";
import type { ProductData } from "./sync/protocol.js";

/**
 * Creates the product with this SKU, or updates it. Returns its id. Writing a product with the
 * same name and price again changes nothing and adds no change to the log.
 */
export async function upsertProduct(db: Db, product: ProductData): Promise<string> {
  return writeSynced(db, async (tx, append) => {
    const [written] = await tx
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
        setWhere: sql`(${products.name}, ${products.priceCents}) is distinct from (excluded.name, excluded.price_cents)`,
      })
      .returning({ id: products.id, version: products.version });

    if (!written) {
      const [unchanged] = await tx
        .select({ id: products.id })
        .from(products)
        .where(eq(products.sku, product.sku));
      if (!unchanged) throw new Error(`product ${product.sku} vanished during upsert`);
      return unchanged.id;
    }

    await append({
      entity: "product",
      entityId: written.id,
      op: "upsert",
      version: written.version,
      data: product,
    });
    return written.id;
  });
}
