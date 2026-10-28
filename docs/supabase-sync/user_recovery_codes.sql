-- Recovery code for the fork's Supabase backup.
-- Run this in the Supabase SQL Editor once (after user_custom_meals.sql,
-- user_recipes.sql and the user_nutrient_overrides table exist). Safe to
-- run again: everything is CREATE IF NOT EXISTS / CREATE OR REPLACE.
--
-- The app signs in anonymously, so a reinstall gets a new auth.uid() and
-- row-level security hides the old rows. Each install registers a random
-- recovery code (the app shows it under Settings -> Polar & Sync and puts
-- it in the JSON export). Claiming that code from a new install moves the
-- old user's rows to the new user; the code moves with them and stays valid.
--
-- Only a SHA-256 hash of the code is stored. The table has RLS on and no
-- policies, so clients reach it only through the two functions below.

CREATE TABLE IF NOT EXISTS user_recovery_codes (
    user_id     UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    code_hash   TEXT NOT NULL UNIQUE,
    updated_at  TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE user_recovery_codes ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION recovery_code_hash(code TEXT) RETURNS TEXT
    LANGUAGE sql IMMUTABLE
    AS $$ SELECT encode(sha256(convert_to(code, 'UTF8')), 'hex') $$;

-- Registers [code] for the signed-in user, replacing any earlier code.
CREATE OR REPLACE FUNCTION set_recovery_code(code TEXT) RETURNS VOID
    LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
    AS $$
DECLARE
    uid UUID := auth.uid();
BEGIN
    IF uid IS NULL THEN
        RAISE EXCEPTION 'not signed in';
    END IF;
    IF length(code) < 16 THEN
        RAISE EXCEPTION 'recovery code too short';
    END IF;
    INSERT INTO user_recovery_codes (user_id, code_hash)
    VALUES (uid, recovery_code_hash(code))
    ON CONFLICT (user_id) DO UPDATE
        SET code_hash = excluded.code_hash, updated_at = now();
END;
$$;

-- Moves every row of the user who registered [code] to the signed-in user
-- and hands the code over. Where both users have a row with the same key,
-- the newer one (updated_at) is kept.
-- Returns the number of rows moved, 0 when the code is already this
-- user's, and -1 when no user has registered it.
CREATE OR REPLACE FUNCTION claim_recovery_code(code TEXT) RETURNS INTEGER
    LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
    AS $$
DECLARE
    uid     UUID := auth.uid();
    old_uid UUID;
    moved   INTEGER := 0;
    n       INTEGER;
BEGIN
    IF uid IS NULL THEN
        RAISE EXCEPTION 'not signed in';
    END IF;
    SELECT user_id INTO old_uid
        FROM user_recovery_codes WHERE code_hash = recovery_code_hash(code);
    IF old_uid IS NULL THEN
        RETURN -1;
    END IF;
    IF old_uid = uid THEN
        RETURN 0;
    END IF;

    -- Custom meals, keyed by lookup_key.
    DELETE FROM user_custom_meals cur USING user_custom_meals old
        WHERE cur.user_id = uid AND old.user_id = old_uid
          AND cur.lookup_key = old.lookup_key
          AND coalesce(cur.updated_at, '-infinity') <= coalesce(old.updated_at, '-infinity');
    DELETE FROM user_custom_meals old USING user_custom_meals cur
        WHERE old.user_id = old_uid AND cur.user_id = uid
          AND cur.lookup_key = old.lookup_key;
    UPDATE user_custom_meals SET user_id = uid WHERE user_id = old_uid;
    GET DIAGNOSTICS n = ROW_COUNT;
    moved := moved + n;

    -- Recipes, keyed by recipe_id.
    DELETE FROM user_recipes cur USING user_recipes old
        WHERE cur.user_id = uid AND old.user_id = old_uid
          AND cur.recipe_id = old.recipe_id
          AND coalesce(cur.updated_at, '-infinity') <= coalesce(old.updated_at, '-infinity');
    DELETE FROM user_recipes old USING user_recipes cur
        WHERE old.user_id = old_uid AND cur.user_id = uid
          AND cur.recipe_id = old.recipe_id;
    UPDATE user_recipes SET user_id = uid WHERE user_id = old_uid;
    GET DIAGNOSTICS n = ROW_COUNT;
    moved := moved + n;

    -- Nutrient overrides, keyed by (meal_source, lookup_key).
    DELETE FROM user_nutrient_overrides cur USING user_nutrient_overrides old
        WHERE cur.user_id = uid AND old.user_id = old_uid
          AND cur.meal_source = old.meal_source AND cur.lookup_key = old.lookup_key
          AND coalesce(cur.updated_at, '-infinity') <= coalesce(old.updated_at, '-infinity');
    DELETE FROM user_nutrient_overrides old USING user_nutrient_overrides cur
        WHERE old.user_id = old_uid AND cur.user_id = uid
          AND cur.meal_source = old.meal_source AND cur.lookup_key = old.lookup_key;
    UPDATE user_nutrient_overrides SET user_id = uid WHERE user_id = old_uid;
    GET DIAGNOSTICS n = ROW_COUNT;
    moved := moved + n;

    -- The code now belongs to this user; its own earlier code is dropped.
    DELETE FROM user_recovery_codes WHERE user_id = uid;
    UPDATE user_recovery_codes SET user_id = uid, updated_at = now()
        WHERE user_id = old_uid;
    RETURN moved;
END;
$$;

REVOKE ALL ON FUNCTION set_recovery_code(TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION claim_recovery_code(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION set_recovery_code(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION claim_recovery_code(TEXT) TO authenticated;
