"""
Generates the ER diagram (Chen notation), the relational schema diagram and the
data dictionary.  Needs Graphviz ('dot') and a running upishield database.
    python docs/generate_diagrams.py
"""
import os
import subprocess
import mysql.connector

HERE = os.path.dirname(os.path.abspath(__file__))

# ======================================================================
# 1. ER DIAGRAM (Chen notation)
# ======================================================================
ENT = {  # entity: [(attr, kind)]  kind: k=key, p=partial key, d=derived, a=normal
    "BANK": [("bank_code", "k"), ("bank_name", "a"), ("bank_type", "a"), ("hq_city", "a")],
    "BRANCH": [("ifsc", "k"), ("branch_name", "a"), ("city", "a"), ("state", "a")],
    "CUSTOMER": [("customer_id", "k"), ("full_name", "a"), ("phone", "a"), ("email", "a"),
                 ("dob", "a"), ("age", "d"), ("city", "a"), ("kyc_status", "a")],
    "BANK_ACCOUNT": [("account_id", "k"), ("account_no", "a"), ("balance", "a"),
                     ("account_type", "a"), ("status", "a"), ("opened_on", "a")],
    "SAVINGS": [("interest_rate", "a"), ("min_balance", "a")],
    "CURRENT": [("business_name", "a"), ("gstin", "a")],
    "VPA": [("vpa_id", "k"), ("is_primary", "a"), ("created_on", "a")],
    "MERCHANT": [("merchant_id", "k"), ("merchant_name", "a"), ("city", "a"), ("merchant_type", "a")],
    "SMALL": [("daily_limit", "a"), ("static_qr", "a")],
    "ENTERPRISE": [("mdr_rate", "a"), ("settlement_cycle", "a")],
    "MERCHANT_CATEGORY": [("mcc", "k"), ("description", "a"), ("risk_level", "a")],
    "DEVICE": [("device_id", "k"), ("model", "a"), ("os", "a"), ("first_seen", "a")],
    "UPI_TXN": [("txn_id", "k"), ("amount", "a"), ("status", "a"), ("txn_time", "a"),
                ("txn_type", "d"), ("remarks", "a")],
    "FRAUD_RULE": [("rule_id", "k"), ("rule_code", "a"), ("threshold", "a"), ("severity", "a")],
    "DISPUTE": [("dispute_no", "p"), ("reason", "a"), ("status", "a"), ("raised_on", "a")],
    "SETTLEMENT": [("settlement_id", "k"), ("settle_date", "a"), ("gross_amount", "a"), ("net_amount", "a")],
}
WEAK = {"DISPUTE"}
# (name, left, right, card_left, card_right, total_left, total_right, attrs, identifying)
REL = [
    ("HAS", "BANK", "BRANCH", "1", "N", False, True, [], False),
    ("HELD_AT", "BRANCH", "BANK_ACCOUNT", "1", "N", False, True, [], False),
    ("OWNS", "CUSTOMER", "BANK_ACCOUNT", "1", "N", False, True, [], False),
    ("REFERS", "CUSTOMER", "CUSTOMER", "1", "N", False, False, [], False),
    ("LINKED_TO", "BANK_ACCOUNT", "VPA", "1", "N", False, True, [], False),
    ("COLLECTS_VIA", "MERCHANT", "VPA", "1", "1", True, False, [], False),
    ("BELONGS_TO", "MERCHANT", "MERCHANT_CATEGORY", "N", "1", True, False, [], False),
    ("PAYS", "VPA", "UPI_TXN", "1", "N", False, True, [], False),
    ("RECEIVES", "VPA", "UPI_TXN", "1", "N", False, True, [], False),
    ("USED_FOR", "DEVICE", "UPI_TXN", "1", "N", False, False, [], False),
    ("LOGS_IN", "CUSTOMER", "DEVICE", "M", "N", False, True, ["login_time", "ip_address"], False),
    ("SAVES", "CUSTOMER", "VPA", "M", "N", False, False, ["nickname", "added_on"], False),
    ("FLAGS", "FRAUD_RULE", "UPI_TXN", "M", "N", False, False, ["alert_time", "alert_status"], False),
    ("HAS_DISPUTE", "UPI_TXN", "DISPUTE", "1", "N", False, True, [], True),
    ("RAISES", "CUSTOMER", "DISPUTE", "1", "N", False, True, [], False),
    ("SETTLED_IN", "MERCHANT", "SETTLEMENT", "1", "N", False, True, [], False),
]
SPEC = [("BANK_ACCOUNT", ["SAVINGS", "CURRENT"]), ("MERCHANT", ["SMALL", "ENTERPRISE"])]


def erd_dot():
    L = ['graph ERD {', 'layout=neato; overlap=false; sep="+14"; splines=true; outputorder=edgesfirst;',
         'bgcolor="white"; pad=0.4; fontname="Helvetica";',
         'node [fontname="Helvetica", fontsize=11, color="#111111", fontcolor="#111111"];',
         'edge [color="#333333", fontname="Helvetica", fontsize=11, len=1.4];',
         'label="UPIShield - ER Diagram (Chen notation)   |   double line = total participation, '
         'double box = weak entity, double diamond = identifying relationship, dashed = derived, '
         'underline = key, dashed underline = partial key, (d) = disjoint specialization"; labelloc=t; fontsize=13;']
    for e, attrs in ENT.items():
        style = 'peripheries=2' if e in WEAK else 'peripheries=1'
        L.append(f'"{e}" [shape=box, style="filled", fillcolor="#E6E6E6", fontsize=12, {style}, label=<<b>{e}</b>>];')
        for a, k in attrs:
            nid = f"{e}.{a}"
            if k == "k":
                lab = f"<<u>{a}</u>>"
            elif k == "p":
                lab = f"<<u>{a}</u>>"
            else:
                lab = f'"{a}"'
            st = ', style=dashed' if k == "d" else (', style="dashed"' if k == "p" else '')
            L.append(f'"{nid}" [shape=ellipse, fontsize=9, height=0.3, label={lab}{st}];')
            L.append(f'"{e}" -- "{nid}" [len=0.9];')
    for i, (n, a, b, ca, cb, ta, tb, attrs, ident) in enumerate(REL):
        rid = f"R{i}_{n}"
        per = 2 if ident else 1
        L.append(f'"{rid}" [shape=diamond, style=filled, fillcolor="white", peripheries={per}, '
                 f'fontsize=9, label="{n}", width=1.3, height=0.6];')
        def edge(ent, card, total):
            col = 'color="#111111:white:#111111"' if total else 'color="#333333"'
            return f'"{ent}" -- "{rid}" [{col}, label="{card}", fontcolor="#111111"];'
        L.append(edge(a, ca, ta))
        L.append(edge(b, cb, tb))
        for at in attrs:
            L.append(f'"{rid}.{at}" [shape=ellipse, fontsize=9, height=0.3, label="{at}"];')
            L.append(f'"{rid}" -- "{rid}.{at}" [len=0.8];')
    for sup, subs in SPEC:
        sid = f"ISA_{sup}"
        L.append(f'"{sid}" [shape=circle, label="d", width=0.4, fixedsize=true, style=filled, fillcolor="white"];')
        L.append(f'"{sup}" -- "{sid}" [color="#111111:white:#111111", len=0.8];')
        for s in subs:
            L.append(f'"{sid}" -- "{s}" [len=0.8, label="⊂"];')
    L.append("}")
    return "\n".join(L)


# ======================================================================
# 2. SCHEMA DIAGRAM + DATA DICTIONARY (read from information_schema)
# ======================================================================
def fetch(cur, sql):
    cur.execute(sql)
    return cur.fetchall()


def main():
    with open(os.path.join(HERE, "erd.dot"), "w") as f:
        f.write(erd_dot())
    subprocess.run(["dot", "-Kneato", "-Tpng", "-Gdpi=110", "erd.dot", "-o", "erd.png"], cwd=HERE, check=True)
    subprocess.run(["dot", "-Kneato", "-Tsvg", "erd.dot", "-o", "erd.svg"], cwd=HERE, check=True)

    conn = mysql.connector.connect(host="localhost", user=os.environ.get("DB_USER", "root"),
                                   password=os.environ.get("DB_PASS", ""), database="upishield")
    cur = conn.cursor()
    tables = [r[0] for r in fetch(cur, "SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA='upishield' "
                                        "AND TABLE_TYPE='BASE TABLE' AND TABLE_NAME NOT LIKE 'stg%' ORDER BY TABLE_NAME")]
    cols = fetch(cur, "SELECT TABLE_NAME, COLUMN_NAME, COLUMN_TYPE, IS_NULLABLE, COLUMN_KEY, COLUMN_DEFAULT, EXTRA "
                      "FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='upishield' ORDER BY TABLE_NAME, ORDINAL_POSITION")
    fks = fetch(cur, "SELECT k.TABLE_NAME, k.COLUMN_NAME, k.REFERENCED_TABLE_NAME, k.REFERENCED_COLUMN_NAME, "
                     "r.UPDATE_RULE, r.DELETE_RULE FROM information_schema.KEY_COLUMN_USAGE k "
                     "JOIN information_schema.REFERENTIAL_CONSTRAINTS r ON r.CONSTRAINT_NAME = k.CONSTRAINT_NAME "
                     "AND r.CONSTRAINT_SCHEMA = k.CONSTRAINT_SCHEMA WHERE k.TABLE_SCHEMA='upishield' "
                     "AND k.REFERENCED_TABLE_NAME IS NOT NULL")
    pks = fetch(cur, "SELECT TABLE_NAME, COLUMN_NAME FROM information_schema.KEY_COLUMN_USAGE "
                     "WHERE TABLE_SCHEMA='upishield' AND CONSTRAINT_NAME='PRIMARY'")
    uqs = fetch(cur, "SELECT k.TABLE_NAME, k.COLUMN_NAME FROM information_schema.KEY_COLUMN_USAGE k "
                     "JOIN information_schema.TABLE_CONSTRAINTS t ON t.CONSTRAINT_NAME=k.CONSTRAINT_NAME "
                     "AND t.TABLE_NAME=k.TABLE_NAME AND t.TABLE_SCHEMA=k.TABLE_SCHEMA "
                     "WHERE k.TABLE_SCHEMA='upishield' AND t.CONSTRAINT_TYPE='UNIQUE'")
    checks = fetch(cur, "SELECT t.TABLE_NAME, c.CONSTRAINT_NAME, c.CHECK_CLAUSE FROM information_schema.CHECK_CONSTRAINTS c "
                        "JOIN information_schema.TABLE_CONSTRAINTS t ON t.CONSTRAINT_NAME=c.CONSTRAINT_NAME "
                        "AND t.CONSTRAINT_SCHEMA=c.CONSTRAINT_SCHEMA WHERE c.CONSTRAINT_SCHEMA='upishield' "
                        "ORDER BY t.TABLE_NAME, c.CONSTRAINT_NAME")
    pk = {(t, c) for t, c in pks}
    uq = {(t, c) for t, c in uqs}
    fk = {(t, c): (rt, rc, ur, dr) for t, c, rt, rc, ur, dr in fks}

    # schema diagram
    D = ['digraph schema {', 'rankdir=LR; nodesep=0.35; ranksep=1.0; bgcolor="white"; pad=0.3;',
         'node [shape=plaintext, fontname="Helvetica", fontsize=10];',
         'edge [color="#555555", arrowsize=0.7, fontname="Helvetica", fontsize=8];',
         'label="UPIShield - Relational Schema (PK = primary key, FK = foreign key, U = unique)"; labelloc=t; fontsize=14;']
    for t in tables:
        rows = [f'<tr><td bgcolor="#111111" colspan="3"><font color="white"><b>{t}</b></font></td></tr>']
        for tn, cn, ct, nul, key, dflt, extra in cols:
            if tn != t:
                continue
            tag = " ".join(x for x in ["PK" if (t, cn) in pk else "", "FK" if (t, cn) in fk else "",
                                       "U" if (t, cn) in uq else ""] if x)
            name = f"<b>{cn}</b>" if (t, cn) in pk else cn
            rows.append(f'<tr><td align="left" port="{cn}">{name}</td><td align="left"><font color="#555555">{ct}</font></td>'
                        f'<td align="left">{tag}</td></tr>')
        D.append(f'"{t}" [label=<<table border="1" cellborder="0" cellspacing="0" cellpadding="3" bgcolor="#F4F4F4">'
                 + "".join(rows) + "</table>>];")
    for (t, c), (rt, rc, ur, dr) in fk.items():
        if t in tables and rt in tables:
            D.append(f'"{t}":"{c}" -> "{rt}":"{rc}";')
    D.append("}")
    with open(os.path.join(HERE, "schema_diagram.dot"), "w") as f:
        f.write("\n".join(D))
    subprocess.run(["dot", "-Tpng", "-Gdpi=100", "schema_diagram.dot", "-o", "schema_diagram.png"], cwd=HERE, check=True)
    subprocess.run(["dot", "-Tsvg", "schema_diagram.dot", "-o", "schema_diagram.svg"], cwd=HERE, check=True)

    # data dictionary
    M = ["# UPIShield - Data Dictionary", "",
         "Generated from `information_schema` (run `python docs/generate_diagrams.py` to refresh).", "",
         "Key: **PK** primary key, **FK** foreign key, **U** unique, NN = NOT NULL.", ""]
    for t in tables:
        M.append(f"## {t}")
        M.append("")
        M.append("| Column | Domain (type) | NN | Key | Default | References (on update / on delete) |")
        M.append("|---|---|---|---|---|---|")
        for tn, cn, ct, nul, key, dflt, extra in cols:
            if tn != t:
                continue
            k = " ".join(x for x in ["PK" if (t, cn) in pk else "", "FK" if (t, cn) in fk else "",
                                     "U" if (t, cn) in uq else ""] if x)
            ref = ""
            if (t, cn) in fk:
                rt, rc, ur, dr = fk[(t, cn)]
                ref = f"{rt}({rc}) - {ur} / {dr}"
            d = (dflt or "") + (" " + extra if extra else "")
            M.append(f"| {cn} | {ct} | {'yes' if nul == 'NO' else ''} | {k} | {d.strip()} | {ref} |")
        ch = [(n, c) for tn, n, c in checks if tn == t]
        if ch:
            M.append("")
            M.append("CHECK constraints:")
            M.append("")
            for n, c in ch:
                M.append(f"- `{n}`: `{c}`")
        M.append("")
    with open(os.path.join(HERE, "data_dictionary.md"), "w") as f:
        f.write("\n".join(M))
    print("ERD, schema diagram and data dictionary written to", HERE)


if __name__ == "__main__":
    main()
