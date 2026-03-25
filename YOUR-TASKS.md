# What You Need To Do

Steps 1–5 are DONE (Claude ran them). Start from **Step 6**.

---

## ~~Step 1: Set Up Google Cloud Vision API~~ ✅ DONE

## ~~Step 2: Install Supabase CLI & Link~~ ✅ DONE

## ~~Step 3: Set Supabase Secrets~~ ✅ DONE
- `GOOGLE_VISION_API_KEY` is set
- `ERP_EMAIL` — set this later when you have a real ERP email address

## ~~Step 4: Deploy Edge Functions~~ ✅ DONE
- `ocr-extract` deployed
- `send-approval-email` deployed

## ~~Step 5: Create Database Tables~~ ✅ DONE

---

## Step 6: Create Storage Bucket (YOU DO THIS)

This is where uploaded bill images and PDFs are stored.

1. Go to **https://supabase.com/dashboard/project/fphhoxplluplnpteagnj/storage/buckets**
2. Click **"New Bucket"**
3. Name: `bills`
4. Toggle **"Public bucket"** ON
5. Click **"Create bucket"**

## Step 7: Create Webhook (YOU DO THIS)

This makes the approval email fire automatically when an admin approves a bill.

1. Go to **https://supabase.com/dashboard/project/fphhoxplluplnpteagnj** → **Database** → **Webhooks**
2. Click **"Create webhook"**
3. Fill in:
   - Name: `send-approval-email-trigger`
   - Table: `bills`
   - Events: check **UPDATE**
   - Type: **Supabase Edge Function** → select `send-approval-email`
4. Click **"Create webhook"**

---

## Step 8: Test Locally (app is running on Chrome)

Open Chrome — the app should already be open. Run through these tests in order:

### Test 1: Employee Login
- Email: `employee@test.com`
- Password: `test123`
- **Expected**: You see the employee dashboard (empty, no bills yet)
- ❌ If login fails: check browser console (F12 → Console tab) for errors

### Test 2: Upload a Bill (Image with OCR)
- Click the **+** button (FAB) at bottom right
- Click **"Select Image (Gallery)"** and pick any photo of a receipt/invoice
- **Expected**: Loading spinner shows "Scanning bill...", then you land on the form with some fields pre-filled (amount, invoice number, date)
- Fill in any missing fields (purpose, source, description) — all are required
- Click **Submit**
- **Expected**: Bill appears on your dashboard with status "pending"
- ❌ If OCR fails: check Supabase → Edge Functions → `ocr-extract` → Logs

### Test 3: Upload a Bill (PDF, no OCR)
- Click **+** again → **"Select PDF"** → pick any PDF
- **Expected**: Snackbar says "PDF selected. Please fill details manually."
- Fill in all fields manually and submit
- **Expected**: Second bill appears on dashboard as "pending"

### Test 4: View Bill History
- Tap on a bill card to open it
- **Expected**: You see the bill details and can view the uploaded image/PDF
- Go back, check the history page if available

### Test 5: Admin Login & Reject a Bill
- Log out (or open an incognito window)
- Login as admin:
  - Email: `admin@test.com`
  - Password: `test123`
- **Expected**: Admin dashboard shows all bills from all employees
- Tap a bill → click **Reject**
- Try submitting with empty remarks → **Expected**: error message saying remarks are required
- Type a reason (e.g., "Receipt is blurry, please resubmit") → Submit
- **Expected**: Bill status changes to "rejected"

### Test 6: Employee Sees Rejection
- Log back in as employee (`employee@test.com` / `test123`)
- **Expected**: You see a **red rejection banner** at the top of the dashboard
- The rejected bill card shows the **rejection reason** in red text below it

### Test 7: Admin Approves a Bill
- Log back in as admin
- Tap the other bill → click **Approve**
- **Expected**: Bill status changes to "approved"
- Check Supabase → Edge Functions → `send-approval-email` → **Logs** to see if the email function was triggered

---

## Step 9: Deploy to Vercel (after local testing passes)

1. Install Vercel CLI (if you don't have it):
   ```bash
   npm install -g vercel
   ```

2. Build and deploy:
   ```bash
   flutter build web --release
   cd build/web
   vercel
   ```
   - When it asks "Which scope?", pick your account
   - When it asks "Link to existing project?", say **No**
   - When it asks "What's your project's name?", type `reimb-app`

3. After it deploys, it gives you a URL like `reimb-app.vercel.app`

4. To deploy updates in the future:
   ```bash
   flutter build web --release
   cd build/web
   vercel --prod
   ```

---

## Quick Reference

| What | Where |
|------|-------|
| Supabase Dashboard | https://supabase.com/dashboard/project/fphhoxplluplnpteagnj |
| Storage Buckets | https://supabase.com/dashboard/project/fphhoxplluplnpteagnj/storage/buckets |
| Edge Function Logs | Supabase Dashboard → Edge Functions → select function → Logs tab |
| Google Cloud Console | https://console.cloud.google.com |
| Vercel Dashboard | https://vercel.com |

## Test Accounts

| Role | Email | Password |
|------|-------|----------|
| Employee | `employee@test.com` | `test123` |
| Admin | `admin@test.com` | `test123` |

---

*Last updated: 2026-03-23 — Setup complete, ready for local testing*
