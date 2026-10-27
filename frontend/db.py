"""
UPIShield front end - database layer.
All SQL goes through this class so the GUI code never touches the driver
directly.  Uses mysql-connector-python (pip install mysql-connector-python).
"""
import mysql.connector


class Database:
    def __init__(self):
        self.conn = None
        self.info = ""

    # ------------------------------------------------------------ connect
    def connect(self, host, port, user, password, database):
        self.conn = mysql.connector.connect(
            host=host, port=int(port), user=user, password=password,
            database=database, autocommit=True)
        self.info = f"{user}@{host}:{port}/{database}"

    def close(self):
        if self.conn:
            self.conn.close()

    # ------------------------------------------------------------ helpers
    def query(self, sql, params=None):
        """Run a SELECT; return (column_names, rows)."""
        cur = self.conn.cursor()
        try:
            cur.execute(sql, params or ())
            cols = [d[0] for d in cur.description] if cur.description else []
            rows = cur.fetchall() if cur.with_rows else []
            return cols, rows
        finally:
            cur.close()

    def scalar(self, sql, params=None):
        _, rows = self.query(sql, params)
        return rows[0][0] if rows else None

    def execute(self, sql, params=None):
        """Run INSERT/UPDATE/DELETE; return affected row count."""
        cur = self.conn.cursor()
        try:
            cur.execute(sql, params or ())
            if cur.with_rows:
                cur.fetchall()
            return cur.rowcount
        finally:
            cur.close()

    def call(self, proc, args):
        """Call a stored procedure; return (args_after_call, [(cols, rows), ...])."""
        cur = self.conn.cursor()
        try:
            out = cur.callproc(proc, args)
            results = []
            for res in cur.stored_results():
                cols = [d[0] for d in res.description] if res.description else []
                results.append((cols, res.fetchall()))
            return out, results
        finally:
            cur.close()

    def run_any(self, sql):
        """SQL console: run one statement of any kind."""
        cur = self.conn.cursor()
        try:
            cur.execute(sql)
            if cur.with_rows:
                cols = [d[0] for d in cur.description]
                return cols, cur.fetchall(), None
            return [], [], cur.rowcount
        finally:
            cur.close()
