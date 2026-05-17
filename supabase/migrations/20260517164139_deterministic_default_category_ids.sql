-- Align server-seeded default categories with the iOS offline seed IDs.
-- The app can create expenses offline before a pull, so these IDs must be
-- stable across local SwiftData and Supabase validation.

update public.categories
set id = '00000001-0000-0000-0000-000000000000'::uuid,
    trip_id = null,
    icon = '🍽',
    deleted_at = null
where is_default and name = 'Food & Drink';

update public.categories
set id = '00000002-0000-0000-0000-000000000000'::uuid,
    trip_id = null,
    icon = '🚗',
    deleted_at = null
where is_default and name = 'Transport';

update public.categories
set id = '00000003-0000-0000-0000-000000000000'::uuid,
    trip_id = null,
    icon = '🏨',
    deleted_at = null
where is_default and name = 'Lodging';

update public.categories
set id = '00000004-0000-0000-0000-000000000000'::uuid,
    trip_id = null,
    icon = '🎭',
    deleted_at = null
where is_default and name = 'Activities';

update public.categories
set id = '00000005-0000-0000-0000-000000000000'::uuid,
    trip_id = null,
    icon = '🛍',
    deleted_at = null
where is_default and name = 'Shopping';

update public.categories
set id = '00000006-0000-0000-0000-000000000000'::uuid,
    trip_id = null,
    icon = '⋯',
    deleted_at = null
where is_default and name = 'Other';

insert into public.categories (id, trip_id, name, icon, is_default)
values
  ('00000001-0000-0000-0000-000000000000', null, 'Food & Drink', '🍽', true),
  ('00000002-0000-0000-0000-000000000000', null, 'Transport',    '🚗', true),
  ('00000003-0000-0000-0000-000000000000', null, 'Lodging',      '🏨', true),
  ('00000004-0000-0000-0000-000000000000', null, 'Activities',   '🎭', true),
  ('00000005-0000-0000-0000-000000000000', null, 'Shopping',     '🛍', true),
  ('00000006-0000-0000-0000-000000000000', null, 'Other',        '⋯', true)
on conflict (id) do update set
  trip_id = excluded.trip_id,
  name = excluded.name,
  icon = excluded.icon,
  is_default = excluded.is_default,
  deleted_at = null;
