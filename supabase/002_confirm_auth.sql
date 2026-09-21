-- Konfirmasi semua akun Auth yang sudah ada.
-- Toggle "Confirm email" di dashboard TIDAK mengisi email_confirmed_at
-- untuk user yang dibuat sebelumnya (termasuk lewat Authentication → Users).
-- SQL Editor project baru → Run.

UPDATE auth.users
SET email_confirmed_at = COALESCE(email_confirmed_at, now())
WHERE email_confirmed_at IS NULL;
