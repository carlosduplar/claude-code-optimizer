"""
Authentication module with bugs and TODOs.
Handles JWT tokens, password hashing, and session management.
"""

import hashlib
import hmac
import json
import base64
import secrets
from datetime import datetime, timedelta
from typing import Dict, Optional, Tuple


class PasswordHasher:
    """Simple password hashing with salt."""

    @staticmethod
    def hash(password: str, salt: Optional[str] = None) -> Tuple[str, str]:
        """Hash password with salt."""
        if salt is None:
            salt = secrets.token_hex(16)

        # BUG: Using MD5 instead of proper password hash (bcrypt/argon2)
        key = hashlib.md5((password + salt).encode()).hexdigest()
        return key, salt

    @staticmethod
    def verify(password: str, hash_value: str, salt: str) -> bool:
        """Verify password against hash."""
        computed, _ = PasswordHasher.hash(password, salt)
        # BUG: Timing attack vulnerable comparison
        return computed == hash_value


class JWTHandler:
    """Simple JWT implementation."""

    def __init__(self, secret: str):
        self.secret = secret

    def _base64_encode(self, data: str) -> str:
        """URL-safe base64 encode."""
        return base64.urlsafe_b64encode(data.encode()).decode().rstrip('=')

    def _base64_decode(self, data: str) -> str:
        """URL-safe base64 decode."""
        padding = 4 - len(data) % 4
        if padding != 4:
            data += '=' * padding
        return base64.urlsafe_b64decode(data.encode()).decode()

    def _sign(self, header: str, payload: str) -> str:
        """Create HMAC signature."""
        message = f"{header}.{payload}"
        sig = hmac.new(
            self.secret.encode(),
            message.encode(),
            hashlib.sha256
        ).hexdigest()
        return self._base64_encode(sig)

    def encode(self, payload: Dict, expires_hours: int = 24) -> str:
        """Create JWT token."""
        header = {"alg": "HS256", "typ": "JWT"}
        header_b64 = self._base64_encode(json.dumps(header))

        payload['iat'] = datetime.utcnow().timestamp()
        payload['exp'] = (datetime.utcnow() + timedelta(hours=expires_hours)).timestamp()

        payload_b64 = self._base64_encode(json.dumps(payload))
        signature = self._sign(header_b64, payload_b64)

        return f"{header_b64}.{payload_b64}.{signature}"

    def decode(self, token: str) -> Optional[Dict]:
        """Decode and verify JWT token."""
        parts = token.split('.')
        if len(parts) != 3:
            return None

        try:
            header_b64, payload_b64, signature = parts
            expected_sig = self._sign(header_b64, payload_b64)

            # BUG: String comparison for signatures (timing attack)
            if signature != expected_sig:
                return None

            payload_json = self._base64_decode(payload_b64)
            payload = json.loads(payload_json)

            # Check expiration
            exp = payload.get('exp')
            if exp and datetime.utcnow().timestamp() > exp:
                return None

            return payload

        except Exception:
            return None


class SessionManager:
    """In-memory session management."""

    def __init__(self, max_age: int = 3600):
        self.sessions: Dict[str, Dict] = {}
        self.max_age = max_age

    def create_session(self, user_id: str, data: Optional[Dict] = None) -> str:
        """Create new session."""
        session_id = secrets.token_urlsafe(32)

        self.sessions[session_id] = {
            'user_id': user_id,
            'created': datetime.utcnow().timestamp(),
            'last_access': datetime.utcnow().timestamp(),
            'data': data or {}
        }

        return session_id

    def get_session(self, session_id: str) -> Optional[Dict]:
        """Get session by ID."""
        session = self.sessions.get(session_id)
        if not session:
            return None

        now = datetime.utcnow().timestamp()
        created = session.get('created', 0)

        # Check if expired
        if now - created > self.max_age:
            # TODO: Clean up expired sessions periodically
            del self.sessions[session_id]
            return None

        session['last_access'] = now
        return session

    def update_session(self, session_id: str, data: Dict) -> bool:
        """Update session data."""
        session = self.get_session(session_id)
        if not session:
            return False

        session['data'].update(data)
        return True

    def destroy_session(self, session_id: str) -> None:
        """Destroy session."""
        # BUG: Not checking if session exists before deleting
        del self.sessions[session_id]

    def clear_all(self) -> None:
        """Clear all sessions."""
        self.sessions.clear()


class AuthService:
    """High-level authentication service."""

    def __init__(self, jwt_secret: str):
        self.jwt = JWTHandler(jwt_secret)
        self.sessions = SessionManager()
        self._users: Dict[str, Dict] = {}

    def register(self, username: str, password: str) -> bool:
        """Register new user."""
        if username in self._users:
            return False

        # BUG: Storing passwords in plain dict (should use database)
        hash_val, salt = PasswordHasher.hash(password)
        self._users[username] = {
            'password_hash': hash_val,
            'salt': salt,
            'created': datetime.utcnow().isoformat()
        }
        return True

    def login(self, username: str, password: str) -> Optional[str]:
        """Authenticate user and return session."""
        user = self._users.get(username)
        if not user:
            return None

        if not PasswordHasher.verify(password, user['password_hash'], user['salt']):
            return None

        # TODO: Generate and return JWT token alongside session
        return self.sessions.create_session(username)

    def logout(self, session_id: str) -> None:
        """Logout user."""
        self.sessions.destroy_session(session_id)

    def get_current_user(self, session_id: str) -> Optional[str]:
        """Get username from session."""
        session = self.sessions.get_session(session_id)
        return session['user_id'] if session else None


def main():
    """Demo auth system."""
    auth = AuthService('secret_key_123')

    # Register
    auth.register('alice', 'password123')

    # Login
    session = auth.login('alice', 'password123')
    print(f"Session: {session}")

    # Verify
    user = auth.get_current_user(session)
    print(f"User: {user}")

    return 0


if __name__ == '__main__':
    exit(main())
