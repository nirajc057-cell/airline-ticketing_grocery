const express = require("express");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const app = express();
const PORT = Number(process.env.PORT || 4782);
const dataDir = path.join(__dirname, "data");
const dataFile = path.join(dataDir, "store.json");
const sessions = new Map();
const now = () => new Date().toISOString();
const id = p => `${p}-${crypto.randomBytes(4).toString("hex").toUpperCase()}`;
const hash = value => crypto.createHash("sha256").update(value).digest("hex");

function seed() {
  return {
    settings: { agencyName: "Himalaya Travel Partners", currency: "USD", locale: "en-US", ticketApproval: true, platformComplete: false },
    users: [
      { id: "USR-001", name: "Nischal Chaudhary", email: "owner@aerodesk.local", passwordHash: hash("AeroDesk2026!"), role: "Agency owner", branch: "Kathmandu HQ", active: true },
      { id: "USR-002", name: "Maya Shrestha", email: "ticketing@aerodesk.local", passwordHash: hash("Ticketing2026!"), role: "Ticketing officer", branch: "Kathmandu HQ", active: true },
      { id: "USR-003", name: "Arun Rai", email: "accounts@aerodesk.local", passwordHash: hash("Accounts2026!"), role: "Accountant", branch: "Kathmandu HQ", active: true }
    ],
    customers: [
      { id: "CUS-1001", name: "Anika Sharma", email: "anika@example.com", phone: "+977 9800000001", nationality: "Nepal", passport: "PA******12", balance: 0, trips: 3, createdAt: now() },
      { id: "CUS-1002", name: "David Miller", email: "david@example.com", phone: "+1 415 555 0198", nationality: "United States", passport: "US******47", balance: 125, trips: 1, createdAt: now() }
    ],
    bookings: [
      { id: "BK-240701", pnr: "K8Q2LM", customerId: "CUS-1001", customerName: "Anika Sharma", route: "KTM → DXB", airline: "EK", flight: "EK 2154", travelDate: "2026-08-12", status: "Ticketed", total: 612.40, cost: 577.40, paymentStatus: "Paid", ticket: "176-2407010012", createdAt: "2026-07-26T08:30:00.000Z" },
      { id: "BK-240702", pnr: "Q7H9NP", customerId: "CUS-1002", customerName: "David Miller", route: "KTM → DEL", airline: "AI", flight: "AI 216", travelDate: "2026-08-03", status: "On hold", total: 238.00, cost: 218.00, paymentStatus: "Pending", deadline: "2026-07-29T12:00:00.000Z", createdAt: "2026-07-27T10:12:00.000Z" }
    ],
    quotes: [],
    refunds: [{ id: "RF-0018", bookingId: "BK-240615", customerName: "Priya Thapa", amount: 442.00, penalty: 85, status: "Under review", reason: "Passenger request", createdAt: "2026-07-25T07:00:00.000Z" }],
    cases: [{ id: "CS-0091", category: "Schedule change", subject: "EK 2154 departure moved by 55 minutes", bookingId: "BK-240701", priority: "High", status: "Open", assignee: "Maya Shrestha", createdAt: "2026-07-28T03:15:00.000Z" }],
    markups: [
      { id: "MR-01", name: "Default international", scope: "All suppliers", type: "Fixed", value: 25, active: true },
      { id: "MR-02", name: "Business cabin", scope: "Business / First", type: "Percent", value: 3.5, active: true }
    ],
    ledger: [
      { id: "LE-001", date: "2026-07-26", type: "Ticket sale", reference: "BK-240701", debit: 612.40, credit: 0, account: "Customer receivable" },
      { id: "LE-002", date: "2026-07-26", type: "Supplier payable", reference: "BK-240701", debit: 0, credit: 577.40, account: "Supplier payable" },
      { id: "LE-003", date: "2026-07-26", type: "Agency revenue", reference: "BK-240701", debit: 0, credit: 35, account: "Service revenue" }
    ],
    wallet: { balance: 24860.75, creditLimit: 10000, usedCredit: 238, currency: "USD" },
    walletTransactions: [{ id: "WT-01", date: "2026-07-26", type: "Ticket issuance", reference: "BK-240701", amount: -577.40 }],
    notifications: [
      { id: "N-01", title: "Ticketing deadline", message: "Booking Q7H9NP must be ticketed before 29 Jul, 12:00.", read: false, createdAt: now() },
      { id: "N-02", title: "Schedule change", message: "EK 2154 departure time changed. Review customer options.", read: false, createdAt: now() }
    ],
    audit: [{ id: "AU-001", action: "SYSTEM_INITIALIZED", user: "System", entity: "Platform", detail: "Local agency workspace created", createdAt: now() }]
  };
}
function grocerySeed(){
  return {
    settings:{storeName:"FreshMart Grocery",currency:"USD",taxRate:5},
    products:[
      {id:"PRD-001",barcode:"890100100001",name:"Basmati Rice 5 kg",category:"Rice & grains",cost:12.5,price:15.99,stock:28,reorder:10,unit:"bag",expiry:"2027-03-12"},
      {id:"PRD-002",barcode:"890100100002",name:"Fresh Whole Milk 1 L",category:"Dairy",cost:1.12,price:1.65,stock:14,reorder:12,unit:"bottle",expiry:"2026-08-03"},
      {id:"PRD-003",barcode:"890100100003",name:"Sunflower Oil 1 L",category:"Cooking oil",cost:2.4,price:3.25,stock:8,reorder:10,unit:"bottle",expiry:"2027-01-20"},
      {id:"PRD-004",barcode:"890100100004",name:"Brown Bread 500 g",category:"Bakery",cost:1.05,price:1.6,stock:9,reorder:8,unit:"loaf",expiry:"2026-07-31"},
      {id:"PRD-005",barcode:"890100100005",name:"Farm Eggs 12 pack",category:"Dairy",cost:2.1,price:2.95,stock:22,reorder:8,unit:"tray",expiry:"2026-08-14"},
      {id:"PRD-006",barcode:"890100100006",name:"Laundry Detergent 1 kg",category:"Household cleaning",cost:3.2,price:4.75,stock:17,reorder:6,unit:"pack",expiry:"2028-04-01"},
      {id:"PRD-007",barcode:"890100100007",name:"Red Apples",category:"Fruits",cost:1.5,price:2.35,stock:36,reorder:12,unit:"kg",expiry:"2026-08-05"},
      {id:"PRD-008",barcode:"890100100008",name:"Mineral Water 1 L",category:"Beverages",cost:.35,price:.65,stock:54,reorder:20,unit:"bottle",expiry:"2027-06-01"}
    ],
    sales:[], suppliers:[
      {id:"SUP-01",name:"Everest Foods Distribution",contact:"Ram Karki",phone:"+977 9801002003",balance:2450,rating:4.8},
      {id:"SUP-02",name:"Valley Dairy Cooperative",contact:"Sita Lama",phone:"+977 9811002200",balance:820,rating:4.6}
    ],
    purchases:[{id:"PO-1008",supplier:"Everest Foods Distribution",date:"2026-07-26",total:1240,status:"Received"}],
    customers:[{id:"GC-101",name:"Asha Rai",phone:"+977 9802221010",points:240,spent:815.2}],
    expenses:[{id:"EX-01",date:"2026-07-27",category:"Utilities",description:"Electricity",amount:185}],
    audit:[{id:"GA-001",action:"GROCERY_PLATFORM_CREATED",detail:"Local grocery workspace initialized",createdAt:now()}]
  }
}
function load() {
  fs.mkdirSync(dataDir, { recursive: true });
  if (!fs.existsSync(dataFile)) fs.writeFileSync(dataFile, JSON.stringify(seed(), null, 2));
  return JSON.parse(fs.readFileSync(dataFile, "utf8"));
}
let db = load();
if(!db.grocery){db.grocery=grocerySeed();save()}
function save() { fs.writeFileSync(dataFile, JSON.stringify(db, null, 2)); }
function audit(req, action, entity, detail) {
  db.audit.unshift({ id: id("AU"), action, user: req.user?.name || "System", entity, detail, createdAt: now() });
  db.audit = db.audit.slice(0, 5000);
}
function auth(req, res, next) {
  const token = (req.headers.authorization || "").replace("Bearer ", "");
  const userId = sessions.get(token);
  const user = db.users.find(x => x.id === userId && x.active);
  if (!user) return res.status(401).json({ error: "Please sign in." });
  req.user = user; next();
}
app.use(express.json({ limit: "1mb" }));
app.use(express.static(path.join(__dirname, "public")));

app.get("/health", (_req, res) => {
  res.status(200).json({ status: "ok" });
});

app.post("/api/login", (req, res) => {
  const user = db.users.find(x => x.email.toLowerCase() === String(req.body.email || "").toLowerCase() && x.passwordHash === hash(String(req.body.password || "")) && x.active);
  if (!user) return res.status(401).json({ error: "Email or password is incorrect." });
  const token = crypto.randomBytes(24).toString("hex"); sessions.set(token, user.id);
  audit({ user }, "SIGNED_IN", "User", user.email); save();
  res.json({ token, user: { id: user.id, name: user.name, email: user.email, role: user.role, branch: user.branch } });
});
app.post("/api/logout", auth, (req, res) => { const token = req.headers.authorization.replace("Bearer ", ""); sessions.delete(token); res.json({ ok: true }); });
app.get("/api/bootstrap", auth, (req, res) => {
  const revenue = db.bookings.filter(x => x.status === "Ticketed").reduce((s,x) => s + (x.total-x.cost), 0);
  res.json({ user: req.user, settings: db.settings, wallet: db.wallet, stats: {
    sales: db.bookings.reduce((s,x)=>s+x.total,0), bookings: db.bookings.length, ticketed: db.bookings.filter(x=>x.status==="Ticketed").length,
    revenue, refunds: db.refunds.filter(x=>!["Paid to customer","Rejected"].includes(x.status)).length, cases: db.cases.filter(x=>x.status!=="Resolved").length
  }, notifications: db.notifications.slice(0,8) });
});
app.patch("/api/platform-status", auth, (req,res)=>{
  db.settings.platformComplete=Boolean(req.body.complete);
  audit(req,"PLATFORM_STATUS_CHANGED","Platform",db.settings.platformComplete?"Complete platform":"New platform");save();
  res.json({complete:db.settings.platformComplete,label:db.settings.platformComplete?"Complete platform":"New platform"});
});
app.get("/api/grocery/bootstrap",auth,(req,res)=>{
  const g=db.grocery,today=now().slice(0,10),todaySales=g.sales.filter(s=>s.createdAt.slice(0,10)===today),revenue=todaySales.reduce((a,s)=>a+s.total,0),profit=todaySales.reduce((a,s)=>a+s.profit,0);
  res.json({settings:g.settings,stats:{sales:revenue,transactions:todaySales.length,profit,inventoryValue:g.products.reduce((a,p)=>a+p.cost*p.stock,0),lowStock:g.products.filter(p=>p.stock<=p.reorder).length,expenses:g.expenses.reduce((a,e)=>a+e.amount,0)},products:g.products});
});
app.get("/api/grocery/:collection(products|sales|suppliers|purchases|customers|expenses|audit)",auth,(req,res)=>res.json(db.grocery[req.params.collection]));
app.post("/api/grocery/products",auth,(req,res)=>{const p={id:id("PRD"),barcode:req.body.barcode,name:req.body.name,category:req.body.category,cost:Number(req.body.cost),price:Number(req.body.price),stock:Number(req.body.stock),reorder:Number(req.body.reorder||5),unit:req.body.unit||"piece",expiry:req.body.expiry||""};db.grocery.products.unshift(p);db.grocery.audit.unshift({id:id("GA"),action:"PRODUCT_CREATED",detail:p.name,createdAt:now()});save();res.status(201).json(p)});
app.patch("/api/grocery/products/:productId",auth,(req,res)=>{const p=db.grocery.products.find(x=>x.id===req.params.productId);if(!p)return res.status(404).json({error:"Product not found."});for(const k of ["name","barcode","category","unit","expiry"])if(req.body[k]!==undefined)p[k]=req.body[k];for(const k of ["cost","price","stock","reorder"])if(req.body[k]!==undefined)p[k]=Number(req.body[k]);db.grocery.audit.unshift({id:id("GA"),action:"PRODUCT_UPDATED",detail:p.name,createdAt:now()});save();res.json(p)});
app.post("/api/grocery/sales",auth,(req,res)=>{const items=req.body.items||[];if(!items.length)return res.status(400).json({error:"Cart is empty."});let subtotal=0,cost=0;for(const item of items){const p=db.grocery.products.find(x=>x.id===item.id);const qty=Number(item.qty);if(!p||qty<=0||p.stock<qty)return res.status(409).json({error:`Insufficient stock for ${p?.name||"product"}.`});subtotal+=p.price*qty;cost+=p.cost*qty}const discount=Number(req.body.discount||0),tax=Math.max(0,(subtotal-discount)*db.grocery.settings.taxRate/100),total=subtotal-discount+tax;for(const item of items)db.grocery.products.find(x=>x.id===item.id).stock-=Number(item.qty);const sale={id:id("SALE"),receipt:`FM-${String(Date.now()).slice(-8)}`,items,subtotal,discount,tax,total,profit:subtotal-discount-cost,payment:req.body.payment||"Cash",customer:req.body.customer||"Walk-in",cashier:req.user.name,createdAt:now()};db.grocery.sales.unshift(sale);db.grocery.audit.unshift({id:id("GA"),action:"SALE_COMPLETED",detail:`${sale.receipt} • ${total.toFixed(2)}`,createdAt:now()});save();res.status(201).json(sale)});
app.post("/api/grocery/expenses",auth,(req,res)=>{const e={id:id("EX"),date:req.body.date||now().slice(0,10),category:req.body.category,description:req.body.description,amount:Number(req.body.amount)};db.grocery.expenses.unshift(e);db.grocery.audit.unshift({id:id("GA"),action:"EXPENSE_RECORDED",detail:`${e.category} • ${e.amount}`,createdAt:now()});save();res.status(201).json(e)});
app.post("/api/grocery/purchases",auth,(req,res)=>{const p={id:id("PO"),supplier:req.body.supplier,date:req.body.date||now().slice(0,10),total:Number(req.body.total),status:req.body.status||"Ordered"};db.grocery.purchases.unshift(p);db.grocery.audit.unshift({id:id("GA"),action:"PURCHASE_CREATED",detail:p.id,createdAt:now()});save();res.status(201).json(p)});

const airports = { KTM:"Kathmandu", DXB:"Dubai", DEL:"Delhi", DOH:"Doha", SIN:"Singapore", BKK:"Bangkok", LHR:"London", JFK:"New York", HKG:"Hong Kong", SYD:"Sydney", NRT:"Tokyo", CDG:"Paris" };
const carriers = [
  ["QR","Qatar Airways","DOH"],["EK","Emirates","DXB"],["AI","Air India","DEL"],["SQ","Singapore Airlines","SIN"],["TG","Thai Airways","BKK"],["CX","Cathay Pacific","HKG"]
];
function offers(q) {
  const origin = String(q.origin || "KTM").toUpperCase(), destination = String(q.destination || "DXB").toUpperCase();
  const cabinFactor = q.cabin === "Business" ? 2.8 : q.cabin === "First" ? 5.2 : q.cabin === "Premium economy" ? 1.45 : 1;
  const pax = Math.max(1, Number(q.adults || 1) + Number(q.children || 0));
  const baseSeed = [...origin+destination].reduce((s,c)=>s+c.charCodeAt(0),0);
  return carriers.slice(0,5).map((c,i) => {
    const base = Math.round((145 + (baseSeed % 180) + i * 37) * cabinFactor * pax);
    const taxes = Math.round(base*.22), supplierFee = 6+i, markup = 25, total = base+taxes+supplierFee+markup;
    const stop = c[2] === origin || c[2] === destination || i === 2 ? 0 : 1;
    return { id:`OFF-${Date.now()}-${i}`, airline:c[1], carrier:c[0], flight:`${c[0]} ${210+i*37}`, origin, destination, originName:airports[origin]||origin, destinationName:airports[destination]||destination,
      departure:q.departure, departTime:`${String(7+i*2).padStart(2,"0")}:${i%2?"35":"10"}`, arriveTime:`${String(11+i*2).padStart(2,"0")}:${i%2?"20":"55"}`,
      duration:`${4+i}h ${15+i*7}m`, stops:stop, cabin:q.cabin||"Economy", brand:i%2?"Flex":"Value", baggage:i%2?"30 kg":"25 kg", refundable:i%2===1,
      seats:3+i, base, taxes, supplierFee, markup, total, currency:q.currency||"USD", source:i%2?"NDC Sandbox":"GDS Sandbox", expiresAt:new Date(Date.now()+15*60000).toISOString() };
  });
}
app.post("/api/search", auth, (req,res) => { const result=offers(req.body); audit(req,"FLIGHT_SEARCH","Search",`${req.body.origin}–${req.body.destination}`); save(); res.json(result); });
app.post("/api/quotes", auth, (req,res) => {
  const quote={ id:id("QT"), ...req.body, status:"Sent", validUntil:new Date(Date.now()+24*3600000).toISOString(), createdAt:now() };
  db.quotes.unshift(quote); audit(req,"QUOTE_CREATED","Quote",quote.id); save(); res.status(201).json(quote);
});
app.get("/api/:collection(bookings|customers|quotes|refunds|cases|markups|ledger|walletTransactions|users|audit|notifications)", auth, (req,res)=>res.json(db[req.params.collection]));
app.post("/api/customers", auth, (req,res)=>{
  const customer={ id:id("CUS"), name:req.body.name, email:req.body.email, phone:req.body.phone||"", nationality:req.body.nationality||"", passport:req.body.passport||"", balance:0,trips:0,createdAt:now() };
  db.customers.unshift(customer); audit(req,"CUSTOMER_CREATED","Customer",customer.id); save(); res.status(201).json(customer);
});
app.post("/api/bookings", auth, (req,res)=>{
  const offer=req.body.offer, customer=req.body.customer;
  if (!offer || !customer?.name) return res.status(400).json({error:"Offer and passenger are required."});
  if (db.wallet.balance + (db.wallet.creditLimit-db.wallet.usedCredit) < offer.total) return res.status(409).json({error:"Insufficient wallet and credit."});
  const booking={ id:id("BK"), pnr:crypto.randomBytes(3).toString("hex").toUpperCase(), customerId:customer.id||null, customerName:customer.name, route:`${offer.origin} → ${offer.destination}`,
    airline:offer.carrier, flight:offer.flight, travelDate:offer.departure, status:"On hold", total:offer.total, cost:offer.total-offer.markup, paymentStatus:"Pending",
    deadline:new Date(Date.now()+24*3600000).toISOString(), passengers:req.body.passengers||[customer], offer, createdAt:now() };
  db.bookings.unshift(booking); audit(req,"RESERVATION_CREATED","Booking",`${booking.id} / ${booking.pnr}`); save(); res.status(201).json(booking);
});
app.post("/api/bookings/:bookingId/pay", auth, (req,res)=>{
  const b=db.bookings.find(x=>x.id===req.params.bookingId); if(!b)return res.status(404).json({error:"Booking not found."});
  b.paymentStatus="Paid"; b.paymentMethod=req.body.method||"Agency wallet"; audit(req,"PAYMENT_RECORDED","Booking",b.id); save(); res.json(b);
});
app.post("/api/bookings/:bookingId/ticket", auth, (req,res)=>{
  const b=db.bookings.find(x=>x.id===req.params.bookingId); if(!b)return res.status(404).json({error:"Booking not found."});
  if(b.status==="Ticketed")return res.json(b); if(b.paymentStatus!=="Paid")return res.status(409).json({error:"Record payment before ticketing."});
  if(db.wallet.balance < b.cost)return res.status(409).json({error:"Wallet balance is insufficient."});
  b.status="Ticketed"; b.ticket=`176-${String(Date.now()).slice(-10)}`; b.issuedAt=now(); db.wallet.balance-=b.cost;
  db.walletTransactions.unshift({id:id("WT"),date:now().slice(0,10),type:"Ticket issuance",reference:b.id,amount:-b.cost});
  db.ledger.unshift({id:id("LE"),date:now().slice(0,10),type:"Ticket sale",reference:b.id,debit:b.total,credit:0,account:"Customer receivable"},{id:id("LE"),date:now().slice(0,10),type:"Supplier payable",reference:b.id,debit:0,credit:b.cost,account:"Supplier payable"});
  audit(req,"TICKET_ISSUED","Ticket",`${b.ticket} for ${b.id}`); save(); res.json(b);
});
app.post("/api/refunds", auth, (req,res)=>{
  const b=db.bookings.find(x=>x.id===req.body.bookingId); if(!b)return res.status(404).json({error:"Booking not found."});
  const r={id:id("RF"),bookingId:b.id,customerName:b.customerName,amount:Number(req.body.amount||b.total),penalty:Number(req.body.penalty||0),status:"Requested",reason:req.body.reason||"Passenger request",createdAt:now()};
  db.refunds.unshift(r); b.status="Refund requested"; audit(req,"REFUND_REQUESTED","Refund",r.id); save(); res.status(201).json(r);
});
app.patch("/api/refunds/:refundId", auth, (req,res)=>{
  const r=db.refunds.find(x=>x.id===req.params.refundId);if(!r)return res.status(404).json({error:"Refund not found."}); r.status=req.body.status||r.status; audit(req,"REFUND_UPDATED","Refund",`${r.id}: ${r.status}`);save();res.json(r);
});
app.post("/api/cases", auth, (req,res)=>{
  const c={id:id("CS"),category:req.body.category||"General",subject:req.body.subject,bookingId:req.body.bookingId||"",priority:req.body.priority||"Medium",status:"Open",assignee:req.body.assignee||req.user.name,createdAt:now()};
  db.cases.unshift(c);audit(req,"CASE_CREATED","Support case",c.id);save();res.status(201).json(c);
});
app.patch("/api/cases/:caseId", auth, (req,res)=>{const c=db.cases.find(x=>x.id===req.params.caseId);if(!c)return res.status(404).json({error:"Case not found."});Object.assign(c,req.body);audit(req,"CASE_UPDATED","Support case",c.id);save();res.json(c);});
app.post("/api/markups", auth, (req,res)=>{const m={id:id("MR"),name:req.body.name,scope:req.body.scope||"All suppliers",type:req.body.type||"Fixed",value:Number(req.body.value),active:true};db.markups.unshift(m);audit(req,"MARKUP_CREATED","Pricing rule",m.id);save();res.status(201).json(m);});
app.patch("/api/wallet", auth, (req,res)=>{
  const balance=Number(req.body.balance), creditLimit=Number(req.body.creditLimit), usedCredit=Number(req.body.usedCredit);
  if (![balance,creditLimit,usedCredit].every(Number.isFinite) || balance<0 || creditLimit<0 || usedCredit<0 || usedCredit>creditLimit) return res.status(400).json({error:"Enter valid non-negative amounts. Used credit cannot exceed the credit limit."});
  const before={...db.wallet}; Object.assign(db.wallet,{balance,creditLimit,usedCredit});
  audit(req,"WALLET_SETTINGS_UPDATED","Wallet",`Balance ${before.balance} → ${balance}; credit limit ${before.creditLimit} → ${creditLimit}; used credit ${before.usedCredit} → ${usedCredit}`);save();res.json(db.wallet);
});
app.post("/api/wallet/adjustments", auth, (req,res)=>{
  const amount=Number(req.body.amount); if(!Number.isFinite(amount)||amount===0)return res.status(400).json({error:"Adjustment amount cannot be zero."});
  if(db.wallet.balance+amount<0)return res.status(409).json({error:"This adjustment would make the wallet balance negative."});
  db.wallet.balance+=amount; const w={id:id("WT"),date:now().slice(0,10),type:req.body.type||"Manual adjustment",reference:req.body.reference||"MANUAL",amount,note:req.body.note||""};
  db.walletTransactions.unshift(w); db.ledger.unshift({id:id("LE"),date:w.date,type:w.type,reference:w.reference,debit:amount>0?amount:0,credit:amount<0?Math.abs(amount):0,account:req.body.account||"Agency wallet",note:w.note});
  audit(req,"WALLET_ADJUSTED","Wallet",`${amount>0?"+":""}${amount}: ${w.note||w.reference}`);save();res.status(201).json({wallet:db.wallet,transaction:w});
});
app.post("/api/ledger", auth, (req,res)=>{
  const debit=Number(req.body.debit||0),credit=Number(req.body.credit||0); if(!Number.isFinite(debit)||!Number.isFinite(credit)||debit<0||credit<0||(debit===0&&credit===0))return res.status(400).json({error:"Enter a valid debit or credit amount."});
  const entry={id:id("LE"),date:req.body.date||now().slice(0,10),type:req.body.type||"Manual journal",reference:req.body.reference||"MANUAL",debit,credit,account:req.body.account||"General ledger",note:req.body.note||""};
  db.ledger.unshift(entry);audit(req,"LEDGER_ENTRY_CREATED","Ledger entry",`${entry.id}: ${entry.account}`);save();res.status(201).json(entry);
});
app.patch("/api/ledger/:entryId", auth, (req,res)=>{
  const entry=db.ledger.find(x=>x.id===req.params.entryId);if(!entry)return res.status(404).json({error:"Ledger entry not found."});
  const allowed=["date","type","reference","account","note","debit","credit"];for(const k of allowed)if(req.body[k]!==undefined)entry[k]=["debit","credit"].includes(k)?Number(req.body[k]):req.body[k];
  if(!Number.isFinite(entry.debit)||!Number.isFinite(entry.credit)||entry.debit<0||entry.credit<0||(entry.debit===0&&entry.credit===0))return res.status(400).json({error:"Enter a valid debit or credit amount."});
  audit(req,"LEDGER_ENTRY_UPDATED","Ledger entry",entry.id);save();res.json(entry);
});
app.post("/api/users", auth, (req,res)=>{if(req.user.role!=="Agency owner"&&req.user.role!=="Agency administrator")return res.status(403).json({error:"Administrator access required."});const u={id:id("USR"),name:req.body.name,email:req.body.email,passwordHash:hash(req.body.password||"ChangeMe2026!"),role:req.body.role||"Sales agent",branch:req.body.branch||"Kathmandu HQ",active:true};db.users.unshift(u);audit(req,"USER_CREATED","User",u.email);save();res.status(201).json({...u,passwordHash:undefined});});
app.get("/api/reports/sales",auth,(req,res)=>{
  const rows=db.bookings.map(b=>({date:b.createdAt.slice(0,10),reference:b.id,pnr:b.pnr,customer:b.customerName,route:b.route,status:b.status,sales:b.total,cost:b.cost,revenue:b.total-b.cost}));
  res.json({rows,totals:rows.reduce((a,x)=>({sales:a.sales+x.sales,cost:a.cost+x.cost,revenue:a.revenue+x.revenue}),{sales:0,cost:0,revenue:0})});
});
app.get("*",(req,res)=>res.sendFile(path.join(__dirname,"public","index.html")));
app.listen(PORT,()=>console.log(`AeroDesk Local running at http://localhost:${PORT}`));
module.exports=app;
