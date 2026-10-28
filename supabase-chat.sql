-- Ponto: tabelas e políticas para chat individual
-- Execute este arquivo no SQL Editor do projeto Supabase antes de usar o botão Chat.

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
drop policy if exists "Authenticated users can view chat directory" on public.profiles;
create policy "Authenticated users can view chat directory"
  on public.profiles for select to authenticated using (true);

create or replace function public.sync_chat_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, email)
  values (new.id, new.email)
  on conflict (id) do update set email = excluded.email;
  return new;
end;
$$;

drop trigger if exists sync_chat_profile on auth.users;
create trigger sync_chat_profile
  after insert or update of email on auth.users
  for each row execute function public.sync_chat_profile();

insert into public.profiles (id, email)
select id, email from auth.users
on conflict (id) do update set email = excluded.email;

create table if not exists public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now(),
  constraint chat_messages_no_self_message check (sender_id <> recipient_id)
);

create index if not exists chat_messages_conversation_created_idx
  on public.chat_messages (sender_id, recipient_id, created_at);

alter table public.chat_messages enable row level security;
drop policy if exists "Participants can read their chat messages" on public.chat_messages;
create policy "Participants can read their chat messages"
  on public.chat_messages for select to authenticated
  using (auth.uid() = sender_id or auth.uid() = recipient_id);

drop policy if exists "Users can send chat messages as themselves" on public.chat_messages;
create policy "Users can send chat messages as themselves"
  on public.chat_messages for insert to authenticated
  with check (auth.uid() = sender_id and auth.uid() <> recipient_id);
