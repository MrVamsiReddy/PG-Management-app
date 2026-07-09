create table if not exists public.admin_setup_attempts (
  id         bigint generated always as identity primary key,
  ip         text,
  email      text,
  success    boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists admin_setup_attempts_ip_idx
  on public.admin_setup_attempts (ip, created_at);

alter table public.admin_setup_attempts enable row level security;
