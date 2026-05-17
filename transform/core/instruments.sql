SELECT DISTINCT
    t.isin,
    COALESCE(i.name, t.isin) AS name,
    COALESCE(i.index_membership, '(ohne Idee)') AS category
FROM staging.transactions t
LEFT JOIN staging.isin_info i ON i.isin = t.isin
-- #NO_NULLS isin, name, category
-- #UNIQUE isin
