-- ============================================================
-- Chrono Backend – Supabase Schema
-- Run this in the Supabase SQL Editor to set up all tables.
-- ============================================================

-- ---- Preferences ----
create table if not exists preferences (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id) on delete cascade not null unique,
  name        text not null default 'Student',
  focus_window text not null default 'morning',   -- morning | afternoon | night
  bedtime     text not null default '23:00',
  break_minutes int not null default 15,
  onboarding_complete boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

alter table preferences enable row level security;
create policy "Users manage own preferences"
  on preferences for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ---- Courses (fixed class schedule) ----
create table if not exists courses (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id) on delete cascade not null,
  code        text not null default '',
  name        text not null,
  days        int[] not null,          -- 0=Mon … 6=Sun
  start_min   int not null,            -- minutes from midnight
  end_min     int not null,
  room        text not null default '',
  selected    boolean not null default true,
  created_at  timestamptz not null default now()
);

alter table courses enable row level security;
create policy "Users manage own courses"
  on courses for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ---- Blocks (time blocks on the weekly calendar) ----
create table if not exists blocks (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id) on delete cascade not null,
  day         int not null,            -- 0=Mon … 6=Sun
  title       text not null,
  kind        text not null,           -- lecture | focus | task | personal | breakTime
  start_min   int not null,
  end_min     int not null,
  detail      text,
  origin      text,                    -- added | moved | null
  done        boolean not null default false,
  course_id   uuid references courses(id) on delete set null,
  created_at  timestamptz not null default now()
);

alter table blocks enable row level security;
create policy "Users manage own blocks"
  on blocks for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ---- Deadlines ----
create table if not exists deadlines (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id) on delete cascade not null,
  title       text not null,
  course      text not null default '',
  estimate    int not null,            -- minutes total
  due         text not null,
  urgent      boolean not null default false,
  planned     int not null default 0,  -- minutes already scheduled
  done        boolean not null default false,
  created_at  timestamptz not null default now()
);

alter table deadlines enable row level security;
create policy "Users manage own deadlines"
  on deadlines for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ---- Chat messages ----
create table if not exists chat_messages (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id) on delete cascade not null,
  type        text not null,           -- text | proposal
  from_user   boolean not null default false,
  content     text,                    -- text body
  changes     jsonb,                   -- proposed changes (for proposals)
  status      text,                    -- pending | applied | dismissed
  deadline_id uuid,
  created_at  timestamptz not null default now()
);

alter table chat_messages enable row level security;
create policy "Users manage own messages"
  on chat_messages for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ---- Indexes ----
create index if not exists idx_blocks_user_day on blocks(user_id, day);
create index if not exists idx_deadlines_user   on deadlines(user_id);
create index if not exists idx_chat_user        on chat_messages(user_id, created_at);

-- ---- Permissions (needed on newer Supabase projects) ----
grant usage on schema public to anon, authenticated, service_role;

-- Backend (secret / service_role key): full access, RLS bypassed
grant all on table preferences, courses, blocks, deadlines, chat_messages to service_role;

-- Signed-in users (RLS policies still limit them to their own rows)
grant select, insert, update, delete on table preferences, courses, blocks, deadlines, chat_messages to authenticated;

-- Make the API pick up the change right away
notify pgrst, 'reload schema';
