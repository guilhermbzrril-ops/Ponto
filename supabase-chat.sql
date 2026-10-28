-- Ponto: tabelas e políticas para chat individual
-- Compatível com a tabela profiles existente (user_id, display_name, updated_at).
-- Execute este arquivo no SQL Editor do projeto Supabase.

-- Mantém a tabela profiles existente e adiciona somente a coluna que falta.
alter table public.profiles
  add column if not exists email text;

alter table public.profiles enable row level security;

drop policy if exists "Authenticated users can view chat directory" on public.profiles;
create policy "Authenticated users can view chat directory"
  on public.profiles for select to authenticated using (true);

-- Sincroniza o perfil quando um usuário é criado ou seu e-mail é alterado.
create or replace function public.sync_chat_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (user_id, display_name, updated_at, email)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'display_name', ''), nullif(split_part(coalesce(new.email, ''), '@', 1), ''), 'Usuário'),
    now(),
    new.email
  )
  on conflict (user_id) do update
    set email = excluded.email,
        updated_at = now();
  return new;
end;
$$;

drop trigger if exists sync_chat_profile on auth.users;
create trigger sync_chat_profile
  after insert or update of email on auth.users
  for each row execute function public.sync_chat_profile();

-- Preenche os perfis dos usuários que já existem sem sobrescrever seus nomes.
insert into public.profiles (user_id, display_name, updated_at, email)
select
  u.id,
  coalesce(nullif(u.raw_user_meta_data ->> 'display_name', ''), nullif(split_part(coalesce(u.email, ''), '@', 1), ''), 'Usuário'),
  now(),
  u.email
from auth.users u
on conflict (user_id) do update
  set email = excluded.email,
      updated_at = now();

-- Mensagens privadas entre duas contas.
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
