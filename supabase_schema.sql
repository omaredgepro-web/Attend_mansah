-- Supabase schema for attendance system - Project: jqqczvohurvedmnilrzx
-- Run in: Supabase Dashboard > SQL Editor > New Query > Paste > Run

-- 1) جدول الموظفين (للـ dropdown + ربط الجهاز)
create table if not exists public.employees (
  id bigint generated always as identity primary key,
  name text unique not null,
  device_id text unique,
  created_at timestamptz default now()
);

-- 2) جدول الحضور - نفس اعمدة الشيت
create table if not exists public.attendance_logs (
  id bigint generated always as identity primary key,
  name text not null references public.employees(name) on update cascade,
  site text not null check (site in ('From Site','From Home')),
  log_date date not null default ((now() at time zone 'Africa/Cairo'))::date,
  log_time time not null default ((now() at time zone 'Africa/Cairo'))::time(0),
  location text not null,
  device_id text,
  created_at timestamptz default now()
);

create index if not exists idx_att_date on public.attendance_logs(log_date desc);
create index if not exists idx_att_name on public.attendance_logs(name);
-- منع التكرار: الاسم الواحد يسجل مرة واحدة بس في اليوم
create unique index if not exists uniq_att_name_date on public.attendance_logs(name, log_date);

-- 3) Function: فرض وقت مصر + لوكيشن اجباري + ربط الجهاز مرة واحدة
create or replace function public.enforce_attendance_rules()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_bound_device text;
begin
  if new.name is null or btrim(new.name) = '' then
    raise exception 'يجب اختيار الاسم';
  end if;

  if new.site not in ('From Site','From Home') then
    raise exception 'قيمة الموقع غير صحيحة';
  end if;

  if new.location is null or btrim(new.location) = '' then
    raise exception 'اللوكيشن اجباري - لازم تفتح اللوكيشن';
  end if;

  if position(',' in new.location) = 0 then
    raise exception 'صيغة اللوكيشن غير صحيحة';
  end if;

  if new.device_id is null or btrim(new.device_id) = '' then
    raise exception 'Device ID مفقود';
  end if;

  -- التاريخ والوقت من السيرفر بتوقيت مصر
  new.log_date := ((now() at time zone 'Africa/Cairo'))::date;
  new.log_time := ((now() at time zone 'Africa/Cairo'))::time(0);
  new.created_at := now();

  -- منع التسجيل اكتر من مرة في نفس اليوم
  if exists (select 1 from public.attendance_logs where name = new.name and log_date = new.log_date) then
    raise exception 'تم تسجيل اليوم بالفعل';
  end if;

  select device_id into v_bound_device from employees where name = new.name;
  if not found then
    raise exception 'الاسم % غير مسجل', new.name;
  end if;

  if v_bound_device is null or v_bound_device = '' then
    update employees set device_id = new.device_id where name = new.name;
  elsif v_bound_device <> new.device_id then
    raise exception 'الجهاز غير مطابق! الحساب مربوط بجهاز تاني. كلم الإدارة';
  end if;

  if exists (select 1 from employees where device_id = new.device_id and name <> new.name) then
    raise exception 'الجهاز ده مربوط باسم تاني بالفعل';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_attendance_rules on public.attendance_logs;
create trigger trg_attendance_rules
before insert on public.attendance_logs
for each row execute function public.enforce_attendance_rules();

-- 4) RLS: محدش يقدر يعدل او يمسح
alter table public.employees enable row level security;
alter table public.attendance_logs enable row level security;

drop policy if exists "employees_select_all" on public.employees;
create policy "employees_select_all"
on public.employees for select to anon, authenticated using (true);

drop policy if exists "attendance_insert_all" on public.attendance_logs;
create policy "attendance_insert_all"
on public.attendance_logs for insert to anon, authenticated with check (true);

drop policy if exists "attendance_select_all" on public.attendance_logs;
create policy "attendance_select_all"
on public.attendance_logs for select to anon, authenticated using (true);
-- مفيش update/delete policy = اي update/delete هيترفض تلقائيا

-- 5) View بنفس هيدرات الشيت بالظبط للتصدير
create or replace view public.signature_sheet as
select
  name as "Name",
  site as "site",
  log_date as "Date",
  to_char(log_time, 'HH12:MI:SS AM') as "Time",
  location as "Location",
  device_id as "Device ID"
from public.attendance_logs
order by log_date desc, log_time desc;

-- 6) دخّل الاسامي اللي في الشيت عندك
insert into public.employees (name) values
('رحمه محمد'),('اماني هارون'),('فيروز فايز'),('ابتهال ايهاب'),('بسنت طارق'),('منه الله عادل')

on conflict (name) do nothing;
