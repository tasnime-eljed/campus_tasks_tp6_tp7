# Waiting Room

Flutter app with Supabase authentication, account approval, and a shared waiting queue.

## Supabase setup

1. In the Supabase SQL Editor for `waiting-room-app`, run [`supabase/waiting_room_setup.sql`](supabase/waiting_room_setup.sql).
2. Replace `YOUR_ADMIN_EMAIL` in the final SQL statement with the email address that should manage the queue, then run that statement. Admin promotion is deliberately explicit; public sign-up always creates a pending normal user.
3. In Supabase **Database → Publications**, ensure `public.clients` is enabled for `supabase_realtime` so new queue entries appear live.
4. In Supabase **Authentication → URL Configuration → Redirect URLs**, add `http://localhost:*/**` for local Flutter web runs. Add your deployed app URL there too when publishing the web app.
5. Create accounts in the app. The first admin approves them from **Comptes à approuver**. A normal user can then add their name to the queue. Only admins see the next-client and delete controls.

Password reset emails redirect to the current web app origin. The recovery link opens a page where the user enters and confirms a new password.

The migration preserves existing rows in `public.clients` and adds a nullable `user_id` for new queue entries. Existing Supabase Auth accounts are backfilled into `user_profiles` as pending normal users; promote the admin account before approving others.
