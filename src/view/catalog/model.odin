package catalog

import model "../../core/catalog"

SEARCH_QUERY_BYTE_CAPACITY :: model.SEARCH_QUERY_BYTE_CAPACITY
SEARCH_QUERY_ITEM_CAPACITY :: model.SEARCH_QUERY_ITEM_CAPACITY
SEARCH_QUERY_ITEM_BYTE_CAPACITY :: model.SEARCH_QUERY_ITEM_BYTE_CAPACITY
SEARCH_MATCH_BYTE_CAPACITY :: model.SEARCH_MATCH_BYTE_CAPACITY
SEARCH_RESULT_WINDOW_CAPACITY :: model.SEARCH_RESULT_WINDOW_CAPACITY
SEARCH_DOCUMENT_ID_BYTE_COUNT :: model.SEARCH_DOCUMENT_ID_BYTE_COUNT
CATALOG_RECORD_CAPACITY :: model.CATALOG_RECORD_CAPACITY
CATALOG_NAME_BYTE_CAPACITY :: model.CATALOG_NAME_BYTE_CAPACITY
CATALOG_PATH_BYTE_CAPACITY :: model.CATALOG_PATH_BYTE_CAPACITY
CATALOG_DATABASE_PATH_CAPACITY :: model.CATALOG_DATABASE_PATH_CAPACITY
SEARCH_FINGERPRINT_BYTE_COUNT :: model.SEARCH_FINGERPRINT_BYTE_COUNT

Catalog_Node_Kind :: model.Catalog_Node_Kind
Catalog_Record :: model.Catalog_Record
Catalog_Snapshot :: model.Catalog_Snapshot
Search_Source_Namespace :: model.Search_Source_Namespace
Search_Document_Id :: model.Search_Document_Id
Search_Document_Key :: model.Search_Document_Key
Search_Query_Request :: model.Search_Query_Request
Search_Query_Status :: model.Search_Query_Status
Search_Query_Result :: model.Search_Query_Result
Catalog_Control_Result :: model.Catalog_Control_Result
Search_Worker_Request_Kind :: model.Search_Worker_Request_Kind
Search_Worker_Request :: model.Search_Worker_Request
Search_Result_Acceptance :: model.Search_Result_Acceptance
Catalog_Candidate_State :: model.Catalog_Candidate_State
Catalog_Service :: model.Catalog_Service

// Validate both asynchronous generations before display-owned state replacement.
search_result_acceptance :: proc(
    result: ^Search_Query_Result, query_generation,
    index_generation: u64) -> Search_Result_Acceptance {
    if result == nil || result.status != .Ready {
        return .Not_Ready
    }
    if result.generation != query_generation {
        return .Stale_Query_Generation
    }
    if result.index_generation != index_generation {
        return .Stale_Index_Generation
    }
    return .Accepted
}