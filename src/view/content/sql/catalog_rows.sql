SELECT source_namespace, animation_id, parent_animation_id,
node_kind, sibling_order, catalog_order, implementation_path
FROM catalog_node ORDER BY catalog_order
