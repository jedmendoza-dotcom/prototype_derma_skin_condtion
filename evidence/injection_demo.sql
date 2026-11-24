\set QUIET on
-- two real accounts exist in the test database
SET search_path = skin_classification_schema;
\set QUIET off

\echo '--- Payload typed into the Login page username box:'
\set evil 'x'') OR (''1''=''1'
SELECT :'evil' AS typed_username;

\echo
\echo '=== A. UNSAFE: user input glued into the SQL text ==='
SELECT 'SELECT user_id, username FROM skin_classification_schema.users WHERE lower(username) = lower(''' || :'evil' || ''')' AS sql_text \gset
\echo SQL that PostgreSQL would receive:
SELECT :'sql_text' AS sql_text;
BEGIN;
SELECT set_config('app.current_role', 'auth', true) \gset
\echo Result (the attack works, every account is returned):
:sql_text;
ROLLBACK;

\echo
\echo '=== B. SAFE: parameterized query (what backend/auth_queries.py does) ==='
\echo 'SQL text sent:   ... WHERE lower(username) = lower($1)'
\echo 'Value sent separately (as data): the same payload as above'
BEGIN;
SELECT set_config('app.current_role', 'auth', true) \gset
SELECT user_id, username FROM skin_classification_schema.users WHERE lower(username) = lower($1) \bind 'x'') OR (''1''=''1' \g
ROLLBACK;

\echo
\echo '=== C. SAFE query with a real username still works ==='
BEGIN;
SELECT set_config('app.current_role', 'auth', true) \gset
SELECT user_id, username FROM skin_classification_schema.users WHERE lower(username) = lower($1) \bind 'Alice_P' \g
ROLLBACK;
