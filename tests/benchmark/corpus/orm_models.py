"""
Database ORM module with bugs and TODOs.
Simple object-relational mapping for SQLite.
"""

import sqlite3
from typing import Dict, List, Optional, Any, Type, TypeVar
from dataclasses import dataclass, asdict
from datetime import datetime

T = TypeVar('T', bound='Model')


class DatabaseConnection:
    """Manage SQLite database connection."""

    def __init__(self, db_path: str):
        self.db_path = db_path
        self._connection: Optional[sqlite3.Connection] = None

    def connect(self) -> sqlite3.Connection:
        """Get or create connection."""
        if self._connection is None:
            self._connection = sqlite3.connect(self.db_path)
            self._connection.row_factory = sqlite3.Row
        return self._connection

    def close(self) -> None:
        """Close connection."""
        if self._connection:
            self._connection.close()
            self._connection = None

    def execute(self, query: str, params: tuple = ()) -> sqlite3.Cursor:
        """Execute SQL query."""
        conn = self.connect()
        return conn.execute(query, params)

    def commit(self) -> None:
        """Commit transaction."""
        if self._connection:
            self._connection.commit()

    def __enter__(self) -> 'DatabaseConnection':
        self.connect()
        return self

    def __exit__(self, *args) -> None:
        self.close()


class Model:
    """Base model class for ORM."""

    _table_name: str = ''
    _db: Optional[DatabaseConnection] = None

    id: Optional[int] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None

    @classmethod
    def set_db(cls, db: DatabaseConnection) -> None:
        """Set database connection for model class."""
        cls._db = db

    @classmethod
    def _ensure_table(cls) -> None:
        """Create table if not exists."""
        if not cls._db:
            raise RuntimeError("Database not set")

        # BUG: SQL injection vulnerability in table name
        fields = []
        annotations = getattr(cls, '__annotations__', {})

        for name, typ in annotations.items():
            if name.startswith('_'):
                continue
            sql_type = cls._python_to_sql(typ)
            fields.append(f"{name} {sql_type}")

        sql = f"CREATE TABLE IF NOT EXISTS {cls._table_name} ("
        sql += "id INTEGER PRIMARY KEY AUTOINCREMENT, "
        sql += ", ".join(fields)
        sql += ")"

        cls._db.execute(sql)
        cls._db.commit()

    @staticmethod
    def _python_to_sql(py_type: type) -> str:
        """Convert Python type to SQL type."""
        mapping = {
            int: 'INTEGER',
            str: 'TEXT',
            float: 'REAL',
            bool: 'INTEGER',
            datetime: 'TEXT',
        }
        # TODO: Handle Optional types properly
        return mapping.get(py_type, 'TEXT')

    @classmethod
    def create(cls: Type[T], **kwargs) -> T:
        """Create new record."""
        cls._ensure_table()

        instance = cls(**kwargs)
        instance.created_at = datetime.now()
        instance.updated_at = datetime.now()

        fields = [k for k in kwargs.keys() if not k.startswith('_')]
        fields.extend(['created_at', 'updated_at'])

        values = [getattr(instance, f) for f in fields]
        placeholders = ', '.join(['?' for _ in fields])

        # BUG: String formatting instead of parameterization for fields
        sql = f"INSERT INTO {cls._table_name} ({', '.join(fields)}) VALUES ({placeholders})"

        cursor = cls._db.execute(sql, tuple(values))
        cls._db.commit()
        instance.id = cursor.lastrowid

        return instance

    @classmethod
    def get(cls: Type[T], id: int) -> Optional[T]:
        """Get record by ID."""
        cls._ensure_table()

        sql = f"SELECT * FROM {cls._table_name} WHERE id = ?"
        row = cls._db.execute(sql, (id,)).fetchone()

        if not row:
            return None

        return cls._row_to_instance(row)

    @classmethod
    def find(cls: Type[T], **conditions) -> List[T]:
        """Find records matching conditions."""
        cls._ensure_table()

        if conditions:
            where_parts = []
            values = []
            for k, v in conditions.items():
                # BUG: No validation of field names
                where_parts.append(f"{k} = ?")
                values.append(v)
            where_clause = " AND ".join(where_parts)
            sql = f"SELECT * FROM {cls._table_name} WHERE {where_clause}"
        else:
            sql = f"SELECT * FROM {cls._table_name}"
            values = []

        rows = cls._db.execute(sql, tuple(values)).fetchall()
        return [cls._row_to_instance(row) for row in rows]

    @classmethod
    def _row_to_instance(cls: Type[T], row: sqlite3.Row) -> T:
        """Convert database row to model instance."""
        kwargs = {}
        for key in row.keys():
            kwargs[key] = row[key]
        return cls(**kwargs)

    def save(self) -> None:
        """Update existing record."""
        if not self.id:
            raise ValueError("Cannot save unsaved instance")

        self.updated_at = datetime.now()

        # TODO: Implement partial updates (only changed fields)
        fields = [k for k in self.__dict__.keys() if not k.startswith('_') and k != 'id']
        set_clause = ', '.join([f"{f} = ?" for f in fields])
        values = [getattr(self, f) for f in fields]
        values.append(self.id)

        sql = f"UPDATE {self._table_name} SET {set_clause} WHERE id = ?"
        self._db.execute(sql, tuple(values))
        self._db.commit()

    def delete(self) -> None:
        """Delete record."""
        if not self.id:
            return

        sql = f"DELETE FROM {self._table_name} WHERE id = ?"
        self._db.execute(sql, (self.id,))
        self._db.commit()
        self.id = None


@dataclass
class User(Model):
    """User model example."""
    _table_name = 'users'

    name: str = ''
    email: str = ''
    active: bool = True
    age: int = 0


@dataclass
class Product(Model):
    """Product model example."""
    _table_name = 'products'

    name: str = ''
    description: str = ''
    price: float = 0.0
    in_stock: bool = True


def main():
    """Demo ORM usage."""
    db = DatabaseConnection(':memory:')
    Model.set_db(db)

    # Create users
    user1 = User.create(name='Alice', email='alice@example.com', age=30)
    user2 = User.create(name='Bob', email='bob@example.com', age=25)

    # Query
    found = User.get(user1.id)
    print(f"Found user: {found}")

    all_users = User.find()
    print(f"Total users: {len(all_users)}")

    # Update
    user1.age = 31
    user1.save()

    return 0


if __name__ == '__main__':
    exit(main())
