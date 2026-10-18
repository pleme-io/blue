CREATE TABLE IF NOT EXISTS "greetings" (
  "id" bigserial PRIMARY KEY,
  "created_at" timestamptz NOT NULL,
  "note" text,
  "text" text NOT NULL
);
ALTER TABLE "greetings" ADD COLUMN IF NOT EXISTS "created_at" timestamptz;
ALTER TABLE "greetings" ADD COLUMN IF NOT EXISTS "note" text;
ALTER TABLE "greetings" ADD COLUMN IF NOT EXISTS "text" text;
