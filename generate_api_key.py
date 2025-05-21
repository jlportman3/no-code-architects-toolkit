#!/usr/bin/env python3
"""Generate a random API key."""
import secrets
import string
import sys


def generate(length: int = 64) -> str:
    """Return a cryptographically secure random string."""
    alphabet = string.ascii_letters + string.digits
    return ''.join(secrets.choice(alphabet) for _ in range(length))


if __name__ == "__main__":
    length = int(sys.argv[1]) if len(sys.argv) > 1 else 64
    print(generate(length))
