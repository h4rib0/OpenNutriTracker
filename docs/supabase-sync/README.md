# Supabase setup (fork)

The app talks to one Supabase project — the one in `.env`
(`SUPABASE_PROJECT_URL`, `SUPABASE_PROJECT_ANON_KEY`). In this fork that
project holds two independent things.

## 1. Food search backend (upstream)

Food search uses upstream's multi-source backend (`food_summary`,
`food_translation` and the search RPCs; FDC + BLS with native German names).
Set it up, or refresh the data, with:

```bash
bash tools/supabase/setup-food-backend.sh
```

The script clones
[OpenNutriTracker-Backend](https://github.com/simonoppowa/OpenNutriTracker-Backend),
asks for the database password (user and pooler host come from `.env` /
are detected per region) and runs its pipeline. It only creates and refills
the backend's own tables. See upstream's `docs/supabase-self-hosting.md` for
what the app reads.

## 2. Backup of the user's own data (fork-only)

Run these once in the Supabase SQL editor, with
Authentication → Providers → Anonymous Sign-In enabled:

| File | Table | What it stores |
|---|---|---|
| `user_custom_meals.sql` | `user_custom_meals` | Custom meals / foods |
| `user_recipes.sql` | `user_recipes` | Recipes |
| `../nutrient-overrides/README.md` | `user_nutrient_overrides` | Manually enriched nutrient values |
| `user_recovery_codes.sql` | `user_recovery_codes` + RPCs | Recovery code (run after the three above) |

On every start the app restores missing custom meals and recipes from these
tables. Rows belong to the install's anonymous Supabase user, so a fresh
install (new anonymous user) does not see the old rows on its own.

### Recovery code

Every install registers a random recovery code (Settings → Polar & Sync →
*Wiederherstellungscode*; it is also written to the JSON export as
`supabase_recovery.json`). On a new install, enter the old code there — or
import the old JSON export, which claims it automatically. The
`claim_recovery_code` RPC moves the old anonymous user's custom meals,
recipes and nutrient overrides to the new one (on a key clash the newer row
wins) and hands the code over, so the same code keeps working for the next
reinstall. Only a SHA-256 hash of the code is stored server-side.
