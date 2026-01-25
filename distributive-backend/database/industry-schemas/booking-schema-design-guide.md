# Travel / Booking Platform: Principal Architect Schema Design

> **Level**: Google L6+ / Principal Architect / Staff+ SRE
> **Scope**: Listings, Availability, Reservations, Reviews, Pricing — Production DDL

> [!CAUTION]
> **The Cardinal Sin**: Double booking. Availability MUST be checked with `FOR UPDATE` lock at reservation time. Race conditions = angry customers.

---

## 📚 Required Reading

| Paper/Resource | Topic |
| :--- | :--- |
| [Airbnb's Service Architecture](https://medium.com/airbnb-engineering) | Booking system |
| [Calendar Availability at Scale](https://www.booking.com/articles/en/blog/travel-tech-talks) | Availability calendars |
| [Pricing & Yield Management](https://en.wikipedia.org/wiki/Yield_management) | Dynamic pricing |

---

## 🎯 The Principal Laws of Travel/Booking Schema Design

| Law | Statement | Implication |
| :--- | :--- | :--- |
| **Law 1: Availability Is Critical** | Can't oversell a room/property | Calendar + atomic reservations |
| **Law 2: Pricing Is Dynamic** | Weekend vs weekday, seasons | Price per night, not flat |
| **Law 3: Reviews Build Trust** | Both host and guest reviews | Bidirectional review system |
| **Law 4: Search Is Geo + Filters** | Location + dates + amenities | Elasticsearch + PostGIS |

---

# Part 1: Access Pattern Analysis

| # | Access Pattern | Frequency | Latency SLA | Database |
| :--- | :--- | :--- | :--- | :--- |
| 1 | Search listings (geo + dates) | 10M/s | < 200ms | Elasticsearch |
| 2 | Get listing details | 20M/s | < 50ms | Cache + PostgreSQL |
| 3 | Check availability (dates) | 10M/s | < 50ms | Redis + PostgreSQL |
| 4 | Create reservation | 100K/s | < 1s | PostgreSQL (ACID) |
| 5 | Get host's listings | 1M/s | < 100ms | PostgreSQL |
| 6 | Get user's reservations | 5M/s | < 100ms | PostgreSQL |
| 7 | Get/submit reviews | 1M/s | < 200ms | PostgreSQL |
| 8 | Update availability/pricing | 500K/s | < 500ms | PostgreSQL |
| 9 | Process payment | 100K/s | < 2s | Stripe integration |
| 10 | Send messages (host↔guest) | 500K/s | < 100ms | PostgreSQL + Push |

---

# Part 2: Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    BOOKING DATA ARCHITECTURE                     │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         PostgreSQL + PostGIS                     │
│  ✓ Listings    ✓ Reservations   ✓ Availability   ✓ Reviews      │
│                                                                  │
│  • users (hosts & guests)                                        │
│  • listings, listing_amenities                                   │
│  • availability_calendar (date → price + status)                 │
│  • reservations                                                  │
│  • reviews (bidirectional)                                       │
│  • messages                                                      │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         Redis                                    │
│  ✓ Availability cache    ✓ Pricing   ✓ Search cache             │
│                                                                  │
│  • availability:{listing_id}:{yyyy-mm}                           │
│  • listing_cache:{listing_id}                                    │
│  • search_cache:{query_hash}                                     │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         Elasticsearch                            │
│  ✓ Listing search    ✓ Geo   ✓ Filters   ✓ Autocomplete         │
│                                                                  │
│  • listings (title, description, amenities, location)            │
└─────────────────────────────────────────────────────────────────┘
```

---

# Part 3: PostgreSQL DDL

```sql
-- ============================================================
-- BOOKING PLATFORM SCHEMA: PostgreSQL + PostGIS Production DDL
-- Version: Listings, availability, and reservations
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "postgis";


-- ===========================================
-- SECTION 1: USERS (Hosts & Guests)
-- ===========================================

CREATE TABLE users (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Auth
    email               VARCHAR(255) NOT NULL UNIQUE,
    phone               VARCHAR(20),
    password_hash       TEXT,
    
    -- Profile
    first_name          VARCHAR(100) NOT NULL,
    last_name           VARCHAR(100) NOT NULL,
    avatar_url          TEXT,
    bio                 TEXT,
    
    -- Verification
    is_email_verified   BOOLEAN DEFAULT FALSE,
    is_phone_verified   BOOLEAN DEFAULT FALSE,
    is_id_verified      BOOLEAN DEFAULT FALSE,
    
    -- Host info
    is_superhost        BOOLEAN DEFAULT FALSE,
    host_since          DATE,
    
    -- Location
    country             VARCHAR(2),
    city                VARCHAR(100),
    
    -- Stats
    total_reviews       INT DEFAULT 0,
    avg_rating          DECIMAL(3,2),
    
    -- Payment
    stripe_customer_id  VARCHAR(50),
    stripe_account_id   VARCHAR(50),  -- For payouts (hosts)
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_users_email ON users(email);


-- ===========================================
-- SECTION 2: LISTINGS
-- ===========================================

CREATE TYPE listing_type AS ENUM (
    'entire_place', 'private_room', 'shared_room', 'hotel_room'
);

CREATE TYPE property_type AS ENUM (
    'apartment', 'house', 'villa', 'condo', 'cabin', 'cottage',
    'bungalow', 'loft', 'townhouse', 'hotel', 'hostel', 'resort'
);

CREATE TYPE listing_status AS ENUM ('draft', 'published', 'unlisted', 'suspended');

CREATE TABLE listings (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    host_id             UUID NOT NULL REFERENCES users(id),
    
    -- Basic info
    title               VARCHAR(255) NOT NULL,
    description         TEXT,
    
    -- Type
    listing_type        listing_type NOT NULL,
    property_type       property_type NOT NULL,
    
    -- Location
    address_line1       VARCHAR(255),
    city                VARCHAR(100) NOT NULL,
    state               VARCHAR(100),
    country             VARCHAR(2) NOT NULL,
    postal_code         VARCHAR(20),
    location            GEOGRAPHY(Point, 4326) NOT NULL,
    
    -- Capacity
    max_guests          INT NOT NULL DEFAULT 1,
    bedrooms            INT DEFAULT 0,
    beds                INT DEFAULT 1,
    bathrooms           DECIMAL(3,1) DEFAULT 1,
    
    -- Pricing (base, can be overridden per night)
    base_price          INT NOT NULL,  -- In cents
    cleaning_fee        INT DEFAULT 0,
    currency            VARCHAR(3) NOT NULL DEFAULT 'USD',
    
    -- Booking settings
    min_nights          INT DEFAULT 1,
    max_nights          INT DEFAULT 365,
    
    -- Instant book vs request
    instant_book        BOOLEAN DEFAULT FALSE,
    
    -- Check in/out times
    check_in_time       TIME DEFAULT '15:00',
    check_out_time      TIME DEFAULT '11:00',
    
    -- House rules
    pets_allowed        BOOLEAN DEFAULT FALSE,
    smoking_allowed     BOOLEAN DEFAULT FALSE,
    events_allowed      BOOLEAN DEFAULT FALSE,
    
    -- Status
    status              listing_status DEFAULT 'draft',
    
    -- Stats (denormalized)
    avg_rating          DECIMAL(3,2),
    review_count        INT DEFAULT 0,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_listings_host ON listings(host_id);
CREATE INDEX idx_listings_location ON listings USING GIST(location);
CREATE INDEX idx_listings_status ON listings(status) WHERE status = 'published';
CREATE INDEX idx_listings_city ON listings(city, country);


-- Listing images
CREATE TABLE listing_images (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    listing_id          UUID NOT NULL REFERENCES listings(id),
    
    url                 TEXT NOT NULL,
    caption             VARCHAR(255),
    position            INT DEFAULT 0,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_images_listing ON listing_images(listing_id);


-- ===========================================
-- SECTION 3: AMENITIES
-- ===========================================

CREATE TABLE amenities (
    id                  SERIAL PRIMARY KEY,
    name                VARCHAR(100) NOT NULL UNIQUE,
    category            VARCHAR(50),  -- 'essentials', 'features', 'safety', 'location'
    icon                VARCHAR(50)
);

INSERT INTO amenities (name, category) VALUES
    ('WiFi', 'essentials'),
    ('Kitchen', 'essentials'),
    ('Washer', 'essentials'),
    ('Air conditioning', 'essentials'),
    ('Heating', 'essentials'),
    ('TV', 'essentials'),
    ('Pool', 'features'),
    ('Hot tub', 'features'),
    ('Gym', 'features'),
    ('Free parking', 'features'),
    ('EV charger', 'features'),
    ('Smoke alarm', 'safety'),
    ('Carbon monoxide alarm', 'safety'),
    ('Fire extinguisher', 'safety'),
    ('Beachfront', 'location'),
    ('Waterfront', 'location'),
    ('Ski-in/Ski-out', 'location');

CREATE TABLE listing_amenities (
    listing_id          UUID NOT NULL REFERENCES listings(id),
    amenity_id          INT NOT NULL REFERENCES amenities(id),
    
    PRIMARY KEY (listing_id, amenity_id)
);


-- ===========================================
-- SECTION 4: AVAILABILITY CALENDAR
-- ===========================================

CREATE TYPE availability_status AS ENUM ('available', 'blocked', 'booked');

CREATE TABLE availability_calendar (
    id                  BIGSERIAL PRIMARY KEY,
    listing_id          UUID NOT NULL REFERENCES listings(id),
    date                DATE NOT NULL,
    
    -- Price for this specific night (overrides base_price)
    price               INT NOT NULL,  -- In cents
    
    -- Status
    status              availability_status DEFAULT 'available',
    
    -- If booked, link to reservation
    reservation_id      UUID,
    
    -- Min nights requirement for this date
    min_nights_override INT,
    
    CONSTRAINT uk_availability UNIQUE (listing_id, date)
);

CREATE INDEX idx_availability_listing ON availability_calendar(listing_id, date);
CREATE INDEX idx_availability_date ON availability_calendar(date);
CREATE INDEX idx_availability_status ON availability_calendar(listing_id, status, date);


-- ===========================================
-- SECTION 5: RESERVATIONS
-- ===========================================

CREATE TYPE reservation_status AS ENUM (
    'pending',          -- Awaiting host approval (non-instant book)
    'confirmed',        -- Approved, awaiting check-in
    'checked_in',       -- Guest has arrived
    'completed',        -- Stay completed
    'cancelled_guest',  -- Cancelled by guest
    'cancelled_host',   -- Cancelled by host
    'declined'          -- Host declined request
);

CREATE TABLE reservations (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    listing_id          UUID NOT NULL REFERENCES listings(id),
    guest_id            UUID NOT NULL REFERENCES users(id),
    host_id             UUID NOT NULL REFERENCES users(id),
    
    -- Confirmation code
    confirmation_code   VARCHAR(10) NOT NULL UNIQUE,
    
    -- Dates
    check_in_date       DATE NOT NULL,
    check_out_date      DATE NOT NULL,
    nights              INT GENERATED ALWAYS AS (check_out_date - check_in_date) STORED,
    
    -- Guests
    guests_count        INT NOT NULL DEFAULT 1,
    
    -- Status
    status              reservation_status DEFAULT 'pending',
    
    -- Pricing (snapshot at booking time)
    nightly_rate        INT NOT NULL,  -- Average rate
    subtotal            INT NOT NULL,  -- nights × rate
    cleaning_fee        INT DEFAULT 0,
    service_fee         INT DEFAULT 0,  -- Platform fee (guest)
    host_service_fee    INT DEFAULT 0,  -- Platform fee (host)
    taxes               INT DEFAULT 0,
    total_price         INT NOT NULL,
    currency            VARCHAR(3) NOT NULL,
    
    -- Payout to host
    host_payout         INT NOT NULL,
    
    -- Payment
    stripe_payment_intent_id VARCHAR(50),
    payment_status      VARCHAR(20) DEFAULT 'pending',
    
    -- Message from guest
    guest_message       TEXT,
    
    -- Timestamps
    booked_at           TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    confirmed_at        TIMESTAMP WITH TIME ZONE,
    cancelled_at        TIMESTAMP WITH TIME ZONE,
    
    -- Cancellation
    cancellation_reason TEXT,
    refund_amount       INT,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    CONSTRAINT ck_dates CHECK (check_out_date > check_in_date)
);

CREATE INDEX idx_reservations_listing ON reservations(listing_id);
CREATE INDEX idx_reservations_guest ON reservations(guest_id);
CREATE INDEX idx_reservations_host ON reservations(host_id);
CREATE INDEX idx_reservations_dates ON reservations(check_in_date, check_out_date);
CREATE INDEX idx_reservations_status ON reservations(status);
CREATE INDEX idx_reservations_code ON reservations(confirmation_code);


-- ===========================================
-- SECTION 6: REVIEWS (Bidirectional)
-- ===========================================

CREATE TYPE review_type AS ENUM ('guest_to_host', 'host_to_guest');

CREATE TABLE reviews (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    reservation_id      UUID NOT NULL REFERENCES reservations(id),
    
    review_type         review_type NOT NULL,
    
    -- Author and subject
    reviewer_id         UUID NOT NULL REFERENCES users(id),
    reviewee_id         UUID NOT NULL REFERENCES users(id),
    
    -- Linked listing (for listing reviews)
    listing_id          UUID REFERENCES listings(id),
    
    -- Overall rating
    overall_rating      INT NOT NULL CHECK (overall_rating BETWEEN 1 AND 5),
    
    -- Category ratings (guest reviews of listings)
    cleanliness_rating  INT CHECK (cleanliness_rating BETWEEN 1 AND 5),
    accuracy_rating     INT CHECK (accuracy_rating BETWEEN 1 AND 5),
    communication_rating INT CHECK (communication_rating BETWEEN 1 AND 5),
    location_rating     INT CHECK (location_rating BETWEEN 1 AND 5),
    check_in_rating     INT CHECK (check_in_rating BETWEEN 1 AND 5),
    value_rating        INT CHECK (value_rating BETWEEN 1 AND 5),
    
    -- Content
    public_review       TEXT,
    private_feedback    TEXT,  -- Only visible to host/guest
    
    -- Response
    response            TEXT,
    responded_at        TIMESTAMP WITH TIME ZONE,
    
    submitted_at        TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    CONSTRAINT uk_review UNIQUE (reservation_id, review_type)
);

CREATE INDEX idx_reviews_listing ON reviews(listing_id) WHERE listing_id IS NOT NULL;
CREATE INDEX idx_reviews_reviewee ON reviews(reviewee_id);


-- ===========================================
-- SECTION 7: MESSAGES
-- ===========================================

CREATE TABLE conversations (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    reservation_id      UUID REFERENCES reservations(id),
    
    -- Participants
    guest_id            UUID NOT NULL REFERENCES users(id),
    host_id             UUID NOT NULL REFERENCES users(id),
    listing_id          UUID NOT NULL REFERENCES listings(id),
    
    -- Last message preview
    last_message_at     TIMESTAMP WITH TIME ZONE,
    last_message_preview TEXT,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_conversations_guest ON conversations(guest_id);
CREATE INDEX idx_conversations_host ON conversations(host_id);

CREATE TABLE messages (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id     UUID NOT NULL REFERENCES conversations(id),
    sender_id           UUID NOT NULL REFERENCES users(id),
    
    content             TEXT NOT NULL,
    
    is_read             BOOLEAN DEFAULT FALSE,
    read_at             TIMESTAMP WITH TIME ZONE,
    
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_messages_conversation ON messages(conversation_id, created_at DESC);
```

---

# Part 4: Reservation Booking (Atomic)

```sql
-- Create reservation with atomic availability check
CREATE OR REPLACE FUNCTION create_reservation(
    p_listing_id UUID,
    p_guest_id UUID,
    p_check_in DATE,
    p_check_out DATE,
    p_guests_count INT
) RETURNS UUID AS $$
DECLARE
    v_reservation_id UUID := uuid_generate_v4();
    v_listing listings%ROWTYPE;
    v_nights INT;
    v_total_price INT;
    v_blocked_count INT;
BEGIN
    -- Lock listing
    SELECT * INTO v_listing FROM listings 
    WHERE id = p_listing_id FOR UPDATE;
    
    IF v_listing IS NULL THEN
        RAISE EXCEPTION 'Listing not found';
    END IF;
    
    IF v_listing.status != 'published' THEN
        RAISE EXCEPTION 'Listing not available';
    END IF;
    
    v_nights := p_check_out - p_check_in;
    
    -- Check min/max nights
    IF v_nights < v_listing.min_nights OR v_nights > v_listing.max_nights THEN
        RAISE EXCEPTION 'Invalid stay duration';
    END IF;
    
    -- Check guest count
    IF p_guests_count > v_listing.max_guests THEN
        RAISE EXCEPTION 'Too many guests';
    END IF;
    
    -- Lock and check availability for all dates
    SELECT COUNT(*) INTO v_blocked_count
    FROM availability_calendar
    WHERE listing_id = p_listing_id
      AND date >= p_check_in
      AND date < p_check_out
      AND status != 'available'
    FOR UPDATE;
    
    IF v_blocked_count > 0 THEN
        RAISE EXCEPTION 'Dates not available';
    END IF;
    
    -- Calculate pricing
    SELECT COALESCE(SUM(price), v_nights * v_listing.base_price) INTO v_total_price
    FROM availability_calendar
    WHERE listing_id = p_listing_id
      AND date >= p_check_in
      AND date < p_check_out;
    
    -- Create reservation
    INSERT INTO reservations (
        id, listing_id, guest_id, host_id, confirmation_code,
        check_in_date, check_out_date, guests_count, status,
        nightly_rate, subtotal, cleaning_fee, service_fee, total_price,
        currency, host_payout
    ) VALUES (
        v_reservation_id, p_listing_id, p_guest_id, v_listing.host_id,
        UPPER(SUBSTRING(MD5(v_reservation_id::TEXT) FROM 1 FOR 8)),
        p_check_in, p_check_out, p_guests_count,
        CASE WHEN v_listing.instant_book THEN 'confirmed' ELSE 'pending' END,
        v_total_price / v_nights,
        v_total_price,
        v_listing.cleaning_fee,
        (v_total_price * 0.12)::INT,  -- 12% service fee
        v_total_price + v_listing.cleaning_fee + (v_total_price * 0.12)::INT,
        v_listing.currency,
        (v_total_price * 0.97)::INT  -- 3% host fee
    );
    
    -- Block dates
    INSERT INTO availability_calendar (listing_id, date, price, status, reservation_id)
    SELECT 
        p_listing_id,
        generate_series(p_check_in, p_check_out - 1, '1 day'::interval)::DATE,
        v_listing.base_price,
        'booked',
        v_reservation_id
    ON CONFLICT (listing_id, date) 
    DO UPDATE SET status = 'booked', reservation_id = v_reservation_id;
    
    RETURN v_reservation_id;
END;
$$ LANGUAGE plpgsql;
```

---

## ✅ Principal Architect Checklist

| # | Item | Verification |
| :--- | :--- | :--- |
| 1 | Availability atomicity | FOR UPDATE + transaction |
| 2 | Price per night | availability_calendar.price |
| 3 | Bidirectional reviews | guest_to_host, host_to_guest |
| 4 | PostGIS for location | GEOGRAPHY(Point) + GIST index |
| 5 | Instant vs request book | instant_book boolean |
| 6 | Category ratings | 6 sub-ratings for listings |
| 7 | Confirmation code | Human-readable 8-char code |
| 8 | Pricing snapshot | nightly_rate stored at booking |

---

# Part 5: DynamoDB Single-Table Design

```
============================================================
BOOKING/TRAVEL: DynamoDB Single-Table Design
============================================================

TABLE: booking_data
- Partition Key (PK): String
- Sort Key (SK): String
- GSI1: GSI1PK / GSI1SK (status and date queries)
- GSI2: GSI2PK / GSI2SK (geo queries)

============================================================
ENTITY PATTERNS
============================================================

USER
  PK: USER#{user_id}
  SK: PROFILE
  GSI1PK: EMAIL#{email}
  GSI1SK: PROFILE
  
  Attributes: email, first_name, last_name, avatar_url, bio,
              is_superhost, stripe_customer_id, avg_rating

LISTING
  PK: LISTING#{listing_id}
  SK: META
  GSI1PK: HOST#{host_id}
  GSI1SK: LISTING#{listing_id}
  GSI2PK: CITY#{city}#COUNTRY#{country}
  GSI2SK: STATUS#{status}#LISTING#{listing_id}
  
  Attributes: title, description, listing_type, property_type,
              location, max_guests, base_price, avg_rating

LISTING_IMAGE
  PK: LISTING#{listing_id}
  SK: IMAGE#{position}
  
  Attributes: url, caption

LISTING_AMENITY
  PK: LISTING#{listing_id}
  SK: AMENITY#{amenity_id}
  
  Attributes: amenity_name, category

AVAILABILITY (per date)
  PK: LISTING#{listing_id}
  SK: AVAIL#{date}  -- YYYY-MM-DD
  GSI1PK: LISTING#{listing_id}#STATUS#{status}
  GSI1SK: DATE#{date}
  
  Attributes: price, status, reservation_id, min_nights_override

RESERVATION
  PK: USER#{guest_id}
  SK: RES#{reservation_id}
  GSI1PK: LISTING#{listing_id}
  GSI1SK: CHECKIN#{check_in_date}#RES#{reservation_id}
  GSI2PK: HOST#{host_id}
  GSI2SK: CHECKIN#{check_in_date}#RES#{reservation_id}
  
  Attributes: confirmation_code, check_in_date, check_out_date,
              guests_count, status, total_price, host_payout

REVIEW
  PK: LISTING#{listing_id}
  SK: REVIEW#{review_id}
  GSI1PK: USER#{reviewee_id}
  GSI1SK: DATE#{submitted_at}#REVIEW#{review_id}
  
  Attributes: review_type, reviewer_id, overall_rating,
              category_ratings, public_review, response

CONVERSATION
  PK: USER#{user_id}  -- Query from either perspective
  SK: CONV#{conversation_id}
  GSI1PK: CONV#{conversation_id}
  GSI1SK: LAST#{last_message_at}
  
  Attributes: guest_id, host_id, listing_id, last_message_preview

MESSAGE
  PK: CONV#{conversation_id}
  SK: MSG#{timestamp}#{message_id}
  
  Attributes: sender_id, content, is_read

============================================================
ACCESS PATTERNS → DynamoDB QUERIES
============================================================

1. Get listing with all images and amenities
   Table: PK=LISTING#{listing_id} (SK begins_with)

2. Get availability for listing (date range)
   Table: PK=LISTING#{listing_id}, SK between AVAIL#{start} and AVAIL#{end}

3. Get host's listings
   GSI1: PK=HOST#{host_id}

4. Get guest's reservations
   Table: PK=USER#{guest_id}, SK begins_with "RES#"

5. Get host's reservations
   GSI2: PK=HOST#{host_id}

6. Get listing reviews
   Table: PK=LISTING#{listing_id}, SK begins_with "REVIEW#"

7. Get user's conversations
   Table: PK=USER#{user_id}, SK begins_with "CONV#"

8. Get conversation messages
   Table: PK=CONV#{conversation_id}, SK begins_with "MSG#"

9. Find listings by city (for search, use Elasticsearch primarily)
   GSI2: PK=CITY#{city}#COUNTRY#{country}
```

---

# Part 6: Query Examples with EXPLAIN

```sql
-- ============================================================
-- BOOKING PLATFORM QUERY PATTERNS
-- ============================================================

-- ===========================================
-- QUERY 1: Search Listings (Geo + Dates + Filters)
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS)
WITH available_listings AS (
    SELECT listing_id
    FROM availability_calendar
    WHERE date >= $2::DATE 
      AND date < $3::DATE
      AND status = 'available'
    GROUP BY listing_id
    HAVING COUNT(*) = ($3::DATE - $2::DATE)  -- All dates available
)
SELECT 
    l.id,
    l.title,
    l.listing_type,
    l.property_type,
    l.max_guests,
    l.base_price,
    l.avg_rating,
    l.review_count,
    ST_Distance(l.location::geography, ST_MakePoint($4, $5)::geography) AS distance_meters,
    (SELECT url FROM listing_images WHERE listing_id = l.id ORDER BY position LIMIT 1) AS cover_image
FROM listings l
JOIN available_listings al ON al.listing_id = l.id
WHERE l.status = 'published'
  AND l.max_guests >= $1  -- Guest count
  AND ST_DWithin(l.location::geography, ST_MakePoint($4, $5)::geography, $6)  -- Radius
ORDER BY l.avg_rating DESC NULLS LAST, distance_meters
LIMIT 20;

-- Expected: PostGIS GIST index for geo, ~50ms


-- ===========================================
-- QUERY 2: Listing Detail with Availability
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    l.*,
    h.first_name AS host_name,
    h.avatar_url AS host_avatar,
    h.is_superhost,
    h.total_reviews AS host_reviews,
    (
        SELECT json_agg(jsonb_build_object(
            'date', ac.date,
            'price', ac.price,
            'status', ac.status
        ) ORDER BY ac.date)
        FROM availability_calendar ac
        WHERE ac.listing_id = l.id
          AND ac.date >= CURRENT_DATE
          AND ac.date < CURRENT_DATE + 90
    ) AS availability,
    (
        SELECT json_agg(a.name)
        FROM listing_amenities la
        JOIN amenities a ON a.id = la.amenity_id
        WHERE la.listing_id = l.id
    ) AS amenities,
    (
        SELECT json_agg(url ORDER BY position)
        FROM listing_images
        WHERE listing_id = l.id
    ) AS images
FROM listings l
JOIN users h ON h.id = l.host_id
WHERE l.id = $1;

-- Expected: ~5ms with proper indexes


-- ===========================================
-- QUERY 3: Check Availability (Atomic)
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    COUNT(*) FILTER (WHERE status != 'available') AS blocked_count,
    SUM(price) AS total_price,
    COUNT(*) AS nights
FROM availability_calendar
WHERE listing_id = $1
  AND date >= $2
  AND date < $3
FOR UPDATE;  -- Lock for reservation

-- Expected: ~1ms, row-level locks


-- ===========================================
-- QUERY 4: Host Dashboard
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    l.id AS listing_id,
    l.title,
    (
        SELECT COUNT(*) FROM reservations r
        WHERE r.listing_id = l.id
          AND r.check_in_date >= CURRENT_DATE
          AND r.status IN ('confirmed', 'checked_in')
    ) AS upcoming_reservations,
    (
        SELECT SUM(host_payout) FROM reservations r
        WHERE r.listing_id = l.id
          AND r.status = 'completed'
          AND r.check_out_date >= CURRENT_DATE - 30
    ) AS last_30_days_earnings,
    l.avg_rating,
    l.review_count
FROM listings l
WHERE l.host_id = $1
  AND l.status != 'draft'
ORDER BY upcoming_reservations DESC;

-- Expected: ~10ms with indices


-- ===========================================
-- QUERY 5: Reservation History with Reviews
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    r.id,
    r.confirmation_code,
    r.check_in_date,
    r.check_out_date,
    r.total_price,
    r.status,
    l.title AS listing_title,
    l.city,
    (SELECT url FROM listing_images WHERE listing_id = l.id ORDER BY position LIMIT 1) AS listing_image,
    (SELECT overall_rating FROM reviews 
     WHERE reservation_id = r.id AND review_type = 'guest_to_host') AS my_rating,
    (SELECT overall_rating FROM reviews 
     WHERE reservation_id = r.id AND review_type = 'host_to_guest') AS host_rating
FROM reservations r
JOIN listings l ON l.id = r.listing_id
WHERE r.guest_id = $1
ORDER BY r.check_in_date DESC
LIMIT 20;

-- Expected: ~15ms


-- ===========================================
-- QUERY 6: Revenue Report for Host
-- ===========================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    DATE_TRUNC('month', r.check_out_date) AS month,
    l.title AS listing,
    COUNT(*) AS reservations,
    SUM(r.nights) AS nights_booked,
    SUM(r.host_payout) AS earnings,
    AVG(rv.overall_rating) AS avg_rating
FROM reservations r
JOIN listings l ON l.id = r.listing_id
LEFT JOIN reviews rv ON rv.reservation_id = r.id AND rv.review_type = 'guest_to_host'
WHERE r.host_id = $1
  AND r.status = 'completed'
  AND r.check_out_date >= CURRENT_DATE - INTERVAL '12 months'
GROUP BY DATE_TRUNC('month', r.check_out_date), l.id, l.title
ORDER BY month DESC, earnings DESC;

-- Expected: ~25ms for 1 year data
```

---

# Part 7: Capacity Planning

```
============================================================
BOOKING PLATFORM CAPACITY PLANNING
============================================================

ASSUMPTIONS (Airbnb-scale):
- 7 million listings
- 150 million users
- 500,000 reservations/day
- 365 days of availability data
- 5-year data retention for reservations

============================================================
TABLE SIZE ESTIMATES
============================================================

USERS
  Rows: 150M
  Row Size: ~500 bytes
  Table Size: 75 GB
  Indexes: ~30 GB
  Total: ~105 GB

LISTINGS
  Rows: 7M
  Row Size: ~800 bytes
  Table Size: 5.6 GB
  Indexes: ~2 GB
  Total: ~7.6 GB

LISTING_IMAGES
  Rows: 7M × 10 avg = 70M
  Row Size: ~200 bytes
  Total: ~14 GB

AVAILABILITY_CALENDAR
  Rows: 7M listings × 365 days = 2.55 billion
  Row Size: ~50 bytes
  Table Size: 127.5 GB
  Indexes: ~50 GB
  Total: ~180 GB (partition by month!)

RESERVATIONS
  Rate: 500K/day × 365 × 5 years = 912.5M
  Row Size: ~600 bytes
  Table Size: 547.5 GB
  Indexes: ~200 GB
  Total: ~747.5 GB (partition by year!)

REVIEWS
  Rows: ~60% of reservations = 547.5M
  Row Size: ~800 bytes
  Total: ~438 GB

MESSAGES
  Rows: 5B (assuming 5 messages per conversation avg)
  Row Size: ~300 bytes
  Total: 1.5 TB (archive old!)

============================================================
TOTAL STORAGE
============================================================

| Table | Size | Partitioned |
|-------|------|-------------|
| Users | 105 GB | No |
| Listings | 8 GB | No |
| Images | 14 GB | No |
| Availability | 180 GB | By month |
| Reservations | 748 GB | By year |
| Reviews | 438 GB | By year |
| Messages | 1.5 TB | By month |
| **TOTAL** | **~3 TB** | - |

+ Replicas (3x) = 9 TB cluster

============================================================
READ/WRITE PATTERNS
============================================================

PEAK TRAFFIC:
  Search queries: 50,000 QPS
  Listing views: 100,000 QPS
  Availability checks: 20,000 QPS
  Reservations: 50 WPS peak (500K/day)
  Messages: 1,000 WPS

CACHING STRATEGY:
  Listing cache (Redis): 7M × 2KB = 14 GB
  Availability cache (Redis): Hot listings × 90 days
  Search cache (Redis): Query results, 1-hour TTL

ELASTICSEARCH:
  Index size: ~50 GB (listings only)
  Replicas: 3
  Shards: 10

============================================================
SCALING THRESHOLDS
============================================================

| Metric | Warning | Critical | Action |
|--------|---------|----------|--------|
| Availability table > 100GB/partition | > 200GB | Increase partition frequency |
| Search latency p99 > 200ms | > 500ms | Add Elasticsearch nodes |
| Booking conflicts > 0.1% | > 1% | Review locking strategy |
| Redis memory > 70% | > 90% | Scale Redis cluster |
| PostgreSQL connections > 80% | > 95% | Add pgbouncer capacity |

============================================================
COST ESTIMATES (AWS)
============================================================

PostgreSQL (RDS r6g.4xlarge):
  Primary: $1,460/month
  2 Read Replicas: $2,920/month
  Storage (3TB gp3): $345/month
  Total: $4,725/month

Redis (r6g.xlarge cluster):
  3 nodes: $693/month

Elasticsearch (3x r6g.xlarge.search):
  $1,188/month

S3 (images):
  10TB + transfers: ~$500/month

TOTAL: ~$7,100/month for Airbnb-scale platform
```

---

# Part 8: Anti-Patterns to Avoid

```
============================================================
BOOKING PLATFORM ANTI-PATTERNS
============================================================

❌ ANTI-PATTERN 1: Checking Availability Without Locks
-----------------------------------------
WRONG:
  -- Check availability
  SELECT COUNT(*) FROM availability_calendar
  WHERE listing_id = $1 AND date BETWEEN $2 AND $3 AND status != 'available';
  -- ... user confirms ...
  -- Book (but someone else booked in between!)
  
RIGHT:
  BEGIN;
  SELECT COUNT(*) FROM availability_calendar
  WHERE listing_id = $1 AND date BETWEEN $2 AND $3
  FOR UPDATE;  -- Lock the rows!
  -- ... create reservation ...
  COMMIT;


❌ ANTI-PATTERN 2: Storing Availability as Date Ranges
-----------------------------------------
WRONG:
  CREATE TABLE availability (
      listing_id UUID,
      start_date DATE,
      end_date DATE,
      price INT
  );
  -- Complex overlap queries, hard to update single days
  
RIGHT:
  CREATE TABLE availability_calendar (
      listing_id UUID,
      date DATE,  -- One row per day
      price INT,
      status availability_status
  );
  -- Simple queries, easy updates


❌ ANTI-PATTERN 3: No Price Snapshot in Reservation
-----------------------------------------
WRONG:
  CREATE TABLE reservations (
      listing_id UUID,
      -- No price stored, query listing.base_price
  );
  -- Host changes price, historical reservations show wrong amount!
  
RIGHT:
  CREATE TABLE reservations (
      nightly_rate INT,      -- Snapshot at booking
      subtotal INT,
      cleaning_fee INT,
      service_fee INT,
      total_price INT
  );


❌ ANTI-PATTERN 4: Single Reviews Table Without Type
-----------------------------------------
WRONG:
  -- Who reviewed whom? Confusing!
  CREATE TABLE reviews (
      reservation_id UUID,
      author_id UUID,
      target_id UUID,
      rating INT
  );
  
RIGHT:
  CREATE TABLE reviews (
      review_type review_type,  -- 'guest_to_host' or 'host_to_guest'
      reviewer_id UUID,
      reviewee_id UUID,
      listing_id UUID,  -- For guest reviews of property
      ...
  );


❌ ANTI-PATTERN 5: No Geo Index for Location Search
-----------------------------------------
WRONG:
  location_lat DECIMAL,
  location_lng DECIMAL,
  -- Calculate distance in application
  
RIGHT:
  location GEOGRAPHY(Point, 4326),
  CREATE INDEX idx_location ON listings USING GIST(location);
  -- ST_DWithin uses index efficiently


❌ ANTI-PATTERN 6: Unbounded Availability Calendar
-----------------------------------------
WRONG:
  -- 7M listings × 365 × 10 years = 25.5 billion rows!
  SELECT * FROM availability_calendar WHERE listing_id = $1;
  
RIGHT:
  -- Partition by month
  CREATE TABLE availability_calendar (...)
  PARTITION BY RANGE (date);
  
  -- Only keep 18 months of future dates
  -- Archive or delete past availability


❌ ANTI-PATTERN 7: Confirmation Code as Primary Key
-----------------------------------------
WRONG:
  confirmation_code VARCHAR(8) PRIMARY KEY,
  -- Short codes can collide at scale
  
RIGHT:
  id UUID PRIMARY KEY,
  confirmation_code VARCHAR(10) NOT NULL UNIQUE,
  -- UUID for internal use, code for customer-facing


❌ ANTI-PATTERN 8: No Cancellation Data
-----------------------------------------
WRONG:
  status VARCHAR(20),  -- Just 'cancelled'
  -- Why? When? Any refund?
  
RIGHT:
  status reservation_status,
  cancelled_at TIMESTAMP,
  cancellation_reason TEXT,
  cancelled_by VARCHAR(10),  -- 'guest' or 'host'
  refund_amount INT,
  refund_status VARCHAR(20)


❌ ANTI-PATTERN 9: Messages Without Conversation Grouping
-----------------------------------------
WRONG:
  CREATE TABLE messages (
      sender_id UUID,
      recipient_id UUID,
      content TEXT
  );
  -- How to get conversation thread? Complex queries
  
RIGHT:
  CREATE TABLE conversations (
      id UUID,
      guest_id UUID,
      host_id UUID,
      listing_id UUID
  );
  CREATE TABLE messages (
      conversation_id UUID,
      sender_id UUID,
      content TEXT
  );


❌ ANTI-PATTERN 10: Float for Money
-----------------------------------------
WRONG:
  price DECIMAL(10, 2),  -- $150.00
  -- Currency conversion errors
  
RIGHT:
  price INT,  -- 15000 cents
  currency VARCHAR(3),
  -- Always store in smallest unit (cents)
```

---

# Part 9: CDC & Event Streaming

```
============================================================
BOOKING PLATFORM CDC ARCHITECTURE
============================================================

┌─────────────┐     ┌─────────────┐     ┌─────────────────┐
│ PostgreSQL  │────►│  Debezium   │────►│  Kafka          │
│             │     │             │     │                 │
└─────────────┘     └─────────────┘     └────────┬────────┘
                                                  │
        ┌─────────────────┬───────────────┬──────┴──────┐
        ▼                 ▼               ▼             ▼
  ┌───────────┐    ┌───────────┐   ┌───────────┐  ┌──────────┐
  │Elasticsearch│   │ Analytics │   │ Email/SMS │  │ Payments │
  │ (search)    │   │ (BI)      │   │ (notifs)  │  │ (Stripe) │
  └─────────────┘   └───────────┘   └───────────┘  └──────────┘

============================================================
KAFKA TOPICS
============================================================

booking.listings
  - Listing create/update/publish
  - Consumers: Elasticsearch indexer
  - Partition by: listing_id

booking.availability
  - Availability updates (price, status)
  - Consumers: Search cache invalidation
  - Partition by: listing_id
  - High volume during bulk updates

booking.reservations
  - Reservation lifecycle events
  - Consumers: Email notifications, analytics, payments
  - Partition by: reservation_id

booking.reviews
  - New reviews submitted
  - Consumers: Rating recalculation, notifications
  - Partition by: listing_id (for rating updates)

booking.messages
  - New messages sent
  - Consumers: Push notifications, email fallback
  - Partition by: conversation_id

============================================================
EVENT SCHEMAS
============================================================

ReservationCreated:
{
  "event_type": "reservation.created",
  "reservation_id": "uuid",
  "listing_id": "uuid",
  "guest_id": "uuid",
  "host_id": "uuid",
  "check_in_date": "2024-06-01",
  "check_out_date": "2024-06-05",
  "total_price": 50000,
  "status": "pending",
  "created_at": "2024-01-15T10:30:00Z"
}

ReservationConfirmed:
{
  "event_type": "reservation.confirmed",
  "reservation_id": "uuid",
  "confirmed_at": "2024-01-15T11:00:00Z",
  "payment_intent_id": "pi_xxx"
}

ReviewSubmitted:
{
  "event_type": "review.submitted",
  "review_id": "uuid",
  "reservation_id": "uuid",
  "listing_id": "uuid",
  "reviewer_id": "uuid",
  "reviewee_id": "uuid",
  "overall_rating": 5,
  "submitted_at": "2024-01-20T15:00:00Z"
}

============================================================
STREAMING JOBS
============================================================

JOB 1: Elasticsearch Sync
  Input: booking.listings
  Processing: Transform to ES document
  Output: Elasticsearch listings index

JOB 2: Rating Calculator
  Input: booking.reviews
  Processing: Calculate new average rating
  Output: Update listing.avg_rating

JOB 3: Notification Router
  Input: booking.reservations, booking.messages
  Processing: Determine notification type and channel
  Output: Email/SMS/Push queues

JOB 4: Analytics Aggregator
  Input: booking.reservations
  Processing: Daily/weekly aggregations
  Output: Analytics data warehouse
```

---

# Part 10: Disaster Recovery

```
============================================================
BOOKING PLATFORM DISASTER RECOVERY
============================================================

CRITICAL REQUIREMENTS:
- Reservations are legally binding contracts
- Payment data must be recoverable
- Double bookings are unacceptable
- RPO: < 5 minutes (reservations are critical)
- RTO: < 1 hour (booking flow must recover)

============================================================
REPLICATION TOPOLOGY
============================================================

                    ┌──────────────────┐
                    │  Primary (Write) │
                    │   us-east-1a     │
                    └────────┬─────────┘
                             │ Synchronous
             ┌───────────────┼───────────────┐
             ▼               ▼               ▼
      ┌────────────┐  ┌────────────┐  ┌────────────┐
      │ Sync Rep   │  │ Sync Rep   │  │ Async Rep  │
      │ us-east-1b │  │ us-east-1c │  │ eu-west-1  │
      │ Read Pool  │  │ Read Pool  │  │ DR Standby │
      └────────────┘  └────────────┘  └────────────┘

Configuration:
  synchronous_commit = remote_apply
  synchronous_standby_names = 'FIRST 2 (replica_1b, replica_1c)'

============================================================
BACKUP STRATEGY
============================================================

CONTINUOUS:
  - WAL archiving to S3 (every completed transaction)
  - Cross-region replication to eu-west-1 S3

DAILY:
  - pg_basebackup at 03:00 UTC
  - Retention: 30 days
  - Stored in S3 Glacier after 7 days

WEEKLY:
  - Full logical backup (pg_dump)
  - For selective table restore
  - Retention: 1 year

============================================================
FAILOVER SCENARIOS
============================================================

SCENARIO 1: Primary Database Failure
  Detection: < 30 seconds (health checks)
  Action: Promote sync replica (us-east-1b)
  RTO: < 2 minutes
  Data Loss: None (synchronous replication)

SCENARIO 2: Full Region Failure (us-east-1)
  Detection: < 1 minute
  Action:
    1. DNS failover to eu-west-1
    2. Promote async replica
    3. Accept possible < 5 min data loss
  RTO: < 15 minutes
  Data Loss: < 5 minutes of transactions

  Post-Recovery:
    - Reconcile any lost reservations via payment provider
    - Send notifications to affected guests/hosts

SCENARIO 3: Elasticsearch Cluster Failure
  Impact: Search degraded, listings still bookable
  Action: Fallback to PostgreSQL-based search
  RTO: Automatic (application handles fallback)

============================================================
RESERVATION INTEGRITY
============================================================

Anti-Double-Booking After Failover:
  1. All reservation creates use database transactions
  2. Synchronous replication ensures no lost writes
  3. On DR failover:
     - Temporarily disable instant book
     - Require re-confirmation of pending reservations
     - Check availability against payment provider records

Reconciliation Script:
  -- Find reservations without payment confirmation
  SELECT r.* FROM reservations r
  WHERE r.created_at > (NOW() - INTERVAL '1 hour')
    AND r.payment_status = 'pending'
    AND NOT EXISTS (
      SELECT 1 FROM stripe_payments p
      WHERE p.reservation_id = r.id
        AND p.status = 'succeeded'
    );

============================================================
TESTING SCHEDULE
============================================================

| Test | Frequency | Target | Notes |
|------|-----------|--------|-------|
| Replica failover | Weekly | < 2 min | Automated |
| DR failover drill | Quarterly | < 30 min | With traffic |
| Backup restore | Monthly | < 4 hours | Random table |
| Search fallback | Monthly | Automatic | Kill ES leader |
| Full system restore | Annually | < 8 hours | From scratch |
```

---

# Part 13: Production Completeness DDL

```sql
-- ============================================================
-- BOOKING: PRODUCTION-READY CROSS-CUTTING CONCERNS
-- ============================================================

-- ===========================================
-- A. AUDIT / CHANGE HISTORY
-- ===========================================

CREATE TABLE entity_change_log (
    id                  BIGSERIAL PRIMARY KEY,
    entity_type         VARCHAR(50) NOT NULL,  -- 'listing', 'reservation', 'pricing'
    entity_id           UUID NOT NULL,
    field_name          VARCHAR(100) NOT NULL,
    old_value           TEXT,
    new_value           TEXT,
    changed_by_id       UUID NOT NULL,
    changed_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    change_source       VARCHAR(50),  -- 'host_app', 'guest_app', 'admin', 'pricing_engine'
    ip_address          INET
) PARTITION BY RANGE (changed_at);

CREATE INDEX idx_ecl_entity ON entity_change_log(entity_type, entity_id);
CREATE INDEX idx_ecl_time ON entity_change_log(changed_at DESC);


-- ===========================================
-- B. ATTACHMENTS / MEDIA STORAGE
-- ===========================================

CREATE TABLE listing_media (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    listing_id          UUID NOT NULL REFERENCES listings(id),
    
    filename            VARCHAR(255) NOT NULL,
    mime_type           VARCHAR(100) NOT NULL,
    file_size_bytes     BIGINT NOT NULL,
    width               INT,
    height              INT,
    
    storage_bucket      VARCHAR(100) NOT NULL,
    storage_key         VARCHAR(500) NOT NULL,
    cdn_url             VARCHAR(500),
    thumbnail_key       VARCHAR(500),
    
    media_type          VARCHAR(20) NOT NULL,  -- 'photo', 'video', 'floor_plan'
    display_order       INT DEFAULT 0,
    caption             VARCHAR(255),
    
    uploaded_by_id      UUID NOT NULL,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    deleted_at          TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_media_listing ON listing_media(listing_id, display_order);


-- ===========================================
-- C. NOTIFICATIONS QUEUE
-- ===========================================

CREATE TABLE notification_queue (
    id                  BIGSERIAL PRIMARY KEY,
    user_id             UUID,
    channel             VARCHAR(20) NOT NULL,  -- 'email', 'push', 'sms'
    recipient           VARCHAR(255) NOT NULL,
    notification_type   VARCHAR(100) NOT NULL,  -- 'booking_confirmed', 'check_in_reminder'
    subject             VARCHAR(255),
    body                TEXT NOT NULL,
    payload             JSONB,
    status              VARCHAR(20) DEFAULT 'pending',
    retry_count         INT DEFAULT 0,
    scheduled_at        TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    sent_at             TIMESTAMP WITH TIME ZONE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
) PARTITION BY RANGE (created_at);

CREATE INDEX idx_notif_status ON notification_queue(status, scheduled_at);


-- ===========================================
-- D. WEBHOOKS / INTEGRATIONS
-- ===========================================

CREATE TABLE webhook_subscriptions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    host_id             UUID REFERENCES hosts(id),
    url                 VARCHAR(500) NOT NULL,
    secret              VARCHAR(255) NOT NULL,
    events              TEXT[] NOT NULL,  -- ['reservation.created', 'review.posted']
    is_active           BOOLEAN DEFAULT TRUE,
    failure_count       INT DEFAULT 0,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE webhook_deliveries (
    id                  BIGSERIAL PRIMARY KEY,
    subscription_id     UUID NOT NULL REFERENCES webhook_subscriptions(id),
    event_type          VARCHAR(100) NOT NULL,
    payload             JSONB NOT NULL,
    response_code       INT,
    status              VARCHAR(20) DEFAULT 'pending',
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
) PARTITION BY RANGE (created_at);


-- ===========================================
-- E. API KEYS / RATE LIMITING
-- ===========================================

CREATE TABLE api_keys (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID,
    key_prefix          VARCHAR(8) NOT NULL,
    key_hash            VARCHAR(64) NOT NULL UNIQUE,
    name                VARCHAR(100) NOT NULL,
    scopes              TEXT[] NOT NULL,
    rate_limit_rpm      INT DEFAULT 1000,
    is_active           BOOLEAN DEFAULT TRUE,
    expires_at          TIMESTAMP WITH TIME ZONE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);


-- ===========================================
-- F. OAUTH / SSO
-- ===========================================

CREATE TABLE oauth_providers (
    id                  SERIAL PRIMARY KEY,
    provider_type       VARCHAR(50) NOT NULL,
    name                VARCHAR(100) NOT NULL,
    client_id           VARCHAR(255) NOT NULL,
    client_secret_enc   BYTEA NOT NULL,
    issuer_url          VARCHAR(500),
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE user_oauth_links (
    id                  BIGSERIAL PRIMARY KEY,
    user_id             UUID NOT NULL,
    provider_id         INT NOT NULL REFERENCES oauth_providers(id),
    external_id         VARCHAR(255) NOT NULL,
    access_token_enc    BYTEA,
    token_expires_at    TIMESTAMP WITH TIME ZONE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT uk_user_provider UNIQUE (user_id, provider_id)
);


-- ===========================================
-- G. USER SESSIONS
-- ===========================================

CREATE TABLE user_sessions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL,
    token_hash          VARCHAR(64) NOT NULL UNIQUE,
    device_type         VARCHAR(50),
    ip_address          INET NOT NULL,
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    expires_at          TIMESTAMP WITH TIME ZONE NOT NULL
);


-- ===========================================
-- H. FEATURE FLAGS
-- ===========================================

CREATE TABLE feature_flags (
    id                  SERIAL PRIMARY KEY,
    name                VARCHAR(100) NOT NULL UNIQUE,
    description         TEXT,
    is_enabled          BOOLEAN DEFAULT FALSE,
    rollout_percentage  INT DEFAULT 0,
    allowed_user_ids    UUID[],
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

---

# Part 14: Operational Excellence & Internals

```
============================================================
BOOKING: DATABASE TUNING & PRODUCTION INTERNALS
============================================================

1. AVAILABILITY CONCURRENCY (DOUBLE BOOKING PREVENTION)
============================================================

THE CHALLENGE:
Two Users view the same Airbnb for same dates. Both click "Book".
Race condition: `SELECT * FROM reservations WHERE date = ...` returns NULL for both.

SOLUTION: EXCLUSION CONSTRAINTS (PostgreSQL)
```sql
ALTER TABLE reservations 
ADD CONSTRAINT no_overlap 
EXCLUDE USING gist (
  listing_id WITH =, 
  tstzrange(check_in, check_out) WITH &&
);
```
Result: The second transaction fails immediately with database constraint violation. No application locking needed.

OPTIMITIC LOCKING (Application Level):
- Used for "Instant Book".
- `UPDATE listings SET version = version + 1 WHERE id = X and version = Y`.

============================================================
2. SEARCH INDEXING LAG (ELASTICSEARCH IS NOT REALTIME)
============================================================

THE PROBLEM:
Host blocks dates on Calendar -> Database Updated.
Elasticsearch indexer runs every 5 seconds.
User searches -> Sees property as "Available" -> Clicks Book -> Fails.
Result: Bad UX ("Ghost Availability").

SOLUTION: "LATE BINDING" CHECK
1. Search Results (Elastic): "Likely Available".
2. Listing Page: Fetch fresh availability from DB (Read Replica).
3. Checkout Flow: "Soft Reserve" availability in DB (30 min hold).

============================================================
3. PAYMENT STATE MACHINE CONSISTENCY
============================================================

STATES:
Pending -> Authorized -> Captured -> Payout_Scheduled -> Paid_Out.

FAILURE MODE: "Captured but not Booked"
- Stripe Charge succeeds.
- Database INSERT reservation fails.

MITIGATION (The "Orphaned Charge" Job):
- Reconciliation Job looks for Stripe Charges without matching Reservation ID.
- Action: Auto-refund within 10 minutes.

IDEMPOTENCY:
- Payment Intent created early in flow.
- Client retries use same `idempotency_key` (hash of booking params).

============================================================
4. OBSERVABILITY (THE "WHAT TO WATCH" DASHBOARD)
============================================================

KEY SLIs:
┌─────────────────────────────────────────────────────────────┐
│  SLI                          │ Target  │ Alert           │
├─────────────────────────────────────────────────────────────┤
│  Booking Success Rate         │ > 99%   │ < 95% = PAGE    │
│  Availability Check Latency   │ < 200ms │ > 500ms = WARN  │
│  Calendar Load Time (p99)     │ < 1s    │ > 3s = WARN     │
│  Double Booking Rate          │ 0       │ > 0 = P0 ISSUE  │
└─────────────────────────────────────────────────────────────┘

INFRASTRUCTURE METRICS:
- `db_lock_waits`: High during "Flash Sales".
- `elasticsearch_indexing_lag`: > 10s implies stale results.

============================================================
5. FAILURE MODE ANALYSIS
============================================================

SCENARIO 1: "THE NYE SURGE" (New Year's Eve)
Symptom: 100x traffic searching for rentals.
Mitigation:
- Degrade Search: Disable map search, show list only.
- Cache Aggressively: Search results for "Paris, Dec 31" cached for 5 mins (instead of 1 min).
- Queue-it: Waiting room for checkout.

SCENARIO 2: HOST ACCOUNT TAKEOVER
Symptom: Hacker changes payout bank account.
Mitigation:
- "Payout Hold": Any bank change triggers 72-hour payout freeze.
- Compliance Check: Verify bank account owner name matches Host KYC name.

SCENARIO 3: CALENDAR SYNC FAILURE (iCal)
Symptom: Host uses Booking.com and Airbnb. iCal sync stuck. Double booking occurs.
Mitigation:
- Poll Frequency: Increase poll rate for High-Velocity hosts.
- "Instant Notification": Push hook instead of polling (where supported).

============================================================
6. FINOPS & COST OPTIMIZATION
============================================================

IMAGE OPTIMIZATION:
- Hosts upload raw 20MB photos.
- Processing Pipeline: Resize to 1920p (Desktop) and 800p (Mobile) WebP. 
- Savings: 80% bandwidth cost reduction.

DATABASE ARCHIVAL:
- Listings that haven't been booked in 2 years.
- Move to `listings_archive` table (cheaper storage, smaller index).
```

---

## 🔗 Related Documents

- [Uber Schema](./uber-schema-design-guide.md) — Similar geo patterns
- [E-commerce Schema](./ecommerce-schema-design-guide.md) — Similar booking/order flow
- [Stripe Schema](./stripe-schema-design-guide.md) — Payment integration
- [Healthcare Schema](./healthcare-schema-design-guide.md) — Similar audit patterns
