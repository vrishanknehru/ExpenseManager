# Feature Test Checklist

## Authentication
- [ ] Employee login with correct credentials
- [ ] Admin login with correct credentials
- [ ] Wrong password shows error message
- [ ] Session persistence — close and reopen app, should auto-login
- [ ] Sign out from Profile tab — returns to login, reopening does NOT auto-login

## Employee Navigation
- [ ] Bottom nav: Home / History / Profile tabs work correctly
- [ ] Profile tab shows avatar, name, email, employee details, Sign Out button
- [ ] "See All" on Home switches to History tab

## Bill Submission
- [ ] Full flow: capture image → OCR extracts fields → fill form → submit
- [ ] Amount must be > 0 (try 0 or negative — should be rejected)
- [ ] Amount must be ≤ ₹10,00,000 (try 9999999 — should be rejected)
- [ ] Future date rejected (1 day grace)
- [ ] Duplicate invoice number blocked — submit a bill, then try same invoice number
- [ ] File size > 10MB rejected
- [ ] FAB only visible on Home tab

## Employee History
- [ ] Bills sorted by bill date (not upload date)
- [ ] Bills grouped by month headers ("March 2026", "February 2026")

## Bill Viewer
- [ ] Shows Bill Date and Uploaded date in details
- [ ] Documents section shows Original Bill and Generated PDF in one card
- [ ] Rejection reason visible under "Admin Remarks" for rejected bills
- [ ] Tap image/PDF to view full screen

## Admin Dashboard
- [ ] Search bar filters by employee name, purpose, invoice number, amount
- [ ] Filter chips (All/Pending/Approved/Rejected) with count badges
- [ ] Bills sorted by bill date, cards show "Bill Date · Uploaded date"
- [ ] Pagination — "Load more" button appears with 20+ bills
- [ ] CSV export — tap download icon, paste clipboard to verify CSV data
- [ ] Analytics — tap chart icon, bar chart of last 6 months + top 5 categories

## Admin Actions
- [ ] Approve a bill — `approved_by` and `status_updated_at` saved in DB
- [ ] Reject a bill — must enter remarks, employee sees rejection reason
- [ ] Admin cannot edit bill fields (security)

## PWA & Connectivity
- [ ] Offline banner — turn off WiFi, red "You are offline" banner appears at top
- [ ] Banner disappears when back online
- [ ] PWA install — Chrome install prompt or "Add to Home Screen" on mobile
- [ ] Theme color is dark (#171717)

## Security
- [ ] RLS — employee can only see their own bills
- [ ] RLS — admin can see all bills
- [ ] Plaintext password column removed from users table
- [ ] Auth uses Supabase Auth SDK (bcrypt hashed passwords, JWT sessions)
- [ ] CORS on edge functions uses ALLOWED_ORIGIN env var
