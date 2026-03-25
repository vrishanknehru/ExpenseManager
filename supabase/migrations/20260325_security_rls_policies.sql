-- ============================================================
-- Security Migration: RLS Policies + Storage Security
-- ============================================================

-- 1. Enable Row Level Security on tables
ALTER TABLE public.bills ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- 2. RLS Policies for 'bills' table

CREATE POLICY "employees_select_own_bills"
  ON public.bills FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "admins_select_all_bills"
  ON public.bills FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE users.id = auth.uid()
      AND users.role = 'admin'
    )
  );

CREATE POLICY "employees_insert_own_bills"
  ON public.bills FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "admins_update_bills"
  ON public.bills FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE users.id = auth.uid()
      AND users.role = 'admin'
    )
  );

CREATE POLICY "employees_delete_own_pending_bills"
  ON public.bills FOR DELETE
  USING (
    auth.uid() = user_id
    AND status = 'pending'
  );

-- 3. RLS Policies for 'users' table

CREATE POLICY "users_select_own_profile"
  ON public.users FOR SELECT
  USING (auth.uid() = id);

CREATE POLICY "admins_select_all_profiles"
  ON public.users FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid()
      AND u.role = 'admin'
    )
  );

-- 4. Add audit trail columns to bills table (if they don't exist)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'bills' AND column_name = 'approved_by'
  ) THEN
    ALTER TABLE public.bills ADD COLUMN approved_by TEXT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'bills' AND column_name = 'status_updated_at'
  ) THEN
    ALTER TABLE public.bills ADD COLUMN status_updated_at TIMESTAMPTZ;
  END IF;
END $$;

-- 5. Storage RLS policies for receipts bucket

CREATE POLICY "users_upload_own_receipts"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'receipts'
    AND auth.role() = 'authenticated'
  );

CREATE POLICY "users_read_receipts"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'receipts'
    AND auth.role() = 'authenticated'
  );
