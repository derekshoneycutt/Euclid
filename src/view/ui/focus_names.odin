package ui

import viewmodel "model"
import uisemantics "semantics"
import uianimation "animation"
import uilibrary "library"
import uisettings "settings"

// Scenario_Focus_Name maps stable test vocabulary to generation-free identity.
Scenario_Focus_Name :: struct {
    name: string,
    domain: viewmodel.Ui_Node_Domain,
    local_id: u64,
}

SCENARIO_FOCUS_NAMES :: [?]Scenario_Focus_Name{
    {"terminal", .Terminal, 0},
    {"presentation", .Presentation, 0},
    {"context_menu", .Context_Menu, 0},
    {"context_menu_copy", .Context_Menu, 1},
    {"context_menu_secondary", .Context_Menu, 2},
    {"animation_restart", .Animation_Control, uianimation.ANIMATION_REFRESH_BUTTON_ID},
    {"animation_pause", .Animation_Control, uianimation.ANIMATION_PAUSE_BUTTON_ID},
    {"animation_favorite", .Animation_Control, uianimation.ANIMATION_FAVORITE_BUTTON_ID},
    {"accordion_view", .Accordion, u64(viewmodel.Ui_Accordion_Section.View) + 1},
    {"accordion_library", .Accordion,
        u64(viewmodel.Ui_Accordion_Section.Library) + 1},
    {"accordion_save_gif", .Accordion,
        u64(viewmodel.Ui_Accordion_Section.Save_Gif) + 1},
    {"accordion_settings", .Accordion,
        u64(viewmodel.Ui_Accordion_Section.Settings) + 1},
    {"library_search", .Library_Control, uilibrary.LIBRARY_SEARCH_INPUT_ID},
    {"library_tree", .Animation_Tree, uilibrary.TREE_SEMANTIC_LOCAL_ID},
    {"settings_max_dust", .Settings_Control,
        uisettings.SETTINGS_MAX_PARTICLES_SLIDER_PRESS_ID},
}

// semantic_focus_matches_name resolves stable scenario names without exposing IDs.
semantic_focus_matches_name :: proc(
    state: ^viewmodel.Ui_Semantic_Focus_State, name: string) -> bool {
    snapshot := uisemantics.semantic_snapshot(state)
    if snapshot == nil {
        return false
    }
    index := uisemantics.semantic_node_index(snapshot, state^.logical_focus)
    if index < 0 {
        return false
    }
    id := snapshot^.nodes[index].id
    for entry in SCENARIO_FOCUS_NAMES {
        if entry.name == name {
            return id.domain == entry.domain && id.local_id == entry.local_id
        }
    }
    return false
}
