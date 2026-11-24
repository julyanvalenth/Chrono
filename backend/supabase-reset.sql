-- ============================================================
-- Chrono Backend – Full reset (drops the tables, then recreates
-- them exactly as the backend code expects).
-- Run this in the Supabase SQL Editor.
-- WARNING: deletes every row in these five tables.
-- ============================================================

drop table if exists chat_messages cascade;
drop table if exists blocks cascade;
drop table if exists deadlines cascade;
drop table if exists courses cascade;
drop table if exists preferences cascade;

-- ---- Preferences ----
create table preferences (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id) on delete cascade not null unique,
  name        text not null default 'Student',
  focus_window text not null default 'morning',
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
create table courses (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id) on delete cascade not null,
  code        text not null default '',
  name        text not null,
  days        int[] not null,
  start_min   int not null,
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
create table blocks (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id) on delete cascade not null,
  day         int not null,
  title       text not null,
  kind        text not null,
  start_min   int not null,
  end_min     int not null,
  detail      text,
  origin      text,
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
create table deadlines (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id) on delete cascade not null,
  title       text not null,
  course      text not null default '',
  estimate    int not null,
  due         text not null,
  urgent      boolean not null default false,
  planned     int not null default 0,
  done        boolean not null default false,
  created_at  timestamptz not null default now()
);

alter table deadlines enable row level security;
create policy "Users manage own deadlines"
  on deadlines for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ---- Chat messages ----
create table chat_messages (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id) on delete cascade not null,
  type        text not null,
  from_user   boolean not null default false,
  content     text,
  changes     jsonb,
  status      text,
  deadline_id uuid,
  created_at  timestamptz not null default now()
);

alter table chat_messages enable row level security;
create policy "Users manage own messages"
  on chat_messages for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ---- Indexes ----
create index idx_blocks_user_day on blocks(user_id, day);
create index idx_deadlines_user   on deadlines(user_id);
create index idx_chat_user        on chat_messages(user_id, created_at);

-- ---- Permissions (needed on newer Supabase projects) ----
grant usage on schema public to anon, authenticated, service_role;
grant all on table preferences, courses, blocks, deadlines, chat_messages to service_role;
grant select, insert, update, delete on table preferences, courses, blocks, deadlines, chat_messages to authenticated;

notify pgrst, 'reload schema';
