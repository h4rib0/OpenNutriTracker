-- Table for user-created recipes.
-- Run this in the Supabase SQL Editor once to enable cloud sync.

CREATE TABLE IF NOT EXISTS user_recipes (
    id           UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    recipe_id    TEXT NOT NULL,
    recipe_data  JSONB NOT NULL,
    updated_at   TIMESTAMPTZ DEFAULT now(),
    UNIQUE (user_id, recipe_id)
);

ALTER TABLE user_recipes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage their own recipes"
    ON user_recipes FOR ALL
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);
