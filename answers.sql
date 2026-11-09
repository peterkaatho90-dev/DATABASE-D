-- ============================================================
-- answers.sql
-- PostgreSQL practical: Audit logging, category tree,
-- Flyway migration notes, and least-privilege security.
-- Run against the bootcamp database using an administrator role.
-- ============================================================


-- ------------------------------------------------------------
-- QUESTION 1: Create a reusable JSONB audit log
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.audit_log (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tbl TEXT NOT NULL,
    op TEXT NOT NULL,
    old_row JSONB,
    new_row JSONB,
    changed_by TEXT NOT NULL DEFAULT current_user,
    at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION public.audit()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO public.audit_log (tbl, op, old_row, new_row, changed_by)
        VALUES (TG_TABLE_NAME, TG_OP, NULL, to_jsonb(NEW), session_user);
        RETURN NEW;

    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO public.audit_log (tbl, op, old_row, new_row, changed_by)
        VALUES (TG_TABLE_NAME, TG_OP, to_jsonb(OLD), to_jsonb(NEW), session_user);
        RETURN NEW;

    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO public.audit_log (tbl, op, old_row, new_row, changed_by)
        VALUES (TG_TABLE_NAME, TG_OP, to_jsonb(OLD), NULL, session_user);
        RETURN OLD;
    END IF;

    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_audit ON public.students;

CREATE TRIGGER trg_audit
AFTER INSERT OR UPDATE OR DELETE
ON public.students
FOR EACH ROW
EXECUTE FUNCTION public.audit();


-- ------------------------------------------------------------
-- QUESTION 2: Test the audit log
-- Use these example statements only in your practice database.
-- Confirm that student IDs 1 and 3 are the intended test rows
-- before running the UPDATE and DELETE statements.
-- ------------------------------------------------------------

UPDATE public.students
SET name = 'Kofi M.'
WHERE id = 1;

DELETE FROM public.students
WHERE id = 3;

SELECT
    tbl,
    op,
    old_row ->> 'name' AS was,
    new_row ->> 'name' AS now,
    changed_by,
    at
FROM public.audit_log
ORDER BY at DESC;


-- ------------------------------------------------------------
-- QUESTION 3: Create a self-referencing categories table
-- The sample inserts assume the categories table is empty and
-- the generated IDs start at 1, as in the assignment example.
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.categories (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    parent_id INT REFERENCES public.categories(id)
);

INSERT INTO public.categories (name, parent_id) VALUES
    ('Electronics', NULL),
    ('Computers', 1),
    ('Laptops', 2),
    ('Phones', 1);


-- ------------------------------------------------------------
-- QUESTION 4: Display the category hierarchy with a recursive CTE
-- ------------------------------------------------------------

WITH RECURSIVE tree AS (
    SELECT
        id,
        name,
        parent_id,
        0 AS depth
    FROM public.categories
    WHERE parent_id IS NULL

    UNION ALL

    SELECT
        c.id,
        c.name,
        c.parent_id,
        t.depth + 1
    FROM public.categories AS c
    JOIN tree AS t
        ON c.parent_id = t.id
)
SELECT
    repeat('  ', depth) || name AS tree
FROM tree
ORDER BY depth, name;


-- ------------------------------------------------------------
-- QUESTION 5: Flyway migration files
-- These are Flyway command-line instructions, not SQL statements.
-- Save the schema changes in separate files named:
--   V1__core_tables.sql
--   V2__audit_log.sql
--   V3__categories.sql
--
-- Run these commands in the operating-system terminal:
--   flyway -url=jdbc:postgresql://localhost:5432/bootcamp \
--          -user=postgres -locations=filesystem:migrations migrate
--   flyway -url=jdbc:postgresql://localhost:5432/bootcamp \
--          -user=postgres -locations=filesystem:migrations info
-- Do not place database passwords in this file or source control.
-- ------------------------------------------------------------


-- ------------------------------------------------------------
-- QUESTION 6: Apply least-privilege roles and permissions
-- Run as a database administrator. Role names must not already
-- exist; create them once in the target database environment.
-- ------------------------------------------------------------

CREATE ROLE app_read NOLOGIN;
CREATE ROLE app_write NOLOGIN;

GRANT CONNECT ON DATABASE bootcamp TO app_read, app_write;
GRANT USAGE ON SCHEMA public TO app_read, app_write;

GRANT SELECT
ON ALL TABLES IN SCHEMA public
TO app_read;

GRANT SELECT, INSERT, UPDATE, DELETE
ON ALL TABLES IN SCHEMA public
TO app_write;

GRANT USAGE, SELECT
ON ALL SEQUENCES IN SCHEMA public
TO app_write;


-- ------------------------------------------------------------
-- QUESTION 7: Create the application login user
-- Replace the password placeholder with a strong unique password
-- before execution. Never publish a real password in GitHub.
-- ------------------------------------------------------------

CREATE USER api
LOGIN
PASSWORD 'REPLACE_WITH_A_STRONG_UNIQUE_PASSWORD'
IN ROLE app_write;

-- End of answers.sql
