# Reimbursement App

A full-stack expense reimbursement system built with Flutter and Supabase, deployed as a Progressive Web App (PWA).

Employees submit bills with photos or PDFs, OCR automatically extracts invoice details, and admins approve or reject with mandatory remarks. Approved bills trigger automated email notifications to the employee and ERP system.

---

## Features

**Employee Portal**
- Upload bill images (camera/gallery) or PDFs
- Automatic OCR extraction of invoice number, amount, and date via Google Cloud Vision API
- PDF generation from bill data for record-keeping
- Real-time status tracking with inline rejection reasons
- Full bill history with detail view and pinch-to-zoom image preview

**Admin Portal**
- View all submitted bills across employees
- Approve or reject with mandatory rejection remarks
- Full bill detail view with attached image/PDF preview
- Status-based filtering and employee identification

**Automated Workflows**
- Server-side OCR via Supabase Edge Function (works on all platforms including web)
- ERP email with PDF attachment on approval via Resend
- Database webhook triggers for automated processing

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Frontend | Flutter (Dart) — cross-platform: Web, iOS, Android |
| Backend | Supabase (PostgreSQL, Storage, Edge Functions) |
| OCR | Google Cloud Vision API via Supabase Edge Function |
| Email | Resend API |
| Deployment | Vercel (PWA) |
| Auth | Custom auth against Supabase `users` table |

---

## Getting Started

### Prerequisites

- Flutter SDK (stable channel, Dart ^3.8.1)
- Node.js (for Supabase CLI)
- A Supabase project
- A Google Cloud project with Vision API enabled

### 1. Clone and install dependencies

```bash
git clone https://github.com/vrishanknehru/reimbursement-v2.git
cd reimbursement-v2
flutter pub get
```

### 2. Environment setup

Create a `.env` file in the project root:

```env
SUPABASE_URL=https://your-project-ref.supabase.co
SUPABASE_ANON_KEY=your-anon-key
```

### 3. Database setup

Run this SQL in the Supabase SQL Editor:

```sql
CREATE TABLE users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text NOT NULL UNIQUE,
  password text NOT NULL,
  role text NOT NULL DEFAULT 'employee',
  username text
);

CREATE TABLE bills (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES users(id),
  purpose text,
  amount float8,
  date text,
  status text DEFAULT 'pending',
  image_url text,
  generated_pdf_url text,
  source text,
  invoice_no text,
  description text,
  created_at timestamptz DEFAULT now(),
  admin_notes text
);
```

### 4. Storage setup

Create a public storage bucket named `receipts` in the Supabase dashboard.

Add these storage policies in the SQL Editor:

```sql
CREATE POLICY "Allow public uploads" ON storage.objects
  FOR INSERT WITH CHECK (bucket_id = 'receipts');

CREATE POLICY "Allow public reads" ON storage.objects
  FOR SELECT USING (bucket_id = 'receipts');
```

### 5. Deploy Edge Functions

```bash
npm install -g supabase
supabase link --project-ref your-project-ref
supabase secrets set GOOGLE_VISION_API_KEY=your-key
supabase secrets set ERP_EMAIL=erp@yourcompany.com
supabase functions deploy ocr-extract
supabase functions deploy send-approval-email
```

### 6. Run locally

```bash
flutter run -d chrome
```

---

## Deployment

Build and deploy the PWA to Vercel:

```bash
flutter build web --release
cd build/web
vercel --prod
```

Live at [expensemanager-vn.vercel.app](https://expensemanager-vn.vercel.app). Employees can "Add to Home Screen" from Safari for a native app-like experience.

---

## Project Structure

```
lib/
├── main.dart                          # App entry, Supabase init
└── screens/
    ├── login_page.dart                # Email/password auth
    ├── employee/
    │   ├── employee_home.dart         # Dashboard with rejection banners
    │   ├── take_img.dart              # Camera/gallery/PDF capture + OCR
    │   ├── upload_details.dart        # Bill form with animated upload
    │   ├── history_page.dart          # Full bill history
    │   └── bill_viewer_page.dart      # Bill detail + image viewer
    └── admin/
        └── admin_dashboard.dart       # All bills, approve/reject actions

supabase/functions/
├── ocr-extract/index.ts               # Google Vision API OCR
└── send-approval-email/index.ts       # ERP email with PDF via Resend
```

---

## Bill Workflow

```
Employee uploads image/PDF
        ↓
OCR extracts invoice details (server-side)
        ↓
Employee reviews, corrects, and submits
        ↓
PDF generated and uploaded to Supabase Storage
        ↓
Bill record inserted (status: pending)
        ↓
Admin reviews → Approve or Reject (with remarks)
        ↓
On approval: ERP email sent with PDF attachment
On rejection: reason visible to employee on dashboard
```

