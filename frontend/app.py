"""
UPIShield - Front end (Python + Tkinter + MySQL)
-------------------------------------------------
Forms for inserting data, running the stored procedures, monitoring fraud
alerts and running any SQL query.  Plain black / white / grey interface.

Run:   pip install mysql-connector-python
       python frontend/app.py
"""
import time
import tkinter as tk
from tkinter import ttk, messagebox
from tkinter import font as tkfont

from db import Database
from query_catalog import CATALOG

# ---------------------------------------------------------------- palette
BLACK = "#111111"
DARK = "#2B2B2B"
MID = "#5E5E5E"
BORDER = "#BDBDBD"
LIGHT = "#E6E6E6"
LIGHTER = "#F4F4F4"
WHITE = "#FFFFFF"

CITIES = ["Ahmedabad", "Gandhinagar", "Surat", "Vadodara", "Rajkot", "Mumbai", "Pune", "Delhi",
          "Bengaluru", "Hyderabad", "Chennai", "Kolkata", "Jaipur", "Lucknow", "Indore"]


def pick_font():
    families = set(tkfont.families())
    for f in ("Segoe UI", "Helvetica Neue", "DejaVu Sans", "Helvetica", "Arial"):
        if f in families:
            return f
    return "TkDefaultFont"


def setup_style(root):
    fam = pick_font()
    root.option_add("*Font", (fam, 10))
    s = ttk.Style(root)
    s.theme_use("clam")
    s.configure(".", background=WHITE, foreground=BLACK, fieldbackground=WHITE,
                bordercolor=BORDER, lightcolor=WHITE, darkcolor=BORDER, font=(fam, 10))
    s.configure("TFrame", background=WHITE)
    s.configure("Panel.TFrame", background=LIGHTER)
    s.configure("TLabel", background=WHITE, foreground=BLACK)
    s.configure("Panel.TLabel", background=LIGHTER)
    s.configure("Muted.TLabel", background=WHITE, foreground=MID, font=(fam, 9))
    s.configure("PanelMuted.TLabel", background=LIGHTER, foreground=MID, font=(fam, 9))
    s.configure("Section.TLabel", background=WHITE, font=(fam, 12, "bold"))
    s.configure("PanelSection.TLabel", background=LIGHTER, font=(fam, 12, "bold"))
    s.configure("StatValue.TLabel", background=LIGHTER, font=(fam, 20, "bold"))
    s.configure("StatName.TLabel", background=LIGHTER, foreground=MID, font=(fam, 9))
    s.configure("Header.TFrame", background=BLACK)
    s.configure("Header.TLabel", background=BLACK, foreground=WHITE, font=(fam, 16, "bold"))
    s.configure("HeaderSub.TLabel", background=BLACK, foreground="#BBBBBB", font=(fam, 9))
    s.configure("Status.TLabel", background=LIGHT, foreground=DARK, font=(fam, 9), padding=(10, 4))
    s.configure("TButton", background=BLACK, foreground=WHITE, bordercolor=BLACK,
                focuscolor=DARK, padding=(12, 5), font=(fam, 10, "bold"))
    s.map("TButton", background=[("active", DARK), ("pressed", MID)])
    s.configure("Secondary.TButton", background=WHITE, foreground=BLACK, bordercolor=BLACK)
    s.map("Secondary.TButton", background=[("active", LIGHT)])
    s.configure("TEntry", padding=4)
    s.configure("TCombobox", padding=3, arrowcolor=BLACK)
    s.map("TCombobox", fieldbackground=[("readonly", WHITE)], foreground=[("readonly", BLACK)])
    s.configure("TRadiobutton", background=LIGHTER)
    s.configure("TNotebook", background=WHITE, borderwidth=0, tabmargins=(8, 6, 8, 0))
    s.configure("TNotebook.Tab", background=LIGHT, foreground=DARK, padding=(14, 6), borderwidth=0)
    s.map("TNotebook.Tab", background=[("selected", BLACK)], foreground=[("selected", WHITE)])
    s.configure("Treeview", background=WHITE, fieldbackground=WHITE, foreground=BLACK,
                rowheight=24, bordercolor=BORDER)
    s.configure("Treeview.Heading", background=LIGHT, foreground=BLACK, font=(fam, 9, "bold"),
                relief="flat", padding=(6, 4))
    s.map("Treeview", background=[("selected", DARK)], foreground=[("selected", WHITE)])
    s.map("Treeview.Heading", background=[("active", BORDER)])
    return fam


# ---------------------------------------------------------------- widgets
class DataTable(ttk.Frame):
    """Treeview with scrollbars that can show any (columns, rows) result."""

    def __init__(self, master, height=12):
        super().__init__(master)
        self.tree = ttk.Treeview(self, show="headings", height=height)
        ys = ttk.Scrollbar(self, orient="vertical", command=self.tree.yview)
        xs = ttk.Scrollbar(self, orient="horizontal", command=self.tree.xview)
        self.tree.configure(yscrollcommand=ys.set, xscrollcommand=xs.set)
        self.tree.grid(row=0, column=0, sticky="nsew")
        ys.grid(row=0, column=1, sticky="ns")
        xs.grid(row=1, column=0, sticky="ew")
        self.rowconfigure(0, weight=1)
        self.columnconfigure(0, weight=1)
        self.tree.tag_configure("odd", background=LIGHTER)
        self.columns = []

    def show(self, columns, rows):
        self.tree.delete(*self.tree.get_children())
        self.columns = list(columns)
        self.tree["columns"] = self.columns
        f = tkfont.nametofont("TkDefaultFont")
        for c in self.columns:
            sample = [str(r[self.columns.index(c)]) for r in rows[:50]]
            width = max([f.measure(str(c)) + 24] + [f.measure(v) + 16 for v in sample])
            self.tree.heading(c, text=c)
            self.tree.column(c, width=min(max(width, 70), 320), anchor="w", stretch=False)
        for i, r in enumerate(rows):
            vals = ["" if v is None else v for v in r]
            self.tree.insert("", "end", values=vals, tags=("odd",) if i % 2 else ())

    def selected(self):
        sel = self.tree.selection()
        if not sel:
            return None
        return dict(zip(self.columns, self.tree.item(sel[0], "values")))


def form_row(parent, r, label, widget, style="Panel.TLabel"):
    ttk.Label(parent, text=label, style=style).grid(row=r, column=0, sticky="w", padx=(12, 8), pady=4)
    widget.grid(row=r, column=1, sticky="ew", padx=(0, 12), pady=4)
    return widget


# ---------------------------------------------------------------- login
class LoginDialog(tk.Toplevel):
    def __init__(self, master, db):
        super().__init__(master)
        self.db, self.ok = db, False
        self.title("UPIShield - Connect")
        self.configure(bg=WHITE)
        self.resizable(False, False)
        head = ttk.Frame(self, style="Header.TFrame", padding=(20, 14))
        head.pack(fill="x")
        ttk.Label(head, text="UPIShield", style="Header.TLabel").pack(anchor="w")
        ttk.Label(head, text="Connect to the MySQL database", style="HeaderSub.TLabel").pack(anchor="w")
        body = ttk.Frame(self, style="Panel.TFrame", padding=(10, 14))
        body.pack(fill="both", expand=True)
        self.vars = {}
        for i, (k, v, show) in enumerate([("Host", "localhost", ""), ("Port", "3306", ""),
                                          ("User", "root", ""), ("Password", "", "*"),
                                          ("Database", "upishield", "")]):
            var = tk.StringVar(value=v)
            self.vars[k] = var
            form_row(body, i, k, ttk.Entry(body, textvariable=var, width=28, show=show))
        ttk.Button(body, text="Connect", command=self.connect).grid(row=6, column=0, columnspan=2,
                                                                     sticky="ew", padx=12, pady=(12, 4))
        self.bind("<Return>", lambda e: self.connect())
        self.grab_set()

    def connect(self):
        v = {k: var.get() for k, var in self.vars.items()}
        try:
            self.db.connect(v["Host"], v["Port"], v["User"], v["Password"], v["Database"])
            self.ok = True
            self.destroy()
        except Exception as e:
            messagebox.showerror("Connection failed", str(e), parent=self)


# ---------------------------------------------------------------- main app
class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.withdraw()
        setup_style(self)
        self.title("UPIShield - UPI Payments & Fraud Monitoring")
        self.geometry("1280x780")
        self.minsize(1100, 680)
        self.configure(bg=WHITE)
        self.db = Database()

        dlg = LoginDialog(self, self.db)
        self.wait_window(dlg)
        if not dlg.ok:
            self.destroy()
            return
        self.build()
        self.deiconify()

    # ----------------------------------------------------------- layout
    def build(self):
        head = ttk.Frame(self, style="Header.TFrame", padding=(20, 12))
        head.pack(fill="x")
        left = ttk.Frame(head, style="Header.TFrame")
        left.pack(side="left")
        ttk.Label(left, text="UPIShield", style="Header.TLabel").pack(anchor="w")
        ttk.Label(left, text="UPI Payments & Fraud Monitoring System", style="HeaderSub.TLabel").pack(anchor="w")
        ttk.Label(head, text="Connected: " + self.db.info, style="HeaderSub.TLabel").pack(side="right")

        self.status = tk.StringVar(value="Ready")
        ttk.Label(self, textvariable=self.status, style="Status.TLabel", anchor="w").pack(side="bottom", fill="x")

        self.nb = ttk.Notebook(self)
        self.nb.pack(fill="both", expand=True, padx=10, pady=(8, 6))
        self.tab_dashboard()
        self.tab_customers()
        self.tab_accounts()
        self.tab_payments()
        self.tab_fraud()
        self.tab_reports()
        self.tab_console()

    def say(self, msg):
        self.status.set(time.strftime("%H:%M:%S  ") + msg)

    def safe(self, fn):
        """Run a DB action and show errors in a dialog instead of crashing."""
        try:
            return fn()
        except Exception as e:
            messagebox.showerror("Database error", str(e))
            self.say("Error: " + str(e))

    def side_panel(self, parent, title, width=340):
        p = ttk.Frame(parent, style="Panel.TFrame", padding=(4, 10), width=width)
        p.pack(side="left", fill="y", padx=(0, 10))
        p.columnconfigure(1, weight=1)
        ttk.Label(p, text=title, style="PanelSection.TLabel").grid(row=0, column=0, columnspan=2,
                                                                     sticky="w", padx=12, pady=(0, 8))
        return p

    # ----------------------------------------------------------- dashboard
    def tab_dashboard(self):
        f = ttk.Frame(self.nb, padding=12)
        self.nb.add(f, text="Dashboard")
        cards = ttk.Frame(f)
        cards.pack(fill="x")
        self.stats = {}
        names = ["Customers", "Bank accounts", "Transactions", "Value transacted (Rs.)",
                 "Open fraud alerts", "Open disputes"]
        for i, n in enumerate(names):
            c = ttk.Frame(cards, style="Panel.TFrame", padding=(16, 12))
            c.grid(row=0, column=i, sticky="nsew", padx=(0 if i == 0 else 8, 0))
            cards.columnconfigure(i, weight=1)
            v = tk.StringVar(value="-")
            ttk.Label(c, textvariable=v, style="StatValue.TLabel").pack(anchor="w")
            ttk.Label(c, text=n, style="StatName.TLabel").pack(anchor="w")
            self.stats[n] = v
        bar = ttk.Frame(f)
        bar.pack(fill="x", pady=(16, 6))
        ttk.Label(bar, text="Latest transactions", style="Section.TLabel").pack(side="left")
        ttk.Button(bar, text="Refresh", style="Secondary.TButton", command=self.load_dashboard).pack(side="right")
        self.dash_table = DataTable(f, height=16)
        self.dash_table.pack(fill="both", expand=True)
        self.load_dashboard()

    def load_dashboard(self):
        def run():
            q = self.db.scalar
            self.stats["Customers"].set(f"{q('SELECT COUNT(*) FROM customer'):,}")
            self.stats["Bank accounts"].set(f"{q('SELECT COUNT(*) FROM bank_account'):,}")
            self.stats["Transactions"].set(f"{q('SELECT COUNT(*) FROM upi_txn'):,}")
            total = q("SELECT COALESCE(SUM(amount),0) FROM upi_txn WHERE status='SUCCESS'")
            self.stats["Value transacted (Rs.)"].set(f"{float(total) / 1e5:,.1f} L")
            self.stats["Open fraud alerts"].set(q("SELECT COUNT(*) FROM fraud_alert WHERE status IN ('OPEN','INVESTIGATING')"))
            self.stats["Open disputes"].set(q("SELECT COUNT(*) FROM dispute WHERE status IN ('OPEN','UNDER_REVIEW')"))
            cols, rows = self.db.query(
                "SELECT txn_id, txn_time, payer_vpa, payee_vpa, amount, txn_type, status, remarks "
                "FROM upi_txn ORDER BY txn_time DESC, txn_id DESC LIMIT 60")
            self.dash_table.show(cols, rows)
            self.say("Dashboard refreshed")
        self.safe(run)

    # ----------------------------------------------------------- customers
    def tab_customers(self):
        f = ttk.Frame(self.nb, padding=12)
        self.nb.add(f, text="Customers")
        p = self.side_panel(f, "Register customer")
        self.c_vars = {k: tk.StringVar() for k in ("name", "phone", "email", "dob", "city", "ref")}
        form_row(p, 1, "Full name", ttk.Entry(p, textvariable=self.c_vars["name"]))
        form_row(p, 2, "Phone (10 digits)", ttk.Entry(p, textvariable=self.c_vars["phone"]))
        form_row(p, 3, "Email", ttk.Entry(p, textvariable=self.c_vars["email"]))
        form_row(p, 4, "Date of birth", ttk.Entry(p, textvariable=self.c_vars["dob"]))
        ttk.Label(p, text="YYYY-MM-DD, must be 18+", style="PanelMuted.TLabel").grid(row=5, column=1, sticky="w")
        form_row(p, 6, "City", ttk.Combobox(p, textvariable=self.c_vars["city"], values=CITIES))
        form_row(p, 7, "Referred by (ID)", ttk.Entry(p, textvariable=self.c_vars["ref"]))
        ttk.Button(p, text="Add customer", command=self.add_customer).grid(row=8, column=0, columnspan=2,
                                                                          sticky="ew", padx=12, pady=(12, 18))
        ttk.Label(p, text="Update KYC of selected row", style="PanelSection.TLabel").grid(row=9, column=0, columnspan=2,
                                                                                          sticky="w", padx=12)
        self.kyc_var = tk.StringVar(value="VERIFIED")
        form_row(p, 10, "New status", ttk.Combobox(p, textvariable=self.kyc_var, state="readonly",
                                                   values=["PENDING", "VERIFIED", "REJECTED"]))
        ttk.Button(p, text="Update KYC", style="Secondary.TButton", command=self.update_kyc).grid(
            row=11, column=0, columnspan=2, sticky="ew", padx=12, pady=8)

        right = ttk.Frame(f)
        right.pack(side="left", fill="both", expand=True)
        bar = ttk.Frame(right)
        bar.pack(fill="x", pady=(0, 6))
        ttk.Label(bar, text="Search").pack(side="left")
        self.c_search = tk.StringVar()
        e = ttk.Entry(bar, textvariable=self.c_search, width=30)
        e.pack(side="left", padx=8)
        e.bind("<Return>", lambda ev: self.load_customers())
        ttk.Button(bar, text="Search", style="Secondary.TButton", command=self.load_customers).pack(side="left")
        ttk.Label(bar, text="name, city or ID", style="Muted.TLabel").pack(side="left", padx=8)
        self.c_table = DataTable(right, height=20)
        self.c_table.pack(fill="both", expand=True)
        self.load_customers()

    def load_customers(self):
        term = self.c_search.get().strip()
        sql = "SELECT * FROM v_customer_summary"
        params = ()
        if term:
            sql += " WHERE full_name LIKE %s OR city LIKE %s OR customer_id = %s"
            params = (f"%{term}%", f"%{term}%", term if term.isdigit() else -1)
        sql += " ORDER BY customer_id DESC LIMIT 400"
        self.safe(lambda: self.c_table.show(*self.db.query(sql, params)))

    def add_customer(self):
        v = {k: var.get().strip() for k, var in self.c_vars.items()}
        if not v["name"] or not v["phone"] or not v["dob"] or not v["city"]:
            messagebox.showwarning("Missing data", "Name, phone, date of birth and city are required.")
            return

        def run():
            self.db.execute(
                "INSERT INTO customer (full_name, phone, email, dob, city, referred_by) VALUES (%s,%s,%s,%s,%s,%s)",
                (v["name"], v["phone"], v["email"] or None, v["dob"], v["city"], v["ref"] or None))
            new_id = self.db.scalar("SELECT LAST_INSERT_ID()")
            self.say(f"Customer {new_id} added")
            messagebox.showinfo("Customer added", f"Customer ID {new_id} created.")
            for var in self.c_vars.values():
                var.set("")
            self.load_customers()
        self.safe(run)

    def update_kyc(self):
        row = self.c_table.selected()
        if not row:
            messagebox.showwarning("No selection", "Select a customer in the table first.")
            return

        def run():
            self.db.execute("UPDATE customer SET kyc_status = %s WHERE customer_id = %s",
                            (self.kyc_var.get(), row["customer_id"]))
            self.say(f"KYC of customer {row['customer_id']} set to {self.kyc_var.get()} (audit log updated)")
            self.load_customers()
        self.safe(run)

    # ----------------------------------------------------------- accounts
    def tab_accounts(self):
        f = ttk.Frame(self.nb, padding=12)
        self.nb.add(f, text="Accounts")
        p = self.side_panel(f, "Open account  (sp_open_account)")
        self.a_vars = {k: tk.StringVar() for k in ("cust", "ifsc", "accno", "deposit", "rate", "minbal",
                                                    "biz", "gstin", "vpa")}
        self.a_type = tk.StringVar(value="SAVINGS")
        form_row(p, 1, "Customer ID", ttk.Entry(p, textvariable=self.a_vars["cust"]))
        self.ifsc_box = ttk.Combobox(p, textvariable=self.a_vars["ifsc"], state="readonly", width=30)
        form_row(p, 2, "Branch", self.ifsc_box)
        form_row(p, 3, "Account number", ttk.Entry(p, textvariable=self.a_vars["accno"]))
        tf = ttk.Frame(p, style="Panel.TFrame")
        ttk.Radiobutton(tf, text="Savings", value="SAVINGS", variable=self.a_type).pack(side="left")
        ttk.Radiobutton(tf, text="Current", value="CURRENT", variable=self.a_type).pack(side="left", padx=10)
        form_row(p, 4, "Type", tf)
        form_row(p, 5, "Initial deposit", ttk.Entry(p, textvariable=self.a_vars["deposit"]))
        form_row(p, 6, "Interest % (savings)", ttk.Entry(p, textvariable=self.a_vars["rate"]))
        form_row(p, 7, "Min balance (savings)", ttk.Entry(p, textvariable=self.a_vars["minbal"]))
        form_row(p, 8, "Business (current)", ttk.Entry(p, textvariable=self.a_vars["biz"]))
        form_row(p, 9, "GSTIN (current)", ttk.Entry(p, textvariable=self.a_vars["gstin"]))
        form_row(p, 10, "UPI ID", ttk.Entry(p, textvariable=self.a_vars["vpa"]))
        ttk.Label(p, text="e.g. name.surname@oksbi", style="PanelMuted.TLabel").grid(row=11, column=1, sticky="w")
        ttk.Button(p, text="Open account", command=self.open_account).grid(row=12, column=0, columnspan=2,
                                                                          sticky="ew", padx=12, pady=12)
        right = ttk.Frame(f)
        right.pack(side="left", fill="both", expand=True)
        bar = ttk.Frame(right)
        bar.pack(fill="x", pady=(0, 6))
        ttk.Label(bar, text="Accounts (support view, masked)", style="Section.TLabel").pack(side="left")
        self.a_filter = tk.StringVar()
        ttk.Button(bar, text="Show", style="Secondary.TButton", command=self.load_accounts).pack(side="right")
        e = ttk.Entry(bar, textvariable=self.a_filter, width=12)
        e.pack(side="right", padx=8)
        e.bind("<Return>", lambda ev: self.load_accounts())
        ttk.Label(bar, text="Customer ID").pack(side="right")
        self.a_table = DataTable(right, height=20)
        self.a_table.pack(fill="both", expand=True)

        def load_branches():
            _, rows = self.db.query("SELECT br.ifsc, b.bank_name, br.city FROM branch br "
                                    "JOIN bank b ON b.bank_code = br.bank_code ORDER BY b.bank_name, br.city")
            self.ifsc_box["values"] = [f"{r[0]}  |  {r[1]}  |  {r[2]}" for r in rows]
        self.safe(load_branches)
        self.load_accounts()

    def load_accounts(self):
        cid = self.a_filter.get().strip()
        if cid.isdigit():
            data = lambda: self.db.query("SELECT * FROM v_support_customer WHERE customer_id = %s", (cid,))
        else:
            data = lambda: self.db.query("SELECT * FROM v_support_customer ORDER BY account_id DESC LIMIT 300")
        self.safe(lambda: self.a_table.show(*data()))

    def open_account(self):
        v = {k: var.get().strip() for k, var in self.a_vars.items()}
        typ = self.a_type.get()

        def num(x):
            return float(x) if x else None

        def run():
            ifsc = v["ifsc"].split("|")[0].strip()
            out, _ = self.db.call("sp_open_account", [
                int(v["cust"]), ifsc, v["accno"], typ, num(v["deposit"]) or 0,
                num(v["rate"]) if typ == "SAVINGS" else None,
                num(v["minbal"]) if typ == "SAVINGS" else None,
                v["biz"] or None if typ == "CURRENT" else None,
                v["gstin"] or None if typ == "CURRENT" else None,
                v["vpa"], 0])
            self.say(f"Account {out[-1]} opened with UPI ID {v['vpa']}")
            messagebox.showinfo("Account opened", f"Account ID {out[-1]} created.")
            self.a_filter.set(v["cust"])
            self.load_accounts()
        self.safe(run)

    # ----------------------------------------------------------- payments
    def tab_payments(self):
        f = ttk.Frame(self.nb, padding=12)
        self.nb.add(f, text="Payments")
        p = self.side_panel(f, "Send money  (sp_transfer)")
        self.p_vars = {k: tk.StringVar() for k in ("payer", "payee", "amount", "device", "remarks")}
        form_row(p, 1, "Payer UPI ID", ttk.Entry(p, textvariable=self.p_vars["payer"]))
        form_row(p, 2, "Payee UPI ID", ttk.Entry(p, textvariable=self.p_vars["payee"]))
        form_row(p, 3, "Amount (Rs.)", ttk.Entry(p, textvariable=self.p_vars["amount"]))
        form_row(p, 4, "Device ID", ttk.Entry(p, textvariable=self.p_vars["device"]))
        form_row(p, 5, "Remarks", ttk.Entry(p, textvariable=self.p_vars["remarks"]))
        ttk.Button(p, text="Pay", command=self.pay).grid(row=6, column=0, columnspan=2, sticky="ew", padx=12, pady=12)
        self.pay_result = tk.StringVar(value="")
        ttk.Label(p, textvariable=self.pay_result, style="Panel.TLabel", wraplength=300,
                  justify="left").grid(row=7, column=0, columnspan=2, sticky="w", padx=12)

        ttk.Label(p, text="Customer statement", style="PanelSection.TLabel").grid(row=8, column=0, columnspan=2,
                                                                                  sticky="w", padx=12, pady=(18, 4))
        self.s_vars = {"cust": tk.StringVar(value="1001"), "from": tk.StringVar(value="2026-10-01"),
                       "to": tk.StringVar(value=time.strftime("%Y-%m-%d"))}
        form_row(p, 9, "Customer ID", ttk.Entry(p, textvariable=self.s_vars["cust"]))
        form_row(p, 10, "From", ttk.Entry(p, textvariable=self.s_vars["from"]))
        form_row(p, 11, "To", ttk.Entry(p, textvariable=self.s_vars["to"]))
        ttk.Button(p, text="Show statement", style="Secondary.TButton", command=self.statement).grid(
            row=12, column=0, columnspan=2, sticky="ew", padx=12, pady=8)

        right = ttk.Frame(f)
        right.pack(side="left", fill="both", expand=True)
        self.p_title = tk.StringVar(value="Latest transactions")
        ttk.Label(right, textvariable=self.p_title, style="Section.TLabel").pack(anchor="w", pady=(0, 6))
        self.p_table = DataTable(right, height=22)
        self.p_table.pack(fill="both", expand=True)
        self.load_payments()

    def load_payments(self):
        self.p_title.set("Latest transactions")
        self.safe(lambda: self.p_table.show(*self.db.query(
            "SELECT txn_id, txn_time, payer_vpa, payee_vpa, amount, txn_type, status, failure_reason "
            "FROM upi_txn ORDER BY txn_time DESC, txn_id DESC LIMIT 100")))

    def pay(self):
        v = {k: var.get().strip() for k, var in self.p_vars.items()}
        try:
            amount = float(v["amount"])
        except ValueError:
            messagebox.showwarning("Invalid amount", "Enter a numeric amount.")
            return

        def run():
            out, _ = self.db.call("sp_transfer", [v["payer"], v["payee"], amount, v["device"] or None,
                                                  v["remarks"] or None, 0, "", ""])
            txn, status, msg = out[5], out[6], out[7]
            self.pay_result.set(f"{status}: {msg}" + (f"  (txn {txn})" if txn else ""))
            alerts = 0
            if txn:
                alerts = self.db.scalar("SELECT COUNT(*) FROM fraud_alert WHERE txn_id = %s", (txn,))
            if alerts:
                self.pay_result.set(self.pay_result.get() + f"\n{alerts} fraud alert(s) raised by trigger")
            self.say(f"Payment {status.lower()}: {msg}")
            self.load_payments()
            self.load_dashboard()
        self.safe(run)

    def statement(self):
        v = {k: var.get().strip() for k, var in self.s_vars.items()}

        def run():
            _, results = self.db.call("sp_customer_statement", [int(v["cust"]), v["from"], v["to"]])
            cols, rows = results[0] if results else ([], [])
            self.p_title.set(f"Statement of customer {v['cust']}  ({len(rows)} entries)")
            self.p_table.show(cols, rows)
        self.safe(run)

    # ----------------------------------------------------------- fraud
    def tab_fraud(self):
        f = ttk.Frame(self.nb, padding=12)
        self.nb.add(f, text="Fraud & Disputes")
        p = self.side_panel(f, "Review selected alert")
        self.al_status = tk.StringVar(value="CONFIRMED_FRAUD")
        self.al_note = tk.StringVar()
        form_row(p, 1, "Decision", ttk.Combobox(p, textvariable=self.al_status, state="readonly",
                                                values=["OPEN", "INVESTIGATING", "CONFIRMED_FRAUD", "FALSE_POSITIVE"]))
        form_row(p, 2, "Analyst note", ttk.Entry(p, textvariable=self.al_note))
        ttk.Button(p, text="Save decision", command=self.update_alert).grid(row=3, column=0, columnspan=2,
                                                                           sticky="ew", padx=12, pady=10)
        ttk.Label(p, text="Raise dispute", style="PanelSection.TLabel").grid(row=4, column=0, columnspan=2,
                                                                             sticky="w", padx=12, pady=(18, 4))
        self.d_vars = {"txn": tk.StringVar(), "cust": tk.StringVar(), "reason": tk.StringVar(value="NOT_RECEIVED"),
                       "desc": tk.StringVar()}
        form_row(p, 5, "Transaction ID", ttk.Entry(p, textvariable=self.d_vars["txn"]))
        form_row(p, 6, "Customer ID", ttk.Entry(p, textvariable=self.d_vars["cust"]))
        form_row(p, 7, "Reason", ttk.Combobox(p, textvariable=self.d_vars["reason"], state="readonly",
                                              values=["NOT_RECEIVED", "WRONG_AMOUNT", "UNAUTHORIZED",
                                                      "DUPLICATE", "MERCHANT_ISSUE"]))
        form_row(p, 8, "Description", ttk.Entry(p, textvariable=self.d_vars["desc"]))
        ttk.Button(p, text="Raise dispute", style="Secondary.TButton", command=self.raise_dispute).grid(
            row=9, column=0, columnspan=2, sticky="ew", padx=12, pady=10)

        right = ttk.Frame(f)
        right.pack(side="left", fill="both", expand=True)
        bar = ttk.Frame(right)
        bar.pack(fill="x", pady=(0, 6))
        ttk.Label(bar, text="Fraud alerts", style="Section.TLabel").pack(side="left")
        self.al_filter = tk.StringVar(value="All")
        cb = ttk.Combobox(bar, textvariable=self.al_filter, state="readonly", width=18,
                          values=["All", "OPEN", "INVESTIGATING", "CONFIRMED_FRAUD", "FALSE_POSITIVE"])
        cb.pack(side="right")
        cb.bind("<<ComboboxSelected>>", lambda e: self.load_alerts())
        ttk.Label(bar, text="Status").pack(side="right", padx=8)
        self.al_table = DataTable(right, height=11)
        self.al_table.pack(fill="both", expand=True)
        ttk.Label(right, text="Disputes", style="Section.TLabel").pack(anchor="w", pady=(12, 6))
        self.d_table = DataTable(right, height=8)
        self.d_table.pack(fill="both", expand=True)
        self.load_alerts()

    def load_alerts(self):
        st = self.al_filter.get()

        def run():
            sql = ("SELECT alert_id, alert_time, rule_code, severity, alert_status, txn_id, amount, "
                   "payer_name, payer_vpa, payee_vpa, analyst_note FROM v_fraud_analyst_alerts")
            params = ()
            if st != "All":
                sql += " WHERE alert_status = %s"
                params = (st,)
            self.al_table.show(*self.db.query(sql + " ORDER BY alert_time DESC", params))
            self.d_table.show(*self.db.query(
                "SELECT d.txn_id, d.dispute_no, c.full_name AS raised_by, d.reason, d.status, d.raised_on, "
                "d.resolved_on, d.description FROM dispute d JOIN customer c ON c.customer_id = d.raised_by "
                "ORDER BY d.raised_on DESC"))
        self.safe(run)

    def update_alert(self):
        row = self.al_table.selected()
        if not row:
            messagebox.showwarning("No selection", "Select an alert in the table first.")
            return

        def run():
            self.db.execute("UPDATE fraud_alert SET status = %s, analyst_note = %s WHERE alert_id = %s",
                            (self.al_status.get(), self.al_note.get() or None, row["alert_id"]))
            self.say(f"Alert {row['alert_id']} -> {self.al_status.get()} (recorded in audit log)")
            self.load_alerts()
        self.safe(run)

    def raise_dispute(self):
        v = {k: var.get().strip() for k, var in self.d_vars.items()}

        def run():
            self.db.call("sp_raise_dispute", [int(v["txn"]), int(v["cust"]), v["reason"], v["desc"] or None])
            self.say(f"Dispute raised on transaction {v['txn']}")
            self.load_alerts()
        self.safe(run)

    # ----------------------------------------------------------- reports
    REPORTS = {
        "Merchant performance (view)": "SELECT * FROM v_merchant_performance ORDER BY total_collected DESC",
        "Daily merchant volume (materialized view)":
            "SELECT * FROM mv_daily_merchant_volume ORDER BY txn_date DESC, gross_amount DESC",
        "City fraud statistics (materialized view)": "SELECT * FROM mv_city_fraud_stats ORDER BY fraud_rate_pct DESC",
        "Public city statistics (statistical view)": "SELECT * FROM v_public_city_stats",
        "Merchant settlements": "SELECT s.*, m.merchant_name FROM settlement s JOIN merchant m "
                                "ON m.merchant_id = s.merchant_id ORDER BY settle_date DESC, gross_amount DESC",
        "Audit trail": "SELECT * FROM v_auditor_trail ORDER BY log_id DESC",
        "Fraud rules": "SELECT * FROM fraud_rule",
        "Security levels (MAC)": "SELECT * FROM security_level",
    }

    def tab_reports(self):
        f = ttk.Frame(self.nb, padding=12)
        self.nb.add(f, text="Reports")
        bar = ttk.Frame(f)
        bar.pack(fill="x", pady=(0, 8))
        ttk.Label(bar, text="Report").pack(side="left")
        self.r_choice = tk.StringVar(value=list(self.REPORTS)[0])
        cb = ttk.Combobox(bar, textvariable=self.r_choice, values=list(self.REPORTS), state="readonly", width=42)
        cb.pack(side="left", padx=8)
        cb.bind("<<ComboboxSelected>>", lambda e: self.load_report())
        ttk.Button(bar, text="Refresh materialized views", style="Secondary.TButton",
                   command=self.refresh_mv).pack(side="right")
        self.settle_date = tk.StringVar(value="2026-10-23")
        ttk.Button(bar, text="Settle merchants", style="Secondary.TButton",
                   command=self.settle).pack(side="right", padx=8)
        ttk.Entry(bar, textvariable=self.settle_date, width=12).pack(side="right")
        ttk.Label(bar, text="Date").pack(side="right", padx=6)
        self.r_table = DataTable(f, height=24)
        self.r_table.pack(fill="both", expand=True)
        self.load_report()

    def load_report(self):
        self.safe(lambda: self.r_table.show(*self.db.query(self.REPORTS[self.r_choice.get()])))

    def refresh_mv(self):
        def run():
            self.db.call("sp_refresh_all_mv", [])
            self.say("Materialized views refreshed")
            self.load_report()
        self.safe(run)

    def settle(self):
        def run():
            out, _ = self.db.call("sp_settle_merchants", [self.settle_date.get(), 0, 0])
            self.say(f"Settlement {self.settle_date.get()}: {out[1]} settled, {out[2]} skipped (savepoint rollback)")
            self.r_choice.set("Merchant settlements")
            self.load_report()
        self.safe(run)

    # ----------------------------------------------------------- console
    def tab_console(self):
        f = ttk.Frame(self.nb, padding=12)
        self.nb.add(f, text="SQL Console")
        bar = ttk.Frame(f)
        bar.pack(fill="x", pady=(0, 8))
        ttk.Label(bar, text="Category").pack(side="left")
        self.q_cat = tk.StringVar(value=list(CATALOG)[0])
        cat = ttk.Combobox(bar, textvariable=self.q_cat, values=list(CATALOG), state="readonly", width=28)
        cat.pack(side="left", padx=8)
        ttk.Label(bar, text="Query").pack(side="left", padx=(10, 0))
        self.q_name = tk.StringVar()
        self.q_box = ttk.Combobox(bar, textvariable=self.q_name, state="readonly", width=44)
        self.q_box.pack(side="left", padx=8)
        cat.bind("<<ComboboxSelected>>", lambda e: self.fill_queries())
        self.q_box.bind("<<ComboboxSelected>>", lambda e: self.load_query())
        ttk.Button(bar, text="Run  (Ctrl+Enter)", command=self.run_sql).pack(side="right")

        mono = ("Consolas", 10) if "Consolas" in tkfont.families() else ("DejaVu Sans Mono", 10)
        self.sql_text = tk.Text(f, height=8, font=mono, bg=WHITE, fg=BLACK, insertbackground=BLACK,
                                relief="solid", borderwidth=1, highlightthickness=0, padx=8, pady=6)
        self.sql_text.pack(fill="x")
        self.sql_text.bind("<Control-Return>", lambda e: (self.run_sql(), "break")[1])
        self.q_info = tk.StringVar(value="Pick a query or type your own SQL (one statement).")
        ttk.Label(f, textvariable=self.q_info, style="Muted.TLabel").pack(anchor="w", pady=6)
        self.q_table = DataTable(f, height=16)
        self.q_table.pack(fill="both", expand=True)
        self.fill_queries()

    def fill_queries(self):
        items = CATALOG[self.q_cat.get()]
        self.q_box["values"] = [t for t, _ in items]
        self.q_name.set(items[0][0])
        self.load_query()

    def load_query(self):
        for t, sql in CATALOG[self.q_cat.get()]:
            if t == self.q_name.get():
                self.sql_text.delete("1.0", "end")
                self.sql_text.insert("1.0", sql)

    def run_sql(self):
        sql = self.sql_text.get("1.0", "end").strip().rstrip(";")
        if not sql:
            return

        def run():
            t0 = time.perf_counter()
            cols, rows, affected = self.db.run_any(sql)
            ms = (time.perf_counter() - t0) * 1000
            if cols:
                self.q_table.show(cols, rows)
                self.q_info.set(f"{len(rows)} row(s) returned in {ms:.1f} ms")
            else:
                self.q_table.show([], [])
                self.q_info.set(f"Statement executed - {affected} row(s) affected ({ms:.1f} ms)")
            self.say("Query executed")
        self.safe(run)


if __name__ == "__main__":
    app = App()
    try:
        app.mainloop()
    except tk.TclError:
        pass
