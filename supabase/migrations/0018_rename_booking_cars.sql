-- rename bookings.vehicles (jsonb list of cars) to cars so it doesn't clash with the vehicles relationship
alter table public.bookings rename column vehicles to cars;
-- create_booking updated to insert into cars (see 0017)
