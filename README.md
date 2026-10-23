# Marg eOrder Flutter Data Layer Architecture Blueprint

A robust, enterprise-grade offline storage and synchronization data layer for Android field sales representatives, inspired by Marg ERP eOrder.

---

## 1. Domain Entities & Responsibilities

| Entity | Fields | Primary Role |
| :--- | :--- | :--- |
| **Party** | `id`, `storeName`, `balance`, `address`, `creditLimit`, `gstNumber` | Represents retail chemist / store. `balance` tracks ledger dues to prevent delinquent credit ordering. |
| **Product** | `id`, `name`, `stock`, `rate`, `schemeText`, `mrp`, `packSize` | SKU catalog. `schemeText` is parsed dynamically for Marg bonus rules (e.g. *10+1 FREE*, *5% Cash Disc*). |
| **Order** | `id`, `orderNumber`, `partyId`, `items`, `totalPrice`, `syncStatus` | Order aggregate. `syncStatus` is strictly either `'Pending'` or `'Synced'`. |
| **OrderItem** | `id`, `orderId`, `productId`, `quantity`, `freeQuantity`, `unitRate`, `totalAmount` | Relational line item link preventing JSON blobs in order rows. |

---

## 2. Why Sqflite Over Pure SharedPreferences?

Field sales distribution has strict relational and transactional requirements:
1. **ACID Transactions**: When an order is placed, line items are inserted AND inventory is decremented simultaneously. If power is lost mid-entry, Sqflite rolls back completely.
2. **Indexing & Query Performance**: A distributor catalog contains 5,000+ SKUs and hundreds of stores. Sqflite B-Trees with indexes on `sync_status` and `store_name` provide sub-millisecond lookups.
3. **Auditability**: Order line items and historical orders can be searched, sorted, and filtered without reading mega-JSON strings into RAM.

**Role of SharedPreferences:**
Reserved strictly for lightweight distributor configurations:
- `distributor_code`
- `salesman_code`
- `last_sync_timestamp`
- `offline_mode_forced`

---

## 3. Database Schema Overview

```sql
-- Parties Table
CREATE TABLE parties (
  id TEXT PRIMARY KEY,
  store_name TEXT NOT NULL,
  party_code TEXT NOT NULL,
  balance REAL NOT NULL,
  address TEXT NOT NULL,
  phone TEXT,
  credit_limit REAL DEFAULT 0.0,
  gst_number TEXT,
  route TEXT,
  updated_at TEXT NOT NULL
);

-- Products Table
CREATE TABLE products (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  item_code TEXT NOT NULL,
  stock INTEGER NOT NULL,
  rate REAL NOT NULL,
  mrp REAL DEFAULT 0.0,
  pack_size TEXT,
  scheme_text TEXT NOT NULL,
  category TEXT,
  updated_at TEXT NOT NULL
);

-- Orders Table
CREATE TABLE orders (
  id TEXT PRIMARY KEY,
  order_number TEXT NOT NULL UNIQUE,
  party_id TEXT NOT NULL,
  party_name TEXT NOT NULL,
  party_address TEXT NOT NULL,
  party_balance_snapshot REAL DEFAULT 0.0,
  total_quantity INTEGER NOT NULL,
  total_price REAL NOT NULL,
  sync_status TEXT NOT NULL CHECK(sync_status IN ('Pending', 'Synced')),
  created_at TEXT NOT NULL,
  synced_at TEXT,
  remarks TEXT,
  salesman_code TEXT,
  FOREIGN KEY (party_id) REFERENCES parties(id) ON DELETE RESTRICT
);

-- Order Items Table
CREATE TABLE order_items (
  id TEXT PRIMARY KEY,
  order_id TEXT NOT NULL,
  product_id TEXT NOT NULL,
  product_name TEXT NOT NULL,
  quantity INTEGER NOT NULL,
  free_quantity INTEGER NOT NULL DEFAULT 0,
  unit_rate REAL NOT NULL,
  discount_percent REAL NOT NULL DEFAULT 0.0,
  scheme_applied TEXT,
  total_amount REAL NOT NULL,
  FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE,
  FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE RESTRICT
);
```

---

## 4. Synchronization Lifecycle

```
[ Field Sales Rep Books Order ]
              │
              ▼
    [ Atomic Sqflite Txn ]
 ┌───────────────────────────────┐
 │ 1. Insert order (Pending)     │
 │ 2. Insert order_items         │
 │ 3. Decrement product stock    │
 └───────────────────────────────┘
              │
              ▼
[ Device Connects to Network ]
              │
              ▼
 [ SyncService.performFullSync ]
 ┌────────────────────────────────────────────────────────┐
 │ 1. Query: SELECT * FROM orders WHERE sync_status='Pending'
 │ 2. POST batch JSON to /api/v1/orders/batch-push        │
 │ 3. On 200 OK: UPDATE orders SET sync_status='Synced'  │
 │ 4. GET /api/v1/master-data (update stock & balances)   │
 │ 5. Write last_sync_timestamp into SharedPreferences    │
 └────────────────────────────────────────────────────────┘
```
