"""Create the FIRST administrator account. Run once, from this folder:

    python create_admin.py

It connects as db_admin (see DB_ADMIN_USER / DB_ADMIN_PASSWORD in .env). The
backend account (app_service) is not allowed to create administrators, on purpose.
The password is hashed with argon2 before it reaches the database.
"""
from dotenv import load_dotenv

load_dotenv()

import getpass
import os
import sys

import psycopg
from pydantic import ValidationError

import security
from schemas import RegisterIn


def main() -> None:
    print("Create the first DermaScreen administrator\n")
    first = input("First name: ")
    last = input("Last name: ")
    contact = input("Contact number (09XXXXXXXXX): ")
    age = input("Age: ")
    username = input("Username (4-20 letters/numbers/_): ")
    password = getpass.getpass("Password: ")
    if password != getpass.getpass("Confirm password: "):
        sys.exit("Passwords do not match.")

    try:
        d = RegisterIn(first_name=first, last_name=last, contact_number=contact,
                       age=int(age) if age.isdigit() else 0, username=username,
                       password=password, consent=True)
    except ValidationError as e:
        for err in e.errors():
            print(f"  - {err['loc'][0]}: {err['msg']}")
        sys.exit("Please fix the details above and run again.")

    dsn = (
        f"host={os.environ['DB_HOST']} port={os.environ.get('DB_PORT', '5432')} "
        f"dbname={os.environ['DB_NAME']} user={os.environ['DB_ADMIN_USER']} "
        f"password={os.environ['DB_ADMIN_PASSWORD']} sslmode={os.environ.get('DB_SSLMODE', 'require')}"
    )
    with psycopg.connect(dsn) as conn:
        conn.execute(
            "INSERT INTO skin_classification_schema.users "
            "(first_name, last_name, middle_name, contact_number, age, username, password_hash, role) "
            "VALUES (%s, %s, %s, %s, %s, %s, %s, 'administrator')",
            (d.first_name, d.last_name, d.middle_name, d.contact_number, d.age,
             d.username, security.hash_password(password)),
        )
    print(f"\nAdministrator '{d.username}' created. You can now sign in.")


if __name__ == "__main__":
    main()
