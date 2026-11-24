"""Run on your own machine (needs: pip install "psycopg[binary]", the test DB, and
DB_* environment variables). Proves the login query treats input as data.

    python test_injection.py
"""
from auth_queries import get_user_for_login

payload = "x') OR ('1'='1"
print("payload       ->", get_user_for_login(payload))      # expected: None
print("real username ->", get_user_for_login("alice_p"))    # expected: a row
