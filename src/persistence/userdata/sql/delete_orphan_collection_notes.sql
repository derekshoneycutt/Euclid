DELETE FROM user_collection_note
WHERE NOT EXISTS (
    SELECT 1
    FROM user_collection AS collection
    JOIN user_collection_entry AS entry
        ON entry.collection_id = collection.collection_id
    WHERE collection.collection_id = user_collection_note.collection_id
        AND entry.entry_id = user_collection_note.entry_id
        AND collection.system_role IS NULL
        AND entry.entry_kind = 'animation'
        AND entry.animation_id IS NOT NULL
);
