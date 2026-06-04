# Supabase Setup

This project can use Supabase as the online database while keeping Drift/SQLite
as the local offline database.

## 1. Create Supabase Project

1. Go to https://supabase.com/dashboard.
2. Create a new project.
3. Open the SQL Editor.
4. Paste and run `supabase/schema.sql` from this repository.

## 2. Get Your App Keys

In Supabase:

1. Open Project Settings.
2. Open API.
3. Copy the Project URL.
4. Copy the anon public key.

Do not put the service role key in the Flutter app.

## 3. Run Flutter With Supabase Enabled

Use `--dart-define` so secrets are not hardcoded:

```powershell
flutter run `
  --dart-define=SUPABASE_URL=https://your-project-ref.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=your-anon-key
```

If those values are not provided, the app still runs using local SQLite only.

## 4. Upload Current Local Data

The app now has `SupabaseSyncService.uploadLocalSnapshot()`, which uploads:

- `items`
- `members`
- `sales`

This is only the first sync layer. The next step is to add a button or startup
job that calls this service when the device is online.

## 5. Production Notes

Before real users use the online database:

- Add authentication.
- Enable Row Level Security on each Supabase table.
- Add RLS policies for the user roles.
- Add proper offline sync conflict handling.
- Consider adding UUID sync IDs later if multiple devices will create records
  independently.
