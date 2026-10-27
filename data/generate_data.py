"""
UPIShield - seed data generator
--------------------------------
Generates:
  sql/04_seed_data.sql      -> INSERT statements (thousands of rows)
  data/paysim_sample.csv    -> sample file in the PaySim column format, used by
                               sql/05_load_paysim.sql to demonstrate LOAD DATA INFILE

The data is synthetic but realistic, and it respects every business rule
(18+ customers, Rs. 1,00,000 daily limit, active accounts only, etc.), so it
can be loaded with all triggers switched on.  Fraud patterns are injected on
purpose so the fraud-monitoring triggers have something to catch.

Run from the project root:   python data/generate_data.py
(Not needed for normal use - the generated files are already included.)
"""
import csv
import os
import random
from datetime import date, datetime, timedelta

random.seed(2026)
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_SQL = os.path.join(ROOT, "sql", "04_seed_data.sql")
OUT_CSV = os.path.join(ROOT, "data", "paysim_sample.csv")

START = datetime(2026, 9, 1)
END = datetime(2026, 10, 23, 23, 59)
NOW = datetime(2026, 10, 24, 9, 0)


def q(v):
    """SQL literal."""
    if v is None:
        return "NULL"
    if isinstance(v, bool):
        return "TRUE" if v else "FALSE"
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, datetime):
        return "'" + v.strftime("%Y-%m-%d %H:%M:%S") + "'"
    if isinstance(v, date):
        return "'" + v.isoformat() + "'"
    return "'" + str(v).replace("\\", "\\\\").replace("'", "''") + "'"


def insert_block(table, cols, rows, chunk=200):
    out = []
    for i in range(0, len(rows), chunk):
        part = rows[i:i + chunk]
        out.append(f"INSERT INTO {table} ({', '.join(cols)}) VALUES")
        out.append(",\n".join("  (" + ", ".join(q(v) for v in r) + ")" for r in part) + ";")
    return "\n".join(out)


def rand_dt(a, b):
    return a + timedelta(seconds=random.randint(0, int((b - a).total_seconds())))


# ---------------------------------------------------------------- banks
BANKS = [
    ("SBIN", "State Bank of India", "PUBLIC", "Mumbai", 1955),
    ("PUNB", "Punjab National Bank", "PUBLIC", "New Delhi", 1894),
    ("BARB", "Bank of Baroda", "PUBLIC", "Vadodara", 1908),
    ("CNRB", "Canara Bank", "PUBLIC", "Bengaluru", 1906),
    ("UBIN", "Union Bank of India", "PUBLIC", "Mumbai", 1919),
    ("HDFC", "HDFC Bank", "PRIVATE", "Mumbai", 1994),
    ("ICIC", "ICICI Bank", "PRIVATE", "Mumbai", 1994),
    ("UTIB", "Axis Bank", "PRIVATE", "Mumbai", 1993),
    ("KKBK", "Kotak Mahindra Bank", "PRIVATE", "Mumbai", 2003),
    ("IDFB", "IDFC First Bank", "PRIVATE", "Mumbai", 2015),
    ("AIRP", "Airtel Payments Bank", "PAYMENTS", "New Delhi", 2017),
    ("KCCB", "Kalupur Commercial Co-operative Bank", "COOPERATIVE", "Ahmedabad", 1970),
]
CITIES = [
    ("Ahmedabad", "Gujarat", 14), ("Gandhinagar", "Gujarat", 10), ("Surat", "Gujarat", 7),
    ("Vadodara", "Gujarat", 6), ("Rajkot", "Gujarat", 4), ("Mumbai", "Maharashtra", 9),
    ("Pune", "Maharashtra", 6), ("Delhi", "Delhi", 7), ("Bengaluru", "Karnataka", 7),
    ("Hyderabad", "Telangana", 5), ("Chennai", "Tamil Nadu", 4), ("Kolkata", "West Bengal", 4),
    ("Jaipur", "Rajasthan", 4), ("Lucknow", "Uttar Pradesh", 3), ("Indore", "Madhya Pradesh", 3),
]
CITY_STATE = {c: s for c, s, _ in CITIES}
CITY_W = [w for _, _, w in CITIES]
STATE_GST = {"Gujarat": "24", "Maharashtra": "27", "Delhi": "07", "Karnataka": "29",
             "Telangana": "36", "Tamil Nadu": "33", "West Bengal": "19", "Rajasthan": "08",
             "Uttar Pradesh": "09", "Madhya Pradesh": "23"}
HANDLES = ["oksbi", "okhdfcbank", "okicici", "okaxis", "ybl", "paytm", "ibl", "axl"]


def pick_city():
    return random.choices([c for c, _, _ in CITIES], weights=CITY_W)[0]


branches = []
ifsc_by_bank = {}
used_ifsc = set()
for code, name, _, _, _ in BANKS:
    for k in range(4):
        city = pick_city() if k else random.choice(["Ahmedabad", "Gandhinagar", "Mumbai", "Delhi"])
        while True:
            ifsc = f"{code}0{random.randint(0, 999999):06d}"
            if ifsc not in used_ifsc:
                used_ifsc.add(ifsc)
                break
        bname = f"{city} {random.choice(['Main', 'Central', 'Station Road', 'Ring Road', 'Market Yard', 'Sector 21', 'CG Road', 'MG Road'])}"
        branches.append((ifsc, code, bname, city, CITY_STATE[city]))
        ifsc_by_bank.setdefault(code, []).append(ifsc)
ALL_IFSC = [b[0] for b in branches]

# ---------------------------------------------------------------- customers
FIRST = ["Aarav", "Vivaan", "Aditya", "Vihaan", "Arjun", "Sai", "Reyansh", "Krishna", "Ishaan", "Shaurya",
         "Jeet", "Dhruv", "Kabir", "Rohan", "Harsh", "Parth", "Yash", "Meet", "Karan", "Nirav",
         "Rahul", "Amit", "Vikram", "Siddharth", "Manav", "Dev", "Om", "Tanmay", "Kunal", "Hardik",
         "Aanya", "Diya", "Saanvi", "Ananya", "Pari", "Myra", "Isha", "Kavya", "Riya", "Priya",
         "Neha", "Pooja", "Sneha", "Krisha", "Hetvi", "Khushi", "Mahi", "Nidhi", "Janvi", "Tanvi",
         "Shreya", "Aditi", "Meera", "Radhika", "Divya", "Anjali", "Bhavna", "Komal", "Payal", "Zoya",
         "Farhan", "Imran", "Ayaan", "Sara", "Fatima", "Joseph", "Maria", "Gurpreet", "Simran", "Harpreet"]
LAST = ["Patel", "Shah", "Mehta", "Desai", "Joshi", "Trivedi", "Pandya", "Bhatt", "Parikh", "Modi",
        "Samani", "Sharma", "Verma", "Gupta", "Agarwal", "Singh", "Kumar", "Reddy", "Nair", "Iyer",
        "Rao", "Menon", "Kulkarni", "Deshpande", "Chatterjee", "Banerjee", "Das", "Khan", "Sheikh",
        "Fernandes", "DSouza", "Gill", "Sandhu", "Chauhan", "Rathod", "Solanki", "Vyas", "Thakkar",
        "Kapoor", "Malhotra", "Jain", "Saxena", "Mishra", "Tiwari", "Pillai"]

N_CUST = 320
customers = []          # (id, name, phone, email, dob, city, kyc, referred_by, created_at)
used_phone, used_email = set(), set()
for i in range(N_CUST):
    cid = 1001 + i
    fn, ln = random.choice(FIRST), random.choice(LAST)
    while True:
        phone = str(random.choice([6, 7, 8, 9])) + "".join(random.choice("0123456789") for _ in range(9))
        if phone not in used_phone:
            used_phone.add(phone)
            break
    email = None
    if random.random() < 0.92:
        base = f"{fn.lower()}.{ln.lower()}"
        email = f"{base}@{random.choice(['gmail.com', 'yahoo.co.in', 'outlook.com', 'rediffmail.com'])}"
        n = 1
        while email in used_email:
            n += 1
            email = f"{base}{n}@{email.split('@')[1]}"
        used_email.add(email)
    dob = date(1962, 1, 1) + timedelta(days=random.randint(0, (date(2006, 6, 30) - date(1962, 1, 1)).days))
    kyc = random.choices(["VERIFIED", "PENDING", "REJECTED"], [85, 10, 5])[0]
    ref = None
    if i > 20 and random.random() < 0.3:
        ref = 1001 + random.randint(0, i - 1)
    created = rand_dt(datetime(2023, 1, 1), datetime(2026, 6, 30))
    customers.append([cid, f"{fn} {ln}", phone, email, dob, pick_city(), kyc, ref, created])
# a known demo customer
customers[0][1] = "Aarav Mehta"
customers[0][5] = "Gandhinagar"
customers[0][6] = "VERIFIED"

# ---------------------------------------------------------------- accounts + vpas
accounts = []      # (id, cust, ifsc, accno, type, balance, status, opened)
savings, currents, vpas = [], [], []
used_acc, used_vpa = set(), set()
acc_id = 50001
personal_vpa = {}          # customer -> primary personal vpa (active, usable)
vpa_owner = {}             # vpa -> customer
vpa_account = {}
new_unused_accounts = []   # opened in Oct 2026, no transactions (cascade demo)


def new_accno():
    while True:
        a = "".join(random.choice("0123456789") for _ in range(random.choice([11, 12, 14, 15, 16])))
        if a[0] != "0" and a not in used_acc:
            used_acc.add(a)
            return a


def make_vpa(base, handle=None):
    base = "".join(ch for ch in base.lower() if ch.isalnum() or ch in "._")
    base = base.strip("._")[:30] or "user"
    handle = handle or random.choice(HANDLES)
    v = f"{base}@{handle}"
    n = 1
    while v in used_vpa:
        n += 1
        v = f"{base}{n}@{handle}"
    used_vpa.add(v)
    return v


def add_account(cust, typ, opened, status="ACTIVE", balance=None, business=None, gstin=None, vpa_base=None):
    global acc_id
    aid = acc_id
    acc_id += 1
    ifsc = random.choice(ALL_IFSC)
    if balance is None:
        balance = round(random.uniform(8000, 400000), 2) if typ == "SAVINGS" else round(random.uniform(100000, 2500000), 2)
    accounts.append([aid, cust[0], ifsc, new_accno(), typ, balance, status, opened])
    if typ == "SAVINGS":
        savings.append([aid, random.choice([2.70, 3.00, 3.25, 3.50, 4.00]), random.choice([0, 1000, 1000, 2500, 5000, 10000])])
    else:
        currents.append([aid, business, gstin])
    v = make_vpa(vpa_base or cust[1].replace(" ", "."))
    vpas.append([v, aid, True, opened])
    vpa_owner[v] = cust[0]
    vpa_account[v] = aid
    return aid, v


for c in customers:
    opened = (c[8] + timedelta(days=random.randint(0, 20))).date()
    if opened > date(2026, 7, 31):
        opened = date(2026, 7, 31)
    status = "ACTIVE"
    aid, v = add_account(c, "SAVINGS", opened)
    personal_vpa[c[0]] = v
    if random.random() < 0.22:
        add_account(c, "SAVINGS", opened + timedelta(days=random.randint(30, 300)))

# a few frozen / closed accounts (never used as payers)
inactive_accounts = set()
for a in random.sample([a for a in accounts if a[0] > 50001 and a[1] not in (1001,)], 8):
    a[6] = "FROZEN" if len(inactive_accounts) < 5 else "CLOSED"
    inactive_accounts.add(a[0])
inactive_vpas = {v for v, aid in vpa_account.items() if aid in inactive_accounts}
for cid, v in list(personal_vpa.items()):
    if v in inactive_vpas:
        del personal_vpa[cid]

# secondary mobile-number VPAs
for c in random.sample(customers, 40):
    if c[0] in personal_vpa:
        aid = vpa_account[personal_vpa[c[0]]]
        v = make_vpa(c[2], random.choice(["paytm", "ybl", "axl"]))
        vpas.append([v, aid, False, accounts[aid - 50001][7] + timedelta(days=random.randint(1, 200))])
        vpa_owner[v] = c[0]
        vpa_account[v] = aid

# ---------------------------------------------------------------- merchants
MCC = [
    ("5411", "Grocery Stores and Supermarkets", "LOW"),
    ("5812", "Restaurants and Eating Places", "LOW"),
    ("5814", "Fast Food Outlets", "LOW"),
    ("5541", "Fuel Stations", "LOW"),
    ("5912", "Pharmacies and Drug Stores", "LOW"),
    ("4121", "Taxi and Ride Sharing", "LOW"),
    ("4900", "Utilities - Electricity, Gas, Water", "LOW"),
    ("8220", "Colleges and Universities", "LOW"),
    ("5311", "Department Stores", "MEDIUM"),
    ("5732", "Electronics Stores", "MEDIUM"),
    ("7011", "Hotels and Lodging", "MEDIUM"),
    ("5944", "Jewellery Stores", "HIGH"),
    ("6051", "Crypto and Quasi-Cash", "HIGH"),
    ("7995", "Online Gaming and Betting", "HIGH"),
]
AMOUNT_RANGE = {"5411": (40, 2500), "5812": (150, 3000), "5814": (60, 900), "5541": (200, 4000),
                "5912": (50, 2200), "4121": (80, 950), "4900": (300, 6000), "8220": (5000, 60000),
                "5311": (300, 9000), "5732": (1500, 45000), "7011": (1500, 18000), "5944": (5000, 60000),
                "6051": (1000, 20000), "7995": (100, 6000)}
SMALL_SPECS = [("5411", ["Shree Ganesh Kirana", "Jay Ambe Provision Store", "Fresh Basket Mart", "Annapurna General Store",
                         "Krishna Super Market", "Daily Needs Bazaar", "Patel Grocery Point", "Om Sai Kirana",
                         "Green Leaf Vegetables", "Sanjivani Dairy"]),
               ("5812", ["Cafe Mocha Point", "Swati Snacks", "Honest Restaurant", "Gopi Dining Hall",
                         "Rajwadu Thali House", "Chai Sutta Corner"]),
               ("5814", ["Jassi De Parathe", "Tasty Bites Express", "Pizza Junction", "Vadapav Hub",
                         "Momos Point"]),
               ("5541", ["FuelUp Petroleum", "Highway Fuels", "City Petrol Pump"]),
               ("5912", ["Apollo Medicos Sector 21", "Shiv Medical Store", "Wellness Pharmacy",
                         "LifeCare Chemist"]),
               ("4121", ["Gandhinagar Auto Union", "Quick Ride Cabs", "Metro Taxi Service",
                         "Campus Rickshaw Stand"]),
               ("5311", ["Bharat Bazaar", "Sapna Fashion Store", "Trendz Garments", "Royal Footwear",
                         "Shubham Stationers", "Gift Gallery"]),
               ]
ENT_SPECS = [("5311", ["DMart Retail", "Reliance Smart", "Big Bazaar Plus"]),
             ("5732", ["Croma Electronics", "Vijay Sales", "Reliance Digital"]),
             ("7011", ["Hotel Grand Bhagwati", "The Leela Gandhinagar"]),
             ("4900", ["Torrent Power", "Adani Total Gas", "GSPC Gas"]),
             ("8220", ["PDEU Fee Collection", "Nirma University Fees"]),
             ("5944", ["Tanishq Jewellers", "Kalyan Jewellers"]),
             ("6051", ["CoinVault Exchange", "QuickCash Wallet"]),
             ("7995", ["Dream Fantasy Games", "LuckyPlay Gaming"])]
merchants, small_m, ent_m = [], [], []
merchant_by_vpa = {}
owners = random.sample([c for c in customers if c[0] != 1001], 60)
mid = 701
specs = [(mcc, n, "SMALL") for mcc, names in SMALL_SPECS for n in names]
specs += [(mcc, n, "ENTERPRISE") for mcc, names in ENT_SPECS for n in names]
specs = specs[:60]
for owner, (mcc, mname, mtype) in zip(owners, specs):
    opened = (owner[8] + timedelta(days=random.randint(5, 60))).date()
    if opened > date(2026, 7, 31):
        opened = date(2026, 7, 15)
    state = CITY_STATE[owner[5]]
    gstin = None
    if mtype == "ENTERPRISE" or random.random() < 0.4:
        letters = "".join(random.choice("ABCDEFGHIJKLMNOPQRSTUVWXYZ") for _ in range(5))
        gstin = f"{STATE_GST[state]}{letters}{random.randint(1000, 9999)}{random.choice('ABCDEFGHJKLMNPQRSTUVWXYZ')}{random.randint(1, 9)}Z{random.choice('0123456789ABCDEFGHJ')}"
    aid, v = add_account(owner, "CURRENT", opened, business=mname, gstin=gstin, vpa_base=mname.replace(" ", ""))
    merchants.append([mid, mname, v, mcc, owner[5], mtype, opened])
    merchant_by_vpa[v] = (mid, mcc, mtype)
    if mtype == "SMALL":
        small_m.append([mid, random.choice([100000, 200000, 200000, 500000]), random.random() < 0.8])
    else:
        ent_m.append([mid, random.choice([0.30, 0.50, 0.90, 1.10, 1.50, 2.00]), random.choice(["T+0", "T+1", "T+1", "T+2"]), True])
    mid += 1

# new accounts opened this month - no transactions yet (used in DELETE CASCADE demo)
for c in random.sample([c for c in customers if c[0] in personal_vpa and c[0] != 1001], 10):
    aid, v = add_account(c, "SAVINGS", date(2026, 10, random.randint(5, 22)))
    new_unused_accounts.append((aid, v))

# ---------------------------------------------------------------- devices
MODELS = [("Samsung Galaxy M34", "ANDROID", "14"), ("Redmi Note 13", "ANDROID", "14"), ("OnePlus Nord CE4", "ANDROID", "15"),
          ("Vivo T3", "ANDROID", "14"), ("Realme Narzo 70", "ANDROID", "14"), ("iPhone 15", "IOS", "18.2"),
          ("iPhone 13", "IOS", "17.6"), ("Google Pixel 8a", "ANDROID", "15"), ("Motorola G85", "ANDROID", "14"),
          ("Samsung Galaxy S24", "ANDROID", "15"), ("iPhone 16", "IOS", "18.5"), ("Poco X6", "ANDROID", "14")]
devices, logins = [], []
cust_devices = {}
dev_n = 100000


def new_device(first_seen):
    global dev_n
    dev_n += random.randint(1, 37)
    m = random.choice(MODELS)
    d = f"DEV{dev_n}"
    devices.append([d, m[0], m[1], m[2], first_seen])
    return d


def ip():
    return f"{random.choice([49, 103, 106, 117, 152, 157, 182, 223])}.{random.randint(0, 255)}.{random.randint(0, 255)}.{random.randint(1, 254)}"


for c in customers:
    n = 2 if random.random() < 0.15 else 1
    for _ in range(n):
        fs = rand_dt(c[8], datetime(2026, 8, 20))
        d = new_device(fs)
        cust_devices.setdefault(c[0], []).append(d)
        times = sorted({rand_dt(max(fs, datetime(2026, 8, 1)), NOW).replace(microsecond=0) for _ in range(random.randint(2, 4))})
        for t in times:
            logins.append([c[0], d, t, ip()])

# ---------------------------------------------------------------- transactions
contacts = {}
active_personal = [cid for cid in personal_vpa]
for cid in active_personal:
    contacts[cid] = random.sample([x for x in active_personal if x != cid], random.randint(5, 10))
low_merchants = [m for m in merchants if m[3] not in ("5944", "6051", "7995")]
high_merchants = [m for m in merchants if m[3] in ("5944", "6051", "7995")]
small_weight = [5 if m[5] == "SMALL" else 2 for m in low_merchants]

txns = []          # dicts
daily = {}         # (account, date) -> spent


def hour_pick():
    return random.choices(range(24), weights=[1, 1, 1, 1, 1, 2, 4, 6, 8, 8, 8, 8, 9, 8, 7, 7, 7, 8, 9, 10, 10, 9, 6, 3])[0]


def add_txn(payer, payee, amount, when, status=None, remarks=None, device=None, reason=None, inject=None):
    acc = vpa_account[payer]
    key = (acc, when.date())
    if status is None:
        status = random.choices(["SUCCESS", "FAILED", "PENDING"], [94, 4.5, 1.5])[0]
        if when > datetime(2026, 10, 23, 12) and random.random() < 0.3:
            status = "PENDING"
        elif status == "PENDING":
            status = "SUCCESS"
    if status == "FAILED" and reason is None:
        reason = random.choice(["Insufficient balance", "Incorrect UPI PIN", "Bank server timeout",
                                "Payee bank not reachable"])
    if status == "SUCCESS" and daily.get(key, 0) + amount > 100000:
        status, reason = "FAILED", "Daily UPI limit of Rs. 1,00,000 exceeded for this account"
    if status == "SUCCESS":
        daily[key] = daily.get(key, 0) + amount
    cust = vpa_owner[payer]
    dev = device or random.choice(cust_devices[cust])
    txns.append({"payer": payer, "payee": payee, "amount": round(amount, 2), "status": status,
                 "device": dev, "remarks": remarks, "reason": reason, "time": when, "inject": inject})


P2P_REMARKS = [None, None, None, "dinner split", "rent share", "movie tickets", "petrol", "birthday gift",
               "trip expenses", "thanks", "lunch", "groceries", "books", "cab fare", "loan return", "chai"]
for _ in range(2650):
    payer_c = random.choice(active_personal)
    payer = personal_vpa[payer_c]
    day = START + timedelta(days=random.randint(0, (END - START).days))
    when = day.replace(hour=hour_pick(), minute=random.randint(0, 59), second=random.randint(0, 59))
    if random.random() < 0.55:
        m = random.choices(low_merchants, weights=small_weight)[0]
        lo, hi = AMOUNT_RANGE[m[3]]
        amt = random.uniform(lo, hi) if random.random() < 0.85 else random.uniform(lo, (lo + hi) / 2)
        if m[3] in ("5411", "5814", "4121", "5912", "5812"):
            amt = round(amt)
        add_txn(payer, m[2], amt, when, remarks=None)
    else:
        friend = random.choice(contacts[payer_c]) if random.random() < 0.85 else random.choice(active_personal)
        if friend == payer_c:
            continue
        amt = min(random.lognormvariate(6.6, 1.1), 15000)
        if random.random() < 0.04:
            amt = random.uniform(20000, 45000)
        add_txn(payer, personal_vpa[friend], max(10, round(amt)), when, remarks=random.choice(P2P_REMARKS))

# some customers also pay from their secondary (mobile-number) VPA
secondary = [v for v in vpas if not v[2] and v[1] not in inactive_accounts]
for _ in range(120):
    v = random.choice(secondary)[0]
    m = random.choices(low_merchants, weights=small_weight)[0]
    lo, hi = AMOUNT_RANGE[m[3]]
    day = START + timedelta(days=random.randint(0, (END - START).days))
    add_txn(v, m[2], round(random.uniform(lo, min(hi, 5000))), day.replace(hour=hour_pick(), minute=random.randint(0, 59)))

# ---- injected fraud patterns
fraud_txn_keys = []
inject_pool = random.sample([c for c in active_personal if c != 1001], 40)
strangers = [personal_vpa[c] for c in random.sample(active_personal, 60)]


def fresh_payee(payer_c):
    known = set(personal_vpa[x] for x in contacts[payer_c])
    while True:
        s = random.choice(strangers)
        if s not in known and s != personal_vpa[payer_c]:
            return s


k = 0
for _ in range(8):          # R1 velocity bursts
    c = inject_pool[k]; k += 1
    t = rand_dt(START + timedelta(days=2), END - timedelta(days=1)).replace(second=0)
    for j in range(random.randint(6, 7)):
        add_txn(personal_vpa[c], fresh_payee(c), random.randint(2000, 9000),
                t + timedelta(seconds=40 * j + random.randint(0, 30)), status="SUCCESS",
                remarks=random.choice(["urgent", "help", None]), inject="VELOCITY")
for _ in range(8):          # R2 high value to a new payee
    c = inject_pool[k]; k += 1
    t = rand_dt(START + timedelta(days=2), END - timedelta(days=1)).replace(hour=random.randint(10, 21))
    add_txn(personal_vpa[c], fresh_payee(c), random.randint(50000, 95000), t, status="SUCCESS",
            remarks=random.choice(["KYC update charges", "lottery processing fee", "refund", None]), inject="HIGH_VALUE")
for _ in range(8):          # R3 night high value
    c = inject_pool[k]; k += 1
    t = rand_dt(START + timedelta(days=2), END - timedelta(days=1)).replace(hour=random.randint(1, 4))
    add_txn(personal_vpa[c], random.choice([personal_vpa[x] for x in contacts[c]]), random.randint(20000, 45000), t,
            status="SUCCESS", inject="NIGHT")
for _ in range(6):          # R4 new device
    c = inject_pool[k]; k += 1
    t = rand_dt(START + timedelta(days=2), END - timedelta(days=1)).replace(hour=random.randint(9, 22))
    d = new_device(t - timedelta(hours=random.randint(1, 6), minutes=random.randint(0, 59)))
    logins.append([c, d, devices[-1][4] + timedelta(minutes=5), ip()])
    add_txn(personal_vpa[c], fresh_payee(c), random.randint(12000, 40000), t, status="SUCCESS", device=d, inject="NEW_DEVICE")
for _ in range(6):          # R5 high-risk merchant
    c = inject_pool[k]; k += 1
    m = random.choice(high_merchants)
    t = rand_dt(START + timedelta(days=2), END - timedelta(days=1)).replace(hour=random.randint(10, 23))
    add_txn(personal_vpa[c], m[2], random.randint(25000, 60000), t, status="SUCCESS", inject="HIGH_RISK_MERCHANT")
for _ in range(3):          # account takeover: new device + night + big amount to stranger
    c = inject_pool[k]; k += 1
    t = rand_dt(START + timedelta(days=5), END - timedelta(days=1)).replace(hour=random.randint(1, 3))
    d = new_device(t - timedelta(hours=2))
    logins.append([c, d, devices[-1][4] + timedelta(minutes=3), ip()])
    add_txn(personal_vpa[c], fresh_payee(c), random.randint(55000, 90000), t, status="SUCCESS", device=d,
            remarks="refund", inject="TAKEOVER")

# chronological order, explicit ids
txns.sort(key=lambda x: x["time"])
# recompute daily limits in chronological order (injections were added later)
daily.clear()
for t in txns:
    key = (vpa_account[t["payer"]], t["time"].date())
    if t["status"] == "SUCCESS":
        if daily.get(key, 0) + t["amount"] > 100000:
            t["status"], t["reason"] = "FAILED", "Daily UPI limit of Rs. 1,00,000 exceeded for this account"
            t["inject"] = None
        else:
            daily[key] = daily.get(key, 0) + t["amount"]
for i, t in enumerate(txns):
    t["id"] = 900000001 + i
    if t["status"] != "FAILED":
        t["reason"] = None

injected_ids = [t["id"] for t in txns if t["inject"]]
txn_rows = [[t["id"], t["payer"], t["payee"], t["amount"], t["status"], t["device"], t["remarks"], t["reason"], t["time"]]
            for t in txns]

# ---------------------------------------------------------------- disputes
succ = [t for t in txns if t["status"] == "SUCCESS" and t["time"] < datetime(2026, 10, 23)]
disputes = []
chosen = random.sample([t for t in succ if not t["inject"]], 38) + \
    [t for t in succ if t["inject"] in ("HIGH_VALUE", "TAKEOVER", "NEW_DEVICE")][:9]
for t in chosen:
    raised = t["time"] + timedelta(hours=random.randint(1, 48))
    if raised > NOW:
        raised = NOW - timedelta(hours=1)
    if t["inject"]:
        reason = "UNAUTHORIZED"
    elif t["payee"] in merchant_by_vpa:
        reason = random.choice(["NOT_RECEIVED", "MERCHANT_ISSUE", "DUPLICATE", "WRONG_AMOUNT"])
    else:
        reason = random.choice(["NOT_RECEIVED", "WRONG_AMOUNT"])
    age_days = (NOW - raised).days
    if age_days > 10:
        status = random.choice(["RESOLVED", "RESOLVED", "REJECTED"])
        resolved = raised + timedelta(days=random.randint(1, 7))
    elif age_days > 3:
        status, resolved = random.choice(["UNDER_REVIEW", "RESOLVED"]), None
        if status == "RESOLVED":
            resolved = raised + timedelta(days=random.randint(1, 3))
    else:
        status, resolved = "OPEN", None
    desc = {"NOT_RECEIVED": "Amount debited but payee says not received",
            "WRONG_AMOUNT": "Entered wrong amount by mistake",
            "UNAUTHORIZED": "I did not make this transaction",
            "DUPLICATE": "Charged twice for the same order",
            "MERCHANT_ISSUE": "Order cancelled, refund not given"}[reason]
    disputes.append([t["id"], vpa_owner[t["payer"]], reason, desc, status, raised, resolved])
    if reason in ("NOT_RECEIVED", "MERCHANT_ISSUE") and status == "REJECTED":
        r2 = resolved + timedelta(days=1)
        disputes.append([t["id"], vpa_owner[t["payer"]], "MERCHANT_ISSUE", "Re-opened: still no refund",
                         "UNDER_REVIEW", r2, None])

# ---------------------------------------------------------------- saved payees
NICKS = ["Mom", "Dad", "Bro", "Sis", "Roomie", "Landlord", "Office", "Gym buddy", "College"]
saved = set()
saved_rows = []
first_name = {c[0]: c[1].split()[0] for c in customers}
for cid in active_personal:
    for f in random.sample(contacts[cid], random.randint(2, 4)):
        key = (cid, personal_vpa[f])
        if key not in saved:
            saved.add(key)
            nick = random.choice(NICKS) if random.random() < 0.25 else first_name[f]
            saved_rows.append([cid, personal_vpa[f], nick, date(2026, 8, 1) + timedelta(days=random.randint(0, 50))])
    if random.random() < 0.3:
        m = random.choice(merchants)
        if (cid, m[2]) not in saved:
            saved.add((cid, m[2]))
            saved_rows.append([cid, m[2], m[1][:50], date(2026, 8, 1) + timedelta(days=random.randint(0, 50))])
# some people already saved the brand-new accounts (shows cascade on delete)
for aid, v in new_unused_accounts:
    for cid in random.sample(active_personal, 2):
        if vpa_owner[v] != cid and (cid, v) not in saved:
            saved.add((cid, v))
            saved_rows.append([cid, v, "New account", date(2026, 10, 23)])

# ---------------------------------------------------------------- write SQL
L = []
L.append("-- =====================================================================")
L.append("--  UPIShield - File 04 : Seed data  (generated by data/generate_data.py)")
L.append("--  Guideline: Point 5(b) - populate tables (rows in the thousands)")
L.append("--  Run AFTER files 01-03: the triggers are active while this loads, and")
L.append("--  the data respects every rule, so nothing is rejected.  Fraud alerts")
L.append("--  are generated automatically by trg_txn_ai during the load.")
L.append("-- =====================================================================")
L.append("USE upishield;")
L.append("SET autocommit = 0;")
L.append("")
L.append(insert_block("bank", ["bank_code", "bank_name", "bank_type", "hq_city", "established_year"], BANKS))
L.append(insert_block("branch", ["ifsc", "bank_code", "branch_name", "city", "state"], branches))
# customers: insert without referrals first (FK to later rows), then set referrals
L.append(insert_block("customer", ["customer_id", "full_name", "phone", "email", "dob", "city", "kyc_status", "created_at"],
                      [[c[0], c[1], c[2], c[3], c[4], c[5], c[6], c[8]] for c in customers]))
for c in customers:
    if c[7]:
        L.append(f"UPDATE customer SET referred_by = {c[7]} WHERE customer_id = {c[0]};")
L.append("""INSERT INTO bank_account (account_id, customer_id, ifsc, account_no_enc, account_no_last4, account_type, balance, status, opened_on) VALUES""")
L.append(",\n".join(
    f"  ({a[0]}, {a[1]}, {q(a[2])}, AES_ENCRYPT({q(a[3])}, fn_enc_key()), {q(a[3][-4:])}, {q(a[4])}, {a[5]}, {q(a[6])}, {q(a[7])})"
    for a in accounts) + ";")
L.append(insert_block("savings_account", ["account_id", "interest_rate", "min_balance"], savings))
L.append(insert_block("current_account", ["account_id", "business_name", "gstin"], currents))
L.append(insert_block("vpa", ["vpa_id", "account_id", "is_primary", "created_on"], vpas))
L.append(insert_block("merchant_category", ["mcc", "description", "risk_level"], MCC))
L.append(insert_block("merchant", ["merchant_id", "merchant_name", "vpa_id", "mcc", "city", "merchant_type", "onboarded_on"], merchants))
L.append(insert_block("small_merchant", ["merchant_id", "daily_collection_limit", "static_qr"], small_m))
L.append(insert_block("enterprise_merchant", ["merchant_id", "mdr_rate", "settlement_cycle", "gst_registered"], ent_m))
L.append(insert_block("device", ["device_id", "model", "os", "os_version", "first_seen"], devices))
logins_u = {(l[0], l[1], l[2]): l for l in logins}
L.append(insert_block("device_login", ["customer_id", "device_id", "login_time", "ip_address"], list(logins_u.values())))
L.append(insert_block("fraud_rule", ["rule_id", "rule_code", "rule_name", "description", "threshold_count",
                                     "window_minutes", "threshold_amount", "severity", "is_active"], [
    [1, "VELOCITY", "Payment velocity", "5 or more successful payments from one VPA within 10 minutes", 5, 10, None, "HIGH", True],
    [2, "HIGH_VALUE_NEW_PAYEE", "High value to new payee", "Rs. 50,000+ sent to a VPA the payer has never paid before", None, None, 50000, "CRITICAL", True],
    [3, "NIGHT_HIGH_VALUE", "Night-time high value", "Rs. 20,000+ paid between 00:00 and 05:00", None, None, 20000, "MEDIUM", True],
    [4, "NEW_DEVICE", "New device high value", "Rs. 10,000+ paid from a device first seen in the last 24 hours", None, None, 10000, "HIGH", True],
    [5, "HIGH_RISK_MERCHANT", "High-risk merchant category", "Rs. 25,000+ paid to a merchant in a HIGH risk category", None, None, 25000, "HIGH", True],
    [6, "ROUND_AMOUNT", "Repeated round amounts", "Several exact round-figure transfers in a day (rule disabled - under review)", 3, 1440, 10000, "LOW", False],
]))
L.append("COMMIT;")
L.append("")
L.append("-- Transactions (chronological). Triggers derive txn_type and raise fraud alerts.")
L.append(insert_block("upi_txn", ["txn_id", "payer_vpa", "payee_vpa", "amount", "status", "device_id", "remarks",
                                  "failure_reason", "txn_time"], txn_rows, chunk=250))
L.append("COMMIT;")
L.append("")
L.append("-- Analyst decisions on the alerts (audit trigger records each change)")
L.append(f"UPDATE fraud_alert SET status = 'CONFIRMED_FRAUD', analyst_note = 'Customer confirmed the payment was not made by them' "
         f"WHERE txn_id IN ({', '.join(str(i) for i in injected_ids)}) AND alert_time < '2026-10-18';")
L.append(f"UPDATE fraud_alert SET status = 'INVESTIGATING', analyst_note = 'Customer contacted, awaiting response' "
         f"WHERE txn_id IN ({', '.join(str(i) for i in injected_ids)}) AND alert_time >= '2026-10-18';")
L.append("UPDATE fraud_alert SET status = 'FALSE_POSITIVE', analyst_note = 'Verified with customer - genuine payment' "
         "WHERE status = 'OPEN' AND alert_time < '2026-10-16' AND MOD(alert_id, 10) < 8;")
L.append("UPDATE fraud_alert SET status = 'INVESTIGATING' WHERE status = 'OPEN' AND alert_time < '2026-10-16';")
L.append("COMMIT;")
L.append("")
L.append(insert_block("dispute", ["txn_id", "raised_by", "reason", "description", "status", "raised_on", "resolved_on"], disputes))
L.append(insert_block("saved_payee", ["customer_id", "payee_vpa", "nickname", "added_on"], saved_rows))
L.append("COMMIT;")
L.append("")
L.append("-- Settle merchants day by day up to 22 Oct (23 Oct is left for the live demo)")
d = START.date()
while d <= date(2026, 10, 22):
    L.append(f"CALL sp_settle_merchants('{d.isoformat()}', @settled, @skipped);")
    d += timedelta(days=1)
L.append("SET autocommit = 1;")
L.append("")
L.append("""SELECT 'customer' AS table_name, COUNT(*) AS rows_loaded FROM customer
UNION ALL SELECT 'bank_account', COUNT(*) FROM bank_account
UNION ALL SELECT 'vpa', COUNT(*) FROM vpa
UNION ALL SELECT 'merchant', COUNT(*) FROM merchant
UNION ALL SELECT 'device', COUNT(*) FROM device
UNION ALL SELECT 'device_login', COUNT(*) FROM device_login
UNION ALL SELECT 'upi_txn', COUNT(*) FROM upi_txn
UNION ALL SELECT 'fraud_alert', COUNT(*) FROM fraud_alert
UNION ALL SELECT 'dispute', COUNT(*) FROM dispute
UNION ALL SELECT 'saved_payee', COUNT(*) FROM saved_payee
UNION ALL SELECT 'settlement', COUNT(*) FROM settlement
UNION ALL SELECT 'audit_log', COUNT(*) FROM audit_log;""")

with open(OUT_SQL, "w", encoding="utf-8") as f:
    f.write("\n".join(L) + "\n")

# ---------------------------------------------------------------- PaySim-format CSV
# Same columns as the public PaySim dataset (Kaggle), one month of hourly steps.
with open(OUT_CSV, "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["step", "type", "amount", "nameOrig", "oldbalanceOrg", "newbalanceOrig",
                "nameDest", "oldbalanceDest", "newbalanceDest", "isFraud", "isFlaggedFraud"])
    for _ in range(600):
        step = random.randint(1, 740)
        typ = random.choices(["PAYMENT", "TRANSFER", "CASH_OUT", "CASH_IN", "DEBIT"], [40, 20, 22, 15, 3])[0]
        amt = round(random.lognormvariate(9.2, 1.1), 2) if typ != "PAYMENT" else round(random.lognormvariate(8.6, 0.9), 2)
        orig = f"C{random.randint(100000000, 1999999999)}"
        old_o = round(random.uniform(0, 500000), 2)
        new_o = round(max(old_o - amt, 0), 2)
        dest = (f"M{random.randint(100000000, 1999999999)}" if typ == "PAYMENT"
                else f"C{random.randint(100000000, 1999999999)}")
        old_d = 0.0 if dest.startswith("M") else round(random.uniform(0, 800000), 2)
        new_d = 0.0 if dest.startswith("M") else round(old_d + amt, 2)
        fraud = 1 if typ in ("TRANSFER", "CASH_OUT") and random.random() < 0.04 else 0
        w.writerow([step, typ, amt, orig, old_o, new_o, dest, old_d, new_d, fraud, 0])

print("customers", len(customers), "accounts", len(accounts), "vpas", len(vpas), "merchants", len(merchants))
print("devices", len(devices), "logins", len(logins_u), "txns", len(txns), "injected", len(injected_ids))
print("disputes", len(disputes), "saved payees", len(saved_rows))
print("new unused accounts", new_unused_accounts[:3])
