SELECT
    collection.system_role,
    collection.display_name,
    (
        SELECT COUNT(*)
        FROM user_collection_entry AS entry
        WHERE entry.collection_id = collection.collection_id
            AND entry.entry_kind = 'animation'
    ) AS animation_count,
    (
        SELECT COUNT(*)
        FROM user_collection_entry AS entry
        WHERE entry.collection_id = collection.collection_id
            AND entry.entry_kind != 'animation'
    ) AS unsupported_entry_count
FROM user_collection AS collection
WHERE collection.collection_id = ?1;
