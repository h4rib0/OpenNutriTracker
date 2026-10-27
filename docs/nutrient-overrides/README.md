# Nutrient Overrides – Persistent User-Enriched Nutrition Data

This document describes the **Nutrient Overrides** feature, which lets users
permanently save manually entered nutritional values for food products that
have incomplete or missing data.

---

## Problem

FDC and OpenFoodFacts products sometimes have no nutritional values. The user
can enter them manually in the Edit screen, and the intake is saved correctly.
However, the next time the same product is searched, the values are gone —
the search cache retains the original (empty) remote version.

---

## Solution

Two complementary layers of persistence:

### Layer 1 – Local cache (always active)

When the user saves manually entered nutritional values for an OFF or FDC
product, the enriched version is written back to the local Hive search cache
(`RemoteSearchCacheDataSource`). Subsequent searches return the enriched
version from the cache.

The cache also protects user-entered data during re-searches: if a fresh
remote result has no kcal data but the cached entry already has kcal,
`cacheFromSearch` keeps the existing (user-enriched) entry instead of
overwriting it.

### Layer 2 – Supabase backup (opt-in)

Users can enable **"Nährwert-Ergänzungen sichern"** in Settings. When active:

- Manually entered values are written to the `user_nutrient_overrides` table
  in Supabase (scoped to the device's anonymous Supabase user).
- On app startup, overrides are fetched from Supabase and merged into the
  local cache — so data survives a local cache clear (Settings → Cache
  löschen).

Authentication is fully transparent: the app signs in anonymously via
Supabase Auth on first launch. No account or email is required.

**Known limitation:** After a full app reinstall the local cache is empty.
The startup sync cannot apply overrides to non-existent cache entries. The
user must search for the product once; from then on the local cache entry
exists and the override is applied on the next startup.

---

## Supabase Setup

Run the following SQL once in the **Supabase SQL Editor** of your project:

```sql
CREATE TABLE IF NOT EXISTS user_nutrient_overrides (
    id           BIGSERIAL PRIMARY KEY,
    user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    lookup_key   TEXT NOT NULL,
    meal_source  TEXT NOT NULL,
    kcal_100     NUMERIC,
    carbs_100    NUMERIC,
    fat_100      NUMERIC,
    proteins_100 NUMERIC,
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, meal_source, lookup_key)
);

ALTER TABLE user_nutrient_overrides ENABLE ROW LEVEL SECURITY;

CREATE POLICY "own data only" ON user_nutrient_overrides
    FOR ALL
    USING  (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);
```

### Column reference

| Column | Type | Description |
|---|---|---|
| `user_id` | UUID | Supabase anonymous user ID — scopes data per device |
| `lookup_key` | TEXT | Barcode when available, otherwise the product name |
| `meal_source` | TEXT | `off` (OpenFoodFacts) or `fdc` (USDA FoodData Central) |
| `kcal_100` | NUMERIC | Energy per 100 g/ml in kcal |
| `carbs_100` | NUMERIC | Carbohydrates per 100 g/ml in g |
| `fat_100` | NUMERIC | Fat per 100 g/ml in g |
| `proteins_100` | NUMERIC | Protein per 100 g/ml in g |
| `updated_at` | TIMESTAMPTZ | Last write timestamp |

RLS is enabled — each user can only read and write their own rows.

---

## App Architecture

| Component | Role |
|---|---|
| `NutrientOverrideDataSource` | Supabase client wrapper — `upsert()` and `fetchAll()` |
| `RemoteSearchCacheDataSource` | Local Hive cache; `cacheFromSearch()` protects user-enriched entries |
| `EditMealBloc.updateCachedMealNutrients()` | Called from `edit_meal_screen.dart` after saving a non-custom meal |
| `ConfigEntity.syncNutrientsToSupabase` | Feature flag (HiveField 16, default `false`) |
| `_initSupabaseSync()` in `main.dart` | Startup: anonymous sign-in + override restore |
