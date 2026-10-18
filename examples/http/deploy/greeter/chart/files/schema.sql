CREATE SCHEMA IF NOT EXISTS "greeter";

CREATE TABLE IF NOT EXISTS "greeter"."greetings" (
  "id" bigserial PRIMARY KEY,
  "created_at" timestamptz NOT NULL,
  "note" text,
  "text" text NOT NULL
);
ALTER TABLE "greeter"."greetings" ADD COLUMN IF NOT EXISTS "created_at" timestamptz;
ALTER TABLE "greeter"."greetings" ADD COLUMN IF NOT EXISTS "note" text;
ALTER TABLE "greeter"."greetings" ADD COLUMN IF NOT EXISTS "text" text;
