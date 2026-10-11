CREATE TABLE user_collection (
    collection_id BLOB PRIMARY KEY NOT NULL
        CHECK (length(collection_id) = 16),
    system_role TEXT UNIQUE
        CHECK (system_role IS NULL OR system_role = 'favorites'),
    display_name TEXT,
    collection_order INTEGER NOT NULL CHECK (collection_order >= 0),
    is_read_only INTEGER NOT NULL DEFAULT 0
        CHECK (is_read_only IN (0, 1)),
    CHECK (
        (system_role IS NULL AND display_name IS NOT NULL
            AND length(CAST(display_name AS BLOB)) BETWEEN 1 AND 256
            AND instr(display_name, char(0)) = 0)
        OR (system_role IS NOT NULL AND system_role = 'favorites'
            AND display_name IS NULL)
    ),
    CHECK (system_role IS NOT 'favorites' OR is_read_only = 0)
) STRICT, WITHOUT ROWID;

CREATE TABLE user_collection_entry (
    entry_id BLOB PRIMARY KEY NOT NULL CHECK (length(entry_id) = 16),
    collection_id BLOB NOT NULL CHECK (length(collection_id) = 16),
    parent_entry_id BLOB
        CHECK (parent_entry_id IS NULL OR length(parent_entry_id) = 16),
    sibling_order INTEGER NOT NULL CHECK (sibling_order >= 0),
    entry_kind TEXT NOT NULL CHECK (entry_kind IN ('animation', 'group')),
    animation_id BLOB
        CHECK (animation_id IS NULL OR length(animation_id) = 16),
    UNIQUE (collection_id, entry_id),
    FOREIGN KEY (collection_id) REFERENCES user_collection(collection_id),
    FOREIGN KEY (collection_id, parent_entry_id)
        REFERENCES user_collection_entry(collection_id, entry_id),
    CHECK (parent_entry_id IS NULL OR parent_entry_id <> entry_id),
    CHECK (
        (entry_kind = 'animation' AND animation_id IS NOT NULL)
        OR (entry_kind = 'group' AND animation_id IS NULL)
    )
) STRICT, WITHOUT ROWID;

CREATE UNIQUE INDEX user_collection_root_order
    ON user_collection_entry(collection_id, sibling_order)
    WHERE parent_entry_id IS NULL;

CREATE UNIQUE INDEX user_collection_child_order
    ON user_collection_entry(collection_id, parent_entry_id, sibling_order)
    WHERE parent_entry_id IS NOT NULL;

CREATE INDEX user_collection_membership
    ON user_collection_entry(collection_id, animation_id)
    WHERE animation_id IS NOT NULL;

INSERT INTO user_collection (
    collection_id, system_role, display_name, collection_order, is_read_only
) VALUES (
    X'4555434C494400008000000000000001', 'favorites', NULL, 0, 0
);
