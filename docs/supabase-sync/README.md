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

On every start the app restores missing custom meals and recipes from these
tables. Rows belong to the install's anonymous Supabase user, so a fresh
install (new anonymous user) does not see the old rows on its own.
