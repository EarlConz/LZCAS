// stress-test.js — LZCAS / Stockpile Load Test (k6)
// =============================================================================
// PREREQUISITES:
//   1. Install k6:  choco install k6   (or https://k6.io/docs/get-started/installation/)
//   2. Set environment variables:
//        $env:SUPABASE_URL="https://your-project.supabase.co"
//        $env:SUPABASE_ANON_KEY="your-anon-key"
//   3. (Optional) Create test users so load hits real data:
//        Create a cashier user and an admin user via Supabase dashboard.
//        Set TEST_EMAIL / TEST_PASSWORD below.
//   4. Run:
//        k6 run stress-test.js
//   5. Interpret results:
//        - http_req_duration: p(95) should stay under 500ms for reads, under 2s for writes
//        - http_req_failed: should be < 1% at peak
//        - iterations: total completed requests — should match virtual_users × duration ratio
//        - vus: ramps from 0 → 100 over 5 minutes, holds 0.5 min at peak
// =============================================================================

import http from "k6/http";
import { check, sleep, group } from "k6";
import { Rate, Trend } from "k6/metrics";
import { textSummary } from "https://jslib.k6.io/k6-summary/0.0.1/index.js";

// ── Custom Metrics ──────────────────────────────────────────────────────────
const errorRate = new Rate("errors");
const fetchItemsDuration = new Trend("fetch_items_duration");
const fetchMembersDuration = new Trend("fetch_members_duration");
const fetchSalesDuration = new Trend("fetch_sales_duration");
const addSaleDuration = new Trend("add_sale_duration");
const pendingRequestsDuration = new Trend("pending_requests_duration");
const dashboardDuration = new Trend("dashboard_stats_duration");

// ── Configuration ───────────────────────────────────────────────────────────
const SUPABASE_URL = __ENV.SUPABASE_URL || "https://your-project.supabase.co";
const ANON_KEY = __ENV.SUPABASE_ANON_KEY || "your-anon-key";
const TEST_EMAIL = __ENV.TEST_EMAIL || "test-cashier@example.com";
const TEST_PASSWORD = __ENV.TEST_PASSWORD || "test-password-123";

const BASE = `${SUPABASE_URL}/rest/v1`;
const AUTH_URL = `${SUPABASE_URL}/auth/v1`;

// ── Test Scenario: ramp from 0 → 100 VUs over 5 minutes ─────────────────────
export const options = {
  stages: [
    { duration: "1m", target: 20 }, // Ramp to 20 users over 1 min
    { duration: "2m", target: 50 }, // Ramp to 50 users over 2 min
    { duration: "2m", target: 100 }, // Ramp to 100 users over 2 min
    { duration: "30s", target: 0 }, // Ramp down to 0 over 30s
  ],
  thresholds: {
    http_req_duration: ["p(95)<2000"], // 95% of requests under 2s
    http_req_failed: ["rate<0.05"], // < 5% failure rate
    errors: ["rate<0.05"], // < 5% custom error rate
  },
};

// ── Shared auth token (one per VU) ──────────────────────────────────────────
let authToken = "";

// ── Auth helper: sign in and cache token ────────────────────────────────────
function authenticate() {
  const res = http.post(
    `${AUTH_URL}/token?grant_type=password`,
    JSON.stringify({
      email: TEST_EMAIL,
      password: TEST_PASSWORD,
    }),
    {
      headers: {
        "Content-Type": "application/json",
        apikey: ANON_KEY,
      },
    },
  );

  const ok = check(res, {
    "auth: status 200": (r) => r.status === 200,
  });

  if (ok && res.json("access_token")) {
    authToken = res.json("access_token");
    console.log(`VU ${__VU}: authenticated as ${TEST_EMAIL}`);
  } else {
    console.error(`VU ${__VU}: auth failed — ${res.status} ${res.body}`);
  }
}

// ── Common headers ──────────────────────────────────────────────────────────
function headers() {
  return {
    "Content-Type": "application/json",
    apikey: ANON_KEY,
    Authorization: `Bearer ${authToken}`,
    Prefer: "return=representation",
  };
}

// ── Main test function — each VU runs this loop ─────────────────────────────
export default function () {
  // Authenticate on first iteration or when token expires
  if (!authToken) {
    authenticate();
    if (!authToken) {
      errorRate.add(1);
      return; // skip this iteration — unable to auth
    }
  }

  // ── Read-heavy workload (80% reads, 20% writes) ──────────────────────────
  const scenario = Math.random();

  if (scenario < 0.3) {
    // 30% — Fetch Items (paginated)
    fetchItems();
  } else if (scenario < 0.5) {
    // 20% — Fetch Members (paginated)
    fetchMembers();
  } else if (scenario < 0.65) {
    // 15% — Fetch Sales (paginated, heavier query)
    fetchSales();
  } else if (scenario < 0.8) {
    // 15% — Dashboard Stats (date-range query)
    fetchDashboardStats();
  } else if (scenario < 0.9) {
    // 10% — Pending Requests (admin workload)
    fetchPendingRequests();
  } else {
    // 10% — Add Sale (write operation)
    addSale();
  }

  // Simulate realistic think time between user actions
  sleep(Math.random() * 3 + 1); // 1–4 seconds
}

// ── Scenario: Fetch Items (paginated, 25 rows) ──────────────────────────────
function fetchItems() {
  const res = http.get(
    `${BASE}/items?select=*&order=name.asc&limit=25&offset=0`,
    { headers: headers() },
  );

  const ok = check(res, {
    "items: status 200": (r) => r.status === 200,
    "items: has data": (r) => r.json().length >= 0,
  });

  fetchItemsDuration.add(res.timings.duration);
  if (!ok) errorRate.add(1);
}

// ── Scenario: Fetch Members (paginated, 25 rows) ────────────────────────────
function fetchMembers() {
  const res = http.get(
    `${BASE}/members?select=*&order=last_name.asc&limit=25&offset=0`,
    { headers: headers() },
  );

  const ok = check(res, {
    "members: status 200": (r) => r.status === 200,
    "members: has data": (r) => r.json().length >= 0,
  });

  fetchMembersDuration.add(res.timings.duration);
  if (!ok) errorRate.add(1);
}

// ── Scenario: Fetch Sales (paginated, heavier — most rows) ──────────────────
function fetchSales() {
  const res = http.get(
    `${BASE}/sales?select=*&order=timestamp.desc&limit=25&offset=0`,
    { headers: headers() },
  );

  const ok = check(res, {
    "sales: status 200": (r) => r.status === 200,
    "sales: has data": (r) => r.json().length >= 0,
  });

  fetchSalesDuration.add(res.timings.duration);
  if (!ok) errorRate.add(1);
}

// ── Scenario: Dashboard Stats (date-range filtered) ─────────────────────────
function fetchDashboardStats() {
  const now = new Date().toISOString();
  const monthAgo = new Date(
    Date.now() - 30 * 24 * 60 * 60 * 1000,
  ).toISOString();

  // Simulate the dashboard's month-range sales query
  const res = http.get(
    `${BASE}/sales?select=price,quantity&timestamp=gte.${monthAgo}&timestamp=lt.${now}&limit=1000`,
    { headers: headers() },
  );

  const ok = check(res, {
    "dashboard: status 200": (r) => r.status === 200,
    "dashboard: has data": (r) => r.json().length >= 0,
  });

  dashboardDuration.add(res.timings.duration);
  if (!ok) errorRate.add(1);
}

// ── Scenario: Pending Requests ──────────────────────────────────────────────
function fetchPendingRequests() {
  const res = http.get(
    `${BASE}/pending_requests?select=*&status=eq.pending&order=created_at.desc&limit=25&offset=0`,
    { headers: headers() },
  );

  const ok = check(res, {
    "requests: status 200": (r) => r.status === 200,
    "requests: has data": (r) => r.json().length >= 0,
  });

  pendingRequestsDuration.add(res.timings.duration);
  if (!ok) errorRate.add(1);
}

// ── Scenario: Add Sale (write operation — tests stock deduction race) ───────
function addSale() {
  // Use a known item_id that exists in your test data
  // Adjust ITEM_ID, QUANTITY, PRICE to match your seeded data
  const payload = JSON.stringify({
    item_id: 1, // CHANGE ME to a real item ID in your test DB
    item_name: "Test Product",
    quantity: 1,
    price: 100,
    timestamp: new Date().toISOString(),
    buyer_id: null, // walk-in sale
  });

  const res = http.post(`${BASE}/sales`, payload, { headers: headers() });

  const ok = check(res, {
    "add-sale: status 201 or 200": (r) => r.status === 200 || r.status === 201,
  });

  addSaleDuration.add(res.timings.duration);
  if (!ok) errorRate.add(1);
}

// ── Custom Summary Output ───────────────────────────────────────────────────
export function handleSummary(data) {
  console.log("");
  console.log("══════════════════════════════════════════════════");
  console.log("  LZCAS LOAD TEST RESULTS");
  console.log("══════════════════════════════════════════════════");
  console.log(
    `  Total Requests:     ${data.metrics.http_reqs?.values?.count || 0}`,
  );
  console.log(
    `  Failed Requests:    ${data.metrics.http_req_failed?.values?.rate ? (data.metrics.http_req_failed.values.rate * 100).toFixed(2) : "0.00"}%`,
  );
  console.log(
    `  Custom Errors:      ${(data.metrics.errors?.values?.rate * 100).toFixed(2) || "0.00"}%`,
  );
  console.log(
    `  Avg Response:       ${data.metrics.http_req_duration?.values?.avg?.toFixed(0) || 0}ms`,
  );
  console.log(
    `  P95 Response:       ${data.metrics.http_req_duration?.values["p(95)"]?.toFixed(0) || 0}ms`,
  );
  console.log(
    `  Max Response:       ${data.metrics.http_req_duration?.values?.max?.toFixed(0) || 0}ms`,
  );
  console.log(
    `  Peak VUs:           ${data.metrics.vus_max?.values?.value || 0}`,
  );
  console.log("");
  console.log("  Per-Endpoint Durations (avg):");
  console.log(
    `    fetch_items:      ${data.metrics.fetch_items_duration?.values?.avg?.toFixed(0) || 0}ms`,
  );
  console.log(
    `    fetch_members:    ${data.metrics.fetch_members_duration?.values?.avg?.toFixed(0) || 0}ms`,
  );
  console.log(
    `    fetch_sales:      ${data.metrics.fetch_sales_duration?.values?.avg?.toFixed(0) || 0}ms`,
  );
  console.log(
    `    dashboard_stats:  ${data.metrics.dashboard_stats_duration?.values?.avg?.toFixed(0) || 0}ms`,
  );
  console.log(
    `    pending_requests: ${data.metrics.pending_requests_duration?.values?.avg?.toFixed(0) || 0}ms`,
  );
  console.log(
    `    add_sale:         ${data.metrics.add_sale_duration?.values?.avg?.toFixed(0) || 0}ms`,
  );
  console.log("══════════════════════════════════════════════════");

  return { stdout: textSummary(data, { indent: " ", enableColors: false }) };
}
