set(SOURCES
)

source_group(TREE "${CMAKE_CURRENT_SOURCE_DIR}" PREFIX "Source Files" FILES ${SOURCES})
target_sources(scalable_ccd PRIVATE ${SOURCES})

# ==============================================================================
# Subfolders
# ==============================================================================
# add_subdirectory(broad_phase)
# add_subdirectory(narrow_phase)
# add_subdirectory(utils)