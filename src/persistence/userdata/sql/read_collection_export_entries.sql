WITH RECURSIVE tree (
    entry_id,
    sibling_order,
    animation_id,
    custom_name,
    depth,
    order_path
) AS (
    SELECT
        entry.entry_id,
        entry.sibling_order,
        entry.animation_id,
        entry.custom_name,
        0,
        printf('%020d', entry.sibling_order)
    FROM user_collection_entry AS entry
    WHERE entry.collection_id = ?1
        AND entry.parent_entry_id IS NULL
        AND entry.entry_kind = 'animation'
    UNION ALL
    SELECT
        child.entry_id,
        child.sibling_order,
        child.animation_id,
        child.custom_name,
        tree.depth + 1,
        tree.order_path || '/' || printf('%020d', child.sibling_order)
    FROM user_collection_entry AS child
    JOIN tree ON child.parent_entry_id = tree.entry_id
    WHERE child.collection_id = ?1
        AND child.entry_kind = 'animation'
)
SELECT
    tree.depth,
    tree.animation_id,
    tree.custom_name,
    note.note_text,
    note.notes_on_top,
    CASE WHEN note.entry_id IS NULL THEN 0 ELSE 1 END AS has_note
FROM tree
LEFT JOIN user_collection_note AS note
    ON note.collection_id = ?1
    AND note.entry_id = tree.entry_id
ORDER BY tree.order_path;
