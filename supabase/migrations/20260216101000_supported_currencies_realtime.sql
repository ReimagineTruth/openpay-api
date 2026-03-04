-- USD-based FX rates for the app.
-- Product rule: 1 PI = 3.14 USD.

CREATE TABLE IF NOT EXISTS public.supported_currencies (
  iso_code TEXT PRIMARY KEY,
  display_code TEXT NOT NULL UNIQUE,
  display_name TEXT NOT NULL,
  symbol TEXT NOT NULL,
  flag TEXT NOT NULL,
  usd_rate NUMERIC(20, 8) NOT NULL CHECK (usd_rate > 0),
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Normalize and relax iso_code checks so PI (2 letters) is valid.
UPDATE public.supported_currencies
SET iso_code = upper(trim(iso_code))
WHERE iso_code IS NOT NULL;

ALTER TABLE public.supported_currencies
DROP CONSTRAINT IF EXISTS supported_currencies_iso_code_check;

DO $$
DECLARE
  v_constraint_name TEXT;
BEGIN
  FOR v_constraint_name IN
    SELECT conname
    FROM pg_constraint
    WHERE conrelid = 'public.supported_currencies'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%iso_code%'
  LOOP
    EXECUTE format(
      'ALTER TABLE public.supported_currencies DROP CONSTRAINT IF EXISTS %I',
      v_constraint_name
    );
  END LOOP;
END $$;

ALTER TABLE public.supported_currencies
ADD CONSTRAINT supported_currencies_iso_code_check
CHECK (iso_code ~ '^[A-Z]{2,3}$');

ALTER TABLE public.supported_currencies ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'supported_currencies'
      AND policyname = 'Anyone can read supported currencies'
  ) THEN
    CREATE POLICY "Anyone can read supported currencies"
      ON public.supported_currencies
      FOR SELECT
      USING (true);
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.set_supported_currencies_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_supported_currencies_updated_at ON public.supported_currencies;
CREATE TRIGGER trg_supported_currencies_updated_at
BEFORE UPDATE ON public.supported_currencies
FOR EACH ROW
EXECUTE FUNCTION public.set_supported_currencies_updated_at();

INSERT INTO public.supported_currencies (
  iso_code, display_code, display_name, symbol, flag, usd_rate, is_active
)
SELECT
  v.code,
  v.code,
  v.code,
  v.code,
  '🏳️',
  CASE
    WHEN v.code = 'PI' THEN 3.14
    WHEN v.code = 'USD' THEN 1
    ELSE 1
  END,
  true
FROM (
  VALUES
  ('PI'), ('USD'), ('CAD'), ('MXN'), ('BRL'), ('ARS'), ('CLP'), ('COP'), ('PEN'), ('BOB'),
  ('UYU'), ('PYG'), ('VES'), ('GTQ'), ('HNL'), ('NIO'), ('CRC'), ('PAB'), ('DOP'), ('CUP'),
  ('JMD'), ('TTD'), ('BBD'), ('BSD'), ('XCD'),
  ('EUR'), ('GBP'), ('CHF'), ('SEK'), ('NOK'), ('DKK'), ('PLN'), ('CZK'), ('HUF'), ('RON'),
  ('BGN'), ('RSD'), ('MKD'), ('ALL'), ('ISK'), ('UAH'), ('BYN'), ('RUB'), ('TRY'), ('BAM'), ('MDL'),
  ('JPY'), ('CNY'), ('KRW'), ('INR'), ('PKR'), ('BDT'), ('LKR'), ('NPR'), ('IDR'), ('MYR'),
  ('THB'), ('PHP'), ('SGD'), ('VND'), ('KHR'), ('LAK'), ('MMK'), ('BND'), ('HKD'), ('MOP'),
  ('TWD'), ('MNT'), ('KZT'), ('UZS'), ('TJS'), ('TMT'), ('KGS'), ('IRR'), ('IQD'), ('SAR'),
  ('AED'), ('QAR'), ('KWD'), ('OMR'), ('BHD'), ('ILS'), ('JOD'), ('LBP'), ('SYP'), ('YER'), ('AFN'),
  ('ZAR'), ('EGP'), ('NGN'), ('KES'), ('TZS'), ('UGX'), ('ETB'), ('GHS'), ('ZMW'), ('MWK'),
  ('MZN'), ('BWP'), ('NAD'), ('SZL'), ('LSL'), ('AOA'), ('CDF'), ('RWF'), ('BIF'), ('DJF'),
  ('SOS'), ('SDG'), ('SSP'), ('DZD'), ('MAD'), ('TND'), ('LYD'), ('XOF'), ('XAF'), ('MUR'), ('SCR'),
  ('AUD'), ('NZD'), ('PGK'), ('FJD'), ('SBD'), ('VUV'), ('WST'), ('TOP')
  , ('AMD'), ('AZN'), ('ERN'), ('GMD'), ('GNF'), ('HTG'), ('KMF'), ('KYD'), ('MGA'), ('MRU'),
  ('MVR'), ('SLL'), ('SRD'), ('STN'), ('SVC')
) AS v(code)
ON CONFLICT (iso_code) DO UPDATE
SET
  is_active = true,
  updated_at = now();

-- Apply fixed USD rates (1 PI = 3.14 USD).
UPDATE public.supported_currencies
SET usd_rate = CASE iso_code
  WHEN 'PI' THEN 3.14
  WHEN 'USD' THEN 1
  WHEN 'EUR' THEN 0.8429
  WHEN 'GBP' THEN 0.7344
  WHEN 'AUD' THEN 1.428
  WHEN 'CAD' THEN 1.362
  WHEN 'JPY' THEN 155.926
  WHEN 'CNY' THEN 6.901
  WHEN 'CHF' THEN 0.7786
  WHEN 'SGD' THEN 1.271
  WHEN 'HKD' THEN 7.816
  WHEN 'INR' THEN 90.599
  WHEN 'BRL' THEN 5.5745
  WHEN 'MXN' THEN 17.232
  WHEN 'ZAR' THEN 15.961
  WHEN 'TRY' THEN 43.645
  WHEN 'PLN' THEN 3.554
  WHEN 'RON' THEN 4.292
  WHEN 'CZK' THEN 20.443
  WHEN 'NOK' THEN 9.545
  WHEN 'DKK' THEN 6.298
  WHEN 'SEK' THEN 8.931
  WHEN 'AED' THEN 3.6725
  WHEN 'SAR' THEN 3.75
  WHEN 'QAR' THEN 3.641
  WHEN 'KWD' THEN 0.3066
  WHEN 'BHD' THEN 0.376992
  WHEN 'OMR' THEN 0.3845
  WHEN 'JOD' THEN 0.709
  WHEN 'NGN' THEN 1352
  WHEN 'KES' THEN 129
  WHEN 'ETB' THEN 155.05
  WHEN 'GHS' THEN 11.005
  WHEN 'MAD' THEN 9.139
  WHEN 'RWF' THEN 1453
  WHEN 'XOF' THEN 552.915
  WHEN 'XAF' THEN 552.915
  WHEN 'ARS' THEN 1482.94905
  WHEN 'COP' THEN 3670
  WHEN 'PEN' THEN 3.355
  WHEN 'BOB' THEN 6.9269
  WHEN 'PYG' THEN 6586
  WHEN 'UYU' THEN 38.557
  WHEN 'DOP' THEN 62.625
  WHEN 'CRC' THEN 495.723
  WHEN 'GTQ' THEN 7.672
  WHEN 'NIO' THEN 36.715
  WHEN 'BSD' THEN 1
  WHEN 'BBD' THEN 2
  WHEN 'TTD' THEN 6.776
  WHEN 'CUP' THEN 25.75
  WHEN 'JMD' THEN 156.252
  WHEN 'PHP' THEN 58.074
  WHEN 'THB' THEN 31.082
  WHEN 'VND' THEN 25961
  WHEN 'IDR' THEN 16817
  WHEN 'PKR' THEN 279.6
  WHEN 'BDT' THEN 122.205858
  WHEN 'LKR' THEN 309.457
  WHEN 'NPR' THEN 145.049
  WHEN 'KHR' THEN 4022
  WHEN 'LAK' THEN 21445
  WHEN 'MMK' THEN 2100
  WHEN 'PGK' THEN 4.299
  WHEN 'MOP' THEN 8.055
  WHEN 'AFN' THEN 66.207039
  WHEN 'ALL' THEN 83.2
  WHEN 'AMD' THEN 381.473652
  WHEN 'AZN' THEN 1.7
  WHEN 'BAM' THEN 1.683408
  WHEN 'BIF' THEN 2982.243336
  WHEN 'BWP' THEN 13.115
  WHEN 'CDF' THEN 2240
  WHEN 'DJF' THEN 177.5
  WHEN 'ERN' THEN 15
  WHEN 'FJD' THEN 2.191
  WHEN 'GMD' THEN 73.5
  WHEN 'GNF' THEN 8775
  WHEN 'HTG' THEN 130.977
  WHEN 'KMF' THEN 416
  WHEN 'KYD' THEN 0.8336
  WHEN 'MGA' THEN 4430
  WHEN 'MRU' THEN 39.9
  WHEN 'MVR' THEN 15.46
  WHEN 'MWK' THEN 1737
  WHEN 'MZN' THEN 63.91
  WHEN 'NAD' THEN 15.96
  WHEN 'RSD' THEN 98.934
  WHEN 'SBD' THEN 8.048
  WHEN 'SLL' THEN 20970
  WHEN 'SOS' THEN 571.5
  WHEN 'SRD' THEN 37.779
  WHEN 'SSP' THEN 130.26
  WHEN 'STN' THEN 20.95
  WHEN 'SVC' THEN 8.752
  WHEN 'TJS' THEN 9.418
  WHEN 'TMT' THEN 3.51
  WHEN 'TND' THEN 2.835
  WHEN 'TOP' THEN 2.408
  WHEN 'TZS' THEN 2600
  WHEN 'VUV' THEN 119.995
  ELSE usd_rate
END,
updated_at = now()
WHERE iso_code IN (
  'PI','USD','EUR','GBP','AUD','CAD','JPY','CNY','CHF','SGD','HKD','INR','BRL','MXN','ZAR','TRY','PLN','RON','CZK',
  'NOK','DKK','SEK','AED','SAR','QAR','KWD','BHD','OMR','JOD','NGN','KES','ETB','GHS','MAD','RWF','XOF','XAF','ARS',
  'COP','PEN','BOB','PYG','UYU','DOP','CRC','GTQ','NIO','BSD','BBD','TTD','CUP','JMD','PHP','THB','VND','IDR','PKR',
  'BDT','LKR','NPR','KHR','LAK','MMK','PGK','MOP','AFN','ALL','AMD','AZN','BAM','BIF','BWP','CDF','DJF','ERN','FJD',
  'GMD','GNF','HTG','KMF','KYD','MGA','MRU','MVR','MWK','MZN','NAD','RSD','SBD','SLL','SOS','SRD','SSP','STN','SVC',
  'TJS','TMT','TND','TOP','TZS','VUV'
);

CREATE OR REPLACE FUNCTION public.apply_usd_exchange_rates(p_rates JSONB)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_updated_count INTEGER := 0;
  v_code TEXT;
  v_rate_text TEXT;
  v_rate NUMERIC;
BEGIN
  IF jsonb_typeof(p_rates) <> 'object' THEN
    RAISE EXCEPTION 'p_rates must be a JSON object keyed by currency code';
  END IF;

  -- Hard business rule.
  UPDATE public.supported_currencies
  SET usd_rate = CASE WHEN iso_code = 'PI' THEN 3.14 ELSE 1 END,
      updated_at = now()
  WHERE iso_code IN ('PI', 'USD');

  FOR v_code, v_rate_text IN
    SELECT key, value
    FROM jsonb_each_text(p_rates)
  LOOP
    v_code := upper(v_code);
    IF v_code IN ('PI', 'USD') THEN
      CONTINUE;
    END IF;

    BEGIN
      v_rate := v_rate_text::numeric;
    EXCEPTION WHEN OTHERS THEN
      CONTINUE;
    END;

    IF v_rate IS NULL OR v_rate <= 0 THEN
      CONTINUE;
    END IF;

    UPDATE public.supported_currencies
    SET usd_rate = v_rate, updated_at = now()
    WHERE iso_code = v_code;

    IF FOUND THEN
      v_updated_count := v_updated_count + 1;
    END IF;
  END LOOP;

  RETURN v_updated_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.apply_usd_exchange_rates(JSONB) TO service_role;
